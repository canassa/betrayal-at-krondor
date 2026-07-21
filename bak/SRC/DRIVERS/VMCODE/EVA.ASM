; ============================================================================
; Vmcode.OVL.EVA -- EVA video driver chunk (7687 bytes, 0x1E07)
;
; Shipped with "Betrayal at Krondor" (Dynamix / Sierra, 1993). Image base
; 0000:0000.
;
; The chunk is one of eight interchangeable graphics drivers in Vmcode.ovl.
; "EVA" stands for "EGA-VGA Approximation": pure-EGA 640x200x16 (BIOS mode
; 0Eh) that uses ordered dithering through two 256-byte bit-spread LUTs
; (at chunk:0x4E1 / 0x5E1) to approximate the VGA 256-colour palette in
; only 16 EGA colours. No DAC writes -- the driver assumes a real EGA card
; with its fixed 64-of-262144 palette ROM mapping.
;
; KRONDOR.EXE loads it via the RES-archive loader, runs its init prologue
; once, then snapshots its 50-slot vtable template into the host's
; renderer dispatch table for ordinary far-call dispatch.
; ============================================================================

; ----------------------------------------------------------------------------
; About the EGA hardware (the registers this driver pokes)
;
; Mode 0Eh is 640 x 200 x 16-of-64 EGA hi-res. "16 of 64" means 16 palette
; slots, each programmable to one of 64 fixed colours from a hard-wired ROM
; gamut (the EGA has no DAC -- see DAC note below).
;
; - Framebuffer at A000:0000, 4 planes, 1 bit per plane per pixel, packed
;   8 pixels per byte (MSB = leftmost pixel). 640 x 200 mode 0Eh:
;     80 bytes/scanline (640 / 8)  x  200 scanlines  =  16,000 bytes per
;     plane -- this rounds up to a 16 KB page in the CPU's address window
;     (A000:0000..A000:3FFF). All 4 planes share that 16 KB window
;     simultaneously (32 bits of plane VRAM per CPU address); the
;     Sequencer Map Mask gates which planes a write lands on, GC Read
;     Map Select gates which plane a read returns. Total framebuffer
;     across 4 planes is therefore 16 KB CPU-visible / 64 KB physical.
;     [IBM Options Adapters vol. 2, ch. EGA; FreeVGA vgamem.]
;
;   Additional pages (page-flip) live at A000:4000, A000:8000, A000:C000.
;   The driver allocates A000 (front), A400 (back A), A800 (back B) for
;   page-flip -- 3 pages of 16 KB each = 48 KB. This requires 128 KB+
;   on-card VRAM; the original 64 KB EGA only supports a single page
;   in mode 0Eh.
;
; - Sequencer (index port 0x3C4, data port 0x3C5):
;     index 2 = Map Mask. Selects which of the 4 planes a CPU write
;               actually lands on. Bits 0..3 enable planes 0..3.
;     (BIOS mode 0Eh init programs SR0..SR4; this driver only touches
;     SR2. See FreeVGA seqreg.htm.)
;
; - Graphics Controller (index port 0x3CE, data port 0x3CF):
;     index 0 = Set/Reset. 4-bit colour value used by Write Mode 0 (when
;               Enable Set/Reset selects it per-plane) and Write Mode 3
;               (always; VGA-only, not used here). Unused by this driver.
;     index 1 = Enable Set/Reset. Per-plane bit; if set, the corresponding
;               plane writes the Set/Reset value rather than the CPU data.
;               Unused (left at BIOS default 0).
;     index 3 = Data Rotate / Function. Bits 0..2 = right-rotate count,
;               bits 3..4 = logical op (00=copy, 01=AND, 10=OR, 11=XOR).
;     index 4 = Read Map Select (selects which plane a CPU read returns;
;               see eva_rect_capture / eva_rect_save).
;     index 5 = Mode register. Bits 0..1 = write mode (00/01/10 used
;               here; 11 = Write Mode 3 is VGA-only, never used).
;               Bit 3 = read mode (left at 0 = "single plane via GR4").
;     index 8 = Bit Mask. One bit per pixel-column within the byte; mask
;               bit 0 -> that pixel is unchanged (taken from the latch),
;               mask bit 1 -> that pixel is overwritten by the write
;               pipeline. Same mask broadcasts to all 4 planes.
;     [FreeVGA graphreg.htm.]
;
; - Attribute Controller (single port 0x3C0):
;     Programs the 16 palette registers (each a 6-bit RrGgBb colour-ROM
;     index) and the overscan / mode bits. Flip-flop port protocol: a
;     read of 0x3DA forces the flip-flop to "index next", then alternate
;     OUT 0x3C0 writes target index / value. AC accesses must be bracketed
;     CLI..STI because any interrupt that touches the AC mid-write will
;     corrupt the flip-flop. **200-line palette quirk**: on a true IBM
;     5154 monitor in mode 0Eh, the AR0..AR0F values have NO visible
;     effect -- the positive VSYNC polarity tells the monitor "this is a
;     CGA-style 4-bit signal", which masks the secondary RGB pins. AR
;     ops still work on a VGA monitor (the AC's 6-bit output feeds the
;     DAC); all 1993 BAK players had a VGA display, so the driver still
;     bothers. [reenigne.org on the 200-line quirk.]
;     This driver's only AC code is eva_palette_register_set (NEAR helper,
;     possibly dead -- see its plate); identity-loads AR0..AR0F.
;
; - CRTC (index/data ports at BIOS-stashed 40:0063, normally 0x3D4/0x3D5):
;     This driver writes only CRTC index 0Ch (Start Address High) in
;     eva_vsync_wait to flip the visible page when swapping the back-buffer
;     pair. The full CRTC programming is BIOS's job; we don't touch
;     timings, cursor, or overscan.
;
; - Input Status Register 1 (read-only port 0x3DA): bit 3 = vertical
;   retrace active. Polled in eva_vsync_wait for tear-free page-flips.
;   Also doubles as the AC flip-flop reset (any read clears it).
;
; - DAC: not used. The EGA has no DAC -- its AC output goes directly to
;   the monitor as 6 TTL pins. Ports 0x3C7/0x3C8/0x3C9 (VGA-only DAC
;   index/data) are never touched. Port 0x3CC (VGA-only Misc Output
;   read) is likewise never touched. The driver is a pure-EGA codepath.
;
; FreeVGA reference: www.osdever.net/FreeVGA/home.htm.
; ----------------------------------------------------------------------------

; ----------------------------------------------------------------------------
; EGA write modes, latches, and "what a STOSB into A000h means"
;
; The CPU can't poke individual pixels in EGA mode 0Eh -- each pixel is a
; 4-bit value scattered across 4 planes, and the CPU only has an 8-bit
; data bus to A000h. Instead, the GC sits between the CPU and the four
; plane RAMs and rewrites every read/write. The behaviour is configured
; by the Graphics Controller "Mode" register (port 0x3CE index 5):
;
;   The four latch registers (one per plane, internal to the GC) sit
;   between the CPU and the plane RAMs. Any CPU *read* from A000h
;   broadcasts that byte address to all four planes simultaneously and
;   captures all four into the latches -- in 4 bus cycles' worth of one
;   read. The latch values are then available to merge with the next
;   CPU write (Write Mode 0/2) or to be written verbatim (Write Mode 1).
;   The CPU never sees more than one plane on a read; the multi-plane
;   value lives only in the GC's latches. [FreeVGA vgamem.htm.]
;
;   Write mode 0 (used by chunky-to-planar, fill rect when "set/reset" is
;                 active, sprite blits, line draw):
;     The byte the CPU writes is masked by the Bit Mask register; bit-
;     positions where the mask is 1 are taken from the CPU data (or the
;     Set/Reset register when Enable-Set/Reset's plane bit is 1), bit-
;     positions where the mask is 0 are taken from the corresponding
;     plane's *latch* register. The canonical EGA "modify these pixels,
;     keep those" idiom is therefore "dummy-read to fill latches, then
;     write the CPU byte"; you will see this pattern at almost every
;     framebuffer write in the file:
;
;           MOV AL, es:[DI]   ; latch fill (AL value is discarded)
;           MOV es:[DI], CL   ; effective write -- merges with latches
;
;   Write mode 1 (used by eva_blit_frame_present's planar->planar copy):
;     The byte the CPU writes is *ignored*. Instead, the 4 latch bytes
;     (captured by the immediately-preceding read from A000h) are written
;     verbatim, one to each plane. So a `REP MOVSB` loop -- which is
;     LODSB+STOSB internally -- reads one A000h byte into the 4 latches,
;     then writes those latches back to a different A000h byte: a single
;     `MOVSB` actually moves 32 bits of plane data (8 px * 4 planes) at
;     CPU bus speed. This is the fast path for "copy this rect from
;     buffer A to buffer B".
;
;   Write mode 2 (used by eva_polygon_span_fill, eva_fill_rect, eva_line,
;                 eva_draw_line):
;     The low 4 bits of the CPU byte are a colour index. Bit N is broadcast
;     to all 8 bit-positions of plane N (so bit 0 -> all 8 bits of plane 0
;     in that byte, bit 1 -> plane 1, ..., bit 3 -> plane 3); planes 4..7
;     are ignored. The Bit Mask register (GC[8]) then gates which of the 8
;     pixel positions actually update -- so this is the write mode for
;     "paint these pixels with this colour": colour in CPU AL low nibble,
;     pixel-position mask in GC[8].
;
; Other GC registers used here:
;   index 0  Set/Reset           pre-loaded with a 4-bit colour for mode 0
;   index 1  Enable Set/Reset    per-plane bit; if set, plane's data comes
;                                from Set/Reset, not CPU
;   index 3  Data Rotate / FN    bits 0..2 rotate count, bits 3..4 logical
;                                op (00=copy, 01=AND, 10=OR, 11=XOR);
;                                we use op=00 (mode 0/2) and op=10 (when
;                                eva_blit_chunky_to_planar_v2 writes
;                                AX=1003h -> OR mode -- bit 4 = 1)
;   index 4  Read Map Select     selects which one of the 4 planes a CPU
;                                *read* returns (used by eva_rect_save)
;   index 5  Mode register       (see above)
;   index 8  Bit Mask            1-bit-per-pixel mask within the byte;
;                                only pixels where mask=1 are modified
;
; See FreeVGA "VGA Memory" (osdever.net/FreeVGA/vga/vgamem.htm) and
; "Graphics Registers" (osdever.net/FreeVGA/vga/graphreg.htm) for the
; full register-level state machine.
; ----------------------------------------------------------------------------

; ----------------------------------------------------------------------------
; Dither LUT layout
;
; The two 256-byte tables at chunk:0x04E1 (g_abEvaBitSpreadLutEven) and
; chunk:0x05E1 (g_abEvaBitSpreadLutOdd) are bit-spread tables: each maps
; a chunky source byte (1 byte per pixel, 0..255) to a planar bit pattern
; for one of the four EGA planes, with an even/odd-row ordered-dither phase
; baked in. Together with the EGA palette (16 colours chosen by
; eva_palette_set out of the 64-colour EGA gamut) they synthesise a much
; larger apparent colour count than the 16 hardware indices would suggest.
;
; "Even" vs "Odd" is selected by row parity at the call site -- a single
; dither pattern would produce uniform colour bands; alternating between
; the two LUTs every row produces the 2x2 ordered-dither cell that
; makes the EGA approximation acceptable. Switching between them costs
; one byte in BX: `BX += 0x100` flips between the two LUT pages because
; they sit at adjacent 256-byte boundaries (E1h / 1E1h).
; ----------------------------------------------------------------------------

; ----------------------------------------------------------------------------
; Vmcode.OVL chunk ABI -- how the host talks to this driver
;
; Vmcode.OVL is the game's bag of swappable graphics drivers. KRONDOR.EXE
; loads the appropriate chunk (CGA, EGA-VGA-Approx, MCGA, etc.) at
; startup and uses it through a uniform "50-slot vtable" interface.
; All slot calls share the same protocol:
;
;   1. The host loads the chunk to some unknown segment S and far-calls
;      `eva_init` (the chunk's first byte) once. eva_init returns
;      DX:SI = S:0x00B6, which points at a header block followed by the
;      50-slot vtable at S:0x00BA.
;
;   2. The host iterates the 50-slot vtable, stamps S into every entry's
;      segment half (each entry on disk is `dw offset, 0`), and copies
;      the result into a global jump table.
;
;   3. From then on the host invokes each slot by `CALL FAR [vtable+i*4]`
;      -- a __cdecl16far call where args are pushed right-to-left on the
;      stack and the callee returns with RETF (cleanup is caller-side).
;
; Some slots also take their args in registers (the register-ABI slots like
; eva_draw_line and eva_get_pixel). Each function's plate below names
; the convention used.
;
; The 18-entry "host callbacks" table at chunk:0x017E (overlapping vtable
; slot 49 on disk, populated by REP MOVSW in eva_init) is the *reverse*
; direction -- pointers the chunk uses to call back into the host for
; services it doesn't implement itself.
;
; Per-driver slot numbers are not portable across drivers; see the
; vtable region below (chunk:0x00BA) for EVA's slot assignment.
; ----------------------------------------------------------------------------

; ----------------------------------------------------------------------------
; How to read this source
;
; - TASM numeric-literal parser: hex literals starting with a letter must
;   be prefixed with `0` (write `0AH`, not `AH` -- `AH` parses as a
;   register). The `H` suffix marks hex.
;
; - This is a flat, single-segment chunk -- code and data share one
;   segment. Almost every memory access uses an explicit `cs:` segment
;   override because the host does not guarantee DS at slot entry; the
;   chunk re-loads DS from `cs:[00B2H]` (the page-aligned scratch-data
;   paragraph, computed by eva_init) whenever it needs scratch memory.
;
; - Most slot handlers are `PROC FAR` because they are entered via the
;   vtable's far call. Internal helpers (eva_palette_register_set,
;   eva_palette_find_nearest_rgb) are `PROC NEAR` -- the difference
;   affects only the RET encoding (CB = RETF, C3 = RETN). Where a
;   near-RET appears inside a FAR proc (a hand-coded early-exit) you'll
;   see an explicit `RETN` mnemonic to override TASM's "infer from
;   surrounding PROC" rule.
;
; - Calling conventions vary per function. Each function plate spells
;   out the inputs / outputs / globals it touches; do not assume cdecl
;   stack args. eva_fill_rect, eva_draw_line, eva_get_pixel, and the
;   eva_palette_load chain are register-passed and have no stack frame.
;
; - Local labels inside a function are prefixed with a 3-4 letter
;   nickname for the enclosing function (e.g. `eva_psf_p1_wide` inside
;   eva_polygon_span_fill, `eva_bsm_hfl_loop` inside
;   eva_blit_sprite_master). Avoids cross-function collisions without
;   resorting to TASM's anonymous-label patterns.
;
; - `XLAT BYTE PTR CS:[BX]` is how TASM spells the CS-segment-override
;   form of XLAT (bytes `2E D7`). XLAT's default segment is DS; the
;   eva_blit_*, eva_fill_rect, eva_draw_line, and eva_palette_* paths
;   all use the CS form because they want to look up bytes in chunk-
;   local tables (the bit-spread LUTs and the pixel-mask LUT) without
;   disturbing DS.
;
; - Encoding-significant XCHG/TEST quirk: TASM picks a different opcode
;   byte depending on operand order (`XCHG AH, AL` -> 86 E0,
;   `XCHG AL, AH` -> 86 C4). Borland's compiler uses the AL/CX-first
;   form consistently -- so in this file `XCHG AL, AH` and `XCHG CX, BX`
;   are written that way even though they're semantically symmetric.
;   Same for TEST.
; ----------------------------------------------------------------------------

                .8086
                .MODEL  TINY
                .CODE
                ORG     0
; A STRUC definition emits no bytes. GFXCTX.INC lives
; in this directory; TASM finds it via /iSRC\DRIVERS\VMCODE (see DRIVERS.MAK).
                INCLUDE gfxctx.inc
                ASSUME  ds:NOTHING, es:NOTHING

; ============================================================================
; eva_init -- chunk initialiser (PROC FAR, called via the host's video_init).
; chunk:0x0000..0x0094
;
; CALLER ABI (host-side far call, __cdecl16far):
;   [BP+0x06]  ushort  chunk_data_paragraphs   (page-aligned data seg size)
;   [BP+0x08]  ushort  host_callbacks_off
;   [BP+0x0a]  ushort  host_callbacks_seg
;
; SEQUENCE:
;   1. REP MOVSW copies 38 words (76 bytes) of host callback table from
;      [BP+0Ah]:[BP+8] (seg:off) -> CS:0x017E (the in-chunk callback-table tail
;      g_apEvaHostCallbacksTail). This overlaps vtable slot 49 on disk.
;   2. Stash chunk_data_paragraphs in CS:[0xB4] (g_wEvaChunkDataSeg);
;      compute page-aligned data seg in CS:[0xB2]
;      (g_wEvaPageAlignedDataSeg = chunk_data_paragraphs >> 4 + DS).
;   3. Switch DS to the page-aligned data seg, then initialise scratch-DS
;      slots [0x21]=0xFF (no prior mode), [0x1F]=0x01, [0x14]=0xA000
;      (framebuffer), [0x12]=0xA400, [0x10]=0xA800 (back buffers A/B).
;   4. BIOS INT 10h AX=0Eh -- switch to BIOS mode 0Eh (EGA 640x200x16).
;   5. Build the 200-entry scanline-offset LUT at scratch:[0x6F2] with
;      stride 80 (640 px / 8 bits per byte).
;   6. OUT 0x3C4, AX=0F02h: Sequencer Map-Mask register = 0x0F (enable
;      writes to all 4 planes).
;   7. OUT 0x3CE, AX=0005h: GC Mode register = 0 (Mode 0 read / Mode 0
;      write).
;   8. Publish screen geometry into the scratch DS so the rest of the
;      driver and the host can read it:
;        scratch:[0x06EA] = 0x0140 (= 320; appears to be a screen-width
;                   field but the EGA mode is 640 wide, so the literal
;                   may instead be a logical / virtual width -- this
;                   remains an open question)
;        scratch:[0x0006] = scratch:[0x06EA] - 1 (= 319; "max x")
;        scratch:[0x000A] = scratch:[0x06EC] - 1 (= height-1 / "max y";
;                   scratch:[0x06EC] is host-supplied at chunk load)
;   9. RETF with AX=8 (success magic), DX:SI = CS:0x00B6 -- the 4-byte
;      palette-far-ptr placeholder followed by the 50-slot vtable at
;      CS:0x00BA.
;
; The host stamps the chunk's load segment into every segment-half of the
; vtable template and snapshots all 50 cells into its global renderer
; vtable for subsequent dispatch.
; ============================================================================
_start          LABEL   BYTE
eva_init        PROC    FAR
                PUSH    BP                      ; 55
                MOV     BP, SP                  ; 8B EC
                PUSH    DS                      ; 1E
                PUSH    SI                      ; 56
                PUSH    DI                      ; 57
                MOV     DI, 017EH               ; BF 7E 01  <- callback tail
                PUSH    CS                      ; 0E
                POP     ES                      ; 07
                MOV     SI, [BP+8]              ; 8B 76 08  arg1.off
                MOV     DS, [BP+0AH]            ; 8E 5E 0A  arg1.seg
                MOV     CX, 0026H               ; B9 26 00  38 words = 76 bytes
                REP     MOVSW                   ; F3 A5
                POP     DI                      ; 5F
                POP     SI                      ; 5E
                POP     DS                      ; 1F
                MOV     AX, [BP+6]              ; 8B 46 06
                MOV     cs:[0B4H], AX           ; 2E A3 B4 00  g_wEvaChunkDataSeg
                SHR     AX, 1                   ; D1 E8
                SHR     AX, 1                   ; D1 E8
                SHR     AX, 1                   ; D1 E8
                SHR     AX, 1                   ; D1 E8
                PUSH    DS                      ; 1E
                PUSH    DI                      ; 57
                MOV     BX, DS                  ; 8C DB
                ADD     AX, BX                  ; 03 C3
                MOV     cs:[0B2H], AX           ; 2E A3 B2 00  g_wEvaPageAlignedDataSeg
                MOV     DS, AX                  ; 8E D8
                MOV     BYTE PTR ds:[GfxContext.bActiveVgaMode], 0FFH  ; C6 06 21 00 FF
                MOV     BYTE PTR ds:[GfxContext.bGfxRenderStateFlag], 1 ; C6 06 1F 00 01
                MOV     AX, 0A000H              ; B8 00 A0
                MOV     ds:[GfxContext.wVgaFrontPageBase], AX ; A3 14 00   front fb seg (page 0 @ A000:0000)
                MOV     AX, 0A400H              ; B8 00 A4
                MOV     ds:[GfxContext.wVgaPage2Base], AX ; A3 12 00   back buf A seg (page 1 @ A000:4000)
                MOV     AX, 0A800H              ; B8 00 A8
                MOV     ds:[GfxContext.wVgaPage1Base], AX ; A3 10 00   back buf B seg (page 2 @ A000:8000)
                                                ;            3 x 16 KB pages -> needs 128 KB+ VRAM
                MOV     AX, 000EH               ; B8 0E 00   BIOS mode 0Eh (640x200x16 EGA)
                INT     10H                     ; CD 10      INT 10h AH=0 -- BIOS set-video-mode
                JMP     SHORT eva_init_lut      ; EB 00      branch-to-next
eva_init_lut:
                MOV     CX, 00C8H               ; B9 C8 00   200 rows
                MOV     DI, GfxContext.pRow_offset_lut ; BF F2 06   scratch-DS scanline LUT
                MOV     AX, DS                  ; 8C D8
                MOV     ES, AX                  ; 8E C0      ES = scratch DS
                XOR     AX, AX                  ; 33 C0
                CLD                             ; FC
eva_init_lut_loop:
                STOSW                           ; AB
                ADD     AX, 0050H               ; 05 50 00   +80 bytes per row
                LOOP    SHORT eva_init_lut_loop ; E2 FA
                MOV     DX, 03C4H               ; BA C4 03   Sequencer index
                MOV     AX, 0F02H               ; B8 02 0F   idx 2 (Map Mask) = 0x0F
                OUT     DX, AX                  ; EF
                MOV     DX, 03CEH               ; BA CE 03   GC index
                MOV     AX, 0005H               ; B8 05 00   idx 5 (Mode) = 0
                OUT     DX, AX                  ; EF
                MOV     DX, CS                  ; 8C CA
                MOV     SI, 00B6H               ; BE B6 00   palette-far-ptr placeholder
                ; Publish screen geometry into scratch DS. The literal
                ; 0x0140 = 320 here is suspicious -- BIOS mode 0Eh is
                ; 640 wide -- but every consumer reads it back unchanged
                ; so it may be a "logical / virtual width" rather than
                ; the hardware mode's physical width (an open question).
                MOV     AX, 0140H               ; B8 40 01   width literal (320)
                MOV     ds:[GfxContext.wScreen_width], AX ; A3 EA 06   scratch:[6EA] = width
                DEC     AX                      ; 48
                MOV     ds:[GfxContext.nClip_xmax], AX ; A3 06 00   scratch:[06] = width - 1
                MOV     AX, ds:[GfxContext.wScreen_height] ; A1 EC 06   scratch:[6EC] = host-supplied height
                DEC     AX                      ; 48
                MOV     ds:[GfxContext.nClip_ymax], AX ; A3 0A 00   scratch:[0A] = height - 1
                MOV     AX, 0008H               ; B8 08 00   success magic
                POP     DI                      ; 5F
                POP     DS                      ; 1F
                POP     BP                      ; 5D
                RETF                            ; CB
eva_init        ENDP

; ============================================================================
; eva_palette_register_set -- EGA Attribute-Controller palette setup helper.
; chunk:0x0095..0x00B1
;
; NEAR helper. On disk it is positioned immediately after eva_init; the
; vtable does not reference it directly, and no `CALL NEAR PTR` to
; offset 0x0095 appears anywhere else in the chunk source. It may
; nonetheless be reachable through one of the host-callback pointers
; that gets stamped into g_apEvaHostCallbacksTail at init time, or it
; may be genuinely dead code -- the chunk-local evidence is
; inconclusive.
;
; Programs all 15 Attribute-Controller palette registers (indices
; 1..0xFh) so that EGA palette index N maps to EGA palette ROM colour
; N (identity init).
;
; Standard EGA AC palette write sequence (one register's worth):
;   - Read 0x3DA to reset the AC's index/data flip-flop (the AC has a
;     single port 0x3C0 used for both index and data; the flip-flop
;     decides which on each write, and reading 0x3DA -- input status
;     register 1 -- forces it back to "index next" as a side effect).
;   - OUT 0x3C0, idx     ; the AC is now expecting a value next
;     JMP $+0            ; pipeline-flush filler that doubles as an
;                        ; I/O settling delay -- the OUTs to the AC
;                        ; need a few cycles to propagate before
;                        ; the next port write is decoded.
;     OUT 0x3C0, value
;     JMP $+0
;
; The IN AL, 0x3C0 / PUSH AX / OUT DX,AL at the function's bookends
; saves and restores the AC's "PAS" bit (Palette Address Source, bit 5
; of the AC's index byte). When PAS=1 the AR is in "display mode" --
; values written go nowhere and the monitor keeps showing the current
; palette; when PAS=0 the AR accepts palette loads but the screen
; blanks. The save/restore preserves whatever mode the BIOS / a prior
; caller had the AC in. (On strict IBM EGA the 0x3C0 read is not in
; the spec -- the AR address port is documented write-only -- but in
; practice the latched PAS+index byte reads back, and Borland-era
; drivers commonly depend on this.) See FreeVGA attrreg.htm.
;
; The CLI / STI bracket disables interrupts during the AC write window
; because an interrupt that calls any other AC-touching code mid-write
; would corrupt the flip-flop state.
;
; 200-LINE PALETTE QUIRK: this function would have no visible effect
; on an IBM 5154 ECD running mode 0Eh because the monitor masks AR
; secondary-RGB bits when it sees positive VSYNC (mode 0Eh's VSYNC
; polarity). The function still does the right thing for VGA monitors
; running the same code -- all 1993 BAK customers had VGA -- so the
; palette path is alive on real hardware.
; ============================================================================
eva_palette_register_set PROC NEAR
                MOV     CX, 000FH               ; B9 0F 00
                MOV     DX, 03C0H               ; BA C0 03
                IN      AL, DX                  ; EC
                PUSH    AX                      ; 50
eva_pal_reg_loop:
                CLI                             ; FA       LOOP target (interrupts already off
                                                ;          on second+ iter -- the CLI is just
                                                ;          part of the loop body)
                MOV     DX, 03DAH               ; BA DA 03
                IN      AL, DX                  ; EC      reset AC flip-flop via 0x3DA read
                MOV     DL, 0C0H                ; B2 C0   DX = 0x3C0 (AC address/data port)
                MOV     AL, CL                  ; 8A C1
                OUT     DX, AL                  ; EE      write AC index = CL (1..0xF)
                JMP     SHORT $+2               ; EB 00   I/O settling delay
                OUT     DX, AL                  ; EE      write AC value = same as index
                                                ;          (identity-init: AR[N] <- N)
                JMP     SHORT $+2               ; EB 00   I/O settling delay
                LOOP    SHORT eva_pal_reg_loop  ; E2 EF
                STI                             ; FB
                POP     AX                      ; 58
                OUT     DX, AL                  ; EE      restore saved PAS+index byte
                RET                             ; C3
eva_palette_register_set ENDP

; ============================================================================
; 0x00B2..0x00B9 -- chunk-local globals, zero-initialised on disk.
; ============================================================================
g_wEvaPageAlignedDataSeg DW     0       ; 0x00B2  scratch-DS paragraph
g_wEvaChunkDataSeg       DW     0       ; 0x00B4  saved chunk_data_paragraphs
g_apfnEvaActivePaletteFar DW    0, 0    ; 0x00B6  4-byte active palette far-ptr
                                        ;         placeholder; patched by
                                        ;         eva_palette_set / _load at
                                        ;         runtime. Init returns
                                        ;         DX:SI = CS:0x00B6 -- the
                                        ;         host snapshots the vtable
                                        ;         template starting +4.

; ============================================================================
; g_apfnEvaVtable -- 50-slot renderer-vtable template.
; chunk:0x00BA..0x0181 (200 bytes; 50 entries x 4 bytes each)
;
; Each entry is (offset_word, segment_placeholder_word). The host stamps the
; chunk's load segment into every segment half after init returns. Slot 49
; @ 0x017E overlaps with the first 4-byte entry of g_apEvaHostCallbacksTail;
; on disk that slot holds (eva_unimplemented_slot, 0) just like every other
; unimplemented slot, and at runtime the REP MOVSW in eva_init clobbers it
; with a host-provided callback. Either way, slot 49 is dead in EVA mode.
;
; Slots 38..48 are explicit NULLs on disk (the EVA driver doesn't implement
; them and never sees them invoked).
; ============================================================================
g_apfnEvaVtable LABEL DWORD
                DW      1D66H,  0               ; slot 0  -- eva_get_pixel
                DW      1AF9H,  0               ; slot 1  -- eva_draw_line
                DW      1D4CH,  0               ; slot 2  -- eva_put_pixel
                DW      0D05H,  0               ; slot 3  -- eva_blit_frame_present
                DW      140AH,  0               ; slot 4  -- eva_line
                DW      1481H,  0               ; slot 5  -- eva_sprite_buffer_size
                DW      1A7DH,  0               ; slot 6  -- eva_rect_capture
                DW      0B3CH,  0               ; slot 7  -- eva_vsync_wait
                DW      01CAH,  0               ; slot 8  -- eva_unimplemented_slot
                DW      0D92H,  0               ; slot 9  -- eva_fill_rect
                DW      01CAH,  0               ; slot 10 -- eva_unimplemented_slot
                DW      01CAH,  0               ; slot 11 -- eva_unimplemented_slot
                DW      0B83H,  0               ; slot 12 -- eva_image_install
                DW      0BB6H,  0               ; slot 13 -- eva_image_decode
                DW      0CB1H,  0               ; slot 14 -- eva_image_query_size
                DW      01CAH,  0               ; slot 15 -- eva_unimplemented_slot
                DW      01D3H,  0               ; slot 16 -- eva_blit_chunky_to_planar
                DW      02A0H,  0               ; slot 17 -- eva_blit_chunky_to_planar_v2
                DW      01CAH,  0               ; slot 18 -- eva_unimplemented_slot
                DW      07CBH,  0               ; slot 19 -- eva_present
                DW      12F7H,  0               ; slot 20 -- eva_rect_save
                DW      139EH,  0               ; slot 21 -- eva_rect_paste
                DW      01CAH,  0               ; slot 22 -- eva_unimplemented_slot
                DW      01CAH,  0               ; slot 23 -- eva_unimplemented_slot
                DW      01CAH,  0               ; slot 24 -- eva_unimplemented_slot
                DW      01CAH,  0               ; slot 25 -- eva_unimplemented_slot
                DW      0821H,  0               ; slot 26 -- eva_polygon_span_fill
                DW      01CAH,  0               ; slot 27 -- eva_unimplemented_slot
                DW      14C0H,  0               ; slot 28 -- eva_blit_sprite_master
                DW      01CAH,  0               ; slot 29 -- eva_unimplemented_slot
                DW      01CAH,  0               ; slot 30 -- eva_unimplemented_slot
                DW      01CAH,  0               ; slot 31 -- eva_unimplemented_slot
                DW      01CAH,  0               ; slot 32 -- eva_unimplemented_slot
                DW      01CAH,  0               ; slot 33 -- eva_unimplemented_slot
                DW      01CAH,  0               ; slot 34 -- eva_unimplemented_slot
                DW      0FA0H,  0               ; slot 35 -- eva_blit_sprite
                DW      0E82H,  0               ; slot 36 -- eva_palette_load
                DW      10E6H,  0               ; slot 37 -- eva_palette_set
                DW      0,      0               ; slot 38 -- NULL
                DW      0,      0               ; slot 39 -- NULL
                DW      0,      0               ; slot 40 -- NULL
                DW      0,      0               ; slot 41 -- NULL
                DW      0,      0               ; slot 42 -- NULL
                DW      0,      0               ; slot 43 -- NULL
                DW      0,      0               ; slot 44 -- NULL
                DW      0,      0               ; slot 45 -- NULL
                DW      0,      0               ; slot 46 -- NULL
                DW      0,      0               ; slot 47 -- NULL
                DW      0,      0               ; slot 48 -- NULL
                DW      01CAH,  0               ; slot 49 -- eva_unimplemented_slot
                                                ;            (overlaps callback #0)

; ============================================================================
; g_apEvaHostCallbacksTail -- 18-entry host-service-callback table tail.
; chunk:0x0182..0x01C9 (72 bytes; 18 entries x 4 bytes each)
;
; eva_init copies 38 words = 76 bytes from the caller's callback table to
; CS:0x017E -- that's vtable slot 49 (4 bytes) + this 72-byte tail. On
; disk every entry is initialised to (eva_unimplemented_slot, 0). At
; runtime they hold host-exported service callbacks the chunk dispatches
; into as CALLF [0x0182+N].
; ============================================================================
g_apEvaHostCallbacksTail LABEL DWORD
                DW      01CAH,  0               ; #0
                DW      01CAH,  0               ; #1
                DW      01CAH,  0               ; #2
                DW      01CAH,  0               ; #3
                DW      01CAH,  0               ; #4
                DW      01CAH,  0               ; #5
                DW      01CAH,  0               ; #6
                DW      01CAH,  0               ; #7
                DW      01CAH,  0               ; #8
                DW      01CAH,  0               ; #9
                DW      01CAH,  0               ; #10
                DW      01CAH,  0               ; #11
                DW      01CAH,  0               ; #12
                DW      01CAH,  0               ; #13
                DW      01CAH,  0               ; #14
                DW      01CAH,  0               ; #15
                DW      01CAH,  0               ; #16
                DW      01CAH,  0               ; #17

; ============================================================================
; eva_unimplemented_slot -- 1-byte RETF stub.
; chunk:0x01CA..0x01CA
;
; Reached via any vtable slot that the EVA driver doesn't implement.
; The function body is a single 0xCB byte (RETF) -- the slot accepts
; whatever args the host pushes, ignores them all, and returns
; immediately. Slots dispatching here: 8, 10, 11, 15, 18, 22..25, 27,
; 29..34, 49.
;
; All 18 entries of g_apEvaHostCallbacksTail are initialised to point
; here on disk, so any host-callback the chunk fires before the host
; has overwritten the table also no-ops cleanly. The 1-byte body is
; the minimum: any caller-side stack cleanup is the caller's job
; under __cdecl, so even slots with N stack args route here safely.
; ============================================================================
eva_unimplemented_slot PROC FAR
                RETF                            ; CB
eva_unimplemented_slot ENDP

; ============================================================================
; 0x01CB..0x01D2 -- chunk-local blit-state globals, zero-initialised on disk.
; Read/written via CS: overrides from eva_blit_chunky_to_planar /
; eva_blit_chunky_to_planar_v2 to carry per-row state across the inner loop.
; ============================================================================
g_wEvaBlitWidthBytes      DW    0       ; 0x01CB  bytes per row in dest
g_wEvaBlitRowAdvance      DW    0       ; 0x01CD  ES:DI row-step (negative)
g_wEvaBlitRowsRemaining   DW    0       ; 0x01CF  rows still to copy
g_wEvaBitSpreadLutPtr     DW    0       ; 0x01D1  current dither LUT
                                        ;         (g_abEvaBitSpreadLutEven /
                                        ;          g_abEvaBitSpreadLutOdd)

; ============================================================================
; eva_blit_chunky_to_planar -- chunky-to-planar rect blit (undithered).
; chunk:0x01D3..0x029F
;
; ABI (__cdecl16far):
;   [BP+0x06]  ushort  src_off
;   [BP+0x08]  ushort  src_seg
;   [BP+0x0A]  ushort  dst_x_px
;   [BP+0x0C]  ushort  dst_y_row
;   [BP+0x0E]  ushort  width_px  (treated as / 4 below)
;   [BP+0x10]  ushort  height_rows
;
; Per-row body:
;   - Walks 2 source bytes at a time, splitting each byte into its high and
;     low nibble (4 nibbles total) and writes those nibbles to the EGA
;     framebuffer one per plane.
;   - Plane select cycles through Sequencer Map Mask values 1, 2, 4, 8
;     by writing AL to port 0x3C5 (DX = 0x3C5 after the INC DX at entry).
;   - For each plane: STOSB to ES:[DI], then DEC DI so the same byte
;     position is written 4 times (once per plane).
;   - After 4 nibbles, DI advances by INC (next byte position).
;
; State globals:
;   CS:[0x1CB] = g_wEvaBlitWidthBytes      (width / 4 bytes per row)
;   CS:[0x1CD] = g_wEvaBlitRowAdvance      (negative; -(width/4 - 80))
;   CS:[0x1CF] = g_wEvaBlitRowsRemaining   (rows remaining counter)
;
; Surrounding GC state: Mode=5 entry (set/reset disabled), BitMask=FF, end
; resets BitMask via OUT 3CE, 0F08h pair and Mode register via 0003h.
; ============================================================================
eva_blit_chunky_to_planar PROC FAR
                PUSH    BP                      ; 55
                MOV     BP, SP                  ; 8B EC
                PUSH    SI                      ; 56
                PUSH    DI                      ; 57
                PUSH    DS                      ; 1E
                MOV     DX, 03CEH               ; BA CE 03
                MOV     AX, 0005H               ; B8 05 00   GC[5] Mode = 0
                OUT     DX, AX                  ; EF
                MOV     DX, 03CEH               ; BA CE 03
                MOV     AX, 0FF08H              ; B8 08 FF   GC[8] BitMask = 0xFF
                OUT     DX, AX                  ; EF
                MOV     DX, 03C4H               ; BA C4 03
                MOV     AL, 02H                 ; B0 02      Sequencer idx 2 (Map Mask)
                OUT     DX, AL                  ; EE
                INC     DX                      ; 42         DX = 0x3C5 (data port)
                MOV     DS, cs:[0B2H]           ; 2E 8E 1E B2 00   DS = scratch
                MOV     BX, [BP+0CH]            ; 8B 5E 0C   dst_y_row
                SHL     BX, 1                   ; D1 E3
                MOV     DI, [BX].GfxContext.pRow_offset_lut ; 8B BF F2 06   scanline LUT entry
                MOV     AX, [BP+0AH]            ; 8B 46 0A   dst_x_px
                SHR     AX, 1                   ; D1 E8
                SHR     AX, 1                   ; D1 E8
                SHR     AX, 1                   ; D1 E8      /= 8
                ADD     DI, AX                  ; 03 F8
                MOV     AX, ds:[GfxContext.wGfxBlitDstPage] ; A1 18 00   ES seg from scratch:[0x18]
                MOV     ES, AX                  ; 8E C0
                MOV     AX, [BP+10H]            ; 8B 46 10   height_rows
                MOV     cs:[01CFH], AX          ; 2E A3 CF 01
                MOV     AX, [BP+6]              ; 8B 46 06   src_off
                MOV     SI, AX                  ; 8B F0
                SHR     AX, 1                   ; D1 E8
                SHR     AX, 1                   ; D1 E8
                SHR     AX, 1                   ; D1 E8
                SHR     AX, 1                   ; D1 E8      /= 16
                AND     SI, 000FH               ; 83 E6 0F
                ADD     AX, [BP+8]              ; 03 46 08
                MOV     DS, AX                  ; 8E D8      DS = src_seg + src/16
                MOV     AX, [BP+0EH]            ; 8B 46 0E   width_px
                SHR     AX, 1                   ; D1 E8
                SHR     AX, 1                   ; D1 E8      /= 4
                MOV     cs:[01CBH], AX          ; 2E A3 CB 01
                MOV     BP, AX                  ; 8B E8
                SUB     AX, 0050H               ; 2D 50 00
                NEG     AX                      ; F7 D8
                MOV     cs:[01CDH], AX          ; 2E A3 CD 01
eva_bctp_pixel_pair:
                LODSB                           ; AC
                MOV     BL, AL                  ; 8A D8      BL = src byte 0 (2 px)
                LODSB                           ; AC
                MOV     CL, AL                  ; 8A C8      CL = src byte 1 (2 px)
                MOV     AL, 01H                 ; B0 01
                OUT     DX, AL                  ; EE         Map Mask = plane 0
                MOV     AL, BL                  ; 8A C3
                SHR     AL, 1                   ; D0 E8
                SHR     AL, 1                   ; D0 E8
                SHR     AL, 1                   ; D0 E8
                SHR     AL, 1                   ; D0 E8      AL = (BL >> 4)
                STOSB                           ; AA
                DEC     DI                      ; 4F
                MOV     AL, 02H                 ; B0 02
                OUT     DX, AL                  ; EE         Map Mask = plane 1
                MOV     AL, BL                  ; 8A C3
                AND     AL, 0FH                 ; 24 0F      AL = (BL & 0xF)
                STOSB                           ; AA
                DEC     DI                      ; 4F
                MOV     AL, 04H                 ; B0 04
                OUT     DX, AL                  ; EE         Map Mask = plane 2
                MOV     AL, CL                  ; 8A C1
                SHR     AL, 1                   ; D0 E8
                SHR     AL, 1                   ; D0 E8
                SHR     AL, 1                   ; D0 E8
                SHR     AL, 1                   ; D0 E8      AL = (CL >> 4)
                STOSB                           ; AA
                DEC     DI                      ; 4F
                MOV     AL, 08H                 ; B0 08
                OUT     DX, AL                  ; EE         Map Mask = plane 3
                MOV     AL, CL                  ; 8A C1
                AND     AL, 0FH                 ; 24 0F      AL = (CL & 0xF)
                STOSB                           ; AA
                DEC     BP                      ; 4D
                JLE     SHORT eva_bctp_next_row ; 7E 02
                JMP     SHORT eva_bctp_pixel_pair ; EB C6
eva_bctp_next_row:
                MOV     AX, cs:[01CFH]          ; 2E A1 CF 01
                DEC     AX                      ; 48
                JLE     SHORT eva_bctp_exit     ; 7E 12
                MOV     cs:[01CFH], AX          ; 2E A3 CF 01
                MOV     AX, cs:[01CBH]          ; 2E A1 CB 01
                MOV     BP, AX                  ; 8B E8
                MOV     AX, cs:[01CDH]          ; 2E A1 CD 01
                ADD     DI, AX                  ; 03 F8
                JMP     SHORT eva_bctp_pixel_pair ; EB AD
eva_bctp_exit:
                MOV     AL, 0FH                 ; B0 0F
                OUT     DX, AL                  ; EE         Map Mask back to 0x0F
                MOV     DX, 03CEH               ; BA CE 03
                MOV     AX, 0003H               ; B8 03 00   GC[3] Data Rotate = 0
                OUT     DX, AX                  ; EF
                POP     DS                      ; 1F
                POP     DI                      ; 5F
                POP     SI                      ; 5E
                POP     BP                      ; 5D
                RETF                            ; CB
eva_blit_chunky_to_planar ENDP

; ============================================================================
; eva_blit_chunky_to_planar_v2 -- the dithered chunky-to-planar core.
; chunk:0x02A0..0x04AE
;
; This is the *EVA* core -- it takes a chunky (1 byte per pixel) source
; surface authored against the VGA 256-colour palette and renders it into
; EGA 4-plane output using a 2x2 spatial dither against a 16-of-64 EGA
; palette. The dither tables at 0x4E1 / 0x5E1 select which of the two
; nearest EGA colours each source pixel should be quantised to per row.
;
; ABI matches eva_blit_chunky_to_planar (FAR, 6 word args via stack).
;
; The body has two phases. Phase A is a leading-edge fixup identical to
; eva_blit_chunky_to_planar's main loop (Map Mask write per plane,
; AND/SHR of source bytes, STOSB ES:[DI]) but with a `MOV AH,ES:[DI]`
; read-back so existing planar bits get preserved by `STOSB` (since EGA
; writes are latch-merged in mode 0). Phase B is the dithered core that
; runs row by row: it XLATs each source byte through CS:[g_wEvaBitSpreadLutPtr]
; (alternating between Even/Odd LUT addresses 0x4E1 / 0x5E1 per row) and
; performs 8 SHL+RCL cycles per plane to spread 8 nibbles into a 4-byte
; output word. The 4 result bytes are STOSB'd into the framebuffer with
; Map Mask cycling 8 -> 4 -> 2 -> 1 (note: opposite order from phase A).
; The XLAT uses the CS-segment-override form (`XLAT BYTE PTR CS:[BX]`,
; bytes `2E D7`) so the lookup hits the chunk-local LUT without
; disturbing DS.
; ============================================================================
eva_blit_chunky_to_planar_v2 PROC FAR
                PUSH    BP                      ; 55
                MOV     BP, SP                  ; 8B EC
                PUSH    SI                      ; 56
                PUSH    DI                      ; 57
                PUSH    DS                      ; 1E
                MOV     DX, 03CEH               ; BA CE 03
                MOV     AX, 1003H               ; B8 03 10   GC[3] Data Rotate = 0x10
                OUT     DX, AX                  ; EF
                MOV     AX, 0FF08H              ; B8 08 FF   GC[8] BitMask = 0xFF
                OUT     DX, AX                  ; EF
                MOV     DX, 03C4H               ; BA C4 03
                MOV     AL, 02H                 ; B0 02
                OUT     DX, AL                  ; EE         Sequencer idx 2 (Map Mask)
                INC     DX                      ; 42         DX = 0x3C5
                MOV     DS, cs:[0B2H]           ; 2E 8E 1E B2 00
                MOV     BX, [BP+0CH]            ; 8B 5E 0C   dst_y_row
                SHL     BX, 1                   ; D1 E3
                MOV     DI, [BX].GfxContext.pRow_offset_lut ; 8B BF F2 06
                MOV     AX, [BP+0AH]            ; 8B 46 0A   dst_x_px
                SHR     AX, 1                   ; D1 E8
                SHR     AX, 1                   ; D1 E8
                SHR     AX, 1                   ; D1 E8
                ADD     DI, AX                  ; 03 F8
                MOV     AX, ds:[GfxContext.wGfxBlitDstPage] ; A1 18 00
                MOV     ES, AX                  ; 8E C0
                MOV     AX, [BP+10H]            ; 8B 46 10
                MOV     cs:[01CFH], AX          ; 2E A3 CF 01
                MOV     AX, [BP+6]              ; 8B 46 06
                MOV     SI, AX                  ; 8B F0
                SHR     AX, 1                   ; D1 E8
                SHR     AX, 1                   ; D1 E8
                SHR     AX, 1                   ; D1 E8
                SHR     AX, 1                   ; D1 E8
                AND     SI, 000FH               ; 83 E6 0F
                ADD     AX, [BP+8]              ; 03 46 08
                MOV     DS, AX                  ; 8E D8
                MOV     AX, [BP+0EH]            ; 8B 46 0E
                SHR     AX, 1                   ; D1 E8
                SHR     AX, 1                   ; D1 E8
                MOV     cs:[01CBH], AX          ; 2E A3 CB 01
                MOV     BP, AX                  ; 8B E8
                SUB     AX, 0050H               ; 2D 50 00
                NEG     AX                      ; F7 D8
                MOV     cs:[01CDH], AX          ; 2E A3 CD 01
                PUSH    DI                      ; 57
                PUSH    BP                      ; 55
                PUSH    WORD PTR cs:[01CFH]     ; 2E FF 36 CF 01
                ; ---- Phase A: leading-edge fixup (preserves existing planes
                ;      under the high nibbles via MOV AH, ES:[DI] read-back).
eva_bctp2_phaseA:
                LODSB                           ; AC
                MOV     BL, AL                  ; 8A D8
                LODSB                           ; AC
                MOV     CL, AL                  ; 8A C8
                MOV     AL, 01H                 ; B0 01
                OUT     DX, AL                  ; EE         Map Mask = plane 0
                MOV     AL, BL                  ; 8A C3
                AND     AL, 0F0H                ; 24 F0
                MOV     AH, es:[DI]             ; 26 8A 25
                STOSB                           ; AA
                DEC     DI                      ; 4F
                MOV     AL, 02H                 ; B0 02
                OUT     DX, AL                  ; EE         Map Mask = plane 1
                MOV     AL, BL                  ; 8A C3
                SHL     AL, 1                   ; D0 E0
                SHL     AL, 1                   ; D0 E0
                SHL     AL, 1                   ; D0 E0
                SHL     AL, 1                   ; D0 E0
                MOV     AH, es:[DI]             ; 26 8A 25
                STOSB                           ; AA
                DEC     DI                      ; 4F
                MOV     AL, 04H                 ; B0 04
                OUT     DX, AL                  ; EE         Map Mask = plane 2
                MOV     AL, CL                  ; 8A C1
                AND     AL, 0F0H                ; 24 F0
                MOV     AH, es:[DI]             ; 26 8A 25
                STOSB                           ; AA
                DEC     DI                      ; 4F
                MOV     AL, 08H                 ; B0 08
                OUT     DX, AL                  ; EE         Map Mask = plane 3
                MOV     AL, CL                  ; 8A C1
                SHL     AL, 1                   ; D0 E0
                SHL     AL, 1                   ; D0 E0
                SHL     AL, 1                   ; D0 E0
                SHL     AL, 1                   ; D0 E0
                MOV     AH, es:[DI]             ; 26 8A 25
                STOSB                           ; AA
                DEC     BP                      ; 4D
                JLE     SHORT eva_bctp2_phaseA_next ; 7E 02
                JMP     SHORT eva_bctp2_phaseA  ; EB BA
eva_bctp2_phaseA_next:
                MOV     AX, cs:[01CFH]          ; 2E A1 CF 01
                DEC     AX                      ; 48
                JLE     SHORT eva_bctp2_phaseB_init ; 7E 12
                MOV     cs:[01CFH], AX          ; 2E A3 CF 01
                MOV     AX, cs:[01CBH]          ; 2E A1 CB 01
                MOV     BP, AX                  ; 8B E8
                MOV     AX, cs:[01CDH]          ; 2E A1 CD 01
                ADD     DI, AX                  ; 03 F8
                JMP     SHORT eva_bctp2_phaseA  ; EB A1
eva_bctp2_phaseB_init:
                POP     WORD PTR cs:[01CFH]     ; 2E 8F 06 CF 01
                POP     BP                      ; 5D
                POP     DI                      ; 5F
                MOV     DX, 03CEH               ; BA CE 03
                MOV     AL, 04H                 ; B0 04
                OUT     DX, AL                  ; EE
                MOV     DX, 03CEH               ; BA CE 03
                MOV     AX, 0003H               ; B8 03 00   GC[3] Data Rotate = 0
                OUT     DX, AX                  ; EF
                MOV     AL, 04H                 ; B0 04
                OUT     DX, AL                  ; EE
                PUSH    DS                      ; 1E
                MOV     AX, CS                  ; 8C C8
                MOV     DS, AX                  ; 8E D8
                MOV     AX, OFFSET g_abEvaBitSpreadLutEven ; B8 E1 04
                MOV     cs:[01D1H], AX          ; 2E A3 D1 01
                ; ---- Phase B: dithered core. BX = current LUT base
                ;      (g_abEvaBitSpreadLutEven / g_abEvaBitSpreadLutOdd).
eva_bctp2_phaseB:
                MOV     BX, cs:[01D1H]          ; 2E 8B 1E D1 01
                MOV     DX, 03CFH               ; BA CF 03
                XOR     AL, AL                  ; 32 C0
                OUT     DX, AL                  ; EE
                MOV     AL, es:[DI]             ; 26 8A 05
                XLAT    BYTE PTR CS:[BX]        ; 2E D7
                MOV     CL, AL                  ; 8A C8
                MOV     AL, 01H                 ; B0 01
                OUT     DX, AL                  ; EE
                MOV     AL, es:[DI]             ; 26 8A 05
                XLAT    BYTE PTR CS:[BX]        ; 2E D7
                MOV     CH, AL                  ; 8A E8
                MOV     AL, 02H                 ; B0 02
                OUT     DX, AL                  ; EE
                MOV     AL, es:[DI]             ; 26 8A 05
                XLAT    BYTE PTR CS:[BX]        ; 2E D7
                MOV     AH, AL                  ; 8A E0
                MOV     AL, 03H                 ; B0 03
                OUT     DX, AL                  ; EE
                MOV     AL, es:[DI]             ; 26 8A 05
                XLAT    BYTE PTR CS:[BX]        ; 2E D7
                MOV     BL, AH                  ; 8A DC
                MOV     BH, AL                  ; 8A F8
                ; 32-cycle bit-spread macro: 8 RCLs per source byte (CL,CH,BL,BH),
                ; producing 4 output bytes (AL=plane0, AH=plane1, DL=plane2, DH=plane3).
                SHL     CL, 1                   ; D0 E1
                RCL     AL, 1                   ; D0 D0
                SHL     CL, 1                   ; D0 E1
                RCL     AH, 1                   ; D0 D4
                SHL     CL, 1                   ; D0 E1
                RCL     DL, 1                   ; D0 D2
                SHL     CL, 1                   ; D0 E1
                RCL     DH, 1                   ; D0 D6
                SHL     CL, 1                   ; D0 E1
                RCL     AL, 1                   ; D0 D0
                SHL     CL, 1                   ; D0 E1
                RCL     AH, 1                   ; D0 D4
                SHL     CL, 1                   ; D0 E1
                RCL     DL, 1                   ; D0 D2
                SHL     CL, 1                   ; D0 E1
                RCL     DH, 1                   ; D0 D6
                SHL     CH, 1                   ; D0 E5
                RCL     AL, 1                   ; D0 D0
                SHL     CH, 1                   ; D0 E5
                RCL     AH, 1                   ; D0 D4
                SHL     CH, 1                   ; D0 E5
                RCL     DL, 1                   ; D0 D2
                SHL     CH, 1                   ; D0 E5
                RCL     DH, 1                   ; D0 D6
                SHL     CH, 1                   ; D0 E5
                RCL     AL, 1                   ; D0 D0
                SHL     CH, 1                   ; D0 E5
                RCL     AH, 1                   ; D0 D4
                SHL     CH, 1                   ; D0 E5
                RCL     DL, 1                   ; D0 D2
                SHL     CH, 1                   ; D0 E5
                RCL     DH, 1                   ; D0 D6
                SHL     BL, 1                   ; D0 E3
                RCL     AL, 1                   ; D0 D0
                SHL     BL, 1                   ; D0 E3
                RCL     AH, 1                   ; D0 D4
                SHL     BL, 1                   ; D0 E3
                RCL     DL, 1                   ; D0 D2
                SHL     BL, 1                   ; D0 E3
                RCL     DH, 1                   ; D0 D6
                SHL     BL, 1                   ; D0 E3
                RCL     AL, 1                   ; D0 D0
                SHL     BL, 1                   ; D0 E3
                RCL     AH, 1                   ; D0 D4
                SHL     BL, 1                   ; D0 E3
                RCL     DL, 1                   ; D0 D2
                SHL     BL, 1                   ; D0 E3
                RCL     DH, 1                   ; D0 D6
                SHL     BH, 1                   ; D0 E7
                RCL     AL, 1                   ; D0 D0
                SHL     BH, 1                   ; D0 E7
                RCL     AH, 1                   ; D0 D4
                SHL     BH, 1                   ; D0 E7
                RCL     DL, 1                   ; D0 D2
                SHL     BH, 1                   ; D0 E7
                RCL     DH, 1                   ; D0 D6
                SHL     BH, 1                   ; D0 E7
                RCL     AL, 1                   ; D0 D0
                SHL     BH, 1                   ; D0 E7
                RCL     AH, 1                   ; D0 D4
                SHL     BH, 1                   ; D0 E7
                RCL     DL, 1                   ; D0 D2
                SHL     BH, 1                   ; D0 E7
                RCL     DH, 1                   ; D0 D6
                MOV     CX, AX                  ; 8B C8
                MOV     BX, DX                  ; 8B DA
                MOV     DX, 03C5H               ; BA C5 03
                MOV     AL, 08H                 ; B0 08
                OUT     DX, AL                  ; EE
                MOV     es:[DI], CL             ; 26 88 0D
                MOV     AL, 04H                 ; B0 04
                OUT     DX, AL                  ; EE
                MOV     es:[DI], CH             ; 26 88 2D
                MOV     AL, 02H                 ; B0 02
                OUT     DX, AL                  ; EE
                MOV     es:[DI], BL             ; 26 88 1D
                MOV     AL, 01H                 ; B0 01
                OUT     DX, AL                  ; EE
                MOV     es:[DI], BH             ; 26 88 3D
                INC     DI                      ; 47
                DEC     BP                      ; 4D
                JLE     SHORT eva_bctp2_phaseB_next ; 7E 03
                JMP     eva_bctp2_phaseB        ; E9 28 FF
eva_bctp2_phaseB_next:
                MOV     AX, cs:[01CFH]          ; 2E A1 CF 01
                DEC     AX                      ; 48
                JLE     SHORT eva_bctp2_exit    ; 7E 22
                MOV     cs:[01CFH], AX          ; 2E A3 CF 01
                MOV     BX, OFFSET g_abEvaBitSpreadLutEven ; BB E1 04
                AND     AX, 0001H               ; 25 01 00
                XCHG    AL, AH                  ; 86 C4     bit0 -> high byte (=0x100)
                ADD     BX, AX                  ; 03 D8     BX = E1h or 1E1h offset
                MOV     cs:[01D1H], BX          ; 2E 89 1E D1 01
                MOV     AX, cs:[01CBH]          ; 2E A1 CB 01
                MOV     BP, AX                  ; 8B E8
                MOV     AX, cs:[01CDH]          ; 2E A1 CD 01
                ADD     DI, AX                  ; 03 F8
                JMP     eva_bctp2_phaseB        ; E9 FF FE
eva_bctp2_exit:
                POP     DS                      ; 1F
                MOV     AL, 0FH                 ; B0 0F
                OUT     DX, AL                  ; EE
                MOV     DX, 03CEH               ; BA CE 03
                MOV     AX, 0003H               ; B8 03 00
                OUT     DX, AX                  ; EF
                MOV     DX, 03CEH               ; BA CE 03
                MOV     AX, 0005H               ; B8 05 00
                OUT     DX, AX                  ; EF
                MOV     DX, 03C5H               ; BA C5 03
                MOV     AL, 0FH                 ; B0 0F
                OUT     DX, AL                  ; EE
                POP     DS                      ; 1F
                POP     DI                      ; 5F
                POP     SI                      ; 5E
                POP     BP                      ; 5D
                RETF                            ; CB
eva_blit_chunky_to_planar_v2 ENDP

; ============================================================================
; 0x04AF..0x04DE -- g_abEvaDefaultPaletteRgb: 16 entries x 3 RGB bytes.
; Default EGA palette: VGA-style RGB triples (0..63 per component) that
; eva_palette_set uses as the fallback when the host hasn't supplied one.
; ============================================================================
g_abEvaDefaultPaletteRgb LABEL BYTE
                DB      000H, 000H, 000H        ; idx 0  -- black
                DB      000H, 000H, 02AH        ; idx 1  -- blue
                DB      000H, 02AH, 000H        ; idx 2  -- green
                DB      000H, 02AH, 02AH        ; idx 3  -- cyan
                DB      02AH, 000H, 000H        ; idx 4  -- red
                DB      02AH, 000H, 02AH        ; idx 5  -- magenta
                DB      02AH, 015H, 000H        ; idx 6  -- brown
                DB      02AH, 02AH, 02AH        ; idx 7  -- light grey
                DB      015H, 015H, 015H        ; idx 8  -- dark grey
                DB      015H, 015H, 03FH        ; idx 9  -- bright blue
                DB      015H, 03FH, 015H        ; idx 10 -- bright green
                DB      015H, 03FH, 03FH        ; idx 11 -- bright cyan
                DB      03FH, 015H, 015H        ; idx 12 -- bright red
                DB      03FH, 015H, 03FH        ; idx 13 -- bright magenta
                DB      03FH, 03FH, 015H        ; idx 14 -- yellow
                DB      03FH, 03FH, 03FH        ; idx 15 -- white

; ============================================================================
; 0x04DF..0x04E0 -- g_wEvaPaletteLutPad: 2 bytes of zero padding.
; ============================================================================
g_wEvaPaletteLutPad      DW    0       ; 0x04DF

; ============================================================================
; g_abEvaBitSpreadLutEven / g_abEvaBitSpreadLutOdd -- dither bit-spread LUTs.
; chunk:0x04E1..0x06E0 (2 x 256 bytes)
;
; Populated at runtime by eva_palette_build_remap_lut. On disk both tables
; are zero-initialised; eva_palette_set fills them as part of every palette
; change. The Even table is indexed for even rows, Odd for odd rows; the
; XLAT in eva_blit_chunky_to_planar_v2 reads CS:[BX+AL] where BX is
; g_wEvaBitSpreadLutPtr (alternates between these two table bases).
; ============================================================================
g_abEvaBitSpreadLutEven LABEL BYTE
                DB      256 DUP(0)              ; 0x04E1..0x05E0
g_abEvaBitSpreadLutOdd  LABEL BYTE
                DB      256 DUP(0)              ; 0x05E1..0x06E0

; ============================================================================
; 0x06E1..0x06E4 -- palette-search scratch globals (zero on disk).
; ============================================================================
g_wEvaPaletteMatchIndex  DW    0       ; 0x06E1
g_wEvaPaletteMatchDist   DW    0       ; 0x06E3

; ============================================================================
; eva_palette_find_nearest_rgb -- find closest EGA palette entry to an RGB.
; chunk:0x06E5..0x0775
;
; NEAR helper called from eva_palette_build_remap_lut. Iterates the 16
; entries of g_abEvaDefaultPaletteRgb (taking each as base + 3-offset
; midpoint), computes a Manhattan distance to the input (R,G,B) triple via
; CBW / XOR AL,AH / SUB AL,AH abs-value tricks, and tracks the best match
; in g_wEvaPaletteMatchIndex / g_wEvaPaletteMatchDist.
;
; ABI (NEAR, stack-args):
;   [BP+4]  SS:DI = input RGB triple address (3 bytes, scaled)
; Returns AL = packed (best_idx_lo | (best_idx_lo << 4)). AH side held the
; high-nibble copy; OR AL,AH packs both for the dither LUT consumer.
; ============================================================================
eva_palette_find_nearest_rgb PROC NEAR
                PUSH    BP                      ; 55
                MOV     BP, SP                  ; 8B EC
                PUSH    DI                      ; 57
                PUSH    SI                      ; 56
                PUSH    BX                      ; 53
                PUSH    DX                      ; 52
                MOV     WORD PTR cs:[06E3H], 0301H ; 2E C7 06 E3 06 01 03
                                                ;   initial best-dist low byte = 0x01,
                                                ;   high byte (used as outer-loop count) = 0x03
                SUB     CX, CX                  ; 2B C9   CX = 0
                MOV     DI, [BP+4]              ; 8B 7E 04   SS:DI = input triple
                XOR     BX, BX                  ; 33 DB
                XOR     DX, DX                  ; 33 D2
                MOV     SI, OFFSET g_abEvaDefaultPaletteRgb ; BE AF 04
eva_pfnr_outer_loop:
                MOV     BP, OFFSET g_abEvaDefaultPaletteRgb ; BD AF 04
eva_pfnr_inner:
                MOV     AL, ss:[DI]             ; 36 8A 05
                SUB     AL, cs:[SI]             ; 2E 2A 04
                SUB     AL, cs:[BP+0]           ; 2E 2A 46 00
                CBW                             ; 98
                XOR     AL, AH                  ; 32 C4   abs(x) trick (with SUB next)
                SUB     AL, AH                  ; 2A C4
                MOV     BL, AL                  ; 8A D8   BL = |dR|
                MOV     AL, ss:[DI+1]           ; 36 8A 45 01
                SUB     AL, cs:[SI+1]           ; 2E 2A 44 01
                SUB     AL, cs:[BP+1]           ; 2E 2A 46 01
                CBW                             ; 98
                XOR     AL, AH                  ; 32 C4
                SUB     AL, AH                  ; 2A C4
                MOV     DL, AL                  ; 8A D0   DL = |dG|
                MOV     AL, ss:[DI+2]           ; 36 8A 45 02
                SUB     AL, cs:[SI+2]           ; 2E 2A 44 02
                SUB     AL, cs:[BP+2]           ; 2E 2A 46 02
                CBW                             ; 98
                XOR     AL, AH                  ; 32 C4
                SUB     AL, AH                  ; 2A C4
                XOR     AH, AH                  ; 32 E4
                ADD     AX, BX                  ; 03 C3   AX = |dB| + |dR|
                ADD     AX, DX                  ; 03 C2   AX = + |dG|
                ADD     BP, 3                   ; 83 C5 03
                CMP     AX, cs:[06E3H]          ; 2E 3B 06 E3 06
                JGE     SHORT eva_pfnr_skip     ; 7D 09
                MOV     cs:[06E3H], AX          ; 2E A3 E3 06
                MOV     cs:[06E1H], CX          ; 2E 89 0E E1 06
eva_pfnr_skip:
                INC     CL                      ; FE C1
                CMP     CL, CH                  ; 3A CD
                JLE     SHORT eva_pfnr_inner    ; 7E AC
                ADD     SI, 3                   ; 83 C6 03
                INC     CH                      ; FE C5
                XOR     CL, CL                  ; 32 C9
                CMP     CH, 10H                 ; 80 FD 10
                JL      SHORT eva_pfnr_outer_loop ; 7C 9D
                MOV     AX, cs:[06E1H]          ; 2E A1 E1 06
                SHL     AH, 1                   ; D0 E4
                SHL     AH, 1                   ; D0 E4
                SHL     AH, 1                   ; D0 E4
                SHL     AH, 1                   ; D0 E4
                OR      AL, AH                  ; 0A C4
                POP     DX                      ; 5A
                POP     BX                      ; 5B
                POP     SI                      ; 5E
                POP     DI                      ; 5F
                POP     BP                      ; 5D
                RET                             ; C3
eva_palette_find_nearest_rgb ENDP

; ============================================================================
; eva_palette_build_remap_lut -- build the VGA->EGA 256-entry remap LUT.
; chunk:0x0776..0x07CA
;
; NEAR helper (called from eva_palette_set; tail RETF).
;
; Walks a 256-entry source RGB table (host-provided, 768 bytes) and for
; each entry calls eva_palette_find_nearest_rgb to populate the
; g_abEvaBitSpreadLutEven / g_abEvaBitSpreadLutOdd LUTs in-place:
;   LUTEven[i] = nearest_idx
;   LUTOdd[i]  = ROL nearest_idx, 4  (nibble-swapped for dither phase)
;
; ABI (FAR per RETF tail):
;   [BP+6]  src_palette_off    (256 x 3-byte RGB, scaled by 2 below)
;   [BP+8]  unused (offset into output LUT pair)
;   [BP+0Ah] count_to_build
; Output written at CS:[g_abEvaBitSpreadLutEven + offset_arg].
; ============================================================================
eva_palette_build_remap_lut PROC FAR
                PUSH    BP                      ; 55
                MOV     BP, SP                  ; 8B EC
                SUB     SP, 4                   ; 83 EC 04   stack slot for triple
                PUSH    SI                      ; 56
                PUSH    DI                      ; 57
                MOV     SI, [BP+6]              ; 8B 76 06   src_palette_off
                MOV     BX, [BP+8]              ; 8B 5E 08   lut_offset
                MOV     CX, [BP+0AH]            ; 8B 4E 0A   count
                MOV     AX, SS                  ; 8C D0
                MOV     ES, AX                  ; 8E C0      ES = SS (host palette is on stack)
                MOV     DI, OFFSET g_abEvaBitSpreadLutEven ; BF E1 04
                ADD     DI, BX                  ; 03 FB
eva_pbrl_loop_iter:
                PUSH    CX                      ; 51
                MOV     BX, OFFSET g_abEvaDefaultPaletteRgb ; BB AF 04
                LODSB                           ; AC
                SHL     AL, 1                   ; D0 E0
                MOV     [BP-4], AL              ; 88 46 FC
                LODSB                           ; AC
                SHL     AL, 1                   ; D0 E0
                MOV     [BP-3], AL              ; 88 46 FD
                LODSB                           ; AC
                SHL     AL, 1                   ; D0 E0
                MOV     [BP-2], AL              ; 88 46 FE
                LEA     AX, [BP-4]              ; 8D 46 FC
                PUSH    AX                      ; 50
                CALL    NEAR PTR eva_palette_find_nearest_rgb ; E8 38 FF
                ADD     SP, 2                   ; 83 C4 02
                MOV     cs:[DI], AL             ; 2E 88 05
                ROL     AL, 1                   ; D0 C0
                ROL     AL, 1                   ; D0 C0
                ROL     AL, 1                   ; D0 C0
                ROL     AL, 1                   ; D0 C0
                MOV     cs:[DI+0100H], AL       ; 2E 88 85 00 01
                INC     DI                      ; 47
                POP     CX                      ; 59
                LOOP    SHORT eva_pbrl_loop_iter ; E2 CC
                                                ; ^ CX is the loop counter; pushed before
                                                ;   the CALL and popped after because the
                                                ;   callee doesn't preserve CX.
                POP     DI                      ; 5F
                POP     SI                      ; 5E
                ADD     SP, 4                   ; 83 C4 04
                POP     BP                      ; 5D
                RETF                            ; CB
eva_palette_build_remap_lut ENDP

; ============================================================================
; eva_present -- install a new 256-entry source palette (vtable slot 19).
; chunk:0x07CB..0x080E
;
; Despite the name "present", this slot is
; structurally a palette upload: the caller passes a 768-byte RGB palette
; in DS:SI ([BP+8]:[BP+6]) and the function:
;
;   1. Calls eva_palette_build_remap_lut(palette, offset=0, count=256)
;      to recompute both 256-byte bit-spread LUTs (Even/Odd at 0x4E1 /
;      0x5E1) from the new source palette. This is the slow O(256*16)
;      nearest-RGB search; it dithers the new VGA-style 256-colour
;      palette down to the 16-of-64 EGA hardware palette.
;
;   2. Copies the raw 768-byte palette (= 0x180 words) into the shadow
;      whose far-pointer lives at scratch:[0x1A0]:scratch:[0x19E]
;      (seg:off). Two `REP MOVSW` passes of 0x180 words each: between
;      them `SUB SI, AX; SUB SI, AX` rewinds SI by 0x300 bytes (= the
;      0x180 words just consumed) so the second pass re-reads the
;      same source. DI is *not* rewound, so the second pass lands at
;      the next 768 bytes of the destination -- i.e. the destination
;      holds two back-to-back copies of the source palette. The reason
;      for the duplication is unclear.
;
; If [BP+8] (palette segment) is NULL the function short-circuits to
; the epilogue and does nothing.
;
; ABI (__cdecl16far):
;   [BP+6]  ushort  palette_off   (256 RGB triples, 768 bytes)
;   [BP+8]  ushort  palette_seg   (NULL skips the upload)
;
; Side effects:
;   cs:[0x04E1..0x06E0]  bit-spread LUTs (Even / Odd) rebuilt
;   palette shadow (far-pointer at scratch:[0x1A0]:[0x19E]) updated
; ============================================================================
eva_present     PROC    FAR
                PUSH    BP                      ; 55
                MOV     BP, SP                  ; 8B EC
                PUSH    DI                      ; 57
                PUSH    SI                      ; 56
                PUSH    DS                      ; 1E
                MOV     DS, cs:[0B2H]           ; 2E 8E 1E B2 00
                MOV     DI, ds:[GfxContext.pPaletteScratchBuf]   ; 8B 3E 9E 01  off @ +0x19E
                MOV     ES, ds:[GfxContext.pPaletteScratchBuf+2] ; 8E 06 A0 01  seg @ +0x1A0
                MOV     SI, [BP+6]              ; 8B 76 06
                MOV     AX, [BP+8]              ; 8B 46 08
                MOV     DS, AX                  ; 8E D8
                OR      AX, AX                  ; 0B C0
                JZ      SHORT eva_present_exit  ; 74 20
                PUSH    ES                      ; 06
                MOV     AX, 0100H               ; B8 00 01   count = 256
                PUSH    AX                      ; 50
                XOR     AX, AX                  ; 33 C0
                PUSH    AX                      ; 50         offset = 0
                PUSH    SI                      ; 56         src_off (palette base)
                PUSH    CS                      ; 0E
                CALL    NEAR PTR eva_palette_build_remap_lut ; E8 7F FF
                ADD     SP, 6                   ; 83 C4 06
                POP     ES                      ; 07
                MOV     CX, 0180H               ; B9 80 01   384 words = 768 bytes
                MOV     AX, CX                  ; 8B C1
                REP     MOVSW                   ; F3 A5
                SUB     SI, AX                  ; 2B F0
                SUB     SI, AX                  ; 2B F0      rewind 2*0x180 bytes
                MOV     CX, AX                  ; 8B C8
                REP     MOVSW                   ; F3 A5
eva_present_exit:
                POP     DS                      ; 1F
                POP     SI                      ; 5E
                POP     DI                      ; 5F
                POP     BP                      ; 5D
                RETF                            ; CB
eva_present     ENDP

; ============================================================================
; 0x080F..0x0820 -- polygon scratch globals.
; ============================================================================
g_abEvaPolygonLeftMaskLut LABEL BYTE
                DB      0FFH, 03FH, 00FH, 003H  ; 0x080F (left-edge keep masks)
g_abEvaPolygonRightMaskLut LABEL BYTE
                DB      000H, 0C0H, 0F0H, 0FCH  ; 0x0813 (right-edge keep masks)
g_wEvaPolygonScratch0       DW    0     ; 0x0817
g_wEvaPolygonScanlineCount  DW    0     ; 0x0819
g_wEvaPolygonFillColor      DW    0     ; 0x081B
g_wEvaPolygonScratch1       DW    0     ; 0x081D
g_wEvaPolygonRowBaseOffset  DW    0     ; 0x081F

; ============================================================================
; eva_polygon_span_fill -- polygon scanline fill (vtable slot 26).
; chunk:0x0821..0x0B3B
;
; Reads a span-list at ES:SI (host-provided) and renders one scanline per
; (x0,x1) pair. The body has three near-identical "fill spans for one
; column phase" blocks (entries 0x871, 0x0968, 0x0A4D) because the bit-
; spread phase of the EGA Bit Mask register changes per dither column.
;
; GC state on entry:
;   OUT 0x3CE, 0x0205 -- GC[5] Mode = 0x02 (write mode 2: CPU data = mask)
;   OUT 0x3CE, 0xFF08 -- GC[8] BitMask = 0xFF (start with all bits enabled)
;
; ABI: ES:SI = scanline list, DS = chunk segment on entry. Reads
;      g_wEvaPolygonScanlineCount, g_wEvaPolygonFillColor and the per-row
;      base-offset table; writes via EGA Map Mask and BitMask gymnastics.
;
; Notes on XLAT: the body uses `XLAT BYTE PTR CS:[BX]` (bytes `2E D7`),
; the CS-segment-override form, because the bit-spread LUT lives in
; the code segment alongside the function.
; ============================================================================
eva_polygon_span_fill PROC FAR
                MOV     AX, 0205H               ; B8 05 02   GC[5] Mode = 2 (write mode 2)
                MOV     DX, 03CEH               ; BA CE 03
                OUT     DX, AX                  ; EF
                MOV     AX, 0FF08H              ; B8 08 FF
                OUT     DX, AX                  ; EF
                PUSH    DS                      ; 1E
                MOV     CX, ES                  ; 8C C1
                MOV     DS, CX                  ; 8E D9
                LODSW                           ; AD         scanline count
                SHL     AX, 1                   ; D1 E0
                MOV     BP, AX                  ; 8B E8
                LODSW                           ; AD         and color
                MOV     DS, cs:[0B2H]           ; 2E 8E 1E B2 00
                MOV     cs:[0819H], AX          ; 2E A3 19 08
                MOV     AX, ds:[GfxContext.wGfxBlitDstPage] ; A1 18 00
                MOV     ES, AX                  ; 8E C0
                MOV     AX, GfxContext.pRow_offset_lut ; B8 F2 06
                ADD     AX, cs:[0B4H]           ; 2E 03 06 B4 00
                MOV     cs:[081FH], AX          ; 2E A3 1F 08
                MOV     AL, ds:[GfxContext.bGfx_fill_color] ; A0 0D 00   span-draw colour
                MOV     DS, CX                  ; 8E D9
                MOV     BX, OFFSET g_abEvaBitSpreadLutEven ; BB E1 04
                XLAT    BYTE PTR CS:[BX]        ; 2E D7
                MOV     AH, AL                  ; 8A E0
                SHR     AL, 1                   ; D0 E8
                SHR     AL, 1                   ; D0 E8
                SHR     AL, 1                   ; D0 E8
                SHR     AL, 1                   ; D0 E8
                AND     AH, 0FH                 ; 80 E4 0F
                MOV     cs:[081BH], AX          ; 2E A3 1B 08
                XCHG    AL, AH                  ; 86 C4
                JMP     eva_psf_phase1          ; E9 E8 00
                ; ---- Phase 0 (column-phase 0/3) -------------------------
eva_psf_phase0_loop:
                LODSW                           ; AD         x0
                MOV     BX, AX                  ; 8B D8
                LODSW                           ; AD         x1
                SUB     AX, BX                  ; 2B C3
                JGE     SHORT eva_psf_p0_ok     ; 7D 03
                JMP     eva_psf_phase0_next     ; E9 CD 00
eva_psf_p0_ok:
                INC     AX                      ; 40
                MOV     CX, AX                  ; 8B C8
                MOV     DI, cs:[081FH]          ; 2E 8B 3E 1F 08
                MOV     DI, [BP+DI]             ; 8B 3B
                MOV     AX, cs:[081BH]          ; 2E A1 1B 08
                MOV     cs:[0817H], AX          ; 2E A3 17 08
                MOV     AX, BX                  ; 8B C3
                SHR     AX, 1                   ; D1 E8
                SHR     AX, 1                   ; D1 E8
                ADD     DI, AX                  ; 03 F8
                AND     BX, 0003H               ; 83 E3 03
                MOV     DX, BX                  ; 8B D3
                ADD     DX, CX                  ; 03 D1
                CMP     DX, 0004H               ; 83 FA 04
                JGE     SHORT eva_psf_p0_wide   ; 7D 30
                ; narrow span (< 4 px)
                MOV     CX, cs:[0817H]          ; 2E 8B 0E 17 08
                MOV     AH, cs:[BX+080FH]       ; 2E 8A A7 0F 08
                MOV     BL, DL                  ; 8A DA
                AND     AH, cs:[BX+0813H]       ; 2E 22 A7 13 08
                MOV     BL, AH                  ; 8A DC
                AND     AH, 0AAH                ; 80 E4 AA
                MOV     AL, 08H                 ; B0 08
                MOV     DX, 03CEH               ; BA CE 03
                OUT     DX, AX                  ; EF
                INC     DX                      ; 42
                MOV     AL, es:[DI]             ; 26 8A 05
                MOV     es:[DI], CL             ; 26 88 0D
                MOV     AL, BL                  ; 8A C3
                AND     AL, 55H                 ; 24 55
                OUT     DX, AL                  ; EE
                MOV     AL, es:[DI]             ; 26 8A 05
                MOV     AL, CH                  ; 8A C5
                STOSB                           ; AA
                JMP     SHORT eva_psf_phase0_next ; EB 77
eva_psf_p0_wide:
                MOV     DX, 0004H               ; BA 04 00
                SUB     DX, BX                  ; 2B D3
                SUB     CX, DX                  ; 2B CA
                MOV     AH, cs:[BX+080FH]       ; 2E 8A A7 0F 08
                MOV     DX, 03CEH               ; BA CE 03
                MOV     AL, 08H                 ; B0 08
                OUT     DX, AL                  ; EE
                INC     DX                      ; 42
                MOV     BX, cs:[0817H]          ; 2E 8B 1E 17 08
                MOV     AL, es:[DI]             ; 26 8A 05
                MOV     AL, AH                  ; 8A C4
                AND     AL, 0AAH                ; 24 AA
                OUT     DX, AL                  ; EE
                MOV     es:[DI], BL             ; 26 88 1D
                MOV     AL, es:[DI]             ; 26 8A 05
                MOV     AL, AH                  ; 8A C4
                AND     AL, 55H                 ; 24 55
                OUT     DX, AL                  ; EE
                MOV     AL, BH                  ; 8A C7
                STOSB                           ; AA
                MOV     AH, CL                  ; 8A E1
                SHR     CX, 1                   ; D1 E9
                SHR     CX, 1                   ; D1 E9
                JZ      SHORT eva_psf_p0_tail   ; 74 1D
                MOV     AL, 0AAH                ; B0 AA
                OUT     DX, AL                  ; EE
                MOV     es:[DI], BL             ; 26 88 1D
                SHR     AL, 1                   ; D0 E8
                OUT     DX, AL                  ; EE
                MOV     AL, es:[DI]             ; 26 8A 05
                MOV     AL, BH                  ; 8A C7
                MOV     DH, AH                  ; 8A F4
                MOV     AH, AL                  ; 8A E0
                SHR     CX, 1                   ; D1 E9
                REP     STOSW                   ; F3 AB
                MOV     AH, DH                  ; 8A E6
                MOV     DH, 03H                 ; B6 03
                JNC     SHORT eva_psf_p0_tail   ; 73 01
                STOSB                           ; AA
eva_psf_p0_tail:
                MOV     CL, AH                  ; 8A CC
                XCHG    CX, BX                  ; 87 CB
                AND     BX, 0003H               ; 83 E3 03
                JZ      SHORT eva_psf_phase0_next ; 74 1B
                MOV     AH, cs:[BX+0813H]       ; 2E 8A A7 13 08
                MOV     AL, AH                  ; 8A C4
                AND     AL, 0AAH                ; 24 AA
                OUT     DX, AL                  ; EE
                MOV     AL, es:[DI]             ; 26 8A 05
                MOV     es:[DI], CL             ; 26 88 0D
                MOV     AL, AH                  ; 8A C4
                AND     AL, 55H                 ; 24 55
                OUT     DX, AL                  ; EE
                MOV     AL, es:[DI]             ; 26 8A 05
                MOV     es:[DI], CH             ; 26 88 2D
eva_psf_phase0_next:
                SUB     WORD PTR cs:[0819H], 1  ; 2E 83 2E 19 08 01
                JLE     SHORT eva_psf_p0_exit   ; 7E 06
                ADD     BP, 2                   ; 83 C5 02
                JMP     eva_psf_phase0_loop     ; E9 1A FF
eva_psf_p0_exit:
                POP     DS                      ; 1F
                RETF                            ; CB
                ; ---- Phase 1 / column-phase 1 entry --------------------
eva_psf_phase1:
                MOV     cs:[081DH], AX          ; 2E A3 1D 08
                MOV     BX, BP                  ; 8B DD
                SHR     BX, 1                   ; D1 EB
                SHR     BX, 1                   ; D1 EB
                JC      SHORT eva_psf_p1_kick   ; 72 03
                JMP     eva_psf_phase2_loop     ; E9 E5 00
eva_psf_p1_kick:
eva_psf_phase1_loop:
                LODSW                           ; AD
                MOV     BX, AX                  ; 8B D8
                LODSW                           ; AD
                SUB     AX, BX                  ; 2B C3
                JGE     SHORT eva_psf_p1_ok     ; 7D 03
                JMP     eva_psf_phase1_next     ; E9 CD 00
eva_psf_p1_ok:
                INC     AX                      ; 40
                MOV     CX, AX                  ; 8B C8
                MOV     DI, cs:[081FH]          ; 2E 8B 3E 1F 08
                MOV     DI, [BP+DI]             ; 8B 3B
                MOV     AX, cs:[081BH]          ; 2E A1 1B 08
                MOV     cs:[0817H], AX          ; 2E A3 17 08
                MOV     AX, BX                  ; 8B C3
                SHR     AX, 1                   ; D1 E8
                SHR     AX, 1                   ; D1 E8
                ADD     DI, AX                  ; 03 F8
                AND     BX, 0003H               ; 83 E3 03
                MOV     DX, BX                  ; 8B D3
                ADD     DX, CX                  ; 03 D1
                CMP     DX, 0004H               ; 83 FA 04
                JGE     SHORT eva_psf_p1_wide   ; 7D 30
                MOV     CX, cs:[0817H]          ; 2E 8B 0E 17 08
                MOV     AH, cs:[BX+080FH]       ; 2E 8A A7 0F 08
                MOV     BL, DL                  ; 8A DA
                AND     AH, cs:[BX+0813H]       ; 2E 22 A7 13 08
                MOV     BL, AH                  ; 8A DC
                AND     AH, 0AAH                ; 80 E4 AA
                MOV     AL, 08H                 ; B0 08
                MOV     DX, 03CEH               ; BA CE 03
                OUT     DX, AX                  ; EF
                INC     DX                      ; 42
                MOV     AL, es:[DI]             ; 26 8A 05
                MOV     es:[DI], CL             ; 26 88 0D
                MOV     AL, BL                  ; 8A C3
                AND     AL, 55H                 ; 24 55
                OUT     DX, AL                  ; EE
                MOV     AL, es:[DI]             ; 26 8A 05
                MOV     AL, CH                  ; 8A C5
                STOSB                           ; AA
                JMP     SHORT eva_psf_phase1_next ; EB 77
eva_psf_p1_wide:
                MOV     DX, 0004H               ; BA 04 00
                SUB     DX, BX                  ; 2B D3
                SUB     CX, DX                  ; 2B CA
                MOV     AH, cs:[BX+080FH]       ; 2E 8A A7 0F 08
                MOV     DX, 03CEH               ; BA CE 03
                MOV     AL, 08H                 ; B0 08
                OUT     DX, AL                  ; EE
                INC     DX                      ; 42
                MOV     BX, cs:[0817H]          ; 2E 8B 1E 17 08
                MOV     AL, es:[DI]             ; 26 8A 05
                MOV     AL, AH                  ; 8A C4
                AND     AL, 0AAH                ; 24 AA
                OUT     DX, AL                  ; EE
                MOV     es:[DI], BL             ; 26 88 1D
                MOV     AL, es:[DI]             ; 26 8A 05
                MOV     AL, AH                  ; 8A C4
                AND     AL, 55H                 ; 24 55
                OUT     DX, AL                  ; EE
                MOV     AL, BH                  ; 8A C7
                STOSB                           ; AA
                MOV     AH, CL                  ; 8A E1
                SHR     CX, 1                   ; D1 E9
                SHR     CX, 1                   ; D1 E9
                JZ      SHORT eva_psf_p1_tail   ; 74 1D
                MOV     AL, 0AAH                ; B0 AA
                OUT     DX, AL                  ; EE
                MOV     es:[DI], BL             ; 26 88 1D
                SHR     AL, 1                   ; D0 E8
                OUT     DX, AL                  ; EE
                MOV     AL, es:[DI]             ; 26 8A 05
                MOV     AL, BH                  ; 8A C7
                MOV     DH, AH                  ; 8A F4
                MOV     AH, AL                  ; 8A E0
                SHR     CX, 1                   ; D1 E9
                REP     STOSW                   ; F3 AB
                MOV     AH, DH                  ; 8A E6
                MOV     DH, 03H                 ; B6 03
                JNC     SHORT eva_psf_p1_tail   ; 73 01
                STOSB                           ; AA
eva_psf_p1_tail:
                MOV     CL, AH                  ; 8A CC
                XCHG    CX, BX                  ; 87 CB
                AND     BX, 0003H               ; 83 E3 03
                JZ      SHORT eva_psf_phase1_next ; 74 1B
                MOV     AH, cs:[BX+0813H]       ; 2E 8A A7 13 08
                MOV     AL, AH                  ; 8A C4
                AND     AL, 0AAH                ; 24 AA
                OUT     DX, AL                  ; EE
                MOV     AL, es:[DI]             ; 26 8A 05
                MOV     es:[DI], CL             ; 26 88 0D
                MOV     AL, AH                  ; 8A C4
                AND     AL, 55H                 ; 24 55
                OUT     DX, AL                  ; EE
                MOV     AL, es:[DI]             ; 26 8A 05
                MOV     es:[DI], CH             ; 26 88 2D
eva_psf_phase1_next:
                SUB     WORD PTR cs:[0819H], 1  ; 2E 83 2E 19 08 01
                JG      SHORT eva_psf_p1_more   ; 7F 02
                POP     DS                      ; 1F
                RETF                            ; CB
eva_psf_p1_more:
                ADD     BP, 2                   ; 83 C5 02
                ; ---- Phase 2 / column-phase 2 loop ---------------------
eva_psf_phase2_loop:
                LODSW                           ; AD
                MOV     BX, AX                  ; 8B D8
                LODSW                           ; AD
                SUB     AX, BX                  ; 2B C3
                JGE     SHORT eva_psf_p2_ok     ; 7D 03
                JMP     eva_psf_phase2_next     ; E9 CD 00
eva_psf_p2_ok:
                INC     AX                      ; 40
                MOV     CX, AX                  ; 8B C8
                MOV     DI, cs:[081FH]          ; 2E 8B 3E 1F 08
                MOV     DI, [BP+DI]             ; 8B 3B
                MOV     AX, cs:[081DH]          ; 2E A1 1D 08
                MOV     cs:[0817H], AX          ; 2E A3 17 08
                MOV     AX, BX                  ; 8B C3
                SHR     AX, 1                   ; D1 E8
                SHR     AX, 1                   ; D1 E8
                ADD     DI, AX                  ; 03 F8
                AND     BX, 0003H               ; 83 E3 03
                MOV     DX, BX                  ; 8B D3
                ADD     DX, CX                  ; 03 D1
                CMP     DX, 0004H               ; 83 FA 04
                JGE     SHORT eva_psf_p2_wide   ; 7D 30
                MOV     CX, cs:[0817H]          ; 2E 8B 0E 17 08
                MOV     AH, cs:[BX+080FH]       ; 2E 8A A7 0F 08
                MOV     BL, DL                  ; 8A DA
                AND     AH, cs:[BX+0813H]       ; 2E 22 A7 13 08
                MOV     BL, AH                  ; 8A DC
                AND     AH, 0AAH                ; 80 E4 AA
                MOV     AL, 08H                 ; B0 08
                MOV     DX, 03CEH               ; BA CE 03
                OUT     DX, AX                  ; EF
                INC     DX                      ; 42
                MOV     AL, es:[DI]             ; 26 8A 05
                MOV     es:[DI], CL             ; 26 88 0D
                MOV     AL, BL                  ; 8A C3
                AND     AL, 55H                 ; 24 55
                OUT     DX, AL                  ; EE
                MOV     AL, es:[DI]             ; 26 8A 05
                MOV     AL, CH                  ; 8A C5
                STOSB                           ; AA
                JMP     SHORT eva_psf_phase2_next ; EB 77
eva_psf_p2_wide:
                MOV     DX, 0004H               ; BA 04 00
                SUB     DX, BX                  ; 2B D3
                SUB     CX, DX                  ; 2B CA
                MOV     AH, cs:[BX+080FH]       ; 2E 8A A7 0F 08
                MOV     DX, 03CEH               ; BA CE 03
                MOV     AL, 08H                 ; B0 08
                OUT     DX, AL                  ; EE
                INC     DX                      ; 42
                MOV     BX, cs:[0817H]          ; 2E 8B 1E 17 08
                MOV     AL, es:[DI]             ; 26 8A 05
                MOV     AL, AH                  ; 8A C4
                AND     AL, 0AAH                ; 24 AA
                OUT     DX, AL                  ; EE
                MOV     es:[DI], BL             ; 26 88 1D
                MOV     AL, es:[DI]             ; 26 8A 05
                MOV     AL, AH                  ; 8A C4
                AND     AL, 55H                 ; 24 55
                OUT     DX, AL                  ; EE
                MOV     AL, BH                  ; 8A C7
                STOSB                           ; AA
                MOV     AH, CL                  ; 8A E1
                SHR     CX, 1                   ; D1 E9
                SHR     CX, 1                   ; D1 E9
                JZ      SHORT eva_psf_p2_tail   ; 74 1D
                MOV     AL, 0AAH                ; B0 AA
                OUT     DX, AL                  ; EE
                MOV     es:[DI], BL             ; 26 88 1D
                SHR     AL, 1                   ; D0 E8
                OUT     DX, AL                  ; EE
                MOV     AL, es:[DI]             ; 26 8A 05
                MOV     AL, BH                  ; 8A C7
                MOV     DH, AH                  ; 8A F4
                MOV     AH, AL                  ; 8A E0
                SHR     CX, 1                   ; D1 E9
                REP     STOSW                   ; F3 AB
                MOV     AH, DH                  ; 8A E6
                MOV     DH, 03H                 ; B6 03
                JNC     SHORT eva_psf_p2_tail   ; 73 01
                STOSB                           ; AA
eva_psf_p2_tail:
                MOV     CL, AH                  ; 8A CC
                XCHG    CX, BX                  ; 87 CB
                AND     BX, 0003H               ; 83 E3 03
                JZ      SHORT eva_psf_phase2_next ; 74 1B
                MOV     AH, cs:[BX+0813H]       ; 2E 8A A7 13 08
                MOV     AL, AH                  ; 8A C4
                AND     AL, 0AAH                ; 24 AA
                OUT     DX, AL                  ; EE
                MOV     AL, es:[DI]             ; 26 8A 05
                MOV     es:[DI], CL             ; 26 88 0D
                MOV     AL, AH                  ; 8A C4
                AND     AL, 55H                 ; 24 55
                OUT     DX, AL                  ; EE
                MOV     AL, es:[DI]             ; 26 8A 05
                MOV     es:[DI], CH             ; 26 88 2D
eva_psf_phase2_next:
                SUB     WORD PTR cs:[0819H], 1  ; 2E 83 2E 19 08 01
                JLE     SHORT eva_psf_p2_exit   ; 7E 06
                ADD     BP, 2                   ; 83 C5 02
                JMP     eva_psf_phase1_loop     ; E9 35 FE -- wraps back to phase1
eva_psf_p2_exit:
                POP     DS                      ; 1F
                MOV     AX, 0005H               ; B8 05 00
                MOV     DX, 03CEH               ; BA CE 03
                OUT     DX, AX                  ; EF
                RETF                            ; CB
eva_polygon_span_fill ENDP

; ============================================================================
; eva_vsync_wait -- swap back-buffer page and optionally wait for vsync.
; chunk:0x0B3C..0x0B82  (vtable slot 7)
;
; Swaps the back-buffer A / front-buffer slots (scratch:[0x14] <-> [0x12]),
; reprograms CRTC index 0Ch (Start Address High) so the CRT now scans out
; from the formerly-back page, then -- if [BP+6] != 0 -- busy-polls 0x3DA
; bit 3 (vretrace status) until retrace starts.
;
; Page-flip mechanism: each EGA page is a 16 KB window at A000:N000 (see
; the hardware primer's memory-map note). To present a different page,
; we change the CRTC's Start Address by writing a 16-bit start offset
; into CRTC index 0Ch (high byte) / 0Dh (low byte). This driver only
; writes 0Ch because the back-buffer offsets are page-aligned (0x4000
; multiples) so the low byte is always zero. The Start Address takes
; effect at the NEXT vertical retrace -- which is why the vsync poll
; below matters: returning before the new value latches would show the
; viewer a torn frame.
;
; The CRTC index port (0x3D4 colour / 0x3B4 mono) is not hard-coded --
; we read it from the BIOS data area at 40:0063 ("addr_6845"). BIOS set
; this when it programmed mode 0Eh.
;
; ABI (__cdecl16far, vtable slot):
;   [BP+06]  ushort  wait_for_vsync  (0 = swap pages and return immediately;
;                                     non-zero = also busy-wait for the
;                                     vertical-retrace edge so the page
;                                     flip happens during the blanking
;                                     interval and the viewer sees no tear)
;
; The vsync poll runs TWO loops back to back: the first waits for the
; "active video" state (bit 3 of port 0x3DA == 0) and the second waits
; for vretrace to start (bit 3 == 1). This catches the leading edge of
; retrace even if the function was entered mid-retrace, otherwise the
; second loop would fall through immediately and the swap would be timed
; to the wrong half of the frame.
; ============================================================================
eva_vsync_wait  PROC    FAR
                PUSH    BP                      ; 55
                MOV     BP, SP                  ; 8B EC
                PUSH    ES                      ; 06
                PUSH    DS                      ; 1E
                MOV     DS, cs:[0B2H]           ; 2E 8E 1E B2 00
                MOV     AX, ds:[GfxContext.wVgaPage2Base] ; A1 12 00
                MOV     CX, AX                  ; 8B C8
                XCHG    ds:[GfxContext.wVgaFrontPageBase], AX ; 87 06 14 00
                MOV     ds:[GfxContext.wVgaPage2Base], AX ; A3 12 00
                SHR     CX, 1                   ; D1 E9
                SHR     CX, 1                   ; D1 E9
                SHR     CX, 1                   ; D1 E9
                SHR     CX, 1                   ; D1 E9
                MOV     AX, 0040H               ; B8 40 00
                MOV     ES, AX                  ; 8E C0      BIOS data area segment
                MOV     DX, es:[0063H]          ; 26 8B 16 63 00   BIOS CRTC index port
                                                ;   (40:0063 = "addr_6845" -- 0x3D4 colour
                                                ;    or 0x3B4 mono; BIOS stashed it for us)
                MOV     AL, 0CH                 ; B0 0C       CRTC index 0Ch (Start Address Hi)
                MOV     AH, CL                  ; 8A E1       value = new_page_seg >> 12
                OUT     DX, AX                  ; EF          AX = (value << 8) | 0Ch ->
                                                ;   one 16-bit OUT writes both index and
                                                ;   data in one bus cycle (the CRTC accepts
                                                ;   sequential index/data WORD writes)
                MOV     AX, [BP+6]              ; 8B 46 06
                OR      AX, AX                  ; 0B C0
                JZ      SHORT eva_vsync_exit    ; 74 0F
                MOV     CL, 08H                 ; B1 08
                MOV     DX, 03DAH               ; BA DA 03
eva_vsync_poll_lo:
                IN      AL, DX                  ; EC
                AND     AL, CL                  ; 22 C1
                JNZ     SHORT eva_vsync_poll_lo ; 75 FB
eva_vsync_poll_hi:
                IN      AL, DX                  ; EC
                AND     AL, CL                  ; 22 C1
                JZ      SHORT eva_vsync_poll_hi ; 74 FB
eva_vsync_exit:
                POP     DS                      ; 1F
                POP     ES                      ; 07
                POP     BP                      ; 5D
                RETF                            ; CB
eva_vsync_wait  ENDP

; ============================================================================
; eva_image_install -- compute size of installed image list.
; chunk:0x0B83..0x0BB5  (vtable slot 12)
;
; Walks the host-supplied image-list array (NULL-terminated), accumulates
; width*height for each entry into a 32-bit value in DX:BX, returns AX = BX
; (truncated low word). Zeroes the user-supplied output word at [BP+8].
;
; ABI (__cdecl16far, vtable slot):
;   [BP+06]  ushort  image_list_off  (DI; near-pointer array of pointers
;                    to 10-byte frame headers; NULL-terminated)
;   [BP+08]  ushort  out_word_off    (set to 0 on exit -- appears to be a
;                                     "decoded-byte-count" output slot
;                                     that this implementation always
;                                     zeroes; the count is returned in
;                                     AX instead)
; Returns:
;   AX       low 16 bits of summed sum(w*h)
;   DX:BX    full 32-bit sum (callers that need >64 KB read DX too)
; ============================================================================
eva_image_install PROC FAR
                PUSH    BP                      ; 55
                MOV     BP, SP                  ; 8B EC
                PUSH    SI                      ; 56
                PUSH    DI                      ; 57
                MOV     DI, [BP+6]              ; 8B 7E 06
                XOR     BX, BX                  ; 33 DB
                XOR     DX, DX                  ; 33 D2
eva_ii_loop:
                MOV     SI, [DI]                ; 8B 35
                OR      SI, SI                  ; 0B F6
                JZ      SHORT eva_ii_done       ; 74 14
                PUSH    DX                      ; 52
                XOR     DX, DX                  ; 33 D2
                MOV     AX, [SI+6]              ; 8B 44 06
                MUL     WORD PTR [SI+8]         ; F7 64 08
                POP     DX                      ; 5A
                ADD     BX, AX                  ; 03 D8
                ADC     DX, 0                   ; 83 D2 00
                ADD     DI, 2                   ; 83 C7 02
                JMP     SHORT eva_ii_loop       ; EB E6
eva_ii_done:
                MOV     AX, BX                  ; 8B C3
                MOV     SI, [BP+8]              ; 8B 76 08
                MOV     WORD PTR [SI], 0        ; C7 04 00 00
                POP     DI                      ; 5F
                POP     SI                      ; 5E
                POP     BP                      ; 5D
                RETF                            ; CB
eva_image_install ENDP

; ============================================================================
; eva_image_decode -- install/decode an image-list into a working buffer.
; chunk:0x0BB6..0x0D04  (vtable slot 13)
;
; Walks an image-list, packs the chunky source bytes into 4-bit nibble pairs
; (high << 4 | low), writes them in reverse into the dst buffer. The byte-
; pair packing (`AND AX,0xf0f` etc.) is the inverse of the dither expansion
; in eva_image_query_size.
;
; ABI (__cdecl16far, vtable slot; 5 word args -- semantics partially RE'd):
;   [BP+06]  ushort  image_list_off  (near-pointer array, written back as
;                                     a cursor by `ADD WORD PTR [BP+6],2`)
;   [BP+08]  ushort  dst_off         (working buffer base offset)
;   [BP+0A]  ushort  dst_seg         (working buffer base segment;
;                                     incremented as ES advances past
;                                     64 KB chunks)
;   [BP+0C]  ushort  count_lo        (32-bit count of bytes to pack;
;                                     decremented with borrow into [BP+0E])
;   [BP+0E]  uchar   count_hi        (high byte of the 32-bit count)
; ============================================================================
eva_image_decode PROC FAR
                PUSH    BP                      ; 55
                MOV     BP, SP                  ; 8B EC
                PUSH    SI                      ; 56
                PUSH    DI                      ; 57
                PUSH    DS                      ; 1E
                MOV     DI, [BP+8]              ; 8B 7E 08
                MOV     ES, [BP+0AH]            ; 8E 46 0A
eva_id_outer_load:
                MOV     SI, [BP+6]              ; 8B 76 06
                MOV     SI, [SI]                ; 8B 34
                OR      SI, SI                  ; 0B F6
                JZ      SHORT eva_id_phase2     ; 74 34
                MOV     DX, DI                  ; 8B D7
                MOV     AX, ES                  ; 8C C0
                MOV     CL, 04H                 ; B1 04
                SHR     DX, CL                  ; D3 EA
                ADD     AX, DX                  ; 03 C2
                MOV     [SI], AX                ; 89 04
                MOV     DX, DI                  ; 8B D7
                AND     DX, 000FH               ; 83 E2 0F
                MOV     [SI+2], DX              ; 89 54 02
                MOV     AX, [SI+6]              ; 8B 44 06
                XOR     DX, DX                  ; 33 D2
                MUL     WORD PTR [SI+8]         ; F7 64 08
                XOR     CX, CX                  ; 33 C9
                ADD     DI, AX                  ; 03 F8
                RCR     CX, 1                   ; D1 D9
                SHR     CX, 1                   ; D1 E9
                SHR     CX, 1                   ; D1 E9
                SHR     CX, 1                   ; D1 E9
                MOV     AX, ES                  ; 8C C0
                ADD     AX, CX                  ; 03 C1
                MOV     ES, AX                  ; 8E C0
                ADD     WORD PTR [BP+6], 2      ; 83 46 06 02
                JMP     SHORT eva_id_outer_load ; EB C3
                ; ---- Phase 2: pack source bytes into nibble pairs --
eva_id_phase2:
                MOV     SI, [BP+8]              ; 8B 76 08
                MOV     AX, [BP+0AH]            ; 8B 46 0A
                XOR     CX, CX                  ; 33 C9
                ADD     SI, [BP+0CH]            ; 03 76 0C
                RCR     CX, 1                   ; D1 D9
                SHR     CX, 1                   ; D1 E9
                SHR     CX, 1                   ; D1 E9
                SHR     CX, 1                   ; D1 E9
                MOV     BH, [BP+0EH]            ; 8A 7E 0E
                XOR     BL, BL                  ; 32 DB
                SHL     BX, 1                   ; D1 E3
                SHL     BX, 1                   ; D1 E3
                SHL     BX, 1                   ; D1 E3
                SHL     BX, 1                   ; D1 E3
                ADD     BX, CX                  ; 03 D9
                SUB     SI, 1                   ; 83 EE 01
                JNC     SHORT eva_id_p2_a       ; 73 03
                SUB     AX, 1000H               ; 2D 00 10
eva_id_p2_a:
                ADD     AX, BX                  ; 03 C3
                MOV     DS, AX                  ; 8E D8
                MOV     DI, [BP+8]              ; 8B 7E 08
                MOV     AX, [BP+0AH]            ; 8B 46 0A
                MOV     DX, [BP+0CH]            ; 8B 56 0C
                MOV     BH, [BP+0EH]            ; 8A 7E 0E
                XOR     BL, BL                  ; 32 DB
                SHL     BX, 1                   ; D1 E3
                SHL     BX, 1                   ; D1 E3
                SHL     BX, 1                   ; D1 E3
                SHL     BX, 1                   ; D1 E3
                SHL     BX, 1                   ; D1 E3
                XOR     CX, CX                  ; 33 C9
                SUB     DX, 1                   ; 83 EA 01
                JNC     SHORT eva_id_p2_b       ; 73 04
                SUB     DX, 1000H               ; 81 EA 00 10
eva_id_p2_b:
                SHL     DX, 1                   ; D1 E2
                JNC     SHORT eva_id_p2_c       ; 73 04
                ADD     BX, 1000H               ; 81 C3 00 10
eva_id_p2_c:
                ADD     DI, DX                  ; 03 FA
                RCR     CX, 1                   ; D1 D9
                SHR     CX, 1                   ; D1 E9
                SHR     CX, 1                   ; D1 E9
                SHR     CX, 1                   ; D1 E9
                ADD     BX, CX                  ; 03 D9
                ADD     AX, BX                  ; 03 C3
                MOV     ES, AX                  ; 8E C0
eva_id_p2_loop:
                MOV     AL, [SI]                ; 8A 04
                XOR     CX, CX                  ; 33 C9
                MOV     BX, DS                  ; 8C DB
                SUB     SI, 1                   ; 83 EE 01
                RCR     CX, 1                   ; D1 D9
                SHR     CX, 1                   ; D1 E9
                SHR     CX, 1                   ; D1 E9
                SHR     CX, 1                   ; D1 E9
                SUB     BX, CX                  ; 2B D9
                MOV     DS, BX                  ; 8E DB
                MOV     AH, AL                  ; 8A E0
                MOV     CL, 04H                 ; B1 04
                SHR     AL, CL                  ; D2 E8
                AND     AX, 0F0FH               ; 25 0F 0F
                MOV     es:[DI], AX             ; 26 89 05
                XOR     CX, CX                  ; 33 C9
                MOV     BX, ES                  ; 8C C3
                SUB     DI, 2                   ; 83 EF 02
                RCR     CX, 1                   ; D1 D9
                SHR     CX, 1                   ; D1 E9
                SHR     CX, 1                   ; D1 E9
                SHR     CX, 1                   ; D1 E9
                SUB     BX, CX                  ; 2B D9
                MOV     ES, BX                  ; 8E C3
                SUB     WORD PTR [BP+0CH], 1    ; 83 6E 0C 01
                SBB     WORD PTR [BP+0EH], 0    ; 83 5E 0E 00
                MOV     AX, [BP+0CH]            ; 8B 46 0C
                OR      AX, [BP+0EH]            ; 0B 46 0E
                JNZ     SHORT eva_id_p2_loop    ; 75 BC
                POP     DS                      ; 1F
                POP     DI                      ; 5F
                POP     SI                      ; 5E
                POP     BP                      ; 5D
                RETF                            ; CB
eva_image_decode ENDP

; ============================================================================
; eva_image_query_size -- copy chunky source into doubled-nibble dest.
; chunk:0x0CB1..0x0D04  (vtable slot 14)
;
; Walks CX source bytes at DS:SI, for each splits into two nibbles, shifts
; the high nibble up by 4 bits, AND-masks to 0xF0F0, OR's into ES:DI. The
; net effect is "duplicate each chunky pixel into two planes" -- this is
; the layout the EVA chunky-to-planar engine then dithers.
;
; ABI (__cdecl16far, vtable slot):
;   [BP+06]  ushort  src_off
;   [BP+08]  ushort  src_seg
;   [BP+0A]  ushort  dst_off
;   [BP+0C]  ushort  dst_seg
;   [BP+0E]  ushort  byte_count   (number of chunky source bytes to process)
; ============================================================================
eva_image_query_size PROC FAR
                PUSH    BP                      ; 55
                MOV     BP, SP                  ; 8B EC
                PUSH    SI                      ; 56
                PUSH    DI                      ; 57
                PUSH    DS                      ; 1E
                MOV     SI, [BP+6]              ; 8B 76 06
                MOV     DS, [BP+8]              ; 8E 5E 08
                MOV     DI, [BP+0AH]            ; 8B 7E 0A
                MOV     ES, [BP+0CH]            ; 8E 46 0C
                MOV     CX, [BP+0EH]            ; 8B 4E 0E
eva_iqs_loop:
                XOR     DX, DX                  ; 33 D2
                MOV     AL, [SI]                ; 8A 04
                ADD     SI, 1                   ; 83 C6 01
                RCR     DX, 1                   ; D1 DA
                SHR     DX, 1                   ; D1 EA
                SHR     DX, 1                   ; D1 EA
                SHR     DX, 1                   ; D1 EA
                MOV     BX, DS                  ; 8C DB
                ADD     BX, DX                  ; 03 DA
                MOV     DS, BX                  ; 8E DB
                MOV     AH, AL                  ; 8A E0
                SHL     AH, 1                   ; D0 E4
                SHL     AH, 1                   ; D0 E4
                SHL     AH, 1                   ; D0 E4
                SHL     AH, 1                   ; D0 E4
                AND     AX, 0F0F0H              ; 25 F0 F0
                OR      es:[DI], AX             ; 26 09 05
                XOR     DX, DX                  ; 33 D2
                ADD     DI, 2                   ; 83 C7 02
                RCR     DX, 1                   ; D1 DA
                SHR     DX, 1                   ; D1 EA
                SHR     DX, 1                   ; D1 EA
                SHR     DX, 1                   ; D1 EA
                MOV     BX, ES                  ; 8C C3
                ADD     BX, DX                  ; 03 DA
                MOV     ES, BX                  ; 8E C3
                LOOP    SHORT eva_iqs_loop      ; E2 C6
                POP     DS                      ; 1F
                POP     DI                      ; 5F
                POP     SI                      ; 5E
                POP     BP                      ; 5D
                RETF                            ; CB
eva_image_query_size ENDP

; ============================================================================
; eva_blit_frame_present -- byte-aligned planar->planar rect copy.
; chunk:0x0D05..0x0D78  (vtable slot 3)
;
; Reads a rect from scratch:[0x16] (back-buffer A seg), writes to
; scratch:[0x18] (framebuffer seg). Sets GC to write-mode 1 (latch copy)
; so each REP MOVSB copies all 4 planes at once.
;
; ABI (__cdecl16far, vtable slot):
;   [BP+06]  ushort  x_left        (chunky pixel x; word-aligned internally)
;   [BP+08]  ushort  y_top         (row index into scratch:[06F2] LUT)
;   [BP+0A]  ushort  width_px      (in pixels; rounded up to byte boundary)
;   [BP+0C]  ushort  height_rows
; ============================================================================
eva_blit_frame_present PROC FAR
                PUSH    BP                      ; 55
                MOV     BP, SP                  ; 8B EC
                PUSH    SI                      ; 56
                PUSH    DI                      ; 57
                PUSH    DS                      ; 1E
                PUSH    ES                      ; 06
                MOV     DS, cs:[0B2H]           ; 2E 8E 1E B2 00
                MOV     DX, 03CEH               ; BA CE 03
                MOV     AX, 0105H               ; B8 05 01   GC[5] Mode = 1 (write mode 1)
                OUT     DX, AX                  ; EF
                MOV     DX, 03CEH               ; BA CE 03
                MOV     AX, 0FF08H              ; B8 08 FF
                OUT     DX, AX                  ; EF
                MOV     BX, [BP+0AH]            ; 8B 5E 0A   width
                SHL     BX, 1                   ; D1 E3
                MOV     AX, [BP+6]              ; 8B 46 06   x_left
                SHL     AX, 1                   ; D1 E0
                ADD     BX, AX                  ; 03 D8
                ADD     BX, 7                   ; 83 C3 07
                AND     BX, 0FFF8H              ; 83 E3 F8
                AND     AX, 0FFF8H              ; 25 F8 FF
                SUB     BX, AX                  ; 2B D8
                SHR     BX, 1                   ; D1 EB
                SHR     BX, 1                   ; D1 EB
                SHR     BX, 1                   ; D1 EB
                SHR     AX, 1                   ; D1 E8
                SHR     AX, 1                   ; D1 E8
                SHR     AX, 1                   ; D1 E8
                MOV     SI, AX                  ; 8B F0
                MOV     DX, [BP+0CH]            ; 8B 56 0C   height
                MOV     DI, [BP+8]              ; 8B 7E 08   y_top
                SHL     DI, 1                   ; D1 E7
                MOV     DI, [DI].GfxContext.pRow_offset_lut ; 8B BD F2 06
                ADD     DI, SI                  ; 03 FE
                MOV     AX, ds:[GfxContext.wGfxBlitDstPage] ; A1 18 00
                MOV     ES, AX                  ; 8E C0
                MOV     AX, ds:[GfxContext.wGfxBlitSrcPage] ; A1 16 00
                MOV     DS, AX                  ; 8E D8
eva_bfp_row:
                MOV     CX, BX                  ; 8B CB
                MOV     BP, DI                  ; 8B EF
                MOV     SI, DI                  ; 8B F7
                REP     MOVSB                   ; F3 A4
                MOV     DI, BP                  ; 8B FD
                ADD     DI, 0050H               ; 83 C7 50
                DEC     DX                      ; 4A
                JNZ     SHORT eva_bfp_row       ; 75 F0
                MOV     DX, 03CEH               ; BA CE 03
                MOV     AX, 0005H               ; B8 05 00
                OUT     DX, AX                  ; EF
                POP     ES                      ; 07
                POP     DS                      ; 1F
                POP     DI                      ; 5F
                POP     SI                      ; 5E
                POP     BP                      ; 5D
                RETF                            ; CB
eva_blit_frame_present ENDP

; ============================================================================
; 0x0D79..0x0D91 -- fill-rect dispatch tables / scratch globals.
; ============================================================================
g_bEvaFillRectPad0      DB    0         ; 0x0D79
g_abEvaFillLeftMaskLut LABEL BYTE
                DB      0FFH, 03FH, 00FH, 003H  ; 0x0D7A
g_abEvaFillRightMaskLut LABEL BYTE
                DB      000H, 0C0H, 0F0H, 0FCH  ; 0x0D7E
g_abEvaFillRectPad1     DB    0, 0, 0, 0       ; 0x0D82  (scratch for AND-mask combine)
g_awEvaFillScratch      LABEL WORD
                DW      0                ; 0x0D86
                DW      0                ; 0x0D88
                DW      0200H            ; 0x0D8A  -- pre-baked literal 0x0200
                DW      0                ; 0x0D8C
                DW      0                ; 0x0D8E
g_wEvaPaletteSetScratch DW    0         ; 0x0D90

; ============================================================================
; eva_fill_rect -- fill rectangle in EGA framebuffer.
; chunk:0x0D92..0x0E7B  (vtable slot 9)
;
; This is a NEAR-style entrypoint reached as a vtable FAR call. The caller
; sets ES:DI = framebuffer destination, BX = x-pair (low + (col_phase<<2)),
; CX = pixel run length, DX = colour-index pair; this routine spreads the
; colour through the dither LUT and writes the run using EGA write-mode 2.
;
; Register ABI (inferred from the body):
;   ES:DI = dst byte
;   BX    = (x0 & 3) | (col_phase << 2) basically
;   CX    = run length in bytes
;   DX    = colour-pair (lower byte = colour value, high byte = 0/1 phase)
;
; The body mirrors the inner write-block of eva_polygon_span_fill: it
; computes left/right mask bytes from g_abEvaFillLeftMaskLut /
; g_abEvaFillRightMaskLut and uses Set/Reset + Bit Mask gymnastics.
; ============================================================================
eva_fill_rect   PROC    FAR
                PUSH    AX                      ; 50
                PUSH    BX                      ; 53
                MOV     BX, OFFSET g_abEvaBitSpreadLutEven ; BB E1 04
                SHR     DX, 1                   ; D1 EA
                ADC     BH, 0                   ; 80 D7 00
                XLAT    BYTE PTR CS:[BX]        ; 2E D7
                MOV     AH, AL                  ; 8A E0
                SHR     AH, 1                   ; D0 EC
                SHR     AH, 1                   ; D0 EC
                SHR     AH, 1                   ; D0 EC
                SHR     AH, 1                   ; D0 EC
                AND     AX, 0F0FH               ; 25 0F 0F
                POP     BX                      ; 5B
                MOV     cs:[0D82H], AX          ; 2E A3 82 0D
                MOV     AX, 0205H               ; B8 05 02
                MOV     DX, 03CEH               ; BA CE 03
                OUT     DX, AX                  ; EF
                MOV     AX, BX                  ; 8B C3
                SHR     AX, 1                   ; D1 E8
                SHR     AX, 1                   ; D1 E8
                ADD     DI, AX                  ; 03 F8
                AND     BX, 0003H               ; 83 E3 03
                MOV     DX, BX                  ; 8B D3
                ADD     DX, CX                  ; 03 D1
                CMP     DX, 0004H               ; 83 FA 04
                JGE     SHORT eva_fr_wide       ; 7D 30
                MOV     CX, cs:[0D82H]          ; 2E 8B 0E 82 0D
                MOV     AH, cs:[BX+0D7AH]       ; 2E 8A A7 7A 0D
                MOV     BL, DL                  ; 8A DA
                AND     AH, cs:[BX+0D7EH]       ; 2E 22 A7 7E 0D
                MOV     BL, AH                  ; 8A DC
                AND     AH, 0AAH                ; 80 E4 AA
                MOV     AL, 08H                 ; B0 08
                MOV     DX, 03CEH               ; BA CE 03
                OUT     DX, AX                  ; EF
                INC     DX                      ; 42
                MOV     AL, es:[DI]             ; 26 8A 05
                MOV     es:[DI], CL             ; 26 88 0D
                MOV     AL, BL                  ; 8A C3
                AND     AL, 55H                 ; 24 55
                OUT     DX, AL                  ; EE
                MOV     AL, es:[DI]             ; 26 8A 05
                MOV     AL, CH                  ; 8A C5
                STOSB                           ; AA
                JMP     SHORT eva_fr_exit       ; EB 77
eva_fr_wide:
                MOV     DX, 0004H               ; BA 04 00
                SUB     DX, BX                  ; 2B D3
                SUB     CX, DX                  ; 2B CA
                MOV     AH, cs:[BX+0D7AH]       ; 2E 8A A7 7A 0D
                MOV     DX, 03CEH               ; BA CE 03
                MOV     AL, 08H                 ; B0 08
                OUT     DX, AL                  ; EE
                INC     DX                      ; 42
                MOV     BX, cs:[0D82H]          ; 2E 8B 1E 82 0D
                MOV     AL, es:[DI]             ; 26 8A 05
                MOV     AL, AH                  ; 8A C4
                AND     AL, 0AAH                ; 24 AA
                OUT     DX, AL                  ; EE
                MOV     es:[DI], BL             ; 26 88 1D
                MOV     AL, es:[DI]             ; 26 8A 05
                MOV     AL, AH                  ; 8A C4
                AND     AL, 55H                 ; 24 55
                OUT     DX, AL                  ; EE
                MOV     AL, BH                  ; 8A C7
                STOSB                           ; AA
                MOV     AH, CL                  ; 8A E1
                SHR     CX, 1                   ; D1 E9
                SHR     CX, 1                   ; D1 E9
                JZ      SHORT eva_fr_tail       ; 74 1D
                MOV     AL, 0AAH                ; B0 AA
                OUT     DX, AL                  ; EE
                MOV     es:[DI], BL             ; 26 88 1D
                SHR     AL, 1                   ; D0 E8
                OUT     DX, AL                  ; EE
                MOV     AL, es:[DI]             ; 26 8A 05
                MOV     AL, BH                  ; 8A C7
                MOV     DH, AH                  ; 8A F4
                MOV     AH, AL                  ; 8A E0
                SHR     CX, 1                   ; D1 E9
                REP     STOSW                   ; F3 AB
                MOV     AH, DH                  ; 8A E6
                MOV     DH, 03H                 ; B6 03
                JNC     SHORT eva_fr_tail       ; 73 01
                STOSB                           ; AA
eva_fr_tail:
                MOV     CL, AH                  ; 8A CC
                XCHG    CX, BX                  ; 87 CB
                AND     BX, 0003H               ; 83 E3 03
                JZ      SHORT eva_fr_exit       ; 74 1B
                MOV     AH, cs:[BX+0D7EH]       ; 2E 8A A7 7E 0D
                MOV     AL, AH                  ; 8A C4
                AND     AL, 0AAH                ; 24 AA
                OUT     DX, AL                  ; EE
                MOV     AL, es:[DI]             ; 26 8A 05
                MOV     es:[DI], CL             ; 26 88 0D
                MOV     AL, AH                  ; 8A C4
                AND     AL, 55H                 ; 24 55
                OUT     DX, AL                  ; EE
                MOV     AL, es:[DI]             ; 26 8A 05
                MOV     es:[DI], CH             ; 26 88 2D
eva_fr_exit:
                MOV     AX, 0005H               ; B8 05 00
                MOV     DX, 03CEH               ; BA CE 03
                OUT     DX, AX                  ; EF
                POP     AX                      ; 58
                RETF                            ; CB
eva_fill_rect   ENDP

; ============================================================================
; 0x0E7B..0x0E81 -- palette set scratch globals.
; ============================================================================
g_bEvaPaletteFrameToggle DB    0       ; 0x0E7B
g_wEvaPaletteScratch0    DW    0       ; 0x0E7C
g_wEvaPaletteScratch1    DW    0       ; 0x0E7E
g_wEvaPaletteScratch2    DW    0       ; 0x0E80

; ============================================================================
; eva_palette_load -- per-row palette upload core (vtable slot 36).
; chunk:0x0E82..0x0F9A
;
; Despite the carried-over name "palette_load", structurally this is a row-
; level chunky-to-planar dither blit (cousin of eva_blit_sprite at slot 35
; and eva_palette_set at slot 37, all three of which share the SHL+RCL
; bit-spread pattern). Register-passed -- no stack frame, no __cdecl16far
; args -- so it's invoked by the host directly via the vtable slot rather
; than going through a stack-trampoline.
;
; Register ABI (entry-register-based; the body has no PUSH BP/MOV BP,SP):
;   BP    = src pointer (+2 stride into a chunky source word array)
;   SI    = src offset bias added to BP[]'s words
;   CL    = row count
;   DX    = (x>>2) in DH-ish lane / (x & 3) in CL-ish lane (split below)
;   DI    = dest framebuffer ptr (ES preloaded by host)
;
; Walks the row computing bit-spread XLAT lookups and writing 4 plane
; bytes per pixel-pair via the standard Set/Reset + Map Mask sequence.
; Toggles g_bEvaPaletteFrameToggle at entry to flip the dither phase
; between calls.
;
; State: g_wEvaPaletteScratch0/1/2 @ 0x0E7C..0x0E81 hold per-row scratch.
; ============================================================================
eva_palette_load PROC FAR
                XOR     BYTE PTR cs:[0E7BH], 1  ; 2E 80 36 7B 0E 01
                MOV     BX, OFFSET g_abEvaBitSpreadLutEven ; BB E1 04
                ADD     BH, cs:[0E7BH]          ; 2E 02 3E 7B 0E
                MOV     cs:[0E7EH], BX          ; 2E 89 1E 7E 0E
                MOV     cs:[0E80H], SI          ; 2E 89 36 80 0E
                DEC     CL                      ; FE C9
                MOV     cs:[0E7CH], CX          ; 2E 89 0E 7C 0E
                MOV     CX, DX                  ; 8B CA
                AND     CX, 0003H               ; 83 E1 03
                SHR     DX, 1                   ; D1 EA
                SHR     DX, 1                   ; D1 EA
                ADD     DI, DX                  ; 03 FA
                MOV     DX, 03CEH               ; BA CE 03
                MOV     AX, 0005H               ; B8 05 00
                OUT     DX, AX                  ; EF
                MOV     DX, 03C4H               ; BA C4 03
                MOV     AL, 02H                 ; B0 02
                OUT     DX, AL                  ; EE
                MOV     DX, 03CEH               ; BA CE 03
                MOV     AX, 0FF08H              ; B8 08 FF
                OUT     DX, AX                  ; EF
                SHL     CL, 1                   ; D0 E1
                MOV     AH, 80H                 ; B4 80
                ROR     AH, CL                  ; D2 CC
                XOR     CX, CX                  ; 33 C9
                MOV     DX, CX                  ; 8B D1
                MOV     SI, CX                  ; 8B F1
eva_pl_loop:
                MOV     BX, [BP+0]              ; 8B 5E 00
                ADD     BP, 2                   ; 83 C5 02
                ADD     BX, cs:[0E80H]          ; 2E 03 1E 80 0E
                MOV     AL, [BX]                ; 8A 07
                OR      AL, AL                  ; 0A C0
                JZ      SHORT eva_pl_skip       ; 74 6A
                MOV     BX, cs:[0E7EH]          ; 2E 8B 1E 7E 0E
                XLAT    BYTE PTR CS:[BX]        ; 2E D7
                SHL     AL, 1                   ; D0 E0
                RCL     CL, 1                   ; D0 D1
                SHL     AL, 1                   ; D0 E0
                RCL     CH, 1                   ; D0 D5
                SHL     AL, 1                   ; D0 E0
                RCL     DL, 1                   ; D0 D2
                SHL     AL, 1                   ; D0 E0
                RCL     DH, 1                   ; D0 D6
                SHL     AL, 1                   ; D0 E0
                RCL     CL, 1                   ; D0 D1
                SHL     AL, 1                   ; D0 E0
                RCL     CH, 1                   ; D0 D5
                SHL     AL, 1                   ; D0 E0
                RCL     DL, 1                   ; D0 D2
                SHL     AL, 1                   ; D0 E0
                RCL     DH, 1                   ; D0 D6
                STC                             ; F9
                RCL     SI, 1                   ; D1 D6
                STC                             ; F9
                RCL     SI, 1                   ; D1 D6
                ROR     AH, 1                   ; D0 CC
                ROR     AH, 1                   ; D0 CC
                JNC     SHORT eva_pl_advance    ; 73 2E
eva_pl_emit:
                MOV     BX, DX                  ; 8B DA
                MOV     AL, es:[DI]             ; 26 8A 05
                MOV     DX, 03CFH               ; BA CF 03
                XCHG    AX, SI                  ; 96
                OUT     DX, AL                  ; EE
                MOV     BYTE PTR es:[DI], 0     ; 26 C6 05 00
                XCHG    AX, SI                  ; 96
                MOV     DX, 03C5H               ; BA C5 03
                MOV     AL, 01H                 ; B0 01
                OUT     DX, AL                  ; EE
                MOV     es:[DI], BH             ; 26 88 3D
                SHL     AL, 1                   ; D0 E0
                OUT     DX, AL                  ; EE
                MOV     es:[DI], BL             ; 26 88 1D
                SHL     AL, 1                   ; D0 E0
                OUT     DX, AL                  ; EE
                MOV     es:[DI], CH             ; 26 88 2D
                SHL     AL, 1                   ; D0 E0
                OUT     DX, AL                  ; EE
                MOV     AL, CL                  ; 8A C1
                STOSB                           ; AA
                XOR     CX, CX                  ; 33 C9
                MOV     DX, CX                  ; 8B D1
eva_pl_advance:
                DEC     WORD PTR cs:[0E7CH]     ; 2E FF 0E 7C 0E
                JNZ     SHORT eva_pl_loop       ; 75 87
                JMP     SHORT eva_pl_finalize   ; EB 14
eva_pl_skip:
                SHL     SI, 1                   ; D1 E6
                SHL     SI, 1                   ; D1 E6
                SHL     CX, 1                   ; D1 E1
                SHL     CX, 1                   ; D1 E1
                SHL     DX, 1                   ; D1 E2
                SHL     DX, 1                   ; D1 E2
                ROR     AH, 1                   ; D0 CC
                ROR     AH, 1                   ; D0 CC
                JNC     SHORT eva_pl_advance    ; 73 E5
                JMP     SHORT eva_pl_emit       ; EB B5
eva_pl_finalize:
                SHL     SI, 1                   ; D1 E6
                SHL     SI, 1                   ; D1 E6
                SHL     CX, 1                   ; D1 E1
                SHL     CX, 1                   ; D1 E1
                SHL     DX, 1                   ; D1 E2
                SHL     DX, 1                   ; D1 E2
                ROR     AH, 1                   ; D0 CC
                ROR     AH, 1                   ; D0 CC
                JNC     SHORT eva_pl_finalize   ; 73 EE
                MOV     BX, DX                  ; 8B DA
                XCHG    AX, SI                  ; 96
                MOV     DX, 03CFH               ; BA CF 03
                OUT     DX, AL                  ; EE
                MOV     AL, es:[DI]             ; 26 8A 05
                MOV     BYTE PTR es:[DI], 0     ; 26 C6 05 00
                MOV     DX, 03C5H               ; BA C5 03
                MOV     AL, 01H                 ; B0 01
                OUT     DX, AL                  ; EE
                MOV     es:[DI], BH             ; 26 88 3D
                SHL     AL, 1                   ; D0 E0
                OUT     DX, AL                  ; EE
                MOV     es:[DI], BL             ; 26 88 1D
                SHL     AL, 1                   ; D0 E0
                OUT     DX, AL                  ; EE
                MOV     es:[DI], CH             ; 26 88 2D
                SHL     AL, 1                   ; D0 E0
                OUT     DX, AL                  ; EE
                MOV     AL, CL                  ; 8A C1
                STOSB                           ; AA
                MOV     AL, 0FH                 ; B0 0F
                OUT     DX, AL                  ; EE
                RETF                            ; CB
eva_palette_load ENDP

; ============================================================================
; eva_blit_sprite -- unclipped chunky-byte sprite blit with EGA dither.
; chunk:0x0FA0..0x10E5  (slot 35 of g_apfnEvaVtable).
;
; The 6 bytes at 0x0F9A are the early-exit epilogue, reached by the in-body
; JLE at 0x0FBE -- not a stand-alone function.
;
; Faster path than eva_blit_sprite_master @ 0x14C0 (slot 28): no flip
; dispatch, no clipping. Used for unclipped on-screen sprites where the
; caller guarantees full visibility.
;
; ABI (__cdecl16far, vtable slot):
;   [BP+06]  far*   sprite descriptor (off + seg of frame header)
;   [BP+0A]  int    dst_x (chunky x in pixels)
;   ES:DI    dst framebuffer pointer (entered with ES preloaded by host)
;   DX, CX   width-pre / width-rem in pixels (caller-set; DX negative => clip
;            left and shrink width by |DX|)
;
; Phase toggle:
;   Right after the prologue, the entry flips bit 0 of cs:[0xE7B] --
;   a 0/1 row-phase counter that selects the even/odd bit-spread LUT
;   (g_abEvaBitSpreadLut* @ 0x4E1 / 0x5E1). Each call to this function
;   inverts the dither phase.
;
; Globals touched:
;   cs:[0E7B]  uchar  row-phase toggle
;   cs:[0E7C]  word   per-row pixel-pair counter (decremented)
;   cs:[0E7E]  word   active bit-spread LUT base for this row
;   cs:[0E80]  word   precomputed dst-byte base for the row
; ============================================================================
eva_blit_sprite PROC FAR
                ; --- 0x0F9A: shared early-exit epilogue. Reached by JLE
                ; at 0x0FBE when (width - |dx_clip|) <= 0 (sprite fully
                ; clipped). The RET here is a near return (C3) inside a
                ; PROC FAR -- inconsistent with the vtable FAR-call entry,
                ; which pushes CS:IP. Either the caller path tolerates
                ; the orphaned CS on its stack, or this branch is
                ; unreachable at runtime; the chunk-local evidence is
                ; inconclusive.
eva_blit_sprite_early_exit:
                MOV     AX, SS                  ; 8C D0
                MOV     DS, AX                  ; 8E D8
                POP     BP                      ; 5D
                RETN                            ; C3        ; near RET inside a PROC FAR -- see note above
                ; --- 0x0FA0: function entry. Flip row-phase toggle and
                ; pick the even/odd bit-spread LUT base.
                PUSH    BP                      ; 55
                MOV     BP, SP                  ; 8B EC
                XOR     BYTE PTR cs:[0E7BH], 1  ; 2E 80 36 7B 0E 01
                MOV     BX, 04E1H               ; BB E1 04   ; even LUT base
                ADD     BH, cs:[0E7BH]          ; 2E 02 3E 7B 0E   ; +0/+1 page selects LUT
                MOV     cs:[0E7EH], BX          ; 2E 89 1E 7E 0E
                ; --- 0x0FB6: handle negative dx_clip (left clip). If DX
                ; (clip count, signed) >= 0, fall through; else absorb |DX|
                ; pixel-pairs from the source by SHL/SHL of DX into
                ; [BP+0Ah], and exit early if width <= |DX|.
                OR      DX, DX                  ; 0B D2
                JNS     SHORT eva_blit_sprite_skip_clip ; 79 0D
                NEG     DX                      ; F7 DA
                SUB     CX, DX                  ; 2B CA
                JLE     SHORT eva_blit_sprite_early_exit ; 7E DA
                SHL     DX, 1                   ; D1 E2
                ADD     WORD PTR [BP+0AH], DX   ; 01 56 0A
                XOR     DX, DX                  ; 33 D2
eva_blit_sprite_skip_clip:
                MOV     cs:[0E7CH], CX          ; 2E 89 0E 7C 0E
                MOV     CX, DX                  ; 8B CA
                SHR     DX, 1                   ; D1 EA
                SHR     DX, 1                   ; D1 EA
                ADD     DI, DX                  ; 03 FA
                MOV     BX, [BP+8]              ; 8B 5E 08
                MOV     cs:[0E80H], BX          ; 2E 89 1E 80 0E
                MOV     AX, [BP+0AH]            ; 8B 46 0A
                MOV     BP, [BP+6]              ; 8B 6E 06
                MOV     DS, [BP+0]              ; 8E 5E 00     ; sprite seg
                ADD     BX, [BP+2]              ; 03 5E 02     ; sprite row-base
                MOV     BP, AX                  ; 8B E8
                ; --- 0x0FEA: program EGA write mode 0, sequencer index 2
                ; for plane writes, GC bit-mask = 0xFF.
                MOV     DX, 03CEH               ; BA CE 03
                MOV     AX, 0005H               ; B8 05 00     ; index=5 mode=0
                OUT     DX, AX                  ; EF
                MOV     DX, 03C4H               ; BA C4 03
                MOV     AL, 02H                 ; B0 02        ; SEQ index 2
                OUT     DX, AL                  ; EE
                MOV     DX, 03CEH               ; BA CE 03
                MOV     AX, 0FF08H              ; B8 08 FF     ; index=8 mask=0xFF
                OUT     DX, AX                  ; EF
                ; --- 0x0FFE: build pixel-pair bit mask in AH from low 2
                ; bits of x (CL). Pixel pairs go in 4 EGA columns per byte;
                ; (x & 3) * 2 picks the starting bit pair.
                AND     CL, 03H                 ; 80 E1 03
                SHL     CL, 1                   ; D0 E1
                MOV     AH, 80H                 ; B4 80
                ROR     AH, CL                  ; D2 CC
                ; --- 0x1007: clear per-pixel-pair accumulators.
                XOR     CX, CX                  ; 33 C9
                MOV     DX, CX                  ; 8B D1
                MOV     SI, CX                  ; 8B F1
eva_bs_row_loop:
                ; --- 0x100D: per-row inner loop. Reload source-byte ptr
                ; from BP[0] (sprite span lo word), advance BP by 2 words
                ; (4 bytes consumed per outer iteration), add base.
                MOV     BX, [BP+0]              ; 8B 5E 00
                ADD     BP, 2                   ; 83 C5 02
                ADD     BX, cs:[0E80H]          ; 2E 03 1E 80 0E
                MOV     AL, [BX]                ; 8A 07
                OR      AL, AL                  ; 0A C0
                JZ      SHORT eva_bs_skip_byte  ; 74 70
                ; --- 0x101E: non-zero source byte -- look up dither in the
                ; selected even/odd LUT (XLAT CS:BX with custom base).
                MOV     BX, cs:[0E7EH]          ; 2E 8B 1E 7E 0E
                XLAT    BYTE PTR CS:[BX]        ; 2E D7
                ; --- 0x1025: spread the LUT byte across 4 plane bytes
                ; (CH:CL = planes 0,1; DH:DL = planes 2,3) two phases.
                SHL     AL, 1                   ; D0 E0
                RCL     CL, 1                   ; D0 D1
                SHL     AL, 1                   ; D0 E0
                RCL     CH, 1                   ; D0 D5
                SHL     AL, 1                   ; D0 E0
                RCL     DL, 1                   ; D0 D2
                SHL     AL, 1                   ; D0 E0
                RCL     DH, 1                   ; D0 D6
                SHL     AL, 1                   ; D0 E0
                RCL     CL, 1                   ; D0 D1
                SHL     AL, 1                   ; D0 E0
                RCL     CH, 1                   ; D0 D5
                SHL     AL, 1                   ; D0 E0
                RCL     DL, 1                   ; D0 D2
                SHL     AL, 1                   ; D0 E0
                RCL     DH, 1                   ; D0 D6
                ; --- 0x1045: shift two 1-bits into SI mask (mark this
                ; pixel-pair as touched) and rotate AH (group mask) by 2.
                STC                             ; F9
                RCL     SI, 1                   ; D1 D6
                STC                             ; F9
                RCL     SI, 1                   ; D1 D6
                ROR     AH, 1                   ; D0 CC
                ROR     AH, 1                   ; D0 CC
                JNC     SHORT eva_bs_advance    ; 73 2E
eva_bs_emit:
                ; --- 0x1051: flush 4 plane bytes' worth of accumulated
                ; planar data through SEQ map-mask sequencing.
                MOV     BX, DX                  ; 8B DA
                MOV     AL, es:[DI]             ; 26 8A 05
                MOV     DX, 03CFH               ; BA CF 03    ; GC data port
                XCHG    AX, SI                  ; 96
                OUT     DX, AL                  ; EE
                MOV     BYTE PTR es:[DI], 0     ; 26 C6 05 00
                XCHG    AX, SI                  ; 96
                MOV     DX, 03C5H               ; BA C5 03    ; SEQ data port
                MOV     AL, 01H                 ; B0 01       ; plane 0
                OUT     DX, AL                  ; EE
                MOV     es:[DI], BH             ; 26 88 3D
                SHL     AL, 1                   ; D0 E0       ; plane 1
                OUT     DX, AL                  ; EE
                MOV     es:[DI], BL             ; 26 88 1D
                SHL     AL, 1                   ; D0 E0       ; plane 2
                OUT     DX, AL                  ; EE
                MOV     es:[DI], CH             ; 26 88 2D
                SHL     AL, 1                   ; D0 E0       ; plane 3
                OUT     DX, AL                  ; EE
                MOV     AL, CL                  ; 8A C1
                STOSB                           ; AA
                XOR     CX, CX                  ; 33 C9
                MOV     DX, CX                  ; 8B D1
eva_bs_advance:
                DEC     WORD PTR cs:[0E7CH]     ; 2E FF 0E 7C 0E
                JNZ     SHORT eva_bs_row_loop   ; 75 87
                JMP     SHORT eva_bs_finalize   ; EB 1A
                MOV     AX, SS                  ; 8C D0
                MOV     DS, AX                  ; 8E D8
                POP     BP                      ; 5D
                RETF                            ; CB
eva_bs_skip_byte:
                ; --- 0x108E: zero source byte fast path. Advance the bit
                ; accumulators by 4 pixel-pairs without doing any LUT work.
                SHL     SI, 1                   ; D1 E6
                SHL     SI, 1                   ; D1 E6
                SHL     CX, 1                   ; D1 E1
                SHL     CX, 1                   ; D1 E1
                SHL     DX, 1                   ; D1 E2
                SHL     DX, 1                   ; D1 E2
                ROR     AH, 1                   ; D0 CC
                ROR     AH, 1                   ; D0 CC
                JNC     SHORT eva_bs_advance    ; 73 DF
                JMP     SHORT eva_bs_emit       ; EB AF
eva_bs_finalize:
                ; --- 0x10A2: tail flush -- complete the partial pixel-pair
                ; group at end-of-row, emit the residual planes if any.
                SHL     SI, 1                   ; D1 E6
                SHL     SI, 1                   ; D1 E6
                SHL     CX, 1                   ; D1 E1
                SHL     CX, 1                   ; D1 E1
                SHL     DX, 1                   ; D1 E2
                SHL     DX, 1                   ; D1 E2
                ROR     AH, 1                   ; D0 CC
                ROR     AH, 1                   ; D0 CC
                JNC     SHORT eva_bs_finalize   ; 73 EE
                MOV     BX, DX                  ; 8B DA
                XCHG    AX, SI                  ; 96
                MOV     DX, 03CFH               ; BA CF 03
                OUT     DX, AL                  ; EE
                MOV     AL, es:[DI]             ; 26 8A 05
                MOV     BYTE PTR es:[DI], 0     ; 26 C6 05 00
                MOV     DX, 03C5H               ; BA C5 03
                MOV     AL, 01H                 ; B0 01
                OUT     DX, AL                  ; EE
                MOV     es:[DI], BH             ; 26 88 3D
                SHL     AL, 1                   ; D0 E0
                OUT     DX, AL                  ; EE
                MOV     es:[DI], BL             ; 26 88 1D
                SHL     AL, 1                   ; D0 E0
                OUT     DX, AL                  ; EE
                MOV     es:[DI], CH             ; 26 88 2D
                SHL     AL, 1                   ; D0 E0
                OUT     DX, AL                  ; EE
                MOV     AL, CL                  ; 8A C1
                STOSB                           ; AA
                MOV     AL, 0FH                 ; B0 0F       ; restore SEQ all-planes mask
                OUT     DX, AL                  ; EE
                MOV     AX, SS                  ; 8C D0
                MOV     DS, AX                  ; 8E D8
                POP     BP                      ; 5D
                RETF                            ; CB
eva_blit_sprite ENDP

; ============================================================================
; eva_palette_set -- immediate two-direction chunky-to-planar blit.
; chunk:0x10E6..0x12F6  (529 bytes; vtable slot 37).
;
; Despite the name, this
; is structurally an EGA chunky-to-planar dither blit identical in shape
; to eva_blit_sprite but with two halves selected by the entry CF flag:
;
;   CF==0 -> forward path (DI increases, identical SHL/RCL dither + STOSB)
;   CF==1 -> reverse path (DI decreases, SHL/RCR dither for mirrored output)
;
; Each path uses its own copy of the 250-byte spread+emit core, then both
; reconverge on a `MOV DX,3C4 / OUT AX (0F02)` (SEQ map mask back to all
; planes) + `MOV DX,3CE / OUT AX (0005)` (GC mode 0) + RETF tail.
;
; ABI (__cdecl16far, vtable slot):
;   CF (entry)  forward/reverse selector
;   ES:DI       destination framebuffer ptr
;   DS:SI       source chunky byte stream (LODSB)
;   BX          starting x (low 2 bits select pixel-pair within byte)
;   CX          row pixel count
;   DX          phase selector (its bit 0 -> SHR DX,1 -> CF chooses LUT half)
;
; Globals touched:
;   cs:[0D84]   word   per-row pixel-pair counter
;   cs:[0D90]   word   active even/odd bit-spread LUT base
; ============================================================================
eva_palette_set PROC FAR
                PUSH    BP                      ; 55
                JNC     SHORT eva_ps_forward    ; 73 03
                JMP     eva_ps_reverse          ; E9 05 01
eva_ps_forward:
                ; --- 0x10EC: forward (DI++) path. Pick LUT page using
                ; carry-out of SHR DX,1 + ADC AH,0.
                MOV     AX, 04E1H               ; B8 E1 04
                SHR     DX, 1                   ; D1 EA
                CMC                             ; F5
                ADC     AH, 0                   ; 80 D4 00
                MOV     cs:[0D90H], AX          ; 2E A3 90 0D
                MOV     DX, 03CEH               ; BA CE 03
                MOV     AX, 0005H               ; B8 05 00
                OUT     DX, AX                  ; EF
                MOV     WORD PTR cs:[0D84H], CX ; 2E 89 0E 84 0D
                MOV     AL, 08H                 ; B0 08
                OUT     DX, AL                  ; EE
                MOV     DX, 03C4H               ; BA C4 03
                MOV     AL, 02H                 ; B0 02
                OUT     DX, AL                  ; EE
                MOV     CX, BX                  ; 8B CB
                AND     CX, 03H                 ; 83 E1 03
                SHL     CX, 1                   ; D1 E1
                MOV     AH, 0C0H                ; B4 C0
                SHR     AH, CL                  ; D2 EC
                SHR     BX, 1                   ; D1 EB
                SHR     BX, 1                   ; D1 EB
                ADD     DI, BX                  ; 03 FB
                MOV     BX, cs:[0D90H]          ; 2E 8B 1E 90 0D
                XOR     CX, CX                  ; 33 C9
                MOV     DX, CX                  ; 8B D1
                MOV     BP, CX                  ; 8B E9
eva_ps_fwd_loop:
                LODSB                           ; AC
                XLAT    BYTE PTR CS:[BX]        ; 2E D7
                SHL     AL, 1                   ; D0 E0
                RCL     CL, 1                   ; D0 D1
                SHL     AL, 1                   ; D0 E0
                RCL     CH, 1                   ; D0 D5
                SHL     AL, 1                   ; D0 E0
                RCL     DL, 1                   ; D0 D2
                SHL     AL, 1                   ; D0 E0
                RCL     DH, 1                   ; D0 D6
                SHL     AL, 1                   ; D0 E0
                RCL     CL, 1                   ; D0 D1
                SHL     AL, 1                   ; D0 E0
                RCL     CH, 1                   ; D0 D5
                SHL     AL, 1                   ; D0 E0
                RCL     DL, 1                   ; D0 D2
                SHL     AL, 1                   ; D0 E0
                RCL     DH, 1                   ; D0 D6
                STC                             ; F9
                RCL     BP, 1                   ; D1 D5
                STC                             ; F9
                RCL     BP, 1                   ; D1 D5
                ROR     AH, 1                   ; D0 CC
                ROR     AH, 1                   ; D0 CC
                JNC     SHORT eva_ps_fwd_advance ; 73 3B
                OR      BP, BP                  ; 0B ED
                JZ      SHORT eva_ps_fwd_skip   ; 74 36
                MOV     BX, DX                  ; 8B DA
                MOV     AL, es:[DI]             ; 26 8A 05
                MOV     DX, 03CFH               ; BA CF 03
                XCHG    AX, BP                  ; 95
                OUT     DX, AL                  ; EE
                MOV     AX, BP                  ; 8B C5
                MOV     BYTE PTR es:[DI], 0     ; 26 C6 05 00
                MOV     DX, 03C5H               ; BA C5 03
                MOV     AL, 01H                 ; B0 01
                OUT     DX, AL                  ; EE
                MOV     es:[DI], BH             ; 26 88 3D
                SHL     AL, 1                   ; D0 E0
                OUT     DX, AL                  ; EE
                MOV     es:[DI], BL             ; 26 88 1D
                SHL     AL, 1                   ; D0 E0
                OUT     DX, AL                  ; EE
                MOV     es:[DI], CH             ; 26 88 2D
                SHL     AL, 1                   ; D0 E0
                OUT     DX, AL                  ; EE
                MOV     es:[DI], CL             ; 26 88 0D
                MOV     BX, cs:[0D90H]          ; 2E 8B 1E 90 0D
                XOR     CX, CX                  ; 33 C9
                MOV     DX, CX                  ; 8B D1
                MOV     BP, CX                  ; 8B E9
eva_ps_fwd_skip:
                INC     DI                      ; 47
eva_ps_fwd_advance:
                DEC     WORD PTR cs:[0D84H]     ; 2E FF 0E 84 0D
                JNZ     SHORT eva_ps_fwd_loop   ; 75 8F
                OR      BP, BP                  ; 0B ED
                JZ      SHORT eva_ps_fwd_done   ; 74 42
                ; --- 0x119F: tail flush for forward path. Count remaining
                ; AH-mask rotations to align the partial pixel-pair group.
                MOV     AL, CL                  ; 8A C1
                MOV     CL, 00H                 ; B1 00
eva_ps_fwd_align:
                ADD     CL, 02H                 ; 80 C1 02
                ROR     AH, 1                   ; D0 CC
                ROR     AH, 1                   ; D0 CC
                JNC     SHORT eva_ps_fwd_align  ; 73 F7
                SHL     BP, CL                  ; D3 E5
                SHL     CH, CL                  ; D2 E5
                SHL     AL, CL                  ; D2 E0
                SHL     DX, CL                  ; D3 E2
                MOV     CL, AL                  ; 8A C8
                MOV     BX, DX                  ; 8B DA
                MOV     AL, es:[DI]             ; 26 8A 05
                MOV     DX, 03CFH               ; BA CF 03
                XCHG    AX, BP                  ; 95
                OUT     DX, AL                  ; EE
                MOV     AX, BP                  ; 8B C5
                MOV     BYTE PTR es:[DI], 0     ; 26 C6 05 00
                MOV     DX, 03C5H               ; BA C5 03
                MOV     AL, 01H                 ; B0 01
                OUT     DX, AL                  ; EE
                MOV     es:[DI], BH             ; 26 88 3D
                SHL     AL, 1                   ; D0 E0
                OUT     DX, AL                  ; EE
                MOV     es:[DI], BL             ; 26 88 1D
                SHL     AL, 1                   ; D0 E0
                OUT     DX, AL                  ; EE
                MOV     es:[DI], CH             ; 26 88 2D
                SHL     AL, 1                   ; D0 E0
                OUT     DX, AL                  ; EE
                MOV     es:[DI], CL             ; 26 88 0D
eva_ps_fwd_done:
                MOV     DX, 03C4H               ; BA C4 03
                MOV     AX, 0F02H               ; B8 02 0F
                OUT     DX, AX                  ; EF
                MOV     DX, 03CEH               ; BA CE 03
                MOV     AX, 0005H               ; B8 05 00
                OUT     DX, AX                  ; EF
                POP     BP                      ; 5D
                RETF                            ; CB
eva_ps_reverse:
                ; --- 0x11F1: reverse (DI--) path. Same skeleton as forward
                ; but uses RCR instead of RCL, ROL for the mask rotation,
                ; SHR-then-OR-with-0xC0 to recover the dropped phase bit.
                MOV     AX, 04E1H               ; B8 E1 04
                SHR     DX, 1                   ; D1 EA
                ADC     AH, 0                   ; 80 D4 00
                MOV     cs:[0D90H], AX          ; 2E A3 90 0D
                MOV     DX, 03CEH               ; BA CE 03
                MOV     AX, 0005H               ; B8 05 00
                OUT     DX, AX                  ; EF
                MOV     WORD PTR cs:[0D84H], CX ; 2E 89 0E 84 0D
                MOV     AL, 08H                 ; B0 08
                OUT     DX, AL                  ; EE
                MOV     DX, 03C4H               ; BA C4 03
                MOV     AL, 02H                 ; B0 02
                OUT     DX, AL                  ; EE
                MOV     CX, BX                  ; 8B CB
                AND     CX, 03H                 ; 83 E1 03
                SHL     CX, 1                   ; D1 E1
                MOV     AH, 0C0H                ; B4 C0
                SHR     AH, CL                  ; D2 EC
                SHR     BX, 1                   ; D1 EB
                SHR     BX, 1                   ; D1 EB
                ADD     DI, BX                  ; 03 FB
                MOV     BX, cs:[0D90H]          ; 2E 8B 1E 90 0D
                XOR     CX, CX                  ; 33 C9
                MOV     DX, CX                  ; 8B D1
                MOV     BP, CX                  ; 8B E9
eva_ps_rev_loop:
                LODSB                           ; AC
                XLAT    BYTE PTR CS:[BX]        ; 2E D7
                SHL     AL, 1                   ; D0 E0
                RCR     CL, 1                   ; D0 D9
                SHL     AL, 1                   ; D0 E0
                RCR     CH, 1                   ; D0 DD
                SHL     AL, 1                   ; D0 E0
                RCR     DL, 1                   ; D0 DA
                SHL     AL, 1                   ; D0 E0
                RCR     DH, 1                   ; D0 DE
                SHL     AL, 1                   ; D0 E0
                RCR     CL, 1                   ; D0 D9
                SHL     AL, 1                   ; D0 E0
                RCR     CH, 1                   ; D0 DD
                SHL     AL, 1                   ; D0 E0
                RCR     DL, 1                   ; D0 DA
                SHL     AL, 1                   ; D0 E0
                RCR     DH, 1                   ; D0 DE
                SHR     BP, 1                   ; D1 ED
                SHR     BP, 1                   ; D1 ED
                OR      BP, 0C0H                ; 81 CD C0 00
                ROL     AH, 1                   ; D0 C4
                ROL     AH, 1                   ; D0 C4
                JNC     SHORT eva_ps_rev_advance ; 73 3B
                OR      BP, BP                  ; 0B ED
                JZ      SHORT eva_ps_rev_skip   ; 74 36
                MOV     BX, DX                  ; 8B DA
                MOV     AL, es:[DI]             ; 26 8A 05
                MOV     DX, 03CFH               ; BA CF 03
                XCHG    AX, BP                  ; 95
                OUT     DX, AL                  ; EE
                MOV     AX, BP                  ; 8B C5
                MOV     BYTE PTR es:[DI], 0     ; 26 C6 05 00
                MOV     DX, 03C5H               ; BA C5 03
                MOV     AL, 01H                 ; B0 01
                OUT     DX, AL                  ; EE
                MOV     es:[DI], BH             ; 26 88 3D
                SHL     AL, 1                   ; D0 E0
                OUT     DX, AL                  ; EE
                MOV     es:[DI], BL             ; 26 88 1D
                SHL     AL, 1                   ; D0 E0
                OUT     DX, AL                  ; EE
                MOV     es:[DI], CH             ; 26 88 2D
                SHL     AL, 1                   ; D0 E0
                OUT     DX, AL                  ; EE
                MOV     es:[DI], CL             ; 26 88 0D
                MOV     BX, cs:[0D90H]          ; 2E 8B 1E 90 0D
                XOR     CX, CX                  ; 33 C9
                MOV     DX, CX                  ; 8B D1
                MOV     BP, CX                  ; 8B E9
eva_ps_rev_skip:
                DEC     DI                      ; 4F
eva_ps_rev_advance:
                DEC     WORD PTR cs:[0D84H]     ; 2E FF 0E 84 0D
                JNZ     SHORT eva_ps_rev_loop   ; 75 8D
                OR      BP, BP                  ; 0B ED
                JZ      SHORT eva_ps_rev_done   ; 74 42
                MOV     AL, CL                  ; 8A C1
                MOV     CL, 00H                 ; B1 00
eva_ps_rev_align:
                ADD     CL, 02H                 ; 80 C1 02
                ROL     AH, 1                   ; D0 C4
                ROL     AH, 1                   ; D0 C4
                JNC     SHORT eva_ps_rev_align  ; 73 F7
                SHR     BP, CL                  ; D3 ED
                SHR     CH, CL                  ; D2 ED
                SHR     AL, CL                  ; D2 E8
                SHR     DX, CL                  ; D3 EA
                MOV     CL, AL                  ; 8A C8
                MOV     BX, DX                  ; 8B DA
                MOV     AL, es:[DI]             ; 26 8A 05
                MOV     DX, 03CFH               ; BA CF 03
                XCHG    AX, BP                  ; 95
                OUT     DX, AL                  ; EE
                MOV     AX, BP                  ; 8B C5
                MOV     BYTE PTR es:[DI], 0     ; 26 C6 05 00
                MOV     DX, 03C5H               ; BA C5 03
                MOV     AL, 01H                 ; B0 01
                OUT     DX, AL                  ; EE
                MOV     es:[DI], BH             ; 26 88 3D
                SHL     AL, 1                   ; D0 E0
                OUT     DX, AL                  ; EE
                MOV     es:[DI], BL             ; 26 88 1D
                SHL     AL, 1                   ; D0 E0
                OUT     DX, AL                  ; EE
                MOV     es:[DI], CH             ; 26 88 2D
                SHL     AL, 1                   ; D0 E0
                OUT     DX, AL                  ; EE
                MOV     es:[DI], CL             ; 26 88 0D
eva_ps_rev_done:
                MOV     DX, 03C4H               ; BA C4 03
                MOV     AX, 0F02H               ; B8 02 0F
                OUT     DX, AX                  ; EF
                MOV     DX, 03CEH               ; BA CE 03
                MOV     AX, 0005H               ; B8 05 00
                OUT     DX, AX                  ; EF
                POP     BP                      ; 5D
                RETF                            ; CB
eva_palette_set ENDP

; ============================================================================
; eva_rect_save -- pack one screen pixel (planar -> 8-bit chunky).
; chunk:0x12F7..0x139D  (167 bytes; vtable slot 20).
;
; The inherited plate name is "rect_save" but this is
; really a single-pixel sampler shape (similar shape to eva_get_pixel
; @ 0x1D66 -- 8 bits of pixel value packed from 4 planes via 0x55/0xAA
; interleave masks, returned in AX).
;
; ABI (__cdecl16far, vtable slot):
;   [BP+06]  ushort  x-position (chunky pixel x; low 2 bits -> bit-pair)
;   [BP+08]  ushort  y-row (index into table at DS:[6F2] = row-start LUT)
; Returns:
;   AX       packed dither byte (4 planes x 2-pixel-pairs -> 8 bits)
;
; Globals touched:
;   cs:[00B2]  data segment paragraphs (chunk-local DS)
;   DS:[0016]  shadow framebuffer segment (chunky-side)
;   DS:[06F2]  row-offset LUT (200 words, one per scanline)
; ============================================================================
eva_rect_save PROC FAR
                PUSH    BP                      ; 55
                MOV     BP, SP                  ; 8B EC
                PUSH    DS                      ; 1E
                PUSH    SI                      ; 56
                MOV     DS, cs:[00B2H]          ; 2E 8E 1E B2 00
                MOV     AX, ds:[GfxContext.wGfxBlitSrcPage] ; A1 16 00
                MOV     ES, AX                  ; 8E C0
                MOV     BX, [BP+8]              ; 8B 5E 08    ; y
                SHL     BX, 1                   ; D1 E3
                MOV     SI, [BX].GfxContext.pRow_offset_lut ; 8B B7 F2 06
                MOV     AX, [BP+6]              ; 8B 46 06    ; x
                MOV     CX, AX                  ; 8B C8
                SHR     AX, 1                   ; D1 E8
                SHR     AX, 1                   ; D1 E8
                ADD     SI, AX                  ; 03 F0
                ; --- 0x131A: program GC index 5 mode 0 + index 4 plane 0.
                MOV     DX, 03CEH               ; BA CE 03
                MOV     AX, 0005H               ; B8 05 00
                OUT     DX, AX                  ; EF
                MOV     AX, 0004H               ; B8 04 00    ; index 4 = read map select
                OUT     DX, AX                  ; EF
                INC     DX                      ; 42          ; -> 03CF data port
                MOV     BX, 0AA55H              ; BB 55 AA    ; bit-interleave masks
                MOV     AH, 0C0H                ; B4 C0       ; 2-pixel-pair mask seed
                AND     CL, 03H                 ; 80 E1 03
                SHL     AL, 1                   ; D0 E0       ; pad; AL doesn't matter here
                SHR     AH, CL                  ; D2 EC
                XOR     CX, CX                  ; 33 C9       ; CL = packed result accum
                ; --- 0x1334: plane 0 sample.
                MOV     AL, es:[SI]             ; 26 8A 04
                TEST    AH, AL                  ; 84 E0
                JZ      SHORT eva_rs_pl1        ; 74 0E
                TEST    AL, BL                  ; 84 C3
                JZ      SHORT eva_rs_p0_hi      ; 74 03
                OR      CL, 01H                 ; 80 C9 01
eva_rs_p0_hi:
                TEST    AL, BH                  ; 84 C7
                JZ      SHORT eva_rs_pl1        ; 74 03
                OR      CL, 02H                 ; 80 C9 02
eva_rs_pl1:
                MOV     AL, 01H                 ; B0 01       ; plane 1 select
                OUT     DX, AL                  ; EE
                MOV     AL, es:[SI]             ; 26 8A 04
                TEST    AH, AL                  ; 84 E0
                JZ      SHORT eva_rs_pl2        ; 74 0E
                TEST    AL, BL                  ; 84 C3
                JZ      SHORT eva_rs_p1_hi      ; 74 03
                OR      CL, 04H                 ; 80 C9 04
eva_rs_p1_hi:
                TEST    AL, BH                  ; 84 C7
                JZ      SHORT eva_rs_pl2        ; 74 03
                OR      CL, 08H                 ; 80 C9 08
eva_rs_pl2:
                MOV     AL, 02H                 ; B0 02       ; plane 2 select
                OUT     DX, AL                  ; EE
                MOV     AL, es:[SI]             ; 26 8A 04
                TEST    AH, AL                  ; 84 E0
                JZ      SHORT eva_rs_pl3        ; 74 0E
                TEST    AL, BL                  ; 84 C3
                JZ      SHORT eva_rs_p2_hi      ; 74 03
                OR      CL, 10H                 ; 80 C9 10
eva_rs_p2_hi:
                TEST    AL, BH                  ; 84 C7
                JZ      SHORT eva_rs_pl3        ; 74 03
                OR      CL, 20H                 ; 80 C9 20
eva_rs_pl3:
                MOV     AL, 03H                 ; B0 03       ; plane 3 select
                OUT     DX, AL                  ; EE
                MOV     AL, es:[SI]             ; 26 8A 04
                TEST    AH, AL                  ; 84 E0
                JZ      SHORT eva_rs_done       ; 74 0E
                TEST    AL, BL                  ; 84 C3
                JZ      SHORT eva_rs_p3_hi      ; 74 03
                OR      CL, 40H                 ; 80 C9 40
eva_rs_p3_hi:
                TEST    AL, BH                  ; 84 C7
                JZ      SHORT eva_rs_done       ; 74 03
                OR      CL, 80H                 ; 80 C9 80
eva_rs_done:
                DEC     DX                      ; 4A          ; -> 03CE index port
                MOV     AX, 0005H               ; B8 05 00
                OUT     DX, AX                  ; EF
                MOV     AX, CX                  ; 8B C1
                POP     SI                      ; 5E
                POP     DS                      ; 1F
                MOV     SP, BP                  ; 8B E5
                POP     BP                      ; 5D
                RETF                            ; CB
eva_rect_save ENDP

; ============================================================================
; eva_rect_paste -- single-pixel writeback to the framebuffer.
; chunk:0x139E..0x1409  (108 bytes; vtable slot 21).
;
; Mirror of eva_rect_save: takes a packed dither byte from [BP+0Ah] and
; writes it back into the 4-plane EGA framebuffer. The XLAT through one
; of the two 256-byte bit-spread LUTs (chosen by parity of y) translates
; the packed byte back to a 4-plane bit pattern, then a Mode-2 (set/reset
; mask) write through GC index 8 paints the target pixel pair.
;
; ABI (__cdecl16far, vtable slot):
;   [BP+06]  ushort  x-position
;   [BP+08]  ushort  y-row
;   [BP+0A]  uchar   packed dither byte (from a prior eva_rect_save)
;
; Globals touched:
;   cs:[00B2]  data segment paragraphs
;   DS:[0018]  framebuffer segment (planar side)
;   DS:[06F2]  row-offset LUT
;   cs:[04E1]  even bit-spread LUT (low half indexed by parity)
; ============================================================================
eva_rect_paste PROC FAR
                PUSH    BP                      ; 55
                MOV     BP, SP                  ; 8B EC
                PUSH    DS                      ; 1E
                MOV     DS, cs:[00B2H]          ; 2E 8E 1E B2 00
                MOV     ES, ds:[GfxContext.wGfxBlitDstPage] ; 8E 06 18 00
                MOV     BX, [BP+8]              ; 8B 5E 08
                SHL     BX, 1                   ; D1 E3
                MOV     BX, [BX].GfxContext.pRow_offset_lut ; 8B 9F F2 06
                MOV     AX, [BP+6]              ; 8B 46 06
                MOV     CX, AX                  ; 8B C8
                SHR     AX, 1                   ; D1 E8
                SHR     AX, 1                   ; D1 E8
                ADD     BX, AX                  ; 03 D8
                AND     CX, 03H                 ; 83 E1 03
                MOV     DX, 03CEH               ; BA CE 03
                MOV     AX, 0205H               ; B8 05 02   ; index 5 mode 2
                OUT     DX, AX                  ; EF
                MOV     AH, 80H                 ; B4 80
                SHL     CL, 1                   ; D0 E1
                SHR     AH, CL                  ; D2 EC
                MOV     AL, 08H                 ; B0 08      ; index 8 bit-mask
                OUT     DX, AX                  ; EF
                INC     DX                      ; 42         ; -> 03CF
                MOV     AL, es:[BX]             ; 26 8A 07   ; latch fetch
                MOV     AL, [BP+0AH]            ; 8A 46 0A   ; the packed dither byte
                MOV     CX, BX                  ; 8B CB
                MOV     BH, [BP+8]              ; 8A 7E 08   ; y low byte (phase)
                AND     BX, 0100H               ; 81 E3 00 01
                ADD     BX, 04E1H               ; 81 C3 E1 04
                XLAT    BYTE PTR CS:[BX]        ; 2E D7
                MOV     BX, CX                  ; 8B D9
                MOV     es:[BX], AL             ; 26 88 07
                SHR     AH, 1                   ; D0 EC
                XCHG    AL, AH                  ; 86 C4      ; Borland AL-first form
                OUT     DX, AL                  ; EE
                SHR     AH, 1                   ; D0 EC
                SHR     AH, 1                   ; D0 EC
                SHR     AH, 1                   ; D0 EC
                SHR     AH, 1                   ; D0 EC
                MOV     AL, es:[BX]             ; 26 8A 07
                MOV     es:[BX], AH             ; 26 88 27
                DEC     DX                      ; 4A
                MOV     AX, 0005H               ; B8 05 00
                OUT     DX, AX                  ; EF
                POP     DS                      ; 1F
                MOV     SP, BP                  ; 8B E5
                POP     BP                      ; 5D
                RETF                            ; CB
eva_rect_paste ENDP

; ============================================================================
; eva_line -- block-copy a planar rect from system memory to the framebuffer.
; chunk:0x140A..0x1480  (119 bytes; vtable slot 4).
;
; Despite the name, the
; shape is a 4-plane planar-blit loop, not a line draw. It uses GC index 5
; mode 0 + index 8 bit-mask 0xFF for an unmodified store, then iterates
; over 4 planes (AH counts down from 3) and `count` rows, REP MOVSW for
; each row. Real line drawing lives in eva_draw_line @ 0x1AF9 (slot 12).
;
; ABI (__cdecl16far, vtable slot):
;   [BP+06]  ushort  dst_off       (ES:DI target)
;   [BP+08]  ushort  dst_seg
;   [BP+0A]  ushort  x_start_px    (chunky x, used to compute width words)
;   [BP+0C]  ushort  y_top         (row index into [DS:6F2])
;   [BP+0E]  ushort  x_end_px      (computed against x_start_px for word count)
;   [BP+10]  ushort  row_count     (rows in the rect)
;
; Globals touched:
;   cs:[00B2]  data segment paragraphs
;   DS:[0016]  shadow framebuffer segment (source side)
;   DS:[06F2]  row-offset LUT
; ============================================================================
eva_line PROC FAR
                PUSH    BP                      ; 55
                MOV     BP, SP                  ; 8B EC
                PUSH    SI                      ; 56
                PUSH    DI                      ; 57
                PUSH    DS                      ; 1E
                MOV     DS, cs:[00B2H]          ; 2E 8E 1E B2 00
                MOV     DX, 03CEH               ; BA CE 03
                MOV     AX, 0FF08H              ; B8 08 FF      ; bit-mask = all bits
                OUT     DX, AX                  ; EF
                MOV     DI, [BP+6]              ; 8B 7E 06
                MOV     ES, [BP+8]              ; 8E 46 08
                MOV     CX, [BP+0AH]            ; 8B 4E 0A
                MOV     AX, CX                  ; 8B C1
                SHR     CX, 1                   ; D1 E9
                SHR     CX, 1                   ; D1 E9
                MOV     BX, [BP+0EH]            ; 8B 5E 0E
                ADD     BX, AX                  ; 03 D8
                SHR     BX, 1                   ; D1 EB
                SHR     BX, 1                   ; D1 EB
                SUB     BX, CX                  ; 2B D9
                INC     BX                      ; 43
                MOV     AX, BX                  ; 8B C3
                SHR     BX, 1                   ; D1 EB
                AND     AX, 01H                 ; 25 01 00
                JZ      SHORT eva_line_even     ; 74 01
                INC     BX                      ; 43
eva_line_even:
                MOV     DX, [BP+10H]            ; 8B 56 10      ; row_count
                MOV     SI, [BP+0CH]            ; 8B 76 0C
                SHL     SI, 1                   ; D1 E6
                MOV     SI, [SI].GfxContext.pRow_offset_lut ; 8B B4 F2 06
                ADD     SI, CX                  ; 03 F1
                MOV     AX, ds:[GfxContext.wGfxBlitSrcPage] ; A1 16 00
                MOV     DS, AX                  ; 8E D8         ; DS = src fb seg
                MOV     AX, 0304H               ; B8 04 03      ; index 4 plane 3 (loop start)
eva_line_plane:
                MOV     BP, DX                  ; 8B EA
                MOV     DX, 03CEH               ; BA CE 03
                OUT     DX, AX                  ; EF
                MOV     DX, BP                  ; 8B D5
                PUSH    DX                      ; 52
                PUSH    SI                      ; 56
eva_line_row:
                MOV     CX, BX                  ; 8B CB
                MOV     BP, SI                  ; 8B EE
                REP MOVSW                       ; F3 A5
                MOV     SI, BP                  ; 8B F5
                ADD     SI, 50H                 ; 83 C6 50      ; 80 bytes/row in EGA
                DEC     DX                      ; 4A
                JNZ     SHORT eva_line_row      ; 75 F2
                POP     SI                      ; 5E
                POP     DX                      ; 5A
                DEC     AH                      ; FE CC
                JGE     SHORT eva_line_plane    ; 7D E2
                MOV     DX, 03CEH               ; BA CE 03
                MOV     AX, 0F04H               ; B8 04 0F
                OUT     DX, AX                  ; EF
                POP     DS                      ; 1F
                POP     DI                      ; 5F
                POP     SI                      ; 5E
                POP     BP                      ; 5D
                RETF                            ; CB
eva_line ENDP

; ============================================================================
; eva_sprite_buffer_size -- buffer-byte-count for a w x h EGA sprite frame.
; chunk:0x1481..0x14A8  (40 bytes; vtable slot 5).
;
; Returns DX:AX = ceil(w / 8) * h * 8  -- a long that callers use to size
; a "save under" buffer big enough to hold (width-in-bytes rounded up) x
; (height) x (4 planes x 2 for safety, hence the three SHL/RCL after the
; 16x16 multiply).
;
; ABI (__cdecl16far, vtable slot):
;   [BP+06]  ushort  width_in_pixels
;   [BP+08]  ushort  height_in_rows
; Returns:
;   DX:AX    32-bit byte count
; ============================================================================
eva_sprite_buffer_size PROC FAR
                PUSH    BP                      ; 55
                MOV     BP, SP                  ; 8B EC
                MOV     AX, [BP+6]              ; 8B 46 06
                MOV     BX, AX                  ; 8B D8
                SHR     BX, 1                   ; D1 EB
                SHR     BX, 1                   ; D1 EB
                SHR     BX, 1                   ; D1 EB
                INC     BX                      ; 43
                AND     AX, 07H                 ; 25 07 00
                JZ      SHORT eva_sbs_aligned   ; 74 01
                INC     BX                      ; 43
eva_sbs_aligned:
                MOV     AX, [BP+8]              ; 8B 46 08
                MUL     BX                      ; F7 E3
                SHL     AX, 1                   ; D1 E0
                RCL     DX, 1                   ; D1 D2
                SHL     AX, 1                   ; D1 E0
                RCL     DX, 1                   ; D1 D2
                SHL     AX, 1                   ; D1 E0
                RCL     DX, 1                   ; D1 D2
                POP     BP                      ; 5D
                RETF                            ; CB
eva_sprite_buffer_size ENDP

; ----------------------------------------------------------------------------
; 0x14A9..0x14BF -- inter-function padding + small data island.
;
;   0x14A9..0x14B6  14 bytes of zero padding (scratch / 0-init data).
;   0x14B7..0x14BE  4 little-endian words: 0x1665, 0x1768, 0x186B, 0x196E.
;                   These are near pointers (each +0x103) into the body of
;                   eva_blit_sprite_master @ 0x14C0 -- the function's own
;                   internal-dispatch jump table for the 4 flip-flag cases
;                   (noflip / vflip / hflip / vhflip). The table lives at
;                   the function's "header" because the entry-point's MOV
;                   BL,...; SHL BL,1; JMP cs:[BX+0x14B7] resolves them.
;   0x14BF          1 byte zero -- alignment pad before 0x14C0 entry.
; ----------------------------------------------------------------------------
                DB      14 DUP (0)              ; 0x14A9..0x14B6
g_apfnEvaBlitSpriteMasterCases:
                DW      1665H                   ; case 0 -- noflip
                DW      1768H                   ; case 1 -- vflip
                DW      186BH                   ; case 2 -- hflip
                DW      196EH                   ; case 3 -- vhflip
                DB      0                       ; 0x14BF align pad

; ============================================================================
; eva_blit_sprite_master -- top-level sprite blitter with flip flags & clip.
; chunk:0x14C0..0x1A7C  (1469 bytes; vtable slot 28).
;
; Reads flip flags from [BP+0Ch] (bit0=H-flip, bit1=V-flip), clips against
; screen bounds (DS:[0x4]/[0x6]/[0x8]/[0xA]), then dispatches via a
; computed JMP AX through a 4-entry table at 0x14B7
; (g_apfnEvaBlitSpriteMasterCases). Targets:
;   [0] 0x1665  noflip   (LODSB forward, INC SI, +0x50 row advance)
;   [1] 0x1768  hflip    (column mirror via XCHG-driven byte order)
;   [2] 0x186B  vflip    (LODSB reverse, DEC SI, +0x50 row advance)
;   [3] 0x196E  hvflip   (both)
; All four cores fall through to the shared epilogue at 0x1A6E.
;
; The dense switch needed a manual jump-table override during RE
; (computed-jump targets at 0x1663).
;
; ABI (__cdecl16far, vtable slot):
;   [BP+06]  ushort  sprite_desc_off  (-> 10-byte frame descriptor copied
;                    to SS-local [BP-0Ah..BP-1])
;   [BP+08]  ushort  dst_x
;   [BP+0A]  ushort  dst_y
;   [BP+0C]  ushort  flip_flags / sprite_height etc. (bit0=hflip, bit1=vflip)
;
; Per-blitter scratch globals (mutated each call):
;   cs:[14A9]  word   row counter
;   cs:[14AB]  word   per-row pixel-pair counter
;   cs:[14AF]  word   row pixel count (master copy)
;   cs:[14B1]  word   row-phase sign (+/-256), flips each row
;   cs:[14B3]  word   active LUT base (0x4E1 + phase)
;   cs:[14B5]  word   per-row src advance step (signed)
;   cs:[14BF]  byte   start-pixel mask (0x80/0x40/0x20/0x10 by x&3)
; ============================================================================
eva_blit_sprite_master PROC FAR
                PUSH    BP                      ; 55
                MOV     BP, SP                  ; 8B EC
                SUB     SP, 0AH                 ; 83 EC 0A
                PUSH    DI                      ; 57
                PUSH    SI                      ; 56
                PUSH    ES                      ; 06
                PUSH    DS                      ; 1E
                MOV     DX, 03CEH               ; BA CE 03
                MOV     AX, 0005H               ; B8 05 00      ; GC mode 0
                OUT     DX, AX                  ; EF
                MOV     AX, 0FF08H              ; B8 08 FF      ; bit-mask 0xFF
                OUT     DX, AX                  ; EF
                ; --- 0x14D5: REP MOVSW copy of the 10-byte sprite frame
                ; descriptor from caller-supplied DS:SI to SS:BP-0xA.
                MOV     SI, [BP+6]              ; 8B 76 06
                MOV     DI, BP                  ; 8B FD
                SUB     DI, 0AH                 ; 83 EF 0A
                MOV     AX, SS                  ; 8C D0
                MOV     ES, AX                  ; 8E C0
                MOV     CX, 05H                 ; B9 05 00
                REP MOVSW                       ; F3 A5
                MOV     DS, cs:[00B2H]          ; 2E 8E 1E B2 00
                MOV     SI, [BP-8]              ; 8B 76 F8     ; sprite pixel ptr (desc word 1)
                MOV     WORD PTR cs:[14B5H], 0  ; 2E C7 06 B5 14 00 00
                ; --- 0x14F5: handle V-flip pre-bias.
                TEST    BYTE PTR [BP+0CH], 02H  ; F6 46 0C 02
                JZ      SHORT eva_bsm_no_vflip  ; 74 0E
                MOV     AX, [BP-4]              ; 8B 46 FC
                ADD     SI, AX                  ; 03 F0
                SHL     AX, 1                   ; D1 E0
                NEG     AX                      ; F7 D8
                MOV     cs:[14B5H], AX          ; 2E A3 B5 14
                DEC     SI                      ; 4E
eva_bsm_no_vflip:
                ; --- 0x1509: handle H-flip pre-bias.
                TEST    BYTE PTR [BP+0CH], 01H  ; F6 46 0C 01
                JZ      SHORT eva_bsm_no_hflip  ; 74 1F
                MOV     AX, [BP-4]              ; 8B 46 FC
                MUL     WORD PTR [BP-2]         ; F7 66 FE
                SUB     AX, [BP-4]              ; 2B 46 FC
                ADD     SI, AX                  ; 03 F0
                MOV     AX, [BP-4]              ; 8B 46 FC
                SHL     AX, 1                   ; D1 E0
                TEST    BYTE PTR [BP+0CH], 02H  ; F6 46 0C 02
                JZ      SHORT eva_bsm_hflip_no_v ; 74 02
                NEG     AX                      ; F7 D8
eva_bsm_hflip_no_v:
                SUB     WORD PTR cs:[14B5H], AX ; 2E 29 06 B5 14
                MOV     DX, AX                  ; 8B D0
eva_bsm_no_hflip:
                ; --- 0x152E: compute initial DI = row-base + (x>>2).
                MOV     DI, [BP+0AH]            ; 8B 7E 0A
                SHL     DI, 1                   ; D1 E7
                MOV     DI, [DI].GfxContext.pRow_offset_lut ; 8B BD F2 06
                MOV     AX, [BP+8]              ; 8B 46 08
                MOV     CX, AX                  ; 8B C8
                AND     CX, 03H                 ; 83 E1 03
                SHR     AX, 1                   ; D1 E8
                SHR     AX, 1                   ; D1 E8
                ADD     DI, AX                  ; 03 F8
                MOV     AH, 80H                 ; B4 80
                SHL     CL, 1                   ; D0 E1
                SHR     AH, CL                  ; D2 EC
                MOV     cs:[14BFH], AH          ; 2E 88 26 BF 14
                MOV     AX, [BP-2]              ; 8B 46 FE
                MOV     cs:[14A9H], AX          ; 2E A3 A9 14
                MOV     AX, [BP-4]              ; 8B 46 FC
                MOV     cs:[14AFH], AX          ; 2E A3 AF 14
                ; --- 0x155E: check clip-enable byte at DS:[3].
                MOV     AL, ds:[GfxContext.bClip_enabled] ; A0 03 00
                XOR     BX, BX                  ; 33 DB
                OR      AL, AL                  ; 0A C0
                JNZ     SHORT eva_bsm_clip      ; 75 03
                JMP     eva_bsm_dispatch        ; E9 D7 00
eva_bsm_clip:
                ; --- 0x156A: clip right edge against DS:[6]+1.
                MOV     AX, ds:[GfxContext.nClip_xmax] ; A1 06 00
                INC     AX                      ; 40
                SUB     AX, [BP+8]              ; 2B 46 08
                SUB     AX, [BP-4]              ; 2B 46 FC
                JNS     SHORT eva_bsm_clip_top  ; 79 11
                NEG     AX                      ; F7 D8
                ADD     cs:[14B5H], AX          ; 2E 01 06 B5 14
                SUB     cs:[14AFH], AX          ; 2E 29 06 AF 14
                JNS     SHORT eva_bsm_clip_top  ; 79 03
                JMP     eva_bsm_done            ; E9 E7 04
eva_bsm_clip_top:
                ; --- 0x1587: clip bottom against DS:[A].
                MOV     AX, ds:[GfxContext.nClip_ymax] ; A1 0A 00
                SUB     AX, [BP+0AH]            ; 2B 46 0A
                SUB     AX, cs:[14A9H]          ; 2E 2B 06 A9 14
                JNS     SHORT eva_bsm_clip_left ; 79 0D
                NEG     AX                      ; F7 D8
                DEC     AX                      ; 48
                SUB     cs:[14A9H], AX          ; 2E 29 06 A9 14
                JA      SHORT eva_bsm_clip_left ; 77 03
                JMP     eva_bsm_done            ; E9 CD 04
eva_bsm_clip_left:
                ; --- 0x15A1: clip top against DS:[8].
                MOV     AX, ds:[GfxContext.nClip_ymin] ; A1 08 00
                SUB     AX, [BP+0AH]            ; 2B 46 0A
                JLE     SHORT eva_bsm_left      ; 7E 47
                SUB     cs:[14A9H], AX          ; 2E 29 06 A9 14
                XOR     DX, DX                  ; 33 D2
                MUL     WORD PTR [BP-4]         ; F7 66 FC
                TEST    BYTE PTR [BP+0CH], 01H  ; F6 46 0C 01
                JZ      SHORT eva_bsm_top_skip  ; 74 02
                NEG     AX                      ; F7 D8
eva_bsm_top_skip:
                ADD     SI, AX                  ; 03 F0
                MOV     DI, ds:[GfxContext.nClip_ymin] ; 8B 3E 08 00
                SHL     DI, 1                   ; D1 E7
                MOV     DI, [DI].GfxContext.pRow_offset_lut ; 8B BD F2 06
                MOV     AX, [BP+8]              ; 8B 46 08
                MOV     CX, AX                  ; 8B C8
                AND     CX, 03H                 ; 83 E1 03
                SHR     AX, 1                   ; D1 E8
                SHR     AX, 1                   ; D1 E8
                ADD     DI, AX                  ; 03 F8
                MOV     AH, 80H                 ; B4 80
                SHL     CL, 1                   ; D0 E1
                SHR     AH, CL                  ; D2 EC
                MOV     cs:[14BFH], AH          ; 2E 88 26 BF 14
                MOV     AX, cs:[14A9H]          ; 2E A1 A9 14
                OR      AX, AX                  ; 0B C0
                JNZ     SHORT eva_bsm_top_ok    ; 75 03
                JMP     eva_bsm_done            ; E9 83 04
eva_bsm_top_ok:
                JNS     SHORT eva_bsm_left      ; 79 03
                JMP     eva_bsm_done            ; E9 7E 04
eva_bsm_left:
                ; --- 0x15F0: clip left against DS:[4].
                MOV     AX, ds:[GfxContext.nClip_xmin] ; A1 04 00
                SUB     AX, [BP+8]              ; 2B 46 08
                JLE     SHORT eva_bsm_dispatch  ; 7E 49
                MOV     DI, [BP+0AH]            ; 8B 7E 0A
                CMP     DI, ds:[GfxContext.nClip_ymin] ; 3B 3E 08 00
                JG      SHORT eva_bsm_left_clamp ; 7F 04
                MOV     DI, ds:[GfxContext.nClip_ymin] ; 8B 3E 08 00
eva_bsm_left_clamp:
                SHL     DI, 1                   ; D1 E7
                MOV     DI, [DI].GfxContext.pRow_offset_lut ; 8B BD F2 06
                MOV     BX, ds:[GfxContext.nClip_xmin] ; 8B 1E 04 00
                MOV     CX, BX                  ; 8B CB
                SHR     BX, 1                   ; D1 EB
                SHR     BX, 1                   ; D1 EB
                ADD     DI, BX                  ; 03 FB
                PUSH    AX                      ; 50
                MOV     AL, 80H                 ; B0 80
                AND     CL, 03H                 ; 80 E1 03
                SHL     CX, 1                   ; D1 E1
                SHR     AL, CL                  ; D2 E8
                MOV     cs:[14BFH], AL          ; 2E A2 BF 14
                POP     AX                      ; 58
                TEST    BYTE PTR [BP+0CH], 02H  ; F6 46 0C 02
                JZ      SHORT eva_bsm_left_post ; 74 04
                SUB     SI, AX                  ; 2B F0
                SUB     SI, AX                  ; 2B F0
eva_bsm_left_post:
                ADD     SI, AX                  ; 03 F0
                ADD     cs:[14B5H], AX          ; 2E 01 06 B5 14
                SUB     cs:[14AFH], AX          ; 2E 29 06 AF 14
                JA      SHORT eva_bsm_dispatch  ; 77 03
                JMP     eva_bsm_done            ; E9 2D 04
eva_bsm_dispatch:
                ; --- 0x1641: load ES = host_callbacks (saved at [BP-0Ah]
                ; word), DS = framebuffer planar seg (DS:[18]), seed the
                ; LUT base (0x14B3 = 0x4E1) and the phase (0x14B1 = 0x100),
                ; then JMP through the 4-entry case table at 0x14B7.
                MOV     ES, [BP-0AH]            ; 8E 46 F6
                MOV     DS, ds:[GfxContext.wGfxBlitDstPage] ; 8E 1E 18 00
                MOV     AX, 04E1H               ; B8 E1 04
                MOV     cs:[14B3H], AX          ; 2E A3 B3 14
                MOV     WORD PTR cs:[14B1H], 0100H ; 2E C7 06 B1 14 00 01
                MOV     BX, [BP+0CH]            ; 8B 5E 0C
                AND     BX, 03H                 ; 83 E3 03
                SHL     BX, 1                   ; D1 E3
                MOV     AX, cs:[BX+14B7H]       ; 2E 8B 87 B7 14
                JMP     AX                      ; FF E0
; ----------------------------------------------------------------------------
; --- 0x1665: eva_sprite_row_noflip -- LODSB forward, INC SI, +0x50 row.
; ----------------------------------------------------------------------------
eva_sprite_row_noflip:
                PUSH    DI                      ; 57
                MOV     AX, cs:[14AFH]          ; 2E A1 AF 14
                MOV     cs:[14ABH], AX          ; 2E A3 AB 14
                MOV     AH, cs:[14BFH]          ; 2E 8A 26 BF 14
                MOV     BX, cs:[14B3H]          ; 2E 8B 1E B3 14
                XOR     CX, CX                  ; 33 C9
                MOV     DX, CX                  ; 8B D1
                MOV     BP, CX                  ; 8B E9
eva_bsm_nfl_loop:
                MOV     AL, es:[SI]             ; 26 8A 04
                INC     SI                      ; 46
                OR      AL, AL                  ; 0A C0
                JZ      SHORT eva_bsm_nfl_skip  ; 74 6C
                XLAT    BYTE PTR CS:[BX]        ; 2E D7
                SHL     AL, 1                   ; D0 E0
                RCL     CL, 1                   ; D0 D1
                SHL     AL, 1                   ; D0 E0
                RCL     CH, 1                   ; D0 D5
                SHL     AL, 1                   ; D0 E0
                RCL     DL, 1                   ; D0 D2
                SHL     AL, 1                   ; D0 E0
                RCL     DH, 1                   ; D0 D6
                SHL     AL, 1                   ; D0 E0
                RCL     CL, 1                   ; D0 D1
                SHL     AL, 1                   ; D0 E0
                RCL     CH, 1                   ; D0 D5
                SHL     AL, 1                   ; D0 E0
                RCL     DL, 1                   ; D0 D2
                SHL     AL, 1                   ; D0 E0
                RCL     DH, 1                   ; D0 D6
                STC                             ; F9
                RCL     BP, 1                   ; D1 D5
                STC                             ; F9
                RCL     BP, 1                   ; D1 D5
                ROR     AH, 1                   ; D0 CC
                ROR     AH, 1                   ; D0 CC
                JNC     SHORT eva_bsm_nfl_adv   ; 73 37
eva_bsm_nfl_or_bp:
                OR      BP, BP                  ; 0B ED
                JZ      SHORT eva_bsm_nfl_inc   ; 74 32
                MOV     BX, DX                  ; 8B DA
                MOV     AL, [DI]                ; 8A 05
                MOV     DX, 03CFH               ; BA CF 03
                XCHG    AX, BP                  ; 95
                OUT     DX, AL                  ; EE
                MOV     AX, BP                  ; 8B C5
                MOV     BYTE PTR [DI], 0        ; C6 05 00
                MOV     DX, 03C5H               ; BA C5 03
                MOV     AL, 01H                 ; B0 01
                OUT     DX, AL                  ; EE
                MOV     [DI], BH                ; 88 3D
                SHL     AL, 1                   ; D0 E0
                OUT     DX, AL                  ; EE
                MOV     [DI], BL                ; 88 1D
                SHL     AL, 1                   ; D0 E0
                OUT     DX, AL                  ; EE
                MOV     [DI], CH                ; 88 2D
                SHL     AL, 1                   ; D0 E0
                OUT     DX, AL                  ; EE
                MOV     [DI], CL                ; 88 0D
                MOV     BX, cs:[14B3H]          ; 2E 8B 1E B3 14
                XOR     CX, CX                  ; 33 C9
                MOV     DX, CX                  ; 8B D1
                MOV     BP, CX                  ; 8B E9
eva_bsm_nfl_inc:
                INC     DI                      ; 47
eva_bsm_nfl_adv:
                DEC     WORD PTR cs:[14ABH]     ; 2E FF 0E AB 14
                JNZ     SHORT eva_bsm_nfl_loop  ; 75 8E
                JMP     SHORT eva_bsm_nfl_fin   ; EB 1C
eva_bsm_nfl_skip:
                SHL     BP, 1                   ; D1 E5
                SHL     BP, 1                   ; D1 E5
                SHL     CX, 1                   ; D1 E1
                SHL     CX, 1                   ; D1 E1
                SHL     DX, 1                   ; D1 E2
                SHL     DX, 1                   ; D1 E2
                ROR     AH, 1                   ; D0 CC
                ROR     AH, 1                   ; D0 CC
                JC      SHORT eva_bsm_nfl_or_bp ; 72 B0   ; back-edge into emit
                DEC     WORD PTR cs:[14ABH]     ; 2E FF 0E AB 14
                JZ      SHORT eva_bsm_nfl_fin   ; 74 03
                JMP     eva_bsm_nfl_loop        ; E9 70 FF
eva_bsm_nfl_fin:
                SHL     BP, 1                   ; D1 E5
                SHL     BP, 1                   ; D1 E5
                SHL     CX, 1                   ; D1 E1
                SHL     CX, 1                   ; D1 E1
                SHL     DX, 1                   ; D1 E2
                SHL     DX, 1                   ; D1 E2
                ROR     AH, 1                   ; D0 CC
                ROR     AH, 1                   ; D0 CC
                JNC     SHORT eva_bsm_nfl_fin   ; 73 EE
                MOV     BX, DX                  ; 8B DA
                MOV     AL, [DI]                ; 8A 05
                MOV     DX, 03CFH               ; BA CF 03
                MOV     AX, BP                  ; 8B C5
                OUT     DX, AL                  ; EE
                MOV     BYTE PTR [DI], 0        ; C6 05 00
                MOV     DX, 03C5H               ; BA C5 03
                MOV     AL, 01H                 ; B0 01
                OUT     DX, AL                  ; EE
                MOV     [DI], BH                ; 88 3D
                SHL     AL, 1                   ; D0 E0
                OUT     DX, AL                  ; EE
                MOV     [DI], BL                ; 88 1D
                SHL     AL, 1                   ; D0 E0
                OUT     DX, AL                  ; EE
                MOV     [DI], CH                ; 88 2D
                SHL     AL, 1                   ; D0 E0
                OUT     DX, AL                  ; EE
                MOV     [DI], CL                ; 88 0D
                MOV     AX, cs:[14B1H]          ; 2E A1 B1 14
                NEG     WORD PTR cs:[14B1H]     ; 2E F7 1E B1 14
                ADD     cs:[14B3H], AX          ; 2E 01 06 B3 14
                POP     DI                      ; 5F
                ADD     DI, 50H                 ; 83 C7 50
                ADD     SI, cs:[14B5H]          ; 2E 03 36 B5 14
                DEC     WORD PTR cs:[14A9H]     ; 2E FF 0E A9 14
                JZ      SHORT eva_bsm_nfl_done  ; 74 03
                JMP     eva_sprite_row_noflip   ; E9 00 FF
eva_bsm_nfl_done:
                JMP     eva_bsm_done            ; E9 06 03
; ----------------------------------------------------------------------------
; --- 0x1768: eva_sprite_row_hflip -- LODSB forward, INC SI, no OR BP,BP
;     short-circuit in tail path (MOV AX,BP w/o XCHG).
; ----------------------------------------------------------------------------
eva_sprite_row_hflip:
                PUSH    DI                      ; 57
                MOV     AX, cs:[14AFH]          ; 2E A1 AF 14
                MOV     cs:[14ABH], AX          ; 2E A3 AB 14
                MOV     AH, cs:[14BFH]          ; 2E 8A 26 BF 14
                MOV     BX, cs:[14B3H]          ; 2E 8B 1E B3 14
                XOR     CX, CX                  ; 33 C9
                MOV     DX, CX                  ; 8B D1
                MOV     BP, CX                  ; 8B E9
eva_bsm_hfl_loop:
                MOV     AL, es:[SI]             ; 26 8A 04
                INC     SI                      ; 46
                OR      AL, AL                  ; 0A C0
                JZ      SHORT eva_bsm_hfl_skip  ; 74 6C
                XLAT    BYTE PTR CS:[BX]        ; 2E D7
                SHL     AL, 1                   ; D0 E0
                RCL     CL, 1                   ; D0 D1
                SHL     AL, 1                   ; D0 E0
                RCL     CH, 1                   ; D0 D5
                SHL     AL, 1                   ; D0 E0
                RCL     DL, 1                   ; D0 D2
                SHL     AL, 1                   ; D0 E0
                RCL     DH, 1                   ; D0 D6
                SHL     AL, 1                   ; D0 E0
                RCL     CL, 1                   ; D0 D1
                SHL     AL, 1                   ; D0 E0
                RCL     CH, 1                   ; D0 D5
                SHL     AL, 1                   ; D0 E0
                RCL     DL, 1                   ; D0 D2
                SHL     AL, 1                   ; D0 E0
                RCL     DH, 1                   ; D0 D6
                STC                             ; F9
                RCL     BP, 1                   ; D1 D5
                STC                             ; F9
                RCL     BP, 1                   ; D1 D5
                ROR     AH, 1                   ; D0 CC
                ROR     AH, 1                   ; D0 CC
                JNC     SHORT eva_bsm_hfl_adv   ; 73 37
eva_bsm_hfl_or_bp:
                OR      BP, BP                  ; 0B ED
                JZ      SHORT eva_bsm_hfl_inc   ; 74 32
                MOV     BX, DX                  ; 8B DA
                MOV     AL, [DI]                ; 8A 05
                MOV     DX, 03CFH               ; BA CF 03
                XCHG    AX, BP                  ; 95
                OUT     DX, AL                  ; EE
                MOV     AX, BP                  ; 8B C5
                MOV     BYTE PTR [DI], 0        ; C6 05 00
                MOV     DX, 03C5H               ; BA C5 03
                MOV     AL, 01H                 ; B0 01
                OUT     DX, AL                  ; EE
                MOV     [DI], BH                ; 88 3D
                SHL     AL, 1                   ; D0 E0
                OUT     DX, AL                  ; EE
                MOV     [DI], BL                ; 88 1D
                SHL     AL, 1                   ; D0 E0
                OUT     DX, AL                  ; EE
                MOV     [DI], CH                ; 88 2D
                SHL     AL, 1                   ; D0 E0
                OUT     DX, AL                  ; EE
                MOV     [DI], CL                ; 88 0D
                MOV     BX, cs:[14B3H]          ; 2E 8B 1E B3 14
                XOR     CX, CX                  ; 33 C9
                MOV     DX, CX                  ; 8B D1
                MOV     BP, CX                  ; 8B E9
eva_bsm_hfl_inc:
                INC     DI                      ; 47
eva_bsm_hfl_adv:
                DEC     WORD PTR cs:[14ABH]     ; 2E FF 0E AB 14
                JNZ     SHORT eva_bsm_hfl_loop  ; 75 8E
                JMP     SHORT eva_bsm_hfl_fin   ; EB 1C
eva_bsm_hfl_skip:
                SHL     BP, 1                   ; D1 E5
                SHL     BP, 1                   ; D1 E5
                SHL     CX, 1                   ; D1 E1
                SHL     CX, 1                   ; D1 E1
                SHL     DX, 1                   ; D1 E2
                SHL     DX, 1                   ; D1 E2
                ROR     AH, 1                   ; D0 CC
                ROR     AH, 1                   ; D0 CC
                JC      SHORT eva_bsm_hfl_or_bp ; 72 B0
                DEC     WORD PTR cs:[14ABH]     ; 2E FF 0E AB 14
                JZ      SHORT eva_bsm_hfl_fin   ; 74 03
                JMP     eva_bsm_hfl_loop        ; E9 70 FF
eva_bsm_hfl_fin:
                SHL     BP, 1                   ; D1 E5
                SHL     BP, 1                   ; D1 E5
                SHL     CX, 1                   ; D1 E1
                SHL     CX, 1                   ; D1 E1
                SHL     DX, 1                   ; D1 E2
                SHL     DX, 1                   ; D1 E2
                ROR     AH, 1                   ; D0 CC
                ROR     AH, 1                   ; D0 CC
                JNC     SHORT eva_bsm_hfl_fin   ; 73 EE
                MOV     BX, DX                  ; 8B DA
                MOV     AL, [DI]                ; 8A 05
                MOV     DX, 03CFH               ; BA CF 03
                MOV     AX, BP                  ; 8B C5
                OUT     DX, AL                  ; EE
                MOV     BYTE PTR [DI], 0        ; C6 05 00
                MOV     DX, 03C5H               ; BA C5 03
                MOV     AL, 01H                 ; B0 01
                OUT     DX, AL                  ; EE
                MOV     [DI], BH                ; 88 3D
                SHL     AL, 1                   ; D0 E0
                OUT     DX, AL                  ; EE
                MOV     [DI], BL                ; 88 1D
                SHL     AL, 1                   ; D0 E0
                OUT     DX, AL                  ; EE
                MOV     [DI], CH                ; 88 2D
                SHL     AL, 1                   ; D0 E0
                OUT     DX, AL                  ; EE
                MOV     [DI], CL                ; 88 0D
                MOV     AX, cs:[14B1H]          ; 2E A1 B1 14
                NEG     WORD PTR cs:[14B1H]     ; 2E F7 1E B1 14
                ADD     cs:[14B3H], AX          ; 2E 01 06 B3 14
                POP     DI                      ; 5F
                ADD     DI, 50H                 ; 83 C7 50
                ADD     SI, cs:[14B5H]          ; 2E 03 36 B5 14
                DEC     WORD PTR cs:[14A9H]     ; 2E FF 0E A9 14
                JZ      SHORT eva_bsm_hfl_done  ; 74 03
                JMP     eva_sprite_row_hflip    ; E9 00 FF
eva_bsm_hfl_done:
                JMP     eva_bsm_done            ; E9 03 02
; ----------------------------------------------------------------------------
; --- 0x186B: eva_sprite_row_vflip -- LODSB reverse, DEC SI, SUB SI,row_step.
; ----------------------------------------------------------------------------
eva_sprite_row_vflip:
                PUSH    DI                      ; 57
                MOV     AX, cs:[14AFH]          ; 2E A1 AF 14
                MOV     cs:[14ABH], AX          ; 2E A3 AB 14
                MOV     AH, cs:[14BFH]          ; 2E 8A 26 BF 14
                MOV     BX, cs:[14B3H]          ; 2E 8B 1E B3 14
                XOR     CX, CX                  ; 33 C9
                MOV     DX, CX                  ; 8B D1
                MOV     BP, CX                  ; 8B E9
eva_bsm_vfl_loop:
                MOV     AL, es:[SI]             ; 26 8A 04
                DEC     SI                      ; 4E
                OR      AL, AL                  ; 0A C0
                JZ      SHORT eva_bsm_vfl_skip  ; 74 6C
                XLAT    BYTE PTR CS:[BX]        ; 2E D7
                SHL     AL, 1                   ; D0 E0
                RCL     CL, 1                   ; D0 D1
                SHL     AL, 1                   ; D0 E0
                RCL     CH, 1                   ; D0 D5
                SHL     AL, 1                   ; D0 E0
                RCL     DL, 1                   ; D0 D2
                SHL     AL, 1                   ; D0 E0
                RCL     DH, 1                   ; D0 D6
                SHL     AL, 1                   ; D0 E0
                RCL     CL, 1                   ; D0 D1
                SHL     AL, 1                   ; D0 E0
                RCL     CH, 1                   ; D0 D5
                SHL     AL, 1                   ; D0 E0
                RCL     DL, 1                   ; D0 D2
                SHL     AL, 1                   ; D0 E0
                RCL     DH, 1                   ; D0 D6
                STC                             ; F9
                RCL     BP, 1                   ; D1 D5
                STC                             ; F9
                RCL     BP, 1                   ; D1 D5
                ROR     AH, 1                   ; D0 CC
                ROR     AH, 1                   ; D0 CC
                JNC     SHORT eva_bsm_vfl_adv   ; 73 37
eva_bsm_vfl_or_bp:
                OR      BP, BP                  ; 0B ED
                JZ      SHORT eva_bsm_vfl_inc   ; 74 32
                MOV     BX, DX                  ; 8B DA
                MOV     AL, [DI]                ; 8A 05
                MOV     DX, 03CFH               ; BA CF 03
                XCHG    AX, BP                  ; 95
                OUT     DX, AL                  ; EE
                MOV     AX, BP                  ; 8B C5
                MOV     BYTE PTR [DI], 0        ; C6 05 00
                MOV     DX, 03C5H               ; BA C5 03
                MOV     AL, 01H                 ; B0 01
                OUT     DX, AL                  ; EE
                MOV     [DI], BH                ; 88 3D
                SHL     AL, 1                   ; D0 E0
                OUT     DX, AL                  ; EE
                MOV     [DI], BL                ; 88 1D
                SHL     AL, 1                   ; D0 E0
                OUT     DX, AL                  ; EE
                MOV     [DI], CH                ; 88 2D
                SHL     AL, 1                   ; D0 E0
                OUT     DX, AL                  ; EE
                MOV     [DI], CL                ; 88 0D
                MOV     BX, cs:[14B3H]          ; 2E 8B 1E B3 14
                XOR     CX, CX                  ; 33 C9
                MOV     DX, CX                  ; 8B D1
                MOV     BP, CX                  ; 8B E9
eva_bsm_vfl_inc:
                INC     DI                      ; 47
eva_bsm_vfl_adv:
                DEC     WORD PTR cs:[14ABH]     ; 2E FF 0E AB 14
                JNZ     SHORT eva_bsm_vfl_loop  ; 75 8E
                JMP     SHORT eva_bsm_vfl_fin   ; EB 1C
eva_bsm_vfl_skip:
                SHL     BP, 1                   ; D1 E5
                SHL     BP, 1                   ; D1 E5
                SHL     CX, 1                   ; D1 E1
                SHL     CX, 1                   ; D1 E1
                SHL     DX, 1                   ; D1 E2
                SHL     DX, 1                   ; D1 E2
                ROR     AH, 1                   ; D0 CC
                ROR     AH, 1                   ; D0 CC
                JC      SHORT eva_bsm_vfl_or_bp ; 72 B0
                DEC     WORD PTR cs:[14ABH]     ; 2E FF 0E AB 14
                JZ      SHORT eva_bsm_vfl_fin   ; 74 03
                JMP     eva_bsm_vfl_loop        ; E9 70 FF
eva_bsm_vfl_fin:
                SHL     BP, 1                   ; D1 E5
                SHL     BP, 1                   ; D1 E5
                SHL     CX, 1                   ; D1 E1
                SHL     CX, 1                   ; D1 E1
                SHL     DX, 1                   ; D1 E2
                SHL     DX, 1                   ; D1 E2
                ROR     AH, 1                   ; D0 CC
                ROR     AH, 1                   ; D0 CC
                JNC     SHORT eva_bsm_vfl_fin   ; 73 EE
                MOV     BX, DX                  ; 8B DA
                MOV     AL, [DI]                ; 8A 05
                MOV     DX, 03CFH               ; BA CF 03
                MOV     AX, BP                  ; 8B C5
                OUT     DX, AL                  ; EE
                MOV     BYTE PTR [DI], 0        ; C6 05 00
                MOV     DX, 03C5H               ; BA C5 03
                MOV     AL, 01H                 ; B0 01
                OUT     DX, AL                  ; EE
                MOV     [DI], BH                ; 88 3D
                SHL     AL, 1                   ; D0 E0
                OUT     DX, AL                  ; EE
                MOV     [DI], BL                ; 88 1D
                SHL     AL, 1                   ; D0 E0
                OUT     DX, AL                  ; EE
                MOV     [DI], CH                ; 88 2D
                SHL     AL, 1                   ; D0 E0
                OUT     DX, AL                  ; EE
                MOV     [DI], CL                ; 88 0D
                MOV     AX, cs:[14B1H]          ; 2E A1 B1 14
                NEG     WORD PTR cs:[14B1H]     ; 2E F7 1E B1 14
                ADD     cs:[14B3H], AX          ; 2E 01 06 B3 14
                POP     DI                      ; 5F
                ADD     DI, 50H                 ; 83 C7 50
                SUB     SI, cs:[14B5H]          ; 2E 2B 36 B5 14
                DEC     WORD PTR cs:[14A9H]     ; 2E FF 0E A9 14
                JZ      SHORT eva_bsm_vfl_done  ; 74 03
                JMP     eva_sprite_row_vflip    ; E9 00 FF
eva_bsm_vfl_done:
                JMP     eva_bsm_done            ; E9 00 01
; ----------------------------------------------------------------------------
; --- 0x196E: eva_sprite_row_hvflip -- LODSB reverse, DEC SI, SUB SI,row_step.
;     (matches vflip exactly except wired into hvflip dispatch slot.)
; ----------------------------------------------------------------------------
eva_sprite_row_hvflip:
                PUSH    DI                      ; 57
                MOV     AX, cs:[14AFH]          ; 2E A1 AF 14
                MOV     cs:[14ABH], AX          ; 2E A3 AB 14
                MOV     AH, cs:[14BFH]          ; 2E 8A 26 BF 14
                MOV     BX, cs:[14B3H]          ; 2E 8B 1E B3 14
                XOR     CX, CX                  ; 33 C9
                MOV     DX, CX                  ; 8B D1
                MOV     BP, CX                  ; 8B E9
eva_bsm_hvfl_loop:
                MOV     AL, es:[SI]             ; 26 8A 04
                DEC     SI                      ; 4E
                OR      AL, AL                  ; 0A C0
                JZ      SHORT eva_bsm_hvfl_skip ; 74 6C
                XLAT    BYTE PTR CS:[BX]        ; 2E D7
                SHL     AL, 1                   ; D0 E0
                RCL     CL, 1                   ; D0 D1
                SHL     AL, 1                   ; D0 E0
                RCL     CH, 1                   ; D0 D5
                SHL     AL, 1                   ; D0 E0
                RCL     DL, 1                   ; D0 D2
                SHL     AL, 1                   ; D0 E0
                RCL     DH, 1                   ; D0 D6
                SHL     AL, 1                   ; D0 E0
                RCL     CL, 1                   ; D0 D1
                SHL     AL, 1                   ; D0 E0
                RCL     CH, 1                   ; D0 D5
                SHL     AL, 1                   ; D0 E0
                RCL     DL, 1                   ; D0 D2
                SHL     AL, 1                   ; D0 E0
                RCL     DH, 1                   ; D0 D6
                STC                             ; F9
                RCL     BP, 1                   ; D1 D5
                STC                             ; F9
                RCL     BP, 1                   ; D1 D5
                ROR     AH, 1                   ; D0 CC
                ROR     AH, 1                   ; D0 CC
                JNC     SHORT eva_bsm_hvfl_adv  ; 73 37
eva_bsm_hvfl_or_bp:
                OR      BP, BP                  ; 0B ED
                JZ      SHORT eva_bsm_hvfl_inc  ; 74 32
                MOV     BX, DX                  ; 8B DA
                MOV     AL, [DI]                ; 8A 05
                MOV     DX, 03CFH               ; BA CF 03
                XCHG    AX, BP                  ; 95
                OUT     DX, AL                  ; EE
                MOV     AX, BP                  ; 8B C5
                MOV     BYTE PTR [DI], 0        ; C6 05 00
                MOV     DX, 03C5H               ; BA C5 03
                MOV     AL, 01H                 ; B0 01
                OUT     DX, AL                  ; EE
                MOV     [DI], BH                ; 88 3D
                SHL     AL, 1                   ; D0 E0
                OUT     DX, AL                  ; EE
                MOV     [DI], BL                ; 88 1D
                SHL     AL, 1                   ; D0 E0
                OUT     DX, AL                  ; EE
                MOV     [DI], CH                ; 88 2D
                SHL     AL, 1                   ; D0 E0
                OUT     DX, AL                  ; EE
                MOV     [DI], CL                ; 88 0D
                MOV     BX, cs:[14B3H]          ; 2E 8B 1E B3 14
                XOR     CX, CX                  ; 33 C9
                MOV     DX, CX                  ; 8B D1
                MOV     BP, CX                  ; 8B E9
eva_bsm_hvfl_inc:
                INC     DI                      ; 47
eva_bsm_hvfl_adv:
                DEC     WORD PTR cs:[14ABH]     ; 2E FF 0E AB 14
                JNZ     SHORT eva_bsm_hvfl_loop ; 75 8E
                JMP     SHORT eva_bsm_hvfl_fin  ; EB 1C
eva_bsm_hvfl_skip:
                SHL     BP, 1                   ; D1 E5
                SHL     BP, 1                   ; D1 E5
                SHL     CX, 1                   ; D1 E1
                SHL     CX, 1                   ; D1 E1
                SHL     DX, 1                   ; D1 E2
                SHL     DX, 1                   ; D1 E2
                ROR     AH, 1                   ; D0 CC
                ROR     AH, 1                   ; D0 CC
                JC      SHORT eva_bsm_hvfl_or_bp ; 72 B0
                DEC     WORD PTR cs:[14ABH]     ; 2E FF 0E AB 14
                JZ      SHORT eva_bsm_hvfl_fin  ; 74 03
                JMP     eva_bsm_hvfl_loop       ; E9 70 FF
eva_bsm_hvfl_fin:
                SHL     BP, 1                   ; D1 E5
                SHL     BP, 1                   ; D1 E5
                SHL     CX, 1                   ; D1 E1
                SHL     CX, 1                   ; D1 E1
                SHL     DX, 1                   ; D1 E2
                SHL     DX, 1                   ; D1 E2
                ROR     AH, 1                   ; D0 CC
                ROR     AH, 1                   ; D0 CC
                JNC     SHORT eva_bsm_hvfl_fin  ; 73 EE
                MOV     BX, DX                  ; 8B DA
                MOV     AL, [DI]                ; 8A 05
                MOV     DX, 03CFH               ; BA CF 03
                MOV     AX, BP                  ; 8B C5
                OUT     DX, AL                  ; EE
                MOV     BYTE PTR [DI], 0        ; C6 05 00
                MOV     DX, 03C5H               ; BA C5 03
                MOV     AL, 01H                 ; B0 01
                OUT     DX, AL                  ; EE
                MOV     [DI], BH                ; 88 3D
                SHL     AL, 1                   ; D0 E0
                OUT     DX, AL                  ; EE
                MOV     [DI], BL                ; 88 1D
                SHL     AL, 1                   ; D0 E0
                OUT     DX, AL                  ; EE
                MOV     [DI], CH                ; 88 2D
                SHL     AL, 1                   ; D0 E0
                OUT     DX, AL                  ; EE
                MOV     [DI], CL                ; 88 0D
                MOV     AX, cs:[14B1H]          ; 2E A1 B1 14
                NEG     WORD PTR cs:[14B1H]     ; 2E F7 1E B1 14
                ADD     cs:[14B3H], AX          ; 2E 01 06 B3 14
                POP     DI                      ; 5F
                ADD     DI, 50H                 ; 83 C7 50
                SUB     SI, cs:[14B5H]          ; 2E 2B 36 B5 14
                DEC     WORD PTR cs:[14A9H]     ; 2E FF 0E A9 14
                JZ      SHORT eva_bsm_done      ; 74 03
                JMP     eva_sprite_row_hvflip   ; E9 00 FF
eva_bsm_done:
                ; --- 0x1A6E: shared epilogue. Restore SEQ map-mask to
                ; all-planes (0x0F), tear down the prologue's stack frame
                ; (including the 10-byte scratch + 4 saved segregs), RETF.
                MOV     DX, 03C5H               ; BA C5 03
                MOV     AL, 0FH                 ; B0 0F
                OUT     DX, AL                  ; EE
                POP     DS                      ; 1F
                POP     ES                      ; 07
                POP     SI                      ; 5E
                POP     DI                      ; 5F
                ADD     SP, 0AH                 ; 83 C4 0A
                POP     BP                      ; 5D
                RETF                            ; CB
eva_blit_sprite_master ENDP

; ============================================================================
; eva_rect_capture -- planar-rect read from framebuffer to caller buffer.
; chunk:0x1A7D..0x1AF4  (120 bytes; vtable slot 6).
;
; Reads a rect from the EGA framebuffer in planar form. Iterates planes
; via SEQ index 2 map-mask = 0x08, 0x04, 0x02, 0x01 (controlled by
; AH right-shift loop seed 0x0802). For each plane: REP MOVSW per row
; (DI advances by 0x50 per row = 80 bytes/row in 640-wide mode).
;
; ABI (__cdecl16far, vtable slot):
;   [BP+06]  ushort  src_off    (framebuffer source)
;   [BP+08]  ushort  src_seg    (ignored -- DS:[18] used)
;   [BP+0A]  ushort  x_start
;   [BP+0C]  ushort  y_top
;   [BP+0E]  ushort  x_end
;   [BP+10]  ushort  row_count
; ============================================================================
eva_rect_capture PROC FAR
                PUSH    BP                      ; 55
                MOV     BP, SP                  ; 8B EC
                PUSH    SI                      ; 56
                PUSH    DI                      ; 57
                PUSH    DS                      ; 1E
                MOV     DX, 03CEH               ; BA CE 03
                MOV     AX, 0FF08H              ; B8 08 FF
                OUT     DX, AX                  ; EF
                MOV     SI, [BP+6]              ; 8B 76 06
                PUSH    WORD PTR [BP+8]         ; FF 76 08
                MOV     CX, [BP+0AH]            ; 8B 4E 0A
                MOV     AX, CX                  ; 8B C1
                SHR     CX, 1                   ; D1 E9
                SHR     CX, 1                   ; D1 E9
                MOV     BX, [BP+0EH]            ; 8B 5E 0E
                ADD     BX, AX                  ; 03 D8
                SHR     BX, 1                   ; D1 EB
                SHR     BX, 1                   ; D1 EB
                SUB     BX, CX                  ; 2B D9
                INC     BX                      ; 43
                MOV     AX, BX                  ; 8B C3
                SHR     BX, 1                   ; D1 EB
                AND     AX, 01H                 ; 25 01 00
                JZ      SHORT eva_rc_even       ; 74 01
                INC     BX                      ; 43
eva_rc_even:
                MOV     DS, cs:[00B2H]          ; 2E 8E 1E B2 00
                MOV     DX, [BP+10H]            ; 8B 56 10
                MOV     DI, [BP+0CH]            ; 8B 7E 0C
                SHL     DI, 1                   ; D1 E7
                MOV     DI, [DI].GfxContext.pRow_offset_lut ; 8B BD F2 06
                ADD     DI, CX                  ; 03 F9
                MOV     AX, ds:[GfxContext.wGfxBlitDstPage] ; A1 18 00
                MOV     ES, AX                  ; 8E C0
                POP     DS                      ; 1F          ; src_seg
                MOV     AX, 0802H               ; B8 02 08    ; SEQ index 2 mask 8 -> plane 3 first
eva_rc_plane:
                MOV     BP, DX                  ; 8B EA
                MOV     DX, 03C4H               ; BA C4 03
                OUT     DX, AX                  ; EF
                MOV     DX, BP                  ; 8B D5
                PUSH    DX                      ; 52
                PUSH    DI                      ; 57
eva_rc_row:
                MOV     CX, BX                  ; 8B CB
                MOV     BP, DI                  ; 8B EF
                REP MOVSW                       ; F3 A5
                MOV     DI, BP                  ; 8B FD
                ADD     DI, 50H                 ; 83 C7 50
                DEC     DX                      ; 4A
                JNZ     SHORT eva_rc_row        ; 75 F2
                POP     DI                      ; 5F
                POP     DX                      ; 5A
                SHR     AH, 1                   ; D0 EC
                JNC     SHORT eva_rc_plane      ; 73 E2
                MOV     DX, 03C4H               ; BA C4 03
                MOV     AX, 0F02H               ; B8 02 0F    ; SEQ index 2 mask 0xF (all planes)
                OUT     DX, AX                  ; EF
                POP     DS                      ; 1F
                POP     DI                      ; 5F
                POP     SI                      ; 5E
                POP     BP                      ; 5D
                RETF                            ; CB
eva_rect_capture ENDP

; ----------------------------------------------------------------------------
; g_abEvaDrawLinePixelMaskLut -- 4-byte pixel-mask LUT.
; chunk:0x1AF5..0x1AF8.
;
; Indexed in eva_draw_line @ 0x1B1E by (x & 3) to pick the bit mask for a
; single pixel within an EGA byte (2 bits per pixel x 4 pixels per byte):
;   [0] 0xC0  bits 7-6 (leftmost pixel)
;   [1] 0x30  bits 5-4
;   [2] 0x0C  bits 3-2
;   [3] 0x03  bits 1-0 (rightmost pixel)
; ----------------------------------------------------------------------------
g_abEvaDrawLinePixelMaskLut:
                DB      0C0H, 030H, 00CH, 003H

; ============================================================================
; eva_draw_line -- full Bresenham-style line rasteriser.
; chunk:0x1AF9..0x1D4B  (595 bytes; vtable slot 1).
;
; Bresenham-style line walker using the 4-plane EGA Set/Reset + Bit-Mask
; write path. Splits into 4 cases on the relative magnitudes of dx, dy,
; and direction:
;
;   (x0==x1 && y0==y1)  -- single pixel  -- 0x1B46
;   (x0==x1)            -- pure vertical -- 0x1B96
;   (y0==y1)            -- pure horizontal -- 0x1B5C
;   (|dx| == |dy|)      -- pure diagonal -- 0x1BDF
;   (|dx|  > |dy|)      -- x-major (0x1CAC entry)
;   (|dx|  < |dy|)      -- y-major (0x1C27 entry)
;
; Helper used by eva_line @ 0x140A.
;
; ABI (entry-register-based, host caller-passed):
;   BX     x0, DX  x1
;   CX     y0, SI  y1
;   ES:DI  framebuffer pointer (preloaded by caller)
;   DS:[0x0E]  colour byte (chunky)
;
; Globals touched (chunk-local scratch):
;   ds:[0022]  word   bit-spread of colour (XLAT through 0x4E1 LUT)
;   ds:[06BC]  word   Bresenham step (integer part)
;   ds:[06BE]  word   Bresenham step (fractional remainder)
;   ds:[06C0]  word   minor-axis snapshot
;   ds:[06C2]  word   Bresenham error accumulator
;   ds:[06C4]  byte   start-pixel mask (from g_abEvaDrawLinePixelMaskLut)
; ============================================================================
eva_draw_line PROC FAR
                PUSH    DS                      ; 1E
                MOV     DS, cs:[00B2H]          ; 2E 8E 1E B2 00
                XOR     AH, AH                  ; 32 E4
                MOV     AL, ds:[GfxContext.bGfx_outline_color] ; A0 0E 00      ; colour byte
                PUSH    BX                      ; 53
                PUSH    DX                      ; 52
                MOV     BX, 04E1H               ; BB E1 04
                XLAT    BYTE PTR CS:[BX]        ; 2E D7   spread colour into 4-plane bits
                PUSH    AX                      ; 50
                MOV     DX, 03CEH               ; BA CE 03
                MOV     AX, 0205H               ; B8 05 02      ; index 5 mode 2 (write mode 2)
                OUT     DX, AX                  ; EF
                POP     AX                      ; 58
                POP     DX                      ; 5A
                POP     BX                      ; 5B
                MOV     ds:[0022H], AX          ; A3 22 00
                MOV     DI, BX                  ; 8B FB
                AND     DI, 03H                 ; 83 E7 03
                MOV     AL, cs:[DI+1AF5H]       ; 2E 8A 85 F5 1A
                MOV     ds:[06C4H], AL          ; A2 C4 06
                MOV     DI, CX                  ; 8B F9
                SHL     DI, 1                   ; D1 E7
                MOV     DI, [DI].GfxContext.pRow_offset_lut ; 8B BD F2 06
                MOV     AX, BX                  ; 8B C3
                SHR     AX, 1                   ; D1 E8
                SHR     AX, 1                   ; D1 E8
                ADD     DI, AX                  ; 03 F8
                ; --- 0x1B36: classify the line by axis comparisons.
                CMP     BX, DX                  ; 3B DA
                JNZ     SHORT eva_dl_x_diff     ; 75 06
                CMP     CX, SI                  ; 3B CE
                JZ      SHORT eva_dl_point      ; 74 08
                JMP     eva_dl_vert             ; E9 55 00
eva_dl_x_diff:
                CMP     CX, SI                  ; 3B CE
                JZ      SHORT eva_dl_horiz      ; 74 18
                JMP     eva_dl_other            ; E9 7C 00
eva_dl_point:
                ; --- 0x1B46: single-pixel poke.
                MOV     AH, ds:[06C4H]          ; 8A 26 C4 06
                MOV     AL, es:[DI]             ; 26 8A 05
                MOV     DX, 03CEH               ; BA CE 03
                MOV     AL, 08H                 ; B0 08
                OUT     DX, AX                  ; EF
                MOV     AX, ds:[0022H]          ; A1 22 00
                MOV     es:[DI], AL             ; 26 88 05
                JMP     eva_dl_done             ; E9 E7 01
eva_dl_horiz:
                ; --- 0x1B5C: pure horizontal line (CX == SI).
                SUB     DX, BX                  ; 2B D3
                MOV     CX, DX                  ; 8B CA
                MOV     AH, ds:[06C4H]          ; 8A 26 C4 06
                MOV     BX, ds:[0022H]          ; 8B 1E 22 00
                MOV     DX, 03CEH               ; BA CE 03
                MOV     AL, 08H                 ; B0 08
                MOV     BH, es:[DI]             ; 26 8A 3D
                OUT     DX, AX                  ; EF
                MOV     es:[DI], BL             ; 26 88 1D
eva_dl_horiz_loop:
                ROR     AH, 1                   ; D0 CC
                ROR     AH, 1                   ; D0 CC
                JC      SHORT eva_dl_horiz_carry ; 72 0C
                MOV     BH, es:[DI]             ; 26 8A 3D
                OUT     DX, AX                  ; EF
                MOV     es:[DI], BL             ; 26 88 1D
                DEC     CX                      ; 49
                JZ      SHORT eva_dl_horiz_done ; 74 0F
                JMP     SHORT eva_dl_horiz_loop ; EB F0
eva_dl_horiz_carry:
                INC     DI                      ; 47
                MOV     BH, es:[DI]             ; 26 8A 3D
                OUT     DX, AX                  ; EF
                MOV     es:[DI], BL             ; 26 88 1D
                DEC     CX                      ; 49
                JZ      SHORT eva_dl_horiz_done ; 74 02
                JMP     SHORT eva_dl_horiz_loop ; EB E0
eva_dl_horiz_done:
                JMP     eva_dl_done             ; E9 AD 01
eva_dl_vert:
                ; --- 0x1B96: pure vertical line.
                MOV     AX, 50H                 ; B8 50 00
                MOV     BP, AX                  ; 8B E8
                SUB     SI, CX                  ; 2B F1
                JG      SHORT eva_dl_vert_pos   ; 7F 04
                NEG     SI                      ; F7 DE
                NEG     BP                      ; F7 DD
eva_dl_vert_pos:
                MOV     CX, SI                  ; 8B CE
                MOV     AH, ds:[06C4H]          ; 8A 26 C4 06
                MOV     BX, ds:[0022H]          ; 8B 1E 22 00
                MOV     DX, 03CEH               ; BA CE 03
                MOV     AL, 08H                 ; B0 08
                OUT     DX, AX                  ; EF
eva_dl_vert_loop:
                MOV     BH, es:[DI]             ; 26 8A 3D
                MOV     es:[DI], BL             ; 26 88 1D
                ADD     DI, BP                  ; 03 FD
                DEC     CX                      ; 49
                JS      SHORT eva_dl_vert_done  ; 78 02
                JMP     SHORT eva_dl_vert_loop  ; EB F3
eva_dl_vert_done:
                JMP     eva_dl_done             ; E9 80 01
eva_dl_other:
                ; --- 0x1BC3: non-axis-aligned (slope != 0 in both axes).
                MOV     AX, 50H                 ; B8 50 00
                MOV     BP, AX                  ; 8B E8
                SUB     DX, BX                  ; 2B D3
                SUB     SI, CX                  ; 2B F1
                JG      SHORT eva_dl_other_pos  ; 7F 04
                NEG     SI                      ; F7 DE
                NEG     BP                      ; F7 DD
eva_dl_other_pos:
                MOV     CX, SI                  ; 8B CE
                CMP     CX, DX                  ; 3B CA
                JZ      SHORT eva_dl_diag       ; 74 07
                JC      SHORT eva_dl_xmajor     ; 72 03
                JMP     eva_dl_ymajor           ; E9 CF 00
eva_dl_xmajor:
                JMP     eva_dl_xmaj_entry       ; E9 47 00
eva_dl_diag:
                ; --- 0x1BDF: pure diagonal (|dx| == |dy|).
                MOV     CX, DX                  ; 8B CA
                MOV     AH, ds:[06C4H]          ; 8A 26 C4 06
                MOV     BX, ds:[0022H]          ; 8B 1E 22 00
                MOV     DX, 03CEH               ; BA CE 03
                MOV     AL, 08H                 ; B0 08
                MOV     BH, es:[DI]             ; 26 8A 3D
                OUT     DX, AX                  ; EF
                MOV     es:[DI], BL             ; 26 88 1D
eva_dl_diag_loop:
                ROR     AH, 1                   ; D0 CC
                ROR     AH, 1                   ; D0 CC
                JC      SHORT eva_dl_diag_carry ; 72 14
                MOV     BH, es:[DI]             ; 26 8A 3D
                OUT     DX, AX                  ; EF
                MOV     es:[DI], BL             ; 26 88 1D
                ADD     DI, BP                  ; 03 FD
                MOV     BH, es:[DI]             ; 26 8A 3D
                MOV     es:[DI], BL             ; 26 88 1D
                DEC     CX                      ; 49
                JZ      SHORT eva_dl_diag_done  ; 74 17
                JMP     SHORT eva_dl_diag_loop  ; EB E6
eva_dl_diag_carry:
                INC     DI                      ; 47
                MOV     BH, es:[DI]             ; 26 8A 3D
                OUT     DX, AX                  ; EF
                MOV     es:[DI], BL             ; 26 88 1D
                DEC     CX                      ; 49
                JZ      SHORT eva_dl_diag_done  ; 74 0A
                ADD     DI, BP                  ; 03 FD
                MOV     BH, es:[DI]             ; 26 8A 3D
                MOV     es:[DI], BL             ; 26 88 1D
                JMP     SHORT eva_dl_diag_loop  ; EB D1
eva_dl_diag_done:
                JMP     eva_dl_done             ; E9 1C 01
eva_dl_xmaj_entry:
                ; --- 0x1C27: x-major Bresenham. CX = |dx|, SI = |dy|.
                MOV     SI, DX                  ; 8B F2
                MOV     AX, DX                  ; 8B C2
                XOR     DX, DX                  ; 33 D2
                INC     CX                      ; 41
                DIV     CX                      ; F7 F1
                MOV     ds:[GfxContext.wTextureIdx], AX          ; A3 BC 06
                XOR     AX, AX                  ; 33 C0
                DIV     CX                      ; F7 F1
                MOV     ds:[06BEH], AX          ; A3 BE 06
                XOR     AX, AX                  ; 33 C0
                MOV     ds:[06C2H], AX          ; A3 C2 06
                MOV     AH, ds:[06C4H]          ; 8A 26 C4 06
                MOV     BX, ds:[0022H]          ; 8B 1E 22 00
                MOV     DX, 03CEH               ; BA CE 03
                MOV     AL, 08H                 ; B0 08
                MOV     CX, ds:[GfxContext.wTextureIdx]          ; 8B 0E BC 06
                INC     CX                      ; 41
                MOV     BH, es:[DI]             ; 26 8A 3D
                OUT     DX, AX                  ; EF
                MOV     es:[DI], BL             ; 26 88 1D
eva_dl_xmaj_step:
                MOV     ds:[06C0H], SI          ; 89 36 C0 06
                SUB     SI, CX                  ; 2B F1
                JGE     SHORT eva_dl_xmaj_loop  ; 7D 06
                MOV     CX, ds:[06C0H]          ; 8B 0E C0 06
                XOR     SI, SI                  ; 33 F6
eva_dl_xmaj_loop:
                ROR     AH, 1                   ; D0 CC
                ROR     AH, 1                   ; D0 CC
                JC      SHORT eva_dl_xmaj_carry ; 72 30
                MOV     BH, es:[DI]             ; 26 8A 3D
                OUT     DX, AX                  ; EF
                MOV     es:[DI], BL             ; 26 88 1D
                DEC     CX                      ; 49
                JZ      SHORT eva_dl_xmaj_advance ; 74 02
                JMP     SHORT eva_dl_xmaj_loop  ; EB EE
eva_dl_xmaj_advance:
                CMP     SI, 0                   ; 83 FE 00
                JZ      SHORT eva_dl_xmaj_done  ; 74 2C
                ADD     DI, BP                  ; 03 FD
                MOV     BH, es:[DI]             ; 26 8A 3D
                MOV     es:[DI], BL             ; 26 88 1D
                MOV     CX, ds:[06BEH]          ; 8B 0E BE 06
                ADD     ds:[06C2H], CX          ; 01 0E C2 06
                JNC     SHORT eva_dl_xmaj_no_carry ; 73 07
                MOV     CX, ds:[GfxContext.wTextureIdx]          ; 8B 0E BC 06
                INC     CX                      ; 41
                JMP     SHORT eva_dl_xmaj_step  ; EB C2
eva_dl_xmaj_no_carry:
                MOV     CX, ds:[GfxContext.wTextureIdx]          ; 8B 0E BC 06
                JMP     SHORT eva_dl_xmaj_step  ; EB BC
eva_dl_xmaj_carry:
                INC     DI                      ; 47
                MOV     BH, es:[DI]             ; 26 8A 3D
                OUT     DX, AX                  ; EF
                MOV     es:[DI], BL             ; 26 88 1D
                DEC     CX                      ; 49
                JZ      SHORT eva_dl_xmaj_advance ; 74 D1
                JMP     SHORT eva_dl_xmaj_loop  ; EB BD
eva_dl_xmaj_done:
                JMP     eva_dl_done             ; E9 97 00
eva_dl_ymajor:
                ; --- 0x1CAC: y-major Bresenham.
                XCHG    CX, DX                  ; 87 CA       ; Borland CX-first form
                MOV     SI, DX                  ; 8B F2
                MOV     AX, DX                  ; 8B C2
                XOR     DX, DX                  ; 33 D2
                INC     CX                      ; 41
                DIV     CX                      ; F7 F1
                MOV     ds:[GfxContext.wTextureIdx], AX          ; A3 BC 06
                XOR     AX, AX                  ; 33 C0
                DIV     CX                      ; F7 F1
                MOV     ds:[06BEH], AX          ; A3 BE 06
                XOR     AX, AX                  ; 33 C0
                MOV     ds:[06C2H], AX          ; A3 C2 06
                MOV     AH, ds:[06C4H]          ; 8A 26 C4 06
                MOV     BX, ds:[0022H]          ; 8B 1E 22 00
                MOV     DX, 03CEH               ; BA CE 03
                MOV     AL, 08H                 ; B0 08
                MOV     CX, ds:[GfxContext.wTextureIdx]          ; 8B 0E BC 06
                INC     CX                      ; 41
                MOV     BH, es:[DI]             ; 26 8A 3D
                OUT     DX, AX                  ; EF
                MOV     es:[DI], BL             ; 26 88 1D
eva_dl_ymaj_step:
                MOV     ds:[06C0H], SI          ; 89 36 C0 06
                SUB     SI, CX                  ; 2B F1
                JGE     SHORT eva_dl_ymaj_loop  ; 7D 06
                MOV     CX, ds:[06C0H]          ; 8B 0E C0 06
                XOR     SI, SI                  ; 33 F6
eva_dl_ymaj_loop:
                ADD     DI, BP                  ; 03 FD
                MOV     BH, es:[DI]             ; 26 8A 3D
                OUT     DX, AX                  ; EF
                MOV     es:[DI], BL             ; 26 88 1D
                DEC     CX                      ; 49
                JZ      SHORT eva_dl_ymaj_check ; 74 02
                JMP     SHORT eva_dl_ymaj_loop  ; EB F2
eva_dl_ymaj_check:
                CMP     SI, 0                   ; 83 FE 00
                JZ      SHORT eva_dl_ymaj_done  ; 74 43
                ROR     AH, 1                   ; D0 CC
                ROR     AH, 1                   ; D0 CC
                JC      SHORT eva_dl_ymaj_carry ; 72 1E
                MOV     BH, es:[DI]             ; 26 8A 3D
                OUT     DX, AX                  ; EF
                MOV     es:[DI], BL             ; 26 88 1D
                MOV     CX, ds:[06BEH]          ; 8B 0E BE 06
                ADD     ds:[06C2H], CX          ; 01 0E C2 06
                JNC     SHORT eva_dl_ymaj_no_carry ; 73 07
                MOV     CX, ds:[GfxContext.wTextureIdx]          ; 8B 0E BC 06
                INC     CX                      ; 41
                JMP     SHORT eva_dl_ymaj_step  ; EB C1
eva_dl_ymaj_no_carry:
                MOV     CX, ds:[GfxContext.wTextureIdx]          ; 8B 0E BC 06
                JMP     SHORT eva_dl_ymaj_step  ; EB BB
eva_dl_ymaj_carry:
                INC     DI                      ; 47
                MOV     BH, es:[DI]             ; 26 8A 3D
                OUT     DX, AX                  ; EF
                MOV     es:[DI], BL             ; 26 88 1D
                MOV     CX, ds:[06BEH]          ; 8B 0E BE 06
                ADD     ds:[06C2H], CX          ; 01 0E C2 06
                JNC     SHORT eva_dl_ymaj_no_carry2 ; 73 07
                MOV     CX, ds:[GfxContext.wTextureIdx]          ; 8B 0E BC 06
                INC     CX                      ; 41
                JMP     SHORT eva_dl_ymaj_step  ; EB A1
eva_dl_ymaj_no_carry2:
                MOV     CX, ds:[GfxContext.wTextureIdx]          ; 8B 0E BC 06
                JMP     SHORT eva_dl_ymaj_step  ; EB 9B
eva_dl_ymaj_done:
eva_dl_done:
                ; --- 0x1D43: shared epilogue. Reset GC mode 0, restore DS, RETF.
                MOV     DX, 03CEH               ; BA CE 03
                MOV     AX, 0005H               ; B8 05 00
                OUT     DX, AX                  ; EF
                POP     DS                      ; 1F
                RETF                            ; CB
eva_draw_line ENDP

; ============================================================================
; eva_put_pixel -- thin __cdecl16far wrapper that calls eva_blit_sprite_master.
; chunk:0x1D4C..0x1D65  (26 bytes; vtable slot 2).
;
; Re-stacks the 3 caller args (x, y, sprite_desc) with a zero flip-flags
; argument, then PUSH CS / near-CALL eva_blit_sprite_master @ 0x14C0
; (simulating a far call from within the same chunk segment).
;
; ABI (__cdecl16far, vtable slot):
;   [BP+06]  ushort  sprite_desc_off
;   [BP+08]  ushort  dst_x
;   [BP+0A]  ushort  dst_y
;
; The inherited plate name "put_pixel" is misleading -- the
; function is just a no-flip sprite-blit shortcut, identical to slot-35
; eva_blit_sprite but going through the full clip-aware master path.
; ============================================================================
eva_put_pixel PROC FAR
                PUSH    BP                      ; 55
                MOV     BP, SP                  ; 8B EC
                XOR     AX, AX                  ; 33 C0
                PUSH    AX                      ; 50            ; flip_flags = 0
                PUSH    WORD PTR [BP+0AH]       ; FF 76 0A
                PUSH    WORD PTR [BP+8]         ; FF 76 08
                PUSH    WORD PTR [BP+6]         ; FF 76 06
                ; TASM auto-emits PUSH CS (0Eh) when a NEAR-CALL targets
                ; a FAR PROC in the same segment -- so the source has only
                ; the CALL and the encoded bytes are 0E E8 disp16.
                CALL    eva_blit_sprite_master  ; 0E E8 61 F7
                ADD     SP, 08H                 ; 83 C4 08
                MOV     BP, SP                  ; 8B EC
                POP     BP                      ; 5D
                RETF                            ; CB
eva_put_pixel ENDP

; ============================================================================
; eva_get_pixel -- mask/blit-test row engine (register ABI).
; chunk:0x1D66..0x1E04  (159 bytes; vtable slot 0).
;
; The name "get_pixel"
; is misleading: this is actually an unrolled 8-bit-per-byte mask-blit row
; engine. Walks a chunky source byte LODSB'd from DS:SI, scans 8 bits MSB
; to LSB, and for each '1' bit writes the row's foreground byte via the
; EGA Set/Reset+bit-mask path. The function takes two flavours selected by
; the [DS:2] byte (0 -> one row body at 0x1DDD, !=0 -> another at 0x1DB5),
; with an unusual cross-flavour back-edge at 0x1DF8 -> 0x1DBA that means
; the two row paths share their inner-byte loop after the first iteration.
;
; Register ABI (no stack frame):
;   AX     foreground colour byte (CH after byte-swap)
;   BP     y row index -> shifted -> [BP+0x6F2] row LUT lookup
;   DX     x_start (chunky)
;   CL     row count
;   DS:SI  source mask byte stream (LODSB)
;   ES:DI  framebuffer ptr (recomputed each row)
;
; Trailing 2 bytes at 0x1E05..0x1E06 are mutated at entry by:
;   MOV CS:[1E05], AL  (forecolour byte snapshot)
;   MOV CS:[1E06], AH  (forecolour 2nd byte / overlay flag)
; ============================================================================
eva_get_pixel PROC FAR
                PUSH    SI                      ; 56
                PUSH    BP                      ; 55
                PUSH    DS                      ; 1E
                MOV     DI, AX                  ; 8B F8
                PUSH    ES                      ; 06
                MOV     DS, cs:[00B2H]          ; 2E 8E 1E B2 00
                MOV     ES, ds:[GfxContext.wGfxBlitDstPage] ; 8E 06 18 00
                MOV     AL, ds:[GfxContext.bText_fg_color] ; A0 00 00
                MOV     cs:[1E05H], AL          ; 2E A2 05 1E
                MOV     AH, ds:[GfxContext.bText_bg_color] ; 8A 26 01 00
                MOV     cs:[1E06H], AH          ; 2E 88 26 06 1E
                SHL     BP, 1                   ; D1 E5
                MOV     DI, ds:[BP].GfxContext.pRow_offset_lut ; 3E 8B BE F2 06
                MOV     AX, DX                  ; 8B C2
                SHR     AX, 1                   ; D1 E8
                SHR     AX, 1                   ; D1 E8
                ADD     DI, AX                  ; 03 F8
                MOV     BH, CL                  ; 8A FD         ; row count snapshot
                MOV     CX, DX                  ; 8B CA
                AND     CX, 03H                 ; 83 E1 03
                SHL     CX, 1                   ; D1 E1
                POP     DS                      ; 1F            ; restore src DS
                MOV     DX, 03CEH               ; BA CE 03
                MOV     AL, 08H                 ; B0 08
                OUT     DX, AL                  ; EE
                INC     DX                      ; 42            ; -> 03CF data
                MOV     CH, cs:[1E05H]          ; 2E 8A 2E 05 1E
                MOV     AH, 0C0H                ; B4 C0
                SHR     AH, CL                  ; D2 EC
                CMP     BYTE PTR ds:[02H], 00H  ; 80 3E 02 00 00
                JZ      SHORT eva_gp_path2      ; 74 28
                ; --- 0x1DB5: path 1 (DS:[2] != 0).
eva_gp_path1_row:
                LODSB                           ; AC
                MOV     BL, AL                  ; 8A D8
                MOV     CL, 08H                 ; B1 08
eva_gp_path1_bit:
                SHR     BL, 1                   ; D0 EB
                JNC     SHORT eva_gp_path1_skip ; 73 09
                MOV     AL, AH                  ; 8A C4
                OUT     DX, AL                  ; EE
                MOV     AL, es:[DI]             ; 26 8A 05
                MOV     es:[DI], CH             ; 26 88 2D
eva_gp_path1_skip:
                SHR     AH, 1                   ; D0 EC
                SHR     AH, 1                   ; D0 EC
                ADC     DI, 00H                 ; 83 D7 00
                DEC     CL                      ; FE C9
                JNZ     SHORT eva_gp_path1_bit  ; 75 E8
                ADD     DI, 4EH                 ; 83 C7 4E
                DEC     BH                      ; FE CF
                JNZ     SHORT eva_gp_path1_row  ; 75 DC
                POP     DS                      ; 1F
                POP     BP                      ; 5D
                POP     SI                      ; 5E
                RETF                            ; CB
                ; --- 0x1DDD: path 2 (DS:[2] == 0). Differs only in that
                ; the bit loop's back-edge JNZ at 0x1DF8 jumps back to the
                ; path1 bit-loop body at 0x1DBA, NOT to path2's own copy.
                ; (Compiler artefact -- the two row paths share the inner
                ; bit-loop iteration after the first byte.)
eva_gp_path2:
                LODSB                           ; AC
                MOV     BL, AL                  ; 8A D8
                MOV     CL, 08H                 ; B1 08
eva_gp_path2_bit:
                SHR     BL, 1                   ; D0 EB
                JNC     SHORT eva_gp_path2_skip ; 73 09
                MOV     AL, AH                  ; 8A C4
                OUT     DX, AL                  ; EE
                MOV     AL, es:[DI]             ; 26 8A 05
                MOV     es:[DI], CH             ; 26 88 2D
eva_gp_path2_skip:
                SHR     AH, 1                   ; D0 EC
                SHR     AH, 1                   ; D0 EC
                ADC     DI, 00H                 ; 83 D7 00
                DEC     CL                      ; FE C9
                JNZ     SHORT eva_gp_path1_bit  ; 75 C0  ; cross-flavour back-edge
                ADD     DI, 4EH                 ; 83 C7 4E
                DEC     BH                      ; FE CF
                JNZ     SHORT eva_gp_path2      ; 75 DC
                POP     DS                      ; 1F
                POP     BP                      ; 5D
                POP     SI                      ; 5E
                RETF                            ; CB
eva_get_pixel ENDP

; ----------------------------------------------------------------------------
; g_abEvaGetPixelForecolourSnapshot -- 2 bytes of run-time-mutated data.
; chunk:0x1E05..0x1E06.
; Loaded with DS:[00] and DS:[01] (the "forecolour bytes") at each entry
; to eva_get_pixel, then re-read mid-routine. On disk this is two zero
; bytes -- effectively a zero-initialised scratch slot. The chunk ends at
; 0x1E07 (total chunk size 7687 bytes / 0x1E07).
; ----------------------------------------------------------------------------
g_abEvaGetPixelForecolourSnapshot:
                DB      0, 0                    ; 0x1E05..0x1E06

; ============================================================================
; Glossary
;
; ABI                  application binary interface -- the register / stack /
;                      memory-layout contract callers and callees agree on.
; AC                   Attribute Controller -- the EGA/VGA register block at
;                      port 0x3C0 that programs the 16 palette registers and
;                      the screen-blank bit. Uses a flip-flop port protocol:
;                      read 0x3DA to reset, then alternating writes to 0x3C0
;                      target index / value.
; BIOS mode 0Eh        640x200x16 EGA graphics mode. The number is the AL
;                      value for INT 10h AX=000Eh, which asks the BIOS to
;                      program the CRTC, sequencer, GC, and attribute
;                      controller for 640x200x16 planar.
; Chunky pixel         "1 byte = 1 pixel value", as opposed to planar.
; CRTC                 Cathode Ray Tube Controller -- the EGA/VGA register
;                      block (port pair via BIOS data area 0040:0063) that
;                      programs screen geometry and start address.
; cs:                  segment-override prefix in assembly; forces the next
;                      memory operand to use the CS register as the segment.
; DAC                  Digital-to-Analog Converter -- the VGA-only palette
;                      stage that takes the AC's 8-bit output and looks it
;                      up in a 256 x 18-bit table for analog RGB. EGA has
;                      no DAC: its AC output (6 bits = RrGgBb) goes
;                      straight to the monitor's TTL pins. This driver
;                      writes nothing to ports 0x3C7/0x3C8/0x3C9 (the
;                      VGA-only DAC index/data ports).
; Dither               approximation of a colour by spatial averaging of two
;                      or more colours from a smaller palette. EVA uses a
;                      fixed 2x2 ordered dither between even and odd rows.
; FBOV / VROOMM        the KRONDOR.EXE overlay manager. Not used inside the
;                      chunk -- the chunk is a flat binary loaded by the
;                      separate resource-archive loader.
; GC                   Graphics Controller -- the EGA/VGA register block at
;                      port 0x3CE / 0x3CF. Mediates every CPU read/write to
;                      the framebuffer at A000:0000. See hardware primer.
; Latch register       per-plane 8-bit register inside the GC. Filled by any
;                      CPU *read* from A000h; consumed on the next *write*
;                      by write-mode 0/1 to merge with the CPU-supplied
;                      byte through the Bit Mask. Required reading because
;                      every framebuffer write in this file is preceded by
;                      a dummy read to fill the latches.
; LUT                  lookup table.
; Map Mask             Sequencer register (port 0x3C4, index 2) -- 4-bit
;                      per-plane write-enable. Bits 0..3 select planes
;                      0..3. Mode-0/2 writes only land on enabled planes.
; Mode 0 / 1 / 2       see the "EGA write modes" section above.
; MZ header            the 32-byte DOS .EXE header. The build script strips
;                      it because Vmcode.OVL chunks are flat binaries with
;                      no header at all.
; Page-aligned data    the chunk allocates a single "scratch DS" segment by
;                      adding `chunk_data_paragraphs >> 4` to the host's
;                      original DS at init time. The result lives in
;                      cs:[0x00B2] and is the source of all DS:[...] state.
; Planar pixel         "4 planes x 1 bit per pixel per plane", packed 8
;                      pixels per byte (MSB = leftmost). The EGA / VGA
;                      framebuffer at A000h is planar in 4-bpp modes.
; PROC FAR / PROC NEAR TASM directives that tell the assembler to emit
;                      RETF (CB) or RETN (C3) when it sees a bare `RET`.
; Set/Reset            GC index 0; 4-bit colour used in mode-0 writes when
;                      Enable-Set/Reset (GC index 1) selects that plane.
; SOA                  struct-of-arrays. Per-row / per-plane state in this
;                      file is split into parallel byte arrays rather than
;                      packed into a struct (era convention).
; SS / scratch SS      stack segment. Some helpers (eva_palette_find_*) use
;                      SS to index host-supplied buffers passed by pointer.
; Vmcode.OVL           the bag-of-driver overlay file in the game archive
;                      from which this chunk was extracted.
; Vsync (VRetrace)     vertical retrace -- the few-millisecond gap between
;                      the CRT finishing one frame and starting the next.
;                      eva_vsync_wait polls bit 3 of port 0x3DA for it.
; vtable               the 50-entry table at chunk:0x00BA that the host
;                      copies into its global renderer-dispatch table.
;                      Slot N at offset N*4 holds (function_offset_word,
;                      function_segment_word). The segment half is zero
;                      on disk and stamped by the host post-init.
; XLAT                 1-byte instruction `D7` -- AL = DS:[BX + AL].
;                      Every use in this file is the CS-override form
;                      `XLAT BYTE PTR CS:[BX]` (bytes `2E D7`); the
;                      indexed table lives in the code segment alongside
;                      the function, so the override redirects the read
;                      from DS to CS.
; ============================================================================

                END     _start

