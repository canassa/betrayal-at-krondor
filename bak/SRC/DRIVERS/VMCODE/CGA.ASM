; ============================================================================
; Vmcode.OVL.CGA -- CGA video driver chunk.
;
; The chunk is one of eight interchangeable graphics drivers in Vmcode.ovl.
; KRONDOR.EXE loads it via the RES-archive loader, runs its init prologue
; once, then snapshots its 50-slot vtable template into the host's
; g_renderer_vtable @ 39ae:2ac6 for ordinary far-call dispatch.
;
; Content: 41 functions, the 50-slot vtable template, the 19-entry
; callback-table mirror, the mask LUTs, the bit-reverse XLAT LUT, and the
; scratch-global blocks.
; ============================================================================

; ----------------------------------------------------------------------------
; What this driver is
;
; A "video driver" in Betrayal at Krondor is a small piece of position-
; independent code that the engine loads from the Vmcode.OVL resource
; archive at startup. Different graphics cards need different code, so
; the game ships one driver per supported adapter (CGA, EGA, Tandy,
; Hercules, MCGA, VGA, ...) and picks the right one at runtime based
; on the user's "video setup" choice.
;
; This file is the CGA driver. The engine communicates with it through
; a vtable of far function pointers (see "How the engine dispatches"
; below): 50 slots, each slot a different request like "draw a line",
; "blit a sprite", "set the palette". When a slot is invoked, this
; code translates that high-level request into the specific byte
; patterns the CGA hardware expects in its framebuffer.
;
; Roughly half this file is the dispatch / mode-set / palette / memory-
; management plumbing; the other half is pixel-pushing loops written
; for tight 8086-era cycle budgets (4-pixel-per-byte packing, manual
; partial-byte masks, hand-unrolled inner loops, bank-interleaved
; framebuffer arithmetic).
; ----------------------------------------------------------------------------

; ----------------------------------------------------------------------------
; About the CGA hardware
;
; CGA (IBM Color Graphics Adapter, 1981) is the oldest IBM PC graphics
; card. In its 320x200 4-colour mode -- which is what this driver
; uses -- it presents the CPU with:
;
;   - A 16 KiB framebuffer mapped at physical 0xB8000 (real-mode
;     segment 0xB800, offset 0..0x3FFF). Two displays' worth of
;     framebuffer space (16 KiB each) doesn't quite fit in that
;     window, so this driver also allocates a back-buffer in normal
;     DOS RAM and uses cga_present_rect / cga_capture_rect to ferry
;     pixels between back- and front-buffer.
;
;   - A "mode-control" port at 0x3D8 (write-only; we OR bit 2 in
;     cga_palette_set to engage the undocumented "third palette"
;     -- on an RGBI monitor in mode 4 this swaps the visible palette
;     to red/cyan/white. See IBM CGA TR p. 19-20).
;   - A "status" port at 0x3DA (read-only; bit 3 = vertical retrace
;     active; we poll this in cga_setpal_and_vsync to align palette
;     changes with vblank for tear-free updates. NOTE: bit 0 of the
;     same port is "any retrace H or V" -- the *narrower* vertical-
;     only signal is bit 3, per IBM CGA TR p. 21).
;
; Pixel packing in mode 4: each byte holds 4 pixels, MSB-first.
;
;       bit 7 6 | 5 4 | 3 2 | 1 0
;       pixel 0 |  1  |  2  |  3
;
; Each 2-bit field selects one of 4 colours from the active CGA
; palette. The four colours are themselves fixed at hardware level
; (palette 0 = bg/green/red/brown, palette 1 = bg/cyan/magenta/
; white) with a programmable background and a palette-select bit.
; The "high-intensity" variants (light-green/light-red/yellow, or
; light-cyan/light-magenta/bright-white) are selected by an
; orthogonal "intensity" bit. Palette is selected via INT 10h
; AH=0Bh BH=01h; background colour via INT 10h AH=0Bh BH=00h.
; Source: IBM Options/Adapters Vol.1 (CGA Tech Ref) p. 11 / 18,
; cross-confirmed by vgadoc/CGA.TXT.
;
; Bank-interleaved scanlines (the killer detail):
;
;   The CGA's CRTC (6845) is configured for 100 character rows of
;   2 scanlines each (R6=100, R9=1, per IBM CGA TR p. 17). The CGA's
;   external graphics logic then remaps the row-counter's LSB to
;   address line A13 of display RAM -- so the 6845 thinks it's
;   walking a 100-row x 80-byte framebuffer, while the CPU actually
;   sees two interleaved banks:
;
;       even rows (0, 2, 4, ..., 198) -> base 0x0000, +80 per row
;       odd  rows (1, 3, 5, ..., 199) -> base 0x2000, +80 per row
;
;   So consecutive vertical pixels are NOT contiguous in memory --
;   row N+1 is 0x2000 - 80*(N/2) bytes away from row N. Every line/
;   rect/sprite blitter in this file deals with this via two
;   mechanisms: (a) a precomputed 200-entry scanline-offset LUT
;   built in cga_init at scratch:[0x6F2], and (b) a runtime
;   `XOR DI, 0x2000` followed by `ADD DI, 0x50` when DI's bank bit
;   has just cleared (i.e. when stepping from an odd-bank row to the
;   next even-bank row, which is +80 bytes away in offset).
;
; Stride is 80 bytes per row in both mode 4 (320 px * 2 bpp / 8)
; and mode 6 (640 px * 1 bpp / 8). Each bank holds 100 rows *
; 80 bytes = 8000 bytes, leaving a 192-byte hole at +0x1F40..+0x1FFF
; the 6845 never addresses (see IBM CGA TR p. 10 layout). Total used: 16000 bytes; total mapped
; window: 16 KiB.
;
; For the full register-level reference see the IBM CGA TR
; (IBM_Options_Adapters_Vol1_Apr84.pdf).
; ----------------------------------------------------------------------------

; ----------------------------------------------------------------------------
; How the engine dispatches into this chunk
;
; Vmcode.OVL is a flat archive of driver chunks; one chunk per
; supported adapter. The host engine:
;
;   1. Loads the selected chunk into a freshly-allocated segment.
;   2. Calls the chunk's `_start` (cga_init) as a far function,
;      passing two args on the stack: a paragraph count for the
;      driver's private working segment, and a far pointer to the
;      host's "service callback" table (PrintF-style errno, file
;      I/O, resource loading -- the things this code needs from
;      the host).
;   3. cga_init copies the 19 host callbacks into chunk-local
;      mirror slots at CS:0x02A0, configures the framebuffer,
;      then returns DX:SI = (CS, 0x0200) -- a far pointer to the
;      chunk's vtable template at g_apfnCgaVtable.
;   4. The host stamps the chunk's load segment into every
;      segment-half of that template (50 slots * 4 bytes = 200
;      bytes) and copies the result into a global renderer
;      vtable at 39ae:2ac6 in host RAM.
;   5. Every subsequent rendering call from the game is a far
;      CALL through that vtable -- never a direct CALL into this
;      file. The CGA driver thus only sees a stream of slot
;      invocations after init.
;
; Slot calling convention: most slots are __cdecl16far (push args
; right-to-left, far call, caller cleans the stack). A handful of
; inner functions (cga_fill_pixel_run_dithered,
; cga_fill_spans_dithered, cga_blit_glyph_row8_dithered,
; cga_blit_stretched_row) instead take register-passed args because
; they're called from within this chunk for speed. Each function's
; plate comment lists the actual arg convention.
; ----------------------------------------------------------------------------

; ----------------------------------------------------------------------------
; How to read this source
;
; - TASM numeric-literal parser: hex literals must begin with a
;   digit (write `0AH`, not `AH` -- `AH` parses as a register).
;   `H` suffix marks hex, `B` suffix binary, no suffix is decimal.
;
; - This is a single-segment chunk (`.MODEL TINY`, `.CODE` only).
;   Code, data tables, and chunk-local globals all share the same
;   segment. Chunk-local globals (g_wCgaChunkDataSeg @ 0x00DE etc.)
;   live in dedicated .CODE-segment slots accessed via `cs:` overrides.
;   Separately, the host pre-populates a SCRATCH-DS state block (clip
;   rect, draw colours, framebuffer segments) at fixed scratch-DS
;   offsets that every slot reads via `ds:` after loading scratch DS
;   from cs:[0DEH] -- see the scratch-DS EQUs in the next block.
;
; - Memory accesses use one of three segments:
;     CS:  -- the chunk itself (vtable, mask LUTs, chunk-local globals
;             at 0x00DE.., self-patched scratch words like
;             g_wCgaGlyphRowKeepMask, sprite-clip state at 0x1425..).
;     DS:  -- usually the chunk's "scratch DS", a private working
;             segment allocated `paragraph_count` paragraphs past the
;             caller's DS (set up at cga_init step 2). Every function
;             that needs the scratch reloads DS from cs:[0DEH]
;             (g_wCgaChunkDataSeg) on entry and restores caller DS
;             before returning.
;     ES:  -- usually the framebuffer (B800 or back-buffer); the
;             function plates specify which.
;
; - Local labels inside a function are prefixed with a short
;   nickname for the enclosing function (e.g. `cga_fpr_*` inside
;   cga_fill_pixel_run_dithered, `cga_srn_*` inside
;   cga_sprite_row_noflip). Avoids collisions across functions
;   without anonymous `@@:` labels.
;
; - "Self-patched" / "runtime-patched" markers in this file refer to
;   CS-relative words that one slot writes mid-execution and another
;   slot (or the same slot's inner loop) reads later -- e.g.
;   g_wCgaGlyphRowKeepMask at CS:0x0C99 is patched each call to
;   cga_blit_glyph_row8_dithered from the pixel-replicate LUT. This is
;   not the same as the scratch-DS state block.
; ----------------------------------------------------------------------------

                .8086
                .MODEL  TINY
                .CODE
                ORG     0
                ASSUME  ds:NOTHING, es:NOTHING

; Shared engine graphics-context STRUC (host scratch-DS layout). The driver
; reads/writes engine video-state through ds:[GfxContext.<field>] offsets.
                INCLUDE gfxctx.inc

; ----------------------------------------------------------------------------
; Scratch-DS state-block offsets. These are NOT inside cga_init's code;
; they are offsets into the chunk's private scratch segment (the one
; whose paragraph is stored in cs:[0DEH], see g_wCgaChunkDataSeg below).
; The host pre-populates clip-rect / draw-colour bytes here before
; dispatching a vtable slot; the driver reads them via `ds:[NN]` after
; loading DS from cs:[0DEH] in each slot prologue. cga_init itself
; writes some of these (the back-buffer / framebuffer segments at
; 0x10..0x18) during the alloc phase.
;
; The names below are conventions used throughout this file -- there
; is no symbol table for the scratch zone; every consumer hard-codes
; the literal offset (e.g. `MOV ES, ds:[0018H]`). These EQUs are
; documentation-only and not used by any instruction (TASM would emit
; the same bytes whether the EQU is present or not).
; ----------------------------------------------------------------------------
g_bCgaClipEnabled       equ 0003H        ; uchar  -- clip-rect enabled flag
g_nCgaClipLeft          equ 0004H        ; int    -- clip-rect left
g_nCgaClipRight         equ 0006H        ; int    -- clip-rect right
g_nCgaClipTop           equ 0008H        ; int    -- clip-rect top
g_nCgaClipBottom        equ 000AH        ; int    -- clip-rect bottom
g_bCgaSpanDrawColor     equ 000DH        ; uchar  -- span/fill colour
g_bCgaLineDrawColor     equ 000EH        ; uchar  -- line colour
; Note: cga_init writes a back-buffer segment to ds:[0x12] and 0xB800 to
; ds:[0x14] on the DOS-alloc-only path, but writes them in the OPPOSITE
; order (probe seg to ds:[0x14], B800 to ds:[0x12]) on the aperture path.
; The runtime reads only ds:[0x12]/[0x14] in cga_capture_rect and only
; ds:[0x16]/[0x18] elsewhere; ds:[0x16]/[0x18] are never written by this
; chunk and therefore must be populated by the host before any non-init
; slot is invoked. Treat these names as best-effort labels, not contracts.
g_wCgaBackBufferSeg     equ 0014H        ; ushort -- see note above
g_wCgaBlitSrcSeg        equ 0016H        ; ushort -- host-supplied; never written here
g_wCgaFramebufferSeg    equ 0018H        ; ushort -- host-supplied; never written here

; ----------------------------------------------------------------------------
; Forward-reference CALLs into same-segment FAR procs (cga_image_pack_*,
; cga_blit_sprite_clipped, cga_pack_scanline_via_palette_lut) use the
; `PUSH CS / CALL NEAR PTR <sym>` idiom: a 1-byte PUSH CS plus a 3-byte
; E8 disp16 simulates a 9A seg:off FAR call while keeping the encoding
; compact. `NEAR PTR` is required so TASM doesn't promote the CALL to
; the 5-byte FAR form (PROC FAR's default).
; ----------------------------------------------------------------------------

; ============================================================================
; cga_init -- chunk initialiser (PROC FAR, called via the host's video_init).
; chunk:0x0000..0x00DD
;
; CALLER ABI (host-side far call):
;   [BP+0x06]  ushort  backbuffer_paragraphs  (= 0x400 = 16 KiB / 16)
;   [BP+0x08]  ushort  host_callbacks_off     (off of host service-callback table)
;   [BP+0x0a]  ushort  host_callbacks_seg     (seg of host service-callback table)
;
; INIT SEQUENCE:
;   1. [0x00..0x16]  Copy 0x26 words (76 bytes = 19 far ptrs) from
;      DS:SI = host_callbacks_seg:host_callbacks_off into the chunk-
;      local mirror at CS:0x02A0 (g_apfnHostCallbacks). Other chunk
;      slots later CALLF [0x02A0+N] through this copy.
;   2. [0x19..0x33]  Save the requested paragraph count to
;      g_wCgaChunkDataBaseOff (misnamed; it stores the count). Right-
;      shift by 4, add caller DS, store as g_wCgaChunkDataSeg. The
;      private scratch DS is positioned paragraph_count/16 paragraphs
;      past the caller's DS.
;   3. [0x34..0x47]  If mode-width word at scratch:[0x6EA] == 0x280
;      (640 px requested), set g_bCgaPriorMode640Flag := 1 and clamp
;      the width down to 0x140 (320 px) because CGA mode 4 is 320px.
;      The remembered flag drives cga_post_mode_change_mouse_refresh
;      to expand the mouse coordinate space back to 640x200 later.
;   4. [0x48..0x4D]  INT 10h AX=0004h -- switch to BIOS mode 4 (CGA
;      320x200, 4 colours). On a stock IBM CGA, the BIOS programs
;      3D8h=0Ah, 3D9h=30h (palette 1 = cyan/magenta/white, intensified),
;      reprograms 6845 R0..R11 from its mode-4 table (R6=64h=100 rows
;      of 2 scanlines each = 200 visible lines), and zero-fills the
;      whole B800 framebuffer. Source: IBM CGA TR p. 17 / 20.
;      Stash 4 in scratch:[0x21] (active-mode byte).
;   5. [0x52..0x6C]  Branch on scratch:[0x1C]:
;        != 1  -> jump straight to step 6 (the simple DOS AH=48h
;                 alloc path).
;        == 1  -> try cga_dos_alloc_far(0x400) to see if there's room
;                 at the top of conventional memory; on AL!=0 call
;                 cga_alloc_backbuffer_pages to set up B800-aperture
;                 page pair. If EITHER backbuffer-page segment came
;                 back as something other than 0xB800 (i.e. the page
;                 search found a usable aperture), jump ahead to
;                 step 7 (zero+third-alloc) skipping step 6. Only
;                 when both probes returned 0xB800 (i.e. no usable
;                 page) does the code fall through to the DOS-alloc
;                 path.
;   6. [0x7D..0x9C]  cga_init_dos_alloc: one INT 21h/AH=48h alloc of
;      0x400 paras into scratch:[0x12]; then scratch:[0x14] := 0xB800.
;      Only reached when both backbuffer-page probes returned 0xB800
;      (no usable aperture); the JNZ from step 5 skips this block when
;      the aperture path already populated the pages. JC -> exit with
;      AL = DOS error code (non-1, treated as failure by step 9).
;   7. [0x9D..0xC0]  cga_init_alloc_back_zero_all: another INT 21h/AH=48h
;      alloc into scratch:[0x10] (the back buffer), then 3x REP STOSW
;      to zero 0x2000 words (16 KiB) each into scratch:[0x10], [0x12],
;      [0x14]. JC after the alloc -> exit with AL = DOS error code.
;   8. [0xBB..0xCF]  Build the 200-row CGA bank-interleaved scanline
;      offset table at scratch:[0x6F2]:
;          row 2k    -> 80*k                  (bank 0, base 0x0000)
;          row 2k+1  -> 80*k + 0x2000         (bank 1, base 0x2000)
;   9. [0xD0..0xDD]  On success AL := 1; DX := CS; SI := 0x0200; the
;      scratch:[0x1D] byte gets AL (driver-installed flag in the
;      scratch-DS state block). On the early-exit failure paths AL
;      is whatever the failing branch left it at -- either 0 (from
;      the cga_dos_alloc_far AL==0 path) or a DOS error code (from
;      a JC after INT 21h AH=48h); both result in a non-1 flag.
;
; RETURN:
;   AL    -- 1 on success, 0 on alloc failure.
;   DX:SI -- CS:0x0200, far pointer to g_apfnCgaVtable.
; ============================================================================
_start          LABEL   BYTE
cga_init        PROC    FAR
                PUSH    BP
                MOV     BP, SP
                PUSH    DS
                PUSH    SI
                PUSH    DI
                MOV     DI, 02A0H               ; <- g_apfnHostCallbacks
                PUSH    CS
                POP     ES
                MOV     SI, [BP+8]              ; arg1.off
                MOV     DS, [BP+0AH]            ; arg1.seg
                MOV     CX, 0026H               ; 38 words = 76 bytes
                REP     MOVSW
                POP     DI
                POP     SI
                POP     DS
                MOV     AX, [BP+6]              ; arg0: paragraph count

                MOV     cs:[0E0H], AX
                SHR     AX, 1
                SHR     AX, 1
                SHR     AX, 1
                SHR     AX, 1                   ; AX /= 16
                PUSH    DS
                PUSH    DI
                MOV     BX, DS
                ADD     AX, BX
                MOV     cs:[0DEH], AX
                MOV     DS, AX                  ; DS = scratch segment

                CMP     WORD PTR ds:[GfxContext.wScreen_width], 0280H
                JNZ     SHORT cga_init_mode_set
                MOV     BYTE PTR cs:[0E8H], 1
                MOV     WORD PTR ds:[GfxContext.wScreen_width], 0140H

cga_init_mode_set:
                MOV     AX, 0004H
                INT     10H
                MOV     BYTE PTR ds:[GfxContext.bActiveVgaMode], 4

                CMP     BYTE PTR ds:[GfxContext.bBiosCompatible], 1
                JNZ     SHORT cga_init_dos_alloc

                MOV     AX, 0400H
                PUSH    AX
                PUSH    CS                      ; fake far-call return seg
                CALL    NEAR PTR cga_dos_alloc_far ; near call, callee does RETF
                ADD     SP, 2
                OR      AL, AL
                JNZ     SHORT cga_init_alloc_ok
                JMP     SHORT cga_init_exit
cga_init_alloc_ok:
                CALL    cga_alloc_backbuffer_pages
                CMP     WORD PTR ds:[06E4H], 0B800H
                JNZ     SHORT cga_init_alloc_back_zero_all
                CMP     WORD PTR ds:[06E6H], 0B800H
                JNZ     SHORT cga_init_alloc_back_zero_all

cga_init_dos_alloc:
                MOV     AX, 4800H
                MOV     BX, 0400H
                INT     21H
                JC      SHORT cga_init_exit
                MOV     ds:[GfxContext.wVgaPage2Base], AX
                MOV     AX, 0B800H
                MOV     ds:[GfxContext.wVgaFrontPageBase], AX

cga_init_alloc_back_zero_all:
                MOV     AX, 4800H
                MOV     BX, 0400H
                INT     21H
                JC      SHORT cga_init_exit
                MOV     ds:[GfxContext.wVgaPage1Base], AX

                MOV     AX, ds:[GfxContext.wVgaPage1Base]
                PUSH    AX
                MOV     AX, ds:[GfxContext.wVgaPage2Base]
                PUSH    AX
                MOV     AX, ds:[GfxContext.wVgaFrontPageBase]
                PUSH    AX
                MOV     DX, 3
cga_init_zero_one:
                POP     AX
                MOV     ES, AX
                MOV     CX, 2000H
                XOR     AX, AX
                XOR     DI, DI
                REP     STOSW
                DEC     DX
                JNZ     SHORT cga_init_zero_one

                ; ----- Build the CGA scanline-offset LUT into scratch:[0x6F2]
                ; (ES is reset from DS just above). 200 entries x 2 bytes = 400 bytes total.
                MOV     CX, 0064H
                MOV     DI, GfxContext.pRow_offset_lut
                XOR     AX, AX
                PUSH    DS
                POP     ES                      ; ES = scratch DS
                CLD
cga_init_lut_loop:
                STOSW                           ; row 2k
                ADD     AX, 2000H
                STOSW                           ; row 2k+1
                SUB     AX, 1FB0H
                LOOP    SHORT cga_init_lut_loop
                MOV     AL, 1
cga_init_exit:
                MOV     DX, CS
                MOV     SI, 0200H               ; offset of vtable template
                MOV     ds:[GfxContext.bVideoAdapter], AL ; driver-installed flag
                POP     DI
                POP     DS
                POP     BP
                RETF
cga_init        ENDP

; ============================================================================
; 0x00DE..0x00E8 -- chunk-local globals, zero-initialised on disk.
; Read/written via `CS:` overrides from cga_init and the conventional-
; memory-conversion helpers below.
; ============================================================================
g_wCgaChunkDataSeg      DW      0       ; 0x00DE  scratch-DS paragraph
g_wCgaChunkDataBaseOff  DW      0       ; 0x00E0  saved backbuffer_paragraphs
g_wCgaMemConvBaseSeg    DW      0       ; 0x00E2  total conv. mem (paragraphs)
g_wCgaMemConvEndSeg     DW      0       ; 0x00E4  conv-mem upper limit
g_wCgaMemConvOkFlag     DW      0       ; 0x00E6  cga_dos_alloc_far result
g_bCgaPriorMode640Flag  DB      0       ; 0x00E8

; ============================================================================
; cga_dos_alloc_far -- "is there room above BX paragraphs?" probe.
; chunk:0x00E9..0x0152
;
; Allocates the smallest possible DOS block (BX=1 para), walks the MCB
; chain to find the address of the top-of-conventional-memory MCB, and
; reports whether the system has at least [BP+6] paragraphs of free
; conventional memory above the current load address. Returns 1 in AX
; if yes, 0 if no. On a "yes" the trailing MCB is shrunk by [BP+6]
; paragraphs to reserve the space for later DOS allocs.
;
; The chunk's caller (cga_init) treats AL=0 from this routine as an
; OOM signal and skips straight to cga_init_exit.
;
; Called as: push <para_count> / push CS / call NEAR PTR cga_dos_alloc_far.
; The PUSH CS sets up a fake far-call return frame so the callee can RETF.
;
; ABI:
;   [BP+6]  ushort  para_count_needed
; Returns AX = 1 (ok) or 0 (insufficient memory).
; ============================================================================
cga_dos_alloc_far PROC NEAR
                PUSH    BP
                MOV     BP, SP
                INT     12H                     ; AX = conv mem in KB
                MOV     CL, 6
                SHL     AX, CL                  ; KB -> paragraphs (* 64)
                MOV     cs:[0E2H], AX           ; g_wCgaMemConvBaseSeg
                SUB     AX, [BP+6]              ; - requested paragraphs
                MOV     cs:[0E4H], AX           ; g_wCgaMemConvEndSeg
                MOV     AH, 48H
                MOV     BX, 1
                INT     21H                     ; alloc 1 para (probe handle)
                MOV     DX, AX                  ; save handle
                DEC     AX                      ; back up to MCB header
                MOV     BX, 0
                MOV     ES, AX
                MOV     CL, ES:[BX]             ; MCB.type ('M' or 'Z')
cga_dos_walk_chain:
                MOV     ES, AX
                MOV     BX, 3
                ADD     AX, ES:[BX]             ; += MCB.size
                INC     AX
                MOV     BX, 0
                CMP     ES:[BX], CL             ; stop when type differs
                JZ      SHORT cga_dos_walk_chain
                CMP     AX, cs:[0E4H]
                JBE     SHORT cga_dos_mark_ok   ; end < end-limit -> ok
                CMP     AX, cs:[0E2H]
                JNZ     SHORT cga_dos_mark_fail ; not at top -> fail
                ; Shrink the trailing MCB by the requested paragraphs.
                MOV     BX, 3
                MOV     AX, [BP+6]
                SUB     ES:[BX], AX
cga_dos_mark_ok:
                MOV     WORD PTR cs:[0E6H], 1
                JMP     SHORT cga_dos_free_probe
cga_dos_mark_fail:
                MOV     WORD PTR cs:[0E6H], 0
cga_dos_free_probe:
                MOV     ES, DX
                MOV     AH, 49H
                INT     21H                     ; free probe handle
                MOV     AX, cs:[0E6H]
                POP     BP
                RETF
cga_dos_alloc_far ENDP

; ============================================================================
; cga_alloc_backbuffer_pages -- find two free 16 KiB pages in B800.
; chunk:0x0153..0x0185
;
; Tries the two CGA page-pair palettes (07/06 and 06/07) via
; cga_setpal_and_vsync to draw a calibration signature, then asks
; cga_find_free_page_segment to locate a B800-aperture segment that
; contains the signature. The two returned segments are stashed in
; scratch:[0x6E6] / scratch:[0x6E4]. Finally scratch:[0x14] is set
; to the first page and scratch:[0x12] is hard-coded to B800. (These
; two scratch-DS slots correspond to the EQUs g_wCgaBackBufferSeg
; / -- the role of ds:[0x12] is not named at the top of this file
; because no runtime read of it is annotated; cga_capture_rect at
; line ~4218 reads ds:[0x12] as the source segment of the
; back-buffer -> visible-buffer copy.)
;
; ABI: no args, no return value (results stored in scratch globals).
; Called as a near function (RET at 0x185) by cga_init.
; ============================================================================
cga_alloc_backbuffer_pages PROC NEAR
                MOV     BX, 0607H
                CALL    cga_setpal_and_vsync
                MOV     AX, 1414H
                PUSH    AX
                CALL    cga_find_free_page_segment
                ADD     SP, 2
                MOV     ds:[06E6H], AX
                MOV     BX, 0706H
                CALL    cga_setpal_and_vsync
                MOV     AX, 1515H
                PUSH    AX
                CALL    cga_find_free_page_segment
                ADD     SP, 2
                MOV     ds:[06E4H], AX
                MOV     AX, ds:[06E6H]
                MOV     ds:[GfxContext.wVgaFrontPageBase], AX
                MOV     WORD PTR ds:[GfxContext.wVgaPage2Base], 0B800H
                RET
cga_alloc_backbuffer_pages ENDP

; ============================================================================
; cga_setpal_and_vsync -- issue an INT 10h palette/page call then
; wait for the next vertical retrace via port 3DA bit 3.
; chunk:0x0186..0x019A
;
; Used by cga_alloc_backbuffer_pages to paint a calibration palette
; before sampling the framebuffer for page detection.
;
; The vertical-retrace bit is bit 3 (mask = 8) of port 3DAh -- *not*
; bit 0. Bit 0 is "in any retrace, H or V", a much wider signal that
; goes high once per scanline; bit 3 is the narrower vsync-only
; signal that goes high once per frame (~1 ms). Source: IBM CGA TR
; p. 21. The first inner loop waits for any
; in-progress vblank to end (so we don't latch a "we're already in
; vblank" reading), then the second loop spins until vblank starts.
;
; Register-passed argument, no stack frame.
;
; ABI:
;   BX -- BH:BL passed through to INT 10h AX=0583h as BH/BL. On a
;         PCjr/Tandy the call sets the CRT/CPU page registers; on a
;         real IBM CGA it is a no-op (the BIOS ignores unrecognised
;         AL values). Behaviour confirmed via RBIL INT 10h AX=0583h.
; Returns nothing.
; ============================================================================
cga_setpal_and_vsync PROC NEAR
                MOV     AX, 0583H
                INT     10H                     ; PCjr/Tandy: set page regs
                                                ; Real CGA: no-op
                MOV     CL, 8                   ; bit 3 mask = vertical retrace
                MOV     DX, 03DAH               ; CGA status port
cga_vsync_wait_active:
                IN      AL, DX
                AND     AL, CL
                JNZ     SHORT cga_vsync_wait_active ; spin until vsync ends
cga_vsync_wait_blank:
                IN      AL, DX
                AND     AL, CL
                JZ      SHORT cga_vsync_wait_blank  ; spin until vsync begins
                RET
cga_setpal_and_vsync ENDP

; ============================================================================
; cga_find_free_page_segment -- locate a B800-aperture page that holds
; our calibration pattern.
; chunk:0x019B..0x01DB
;
; Writes a 40-word signature (the AX value passed in) into B800:0000,
; then scans every paragraph of conventional memory looking for a 40-
; word run that matches. Returns the segment paragraph of the match,
; or 0 if none found.
;
; The CS bytes here (`PUSH BP / MOV AX, 0B800H`) are executed once
; during init and never read again -- pure code, no data role.
;
; Non-symmetric stack pattern: the prologue does two PUSH BPs but the
; epilogue does POP ES / POP BP. The "POP ES" pulls the second-pushed
; BP off the stack and lands it in ES; this is effectively garbage in
; ES but the function isn't called again after init, so it doesn't
; matter.
;
; ABI: [BP+4] ushort pattern_word. Returns AX = matched segment, or 0.
; ============================================================================
cga_find_free_page_segment PROC NEAR
                PUSH    BP
                MOV     BP, SP
                ; The second PUSH BP here is the non-symmetric save
                ; mentioned in the plate (POP ES at the epilogue
                ; consumes it).
                PUSH    BP
                MOV     AX, 0B800H
                MOV     ES, AX
                MOV     AX, [BP+4]              ; pattern word
                XOR     DI, DI
                MOV     CX, 0028H
                REP     STOSW                   ; stamp 40 words at B800:0
                XOR     DI, DI
cga_pgscan_new_seg:
                MOV     CX, 0028H
                MOV     ES, DI                  ; ES = scan segment
                MOV     DI, 0FFFEH
cga_pgscan_loop:
                ADD     DI, 2
                CMP     AX, ES:[DI]
                LOOPZ   SHORT cga_pgscan_loop
                JCXZ    SHORT cga_pgscan_found
                MOV     DI, ES
                ADD     DI, 0400H               ; advance 0x400 paras (16 KiB)
                JNZ     SHORT cga_pgscan_new_seg ; until DI wraps to 0
                XOR     AX, AX                  ; not found
                JMP     SHORT cga_pgscan_exit
cga_pgscan_found:
                XOR     AX, AX
                XOR     DI, DI
                MOV     CX, 0028H
                REP     STOSW                   ; clear the matched page
                MOV     AX, ES
cga_pgscan_exit:
                POP     ES
                POP     BP
                RET
cga_find_free_page_segment ENDP

; ============================================================================
; cga_post_mode_change_mouse_refresh -- re-establish the mouse-cursor
; clipping rectangle after the chunk has clamped the mode width.
; chunk:0x01DC..0x01FF
;
; Only does work when g_bCgaPriorMode640Flag is set (i.e. the host had
; originally requested 640px but cga_init clamped to 320). In that case
; it first re-sets BIOS mode 6 (640x200 b/w) then issues INT 33h
; subfunctions AX=0007h (set horizontal cursor range) and AX=0008h
; (set vertical cursor range) to redefine the mouse-driver virtual
; coordinate space to 0..0x4FF (1280) by 0..0x31F (799). These are
; the standard Microsoft Mouse Driver subfunctions; see RBIL
; INT 33h AX=0007h / INT 33h AX=0008h.
;
; Why the values 1280x800? The mouse driver works in "mickeys" --
; virtual units that scale to the framebuffer. On CGA mode 4 the
; on-screen extent is 320x200 but the driver doubles X and quadruples
; Y so that the same pointer-speed setting produces consistent feel
; across video modes. The host code interprets the returned cursor
; coordinates with the same scale factor.
;
; The function is dispatched through the vtable so the host can call
; it after the driver has had a chance to scale the framebuffer.
;
; ABI: no args, no return.  Near-call (RET at 0x1FF).
; ============================================================================
cga_post_mode_change_mouse_refresh PROC NEAR
                MOV     AL, cs:[0E8H]           ; g_bCgaPriorMode640Flag
                OR      AL, AL
                JZ      SHORT cga_pmcm_exit
                MOV     AX, 0006H
                INT     10H                     ; BIOS set mode 6 (640x200 b/w);
                                                ;   this BIOS call also
                                                ;   programs 3D8h=1Eh, 3D9h=3Fh, and
                                                ;   clears the framebuffer to zero.
                MOV     AX, 0007H               ; INT 33h subfunc: set horizontal range
                MOV     CX, 0                   ; min X
                MOV     DX, 04FFH               ; max X (1279)
                INT     33H
                MOV     AX, 0008H               ; INT 33h subfunc: set vertical range
                MOV     CX, 0                   ; min Y
                MOV     DX, 031FH               ; max Y (799)
                INT     33H
cga_pmcm_exit:
                RET
cga_post_mode_change_mouse_refresh ENDP

; ============================================================================
; g_apfnCgaVtable -- 40-slot renderer-vtable template.
; chunk:0x0200..0x029F (160 bytes; 40 entries x 4)
;
; The host snapshots this region (along with the 10 dead slots from
; g_apfnHostCallbacks immediately following, totalling 50 slots = 200
; bytes) into g_renderer_vtable @ 39ae:2ac6 after cga_init returns.
; Each entry is (offset_word, segment_placeholder_word); the host
; STOSWs the chunk's load segment into every segment half.
; ============================================================================
g_apfnCgaVtable LABEL DWORD
                DW      0,      0               ; slot 0  -- NULL
                DW      0C9DH,  0               ; slot 1  -- cga_blit_glyph_row8_dithered
                DW      0470H,  0               ; slot 2  -- cga_draw_line
                DW      0C77H,  0               ; slot 3  -- cga_blit_sprite_noflip
                DW      0F33H,  0               ; slot 4  -- cga_present_rect
                DW      0DC5H,  0               ; slot 5  -- cga_save_rect_to_buffer
                DW      0E32H,  0               ; slot 6  -- cga_sprite_buffer_size
                DW      0E53H,  0               ; slot 7  -- cga_rect_paste_from_buffer
                DW      02ECH,  0               ; slot 8  -- cga_unimplemented_slot
                DW      1A18H,  0               ; slot 9  -- cga_capture_rect
                DW      02FBH,  0               ; slot 10 -- cga_fill_pixel_run_dithered
                DW      02FBH,  0               ; slot 11 -- cga_fill_pixel_run_dithered
                DW      02ECH,  0               ; slot 12 -- cga_unimplemented_slot
                DW      0B72H,  0               ; slot 13 -- cga_image_list_measure
                DW      0BB9H,  0               ; slot 14 -- cga_image_records_install
                DW      02ECH,  0               ; slot 15 -- cga_unimplemented_slot
                DW      02ECH,  0               ; slot 16 -- cga_unimplemented_slot
                DW      0FA8H,  0               ; slot 17 -- cga_blit_chunky_rect_to_video
                DW      02ECH,  0               ; slot 18 -- cga_unimplemented_slot
                DW      0AAEH,  0               ; slot 19 -- cga_palette_load
                DW      0AE9H,  0               ; slot 20 -- cga_palette_set
                DW      0EC0H,  0               ; slot 21 -- cga_getpixel
                DW      0EF4H,  0               ; slot 22 -- cga_putpixel
                DW      02ECH,  0               ; slot 23 -- cga_unimplemented_slot
                DW      1022H,  0               ; slot 24 -- cga_slot24_noop
                DW      1023H,  0               ; slot 25 -- cga_set_border_color
                DW      1033H,  0               ; slot 26 -- cga_slot26_noop
                DW      07EAH,  0               ; slot 27 -- cga_fill_spans_dithered
                DW      02ECH,  0               ; slot 28 -- cga_unimplemented_slot
                DW      1034H,  0               ; slot 29 -- cga_blit_sprite_clipped
                DW      153AH,  0               ; slot 30 -- cga_blit_rect_unrolled_unused
                DW      15FBH,  0               ; slot 31 -- cga_sprite_pool_finalize
                DW      1654H,  0               ; slot 32 -- cga_dos_freemem_block_unused
                DW      1663H,  0               ; slot 33 -- cga_blit_sprite_simple
                DW      02ECH,  0               ; slot 34 -- cga_unimplemented_slot
                DW      02ECH,  0               ; slot 35 -- cga_unimplemented_slot
                DW      02ECH,  0               ; slot 36 -- cga_unimplemented_slot
                DW      03C5H,  0               ; slot 37 -- cga_blit_stretched_row
                DW      0,      0               ; slot 38 -- NULL
                DW      0,      0               ; slot 39 -- NULL

; ============================================================================
; g_apfnHostCallbacks -- 19-entry host-service-callback table.
; chunk:0x02A0..0x02EB (76 bytes; 19 entries x 4)
;
; On disk this region is the *tail of the conceptual 50-slot vtable
; template* -- slots 40..49 of the 50-slot range overlap with the
; first 10 of these 19 entries (the host still snapshots all 50 slots).
; At runtime, the chunk init prologue's REP MOVSW (CX=0x26 words = 76
; bytes) overwrites the entire 76-byte region with the host-exported
; service-callback far pointers; from then on the chunk dispatches into
; the host as CALLF [0x02A0+N].
;
; On disk every entry is initialised to (cga_unimplemented_slot, 0).
; Slot 40..49 (vtable tail) are therefore harmlessly dead — every
; call through those slot indices would land in the 1-byte RETF stub
; (cga_unimplemented_slot @ 0x02EC) — UNLESS the host dispatch is
; gated on adapter-mode and never invokes them on CGA.
; Slots 50..58 (i.e. these 9 trailing entries past the vtable tail)
; are pure dead padding; the host doesn't read them as vtable slots
; and the REP MOVSW erases them at init.
; ============================================================================
g_apfnHostCallbacks LABEL DWORD
                DW      02ECH,  0               ; #0  cb 0 (vtable slot 40 / "fs_open"?)
                DW      02ECH,  0               ; #1  vtable slot 41
                DW      02ECH,  0               ; #2  vtable slot 42
                DW      02ECH,  0               ; #3  vtable slot 43
                DW      02ECH,  0               ; #4  vtable slot 44
                DW      02ECH,  0               ; #5  vtable slot 45
                DW      02ECH,  0               ; #6  vtable slot 46
                DW      02ECH,  0               ; #7  vtable slot 47
                DW      02ECH,  0               ; #8  vtable slot 48
                DW      02ECH,  0               ; #9  vtable slot 49
                DW      02ECH,  0               ; #10 dead past vtable
                DW      02ECH,  0               ; #11
                DW      02ECH,  0               ; #12
                DW      02ECH,  0               ; #13
                DW      02ECH,  0               ; #14
                DW      02ECH,  0               ; #15
                DW      02ECH,  0               ; #16
                DW      02ECH,  0               ; #17
                DW      02ECH,  0               ; #18

; ============================================================================
; cga_unimplemented_slot -- 1-byte RETF stub.
; chunk:0x02EC..0x02EC
;
; Reached either via a vtable slot that the chunk doesn't implement, or
; (statically) via early-exit branches in cga_fill_pixel_run_dithered
; that JLE to the closer near-RETF stub at 0x02FA. The byte value is
; CB (RETF).
; ============================================================================
cga_unimplemented_slot PROC FAR
                RETF
cga_unimplemented_slot ENDP

; ============================================================================
; 0x02ED -- 1 byte of zero padding before the span-mask LUTs.
; ============================================================================
                DB      0                       ; 0x02ED

; ============================================================================
; g_abCgaSpanKeepLeftMaskLut / g_abCgaSpanKeepRightMaskLut
; chunk:0x02EE..0x02F5
;
; Indexed by `pixel_offset_within_byte` (0..3 in CGA 4-colour mode).
; The "left mask" keeps the high (left-of-cursor) bits of the byte
; intact when starting a span partway through a byte; the "right mask"
; keeps the low (right-of-cursor) bits intact when finishing a span
; partway through a byte. Consumed by cga_fill_pixel_run_dithered.
; ============================================================================
g_abCgaSpanKeepLeftMaskLut LABEL BYTE
                DB      000H, 0C0H, 0F0H, 0FCH  ; 0x02EE: keep 0/2/4/6 high bits
g_abCgaSpanKeepRightMaskLut LABEL BYTE
                DB      0FFH, 03FH, 00FH, 003H  ; 0x02F2: keep 8/6/4/2 low bits

; ============================================================================
; 0x02F6..0x02F9 -- scratch words used by cga_blit_stretched_row.
;
;   g_wCgaStretchRowLoopCount  (0x02F6) -- remaining pixel count for
;                                          the current stretched row.
;   g_wCgaStretchRowAccum      (0x02F8) -- 4-pixel pack accumulator
;                                          (BL) plus its keep-mask
;                                          shadow (BH); flushed when
;                                          the rotating bit in CH
;                                          marks the byte complete.
;
; Both start at 0 on disk; cga_blit_stretched_row writes the initial
; values on every entry (see prologue around 0x03DD..0x03F5). No code
; reads them between calls, but they live in the .CODE segment because
; the stretched-row inner loop uses CS-relative encodings to reach
; them in one byte less than a DS-relative form would need.
; ============================================================================
g_wCgaStretchRowLoopCount DW      0
g_wCgaStretchRowAccum     DW      0

; ============================================================================
; cga_fill_pixel_run_early_ret -- 1-byte near-RETF stub at 0x02FA.
; Branch target for cga_fill_pixel_run_dithered's CX<=0 early-exit
; (JLE at 0x02FD reaches here in 2 bytes vs 0x03C4's terminal RETF
; which would need a longer encoding from there).
; ============================================================================
cga_fill_pixel_run_early_ret:
                RETF

; ============================================================================
; cga_fill_pixel_run_dithered -- write CX pixels of colour AL into the
; CGA 4-colour byte stream at ES:DI, applying a 2x1 checkerboard dither.
; chunk:0x02FB..0x03C4
;
; Vtable slots 10 and 11 both target this function.
; Register-passed args (no BP frame), reads the host's saved DS via SS:
; (the prologue pushes the host DS just before overwriting it, so SS:
; still indexes into the host's data segment for the dither lookup).
;
; ABI (register-passed):
;   CX  -- pixel count (count <= 0 early-exits via 0x02FA stub).
;   AL  -- pixel-row dither index (looked up in host's per-row palette
;          table at SS:[BX+AL] where BX = scratch:[0x019E]).
;   ES:DI -- destination byte address in CGA framebuffer.
;
; STRATEGY:
;   1. Re-fetch the actual colour for this row via SS:[BX+AL] indexed
;      by AL, where scratch:[0x019E] holds a near-offset into the host
;      data segment (a per-row palette/dither table). Toggle dither
;      phase by XORing scratch:[0x002A] with 1; on phase-1 rows ROR
;      the colour byte by 4 to swap nybbles.
;   2. Replicate the 4-bit colour to fill both nibbles of a byte
;      (AH=AL after the 4x SHL+OR). That gives the pixel pattern for
;      bytes whose 4 packed pixels are all the same colour.
;   3. Convert the cumulative pixel offset in BX (from the dither
;      lookup) into a byte offset (>>2) and pixel-within-byte (BX & 3),
;      then bump DI by the byte count.
;   4. Compute the right-edge byte position (BL+CX) vs 4. If the run
;      stays within one byte (<4), apply both left and right keep-
;      masks and OR in the dithered colour, writing one byte. Otherwise
;      do an unaligned leading byte, a REP STOSW middle, an optional
;      STOSB middle, then a tail byte with right-keep mask.
;
; CONSUMES (read-only):
;   scratch:[0x019E]  near-offset into host's data segment for the
;                     per-row palette table (written by cga_palette_set
;                     into scratch DS, NOT into CS).
;   scratch:[0x002A]  dither phase flag, toggled each call.
;   g_abCgaSpanKeepLeftMaskLut  / g_abCgaSpanKeepRightMaskLut.
; ============================================================================
cga_fill_pixel_run_dithered PROC FAR
                OR      CX, CX
                JLE     SHORT cga_fill_pixel_run_early_ret ; (target = 0x02FA)
                PUSH    DS
                MOV     DS, cs:[0DEH]           ; scratch DS
                PUSH    BX
                XOR     AH, AH
                MOV     BX, ds:[GfxContext.pPaletteScratchBuf] ; near-offset into host DS
                ADD     BX, AX                  ; +pixel-row index
                MOV     AL, ss:[BX]             ; per-row colour byte from host DS
                POP     BX
                XOR     WORD PTR ds:[002AH], 1  ; toggle dither phase
                JZ      SHORT cga_fpr_keep_phase
                ROR     AL, 1                   ; phase 1: swap nibbles via 4xROR
                ROR     AL, 1
                ROR     AL, 1
                ROR     AL, 1
cga_fpr_keep_phase:
                POP     DS
                AND     AL, 0FH                 ; keep low nibble (2-bit colour x 2)
                MOV     AH, AL
                SHL     AL, 1
                SHL     AL, 1
                SHL     AL, 1
                SHL     AL, 1
                OR      AL, AH                  ; AL = colour replicated into both nibbles
                MOV     AH, AL
                MOV     DX, AX                  ; DX = replicated-colour word
                MOV     AX, BX
                SHR     AX, 1
                SHR     AX, 1                   ; AX = BX/4 byte offset
                ADD     DI, AX
                AND     BX, 3                   ; BL = starting pixel within byte (0..3)
                MOV     AX, DX                  ; AX = colour byte
                MOV     DX, BX
                ADD     DX, CX                  ; DX = end pixel within byte
                CMP     DX, 4
                JGE     SHORT cga_fpr_multi_byte
                ; Single-byte path: span fits in one byte.
                MOV     CX, AX                  ; CL = colour byte
                MOV     AH, cs:[BX+02EEH]       ; left-keep mask for BX
                MOV     BX, DX
                MOV     AL, cs:[BX+02F2H]       ; right-keep mask for end pixel
                OR      AH, AL                  ; merge keep masks
                MOV     AL, ES:[DI]
                AND     AL, AH                  ; keep bits outside the span
                XOR     AH, 0FFH                ; flip mask = drop bits
                AND     CL, AH                  ; mask the colour byte to the span
                OR      AL, CL
                MOV     ES:[DI], AL
                JMP     SHORT cga_fpr_exit
cga_fpr_multi_byte:
                ; Multi-byte path: leading partial byte, optional REP STOSW
                ; middle, optional STOSB, trailing partial byte.
                MOV     DX, 4
                SUB     DX, BX                  ; DX = pixels in leading byte (1..4)
                SUB     CX, DX                  ; CX = pixels remaining after lead
                MOV     DX, AX                  ; DX = colour byte
                MOV     AL, ES:[DI]
                MOV     AH, cs:[BX+02EEH]       ; left-keep mask for BX
                AND     AL, AH                  ; keep left-of-span bits
                MOV     AH, cs:[BX+02F2H]       ; right-keep-complement for BX
                MOV     BL, DL
                AND     BL, AH                  ; span-pixels of colour
                OR      AL, BL
                STOSB                           ; write leading byte
                MOV     AX, DX                  ; AX = colour byte again
                MOV     DX, CX                  ; DX = total trailing-pixel count
                AND     CX, 0FFF8H              ; CX = whole-word pixel count (mult of 8)
                JZ      SHORT cga_fpr_lone_byte
                SHR     CX, 1
                SHR     CX, 1
                SHR     CX, 1                   ; CX = word count (pixels/8)
                REP     STOSW                   ; full-byte run
cga_fpr_lone_byte:
                MOV     CX, DX
                AND     CX, 4                   ; 4 leftover pixels = one byte?
                JZ      SHORT cga_fpr_tail_check
                STOSB
cga_fpr_tail_check:
                MOV     CX, DX
                AND     CX, 3                   ; trailing partial-byte pixels?
                JZ      SHORT cga_fpr_exit
                MOV     DX, AX                  ; DX = colour byte
                MOV     BX, CX                  ; BX = trailing pixel count (1..3)
                MOV     AH, cs:[BX+02F2H]       ; right-keep mask = high-bits-keep for tail
                MOV     AL, ES:[DI]
                AND     AL, AH
                MOV     AH, cs:[BX+02EEH]       ; left-keep mask = low-bits drop-complement
                AND     DL, AH
                OR      AL, DL
                MOV     ES:[DI], AL
cga_fpr_exit:
                RETF
cga_fill_pixel_run_dithered ENDP

; ============================================================================
; cga_blit_stretched_row -- horizontally-stretched 1-row blit of a CGA
; 2-bit-per-pixel source into the framebuffer.
; chunk:0x03C5..0x0467
;
; Register-passed args, no BP stack frame; [BP] is used
; as a NEAR pointer / iterator argument from the caller. Two scratch
; words at g_wCgaStretchRowLoopCount (0x02F6, loop counter) and
; g_wCgaStretchRowAccum (0x02F8, 4-pixel accumulator + mask shadow)
; are read and written every iteration. Branches at 0x042E/0x0448 use
; JC/JNC on a rotating bit in CH to detect "accumulator full" and
; "drained" states.
;
; ABI (register-passed). Caller is blit_image_stretched (host code at
; 0x180c:171f); registers are loaded immediately before the FAR call
; through slot 37 at DS:[0x2B5A]:
;   CX  -- pixel count (clipped dst x-end minus clipped dst x-start).
;   DX  -- destination start pixel index. Low 2 bits select the pixel
;          slot within the first dest byte; the remaining bits are
;          the byte offset to add to DI. Consumed in the prologue
;          (split into BX = within-byte * 2 and DI += byte_offset),
;          then DX is cleared and immediately REPURPOSED to hold a
;          copy of AX -- see AX below. The original input DX value
;          is dead after the prologue.
;   AX  -- source-image ROW STRIDE in bytes
;          (= image_width_pixels >> log2(pixels-per-byte); for CGA's
;          2bpp packing the shift is 2). Used twice: (1) `ADD SI, AX`
;          primes SI to the row immediately after the current sample
;          row, and (2) AX is also copied into DX (since AX itself is
;          consumed inside the loop) so the transparency-fallback
;          path can do `SUB BX, DX` to step the source pointer back
;          one row -- meaning a "transparent" sample on row N+1
;          resamples from row N.
;   SI  -- source byte offset (low half of the packed-pixel source
;          pointer) for the current dst row -- looked up by the
;          caller via a precomputed y-stretch table at ss:[0x5976].
;   BP  -- pointer into the caller's precomputed x-stretch table at
;          ss:[0x5476]; each `[BP+0]` read yields a source pixel
;          index, and `ADD BP, 2` walks one entry per iteration.
;   DS  -- image-data segment (set by caller from the source far
;          pointer's segment half).
;   ES:DI -- destination byte address in the CGA framebuffer.
; Returns nothing.
; ============================================================================
cga_blit_stretched_row PROC FAR
                MOV     BX, DX
                AND     BX, 3                   ; start pixel-within-byte (*2 later)
                SHL     BX, 1
                SHR     DX, 1
                SHR     DX, 1                   ; DX = byte offset
                ADD     DI, DX
                XOR     DX, DX
                DEC     CX
                MOV     cs:[02F6H], CX          ; pixel loop counter
                MOV     DX, AX
                ADD     SI, AX                  ; prime source position
                MOV     CL, BL
                MOV     CH, 0C0H                ; pixel-shift mask
                SHR     CH, CL                  ; align mask to starting pixel
                MOV     WORD PTR cs:[02F8H], 0FF00H
cga_bsr_pixel_loop:
                MOV     BX, [BP+0]              ; caller-supplied iter state
                MOV     CL, BL
                SHR     BX, 1
                SHR     BX, 1
                ADD     BX, SI
                MOV     AL, 0C0H
                AND     CL, 3
                SHL     CL, 1
                SHR     AL, CL
                MOV     AH, 30H                 ; sentinel value to test against
                TEST    [BX], AL
                JNZ     SHORT cga_bsr_have_pixel
                SUB     BX, DX
                AND     AL, [BX]
                SHL     AL, CL                  ; re-align
                MOV     AH, AL
cga_bsr_have_pixel:
                MOV     BX, cs:[02F8H]          ; pixel accumulator
                ; 4 cycles of SHL AH + RCL into BL/BH -- packs 2 pixels
                ; (one nybble) into the accumulator's mask half.
                SHL     AH, 1
                RCL     BL, 1
                SHL     AH, 1
                RCL     BL, 1
                SHL     AH, 1
                RCL     BH, 1
                SHL     AH, 1
                RCL     BH, 1
                MOV     cs:[02F8H], BX
                ADD     BP, 2
                ROR     CH, 1
                ROR     CH, 1                   ; rotated through bit-7 yet?
                JC      SHORT cga_bsr_flush_byte
                DEC     WORD PTR cs:[02F6H]
                JG      SHORT cga_bsr_pixel_loop
                ; Drained: pack the partial accumulator's mask bits, then
                ; flush a partial byte.
                MOV     BX, cs:[02F8H]
cga_bsr_drain_loop:
                SHL     BX, 1
                SHL     BX, 1
                OR      BX, 0300H
                SHR     CH, 1
                SHR     CH, 1
                JNC     SHORT cga_bsr_drain_loop
                MOV     AL, ES:[DI]
                AND     AL, BH
                OR      AL, BL
                STOSB
                RETF
cga_bsr_flush_byte:
                MOV     BX, cs:[02F8H]
                MOV     AL, ES:[DI]
                AND     AL, BH
                OR      AL, BL
                STOSB
                DEC     WORD PTR cs:[02F6H]
                JG      SHORT cga_bsr_pixel_loop
                RETF
cga_blit_stretched_row ENDP

; ============================================================================
; g_awCgaLineKeepMaskLut -- 4 keep-masks for CGA single-pixel plot.
; chunk:0x0468..0x046F (4 entries x 2 bytes)
;
; Indexed by (pixel_within_byte * 2). Each word's bits 0..7 are the
; mask byte to AND against the framebuffer byte to clear the target
; pixel slot; bits 8..15 are 0xFF (unused, padding so the AND of the
; full word leaves the high byte of any 16-bit source unchanged).
; Consumed by cga_draw_line.
; ============================================================================
g_awCgaLineKeepMaskLut LABEL WORD
                DW      03FFFH                  ; pixel 0: keep all except top 2 bits
                DW      0CFFFH                  ; pixel 1: keep all except bits 12-13
                DW      0F3FFH                  ; pixel 2: keep all except bits 10-11
                DW      0FCFFH                  ; pixel 3: keep all except bits  8- 9

; ============================================================================
; cga_draw_line -- Bresenham line plot for CGA 4-colour mode.
; chunk:0x0470..0x07D9
;
; Register-ABI. Reads g_bCgaLineDrawColor from scratch DS:[0x0E] (set by
; the host before this slot is invoked), broadcasts it across all 4
; pixels of a byte, then dispatches into one of four cases based on
; (start.x == end.x) and (start.y == end.y):
;
;   single pixel        BX==DX && CX==SI   -> 0x04CC
;   horizontal HRUN     BX!=DX && CX==SI   -> 0x04E3
;   vertical   VRUN     BX==DX && CX!=SI   -> 0x054C
;   diagonal Bresenham  BX!=DX && CX!=SI   -> 0x05D3
;
; The diagonal case is split again by whether dx > dy (X-major) or
; dy > dx (Y-major), and each is split again on slope sign and on
; whether the start row is in CGA bank 0 (BP=0x2000 step) or bank 1
; (BP=0xE050 step) -- the bank toggle is `XOR BP, 0xC050`.
;
; ABI (register-passed):
;   BX -- x0, DX -- x1, CX -- y0, SI -- y1.
; ES:DI -- caller need not set DI (this fn computes it from row LUT).
; Reads scratch globals: g_wCgaBlitSrcSeg etc. via DS = scratch.
; Caller's DS is preserved (PUSH/POP at entry/exit).
; ============================================================================
cga_draw_line   PROC    FAR
                PUSH    DS
                MOV     DS, cs:[0DEH]           ; scratch
                MOV     AL, ds:[GfxContext.bGfx_outline_color] ; g_bCgaLineDrawColor
                AND     AL, 3
                MOV     AH, AL
                SHL     AH, 1
                SHL     AH, 1
                OR      AL, AH
                MOV     AH, AL
                SHL     AL, 1
                SHL     AL, 1
                SHL     AL, 1
                SHL     AL, 1
                OR      AL, AH
                MOV     AH, AL                  ; AL=AH=colour x 4 pixels
                MOV     ds:[06C6H], AX          ; "set bits" word
                MOV     DI, BX
                AND     DI, 3
                SHL     DI, 1
                MOV     AX, cs:[DI+0468H]       ; g_awCgaLineKeepMaskLut
                MOV     ds:[06C0H], AX          ; keep mask cache
                XOR     AX, 0FFFFH
                AND     ds:[06C6H], AX
                MOV     DI, CX                  ; DI = y0
                SHL     DI, 1
                MOV     DI, ds:[DI].pRow_offset_lut       ; scanline offset LUT
                MOV     AX, BX
                SHR     AX, 1
                SHR     AX, 1
                ADD     DI, AX
                CMP     BX, DX
                JNZ     SHORT cga_dl_test_y_diff
                CMP     CX, SI
                JZ      SHORT cga_dl_one_pixel
                JMP     cga_dl_vertical
cga_dl_test_y_diff:
                CMP     CX, SI
                JZ      SHORT cga_dl_horiz
                JMP     cga_dl_diag

cga_dl_one_pixel:
                MOV     AX, ds:[06C0H]
                MOV     BX, AX
                MOV     AX, ds:[06C6H]
                MOV     DX, AX
                MOV     AL, ES:[DI]
                AND     AL, BH
                OR      AL, DH
                MOV     ES:[DI], AL
                JMP     cga_dl_exit

cga_dl_horiz:
                SUB     DX, BX                  ; run length
                MOV     CX, DX
                MOV     AX, ds:[06C0H]
                MOV     BX, AX
                MOV     AX, ds:[06C6H]
                MOV     DX, AX
                MOV     AX, ES:[DI]
                XCHG    AH, AL
                AND     AX, BX
                OR      AX, DX
cga_dl_hrun_step:
                ROR     DX, 1
                ROR     DX, 1
                ROR     BX, 1
                ROR     BX, 1
                JNC     SHORT cga_dl_hrun_flush
                AND     AX, BX
                OR      AX, DX
                DEC     CX
                JZ      SHORT cga_dl_hrun_done
                ROR     DX, 1
                ROR     DX, 1
                ROR     BX, 1
                ROR     BX, 1
                JNC     SHORT cga_dl_hrun_flush
                AND     AX, BX
                OR      AX, DX
                DEC     CX
                JZ      SHORT cga_dl_hrun_done
                ROR     DX, 1
                ROR     DX, 1
                ROR     BX, 1
                ROR     BX, 1
                JNC     SHORT cga_dl_hrun_flush
                AND     AX, BX
                OR      AX, DX
                DEC     CX
                JZ      SHORT cga_dl_hrun_done
                JMP     SHORT cga_dl_hrun_step
cga_dl_hrun_flush:
                XCHG    AH, AL
                MOV     ES:[DI], AX
                INC     DI
                INC     DI
                MOV     AX, ES:[DI]
                XCHG    AH, AL
                AND     AX, BX
                OR      AX, DX
                DEC     CX
                JZ      SHORT cga_dl_hrun_done
                JMP     SHORT cga_dl_hrun_step
cga_dl_hrun_done:
                XCHG    AH, AL
                MOV     ES:[DI], AX
                JMP     cga_dl_exit

cga_dl_vertical:
                SUB     CX, SI
                JL      SHORT cga_dl_vert_down
                NEG     CX
                SHL     SI, 1
                MOV     DI, ds:[SI].pRow_offset_lut
                MOV     AX, BX
                SHR     AX, 1
                SHR     AX, 1
                ADD     DI, AX
cga_dl_vert_down:
                NEG     CX
                MOV     BP, 2000H
                TEST    DI, 2000H
                JZ      SHORT cga_dl_vert_loop
                MOV     BP, 0E050H
cga_dl_vert_loop:
                MOV     AX, ds:[06C0H]
                MOV     BX, AX
                MOV     AX, ds:[06C6H]
                MOV     DX, AX
                MOV     AL, ES:[DI]
                AND     AL, BH
                OR      AL, DH
cga_dl_vert_write:                              ; 0x057F -- wrap target
                MOV     ES:[DI], AL
                DEC     CX
                JS      SHORT cga_dl_vert_last
                ADD     DI, BP
                XOR     BP, 0C050H
                MOV     AL, ES:[DI]
                AND     AL, BH
                OR      AL, DH
                MOV     ES:[DI], AL
                DEC     CX
                JS      SHORT cga_dl_vert_last
                ADD     DI, BP
                XOR     BP, 0C050H
                MOV     AL, ES:[DI]
                AND     AL, BH
                OR      AL, DH
                MOV     ES:[DI], AL
                DEC     CX
                JS      SHORT cga_dl_vert_last
                ADD     DI, BP
                XOR     BP, 0C050H
                MOV     AL, ES:[DI]
                AND     AL, BH
                OR      AL, DH
                MOV     ES:[DI], AL
                DEC     CX
                JS      SHORT cga_dl_vert_last
                ADD     DI, BP
                XOR     BP, 0C050H
                MOV     AL, ES:[DI]
                AND     AL, BH
                OR      AL, DH
                JMP     SHORT cga_dl_vert_write ; → 0x057F
cga_dl_vert_last:
                MOV     ES:[DI], AL
                JMP     cga_dl_exit

cga_dl_diag:
                SUB     DX, BX                  ; dx
                SUB     SI, CX                  ; dy
                JG      SHORT cga_dl_diag_dy_pos
                NEG     SI
                JMP     cga_dl_diag_dy_neg
cga_dl_diag_dy_pos:
                MOV     BP, 2000H
                TEST    DI, 2000H
                JZ      SHORT cga_dl_diag_dy_pos_bank0
                MOV     BP, 0E050H
cga_dl_diag_dy_pos_bank0:
                MOV     CX, SI
                CMP     CX, DX
                JZ      SHORT cga_dl_diag_dy_pos_eq
                JC      SHORT cga_dl_diag_dy_pos_lt
                JMP     cga_dl_diag_dy_pos_xmaj
cga_dl_diag_dy_pos_lt:
                JMP     SHORT cga_dl_diag_dy_pos_ymaj
cga_dl_diag_dy_pos_eq:
                ; 45-degree diagonal: step DX times across BP and right-shift
                ; the BX/DX masks each step.
                MOV     CX, DX
                MOV     BX, ds:[06C0H]
                MOV     AX, ds:[06C6H]
                MOV     DX, AX
                MOV     AL, ES:[DI]
                AND     AL, BH
                OR      AL, DH
                MOV     ES:[DI], AL
                DEC     CX
                JZ      SHORT cga_dl_diag_eq_done
cga_dl_diag_eq_loop:
                ADD     DI, BP
                XOR     BP, 0C050H
                ROR     DH, 1
                ROR     DH, 1
                ROR     BH, 1
                ROR     BH, 1
                JC      SHORT cga_dl_diag_eq_no_inc
                INC     DI
cga_dl_diag_eq_no_inc:
                MOV     AL, ES:[DI]
                AND     AL, BH
                OR      AL, DH
                JMP     $-1EH                    ; → cga_dl_diag_eq_loop. TASM auto-shortens both
                                                 ; `JMP label` and `JMP NEAR PTR label` to the 2-byte
                                                 ; EB form for backward in-range targets; the literal
                                                 ; `$-disp` arithmetic form forces the 3-byte E9 NEAR jump.
cga_dl_diag_eq_done:
                JMP     cga_dl_exit
cga_dl_diag_dy_pos_ymaj:
                MOV     BX, CX                  ; Y-major (|dy|>|dx|)
                MOV     CX, DX
                MOV     AX, BX
                SHL     AX, 1
                MOV     ds:[06C2H], AX          ; dx*2
                SUB     AX, CX
                MOV     SI, AX                  ; error0 = 2*dx - dy
                SUB     AX, CX
                MOV     BX, BP                  ; save bank-step
                MOV     BP, AX                  ; decision step = 2*(dx-dy)
                MOV     AX, ds:[06C0H]
                MOV     DX, ds:[06C6H]
                MOV     AL, ES:[DI]
                AND     AL, AH
                OR      AL, DH
                MOV     ES:[DI], AL
                ROR     DH, 1
                ROR     DH, 1
                ROR     AH, 1
                ROR     AH, 1
                CMC
                ADC     DI, 0
cga_dl_diag_ymaj1_loop:
                OR      SI, SI
                JS      SHORT cga_dl_diag_ymaj1_neg
                ADD     DI, BX
                XOR     BX, 0C050H
                ADD     SI, BP
                JMP     SHORT cga_dl_diag_ymaj1_plot
cga_dl_diag_ymaj1_neg:
                ADD     SI, ds:[06C2H]
cga_dl_diag_ymaj1_plot:
                MOV     AL, ES:[DI]
                AND     AL, AH
                OR      AL, DH
                MOV     ES:[DI], AL
                ROR     DH, 1
                ROR     DH, 1
                ROR     AH, 1
                ROR     AH, 1
                CMC
                ADC     DI, 0
                LOOP    cga_dl_diag_ymaj1_loop
                JMP     cga_dl_exit
cga_dl_diag_dy_pos_xmaj:
                MOV     BX, DX                  ; X-major
                MOV     AX, BX
                SHL     AX, 1
                MOV     ds:[06C2H], AX
                SUB     AX, CX
                MOV     SI, AX
                SUB     AX, CX
                MOV     BX, BP
                MOV     BP, AX
                MOV     AX, ds:[06C0H]
                MOV     DX, ds:[06C6H]
                MOV     AL, ES:[DI]
                AND     AL, AH
                OR      AL, DH
                MOV     ES:[DI], AL
cga_dl_diag_xmaj1_loop:
                ADD     DI, BX
                XOR     BX, 0C050H
                OR      SI, SI
                JS      SHORT cga_dl_diag_xmaj1_neg
                ROR     DH, 1
                ROR     DH, 1
                ROR     AH, 1
                ROR     AH, 1
                CMC
                ADC     DI, 0
                ADD     SI, BP
                JMP     SHORT cga_dl_diag_xmaj1_plot
cga_dl_diag_xmaj1_neg:
                ADD     SI, ds:[06C2H]
cga_dl_diag_xmaj1_plot:
                MOV     AL, ES:[DI]
                AND     AL, AH
                OR      AL, DH
                MOV     ES:[DI], AL
                LOOP    cga_dl_diag_xmaj1_loop
                JMP     cga_dl_exit

cga_dl_diag_dy_neg:
                MOV     BP, 2000H
                TEST    DI, 2000H
                JNZ     SHORT cga_dl_diag_dy_neg_bank0
                MOV     BP, 0E050H
cga_dl_diag_dy_neg_bank0:
                MOV     CX, SI
                CMP     CX, DX
                JZ      SHORT cga_dl_diag_dyn_eq
                JC      SHORT cga_dl_diag_dyn_lt
                JMP     cga_dl_diag_dyn_xmaj
cga_dl_diag_dyn_lt:
                JMP     SHORT cga_dl_diag_dyn_ymaj
cga_dl_diag_dyn_eq:
                MOV     CX, DX
                MOV     BX, ds:[06C0H]
                MOV     AX, ds:[06C6H]
                MOV     DX, AX
                MOV     AL, ES:[DI]
                AND     AL, BH
                OR      AL, DH
                MOV     ES:[DI], AL
                DEC     CX
                JZ      SHORT cga_dl_diag_dyn_eq_done
cga_dl_diag_dyn_eq_loop:
                SUB     DI, BP
                XOR     BP, 0C050H
                ROR     DH, 1
                ROR     DH, 1
                ROR     BH, 1
                ROR     BH, 1
                JC      SHORT cga_dl_diag_dyn_eq_no_inc
                INC     DI
cga_dl_diag_dyn_eq_no_inc:
                MOV     AL, ES:[DI]
                AND     AL, BH
                OR      AL, DH
                JMP     $-1EH                    ; → cga_dl_diag_dyn_eq_loop. Same NEAR-forcing trick
                                                 ; as cga_dl_diag_eq_loop above: the `$-disp` form forces
                                                 ; the 3-byte E9 jump (TASM otherwise auto-shortens to 2-byte EB).
cga_dl_diag_dyn_eq_done:
                JMP     cga_dl_exit
cga_dl_diag_dyn_ymaj:
                MOV     BX, CX
                MOV     CX, DX
                MOV     AX, BX
                SHL     AX, 1
                MOV     ds:[06C2H], AX
                SUB     AX, CX
                MOV     SI, AX
                SUB     AX, CX
                MOV     BX, BP
                MOV     BP, AX
                MOV     AX, ds:[06C0H]
                MOV     DX, ds:[06C6H]
                MOV     AL, ES:[DI]
                AND     AL, AH
                OR      AL, DH
                MOV     ES:[DI], AL
                ROR     DH, 1
                ROR     DH, 1
                ROR     AH, 1
                ROR     AH, 1
                CMC
                ADC     DI, 0
cga_dl_diag_dyn_ymaj_loop:
                OR      SI, SI
                JS      SHORT cga_dl_diag_dyn_ymaj_neg
                SUB     DI, BX
                XOR     BX, 0C050H
                ADD     SI, BP
                JMP     SHORT cga_dl_diag_dyn_ymaj_plot
cga_dl_diag_dyn_ymaj_neg:
                ADD     SI, ds:[06C2H]
cga_dl_diag_dyn_ymaj_plot:
                MOV     AL, ES:[DI]
                AND     AL, AH
                OR      AL, DH
                MOV     ES:[DI], AL
                ROR     DH, 1
                ROR     DH, 1
                ROR     AH, 1
                ROR     AH, 1
                CMC
                ADC     DI, 0
                LOOP    cga_dl_diag_dyn_ymaj_loop
                JMP     SHORT cga_dl_exit
cga_dl_diag_dyn_xmaj:
                MOV     BX, DX
                MOV     AX, BX
                SHL     AX, 1
                MOV     ds:[06C2H], AX
                SUB     AX, CX
                MOV     SI, AX
                SUB     AX, CX
                MOV     BX, BP
                MOV     BP, AX
                MOV     AX, ds:[06C0H]
                MOV     DX, ds:[06C6H]
                MOV     AL, ES:[DI]
                AND     AL, AH
                OR      AL, DH
                MOV     ES:[DI], AL
cga_dl_diag_dyn_xmaj_loop:
                SUB     DI, BX
                XOR     BX, 0C050H
                OR      SI, SI
                JS      SHORT cga_dl_diag_dyn_xmaj_neg
                ROR     DH, 1
                ROR     DH, 1
                ROR     AH, 1
                ROR     AH, 1
                CMC
                ADC     DI, 0
                ADD     SI, BP
                JMP     SHORT cga_dl_diag_dyn_xmaj_plot
cga_dl_diag_dyn_xmaj_neg:
                ADD     SI, ds:[06C2H]
cga_dl_diag_dyn_xmaj_plot:
                MOV     AL, ES:[DI]
                AND     AL, AH
                OR      AL, DH
                MOV     ES:[DI], AL
                LOOP    cga_dl_diag_dyn_xmaj_loop
                JMP     SHORT cga_dl_exit        ; assembles to EB 00 -- fall through
cga_dl_exit:
                POP     DS
                RETF
cga_draw_line   ENDP

; ============================================================================
; cga_fill_spans data block -- mask LUTs + scratch globals.
; chunk:0x07DA..0x07E9 (16 bytes)
;
; Same 4-entry left/right keep-mask pattern as the cga_fill_pixel_run
; block at 0x02EE/0x02F2, duplicated here for cga_fill_spans_dithered's
; CS-relative reads (which use a +0x07DA / +0x07DE indexed form).
; ============================================================================
g_abCgaMaskKeepLeftN LABEL BYTE
                DB      000H, 0C0H, 0F0H, 0FCH  ; 0x07DA
g_abCgaMaskKeepRightN LABEL BYTE
                DB      0FFH, 03FH, 00FH, 003H  ; 0x07DE
g_nCgaSpanRemainingRows  DW 0                   ; 0x07E2
g_nCgaSpanColorEvenRow   DW 0                   ; 0x07E4
g_nCgaSpanColorOddRow    DW 0                   ; 0x07E6
g_nCgaSpanRowOffsetTableBase DW 0               ; 0x07E8

; ============================================================================
; cga_fill_spans_dithered -- multi-row span filler with 2x1 dither.
; chunk:0x07EA..0x0A9C
;
; Register-ABI. Reads a vector of (x0, x1) span pairs from DS:SI via LODSW,
; renders each into the CGA framebuffer with a row-dependent colour
; alternating between an "even row" cache (g_nCgaSpanColorEvenRow) and
; an "odd row" cache (g_nCgaSpanColorOddRow). Three near-identical loop
; bodies handle init/first-row dispatch (body #1, falls through),
; even-row pass (body #2), and odd-row pass (body #3) -- the last two
; tail into each other so each iteration renders one row.
;
; Reads g_bCgaSpanDrawColor from scratch DS:[0x0D] (set by host), then
; SS-relative pattern lookup (host DS preserved in CX after the initial
; MOV CX, ES).
;
; The inner per-row span code is structurally identical to
; cga_fill_pixel_run_dithered's body: leading partial byte, REP STOSW
; middle, optional STOSB, trailing partial byte. The mask LUTs are
; addressed CS:[BX+0x07DA] / CS:[BX+0x07DE] (duplicates of the LUTs
; at 0x02EE/0x02F2, deliberately placed near this function for shorter
; encoding).
; ============================================================================
cga_fill_spans_dithered PROC FAR
                PUSH    DS
                ; Stash caller's ES into CX, then mirror into DS.
                ; The vtable convention here is that the host has set
                ; ES = the segment holding the span-vector + per-row
                ; palette table, so DS := ES lets us LODSW the span
                ; vector below. The original DS is saved on the stack.
                ; CX is later restored back into DS at the SS-relative
                ; pattern-byte fetch (see line below "MOV DS, CX").
                MOV     CX, ES
                MOV     DS, CX
                LODSW                           ; AX = arg word
                SHL     AX, 1
                MOV     BP, AX                  ; BP = arg*2 (initial row word index)
                LODSW                           ; AX = row count
                MOV     DS, cs:[0DEH]           ; scratch DS
                MOV     cs:[07E2H], AX          ; g_nCgaSpanRemainingRows
                MOV     AX, ds:[GfxContext.wGfxBlitDstPage]          ; g_wCgaFramebufferSeg
                MOV     ES, AX
                MOV     AX, GfxContext.pRow_offset_lut               ; scanline LUT base offset
                ADD     AX, cs:[0E0H]           ; + saved paragraph count
                MOV     cs:[07E8H], AX          ; g_nCgaSpanRowOffsetTableBase
                MOV     AL, ds:[GfxContext.bGfx_fill_color] ; g_bCgaSpanDrawColor
                SUB     AH, AH
                MOV     BX, ds:[GfxContext.pPaletteScratchBuf]          ; pattern base in host DS
                ADD     BX, AX
                MOV     AL, ss:[BX]             ; pattern byte from host DS
                MOV     DS, CX                   ; DS := caller's ES (per prologue)
                MOV     cs:[07E4H], AX          ; g_nCgaSpanColorEvenRow
                ROR     AL, 1
                ROR     AL, 1
                ROR     AL, 1
                ROR     AL, 1                   ; swap nibbles for odd-row colour
                JMP     cga_fsd_set_odd         ; → 0x08F9

cga_fsd_body1:
                LODSW                           ; x0
                MOV     BX, AX
                LODSW                           ; x1
                SUB     AX, BX
                JGE     SHORT cga_fsd_b1_pos
                JMP     cga_fsd_b1_step
cga_fsd_b1_pos:
                INC     AX
                MOV     CX, AX                  ; CX = span width
                MOV     DI, cs:[07E8H]
                MOV     DI, [BP+DI]             ; DI = scanline row offset
                MOV     AX, cs:[07E4H]          ; even-row colour
                AND     AL, 0FH
                MOV     AH, AL
                SHL     AL, 1
                SHL     AL, 1
                SHL     AL, 1
                SHL     AL, 1
                OR      AL, AH
                MOV     AH, AL
                MOV     DX, AX
                MOV     AX, BX
                SHR     AX, 1
                SHR     AX, 1
                ADD     DI, AX
                AND     BX, 3
                MOV     AX, DX
                MOV     DX, BX
                ADD     DX, CX
                CMP     DX, 4
                JGE     SHORT cga_fsd_b1_multi
                MOV     CX, AX
                MOV     AH, cs:[BX+07DAH]
                MOV     BX, DX
                MOV     AL, cs:[BX+07DEH]
                OR      AH, AL
                MOV     AL, ES:[DI]
                AND     AL, AH
                XOR     AH, 0FFH
                AND     CL, AH
                OR      AL, CL
                MOV     ES:[DI], AL
                JMP     SHORT cga_fsd_b1_step
cga_fsd_b1_multi:
                MOV     DX, 4
                SUB     DX, BX
                SUB     CX, DX
                MOV     DX, AX
                MOV     AL, ES:[DI]
                MOV     AH, cs:[BX+07DAH]
                AND     AL, AH
                MOV     AH, cs:[BX+07DEH]
                MOV     BL, DL
                AND     BL, AH
                OR      AL, BL
                STOSB
                MOV     AX, DX
                MOV     DX, CX
                AND     CX, 0FFF8H
                JZ      SHORT cga_fsd_b1_lone
                SHR     CX, 1
                SHR     CX, 1
                SHR     CX, 1
                REP     STOSW
cga_fsd_b1_lone:
                MOV     CX, DX
                AND     CX, 4
                JZ      SHORT cga_fsd_b1_tail
                STOSB
cga_fsd_b1_tail:
                MOV     CX, DX
                AND     CX, 3
                JZ      SHORT cga_fsd_b1_step
                MOV     DX, AX
                MOV     BX, CX
                MOV     AH, cs:[BX+07DEH]
                MOV     AL, ES:[DI]
                AND     AL, AH
                MOV     AH, cs:[BX+07DAH]
                AND     DL, AH
                OR      AL, DL
                MOV     ES:[DI], AL
cga_fsd_b1_step:
                SUB     WORD PTR cs:[07E2H], 1
                JLE     SHORT cga_fsd_b1_exit
                ADD     BP, 2
                JMP     cga_fsd_body1
cga_fsd_b1_exit:
                POP     DS
                RETF

cga_fsd_set_odd:
                ; Set odd-row colour cache, then dispatch on starting
                ; row parity bit into either body #2 (even) or body #3 (odd).
                MOV     cs:[07E6H], AX
                MOV     BX, BP
                SHR     BX, 1
                ADD     BX, [SI]
                SHR     BX, 1
                JC      SHORT cga_fsd_body2
                JMP     cga_fsd_body3

cga_fsd_body2:
                LODSW
                MOV     BX, AX
                LODSW
                SUB     AX, BX
                JGE     SHORT cga_fsd_b2_pos
                JMP     cga_fsd_b2_step
cga_fsd_b2_pos:
                INC     AX
                MOV     CX, AX
                MOV     DI, cs:[07E8H]
                MOV     DI, [BP+DI]
                MOV     AX, cs:[07E4H]          ; even colour
                AND     AL, 0FH
                MOV     AH, AL
                SHL     AL, 1
                SHL     AL, 1
                SHL     AL, 1
                SHL     AL, 1
                OR      AL, AH
                MOV     AH, AL
                MOV     DX, AX
                MOV     AX, BX
                SHR     AX, 1
                SHR     AX, 1
                ADD     DI, AX
                AND     BX, 3
                MOV     AX, DX
                MOV     DX, BX
                ADD     DX, CX
                CMP     DX, 4
                JGE     SHORT cga_fsd_b2_multi
                MOV     CX, AX
                MOV     AH, cs:[BX+07DAH]
                MOV     BX, DX
                MOV     AL, cs:[BX+07DEH]
                OR      AH, AL
                MOV     AL, ES:[DI]
                AND     AL, AH
                XOR     AH, 0FFH
                AND     CL, AH
                OR      AL, CL
                MOV     ES:[DI], AL
                JMP     SHORT cga_fsd_b2_step
cga_fsd_b2_multi:
                MOV     DX, 4
                SUB     DX, BX
                SUB     CX, DX
                MOV     DX, AX
                MOV     AL, ES:[DI]
                MOV     AH, cs:[BX+07DAH]
                AND     AL, AH
                MOV     AH, cs:[BX+07DEH]
                MOV     BL, DL
                AND     BL, AH
                OR      AL, BL
                STOSB
                MOV     AX, DX
                MOV     DX, CX
                AND     CX, 0FFF8H
                JZ      SHORT cga_fsd_b2_lone
                SHR     CX, 1
                SHR     CX, 1
                SHR     CX, 1
                REP     STOSW
cga_fsd_b2_lone:
                MOV     CX, DX
                AND     CX, 4
                JZ      SHORT cga_fsd_b2_tail
                STOSB
cga_fsd_b2_tail:
                MOV     CX, DX
                AND     CX, 3
                JZ      SHORT cga_fsd_b2_step
                MOV     DX, AX
                MOV     BX, CX
                MOV     AH, cs:[BX+07DEH]
                MOV     AL, ES:[DI]
                AND     AL, AH
                MOV     AH, cs:[BX+07DAH]
                AND     DL, AH
                OR      AL, DL
                MOV     ES:[DI], AL
cga_fsd_b2_step:
                SUB     WORD PTR cs:[07E2H], 1
                JG      SHORT cga_fsd_b2_continue
                POP     DS
                RETF
cga_fsd_b2_continue:
                ADD     BP, 2
                ; fall through to body #3
cga_fsd_body3:
                LODSW
                MOV     BX, AX
                LODSW
                SUB     AX, BX
                JGE     SHORT cga_fsd_b3_pos
                JMP     cga_fsd_b3_step
cga_fsd_b3_pos:
                INC     AX
                MOV     CX, AX
                MOV     DI, cs:[07E8H]
                MOV     DI, [BP+DI]
                MOV     AX, cs:[07E6H]          ; odd colour
                AND     AL, 0FH
                MOV     AH, AL
                SHL     AL, 1
                SHL     AL, 1
                SHL     AL, 1
                SHL     AL, 1
                OR      AL, AH
                MOV     AH, AL
                MOV     DX, AX
                MOV     AX, BX
                SHR     AX, 1
                SHR     AX, 1
                ADD     DI, AX
                AND     BX, 3
                MOV     AX, DX
                MOV     DX, BX
                ADD     DX, CX
                CMP     DX, 4
                JGE     SHORT cga_fsd_b3_multi
                MOV     CX, AX
                MOV     AH, cs:[BX+07DAH]
                MOV     BX, DX
                MOV     AL, cs:[BX+07DEH]
                OR      AH, AL
                MOV     AL, ES:[DI]
                AND     AL, AH
                XOR     AH, 0FFH
                AND     CL, AH
                OR      AL, CL
                MOV     ES:[DI], AL
                JMP     SHORT cga_fsd_b3_step
cga_fsd_b3_multi:
                MOV     DX, 4
                SUB     DX, BX
                SUB     CX, DX
                MOV     DX, AX
                MOV     AL, ES:[DI]
                MOV     AH, cs:[BX+07DAH]
                AND     AL, AH
                MOV     AH, cs:[BX+07DEH]
                MOV     BL, DL
                AND     BL, AH
                OR      AL, BL
                STOSB
                MOV     AX, DX
                MOV     DX, CX
                AND     CX, 0FFF8H
                JZ      SHORT cga_fsd_b3_lone
                SHR     CX, 1
                SHR     CX, 1
                SHR     CX, 1
                REP     STOSW
cga_fsd_b3_lone:
                MOV     CX, DX
                AND     CX, 4
                JZ      SHORT cga_fsd_b3_tail
                STOSB
cga_fsd_b3_tail:
                MOV     CX, DX
                AND     CX, 3
                JZ      SHORT cga_fsd_b3_step
                MOV     DX, AX
                MOV     BX, CX
                MOV     AH, cs:[BX+07DEH]
                MOV     AL, ES:[DI]
                AND     AL, AH
                MOV     AH, cs:[BX+07DAH]
                AND     DL, AH
                OR      AL, DL
                MOV     ES:[DI], AL
cga_fsd_b3_step:
                SUB     WORD PTR cs:[07E2H], 1
                JLE     SHORT cga_fsd_b3_exit
                ADD     BP, 2
                JMP     cga_fsd_body2
cga_fsd_b3_exit:
                POP     DS
                RETF
cga_fill_spans_dithered ENDP

; ============================================================================
; g_abCgaBiosPalRegisterTable -- 17-byte BIOS palette-register stage.
; chunk:0x0A9D..0x0AAD
;
; First 4 bytes are pre-initialised CGA palette register indices
; (0, 3, 4, 0x0F). Bytes 4..16 are zero on disk. cga_palette_set writes
; into byte 0 (CS:[0A9D]) before issuing INT 10h AX=1002h (set all
; palette regs from ES:DX); the host expects this table laid out as
; 17 consecutive bytes (16 palette regs + overscan).
; ============================================================================
g_abCgaBiosPalRegisterTable LABEL BYTE
                DB      000H, 003H, 004H, 00FH
                DB      0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0

; ============================================================================
; cga_palette_load -- resolve a palette resource and load it via host
; callback. Vtable slot 19.
; chunk:0x0AAE..0x0AE8
;
; ABI (__cdecl16far):
;   [BP+0x06]  ushort  arg0  (palette resource id, passed to callback)
; Returns DX:AX = far pointer to loaded palette (DS:BX from callback),
; or 0:0 on failure.
;
; Host callbacks used:
;   CS:[02D0H]  (#12) -- allocate/locate near-buffer for palette load
;   CS:[02C8H]  (#10) -- load palette into the near-buffer
; ============================================================================
cga_palette_load PROC FAR
                PUSH    BP
                MOV     BP, SP
                PUSH    SI
                PUSH    DI
                PUSH    DS
                XOR     DX, DX
                MOV     AX, 0102H
                PUSH    AX
                CALL    DWORD PTR cs:[02D0H]    ; host callback #12
                ADD     SP, 2
                MOV     BX, AX
                OR      BX, BX
                JZ      SHORT cga_palload_exit
                MOV     AX, [BP+6]
                PUSH    AX
                MOV     AX, 0102H
                PUSH    AX
                MOV     AX, 1
                PUSH    AX
                MOV     AX, BX
                PUSH    BX
                CALL    DWORD PTR cs:[02C8H]    ; host callback #10
                POP     BX
                ADD     SP, 6
                MOV     DX, DS
cga_palload_exit:
                MOV     AX, BX
                POP     DS
                POP     DI
                POP     SI
                POP     BP
                RETF
cga_palette_load ENDP

; ============================================================================
; cga_palette_set -- install a palette into the active CGA mode.
; chunk:0x0AE9..0x0B71. Vtable slot 20.
;
; Writes the palette-table far pointer into scratch:[0x019E]/[0x01A0]
; (the cache that cga_fill_pixel_run_dithered / cga_fill_spans_dithered
; both read via SS-relative for per-row colour lookups). The byte at
; offset +0x100 in the resource selects the BIOS palette mode:
;   bytes 0..3  -> INT 10h AX=0004h (set mode 4), then INT 10h AH=0Bh
;                  BH=01h (select sub-palette 0 = green/red/brown vs
;                  1 = cyan/magenta/white). BL is derived from the
;                  resource's type byte via SHR 1 + XOR 1. See IBM
;                  CGA TR p. 18.
;   byte  4     -> "third-palette" path: OR bit 2 into the CGA
;                  mode-control register (port 3D8h). On an RGBI
;                  monitor in mode 4 this switches the visible palette
;                  to (bg / cyan / red / white) -- the undocumented
;                  "mode 5" effect. See IBM CGA TR p. 19-20.
;                  Then writes a foreground colour
;                  into g_abCgaBiosPalRegisterTable and issues INT 10h
;                  AX=1002h (EGA/VGA SET ALL PAL REGS) to commit
;                  -- the call is a no-op on a pure CGA but harmless,
;                  so the same code path works for cards that
;                  pretend to be a CGA at the BIOS level (EGA, VGA).
; Finally calls cga_post_mode_change_mouse_refresh and returns the input
; (offset, segment) pair via AX/DX.
;
; ABI (__cdecl16far):
;   [BP+0x06] ushort palette_off
;   [BP+0x08] ushort palette_seg
; Returns DX:AX = same far pointer (palette_seg:palette_off).
; ============================================================================
cga_palette_set PROC FAR
                PUSH    BP
                MOV     BP, SP
                PUSH    SI
                PUSH    DI
                PUSH    DS
                MOV     DS, cs:[0DEH]           ; scratch
                MOV     SI, [BP+6]
                MOV     AX, [BP+8]
                OR      AX, AX
                JZ      SHORT cga_palset_post
                MOV     ds:[GfxContext.pPaletteScratchBuf], SI          ; cache offset for per-row lookups
                MOV     ds:[GfxContext.pPaletteScratchBuf + 2], AX          ; cache segment
                MOV     DS, AX                  ; DS = palette-resource segment
                ADD     SI, 0100H               ; SI -> mode-byte trailer
                MOV     BL, [SI]                ; BL = palette type
                CMP     BL, 4
                JZ      SHORT cga_palset_mode4
                MOV     AX, 0004H
                INT     10H                     ; INT 10h AH=00h AL=04h: set mode 4
                                                ;   (320x200 4-colour). Side effects:
                                                ;   writes
                                                ;   3D8h=0Ah, 3D9h=30h, programs
                                                ;   6845, clears framebuffer.
                MOV     AH, 0BH
                MOV     BH, 1                   ; subfn 01h = "select palette"
                SHR     BL, 1
                XOR     BL, 1                   ; resource_type -> BIOS palette idx
                INT     10H                     ; INT 10h AH=0Bh BH=01h: select
                                                ;   sub-palette (BL=0 green/red/brown
                                                ;   vs BL=1 cyan/magenta/white).
                                                ;   Sets bit 5 of 3D9h. Source:
                                                ;   RBIL INT 10h AH=0Bh, IBM CGA TR
                                                ;   p. 18.
                MOV     BL, [SI]
                TEST    BL, 1
                JNZ     SHORT cga_palset_int1001
                MOV     BL, [SI+1]
                MOV     AH, 0BH
                XOR     BH, BH                  ; subfn 00h = "set bg/border colour"
                INT     10H                     ; INT 10h AH=0Bh BH=00h BL=colour:
                                                ;   in mode 4 writes BL[0..3] to
                                                ;   3D9h bits 0..3 (background
                                                ;   colour). Source: RBIL.
                JMP     SHORT cga_palset_post
cga_palset_int1001:
                MOV     BH, [SI+1]
                MOV     AX, 1001H
                INT     10H                     ; INT 10h AX=1001h: EGA/VGA "Set
                                                ; Overscan (Border) Color", BH=colour.
                                                ; Source: RBIL INT 10h AX=1001h.
                JMP     SHORT cga_palset_post
cga_palset_mode4:
                ; UNRESOLVED: this branch reads ES:[0x65] and writes
                ; port DX, but neither ES nor DX is set anywhere in
                ; cga_palette_set, and the two known C-side callers
                ; (palette_apply_cycled @ p1c8c:0x386 and the
                ; 39ae:04f0 setter at p1c8c:0x746) don't
                ; set them either. The instruction bytes only make
                ; sense as `MOV AL, [BIOS_DA:CRT_MODE]; OR AL, 4;
                ; OUT 3D8h, AL; MOV [BIOS_DA:CRT_MODE], AL` -- i.e.
                ; ES = 0x40 (BIOS data area) and DX = 0x3D8 (CGA
                ; mode-control port). Most likely candidates: (a)
                ; this branch is dead in practice because no game
                ; palette resource has type byte == 4 on CGA, or
                ; (b) implicit caller-ABI inherited from an earlier
                ; BIOS INT 10h on the call chain. Not resolved.
                MOV     AL, ES:[0065H]          ; presumed BIOS DA: CRT_MODE shadow
                                                ; (40h:65h is the BIOS-DA mirror of
                                                ; the last value written to 3D8h;
                                                ; see RBIL "BIOS Data Area" / HelpPC).
                OR      AL, 4                   ; set bit 2 = "B/W"; on RGB monitor
                                                ; in mode 4 this engages the
                                                ; third-palette quirk (red/cyan/white).
                OUT     DX, AL                  ; presumed port 3D8h (CGA mode-control)
                MOV     ES:[0065H], AL          ; keep BIOS-DA shadow in sync
                CMP     BYTE PTR ds:[GfxContext.bBiosCompatible], 1
                JZ      SHORT cga_palset_post
                MOV     AL, [SI+1]
                MOV     BX, 0A9DH               ; offset of pal-reg-stage byte 0
                MOV     cs:[BX], AL             ; overwrite stage[0]
                MOV     DX, BX
                MOV     AX, 1002H
                PUSH    CS
                POP     ES
                INT     10H                     ; INT 10h AX=1002h: EGA/VGA "Set All
                                                ; Palette Registers" -- ES:DX -> a
                                                ; 17-byte block (16 reg values +
                                                ; overscan). No-op on a pure CGA,
                                                ; works on EGA/VGA emulating CGA.
                                                ; Source: RBIL INT 10h AX=1002h.
                JMP     SHORT cga_palset_int1001
cga_palset_post:
                CALL    cga_post_mode_change_mouse_refresh
                MOV     AX, [BP+6]
                MOV     DX, [BP+8]
                POP     DS
                POP     DI
                POP     SI
                POP     BP
                RETF
cga_palette_set ENDP

; ============================================================================
; cga_image_list_measure -- sum (width/2 * height) over an image list,
; track the largest single image.
; chunk:0x0B72..0x0BB8. Vtable slot 13.
;
; ABI: [BP+6] image_list_ptr (NEAR), [BP+8] out_max_size_ptr.
; Returns DX:AX = total bytes needed for packed images.
; ============================================================================
cga_image_list_measure PROC FAR
                PUSH    BP
                MOV     BP, SP
                SUB     SP, 2
                PUSH    SI
                PUSH    DI
                MOV     DI, [BP+6]
                XOR     BX, BX
                XOR     CX, CX
                MOV     [BP-2], CX
cga_ilm_loop:
                MOV     SI, [DI]
                OR      SI, SI
                JZ      SHORT cga_ilm_done
                MOV     AX, [SI+6]
                SHR     AX, 1
                MOV     DX, [SI+8]
                MUL     DX
                CMP     AX, [BP-2]
                JLE     SHORT cga_ilm_no_max
                MOV     [BP-2], AX
cga_ilm_no_max:
                ADD     BX, AX
                ADC     CX, 0
                ADD     DI, 2
                JMP     SHORT cga_ilm_loop
cga_ilm_done:
                MOV     DX, CX
                MOV     SI, [BP+8]
                MOV     AX, [BP-2]
                MOV     [SI], AX
                MOV     AX, BX
                POP     DI
                POP     SI
                ADD     SP, 2
                POP     BP
                RETF
cga_image_list_measure ENDP

; ============================================================================
; cga_image_records_install -- pack a list of source images into a target
; buffer, filling each image-record's seg/off/end_off fields and calling
; cga_image_pack_loop_planar + cga_image_pack_transparency_mask per image.
; chunk:0x0BB9..0x0C76. Vtable slot 14.
;
; ABI (__cdecl16far):
;   [BP+6]   ushort  image_list_ptr (NEAR, modified)
;   [BP+8]   ushort  src_off
;   [BP+0Ah] ushort  src_seg
;   [BP+10H] ushort  dst_off
;   [BP+12H] ushort  dst_seg
; Each image-record at *image_list_ptr is a struct:
;   [+0..+1] seg, [+2..+3] off, [+4..+5] end_off,
;   [+6..+7] width, [+8..+9] height, ...
; ============================================================================
cga_image_records_install PROC FAR
                PUSH    BP
                MOV     BP, SP
                PUSH    SI
                PUSH    DI
cga_iri_loop:
                MOV     SI, [BP+6]
                MOV     DI, [BP+8]
                MOV     ES, [BP+0AH]
                MOV     SI, [SI]
                OR      SI, SI
                JNZ     SHORT cga_iri_rec
                JMP     cga_iri_done
cga_iri_rec:
                MOV     DX, DI
                MOV     AX, ES
                MOV     CL, 4
                SHR     DX, CL
                ADD     AX, DX
                MOV     [SI], AX
                MOV     DX, DI
                AND     DX, 0FH
                MOV     [SI+2], DX
                MOV     AX, [SI+6]
                XOR     DX, DX
                MUL     WORD PTR [SI+8]
                SHR     AX, 1
                SHR     AX, 1
                MOV     CX, AX
                ADD     AX, [SI+2]
                MOV     [SI+4], AX
                PUSH    SI
                PUSH    DI
                PUSH    DS
                PUSH    CX
                MOV     SI, [BP+8]
                MOV     DS, [BP+0AH]
                MOV     DI, [BP+10H]
                MOV     ES, [BP+12H]
                REP     MOVSW
                POP     CX
                POP     DS
                POP     DI
                POP     SI
                PUSH    CX
                XOR     AX, AX
                PUSH    AX
                MOV     AX, [SI+8]
                PUSH    AX
                MOV     AX, [SI+6]
                PUSH    AX
                PUSH    WORD PTR [BP+12H]
                PUSH    WORD PTR [BP+10H]
                PUSH    WORD PTR [BP+0AH]
                PUSH    WORD PTR [BP+8]
                PUSH    CS
                CALL    NEAR PTR cga_image_pack_loop_planar
                ADD     SP, 0EH
                POP     CX
                XOR     AX, AX
                ADD     [BP+8], CX
                RCR     AX, 1
                SHR     AX, 1
                SHR     AX, 1
                SHR     AX, 1
                ADD     [BP+0AH], AX
                PUSH    CX
                PUSH    WORD PTR [BP+12H]
                PUSH    WORD PTR [BP+10H]
                PUSH    WORD PTR [BP+0AH]
                PUSH    WORD PTR [BP+8]
                PUSH    CS
                CALL    NEAR PTR cga_image_pack_transparency_mask
                ADD     SP, 8
                POP     CX
                ADD     CX, [BP+8]
                MOV     AX, CX
                AND     CX, 0FH
                AND     AX, 0FFF0H
                SHR     AX, 1
                SHR     AX, 1
                SHR     AX, 1
                SHR     AX, 1
                ADD     [BP+0AH], AX
                MOV     [BP+8], CX
                ADD     WORD PTR [BP+6], 2
                JMP     cga_iri_loop
cga_iri_done:
                POP     DI
                POP     SI
                POP     BP
                RETF
cga_image_records_install ENDP

; ============================================================================
; cga_blit_sprite_noflip -- thin __cdecl16far wrapper that converts the
; vtable-style frame to cga_blit_sprite_clipped's calling convention by
; pushing a NULL flag-arg (no flip). Vtable slot 3.
; chunk:0x0C77..0x0C90 (26 bytes)
; ============================================================================
cga_blit_sprite_noflip PROC FAR
                PUSH    BP
                MOV     BP, SP
                XOR     AX, AX
                PUSH    AX                      ; flags = 0 (no flip)
                PUSH    WORD PTR [BP+0AH]
                PUSH    WORD PTR [BP+8]
                PUSH    WORD PTR [BP+6]
                PUSH    CS
                CALL    NEAR PTR cga_blit_sprite_clipped
                ADD     SP, 8
                MOV     BP, SP                  ; (dead-store)
                POP     BP
                RETF
cga_blit_sprite_noflip ENDP

; ============================================================================
; g_awCgaPixelReplicateLut -- 4-word LUT mapping a 2-bit colour index to
; the byte-replicated CGA 4-pixel pattern.
; chunk:0x0C91..0x0C98 (4 entries x 2 bytes)
;
; Index 0 -> 0x0000 (4 transparent pixels)
; Index 1 -> 0x5555 (4 pixels of colour 1)
; Index 2 -> 0xAAAA (4 pixels of colour 2)
; Index 3 -> 0xFFFF (4 pixels of colour 3)
; Consumed by cga_blit_glyph_row8_dithered to expand a 1-bit-per-pixel
; glyph row into a 2-bit-per-pixel CGA byte pair.
; ============================================================================
g_awCgaPixelReplicateLut LABEL WORD
                DW      0000H, 5555H, 0AAAAH, 0FFFFH

; ============================================================================
; g_wCgaGlyphRowKeepMask / g_wCgaGlyphRowSetMask -- dual-use scratch words.
; chunk:0x0C99 / 0x0C9B (each 2 bytes)
;
; cga_blit_glyph_row8_dithered patches these every call from the pixel-
; replicate LUT (using the foreground/background colour indices passed
; in AL/[0001H] of scratch DS) -- in effect this is self-modifying-code
; for the inner glyph blit loop.
; ============================================================================
g_wCgaGlyphRowKeepMask  DW      0       ; 0x0C99
g_wCgaGlyphRowSetMask   DW      0       ; 0x0C9B

; ============================================================================
; cga_blit_glyph_row8_dithered -- blit a 1-bit-per-pixel 8-wide glyph
; row sequence into the CGA framebuffer with optional mask.
; chunk:0x0C9D..0x0DC4 (296 bytes). Vtable slot 1.
;
; Register-passed args (no BP frame):
;   DX -- start X (pixel)
;   CX -- start Y (row)
;   BP -- row count
;   DS:SI -- source glyph rows (one byte per row, 1bpp)
;   The DS scratch slots [0x0000] (fg colour), [0x0001] (bg colour),
;     [0x0002] (mask flag = 0 no mask, !=0 with mask) are read first.
; The function patches g_wCgaGlyphRowKeepMask / g_wCgaGlyphRowSetMask
; from g_awCgaPixelReplicateLut and runs one of two inner loops:
;   mask path     (0x0CF1..0x0D59) -- two-bit-per-pixel mask from glyph byte
;   no-mask path  (0x0D5A..0x0DC4) -- always-on row write
; Both paths step DI through CGA bank-interleaved scanline offsets via
; XOR DI, 0x2000 + conditional ADD DI, 0x50 (paragraph wrap).
; ============================================================================
; Unusual register-save shape: prologue pushes SI/BP/DS/ES (4 saves).
; The fourth (ES = caller's ES) is consumed mid-function by the POP
; DS at line marked "pops ES into DS" -- after that POP, DS holds
; the value the caller had in ES, and the inner LODSB loops read
; source glyph bytes from that segment. The other three saves
; (DS/BP/SI) are popped at the exit paths in reverse order. Net
; stack is balanced (4 pushes, 4 pops), but the second-half of the
; function effectively swaps caller DS <-> ES: the caller's ES
; provides the source data and the caller's DS is restored on exit.
; ES is never restored to its caller value -- the function leaves it
; pointing at g_wCgaFramebufferSeg. No caller observes ES after
; return (vtable callers reload ES from scratch globals before any
; further framebuffer access).
cga_blit_glyph_row8_dithered PROC FAR
                PUSH    SI
                PUSH    BP
                PUSH    DS
                PUSH    ES                      ; (consumed by POP DS below)
                MOV     DS, cs:[0DEH]           ; scratch
                MOV     ES, ds:[GfxContext.wGfxBlitDstPage]          ; g_wCgaFramebufferSeg
                MOV     AL, ds:[GfxContext.bText_fg_color] ; scratch [0]
                AND     AX, 0003H
                SHL     AL, 1                   ; idx*2
                MOV     DI, AX
                MOV     AX, cs:[DI+0C91H]       ; pixel-replicate LUT
                MOV     cs:[0C99H], AX          ; patch g_wCgaGlyphRowKeepMask
                MOV     AL, ds:[GfxContext.bText_bg_color]
                AND     AX, 0003H
                SHL     AL, 1
                MOV     DI, AX
                MOV     AX, cs:[DI+0C91H]
                MOV     cs:[0C9BH], AX          ; patch g_wCgaGlyphRowSetMask
                SHL     BP, 1
                ; BP-relative addressing defaults to SS; the 3EH
                ; prefix forces DS so we index the scratch-DS
                ; scanline LUT, not the stack.
                MOV     DI, ds:[BP].pRow_offset_lut       ; scanline LUT[row]
                MOV     AX, DX
                MOV     BP, CX
                SHR     AX, 1
                SHR     AX, 1
                ADD     DI, AX
                MOV     BX, CX
                MOV     CX, DX
                AND     CX, 3
                MOV     AH, ds:[GfxContext.bText_style_flags]
                POP     DS                      ; pops ES into DS (see prologue note);
                                                ;     DS now = caller's ES, used for LODSB
                                                ;     of glyph source in the inner loops
                OR      AH, AH
                JZ      SHORT cga_gly_no_mask
                ; ----- mask path -----
cga_gly_mask_loop:
                LODSB
                XOR     BX, BX
                MOV     DX, CX
                MOV     CX, 8
cga_gly_m_expand:
                SHR     AL, 1
                RCR     BX, 1
                SHR     BX, 1
                LOOP    SHORT cga_gly_m_expand
                MOV     CX, DX
                MOV     AX, BX
                SHL     AX, 1
                OR      BX, AX
                XOR     DX, DX
                OR      CX, CX
                JZ      SHORT cga_gly_m_aligned
                MOV     AX, CX
cga_gly_m_shift:
                SHR     BX, 1
                RCR     DX, 1
                SHR     BX, 1
                RCR     DX, 1
                LOOP    SHORT cga_gly_m_shift
                MOV     CX, AX
cga_gly_m_aligned:
                MOV     AX, ES:[DI]
                XCHG    AL, AH
                NOT     BX
                AND     AX, BX
                NOT     BX
                AND     BX, cs:[0C99H]
                OR      AX, BX
                XCHG    AL, AH
                STOSW
                MOV     AL, ES:[DI]
                NOT     DH
                AND     AL, DH
                NOT     DH
                AND     DH, cs:[0C99H]          ; (note: high byte of word at 0xC99)
                OR      AL, DH
                STOSB
                XOR     DI, 2000H
                TEST    DI, 2000H
                JNZ     SHORT cga_gly_m_no_wrap
                ADD     DI, 50H
cga_gly_m_no_wrap:
                SUB     DI, 3
                DEC     BP
                JNZ     SHORT cga_gly_mask_loop
                ; Three pops match the three remaining stack entries
                ; DS/BP/SI; the ES save was already consumed at the
                ; prologue POP DS. See function plate above.
                POP     DS
                POP     BP
                POP     SI
                RETF
                ; ----- no-mask path -----
cga_gly_no_mask:
                ; Pre-double CL because this path uses single SHR/ROR
                ; instructions below (SHR DX, CL / ROR BX, CL) for the
                ; pixel-within-byte alignment, where the mask path used
                ; a loop that shifts 2 bits per iteration. Both paths
                ; end up shifting by 2 * (start_x & 3) bits.
                SHL     CL, 1
cga_gly_n_loop:
                LODSB
                XOR     BX, BX
                MOV     DX, CX
                MOV     CX, 8
cga_gly_n_expand:
                SHR     AL, 1
                RCR     BX, 1
                SHR     BX, 1
                LOOP    SHORT cga_gly_n_expand
                MOV     CX, DX
                MOV     AX, BX
                SHL     AX, 1
                OR      BX, AX
                MOV     AX, cs:[0C9BH]
                NOT     BX
                AND     AX, BX
                NOT     BX
                AND     BX, cs:[0C99H]
                OR      BX, AX
                MOV     AX, ES:[DI]
                XCHG    AL, AH
                MOV     DX, 0FFFFH
                SHR     DX, CL
                NOT     DX
                AND     AX, DX
                ROR     BX, CL
                NOT     DX
                AND     DX, BX
                OR      AX, DX
                XCHG    AL, AH
                STOSW
                MOV     AL, ES:[DI]
                MOV     DL, 0FFH
                SHR     DL, CL
                AND     AL, DL
                NOT     DL
                AND     BH, DL
                OR      AL, BH
                STOSB
                XOR     DI, 2000H
                TEST    DI, 2000H
                JNZ     SHORT cga_gly_n_no_wrap
                ADD     DI, 50H
cga_gly_n_no_wrap:
                SUB     DI, 3
                DEC     BP
                JNZ     SHORT cga_gly_n_loop
                POP     DS
                POP     BP
                POP     SI
                RETF
cga_blit_glyph_row8_dithered ENDP

; ============================================================================
; cga_save_rect_to_buffer -- copy a rectangle from g_wCgaBlitSrcSeg
; (back/visible) into a caller-provided buffer. Vtable slot 5.
; chunk:0x0DC5..0x0E31
; ABI: [BP+6] dst.off, [BP+8] dst.seg, [BP+0Ah] x0, [BP+0Ch] y0,
;      [BP+0Eh] x1, [BP+10h] row_count.
; ============================================================================
cga_save_rect_to_buffer PROC FAR
                PUSH    BP
                MOV     BP, SP
                PUSH    SI
                PUSH    DI
                PUSH    DS
                PUSH    ES
                MOV     AX, [BP+6]
                MOV     DI, AX
                SHR     AX, 1
                SHR     AX, 1
                SHR     AX, 1
                SHR     AX, 1
                AND     DI, 0FH
                ADD     AX, [BP+8]
                MOV     ES, AX
                MOV     SI, [BP+0AH]
                MOV     AX, SI
                SHR     SI, 1
                SHR     SI, 1
                MOV     BX, [BP+0EH]
                ADD     BX, AX
                SHR     BX, 1
                SHR     BX, 1
                SUB     BX, SI
                INC     BX
                MOV     AX, BX
                SHR     BX, 1
                AND     AX, 1
                JZ      SHORT cga_srtb_even
                INC     BX
cga_srtb_even:
                MOV     DX, [BP+10H]
                MOV     BP, [BP+0CH]
                SHL     BP, 1
                LEA     BP, [BP].pRow_offset_lut
                ADD     BP, cs:[0E0H]
                MOV     DS, cs:[0DEH]
                MOV     AX, ds:[GfxContext.wGfxBlitSrcPage]
                MOV     DS, AX
                MOV     AX, SI
cga_srtb_row:
                MOV     CX, BX
                MOV     SI, [BP+0]
                ADD     SI, AX
                REP     MOVSW
                ADD     BP, 2
                DEC     DX
                JNZ     SHORT cga_srtb_row
                POP     ES
                POP     DS
                POP     DI
                POP     SI
                POP     BP
                RETF
cga_save_rect_to_buffer ENDP

; ============================================================================
; cga_sprite_buffer_size -- compute the byte size of a sprite buffer for
; a given rect (round up width to multiple of 2 bytes, multiply by height).
; chunk:0x0E32..0x0E52. Vtable slot 6.
; ABI: [BP+6] width_pixels, [BP+8] height. Returns DX:AX = byte count.
; ============================================================================
cga_sprite_buffer_size PROC FAR
                PUSH    BP
                MOV     BP, SP
                MOV     AX, [BP+6]
                MOV     BX, AX
                SHR     BX, 1
                SHR     BX, 1
                INC     BX
                AND     AX, 3
                JZ      SHORT cga_sbs_even
                INC     BX
cga_sbs_even:
                TEST    BX, 1
                JZ      SHORT cga_sbs_word_aln
                INC     BX
cga_sbs_word_aln:
                MOV     AX, [BP+8]
                MUL     BX
                POP     BP
                RETF
cga_sprite_buffer_size ENDP

; ============================================================================
; cga_rect_paste_from_buffer -- inverse of cga_save_rect_to_buffer.
; chunk:0x0E53..0x0EBF. Vtable slot 7.
; ============================================================================
cga_rect_paste_from_buffer PROC FAR
                PUSH    BP
                MOV     BP, SP
                PUSH    SI
                PUSH    DI
                PUSH    DS
                PUSH    ES
                MOV     AX, [BP+6]
                MOV     SI, AX
                SHR     AX, 1
                SHR     AX, 1
                SHR     AX, 1
                SHR     AX, 1
                AND     SI, 0FH
                ADD     AX, [BP+8]
                PUSH    AX
                MOV     DI, [BP+0AH]
                MOV     AX, DI
                SHR     DI, 1
                SHR     DI, 1
                MOV     BX, [BP+0EH]
                ADD     BX, AX
                SHR     BX, 1
                SHR     BX, 1
                SUB     BX, DI
                INC     BX
                MOV     AX, BX
                SHR     BX, 1
                AND     AX, 1
                JZ      SHORT cga_rpfb_even
                INC     BX
cga_rpfb_even:
                MOV     DX, [BP+10H]
                MOV     BP, [BP+0CH]
                SHL     BP, 1
                LEA     BP, [BP].pRow_offset_lut
                ADD     BP, cs:[0E0H]
                MOV     DS, cs:[0DEH]
                MOV     AX, ds:[GfxContext.wGfxBlitDstPage]
                MOV     ES, AX
                POP     DS
                MOV     AX, DI
cga_rpfb_row:
                MOV     CX, BX
                MOV     DI, [BP+0]
                ADD     DI, AX
                REP     MOVSW
                ADD     BP, 2
                DEC     DX
                JNZ     SHORT cga_rpfb_row
                POP     ES
                POP     DS
                POP     DI
                POP     SI
                POP     BP
                RETF
cga_rect_paste_from_buffer ENDP

; ============================================================================
; cga_getpixel -- read a single pixel from the back buffer.
; chunk:0x0EC0..0x0EF3. Vtable slot 21.
; ABI: [BP+6] x, [BP+8] y. Returns AL = 2-bit pixel value.
; ============================================================================
cga_getpixel    PROC FAR
                PUSH    BP
                MOV     BP, SP
                PUSH    DS
                MOV     DS, cs:[0DEH]
                MOV     ES, ds:[GfxContext.wGfxBlitSrcPage]          ; g_wCgaBlitSrcSeg
                MOV     BX, [BP+8]
                SHL     BX, 1
                MOV     BX, ds:[BX].pRow_offset_lut
                MOV     AX, [BP+6]
                MOV     CX, AX
                SHR     AX, 1
                SHR     AX, 1
                ADD     BX, AX
                MOV     AX, 3
                NOT     CL
                AND     CL, AL
                SHL     CL, 1
                SHL     AL, CL
                AND     AL, ES:[BX]
                SHR     AL, CL
                POP     DS
                POP     BP
                RETF
cga_getpixel    ENDP

; ============================================================================
; cga_putpixel -- write a single pixel into the visible buffer.
; chunk:0x0EF4..0x0F32. Vtable slot 22.
; ABI: [BP+6] x, [BP+8] y, [BP+0Ah] colour.
; ============================================================================
cga_putpixel    PROC FAR
                PUSH    BP
                MOV     BP, SP
                PUSH    DS
                MOV     DS, cs:[0DEH]
                MOV     ES, ds:[GfxContext.wGfxBlitDstPage]          ; g_wCgaFramebufferSeg
                MOV     BX, [BP+8]
                SHL     BX, 1
                MOV     BX, ds:[BX].pRow_offset_lut
                MOV     AX, [BP+6]
                MOV     CX, AX
                SHR     AX, 1
                SHR     AX, 1
                ADD     BX, AX
                MOV     AL, 3
                NOT     CL
                AND     CL, AL
                MOV     AH, [BP+0AH]
                AND     AH, AL
                SHL     CL, 1
                SHL     AX, CL
                NOT     AL
                MOV     CL, ES:[BX]
                AND     CL, AL
                OR      CL, AH
                MOV     ES:[BX], CL
                POP     DS
                POP     BP
                RETF
cga_putpixel    ENDP

; ============================================================================
; cga_present_rect -- copy a rect from back buffer to front (B800).
; Vtable slot 4. chunk:0x0F33..0x0FA7.
; ABI: [BP+6] x0, [BP+8] y0, [BP+0Ah] x1, [BP+0Ch] row_count.
; ============================================================================
cga_present_rect PROC FAR
                PUSH    BP
                MOV     BP, SP
                PUSH    SI
                PUSH    DI
                PUSH    DS
                PUSH    ES
                MOV     DS, cs:[0DEH]
                MOV     BX, [BP+0AH]
                MOV     AX, [BP+6]
                ADD     BX, AX
                ADD     BX, 3
                AND     BX, 0FFFCH
                AND     AX, 0FFFCH
                SUB     BX, AX
                SHR     BX, 1
                SHR     BX, 1
                SHR     AX, 1
                SHR     AX, 1
                MOV     SI, AX
                MOV     DX, [BP+0CH]
                MOV     BP, [BP+8]
                SHL     BP, 1
                LEA     BP, [BP].pRow_offset_lut
                ADD     BP, cs:[0E0H]
                MOV     AX, ds:[GfxContext.wGfxBlitDstPage]
                MOV     ES, AX
                MOV     AX, ds:[GfxContext.wGfxBlitSrcPage]
                MOV     DS, AX
                MOV     AX, SI
                SHR     BX, 1
                JC      SHORT cga_pr_odd_row
cga_pr_even_row:
                MOV     CX, BX
                MOV     DI, [BP+0]
                ADD     DI, AX
                MOV     SI, DI
                REP     MOVSW
                ADD     BP, 2
                DEC     DX
                JNZ     SHORT cga_pr_even_row
                JZ      SHORT cga_pr_done
cga_pr_odd_row:
cga_pr_odd_loop:
                MOV     CX, BX
                MOV     DI, [BP+0]
                ADD     DI, AX
                MOV     SI, DI
                REP     MOVSW
                MOVSB
                ADD     BP, 2
                DEC     DX
                JNZ     SHORT cga_pr_odd_loop
cga_pr_done:
                POP     ES
                POP     DS
                POP     DI
                POP     SI
                POP     BP
                RETF
cga_present_rect ENDP

; ============================================================================
; cga_blit_chunky_rect_to_video -- copy a chunky-buffer rect into the
; back buffer one row at a time via cga_pack_scanline_via_palette_lut.
; chunk:0x0FA8..0x1021. Vtable slot 17.
;
; Note unusual prologue: PUSH BP / PUSH DS / PUSH SI / PUSH ES / PUSH DI
; then MOV BP, SP -- five saves before the frame is established, so all
; arg offsets are shifted up accordingly.
; ============================================================================
cga_blit_chunky_rect_to_video PROC FAR
                PUSH    BP
                PUSH    DS
                PUSH    SI
                PUSH    ES
                PUSH    DI
                MOV     BP, SP
                MOV     AX, [BP+16H]
                SHR     AX, 1
                SHR     AX, 1
                MOV     [BP+16H], AX
                MOV     AX, [BP+12H]
                SHR     AX, 1
                SHR     AX, 1
                MOV     [BP+12H], AX
                MOV     AX, [BP+0EH]
                MOV     BX, AX
                AND     BX, 0FH
                MOV     SI, BX
                SHR     AX, 1
                SHR     AX, 1
                SHR     AX, 1
                SHR     AX, 1
                ADD     AX, [BP+10H]
                MOV     DS, AX
                MOV     BX, 0018H
                ADD     BX, cs:[0E0H]
                MOV     ES, ss:[BX]
cga_bcrt_row:
                MOV     AX, [BP+14H]
                SHL     AX, 1
                MOV     BX, GfxContext.pRow_offset_lut
                ADD     BX, AX
                ADD     BX, cs:[0E0H]
                MOV     AX, ss:[BX]
                ADD     AX, [BP+12H]
                MOV     DI, AX
                MOV     DX, [BP+14H]
                MOV     CX, [BP+16H]
                PUSH    CS
                CALL    NEAR PTR cga_pack_scanline_via_palette_lut
                MOV     BP, SP
                MOV     AX, [BP+14H]
                ADD     AX, 1
                MOV     [BP+14H], AX
                MOV     AX, [BP+18H]
                SUB     AX, 1
                MOV     [BP+18H], AX
                JNZ     SHORT cga_bcrt_row
                POP     DI
                POP     ES
                POP     SI
                POP     DS
                POP     BP
                RETF
cga_blit_chunky_rect_to_video ENDP

; ============================================================================
; cga_slot24_noop -- 1-byte RETF stub at vtable slot 24.
; chunk:0x1022
; ============================================================================
cga_slot24_noop PROC FAR
                RETF
cga_slot24_noop ENDP

; ============================================================================
; cga_set_border_color -- thin wrapper over INT 10h AX=1001h (EGA/VGA
; "Set Overscan/Border Color"). Vtable slot 25.
; chunk:0x1023..0x1032
;
; The function is essentially a no-op on real CGA hardware (no border-
; colour register at this level; CGA's border is set indirectly via
; bits 0..3 of 3D9h when in text mode). On EGA/VGA in CGA emulation,
; the border is a real attribute-controller register and AX=1001h
; programs it directly.
;
; ABI: [BP+6] colour (low byte) -- BL replicated into BH for the call.
; Source: RBIL INT 10h AX=1001h.
; ============================================================================
cga_set_border_color PROC FAR
                PUSH    BP
                MOV     BP, SP
                MOV     BX, [BP+6]
                MOV     BH, BL                  ; BH = colour for AX=1001h
                MOV     AH, 10H
                MOV     AL, 1                   ; AX = 1001h (set overscan)
                INT     10H
                POP     BP
                RETF
cga_set_border_color ENDP

; ============================================================================
; cga_slot26_noop -- 1-byte RETF stub at vtable slot 26.
; chunk:0x1033
; ============================================================================
cga_slot26_noop PROC FAR
                RETF
cga_slot26_noop ENDP

; ============================================================================
; cga_blit_sprite_clipped -- clipped sprite blit dispatcher.
; chunk:0x1034..0x11E6. Vtable slot 29.
;
; Reads a 10-byte sprite descriptor from [BP+6] (sprite_desc_ptr), copies
; into a [BP-10..BP-1] local, then populates the CS-relative sprite-clip
; state globals at 0x1425..0x1439 and applies the clip rectangle from
; scratch:[0x3..0xB]. Tail-dispatches via JMP AX into one of 4 row engines
; via g_apfnCgaSpriteFlipDispatch (4-entry table at 0x1427).
;
; ABI (__cdecl16far, called via cga_blit_sprite_noflip / vtable slot 29):
;   [BP+6]   ushort  sprite_desc_off
;   [BP+8]   int     dst_x
;   [BP+0Ah] int     dst_y
;   [BP+0Ch] uchar   flags (bit0=vflip, bit1=hflip)
; ============================================================================
cga_blit_sprite_clipped PROC FAR
                PUSH    BP
                MOV     BP, SP
                SUB     SP, 0AH
                PUSH    SI
                PUSH    DI
                PUSH    ES
                PUSH    DS
                MOV     SI, [BP+6]
                MOV     DI, BP
                SUB     DI, 0AH
                MOV     AX, DS
                MOV     ES, AX
                MOV     CX, 5
                REP     MOVSW
                MOV     DS, cs:[0DEH]           ; scratch
                MOV     AX, ds:[GfxContext.wGfxBlitDstPage]
                MOV     ES, AX
                MOV     AL, [BP+0CH]            ; flags
                MOV     cs:[01437H], AL         ; g_bCgaSpriteFlipFlags
                MOV     BX, [BP+0AH]            ; dst_y
                SHL     BX, 1
                JNS     SHORT cga_bsc_dst_y_pos
                SAR     BX, 1
                NEG     BX
                MOV     cs:[01433H], BX         ; g_wCgaSpriteClipLeftSkip
                XOR     DI, DI
                JMP     SHORT cga_bsc_dst_y_done
cga_bsc_dst_y_pos:
                MOV     WORD PTR cs:[01433H], 0
                MOV     DI, ds:[BX].pRow_offset_lut
cga_bsc_dst_y_done:
                MOV     AX, [BP+8]
                MOV     CH, AL
                SAR     AX, 1
                SAR     AX, 1
                ADD     DI, AX
                AND     CH, 3
                SHL     CH, 1
                MOV     AX, [BP-4]
                MOV     DX, AX
                SHR     AX, 1
                SHR     AX, 1
                MOV     cs:[01425H], AX         ; g_wCgaSpriteClipStride
                ADD     DX, 3
                SHR     DX, 1
                SHR     DX, 1
                MOV     DH, DL
                MOV     AL, [BP-2]
                MOV     cs:[01439H], AL         ; g_bCgaSpriteRowCounter
                MOV     AX, [BP-0AH]
                MOV     cs:[0142FH], AX         ; g_wCgaSpriteClipSrcSeg
                MOV     SI, [BP-8]
                MOV     AX, [BP-6]
                MOV     cs:[01431H], AX         ; g_wCgaSpriteClipSrcOff
                XOR     AX, AX
                MOV     cs:[01435H], AL
                MOV     cs:[01436H], AL
                TEST    BYTE PTR cs:[01437H], 1
                JZ      SHORT cga_bsc_after_vflip
                PUSH    DX
                MOV     AL, cs:[01439H]
                XOR     AH, AH
                DEC     AX
                XOR     DX, DX
                MUL     WORD PTR cs:[01425H]
                ADD     SI, AX
                ADD     cs:[01431H], AX
                POP     DX
cga_bsc_after_vflip:
                TEST    BYTE PTR cs:[01437H], 2
                JZ      SHORT cga_bsc_after_hflip
                MOV     AX, cs:[01425H]
                DEC     AX
                ADD     SI, AX
                ADD     cs:[01431H], AX
cga_bsc_after_hflip:
                MOV     AL, ds:[GfxContext.bClip_enabled]          ; g_bCgaClipEnabled
                OR      AL, AL
                JNZ     SHORT cga_bsc_apply_clip
                JMP     cga_bsc_dispatch
cga_bsc_apply_clip:
                MOV     AX, ds:[GfxContext.nClip_xmax]
                INC     AX
                MOV     BX, [BP+8]
                ADD     BX, [BP-4]
                SUB     AX, BX
                JG      SHORT cga_bsc_right_ok
                NEG     AX
                CMP     AX, [BP-4]
                JL      SHORT cga_bsc_right_partial
                JMP     cga_sprite_blit_epilogue
cga_bsc_right_partial:
                SHR     AX, 1
                SHR     AX, 1
                SUB     DH, AL
                MOV     BYTE PTR cs:[01435H], 1
cga_bsc_right_ok:
                MOV     AX, [BP+8]
                SUB     AX, ds:[GfxContext.nClip_xmin]
                JNS     SHORT cga_bsc_after_left
                MOV     BX, AX
                ADD     AX, [BP-4]
                JG      SHORT cga_bsc_left_partial
                JMP     cga_sprite_blit_epilogue
cga_bsc_left_partial:
                MOV     BYTE PTR cs:[01436H], 1
                NEG     BX
                ADD     BX, 3
                SHR     BX, 1
                SHR     BX, 1
                SUB     DH, BL
                ADD     DI, BX
                TEST    BYTE PTR cs:[01437H], 2
                JZ      SHORT cga_bsc_left_no_neg
                NEG     BX
cga_bsc_left_no_neg:
                ADD     SI, BX
                ADD     cs:[01431H], BX
cga_bsc_after_left:
                MOV     AX, [BP+0AH]
                ADD     AX, [BP-2]
                SUB     AX, ds:[GfxContext.nClip_ymax]
                JLE     SHORT cga_bsc_after_bot
                CMP     AX, [BP-2]
                JS      SHORT cga_bsc_bot_partial
                JMP     cga_sprite_blit_epilogue
cga_bsc_bot_partial:
                DEC     AL
                SUB     cs:[01439H], AL
cga_bsc_after_bot:
                MOV     AX, ds:[GfxContext.nClip_ymin]
                SUB     AX, [BP+0AH]
                JS      SHORT cga_bsc_dispatch
                CMP     AX, [BP-2]
                JS      SHORT cga_bsc_top_partial
                JMP     cga_sprite_blit_epilogue
cga_bsc_top_partial:
                SUB     cs:[01439H], AL
                MOV     BX, AX
                SUB     AX, cs:[01433H]
                SHR     AX, 1
                JNC     SHORT cga_bsc_top_xor
                XOR     DI, 2000H
                TEST    DI, 2000H
                JNZ     SHORT cga_bsc_top_xor
                INC     AX
cga_bsc_top_xor:
                SHL     AX, 1
                SHL     AX, 1
                SHL     AX, 1
                SHL     AX, 1                   ; AX *= 16
                ADD     DI, AX
                SHL     AX, 1
                SHL     AX, 1                   ; AX *= 64 total
                ADD     DI, AX                  ; DI += AX*80
                MOV     AX, BX
                MUL     BYTE PTR cs:[01425H]
                TEST    BYTE PTR cs:[01437H], 1
                JZ      SHORT cga_bsc_top_no_neg
                NEG     AX
cga_bsc_top_no_neg:
                ADD     SI, AX
                ADD     cs:[01431H], AX
cga_bsc_dispatch:
                MOV     BL, cs:[01437H]
                XOR     BH, BH
                SHL     BX, 1
                MOV     AX, cs:[BX+01427H]      ; g_apfnCgaSpriteFlipDispatch[flags]
                MOV     DS, cs:[0142FH]         ; g_wCgaSpriteClipSrcSeg
                MOV     BP, cs:[01431H]         ; g_wCgaSpriteClipSrcOff
                JMP     AX
cga_blit_sprite_clipped ENDP

; ============================================================================
; cga_sprite_row_noflip -- row engine for unflipped sprite blits.
; chunk:0x11E7..0x1260. No PROC-level frame.
; Entered via cga_blit_sprite_clipped's JMP AX through
; g_apfnCgaSpriteFlipDispatch[0]. Loops over rows, decrementing
; cs:[01439H] and reusing the shared epilogue at 0x141C.
; ============================================================================
cga_sprite_row_noflip:
                PUSH    BP
                PUSH    SI
                PUSH    DI
cga_srn_row_top:
                MOV     DL, DH
                XOR     AH, AH
                MOV     BH, 0FFH
                TEST    BYTE PTR cs:[01436H], 1
                JZ      SHORT cga_srn_no_left
                MOV     BH, ds:[BP-1]
                MOV     AH, [SI-1]
                OR      DL, DL
                JZ      SHORT cga_srn_right_chk
cga_srn_no_left:
                MOV     CL, CH
                MOV     BL, ds:[BP+0]
                INC     BP
                ROR     BX, CL
                AND     BL, ES:[DI]
                LODSB
                ROR     AX, CL
                OR      AL, BL
                STOSB
                SUB     CL, 8
                NEG     CL
                SHR     AH, CL
                SHR     BH, CL
                DEC     DL
                JNZ     SHORT cga_srn_no_left
                TEST    BYTE PTR cs:[01435H], 1
                JNZ     SHORT cga_srn_row_advance
cga_srn_right_chk:
                MOV     CL, CH
                MOV     BL, 0FFH
                XOR     AL, AL
                SHR     BX, CL
                AND     BL, ES:[DI]
                SHR     AX, CL
                OR      AL, BL
                STOSB
cga_srn_row_advance:
                POP     DI
                MOV     AX, 2000H
                XOR     DI, AX
                TEST    DI, AX
                JNZ     SHORT cga_srn_no_wrap
                ADD     DI, 50H
cga_srn_no_wrap:
                POP     SI
                POP     BP
                MOV     AX, cs:[01425H]
                ADD     BP, AX
                ADD     SI, AX
                PUSH    BP
                PUSH    SI
                PUSH    DI
                DEC     BYTE PTR cs:[01439H]
                JNZ     SHORT cga_srn_row_top
                ADD     SP, 6
                JMP     cga_sprite_blit_epilogue

; ============================================================================
; cga_sprite_row_vflip -- row engine for vflip-only sprite blits.
; chunk:0x1261..0x12DA. Same as noflip but SUB BP/SI per row.
; ============================================================================
cga_sprite_row_vflip:
                PUSH    BP
                PUSH    SI
                PUSH    DI
cga_srv_row_top:
                MOV     DL, DH
                XOR     AH, AH
                MOV     BH, 0FFH
                TEST    BYTE PTR cs:[01436H], 1
                JZ      SHORT cga_srv_no_left
                MOV     BH, ds:[BP-1]
                MOV     AH, [SI-1]
                OR      DL, DL
                JZ      SHORT cga_srv_right_chk
cga_srv_no_left:
                MOV     CL, CH
                MOV     BL, ds:[BP+0]
                INC     BP
                ROR     BX, CL
                AND     BL, ES:[DI]
                LODSB
                ROR     AX, CL
                OR      AL, BL
                STOSB
                SUB     CL, 8
                NEG     CL
                SHR     AH, CL
                SHR     BH, CL
                DEC     DL
                JNZ     SHORT cga_srv_no_left
                TEST    BYTE PTR cs:[01435H], 1
                JNZ     SHORT cga_srv_row_advance
cga_srv_right_chk:
                MOV     CL, CH
                MOV     BL, 0FFH
                XOR     AL, AL
                SHR     BX, CL
                AND     BL, ES:[DI]
                SHR     AX, CL
                OR      AL, BL
                STOSB
cga_srv_row_advance:
                POP     DI
                MOV     AX, 2000H
                XOR     DI, AX
                TEST    DI, AX
                JNZ     SHORT cga_srv_no_wrap
                ADD     DI, 50H
cga_srv_no_wrap:
                POP     SI
                POP     BP
                MOV     AX, cs:[01425H]
                SUB     BP, AX
                SUB     SI, AX
                PUSH    BP
                PUSH    SI
                PUSH    DI
                DEC     BYTE PTR cs:[01439H]
                JNZ     SHORT cga_srv_row_top
                ADD     SP, 6
                JMP     cga_sprite_blit_epilogue

; ============================================================================
; cga_sprite_row_hflip -- row engine for hflip-only blits.
; chunk:0x12DB..0x137C. Uses XLAT CS:BX through g_abCgaPixelBitReverseLut
; at 0x143A to byte-reverse each source byte before merging.
; ============================================================================
cga_sprite_row_hflip:
                PUSH    BP
                PUSH    SI
                PUSH    DI
                MOV     BX, 0143AH              ; bit-reverse LUT base
                MOV     CL, CH
                SUB     CL, 8
                NEG     CL
cga_srh_row_top:
                PUSH    DX
                MOV     CH, DH
                XOR     AH, AH
                MOV     DH, 0FFH
                MOV     AL, cs:[01436H]
                OR      AL, AL
                JZ      SHORT cga_srh_no_left
                MOV     AL, ds:[BP+1]
                ; XLAT defaults to DS:BX. The `XLAT BYTE PTR CS:[BX]`
                ; form applies a CS segment override (0x2E prefix) so the
                ; table at g_abCgaPixelBitReverseLut is addressed
                ; CS-relative regardless of DS.
                XLAT    BYTE PTR CS:[BX]        ; -> AL = CS:[BX+AL]
                MOV     DH, AL
                MOV     AL, [SI+1]
                XLAT    BYTE PTR CS:[BX]
                MOV     AH, AL
                OR      CH, CH
                JZ      SHORT cga_srh_right_chk
cga_srh_no_left:
                SUB     CL, 8
                NEG     CL
                MOV     AL, ds:[BP+0]
                DEC     BP
                XLAT    BYTE PTR CS:[BX]
                MOV     DL, AL
                ROR     DX, CL
                AND     DL, ES:[DI]
                LODSB
                XLAT    BYTE PTR CS:[BX]
                SUB     SI, 2
                ROR     AX, CL
                OR      AL, DL
                STOSB
                SUB     CL, 8
                NEG     CL
                SHR     AH, CL
                SHR     DH, CL
                DEC     CH
                JNZ     SHORT cga_srh_no_left
                MOV     AL, cs:[01435H]
                OR      AL, AL
                JNZ     SHORT cga_srh_row_advance
cga_srh_right_chk:
                PUSH    CX
                SUB     CL, 8
                NEG     CL
                MOV     DL, 0FFH
                XOR     AL, AL
                SHR     DX, CL
                AND     DL, ES:[DI]
                SHR     AX, CL
                OR      AL, DL
                POP     CX
                STOSB
cga_srh_row_advance:
                POP     DX
                POP     DI
                MOV     AX, 2000H
                XOR     DI, AX
                TEST    DI, AX
                JNZ     SHORT cga_srh_no_wrap
                ADD     DI, 50H
cga_srh_no_wrap:
                POP     SI
                POP     BP
                MOV     AX, cs:[01425H]
                ADD     BP, AX
                ADD     SI, AX
                PUSH    BP
                PUSH    SI
                PUSH    DI
                DEC     BYTE PTR cs:[01439H]
                JZ      SHORT cga_srh_done
                JMP     cga_srh_row_top
cga_srh_done:
                ADD     SP, 6
                JMP     cga_sprite_blit_epilogue

; ============================================================================
; cga_sprite_row_vhflip -- row engine for vhflip blits (V + H reversed).
; chunk:0x137D..0x141B. Same as hflip but SUB BP/SI per row.
; ============================================================================
cga_sprite_row_vhflip:
                PUSH    BP
                PUSH    SI
                PUSH    DI
                MOV     BX, 0143AH
                MOV     CL, CH
                SUB     CL, 8
                NEG     CL
cga_srvh_row_top:
                PUSH    DX
                MOV     CH, DH
                XOR     AH, AH
                MOV     DH, 0FFH
                MOV     AL, cs:[01436H]
                OR      AL, AL
                JZ      SHORT cga_srvh_no_left
                MOV     AL, ds:[BP+1]
                XLAT    BYTE PTR CS:[BX]
                MOV     DH, AL
                MOV     AL, [SI+1]
                XLAT    BYTE PTR CS:[BX]
                MOV     AH, AL
                OR      CH, CH
                JZ      SHORT cga_srvh_right_chk
cga_srvh_no_left:
                SUB     CL, 8
                NEG     CL
                MOV     AL, ds:[BP+0]
                DEC     BP
                XLAT    BYTE PTR CS:[BX]
                MOV     DL, AL
                ROR     DX, CL
                AND     DL, ES:[DI]
                LODSB
                XLAT    BYTE PTR CS:[BX]
                SUB     SI, 2
                ROR     AX, CL
                OR      AL, DL
                STOSB
                SUB     CL, 8
                NEG     CL
                SHR     AH, CL
                SHR     DH, CL
                DEC     CH
                JNZ     SHORT cga_srvh_no_left
                MOV     AL, cs:[01435H]
                OR      AL, AL
                JNZ     SHORT cga_srvh_row_advance
cga_srvh_right_chk:
                PUSH    CX
                SUB     CL, 8
                NEG     CL
                MOV     DL, 0FFH
                XOR     AL, AL
                SHR     DX, CL
                AND     DL, ES:[DI]
                SHR     AX, CL
                OR      AL, DL
                POP     CX
                STOSB
cga_srvh_row_advance:
                POP     DX
                POP     DI
                MOV     AX, 2000H
                XOR     DI, AX
                TEST    DI, AX
                JNZ     SHORT cga_srvh_no_wrap
                ADD     DI, 50H
cga_srvh_no_wrap:
                POP     SI
                POP     BP
                MOV     AX, cs:[01425H]
                SUB     BP, AX
                SUB     SI, AX
                PUSH    BP
                PUSH    SI
                PUSH    DI
                DEC     BYTE PTR cs:[01439H]
                JZ      SHORT cga_srvh_done
                JMP     cga_srvh_row_top
cga_srvh_done:
                ADD     SP, 6

; ============================================================================
; cga_sprite_blit_epilogue -- shared tear-down for all 4 sprite-row cores
; AND for cga_blit_sprite_clipped's clip-rejected early exit.
; chunk:0x141C..0x1424 (9 bytes)
; ============================================================================
cga_sprite_blit_epilogue:
                POP     DS
                POP     ES
                POP     DI
                POP     SI
                ADD     SP, 0AH
                POP     BP
                RETF

; ============================================================================
; Sprite-clip state globals + bit-reverse LUT.
; chunk:0x1425..0x1539
; ============================================================================
g_wCgaSpriteClipStride          DW 0           ; 0x1425
g_apfnCgaSpriteFlipDispatch     LABEL WORD     ; 0x1427 -- 4-entry function table
                DW      011E7H                  ; cga_sprite_row_noflip
                DW      01261H                  ; cga_sprite_row_vflip
                DW      012DBH                  ; cga_sprite_row_hflip
                DW      0137DH                  ; cga_sprite_row_vhflip
g_wCgaSpriteClipSrcSeg          DW 0           ; 0x142F
g_wCgaSpriteClipSrcOff          DW 0           ; 0x1431
g_wCgaSpriteClipLeftSkip        DW 0           ; 0x1433
g_bCgaSpriteClipPartialRightFlag DB 0          ; 0x1435
g_bCgaSpriteClipPartialLeftFlag DB 0           ; 0x1436
g_bCgaSpriteFlipFlags           DB 0           ; 0x1437
                DB      0                       ; 0x1438 -- unnamed padding byte
g_bCgaSpriteRowCounter          DB 0           ; 0x1439

; ----------------------------------------------------------------------------
; g_abCgaPixelBitReverseLut -- 256-byte XLAT table mapping a 4-pixel
; CGA byte (AB|CD|EF|GH) to its reverse (HG|FE|DC|BA). Used by the
; hflip / vhflip cores via XLAT CS:[BX].
; ----------------------------------------------------------------------------
g_abCgaPixelBitReverseLut LABEL BYTE
                DB 000H, 040H, 080H, 0C0H, 010H, 050H, 090H, 0D0H
                DB 020H, 060H, 0A0H, 0E0H, 030H, 070H, 0B0H, 0F0H
                DB 004H, 044H, 084H, 0C4H, 014H, 054H, 094H, 0D4H
                DB 024H, 064H, 0A4H, 0E4H, 034H, 074H, 0B4H, 0F4H
                DB 008H, 048H, 088H, 0C8H, 018H, 058H, 098H, 0D8H
                DB 028H, 068H, 0A8H, 0E8H, 038H, 078H, 0B8H, 0F8H
                DB 00CH, 04CH, 08CH, 0CCH, 01CH, 05CH, 09CH, 0DCH
                DB 02CH, 06CH, 0ACH, 0ECH, 03CH, 07CH, 0BCH, 0FCH
                DB 001H, 041H, 081H, 0C1H, 011H, 051H, 091H, 0D1H
                DB 021H, 061H, 0A1H, 0E1H, 031H, 071H, 0B1H, 0F1H
                DB 005H, 045H, 085H, 0C5H, 015H, 055H, 095H, 0D5H
                DB 025H, 065H, 0A5H, 0E5H, 035H, 075H, 0B5H, 0F5H
                DB 009H, 049H, 089H, 0C9H, 019H, 059H, 099H, 0D9H
                DB 029H, 069H, 0A9H, 0E9H, 039H, 079H, 0B9H, 0F9H
                DB 00DH, 04DH, 08DH, 0CDH, 01DH, 05DH, 09DH, 0DDH
                DB 02DH, 06DH, 0ADH, 0EDH, 03DH, 07DH, 0BDH, 0FDH
                DB 002H, 042H, 082H, 0C2H, 012H, 052H, 092H, 0D2H
                DB 022H, 062H, 0A2H, 0E2H, 032H, 072H, 0B2H, 0F2H
                DB 006H, 046H, 086H, 0C6H, 016H, 056H, 096H, 0D6H
                DB 026H, 066H, 0A6H, 0E6H, 036H, 076H, 0B6H, 0F6H
                DB 00AH, 04AH, 08AH, 0CAH, 01AH, 05AH, 09AH, 0DAH
                DB 02AH, 06AH, 0AAH, 0EAH, 03AH, 07AH, 0BAH, 0FAH
                DB 00EH, 04EH, 08EH, 0CEH, 01EH, 05EH, 09EH, 0DEH
                DB 02EH, 06EH, 0AEH, 0EEH, 03EH, 07EH, 0BEH, 0FEH
                DB 003H, 043H, 083H, 0C3H, 013H, 053H, 093H, 0D3H
                DB 023H, 063H, 0A3H, 0E3H, 033H, 073H, 0B3H, 0F3H
                DB 007H, 047H, 087H, 0C7H, 017H, 057H, 097H, 0D7H
                DB 027H, 067H, 0A7H, 0E7H, 037H, 077H, 0B7H, 0F7H
                DB 00BH, 04BH, 08BH, 0CBH, 01BH, 05BH, 09BH, 0DBH
                DB 02BH, 06BH, 0ABH, 0EBH, 03BH, 07BH, 0BBH, 0FBH
                DB 00FH, 04FH, 08FH, 0CFH, 01FH, 05FH, 09FH, 0DFH
                DB 02FH, 06FH, 0AFH, 0EFH, 03FH, 07FH, 0BFH, 0FFH

; ============================================================================
; cga_blit_rect_unrolled_unused -- 7x-unrolled rect blit. Vtable slot 30.
; chunk:0x153A..0x15FA
; The vtable entry is set but the function appears unreferenced from host
; code in this build (presumably superseded by cga_present_rect).
; ============================================================================
cga_blit_rect_unrolled_unused PROC FAR
                PUSH    BP
                MOV     BP, SP
                PUSH    SI
                PUSH    DI
                PUSH    DS
                MOV     DS, cs:[0DEH]
                MOV     DI, [BP+0AH]
                SHL     DI, 1
                MOV     DI, ds:[DI].pRow_offset_lut
                MOV     AX, [BP+8]
                SHR     AX, 1
                SHR     AX, 1
                ADD     DI, AX
                MOV     BP, [BP+6]
                MOV     ES, ds:[GfxContext.wGfxBlitDstPage]
                MOV     DX, [BP+8]
                MOV     BX, [BP+6]
                SHR     BX, 1
                SHR     BX, 1
                MOV     SI, [BP+2]
                MOV     DS, [BP+0]
                MOV     BP, 50H
                SUB     BP, BX
                SHR     BX, 1
                MOV     AX, 2000H
cga_bru_blk0:
                MOV     CX, BX
                REP     MOVSW
                ADD     DI, BP
                XOR     DI, AX
                TEST    DI, AX
                JZ      SHORT cga_bru_blk0_keep
                SUB     DI, 50H
cga_bru_blk0_keep:
                DEC     DX
                JZ      SHORT cga_bru_done
                MOV     CX, BX
                REP     MOVSW
                ADD     DI, BP
                XOR     DI, AX
                TEST    DI, AX
                JZ      SHORT cga_bru_blk1_keep
                SUB     DI, 50H
cga_bru_blk1_keep:
                DEC     DX
                JZ      SHORT cga_bru_done
                MOV     CX, BX
                REP     MOVSW
                ADD     DI, BP
                XOR     DI, AX
                TEST    DI, AX
                JZ      SHORT cga_bru_blk2_keep
                SUB     DI, 50H
cga_bru_blk2_keep:
                DEC     DX
                JZ      SHORT cga_bru_done
                MOV     CX, BX
                REP     MOVSW
                ADD     DI, BP
                XOR     DI, AX
                TEST    DI, AX
                JZ      SHORT cga_bru_blk3_keep
                SUB     DI, 50H
cga_bru_blk3_keep:
                DEC     DX
                JZ      SHORT cga_bru_done
                MOV     CX, BX
                REP     MOVSW
                ADD     DI, BP
                XOR     DI, AX
                TEST    DI, AX
                JZ      SHORT cga_bru_blk4_keep
                SUB     DI, 50H
cga_bru_blk4_keep:
                DEC     DX
                JZ      SHORT cga_bru_done
                MOV     CX, BX
                REP     MOVSW
                ADD     DI, BP
                XOR     DI, AX
                TEST    DI, AX
                JZ      SHORT cga_bru_blk5_keep
                SUB     DI, 50H
cga_bru_blk5_keep:
                DEC     DX
                JZ      SHORT cga_bru_done
                MOV     CX, BX
                REP     MOVSW
                ADD     DI, BP
                XOR     DI, AX
                TEST    DI, AX
                JZ      SHORT cga_bru_blk6_keep
                SUB     DI, 50H
cga_bru_blk6_keep:
                DEC     DX
                JNZ     SHORT cga_bru_blk0
cga_bru_done:
                POP     DS
                POP     DI
                POP     SI
                POP     BP
                RETF
cga_blit_rect_unrolled_unused ENDP

; ============================================================================
; cga_sprite_pool_finalize -- pack a sprite pool, freeing tail memory.
; chunk:0x15FB..0x1653. Vtable slot 31.
; ============================================================================
cga_sprite_pool_finalize PROC FAR
                PUSH    BP
                MOV     BP, SP
                PUSH    DI
                PUSH    SI
                MOV     BP, [BP+6]
                MOV     BX, [BP+0]
                PUSH    BP
                MOV     AX, [BX]
                PUSH    AX
                MOV     ES, AX
                XOR     DI, DI
                XOR     SI, SI
                XOR     DX, DX
cga_spf_loop:
                MOV     BX, [BP+0]
                ADD     BP, 2
                OR      BX, BX
                JZ      SHORT cga_spf_free
                MOV     AX, ES
                MOV     [BX], AX
                MOV     [BX+2], DI
                MOV     AX, [BX+6]
                MUL     BYTE PTR [BX+8]
                SHR     AX, 1
                SHR     AX, 1
                MOV     CX, AX
                PUSH    DS
                MOV     BX, ES
                MOV     DS, BX
                REP     MOVSB
                POP     DS
                ADD     SI, AX
                ADD     DX, AX
                JMP     SHORT cga_spf_loop
cga_spf_free:
                POP     ES
                MOV     BX, DX
                ADD     BX, 0FH
                SHR     BX, 1
                SHR     BX, 1
                SHR     BX, 1
                SHR     BX, 1
                MOV     AH, 4AH
                INT     21H                     ; DOS realloc
                POP     AX
                POP     SI
                POP     DI
                POP     BP
                RETF
cga_sprite_pool_finalize ENDP

; ============================================================================
; cga_dos_freemem_block_unused -- INT 21h/AH=49h on a far segment.
; chunk:0x1654..0x1662. Vtable slot 32. Apparently unreferenced.
; ============================================================================
cga_dos_freemem_block_unused PROC FAR
                PUSH    BP
                MOV     BP, SP
                MOV     BP, [BP+6]
                MOV     ES, [BP+0]
                MOV     AH, 49H
                INT     21H
                POP     BP
                RETF
cga_dos_freemem_block_unused ENDP

; ============================================================================
; cga_blit_sprite_simple -- vtable slot 33, structurally a near-clone of
; cga_blit_sprite_clipped, but operating against a *separate* set of
; sprite-state globals at 0x183B..0x1847. Has the same epilogue
; structure (POP DS/ES/DI/SI; ADD SP,0Ah; POP BP; RETF) as
; cga_sprite_blit_epilogue but inlined locally rather than jumped to.
; chunk:0x1663..0x183A
; ============================================================================
cga_blit_sprite_simple PROC FAR
                PUSH    BP
                MOV     BP, SP
                SUB     SP, 0AH
                PUSH    SI
                PUSH    DI
                PUSH    ES
                PUSH    DS
                MOV     SI, [BP+6]
                MOV     DI, BP
                SUB     DI, 0AH
                MOV     AX, DS
                MOV     ES, AX
                MOV     CX, 5
                REP     MOVSW
                MOV     DS, cs:[0DEH]
                MOV     AX, ds:[GfxContext.wGfxBlitDstPage]
                MOV     ES, AX
                MOV     AL, [BP+0CH]
                MOV     cs:[01845H], AL
                MOV     BX, [BP+0AH]
                SHL     BX, 1
                JNS     SHORT cga_bss_y_pos
                SAR     BX, 1
                NEG     BX
                MOV     cs:[01841H], BX
                XOR     DI, DI
                JMP     SHORT cga_bss_y_done
cga_bss_y_pos:
                MOV     WORD PTR cs:[01841H], 0
                MOV     DI, ds:[BX].pRow_offset_lut
cga_bss_y_done:
                MOV     AX, [BP+8]
                MOV     CH, AL
                SAR     AX, 1
                SAR     AX, 1
                ADD     DI, AX
                AND     CH, 3
                SHL     CH, 1
                MOV     AX, [BP-4]
                MOV     DX, AX
                SHR     AX, 1
                SHR     AX, 1
                MOV     cs:[0183BH], AX
                ADD     DX, 3
                SHR     DX, 1
                SHR     DX, 1
                MOV     DH, DL
                MOV     AL, [BP-2]
                MOV     cs:[01847H], AL
                MOV     AX, [BP-0AH]
                MOV     cs:[0183DH], AX
                MOV     SI, [BP-8]
                MOV     AX, [BP-6]
                MOV     cs:[0183FH], AX
                XOR     AX, AX
                MOV     cs:[01843H], AL
                MOV     cs:[01844H], AL
                MOV     AL, ds:[GfxContext.bClip_enabled]
                OR      AL, AL
                JNZ     SHORT cga_bss_clip
                JMP     cga_bss_setup_row
cga_bss_clip:
                MOV     AX, ds:[GfxContext.nClip_xmax]
                INC     AX
                MOV     BX, [BP+8]
                ADD     BX, [BP-4]
                SUB     AX, BX
                JG      SHORT cga_bss_r_ok
                NEG     AX
                CMP     AX, [BP-4]
                JL      SHORT cga_bss_r_part
                JMP     cga_bss_exit
cga_bss_r_part:
                SHR     AX, 1
                SHR     AX, 1
                SUB     DH, AL
                MOV     BYTE PTR cs:[01843H], 1
cga_bss_r_ok:
                MOV     AX, [BP+8]
                SUB     AX, ds:[GfxContext.nClip_xmin]
                JNS     SHORT cga_bss_l_ok
                MOV     BX, AX
                ADD     AX, [BP-4]
                JG      SHORT cga_bss_l_part
                JMP     cga_bss_exit
cga_bss_l_part:
                MOV     BYTE PTR cs:[01844H], 1
                NEG     BX
                ADD     BX, 3
                SHR     BX, 1
                SHR     BX, 1
                SUB     DH, BL
                ADD     DI, BX
                ADD     SI, BX
                ADD     cs:[0183FH], BX
cga_bss_l_ok:
                MOV     AX, [BP+0AH]
                ADD     AX, [BP-2]
                SUB     AX, ds:[GfxContext.nClip_ymax]
                JS      SHORT cga_bss_b_ok
                CMP     AX, [BP-2]
                JS      SHORT cga_bss_b_part
                JMP     cga_bss_exit
cga_bss_b_part:
                DEC     AL
                SUB     cs:[01847H], AL
cga_bss_b_ok:
                MOV     AX, ds:[GfxContext.nClip_ymin]
                SUB     AX, [BP+0AH]
                JS      SHORT cga_bss_setup_row
                CMP     AX, [BP-2]
                JS      SHORT cga_bss_t_part
                JMP     cga_bss_exit
cga_bss_t_part:
                SUB     cs:[01847H], AL
                MOV     BX, AX
                SUB     AX, cs:[01841H]
                SHR     AX, 1
                JNC     SHORT cga_bss_t_xor
                XOR     DI, 2000H
                TEST    DI, 2000H
                JNZ     SHORT cga_bss_t_xor
                INC     AX
cga_bss_t_xor:
                SHL     AX, 1
                SHL     AX, 1
                SHL     AX, 1
                SHL     AX, 1
                ADD     DI, AX
                SHL     AX, 1
                SHL     AX, 1
                ADD     DI, AX
                MOV     AX, BX
                MUL     BYTE PTR cs:[0183BH]
                ADD     SI, AX
                ADD     cs:[0183FH], AX
cga_bss_setup_row:
                MOV     DS, cs:[0183DH]
                MOV     BP, cs:[0183FH]
                PUSH    BP
                PUSH    SI
                PUSH    DI
cga_bss_row_top:
                MOV     DL, DH
                XOR     AH, AH
                MOV     BH, 0FFH
                TEST    BYTE PTR cs:[01844H], 1
                JZ      SHORT cga_bss_no_l
                XOR     BH, BH
                MOV     AH, [SI-1]
                OR      DL, DL
                JZ      SHORT cga_bss_r_chk
cga_bss_no_l:
                MOV     CL, CH
                XOR     BL, BL
                INC     BP
                ROR     BX, CL
                AND     BL, ES:[DI]
                LODSB
                ROR     AX, CL
                OR      AL, BL
                STOSB
                SUB     CL, 8
                NEG     CL
                SHR     AH, CL
                SHR     BH, CL
                DEC     DL
                JNZ     SHORT cga_bss_no_l
                TEST    BYTE PTR cs:[01843H], 1
                JNZ     SHORT cga_bss_row_step
cga_bss_r_chk:
                MOV     CL, CH
                MOV     BL, 0FFH
                XOR     AL, AL
                SHR     BX, CL
                AND     BL, ES:[DI]
                SHR     AX, CL
                OR      AL, BL
                STOSB
cga_bss_row_step:
                POP     DI
                MOV     AX, 2000H
                XOR     DI, AX
                TEST    DI, AX
                JNZ     SHORT cga_bss_no_wrap
                ADD     DI, 50H
cga_bss_no_wrap:
                POP     SI
                POP     BP
                MOV     AX, cs:[0183BH]
                ADD     BP, AX
                ADD     SI, AX
                PUSH    BP
                PUSH    SI
                PUSH    DI
                DEC     BYTE PTR cs:[01847H]
                JNZ     SHORT cga_bss_row_top
                ADD     SP, 6
cga_bss_exit:
                POP     DS
                POP     ES
                POP     DI
                POP     SI
                ADD     SP, 0AH
                POP     BP
                RETF
cga_blit_sprite_simple ENDP

; ============================================================================
; Sprite-simple state globals.
; chunk:0x183B..0x184B (17 bytes, all zero on disk)
; ============================================================================
g_wCgaSpriteSimpleStride            DW 0       ; 0x183B
g_wCgaSpriteSimpleSrcSeg            DW 0       ; 0x183D
g_wCgaSpriteSimpleSrcOff            DW 0       ; 0x183F
g_wCgaSpriteSimpleLeftSkip          DW 0       ; 0x1841
g_bCgaSpriteSimplePartialRightFlag  DB 0       ; 0x1843
g_bCgaSpriteSimplePartialLeftFlag   DB 0       ; 0x1844
g_bCgaSpriteSimpleFlipFlagsUnread   DB 0       ; 0x1845 -- written w/ caller flags
                                                ;          (slot 33 [BP+0Ch]) but never
                                                ;          read; flip path absent in simple
                DB      0                       ; 0x1846 -- unnamed padding
g_bCgaSpriteSimpleRowCounter        DB 0       ; 0x1847
g_wCgaImagePackInnerCount           DW 0       ; 0x1848
g_wCgaPaletteLutBaseCache           DW 0       ; 0x184A

; ============================================================================
; cga_pack_scanline_via_palette_lut -- pack a chunky (1 byte per pixel,
; 4-bit colour-index) scanline into CGA 2-bits-per-pixel using a per-row
; palette LUT (cached at g_wCgaPaletteLutBaseCache).
; chunk:0x184C..0x1914.
;
; Register-passed args, no BP frame:
;   DS:SI -- source scanline (chunky, one byte per pixel)
;   ES:DI -- destination CGA byte stream
;   CX    -- pair count; each iteration consumes 8 source bytes and
;            writes 2 destination bytes (4 pixels per dest byte, 2
;            dest bytes per pair iteration)
;   DX    -- row index (low bit selects which 2-bit nibble of each
;            palette-LUT entry to consume -- the LUT stores one byte
;            per chunky colour with two CGA colours packed in)
;
; The body is the same 4-pixel pack repeated four times (hence
; "p0_nosh" .. "p3_nosh" labels). Loops on CX, returns when CX
; reaches 0.
;
; Called per-row by cga_blit_chunky_rect_to_video.
; ============================================================================
cga_pack_scanline_via_palette_lut PROC FAR
                PUSH    BP
                MOV     AX, GfxContext.pPaletteScratchBuf ; B8 9E 01  palette-scratch field offset within scratch
                ADD     AX, cs:[0E0H]
                MOV     BP, AX
                MOV     AX, [BP+0]
                MOV     cs:[0184AH], AX
cga_psv_pair_loop:
                XOR     BX, BX
                LODSB
                MOV     BH, AL
                SHR     AL, 1
                SHR     AL, 1
                SHR     AL, 1
                SHR     AL, 1
                AND     AX, 0FH
                MOV     BP, AX
                ADD     BP, cs:[0184AH]
                MOV     AL, [BP+0]
                TEST    DX, 1
                JZ      SHORT cga_psv_p0_nosh
                SHR     AL, 1
                SHR     AL, 1
                SHR     AL, 1
                SHR     AL, 1
cga_psv_p0_nosh:
                AND     AL, 3
                OR      BL, AL
                SHL     BL, 1
                SHL     BL, 1
                MOV     AL, BH
                AND     AX, 0FH
                MOV     BP, AX
                ADD     BP, cs:[0184AH]
                MOV     AL, [BP+0]
                TEST    DX, 1
                JZ      SHORT cga_psv_p1_nosh
                SHR     AL, 1
                SHR     AL, 1
                SHR     AL, 1
                SHR     AL, 1
cga_psv_p1_nosh:
                SHR     AL, 1
                SHR     AL, 1
                AND     AL, 3
                OR      BL, AL
                SHL     BL, 1
                SHL     BL, 1
                LODSB
                MOV     BH, AL
                SHR     AL, 1
                SHR     AL, 1
                SHR     AL, 1
                SHR     AL, 1
                AND     AX, 0FH
                MOV     BP, AX
                ADD     BP, cs:[0184AH]
                MOV     AL, [BP+0]
                TEST    DX, 1
                JZ      SHORT cga_psv_p2_nosh
                SHR     AL, 1
                SHR     AL, 1
                SHR     AL, 1
                SHR     AL, 1
cga_psv_p2_nosh:
                AND     AL, 3
                OR      BL, AL
                SHL     BL, 1
                SHL     BL, 1
                MOV     AL, BH
                AND     AX, 0FH
                MOV     BP, AX
                ADD     BP, cs:[0184AH]
                MOV     AL, [BP+0]
                TEST    DX, 1
                JZ      SHORT cga_psv_p3_nosh
                SHR     AL, 1
                SHR     AL, 1
                SHR     AL, 1
                SHR     AL, 1
cga_psv_p3_nosh:
                SHR     AL, 1
                SHR     AL, 1
                AND     AL, 3
                OR      BL, AL
                MOV     AL, BL
                STOSB
                DEC     CX
                JZ      SHORT cga_psv_done
                JMP     cga_psv_pair_loop
cga_psv_done:
                POP     BP
                RETF
cga_pack_scanline_via_palette_lut ENDP

; ============================================================================
; cga_image_pack_loop_planar -- per-image driver around the chunky->CGA
; packer. Iterates rows, normalising the (seg, off) far pointers each
; iteration so the SHR-by-4 arithmetic that splits an unaligned far
; offset across seg+off doesn't lose precision on long source/dest
; spans.
; chunk:0x1915..0x19AF.
;
; ABI (__cdecl16far, called via PUSH CS + near CALL from
; cga_image_records_install):
;   [BP+6]    src_off
;   [BP+8]    src_seg
;   [BP+0Ah]  dst_off
;   [BP+0Ch]  dst_seg
;   [BP+0Eh]  width_pixels    (will be >>2 to get CX = pair_count)
;   [BP+10h]  row_count
;   [BP+12h]  starting_row_parity (passed by ref via stack slot;
;                                  read+written so caller can XOR
;                                  the LSB to toggle dither phase)
;
; Calls cga_pack_scanline_via_palette_lut once per row.
; ============================================================================
cga_image_pack_loop_planar PROC FAR
                PUSH    BP
                MOV     BP, SP
                PUSH    DS
                PUSH    SI
                PUSH    ES
                PUSH    DI
                TEST    BYTE PTR [BP+10H], 1
                JZ      SHORT cga_ipl_no_odd
                XOR     BYTE PTR [BP+12H], 1
cga_ipl_no_odd:
                MOV     AX, [BP+0EH]
                SHR     AX, 1
                SHR     AX, 1
                MOV     cs:[01848H], AX
                MOV     AX, [BP+0AH]
                MOV     BX, AX
                AND     BX, 0FH
                MOV     SI, BX
                SHR     AX, 1
                SHR     AX, 1
                SHR     AX, 1
                SHR     AX, 1
                ADD     AX, [BP+0CH]
                MOV     DS, AX
                MOV     AX, [BP+6]
                MOV     BX, AX
                AND     BX, 0FH
                MOV     DI, BX
                SHR     AX, 1
                SHR     AX, 1
                SHR     AX, 1
                SHR     AX, 1
                ADD     AX, [BP+8]
                MOV     ES, AX
                MOV     DX, [BP+12H]
                AND     DX, 1
                MOV     [BP+12H], DX
                ADD     DX, [BP+10H]
cga_ipl_row_loop:
                MOV     CX, cs:[01848H]
                PUSH    CS
                CALL    NEAR PTR cga_pack_scanline_via_palette_lut
                MOV     BX, DS
                MOV     AX, SI
                SHR     AX, 1
                SHR     AX, 1
                SHR     AX, 1
                SHR     AX, 1
                ADD     AX, BX
                MOV     DS, AX
                MOV     AX, SI
                AND     AX, 0FH
                MOV     SI, AX
                MOV     BX, ES
                MOV     AX, DI
                SHR     AX, 1
                SHR     AX, 1
                SHR     AX, 1
                SHR     AX, 1
                ADD     AX, BX
                MOV     ES, AX
                MOV     AX, DI
                AND     AX, 0FH
                MOV     DI, AX
                SUB     DX, 1
                CMP     DX, [BP+12H]
                JNZ     SHORT cga_ipl_row_loop
                POP     DI
                POP     ES
                POP     SI
                POP     DS
                POP     BP
                RETF
cga_image_pack_loop_planar ENDP

; ============================================================================
; cga_image_pack_transparency_mask -- pack a per-pixel transparency mask
; from a chunky-4bpp source into a CGA-2bpp mask byte stream.
; chunk:0x19B0..0x1A17.
;
; For each source word (4 pixels worth, 4 bits per pixel), looks at the
; four nibble fields independently. If a nibble is nonzero (opaque), the
; corresponding 2-bit slot in the dest byte is set to 11; if zero
; (transparent), it stays 00. The byte is then NOTed -- so transparent
; pixels end up 11 in the mask, opaque ones 00, matching the "AND the
; mask with framebuffer, OR the colour bits in" idiom the sprite cores
; expect.
;
; ABI (__cdecl16far, near-called via PUSH CS from
; cga_image_records_install):
;   [BP+6]   src_off
;   [BP+8]   src_seg
;   [BP+0Ah] dst_off
;   [BP+0Ch] dst_seg
;   [BP+0Eh] pair_count (each iteration consumes one word and writes one byte)
; ============================================================================
cga_image_pack_transparency_mask PROC FAR
                PUSH    BP
                MOV     BP, SP
                PUSH    DS
                PUSH    SI
                PUSH    ES
                PUSH    DI
                MOV     AX, [BP+0AH]
                MOV     BX, AX
                AND     BX, 0FH
                MOV     SI, BX
                SHR     AX, 1
                SHR     AX, 1
                SHR     AX, 1
                SHR     AX, 1
                ADD     AX, [BP+0CH]
                MOV     DS, AX
                MOV     AX, [BP+6]
                MOV     BX, AX
                AND     BX, 0FH
                MOV     DI, BX
                SHR     AX, 1
                SHR     AX, 1
                SHR     AX, 1
                SHR     AX, 1
                ADD     AX, [BP+8]
                MOV     ES, AX
                MOV     CX, [BP+0EH]
cga_iptm_pixel:
                XOR     BX, BX
                LODSW
                TEST    AX, 0F000H
                JZ      SHORT cga_iptm_no_hi
                OR      BL, 0CH
cga_iptm_no_hi:
                TEST    AX, 0F00H
                JZ      SHORT cga_iptm_no_mh
                OR      BL, 3
cga_iptm_no_mh:
                TEST    AX, 0F0H
                JZ      SHORT cga_iptm_no_ml
                OR      BL, 0C0H
cga_iptm_no_ml:
                TEST    AX, 0FH
                JZ      SHORT cga_iptm_no_lo
                OR      BL, 30H
cga_iptm_no_lo:
                MOV     AL, BL
                NOT     AX
                STOSB
                LOOP    SHORT cga_iptm_pixel
                POP     DI
                POP     ES
                POP     SI
                POP     DS
                POP     BP
                RETF
cga_image_pack_transparency_mask ENDP

; ============================================================================
; cga_capture_rect -- copy a rect from the back-buffer (g_wCgaFramebufferSeg)
; to the visible/front buffer (g_wCgaBlitSrcSeg, B800), inverse direction
; of cga_present_rect. Same row-LUT + odd/even byte-pair pattern as
; cga_present_rect / cga_save_rect_to_buffer.
; chunk:0x1A18..0x1A7B. Vtable slot 9.
;
; ABI (__cdecl16far):
;   [BP+6]    x0
;   [BP+8]    y0
;   [BP+0Ah]  x1
;   [BP+0Ch]  row_count
; ============================================================================
cga_capture_rect PROC FAR
                PUSH    BP
                MOV     BP, SP
                PUSH    SI
                PUSH    DI
                PUSH    DS
                PUSH    ES
                MOV     DS, cs:[0DEH]
                MOV     SI, [BP+6]
                MOV     AX, SI
                SHR     SI, 1
                SHR     SI, 1
                MOV     BX, [BP+0AH]
                ADD     BX, AX
                SHR     BX, 1
                SHR     BX, 1
                SUB     BX, SI
                CMP     BX, 50H
                JZ      SHORT cga_cr_skip_inc
                INC     BX
cga_cr_skip_inc:
                MOV     AX, BX
                SHR     BX, 1
                AND     AX, 1
                JZ      SHORT cga_cr_even
                INC     BX
cga_cr_even:
                MOV     DX, [BP+0CH]
                MOV     BP, [BP+8]
                SHL     BP, 1
                LEA     BP, [BP].pRow_offset_lut
                ADD     BP, cs:[0E0H]
                MOV     AX, ds:[GfxContext.wVgaFrontPageBase]
                MOV     ES, AX
                MOV     AX, ds:[GfxContext.wVgaPage2Base]
                MOV     DS, AX
                MOV     AX, SI
cga_cr_row:
                MOV     CX, BX
                MOV     DI, [BP+0]
                ADD     DI, AX
                MOV     SI, DI
                REP     MOVSW
                ADD     BP, 2
                DEC     DX
                JNZ     SHORT cga_cr_row
                POP     ES
                POP     DS
                POP     DI
                POP     SI
                POP     BP
                RETF
cga_capture_rect ENDP

                END     _start
