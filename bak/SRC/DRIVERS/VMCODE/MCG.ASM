; ============================================================================
; Vmcode.OVL.MCG -- MCGA (mode-13h chunky 256-colour) video driver chunk
;
; Smallest of the eight Vmcode.OVL adapter chunks.
; Shipped with "Betrayal at Krondor" (Dynamix / Sierra, 1993).
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
; This file is the MCG driver -- the path used when the host detects an
; MCGA-capable adapter (PS/2 MCGA cards from 1987 onwards, but in
; practice almost always a VGA card running BIOS mode 13h). It is the
; structural simplification of the rest of the family: mode 13h gives
; the CPU a single linear 320x200 plane at A000:0000 with one byte per
; pixel, so the driver does no plane-mask juggling, no sequencer / GC /
; CRTC programming, and no bank-switch arithmetic. The blit primitives
; collapse to plain MOVSB/MOVSW loops and the palette helpers stream
; RGB bytes to port 0x3C9.
;
; The engine communicates with the driver through a vtable of far
; function pointers (see "How the engine dispatches" below): 41 slots
; (5 fewer than the planar chunks; the planar plane-fill / mask-set /
; latch-clear slots have no purpose in chunky mode). When a slot is
; invoked, this code translates the high-level request ("draw a line",
; "blit a sprite", "set the palette") into the mode-13h byte pattern.
;
; Roughly half this file is dispatch / mode-set / palette / clipping
; plumbing; the other half is rectangle and sprite blitters written
; as straight-line MOVS / STOS loops -- chunky 256-colour mode 13h is
; the easiest of the BAK video targets to drive.
; ----------------------------------------------------------------------------

; ----------------------------------------------------------------------------
; About the MCGA / mode-13h hardware
;
; "MCGA" = Multi-Color Graphics Array, IBM's PS/2-era integrated
; graphics subsystem (1987). MCGA is NOT a card -- it was soldered
; onto the planar of two specific IBM machines (PS/2 Model 25 and
; Model 30); no standalone ISA card was ever produced. On a 1993
; system running Betrayal at Krondor, the same mode-13h programming
; model is almost always being served by a VGA chip -- VGA is
; backward-compatible with MCGA at the I/O-port + DAC + INT 10h
; level, so a "mode-13h MCGA driver" runs unmodified on either chip.
; This file calls the path "MCGA" because that is the lowest common
; denominator the engine is targeting; in practice it is the VGA
; mode-13h path on most hardware.
; (Sources: IBM PS/2 HITR May 1988;
;  Ferraro Programmer's Guide §4.46.)
;
; What the chip presents to the CPU in mode 13h:
;
;   - A 64000-byte linear chunky framebuffer mapped at physical
;     0xA0000 (real-mode segment 0xA000, offset 0..0xF9FF). One byte
;     per pixel, 320 bytes per row, 200 rows. Pixel (x, y) lives at
;     offset y*320 + x. Single page only -- mode 13h on MCGA (and
;     VGA) has no hardware page-flipping; the rest of the 64 KiB
;     window at A000:FA00..A000:FFFF is undefined garbage on MCGA.
;     The driver's two "back buffers" are ordinary DOS-allocated RAM
;     segments (see mcg_init step 5), NOT a second hardware page.
;     Compare to CGA's 16 KiB bank-interleaved 2-bit framebuffer at
;     B800 -- mode 13h is the simplest possible PC graphics memory
;     model. (Sources: Abrash ch. 31; ch. 47.)
;
;   - A DAC (digital-to-analog converter, the INMOS IMS G171 chip on
;     real MCGA) reachable through four I/O ports, programmed as a
;     state machine:
;       0x3C6  -- read/write: 8-bit "pixel mask"; ANDed with every
;                  pixel index before palette lookup. Normal value:
;                  0xFF. The BIOS leaves it at 0xFF and this driver
;                  never touches it. (VGADOC VGAREGS.TXT.)
;       0x3C7  -- READ: DAC state register. Bits 0..1 only:
;                  0b00 = chip is in WRITE mode (last index set via
;                          0x3C8)
;                  0b11 = chip is in READ mode (last index set via
;                          this port)
;                  bits 2..7 are undefined.
;                 WRITE: sets the DAC's READ index and switches the
;                  chip to READ mode (subsequent reads of 0x3C9 will
;                  stream out R, G, B of the indexed entry).
;       0x3C8  -- read/write: sets the DAC's WRITE index and (on
;                  write) switches the chip to WRITE mode. Reading
;                  returns the current index (auto-incremented every
;                  third 0x3C9 access).
;       0x3C9  -- read/write: streams one byte per access; the chip
;                  has an internal 3-state counter that cycles
;                  R -> G -> B; after B the palette index auto-
;                  increments and the counter restarts at R. Each
;                  channel is **6 bits, not 8** -- the top 2 bits of
;                  every byte written here are dropped, so useful
;                  values are 0..63 (NOT 0..255; this trips up first-
;                  time VGA/MCGA programmers). The palette therefore
;                  stores 256 entries x 18 bits = 256 colours from a
;                  262,144-colour gamut.
;     A full 256-entry palette write is 768 bytes streamed to 0x3C9
;     after one index write to 0x3C8 (see mcg_dac_write_vsync).
;     (Sources: VGADOC VGAREGS.TXT for the register
;      map; INMOS IMS G171 datasheet for the chip-level cycle.)
;
;   - The CRTC's "Input Status Register #1" at port 0x3DA (read-only).
;     Two bits matter and they are DIFFERENT signals:
;       bit 0  -- "either vertical or horizontal retrace in progress"
;                  (display memory may be accessed by the PC). Useless
;                  for frame pacing -- toggles every scanline.
;       bit 3  -- "vertical retrace in progress" -- the bit you want
;                  for vblank synchronisation. mcg_dac_write_vsync
;                  polls this with mask 0x08 before reprogramming the
;                  DAC, so palette changes happen during the (~50 us)
;                  vblank window and don't flicker mid-frame.
;     Note: the IMS G171 chip itself does NOT stall DAC writes
;     during scan-out. If you write 0x3C9 mid-frame on a pixel that
;     is currently using the entry being updated, you get a visible
;     "snow dot" in the output -- vsync gating is the software's
;     responsibility, not the chip's.
;     (Sources: VGADOC VGAREGS.TXT bit
;      definitions; Abrash ch. 34 on the snow phenomenon.)
;
; What mode 13h does NOT have, that distinguishes it from VGA's other
; modes (and so from the planar drivers in this codebase):
;
;   - No plane select, no write modes 0..3, no read modes, no
;     latches, no bit-mask register, no set/reset, no raster ops --
;     direct CPU byte writes are the only path.
;   - No bank switching -- single 64000-byte page.
;   - No hardware page flipping (mode 13h on both MCGA and VGA).
;     The BIOS function INT 10h AX=05h "Set Active Page" is a no-op
;     in mode 13h. (Abrash ch. 47.)
;   - No programmable border / overscan colour. The MCGA cannot
;     generate a coloured border at all (the CGA-style 3D9h register
;     has no effect; the VGA Attribute Controller overscan register
;     at AC[11h] is honoured by VGA hardware but the overscan area
;     is effectively zero pixels in mode 13h). Code in this driver
;     that looks like it sets a border colour (see
;     mcg_dac_write_single_entry below, ex-"set_border_color") is
;     actually just a single-DAC-entry palette write -- the function
;     name is a CGA-era misnomer. (Ardent Tool of Capitalism
;     "PS/2 Video Programming".)
;
; For the full register-level reference, see VGADOC's VGAREGS.TXT,
; FreeVGA at http://www.osdever.net/FreeVGA/vga/colorreg.htm, or any
; VGA technical reference.
; ----------------------------------------------------------------------------

; ----------------------------------------------------------------------------
; How the engine dispatches into this chunk
;
; Vmcode.OVL is a flat archive of driver chunks; one chunk per
; supported adapter. The host engine:
;
;   1. Loads the selected chunk into a freshly-allocated segment.
;   2. Calls the chunk's `_start` (mcg_init) as a far function,
;      passing on the stack: a paragraph count for the driver's
;      private working segment and a far pointer to the host's
;      "service callback" table (PrintF-style errno, file I/O,
;      resource loading -- the things this code needs from the
;      host).
;   3. mcg_init copies the 19 host callbacks into a chunk-local
;      mirror at CS:0x0149, sets video mode 13h, allocates two
;      64000-byte off-screen pages from DOS for double-buffering,
;      builds the 200-row scanline-offset LUT, then returns
;      DX:SI = (CS, 0x00A9) -- a far pointer to the chunk's
;      vtable template at g_apfnMcgVtable.
;   4. The host stamps the chunk's load segment into every
;      segment-half of that template (41 slots * 4 bytes = 164
;      bytes) and copies the result into the global renderer
;      vtable in host RAM.
;   5. Every subsequent rendering call from the game is a far
;      CALL through that vtable -- never a direct CALL into this
;      file. The MCG driver thus only sees a stream of slot
;      invocations after init.
;
; Slot 0x00A9 layout overlaps the host-callback mirror:
;   on-disk bytes 0x0149..0x0194 are the tail of the 41-slot vtable
;   template (slot 40) plus 18 trailing far-pointer slots that all
;   point at the 1-byte RETF stub at 0x0195. At runtime the init
;   prologue's `MOV DI, 0x149 / REP MOVSW CX=0x26` overwrites those
;   76 bytes with the host's 19 callback far pointers. The "tail"
;   slots are therefore template placeholders -- never actually
;   used as vtable entries, just structural padding to give the
;   host-callback mirror a stable address.
;
; The RETF stub at 0x0195 is the catch-all "unimplemented in MCGA
; mode" sink; ~12 vtable slots point at it on disk.
;
; Slot calling convention: most slots are __cdecl16far (push args
; right-to-left, far call, caller cleans the stack). A handful of
; helpers (mcg_fill_pixel_run, mcg_fill_pixel_run_dither,
; mcg_slot37_helper, mcg_slot16_helper, mcg_slot38_helper,
; mcg_slot36_helper, the four sprite-row primitives) instead take
; register-passed args (or a hybrid of register + stack args) because
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
;   segment.
;
; - Memory accesses use one of three segments, depending on
;   what's being touched:
;     CS:  -- the chunk itself: vtable, scratch globals defined as
;             top-level DW slots after the init body (e.g.
;             g_wMcgChunkDataSeg @ 0x00A5), and the per-polygon /
;             per-sprite globals at 0x0370 / 0x0A03 / 0x0C48.
;     DS:  -- the chunk's "scratch DS", a private working segment
;             allocated `backbuffer_paragraphs/16` paragraphs past
;             the caller's DS (set up at mcg_init step 2). Every
;             function that needs the scratch reloads
;             `DS, cs:[g_wMcgChunkDataSeg]` (g_wMcgChunkDataSeg) on entry and
;             restores caller DS before returning. The scratch DS
;             contains the clip-rect block (offsets 0x03..0x0A),
;             colour bytes (0x0D..0x0F), the back-buffer / source /
;             framebuffer seg slots (0x10..0x18), the driver-state
;             byte (0x1D), the line-colour packed-word slot
;             (0x6BC), and the 200-entry scanline-offset LUT
;             (0x6F2..0x82B).
;     ES:  -- usually the framebuffer (0xA000) or the back-buffer;
;             function plates specify which.
;
; - Local labels inside a function are prefixed with a short
;   nickname for the enclosing function (e.g. `mcg_fpr_*` inside
;   mcg_fill_pixel_run, `mcg_srn_*` inside mcg_sprite_row_noflip).
;   Avoids collisions across functions without anonymous `@@:`
;   labels.
;
; - All accesses through `DS:[off]` go to the heap-allocated scratch
;   segment (see g_wMcgChunkDataSeg in mcg_init), not to CS. Where
;   numeric offsets happen to fall inside a code byte range (e.g.
;   the active-palette pointer at scratch:0x019E falls at the same
;   offset as mcg_fill_pixel_run's prologue in CS), the two are
;   independent memory locations -- nothing dead-code-as-storage.
; ----------------------------------------------------------------------------

; ----------------------------------------------------------------------------
; Scratch-DS layout (g_wMcgChunkDataSeg points here at runtime)
;
; The chunk's scratch segment is allocated by the host at load time
; (paragraph_count/16 paragraphs past the caller's DS, see mcg_init
; step 2). scratch_DS:0 points at the host engine's graphics-context
; struct, so all `DS:[off]` accesses below are reads/writes of that
; struct by offset. The struct is the shared TASM STRUC
; `GfxContext` in gfxctx.inc (INCLUDEd above), whose field names resolve
; to these exact offsets. The driver and the engine name the same byte
; differently (e.g. the back-buffer page seg the driver allocates lives
; at the offset the engine calls `wVgaPage1Base`); the field reference
; documents the offset's place in the engine struct. The
; MCG_SCRATCH_* -> GfxContext.<field> mapping:
;
;   MCG_SCRATCH_CLIP_ENABLED    0x003  GfxContext.bClip_enabled
;   MCG_SCRATCH_CLIP_LEFT       0x004  GfxContext.nClip_xmin
;   MCG_SCRATCH_CLIP_RIGHT      0x006  GfxContext.nClip_xmax
;   MCG_SCRATCH_CLIP_TOP        0x008  GfxContext.nClip_ymin
;   MCG_SCRATCH_CLIP_BOTTOM     0x00A  GfxContext.nClip_ymax
;   MCG_SCRATCH_GLYPH_FG        0x000  GfxContext.bText_fg_color
;   MCG_SCRATCH_GLYPH_BG        0x001  GfxContext.bText_bg_color
;   MCG_SCRATCH_GLYPH_TRANS     0x002  GfxContext.bText_style_flags
;   MCG_SCRATCH_SPAN_EVEN_COLOR 0x00D  GfxContext.bGfx_fill_color
;   MCG_SCRATCH_LINE_COLOR      0x00E  GfxContext.bGfx_outline_color
;   MCG_SCRATCH_SPAN_ODD_COLOR  0x00F  GfxContext.bGfx_dither_color
;   MCG_SCRATCH_BACKBUF_SEG     0x010  GfxContext.wVgaPage1Base
;   MCG_SCRATCH_BLIT_SRC_SEG    0x012  GfxContext.wVgaPage2Base
;   MCG_SCRATCH_FB_SEG          0x014  GfxContext.wVgaFrontPageBase
;   MCG_SCRATCH_BACKBUF_SEG2    0x016  GfxContext.wGfxBlitSrcPage
;   MCG_SCRATCH_VISIBLE_FB_SEG  0x018  GfxContext.wGfxBlitDstPage
;   MCG_SCRATCH_MODE_FLAG       0x01D  GfxContext.bVideoAdapter
;   MCG_SCRATCH_LOAD_COUNT      0x01F  GfxContext.bGfxRenderStateFlag
;   MCG_SCRATCH_MOUSE_ACTIVE    0x021  GfxContext.bActiveVgaMode
;   MCG_SCRATCH_PAL_PTR_OFF     0x19E  GfxContext.pPaletteScratchBuf
;   MCG_SCRATCH_PAL_PTR_SEG     0x1A0  GfxContext.pPaletteScratchBuf + 2 (seg half)
;   MCG_SCRATCH_LINE_COLOR_W    0x6BC  GfxContext.wTextureIdx
;   MCG_SCRATCH_ROW_LUT         0x6F2  GfxContext.pRow_offset_lut
;
; One offset has no clean field name and stays a local EQU below:
;   MCG_SCRATCH_DITHER_PARITY   0x02A  -- falls INSIDE GfxContext's
;       reserved hole pReserved_0x22 (0x22..0x33); the engine has no
;       named field there, so this driver-private dither-parity word is
;       kept as an offset literal rather than a fabricated field.
; ----------------------------------------------------------------------------
MCG_SCRATCH_DITHER_PARITY   EQU 002AH   ; ushort -- toggling parity for dither fill
                                        ; (inside GfxContext.pReserved_0x22 hole)

; Chunk-local globals live below in `.CODE` at fixed offsets and are
; accessed via `CS:[off]`. See the labelled DW slots after mcg_init.

; ----------------------------------------------------------------------------
; Chunk memory map (linear byte offsets):
;
; 0x0000..0x00A4  mcg_init
; 0x00A5..0x00A8  g_wMcgChunkDataSeg, g_wMcgBackbufferParagraphs
; 0x00A9..0x014C  g_apfnMcgVtable (41 slots)
; 0x014D..0x0194  g_apfnMcgHostCallbacksTail (18 dead slots)
; 0x0195          mcg_unimplemented_slot (RETF stub)
; 0x0196..0x01D9  mcg_fill_pixel_run_dither / mcg_fill_pixel_run
; 0x01DA..0x01F3  mcg_slot37_helper
; 0x01F4..0x0226  mcg_slot16_helper
; 0x0227..0x023B  mcg_slot38_helper
; 0x023C..0x027D  mcg_slot36_helper
; 0x027E..0x036F  mcg_draw_line
; 0x0370..0x0377  g_wMcgSpan* scratch globals
; 0x0378..0x0465  mcg_polygon_span_fill
; 0x0466..0x0467  alignment pad
; 0x0468..0x04A4  mcg_dac_write_vsync
; 0x04A5..0x04BB  mcg_dac_write_single_entry
; 0x04BC..0x04FD  mcg_palette_set
; 0x04FE..0x057B  mcg_palette_fade_blend
; 0x057C..0x05AE  mcg_image_list_measure
; 0x05AF..0x06A9  mcg_image_records_install
; 0x06AA..0x06FD  mcg_image_pack_nibble_or
; 0x06FE..0x0717  mcg_blit_sprite_noflip
; 0x0718..0x0781  mcg_blit_glyph_row
; 0x0782..0x07D7  mcg_save_rect_to_buffer
; 0x07D8..0x07E3  mcg_sprite_buffer_size
; 0x07E4..0x0839  mcg_rect_paste_from_buffer
; 0x083A..0x085B  mcg_getpixel
; 0x085C..0x087E  mcg_putpixel
; 0x087F..0x08C6  mcg_present_rect
; 0x08C7..0x090C  mcg_capture_rect
; 0x090D..0x0982  mcg_stretched_blit
; 0x0983..0x0A02  mcg_blit_chunky_nibble_pixels
; 0x0A03..0x0A04  g_nMcgSpriteClipRows
; 0x0A05..0x0A0C  g_apfnMcgSpriteFlipDispatch (4 near-ptrs)
; 0x0A0D..0x0B15  mcg_blit_sprite_clipped
; 0x0B16..0x0B35  mcg_sprite_row_noflip
; 0x0B36..0x0B5D  mcg_sprite_row_vflip
; 0x0B5E..0x0B87  mcg_sprite_row_hflip
; 0x0B88..0x0BA9  mcg_sprite_row_hvflip
; 0x0BAA..0x0BB2  mcg_sprite_blit_epilogue
; 0x0BB3..0x0C30  mcg_blit_chunky_rect_to_video
; 0x0C31..0x0C38  mcg_slot31_passthrough
; 0x0C39..0x0C49  mcg_dos_freemem_block_unused
; 0x0C4A..0x0D3B  mcg_slot33_helper
; ============================================================================

                .8086
                .MODEL  TINY
                .CODE

; Shared graphics-context STRUC (engine video-state the driver overlays
; by offset through its scratch DS). A STRUC emits no bytes.
; GFXCTX.INC lives in this directory; TASM finds it
; via /iSRC\DRIVERS\VMCODE (see DRIVERS.MAK).
                INCLUDE gfxctx.inc

                ORG     0
                ASSUME  ds:NOTHING, es:NOTHING

; ============================================================================
; mcg_init -- chunk initialiser. PROC FAR, called via host's video_init.
; chunk:0x0000..0x00A4
;
; CALLER ABI (host-side far call):
;   [BP+0x06]  ushort  backbuffer_paragraphs   (= 0x0FA0 = 64000B / 16)
;   [BP+0x08]  ushort  host_callbacks_off      (off of host service-callback table)
;   [BP+0x0A]  ushort  host_callbacks_seg      (seg of host service-callback table)
;
; INIT SEQUENCE:
;   1. [0x00..0x18]  Standard 14-byte shared prologue: REP MOVSW CX=0x26
;      copies the 76-byte host callback table from [BP+8..0xA] into the
;      chunk-local mirror at CS:0x0149 (g_apfnHostCallbacks, which sits
;      where slots 40..56 of the vtable template were on disk).
;   2. [0x19..0x34]  Saves backbuffer_paragraphs at CS:[0xA7]; computes
;      chunk_data_seg = caller-DS + (paras/16); stashes at CS:[0xA5].
;      Loads DS=ES=chunk_data_seg.
;   3. [0x36..0x3E]  Init two scratch-DS bytes: [0x21] := 0xFF and
;      INC [0x1F]. The 0xFF byte is the "mouse-active" flag the host
;      will read later; the [0x1F] counter is the "chunk-loaded-count"
;      that increments every time mcg_init runs (the host can call init
;      multiple times in some scenarios).
;   4. [0x3F..0x43]  INT 10h AX=0013h -- BIOS mode set to MCGA 320x200x256.
;   5. [0x44..0x5E]  Two DOS alloc-far calls (INT 21h AH=48h, BX=0x0FA0 paras
;      = 64000 bytes each). First result -> ds:[0x12]; second -> ds:[0x10].
;      These are the back-buffer pages (same logical layout as CGA but
;      one frame is the full 64000 bytes since mode 13h is one byte per
;      pixel). The check pattern is `CMP BX,CX / JNZ OOM`: BX is the
;      DOS-returned allocated-paragraph count, CX = the requested count
;      we saved; if they differ DOS gave us less than asked, jump to OOM.
;   6. [0x5F..0x7F]  Zero three 64000-byte pages: ds:[0x10], ds:[0x12],
;      and the fixed framebuffer seg 0xA000 (saved at ds:[0x14]). REP
;      STOSW CX=0x7D00 (32000 words = 64000 bytes) in a 3-iteration loop
;      driven by DX.
;   7. [0x80..0x92]  Build the 200-row scanline-offset LUT into
;      ds:[0x6F2]. STOSW with AX += 0x140 (320) each iteration. The
;      LUT is consumed by every blit primitive as `mov DI, ds:[BP*2+0x6F2]`.
;   8. [0x93..0xA0]  AL := 5 (mode flag = MCGA); stash at ds:[0x1D].
;      Return DX:SI = CS:0x00A9, a far pointer to g_apfnMcgVtable.
;
;   OOM path [0xA1..0xA3]:  AL := 0 then jump back to step 8's store
;   so the failure flag at ds:[0x1D] = 0 and DX:SI still points at
;   the vtable (the host treats AL=0 as the OOM signal regardless).
;
; RETURN:
;   AL    -- 5 on success (mode flag), 0 on alloc failure.
;   DX:SI -- CS:0x00A9, far pointer to g_apfnMcgVtable.
; ============================================================================
_start          LABEL   BYTE
mcg_init        PROC    FAR
                PUSH    BP
                MOV     BP, SP
                PUSH    DS
                PUSH    SI
                PUSH    DI
                MOV     DI, OFFSET g_apfnHostCallbacks
                PUSH    CS
                POP     ES
                MOV     SI, [BP+8]              ; arg1.off
                MOV     DS, [BP+0AH]            ; arg1.seg
                MOV     CX, 0026H               ; 38 words = 76 bytes
                REP     MOVSW
                POP     DI
                POP     SI
                POP     DS
                MOV     AX, [BP+6]              ; backbuffer_paragraphs
                MOV     cs:[g_wMcgBackbufferParagraphs], AX
                SHR     AX, 1
                SHR     AX, 1
                SHR     AX, 1
                SHR     AX, 1                   ; AX /= 16
                PUSH    DS
                PUSH    DI
                MOV     BX, DS
                ADD     AX, BX
                MOV     cs:[g_wMcgChunkDataSeg], AX           ; g_wMcgChunkDataSeg
                MOV     DS, AX
                MOV     ES, AX

                ; Initialise scratch state. 0x21 is the "mouse-active"
                ; flag the host reads later; 0xFF means "not yet seen".
                ; 0x1F is a load-count byte; the host can call init
                ; more than once in some recovery paths.
                MOV     BYTE PTR ds:[GfxContext.bActiveVgaMode], 0FFH
                INC     BYTE PTR ds:[GfxContext.bGfxRenderStateFlag]

                ; BIOS INT 10h AX=0013h -- switch the video adapter
                ; into MCGA mode 13h: 320x200x256, single 64000-byte
                ; linear framebuffer at A000:0000, default ROM
                ; palette loaded into the DAC (16 EGA colours +
                ; 16 greys + 216-colour cube + 8 trailing entries),
                ; cursor off, pixel mask 0x3C6 = 0xFF, DAC left in
                ; WRITE mode at index 0. The screen is cleared to
                ; colour 0 unless bit 7 of AL is set (AX=8013h
                ; preserves contents).
                ; (Source: RBIL INT 10h AH=00h.)
                MOV     AX, 0013H
                INT     10H

                ; Allocate two 64000-byte (= 0xFA0 paragraphs) blocks
                ; from ordinary DOS conventional memory for the two
                ; off-screen pages used as software back-buffers. Mode
                ; 13h has NO hardware page-flipping (single 64000-byte
                ; page at 0xA0000); these are plain DOS-alloc'd RAM
                ; segments that this driver blits through, not a
                ; second VRAM page.
                ;
                ; DOS service is INT 21h AH=48h ("allocate memory
                ; block"): BX = requested paragraph count, returns
                ; AX = segment of the allocated block, BX = actually-
                ; granted paras (if allocation failed because of
                ; fragmentation, BX < the requested count). See RBIL
                ; INT 21h AH=48h. CX holds our reference count so the
                ; post-call `CMP BX, CX / JNZ oom` catches under-
                ; allocation.
                MOV     BX, 0FA0H               ; 0xFA0 = 64000 / 16
                MOV     CX, BX
                MOV     AH, 48H
                INT     21H
                CMP     BX, CX
                JNZ     SHORT mcg_init_oom
                MOV     ds:[GfxContext.wVgaPage2Base], AX
                MOV     AH, 48H
                INT     21H
                CMP     BX, CX
                JNZ     SHORT mcg_init_oom
                MOV     ds:[GfxContext.wVgaPage1Base], AX

                ; Zero all three pages: the two DOS-alloc'd back
                ; buffers and the 64000 bytes of mode-13h VRAM at
                ; A000:0000. Driven by DX=3 counting down; the
                ; segments are stacked beforehand so each iteration
                ; POPs the next one into ES.
                MOV     AX, ds:[GfxContext.wVgaPage1Base]
                PUSH    AX
                MOV     AX, ds:[GfxContext.wVgaPage2Base]
                PUSH    AX
                MOV     AX, 0A000H              ; mode-13h VRAM seg
                MOV     ds:[GfxContext.wVgaFrontPageBase], AX
                PUSH    AX
                MOV     DX, 3
mcg_init_zero_one:
                POP     AX
                MOV     ES, AX
                MOV     CX, 7D00H               ; 32000 words = 64000 B
                XOR     AX, AX
                XOR     DI, DI
                REP     STOSW
                DEC     DX
                JNZ     SHORT mcg_init_zero_one

                ; ----- Build the 200-row scanline-offset LUT at scratch:[0x6F2].
                ; AX starts at 0; AX += 0x140 = 320 per row; STOSW.
                ; ES is already DS (chunk_data_seg), so the LUT lands in
                ; scratch RAM as `ushort row_offsets[200]`.
                MOV     CX, 00C8H               ; 200 rows
                MOV     DI, GfxContext.pRow_offset_lut
                MOV     AX, DS
                MOV     ES, AX
                XOR     AX, AX
                CLD
mcg_init_lut_loop:
                STOSW
                ADD     AX, 0140H
                LOOP    SHORT mcg_init_lut_loop
                MOV     AL, 5                   ; mode flag = MCGA
mcg_init_exit:
                MOV     ds:[GfxContext.bVideoAdapter], AL          ; driver-installed flag
                MOV     DX, CS
                MOV     SI, OFFSET g_apfnMcgVtable
                POP     DI
                POP     DS
                POP     BP
                RETF

mcg_init_oom:
                XOR     AX, AX
                JMP     SHORT mcg_init_exit
mcg_init        ENDP

; ============================================================================
; 0x00A5..0x00A8 -- chunk-local globals, zero-initialised on disk.
; Read/written via `CS:` overrides from mcg_init and the rest of the chunk.
; ============================================================================
g_wMcgChunkDataSeg          DW      0   ; 0x00A5  scratch-DS paragraph
g_wMcgBackbufferParagraphs  DW      0   ; 0x00A7  saved arg[0] from init

; ============================================================================
; g_apfnMcgVtable -- 41-slot renderer-vtable template.
; chunk:0x00A9..0x014C (164 bytes; 41 entries x 4)
;
; The host snapshots the first ~50 conceptual slots into g_renderer_vtable
; @ host:39ae:2ac6 after mcg_init returns. Each entry is
; (offset_word, segment_placeholder_word); the host STOSWs the chunk's
; load segment into every segment half.
;
; Slot 40 (at 0x0149) overlaps the start of g_apfnHostCallbacks: the init
; prologue's REP MOVSW writes 76 bytes starting at 0x0149, so that slot
; gets overwritten at load time. On disk it still has the RETF-stub
; pointer for completeness.
;
; The MCG vtable has 41 slots instead of the CGA chunk's 40 because slots
; 38..40 carry MCGA-mode-specific helpers (mcg_slot36/37/38_helper) that
; the planar drivers fold into other paths.
; ============================================================================
g_apfnMcgVtable LABEL   DWORD
                DW      0,      0               ; slot  0  -- NULL
                DW      OFFSET mcg_blit_glyph_row,  0               ; slot  1
                DW      OFFSET mcg_draw_line,  0                    ; slot  2
                DW      OFFSET mcg_blit_sprite_noflip,  0           ; slot  3
                DW      OFFSET mcg_present_rect,  0                 ; slot  4
                DW      OFFSET mcg_save_rect_to_buffer,  0          ; slot  5
                DW      OFFSET mcg_sprite_buffer_size,  0           ; slot  6
                DW      OFFSET mcg_rect_paste_from_buffer,  0       ; slot  7
                DW      OFFSET mcg_unimplemented_slot,  0           ; slot  8
                DW      OFFSET mcg_capture_rect,  0                 ; slot  9
                DW      OFFSET mcg_fill_pixel_run,  0               ; slot 10
                DW      OFFSET mcg_fill_pixel_run_dither,  0        ; slot 11
                DW      OFFSET mcg_unimplemented_slot,  0           ; slot 12
                DW      OFFSET mcg_image_list_measure,  0           ; slot 13
                DW      OFFSET mcg_image_records_install,  0        ; slot 14
                DW      OFFSET mcg_image_pack_nibble_or,  0         ; slot 15
                DW      OFFSET mcg_slot16_helper,  0                ; slot 16
                DW      OFFSET mcg_stretched_blit,  0               ; slot 17
                DW      OFFSET mcg_blit_chunky_nibble_pixels,  0    ; slot 18
                DW      OFFSET mcg_unimplemented_slot,  0           ; slot 19
                DW      OFFSET mcg_palette_set,  0                  ; slot 20
                DW      OFFSET mcg_getpixel,  0                     ; slot 21
                DW      OFFSET mcg_putpixel,  0                     ; slot 22
                DW      OFFSET mcg_unimplemented_slot,  0           ; slot 23
                DW      OFFSET mcg_unimplemented_slot,  0           ; slot 24
                DW      OFFSET mcg_unimplemented_slot,  0           ; slot 25
                DW      OFFSET mcg_unimplemented_slot,  0           ; slot 26
                DW      OFFSET mcg_polygon_span_fill,  0            ; slot 27
                DW      OFFSET mcg_unimplemented_slot,  0           ; slot 28
                DW      OFFSET mcg_blit_sprite_clipped,  0          ; slot 29
                DW      OFFSET mcg_blit_chunky_rect_to_video,  0    ; slot 30
                DW      OFFSET mcg_slot31_passthrough,  0           ; slot 31
                DW      OFFSET mcg_dos_freemem_block_unused,  0     ; slot 32
                DW      OFFSET mcg_slot33_helper,  0                ; slot 33
                DW      OFFSET mcg_palette_fade_blend,  0           ; slot 34
                DW      OFFSET mcg_dac_write_vsync,  0              ; slot 35
                DW      OFFSET mcg_slot36_helper,  0                ; slot 36
                DW      OFFSET mcg_slot37_helper,  0                ; slot 37
                DW      OFFSET mcg_slot38_helper,  0                ; slot 38
                DW      0,      0                                   ; slot 39  -- NULL
g_apfnHostCallbacks LABEL DWORD                                     ; 0x0149 -- head of host-callback mirror; overlaps slot 40 on disk
                DW      OFFSET mcg_unimplemented_slot,  0           ; slot 40  (overlap)

; ============================================================================
; g_apfnMcgHostCallbacksTail -- 18-entry tail of the host-callback mirror.
; chunk:0x014D..0x0194 (72 bytes; 18 entries x 4)
;
; On disk the bytes here are 18 copies of (mcg_unimplemented_slot, 0).
; Adding the 1 slot at 0x0149 that overlaps the vtable's slot 40 makes
; 19 slots total -- which matches the 19 host service-callback entries
; the init prologue's REP MOVSW (CX=0x26 words = 76 bytes) copies into
; this region from the host. Hence the symbol name "tail": the head of
; g_apfnHostCallbacks is at 0x0149 and is invisible from the source side
; (it appears inside the vtable's last slot).
;
; After init runs, every byte here has been overwritten with host-exported
; far pointers. On disk every slot is (RETF_stub, 0) so any accidental
; call into a stale slot harmlessly returns.
; ============================================================================
g_apfnMcgHostCallbacksTail LABEL DWORD
                DW      OFFSET mcg_unimplemented_slot,  0           ; cb 0
                DW      OFFSET mcg_unimplemented_slot,  0           ; cb 1
                DW      OFFSET mcg_unimplemented_slot,  0           ; cb 2
                DW      OFFSET mcg_unimplemented_slot,  0           ; cb 3
                DW      OFFSET mcg_unimplemented_slot,  0           ; cb 4
                DW      OFFSET mcg_unimplemented_slot,  0           ; cb 5
                DW      OFFSET mcg_unimplemented_slot,  0           ; cb 6
                DW      OFFSET mcg_unimplemented_slot,  0           ; cb 7
                DW      OFFSET mcg_unimplemented_slot,  0           ; cb 8
                DW      OFFSET mcg_unimplemented_slot,  0           ; cb 9
                DW      OFFSET mcg_unimplemented_slot,  0           ; cb10
                DW      OFFSET mcg_unimplemented_slot,  0           ; cb11
                DW      OFFSET mcg_unimplemented_slot,  0           ; cb12
                DW      OFFSET mcg_unimplemented_slot,  0           ; cb13
                DW      OFFSET mcg_unimplemented_slot,  0           ; cb14
                DW      OFFSET mcg_unimplemented_slot,  0           ; cb15
                DW      OFFSET mcg_unimplemented_slot,  0           ; cb16
                DW      OFFSET mcg_unimplemented_slot,  0           ; cb17

; ============================================================================
; mcg_unimplemented_slot -- 1-byte RETF stub @ chunk:0x0195.
;
; Default target for unimplemented vtable slots. Slots that point here:
;   8, 12, 19, 23-26, 28, 40 (and all 18 of the host-callback tail entries
;   on disk, but those get overwritten at init).
; ============================================================================
mcg_unimplemented_slot PROC FAR
                RETF
mcg_unimplemented_slot ENDP

; ============================================================================
; mcg_fill_pixel_run_dither -- dithered-fill alternate entry @ 0x0196.
; mcg_fill_pixel_run        -- pixel-run fill core    @ 0x019D..0x01D9.
;
; REGISTER ABI (both entries):
;   AX = colour (or {AH,AL} packed pair for dithered variant)
;   BX = start offset
;   CX = run length in bytes
;   DI = base offset (e.g. row offset from LUT)
;   DX = parity flag (passed through; only the dither entry tests it)
;   ES = framebuffer segment
;
; The two-entry shape gives callers a choice:
;   * call 0x019D for a solid run (AH ignored).
;   * call 0x0196 for a dithered run (AH/AL pair, parity from DX).
;
; The active-palette far pointer (g_pMcgActivePaletteFar) lives at the
; SAME numeric offset 0x019E -- but in the scratch DS segment that init
; allocates after the chunk's code (see mcg_init / g_wMcgChunkDataSeg),
; NOT inside this function. The accesses in mcg_palette_set go through
; `MOV DS, cs:[g_wMcgChunkDataSeg] / MOV DI, ds:[0x019E]` so they read
; the heap-allocated scratch buffer; the two regions only share an
; offset, not a physical location.
; ============================================================================
mcg_fill_pixel_run_dither PROC FAR
                AND     DX, 1
                JZ      SHORT mcg_fpr_main
                MOV     AX, DX                  ; parity flips -> use other half
mcg_fill_pixel_run_dither ENDP
                                                ;
                                                ; Fall through into mcg_fill_pixel_run.
                                                ;
mcg_fill_pixel_run PROC FAR
mcg_fpr_main:                                   ; (0x019D after the 2-byte fall-through)
                OR      CX, CX
                JLE     SHORT mcg_fpr_exit
                OR      AH, AH
                JNZ     SHORT mcg_fpr_dither
                MOV     AH, AL                  ; solid fill: replicate byte into word
                ADD     DI, BX
                SHR     CX, 1
                REP     STOSW
                JNC     SHORT mcg_fpr_norem
                STOSB                           ; odd remainder
mcg_fpr_norem:
                MOV     AX, SS
                MOV     DS, AX                  ; restore DS = SS
                RETF
mcg_fpr_dither:
                MOV     DS, cs:[g_wMcgChunkDataSeg]           ; DS = scratch
                XOR     WORD PTR ds:[MCG_SCRATCH_DITHER_PARITY], 1  ; toggle parity bit
                MOV     DL, ds:[MCG_SCRATCH_DITHER_PARITY]
                XOR     DL, BL
                AND     DL, 1
                JZ      SHORT mcg_fpr_no_swap
                XCHG    AL, AH                  ; flip dither colours
mcg_fpr_no_swap:
                ADD     DI, BX
                SHR     CX, 1
                REP     STOSW
                JNC     SHORT mcg_fpr_dith_norem
                STOSB
mcg_fpr_dith_norem:
                MOV     AX, SS
                MOV     DS, AX
mcg_fpr_exit:
                RETF
mcg_fill_pixel_run ENDP

; ============================================================================
; mcg_slot37_helper -- glyph-decode primitive (slot 37) @ 0x01DA..0x01F3.
;
; REGISTER ABI:
;   SI/DI/BP source/dest/index, CX = byte count, DX = pre-step delta,
;   ES = framebuffer-seg.
;
; String-copy until null-terminator into ES:DI; advances a pointer table
; at BP. Copies non-null bytes from the indexed source into framebuffer
; until first zero (zero = transparency).
; ============================================================================
mcg_slot37_helper PROC FAR
                ADD     DI, DX
                DEC     DI
                INC     CX                      ; compensate for first DEC CX in loop
mcg_s37_step:
                INC     DI
                DEC     CX
                ; JZ targets 0x01D9, which is the RETF byte CB inside
                ; mcg_fill_pixel_run's mcg_fpr_exit -- shared single-byte
                ; exit.
                JZ      SHORT mcg_fpr_exit
mcg_s37_more:
                MOV     BX, [BP]
                ADD     BP, 2
                ADD     BX, SI
                MOV     AL, [BX]
                OR      AL, AL
                JZ      SHORT mcg_s37_step
                STOSB
                LOOP    SHORT mcg_s37_more
                RETF
mcg_slot37_helper ENDP

; ============================================================================
; mcg_slot16_helper -- depth-tested indexed-byte blit (slot 16).
; chunk:0x01F4..0x0226.
;
; REGISTER ABI:
;   CX  --  loop count (decremented each iteration; exit when zero)
;   DX  --  pre-step delta added once to DI before the loop
;   DI  --  destination base offset (ES:DI is the output target)
;   BP  --  walker into a per-column byte-offset array (advanced by 2/iter)
;   SI  --  source base offset (combined with BP[i] to form source ptr)
;   ES  --  destination segment (framebuffer)
;
; Loop body: for each iteration,
;   1. Read the back-buffer pixel at (BACKBUF_SEG:DI) by swapping ES
;      to BACKBUF_SEG temporarily. AL = existing back-buffer pixel.
;   2. If AH (threshold = GfxContext.wTextureIdx) < AL (existing):
;      skip this column. JC after CMP AH,AL takes when AH < AL, i.e.
;      back-buffer pixel exceeds threshold (depth-test reject).
;   3. Else load source byte at SI + BP[i].
;      If source byte is 0: skip (transparency).
;      Else STOSB into ES:DI (= framebuffer).
;
; Exits via the shared single-byte RETF at 0x01D9 (mcg_fpr_exit inside
; mcg_fill_pixel_run; see "shared exit byte" note above slot 37).
; ============================================================================
mcg_slot16_helper PROC FAR
                ADD     DI, DX
                PUSH    DS
                MOV     DS, cs:[g_wMcgChunkDataSeg]           ; DS = scratch
                MOV     DX, ds:[GfxContext.wVgaPage1Base]          ; back-buffer seg
                MOV     AH, BYTE PTR ds:[GfxContext.wTextureIdx]  ; colour threshold (low byte of word field)
                POP     DS
                DEC     DI                      ; pre-step (paired with INC below)
mcg_s16_step:
                INC     DI
                DEC     CX
                JZ      SHORT mcg_fpr_exit      ; shared single-byte RETF @ 0x01D9
mcg_s16_more:
                MOV     BX, [BP]
                ADD     BP, 2
                ADD     BX, SI
                PUSH    ES
                MOV     ES, DX
                MOV     AL, ES:[DI]             ; existing pixel
                POP     ES
                CMP     AH, AL
                JC      SHORT mcg_s16_step      ; pixel > thresh -> skip
                MOV     AL, [BX]
                OR      AL, AL
                JZ      SHORT mcg_s16_step      ; null source -> skip
                STOSB
                LOOP    SHORT mcg_s16_more
                RETF
mcg_slot16_helper ENDP

; ============================================================================
; mcg_slot38_helper -- bidirectional run copy (slot 38) @ 0x0227..0x023B.
;
; REGISTER ABI:
;   CF (entry carry-flag) = direction. CX = count, BX = offset, SI = source,
;   DI = base.
;
; If CF set on entry: copy backwards (overlapping rect). Else forwards.
; A tiny REP-MOVS wrapper that decides direction from the entry CF.
; ============================================================================
mcg_slot38_helper PROC FAR
                JC      SHORT mcg_s38_back
                ADD     DI, BX
                SHR     CX, 1
                JNC     SHORT mcg_s38_fwd_word
                MOVSB
mcg_s38_fwd_word:
                REP     MOVSW
                RETF
mcg_s38_back:
                ADD     DI, BX
mcg_s38_back_loop:
                MOVSB
                SUB     DI, 2
                LOOP    SHORT mcg_s38_back_loop
                RETF
mcg_slot38_helper ENDP

; ============================================================================
; mcg_slot36_helper -- clipped horizontal-span fill (slot 36).
; chunk:0x023C..0x027D.
;
; HYBRID ABI (register args + stack args, called via far call from host):
;   DX  --  y-offset / signed pre-step (clip-clamps if negative)
;   CX  --  byte count
;   DI  --  destination offset (base output offset in ES:DI)
;   ES  --  destination segment
;   [BP+6]  ushort  far-ptr.off into a descriptor (DS:BX base)
;   [BP+8]  ushort  base offset added to BX (combined with descriptor[2])
;   [BP+0AH] ushort indexed-ptr-array offset (BP-walker for per-byte source)
;
; When DX < 0: clamps CX, advances the index-array offset, zeroes DX.
; Then copies non-null bytes from BP-indexed source into ES:DI, skipping
; zeros as transparency. Restores DS = SS on exit.
;
; The hybrid convention is not advertised in the chunk-overview list at
; the top of the file. At the entry point (0x023C-0x023F) DX and CX are
; read before any prologue setup.
; ============================================================================
mcg_slot36_helper PROC FAR
                PUSH    BP
                MOV     BP, SP
                OR      DX, DX
                JNS     SHORT mcg_s36_nonneg
                NEG     DX
                SUB     CX, DX
                JLE     SHORT mcg_s36_exit
                SHL     DX, 1
                ADD     [BP+0AH], DX
                XOR     DX, DX
mcg_s36_nonneg:
                ADD     DI, DX
                MOV     BX, [BP+8]
                MOV     AX, [BP+0AH]
                MOV     BP, [BP+6]
                MOV     DS, [BP]
                ADD     BX, [BP+2]
                MOV     BP, AX
mcg_s36_row:
                MOV     SI, [BP]
                ADD     BP, 2
                ADD     SI, BX
                LODSB
                OR      AL, AL
                JZ      SHORT mcg_s36_skip
                STOSB
                LOOP    SHORT mcg_s36_row
                JMP     SHORT mcg_s36_exit
mcg_s36_skip:
                INC     DI
                LOOP    SHORT mcg_s36_row
mcg_s36_exit:
                MOV     AX, SS
                MOV     DS, AX
                POP     BP
                RETF
mcg_slot36_helper ENDP

; ============================================================================
; mcg_draw_line -- glyph row blit / line draw (slot 2).
; chunk:0x027E..0x036F
;
; REGISTER ABI: BX=x0, CX=y0, DX=x1, SI=y1.
;
; Bresenham-style line draw with axis-aligned and 4 octant cases. Uses the
; scanline LUT at DS-relative offset 0x6F2 (built by init step 7). The
; packed-colour word is staged at scratch:[0x6BC] from the byte at
; scratch:[0xE] (the line-colour register).
;
; Five branches:
;   * point (x0==x1 && y0==y1)          -- single STOSB.
;   * horizontal (y0==y1)               -- forward STOSW run.
;   * vertical (x0==x1)                 -- column loop with row-stride.
;   * shallow octants (|dx| > |dy|)     -- the BP=0x140 or BP=-0x140 path
;     with running error accumulator.
;   * steep octants (|dy| > |dx|)       -- the AX=0x140 mul / BP swap path.
; ============================================================================
mcg_draw_line PROC FAR
                PUSH    DS
                MOV     DS, cs:[g_wMcgChunkDataSeg]           ; DS = scratch
                MOV     AL, ds:[GfxContext.bGfx_outline_color]          ; line-colour byte
                MOV     AH, AL
                MOV     ds:[GfxContext.wTextureIdx], AX          ; stash as packed word
                MOV     DI, BX
                MOV     DI, CX
                SHL     DI, 1
                MOV     DI, ds:[DI].GfxContext.pRow_offset_lut       ; row offset from LUT
                ADD     DI, BX                  ; + x0 -- DI now points at pixel (x0,y0)
                CMP     BX, DX
                JNZ     SHORT mcg_dl_diffx
                CMP     CX, SI
                JZ      SHORT mcg_dl_point
                JMP     SHORT mcg_dl_vert
mcg_dl_diffx:
                CMP     CX, SI
                JZ      SHORT mcg_dl_horiz
                JMP     SHORT mcg_dl_shallow
mcg_dl_point:
                MOV     AX, ds:[GfxContext.wTextureIdx]
                STOSB
                JMP     mcg_dl_exit
mcg_dl_horiz:
                SUB     DX, BX
                MOV     CX, DX
                MOV     AX, ds:[GfxContext.wTextureIdx]
                INC     CX
                SHR     CX, 1
                JNC     SHORT mcg_dl_horiz_word
                STOSB
mcg_dl_horiz_word:
                REP     STOSW
                JMP     mcg_dl_exit
mcg_dl_vert:
                MOV     BP, 013FH               ; row stride - 1
                SUB     SI, CX
                JG      SHORT mcg_dl_vert_pos
                NEG     SI
                SHL     SI, 1
                SUB     DI, ds:[SI].GfxContext.pRow_offset_lut       ; DI -= row LUT entry
                SHR     SI, 1
mcg_dl_vert_pos:
                MOV     CX, SI
                MOV     AX, ds:[GfxContext.wTextureIdx]
                INC     CX
mcg_dl_vert_loop:
                STOSB
                ADD     DI, BP                  ; step down by 320-1 then +1 below
                LOOP    SHORT mcg_dl_vert_loop
                JMP     mcg_dl_exit
mcg_dl_shallow:
                MOV     BP, 0140H
                SUB     DX, BX                  ; dx
                SUB     SI, CX                  ; dy
                JG      SHORT mcg_dl_sh_pos
                NEG     SI
                NEG     BP
mcg_dl_sh_pos:
                MOV     CX, SI                  ; |dy|
                CMP     CX, DX
                JZ      SHORT mcg_dl_sh_diag
                JC      SHORT mcg_dl_sh_xstep
                JMP     SHORT mcg_dl_steep
mcg_dl_sh_xstep:
                JMP     SHORT mcg_dl_xstep
mcg_dl_sh_diag:
                MOV     CX, DX
                INC     CX
                MOV     AX, ds:[GfxContext.wTextureIdx]
mcg_dl_sh_diag_loop:
                STOSB
                ADD     DI, BP
                LOOP    SHORT mcg_dl_sh_diag_loop
                JMP     mcg_dl_exit
mcg_dl_xstep:
                MOV     BX, CX                  ; BX = |dy|
                MOV     CX, DX                  ; CX = |dx| (loop count)
                MOV     AX, BX
                SHL     AX, 1
                MOV     SI, AX                  ; SI = 2*|dy|
                SUB     AX, CX
                MOV     DX, AX                  ; DX = error
                SUB     AX, CX
                MOV     BX, BP
                MOV     BP, AX                  ; BP = 2*|dy| - 2*|dx|
                MOV     AX, ds:[GfxContext.wTextureIdx]
                STOSB
mcg_dl_xstep_loop:
                OR      DX, DX
                JS      SHORT mcg_dl_xstep_skip
                ADD     DI, BX
                ADD     DX, BP
                JMP     SHORT mcg_dl_xstep_store
mcg_dl_xstep_skip:
                ADD     DX, SI
mcg_dl_xstep_store:
                STOSB
                LOOP    SHORT mcg_dl_xstep_loop
                JMP     SHORT mcg_dl_exit
mcg_dl_steep:
                MOV     BX, DX                  ; BX = |dx|
                MOV     AX, 1
                OR      BP, BP
                JNS     SHORT mcg_dl_steep_pos
                NEG     AX
                PUSH    AX
                MOV     AX, 0140H
                MUL     CX
                SUB     DI, AX
                ADD     DI, BX
                POP     AX
mcg_dl_steep_pos:
                MOV     BP, AX                  ; step direction
                MOV     AX, BX
                SHL     AX, 1
                MOV     SI, AX                  ; SI = 2*|dx|
                SUB     AX, CX
                MOV     DX, AX
                SUB     AX, CX
                MOV     BX, BP
                MOV     BP, AX
                MOV     AX, ds:[GfxContext.wTextureIdx]
                STOSB
mcg_dl_steep_loop:
                ADD     DI, 013FH
                OR      DX, DX
                JS      SHORT mcg_dl_steep_skip
                ADD     DI, BX
                ADD     DX, BP
                JMP     SHORT mcg_dl_steep_store
mcg_dl_steep_skip:
                ADD     DX, SI
mcg_dl_steep_store:
                STOSB
                LOOP    SHORT mcg_dl_steep_loop
mcg_dl_exit:
                POP     DS
                RETF
mcg_draw_line ENDP

; ============================================================================
; 0x0370..0x0377 -- per-polygon scratch globals (mcg_polygon_span_fill state).
; Stashed via `CS:` overrides; zero on disk.
; ============================================================================
g_wMcgSpanRemainingRows  DW     0   ; 0x0370  rows left in current polygon
g_wMcgSpanColorEvenRow   DW     0   ; 0x0372  packed colour for even rows
g_wMcgSpanColorOddRow    DW     0   ; 0x0374  packed colour for odd rows
g_wMcgSpanRowOffsetBase  DW     0   ; 0x0376  base offset for row LUT (0x6F2 + paras)

; ============================================================================
; mcg_polygon_span_fill -- polygon scanline-span fill (slot 27).
; chunk:0x0378..0x0465.
;
; REGISTER ABI: ES:SI = far pointer to span descriptor.
;
; Descriptor layout (read via LODSW):
;   [+0]  ushort  span_count (* 2 -> stride between row entries)
;   [+2]  ushort  row_count (stored to g_wMcgSpanRemainingRows)
;   [+4]  ushort[] pairs of (x_left, x_right) per row
;
; For each row, writes the [x_left..x_right] run with the colour at
; scratch:[GfxContext.bGfx_fill_color] / [GfxContext.bGfx_dither_color].
; Uses the scanline LUT (scratch:[GfxContext.pRow_offset_lut], indexed by
; g_wMcgSpanRowOffsetBase = LUT_offset + chunk_backbuffer_paragraphs).
;
; Two main paths:
;   - solid (AH==0 after loading)          : single colour fill, straight REP STOSW.
;   - dithered (AH!=0)                     : alternates colours per row by parity
;                                           of (start_x), entering through the
;                                           odd/even halves at the BX/0x1 test.
; ============================================================================
mcg_polygon_span_fill PROC FAR
                PUSH    DS
                MOV     CX, ES
                MOV     DS, CX
                LODSW                           ; AX = descriptor count
                SHL     AX, 1
                MOV     BP, AX
                LODSW                           ; AX = y_start (or stride)
                MOV     DS, cs:[g_wMcgChunkDataSeg]           ; DS = scratch
                MOV     cs:[g_wMcgSpanRemainingRows], AX          ; g_wMcgSpanRemainingRows
                MOV     AX, ds:[GfxContext.wGfxBlitDstPage]          ; visible-FB seg
                MOV     ES, AX
                MOV     AX, GfxContext.pRow_offset_lut
                ADD     AX, cs:[g_wMcgBackbufferParagraphs]
                MOV     cs:[g_wMcgSpanRowOffsetBase], AX          ; g_wMcgSpanRowOffsetBase
                MOV     AL, ds:[GfxContext.bGfx_fill_color]          ; even-row colour byte
                MOV     AH, ds:[GfxContext.bGfx_dither_color]          ; odd-row colour byte
                MOV     DS, CX
                MOV     cs:[g_wMcgSpanColorEvenRow], AX
                OR      AH, AH
                JZ      SHORT mcg_psf_solid
                XCHG    AL, AH
                MOV     cs:[g_wMcgSpanColorOddRow], AX
                JMP     SHORT mcg_psf_dith
mcg_psf_solid:
                LODSW                           ; x_left
                MOV     BX, AX
                LODSW                           ; x_right
                SUB     AX, BX
                JGE     SHORT mcg_psf_solid_ok
                JMP     SHORT mcg_psf_solid_skip
mcg_psf_solid_ok:
                INC     AX                      ; length = right-left+1
                MOV     CX, AX
                MOV     DI, cs:[g_wMcgSpanRowOffsetBase]
                MOV     DI, [BP+DI]             ; row offset
                MOV     AX, cs:[g_wMcgSpanColorEvenRow]
                MOV     AH, AL                  ; solid: replicate AL into AH
                ADD     DI, BX
                SHR     CX, 1
                REP     STOSW
                JNC     SHORT mcg_psf_solid_skip
                STOSB
mcg_psf_solid_skip:
                SUB     WORD PTR cs:[g_wMcgSpanRemainingRows], 1
                JLE     SHORT mcg_psf_done
                ADD     BP, 2
                JMP     SHORT mcg_psf_solid
mcg_psf_done:
                POP     DS
                RETF
mcg_psf_dith:
                MOV     cs:[g_wMcgSpanColorOddRow], AX
                MOV     BX, BP
                SHR     BX, 1
                ADD     BX, [SI]
                SHR     BX, 1
                JC      SHORT mcg_psf_dith_even
                JMP     SHORT mcg_psf_dith_odd
mcg_psf_dith_even:
                LODSW
                MOV     BX, AX
                LODSW
                SUB     AX, BX
                JGE     SHORT mcg_psf_dith_e_ok
                JMP     SHORT mcg_psf_dith_e_sk
mcg_psf_dith_e_ok:
                INC     AX
                MOV     CX, AX
                MOV     DI, cs:[g_wMcgSpanRowOffsetBase]
                MOV     DI, [BP+DI]
                MOV     AX, cs:[g_wMcgSpanColorEvenRow]
                TEST    BX, 1
                JZ      SHORT mcg_psf_dith_e_no_swap
                XCHG    AL, AH
mcg_psf_dith_e_no_swap:
                ADD     DI, BX
                SHR     CX, 1
                REP     STOSW
                JNC     SHORT mcg_psf_dith_e_sk
                STOSB
mcg_psf_dith_e_sk:
                SUB     WORD PTR cs:[g_wMcgSpanRemainingRows], 1
                JG      SHORT mcg_psf_dith_more
                POP     DS
                RETF
mcg_psf_dith_more:
                ADD     BP, 2
mcg_psf_dith_odd:
                LODSW
                MOV     BX, AX
                LODSW
                SUB     AX, BX
                JGE     SHORT mcg_psf_dith_o_ok
                JMP     SHORT mcg_psf_dith_o_sk
mcg_psf_dith_o_ok:
                INC     AX
                MOV     CX, AX
                MOV     DI, cs:[g_wMcgSpanRowOffsetBase]
                MOV     DI, [BP+DI]
                MOV     AX, cs:[g_wMcgSpanColorOddRow]
                TEST    BX, 1
                JZ      SHORT mcg_psf_dith_o_no_swap
                XCHG    AL, AH
mcg_psf_dith_o_no_swap:
                ADD     DI, BX
                SHR     CX, 1
                REP     STOSW
                JNC     SHORT mcg_psf_dith_o_sk
                STOSB
mcg_psf_dith_o_sk:
                SUB     WORD PTR cs:[g_wMcgSpanRemainingRows], 1
                JLE     SHORT mcg_psf_dith_exit
                ADD     BP, 2
                JMP     SHORT mcg_psf_dith_even
mcg_psf_dith_exit:
                POP     DS
                RETF
mcg_polygon_span_fill ENDP

; ============================================================================
; 0x0466..0x0467 -- two-byte alignment pad.
; ============================================================================
g_wMcgAlignmentPad466   DW      0       ; 0x0466

; ============================================================================
; mcg_dac_write_vsync -- DAC palette write with vsync gate.
; chunk:0x0468..0x04A4.  __cdecl16far(rgb_near_off, start_index, count).
;
; CALLER ABI:
;   [BP+6]   ushort  rgb_near_off  (offset of palette source bytes,
;                                    in the CALLER's DS -- this is a
;                                    near pointer, not a far pointer;
;                                    only 3 args = 6 bytes on the stack)
;   [BP+8]   ushort  start_index   (DAC index in 0..255)
;   [BP+0A]  ushort  count         (number of triples to write;
;                                    each triple is 3 bytes of 6-bit
;                                    R, G, B in the 0..63 range)
;
; Sequence:
;   1. Poll 0x3DA bit 3 (vertical retrace) until set, so the palette
;      stream lands inside vblank. The IMS G171 RAMDAC does NOT stall
;      its own writes against scan-out -- any DAC write outside vblank
;      that hits a pixel currently using the entry being updated
;      produces a one-pixel "snow dot" in the output, so software
;      gating is necessary. (Abrash ch. 34.)
;   2. Probe the DAC state via port 0x3C7 read. The chip exposes its
;      current R/W mode in bits 0..1 (see DAC primer above and the
;      inline note on the conditional write below).
;   3. Set the DAC WRITE index via port 0x3C8 -- this both selects
;      the starting palette entry AND resets the chip's internal
;      R/G/B byte counter to "next access is Red".
;   4. Stream count*3 bytes to 0x3C9 under CLI. The chip auto-
;      advances the sub-counter every byte and the palette index
;      every third byte. CLI is essential because the byte counter
;      is internal to the chip; any ISR that touched 0x3C9 mid-
;      stream would desync the counter and write our R into the
;      previous entry's G/B slot.
;
; Primary register-level reference: VGADOC VGAREGS.TXT. The IMS G171
; chip reference is the INMOS Graphics Databook 1990.
; ============================================================================
mcg_dac_write_vsync PROC FAR
                PUSH    BP
                MOV     BP, SP
                PUSH    SI
                PUSH    DI
                MOV     SI, [BP+6]              ; rgb_off (DS:SI src)
                MOV     CX, [BP+0AH]            ; count of RGB triples

                ; CX = count * 3 (number of bytes to stream out).
                MOV     AX, CX
                SHL     CX, 1
                ADD     CX, AX
                MOV     BX, [BP+8]              ; start_index

                ; Spin on port 0x3DA bit 3 until vertical retrace is
                ; in progress. Doing the palette write inside vblank
                ; means the user never sees a half-updated DAC during
                ; a scanout. Note bit 0 is a DIFFERENT signal ("any
                ; retrace, H or V") and is NOT what we want -- it
                ; toggles every horizontal line. (VGADOC VGAREGS.TXT;
                ; Ferraro §4.5.3 status-register table.)
                MOV     DX, 03DAH
mcg_dac_wait_vsync:
                IN      AL, DX
                AND     AL, 8
                JZ      SHORT mcg_dac_wait_vsync

                ; DAC state probe + conditional dummy write to 0x3C9.
                ; Port 0x3C7 read returns the DAC's mode in bits 0..1:
                ;   0b00 (= 0)  -- chip is in WRITE mode (last index
                ;                  was set via 0x3C8)
                ;   0b11 (= 3)  -- chip is in READ mode (last index
                ;                  was set via 0x3C7)
                ;   intermediate values transient / undefined.
                ; If READ mode (= 3) we jump straight to setting the
                ; WRITE index. If WRITE mode (= 0..2), we first issue
                ; a single OUT to 0x3C9 with the masked state byte.
                ;
                ; The exact reason for this conditional OUT is unclear.
                ; A stray OUT 0x3C9 does NOT reset
                ; the chip's R/G/B byte counter -- it consumes a slot
                ; in the current cycle (advancing the counter by one).
                ; The subsequent OUT 0x3C8 below DOES reset the byte
                ; counter (back to "next access is Red"), so whatever
                ; this extra OUT writes is discarded by the index-set
                ; before our real palette data starts. Most charitable
                ; reading: a defensive hedge against an off-by-one in
                ; case a prior code path left the counter mid-cycle.
                ; The hedge isn't sound, but it's also harmless.
                MOV     DX, 03C7H
                IN      AL, DX
                AND     AL, 3
                CMP     AL, 3
                JZ      SHORT mcg_dac_set_idx
                MOV     DX, 03C9H
                OUT     DX, AL
mcg_dac_set_idx:
                ; Program the WRITE index (port 0x3C8). The DAC will
                ; auto-increment after every 3 bytes streamed to 0x3C9.
                MOV     DX, 03C8H
                MOV     AX, BX
                OUT     DX, AL

                ; Stream count*3 bytes (R,G,B,R,G,B,...) to 0x3C9.
                ; CLI fences the loop against interrupts -- any ISR
                ; that touched the DAC mid-stream would desync the
                ; chip's internal 3-byte counter.
                MOV     DX, 03C9H
                CLI
mcg_dac_stream:
                LODSB
                OUT     DX, AL
                LOOP    SHORT mcg_dac_stream
                STI
                POP     DI
                POP     SI
                POP     BP
                RETF
mcg_dac_write_vsync ENDP

; ============================================================================
; mcg_dac_write_single_entry -- single-RGB-triple DAC-upload wrapper.
; chunk:0x04A5..0x04BB.  Signature looks like
; __cdecl16far(struct rgb_triple, ushort dac_index).
;
; NAMING NOTE: a "set border colour" name would be a CGA-era misnomer
; here, on two counts:
;
;   1. MCGA mode 13h has no programmable border / overscan colour
;      at all. The CGA Color Select register at 0x3D9 has no
;      effect on the border, and although the VGA Attribute
;      Controller does expose an overscan-colour register at
;      AC[11h], the visible overscan area in mode 13h is
;      essentially zero pixels. Quoting Ardent Tool of Capitalism
;      "PS/2 Video Programming": "The MCGA cannot generate a
;      colored border".
;   2. The function can target ANY of the 256 DAC entries via the
;      `dac_index` argument -- it is not specific to entry 0 (the
;      colour that fills the screen edge in mode 13h), entry 255,
;      or any other "border-adjacent" slot.
;
; NOT WIRED INTO THE VTABLE. Slot 25 of g_apfnMcgVtable points at
; mcg_unimplemented_slot (the RETF stub), and no other code in this
; chunk references this function.
;
; The body itself has a stack-balance bug: it pushes 6 bytes of args
; before `PUSH CS / CALL NEAR PTR
; mcg_dac_write_vsync` (cdecl convention; caller must pop the args
; after the callee's RETF), but then cleans up with only `POP SI /
; POP BP / RETF` -- which leaves 2 bytes too few popped, sending the
; final RETF to a garbage address. If the host ever did call this,
; it would crash.
;
; Body reads: a 3-byte RGB triple passed by value at [BP+6..BP+8] (high
; byte of the second word is struct-alignment padding) and the target
; DAC index as a word at [BP+0AH], then forwards to
; mcg_dac_write_vsync(&rgb, index, 1) to upload exactly one palette
; entry through the VSYNC-gated path.
; ============================================================================
mcg_dac_write_single_entry PROC FAR
                PUSH    BP
                MOV     BP, SP
                PUSH    SI
                MOV     BX, [BP+0AH]            ; arg1: DAC index
                LEA     SI, [BP+6]              ; arg0: &{r,g,b} (3 contiguous bytes)
                MOV     AX, 1                   ; count = 1 entry
                PUSH    AX
                PUSH    BX
                PUSH    SI
                PUSH    CS
                CALL    NEAR PTR mcg_dac_write_vsync
                POP     SI
                POP     BP
                RETF
mcg_dac_write_single_entry ENDP

; ============================================================================
; mcg_palette_set -- palette set (slot 20).
; chunk:0x04BC..0x04FD.  __cdecl16far(palette_far_ptr, set_flag).
;
; If palette_far_ptr.seg != 0:
;   1. Writes 256 DAC entries from palette_far_ptr to the chip via
;      mcg_dac_write_vsync(pal, 0, 0x100). The source bytes must be
;      6-bit R/G/B values (0..63); any value 64..255 will have its
;      top 2 bits silently dropped by the IMS G171 DAC.
;   2. Copies the 768-byte palette into the host-allocated "active
;      palette" storage block. The destination far pointer is loaded
;      from the slot pair at scratch:[GfxContext.pPaletteScratchBuf / _SEG]
;      (offsets 0x019E/0x01A0); the slot pair holds the address of the
;      block, not the block itself. The block is 1536 bytes (two halves
;      of 768 bytes); the same source is REP MOVSW'd into both halves.
;   3. Returns. (Else: skip both steps and return immediately.)
;
; The double 0x180 loop is the 768-byte memcpy in two halves,
; done this way to keep CX < 0x10000 in one pass
; (768 = 256*3, MOVSW two halves of 384 words each). The two-half
; layout is consumed later by mcg_palette_fade_blend (slot 34) which
; treats the second half as the "target" palette for blends.
; ============================================================================
mcg_palette_set PROC FAR
                PUSH    BP
                MOV     BP, SP
                PUSH    DI
                PUSH    SI
                PUSH    DS
                MOV     DS, cs:[g_wMcgChunkDataSeg]
                MOV     DI, ds:[GfxContext.pPaletteScratchBuf]          ; g_pMcgActivePaletteFar.off
                MOV     ES, ds:[(GfxContext.pPaletteScratchBuf + 2)]          ; g_pMcgActivePaletteFar.seg
                MOV     SI, [BP+6]              ; pal.off
                MOV     AX, [BP+8]              ; pal.seg
                MOV     DS, AX
                OR      AX, AX
                JZ      SHORT mcg_ps_exit
                MOV     AX, 0100H               ; count = 256 entries
                PUSH    AX
                XOR     AX, AX                  ; start_index = 0
                PUSH    AX
                PUSH    SI
                PUSH    CS
                CALL    NEAR PTR mcg_dac_write_vsync
                ADD     SP, 6

                ; Copy the 768-byte palette into the chunk's active-
                ; palette storage TWICE -- the storage block is 1536
                ; bytes (current + target halves used by the fade
                ; blender). After the first REP MOVSW, SI is rewound
                ; by 768 bytes so the second REP MOVSW re-reads the
                ; same source into ES:DI+768.
                MOV     CX, 0180H               ; CX = 384 words = 768 bytes
                MOV     AX, CX
                REP     MOVSW                   ; copy 1: current palette
                SUB     SI, AX
                SUB     SI, AX                  ; SI -= 2*0x180 = 768 bytes (rewind)
                MOV     CX, AX
                REP     MOVSW                   ; copy 2: target palette (= same bytes)
mcg_ps_exit:
                POP     DS
                POP     SI
                POP     DI
                POP     BP
                RETF
mcg_palette_set ENDP

; ============================================================================
; mcg_palette_fade_blend -- palette fade blend (slot 34).
; chunk:0x04FE..0x057B.
; __cdecl16far(start_index, count, target_index, fade_level).
;
; Blends from the active palette (scratch DS:0x019E) towards a target
; palette by fade_level (0..0x3F = 0..63). Output triples are
; interleaved RGB and written via mcg_dac_write_vsync.
;
; Per-channel formula:
;   out = (src * fade)/0x3F + (tgt * (0x3F - fade))/0x3F
;
; The 0x3F constant is the MCGA / VGA DAC's 6-bit per-channel
; maximum (each R/G/B is 0..63, see hardware primer above). The
; fade_level is therefore a "fraction expressed in 64ths" -- 0x00 =
; fully target, 0x3F = fully source.
;
; The body swaps DL between `fade` and `0x3F - fade` in place by
; running `AL := DL; DL := DH; DL := DL - AL` on each side -- saves
; the second 8-bit constant from having to live in a register. Each
; RGB triple cycles through (R, G, B) by counting BL up to 3 and
; rewinding BP -= 3 / BL := 0 on wrap.
; ============================================================================
mcg_palette_fade_blend PROC FAR
                PUSH    BP
                MOV     BP, SP
                PUSH    DS
                PUSH    DI
                PUSH    SI
                MOV     DS, cs:[g_wMcgChunkDataSeg]
                MOV     AX, [BP+8]
                PUSH    AX
                MOV     CX, AX
                SHL     AX, 1
                ADD     CX, AX
                MOV     DL, [BP+0CH]            ; fade level
                MOV     DH, 03FH                ; max level
                MOV     DS, ds:[(GfxContext.pPaletteScratchBuf + 2)]
                MOV     AX, [BP+6]
                PUSH    AX
                MOV     DI, AX
                SHL     AX, 1
                ADD     DI, AX                  ; DI = idx*3 (source offset)
                PUSH    DI
                MOV     SI, DI
                ADD     SI, 0300H
                MOV     AX, [BP+0AH]
                MOV     BP, 0300H
                ADD     BP, AX
                SHL     AX, 1
                ADD     BP, AX
                PUSH    DS
                POP     ES                      ; ES = DS (palette seg)
                XOR     BX, BX
mcg_pfb_loop:
                XOR     AH, AH
                LODSB                           ; source byte
                MUL     DL                      ; AL *= fade
                DIV     DH                      ; AL /= 0x3F
                MOV     BH, AL                  ; stash blended source
                MOV     AL, DL
                MOV     DL, DH
                SUB     DL, AL                  ; DL = 0x3F - fade
                XOR     AH, AH
                MOV     AL, ds:[BP+0]           ; target byte
                MUL     DL
                DIV     DH
                ADD     AL, BH                  ; sum the two halves
                STOSB
                MOV     AL, DL
                MOV     DL, DH
                SUB     DL, AL                  ; restore DL = fade
                INC     BP
                INC     BL
                CMP     BL, 3
                JNZ     SHORT mcg_pfb_no_wrap
                XOR     BX, BX
                SUB     BP, 3
mcg_pfb_no_wrap:
                LOOP    SHORT mcg_pfb_loop
                PUSH    CS
                CALL    NEAR PTR mcg_dac_write_vsync
                ADD     SP, 6                   ; pop count/idx/ptr from CALL
                ADD     SP, CX                  ; pop locals
                POP     SI
                POP     DI
                POP     DS
                POP     BP
                RETF
mcg_palette_fade_blend ENDP

; ============================================================================
; mcg_image_list_measure -- image-list measure (slot 13).
; chunk:0x057C..0x05AE.
; __cdecl16far(image_record_array, out_overflow_ptr) -> ulong total_pixels.
;
; Walks a NULL-terminated array of image-record near pointers; sums
; width * height (fields +6, +8 within each record) using 32-bit
; arithmetic with carry into DX. On return:
;   AX  --  low 16 bits of the sum
;   DX  --  high 16 bits (32-bit return via DX:AX, Borland `long` ABI)
;   *out_overflow_ptr := 0  (always written, even on overflow -- a real
;                             output slot, but the game always sees zero
;                             here)
; ============================================================================
mcg_image_list_measure PROC FAR
                PUSH    BP
                MOV     BP, SP
                PUSH    SI
                PUSH    DI
                MOV     DI, [BP+6]              ; image_record_array
                XOR     BX, BX
                XOR     DX, DX
mcg_ilm_loop:
                MOV     SI, [DI]
                OR      SI, SI
                JZ      SHORT mcg_ilm_done
                PUSH    DX
                XOR     DX, DX
                MOV     AX, [SI+6]              ; width
                MUL     WORD PTR [SI+8]         ; * height
                POP     DX
                ADD     BX, AX
                ADC     DX, 0                   ; propagate carry into DX
                ADD     DI, 2
                JMP     SHORT mcg_ilm_loop
mcg_ilm_done:
                MOV     AX, BX
                MOV     SI, [BP+8]              ; out_overflow_ptr
                MOV     WORD PTR [SI], 0        ; *out_overflow_ptr := 0
                POP     DI
                POP     SI
                POP     BP
                RETF
mcg_image_list_measure ENDP

; ============================================================================
; mcg_image_records_install -- image records install (slot 14).
; chunk:0x05AF..0x06A9.
; __cdecl16far(record_array, base_off, base_seg, target_off, target_seg).
;
; Walks the NULL-terminated record array, computing per-image far-pointer
; (segment = base_seg + (running_off >> 4), offset = running_off & 0xF).
; Stores into image record fields +0 (seg) and +2 (off), advancing by
; record->w * record->h (fields +6, +8). Second loop walks the same
; source backwards and packs each byte's high/low nibble pair into the
; two bytes of a word -- write of `((src>>4) | (src<<8)) & 0x0F0F` per
; iteration, with both DS and ES decremented per step to back-walk
; through the source/dest buffers using carry-aware segment arithmetic
; (real-mode huge-pointer normalisation).
; ============================================================================
mcg_image_records_install PROC FAR
                PUSH    BP
                MOV     BP, SP
                PUSH    SI
                PUSH    DI
                PUSH    DS
                MOV     DI, [BP+8]
                MOV     ES, [BP+0AH]
mcg_iri_record:
                MOV     SI, [BP+6]
                MOV     SI, [SI]
                OR      SI, SI
                JZ      SHORT mcg_iri_pack
                MOV     DX, DI
                MOV     AX, ES
                MOV     CL, 4
                SHR     DX, CL                  ; DI >> 4
                ADD     AX, DX
                MOV     [SI], AX                ; record.seg
                MOV     DX, DI
                AND     DX, 000FH
                MOV     [SI+2], DX              ; record.off (low nibble)
                MOV     AX, [SI+6]
                XOR     DX, DX
                MUL     WORD PTR [SI+8]         ; w*h
                XOR     CX, CX
                ADD     DI, AX
                RCR     CX, 1
                SHR     CX, 1
                SHR     CX, 1
                SHR     CX, 1                   ; CX = carry-shifted high bits
                MOV     AX, ES
                ADD     AX, CX
                MOV     ES, AX
                ADD     WORD PTR [BP+6], 2
                JMP     SHORT mcg_iri_record
mcg_iri_pack:
                MOV     SI, [BP+8]
                MOV     AX, [BP+0AH]
                XOR     CX, CX
                ADD     SI, [BP+0CH]
                RCR     CX, 1
                SHR     CX, 1
                SHR     CX, 1
                SHR     CX, 1
                MOV     BH, [BP+0EH]
                XOR     BL, BL
                SHL     BX, 1
                SHL     BX, 1
                SHL     BX, 1
                SHL     BX, 1                   ; BX = high-byte << 4
                ADD     BX, CX
                SUB     SI, 1
                JNC     SHORT mcg_iri_pack_si_ok
                SUB     AX, 1000H               ; borrow segment para
mcg_iri_pack_si_ok:
                ADD     AX, BX
                MOV     DS, AX
                MOV     DI, [BP+8]
                MOV     AX, [BP+0AH]
                MOV     DX, [BP+0CH]
                MOV     BH, [BP+0EH]
                XOR     BL, BL
                SHL     BX, 1
                SHL     BX, 1
                SHL     BX, 1
                SHL     BX, 1
                SHL     BX, 1
                XOR     CX, CX
                SUB     DX, 1
                JNC     SHORT mcg_iri_pack_dx_ok
                SUB     DX, 1000H
mcg_iri_pack_dx_ok:
                SHL     DX, 1
                JNC     SHORT mcg_iri_pack_no_dx_carry
                ADD     BX, 1000H
mcg_iri_pack_no_dx_carry:
                ADD     DI, DX
                RCR     CX, 1
                SHR     CX, 1
                SHR     CX, 1
                SHR     CX, 1
                ADD     BX, CX
                ADD     AX, BX
                MOV     ES, AX
mcg_iri_pack_loop:
                MOV     AL, [SI]
                XOR     CX, CX
                MOV     BX, DS
                SUB     SI, 1
                RCR     CX, 1
                SHR     CX, 1
                SHR     CX, 1
                SHR     CX, 1
                SUB     BX, CX
                MOV     DS, BX
                MOV     AH, AL
                MOV     CL, 4
                SHR     AL, CL                  ; AL = high nibble
                AND     AX, 0F0FH               ; keep nibbles
                MOV     ES:[DI], AX             ; write nibble-packed word
                XOR     CX, CX
                MOV     BX, ES
                SUB     DI, 2
                RCR     CX, 1
                SHR     CX, 1
                SHR     CX, 1
                SHR     CX, 1
                SUB     BX, CX
                MOV     ES, BX
                SUB     WORD PTR [BP+0CH], 1
                SBB     WORD PTR [BP+0EH], 0
                MOV     AX, [BP+0CH]
                OR      AX, [BP+0EH]
                JNZ     SHORT mcg_iri_pack_loop
                POP     DS
                POP     DI
                POP     SI
                POP     BP
                RETF
mcg_image_records_install ENDP

; ============================================================================
; mcg_image_pack_nibble_or -- image-pack nibble-OR helper (slot 15).
; chunk:0x06AA..0x06FD.
; __cdecl16far(src, src_seg_hi, dst, dst_seg_hi, count).
;
; For each of `count` source bytes:
;   src_byte  = DS:[SI]   (then SI++)
;   word_out  = (src_byte & 0xF0)   |   ((src_byte & 0x0F) << 12)
;             = { (src_high_nibble << 4) , (src_low_nibble << 4) }
;             (little-endian: low byte = src high nibble in top 4 bits;
;              high byte = src low nibble in top 4 bits)
;   ES:[DI] |= word_out      (OR-merge, not overwrite)
;   DI += 2
;
; The extra RCR/SHR/ADD-BX dance around each load/store advances DS
; (source) and ES (destination) segment by one paragraph whenever the
; pointer arithmetic carries out of the offset -- the standard Borland
; huge-pointer normalisation pattern. The two seg_hi args are the seed
; values for these arithmetic-carries.
; ============================================================================
mcg_image_pack_nibble_or PROC FAR
                PUSH    BP
                MOV     BP, SP
                PUSH    SI
                PUSH    DI
                PUSH    DS
                MOV     SI, [BP+6]
                MOV     DS, [BP+8]
                MOV     DI, [BP+0AH]
                MOV     ES, [BP+0CH]
                MOV     CX, [BP+0EH]
mcg_ipno_loop:
                XOR     DX, DX
                MOV     AL, [SI]
                ADD     SI, 1
                RCR     DX, 1                   ; carry -> DX top
                SHR     DX, 1
                SHR     DX, 1
                SHR     DX, 1
                MOV     BX, DS
                ADD     BX, DX
                MOV     DS, BX                  ; advance DS by carry paras
                MOV     AH, AL
                SHL     AH, 1
                SHL     AH, 1
                SHL     AH, 1
                SHL     AH, 1                   ; AH = low nibble shifted up
                AND     AX, 0F0F0H              ; keep high nibbles
                OR      ES:[DI], AX
                XOR     DX, DX
                ADD     DI, 2
                RCR     DX, 1
                SHR     DX, 1
                SHR     DX, 1
                SHR     DX, 1
                MOV     BX, ES
                ADD     BX, DX
                MOV     ES, BX
                LOOP    SHORT mcg_ipno_loop
                POP     DS
                POP     DI
                POP     SI
                POP     BP
                RETF
mcg_image_pack_nibble_or ENDP

; ============================================================================
; mcg_blit_sprite_noflip -- sprite-blit no-flip wrapper (slot 3).
; chunk:0x06FE..0x0717.
; __cdecl16far(x, y, sprite_id) -> mcg_blit_sprite_clipped(x, y, sprite_id, 0).
;
; Pure 4-argument thunk. Pushes flip_flags=0 and the original 3 args,
; tail-calls mcg_blit_sprite_clipped.
; ============================================================================
mcg_blit_sprite_noflip PROC FAR
                PUSH    BP
                MOV     BP, SP
                XOR     AX, AX                  ; flip_flags = 0
                PUSH    AX
                PUSH    [BP+0AH]
                PUSH    [BP+8]
                PUSH    [BP+6]
                PUSH    CS
                CALL    NEAR PTR mcg_blit_sprite_clipped
                ADD     SP, 8
                MOV     BP, SP
                POP     BP
                RETF
mcg_blit_sprite_noflip ENDP

; ============================================================================
; mcg_blit_glyph_row -- glyph row blit / sprite-row blit (slot 1).
; chunk:0x0718..0x0781.
;
; REGISTER ABI (entry-register reads at chunk:0x0718-0x0731):
;   SI  --  source bitmap pointer (DS:SI), 1-bit-per-pixel rows
;   BX  --  glyph width in pixels (= bits per row)
;   CX  --  row count (decremented as the outer-loop counter via DX)
;   DX  --  destination x offset (one-time, added to DI after row LUT)
;   BP  --  destination y (used as LUT index, then repurposed as width
;             for inner-loop / row-stride correction)
;   DI  --  preserved across the call (entry value NOT read)
;
; Reads a 1-bit-per-pixel glyph bitmap row from DS:SI, expands each bit
; to a chunky pixel (foreground colour or transparent), and writes to
; framebuffer ES:DI. The CL byte at scratch:[GfxContext.bText_style_flags] gates
; the two paths:
;   CL==0 : non-transparent (overwrite all pixels with FG or BG)
;   CL!=0 : transparent (skip 0-bits)
; Frame buffer chosen from scratch:[GfxContext.wGfxBlitDstPage].
; ============================================================================
mcg_blit_glyph_row PROC FAR
                PUSH    DI
                PUSH    BP
                PUSH    DS
                PUSH    ES
                MOV     DS, cs:[g_wMcgChunkDataSeg]
                MOV     ES, ds:[GfxContext.wGfxBlitDstPage]
                SHL     BP, 1
                MOV     DI, ds:[BP].GfxContext.pRow_offset_lut       ; DI = row LUT[y]
                ADD     DI, DX                  ; DI += x (DX entry = x offset)
                MOV     DX, CX                  ; DX = entry_CX = row count
                MOV     CX, BX                  ; CX = entry_BX = width (bits/row)
                MOV     BP, CX                  ; BP = width (used by row stride)
                MOV     AL, ds:[GfxContext.bText_fg_color]          ; FG colour
                MOV     AH, ds:[GfxContext.bText_bg_color]          ; BG colour
                MOV     BX, AX
                MOV     CL, ds:[GfxContext.bText_style_flags]          ; transparent flag
                POP     DS
                OR      CL, CL
                JNZ     SHORT mcg_bgr_trans
mcg_bgr_solid_row:
                MOV     CX, BP
                LODSB
                MOV     AH, AL
mcg_bgr_solid_bit:
                SHL     AH, 1
                MOV     AL, BH
                JNC     SHORT mcg_bgr_solid_bg
                MOV     AL, BL
mcg_bgr_solid_bg:
                STOSB
                LOOP    SHORT mcg_bgr_solid_bit
                ADD     DI, 0140H
                SUB     DI, BP
                DEC     DX
                JNZ     SHORT mcg_bgr_solid_row
                JMP     SHORT mcg_bgr_exit
mcg_bgr_trans:
mcg_bgr_trans_row:
                MOV     CX, BP
                LODSB
                MOV     AH, AL
mcg_bgr_trans_bit:
                SHL     AH, 1
                JNC     SHORT mcg_bgr_trans_skip
                MOV     AL, BL
                STOSB
                LOOP    SHORT mcg_bgr_trans_bit
                DEC     DI
mcg_bgr_trans_skip:
                INC     DI
                LOOP    SHORT mcg_bgr_trans_bit
                ADD     DI, 0140H
                SUB     DI, BP
                DEC     DX
                JNZ     SHORT mcg_bgr_trans_row
                JMP     SHORT mcg_bgr_exit
mcg_bgr_exit:
                POP     DS
                POP     BP
                POP     DI
                RETF
mcg_blit_glyph_row ENDP

; ============================================================================
; mcg_save_rect_to_buffer -- save rect to buffer (slot 5).
; chunk:0x0782..0x07D7.
; __cdecl16far(buf, buf_seg_hi, x, y, width_bytes, height).
;
; Copies a rectangular region from the back-buffer (seg at scratch:[0x16])
; to buf. The destination far pointer is computed from
; buf+buf_seg_hi by the (off >> 4) seg-adjust and (off & 0xF) offset-
; trim pattern at the entry. Stride per row = 0x140 = 320 (= 320/2 words).
; ============================================================================
mcg_save_rect_to_buffer PROC FAR
                PUSH    BP
                MOV     BP, SP
                PUSH    SI
                PUSH    DI
                PUSH    DS
                PUSH    ES
                MOV     DS, cs:[g_wMcgChunkDataSeg]
                MOV     AX, [BP+6]
                MOV     DI, AX
                AND     DI, 000FH
                SHR     AX, 1
                SHR     AX, 1
                SHR     AX, 1
                SHR     AX, 1
                ADD     AX, [BP+8]
                MOV     ES, AX
                MOV     BX, [BP+0EH]            ; width_bytes
                MOV     DX, [BP+10H]            ; height
                MOV     SI, [BP+0AH]            ; x
                MOV     BP, [BP+0CH]            ; y
                SHL     BP, 1
                LEA     BP, [BP].GfxContext.pRow_offset_lut
                ADD     SI, ds:[BP+0]           ; + row LUT entry
                MOV     AX, ds:[GfxContext.wGfxBlitSrcPage]          ; back-buffer seg
                MOV     DS, AX
                MOV     BP, SI
mcg_srtb_row:
                MOV     SI, BP
                MOV     CX, BX
                SHR     CX, 1
                JNC     SHORT mcg_srtb_word
                MOVSB
mcg_srtb_word:
                REP     MOVSW
                ADD     BP, 0140H
                DEC     DX
                JNZ     SHORT mcg_srtb_row
                POP     ES
                POP     DS
                POP     DI
                POP     SI
                POP     BP
                RETF
mcg_save_rect_to_buffer ENDP

; ============================================================================
; mcg_sprite_buffer_size -- sprite buffer size (slot 6).
; chunk:0x07D8..0x07E3.
; __cdecl16far(ushort width, ushort height) -> ulong width * height.
;
; Body: AX = width; CWD (sign-extends AX into DX -- irrelevant under
; unsigned MUL but emitted by Borland's codegen for `int * int` ->
; `long` regardless); MUL [BP+8] gives DX:AX = width * height.
; Return ABI: 32-bit result in DX:AX (Borland `long` convention).
; ============================================================================
mcg_sprite_buffer_size PROC FAR
                PUSH    BP
                MOV     BP, SP
                MOV     AX, [BP+6]
                CWD
                MUL     WORD PTR [BP+8]
                POP     BP
                RETF
mcg_sprite_buffer_size ENDP

; ============================================================================
; mcg_rect_paste_from_buffer -- rect paste from buffer (slot 7).
; chunk:0x07E4..0x0839.
; __cdecl16far(buf, buf_seg_hi, x, y, width_bytes, height).
;
; Mirror of mcg_save_rect_to_buffer: paste direction (buf -> framebuffer).
; Uses framebuffer seg scratch:[0x18] instead of back-buffer seg [0x16].
; ============================================================================
mcg_rect_paste_from_buffer PROC FAR
                PUSH    BP
                MOV     BP, SP
                PUSH    SI
                PUSH    DI
                PUSH    DS
                PUSH    ES
                MOV     DS, cs:[g_wMcgChunkDataSeg]
                MOV     AX, ds:[GfxContext.wGfxBlitDstPage]
                MOV     ES, AX
                MOV     AX, [BP+6]
                MOV     SI, AX
                AND     SI, 000FH
                SHR     AX, 1
                SHR     AX, 1
                SHR     AX, 1
                SHR     AX, 1
                ADD     AX, [BP+8]
                PUSH    AX
                MOV     BX, [BP+0EH]
                MOV     DX, [BP+10H]
                MOV     DI, [BP+0AH]
                MOV     BP, [BP+0CH]
                SHL     BP, 1
                LEA     BP, [BP].GfxContext.pRow_offset_lut
                ADD     DI, ds:[BP+0]
                POP     DS                      ; DS = src seg
                MOV     BP, DI
mcg_rpfb_row:
                MOV     DI, BP
                MOV     CX, BX
                SHR     CX, 1
                JNC     SHORT mcg_rpfb_word
                MOVSB
mcg_rpfb_word:
                REP     MOVSW
                ADD     BP, 0140H
                DEC     DX
                JNZ     SHORT mcg_rpfb_row
                POP     ES
                POP     DS
                POP     DI
                POP     SI
                POP     BP
                RETF
mcg_rect_paste_from_buffer ENDP

; ============================================================================
; mcg_getpixel -- getpixel (slot 21).
; chunk:0x083A..0x085B.
; __cdecl16far(x, y) -> color.
;
; Returns *(back_buffer + scanline_lut[y] + x). In MCGA mode 13h, that
; is a direct chunky byte read.
; ============================================================================
mcg_getpixel PROC FAR
                PUSH    BP
                MOV     BP, SP
                PUSH    DS
                MOV     DS, cs:[g_wMcgChunkDataSeg]
                MOV     BX, [BP+8]              ; y
                SHL     BX, 1
                MOV     BX, ds:[BX].GfxContext.pRow_offset_lut
                ADD     BX, [BP+6]              ; + x
                MOV     AX, ds:[GfxContext.wGfxBlitSrcPage]          ; back-buffer seg
                MOV     ES, AX
                MOV     AL, ES:[BX]
                XOR     AH, AH
                POP     DS
                POP     BP
                RETF
mcg_getpixel ENDP

; ============================================================================
; mcg_putpixel -- putpixel (slot 22).
; chunk:0x085C..0x087E.
; __cdecl16far(x, y, color).
;
; Mirror of mcg_getpixel: write. Single chunky byte store at
; (visible-FB seg [0x18] + scanline_lut[y] + x).
; ============================================================================
mcg_putpixel PROC FAR
                PUSH    BP
                MOV     BP, SP
                PUSH    DS
                MOV     DS, cs:[g_wMcgChunkDataSeg]
                MOV     BX, [BP+8]              ; y
                SHL     BX, 1
                MOV     BX, ds:[BX].GfxContext.pRow_offset_lut
                ADD     BX, [BP+6]              ; + x
                MOV     AX, ds:[GfxContext.wGfxBlitDstPage]          ; visible-FB seg
                MOV     ES, AX
                MOV     AL, [BP+0AH]            ; color
                MOV     ES:[BX], AL
                POP     DS
                POP     BP
                RETF
mcg_putpixel ENDP

; ============================================================================
; mcg_present_rect -- present rect (slot 4).
; chunk:0x087F..0x08C6.
; __cdecl16far(src_off, y, width_bytes, height).
;
; Copies a rectangle from back-buffer (seg scratch:[0x16]) to
; framebuffer (seg scratch:[0x18]). The "src_off" arg is the
; in-back-buffer byte offset of the row's left edge minus the row
; LUT entry (i.e. the destination x already folded in by the caller);
; the body adds scanline_lut[y] to it to land at the final pixel
; position. Stride per row = 0x140 = 320.
; ============================================================================
mcg_present_rect PROC FAR
                PUSH    BP
                MOV     BP, SP
                PUSH    SI
                PUSH    DI
                PUSH    DS
                PUSH    ES
                MOV     DS, cs:[g_wMcgChunkDataSeg]
                MOV     SI, [BP+6]
                MOV     BX, [BP+0AH]
                MOV     DX, [BP+0CH]
                MOV     BP, [BP+8]
                SHL     BP, 1
                LEA     BP, [BP].GfxContext.pRow_offset_lut
                MOV     BP, ds:[BP+0]
                MOV     AX, ds:[GfxContext.wGfxBlitDstPage]
                MOV     ES, AX
                MOV     AX, ds:[GfxContext.wGfxBlitSrcPage]
                MOV     DS, AX
                ADD     BP, SI
mcg_pr_row:
                MOV     SI, BP
                MOV     DI, SI
                MOV     CX, BX
                SHR     CX, 1
                JNC     SHORT mcg_pr_word
                MOVSB
mcg_pr_word:
                REP     MOVSW
                ADD     BP, 0140H
                DEC     DX
                JNZ     SHORT mcg_pr_row
                POP     ES
                POP     DS
                POP     DI
                POP     SI
                POP     BP
                RETF
mcg_present_rect ENDP

; ============================================================================
; mcg_capture_rect -- slot 9 rectangle copy. chunk:0x08C7..0x090C.
; __cdecl16far(x, y, width_bytes, height).
;
; Copies a rectangle from scratch:[GfxContext.wVgaPage2Base] (the second
; DOS-allocated 64000-byte buffer, used as a sprite-blit working area)
; to scratch:[GfxContext.wVgaFrontPageBase] (the real mode-13h VRAM at 0xA000).
; Stride per row = 0x140 = 320.
;
; The inherited name "capture_rect" is misleading -- read direction is
; DOS-RAM-buffer -> VRAM, i.e. functionally a present-style copy with a
; different source segment than slot 4 (mcg_present_rect, which sources
; from GfxContext.wGfxBlitSrcPage / 0x16 to GfxContext.wGfxBlitDstPage / 0x18).
; The "capture" name is misleading; the
; actual semantic is "present from blit-source buffer". Direction:
; ES = FB_SEG (0x14, = 0xA000), DS = BLIT_SRC_SEG
; (0x12), and `REP MOVSW` copies DS:SI -> ES:DI.
;
; Note: mode 13h has no hardware page-flipping. The two DOS-allocated
; buffers here and in the rest of the driver are ordinary RAM
; segments, not a hardware "page 2".
; ============================================================================
mcg_capture_rect PROC FAR
                PUSH    BP
                MOV     BP, SP
                PUSH    SI
                PUSH    DI
                PUSH    DS
                MOV     DS, cs:[g_wMcgChunkDataSeg]
                MOV     SI, [BP+6]
                MOV     BX, [BP+0AH]
                MOV     DX, [BP+0CH]
                MOV     BP, [BP+8]
                SHL     BP, 1
                LEA     BP, [BP].GfxContext.pRow_offset_lut
                MOV     BP, ds:[BP+0]
                MOV     AX, ds:[GfxContext.wVgaFrontPageBase]
                MOV     ES, AX
                MOV     AX, ds:[GfxContext.wVgaPage2Base]
                MOV     DS, AX
                ADD     BP, SI
mcg_cr_row:
                MOV     SI, BP
                MOV     DI, SI
                MOV     CX, BX
                SHR     CX, 1
                JNC     SHORT mcg_cr_word
                MOVSB
mcg_cr_word:
                REP     MOVSW
                ADD     BP, 0140H
                DEC     DX
                JNZ     SHORT mcg_cr_row
                POP     DS
                POP     DI
                POP     SI
                POP     BP
                RETF
mcg_capture_rect ENDP

; ============================================================================
; mcg_stretched_blit -- nibble-unpacked blit (overwrite) (slot 17).
; chunk:0x090D..0x0982.
; __cdecl16far(src_off, src_seg, dst_x, dst_y, width_pixels, row_count).
;
; Reads packed-nibble source (LODSB), splits each byte's high/low
; nibbles into the upper bits of AH/AL, swaps via XCHG, and STOSWs
; to ES:[DI] in framebuffer. Each source byte produces 2 destination
; pixels (high nibble first, low nibble second).
;
; Functionally identical to mcg_blit_chunky_nibble_pixels (slot 18,
; below) except this entry uses STOSW (overwrite) where the slot-18
; variant uses `OR ES:[DI], AX` (additive merge). Same arg layout,
; same row LUT, same scratch-globals; only the write semantic differs.
;
; The unusual prologue order (PUSH BP / PUSH DS / PUSH SI / PUSH ES /
; PUSH DI / MOV BP,SP) puts saved DS/SI/ES/DI on the stack frame; the
; body reads neither of them via [BP-x] -- they're only popped at
; exit.
;
; "Stretched" in the name overstates it: the function doesn't stretch in
; the modern sense; it
; unpacks one source byte into two destination pixels (a fixed 2x
; horizontal expansion in pixel count, not in size).
; ============================================================================
mcg_stretched_blit PROC FAR
                PUSH    BP
                PUSH    DS
                PUSH    SI
                PUSH    ES
                PUSH    DI
                MOV     BP, SP
                MOV     AX, [BP+16H]
                SHR     AX, 1
                MOV     [BP+16H], AX
                MOV     AX, [BP+0EH]
                MOV     BX, AX
                AND     BX, 000FH
                MOV     SI, BX
                SHR     AX, 1
                SHR     AX, 1
                SHR     AX, 1
                SHR     AX, 1
                ADD     AX, [BP+10H]
                MOV     DS, AX
                ; SS-relative scratch read: SS+paragraphs aliases the scratch
                ; segment (paragraphs were added at init), so `ss:[paragraphs+off]`
                ; is equivalent to `scratch_ds:[off]`.
                MOV     DI, GfxContext.wGfxBlitDstPage
                ADD     DI, cs:[g_wMcgBackbufferParagraphs]
                MOV     ES, ss:[DI]
                MOV     DX, [BP+18H]
mcg_sb_row:
                MOV     AX, [BP+14H]
                SHL     AX, 1
                MOV     BX, GfxContext.pRow_offset_lut
                ADD     BX, AX
                ADD     BX, cs:[g_wMcgBackbufferParagraphs]
                MOV     AX, ss:[BX]
                ADD     AX, [BP+12H]
                MOV     DI, AX
                MOV     CX, [BP+16H]
mcg_sb_pix:
                XOR     AX, AX
                LODSB
                SHL     AX, 1
                SHL     AX, 1
                SHL     AX, 1
                SHL     AX, 1
                SHR     AL, 1
                SHR     AL, 1
                SHR     AL, 1
                SHR     AL, 1
                XCHG    AL, AH
                STOSW
                LOOP    SHORT mcg_sb_pix
                MOV     AX, [BP+14H]
                INC     AX
                MOV     [BP+14H], AX
                DEC     DX
                JNZ     SHORT mcg_sb_row
                POP     DI
                POP     ES
                POP     SI
                POP     DS
                POP     BP
                RETF
mcg_stretched_blit ENDP

; ============================================================================
; mcg_blit_chunky_nibble_pixels -- chunky 4bpp->mode-13 nibble blit (slot 18).
; chunk:0x0983..0x0A02.  __cdecl16far(src_off, src_seg, dst_x, dst_y,
;                                     width_pixels, row_count).
;
; Reads packed-nibble source (LODSB), splits each byte's high/low nibbles
; into AH/AL, applies SHL 4 to put nibble in upper bits of each, and ORs
; to ES:[DI] in framebuffer. Each source byte produces 2 destination
; pixels.
;
; Row offset is read from the scanline LUT through the SS+paragraphs
; aliasing pattern: `MOV AX, ss:[GfxContext.pRow_offset_lut + y*2 + paragraphs]`
; (the host arranges SS such that SS+chunk_paragraphs == scratch DS, so
; an SS-relative read at +paragraphs reaches the same byte as a normal
; scratch DS read at +0).  Same pattern is used for the framebuffer
; segment slot read above.
;
; Body 0x0983..0x0A02; ends with POP DI/ES/SI/DS/BP / RETF.
; ============================================================================
mcg_blit_chunky_nibble_pixels PROC FAR
                PUSH    BP
                PUSH    DS
                PUSH    SI
                PUSH    ES
                PUSH    DI
                MOV     BP, SP
                MOV     DS, cs:[g_wMcgChunkDataSeg]
                MOV     AX, [BP+16H]
                SHR     AX, 1
                MOV     [BP+16H], AX
                MOV     AX, [BP+0EH]
                MOV     BX, AX
                AND     BX, 000FH
                MOV     SI, BX
                SHR     AX, 1
                SHR     AX, 1
                SHR     AX, 1
                SHR     AX, 1
                ADD     AX, [BP+10H]
                MOV     DS, AX
                ; SS-relative scratch read; see mcg_stretched_blit for the
                ; SS+paragraphs scratch-aliasing pattern.
                MOV     DI, GfxContext.wGfxBlitDstPage
                ADD     DI, cs:[g_wMcgBackbufferParagraphs]
                MOV     ES, ss:[DI]
                MOV     DX, [BP+18H]
mcg_bcnp_row:
                MOV     AX, [BP+14H]
                SHL     AX, 1
                MOV     BX, GfxContext.pRow_offset_lut
                ADD     BX, AX
                ADD     BX, cs:[g_wMcgBackbufferParagraphs]
                MOV     AX, ss:[BX]
                ADD     AX, [BP+12H]
                MOV     DI, AX
                MOV     CX, [BP+16H]
mcg_bcnp_pix:
                XOR     AX, AX
                LODSB
                SHL     AX, 1
                SHL     AX, 1
                SHL     AX, 1
                SHL     AX, 1
                SHL     AH, 1
                SHL     AH, 1
                SHL     AH, 1
                SHL     AH, 1
                XCHG    AL, AH
                OR      ES:[DI], AX
                ADD     DI, 2
                LOOP    SHORT mcg_bcnp_pix
                MOV     AX, [BP+14H]
                INC     AX
                MOV     [BP+14H], AX
                DEC     DX
                JNZ     SHORT mcg_bcnp_row
                POP     DI
                POP     ES
                POP     SI
                POP     DS
                POP     BP
                RETF
mcg_blit_chunky_nibble_pixels ENDP

; ============================================================================
; g_nMcgSpriteClipRows -- per-sprite clipped row count.
; chunk:0x0A03..0x0A04.  Read/written via CS:[0xA03] from
; mcg_blit_sprite_clipped and the 4 sprite-row primitives below.
; ============================================================================
g_nMcgSpriteClipRows DW 0       ; 0x0A03

; ============================================================================
; g_apfnMcgSpriteFlipDispatch -- 4-slot NEAR-pointer table for sprite flips.
; chunk:0x0A05..0x0A0C  (4 entries x 2 bytes).
;
; Indexed by `flip_flags * 2` at the end of mcg_blit_sprite_clipped:
;   [0]  -> mcg_sprite_row_noflip    (0x0B16)   no flip
;   [1]  -> mcg_sprite_row_vflip     (0x0B36)   vertical flip
;   [2]  -> mcg_sprite_row_hflip     (0x0B5E)   horizontal flip
;   [3]  -> mcg_sprite_row_hvflip    (0x0B88)   both flips
;
; All four targets share the epilogue at 0x0BAA (mcg_sprite_blit_epilogue).
; ============================================================================
g_apfnMcgSpriteFlipDispatch LABEL WORD
                DW      OFFSET mcg_sprite_row_noflip
                DW      OFFSET mcg_sprite_row_vflip
                DW      OFFSET mcg_sprite_row_hflip
                DW      OFFSET mcg_sprite_row_hvflip

; ============================================================================
; mcg_blit_sprite_clipped -- clipped sprite blit dispatcher (slot 29).
; chunk:0x0A0D..0x0B15.
; __cdecl16far(sprite_record, x, y, flip_flags).
;
; Reads clip rect from scratch globals at [0x3] (enabled), [0x4] (left),
; [0x6] (right), [0x8] (top), [0xA] (bottom). Same layout as the CGA chunk
; -- see cga_blit_sprite_clipped for reference.
;
; Dispatches via `MOV AX, [BX+0x0A05] / JMP AX` indexed by flip_flags*2
; through g_apfnMcgSpriteFlipDispatch. The 4 dispatch targets all reach
; mcg_sprite_blit_epilogue at 0x0BAA: noflip / vflip / hflip exit with
; an explicit `JMP SHORT mcg_sprite_blit_epilogue`, while hvflip falls
; through (it's the function physically immediately before the epilogue).
;
; Uses scratch global g_nMcgSpriteClipRows @ 0x0A03 for the clipped row
; count (set up here, decremented inside the row primitives via
; `DEC WORD PTR cs:[0x0A03]`).
; ============================================================================
mcg_blit_sprite_clipped PROC FAR
                PUSH    BP
                MOV     BP, SP
                SUB     SP, 0AH                 ; 10 bytes of locals
                PUSH    DI
                PUSH    SI
                PUSH    ES
                PUSH    DS
                MOV     SI, [BP+6]              ; sprite_record offset
                MOV     DI, BP
                SUB     DI, 0AH
                MOV     AX, SS
                MOV     ES, AX
                MOV     CX, 5
                REP     MOVSW                   ; copy 10 bytes -> stack locals
                MOV     DS, cs:[g_wMcgChunkDataSeg]
                MOV     AX, ds:[GfxContext.wGfxBlitDstPage]
                MOV     ES, AX
                MOV     SI, [BP-8]
                TEST    BYTE PTR [BP+0CH], 2
                JZ      SHORT mcg_bsc_no_hflip
                ADD     SI, [BP-4]
                DEC     SI
mcg_bsc_no_hflip:
                TEST    BYTE PTR [BP+0CH], 1
                JZ      SHORT mcg_bsc_no_vflip
                MOV     AX, [BP-4]
                MUL     WORD PTR [BP-2]
                SUB     AX, [BP-4]
                ADD     SI, AX
mcg_bsc_no_vflip:
                MOV     DI, [BP+0AH]            ; y
                SHL     DI, 1
                MOV     DI, ds:[DI].GfxContext.pRow_offset_lut
                ADD     DI, [BP+8]
                MOV     DX, [BP-4]
                MOV     AX, [BP-2]
                MOV     cs:[g_nMcgSpriteClipRows], AX
                MOV     AL, ds:[GfxContext.bClip_enabled]
                XOR     BX, BX
                OR      AL, AL
                JNZ     SHORT mcg_bsc_clip_chk_x
                JMP     mcg_bsc_dispatch
mcg_bsc_clip_chk_x:
                MOV     AX, ds:[GfxContext.nClip_xmax]              ; clip right
                SUB     AX, [BP+8]
                MOV     CX, DX
                SUB     AX, CX
                JNS     SHORT mcg_bsc_clip_chk_y
                NEG     AX
                DEC     AX
                MOV     BX, AX
                SUB     DX, AX
                SUB     AX, [BP-4]
                JC      SHORT mcg_bsc_clip_chk_y
                JMP     mcg_bsc_done
mcg_bsc_clip_chk_y:
                MOV     AX, ds:[GfxContext.nClip_ymax]            ; clip bottom
                SUB     AX, [BP+0AH]
                MOV     CX, cs:[g_nMcgSpriteClipRows]
                SUB     AX, CX
                JNS     SHORT mcg_bsc_clip_chk_top
                NEG     AX
                DEC     AX
                SUB     cs:[g_nMcgSpriteClipRows], AX
                JA      SHORT mcg_bsc_clip_chk_top
                JMP     mcg_bsc_done
mcg_bsc_clip_chk_top:
                MOV     AX, ds:[GfxContext.nClip_ymin]              ; clip top
                SUB     AX, [BP+0AH]
                JLE     SHORT mcg_bsc_clip_chk_left
                SUB     cs:[g_nMcgSpriteClipRows], AX
                PUSH    DX
                XOR     DX, DX
                MUL     WORD PTR [BP-4]
                POP     DX
                TEST    BYTE PTR [BP+0CH], 1
                JZ      SHORT mcg_bsc_pos_y
                NEG     AX
mcg_bsc_pos_y:
                ADD     SI, AX
                MOV     DI, ds:[GfxContext.nClip_ymin]
                SHL     DI, 1
                MOV     DI, ds:[DI].GfxContext.pRow_offset_lut
                ADD     DI, [BP+8]
                MOV     AX, cs:[g_nMcgSpriteClipRows]
                OR      AX, AX
                JZ      SHORT mcg_srn_to_epi    ; jump via trampoline @ 0x0B34
                JNS     SHORT mcg_bsc_clip_chk_left
                JMP     mcg_bsc_done
mcg_bsc_clip_chk_left:
                MOV     AX, ds:[GfxContext.nClip_xmin]              ; clip left
                SUB     AX, [BP+8]
                JLE     SHORT mcg_bsc_dispatch
                ADD     DI, AX
                MOV     BX, AX
                TEST    BYTE PTR [BP+0CH], 2
                JZ      SHORT mcg_bsc_skip_hadj
                SUB     SI, AX
                SUB     SI, AX
mcg_bsc_skip_hadj:
                ADD     SI, AX
                SUB     DX, AX
                SUB     AX, [BP-4]
                JC      SHORT mcg_bsc_dispatch
                JMP     mcg_bsc_done
mcg_bsc_dispatch:
                MOV     AX, [BP-0AH]
                MOV     DS, AX
                PUSH    BX
                MOV     BX, [BP+0CH]            ; flip_flags
                SHL     BX, 1
                MOV     AX, cs:[BX+0A05H]
                POP     BX
                JMP     AX
                ;
                ; Fall through into the dispatch targets at 0x0B16.
                ;
mcg_blit_sprite_clipped ENDP

; ============================================================================
; mcg_sprite_row_noflip -- no-flip sprite row primitive.
; chunk:0x0B16..0x0B35.  Jumped to from mcg_blit_sprite_clipped dispatch.
;
; ABI on entry: SI=source, DI=dest base, DX=width, BX=src-stride-delta,
; CS:[0xA03] = remaining row count. Falls through to
; mcg_sprite_blit_epilogue (0x0BAA) via the trailing JMP.
; ============================================================================
mcg_sprite_row_noflip PROC FAR
                MOV     BP, 0140H
                MOV     AX, DX
                SUB     BP, AX
mcg_srn_row_setup:
                MOV     CX, DX
mcg_srn_pix:
                LODSB
                OR      AL, AL
                JZ      SHORT mcg_srn_skip
                STOSB
                DEC     DI
mcg_srn_skip:
                INC     DI
                LOOP    SHORT mcg_srn_pix
                ADD     SI, BX
                ADD     DI, BP
                DEC     WORD PTR cs:[g_nMcgSpriteClipRows]
                JNZ     SHORT mcg_srn_row_setup
mcg_srn_to_epi:
                JMP     SHORT mcg_sprite_blit_epilogue
mcg_sprite_row_noflip ENDP

; ============================================================================
; mcg_sprite_row_vflip -- vertical-flip sprite row primitive.
; chunk:0x0B36..0x0B5D.  Reverses source advance per row (BX -= 2*width).
; ============================================================================
mcg_sprite_row_vflip PROC FAR
                SUB     BX, [BP-4]
                SUB     BX, [BP-4]
                MOV     BP, 0140H
                MOV     AX, DX
                SUB     BP, AX
                XOR     CX, CX
mcg_srv_row:
                MOV     CX, DX
mcg_srv_pix:
                LODSB
                OR      AL, AL
                JZ      SHORT mcg_srv_skip
                STOSB
                DEC     DI
mcg_srv_skip:
                INC     DI
                LOOP    SHORT mcg_srv_pix
                ADD     SI, BX
                ADD     DI, BP
                DEC     WORD PTR cs:[g_nMcgSpriteClipRows]
                JNZ     SHORT mcg_srv_row
                JMP     SHORT mcg_sprite_blit_epilogue
mcg_sprite_row_vflip ENDP

; ============================================================================
; mcg_sprite_row_hflip -- horizontal-flip sprite row primitive.
; chunk:0x0B5E..0x0B87.  Reads source via [SI] then DEC SI (decrement).
; ============================================================================
mcg_sprite_row_hflip PROC FAR
                SUB     BX, [BP-4]
                SUB     BX, [BP-4]
                MOV     BP, 0140H
                MOV     AX, DX
                SUB     BP, AX
                XOR     CX, CX
mcg_srh_row:
                MOV     CX, DX
mcg_srh_pix:                                    ; LOOP target (read MOV AL,[SI])
                MOV     AL, [SI]
                DEC     SI
                OR      AL, AL
                JZ      SHORT mcg_srh_skip
                STOSB
                DEC     DI
mcg_srh_skip:
                INC     DI
                LOOP    SHORT mcg_srh_pix
                SUB     SI, BX
                ADD     DI, BP
                DEC     WORD PTR cs:[g_nMcgSpriteClipRows]
                JNZ     SHORT mcg_srh_row
                JMP     SHORT mcg_sprite_blit_epilogue
mcg_sprite_row_hflip ENDP

; ============================================================================
; mcg_sprite_row_hvflip -- both-flips sprite row primitive.
; chunk:0x0B88..0x0BA9.  Combines vflip's source step and hflip's read direction.
; Note: no trailing JMP -- falls through into mcg_sprite_blit_epilogue.
; ============================================================================
mcg_sprite_row_hvflip PROC FAR
                MOV     BP, 0140H
                MOV     AX, DX
                SUB     BP, AX
                XOR     CX, CX
mcg_srhv_row:
                MOV     CX, DX
mcg_srhv_pix:                                   ; LOOP target
                MOV     AL, [SI]
                DEC     SI
                OR      AL, AL
                JZ      SHORT mcg_srhv_skip
                STOSB
                DEC     DI
mcg_srhv_skip:
                INC     DI
                LOOP    SHORT mcg_srhv_pix
                SUB     SI, BX
                ADD     DI, BP
                DEC     WORD PTR cs:[g_nMcgSpriteClipRows]
                JNZ     SHORT mcg_srhv_row
                ; falls through into mcg_sprite_blit_epilogue
mcg_sprite_row_hvflip ENDP

; ============================================================================
; mcg_sprite_blit_epilogue -- shared 9-byte cleanup tail for the 4 sprite
; row primitives. chunk:0x0BAA..0x0BB2.
;
; Frees the 10-byte stack-local block reserved in
; mcg_blit_sprite_clipped's prologue (`SUB SP, 0xA`) and restores all
; saved regs.
; ============================================================================
mcg_sprite_blit_epilogue PROC FAR
mcg_bsc_done:
                POP     DS
                POP     ES
                POP     SI
                POP     DI
                ADD     SP, 0AH
                POP     BP
                RETF
mcg_sprite_blit_epilogue ENDP

; ============================================================================
; mcg_blit_chunky_rect_to_video -- blit chunky rect to video (slot 30).
; chunk:0x0BB3..0x0C30.
; __cdecl16far(rect_descriptor, x, y).
;
; Unrolled 8-row loop (Duff's-device shape) copying a chunky rectangle
; from a caller-supplied source into the visible framebuffer at
; scanline_lut[y] + x.
;
; rect_descriptor layout (from the field reads in the prologue):
;   [+0]  ushort  src_seg      (loaded into DS)
;   [+2]  ushort  src_off      (loaded into SI)
;   [+4]  ushort  -- unused by this function; not read
;   [+6]  ushort  width_bytes  (also halved into BX = width_words)
;   [+8]  ushort  height       (DX outer-loop counter)
;
; Per-row destination DI step after `REP MOVSW` = 320 - width_bytes
; (stashed in BP and added to DI between rows). The source advances
; tightly through MOVSW with no gap, so the descriptor implicitly
; treats the source as a packed rect of width_bytes per row.
;
; The 8x copy of (MOV CX,BX / REP MOVSW / ADD DI,BP / DEC DX / JZ exit)
; is loop unrolling to amortise the per-row
; bookkeeping over 8 rows.
; ============================================================================
mcg_blit_chunky_rect_to_video PROC FAR
                PUSH    BP
                MOV     BP, SP
                PUSH    SI
                PUSH    DI
                PUSH    DS
                MOV     DS, cs:[g_wMcgChunkDataSeg]

                ; ES:DI = framebuffer + scanline_lut[y] + x.
                MOV     DI, [BP+0AH]            ; y
                SHL     DI, 1
                MOV     DI, ds:[DI].GfxContext.pRow_offset_lut
                ADD     DI, [BP+8]              ; + x

                ; Switch BP to point at the rect_descriptor (saved
                ; on the stack as [BP+6] before this MOV). After this,
                ; [BP] / [BP+2] / [BP+6] / [BP+8] index into the
                ; rect_descriptor struct, not the caller's frame.
                MOV     BP, [BP+6]              ; BP = &rect_descriptor
                MOV     ES, ds:[GfxContext.wGfxBlitDstPage]          ; ES = visible-FB seg
                MOV     DX, [BP+8]              ; height (rows)
                MOV     BX, [BP+6]              ; width_bytes
                MOV     SI, [BP+2]              ; src_off
                MOV     DS, [BP]                ; src_seg
                MOV     BP, 0140H               ; 320 (one row of mode-13h)
                SUB     BP, BX                  ; BP = 320 - width_bytes
                                                ;  (per-row DI step after REP MOVSW)
                SHR     BX, 1                   ; BX = width_words

                ; ----- Unrolled 8-row blit loop.
                ; Each iteration of the outer loop does up to 8 rows
                ; of `REP MOVSW + ADD DI,BP` before re-testing the
                ; loop-top condition. Mid-block `DEC DX / JZ exit`
                ; rungs let the loop bail at any row boundary. Saves
                ; ~7 LOOP overhead per 8 rows.
mcg_bcrtv_loop_top:
                MOV     CX, BX                  ; row 0 of 8
                REP     MOVSW
                ADD     DI, BP
                DEC     DX
                JZ      SHORT mcg_bcrtv_exit
                MOV     CX, BX                  ; row 1
                REP     MOVSW
                ADD     DI, BP
                DEC     DX
                JZ      SHORT mcg_bcrtv_exit
                MOV     CX, BX                  ; row 2
                REP     MOVSW
                ADD     DI, BP
                DEC     DX
                JZ      SHORT mcg_bcrtv_exit
                MOV     CX, BX                  ; row 3
                REP     MOVSW
                ADD     DI, BP
                DEC     DX
                JZ      SHORT mcg_bcrtv_exit
                MOV     CX, BX                  ; row 4
                REP     MOVSW
                ADD     DI, BP
                DEC     DX
                JZ      SHORT mcg_bcrtv_exit
                MOV     CX, BX                  ; row 5
                REP     MOVSW
                ADD     DI, BP
                DEC     DX
                JZ      SHORT mcg_bcrtv_exit
                MOV     CX, BX                  ; row 6
                REP     MOVSW
                ADD     DI, BP
                DEC     DX
                JZ      SHORT mcg_bcrtv_exit
                MOV     CX, BX                  ; row 7
                REP     MOVSW
                ADD     DI, BP
                DEC     DX
                JNZ     SHORT mcg_bcrtv_loop_top
mcg_bcrtv_exit:
                POP     DS
                POP     DI
                POP     SI
                POP     BP
                RETF
mcg_blit_chunky_rect_to_video ENDP

; ============================================================================
; mcg_slot31_passthrough -- slot 31 passthrough.
; chunk:0x0C31..0x0C38.
; __cdecl16far(x) -> x.
;
; Returns the first stack-passed argument unchanged in AX. The exact
; semantic of slot 31 across the driver family is not nailed down --
; in MCG it's a no-op pass-through that the host can use as an identity
; function; the planar driver variants may implement non-trivial work
; in the corresponding slot.
; ============================================================================
mcg_slot31_passthrough PROC FAR
                PUSH    BP
                MOV     BP, SP
                MOV     AX, [BP+6]
                POP     BP
                RETF
mcg_slot31_passthrough ENDP

; ============================================================================
; mcg_dos_freemem_block_unused -- DOS freemem-block thunk (slot 32, unused).
; chunk:0x0C39..0x0C49.
; __cdecl16far(far_block_ptr).
;
; Calls INT 21h AH=49h (DOS free memory block) on the given far pointer.
; Mirror of cga_dos_freemem_block_unused -- dead-code in the normal flow.
; ============================================================================
mcg_dos_freemem_block_unused PROC FAR
                PUSH    BP
                MOV     BP, SP
                MOV     BP, [BP+6]
                MOV     ES, [BP]
                MOV     AH, 49H
                INT     21H
                POP     BP
                RETF
mcg_dos_freemem_block_unused ENDP

; ============================================================================
; g_nMcgSpriteClipRowCount @ 0x0C48 -- scratch global for mcg_slot33_helper's
; per-call row counter (analogue of g_nMcgSpriteClipRows @ 0x0A03 for slot 29).
; Zero on disk; 2 bytes alignment. Read/written via CS:[0x0C48] from within
; mcg_slot33_helper.
; ============================================================================
g_nMcgSpriteClipRowCount DW 0   ; 0x0C48

; ============================================================================
; mcg_slot33_helper -- clipped sprite blit, no flip (slot 33).
; chunk:0x0C4A..0x0D3B.
; __cdecl16far(sprite_record, x, y) -> clipped row count.
;
; Mirror of mcg_blit_sprite_clipped (slot 29) but without the flip
; dispatch -- a simpler clipped sprite-blit. Reads the same clip-rect
; globals at scratch:[0x3..0xA]. Stride 0x140. Uses scratch global
; g_nMcgSpriteClipRowCount (0x0C48) as a temp row-counter.
; ============================================================================
mcg_slot33_helper PROC FAR
                PUSH    BP
                MOV     BP, SP
                SUB     SP, 0AH
                PUSH    DI
                PUSH    SI
                PUSH    ES
                PUSH    DS
                MOV     SI, [BP+6]
                MOV     DI, BP
                SUB     DI, 0AH
                MOV     AX, SS
                MOV     ES, AX
                MOV     CX, 5
                REP     MOVSW
                MOV     DS, cs:[g_wMcgChunkDataSeg]
                MOV     AX, ds:[GfxContext.wGfxBlitDstPage]
                MOV     ES, AX
                MOV     SI, [BP-8]
                MOV     DI, [BP+0AH]
                SHL     DI, 1
                MOV     DI, ds:[DI].GfxContext.pRow_offset_lut
                ADD     DI, [BP+8]
                MOV     DX, [BP-4]
                MOV     AX, [BP-2]
                MOV     cs:[g_nMcgSpriteClipRowCount], AX
                MOV     AL, ds:[GfxContext.bClip_enabled]
                XOR     BX, BX
                OR      AL, AL
                JNZ     SHORT mcg_s33_clip_x
                JMP     SHORT mcg_s33_row_loop
mcg_s33_clip_x:
                MOV     AX, ds:[GfxContext.nClip_xmax]
                SUB     AX, [BP+8]
                MOV     CX, DX
                SUB     AX, CX
                JNS     SHORT mcg_s33_clip_y
                NEG     AX
                DEC     AX
                MOV     BX, AX
                SUB     DX, AX
                SUB     AX, [BP-4]
                JC      SHORT mcg_s33_clip_y
                JMP     mcg_s33_done
mcg_s33_clip_y:
                MOV     AX, ds:[GfxContext.nClip_ymax]
                SUB     AX, [BP+0AH]
                MOV     CX, cs:[g_nMcgSpriteClipRowCount]
                SUB     AX, CX
                JNS     SHORT mcg_s33_clip_top
                NEG     AX
                DEC     AX
                SUB     cs:[g_nMcgSpriteClipRowCount], AX
                JA      SHORT mcg_s33_clip_top
                JMP     SHORT mcg_s33_done
mcg_s33_clip_top:
                MOV     AX, ds:[GfxContext.nClip_ymin]
                SUB     AX, [BP+0AH]
                JLE     SHORT mcg_s33_clip_left
                SUB     cs:[g_nMcgSpriteClipRowCount], AX
                DEC     AX
                PUSH    DX
                XOR     DX, DX
                MUL     WORD PTR [BP-4]
                POP     DX
                ADD     SI, AX
                MOV     DI, ds:[GfxContext.nClip_ymin]
                SHL     DI, 1
                MOV     DI, ds:[DI].GfxContext.pRow_offset_lut
                ADD     DI, [BP+8]
                MOV     AX, cs:[g_nMcgSpriteClipRowCount]
                OR      AX, AX
                JZ      SHORT mcg_s33_done
                JNS     SHORT mcg_s33_clip_left
                JMP     SHORT mcg_s33_done
mcg_s33_clip_left:
                MOV     AX, ds:[GfxContext.nClip_xmin]
                SUB     AX, [BP+8]
                JLE     SHORT mcg_s33_row_loop
                ADD     DI, AX
                MOV     BX, AX
                ADD     SI, AX
                SUB     DX, AX
                SUB     AX, [BP-4]
                JC      SHORT mcg_s33_row_loop
                JMP     SHORT mcg_s33_done
mcg_s33_row_loop:
                MOV     AX, [BP-0AH]
                MOV     DS, AX
                MOV     BP, 0140H
                MOV     AX, DX
                SUB     BP, AX
mcg_s33_row_setup:
                MOV     CX, DX
mcg_s33_pix:
                LODSB
                OR      AL, AL
                JZ      SHORT mcg_s33_pix_skip
                STOSB
                DEC     DI
mcg_s33_pix_skip:
                INC     DI
                LOOP    SHORT mcg_s33_pix
                ADD     SI, BX
                ADD     DI, BP
                DEC     WORD PTR cs:[g_nMcgSpriteClipRowCount]
                JNZ     SHORT mcg_s33_row_setup
mcg_s33_done:
                POP     DS
                POP     ES
                POP     SI
                POP     DI
                ADD     SP, 0AH
                POP     BP
                RETF
mcg_slot33_helper ENDP

                END     _start








