; ============================================================================
; Vmcode.OVL.EGA -- EGA video driver chunk (10466 bytes, 0x28E2)
;
; Shipped with "Betrayal at Krondor" (Dynamix / Sierra, 1993). Image base
; 0000:0000.
;
; The chunk is one of eight interchangeable graphics drivers in Vmcode.ovl.
; KRONDOR.EXE loads it via the RES-archive loader, runs its init prologue
; once, then snapshots its 50-slot vtable template into the host's
; renderer-vtable for ordinary far-call dispatch.
; ----------------------------------------------------------------------------
; Layers in this file:
;   1. ega_init (0x0000..0x007C)              -- chunk initialiser, FAR.
;   2. g_wEgaBackBufferSeg / g_wEgaChunkDataSeg (0x007D..0x0080) -- DW slots.
;   3. g_apEgaVtable (0x0081..0x0148)         -- 50-slot vtable template.
;   4. g_aEgaHostCallbacks tail (0x0149..0x016C) -- 9 dead entries (REP-MOVSW
;                                                  overwritten at init).
;   5. ega_unimplemented_slot (0x016D)        -- 1-byte RETF stub.
;   6. Edge / bit mask LUTs (0x016E..0x0185)  -- 3x 8-byte DB tables.
;   7. Scratch globals (0x0186..0x0193)       -- 14-byte zero-init region.
;   8. Function bodies (0x0194..0x28E1)       -- 38 functions interleaved
;                                                 with ~7 inline data/state
;                                                 blocks (per-function LUTs,
;                                                 dispatch tables, sprite-
;                                                 state scratch, and small
;                                                 self-modifying slots; each
;                                                 announced with a banner).
;
; Assembled by SRC\DRIVERS\DRIVERS.MAK, same recipe as the CGA driver.
; ============================================================================

; ----------------------------------------------------------------------------
; What this driver is
;
; A video driver is a small code chunk the game loads on startup and calls
; every time it wants to draw something on screen. Krondor ships eight
; such drivers in Vmcode.OVL -- one per supported video card -- and picks
; the right one at runtime based on the user's "video setup" choice.
;
; This file is the EGA driver (IBM Enhanced Graphics Adapter, 1984;
; 320x200 with 16 colours in BIOS mode 0Dh). It exposes a fixed table of
; 50 entry points ("the vtable") via which the engine calls into it for
; primitives like draw-line, save-rect, present-rect, draw-sprite,
; fill-polygon, set-palette, etc. The first entry point (ega_init) is
; invoked once at startup; the host snapshots the vtable and from then
; on every render call goes through it as a FAR procedure call.
;
; Almost the entire file is rendering code: the 4 sprite-flip cores
; alone account for ~3.4 KB (~33% of the chunk). Data tables are
; small -- a couple of edge-mask LUTs and the sprite-flip dispatch
; table. State is kept in two places: ROM-side at the bottom of CS
; (chunk slots like g_wEgaBackBufferSeg), and RAM-side in a private
; "scratch DS" segment the host allocates for this chunk at init.
; ----------------------------------------------------------------------------

; ----------------------------------------------------------------------------
; About the EGA hardware (mode 0Dh)
;
; EGA (IBM Enhanced Graphics Adapter, 1984) in mode 0Dh provides:
;
;   - 320x200 pixels, 16 simultaneous colours selected from a master
;     palette of 64 (RrGgBb -- two bits per primary, sent as six TTL
;     lines straight to the monitor; the EGA has NO DAC, that's a
;     VGA-only addition).  The pixel format is 4-plane planar: each
;     pixel uses one bit in each of 4 planes -- plane 0 = Blue
;     (LSB), 1 = Green, 2 = Red, 3 = Intensity (MSB). The 4-bit
;     pixel value then indexes Attribute-Controller registers
;     AR0..AR0F to produce the 6-bit RrGgBb the monitor receives.
;     One byte at the same offset across all 4 planes therefore
;     encodes 8 pixels (the SAME 8 horizontal pixels -- each plane
;     contributes one bit to each pixel's 4-bit colour index).
;     [Source: IBM EGA TR / VGADOC EGAREGS.TXT; FreeVGA vgamem.htm.]
;
;     CRT-monitor caveat: on a real IBM 5154 the 200-line modes
;     use the VSYNC polarity to signal "RGBI" rather than "RrGgBb",
;     which clamps the visible palette to 16-of-16 regardless of
;     AR0..AR0F. A 1993 VGA-monitor user sees the full 64-of-64.
;     [Source: reenigne.org/blog ("Why the EGA can only use 16 of
;     its 64 colours in 200-line modes").]
;
;   - Stride: 40 bytes per scan-line (320px / 8px per byte). 200
;     rows. One "page" therefore occupies 40*200 = 8 000 visible
;     bytes per plane = 32 000 bytes linear across 4 byte-
;     interleaved planes. Pages are 32-KB-aligned, so the segment
;     increment between consecutive pages is `0x0200` (i.e. 8 KB
;     planar / 16-byte paragraph = 0x200; the CPU sees the 4
;     planes byte-interleaved through the same address window, so
;     one "page" is 0x2000 linear bytes = 0x200 segment units).
;     The driver caches page bases at scratch:[10]/[12]/[14]:
;       0xA000  page 0 (display-on-boot)
;       0xA200  page 1 (back buffer; NOT 0xA800)
;       0xA400  page 2 (scratch/sprite save buffer)
;     [Source: Cosmodoc EGA functions: drawPageSegment = 0xA000 +
;     page * 0x0200; corroborated by Wikipedia EGA.]
;
; Per-pixel access uses the EGA's plane-selection and bit-mask
; hardware via two I/O port pairs:
;
;   * 0x3C4..0x3C5 -- Sequencer registers (index/data) [SR0..SR4]:
;       SR0 (Reset)         -- sync/async reset bits.
;       SR1 (Clocking Mode) -- dot clock + 8/9-dot character cells.
;       SR2 (Map Mask)      -- 4 plane-enable bits (bits 3..0 =
;         planes 3..0). CPU writes only reach enabled planes. Init
;         sets this to 0x0F (all 4 planes enabled).
;       SR3 (Char Map)      -- text-mode font select (unused in 0Dh).
;       SR4 (Memory Mode)   -- bit 0 = alpha/gfx, bit 1 = Ext Mem,
;         bit 2 = Odd/Even.  BIT-2 POLARITY DISAGREEMENT: per IBM
;         EGA TR / VGADOC EGAREGS.TXT bit 2 = 1 ENABLES Odd/Even
;         addressing; per FreeVGA seqreg.htm the same bit is named
;         "O/E Dis." and 1 DISABLES it. Mode 0Dh wants pure planar,
;         so the IBM polarity sets bit 2 = 0 and the FreeVGA
;         polarity sets it = 1.  This driver does NOT reprogram
;         SR4 -- it inherits the BIOS mode-0Dh defaults.
;     [Sources: vgadoc/EGAREGS.TXT lines 102..107; FreeVGA
;     seqreg.htm SR4 description.]
;
;   * 0x3CE..0x3CF -- Graphics Controller registers (index/data)
;     [GR0..GR8]:
;       GR0 (Set/Reset)      -- per-plane "constant fill" value;
;                               substituted for CPU data when GR1
;                               enables (write mode 0).
;       GR1 (Enable S/R)     -- per-plane Set/Reset enable mask.
;       GR2 (Color Compare)  -- 4-bit reference colour for read
;                               mode 1.
;       GR3 (Data Rotate)    -- low 3 bits = right-rotate count
;         on CPU data (write modes 0/3); bits 3..4 = logical op
;         with the latches: 00=replace, 01=AND, 10=OR, 11=XOR
;         (applies in write modes 0 and 2).
;       GR4 (Read Map Sel)   -- which plane the CPU sees on read
;                               in read mode 0 (bits 1..0).
;       GR5 (Mode)           -- read mode (bit 3) + write mode
;         (bits 1..0):
;                  00 = Write Mode 0  (CPU byte through full pipe)
;                  01 = Write Mode 1  (broadcast latches -> planes)
;                  10 = Write Mode 2  (CPU low nibble -> per-plane
;                                       bit broadcast for 8 pixels)
;                  11 = Write Mode 3  (VGA-ONLY; not valid on EGA)
;       GR6 (Misc)           -- aperture mapping (mode 0Dh: 64 KB
;                               at A0000-AFFFF), graphics/alpha.
;       GR7 (Don't Care)     -- mask for read-mode-1 compare.
;       GR8 (Bit Mask)       -- per-bit "passthrough vs preserve":
;                               bit=1 in GR8 -> CPU/pipeline data
;                               wins; bit=0 -> latched value
;                               retained.  Applies in write modes
;                               0, 2, 3 (not 1).
;     [Sources: VGADOC EGAREGS.TXT; FreeVGA graphreg.htm.]
;
;   * 0x3C0 -- Attribute Controller (index AND data on the same
;     port; a HW flip-flop alternates roles). Holds 16 palette
;     regs (AR0..AR0F, 6 bits each, RrGgBb encoding) plus a few
;     control regs (AR10 mode ctrl, AR11 overscan, AR12 plane
;     enable, AR13 panning).  Reading port 0x3DA (input-status-1)
;     RESETS the flip-flop to "index" mode -- this dummy read is
;     mandatory before every AC write sequence; forgetting it is
;     the #1 EGA-programming mistake.  [Sources: VGADOC EGAREGS.TXT
;     "Port 3C0h is special..."; FreeVGA attrreg.htm.]
;
;   * 0x3DA -- Input Status 1 (read). Bit 3 = "vertical retrace
;     active"; bit 0 = "in horizontal-OR-vertical blanking". The
;     driver polls these for tear-free flips and synced palette
;     writes. The CRTC port pair is at 0x3D4/0x3D5 in colour
;     emulation; mode 0Dh uses colour. The driver fetches the
;     base address from BIOS data area 40:63 rather than hard-
;     coding the port.  [Source: VGADOC EGAREGS.TXT 3DAh entry.]
;
; EGA latches: every CPU read from the framebuffer at A000:xxxx
; LATCHES one byte per plane (4 bytes total at the same offset)
; into hardware latch registers, regardless of read mode.  The
; latches are *opaque* -- there is no I/O port that reads them.
; They feed:
;   * write-mode 1 (broadcast latches back -> the CPU data byte
;     is ignored, only the destination address matters);
;   * the "preserve" side of GR8 Bit Mask in write modes 0/2/3;
;   * the logical-op operand for GR3 in write modes 0/2.
; The latches hold their value across many writes (and across
; read-mode changes) until the next CPU read. This is the basis
; of fast rect-copy: one read at the source loads the latches,
; one write at the destination stores them in all 4 planes (write
; mode 1), `REP MOVSB` does both in one instruction.
; [Source: FreeVGA vgamem.htm "Manipulating Display Memory".]
;
; EGA WRITE-MODES this chunk uses:
;   * Mode 2 (set by init -- the chunk's default) -- the CPU byte
;     is reinterpreted: bits 3..0 become per-plane "fill" bits
;     replicated 8x across each plane, then GR8 Bit Mask gates
;     which pixel positions update (others keep latched value).
;     Lets one CPU store paint 8 horizontal pixels with one
;     colour; combined with Bit Mask you can write any subset
;     of those 8 pixels.  [Source: VGADOC EGAREGS.TXT; Abrash
;     Ch.27.]
;   * Mode 0 (sprite/glyph/chunky paths) -- CPU byte passes the
;     full 5-stage GC pipeline (rotate, Set/Reset substitute,
;     logical-op with latches, Bit Mask merge, Map Mask gate).
;     The driver typically uses it with Map Mask cycling
;     1->2->4->8 plus a constant byte to lay down per-plane
;     bitmaps (transparent sprite blits).
;   * Mode 1 (rect copy: ega_present_rect, ega_paste_rect) --
;     write data is ignored; the latches loaded by the
;     immediately-preceding read get written to all 4 planes at
;     once.
;
; Write Mode 3 is VGA-only.  This driver writes mode 0, 1, and 2
; only -- if you see `out 0x3CE, 0x?305` with `?` non-zero, it's
; not a write-mode-3 setup, it's some other GR5 bit (e.g. bit 3 =
; read mode 1).  [Source: VGADOC EGAREGS.TXT GR5 description does
; not list mode 3.]
;
; Pixel format on disk for sprites: 4 planes interleaved per row.
; A 16-pixel-wide sprite is 2 bytes per plane = 8 bytes per row,
; in plane order 0,1,2,3 (B,G,R,I).
;
; Sources for everything in this primer: IBM EGA TR, VGADOC
; EGAREGS.TXT, FreeVGA, Abrash chs 23-31, Cosmodoc EGA-functions,
; Reenigne 200-line.
; ----------------------------------------------------------------------------

; ----------------------------------------------------------------------------
; How to read this source
;
; - TASM numeric-literal parser: hex literals must begin with a
;   digit (write `0AH`, not `AH`). `H` suffix marks hex.
;
; - Single-segment chunk (`.MODEL TINY`, `.CODE` only). Code, data
;   tables, and chunk-local globals all share the same segment.
;
; - Memory accesses use one of three segments:
;     CS:  -- the chunk itself (vtable, mask LUTs, init-set chunk-
;             local slots like g_wEgaChunkDataSeg).
;     DS:  -- the chunk's "scratch DS", a private working segment
;             allocated by the host at init. Most function prologues
;             begin `MOV DS, cs:[7D]` to point DS at it.  Holds
;             runtime state.  The slots used by rendering code:
;
;               [0x10]  WORD  plane base A400 (back-buffer 2)     -- set by ega_init
;               [0x12]  WORD  plane base A200 (back-buffer 1)     -- set by ega_init
;               [0x14]  WORD  plane base A000 (display on boot)   -- set by ega_init
;               [0x16]  WORD  "back buffer A" plane base          -- HOST-POPULATED
;               [0x18]  WORD  "visible plane" base                -- HOST-POPULATED
;               [0x1D]  BYTE  monochrome-mode flag (2 = mono)     -- HOST-POPULATED
;               [0x21]  BYTE  mouse-active flag                   -- set by ega_init = 0x10
;               [0x19E] WORD  cached palette-image far-ptr offset -- ega_palette_load
;               [0x1A0] WORD  cached palette-image far-ptr seg    -- ega_palette_load
;               [0x6F2] WORD[200]  scanline-offset LUT (y*40)     -- set by ega_init
;
;             Note that the "active back-buffer" and "active visible"
;             segments the renderer actually uses are at [0x16] and
;             [0x18] -- NOT [0x10..0x14].  Slots [0x10..0x14] are the
;             *invariant* plane bases the chunk knows about (A000,
;             A200, A400); the host swaps in whichever it wants the
;             chunk to draw to/from by writing [0x16] and [0x18]
;             before invoking a render slot.  ega_vsync_wait does
;             rotate [0x12] and [0x14] when it flips the CRT
;             display address, so the meaning of those two slots
;             drifts at runtime.
;
;             For the page-segment math (0xA000 + page * 0x0200, NOT
;             0x0800), see the hardware primer above.
;     ES:  -- usually the framebuffer (A000/A200/A400 EGA planes).
;
; - Local labels inside a function are prefixed with a short
;   nickname for the enclosing function (`ega_init_*`, `ega_prf_*`
;   etc.) to avoid collisions across functions.
;
; - The 4-byte hex sequences in the right column ARE the encoded
;   instruction bytes.
; ----------------------------------------------------------------------------

                .8086
                .MODEL  TINY
                .CODE

; Shared engine graphics-context STRUC (host scratch-DS layout). TASM finds it
; via /iSRC\DRIVERS\VMCODE (see DRIVERS.MAK).
                INCLUDE gfxctx.inc

                ORG     0
                ASSUME  ds:NOTHING, es:NOTHING

; ============================================================================
; ega_init -- chunk initialiser (PROC FAR, called via the host's video_init).
; chunk:0x0000..0x007C
;
; CALLER ABI (host-side far call):
;   [BP+0x06]  ushort  chunk_data_paragraphs
;   [BP+0x08]  ushort  host_callbacks_off
;   [BP+0x0a]  ushort  host_callbacks_seg
;
; INIT SEQUENCE:
;   1. [0x00..0x18]  Copy 0x26 words (76 bytes = 19 far ptrs) from
;      DS:SI = host_callbacks_seg:host_callbacks_off into the chunk-
;      local mirror at CS:0x0121 (g_aEgaHostCallbacks). Other chunk
;      slots later CALLF [0x0121+N] through this copy.
;   2. [0x19..0x32]  Save arg [BP+6] (the "chunk_data_paragraphs"
;      count) into the slot at CS:[7F] -- misleadingly named
;      g_wEgaChunkDataSeg, but actually used later as a near-offset
;      into a 16-entry LUT @ CS:[6BC] in blit_chunky_to_mode.
;      Right-shift >>4, add caller DS, store the resulting segment
;      value into CS:[7D] -- misleadingly named g_wEgaBackBufferSeg,
;      but actually the segment of the chunk's private scratch-DS
;      block (positioned chunk_data_paragraphs/16 paragraphs past
;      the caller's DS). DS is then set to that segment for the
;      remainder of init.
;   3. [0x34]        scratch:[0x21] := 0x10 (mouse-active flag).
;   4. [0x39..0x4A]  Cache the three EGA plane-base segments the
;      driver knows about, in REVERSE order of slot number:
;        scratch:[0x14] := 0xA000  (the boot-displayed page)
;        scratch:[0x12] := 0xA200  (page 1)
;        scratch:[0x10] := 0xA400  (page 2)
;      (segment increment 0x200 = one EGA page = 0x2000 linear
;      bytes; the four planes are byte-interleaved through the
;      same aperture window).  The driver does NOT populate
;      [0x16] or [0x18] -- those are written by the host via a
;      callback table entry before the first render call, and
;      hold the "current back-buffer" and "current visible"
;      segments.  See "How to read this source" above for the
;      full scratch-DS slot map.
;   5. [0x4B..0x4F]  INT 10h AX=0Dh -- BIOS mode 0Dh (EGA 320x200,
;      16 colours of 64 on VGA monitor / 16 of 16 RGBI on 5154).
;      [Source: VGADOC VGABIOS.TXT mode 0Dh row.]
;   6. [0x50..0x62]  Build the 200-row scanline-offset LUT at
;      scratch:[0x6F2]: 200 entries of (y*40), stride 40 bytes per
;      row.  (NO bank interleave -- unlike CGA mode 4 which
;      splits even/odd rows across 0x0000 and 0x2000.)  This LUT
;      collapses `row_offset = y*40` to a single word load in the
;      blitter hot paths.
;   7. [0x63..0x70]  Program the EGA default write state for this
;      chunk's hot path:
;        OUT 0x3C4, 0x0F02  -- Sequencer SR2 (Map Mask) = 0x0F
;                              (all 4 plane writes enabled).
;        OUT 0x3CE, 0x0205  -- Graphics GR5 (Mode) = 0x02
;                              (write mode 2, read mode 0).
;      Individual blit functions temporarily switch into write
;      mode 0 or 1 and restore 0x0205 on exit.
;   8. [0x71..0x7C]  Return DX:SI = (CS, 0x0081) (vtable address),
;      AX = 2 (success indicator -- not the 0/1 the CGA driver
;      returns; the host treats AX as opaque except for 0 = fail).
;
; RETURN:
;   AX    -- 2 on success.
;   DX:SI -- CS:0x0081, far pointer to g_apEgaVtable.
; ============================================================================
_start          LABEL   BYTE
ega_init        PROC    FAR
                PUSH    BP                      ; 55
                MOV     BP, SP                  ; 8B EC
                PUSH    DS                      ; 1E
                PUSH    SI                      ; 56
                PUSH    DI                      ; 57
                MOV     DI, 0121H               ; BF 21 01  <- g_aEgaHostCallbacks
                PUSH    CS                      ; 0E
                POP     ES                      ; 07
                MOV     SI, [BP+8]              ; 8B 76 08  arg1.off (host callbacks)
                MOV     DS, [BP+0AH]            ; 8E 5E 0A  arg1.seg
                MOV     CX, 0026H               ; B9 26 00  38 words = 76 bytes
                REP     MOVSW                   ; F3 A5
                POP     DI                      ; 5F
                POP     SI                      ; 5E
                POP     DS                      ; 1F
                MOV     AX, [BP+6]              ; 8B 46 06  arg0: chunk_data_paragraphs

                MOV     cs:[007FH], AX          ; 2E A3 7F 00   stash paragraph count
                                                ;              (used later as LUT index;
                                                ;               misnamed g_wEgaChunkDataSeg)
                SHR     AX, 1                   ; D1 E8
                SHR     AX, 1                   ; D1 E8
                SHR     AX, 1                   ; D1 E8
                SHR     AX, 1                   ; D1 E8   AX = paragraphs / 16
                PUSH    DS                      ; 1E
                PUSH    DI                      ; 57
                MOV     BX, DS                  ; 8C DB
                ADD     AX, BX                  ; 03 C3   AX = caller_DS + paragraphs/16
                MOV     cs:[007DH], AX          ; 2E A3 7D 00   = scratch-DS segment
                                                ;              (misnamed g_wEgaBackBufferSeg)
                MOV     DS, AX                  ; 8E D8         DS = scratch segment

                MOV     BYTE PTR ds:[GfxContext.bActiveVgaMode], 10H ; C6 06 21 00 10   mouse_active_flag

                ; Cache the three EGA-page segment values into scratch slots.
                ; Page math: each EGA mode-0Dh page is 0x2000 linear bytes (=
                ; 8 KB planar across 4 byte-interleaved planes), so consecutive
                ; pages are 0x200 paragraphs apart -- 0xA000 + page * 0x200.
                ; [Source: Cosmodoc EGA functions.]
                MOV     AX, 0A000H              ; B8 00 A0
                MOV     ds:[GfxContext.wVgaFrontPageBase], AX          ; A3 14 00          page 0 (displayed at boot)
                MOV     AX, 0A200H              ; B8 00 A2
                MOV     ds:[GfxContext.wVgaPage2Base], AX          ; A3 12 00          page 1
                MOV     AX, 0A400H              ; B8 00 A4
                MOV     ds:[GfxContext.wVgaPage1Base], AX          ; A3 10 00          page 2

                MOV     AX, 000DH               ; B8 0D 00
                INT     10H                     ; CD 10             BIOS mode 0Dh

                ; ----- Build the EGA scanline-offset LUT into scratch:[0x6F2].
                ; 200 entries x 2 bytes; entry N = N*40 (stride 40 B/row, no
                ; bank interleave on EGA mode 0Dh, unlike CGA mode 4).
                MOV     CX, 00C8H               ; B9 C8 00          200 rows
                MOV     DI, GfxContext.pRow_offset_lut ; BF F2 06  LUT base
                MOV     AX, DS                  ; 8C D8
                MOV     ES, AX                  ; 8E C0             ES = scratch DS
                XOR     AX, AX                  ; 33 C0
                CLD                             ; FC
ega_init_lut_loop:
                STOSW                           ; AB
                ADD     AX, 0028H               ; 05 28 00          +40 each row
                LOOP    SHORT ega_init_lut_loop ; E2 FA

                ; ----- Program EGA default write state.
                ; SR2 (Map Mask) = 0x0F  -> writes affect all 4 planes.
                ; GR5 (Mode)     = 0x02  -> read-mode 0, write-mode 2
                ;                          (the chunk's hot path; the CPU
                ;                          byte becomes a per-plane fill
                ;                          and GR8 Bit Mask picks which
                ;                          of the 8 horizontal pixels in
                ;                          the addressed byte update).
                MOV     DX, 03C4H               ; BA C4 03         Sequencer index port
                MOV     AX, 0F02H               ; B8 02 0F         AL=02 (idx SR2), AH=0F (Map Mask)
                OUT     DX, AX                  ; EF               (16-bit OUT writes idx,then data)
                MOV     DX, 03CEH               ; BA CE 03         Graphics Controller index port
                MOV     AX, 0205H               ; B8 05 02         AL=05 (idx GR5), AH=02 (Mode=wm2)
                OUT     DX, AX                  ; EF

                MOV     DX, CS                  ; 8C CA
                MOV     SI, 0081H               ; BE 81 00          DX:SI = &g_apEgaVtable
                MOV     AX, 0002H               ; B8 02 00          AX=2 (success)
                POP     DI                      ; 5F
                POP     DS                      ; 1F
                POP     BP                      ; 5D
                RETF                            ; CB
ega_init        ENDP

; ============================================================================
; Chunk-local state slots @ 0x007D / 0x007F, set by ega_init, read by every
; other function via CS-relative loads. These names are MISLEADING -- the actual
; semantics:
;
;   g_wEgaBackBufferSeg @ 0x7D
;     NOT the back-buffer segment.  Actually the SEGMENT VALUE OF THE
;     SCRATCH-DS BLOCK that this chunk owns (caller's DS + chunk_data /
;     16). Most function prologues do `MOV DS, cs:[7D]` to point DS at
;     this scratch region.  The real back-buffer-plane segment is stored
;     IN the scratch region at offset 0x16 ("back buffer A") and 0x18
;     ("visible plane") -- both populated by the host, not by ega_init.
;
;   g_wEgaChunkDataSeg @ 0x7F
;     NOT a segment.  Actually a PARAGRAPH COUNT (saved verbatim from
;     [BP+6] in ega_init), used later as a near-offset into the
;     CS-resident 16-entry "chunky-to-mode" dither LUT @ CS:[06BC]
;     (ega_blit_chunky_to_mode reads `ss:[6BC + cs:[7F]]`).  The "Seg"
;     suffix is a misnomer.
;
; UNLIKE the CGA driver, these slots do NOT alias instruction bytes
; inside ega_init -- the EGA prologue ends at 0x7C with RETF, so the
; 4 bytes here are pure data storage.
; ============================================================================
g_wEgaBackBufferSeg:
                DW      0                       ; 00 00  := caller_DS + chunk_data_paragraphs/16
g_wEgaChunkDataSeg:
                DW      0                       ; 00 00  := chunk_data_paragraphs (LUT index)

; ----------------------------------------------------------------------------
; ===== VTABLE + CALLBACK COPY REGION =====
; ----------------------------------------------------------------------------
g_apEgaVtable   LABEL   DWORD
                DW      0,      0               ; slot  0 -- NULL (0x081)
                DW      0102EH, 0               ; slot  1 -- ega_blit_glyph_row (0x085)
                DW      008B4H, 0               ; slot  2 -- ega_draw_line (0x089)
                DW      01014H, 0               ; slot  3 -- ega_blit_sprite_noflip (0x08D)
                DW      0131EH, 0               ; slot  4 -- ega_present_rect (0x091)
                DW      010DEH, 0               ; slot  5 -- ega_save_rect (0x095)
                DW      0116CH, 0               ; slot  6 -- ega_query_sprite_buffer_size (0x099)
                DW      01190H, 0               ; slot  7 -- ega_paste_rect (0x09D)
                DW      012D7H, 0               ; slot  8 -- ega_vsync_wait (0x0A1)
                DW      0016DH, 0               ; slot  9 -- ega_unimplemented_slot (0x0A5)
                DW      00269H, 0               ; slot 10 -- ega_pixel_run_fill (0x0A9)
                DW      00194H, 0               ; slot 11 -- ega_pixel_run_fill_dithered (0x0AD)
                DW      0016DH, 0               ; slot 12 -- ega_unimplemented_slot (0x0B1)
                DW      00DB7H, 0               ; slot 13 -- ega_image_install (0x0B5)
                DW      00DF8H, 0               ; slot 14 -- ega_image_decode (0x0B9)
                DW      0016DH, 0               ; slot 15 -- ega_unimplemented_slot (0x0BD)
                DW      0040DH, 0               ; slot 16 -- ega_blit_chunky_to_mode (0x0C1)
                DW      0138DH, 0               ; slot 17 -- ega_blit_chunky_to_ega (0x0C5)
                DW      0016DH, 0               ; slot 18 -- ega_unimplemented_slot (0x0C9)
                DW      0016DH, 0               ; slot 19 -- ega_unimplemented_slot (0x0CD)
                DW      00D93H, 0               ; slot 20 -- ega_palette_load (0x0D1)
                DW      01225H, 0               ; slot 21 -- ega_getpixel (0x0D5)
                DW      0129AH, 0               ; slot 22 -- ega_putpixel (0x0D9)
                DW      0016DH, 0               ; slot 23 -- ega_unimplemented_slot (0x0DD)
                DW      0286DH, 0               ; slot 24 -- ega_slot24_retf_stub (0x0E1)
                DW      0286EH, 0               ; slot 25 -- ega_palette_set_one (0x0E5)
                DW      02897H, 0               ; slot 26 -- ega_palette_set_synced (0x0E9)
                DW      00ABAH, 0               ; slot 27 -- ega_polygon_span_fill (0x0ED)
                DW      0016DH, 0               ; slot 28 -- ega_unimplemented_slot (0x0F1)
                DW      014C4H, 0               ; slot 29 -- ega_blit_sprite_master (0x0F5)
                DW      0236EH, 0               ; slot 30 -- ega_blit_stretched (0x0F9)
                DW      02406H, 0               ; slot 31 -- ega_sprite_cache_upload_dead (0x0FD)
                DW      0249BH, 0               ; slot 32 -- ega_sprite_state_reset (0x101)
                DW      024A2H, 0               ; slot 33 -- ega_blit_sprite_chunky_shifted (0x105)
                DW      0016DH, 0               ; slot 34 -- ega_unimplemented_slot (0x109)
                DW      0016DH, 0               ; slot 35 -- ega_unimplemented_slot (0x10D)
                DW      006F7H, 0               ; slot 36 -- ega_blit_glyph_pattern (0x111)
                DW      002F5H, 0               ; slot 37 -- ega_blit_stretched_alt (0x115)
                DW      00854H, 0               ; slot 38 -- ega_blit_byte_run_with_mask (0x119)
                DW      0,      0               ; slot 39 -- NULL (0x11D)
                DW      0016DH, 0               ; slot 40 -- ega_unimplemented_slot (0x121)
                DW      0016DH, 0               ; slot 41 -- ega_unimplemented_slot (0x125)
                DW      0016DH, 0               ; slot 42 -- ega_unimplemented_slot (0x129)
                DW      0016DH, 0               ; slot 43 -- ega_unimplemented_slot (0x12D)
                DW      0016DH, 0               ; slot 44 -- ega_unimplemented_slot (0x131)
                DW      0016DH, 0               ; slot 45 -- ega_unimplemented_slot (0x135)
                DW      0016DH, 0               ; slot 46 -- ega_unimplemented_slot (0x139)
                DW      0016DH, 0               ; slot 47 -- ega_unimplemented_slot (0x13D)
                DW      0016DH, 0               ; slot 48 -- ega_unimplemented_slot (0x141)
                DW      0016DH, 0               ; slot 49 -- ega_unimplemented_slot (0x145)

; ----------------------------------------------------------------------------
; g_aEgaHostCallbacks tail -- chunk:0x0149..0x016C (9 entries x 4 = 36 bytes).
;
; The host_callbacks region is 76 bytes (19 entries) starting at 0x0121.
; The first 10 entries (0x0121..0x0148) overlap with vtable slots 40..49
; (already emitted above). The remaining 9 entries are here, immediately
; before the RETF stub at 0x016D.
;
; On disk these slots are all (016DH, 0) — the offset of ega_unimplemented_slot.
; At runtime the chunk init prologue REP MOVSW overwrites them with the host
; service-callback far pointers.
; ----------------------------------------------------------------------------
                DW      016DH,  0               ; #10 dead-past-vtable (0x149)
                DW      016DH,  0               ; #11 dead-past-vtable (0x14D)
                DW      016DH,  0               ; #12 dead-past-vtable (0x151)
                DW      016DH,  0               ; #13 dead-past-vtable (0x155)
                DW      016DH,  0               ; #14 dead-past-vtable (0x159)
                DW      016DH,  0               ; #15 dead-past-vtable (0x15D)
                DW      016DH,  0               ; #16 dead-past-vtable (0x161)
                DW      016DH,  0               ; #17 dead-past-vtable (0x165)
                DW      016DH,  0               ; #18 dead-past-vtable (0x169)

; ============================================================================
; ega_unimplemented_slot -- 1-byte RETF stub.
; chunk:0x016D
;
; The default vtable slot target. Every vtable slot the EGA driver
; does not implement points here. Single-byte function (CB = RETF).
; ============================================================================
ega_unimplemented_slot PROC FAR
                RETF                            ; CB
ega_unimplemented_slot ENDP

; ============================================================================
; EGA edge-mask LUTs -- chunk:0x016E..0x0185 (24 bytes total).
;
; Three 8-byte tables used by span / rect / line / sprite routines to
; mask off the partial-byte ends of pixel runs that span 8 pixels per
; byte in EGA mode 0Dh.
;
;   g_abEgaRightEdgeMask  (0x016E)  -- keep low 8-N bits of last byte
;                                       (entry N = (1<<(8-N)) - 1)
;   g_abEgaLeftEdgeMask   (0x0176)  -- keep high N bits of first byte
;                                       (entry N = ~((1<<(8-N))-1) & 0xFF)
;   g_abEgaBitMaskTable   (0x017E)  -- single-bit-mask for pixel N within
;                                       a byte (1<<(7-N))
; ============================================================================
g_abEgaRightEdgeMask:
                DB      0FFH, 07FH, 03FH, 01FH, 00FH, 007H, 003H, 001H   ; 0x016E
g_abEgaLeftEdgeMask:
                DB      000H, 080H, 0C0H, 0E0H, 0F0H, 0F8H, 0FCH, 0FEH   ; 0x0176
g_abEgaBitMaskTable:
                DB      080H, 040H, 020H, 010H, 008H, 004H, 002H, 001H   ; 0x017E

; ============================================================================
; Chunk-local scratch globals -- chunk:0x0186..0x0193 (14 bytes).
;
; Initialised to mostly zero on disk; one constant byte (0x02 @ 0x18F)
; sits in the middle. Slot map (referenced via CS:[...] from various
; rendering routines):
;
;   0x0186  WORD   dither colour pair (lo/hi byte = even/odd cols);
;                  written by ega_pixel_run_fill_dithered prologue.
;   0x0188  WORD   inner-loop pixel counter for stretched / glyph_compare /
;                  blit_chunky_to_mode (decremented each output byte).
;   0x018A  WORD   plane 0+1 accumulator (BL/BH) for partial-byte flush.
;   0x018C  WORD   plane 2+3 accumulator (CL/CH).
;   0x018E  BYTE   GC Bit Mask byte being built up (1 bit per pixel).
;   0x018F  BYTE   next-byte loop limit (live for blit_chunky_to_mode and
;                  glyph_compare; on-disk value 0x02 happens to match the
;                  initial value the prologue would write anyway).
;   0x0190  WORD   source offset (glyph_pattern self-modifying slot).
;   0x0192  WORD   source segment (glyph_pattern self-modifying slot).
; ============================================================================
                DB      000H, 000H, 000H, 000H, 000H, 000H, 000H, 000H, 000H, 002H, 000H, 000H, 000H, 000H ; 0x0186

; ============================================================================
; ===== FUNCTION BODIES =====
;
; 38 functions follow. A handful of small data blocks are interleaved between
; them (rendering LUTs, sprite-state slots, alignment padding); each is
; announced with a banner. Every function carries a plate naming it and its
; [start..end) byte range.
; ============================================================================

; ============================================================================
; ega_pixel_run_fill_dithered @ 0x0194..0x0269 (213 bytes)
;
; FAR entry from vtable slot 11. Reached with specific register state set
; up by the caller (no C prologue):
;   AX = (low_byte hi_byte) -- two checkerboard colours
;   BX = pixel x position
;   CX = pixel run length
;   DX = parity flag (bit 0 = swap colours)
;   ES:DI = framebuffer dst-row base
;   DS = scratch DS
; Uses left/right edge mask LUTs at CS:[16E]/CS:[176] for the byte-aligned
; head and tail. The middle is REP STOSW with alternating colour bytes.
; Shares its RETF at 0x0268 with the neighbouring pixel_run_fill function.
; ============================================================================
ega_pixel_run_fill_dithered PROC FAR
                MOV     AH, AL                          ; 8A E0
                SHR     AH, 1                           ; D0 EC
                SHR     AH, 1                           ; D0 EC
                SHR     AH, 1                           ; D0 EC
                SHR     AH, 1                           ; D0 EC      AH = AL >> 4
                AND     DX, 1                           ; 83 E2 01
                JZ      SHORT @@prfd_no_swap            ; 74 02
                XCHG    AL, AH                          ; 86 C4      swap colours on odd parity
@@prfd_no_swap:
                MOV     cs:[186H], AX                   ; 2E A3 86 01    save colour pair
                MOV     AX, BX                          ; 8B C3
                SHR     AX, 1                           ; D1 E8
                SHR     AX, 1                           ; D1 E8
                SHR     AX, 1                           ; D1 E8       AX = x/8
                ADD     DI, AX                          ; 03 F8
                AND     BX, 7                           ; 83 E3 07
                MOV     DX, BX                          ; 8B D3
                ADD     DX, CX                          ; 03 D1
                CMP     DX, 8                           ; 83 FA 08
                JNL     @@prfd_multi_byte               ; 7D 30
                ; --- entire run fits in one byte ---
                MOV     CX, cs:[186H]                   ; 2E 8B 0E 86 01
                MOV     AH, cs:[BX+16EH]                ; 2E 8A A7 6E 01 left edge mask
                MOV     BL, DL                          ; 8A DA
                AND     AH, cs:[BX+176H]                ; 2E 22 A7 76 01 & right edge mask
                MOV     BL, AH                          ; 8A DC
                AND     AH, 0AAH                        ; 80 E4 AA       even cols
                MOV     AL, 8                           ; B0 08
                MOV     DX, 03CEH                       ; BA CE 03
                OUT     DX, AX                          ; EF             Bit Mask
                INC     DX                              ; 42
                MOV     AL, es:[DI]                     ; 26 8A 05       latch
                MOV     es:[DI], CL                     ; 26 88 0D       colour 0
                MOV     AL, BL                          ; 8A C3
                AND     AL, 55H                         ; 24 55          odd cols
                OUT     DX, AL                          ; EE
                MOV     AL, es:[DI]                     ; 26 8A 05
                MOV     AL, CH                          ; 8A C5
                STOSB                                   ; AA             colour 1
                JMP     SHORT ega_prfd_retf             ; EB 79
@@prfd_multi_byte:
                MOV     DX, 8                           ; BA 08 00
                SUB     DX, BX                          ; 2B D3       DX = bits in first byte
                SUB     CX, DX                          ; 2B CA       CX -= those
                MOV     AH, cs:[BX+16EH]                ; 2E 8A A7 6E 01 left edge mask
                MOV     DX, 03CEH                       ; BA CE 03
                MOV     AL, 8                           ; B0 08
                OUT     DX, AL                          ; EE
                INC     DX                              ; 42
                MOV     BX, cs:[186H]                   ; 2E 8B 1E 86 01
                MOV     AL, es:[DI]                     ; 26 8A 05
                MOV     AL, AH                          ; 8A C4
                AND     AL, 0AAH                        ; 24 AA
                OUT     DX, AL                          ; EE
                MOV     es:[DI], BL                     ; 26 88 1D    colour 0
                MOV     AL, es:[DI]                     ; 26 8A 05
                MOV     AL, AH                          ; 8A C4
                AND     AL, 55H                         ; 24 55
                OUT     DX, AL                          ; EE
                MOV     AL, BH                          ; 8A C7
                STOSB                                   ; AA          colour 1
                MOV     AH, CL                          ; 8A E1
                SHR     CX, 1                           ; D1 E9
                SHR     CX, 1                           ; D1 E9
                SHR     CX, 1                           ; D1 E9       CX = full bytes
                JZ      SHORT @@prfd_tail               ; 74 1D
                MOV     AL, 0AAH                        ; B0 AA
                OUT     DX, AL                          ; EE
                MOV     es:[DI], BL                     ; 26 88 1D
                SHR     AL, 1                           ; D0 E8
                OUT     DX, AL                          ; EE
                MOV     AL, es:[DI]                     ; 26 8A 05
                MOV     AL, BH                          ; 8A C7
                MOV     DH, AH                          ; 8A F4
                MOV     AH, AL                          ; 8A E0
                SHR     CX, 1                           ; D1 E9
                REP     STOSW                           ; F3 AB
                MOV     AH, DH                          ; 8A E6
                MOV     DH, 3                           ; B6 03
                JNC     SHORT @@prfd_tail               ; 73 01
                STOSB                                   ; AA          odd tail byte
@@prfd_tail:
                MOV     CL, AH                          ; 8A CC
                XCHG    CX, BX                          ; 87 CB
                AND     BX, 7                           ; 83 E3 07
                JZ      SHORT ega_prfd_retf             ; 74 1B
                MOV     AH, cs:[BX+176H]                ; 2E 8A A7 76 01 right edge mask
                MOV     AL, AH                          ; 8A C4
                AND     AL, 0AAH                        ; 24 AA
                OUT     DX, AL                          ; EE
                MOV     AL, es:[DI]                     ; 26 8A 05
                MOV     es:[DI], CL                     ; 26 88 0D
                MOV     AL, AH                          ; 8A C4
                AND     AL, 55H                         ; 24 55
                OUT     DX, AL                          ; EE
                MOV     AL, es:[DI]                     ; 26 8A 05
                MOV     es:[DI], CH                     ; 26 88 2D
ega_prfd_retf:                                          ; shared retf addr 0x0268
                RETF                                    ; CB
ega_pixel_run_fill_dithered ENDP

; ============================================================================
; ega_pixel_run_fill @ 0x0269..0x02F5 (140 bytes)
;
; FAR entry from vtable slot 10. Reached with the SAME register-passed ABI
; as the dithered variant (AL = colour, BX = x, CX = run, DX = ignored,
; ES:DI = framebuffer dst-row base, DS = scratch DS).
;
; Two epilogue tricks shared with the neighbouring dithered function:
;   * On CX<=0, falls through to JNG into the RETF at 0x0268 (last byte of
;     ega_pixel_run_fill_dithered).
;   * On AL high nibble != 0 (i.e. caller packed a second colour in bits
;     4..7), TEST AL,0F0H is non-zero so the JZ falls through and the JMP
;     dispatches back into ega_pixel_run_fill_dithered's entry at 0x0194
;     -- AL/AH are then treated as two checkerboard colours.
;
; Otherwise it's a flat run-fill: head byte via Bit Mask, middle bytes via
; REP STOSB with Bit Mask = FF, tail byte via Bit Mask.
; ============================================================================
ega_pixel_run_fill PROC FAR
                OR      CX, CX                          ; 0B C9
                JNG     SHORT ega_prfd_retf             ; 7E FB        return via dithered's retf
                TEST    AL, 0F0H                        ; A8 F0
                JZ      SHORT @@prf_solid               ; 74 03
                JMP     ega_pixel_run_fill_dithered     ; E9 20 FF     dispatch to dithered path
@@prf_solid:
                MOV     DX, AX                          ; 8B D0        save colour
                MOV     AX, BX                          ; 8B C3
                SHR     AX, 1                           ; D1 E8
                SHR     AX, 1                           ; D1 E8
                SHR     AX, 1                           ; D1 E8
                ADD     DI, AX                          ; 03 F8
                AND     BX, 7                           ; 83 E3 07
                MOV     AX, DX                          ; 8B C2
                MOV     DX, BX                          ; 8B D3
                ADD     DX, CX                          ; 03 D1
                CMP     DX, 8                           ; 83 FA 08
                JNL     SHORT @@prf_multi               ; 7D 1E
                ; --- run fits in one byte ---
                MOV     AH, cs:[BX+16EH]                ; 2E 8A A7 6E 01
                MOV     BL, DL                          ; 8A DA
                MOV     CL, cs:[BX+176H]                ; 2E 8A 8F 76 01
                AND     AH, CL                          ; 22 E1
                MOV     BL, AL                          ; 8A D8
                MOV     AL, 8                           ; B0 08
                MOV     DX, 03CEH                       ; BA CE 03
                OUT     DX, AX                          ; EF           Bit Mask
                MOV     AL, es:[DI]                     ; 26 8A 05     latch
                MOV     es:[DI], BL                     ; 26 88 1D     write
                JMP     SHORT @@prf_done                ; EB 48
@@prf_multi:
                MOV     DX, 8                           ; BA 08 00
                SUB     DX, BX                          ; 2B D3
                SUB     CX, DX                          ; 2B CA
                MOV     AH, cs:[BX+16EH]                ; 2E 8A A7 6E 01
                MOV     BL, AL                          ; 8A D8
                MOV     AL, 8                           ; B0 08
                MOV     DX, 03CEH                       ; BA CE 03
                OUT     DX, AX                          ; EF           Bit Mask for head
                MOV     AL, es:[DI]                     ; 26 8A 05
                MOV     AL, BL                          ; 8A C3
                STOSB                                   ; AA
                PUSH    CX                              ; 51
                AND     CX, 0FFF8H                      ; 83 E1 F8
                JZ      SHORT @@prf_no_middle           ; 74 12
                SHR     CX, 1                           ; D1 E9
                SHR     CX, 1                           ; D1 E9
                SHR     CX, 1                           ; D1 E9        CX = full bytes
                MOV     AX, 0FF08H                      ; B8 08 FF     Bit Mask = FF
                OUT     DX, AX                          ; EF
                MOV     AL, BL                          ; 8A C3
@@prf_middle:
                MOV     AH, es:[DI]                     ; 26 8A 25
                STOSB                                   ; AA
                LOOP    SHORT @@prf_middle              ; E2 FA
@@prf_no_middle:
                MOV     CL, BL                          ; 8A CB
                POP     BX                              ; 5B
                AND     BX, 7                           ; 83 E3 07
                JZ      SHORT @@prf_done                ; 74 0E
                MOV     AH, cs:[BX+176H]                ; 2E 8A A7 76 01 right edge mask
                MOV     AL, 8                           ; B0 08
                OUT     DX, AX                          ; EF
                MOV     AL, es:[DI]                     ; 26 8A 05
                MOV     es:[DI], CL                     ; 26 88 0D
@@prf_done:
ega_prf_retf:                                            ; shared retf addr 0x02F4
                RETF                                    ; CB
ega_pixel_run_fill ENDP

; ============================================================================
; ega_blit_stretched_alt @ 0x02F5..0x040D (280 bytes)
;
; FAR. Source-pattern-driven stretched blit. Reads source patterns at
; DS:[BP], walks one source bit at a time across CX pixels, packing the
; 4 plane masks into cs:[18A] / cs:[18C] (two word accumulators -- planes
; 0+1 in BL/BH and planes 2+3 in CL/CH) plus cs:[18E] (one byte: the GC
; Bit Mask byte being built up, 1 bit per pixel). When CH bit-mask wraps
; (every 8 pixels) the accumulators are flushed: GC Bit Mask written from
; cs:[18E], then one byte per plane to ES:DI cycling Map Mask 1->8 via
; Sequencer reg 2.
;
; Register-passed ABI: AX/BX/CX/DX/SI/DI/ES/DS/BP set up by caller (no
; standard C prologue). Shares the JZ short-circuit with neighbouring
; pixel_run_fill at 0x02F4.
; ============================================================================
ega_blit_stretched_alt PROC FAR
                MOV     BX, DX                          ; 8B DA
                AND     BX, 7                           ; 83 E3 07
                SHR     DX, 1                           ; D1 EA
                SHR     DX, 1                           ; D1 EA
                SHR     DX, 1                           ; D1 EA
                ADD     DI, DX                          ; 03 FA
                XOR     DX, DX                          ; 33 D2
                MOV     cs:[18AH], DX                   ; 2E 89 16 8A 01
                MOV     cs:[18CH], DX                   ; 2E 89 16 8C 01
                MOV     cs:[18EH], DL                   ; 2E 88 16 8E 01
                DEC     CX                              ; 49
                JZ      SHORT ega_prf_retf              ; 74 DE   shared epilogue
                MOV     cs:[188H], CX                   ; 2E 89 0E 88 01
                PUSH    AX                              ; 50
                SHL     AX, 1                           ; D1 E0
                SHL     AX, 1                           ; D1 E0
                ADD     SI, AX                          ; 03 F0
                MOV     CL, BL                          ; 8A CB
                MOV     CH, 80H                         ; B5 80
                SHR     CH, CL                          ; D2 ED       initial bit mask
                POP     DX                              ; 5A
@@bsa_pix:
                MOV     BX, [BP+0]                      ; 8B 5E 00
                MOV     CL, BL                          ; 8A CB
                SHR     BX, 1                           ; D1 EB
                SHR     BX, 1                           ; D1 EB
                SHR     BX, 1                           ; D1 EB
                ADD     BX, SI                          ; 03 DE
                MOV     AL, 80H                         ; B0 80
                AND     CL, 7                           ; 80 E1 07
                SHR     AL, CL                          ; D2 E8
                MOV     CL, AL                          ; 8A C8
                TEST    [BX], CL                        ; 84 0F
                JNZ     SHORT @@bsa_flush               ; 75 35
                OR      cs:[18EH], CH                   ; 2E 08 2E 8E 01
                MOV     AX, cs:[18AH]                   ; 2E A1 8A 01
                SUB     BX, DX                          ; 2B DA
                TEST    [BX], CL                        ; 84 0F
                JZ      SHORT @@bsa_1                   ; 74 02
                OR      AL, CH                          ; 0A C5
@@bsa_1:
                SUB     BX, DX                          ; 2B DA
                TEST    [BX], CL                        ; 84 0F
                JZ      SHORT @@bsa_2                   ; 74 02
                OR      AH, CH                          ; 0A E5
@@bsa_2:
                MOV     cs:[18AH], AX                   ; 2E A3 8A 01
                MOV     AX, cs:[18CH]                   ; 2E A1 8C 01
                SUB     BX, DX                          ; 2B DA
                TEST    [BX], CL                        ; 84 0F
                JZ      SHORT @@bsa_3                   ; 74 02
                OR      AL, CH                          ; 0A C5
@@bsa_3:
                SUB     BX, DX                          ; 2B DA
                TEST    [BX], CL                        ; 84 0F
                JZ      SHORT @@bsa_4                   ; 74 02
                OR      AH, CH                          ; 0A E5
@@bsa_4:
                MOV     cs:[18CH], AX                   ; 2E A3 8C 01
@@bsa_flush:
                ADD     BP, 2                           ; 83 C5 02
                ROR     CH, 1                           ; D0 CD
                JC      SHORT @@bsa_byte                ; 72 09
                DEC     WORD PTR cs:[188H]              ; 2E FF 0E 88 01
                JG      SHORT @@bsa_pix                 ; 7F A3
                JMP     SHORT @@bsa_tail                ; EB 54
@@bsa_byte:
                PUSH    DX                              ; 52
                MOV     DX, 03CFH                       ; BA CF 03
                MOV     AL, cs:[18EH]                   ; 2E A0 8E 01
                OR      AL, AL                          ; 0A C0
                JZ      SHORT @@bsa_no_byte             ; 74 2D
                CMP     AL, 0FFH                        ; 3C FF
                JZ      SHORT @@bsa_skip_latch          ; 74 03
                MOV     AH, es:[DI]                     ; 26 8A 25
@@bsa_skip_latch:
                OUT     DX, AL                          ; EE
                MOV     BX, cs:[18AH]                   ; 2E 8B 1E 8A 01
                MOV     DX, 03C5H                       ; BA C5 03
                MOV     AL, 8                           ; B0 08
                OUT     DX, AL                          ; EE
                MOV     es:[DI], BL                     ; 26 88 1D
                SHR     AL, 1                           ; D0 E8
                OUT     DX, AL                          ; EE
                MOV     es:[DI], BH                     ; 26 88 3D
                MOV     BX, cs:[18CH]                   ; 2E 8B 1E 8C 01
                SHR     AL, 1                           ; D0 E8
                OUT     DX, AL                          ; EE
                MOV     es:[DI], BL                     ; 26 88 1D
                SHR     AL, 1                           ; D0 E8
                OUT     DX, AL                          ; EE
                MOV     es:[DI], BH                     ; 26 88 3D
@@bsa_no_byte:
                INC     DI                              ; 47
                XOR     AX, AX                          ; 33 C0
                MOV     cs:[18AH], AX                   ; 2E A3 8A 01
                MOV     cs:[18CH], AX                   ; 2E A3 8C 01
                MOV     cs:[18EH], AL                   ; 2E A2 8E 01
                POP     DX                              ; 5A
                DEC     WORD PTR cs:[188H]              ; 2E FF 0E 88 01
                JNG     SHORT @@bsa_retf                ; 7E 03
                JMP     @@bsa_pix                       ; E9 4E FF
@@bsa_retf:
                RETF                                    ; CB
@@bsa_tail:
                MOV     AL, es:[DI]                     ; 26 8A 05
                MOV     DX, 03CFH                       ; BA CF 03
                MOV     AL, cs:[18EH]                   ; 2E A0 8E 01
                OUT     DX, AL                          ; EE
                MOV     BX, cs:[18AH]                   ; 2E 8B 1E 8A 01
                MOV     DX, 03C5H                       ; BA C5 03
                MOV     AL, 8                           ; B0 08
                OUT     DX, AL                          ; EE
                MOV     es:[DI], BL                     ; 26 88 1D
                SHR     AL, 1                           ; D0 E8
                OUT     DX, AL                          ; EE
                MOV     es:[DI], BH                     ; 26 88 3D
                MOV     BX, cs:[18CH]                   ; 2E 8B 1E 8C 01
                SHR     AL, 1                           ; D0 E8
                OUT     DX, AL                          ; EE
                MOV     es:[DI], BL                     ; 26 88 1D
                SHR     AL, 1                           ; D0 E8
                OUT     DX, AL                          ; EE
                MOV     es:[DI], BH                     ; 26 88 3D
                RETF                                    ; CB
ega_blit_stretched_alt ENDP

; ============================================================================
; ega_blit_chunky_to_mode @ 0x040D..0x0463 (86 bytes; entry point only,
; falls through into ega_blit_glyph_compare at 0x0463)
;
; FAR entry point reached from vtable slot 16. Reads a per-mode dither
; offset from a CS-local 16-byte LUT @ CS:[06BC + chunk_state_seg],
; saves the next-byte loop limit to CS:[018F], then sets up shared state
; @ CS:[018A], CS:[018C], CS:[018E], CS:[0188] used by the fall-through
; glyph-compare loop. The path eventually returns via the RETF inside
; ega_blit_glyph_compare around 0x06F6.
; ============================================================================
ega_blit_chunky_to_mode LABEL FAR
                MOV     BX, 06BCH                       ; BB BC 06    LUT offset
                ADD     BX, cs:[7FH]                    ; 2E 03 1E 7F 00
                MOV     BL, ss:[BX]                     ; 36 8A 1F
                INC     BL                              ; FE C3
                MOV     cs:[18FH], BL                   ; 2E 88 1E 8F 01
                MOV     BX, DX                          ; 8B DA
                AND     BX, 7                           ; 83 E3 07
                SHR     DX, 1                           ; D1 EA
                SHR     DX, 1                           ; D1 EA
                SHR     DX, 1                           ; D1 EA
                ADD     DI, DX                          ; 03 FA
                XOR     DX, DX                          ; 33 D2
                MOV     cs:[18AH], DX                   ; 2E 89 16 8A 01
                MOV     cs:[18CH], DX                   ; 2E 89 16 8C 01
                MOV     cs:[18EH], DL                   ; 2E 88 16 8E 01
                DEC     CX                              ; 49
                MOV     cs:[188H], CX                   ; 2E 89 0E 88 01
                PUSH    AX                              ; 50
                SHL     AX, 1                           ; D1 E0
                SHL     AX, 1                           ; D1 E0
                ADD     SI, AX                          ; 03 F0
                MOV     CL, BL                          ; 8A CB
                MOV     CH, 80H                         ; B5 80
                SHR     CH, CL                          ; D2 ED
                POP     DX                              ; 5A
ega_glyph_compare_loop_head:                            ; 0x0451 - branch target from glyph_compare loop
                MOV     BX, [BP+0]                      ; 8B 5E 00
                MOV     CL, BL                          ; 8A CB
                SHR     BX, 1                           ; D1 EB
                SHR     BX, 1                           ; D1 EB
                SHR     BX, 1                           ; D1 EB
                ADD     BX, SI                          ; 03 DE
                MOV     AL, 80H                         ; B0 80
                AND     CL, 7                           ; 80 E1 07
                ; -- fall through into ega_blit_glyph_compare at 0x0463 --

; ============================================================================
; ega_blit_glyph_compare @ 0x0463..0x06F7 (660 bytes)
;
; FAR body that the chunky_to_mode prologue at 0x040D falls through into.
; Together they form the glyph-comparator function: walks a source byte
; pattern; for each set bit, accumulates 4 plane bytes by sampling DS:[BX]
; / DS:[BX-DX] / DS:[BX-2DX] / DS:[BX-3DX] etc. Two big code-bodies
; (initial-byte path at 0x0463 and second-byte path at 0x0561) differ
; only in the AH=2 vs AH=1 comparator used to detect a colour change.
;
; Returns via RETF at 0x06F2; the 4 dead trailing bytes (0x06F3..0x06F6)
; are an alternative POP DI/POP DS/POP BP/RET tail not reached at runtime.
; ============================================================================
ega_blit_glyph_compare PROC FAR
                SHR     AL, CL                          ; D2 E8
                MOV     CL, AL                          ; 8A C8
                TEST    [BX], CL                        ; 84 0F
                JNZ     gc_04a0                        ; 75 35
                OR      cs:[18EH], CH                   ; 2E 08 2E 8E 01
                MOV     AX, cs:[18AH]                   ; 2E A1 8A 01
                SUB     BX, DX                          ; 2B DA
                TEST    [BX], CL                        ; 84 0F
                JZ      gc_047c                        ; 74 02
                OR      AL, CH                          ; 0A C5
gc_047c:
                SUB     BX, DX                          ; 2B DA
                TEST    [BX], CL                        ; 84 0F
                JZ      gc_0484                        ; 74 02
                OR      AH, CH                          ; 0A E5
gc_0484:
                MOV     cs:[18AH], AX                   ; 2E A3 8A 01
                MOV     AX, cs:[18CH]                   ; 2E A1 8C 01
                SUB     BX, DX                          ; 2B DA
                TEST    [BX], CL                        ; 84 0F
                JZ      gc_0494                        ; 74 02
                OR      AL, CH                          ; 0A C5
gc_0494:
                SUB     BX, DX                          ; 2B DA
                TEST    [BX], CL                        ; 84 0F
                JZ      gc_049c                        ; 74 02
                OR      AH, CH                          ; 0A E5
gc_049c:
                MOV     cs:[18CH], AX                   ; 2E A3 8C 01
gc_04a0:
                ADD     BP, 2H                          ; 83 C5 02
                ROR     CH, 1                           ; D0 CD
                JC      gc_04b1                        ; 72 0A
                DEC     WORD PTR cs:[188H]              ; 2E FF 0E 88 01
                JA      ega_glyph_compare_loop_head                        ; 77 A3
                JMP     gc_05e9                        ; E9 38 01
gc_04b1:
                PUSH    DX                              ; 52
                PUSH    ES                              ; 06
                MOV     AX, 0AC00H                      ; B8 00 AC
                MOV     ES, AX                          ; 8E C0
                MOV     DX, 3CEH                        ; BA CE 03
                MOV     AX, 4H                          ; B8 04 00
                OUT     DX, AX                          ; EF
                INC     DX                              ; 42
                MOV     BL, es:[DI]                     ; 26 8A 1D
                MOV     AL, 1H                          ; B0 01
                OUT     DX, AL                          ; EE
                MOV     BH, es:[DI]                     ; 26 8A 3D
                INC     AL                              ; FE C0
                OUT     DX, AL                          ; EE
                MOV     CL, es:[DI]                     ; 26 8A 0D
                INC     AL                              ; FE C0
                OUT     DX, AL                          ; EE
                MOV     DL, es:[DI]                     ; 26 8A 15
                MOV     DH, cs:[18FH]                   ; 2E 8A 36 8F 01
                XOR     AX, AX                          ; 33 C0
                SHL     DL, 1                           ; D0 E2
                RCL     AH, 1                           ; D0 D4
                SHL     CL, 1                           ; D0 E1
                RCL     AH, 1                           ; D0 D4
                SHL     BH, 1                           ; D0 E7
                RCL     AH, 1                           ; D0 D4
                SHL     BL, 1                           ; D0 E3
                RCL     AH, 1                           ; D0 D4
                CMP     AH, DH                          ; 3A E6
                RCL     AL, 1                           ; D0 D0
                XOR     AH, AH                          ; 32 E4
                SHL     DL, 1                           ; D0 E2
                RCL     AH, 1                           ; D0 D4
                SHL     CL, 1                           ; D0 E1
                RCL     AH, 1                           ; D0 D4
                SHL     BH, 1                           ; D0 E7
                RCL     AH, 1                           ; D0 D4
                SHL     BL, 1                           ; D0 E3
                RCL     AH, 1                           ; D0 D4
                CMP     AH, DH                          ; 3A E6
                RCL     AL, 1                           ; D0 D0
                XOR     AH, AH                          ; 32 E4
                SHL     DL, 1                           ; D0 E2
                RCL     AH, 1                           ; D0 D4
                SHL     CL, 1                           ; D0 E1
                RCL     AH, 1                           ; D0 D4
                SHL     BH, 1                           ; D0 E7
                RCL     AH, 1                           ; D0 D4
                SHL     BL, 1                           ; D0 E3
                RCL     AH, 1                           ; D0 D4
                CMP     AH, DH                          ; 3A E6
                RCL     AL, 1                           ; D0 D0
                XOR     AH, AH                          ; 32 E4
                SHL     DL, 1                           ; D0 E2
                RCL     AH, 1                           ; D0 D4
                SHL     CL, 1                           ; D0 E1
                RCL     AH, 1                           ; D0 D4
                SHL     BH, 1                           ; D0 E7
                RCL     AH, 1                           ; D0 D4
                SHL     BL, 1                           ; D0 E3
                RCL     AH, 1                           ; D0 D4
                CMP     AH, DH                          ; 3A E6
                RCL     AL, 1                           ; D0 D0
                XOR     AH, AH                          ; 32 E4
                SHL     DL, 1                           ; D0 E2
                RCL     AH, 1                           ; D0 D4
                SHL     CL, 1                           ; D0 E1
                RCL     AH, 1                           ; D0 D4
                SHL     BH, 1                           ; D0 E7
                RCL     AH, 1                           ; D0 D4
                SHL     BL, 1                           ; D0 E3
                RCL     AH, 1                           ; D0 D4
                CMP     AH, DH                          ; 3A E6
                RCL     AL, 1                           ; D0 D0
                XOR     AH, AH                          ; 32 E4
                SHL     DL, 1                           ; D0 E2
                RCL     AH, 1                           ; D0 D4
                SHL     CL, 1                           ; D0 E1
                RCL     AH, 1                           ; D0 D4
                SHL     BH, 1                           ; D0 E7
                RCL     AH, 1                           ; D0 D4
                SHL     BL, 1                           ; D0 E3
                RCL     AH, 1                           ; D0 D4
                CMP     AH, DH                          ; 3A E6
                RCL     AL, 1                           ; D0 D0
                XOR     AH, AH                          ; 32 E4
                SHL     DL, 1                           ; D0 E2
                RCL     AH, 1                           ; D0 D4
                SHL     CL, 1                           ; D0 E1
                RCL     AH, 1                           ; D0 D4
                SHL     BH, 1                           ; D0 E7
                RCL     AH, 1                           ; D0 D4
                SHL     BL, 1                           ; D0 E3
                RCL     AH, 1                           ; D0 D4
                CMP     AH, DH                          ; 3A E6
                RCL     AL, 1                           ; D0 D0
                XOR     AH, AH                          ; 32 E4
                SHL     DL, 1                           ; D0 E2
                RCL     AH, 1                           ; D0 D4
                SHL     CL, 1                           ; D0 E1
                RCL     AH, 1                           ; D0 D4
                SHL     BH, 1                           ; D0 E7
                RCL     AH, 1                           ; D0 D4
                SHL     BL, 1                           ; D0 E3
                RCL     AH, 1                           ; D0 D4
                CMP     AH, DH                          ; 3A E6
                RCL     AL, 1                           ; D0 D0
                XOR     AH, AH                          ; 32 E4
                AND     cs:[18EH], AL                   ; 2E 20 06 8E 01
                POP     ES                              ; 07
                MOV     DX, 3CEH                        ; BA CE 03
                MOV     AL, 8H                          ; B0 08
                OUT     DX, AL                          ; EE
                INC     DX                              ; 42
                MOV     AL, cs:[18EH]                   ; 2E A0 8E 01
                OR      AL, AL                          ; 0A C0
                JZ      gc_05ce                        ; 74 2D
                CMP     AL, 0FFH                        ; 3C FF
                JZ      gc_05a8                        ; 74 03
                MOV     AH, es:[DI]                     ; 26 8A 25
gc_05a8:
                OUT     DX, AL                          ; EE
                MOV     BX, cs:[18AH]                   ; 2E 8B 1E 8A 01
                MOV     DX, 3C5H                        ; BA C5 03
                MOV     AL, 8H                          ; B0 08
                OUT     DX, AL                          ; EE
                MOV     es:[DI], BL                     ; 26 88 1D
                SHR     AL, 1                           ; D0 E8
                OUT     DX, AL                          ; EE
                MOV     es:[DI], BH                     ; 26 88 3D
                MOV     BX, cs:[18CH]                   ; 2E 8B 1E 8C 01
                SHR     AL, 1                           ; D0 E8
                OUT     DX, AL                          ; EE
                MOV     es:[DI], BL                     ; 26 88 1D
                SHR     AL, 1                           ; D0 E8
                OUT     DX, AL                          ; EE
                MOV     es:[DI], BH                     ; 26 88 3D
gc_05ce:
                INC     DI                              ; 47
                XOR     AX, AX                          ; 33 C0
                MOV     cs:[18AH], AX                   ; 2E A3 8A 01
                MOV     cs:[18CH], AX                   ; 2E A3 8C 01
                MOV     cs:[18EH], AL                   ; 2E A2 8E 01
                POP     DX                              ; 5A
                DEC     WORD PTR cs:[188H]              ; 2E FF 0E 88 01
                JNG     gc_05e8                        ; 7E 03
                JMP     ega_glyph_compare_loop_head                        ; E9 69 FE
gc_05e8:
                RETF                                    ; CB
gc_05e9:
                PUSH    ES                              ; 06
                MOV     AX, 0AC00H                      ; B8 00 AC
                MOV     ES, AX                          ; 8E C0
                MOV     DX, 3CEH                        ; BA CE 03
                MOV     AX, 4H                          ; B8 04 00
                OUT     DX, AX                          ; EF
                INC     DX                              ; 42
                MOV     BL, es:[DI]                     ; 26 8A 1D
                MOV     AL, 1H                          ; B0 01
                OUT     DX, AL                          ; EE
                MOV     BH, es:[DI]                     ; 26 8A 3D
                INC     AL                              ; FE C0
                OUT     DX, AL                          ; EE
                MOV     CL, es:[DI]                     ; 26 8A 0D
                INC     AL                              ; FE C0
                OUT     DX, AL                          ; EE
                MOV     DL, es:[DI]                     ; 26 8A 15
                XOR     AX, AX                          ; 33 C0
                SHL     DL, 1                           ; D0 E2
                RCL     AH, 1                           ; D0 D4
                SHL     CL, 1                           ; D0 E1
                RCL     AH, 1                           ; D0 D4
                SHL     BH, 1                           ; D0 E7
                RCL     AH, 1                           ; D0 D4
                SHL     BL, 1                           ; D0 E3
                RCL     AH, 1                           ; D0 D4
                CMP     AH, 2H                          ; 80 FC 02
                RCL     AL, 1                           ; D0 D0
                SHL     DL, 1                           ; D0 E2
                RCL     AH, 1                           ; D0 D4
                SHL     CL, 1                           ; D0 E1
                RCL     AH, 1                           ; D0 D4
                SHL     BH, 1                           ; D0 E7
                RCL     AH, 1                           ; D0 D4
                SHL     BL, 1                           ; D0 E3
                RCL     AH, 1                           ; D0 D4
                CMP     AH, 2H                          ; 80 FC 02
                RCL     AL, 1                           ; D0 D0
                SHL     DL, 1                           ; D0 E2
                RCL     AH, 1                           ; D0 D4
                SHL     CL, 1                           ; D0 E1
                RCL     AH, 1                           ; D0 D4
                SHL     BH, 1                           ; D0 E7
                RCL     AH, 1                           ; D0 D4
                SHL     BL, 1                           ; D0 E3
                RCL     AH, 1                           ; D0 D4
                CMP     AH, 2H                          ; 80 FC 02
                RCL     AL, 1                           ; D0 D0
                SHL     DL, 1                           ; D0 E2
                RCL     AH, 1                           ; D0 D4
                SHL     CL, 1                           ; D0 E1
                RCL     AH, 1                           ; D0 D4
                SHL     BH, 1                           ; D0 E7
                RCL     AH, 1                           ; D0 D4
                SHL     BL, 1                           ; D0 E3
                RCL     AH, 1                           ; D0 D4
                CMP     AH, 2H                          ; 80 FC 02
                RCL     AL, 1                           ; D0 D0
                SHL     DL, 1                           ; D0 E2
                RCL     AH, 1                           ; D0 D4
                SHL     CL, 1                           ; D0 E1
                RCL     AH, 1                           ; D0 D4
                SHL     BH, 1                           ; D0 E7
                RCL     AH, 1                           ; D0 D4
                SHL     BL, 1                           ; D0 E3
                RCL     AH, 1                           ; D0 D4
                CMP     AH, 2H                          ; 80 FC 02
                RCL     AL, 1                           ; D0 D0
                SHL     DL, 1                           ; D0 E2
                RCL     AH, 1                           ; D0 D4
                SHL     CL, 1                           ; D0 E1
                RCL     AH, 1                           ; D0 D4
                SHL     BH, 1                           ; D0 E7
                RCL     AH, 1                           ; D0 D4
                SHL     BL, 1                           ; D0 E3
                RCL     AH, 1                           ; D0 D4
                CMP     AH, 2H                          ; 80 FC 02
                RCL     AL, 1                           ; D0 D0
                SHL     DL, 1                           ; D0 E2
                RCL     AH, 1                           ; D0 D4
                SHL     CL, 1                           ; D0 E1
                RCL     AH, 1                           ; D0 D4
                SHL     BH, 1                           ; D0 E7
                RCL     AH, 1                           ; D0 D4
                SHL     BL, 1                           ; D0 E3
                RCL     AH, 1                           ; D0 D4
                CMP     AH, 2H                          ; 80 FC 02
                RCL     AL, 1                           ; D0 D0
                SHL     DL, 1                           ; D0 E2
                RCL     AH, 1                           ; D0 D4
                SHL     CL, 1                           ; D0 E1
                RCL     AH, 1                           ; D0 D4
                SHL     BH, 1                           ; D0 E7
                RCL     AH, 1                           ; D0 D4
                SHL     BL, 1                           ; D0 E3
                RCL     AH, 1                           ; D0 D4
                CMP     AH, 2H                          ; 80 FC 02
                RCL     AL, 1                           ; D0 D0
                AND     cs:[18EH], AL                   ; 2E 20 06 8E 01
                POP     ES                              ; 07
                MOV     DL, 0CEH                        ; B2 CE
                MOV     AL, 8H                          ; B0 08
                OUT     DX, AL                          ; EE
                INC     DX                              ; 42
                MOV     AL, es:[DI]                     ; 26 8A 05
                MOV     DX, 3CFH                        ; BA CF 03
                MOV     AL, cs:[18EH]                   ; 2E A0 8E 01
                OUT     DX, AL                          ; EE
                MOV     BX, cs:[18AH]                   ; 2E 8B 1E 8A 01
                MOV     DX, 3C5H                        ; BA C5 03
                MOV     AL, 8H                          ; B0 08
                OUT     DX, AL                          ; EE
                MOV     es:[DI], BL                     ; 26 88 1D
                SHR     AL, 1                           ; D0 E8
                OUT     DX, AL                          ; EE
                MOV     es:[DI], BH                     ; 26 88 3D
                MOV     BX, cs:[18CH]                   ; 2E 8B 1E 8C 01
                SHR     AL, 1                           ; D0 E8
                OUT     DX, AL                          ; EE
                MOV     es:[DI], BL                     ; 26 88 1D
                SHR     AL, 1                           ; D0 E8
                OUT     DX, AL                          ; EE
                MOV     es:[DI], BH                     ; 26 88 3D
                RETF                                    ; CB
                ; 0x06F3..0x06F6: shared early-exit tail. Reached via JNG
                ; from ega_blit_glyph_pattern's start when its arg is
                ; negative (no work to do). NEAR-RET here because the
                ; only caller is glyph_pattern, not via FAR dispatch.
ega_glyph_compare_tail:
                POP     DI                              ; 5F
                POP     DS                              ; 1F
                POP     BP                              ; 5D
                RETN                                    ; C3   explicit NEAR RET inside PROC FAR
ega_blit_glyph_compare ENDP

; ============================================================================
; ega_blit_glyph_pattern @ 0x06F7..0x0854 (349 bytes)
;
; FAR. Mirror of glyph_compare for the "transparent + colour-encoded"
; case. Shares the 0x06F3 tail label with glyph_compare for early-exit
; on negative size. Otherwise programs GC reg 5 to wm0, walks source
; pattern bits, accumulates per-plane masks in cs:[18A..18E], flushes
; each byte through Map Mask + GC Bit Mask, and restores state.
;
; Self-modifying word slots: cs:[188]=loop count, cs:[190]/[192]=src
; pointer (set from caller's far-ptr arg).
; ============================================================================
ega_blit_glyph_pattern PROC FAR
                PUSH    BP                              ; 55
                MOV     BP, SP                          ; 8B EC
                MOV     AX, DX                          ; 8B C2
                OR      AX, AX                          ; 0B C0
                JNS     gp_070d                        ; 79 0D
                NEG     AX                              ; F7 D8
                SUB     CX, AX                          ; 2B C8
                JNG     ega_glyph_compare_tail                        ; 7E ED
                SHL     AX, 1                           ; D1 E0
                ADD     [BP+0AH], AX                    ; 01 46 0A
                XOR     AX, AX                          ; 33 C0
gp_070d:
                MOV     BL, AL                          ; 8A D8
                SHR     AX, 1                           ; D1 E8
                SHR     AX, 1                           ; D1 E8
                SHR     AX, 1                           ; D1 E8
                ADD     DI, AX                          ; 03 F8
                MOV     AL, 8H                          ; B0 08
                MOV     DX, 3CEH                        ; BA CE 03
                OUT     DX, AL                          ; EE
                XOR     AX, AX                          ; 33 C0
                MOV     cs:[18AH], AX                   ; 2E A3 8A 01
                MOV     cs:[18CH], AX                   ; 2E A3 8C 01
                MOV     cs:[18EH], AL                   ; 2E A2 8E 01
                AND     BX, 7H                          ; 83 E3 07
                MOV     AH, cs:[BX+17EH]                ; 2E 8A A7 7E 01
                PUSH    BP                              ; 55
                MOV     BX, [BP+8H]                     ; 8B 5E 08
                MOV     cs:[190H], BX                   ; 2E 89 1E 90 01
                MOV     BP, [BP+6H]                     ; 8B 6E 06
                MOV     BX, [BP+4H]                     ; 8B 5E 04
                MOV     cs:[192H], BX                   ; 2E 89 1E 92 01
                MOV     DS, [BP+0H]                     ; 8E 5E 00
                POP     BP                              ; 5D
                MOV     BP, [BP+0AH]                    ; 8B 6E 0A
                MOV     cs:[188H], CX                   ; 2E 89 0E 88 01
gp_0753:
                MOV     SI, [BP+0H]                     ; 8B 76 00
                ADD     BP, 2H                          ; 83 C5 02
                ADD     SI, cs:[190H]                   ; 2E 03 36 90 01
                MOV     CX, SI                          ; 8B CE
                SHR     SI, 1                           ; D1 EE
                SHR     SI, 1                           ; D1 EE
                SHR     SI, 1                           ; D1 EE
                MOV     BX, cs:[192H]                   ; 2E 8B 1E 92 01
                ADD     SI, BX                          ; 03 F3
                SHR     BX, 1                           ; D1 EB
                SHR     BX, 1                           ; D1 EB
                MOV     AL, 80H                         ; B0 80
                AND     CL, 7H                          ; 80 E1 07
                SHR     AL, CL                          ; D2 E8
                TEST    [SI], AL                        ; 84 04
                JNZ     gp_07b5                        ; 75 39
                OR      cs:[18EH], AH                   ; 2E 08 26 8E 01
                MOV     DX, cs:[18AH]                   ; 2E 8B 16 8A 01
                SUB     SI, BX                          ; 2B F3
                TEST    [SI], AL                        ; 84 04
                JZ      gp_078e                        ; 74 02
                OR      DL, AH                          ; 0A D4
gp_078e:
                SUB     SI, BX                          ; 2B F3
                TEST    [SI], AL                        ; 84 04
                JZ      gp_0796                        ; 74 02
                OR      DH, AH                          ; 0A F4
gp_0796:
                MOV     cs:[18AH], DX                   ; 2E 89 16 8A 01
                MOV     DX, cs:[18CH]                   ; 2E 8B 16 8C 01
                SUB     SI, BX                          ; 2B F3
                TEST    [SI], AL                        ; 84 04
                JZ      gp_07a8                        ; 74 02
                OR      DL, AH                          ; 0A D4
gp_07a8:
                SUB     SI, BX                          ; 2B F3
                TEST    [SI], AL                        ; 84 04
                JZ      gp_07b0                        ; 74 02
                OR      DH, AH                          ; 0A F4
gp_07b0:
                MOV     cs:[18CH], DX                   ; 2E 89 16 8C 01
gp_07b5:
                ROR     AH, 1                           ; D0 CC
                JC      gp_07c2                        ; 72 09
                DEC     WORD PTR cs:[188H]              ; 2E FF 0E 88 01
                JNZ     gp_0753                        ; 75 93
                JMP     gp_0816                        ; EB 54
gp_07c2:
                MOV     AL, cs:[18EH]                   ; 2E A0 8E 01
                OR      AL, AL                          ; 0A C0
                JZ      gp_07fa                        ; 74 30
                MOV     DX, 3CFH                        ; BA CF 03
                OUT     DX, AL                          ; EE
                INC     AL                              ; FE C0
                JZ      gp_07d5                        ; 74 03
                MOV     AL, es:[DI]                     ; 26 8A 05
gp_07d5:
                MOV     BX, cs:[18AH]                   ; 2E 8B 1E 8A 01
                MOV     DX, 3C5H                        ; BA C5 03
                MOV     AL, 8H                          ; B0 08
                OUT     DX, AL                          ; EE
                MOV     es:[DI], BL                     ; 26 88 1D
                SHR     AL, 1                           ; D0 E8
                OUT     DX, AL                          ; EE
                MOV     es:[DI], BH                     ; 26 88 3D
                MOV     BX, cs:[18CH]                   ; 2E 8B 1E 8C 01
                SHR     AL, 1                           ; D0 E8
                OUT     DX, AL                          ; EE
                MOV     es:[DI], BL                     ; 26 88 1D
                SHR     AL, 1                           ; D0 E8
                OUT     DX, AL                          ; EE
                MOV     es:[DI], BH                     ; 26 88 3D
gp_07fa:
                XOR     BX, BX                          ; 33 DB
                MOV     cs:[18AH], BX                   ; 2E 89 1E 8A 01
                MOV     cs:[18CH], BX                   ; 2E 89 1E 8C 01
                MOV     cs:[18EH], BL                   ; 2E 88 1E 8E 01
                INC     DI                              ; 47
                DEC     WORD PTR cs:[188H]              ; 2E FF 0E 88 01
                JZ      gp_0816                        ; 74 03
                JMP     gp_0753                        ; E9 3D FF
gp_0816:
                MOV     AL, cs:[18EH]                   ; 2E A0 8E 01
                OR      AL, AL                          ; 0A C0
                JZ      gp_084e                        ; 74 30
                MOV     DX, 3CFH                        ; BA CF 03
                OUT     DX, AL                          ; EE
                INC     AL                              ; FE C0
                JZ      gp_0829                        ; 74 03
                MOV     AL, es:[DI]                     ; 26 8A 05
gp_0829:
                MOV     BX, cs:[18AH]                   ; 2E 8B 1E 8A 01
                MOV     DX, 3C5H                        ; BA C5 03
                MOV     AL, 8H                          ; B0 08
                OUT     DX, AL                          ; EE
                MOV     es:[DI], BL                     ; 26 88 1D
                SHR     AL, 1                           ; D0 E8
                OUT     DX, AL                          ; EE
                MOV     es:[DI], BH                     ; 26 88 3D
                MOV     BX, cs:[18CH]                   ; 2E 8B 1E 8C 01
                SHR     AL, 1                           ; D0 E8
                OUT     DX, AL                          ; EE
                MOV     es:[DI], BL                     ; 26 88 1D
                SHR     AL, 1                           ; D0 E8
                OUT     DX, AL                          ; EE
                MOV     es:[DI], BH                     ; 26 88 3D
gp_084e:
                MOV     AX, SS                          ; 8C D0
                MOV     DS, AX                          ; 8E D8
                POP     BP                              ; 5D
                RETF                                    ; CB
ega_blit_glyph_pattern ENDP

; ============================================================================
; ega_blit_byte_run_with_mask @ 0x0854..0x08AC (88 bytes)
;
; Internal helper called from ega_draw_line. Entry register state:
;   ES:DI = framebuffer dst, BX = pixel-x bit position, CX = run length,
;   DS:SI = mask bytes (one per pixel), AH/AL scratch.
; Hidden in-arg: CF on entry selects forward (CF=0) vs reverse (CF=1) sweep.
; ============================================================================
ega_blit_byte_run_with_mask PROC FAR
                JC      SHORT @@brwm_reverse            ; 72 2B
                ; --- forward branch (CF=0) ---
                MOV     DX, BX                          ; 8B D3
                AND     BX, 7                           ; 83 E3 07
                MOV     AH, cs:[BX+17EH]                ; 2E 8A A7 7E 01
                SHR     DX, 1                           ; D1 EA
                SHR     DX, 1                           ; D1 EA
                SHR     DX, 1                           ; D1 EA
                ADD     DI, DX                          ; 03 FA
                MOV     DX, 03CEH                       ; BA CE 03
                MOV     AL, 8                           ; B0 08         GC idx 8 = Bit Mask
                OUT     DX, AL                          ; EE
                INC     DX                              ; 42
@@brwm_fwd_loop:
                MOV     AL, AH                          ; 8A C4
                OUT     DX, AL                          ; EE
                MOV     AL, es:[DI]                     ; 26 8A 05
                LODSB                                   ; AC
                MOV     es:[DI], AL                     ; 26 88 05
                ROR     AH, 1                           ; D0 CC         shift mask right
                ADC     DI, 0                           ; 83 D7 00
                LOOP    SHORT @@brwm_fwd_loop           ; E2 EF
                RETF                                    ; CB
@@brwm_reverse:
                ; --- reverse branch (CF=1) ---
                MOV     DX, BX                          ; 8B D3
                AND     BX, 7                           ; 83 E3 07
                MOV     AH, cs:[BX+17EH]                ; 2E 8A A7 7E 01
                SHR     DX, 1                           ; D1 EA
                SHR     DX, 1                           ; D1 EA
                SHR     DX, 1                           ; D1 EA
                ADD     DI, DX                          ; 03 FA
                MOV     DX, 03CEH                       ; BA CE 03
                MOV     AL, 8                           ; B0 08
                OUT     DX, AL                          ; EE
                INC     DX                              ; 42
@@brwm_rev_loop:
                MOV     AL, AH                          ; 8A C4
                OUT     DX, AL                          ; EE
                MOV     AL, es:[DI]                     ; 26 8A 05
                LODSB                                   ; AC
                MOV     es:[DI], AL                     ; 26 88 05
                ROL     AH, 1                           ; D0 C4         shift mask left
                SBB     DI, 0                           ; 83 DF 00
                LOOP    SHORT @@brwm_rev_loop           ; E2 EF
                RETF                                    ; CB
ega_blit_byte_run_with_mask ENDP

; --- g_aEgaDrawLineLUT (08AC..08B4, 8 bytes) ---
g_aEgaDrawLineLUT:
                DB      080H, 040H, 020H, 010H, 008H, 004H, 002H, 001H                                   ; 0x08AC

; ============================================================================
; ega_draw_line @ 0x08B4..0x0AA0 (492 bytes)
;
; FAR. Bresenham line drawer. Uses g_aEgaDrawLineLUT @ CS:0x08AC for the
; initial bit-mask byte. Falls into ega_pixel_run_fill for horizontals.
; Register ABI: AX=colour, BX=x0, CX=y0, DX=x1, SI=y1.
; Two self-modifying byte slots: cs:[6C2] (mouse-active copy) and
; cs:[6C4] (initial pixel bit mask shifted to x0%8).
; ============================================================================
ega_draw_line PROC FAR
                PUSH    DS                              ; 1E
                MOV     DS, cs:[7DH]                    ; 2E 8E 1E 7D 00
                XOR     AH, AH                          ; 32 E4
                MOV     AL, ds:[GfxContext.bGfx_outline_color]                    ; A0 0E 00
                MOV     ds:[6C2H], AL                   ; A2 C2 06
                MOV     DI, BX                          ; 8B FB
                AND     DI, 7H                          ; 83 E7 07
                MOV     AL, cs:[DI+8ACH]                ; 2E 8A 85 AC 08
                MOV     ds:[6C4H], AL                   ; A2 C4 06
                MOV     DI, CX                          ; 8B F9
                SHL     DI, 1                           ; D1 E7
                MOV     DI, [DI+(GfxContext.pRow_offset_lut)]                   ; 8B BD F2 06
                MOV     AX, BX                          ; 8B C3
                SHR     AX, 1                           ; D1 E8
                SHR     AX, 1                           ; D1 E8
                SHR     AX, 1                           ; D1 E8
                ADD     DI, AX                          ; 03 F8
                CMP     BX, DX                          ; 3B DA
                JNZ     dl_08eb                        ; 75 06
                CMP     CX, SI                          ; 3B CE
                JZ      dl_08f1                        ; 74 08
                JMP     dl_091e                        ; EB 33
dl_08eb:
                CMP     CX, SI                          ; 3B CE
                JZ      dl_0907                        ; 74 18
                JMP     dl_0949                        ; EB 58
dl_08f1:
                MOV     AH, ds:[6C4H]                   ; 8A 26 C4 06
                MOV     AL, es:[DI]                     ; 26 8A 05
                MOV     DX, 3CEH                        ; BA CE 03
                MOV     AL, 8H                          ; B0 08
                OUT     DX, AX                          ; EF
                MOV     AL, ds:[6C2H]                   ; A0 C2 06
                MOV     es:[DI], AL                     ; 26 88 05
                JMP     dl_0a9e                        ; E9 97 01
dl_0907:
                MOV     DI, CX                          ; 8B F9
                SHL     DI, 1                           ; D1 E7
                MOV     DI, [DI+(GfxContext.pRow_offset_lut)]                   ; 8B BD F2 06
                SUB     DX, BX                          ; 2B D3
                MOV     CX, DX                          ; 8B CA
                INC     CX                              ; 41
                MOV     AL, ds:[6C2H]                   ; A0 C2 06
                PUSH    CS                              ; 0E
                CALL    NEAR PTR ega_pixel_run_fill     ; E8 4E F9
                JMP     dl_0a9e                        ; E9 80 01
dl_091e:
                MOV     AX, 28H                         ; B8 28 00
                MOV     BP, AX                          ; 8B E8
                SUB     SI, CX                          ; 2B F1
                JG      dl_092b                        ; 7F 04
                NEG     SI                              ; F7 DE
                NEG     BP                              ; F7 DD
dl_092b:
                MOV     CX, SI                          ; 8B CE
                MOV     AH, ds:[6C4H]                   ; 8A 26 C4 06
                MOV     BL, ds:[6C2H]                   ; 8A 1E C2 06
                MOV     DX, 3CEH                        ; BA CE 03
                MOV     AL, 8H                          ; B0 08
                OUT     DX, AX                          ; EF
dl_093b:
                MOV     BH, es:[DI]                     ; 26 8A 3D
                MOV     es:[DI], BL                     ; 26 88 1D
                ADD     DI, BP                          ; 03 FD
                DEC     CX                              ; 49
                JNS     dl_093b                        ; 79 F5
                JMP     dl_0a9e                        ; E9 55 01
dl_0949:
                MOV     AX, 28H                         ; B8 28 00
                MOV     BP, AX                          ; 8B E8
                SUB     DX, BX                          ; 2B D3
                MOV     ds:[6C0H], SI                   ; 89 36 C0 06
                SUB     SI, CX                          ; 2B F1
                JG      dl_095c                        ; 7F 04
                NEG     SI                              ; F7 DE
                NEG     BP                              ; F7 DD
dl_095c:
                MOV     CX, SI                          ; 8B CE
                CMP     CX, DX                          ; 3B CA
                JZ      dl_0967                        ; 74 05
                JC      dl_099d                        ; 72 39
                JMP     dl_09f4                        ; E9 8D 00
dl_0967:
                MOV     CX, DX                          ; 8B CA
                MOV     BL, ds:[6C2H]                   ; 8A 1E C2 06
                MOV     DX, 3CEH                        ; BA CE 03
                MOV     AL, 8H                          ; B0 08
                OUT     DX, AL                          ; EE
                INC     DX                              ; 42
                MOV     AL, ds:[6C4H]                   ; A0 C4 06
                JMP     dl_097d                        ; EB 04
dl_0979:
                ROR     AL, 1                           ; D0 C8
                JC      dl_098b                        ; 72 0E
dl_097d:
                MOV     AH, es:[DI]                     ; 26 8A 25
                OUT     DX, AL                          ; EE
                MOV     es:[DI], BL                     ; 26 88 1D
                ADD     DI, BP                          ; 03 FD
                DEC     CX                              ; 49
                JZ      dl_099a                        ; 74 11
                JMP     dl_0979                        ; EB EE
dl_098b:
                INC     DI                              ; 47
                MOV     BH, es:[DI]                     ; 26 8A 3D
                OUT     DX, AL                          ; EE
                MOV     es:[DI], BL                     ; 26 88 1D
                DEC     CX                              ; 49
                JZ      dl_099a                        ; 74 04
                ADD     DI, BP                          ; 03 FD
                JMP     dl_0979                        ; EB DF
dl_099a:
                JMP     dl_0a9e                        ; E9 01 01
dl_099d:
                MOV     BX, CX                          ; 8B D9
                MOV     CX, DX                          ; 8B CA
                MOV     AX, BX                          ; 8B C3
                SHL     AX, 1                           ; D1 E0
                MOV     ds:[6C0H], AX                   ; A3 C0 06
                SUB     AX, CX                          ; 2B C1
                MOV     SI, AX                          ; 8B F0
                SUB     AX, CX                          ; 2B C1
                MOV     BX, BP                          ; 8B DD
                MOV     BP, AX                          ; 8B E8
                MOV     DX, 3CEH                        ; BA CE 03
                MOV     AL, 8H                          ; B0 08
                OUT     DX, AL                          ; EE
                INC     DX                              ; 42
                MOV     AL, ds:[6C4H]                   ; A0 C4 06
                MOV     AH, es:[DI]                     ; 26 8A 25
                OUT     DX, AL                          ; EE
                MOV     AL, ds:[6C2H]                   ; A0 C2 06
                MOV     es:[DI], AL                     ; 26 88 05
                ROR     BYTE PTR ds:[6C4H], 1           ; D0 0E C4 06
                ADC     DI, 0H                          ; 83 D7 00
dl_09cd:
                OR      SI, SI                          ; 0B F6
                JS      dl_09d7                        ; 78 06
                ADD     DI, BX                          ; 03 FB
                ADD     SI, BP                          ; 03 F5
                JMP     dl_09db                        ; EB 04
dl_09d7:
                ADD     SI, ds:[6C0H]                   ; 03 36 C0 06
dl_09db:
                MOV     AL, ds:[6C4H]                   ; A0 C4 06
                MOV     AH, es:[DI]                     ; 26 8A 25
                OUT     DX, AL                          ; EE
                MOV     AL, ds:[6C2H]                   ; A0 C2 06
                MOV     es:[DI], AL                     ; 26 88 05
                ROR     BYTE PTR ds:[6C4H], 1           ; D0 0E C4 06
                ADC     DI, 0H                          ; 83 D7 00
                LOOP    dl_09cd                        ; E2 DC
                JMP     dl_0a9e                        ; E9 AA 00
dl_09f4:
                XCHG    BX, DX                          ; 87 DA
                MOV     AX, 1H                          ; B8 01 00
                OR      BP, BP                          ; 0B ED
                JNS     dl_0a27                        ; 79 2A
                NEG     AX                              ; F7 D8
                PUSH    AX                              ; 50
                MOV     DI, ds:[6C0H]                   ; 8B 3E C0 06
                SHL     DI, 1                           ; D1 E7
                MOV     DI, [DI+(GfxContext.pRow_offset_lut)]                   ; 8B BD F2 06
                MOV     AX, BX                          ; 8B C3
                ADD     BX, DX                          ; 03 DA
                MOV     DX, BX                          ; 8B D3
                AND     BX, 7H                          ; 83 E3 07
                MOV     BL, cs:[BX+8ACH]                ; 2E 8A 9F AC 08
                MOV     ds:[6C4H], BL                   ; 88 1E C4 06
                SHR     DX, 1                           ; D1 EA
                SHR     DX, 1                           ; D1 EA
                SHR     DX, 1                           ; D1 EA
                ADD     DI, DX                          ; 03 FA
                MOV     BX, AX                          ; 8B D8
                POP     AX                              ; 58
dl_0a27:
                MOV     BP, AX                          ; 8B E8
                MOV     AX, BX                          ; 8B C3
                SHL     AX, 1                           ; D1 E0
                MOV     ds:[6C0H], AX                   ; A3 C0 06
                SUB     AX, CX                          ; 2B C1
                MOV     SI, AX                          ; 8B F0
                SUB     AX, CX                          ; 2B C1
                MOV     BX, BP                          ; 8B DD
                MOV     BP, AX                          ; 8B E8
                MOV     DX, 3CEH                        ; BA CE 03
                MOV     AL, 8H                          ; B0 08
                OUT     DX, AL                          ; EE
                INC     DX                              ; 42
                MOV     AL, ds:[6C4H]                   ; A0 C4 06
                MOV     AH, es:[DI]                     ; 26 8A 25
                OUT     DX, AL                          ; EE
                MOV     AL, ds:[6C2H]                   ; A0 C2 06
                MOV     es:[DI], AL                     ; 26 88 05
                OR      BX, BX                          ; 0B DB
                JS      dl_0a79                        ; 78 27
dl_0a52:
                ADD     DI, 28H                         ; 83 C7 28
                OR      SI, SI                          ; 0B F6
                JS      dl_0a64                        ; 78 0B
                ROR     BYTE PTR ds:[6C4H], 1           ; D0 0E C4 06
                ADC     DI, 0H                          ; 83 D7 00
                ADD     SI, BP                          ; 03 F5
                JMP     dl_0a68                        ; EB 04
dl_0a64:
                ADD     SI, ds:[6C0H]                   ; 03 36 C0 06
dl_0a68:
                MOV     AL, ds:[6C4H]                   ; A0 C4 06
                MOV     AH, es:[DI]                     ; 26 8A 25
                OUT     DX, AL                          ; EE
                MOV     AL, ds:[6C2H]                   ; A0 C2 06
                MOV     es:[DI], AL                     ; 26 88 05
                LOOP    dl_0a52                        ; E2 DB
                JMP     dl_0a9e                        ; EB 25
dl_0a79:
                ADD     DI, 28H                         ; 83 C7 28
                OR      SI, SI                          ; 0B F6
                JS      dl_0a8b                        ; 78 0B
                ROL     BYTE PTR ds:[6C4H], 1           ; D0 06 C4 06
                SBB     DI, 0H                          ; 83 DF 00
                ADD     SI, BP                          ; 03 F5
                JMP     dl_0a8f                        ; EB 04
dl_0a8b:
                ADD     SI, ds:[6C0H]                   ; 03 36 C0 06
dl_0a8f:
                MOV     AL, ds:[6C4H]                   ; A0 C4 06
                MOV     AH, es:[DI]                     ; 26 8A 25
                OUT     DX, AL                          ; EE
                MOV     AL, ds:[6C2H]                   ; A0 C2 06
                MOV     es:[DI], AL                     ; 26 88 05
                LOOP    dl_0a79                        ; E2 DB
dl_0a9e:
                POP     DS                              ; 1F
                RETF                                    ; CB
ega_draw_line ENDP

; ----------------------------------------------------------------------------
; g_aEgaPolygonEdgeMaskLUT @ 0x0AA0..0x0AB0 (16 bytes of LUT data).
;
;   0x0AA0..0x0AA7  -- right-edge mask (keep low 8-N bits)
;                       indexed by (start_bit+run) mod 8 via [BX+0AA0H]
;   0x0AA8..0x0AAF  -- left-edge mask  (keep high N bits)
;                       indexed by (start_bit) via [BX+0AA8H]
;
; Followed by 10 bytes of CS-resident self-modifying state slots
; (NOT part of the LUT -- declared zero on disk, written every call by
;  ega_polygon_span_fill's prologue):
;
;   0x0AB0  WORD  current x-end / mask scratch (psf_0bbe path)
;   0x0AB2  WORD  edges-remaining counter (`SUB cs:[0AB2H], 1; JNG ...`)
;   0x0AB4  WORD  colour | (colour rotated 4) -- packed colour pair
;   0x0AB6  WORD  reserved (high path only -- written from AX at psf_0bad)
;   0x0AB8  WORD  scanline-LUT base offset (6F2H + cs:[7FH])
; ----------------------------------------------------------------------------
g_aEgaPolygonEdgeMaskLUT:
                DB      0FFH, 07FH, 03FH, 01FH, 00FH, 007H, 003H, 001H, 000H, 080H, 0C0H, 0E0H, 0F0H, 0F8H, 0FCH, 0FEH ; 0x0AA0
                ; --- self-modifying state slots 0x0AB0..0x0AB9 (zero-init on disk) ---
                DB      000H, 000H, 000H, 000H, 000H, 000H, 000H, 000H, 000H, 000H                       ; 0x0AB0

; ============================================================================
; ega_polygon_span_fill @ 0x0ABA..0x0D93 (729 bytes)
;
; FAR. Polygon span-fill renderer. Walks a sorted edge list, computes the
; left/right byte-aligned span endpoints, and fills the span via EGA
; write-mode 2 (Map Mask 0F + Bit Mask). Uses g_aEgaPolygonEdgeMaskLUT
; @ CS:0x0AA0 (8 right-edge + 8 left-edge masks; see plate above the
; LUT). The 10 bytes immediately after the LUT (0x0AB0..0x0AB9) are
; CS-resident self-modifying state slots for this function (not part
; of the LUT).
;
; ARGS in REGISTERS (caller-supplied):
;   AL = colour, BX = left x, CX = pixel count, DX = right x,
;   SI = edge-table pointer, DI = framebuffer ptr.
; ============================================================================
ega_polygon_span_fill PROC FAR
                MOV     AX, 205H                        ; B8 05 02
                MOV     DX, 3CEH                        ; BA CE 03
                OUT     DX, AX                          ; EF
                MOV     AX, 0FF08H                      ; B8 08 FF
                OUT     DX, AX                          ; EF
                PUSH    DS                              ; 1E
                MOV     CX, ES                          ; 8C C1
                MOV     DS, CX                          ; 8E D9
                LODSW                                   ; AD
                SHL     AX, 1                           ; D1 E0
                MOV     BP, AX                          ; 8B E8
                LODSW                                   ; AD
                MOV     DS, cs:[7DH]                    ; 2E 8E 1E 7D 00
                MOV     cs:[0AB2H], AX                  ; 2E A3 B2 0A
                MOV     AX, ds:[GfxContext.wGfxBlitDstPage]                    ; A1 18 00
                MOV     ES, AX                          ; 8E C0
                MOV     AX, GfxContext.pRow_offset_lut  ; B8 F2 06  row LUT offset within scratch
                ADD     AX, cs:[7FH]                    ; 2E 03 06 7F 00
                MOV     cs:[0AB8H], AX                  ; 2E A3 B8 0A
                MOV     AL, ds:[GfxContext.bGfx_fill_color]                    ; A0 0D 00
                XOR     AH, AH                          ; 32 E4
                MOV     DL, AL                          ; 8A D0
                MOV     AH, AL                          ; 8A E0
                ROR     AH, 1                           ; D0 CC
                ROR     AH, 1                           ; D0 CC
                ROR     AH, 1                           ; D0 CC
                ROR     AH, 1                           ; D0 CC
                MOV     cs:[0AB4H], AX                  ; 2E A3 B4 0A
                AND     DL, 0F0H                        ; 80 E2 F0
                MOV     DS, CX                          ; 8E D9
                JZ      psf_0b0b                        ; 74 05
                XCHG    AL, AH                          ; 86 C4
                JMP     psf_0bad                        ; E9 A2 00
psf_0b0b:
                LODSW                                   ; AD
                MOV     BX, AX                          ; 8B D8
                LODSW                                   ; AD
                SUB     AX, BX                          ; 2B C3
                JNL     psf_0b16                        ; 7D 03
                JMP     psf_0b9d                        ; E9 87 00
psf_0b16:
                INC     AX                              ; 40
                MOV     CX, AX                          ; 8B C8
                MOV     DI, cs:[0AB8H]                  ; 2E 8B 3E B8 0A
                MOV     DI, [BP+DI]                     ; 8B 3B
                MOV     AX, cs:[0AB4H]                  ; 2E A1 B4 0A
                MOV     DX, AX                          ; 8B D0
                MOV     AX, BX                          ; 8B C3
                SHR     AX, 1                           ; D1 E8
                SHR     AX, 1                           ; D1 E8
                SHR     AX, 1                           ; D1 E8
                ADD     DI, AX                          ; 03 F8
                AND     BX, 7H                          ; 83 E3 07
                MOV     AX, DX                          ; 8B C2
                MOV     DX, BX                          ; 8B D3
                ADD     DX, CX                          ; 03 D1
                CMP     DX, 8H                          ; 83 FA 08
                JL      psf_0b81                        ; 7C 43
                MOV     DX, 8H                          ; BA 08 00
                SUB     DX, BX                          ; 2B D3
                SUB     CX, DX                          ; 2B CA
                MOV     AH, cs:[BX+0AA0H]               ; 2E 8A A7 A0 0A
                MOV     BL, AL                          ; 8A D8
                MOV     AL, 8H                          ; B0 08
                MOV     DX, 3CEH                        ; BA CE 03
                OUT     DX, AX                          ; EF
                INC     DX                              ; 42
                MOV     AL, es:[DI]                     ; 26 8A 05
                MOV     AL, BL                          ; 8A C3
                STOSB                                   ; AA
                MOV     BH, CL                          ; 8A F9
                SHR     CX, 1                           ; D1 E9
                SHR     CX, 1                           ; D1 E9
                SHR     CX, 1                           ; D1 E9
                JZ      psf_0b6a                        ; 74 07
                MOV     AL, 0FFH                        ; B0 FF
                OUT     DX, AL                          ; EE
                MOV     AL, BL                          ; 8A C3
                REP     STOSB                           ; F3 AA
psf_0b6a:
                MOV     CL, BL                          ; 8A CB
                MOV     BL, BH                          ; 8A DF
                AND     BX, 7H                          ; 83 E3 07
                JZ      psf_0b9d                        ; 74 2A
                MOV     AL, cs:[BX+0AA8H]               ; 2E 8A 87 A8 0A
                OUT     DX, AL                          ; EE
                MOV     AL, es:[DI]                     ; 26 8A 05
                MOV     es:[DI], CL                     ; 26 88 0D
                JMP     psf_0b9d                        ; EB 1C
psf_0b81:
                MOV     AH, cs:[BX+0AA0H]               ; 2E 8A A7 A0 0A
                MOV     BL, DL                          ; 8A DA
                MOV     CL, cs:[BX+0AA8H]               ; 2E 8A 8F A8 0A
                AND     AH, CL                          ; 22 E1
                MOV     BL, AL                          ; 8A D8
                MOV     AL, 8H                          ; B0 08
                MOV     DX, 3CEH                        ; BA CE 03
                OUT     DX, AX                          ; EF
                MOV     AL, es:[DI]                     ; 26 8A 05
                MOV     es:[DI], BL                     ; 26 88 1D
psf_0b9d:
                SUB     WORD PTR cs:[0AB2H], 1H         ; 2E 83 2E B2 0A 01
                JNG     psf_0bab                        ; 7E 06
                ADD     BP, 2H                          ; 83 C5 02
                JMP     psf_0b0b                        ; E9 60 FF
psf_0bab:
                POP     DS                              ; 1F
                RETF                                    ; CB
psf_0bad:
                MOV     cs:[0AB6H], AX                  ; 2E A3 B6 0A
                MOV     BX, BP                          ; 8B DD
                SHR     BX, 1                           ; D1 EB
                ADD     BX, [SI]                        ; 03 1C
                SHR     BX, 1                           ; D1 EB
                JC      psf_0bbe                        ; 72 03
                JMP     psf_0ca7                        ; E9 E9 00
psf_0bbe:
                LODSW                                   ; AD
                MOV     BX, AX                          ; 8B D8
                LODSW                                   ; AD
                SUB     AX, BX                          ; 2B C3
                JNL     psf_0bc9                        ; 7D 03
                JMP     psf_0c9a                        ; E9 D1 00
psf_0bc9:
                INC     AX                              ; 40
                MOV     CX, AX                          ; 8B C8
                MOV     DI, cs:[0AB8H]                  ; 2E 8B 3E B8 0A
                MOV     DI, [BP+DI]                     ; 8B 3B
                MOV     AX, cs:[0AB4H]                  ; 2E A1 B4 0A
                MOV     cs:[0AB0H], AX                  ; 2E A3 B0 0A
                MOV     AX, BX                          ; 8B C3
                SHR     AX, 1                           ; D1 E8
                SHR     AX, 1                           ; D1 E8
                SHR     AX, 1                           ; D1 E8
                ADD     DI, AX                          ; 03 F8
                AND     BX, 7H                          ; 83 E3 07
                MOV     DX, BX                          ; 8B D3
                ADD     DX, CX                          ; 03 D1
                CMP     DX, 8H                          ; 83 FA 08
                JNL     psf_0c21                        ; 7D 30
                MOV     CX, cs:[0AB0H]                  ; 2E 8B 0E B0 0A
                MOV     AH, cs:[BX+0AA0H]               ; 2E 8A A7 A0 0A
                MOV     BL, DL                          ; 8A DA
                AND     AH, cs:[BX+0AA8H]               ; 2E 22 A7 A8 0A
                MOV     BL, AH                          ; 8A DC
                AND     AH, 0AAH                        ; 80 E4 AA
                MOV     AL, 8H                          ; B0 08
                MOV     DX, 3CEH                        ; BA CE 03
                OUT     DX, AX                          ; EF
                INC     DX                              ; 42
                MOV     AL, es:[DI]                     ; 26 8A 05
                MOV     es:[DI], CL                     ; 26 88 0D
                MOV     AL, BL                          ; 8A C3
                AND     AL, 55H                         ; 24 55
                OUT     DX, AL                          ; EE
                MOV     AL, es:[DI]                     ; 26 8A 05
                MOV     AL, CH                          ; 8A C5
                STOSB                                   ; AA
                JMP     psf_0c9a                        ; EB 79
psf_0c21:
                MOV     DX, 8H                          ; BA 08 00
                SUB     DX, BX                          ; 2B D3
                SUB     CX, DX                          ; 2B CA
                MOV     AH, cs:[BX+0AA0H]               ; 2E 8A A7 A0 0A
                MOV     DX, 3CEH                        ; BA CE 03
                MOV     AL, 8H                          ; B0 08
                OUT     DX, AL                          ; EE
                INC     DX                              ; 42
                MOV     BX, cs:[0AB0H]                  ; 2E 8B 1E B0 0A
                MOV     AL, es:[DI]                     ; 26 8A 05
                MOV     AL, AH                          ; 8A C4
                AND     AL, 0AAH                        ; 24 AA
                OUT     DX, AL                          ; EE
                MOV     es:[DI], BL                     ; 26 88 1D
                MOV     AL, es:[DI]                     ; 26 8A 05
                MOV     AL, AH                          ; 8A C4
                AND     AL, 55H                         ; 24 55
                OUT     DX, AL                          ; EE
                MOV     AL, BH                          ; 8A C7
                STOSB                                   ; AA
                MOV     AH, CL                          ; 8A E1
                SHR     CX, 1                           ; D1 E9
                SHR     CX, 1                           ; D1 E9
                SHR     CX, 1                           ; D1 E9
                JZ      psf_0c76                        ; 74 1D
                MOV     AL, 0AAH                        ; B0 AA
                OUT     DX, AL                          ; EE
                MOV     es:[DI], BL                     ; 26 88 1D
                SHR     AL, 1                           ; D0 E8
                OUT     DX, AL                          ; EE
                MOV     AL, es:[DI]                     ; 26 8A 05
                MOV     AL, BH                          ; 8A C7
                MOV     DH, AH                          ; 8A F4
                MOV     AH, AL                          ; 8A E0
                SHR     CX, 1                           ; D1 E9
                REP     STOSW                           ; F3 AB
                MOV     AH, DH                          ; 8A E6
                MOV     DH, 3H                          ; B6 03
                JNC     psf_0c76                        ; 73 01
                STOSB                                   ; AA
psf_0c76:
                MOV     CL, AH                          ; 8A CC
                XCHG    CX, BX                          ; 87 CB
                AND     BX, 7H                          ; 83 E3 07
                JZ      psf_0c9a                        ; 74 1B
                MOV     AH, cs:[BX+0AA8H]               ; 2E 8A A7 A8 0A
                MOV     AL, AH                          ; 8A C4
                AND     AL, 0AAH                        ; 24 AA
                OUT     DX, AL                          ; EE
                MOV     AL, es:[DI]                     ; 26 8A 05
                MOV     es:[DI], CL                     ; 26 88 0D
                MOV     AL, AH                          ; 8A C4
                AND     AL, 55H                         ; 24 55
                OUT     DX, AL                          ; EE
                MOV     AL, es:[DI]                     ; 26 8A 05
                MOV     es:[DI], CH                     ; 26 88 2D
psf_0c9a:
                SUB     WORD PTR cs:[0AB2H], 1H         ; 2E 83 2E B2 0A 01
                JG      psf_0ca4                        ; 7F 02
                POP     DS                              ; 1F
                RETF                                    ; CB
psf_0ca4:
                ADD     BP, 2H                          ; 83 C5 02
psf_0ca7:
                LODSW                                   ; AD
                MOV     BX, AX                          ; 8B D8
                LODSW                                   ; AD
                SUB     AX, BX                          ; 2B C3
                JNL     psf_0cb2                        ; 7D 03
                JMP     psf_0d83                        ; E9 D1 00
psf_0cb2:
                INC     AX                              ; 40
                MOV     CX, AX                          ; 8B C8
                MOV     DI, cs:[0AB8H]                  ; 2E 8B 3E B8 0A
                MOV     DI, [BP+DI]                     ; 8B 3B
                MOV     AX, cs:[0AB6H]                  ; 2E A1 B6 0A
                MOV     cs:[0AB0H], AX                  ; 2E A3 B0 0A
                MOV     AX, BX                          ; 8B C3
                SHR     AX, 1                           ; D1 E8
                SHR     AX, 1                           ; D1 E8
                SHR     AX, 1                           ; D1 E8
                ADD     DI, AX                          ; 03 F8
                AND     BX, 7H                          ; 83 E3 07
                MOV     DX, BX                          ; 8B D3
                ADD     DX, CX                          ; 03 D1
                CMP     DX, 8H                          ; 83 FA 08
                JNL     psf_0d0a                        ; 7D 30
                MOV     CX, cs:[0AB0H]                  ; 2E 8B 0E B0 0A
                MOV     AH, cs:[BX+0AA0H]               ; 2E 8A A7 A0 0A
                MOV     BL, DL                          ; 8A DA
                AND     AH, cs:[BX+0AA8H]               ; 2E 22 A7 A8 0A
                MOV     BL, AH                          ; 8A DC
                AND     AH, 0AAH                        ; 80 E4 AA
                MOV     AL, 8H                          ; B0 08
                MOV     DX, 3CEH                        ; BA CE 03
                OUT     DX, AX                          ; EF
                INC     DX                              ; 42
                MOV     AL, es:[DI]                     ; 26 8A 05
                MOV     es:[DI], CL                     ; 26 88 0D
                MOV     AL, BL                          ; 8A C3
                AND     AL, 55H                         ; 24 55
                OUT     DX, AL                          ; EE
                MOV     AL, es:[DI]                     ; 26 8A 05
                MOV     AL, CH                          ; 8A C5
                STOSB                                   ; AA
                JMP     psf_0d83                        ; EB 79
psf_0d0a:
                MOV     DX, 8H                          ; BA 08 00
                SUB     DX, BX                          ; 2B D3
                SUB     CX, DX                          ; 2B CA
                MOV     AH, cs:[BX+0AA0H]               ; 2E 8A A7 A0 0A
                MOV     DX, 3CEH                        ; BA CE 03
                MOV     AL, 8H                          ; B0 08
                OUT     DX, AL                          ; EE
                INC     DX                              ; 42
                MOV     BX, cs:[0AB0H]                  ; 2E 8B 1E B0 0A
                MOV     AL, es:[DI]                     ; 26 8A 05
                MOV     AL, AH                          ; 8A C4
                AND     AL, 0AAH                        ; 24 AA
                OUT     DX, AL                          ; EE
                MOV     es:[DI], BL                     ; 26 88 1D
                MOV     AL, es:[DI]                     ; 26 8A 05
                MOV     AL, AH                          ; 8A C4
                AND     AL, 55H                         ; 24 55
                OUT     DX, AL                          ; EE
                MOV     AL, BH                          ; 8A C7
                STOSB                                   ; AA
                MOV     AH, CL                          ; 8A E1
                SHR     CX, 1                           ; D1 E9
                SHR     CX, 1                           ; D1 E9
                SHR     CX, 1                           ; D1 E9
                JZ      psf_0d5f                        ; 74 1D
                MOV     AL, 0AAH                        ; B0 AA
                OUT     DX, AL                          ; EE
                MOV     es:[DI], BL                     ; 26 88 1D
                SHR     AL, 1                           ; D0 E8
                OUT     DX, AL                          ; EE
                MOV     AL, es:[DI]                     ; 26 8A 05
                MOV     AL, BH                          ; 8A C7
                MOV     DH, AH                          ; 8A F4
                MOV     AH, AL                          ; 8A E0
                SHR     CX, 1                           ; D1 E9
                REP     STOSW                           ; F3 AB
                MOV     AH, DH                          ; 8A E6
                MOV     DH, 3H                          ; B6 03
                JNC     psf_0d5f                        ; 73 01
                STOSB                                   ; AA
psf_0d5f:
                MOV     CL, AH                          ; 8A CC
                XCHG    CX, BX                          ; 87 CB
                AND     BX, 7H                          ; 83 E3 07
                JZ      psf_0d83                        ; 74 1B
                MOV     AH, cs:[BX+0AA8H]               ; 2E 8A A7 A8 0A
                MOV     AL, AH                          ; 8A C4
                AND     AL, 0AAH                        ; 24 AA
                OUT     DX, AL                          ; EE
                MOV     AL, es:[DI]                     ; 26 8A 05
                MOV     es:[DI], CL                     ; 26 88 0D
                MOV     AL, AH                          ; 8A C4
                AND     AL, 55H                         ; 24 55
                OUT     DX, AL                          ; EE
                MOV     AL, es:[DI]                     ; 26 8A 05
                MOV     es:[DI], CH                     ; 26 88 2D
psf_0d83:
                SUB     WORD PTR cs:[0AB2H], 1H         ; 2E 83 2E B2 0A 01
                JNG     psf_0d91                        ; 7E 06
                ADD     BP, 2H                          ; 83 C5 02
                JMP     psf_0bbe                        ; E9 2D FE
psf_0d91:
                POP     DS                              ; 1F
                RETF                                    ; CB
ega_polygon_span_fill ENDP

; ============================================================================
; ega_palette_load @ 0x0D93..0x0DB7 (36 bytes)
;
; FAR helper that stashes a far-pointer to a 17-byte EGA palette image
; (16 colour bytes + overscan) in chunk-local slot CS:[019E] (offset) +
; CS:[01A0] (segment), then calls BIOS INT 10h AX=1002h (set all
; attribute-controller palette registers from a buffer at ES:DX).
;
; ARGS (far, two-word far-ptr): [BP+6] = off, [BP+8] = seg
; If seg is 0 the call is skipped (defensive null check).
; ============================================================================
ega_palette_load PROC FAR
                PUSH    BP                              ; 55
                MOV     BP, SP                          ; 8B EC
                PUSH    DS                              ; 1E
                MOV     DS, cs:[7DH]                    ; 2E 8E 1E 7D 00  DS = scratch
                MOV     DX, [BP+6]                      ; 8B 56 06    off
                MOV     AX, [BP+8]                      ; 8B 46 08    seg
                OR      AX, AX                          ; 0B C0
                JZ      SHORT @@pl_skip                 ; 74 0E
                MOV     ds:[GfxContext.pPaletteScratchBuf], DX                   ; 89 16 9E 01  stash far-ptr offset
                MOV     ds:[GfxContext.pPaletteScratchBuf+2], AX                   ; A3 A0 01     stash far-ptr segment
                MOV     ES, AX                          ; 8E C0
                MOV     AX, 1002H                       ; B8 02 10
                INT     10H                             ; CD 10
@@pl_skip:
                POP     DS                              ; 1F
                POP     BP                              ; 5D
                RETF                                    ; CB
ega_palette_load ENDP

; ============================================================================
; ega_image_install @ 0x0DB7..0x0DF8 (65 bytes)
;
; FAR. Walks an array of image-descriptor near-pointers terminated by 0,
; summing (width/2 * height) over each descriptor. Returns 1.25 * sum in
; DX:AX and zeroes [BP+8]->[0] as a side effect (callers use it as a fail
; flag). Used by the image-archive registration path.
;
; ARGS (far): [BP+6] = ptr to near-ptr array, [BP+8] = ptr to fail flag.
; ============================================================================
ega_image_install PROC FAR
                PUSH    BP                              ; 55
                MOV     BP, SP                          ; 8B EC
                PUSH    SI                              ; 56
                PUSH    DI                              ; 57
                MOV     DI, [BP+6]                      ; 8B 7E 06    array ptr
                XOR     BX, BX                          ; 33 DB       sum lo
                XOR     CX, CX                          ; 33 C9       sum hi
@@ii_loop:
                MOV     SI, [DI]                        ; 8B 35
                OR      SI, SI                          ; 0B F6
                JZ      SHORT @@ii_done                 ; 74 14       null terminator
                MOV     AX, [SI+6]                      ; 8B 44 06    width
                SHR     AX, 1                           ; D1 E8       width/2
                MOV     DX, [SI+8]                      ; 8B 54 08    height
                MUL     DX                              ; F7 E2       DX:AX = w/2*h
                ADD     BX, AX                          ; 03 D8
                ADC     CX, 0                           ; 83 D1 00    BX:CX += partial
                ADD     DI, 2                           ; 83 C7 02
                JMP     SHORT @@ii_loop                 ; EB E6
@@ii_done:
                MOV     AX, BX                          ; 8B C3
                MOV     DX, CX                          ; 8B D1       DX:AX = sum
                SHR     DX, 1                           ; D1 EA
                RCR     AX, 1                           ; D1 D8       /2
                SHR     DX, 1                           ; D1 EA
                RCR     AX, 1                           ; D1 D8       /4
                ADD     AX, BX                          ; 03 C3
                ADC     DX, CX                          ; 13 D1       sum/4 + sum = 1.25*sum
                MOV     SI, [BP+8]                      ; 8B 76 08
                MOV     WORD PTR [SI], 0                ; C7 04 00 00
                POP     DI                              ; 5F
                POP     SI                              ; 5E
                POP     BP                              ; 5D
                RETF                                    ; CB
ega_image_install ENDP

; ============================================================================
; ega_image_decode @ 0x0DF8..0x0E9B (163 bytes)
;
; FAR. Decodes a list of EGA image records (chunky source -> planar dest
; via the temporary A600 scratch segment). For each record:
;   1. Call ega_chunky_to_planar_row to interleave the chunky source bytes.
;   2. Call ega_read_planes_to_buffer to read the planar bytes back.
;   3. Call ega_build_transparency_mask to compute the alpha mask.
; The accumulated buffer-position advances by (w/2 * h / 4 * 5) per image.
;
; ARGS (far):
;   [BP+6]  near-ptr array of image-descriptor records (each is a near ptr)
;   [BP+8]  current decode offset (in/out)
;   [BP+A]  current decode segment (in/out)
;   [BP+C]  size-low (used by chunky_to_planar_row)
;   [BP+E]  size-hi
; ============================================================================
ega_image_decode PROC FAR
                PUSH    BP                              ; 55
                MOV     BP, SP                          ; 8B EC
                PUSH    SI                              ; 56
                PUSH    DI                              ; 57
                MOV     DX, [BP+0EH]                    ; 8B 56 0E    size hi
                MOV     AX, [BP+0CH]                    ; 8B 46 0C    size lo
                SHR     DX, 1                           ; D1 EA
                RCR     AX, 1                           ; D1 D8
                SHR     DX, 1                           ; D1 EA
                RCR     AX, 1                           ; D1 D8       size /= 4
                PUSH    AX                              ; 50
                MOV     AX, 0A600H                      ; B8 00 A6
                PUSH    AX                              ; 50          scratch seg
                XOR     AX, AX                          ; 33 C0
                PUSH    AX                              ; 50          scratch off=0
                MOV     AX, [BP+0AH]                    ; 8B 46 0A
                PUSH    AX                              ; 50          src seg
                MOV     AX, [BP+8]                      ; 8B 46 08
                PUSH    AX                              ; 50          src off
                PUSH    CS                              ; 0E
                CALL    NEAR PTR ega_chunky_to_planar_row ; E8 7C 00
                ADD     SP, 0CH                         ; 83 C4 0C
                XOR     DI, DI                          ; 33 FF
                MOV     BX, [BP+6]                      ; 8B 5E 06    record array
@@id_loop:
                PUSH    BX                              ; 53
                MOV     SI, [BX]                        ; 8B 37
                OR      SI, SI                          ; 0B F6
                JNZ     SHORT @@id_have_rec             ; 75 02
                JMP     SHORT @@id_done                 ; EB 66
@@id_have_rec:
                MOV     AX, [SI+6]                      ; 8B 44 06    width
                SHR     AX, 1                           ; D1 E8
                MOV     DX, [SI+8]                      ; 8B 54 08    height
                MUL     DX                              ; F7 E2
                SHR     AX, 1                           ; D1 E8
                SHR     AX, 1                           ; D1 E8       AX = w/2*h/4
                MOV     BX, AX                          ; 8B D8
                SHL     BX, 1                           ; D1 E3
                SHL     BX, 1                           ; D1 E3       BX = AX*4
                PUSH    AX                              ; 50
                MOV     AX, [BP+0AH]                    ; 8B 46 0A
                MOV     [SI], AX                        ; 89 04       record.seg
                PUSH    AX                              ; 50
                MOV     AX, [BP+8]                      ; 8B 46 08
                MOV     [SI+2], AX                      ; 89 44 02    record.off
                PUSH    AX                              ; 50
                ADD     BX, [BP+8]                      ; 03 5E 08
                MOV     [SI+4], BX                      ; 89 5C 04
                MOV     [BP+8], BX                      ; 89 5E 08
                MOV     AX, 0A600H                      ; B8 00 A6
                PUSH    AX                              ; 50
                PUSH    DI                              ; 57
                PUSH    CS                              ; 0E
                CALL    NEAR PTR ega_read_planes_to_buffer ; E8 3A 01
                ADD     SP, 8                           ; 83 C4 08
                MOV     AX, [BP+8]                      ; 8B 46 08
                PUSH    AX                              ; 50
                MOV     AX, 0A600H                      ; B8 00 A6
                PUSH    AX                              ; 50
                PUSH    DI                              ; 57
                PUSH    CS                              ; 0E
                CALL    NEAR PTR ega_build_transparency_mask ; E8 5D 01
                ADD     SP, 0AH                         ; 83 C4 0A
                POP     AX                              ; 58
                ADD     DI, AX                          ; 03 F8
                ADD     AX, [BP+8]                     ; 03 46 08
                MOV     DX, AX                          ; 8B D0
                SHR     DX, 1                           ; D1 EA
                SHR     DX, 1                           ; D1 EA
                SHR     DX, 1                           ; D1 EA
                SHR     DX, 1                           ; D1 EA
                ADD     [BP+0AH], DX                    ; 01 56 0A
                AND     AX, 0FH                         ; 25 0F 00
                MOV     [BP+8], AX                      ; 89 46 08
                POP     BX                              ; 5B
                ADD     BX, 2                           ; 83 C3 02
                JMP     SHORT @@id_loop                 ; EB 91
@@id_done:
                POP     ES                              ; 07
                POP     DI                              ; 5F
                POP     SI                              ; 5E
                POP     BP                              ; 5D
                RETF                                    ; CB
ega_image_decode ENDP

; ============================================================================
; ega_chunky_to_planar_row @ 0x0E9B..0x0F9E (259 bytes)
;
; NEAR. Per-byte chunky->planar bit-shuffle, similar to blit_chunky_to_ega
; but writes the planar bytes to a caller-supplied DS:SI scratch buffer
; rather than the framebuffer (caller then uses read_planes_to_buffer to
; harvest). 32 SHL+RCL groups unrolled per source-word pair.
;
; Used as a helper from ega_image_decode (one of three sub-calls per image).
; ============================================================================
ega_chunky_to_planar_row PROC NEAR
                PUSH    BP                              ; 55
                MOV     BP, SP                          ; 8B EC
                PUSH    SI                              ; 56
                PUSH    DI                              ; 57
                PUSH    DS                              ; 1E
                ; Set up GC state for plane-cycling fill via SR2 Map Mask:
                ;   GR5 (Mode) = 0x00  -> write-mode 0 (CPU byte unchanged
                ;                         through the pipe; Set/Reset off);
                ;   GR8 (Bit Mask) = 0xFF -> every bit of the CPU byte
                ;                            passes through to its plane.
                ; The wm2 / Bit Mask=FF setup written first by 0205H + FF08H
                ; is overwritten three OUTs later by 0005H -- we end up in
                ; write-mode 0, which is what the loop below depends on.
                MOV     AX, 0205H                       ; B8 05 02
                MOV     DX, 03CEH                       ; BA CE 03
                OUT     DX, AX                          ; EF           GR5=02 (briefly)
                MOV     AX, 0FF08H                      ; B8 08 FF
                OUT     DX, AX                          ; EF           GR8 (Bit Mask) = 0xFF
                MOV     AX, 0005H                       ; B8 05 00
                MOV     DX, 03CEH                       ; BA CE 03
                OUT     DX, AX                          ; EF           GR5=00 (final: wm0, rm0)
                MOV     DI, [BP+0AH]                    ; 8B 7E 0A
                MOV     AX, [BP+0CH]                    ; 8B 46 0C
                MOV     ES, AX                          ; 8E C0
                MOV     SI, [BP+6]                      ; 8B 76 06
                MOV     AX, [BP+8]                      ; 8B 46 08
                MOV     BP, [BP+0EH]                    ; 8B 6E 0E     byte count
                MOV     DS, AX                          ; 8E D8
                MOV     DX, 03C4H                       ; BA C4 03
                MOV     AX, 0102H                       ; B8 02 01     AH=01 plane 0, AL=02 Map Mask
                OUT     DX, AX                          ; EF
@@ctpr_loop:
                LODSW                                   ; AD
                SHL     AL, 1                           ; D0 E0
                RCL     CH, 1                           ; D0 D5
                SHL     AL, 1                           ; D0 E0
                RCL     CL, 1                           ; D0 D1
                SHL     AL, 1                           ; D0 E0
                RCL     BH, 1                           ; D0 D7
                SHL     AL, 1                           ; D0 E0
                RCL     BL, 1                           ; D0 D3
                SHL     AL, 1                           ; D0 E0
                RCL     CH, 1                           ; D0 D5
                SHL     AL, 1                           ; D0 E0
                RCL     CL, 1                           ; D0 D1
                SHL     AL, 1                           ; D0 E0
                RCL     BH, 1                           ; D0 D7
                SHL     AL, 1                           ; D0 E0
                RCL     BL, 1                           ; D0 D3
                MOV     AL, AH                          ; 8A C4
                SHL     AL, 1                           ; D0 E0
                RCL     CH, 1                           ; D0 D5
                SHL     AL, 1                           ; D0 E0
                RCL     CL, 1                           ; D0 D1
                SHL     AL, 1                           ; D0 E0
                RCL     BH, 1                           ; D0 D7
                SHL     AL, 1                           ; D0 E0
                RCL     BL, 1                           ; D0 D3
                SHL     AL, 1                           ; D0 E0
                RCL     CH, 1                           ; D0 D5
                SHL     AL, 1                           ; D0 E0
                RCL     CL, 1                           ; D0 D1
                SHL     AL, 1                           ; D0 E0
                RCL     BH, 1                           ; D0 D7
                SHL     AL, 1                           ; D0 E0
                RCL     BL, 1                           ; D0 D3
                XOR     DX, DX                          ; 33 D2
                MOV     AX, [SI]                        ; 8B 04
                ADD     SI, 2                           ; 83 C6 02
                RCL     DH, 1                           ; D0 D6
                SHL     DH, 1                           ; D0 E6
                SHL     DH, 1                           ; D0 E6
                SHL     DH, 1                           ; D0 E6
                SHL     DH, 1                           ; D0 E6
                SHL     AL, 1                           ; D0 E0
                RCL     CH, 1                           ; D0 D5
                SHL     AL, 1                           ; D0 E0
                RCL     CL, 1                           ; D0 D1
                SHL     AL, 1                           ; D0 E0
                RCL     BH, 1                           ; D0 D7
                SHL     AL, 1                           ; D0 E0
                RCL     BL, 1                           ; D0 D3
                SHL     AL, 1                           ; D0 E0
                RCL     CH, 1                           ; D0 D5
                SHL     AL, 1                           ; D0 E0
                RCL     CL, 1                           ; D0 D1
                SHL     AL, 1                           ; D0 E0
                RCL     BH, 1                           ; D0 D7
                SHL     AL, 1                           ; D0 E0
                RCL     BL, 1                           ; D0 D3
                MOV     AL, AH                          ; 8A C4
                SHL     AL, 1                           ; D0 E0
                RCL     CH, 1                           ; D0 D5
                SHL     AL, 1                           ; D0 E0
                RCL     CL, 1                           ; D0 D1
                SHL     AL, 1                           ; D0 E0
                RCL     BH, 1                           ; D0 D7
                SHL     AL, 1                           ; D0 E0
                RCL     BL, 1                           ; D0 D3
                SHL     AL, 1                           ; D0 E0
                RCL     CH, 1                           ; D0 D5
                SHL     AL, 1                           ; D0 E0
                RCL     CL, 1                           ; D0 D1
                SHL     AL, 1                           ; D0 E0
                RCL     BH, 1                           ; D0 D7
                SHL     AL, 1                           ; D0 E0
                RCL     BL, 1                           ; D0 D3
                MOV     AX, DS                          ; 8C D8
                ADD     AX, DX                          ; 03 C2
                MOV     DS, AX                          ; 8E D8        bump DS by spillover
                MOV     DX, 03C5H                       ; BA C5 03     Sequencer data
                MOV     AL, 1                           ; B0 01        Map Mask = 1 (plane 0)
                OUT     DX, AL                          ; EE
                MOV     es:[DI], BL                     ; 26 88 1D
                SHL     AL, 1                           ; D0 E0        plane 1
                OUT     DX, AL                          ; EE
                MOV     es:[DI], BH                     ; 26 88 3D
                SHL     AL, 1                           ; D0 E0        plane 2
                OUT     DX, AL                          ; EE
                MOV     es:[DI], CL                     ; 26 88 0D
                SHL     AL, 1                           ; D0 E0        plane 3
                OUT     DX, AL                          ; EE
                MOV     es:[DI], CH                     ; 26 88 2D
                INC     DI                              ; 47
                DEC     BP                              ; 4D
                JZ      SHORT @@ctpr_done               ; 74 03
                JMP     @@ctpr_loop                     ; E9 42 FF
@@ctpr_done:
                MOV     AX, 0205H                       ; B8 05 02     restore wm2
                MOV     DX, 03CEH                       ; BA CE 03
                OUT     DX, AX                          ; EF
                MOV     AX, 0F02H                       ; B8 02 0F     Map Mask = 0F
                MOV     DX, 03C4H                       ; BA C4 03
                OUT     DX, AX                          ; EF
                POP     DS                              ; 1F
                POP     DI                              ; 5F
                POP     SI                              ; 5E
                POP     BP                              ; 5D
                RET                                     ; C3
ega_chunky_to_planar_row ENDP

; ============================================================================
; ega_read_planes_to_buffer @ 0x0F9E..0x0FD1 (51 bytes)
;
; NEAR helper. Copies "byte width" bytes from EGA framebuffer (one plane at a
; time, using GC reg 4 = Read Plane Select) into a chunky buffer. Plane order
; written is 0,1,2,3 (low byte of AX is GC index 4; AH is the plane number).
;
; ARGS (near, pushed before CALL by callers):
;   [BP+ 6] DS:SI source seg-off  (framebuffer plane)
;   [BP+ 8] DS:SI source seg
;   [BP+ A] ES:DI dest seg-off
;   [BP+ C] ES:DI dest seg
;   [BP+ E] byte width per plane
; ============================================================================
ega_read_planes_to_buffer PROC NEAR
                PUSH    BP                              ; 55
                MOV     BP, SP                          ; 8B EC
                PUSH    SI                              ; 56
                PUSH    DI                              ; 57
                PUSH    DS                              ; 1E
                MOV     DI, [BP+0AH]                    ; 8B 7E 0A
                MOV     AX, [BP+0CH]                    ; 8B 46 0C
                MOV     ES, AX                          ; 8E C0
                MOV     SI, [BP+6]                      ; 8B 76 06
                MOV     AX, [BP+8]                      ; 8B 46 08
                MOV     DS, AX                          ; 8E D8
                MOV     BX, [BP+0EH]                    ; 8B 5E 0E
                MOV     AX, 0004H                       ; B8 04 00     AH=plane, AL=idx 4 (Read Plane)
                MOV     BP, 4                           ; BD 04 00     loop count
                MOV     DX, 03CEH                       ; BA CE 03     GC index
@@rptb_loop:
                OUT     DX, AX                          ; EF
                MOV     CX, BX                          ; 8B CB
                PUSH    SI                              ; 56
                REP     MOVSB                           ; F3 A4
                POP     SI                              ; 5E
                INC     AH                              ; FE C4        next plane
                DEC     BP                              ; 4D
                JNZ     SHORT @@rptb_loop               ; 75 F4
                POP     DS                              ; 1F
                POP     DI                              ; 5F
                POP     SI                              ; 5E
                POP     BP                              ; 5D
                RET                                     ; C3
ega_read_planes_to_buffer ENDP

; ============================================================================
; ega_build_transparency_mask @ 0x0FD1..0x1014 (67 bytes)
;
; NEAR helper. For each source byte at DS:SI, reads the SAME byte from all
; four EGA planes (via GC reg 4 = Read Plane Select), ORs them together
; into AH, NOTs the result, and stores it at ES:DI. The output is a
; transparency mask: bits set where ALL planes are 0 (background pixel),
; bits clear where at least one plane has data (opaque pixel).
;
; ARGS (near): [BP+6/8]=src DS:SI, [BP+A/C]=dst ES:DI, [BP+E]=byte count
; ============================================================================
ega_build_transparency_mask PROC NEAR
                PUSH    BP                              ; 55
                MOV     BP, SP                          ; 8B EC
                PUSH    SI                              ; 56
                PUSH    DI                              ; 57
                PUSH    DS                              ; 1E
                MOV     DI, [BP+0AH]                    ; 8B 7E 0A
                MOV     AX, [BP+0CH]                    ; 8B 46 0C
                MOV     ES, AX                          ; 8E C0
                MOV     SI, [BP+6]                      ; 8B 76 06
                MOV     AX, [BP+8]                      ; 8B 46 08
                MOV     DS, AX                          ; 8E D8
                MOV     BP, [BP+0EH]                    ; 8B 6E 0E    byte count
                MOV     DX, 03CEH                       ; BA CE 03
                MOV     AX, 0004H                       ; B8 04 00    AH=plane 0, AL=GC idx 4
                OUT     DX, AX                          ; EF
                INC     DX                              ; 42          DX = 0x3CF (data)
@@btm_loop:
                XOR     AL, AL                          ; 32 C0       plane 0
                OUT     DX, AL                          ; EE
                MOV     AH, [SI]                        ; 8A 24
                INC     AL                              ; FE C0       plane 1
                OUT     DX, AL                          ; EE
                OR      AH, [SI]                        ; 0A 24
                INC     AL                              ; FE C0       plane 2
                OUT     DX, AL                          ; EE
                OR      AH, [SI]                        ; 0A 24
                INC     AL                              ; FE C0       plane 3
                OUT     DX, AL                          ; EE
                OR      AH, [SI]                        ; 0A 24
                MOV     AL, AH                          ; 8A C4
                NOT     AL                              ; F6 D0       transparent bits
                STOSB                                   ; AA
                INC     SI                              ; 46
                DEC     BP                              ; 4D
                JNZ     SHORT @@btm_loop                ; 75 E3
                POP     DS                              ; 1F
                POP     DI                              ; 5F
                POP     SI                              ; 5E
                POP     BP                              ; 5D
                RET                                     ; C3
ega_build_transparency_mask ENDP

; ============================================================================
; ega_blit_sprite_noflip @ 0x1014..0x102E (26 bytes)
;
; FAR thunk into ega_blit_sprite_master with an extra 0 prepended for the
; flags arg. Used from vtable slot 3 (no-flip sprite blit). The master
; routine takes (sprite_desc_off, dst_x, dst_y, flags); this thunk pushes
; the caller's three args plus flags=0 and synthesises a FAR call.
; ============================================================================
ega_blit_sprite_noflip PROC FAR
                PUSH    BP                              ; 55
                MOV     BP, SP                          ; 8B EC
                XOR     AX, AX                          ; 33 C0
                PUSH    AX                              ; 50           flags = 0
                PUSH    WORD PTR [BP+0AH]               ; FF 76 0A     dst_y
                PUSH    WORD PTR [BP+8]                 ; FF 76 08     dst_x
                PUSH    WORD PTR [BP+6]                 ; FF 76 06     sprite_desc_off
                PUSH    CS                              ; 0E           synthesise FAR call
                CALL    NEAR PTR ega_blit_sprite_master ; E8 9D 04
                ADD     SP, 8                           ; 83 C4 08
                MOV     BP, SP                          ; 8B EC
                POP     BP                              ; 5D
                RETF                                    ; CB
ega_blit_sprite_noflip ENDP

; ============================================================================
; ega_blit_glyph_row @ 0x102E..0x10DE (176 bytes)
;
; FAR entry called via the renderer-vtable slot 1 (8 pixel font row blit).
; Two runtime-self-modifying byte slots are at 0x10DC (foreground colour)
; and 0x10DD (background colour) -- referenced via MOV cs:[10DC] /
; MOV cs:[10DD] inside the function body. On disk these bytes are 0;
; first invocation patches them and they remain set for the whole session.
;
; ARGS (register, FAR call):
;   AX = source pixel-row pattern byte (8 source bits, packed)
;   BX = row count (-> CX in body)
;   CX = source segment? (callers fix DS via cs:[7D])
;   DX = dst x
;   BP = dst y
;   SI = src pointer offset
; The vtable thunk that calls this passes (FG colour, BG colour, mode flag)
; via a 3-byte buffer at DS:[0,1,2] which the entry copies to cs:[10DC..10DE].
; ============================================================================
ega_blit_glyph_row PROC FAR
                PUSH    SI                              ; 56
                PUSH    BP                              ; 55
                PUSH    DS                              ; 1E
                MOV     DI, AX                          ; 8B F8
                PUSH    ES                              ; 06
                MOV     DS, cs:[7DH]                    ; 2E 8E 1E 7D 00
                MOV     ES, ds:[GfxContext.wGfxBlitDstPage]                    ; 8E 06 18 00     visible plane
                MOV     AL, ds:[0]                      ; A0 00 00
                MOV     cs:[10DCH], AL                  ; 2E A2 DC 10     stash fg
                MOV     AH, ds:[1]                      ; 8A 26 01 00
                MOV     cs:[10DDH], AH                  ; 2E 88 26 DD 10  stash bg
                SHL     BP, 1                           ; D1 E5
                MOV     DI, ds:[BP+(GfxContext.pRow_offset_lut)]                ; 3E 8B BE F2 06  row base
                MOV     AX, DX                          ; 8B C2
                SHR     AX, 1                           ; D1 E8
                SHR     AX, 1                           ; D1 E8
                SHR     AX, 1                           ; D1 E8           AX = x/8
                ADD     DI, AX                          ; 03 F8
                MOV     BX, CX                          ; 8B D9           BX = row count
                MOV     CX, DX                          ; 8B CA
                AND     CX, 7                           ; 83 E1 07
                MOV     AH, ds:[2]                      ; 8A 26 02 00     transparent-fg mode flag
                POP     DS                              ; 1F
                MOV     DX, 03CEH                       ; BA CE 03
                MOV     AL, 8                           ; B0 08
                OUT     DX, AL                          ; EE              GC idx 8
                INC     DX                              ; 42
                MOV     CH, cs:[10DCH]                  ; 2E 8A 2E DC 10  fg
                OR      AH, AH                          ; 0A E4
                JZ      SHORT @@bgr_with_bg             ; 74 1F
@@bgr_fg_loop:
                ; --- fg-only loop (transparent BG) ---
                LODSB                                   ; AC              pattern byte
                XOR     AH, AH                          ; 32 E4
                ROR     AX, CL                          ; D3 C8           split across 2 bytes
                OUT     DX, AL                          ; EE
                MOV     AL, es:[DI]                     ; 26 8A 05        latch
                MOV     AL, CH                          ; 8A C5           fg byte
                STOSB                                   ; AA
                MOV     AL, AH                          ; 8A C4
                OUT     DX, AL                          ; EE              spillover bits
                MOV     AL, es:[DI]                     ; 26 8A 05
                MOV     AL, CH                          ; 8A C5
                STOSB                                   ; AA
                ADD     DI, 26H                         ; 83 C7 26        next row (38)
                DEC     BX                              ; 4B
                JNZ     SHORT @@bgr_fg_loop             ; 75 E5
                POP     DS                              ; 1F
                POP     BP                              ; 5D
                POP     SI                              ; 5E
                RETF                                    ; CB
@@bgr_with_bg:
                ; --- fg+bg loop ---
                MOV     BP, BX                          ; 8B EB
@@bgr_bg_loop:
                MOV     AL, es:[DI]                     ; 26 8A 05
                LODSB                                   ; AC
                XOR     BX, BX                          ; 33 DB
                DEC     BL                              ; FE CB           BL = ~0 (bg mask)
                XOR     AH, AH                          ; 32 E4
                ROR     AX, CL                          ; D3 C8
                ROR     BX, CL                          ; D3 CB
                XCHG    AL, BL                          ; 86 C3
                OUT     DX, AL                          ; EE              bg-mask byte
                MOV     AL, cs:[10DDH]                  ; 2E A0 DD 10     bg colour
                MOV     es:[DI], AL                     ; 26 88 05
                XCHG    AL, BL                          ; 86 C3
                OUT     DX, AL                          ; EE              fg-mask byte
                MOV     AL, es:[DI]                     ; 26 8A 05
                MOV     AL, CH                          ; 8A C5           fg
                STOSB                                   ; AA
                MOV     AL, es:[DI]                     ; 26 8A 05
                MOV     AL, BH                          ; 8A C7           spillover bg
                OUT     DX, AL                          ; EE
                MOV     AL, cs:[10DDH]                  ; 2E A0 DD 10
                MOV     es:[DI], AL                     ; 26 88 05
                MOV     AL, AH                          ; 8A C4           spillover fg
                OUT     DX, AL                          ; EE
                MOV     AL, es:[DI]                     ; 26 8A 05
                MOV     AL, CH                          ; 8A C5
                STOSB                                   ; AA
                ADD     DI, 26H                         ; 83 C7 26
                DEC     BP                              ; 4D
                JNZ     SHORT @@bgr_bg_loop             ; 75 C3
                POP     DS                              ; 1F
                POP     BP                              ; 5D
                POP     SI                              ; 5E
                RETF                                    ; CB
                ; 0x10DC..0x10DD: dual-use slots overwritten at first call
                ; with fg/bg colour bytes pulled from caller DS:[0..2].
g_bEgaGlyphFgColour:
                DB      0                               ; 00
g_bEgaGlyphBgColour:
                DB      0                               ; 00
ega_blit_glyph_row ENDP

; ============================================================================
; ega_save_rect @ 0x10DE..0x116C (142 bytes)
;
; FAR. Reads a rect from back-buffer plane [16] into a caller-supplied
; chunky buffer (4 planes interleaved, one plane at a time via GC read-
; plane select). The plane index is in AH and counts DOWN from 3 to 0.
; ============================================================================
ega_save_rect PROC FAR
                PUSH    BP                              ; 55
                MOV     BP, SP                          ; 8B EC
                PUSH    SI                              ; 56
                PUSH    DI                              ; 57
                PUSH    DS                              ; 1E
                PUSH    ES                              ; 06
                MOV     DS, cs:[7DH]                    ; 2E 8E 1E 7D 00
                MOV     DX, 03CEH                       ; BA CE 03
                MOV     AX, 0005H                       ; B8 05 00     GC Mode = 0 (read)
                OUT     DX, AX                          ; EF
                MOV     AX, 0FF08H                      ; B8 08 FF     GC Bit Mask = FF
                OUT     DX, AX                          ; EF
                XOR     AX, AX                          ; 33 C0
                OUT     DX, AX                          ; EF           GC idx 0 = 0
                MOV     AX, [BP+6]                      ; 8B 46 06     x
                MOV     DI, AX                          ; 8B F8
                SHR     AX, 1                           ; D1 E8
                SHR     AX, 1                           ; D1 E8
                SHR     AX, 1                           ; D1 E8
                SHR     AX, 1                           ; D1 E8        AX = x/16
                AND     DI, 0FH                         ; 83 E7 0F
                ADD     AX, [BP+8]                      ; 03 46 08     +dst_seg
                MOV     ES, AX                          ; 8E C0
                MOV     CX, [BP+0AH]                    ; 8B 4E 0A     byte_width
                MOV     AX, CX                          ; 8B C1
                SHR     CX, 1                           ; D1 E9
                SHR     CX, 1                           ; D1 E9
                SHR     CX, 1                           ; D1 E9        CX = bytes / 8
                MOV     BX, [BP+0EH]                    ; 8B 5E 0E     width
                ADD     BX, AX                          ; 03 D8
                SHR     BX, 1                           ; D1 EB
                SHR     BX, 1                           ; D1 EB
                SHR     BX, 1                           ; D1 EB
                SUB     BX, CX                          ; 2B D9
                INC     BX                              ; 43
                MOV     DX, [BP+10H]                    ; 8B 56 10     row count
                MOV     SI, [BP+0CH]                    ; 8B 76 0C     y
                SHL     SI, 1                           ; D1 E6
                MOV     SI, ds:[SI+(GfxContext.pRow_offset_lut)]                ; 8B B4 F2 06  row base
                ADD     SI, CX                          ; 03 F1
                MOV     AX, ds:[GfxContext.wGfxBlitSrcPage]                    ; A1 16 00     back buffer A seg
                MOV     DS, AX                          ; 8E D8
                MOV     AX, 0304H                       ; B8 04 03     AH=3 (plane), AL=4 (Read Plane Select)
@@sr_plane:
                MOV     BP, DX                          ; 8B EA        save row count
                MOV     DX, 03CEH                       ; BA CE 03
                OUT     DX, AX                          ; EF           set plane
                MOV     DX, BP                          ; 8B D5
                PUSH    DX                              ; 52
                PUSH    SI                              ; 56
@@sr_row:
                MOV     BP, SI                          ; 8B EE
                MOV     CX, BX                          ; 8B CB
                SHR     CX, 1                           ; D1 E9
                JNC     SHORT @@sr_no_odd               ; 73 01
                MOVSB                                   ; A4
@@sr_no_odd:
                REP     MOVSW                           ; F3 A5
                MOV     SI, BP                          ; 8B F5
                ADD     SI, 28H                         ; 83 C6 28     +40 next row
                DEC     DX                              ; 4A
                JNZ     SHORT @@sr_row                  ; 75 ED
                POP     SI                              ; 5E
                POP     DX                              ; 5A
                DEC     AH                              ; FE CC        plane--
                JNL     SHORT @@sr_plane                ; 7D DD        next plane
                MOV     DX, 03CEH                       ; BA CE 03
                MOV     AX, 0205H                       ; B8 05 02     restore Mode=wm2
                OUT     DX, AX                          ; EF
                POP     ES                              ; 07
                POP     DS                              ; 1F
                POP     DI                              ; 5F
                POP     SI                              ; 5E
                POP     BP                              ; 5D
                RETF                                    ; CB
ega_save_rect ENDP

; ============================================================================
; ega_query_sprite_buffer_size @ 0x116C..0x1190 (36 bytes)
;
; FAR helper used by sprite save/paste flows to compute the buffer size
; required to capture a sprite-shaped rect from the framebuffer.
;
; ARGS (far): [BP+6] = pixel width, [BP+8] = pixel height
; RETURNS:    DX:AX = 4 * ((width+7)/8 + 1) * height bytes
;             (one byte per 8 pixels per plane * 4 planes = bytes per pixel-row;
;              the +1 byte slack accounts for unaligned start x.)
; ============================================================================
ega_query_sprite_buffer_size PROC FAR
                PUSH    BP                              ; 55
                MOV     BP, SP                          ; 8B EC
                MOV     AX, [BP+6]                      ; 8B 46 06    width
                MOV     BX, AX                          ; 8B D8
                SHR     BX, 1                           ; D1 EB
                SHR     BX, 1                           ; D1 EB
                SHR     BX, 1                           ; D1 EB       BX = width / 8
                INC     BX                              ; 43          +1 slack
                AND     AX, 7                           ; 25 07 00
                JZ      SHORT @@qsbs_no_pad             ; 74 01
                INC     BX                              ; 43          extra byte for unaligned x
@@qsbs_no_pad:
                MOV     AX, [BP+8]                      ; 8B 46 08    height
                MUL     BX                              ; F7 E3       AX = rows * bytes/row
                SHL     AX, 1                           ; D1 E0
                RCL     DX, 1                           ; D1 D2       DX:AX *= 2
                SHL     AX, 1                           ; D1 E0
                RCL     DX, 1                           ; D1 D2       DX:AX *= 2  (now *4 = planes)
                POP     BP                              ; 5D
                RETF                                    ; CB
ega_query_sprite_buffer_size ENDP

; ============================================================================
; ega_paste_rect @ 0x1190..0x1225 (149 bytes)
;
; FAR. Mirror of ega_save_rect that writes a chunky 4-plane buffer back to
; the visible plane [18]. Per-plane writes select planes via Sequencer reg 2
; (Map Mask) with a 1-bit walking mask (AH starts 0x08 = plane 3 and shifts
; right). Each plane's bytes are REP MOVSed into the framebuffer row by row.
; Restores GC Mode = wm2 and Map Mask = 0x0F at the end.
; ============================================================================
ega_paste_rect PROC FAR
                PUSH    BP                              ; 55
                MOV     BP, SP                          ; 8B EC
                PUSH    SI                              ; 56
                PUSH    DI                              ; 57
                PUSH    DS                              ; 1E
                PUSH    ES                              ; 06
                MOV     DX, 03CEH                       ; BA CE 03
                MOV     AX, 0005H                       ; B8 05 00     GC Mode = 0 (write through)
                OUT     DX, AX                          ; EF
                MOV     AX, 0FF08H                      ; B8 08 FF     Bit Mask = FF
                OUT     DX, AX                          ; EF
                XOR     AX, AX                          ; 33 C0
                OUT     DX, AX                          ; EF           GC reg 0 = 0
                MOV     AX, [BP+6]                      ; 8B 46 06     x
                MOV     SI, AX                          ; 8B F0
                SHR     AX, 1                           ; D1 E8
                SHR     AX, 1                           ; D1 E8
                SHR     AX, 1                           ; D1 E8
                SHR     AX, 1                           ; D1 E8        AX = x/16
                AND     SI, 0FH                         ; 83 E6 0F
                ADD     AX, [BP+8]                      ; 03 46 08     +src_seg
                PUSH    AX                              ; 50
                MOV     CX, [BP+0AH]                    ; 8B 4E 0A
                MOV     AX, CX                          ; 8B C1
                SHR     CX, 1                           ; D1 E9
                SHR     CX, 1                           ; D1 E9
                SHR     CX, 1                           ; D1 E9        CX = bytes / 8
                MOV     BX, [BP+0EH]                    ; 8B 5E 0E
                ADD     BX, AX                          ; 03 D8
                SHR     BX, 1                           ; D1 EB
                SHR     BX, 1                           ; D1 EB
                SHR     BX, 1                           ; D1 EB
                SUB     BX, CX                          ; 2B D9
                INC     BX                              ; 43
                MOV     DS, cs:[7DH]                    ; 2E 8E 1E 7D 00
                MOV     DX, [BP+10H]                    ; 8B 56 10
                MOV     DI, [BP+0CH]                    ; 8B 7E 0C     y
                SHL     DI, 1                           ; D1 E7
                MOV     DI, ds:[DI+(GfxContext.pRow_offset_lut)]                ; 8B BD F2 06
                ADD     DI, CX                          ; 03 F9
                MOV     AX, ds:[GfxContext.wGfxBlitDstPage]                    ; A1 18 00     visible plane seg
                MOV     ES, AX                          ; 8E C0
                POP     DS                              ; 1F           DS = src_seg
                MOV     AX, 0802H                       ; B8 02 08     AH=08 (plane 3), AL=02 (Seq Map Mask)
@@pst_plane:
                MOV     BP, DX                          ; 8B EA
                MOV     DX, 03C4H                       ; BA C4 03     Sequencer
                OUT     DX, AX                          ; EF           Map Mask = AH
                MOV     DX, BP                          ; 8B D5
                PUSH    DX                              ; 52
                PUSH    DI                              ; 57
@@pst_row:
                MOV     BP, DI                          ; 8B EF
                MOV     CX, BX                          ; 8B CB
                SHR     CX, 1                           ; D1 E9
                JNC     SHORT @@pst_no_odd              ; 73 01
                MOVSB                                   ; A4
@@pst_no_odd:
                REP     MOVSW                           ; F3 A5
                MOV     DI, BP                          ; 8B FD
                ADD     DI, 28H                         ; 83 C7 28
                DEC     DX                              ; 4A
                JNZ     SHORT @@pst_row                 ; 75 ED
                POP     DI                              ; 5F
                POP     DX                              ; 5A
                SHR     AH, 1                           ; D0 EC        next plane bit
                JNC     SHORT @@pst_plane               ; 73 DD
                MOV     DX, 03CEH                       ; BA CE 03
                MOV     AX, 0205H                       ; B8 05 02     restore GC Mode = wm2
                OUT     DX, AX                          ; EF
                MOV     DX, 03C4H                       ; BA C4 03
                MOV     AX, 0F02H                       ; B8 02 0F     restore Map Mask = 0F
                OUT     DX, AX                          ; EF
                POP     ES                              ; 07
                POP     DS                              ; 1F
                POP     DI                              ; 5F
                POP     SI                              ; 5E
                POP     BP                              ; 5D
                RETF                                    ; CB
ega_paste_rect ENDP

; ============================================================================
; ega_getpixel @ 0x1225..0x129A (117 bytes)
;
; FAR. Reads one pixel from the back buffer [16]. The read uses read-mode
; 0 (CPU sees the plane GR4 selects) and cycles GR4 = 0,1,2,3 to fetch
; the 4 bits that make up the pixel's colour index.  The "GR5 = 0x01"
; that the prologue writes sets write-mode 1 -- which has no effect on
; the read pipeline, since GR5 bit 3 (read mode) stays 0.  Why the
; driver writes the Mode register here at all is unclear; leaving GR5
; at its 0x02 default would work too.  AH = 0x80 >> (x & 7) is the
; single-bit mask AND-tested against each plane's byte; the four
; results become the 4 bits of CL.
;
; ARGS (far): [BP+6]=x, [BP+8]=y
; RETURN:     AX = colour (0..0xF)
; ============================================================================
ega_getpixel PROC FAR
                PUSH    BP                              ; 55
                MOV     BP, SP                          ; 8B EC
                PUSH    DS                              ; 1E
                MOV     DS, cs:[7DH]                    ; 2E 8E 1E 7D 00
                MOV     ES, ds:[GfxContext.wGfxBlitSrcPage]                    ; 8E 06 16 00  back buffer A
                MOV     BX, [BP+8]                      ; 8B 5E 08     y
                SHL     BX, 1                           ; D1 E3
                MOV     BX, ds:[BX+(GfxContext.pRow_offset_lut)]                ; 8B 9F F2 06  row base
                MOV     AX, [BP+6]                      ; 8B 46 06     x
                MOV     CX, AX                          ; 8B C8
                SHR     AX, 1                           ; D1 E8
                SHR     AX, 1                           ; D1 E8
                SHR     AX, 1                           ; D1 E8
                ADD     BX, AX                          ; 03 D8        BX = row+x/8
                MOV     DX, 03CEH                       ; BA CE 03
                MOV     AX, 0105H                       ; B8 05 01     GR5 (Mode) = 0x01 (wm1, rm0)
                OUT     DX, AX                          ; EF
                MOV     AX, 0004H                       ; B8 04 00     GR4 (Read Plane Sel) = 0 (B)
                OUT     DX, AX                          ; EF
                INC     DX                              ; 42           DX = 0x3CF (data)
                MOV     AH, 80H                         ; B4 80
                AND     CL, 7                           ; 80 E1 07
                SHR     AH, CL                          ; D2 EC        AH = pixel bit
                XOR     CX, CX                          ; 33 C9        colour accumulator
                MOV     AL, es:[BX]                     ; 26 8A 07
                TEST    AH, AL                          ; 84 E0
                JZ      SHORT @@gp_1                    ; 74 03
                OR      CL, 1                           ; 80 C9 01
@@gp_1:
                MOV     AL, 1                           ; B0 01
                OUT     DX, AL                          ; EE           plane 1
                MOV     AL, es:[BX]                     ; 26 8A 07
                TEST    AH, AL                          ; 84 E0
                JZ      SHORT @@gp_2                    ; 74 03
                OR      CL, 2                           ; 80 C9 02
@@gp_2:
                MOV     AL, 2                           ; B0 02
                OUT     DX, AL                          ; EE           plane 2
                MOV     AL, es:[BX]                     ; 26 8A 07
                TEST    AH, AL                          ; 84 E0
                JZ      SHORT @@gp_3                    ; 74 03
                OR      CL, 4                           ; 80 C9 04
@@gp_3:
                MOV     AL, 3                           ; B0 03
                OUT     DX, AL                          ; EE           plane 3
                MOV     AL, es:[BX]                     ; 26 8A 07
                TEST    AH, AL                          ; 84 E0
                JZ      SHORT @@gp_done                 ; 74 03
                OR      CL, 8                           ; 80 C9 08
@@gp_done:
                DEC     DX                              ; 4A
                MOV     AX, 0205H                       ; B8 05 02     restore Mode=wm2
                OUT     DX, AX                          ; EF
                MOV     AX, CX                          ; 8B C1        return colour
                POP     DS                              ; 1F
                MOV     SP, BP                          ; 8B E5
                POP     BP                              ; 5D
                RETF                                    ; CB
ega_getpixel ENDP

; ============================================================================
; ega_putpixel @ 0x129A..0x12D7 (61 bytes)
;
; FAR helper. Plots one pixel via EGA write-mode 2 (chunk default).
; ARGS (far): [BP+6]=x, [BP+8]=y, [BP+0A]=colour
;
; Mechanics: GC reg 8 (Bit Mask) = 80h >> (x & 7) makes ONE bit writable;
; reading the framebuffer byte latches all 4 planes; writing the colour
; byte broadcasts the low nibble to per-plane bits, masked by Bit Mask.
; ============================================================================
ega_putpixel PROC FAR
                PUSH    BP                              ; 55
                MOV     BP, SP                          ; 8B EC
                PUSH    DS                              ; 1E
                MOV     DS, cs:[7DH]                    ; 2E 8E 1E 7D 00
                MOV     ES, ds:[GfxContext.wGfxBlitDstPage]                    ; 8E 06 18 00     ES = visible plane base
                MOV     BX, [BP+8]                      ; 8B 5E 08        y
                SHL     BX, 1                           ; D1 E3
                MOV     BX, ds:[BX+(GfxContext.pRow_offset_lut)]                ; 8B 9F F2 06     row-base from LUT
                MOV     AX, [BP+6]                      ; 8B 46 06        x
                MOV     CX, AX                          ; 8B C8
                SHR     AX, 1                           ; D1 E8
                SHR     AX, 1                           ; D1 E8
                SHR     AX, 1                           ; D1 E8           AX = x/8
                ADD     BX, AX                          ; 03 D8
                AND     CX, 7                           ; 83 E1 07
                MOV     AX, 8008H                       ; B8 08 80        AH=80h, AL=8 (GC Bit Mask)
                SHR     AH, CL                          ; D2 EC           shift to pixel bit
                MOV     DX, 03CEH                       ; BA CE 03
                OUT     DX, AX                          ; EF              program bit mask
                MOV     AL, es:[BX]                     ; 26 8A 07        latch all planes
                MOV     AL, [BP+0AH]                    ; 8A 46 0A        colour
                MOV     es:[BX], AL                     ; 26 88 07        wm2 broadcast
                POP     DS                              ; 1F
                MOV     SP, BP                          ; 8B E5
                POP     BP                              ; 5D
                RETF                                    ; CB
ega_putpixel ENDP

; ============================================================================
; ega_vsync_wait @ 0x12D7..0x131E (71 bytes)
;
; FAR helper. Swaps the display segment (CRT start address) with the back
; buffer A segment in scratch:[12]/[14], programs the CRTC start-address
; high register (CRTC index 0Ch) to the new visible plane, and -- if
; [BP+6] != 0 -- spins until end-of-display then beginning of vertical
; retrace (so the next on-screen frame uses the new buffer).
;
; ARGS (far): [BP+6] = wait_flag (0 = don't wait for vsync)
; CALLS:      CRTC port (40:63 -> 0x3D4); status port 0x3DA bit 3 = vsync.
; ============================================================================
ega_vsync_wait PROC FAR
                PUSH    BP                              ; 55
                MOV     BP, SP                          ; 8B EC
                PUSH    ES                              ; 06
                PUSH    DS                              ; 1E
                MOV     DS, cs:[7DH]                    ; 2E 8E 1E 7D 00   DS = scratch
                MOV     AX, ds:[GfxContext.wVgaPage2Base]                    ; A1 12 00     "page 1" seg (CX)
                MOV     CX, AX                          ; 8B C8
                XCHG    AX, ds:[GfxContext.wVgaFrontPageBase]                    ; 87 06 14 00  swap [12] <-> [14]
                MOV     ds:[GfxContext.wVgaPage2Base], AX                    ; A3 12 00     (the "displayed page" rotates)
                ; CRTC reg 0Ch wants the high byte of the 16-bit Start Address
                ; (in *linear* bytes from the aperture base). For an EGA page at
                ; segment 0xA200 the linear page offset is 0x2000 and the high
                ; byte is 0x20.  We get that by `(seg - 0xA000) >> 4` = `seg >>
                ; 4 - 0x0A00`; since the SHR keeps a constant 0x0A00 offset
                ; that the BIOS already programs as the segment-base baseline,
                ; the driver just uses (seg >> 4) directly and lets the high
                ; bits be ignored / masked by the start-address register
                ; width.  [Source: FreeVGA crtcreg.htm index 0Ch/0Dh.]
                SHR     CX, 1                           ; D1 E9
                SHR     CX, 1                           ; D1 E9
                SHR     CX, 1                           ; D1 E9
                SHR     CX, 1                           ; D1 E9        CX = seg >> 4 (paragraphs)
                MOV     AX, 0040H                       ; B8 40 00
                MOV     ES, AX                          ; 8E C0        ES = BIOS data area
                MOV     DX, es:[63H]                    ; 26 8B 16 63 00  BDA 40:63 = CRTC idx port
                MOV     AL, 0CH                         ; B0 0C        idx 0Ch = Start Address Hi
                MOV     AH, CL                          ; 8A E1        AH = new high byte
                OUT     DX, AX                          ; EF           idx+data in one 16-bit OUT
                MOV     AX, [BP+6]                      ; 8B 46 06     wait_flag
                OR      AX, AX                          ; 0B C0
                JZ      SHORT @@vw_done                 ; 74 0F
                ; Spin for a tear-free flip.  Per VGADOC EGAREGS.TXT 3DAh
                ; bit 3 = "vertical retrace in progress".  Sequence is:
                ;   1. wait until bit 3 = 0 (display drawing - i.e. NOT in
                ;      vsync; ensures we don't see a vsync we missed the
                ;      start of);
                ;   2. wait until bit 3 = 1 (vsync just started -- CRTC has
                ;      now latched the new start address).
                MOV     CL, 8                           ; B1 08        mask for bit 3 = vsync-active
                MOV     DX, 03DAH                       ; BA DA 03     input-status-1
@@vw_wait_disp:
                IN      AL, DX                          ; EC
                AND     AL, CL                          ; 22 C1
                JNZ     SHORT @@vw_wait_disp            ; 75 FB        spin while bit3=1 (vsync up)
@@vw_wait_vsync:
                IN      AL, DX                          ; EC
                AND     AL, CL                          ; 22 C1
                JZ      SHORT @@vw_wait_vsync           ; 74 FB        spin until bit3=1 again
@@vw_done:
                POP     DS                              ; 1F
                POP     ES                              ; 07
                POP     BP                              ; 5D
                RETF                                    ; CB
ega_vsync_wait ENDP

; ============================================================================
; ega_present_rect @ 0x131E..0x1387 (105 bytes code; the 6 bytes that follow
; at 0x1387..0x138C are self-modifying state for the next function, not pad)
;
; FAR. Copies a rect from back-buffer plane [16] to visible plane [18]
; using EGA write-mode 1 (latch copy -- CPU data ignored; read at ES:[DI]
; latches all 4 planes, next write at ES:[DI] stores them back).
;
; ARGS (far): [BP+6]=x, [BP+8]=y, [BP+A]=width_px, [BP+C]=height_rows
; ============================================================================
ega_present_rect PROC FAR
                PUSH    BP                              ; 55
                MOV     BP, SP                          ; 8B EC
                PUSH    SI                              ; 56
                PUSH    DI                              ; 57
                PUSH    DS                              ; 1E
                PUSH    ES                              ; 06
                MOV     DS, cs:[7DH]                    ; 2E 8E 1E 7D 00
                MOV     DX, 03CEH                       ; BA CE 03
                MOV     AX, 0105H                       ; B8 05 01    GC reg 5 (Mode) = 0x01 (wm1)
                OUT     DX, AX                          ; EF
                MOV     BX, [BP+0AH]                    ; 8B 5E 0A    width
                MOV     AX, [BP+6]                      ; 8B 46 06    x
                ADD     BX, AX                          ; 03 D8       BX = x+w
                ADD     BX, 7                           ; 83 C3 07
                AND     BX, 0FFF8H                      ; 83 E3 F8    align end up to byte
                AND     AX, 0FFF8H                      ; 25 F8 FF    align x down to byte
                SUB     BX, AX                          ; 2B D8       width in pixels * 8
                SHR     BX, 1                           ; D1 EB
                SHR     BX, 1                           ; D1 EB
                SHR     BX, 1                           ; D1 EB       BX = byte count
                SHR     AX, 1                           ; D1 E8
                SHR     AX, 1                           ; D1 E8
                SHR     AX, 1                           ; D1 E8       AX = x/8
                MOV     SI, AX                          ; 8B F0
                MOV     DX, [BP+0CH]                    ; 8B 56 0C    row count
                MOV     DI, [BP+8]                      ; 8B 7E 08    y
                SHL     DI, 1                           ; D1 E7
                MOV     DI, ds:[DI+(GfxContext.pRow_offset_lut)]                ; 8B BD F2 06 row base
                ADD     DI, SI                          ; 03 FE       DI = row + x/8
                MOV     AX, ds:[GfxContext.wGfxBlitDstPage]                    ; A1 18 00    visible plane
                MOV     ES, AX                          ; 8E C0
                MOV     AX, ds:[GfxContext.wGfxBlitSrcPage]                    ; A1 16 00    back buffer A
                MOV     DS, AX                          ; 8E D8
@@pr_row:
                ; Per-row REP MOVSB in write-mode 1 = the EGA's hardware
                ; blitter.  DS:SI reads from the back-buffer plane (load
                ; latches with 4-plane content at that offset); ES:DI writes
                ; the same offset to the visible plane (wm1: write fans the
                ; latches across all 4 planes, CPU data is ignored).
                ; SI = DI by design -- the source and destination are at the
                ; same offset within their respective planes, just different
                ; aperture segments (DS=back-buffer A, ES=visible).
                MOV     CX, BX                          ; 8B CB
                MOV     BP, DI                          ; 8B EF
                MOV     SI, DI                          ; 8B F7
                REP     MOVSB                           ; F3 A4
                MOV     DI, BP                          ; 8B FD
                ADD     DI, 28H                         ; 83 C7 28    +40 (next row)
                DEC     DX                              ; 4A
                JNZ     SHORT @@pr_row                  ; 75 F0
                MOV     DX, 03CEH                       ; BA CE 03
                MOV     AX, 0205H                       ; B8 05 02    restore GC Mode = wm2
                OUT     DX, AX                          ; EF
                POP     ES                              ; 07
                POP     DS                              ; 1F
                POP     DI                              ; 5F
                POP     SI                              ; 5E
                POP     BP                              ; 5D
                RETF                                    ; CB
                ; 0x1387..0x138C: NOT padding. These 6 bytes are 3 CS-resident
                ; self-modifying state slots for ega_blit_chunky_to_ega (the
                ; next function), declared zero on disk and overwritten every
                ; call by its prologue. See its plate below:
                ;   cs:[1387]  bytes-per-row    (width/8)
                ;   cs:[1389]  negative row-stride (40 - bytes/row)
                ;   cs:[138B]  row count        ([BP+10] from caller)
                DB      0, 0, 0, 0, 0, 0
ega_present_rect ENDP

; ============================================================================
; ega_blit_chunky_to_ega @ 0x138D..0x14C4 (311 bytes)
;
; FAR. Converts a 4bpp packed-nibble (chunky) source buffer into planar
; EGA bytes and OR-merges them into the framebuffer. Loops over 16-pixel
; (8-byte) horizontal strips: reads 4 source bytes via LODSW twice, then
; for each byte SHL/RCL builds the 4 plane bytes (in BL/BH/CL/CH) by
; rotating one bit at a time through the four destination accumulators.
; Bit-twiddling block is fully unrolled (~128 SHL/RCL pairs).
;
; Three runtime self-modifying word slots:
;   cs:[1387]  bytes-per-row (saved width/8)
;   cs:[1389]  negative row-stride for DI rewind
;   cs:[138B]  row count
; ============================================================================
ega_blit_chunky_to_ega PROC FAR
                PUSH    BP                              ; 55
                MOV     BP, SP                          ; 8B EC
                PUSH    SI                              ; 56
                PUSH    DI                              ; 57
                PUSH    DS                              ; 1E
                MOV     DX, 03CEH                       ; BA CE 03
                MOV     AX, 0005H                       ; B8 05 00     GC Mode = 0 (write)
                OUT     DX, AX                          ; EF
                MOV     AX, 0FF08H                      ; B8 08 FF     Bit Mask = FF
                OUT     DX, AX                          ; EF
                MOV     DX, 03C4H                       ; BA C4 03     Sequencer index
                MOV     AL, 2                           ; B0 02
                OUT     DX, AL                          ; EE           idx = 2 (Map Mask)
                INC     DX                              ; 42           DX = 3C5 (data)
                MOV     DS, cs:[7DH]                    ; 2E 8E 1E 7D 00 DS = scratch
                MOV     BX, [BP+0CH]                    ; 8B 5E 0C     y
                SHL     BX, 1                           ; D1 E3
                MOV     DI, ds:[BX+(GfxContext.pRow_offset_lut)]                ; 8B BF F2 06  row base
                MOV     AX, [BP+0AH]                    ; 8B 46 0A
                SHR     AX, 1                           ; D1 E8
                SHR     AX, 1                           ; D1 E8
                SHR     AX, 1                           ; D1 E8        AX = x/8
                ADD     DI, AX                          ; 03 F8
                MOV     AX, ds:[GfxContext.wGfxBlitDstPage]                    ; A1 18 00
                MOV     ES, AX                          ; 8E C0        ES = visible
                MOV     AX, [BP+10H]                    ; 8B 46 10
                MOV     cs:[138BH], AX                  ; 2E A3 8B 13  row count
                MOV     AX, [BP+6]                      ; 8B 46 06     src x
                MOV     SI, AX                          ; 8B F0
                SHR     AX, 1                           ; D1 E8
                SHR     AX, 1                           ; D1 E8
                SHR     AX, 1                           ; D1 E8
                SHR     AX, 1                           ; D1 E8
                AND     SI, 0FH                         ; 83 E6 0F
                ADD     AX, [BP+8]                      ; 03 46 08
                MOV     DS, AX                          ; 8E D8        DS = src seg
                MOV     AX, [BP+0EH]                    ; 8B 46 0E
                SHR     AX, 1                           ; D1 E8
                SHR     AX, 1                           ; D1 E8
                SHR     AX, 1                           ; D1 E8        AX = width/8
                MOV     cs:[1387H], AX                  ; 2E A3 87 13
                MOV     BP, AX                          ; 8B E8        BP = bytes-per-row
                SUB     AX, 28H                         ; 2D 28 00     -40
                NEG     AX                              ; F7 D8        AX = 40 - bytes/row
                MOV     cs:[1389H], AX                  ; 2E A3 89 13
@@bcte_row:
                LODSW                                   ; AD           src word
                ; --- unrolled bit-shuffle: 16 SHL/RCL groups per LODSW ---
                SHL     AL, 1                           ; D0 E0
                RCL     CH, 1                           ; D0 D5
                SHL     AL, 1                           ; D0 E0
                RCL     CL, 1                           ; D0 D1
                SHL     AL, 1                           ; D0 E0
                RCL     BH, 1                           ; D0 D7
                SHL     AL, 1                           ; D0 E0
                RCL     BL, 1                           ; D0 D3
                SHL     AL, 1                           ; D0 E0
                RCL     CH, 1                           ; D0 D5
                SHL     AL, 1                           ; D0 E0
                RCL     CL, 1                           ; D0 D1
                SHL     AL, 1                           ; D0 E0
                RCL     BH, 1                           ; D0 D7
                SHL     AL, 1                           ; D0 E0
                RCL     BL, 1                           ; D0 D3
                SHL     AH, 1                           ; D0 E4
                RCL     CH, 1                           ; D0 D5
                SHL     AH, 1                           ; D0 E4
                RCL     CL, 1                           ; D0 D1
                SHL     AH, 1                           ; D0 E4
                RCL     BH, 1                           ; D0 D7
                SHL     AH, 1                           ; D0 E4
                RCL     BL, 1                           ; D0 D3
                SHL     AH, 1                           ; D0 E4
                RCL     CH, 1                           ; D0 D5
                SHL     AH, 1                           ; D0 E4
                RCL     CL, 1                           ; D0 D1
                SHL     AH, 1                           ; D0 E4
                RCL     BH, 1                           ; D0 D7
                SHL     AH, 1                           ; D0 E4
                RCL     BL, 1                           ; D0 D3
                LODSW                                   ; AD           src word 2
                SHL     AL, 1                           ; D0 E0
                RCL     CH, 1                           ; D0 D5
                SHL     AL, 1                           ; D0 E0
                RCL     CL, 1                           ; D0 D1
                SHL     AL, 1                           ; D0 E0
                RCL     BH, 1                           ; D0 D7
                SHL     AL, 1                           ; D0 E0
                RCL     BL, 1                           ; D0 D3
                SHL     AL, 1                           ; D0 E0
                RCL     CH, 1                           ; D0 D5
                SHL     AL, 1                           ; D0 E0
                RCL     CL, 1                           ; D0 D1
                SHL     AL, 1                           ; D0 E0
                RCL     BH, 1                           ; D0 D7
                SHL     AL, 1                           ; D0 E0
                RCL     BL, 1                           ; D0 D3
                SHL     AH, 1                           ; D0 E4
                RCL     CH, 1                           ; D0 D5
                SHL     AH, 1                           ; D0 E4
                RCL     CL, 1                           ; D0 D1
                SHL     AH, 1                           ; D0 E4
                RCL     BH, 1                           ; D0 D7
                SHL     AH, 1                           ; D0 E4
                RCL     BL, 1                           ; D0 D3
                SHL     AH, 1                           ; D0 E4
                RCL     CH, 1                           ; D0 D5
                SHL     AH, 1                           ; D0 E4
                RCL     CL, 1                           ; D0 D1
                SHL     AH, 1                           ; D0 E4
                RCL     BH, 1                           ; D0 D7
                SHL     AH, 1                           ; D0 E4
                RCL     BL, 1                           ; D0 D3
                MOV     AL, 1                           ; B0 01
                OUT     DX, AL                          ; EE           plane 0
                MOV     es:[DI], BL                     ; 26 88 1D
                SHL     AL, 1                           ; D0 E0
                OUT     DX, AL                          ; EE           plane 1
                MOV     es:[DI], BH                     ; 26 88 3D
                SHL     AL, 1                           ; D0 E0
                OUT     DX, AL                          ; EE           plane 2
                MOV     es:[DI], CL                     ; 26 88 0D
                SHL     AL, 1                           ; D0 E0
                OUT     DX, AL                          ; EE           plane 3
                MOV     AL, CH                          ; 8A C5
                STOSB                                   ; AA
                DEC     BP                              ; 4D
                JNG     SHORT @@bcte_next_row           ; 7E 03
                JMP     @@bcte_row                      ; E9 60 FF
@@bcte_next_row:
                MOV     AX, cs:[138BH]                  ; 2E A1 8B 13
                DEC     AX                              ; 48
                JNG     SHORT @@bcte_done               ; 7E 13
                MOV     cs:[138BH], AX                  ; 2E A3 8B 13
                MOV     AX, cs:[1387H]                  ; 2E A1 87 13
                MOV     BP, AX                          ; 8B E8
                MOV     AX, cs:[1389H]                  ; 2E A1 89 13
                ADD     DI, AX                          ; 03 F8
                JMP     @@bcte_row                      ; E9 46 FF
@@bcte_done:
                MOV     AL, 0FH                         ; B0 0F        Map Mask = 0F
                OUT     DX, AL                          ; EE
                MOV     AX, 0205H                       ; B8 05 02     GC Mode = wm2
                MOV     DX, 03CEH                       ; BA CE 03
                OUT     DX, AX                          ; EF
                MOV     AX, 0003H                       ; B8 03 00     GC Data Rotate = 0
                OUT     DX, AX                          ; EF
                POP     DS                              ; 1F
                POP     DI                              ; 5F
                POP     SI                              ; 5E
                POP     BP                              ; 5D
                RETF                                    ; CB
ega_blit_chunky_to_ega ENDP

; ============================================================================
; ega_blit_sprite_master @ 0x14C4..0x1675 (433 bytes)
;
; FAR. Master sprite-blit dispatcher. Copies the 10-byte sprite-descriptor
; frame from caller-supplied DS:SI to a stack-local buffer; computes the
; row/column starts using y-LUT @ scratch:[6F2]; handles V-flip / H-flip
; pre-bias (negative row stride for V-flip; H-flip slides SI to end +
; uses negative byte stride); applies clip-rect against DS:[6]/DS:[A] if
; DS:[3] is set; then dispatches to one of 4 sprite cores via the near-ptr
; table at CS:0x2357:
;   flags=0 -> ega_blit_sprite_noflip_core   (0x1675)
;   flags=1 -> ega_blit_sprite_flipy_core    (0x18EE)
;   flags=2 -> ega_blit_sprite_flipx_core    (0x1B67)
;   flags=3 -> ega_blit_sprite_flipxy_core   (0x1F53)
; ARGS (far): [BP+6]=sprite_desc_off, [BP+8]=dst_x, [BP+0A]=dst_y,
;             [BP+0C]=flags (bit0=hflip, bit1=vflip).
; ============================================================================
ega_blit_sprite_master PROC FAR
                PUSH    BP                              ; 55
                MOV     BP, SP                          ; 8B EC
                SUB     SP, 0AH                         ; 83 EC 0A
                PUSH    SI                              ; 56
                PUSH    DI                              ; 57
                PUSH    ES                              ; 06
                PUSH    DS                              ; 1E
                MOV     SI, [BP+6H]                     ; 8B 76 06
                MOV     DI, BP                          ; 8B FD
                SUB     DI, 0AH                         ; 83 EF 0A
                MOV     AX, DS                          ; 8C D8
                MOV     ES, AX                          ; 8E C0
                MOV     CX, 5H                          ; B9 05 00
                REP     MOVSW                           ; F3 A5
                MOV     DS, cs:[7DH]                    ; 2E 8E 1E 7D 00
                MOV     AX, ds:[GfxContext.wGfxBlitDstPage]                    ; A1 18 00
                MOV     ES, AX                          ; 8E C0
                MOV     AX, [BP-6H]                     ; 8B 46 FA
                SUB     AX, [BP-8H]                     ; 2B 46 F8
                SHR     AX, 1                           ; D1 E8
                SHR     AX, 1                           ; D1 E8
                MOV     cs:[2361H], AX                  ; 2E A3 61 23
                MOV     AL, [BP+0CH]                    ; 8A 46 0C
                MOV     cs:[2367H], AL                  ; 2E A2 67 23
                MOV     BX, [BP+0AH]                    ; 8B 5E 0A
                SHL     BX, 1                           ; D1 E3
                JNS     bsm_1517                        ; 79 12
                SAR     BX, 1                           ; D1 FB
                SHL     BX, 1                           ; D1 E3
                SHL     BX, 1                           ; D1 E3
                SHL     BX, 1                           ; D1 E3
                MOV     DI, BX                          ; 8B FB
                SHL     BX, 1                           ; D1 E3
                SHL     BX, 1                           ; D1 E3
                ADD     DI, BX                          ; 03 FB
                JMP     bsm_151b                        ; EB 04
bsm_1517:
                MOV     DI, [BX+(GfxContext.pRow_offset_lut)]                   ; 8B BF F2 06
bsm_151b:
                MOV     AX, [BP+8H]                     ; 8B 46 08
                MOV     CL, AL                          ; 8A C8
                SAR     AX, 1                           ; D1 F8
                SAR     AX, 1                           ; D1 F8
                SAR     AX, 1                           ; D1 F8
                ADD     DI, AX                          ; 03 F8
                AND     CL, 7H                          ; 80 E1 07
                MOV     AX, [BP-4H]                     ; 8B 46 FC
                MOV     DX, AX                          ; 8B D0
                SHR     AX, 1                           ; D1 E8
                SHR     AX, 1                           ; D1 E8
                SHR     AX, 1                           ; D1 E8
                MOV     cs:[235FH], AX                  ; 2E A3 5F 23
                ADD     DX, 7H                          ; 83 C2 07
                SHR     DX, 1                           ; D1 EA
                SHR     DX, 1                           ; D1 EA
                SHR     DX, 1                           ; D1 EA
                MOV     DH, DL                          ; 8A F2
                MOV     AL, [BP-2H]                     ; 8A 46 FE
                MOV     cs:[236AH], AL                  ; 2E A2 6A 23
                MOV     AX, [BP-0AH]                    ; 8B 46 F6
                MOV     cs:[2363H], AX                  ; 2E A3 63 23
                MOV     SI, [BP-8H]                     ; 8B 76 F8
                MOV     AX, [BP-6H]                     ; 8B 46 FA
                MOV     cs:[2365H], AX                  ; 2E A3 65 23
                XOR     AX, AX                          ; 33 C0
                MOV     cs:[2368H], AL                  ; 2E A2 68 23
                MOV     cs:[2369H], AL                  ; 2E A2 69 23
                TEST    BYTE PTR cs:[2367H], 1H         ; 2E F6 06 67 23 01
                JZ      bsm_1586                        ; 74 17
                PUSH    DX                              ; 52
                MOV     AL, cs:[236AH]                  ; 2E A0 6A 23
                XOR     AH, AH                          ; 32 E4
                DEC     AX                              ; 48
                XOR     DX, DX                          ; 33 D2
                MUL     WORD PTR cs:[235FH]             ; 2E F7 26 5F 23
                ADD     SI, AX                          ; 03 F0
                ADD     cs:[2365H], AX                  ; 2E 01 06 65 23
                POP     DX                              ; 5A
bsm_1586:
                TEST    BYTE PTR cs:[2367H], 2H         ; 2E F6 06 67 23 02
                JZ      bsm_159a                        ; 74 0C
                MOV     AX, cs:[235FH]                  ; 2E A1 5F 23
                DEC     AX                              ; 48
                ADD     SI, AX                          ; 03 F0
                ADD     cs:[2365H], AX                  ; 2E 01 06 65 23
bsm_159a:
                MOV     AL, ds:[GfxContext.bClip_enabled]                     ; A0 03 00
                OR      AL, AL                          ; 0A C0
                JNZ     bsm_15a4                        ; 75 03
                JMP     bsm_165b                        ; E9 B7 00
bsm_15a4:
                MOV     AX, ds:[GfxContext.nClip_xmax]                     ; A1 06 00
                INC     AX                              ; 40
                MOV     BX, [BP+8H]                     ; 8B 5E 08
                ADD     BX, [BP-4H]                     ; 03 5E FC
                SUB     AX, BX                          ; 2B C3
                JG      bsm_15ca                        ; 7F 18
                NEG     AX                              ; F7 D8
                CMP     AX, [BP-4H]                     ; 3B 46 FC
                JL      bsm_15bc                        ; 7C 03
                JMP     ega_sprite_epilogue                        ; E9 80 0D
bsm_15bc:
                SHR     AX, 1                           ; D1 E8
                SHR     AX, 1                           ; D1 E8
                SHR     AX, 1                           ; D1 E8
                SUB     DH, AL                          ; 2A F0
                MOV     BYTE PTR cs:[2368H], 1H         ; 2E C6 06 68 23 01
bsm_15ca:
                MOV     AX, [BP+8H]                     ; 8B 46 08
                SUB     AX, ds:[GfxContext.nClip_xmin]                     ; 2B 06 04 00
                JNS     bsm_1603                        ; 79 30
                MOV     BX, AX                          ; 8B D8
                ADD     AX, [BP-4H]                     ; 03 46 FC
                JG      bsm_15dd                        ; 7F 03
                JMP     ega_sprite_epilogue                        ; E9 5F 0D
bsm_15dd:
                MOV     BYTE PTR cs:[2369H], 1H         ; 2E C6 06 69 23 01
                NEG     BX                              ; F7 DB
                ADD     BX, 7H                          ; 83 C3 07
                SHR     BX, 1                           ; D1 EB
                SHR     BX, 1                           ; D1 EB
                SHR     BX, 1                           ; D1 EB
                SUB     DH, BL                          ; 2A F3
                ADD     DI, BX                          ; 03 FB
                TEST    BYTE PTR cs:[2367H], 2H         ; 2E F6 06 67 23 02
                JZ      bsm_15fc                        ; 74 02
                NEG     BX                              ; F7 DB
bsm_15fc:
                ADD     SI, BX                          ; 03 F3
                ADD     cs:[2365H], BX                  ; 2E 01 1E 65 23
bsm_1603:
                MOV     AX, [BP+0AH]                    ; 8B 46 0A
                ADD     AX, [BP-2H]                     ; 03 46 FE
                SUB     AX, ds:[GfxContext.nClip_ymax]                    ; 2B 06 0A 00
                JNG     bsm_161e                        ; 7E 0F
                CMP     AX, [BP-2H]                     ; 3B 46 FE
                JS      bsm_1617                        ; 78 03
                JMP     ega_sprite_epilogue                        ; E9 25 0D
bsm_1617:
                DEC     AL                              ; FE C8
                SUB     cs:[236AH], AL                  ; 2E 28 06 6A 23
bsm_161e:
                MOV     AX, ds:[GfxContext.nClip_ymin]                     ; A1 08 00
                SUB     AX, [BP+0AH]                    ; 2B 46 0A
                JS      bsm_165b                        ; 78 35
                CMP     AX, [BP-2H]                     ; 3B 46 FE
                JS      bsm_162e                        ; 78 03
                JMP     ega_sprite_epilogue                        ; E9 0E 0D
bsm_162e:
                SUB     cs:[236AH], AL                  ; 2E 28 06 6A 23
                MOV     BX, AX                          ; 8B D8
                SHL     AX, 1                           ; D1 E0
                SHL     AX, 1                           ; D1 E0
                SHL     AX, 1                           ; D1 E0
                ADD     DI, AX                          ; 03 F8
                SHL     AX, 1                           ; D1 E0
                SHL     AX, 1                           ; D1 E0
                ADD     DI, AX                          ; 03 F8
                MOV     AX, BX                          ; 8B C3
                MUL     BYTE PTR cs:[235FH]             ; 2E F6 26 5F 23
                TEST    BYTE PTR cs:[2367H], 1H         ; 2E F6 06 67 23 01
                JZ      bsm_1654                        ; 74 02
                NEG     AX                              ; F7 D8
bsm_1654:
                ADD     SI, AX                          ; 03 F0
                ADD     cs:[2365H], AX                  ; 2E 01 06 65 23
bsm_165b:
                MOV     BL, cs:[2367H]                  ; 2E 8A 1E 67 23
                XOR     BH, BH                          ; 32 FF
                SHL     BX, 1                           ; D1 E3
                MOV     AX, cs:[BX+2357H]               ; 2E 8B 87 57 23
                MOV     DS, cs:[2363H]                  ; 2E 8E 1E 63 23
                MOV     BP, cs:[2365H]                  ; 2E 8B 2E 65 23
                ; Tail-call into one of the 4 flip cores: AX holds the
                ; near-pointer that we just loaded from
                ; g_apfnEgaSpriteFlipDispatch[flags]. JMP AX is the indirect
                ; near-jump form (FF /4 with mod=11, r/m=AX => FF E0).
                JMP     AX                              ; FF E0
ega_blit_sprite_master ENDP

; ============================================================================
; ega_blit_sprite_noflip_core @ 0x1675..0x18EE (633 bytes)
;
; FAR core invoked via dispatch table CS:[2357] from ega_blit_sprite_master
; (slot 0; flags=0, no flip). This is the master template the other three
; cores are cloned from -- read it once and you have read all four.
;
; Structure:
;   Pass 0 (the "transparency" pass)
;     -- programs GC reg 8 Bit Mask, walks the chunky source, builds the
;        AND-mask byte that says "which pixels are background". One row
;        per outer iteration; one source-byte per inner iteration. The
;        first source byte each row is the only one that may need the
;        "spillover" branch when (x mod 8) != 0.
;   Passes 1..4 (one per plane)
;     -- programs Read-Plane=N and Map-Mask=(1<<N); walks the same source
;        pixels and STOSB's plane-N byte into the framebuffer using GC
;        Data Rotate = OR (set to 0x10 at the head of pass 1) so the
;        sprite OR-merges over whatever is there.
;
; The cs:[2369h] (left-edge clip) and cs:[2368h] (right-edge clip) bytes
; gate the "skip first source byte" and "skip last source byte" paths so
; that x-clipped sprites still iterate exactly once per output column.
; SI walks the chunky source; cs:[235Fh] is the source-row stride; DI
; walks the framebuffer; +0x28 (=40) is the screen-row stride.
;
; Returns by tail-jumping to ega_sprite_epilogue (0x233C) which restores
; GC Mode=wm2, GC Data Rotate=0, and Map Mask=0x0F.
; ============================================================================
ega_blit_sprite_noflip_core PROC FAR
                ; ----- Pass 0: build the transparency mask via GC Bit Mask (reg 8).
                ; Walks the chunky source one byte per inner step; for each
                ; pixel that should be opaque, the matching bit in the GC
                ; Bit Mask is set to 1 so the subsequent plane writes go
                ; through. Background pixels keep the framebuffer latches.
                PUSH    SI                              ; 56
                PUSH    DI                              ; 57
                PUSH    DX                              ; 52
                PUSH    DI                              ; 57
                MOV     BH, DH                          ; 8A FE
                MOV     BL, cs:[236AH]                  ; 2E 8A 1E 6A 23   row count
                MOV     DX, 3CEH                        ; BA CE 03
                MOV     AL, 8H                          ; B0 08            GC idx 8 = Bit Mask
                OUT     DX, AL                          ; EE
                INC     DX                              ; 42               DX = 0x3CF (data)
                MOV     SI, BP                          ; 8B F5
                PUSH    SI                              ; 56
nc_168a:
                MOV     CH, BH                          ; 8A EF
                XOR     AH, AH                          ; 32 E4
                TEST    BYTE PTR cs:[2369H], 1H         ; 2E F6 06 69 23 01
                JZ      nc_169f                        ; 74 09
                MOV     AH, [SI-1H]                     ; 8A 64 FF
                NOT     AH                              ; F6 D4
                OR      CH, CH                          ; 0A ED
                JZ      nc_16c3                        ; 74 24
nc_169f:
                LODSB                                   ; AC
                NOT     AL                              ; F6 D0
                ROR     AX, CL                          ; D3 C8
                OUT     DX, AL                          ; EE
                MOV     AL, es:[DI]                     ; 26 8A 05
                XOR     AL, AL                          ; 32 C0
                STOSB                                   ; AA
                MOV     AL, 8H                          ; B0 08
                SUB     CL, AL                          ; 2A C8
                NEG     CL                              ; F6 D9
                SHR     AH, CL                          ; D2 EC
                SUB     CL, AL                          ; 2A C8
                NEG     CL                              ; F6 D9
                DEC     CH                              ; FE CD
                JNZ     nc_169f                        ; 75 E4
                TEST    BYTE PTR cs:[2368H], 1H         ; 2E F6 06 68 23 01
                JNZ     nc_16ce                        ; 75 0B
nc_16c3:
                XOR     AL, AL                          ; 32 C0
                ROR     AX, CL                          ; D3 C8
                OUT     DX, AL                          ; EE
                MOV     AL, es:[DI]                     ; 26 8A 05
                XOR     AL, AL                          ; 32 C0
                STOSB                                   ; AA
nc_16ce:
                POP     SI                              ; 5E
                POP     DI                              ; 5F
                ADD     SI, cs:[235FH]                  ; 2E 03 36 5F 23
                ADD     DI, 28H                         ; 83 C7 28
                PUSH    DI                              ; 57
                PUSH    SI                              ; 56
                DEC     BL                              ; FE CB
                JNZ     nc_168a                        ; 75 AC
                XOR     AL, AL                          ; 32 C0
                MOV     AL, 0FFH                        ; B0 FF
                OUT     DX, AL                          ; EE
                ADD     SP, 2H                          ; 83 C4 02
                POP     DI                              ; 5F
                POP     DX                              ; 5A
                POP     DI                              ; 5F
                POP     SI                              ; 5E
                ; ----- Switch to write-mode 0 + GC Data Rotate=OR (0x10).
                ; All subsequent plane writes will OR the CPU byte into the
                ; framebuffer (transparent sprites over existing content).
                PUSH    DX                              ; 52
                MOV     DX, 3CEH                        ; BA CE 03
                MOV     AX, 5H                          ; B8 05 00         GC reg 5 (Mode) = 0
                OUT     DX, AX                          ; EF
                MOV     AX, 1003H                       ; B8 03 10         GC reg 3 (Data Rotate)=OR
                OUT     DX, AX                          ; EF
                POP     DX                              ; 5A
                ; ----- Pass 1: plane 0 (B). GC Read Plane Select=0 +
                ; Seq Map Mask=0x01. Walks the same chunky source again,
                ; writing the chunky byte's plane-0 contribution.
                PUSH    SI                              ; 56
                PUSH    DI                              ; 57
                PUSH    DX                              ; 52
                MOV     DX, 3CEH                        ; BA CE 03
                MOV     AX, 4H                          ; B8 04 00         GC idx 4 (Read Plane) = 0
                OUT     DX, AX                          ; EF
                MOV     DX, 3C4H                        ; BA C4 03
                MOV     AX, 102H                        ; B8 02 01         Seq Map Mask = 0x01
                OUT     DX, AX                          ; EF
                POP     DX                              ; 5A
                PUSH    DX                              ; 52
                PUSH    DI                              ; 57
                MOV     BL, cs:[236AH]                  ; 2E 8A 1E 6A 23
                XOR     BH, BH                          ; 32 FF
                MOV     BP, BX                          ; 8B EB
                MOV     BH, DH                          ; 8A FE
                MOV     DH, CL                          ; 8A F1
                SUB     CL, 8H                          ; 80 E9 08
                NEG     CL                              ; F6 D9
                MOV     BL, CL                          ; 8A D9
                PUSH    SI                              ; 56
nc_1720:
                MOV     CH, BH                          ; 8A EF
                XOR     AH, AH                          ; 32 E4
                TEST    BYTE PTR cs:[2369H], 1H         ; 2E F6 06 69 23 01
                JZ      nc_1733                        ; 74 07
                MOV     AH, [SI-1H]                     ; 8A 64 FF
                OR      CH, CH                          ; 0A ED
                JZ      nc_174c                        ; 74 19
nc_1733:
                MOV     CL, DH                          ; 8A CE
                LODSB                                   ; AC
                ROR     AX, CL                          ; D3 C8
                MOV     DL, es:[DI]                     ; 26 8A 15
                STOSB                                   ; AA
                MOV     CL, BL                          ; 8A CB
                SHR     AH, CL                          ; D2 EC
                DEC     CH                              ; FE CD
                JNZ     nc_1733                        ; 75 EF
                TEST    BYTE PTR cs:[2368H], 1H         ; 2E F6 06 68 23 01
                JNZ     nc_1758                        ; 75 0C
nc_174c:
                MOV     CL, DH                          ; 8A CE
                XOR     AL, AL                          ; 32 C0
                ROR     AX, CL                          ; D3 C8
                MOV     AH, es:[DI]                     ; 26 8A 25
                STOSB                                   ; AA
                MOV     CL, BL                          ; 8A CB
nc_1758:
                POP     SI                              ; 5E
                POP     DI                              ; 5F
                ADD     SI, cs:[235FH]                  ; 2E 03 36 5F 23
                ADD     DI, 28H                         ; 83 C7 28
                PUSH    DI                              ; 57
                PUSH    SI                              ; 56
                DEC     BP                              ; 4D
                JNZ     nc_1720                        ; 75 B9
                MOV     CL, DH                          ; 8A CE
                ADD     SP, 2H                          ; 83 C4 02
                POP     DI                              ; 5F
                POP     DX                              ; 5A
                POP     DI                              ; 5F
                POP     SI                              ; 5E
                ; ----- Pass 2: plane 1 (G). GC Read Plane Select=1,
                ; Seq Map Mask=0x02. Source advances by cs:[2361h] (one
                ; chunky byte per pixel for plane separation).
                ADD     SI, cs:[2361H]                  ; 2E 03 36 61 23
                PUSH    SI                              ; 56
                PUSH    DI                              ; 57
                PUSH    DX                              ; 52
                MOV     DX, 3CEH                        ; BA CE 03
                MOV     AX, 104H                        ; B8 04 01         GC Read Plane = 1
                OUT     DX, AX                          ; EF
                MOV     DX, 3C4H                        ; BA C4 03
                MOV     AX, 202H                        ; B8 02 02         Seq Map Mask = 0x02
                OUT     DX, AX                          ; EF
                POP     DX                              ; 5A
                PUSH    DX                              ; 52
                PUSH    DI                              ; 57
                MOV     BL, cs:[236AH]                  ; 2E 8A 1E 6A 23
                XOR     BH, BH                          ; 32 FF
                MOV     BP, BX                          ; 8B EB
                MOV     BH, DH                          ; 8A FE
                MOV     DH, CL                          ; 8A F1
                SUB     CL, 8H                          ; 80 E9 08
                NEG     CL                              ; F6 D9
                MOV     BL, CL                          ; 8A D9
                PUSH    SI                              ; 56
nc_179e:
                MOV     CH, BH                          ; 8A EF
                XOR     AH, AH                          ; 32 E4
                TEST    BYTE PTR cs:[2369H], 1H         ; 2E F6 06 69 23 01
                JZ      nc_17b1                        ; 74 07
                MOV     AH, [SI-1H]                     ; 8A 64 FF
                OR      CH, CH                          ; 0A ED
                JZ      nc_17ca                        ; 74 19
nc_17b1:
                MOV     CL, DH                          ; 8A CE
                LODSB                                   ; AC
                ROR     AX, CL                          ; D3 C8
                MOV     DL, es:[DI]                     ; 26 8A 15
                STOSB                                   ; AA
                MOV     CL, BL                          ; 8A CB
                SHR     AH, CL                          ; D2 EC
                DEC     CH                              ; FE CD
                JNZ     nc_17b1                        ; 75 EF
                TEST    BYTE PTR cs:[2368H], 1H         ; 2E F6 06 68 23 01
                JNZ     nc_17d6                        ; 75 0C
nc_17ca:
                MOV     CL, DH                          ; 8A CE
                XOR     AL, AL                          ; 32 C0
                ROR     AX, CL                          ; D3 C8
                MOV     AH, es:[DI]                     ; 26 8A 25
                STOSB                                   ; AA
                MOV     CL, BL                          ; 8A CB
nc_17d6:
                POP     SI                              ; 5E
                POP     DI                              ; 5F
                ADD     SI, cs:[235FH]                  ; 2E 03 36 5F 23
                ADD     DI, 28H                         ; 83 C7 28
                PUSH    DI                              ; 57
                PUSH    SI                              ; 56
                DEC     BP                              ; 4D
                JNZ     nc_179e                        ; 75 B9
                MOV     CL, DH                          ; 8A CE
                ADD     SP, 2H                          ; 83 C4 02
                POP     DI                              ; 5F
                POP     DX                              ; 5A
                POP     DI                              ; 5F
                POP     SI                              ; 5E
                ; ----- Pass 3: plane 2 (R). GC Read Plane Select=2,
                ; Seq Map Mask=0x04.
                ADD     SI, cs:[2361H]                  ; 2E 03 36 61 23
                PUSH    SI                              ; 56
                PUSH    DI                              ; 57
                PUSH    DX                              ; 52
                MOV     DX, 3CEH                        ; BA CE 03
                MOV     AX, 204H                        ; B8 04 02         GC Read Plane = 2
                OUT     DX, AX                          ; EF
                MOV     DX, 3C4H                        ; BA C4 03
                MOV     AX, 402H                        ; B8 02 04         Seq Map Mask = 0x04
                OUT     DX, AX                          ; EF
                POP     DX                              ; 5A
                PUSH    DX                              ; 52
                PUSH    DI                              ; 57
                MOV     BL, cs:[236AH]                  ; 2E 8A 1E 6A 23
                XOR     BH, BH                          ; 32 FF
                MOV     BP, BX                          ; 8B EB
                MOV     BH, DH                          ; 8A FE
                MOV     DH, CL                          ; 8A F1
                SUB     CL, 8H                          ; 80 E9 08
                NEG     CL                              ; F6 D9
                MOV     BL, CL                          ; 8A D9
                PUSH    SI                              ; 56
nc_181c:
                MOV     CH, BH                          ; 8A EF
                XOR     AH, AH                          ; 32 E4
                TEST    BYTE PTR cs:[2369H], 1H         ; 2E F6 06 69 23 01
                JZ      nc_182f                        ; 74 07
                MOV     AH, [SI-1H]                     ; 8A 64 FF
                OR      CH, CH                          ; 0A ED
                JZ      nc_1848                        ; 74 19
nc_182f:
                MOV     CL, DH                          ; 8A CE
                LODSB                                   ; AC
                ROR     AX, CL                          ; D3 C8
                MOV     DL, es:[DI]                     ; 26 8A 15
                STOSB                                   ; AA
                MOV     CL, BL                          ; 8A CB
                SHR     AH, CL                          ; D2 EC
                DEC     CH                              ; FE CD
                JNZ     nc_182f                        ; 75 EF
                TEST    BYTE PTR cs:[2368H], 1H         ; 2E F6 06 68 23 01
                JNZ     nc_1854                        ; 75 0C
nc_1848:
                MOV     CL, DH                          ; 8A CE
                XOR     AL, AL                          ; 32 C0
                ROR     AX, CL                          ; D3 C8
                MOV     AH, es:[DI]                     ; 26 8A 25
                STOSB                                   ; AA
                MOV     CL, BL                          ; 8A CB
nc_1854:
                POP     SI                              ; 5E
                POP     DI                              ; 5F
                ADD     SI, cs:[235FH]                  ; 2E 03 36 5F 23
                ADD     DI, 28H                         ; 83 C7 28
                PUSH    DI                              ; 57
                PUSH    SI                              ; 56
                DEC     BP                              ; 4D
                JNZ     nc_181c                        ; 75 B9
                MOV     CL, DH                          ; 8A CE
                ADD     SP, 2H                          ; 83 C4 02
                POP     DI                              ; 5F
                POP     DX                              ; 5A
                POP     DI                              ; 5F
                POP     SI                              ; 5E
                ; ----- Pass 4: plane 3 (I). GC Read Plane Select=3,
                ; Seq Map Mask=0x08.
                ADD     SI, cs:[2361H]                  ; 2E 03 36 61 23
                PUSH    SI                              ; 56
                PUSH    DI                              ; 57
                PUSH    DX                              ; 52
                MOV     DX, 3CEH                        ; BA CE 03
                MOV     AX, 304H                        ; B8 04 03         GC Read Plane = 3
                OUT     DX, AX                          ; EF
                MOV     DX, 3C4H                        ; BA C4 03
                MOV     AX, 802H                        ; B8 02 08         Seq Map Mask = 0x08
                OUT     DX, AX                          ; EF
                POP     DX                              ; 5A
                PUSH    DX                              ; 52
                PUSH    DI                              ; 57
                MOV     BL, cs:[236AH]                  ; 2E 8A 1E 6A 23
                XOR     BH, BH                          ; 32 FF
                MOV     BP, BX                          ; 8B EB
                MOV     BH, DH                          ; 8A FE
                MOV     DH, CL                          ; 8A F1
                SUB     CL, 8H                          ; 80 E9 08
                NEG     CL                              ; F6 D9
                MOV     BL, CL                          ; 8A D9
                PUSH    SI                              ; 56
nc_189a:
                MOV     CH, BH                          ; 8A EF
                XOR     AH, AH                          ; 32 E4
                TEST    BYTE PTR cs:[2369H], 1H         ; 2E F6 06 69 23 01
                JZ      nc_18ad                        ; 74 07
                MOV     AH, [SI-1H]                     ; 8A 64 FF
                OR      CH, CH                          ; 0A ED
                JZ      nc_18c6                        ; 74 19
nc_18ad:
                MOV     CL, DH                          ; 8A CE
                LODSB                                   ; AC
                ROR     AX, CL                          ; D3 C8
                MOV     DL, es:[DI]                     ; 26 8A 15
                STOSB                                   ; AA
                MOV     CL, BL                          ; 8A CB
                SHR     AH, CL                          ; D2 EC
                DEC     CH                              ; FE CD
                JNZ     nc_18ad                        ; 75 EF
                TEST    BYTE PTR cs:[2368H], 1H         ; 2E F6 06 68 23 01
                JNZ     nc_18d2                        ; 75 0C
nc_18c6:
                MOV     CL, DH                          ; 8A CE
                XOR     AL, AL                          ; 32 C0
                ROR     AX, CL                          ; D3 C8
                MOV     AH, es:[DI]                     ; 26 8A 25
                STOSB                                   ; AA
                MOV     CL, BL                          ; 8A CB
nc_18d2:
                POP     SI                              ; 5E
                POP     DI                              ; 5F
                ADD     SI, cs:[235FH]                  ; 2E 03 36 5F 23
                ADD     DI, 28H                         ; 83 C7 28
                PUSH    DI                              ; 57
                PUSH    SI                              ; 56
                DEC     BP                              ; 4D
                JNZ     nc_189a                        ; 75 B9
                MOV     CL, DH                          ; 8A CE
                ADD     SP, 2H                          ; 83 C4 02
                POP     DI                              ; 5F
                POP     DX                              ; 5A
                ADD     SP, 4H                          ; 83 C4 04
                JMP     ega_sprite_epilogue                        ; E9 4E 0A
ega_blit_sprite_noflip_core ENDP

; ============================================================================
; ega_blit_sprite_flipy_core @ 0x18EE..0x1B67 (633 bytes)
;
; FAR core invoked via dispatch table CS:[2357] from ega_blit_sprite_master
; (slot 1; flags=1, vertical flip). Clone of
; ega_blit_sprite_noflip_core except the per-row source-pointer update is
;   `SUB SI, cs:[235Fh]`  (2E 2B 36 5F 23)
; instead of
;   `ADD SI, cs:[235Fh]`  (2E 03 36 5F 23).
; So the chunky source pointer walks rows from BOTTOM to TOP while the
; framebuffer pointer still goes top-down (DI += 40 each row), producing
; a vertically mirrored sprite. Caller (ega_blit_sprite_master) is
; responsible for biasing SI to the last source row before the call.
;
; Tail-jumps to ega_sprite_epilogue (0x233C). See the noflip plate for
; the per-plane / per-pass structure shared by all four cores.
; ============================================================================
ega_blit_sprite_flipy_core PROC FAR
                ; ----- Pass 0: build the transparency mask via GC Bit Mask (reg 8).
                ; Identical to noflip_core's mask pass; the only structural
                ; difference is the per-row source-pointer update at the bottom
                ; of this loop (SUB instead of ADD, see fy_1947 below).
                PUSH    SI                              ; 56
                PUSH    DI                              ; 57
                PUSH    DX                              ; 52
                PUSH    DI                              ; 57
                MOV     BH, DH                          ; 8A FE
                MOV     BL, cs:[236AH]                  ; 2E 8A 1E 6A 23   row count
                MOV     DX, 3CEH                        ; BA CE 03
                MOV     AL, 8H                          ; B0 08            GC idx 8 = Bit Mask
                OUT     DX, AL                          ; EE
                INC     DX                              ; 42               DX = 0x3CF (data)
                MOV     SI, BP                          ; 8B F5
                PUSH    SI                              ; 56
fy_1903:
                MOV     CH, BH                          ; 8A EF
                XOR     AH, AH                          ; 32 E4
                TEST    BYTE PTR cs:[2369H], 1H         ; 2E F6 06 69 23 01
                JZ      fy_1918                        ; 74 09
                MOV     AH, [SI-1H]                     ; 8A 64 FF
                NOT     AH                              ; F6 D4
                OR      CH, CH                          ; 0A ED
                JZ      fy_193c                        ; 74 24
fy_1918:
                LODSB                                   ; AC
                NOT     AL                              ; F6 D0
                ROR     AX, CL                          ; D3 C8
                OUT     DX, AL                          ; EE
                MOV     AL, es:[DI]                     ; 26 8A 05
                XOR     AL, AL                          ; 32 C0
                STOSB                                   ; AA
                MOV     AL, 8H                          ; B0 08
                SUB     CL, AL                          ; 2A C8
                NEG     CL                              ; F6 D9
                SHR     AH, CL                          ; D2 EC
                SUB     CL, AL                          ; 2A C8
                NEG     CL                              ; F6 D9
                DEC     CH                              ; FE CD
                JNZ     fy_1918                        ; 75 E4
                TEST    BYTE PTR cs:[2368H], 1H         ; 2E F6 06 68 23 01
                JNZ     fy_1947                        ; 75 0B
fy_193c:
                XOR     AL, AL                          ; 32 C0
                ROR     AX, CL                          ; D3 C8
                OUT     DX, AL                          ; EE
                MOV     AL, es:[DI]                     ; 26 8A 05
                XOR     AL, AL                          ; 32 C0
                STOSB                                   ; AA
fy_1947:
                POP     SI                              ; 5E
                POP     DI                              ; 5F
                SUB     SI, cs:[235FH]                  ; 2E 2B 36 5F 23
                ADD     DI, 28H                         ; 83 C7 28
                PUSH    DI                              ; 57
                PUSH    SI                              ; 56
                DEC     BL                              ; FE CB
                JNZ     fy_1903                        ; 75 AC
                XOR     AL, AL                          ; 32 C0
                MOV     AL, 0FFH                        ; B0 FF
                OUT     DX, AL                          ; EE
                ADD     SP, 2H                          ; 83 C4 02
                POP     DI                              ; 5F
                POP     DX                              ; 5A
                POP     DI                              ; 5F
                POP     SI                              ; 5E
                ; ----- Switch to write-mode 0 + GC Data Rotate=OR (0x10).
                PUSH    DX                              ; 52
                MOV     DX, 3CEH                        ; BA CE 03
                MOV     AX, 5H                          ; B8 05 00         GC reg 5 (Mode) = 0
                OUT     DX, AX                          ; EF
                MOV     AX, 1003H                       ; B8 03 10         GC reg 3 (Data Rotate)=OR
                OUT     DX, AX                          ; EF
                POP     DX                              ; 5A
                ; ----- Pass 1: plane 0 (B). GC Read Plane Select=0 +
                ; Seq Map Mask=0x01.
                PUSH    SI                              ; 56
                PUSH    DI                              ; 57
                PUSH    DX                              ; 52
                MOV     DX, 3CEH                        ; BA CE 03
                MOV     AX, 4H                          ; B8 04 00         GC idx 4 (Read Plane) = 0
                OUT     DX, AX                          ; EF
                MOV     DX, 3C4H                        ; BA C4 03
                MOV     AX, 102H                        ; B8 02 01         Seq Map Mask = 0x01
                OUT     DX, AX                          ; EF
                POP     DX                              ; 5A
                PUSH    DX                              ; 52
                PUSH    DI                              ; 57
                MOV     BL, cs:[236AH]                  ; 2E 8A 1E 6A 23
                XOR     BH, BH                          ; 32 FF
                MOV     BP, BX                          ; 8B EB
                MOV     BH, DH                          ; 8A FE
                MOV     DH, CL                          ; 8A F1
                SUB     CL, 8H                          ; 80 E9 08
                NEG     CL                              ; F6 D9
                MOV     BL, CL                          ; 8A D9
                PUSH    SI                              ; 56
fy_1999:
                MOV     CH, BH                          ; 8A EF
                XOR     AH, AH                          ; 32 E4
                TEST    BYTE PTR cs:[2369H], 1H         ; 2E F6 06 69 23 01
                JZ      fy_19ac                        ; 74 07
                MOV     AH, [SI-1H]                     ; 8A 64 FF
                OR      CH, CH                          ; 0A ED
                JZ      fy_19c5                        ; 74 19
fy_19ac:
                MOV     CL, DH                          ; 8A CE
                LODSB                                   ; AC
                ROR     AX, CL                          ; D3 C8
                MOV     DL, es:[DI]                     ; 26 8A 15
                STOSB                                   ; AA
                MOV     CL, BL                          ; 8A CB
                SHR     AH, CL                          ; D2 EC
                DEC     CH                              ; FE CD
                JNZ     fy_19ac                        ; 75 EF
                TEST    BYTE PTR cs:[2368H], 1H         ; 2E F6 06 68 23 01
                JNZ     fy_19d1                        ; 75 0C
fy_19c5:
                MOV     CL, DH                          ; 8A CE
                XOR     AL, AL                          ; 32 C0
                ROR     AX, CL                          ; D3 C8
                MOV     AH, es:[DI]                     ; 26 8A 25
                STOSB                                   ; AA
                MOV     CL, BL                          ; 8A CB
fy_19d1:
                POP     SI                              ; 5E
                POP     DI                              ; 5F
                SUB     SI, cs:[235FH]                  ; 2E 2B 36 5F 23
                ADD     DI, 28H                         ; 83 C7 28
                PUSH    DI                              ; 57
                PUSH    SI                              ; 56
                DEC     BP                              ; 4D
                JNZ     fy_1999                        ; 75 B9
                MOV     CL, DH                          ; 8A CE
                ADD     SP, 2H                          ; 83 C4 02
                POP     DI                              ; 5F
                POP     DX                              ; 5A
                POP     DI                              ; 5F
                POP     SI                              ; 5E
                ; ----- Pass 2: plane 1 (G). GC Read Plane Select=1,
                ; Seq Map Mask=0x02.
                ADD     SI, cs:[2361H]                  ; 2E 03 36 61 23
                PUSH    SI                              ; 56
                PUSH    DI                              ; 57
                PUSH    DX                              ; 52
                MOV     DX, 3CEH                        ; BA CE 03
                MOV     AX, 104H                        ; B8 04 01         GC Read Plane = 1
                OUT     DX, AX                          ; EF
                MOV     DX, 3C4H                        ; BA C4 03
                MOV     AX, 202H                        ; B8 02 02         Seq Map Mask = 0x02
                OUT     DX, AX                          ; EF
                POP     DX                              ; 5A
                PUSH    DX                              ; 52
                PUSH    DI                              ; 57
                MOV     BL, cs:[236AH]                  ; 2E 8A 1E 6A 23
                XOR     BH, BH                          ; 32 FF
                MOV     BP, BX                          ; 8B EB
                MOV     BH, DH                          ; 8A FE
                MOV     DH, CL                          ; 8A F1
                SUB     CL, 8H                          ; 80 E9 08
                NEG     CL                              ; F6 D9
                MOV     BL, CL                          ; 8A D9
                PUSH    SI                              ; 56
fy_1a17:
                MOV     CH, BH                          ; 8A EF
                XOR     AH, AH                          ; 32 E4
                TEST    BYTE PTR cs:[2369H], 1H         ; 2E F6 06 69 23 01
                JZ      fy_1a2a                        ; 74 07
                MOV     AH, [SI-1H]                     ; 8A 64 FF
                OR      CH, CH                          ; 0A ED
                JZ      fy_1a43                        ; 74 19
fy_1a2a:
                MOV     CL, DH                          ; 8A CE
                LODSB                                   ; AC
                ROR     AX, CL                          ; D3 C8
                MOV     DL, es:[DI]                     ; 26 8A 15
                STOSB                                   ; AA
                MOV     CL, BL                          ; 8A CB
                SHR     AH, CL                          ; D2 EC
                DEC     CH                              ; FE CD
                JNZ     fy_1a2a                        ; 75 EF
                TEST    BYTE PTR cs:[2368H], 1H         ; 2E F6 06 68 23 01
                JNZ     fy_1a4f                        ; 75 0C
fy_1a43:
                MOV     CL, DH                          ; 8A CE
                XOR     AL, AL                          ; 32 C0
                ROR     AX, CL                          ; D3 C8
                MOV     AH, es:[DI]                     ; 26 8A 25
                STOSB                                   ; AA
                MOV     CL, BL                          ; 8A CB
fy_1a4f:
                POP     SI                              ; 5E
                POP     DI                              ; 5F
                SUB     SI, cs:[235FH]                  ; 2E 2B 36 5F 23
                ADD     DI, 28H                         ; 83 C7 28
                PUSH    DI                              ; 57
                PUSH    SI                              ; 56
                DEC     BP                              ; 4D
                JNZ     fy_1a17                        ; 75 B9
                MOV     CL, DH                          ; 8A CE
                ADD     SP, 2H                          ; 83 C4 02
                POP     DI                              ; 5F
                POP     DX                              ; 5A
                POP     DI                              ; 5F
                POP     SI                              ; 5E
                ; ----- Pass 3: plane 2 (R). GC Read Plane Select=2,
                ; Seq Map Mask=0x04.
                ADD     SI, cs:[2361H]                  ; 2E 03 36 61 23
                PUSH    SI                              ; 56
                PUSH    DI                              ; 57
                PUSH    DX                              ; 52
                MOV     DX, 3CEH                        ; BA CE 03
                MOV     AX, 204H                        ; B8 04 02         GC Read Plane = 2
                OUT     DX, AX                          ; EF
                MOV     DX, 3C4H                        ; BA C4 03
                MOV     AX, 402H                        ; B8 02 04         Seq Map Mask = 0x04
                OUT     DX, AX                          ; EF
                POP     DX                              ; 5A
                PUSH    DX                              ; 52
                PUSH    DI                              ; 57
                MOV     BL, cs:[236AH]                  ; 2E 8A 1E 6A 23
                XOR     BH, BH                          ; 32 FF
                MOV     BP, BX                          ; 8B EB
                MOV     BH, DH                          ; 8A FE
                MOV     DH, CL                          ; 8A F1
                SUB     CL, 8H                          ; 80 E9 08
                NEG     CL                              ; F6 D9
                MOV     BL, CL                          ; 8A D9
                PUSH    SI                              ; 56
fy_1a95:
                MOV     CH, BH                          ; 8A EF
                XOR     AH, AH                          ; 32 E4
                TEST    BYTE PTR cs:[2369H], 1H         ; 2E F6 06 69 23 01
                JZ      fy_1aa8                        ; 74 07
                MOV     AH, [SI-1H]                     ; 8A 64 FF
                OR      CH, CH                          ; 0A ED
                JZ      fy_1ac1                        ; 74 19
fy_1aa8:
                MOV     CL, DH                          ; 8A CE
                LODSB                                   ; AC
                ROR     AX, CL                          ; D3 C8
                MOV     DL, es:[DI]                     ; 26 8A 15
                STOSB                                   ; AA
                MOV     CL, BL                          ; 8A CB
                SHR     AH, CL                          ; D2 EC
                DEC     CH                              ; FE CD
                JNZ     fy_1aa8                        ; 75 EF
                TEST    BYTE PTR cs:[2368H], 1H         ; 2E F6 06 68 23 01
                JNZ     fy_1acd                        ; 75 0C
fy_1ac1:
                MOV     CL, DH                          ; 8A CE
                XOR     AL, AL                          ; 32 C0
                ROR     AX, CL                          ; D3 C8
                MOV     AH, es:[DI]                     ; 26 8A 25
                STOSB                                   ; AA
                MOV     CL, BL                          ; 8A CB
fy_1acd:
                POP     SI                              ; 5E
                POP     DI                              ; 5F
                SUB     SI, cs:[235FH]                  ; 2E 2B 36 5F 23
                ADD     DI, 28H                         ; 83 C7 28
                PUSH    DI                              ; 57
                PUSH    SI                              ; 56
                DEC     BP                              ; 4D
                JNZ     fy_1a95                        ; 75 B9
                MOV     CL, DH                          ; 8A CE
                ADD     SP, 2H                          ; 83 C4 02
                POP     DI                              ; 5F
                POP     DX                              ; 5A
                POP     DI                              ; 5F
                POP     SI                              ; 5E
                ; ----- Pass 4: plane 3 (I). GC Read Plane Select=3,
                ; Seq Map Mask=0x08.
                ADD     SI, cs:[2361H]                  ; 2E 03 36 61 23
                PUSH    SI                              ; 56
                PUSH    DI                              ; 57
                PUSH    DX                              ; 52
                MOV     DX, 3CEH                        ; BA CE 03
                MOV     AX, 304H                        ; B8 04 03         GC Read Plane = 3
                OUT     DX, AX                          ; EF
                MOV     DX, 3C4H                        ; BA C4 03
                MOV     AX, 802H                        ; B8 02 08         Seq Map Mask = 0x08
                OUT     DX, AX                          ; EF
                POP     DX                              ; 5A
                PUSH    DX                              ; 52
                PUSH    DI                              ; 57
                MOV     BL, cs:[236AH]                  ; 2E 8A 1E 6A 23
                XOR     BH, BH                          ; 32 FF
                MOV     BP, BX                          ; 8B EB
                MOV     BH, DH                          ; 8A FE
                MOV     DH, CL                          ; 8A F1
                SUB     CL, 8H                          ; 80 E9 08
                NEG     CL                              ; F6 D9
                MOV     BL, CL                          ; 8A D9
                PUSH    SI                              ; 56
fy_1b13:
                MOV     CH, BH                          ; 8A EF
                XOR     AH, AH                          ; 32 E4
                TEST    BYTE PTR cs:[2369H], 1H         ; 2E F6 06 69 23 01
                JZ      fy_1b26                        ; 74 07
                MOV     AH, [SI-1H]                     ; 8A 64 FF
                OR      CH, CH                          ; 0A ED
                JZ      fy_1b3f                        ; 74 19
fy_1b26:
                MOV     CL, DH                          ; 8A CE
                LODSB                                   ; AC
                ROR     AX, CL                          ; D3 C8
                MOV     DL, es:[DI]                     ; 26 8A 15
                STOSB                                   ; AA
                MOV     CL, BL                          ; 8A CB
                SHR     AH, CL                          ; D2 EC
                DEC     CH                              ; FE CD
                JNZ     fy_1b26                        ; 75 EF
                TEST    BYTE PTR cs:[2368H], 1H         ; 2E F6 06 68 23 01
                JNZ     fy_1b4b                        ; 75 0C
fy_1b3f:
                MOV     CL, DH                          ; 8A CE
                XOR     AL, AL                          ; 32 C0
                ROR     AX, CL                          ; D3 C8
                MOV     AH, es:[DI]                     ; 26 8A 25
                STOSB                                   ; AA
                MOV     CL, BL                          ; 8A CB
fy_1b4b:
                POP     SI                              ; 5E
                POP     DI                              ; 5F
                SUB     SI, cs:[235FH]                  ; 2E 2B 36 5F 23
                ADD     DI, 28H                         ; 83 C7 28
                PUSH    DI                              ; 57
                PUSH    SI                              ; 56
                DEC     BP                              ; 4D
                JNZ     fy_1b13                        ; 75 B9
                MOV     CL, DH                          ; 8A CE
                ADD     SP, 2H                          ; 83 C4 02
                POP     DI                              ; 5F
                POP     DX                              ; 5A
                ADD     SP, 4H                          ; 83 C4 04
                JMP     ega_sprite_epilogue                        ; E9 D5 07
ega_blit_sprite_flipy_core ENDP

; ============================================================================
; ega_blit_sprite_flipx_core @ 0x1B67..0x1F53 (1004 bytes)
;
; FAR core for flags=2 (horizontal flip). Unlike flipy_core, which only
; substitutes one instruction, this core is structurally different from
; noflip_core because the per-byte pixel order has to be REVERSED. For
; each source byte, instead of writing the byte directly we run an 8-step
;   SHR AL,1 ; RCL <plane>,1
; unrolled "bit reverser" that produces the mirror image, then OUT/STOSB
; that. The caller pre-biases SI to the LAST source byte and decrements
; (DEC SI) once per inner iteration, so the chunky source is consumed
; right-to-left.
;
; The dispatch byte at cs:[236Bh] is a private row-counter for this
; core (and flipxy_core); the noflip / flipy cores reuse BL directly,
; but the flip cores need BL free for the bit-reverse RCL target during
; the inner loop.
;
; Tail-jumps to ega_sprite_epilogue (0x233C). See the noflip plate for
; the per-plane / per-pass structure shared by all four cores.
; ============================================================================
ega_blit_sprite_flipx_core PROC FAR
                ; ----- Pass 0: build the transparency mask via GC Bit Mask (reg 8).
                ; Unlike noflip/flipy, the inner loop bit-reverses each source
                ; byte (8x SHR AL,1 / RCL <plane>,1) so the output byte holds
                ; the chunky pixels in mirrored order. Row counter is copied
                ; into the private CS slot 0x236B so BL is free to act as the
                ; RCL target during the inner reversal.
                PUSH    SI                              ; 56
                PUSH    DI                              ; 57
                PUSH    DX                              ; 52
                PUSH    DI                              ; 57
                MOV     BH, DH                          ; 8A FE
                MOV     AL, cs:[236AH]                  ; 2E A0 6A 23      row count
                MOV     cs:[236BH], AL                  ; 2E A2 6B 23      stash for the inner DEC
                MOV     DX, 3CEH                        ; BA CE 03
                MOV     AL, 8H                          ; B0 08            GC idx 8 = Bit Mask
                OUT     DX, AL                          ; EE
                INC     DX                              ; 42               DX = 0x3CF (data)
                MOV     SI, BP                          ; 8B F5
                PUSH    SI                              ; 56
fx_1b7f:
                MOV     CH, BH                          ; 8A EF
                XOR     AH, AH                          ; 32 E4
                TEST    BYTE PTR cs:[2369H], 1H         ; 2E F6 06 69 23 01
                JZ      fx_1bb6                        ; 74 2B
                MOV     AL, [SI+1H]                     ; 8A 44 01
                NOT     AL                              ; F6 D0
                SHR     AL, 1                           ; D0 E8
                RCL     AH, 1                           ; D0 D4
                SHR     AL, 1                           ; D0 E8
                RCL     AH, 1                           ; D0 D4
                SHR     AL, 1                           ; D0 E8
                RCL     AH, 1                           ; D0 D4
                SHR     AL, 1                           ; D0 E8
                RCL     AH, 1                           ; D0 D4
                SHR     AL, 1                           ; D0 E8
                RCL     AH, 1                           ; D0 D4
                SHR     AL, 1                           ; D0 E8
                RCL     AH, 1                           ; D0 D4
                SHR     AL, 1                           ; D0 E8
                RCL     AH, 1                           ; D0 D4
                SHR     AL, 1                           ; D0 E8
                RCL     AH, 1                           ; D0 D4
                MOV     AL, AH                          ; 8A C4
                OR      CH, CH                          ; 0A ED
                JZ      fx_1bfe                        ; 74 48
fx_1bb6:
                MOV     AL, [SI]                        ; 8A 04
                DEC     SI                              ; 4E
                NOT     AL                              ; F6 D0
                SHR     AL, 1                           ; D0 E8
                RCL     BL, 1                           ; D0 D3
                SHR     AL, 1                           ; D0 E8
                RCL     BL, 1                           ; D0 D3
                SHR     AL, 1                           ; D0 E8
                RCL     BL, 1                           ; D0 D3
                SHR     AL, 1                           ; D0 E8
                RCL     BL, 1                           ; D0 D3
                SHR     AL, 1                           ; D0 E8
                RCL     BL, 1                           ; D0 D3
                SHR     AL, 1                           ; D0 E8
                RCL     BL, 1                           ; D0 D3
                SHR     AL, 1                           ; D0 E8
                RCL     BL, 1                           ; D0 D3
                SHR     AL, 1                           ; D0 E8
                RCL     BL, 1                           ; D0 D3
                MOV     AL, BL                          ; 8A C3
                ROR     AX, CL                          ; D3 C8
                OUT     DX, AL                          ; EE
                MOV     AL, es:[DI]                     ; 26 8A 05
                XOR     AL, AL                          ; 32 C0
                STOSB                                   ; AA
                MOV     AL, 8H                          ; B0 08
                SUB     CL, AL                          ; 2A C8
                NEG     CL                              ; F6 D9
                SHR     AH, CL                          ; D2 EC
                SUB     CL, AL                          ; 2A C8
                NEG     CL                              ; F6 D9
                DEC     CH                              ; FE CD
                JNZ     fx_1bb6                        ; 75 C0
                TEST    BYTE PTR cs:[2368H], 1H         ; 2E F6 06 68 23 01
                JNZ     fx_1c09                        ; 75 0B
fx_1bfe:
                XOR     AL, AL                          ; 32 C0
                ROR     AX, CL                          ; D3 C8
                OUT     DX, AL                          ; EE
                MOV     AL, es:[DI]                     ; 26 8A 05
                XOR     AL, AL                          ; 32 C0
                STOSB                                   ; AA
fx_1c09:
                POP     SI                              ; 5E
                POP     DI                              ; 5F
                ADD     SI, cs:[235FH]                  ; 2E 03 36 5F 23
                ADD     DI, 28H                         ; 83 C7 28
                PUSH    DI                              ; 57
                PUSH    SI                              ; 56
                DEC     BYTE PTR cs:[236BH]             ; 2E FE 0E 6B 23
                JZ      fx_1c1f                        ; 74 03
                JMP     fx_1b7f                        ; E9 60 FF
fx_1c1f:
                XOR     AL, AL                          ; 32 C0
                MOV     AL, 0FFH                        ; B0 FF
                OUT     DX, AL                          ; EE
                ADD     SP, 2H                          ; 83 C4 02
                POP     DI                              ; 5F
                POP     DX                              ; 5A
                POP     DI                              ; 5F
                POP     SI                              ; 5E
                ; ----- Switch to write-mode 0 + GC Data Rotate=OR (0x10).
                PUSH    DX                              ; 52
                MOV     DX, 3CEH                        ; BA CE 03
                MOV     AX, 5H                          ; B8 05 00         GC reg 5 (Mode) = 0
                OUT     DX, AX                          ; EF
                MOV     AX, 1003H                       ; B8 03 10         GC reg 3 (Data Rotate)=OR
                OUT     DX, AX                          ; EF
                POP     DX                              ; 5A
                ; ----- Pass 1: plane 0 (B). GC Read Plane Select=0 +
                ; Seq Map Mask=0x01.
                PUSH    SI                              ; 56
                PUSH    DI                              ; 57
                PUSH    DX                              ; 52
                MOV     DX, 3CEH                        ; BA CE 03
                MOV     AX, 4H                          ; B8 04 00         GC idx 4 (Read Plane) = 0
                OUT     DX, AX                          ; EF
                MOV     DX, 3C4H                        ; BA C4 03
                MOV     AX, 102H                        ; B8 02 01         Seq Map Mask = 0x01
                OUT     DX, AX                          ; EF
                POP     DX                              ; 5A
                PUSH    DX                              ; 52
                PUSH    DI                              ; 57
                MOV     BL, cs:[236AH]                  ; 2E 8A 1E 6A 23
                XOR     BH, BH                          ; 32 FF
                MOV     BP, BX                          ; 8B EB
                MOV     BH, DH                          ; 8A FE
                MOV     DH, CL                          ; 8A F1
                SUB     CL, 8H                          ; 80 E9 08
                NEG     CL                              ; F6 D9
                MOV     BL, CL                          ; 8A D9
                PUSH    SI                              ; 56
fx_1c61:
                MOV     CH, BH                          ; 8A EF
                XOR     AH, AH                          ; 32 E4
                TEST    BYTE PTR cs:[2369H], 1H         ; 2E F6 06 69 23 01
                JZ      fx_1c96                        ; 74 29
                MOV     AL, [SI+1H]                     ; 8A 44 01
                SHR     AL, 1                           ; D0 E8
                RCL     AH, 1                           ; D0 D4
                SHR     AL, 1                           ; D0 E8
                RCL     AH, 1                           ; D0 D4
                SHR     AL, 1                           ; D0 E8
                RCL     AH, 1                           ; D0 D4
                SHR     AL, 1                           ; D0 E8
                RCL     AH, 1                           ; D0 D4
                SHR     AL, 1                           ; D0 E8
                RCL     AH, 1                           ; D0 D4
                SHR     AL, 1                           ; D0 E8
                RCL     AH, 1                           ; D0 D4
                SHR     AL, 1                           ; D0 E8
                RCL     AH, 1                           ; D0 D4
                SHR     AL, 1                           ; D0 E8
                RCL     AH, 1                           ; D0 D4
                MOV     AL, AH                          ; 8A C4
                OR      CH, CH                          ; 0A ED
                JZ      fx_1cd3                        ; 74 3D
fx_1c96:
                MOV     CL, DH                          ; 8A CE
                MOV     AL, [SI]                        ; 8A 04
                DEC     SI                              ; 4E
                SHR     AL, 1                           ; D0 E8
                RCL     DL, 1                           ; D0 D2
                SHR     AL, 1                           ; D0 E8
                RCL     DL, 1                           ; D0 D2
                SHR     AL, 1                           ; D0 E8
                RCL     DL, 1                           ; D0 D2
                SHR     AL, 1                           ; D0 E8
                RCL     DL, 1                           ; D0 D2
                SHR     AL, 1                           ; D0 E8
                RCL     DL, 1                           ; D0 D2
                SHR     AL, 1                           ; D0 E8
                RCL     DL, 1                           ; D0 D2
                SHR     AL, 1                           ; D0 E8
                RCL     DL, 1                           ; D0 D2
                SHR     AL, 1                           ; D0 E8
                RCL     DL, 1                           ; D0 D2
                MOV     AL, DL                          ; 8A C2
                ROR     AX, CL                          ; D3 C8
                MOV     DL, es:[DI]                     ; 26 8A 15
                STOSB                                   ; AA
                MOV     CL, BL                          ; 8A CB
                SHR     AH, CL                          ; D2 EC
                DEC     CH                              ; FE CD
                JNZ     fx_1c96                        ; 75 CB
                TEST    BYTE PTR cs:[2368H], 1H         ; 2E F6 06 68 23 01
                JNZ     fx_1cdf                        ; 75 0C
fx_1cd3:
                MOV     CL, DH                          ; 8A CE
                XOR     AL, AL                          ; 32 C0
                ROR     AX, CL                          ; D3 C8
                MOV     AH, es:[DI]                     ; 26 8A 25
                STOSB                                   ; AA
                MOV     CL, BL                          ; 8A CB
fx_1cdf:
                POP     SI                              ; 5E
                POP     DI                              ; 5F
                ADD     SI, cs:[235FH]                  ; 2E 03 36 5F 23
                ADD     DI, 28H                         ; 83 C7 28
                PUSH    DI                              ; 57
                PUSH    SI                              ; 56
                DEC     BP                              ; 4D
                JZ      fx_1cf1                        ; 74 03
                JMP     fx_1c61                        ; E9 70 FF
fx_1cf1:
                MOV     CL, DH                          ; 8A CE
                ADD     SP, 2H                          ; 83 C4 02
                POP     DI                              ; 5F
                POP     DX                              ; 5A
                POP     DI                              ; 5F
                POP     SI                              ; 5E
                ; ----- Pass 2: plane 1 (G). GC Read Plane Select=1,
                ; Seq Map Mask=0x02.
                ADD     SI, cs:[2361H]                  ; 2E 03 36 61 23
                PUSH    SI                              ; 56
                PUSH    DI                              ; 57
                PUSH    DX                              ; 52
                MOV     DX, 3CEH                        ; BA CE 03
                MOV     AX, 104H                        ; B8 04 01         GC Read Plane = 1
                OUT     DX, AX                          ; EF
                MOV     DX, 3C4H                        ; BA C4 03
                MOV     AX, 202H                        ; B8 02 02         Seq Map Mask = 0x02
                OUT     DX, AX                          ; EF
                POP     DX                              ; 5A
                PUSH    DX                              ; 52
                PUSH    DI                              ; 57
                MOV     BL, cs:[236AH]                  ; 2E 8A 1E 6A 23
                XOR     BH, BH                          ; 32 FF
                MOV     BP, BX                          ; 8B EB
                MOV     BH, DH                          ; 8A FE
                MOV     DH, CL                          ; 8A F1
                SUB     CL, 8H                          ; 80 E9 08
                NEG     CL                              ; F6 D9
                MOV     BL, CL                          ; 8A D9
                PUSH    SI                              ; 56
fx_1d28:
                MOV     CH, BH                          ; 8A EF
                XOR     AH, AH                          ; 32 E4
                TEST    BYTE PTR cs:[2369H], 1H         ; 2E F6 06 69 23 01
                JZ      fx_1d5d                        ; 74 29
                MOV     AL, [SI+1H]                     ; 8A 44 01
                SHR     AL, 1                           ; D0 E8
                RCL     AH, 1                           ; D0 D4
                SHR     AL, 1                           ; D0 E8
                RCL     AH, 1                           ; D0 D4
                SHR     AL, 1                           ; D0 E8
                RCL     AH, 1                           ; D0 D4
                SHR     AL, 1                           ; D0 E8
                RCL     AH, 1                           ; D0 D4
                SHR     AL, 1                           ; D0 E8
                RCL     AH, 1                           ; D0 D4
                SHR     AL, 1                           ; D0 E8
                RCL     AH, 1                           ; D0 D4
                SHR     AL, 1                           ; D0 E8
                RCL     AH, 1                           ; D0 D4
                SHR     AL, 1                           ; D0 E8
                RCL     AH, 1                           ; D0 D4
                MOV     AL, AH                          ; 8A C4
                OR      CH, CH                          ; 0A ED
                JZ      fx_1d9a                        ; 74 3D
fx_1d5d:
                MOV     CL, DH                          ; 8A CE
                MOV     AL, [SI]                        ; 8A 04
                DEC     SI                              ; 4E
                SHR     AL, 1                           ; D0 E8
                RCL     DL, 1                           ; D0 D2
                SHR     AL, 1                           ; D0 E8
                RCL     DL, 1                           ; D0 D2
                SHR     AL, 1                           ; D0 E8
                RCL     DL, 1                           ; D0 D2
                SHR     AL, 1                           ; D0 E8
                RCL     DL, 1                           ; D0 D2
                SHR     AL, 1                           ; D0 E8
                RCL     DL, 1                           ; D0 D2
                SHR     AL, 1                           ; D0 E8
                RCL     DL, 1                           ; D0 D2
                SHR     AL, 1                           ; D0 E8
                RCL     DL, 1                           ; D0 D2
                SHR     AL, 1                           ; D0 E8
                RCL     DL, 1                           ; D0 D2
                MOV     AL, DL                          ; 8A C2
                ROR     AX, CL                          ; D3 C8
                MOV     DL, es:[DI]                     ; 26 8A 15
                STOSB                                   ; AA
                MOV     CL, BL                          ; 8A CB
                SHR     AH, CL                          ; D2 EC
                DEC     CH                              ; FE CD
                JNZ     fx_1d5d                        ; 75 CB
                TEST    BYTE PTR cs:[2368H], 1H         ; 2E F6 06 68 23 01
                JNZ     fx_1da6                        ; 75 0C
fx_1d9a:
                MOV     CL, DH                          ; 8A CE
                XOR     AL, AL                          ; 32 C0
                ROR     AX, CL                          ; D3 C8
                MOV     AH, es:[DI]                     ; 26 8A 25
                STOSB                                   ; AA
                MOV     CL, BL                          ; 8A CB
fx_1da6:
                POP     SI                              ; 5E
                POP     DI                              ; 5F
                ADD     SI, cs:[235FH]                  ; 2E 03 36 5F 23
                ADD     DI, 28H                         ; 83 C7 28
                PUSH    DI                              ; 57
                PUSH    SI                              ; 56
                DEC     BP                              ; 4D
                JZ      fx_1db8                        ; 74 03
                JMP     fx_1d28                        ; E9 70 FF
fx_1db8:
                MOV     CL, DH                          ; 8A CE
                ADD     SP, 2H                          ; 83 C4 02
                POP     DI                              ; 5F
                POP     DX                              ; 5A
                POP     DI                              ; 5F
                POP     SI                              ; 5E
                ; ----- Pass 3: plane 2 (R). GC Read Plane Select=2,
                ; Seq Map Mask=0x04.
                ADD     SI, cs:[2361H]                  ; 2E 03 36 61 23
                PUSH    SI                              ; 56
                PUSH    DI                              ; 57
                PUSH    DX                              ; 52
                MOV     DX, 3CEH                        ; BA CE 03
                MOV     AX, 204H                        ; B8 04 02         GC Read Plane = 2
                OUT     DX, AX                          ; EF
                MOV     DX, 3C4H                        ; BA C4 03
                MOV     AX, 402H                        ; B8 02 04         Seq Map Mask = 0x04
                OUT     DX, AX                          ; EF
                POP     DX                              ; 5A
                PUSH    DX                              ; 52
                PUSH    DI                              ; 57
                MOV     BL, cs:[236AH]                  ; 2E 8A 1E 6A 23
                XOR     BH, BH                          ; 32 FF
                MOV     BP, BX                          ; 8B EB
                MOV     BH, DH                          ; 8A FE
                MOV     DH, CL                          ; 8A F1
                SUB     CL, 8H                          ; 80 E9 08
                NEG     CL                              ; F6 D9
                MOV     BL, CL                          ; 8A D9
                PUSH    SI                              ; 56
fx_1def:
                MOV     CH, BH                          ; 8A EF
                XOR     AH, AH                          ; 32 E4
                TEST    BYTE PTR cs:[2369H], 1H         ; 2E F6 06 69 23 01
                JZ      fx_1e24                        ; 74 29
                MOV     AL, [SI+1H]                     ; 8A 44 01
                SHR     AL, 1                           ; D0 E8
                RCL     AH, 1                           ; D0 D4
                SHR     AL, 1                           ; D0 E8
                RCL     AH, 1                           ; D0 D4
                SHR     AL, 1                           ; D0 E8
                RCL     AH, 1                           ; D0 D4
                SHR     AL, 1                           ; D0 E8
                RCL     AH, 1                           ; D0 D4
                SHR     AL, 1                           ; D0 E8
                RCL     AH, 1                           ; D0 D4
                SHR     AL, 1                           ; D0 E8
                RCL     AH, 1                           ; D0 D4
                SHR     AL, 1                           ; D0 E8
                RCL     AH, 1                           ; D0 D4
                SHR     AL, 1                           ; D0 E8
                RCL     AH, 1                           ; D0 D4
                MOV     AL, AH                          ; 8A C4
                OR      CH, CH                          ; 0A ED
                JZ      fx_1e61                        ; 74 3D
fx_1e24:
                MOV     CL, DH                          ; 8A CE
                MOV     AL, [SI]                        ; 8A 04
                DEC     SI                              ; 4E
                SHR     AL, 1                           ; D0 E8
                RCL     DL, 1                           ; D0 D2
                SHR     AL, 1                           ; D0 E8
                RCL     DL, 1                           ; D0 D2
                SHR     AL, 1                           ; D0 E8
                RCL     DL, 1                           ; D0 D2
                SHR     AL, 1                           ; D0 E8
                RCL     DL, 1                           ; D0 D2
                SHR     AL, 1                           ; D0 E8
                RCL     DL, 1                           ; D0 D2
                SHR     AL, 1                           ; D0 E8
                RCL     DL, 1                           ; D0 D2
                SHR     AL, 1                           ; D0 E8
                RCL     DL, 1                           ; D0 D2
                SHR     AL, 1                           ; D0 E8
                RCL     DL, 1                           ; D0 D2
                MOV     AL, DL                          ; 8A C2
                ROR     AX, CL                          ; D3 C8
                MOV     DL, es:[DI]                     ; 26 8A 15
                STOSB                                   ; AA
                MOV     CL, BL                          ; 8A CB
                SHR     AH, CL                          ; D2 EC
                DEC     CH                              ; FE CD
                JNZ     fx_1e24                        ; 75 CB
                TEST    BYTE PTR cs:[2368H], 1H         ; 2E F6 06 68 23 01
                JNZ     fx_1e6d                        ; 75 0C
fx_1e61:
                MOV     CL, DH                          ; 8A CE
                XOR     AL, AL                          ; 32 C0
                ROR     AX, CL                          ; D3 C8
                MOV     AH, es:[DI]                     ; 26 8A 25
                STOSB                                   ; AA
                MOV     CL, BL                          ; 8A CB
fx_1e6d:
                POP     SI                              ; 5E
                POP     DI                              ; 5F
                ADD     SI, cs:[235FH]                  ; 2E 03 36 5F 23
                ADD     DI, 28H                         ; 83 C7 28
                PUSH    DI                              ; 57
                PUSH    SI                              ; 56
                DEC     BP                              ; 4D
                JZ      fx_1e7f                        ; 74 03
                JMP     fx_1def                        ; E9 70 FF
fx_1e7f:
                MOV     CL, DH                          ; 8A CE
                ADD     SP, 2H                          ; 83 C4 02
                POP     DI                              ; 5F
                POP     DX                              ; 5A
                POP     DI                              ; 5F
                POP     SI                              ; 5E
                ; ----- Pass 4: plane 3 (I). GC Read Plane Select=3,
                ; Seq Map Mask=0x08.
                ADD     SI, cs:[2361H]                  ; 2E 03 36 61 23
                PUSH    SI                              ; 56
                PUSH    DI                              ; 57
                PUSH    DX                              ; 52
                MOV     DX, 3CEH                        ; BA CE 03
                MOV     AX, 304H                        ; B8 04 03         GC Read Plane = 3
                OUT     DX, AX                          ; EF
                MOV     DX, 3C4H                        ; BA C4 03
                MOV     AX, 802H                        ; B8 02 08         Seq Map Mask = 0x08
                OUT     DX, AX                          ; EF
                POP     DX                              ; 5A
                PUSH    DX                              ; 52
                PUSH    DI                              ; 57
                MOV     BL, cs:[236AH]                  ; 2E 8A 1E 6A 23
                XOR     BH, BH                          ; 32 FF
                MOV     BP, BX                          ; 8B EB
                MOV     BH, DH                          ; 8A FE
                MOV     DH, CL                          ; 8A F1
                SUB     CL, 8H                          ; 80 E9 08
                NEG     CL                              ; F6 D9
                MOV     BL, CL                          ; 8A D9
                PUSH    SI                              ; 56
fx_1eb6:
                MOV     CH, BH                          ; 8A EF
                XOR     AH, AH                          ; 32 E4
                TEST    BYTE PTR cs:[2369H], 1H         ; 2E F6 06 69 23 01
                JZ      fx_1eeb                        ; 74 29
                MOV     AL, [SI+1H]                     ; 8A 44 01
                SHR     AL, 1                           ; D0 E8
                RCL     AH, 1                           ; D0 D4
                SHR     AL, 1                           ; D0 E8
                RCL     AH, 1                           ; D0 D4
                SHR     AL, 1                           ; D0 E8
                RCL     AH, 1                           ; D0 D4
                SHR     AL, 1                           ; D0 E8
                RCL     AH, 1                           ; D0 D4
                SHR     AL, 1                           ; D0 E8
                RCL     AH, 1                           ; D0 D4
                SHR     AL, 1                           ; D0 E8
                RCL     AH, 1                           ; D0 D4
                SHR     AL, 1                           ; D0 E8
                RCL     AH, 1                           ; D0 D4
                SHR     AL, 1                           ; D0 E8
                RCL     AH, 1                           ; D0 D4
                MOV     AL, AH                          ; 8A C4
                OR      CH, CH                          ; 0A ED
                JZ      fx_1f28                        ; 74 3D
fx_1eeb:
                MOV     CL, DH                          ; 8A CE
                MOV     AL, [SI]                        ; 8A 04
                DEC     SI                              ; 4E
                SHR     AL, 1                           ; D0 E8
                RCL     DL, 1                           ; D0 D2
                SHR     AL, 1                           ; D0 E8
                RCL     DL, 1                           ; D0 D2
                SHR     AL, 1                           ; D0 E8
                RCL     DL, 1                           ; D0 D2
                SHR     AL, 1                           ; D0 E8
                RCL     DL, 1                           ; D0 D2
                SHR     AL, 1                           ; D0 E8
                RCL     DL, 1                           ; D0 D2
                SHR     AL, 1                           ; D0 E8
                RCL     DL, 1                           ; D0 D2
                SHR     AL, 1                           ; D0 E8
                RCL     DL, 1                           ; D0 D2
                SHR     AL, 1                           ; D0 E8
                RCL     DL, 1                           ; D0 D2
                MOV     AL, DL                          ; 8A C2
                ROR     AX, CL                          ; D3 C8
                MOV     DL, es:[DI]                     ; 26 8A 15
                STOSB                                   ; AA
                MOV     CL, BL                          ; 8A CB
                SHR     AH, CL                          ; D2 EC
                DEC     CH                              ; FE CD
                JNZ     fx_1eeb                        ; 75 CB
                TEST    BYTE PTR cs:[2368H], 1H         ; 2E F6 06 68 23 01
                JNZ     fx_1f34                        ; 75 0C
fx_1f28:
                MOV     CL, DH                          ; 8A CE
                XOR     AL, AL                          ; 32 C0
                ROR     AX, CL                          ; D3 C8
                MOV     AH, es:[DI]                     ; 26 8A 25
                STOSB                                   ; AA
                MOV     CL, BL                          ; 8A CB
fx_1f34:
                POP     SI                              ; 5E
                POP     DI                              ; 5F
                ADD     SI, cs:[235FH]                  ; 2E 03 36 5F 23
                ADD     DI, 28H                         ; 83 C7 28
                PUSH    DI                              ; 57
                PUSH    SI                              ; 56
                DEC     BP                              ; 4D
                JZ      fx_1f46                        ; 74 03
                JMP     fx_1eb6                        ; E9 70 FF
fx_1f46:
                MOV     CL, DH                          ; 8A CE
                ADD     SP, 2H                          ; 83 C4 02
                POP     DI                              ; 5F
                POP     DX                              ; 5A
                ADD     SP, 4H                          ; 83 C4 04
                JMP     ega_sprite_epilogue                        ; E9 E9 03
ega_blit_sprite_flipx_core ENDP

; ============================================================================
; ega_blit_sprite_flipxy_core @ 0x1F53..0x2357 (1028 bytes)
;
; FAR core for flags=3 (h+v flip). Combines the per-byte bit reversal of
; flipx_core (8x SHR/RCL bit-reverser) with the per-row SUB-instead-of-ADD
; source-pointer step from flipy_core. The source thus walks bottom-to-top
; row-wise and right-to-left within each row.
;
; This is the largest of the four cores because it sits at the end of the
; group and falls into the SHARED sprite-core epilogue at
; ega_sprite_epilogue (0x233C) -- the other three cores tail-JMP to that
; same label. See the noflip plate for the per-plane / per-pass structure
; shared by all four cores.
; ============================================================================
ega_blit_sprite_flipxy_core PROC FAR
                ; ----- Pass 0: build the transparency mask via GC Bit Mask (reg 8).
                ; Inner loop does flipx's bit-reverse and flipy's per-row
                ; SUB-stepping; row counter is stashed at cs:[0x236B] for the
                ; same reason as flipx (BL is the RCL accumulator).
                PUSH    SI                              ; 56
                PUSH    DI                              ; 57
                PUSH    DX                              ; 52
                PUSH    DI                              ; 57
                MOV     BH, DH                          ; 8A FE
                MOV     AL, cs:[236AH]                  ; 2E A0 6A 23      row count
                MOV     cs:[236BH], AL                  ; 2E A2 6B 23      stash for the inner DEC
                MOV     DX, 3CEH                        ; BA CE 03
                MOV     AL, 8H                          ; B0 08            GC idx 8 = Bit Mask
                OUT     DX, AL                          ; EE
                INC     DX                              ; 42               DX = 0x3CF (data)
                MOV     SI, BP                          ; 8B F5
                PUSH    SI                              ; 56
fxy_1f6b:
                MOV     CH, BH                          ; 8A EF
                XOR     AH, AH                          ; 32 E4
                TEST    BYTE PTR cs:[2369H], 1H         ; 2E F6 06 69 23 01
                JZ      fxy_1fa2                        ; 74 2B
                MOV     AL, [SI+1H]                     ; 8A 44 01
                NOT     AL                              ; F6 D0
                SHR     AL, 1                           ; D0 E8
                RCL     AH, 1                           ; D0 D4
                SHR     AL, 1                           ; D0 E8
                RCL     AH, 1                           ; D0 D4
                SHR     AL, 1                           ; D0 E8
                RCL     AH, 1                           ; D0 D4
                SHR     AL, 1                           ; D0 E8
                RCL     AH, 1                           ; D0 D4
                SHR     AL, 1                           ; D0 E8
                RCL     AH, 1                           ; D0 D4
                SHR     AL, 1                           ; D0 E8
                RCL     AH, 1                           ; D0 D4
                SHR     AL, 1                           ; D0 E8
                RCL     AH, 1                           ; D0 D4
                SHR     AL, 1                           ; D0 E8
                RCL     AH, 1                           ; D0 D4
                MOV     AL, AH                          ; 8A C4
                OR      CH, CH                          ; 0A ED
                JZ      fxy_1fea                        ; 74 48
fxy_1fa2:
                MOV     AL, [SI]                        ; 8A 04
                DEC     SI                              ; 4E
                NOT     AL                              ; F6 D0
                SHR     AL, 1                           ; D0 E8
                RCL     BL, 1                           ; D0 D3
                SHR     AL, 1                           ; D0 E8
                RCL     BL, 1                           ; D0 D3
                SHR     AL, 1                           ; D0 E8
                RCL     BL, 1                           ; D0 D3
                SHR     AL, 1                           ; D0 E8
                RCL     BL, 1                           ; D0 D3
                SHR     AL, 1                           ; D0 E8
                RCL     BL, 1                           ; D0 D3
                SHR     AL, 1                           ; D0 E8
                RCL     BL, 1                           ; D0 D3
                SHR     AL, 1                           ; D0 E8
                RCL     BL, 1                           ; D0 D3
                SHR     AL, 1                           ; D0 E8
                RCL     BL, 1                           ; D0 D3
                MOV     AL, BL                          ; 8A C3
                ROR     AX, CL                          ; D3 C8
                OUT     DX, AL                          ; EE
                MOV     AL, es:[DI]                     ; 26 8A 05
                XOR     AL, AL                          ; 32 C0
                STOSB                                   ; AA
                MOV     AL, 8H                          ; B0 08
                SUB     CL, AL                          ; 2A C8
                NEG     CL                              ; F6 D9
                SHR     AH, CL                          ; D2 EC
                SUB     CL, AL                          ; 2A C8
                NEG     CL                              ; F6 D9
                DEC     CH                              ; FE CD
                JNZ     fxy_1fa2                        ; 75 C0
                TEST    BYTE PTR cs:[2368H], 1H         ; 2E F6 06 68 23 01
                JNZ     fxy_1ff5                        ; 75 0B
fxy_1fea:
                XOR     AL, AL                          ; 32 C0
                ROR     AX, CL                          ; D3 C8
                OUT     DX, AL                          ; EE
                MOV     AL, es:[DI]                     ; 26 8A 05
                XOR     AL, AL                          ; 32 C0
                STOSB                                   ; AA
fxy_1ff5:
                POP     SI                              ; 5E
                POP     DI                              ; 5F
                SUB     SI, cs:[235FH]                  ; 2E 2B 36 5F 23
                ADD     DI, 28H                         ; 83 C7 28
                PUSH    DI                              ; 57
                PUSH    SI                              ; 56
                DEC     BYTE PTR cs:[236BH]             ; 2E FE 0E 6B 23
                JZ      fxy_200b                        ; 74 03
                JMP     fxy_1f6b                        ; E9 60 FF
fxy_200b:
                XOR     AL, AL                          ; 32 C0
                MOV     AL, 0FFH                        ; B0 FF
                OUT     DX, AL                          ; EE
                ADD     SP, 2H                          ; 83 C4 02
                POP     DI                              ; 5F
                POP     DX                              ; 5A
                POP     DI                              ; 5F
                POP     SI                              ; 5E
                ; ----- Switch to write-mode 0 + GC Data Rotate=OR (0x10).
                PUSH    DX                              ; 52
                MOV     DX, 3CEH                        ; BA CE 03
                MOV     AX, 5H                          ; B8 05 00         GC reg 5 (Mode) = 0
                OUT     DX, AX                          ; EF
                MOV     AX, 1003H                       ; B8 03 10         GC reg 3 (Data Rotate)=OR
                OUT     DX, AX                          ; EF
                POP     DX                              ; 5A
                ; ----- Pass 1: plane 0 (B). GC Read Plane Select=0 +
                ; Seq Map Mask=0x01.
                PUSH    SI                              ; 56
                PUSH    DI                              ; 57
                PUSH    DX                              ; 52
                MOV     DX, 3CEH                        ; BA CE 03
                MOV     AX, 4H                          ; B8 04 00         GC idx 4 (Read Plane) = 0
                OUT     DX, AX                          ; EF
                MOV     DX, 3C4H                        ; BA C4 03
                MOV     AX, 102H                        ; B8 02 01         Seq Map Mask = 0x01
                OUT     DX, AX                          ; EF
                POP     DX                              ; 5A
                PUSH    DX                              ; 52
                PUSH    DI                              ; 57
                MOV     BL, cs:[236AH]                  ; 2E 8A 1E 6A 23
                XOR     BH, BH                          ; 32 FF
                MOV     BP, BX                          ; 8B EB
                MOV     BH, DH                          ; 8A FE
                MOV     DH, CL                          ; 8A F1
                SUB     CL, 8H                          ; 80 E9 08
                NEG     CL                              ; F6 D9
                MOV     BL, CL                          ; 8A D9
                PUSH    SI                              ; 56
fxy_204d:
                MOV     CH, BH                          ; 8A EF
                XOR     AH, AH                          ; 32 E4
                TEST    BYTE PTR cs:[2369H], 1H         ; 2E F6 06 69 23 01
                JZ      fxy_2082                        ; 74 29
                MOV     AL, [SI+1H]                     ; 8A 44 01
                SHR     AL, 1                           ; D0 E8
                RCL     AH, 1                           ; D0 D4
                SHR     AL, 1                           ; D0 E8
                RCL     AH, 1                           ; D0 D4
                SHR     AL, 1                           ; D0 E8
                RCL     AH, 1                           ; D0 D4
                SHR     AL, 1                           ; D0 E8
                RCL     AH, 1                           ; D0 D4
                SHR     AL, 1                           ; D0 E8
                RCL     AH, 1                           ; D0 D4
                SHR     AL, 1                           ; D0 E8
                RCL     AH, 1                           ; D0 D4
                SHR     AL, 1                           ; D0 E8
                RCL     AH, 1                           ; D0 D4
                SHR     AL, 1                           ; D0 E8
                RCL     AH, 1                           ; D0 D4
                MOV     AL, AH                          ; 8A C4
                OR      CH, CH                          ; 0A ED
                JZ      fxy_20bf                        ; 74 3D
fxy_2082:
                MOV     CL, DH                          ; 8A CE
                MOV     AL, [SI]                        ; 8A 04
                DEC     SI                              ; 4E
                SHR     AL, 1                           ; D0 E8
                RCL     DL, 1                           ; D0 D2
                SHR     AL, 1                           ; D0 E8
                RCL     DL, 1                           ; D0 D2
                SHR     AL, 1                           ; D0 E8
                RCL     DL, 1                           ; D0 D2
                SHR     AL, 1                           ; D0 E8
                RCL     DL, 1                           ; D0 D2
                SHR     AL, 1                           ; D0 E8
                RCL     DL, 1                           ; D0 D2
                SHR     AL, 1                           ; D0 E8
                RCL     DL, 1                           ; D0 D2
                SHR     AL, 1                           ; D0 E8
                RCL     DL, 1                           ; D0 D2
                SHR     AL, 1                           ; D0 E8
                RCL     DL, 1                           ; D0 D2
                MOV     AL, DL                          ; 8A C2
                ROR     AX, CL                          ; D3 C8
                MOV     DL, es:[DI]                     ; 26 8A 15
                STOSB                                   ; AA
                MOV     CL, BL                          ; 8A CB
                SHR     AH, CL                          ; D2 EC
                DEC     CH                              ; FE CD
                JNZ     fxy_2082                        ; 75 CB
                TEST    BYTE PTR cs:[2368H], 1H         ; 2E F6 06 68 23 01
                JNZ     fxy_20cb                        ; 75 0C
fxy_20bf:
                MOV     CL, DH                          ; 8A CE
                XOR     AL, AL                          ; 32 C0
                ROR     AX, CL                          ; D3 C8
                MOV     AH, es:[DI]                     ; 26 8A 25
                STOSB                                   ; AA
                MOV     CL, BL                          ; 8A CB
fxy_20cb:
                POP     SI                              ; 5E
                POP     DI                              ; 5F
                SUB     SI, cs:[235FH]                  ; 2E 2B 36 5F 23
                ADD     DI, 28H                         ; 83 C7 28
                PUSH    DI                              ; 57
                PUSH    SI                              ; 56
                DEC     BP                              ; 4D
                JZ      fxy_20dd                        ; 74 03
                JMP     fxy_204d                        ; E9 70 FF
fxy_20dd:
                MOV     CL, DH                          ; 8A CE
                ADD     SP, 2H                          ; 83 C4 02
                POP     DI                              ; 5F
                POP     DX                              ; 5A
                POP     DI                              ; 5F
                POP     SI                              ; 5E
                ADD     SI, cs:[2361H]                  ; 2E 03 36 61 23
                PUSH    SI                              ; 56
                PUSH    DI                              ; 57
                PUSH    DX                              ; 52
                MOV     DX, 3CEH                        ; BA CE 03
                MOV     AX, 104H                        ; B8 04 01
                OUT     DX, AX                          ; EF
                MOV     DX, 3C4H                        ; BA C4 03
                MOV     AX, 202H                        ; B8 02 02
                OUT     DX, AX                          ; EF
                POP     DX                              ; 5A
                PUSH    DX                              ; 52
                PUSH    DI                              ; 57
                MOV     BL, cs:[236AH]                  ; 2E 8A 1E 6A 23
                XOR     BH, BH                          ; 32 FF
                MOV     BP, BX                          ; 8B EB
                MOV     BH, DH                          ; 8A FE
                MOV     DH, CL                          ; 8A F1
                SUB     CL, 8H                          ; 80 E9 08
                NEG     CL                              ; F6 D9
                MOV     BL, CL                          ; 8A D9
                PUSH    SI                              ; 56
fxy_2114:
                MOV     CH, BH                          ; 8A EF
                XOR     AH, AH                          ; 32 E4
                TEST    BYTE PTR cs:[2369H], 1H         ; 2E F6 06 69 23 01
                JZ      fxy_2149                        ; 74 29
                MOV     AL, [SI+1H]                     ; 8A 44 01
                SHR     AL, 1                           ; D0 E8
                RCL     AH, 1                           ; D0 D4
                SHR     AL, 1                           ; D0 E8
                RCL     AH, 1                           ; D0 D4
                SHR     AL, 1                           ; D0 E8
                RCL     AH, 1                           ; D0 D4
                SHR     AL, 1                           ; D0 E8
                RCL     AH, 1                           ; D0 D4
                SHR     AL, 1                           ; D0 E8
                RCL     AH, 1                           ; D0 D4
                SHR     AL, 1                           ; D0 E8
                RCL     AH, 1                           ; D0 D4
                SHR     AL, 1                           ; D0 E8
                RCL     AH, 1                           ; D0 D4
                SHR     AL, 1                           ; D0 E8
                RCL     AH, 1                           ; D0 D4
                MOV     AL, AH                          ; 8A C4
                OR      CH, CH                          ; 0A ED
                JZ      fxy_2186                        ; 74 3D
fxy_2149:
                MOV     CL, DH                          ; 8A CE
                MOV     AL, [SI]                        ; 8A 04
                DEC     SI                              ; 4E
                SHR     AL, 1                           ; D0 E8
                RCL     DL, 1                           ; D0 D2
                SHR     AL, 1                           ; D0 E8
                RCL     DL, 1                           ; D0 D2
                SHR     AL, 1                           ; D0 E8
                RCL     DL, 1                           ; D0 D2
                SHR     AL, 1                           ; D0 E8
                RCL     DL, 1                           ; D0 D2
                SHR     AL, 1                           ; D0 E8
                RCL     DL, 1                           ; D0 D2
                SHR     AL, 1                           ; D0 E8
                RCL     DL, 1                           ; D0 D2
                SHR     AL, 1                           ; D0 E8
                RCL     DL, 1                           ; D0 D2
                SHR     AL, 1                           ; D0 E8
                RCL     DL, 1                           ; D0 D2
                MOV     AL, DL                          ; 8A C2
                ROR     AX, CL                          ; D3 C8
                MOV     DL, es:[DI]                     ; 26 8A 15
                STOSB                                   ; AA
                MOV     CL, BL                          ; 8A CB
                SHR     AH, CL                          ; D2 EC
                DEC     CH                              ; FE CD
                JNZ     fxy_2149                        ; 75 CB
                TEST    BYTE PTR cs:[2368H], 1H         ; 2E F6 06 68 23 01
                JNZ     fxy_2192                        ; 75 0C
fxy_2186:
                MOV     CL, DH                          ; 8A CE
                XOR     AL, AL                          ; 32 C0
                ROR     AX, CL                          ; D3 C8
                MOV     AH, es:[DI]                     ; 26 8A 25
                STOSB                                   ; AA
                MOV     CL, BL                          ; 8A CB
fxy_2192:
                POP     SI                              ; 5E
                POP     DI                              ; 5F
                SUB     SI, cs:[235FH]                  ; 2E 2B 36 5F 23
                ADD     DI, 28H                         ; 83 C7 28
                PUSH    DI                              ; 57
                PUSH    SI                              ; 56
                DEC     BP                              ; 4D
                JZ      fxy_21a4                        ; 74 03
                JMP     fxy_2114                        ; E9 70 FF
fxy_21a4:
                MOV     CL, DH                          ; 8A CE
                ADD     SP, 2H                          ; 83 C4 02
                POP     DI                              ; 5F
                POP     DX                              ; 5A
                POP     DI                              ; 5F
                POP     SI                              ; 5E
                ADD     SI, cs:[2361H]                  ; 2E 03 36 61 23
                PUSH    SI                              ; 56
                PUSH    DI                              ; 57
                PUSH    DX                              ; 52
                MOV     DX, 3CEH                        ; BA CE 03
                MOV     AX, 204H                        ; B8 04 02
                OUT     DX, AX                          ; EF
                MOV     DX, 3C4H                        ; BA C4 03
                MOV     AX, 402H                        ; B8 02 04
                OUT     DX, AX                          ; EF
                POP     DX                              ; 5A
                PUSH    DX                              ; 52
                PUSH    DI                              ; 57
                MOV     BL, cs:[236AH]                  ; 2E 8A 1E 6A 23
                XOR     BH, BH                          ; 32 FF
                MOV     BP, BX                          ; 8B EB
                MOV     BH, DH                          ; 8A FE
                MOV     DH, CL                          ; 8A F1
                SUB     CL, 8H                          ; 80 E9 08
                NEG     CL                              ; F6 D9
                MOV     BL, CL                          ; 8A D9
                PUSH    SI                              ; 56
fxy_21db:
                MOV     CH, BH                          ; 8A EF
                XOR     AH, AH                          ; 32 E4
                TEST    BYTE PTR cs:[2369H], 1H         ; 2E F6 06 69 23 01
                JZ      fxy_2210                        ; 74 29
                MOV     AL, [SI+1H]                     ; 8A 44 01
                SHR     AL, 1                           ; D0 E8
                RCL     AH, 1                           ; D0 D4
                SHR     AL, 1                           ; D0 E8
                RCL     AH, 1                           ; D0 D4
                SHR     AL, 1                           ; D0 E8
                RCL     AH, 1                           ; D0 D4
                SHR     AL, 1                           ; D0 E8
                RCL     AH, 1                           ; D0 D4
                SHR     AL, 1                           ; D0 E8
                RCL     AH, 1                           ; D0 D4
                SHR     AL, 1                           ; D0 E8
                RCL     AH, 1                           ; D0 D4
                SHR     AL, 1                           ; D0 E8
                RCL     AH, 1                           ; D0 D4
                SHR     AL, 1                           ; D0 E8
                RCL     AH, 1                           ; D0 D4
                MOV     AL, AH                          ; 8A C4
                OR      CH, CH                          ; 0A ED
                JZ      fxy_224d                        ; 74 3D
fxy_2210:
                MOV     CL, DH                          ; 8A CE
                MOV     AL, [SI]                        ; 8A 04
                DEC     SI                              ; 4E
                SHR     AL, 1                           ; D0 E8
                RCL     DL, 1                           ; D0 D2
                SHR     AL, 1                           ; D0 E8
                RCL     DL, 1                           ; D0 D2
                SHR     AL, 1                           ; D0 E8
                RCL     DL, 1                           ; D0 D2
                SHR     AL, 1                           ; D0 E8
                RCL     DL, 1                           ; D0 D2
                SHR     AL, 1                           ; D0 E8
                RCL     DL, 1                           ; D0 D2
                SHR     AL, 1                           ; D0 E8
                RCL     DL, 1                           ; D0 D2
                SHR     AL, 1                           ; D0 E8
                RCL     DL, 1                           ; D0 D2
                SHR     AL, 1                           ; D0 E8
                RCL     DL, 1                           ; D0 D2
                MOV     AL, DL                          ; 8A C2
                ROR     AX, CL                          ; D3 C8
                MOV     DL, es:[DI]                     ; 26 8A 15
                STOSB                                   ; AA
                MOV     CL, BL                          ; 8A CB
                SHR     AH, CL                          ; D2 EC
                DEC     CH                              ; FE CD
                JNZ     fxy_2210                        ; 75 CB
                TEST    BYTE PTR cs:[2368H], 1H         ; 2E F6 06 68 23 01
                JNZ     fxy_2259                        ; 75 0C
fxy_224d:
                MOV     CL, DH                          ; 8A CE
                XOR     AL, AL                          ; 32 C0
                ROR     AX, CL                          ; D3 C8
                MOV     AH, es:[DI]                     ; 26 8A 25
                STOSB                                   ; AA
                MOV     CL, BL                          ; 8A CB
fxy_2259:
                POP     SI                              ; 5E
                POP     DI                              ; 5F
                SUB     SI, cs:[235FH]                  ; 2E 2B 36 5F 23
                ADD     DI, 28H                         ; 83 C7 28
                PUSH    DI                              ; 57
                PUSH    SI                              ; 56
                DEC     BP                              ; 4D
                JZ      fxy_226b                        ; 74 03
                JMP     fxy_21db                        ; E9 70 FF
fxy_226b:
                MOV     CL, DH                          ; 8A CE
                ADD     SP, 2H                          ; 83 C4 02
                POP     DI                              ; 5F
                POP     DX                              ; 5A
                POP     DI                              ; 5F
                POP     SI                              ; 5E
                ADD     SI, cs:[2361H]                  ; 2E 03 36 61 23
                PUSH    SI                              ; 56
                PUSH    DI                              ; 57
                PUSH    DX                              ; 52
                MOV     DX, 3CEH                        ; BA CE 03
                MOV     AX, 304H                        ; B8 04 03
                OUT     DX, AX                          ; EF
                MOV     DX, 3C4H                        ; BA C4 03
                MOV     AX, 802H                        ; B8 02 08
                OUT     DX, AX                          ; EF
                POP     DX                              ; 5A
                PUSH    DX                              ; 52
                PUSH    DI                              ; 57
                MOV     BL, cs:[236AH]                  ; 2E 8A 1E 6A 23
                XOR     BH, BH                          ; 32 FF
                MOV     BP, BX                          ; 8B EB
                MOV     BH, DH                          ; 8A FE
                MOV     DH, CL                          ; 8A F1
                SUB     CL, 8H                          ; 80 E9 08
                NEG     CL                              ; F6 D9
                MOV     BL, CL                          ; 8A D9
                PUSH    SI                              ; 56
fxy_22a2:
                MOV     CH, BH                          ; 8A EF
                XOR     AH, AH                          ; 32 E4
                TEST    BYTE PTR cs:[2369H], 1H         ; 2E F6 06 69 23 01
                JZ      fxy_22d7                        ; 74 29
                MOV     AL, [SI+1H]                     ; 8A 44 01
                SHR     AL, 1                           ; D0 E8
                RCL     AH, 1                           ; D0 D4
                SHR     AL, 1                           ; D0 E8
                RCL     AH, 1                           ; D0 D4
                SHR     AL, 1                           ; D0 E8
                RCL     AH, 1                           ; D0 D4
                SHR     AL, 1                           ; D0 E8
                RCL     AH, 1                           ; D0 D4
                SHR     AL, 1                           ; D0 E8
                RCL     AH, 1                           ; D0 D4
                SHR     AL, 1                           ; D0 E8
                RCL     AH, 1                           ; D0 D4
                SHR     AL, 1                           ; D0 E8
                RCL     AH, 1                           ; D0 D4
                SHR     AL, 1                           ; D0 E8
                RCL     AH, 1                           ; D0 D4
                MOV     AL, AH                          ; 8A C4
                OR      CH, CH                          ; 0A ED
                JZ      fxy_2314                        ; 74 3D
fxy_22d7:
                MOV     CL, DH                          ; 8A CE
                MOV     AL, [SI]                        ; 8A 04
                DEC     SI                              ; 4E
                SHR     AL, 1                           ; D0 E8
                RCL     DL, 1                           ; D0 D2
                SHR     AL, 1                           ; D0 E8
                RCL     DL, 1                           ; D0 D2
                SHR     AL, 1                           ; D0 E8
                RCL     DL, 1                           ; D0 D2
                SHR     AL, 1                           ; D0 E8
                RCL     DL, 1                           ; D0 D2
                SHR     AL, 1                           ; D0 E8
                RCL     DL, 1                           ; D0 D2
                SHR     AL, 1                           ; D0 E8
                RCL     DL, 1                           ; D0 D2
                SHR     AL, 1                           ; D0 E8
                RCL     DL, 1                           ; D0 D2
                SHR     AL, 1                           ; D0 E8
                RCL     DL, 1                           ; D0 D2
                MOV     AL, DL                          ; 8A C2
                ROR     AX, CL                          ; D3 C8
                MOV     DL, es:[DI]                     ; 26 8A 15
                STOSB                                   ; AA
                MOV     CL, BL                          ; 8A CB
                SHR     AH, CL                          ; D2 EC
                DEC     CH                              ; FE CD
                JNZ     fxy_22d7                        ; 75 CB
                TEST    BYTE PTR cs:[2368H], 1H         ; 2E F6 06 68 23 01
                JNZ     fxy_2320                        ; 75 0C
fxy_2314:
                MOV     CL, DH                          ; 8A CE
                XOR     AL, AL                          ; 32 C0
                ROR     AX, CL                          ; D3 C8
                MOV     AH, es:[DI]                     ; 26 8A 25
                STOSB                                   ; AA
                MOV     CL, BL                          ; 8A CB
fxy_2320:
                POP     SI                              ; 5E
                POP     DI                              ; 5F
                SUB     SI, cs:[235FH]                  ; 2E 2B 36 5F 23
                ADD     DI, 28H                         ; 83 C7 28
                PUSH    DI                              ; 57
                PUSH    SI                              ; 56
                DEC     BP                              ; 4D
                JZ      fxy_2332                        ; 74 03
                JMP     fxy_22a2                        ; E9 70 FF
fxy_2332:
                MOV     CL, DH                          ; 8A CE
                ADD     SP, 2H                          ; 83 C4 02
                POP     DI                              ; 5F
                POP     DX                              ; 5A
                ADD     SP, 4H                          ; 83 C4 04
ega_sprite_epilogue:                                            ; 0x233C
                ; ----- Shared sprite-core epilogue. Reached by:
                ;   * fall-through from ega_blit_sprite_flipxy_core
                ;   * tail-JMP from ega_blit_sprite_noflip_core / flipy_core /
                ;     flipx_core
                ;   * tail-JMP from ega_blit_sprite_master's clip-fail paths
                ; Restores the chunk's default EGA state (GC Mode=wm2, GC
                ; Data Rotate=0, Seq Map Mask=0F), unwinds the 10-byte
                ; sprite-descriptor stack buffer set up by the master, then
                ; RETFs back to the original FAR caller.
                MOV     DX, 3CEH                        ; BA CE 03
                MOV     AX, 205H                        ; B8 05 02         GC Mode = 2 (wm2)
                OUT     DX, AX                          ; EF
                MOV     AX, 3H                          ; B8 03 00         GC Data Rotate = 0
                OUT     DX, AX                          ; EF
                MOV     DX, 3C4H                        ; BA C4 03
                MOV     AX, 0F02H                       ; B8 02 0F         Seq Map Mask = 0x0F
                OUT     DX, AX                          ; EF
                POP     DS                              ; 1F
                POP     ES                              ; 07
                POP     DI                              ; 5F
                POP     SI                              ; 5E
                ADD     SP, 0AH                         ; 83 C4 0A         drop sprite-desc scratch
                POP     BP                              ; 5D
                RETF                                    ; CB
ega_blit_sprite_flipxy_core ENDP

; ----------------------------------------------------------------------------
; g_apfnEgaSpriteFlipDispatch -- 4-entry near-pointer table, 2 bytes each.
; chunk:0x2357..0x235E
;
; Indexed by the (flags & 3) byte arg of ega_blit_sprite_master:
;   index 0 (flags=0, no flip)  -> 0x1675  ega_blit_sprite_noflip_core
;   index 1 (flags=1, vflip)    -> 0x18EE  ega_blit_sprite_flipy_core
;   index 2 (flags=2, hflip)    -> 0x1B67  ega_blit_sprite_flipx_core
;   index 3 (flags=3, h+v flip) -> 0x1F53  ega_blit_sprite_flipxy_core
;
; The master loads the entry into AX and `JMP AX`s to it (see end of
; ega_blit_sprite_master). All four cores tail-jump (or fall through, for
; flipxy) into ega_sprite_epilogue at 0x233C.
; ----------------------------------------------------------------------------
g_apfnEgaSpriteFlipDispatch:
                DB      075H, 016H, 0EEH, 018H, 067H, 01BH, 053H, 01FH                                   ; 0x2357

; ----------------------------------------------------------------------------
; sprite_scratch_globals_mid1 -- chunk-local sprite-state slots.
; chunk:0x235F..0x236D (15 bytes, zero-init).
;
; Populated by ega_blit_sprite_master at the head of each blit; read by
; the dispatched sprite core. Slots are 1-byte unless noted:
;
;   0x235F  WORD  src_row_stride        -- chunky source bytes/row
;   0x2361  WORD  src_col_advance       -- columns added across "passes"
;   0x2363  WORD  src_seg               -- caller's source segment
;   0x2365  WORD  src_off_initial       -- initial source offset
;   0x2367  BYTE  flags                 -- bit0=hflip, bit1=vflip
;   0x2368  BYTE  clip_right_active     -- 1 = right edge is clipped
;   0x2369  BYTE  clip_left_active      -- 1 = left edge is clipped
;   0x236A  BYTE  rows_to_draw          -- vertical span after clip
;   0x236B  BYTE  row_counter           -- private to flipx/flipxy cores
;   0x236C  WORD  sprite_cache_offset   -- accumulator for cache uploader
;                                          (also reset by ega_sprite_state_reset)
; ----------------------------------------------------------------------------
sprite_scratch_globals_mid1:
                DB      000H, 000H, 000H, 000H, 000H, 000H, 000H, 000H, 000H, 000H, 000H, 000H, 000H, 000H, 000H ; 0x235F

; ============================================================================
; ega_blit_stretched @ 0x236E..0x2406 (152 bytes)
;
; FAR. Performs a vertical-stretch blit by REP MOVSB-ing the same source
; row repeatedly to consecutive destination rows. Uses GC Mode 1 (latch
; copy). The inner row-copy loop is 8x-unrolled with early-exit JZ at
; each step when the row counter hits zero.
;
; ARGS (far): [BP+0]=src_seg, [BP+2]=src_off, [BP+6]=byte_width,
;             [BP+8]=dst_x, [BP+A]=dst_y; row count in [BP+8] saved early
; ============================================================================
ega_blit_stretched PROC FAR
                PUSH    BP                              ; 55
                MOV     BP, SP                          ; 8B EC
                PUSH    SI                              ; 56
                PUSH    DI                              ; 57
                PUSH    DS                              ; 1E
                MOV     DS, cs:[7DH]                    ; 2E 8E 1E 7D 00
                MOV     DI, [BP+0AH]                    ; 8B 7E 0A     dst_y
                SHL     DI, 1                           ; D1 E7
                MOV     DI, ds:[DI+(GfxContext.pRow_offset_lut)]                ; 8B BD F2 06  row base
                MOV     AX, [BP+8]                      ; 8B 46 08     dst_x
                SHR     AX, 1                           ; D1 E8
                SHR     AX, 1                           ; D1 E8
                SHR     AX, 1                           ; D1 E8
                ADD     DI, AX                          ; 03 F8
                MOV     BP, [BP+6]                      ; 8B 6E 06     byte width
                MOV     ES, ds:[GfxContext.wGfxBlitDstPage]                    ; 8E 06 18 00
                MOV     DX, 03CEH                       ; BA CE 03
                MOV     AX, 0105H                       ; B8 05 01     GC Mode = 1
                OUT     DX, AX                          ; EF
                MOV     DX, [BP+8]                      ; 8B 56 08     reuse: dst_x as row count slot
                MOV     BX, [BP+6]                      ; 8B 5E 06
                SHR     BX, 1                           ; D1 EB
                SHR     BX, 1                           ; D1 EB
                SHR     BX, 1                           ; D1 EB        BX = bytes
                MOV     SI, [BP+2]                      ; 8B 76 02     src off
                MOV     DS, [BP+0]                      ; 8E 5E 00     src seg
                MOV     BP, 28H                         ; BD 28 00
                SUB     BP, BX                          ; 2B EB        BP = 40 - bytes
@@bs_row:
                MOV     CX, BX                          ; 8B CB
                REP     MOVSB                           ; F3 A4
                ADD     DI, BP                          ; 03 FD
                DEC     DX                              ; 4A
                JZ      SHORT @@bs_done                 ; 74 3F
                MOV     CX, BX                          ; 8B CB
                REP     MOVSB                           ; F3 A4
                ADD     DI, BP                          ; 03 FD
                DEC     DX                              ; 4A
                JZ      SHORT @@bs_done                 ; 74 36
                MOV     CX, BX                          ; 8B CB
                REP     MOVSB                           ; F3 A4
                ADD     DI, BP                          ; 03 FD
                DEC     DX                              ; 4A
                JZ      SHORT @@bs_done                 ; 74 2D
                MOV     CX, BX                          ; 8B CB
                REP     MOVSB                           ; F3 A4
                ADD     DI, BP                          ; 03 FD
                DEC     DX                              ; 4A
                JZ      SHORT @@bs_done                 ; 74 24
                MOV     CX, BX                          ; 8B CB
                REP     MOVSB                           ; F3 A4
                ADD     DI, BP                          ; 03 FD
                DEC     DX                              ; 4A
                JZ      SHORT @@bs_done                 ; 74 1B
                MOV     CX, BX                          ; 8B CB
                REP     MOVSB                           ; F3 A4
                ADD     DI, BP                          ; 03 FD
                DEC     DX                              ; 4A
                JZ      SHORT @@bs_done                 ; 74 12
                MOV     CX, BX                          ; 8B CB
                REP     MOVSB                           ; F3 A4
                ADD     DI, BP                          ; 03 FD
                DEC     DX                              ; 4A
                JZ      SHORT @@bs_done                 ; 74 09
                MOV     CX, BX                          ; 8B CB
                REP     MOVSB                           ; F3 A4
                ADD     DI, BP                          ; 03 FD
                DEC     DX                              ; 4A
                JNZ     SHORT @@bs_row                  ; 75 B8
@@bs_done:
                MOV     DX, 03CEH                       ; BA CE 03
                MOV     AX, 0205H                       ; B8 05 02     restore Mode=wm2
                OUT     DX, AX                          ; EF
                POP     DS                              ; 1F
                POP     DI                              ; 5F
                POP     SI                              ; 5E
                POP     BP                              ; 5D
                RETF                                    ; CB
ega_blit_stretched ENDP

; ============================================================================
; ega_sprite_cache_upload_dead @ 0x2406..0x249B (149 bytes)
;
; FAR. Sprite-cache uploader (dead / unused in the shipping game). Walks a
; near-ptr array of sprite descriptors at [BP+6]; for each
; non-null, copies the sprite's 4-plane bytes from caller's source seg
; to a freshly-allocated AC00 EGA scratch segment, updates each
; descriptor's segment field to AC00, advances a chunk-local linear
; offset tracker at cs:[236C] (= ega_sprite_state_reset's slot). When
; the array terminates, INT 21h AH=49 frees the AC00 segment (DOS free).
; ============================================================================
ega_sprite_cache_upload_dead PROC FAR
                PUSH    BP                              ; 55
                MOV     BP, SP                          ; 8B EC
                PUSH    DI                              ; 57
                PUSH    SI                              ; 56
                MOV     BP, [BP+6]                      ; 8B 6E 06     descriptor array
                MOV     BX, [BP+0]                      ; 8B 5E 00
                PUSH    BP                              ; 55
                PUSH    WORD PTR [BX]                   ; FF 37        save initial seg
@@scud_loop:
                MOV     BX, [BP+0]                      ; 8B 5E 00
                ADD     BP, 2                           ; 83 C5 02
                OR      BX, BX                          ; 0B DB
                JZ      SHORT @@scud_done               ; 74 65
                MOV     AX, 0AC00H                      ; B8 00 AC
                MOV     ES, AX                          ; 8E C0
                MOV     DI, cs:[236CH]                  ; 2E 8B 3E 6C 23 dst offset accumulator
                MOV     SI, [BX+2]                      ; 8B 77 02
                MOV     [BX+2], DI                      ; 89 7F 02
                MOV     AX, [BX+6]                      ; 8B 47 06     width
                XOR     DX, DX                          ; 33 D2
                MUL     WORD PTR [BX+8]                 ; F7 67 08     * height
                SHR     AX, 1                           ; D1 E8
                SHR     AX, 1                           ; D1 E8
                SHR     AX, 1                           ; D1 E8        /= 8
                ADD     cs:[236CH], AX                  ; 2E 01 06 6C 23
                MOV     CX, AX                          ; 8B C8
                PUSH    DS                              ; 1E
                MOV     AX, [BX]                        ; 8B 07
                MOV     DX, ES                          ; 8C C2
                MOV     [BX], DX                        ; 89 17
                MOV     DS, AX                          ; 8E D8
                MOV     AX, 0005H                       ; B8 05 00
                MOV     DX, 03CEH                       ; BA CE 03
                OUT     DX, AX                          ; EF           GC Mode = 0
                MOV     AX, 0005H                       ; B8 05 00     ; reload (unused result)
                MOV     AX, 0102H                       ; B8 02 01     AH=01 (plane 0), AL=02 (Seq Map Mask)
                MOV     DX, 03C4H                       ; BA C4 03
                PUSH    CX                              ; 51
                PUSH    DI                              ; 57
                OUT     DX, AX                          ; EF
                SHL     AH, 1                           ; D0 E4        next plane bit
                REP     MOVSB                           ; F3 A4
                POP     DI                              ; 5F
                POP     CX                              ; 59
                PUSH    CX                              ; 51
                PUSH    DI                              ; 57
                OUT     DX, AX                          ; EF
                SHL     AH, 1                           ; D0 E4
                REP     MOVSB                           ; F3 A4
                POP     DI                              ; 5F
                POP     CX                              ; 59
                PUSH    CX                              ; 51
                PUSH    DI                              ; 57
                OUT     DX, AX                          ; EF
                SHL     AH, 1                           ; D0 E4
                REP     MOVSB                           ; F3 A4
                POP     DI                              ; 5F
                POP     CX                              ; 59
                PUSH    CX                              ; 51
                PUSH    DI                              ; 57
                OUT     DX, AX                          ; EF
                SHL     AH, 1                           ; D0 E4
                REP     MOVSB                           ; F3 A4
                POP     DI                              ; 5F
                POP     CX                              ; 59
                POP     DS                              ; 1F
                JMP     SHORT @@scud_loop               ; EB 91
@@scud_done:
                POP     ES                              ; 07
                MOV     AH, 49H                         ; B4 49        INT 21h AH=49 (free mem)
                INT     21H                             ; CD 21
                MOV     AX, 0205H                       ; B8 05 02
                MOV     DX, 03CEH                       ; BA CE 03
                OUT     DX, AX                          ; EF           restore Mode=wm2
                MOV     AX, 0F02H                       ; B8 02 0F
                MOV     DX, 03C4H                       ; BA C4 03
                OUT     DX, AX                          ; EF           Map Mask = FF
                POP     AX                              ; 58
                POP     SI                              ; 5E
                POP     DI                              ; 5F
                POP     BP                              ; 5D
                RETF                                    ; CB
ega_sprite_cache_upload_dead ENDP

; ============================================================================
; ega_sprite_state_reset @ 0x249B..0x24A2 (7 bytes)
;
; FAR helper that clears a chunk-local sprite-shift state word at CS:236C.
; Called by ega_blit_sprite_chunky_shifted prologue paths that need to
; reset accumulated shift state between distinct sprite blits. Returns
; AX = 0 as a side effect (callers ignore).
; ============================================================================
ega_sprite_state_reset PROC FAR
                XOR     AX, AX                          ; 33 C0
                MOV     cs:[236CH], AX                  ; 2E A3 6C 23
                RETF                                    ; CB
ega_sprite_state_reset ENDP

; ============================================================================
; ega_blit_sprite_chunky_shifted @ 0x24A2..0x2864 (962 bytes)
;
; FAR. Stretched / shifted sprite blit -- variant of blit_sprite_master
; that allows sub-byte x positioning. Walks source pixels two per byte,
; shifts each into the correct plane bit positions via cs:[2364..236C]
; (self-modifying word slots), and ORs into the framebuffer one pixel
; column at a time. Used for special effect sprites (mouse cursor etc.).
;
; ARGS (far): standard sprite blit args at [BP+6..+0E]; flags in [BP+0C].
; ============================================================================
ega_blit_sprite_chunky_shifted PROC FAR
                PUSH    BP                              ; 55
                MOV     BP, SP                          ; 8B EC
                SUB     SP, 0AH                         ; 83 EC 0A
                PUSH    SI                              ; 56
                PUSH    DI                              ; 57
                PUSH    ES                              ; 06
                PUSH    DS                              ; 1E
                MOV     SI, [BP+6H]                     ; 8B 76 06
                MOV     DI, BP                          ; 8B FD
                SUB     DI, 0AH                         ; 83 EF 0A
                MOV     AX, SS                          ; 8C D0
                MOV     ES, AX                          ; 8E C0
                MOV     CX, 5H                          ; B9 05 00
                REP     MOVSW                           ; F3 A5
                MOV     DS, cs:[7DH]                    ; 2E 8E 1E 7D 00
                MOV     AX, ds:[GfxContext.wGfxBlitDstPage]                    ; A1 18 00
                MOV     ES, AX                          ; 8E C0
                MOV     AX, [BP-4H]                     ; 8B 46 FC
                SHR     AX, 1                           ; D1 E8
                SHR     AX, 1                           ; D1 E8
                SHR     AX, 1                           ; D1 E8
                MUL     BYTE PTR [BP-2H]                ; F6 66 FE
                MOV     cs:[2866H], AX                  ; 2E A3 66 28
                MOV     BX, [BP+0AH]                    ; 8B 5E 0A
                SHL     BX, 1                           ; D1 E3
                JNS     bcs_24f0                        ; 79 12
                SAR     BX, 1                           ; D1 FB
                SHL     BX, 1                           ; D1 E3
                SHL     BX, 1                           ; D1 E3
                SHL     BX, 1                           ; D1 E3
                MOV     DI, BX                          ; 8B FB
                SHL     BX, 1                           ; D1 E3
                SHL     BX, 1                           ; D1 E3
                ADD     DI, BX                          ; 03 FB
                JMP     bcs_24f4                        ; EB 04
bcs_24f0:
                MOV     DI, [BX+(GfxContext.pRow_offset_lut)]                   ; 8B BF F2 06
bcs_24f4:
                MOV     AX, [BP+8H]                     ; 8B 46 08
                MOV     CL, AL                          ; 8A C8
                SAR     AX, 1                           ; D1 F8
                SAR     AX, 1                           ; D1 F8
                SAR     AX, 1                           ; D1 F8
                ADD     DI, AX                          ; 03 F8
                AND     CL, 7H                          ; 80 E1 07
                MOV     AX, [BP-4H]                     ; 8B 46 FC
                MOV     DX, AX                          ; 8B D0
                SHR     AX, 1                           ; D1 E8
                SHR     AX, 1                           ; D1 E8
                SHR     AX, 1                           ; D1 E8
                MOV     cs:[2864H], AX                  ; 2E A3 64 28
                ADD     DX, 7H                          ; 83 C2 07
                SHR     DX, 1                           ; D1 EA
                SHR     DX, 1                           ; D1 EA
                SHR     DX, 1                           ; D1 EA
                MOV     DH, DL                          ; 8A F2
                MOV     AL, [BP-2H]                     ; 8A 46 FE
                MOV     cs:[286CH], AL                  ; 2E A2 6C 28
                MOV     AX, [BP-0AH]                    ; 8B 46 F6
                MOV     cs:[2868H], AX                  ; 2E A3 68 28
                MOV     SI, [BP-8H]                     ; 8B 76 F8
                XOR     AX, AX                          ; 33 C0
                MOV     cs:[286AH], AL                  ; 2E A2 6A 28
                MOV     cs:[286BH], AL                  ; 2E A2 6B 28
                JZ      bcs_2542                        ; 74 07
                MOV     AX, cs:[2864H]                  ; 2E A1 64 28
                DEC     AX                              ; 48
                ADD     SI, AX                          ; 03 F0
bcs_2542:
                MOV     AL, ds:[GfxContext.bClip_enabled]                     ; A0 03 00
                OR      AL, AL                          ; 0A C0
                JNZ     bcs_254c                        ; 75 03
                JMP     bcs_25e5                        ; E9 99 00
bcs_254c:
                MOV     AX, ds:[GfxContext.nClip_xmax]                     ; A1 06 00
                INC     AX                              ; 40
                MOV     BX, [BP+8H]                     ; 8B 5E 08
                ADD     BX, [BP-4H]                     ; 03 5E FC
                SUB     AX, BX                          ; 2B C3
                JG      bcs_2572                        ; 7F 18
                NEG     AX                              ; F7 D8
                CMP     AX, [BP-4H]                     ; 3B 46 FC
                JL      bcs_2564                        ; 7C 03
                JMP     bcs_2849                        ; E9 E5 02
bcs_2564:
                SHR     AX, 1                           ; D1 E8
                SHR     AX, 1                           ; D1 E8
                SHR     AX, 1                           ; D1 E8
                SUB     DH, AL                          ; 2A F0
                MOV     BYTE PTR cs:[286AH], 1H         ; 2E C6 06 6A 28 01
bcs_2572:
                MOV     AX, [BP+8H]                     ; 8B 46 08
                SUB     AX, ds:[GfxContext.nClip_xmin]                     ; 2B 06 04 00
                JNS     bcs_259c                        ; 79 21
                MOV     BX, AX                          ; 8B D8
                ADD     AX, [BP-4H]                     ; 03 46 FC
                JG      bcs_2585                        ; 7F 03
                JMP     bcs_2849                        ; E9 C4 02
bcs_2585:
                MOV     BYTE PTR cs:[286BH], 1H         ; 2E C6 06 6B 28 01
                NEG     BX                              ; F7 DB
                ADD     BX, 7H                          ; 83 C3 07
                SHR     BX, 1                           ; D1 EB
                SHR     BX, 1                           ; D1 EB
                SHR     BX, 1                           ; D1 EB
                SUB     DH, BL                          ; 2A F3
                ADD     DI, BX                          ; 03 FB
                ADD     SI, BX                          ; 03 F3
bcs_259c:
                MOV     AX, [BP+0AH]                    ; 8B 46 0A
                ADD     AX, [BP-2H]                     ; 03 46 FE
                SUB     AX, ds:[GfxContext.nClip_ymax]                    ; 2B 06 0A 00
                JS      bcs_25b7                        ; 78 0F
                CMP     AX, [BP-2H]                     ; 3B 46 FE
                JS      bcs_25b0                        ; 78 03
                JMP     bcs_2849                        ; E9 99 02
bcs_25b0:
                DEC     AL                              ; FE C8
                SUB     cs:[286CH], AL                  ; 2E 28 06 6C 28
bcs_25b7:
                MOV     AX, ds:[GfxContext.nClip_ymin]                     ; A1 08 00
                SUB     AX, [BP+0AH]                    ; 2B 46 0A
                JS      bcs_25e5                        ; 78 26
                CMP     AX, [BP-2H]                     ; 3B 46 FE
                JS      bcs_25c7                        ; 78 03
                JMP     bcs_2849                        ; E9 82 02
bcs_25c7:
                SUB     cs:[286CH], AL                  ; 2E 28 06 6C 28
                MOV     BX, AX                          ; 8B D8
                SHL     AX, 1                           ; D1 E0
                SHL     AX, 1                           ; D1 E0
                SHL     AX, 1                           ; D1 E0
                ADD     DI, AX                          ; 03 F8
                SHL     AX, 1                           ; D1 E0
                SHL     AX, 1                           ; D1 E0
                ADD     DI, AX                          ; 03 F8
                MOV     AX, BX                          ; 8B C3
                MUL     BYTE PTR cs:[2864H]             ; 2E F6 26 64 28
                ADD     SI, AX                          ; 03 F0
bcs_25e5:
                MOV     DS, cs:[2868H]                  ; 2E 8E 1E 68 28
                PUSH    SI                              ; 56
                PUSH    DI                              ; 57
                PUSH    DX                              ; 52
                PUSH    DI                              ; 57
                MOV     BH, DH                          ; 8A FE
                MOV     BL, cs:[286CH]                  ; 2E 8A 1E 6C 28
                MOV     DX, 3CEH                        ; BA CE 03
                MOV     AL, 8H                          ; B0 08
                OUT     DX, AL                          ; EE
                INC     DX                              ; 42
                MOV     SI, BP                          ; 8B F5
                PUSH    SI                              ; 56
bcs_25ff:
                MOV     CH, BH                          ; 8A EF
                XOR     AH, AH                          ; 32 E4
                TEST    BYTE PTR cs:[286BH], 1H         ; 2E F6 06 6B 28 01
                JZ      bcs_2614                        ; 74 09
                MOV     AH, [SI-1H]                     ; 8A 64 FF
                NOT     AH                              ; F6 D4
                OR      CH, CH                          ; 0A ED
                JZ      bcs_2639                        ; 74 25
bcs_2614:
                XOR     AL, AL                          ; 32 C0
                NOT     AL                              ; F6 D0
                ROR     AX, CL                          ; D3 C8
                OUT     DX, AL                          ; EE
                MOV     AL, es:[DI]                     ; 26 8A 05
                XOR     AL, AL                          ; 32 C0
                STOSB                                   ; AA
                MOV     AL, 8H                          ; B0 08
                SUB     CL, AL                          ; 2A C8
                NEG     CL                              ; F6 D9
                SHR     AH, CL                          ; D2 EC
                SUB     CL, AL                          ; 2A C8
                NEG     CL                              ; F6 D9
                DEC     CH                              ; FE CD
                JNZ     bcs_2614                        ; 75 E3
                TEST    BYTE PTR cs:[286AH], 1H         ; 2E F6 06 6A 28 01
                JNZ     bcs_2644                        ; 75 0B
bcs_2639:
                XOR     AL, AL                          ; 32 C0
                ROR     AX, CL                          ; D3 C8
                OUT     DX, AL                          ; EE
                MOV     AL, es:[DI]                     ; 26 8A 05
                XOR     AL, AL                          ; 32 C0
                STOSB                                   ; AA
bcs_2644:
                POP     SI                              ; 5E
                POP     DI                              ; 5F
                ADD     SI, cs:[2864H]                  ; 2E 03 36 64 28
                ADD     DI, 28H                         ; 83 C7 28
                PUSH    DI                              ; 57
                PUSH    SI                              ; 56
                DEC     BL                              ; FE CB
                JNZ     bcs_25ff                        ; 75 AB
                XOR     AL, AL                          ; 32 C0
                MOV     AL, 0FFH                        ; B0 FF
                OUT     DX, AL                          ; EE
                ADD     SP, 2H                          ; 83 C4 02
                POP     DI                              ; 5F
                POP     DX                              ; 5A
                POP     DI                              ; 5F
                POP     SI                              ; 5E
                PUSH    DX                              ; 52
                MOV     DX, 3CEH                        ; BA CE 03
                MOV     AX, 5H                          ; B8 05 00
                OUT     DX, AX                          ; EF
                MOV     AX, 1003H                       ; B8 03 10
                OUT     DX, AX                          ; EF
                MOV     AX, 0FF08H                      ; B8 08 FF
                OUT     DX, AX                          ; EF
                POP     DX                              ; 5A
                PUSH    SI                              ; 56
                PUSH    DI                              ; 57
                PUSH    DX                              ; 52
                MOV     DX, 3C4H                        ; BA C4 03
                MOV     AX, 102H                        ; B8 02 01
                OUT     DX, AX                          ; EF
                POP     DX                              ; 5A
                PUSH    DX                              ; 52
                PUSH    DI                              ; 57
                MOV     BL, cs:[286CH]                  ; 2E 8A 1E 6C 28
                XOR     BH, BH                          ; 32 FF
                MOV     BP, BX                          ; 8B EB
                MOV     BH, DH                          ; 8A FE
                MOV     DH, CL                          ; 8A F1
                SUB     CL, 8H                          ; 80 E9 08
                NEG     CL                              ; F6 D9
                MOV     BL, CL                          ; 8A D9
                PUSH    SI                              ; 56
bcs_2693:
                MOV     CH, BH                          ; 8A EF
                XOR     AH, AH                          ; 32 E4
                TEST    BYTE PTR cs:[286BH], 1H         ; 2E F6 06 6B 28 01
                JZ      bcs_26a6                        ; 74 07
                MOV     AH, [SI-1H]                     ; 8A 64 FF
                OR      CH, CH                          ; 0A ED
                JZ      bcs_26bf                        ; 74 19
bcs_26a6:
                MOV     CL, DH                          ; 8A CE
                LODSB                                   ; AC
                ROR     AX, CL                          ; D3 C8
                MOV     DL, es:[DI]                     ; 26 8A 15
                STOSB                                   ; AA
                MOV     CL, BL                          ; 8A CB
                SHR     AH, CL                          ; D2 EC
                DEC     CH                              ; FE CD
                JNZ     bcs_26a6                        ; 75 EF
                TEST    BYTE PTR cs:[286AH], 1H         ; 2E F6 06 6A 28 01
                JNZ     bcs_26cb                        ; 75 0C
bcs_26bf:
                MOV     CL, DH                          ; 8A CE
                XOR     AL, AL                          ; 32 C0
                ROR     AX, CL                          ; D3 C8
                MOV     AH, es:[DI]                     ; 26 8A 25
                STOSB                                   ; AA
                MOV     CL, BL                          ; 8A CB
bcs_26cb:
                POP     SI                              ; 5E
                POP     DI                              ; 5F
                ADD     SI, cs:[2864H]                  ; 2E 03 36 64 28
                ADD     DI, 28H                         ; 83 C7 28
                PUSH    DI                              ; 57
                PUSH    SI                              ; 56
                DEC     BP                              ; 4D
                JNZ     bcs_2693                        ; 75 B9
                MOV     CL, DH                          ; 8A CE
                ADD     SP, 2H                          ; 83 C4 02
                POP     DI                              ; 5F
                POP     DX                              ; 5A
                POP     DI                              ; 5F
                POP     SI                              ; 5E
                ADD     SI, cs:[2866H]                  ; 2E 03 36 66 28
                PUSH    SI                              ; 56
                PUSH    DI                              ; 57
                PUSH    DX                              ; 52
                MOV     DX, 3C4H                        ; BA C4 03
                MOV     AX, 202H                        ; B8 02 02
                OUT     DX, AX                          ; EF
                POP     DX                              ; 5A
                PUSH    DX                              ; 52
                PUSH    DI                              ; 57
                MOV     BL, cs:[286CH]                  ; 2E 8A 1E 6C 28
                XOR     BH, BH                          ; 32 FF
                MOV     BP, BX                          ; 8B EB
                MOV     BH, DH                          ; 8A FE
                MOV     DH, CL                          ; 8A F1
                SUB     CL, 8H                          ; 80 E9 08
                NEG     CL                              ; F6 D9
                MOV     BL, CL                          ; 8A D9
                PUSH    SI                              ; 56
bcs_270a:
                MOV     CH, BH                          ; 8A EF
                XOR     AH, AH                          ; 32 E4
                TEST    BYTE PTR cs:[286BH], 1H         ; 2E F6 06 6B 28 01
                JZ      bcs_271d                        ; 74 07
                MOV     AH, [SI-1H]                     ; 8A 64 FF
                OR      CH, CH                          ; 0A ED
                JZ      bcs_2736                        ; 74 19
bcs_271d:
                MOV     CL, DH                          ; 8A CE
                LODSB                                   ; AC
                ROR     AX, CL                          ; D3 C8
                MOV     DL, es:[DI]                     ; 26 8A 15
                STOSB                                   ; AA
                MOV     CL, BL                          ; 8A CB
                SHR     AH, CL                          ; D2 EC
                DEC     CH                              ; FE CD
                JNZ     bcs_271d                        ; 75 EF
                TEST    BYTE PTR cs:[286AH], 1H         ; 2E F6 06 6A 28 01
                JNZ     bcs_2742                        ; 75 0C
bcs_2736:
                MOV     CL, DH                          ; 8A CE
                XOR     AL, AL                          ; 32 C0
                ROR     AX, CL                          ; D3 C8
                MOV     AH, es:[DI]                     ; 26 8A 25
                STOSB                                   ; AA
                MOV     CL, BL                          ; 8A CB
bcs_2742:
                POP     SI                              ; 5E
                POP     DI                              ; 5F
                ADD     SI, cs:[2864H]                  ; 2E 03 36 64 28
                ADD     DI, 28H                         ; 83 C7 28
                PUSH    DI                              ; 57
                PUSH    SI                              ; 56
                DEC     BP                              ; 4D
                JNZ     bcs_270a                        ; 75 B9
                MOV     CL, DH                          ; 8A CE
                ADD     SP, 2H                          ; 83 C4 02
                POP     DI                              ; 5F
                POP     DX                              ; 5A
                POP     DI                              ; 5F
                POP     SI                              ; 5E
                ADD     SI, cs:[2866H]                  ; 2E 03 36 66 28
                PUSH    SI                              ; 56
                PUSH    DI                              ; 57
                PUSH    DX                              ; 52
                MOV     DX, 3C4H                        ; BA C4 03
                MOV     AX, 402H                        ; B8 02 04
                OUT     DX, AX                          ; EF
                POP     DX                              ; 5A
                PUSH    DX                              ; 52
                PUSH    DI                              ; 57
                MOV     BL, cs:[286CH]                  ; 2E 8A 1E 6C 28
                XOR     BH, BH                          ; 32 FF
                MOV     BP, BX                          ; 8B EB
                MOV     BH, DH                          ; 8A FE
                MOV     DH, CL                          ; 8A F1
                SUB     CL, 8H                          ; 80 E9 08
                NEG     CL                              ; F6 D9
                MOV     BL, CL                          ; 8A D9
                PUSH    SI                              ; 56
bcs_2781:
                MOV     CH, BH                          ; 8A EF
                XOR     AH, AH                          ; 32 E4
                TEST    BYTE PTR cs:[286BH], 1H         ; 2E F6 06 6B 28 01
                JZ      bcs_2794                        ; 74 07
                MOV     AH, [SI-1H]                     ; 8A 64 FF
                OR      CH, CH                          ; 0A ED
                JZ      bcs_27ad                        ; 74 19
bcs_2794:
                MOV     CL, DH                          ; 8A CE
                LODSB                                   ; AC
                ROR     AX, CL                          ; D3 C8
                MOV     DL, es:[DI]                     ; 26 8A 15
                STOSB                                   ; AA
                MOV     CL, BL                          ; 8A CB
                SHR     AH, CL                          ; D2 EC
                DEC     CH                              ; FE CD
                JNZ     bcs_2794                        ; 75 EF
                TEST    BYTE PTR cs:[286AH], 1H         ; 2E F6 06 6A 28 01
                JNZ     bcs_27b9                        ; 75 0C
bcs_27ad:
                MOV     CL, DH                          ; 8A CE
                XOR     AL, AL                          ; 32 C0
                ROR     AX, CL                          ; D3 C8
                MOV     AH, es:[DI]                     ; 26 8A 25
                STOSB                                   ; AA
                MOV     CL, BL                          ; 8A CB
bcs_27b9:
                POP     SI                              ; 5E
                POP     DI                              ; 5F
                ADD     SI, cs:[2864H]                  ; 2E 03 36 64 28
                ADD     DI, 28H                         ; 83 C7 28
                PUSH    DI                              ; 57
                PUSH    SI                              ; 56
                DEC     BP                              ; 4D
                JNZ     bcs_2781                        ; 75 B9
                MOV     CL, DH                          ; 8A CE
                ADD     SP, 2H                          ; 83 C4 02
                POP     DI                              ; 5F
                POP     DX                              ; 5A
                POP     DI                              ; 5F
                POP     SI                              ; 5E
                ADD     SI, cs:[2866H]                  ; 2E 03 36 66 28
                PUSH    SI                              ; 56
                PUSH    DI                              ; 57
                PUSH    DX                              ; 52
                MOV     DX, 3C4H                        ; BA C4 03
                MOV     AX, 802H                        ; B8 02 08
                OUT     DX, AX                          ; EF
                POP     DX                              ; 5A
                PUSH    DX                              ; 52
                PUSH    DI                              ; 57
                MOV     BL, cs:[286CH]                  ; 2E 8A 1E 6C 28
                XOR     BH, BH                          ; 32 FF
                MOV     BP, BX                          ; 8B EB
                MOV     BH, DH                          ; 8A FE
                MOV     DH, CL                          ; 8A F1
                SUB     CL, 8H                          ; 80 E9 08
                NEG     CL                              ; F6 D9
                MOV     BL, CL                          ; 8A D9
                PUSH    SI                              ; 56
bcs_27f8:
                MOV     CH, BH                          ; 8A EF
                XOR     AH, AH                          ; 32 E4
                TEST    BYTE PTR cs:[286BH], 1H         ; 2E F6 06 6B 28 01
                JZ      bcs_280b                        ; 74 07
                MOV     AH, [SI-1H]                     ; 8A 64 FF
                OR      CH, CH                          ; 0A ED
                JZ      bcs_2824                        ; 74 19
bcs_280b:
                MOV     CL, DH                          ; 8A CE
                LODSB                                   ; AC
                ROR     AX, CL                          ; D3 C8
                MOV     DL, es:[DI]                     ; 26 8A 15
                STOSB                                   ; AA
                MOV     CL, BL                          ; 8A CB
                SHR     AH, CL                          ; D2 EC
                DEC     CH                              ; FE CD
                JNZ     bcs_280b                        ; 75 EF
                TEST    BYTE PTR cs:[286AH], 1H         ; 2E F6 06 6A 28 01
                JNZ     bcs_2830                        ; 75 0C
bcs_2824:
                MOV     CL, DH                          ; 8A CE
                XOR     AL, AL                          ; 32 C0
                ROR     AX, CL                          ; D3 C8
                MOV     AH, es:[DI]                     ; 26 8A 25
                STOSB                                   ; AA
                MOV     CL, BL                          ; 8A CB
bcs_2830:
                POP     SI                              ; 5E
                POP     DI                              ; 5F
                ADD     SI, cs:[2864H]                  ; 2E 03 36 64 28
                ADD     DI, 28H                         ; 83 C7 28
                PUSH    DI                              ; 57
                PUSH    SI                              ; 56
                DEC     BP                              ; 4D
                JNZ     bcs_27f8                        ; 75 B9
                MOV     CL, DH                          ; 8A CE
                ADD     SP, 2H                          ; 83 C4 02
                POP     DI                              ; 5F
                POP     DX                              ; 5A
                ADD     SP, 4H                          ; 83 C4 04
bcs_2849:
                MOV     DX, 3CEH                        ; BA CE 03
                MOV     AX, 205H                        ; B8 05 02
                OUT     DX, AX                          ; EF
                MOV     AX, 3H                          ; B8 03 00
                OUT     DX, AX                          ; EF
                MOV     DX, 3C4H                        ; BA C4 03
                MOV     AX, 0F02H                       ; B8 02 0F
                OUT     DX, AX                          ; EF
                POP     DS                              ; 1F
                POP     ES                              ; 07
                POP     DI                              ; 5F
                POP     SI                              ; 5E
                ADD     SP, 0AH                         ; 83 C4 0A
                POP     BP                              ; 5D
                RETF                                    ; CB
ega_blit_sprite_chunky_shifted ENDP

; ----------------------------------------------------------------------------
; sprite_scratch_globals_mid2 -- chunk-local state for the shifted-sprite blit.
; chunk:0x2864..0x286C (9 bytes, zero-init).
;
; Used exclusively by ega_blit_sprite_chunky_shifted (the same way mid1 is
; used by the four flip cores). Slots:
;
;   0x2864  WORD  src_row_stride
;   0x2866  WORD  src_col_advance
;   0x2868  WORD  src_seg
;   0x286A  BYTE  clip_right_active
;   0x286B  BYTE  clip_left_active
;   0x286C  BYTE  rows_to_draw
; ----------------------------------------------------------------------------
sprite_scratch_globals_mid2:
                DB      000H, 000H, 000H, 000H, 000H, 000H, 000H, 000H, 000H                             ; 0x2864

; ============================================================================
; ega_slot24_retf_stub @ 0x286D..0x286E (1 bytes)
;
; A second 1-byte RETF stub (distinct from ega_unimplemented_slot @ 0x16D
; only by address). Wedged here between sprite_scratch_globals_mid2 and
; ega_palette_set_one so vtable slot 24 has a unique linear target if
; some adapter snapshots offsets at link time. Behaviourally identical
; to ega_unimplemented_slot.
; ============================================================================
ega_slot24_retf_stub PROC FAR
                RETF                                    ; CB
ega_slot24_retf_stub ENDP

; ============================================================================
; ega_palette_set_one @ 0x286E..0x2897 (41 bytes)
;
; FAR helper that sets BIOS palette register #1 to a caller-supplied
; colour, with a special remap when the chunk is running in monochrome
; mode (ds:[1Dh] == 2). In mono, colours 0..7 are passed through, but
; colours 8..15 are remapped to 0x10..0x17 (the high-intensity bank).
;
; ARGS (far, single ushort): [BP+6] = colour_index (0..0Fh)
; CLOBBERS: BX, AX, flags
; CALLS:    BIOS INT 10h AH=10h AL=01h (set individual palette register)
; ============================================================================
ega_palette_set_one PROC FAR
                PUSH    BP                              ; 55
                MOV     BP, SP                          ; 8B EC
                PUSH    DS                              ; 1E
                MOV     DS, cs:[7DH]                    ; 2E 8E 1E 7D 00  DS = scratch
                MOV     BX, [BP+6]                      ; 8B 5E 06
                MOV     BH, BL                          ; 8A FB
                AND     BH, 0FH                         ; 80 E7 0F
                CMP     BYTE PTR ds:[GfxContext.bVideoAdapter], 2            ; 80 3E 1D 00 02   mono-mode flag
                JNZ     SHORT @@pso_skip                ; 75 08
                CMP     BH, 8                           ; 80 FF 08
                JC      SHORT @@pso_skip                ; 72 03
                ADD     BH, 8                           ; 80 C7 08         remap 8..F -> 10..17
@@pso_skip:
                MOV     AH, 10H                         ; B4 10
                MOV     AL, 1                           ; B0 01            AH=10h AL=01h
                INT     10H                             ; CD 10            set palette register
                POP     DS                              ; 1F
                POP     BP                              ; 5D
                RETF                                    ; CB
ega_palette_set_one ENDP

; ============================================================================
; ega_palette_set_synced @ 0x2897..0x28E2 (75 bytes)
;
; FAR helper that programs ONE EGA attribute-controller palette register
; (AR0..AR0F or the mono-remapped AR10..AR17) directly through port
; 0x3C0, synchronised with the input-status-1 retrace signal so the
; write does not cause visible "snow" on a real EGA.  [The snow happens
; because AC palette writes during scan-out can corrupt the AC pixel
; pipeline.]
;
; Each AR register is 6 bits: bits 2..0 = primary R/G/B, bits 5..3 =
; secondary R/G/B (encoded as RrGgBb on the wire).  On a real IBM
; 5154 monitor, mode-0Dh vsync polarity
; signals "200-line / RGBI" and the secondary bits are dropped (clamps
; to 16-of-16); on a VGA-class monitor all 64 codes are reachable.
;
; ARGS (far): [BP+6] = palette_idx (0..0Fh), [BP+8] = colour (RrGgBb)
;
; SEQUENCE:
;   1. Remap idx 8..0F to 10..17 (mono-aware path; same as palette_set_one
;      but applied unconditionally -- caller has already chosen).
;   2. Read the CRTC base port from BIOS data area 40:63 (= 0x3D4 in
;      colour emulation), add 6 -> input-status-1 at 0x3DA.
;   3. CLI + dummy read of 0x3DA (also resets the AC flip-flop to
;      "index" mode, which is mandatory before any AC write -- the #1
;      EGA programming bug per VGADOC EGAREGS.TXT).
;   4. Spin until bit 0 = 0 (display drawing), then until bit 0 = 1
;      (back in retrace/blanking) -- a tight retrace window in which
;      the AC update is safe.  Bit 0 = "display disabled / in
;      H-or-V retrace" per EGAREGS.TXT 3DAh (FreeVGA calls it "DD"
;      with the same polarity).
;   5. Write AR index then AR data through port 0x3C0; the AC's
;      internal flip-flop alternates roles between the two writes.
;   6. Reset the flip-flop again and write 0x20 (= bit 5, PAS,
;      "screen enable / palette read-locked") to re-arm the AC.  STI.
; ============================================================================
ega_palette_set_synced PROC FAR
                PUSH    BP                              ; 55
                MOV     BP, SP                          ; 8B EC
                PUSH    SI                              ; 56
                PUSH    DI                              ; 57
                PUSH    ES                              ; 06
                MOV     SI, [BP+8]                      ; 8B 76 08    colour
                CMP     SI, 8                           ; 83 FE 08
                JC      SHORT @@pss_skip                ; 72 03
                ADD     SI, 8                           ; 83 C6 08    remap 8..F -> 10..17
@@pss_skip:
                MOV     DI, [BP+6]                      ; 8B 7E 06    palette idx
                MOV     AX, 0040H                       ; B8 40 00
                MOV     ES, AX                          ; 8E C0       ES = BIOS data area
                MOV     DX, es:[63H]                    ; 26 8B 16 63 00   CRTC base port
                ADD     DL, 6                           ; 80 C2 06    +6 -> input-status-1 (0x3DA)
                MOV     BP, DX                          ; 8B EA       save 0x3DA in BP
                MOV     BL, 0C0H                        ; B3 C0       AC port low byte (DX=0x3C0)
                MOV     BH, 20H                         ; B7 20       AC PAS bit (re-enable value)
                MOV     CL, 1                           ; B1 01       mask bit 0 of input-status-1
                CLI                                     ; FA          no IRQs during AC sequence
                IN      AL, DX                          ; EC          reset AC flip-flop to "index"
@@pss_wait_display:
                IN      AL, DX                          ; EC
                TEST    AL, CL                          ; 84 C1
                JNZ     SHORT @@pss_wait_display        ; 75 FB       spin while bit0=1 (in retrace)
@@pss_wait_vsync:
                IN      AL, DX                          ; EC
                TEST    AL, CL                          ; 84 C1
                JZ      SHORT @@pss_wait_vsync          ; 74 FB       spin until bit0=1 (retrace hits)
                MOV     DL, BL                          ; 8A D3       DX = 0x3C0 (AC port)
                MOV     AX, DI                          ; 8B C7
                OUT     DX, AL                          ; EE          AC index (PAS=0; flipflop->data)
                MOV     AX, SI                          ; 8B C6
                OUT     DX, AL                          ; EE          AC data (flipflop->index)
                MOV     DX, BP                          ; 8B D5       DX = 0x3DA
                IN      AL, DX                          ; EC          reset flip-flop again
                MOV     DL, BL                          ; 8A D3       DX = 0x3C0
                MOV     AL, BH                          ; 8A C7       AL=0x20 (PAS=1 -> re-arm AC)
                OUT     DX, AL                          ; EE
                STI                                     ; FB
                POP     ES                              ; 07
                POP     DI                              ; 5F
                POP     SI                              ; 5E
                POP     BP                              ; 5D
                RETF                                    ; CB
ega_palette_set_synced ENDP


                END     _start
