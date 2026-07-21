; ============================================================================
; Vmcode.OVL.VGA -- VGA Mode-Y video driver chunk (10177 bytes, 0x27C1)
;
; Shipped with "Betrayal at Krondor" (Dynamix / Sierra, 1993). Image base
; 0000:0000.
;
; The chunk is one of eight interchangeable graphics drivers in Vmcode.ovl
; and is the engine's PRIMARY rendering target -- selected for any user
; with a VGA-class adapter. Of the seven other drivers, this is the largest
; and the most heavily optimised.
;
; Content: four Mode-Y span pumps, the 3 KB vga_blit_sprite_master with its
; 15 internal JMP-AX dispatchers, the chunky-to-planar converters, the
; full Bresenham line core, DAC / palette helpers, and the trailing data
; tables.
; ============================================================================

; ----------------------------------------------------------------------------
; What this driver is
;
; A "video driver" in Betrayal at Krondor is a small piece of position-
; independent code that the engine loads from the Vmcode.OVL resource
; archive at startup. Different graphics cards need different code, so
; the game ships one driver per supported adapter (CGA, EGA, Tandy,
; Hercules, MCGA, VGA, ...) and picks the right one at runtime.
;
; This file is the VGA driver. The engine communicates with it through
; a vtable of far function pointers: 50 slots, each slot a different
; request like "draw a line", "blit a sprite", "set the palette". When
; a slot is invoked, this code translates that high-level request into
; the specific byte patterns the VGA hardware expects.
; ----------------------------------------------------------------------------

; ----------------------------------------------------------------------------
; About the VGA hardware (Mode-Y configuration)
;
; BACKGROUND -- BIOS Mode 13h and why it's not enough.
;
; IBM's VGA (1987) has 256 KiB of frame buffer arranged as four
; parallel 64 KiB "planes", but only one 64 KiB window is exposed to
; the CPU at a time at A000:0000. The only BIOS-blessed 256-colour
; mode, mode 13h (set via INT 10h AX=0013h), papers over the planar
; reality with a hardware trick called "chain-4": the bottom two
; address bits (A0, A1) silently route consecutive byte writes round-
; robin across the four planes, so the CPU sees a flat linear
; 320*200 = 64,000-byte "chunky" framebuffer where offset = y*320 + x
; selects exactly one pixel. Easy to program -- but it costs you
; access to 3/4 of the installed VRAM, leaves no room for off-screen
; double-buffering, and gives every byte-write a fixed plane target.
;
; "Mode-Y" is NOT a documented IBM mode. IBM never blessed it; the
; name was coined informally on rec.games.programmer in August 1993
; for the 320x200 variant of Michael Abrash's earlier "Mode X"
; (320x240). Both are software-only re-programs: start with BIOS
; mode 13h, then poke a handful of Sequencer / CRTC registers to
; disable chain-4 and switch the CRTC's address generator from
; word-mode (which assumed chain-4) to byte-mode. After that the CPU
; sees the real 4-plane layout. Same 320x200 resolution as 13h, same
; DAC palette, but now:
;
;   * All 256 KiB of VRAM are reachable through the same 64 KiB
;     window -- by toggling the Sequencer's "Map Mask" register the
;     CPU picks which plane(s) a write hits.
;   * Four 16,000-byte pages fit in the 64 KiB window, enabling
;     atomic page-flip double/triple-buffering via the CRTC's
;     start-address register.
;   * One CPU write to a planar address with Map Mask = 0Fh writes
;     four pixels at once (one per plane), so solid fills get a 4x
;     speedup over chunky.
;   * VRAM-to-VRAM rectangle copies via Graphics Controller "write
;     mode 1" (latch copy, see below) read 4 pixels from source into
;     internal latches and write them back to destination in one
;     CPU memcpy cycle -- another 4x speedup.
;
; This is what made smooth-scrolling 256-colour games (Wolfenstein 3D,
; Doom, Pinball Fantasies, Krondor, ...) feasible on a 286/386 in 1991.
;
; The technique was popularised by Abrash's columns in Dr Dobb's and
; PC Techniques in 1990-91 and later collected as chapters 47-49 of
; the *Graphics Programming Black Book*:
;   ch.47  "Mode X: 256-Color VGA Magic"          -- mode-set + theory
;   ch.48  "Mode X Marks the Latch"                -- latch-copy tricks
;   ch.49  "Mode X: A Closer Look"                 -- scrolling, fills
; "X" in Abrash is 320x240 (square-pixel, reprogrammed vertical
; timing); "Y" is the same trick at 320x200, keeping mode-13h's
; vertical timings as-is. Krondor's driver does the Y variant.
; Every Mode-Y / Mode-X driver of the era follows the same setup
; sequence; vga_init below is a textbook example (and is annotated
; with primary-source register-bit citations).
;
; HARDWARE MODEL
;
; The VGA frame buffer at A000:0000 is physically four parallel byte-
; lane "planes" (planes 0..3), all four lanes 64 KiB each. In Mode 13h
; the CPU sees a single chunky byte stream because the chain-4 logic
; (Sequencer reg 4 bit 3, Memory Mode register) silently routes
; consecutive byte writes round-robin across the four planes. With
; chain-4 disabled, the CPU sees plane 0 only on every byte address;
; writes to other planes are selected via the Sequencer Map Mask
; register (reg 2, port 0x3C4/0x3C5), which is a 4-bit "which planes
; receive this write" mask.
;
; Three registers do most of the work:
;
;   * Sequencer reg 2 ("Map Mask"), port 0x3C4 / 0x3C5
;       Bits 0..3 enable plane 0..3 for the next CPU write. 0x0F means
;       "write to all 4 planes at once" -- this is what makes solid
;       colour rectangle fills 4x faster than chunky.
;
;   * Graphics Controller reg 5 ("Mode"), port 0x3CE / 0x3CF
;       Bits 0..1 = write mode. Mode 0 = "write CPU data into the
;       selected planes" (the normal case). Mode 1 = "write the latch
;       contents into the selected planes" -- a CPU read into the
;       latches followed by a CPU write back, all in one MOVSB, copies
;       4 planes worth of source pixels in one go. vga_present and
;       vga_blit_sprite_flip_h use this to copy whole rectangles
;       between buffers at memcpy speed.
;
;   * CRTC reg 0x17 ("Mode Control"), port 0x3D4 / 0x3D5
;       Bit 6 = W/B (Word/Byte mode). Set => CRTC walks one byte per
;       character clock instead of one word; combined with chain-4 OFF
;       (and CR14 bit 6 cleared = DW off), this makes the pixel at
;       (x, y) live at byte offset y * 80 + (x / 4) within plane
;       (x % 4). (See IBM VGA/XGA TR May 1992 chapter 4, FreeVGA CRTC
;       reference, or VGADOC for the bit-level semantics of regs
;       0x14 and 0x17.)
;
; MEMORY MAP & PIXEL ADDRESSING
;
;   - One "page" in Mode-Y is 80 bytes per row * 200 rows = 16,000
;     bytes (NOT 16 KiB / 16,384). The 4 pages are conventionally
;     placed on 0x4000-byte (16 KiB) boundaries within the 64 KiB
;     A000 VRAM window, leaving 384 bytes of slack at the tail of
;     each page (see Abrash GPBB ch.49):
;        Page 0 -> A000:0000..3E7F  (16000 bytes used, 384 slack)
;        Page 1 -> A000:4000..7E7F
;        Page 2 -> A000:8000..BE7F
;        Page 3 -> A000:C000..FE7F
;     Krondor uses three of these as render/visible/back-buffer pages.
;     vga_init stores their *segments* (A000 / A400 / A800) at
;     ds:[0x14] / [0x12] / [0x10] so each handler can load ES directly.
;     Page swaps go through the CRTC start-address registers
;     (reg 0x0C high / 0x0D low) in vga_vsync_wait.
;   - Pixel at (x, y):
;         byte_offset_within_plane = y * 80 + (x / 4)
;         plane_select_mask        = 1 << (x & 3)
;     A 200-row offset LUT at scratch:[0x6F2] caches y*80 for every row.
;
; ADVANTAGES OVER MODE 13H CHUNKY
;
;   - VRAM-to-VRAM copies via latch tricks are ~4x faster (one MOVSB
;     moves 4 pixels at once).
;   - Solid fills via Map Mask = 0Fh write all 4 planes simultaneously.
;   - Triple-buffering fits in one 64 KiB segment.
;   - Hardware page-flipping via the CRTC start-address register --
;     atomic, fully synced with vertical retrace, no tearing.
;
; THE PRICE: pixel-at-a-time writes are slower (the Map Mask has to
; change every time x % 4 rolls over), and any algorithm that walks
; pixels in horizontal scanline order has to do 4 OUT instructions per
; pixel for plane select. This is why the driver has FOUR separate
; "Mode-Y span pump" implementations -- each one is specialised for a
; different combination of source format (solid / textured / dithered /
; world-tiled) and tries to amortise the plane-mask cost across as
; many pixels as possible. See vga_fill_run_a, vga_fill_run_b,
; vga_fill_spans_dithered_modey, vga_fill_world_textured_span_modey,
; vga_fill_textured_span_modey, vga_fill_textured_span_modey_b.
;
; Memory map after vga_init:
;   A000:0000..3E7F  -- back buffer 0 (16,000 bytes used, 384 slack)
;   A400:0000..3E7F  -- back buffer 1 (offset stored at scratch:[0x12])
;   A800:0000..3E7F  -- back buffer 2 / visible (offset at [0x14])
; (Each page occupies one quarter of the 64 KiB A000 window. Krondor
; uses three of the four available Mode-Y pages.)
;
; I/O port reference (Mode-Y register-level summary; index port even,
; data port odd, so most groups accept a single OUT DX,AX with AL=idx
; and AH=data):
;   3C0..3C1  Attribute Controller (palette index, mode; single-port
;                          protocol with internal flip-flop reset by
;                          reading 3DAh)
;   3C4..3C5  Sequencer    (reg 2 = Map Mask -- plane write enable;
;                          reg 4 = Memory Mode -- Chain-4 lives here)
;   3C6..3C9  DAC          (3C6 = PEL Mask, 3C7 W/R = Read Index /
;                          DAC State, 3C8 = Write Index, 3C9 = Data;
;                          6 bits per RGB channel, 3-byte triples)
;   3CE..3CF  Graphics Controller (reg 0 = Set/Reset, reg 4 = Read
;                          Plane Sel, reg 5 = Graphics Mode --
;                          WM/RM/Shift256, reg 6 = Misc Graphics,
;                          reg 8 = Bit Mask)
;   3D4..3D5  CRTC         (reg 9 = Max Scan Line, reg 0Ch/0Dh =
;                          Start Addr Hi/Lo -- page flip, reg 14h =
;                          Underline Loc -- DW bit, reg 17h = Mode
;                          Control -- W/B bit)
;   3DA       Input Status 1 (bit 3 = vertical retrace,
;                          bit 0 = "any retrace -- display disable")
;
; Most port pairs accept a 16-bit OUT DX, AX as a one-shot
; "write index+data" because the index port is even and the data port
; is the next-higher odd address; some lines below use this idiom and
; some don't (the choice is not a semantic difference).
;
; Further reading:
;   - Michael Abrash, *Graphics Programming Black Book*, ch.47-49
;     (freely available online from various mirrors).
;   - FreeVGA register reference: osdever.net/FreeVGA/home.htm.
;   - Finn Thoegersen, *VGA Documentation Project* (VGADOC4b).
;   - IBM, *VGA and XGA Technical Reference* (May 1992),
;     bitsavers/ibm/pc/cards/.
;   - INMOS IMS G171 datasheet (the RAMDAC chip in early VGA /
;     MCGA boards) for DAC-side timing.
;   - Wikipedia "Mode X" / "Mode Y" articles for the historical
;     coining of the names.
; ----------------------------------------------------------------------------

; ----------------------------------------------------------------------------
; How the engine dispatches into this chunk
;
; Vmcode.OVL is a flat archive of eight chunks (one per supported video
; adapter). At startup the engine reads the right chunk into a freshly-
; allocated paragraph-aligned segment, then calls offset 0x0000 of that
; segment as a far function -- this is vga_init below. vga_init does
; three jobs:
;
;   1. Take the host's 19 callback far pointers (which the engine
;      passes in as a "callback table base pointer" via stack args)
;      and REP MOVSW them into the chunk's own 19-slot mirror at
;      chunk:0x01C0..0x020B. After this, the chunk can call back into
;      the engine for memory allocation, file I/O, etc. by doing a
;      CALL FAR [CS:01C0H + N*4] for callback slot N.
;
;   2. Allocate the chunk's private "scratch DS" segment. The engine
;      passes the size in paragraphs at [BP+6]; vga_init carves it off
;      the engine's own data segment (just adds paras/16 to caller's
;      DS) and stores it at chunk:0x00F4 so every later slot handler
;      can re-load it with `MOV DS, cs:[0F4H]`. Real OS-level
;      allocation happens in the engine; the chunk just uses the
;      sub-segment.
;
;   3. Program the VGA into Mode-Y (chain-4 off, byte-mode addressing
;      on, etc.) and pre-compute the 200-row LUT y * 80 at
;      scratch:[0x6F2] so per-scanline byte offsets are a single
;      indexed load later.
;
; vga_init returns a far pointer in DX:SI to the renderer vtable at
; chunk:0x00F8 (g_apfnVgaVtable below). The engine then snapshots that
; table -- 50 far pointers, 200 bytes -- into its own
; g_renderer_vtable storage. From that moment on, every video operation
; the engine wants to perform is a CALL FAR [g_renderer_vtable + slot*4]
; with the slot-specific argument convention.
;
; The 50 slots aren't strict cdecl -- many of them pass arguments in
; registers (BX, CX, DX, SI, DI) directly, the rest are __cdecl16far.
; Each function header below lists its specific ABI. Slots the driver
; doesn't implement point at vga_unimplemented_slot @ chunk:0x020C
; (a 1-byte RETF, harmless no-op).
;
; Layout summary of the chunk's first 0x020D bytes:
;   0x0000..0x00F3  vga_init code
;   0x00F4..0x00F7  globals (chunk DS, paragraph count)
;   0x00F8..0x01BF  g_apfnVgaVtable          (50 slots x 4 bytes)
;   0x01C0..0x020B  g_apfnVgaHostCallbacks   (19 slots x 4 bytes,
;                                              overwritten at runtime)
;   0x020C          vga_unimplemented_slot   (1 byte: RETF)
;   0x020D+         in-line LUTs + function bodies, no further dispatch
;
; The CGA / EGA / Tandy / Hercules / MCGA drivers in Vmcode.OVL follow
; the same shape with chunk-specific vtable offsets. The VGA chunk's
; specifics:
;   - vtable @ chunk:0x00F8 (vs 0x0200 in cga.asm).
;   - 50 slots (vs 50 in cga.asm; the slot count is the same across
;     all drivers; only the offsets vary).
;   - vga_unimplemented_slot @ chunk:0x020C (the 1-byte RETF that
;     stands in for every unimplemented slot).
; ----------------------------------------------------------------------------

; ----------------------------------------------------------------------------
; How to read this source
;
; - TASM Ideal-mode-ish style; HEX literals must start with a digit
;   (write 0AH not AH, since AH is a register). `H` suffix marks hex,
;   no suffix is decimal. ASCII numerics here uniformly use the H form.
; - Single-segment chunk (.MODEL TINY, .CODE). All globals live in
;   the code segment. Some globals overlap instruction bytes that
;   are only live during init (dual-use storage).
; - Memory accesses use one of three segments:
;     CS:  -- the chunk itself (vtable, callbacks, mask LUTs, globals
;             and per-function CS-relative scratch words). Read-write,
;             since the chunk has been copied into a private segment.
;     DS:  -- the chunk's "scratch DS", a private segment allocated
;             paragraph_count/16 paragraphs past the caller's DS at
;             vga_init step 2. Reloaded from cs:[0F4H] in most callers.
;             Holds the row LUT at 0x6F2 and various host-shared state.
;     ES:  -- usually A000 (planar VRAM) or one of the back-buffer
;             segments A400 / A800. Stored at scratch:[0x14] / [0x12] /
;             [0x10] and reloaded per-function.
;
; - Calling conventions vary slot-by-slot. Some functions take
;   __cdecl16far stack arguments; many take register arguments
;   (DX = signed x, CX = pixel count, DI = dst byte offset, etc.). The
;   per-function ABI is documented in each plate; do not assume any
;   single convention.
;
; - Several handlers use `XLAT BYTE PTR SS:[BX]` to do a translate
;   through a LUT whose offset lives in the chunk's scratch DS but
;   whose actual storage is reachable via SS. This works because of
;   Borland C++ 3.1's "-Ms / Assume SS equals DS" compiler convention
;   (the engine that loads this chunk was built large/medium model
;   with SS aliasing DS, so an offset usable as ds:[X] is equally
;   usable as ss:[X]). This is a CPU/COMPILER convention, NOT a VGA
;   hardware behaviour -- the VGA never sees x86 segment registers.
;
; - The 4-byte hex sequences in the right column are the encoded
;   instruction bytes.
;
; - Local labels inside a function are prefixed with a short nickname
;   for the enclosing function (e.g. `vga_dl_v_loop` for vertical-line
;   loop inside vga_draw_line). Avoids collisions and makes the
;   purpose visible at the label.
; ----------------------------------------------------------------------------

                .8086
                .MODEL  TINY
                .CODE
                ORG     0
                ASSUME  ds:NOTHING, es:NOTHING

; Shared engine graphics-context STRUC (field names for the
; host/scratch-DS struct this driver overlays by offset). A STRUC emits
; no bytes.
                INCLUDE gfxctx.inc

; ============================================================================
; vga_init -- chunk initialiser (PROC FAR, called via the host's video_init).
; chunk:0x0000..0x00F3
;
; CALLER ABI (host-side far call):
;   [BP+0x06]  ushort  backbuffer_paragraphs
;   [BP+0x08]  ushort  host_callbacks_off
;   [BP+0x0a]  ushort  host_callbacks_seg
;
; INIT SEQUENCE:
;   1. Copy 0x26 words (76 bytes = 19 far ptrs) from
;      DS:SI = host_callbacks_seg:host_callbacks_off into the chunk-
;      local mirror at CS:0x01C0 (g_apfnVgaHostCallbacks).
;   2. Save backbuffer_paragraphs to g_wVgaBackbufferParagraphs.
;      Compute scratch_DS = caller_DS + (paras / 16) and save it
;      into g_wVgaChunkDataSeg. ES = DS = scratch_DS thereafter.
;   3. ds:[0x21] := 0xFF (active-mode marker), increment ds:[0x1F]
;      (mode-change tick). Test ds:[0x6EC] (host-supplied mode-init
;      gate flag) -- if 0, skip mode-set and jump directly to the
;      back-buffer-segment allocation (already-initialised path).
;   4. INT 10h AX=0013h -- enter mode 13h (320x200x256 chunky).
;   5. Configure VGA registers for Mode-Y (matches Abrash GPBB ch.47;
;      register-bit citations from FreeVGA + IBM VGA/XGA TR May 1992):
;      a. Sequencer reg 4 (Memory Mode) := AND ~08h, OR 04h.
;         Clears bit 3 (Chain-4) -> Mode-Y's planar layout active.
;         Sets bit 2 (Odd/Even Disable = "Sequential addressing"
;         per IBM TR), so the CPU's A0 picks bytes within a plane
;         rather than alternating Even/Odd planes. Net SR4 value
;         after this read-modify-write is 06h (the canonical Mode-Y
;         value -- bit 1 "Extended Memory" was already 1 after mode
;         13h, leaving us with bits {1,2} set).
;      b. GC reg 6 (Miscellaneous) := AND ~02h. Clears bit 1
;         ("Chain Odd/Even" on CPU side, used for CGA emulation).
;      c. Sequencer reg 02h (Map Mask) := 0Fh -- enable writes to
;         all 4 planes for the upcoming bulk zero.
;      d. Zero 64 KiB at A000:0000 (REP STOSW CX=0x8000 AX=0).
;      e. CRTC reg 14h (Underline Location) := AND ~40h. Clears
;         bit 6 (DW = Double-Word addressing); must be 0 in Mode-X/Y
;         (in mode 13h it was 1, matching chain-4).
;      f. CRTC reg 17h (Mode Control) := OR 40h. Sets bit 6 (W/B =
;         Word/Byte mode) -> byte-mode addressing. In mode 13h this
;         was 0 (word mode) which paired with chain-4's dword-stepping
;         logic. Resulting CR17 value is E3h (= 1110 0011b).
;      g. GC reg 05h (Graphics Mode) := 40h. Bit 6 (Shift256) STAYS
;         set, ensuring the serializer still treats 4 planar bytes
;         as one 8-bit pixel; bits 0..1 (Write Mode) = 00, bit 3
;         (Read Mode) = 0. NOTE: the original "Mode-X / Mode-Y"
;         cookbooks (Abrash, Brackeen) all preserve Shift256;
;         clearing it would change how the screen rasters, even
;         though the CPU side is planar now. Then GC reg 0
;         (Set/Reset data) := 01h and GC reg 8 (Bit Mask) := FFh.
;   6. Set g_wVgaScratchPad14/12/10 := A000 / A400 / A800.
;   7. If ds:[0x6EC] == 0x190 (mode height = 400, large-screen path),
;      additional CRTC reg 9 mask + reposition pages 12/10 to A800.
;   8. Build a 200-row (or ds:[0x6EC] count) row-offset LUT at
;      scratch:[0x6F2]: row N -> N * 80. Each entry = 2 bytes.
;   9. AL := 8 (driver-installed flag), DX := CS, SI := 0x00F8
;      (offset of g_apfnVgaVtable). Pop, RETF.
;
; RETURN:
;   AL    -- 8 on success.
;   DX:SI -- CS:0x00F8, far pointer to g_apfnVgaVtable.
; ============================================================================
_start          LABEL   BYTE
vga_init        PROC    FAR
                PUSH    BP                      ; 55
                MOV     BP, SP                  ; 8B EC
                PUSH    DS                      ; 1E
                PUSH    SI                      ; 56
                PUSH    DI                      ; 57
                MOV     DI, 01C0H               ; BF C0 01  -- g_apfnVgaHostCallbacks
                PUSH    CS                      ; 0E
                POP     ES                      ; 07
                MOV     SI, [BP+8]              ; 8B 76 08  arg1.off (host_callbacks_off)
                MOV     DS, [BP+0AH]            ; 8E 5E 0A  arg1.seg (host_callbacks_seg)
                MOV     CX, 0026H               ; B9 26 00  38 words = 76 bytes
                REP     MOVSW                   ; F3 A5
                POP     DI                      ; 5F
                POP     SI                      ; 5E
                POP     DS                      ; 1F
                MOV     AX, [BP+6]              ; 8B 46 06  backbuffer_paragraphs
                MOV     cs:[0F6H], AX           ; 2E A3 F6 00  g_wVgaBackbufferParagraphs
                SHR     AX, 1                   ; D1 E8
                SHR     AX, 1                   ; D1 E8
                SHR     AX, 1                   ; D1 E8
                SHR     AX, 1                   ; D1 E8   AX /= 16
                PUSH    DS                      ; 1E
                PUSH    DI                      ; 57
                MOV     BX, DS                  ; 8C DB
                ADD     AX, BX                  ; 03 C3
                MOV     cs:[0F4H], AX           ; 2E A3 F4 00  g_wVgaChunkDataSeg
                MOV     DS, AX                  ; 8E D8
                MOV     ES, AX                  ; 8E C0
                MOV     BYTE PTR ds:[GfxContext.bActiveVgaMode], 0FFH ; C6 06 21 00 FF
                INC     BYTE PTR ds:[GfxContext.bGfxRenderStateFlag]       ; FE 06 1F 00

                CMP     BYTE PTR ds:[GfxContext.bVideoAutoDetectEnabled], 0  ; 80 3E B4 0A 00
                JZ      vga_init_alloc_segs     ; 74 5D

                ; --- Mode-Y register-level setup (Abrash GPBB ch.47) ---
                MOV     AX, 0013H               ; B8 13 00
                INT     10H                     ; CD 10        -- BIOS mode 13h (320x200x256)

                ; Sequencer reg 4 = Memory Mode: clear Chain-4, set
                ; sequential addressing. Mode-Y final value = 06h.
                MOV     DX, 03C4H               ; BA C4 03     -- Sequencer addr port
                MOV     AL, 4                   ; B0 04        -- reg 4 = Memory Mode
                OUT     DX, AL                  ; EE
                INC     DX                      ; 42           -- 3C5 = data
                IN      AL, DX                  ; EC
                AND     AL, 0F7H                ; 24 F7        -- clear bit 3 (Chain-4)
                OR      AL, 04H                 ; 0C 04        -- set  bit 2 (Odd/Even Disable)
                OUT     DX, AL                  ; EE

                ; GC reg 6 = Misc Graphics: clear "Chain Odd/Even"
                ; (bit 1) -- a CGA-emulation address-bit-swap that
                ; chain-4 mode left set. Memory-map bits stay at
                ; "A0000-AFFFF, 64 KiB window".
                MOV     DX, 03CEH               ; BA CE 03     -- GC addr port
                MOV     AL, 6                   ; B0 06        -- reg 6 = Misc Graphics
                OUT     DX, AL                  ; EE
                INC     DX                      ; 42
                IN      AL, DX                  ; EC
                AND     AL, 0FDH                ; 24 FD        -- clear bit 1 (Chain O/E)
                OUT     DX, AL                  ; EE

                MOV     DX, 03C4H               ; BA C4 03     -- Sequencer index
                MOV     AX, 0F02H               ; B8 02 0F     -- AL=reg 2 (Map Mask), AH=0Fh (all planes)
                OUT     DX, AX                  ; EF           -- 16-bit OUT writes reg+data in one shot

                MOV     AX, 0A000H              ; B8 00 A0     -- VRAM segment
                MOV     ES, AX                  ; 8E C0
                MOV     CX, 8000H               ; B9 00 80     -- 64 KiB / 2 = 32K words
                XOR     AX, AX                  ; 33 C0
                MOV     DI, AX                  ; 8B F8
                CLD                             ; FC
                REP     STOSW                   ; F3 AB        -- zero VRAM (all 4 planes)

                ; CRTC reg 14h = Underline Location: clear DW (bit 6).
                ; Then CRTC reg 17h = Mode Control: set W/B = Byte mode
                ; (bit 6). Together these undo mode-13h's chain-4-paired
                ; dword address stepping and switch the CRTC to a
                ; linear 80-byte-per-scanline planar address generator.
                MOV     DX, 03D4H               ; BA D4 03     -- CRTC addr port
                MOV     AL, 14H                 ; B0 14        -- reg 14h = Underline Location
                OUT     DX, AL                  ; EE
                INC     DX                      ; 42
                IN      AL, DX                  ; EC
                AND     AL, 0BFH                ; 24 BF        -- clear bit 6 (DW Double-Word)
                OUT     DX, AL                  ; EE
                DEC     DX                      ; 4A
                MOV     AL, 17H                 ; B0 17        -- reg 17h = Mode Control
                OUT     DX, AL                  ; EE
                INC     DX                      ; 42
                IN      AL, DX                  ; EC
                OR      AL, 40H                 ; 0C 40        -- set bit 6 (W/B = Byte mode)
                OUT     DX, AL                  ; EE

                ; GC reg 5 = Graphics Mode: write 40h. Bit 6 (Shift256)
                ; STAYS set so the serializer still packs 4 planar
                ; bytes -> 1 256-colour pixel; bits 0..1 (Write Mode)
                ; and bit 3 (Read Mode) are explicitly zeroed.
                MOV     DX, 03CEH               ; BA CE 03     -- GC addr port
                MOV     AL, 5                   ; B0 05        -- reg 5 = Graphics Mode
                OUT     DX, AL                  ; EE
                INC     DX                      ; 42
                MOV     AL, 40H                 ; B0 40        -- Shift256=1, WM=0, RM=0
                OUT     DX, AL                  ; EE
                ; GC reg 0 (Set/Reset) := 01h and GC reg 8 (Bit Mask)
                ; := FFh. These are defaults expected by later write-
                ; mode-0 paths.
                DEC     DX                      ; 4A
                MOV     AX, 0001H               ; B8 01 00     -- AL=reg 0 (Set/Reset), AH=01h
                OUT     DX, AX                  ; EF
                MOV     AL, 8                   ; B0 08        -- reg 8 = Bit Mask
                OUT     DX, AL                  ; EE
                INC     DX                      ; 42
                MOV     AL, 0FFH                ; B0 FF        -- bit mask = all bits writable
                OUT     DX, AL                  ; EE

vga_init_alloc_segs:
                MOV     AX, 0A000H              ; B8 00 A0
                MOV     ds:[GfxContext.wVgaFrontPageBase], AX            ; A3 14 00     -- page 2 base (A000)
                ADD     AX, 0400H               ; 05 00 04
                MOV     ds:[GfxContext.wVgaPage2Base], AX            ; A3 12 00     -- page 1 base (A400)
                ADD     AX, 0400H               ; 05 00 04
                MOV     ds:[GfxContext.wVgaPage1Base], AX            ; A3 10 00     -- page 0 base (A800)

                CMP     WORD PTR ds:[GfxContext.wScreen_height], 0190H ; 81 3E EC 06 90 01
                JNZ     SHORT vga_init_build_row_lut ; 75 15

                ; Large-screen (400-row) path: clear CRTC reg 9
                ; (Max Scan Line) lower 5 bits so each row is single-
                ; scanline, and collapse page 1/0 back to A800.
                MOV     DX, 03D4H               ; BA D4 03
                MOV     AL, 9                   ; B0 09
                OUT     DX, AL                  ; EE
                INC     DX                      ; 42
                IN      AL, DX                  ; EC
                AND     AL, 0E0H                ; 24 E0        -- clear bits 0..4 (1 line/row)
                OUT     DX, AL                  ; EE
                DEC     DX                      ; 4A
                MOV     AX, 0A800H              ; B8 00 A8
                MOV     ds:[GfxContext.wVgaPage2Base], AX            ; A3 12 00
                MOV     ds:[GfxContext.wVgaPage1Base], AX            ; A3 10 00

vga_init_build_row_lut:
                MOV     CX, ds:[GfxContext.wScreen_height]          ; 8B 0E EC 06  -- row count (200 or 400)
                MOV     DI, GfxContext.pRow_offset_lut ; BF F2 06  LUT base
                MOV     AX, DS                  ; 8C D8
                MOV     ES, AX                  ; 8E C0
                XOR     AX, AX                  ; 33 C0
                CLD                             ; FC
vga_init_row_loop:
                STOSW                           ; AB           -- row[k] = k * 80
                ADD     AX, 50H                 ; 05 50 00
                LOOP    SHORT vga_init_row_loop ; E2 FA

                MOV     AL, 8                   ; B0 08        -- driver-installed flag
                MOV     DX, CS                  ; 8C CA
                MOV     SI, 0F8H                ; BE F8 00     -- offset of g_apfnVgaVtable
                MOV     ds:[GfxContext.bVideoAdapter], AL            ; A2 1D 00
                POP     DI                      ; 5F
                POP     DS                      ; 1F
                POP     BP                      ; 5D
                RETF                            ; CB
vga_init        ENDP

; ============================================================================
; 0x00F4..0x00F7 -- chunk-local globals, zero-initialised on disk.
; Read/written via `CS:` overrides from vga_init.
; ============================================================================
g_wVgaChunkDataSeg              DW      0       ; 0x00F4
g_wVgaBackbufferParagraphs      DW      0       ; 0x00F6

; ============================================================================
; g_apfnVgaVtable -- 50-slot renderer-vtable template.
; chunk:0x00F8..0x01BF (200 bytes; 50 entries x 4)
;
; Snapshotted into host g_renderer_vtable @ 39ae:2ac6 after vga_init.
; Each entry: (offset_word, segment_placeholder_word). Host STOSWs
; the chunk's load segment into every segment half before publishing
; the vtable.
; ============================================================================
g_apfnVgaVtable LABEL DWORD
                DW      0,      0               ; slot 0  -- NULL
                DW      0FE8H,  0               ; slot 1  -- vga_blit_glyph_row
                DW      08C9H,  0               ; slot 2  -- vga_draw_line
                DW      0FCEH,  0               ; slot 3  -- vga_blit_sprite
                DW      1353H,  0               ; slot 4  -- vga_present
                DW      10DDH,  0               ; slot 5  -- vga_save_rect
                DW      11B1H,  0               ; slot 6  -- vga_blit_size
                DW      11BDH,  0               ; slot 7  -- vga_paste_rect
                DW      12FDH,  0               ; slot 8  -- vga_vsync_wait
                DW      020CH,  0               ; slot 9  -- vga_unimplemented_slot
                DW      02CFH,  0               ; slot 10 -- vga_fill_run_a
                DW      0223H,  0               ; slot 11 -- vga_fill_run_b
                DW      07C3H,  0               ; slot 12 -- vga_unimplemented_slot_12
                DW      0E4CH,  0               ; slot 13 -- vga_image_install
                DW      0E7FH,  0               ; slot 14 -- vga_image_decode
                DW      0F7AH,  0               ; slot 15 -- vga_unpack_nibbles_to_planes
                DW      07C2H,  0               ; slot 16 -- vga_unimplemented_slot_16
                DW      14BDH,  0               ; slot 17 -- vga_blit_chunky
                DW      156CH,  0               ; slot 18 -- vga_blit_chunky_planar_4bit
                DW      0684H,  0               ; slot 19 -- vga_fill_textured_span_modey_b
                DW      0D8CH,  0               ; slot 20 -- vga_palette_set
                DW      128FH,  0               ; slot 21 -- vga_getpixel
                DW      12C5H,  0               ; slot 22 -- vga_putpixel
                DW      13C3H,  0               ; slot 23 -- vga_blit_rect_buffer
                DW      14A2H,  0               ; slot 24 -- vga_set_buffer_offset
                DW      020CH,  0               ; slot 25 -- vga_unimplemented_slot
                DW      020CH,  0               ; slot 26 -- vga_unimplemented_slot
                DW      0AA8H,  0               ; slot 27 -- vga_fill_spans_dithered_modey
                DW      020CH,  0               ; slot 28 -- vga_unimplemented_slot
                DW      1662H,  0               ; slot 29 -- vga_blit_sprite_master
                DW      2231H,  0               ; slot 30 -- vga_blit_sprite_flip_h
                DW      22CCH,  0               ; slot 31 -- vga_blit_sprite_flip_v
                DW      2378H,  0               ; slot 32 -- vga_clear_rect_state
                DW      238DH,  0               ; slot 33 -- vga_blit_sprite_simple
                DW      0DCEH,  0               ; slot 34 -- vga_palette_lerp_dac
                DW      0D38H,  0               ; slot 35 -- vga_dac_write_palette
                DW      0352H,  0               ; slot 36 -- vga_blit_sprite_planar_rotated
                DW      05AEH,  0               ; slot 37 -- vga_blit_stretched
                DW      07C4H,  0               ; slot 38 -- vga_blit_sprite_chunky_flip
                DW      2734H,  0               ; slot 39 -- vga_fill_world_textured_span_modey
                DW      0452H,  0               ; slot 40 -- vga_fill_textured_span_modey
                DW      020CH,  0               ; slot 41 -- vga_unimplemented_slot
                DW      020CH,  0               ; slot 42 -- vga_unimplemented_slot
                DW      020CH,  0               ; slot 43 -- vga_unimplemented_slot
                DW      020CH,  0               ; slot 44 -- vga_unimplemented_slot
                DW      020CH,  0               ; slot 45 -- vga_unimplemented_slot
                DW      020CH,  0               ; slot 46 -- vga_unimplemented_slot
                DW      020CH,  0               ; slot 47 -- vga_unimplemented_slot
                DW      020CH,  0               ; slot 48 -- vga_unimplemented_slot
                DW      0,      0               ; slot 49 -- on-disk null (host fills at runtime)

; ============================================================================
; g_apfnVgaHostCallbacks -- 19-entry host-service-callback table.
; chunk:0x01C0..0x020B (76 bytes; 19 entries x 4)
;
; On disk every entry points to vga_unimplemented_slot @ 0x020C. At
; runtime the init prologue's REP MOVSW overwrites this region with
; the host-exported callback far pointers; the chunk then dispatches
; into the host as CALLF [0x01C0+N].
; ============================================================================
g_apfnVgaHostCallbacks LABEL DWORD
                DW      020CH,  0               ; #0
                DW      020CH,  0               ; #1
                DW      020CH,  0               ; #2
                DW      020CH,  0               ; #3
                DW      020CH,  0               ; #4
                DW      020CH,  0               ; #5
                DW      020CH,  0               ; #6
                DW      020CH,  0               ; #7
                DW      020CH,  0               ; #8
                DW      020CH,  0               ; #9
                DW      020CH,  0               ; #10
                DW      020CH,  0               ; #11
                DW      020CH,  0               ; #12
                DW      020CH,  0               ; #13
                DW      020CH,  0               ; #14
                DW      020CH,  0               ; #15
                DW      020CH,  0               ; #16
                DW      020CH,  0               ; #17
                DW      020CH,  0               ; #18

; ============================================================================
; vga_unimplemented_slot -- 1-byte RETF stub. chunk:0x020C.
; All vtable / callback slots that aren't implemented in this driver
; point here. Calling it has no effect (no args, no return value).
; ============================================================================
vga_unimplemented_slot PROC FAR
                RETF                            ; CB
vga_unimplemented_slot ENDP

; ============================================================================
; 0x020D..0x0222 -- in-line data tables.
;
; Six pad bytes, three 4-byte mask LUTs (left-edge / right-edge /
; single-byte spans), and four more pad bytes that lead into the
; vga_fill_run_b function body at 0x0223.
;
; The mask LUTs are indexed by (x & 3) to derive the Map Mask byte
; for partial-byte pixels at the start/end of a Mode-Y horizontal
; span. Used by vga_fill_run_a / vga_fill_run_b.
; ============================================================================
g_abVgaPad020D                  DB      0, 0, 0, 0, 0, 0        ; 0x020D pad

g_abVgaSpanLeftMaskLut          DB      0FH, 0EH, 0CH, 08H      ; 0x0213
g_abVgaSpanRightMaskLut         DB      0FH, 01H, 03H, 07H      ; 0x0217
g_abVgaSpanSingleByteMaskLut    DB      00H, 01H, 03H, 07H      ; 0x021B
g_abVgaPad021F                  DB      00H, 0ACH, 00H, 0CBH    ; 0x021F pad

; ============================================================================
; vga_fill_run_b -- horizontal pixel run draw via VGA Sequencer Map Mask.
; chunk:0x0223..0x02CE
;
; ENTRY ABI (register-based, no stack frame):
;   AL  -- low fill colour (used for left + middle bytes)
;   AH  -- high fill colour (used for right edge byte)
;   BX  -- starting pixel x-coordinate within current row
;   CX  -- pixel count (>0)
;   DX  -- "swap colours" flag in bit 0 (if set: XCHG AL,AH before
;          starting; effectively dither stripe selection)
;   DI  -- byte offset within current row (will be advanced)
;   ES  -- back-buffer segment (caller has set ES=g_wVgaScratchPad14)
;
; Two cases:
;   (a) Entire run lives within a single 4-pixel byte (the AND with
;       0xFFFC of x ^ (x+count-1) == 0): write one byte, set Map Mask
;       to the combined left+right edge mask, single STOSB.
;   (b) Run straddles >= 2 bytes: emit left-edge byte, REP STOSB
;       the middle full bytes (count>>2 of each fill), then right-edge
;       byte.
;
; The Map Mask register at port 3C4h reg 2 selects which of the 4
; Mode-Y planes the next CPU write hits. The split between AL and AH
; lets the function alternate plane sets for dithering (caller passes
; AL=odd-plane colour, AH=even-plane colour with port-5 / port-A
; halves).
;
; Plane mask conventions used here:
;   0x0A = planes 1+3 (odd planes)
;   0x05 = planes 0+2 (even planes)
;   0x0F = all four planes
; ============================================================================
vga_fill_run_b  PROC FAR
                AND     DX, 1                   ; 83 E2 01
                JZ      SHORT vga_frb_no_swap   ; 74 02
                XCHG    AL, AH                  ; 86 C4     -- swap colour halves (AL becomes high)
vga_frb_no_swap:
                MOV     DX, AX                  ; 8B D0     -- save (al_lo, ah_hi) to DX
                MOV     AX, BX                  ; 8B C3
                ADD     AX, CX                  ; 03 C1
                DEC     AX                      ; 48
                XOR     AX, BX                  ; 33 C3     -- x ^ (x+count-1)
                AND     AX, 0FFFCH              ; 25 FC FF  -- any high bits differ?
                JNZ     SHORT vga_frb_multibyte ; 75 36     -- yes: multi-byte path

                ; --- Single-byte case: run is entirely within one byte. ---
                MOV     AX, BX                  ; 8B C3
                SHR     AX, 1                   ; D1 E8
                SHR     AX, 1                   ; D1 E8     -- byte offset = x/4
                ADD     DI, AX                  ; 03 F8
                MOV     AX, BX                  ; 8B C3
                ADD     BX, CX                  ; 03 D9     -- BX = end x (one past)
                AND     AX, 3                   ; 25 03 00  -- AL = x & 3 (left edge mask index)
                AND     BX, 3                   ; 83 E3 03  -- BL = end & 3
                MOV     CL, AL                  ; 8A C8
                MOV     AX, 0FF02H              ; B8 02 FF  -- AL=02 (Sequencer reg 2), AH=FFh seed
                SHL     AH, CL                  ; D2 E4     -- AH = (FFh << (x&3)) = left-edge mask
                AND     AH, cs:[BX+0217H]       ; 2E 22 A7 17 02  -- combine with right-edge mask
                MOV     BX, DX                  ; 8B DA     -- BX = colour pair
                MOV     DX, 03C4H               ; BA C4 03
                OUT     DX, AL                  ; EE        -- write Sequencer index = 2
                INC     DX                      ; 42
                MOV     AL, 5                   ; B0 05
                AND     AL, AH                  ; 22 C4     -- even planes (0+2)
                OUT     DX, AL                  ; EE
                MOV     ES:[DI], BH             ; 26 88 3D  -- preload even half-colour
                MOV     AL, 0AH                 ; B0 0A
                AND     AL, AH                  ; 22 C4     -- odd planes (1+3)
                OUT     DX, AL                  ; EE
                MOV     AL, BL                  ; 8A C3
                STOSB                           ; AA        -- write odd half-colour
                RETF                            ; CB

vga_frb_multibyte:
                ; --- Multi-byte case: left-edge byte, middle, right-edge. ---
                MOV     AX, BX                  ; 8B C3
                SHR     AX, 1                   ; D1 E8
                SHR     AX, 1                   ; D1 E8     -- byte offset = x/4
                ADD     DI, AX                  ; 03 F8
                PUSH    DX                      ; 52        -- save colour pair
                MOV     AL, 2                   ; B0 02     -- Sequencer reg 2 = Map Mask
                MOV     DX, 03C4H               ; BA C4 03
                OUT     DX, AL                  ; EE
                INC     DX                      ; 42
                AND     BX, 3                   ; 83 E3 03  -- BX = x & 3 (left-edge index)
                SUB     CX, 4                   ; 83 E9 04  -- adjust count: -4 (will +(x&3)+(end&3))
                ADD     CX, BX                  ; 03 CB
                MOV     AL, cs:[BX+0213H]       ; 2E 8A 87 13 02  -- left-edge mask
                MOV     AH, AL                  ; 8A E0
                POP     BX                      ; 5B        -- BX = colour pair
                AND     AL, 0AH                 ; 24 0A     -- mask -> odd planes only
                OUT     DX, AL                  ; EE
                MOV     ES:[DI], BL             ; 26 88 1D  -- preload (latch read)
                MOV     AL, AH                  ; 8A C4
                AND     AL, 5                   ; 24 05     -- mask -> even planes only
                OUT     DX, AL                  ; EE
                MOV     AL, BH                  ; 8A C7
                STOSB                           ; AA        -- write left-edge byte
                MOV     AL, 0AH                 ; B0 0A     -- restore Map Mask to odd planes
                OUT     DX, AL                  ; EE

                ; Middle: count >> 2 = whole bytes, REP STOSB twice
                ; (once for odd planes, once for even planes).
                PUSH    CX                      ; 51
                SHR     CX, 1                   ; D1 E9
                SHR     CX, 1                   ; D1 E9     -- CX = full-byte run length
                MOV     AL, BL                  ; 8A C3
                PUSH    CX                      ; 51
                PUSH    DI                      ; 57
                REP     STOSB                   ; F3 AA     -- fill odd planes
                POP     DI                      ; 5F
                POP     CX                      ; 59
                MOV     AL, 5                   ; B0 05     -- Map Mask = even planes
                OUT     DX, AL                  ; EE
                MOV     AL, BH                  ; 8A C7
                REP     STOSB                   ; F3 AA     -- fill even planes
                MOV     CX, BX                  ; 8B CB     -- CX = colour pair (CH/CL)
                POP     BX                      ; 5B        -- BX = original CX (count)
                AND     BX, 3                   ; 83 E3 03  -- BX = end & 3
                MOV     AL, cs:[BX+021BH]       ; 2E 8A 87 1B 02  -- right-edge single-byte mask
                MOV     AH, AL                  ; 8A E0
                AND     AL, 0AH                 ; 24 0A
                OUT     DX, AL                  ; EE        -- odd planes mask
                MOV     ES:[DI], CL             ; 26 88 0D  -- preload byte
                MOV     AL, AH                  ; 8A C4
                AND     AL, 5                   ; 24 05
                OUT     DX, AL                  ; EE        -- even planes mask
                MOV     AL, CH                  ; 8A C5
                STOSB                           ; AA        -- write right-edge byte
vga_frb_exit_retf:                              ; vga_fill_run_a JLE-backwards target
                RETF                            ; CB
vga_fill_run_b  ENDP

; ============================================================================
; vga_fill_run_a -- solid-colour horizontal pixel run.
; chunk:0x02CF..0x0351
;
; ENTRY ABI (register-based):
;   AL  -- fill colour (entire run)
;   AH  -- 0 = solid fill (this routine), nonzero = dither dispatch
;          (tail-jump back to vga_fill_run_b at 0x0223 with the
;          colour pair AH:AL preserved)
;   BX  -- starting x
;   CX  -- pixel count (early-out if <=0)
;   DI  -- row byte offset
;   ES  -- back-buffer segment
;
; Solid case: same single-byte vs multi-byte split as vga_fill_run_b,
; except no plane-pair alternation -- Map Mask is written once with
; the combined edge mask (single-byte) or with 0Fh (all planes) for
; the middle REP STOSW/STOSB block, then with the right-edge mask.
; Uses 16-bit OUT DX,AX to write both the index and data byte in one
; instruction (port 3C4h takes index+data as a single word).
; ============================================================================
vga_fill_run_a  PROC FAR
                OR      CX, CX                  ; 0B C9
                JLE     SHORT vga_frb_exit_retf ; 7E FB     -- branch BACK 5 to 0x02CE's RETF
                OR      AH, AH                  ; 0A E4
                JZ      SHORT vga_fra_solid     ; 74 03
                JMP     vga_fill_run_b          ; E9 49 FF  -- dither: into _b at 0x0223

vga_fra_solid:
                MOV     AH, AL                  ; 8A E0     -- duplicate colour to AH
                MOV     DX, AX                  ; 8B D0     -- save colour pair
                MOV     AX, BX                  ; 8B C3
                ADD     AX, CX                  ; 03 C1
                DEC     AX                      ; 48
                XOR     AX, BX                  ; 33 C3
                AND     AX, 0FFFCH              ; 25 FC FF  -- any high bits differ?
                JNZ     SHORT vga_fra_multibyte ; 75 28

                ; Single-byte case.
                MOV     AX, BX                  ; 8B C3
                SHR     AX, 1                   ; D1 E8
                SHR     AX, 1                   ; D1 E8
                ADD     DI, AX                  ; 03 F8
                MOV     AX, BX                  ; 8B C3
                ADD     BX, CX                  ; 03 D9
                AND     AX, 3                   ; 25 03 00
                AND     BX, 3                   ; 83 E3 03
                MOV     CL, AL                  ; 8A C8
                MOV     AX, 0FF02H              ; B8 02 FF  -- AL=2, AH=FFh
                SHL     AH, CL                  ; D2 E4     -- AH = left-edge mask
                AND     AH, cs:[BX+0217H]       ; 2E 22 A7 17 02  -- combine right-edge
                MOV     BX, DX                  ; 8B DA     -- BX = colour pair
                MOV     DX, 03C4H               ; BA C4 03
                OUT     DX, AX                  ; EF        -- 16-bit OUT writes reg2 + mask
                MOV     AX, BX                  ; 8B C3
                STOSB                           ; AA
                RETF                            ; CB

vga_fra_multibyte:
                MOV     AX, BX                  ; 8B C3
                SHR     AX, 1                   ; D1 E8
                SHR     AX, 1                   ; D1 E8
                ADD     DI, AX                  ; 03 F8
                AND     BX, 3                   ; 83 E3 03
                SUB     CX, 4                   ; 83 E9 04
                ADD     CX, BX                  ; 03 CB
                MOV     AH, cs:[BX+0213H]       ; 2E 8A A7 13 02  -- left-edge mask -> AH
                MOV     AL, 2                   ; B0 02
                MOV     BX, DX                  ; 8B DA     -- BX = colour pair
                MOV     DX, 03C4H               ; BA C4 03
                OUT     DX, AX                  ; EF        -- Sequencer reg 2 := left mask
                INC     DX                      ; 42        -- 3C5 = Map Mask data port
                MOV     AX, BX                  ; 8B C3
                STOSB                           ; AA        -- write left-edge byte
                MOV     AL, 0FH                 ; B0 0F
                OUT     DX, AL                  ; EE        -- Map Mask = all planes
                MOV     AL, AH                  ; 8A C4
                MOV     BX, CX                  ; 8B D9     -- save count to BX
                SHR     CX, 1                   ; D1 E9
                SHR     CX, 1                   ; D1 E9
                SHR     CX, 1                   ; D1 E9     -- CX = (count >> 3) words... see JNC below
                JNC     SHORT vga_fra_word_run  ; 73 01     -- if was even, skip leading byte
                STOSB                           ; AA        -- write one byte (carry from last SHR)
vga_fra_word_run:
                REP     STOSW                   ; F3 AB     -- bulk middle (word-at-a-time)
                AND     BX, 3                   ; 83 E3 03
                MOV     AL, cs:[BX+021BH]       ; 2E 8A 87 1B 02  -- right-edge single-byte mask
                OUT     DX, AL                  ; EE
                MOV     AL, AH                  ; 8A C4
                STOSB                           ; AA        -- write right-edge
                RETF                            ; CB
vga_fill_run_a  ENDP

; ============================================================================
; ABOUT MODE-Y "SPAN PUMPS"
;
; The next four routines (vga_blit_sprite_planar_rotated,
; vga_fill_textured_span_modey, vga_blit_stretched,
; vga_fill_textured_span_modey_b) all share the same overall shape:
;
;   1. Clip the left edge if x < 0 (NEG / SUB CX, etc.).
;   2. Compute (x & 3) to choose the starting plane mask
;      (1 << (x & 3)); write the Sequencer Map Mask register.
;   3. Unroll the body 4x, one chunk per plane:
;        a. Emit (count/4)+1 pixels from this plane's lane.
;        b. SHL AH, 1 to rotate to the next plane mask. If it leaves
;           the 4-bit window (TEST AH, 0x0F == 0), wrap to plane 0
;           and INC DI to advance the destination byte. Then write
;           the new Map Mask via OUT DX, AL.
;   4. Per-pixel inner loop varies by function: some fetch a raw
;      source byte through a column-index table; some XLAT through
;      an SS-relative LUT; some take a fixed-stride chunky source.
;
; The reason for unrolling exactly 4 plane lanes is that every fourth
; destination byte covers all 4 Mode-Y planes (writing 4 pixels). By
; cycling plane masks externally and incrementing DI only on plane
; rollover, the per-pixel cost stays close to one STOSB + one branch.
;
; Most of these functions take essentially the same ABI:
;   DX = signed left x (negative => clip left)
;   CX = pixel count
;   DI = destination byte offset within current row
;   ES = back-buffer segment
;   __cdecl16far stack args at [BP+6]..[BP+0xA] supply the source far
;   ptr and the column-index table base.
; ============================================================================

; ============================================================================
; vga_blit_sprite_planar_rotated -- rotated sprite blit using Mode-Y plane
; cycling via a per-source-pixel column index table.
; chunk:0x0352..0x0451
;
; Vtable slot 36.
;
; ABI (__cdecl16far, register-based extras):
;   [BP+6]  far*  source pixel-table base (segment + offset live there)
;   [BP+8]  word  source-row base index (added to column offset)
;   [BP+10] word* near-pointer table of per-column source byte-offset words
;                (advanced by 8 bytes per source pixel during scanout)
;   CX = pixel count, DX = signed left-edge x (negative means clip left),
;   DI = destination byte offset within current row, ES = back-buffer seg.
;
; The function unrolls 4 plane iterations (one per Mode-Y plane). Each
; iteration:
;   1. Compute Sequencer reg 2 (Map Mask) value -- single-plane mask
;      shifted by (x & 3); on overflow into bit 4, reset to plane 0 and
;      advance the destination byte (DI++).
;   2. OUT 3C5 to publish the Map Mask.
;   3. Walk (count/4)+1 source pixels; each pixel reads through the column
;      index table to fetch its source byte, skips transparent (== 0), and
;      STOSBs the visible byte to ES:DI.
;   4. Decrement count, fall through to next plane until count exhausted.
; ============================================================================
vga_blit_sprite_planar_rotated PROC FAR
                PUSH    BP                      ; 55
                MOV     BP, SP                  ; 8B EC
                MOV     AX, DX                  ; 8B C2
                OR      AX, AX                  ; 0B C0
                JNS     SHORT vga_bspr_left_ok  ; 79 0D
                NEG     AX                      ; F7 D8
                SUB     CX, AX                  ; 2B C8
                JLE     SHORT vga_bspr_jmp_done ; 7E 58     -- nothing left after clip
                SHL     AX, 1                   ; D1 E0
                ADD     [BP+0AH], AX            ; 01 46 0A  -- skip clipped indexes
                XOR     AX, AX                  ; 33 C0
vga_bspr_left_ok:
                MOV     BX, AX                  ; 8B D8
                SHR     AX, 1                   ; D1 E8
                SHR     AX, 1                   ; D1 E8     -- AX = x / 4
                ADD     DI, AX                  ; 03 F8
                XCHG    CX, BX                  ; 87 CB     -- BX = count, CX = x
                AND     CX, 3                   ; 83 E1 03
                MOV     AX, 0102H               ; B8 02 01  -- AL=Sequencer reg 2, AH=plane-0 bit
                SHL     AH, CL                  ; D2 E4     -- AH = 1 << (x & 3)
                MOV     DX, 03C4H               ; BA C4 03
                OUT     DX, AX                  ; EF
                INC     DX                      ; 42        -- 3C5 = data port
                MOV     CX, BX                  ; 8B CB     -- CX = pixel count
                MOV     BX, [BP+8]              ; 8B 5E 08  -- source-row base index
                PUSH    [BP+0AH]                ; FF 76 0A  -- column index table off
                MOV     BP, [BP+6]              ; 8B 6E 06  -- &source far ptr
                MOV     DS, [BP+0]              ; 8E 5E 00
                ADD     BX, [BP+2]              ; 03 5E 02
                POP     BP                      ; 5D        -- BP = column index table
                ADD     CX, 3                   ; 83 C1 03

                ; --- Plane 0 ---
                PUSH    CX                      ; 51
                PUSH    BP                      ; 55
                PUSH    DI                      ; 57
                SHR     CX, 1                   ; D1 E9
                SHR     CX, 1                   ; D1 E9
                INC     CX                      ; 41
                DEC     DI                      ; 4F
vga_bspr_p0_top:
                DEC     CX                      ; 49
                JZ      SHORT vga_bspr_p0_end   ; 74 10
                INC     DI                      ; 47
vga_bspr_p0_body:
                MOV     SI, [BP+0]              ; 8B 76 00
                ADD     BP, 8                   ; 83 C5 08
                MOV     AL, [BX+SI]             ; 8A 00
                OR      AL, AL                  ; 0A C0
                JZ      SHORT vga_bspr_p0_top   ; 74 F0
                STOSB                           ; AA
                LOOP    SHORT vga_bspr_p0_body  ; E2 F1
vga_bspr_p0_end:
                POP     DI                      ; 5F
                POP     BP                      ; 5D
                POP     CX                      ; 59
                ADD     BP, 2                   ; 83 C5 02
                DEC     CX                      ; 49
                JNZ     SHORT vga_bspr_p1       ; 75 03
vga_bspr_jmp_done:
                JMP     vga_bspr_done           ; E9 90 00

                ; --- Plane 1 ---
vga_bspr_p1:
                SHL     AH, 1                   ; D0 E4
                TEST    AH, 0FH                 ; F6 C4 0F
                JNZ     SHORT vga_bspr_p1_mask  ; 75 03
                MOV     AH, 1                   ; B4 01
                INC     DI                      ; 47
vga_bspr_p1_mask:
                MOV     AL, AH                  ; 8A C4
                OUT     DX, AL                  ; EE
                PUSH    CX                      ; 51
                PUSH    BP                      ; 55
                PUSH    DI                      ; 57
                SHR     CX, 1                   ; D1 E9
                SHR     CX, 1                   ; D1 E9
                INC     CX                      ; 41
                DEC     DI                      ; 4F
vga_bspr_p1_top:
                DEC     CX                      ; 49
                JZ      SHORT vga_bspr_p1_end   ; 74 10
                INC     DI                      ; 47
vga_bspr_p1_body:
                MOV     SI, [BP+0]              ; 8B 76 00
                ADD     BP, 8                   ; 83 C5 08
                MOV     AL, [BX+SI]             ; 8A 00
                OR      AL, AL                  ; 0A C0
                JZ      SHORT vga_bspr_p1_top   ; 74 F0
                STOSB                           ; AA
                LOOP    SHORT vga_bspr_p1_body  ; E2 F1
vga_bspr_p1_end:
                POP     DI                      ; 5F
                POP     BP                      ; 5D
                POP     CX                      ; 59
                ADD     BP, 2                   ; 83 C5 02
                DEC     CX                      ; 49
                JZ      SHORT vga_bspr_done     ; 74 5E

                ; --- Plane 2 ---
                SHL     AH, 1                   ; D0 E4
                TEST    AH, 0FH                 ; F6 C4 0F
                JNZ     SHORT vga_bspr_p2_mask  ; 75 03
                MOV     AH, 1                   ; B4 01
                INC     DI                      ; 47
vga_bspr_p2_mask:
                MOV     AL, AH                  ; 8A C4
                OUT     DX, AL                  ; EE
                PUSH    CX                      ; 51
                PUSH    BP                      ; 55
                PUSH    DI                      ; 57
                SHR     CX, 1                   ; D1 E9
                SHR     CX, 1                   ; D1 E9
                INC     CX                      ; 41
                DEC     DI                      ; 4F
vga_bspr_p2_top:
                DEC     CX                      ; 49
                JZ      SHORT vga_bspr_p2_end   ; 74 10
                INC     DI                      ; 47
vga_bspr_p2_body:
                MOV     SI, [BP+0]              ; 8B 76 00
                ADD     BP, 8                   ; 83 C5 08
                MOV     AL, [BX+SI]             ; 8A 00
                OR      AL, AL                  ; 0A C0
                JZ      SHORT vga_bspr_p2_top   ; 74 F0
                STOSB                           ; AA
                LOOP    SHORT vga_bspr_p2_body  ; E2 F1
vga_bspr_p2_end:
                POP     DI                      ; 5F
                POP     BP                      ; 5D
                POP     CX                      ; 59
                ADD     BP, 2                   ; 83 C5 02
                DEC     CX                      ; 49
                JZ      SHORT vga_bspr_done     ; 74 2C

                ; --- Plane 3 ---
                SHL     AH, 1                   ; D0 E4
                TEST    AH, 0FH                 ; F6 C4 0F
                JNZ     SHORT vga_bspr_p3_mask  ; 75 03
                MOV     AH, 1                   ; B4 01
                INC     DI                      ; 47
vga_bspr_p3_mask:
                MOV     AL, AH                  ; 8A C4
                OUT     DX, AL                  ; EE
                PUSH    CX                      ; 51
                PUSH    BP                      ; 55
                PUSH    DI                      ; 57
                SHR     CX, 1                   ; D1 E9
                SHR     CX, 1                   ; D1 E9
                INC     CX                      ; 41
                DEC     DI                      ; 4F
vga_bspr_p3_top:
                DEC     CX                      ; 49
                JZ      SHORT vga_bspr_p3_end   ; 74 10
                INC     DI                      ; 47
vga_bspr_p3_body:
                MOV     SI, [BP+0]              ; 8B 76 00
                ADD     BP, 8                   ; 83 C5 08
                MOV     AL, [BX+SI]             ; 8A 00
                OR      AL, AL                  ; 0A C0
                JZ      SHORT vga_bspr_p3_top   ; 74 F0
                STOSB                           ; AA
                LOOP    SHORT vga_bspr_p3_body  ; E2 F1
vga_bspr_p3_end:
                ADD     SP, 6                   ; 83 C4 06  -- drop the 3 saved regs
vga_bspr_done:
                MOV     AX, SS                  ; 8C D0
                MOV     DS, AX                  ; 8E D8
                POP     BP                      ; 5D
                RETF                            ; CB
vga_blit_sprite_planar_rotated ENDP

; ============================================================================
; vga_fill_textured_span_modey -- textured horizontal span with per-pixel
; LUT translation. chunk:0x0452..0x05AD
;
; Vtable slot 40.
;
; Same 4-plane unrolled shape as vga_blit_sprite_planar_rotated, but the
; per-pixel inner core fetches a TEXTURE BYTE from the source (BX+SI off
; the caller-supplied far ptr), then translates it through a 256-byte
; LUT at scratch:[0x6BC] (chunk's DS, indirected via SS:BX after a
; segment-saver dance to get a SS-relative XLAT base).
;
; ABI: same as vga_blit_sprite_planar_rotated (DX=signed left x clip,
; CX=count, DI=dst byte offset, ES=back-buffer, [BP+6]=far src ptr,
; [BP+8]=row base, [BP+0xA]=column index table).
;
; The SS:XLAT trick lets the inner loop keep DS pointing at the SOURCE
; texture far segment (so [BX+SI] reads the raw texture byte) without
; reloading DS for the LUT translate. The setup at the top of each
; plane lane is:
;   MOV  SI, DS                ; stash source-seg
;   MOV  DS, cs:[0F4H]         ; DS := chunk scratch
;   MOV  BX, ds:[GfxContext.wTextureIdx]        ; BX := value stored at scratch:0x6BC
;   MOV  DS, SI                ; restore DS to source-seg
; The word at scratch:[0x6BC] is an SS-relative offset to the
; 256-byte translation LUT (the host engine writes that offset there
; at setup time; the LUT itself lives in the host data segment, which
; the caller has set up such that SS reaches it). XLAT BYTE PTR SS:[BX]
; then performs `AL := SS:[BX + AL]` in a single instruction, costing
; one byte of source rather than a full DS reload per pixel.
;
; (NOTE: the LUT-base word at scratch:0x6BC is treated as an SS offset
; by every call site below.)
; ============================================================================
vga_fill_textured_span_modey PROC FAR
                PUSH    BP                      ; 55
                MOV     BP, SP                  ; 8B EC
                MOV     AX, DX                  ; 8B C2
                OR      AX, AX                  ; 0B C0
                JNS     SHORT vga_ftsm_left_ok  ; 79 0D
                NEG     AX                      ; F7 D8
                SUB     CX, AX                  ; 2B C8
                JLE     SHORT vga_ftsm_jmp_done ; 7E 6F
                SHL     AX, 1                   ; D1 E0
                ADD     [BP+0AH], AX            ; 01 46 0A
                XOR     AX, AX                  ; 33 C0
vga_ftsm_left_ok:
                MOV     BX, AX                  ; 8B D8
                SHR     AX, 1                   ; D1 E8
                SHR     AX, 1                   ; D1 E8
                ADD     DI, AX                  ; 03 F8
                XCHG    CX, BX                  ; 87 CB
                AND     CX, 3                   ; 83 E1 03
                MOV     AX, 0102H               ; B8 02 01
                SHL     AH, CL                  ; D2 E4
                MOV     DX, 03C4H               ; BA C4 03
                OUT     DX, AX                  ; EF
                INC     DX                      ; 42
                MOV     CX, BX                  ; 8B CB
                MOV     BX, [BP+8]              ; 8B 5E 08
                PUSH    [BP+0AH]                ; FF 76 0A
                MOV     BP, [BP+6]              ; 8B 6E 06
                MOV     DS, [BP+0]              ; 8E 5E 00
                ADD     BX, [BP+2]              ; 03 5E 02
                POP     BP                      ; 5D
                ADD     CX, 3                   ; 83 C1 03

                ; --- Plane 0 ---
                PUSH    CX                      ; 51
                PUSH    BP                      ; 55
                PUSH    DI                      ; 57
                PUSH    DX                      ; 52
                MOV     DX, BX                  ; 8B D3     -- save source-row base in DX
                MOV     SI, DS                  ; 8C DE
                MOV     DS, cs:[0F4H]           ; 2E 8E 1E F4 00  -- DS = chunk scratch
                MOV     BX, ds:[GfxContext.wTextureIdx]          ; 8B 1E BC 06  -- BX = LUT base @ scratch:0x6BC
                MOV     DS, SI                  ; 8E DE     -- restore DS = source far seg
                SHR     CX, 1                   ; D1 E9
                SHR     CX, 1                   ; D1 E9
                INC     CX                      ; 41
                DEC     DI                      ; 4F
vga_ftsm_p0_top:
                DEC     CX                      ; 49
                JZ      SHORT vga_ftsm_p0_end   ; 74 14
                INC     DI                      ; 47
vga_ftsm_p0_body:
                MOV     SI, [BP+0]              ; 8B 76 00
                ADD     BP, 8                   ; 83 C5 08
                ADD     SI, DX                  ; 03 F2
                MOV     AL, [SI]                ; 8A 04
                XLAT    BYTE PTR SS:[BX]        ; 36 D7  -- AL := SS:[BX + AL] (LUT translate)
                OR      AL, AL                  ; 0A C0
                JZ      SHORT vga_ftsm_p0_top   ; 74 EC
                STOSB                           ; AA
                LOOP    SHORT vga_ftsm_p0_body  ; E2 ED
vga_ftsm_p0_end:
                MOV     BX, DX                  ; 8B DA     -- restore BX = row base
                POP     DX                      ; 5A
                POP     DI                      ; 5F
                POP     BP                      ; 5D
                POP     CX                      ; 59
                ADD     BP, 2                   ; 83 C5 02
                DEC     CX                      ; 49
                JNZ     SHORT vga_ftsm_p1       ; 75 03
vga_ftsm_jmp_done:
                JMP     vga_ftsm_done           ; E9 D5 00

                ; --- Plane 1 ---
vga_ftsm_p1:
                SHL     AH, 1                   ; D0 E4
                TEST    AH, 0FH                 ; F6 C4 0F
                JNZ     SHORT vga_ftsm_p1_mask  ; 75 03
                MOV     AH, 1                   ; B4 01
                INC     DI                      ; 47
vga_ftsm_p1_mask:
                MOV     AL, AH                  ; 8A C4
                OUT     DX, AL                  ; EE
                PUSH    CX                      ; 51
                PUSH    BP                      ; 55
                PUSH    DI                      ; 57
                PUSH    DX                      ; 52
                MOV     DX, BX                  ; 8B D3
                MOV     SI, DS                  ; 8C DE
                MOV     DS, cs:[0F4H]           ; 2E 8E 1E F4 00
                MOV     BX, ds:[GfxContext.wTextureIdx]          ; 8B 1E BC 06
                MOV     DS, SI                  ; 8E DE
                SHR     CX, 1                   ; D1 E9
                SHR     CX, 1                   ; D1 E9
                INC     CX                      ; 41
                DEC     DI                      ; 4F
vga_ftsm_p1_top:
                DEC     CX                      ; 49
                JZ      SHORT vga_ftsm_p1_end   ; 74 14
                INC     DI                      ; 47
vga_ftsm_p1_body:
                MOV     SI, [BP+0]              ; 8B 76 00
                ADD     BP, 8                   ; 83 C5 08
                ADD     SI, DX                  ; 03 F2
                MOV     AL, [SI]                ; 8A 04
                XLAT    BYTE PTR SS:[BX]        ; 36 D7
                OR      AL, AL                  ; 0A C0
                JZ      SHORT vga_ftsm_p1_top   ; 74 EC
                STOSB                           ; AA
                LOOP    SHORT vga_ftsm_p1_body  ; E2 ED
vga_ftsm_p1_end:
                MOV     BX, DX                  ; 8B DA
                POP     DX                      ; 5A
                POP     DI                      ; 5F
                POP     BP                      ; 5D
                POP     CX                      ; 59
                ADD     BP, 2                   ; 83 C5 02
                DEC     CX                      ; 49
                JZ      SHORT vga_ftsm_jmp_done ; 74 B4

                ; --- Plane 2 ---
                SHL     AH, 1                   ; D0 E4
                TEST    AH, 0FH                 ; F6 C4 0F
                JNZ     SHORT vga_ftsm_p2_mask  ; 75 03
                MOV     AH, 1                   ; B4 01
                INC     DI                      ; 47
vga_ftsm_p2_mask:
                MOV     AL, AH                  ; 8A C4
                OUT     DX, AL                  ; EE
                PUSH    CX                      ; 51
                PUSH    BP                      ; 55
                PUSH    DI                      ; 57
                PUSH    DX                      ; 52
                MOV     DX, BX                  ; 8B D3
                MOV     SI, DS                  ; 8C DE
                MOV     DS, cs:[0F4H]           ; 2E 8E 1E F4 00
                MOV     BX, ds:[GfxContext.wTextureIdx]          ; 8B 1E BC 06
                MOV     DS, SI                  ; 8E DE
                SHR     CX, 1                   ; D1 E9
                SHR     CX, 1                   ; D1 E9
                INC     CX                      ; 41
                DEC     DI                      ; 4F
vga_ftsm_p2_top:
                DEC     CX                      ; 49
                JZ      SHORT vga_ftsm_p2_end   ; 74 14
                INC     DI                      ; 47
vga_ftsm_p2_body:
                MOV     SI, [BP+0]              ; 8B 76 00
                ADD     BP, 8                   ; 83 C5 08
                ADD     SI, DX                  ; 03 F2
                MOV     AL, [SI]                ; 8A 04
                XLAT    BYTE PTR SS:[BX]        ; 36 D7
                OR      AL, AL                  ; 0A C0
                JZ      SHORT vga_ftsm_p2_top   ; 74 EC
                STOSB                           ; AA
                LOOP    SHORT vga_ftsm_p2_body  ; E2 ED
vga_ftsm_p2_end:
                MOV     BX, DX                  ; 8B DA
                POP     DX                      ; 5A
                POP     DI                      ; 5F
                POP     BP                      ; 5D
                POP     CX                      ; 59
                ADD     BP, 2                   ; 83 C5 02
                DEC     CX                      ; 49
                JZ      SHORT vga_ftsm_done     ; 74 43

                ; --- Plane 3 ---
                SHL     AH, 1                   ; D0 E4
                TEST    AH, 0FH                 ; F6 C4 0F
                JNZ     SHORT vga_ftsm_p3_mask  ; 75 03
                MOV     AH, 1                   ; B4 01
                INC     DI                      ; 47
vga_ftsm_p3_mask:
                MOV     AL, AH                  ; 8A C4
                OUT     DX, AL                  ; EE
                PUSH    CX                      ; 51
                PUSH    BP                      ; 55
                PUSH    DI                      ; 57
                PUSH    DX                      ; 52
                MOV     DX, BX                  ; 8B D3
                MOV     SI, DS                  ; 8C DE
                MOV     DS, cs:[0F4H]           ; 2E 8E 1E F4 00
                MOV     BX, ds:[GfxContext.wTextureIdx]          ; 8B 1E BC 06
                MOV     DS, SI                  ; 8E DE
                SHR     CX, 1                   ; D1 E9
                SHR     CX, 1                   ; D1 E9
                INC     CX                      ; 41
                DEC     DI                      ; 4F
vga_ftsm_p3_top:
                DEC     CX                      ; 49
                JZ      SHORT vga_ftsm_p3_end   ; 74 14
                INC     DI                      ; 47
vga_ftsm_p3_body:
                MOV     SI, [BP+0]              ; 8B 76 00
                ADD     BP, 8                   ; 83 C5 08
                ADD     SI, DX                  ; 03 F2
                MOV     AL, [SI]                ; 8A 04
                XLAT    BYTE PTR SS:[BX]        ; 36 D7
                OR      AL, AL                  ; 0A C0
                JZ      SHORT vga_ftsm_p3_top   ; 74 EC
                STOSB                           ; AA
                LOOP    SHORT vga_ftsm_p3_body  ; E2 ED
vga_ftsm_p3_end:
                MOV     BX, DX                  ; 8B DA
                POP     DX                      ; 5A
                ADD     SP, 6                   ; 83 C4 06
vga_ftsm_done:
                MOV     AX, SS                  ; 8C D0
                MOV     DS, AX                  ; 8E D8
                POP     BP                      ; 5D
                RETF                            ; CB
vga_fill_textured_span_modey ENDP

; ============================================================================
; vga_blit_stretched -- horizontal-stretched sprite blit (4-plane).
; chunk:0x05AE..0x0683
;
; Vtable slot 37.
;
; This variant takes a different ABI: caller sets up DS=source, SI=source
; row base, ES=back-buffer, DI=dest byte, BP=column index table base,
; CX=pixel count, DX=signed left x. The loop walks the BP table with an
; 8-byte stride (BP+0..BP+6 are 4 column offsets at 2 bytes each, packed
; for a 4x-zoom horizontal stretch).
;
; Algorithm per plane:
;   PUSH SI/DI/BP/CX, decrement-then-increment DI, walk CX/4 pixels (CX
;   reduces by 4 per pixel), fetch byte from [BX+SI] via column offset,
;   skip transparent. SHL AH plane mask on plane change with rollover to
;   plane 0 (and DI++) when bits leave the 4-plane window.
; ============================================================================
vga_blit_stretched PROC FAR
                ADD     CX, 4                   ; 83 C1 04
                PUSH    CX                      ; 51
                MOV     BX, DX                  ; 8B DA
                MOV     DX, 03C4H               ; BA C4 03
                MOV     AL, 2                   ; B0 02
                MOV     AH, 1                   ; B4 01
                MOV     CL, BL                  ; 8A CB
                AND     CL, 3                   ; 80 E1 03
                SHL     AH, CL                  ; D2 E4
                OUT     DX, AX                  ; EF
                INC     DX                      ; 42
                SHR     BX, 1                   ; D1 EB
                SHR     BX, 1                   ; D1 EB
                ADD     DI, BX                  ; 03 FB
                POP     CX                      ; 59

                ; --- Plane 0 ---
                PUSH    SI                      ; 56
                PUSH    DI                      ; 57
                PUSH    BP                      ; 55
                PUSH    CX                      ; 51
                DEC     DI                      ; 4F
vga_bstr_p0_top:
                INC     DI                      ; 47
                SUB     CX, 4                   ; 83 E9 04
                JLE     SHORT vga_bstr_p0_end   ; 7E 12
vga_bstr_p0_body:
                MOV     BX, [BP+0]              ; 8B 5E 00
                ADD     BP, 8                   ; 83 C5 08
                MOV     AL, [BX+SI]             ; 8A 00
                OR      AL, AL                  ; 0A C0
                JZ      SHORT vga_bstr_p0_top   ; 74 EE
                STOSB                           ; AA
                SUB     CX, 4                   ; 83 E9 04
                JA      SHORT vga_bstr_p0_body  ; 77 EE
vga_bstr_p0_end:
                POP     CX                      ; 59
                POP     BP                      ; 5D
                POP     DI                      ; 5F
                POP     SI                      ; 5E
                DEC     CX                      ; 49

                ; --- Plane 1 ---
                SHL     AH, 1                   ; D0 E4
                TEST    AH, 0FH                 ; F6 C4 0F
                JNZ     SHORT vga_bstr_p1_mask  ; 75 03
                MOV     AH, 1                   ; B4 01
                INC     DI                      ; 47
vga_bstr_p1_mask:
                MOV     AL, AH                  ; 8A C4
                OUT     DX, AL                  ; EE
                ADD     BP, 2                   ; 83 C5 02
                PUSH    SI                      ; 56
                PUSH    DI                      ; 57
                PUSH    BP                      ; 55
                PUSH    CX                      ; 51
                DEC     DI                      ; 4F
vga_bstr_p1_top:
                INC     DI                      ; 47
                SUB     CX, 4                   ; 83 E9 04
                JLE     SHORT vga_bstr_p1_end   ; 7E 12
vga_bstr_p1_body:
                MOV     BX, [BP+0]              ; 8B 5E 00
                ADD     BP, 8                   ; 83 C5 08
                MOV     AL, [BX+SI]             ; 8A 00
                OR      AL, AL                  ; 0A C0
                JZ      SHORT vga_bstr_p1_top   ; 74 EE
                STOSB                           ; AA
                SUB     CX, 4                   ; 83 E9 04
                JA      SHORT vga_bstr_p1_body  ; 77 EE
vga_bstr_p1_end:
                POP     CX                      ; 59
                POP     BP                      ; 5D
                POP     DI                      ; 5F
                POP     SI                      ; 5E
                DEC     CX                      ; 49

                ; --- Plane 2 ---
                SHL     AH, 1                   ; D0 E4
                TEST    AH, 0FH                 ; F6 C4 0F
                JNZ     SHORT vga_bstr_p2_mask  ; 75 03
                MOV     AH, 1                   ; B4 01
                INC     DI                      ; 47
vga_bstr_p2_mask:
                MOV     AL, AH                  ; 8A C4
                OUT     DX, AL                  ; EE
                ADD     BP, 2                   ; 83 C5 02
                PUSH    SI                      ; 56
                PUSH    DI                      ; 57
                PUSH    BP                      ; 55
                PUSH    CX                      ; 51
                DEC     DI                      ; 4F
vga_bstr_p2_top:
                INC     DI                      ; 47
                SUB     CX, 4                   ; 83 E9 04
                JLE     SHORT vga_bstr_p2_end   ; 7E 12
vga_bstr_p2_body:
                MOV     BX, [BP+0]              ; 8B 5E 00
                ADD     BP, 8                   ; 83 C5 08
                MOV     AL, [BX+SI]             ; 8A 00
                OR      AL, AL                  ; 0A C0
                JZ      SHORT vga_bstr_p2_top   ; 74 EE
                STOSB                           ; AA
                SUB     CX, 4                   ; 83 E9 04
                JA      SHORT vga_bstr_p2_body  ; 77 EE
vga_bstr_p2_end:
                POP     CX                      ; 59
                POP     BP                      ; 5D
                POP     DI                      ; 5F
                POP     SI                      ; 5E
                DEC     CX                      ; 49

                ; --- Plane 3 ---
                SHL     AH, 1                   ; D0 E4
                TEST    AH, 0FH                 ; F6 C4 0F
                JNZ     SHORT vga_bstr_p3_mask  ; 75 03
                MOV     AH, 1                   ; B4 01
                INC     DI                      ; 47
vga_bstr_p3_mask:
                MOV     AL, AH                  ; 8A C4
                OUT     DX, AL                  ; EE
                ADD     BP, 2                   ; 83 C5 02
                PUSH    SI                      ; 56
                PUSH    DI                      ; 57
                PUSH    BP                      ; 55
                PUSH    CX                      ; 51
                DEC     DI                      ; 4F
vga_bstr_p3_top:
                INC     DI                      ; 47
                SUB     CX, 4                   ; 83 E9 04
                JLE     SHORT vga_bstr_p3_end   ; 7E 12
vga_bstr_p3_body:
                MOV     BX, [BP+0]              ; 8B 5E 00
                ADD     BP, 8                   ; 83 C5 08
                MOV     AL, [BX+SI]             ; 8A 00
                OR      AL, AL                  ; 0A C0
                JZ      SHORT vga_bstr_p3_top   ; 74 EE
                STOSB                           ; AA
                SUB     CX, 4                   ; 83 E9 04
                JA      SHORT vga_bstr_p3_body  ; 77 EE
vga_bstr_p3_end:
                POP     CX                      ; 59
                POP     BP                      ; 5D
                POP     DI                      ; 5F
                POP     SI                      ; 5E
                DEC     CX                      ; 49
                RETF                            ; CB
vga_blit_stretched ENDP

; ============================================================================
; vga_fill_textured_span_modey_b -- alternate textured span variant.
; chunk:0x0684..0x07C1
;
; Vtable slot 19.
;
; Similar to vga_fill_textured_span_modey but counts down via AH instead
; of CX, and reloads the LUT base per-plane into CX (saved across the
; pixel loop) instead of BX. The XLAT SS:[BX] dance uses BX as scratch
; for the LUT pointer right before each XLAT.
;
; ABI: DX=signed left x, CX=pixel count, DI=dest byte, ES=back-buffer,
; DS:SI=source far ptr, BP=column index table.
; ============================================================================
vga_fill_textured_span_modey_b PROC FAR
                ADD     CX, 3                   ; 83 C1 03
                PUSH    CX                      ; 51
                MOV     BX, DX                  ; 8B DA
                MOV     DX, 03C4H               ; BA C4 03
                MOV     AL, 2                   ; B0 02
                MOV     AH, 1                   ; B4 01
                MOV     CL, BL                  ; 8A CB
                AND     CL, 3                   ; 80 E1 03
                SHL     AH, CL                  ; D2 E4
                OUT     DX, AX                  ; EF
                INC     DX                      ; 42
                SHR     BX, 1                   ; D1 EB
                SHR     BX, 1                   ; D1 EB
                ADD     DI, BX                  ; 03 FB
                POP     CX                      ; 59

                ; --- Plane 0 ---
                PUSH    SI                      ; 56
                PUSH    DI                      ; 57
                PUSH    BP                      ; 55
                PUSH    CX                      ; 51
                PUSH    AX                      ; 50
                ADD     CX, 3                   ; 83 C1 03
                SHR     CX, 1                   ; D1 E9
                SHR     CX, 1                   ; D1 E9
                MOV     AH, CL                  ; 8A E1
                MOV     BX, DS                  ; 8C DB
                MOV     DS, cs:[0F4H]           ; 2E 8E 1E F4 00
                MOV     CX, ds:[GfxContext.wTextureIdx]          ; 8B 0E BC 06
                MOV     DS, BX                  ; 8E DB
                DEC     DI                      ; 4F
vga_ftsb_p0_top:
                INC     DI                      ; 47
                DEC     AH                      ; FE CC
                JLE     SHORT vga_ftsb_p0_end   ; 7E 15
vga_ftsb_p0_body:
                MOV     BX, [BP+0]              ; 8B 5E 00
                ADD     BP, 8                   ; 83 C5 08
                MOV     AL, [BX+SI]             ; 8A 00
                OR      AL, AL                  ; 0A C0
                JZ      SHORT vga_ftsb_p0_top   ; 74 EF
                MOV     BX, CX                  ; 8B D9
                XLAT    BYTE PTR SS:[BX]        ; 36 D7
                STOSB                           ; AA
                DEC     AH                      ; FE CC
                JA      SHORT vga_ftsb_p0_body  ; 77 ED
vga_ftsb_p0_end:
                POP     AX                      ; 58
                POP     CX                      ; 59
                POP     BP                      ; 5D
                POP     DI                      ; 5F
                POP     SI                      ; 5E
                DEC     CX                      ; 49

                ; --- Plane 1 ---
                SHL     AH, 1                   ; D0 E4
                TEST    AH, 0FH                 ; F6 C4 0F
                JNZ     SHORT vga_ftsb_p1_mask  ; 75 03
                MOV     AH, 1                   ; B4 01
                INC     DI                      ; 47
vga_ftsb_p1_mask:
                MOV     AL, AH                  ; 8A C4
                OUT     DX, AL                  ; EE
                ADD     BP, 2                   ; 83 C5 02
                PUSH    SI                      ; 56
                PUSH    DI                      ; 57
                PUSH    BP                      ; 55
                PUSH    CX                      ; 51
                PUSH    AX                      ; 50
                ADD     CX, 3                   ; 83 C1 03
                SHR     CX, 1                   ; D1 E9
                SHR     CX, 1                   ; D1 E9
                MOV     AH, CL                  ; 8A E1
                MOV     BX, DS                  ; 8C DB
                MOV     DS, cs:[0F4H]           ; 2E 8E 1E F4 00
                MOV     CX, ds:[GfxContext.wTextureIdx]          ; 8B 0E BC 06
                MOV     DS, BX                  ; 8E DB
                DEC     DI                      ; 4F
vga_ftsb_p1_top:
                INC     DI                      ; 47
                DEC     AH                      ; FE CC
                JLE     SHORT vga_ftsb_p1_end   ; 7E 15
vga_ftsb_p1_body:
                MOV     BX, [BP+0]              ; 8B 5E 00
                ADD     BP, 8                   ; 83 C5 08
                MOV     AL, [BX+SI]             ; 8A 00
                OR      AL, AL                  ; 0A C0
                JZ      SHORT vga_ftsb_p1_top   ; 74 EF
                MOV     BX, CX                  ; 8B D9
                XLAT    BYTE PTR SS:[BX]        ; 36 D7
                STOSB                           ; AA
                DEC     AH                      ; FE CC
                JA      SHORT vga_ftsb_p1_body  ; 77 ED
vga_ftsb_p1_end:
                POP     AX                      ; 58
                POP     CX                      ; 59
                POP     BP                      ; 5D
                POP     DI                      ; 5F
                POP     SI                      ; 5E
                DEC     CX                      ; 49

                ; --- Plane 2 ---
                SHL     AH, 1                   ; D0 E4
                TEST    AH, 0FH                 ; F6 C4 0F
                JNZ     SHORT vga_ftsb_p2_mask  ; 75 03
                MOV     AH, 1                   ; B4 01
                INC     DI                      ; 47
vga_ftsb_p2_mask:
                MOV     AL, AH                  ; 8A C4
                OUT     DX, AL                  ; EE
                ADD     BP, 2                   ; 83 C5 02
                PUSH    SI                      ; 56
                PUSH    DI                      ; 57
                PUSH    BP                      ; 55
                PUSH    CX                      ; 51
                PUSH    AX                      ; 50
                ADD     CX, 3                   ; 83 C1 03
                SHR     CX, 1                   ; D1 E9
                SHR     CX, 1                   ; D1 E9
                MOV     AH, CL                  ; 8A E1
                MOV     BX, DS                  ; 8C DB
                MOV     DS, cs:[0F4H]           ; 2E 8E 1E F4 00
                MOV     CX, ds:[GfxContext.wTextureIdx]          ; 8B 0E BC 06
                MOV     DS, BX                  ; 8E DB
                DEC     DI                      ; 4F
vga_ftsb_p2_top:
                INC     DI                      ; 47
                DEC     AH                      ; FE CC
                JLE     SHORT vga_ftsb_p2_end   ; 7E 15
vga_ftsb_p2_body:
                MOV     BX, [BP+0]              ; 8B 5E 00
                ADD     BP, 8                   ; 83 C5 08
                MOV     AL, [BX+SI]             ; 8A 00
                OR      AL, AL                  ; 0A C0
                JZ      SHORT vga_ftsb_p2_top   ; 74 EF
                MOV     BX, CX                  ; 8B D9
                XLAT    BYTE PTR SS:[BX]        ; 36 D7
                STOSB                           ; AA
                DEC     AH                      ; FE CC
                JA      SHORT vga_ftsb_p2_body  ; 77 ED
vga_ftsb_p2_end:
                POP     AX                      ; 58
                POP     CX                      ; 59
                POP     BP                      ; 5D
                POP     DI                      ; 5F
                POP     SI                      ; 5E
                DEC     CX                      ; 49

                ; --- Plane 3 ---
                SHL     AH, 1                   ; D0 E4
                TEST    AH, 0FH                 ; F6 C4 0F
                JNZ     SHORT vga_ftsb_p3_mask  ; 75 03
                MOV     AH, 1                   ; B4 01
                INC     DI                      ; 47
vga_ftsb_p3_mask:
                MOV     AL, AH                  ; 8A C4
                OUT     DX, AL                  ; EE
                ADD     BP, 2                   ; 83 C5 02
                PUSH    SI                      ; 56
                PUSH    DI                      ; 57
                PUSH    BP                      ; 55
                PUSH    CX                      ; 51
                PUSH    AX                      ; 50
                ADD     CX, 3                   ; 83 C1 03
                SHR     CX, 1                   ; D1 E9
                SHR     CX, 1                   ; D1 E9
                MOV     AH, CL                  ; 8A E1
                MOV     BX, DS                  ; 8C DB
                MOV     DS, cs:[0F4H]           ; 2E 8E 1E F4 00
                MOV     CX, ds:[GfxContext.wTextureIdx]          ; 8B 0E BC 06
                MOV     DS, BX                  ; 8E DB
                DEC     DI                      ; 4F
vga_ftsb_p3_top:
                INC     DI                      ; 47
                DEC     AH                      ; FE CC
                JLE     SHORT vga_ftsb_p3_end   ; 7E 15
vga_ftsb_p3_body:
                MOV     BX, [BP+0]              ; 8B 5E 00
                ADD     BP, 8                   ; 83 C5 08
                MOV     AL, [BX+SI]             ; 8A 00
                OR      AL, AL                  ; 0A C0
                JZ      SHORT vga_ftsb_p3_top   ; 74 EF
                MOV     BX, CX                  ; 8B D9
                XLAT    BYTE PTR SS:[BX]        ; 36 D7
                STOSB                           ; AA
                DEC     AH                      ; FE CC
                JA      SHORT vga_ftsb_p3_body  ; 77 ED
vga_ftsb_p3_end:
                POP     AX                      ; 58
                POP     CX                      ; 59
                POP     BP                      ; 5D
                POP     DI                      ; 5F
                POP     SI                      ; 5E
                DEC     CX                      ; 49
                RETF                            ; CB
vga_fill_textured_span_modey_b ENDP

; ============================================================================
; vga_unimplemented_slot_16 -- 1-byte RETF stub. chunk:0x07C2.
; vga_unimplemented_slot_12 -- 1-byte RETF stub. chunk:0x07C3.
;
; Two extra stubs that some vtable slots target instead of the canonical
; vga_unimplemented_slot @ 0x020C. Identical behaviour (no-op far return).
; The duplicates exist because the slot offsets are baked in as constants.
; ============================================================================
vga_unimplemented_slot_16 PROC FAR
                RETF                            ; CB
vga_unimplemented_slot_16 ENDP

vga_unimplemented_slot_12 PROC FAR
                RETF                            ; CB
vga_unimplemented_slot_12 ENDP

; ============================================================================
; vga_blit_sprite_chunky_flip -- chunky-source-to-planar blit with
; optional horizontal flip selected by the CARRY FLAG on entry.
; chunk:0x07C4..0x08C4
;
; Vtable slot 38.
;
; ABI (register-based, no stack frame):
;   AL/AH not used at entry; this is a CF-dispatched blit.
;   BX = starting pixel x, CX = pixel count, DX = (saved) total width,
;   DI = dst byte offset, SI = chunky source byte ptr, ES = back-buffer.
;
; CF=0 (forward path, 0x07C7..0x084A): SI advances by +3 per pixel
;   (skips alpha/padding bytes in a packed RGB source), plane mask
;   shifts LEFT (AH<<=1 with rollover to plane 0+DI++ on bit-4).
; CF=1 (reverse path, 0x084B..0x08C4): set STD, SI advances by +5 per
;   plane row, plane mask shifts RIGHT (AL>>=1 with carry-out -> AL=8
;   and DI--), then CLD before final RETF.
;
; Both halves unroll exactly 4 plane iterations.
; ============================================================================
vga_blit_sprite_chunky_flip PROC FAR
                MOV     DX, CX                  ; 8B D1     -- save pixel count
                MOV     CL, BL                  ; 8A CB
                MOV     AX, 0102H               ; B8 02 01  -- AL=reg 2, AH=plane-0 bit
                JC      vga_bscf_reverse        ; 72 7E     -- CF=1 -> reverse path
                SHR     BX, 1                   ; D1 EB
                SHR     BX, 1                   ; D1 EB
                ADD     DI, BX                  ; 03 FB     -- DI += x/4
                AND     CL, 3                   ; 80 E1 03
                SHL     AH, CL                  ; D2 E4     -- AH = 1 << (x & 3)
                MOV     CX, DX                  ; 8B CA
                MOV     DX, 03C4H               ; BA C4 03
                OUT     DX, AX                  ; EF
                MOV     AL, AH                  ; 8A C4     -- AL tracks current plane mask
                INC     DX                      ; 42        -- 3C5 = data port
                ADD     CX, 3                   ; 83 C1 03
                MOV     BX, CX                  ; 8B D9
                SHR     CX, 1                   ; D1 E9
                SHR     CX, 1                   ; D1 E9

                ; --- Forward plane 0 ---
                PUSH    SI                      ; 56
                PUSH    DI                      ; 57
vga_bscf_f0:
                MOVSB                           ; A4
                ADD     SI, 3                   ; 83 C6 03
                LOOP    SHORT vga_bscf_f0       ; E2 FA
                DEC     BX                      ; 4B
                POP     DI                      ; 5F
                POP     SI                      ; 5E
                INC     SI                      ; 46
                MOV     CX, BX                  ; 8B CB
                SHR     CX, 1                   ; D1 E9
                SHR     CX, 1                   ; D1 E9
                JZ      SHORT vga_bscf_f_done   ; 74 4C

                ; --- Forward plane 1 ---
                SHL     AL, 1                   ; D0 E0
                AND     AL, 0FH                 ; 24 0F
                JNZ     SHORT vga_bscf_f1_mask  ; 75 03
                INC     AL                      ; FE C0
                INC     DI                      ; 47
vga_bscf_f1_mask:
                OUT     DX, AL                  ; EE
                PUSH    SI                      ; 56
                PUSH    DI                      ; 57
vga_bscf_f1:
                MOVSB                           ; A4
                ADD     SI, 3                   ; 83 C6 03
                LOOP    SHORT vga_bscf_f1       ; E2 FA
                DEC     BX                      ; 4B
                POP     DI                      ; 5F
                POP     SI                      ; 5E
                INC     SI                      ; 46
                MOV     CX, BX                  ; 8B CB
                SHR     CX, 1                   ; D1 E9
                SHR     CX, 1                   ; D1 E9
                JZ      SHORT vga_bscf_f_done   ; 74 2E

                ; --- Forward plane 2 ---
                SHL     AL, 1                   ; D0 E0
                AND     AL, 0FH                 ; 24 0F
                JNZ     SHORT vga_bscf_f2_mask  ; 75 03
                INC     AL                      ; FE C0
                INC     DI                      ; 47
vga_bscf_f2_mask:
                OUT     DX, AL                  ; EE
                PUSH    SI                      ; 56
                PUSH    DI                      ; 57
vga_bscf_f2:
                MOVSB                           ; A4
                ADD     SI, 3                   ; 83 C6 03
                LOOP    SHORT vga_bscf_f2       ; E2 FA
                DEC     BX                      ; 4B
                POP     DI                      ; 5F
                POP     SI                      ; 5E
                INC     SI                      ; 46
                MOV     CX, BX                  ; 8B CB
                SHR     CX, 1                   ; D1 E9
                SHR     CX, 1                   ; D1 E9
                JZ      SHORT vga_bscf_f_done   ; 74 10

                ; --- Forward plane 3 ---
                SHL     AL, 1                   ; D0 E0
                AND     AL, 0FH                 ; 24 0F
                JNZ     SHORT vga_bscf_f3_mask  ; 75 03
                INC     AL                      ; FE C0
                INC     DI                      ; 47
vga_bscf_f3_mask:
                OUT     DX, AL                  ; EE
vga_bscf_f3:
                MOVSB                           ; A4
                ADD     SI, 3                   ; 83 C6 03
                LOOP    SHORT vga_bscf_f3       ; E2 FA
vga_bscf_f_done:
                RETF                            ; CB

                ; --- Reverse path (CF=1 at entry) ---
vga_bscf_reverse:
                STD                             ; FD
                SHR     BX, 1                   ; D1 EB
                SHR     BX, 1                   ; D1 EB
                ADD     DI, BX                  ; 03 FB
                AND     CL, 3                   ; 80 E1 03
                SHL     AH, CL                  ; D2 E4
                MOV     CX, DX                  ; 8B CA
                MOV     DX, 03C4H               ; BA C4 03
                OUT     DX, AX                  ; EF
                MOV     AL, AH                  ; 8A C4
                INC     DX                      ; 42
                ADD     CX, 3                   ; 83 C1 03
                MOV     BX, CX                  ; 8B D9
                SHR     CX, 1                   ; D1 E9
                SHR     CX, 1                   ; D1 E9

                ; --- Reverse plane 0 ---
                ; STD has been set at the top of vga_bscf_reverse, so
                ; MOVSB does SI-=1 / DI-=1 (one source byte fetched,
                ; one dst byte written). The explicit ADD SI, 5 then
                ; recovers a net SI advance of +4 per pixel, and DI
                ; stays at the same destination byte for the next
                ; plane-mask cycle (handled by DEC BX outside the loop).
                PUSH    SI                      ; 56
                PUSH    DI                      ; 57
vga_bscf_r0:
                MOVSB                           ; A4
                ADD     SI, 5                   ; 83 C6 05  (net SI += 4 after STD MOVSB)
                LOOP    SHORT vga_bscf_r0       ; E2 FA
                DEC     BX                      ; 4B
                POP     DI                      ; 5F
                POP     SI                      ; 5E
                INC     SI                      ; 46
                MOV     CX, BX                  ; 8B CB
                SHR     CX, 1                   ; D1 E9
                SHR     CX, 1                   ; D1 E9
                JZ      SHORT vga_bscf_r_done   ; 74 46

                ; --- Reverse plane 1 ---
                SHR     AL, 1                   ; D0 E8
                JNC     SHORT vga_bscf_r1_mask  ; 73 03
                MOV     AL, 8                   ; B0 08
                DEC     DI                      ; 4F
vga_bscf_r1_mask:
                OUT     DX, AL                  ; EE
                PUSH    SI                      ; 56
                PUSH    DI                      ; 57
vga_bscf_r1:
                MOVSB                           ; A4
                ADD     SI, 5                   ; 83 C6 05
                LOOP    SHORT vga_bscf_r1       ; E2 FA
                DEC     BX                      ; 4B
                POP     DI                      ; 5F
                POP     SI                      ; 5E
                INC     SI                      ; 46
                MOV     CX, BX                  ; 8B CB
                SHR     CX, 1                   ; D1 E9
                SHR     CX, 1                   ; D1 E9
                JZ      SHORT vga_bscf_r_done   ; 74 2A

                ; --- Reverse plane 2 ---
                SHR     AL, 1                   ; D0 E8
                JNC     SHORT vga_bscf_r2_mask  ; 73 03
                MOV     AL, 8                   ; B0 08
                DEC     DI                      ; 4F
vga_bscf_r2_mask:
                OUT     DX, AL                  ; EE
                PUSH    SI                      ; 56
                PUSH    DI                      ; 57
vga_bscf_r2:
                MOVSB                           ; A4
                ADD     SI, 5                   ; 83 C6 05
                LOOP    SHORT vga_bscf_r2       ; E2 FA
                DEC     BX                      ; 4B
                POP     DI                      ; 5F
                POP     SI                      ; 5E
                INC     SI                      ; 46
                MOV     CX, BX                  ; 8B CB
                SHR     CX, 1                   ; D1 E9
                SHR     CX, 1                   ; D1 E9
                JZ      SHORT vga_bscf_r_done   ; 74 0E

                ; --- Reverse plane 3 ---
                SHR     AL, 1                   ; D0 E8
                JNC     SHORT vga_bscf_r3_mask  ; 73 03
                MOV     AL, 8                   ; B0 08
                DEC     DI                      ; 4F
vga_bscf_r3_mask:
                OUT     DX, AL                  ; EE
vga_bscf_r3:
                MOVSB                           ; A4
                ADD     SI, 5                   ; 83 C6 05
                LOOP    SHORT vga_bscf_r3       ; E2 FA
vga_bscf_r_done:
                CLD                             ; FC
                RETF                            ; CB
vga_blit_sprite_chunky_flip ENDP

; ============================================================================
; g_abVgaPlaneMaskLut -- 4-byte plane mask LUT @ chunk:0x08C5.
; Single-plane masks (1<<plane) for plane index 0..3. Wedged in the
; 4-byte gap between vga_blit_sprite_chunky_flip's RETF and the start
; of vga_draw_line.
; ============================================================================
g_abVgaPlaneMaskLut     DB      01H, 02H, 04H, 08H

; ============================================================================
; vga_draw_line -- Bresenham single-pixel-thick line draw, Mode-Y.
; chunk:0x08C9..0x0A93
;
; Vtable slot 2.
;
; ABI (register-based):
;   BX = x0, CX = y0, DX = x1, SI = y1, AL = colour (mirrored to AH).
;   ES = back-buffer segment.
;
; Internal cases (dispatched at top):
;   - Single point (x0==x1 && y0==y1): set Map Mask, single STOSB (the
;     latch-read MOV AL,ES:[DI] preserves the other 3 planes).
;   - Horizontal (y0==y1): PUSH CS; CALL vga_fill_run_a (calls _a as a
;     same-segment far call by pushing CS then CALL far).
;   - Vertical (x0==x1): plane mask set once, loop SI..count writing one
;     pixel per row (DI += 80 per step).
;   - Diagonal: full Bresenham. Branches into the 4 octant cores:
;       major-X same-Y (CX==DX) -> simple line of pixels along X
;       major-X (CX<DX)         -> Bresenham X-major
;       major-Y (CX>DX)         -> Bresenham Y-major
;     Each core OUTs Map Mask per pixel, with the same latch-read
;     pattern (MOV AH,ES:[DI]; STOSB).
;
; Calls vga_fill_run_a at chunk:0x02CF via PUSH CS + CALL near (effectively
; a far call to the same segment).
; ============================================================================
vga_draw_line   PROC FAR
                PUSH    DS                      ; 1E
                MOV     DS, cs:[0F4H]           ; 2E 8E 1E F4 00  -- DS = scratch
                XOR     AH, AH                  ; 32 E4
                MOV     AL, ds:[GfxContext.bGfx_outline_color]            ; A0 0E 00       -- AL = active colour
                MOV     ds:[06C2H], AX          ; A3 C2 06       -- save colour pair
                MOV     DI, BX                  ; 8B FB          -- dead-store (DI gets clobbered next)
                MOV     DI, CX                  ; 8B F9
                SHL     DI, 1                   ; D1 E7
                MOV     DI, ds:[DI].GfxContext.pRow_offset_lut ; 8B BD F2 06  DI = row LUT[y0]
                CMP     BX, DX                  ; 3B DA          -- x0 == x1 ?
                JNZ     SHORT vga_dl_xneq       ; 75 06
                CMP     CX, SI                  ; 3B CE
                JZ      SHORT vga_dl_point      ; 74 08
                JMP     SHORT vga_dl_vertical   ; EB 35
vga_dl_xneq:
                CMP     CX, SI                  ; 3B CE          -- y0 == y1 ?
                JZ      SHORT vga_dl_horiz      ; 74 22
                JMP     SHORT vga_dl_diag       ; EB 6A

                ; --- Single point ---
vga_dl_point:
                MOV     AX, BX                  ; 8B C3
                SHR     AX, 1                   ; D1 E8
                SHR     AX, 1                   ; D1 E8
                ADD     DI, AX                  ; 03 F8
                AND     BX, 3                   ; 83 E3 03
                MOV     AH, cs:[BX+08C5H]       ; 2E 8A A7 C5 08  -- plane mask
                MOV     AL, 2                   ; B0 02
                MOV     DX, 03C4H               ; BA C4 03
                OUT     DX, AX                  ; EF
                MOV     AX, ds:[06C2H]          ; A1 C2 06
                MOV     AH, es:[DI]             ; 26 8A 25       -- latch read other 3 planes
                STOSB                           ; AA
                JMP     vga_dl_done             ; E9 81 01

                ; --- Horizontal: tail-call vga_fill_run_a ---
vga_dl_horiz:
                SUB     DX, BX                  ; 2B D3          -- DX = width-1
                MOV     CX, DX                  ; 8B CA
                INC     CX                      ; 41
                MOV     AX, ds:[06C2H]          ; A1 C2 06
                PUSH    CS                      ; 0E             -- same-seg far call setup
                CALL    NEAR PTR vga_fill_run_a ; E8 B2 F9
                JMP     vga_dl_done             ; E9 72 01

                ; --- Vertical: walk y0..y1 in current plane mask ---
vga_dl_vertical:
                MOV     AX, BX                  ; 8B C3
                SHR     AX, 1                   ; D1 E8
                SHR     AX, 1                   ; D1 E8
                ADD     DI, AX                  ; 03 F8
                AND     BX, 3                   ; 83 E3 03
                MOV     AH, cs:[BX+08C5H]       ; 2E 8A A7 C5 08
                MOV     AL, 2                   ; B0 02
                MOV     DX, 03C4H               ; BA C4 03
                OUT     DX, AX                  ; EF
                MOV     AX, ds:[06C2H]          ; A1 C2 06
                MOV     BP, 004FH               ; BD 4F 00       -- row stride = 79
                SUB     SI, CX                  ; 2B F1
                JG      SHORT vga_dl_v_down     ; 7F 0A
                NEG     SI                      ; F7 DE
                SHL     SI, 1                   ; D1 E6          -- |dy| * 2 -> word index
                SUB     DI, ds:[SI].GfxContext.pRow_offset_lut       ; 2B BC F2 06    -- climb up (BP stays +79 actually)
                SHR     SI, 1                   ; D1 EE          -- restore SI to |dy|
vga_dl_v_down:
                MOV     CX, SI                  ; 8B CE
                INC     CX                      ; 41
                MOV     AX, ds:[06C2H]          ; A1 C2 06       -- load colour once
vga_dl_v_loop:
                MOV     AH, es:[DI]             ; 26 8A 25       -- latch read
                STOSB                           ; AA             -- DI += 1
                ADD     DI, BP                  ; 03 FD          -- DI += 79 (total 80 = next row)
                LOOP    SHORT vga_dl_v_loop     ; E2 F8
                JMP     vga_dl_done             ; E9 37 01

                ; --- Diagonal: Bresenham setup ---
vga_dl_diag:
                SHL     DI, 1                   ; D1 E7
                SHL     DI, 1                   ; D1 E7          -- DI *= 4 (re-scale row LUT to 4 byte units)
                ADD     DI, BX                  ; 03 FB          -- + x0
                MOV     BP, 0140H               ; BD 40 01       -- screen-pitch (320) for step-down
                SUB     DX, BX                  ; 2B D3          -- dx = x1-x0
                SUB     SI, CX                  ; 2B F1          -- dy = y1-y0
                JG      SHORT vga_dl_d_post     ; 7F 04
                NEG     SI                      ; F7 DE
                NEG     BP                      ; F7 DD
vga_dl_d_post:
                MOV     CX, SI                  ; 8B CE          -- CX = |dy|
                CMP     CX, DX                  ; 3B CA          -- |dy| vs |dx|
                JZ      SHORT vga_dl_d_xmajor   ; 74 07          -- CX==DX -> X-major (45 deg)
                JC      SHORT vga_dl_d_eq       ; 72 03          -- CX<DX  -> short trampoline
                JMP     vga_dl_d_ymajor         ; E9 9F 00       -- CX>DX  -> Y-major
vga_dl_d_eq:
                JMP     SHORT vga_dl_d_xm_skip  ; EB 31          -- trampoline into X-major Bresenham core

                ; --- X-major (CX == DX, 45-degree case) inlined ---
vga_dl_d_xmajor:
                MOV     CX, DX                  ; 8B CA
                INC     CX                      ; 41
                MOV     AL, 2                   ; B0 02
                MOV     DX, 03C4H               ; BA C4 03
                OUT     DX, AL                  ; EE
                INC     DX                      ; 42             -- DX = 3C5
vga_dl_d_xm_loop:
                PUSH    DX                      ; 52
                PUSH    DI                      ; 57
                PUSH    BX                      ; 53
                MOV     DX, 03C5H               ; BA C5 03
                MOV     BX, DI                  ; 8B DF
                AND     BX, 3                   ; 83 E3 03
                MOV     AL, cs:[BX+08C5H]       ; 2E 8A 87 C5 08
                OUT     DX, AL                  ; EE
                MOV     AL, ds:[06C2H]          ; A0 C2 06       -- 8-bit load colour
                SHR     DI, 1                   ; D1 EF
                SHR     DI, 1                   ; D1 EF
                MOV     AH, es:[DI]             ; 26 8A 25
                STOSB                           ; AA
                POP     BX                      ; 5B
                POP     DI                      ; 5F
                INC     DI                      ; 47
                POP     DX                      ; 5A
                ADD     DI, BP                  ; 03 FD
                LOOP    SHORT vga_dl_d_xm_loop  ; E2 DC
                JMP     vga_dl_done             ; E9 E6 00

                ; --- 45-degree diagonal (CX==DX), shared with the diag-eq case ---
vga_dl_d_xm_skip:
                PUSH    DX                      ; 52
                MOV     AL, 2                   ; B0 02
                MOV     DX, 03C4H               ; BA C4 03
                OUT     DX, AL                  ; EE
                POP     DX                      ; 5A
                MOV     BX, CX                  ; 8B D9
                MOV     CX, DX                  ; 8B CA
                MOV     AX, BX                  ; 8B C3
                SHL     AX, 1                   ; D1 E0
                MOV     SI, AX                  ; 8B F0
                SUB     AX, CX                  ; 2B C1
                MOV     DX, AX                  ; 8B D0
                SUB     AX, CX                  ; 2B C1
                MOV     BX, BP                  ; 8B DD
                MOV     BP, AX                  ; 8B E8
                ; --- 45-deg: first pixel write (one-shot before loop) ---
                PUSH    DX                      ; 52
                PUSH    DI                      ; 57
                PUSH    BX                      ; 53
                MOV     DX, 03C5H               ; BA C5 03
                MOV     BX, DI                  ; 8B DF
                AND     BX, 3                   ; 83 E3 03
                MOV     AL, cs:[BX+08C5H]       ; 2E 8A 87 C5 08
                OUT     DX, AL                  ; EE
                MOV     AL, ds:[06C2H]          ; A0 C2 06
                SHR     DI, 1                   ; D1 EF
                SHR     DI, 1                   ; D1 EF
                MOV     AH, es:[DI]             ; 26 8A 25
                STOSB                           ; AA
                POP     BX                      ; 5B
                POP     DI                      ; 5F
                INC     DI                      ; 47
                POP     DX                      ; 5A
vga_dl_d_eq_loop:
                OR      DX, DX                  ; 0B D2
                JS      SHORT vga_dl_d_eq_neg   ; 78 06
                ADD     DI, BX                  ; 03 FB
                ADD     DX, BP                  ; 03 D5
                JMP     SHORT vga_dl_d_eq_join  ; EB 02
vga_dl_d_eq_neg:
                ADD     DX, SI                  ; 03 D6
vga_dl_d_eq_join:
                PUSH    DX                      ; 52
                PUSH    DI                      ; 57
                PUSH    BX                      ; 53
                MOV     DX, 03C5H               ; BA C5 03
                MOV     BX, DI                  ; 8B DF
                AND     BX, 3                   ; 83 E3 03
                MOV     AL, cs:[BX+08C5H]       ; 2E 8A 87 C5 08
                OUT     DX, AL                  ; EE
                MOV     AL, ds:[06C2H]          ; A0 C2 06
                SHR     DI, 1                   ; D1 EF
                SHR     DI, 1                   ; D1 EF
                MOV     AH, es:[DI]             ; 26 8A 25
                STOSB                           ; AA
                POP     BX                      ; 5B
                POP     DI                      ; 5F
                INC     DI                      ; 47
                POP     DX                      ; 5A
                LOOP    SHORT vga_dl_d_eq_loop  ; E2 D2
                JMP     SHORT vga_dl_done       ; EB 7A

                ; --- Y-major Bresenham core (CX = |dy|, taller than wide) ---
vga_dl_d_ymajor:
                MOV     BX, DX                  ; 8B DA
                MOV     AX, 0001H               ; B8 01 00
                OR      BP, BP                  ; 0B ED
                JNS     SHORT vga_dl_d_ym_pos   ; 79 0D
                NEG     AX                      ; F7 D8
                PUSH    AX                      ; 50
                MOV     AX, 0140H               ; B8 40 01
                MUL     CX                      ; F7 E1
                SUB     DI, AX                  ; 2B F8
                ADD     DI, BX                  ; 03 FB
                POP     AX                      ; 58
vga_dl_d_ym_pos:
                MOV     BP, AX                  ; 8B E8
                MOV     AX, BX                  ; 8B C3
                SHL     AX, 1                   ; D1 E0
                MOV     SI, AX                  ; 8B F0
                SUB     AX, CX                  ; 2B C1
                MOV     DX, AX                  ; 8B D0
                SUB     AX, CX                  ; 2B C1
                MOV     BX, BP                  ; 8B DD
                MOV     BP, AX                  ; 8B E8
                ; --- Y-major: first pixel write (one-shot before loop) ---
                PUSH    DX                      ; 52
                PUSH    DI                      ; 57
                PUSH    BX                      ; 53
                MOV     DX, 03C5H               ; BA C5 03
                MOV     BX, DI                  ; 8B DF
                AND     BX, 3                   ; 83 E3 03
                MOV     AL, cs:[BX+08C5H]       ; 2E 8A 87 C5 08
                OUT     DX, AL                  ; EE
                MOV     AL, ds:[06C2H]          ; A0 C2 06
                SHR     DI, 1                   ; D1 EF
                SHR     DI, 1                   ; D1 EF
                MOV     AH, es:[DI]             ; 26 8A 25
                STOSB                           ; AA
                POP     BX                      ; 5B
                POP     DI                      ; 5F
                INC     DI                      ; 47
                POP     DX                      ; 5A
vga_dl_d_ym_loop:
                ADD     DI, 013FH               ; 81 C7 3F 01     -- DI += 319 (line wrap)
                OR      DX, DX                  ; 0B D2
                JS      SHORT vga_dl_d_ym_neg   ; 78 06
                ADD     DI, BX                  ; 03 FB
                ADD     DX, BP                  ; 03 D5
                JMP     SHORT vga_dl_d_ym_join  ; EB 02
vga_dl_d_ym_neg:
                ADD     DX, SI                  ; 03 D6
vga_dl_d_ym_join:
                PUSH    DX                      ; 52
                PUSH    DI                      ; 57
                PUSH    BX                      ; 53
                MOV     DX, 03C5H               ; BA C5 03
                MOV     BX, DI                  ; 8B DF
                AND     BX, 3                   ; 83 E3 03
                MOV     AL, cs:[BX+08C5H]       ; 2E 8A 87 C5 08
                OUT     DX, AL                  ; EE
                MOV     AL, ds:[06C2H]          ; A0 C2 06
                SHR     DI, 1                   ; D1 EF
                SHR     DI, 1                   ; D1 EF
                MOV     AH, es:[DI]             ; 26 8A 25
                STOSB                           ; AA
                POP     BX                      ; 5B
                POP     DI                      ; 5F
                INC     DI                      ; 47
                POP     DX                      ; 5A
                LOOP    SHORT vga_dl_d_ym_loop  ; E2 CE
vga_dl_done:
                POP     DS                      ; 1F
                RETF                            ; CB
vga_draw_line   ENDP

; ============================================================================
; Mask LUTs and pad bytes between vga_draw_line and
; vga_fill_spans_dithered_modey. chunk:0x0A94..0x0AA7.
;
; These mirror the leading mask LUTs at 0x0213/0x0217/0x021B; the engine
; addresses both pairs depending on which span helper is calling.
; ============================================================================
g_abVgaFillRunLeftMaskLut       DB      0FH, 0EH, 0CH, 08H      ; 0x0A94
g_abVgaFillRunRightMaskLut      DB      0FH, 01H, 03H, 07H      ; 0x0A98
g_abVgaFillRunSingleByteMaskLut DB      00H, 01H, 03H, 07H      ; 0x0A9C

; ============================================================================
; Span-fill scratch words used by vga_fill_spans_dithered_modey.
; chunk:0x0AA0..0x0AA7. Zero-initialised on disk.
; ============================================================================
g_wVgaSpanFillRowCounter        DW      0       ; 0x0AA0
g_wVgaSpanFillColors            DW      0       ; 0x0AA2
g_wVgaSpanFillColorsSwapped     DW      0       ; 0x0AA4
g_wVgaSpanFillRowLutPtr         DW      0       ; 0x0AA6

; ============================================================================
; vga_fill_spans_dithered_modey -- multi-row span filler with Mode-Y dither.
; chunk:0x0AA8..0x0D35 (vtable slot 27)
;
; ABI (vtable far call):
;   DS:SI  -> span vector: { offset_arg: word, row_count: word,
;                            { x0, x1 }* row_count }
;   ES     = working framebuffer segment (preserved as scratch in CX/DS).
;
; Algorithm: see plate. Two paths (single-colour vs dither). Each path
; has a one-byte-span fast case and a multi-byte (left-mask + middle
; STOSB + right-mask) case. Map Mask cycling: 0x05 = planes 0+2
; (colour A), 0x0A = planes 1+3 (colour B).
; ============================================================================
vga_fill_spans_dithered_modey PROC FAR
                MOV     DX, 03C4H               ; BA C4 03  -- Sequencer index
                MOV     AL, 02H                 ; B0 02     -- reg 2 = Map Mask
                OUT     DX, AL                  ; EE
                PUSH    DS                      ; 1E
                MOV     CX, ES                  ; 8C C1     -- stash caller's ES
                MOV     DS, CX                  ; 8E D9     -- DS := caller ES
                LODSW                           ; AD        -- AX = arg word
                SHL     AX, 1                   ; D1 E0
                MOV     BP, AX                  ; 8B E8     -- BP = arg*2 (row LUT idx step)
                LODSW                           ; AD        -- AX = row count
                MOV     DS, cs:[0F4H]           ; 2E 8E 1E F4 00  scratch DS
                MOV     cs:[0AA0H], AX          ; 2E A3 A0 0A  g_wVgaSpanFillRowCounter
                MOV     AX, ds:[GfxContext.wGfxBlitDstPage]            ; A1 18 00  FB seg
                MOV     ES, AX                  ; 8E C0
                ; Build an SS-relative pointer to the row LUT.
                ; scratch DS sits paragraphs/16 segments past caller's
                ; DS (= caller's SS), which is paragraphs BYTES past SS.
                ; The row LUT lives at scratch:[0x6F2], so the byte
                ; offset reachable via SS is (0x6F2 + paragraph_count).
                ; Hot loop uses `[BP+DI]` (SS-relative) to fetch each
                ; row's offset, so this saves a DS reload per scanline.
                MOV     AX, GfxContext.pRow_offset_lut               ; B8 F2 06  row LUT offset within scratch
                ADD     AX, cs:[0F6H]           ; 2E 03 06 F6 00  + scratch-vs-SS byte distance
                MOV     cs:[0AA6H], AX          ; 2E A3 A6 0A  g_wVgaSpanFillRowLutPtr
                MOV     AL, ds:[GfxContext.bGfx_fill_color]            ; A0 0D 00  primary colour
                MOV     AH, ds:[GfxContext.bGfx_dither_color]            ; 8A 26 0F 00  secondary colour
                MOV     DS, CX                  ; 8E D9     DS := caller ES
                MOV     cs:[0AA2H], AX          ; 2E A3 A2 0A  g_wVgaSpanFillColors
                OR      AH, AH                  ; 0A E4
                JZ      SHORT vga_fsdm_single   ; 74 09     -- AH=0 -> single-colour
                XCHG    AL, AH                  ; 86 C4
                MOV     cs:[0AA4H], AX          ; 2E A3 A4 0A  g_wVgaSpanFillColorsSwapped
                JMP     vga_fsdm_dither_setup   ; E9 9F 00

                ; --- Single-colour span path ---
vga_fsdm_single:
vga_fsdm_s_body:
                LODSW                           ; AD        -- x0
                MOV     BX, AX                  ; 8B D8
                LODSW                           ; AD        -- x1
                SUB     AX, BX                  ; 2B C3
                JGE     SHORT vga_fsdm_s_pos    ; 7D 03
                JMP     vga_fsdm_s_step         ; E9 84 00
vga_fsdm_s_pos:
                INC     AX                      ; 40
                MOV     CX, AX                  ; 8B C8     -- CX = width
                MOV     DI, cs:[0AA6H]          ; 2E 8B 3E A6 0A
                MOV     DI, [BP+DI]             ; 8B 3B     -- DI = row offset
                MOV     AX, cs:[0AA2H]          ; 2E A1 A2 0A
                MOV     AH, AL                  ; 8A E0     -- dup colour byte in AH
                MOV     DX, AX                  ; 8B D0     -- DX = colour-pair stash
                MOV     AX, BX                  ; 8B C3
                ADD     AX, CX                  ; 03 C1
                DEC     AX                      ; 48
                XOR     AX, BX                  ; 33 C3
                AND     AX, 0FFCH               ; 25 FC 0F
                JNZ     SHORT vga_fsdm_s_multi  ; 75 2A
                ; one-byte span (entirely inside one plane group)
                MOV     AX, BX                  ; 8B C3
                SHR     AX, 1                   ; D1 E8
                SHR     AX, 1                   ; D1 E8     -- AX = x/4
                ADD     DI, AX                  ; 03 F8
                MOV     AX, BX                  ; 8B C3
                ADD     BX, CX                  ; 03 D9
                AND     AX, 3                   ; 25 03 00
                AND     BX, 3                   ; 83 E3 03
                MOV     CL, AL                  ; 8A C8     -- shift count
                MOV     AL, 0FFH                ; B0 FF
                SHL     AL, CL                  ; D2 E0
                AND     AL, cs:[BX+0A98H]       ; 2E 22 87 98 0A  & right-mask
                MOV     BX, DX                  ; 8B DA     -- restore colour
                MOV     DX, 03C5H               ; BA C5 03  Sequencer data
                OUT     DX, AL                  ; EE        -- Map Mask = composed
                MOV     AX, BX                  ; 8B C3
                MOV     es:[DI], AL             ; 26 88 05
                JMP     SHORT vga_fsdm_s_step   ; EB 3C
vga_fsdm_s_multi:
                MOV     AX, BX                  ; 8B C3
                SHR     AX, 1                   ; D1 E8
                SHR     AX, 1                   ; D1 E8
                ADD     DI, AX                  ; 03 F8
                AND     BX, 3                   ; 83 E3 03
                SUB     CX, 4                   ; 83 E9 04
                ADD     CX, BX                  ; 03 CB
                MOV     AL, cs:[BX+0A94H]       ; 2E 8A 87 94 0A  left mask
                MOV     BX, DX                  ; 8B DA
                MOV     DX, 03C5H               ; BA C5 03
                OUT     DX, AL                  ; EE        -- Map Mask = left
                MOV     AX, BX                  ; 8B C3
                STOSB                           ; AA        -- one byte
                MOV     AL, 0FH                 ; B0 0F
                OUT     DX, AL                  ; EE        -- Map Mask = all planes
                MOV     AL, AH                  ; 8A C4     -- colour byte
                MOV     BX, CX                  ; 8B D9
                SHR     CX, 1                   ; D1 E9
                SHR     CX, 1                   ; D1 E9
                SHR     CX, 1                   ; D1 E9     -- bytes/8 (word reps)
                REP     STOSW                   ; F3 AB
                JNC     SHORT vga_fsdm_s_nopad  ; 73 01
                STOSB                           ; AA        -- odd-byte tail
vga_fsdm_s_nopad:
                AND     BX, 3                   ; 83 E3 03
                MOV     AL, cs:[BX+0A9CH]       ; 2E 8A 87 9C 0A  right mask
                OUT     DX, AL                  ; EE
                MOV     AL, AH                  ; 8A C4
                STOSB                           ; AA
vga_fsdm_s_step:
                SUB     WORD PTR cs:[0AA0H], 1  ; 2E 83 2E A0 0A 01
                JLE     SHORT vga_fsdm_s_done   ; 7E 06
                ADD     BP, 2                   ; 83 C5 02
                JMP     vga_fsdm_s_body         ; E9 63 FF
vga_fsdm_s_done:
                POP     DS                      ; 1F
                RETF                            ; CB

                ; --- Dither (two-colour) span path ---
vga_fsdm_dither_setup:
                MOV     cs:[0AA4H], AX          ; 2E A3 A4 0A  g_wVgaSpanFillColorsSwapped
                MOV     BX, BP                  ; 8B DD
                SHR     BX, 1                   ; D1 EB
                ADD     BX, [SI]                ; 03 1C
                SHR     BX, 1                   ; D1 EB
                JC      SHORT vga_fsdm_d_evenh  ; 72 03
                JMP     vga_fsdm_d_oddhead      ; E9 CB 00
vga_fsdm_d_evenh:
                LODSW                           ; AD        -- x0
                MOV     BX, AX                  ; 8B D8
                LODSW                           ; AD        -- x1
                SUB     AX, BX                  ; 2B C3
                JGE     SHORT vga_fsdm_d_e_pos  ; 7D 03
                JMP     vga_fsdm_d_e_step       ; E9 B0 00
vga_fsdm_d_e_pos:
                INC     AX                      ; 40
                MOV     CX, AX                  ; 8B C8
                MOV     DI, cs:[0AA6H]          ; 2E 8B 3E A6 0A
                MOV     DI, [BP+DI]             ; 8B 3B
                MOV     AX, cs:[0AA2H]          ; 2E A1 A2 0A  even colour pair
                MOV     DX, AX                  ; 8B D0
                MOV     AX, BX                  ; 8B C3
                ADD     AX, CX                  ; 03 C1
                DEC     AX                      ; 48
                XOR     AX, BX                  ; 33 C3
                AND     AX, 0FFCH               ; 25 FC 0F
                JNZ     SHORT vga_fsdm_d_e_multi ; 75 37
                MOV     AX, BX                  ; 8B C3
                SHR     AX, 1                   ; D1 E8
                SHR     AX, 1                   ; D1 E8
                ADD     DI, AX                  ; 03 F8
                MOV     AX, BX                  ; 8B C3
                ADD     BX, CX                  ; 03 D9
                AND     AX, 3                   ; 25 03 00
                AND     BX, 3                   ; 83 E3 03
                MOV     CL, AL                  ; 8A C8
                MOV     AX, 0FF02H              ; B8 02 FF
                SHL     AH, CL                  ; D2 E4
                AND     AH, cs:[BX+0A98H]       ; 2E 22 A7 98 0A
                MOV     BX, DX                  ; 8B DA
                MOV     DX, 03C4H               ; BA C4 03
                OUT     DX, AL                  ; EE
                INC     DX                      ; 42
                MOV     AL, 5                   ; B0 05
                AND     AL, AH                  ; 22 C4     -- planes 0+2 (colour A)
                OUT     DX, AL                  ; EE
                MOV     es:[DI], BH             ; 26 88 3D
                MOV     AL, 0AH                 ; B0 0A
                AND     AL, AH                  ; 22 C4     -- planes 1+3 (colour B)
                OUT     DX, AL                  ; EE
                MOV     AL, BL                  ; 8A C3
                STOSB                           ; AA
                JMP     SHORT vga_fsdm_d_e_step ; EB 60
vga_fsdm_d_e_multi:
                MOV     AX, BX                  ; 8B C3
                SHR     AX, 1                   ; D1 E8
                SHR     AX, 1                   ; D1 E8
                ADD     DI, AX                  ; 03 F8
                PUSH    DX                      ; 52
                MOV     AL, 02H                 ; B0 02
                MOV     DX, 03C4H               ; BA C4 03
                INC     DX                      ; 42
                OUT     DX, AL                  ; EE
                AND     BX, 3                   ; 83 E3 03
                SUB     CX, 4                   ; 83 E9 04
                ADD     CX, BX                  ; 03 CB
                MOV     AL, cs:[BX+0A94H]       ; 2E 8A 87 94 0A
                MOV     AH, AL                  ; 8A E0
                POP     BX                      ; 5B
                AND     AL, 0AH                 ; 24 0A
                OUT     DX, AL                  ; EE
                MOV     es:[DI], BL             ; 26 88 1D
                MOV     AL, AH                  ; 8A C4
                AND     AL, 5                   ; 24 05
                OUT     DX, AL                  ; EE
                MOV     AL, BH                  ; 8A C7
                STOSB                           ; AA
                MOV     AL, 0AH                 ; B0 0A
                OUT     DX, AL                  ; EE
                PUSH    CX                      ; 51
                SHR     CX, 1                   ; D1 E9
                SHR     CX, 1                   ; D1 E9
                MOV     AL, BL                  ; 8A C3
                PUSH    CX                      ; 51
                PUSH    DI                      ; 57
                REP     STOSB                   ; F3 AA
                POP     DI                      ; 5F
                POP     CX                      ; 59
                MOV     AL, 5                   ; B0 05
                OUT     DX, AL                  ; EE
                MOV     AL, BH                  ; 8A C7
                REP     STOSB                   ; F3 AA
                MOV     CX, BX                  ; 8B CB
                POP     BX                      ; 5B
                AND     BX, 3                   ; 83 E3 03
                MOV     AL, cs:[BX+0A9CH]       ; 2E 8A 87 9C 0A
                MOV     AH, AL                  ; 8A E0
                AND     AL, 0AH                 ; 24 0A
                OUT     DX, AL                  ; EE
                MOV     es:[DI], CL             ; 26 88 0D
                MOV     AL, AH                  ; 8A C4
                AND     AL, 5                   ; 24 05
                OUT     DX, AL                  ; EE
                MOV     AL, CH                  ; 8A C5
                STOSB                           ; AA
vga_fsdm_d_e_step:
                SUB     WORD PTR cs:[0AA0H], 1  ; 2E 83 2E A0 0A 01
                JG      SHORT vga_fsdm_d_odd    ; 7F 02
                POP     DS                      ; 1F
                RETF                            ; CB
vga_fsdm_d_odd:
                ADD     BP, 2                   ; 83 C5 02
vga_fsdm_d_oddhead:
                LODSW                           ; AD
                MOV     BX, AX                  ; 8B D8
                LODSW                           ; AD
                SUB     AX, BX                  ; 2B C3
                JGE     SHORT vga_fsdm_d_o_pos  ; 7D 03
                JMP     vga_fsdm_d_o_step       ; E9 B3 00
vga_fsdm_d_o_pos:
                INC     AX                      ; 40
                MOV     CX, AX                  ; 8B C8
                MOV     DI, cs:[0AA6H]          ; 2E 8B 3E A6 0A
                MOV     DI, [BP+DI]             ; 8B 3B
                MOV     AX, cs:[0AA4H]          ; 2E A1 A4 0A  swapped colour pair (odd row)
                MOV     DX, AX                  ; 8B D0
                MOV     AX, BX                  ; 8B C3
                ADD     AX, CX                  ; 03 C1
                DEC     AX                      ; 48
                XOR     AX, BX                  ; 33 C3
                AND     AX, 0FFCH               ; 25 FC 0F
                JNZ     SHORT vga_fsdm_d_o_multi ; 75 37
                MOV     AX, BX                  ; 8B C3
                SHR     AX, 1                   ; D1 E8
                SHR     AX, 1                   ; D1 E8
                ADD     DI, AX                  ; 03 F8
                MOV     AX, BX                  ; 8B C3
                ADD     BX, CX                  ; 03 D9
                AND     AX, 3                   ; 25 03 00
                AND     BX, 3                   ; 83 E3 03
                MOV     CL, AL                  ; 8A C8
                MOV     AX, 0FF02H              ; B8 02 FF
                SHL     AH, CL                  ; D2 E4
                AND     AH, cs:[BX+0A98H]       ; 2E 22 A7 98 0A
                MOV     BX, DX                  ; 8B DA
                MOV     DX, 03C4H               ; BA C4 03
                OUT     DX, AL                  ; EE
                INC     DX                      ; 42
                MOV     AL, 5                   ; B0 05
                AND     AL, AH                  ; 22 C4
                OUT     DX, AL                  ; EE
                MOV     es:[DI], BH             ; 26 88 3D
                MOV     AL, 0AH                 ; B0 0A
                AND     AL, AH                  ; 22 C4
                OUT     DX, AL                  ; EE
                MOV     AL, BL                  ; 8A C3
                STOSB                           ; AA
                JMP     SHORT vga_fsdm_d_o_step ; EB 60
vga_fsdm_d_o_multi:
                MOV     AX, BX                  ; 8B C3
                SHR     AX, 1                   ; D1 E8
                SHR     AX, 1                   ; D1 E8
                ADD     DI, AX                  ; 03 F8
                PUSH    DX                      ; 52
                MOV     AL, 02H                 ; B0 02
                MOV     DX, 03C4H               ; BA C4 03
                INC     DX                      ; 42
                OUT     DX, AL                  ; EE
                AND     BX, 3                   ; 83 E3 03
                SUB     CX, 4                   ; 83 E9 04
                ADD     CX, BX                  ; 03 CB
                MOV     AL, cs:[BX+0A94H]       ; 2E 8A 87 94 0A
                MOV     AH, AL                  ; 8A E0
                POP     BX                      ; 5B
                AND     AL, 0AH                 ; 24 0A
                OUT     DX, AL                  ; EE
                MOV     es:[DI], BL             ; 26 88 1D
                MOV     AL, AH                  ; 8A C4
                AND     AL, 5                   ; 24 05
                OUT     DX, AL                  ; EE
                MOV     AL, BH                  ; 8A C7
                STOSB                           ; AA
                MOV     AL, 0AH                 ; B0 0A
                OUT     DX, AL                  ; EE
                PUSH    CX                      ; 51
                SHR     CX, 1                   ; D1 E9
                SHR     CX, 1                   ; D1 E9
                MOV     AL, BL                  ; 8A C3
                PUSH    CX                      ; 51
                PUSH    DI                      ; 57
                REP     STOSB                   ; F3 AA
                POP     DI                      ; 5F
                POP     CX                      ; 59
                MOV     AL, 5                   ; B0 05
                OUT     DX, AL                  ; EE
                MOV     AL, BH                  ; 8A C7
                REP     STOSB                   ; F3 AA
                MOV     CX, BX                  ; 8B CB
                POP     BX                      ; 5B
                AND     BX, 3                   ; 83 E3 03
                MOV     AL, cs:[BX+0A9CH]       ; 2E 8A 87 9C 0A
                MOV     AH, AL                  ; 8A E0
                AND     AL, 0AH                 ; 24 0A
                OUT     DX, AL                  ; EE
                MOV     es:[DI], CL             ; 26 88 0D
                MOV     AL, AH                  ; 8A C4
                AND     AL, 5                   ; 24 05
                OUT     DX, AL                  ; EE
                MOV     AL, CH                  ; 8A C5
                STOSB                           ; AA
vga_fsdm_d_o_step:
                SUB     WORD PTR cs:[0AA0H], 1  ; 2E 83 2E A0 0A 01
                JLE     SHORT vga_fsdm_d_o_done ; 7E 06
                ADD     BP, 2                   ; 83 C5 02
                JMP     vga_fsdm_d_evenh        ; E9 69 FE
vga_fsdm_d_o_done:
                POP     DS                      ; 1F
                RETF                            ; CB
vga_fill_spans_dithered_modey ENDP

; ============================================================================
; 0x0D36 -- 2-byte pad before vga_dac_write_palette. Zero on disk.
; ============================================================================
g_abVgaPad0D36                  DB      0, 0    ; 0x0D36

; ============================================================================
; vga_dac_write_palette -- DAC bulk palette upload.
; chunk:0x0D38..0x0D74
;
; ABI (__cdecl16far):
;   [BP+6]   byte *rgb_triplets   (near pointer; DS-relative)
;   [BP+8]   ushort start_index   (DAC slot 0..255)
;   [BP+0Ah] ushort count         (number of COLOURS; CX = count*3)
;
; THE DAC SIDE -- VGA palette is 256 entries x 3 channels (R, G, B)
; at 6 bits each (values 0..63). Programmed via three I/O ports:
;   0x3C7  W: DAC Read Index   |  R: DAC State (bits 0..1)
;          The State register reads 00b = "DAC is in write mode" or
;          11b = "DAC is in read mode". (See FreeVGA DAC reference;
;          INMOS IMS G171 datasheet for the underlying chip.)
;   0x3C8  W: DAC Write Index. Writing N starts a 3-byte cycle for
;          entry N: the next three OUTs to 0x3C9 are interpreted as
;          R, G, B; on the third byte the index auto-increments to N+1.
;   0x3C9  W/R: DAC Data. Each access steps the internal "which of
;          R/G/B-next" sub-counter; the counter is NOT reset by
;          re-arming 0x3C8 mid-triple -- a
;          bare OUT to 0x3C9 outside a clean triple will shift the
;          R/G/B phase, not be silently dropped.
;
; Algorithm:
;   1. Wait for vertical retrace start (poll port 0x3DA bit 3 until
;      set). Gating palette writes on vretrace prevents visible
;      "snow" / fringes on original-IBM-era VGA chips where a write
;      racing the beam can corrupt the displayed colour for one frame
;      (see DJGPP DOS VGA docs).
;   2. DAC-state defensive sync: read DAC State (0x3C7) AND with 3;
;      if low 2 bits != 3 (= we're not in clean read mode), OUT the
;      masked value to 0x3C9. This is the original code's attempt to
;      "resync" -- but per FreeVGA + o3one + VGADOC, an OUT to 0x3C9
;      does NOT reset the DAC state machine; it just shifts the
;      sub-counter phase. So this branch is effectively a no-op. The
;      clean 0x3C8 write in step 3 is what actually re-arms the cycle.
;   3. Write start_index to 0x3C8 (DAC Write Index).
;   4. CLI; LODSB + OUT 0x3C9 in a loop, count*3 iterations; STI.
;      Interrupts off so the 768 bytes of palette upload complete
;      atomically -- an ISR firing mid-loop could leak random
;      R/G/B writes through 0x3C9 and corrupt the phase.
; ============================================================================
vga_dac_write_palette PROC FAR
                PUSH    BP                      ; 55
                MOV     BP, SP                  ; 8B EC
                PUSH    SI                      ; 56
                PUSH    DI                      ; 57
                MOV     SI, [BP+6]              ; 8B 76 06  rgb_triplets
                MOV     CX, [BP+0AH]            ; 8B 4E 0A  count
                MOV     AX, CX                  ; 8B C1
                SHL     CX, 1                   ; D1 E1
                ADD     CX, AX                  ; 03 C8     CX = count*3 (bytes)
                MOV     BX, [BP+8]              ; 8B 5E 08  start_index
                MOV     DX, 03DAH               ; BA DA 03  -- Input Status 1
vga_dac_wp_vsync:
                IN      AL, DX                  ; EC
                AND     AL, 8                   ; 24 08     -- bit 3 = vsync
                JZ      SHORT vga_dac_wp_vsync  ; 74 FB
                MOV     DX, 03C7H               ; BA C7 03  -- DAC State (R)
                IN      AL, DX                  ; EC
                AND     AL, 3                   ; 24 03
                CMP     AL, 3                   ; 3C 03
                JZ      SHORT vga_dac_wp_setidx ; 74 04
                MOV     DX, 03C9H               ; BA C9 03  -- DAC Data
                OUT     DX, AL                  ; EE        -- defensive sub-counter bump
                                                ;            (does NOT reset the DAC -- a bare
                                                ;            OUT to 0x3C9 sticks with phase
                                                ;            shift; see plate above).
vga_dac_wp_setidx:
                MOV     DX, 03C8H               ; BA C8 03  -- DAC Write Index
                MOV     AX, BX                  ; 8B C3
                OUT     DX, AL                  ; EE
                MOV     DX, 03C9H               ; BA C9 03  -- DAC Data
                CLI                             ; FA
vga_dac_wp_loop:
                LODSB                           ; AC
                OUT     DX, AL                  ; EE
                LOOP    SHORT vga_dac_wp_loop   ; E2 FC
                STI                             ; FB
                POP     DI                      ; 5F
                POP     SI                      ; 5E
                POP     BP                      ; 5D
                RETF                            ; CB
vga_dac_write_palette ENDP

; ============================================================================
; vga_palette_set_one -- single-colour wrapper around vga_dac_write_palette.
; chunk:0x0D75..0x0D8B
;
; ABI (__cdecl16far):
;   [BP+6..8] uchar rgb[3]   inline RGB triplet (passed by value on stack)
;   [BP+0Ah]  ushort idx     DAC slot
;
; Body: push (count=1, idx, &rgb_on_stack); PUSH CS; CALL NEAR
; vga_dac_write_palette. The PUSH CS + near CALL simulates a far call so
; the callee's RETF returns correctly.
; ============================================================================
vga_palette_set_one PROC FAR
                PUSH    BP                      ; 55
                MOV     BP, SP                  ; 8B EC
                PUSH    SI                      ; 56
                MOV     BX, [BP+0AH]            ; 8B 5E 0A  idx
                LEA     SI, [BP+6]              ; 8D 76 06  &rgb on stack
                MOV     AX, 1                   ; B8 01 00  count = 1
                PUSH    AX                      ; 50
                PUSH    BX                      ; 53
                PUSH    SI                      ; 56
                PUSH    CS                      ; 0E
                CALL    NEAR PTR vga_dac_write_palette ; E8 AF FF
                POP     SI                      ; 5E
                POP     BP                      ; 5D
                RETF                            ; CB
vga_palette_set_one ENDP

; ============================================================================
; vga_palette_set -- bulk DAC palette set + double-buffered cache copy.
; chunk:0x0D8C..0x0DCD (vtable slot 20)
;
; ABI (__cdecl16far):
;   [BP+6]  ushort palette_off   far ptr offset (in caller's seg)
;   [BP+8]  ushort palette_seg   far ptr segment (skipped if 0)
;
; The [ds:019Eh] / [ds:01A0h] reads at the top of the body resolve to
; scratch-heap memory: at this point DS has been reloaded from
; cs:[0F4H] = chunk's private "scratch DS" segment (allocated by the
; engine at vga_init), so these are offsets WITHIN that scratch
; segment, not the chunk's code segment. The chunk's own 0x019E..0x01A0
; bytes are inside the host-callback table at CS:01C0; the matching
; SCRATCH bytes just happen to share the same numeric offset, which
; is coincidence -- different segments. Scratch:0x19E:0x1A0 holds a
; far pointer to the engine's palette-cache buffer (2 x 768 bytes,
; "palette A" + "palette B" for cross-fade interpolation).
;
; Body:
;   1. DS := scratch; DI := scratch:[0x19E] (cache off); ES :=
;      scratch:[0x1A0] (cache seg).
;   2. SI := palette_off; AX := palette_seg; if seg==0 -> skip
;      (no palette supplied).
;   3. Call vga_dac_write_palette(SI, 0, 256).
;   4. REP MOVSW 0x180 words (768 bytes) into ES:DI = palette A,
;      then SI -= 768*2 (rewind) and REP MOVSW 0x180 again into
;      palette B. After this the cache holds two identical copies
;      of the palette; later vga_palette_lerp_dac reads from both.
; ============================================================================
vga_palette_set PROC FAR
                PUSH    BP                      ; 55
                MOV     BP, SP                  ; 8B EC
                PUSH    DI                      ; 57
                PUSH    SI                      ; 56
                PUSH    DS                      ; 1E
                MOV     DS, cs:[0F4H]           ; 2E 8E 1E F4 00  scratch DS
                MOV     DI, ds:[GfxContext.pPaletteScratchBuf]          ; 8B 3E 9E 01  palette ptr offset (alias)
                MOV     ES, ds:[GfxContext.pPaletteScratchBuf+2]          ; 8E 06 A0 01  palette ptr segment (alias)
                MOV     SI, [BP+6]              ; 8B 76 06
                MOV     AX, [BP+8]              ; 8B 46 08
                MOV     DS, AX                  ; 8E D8
                OR      AX, AX                  ; 0B C0
                JZ      SHORT vga_palset_done   ; 74 1E
                MOV     AX, 0100H               ; B8 00 01  count = 256
                PUSH    AX                      ; 50
                XOR     AX, AX                  ; 33 C0     start_index = 0
                PUSH    AX                      ; 50
                PUSH    SI                      ; 56        rgb_triplets
                PUSH    CS                      ; 0E
                CALL    NEAR PTR vga_dac_write_palette ; E8 81 FF
                ADD     SP, 6                   ; 83 C4 06
                ; Cache the 256-colour palette into the engine's
                ; double-buffered storage at ES:DI. 0x180 words = 384
                ; words = 768 bytes = 256 colours x 3 RGB bytes.
                MOV     CX, 0180H               ; B9 80 01  384 words = full palette
                MOV     AX, CX                  ; 8B C1
                REP     MOVSW                   ; F3 A5     -- first copy (palette A)
                SUB     SI, AX                  ; 2B F0
                SUB     SI, AX                  ; 2B F0     -- rewind SI by 0x180 words = 768 bytes
                MOV     CX, AX                  ; 8B C8
                REP     MOVSW                   ; F3 A5     -- second copy (palette B)
vga_palset_done:
                POP     DS                      ; 1F
                POP     SI                      ; 5E
                POP     DI                      ; 5F
                POP     BP                      ; 5D
                RETF                            ; CB
vga_palette_set ENDP

; ============================================================================
; vga_palette_lerp_dac -- palette cross-fade upload.
; chunk:0x0DCE..0x0E4B
;
; ABI (__cdecl16far):
;   [BP+6]  ushort start_idx     DAC slot range [start..start+count)
;   [BP+8]  ushort count         number of colours
;   [BP+0Ah]ushort dst_idx       destination palette half-offset (colours)
;   [BP+0Ch]uchar  weight        0..63 (DH=0x3F fixed scale)
;
; Builds an interpolated RGB triplet sequence on the stack from the
; double-buffered cache (palette A at +0, palette B at +0x300) and
; then forwards it to vga_dac_write_palette as the byte buffer.
;
; Per-byte recipe:
;   out = (B * w + A * (0x3F - w)) / 0x3F
; The triplet counter BL wraps 0..2 and rewinds BP by 3 between
; colour groups to share the second-palette row pointer.
; ============================================================================
vga_palette_lerp_dac PROC FAR
                PUSH    BP                      ; 55
                MOV     BP, SP                  ; 8B EC
                PUSH    DS                      ; 1E
                PUSH    DI                      ; 57
                PUSH    SI                      ; 56
                MOV     DS, cs:[0F4H]           ; 2E 8E 1E F4 00  scratch DS
                MOV     AX, [BP+8]              ; 8B 46 08  count
                PUSH    AX                      ; 50
                MOV     CX, AX                  ; 8B C8
                SHL     AX, 1                   ; D1 E0
                ADD     CX, AX                  ; 03 C8     CX = count*3 (RGB bytes)
                MOV     DL, [BP+0CH]            ; 8A 56 0C  weight
                MOV     DH, 03FH                ; B6 3F     scale denom
                MOV     DS, ds:[GfxContext.pPaletteScratchBuf+2]          ; 8E 1E A0 01  palette-cache seg
                MOV     AX, [BP+6]              ; 8B 46 06  start_idx
                PUSH    AX                      ; 50
                MOV     DI, AX                  ; 8B F8
                SHL     AX, 1                   ; D1 E0
                ADD     DI, AX                  ; 03 F8     DI = start_idx*3 (palette A)
                PUSH    DI                      ; 57
                MOV     SI, DI                  ; 8B F7
                ADD     SI, 0300H               ; 81 C6 00 03  SI = +0x300 (palette B)
                MOV     AX, [BP+0AH]            ; 8B 46 0A  dst_idx
                MOV     BP, 0300H               ; BD 00 03
                ADD     BP, AX                  ; 03 E8
                SHL     AX, 1                   ; D1 E0
                ADD     BP, AX                  ; 03 E8     BP = 0x300 + dst_idx*3
                PUSH    DS                      ; 1E
                POP     ES                      ; 07        ES := DS (cache seg)
                XOR     BX, BX                  ; 33 DB     BL = triplet phase (0..2)
vga_lerp_loop:
                XOR     AH, AH                  ; 32 E4
                LODSB                           ; AC        AL = palette-B byte
                MUL     DL                      ; F6 E2     * weight
                DIV     DH                      ; F6 F6     / 0x3F
                MOV     BH, AL                  ; 8A F8     stash term1
                MOV     AL, DL                  ; 8A C2
                MOV     DL, DH                  ; 8A D6
                SUB     DL, AL                  ; 2A D0     DL := 0x3F - weight
                XOR     AH, AH                  ; 32 E4
                MOV     AL, ds:[BP+0]           ; 3E 8A 46 00  palette-A byte
                MUL     DL                      ; F6 E2
                DIV     DH                      ; F6 F6
                ADD     AL, BH                  ; 02 C7     + term1
                STOSB                           ; AA
                MOV     AL, DL                  ; 8A C2
                MOV     DL, DH                  ; 8A D6
                SUB     DL, AL                  ; 2A D0     restore DL := weight
                INC     BP                      ; 45        advance palette-A pointer
                INC     BL                      ; FE C3
                CMP     BL, 3                   ; 80 FB 03
                JNZ     SHORT vga_lerp_next     ; 75 05
                XOR     BX, BX                  ; 33 DB
                SUB     BP, 3                   ; 83 ED 03  rewind for next triplet
vga_lerp_next:
                LOOP    SHORT vga_lerp_loop     ; E2 CF
                PUSH    CS                      ; 0E
                CALL    NEAR PTR vga_dac_write_palette ; E8 F6 FE
                ADD     SP, 6                   ; 83 C4 06  -- pop the 3 args we pushed
                ADD     SP, CX                  ; 03 E1     -- vestigial no-op:
                                                ;   This LOOKS like "release a CX-byte
                                                ;   stack scratch buffer", but no scratch
                                                ;   was ever allocated on the stack here.
                                                ;   STOSB above writes to ES:DI in the
                                                ;   palette-cache seg (ES := DS at the
                                                ;   PUSH DS / POP ES above), NOT the stack.
                                                ;
                                                ;   At runtime CX is always 0 here:
                                                ;   vga_dac_write_palette's
                                                ;   LOOP vga_dac_wp_loop only exits when
                                                ;   CX decrements to 0, and the callee
                                                ;   does not restore CX. So ADD SP, CX
                                                ;   reduces to ADD SP, 0 -- harmless.
                                                ;
                                                ;   Likely a leftover from an earlier
                                                ;   revision of the source where the
                                                ;   interpolated triplets were built on
                                                ;   the stack via PUSH and the callee
                                                ;   read them from there.
                POP     SI                      ; 5E
                POP     DI                      ; 5F
                POP     DS                      ; 1F
                POP     BP                      ; 5D
                RETF                            ; CB
vga_palette_lerp_dac ENDP

; ============================================================================
; vga_image_install -- compute aggregate image size.
; chunk:0x0E4C..0x0E7E
;
; ABI (__cdecl16far):
;   [BP+6]  word *image_descs_table   table of near pointers (NULL-terminated)
;   [BP+8]  word *out_status          out: cleared to 0
;
; Each descriptor entry: word[3] = width, word[4] = height (offsets +6/+8).
; Iterates the NULL-terminated descriptor-pointer array and sums
; width*height in DX:BX (long product). Returns total in DX:AX, stores
; 0 at *out_status.
; ============================================================================
vga_image_install PROC FAR
                PUSH    BP                      ; 55
                MOV     BP, SP                  ; 8B EC
                PUSH    SI                      ; 56
                PUSH    DI                      ; 57
                MOV     DI, [BP+6]              ; 8B 7E 06  descs table ptr
                XOR     BX, BX                  ; 33 DB     accumulator lo
                XOR     DX, DX                  ; 33 D2     accumulator hi
vga_imginst_loop:
                MOV     SI, [DI]                ; 8B 35
                OR      SI, SI                  ; 0B F6
                JZ      SHORT vga_imginst_done  ; 74 14
                PUSH    DX                      ; 52
                XOR     DX, DX                  ; 33 D2
                MOV     AX, [SI+6]              ; 8B 44 06  width
                MUL     WORD PTR [SI+8]         ; F7 64 08  * height
                POP     DX                      ; 5A
                ADD     BX, AX                  ; 03 D8
                ADC     DX, 0                   ; 83 D2 00
                ADD     DI, 2                   ; 83 C7 02
                JMP     SHORT vga_imginst_loop  ; EB E6
vga_imginst_done:
                MOV     AX, BX                  ; 8B C3
                MOV     SI, [BP+8]              ; 8B 76 08
                MOV     WORD PTR [SI], 0        ; C7 04 00 00
                POP     DI                      ; 5F
                POP     SI                      ; 5E
                POP     BP                      ; 5D
                RETF                            ; CB
vga_image_install ENDP

; ============================================================================
; vga_image_decode -- decode packed nibble image stream into VRAM (Mode-Y).
; chunk:0x0E7F..0x0F79
;
; ABI (__cdecl16far):
;   [BP+6]  word *image_descs_table    NULL-terminated descriptor list
;   [BP+8]  ushort dst_off             far destination pointer
;   [BP+0Ah]ushort dst_seg
;   [BP+0Ch]ushort src_off             far source pointer (nibble stream)
;   [BP+0Eh]ushort src_seg
;
; Phase 1 (0x0E84..0x0EC7): walk descriptors. For each non-null desc:
;   - desc[0] = far ptr of decoded region (computed from dst).
;   - desc[1] = byte offset within the 16-byte segment.
;   - dst += desc[+6] * desc[+8] (width * height).
;
; Phase 2 (0x0EC8..0x0F79): nibble-unpack from src (reverse order) into
; the destination, paired-pixel write per nibble byte. Heavy use of
; segment normalisation: any time DI/SI rolls below 0x1000 we move
; 0x1000 paragraphs to the next segment to keep the offset wrapping
; well-defined.
; ============================================================================
vga_image_decode PROC FAR
                PUSH    BP                      ; 55
                MOV     BP, SP                  ; 8B EC
                PUSH    SI                      ; 56
                PUSH    DI                      ; 57
                PUSH    DS                      ; 1E
                MOV     DI, [BP+8]              ; 8B 7E 08
                MOV     ES, [BP+0AH]            ; 8E 46 0A
vga_imgdec_walk:
                MOV     SI, [BP+6]              ; 8B 76 06
                MOV     SI, [SI]                ; 8B 34
                OR      SI, SI                  ; 0B F6
                JZ      SHORT vga_imgdec_phase2 ; 74 34
                MOV     DX, DI                  ; 8B D7
                MOV     AX, ES                  ; 8C C0
                MOV     CL, 4                   ; B1 04
                SHR     DX, CL                  ; D3 EA
                ADD     AX, DX                  ; 03 C2
                MOV     [SI], AX                ; 89 04     desc[0] = seg
                MOV     DX, DI                  ; 8B D7
                AND     DX, 0FH                 ; 83 E2 0F
                MOV     [SI+2], DX              ; 89 54 02  desc[1] = off
                MOV     AX, [SI+6]              ; 8B 44 06  width
                XOR     DX, DX                  ; 33 D2
                MUL     WORD PTR [SI+8]         ; F7 64 08  * height
                XOR     CX, CX                  ; 33 C9
                ADD     DI, AX                  ; 03 F8
                RCR     CX, 1                   ; D1 D9
                SHR     CX, 1                   ; D1 E9
                SHR     CX, 1                   ; D1 E9
                SHR     CX, 1                   ; D1 E9     -- CX = (carry << 12)
                MOV     AX, ES                  ; 8C C0
                ADD     AX, CX                  ; 03 C1
                MOV     ES, AX                  ; 8E C0
                ADD     WORD PTR [BP+6], 2      ; 83 46 06 02
                JMP     SHORT vga_imgdec_walk   ; EB C3

vga_imgdec_phase2:
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
                JNC     SHORT vga_imgdec_p2_noborr ; 73 03
                SUB     AX, 1000H               ; 2D 00 10
vga_imgdec_p2_noborr:
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
                JNC     SHORT vga_imgdec_p2_dnoborr ; 73 04
                SUB     DX, 1000H               ; 81 EA 00 10
vga_imgdec_p2_dnoborr:
                SHL     DX, 1                   ; D1 E2
                JNC     SHORT vga_imgdec_p2_nocarry ; 73 04
                ADD     BX, 1000H               ; 81 C3 00 10
vga_imgdec_p2_nocarry:
                ADD     DI, DX                  ; 03 FA
                RCR     CX, 1                   ; D1 D9
                SHR     CX, 1                   ; D1 E9
                SHR     CX, 1                   ; D1 E9
                SHR     CX, 1                   ; D1 E9
                ADD     BX, CX                  ; 03 D9
                ADD     AX, BX                  ; 03 C3
                MOV     ES, AX                  ; 8E C0

vga_imgdec_p2_loop:
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
                MOV     CL, 4                   ; B1 04
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
                JNZ     SHORT vga_imgdec_p2_loop ; 75 BC
                POP     DS                      ; 1F
                POP     DI                      ; 5F
                POP     SI                      ; 5E
                POP     BP                      ; 5D
                RETF                            ; CB
vga_image_decode ENDP

; ============================================================================
; vga_unpack_nibbles_to_planes -- nibble unpack with segment wrap.
; chunk:0x0F7A..0x0FCD
;
; ABI (__cdecl16far):
;   [BP+6:8]   far ptr src (DS:SI)
;   [BP+0A:0C] far ptr dst (ES:DI)
;   [BP+0Eh]   ushort count (loop iterations)
;
; Per iteration: read AL = ds:[SI++]; high nibble of AL goes into AH
; (shifted left 4), AL is kept; result ANDed with 0xF0F0 to mask out the
; high nibbles of both halves; ORed into es:[DI]; DI += 2. The carry-
; preserving SUB/SHR sequence normalises DS/ES after every SI/DI advance
; (same trick as vga_image_decode).
; ============================================================================
vga_unpack_nibbles_to_planes PROC FAR
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
vga_unp_loop:
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
                LOOP    SHORT vga_unp_loop      ; E2 C6
                POP     DS                      ; 1F
                POP     DI                      ; 5F
                POP     SI                      ; 5E
                POP     BP                      ; 5D
                RETF                            ; CB
vga_unpack_nibbles_to_planes ENDP

; ============================================================================
; vga_blit_sprite -- thin wrapper that calls vga_blit_sprite_master with
; flags=0 (no flips). chunk:0x0FCE..0x0FE7 (vtable slot 3).
;
; ABI (__cdecl16far):
;   [BP+6]   sprite descriptor offset
;   [BP+8]   dst_x
;   [BP+0Ah] dst_y
;
; PUSH 0; PUSH y; PUSH x; PUSH desc; PUSH CS; CALL NEAR master.
; ============================================================================
vga_blit_sprite PROC FAR
                PUSH    BP                      ; 55
                MOV     BP, SP                  ; 8B EC
                XOR     AX, AX                  ; 33 C0
                PUSH    AX                      ; 50      flags = 0
                PUSH    [BP+0AH]                ; FF 76 0A
                PUSH    [BP+8]                  ; FF 76 08
                PUSH    [BP+6]                  ; FF 76 06
                PUSH    CS                      ; 0E
                CALL    NEAR PTR vga_blit_sprite_master
                ADD     SP, 8                   ; 83 C4 08
                MOV     BP, SP                  ; 8B EC
                POP     BP                      ; 5D
                RETF                            ; CB
vga_blit_sprite ENDP

; ============================================================================
; vga_blit_glyph_row -- Mode-Y glyph (text) row blit.
; chunk:0x0FE8..0x10DC (vtable slot 1)
;
; ABI (register-passing):
;   BP       row index (multiplied by 2 to index the row LUT @ 6F2)
;   DX       x_start (pixel; DX/4 -> byte offset, DX&3 -> bit shift)
;   CX       row count
;   DS:SI    glyph row bytes (1 byte per row, 8 pixels)
;   ds:[GfxContext.bText_fg_color]   foreground colour byte (drawn through STOSB after Map Mask)
;   ds:[GfxContext.bText_bg_color]   background colour byte (used in shadow pass when ds:[GfxContext.bText_style_flags] != 0)
;   ds:[GfxContext.bText_style_flags]   "draw shadow first" flag (non-zero -> emit shadow pass)
;
; Per-row inner pump:
;   Glyph byte -> BH; iterate 8 bits: SHL BX,1 / RCR AH,1 etc. to slide
;   into AH; every 4 bits write AH to Map Mask (port 0x3C5) and STOSB
;   the colour byte; total of three writes per row (12 pixels span:
;   8 + 4 + tail). Row stride: DI += 0x4D (77 bytes = 320/4 - 3).
; ============================================================================
vga_blit_glyph_row PROC FAR
                PUSH    DI                      ; 57
                PUSH    BP                      ; 55
                PUSH    DS                      ; 1E
                PUSH    ES                      ; 06
                MOV     DS, cs:[0F4H]           ; 2E 8E 1E F4 00  scratch DS
                SHL     BP, 1                   ; D1 E5
                MOV     DI, ds:[BP].GfxContext.pRow_offset_lut       ; 3E 8B BE F2 06  row offset
                MOV     ES, ds:[GfxContext.wGfxBlitDstPage]            ; 8E 06 18 00     FB seg
                MOV     BP, CX                  ; 8B E9         row count
                MOV     BX, DX                  ; 8B DA         x_start
                MOV     DX, 03C4H               ; BA C4 03      Sequencer index
                MOV     AL, 2                   ; B0 02         reg 2 (Map Mask)
                OUT     DX, AL                  ; EE
                INC     DX                      ; 42            data port
                MOV     AX, BX                  ; 8B C3
                SHR     AX, 1                   ; D1 E8
                SHR     AX, 1                   ; D1 E8
                ADD     DI, AX                  ; 03 F8         DI += x/4
                MOV     CL, BL                  ; 8A CB
                AND     CL, 3                   ; 80 E1 03
                MOV     CH, ds:[GfxContext.bText_fg_color]              ; 8A 2E 00 00   foreground colour
                CMP     BYTE PTR ds:[GfxContext.bText_style_flags], 0      ; 80 3E 02 00
                JNZ     SHORT vga_bgr_fg_only   ; 75 62
                ; --- Shadow pass (background colour first) ---
                PUSH    DI                      ; 57
                PUSH    BX                      ; 53
                PUSH    BP                      ; 55
                PUSH    CX                      ; 51
                MOV     CH, ds:[GfxContext.bText_bg_color]              ; 8A 2E 01 00   background colour
vga_bgr_shadow_loop:
                MOV     BH, 0FFH                ; B7 FF
                XOR     BL, BL                  ; 32 DB
                SHR     BX, CL                  ; D3 EB         pre-shift
                ; --- first 8-bit lane -> AH ---
                SHL     BX, 1                   ; D1 E3
                RCR     AH, 1                   ; D0 DC
                SHL     BX, 1                   ; D1 E3
                RCR     AH, 1                   ; D0 DC
                SHL     BX, 1                   ; D1 E3
                RCR     AH, 1                   ; D0 DC
                SHL     BX, 1                   ; D1 E3
                RCR     AH, 1                   ; D0 DC
                SHL     BX, 1                   ; D1 E3
                RCR     AH, 1                   ; D0 DC
                SHL     BX, 1                   ; D1 E3
                RCR     AH, 1                   ; D0 DC
                SHL     BX, 1                   ; D1 E3
                RCR     AH, 1                   ; D0 DC
                SHL     BX, 1                   ; D1 E3
                RCR     AH, 1                   ; D0 DC
                MOV     AL, AH                  ; 8A C4
                OUT     DX, AL                  ; EE
                MOV     AL, CH                  ; 8A C5
                STOSB                           ; AA
                ; --- second 4-bit lane ---
                SHL     BX, 1                   ; D1 E3
                RCR     AH, 1                   ; D0 DC
                SHL     BX, 1                   ; D1 E3
                RCR     AH, 1                   ; D0 DC
                SHL     BX, 1                   ; D1 E3
                RCR     AH, 1                   ; D0 DC
                SHL     BX, 1                   ; D1 E3
                RCR     AH, 1                   ; D0 DC
                MOV     AL, AH                  ; 8A C4
                OUT     DX, AL                  ; EE
                MOV     AL, CH                  ; 8A C5
                STOSB                           ; AA
                ; --- tail 4-bit lane (just shift in 4 zeros) ---
                SHR     AH, 1                   ; D0 EC
                SHR     AH, 1                   ; D0 EC
                SHR     AH, 1                   ; D0 EC
                SHR     AH, 1                   ; D0 EC
                MOV     AL, AH                  ; 8A C4
                OUT     DX, AL                  ; EE
                MOV     AL, CH                  ; 8A C5
                STOSB                           ; AA
                ADD     DI, 4DH                 ; 83 C7 4D
                DEC     BP                      ; 4D
                JNZ     SHORT vga_bgr_shadow_loop ; 75 AA  -- next shadow row
                POP     CX                      ; 59
                POP     BP                      ; 5D
                POP     BX                      ; 5B
                POP     DI                      ; 5F
vga_bgr_fg_only:
                POP     DS                      ; 1F
                ; --- Foreground pass (CH = ds:[GfxContext.bText_fg_color] already loaded) ---
vga_bgr_fg_loop:
                MOV     BH, [SI]                ; 8A 3C       next glyph byte
                INC     SI                      ; 46
                XOR     BL, BL                  ; 32 DB
                SHR     BX, CL                  ; D3 EB
                SHL     BX, 1                   ; D1 E3
                RCR     AH, 1                   ; D0 DC
                SHL     BX, 1                   ; D1 E3
                RCR     AH, 1                   ; D0 DC
                SHL     BX, 1                   ; D1 E3
                RCR     AH, 1                   ; D0 DC
                SHL     BX, 1                   ; D1 E3
                RCR     AH, 1                   ; D0 DC
                SHL     BX, 1                   ; D1 E3
                RCR     AH, 1                   ; D0 DC
                SHL     BX, 1                   ; D1 E3
                RCR     AH, 1                   ; D0 DC
                SHL     BX, 1                   ; D1 E3
                RCR     AH, 1                   ; D0 DC
                SHL     BX, 1                   ; D1 E3
                RCR     AH, 1                   ; D0 DC
                MOV     AL, AH                  ; 8A C4
                OUT     DX, AL                  ; EE
                MOV     AL, CH                  ; 8A C5
                STOSB                           ; AA
                SHL     BX, 1                   ; D1 E3
                RCR     AH, 1                   ; D0 DC
                SHL     BX, 1                   ; D1 E3
                RCR     AH, 1                   ; D0 DC
                SHL     BX, 1                   ; D1 E3
                RCR     AH, 1                   ; D0 DC
                SHL     BX, 1                   ; D1 E3
                RCR     AH, 1                   ; D0 DC
                MOV     AL, AH                  ; 8A C4
                OUT     DX, AL                  ; EE
                MOV     AL, CH                  ; 8A C5
                STOSB                           ; AA
                SHR     AH, 1                   ; D0 EC
                SHR     AH, 1                   ; D0 EC
                SHR     AH, 1                   ; D0 EC
                SHR     AH, 1                   ; D0 EC
                MOV     AL, AH                  ; 8A C4
                OUT     DX, AL                  ; EE
                MOV     AL, CH                  ; 8A C5
                STOSB                           ; AA
                ADD     DI, 4DH                 ; 83 C7 4D
                DEC     BP                      ; 4D
                JNZ     SHORT vga_bgr_fg_loop   ; 75 A9
                POP     DS                      ; 1F
                POP     BP                      ; 5D
                POP     DI                      ; 5F
                RETF                            ; CB
vga_blit_glyph_row ENDP

; ============================================================================
; vga_save_rect -- save a planar rectangle from VRAM to a buffer.
; chunk:0x10DD..0x11B0
;
; ABI (__cdecl16far):
;   [BP+6:8]   far ptr dst_buffer
;   [BP+0Ah]   x_start (pixel)
;   [BP+0Ch]   y_start (row)
;   [BP+0Eh]   width  (pixels)
;   [BP+10h]   height (rows)
;
; Builds 4 frame locals (CX=width, DI=dst_off_local, BX=src_off_local)
; via PUSH AX/DI/SI, then runs a per-row 4-plane unroll:
;   for each plane k in 0..3:
;     OUT 0x3CF, plane_select; REP MOVSB stride-3 into dst.
; Source plane increments wrap via INC BX when plane wraps 4->0.
; ============================================================================
vga_save_rect PROC FAR
                PUSH    BP                      ; 55
                MOV     BP, SP                  ; 8B EC
                PUSH    DI                      ; 57
                PUSH    SI                      ; 56
                PUSH    DS                      ; 1E
                MOV     DS, cs:[0F4H]           ; 2E 8E 1E F4 00
                MOV     AX, [BP+0AH]            ; 8B 46 0A   x_start
                MOV     BX, [BP+0CH]            ; 8B 5E 0C   y_start
                SHL     BX, 1                   ; D1 E3
                MOV     SI, [BX].GfxContext.pRow_offset_lut          ; 8B B7 F2 06  row LUT
                MOV     BX, AX                  ; 8B D8
                SHR     AX, 1                   ; D1 E8
                SHR     AX, 1                   ; D1 E8
                ADD     SI, AX                  ; 03 F0      SI = src offset
                AND     BX, 3                   ; 83 E3 03   BX = plane index 0..3
                MOV     DX, 03CEH               ; BA CE 03   GC index
                MOV     AL, 4                   ; B0 04      reg 4 = Read Plane Select
                OUT     DX, AL                  ; EE
                INC     DX                      ; 42         data port
                MOV     AX, [BP+0EH]            ; 8B 46 0E   width
                PUSH    AX                      ; 50         local [BP-8]
                MOV     DI, [BP+6]              ; 8B 7E 06   dst_off
                MOV     AX, [BP+8]              ; 8B 46 08   dst_seg
                MOV     ES, AX                  ; 8E C0
                MOV     AX, ds:[GfxContext.wGfxBlitSrcPage]            ; A1 16 00   FB seg
                MOV     DS, AX                  ; 8E D8
                MOV     AH, BL                  ; 8A E3      AH = starting plane
                PUSH    DI                      ; 57         local [BP-0xA]
                PUSH    SI                      ; 56         local [BP-0xC]
vga_savrect_row:
                MOV     AL, AH                  ; 8A C4
                MOV     CX, [BP-8]              ; 8B 4E F8   width
                MOV     DI, [BP-0AH]            ; 8B 7E F6   dst off (local)
                MOV     BX, [BP-0CH]            ; 8B 5E F4   src off (local)
                MOV     SI, BX                  ; 8B F3
                ADD     CX, 3                   ; 83 C1 03
                SHR     CX, 1                   ; D1 E9
                SHR     CX, 1                   ; D1 E9     -- bytes for plane 0 = (w+3)/4
                OUT     DX, AL                  ; EE
vga_savrect_p0:
                MOVSB                           ; A4
                ADD     DI, 3                   ; 83 C7 03
                LOOP    SHORT vga_savrect_p0    ; E2 FA
                INC     AL                      ; FE C0
                AND     AL, 3                   ; 24 03
                JNZ     SHORT vga_savrect_p1_setup ; 75 01
                INC     BX                      ; 43        plane wrap -> next src byte
vga_savrect_p1_setup:
                MOV     CX, [BP-8]              ; 8B 4E F8
                MOV     DI, [BP-0AH]            ; 8B 7E F6
                INC     DI                      ; 47
                MOV     SI, BX                  ; 8B F3
                ADD     CX, 2                   ; 83 C1 02
                SHR     CX, 1                   ; D1 E9
                SHR     CX, 1                   ; D1 E9
                JZ      SHORT vga_savrect_step  ; 74 48
                OUT     DX, AL                  ; EE
vga_savrect_p1:
                MOVSB                           ; A4
                ADD     DI, 3                   ; 83 C7 03
                LOOP    SHORT vga_savrect_p1    ; E2 FA
                INC     AL                      ; FE C0
                AND     AL, 3                   ; 24 03
                JNZ     SHORT vga_savrect_p2_setup ; 75 01
                INC     BX                      ; 43
vga_savrect_p2_setup:
                MOV     CX, [BP-8]              ; 8B 4E F8
                MOV     DI, [BP-0AH]            ; 8B 7E F6
                ADD     DI, 2                   ; 83 C7 02
                MOV     SI, BX                  ; 8B F3
                ADD     CX, 1                   ; 83 C1 01
                SHR     CX, 1                   ; D1 E9
                SHR     CX, 1                   ; D1 E9
                JZ      SHORT vga_savrect_step  ; 74 26
                OUT     DX, AL                  ; EE
vga_savrect_p2:
                MOVSB                           ; A4
                ADD     DI, 3                   ; 83 C7 03
                LOOP    SHORT vga_savrect_p2    ; E2 FA
                INC     AL                      ; FE C0
                AND     AL, 3                   ; 24 03
                JNZ     SHORT vga_savrect_p3_setup ; 75 01
                INC     BX                      ; 43
vga_savrect_p3_setup:
                MOV     CX, [BP-8]              ; 8B 4E F8
                MOV     DI, [BP-0AH]            ; 8B 7E F6
                ADD     DI, 3                   ; 83 C7 03
                MOV     SI, BX                  ; 8B F3
                SHR     CX, 1                   ; D1 E9
                SHR     CX, 1                   ; D1 E9
                JZ      SHORT vga_savrect_step  ; 74 07
                OUT     DX, AL                  ; EE
vga_savrect_p3:
                MOVSB                           ; A4
                ADD     DI, 3                   ; 83 C7 03
                LOOP    SHORT vga_savrect_p3    ; E2 FA
vga_savrect_step:
                MOV     CX, [BP-8]              ; 8B 4E F8
                ADD     [BP-0AH], CX            ; 01 4E F6
                ADD     WORD PTR [BP-0CH], 50H  ; 83 46 F4 50  src += 80 (next row)
                DEC     WORD PTR [BP+10H]       ; FF 4E 10
                JZ      SHORT vga_savrect_done  ; 74 03
                JMP     vga_savrect_row         ; E9 72 FF
vga_savrect_done:
                ADD     SP, 6                   ; 83 C4 06
                POP     DS                      ; 1F
                POP     SI                      ; 5E
                POP     DI                      ; 5F
                POP     BP                      ; 5D
                RETF                            ; CB
vga_save_rect ENDP

; ============================================================================
; vga_blit_size -- return rectangle byte size as long (DX:AX).
; chunk:0x11B1..0x11BC
;
; ABI (__cdecl16far): [BP+6]=width, [BP+8]=height -> DX:AX = width*height (signed).
; ============================================================================
vga_blit_size PROC FAR
                PUSH    BP                      ; 55
                MOV     BP, SP                  ; 8B EC
                MOV     AX, [BP+6]              ; 8B 46 06
                CWD                             ; 99
                MUL     WORD PTR [BP+8]         ; F7 66 08
                POP     BP                      ; 5D
                RETF                            ; CB
vga_blit_size ENDP

; ============================================================================
; vga_paste_rect -- mirror of vga_save_rect, in the other direction.
; chunk:0x11BD..0x128E
;
; ABI (__cdecl16far):
;   [BP+6:8]   far ptr src_buffer
;   [BP+0Ah]   x_start
;   [BP+0Ch]   y_start
;   [BP+0Eh]   width
;   [BP+10h]   height
;
; Uses Sequencer Map Mask (port 0x3C5) directly with a rotating mask.
; The mask is seeded with 0x11 (binary 0001 0001) and ROLed by CL on
; entry, then by 1 per plane. The 0x11 seed has bits 0 AND 4 set so
; that after any 0..3-bit rotation exactly one bit lands in the low
; nibble (the VGA Map Mask only uses bits 0..3 -- planes 0..3 -- so
; the bit-4 copy is harmless). When the rotate carries out of bit 7
; back into bit 0, CF is set; ADC BX, 0 then advances the destination
; byte address by 1, modelling the "plane wrap -> next byte" boundary.
; ============================================================================
vga_paste_rect PROC FAR
                PUSH    BP                      ; 55
                MOV     BP, SP                  ; 8B EC
                PUSH    SI                      ; 56
                PUSH    DI                      ; 57
                PUSH    DS                      ; 1E
                MOV     DS, cs:[0F4H]           ; 2E 8E 1E F4 00
                MOV     AX, [BP+0AH]            ; 8B 46 0A
                MOV     BX, [BP+0CH]            ; 8B 5E 0C
                SHL     BX, 1                   ; D1 E3
                MOV     DI, [BX].GfxContext.pRow_offset_lut          ; 8B BF F2 06
                MOV     BX, AX                  ; 8B D8
                SHR     AX, 1                   ; D1 E8
                SHR     AX, 1                   ; D1 E8
                ADD     DI, AX                  ; 03 F8
                AND     BX, 3                   ; 83 E3 03
                MOV     CX, BX                  ; 8B CB     CL = plane shift count
                MOV     DX, 03C4H               ; BA C4 03  Sequencer index
                MOV     AL, 2                   ; B0 02     reg 2 (Map Mask)
                OUT     DX, AL                  ; EE
                INC     DX                      ; 42
                MOV     AX, [BP+0EH]            ; 8B 46 0E  width
                PUSH    AX                      ; 50        local [BP-8]
                MOV     SI, [BP+6]              ; 8B 76 06  src_off
                MOV     AX, ds:[GfxContext.wGfxBlitDstPage]            ; A1 18 00  FB seg
                MOV     ES, AX                  ; 8E C0
                MOV     AX, [BP+8]              ; 8B 46 08  src_seg
                MOV     DS, AX                  ; 8E D8
                MOV     AH, 11H                 ; B4 11     mask seed 0001 0001 (see plate)
                ROL     AH, CL                  ; D2 C4
                PUSH    DI                      ; 57        local [BP-0xA]
                PUSH    SI                      ; 56        local [BP-0xC]
vga_pastrect_row:
                MOV     AL, AH                  ; 8A C4
                MOV     CX, [BP-8]              ; 8B 4E F8
                MOV     DI, [BP-0AH]            ; 8B 7E F6
                MOV     SI, [BP-0CH]            ; 8B 76 F4
                MOV     BX, DI                  ; 8B DF
                OUT     DX, AL                  ; EE
                ADD     CX, 3                   ; 83 C1 03
                SHR     CX, 1                   ; D1 E9
                SHR     CX, 1                   ; D1 E9
vga_pastrect_p0:
                MOVSB                           ; A4
                ADD     SI, 3                   ; 83 C6 03
                LOOP    SHORT vga_pastrect_p0   ; E2 FA
                MOV     CX, [BP-8]              ; 8B 4E F8
                MOV     SI, [BP-0CH]            ; 8B 76 F4
                INC     SI                      ; 46
                ROL     AL, 1                   ; D0 C0
                ADC     BX, 0                   ; 83 D3 00
                MOV     DI, BX                  ; 8B FB
                OUT     DX, AL                  ; EE
                ADD     CX, 2                   ; 83 C1 02
                SHR     CX, 1                   ; D1 E9
                SHR     CX, 1                   ; D1 E9
                JZ      SHORT vga_pastrect_step ; 74 43
vga_pastrect_p1:
                MOVSB                           ; A4
                ADD     SI, 3                   ; 83 C6 03
                LOOP    SHORT vga_pastrect_p1   ; E2 FA
                MOV     CX, [BP-8]              ; 8B 4E F8
                MOV     SI, [BP-0CH]            ; 8B 76 F4
                ADD     SI, 2                   ; 83 C6 02
                ROL     AL, 1                   ; D0 C0
                ADC     BX, 0                   ; 83 D3 00
                MOV     DI, BX                  ; 8B FB
                OUT     DX, AL                  ; EE
                ADD     CX, 1                   ; 83 C1 01
                SHR     CX, 1                   ; D1 E9
                SHR     CX, 1                   ; D1 E9
                JZ      SHORT vga_pastrect_step ; 74 23
vga_pastrect_p2:
                MOVSB                           ; A4
                ADD     SI, 3                   ; 83 C6 03
                LOOP    SHORT vga_pastrect_p2   ; E2 FA
                MOV     CX, [BP-8]              ; 8B 4E F8
                MOV     SI, [BP-0CH]            ; 8B 76 F4
                ADD     SI, 3                   ; 83 C6 03
                ROL     AL, 1                   ; D0 C0
                ADC     BX, 0                   ; 83 D3 00
                MOV     DI, BX                  ; 8B FB
                OUT     DX, AL                  ; EE
                SHR     CX, 1                   ; D1 E9
                SHR     CX, 1                   ; D1 E9
                JZ      SHORT vga_pastrect_step ; 74 06
vga_pastrect_p3:
                MOVSB                           ; A4
                ADD     SI, 3                   ; 83 C6 03
                LOOP    SHORT vga_pastrect_p3   ; E2 FA
vga_pastrect_step:
                MOV     CX, [BP-8]              ; 8B 4E F8
                ADD     [BP-0CH], CX            ; 01 4E F4
                ADD     WORD PTR [BP-0AH], 50H  ; 83 46 F6 50
                DEC     WORD PTR [BP+10H]       ; FF 4E 10
                JZ      SHORT vga_pastrect_done ; 74 03
                JMP     vga_pastrect_row        ; E9 78 FF
vga_pastrect_done:
                ADD     SP, 6                   ; 83 C4 06
                POP     DS                      ; 1F
                POP     DI                      ; 5F
                POP     SI                      ; 5E
                POP     BP                      ; 5D
                RETF                            ; CB
vga_paste_rect ENDP

; ============================================================================
; vga_getpixel -- read one pixel.
; chunk:0x128F..0x12C4
;
; ABI (__cdecl16far): [BP+6]=x, [BP+8]=y -> AX = pixel colour byte.
;
; Selects plane (x & 3) via GC Read Plane Select (reg 4), then reads
; one byte from VRAM at row[y] + x/4.
; ============================================================================
vga_getpixel PROC FAR
                PUSH    BP                      ; 55
                MOV     BP, SP                  ; 8B EC
                PUSH    DS                      ; 1E
                MOV     DS, cs:[0F4H]           ; 2E 8E 1E F4 00
                MOV     BX, [BP+8]              ; 8B 5E 08    y
                SHL     BX, 1                   ; D1 E3
                MOV     BX, [BX].GfxContext.pRow_offset_lut          ; 8B 9F F2 06  row offset
                MOV     AX, [BP+6]              ; 8B 46 06    x
                AND     AX, 3                   ; 25 03 00
                MOV     DX, 03CEH               ; BA CE 03    GC index
                MOV     AH, AL                  ; 8A E0       plane idx
                MOV     AL, 4                   ; B0 04       reg 4 = Read Plane Select
                OUT     DX, AX                  ; EF
                MOV     AX, [BP+6]              ; 8B 46 06
                SHR     AX, 1                   ; D1 E8
                SHR     AX, 1                   ; D1 E8
                ADD     BX, AX                  ; 03 D8
                MOV     AX, ds:[GfxContext.wGfxBlitSrcPage]            ; A1 16 00    FB seg
                MOV     ES, AX                  ; 8E C0
                MOV     AL, es:[BX]             ; 26 8A 07
                XOR     AH, AH                  ; 32 E4
                POP     DS                      ; 1F
                POP     BP                      ; 5D
                RETF                            ; CB
vga_getpixel ENDP

; ============================================================================
; vga_putpixel -- write one pixel.
; chunk:0x12C5..0x12FC
;
; ABI (__cdecl16far): [BP+6]=x, [BP+8]=y, [BP+0Ah]=colour (byte).
;
; Selects plane (x & 3) via Sequencer Map Mask (reg 2, mask = 1 << (x&3)).
; ============================================================================
vga_putpixel PROC FAR
                PUSH    BP                      ; 55
                MOV     BP, SP                  ; 8B EC
                PUSH    DS                      ; 1E
                MOV     DS, cs:[0F4H]           ; 2E 8E 1E F4 00
                MOV     BX, [BP+8]              ; 8B 5E 08
                SHL     BX, 1                   ; D1 E3
                MOV     BX, [BX].GfxContext.pRow_offset_lut          ; 8B 9F F2 06
                MOV     CX, [BP+6]              ; 8B 4E 06
                AND     CX, 3                   ; 83 E1 03
                MOV     DX, 03C4H               ; BA C4 03   Sequencer index
                MOV     AX, 0102H               ; B8 02 01   AL=reg 2, AH=mask=1
                SHL     AH, CL                  ; D2 E4
                OUT     DX, AX                  ; EF
                MOV     AX, [BP+6]              ; 8B 46 06
                SHR     AX, 1                   ; D1 E8
                SHR     AX, 1                   ; D1 E8
                ADD     BX, AX                  ; 03 D8
                MOV     AX, ds:[GfxContext.wGfxBlitDstPage]            ; A1 18 00
                MOV     ES, AX                  ; 8E C0
                MOV     AL, [BP+0AH]            ; 8A 46 0A
                MOV     es:[BX], AL             ; 26 88 07
                POP     DS                      ; 1F
                POP     BP                      ; 5D
                RETF                            ; CB
vga_putpixel ENDP

; ============================================================================
; vga_vsync_wait -- page flip + vsync wait.
; chunk:0x12FD..0x1352 (vtable slot 8)
;
; ABI (__cdecl16far): [BP+6] = wait_flag (non-zero -> poll vsync).
;
; Body:
;   1. Swap front (ds:[0x14]) and back (ds:[0x12]) buffer segments.
;   2. CRTC Start-Address-High/Low write (regs 0x0C/0x0D) so the new
;      visible page is the old back buffer. Address comes from the
;      paragraph-sized buffer seg, divided by 16 (4x SHR/RCR).
;   3. Read the BIOS data area's CRT port from 40:63 (the BIOS-
;      detected CRTC base, 0x3B4 on monochrome / 0x3D4 on colour
;      boards; we know we're colour but the BIOS-stored value
;      handles cards that vary).
;   4. If wait_flag != 0, poll port 0x3DA bit 3 (vertical retrace
;      bit per IBM VGA/XGA TR Input Status 1) until LOW, then until
;      HIGH. This catches the leading edge of vretrace (not the
;      middle), giving the longest possible "safe to write CRTC
;      regs" window before the active video resumes. See Abrash
;      GPBB ch.23.
; ============================================================================
vga_vsync_wait PROC FAR
                PUSH    BP                      ; 55
                MOV     BP, SP                  ; 8B EC
                PUSH    ES                      ; 06
                PUSH    DS                      ; 1E
                MOV     DS, cs:[0F4H]           ; 2E 8E 1E F4 00
                MOV     AX, ds:[GfxContext.wVgaPage2Base]            ; A1 12 00     back buffer seg
                MOV     CX, AX                  ; 8B C8
                XCHG    AX, ds:[GfxContext.wVgaFrontPageBase]            ; 87 06 14 00  swap with front
                MOV     ds:[GfxContext.wVgaPage2Base], AX            ; A3 12 00
                XOR     BX, BX                  ; 33 DB
                SHR     CX, 1                   ; D1 E9
                RCR     BX, 1                   ; D1 DB
                SHR     CX, 1                   ; D1 E9
                RCR     BX, 1                   ; D1 DB
                SHR     CX, 1                   ; D1 E9
                RCR     BX, 1                   ; D1 DB
                SHR     CX, 1                   ; D1 E9
                RCR     BX, 1                   ; D1 DB    -- CX:BX = seg << 12, divided 4x
                MOV     AX, 40H                 ; B8 40 00
                MOV     ES, AX                  ; 8E C0
                MOV     DX, es:[63H]            ; 26 8B 16 63 00   BIOS CRTC port
                MOV     AL, 0CH                 ; B0 0C    -- Start Addr High
                MOV     AH, CL                  ; 8A E1
                OUT     DX, AX                  ; EF
                INC     AL                      ; FE C0    -- 0Dh = Start Addr Low
                MOV     AH, BH                  ; 8A E7
                OUT     DX, AX                  ; EF
                MOV     AX, [BP+6]              ; 8B 46 06
                OR      AX, AX                  ; 0B C0
                JZ      SHORT vga_vsync_done    ; 74 0F
                MOV     CL, 8                   ; B1 08
                MOV     DX, 03DAH               ; BA DA 03
vga_vsync_wait_low:
                IN      AL, DX                  ; EC
                AND     AL, CL                  ; 22 C1
                JNZ     SHORT vga_vsync_wait_low ; 75 FB
vga_vsync_wait_high:
                IN      AL, DX                  ; EC
                AND     AL, CL                  ; 22 C1
                JZ      SHORT vga_vsync_wait_high ; 74 FB
vga_vsync_done:
                POP     DS                      ; 1F
                POP     ES                      ; 07
                POP     BP                      ; 5D
                RETF                            ; CB
vga_vsync_wait ENDP

; ============================================================================
; vga_present -- rectangular copy from back buffer to front buffer using
; the GC write-mode-1 (latch copy) trick.
; chunk:0x1353..0x13B8 (vtable slot 5)
;
; ABI (__cdecl16far):
;   [BP+6]   x_start
;   [BP+8]   y_start
;   [BP+0Ah] width
;   [BP+0Ch] height
;
; Body:
;   1. Set Map Mask = 0Fh (all 4 planes enabled), GC Mode := 41h
;      (Write Mode 1 = "CPU writes copy the latch contents to the
;      planes"; Shift256 bit 6 stays set). Each MOVSB byte then
;      reads source -> 4 latches, writes dst -> 4 pixels at once.
;   2. For each row: MOVSB CX times (DS=back, ES=front -- one byte
;      per stride moves 4 pixels through the latches).
;   3. Restore GC Mode := 40h (Write Mode 0, Shift256 still set).
;      See FreeVGA GR5 reference / Abrash GPBB ch.48 for the latch-
;      copy idiom and ch.47 for the Shift256 semantics.
; ============================================================================
vga_present PROC FAR
                PUSH    BP                      ; 55
                MOV     BP, SP                  ; 8B EC
                PUSH    SI                      ; 56
                PUSH    DI                      ; 57
                PUSH    DS                      ; 1E
                MOV     DS, cs:[0F4H]           ; 2E 8E 1E F4 00
                MOV     SI, [BP+6]              ; 8B 76 06   x_start
                MOV     BX, SI                  ; 8B DE
                AND     BX, 3                   ; 83 E3 03
                ADD     BX, [BP+0AH]            ; 03 5E 0A   + width
                MOV     DX, [BP+0CH]            ; 8B 56 0C   height
                MOV     BP, [BP+8]              ; 8B 6E 08   y_start
                SHL     BP, 1                   ; D1 E5
                MOV     BP, ds:[BP].GfxContext.pRow_offset_lut       ; 3E 8B AE F2 06  row offset
                MOV     AX, ds:[GfxContext.wGfxBlitDstPage]            ; A1 18 00   FB seg (back)
                MOV     ES, AX                  ; 8E C0
                MOV     AX, ds:[GfxContext.wGfxBlitSrcPage]            ; A1 16 00   FB seg (front)
                MOV     DS, AX                  ; 8E D8
                MOV     AX, SI                  ; 8B C6
                SHR     SI, 1                   ; D1 EE
                SHR     SI, 1                   ; D1 EE     SI = x/4
                ADD     BX, 3                   ; 83 C3 03
                SHR     BX, 1                   ; D1 EB
                SHR     BX, 1                   ; D1 EB     BX = (x%4+w+3)/4 = byte width
                ADD     BP, SI                  ; 03 EE
                PUSH    DX                      ; 52
                MOV     DX, 03C4H               ; BA C4 03
                MOV     AX, 0F02H               ; B8 02 0F   Map Mask = 0F (all planes)
                OUT     DX, AX                  ; EF
                MOV     DX, 03CEH               ; BA CE 03
                MOV     AX, 4105H               ; B8 05 41   GR5 = 41h: WM=01 (latch copy), Shift256=1
                OUT     DX, AX                  ; EF
                POP     DX                      ; 5A
vga_present_row:
                MOV     SI, BP                  ; 8B F5
                MOV     DI, SI                  ; 8B FE
                MOV     CX, BX                  ; 8B CB
                REP     MOVSB                   ; F3 A4     -- each MOVSB copies 4 pixels via latches
                ADD     BP, 50H                 ; 83 C5 50  next row (stride 80 = 320/4)
                DEC     DX                      ; 4A
                JNZ     SHORT vga_present_row   ; 75 F2
                MOV     DX, 03CEH               ; BA CE 03
                MOV     AX, 4005H               ; B8 05 40  GR5 = 40h: WM=00 (normal), Shift256=1
                OUT     DX, AX                  ; EF
                POP     DS                      ; 1F
                POP     DI                      ; 5F
                POP     SI                      ; 5E
                POP     BP                      ; 5D
                RETF                            ; CB
vga_present ENDP

; ============================================================================
; vga_blit_rect_buffer scratch & edge-mask LUT.
; chunk:0x13B9..0x13C2 (4 ushorts + 4 bytes; zero on disk except mask)
;
; Globals consumed by vga_blit_rect_buffer below.
; ============================================================================
g_wVgaRectBufferRowStride       DW      0       ; 0x13B9
g_wVgaRectBufferPlaneCount      DW      0       ; 0x13BB
g_wVgaRectBufferOffset          DW      0       ; 0x13BD
g_abVgaRectBufferEdgeMaskLut    DB      0FH, 01H, 03H, 07H  ; 0x13BF

; ============================================================================
; vga_blit_rect_buffer -- multi-row composite blitter using GC write-mode 1.
; chunk:0x13C3..0x14A1
;
; ABI (register-passing):
;   ES:SI -> command stream { row_y_first: word, row_count: word,
;                             { x_start: word, x_end: word }* rows }
;
; Each row reads the back-buffer-cache at +g_wVgaRectBufferOffset and
; copies the planar bytes to the visible plane at DI. Per-row split:
;   - one-byte span -> compose mask, single MOVSB.
;   - multi-byte span -> left edge mask + REP MOVSB + right edge mask.
; ============================================================================
vga_blit_rect_buffer PROC FAR
                PUSH    BP                      ; 55
                PUSH    DI                      ; 57
                PUSH    DS                      ; 1E
                MOV     BP, SI                  ; 8B EE
                MOV     DS, cs:[0F4H]           ; 2E 8E 1E F4 00
                MOV     AX, ds:[GfxContext.wGfxBlitDstPage]            ; A1 18 00     FB seg (back)
                MOV     cs:[13BBH], AX          ; 2E A3 BB 13
                MOV     AX, ds:[GfxContext.wGfxBlitSrcPage]            ; A1 16 00     front seg
                MOV     BX, es:[BP+0]           ; 26 8B 5E 00
                SHL     BX, 1                   ; D1 E3
                MOV     DI, [BX].GfxContext.pRow_offset_lut          ; 8B BF F2 06
                MOV     DS, AX                  ; 8E D8
                MOV     DX, 03CEH               ; BA CE 03
                MOV     AX, 4105H               ; B8 05 41   GR5 = 41h: WM=01 (latch copy), Shift256=1
                OUT     DX, AX                  ; EF
                MOV     DX, 03C4H               ; BA C4 03
                MOV     AL, 2                   ; B0 02      Sequencer Map Mask reg
                OUT     DX, AL                  ; EE
                INC     DX                      ; 42
                MOV     AX, es:[BP+2]           ; 26 8B 46 02  row_count
                MOV     cs:[13B9H], AX          ; 2E A3 B9 13
                ADD     BP, 4                   ; 83 C5 04
vga_brbuf_row:
                MOV     AX, es:[BP+0]           ; 26 8B 46 00  x_start
                MOV     BX, es:[BP+2]           ; 26 8B 5E 02  x_end
                MOV     CX, AX                  ; 8B C8
                ADD     BP, 4                   ; 83 C5 04
                XOR     AX, BX                  ; 33 C3
                AND     AX, 0FFCH               ; 25 FC 0F
                MOV     AX, CX                  ; 8B C1
                JNZ     SHORT vga_brbuf_multi   ; 75 36
                ; --- one-byte span (start & end in same plane group) ---
                PUSH    ES                      ; 06
                PUSH    DI                      ; 57
                MOV     ES, cs:[13BBH]          ; 2E 8E 06 BB 13
                MOV     CX, AX                  ; 8B C8
                SHR     AX, 1                   ; D1 E8
                SHR     AX, 1                   ; D1 E8
                ADD     DI, AX                  ; 03 F8
                AND     CX, 3                   ; 83 E1 03
                MOV     AL, 0FH                 ; B0 0F
                SHL     AL, CL                  ; D2 E0
                INC     BX                      ; 43
                AND     BX, 3                   ; 83 E3 03
                AND     AL, cs:[BX+13BFH]       ; 2E 22 87 BF 13
                OUT     DX, AL                  ; EE
                MOV     SI, DI                  ; 8B F7
                ADD     SI, cs:[13BDH]          ; 2E 03 36 BD 13
                MOVSB                           ; A4
                POP     DI                      ; 5F
                ADD     DI, 50H                 ; 83 C7 50
                POP     ES                      ; 07
                DEC     WORD PTR cs:[13B9H]     ; 2E FF 0E B9 13
                JNZ     SHORT vga_brbuf_row     ; 75 B6
                JMP     SHORT vga_brbuf_done    ; EB 4F
                ; --- multi-byte span ---
vga_brbuf_multi:
                PUSH    ES                      ; 06
                PUSH    DI                      ; 57
                MOV     ES, cs:[13BBH]          ; 2E 8E 06 BB 13
                MOV     CX, AX                  ; 8B C8
                AND     CX, 3                   ; 83 E1 03
                SUB     BX, AX                  ; 2B D8
                JLE     SHORT vga_brbuf_step    ; 7E 30
                SHR     AX, 1                   ; D1 E8
                SHR     AX, 1                   ; D1 E8
                ADD     DI, AX                  ; 03 F8
                MOV     AL, 0FH                 ; B0 0F
                SHL     AL, CL                  ; D2 E0
                SUB     CX, 3                   ; 83 E9 03
                ADD     BX, CX                  ; 03 D9
                OUT     DX, AL                  ; EE
                MOV     SI, DI                  ; 8B F7
                ADD     SI, cs:[13BDH]          ; 2E 03 36 BD 13
                MOVSB                           ; A4
                MOV     CX, BX                  ; 8B CB
                SHR     CX, 1                   ; D1 E9
                SHR     CX, 1                   ; D1 E9
                MOV     AL, 0FH                 ; B0 0F
                OUT     DX, AL                  ; EE
                REP     MOVSB                   ; F3 A4
                MOV     CX, BX                  ; 8B CB
                AND     CX, 3                   ; 83 E1 03
                JZ      SHORT vga_brbuf_step    ; 74 06
                MOV     AL, 0F0H                ; B0 F0
                ROL     AL, CL                  ; D2 C0
                OUT     DX, AL                  ; EE
                MOVSB                           ; A4
vga_brbuf_step:
                POP     DI                      ; 5F
                ADD     DI, 50H                 ; 83 C7 50
                POP     ES                      ; 07
                DEC     WORD PTR cs:[13B9H]     ; 2E FF 0E B9 13
                JZ      SHORT vga_brbuf_done    ; 74 03
                JMP     vga_brbuf_row           ; E9 65 FF
vga_brbuf_done:
                MOV     DX, 03CEH               ; BA CE 03
                MOV     AX, 4005H               ; B8 05 40   GR5 = 40h: WM=00 (normal), Shift256=1
                OUT     DX, AX                  ; EF
                POP     DS                      ; 1F
                POP     DI                      ; 5F
                POP     BP                      ; 5D
                RETF                            ; CB
vga_blit_rect_buffer ENDP

; ============================================================================
; vga_set_buffer_offset -- compute and stash the rect-buffer source offset.
; chunk:0x14A2..0x14BC
;
; ABI (__cdecl16far):
;   [BP+6] short x_in_pixels
;   [BP+8] short y_row
;
; Computes y*80 + x/4 and stores it at g_wVgaRectBufferOffset (0x13BD)
; -- consumed by vga_blit_rect_buffer's `ADD SI, cs:[13BDH]`.
; ============================================================================
vga_set_buffer_offset PROC FAR
                PUSH    BP                      ; 55
                MOV     BP, SP                  ; 8B EC
                MOV     AX, [BP+8]              ; 8B 46 08
                CWD                             ; 99
                MOV     BX, 50H                 ; BB 50 00
                MUL     BX                      ; F7 E3
                MOV     BX, [BP+6]              ; 8B 5E 06
                SAR     BX, 1                   ; D1 FB
                SAR     BX, 1                   ; D1 FB
                ADD     AX, BX                  ; 03 C3
                MOV     cs:[13BDH], AX          ; 2E A3 BD 13
                POP     BP                      ; 5D
                RETF                            ; CB
vga_set_buffer_offset ENDP

; ============================================================================
; vga_blit_chunky -- nibble-pair (chunky 4-bit) -> Mode-Y planar blit.
; chunk:0x14BD..0x156B
;
; ABI (__cdecl16far): big stack frame; uses [BP+0x0E:0x10] as far-ptr to
; source nibbles, [BP+0x12]/[BP+0x14] = dst position, [BP+0x16] =
; width (in *bytes* of source = 2 pixels each), [BP+0x18] = height.
;
; Per row: emit 4 pixels per source byte via 2 different Map Mask
; values (0x01, 0x02 then again with shifted CX). The shift+rotate
; dance turns a chunky 4bpp byte into two 4-bit packed planar pairs.
; ============================================================================
vga_blit_chunky PROC FAR
                PUSH    BP                      ; 55
                PUSH    DS                      ; 1E
                PUSH    SI                      ; 56
                PUSH    ES                      ; 06
                PUSH    DI                      ; 57
                MOV     BP, SP                  ; 8B EC
                MOV     AX, [BP+16H]            ; 8B 46 16   width (bytes)
                SHR     AX, 1                   ; D1 E8
                MOV     [BP+16H], AX            ; 89 46 16
                MOV     AX, [BP+0EH]            ; 8B 46 0E   src_off
                MOV     BX, AX                  ; 8B D8
                AND     BX, 0FH                 ; 83 E3 0F
                MOV     SI, BX                  ; 8B F3
                SHR     AX, 1                   ; D1 E8
                SHR     AX, 1                   ; D1 E8
                SHR     AX, 1                   ; D1 E8
                SHR     AX, 1                   ; D1 E8
                ADD     AX, [BP+10H]            ; 03 46 10   + src_seg
                MOV     DS, AX                  ; 8E D8
                MOV     DI, 18H                 ; BF 18 00
                ADD     DI, cs:[0F6H]           ; 2E 03 3E F6 00
                MOV     ES, ss:[DI]             ; 36 8E 05   FB seg from scratch
                MOV     DX, 03C4H               ; BA C4 03
                MOV     AL, 2                   ; B0 02
                OUT     DX, AL                  ; EE
                INC     DX                      ; 42
                MOV     BX, [BP+18H]            ; 8B 5E 18   height (used as BL via dec at end)
vga_chunky_row:
                MOV     AX, [BP+14H]            ; 8B 46 14   y_row
                SHL     AX, 1                   ; D1 E0
                MOV     DI, GfxContext.pRow_offset_lut               ; BF F2 06
                ADD     DI, AX                  ; 03 F8
                ADD     DI, cs:[0F6H]           ; 2E 03 3E F6 00
                MOV     DI, ss:[DI]             ; 36 8B 3D
                ADD     DI, [BP+12H]            ; 03 7E 12   + x_byte_off
                MOV     CX, [BP+16H]            ; 8B 4E 16   width
                SHR     CX, 1                   ; D1 E9
                MOV     BH, CL                  ; 8A F9      BH = pairs per row
vga_chunky_pair:
                XOR     CX, CX                  ; 33 C9
                MOV     CL, [SI]                ; 8A 0C      src byte
                INC     SI                      ; 46
                SHL     CX, 1                   ; D1 E1
                SHL     CX, 1                   ; D1 E1
                SHL     CX, 1                   ; D1 E1
                SHL     CX, 1                   ; D1 E1
                SHR     CL, 1                   ; D0 E9
                SHR     CL, 1                   ; D0 E9
                SHR     CL, 1                   ; D0 E9
                SHR     CL, 1                   ; D0 E9
                MOV     AL, 1                   ; B0 01      Map Mask = plane 0
                OUT     DX, AL                  ; EE
                MOV     es:[DI], CH             ; 26 88 2D
                SHL     AL, 1                   ; D0 E0
                OUT     DX, AL                  ; EE
                MOV     es:[DI], CL             ; 26 88 0D
                XOR     CX, CX                  ; 33 C9
                MOV     CL, [SI]                ; 8A 0C
                INC     SI                      ; 46
                SHL     CX, 1                   ; D1 E1
                SHL     CX, 1                   ; D1 E1
                SHL     CX, 1                   ; D1 E1
                SHL     CX, 1                   ; D1 E1
                SHR     CL, 1                   ; D0 E9
                SHR     CL, 1                   ; D0 E9
                SHR     CL, 1                   ; D0 E9
                SHR     CL, 1                   ; D0 E9
                SHL     AL, 1                   ; D0 E0
                OUT     DX, AL                  ; EE
                MOV     es:[DI], CH             ; 26 88 2D
                SHL     AL, 1                   ; D0 E0
                OUT     DX, AL                  ; EE
                MOV     es:[DI], CL             ; 26 88 0D
                INC     DI                      ; 47
                DEC     BH                      ; FE CF
                JNZ     SHORT vga_chunky_pair   ; 75 B9
                MOV     AX, [BP+14H]            ; 8B 46 14
                INC     AX                      ; 40
                MOV     [BP+14H], AX            ; 89 46 14
                DEC     BL                      ; FE CB
                JNZ     SHORT vga_chunky_row    ; 75 92
                POP     DI                      ; 5F
                POP     ES                      ; 07
                POP     SI                      ; 5E
                POP     DS                      ; 1F
                POP     BP                      ; 5D
                RETF                            ; CB
vga_blit_chunky ENDP

; ============================================================================
; vga_blit_chunky_planar_4bit -- chunky 4bpp -> Mode-Y, OR-style.
; chunk:0x156C..0x1649
;
; Variant of vga_blit_chunky that OR's into the destination (vs MOV).
; Uses both GC Read Plane Select (port 0x3CE reg 4) and Sequencer Map
; Mask (port 0x3C4 reg 2) per write so the read latch pulls the
; pre-existing planar bits in for the OR. Per-pair sequence emits
; 4 plane writes with the appropriate read/write plane pair.
; ============================================================================
vga_blit_chunky_planar_4bit PROC FAR
                PUSH    BP                      ; 55
                PUSH    DS                      ; 1E
                PUSH    SI                      ; 56
                PUSH    ES                      ; 06
                PUSH    DI                      ; 57
                MOV     BP, SP                  ; 8B EC
                MOV     AX, [BP+16H]            ; 8B 46 16
                SHR     AX, 1                   ; D1 E8
                MOV     [BP+16H], AX            ; 89 46 16
                MOV     AX, [BP+0EH]            ; 8B 46 0E
                MOV     BX, AX                  ; 8B D8
                AND     BX, 0FH                 ; 83 E3 0F
                MOV     SI, BX                  ; 8B F3
                SHR     AX, 1                   ; D1 E8
                SHR     AX, 1                   ; D1 E8
                SHR     AX, 1                   ; D1 E8
                SHR     AX, 1                   ; D1 E8
                ADD     AX, [BP+10H]            ; 03 46 10
                MOV     DS, AX                  ; 8E D8
                MOV     DI, 18H                 ; BF 18 00
                ADD     DI, cs:[0F6H]           ; 2E 03 3E F6 00
                MOV     ES, ss:[DI]             ; 36 8E 05
                MOV     DX, 03CEH               ; BA CE 03   GC index
                MOV     AL, 4                   ; B0 04      reg 4 = Read Plane Select
                OUT     DX, AL                  ; EE
                MOV     DX, 03C4H               ; BA C4 03   Sequencer index
                MOV     AL, 2                   ; B0 02      reg 2 = Map Mask
                OUT     DX, AL                  ; EE
                INC     DX                      ; 42
                MOV     BX, [BP+18H]            ; 8B 5E 18   height
vga_chunky4_row:
                MOV     AX, [BP+14H]            ; 8B 46 14
                SHL     AX, 1                   ; D1 E0
                MOV     DI, GfxContext.pRow_offset_lut               ; BF F2 06
                ADD     DI, AX                  ; 03 F8
                ADD     DI, cs:[0F6H]           ; 2E 03 3E F6 00
                MOV     DI, ss:[DI]             ; 36 8B 3D
                ADD     DI, [BP+12H]            ; 03 7E 12
                MOV     CX, [BP+16H]            ; 8B 4E 16
                SHR     CX, 1                   ; D1 E9
                MOV     BH, CL                  ; 8A F9
vga_chunky4_pair:
                XOR     CX, CX                  ; 33 C9
                MOV     CL, [SI]                ; 8A 0C
                INC     SI                      ; 46
                SHL     CX, 1                   ; D1 E1
                SHL     CX, 1                   ; D1 E1
                SHL     CX, 1                   ; D1 E1
                SHL     CX, 1                   ; D1 E1
                SHL     CH, 1                   ; D0 E5
                SHL     CH, 1                   ; D0 E5
                SHL     CH, 1                   ; D0 E5
                SHL     CH, 1                   ; D0 E5
                MOV     AX, 0001H               ; B8 01 00   AL=mask-plane0, AH=read-plane0
                OUT     DX, AL                  ; EE        Map Mask = plane 0
                ADD     DX, 0AH                 ; 83 C2 0A  -> 0x3CF GC data
                MOV     AL, AH                  ; 8A C4
                OUT     DX, AL                  ; EE        Read Plane Select = plane 0
                SUB     DX, 0AH                 ; 83 EA 0A
                OR      es:[DI], CH             ; 26 08 2D
                MOV     AX, 0102H               ; B8 02 01
                OUT     DX, AL                  ; EE
                ADD     DX, 0AH                 ; 83 C2 0A
                MOV     AL, AH                  ; 8A C4
                OUT     DX, AL                  ; EE
                SUB     DX, 0AH                 ; 83 EA 0A
                OR      es:[DI], CL             ; 26 08 0D
                MOV     CL, [SI]                ; 8A 0C
                INC     SI                      ; 46
                SHL     CX, 1                   ; D1 E1
                SHL     CX, 1                   ; D1 E1
                SHL     CX, 1                   ; D1 E1
                SHL     CX, 1                   ; D1 E1
                SHL     CH, 1                   ; D0 E5
                SHL     CH, 1                   ; D0 E5
                SHL     CH, 1                   ; D0 E5
                SHL     CH, 1                   ; D0 E5
                MOV     AX, 0204H               ; B8 04 02
                OUT     DX, AL                  ; EE
                ADD     DX, 0AH                 ; 83 C2 0A
                MOV     AL, AH                  ; 8A C4
                OUT     DX, AL                  ; EE
                SUB     DX, 0AH                 ; 83 EA 0A
                OR      es:[DI], CH             ; 26 08 2D
                MOV     AX, 0308H               ; B8 08 03
                OUT     DX, AL                  ; EE
                ADD     DX, 0AH                 ; 83 C2 0A
                MOV     AL, AH                  ; 8A C4
                OUT     DX, AL                  ; EE
                SUB     DX, 0AH                 ; 83 EA 0A
                OR      es:[DI], CL             ; 26 08 0D
                INC     DI                      ; 47
                DEC     BH                      ; FE CF
                JNZ     SHORT vga_chunky4_pair  ; 75 93
                MOV     AX, [BP+14H]            ; 8B 46 14
                INC     AX                      ; 40
                MOV     [BP+14H], AX            ; 89 46 14
                DEC     BL                      ; FE CB
                JZ      SHORT vga_chunky4_done  ; 74 03
                JMP     vga_chunky4_row         ; E9 69 FF
vga_chunky4_done:
                POP     DI                      ; 5F
                POP     ES                      ; 07
                POP     SI                      ; 5E
                POP     DS                      ; 1F
                POP     BP                      ; 5D
                RETF                            ; CB
vga_blit_chunky_planar_4bit ENDP

; ============================================================================
; vga_blit_sprite_master scratch + sprite_row_* dispatch table.
; chunk:0x164A..0x1661
;
; 16 bytes of zero-initialised scratch (sprite-descriptor copy locals)
; followed by the 4-entry near-pointer dispatch table indexed by
; (flip_flags & 3) * 2.
;
; FLIP-FLAG BIT SEMANTICS:
;   bit 0 (mask 0x01) = V-flip  (vertical / Y-axis mirror)
;   bit 1 (mask 0x02) = H-flip  (horizontal / X-axis mirror)
;
; So:
;   flip=0 (00b) -> index 0 -> vga_sprite_row_noflip
;   flip=1 (01b) -> index 1 -> vga_sprite_row_vflip   (bit 0 set = V)
;   flip=2 (10b) -> index 2 -> vga_sprite_row_hflip   (bit 1 set = H)
;   flip=3 (11b) -> index 3 -> vga_sprite_row_vhflip  (both)
;
; Note: the preamble (vga_blit_sprite_master) uses TEST <flag>,2 to
; pick the H-flip code path and TEST <flag>,1 for the V-flip path --
; matching this assignment. The "vflip-ON dispatch" / "vflip-OFF
; dispatch" comments inside the preamble are legacy mislabels and
; have been corrected to "hflip-ON / hflip-OFF" inline.
; ============================================================================
g_awVgaSpriteMasterScratch      DW      0, 0, 0, 0, 0, 0, 0, 0  ; 0x164A
g_apVgaSpriteRowDispatch:                                       ; 0x165A
                DW      18BBH      ; 0x165A -> vga_sprite_row_noflip
                DW      1AF7H      ; 0x165C -> vga_sprite_row_vflip
                DW      1D53H      ; 0x165E -> vga_sprite_row_hflip
                DW      1FBEH      ; 0x1660 -> vga_sprite_row_vhflip

; ============================================================================
; vga_blit_sprite_master -- 4-way flip Mode-Y sprite blitter (vtable slot 29).
; chunk:0x1662..0x222E  (~3 KB; the largest function in the chunk)
;
; ABI (__cdecl16far):
;   [BP+6]   ushort sprite-descriptor near offset (in caller's DS).
;            The descriptor is 10 bytes (5 words); the preamble does
;            REP MOVSW CX=5 to copy it into the stack frame.
;   [BP+8]   short  X (signed pixel coordinate of dst top-left)
;   [BP+0Ah] short  Y (signed pixel coordinate of dst top-left)
;   [BP+0Ch] byte   flip_flags
;                     bit 0 = V-flip (vertical / Y-axis mirror)
;                     bit 1 = H-flip (horizontal / X-axis mirror)
;   See the dispatch-table plate above for the per-flag-value handler
;   mapping. The wrapper vga_blit_sprite (slot 3) calls this with
;   flags = 0; non-zero flags come from other entry points.
;
; SUMMARY
;
; Blits a 4bpp source sprite into the Mode-Y back buffer with optional
; horizontal and/or vertical flip. The flip flags select one of four
; "row handler" code paths (noflip / vflip / hflip / vhflip). Within
; each row handler the four Mode-Y planes are walked in a fixed
; sequence; the inner pixel loop is unrolled and a "sliding entry
; point" trick (see below) selects which of the four plane lanes the
; first source byte lands on.
;
; ARCHITECTURE
;
; This is one PROC FAR containing four "row handler" labels reached
; via the near-pointer dispatch table at 0x165A. They are LABELS not
; nested PROCs because they share:
;
;   - the function's setup / clip preamble at chunk:0x1662..0x1862
;     (saves callee-saved registers + the eight master scratch words
;     at 0x164A..0x1659, copies the descriptor, computes start/end
;     coordinates and clipping, configures the Map Mask register);
;   - the epilogue at chunk:0x21FE (restores the scratch words and
;     callee-saved registers and RETFs).
;
; The dispatch table:
;
;     g_apVgaSpriteRowDispatch @ chunk:0x165A
;       [0] = 0x18BB  vga_sprite_row_noflip
;       [1] = 0x1AF7  vga_sprite_row_vflip
;       [2] = 0x1D53  vga_sprite_row_hflip
;       [3] = 0x1FBE  vga_sprite_row_vhflip
;
; The preamble loads (flip_flags & 3) * 2, indexes into the table, and
; PUSH AX -- the row-handler offset is then on the stack so the JMP AX
; at the bottom of the per-plane "plane-select" trampoline can pop it
; and dispatch.
;
; THE SLIDING-ENTRY ROTATOR
;
; Inside each row handler the four Mode-Y planes are walked in plane
; order, but the FIRST plane to write depends on which sub-pixel of
; the destination's leftmost byte we're starting in. Rather than emit
; a 4-way conditional at the top of each lane, the code uses a "slide"
; trick:
;
;     MOV     AX, cs:[1650H]          ; current plane phase (0..3)
;     XOR     AX, 3                   ; reverse phase
;     SHL     AX, 1                   ; * 2 bytes (each "ADD BX,SI" is 2 bytes)
;     ADD     AX, <slide_base>        ; absolute address of slide
;     ...
;     XOR     BX, BX
;     JMP     AX                      ; jump into the slide N entries in
;     ; --- the slide (3 copies of ADD BX,SI, each 2 bytes) ---
;     ADD     BX, SI                  ; (only executed if entered before this)
;     ADD     BX, SI                  ; (only executed if entered before this)
;     ADD     BX, SI                  ; (only executed if entered before this)
;     MOV     AX, BX                  ; common tail: BX now holds (3 - phase)
;
; This builds the running plane offset (3 - phase) without a branch.
; SI is set to 1 before the jump so each `ADD BX, SI` effectively
; increments BX by 1; depending on where in the slide we entered, BX
; ends up as 3, 2, 1, or 0. That value (plus the cached row offset at
; cs:[164EH]) becomes the next source byte index.
;
; PER-LANE PIXEL LOOP
;
; Inside one lane the pixel loop is:
;
;     LODSB                           ; AL = next source nibble pair byte
;     ADD     SI, 3                   ; advance to next pixel-in-plane source
;     OR      AL, AL
;     JZ      <next>                  ; transparent pixel: skip STOSB
;     STOSB
;     DEC     DI                      ; (cancels the STOSB DI++ in the next iter
;     INC     DI                      ;  so that DI lands on the same byte the
;                                     ;  next STOSB would have written -- this
;                                     ;  is the "skip but advance dst" idiom)
;     LOOP    <body>
;
; SHARED SCRATCH WORDS (chunk:0x164A..0x1659)
;
; The function pushes the on-disk contents of these eight words on
; entry and pops them on exit, so the master is reentrant via PUSH/POP
; even though it stores state in CS-relative globals during execution:
;
;     0x164A  g_w164a  row-byte clip offset
;     0x164C  g_w164c  source bytes per row
;     0x164E  g_w164e  current source byte offset within this row
;     0x1650  g_w1650  current plane phase (0..3, the rotator input)
;     0x1652  g_w1652  current Map Mask bit position (0..3)
;     0x1654  g_w1654  remaining-rows counter
;     0x1656  g_w1656  original sprite width
;     0x1658  g_w1658  cached destination byte offset
;
; The descriptor structure copied via REP MOVSW at entry occupies the
; 5 words at [BP-0xA] .. [BP-0x2] (which the code aliases via the
; same scratch addresses, because the dispatch logic walks both).
;
; LABELS DO NOT PARTICIPATE IN ENCODED IMMEDIATES. Internal control
; flow uses TASM's `$+N` / `$-N` numeric self-relative jumps, which
; avoids TASM one-pass forward-reference issues. The labels emitted
; for navigation (vga_sprite_row_*) are not referenced by any jump;
; they are pure annotations.
; ============================================================================
vga_blit_sprite_master PROC FAR
                PUSH    BP                      ; 55
                MOV     BP, SP                  ; 8B EC
                SUB     SP, 0AH                 ; 83 EC 0A
                PUSH    DI                      ; 57
                PUSH    SI                      ; 56
                PUSH    ES                      ; 06
                PUSH    DS                      ; 1E
                PUSH    WORD PTR cs:[164AH]     ; 2E FF 36 4A 16
                PUSH    WORD PTR cs:[164CH]     ; 2E FF 36 4C 16
                PUSH    WORD PTR cs:[164EH]     ; 2E FF 36 4E 16
                PUSH    WORD PTR cs:[1650H]     ; 2E FF 36 50 16
                PUSH    WORD PTR cs:[1652H]     ; 2E FF 36 52 16
                PUSH    WORD PTR cs:[1654H]     ; 2E FF 36 54 16
                PUSH    WORD PTR cs:[1656H]     ; 2E FF 36 56 16
                PUSH    WORD PTR cs:[1658H]     ; 2E FF 36 58 16
                MOV     SI, [BP+6]              ; 8B 76 06
                MOV     DI, BP                  ; 8B FD
                SUB     DI, 0AH                 ; 83 EF 0A
                MOV     AX, SS                  ; 8C D0
                MOV     ES, AX                  ; 8E C0
                MOV     CX, 5                   ; B9 05 00
                REP     MOVSW                   ; F3 A5
                MOV     AX, [BP-4]              ; 8B 46 FC
                MOV     cs:[1656H], AX          ; 2E A3 56 16
                SHR     AX, 1                   ; D1 E8
                SHR     AX, 1                   ; D1 E8
                MOV     [BP-4], AX              ; 89 46 FC
                SHL     AX, 1                   ; D1 E0
                SHL     AX, 1                   ; D1 E0
                XOR     DX, DX                  ; 33 D2
                MUL     WORD PTR [BP-2]         ; F7 66 FE
                MOV     cs:[164CH], AX          ; 2E A3 4C 16
                MOV     DS, cs:[0F4H]           ; 2E 8E 1E F4 00
                MOV     AX, ds:[GfxContext.wGfxBlitDstPage]            ; A1 18 00
                MOV     ES, AX                  ; 8E C0
                XOR     SI, SI                  ; 33 F6
                TEST    BYTE PTR [BP+0CH], 2    ; F6 46 0C 02  -- bit 1 = H-flip
                JZ      SHORT $+8               ; 74 06   -- skip H-flip pre-bias
                MOV     SI, cs:[1656H]          ; 2E 8B 36 56 16
                DEC     SI                      ; 4E      -- SI = sprite_width - 1 (rightmost source byte)
                TEST    BYTE PTR [BP+0CH], 1    ; F6 46 0C 01  -- bit 0 = V-flip
                JZ      SHORT $+13              ; 74 0B   -- skip V-flip row adjust
                MOV     AX, cs:[164CH]          ; 2E A1 4C 16
                SUB     AX, cs:[1656H]          ; 2E 2B 06 56 16
                ADD     SI, AX                  ; 03 F0
                MOV     DI, [BP+0AH]            ; 8B 7E 0A
                SHL     DI, 1                   ; D1 E7
                MOV     DI, [DI].GfxContext.pRow_offset_lut          ; 8B BD F2 06
                SHL     DI, 1                   ; D1 E7
                SHL     DI, 1                   ; D1 E7
                PUSHF                           ; 9C
                ADD     DI, [BP+8]              ; 03 7E 08
                MOV     DX, [BP-4]              ; 8B 56 FC
                SHL     DX, 1                   ; D1 E2
                SHL     DX, 1                   ; D1 E2
                MOV     AX, [BP-2]              ; 8B 46 FE
                MOV     cs:[1654H], AX          ; 2E A3 54 16
                MOV     AL, ds:[GfxContext.bClip_enabled]              ; A0 03 00
                XOR     BX, BX                  ; 33 DB
                OR      AL, AL                  ; 0A C0
                JNZ     SHORT $+5               ; 75 03   -- proceed to clipping
                JMP     $+0BAH                  ; E9 B7 00  -- skip clip block (to postclip @ 0x17CB)
                ; clip_right: 0x1714
                MOV     AX, ds:[GfxContext.nClip_xmax]              ; A1 06 00
                SUB     AX, [BP+8]              ; 2B 46 08
                MOV     CX, DX                  ; 8B CA
                SUB     AX, CX                  ; 2B C1
                JNS     SHORT $+18H             ; 79 16
                NEG     AX                      ; F7 D8
                DEC     AX                      ; 48
                MOV     BX, AX                  ; 8B D8
                SUB     DX, AX                  ; 2B D0
                SHR     AX, 1                   ; D1 E8
                SHR     AX, 1                   ; D1 E8
                SUB     AX, [BP-4]              ; 2B 46 FC
                JC      SHORT $+8               ; 72 06
                ADD     SP, 2                   ; 83 C4 02
                JMP     $+0ACBH                 ; E9 C8 0A  -- to epilogue @ 0x21FE
                ; clip_bot: 0x1736
                MOV     AX, ds:[GfxContext.nClip_ymax]            ; A1 0A 00
                SUB     AX, [BP+0AH]            ; 2B 46 0A
                MOV     CX, cs:[1654H]          ; 2E 8B 0E 54 16
                SUB     AX, CX                  ; 2B C1
                JNS     SHORT $+12H             ; 79 10
                NEG     AX                      ; F7 D8
                DEC     AX                      ; 48
                SUB     WORD PTR cs:[1654H], AX ; 2E 29 06 54 16
                JA      SHORT $+8               ; 77 06
                ADD     SP, 2                   ; 83 C4 02
                JMP     $+0AACH                 ; E9 A9 0A  -- to epilogue
                ; clip_top: 0x1755
                MOV     AX, ds:[GfxContext.nClip_ymin]              ; A1 08 00
                SUB     AX, [BP+0AH]            ; 2B 46 0A
                JLE     SHORT $+47H             ; 7E 45   -- to clip_left @ 0x17A2
                SUB     WORD PTR cs:[1654H], AX ; 2E 29 06 54 16
                PUSH    DX                      ; 52
                XOR     DX, DX                  ; 33 D2
                MUL     WORD PTR [BP-4]         ; F7 66 FC
                SHL     AX, 1                   ; D1 E0
                SHL     AX, 1                   ; D1 E0
                POP     DX                      ; 5A
                TEST    BYTE PTR [BP+0CH], 1    ; F6 46 0C 01
                JZ      SHORT $+4               ; 74 02
                NEG     AX                      ; F7 D8
                ADD     SI, AX                  ; 03 F0
                MOV     DI, ds:[GfxContext.nClip_ymin]              ; 8B 3E 08 00
                SHL     DI, 1                   ; D1 E7
                MOV     DI, [DI].GfxContext.pRow_offset_lut          ; 8B BD F2 06
                SHL     DI, 1                   ; D1 E7
                SHL     DI, 1                   ; D1 E7
                ADD     SP, 2                   ; 83 C4 02
                PUSHF                           ; 9C
                ADD     DI, [BP+8]              ; 03 7E 08
                MOV     AX, cs:[1654H]          ; 2E A1 54 16
                OR      AX, AX                  ; 0B C0
                JNZ     SHORT $+8               ; 75 06
                ADD     SP, 2                   ; 83 C4 02
                JMP     $+0A67H                 ; E9 64 0A
                JNS     SHORT $+8               ; 79 06
                ADD     SP, 2                   ; 83 C4 02
                JMP     $+0A5FH                 ; E9 5C 0A
                ; clip_left: 0x17A2
                MOV     AX, ds:[GfxContext.nClip_xmin]              ; A1 04 00
                SUB     AX, [BP+8]              ; 2B 46 08
                JLE     SHORT $+23H             ; 7E 21   -- to postclip
                ADD     DI, AX                  ; 03 F8
                ADD     BX, AX                  ; 03 D8
                TEST    BYTE PTR [BP+0CH], 2    ; F6 46 0C 02
                JZ      SHORT $+6               ; 74 04
                SUB     SI, AX                  ; 2B F0
                SUB     SI, AX                  ; 2B F0
                SUB     DX, AX                  ; 2B D0
                ADD     SI, AX                  ; 03 F0
                SHR     AX, 1                   ; D1 E8
                SHR     AX, 1                   ; D1 E8
                SUB     AX, [BP-4]              ; 2B 46 FC
                JC      SHORT $+8               ; 72 06
                ADD     SP, 2                   ; 83 C4 02
                JMP     $+0A36H                 ; E9 33 0A
                ; postclip: 0x17CB
                MOV     AX, DI                  ; 8B C7
                AND     AX, 3                   ; 25 03 00
                MOV     cs:[1652H], AX          ; 2E A3 52 16
                MOV     AX, SI                  ; 8B C6
                TEST    BYTE PTR [BP+0CH], 2    ; F6 46 0C 02
                JZ      SHORT $+4               ; 74 02
                NOT     AX                      ; F7 D0
                AND     AX, 3                   ; 25 03 00
                MOV     cs:[1650H], AX          ; 2E A3 50 16
                POPF                            ; 9D
                RCR     DI, 1                   ; D1 DF
                SHR     DI, 1                   ; D1 EF
                MOV     cs:[164AH], BX          ; 2E 89 1E 4A 16
                TEST    BYTE PTR [BP+0CH], 2    ; F6 46 0C 02
                JZ      SHORT $+8               ; 74 06
                XOR     WORD PTR cs:[1650H], 3  ; 2E 83 36 50 16 03
                MOV     AX, [BP-0AH]            ; 8B 46 F6
                ADD     SI, [BP-8]              ; 03 76 F8
                AND     SI, 0FFFCH              ; 83 E6 FC
                MOV     cs:[164EH], SI          ; 2E 89 36 4E 16
                MOV     DS, AX                  ; 8E D8
                MOV     BX, [BP+0CH]            ; 8B 5E 0C
                AND     BX, 3                   ; 83 E3 03
                SHL     BX, 1                   ; D1 E3
                MOV     AX, cs:[BX+165AH]       ; 2E 8B 87 5A 16
                MOV     cs:[1658H], DI          ; 2E 89 3E 58 16
                PUSH    AX                      ; 50
                ; plane-write setup (initial map mask): 0x181E
                PUSH    DX                      ; 52
                MOV     DX, 03C4H               ; BA C4 03
                MOV     AL, 2                   ; B0 02
                OUT     DX, AL                  ; EE
                POP     DX                      ; 5A
                PUSH    DX                      ; 52
                MOV     CL, cs:[1652H]          ; 2E 8A 0E 52 16
                MOV     DI, cs:[1658H]          ; 2E 8B 3E 58 16
                MOV     AL, 1                   ; B0 01
                SHL     AL, CL                  ; D2 E0
                INC     WORD PTR cs:[1652H]     ; 2E FF 06 52 16
                CMP     AL, 10H                 ; 3C 10
                JNZ     SHORT $+0EH             ; 75 0C
                INC     DI                      ; 47
                MOV     cs:[1658H], DI          ; 2E 89 3E 58 16
                MOV     AL, 1                   ; B0 01
                MOV     cs:[1652H], AL          ; 2E A2 52 16
                MOV     DX, 03C5H               ; BA C5 03
                OUT     DX, AL                  ; EE
                POP     DX                      ; 5A
                TEST    BYTE PTR [BP+0CH], 2    ; F6 46 0C 02  -- bit 1 = H-flip
                JNZ     SHORT $+35H             ; 75 33  -- to H-flip-ON dispatch
                ; H-flip-OFF dispatch (0x1855): plane-phase walks INC (left->right)
                MOV     AX, cs:[1650H]          ; 2E A1 50 16
                XOR     AX, 3                   ; 35 03 00
                SHL     AX, 1                   ; D1 E0
                ADD     AX, 1869H               ; 05 69 18
                MOV     SI, 1                   ; BE 01 00
                PUSH    BX                      ; 53
                XOR     BX, BX                  ; 33 DB
                JMP     AX                      ; FF E0
                ; H-flip-OFF slide (0x1869):
                ADD     BX, SI                  ; 03 DE
                ADD     BX, SI                  ; 03 DE
                ADD     BX, SI                  ; 03 DE
                MOV     AX, BX                  ; 8B C3
                POP     BX                      ; 5B
                ADD     AX, cs:[164EH]          ; 2E 03 06 4E 16
                MOV     SI, AX                  ; 8B F0
                MOV     AX, cs:[1650H]          ; 2E A1 50 16
                INC     AX                      ; 40
                AND     AX, 3                   ; 25 03 00
                MOV     cs:[1650H], AX          ; 2E A3 50 16
                POP     AX                      ; 58
                JMP     AX                      ; FF E0
                ; H-flip-ON dispatch (0x1888): plane-phase walks DEC (right->left)
                MOV     AX, cs:[1650H]          ; 2E A1 50 16
                XOR     AX, 3                   ; 35 03 00
                SHL     AX, 1                   ; D1 E0
                ADD     AX, 189CH               ; 05 9C 18
                MOV     SI, 1                   ; BE 01 00
                PUSH    BX                      ; 53
                XOR     BX, BX                  ; 33 DB
                JMP     AX                      ; FF E0
                ; H-flip-ON slide (0x189C):
                ADD     BX, SI                  ; 03 DE
                ADD     BX, SI                  ; 03 DE
                ADD     BX, SI                  ; 03 DE
                MOV     AX, BX                  ; 8B C3
                POP     BX                      ; 5B
                ADD     AX, cs:[164EH]          ; 2E 03 06 4E 16
                MOV     SI, AX                  ; 8B F0
                MOV     AX, cs:[1650H]          ; 2E A1 50 16
                DEC     AX                      ; 48
                AND     AX, 3                   ; 25 03 00
                MOV     cs:[1650H], AX          ; 2E A3 50 16
                POP     AX                      ; 58
                JMP     AX                      ; FF E0
                ; ==== vga_sprite_row_noflip @ 0x18BB ====
vga_sprite_row_noflip:
                ; --- Plane lane 0 (high byte): 0x18BB..0x1903
                MOV     BP, 50H                 ; BD 50 00
                PUSH    DX                      ; 52
                PUSH    WORD PTR cs:[1654H]     ; 2E FF 36 54 16
                ADD     DX, 3                   ; 83 C2 03
                MOV     BX, cs:[164AH]          ; 2E 8B 1E 4A 16
                ADD     BX, 0                   ; 83 C3 00
                AND     BX, 0FFFCH              ; 83 E3 FC
                SHR     DX, 1                   ; D1 EA
                SHR     DX, 1                   ; D1 EA
                JZ      SHORT $+20H             ; 74 1E
                MOV     AX, DX                  ; 8B C2
                SUB     BP, AX                  ; 2B E8
                MOV     CX, DX                  ; 8B CA
                LODSB                           ; AC
                ADD     SI, 3                   ; 83 C6 03
                OR      AL, AL                  ; 0A C0
                JZ      SHORT $+4               ; 74 02
                STOSB                           ; AA
                DEC     DI                      ; 4F
                INC     DI                      ; 47
                LOOP    SHORT $-0BH             ; E2 F3   (-13 -> back to LODSB)
                ADD     SI, BX                  ; 03 F3
                ADD     DI, BP                  ; 03 FD
                DEC     WORD PTR cs:[1654H]     ; 2E FF 0E 54 16
                JNZ     SHORT $-18H             ; 75 E6
                POP     WORD PTR cs:[1654H]     ; 2E 8F 06 54 16
                POP     DX                      ; 5A
                MOV     AX, cs:[1650H]          ; 2E A1 50 16
                OR      AX, AX                  ; 0B C0
                JNZ     SHORT $+8               ; 75 06
                ADD     WORD PTR cs:[164EH], 4  ; 2E 83 06 4E 16 04
                ; --- Plane rotator slide #2 (0x190A)
                MOV     AX, cs:[1650H]          ; 2E A1 50 16
                XOR     AX, 3                   ; 35 03 00
                SHL     AX, 1                   ; D1 E0
                ADD     AX, 191EH               ; 05 1E 19
                MOV     SI, 1                   ; BE 01 00
                PUSH    BX                      ; 53
                XOR     BX, BX                  ; 33 DB
                JMP     AX                      ; FF E0
                ; slide at 0x191E
                ADD     BX, SI                  ; 03 DE
                ADD     BX, SI                  ; 03 DE
                ADD     BX, SI                  ; 03 DE
                MOV     AX, BX                  ; 8B C3
                POP     BX                      ; 5B
                ADD     AX, cs:[164EH]          ; 2E 03 06 4E 16
                MOV     SI, AX                  ; 8B F0
                MOV     AX, cs:[1650H]          ; 2E A1 50 16
                INC     AX                      ; 40
                AND     AX, 3                   ; 25 03 00
                MOV     cs:[1650H], AX          ; 2E A3 50 16
                ; --- Plane select setup #2 (no PUSH AX since we're not popping it after)
                PUSH    DX                      ; 52
                MOV     CL, cs:[1652H]          ; 2E 8A 0E 52 16
                MOV     DI, cs:[1658H]          ; 2E 8B 3E 58 16
                MOV     AL, 1                   ; B0 01
                SHL     AL, CL                  ; D2 E0
                INC     WORD PTR cs:[1652H]     ; 2E FF 06 52 16
                CMP     AL, 10H                 ; 3C 10
                JNZ     SHORT $+0EH             ; 75 0C
                INC     DI                      ; 47
                MOV     cs:[1658H], DI          ; 2E 89 3E 58 16
                MOV     AL, 1                   ; B0 01
                MOV     cs:[1652H], AL          ; 2E A2 52 16
                MOV     DX, 03C5H               ; BA C5 03
                OUT     DX, AL                  ; EE
                POP     DX                      ; 5A
                ; --- Plane lane 1: 0x1963..
                MOV     BP, 50H                 ; BD 50 00
                PUSH    DX                      ; 52
                PUSH    WORD PTR cs:[1654H]     ; 2E FF 36 54 16
                ADD     DX, 2                   ; 83 C2 02
                MOV     BX, cs:[164AH]          ; 2E 8B 1E 4A 16
                ADD     BX, 1                   ; 83 C3 01
                AND     BX, 0FFFCH              ; 83 E3 FC
                SHR     DX, 1                   ; D1 EA
                SHR     DX, 1                   ; D1 EA
                JZ      SHORT $+20H             ; 74 1E
                MOV     AX, DX                  ; 8B C2
                SUB     BP, AX                  ; 2B E8
                MOV     CX, DX                  ; 8B CA
                LODSB                           ; AC
                ADD     SI, 3                   ; 83 C6 03
                OR      AL, AL                  ; 0A C0
                JZ      SHORT $+4               ; 74 02
                STOSB                           ; AA
                DEC     DI                      ; 4F
                INC     DI                      ; 47
                LOOP    SHORT $-0BH             ; E2 F3
                ADD     SI, BX                  ; 03 F3
                ADD     DI, BP                  ; 03 FD
                DEC     WORD PTR cs:[1654H]     ; 2E FF 0E 54 16
                JNZ     SHORT $-18H             ; 75 E6
                POP     WORD PTR cs:[1654H]     ; 2E 8F 06 54 16
                POP     DX                      ; 5A
                MOV     AX, cs:[1650H]          ; 2E A1 50 16
                OR      AX, AX                  ; 0B C0
                JNZ     SHORT $+8               ; 75 06
                ADD     WORD PTR cs:[164EH], 4  ; 2E 83 06 4E 16 04
                MOV     AX, cs:[1650H]          ; 2E A1 50 16
                XOR     AX, 3                   ; 35 03 00
                SHL     AX, 1                   ; D1 E0
                ADD     AX, 19C6H               ; 05 C6 19
                MOV     SI, 1                   ; BE 01 00
                PUSH    BX                      ; 53
                XOR     BX, BX                  ; 33 DB
                JMP     AX                      ; FF E0
                ; slide at 0x19C6
                ADD     BX, SI                  ; 03 DE
                ADD     BX, SI                  ; 03 DE
                ADD     BX, SI                  ; 03 DE
                MOV     AX, BX                  ; 8B C3
                POP     BX                      ; 5B
                ADD     AX, cs:[164EH]          ; 2E 03 06 4E 16
                MOV     SI, AX                  ; 8B F0
                MOV     AX, cs:[1650H]          ; 2E A1 50 16
                INC     AX                      ; 40
                AND     AX, 3                   ; 25 03 00
                MOV     cs:[1650H], AX          ; 2E A3 50 16
                PUSH    DX                      ; 52
                MOV     CL, cs:[1652H]          ; 2E 8A 0E 52 16
                MOV     DI, cs:[1658H]          ; 2E 8B 3E 58 16
                MOV     AL, 1                   ; B0 01
                SHL     AL, CL                  ; D2 E0
                INC     WORD PTR cs:[1652H]     ; 2E FF 06 52 16
                CMP     AL, 10H                 ; 3C 10
                JNZ     SHORT $+0EH             ; 75 0C
                INC     DI                      ; 47
                MOV     cs:[1658H], DI          ; 2E 89 3E 58 16
                MOV     AL, 1                   ; B0 01
                MOV     cs:[1652H], AL          ; 2E A2 52 16
                MOV     DX, 03C5H               ; BA C5 03
                OUT     DX, AL                  ; EE
                POP     DX                      ; 5A
                ; --- Plane lane 2: 0x1A0B
                MOV     BP, 50H                 ; BD 50 00
                PUSH    DX                      ; 52
                PUSH    WORD PTR cs:[1654H]     ; 2E FF 36 54 16
                ADD     DX, 1                   ; 83 C2 01
                MOV     BX, cs:[164AH]          ; 2E 8B 1E 4A 16
                ADD     BX, 2                   ; 83 C3 02
                AND     BX, 0FFFCH              ; 83 E3 FC
                SHR     DX, 1                   ; D1 EA
                SHR     DX, 1                   ; D1 EA
                JZ      SHORT $+20H             ; 74 1E
                MOV     AX, DX                  ; 8B C2
                SUB     BP, AX                  ; 2B E8
                MOV     CX, DX                  ; 8B CA
                LODSB                           ; AC
                ADD     SI, 3                   ; 83 C6 03
                OR      AL, AL                  ; 0A C0
                JZ      SHORT $+4               ; 74 02
                STOSB                           ; AA
                DEC     DI                      ; 4F
                INC     DI                      ; 47
                LOOP    SHORT $-0BH             ; E2 F3
                ADD     SI, BX                  ; 03 F3
                ADD     DI, BP                  ; 03 FD
                DEC     WORD PTR cs:[1654H]     ; 2E FF 0E 54 16
                JNZ     SHORT $-18H             ; 75 E6
                POP     WORD PTR cs:[1654H]     ; 2E 8F 06 54 16
                POP     DX                      ; 5A
                MOV     AX, cs:[1650H]          ; 2E A1 50 16
                OR      AX, AX                  ; 0B C0
                JNZ     SHORT $+8               ; 75 06
                ADD     WORD PTR cs:[164EH], 4  ; 2E 83 06 4E 16 04
                MOV     AX, cs:[1650H]          ; 2E A1 50 16
                XOR     AX, 3                   ; 35 03 00
                SHL     AX, 1                   ; D1 E0
                ADD     AX, 1A6EH               ; 05 6E 1A
                MOV     SI, 1                   ; BE 01 00
                PUSH    BX                      ; 53
                XOR     BX, BX                  ; 33 DB
                JMP     AX                      ; FF E0
                ; slide at 0x1A6E
                ADD     BX, SI                  ; 03 DE
                ADD     BX, SI                  ; 03 DE
                ADD     BX, SI                  ; 03 DE
                MOV     AX, BX                  ; 8B C3
                POP     BX                      ; 5B
                ADD     AX, cs:[164EH]          ; 2E 03 06 4E 16
                MOV     SI, AX                  ; 8B F0
                MOV     AX, cs:[1650H]          ; 2E A1 50 16
                INC     AX                      ; 40
                AND     AX, 3                   ; 25 03 00
                MOV     cs:[1650H], AX          ; 2E A3 50 16
                PUSH    DX                      ; 52
                MOV     CL, cs:[1652H]          ; 2E 8A 0E 52 16
                MOV     DI, cs:[1658H]          ; 2E 8B 3E 58 16
                MOV     AL, 1                   ; B0 01
                SHL     AL, CL                  ; D2 E0
                INC     WORD PTR cs:[1652H]     ; 2E FF 06 52 16
                CMP     AL, 10H                 ; 3C 10
                JNZ     SHORT $+0EH             ; 75 0C
                INC     DI                      ; 47
                MOV     cs:[1658H], DI          ; 2E 89 3E 58 16
                MOV     AL, 1                   ; B0 01
                MOV     cs:[1652H], AL          ; 2E A2 52 16
                MOV     DX, 03C5H               ; BA C5 03
                OUT     DX, AL                  ; EE
                POP     DX                      ; 5A
                ; --- Plane lane 3: 0x1AB3
                MOV     BP, 50H                 ; BD 50 00
                PUSH    DX                      ; 52
                PUSH    WORD PTR cs:[1654H]     ; 2E FF 36 54 16
                ADD     DX, 0                   ; 83 C2 00
                MOV     BX, cs:[164AH]          ; 2E 8B 1E 4A 16
                ADD     BX, 3                   ; 83 C3 03
                AND     BX, 0FFFCH              ; 83 E3 FC
                SHR     DX, 1                   ; D1 EA
                SHR     DX, 1                   ; D1 EA
                JZ      SHORT $+20H             ; 74 1E
                MOV     AX, DX                  ; 8B C2
                SUB     BP, AX                  ; 2B E8
                MOV     CX, DX                  ; 8B CA
                LODSB                           ; AC
                ADD     SI, 3                   ; 83 C6 03
                OR      AL, AL                  ; 0A C0
                JZ      SHORT $+4               ; 74 02
                STOSB                           ; AA
                DEC     DI                      ; 4F
                INC     DI                      ; 47
                LOOP    SHORT $-0BH             ; E2 F3
                ADD     SI, BX                  ; 03 F3
                ADD     DI, BP                  ; 03 FD
                DEC     WORD PTR cs:[1654H]     ; 2E FF 0E 54 16
                JNZ     SHORT $-18H             ; 75 E6
                POP     WORD PTR cs:[1654H]     ; 2E 8F 06 54 16
                POP     DX                      ; 5A
                JMP     $+70AH                  ; E9 07 07   -- to epilogue @ 0x21FE
                ; ==== vga_sprite_row_vflip @ 0x1AF7 ====
vga_sprite_row_vflip:
                ; --- Lane 0
                MOV     BP, 50H                 ; BD 50 00
                PUSH    DX                      ; 52
                PUSH    WORD PTR cs:[1654H]     ; 2E FF 36 54 16
                ADD     DX, 3                   ; 83 C2 03
                MOV     BX, cs:[164AH]          ; 2E 8B 1E 4A 16
                ADD     BX, 0                   ; 83 C3 00
                AND     BX, 0FFFCH              ; 83 E3 FC
                MOV     AX, cs:[1656H]          ; 2E A1 56 16
                SHL     AX, 1                   ; D1 E0
                SUB     BX, AX                  ; 2B D8
                SHR     DX, 1                   ; D1 EA
                SHR     DX, 1                   ; D1 EA
                JZ      SHORT $+20H             ; 74 1E
                MOV     AX, DX                  ; 8B C2
                SUB     BP, AX                  ; 2B E8
                MOV     CX, DX                  ; 8B CA
                LODSB                           ; AC
                ADD     SI, 3                   ; 83 C6 03
                OR      AL, AL                  ; 0A C0
                JZ      SHORT $+4               ; 74 02
                STOSB                           ; AA
                DEC     DI                      ; 4F
                INC     DI                      ; 47
                LOOP    SHORT $-0BH             ; E2 F3
                ADD     SI, BX                  ; 03 F3
                ADD     DI, BP                  ; 03 FD
                DEC     WORD PTR cs:[1654H]     ; 2E FF 0E 54 16
                JNZ     SHORT $-18H             ; 75 E6
                POP     WORD PTR cs:[1654H]     ; 2E 8F 06 54 16
                POP     DX                      ; 5A
                MOV     AX, cs:[1650H]          ; 2E A1 50 16
                OR      AX, AX                  ; 0B C0
                JNZ     SHORT $+8               ; 75 06
                ADD     WORD PTR cs:[164EH], 4  ; 2E 83 06 4E 16 04
                MOV     AX, cs:[1650H]          ; 2E A1 50 16
                XOR     AX, 3                   ; 35 03 00
                SHL     AX, 1                   ; D1 E0
                ADD     AX, 1B62H               ; 05 62 1B
                MOV     SI, 1                   ; BE 01 00
                PUSH    BX                      ; 53
                XOR     BX, BX                  ; 33 DB
                JMP     AX                      ; FF E0
                ; slide at 0x1B62
                ADD     BX, SI                  ; 03 DE
                ADD     BX, SI                  ; 03 DE
                ADD     BX, SI                  ; 03 DE
                MOV     AX, BX                  ; 8B C3
                POP     BX                      ; 5B
                ADD     AX, cs:[164EH]          ; 2E 03 06 4E 16
                MOV     SI, AX                  ; 8B F0
                MOV     AX, cs:[1650H]          ; 2E A1 50 16
                INC     AX                      ; 40
                AND     AX, 3                   ; 25 03 00
                MOV     cs:[1650H], AX          ; 2E A3 50 16
                PUSH    DX                      ; 52
                MOV     CL, cs:[1652H]          ; 2E 8A 0E 52 16
                MOV     DI, cs:[1658H]          ; 2E 8B 3E 58 16
                MOV     AL, 1                   ; B0 01
                SHL     AL, CL                  ; D2 E0
                INC     WORD PTR cs:[1652H]     ; 2E FF 06 52 16
                CMP     AL, 10H                 ; 3C 10
                JNZ     SHORT $+0EH             ; 75 0C
                INC     DI                      ; 47
                MOV     cs:[1658H], DI          ; 2E 89 3E 58 16
                MOV     AL, 1                   ; B0 01
                MOV     cs:[1652H], AL          ; 2E A2 52 16
                MOV     DX, 03C5H               ; BA C5 03
                OUT     DX, AL                  ; EE
                POP     DX                      ; 5A
                ; --- Lane 1
                MOV     BP, 50H                 ; BD 50 00
                PUSH    DX                      ; 52
                PUSH    WORD PTR cs:[1654H]     ; 2E FF 36 54 16
                ADD     DX, 2                   ; 83 C2 02
                MOV     BX, cs:[164AH]          ; 2E 8B 1E 4A 16
                ADD     BX, 1                   ; 83 C3 01
                AND     BX, 0FFFCH              ; 83 E3 FC
                MOV     AX, cs:[1656H]          ; 2E A1 56 16
                SHL     AX, 1                   ; D1 E0
                SUB     BX, AX                  ; 2B D8
                SHR     DX, 1                   ; D1 EA
                SHR     DX, 1                   ; D1 EA
                JZ      SHORT $+20H             ; 74 1E
                MOV     AX, DX                  ; 8B C2
                SUB     BP, AX                  ; 2B E8
                MOV     CX, DX                  ; 8B CA
                LODSB                           ; AC
                ADD     SI, 3                   ; 83 C6 03
                OR      AL, AL                  ; 0A C0
                JZ      SHORT $+4               ; 74 02
                STOSB                           ; AA
                DEC     DI                      ; 4F
                INC     DI                      ; 47
                LOOP    SHORT $-0BH             ; E2 F3
                ADD     SI, BX                  ; 03 F3
                ADD     DI, BP                  ; 03 FD
                DEC     WORD PTR cs:[1654H]     ; 2E FF 0E 54 16
                JNZ     SHORT $-18H             ; 75 E6
                POP     WORD PTR cs:[1654H]     ; 2E 8F 06 54 16
                POP     DX                      ; 5A
                MOV     AX, cs:[1650H]          ; 2E A1 50 16
                OR      AX, AX                  ; 0B C0
                JNZ     SHORT $+8               ; 75 06
                ADD     WORD PTR cs:[164EH], 4  ; 2E 83 06 4E 16 04
                MOV     AX, cs:[1650H]          ; 2E A1 50 16
                XOR     AX, 3                   ; 35 03 00
                SHL     AX, 1                   ; D1 E0
                ADD     AX, 1C12H               ; 05 12 1C
                MOV     SI, 1                   ; BE 01 00
                PUSH    BX                      ; 53
                XOR     BX, BX                  ; 33 DB
                JMP     AX                      ; FF E0
                ; slide at 0x1C12
                ADD     BX, SI                  ; 03 DE
                ADD     BX, SI                  ; 03 DE
                ADD     BX, SI                  ; 03 DE
                MOV     AX, BX                  ; 8B C3
                POP     BX                      ; 5B
                ADD     AX, cs:[164EH]          ; 2E 03 06 4E 16
                MOV     SI, AX                  ; 8B F0
                MOV     AX, cs:[1650H]          ; 2E A1 50 16
                INC     AX                      ; 40
                AND     AX, 3                   ; 25 03 00
                MOV     cs:[1650H], AX          ; 2E A3 50 16
                PUSH    DX                      ; 52
                MOV     CL, cs:[1652H]          ; 2E 8A 0E 52 16
                MOV     DI, cs:[1658H]          ; 2E 8B 3E 58 16
                MOV     AL, 1                   ; B0 01
                SHL     AL, CL                  ; D2 E0
                INC     WORD PTR cs:[1652H]     ; 2E FF 06 52 16
                CMP     AL, 10H                 ; 3C 10
                JNZ     SHORT $+0EH             ; 75 0C
                INC     DI                      ; 47
                MOV     cs:[1658H], DI          ; 2E 89 3E 58 16
                MOV     AL, 1                   ; B0 01
                MOV     cs:[1652H], AL          ; 2E A2 52 16
                MOV     DX, 03C5H               ; BA C5 03
                OUT     DX, AL                  ; EE
                POP     DX                      ; 5A
                ; --- Lane 2
                MOV     BP, 50H                 ; BD 50 00
                PUSH    DX                      ; 52
                PUSH    WORD PTR cs:[1654H]     ; 2E FF 36 54 16
                ADD     DX, 1                   ; 83 C2 01
                MOV     BX, cs:[164AH]          ; 2E 8B 1E 4A 16
                ADD     BX, 2                   ; 83 C3 02
                AND     BX, 0FFFCH              ; 83 E3 FC
                MOV     AX, cs:[1656H]          ; 2E A1 56 16
                SHL     AX, 1                   ; D1 E0
                SUB     BX, AX                  ; 2B D8
                SHR     DX, 1                   ; D1 EA
                SHR     DX, 1                   ; D1 EA
                JZ      SHORT $+20H             ; 74 1E
                MOV     AX, DX                  ; 8B C2
                SUB     BP, AX                  ; 2B E8
                MOV     CX, DX                  ; 8B CA
                LODSB                           ; AC
                ADD     SI, 3                   ; 83 C6 03
                OR      AL, AL                  ; 0A C0
                JZ      SHORT $+4               ; 74 02
                STOSB                           ; AA
                DEC     DI                      ; 4F
                INC     DI                      ; 47
                LOOP    SHORT $-0BH             ; E2 F3
                ADD     SI, BX                  ; 03 F3
                ADD     DI, BP                  ; 03 FD
                DEC     WORD PTR cs:[1654H]     ; 2E FF 0E 54 16
                JNZ     SHORT $-18H             ; 75 E6
                POP     WORD PTR cs:[1654H]     ; 2E 8F 06 54 16
                POP     DX                      ; 5A
                MOV     AX, cs:[1650H]          ; 2E A1 50 16
                OR      AX, AX                  ; 0B C0
                JNZ     SHORT $+8               ; 75 06
                ADD     WORD PTR cs:[164EH], 4  ; 2E 83 06 4E 16 04
                MOV     AX, cs:[1650H]          ; 2E A1 50 16
                XOR     AX, 3                   ; 35 03 00
                SHL     AX, 1                   ; D1 E0
                ADD     AX, 1CC2H               ; 05 C2 1C
                MOV     SI, 1                   ; BE 01 00
                PUSH    BX                      ; 53
                XOR     BX, BX                  ; 33 DB
                JMP     AX                      ; FF E0
                ; slide at 0x1CC2
                ADD     BX, SI                  ; 03 DE
                ADD     BX, SI                  ; 03 DE
                ADD     BX, SI                  ; 03 DE
                MOV     AX, BX                  ; 8B C3
                POP     BX                      ; 5B
                ADD     AX, cs:[164EH]          ; 2E 03 06 4E 16
                MOV     SI, AX                  ; 8B F0
                MOV     AX, cs:[1650H]          ; 2E A1 50 16
                INC     AX                      ; 40
                AND     AX, 3                   ; 25 03 00
                MOV     cs:[1650H], AX          ; 2E A3 50 16
                PUSH    DX                      ; 52
                MOV     CL, cs:[1652H]          ; 2E 8A 0E 52 16
                MOV     DI, cs:[1658H]          ; 2E 8B 3E 58 16
                MOV     AL, 1                   ; B0 01
                SHL     AL, CL                  ; D2 E0
                INC     WORD PTR cs:[1652H]     ; 2E FF 06 52 16
                CMP     AL, 10H                 ; 3C 10
                JNZ     SHORT $+0EH             ; 75 0C
                INC     DI                      ; 47
                MOV     cs:[1658H], DI          ; 2E 89 3E 58 16
                MOV     AL, 1                   ; B0 01
                MOV     cs:[1652H], AL          ; 2E A2 52 16
                MOV     DX, 03C5H               ; BA C5 03
                OUT     DX, AL                  ; EE
                POP     DX                      ; 5A
                ; --- Lane 3
                MOV     BP, 50H                 ; BD 50 00
                PUSH    DX                      ; 52
                PUSH    WORD PTR cs:[1654H]     ; 2E FF 36 54 16
                ADD     DX, 0                   ; 83 C2 00
                MOV     BX, cs:[164AH]          ; 2E 8B 1E 4A 16
                ADD     BX, 3                   ; 83 C3 03
                AND     BX, 0FFFCH              ; 83 E3 FC
                MOV     AX, cs:[1656H]          ; 2E A1 56 16
                SHL     AX, 1                   ; D1 E0
                SUB     BX, AX                  ; 2B D8
                SHR     DX, 1                   ; D1 EA
                SHR     DX, 1                   ; D1 EA
                JZ      SHORT $+20H             ; 74 1E
                MOV     AX, DX                  ; 8B C2
                SUB     BP, AX                  ; 2B E8
                MOV     CX, DX                  ; 8B CA
                LODSB                           ; AC
                ADD     SI, 3                   ; 83 C6 03
                OR      AL, AL                  ; 0A C0
                JZ      SHORT $+4               ; 74 02
                STOSB                           ; AA
                DEC     DI                      ; 4F
                INC     DI                      ; 47
                LOOP    SHORT $-0BH             ; E2 F3
                ADD     SI, BX                  ; 03 F3
                ADD     DI, BP                  ; 03 FD
                DEC     WORD PTR cs:[1654H]     ; 2E FF 0E 54 16
                JNZ     SHORT $-18H             ; 75 E6
                POP     WORD PTR cs:[1654H]     ; 2E 8F 06 54 16
                POP     DX                      ; 5A
                JMP     $+4AEH                  ; E9 AB 04   -- to epilogue @ 0x21FE
                ; ==== vga_sprite_row_hflip @ 0x1D53 ====
vga_sprite_row_hflip:
                ; --- Lane 0
                MOV     BP, 50H                 ; BD 50 00
                PUSH    DX                      ; 52
                PUSH    WORD PTR cs:[1654H]     ; 2E FF 36 54 16
                ADD     DX, 3                   ; 83 C2 03
                MOV     BX, cs:[164AH]          ; 2E 8B 1E 4A 16
                ADD     BX, 0                   ; 83 C3 00
                AND     BX, 0FFFCH              ; 83 E3 FC
                NEG     BX                      ; F7 DB
                MOV     AX, cs:[1656H]          ; 2E A1 56 16
                SHL     AX, 1                   ; D1 E0
                ADD     BX, AX                  ; 03 D8
                SHR     DX, 1                   ; D1 EA
                SHR     DX, 1                   ; D1 EA
                JZ      SHORT $+21H             ; 74 1F
                MOV     AX, DX                  ; 8B C2
                SUB     BP, AX                  ; 2B E8
                MOV     CX, DX                  ; 8B CA
                MOV     AL, [SI]                ; 8A 04
                SUB     SI, 4                   ; 83 EE 04
                OR      AL, AL                  ; 0A C0
                JZ      SHORT $+4               ; 74 02
                STOSB                           ; AA
                DEC     DI                      ; 4F
                INC     DI                      ; 47
                LOOP    SHORT $-0CH             ; E2 F2
                ADD     SI, BX                  ; 03 F3
                ADD     DI, BP                  ; 03 FD
                DEC     WORD PTR cs:[1654H]     ; 2E FF 0E 54 16
                JNZ     SHORT $-19H             ; 75 E5
                POP     WORD PTR cs:[1654H]     ; 2E 8F 06 54 16
                POP     DX                      ; 5A
                MOV     AX, cs:[1650H]          ; 2E A1 50 16
                CMP     AX, 3                   ; 3D 03 00
                JNZ     SHORT $+8               ; 75 06
                SUB     WORD PTR cs:[164EH], 4  ; 2E 83 2E 4E 16 04
                MOV     AX, cs:[1650H]          ; 2E A1 50 16
                XOR     AX, 3                   ; 35 03 00
                SHL     AX, 1                   ; D1 E0
                ADD     AX, 1DC2H               ; 05 C2 1D
                MOV     SI, 1                   ; BE 01 00
                PUSH    BX                      ; 53
                XOR     BX, BX                  ; 33 DB
                JMP     AX                      ; FF E0
                ; slide at 0x1DC2 (DEC AX path)
                ADD     BX, SI                  ; 03 DE
                ADD     BX, SI                  ; 03 DE
                ADD     BX, SI                  ; 03 DE
                MOV     AX, BX                  ; 8B C3
                POP     BX                      ; 5B
                ADD     AX, cs:[164EH]          ; 2E 03 06 4E 16
                MOV     SI, AX                  ; 8B F0
                MOV     AX, cs:[1650H]          ; 2E A1 50 16
                DEC     AX                      ; 48
                AND     AX, 3                   ; 25 03 00
                MOV     cs:[1650H], AX          ; 2E A3 50 16
                PUSH    DX                      ; 52
                MOV     CL, cs:[1652H]          ; 2E 8A 0E 52 16
                MOV     DI, cs:[1658H]          ; 2E 8B 3E 58 16
                MOV     AL, 1                   ; B0 01
                SHL     AL, CL                  ; D2 E0
                INC     WORD PTR cs:[1652H]     ; 2E FF 06 52 16
                CMP     AL, 10H                 ; 3C 10
                JNZ     SHORT $+0EH             ; 75 0C
                INC     DI                      ; 47
                MOV     cs:[1658H], DI          ; 2E 89 3E 58 16
                MOV     AL, 1                   ; B0 01
                MOV     cs:[1652H], AL          ; 2E A2 52 16
                MOV     DX, 03C5H               ; BA C5 03
                OUT     DX, AL                  ; EE
                POP     DX                      ; 5A
                ; --- Lane 1
                MOV     BP, 50H                 ; BD 50 00
                PUSH    DX                      ; 52
                PUSH    WORD PTR cs:[1654H]     ; 2E FF 36 54 16
                ADD     DX, 2                   ; 83 C2 02
                MOV     BX, cs:[164AH]          ; 2E 8B 1E 4A 16
                ADD     BX, 1                   ; 83 C3 01
                AND     BX, 0FFFCH              ; 83 E3 FC
                NEG     BX                      ; F7 DB
                MOV     AX, cs:[1656H]          ; 2E A1 56 16
                SHL     AX, 1                   ; D1 E0
                ADD     BX, AX                  ; 03 D8
                SHR     DX, 1                   ; D1 EA
                SHR     DX, 1                   ; D1 EA
                JZ      SHORT $+21H             ; 74 1F
                MOV     AX, DX                  ; 8B C2
                SUB     BP, AX                  ; 2B E8
                MOV     CX, DX                  ; 8B CA
                MOV     AL, [SI]                ; 8A 04
                SUB     SI, 4                   ; 83 EE 04
                OR      AL, AL                  ; 0A C0
                JZ      SHORT $+4               ; 74 02
                STOSB                           ; AA
                DEC     DI                      ; 4F
                INC     DI                      ; 47
                LOOP    SHORT $-0CH             ; E2 F2
                ADD     SI, BX                  ; 03 F3
                ADD     DI, BP                  ; 03 FD
                DEC     WORD PTR cs:[1654H]     ; 2E FF 0E 54 16
                JNZ     SHORT $-19H             ; 75 E5
                POP     WORD PTR cs:[1654H]     ; 2E 8F 06 54 16
                POP     DX                      ; 5A
                ; Lane 1 -> Lane 2 transition (0x1E53)
                MOV     AX, cs:[1650H]          ; 2E A1 50 16
                CMP     AX, 3                   ; 3D 03 00
                JNZ     SHORT $+8               ; 75 06
                SUB     WORD PTR cs:[164EH], 4  ; 2E 83 2E 4E 16 04
                MOV     AX, cs:[1650H]          ; 2E A1 50 16
                XOR     AX, 3                   ; 35 03 00
                SHL     AX, 1                   ; D1 E0
                ADD     AX, 1E76H               ; 05 76 1E
                MOV     SI, 1                   ; BE 01 00
                PUSH    BX                      ; 53
                XOR     BX, BX                  ; 33 DB
                JMP     AX                      ; FF E0
                ADD     BX, SI                  ; 03 DE
                ADD     BX, SI                  ; 03 DE
                ADD     BX, SI                  ; 03 DE
                MOV     AX, BX                  ; 8B C3
                POP     BX                      ; 5B
                ADD     AX, cs:[164EH]          ; 2E 03 06 4E 16
                MOV     SI, AX                  ; 8B F0
                MOV     AX, cs:[1650H]          ; 2E A1 50 16
                DEC     AX                      ; 48
                AND     AX, 3                   ; 25 03 00
                MOV     cs:[1650H], AX          ; 2E A3 50 16
                PUSH    DX                      ; 52
                MOV     CL, cs:[1652H]          ; 2E 8A 0E 52 16
                MOV     DI, cs:[1658H]          ; 2E 8B 3E 58 16
                MOV     AL, 1                   ; B0 01
                SHL     AL, CL                  ; D2 E0
                INC     WORD PTR cs:[1652H]     ; 2E FF 06 52 16
                CMP     AL, 10H                 ; 3C 10
                JNZ     SHORT $+0EH             ; 75 0C
                INC     DI                      ; 47
                MOV     cs:[1658H], DI          ; 2E 89 3E 58 16
                MOV     AL, 1                   ; B0 01
                MOV     cs:[1652H], AL          ; 2E A2 52 16
                MOV     DX, 03C5H               ; BA C5 03
                OUT     DX, AL                  ; EE
                POP     DX                      ; 5A
                ; --- Lane 2
                MOV     BP, 50H                 ; BD 50 00
                PUSH    DX                      ; 52
                PUSH    WORD PTR cs:[1654H]     ; 2E FF 36 54 16
                ADD     DX, 1                   ; 83 C2 01
                MOV     BX, cs:[164AH]          ; 2E 8B 1E 4A 16
                ADD     BX, 2                   ; 83 C3 02
                AND     BX, 0FFFCH              ; 83 E3 FC
                NEG     BX                      ; F7 DB
                MOV     AX, cs:[1656H]          ; 2E A1 56 16
                SHL     AX, 1                   ; D1 E0
                ADD     BX, AX                  ; 03 D8
                SHR     DX, 1                   ; D1 EA
                SHR     DX, 1                   ; D1 EA
                JZ      SHORT $+21H             ; 74 1F
                MOV     AX, DX                  ; 8B C2
                SUB     BP, AX                  ; 2B E8
                MOV     CX, DX                  ; 8B CA
                MOV     AL, [SI]                ; 8A 04
                SUB     SI, 4                   ; 83 EE 04
                OR      AL, AL                  ; 0A C0
                JZ      SHORT $+4               ; 74 02
                STOSB                           ; AA
                DEC     DI                      ; 4F
                INC     DI                      ; 47
                LOOP    SHORT $-0CH             ; E2 F2
                ADD     SI, BX                  ; 03 F3
                ADD     DI, BP                  ; 03 FD
                DEC     WORD PTR cs:[1654H]     ; 2E FF 0E 54 16
                JNZ     SHORT $-19H             ; 75 E5
                POP     WORD PTR cs:[1654H]     ; 2E 8F 06 54 16
                POP     DX                      ; 5A
                MOV     AX, cs:[1650H]          ; 2E A1 50 16
                CMP     AX, 3                   ; 3D 03 00
                JNZ     SHORT $+8               ; 75 06
                SUB     WORD PTR cs:[164EH], 4  ; 2E 83 2E 4E 16 04
                MOV     AX, cs:[1650H]          ; 2E A1 50 16
                XOR     AX, 3                   ; 35 03 00
                SHL     AX, 1                   ; D1 E0
                ADD     AX, 1F2AH               ; 05 2A 1F
                MOV     SI, 1                   ; BE 01 00
                PUSH    BX                      ; 53
                XOR     BX, BX                  ; 33 DB
                JMP     AX                      ; FF E0
                ; slide at 0x1F2A
                ADD     BX, SI                  ; 03 DE
                ADD     BX, SI                  ; 03 DE
                ADD     BX, SI                  ; 03 DE
                MOV     AX, BX                  ; 8B C3
                POP     BX                      ; 5B
                ADD     AX, cs:[164EH]          ; 2E 03 06 4E 16
                MOV     SI, AX                  ; 8B F0
                MOV     AX, cs:[1650H]          ; 2E A1 50 16
                DEC     AX                      ; 48
                AND     AX, 3                   ; 25 03 00
                MOV     cs:[1650H], AX          ; 2E A3 50 16
                PUSH    DX                      ; 52
                MOV     CL, cs:[1652H]          ; 2E 8A 0E 52 16
                MOV     DI, cs:[1658H]          ; 2E 8B 3E 58 16
                MOV     AL, 1                   ; B0 01
                SHL     AL, CL                  ; D2 E0
                INC     WORD PTR cs:[1652H]     ; 2E FF 06 52 16
                CMP     AL, 10H                 ; 3C 10
                JNZ     SHORT $+0EH             ; 75 0C
                INC     DI                      ; 47
                MOV     cs:[1658H], DI          ; 2E 89 3E 58 16
                MOV     AL, 1                   ; B0 01
                MOV     cs:[1652H], AL          ; 2E A2 52 16
                MOV     DX, 03C5H               ; BA C5 03
                OUT     DX, AL                  ; EE
                POP     DX                      ; 5A
                ; --- Lane 3
                MOV     BP, 50H                 ; BD 50 00
                PUSH    DX                      ; 52
                PUSH    WORD PTR cs:[1654H]     ; 2E FF 36 54 16
                ADD     DX, 0                   ; 83 C2 00
                MOV     BX, cs:[164AH]          ; 2E 8B 1E 4A 16
                ADD     BX, 3                   ; 83 C3 03
                AND     BX, 0FFFCH              ; 83 E3 FC
                NEG     BX                      ; F7 DB
                MOV     AX, cs:[1656H]          ; 2E A1 56 16
                SHL     AX, 1                   ; D1 E0
                ADD     BX, AX                  ; 03 D8
                SHR     DX, 1                   ; D1 EA
                SHR     DX, 1                   ; D1 EA
                JZ      SHORT $+21H             ; 74 1F
                MOV     AX, DX                  ; 8B C2
                SUB     BP, AX                  ; 2B E8
                MOV     CX, DX                  ; 8B CA
                MOV     AL, [SI]                ; 8A 04
                SUB     SI, 4                   ; 83 EE 04
                OR      AL, AL                  ; 0A C0
                JZ      SHORT $+4               ; 74 02
                STOSB                           ; AA
                DEC     DI                      ; 4F
                INC     DI                      ; 47
                LOOP    SHORT $-0CH             ; E2 F2
                ADD     SI, BX                  ; 03 F3
                ADD     DI, BP                  ; 03 FD
                DEC     WORD PTR cs:[1654H]     ; 2E FF 0E 54 16
                JNZ     SHORT $-19H             ; 75 E5
                POP     WORD PTR cs:[1654H]     ; 2E 8F 06 54 16
                POP     DX                      ; 5A
                JMP     $+243H                  ; E9 40 02   -- to epilogue @ 0x21FE
                ; ==== vga_sprite_row_vhflip @ 0x1FBE ====
vga_sprite_row_vhflip:
                ; --- Lane 0
                MOV     BP, 50H                 ; BD 50 00
                PUSH    DX                      ; 52
                PUSH    WORD PTR cs:[1654H]     ; 2E FF 36 54 16
                ADD     DX, 3                   ; 83 C2 03
                MOV     BX, cs:[164AH]          ; 2E 8B 1E 4A 16
                ADD     BX, 0                   ; 83 C3 00
                AND     BX, 0FFFCH              ; 83 E3 FC
                SHR     DX, 1                   ; D1 EA
                SHR     DX, 1                   ; D1 EA
                JZ      SHORT $+21H             ; 74 1F
                MOV     AX, DX                  ; 8B C2
                SUB     BP, AX                  ; 2B E8
                MOV     CX, DX                  ; 8B CA
                MOV     AL, [SI]                ; 8A 04
                SUB     SI, 4                   ; 83 EE 04
                OR      AL, AL                  ; 0A C0
                JZ      SHORT $+4               ; 74 02
                STOSB                           ; AA
                DEC     DI                      ; 4F
                INC     DI                      ; 47
                LOOP    SHORT $-0CH             ; E2 F2
                SUB     SI, BX                  ; 2B F3
                ADD     DI, BP                  ; 03 FD
                DEC     WORD PTR cs:[1654H]     ; 2E FF 0E 54 16
                JNZ     SHORT $-19H             ; 75 E5
                POP     WORD PTR cs:[1654H]     ; 2E 8F 06 54 16
                POP     DX                      ; 5A
                MOV     AX, cs:[1650H]          ; 2E A1 50 16
                CMP     AX, 3                   ; 3D 03 00
                JNZ     SHORT $+8               ; 75 06
                SUB     WORD PTR cs:[164EH], 4  ; 2E 83 2E 4E 16 04
                MOV     AX, cs:[1650H]          ; 2E A1 50 16
                XOR     AX, 3                   ; 35 03 00
                SHL     AX, 1                   ; D1 E0
                ADD     AX, 2023H               ; 05 23 20
                MOV     SI, 1                   ; BE 01 00
                PUSH    BX                      ; 53
                XOR     BX, BX                  ; 33 DB
                JMP     AX                      ; FF E0
                ; slide at 0x2023
                ADD     BX, SI                  ; 03 DE
                ADD     BX, SI                  ; 03 DE
                ADD     BX, SI                  ; 03 DE
                MOV     AX, BX                  ; 8B C3
                POP     BX                      ; 5B
                ADD     AX, cs:[164EH]          ; 2E 03 06 4E 16
                MOV     SI, AX                  ; 8B F0
                MOV     AX, cs:[1650H]          ; 2E A1 50 16
                DEC     AX                      ; 48
                AND     AX, 3                   ; 25 03 00
                MOV     cs:[1650H], AX          ; 2E A3 50 16
                PUSH    DX                      ; 52
                MOV     CL, cs:[1652H]          ; 2E 8A 0E 52 16
                MOV     DI, cs:[1658H]          ; 2E 8B 3E 58 16
                MOV     AL, 1                   ; B0 01
                SHL     AL, CL                  ; D2 E0
                INC     WORD PTR cs:[1652H]     ; 2E FF 06 52 16
                CMP     AL, 10H                 ; 3C 10
                JNZ     SHORT $+0EH             ; 75 0C
                INC     DI                      ; 47
                MOV     cs:[1658H], DI          ; 2E 89 3E 58 16
                MOV     AL, 1                   ; B0 01
                MOV     cs:[1652H], AL          ; 2E A2 52 16
                MOV     DX, 03C5H               ; BA C5 03
                OUT     DX, AL                  ; EE
                POP     DX                      ; 5A
                ; --- Lane 1
                MOV     BP, 50H                 ; BD 50 00
                PUSH    DX                      ; 52
                PUSH    WORD PTR cs:[1654H]     ; 2E FF 36 54 16
                ADD     DX, 2                   ; 83 C2 02
                MOV     BX, cs:[164AH]          ; 2E 8B 1E 4A 16
                ADD     BX, 1                   ; 83 C3 01
                AND     BX, 0FFFCH              ; 83 E3 FC
                SHR     DX, 1                   ; D1 EA
                SHR     DX, 1                   ; D1 EA
                JZ      SHORT $+21H             ; 74 1F
                MOV     AX, DX                  ; 8B C2
                SUB     BP, AX                  ; 2B E8
                MOV     CX, DX                  ; 8B CA
                MOV     AL, [SI]                ; 8A 04
                SUB     SI, 4                   ; 83 EE 04
                OR      AL, AL                  ; 0A C0
                JZ      SHORT $+4               ; 74 02
                STOSB                           ; AA
                DEC     DI                      ; 4F
                INC     DI                      ; 47
                LOOP    SHORT $-0CH             ; E2 F2
                SUB     SI, BX                  ; 2B F3
                ADD     DI, BP                  ; 03 FD
                DEC     WORD PTR cs:[1654H]     ; 2E FF 0E 54 16
                JNZ     SHORT $-19H             ; 75 E5
                POP     WORD PTR cs:[1654H]     ; 2E 8F 06 54 16
                POP     DX                      ; 5A
                MOV     AX, cs:[1650H]          ; 2E A1 50 16
                CMP     AX, 3                   ; 3D 03 00
                JNZ     SHORT $+8               ; 75 06
                SUB     WORD PTR cs:[164EH], 4  ; 2E 83 2E 4E 16 04
                MOV     AX, cs:[1650H]          ; 2E A1 50 16
                XOR     AX, 3                   ; 35 03 00
                SHL     AX, 1                   ; D1 E0
                ADD     AX, 20CDH               ; 05 CD 20
                MOV     SI, 1                   ; BE 01 00
                PUSH    BX                      ; 53
                XOR     BX, BX                  ; 33 DB
                JMP     AX                      ; FF E0
                ; slide at 0x20CD
                ADD     BX, SI                  ; 03 DE
                ADD     BX, SI                  ; 03 DE
                ADD     BX, SI                  ; 03 DE
                MOV     AX, BX                  ; 8B C3
                POP     BX                      ; 5B
                ADD     AX, cs:[164EH]          ; 2E 03 06 4E 16
                MOV     SI, AX                  ; 8B F0
                MOV     AX, cs:[1650H]          ; 2E A1 50 16
                DEC     AX                      ; 48
                AND     AX, 3                   ; 25 03 00
                MOV     cs:[1650H], AX          ; 2E A3 50 16
                PUSH    DX                      ; 52
                MOV     CL, cs:[1652H]          ; 2E 8A 0E 52 16
                MOV     DI, cs:[1658H]          ; 2E 8B 3E 58 16
                MOV     AL, 1                   ; B0 01
                SHL     AL, CL                  ; D2 E0
                INC     WORD PTR cs:[1652H]     ; 2E FF 06 52 16
                CMP     AL, 10H                 ; 3C 10
                JNZ     SHORT $+0EH             ; 75 0C
                INC     DI                      ; 47
                MOV     cs:[1658H], DI          ; 2E 89 3E 58 16
                MOV     AL, 1                   ; B0 01
                MOV     cs:[1652H], AL          ; 2E A2 52 16
                MOV     DX, 03C5H               ; BA C5 03
                OUT     DX, AL                  ; EE
                POP     DX                      ; 5A
                ; --- Lane 2
                MOV     BP, 50H                 ; BD 50 00
                PUSH    DX                      ; 52
                PUSH    WORD PTR cs:[1654H]     ; 2E FF 36 54 16
                ADD     DX, 1                   ; 83 C2 01
                MOV     BX, cs:[164AH]          ; 2E 8B 1E 4A 16
                ADD     BX, 2                   ; 83 C3 02
                AND     BX, 0FFFCH              ; 83 E3 FC
                SHR     DX, 1                   ; D1 EA
                SHR     DX, 1                   ; D1 EA
                JZ      SHORT $+21H             ; 74 1F
                MOV     AX, DX                  ; 8B C2
                SUB     BP, AX                  ; 2B E8
                MOV     CX, DX                  ; 8B CA
                MOV     AL, [SI]                ; 8A 04
                SUB     SI, 4                   ; 83 EE 04
                OR      AL, AL                  ; 0A C0
                JZ      SHORT $+4               ; 74 02
                STOSB                           ; AA
                DEC     DI                      ; 4F
                INC     DI                      ; 47
                LOOP    SHORT $-0CH             ; E2 F2
                SUB     SI, BX                  ; 2B F3
                ADD     DI, BP                  ; 03 FD
                DEC     WORD PTR cs:[1654H]     ; 2E FF 0E 54 16
                JNZ     SHORT $-19H             ; 75 E5
                POP     WORD PTR cs:[1654H]     ; 2E 8F 06 54 16
                POP     DX                      ; 5A
                MOV     AX, cs:[1650H]          ; 2E A1 50 16
                CMP     AX, 3                   ; 3D 03 00
                JNZ     SHORT $+8               ; 75 06
                SUB     WORD PTR cs:[164EH], 4  ; 2E 83 2E 4E 16 04
                MOV     AX, cs:[1650H]          ; 2E A1 50 16
                XOR     AX, 3                   ; 35 03 00
                SHL     AX, 1                   ; D1 E0
                ADD     AX, 2177H               ; 05 77 21
                MOV     SI, 1                   ; BE 01 00
                PUSH    BX                      ; 53
                XOR     BX, BX                  ; 33 DB
                JMP     AX                      ; FF E0
                ; slide at 0x2177
                ADD     BX, SI                  ; 03 DE
                ADD     BX, SI                  ; 03 DE
                ADD     BX, SI                  ; 03 DE
                MOV     AX, BX                  ; 8B C3
                POP     BX                      ; 5B
                ADD     AX, cs:[164EH]          ; 2E 03 06 4E 16
                MOV     SI, AX                  ; 8B F0
                MOV     AX, cs:[1650H]          ; 2E A1 50 16
                DEC     AX                      ; 48
                AND     AX, 3                   ; 25 03 00
                MOV     cs:[1650H], AX          ; 2E A3 50 16
                PUSH    DX                      ; 52
                MOV     CL, cs:[1652H]          ; 2E 8A 0E 52 16
                MOV     DI, cs:[1658H]          ; 2E 8B 3E 58 16
                MOV     AL, 1                   ; B0 01
                SHL     AL, CL                  ; D2 E0
                INC     WORD PTR cs:[1652H]     ; 2E FF 06 52 16
                CMP     AL, 10H                 ; 3C 10
                JNZ     SHORT $+0EH             ; 75 0C
                INC     DI                      ; 47
                MOV     cs:[1658H], DI          ; 2E 89 3E 58 16
                MOV     AL, 1                   ; B0 01
                MOV     cs:[1652H], AL          ; 2E A2 52 16
                MOV     DX, 03C5H               ; BA C5 03
                OUT     DX, AL                  ; EE
                POP     DX                      ; 5A
                ; --- Lane 3
                MOV     BP, 50H                 ; BD 50 00
                PUSH    DX                      ; 52
                PUSH    WORD PTR cs:[1654H]     ; 2E FF 36 54 16
                ADD     DX, 0                   ; 83 C2 00
                MOV     BX, cs:[164AH]          ; 2E 8B 1E 4A 16
                ADD     BX, 3                   ; 83 C3 03
                AND     BX, 0FFFCH              ; 83 E3 FC
                SHR     DX, 1                   ; D1 EA
                SHR     DX, 1                   ; D1 EA
                JZ      SHORT $+21H             ; 74 1F
                MOV     AX, DX                  ; 8B C2
                SUB     BP, AX                  ; 2B E8
                MOV     CX, DX                  ; 8B CA
                MOV     AL, [SI]                ; 8A 04
                SUB     SI, 4                   ; 83 EE 04
                OR      AL, AL                  ; 0A C0
                JZ      SHORT $+4               ; 74 02
                STOSB                           ; AA
                DEC     DI                      ; 4F
                INC     DI                      ; 47
                LOOP    SHORT $-0CH             ; E2 F2
                SUB     SI, BX                  ; 2B F3
                ADD     DI, BP                  ; 03 FD
                DEC     WORD PTR cs:[1654H]     ; 2E FF 0E 54 16
                JNZ     SHORT $-19H             ; 75 E5
                POP     WORD PTR cs:[1654H]     ; 2E 8F 06 54 16
                POP     DX                      ; 5A
                ; --- shared epilogue @ 0x21FE
vga_bsm_epilogue:
                POP     WORD PTR cs:[1658H]     ; 2E 8F 06 58 16
                POP     WORD PTR cs:[1656H]     ; 2E 8F 06 56 16
                POP     WORD PTR cs:[1654H]     ; 2E 8F 06 54 16
                POP     WORD PTR cs:[1652H]     ; 2E 8F 06 52 16
                POP     WORD PTR cs:[1650H]     ; 2E 8F 06 50 16
                POP     WORD PTR cs:[164EH]     ; 2E 8F 06 4E 16
                POP     WORD PTR cs:[164CH]     ; 2E 8F 06 4C 16
                POP     WORD PTR cs:[164AH]     ; 2E 8F 06 4A 16
                POP     DS                      ; 1F
                POP     ES                      ; 07
                POP     SI                      ; 5E
                POP     DI                      ; 5F
                ADD     SP, 0AH                 ; 83 C4 0A
                POP     BP                      ; 5D
                RETF                            ; CB
vga_blit_sprite_master ENDP

; ============================================================================
; 0x222F..0x2230 -- 2-byte pad before vga_blit_sprite_flip_h.
; ============================================================================
g_abVgaSpritePad222F            DB      0, 0    ; 0x222F

; ============================================================================
; vga_blit_sprite_flip_h -- 8x-unrolled VRAM rectangle copy (write-mode 1).
; chunk:0x2231..0x22CB
;
; ABI (__cdecl16far): [BP+6]=src_off (planar), [BP+8]=src_seg,
;   [BP+0Ah] = packed x,y bundle.
;
; Misleadingly named: this function does NOT perform a horizontal flip.
; It is a generic VRAM-to-VRAM rectangle copy with the per-row body
; unrolled 8x. Each row does:
;     MOV CX, BX    ; row byte count
;     REP MOVSB
;     ADD DI, BP    ; advance dst to next row (stride - count)
;     DEC DX        ; remaining rows
;     JZ done
; ...repeated 8 times in straight-line code, with a JNZ at the bottom
; that jumps back to the top of the unrolled block when 8 rows are
; insufficient. The "8x" is straight loop unrolling, not Duff's device
; (no jump-in-middle).
;
; Map Mask is set to 0x0F (all planes) and GC Mode is set to write-
; mode 1 (latch-copy) before the loop, so each MOVSB copies a 4-plane
; byte's worth of pixels with one instruction.
;
; Internal jumps use TASM's `$+N` / `$-N` self-relative form rather
; than named labels (see the matching note on vga_blit_sprite_master).
; ============================================================================
vga_blit_sprite_flip_h PROC FAR
                PUSH    BP                      ; 55
                MOV     BP, SP                  ; 8B EC
                PUSH    SI                      ; 56
                PUSH    DI                      ; 57
                PUSH    DS                      ; 1E
                MOV     DS, cs:[0F4H]           ; 2E 8E 1E F4 00
                MOV     DI, [BP+0AH]            ; 8B 7E 0A
                SHL     DI, 1                   ; D1 E7
                MOV     DI, [DI].GfxContext.pRow_offset_lut          ; 8B BD F2 06
                MOV     AX, [BP+8]              ; 8B 46 08
                SHR     AX, 1                   ; D1 E8
                SHR     AX, 1                   ; D1 E8
                ADD     DI, AX                  ; 03 F8
                MOV     BP, [BP+6]              ; 8B 6E 06
                MOV     ES, ds:[GfxContext.wGfxBlitDstPage]            ; 8E 06 18 00
                MOV     DX, 03C4H               ; BA C4 03
                MOV     AX, 0F02H               ; B8 02 0F
                OUT     DX, AX                  ; EF
                MOV     DX, 03CEH               ; BA CE 03
                MOV     AX, 4105H               ; B8 05 41  GR5 = 41h: WM=01 (latch copy), Shift256=1
                OUT     DX, AX                  ; EF
                MOV     DX, [BP+8]              ; 8B 56 08
                MOV     BX, [BP+6]              ; 8B 5E 06
                SHR     BX, 1                   ; D1 EB
                SHR     BX, 1                   ; D1 EB
                MOV     SI, [BP+2]              ; 8B 76 02
                MOV     DS, [BP+0]              ; 8E 5E 00
                MOV     BP, 50H                 ; BD 50 00
                SUB     BP, BX                  ; 2B EB
                ; 8x unrolled row loop (7 JZ + 1 JNZ)
                MOV     CX, BX                  ; 8B CB    -- row 1
                REP     MOVSB                   ; F3 A4
                ADD     DI, BP                  ; 03 FD
                DEC     DX                      ; 4A
                JZ      SHORT $+41H             ; 74 3F
                MOV     CX, BX                  ; 8B CB    -- row 2
                REP     MOVSB                   ; F3 A4
                ADD     DI, BP                  ; 03 FD
                DEC     DX                      ; 4A
                JZ      SHORT $+38H             ; 74 36
                MOV     CX, BX                  ; 8B CB    -- row 3
                REP     MOVSB                   ; F3 A4
                ADD     DI, BP                  ; 03 FD
                DEC     DX                      ; 4A
                JZ      SHORT $+2FH             ; 74 2D
                MOV     CX, BX                  ; 8B CB    -- row 4
                REP     MOVSB                   ; F3 A4
                ADD     DI, BP                  ; 03 FD
                DEC     DX                      ; 4A
                JZ      SHORT $+26H             ; 74 24
                MOV     CX, BX                  ; 8B CB    -- row 5
                REP     MOVSB                   ; F3 A4
                ADD     DI, BP                  ; 03 FD
                DEC     DX                      ; 4A
                JZ      SHORT $+1DH             ; 74 1B
                MOV     CX, BX                  ; 8B CB    -- row 6
                REP     MOVSB                   ; F3 A4
                ADD     DI, BP                  ; 03 FD
                DEC     DX                      ; 4A
                JZ      SHORT $+14H             ; 74 12
                MOV     CX, BX                  ; 8B CB    -- row 7
                REP     MOVSB                   ; F3 A4
                ADD     DI, BP                  ; 03 FD
                DEC     DX                      ; 4A
                JZ      SHORT $+0BH             ; 74 09
                MOV     CX, BX                  ; 8B CB    -- row 8 (loop back)
                REP     MOVSB                   ; F3 A4
                ADD     DI, BP                  ; 03 FD
                DEC     DX                      ; 4A
                JNZ     SHORT $-46H             ; 75 B8
                MOV     DX, 03CEH               ; BA CE 03
                MOV     AX, 4005H               ; B8 05 40  GR5 = 40h: WM=00 (normal), Shift256=1
                OUT     DX, AX                  ; EF
                POP     DS                      ; 1F
                POP     DI                      ; 5F
                POP     SI                      ; 5E
                POP     BP                      ; 5D
                RETF                            ; CB
vga_blit_sprite_flip_h ENDP

; ============================================================================
; vga_blit_sprite_flip_v -- sprite-list cache decoder (with DOS free).
; chunk:0x22CC..0x2377
;
; Walks a NULL-terminated descriptor list at DS:BX (init from [BP+6])
; and decodes each sprite to plane bytes in segment 0xAC00 (writes
; via Sequencer Map Mask 0x102 rotating). After the loop, frees the
; allocated decode segment via INT 21h AH=49h (Free Memory; see
; Ralf Brown's Interrupt List INT 21h AH=49h).
;
; The inner loop FIRST writes GC reg 5 = 40h (Write Mode 0, normal
; CPU-data-into-planes), then alternates Map Mask 0x01..0x08 for the
; four plane lanes -- the GR5 reset matters because the engine may
; have left write-mode 1 set from a prior vga_present / blit_rect.
;
; The 2-byte slot at 0x222F is the running write-pointer into AC00.
;
; Internal jumps use TASM's `$+N` / `$-N` self-relative form rather
; than named labels (see the matching note on vga_blit_sprite_master).
; ============================================================================
vga_blit_sprite_flip_v PROC FAR
                PUSH    BP                      ; 55
                MOV     BP, SP                  ; 8B EC
                PUSH    DI                      ; 57
                PUSH    SI                      ; 56
                MOV     BP, [BP+6]              ; 8B 6E 06
                MOV     BX, [BP+0]              ; 8B 5E 00
                PUSH    BP                      ; 55
                PUSH    WORD PTR [BX]           ; FF 37
                MOV     BX, [BP+0]              ; 8B 5E 00
                ADD     BP, 2                   ; 83 C5 02
vga_bsfv_loop:
                OR      BX, BX                  ; 0B DB
                JZ      SHORT $+7EH             ; 74 7C   -- to vga_bsfv_free @ 0x2360
                MOV     AX, 0AC00H              ; B8 00 AC
                MOV     ES, AX                  ; 8E C0
                MOV     DI, cs:[222FH]          ; 2E 8B 3E 2F 22
                MOV     SI, [BX+2]              ; 8B 77 02
                MOV     [BX+2], DI              ; 89 7F 02
                MOV     AX, [BX+6]              ; 8B 47 06
                XOR     DX, DX                  ; 33 D2
                MUL     WORD PTR [BX+8]         ; F7 67 08
                SHR     AX, 1                   ; D1 E8
                SHR     AX, 1                   ; D1 E8
                ADD     cs:[222FH], AX          ; 2E 01 06 2F 22
                MOV     CX, AX                  ; 8B C8
                PUSH    DS                      ; 1E
                MOV     AX, [BX]                ; 8B 07
                MOV     DX, ES                  ; 8C C2
                MOV     [BX], DX                ; 89 17
                MOV     DS, AX                  ; 8E D8
                MOV     AX, 4005H               ; B8 05 40   GC reg5 writemode 0
                MOV     DX, 03CEH               ; BA CE 03
                OUT     DX, AX                  ; EF
                MOV     AX, 0102H               ; B8 02 01   Map Mask plane 0
                MOV     DX, 03C4H               ; BA C4 03
                PUSH    SI                      ; 56
                PUSH    CX                      ; 51
                PUSH    DI                      ; 57
                OUT     DX, AX                  ; EF
                SHL     AH, 1                   ; D0 E4
                MOVSB                           ; A4
                ADD     SI, 3                   ; 83 C6 03
                LOOP    SHORT $-4               ; E2 FA
                POP     DI                      ; 5F
                POP     CX                      ; 59
                POP     SI                      ; 5E
                INC     SI                      ; 46
                PUSH    SI                      ; 56
                PUSH    CX                      ; 51
                PUSH    DI                      ; 57
                OUT     DX, AX                  ; EF
                SHL     AH, 1                   ; D0 E4
                MOVSB                           ; A4
                ADD     SI, 3                   ; 83 C6 03
                LOOP    SHORT $-4               ; E2 FA
                POP     DI                      ; 5F
                POP     CX                      ; 59
                POP     SI                      ; 5E
                INC     SI                      ; 46
                PUSH    SI                      ; 56
                PUSH    CX                      ; 51
                PUSH    DI                      ; 57
                OUT     DX, AX                  ; EF
                SHL     AH, 1                   ; D0 E4
                MOVSB                           ; A4
                ADD     SI, 3                   ; 83 C6 03
                LOOP    SHORT $-4               ; E2 FA
                POP     DI                      ; 5F
                POP     CX                      ; 59
                POP     SI                      ; 5E
                INC     SI                      ; 46
                PUSH    SI                      ; 56
                PUSH    CX                      ; 51
                PUSH    DI                      ; 57
                OUT     DX, AX                  ; EF
                MOVSB                           ; A4
                ADD     SI, 3                   ; 83 C6 03
                LOOP    SHORT $-4               ; E2 FA
                SHL     AH, 1                   ; D0 E4
                POP     DI                      ; 5F
                POP     CX                      ; 59
                POP     SI                      ; 5E
                POP     DS                      ; 1F
                JMP     $-83H                   ; E9 7A FF   -- back to 0x22DA
                ; vga_bsfv_free @ 0x2360
                POP     ES                      ; 07
                MOV     AH, 49H                 ; B4 49
                INT     21H                     ; CD 21      -- DOS free memory block
                MOV     AX, 4005H               ; B8 05 40
                MOV     DX, 03CEH               ; BA CE 03
                OUT     DX, AX                  ; EF
                MOV     AX, 0F02H               ; B8 02 0F
                MOV     DX, 03C4H               ; BA C4 03
                OUT     DX, AX                  ; EF
                POP     AX                      ; 58
                POP     SI                      ; 5E
                POP     DI                      ; 5F
                POP     BP                      ; 5D
                RETF                            ; CB
vga_blit_sprite_flip_v ENDP

; ============================================================================
; vga_clear_rect_state -- reset the sprite-write cache pointer.
; chunk:0x2378..0x237E
; ============================================================================
vga_clear_rect_state PROC FAR
                XOR     AX, AX                  ; 33 C0
                MOV     cs:[222FH], AX          ; 2E A3 2F 22
                RETF                            ; CB
vga_clear_rect_state ENDP

; ============================================================================
; 0x237F..0x238C -- sprite-simple scratch (zero on disk).
; ============================================================================
g_awVgaSpriteSimpleScratch      DW      0, 0, 0, 0, 0, 0, 0   ; 0x237F (14 bytes)

; ============================================================================
; vga_blit_sprite_simple -- "simple" (no flip) sprite blitter using its own
; scratch area at 0x237F..0x238C and a fixed 4-plane lane unroll.
; chunk:0x238D..0x2729
;
; Same basic shape as vga_blit_sprite_master but specialised to flip=0
; (no NEG BX, no sliding INC/DEC). The 4 plane lanes are emitted as
; straight-line code rather than reached via a dispatch table because
; only the no-flip arrangement is needed. Uses its own private scratch
; words at:
;   0x237F  g_w164a-equivalent (width_quads)
;   0x2381  g_w164e-equivalent (src_byte_off)
;   0x2383  g_w1650-equivalent (plane index)
;   0x2385  g_w1652-equivalent (Map Mask bit)
;   0x2387  g_w1654-equivalent (height counter)
;   0x2389  g_w1656-equivalent (original width)
;   0x238B  g_w1658-equivalent (FB dest ptr)
;
; Internal jumps use TASM's `$+N` / `$-N` self-relative form rather
; than named labels (see the matching note on vga_blit_sprite_master).
; ============================================================================
vga_blit_sprite_simple PROC FAR
                PUSH    BP                      ; 55
                MOV     BP, SP                  ; 8B EC
                SUB     SP, 0AH                 ; 83 EC 0A
                PUSH    DI                      ; 57
                PUSH    SI                      ; 56
                PUSH    ES                      ; 06
                PUSH    DS                      ; 1E
                MOV     SI, [BP+6]              ; 8B 76 06
                MOV     DI, BP                  ; 8B FD
                SUB     DI, 0AH                 ; 83 EF 0A
                MOV     AX, SS                  ; 8C D0
                MOV     ES, AX                  ; 8E C0
                MOV     CX, 5                   ; B9 05 00
                REP     MOVSW                   ; F3 A5
                MOV     AX, [BP-4]              ; 8B 46 FC
                MOV     cs:[2389H], AX          ; 2E A3 89 23
                SHR     AX, 1                   ; D1 E8
                SHR     AX, 1                   ; D1 E8
                MOV     [BP-4], AX              ; 89 46 FC
                MOV     DS, cs:[0F4H]           ; 2E 8E 1E F4 00
                MOV     AX, ds:[GfxContext.wGfxBlitDstPage]            ; A1 18 00
                MOV     ES, AX                  ; 8E C0
                XOR     SI, SI                  ; 33 F6
                MOV     DI, [BP+0AH]            ; 8B 7E 0A
                SHL     DI, 1                   ; D1 E7
                MOV     DI, [DI].GfxContext.pRow_offset_lut          ; 8B BD F2 06
                SHL     DI, 1                   ; D1 E7
                SHL     DI, 1                   ; D1 E7
                ADD     DI, [BP+8]              ; 03 7E 08
                MOV     DX, [BP-4]              ; 8B 56 FC
                SHL     DX, 1                   ; D1 E2
                SHL     DX, 1                   ; D1 E2
                MOV     AX, [BP-2]              ; 8B 46 FE
                MOV     cs:[2387H], AX          ; 2E A3 87 23
                MOV     AL, ds:[GfxContext.bClip_enabled]              ; A0 03 00
                XOR     BX, BX                  ; 33 DB
                OR      AL, AL                  ; 0A C0
                JNZ     SHORT $+5               ; 75 03
                JMP     $+96H                   ; E9 93 00   -- skip clip
                ; clip_right @ 0x23EC
                MOV     AX, ds:[GfxContext.nClip_xmax]              ; A1 06 00
                SUB     AX, [BP+8]              ; 2B 46 08
                MOV     CX, DX                  ; 8B CA
                SUB     AX, CX                  ; 2B C1
                JNS     SHORT $+15H             ; 79 13
                NEG     AX                      ; F7 D8
                DEC     AX                      ; 48
                MOV     BX, AX                  ; 8B D8
                SUB     DX, AX                  ; 2B D0
                SHR     AX, 1                   ; D1 E8
                SHR     AX, 1                   ; D1 E8
                SUB     AX, [BP-4]              ; 2B 46 FC
                JC      SHORT $+5               ; 72 03
                JMP     $+319H                  ; E9 16 03   -- to epilogue @ 0x2721
                ; clip_bot @ 0x240B
                MOV     AX, ds:[GfxContext.nClip_ymax]            ; A1 0A 00
                SUB     AX, [BP+0AH]            ; 2B 46 0A
                MOV     CX, cs:[2387H]          ; 2E 8B 0E 87 23
                SUB     AX, CX                  ; 2B C1
                JNS     SHORT $+0FH             ; 79 0D
                NEG     AX                      ; F7 D8
                DEC     AX                      ; 48
                SUB     WORD PTR cs:[2387H], AX ; 2E 29 06 87 23
                JA      SHORT $+5               ; 77 03
                JMP     $+2FDH                  ; E9 FA 02
                ; clip_top @ 0x2427
                MOV     AX, ds:[GfxContext.nClip_ymin]              ; A1 08 00
                SUB     AX, [BP+0AH]            ; 2B 46 0A
                JLE     SHORT $+36H             ; 7E 34
                SUB     WORD PTR cs:[2387H], AX ; 2E 29 06 87 23
                DEC     AX                      ; 48
                PUSH    DX                      ; 52
                XOR     DX, DX                  ; 33 D2
                MUL     WORD PTR [BP-4]         ; F7 66 FC
                SHL     AX, 1                   ; D1 E0
                SHL     AX, 1                   ; D1 E0
                POP     DX                      ; 5A
                ADD     SI, AX                  ; 03 F0
                MOV     DI, ds:[GfxContext.nClip_ymin]              ; 8B 3E 08 00
                SHL     DI, 1                   ; D1 E7
                MOV     DI, [DI].GfxContext.pRow_offset_lut          ; 8B BD F2 06
                SHL     DI, 1                   ; D1 E7
                SHL     DI, 1                   ; D1 E7
                ADD     DI, [BP+8]              ; 03 7E 08
                MOV     AX, cs:[2387H]          ; 2E A1 87 23
                OR      AX, AX                  ; 0B C0
                JNZ     SHORT $+5               ; 75 03
                JMP     $+2C6H                  ; E9 C3 02
                JNS     SHORT $+5               ; 79 03
                JMP     $+2C1H                  ; E9 BE 02
                ; clip_left @ 0x2463
                MOV     AX, ds:[GfxContext.nClip_xmin]              ; A1 04 00
                SUB     AX, [BP+8]              ; 2B 46 08
                JLE     SHORT $+16H             ; 7E 14
                ADD     DI, AX                  ; 03 F8
                ADD     BX, AX                  ; 03 D8
                SUB     DX, AX                  ; 2B D0
                ADD     SI, AX                  ; 03 F0
                SHR     AX, 1                   ; D1 E8
                SHR     AX, 1                   ; D1 E8
                SUB     AX, [BP-4]              ; 2B 46 FC
                JC      SHORT $+5               ; 72 03
                JMP     $+2A5H                  ; E9 A2 02
                ; postclip @ 0x247F
                MOV     AX, DI                  ; 8B C7
                AND     AX, 3                   ; 25 03 00
                MOV     cs:[2385H], AX          ; 2E A3 85 23
                MOV     AX, SI                  ; 8B C6
                AND     AX, 3                   ; 25 03 00
                MOV     cs:[2383H], AX          ; 2E A3 83 23
                SHR     DI, 1                   ; D1 EF
                SHR     DI, 1                   ; D1 EF
                MOV     AX, [BP-0AH]            ; 8B 46 F6
                ADD     SI, [BP-8]              ; 03 76 F8
                AND     SI, 0FFFCH              ; 83 E6 FC
                MOV     cs:[2381H], SI          ; 2E 89 36 81 23
                MOV     DS, AX                  ; 8E D8
                MOV     cs:[237FH], BX          ; 2E 89 1E 7F 23
                MOV     cs:[238BH], DI          ; 2E 89 3E 8B 23
                ; plane-write setup (initial Map Mask): 0x24AF
                PUSH    DX                      ; 52
                MOV     DX, 03C4H               ; BA C4 03
                MOV     AL, 2                   ; B0 02
                OUT     DX, AL                  ; EE
                POP     DX                      ; 5A
                PUSH    DX                      ; 52
                MOV     CL, cs:[2385H]          ; 2E 8A 0E 85 23
                MOV     DI, cs:[238BH]          ; 2E 8B 3E 8B 23
                MOV     AL, 1                   ; B0 01
                SHL     AL, CL                  ; D2 E0
                INC     WORD PTR cs:[2385H]     ; 2E FF 06 85 23
                CMP     AL, 10H                 ; 3C 10
                JNZ     SHORT $+0EH             ; 75 0C
                INC     DI                      ; 47
                MOV     cs:[238BH], DI          ; 2E 89 3E 8B 23
                MOV     AL, 1                   ; B0 01
                MOV     cs:[2385H], AL          ; 2E A2 85 23
                MOV     DX, 03C5H               ; BA C5 03
                OUT     DX, AL                  ; EE
                POP     DX                      ; 5A
                ; dispatcher (no V-flip branching since simple): 0x24E0
                MOV     AX, cs:[2383H]          ; 2E A1 83 23
                XOR     AX, 3                   ; 35 03 00
                SHL     AX, 1                   ; D1 E0
                ADD     AX, 24F4H               ; 05 F4 24
                MOV     SI, 1                   ; BE 01 00
                PUSH    BX                      ; 53
                XOR     BX, BX                  ; 33 DB
                JMP     AX                      ; FF E0
                ; slide at 0x24F4
                ADD     BX, SI                  ; 03 DE
                ADD     BX, SI                  ; 03 DE
                ADD     BX, SI                  ; 03 DE
                MOV     AX, BX                  ; 8B C3
                POP     BX                      ; 5B
                ADD     AX, cs:[2381H]          ; 2E 03 06 81 23
                MOV     SI, AX                  ; 8B F0
                MOV     AX, cs:[2383H]          ; 2E A1 83 23
                INC     AX                      ; 40
                AND     AX, 3                   ; 25 03 00
                MOV     cs:[2383H], AX          ; 2E A3 83 23
                ; --- Lane 0 (0x2510)
                MOV     BP, 50H                 ; BD 50 00
                PUSH    DX                      ; 52
                PUSH    WORD PTR cs:[2387H]     ; 2E FF 36 87 23
                ADD     DX, 3                   ; 83 C2 03
                MOV     BX, cs:[237FH]          ; 2E 8B 1E 7F 23
                ADD     BX, 0                   ; 83 C3 00
                AND     BX, 0FFFCH              ; 83 E3 FC
                SHR     DX, 1                   ; D1 EA
                SHR     DX, 1                   ; D1 EA
                JZ      SHORT $+19H             ; 74 17
                MOV     AX, DX                  ; 8B C2
                SUB     BP, AX                  ; 2B E8
                MOV     CX, DX                  ; 8B CA
                MOVSB                           ; A4
                ADD     SI, 3                   ; 83 C6 03
                LOOP    SHORT $-4               ; E2 FA
                ADD     SI, BX                  ; 03 F3
                ADD     DI, BP                  ; 03 FD
                DEC     WORD PTR cs:[2387H]     ; 2E FF 0E 87 23
                JNZ     SHORT $-11H             ; 75 ED
                POP     WORD PTR cs:[2387H]     ; 2E 8F 06 87 23
                POP     DX                      ; 5A
                MOV     AX, cs:[2383H]          ; 2E A1 83 23
                OR      AX, AX                  ; 0B C0
                JNZ     SHORT $+8               ; 75 06
                ADD     WORD PTR cs:[2381H], 4  ; 2E 83 06 81 23 04
                XOR     AX, 3                   ; 35 03 00
                SHL     AX, 1                   ; D1 E0
                ADD     AX, 2568H               ; 05 68 25
                MOV     SI, 1                   ; BE 01 00
                PUSH    BX                      ; 53
                XOR     BX, BX                  ; 33 DB
                JMP     AX                      ; FF E0
                ; slide at 0x2568
                ADD     BX, SI                  ; 03 DE
                ADD     BX, SI                  ; 03 DE
                ADD     BX, SI                  ; 03 DE
                MOV     AX, BX                  ; 8B C3
                POP     BX                      ; 5B
                ADD     AX, cs:[2381H]          ; 2E 03 06 81 23
                MOV     SI, AX                  ; 8B F0
                MOV     AX, cs:[2383H]          ; 2E A1 83 23
                INC     AX                      ; 40
                AND     AX, 3                   ; 25 03 00
                MOV     cs:[2383H], AX          ; 2E A3 83 23
                PUSH    DX                      ; 52
                MOV     CL, cs:[2385H]          ; 2E 8A 0E 85 23
                MOV     DI, cs:[238BH]          ; 2E 8B 3E 8B 23
                MOV     AL, 1                   ; B0 01
                SHL     AL, CL                  ; D2 E0
                INC     WORD PTR cs:[2385H]     ; 2E FF 06 85 23
                CMP     AL, 10H                 ; 3C 10
                JNZ     SHORT $+0EH             ; 75 0C
                INC     DI                      ; 47
                MOV     cs:[238BH], DI          ; 2E 89 3E 8B 23
                MOV     AL, 1                   ; B0 01
                MOV     cs:[2385H], AL          ; 2E A2 85 23
                MOV     DX, 03C5H               ; BA C5 03
                OUT     DX, AL                  ; EE
                POP     DX                      ; 5A
                ; --- Lane 1 (0x25AD)
                MOV     BP, 50H                 ; BD 50 00
                PUSH    DX                      ; 52
                PUSH    WORD PTR cs:[2387H]     ; 2E FF 36 87 23
                ADD     DX, 2                   ; 83 C2 02
                MOV     BX, cs:[237FH]          ; 2E 8B 1E 7F 23
                ADD     BX, 1                   ; 83 C3 01
                AND     BX, 0FFFCH              ; 83 E3 FC
                SHR     DX, 1                   ; D1 EA
                SHR     DX, 1                   ; D1 EA
                JZ      SHORT $+19H             ; 74 17
                MOV     AX, DX                  ; 8B C2
                SUB     BP, AX                  ; 2B E8
                MOV     CX, DX                  ; 8B CA
                MOVSB                           ; A4
                ADD     SI, 3                   ; 83 C6 03
                LOOP    SHORT $-4               ; E2 FA
                ADD     SI, BX                  ; 03 F3
                ADD     DI, BP                  ; 03 FD
                DEC     WORD PTR cs:[2387H]     ; 2E FF 0E 87 23
                JNZ     SHORT $-11H             ; 75 ED
                POP     WORD PTR cs:[2387H]     ; 2E 8F 06 87 23
                POP     DX                      ; 5A
                MOV     AX, cs:[2383H]          ; 2E A1 83 23
                OR      AX, AX                  ; 0B C0
                JNZ     SHORT $+8               ; 75 06
                ADD     WORD PTR cs:[2381H], 4  ; 2E 83 06 81 23 04
                XOR     AX, 3                   ; 35 03 00
                SHL     AX, 1                   ; D1 E0
                ADD     AX, 2605H               ; 05 05 26
                MOV     SI, 1                   ; BE 01 00
                PUSH    BX                      ; 53
                XOR     BX, BX                  ; 33 DB
                JMP     AX                      ; FF E0
                ; slide at 0x2605
                ADD     BX, SI                  ; 03 DE
                ADD     BX, SI                  ; 03 DE
                ADD     BX, SI                  ; 03 DE
                MOV     AX, BX                  ; 8B C3
                POP     BX                      ; 5B
                ADD     AX, cs:[2381H]          ; 2E 03 06 81 23
                MOV     SI, AX                  ; 8B F0
                MOV     AX, cs:[2383H]          ; 2E A1 83 23
                INC     AX                      ; 40
                AND     AX, 3                   ; 25 03 00
                MOV     cs:[2383H], AX          ; 2E A3 83 23
                PUSH    DX                      ; 52
                MOV     CL, cs:[2385H]          ; 2E 8A 0E 85 23
                MOV     DI, cs:[238BH]          ; 2E 8B 3E 8B 23
                MOV     AL, 1                   ; B0 01
                SHL     AL, CL                  ; D2 E0
                INC     WORD PTR cs:[2385H]     ; 2E FF 06 85 23
                CMP     AL, 10H                 ; 3C 10
                JNZ     SHORT $+0EH             ; 75 0C
                INC     DI                      ; 47
                MOV     cs:[238BH], DI          ; 2E 89 3E 8B 23
                MOV     AL, 1                   ; B0 01
                MOV     cs:[2385H], AL          ; 2E A2 85 23
                MOV     DX, 03C5H               ; BA C5 03
                OUT     DX, AL                  ; EE
                POP     DX                      ; 5A
                ; --- Lane 2 (0x264A)
                MOV     BP, 50H                 ; BD 50 00
                PUSH    DX                      ; 52
                PUSH    WORD PTR cs:[2387H]     ; 2E FF 36 87 23
                ADD     DX, 1                   ; 83 C2 01
                MOV     BX, cs:[237FH]          ; 2E 8B 1E 7F 23
                ADD     BX, 2                   ; 83 C3 02
                AND     BX, 0FFFCH              ; 83 E3 FC
                SHR     DX, 1                   ; D1 EA
                SHR     DX, 1                   ; D1 EA
                JZ      SHORT $+19H             ; 74 17
                MOV     AX, DX                  ; 8B C2
                SUB     BP, AX                  ; 2B E8
                MOV     CX, DX                  ; 8B CA
                MOVSB                           ; A4
                ADD     SI, 3                   ; 83 C6 03
                LOOP    SHORT $-4               ; E2 FA
                ADD     SI, BX                  ; 03 F3
                ADD     DI, BP                  ; 03 FD
                DEC     WORD PTR cs:[2387H]     ; 2E FF 0E 87 23
                JNZ     SHORT $-11H             ; 75 ED
                POP     WORD PTR cs:[2387H]     ; 2E 8F 06 87 23
                POP     DX                      ; 5A
                MOV     AX, cs:[2383H]          ; 2E A1 83 23
                OR      AX, AX                  ; 0B C0
                JNZ     SHORT $+8               ; 75 06
                ADD     WORD PTR cs:[2381H], 4  ; 2E 83 06 81 23 04
                XOR     AX, 3                   ; 35 03 00
                SHL     AX, 1                   ; D1 E0
                ADD     AX, 26A2H               ; 05 A2 26
                MOV     SI, 1                   ; BE 01 00
                PUSH    BX                      ; 53
                XOR     BX, BX                  ; 33 DB
                JMP     AX                      ; FF E0
                ; slide at 0x26A2
                ADD     BX, SI                  ; 03 DE
                ADD     BX, SI                  ; 03 DE
                ADD     BX, SI                  ; 03 DE
                MOV     AX, BX                  ; 8B C3
                POP     BX                      ; 5B
                ADD     AX, cs:[2381H]          ; 2E 03 06 81 23
                MOV     SI, AX                  ; 8B F0
                MOV     AX, cs:[2383H]          ; 2E A1 83 23
                INC     AX                      ; 40
                AND     AX, 3                   ; 25 03 00
                MOV     cs:[2383H], AX          ; 2E A3 83 23
                PUSH    DX                      ; 52
                MOV     CL, cs:[2385H]          ; 2E 8A 0E 85 23
                MOV     DI, cs:[238BH]          ; 2E 8B 3E 8B 23
                MOV     AL, 1                   ; B0 01
                SHL     AL, CL                  ; D2 E0
                INC     WORD PTR cs:[2385H]     ; 2E FF 06 85 23
                CMP     AL, 10H                 ; 3C 10
                JNZ     SHORT $+0EH             ; 75 0C
                INC     DI                      ; 47
                MOV     cs:[238BH], DI          ; 2E 89 3E 8B 23
                MOV     AL, 1                   ; B0 01
                MOV     cs:[2385H], AL          ; 2E A2 85 23
                MOV     DX, 03C5H               ; BA C5 03
                OUT     DX, AL                  ; EE
                POP     DX                      ; 5A
                ; --- Lane 3 (0x26E7)
                MOV     BP, 50H                 ; BD 50 00
                PUSH    DX                      ; 52
                PUSH    WORD PTR cs:[2387H]     ; 2E FF 36 87 23
                ADD     DX, 0                   ; 83 C2 00
                MOV     BX, cs:[237FH]          ; 2E 8B 1E 7F 23
                ADD     BX, 3                   ; 83 C3 03
                AND     BX, 0FFFCH              ; 83 E3 FC
                SHR     DX, 1                   ; D1 EA
                SHR     DX, 1                   ; D1 EA
                JZ      SHORT $+19H             ; 74 17
                MOV     AX, DX                  ; 8B C2
                SUB     BP, AX                  ; 2B E8
                MOV     CX, DX                  ; 8B CA
                MOVSB                           ; A4
                ADD     SI, 3                   ; 83 C6 03
                LOOP    SHORT $-4               ; E2 FA
                ADD     SI, BX                  ; 03 F3
                ADD     DI, BP                  ; 03 FD
                DEC     WORD PTR cs:[2387H]     ; 2E FF 0E 87 23
                JNZ     SHORT $-11H             ; 75 ED
                POP     WORD PTR cs:[2387H]     ; 2E 8F 06 87 23
                POP     DX                      ; 5A
                ; epilogue @ 0x2721
                POP     DS                      ; 1F
                POP     ES                      ; 07
                POP     SI                      ; 5E
                POP     DI                      ; 5F
                ADD     SP, 0AH                 ; 83 C4 0A
                POP     BP                      ; 5D
                RETF                            ; CB
vga_blit_sprite_simple ENDP

; ============================================================================
; Mode-Y plane-mask LUT + span-fill scratch words (slot 39's data block).
; chunk:0x272A..0x2733
; ============================================================================
g_abVgaModeYPlaneMaskLut        DB      01H, 02H, 04H, 08H   ; 0x272A
g_wVgaSpanModeYFbSeg            DW      0       ; 0x272E
g_wVgaSpanModeYRowCounter       DW      0       ; 0x2730
g_wVgaSpanModeYScratch          DW      0       ; 0x2732

; ============================================================================
; vga_fill_world_textured_span_modey -- textured span fill (slot 39).
; chunk:0x2734..0x27B9
;
; The world-map renderer hot-swaps slot 27 with this at run-time.
; Walks an ES:SI command stream: each entry { x_start: word, x_end: word }.
; Per pixel: XLAT lookups against the in-chunk plane LUT (CS:0x272A) and
; an SS-relative texture LUT (BP = ds:[0x6BC] pre-fetched outside). The
; second XLAT (SS:BX) reads a texture-row byte by table-indexing.
;
; Internal jumps use TASM's `$+N` / `$-N` self-relative form rather
; than named labels (see the matching note on vga_blit_sprite_master).
; ============================================================================
vga_fill_world_textured_span_modey PROC FAR
                PUSH    BP                      ; 55
                PUSH    DI                      ; 57
                PUSH    DS                      ; 1E
                MOV     DS, cs:[0F4H]           ; 2E 8E 1E F4 00
                MOV     AX, ds:[GfxContext.wGfxBlitDstPage]            ; A1 18 00
                MOV     cs:[272EH], AX          ; 2E A3 2E 27
                MOV     BX, es:[SI]             ; 26 8B 1C
                SHL     BX, 1                   ; D1 E3
                MOV     DI, [BX].GfxContext.pRow_offset_lut          ; 8B BF F2 06
                MOV     BP, ds:[GfxContext.wTextureIdx]          ; 8B 2E BC 06
                PUSH    ES                      ; 06
                POP     DS                      ; 1F
                MOV     DX, 03C4H               ; BA C4 03
                MOV     AL, 2                   ; B0 02
                OUT     DX, AL                  ; EE
                MOV     DX, 03CEH               ; BA CE 03
                MOV     AL, 4                   ; B0 04
                OUT     DX, AL                  ; EE
                MOV     AX, [SI+2]              ; 8B 44 02
                MOV     cs:[2730H], AX          ; 2E A3 30 27
                ADD     SI, 4                   ; 83 C6 04
vga_fwts_row:
                MOV     AX, [SI]                ; 8B 04       x_start
                MOV     BX, [SI+2]              ; 8B 5C 02    x_end
                PUSH    DI                      ; 57
                MOV     ES, cs:[272EH]          ; 2E 8E 06 2E 27
                MOV     CX, BX                  ; 8B CB
                SUB     CX, AX                  ; 2B C8
                JLE     SHORT $+31H             ; 7E 2F
                MOV     BX, AX                  ; 8B D8
                SHR     BX, 1                   ; D1 EB
                SHR     BX, 1                   ; D1 EB
                ADD     DI, BX                  ; 03 FB
                AND     AL, 3                   ; 24 03
                MOV     AH, AL                  ; 8A E0
vga_fwts_pixel:
                MOV     DX, 03CFH               ; BA CF 03
                OUT     DX, AL                  ; EE
                MOV     BX, 272AH               ; BB 2A 27
                XLAT    BYTE PTR CS:[BX]        ; 2E D7 — XLAT CS:[BX+AL]
                MOV     DX, 03C5H               ; BA C5 03
                OUT     DX, AL                  ; EE
                MOV     AL, es:[DI]             ; 26 8A 05
                MOV     BX, BP                  ; 8B DD
                XLAT    BYTE PTR SS:[BX]        ; 36 D7 — XLAT SS:[BX+AL]
                MOV     es:[DI], AL             ; 26 88 05
                INC     AH                      ; FE C4
                AND     AH, 3                   ; 80 E4 03
                JNZ     SHORT $+3               ; 75 01
                INC     DI                      ; 47
                MOV     AL, AH                  ; 8A C4
                LOOP    SHORT $-21H             ; E2 DD
                POP     DI                      ; 5F
                ADD     DI, 50H                 ; 83 C7 50
                ADD     SI, 4                   ; 83 C6 04
                DEC     WORD PTR cs:[2730H]     ; 2E FF 0E 30 27
                JNZ     SHORT $-4CH             ; 75 B2
                POP     DS                      ; 1F
                POP     DI                      ; 5F
                POP     BP                      ; 5D
                RETF                            ; CB
vga_fill_world_textured_span_modey ENDP

; ============================================================================
; g_abVgaTrailingEpilogue -- 7-byte "ADD SP,2; POP DS; POP DI; POP BP; RETF"
; sequence at chunk:0x27BA..0x27C0. Marked as data during RE; the bytes
; encode an early-exit epilogue but no internal flow reaches it from inside
; this chunk. Likely a tool-driven trailing remnant; emit verbatim for byte
; identity. (Per project rules: db is OK for data declarations.)
; ============================================================================
g_abVgaTrailingEpilogue         DB      83H, 0C4H, 02H, 1FH, 5FH, 5DH, 0CBH ; 0x27BA

; ============================================================================
; Glossary -- terms used in the comments above.
;
;   Mode 13h          The standard BIOS 320x200x256 chunky mode (one byte
;                     per pixel, chain-4 addressing on). Set via
;                     INT 10h AX=0013h.
;   Mode-Y            A software-only re-program of Mode 13h that disables
;                     chain-4 to expose the VGA's native 4-plane layout
;                     while keeping the 320x200 resolution and palette.
;                     "Mode X" in Abrash is 320x240 with the same trick.
;   Chain-4           A VGA mode-set bit (Sequencer reg 4 bit 3) that
;                     makes the four VGA planes act as a single chunky
;                     byte stream. Mode 13h has chain-4 on; Mode-Y has
;                     it off.
;   Plane             One of four parallel 64 KiB byte lanes inside the
;                     VGA frame buffer at A000. With chain-4 off, the CPU
;                     selects which plane(s) receive a write via the
;                     Sequencer Map Mask register.
;   Map Mask          Sequencer register 2 (port 0x3C4 / 0x3C5). A 4-bit
;                     "plane enable" mask. 0x0F = write all 4 planes.
;   Latch             Each VGA plane has an internal 8-bit latch that
;                     captures the byte fetched on the most recent CPU
;                     read. In GC write mode 1, the next CPU write copies
;                     the latched bytes into the destination planes -- a
;                     "free" 4-plane MOVSB.
;   Write Mode 1      GC reg 5 bits 0..1 = 01. CPU writes route the
;                     contents of the four latches into the planes
;                     selected by Map Mask. Used for VRAM-to-VRAM
;                     rectangle copies (vga_present, vga_blit_sprite_flip_h).
;   CRTC              Cathode Ray Tube Controller. The VGA register file
;                     at port 0x3D4 / 0x3D5 that controls scan-out timing,
;                     start address, etc. We use reg 0x0C/0x0D
;                     (start address high/low) for page flipping.
;   DAC               Digital-to-Analog Converter. The VGA's 256 x 18-bit
;                     palette, accessed via ports 0x3C7 (read index),
;                     0x3C8 (write index), 0x3C9 (data). Each colour is
;                     three 6-bit RGB bytes.
;   F-number          Used in the OPL2 audio drivers; NOT used in this
;                     VGA driver. (Listed here only because the term may
;                     leak in from sibling glossaries.)
;   Vsync             Vertical retrace. Port 0x3DA bit 3 == 1 during the
;                     CRT's vertical-retrace interval. Polled by
;                     vga_vsync_wait to align page flips with the start
;                     of a fresh frame.
;   Sequencer         The VGA register block at port 0x3C4 / 0x3C5
;                     ("which planes are active for writes"). Map Mask
;                     lives here.
;   GC                Graphics Controller. The register block at port
;                     0x3CE / 0x3CF. Controls write mode, read mode,
;                     bit mask, set/reset, plane select on reads.
;   DUDE / FBOV       Vmcode.OVL is not in DUDE format (DUDE is the
;                     AUDIO driver family). FBOV is the executable
;                     overlay format. Vmcode.OVL is a 5th format -- a
;                     flat chunk archive selected at runtime per the
;                     player's video adapter. Each chunk is paragraph-
;                     aligned and exposes a fixed init entry at offset 0.
;   Vtable / slot     The 50-entry far-pointer table at chunk:0x00F8.
;                     Each "slot" maps to one renderer operation
;                     (draw_line, blit_sprite, etc.). The engine calls
;                     CALL FAR [vtable + slot*4] to dispatch.
;   Host callback     The 19-entry far-pointer table at chunk:0x01C0,
;                     overwritten at init time by REP MOVSW from the
;                     engine. Lets this chunk call back into the engine
;                     for memory / I/O / asset services.
;   Scratch DS        A private segment the engine allocates for this
;                     chunk at init, stored at cs:[0F4H] and loaded into
;                     DS at the top of most slot handlers. Holds the row
;                     LUT, palette cache, host-shared state.
;   Row LUT           A 200-entry word array at scratch:[0x6F2] caching
;                     y * 80 for y in 0..199. Mode-Y rows are 80 bytes
;                     each (320 pixels / 4 planes); caching the offset
;                     avoids a multiplication per scanline.
;   "Sliding entry"   The JMP AX + slide-of-ADDs trick used inside
;                     vga_blit_sprite_master to dispatch into one of
;                     four plane lanes without an `if` chain. See the
;                     master plate for the full explanation.
;
; Further reading:
;   - Michael Abrash, *Graphics Programming Black Book*, esp. ch.47-49.
;   - FreeVGA register reference at osdever.net/FreeVGA/home.htm.
;   - Ralf Brown's Interrupt List for INT 10h AX=0013h, INT 21h AH=49h.
; ============================================================================

                END     _start
