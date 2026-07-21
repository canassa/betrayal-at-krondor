; ============================================================================
; Vmcode.OVL.HEG -- Hi-res EGA / VGA video driver chunk (11035 bytes, 0x2B1B)
;
; Shipped with "Betrayal at Krondor" (Dynamix / Sierra, 1993). Image base
; 0000:0000; the MZ-stripped image is 11035 bytes = the HEG chunk
; uncompressed size.
;
; Packing: TASM + TLINK produce an MZ .EXE; the packer strips the MZ header
; and LZW-packs the flat image into VMCODE.OVL.
;
; The chunk is one of eight interchangeable graphics drivers in Vmcode.ovl.
; KRONDOR.EXE loads it via the RES-archive loader, runs its init prologue
; once, then snapshots its 50-slot vtable template (at chunk:0x013E) into
; the host's g_renderer_vtable @ 39ae:2ac6 for ordinary far-call dispatch.
;
; Content: 31 distinct functions (43 vtable slots) and the chunk-local data
; regions across 0x0000..0x2B1A. The file is laid out function-by-function in
; literal byte order. Do not reorder.
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
; This file is the HEG (Hi-res EGA / VGA) driver. The engine
; communicates with it through a vtable of far function pointers
; (see "How the engine dispatches" below): 50 slots, each slot a
; different request like "draw a line", "blit a sprite", "set the
; palette". When a slot is invoked, this code translates that high-
; level request into the specific byte patterns the chosen VGA/EGA
; mode expects in its framebuffer and hardware registers.
;
; HEG dispatches one of FOUR initialisation paths depending on the
; runtime DS:[0x6EC] mode-id field (which is the requested visible
; height in scanlines):
;
;   0x1E0 (=480 dec): MODE 12h -- 640x480x16 VGA.
;          Plain BIOS mode-set + AR palette reset. Back-buffer at
;          segment 0xA000. This is the preferred VGA path.
;   0x190 (=400 dec): MODE 12h with CRTC viewport tweak.
;          640x480 hardware mode, but the CRTC is reprogrammed so
;          only 400 rows are visible. Tweaks vertical-display-end
;          (CR12), start-vertical-blanking-end (CR16), and the
;          start-address pair (CR0C/CR0D) so the visible window is
;          shrunk to 400 rows. Back-buffer at 0xA800. Requires VGA.
;   0x15E (=350 dec): MODE 10h -- 640x350x16 Enhanced EGA.
;          The classic EGA hi-res mode; works on both EGA and VGA
;          cards. AR palette reset; no CRTC tweaks.
;   default:          MODE 0Eh -- 640x200x16 vanilla EGA.
;          Reached on any non-matching mode-id. Almost certainly a
;          never-taken fallback in the shipping game (the engine
;          appears to always request one of the three named modes).
;
; In other words, HEG's "fallback chain" idea (VGA mode 12h ->
; EGA mode 10h -> EGA mode 0Eh) is hard-coded in the engine's
; mode-id assignment, NOT auto-detected here at runtime: the engine
; decides which mode to use (presumably from the user's video-setup
; choice and any earlier adapter probe), and this driver just does
; what it's told. The reason the *engine* picks 12h-then-10h-then-0Eh
; is to use the best 640-wide 16-colour mode the user's adapter
; supports.
;
; All four paths share the same low-level programming model: 4-plane
; planar 4bpp framebuffer at segment 0xA000 (or 0xA800 for the
; 400-row viewport), 80 bytes per scanline, accessed via the EGA/VGA
; sequencer "map-mask" plus GC bit-mask + write-mode-2 latched-write
; idiom. The differences between modes 12h / 10h / 0Eh are confined
; to:
;   (a) the BIOS mode-set sequence (CRTC timing values differ for
;       480/350/200-line vertical resolution);
;   (b) the available off-screen memory (= number of back-buffer
;       pages, which is why the 0x190 / 0x1E0 paths set up different
;       segment shadows at DS:[0x10/0x12/0x14]);
;   (c) the palette path: on EGA the attribute-controller writes
;       drive the 6 monitor pins directly (RrGgBb), on VGA the AR
;       just produces a 6-bit index into the 256-entry DAC LUT that
;       a separate code path (heg_load_palette) programs.
; The actual pixel-pumping cores are identical across all four
; paths.
; ----------------------------------------------------------------------------

; ----------------------------------------------------------------------------
; About the HEG / EGA hi-res / VGA 16-colour hardware
;
; The graphics adapters HEG targets all share the same programming
; model: a planar 4-bit-per-pixel framebuffer. Each pixel's 4 bits
; are stored ACROSS 4 separate 64KB banks (planes 0..3) at the same
; byte offset; the byte at framebuffer offset N selects 8 horizontal
; pixels and the SEQUENCER's "map mask" register (port 0x3C4 index
; 0x02) selects which plane(s) the CPU's write hits.
;
; Pixel packing: each byte is 8 horizontal pixels, MSB-first.
;
;       bit 7 6 5 4 3 2 1 0
;       pixel 0 1 2 3 4 5 6 7  (in this byte; same byte offset in
;                               each of 4 planes contributes the
;                               4 bit-planes for these 8 pixels)
;
; Hardware ports used (port numbers per IBM VGA TR / IBM EGA TR /
; FreeVGA register reference):
;
;   0x3C0 -- attribute controller (AC) index/data. SAME physical
;          port for both: the AC contains a single internal flip-
;          flop that toggles between "expecting index" and
;          "expecting data" on every write. The flip-flop is reset
;          to "expecting index" by ANY READ from port 0x3DA. The
;          AC holds a 16-entry palette that maps 4-bit framebuffer
;          values to 6-bit colour codes.
;
;          On EGA: those 6 bits drive the 6 RGB monitor pins
;          (RrGgBb -- secondary R, primary R, secondary G, primary G,
;          secondary B, primary B). The palette stops there; the
;          monitor's CRT receives the 6 bits directly.
;
;          On VGA: those 6 bits are the low 6 bits of an 8-bit
;          index into the 256-entry DAC LUT (the top 2 bits come
;          from AR14 and the AR10/bit-7 control). The DAC then
;          produces analogue R/G/B for the monitor. So on VGA there
;          is an EXTRA stage (DAC LUT) between the AR output and
;          the monitor; programming a colour on VGA usually means
;          programming the DAC entry (via 0x3C7/0x3C8/0x3C9) AND
;          ensuring the AR maps to the right DAC slot.
;   0x3C4/0x3C5 (sequencer index/data): map mask (idx 0x02 = which
;          planes the CPU's writes hit), character map, memory mode.
;   0x3CE/0x3CF (graphics controller index/data): set/reset (0x00),
;          enable set/reset (0x01), colour compare (0x02), data
;          rotate / function-select (0x03), read map select (0x04),
;          graphics mode (0x05) -- bits 0..1 = write mode 0..3,
;          bit 3 = read mode (0=plane-select, 1=colour-compare);
;          miscellaneous (0x06), colour don't-care (0x07),
;          bit mask (0x08).
;   0x3C7/0x3C8/0x3C9 (DAC palette index/data): VGA ONLY. Writes
;          18-bit (6 + 6 + 6 RGB) entries into the 256-entry DAC
;          LUT. Plain EGA has no DAC -- the AR's 6-bit output goes
;          straight to the monitor. The HEG palette-set functions
;          (heg_load_palette etc.) are no-ops in spirit on EGA: they
;          still write 0x3C9, but on real EGA those writes land
;          nowhere meaningful (the AR path is the one that takes
;          effect). The game's palette path is therefore "best on
;          VGA, acceptable on EGA hi-res".
;   0x3D4/0x3D5 (CRTC index/data): vertical/horizontal timing.
;          HEG programs CR12, CR15, CR16, CR0C, CR0D in the 0x190
;          (400-row viewport) path to shrink the visible area to
;          400 rows. NB: writes to CR0..CR7 silently fail if
;          CR11 bit 7 (the write-protect bit) is still set from the
;          BIOS's mode-set. HEG avoids that pitfall because it only
;          touches CR0C/CR0D/CR12/CR15/CR16 -- all unprotected.
;          (See FreeVGA CRTC reference.)
;   0x3DA (read-only): input status register 1. Bit 3 = vertical
;          retrace active; bit 0 = display enable. Reading also
;          resets the AR flip-flop -- the standard "before every
;          attribute-port access, read 0x3DA first" idiom.
;
; Bank-interleaved scanlines: HEG does NOT use the CGA's bank-
; interleaved layout. Each scanline is a flat 80-byte run in each
; plane, computed via the 480-entry scanline-offset LUT at
; chunk_data_seg:[0x6F2] which holds row*80 for rows 0..479.
;
; The LUT is sized for the largest supported mode (480 rows); the
; smaller modes (350-row, 400-row) just use a prefix of it.
;
; For the full register-level reference, see FreeVGA at
; www.osdever.net/FreeVGA/home.htm.
; ----------------------------------------------------------------------------

; ----------------------------------------------------------------------------
; How the engine dispatches into this chunk
;
; Vmcode.OVL is a flat archive of driver chunks; one chunk per
; supported adapter. The host engine:
;
;   1. Loads the selected chunk into a freshly-allocated segment.
;   2. Calls the chunk's `_start` (heg_init) as a far function,
;      passing two args on the stack: a paragraph count for the
;      driver's private working segment, and a far pointer to the
;      host's "service callback" table (file I/O, allocator,
;      drawing primitives the chunk delegates back).
;   3. heg_init copies the 19 host callbacks into chunk-local
;      mirror slots at CS:0x0206, configures the framebuffer for
;      the requested mode, builds the 480-row scanline LUT in the
;      scratch segment, then returns DX:SI = (CS, 0x013E) -- a far
;      pointer to the chunk's vtable template at g_apfnHegVtable.
;   4. The host stamps the chunk's load segment into every
;      segment-half of that template (50 slots * 4 bytes = 200
;      bytes) and copies the result into the global renderer
;      vtable at 39ae:2ac6 in host RAM.
;   5. Every subsequent rendering call from the game is a far
;      CALL through that vtable -- never a direct CALL into this
;      file. The HEG driver thus only sees a stream of slot
;      invocations after init.
;
; Slot calling convention: most slots are __cdecl16far (push args
; right-to-left, far call, caller cleans the stack). A handful of
; inner functions (the sprite-blit cores, pixel-run
; fill, span fill, glyph row blit, stretched row, chunky pack) take
; register-passed args because they're called from within this
; chunk for speed. Each function's plate comment lists the actual
; arg convention.
;
; The HEG vtable is NOT followed by 10 dead slots like the CGA /
; EGA / EVG / MCG / TAN vtables -- vtable
; (0x013E..0x0205) and callback-table copy region (0x0206..0x0251)
; are **adjacent with no overlap**. All 50 slots are live (modulo
; the 10 entries that point at heg_unimplemented_slot, the 1-byte
; RETF stub at 0x0252; those slots are reserved for future
; expansion in the renderer interface and never invoked by the
; host).
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
;   segment. Many of the chunk-local globals live at fixed offsets
;   *inside instructions* in heg_init -- after init runs once,
;   those bytes are repurposed as runtime-readable state. The EQUs
;   in the next block document the addresses; see also the
;   "Dual-use storage" notes in individual function plates.
;
; - Memory accesses use one of three segments:
;     CS:  -- the chunk itself (vtable, mask LUTs, dual-use globals,
;             callback-table mirror).
;     DS:  -- usually the chunk's "scratch DS", a private working
;             segment allocated `paragraph_count` paragraphs past the
;             caller's DS (set up at heg_init step 2). Holds the
;             scanline LUT, framebuffer-segment globals, and per-
;             slot scratch state. Every function that needs the
;             scratch reloads DS from cs:[g_wHegChunkDataSeg @
;             0x013A] on entry and restores caller DS before RETF.
;     ES:  -- usually the framebuffer (A000:0000 or A800:0000); the
;             function plates specify which.
;
; - Local labels inside a function are prefixed with a short
;   nickname for the enclosing function. Avoids collisions across
;   functions without bare anonymous labels.
; ----------------------------------------------------------------------------

                .8086
                .MODEL  TINY
                .CODE
                ORG     0
                ASSUME  ds:NOTHING, es:NOTHING

; Shared engine graphics-context STRUC (host struct overlaid by the driver
; through its scratch DS = caller_DS + paragraphs/16). A STRUC emits no bytes,
; so this INCLUDE does not perturb the assembled output. GFXCTX.INC lives in this
; directory; TASM finds it via /iSRC\DRIVERS\VMCODE (see DRIVERS.MAK).
                INCLUDE gfxctx.inc

; ----------------------------------------------------------------------------
; Dual-use storage equates -- bytes that live INSIDE the
; instructions of heg_init double as runtime-readable globals after
; init has executed once. Init sets them via `MOV CS:[imm16], reg`
; in its prologue; later slots read them via `CS:` overrides at
; the consumer sites.
;
; (HEG places its dual-use globals AFTER the vtable rather than
; inside the init prologue itself -- the prologue uses immediate
; constants instead. So unlike CGA, HEG only has two CS-relative
; storage cells: g_wHegChunkDataSeg @ 0x013A and the unnamed
; storage at 0x013C.)
; ----------------------------------------------------------------------------
g_wHegChunkDataSeg      equ 013AH        ; ushort -- scratch-DS segment (caller DS + paragraphs/16)
g_wHegInitParagraphs    equ 013CH        ; ushort -- saved init arg [BP+6] paragraph count

; ============================================================================
; heg_init -- chunk initialiser (PROC FAR, called via the host's video_init).
; chunk:0x0000..0x011C
;
; This is the MOST IMPORTANT entry point in the file for a reader new
; to DOS. The host (KRONDOR.EXE) calls this once at startup; everything
; else this chunk does is in response to vtable calls that come later.
; What happens here:
;
;   - The host hands us two things: a "paragraph count" (how much
;     extra memory it has reserved for our private scratch state,
;     measured in 16-byte paragraphs), and a far pointer to a table
;     of 19 service callbacks (file I/O, allocator, etc.) we can
;     invoke back into the host. We copy that callback table into
;     our own chunk-local slot at CS:0x0206 so we can call it
;     without re-checking the original pointer.
;
;   - We set up a "scratch DS" segment = caller_DS + paragraphs/16.
;     The host has guaranteed that all the bytes from caller_DS
;     through our scratch DS are reserved for us; we use them for
;     the scanline LUT, runtime palette mirrors, and per-slot
;     state.
;
;   - We ask the BIOS to set the desired video mode (see "mode-id
;     dispatch" below) via INT 10h AH=00h.  An "INT 10h" call is
;     the standard way DOS programs invoke the BIOS video API:
;     the CPU jumps through the interrupt vector at 0x40, where
;     the system BIOS lives; AH selects a subfunction (00h = set
;     mode), AL = mode number. After the call, the requested 640-
;     wide 16-colour video mode is active.
;     (See Ralf Brown's Interrupt List, INT 10 AH=00h.)
;
;   - For the VGA modes we additionally call INT 10h AX=1013h with
;     BX=0100h, which selects palette page 1 (a VGA feature that
;     remaps the AR's 6-bit output into different DAC slots; see
;     IBM VGA TR p.40). We then run our own AR-reset helper to
;     drop a known identity mapping back into the 16 AR palette
;     registers.
;
;   - We build the 480-entry scanline-offset LUT in scratch DS:
;     [row] -> row * 80. Slot handlers use this to turn an x/y
;     coordinate into a byte offset without doing a multiply per
;     pixel.
;
;   - Finally we program SC index 0x02 (map mask) := 0x0F (all
;     planes enabled for writes), GC index 0x05 := 0x02 (write
;     mode 2, read mode 0 -- the chunk's "default" GC mode that
;     every slot returns to on exit), and return DX:SI = our
;     CS:vtable_offset so the host can snapshot our vtable
;     template.
;
; CALLER ABI (host-side far call):
;   [BP+0x06]  ushort  backbuffer_paragraphs
;   [BP+0x08]  ushort  host_callbacks_off  (off of host service-callback table)
;   [BP+0x0a]  ushort  host_callbacks_seg  (seg of host service-callback table)
;
; INIT SEQUENCE:
;   1. [0x00..0x18]  Copy 0x26 words (76 bytes = 19 far ptrs) from
;      DS:SI = host_callbacks_seg:host_callbacks_off into the chunk-
;      local mirror at CS:0x0206 (g_apfnHegHostCallbacks). Other
;      chunk slots later CALLF [0x0206+N] through this copy.
;   2. [0x19..0x33]  Save paragraph count to g_wHegInitParagraphs;
;      shift right by 4 to convert paragraphs to segments, add the
;      caller's DS, store as g_wHegChunkDataSeg. The private scratch
;      DS is positioned paragraphs/16 paragraphs past caller DS.
;   3. [0x34..0x4C]  Initialise runtime DS state (now pointing at
;      scratch seg): [0x6E8]=1, [0x21]=0x10, [0x14]=0xA000,
;      [0x12]=0xA800, [0x10]=0xA800.
;   4. [0x4D..0x66]  Read mode-id from runtime DS:[0x6EC] (requested
;      visible scanline count) and dispatch to one of four paths
;      via CMP/JZ. The order of the CMP tests is: 0x15E, 0x1E0,
;      0x190, then fall through to the default:
;        0x15E -> MODE 10h (640x350 EGA hi-res, works on EGA + VGA)
;        0x1E0 -> MODE 12h (640x480 VGA hi-res, A000 framebuffer)
;        0x190 -> MODE 12h with CRTC viewport tweak
;                 (640x480 hardware, 640x400 visible, A800 fb)
;        default -> MODE 0Eh (640x200 EGA fallback)
;      The "engine picks the best mode the user has" decision was
;      made earlier by the host; this dispatch just programmes
;      whatever was decided.
;   5. [0x67..0xDE]  Per-path mode set and back-buffer config:
;        default: INT 10h AX=000Eh; [0x12]=0xA400; jump to step 6.
;        0x190:   INT 10h AX=0012h; INT 10h AX=1013h BX=0100h
;                 (palette block 1); call heg_reset_attribute_palette;
;                 [0x12]=[0x10]=0xA800; CRTC tweaks via 0x3D4/0x3D5:
;                   CR12  := read - 0x23      (vertical display end)
;                   CR15  :  read-only        (see "CR15 read" note
;                                              below)
;                   CR16  := read + 0x28      (end vertical blanking)
;                   CR0C  := 0xF1             (start address hi)
;                   CR0D  := 0xF0             (start address lo)
;                 The read-modify-write idiom on CR12/CR16 preserves
;                 the BIOS-programmed value's other bits and adjusts
;                 only the deltas the driver cares about; CR0C/CR0D
;                 are written outright (no read), setting the
;                 displayed framebuffer base to 0xF1F0 / 16 =
;                 paragraph 0x0F1F = byte offset 0xF1F0. This shifts
;                 the visible 400 rows down by ~3840 bytes (= 48
;                 rows * 80 bytes/row) within the 480-row buffer,
;                 producing a 400-row letterboxed display.
;                 CR0..CR7 are NOT touched, so CR11 bit 7 (write-
;                 protect) doesn't need to be cleared.
;                 then jump to step 6.
;        0x15E:   INT 10h AX=0010h; INT 10h AX=1013h BX=0100h
;                 (palette block 1); call heg_reset_attribute_palette;
;                 jump to step 6.
;        0x1E0:   INT 10h AX=0012h; INT 10h AX=1013h BX=0100h;
;                 call heg_reset_attribute_palette;
;                 [0x12]=[0x10]=0xA000; fall through to step 6.
;
; CR15 read at mode-set time (the 0x190 path's `IN AL, DX` from
;   port 0x3D5 with CR15 selected, followed by NOP / DEC DX and no
;   write-back): per FreeVGA and the IBM VGA TR there is no
;   documented hardware side-effect from reading CR15. The most
;   plausible explanation in this context is mode-set verification:
;   CR15 (Start Vertical Blanking, low 8 bits) holds a value that
;   uniquely distinguishes the three modes this driver might be in
;   (~0x80 for 200-line, ~0xE0 for 350-line, ~0xDD for 480-line),
;   which is more reliable than the BDA byte at 0040:0049h (that
;   only reports the *requested* mode, not the actual hardware
;   state). The read result is dropped on the floor here, so any
;   verification logic was either stubbed out at the C level or
;   moved to a separate function the compiler inlined away. The "read as timing pause" theory
;   is unsupported -- no canonical reference recommends CR15 reads
;   for that purpose.
;   6. [0xDF..0xF1]  Build the 480-row scanline-offset LUT at
;      scratch_DS:[0x6F2..0x6F2+0x3C0]: each entry is 2 bytes,
;      holding 80*row for rows 0..479. 480 = the largest supported
;      vertical resolution (mode 12h); shorter modes use a prefix.
;   7. [0xF2..0xFF]  Program the EGA/VGA sequencer and graphics
;      controller for full-plane / read-mode-0 access:
;        port 0x3C4 (seq) idx 0x02 := 0x0F (enable all 4 planes)
;        port 0x3CE (gfx) idx 0x05 := 0x02 (read mode 0, write mode 2)
;   8. [0x100..0x118] Set up return values and clean up the stack
;      frame:
;        DX  := CS  (chunk segment for host's vtable snapshot)
;        SI  := 0x013E (offset of g_apfnHegVtable)
;        Stash AX=0x0280 at scratch:[0x6EA] -> 640 = display width;
;          dec AX -> 0x027F at scratch:[0x06] (clip-right?)
;        Stash AX=DS:[0x6EC] -1 at scratch:[0x0A] (clip-bottom?)
;        AX := 0x0002 (success/version stamp)
;        POP DI, POP SI, POP DS, POP BP, RETF.
;
; RETURN:
;   AX     -- 0x0002 (success).
;   DX:SI  -- CS:0x013E, far pointer to g_apfnHegVtable.
; ============================================================================
_start          LABEL   BYTE
heg_init        PROC    FAR
                ; ------ Step 1: copy 76-byte host-callback table to chunk-local mirror.
                PUSH    BP                              ; 55
                MOV     BP, SP                          ; 8B EC
                PUSH    DS                              ; 1E
                PUSH    SI                              ; 56
                PUSH    DI                              ; 57
                MOV     DI, OFFSET g_apfnHegHostCallbacks   ; BF 06 02  ; chunk:0x0206
                PUSH    CS                              ; 0E
                POP     ES                              ; 07
                MOV     SI, [BP+8]                      ; 8B 76 08  ; host_callbacks_off
                MOV     DS, [BP+0Ah]                    ; 8E 5E 0A  ; host_callbacks_seg
                MOV     CX, 26H                         ; B9 26 00  ; 38 words = 76 bytes
                REP     MOVSW                           ; F3 A5     ; copy callback table
                POP     DI                              ; 5F
                POP     SI                              ; 5E
                POP     DS                              ; 1F
                ; ------ Step 2: paragraph-count -> chunk_data_seg.
                MOV     AX, [BP+6]                      ; 8B 46 06  ; backbuffer_paragraphs
                MOV     cs:[g_wHegInitParagraphs], AX   ; 2E A3 3C 01
                SHR     AX, 1                           ; D1 E8
                SHR     AX, 1                           ; D1 E8
                SHR     AX, 1                           ; D1 E8
                SHR     AX, 1                           ; D1 E8     ; paragraphs/16 -> segments
                PUSH    DS                              ; 1E
                PUSH    DI                              ; 57
                MOV     BX, DS                          ; 8C DB     ; caller DS
                ADD     AX, BX                          ; 03 C3     ; scratch_DS = caller_DS + paragraphs/16
                MOV     cs:[g_wHegChunkDataSeg], AX     ; 2E A3 3A 01
                MOV     DS, AX                          ; 8E D8     ; switch to scratch DS
                ; ------ Step 3: prime runtime DS state.
                MOV     BYTE PTR ds:[GfxContext.bYResDoubled], 1   ; C6 06 E8 06 01
                MOV     BYTE PTR ds:[GfxContext.bActiveVgaMode], 10H ; C6 06 21 00 10  ; font/glyph step
                MOV     AX, 0A000H                      ; B8 00 A0
                MOV     ds:[GfxContext.wVgaFrontPageBase], AX  ; A3 14 00          ; framebuffer A
                MOV     AX, 0A800H                      ; B8 00 A8
                MOV     ds:[GfxContext.wVgaPage2Base], AX      ; A3 12 00          ; framebuffer B
                MOV     ds:[GfxContext.wVgaPage1Base], AX      ; A3 10 00          ; active framebuffer
                ; ------ Step 4: read mode-id, dispatch.
                MOV     AX, ds:[GfxContext.wScreen_height]     ; A1 EC 06          ; runtime mode-id
                CMP     AX, 015EH                       ; 3D 5E 01          ; EGA hi-res 350?
                JZ      heg_init_path_15e               ; 74 5F
                CMP     AX, 01E0H                       ; 3D E0 01          ; VGA hi-res 480?
                JZ      heg_init_path_1e0               ; 74 6C
                CMP     AX, 0190H                       ; 3D 90 01          ; 640x400 viewport?
                JZ      heg_init_path_190               ; 74 0D
                ; ------ Default path: BIOS mode 0Eh (640x200 EGA fallback).
                MOV     AX, 000EH                       ; B8 0E 00
                INT     10H                             ; CD 10
                MOV     AX, 0A400H                      ; B8 00 A4
                MOV     ds:[GfxContext.wVgaPage2Base], AX      ; A3 12 00
                JMP     heg_init_build_scanline_lut     ; EB 73             ; -> step 6
                ; ------ 0x190 path: MODE 12h + CRTC tweak for 640x400 visible.
heg_init_path_190:
                MOV     AX, 0012H                       ; B8 12 00
                INT     10H                             ; CD 10             ; set VGA 640x480x16
                MOV     AX, 1013H                       ; B8 13 10
                MOV     BX, 0100H                       ; BB 00 01
                INT     10H                             ; CD 10             ; palette block 1
                CALL    heg_reset_attribute_palette     ; E8 A1 00
                MOV     AX, 0A800H                      ; B8 00 A8
                MOV     ds:[GfxContext.wVgaPage2Base], AX      ; A3 12 00
                MOV     ds:[GfxContext.wVgaPage1Base], AX      ; A3 10 00
                ; CRTC tweaks at 0x3D4/0x3D5 -- shrink the visible area to 400 rows.
                MOV     DX, 03D4H                       ; BA D4 03
                MOV     AL, 12H                         ; B0 12             ; reg 0x12 = vertical display end
                OUT     DX, AL                          ; EE
                INC     DX                              ; 42
                IN      AL, DX                          ; EC
                SUB     AL, 23H                         ; 2C 23
                OUT     DX, AL                          ; EE                ; write back reduced value
                MOV     DX, 03D4H                       ; BA D4 03
                MOV     AL, 15H                         ; B0 15             ; CR15 = start vertical blanking (low 8 bits)
                OUT     DX, AL                          ; EE
                INC     DX                              ; 42
                IN      AL, DX                          ; EC                ; read CR15 -- value dropped (likely a
                                                                            ;   stubbed mode-set verification check;
                                                                            ;   see plate header note on "CR15 read")
                NOP                                     ; 90
                DEC     DX                              ; 4A
                MOV     AL, 16H                         ; B0 16             ; reg 0x16 = end vertical blanking
                OUT     DX, AL                          ; EE
                INC     DX                              ; 42
                IN      AL, DX                          ; EC
                ADD     AL, 28H                         ; 04 28
                OUT     DX, AL                          ; EE
                DEC     DX                              ; 4A
                MOV     AL, 0CH                         ; B0 0C             ; reg 0x0C = start address hi
                OUT     DX, AL                          ; EE
                INC     DX                              ; 42
                MOV     AL, 0F1H                        ; B0 F1
                OUT     DX, AL                          ; EE
                DEC     DX                              ; 4A
                MOV     AL, 0DH                         ; B0 0D             ; reg 0x0D = start address lo
                OUT     DX, AL                          ; EE
                INC     DX                              ; 42
                MOV     AL, 0F0H                        ; B0 F0
                OUT     DX, AL                          ; EE
                JMP     heg_init_build_scanline_lut     ; EB 2B             ; -> step 6
                ; ------ 0x15E path: MODE 10h (EGA hi-res 640x350x16).
heg_init_path_15e:
                MOV     AX, 0010H                       ; B8 10 00
                INT     10H                             ; CD 10
                MOV     AX, 1013H                       ; B8 13 10
                MOV     BX, 0100H                       ; BB 00 01
                INT     10H                             ; CD 10             ; palette block 1
                CALL    heg_reset_attribute_palette     ; E8 59 00
                JMP     heg_init_build_scanline_lut     ; EB 19             ; -> step 6
                ; ------ 0x1E0 path: MODE 12h (VGA hi-res 640x480x16, A000).
heg_init_path_1e0:
                MOV     AX, 0012H                       ; B8 12 00
                INT     10H                             ; CD 10
                MOV     AX, 1013H                       ; B8 13 10
                MOV     BX, 0100H                       ; BB 00 01
                INT     10H                             ; CD 10
                CALL    heg_reset_attribute_palette     ; E8 47 00
                MOV     AX, 0A000H                      ; B8 00 A0
                MOV     ds:[GfxContext.wVgaPage2Base], AX      ; A3 12 00
                MOV     ds:[GfxContext.wVgaPage1Base], AX      ; A3 10 00          ; A000 instead of A800
                ; ------ Step 6: build 480-entry scanline-offset LUT.
heg_init_build_scanline_lut:
                MOV     CX, 01E0H                       ; B9 E0 01          ; 480 entries
                MOV     DI, GfxContext.pRow_offset_lut  ; BF F2 06          ; LUT base in scratch DS
                MOV     AX, DS                          ; 8C D8
                MOV     ES, AX                          ; 8E C0             ; ES <- scratch DS
                XOR     AX, AX                          ; 33 C0             ; AX = 0 = first row offset
                CLD                                     ; FC
heg_init_lut_loop:
                STOSW                                   ; AB                ; *DI++ = AX
                ADD     AX, 50H                         ; 05 50 00          ; +80 bytes per row
                LOOP    heg_init_lut_loop               ; E2 FA
                ; ------ Step 7: program sequencer + graphics controller.
                MOV     DX, 03C4H                       ; BA C4 03
                MOV     AX, 0F02H                       ; B8 02 0F          ; seq idx 0x02 (map mask) = 0x0F (all planes)
                OUT     DX, AX                          ; EF
                MOV     DX, 03CEH                       ; BA CE 03
                MOV     AX, 0205H                       ; B8 05 02          ; gfx idx 0x05 (mode) = 0x02 (read 0, write 2)
                OUT     DX, AX                          ; EF
                ; ------ Step 8: return-value setup + epilogue.
                MOV     DX, CS                          ; 8C CA             ; DX = chunk segment
                MOV     SI, OFFSET g_apfnHegVtable      ; BE 3E 01          ; SI = 0x013E
                MOV     AX, 0280H                       ; B8 80 02          ; 640 = visible width
                MOV     ds:[GfxContext.wScreen_width], AX      ; A3 EA 06
                DEC     AX                              ; 48                ; 0x27F
                MOV     ds:[GfxContext.nClip_xmax], AX         ; A3 06 00          ; clip-right = width-1
                MOV     AX, ds:[GfxContext.wScreen_height]     ; A1 EC 06          ; visible height
                DEC     AX                              ; 48
                MOV     ds:[GfxContext.nClip_ymax], AX         ; A3 0A 00          ; clip-bottom = height-1
                MOV     AX, 0002H                       ; B8 02 00          ; return success
                POP     DI                              ; 5F
                POP     DS                              ; 1F
                POP     BP                              ; 5D
                RETF                                    ; CB
heg_init        ENDP

; ============================================================================
; heg_reset_attribute_palette -- reset attribute-controller palette to
; identity mapping (colour N -> palette index N) for the 16 EGA/VGA
; foreground colours.
;
; Called by heg_init after every BIOS mode-set (BIOS sometimes sets
; an indirect palette; we want a clean 1:1 mapping so the in-game
; colour numbers and the framebuffer nibbles agree).
;
; Algorithm (per FreeVGA "attribute controller"):
;   Preamble: read port 0x3C0 once to capture whatever attribute-
;     index/palette-source byte the BIOS left there, and stash it
;     on the stack so we can restore it at the end. (Note that the
;     value of bit 5 -- "Palette Address Source" / PAS -- in this
;     captured byte determines whether the display will be enabled
;     when we write it back; after a successful BIOS mode-set it is
;     normally 1 = "use the AR for display".)
;   For each colour N in 0xF..0x1 (LOOP exits when CX reaches 0,
;   so colour 0 is NOT touched by the loop and keeps the BIOS's
;   identity entry):
;     - Read 0x3DA to reset the attribute-controller flip-flop
;       (every attribute-port access starts with the flip-flop in
;       "expecting index" state; a stray IRQ flipping it would
;       desync the index/data pair below).
;     - Write N to port 0x3C0 (selects palette register N -- bit 5
;       (PAS) must be 0 here so the controller treats this byte as
;       an index byte rather than enabling display from the AR).
;     - Write N to port 0x3C0 (data: identity-map palette[N] = N).
;       The `JMP $+2` between the two OUTs is a deliberate ~5-cycle
;       pad. The instruction's only "effect" is to flush the CPU's
;       prefetch queue and consume bus cycles -- which gives the AR
;       flip-flop and slow-bus chip time to settle between the
;       index write and the data write. AR writes on the 6-MHz
;       EGA bus can otherwise be missed if back-to-back. (Common
;       idiom in period-correct EGA drivers; not a cross-procedure
;       jump.)
;   Tail: pop the saved initial 0x3C0 byte and write it back. The
;     last OUT restores the original PAS bit so the display is
;     re-enabled (normally PAS=1 after the BIOS mode-set, so this
;     final OUT lets the freshly-loaded palette take effect).
;
; ABI (no caller args): NEAR call. Clobbers AX, CX, DX.
; Returns: nothing.
;
; Note the CLI on entry and STI after the loop -- prevents an IRQ
; in the middle of the attribute-port flip-flop dance, which would
; leave the flip-flop in the wrong state and corrupt the next
; attribute-port access made by either us or the IRQ handler.
; ============================================================================
heg_reset_attribute_palette PROC NEAR
                MOV     CX, 0FH                         ; B9 0F 00          ; loop count = 15 (LOOP exits at CX=0, so colour 0 untouched)
                MOV     DX, 03C0H                       ; BA C0 03          ; attribute index/data port
                IN      AL, DX                          ; EC                ; capture BIOS-set 0x3C0 state for tail restore
                PUSH    AX                              ; 50
heg_rap_loop:
                CLI                                     ; FA                ; keep IRQs out of the index/data pair below
                MOV     DX, 03DAH                       ; BA DA 03
                IN      AL, DX                          ; EC                ; reset attribute flip-flop (expects index next)
                MOV     DL, 0C0H                        ; B2 C0             ; DX = 0x3C0
                MOV     AL, CL                          ; 8A C1             ; AL = index N
                OUT     DX, AL                          ; EE                ; write index N (PAS bit 5 = 0)
                JMP     $+2                             ; EB 00             ; ~5-cycle pad: AR flip-flop settle delay
                                                                            ;   (NOT a cross-procedure jump)
                OUT     DX, AL                          ; EE                ; write data N (identity map: palette[N] = N)
                JMP     $+2                             ; EB 00             ; ~5-cycle pad (AR settle delay)
                LOOP    heg_rap_loop                    ; E2 EF             ; next colour (down to CX=1)
                STI                                     ; FB                ; re-enable IRQs
                POP     AX                              ; 58
                OUT     DX, AL                          ; EE                ; restore saved 0x3C0 state (PAS bit re-enables display)
                RET                                     ; C3
heg_reset_attribute_palette ENDP

; ----------------------------------------------------------------------------
; 3 bytes of zero pad at 0x013A..0x013D would normally fall here, but
; the bytes at 0x013A..0x013D are claimed by the dual-use storage
; equates (g_wHegChunkDataSeg / g_wHegInitParagraphs). They live INSIDE
; the .CODE segment; init's MOV CS:[imm16],AX instructions write them.
; On disk they're zero-initialised; we declare them as data here so
; TASM accounts for the 4 bytes that pad the gap between
; heg_reset_attribute_palette (ends 0x0139) and g_apfnHegVtable (starts
; 0x013E).
; ----------------------------------------------------------------------------
                ORG     013AH
                DW      0                               ; g_wHegChunkDataSeg @ 0x013A
                DW      0                               ; g_wHegInitParagraphs @ 0x013C

; ============================================================================
; g_apfnHegVtable -- 50-slot renderer-vtable template.
; chunk:0x013E..0x0205
;
; Snapshotted by the host into g_renderer_vtable @ 39ae:2ac6 after
; heg_init returns. Each entry is (offset, segment-placeholder).
; The host fills segment halves with the chunk's load segment.
;
; Slot map:
;   0   null
;   1   heg_glyph_row_blit        @ 0x124B
;   2   heg_line_renderer         @ 0x0998
;   3   heg_blit_sprite_noflip    @ 0x1231
;   4   heg_present_rect          @ 0x1561
;   5   heg_glyph_blit_wrapper    @ 0x12FB
;   6   heg_query_sprite_buf_size @ 0x138E
;   7   heg_blit_chunky_to_video  @ 0x13B9
;   8   heg_page_flip_present     @ 0x150F
;   9   heg_unimplemented_slot    @ 0x0252  (RETF)
;   10  heg_pixel_run_fill        @ 0x034F
;   11  heg_pixel_run_fill_alt    @ 0x027A
;   12  heg_unimplemented_slot    @ 0x0252
;   13  heg_query_image_set_size  @ 0x0FD4
;   14  heg_install_image_set     @ 0x1015
;   15  heg_unimplemented_slot    @ 0x0252
;   16  heg_image_install_helper  @ 0x04F1
;   17  heg_chunky_blit_alt       @ 0x15D0
;   18  heg_unimplemented_slot    @ 0x0252
;   19  heg_unimplemented_slot    @ 0x0252
;   20  heg_install_palette       @ 0x0F15
;   21  heg_getpixel              @ 0x1453
;   22  heg_putpixel              @ 0x14C9
;   23  heg_unimplemented_slot    @ 0x0252
;   24  heg_tail_retf_stub        @ 0x2AF1  (RETF)
;   25  heg_set_border_color      @ 0x2AF2
;   26  heg_set_palette_entry     @ 0x0EFE
;   27  heg_span_fill             @ 0x0BE6
;   28  heg_unimplemented_slot    @ 0x0252
;   29  heg_blit_sprite_master    @ 0x1720
;   30  heg_blit_byte_aligned_latched @ 0x25F2
;   31  heg_install_image_archive @ 0x268A
;   32  heg_reset_archive_install_flag @ 0x271F
;   33  heg_blit_sprite_planar    @ 0x2726
;   34  heg_palette_blend         @ 0x0F57
;   35  heg_unimplemented_slot    @ 0x0252
;   36  heg_blit_stretched_row    @ 0x07DB
;   37  heg_pattern_span_fill     @ 0x03DB
;   38  heg_chunky_row_blit_pixelwise @ 0x0938
;   39  null
;   40..49 null (HEG vtable does NOT overlap with the callback-
;          table copy region -- that region starts at 0x0206,
;          adjacent to the end of slot 49 at 0x0205).
;
; Because the on-disk segment halves are zero and the host stamps
; them with the chunk's load segment AFTER snapshotting, we declare
; each slot as `dw offset, 0`. Some offsets are written as numeric
; literals (rather than `OFFSET name`) because those names are
; forward-references to functions in later regions of the file; the
; offsets are documented in the slot map above.
; ============================================================================
g_apfnHegVtable LABEL  BYTE
                DW      0,         0                        ; slot 0  -- null
                DW      124BH,     0                        ; slot 1  heg_glyph_row_blit
                DW      0998H,     0                        ; slot 2  heg_line_renderer
                DW      1231H,     0                        ; slot 3  heg_blit_sprite_noflip
                DW      1561H,     0                        ; slot 4  heg_present_rect
                DW      12FBH,     0                        ; slot 5  heg_glyph_blit_wrapper
                DW      138EH,     0                        ; slot 6  heg_query_sprite_buf_size
                DW      13B9H,     0                        ; slot 7  heg_blit_chunky_to_video
                DW      150FH,     0                        ; slot 8  heg_page_flip_present
                DW      OFFSET heg_unimplemented_slot, 0    ; slot 9  RETF @ 0x0252
                DW      034FH,     0                        ; slot 10 heg_pixel_run_fill
                DW      027AH,     0                        ; slot 11 heg_pixel_run_fill_alt
                DW      OFFSET heg_unimplemented_slot, 0    ; slot 12 RETF
                DW      0FD4H,     0                        ; slot 13 heg_query_image_set_size
                DW      1015H,     0                        ; slot 14 heg_install_image_set
                DW      OFFSET heg_unimplemented_slot, 0    ; slot 15 RETF
                DW      04F1H,     0                        ; slot 16 heg_image_install_helper
                DW      15D0H,     0                        ; slot 17 heg_chunky_blit_alt
                DW      OFFSET heg_unimplemented_slot, 0    ; slot 18 RETF
                DW      OFFSET heg_unimplemented_slot, 0    ; slot 19 RETF
                DW      0F15H,     0                        ; slot 20 heg_install_palette
                DW      1453H,     0                        ; slot 21 heg_getpixel
                DW      14C9H,     0                        ; slot 22 heg_putpixel
                DW      OFFSET heg_unimplemented_slot, 0    ; slot 23 RETF
                DW      2AF1H,     0                        ; slot 24 heg_tail_retf_stub
                DW      2AF2H,     0                        ; slot 25 heg_set_border_color
                DW      0EFEH,     0                        ; slot 26 heg_set_palette_entry
                DW      0BE6H,     0                        ; slot 27 heg_span_fill
                DW      OFFSET heg_unimplemented_slot, 0    ; slot 28 RETF
                DW      1720H,     0                        ; slot 29 heg_blit_sprite_master
                DW      25F2H,     0                        ; slot 30 heg_blit_byte_aligned_latched
                DW      268AH,     0                        ; slot 31 heg_install_image_archive
                DW      271FH,     0                        ; slot 32 heg_reset_archive_install_flag
                DW      2726H,     0                        ; slot 33 heg_blit_sprite_planar
                DW      0F57H,     0                        ; slot 34 heg_palette_blend
                DW      OFFSET heg_unimplemented_slot, 0    ; slot 35 RETF
                DW      07DBH,     0                        ; slot 36 heg_blit_stretched_row
                DW      03DBH,     0                        ; slot 37 heg_pattern_span_fill
                DW      0938H,     0                        ; slot 38 heg_chunky_row_blit_pixelwise
                DW      0,         0                        ; slot 39 -- null
                DW      0, 0                                ; slot 40
                DW      0, 0                                ; slot 41
                DW      0, 0                                ; slot 42
                DW      0, 0                                ; slot 43
                DW      0, 0                                ; slot 44
                DW      0, 0                                ; slot 45
                DW      0, 0                                ; slot 46
                DW      0, 0                                ; slot 47
                DW      0, 0                                ; slot 48
                DW      0, 0                                ; slot 49

; ============================================================================
; g_apfnHegHostCallbacks -- 19-entry host-service-callback mirror.
; chunk:0x0206..0x0251 (76 bytes = 19 far pointers)
;
; Populated by heg_init's REP MOVSW prologue from the [BP+8] /
; [BP+0Ah] far pointer the host passes in. Chunk slots later
; CALLF [0x0206 + N*4] to invoke host services (file I/O,
; allocator, error reporting).
;
; ON-DISK DEFAULT: each slot points at heg_unimplemented_slot
; (offset 0x0252, segment-placeholder zero, stamped with chunk
; segment by host at the same time as the vtable). This is a
; defensive default -- if for any reason a callback gets invoked
; before init's REP MOVSW overwrites these slots, the call lands
; on the 1-byte RETF and returns harmlessly. CGA / EGA / EVG etc.
; have the same defensive default (and in their case the bytes
; overlap with the vtable tail's RETF-stub slots, which is why
; the affected vtable slots are effectively dead --
; the callback writes don't break anything that was live anyway).
;
; The HEG vtable (above) ends at 0x0205 and this region starts at
; 0x0206 -- ADJACENT, NO OVERLAP.
; ============================================================================
g_apfnHegHostCallbacks LABEL BYTE
                ; 19 default entries: (offset=heg_unimplemented_slot, seg=0)
                DW      OFFSET heg_unimplemented_slot, 0    ; callback 0
                DW      OFFSET heg_unimplemented_slot, 0    ; callback 1
                DW      OFFSET heg_unimplemented_slot, 0    ; callback 2
                DW      OFFSET heg_unimplemented_slot, 0    ; callback 3
                DW      OFFSET heg_unimplemented_slot, 0    ; callback 4
                DW      OFFSET heg_unimplemented_slot, 0    ; callback 5
                DW      OFFSET heg_unimplemented_slot, 0    ; callback 6
                DW      OFFSET heg_unimplemented_slot, 0    ; callback 7
                DW      OFFSET heg_unimplemented_slot, 0    ; callback 8
                DW      OFFSET heg_unimplemented_slot, 0    ; callback 9
                DW      OFFSET heg_unimplemented_slot, 0    ; callback 10
                DW      OFFSET heg_unimplemented_slot, 0    ; callback 11
                DW      OFFSET heg_unimplemented_slot, 0    ; callback 12
                DW      OFFSET heg_unimplemented_slot, 0    ; callback 13
                DW      OFFSET heg_unimplemented_slot, 0    ; callback 14
                DW      OFFSET heg_unimplemented_slot, 0    ; callback 15
                DW      OFFSET heg_unimplemented_slot, 0    ; callback 16
                DW      OFFSET heg_unimplemented_slot, 0    ; callback 17
                DW      OFFSET heg_unimplemented_slot, 0    ; callback 18

; ============================================================================
; heg_unimplemented_slot -- 1-byte RETF stub for unused vtable slots.
; chunk:0x0252
;
; Referenced by vtable slots 9, 12, 15, 18, 19, 23, 28, 35.
; Slot 24 separately points at heg_tail_retf_stub @ 0x2AF1, which
; is structurally identical (also a 1-byte RETF) -- duplicate stubs
; in different locations are an artifact of the original C source
; layout (two distinct `void f(void){}` definitions in different
; .C files, or a forward-declared placeholder and a real stub).
; Either way, both slots return immediately on call.
; ============================================================================
heg_unimplemented_slot PROC FAR
                RETF                                    ; CB
heg_unimplemented_slot ENDP

; One byte of zero pad at 0x0253 to align the LUT to an even address.
                DB      0                               ; 0x0253 pad byte

; ============================================================================
; g_abHegLeftMaskLut -- 8-byte left-edge mask LUT (chunk:0x0254..0x025B).
;
; Indexed by bit-position (0..7) within a byte; produces a mask with
; bits [pos..7] set (i.e. clears the LEFT side of a byte for partial-
; pixel updates at the leading edge of a fill or sprite).
;
;   idx 0: 0xFF (11111111)  -- no leading pixels skipped
;   idx 1: 0x7F (01111111)  -- 1 left pixel skipped
;   idx 2: 0x3F (00111111)
;   ...
;   idx 7: 0x01 (00000001)
;
; Used as `CS:[BX + offset g_abHegLeftMaskLut]` from heg_pixel_run_fill,
; heg_span_fill, and the sprite cores (register-ABI cores only).
; ============================================================================
g_abHegLeftMaskLut LABEL  BYTE
                DB      0FFH, 07FH, 03FH, 01FH, 00FH, 007H, 003H, 001H

; ============================================================================
; g_abHegRightMaskLut -- 8-byte right-edge mask LUT (chunk:0x025C..0x0263).
;
; Indexed by (8 - trailing_pixel_count) or similar; produces a mask
; with bits [0..pos-1] set (clears the RIGHT side of a byte for
; partial-pixel updates at the trailing edge).
;
;   idx 0: 0x00 (00000000)  -- all right pixels skipped
;   idx 1: 0x80 (10000000)  -- 7 right pixels skipped
;   idx 2: 0xC0 (11000000)
;   ...
;   idx 7: 0xFE (11111110)
; ============================================================================
g_abHegRightMaskLut LABEL  BYTE
                DB      000H, 080H, 0C0H, 0E0H, 0F0H, 0F8H, 0FCH, 0FEH

; ============================================================================
; g_abHegBitPosMaskLut -- 8-byte single-bit mask LUT (chunk:0x0264..0x026B).
;
; Indexed by bit-position (0..7); produces 0x80 >> idx -- a single set
; bit at position (7 - idx). Used by getpixel / putpixel / sprite cores
; to address one pixel within a packed byte.
;
;   idx 0: 0x80 (10000000)  -- leftmost pixel
;   idx 1: 0x40 (01000000)
;   ...
;   idx 7: 0x01 (00000001)  -- rightmost pixel
; ============================================================================
g_abHegBitPosMaskLut LABEL  BYTE
                DB      080H, 040H, 020H, 010H, 008H, 004H, 002H, 001H

; ============================================================================
; Chunk-local scratch globals at 0x026C..0x0279 (14 bytes).
;
; Mostly zero-initialised on disk; one slot at 0x0275 holds 0x02 on
; disk (looks like a per-driver "default attribute / fill colour"
; constant). The fields are sub-function scratch words at 0x026C / 026E /
; 0270 / 0272 / 0274 / 0276 / 0278 with no known semantic name; declared as
; raw words/bytes matching the on-disk layout.
; ============================================================================
DAT_0000_026c   DW      0                               ; 026C: ushort
DAT_0000_026e   DW      0                               ; 026E: ushort
DAT_0000_0270   DW      0                               ; 0270: ushort
DAT_0000_0272   DW      0                               ; 0272: ushort
DAT_0000_0274   DB      0                               ; 0274: uchar
DAT_0000_0275   DB      02H                             ; 0275: uchar (default attr?)
DAT_0000_0276   DW      0                               ; 0276: ushort
DAT_0000_0278   DW      0                               ; 0278: ushort

; ============================================================================
; heg_pixel_run_fill_alt -- horizontal run-of-pixels filler (planar, write mode 2).
; chunk:0x027A..0x034E
;
; Register-ABI helper invoked internally (no PROC frame). Fills a run
; of CX pixels starting at bit-offset BX within row, at ES:DI byte
; cursor. Uses a 2-byte "color" packed into AL (foreground) / AH-after-
; swap pattern for a dithered fill. The function uses sequencer/graphics-
; controller write-mode-2 to OR dithered nibbles into planes 0+2 and
; 1+3 separately (mask 0xAA then mask 0x55), then writes plain bytes
; for the bulk run via STOSW.
;
; Inputs:
;   AL  -- pixel colour code (0..15)
;   DX  -- low bit: parity (controls AH=AL initial swap)
;   BX  -- starting x-coordinate (in pixels)
;   CX  -- pixel count (run length)
;   ES:DI -- byte cursor (already at row base)
;
; Returns: AL clobbered, DI advanced, AX/BX/CX/DX clobbered.
; Uses CS-relative scratch at 0x26C (g_dwHegPixelRunColor).
; ============================================================================
                ASSUME  ds:NOTHING, es:NOTHING
heg_pixel_run_fill_alt PROC FAR
                MOV     AH, AL
                SHR     AH, 1
                SHR     AH, 1
                SHR     AH, 1
                SHR     AH, 1
                AND     DX, 1
                JZ      SHORT hpfa_no_swap
                XCHG    AL, AH
hpfa_no_swap:
                MOV     cs:[DAT_0000_026c], AX
                MOV     AX, BX
                SHR     AX, 1
                SHR     AX, 1
                SHR     AX, 1
                ADD     DI, AX                          ; advance byte cursor by x/8
                AND     BX, 7                           ; BX = pixel bit-position 0..7
                MOV     DX, BX
                ADD     DX, CX                          ; DX = end bit-pos within byte
                CMP     DX, 8
                JGE     SHORT hpfa_multi_byte
                ; ---- fast path: run fits inside one byte ----
                MOV     CX, cs:[DAT_0000_026c]
                MOV     AH, cs:[BX + offset g_abHegLeftMaskLut]
                MOV     BL, DL
                AND     AH, cs:[BX + offset g_abHegRightMaskLut]
                MOV     BL, AH                          ; BL = combined mask
                AND     AH, 0AAH                        ; planes 0 + 2 mask
                MOV     AL, 8
                MOV     DX, 3CEH
                OUT     DX, AX                          ; GC idx 8 (bit mask) := AH
                INC     DX                              ; DX = 0x3CF (data reg)
                MOV     AL, ES:[DI]                     ; latch read
                MOV     ES:[DI], CL                     ; write low colour byte
                MOV     AL, BL
                AND     AL, 55H                         ; planes 1 + 3 mask
                OUT     DX, AL                          ; bit mask := masked
                MOV     AL, ES:[DI]                     ; latch read
                MOV     AL, CH
                STOSB                                   ; ES:[DI++] := high colour byte
                JMP     hpfa_done
hpfa_multi_byte:
                ; ---- run spans multiple bytes ----
                MOV     DX, 8
                SUB     DX, BX                          ; DX = pixels before first byte boundary
                SUB     CX, DX                          ; CX = remaining pixels after first byte
                MOV     AH, cs:[BX + offset g_abHegLeftMaskLut]
                MOV     DX, 3CEH
                MOV     AL, 8
                OUT     DX, AL                          ; select GC idx 8 (bit mask)
                INC     DX                              ; DX = 0x3CF
                MOV     BX, cs:[DAT_0000_026c]
                MOV     AL, ES:[DI]                     ; latch
                MOV     AL, AH
                AND     AL, 0AAH
                OUT     DX, AL
                MOV     ES:[DI], BL
                MOV     AL, ES:[DI]                     ; latch
                MOV     AL, AH
                AND     AL, 55H
                OUT     DX, AL
                MOV     AL, BH
                STOSB
                MOV     AH, CL                          ; save low byte of CX
                SHR     CX, 1
                SHR     CX, 1
                SHR     CX, 1                           ; CX = full bytes remaining
                JZ      SHORT hpfa_tail
                MOV     AL, 0AAH
                OUT     DX, AL
                MOV     ES:[DI], BL
                SHR     AL, 1                           ; AL = 0x55
                OUT     DX, AL
                MOV     AL, ES:[DI]                     ; latch
                MOV     AL, BH
                MOV     DH, AH                          ; save tail bits
                MOV     AH, AL
                SHR     CX, 1                           ; word-count (carry = odd byte)
                REP STOSW
                MOV     AH, DH
                MOV     DH, 3
                JNC     SHORT hpfa_tail
                STOSB
hpfa_tail:
                MOV     CL, AH                          ; restore tail bits
                XCHG    CX, BX
                AND     BX, 7
                JZ      SHORT hpfa_done
                MOV     AH, cs:[BX + offset g_abHegRightMaskLut]
                MOV     AL, AH
                AND     AL, 0AAH
                OUT     DX, AL
                MOV     AL, ES:[DI]                     ; latch
                MOV     ES:[DI], CL
                MOV     AL, AH
                AND     AL, 55H
                OUT     DX, AL
                MOV     AL, ES:[DI]                     ; latch
                MOV     ES:[DI], CH
hpfa_done:
                RETF
heg_pixel_run_fill_alt ENDP

; ============================================================================
; heg_pixel_run_fill -- horizontal run-of-pixels filler (planar, write mode 2).
; chunk:0x034F..0x03DA
;
; Plain (non-dithered) variant of heg_pixel_run_fill_alt. Tests the
; high nibble of AL: if AL has any bits set in 0xF0, the function
; jumps to heg_pixel_run_fill_alt (the dithered 2-colour core). For
; a single-colour fill (AL in 0..15) it runs its own simpler loop.
;
; Inputs:
;   AL  -- pixel colour code (0..15); high nibble nonzero -> branch
;   BX  -- starting x-coordinate (pixels)
;   CX  -- pixel count
;   ES:DI -- byte cursor (at row base)
; ============================================================================
heg_pixel_run_fill PROC FAR
                OR      CX, CX
                JLE     SHORT hpfa_done                 ; share prev fn's RETF at 0x034E
                TEST    AL, 0F0H
                JZ      SHORT hpf_solid_fill
                JMP     heg_pixel_run_fill_alt          ; dithered path (NEAR jmp E9)
hpf_solid_fill:
                MOV     DX, AX                          ; save colour byte
                MOV     AX, BX
                SHR     AX, 1
                SHR     AX, 1
                SHR     AX, 1
                ADD     DI, AX
                AND     BX, 7
                MOV     AX, DX                          ; restore colour
                MOV     DX, BX
                ADD     DX, CX
                CMP     DX, 8
                JGE     SHORT hpf_multi_byte
                MOV     AH, cs:[BX + offset g_abHegLeftMaskLut]
                MOV     BL, DL
                MOV     CL, cs:[BX + offset g_abHegRightMaskLut]
                AND     AH, CL
                MOV     BL, AL
                MOV     AL, 8
                MOV     DX, 3CEH
                OUT     DX, AX                          ; GC idx 8 bit mask
                MOV     AL, ES:[DI]                     ; latch
                MOV     ES:[DI], BL
                JMP     SHORT hpf_done
hpf_multi_byte:
                MOV     DX, 8
                SUB     DX, BX
                SUB     CX, DX
                MOV     AH, cs:[BX + offset g_abHegLeftMaskLut]
                MOV     BL, AL
                MOV     AL, 8
                MOV     DX, 3CEH
                OUT     DX, AX                          ; GC idx 8 bit mask
                MOV     AL, ES:[DI]                     ; latch
                MOV     AL, BL
                STOSB
                PUSH    CX
                AND     CX, 0FFF8H
                JZ      SHORT hpf_drained
                SHR     CX, 1
                SHR     CX, 1
                SHR     CX, 1
                MOV     AX, 0FF08H
                OUT     DX, AX                          ; bit mask := 0xFF
                MOV     AL, BL
hpf_bulk_loop:
                MOV     AH, ES:[DI]                     ; latch
                STOSB
                LOOP    hpf_bulk_loop
hpf_drained:
                MOV     CL, BL
                POP     BX
                AND     BX, 7
                JZ      SHORT hpf_done
                MOV     AH, cs:[BX + offset g_abHegRightMaskLut]
                MOV     AL, 8
                OUT     DX, AX
                MOV     AL, ES:[DI]                     ; latch
                MOV     ES:[DI], CL
hpf_done:
                RETF
heg_pixel_run_fill ENDP

; ============================================================================
; heg_pattern_span_fill -- planar row blit using a per-bit pattern mask.
; chunk:0x03DB..0x04BF
;
; Reads bits from a source bitmap with a sliding mask, accumulates an
; output mask + 4 plane bytes (stored in CS scratch 0x270/0x272/0x274),
; and flushes them to the framebuffer via sequencer "map mask" writes
; once a byte is complete (carry out of ROR CH).
;
; The loop reads from [BP+0] -- the pattern source -- and the caller
; supplies BP, SI, DX, ES:DI, AX, CX. The inner ROR CH detects an 8-bit
; alignment boundary; on alignment the function emits one framebuffer
; byte per plane by cycling SEQUENCER index 2 (map mask) through plane
; selects 8, 4, 2, 1 (planes 3, 2, 1, 0) with a write to ES:[DI]
; between each, while GRAPHICS-CONTROLLER index 8 (bit mask) is set
; from the accumulated write-mask byte at cs:[0x274].
;
; Inputs:
;   DX  -- starting x
;   CX  -- pixel count
;   AX  -- bits-per-source-row index (then shifted x4 -> byte stride)
;   SI  -- source pattern base (modified)
;   BP  -- pattern stride / window base ([BP+0] loaded each iter)
;   ES:DI -- destination cursor
;
; Uses CS scratch at:
;   0x26e -- remaining pixel count
;   0x270 -- planes 0+1 accumulator
;   0x272 -- planes 2+3 accumulator
;   0x274 -- write mask
; ============================================================================
heg_pattern_span_fill PROC FAR
                MOV     BX, DX
                AND     BX, 7                           ; BX = bit-pos within first byte
                SHR     DX, 1
                SHR     DX, 1
                SHR     DX, 1
                ADD     DI, DX                          ; advance byte cursor
                XOR     DX, DX
                MOV     cs:[DAT_0000_0270], DX
                MOV     cs:[DAT_0000_0272], DX
                MOV     cs:[DAT_0000_0274], DL
                DEC     CX
                MOV     cs:[DAT_0000_026e], CX
                PUSH    AX
                SHL     AX, 1
                SHL     AX, 1
                ADD     SI, AX                          ; SI += stride*4
                MOV     CL, BL
                MOV     CH, 80H
                SHR     CH, CL                          ; CH = bit selector mask
                POP     DX                              ; DX = pattern stride
hpsf_pixel_loop:
                MOV     BX, [BP + 0]
                MOV     CL, BL
                SHR     BX, 1
                SHR     BX, 1
                SHR     BX, 1
                ADD     BX, SI                          ; BX = pattern byte address
                MOV     AL, 80H
                AND     CL, 7
                SHR     AL, CL
                MOV     CL, AL                          ; CL = source bit-mask
                TEST    [BX], CL
                JNZ     SHORT hpsf_skip
                OR      cs:[DAT_0000_0274], CH          ; write-enable this bit
                MOV     AX, cs:[DAT_0000_0270]
                SUB     BX, DX
                TEST    [BX], CL
                JZ      SHORT hpsf_p1_off
                OR      AL, CH
hpsf_p1_off:
                SUB     BX, DX
                TEST    [BX], CL
                JZ      SHORT hpsf_p2_off
                OR      AH, CH
hpsf_p2_off:
                MOV     cs:[DAT_0000_0270], AX
                MOV     AX, cs:[DAT_0000_0272]
                SUB     BX, DX
                TEST    [BX], CL
                JZ      SHORT hpsf_p3_off
                OR      AL, CH
hpsf_p3_off:
                SUB     BX, DX
                TEST    [BX], CL
                JZ      SHORT hpsf_p4_off
                OR      AH, CH
hpsf_p4_off:
                MOV     cs:[DAT_0000_0272], AX
hpsf_skip:
                ADD     BP, 2
                ROR     CH, 1
                JC      SHORT hpsf_emit_byte
                DEC     word ptr cs:[DAT_0000_026e]
                JA      SHORT hpsf_pixel_loop           ; (target 0x0410)
                JMP     SHORT heg_pattern_span_flush_tail ; (target 0x04C0)
hpsf_emit_byte:
                PUSH    DX
                MOV     DX, 3CFH                        ; GC data reg
                MOV     AL, cs:[DAT_0000_0274]
                OR      AL, AL
                JZ      SHORT hpsf_no_write
                CMP     AL, 0FFH
                JZ      SHORT hpsf_skip_latch
                MOV     AH, ES:[DI]                     ; latch read
hpsf_skip_latch:
                OUT     DX, AL                          ; GC bit mask := AL
                MOV     BX, cs:[DAT_0000_0270]
                MOV     DX, 3C5H                        ; SEQ data reg
                MOV     AL, 8                           ; plane 3 (0b1000)
                OUT     DX, AL
                MOV     ES:[DI], BL
                SHR     AL, 1                           ; plane 2 (0b0100)
                OUT     DX, AL
                MOV     ES:[DI], BH
                MOV     BX, cs:[DAT_0000_0272]
                SHR     AL, 1                           ; plane 1
                OUT     DX, AL
                MOV     ES:[DI], BL
                SHR     AL, 1                           ; plane 0
                OUT     DX, AL
                MOV     ES:[DI], BH
hpsf_no_write:
                INC     DI
                XOR     AX, AX
                MOV     cs:[DAT_0000_0270], AX
                MOV     cs:[DAT_0000_0272], AX
                MOV     cs:[DAT_0000_0274], AL
                POP     DX
                DEC     word ptr cs:[DAT_0000_026e]
                JLE     SHORT hpsf_retf
                JMP     hpsf_pixel_loop                 ; NEAR (target 0x040D)
hpsf_retf:
                RETF
heg_pattern_span_fill ENDP

; ============================================================================
; heg_pattern_span_flush_tail -- emit the final accumulated pattern byte.
; chunk:0x04C0..0x04F0
;
; Called by the pattern-span loop when the run ends mid-byte. Reads
; the latch via a dummy ES:[DI] load, programs GC bit mask from
; CS:[0x274], then for each of the 4 planes writes either the low
; or high byte of the accumulated 16-bit plane data at CS:[0x270]
; (planes 0+1) and CS:[0x272] (planes 2+3).
; ============================================================================
heg_pattern_span_flush_tail PROC FAR
                MOV     AL, ES:[DI]                     ; latch read
                MOV     DX, 3CFH
                MOV     AL, cs:[DAT_0000_0274]
                OUT     DX, AL                          ; GC bit mask
                MOV     BX, cs:[DAT_0000_0270]
                MOV     DX, 3C5H                        ; SEQ data
                MOV     AL, 8                           ; plane 3
                OUT     DX, AL
                MOV     ES:[DI], BL
                SHR     AL, 1                           ; plane 2
                OUT     DX, AL
                MOV     ES:[DI], BH
                MOV     BX, cs:[DAT_0000_0272]
                SHR     AL, 1                           ; plane 1
                OUT     DX, AL
                MOV     ES:[DI], BL
                SHR     AL, 1                           ; plane 0
                OUT     DX, AL
                MOV     ES:[DI], BH
                RETF
heg_pattern_span_flush_tail ENDP

; ============================================================================
; heg_image_install_helper -- pattern-driven planar blit with palette remap.
; chunk:0x04F1..0x07D6
;
; Large helper that reads a 4-plane source bitmap, transposes 8 source
; pixels into a per-plane mask, and writes through the planar
; framebuffer via sequencer/graphics-controller programming.
;
; Two emit cores follow the inner loop:
;   - hii_emit_remap   @ 0x0595 : full 4-plane transpose with palette
;                                 remap byte at CS:[0x275] (=BL+1 from
;                                 SS:[BX] table read).
;   - hii_emit_simple  @ 0x06CD : fixed-mapping transpose (CMP AH,2).
;
; Both cores program GC bit-mask 0x3CE/0x3CF then SEQ map-mask 0x3C4/
; 0x3C5 to splay the accumulated 16-bit plane data across 4 planes.
; ============================================================================
heg_image_install_helper PROC FAR
                MOV     BX, 06BCH                       ; (host palette page table base?)
                ADD     BX, cs:[g_wHegInitParagraphs]   ; +CS:[0x13C]
                MOV     BL, SS:[BX]                     ; read byte from stack-seg
                INC     BL
                MOV     cs:[DAT_0000_0275], BL          ; store remap key+1
                MOV     BX, DX
                AND     BX, 7
                SHR     DX, 1
                SHR     DX, 1
                SHR     DX, 1
                ADD     DI, DX
                XOR     DX, DX
                MOV     cs:[DAT_0000_0270], DX
                MOV     cs:[DAT_0000_0272], DX
                MOV     cs:[DAT_0000_0274], DL
                DEC     CX
                MOV     cs:[DAT_0000_026e], CX
                PUSH    AX
                SHL     AX, 1
                SHL     AX, 1
                ADD     SI, AX
                MOV     CL, BL
                MOV     CH, 80H
                SHR     CH, CL
                POP     DX
hii_pixel_loop:
                MOV     BX, [BP + 0]
                MOV     CL, BL
                SHR     BX, 1
                SHR     BX, 1
                SHR     BX, 1
                ADD     BX, SI
                MOV     AL, 80H
                AND     CL, 7
                SHR     AL, CL
                MOV     CL, AL
                TEST    [BX], CL
                JNZ     SHORT hii_skip
                OR      cs:[DAT_0000_0274], CH
                MOV     AX, cs:[DAT_0000_0270]
                SUB     BX, DX
                TEST    [BX], CL
                JZ      SHORT hii_p1_off
                OR      AL, CH
hii_p1_off:
                SUB     BX, DX
                TEST    [BX], CL
                JZ      SHORT hii_p2_off
                OR      AH, CH
hii_p2_off:
                MOV     cs:[DAT_0000_0270], AX
                MOV     AX, cs:[DAT_0000_0272]
                SUB     BX, DX
                TEST    [BX], CL
                JZ      SHORT hii_p3_off
                OR      AL, CH
hii_p3_off:
                SUB     BX, DX
                TEST    [BX], CL
                JZ      SHORT hii_p4_off
                OR      AH, CH
hii_p4_off:
                MOV     cs:[DAT_0000_0272], AX
hii_skip:
                ADD     BP, 2
                ROR     CH, 1
                JC      SHORT hii_emit_remap
                DEC     word ptr cs:[DAT_0000_026e]
                JA      SHORT hii_pixel_loop
                JMP     hii_emit_simple                 ; (target 0x06cd)
hii_emit_remap:
                PUSH    DX
                PUSH    ES
                MOV     AX, 0AC00H
                MOV     ES, AX                          ; ES = pattern temp seg
                MOV     DX, 3CEH
                MOV     AX, 4
                OUT     DX, AX                          ; GC idx 4 (read plane sel)
                INC     DX
                MOV     BL, ES:[DI]                     ; read plane 0
                MOV     AL, 1
                OUT     DX, AL
                MOV     BH, ES:[DI]                     ; read plane 1
                INC     AL
                OUT     DX, AL
                MOV     CL, ES:[DI]                     ; read plane 2
                INC     AL
                OUT     DX, AL
                MOV     DL, ES:[DI]                     ; read plane 3
                MOV     DH, cs:[DAT_0000_0275]          ; remap threshold
                XOR     AX, AX
                ; --- 8x transpose with remap CMP AH,DH ---
                SHL     DL, 1                           ; pixel 0
                RCL     AH, 1
                SHL     CL, 1
                RCL     AH, 1
                SHL     BH, 1
                RCL     AH, 1
                SHL     BL, 1
                RCL     AH, 1
                CMP     AH, DH
                RCL     AL, 1
                XOR     AH, AH
                SHL     DL, 1                           ; pixel 1
                RCL     AH, 1
                SHL     CL, 1
                RCL     AH, 1
                SHL     BH, 1
                RCL     AH, 1
                SHL     BL, 1
                RCL     AH, 1
                CMP     AH, DH
                RCL     AL, 1
                XOR     AH, AH
                SHL     DL, 1                           ; pixel 2
                RCL     AH, 1
                SHL     CL, 1
                RCL     AH, 1
                SHL     BH, 1
                RCL     AH, 1
                SHL     BL, 1
                RCL     AH, 1
                CMP     AH, DH
                RCL     AL, 1
                XOR     AH, AH
                SHL     DL, 1                           ; pixel 3
                RCL     AH, 1
                SHL     CL, 1
                RCL     AH, 1
                SHL     BH, 1
                RCL     AH, 1
                SHL     BL, 1
                RCL     AH, 1
                CMP     AH, DH
                RCL     AL, 1
                XOR     AH, AH
                SHL     DL, 1                           ; pixel 4
                RCL     AH, 1
                SHL     CL, 1
                RCL     AH, 1
                SHL     BH, 1
                RCL     AH, 1
                SHL     BL, 1
                RCL     AH, 1
                CMP     AH, DH
                RCL     AL, 1
                XOR     AH, AH
                SHL     DL, 1                           ; pixel 5
                RCL     AH, 1
                SHL     CL, 1
                RCL     AH, 1
                SHL     BH, 1
                RCL     AH, 1
                SHL     BL, 1
                RCL     AH, 1
                CMP     AH, DH
                RCL     AL, 1
                XOR     AH, AH
                SHL     DL, 1                           ; pixel 6
                RCL     AH, 1
                SHL     CL, 1
                RCL     AH, 1
                SHL     BH, 1
                RCL     AH, 1
                SHL     BL, 1
                RCL     AH, 1
                CMP     AH, DH
                RCL     AL, 1
                XOR     AH, AH
                SHL     DL, 1                           ; pixel 7
                RCL     AH, 1
                SHL     CL, 1
                RCL     AH, 1
                SHL     BH, 1
                RCL     AH, 1
                SHL     BL, 1
                RCL     AH, 1
                CMP     AH, DH
                RCL     AL, 1
                XOR     AH, AH
                AND     cs:[DAT_0000_0274], AL          ; combine write-mask
                POP     ES
                MOV     DX, 3CEH
                MOV     AL, 8
                OUT     DX, AL                          ; GC idx 8 (bit mask)
                INC     DX
                MOV     AL, cs:[DAT_0000_0274]
                OR      AL, AL
                JZ      SHORT hii_no_emit
                CMP     AL, 0FFH
                JZ      SHORT hii_skip_latch
                MOV     AH, ES:[DI]                     ; latch
hii_skip_latch:
                OUT     DX, AL
                MOV     BX, cs:[DAT_0000_0270]
                MOV     DX, 3C5H
                MOV     AL, 8                           ; plane 3
                OUT     DX, AL
                MOV     ES:[DI], BL
                SHR     AL, 1                           ; plane 2
                OUT     DX, AL
                MOV     ES:[DI], BH
                MOV     BX, cs:[DAT_0000_0272]
                SHR     AL, 1                           ; plane 1
                OUT     DX, AL
                MOV     ES:[DI], BL
                SHR     AL, 1                           ; plane 0
                OUT     DX, AL
                MOV     ES:[DI], BH
hii_no_emit:
                INC     DI
                XOR     AX, AX
                MOV     cs:[DAT_0000_0270], AX
                MOV     cs:[DAT_0000_0272], AX
                MOV     cs:[DAT_0000_0274], AL
                POP     DX
                DEC     word ptr cs:[DAT_0000_026e]
                JLE     SHORT hii_retf
                JMP     hii_pixel_loop                  ; NEAR (target 0x0535)
hii_retf:
                RETF
hii_emit_simple:
                PUSH    ES
                MOV     AX, 0AC00H
                MOV     ES, AX
                MOV     DX, 3CEH
                MOV     AX, 4
                OUT     DX, AX
                INC     DX
                MOV     BL, ES:[DI]
                MOV     AL, 1
                OUT     DX, AL
                MOV     BH, ES:[DI]
                INC     AL
                OUT     DX, AL
                MOV     CL, ES:[DI]
                INC     AL
                OUT     DX, AL
                MOV     DL, ES:[DI]
                XOR     AX, AX
                ; --- 8x transpose with CMP AH,2 ---
                SHL     DL, 1                           ; pixel 0
                RCL     AH, 1
                SHL     CL, 1
                RCL     AH, 1
                SHL     BH, 1
                RCL     AH, 1
                SHL     BL, 1
                RCL     AH, 1
                CMP     AH, 2
                RCL     AL, 1
                SHL     DL, 1                           ; pixel 1
                RCL     AH, 1
                SHL     CL, 1
                RCL     AH, 1
                SHL     BH, 1
                RCL     AH, 1
                SHL     BL, 1
                RCL     AH, 1
                CMP     AH, 2
                RCL     AL, 1
                SHL     DL, 1                           ; pixel 2
                RCL     AH, 1
                SHL     CL, 1
                RCL     AH, 1
                SHL     BH, 1
                RCL     AH, 1
                SHL     BL, 1
                RCL     AH, 1
                CMP     AH, 2
                RCL     AL, 1
                SHL     DL, 1                           ; pixel 3
                RCL     AH, 1
                SHL     CL, 1
                RCL     AH, 1
                SHL     BH, 1
                RCL     AH, 1
                SHL     BL, 1
                RCL     AH, 1
                CMP     AH, 2
                RCL     AL, 1
                SHL     DL, 1                           ; pixel 4
                RCL     AH, 1
                SHL     CL, 1
                RCL     AH, 1
                SHL     BH, 1
                RCL     AH, 1
                SHL     BL, 1
                RCL     AH, 1
                CMP     AH, 2
                RCL     AL, 1
                SHL     DL, 1                           ; pixel 5
                RCL     AH, 1
                SHL     CL, 1
                RCL     AH, 1
                SHL     BH, 1
                RCL     AH, 1
                SHL     BL, 1
                RCL     AH, 1
                CMP     AH, 2
                RCL     AL, 1
                SHL     DL, 1                           ; pixel 6
                RCL     AH, 1
                SHL     CL, 1
                RCL     AH, 1
                SHL     BH, 1
                RCL     AH, 1
                SHL     BL, 1
                RCL     AH, 1
                CMP     AH, 2
                RCL     AL, 1
                SHL     DL, 1                           ; pixel 7
                RCL     AH, 1
                SHL     CL, 1
                RCL     AH, 1
                SHL     BH, 1
                RCL     AH, 1
                SHL     BL, 1
                RCL     AH, 1
                CMP     AH, 2
                RCL     AL, 1
                AND     cs:[DAT_0000_0274], AL
                POP     ES
                MOV     DL, 0CEH                        ; DH still 0x3 -> DX = 0x3CE
                MOV     AL, 8
                OUT     DX, AL                          ; GC idx 8
                INC     DX
                MOV     AL, ES:[DI]                     ; latch
                MOV     DX, 3CFH
                MOV     AL, cs:[DAT_0000_0274]
                OUT     DX, AL                          ; bit mask
                MOV     BX, cs:[DAT_0000_0270]
                MOV     DX, 3C5H
                MOV     AL, 8                           ; plane 3
                OUT     DX, AL
                MOV     ES:[DI], BL
                SHR     AL, 1
                OUT     DX, AL
                MOV     ES:[DI], BH
                MOV     BX, cs:[DAT_0000_0272]
                SHR     AL, 1
                OUT     DX, AL
                MOV     ES:[DI], BL
                SHR     AL, 1
                OUT     DX, AL
                MOV     ES:[DI], BH
                RETF
heg_image_install_helper ENDP

; ----------------------------------------------------------------------------
; Orphan epilogue bytes at 0x07D7..0x07DA (4 bytes: 5F 1F 5D C3).
; These are reached by heg_blit_stretched_row's early-exit JLE at 0x07E8
; (`7E ED` -> target 0x07D7). They decode as `POP DI; POP DS; POP BP;
; RET (near)` -- a stale Borland epilogue that doesn't match the
; function's actual prologue (which only pushes BP). The path looks
; dead at the C level (only taken when the negate-then-clamp branch
; underflows).
; ----------------------------------------------------------------------------
heg_blit_stretched_row_orphan LABEL BYTE
                POP     DI
                POP     DS
                POP     BP
                RET                                     ; NEAR return

; ============================================================================
; heg_blit_stretched_row -- planar row blit with horizontal source offset.
; chunk:0x07DB..0x0937
;
; Sets up BP stack frame; takes far-source pointer + dest pos + width
; in stack args. Iterates over CX pixels, reading from [BP+0]
; (source-row pointer slot), transposing bits across 4 planes, and
; flushing every 8 pixels via SEQ map-mask writes.
;
; Stack args (after PUSH BP / MOV BP,SP):
;   [BP+0x04..0x06] : source segment offset (?)
;   [BP+0x08]       : source-x in pixels
;   [BP+0x0A]       : pattern stride
;
; Tail-flushes the partial accumulator at the end and restores DS=SS.
; ============================================================================
heg_blit_stretched_row PROC FAR
                PUSH    BP
                MOV     BP, SP
                MOV     AX, DX
                OR      AX, AX
                JNS     SHORT hbsr_no_neg
                NEG     AX
                SUB     CX, AX
                JLE     SHORT heg_blit_stretched_row_orphan ; target 0x07D7
                SHL     AX, 1
                ADD     [BP + 0AH], AX
                XOR     AX, AX
hbsr_no_neg:
                MOV     BL, AL
                SHR     AX, 1
                SHR     AX, 1
                SHR     AX, 1
                ADD     DI, AX
                MOV     AL, 8
                MOV     DX, 3CEH
                OUT     DX, AL
                XOR     AX, AX
                MOV     cs:[DAT_0000_0270], AX
                MOV     cs:[DAT_0000_0272], AX
                MOV     cs:[DAT_0000_0274], AL
                AND     BX, 7
                MOV     AH, cs:[BX + offset g_abHegBitPosMaskLut]
                PUSH    BP
                MOV     BX, [BP + 8]
                MOV     cs:[DAT_0000_0276], BX
                MOV     BP, [BP + 6]
                MOV     BX, [BP + 4]
                MOV     cs:[DAT_0000_0278], BX
                MOV     DS, [BP + 0]
                POP     BP
                MOV     BP, [BP + 0AH]
                MOV     cs:[DAT_0000_026e], CX
hbsr_pixel_loop:
                MOV     SI, [BP + 0]
                ADD     BP, 2
                ADD     SI, cs:[DAT_0000_0276]
                MOV     CX, SI
                SHR     SI, 1
                SHR     SI, 1
                SHR     SI, 1
                MOV     BX, cs:[DAT_0000_0278]
                ADD     SI, BX
                SHR     BX, 1
                SHR     BX, 1
                MOV     AL, 80H
                AND     CL, 7
                SHR     AL, CL
                TEST    [SI], AL
                JNZ     SHORT hbsr_skip
                OR      cs:[DAT_0000_0274], AH
                MOV     DX, cs:[DAT_0000_0270]
                SUB     SI, BX
                TEST    [SI], AL
                JZ      SHORT hbsr_p1_off
                OR      DL, AH
hbsr_p1_off:
                SUB     SI, BX
                TEST    [SI], AL
                JZ      SHORT hbsr_p2_off
                OR      DH, AH
hbsr_p2_off:
                MOV     cs:[DAT_0000_0270], DX
                MOV     DX, cs:[DAT_0000_0272]
                SUB     SI, BX
                TEST    [SI], AL
                JZ      SHORT hbsr_p3_off
                OR      DL, AH
hbsr_p3_off:
                SUB     SI, BX
                TEST    [SI], AL
                JZ      SHORT hbsr_p4_off
                OR      DH, AH
hbsr_p4_off:
                MOV     cs:[DAT_0000_0272], DX
hbsr_skip:
                ROR     AH, 1
                JC      SHORT hbsr_flush_byte
                DEC     word ptr cs:[DAT_0000_026e]
                JNZ     SHORT hbsr_pixel_loop
                JMP     SHORT hbsr_tail_flush
hbsr_flush_byte:
                MOV     AL, cs:[DAT_0000_0274]
                OR      AL, AL
                JZ      SHORT hbsr_zero_mask
                MOV     DX, 3CFH
                OUT     DX, AL
                INC     AL
                JZ      SHORT hbsr_skip_latch
                MOV     AL, ES:[DI]                     ; latch
hbsr_skip_latch:
                MOV     BX, cs:[DAT_0000_0270]
                MOV     DX, 3C5H
                MOV     AL, 8
                OUT     DX, AL
                MOV     ES:[DI], BL
                SHR     AL, 1
                OUT     DX, AL
                MOV     ES:[DI], BH
                MOV     BX, cs:[DAT_0000_0272]
                SHR     AL, 1
                OUT     DX, AL
                MOV     ES:[DI], BL
                SHR     AL, 1
                OUT     DX, AL
                MOV     ES:[DI], BH
hbsr_zero_mask:
                XOR     BX, BX
                MOV     cs:[DAT_0000_0270], BX
                MOV     cs:[DAT_0000_0272], BX
                MOV     cs:[DAT_0000_0274], BL
                INC     DI
                DEC     word ptr cs:[DAT_0000_026e]
                JZ      SHORT hbsr_tail_flush
                JMP     hbsr_pixel_loop                 ; NEAR (target 0x0837)
hbsr_tail_flush:
                MOV     AL, cs:[DAT_0000_0274]
                OR      AL, AL
                JZ      SHORT hbsr_exit
                MOV     DX, 3CFH
                OUT     DX, AL
                INC     AL
                JZ      SHORT hbsr_tail_skip_latch
                MOV     AL, ES:[DI]
hbsr_tail_skip_latch:
                MOV     BX, cs:[DAT_0000_0270]
                MOV     DX, 3C5H
                MOV     AL, 8
                OUT     DX, AL
                MOV     ES:[DI], BL
                SHR     AL, 1
                OUT     DX, AL
                MOV     ES:[DI], BH
                MOV     BX, cs:[DAT_0000_0272]
                SHR     AL, 1
                OUT     DX, AL
                MOV     ES:[DI], BL
                SHR     AL, 1
                OUT     DX, AL
                MOV     ES:[DI], BH
hbsr_exit:
                MOV     AX, SS
                MOV     DS, AX
                POP     BP
                RETF
heg_blit_stretched_row ENDP

; ============================================================================
; heg_chunky_row_blit_pixelwise -- single-byte-per-pixel chunky row blit.
; chunk:0x0938..0x098F
;
; Register ABI: BX=start_x, CX=count, ES:DI=dst, DS:SI=src.
; CF on entry selects direction:
;   CF=0 -> forward core  (ADC DI,0)   addresses INCREMENT
;   CF=1 -> reverse core  (SBB DI,0)   addresses DECREMENT
;
; Each pixel: program GC idx 8 with the current bit-mask, dummy-read
; the latch, LODSB the source colour byte, write to ES:[DI]. ROR/ROL
; AH rotates the bit-mask; ADC/SBB DI carries the byte advance when
; the mask wraps.
; ============================================================================
heg_chunky_row_blit_pixelwise PROC FAR
                JC      SHORT hcrb_reverse              ; (target 0x0965)
                ; ---- forward core ----
                MOV     DX, BX
                AND     BX, 7
                MOV     AH, cs:[BX + offset g_abHegBitPosMaskLut]
                SHR     DX, 1
                SHR     DX, 1
                SHR     DX, 1
                ADD     DI, DX
                MOV     DX, 3CEH
                MOV     AL, 8
                OUT     DX, AL                          ; GC idx 8
                INC     DX
hcrb_fwd_loop:
                MOV     AL, AH
                OUT     DX, AL                          ; bit mask
                MOV     AL, ES:[DI]                     ; latch
                LODSB                                   ; AL = next source colour
                MOV     ES:[DI], AL
                ROR     AH, 1
                ADC     DI, 0
                LOOP    hcrb_fwd_loop
                RETF
hcrb_reverse:
                ; ---- reverse core ----
                MOV     DX, BX
                AND     BX, 7
                MOV     AH, cs:[BX + offset g_abHegBitPosMaskLut]
                SHR     DX, 1
                SHR     DX, 1
                SHR     DX, 1
                ADD     DI, DX
                MOV     DX, 3CEH
                MOV     AL, 8
                OUT     DX, AL
                INC     DX
hcrb_rev_loop:
                MOV     AL, AH
                OUT     DX, AL
                MOV     AL, ES:[DI]
                LODSB
                MOV     ES:[DI], AL
                ROL     AH, 1
                SBB     DI, 0
                LOOP    hcrb_rev_loop
                RETF
heg_chunky_row_blit_pixelwise ENDP

; ----------------------------------------------------------------------------
; Inline copy of the bit-position mask LUT at 0x0990..0x0997 (8 bytes).
; A duplicate of g_abHegBitPosMaskLut @ 0x0264, embedded here likely as
; an artefact of the original source layout (different .obj sections
; linking adjacent).
; ----------------------------------------------------------------------------
g_abHegBitPosMaskLut_inline LABEL BYTE
                DB      080H, 040H, 020H, 010H, 008H, 004H, 002H, 001H

; ============================================================================
; heg_line_renderer -- Bresenham line drawer (slot-2 in vtable).
; chunk:0x0998..0x0BCB
;
; Real slot-2 line drawer. Draws a planar line from (BX,CX) to
; (DX,SI) using EGA write-mode-2 plus a precomputed bit-mask. Branches
; on slope into: vertical-only / horizontal-only / diagonal short axis
; (Bresenham) / diagonal long axis (Bresenham).
;
; Per-call scratch lives in scratch-DS:[0x6BC..0x6C4] (Bresenham
; quotient/remainder/error accumulator + current bit-mask).
; Reloads DS from cs:[g_wHegChunkDataSeg @ 0x13A] on entry,
; restores caller DS via POP DS before RETF.
; ============================================================================
heg_line_renderer PROC FAR
                PUSH    DS
                MOV     DS, cs:[g_wHegChunkDataSeg]     ; CS:[0x13a]
                XOR     AH, AH
                MOV     AL, ds:[GfxContext.bGfx_outline_color] ; pen colour
                MOV     ds:[22H], AX                       ; save in DS:[0x22] (driver scratch -- reserved hole)
                MOV     DI, BX
                AND     DI, 7
                MOV     AL, cs:[DI + 0990H]             ; bitpos mask (inline LUT)
                MOV     ds:[06C4H], AL                     ; DS:[0x6C4] := mask
                MOV     DI, CX
                SHL     DI, 1
                MOV     DI, [DI].GfxContext.pRow_offset_lut    ; scanline LUT lookup
                MOV     AX, BX
                SHR     AX, 1
                SHR     AX, 1
                SHR     AX, 1
                ADD     DI, AX                          ; DI = row_off + (x/8)
                CMP     BX, DX
                JNZ     SHORT hlr_x_diff
                CMP     CX, SI
                JZ      SHORT hlr_single_pixel
                JMP     SHORT hlr_vertical
hlr_x_diff:
                CMP     CX, SI
                JZ      SHORT hlr_horizontal
                JMP     SHORT hlr_diagonal
hlr_single_pixel:
                MOV     AH, ds:[06C4H]
                MOV     AL, ES:[DI]                     ; latch
                MOV     DX, 3CEH
                MOV     AL, 8
                OUT     DX, AX                          ; GC bit mask
                MOV     AX, ds:[22H]
                MOV     ES:[DI], AL
                JMP     hlr_exit                        ; (0x0bca)
hlr_horizontal:
                SUB     DX, BX
                MOV     CX, DX
                MOV     AH, ds:[06C4H]
                MOV     BX, ds:[22H]
                MOV     DX, 3CEH
                MOV     AL, 8
                MOV     BH, ES:[DI]                     ; latch
                OUT     DX, AX
                MOV     ES:[DI], BL
hlr_h_loop:
                ROR     AH, 1
                JC      SHORT hlr_h_carry
                MOV     BH, ES:[DI]
                OUT     DX, AX
                MOV     ES:[DI], BL
                DEC     CX
                JZ      SHORT hlr_h_exit
                JMP     SHORT hlr_h_loop
hlr_h_carry:
                INC     DI
                MOV     BH, ES:[DI]
                OUT     DX, AX
                MOV     ES:[DI], BL
                DEC     CX
                JZ      SHORT hlr_h_exit
                JMP     SHORT hlr_h_loop
hlr_h_exit:
                JMP     hlr_exit
hlr_vertical:
                MOV     AX, 50H
                MOV     BP, AX
                SUB     SI, CX
                JG      SHORT hlr_v_pos
                NEG     SI
                NEG     BP
hlr_v_pos:
                MOV     CX, SI
                MOV     AH, ds:[06C4H]
                MOV     BX, ds:[22H]
                MOV     DX, 3CEH
                MOV     AL, 8
                OUT     DX, AX
hlr_v_loop:
                MOV     BH, ES:[DI]
                MOV     ES:[DI], BL
                ADD     DI, BP
                DEC     CX
                JS      SHORT hlr_v_done
                JMP     SHORT hlr_v_loop
hlr_v_done:
                JMP     hlr_exit
hlr_diagonal:
                MOV     AX, 50H
                MOV     BP, AX
                SUB     DX, BX
                SUB     SI, CX
                JG      SHORT hlr_diag_pos
                NEG     SI
                NEG     BP
hlr_diag_pos:
                MOV     CX, SI
                CMP     CX, DX
                JZ      SHORT hlr_diag_eq
                JC      SHORT hlr_diag_dx_long
                JMP     hlr_diag_dx_short
hlr_diag_dx_long:
                JMP     hlr_diag_dx_long2
hlr_diag_eq:
                MOV     CX, DX
                MOV     AH, ds:[06C4H]
                MOV     BX, ds:[22H]
                MOV     DX, 3CEH
                MOV     AL, 8
                MOV     BH, ES:[DI]
                OUT     DX, AX
                MOV     ES:[DI], BL
hlr_eq_loop:
                ROR     AH, 1
                JC      SHORT hlr_eq_carry
                MOV     BH, ES:[DI]
                OUT     DX, AX
                MOV     ES:[DI], BL
                ADD     DI, BP
                MOV     BH, ES:[DI]
                MOV     ES:[DI], BL
                DEC     CX
                JZ      SHORT hlr_eq_done
                JMP     SHORT hlr_eq_loop
hlr_eq_carry:
                INC     DI
                MOV     BH, ES:[DI]
                OUT     DX, AX
                MOV     ES:[DI], BL
                DEC     CX
                JZ      SHORT hlr_eq_done
                ADD     DI, BP
                MOV     BH, ES:[DI]
                MOV     ES:[DI], BL
                JMP     SHORT hlr_eq_loop
hlr_eq_done:
                JMP     hlr_exit
hlr_diag_dx_long2:
                MOV     SI, DX
                MOV     AX, DX
                XOR     DX, DX
                INC     CX
                DIV     CX
                MOV     ds:[GfxContext.wTextureIdx], AX                     ; pixels-per-step quotient
                XOR     AX, AX
                DIV     CX
                MOV     ds:[06BEH], AX                     ; fractional remainder
                XOR     AX, AX
                MOV     ds:[06C2H], AX                     ; error accumulator
                MOV     AH, ds:[06C4H]
                MOV     BX, ds:[22H]
                MOV     DX, 3CEH
                MOV     AL, 8
                MOV     CX, ds:[GfxContext.wTextureIdx]
                INC     CX
                MOV     BH, ES:[DI]
                OUT     DX, AX
                MOV     ES:[DI], BL
hlr_long2_outer:
                MOV     ds:[06C0H], SI                     ; save remaining
                SUB     SI, CX
                JGE     SHORT hlr_long2_keep
                MOV     CX, ds:[06C0H]
                XOR     SI, SI
hlr_long2_keep:
                ROR     AH, 1
                JC      SHORT hlr_long2_carry
                MOV     BH, ES:[DI]
                OUT     DX, AX
                MOV     ES:[DI], BL
                DEC     CX
                JZ      SHORT hlr_long2_step
                JMP     SHORT hlr_long2_keep
hlr_long2_step:
                CMP     SI, 0
                JZ      SHORT hlr_long2_exit
                ADD     DI, BP
                MOV     BH, ES:[DI]
                MOV     ES:[DI], BL
                MOV     CX, ds:[06BEH]
                ADD     ds:[06C2H], CX
                JNC     SHORT hlr_long2_no_carry
                MOV     CX, ds:[GfxContext.wTextureIdx]
                INC     CX
                JMP     hlr_long2_outer
hlr_long2_no_carry:
                MOV     CX, ds:[GfxContext.wTextureIdx]
                JMP     hlr_long2_outer
hlr_long2_carry:
                INC     DI
                MOV     BH, ES:[DI]
                OUT     DX, AX
                MOV     ES:[DI], BL
                DEC     CX
                JZ      SHORT hlr_long2_step
                JMP     SHORT hlr_long2_keep
hlr_long2_exit:
                JMP     hlr_exit
hlr_diag_dx_short:
                XCHG    CX, DX
                MOV     SI, DX
                MOV     AX, DX
                XOR     DX, DX
                INC     CX
                DIV     CX
                MOV     ds:[GfxContext.wTextureIdx], AX
                XOR     AX, AX
                DIV     CX
                MOV     ds:[06BEH], AX
                XOR     AX, AX
                MOV     ds:[06C2H], AX
                MOV     AH, ds:[06C4H]
                MOV     BX, ds:[22H]
                MOV     DX, 3CEH
                MOV     AL, 8
                MOV     CX, ds:[GfxContext.wTextureIdx]
                INC     CX
                MOV     BH, ES:[DI]
                OUT     DX, AX
                MOV     ES:[DI], BL
hlr_short_outer:
                MOV     ds:[06C0H], SI
                SUB     SI, CX
                JGE     SHORT hlr_short_keep
                MOV     CX, ds:[06C0H]
                XOR     SI, SI
hlr_short_keep:
                ADD     DI, BP
                MOV     BH, ES:[DI]
                OUT     DX, AX
                MOV     ES:[DI], BL
                DEC     CX
                JZ      SHORT hlr_short_step
                JMP     SHORT hlr_short_keep
hlr_short_step:
                CMP     SI, 0
                JZ      SHORT hlr_exit
                ROR     AH, 1
                JC      SHORT hlr_short_carry
                MOV     BH, ES:[DI]
                OUT     DX, AX
                MOV     ES:[DI], BL
                MOV     CX, ds:[06BEH]
                ADD     ds:[06C2H], CX
                JNC     SHORT hlr_short_no_carry
                MOV     CX, ds:[GfxContext.wTextureIdx]
                INC     CX
                JMP     hlr_short_outer
hlr_short_no_carry:
                MOV     CX, ds:[GfxContext.wTextureIdx]
                JMP     hlr_short_outer
hlr_short_carry:
                INC     DI
                MOV     BH, ES:[DI]
                OUT     DX, AX
                MOV     ES:[DI], BL
                MOV     CX, ds:[06BEH]
                ADD     ds:[06C2H], CX
                JNC     SHORT hlr_short_no_carry2
                MOV     CX, ds:[GfxContext.wTextureIdx]
                INC     CX
                JMP     hlr_short_outer
hlr_short_no_carry2:
                MOV     CX, ds:[GfxContext.wTextureIdx]
                JMP     hlr_short_outer
hlr_exit:
                POP     DS
                RETF
heg_line_renderer ENDP

; ----------------------------------------------------------------------------
; Inline left+right mask LUTs at 0x0BCC..0x0BDB (16 bytes).
; Duplicates of g_abHegLeftMaskLut and g_abHegRightMaskLut at 0x0254
; and 0x025C, embedded here for the consumers that read with `[0BCCH+BX]`
; style indexing (locality with the line renderer or span fill).
; ----------------------------------------------------------------------------
g_abHegLeftMaskLut2 LABEL BYTE
                DB      0FFH, 07FH, 03FH, 01FH, 00FH, 007H, 003H, 001H
g_abHegRightMaskLut2 LABEL BYTE
                DB      000H, 080H, 0C0H, 0E0H, 0F0H, 0F8H, 0FCH, 0FEH

; ----------------------------------------------------------------------------
; Scratch globals at 0x0BDC..0x0BE5 (10 zero bytes -- 5 scratch words).
; ----------------------------------------------------------------------------
DAT_0000_0bdc   DW      0
DAT_0000_0bde   DW      0
DAT_0000_0be0   DW      0
DAT_0000_0be2   DW      0
DAT_0000_0be4   DW      0

; ============================================================================
; heg_span_fill -- multi-span planar fill (used for filled polys / rects).
; chunk:0x0BE6..0x0EC0
;
; Reads a series of (span_count, colour, span_descriptors...) records
; from DS:SI and paints them into the framebuffer. Three engines:
;
;   - solid-colour single-segment span fill (entry: 0x0C37)
;   - dithered two-colour A-pattern (entry: 0x0CD9 - 0x0DCF)
;   - dithered two-colour B-pattern (entry: 0x0DD3 - 0x0EBC)
;
; CS-scratch state:
;   0x0BDC -- dither phase A
;   0x0BDE -- remaining span count
;   0x0BE0 -- packed-byte for plain fill
;   0x0BE2 -- packed-byte for dither pattern B
;   0x0BE4 -- scanline LUT base (0x6F2 + paragraphs from heg_init)
; ============================================================================
heg_span_fill PROC FAR
                MOV     AX, 0205H
                MOV     DX, 3CEH
                OUT     DX, AX                          ; GC idx 5 := 2 (write mode 2)
                MOV     AX, 0FF08H
                OUT     DX, AX                          ; GC idx 8 := 0xFF (bit mask)
                PUSH    DS
                MOV     CX, ES
                MOV     DS, CX
                LODSW                                   ; AX = span_count * something
                SHL     AX, 1
                MOV     BP, AX
                LODSW                                   ; AX = total record count
                MOV     DS, cs:[g_wHegChunkDataSeg]     ; switch to scratch DS
                MOV     cs:[DAT_0000_0bde], AX
                MOV     AX, ds:[GfxContext.wGfxBlitDstPage]
                MOV     ES, AX                          ; ES = framebuffer seg
                MOV     AX, GfxContext.pRow_offset_lut
                ADD     AX, cs:[g_wHegInitParagraphs]
                MOV     cs:[DAT_0000_0be4], AX          ; scanline LUT base
                MOV     AL, ds:[GfxContext.bGfx_fill_color]
                XOR     AH, AH
                MOV     DL, AL
                MOV     AH, AL
                ROR     AH, 1
                ROR     AH, 1
                ROR     AH, 1
                ROR     AH, 1
                MOV     cs:[DAT_0000_0be0], AX
                AND     DL, 0F0H
                MOV     DS, CX                          ; restore caller DS
                JZ      SHORT hsf_solid_path
                XCHG    AL, AH
                JMP     hsf_dither_a                    ; (0x0cd9)
hsf_solid_path:
                ; ---- solid single-colour span fill ----
                LODSW
                MOV     BX, AX                          ; BX = start x
                LODSW
                SUB     AX, BX
                JGE     SHORT hsf_s_continue
                JMP     hsf_s_next                      ; (0x0cc9)
hsf_s_continue:
                INC     AX
                MOV     CX, AX                          ; CX = pixel count
                MOV     DI, cs:[DAT_0000_0be4]
                MOV     DI, [BP + DI]                   ; scanline base
                MOV     AX, cs:[DAT_0000_0be0]
                MOV     DX, AX
                MOV     AX, BX
                SHR     AX, 1
                SHR     AX, 1
                SHR     AX, 1
                ADD     DI, AX
                AND     BX, 7
                MOV     AX, DX
                MOV     DX, BX
                ADD     DX, CX
                CMP     DX, 8
                JL      SHORT hsf_s_one_byte
                MOV     DX, 8
                SUB     DX, BX
                SUB     CX, DX
                MOV     AH, cs:[BX + offset g_abHegLeftMaskLut2]
                MOV     BL, AL
                MOV     AL, 8
                MOV     DX, 3CEH
                OUT     DX, AX
                INC     DX
                MOV     AL, ES:[DI]                     ; latch
                MOV     AL, BL
                STOSB
                MOV     BH, CL
                SHR     CX, 1
                SHR     CX, 1
                SHR     CX, 1
                JZ      SHORT hsf_s_after_bulk
                MOV     AL, 0FFH
                OUT     DX, AL
                MOV     AL, BL
                REP STOSB
hsf_s_after_bulk:
                MOV     CL, BL
                MOV     BL, BH
                AND     BX, 7
                JZ      SHORT hsf_s_next
                MOV     AL, cs:[BX + offset g_abHegRightMaskLut2]
                OUT     DX, AL
                MOV     AL, ES:[DI]
                MOV     ES:[DI], CL
                JMP     SHORT hsf_s_next
hsf_s_one_byte:
                MOV     AH, cs:[BX + offset g_abHegLeftMaskLut2]
                MOV     BL, DL
                MOV     CL, cs:[BX + offset g_abHegRightMaskLut2]
                AND     AH, CL
                MOV     BL, AL
                MOV     AL, 8
                MOV     DX, 3CEH
                OUT     DX, AX
                MOV     AL, ES:[DI]
                MOV     ES:[DI], BL
hsf_s_next:
                SUB     word ptr cs:[DAT_0000_0bde], 1
                JLE     SHORT hsf_s_exit
                ADD     BP, 2
                JMP     hsf_solid_path                  ; (0x0c37)
hsf_s_exit:
                POP     DS
                RETF
hsf_dither_a:
                MOV     cs:[DAT_0000_0be2], AX
                MOV     BX, BP
                SHR     BX, 1
                ADD     BX, [SI]
                SHR     BX, 1
                JC      SHORT hsf_dither_a_continue
                JMP     hsf_dither_b                    ; (0x0dd3)
hsf_dither_a_continue:
                LODSW
                MOV     BX, AX
                LODSW
                SUB     AX, BX
                JGE     SHORT hsf_a_have_count
                JMP     hsf_a_next
hsf_a_have_count:
                INC     AX
                MOV     CX, AX
                MOV     DI, cs:[DAT_0000_0be4]
                MOV     DI, [BP + DI]
                MOV     AX, cs:[DAT_0000_0be0]
                MOV     cs:[DAT_0000_0bdc], AX
                MOV     AX, BX
                SHR     AX, 1
                SHR     AX, 1
                SHR     AX, 1
                ADD     DI, AX
                AND     BX, 7
                MOV     DX, BX
                ADD     DX, CX
                CMP     DX, 8
                JGE     SHORT hsf_a_multi
                MOV     CX, cs:[DAT_0000_0bdc]
                MOV     AH, cs:[BX + offset g_abHegLeftMaskLut2]
                MOV     BL, DL
                AND     AH, cs:[BX + offset g_abHegRightMaskLut2]
                MOV     BL, AH
                AND     AH, 0AAH
                MOV     AL, 8
                MOV     DX, 3CEH
                OUT     DX, AX
                INC     DX
                MOV     AL, ES:[DI]
                MOV     ES:[DI], CL
                MOV     AL, BL
                AND     AL, 55H
                OUT     DX, AL
                MOV     AL, ES:[DI]
                MOV     AL, CH
                STOSB
                JMP     hsf_a_next
hsf_a_multi:
                MOV     DX, 8
                SUB     DX, BX
                SUB     CX, DX
                MOV     AH, cs:[BX + offset g_abHegLeftMaskLut2]
                MOV     DX, 3CEH
                MOV     AL, 8
                OUT     DX, AL
                INC     DX
                MOV     BX, cs:[DAT_0000_0bdc]
                MOV     AL, ES:[DI]
                MOV     AL, AH
                AND     AL, 0AAH
                OUT     DX, AL
                MOV     ES:[DI], BL
                MOV     AL, ES:[DI]
                MOV     AL, AH
                AND     AL, 55H
                OUT     DX, AL
                MOV     AL, BH
                STOSB
                MOV     AH, CL
                SHR     CX, 1
                SHR     CX, 1
                SHR     CX, 1
                JZ      SHORT hsf_a_tail
                MOV     AL, 0AAH
                OUT     DX, AL
                MOV     ES:[DI], BL
                SHR     AL, 1
                OUT     DX, AL
                MOV     AL, ES:[DI]
                MOV     AL, BH
                MOV     DH, AH
                MOV     AH, AL
                SHR     CX, 1
                REP STOSW
                MOV     AH, DH
                MOV     DH, 3
                JNC     SHORT hsf_a_tail
                STOSB
hsf_a_tail:
                MOV     CL, AH
                XCHG    CX, BX
                AND     BX, 7
                JZ      SHORT hsf_a_next
                MOV     AH, cs:[BX + offset g_abHegRightMaskLut2]
                MOV     AL, AH
                AND     AL, 0AAH
                OUT     DX, AL
                MOV     AL, ES:[DI]
                MOV     ES:[DI], CL
                MOV     AL, AH
                AND     AL, 55H
                OUT     DX, AL
                MOV     AL, ES:[DI]
                MOV     ES:[DI], CH
hsf_a_next:
                SUB     word ptr cs:[DAT_0000_0bde], 1
                JG      SHORT hsf_a_continue
                POP     DS
                RETF
hsf_a_continue:
                ADD     BP, 2
hsf_dither_b:
                LODSW
                MOV     BX, AX
                LODSW
                SUB     AX, BX
                JGE     SHORT hsf_b_have_count
                JMP     hsf_b_next
hsf_b_have_count:
                INC     AX
                MOV     CX, AX
                MOV     DI, cs:[DAT_0000_0be4]
                MOV     DI, [BP + DI]
                MOV     AX, cs:[DAT_0000_0be2]
                MOV     cs:[DAT_0000_0bdc], AX
                MOV     AX, BX
                SHR     AX, 1
                SHR     AX, 1
                SHR     AX, 1
                ADD     DI, AX
                AND     BX, 7
                MOV     DX, BX
                ADD     DX, CX
                CMP     DX, 8
                JGE     SHORT hsf_b_multi
                MOV     CX, cs:[DAT_0000_0bdc]
                MOV     AH, cs:[BX + offset g_abHegLeftMaskLut2]
                MOV     BL, DL
                AND     AH, cs:[BX + offset g_abHegRightMaskLut2]
                MOV     BL, AH
                AND     AH, 0AAH
                MOV     AL, 8
                MOV     DX, 3CEH
                OUT     DX, AX
                INC     DX
                MOV     AL, ES:[DI]
                MOV     ES:[DI], CL
                MOV     AL, BL
                AND     AL, 55H
                OUT     DX, AL
                MOV     AL, ES:[DI]
                MOV     AL, CH
                STOSB
                JMP     hsf_b_next
hsf_b_multi:
                MOV     DX, 8
                SUB     DX, BX
                SUB     CX, DX
                MOV     AH, cs:[BX + offset g_abHegLeftMaskLut2]
                MOV     DX, 3CEH
                MOV     AL, 8
                OUT     DX, AL
                INC     DX
                MOV     BX, cs:[DAT_0000_0bdc]
                MOV     AL, ES:[DI]
                MOV     AL, AH
                AND     AL, 0AAH
                OUT     DX, AL
                MOV     ES:[DI], BL
                MOV     AL, ES:[DI]
                MOV     AL, AH
                AND     AL, 55H
                OUT     DX, AL
                MOV     AL, BH
                STOSB
                MOV     AH, CL
                SHR     CX, 1
                SHR     CX, 1
                SHR     CX, 1
                JZ      SHORT hsf_b_tail
                MOV     AL, 0AAH
                OUT     DX, AL
                MOV     ES:[DI], BL
                SHR     AL, 1
                OUT     DX, AL
                MOV     AL, ES:[DI]
                MOV     AL, BH
                MOV     DH, AH
                MOV     AH, AL
                SHR     CX, 1
                REP STOSW
                MOV     AH, DH
                MOV     DH, 3
                JNC     SHORT hsf_b_tail
                STOSB
hsf_b_tail:
                MOV     CL, AH
                XCHG    CX, BX
                AND     BX, 7
                JZ      SHORT hsf_b_next
                MOV     AH, cs:[BX + offset g_abHegRightMaskLut2]
                MOV     AL, AH
                AND     AL, 0AAH
                OUT     DX, AL
                MOV     AL, ES:[DI]
                MOV     ES:[DI], CL
                MOV     AL, AH
                AND     AL, 55H
                OUT     DX, AL
                MOV     AL, ES:[DI]
                MOV     ES:[DI], CH
hsf_b_next:
                SUB     word ptr cs:[DAT_0000_0bde], 1
                JLE     SHORT hsf_b_exit
                ADD     BP, 2
                JMP     hsf_dither_a_continue           ; (0x0cea -- A-pattern entry)
hsf_b_exit:
                POP     DS
                RETF
heg_span_fill ENDP

; ----------------------------------------------------------------------------
; 2-byte zero pad at 0x0EBF..0x0EC0 (likely segment alignment between
; the pixel core and the palette helper).
; ----------------------------------------------------------------------------
                DB      0, 0

; ============================================================================
; heg_load_palette -- write a range of DAC palette entries.
; chunk:0x0EC1..0x0EFD
;
; ABI (__cdecl16far):
;   [BP+6]   ushort  src_palette_off (DS:SI input)
;   [BP+8]   ushort  start_dac_index
;   [BP+0xA] ushort  entry_count
;
; PALETTE PATH (this function is VGA-only in effect):
;
;   On VGA, the 256-entry DAC LUT lives behind ports 0x3C7/0x3C8/0x3C9:
;   write the entry number to 0x3C8 (PEL write index), then send R, G, B
;   (6 bits each, padded into bytes) consecutively to 0x3C9. The DAC
;   auto-increments the index after every third byte. The 4-bit
;   framebuffer pixel value is mapped to a DAC index through the AR
;   palette + optional AR14 paging; heg_reset_attribute_palette has
;   already configured the AR for identity, so DAC slot N is the
;   colour for framebuffer value N.
;
;   On EGA, there IS no DAC -- the AR's 6-bit output goes straight to
;   the monitor. Writes to 0x3C9 on EGA hardware go nowhere; the
;   function appears to succeed but has no visible effect. The game
;   gets away with this because (a) on the EGA hi-res 0x15E path, only
;   16 colours are available anyway and the AR was set to identity,
;   so the game uses only the 16 hardware colours; and (b) games
;   targeting the EGA hi-res mode usually don't try to recolor
;   sub-palettes mid-game.
;
; ALGORITHM:
;   - Multiply count by 3 to get the byte count for the LODSB/OUT loop
;     (3 bytes per entry: R, G, B).
;   - Wait for vertical-blank rising edge via the 0x3DA bit-3 polling
;     loop (vsync active = bit 3 high; bit 3 low = display active).
;     Writing the DAC during display active produces visible "snow";
;     waiting for vblank avoids it.
;   - PEL-state quirk handling: see hlp_skip_quirk below.
;   - Write the PEL write index to 0x3C8, then run the RGB-output loop
;     with interrupts off (CLI). The CLI is needed because the DAC's
;     auto-increment counter is at 0x3C9; an IRQ that itself wrote to
;     the DAC would corrupt the index. STI on exit.
; ============================================================================
heg_load_palette PROC FAR
                PUSH    BP
                MOV     BP, SP
                PUSH    SI
                PUSH    DI
                MOV     SI, [BP + 6]
                MOV     CX, [BP + 0AH]
                MOV     AX, CX
                SHL     CX, 1
                ADD     CX, AX                          ; CX *= 3
                MOV     BX, [BP + 8]
                MOV     DX, 3DAH
hlp_vsync_wait:
                IN      AL, DX
                AND     AL, 8
                JZ      SHORT hlp_vsync_wait
                ; --- DAC-state-machine recovery ---
                ; Port 0x3C7 is the DAC State Register on read (per
                ; IBM VGA TR p.41). Bits 0..1 = 11b means "the last
                ; DAC operation was a WRITE" -- meaning the DAC's
                ; internal 3-byte (R/G/B) auto-increment counter is
                ; somewhere in the middle of a triple (it advances
                ; mod 3). If we read 11b, the DAC is mid-triple and
                ; we MUST NOT send a stray byte to 0x3C9 here -- it
                ; would land in the wrong R/G/B slot of an in-flight
                ; entry. If we read anything else (00 = idle, 01 =
                ; reading), it's safe to emit one byte to 0x3C9 to
                ; resynchronise the internal counter to "start of
                ; triple" before our index write below.
                MOV     DX, 3C7H
                IN      AL, DX                          ; read DAC state register
                AND     AL, 3
                CMP     AL, 3                           ; 11b = mid-write -> skip resync
                JZ      SHORT hlp_skip_quirk
                MOV     DX, 3C9H
                OUT     DX, AL                          ; resync DAC triple counter
hlp_skip_quirk:
                MOV     DX, 3C8H
                MOV     AX, BX
                OUT     DX, AL                          ; PEL write index
                MOV     DX, 3C9H
                CLI
hlp_emit_loop:
                LODSB
                OUT     DX, AL
                LOOP    hlp_emit_loop
                STI
                POP     DI
                POP     SI
                POP     BP
                RETF
heg_load_palette ENDP

; ============================================================================
; heg_set_palette_entry -- write a single RGB triple to one DAC slot.
; chunk:0x0EFE..0x0F14
;
; ABI (__cdecl16far):
;   [BP+6]   uchar  red
;   [BP+8]   uchar  green   (with red, green, blue at [BP+6..8])
;   [BP+0xA] ushort dac_index
;
; Just forwards to heg_load_palette with count=1 by pushing
; (SI=&[BP+6], BX=dac_index, AX=1) on the stack and calling.
; ============================================================================
heg_set_palette_entry PROC FAR
                PUSH    BP
                MOV     BP, SP
                PUSH    SI
                MOV     BX, [BP + 0AH]
                LEA     SI, [BP + 6]
                MOV     AX, 1
                PUSH    AX
                PUSH    BX
                PUSH    SI
                PUSH    CS
                CALL    NEAR PTR heg_load_palette       ; fake far-call: PUSH CS + near CALL
                POP     SI
                POP     BP
                RETF
heg_set_palette_entry ENDP

; ============================================================================
; heg_install_palette -- install a 48-byte palette and mirror it to backbuf.
; chunk:0x0F15..0x0F56
;
; ABI (__cdecl16far):
;   [BP+6]   ushort  pal_off  (palette source offset in DS)
;   [BP+8]   ushort  pal_seg  (palette source segment)
;
; Loads ES:DI from scratch DS:[0x19E/0x1A0] (palette mirror dst),
; sources from [BP+8]:[BP+6]. If pal_seg is nonzero, calls
; heg_load_palette(start=0, count=0x10) then copies 0x18 words
; (48 bytes) to backbuffer mirror twice (the two-buffer scheme).
;
; Note that heg_install_palette only touches the DAC path (via
; heg_load_palette). It does NOT reprogram the attribute-controller
; palette -- that was set to identity by heg_reset_attribute_palette
; once at init and stays there. The setup is: AR maps framebuffer
; nibble N to DAC index N (identity); the DAC at index N holds the
; final RGB triple. Game palette changes therefore only have to
; rewrite the 16 DAC entries.
; ============================================================================
heg_install_palette PROC FAR
                PUSH    BP
                MOV     BP, SP
                PUSH    DI
                PUSH    SI
                PUSH    DS
                MOV     DS, cs:[g_wHegChunkDataSeg]
                MOV     DI, ds:[GfxContext.pPaletteScratchBuf]     ; far-ptr off half
                MOV     ES, ds:[GfxContext.pPaletteScratchBuf + 2] ; far-ptr seg half
                MOV     SI, [BP + 6]
                MOV     AX, [BP + 8]
                MOV     DS, AX
                OR      AX, AX
                JZ      SHORT hip_exit
                MOV     AX, 10H
                PUSH    AX
                XOR     AX, AX
                PUSH    AX
                PUSH    SI
                PUSH    CS
                CALL    NEAR PTR heg_load_palette       ; (target 0x0ec1)
                ADD     SP, 6
                MOV     CX, 18H
                MOV     AX, CX
                REP MOVSW
                SUB     SI, AX
                SUB     SI, AX
                MOV     CX, AX
                REP MOVSW
hip_exit:
                POP     DS
                POP     SI
                POP     DI
                POP     BP
                RETF
heg_install_palette ENDP

; ============================================================================
; heg_palette_blend -- blend two palettes by a 0..63 weight, write to DAC.
; chunk:0x0F57..0x0FD3
;
; ABI (__cdecl16far):
;   [BP+6]   ushort  dst_pal_index
;   [BP+8]   ushort  count
;   [BP+0xA] ushort  src_pal_offset (second palette base)
;   [BP+0xC] uchar   weight (0..63)
;
; For each of 3*count bytes: result = (a*weight + b*(63-weight)) / 63.
; Pushes result onto stack as new RGB triples, then calls
; heg_load_palette to flush them to the DAC. Stack-managed temp.
; ============================================================================
heg_palette_blend PROC FAR
                PUSH    BP
                MOV     BP, SP
                PUSH    DS
                PUSH    DI
                PUSH    SI
                MOV     DS, cs:[g_wHegChunkDataSeg]
                MOV     AX, [BP + 8]
                PUSH    AX                              ; arg3: count for heg_load_palette
                MOV     CX, AX
                SHL     AX, 1
                ADD     CX, AX                          ; CX = 3*count
                MOV     DL, [BP + 0CH]                  ; weight
                MOV     DH, 3FH                         ; weight max
                MOV     DS, ds:[GfxContext.pPaletteScratchBuf + 2] ; palette mirror seg
                MOV     AX, [BP + 6]
                PUSH    AX                              ; arg2: dst_index
                MOV     DI, AX
                SHL     AX, 1
                ADD     DI, AX                          ; DI = dst_index * 3
                PUSH    DI                              ; arg1: src_off (we build temp on stack)
                MOV     SI, DI
                ADD     SI, 30H
                MOV     AX, [BP + 0AH]
                MOV     BP, 30H
                ADD     BP, AX
                SHL     AX, 1
                ADD     BP, AX                          ; BP = 0x30 + src*3
                PUSH    DS
                POP     ES
                XOR     BX, BX
hpb_loop:
                XOR     AH, AH
                LODSB                                   ; AL = palette A byte
                MUL     DL                              ; * weight
                DIV     DH                              ; / 63
                MOV     BH, AL                          ; BH = a*w/63
                MOV     AL, DL
                MOV     DL, DH
                SUB     DL, AL                          ; (63 - weight)
                XOR     AH, AH
                MOV     AL, ds:[BP + 0]                 ; palette B byte
                MUL     DL
                DIV     DH
                ADD     AL, BH                          ; blend
                STOSB
                MOV     AL, DL
                MOV     DL, DH
                SUB     DL, AL                          ; restore weight for next iter
                INC     BP
                INC     BL
                CMP     BL, 3
                JNZ     SHORT hpb_no_wrap
                XOR     BX, BX
                SUB     BP, 3
hpb_no_wrap:
                LOOP    hpb_loop
                PUSH    CS
                CALL    NEAR PTR heg_load_palette
                ADD     SP, 6                           ; pop our 3 saved args
                ADD     SP, CX                          ; pop blended temp
                POP     SI
                POP     DI
                POP     DS
                POP     BP
                RETF
heg_palette_blend ENDP

; ============================================================================
; heg_query_image_set_size -- compute total storage for an image-set archive.
; chunk:0x0FD4..0x1014
;
; ABI: [BP+6] = near ptr to {ushort *} array (image headers), [BP+8] =
; near ptr to output ushort (zero-initialised). Walks the array reading
; size=(width/2)*height as packed planar bytes, accumulates into
; DX:AX, then returns floor(1.25 * total).
; ============================================================================
heg_query_image_set_size PROC FAR
                PUSH    BP
                MOV     BP, SP
                PUSH    SI
                PUSH    DI
                MOV     DI, [BP + 6]
                XOR     BX, BX
                XOR     CX, CX
hqis_loop:
                MOV     SI, [DI]
                OR      SI, SI
                JZ      SHORT hqis_done
                MOV     AX, [SI + 6]
                SHR     AX, 1
                MOV     DX, [SI + 8]
                MUL     DX
                ADD     BX, AX
                ADC     CX, 0
                ADD     DI, 2
                JMP     SHORT hqis_loop
hqis_done:
                MOV     AX, BX
                MOV     DX, CX
                SHR     DX, 1
                RCR     AX, 1
                SHR     DX, 1
                RCR     AX, 1
                ADD     AX, BX
                ADC     DX, CX
                MOV     SI, [BP + 8]
                MOV     word ptr [SI], 0
                POP     DI
                POP     SI
                POP     BP
                RETF
heg_query_image_set_size ENDP

; ============================================================================
; heg_install_image_set -- install a packed image archive into video planes.
; chunk:0x1015..0x10B7
;
; ABI (__cdecl16far):
;   [BP+6]   uint16   header_array (near ptr to {ImageHdr * } table)
;   [BP+8]   uint16   src_off       (current pack offset, mutable)
;   [BP+0xA] uint16   dst_seg
;   [BP+0xC] uint32   total_size    (low at +0xC, high at +0xE)
;
; Calls heg_chunky_to_planar to allocate the planar buffer, then
; per-image loops: chunky_to_planar -> install_image_planes ->
; read_planar_to_buffer, advancing src/dst pointers.
; ============================================================================
heg_install_image_set PROC FAR
                PUSH    BP
                MOV     BP, SP
                PUSH    SI
                PUSH    DI
                MOV     DX, [BP + 0EH]
                MOV     AX, [BP + 0CH]
                SHR     DX, 1
                RCR     AX, 1
                SHR     DX, 1
                RCR     AX, 1
                PUSH    AX
                MOV     AX, 0A6D6H
                PUSH    AX
                XOR     AX, AX
                PUSH    AX
                MOV     AX, [BP + 0AH]
                PUSH    AX
                MOV     AX, [BP + 8]
                PUSH    AX
                PUSH    CS
                CALL    heg_chunky_to_planar            ; intra-seg far-call via PUSH CS + near CALL
                ADD     SP, 0CH
                XOR     DI, DI
                MOV     BX, [BP + 6]
hiis_loop:
                PUSH    BX
                MOV     SI, [BX]
                OR      SI, SI
                JNZ     SHORT hiis_continue
                JMP     SHORT hiis_done
hiis_continue:
                MOV     AX, [SI + 6]
                SHR     AX, 1
                MOV     DX, [SI + 8]
                MUL     DX
                SHR     AX, 1
                SHR     AX, 1
                MOV     BX, AX
                SHL     BX, 1
                SHL     BX, 1
                PUSH    AX
                MOV     AX, [BP + 0AH]
                MOV     [SI], AX
                PUSH    AX
                MOV     AX, [BP + 8]
                MOV     [SI + 2], AX
                PUSH    AX
                ADD     BX, [BP + 8]
                MOV     [SI + 4], BX
                MOV     [BP + 8], BX
                MOV     AX, 0A6D6H
                PUSH    AX
                PUSH    DI
                PUSH    CS
                CALL    heg_install_image_planes        ; intra-seg far-call via PUSH CS + near CALL
                ADD     SP, 8
                MOV     AX, [BP + 8]
                PUSH    AX
                MOV     AX, 0A6D6H
                PUSH    AX
                PUSH    DI
                PUSH    CS
                CALL    heg_read_planar_to_buffer       ; intra-seg far-call via PUSH CS + near CALL
                ADD     SP, 0AH
                POP     AX
                ADD     DI, AX
                ADD     AX, [BP + 8]
                MOV     DX, AX
                SHR     DX, 1
                SHR     DX, 1
                SHR     DX, 1
                SHR     DX, 1
                ADD     [BP + 0AH], DX
                AND     AX, 0FH
                MOV     [BP + 8], AX
                POP     BX
                ADD     BX, 2
                JMP     SHORT hiis_loop
hiis_done:
                POP     ES
                POP     DI
                POP     SI
                POP     BP
                RETF
heg_install_image_set ENDP

; ============================================================================
; heg_chunky_to_planar -- transpose chunky image bytes into 4 EGA planes.
; chunk:0x10B8..0x11BA
;
; NEAR-callable (final RET near). Programs GC for WRITE MODE 0
; (note: the prologue writes GC idx 5 := 2 first, then overwrites it
; with GC idx 5 := 0 two instructions later -- looks like an
; unintentional double-program, the final state is write mode 0).
; Sets GC bit-mask to 0xFF (all pixels selected). Then for each
; iteration loads 2 source bytes (chunky 4bpp; each byte encoding 2
; pixels with high nibble = even pixel, low nibble = odd pixel),
; splays the 16 pixels across the 4 planes using SHL/RCL into
; BL/BH/CL/CH, and writes them to the planar destination via SC idx 2
; (map-mask) plane select.
;
; Chunky-to-planar transpose idiom: for each chunky pixel (a 4-bit
; nibble), SHL AL,1 sends the high bit of AL into CF, then four RCL
; instructions rotate CF into BH (bit 0), CL (bit 1), BL (bit 2),
; CH (bit 3) -- one bit-plane register per pixel-plane. After 8
; iterations of the 8-instr sequence, the 4 plane registers each hold
; 8 horizontal pixels' worth of one plane's bits. Repeating for AH
; gives the other 8 pixels into the same 4 registers, packing all 16
; pixels into 4 bytes (one per plane).
; ============================================================================
heg_chunky_to_planar PROC NEAR
                PUSH    BP
                MOV     BP, SP
                PUSH    SI
                PUSH    DI
                PUSH    DS
                MOV     AX, 0205H
                MOV     DX, 3CEH
                OUT     DX, AX                          ; GC idx 5 := 2 (write mode 2 -- overwritten 2 lines below)
                MOV     AX, 0FF08H
                OUT     DX, AX                          ; GC idx 8 := 0xFF (bit mask, all pixels selected)
                MOV     AX, 5
                MOV     DX, 3CEH
                OUT     DX, AX                          ; GC idx 5 := 0 (write mode 0; read mode 0 also forced)
                MOV     DI, [BP + 0AH]
                MOV     AX, [BP + 0CH]
                MOV     ES, AX
                MOV     SI, [BP + 6]
                MOV     AX, [BP + 8]
                MOV     BP, [BP + 0EH]
                MOV     DS, AX
                MOV     DX, 3C4H
                MOV     AX, 0102H
                OUT     DX, AX                          ; SEQ idx 2 := 1 (plane 0)
hctp_loop:
                LODSW
                SHL     AL, 1
                RCL     CH, 1
                SHL     AL, 1
                RCL     CL, 1
                SHL     AL, 1
                RCL     BH, 1
                SHL     AL, 1
                RCL     BL, 1
                SHL     AL, 1
                RCL     CH, 1
                SHL     AL, 1
                RCL     CL, 1
                SHL     AL, 1
                RCL     BH, 1
                SHL     AL, 1
                RCL     BL, 1
                MOV     AL, AH
                SHL     AL, 1
                RCL     CH, 1
                SHL     AL, 1
                RCL     CL, 1
                SHL     AL, 1
                RCL     BH, 1
                SHL     AL, 1
                RCL     BL, 1
                SHL     AL, 1
                RCL     CH, 1
                SHL     AL, 1
                RCL     CL, 1
                SHL     AL, 1
                RCL     BH, 1
                SHL     AL, 1
                RCL     BL, 1
                XOR     DX, DX
                MOV     AX, [SI]
                ADD     SI, 2
                RCL     DH, 1
                SHL     DH, 1
                SHL     DH, 1
                SHL     DH, 1
                SHL     DH, 1
                SHL     AL, 1
                RCL     CH, 1
                SHL     AL, 1
                RCL     CL, 1
                SHL     AL, 1
                RCL     BH, 1
                SHL     AL, 1
                RCL     BL, 1
                SHL     AL, 1
                RCL     CH, 1
                SHL     AL, 1
                RCL     CL, 1
                SHL     AL, 1
                RCL     BH, 1
                SHL     AL, 1
                RCL     BL, 1
                MOV     AL, AH
                SHL     AL, 1
                RCL     CH, 1
                SHL     AL, 1
                RCL     CL, 1
                SHL     AL, 1
                RCL     BH, 1
                SHL     AL, 1
                RCL     BL, 1
                SHL     AL, 1
                RCL     CH, 1
                SHL     AL, 1
                RCL     CL, 1
                SHL     AL, 1
                RCL     BH, 1
                SHL     AL, 1
                RCL     BL, 1
                MOV     AX, DS
                ADD     AX, DX
                MOV     DS, AX
                MOV     DX, 3C5H
                MOV     AL, 1
                OUT     DX, AL                          ; plane 0
                MOV     ES:[DI], BL
                SHL     AL, 1
                OUT     DX, AL                          ; plane 1
                MOV     ES:[DI], BH
                SHL     AL, 1
                OUT     DX, AL                          ; plane 2
                MOV     ES:[DI], CL
                SHL     AL, 1
                OUT     DX, AL                          ; plane 3
                MOV     ES:[DI], CH
                INC     DI
                DEC     BP
                JZ      SHORT hctp_done
                JMP     hctp_loop                       ; NEAR (0x10ea)
hctp_done:
                MOV     AX, 0205H
                MOV     DX, 3CEH
                OUT     DX, AX
                MOV     AX, 0F02H
                MOV     DX, 3C4H
                OUT     DX, AX
                POP     DS
                POP     DI
                POP     SI
                POP     BP
                RET                                     ; NEAR
heg_chunky_to_planar ENDP

; ============================================================================
; heg_install_image_planes -- copy 4 planes of raw bytes into framebuffer.
; chunk:0x11BB..0x11ED
;
; NEAR-callable.
;
; ABI: [BP+6/8] src far ptr, [BP+0xA/0xC] dst far ptr, [BP+0xE] byte count.
; Programs GC idx 4 with plane select (0,1,2,3), REP MOVSBs the same
; source bytes once per plane.
; ============================================================================
heg_install_image_planes PROC NEAR
                PUSH    BP
                MOV     BP, SP
                PUSH    SI
                PUSH    DI
                PUSH    DS
                MOV     DI, [BP + 0AH]
                MOV     AX, [BP + 0CH]
                MOV     ES, AX
                MOV     SI, [BP + 6]
                MOV     AX, [BP + 8]
                MOV     DS, AX
                MOV     BX, [BP + 0EH]
                MOV     AX, 4
                MOV     BP, 4
                MOV     DX, 3CEH
hiip_loop:
                OUT     DX, AX
                MOV     CX, BX
                PUSH    SI
                REP MOVSB
                POP     SI
                INC     AH                              ; next plane select
                DEC     BP
                JNZ     SHORT hiip_loop
                POP     DS
                POP     DI
                POP     SI
                POP     BP
                RET
heg_install_image_planes ENDP

; ============================================================================
; heg_read_planar_to_buffer -- read 4 planes through GC into a mask byte.
; chunk:0x11EE..0x1230
;
; NEAR-callable.
;
; For each output byte: reads framebuffer byte from each of the 4
; planes (via GC idx 4 / read map select), OR's them into AH, then
; stores NOT(AH) -- producing a transparency/coverage mask byte.
; ============================================================================
heg_read_planar_to_buffer PROC NEAR
                PUSH    BP
                MOV     BP, SP
                PUSH    SI
                PUSH    DI
                PUSH    DS
                MOV     DI, [BP + 0AH]
                MOV     AX, [BP + 0CH]
                MOV     ES, AX
                MOV     SI, [BP + 6]
                MOV     AX, [BP + 8]
                MOV     DS, AX
                MOV     BP, [BP + 0EH]
                MOV     DX, 3CEH
                MOV     AX, 4
                OUT     DX, AX                          ; GC idx 4
                INC     DX
hrpb_loop:
                XOR     AL, AL
                OUT     DX, AL                          ; read map = plane 0
                MOV     AH, [SI]
                INC     AL
                OUT     DX, AL                          ; plane 1
                OR      AH, [SI]
                INC     AL
                OUT     DX, AL                          ; plane 2
                OR      AH, [SI]
                INC     AL
                OUT     DX, AL                          ; plane 3
                OR      AH, [SI]
                MOV     AL, AH
                NOT     AL
                STOSB
                INC     SI
                DEC     BP
                JNZ     SHORT hrpb_loop
                POP     DS
                POP     DI
                POP     SI
                POP     BP
                RET
heg_read_planar_to_buffer ENDP

; ============================================================================
; heg_blit_sprite_noflip -- vtable slot 3 wrapper for sprite blit.
; chunk:0x1231..0x124A
;
; Thin __cdecl16far wrapper. Re-pushes its 3 stack args (desc, dst_x,
; dst_y) plus a fourth zero word (`flags=0` = no flip), then far-calls
; heg_blit_sprite_master. This is the path the engine uses for any
; sprite drawn in its source-orientation; flipping callers go through
; heg_blit_sprite_master directly with non-zero flags.
;
; The `MOV BP, SP` between `ADD SP, 8` and `POP BP` looks superfluous
; (SP is already where we want it) -- a Borland C-compiler tic when
; restoring after a __cdecl call.
; ============================================================================
heg_blit_sprite_noflip PROC FAR
                PUSH    BP
                MOV     BP, SP
                XOR     AX, AX                          ; flags = 0
                PUSH    AX
                PUSH    word ptr [BP + 0AH]
                PUSH    word ptr [BP + 8]
                PUSH    word ptr [BP + 6]
                PUSH    CS
                CALL    NEAR PTR heg_blit_sprite_master ; intra-seg far-call: caller PUSHes CS, callee RETFs
                ADD     SP, 8
                MOV     BP, SP
                POP     BP
                RETF
heg_blit_sprite_noflip ENDP

; ============================================================================
; heg_glyph_row_blit -- planar 8x8 glyph row blit (write mode 2 / mask LUT).
; chunk:0x124B..0x12F8 (plus DAT_0000_12f9/12fa storage cells)
;
; Register ABI helper. Reads scratch DS:[0x0..0x2] for {colour, bg, mode},
; stores them in CS:[0x12F9/0x12FA] dual-use cells. Two cores:
;   - direct: when mode (AH) != 0 (zero-bg drawing, single byte/glyph row)
;   - masked: when mode == 0 (writes two adjacent bytes per row, both
;             foreground and background, shifted by CL bits)
; ============================================================================
heg_glyph_row_blit PROC FAR
                PUSH    SI
                PUSH    BP
                PUSH    DS
                MOV     DI, AX
                PUSH    ES
                MOV     DS, cs:[g_wHegChunkDataSeg]
                MOV     ES, ds:[GfxContext.wGfxBlitDstPage]
                MOV     AL, ds:[GfxContext.bText_fg_color]
                MOV     cs:[DAT_0000_12f9], AL
                MOV     AH, ds:[GfxContext.bText_bg_color]
                MOV     cs:[DAT_0000_12fa], AH
                SHL     BP, 1
                MOV     DI, ds:[BP].GfxContext.pRow_offset_lut  ; scanline LUT
                MOV     AX, DX
                SHR     AX, 1
                SHR     AX, 1
                SHR     AX, 1
                ADD     DI, AX
                MOV     BX, CX
                MOV     CX, DX
                AND     CX, 7
                MOV     AH, ds:[GfxContext.bText_style_flags]  ; mode (0 = masked)
                POP     DS
                MOV     DX, 3CEH
                MOV     AL, 8
                OUT     DX, AL
                INC     DX
                MOV     CH, cs:[DAT_0000_12f9]
                OR      AH, AH
                JZ      SHORT hgrb_masked
                ; ---- direct core (single byte/glyph row) ----
hgrb_direct_loop:
                LODSB
                XOR     AH, AH
                ROR     AX, CL
                OUT     DX, AL
                MOV     AL, ES:[DI]                     ; latch
                MOV     AL, CH
                STOSB
                MOV     AL, AH
                OUT     DX, AL
                MOV     AL, ES:[DI]
                MOV     AL, CH
                STOSB
                ADD     DI, 04EH
                DEC     BX
                JNZ     SHORT hgrb_direct_loop
                POP     DS
                POP     BP
                POP     SI
                RETF
hgrb_masked:
                MOV     BP, BX
hgrb_masked_loop:
                MOV     AL, ES:[DI]                     ; latch (per-iter)
                LODSB
                XOR     BX, BX
                DEC     BL                              ; BL = 0xFF
                XOR     AH, AH
                ROR     AX, CL
                ROR     BX, CL
                XCHG    AL, BL
                OUT     DX, AL
                MOV     AL, cs:[DAT_0000_12fa]
                MOV     ES:[DI], AL
                XCHG    AL, BL
                OUT     DX, AL
                MOV     AL, ES:[DI]
                MOV     AL, CH
                STOSB
                MOV     AL, ES:[DI]
                MOV     AL, BH
                OUT     DX, AL
                MOV     AL, cs:[DAT_0000_12fa]
                MOV     ES:[DI], AL
                MOV     AL, AH
                OUT     DX, AL
                MOV     AL, ES:[DI]
                MOV     AL, CH
                STOSB
                ADD     DI, 04EH
                DEC     BP
                JNZ     SHORT hgrb_masked_loop
                POP     DS
                POP     BP
                POP     SI
                RETF
heg_glyph_row_blit ENDP

; ----------------------------------------------------------------------------
; Dual-use storage at 0x12F9/0x12FA -- 2 bytes embedded in chunk body
; that heg_glyph_row_blit caches the input colour and mode bytes in.
; ----------------------------------------------------------------------------
DAT_0000_12f9   DB      0                               ; cached foreground colour
DAT_0000_12fa   DB      0                               ; cached background colour

; ============================================================================
; heg_glyph_blit_wrapper -- rectangle copy via planar latched MOVSW.
; chunk:0x12FB..0x138D
;
; Stack-frame __cdecl16far. Programs GC for read mode 0 + write mode 0
; (idx 5 := 0; idx 8 := 0xFF; idx 0 := 0), computes dest segment +
; offset from [BP+6..8], source from [BP+0xC..0xE]+scanline LUT,
; count=[BP+0xA] and rows=[BP+0x10]. Per plane (4 iterations): set GC
; idx 4 := plane_number (read-plane select cycles 3..0); REP MOVSW
; rows*count words. Restores write mode 2 (chunk default) on exit.
;
; Note: this function programs GC idx 4 (read plane) per iteration but
; does NOT program SC idx 2 (map mask) -- the map mask is left at the
; chunk's default of 0x0F (all planes). With write mode 0 + map mask
; 0x0F, the CPU's byte data is replicated across all 4 planes, which
; is unusual for a plane-by-plane copy. The intended semantics are
; unclear without runtime trace -- documenting only what the bytes do.
; ============================================================================
heg_glyph_blit_wrapper PROC FAR
                PUSH    BP
                MOV     BP, SP
                PUSH    SI
                PUSH    DI
                PUSH    DS
                PUSH    ES
                MOV     DS, cs:[g_wHegChunkDataSeg]
                MOV     DX, 3CEH
                MOV     AX, 5
                OUT     DX, AX                          ; GC idx 5 := 0 (write mode 0)
                MOV     AX, 0FF08H
                OUT     DX, AX                          ; idx 8 := 0xFF
                XOR     AX, AX
                OUT     DX, AX                          ; idx 0 := 0
                MOV     AX, [BP + 6]
                MOV     DI, AX
                SHR     AX, 1
                SHR     AX, 1
                SHR     AX, 1
                SHR     AX, 1
                AND     DI, 0FH
                ADD     AX, [BP + 8]
                MOV     ES, AX
                MOV     CX, [BP + 0AH]
                MOV     AX, CX
                SHR     CX, 1
                SHR     CX, 1
                SHR     CX, 1
                MOV     BX, [BP + 0EH]
                ADD     BX, AX
                SHR     BX, 1
                SHR     BX, 1
                SHR     BX, 1
                SUB     BX, CX
                INC     BX
                MOV     AX, BX
                SHR     BX, 1
                AND     AX, 1
                JZ      SHORT hgbw_even
                INC     BX
hgbw_even:
                MOV     DX, [BP + 10H]
                MOV     SI, [BP + 0CH]
                SHL     SI, 1
                MOV     SI, [SI].GfxContext.pRow_offset_lut
                ADD     SI, CX
                MOV     AX, ds:[GfxContext.wGfxBlitSrcPage]
                MOV     DS, AX
                MOV     AX, 0304H
hgbw_plane_loop:
                MOV     BP, DX
                MOV     DX, 3CEH
                OUT     DX, AX
                MOV     DX, BP
                PUSH    DX
                PUSH    SI
hgbw_row_loop:
                MOV     CX, BX
                MOV     BP, SI
                REP MOVSW
                MOV     SI, BP
                ADD     SI, 50H
                DEC     DX
                JNZ     SHORT hgbw_row_loop
                POP     SI
                POP     DX
                DEC     AH
                JGE     SHORT hgbw_plane_loop
                MOV     DX, 3CEH
                MOV     AX, 0205H
                OUT     DX, AX                          ; restore write mode 2
                POP     ES
                POP     DS
                POP     DI
                POP     SI
                POP     BP
                RETF
heg_glyph_blit_wrapper ENDP

; ============================================================================
; heg_query_sprite_buf_size -- compute storage bytes for a sprite of WxH.
; chunk:0x138E..0x13B8
;
; ABI: [BP+6] = width, [BP+8] = height. Returns DX:AX = (((W/8)+pad)
; rounded up to 2) * H * 4.
; ============================================================================
heg_query_sprite_buf_size PROC FAR
                PUSH    BP
                MOV     BP, SP
                MOV     AX, [BP + 6]
                MOV     BX, AX
                SHR     BX, 1
                SHR     BX, 1
                SHR     BX, 1
                INC     BX
                AND     AX, 7
                JZ      SHORT hqsbs_no_rem
                INC     BX
hqsbs_no_rem:
                TEST    BX, 1
                JZ      SHORT hqsbs_even
                INC     BX
hqsbs_even:
                MOV     AX, [BP + 8]
                MUL     BX
                SHL     AX, 1
                RCL     DX, 1
                SHL     AX, 1
                RCL     DX, 1
                POP     BP
                RETF
heg_query_sprite_buf_size ENDP

; ============================================================================
; heg_blit_chunky_to_video -- planar rect copy via SEQ map-mask shifting.
; chunk:0x13B9..0x1452
;
; Per-plane (4 planes selected via SEQ map-mask 0x0802 with right shift),
; REP MOVSW row-by-row. The plane-select runs in SHR AH,1; JNC loop:
; AH starts at 0x08 then 0x04 then 0x02 then 0x01.
; ============================================================================
heg_blit_chunky_to_video PROC FAR
                PUSH    BP
                MOV     BP, SP
                PUSH    SI
                PUSH    DI
                PUSH    DS
                PUSH    ES
                MOV     DX, 3CEH
                MOV     AX, 5
                OUT     DX, AX
                MOV     AX, 0FF08H
                OUT     DX, AX
                XOR     AX, AX
                OUT     DX, AX
                MOV     AX, [BP + 6]
                MOV     SI, AX
                SHR     AX, 1
                SHR     AX, 1
                SHR     AX, 1
                SHR     AX, 1
                AND     SI, 0FH
                ADD     AX, [BP + 8]
                PUSH    AX
                MOV     CX, [BP + 0AH]
                MOV     AX, CX
                SHR     CX, 1
                SHR     CX, 1
                SHR     CX, 1
                MOV     BX, [BP + 0EH]
                ADD     BX, AX
                SHR     BX, 1
                SHR     BX, 1
                SHR     BX, 1
                SUB     BX, CX
                INC     BX
                MOV     AX, BX
                SHR     BX, 1
                AND     AX, 1
                JZ      SHORT hbcv_even
                INC     BX
hbcv_even:
                MOV     DS, cs:[g_wHegChunkDataSeg]
                MOV     DX, [BP + 10H]
                MOV     DI, [BP + 0CH]
                SHL     DI, 1
                MOV     DI, [DI].GfxContext.pRow_offset_lut
                ADD     DI, CX
                MOV     AX, ds:[GfxContext.wGfxBlitDstPage]
                MOV     ES, AX
                POP     DS
                MOV     AX, 0802H
hbcv_plane_loop:
                MOV     BP, DX
                MOV     DX, 3C4H
                OUT     DX, AX
                MOV     DX, BP
                PUSH    DX
                PUSH    DI
hbcv_row_loop:
                MOV     CX, BX
                MOV     BP, DI
                REP MOVSW
                MOV     DI, BP
                ADD     DI, 50H
                DEC     DX
                JNZ     SHORT hbcv_row_loop
                POP     DI
                POP     DX
                SHR     AH, 1
                JNC     SHORT hbcv_plane_loop
                MOV     DX, 3CEH
                MOV     AX, 0205H
                OUT     DX, AX
                MOV     DX, 3C4H
                MOV     AX, 0F02H
                OUT     DX, AX
                POP     ES
                POP     DS
                POP     DI
                POP     SI
                POP     BP
                RETF
heg_blit_chunky_to_video ENDP

; ============================================================================
; heg_getpixel -- read a single pixel from the planar framebuffer.
; chunk:0x1453..0x14C8
;
; ABI: [BP+6] = x, [BP+8] = y. Returns AX = packed colour 0..15.
;
; Uses GC READ MODE 0 (plane-select; the default after init): cycles
; GC idx 4 (read map select) through plane 0..3, dummy-reads ES:[BX]
; after each idx-4 write, and tests the per-pixel bit (mask AH = 0x80
; >> (x mod 8)) against the byte that was returned. Concatenates the
; four 1-bit results into the low nibble of CL -> AX.
;
; Note: the prologue writes GC idx 5 := 0x01. That sets write mode 1
; (irrelevant -- this function never writes VRAM) and read mode 0
; (the mode we need). The epilogue resets GC idx 5 := 0x02 (write
; mode 2, the chunk default; read mode still 0).
; ============================================================================
heg_getpixel PROC FAR
                PUSH    BP
                MOV     BP, SP
                PUSH    DS
                MOV     DS, cs:[g_wHegChunkDataSeg]
                MOV     AX, ds:[GfxContext.wGfxBlitSrcPage]
                MOV     ES, AX
                MOV     BX, [BP + 8]
                SHL     BX, 1
                MOV     BX, [BX].GfxContext.pRow_offset_lut
                MOV     AX, [BP + 6]
                MOV     CX, AX
                SHR     AX, 1
                SHR     AX, 1
                SHR     AX, 1
                ADD     BX, AX
                MOV     DX, 3CEH
                MOV     AX, 0105H
                OUT     DX, AX                          ; GC idx 5 := 0x01 (write mode 1; read mode unchanged at 0)
                MOV     AX, 4
                OUT     DX, AX                          ; GC idx 4 prep
                INC     DX
                MOV     AH, 80H
                AND     CL, 7
                SHR     AH, CL
                XOR     CX, CX
                MOV     AL, ES:[BX]                     ; plane 0
                TEST    AH, AL
                JZ      SHORT hgp_p1
                OR      CL, 1
hgp_p1:
                MOV     AL, 1
                OUT     DX, AL
                MOV     AL, ES:[BX]
                TEST    AH, AL
                JZ      SHORT hgp_p2
                OR      CL, 2
hgp_p2:
                MOV     AL, 2
                OUT     DX, AL
                MOV     AL, ES:[BX]
                TEST    AH, AL
                JZ      SHORT hgp_p3
                OR      CL, 4
hgp_p3:
                MOV     AL, 3
                OUT     DX, AL
                MOV     AL, ES:[BX]
                TEST    AH, AL
                JZ      SHORT hgp_done
                OR      CL, 8
hgp_done:
                DEC     DX
                MOV     AX, 0205H
                OUT     DX, AX                          ; GC idx 5 := 0x02 (write mode 2, the chunk default; read mode 0)
                MOV     AX, CX
                POP     DS
                MOV     SP, BP
                POP     BP
                RETF
heg_getpixel ENDP

; ============================================================================
; heg_putpixel -- write a single pixel via planar write mode 2.
; chunk:0x14C9..0x150E
;
; ABI: [BP+6] = x, [BP+8] = y, [BP+0xA] = colour.
;
; Programs GC idx 8 := 0x80 >> (x mod 8) (single-pixel bit mask),
; then GC idx 5 := 0x02 (write mode 2 + read mode 0 -- both nibbles
; of the AX value matter: low byte 0x05 selects GC idx 5, high byte
; 0x02 = WM2/RM0). Does a dummy latch-load (MOV AL, ES:[BX]) to
; populate the GC's 4-byte latch with the existing pixel data, then
; writes the new colour byte: in WM2 the low 4 bits of the CPU data
; become the colour for each pixel selected by the bit mask, with
; the latch supplying everything else. Restores GC idx 8 := 0xFF
; (all-pixels mask, the chunk's default) on exit.
; ============================================================================
heg_putpixel PROC FAR
                PUSH    BP
                MOV     BP, SP
                PUSH    DS
                MOV     DS, cs:[g_wHegChunkDataSeg]
                MOV     ES, ds:[GfxContext.wGfxBlitDstPage]
                MOV     BX, [BP + 8]
                SHL     BX, 1
                MOV     BX, [BX].GfxContext.pRow_offset_lut
                MOV     AX, [BP + 6]
                MOV     CX, AX
                SHR     AX, 1
                SHR     AX, 1
                SHR     AX, 1
                ADD     BX, AX
                AND     CX, 7
                MOV     AH, 80H
                SHR     AH, CL
                MOV     DX, 3CEH
                MOV     AL, 8
                OUT     DX, AX
                MOV     AX, 0205H
                OUT     DX, AX
                MOV     AL, ES:[BX]
                MOV     AL, [BP + 0AH]
                MOV     ES:[BX], AL
                MOV     AX, 0FF08H
                OUT     DX, AX
                POP     DS
                MOV     SP, BP
                POP     BP
                RETF
heg_putpixel ENDP

; ============================================================================
; heg_page_flip_present -- swap front/back buffer offsets and tell CRTC.
; chunk:0x150F..0x1560
;
; XCHGs DS:[0x12] (back) with DS:[0x14] (front), then programs CRTC
; index 0x0C (start address hi) via the active CRTC port from BIOS
; data area at 0x40:[0x63]. If mode is 0x190 (640x400 visible),
; subtracts 0xF from the high byte (CRTC viewport tweak).
; ============================================================================
heg_page_flip_present PROC FAR
                PUSH    BP
                MOV     BP, SP
                PUSH    ES
                PUSH    DS
                MOV     DS, cs:[g_wHegChunkDataSeg]
                MOV     AX, ds:[GfxContext.wVgaPage2Base]
                MOV     CX, AX
                XCHG    ds:[GfxContext.wVgaFrontPageBase], AX  ; swap front/back
                MOV     ds:[GfxContext.wVgaPage2Base], AX
                SHR     CX, 1
                SHR     CX, 1
                SHR     CX, 1
                SHR     CX, 1                           ; CX = paragraph-shifted base
                CMP     word ptr ds:[GfxContext.wScreen_height], 0190H
                JNZ     SHORT hpfp_no_tweak
                SUB     CX, 0FH
hpfp_no_tweak:
                MOV     AX, 40H
                MOV     ES, AX
                MOV     DX, ES:[63H]                    ; BIOS CRTC port (0x3D4)
                MOV     AL, 0CH                         ; CRTC idx 12 (start hi)
                MOV     AH, CL
                OUT     DX, AX
                MOV     AX, [BP + 6]                    ; vsync arg
                OR      AX, AX
                JZ      SHORT hpfp_exit
                MOV     CL, 8
                MOV     DX, 3DAH
hpfp_vsync_active:
                IN      AL, DX
                AND     AL, CL
                JNZ     SHORT hpfp_vsync_active
hpfp_vsync_blank:
                IN      AL, DX
                AND     AL, CL
                JZ      SHORT hpfp_vsync_blank
hpfp_exit:
                POP     DS
                POP     ES
                POP     BP
                RETF
heg_page_flip_present ENDP

; ============================================================================
; heg_present_rect -- copy a rectangle from back-buffer to front-buffer.
; chunk:0x1561..0x15C9
;
; ABI: [BP+6] = x_start, [BP+8] = y_start, [BP+0xA] = width,
;      [BP+0xC] = height.
;
; Uses GC WRITE MODE 1 (latch-copy): a read from VRAM loads all 4 plane
; bytes at the source address into the GC's 4-byte latch; a subsequent
; write to VRAM copies those latches into all 4 planes at the destination
; address, regardless of what CPU data was passed. With write mode 1,
; one REP MOVSB through a video-to-video span moves a planar bitmap row
; with all 4 planes intact. Restores write mode 2 (the chunk's default)
; on exit.
; ============================================================================
heg_present_rect PROC FAR
                PUSH    BP
                MOV     BP, SP
                PUSH    SI
                PUSH    DI
                PUSH    DS
                PUSH    ES
                MOV     DS, cs:[g_wHegChunkDataSeg]
                MOV     DX, 3CEH
                MOV     AX, 0105H
                OUT     DX, AX                          ; GC idx 5 := 0x01 = write mode 1 (latch copy)
                MOV     BX, [BP + 0AH]
                MOV     AX, [BP + 6]
                ADD     BX, AX
                ADD     BX, 7
                AND     BX, 0FFF8H                      ; round end up
                AND     AX, 0FFF8H                      ; round start down
                SUB     BX, AX
                SHR     BX, 1
                SHR     BX, 1
                SHR     BX, 1
                SHR     AX, 1
                SHR     AX, 1
                SHR     AX, 1
                MOV     SI, AX
                MOV     DX, [BP + 0CH]
                MOV     DI, [BP + 8]
                SHL     DI, 1
                MOV     DI, [DI].GfxContext.pRow_offset_lut
                ADD     DI, SI
                MOV     AX, ds:[GfxContext.wGfxBlitDstPage]
                MOV     ES, AX                          ; ES = front buffer
                MOV     AX, ds:[GfxContext.wGfxBlitSrcPage]
                MOV     DS, AX                          ; DS = back buffer
hprr_row_loop:
                MOV     CX, BX
                MOV     BP, DI
                MOV     SI, DI
                REP MOVSB
                MOV     DI, BP
                ADD     DI, 50H
                DEC     DX
                JNZ     SHORT hprr_row_loop
                MOV     DX, 3CEH
                MOV     AX, 0205H
                OUT     DX, AX                          ; GC idx 5 := 0x02 = restore write mode 2 (data-as-colour)
                POP     ES
                POP     DS
                POP     DI
                POP     SI
                POP     BP
                RETF
heg_present_rect ENDP

; ----------------------------------------------------------------------------
; Scratch globals at 0x15CA..0x15CF -- 3 words (zero-initialised on disk).
; Used by heg_chunky_blit_alt as per-call cached args.
; ----------------------------------------------------------------------------
DAT_0000_15ca   DW      0
DAT_0000_15cc   DW      0
DAT_0000_15ce   DW      0

; ============================================================================
; heg_chunky_blit_alt -- alternate chunky-to-planar rectangle blit.
; chunk:0x15D0..0x1706
;
; Uses SEQ map-mask 0x02 (single-plane writes) and transposes 16
; chunky pixels per iteration into BL/BH/CL/CH plane bytes, then
; writes 4 plane bytes to ES:[DI] cycling map-mask 1->2->4->8.
; Loop count in BP / row stride at CS:[0x15CC] / line counter at
; CS:[0x15CE]; column count saved at CS:[0x15CA].
; ============================================================================
heg_chunky_blit_alt PROC FAR
                PUSH    BP
                MOV     BP, SP
                PUSH    SI
                PUSH    DI
                PUSH    DS
                MOV     DX, 3CEH
                MOV     AX, 5
                OUT     DX, AX
                MOV     AX, 0FF08H
                OUT     DX, AX
                MOV     DX, 3C4H
                MOV     AL, 2
                OUT     DX, AL                          ; SEQ idx 2 prep
                INC     DX                              ; DX = 0x3C5 (SEQ data)
                MOV     DS, cs:[g_wHegChunkDataSeg]
                MOV     BX, [BP + 0CH]
                SHL     BX, 1
                MOV     DI, [BX].GfxContext.pRow_offset_lut
                MOV     AX, [BP + 0AH]
                SHR     AX, 1
                SHR     AX, 1
                SHR     AX, 1
                ADD     DI, AX
                MOV     AX, ds:[GfxContext.wGfxBlitDstPage]
                MOV     ES, AX
                MOV     AX, [BP + 10H]
                MOV     cs:[DAT_0000_15ce], AX
                MOV     AX, [BP + 6]
                MOV     SI, AX
                SHR     AX, 1
                SHR     AX, 1
                SHR     AX, 1
                SHR     AX, 1
                AND     SI, 0FH
                ADD     AX, [BP + 8]
                MOV     DS, AX
                MOV     AX, [BP + 0EH]
                SHR     AX, 1
                SHR     AX, 1
                SHR     AX, 1
                MOV     cs:[DAT_0000_15ca], AX
                MOV     BP, AX
                SUB     AX, 50H
                NEG     AX
                MOV     cs:[DAT_0000_15cc], AX
hcba_col_loop:
                LODSW
                SHL     AL, 1
                RCL     CH, 1
                SHL     AL, 1
                RCL     CL, 1
                SHL     AL, 1
                RCL     BH, 1
                SHL     AL, 1
                RCL     BL, 1
                SHL     AL, 1
                RCL     CH, 1
                SHL     AL, 1
                RCL     CL, 1
                SHL     AL, 1
                RCL     BH, 1
                SHL     AL, 1
                RCL     BL, 1
                SHL     AH, 1
                RCL     CH, 1
                SHL     AH, 1
                RCL     CL, 1
                SHL     AH, 1
                RCL     BH, 1
                SHL     AH, 1
                RCL     BL, 1
                SHL     AH, 1
                RCL     CH, 1
                SHL     AH, 1
                RCL     CL, 1
                SHL     AH, 1
                RCL     BH, 1
                SHL     AH, 1
                RCL     BL, 1
                LODSW
                SHL     AL, 1
                RCL     CH, 1
                SHL     AL, 1
                RCL     CL, 1
                SHL     AL, 1
                RCL     BH, 1
                SHL     AL, 1
                RCL     BL, 1
                SHL     AL, 1
                RCL     CH, 1
                SHL     AL, 1
                RCL     CL, 1
                SHL     AL, 1
                RCL     BH, 1
                SHL     AL, 1
                RCL     BL, 1
                SHL     AH, 1
                RCL     CH, 1
                SHL     AH, 1
                RCL     CL, 1
                SHL     AH, 1
                RCL     BH, 1
                SHL     AH, 1
                RCL     BL, 1
                SHL     AH, 1
                RCL     CH, 1
                SHL     AH, 1
                RCL     CL, 1
                SHL     AH, 1
                RCL     BH, 1
                SHL     AH, 1
                RCL     BL, 1
                MOV     AL, 1
                OUT     DX, AL
                MOV     ES:[DI], BL
                SHL     AL, 1
                OUT     DX, AL
                MOV     ES:[DI], BH
                SHL     AL, 1
                OUT     DX, AL
                MOV     ES:[DI], CL
                SHL     AL, 1
                OUT     DX, AL
                MOV     AL, CH
                STOSB
                DEC     BP
                JLE     SHORT hcba_row_step
                JMP     hcba_col_loop
hcba_row_step:
                MOV     AX, cs:[DAT_0000_15ce]
                DEC     AX
                JLE     SHORT hcba_done
                MOV     cs:[DAT_0000_15ce], AX
                MOV     AX, cs:[DAT_0000_15ca]
                MOV     BP, AX
                MOV     AX, cs:[DAT_0000_15cc]
                ADD     DI, AX
                JMP     hcba_col_loop
hcba_done:
                MOV     AL, 0FH
                OUT     DX, AL                          ; restore SEQ map-mask = 0xF
                MOV     AX, 0205H
                MOV     DX, 3CEH
                OUT     DX, AX
                MOV     AX, 3
                OUT     DX, AX
                POP     DS
                POP     DI
                POP     SI
                POP     BP
                RETF
heg_chunky_blit_alt ENDP

; ----------------------------------------------------------------------------
; 1-byte even-align pad + 4-entry sprite-flip dispatch table + scratch.
; chunk:0x1707..0x171F
;
; - 0x1707           : even-align pad (0x00)
; - 0x1708..0x170F   : g_apHegSpriteFlipDispatch (4 word ptrs)
;     [0] -> 0x18FA  heg_sprite_row_noflip   (flags 0: no flip)
;     [1] -> 0x1B71  heg_sprite_row_flipx    (flags 1: VERTICAL flip --
;                                              "flipx" label is misleading)
;     [2] -> 0x1DE8  heg_sprite_row_flipy    (flags 2: HORIZONTAL flip --
;                                              "flipy" label is misleading)
;     [3] -> 0x21CC  heg_sprite_row_flipxy   (flags 3: 180-deg rotation)
; - 0x1710..0x171F   : 16-byte scratch (DAT_0000_1710..1716, then 4 bytes)
; ----------------------------------------------------------------------------
                DB      0                               ; even-align pad
g_apHegSpriteFlipDispatch LABEL WORD
                DW      18FAH, 1B71H, 1DE8H, 21CCH
DAT_0000_1710   DW      0
DAT_0000_1712   DW      0
DAT_0000_1714   DW      0
DAT_0000_1716   DW      0
DAT_0000_1718   DW      0
DAT_0000_171a   DW      0
DAT_0000_171c   DB      0
DAT_0000_171d   DB      0
DAT_0000_171e   DB      0
DAT_0000_171f   DB      0

; ============================================================================
; heg_blit_sprite_master -- master sprite blit dispatcher.
; chunk:0x1720..0x18F9
;
; Dispatches via g_apHegSpriteFlipDispatch[flags] at 0x1708.
;
; Stack frame __cdecl16far. [BP+6]=desc, [BP+8]=dst_x, [BP+0xA]=dst_y,
; [BP+0xC]=flags(0..3). Saves chunk-local globals 0x1710-0x171f on
; stack, copies sprite descriptor into [BP-A..BP-0], applies clip-rect
; from DS:[0..0xA], programs sprite-row params at CS:[0x1710..0x1718],
; then tail-jumps into g_apHegSpriteFlipDispatch[flags*2] via JMP AX.
; ============================================================================
heg_blit_sprite_master PROC FAR
                PUSH    BP
                MOV     BP, SP
                SUB     SP, 0AH
                PUSH    SI
                PUSH    DI
                PUSH    ES
                PUSH    DS
                PUSH    cs:[DAT_0000_1718]
                PUSH    cs:[DAT_0000_171a]
                PUSH    cs:[DAT_0000_1710]
                PUSH    cs:[DAT_0000_1712]
                PUSH    cs:[DAT_0000_1714]
                PUSH    cs:[DAT_0000_1716]
                PUSH    word ptr cs:[DAT_0000_171c]
                PUSH    word ptr cs:[DAT_0000_171e]
                MOV     SI, [BP + 6]
                MOV     DI, BP
                SUB     DI, 0AH
                MOV     AX, DS
                MOV     ES, AX
                MOV     CX, 5
                REP MOVSW
                MOV     DS, cs:[g_wHegChunkDataSeg]
                MOV     AX, ds:[GfxContext.wGfxBlitDstPage]
                MOV     ES, AX
                MOV     AX, [BP - 6]
                SUB     AX, [BP - 8]
                SHR     AX, 1
                SHR     AX, 1
                MOV     cs:[DAT_0000_1712], AX
                MOV     AL, [BP + 0CH]                  ; flags
                MOV     cs:[DAT_0000_171c], AL
                MOV     BX, [BP + 0AH]
                SHL     BX, 1
                JNS     SHORT hbsm_y_pos
                SAR     BX, 1
                SHL     BX, 1
                SHL     BX, 1
                SHL     BX, 1
                SHL     BX, 1
                MOV     DI, BX
                SHL     BX, 1
                SHL     BX, 1
                ADD     DI, BX
                JMP     SHORT hbsm_after_y
hbsm_y_pos:
                MOV     DI, [BX].GfxContext.pRow_offset_lut
hbsm_after_y:
                MOV     AX, [BP + 8]
                MOV     CL, AL
                SAR     AX, 1
                SAR     AX, 1
                SAR     AX, 1
                ADD     DI, AX
                AND     CL, 7
                MOV     AX, [BP - 4]
                MOV     DX, AX
                SHR     AX, 1
                SHR     AX, 1
                SHR     AX, 1
                MOV     cs:[DAT_0000_1710], AX
                ADD     DX, 7
                SHR     DX, 1
                SHR     DX, 1
                SHR     DX, 1
                MOV     DH, DL
                MOV     AX, [BP - 2]
                MOV     cs:[DAT_0000_1718], AX
                MOV     AX, [BP - 0AH]
                MOV     cs:[DAT_0000_1714], AX
                MOV     SI, [BP - 8]
                MOV     AX, [BP - 6]
                MOV     cs:[DAT_0000_1716], AX
                XOR     AX, AX
                MOV     cs:[DAT_0000_171d], AL
                MOV     cs:[DAT_0000_171e], AL
                TEST    byte ptr cs:[DAT_0000_171c], 1
                JZ      SHORT hbsm_no_vflip
                PUSH    DX
                MOV     AX, cs:[DAT_0000_1718]
                DEC     AX
                XOR     DX, DX
                MUL     word ptr cs:[DAT_0000_1710]
                ADD     SI, AX
                ADD     cs:[DAT_0000_1716], AX
                POP     DX
hbsm_no_vflip:
                TEST    byte ptr cs:[DAT_0000_171c], 2
                JZ      SHORT hbsm_no_hflip
                MOV     AX, cs:[DAT_0000_1710]
                DEC     AX
                ADD     SI, AX
                ADD     cs:[DAT_0000_1716], AX
hbsm_no_hflip:
                MOV     AL, ds:[GfxContext.bClip_enabled]      ; clip-rect enable
                OR      AL, AL
                JNZ     SHORT hbsm_do_clip
                JMP     hbsm_dispatch                   ; NEAR
hbsm_do_clip:
                ; --- check sprite against clip-right (max x) ---
                MOV     AX, ds:[GfxContext.nClip_xmax]         ; clip-right (max x)
                INC     AX
                MOV     BX, [BP + 8]                    ; dst_x
                ADD     BX, [BP - 4]                    ; + sprite width
                SUB     AX, BX                          ; spare px on the right
                JG      SHORT hbsm_check_left           ; fully inside -- no right clip
                NEG     AX
                CMP     AX, [BP - 4]
                JL      SHORT hbsm_right_clip
                JMP     heg_blit_sprite_epilogue        ; fully off-screen
hbsm_right_clip:
                SHR     AX, 1
                SHR     AX, 1
                SHR     AX, 1                           ; px overflow / 8 = bytes
                SUB     DH, AL                          ; shrink per-row width
                MOV     byte ptr cs:[DAT_0000_171d], 1  ; flag right-clip active
hbsm_check_left:
                ; --- check sprite against clip-left (min x) ---
                MOV     AX, [BP + 8]                    ; dst_x
                SUB     AX, ds:[GfxContext.nClip_xmin]         ; - clip-left
                JNS     SHORT hbsm_check_right          ; dst_x >= left edge: no left clip
                MOV     BX, AX
                ADD     AX, [BP - 4]
                JG      SHORT hbsm_left_clip
                JMP     heg_blit_sprite_epilogue        ; fully left of clip-rect
hbsm_left_clip:
                MOV     byte ptr cs:[DAT_0000_171e], 1  ; flag left-clip active
                NEG     BX
                ADD     BX, 7
                SHR     BX, 1
                SHR     BX, 1
                SHR     BX, 1                           ; (-overflow+7)/8 = bytes to skip
                SUB     DH, BL
                ADD     DI, BX
                TEST    byte ptr cs:[DAT_0000_171c], 2  ; H-flip flag set?
                JZ      SHORT hbsm_neg_done
                NEG     BX                              ; H-flip walks SI backwards
hbsm_neg_done:
                ADD     SI, BX
                ADD     cs:[DAT_0000_1716], BX
hbsm_check_right:
                ; --- check sprite against clip-bottom (max y) ---
                MOV     AX, [BP + 0AH]                  ; dst_y
                ADD     AX, [BP - 2]                    ; + sprite height
                SUB     AX, ds:[GfxContext.nClip_ymax]         ; - clip-bottom
                JLE     SHORT hbsm_check_top            ; entirely above clip-bottom
                CMP     AX, [BP - 2]
                JS      SHORT hbsm_bottom_clip
                JMP     heg_blit_sprite_epilogue        ; entirely below clip-bottom
hbsm_bottom_clip:
                DEC     AX
                SUB     cs:[DAT_0000_1718], AX          ; shrink row count
hbsm_check_top:
                ; --- check sprite against clip-top (min y) ---
                MOV     AX, ds:[GfxContext.nClip_ymin]         ; clip-top
                SUB     AX, [BP + 0AH]                  ; - dst_y
                JS      SHORT hbsm_dispatch             ; dst_y >= top: no top clip
                CMP     AX, [BP - 2]
                JS      SHORT hbsm_top_chop
                JMP     heg_blit_sprite_epilogue        ; entirely above clip-top
hbsm_top_chop:
                SUB     cs:[DAT_0000_1718], AX
                MOV     BX, AX
                SHL     AX, 1
                SHL     AX, 1
                SHL     AX, 1
                SHL     AX, 1
                ADD     DI, AX
                SHL     AX, 1
                SHL     AX, 1
                ADD     DI, AX
                MOV     AX, BX
                MUL     byte ptr cs:[DAT_0000_1710]
                TEST    byte ptr cs:[DAT_0000_171c], 1
                JZ      SHORT hbsm_no_neg2
                NEG     AX
hbsm_no_neg2:
                ADD     SI, AX
                ADD     cs:[DAT_0000_1716], AX
hbsm_dispatch:
                MOV     BL, cs:[DAT_0000_171c]
                XOR     BH, BH
                SHL     BX, 1
                MOV     AX, cs:[BX + offset g_apHegSpriteFlipDispatch]
                MOV     DS, cs:[DAT_0000_1714]
                MOV     BP, cs:[DAT_0000_1716]
                JMP     AX
heg_blit_sprite_master ENDP

; ============================================================================
; The four sprite-row blit cores (0x18FA..0x25AC)
;
; Sprites in HEG are drawn through one of four 5-plane-pass cores selected
; from g_apHegSpriteFlipDispatch[flags] (see chunk:0x1708). The flag bits
; (passed in as the low byte of [BP+0xC]) are:
;
;   bit 0 (mask 1) -- vertical flip (mirror top<->bottom)
;   bit 1 (mask 2) -- horizontal flip (mirror left<->right)
;
; NAMING CAVEAT: the labels `heg_sprite_row_flipx` and
; `heg_sprite_row_flipy` are MISLEADING -- they encode the wrong axis
; relative to the dispatch index. Cross-checking the dispatch table at
; 0x1708 with the master's flag-bit handling at heg_blit_sprite_master
; (TEST cs:[..171c], 1 = vflip; TEST cs:[..171c], 2 = hflip) shows:
;
;   flags=1 (vflip set)         -> dispatch[1] = 0x1B71 = "flipx" (sic)
;   flags=2 (hflip set)         -> dispatch[2] = 0x1DE8 = "flipy" (sic)
;   flags=3 (vflip + hflip set) -> dispatch[3] = 0x21CC = flipxy
;
; The functions also exhibit the matching behaviour: "flipx" subtracts the
; row stride each pass (walks rows bottom-to-top -> vertical mirror), and
; "flipy" bit-reverses each source byte and walks SI backward within a row
; (-> horizontal mirror). The labels are kept as-is; this banner uses the
; names by their actual semantics.
;
; The four resulting cores are:
;
;   noflip  (flags=0)  -- forward source walk, forward bit order.
;   flipx   (flags=1)  -- per-pass ROW-stride advance is SUB instead of ADD,
;                         i.e. the per-row cursor walks UP through the
;                         source row by row. Net effect: VERTICAL mirror
;                         (top<->bottom). The byte order WITHIN a row and
;                         the bit order WITHIN a byte are both forward,
;                         identical to noflip.
;   flipy   (flags=2)  -- per-pass row-stride advance is ADD (forward), BUT
;                         within each row the source pointer walks BACKWARD
;                         byte-by-byte (`MOV AL, [SI]; DEC SI`) AND each
;                         source byte is BIT-REVERSED inline (unrolled
;                         SHR AL,1 / RCL r,1 x8). The LHS partial-byte
;                         fetch uses `[SI+1]` instead of `[SI-1]` (a
;                         consequence of the backward walk). Net effect:
;                         HORIZONTAL mirror (left<->right).
;   flipxy  (flags=3)  -- combines flipx's SUB row-stride with flipy's
;                         backward-byte-walk + bit-reverse: 180-degree
;                         rotation.
;
; Each core consists of FIVE near-identical passes:
;
;   pass 1 : program GC idx 8 (bit mask) for sequencer write-mode 2 paint.
;            Walks every row of the sprite and writes 0x00 bytes (clears
;            destination under the sprite footprint) using GC index 8 as
;            a transparency mask read from the source. This step latches
;            the destination, ANDs with the inverted source mask, and
;            writes back -- effectively the "transparency cutout" pass.
;   passes 2..5 : one per EGA plane. GC idx 4 (read map select) +
;                 SC idx 2 (write map mask) cycle through plane 0..3
;                 (0x01, 0x02, 0x04, 0x08 for the SC, paired with GC
;                 read map 1,2,3,3 read in pass 2..5). Each pass shifts
;                 the per-byte sprite-pixel mask through CL bits, OR's
;                 in any source bits, and writes the byte through the
;                 EGA latch.
;
; All four cores share an identical control-flow skeleton and the same
; CS-relative scratch state at chunk:0x1710..0x171F (set up by
; heg_blit_sprite_master). The differences between the four cores are
; LOCALISED to:
;
;   - per-pass row-stride direction (`ADD SI, ...` vs `SUB SI, ...`)
;   - per-byte bit-reverse presence (Y-flip cores only)
;   - tail jump to heg_blit_sprite_epilogue at chunk:0x25AD (flipxy
;     falls through; the other three encode an explicit JMP).
;
; This pattern -- four byte-shuffled clones of a 5-pass core sharing a
; common epilogue at 0x25AD -- is the same one used by the other planar
; drivers in the OVL (EGA, EVG, MCG, VGA). The original C source almost
; certainly used a single template function with #define toggles or
; preprocessor switches; the linker emitted 4 separate copies.
; ============================================================================

; ============================================================================
; heg_sprite_row_noflip -- sprite-row blit core, no flip, 5 plane passes.
; chunk:0x18FA..0x1B70 (631 bytes)
;
; Reference core. The other three (flipx, flipy, flipxy) are described
; relative to this one -- their plate comments only call out the byte
; differences.
;
; Per-pass control flow (single pass):
;   - PUSH/save framebuffer DI and source SI.
;   - For each of BH rows of the sprite footprint:
;       * if left-clip flag set (CS:[DAT_0000_171e]) and we're at row start:
;           fetch LHS partial byte from [SI - 1], invert (NOT AH).
;       * LODSB the next source byte, NOT AL, rotate (AH:AL) right by CL.
;       * OUT to GC bit-mask (AL) -- masks the planar write to only those
;         pixels covered by the sprite.
;       * MOV AL, ES:[DI]  -- latch read.
;       * MOV ES:[DI], <colour>  -- planar write (latch+mask -> framebuffer).
;       * advance DI within the row by 1 byte.
;   - At end of row: ADD SI, cs:[DAT_0000_1710]  (forward stride)
;                    ADD DI, 50H                 (next scanline)
; ============================================================================
heg_sprite_row_noflip PROC FAR
                PUSH    SI
                PUSH    DI
                PUSH    DX
                PUSH    DI
                MOV     BH, DH
                MOV     AX, cs:[DAT_0000_1718]
                MOV     cs:[DAT_0000_171a], AX
                MOV     DX, 3CEH
                MOV     AL, 8
                OUT     DX, AL
                INC     DX
                MOV     SI, BP
                PUSH    SI
hsrn_p1_outer:
                MOV     CH, BH
                XOR     AH, AH
                TEST    byte ptr cs:[DAT_0000_171e], 1
                JZ      SHORT hsrn_p1_no_lhs
                MOV     AH, [SI - 1]
                NOT     AH
                OR      CH, CH
                JZ      SHORT hsrn_p1_tail
hsrn_p1_no_lhs:
                LODSB
                NOT     AL
                ROR     AX, CL
                OUT     DX, AL
                MOV     AL, ES:[DI]
                XOR     AL, AL
                STOSB
                MOV     AL, 8
                SUB     CL, AL
                NEG     CL
                SHR     AH, CL
                SUB     CL, AL
                NEG     CL
                DEC     CH
                JNZ     SHORT hsrn_p1_no_lhs
                TEST    byte ptr cs:[DAT_0000_171d], 1
                JNZ     SHORT hsrn_p1_done
hsrn_p1_tail:
                XOR     AL, AL
                ROR     AX, CL
                OUT     DX, AL
                MOV     AL, ES:[DI]
                XOR     AL, AL
                STOSB
hsrn_p1_done:
                POP     SI
                POP     DI
                ADD     SI, cs:[DAT_0000_1710]
                ADD     DI, 50H
                PUSH    DI
                PUSH    SI
                DEC     word ptr cs:[DAT_0000_171a]
                JNZ     SHORT hsrn_p1_outer
                XOR     AL, AL
                MOV     AL, 0FFH
                OUT     DX, AL
                ADD     SP, 2
                POP     DI
                POP     DX
                POP     DI
                POP     SI
                ; ---- pass 2 ----
                PUSH    DX
                MOV     DX, 3CEH
                MOV     AX, 5
                OUT     DX, AX
                MOV     AX, 1003H
                OUT     DX, AX
                POP     DX
                PUSH    SI
                PUSH    DI
                PUSH    DX
                MOV     DX, 3CEH
                MOV     AX, 4
                OUT     DX, AX
                MOV     DX, 3C4H
                MOV     AX, 0102H
                OUT     DX, AX
                POP     DX
                PUSH    DX
                PUSH    DI
                MOV     BX, cs:[DAT_0000_1718]
                MOV     BP, BX
                MOV     BH, DH
                MOV     DH, CL
                SUB     CL, 8
                NEG     CL
                MOV     BL, CL
                PUSH    SI
hsrn_p2_outer:
                MOV     CH, BH
                XOR     AH, AH
                TEST    byte ptr cs:[DAT_0000_171e], 1
                JZ      SHORT hsrn_p2_inner
                MOV     AH, [SI - 1]
                OR      CH, CH
                JZ      SHORT hsrn_p2_tail
hsrn_p2_inner:
                MOV     CL, DH
                LODSB
                ROR     AX, CL
                MOV     DL, ES:[DI]
                STOSB
                MOV     CL, BL
                SHR     AH, CL
                DEC     CH
                JNZ     SHORT hsrn_p2_inner
                TEST    byte ptr cs:[DAT_0000_171d], 1
                JNZ     SHORT hsrn_p2_done
hsrn_p2_tail:
                MOV     CL, DH
                XOR     AL, AL
                ROR     AX, CL
                MOV     AH, ES:[DI]
                STOSB
                MOV     CL, BL
hsrn_p2_done:
                POP     SI
                POP     DI
                ADD     SI, cs:[DAT_0000_1710]
                ADD     DI, 50H
                PUSH    DI
                PUSH    SI
                DEC     BP
                JNZ     SHORT hsrn_p2_outer
                MOV     CL, DH
                ADD     SP, 2
                POP     DI
                POP     DX
                POP     DI
                POP     SI
                ADD     SI, cs:[DAT_0000_1712]
                ; ---- pass 3 ----
                PUSH    SI
                PUSH    DI
                PUSH    DX
                MOV     DX, 3CEH
                MOV     AX, 0104H
                OUT     DX, AX
                MOV     DX, 3C4H
                MOV     AX, 0202H
                OUT     DX, AX
                POP     DX
                PUSH    DX
                PUSH    DI
                MOV     BX, cs:[DAT_0000_1718]
                MOV     BP, BX
                MOV     BH, DH
                MOV     DH, CL
                SUB     CL, 8
                NEG     CL
                MOV     BL, CL
                PUSH    SI
hsrn_p3_outer:
                MOV     CH, BH
                XOR     AH, AH
                TEST    byte ptr cs:[DAT_0000_171e], 1
                JZ      SHORT hsrn_p3_inner
                MOV     AH, [SI - 1]
                OR      CH, CH
                JZ      SHORT hsrn_p3_tail
hsrn_p3_inner:
                MOV     CL, DH
                LODSB
                ROR     AX, CL
                MOV     DL, ES:[DI]
                STOSB
                MOV     CL, BL
                SHR     AH, CL
                DEC     CH
                JNZ     SHORT hsrn_p3_inner
                TEST    byte ptr cs:[DAT_0000_171d], 1
                JNZ     SHORT hsrn_p3_done
hsrn_p3_tail:
                MOV     CL, DH
                XOR     AL, AL
                ROR     AX, CL
                MOV     AH, ES:[DI]
                STOSB
                MOV     CL, BL
hsrn_p3_done:
                POP     SI
                POP     DI
                ADD     SI, cs:[DAT_0000_1710]
                ADD     DI, 50H
                PUSH    DI
                PUSH    SI
                DEC     BP
                JNZ     SHORT hsrn_p3_outer
                MOV     CL, DH
                ADD     SP, 2
                POP     DI
                POP     DX
                POP     DI
                POP     SI
                ADD     SI, cs:[DAT_0000_1712]
                ; ---- pass 4 ----
                PUSH    SI
                PUSH    DI
                PUSH    DX
                MOV     DX, 3CEH
                MOV     AX, 0204H
                OUT     DX, AX
                MOV     DX, 3C4H
                MOV     AX, 0402H
                OUT     DX, AX
                POP     DX
                PUSH    DX
                PUSH    DI
                MOV     BX, cs:[DAT_0000_1718]
                MOV     BP, BX
                MOV     BH, DH
                MOV     DH, CL
                SUB     CL, 8
                NEG     CL
                MOV     BL, CL
                PUSH    SI
hsrn_p4_outer:
                MOV     CH, BH
                XOR     AH, AH
                TEST    byte ptr cs:[DAT_0000_171e], 1
                JZ      SHORT hsrn_p4_inner
                MOV     AH, [SI - 1]
                OR      CH, CH
                JZ      SHORT hsrn_p4_tail
hsrn_p4_inner:
                MOV     CL, DH
                LODSB
                ROR     AX, CL
                MOV     DL, ES:[DI]
                STOSB
                MOV     CL, BL
                SHR     AH, CL
                DEC     CH
                JNZ     SHORT hsrn_p4_inner
                TEST    byte ptr cs:[DAT_0000_171d], 1
                JNZ     SHORT hsrn_p4_done
hsrn_p4_tail:
                MOV     CL, DH
                XOR     AL, AL
                ROR     AX, CL
                MOV     AH, ES:[DI]
                STOSB
                MOV     CL, BL
hsrn_p4_done:
                POP     SI
                POP     DI
                ADD     SI, cs:[DAT_0000_1710]
                ADD     DI, 50H
                PUSH    DI
                PUSH    SI
                DEC     BP
                JNZ     SHORT hsrn_p4_outer
                MOV     CL, DH
                ADD     SP, 2
                POP     DI
                POP     DX
                POP     DI
                POP     SI
                ADD     SI, cs:[DAT_0000_1712]
                ; ---- pass 5 ----
                PUSH    SI
                PUSH    DI
                PUSH    DX
                MOV     DX, 3CEH
                MOV     AX, 0304H
                OUT     DX, AX
                MOV     DX, 3C4H
                MOV     AX, 0802H
                OUT     DX, AX
                POP     DX
                PUSH    DX
                PUSH    DI
                MOV     BX, cs:[DAT_0000_1718]
                MOV     BP, BX
                MOV     BH, DH
                MOV     DH, CL
                SUB     CL, 8
                NEG     CL
                MOV     BL, CL
                PUSH    SI
hsrn_p5_outer:
                MOV     CH, BH
                XOR     AH, AH
                TEST    byte ptr cs:[DAT_0000_171e], 1
                JZ      SHORT hsrn_p5_inner
                MOV     AH, [SI - 1]
                OR      CH, CH
                JZ      SHORT hsrn_p5_tail
hsrn_p5_inner:
                MOV     CL, DH
                LODSB
                ROR     AX, CL
                MOV     DL, ES:[DI]
                STOSB
                MOV     CL, BL
                SHR     AH, CL
                DEC     CH
                JNZ     SHORT hsrn_p5_inner
                TEST    byte ptr cs:[DAT_0000_171d], 1
                JNZ     SHORT hsrn_p5_done
hsrn_p5_tail:
                MOV     CL, DH
                XOR     AL, AL
                ROR     AX, CL
                MOV     AH, ES:[DI]
                STOSB
                MOV     CL, BL
hsrn_p5_done:
                POP     SI
                POP     DI
                ADD     SI, cs:[DAT_0000_1710]
                ADD     DI, 50H
                PUSH    DI
                PUSH    SI
                DEC     BP
                JNZ     SHORT hsrn_p5_outer
                MOV     CL, DH
                ADD     SP, 2
                POP     DI
                POP     DX
                ADD     SP, 4
                JMP     heg_blit_sprite_epilogue
heg_sprite_row_noflip ENDP

; ============================================================================
; heg_sprite_row_flipx -- sprite-row blit core, VERTICAL flip (despite name),
; 5 plane passes. chunk:0x1B71..0x1DE7 (631 bytes).
;
; Reached from dispatch index 1 (flag bit 0 = vflip; see banner before
; heg_sprite_row_noflip and master at heg_blit_sprite_master step
; "TEST cs:[..171c], 1").
;
; The "flipx" label is misleading -- this core actually performs the
; VERTICAL mirror. See the family banner before heg_sprite_row_noflip
; for the rationale. We keep the inherited label to ease cross-
; referencing.
;
; See the family banner before heg_sprite_row_noflip for the shared 5-pass
; scaffolding. Diffs from the reference (noflip) core:
;
;   - Each of the 5 per-pass row-stride advances is `SUB SI, [..1710]`
;     instead of `ADD SI, [..1710]`. DAT_0000_1710 holds the ROW STRIDE
;     in bytes (sprite_width_pixels / 8), set up by master before
;     dispatch. Subtracting it once per row means SI walks UPWARD
;     through the source row-by-row -- reading the bottom row first
;     and the top row last. That is what produces the top<->bottom
;     mirror (a vertical flip). The byte order within a row and the
;     bit order within each byte are both forward, identical to noflip.
;   - The encoded tail jump is `$+07C8H` (target 0x25AD = the shared
;     epilogue), 3 bytes shorter displacement than noflip's `$+0A3FH`.
;     The epilogue is closer because flipx sits at chunk:0x1B71, only
;     ~2.6KB ahead of the epilogue at 0x25AD; noflip at 0x18FA is
;     ~3.3KB ahead. Just a near-jump displacement difference, no
;     semantic change.
;   - The 4 inter-pass `ADD SI, cs:[DAT_0000_1712]` are unchanged --
;     0x1712 holds the full-sprite source advance per pass, which is
;     the same regardless of flip direction.
; ============================================================================
heg_sprite_row_flipx PROC FAR
                PUSH    SI
                PUSH    DI
                PUSH    DX
                PUSH    DI
                MOV     BH, DH
                MOV     AX, cs:[DAT_0000_1718]
                MOV     cs:[DAT_0000_171a], AX
                MOV     DX, 3CEH
                MOV     AL, 8
                OUT     DX, AL
                INC     DX
                MOV     SI, BP
                PUSH    SI
hsrfx_p1_outer:
                MOV     CH, BH
                XOR     AH, AH
                TEST    byte ptr cs:[DAT_0000_171e], 1
                JZ      SHORT hsrfx_p1_no_lhs
                MOV     AH, [SI - 1]
                NOT     AH
                OR      CH, CH
                JZ      SHORT hsrfx_p1_tail
hsrfx_p1_no_lhs:
                LODSB
                NOT     AL
                ROR     AX, CL
                OUT     DX, AL
                MOV     AL, ES:[DI]
                XOR     AL, AL
                STOSB
                MOV     AL, 8
                SUB     CL, AL
                NEG     CL
                SHR     AH, CL
                SUB     CL, AL
                NEG     CL
                DEC     CH
                JNZ     SHORT hsrfx_p1_no_lhs
                TEST    byte ptr cs:[DAT_0000_171d], 1
                JNZ     SHORT hsrfx_p1_done
hsrfx_p1_tail:
                XOR     AL, AL
                ROR     AX, CL
                OUT     DX, AL
                MOV     AL, ES:[DI]
                XOR     AL, AL
                STOSB
hsrfx_p1_done:
                POP     SI
                POP     DI
                SUB     SI, cs:[DAT_0000_1710]                  ; X-flip: row stride SUBTRACTED
                ADD     DI, 50H
                PUSH    DI
                PUSH    SI
                DEC     word ptr cs:[DAT_0000_171a]
                JNZ     SHORT hsrfx_p1_outer
                XOR     AL, AL
                MOV     AL, 0FFH
                OUT     DX, AL
                ADD     SP, 2
                POP     DI
                POP     DX
                POP     DI
                POP     SI
                ; ---- pass 2 ----
                PUSH    DX
                MOV     DX, 3CEH
                MOV     AX, 5
                OUT     DX, AX
                MOV     AX, 1003H
                OUT     DX, AX
                POP     DX
                PUSH    SI
                PUSH    DI
                PUSH    DX
                MOV     DX, 3CEH
                MOV     AX, 4
                OUT     DX, AX
                MOV     DX, 3C4H
                MOV     AX, 0102H
                OUT     DX, AX
                POP     DX
                PUSH    DX
                PUSH    DI
                MOV     BX, cs:[DAT_0000_1718]
                MOV     BP, BX
                MOV     BH, DH
                MOV     DH, CL
                SUB     CL, 8
                NEG     CL
                MOV     BL, CL
                PUSH    SI
hsrfx_p2_outer:
                MOV     CH, BH
                XOR     AH, AH
                TEST    byte ptr cs:[DAT_0000_171e], 1
                JZ      SHORT hsrfx_p2_inner
                MOV     AH, [SI - 1]
                OR      CH, CH
                JZ      SHORT hsrfx_p2_tail
hsrfx_p2_inner:
                MOV     CL, DH
                LODSB
                ROR     AX, CL
                MOV     DL, ES:[DI]
                STOSB
                MOV     CL, BL
                SHR     AH, CL
                DEC     CH
                JNZ     SHORT hsrfx_p2_inner
                TEST    byte ptr cs:[DAT_0000_171d], 1
                JNZ     SHORT hsrfx_p2_done
hsrfx_p2_tail:
                MOV     CL, DH
                XOR     AL, AL
                ROR     AX, CL
                MOV     AH, ES:[DI]
                STOSB
                MOV     CL, BL
hsrfx_p2_done:
                POP     SI
                POP     DI
                SUB     SI, cs:[DAT_0000_1710]                  ; X-flip: row stride SUBTRACTED
                ADD     DI, 50H
                PUSH    DI
                PUSH    SI
                DEC     BP
                JNZ     SHORT hsrfx_p2_outer
                MOV     CL, DH
                ADD     SP, 2
                POP     DI
                POP     DX
                POP     DI
                POP     SI
                ADD     SI, cs:[DAT_0000_1712]
                ; ---- pass 3 ----
                PUSH    SI
                PUSH    DI
                PUSH    DX
                MOV     DX, 3CEH
                MOV     AX, 0104H
                OUT     DX, AX
                MOV     DX, 3C4H
                MOV     AX, 0202H
                OUT     DX, AX
                POP     DX
                PUSH    DX
                PUSH    DI
                MOV     BX, cs:[DAT_0000_1718]
                MOV     BP, BX
                MOV     BH, DH
                MOV     DH, CL
                SUB     CL, 8
                NEG     CL
                MOV     BL, CL
                PUSH    SI
hsrfx_p3_outer:
                MOV     CH, BH
                XOR     AH, AH
                TEST    byte ptr cs:[DAT_0000_171e], 1
                JZ      SHORT hsrfx_p3_inner
                MOV     AH, [SI - 1]
                OR      CH, CH
                JZ      SHORT hsrfx_p3_tail
hsrfx_p3_inner:
                MOV     CL, DH
                LODSB
                ROR     AX, CL
                MOV     DL, ES:[DI]
                STOSB
                MOV     CL, BL
                SHR     AH, CL
                DEC     CH
                JNZ     SHORT hsrfx_p3_inner
                TEST    byte ptr cs:[DAT_0000_171d], 1
                JNZ     SHORT hsrfx_p3_done
hsrfx_p3_tail:
                MOV     CL, DH
                XOR     AL, AL
                ROR     AX, CL
                MOV     AH, ES:[DI]
                STOSB
                MOV     CL, BL
hsrfx_p3_done:
                POP     SI
                POP     DI
                SUB     SI, cs:[DAT_0000_1710]                  ; X-flip: row stride SUBTRACTED
                ADD     DI, 50H
                PUSH    DI
                PUSH    SI
                DEC     BP
                JNZ     SHORT hsrfx_p3_outer
                MOV     CL, DH
                ADD     SP, 2
                POP     DI
                POP     DX
                POP     DI
                POP     SI
                ADD     SI, cs:[DAT_0000_1712]
                ; ---- pass 4 ----
                PUSH    SI
                PUSH    DI
                PUSH    DX
                MOV     DX, 3CEH
                MOV     AX, 0204H
                OUT     DX, AX
                MOV     DX, 3C4H
                MOV     AX, 0402H
                OUT     DX, AX
                POP     DX
                PUSH    DX
                PUSH    DI
                MOV     BX, cs:[DAT_0000_1718]
                MOV     BP, BX
                MOV     BH, DH
                MOV     DH, CL
                SUB     CL, 8
                NEG     CL
                MOV     BL, CL
                PUSH    SI
hsrfx_p4_outer:
                MOV     CH, BH
                XOR     AH, AH
                TEST    byte ptr cs:[DAT_0000_171e], 1
                JZ      SHORT hsrfx_p4_inner
                MOV     AH, [SI - 1]
                OR      CH, CH
                JZ      SHORT hsrfx_p4_tail
hsrfx_p4_inner:
                MOV     CL, DH
                LODSB
                ROR     AX, CL
                MOV     DL, ES:[DI]
                STOSB
                MOV     CL, BL
                SHR     AH, CL
                DEC     CH
                JNZ     SHORT hsrfx_p4_inner
                TEST    byte ptr cs:[DAT_0000_171d], 1
                JNZ     SHORT hsrfx_p4_done
hsrfx_p4_tail:
                MOV     CL, DH
                XOR     AL, AL
                ROR     AX, CL
                MOV     AH, ES:[DI]
                STOSB
                MOV     CL, BL
hsrfx_p4_done:
                POP     SI
                POP     DI
                SUB     SI, cs:[DAT_0000_1710]                  ; X-flip: row stride SUBTRACTED
                ADD     DI, 50H
                PUSH    DI
                PUSH    SI
                DEC     BP
                JNZ     SHORT hsrfx_p4_outer
                MOV     CL, DH
                ADD     SP, 2
                POP     DI
                POP     DX
                POP     DI
                POP     SI
                ADD     SI, cs:[DAT_0000_1712]
                ; ---- pass 5 ----
                PUSH    SI
                PUSH    DI
                PUSH    DX
                MOV     DX, 3CEH
                MOV     AX, 0304H
                OUT     DX, AX
                MOV     DX, 3C4H
                MOV     AX, 0802H
                OUT     DX, AX
                POP     DX
                PUSH    DX
                PUSH    DI
                MOV     BX, cs:[DAT_0000_1718]
                MOV     BP, BX
                MOV     BH, DH
                MOV     DH, CL
                SUB     CL, 8
                NEG     CL
                MOV     BL, CL
                PUSH    SI
hsrfx_p5_outer:
                MOV     CH, BH
                XOR     AH, AH
                TEST    byte ptr cs:[DAT_0000_171e], 1
                JZ      SHORT hsrfx_p5_inner
                MOV     AH, [SI - 1]
                OR      CH, CH
                JZ      SHORT hsrfx_p5_tail
hsrfx_p5_inner:
                MOV     CL, DH
                LODSB
                ROR     AX, CL
                MOV     DL, ES:[DI]
                STOSB
                MOV     CL, BL
                SHR     AH, CL
                DEC     CH
                JNZ     SHORT hsrfx_p5_inner
                TEST    byte ptr cs:[DAT_0000_171d], 1
                JNZ     SHORT hsrfx_p5_done
hsrfx_p5_tail:
                MOV     CL, DH
                XOR     AL, AL
                ROR     AX, CL
                MOV     AH, ES:[DI]
                STOSB
                MOV     CL, BL
hsrfx_p5_done:
                POP     SI
                POP     DI
                SUB     SI, cs:[DAT_0000_1710]                  ; X-flip: row stride SUBTRACTED
                ADD     DI, 50H
                PUSH    DI
                PUSH    SI
                DEC     BP
                JNZ     SHORT hsrfx_p5_outer
                MOV     CL, DH
                ADD     SP, 2
                POP     DI
                POP     DX
                ADD     SP, 4
                JMP     heg_blit_sprite_epilogue
heg_sprite_row_flipx ENDP

; ============================================================================
; heg_sprite_row_flipy -- sprite-row blit core, HORIZONTAL flip (despite name),
; 5 plane passes. chunk:0x1DE8..0x21CB (996 bytes).
;
; Reached from dispatch index 2 (flag bit 1 = hflip; see banner before
; heg_sprite_row_noflip and master at heg_blit_sprite_master step
; "TEST cs:[..171c], 2").
;
; The "flipy" label is misleading -- this core actually performs the
; HORIZONTAL mirror. See the family banner before heg_sprite_row_noflip
; for the rationale. We keep the inherited label to ease cross-
; referencing.
;
; See the family banner before heg_sprite_row_noflip for the shared 5-pass
; scaffolding. Diffs from the reference (noflip) core:
;
;   - Each per-byte source read is BIT-REVERSED inline before being
;     shifted into place and OUT'd. The unrolled reversal is 8x
;     `SHR AL, 1; RCL <r>, 1` -- shifts the low bit of AL out into the
;     carry, then rotates carry into the high end of the destination
;     register. After 8 iterations, AL is empty and the destination
;     holds AL's bits in reversed order. This reverses the 8 pixels
;     packed into a source byte.
;   - Within a row, the source pointer walks BACKWARD byte-by-byte
;     (`MOV AL, [SI]; DEC SI`) rather than forward (`LODSB`). Combined
;     with the per-byte bit-reverse this reverses every pixel in a
;     row: byte ordering across the row is flipped, and the bit order
;     within each byte is flipped, so the row reads left<->right.
;   - The LHS partial-byte fetch (left-clip case) reads from `[SI + 1]`
;     instead of `[SI - 1]` (a consequence of the backward walk).
;   - The PER-PASS (not per-row) row-stride advance at each plane-pass
;     end is still `ADD SI, cs:[DAT_0000_1710]` (FORWARD). The HORIZONTAL
;     mirror is implemented entirely by reading byte-bits in reverse plus
;     walking backward INSIDE a single row; the row-to-row order across
;     passes is unchanged. (Net effect = horizontal mirror, not vertical.)
;
; The outer loop body of each pass is too large for a 2-byte short JNZ
; (>127 bytes after the unrolled bit-reverse expansion), so the loop
; trailer uses `DEC ..; JZ SHORT exit; JMP NEAR outer` (5 + 3 bytes)
; instead of the noflip core's `JNZ SHORT outer` (2 bytes). This is the
; reason heg_sprite_row_flipy is ~365 bytes larger than heg_sprite_row_noflip.
; ============================================================================
heg_sprite_row_flipy PROC FAR
                PUSH    SI
                PUSH    DI
                PUSH    DX
                PUSH    DI
                MOV     BH, DH
                MOV     AX, cs:[DAT_0000_1718]
                MOV     cs:[DAT_0000_171a], AX
                MOV     DX, 3CEH
                MOV     AL, 8
                OUT     DX, AL
                INC     DX
                MOV     SI, BP
                PUSH    SI
hsrfy_p1_outer:
                MOV     CH, BH
                XOR     AH, AH
                TEST    byte ptr cs:[DAT_0000_171e], 1
                JZ      SHORT hsrfy_p1_no_lhs
                MOV     AL, [SI + 1]
                NOT     AL
                SHR     AL, 1                           ; bit-reverse AL into AH (x8)
                RCL     AH, 1
                SHR     AL, 1
                RCL     AH, 1
                SHR     AL, 1
                RCL     AH, 1
                SHR     AL, 1
                RCL     AH, 1
                SHR     AL, 1
                RCL     AH, 1
                SHR     AL, 1
                RCL     AH, 1
                SHR     AL, 1
                RCL     AH, 1
                SHR     AL, 1
                RCL     AH, 1
                MOV     AL, AH
                OR      CH, CH
                JZ      SHORT hsrfy_p1_tail
hsrfy_p1_no_lhs:
                MOV     AL, [SI]
                DEC     SI
                NOT     AL
                SHR     AL, 1                           ; bit-reverse AL into BL (x8)
                RCL     BL, 1
                SHR     AL, 1
                RCL     BL, 1
                SHR     AL, 1
                RCL     BL, 1
                SHR     AL, 1
                RCL     BL, 1
                SHR     AL, 1
                RCL     BL, 1
                SHR     AL, 1
                RCL     BL, 1
                SHR     AL, 1
                RCL     BL, 1
                SHR     AL, 1
                RCL     BL, 1
                MOV     AL, BL
                ROR     AX, CL
                OUT     DX, AL
                MOV     AL, ES:[DI]
                XOR     AL, AL
                STOSB
                MOV     AL, 8
                SUB     CL, AL
                NEG     CL
                SHR     AH, CL
                SUB     CL, AL
                NEG     CL
                DEC     CH
                JNZ     SHORT hsrfy_p1_no_lhs
                TEST    byte ptr cs:[DAT_0000_171d], 1
                JNZ     SHORT hsrfy_p1_done
hsrfy_p1_tail:
                XOR     AL, AL
                ROR     AX, CL
                OUT     DX, AL
                MOV     AL, ES:[DI]
                XOR     AL, AL
                STOSB
hsrfy_p1_done:
                POP     SI
                POP     DI
                ADD     SI, cs:[DAT_0000_1710]
                ADD     DI, 50H
                PUSH    DI
                PUSH    SI
                DEC     word ptr cs:[DAT_0000_171a]
                JZ      SHORT hsrfy_p1_exit
                JMP     hsrfy_p1_outer                  ; near (>127 bytes back)
hsrfy_p1_exit:
                XOR     AL, AL
                MOV     AL, 0FFH
                OUT     DX, AL
                ADD     SP, 2
                POP     DI
                POP     DX
                POP     DI
                POP     SI
                ; ---- pass 2 ----
                PUSH    DX
                MOV     DX, 3CEH
                MOV     AX, 5
                OUT     DX, AX
                MOV     AX, 1003H
                OUT     DX, AX
                POP     DX
                PUSH    SI
                PUSH    DI
                PUSH    DX
                MOV     DX, 3CEH
                MOV     AX, 4
                OUT     DX, AX
                MOV     DX, 3C4H
                MOV     AX, 0102H
                OUT     DX, AX
                POP     DX
                PUSH    DX
                PUSH    DI
                MOV     BX, cs:[DAT_0000_1718]
                MOV     BP, BX
                MOV     BH, DH
                MOV     DH, CL
                SUB     CL, 8
                NEG     CL
                MOV     BL, CL
                PUSH    SI
hsrfy_p2_outer:
                MOV     CH, BH
                XOR     AH, AH
                TEST    byte ptr cs:[DAT_0000_171e], 1
                JZ      SHORT hsrfy_p2_no_lhs
                MOV     AL, [SI + 1]
                SHR     AL, 1
                RCL     AH, 1
                SHR     AL, 1
                RCL     AH, 1
                SHR     AL, 1
                RCL     AH, 1
                SHR     AL, 1
                RCL     AH, 1
                SHR     AL, 1
                RCL     AH, 1
                SHR     AL, 1
                RCL     AH, 1
                SHR     AL, 1
                RCL     AH, 1
                SHR     AL, 1
                RCL     AH, 1
                MOV     AL, AH
                OR      CH, CH
                JZ      SHORT hsrfy_p2_tail
hsrfy_p2_no_lhs:
                MOV     CL, DH
                MOV     AL, [SI]
                DEC     SI
                SHR     AL, 1                           ; bit-reverse AL into DL (x8)
                RCL     DL, 1
                SHR     AL, 1
                RCL     DL, 1
                SHR     AL, 1
                RCL     DL, 1
                SHR     AL, 1
                RCL     DL, 1
                SHR     AL, 1
                RCL     DL, 1
                SHR     AL, 1
                RCL     DL, 1
                SHR     AL, 1
                RCL     DL, 1
                SHR     AL, 1
                RCL     DL, 1
                MOV     AL, DL
                ROR     AX, CL
                MOV     DL, ES:[DI]
                STOSB
                MOV     CL, BL
                SHR     AH, CL
                DEC     CH
                JNZ     SHORT hsrfy_p2_no_lhs
                TEST    byte ptr cs:[DAT_0000_171d], 1
                JNZ     SHORT hsrfy_p2_done
hsrfy_p2_tail:
                MOV     CL, DH
                XOR     AL, AL
                ROR     AX, CL
                MOV     AH, ES:[DI]
                STOSB
                MOV     CL, BL
hsrfy_p2_done:
                POP     SI
                POP     DI
                ADD     SI, cs:[DAT_0000_1710]
                ADD     DI, 50H
                PUSH    DI
                PUSH    SI
                DEC     BP
                JZ      SHORT hsrfy_p2_exit
                JMP     hsrfy_p2_outer
hsrfy_p2_exit:
                MOV     CL, DH
                ADD     SP, 2
                POP     DI
                POP     DX
                POP     DI
                POP     SI
                ADD     SI, cs:[DAT_0000_1712]
                ; ---- pass 3 ----
                PUSH    SI
                PUSH    DI
                PUSH    DX
                MOV     DX, 3CEH
                MOV     AX, 0104H
                OUT     DX, AX
                MOV     DX, 3C4H
                MOV     AX, 0202H
                OUT     DX, AX
                POP     DX
                PUSH    DX
                PUSH    DI
                MOV     BX, cs:[DAT_0000_1718]
                MOV     BP, BX
                MOV     BH, DH
                MOV     DH, CL
                SUB     CL, 8
                NEG     CL
                MOV     BL, CL
                PUSH    SI
hsrfy_p3_outer:
                MOV     CH, BH
                XOR     AH, AH
                TEST    byte ptr cs:[DAT_0000_171e], 1
                JZ      SHORT hsrfy_p3_no_lhs
                MOV     AL, [SI + 1]
                SHR     AL, 1
                RCL     AH, 1
                SHR     AL, 1
                RCL     AH, 1
                SHR     AL, 1
                RCL     AH, 1
                SHR     AL, 1
                RCL     AH, 1
                SHR     AL, 1
                RCL     AH, 1
                SHR     AL, 1
                RCL     AH, 1
                SHR     AL, 1
                RCL     AH, 1
                SHR     AL, 1
                RCL     AH, 1
                MOV     AL, AH
                OR      CH, CH
                JZ      SHORT hsrfy_p3_tail
hsrfy_p3_no_lhs:
                MOV     CL, DH
                MOV     AL, [SI]
                DEC     SI
                SHR     AL, 1
                RCL     DL, 1
                SHR     AL, 1
                RCL     DL, 1
                SHR     AL, 1
                RCL     DL, 1
                SHR     AL, 1
                RCL     DL, 1
                SHR     AL, 1
                RCL     DL, 1
                SHR     AL, 1
                RCL     DL, 1
                SHR     AL, 1
                RCL     DL, 1
                SHR     AL, 1
                RCL     DL, 1
                MOV     AL, DL
                ROR     AX, CL
                MOV     DL, ES:[DI]
                STOSB
                MOV     CL, BL
                SHR     AH, CL
                DEC     CH
                JNZ     SHORT hsrfy_p3_no_lhs
                TEST    byte ptr cs:[DAT_0000_171d], 1
                JNZ     SHORT hsrfy_p3_done
hsrfy_p3_tail:
                MOV     CL, DH
                XOR     AL, AL
                ROR     AX, CL
                MOV     AH, ES:[DI]
                STOSB
                MOV     CL, BL
hsrfy_p3_done:
                POP     SI
                POP     DI
                ADD     SI, cs:[DAT_0000_1710]
                ADD     DI, 50H
                PUSH    DI
                PUSH    SI
                DEC     BP
                JZ      SHORT hsrfy_p3_exit
                JMP     hsrfy_p3_outer
hsrfy_p3_exit:
                MOV     CL, DH
                ADD     SP, 2
                POP     DI
                POP     DX
                POP     DI
                POP     SI
                ADD     SI, cs:[DAT_0000_1712]
                ; ---- pass 4 ----
                PUSH    SI
                PUSH    DI
                PUSH    DX
                MOV     DX, 3CEH
                MOV     AX, 0204H
                OUT     DX, AX
                MOV     DX, 3C4H
                MOV     AX, 0402H
                OUT     DX, AX
                POP     DX
                PUSH    DX
                PUSH    DI
                MOV     BX, cs:[DAT_0000_1718]
                MOV     BP, BX
                MOV     BH, DH
                MOV     DH, CL
                SUB     CL, 8
                NEG     CL
                MOV     BL, CL
                PUSH    SI
hsrfy_p4_outer:
                MOV     CH, BH
                XOR     AH, AH
                TEST    byte ptr cs:[DAT_0000_171e], 1
                JZ      SHORT hsrfy_p4_no_lhs
                MOV     AL, [SI + 1]
                SHR     AL, 1
                RCL     AH, 1
                SHR     AL, 1
                RCL     AH, 1
                SHR     AL, 1
                RCL     AH, 1
                SHR     AL, 1
                RCL     AH, 1
                SHR     AL, 1
                RCL     AH, 1
                SHR     AL, 1
                RCL     AH, 1
                SHR     AL, 1
                RCL     AH, 1
                SHR     AL, 1
                RCL     AH, 1
                MOV     AL, AH
                OR      CH, CH
                JZ      SHORT hsrfy_p4_tail
hsrfy_p4_no_lhs:
                MOV     CL, DH
                MOV     AL, [SI]
                DEC     SI
                SHR     AL, 1
                RCL     DL, 1
                SHR     AL, 1
                RCL     DL, 1
                SHR     AL, 1
                RCL     DL, 1
                SHR     AL, 1
                RCL     DL, 1
                SHR     AL, 1
                RCL     DL, 1
                SHR     AL, 1
                RCL     DL, 1
                SHR     AL, 1
                RCL     DL, 1
                SHR     AL, 1
                RCL     DL, 1
                MOV     AL, DL
                ROR     AX, CL
                MOV     DL, ES:[DI]
                STOSB
                MOV     CL, BL
                SHR     AH, CL
                DEC     CH
                JNZ     SHORT hsrfy_p4_no_lhs
                TEST    byte ptr cs:[DAT_0000_171d], 1
                JNZ     SHORT hsrfy_p4_done
hsrfy_p4_tail:
                MOV     CL, DH
                XOR     AL, AL
                ROR     AX, CL
                MOV     AH, ES:[DI]
                STOSB
                MOV     CL, BL
hsrfy_p4_done:
                POP     SI
                POP     DI
                ADD     SI, cs:[DAT_0000_1710]
                ADD     DI, 50H
                PUSH    DI
                PUSH    SI
                DEC     BP
                JZ      SHORT hsrfy_p4_exit
                JMP     hsrfy_p4_outer
hsrfy_p4_exit:
                MOV     CL, DH
                ADD     SP, 2
                POP     DI
                POP     DX
                POP     DI
                POP     SI
                ADD     SI, cs:[DAT_0000_1712]
                ; ---- pass 5 ----
                PUSH    SI
                PUSH    DI
                PUSH    DX
                MOV     DX, 3CEH
                MOV     AX, 0304H
                OUT     DX, AX
                MOV     DX, 3C4H
                MOV     AX, 0802H
                OUT     DX, AX
                POP     DX
                PUSH    DX
                PUSH    DI
                MOV     BX, cs:[DAT_0000_1718]
                MOV     BP, BX
                MOV     BH, DH
                MOV     DH, CL
                SUB     CL, 8
                NEG     CL
                MOV     BL, CL
                PUSH    SI
hsrfy_p5_outer:
                MOV     CH, BH
                XOR     AH, AH
                TEST    byte ptr cs:[DAT_0000_171e], 1
                JZ      SHORT hsrfy_p5_no_lhs
                MOV     AL, [SI + 1]
                SHR     AL, 1
                RCL     AH, 1
                SHR     AL, 1
                RCL     AH, 1
                SHR     AL, 1
                RCL     AH, 1
                SHR     AL, 1
                RCL     AH, 1
                SHR     AL, 1
                RCL     AH, 1
                SHR     AL, 1
                RCL     AH, 1
                SHR     AL, 1
                RCL     AH, 1
                SHR     AL, 1
                RCL     AH, 1
                MOV     AL, AH
                OR      CH, CH
                JZ      SHORT hsrfy_p5_tail
hsrfy_p5_no_lhs:
                MOV     CL, DH
                MOV     AL, [SI]
                DEC     SI
                SHR     AL, 1
                RCL     DL, 1
                SHR     AL, 1
                RCL     DL, 1
                SHR     AL, 1
                RCL     DL, 1
                SHR     AL, 1
                RCL     DL, 1
                SHR     AL, 1
                RCL     DL, 1
                SHR     AL, 1
                RCL     DL, 1
                SHR     AL, 1
                RCL     DL, 1
                SHR     AL, 1
                RCL     DL, 1
                MOV     AL, DL
                ROR     AX, CL
                MOV     DL, ES:[DI]
                STOSB
                MOV     CL, BL
                SHR     AH, CL
                DEC     CH
                JNZ     SHORT hsrfy_p5_no_lhs
                TEST    byte ptr cs:[DAT_0000_171d], 1
                JNZ     SHORT hsrfy_p5_done
hsrfy_p5_tail:
                MOV     CL, DH
                XOR     AL, AL
                ROR     AX, CL
                MOV     AH, ES:[DI]
                STOSB
                MOV     CL, BL
hsrfy_p5_done:
                POP     SI
                POP     DI
                ADD     SI, cs:[DAT_0000_1710]
                ADD     DI, 50H
                PUSH    DI
                PUSH    SI
                DEC     BP
                JZ      SHORT hsrfy_p5_exit
                JMP     hsrfy_p5_outer
hsrfy_p5_exit:
                MOV     CL, DH
                ADD     SP, 2
                POP     DI
                POP     DX
                ADD     SP, 4
                JMP     heg_blit_sprite_epilogue
heg_sprite_row_flipy ENDP

; ============================================================================
; heg_sprite_row_flipxy -- sprite-row blit core, BOTH-axis flip (180 rotate),
; 5 plane passes. chunk:0x21CC..0x25AC (993 bytes).
;
; Reached from dispatch index 3 (flag bits 0 AND 1 both set; see banner
; before heg_sprite_row_noflip).
;
; Diffs from heg_sprite_row_flipy (the horizontal-mirror core):
;
;   - Each of the 5 per-pass row-stride advances becomes `SUB SI, [..1710]`
;     instead of `ADD SI, [..1710]`. This adds VERTICAL mirror on top of
;     the horizontal mirror that flipy already provides: source rows are
;     consumed bottom-to-top AND within each row, bytes are consumed
;     end-to-start with each byte bit-reversed. Net effect: 180-degree
;     rotation.
;   - There is no explicit `JMP heg_blit_sprite_epilogue` at the end:
;     the function ends with `ADD SP, 4` and FALLS THROUGH into
;     heg_blit_sprite_epilogue at chunk:0x25AD (which immediately follows
;     in memory). The fall-through saves the 3 bytes of the JMP that the
;     other three cores require -- which is also why this core is the
;     last in the family and is placed adjacent to the epilogue.
;     (No PROC duplication: in this source, flipxy's ENDP is followed
;     textually by the epilogue's PROC, and the byte stream emits no
;     intervening JMP. The CPU naturally falls into the epilogue.)
; ============================================================================
heg_sprite_row_flipxy PROC FAR
                PUSH    SI
                PUSH    DI
                PUSH    DX
                PUSH    DI
                MOV     BH, DH
                MOV     AX, cs:[DAT_0000_1718]
                MOV     cs:[DAT_0000_171a], AX
                MOV     DX, 3CEH
                MOV     AL, 8
                OUT     DX, AL
                INC     DX
                MOV     SI, BP
                PUSH    SI
hsrfxy_p1_outer:
                MOV     CH, BH
                XOR     AH, AH
                TEST    byte ptr cs:[DAT_0000_171e], 1
                JZ      SHORT hsrfxy_p1_no_lhs
                MOV     AL, [SI + 1]
                NOT     AL
                SHR     AL, 1
                RCL     AH, 1
                SHR     AL, 1
                RCL     AH, 1
                SHR     AL, 1
                RCL     AH, 1
                SHR     AL, 1
                RCL     AH, 1
                SHR     AL, 1
                RCL     AH, 1
                SHR     AL, 1
                RCL     AH, 1
                SHR     AL, 1
                RCL     AH, 1
                SHR     AL, 1
                RCL     AH, 1
                MOV     AL, AH
                OR      CH, CH
                JZ      SHORT hsrfxy_p1_tail
hsrfxy_p1_no_lhs:
                MOV     AL, [SI]
                DEC     SI
                NOT     AL
                SHR     AL, 1
                RCL     BL, 1
                SHR     AL, 1
                RCL     BL, 1
                SHR     AL, 1
                RCL     BL, 1
                SHR     AL, 1
                RCL     BL, 1
                SHR     AL, 1
                RCL     BL, 1
                SHR     AL, 1
                RCL     BL, 1
                SHR     AL, 1
                RCL     BL, 1
                SHR     AL, 1
                RCL     BL, 1
                MOV     AL, BL
                ROR     AX, CL
                OUT     DX, AL
                MOV     AL, ES:[DI]
                XOR     AL, AL
                STOSB
                MOV     AL, 8
                SUB     CL, AL
                NEG     CL
                SHR     AH, CL
                SUB     CL, AL
                NEG     CL
                DEC     CH
                JNZ     SHORT hsrfxy_p1_no_lhs
                TEST    byte ptr cs:[DAT_0000_171d], 1
                JNZ     SHORT hsrfxy_p1_done
hsrfxy_p1_tail:
                XOR     AL, AL
                ROR     AX, CL
                OUT     DX, AL
                MOV     AL, ES:[DI]
                XOR     AL, AL
                STOSB
hsrfxy_p1_done:
                POP     SI
                POP     DI
                SUB     SI, cs:[DAT_0000_1710]                  ; X-flip: SUB
                ADD     DI, 50H
                PUSH    DI
                PUSH    SI
                DEC     word ptr cs:[DAT_0000_171a]
                JZ      SHORT hsrfxy_p1_exit
                JMP     hsrfxy_p1_outer
hsrfxy_p1_exit:
                XOR     AL, AL
                MOV     AL, 0FFH
                OUT     DX, AL
                ADD     SP, 2
                POP     DI
                POP     DX
                POP     DI
                POP     SI
                ; ---- pass 2 ----
                PUSH    DX
                MOV     DX, 3CEH
                MOV     AX, 5
                OUT     DX, AX
                MOV     AX, 1003H
                OUT     DX, AX
                POP     DX
                PUSH    SI
                PUSH    DI
                PUSH    DX
                MOV     DX, 3CEH
                MOV     AX, 4
                OUT     DX, AX
                MOV     DX, 3C4H
                MOV     AX, 0102H
                OUT     DX, AX
                POP     DX
                PUSH    DX
                PUSH    DI
                MOV     BX, cs:[DAT_0000_1718]
                MOV     BP, BX
                MOV     BH, DH
                MOV     DH, CL
                SUB     CL, 8
                NEG     CL
                MOV     BL, CL
                PUSH    SI
hsrfxy_p2_outer:
                MOV     CH, BH
                XOR     AH, AH
                TEST    byte ptr cs:[DAT_0000_171e], 1
                JZ      SHORT hsrfxy_p2_no_lhs
                MOV     AL, [SI + 1]
                SHR     AL, 1
                RCL     AH, 1
                SHR     AL, 1
                RCL     AH, 1
                SHR     AL, 1
                RCL     AH, 1
                SHR     AL, 1
                RCL     AH, 1
                SHR     AL, 1
                RCL     AH, 1
                SHR     AL, 1
                RCL     AH, 1
                SHR     AL, 1
                RCL     AH, 1
                SHR     AL, 1
                RCL     AH, 1
                MOV     AL, AH
                OR      CH, CH
                JZ      SHORT hsrfxy_p2_tail
hsrfxy_p2_no_lhs:
                MOV     CL, DH
                MOV     AL, [SI]
                DEC     SI
                SHR     AL, 1
                RCL     DL, 1
                SHR     AL, 1
                RCL     DL, 1
                SHR     AL, 1
                RCL     DL, 1
                SHR     AL, 1
                RCL     DL, 1
                SHR     AL, 1
                RCL     DL, 1
                SHR     AL, 1
                RCL     DL, 1
                SHR     AL, 1
                RCL     DL, 1
                SHR     AL, 1
                RCL     DL, 1
                MOV     AL, DL
                ROR     AX, CL
                MOV     DL, ES:[DI]
                STOSB
                MOV     CL, BL
                SHR     AH, CL
                DEC     CH
                JNZ     SHORT hsrfxy_p2_no_lhs
                TEST    byte ptr cs:[DAT_0000_171d], 1
                JNZ     SHORT hsrfxy_p2_done
hsrfxy_p2_tail:
                MOV     CL, DH
                XOR     AL, AL
                ROR     AX, CL
                MOV     AH, ES:[DI]
                STOSB
                MOV     CL, BL
hsrfxy_p2_done:
                POP     SI
                POP     DI
                SUB     SI, cs:[DAT_0000_1710]                  ; X-flip: SUB
                ADD     DI, 50H
                PUSH    DI
                PUSH    SI
                DEC     BP
                JZ      SHORT hsrfxy_p2_exit
                JMP     hsrfxy_p2_outer
hsrfxy_p2_exit:
                MOV     CL, DH
                ADD     SP, 2
                POP     DI
                POP     DX
                POP     DI
                POP     SI
                ADD     SI, cs:[DAT_0000_1712]
                ; ---- pass 3 ----
                PUSH    SI
                PUSH    DI
                PUSH    DX
                MOV     DX, 3CEH
                MOV     AX, 0104H
                OUT     DX, AX
                MOV     DX, 3C4H
                MOV     AX, 0202H
                OUT     DX, AX
                POP     DX
                PUSH    DX
                PUSH    DI
                MOV     BX, cs:[DAT_0000_1718]
                MOV     BP, BX
                MOV     BH, DH
                MOV     DH, CL
                SUB     CL, 8
                NEG     CL
                MOV     BL, CL
                PUSH    SI
hsrfxy_p3_outer:
                MOV     CH, BH
                XOR     AH, AH
                TEST    byte ptr cs:[DAT_0000_171e], 1
                JZ      SHORT hsrfxy_p3_no_lhs
                MOV     AL, [SI + 1]
                SHR     AL, 1
                RCL     AH, 1
                SHR     AL, 1
                RCL     AH, 1
                SHR     AL, 1
                RCL     AH, 1
                SHR     AL, 1
                RCL     AH, 1
                SHR     AL, 1
                RCL     AH, 1
                SHR     AL, 1
                RCL     AH, 1
                SHR     AL, 1
                RCL     AH, 1
                SHR     AL, 1
                RCL     AH, 1
                MOV     AL, AH
                OR      CH, CH
                JZ      SHORT hsrfxy_p3_tail
hsrfxy_p3_no_lhs:
                MOV     CL, DH
                MOV     AL, [SI]
                DEC     SI
                SHR     AL, 1
                RCL     DL, 1
                SHR     AL, 1
                RCL     DL, 1
                SHR     AL, 1
                RCL     DL, 1
                SHR     AL, 1
                RCL     DL, 1
                SHR     AL, 1
                RCL     DL, 1
                SHR     AL, 1
                RCL     DL, 1
                SHR     AL, 1
                RCL     DL, 1
                SHR     AL, 1
                RCL     DL, 1
                MOV     AL, DL
                ROR     AX, CL
                MOV     DL, ES:[DI]
                STOSB
                MOV     CL, BL
                SHR     AH, CL
                DEC     CH
                JNZ     SHORT hsrfxy_p3_no_lhs
                TEST    byte ptr cs:[DAT_0000_171d], 1
                JNZ     SHORT hsrfxy_p3_done
hsrfxy_p3_tail:
                MOV     CL, DH
                XOR     AL, AL
                ROR     AX, CL
                MOV     AH, ES:[DI]
                STOSB
                MOV     CL, BL
hsrfxy_p3_done:
                POP     SI
                POP     DI
                SUB     SI, cs:[DAT_0000_1710]                  ; X-flip: SUB
                ADD     DI, 50H
                PUSH    DI
                PUSH    SI
                DEC     BP
                JZ      SHORT hsrfxy_p3_exit
                JMP     hsrfxy_p3_outer
hsrfxy_p3_exit:
                MOV     CL, DH
                ADD     SP, 2
                POP     DI
                POP     DX
                POP     DI
                POP     SI
                ADD     SI, cs:[DAT_0000_1712]
                ; ---- pass 4 ----
                PUSH    SI
                PUSH    DI
                PUSH    DX
                MOV     DX, 3CEH
                MOV     AX, 0204H
                OUT     DX, AX
                MOV     DX, 3C4H
                MOV     AX, 0402H
                OUT     DX, AX
                POP     DX
                PUSH    DX
                PUSH    DI
                MOV     BX, cs:[DAT_0000_1718]
                MOV     BP, BX
                MOV     BH, DH
                MOV     DH, CL
                SUB     CL, 8
                NEG     CL
                MOV     BL, CL
                PUSH    SI
hsrfxy_p4_outer:
                MOV     CH, BH
                XOR     AH, AH
                TEST    byte ptr cs:[DAT_0000_171e], 1
                JZ      SHORT hsrfxy_p4_no_lhs
                MOV     AL, [SI + 1]
                SHR     AL, 1
                RCL     AH, 1
                SHR     AL, 1
                RCL     AH, 1
                SHR     AL, 1
                RCL     AH, 1
                SHR     AL, 1
                RCL     AH, 1
                SHR     AL, 1
                RCL     AH, 1
                SHR     AL, 1
                RCL     AH, 1
                SHR     AL, 1
                RCL     AH, 1
                SHR     AL, 1
                RCL     AH, 1
                MOV     AL, AH
                OR      CH, CH
                JZ      SHORT hsrfxy_p4_tail
hsrfxy_p4_no_lhs:
                MOV     CL, DH
                MOV     AL, [SI]
                DEC     SI
                SHR     AL, 1
                RCL     DL, 1
                SHR     AL, 1
                RCL     DL, 1
                SHR     AL, 1
                RCL     DL, 1
                SHR     AL, 1
                RCL     DL, 1
                SHR     AL, 1
                RCL     DL, 1
                SHR     AL, 1
                RCL     DL, 1
                SHR     AL, 1
                RCL     DL, 1
                SHR     AL, 1
                RCL     DL, 1
                MOV     AL, DL
                ROR     AX, CL
                MOV     DL, ES:[DI]
                STOSB
                MOV     CL, BL
                SHR     AH, CL
                DEC     CH
                JNZ     SHORT hsrfxy_p4_no_lhs
                TEST    byte ptr cs:[DAT_0000_171d], 1
                JNZ     SHORT hsrfxy_p4_done
hsrfxy_p4_tail:
                MOV     CL, DH
                XOR     AL, AL
                ROR     AX, CL
                MOV     AH, ES:[DI]
                STOSB
                MOV     CL, BL
hsrfxy_p4_done:
                POP     SI
                POP     DI
                SUB     SI, cs:[DAT_0000_1710]                  ; X-flip: SUB
                ADD     DI, 50H
                PUSH    DI
                PUSH    SI
                DEC     BP
                JZ      SHORT hsrfxy_p4_exit
                JMP     hsrfxy_p4_outer
hsrfxy_p4_exit:
                MOV     CL, DH
                ADD     SP, 2
                POP     DI
                POP     DX
                POP     DI
                POP     SI
                ADD     SI, cs:[DAT_0000_1712]
                ; ---- pass 5 ----
                PUSH    SI
                PUSH    DI
                PUSH    DX
                MOV     DX, 3CEH
                MOV     AX, 0304H
                OUT     DX, AX
                MOV     DX, 3C4H
                MOV     AX, 0802H
                OUT     DX, AX
                POP     DX
                PUSH    DX
                PUSH    DI
                MOV     BX, cs:[DAT_0000_1718]
                MOV     BP, BX
                MOV     BH, DH
                MOV     DH, CL
                SUB     CL, 8
                NEG     CL
                MOV     BL, CL
                PUSH    SI
hsrfxy_p5_outer:
                MOV     CH, BH
                XOR     AH, AH
                TEST    byte ptr cs:[DAT_0000_171e], 1
                JZ      SHORT hsrfxy_p5_no_lhs
                MOV     AL, [SI + 1]
                SHR     AL, 1
                RCL     AH, 1
                SHR     AL, 1
                RCL     AH, 1
                SHR     AL, 1
                RCL     AH, 1
                SHR     AL, 1
                RCL     AH, 1
                SHR     AL, 1
                RCL     AH, 1
                SHR     AL, 1
                RCL     AH, 1
                SHR     AL, 1
                RCL     AH, 1
                SHR     AL, 1
                RCL     AH, 1
                MOV     AL, AH
                OR      CH, CH
                JZ      SHORT hsrfxy_p5_tail
hsrfxy_p5_no_lhs:
                MOV     CL, DH
                MOV     AL, [SI]
                DEC     SI
                SHR     AL, 1
                RCL     DL, 1
                SHR     AL, 1
                RCL     DL, 1
                SHR     AL, 1
                RCL     DL, 1
                SHR     AL, 1
                RCL     DL, 1
                SHR     AL, 1
                RCL     DL, 1
                SHR     AL, 1
                RCL     DL, 1
                SHR     AL, 1
                RCL     DL, 1
                SHR     AL, 1
                RCL     DL, 1
                MOV     AL, DL
                ROR     AX, CL
                MOV     DL, ES:[DI]
                STOSB
                MOV     CL, BL
                SHR     AH, CL
                DEC     CH
                JNZ     SHORT hsrfxy_p5_no_lhs
                TEST    byte ptr cs:[DAT_0000_171d], 1
                JNZ     SHORT hsrfxy_p5_done
hsrfxy_p5_tail:
                MOV     CL, DH
                XOR     AL, AL
                ROR     AX, CL
                MOV     AH, ES:[DI]
                STOSB
                MOV     CL, BL
hsrfxy_p5_done:
                POP     SI
                POP     DI
                SUB     SI, cs:[DAT_0000_1710]                  ; X-flip: SUB
                ADD     DI, 50H
                PUSH    DI
                PUSH    SI
                DEC     BP
                JZ      SHORT hsrfxy_p5_exit
                JMP     hsrfxy_p5_outer
hsrfxy_p5_exit:
                MOV     CL, DH
                ADD     SP, 2
                POP     DI
                POP     DX
                ADD     SP, 4
                ; FALLS THROUGH into heg_blit_sprite_epilogue at 0x25AD --
                ; the 3 bytes of a trailing JMP are intentionally omitted.
heg_sprite_row_flipxy ENDP

; ============================================================================
; heg_blit_sprite_epilogue -- common tail for all 4 sprite-row cores.
; chunk:0x25AD..0x25F1 (69 bytes incl. 2-byte interior pad).
;
; Restores the EGA GC/SC registers to safe defaults, then restores the
; chunk-local globals (the 8 words pushed by heg_blit_sprite_master),
; tears down the local frame, and RETFs.
;
; Register restore pattern:
;   GC idx 5 := 0x02  -- write mode 2, read mode 0 (chunk's default)
;   GC idx 3 := 0x00  -- data rotate / function select reset to identity
;                        (NB: this is GC[3]:=0, NOT GR5:=3 / write mode 3.
;                        Write mode 3 is VGA-only; this driver supports
;                        EGA cards as well, so it never selects WM3.)
;   SC idx 2 := 0x0F  -- map mask = all 4 planes enabled
; The four sprite-row cores all jump (or fall through, for flipxy) here
; so the register-restore pattern only needs to exist once.
;
; The 2-byte zero pad after RETF (0x25F0..0x25F1) is the
; heg_install_image_archive scratch word `g_wHegArchiveCursor`,
; referenced as CS:[0x25F0] by heg_install_image_archive and
; heg_reset_archive_install_flag.
; ============================================================================
heg_blit_sprite_epilogue PROC FAR
                MOV     DX, 3CEH
                MOV     AX, 0205H
                OUT     DX, AX
                MOV     AX, 3
                OUT     DX, AX
                MOV     DX, 3C4H
                MOV     AX, 0F02H
                OUT     DX, AX
                POP     word ptr cs:[DAT_0000_171e]
                POP     word ptr cs:[DAT_0000_171c]
                POP     cs:[DAT_0000_1716]
                POP     cs:[DAT_0000_1714]
                POP     cs:[DAT_0000_1712]
                POP     cs:[DAT_0000_1710]
                POP     cs:[DAT_0000_171a]
                POP     cs:[DAT_0000_1718]
                POP     DS
                POP     ES
                POP     DI
                POP     SI
                ADD     SP, 0AH
                POP     BP
                RETF
heg_blit_sprite_epilogue ENDP

; ----------------------------------------------------------------------------
; g_wHegArchiveCursor -- 2-byte scratch word at chunk:0x25F0.
; Used by heg_install_image_archive (CS:[0x25F0]) as a running offset
; cursor into the destination paragraph (segment 0xAC00) while
; copying each archive entry; reset to 0 by heg_reset_archive_install_flag.
; On-disk default is zero.
; ----------------------------------------------------------------------------
g_wHegArchiveCursor DW 0                                ; 0x25F0..0x25F1

; ============================================================================
; heg_blit_byte_aligned_latched -- fast rectangular block-copy from
; off-screen to on-screen, EGA "latched" / planar mode, byte-aligned X.
; chunk:0x25F2..0x2689 (152 bytes).
;
; Vtable slot 30.
;
; __cdecl16far args: [BP+6]=src_seg, [BP+8]=width_px, [BP+0xA]=dst_y_px.
; Actually the layout differs: BP is reloaded from [BP+6] partway through
; (BP becomes a FAR pointer's offset for source descriptor); see below.
;
; Programs the GC for WRITE MODE 1 (latch-copy; AX=0x0105 -> GC idx 5
; := 0x01) so that REP MOVSB on a video-memory destination reads the
; latches from the source byte position and writes all 4 planes
; simultaneously. Outer loop is 8x unrolled MOVSB; ADD DI,BP; DEC DX;
; JZ tail. Restores write mode 2 (the chunk default; AX=0x0205 -> GC
; idx 5 := 0x02) on exit.
; ============================================================================
heg_blit_byte_aligned_latched PROC FAR
                PUSH    BP
                MOV     BP, SP
                PUSH    SI
                PUSH    DI
                PUSH    DS
                MOV     DS, cs:[g_wHegChunkDataSeg]
                MOV     DI, [BP + 0AH]
                SHL     DI, 1
                MOV     DI, [DI].GfxContext.pRow_offset_lut    ; row LUT
                MOV     AX, [BP + 8]
                SHR     AX, 1
                SHR     AX, 1
                SHR     AX, 1
                ADD     DI, AX
                MOV     BP, [BP + 6]
                MOV     ES, ds:[GfxContext.wGfxBlitDstPage]    ; VRAM segment from chunk-data slot
                MOV     DX, 3CEH
                MOV     AX, 0105H                       ; GC index 5 (mode) = 01 (write-mode 1)
                OUT     DX, AX
                MOV     DX, [BP + 8]
                MOV     BX, [BP + 6]
                SHR     BX, 1
                SHR     BX, 1
                SHR     BX, 1
                MOV     SI, [BP + 2]
                MOV     DS, [BP + 0]
                MOV     BP, 50H
                SUB     BP, BX
hbal_outer:
                MOV     CX, BX
                REP MOVSB
                ADD     DI, BP
                DEC     DX
                JZ      SHORT hbal_done
                MOV     CX, BX
                REP MOVSB
                ADD     DI, BP
                DEC     DX
                JZ      SHORT hbal_done
                MOV     CX, BX
                REP MOVSB
                ADD     DI, BP
                DEC     DX
                JZ      SHORT hbal_done
                MOV     CX, BX
                REP MOVSB
                ADD     DI, BP
                DEC     DX
                JZ      SHORT hbal_done
                MOV     CX, BX
                REP MOVSB
                ADD     DI, BP
                DEC     DX
                JZ      SHORT hbal_done
                MOV     CX, BX
                REP MOVSB
                ADD     DI, BP
                DEC     DX
                JZ      SHORT hbal_done
                MOV     CX, BX
                REP MOVSB
                ADD     DI, BP
                DEC     DX
                JZ      SHORT hbal_done
                MOV     CX, BX
                REP MOVSB
                ADD     DI, BP
                DEC     DX
                JNZ     SHORT hbal_outer
hbal_done:
                MOV     DX, 3CEH
                MOV     AX, 0205H                       ; restore write-mode 2
                OUT     DX, AX
                POP     DS
                POP     DI
                POP     SI
                POP     BP
                RETF
heg_blit_byte_aligned_latched ENDP

; ============================================================================
; heg_install_image_archive -- bulk-stage a list of sprite/image entries
; into off-screen video memory (segment 0xAC00) and free the source bufs.
; chunk:0x268A..0x271E (149 bytes).
;
; Vtable slot 31.
;
; Walks a NULL-terminated list of image-descriptor far pointers passed in
; [BP+6] (pointer to first slot; each slot is a far ptr; terminated by a
; NULL OFFSET word).
; For each non-NULL descriptor: copies the 4 EGA planes (one per pass)
; from descriptor's data into VRAM at the running cursor `g_wHegArchiveCursor`
; (CS:[0x25F0]) via the GC map-mask trick (SC index 2, mask = 0x01, 0x02,
; 0x04, 0x08 — produced by SHL AH,1 between OUTs). Stores the destination
; offset back into the descriptor (so the host can fetch it later) and
; INT 21h AH=49h frees the source memory block. Restores GC write-mode
; 2 / SC map-mask 0xF on exit.
;
; NOTE: contains an apparently-dead `MOV AX, 5` (B8 05 00) at chunk:0x26D7
; immediately followed by `MOV AX, 0x102` — likely a refactoring residue.
; ============================================================================
heg_install_image_archive PROC FAR
                PUSH    BP
                MOV     BP, SP
                PUSH    DI
                PUSH    SI
                MOV     BP, [BP + 6]                    ; BP <- pointer to descriptor list
                MOV     BX, [BP + 0]
                PUSH    BP
                PUSH    word ptr [BX]                   ; save first descriptor's [0] field
hiia_loop:
                MOV     BX, [BP + 0]
                ADD     BP, 2
                OR      BX, BX
                JZ      SHORT hiia_done
                MOV     AX, 0AC00H
                MOV     ES, AX
                MOV     DI, cs:[g_wHegArchiveCursor]
                MOV     SI, [BX + 2]
                MOV     [BX + 2], DI
                MOV     AX, [BX + 6]
                XOR     DX, DX
                MUL     word ptr [BX + 8]
                SHR     AX, 1
                SHR     AX, 1
                SHR     AX, 1
                ADD     cs:[g_wHegArchiveCursor], AX
                MOV     CX, AX
                PUSH    DS
                MOV     AX, [BX]
                MOV     DX, ES
                MOV     [BX], DX
                MOV     DS, AX
                MOV     AX, 5
                MOV     DX, 3CEH
                OUT     DX, AX
                MOV     AX, 5                           ; (dead; immediately overwritten)
                MOV     AX, 0102H                       ; SC index 2 (map mask), data 0x01
                MOV     DX, 3C4H
                PUSH    CX
                PUSH    DI
                OUT     DX, AX
                SHL     AH, 1                           ; AH: 01 -> 02 -> 04 -> 08
                REP MOVSB
                POP     DI
                POP     CX
                PUSH    CX
                PUSH    DI
                OUT     DX, AX
                SHL     AH, 1
                REP MOVSB
                POP     DI
                POP     CX
                PUSH    CX
                PUSH    DI
                OUT     DX, AX
                SHL     AH, 1
                REP MOVSB
                POP     DI
                POP     CX
                PUSH    CX
                PUSH    DI
                OUT     DX, AX
                SHL     AH, 1
                REP MOVSB
                POP     DI
                POP     CX
                POP     DS
                JMP     SHORT hiia_loop
hiia_done:
                POP     ES
                MOV     AH, 49H                         ; DOS free memory block
                INT     21H
                MOV     AX, 0205H
                MOV     DX, 3CEH
                OUT     DX, AX
                MOV     AX, 0F02H
                MOV     DX, 3C4H
                OUT     DX, AX
                POP     AX
                POP     SI
                POP     DI
                POP     BP
                RETF
heg_install_image_archive ENDP

; ============================================================================
; heg_reset_archive_install_flag -- reset the running archive-install cursor
; (g_wHegArchiveCursor at chunk:0x25F0) to zero.
; chunk:0x271F..0x2725 (7 bytes).
;
; Vtable slot 32.
; ============================================================================
heg_reset_archive_install_flag PROC FAR
                XOR     AX, AX
                MOV     cs:[g_wHegArchiveCursor], AX
                RETF
heg_reset_archive_install_flag ENDP

; ============================================================================
; heg_blit_sprite_planar -- standalone planar sprite blitter (no flip),
; with full clip-rect support.
; chunk:0x2726..0x2AE7 (962 bytes).
;
; Vtable slot 33.
;
; __cdecl16far(SpriteDesc *desc, int dst_x, int dst_y).
; Builds the local stack frame (0xA bytes for a copy of the 10-byte sprite
; descriptor), clips against DS:[0..0xA] (the chunk's clip-rect block),
; then runs the same 5-plane-pass blit core as heg_sprite_row_noflip --
; except it operates on private scratch globals at chunk:0x2AE8..0x2AF0
; (NOT the shared 0x1710..0x171F block used by the dispatched cores).
;
; This is the OVL chunk's "single-shot" sprite blitter (called directly,
; bypassing heg_blit_sprite_master / g_apHegSpriteFlipDispatch). Used by
; the host for sprites that don't need flip dispatch.
; ============================================================================
heg_blit_sprite_planar PROC FAR
                PUSH    BP
                MOV     BP, SP
                SUB     SP, 0AH
                PUSH    SI
                PUSH    DI
                PUSH    ES
                PUSH    DS
                MOV     SI, [BP + 6]
                MOV     DI, BP
                SUB     DI, 0AH
                MOV     AX, SS
                MOV     ES, AX
                MOV     CX, 5
                REP MOVSW
                MOV     DS, cs:[g_wHegChunkDataSeg]
                MOV     AX, ds:[GfxContext.wGfxBlitDstPage]
                MOV     ES, AX
                MOV     AX, [BP - 4]
                SHR     AX, 1
                SHR     AX, 1
                SHR     AX, 1
                MUL     byte ptr [BP - 2]
                MOV     cs:[DAT_0000_2aea], AX
                MOV     BX, [BP + 0AH]
                SHL     BX, 1
                JNS     SHORT hbsp_y_pos
                SAR     BX, 1
                SHL     BX, 1
                SHL     BX, 1
                SHL     BX, 1
                MOV     DI, BX
                SHL     BX, 1
                SHL     BX, 1
                ADD     DI, BX
                JMP     SHORT hbsp_after_y
hbsp_y_pos:
                MOV     DI, [BX].GfxContext.pRow_offset_lut
hbsp_after_y:
                MOV     AX, [BP + 8]
                MOV     CL, AL
                SAR     AX, 1
                SAR     AX, 1
                SAR     AX, 1
                ADD     DI, AX
                AND     CL, 7
                MOV     AX, [BP - 4]
                MOV     DX, AX
                SHR     AX, 1
                SHR     AX, 1
                SHR     AX, 1
                MOV     cs:[DAT_0000_2ae8], AX
                ADD     DX, 7
                SHR     DX, 1
                SHR     DX, 1
                SHR     DX, 1
                MOV     DH, DL
                MOV     AL, [BP - 2]
                MOV     cs:[DAT_0000_2af0], AL
                MOV     AX, [BP - 0AH]
                MOV     cs:[DAT_0000_2aec], AX
                MOV     SI, [BP - 8]
                XOR     AX, AX
                MOV     cs:[DAT_0000_2aee], AL
                MOV     cs:[DAT_0000_2aef], AL
                JZ      SHORT hbsp_after_si_adj
                MOV     AX, cs:[DAT_0000_2ae8]          ; dead: JZ above always taken
                DEC     AX
                ADD     SI, AX
hbsp_after_si_adj:
                MOV     AL, ds:[GfxContext.bClip_enabled]      ; clip-rect enable
                OR      AL, AL
                JNZ     SHORT hbsp_clip_check
                JMP     hbsp_pass1_setup
hbsp_clip_check:
                MOV     AX, ds:[GfxContext.nClip_xmax]
                INC     AX
                MOV     BX, [BP + 8]
                ADD     BX, [BP - 4]
                SUB     AX, BX
                JG      SHORT hbsp_right_ok
                NEG     AX
                CMP     AX, [BP - 4]
                JL      SHORT hbsp_right_partial
                JMP     hbsp_clipped_exit
hbsp_right_partial:
                SHR     AX, 1
                SHR     AX, 1
                SHR     AX, 1
                SUB     DH, AL
                MOV     byte ptr cs:[DAT_0000_2aee], 1
hbsp_right_ok:
                MOV     AX, [BP + 8]
                SUB     AX, ds:[GfxContext.nClip_xmin]
                JNS     SHORT hbsp_left_ok
                MOV     BX, AX
                ADD     AX, [BP - 4]
                JG      SHORT hbsp_left_partial
                JMP     hbsp_clipped_exit
hbsp_left_partial:
                MOV     byte ptr cs:[DAT_0000_2aef], 1
                NEG     BX
                ADD     BX, 7
                SHR     BX, 1
                SHR     BX, 1
                SHR     BX, 1
                SUB     DH, BL
                ADD     DI, BX
                ADD     SI, BX
hbsp_left_ok:
                MOV     AX, [BP + 0AH]
                ADD     AX, [BP - 2]
                SUB     AX, ds:[GfxContext.nClip_ymax]
                JS      SHORT hbsp_bottom_ok
                CMP     AX, [BP - 2]
                JS      SHORT hbsp_bottom_partial
                JMP     hbsp_clipped_exit
hbsp_bottom_partial:
                DEC     AL
                SUB     byte ptr cs:[DAT_0000_2af0], AL
hbsp_bottom_ok:
                MOV     AX, ds:[GfxContext.nClip_ymin]
                SUB     AX, [BP + 0AH]
                JS      SHORT hbsp_pass1_setup
                CMP     AX, [BP - 2]
                JS      SHORT hbsp_top_partial
                JMP     hbsp_clipped_exit
hbsp_top_partial:
                SUB     byte ptr cs:[DAT_0000_2af0], AL
                MOV     BX, AX
                SHL     AX, 1
                SHL     AX, 1
                SHL     AX, 1
                ADD     DI, AX
                SHL     AX, 1
                SHL     AX, 1
                ADD     DI, AX
                MOV     AX, BX
                MUL     byte ptr cs:[DAT_0000_2ae8]
                ADD     SI, AX
hbsp_pass1_setup:
                MOV     DS, cs:[DAT_0000_2aec]
                ; ---- pass 1 (plane 0) ----
                PUSH    SI
                PUSH    DI
                PUSH    DX
                PUSH    DI
                MOV     BH, DH
                MOV     BL, cs:[DAT_0000_2af0]
                MOV     DX, 3CEH
                MOV     AL, 8
                OUT     DX, AL
                INC     DX
                MOV     SI, BP
                PUSH    SI
hbsp_p1_outer:
                MOV     CH, BH
                XOR     AH, AH
                TEST    byte ptr cs:[DAT_0000_2aef], 1
                JZ      SHORT hbsp_p1_no_lhs
                MOV     AH, [SI - 1]
                NOT     AH
                OR      CH, CH
                JZ      SHORT hbsp_p1_tail
hbsp_p1_no_lhs:
                XOR     AL, AL
                NOT     AL
                ROR     AX, CL
                OUT     DX, AL
                MOV     AL, ES:[DI]
                XOR     AL, AL
                STOSB
                MOV     AL, 8
                SUB     CL, AL
                NEG     CL
                SHR     AH, CL
                SUB     CL, AL
                NEG     CL
                DEC     CH
                JNZ     SHORT hbsp_p1_no_lhs
                TEST    byte ptr cs:[DAT_0000_2aee], 1
                JNZ     SHORT hbsp_p1_done
hbsp_p1_tail:
                XOR     AL, AL
                ROR     AX, CL
                OUT     DX, AL
                MOV     AL, ES:[DI]
                XOR     AL, AL
                STOSB
hbsp_p1_done:
                POP     SI
                POP     DI
                ADD     SI, cs:[DAT_0000_2ae8]
                ADD     DI, 50H
                PUSH    DI
                PUSH    SI
                DEC     BL
                JNZ     SHORT hbsp_p1_outer
                XOR     AL, AL
                MOV     AL, 0FFH
                OUT     DX, AL
                ADD     SP, 2
                POP     DI
                POP     DX
                POP     DI
                POP     SI
                ; ---- pass 2 setup ----
                PUSH    DX
                MOV     DX, 3CEH
                MOV     AX, 5
                OUT     DX, AX
                MOV     AX, 1003H
                OUT     DX, AX
                MOV     AX, 0FF08H
                OUT     DX, AX
                POP     DX
                PUSH    SI
                PUSH    DI
                PUSH    DX
                MOV     DX, 3C4H
                MOV     AX, 0102H
                OUT     DX, AX
                POP     DX
                PUSH    DX
                PUSH    DI
                MOV     BL, cs:[DAT_0000_2af0]
                XOR     BH, BH
                MOV     BP, BX
                MOV     BH, DH
                MOV     DH, CL
                SUB     CL, 8
                NEG     CL
                MOV     BL, CL
                PUSH    SI
hbsp_p2_outer:
                MOV     CH, BH
                XOR     AH, AH
                TEST    byte ptr cs:[DAT_0000_2aef], 1
                JZ      SHORT hbsp_p2_inner
                MOV     AH, [SI - 1]
                OR      CH, CH
                JZ      SHORT hbsp_p2_tail
hbsp_p2_inner:
                MOV     CL, DH
                LODSB
                ROR     AX, CL
                MOV     DL, ES:[DI]
                STOSB
                MOV     CL, BL
                SHR     AH, CL
                DEC     CH
                JNZ     SHORT hbsp_p2_inner
                TEST    byte ptr cs:[DAT_0000_2aee], 1
                JNZ     SHORT hbsp_p2_done
hbsp_p2_tail:
                MOV     CL, DH
                XOR     AL, AL
                ROR     AX, CL
                MOV     AH, ES:[DI]
                STOSB
                MOV     CL, BL
hbsp_p2_done:
                POP     SI
                POP     DI
                ADD     SI, cs:[DAT_0000_2ae8]
                ADD     DI, 50H
                PUSH    DI
                PUSH    SI
                DEC     BP
                JNZ     SHORT hbsp_p2_outer
                MOV     CL, DH
                ADD     SP, 2
                POP     DI
                POP     DX
                POP     DI
                POP     SI
                ADD     SI, cs:[DAT_0000_2aea]
                ; ---- pass 3 ----
                PUSH    SI
                PUSH    DI
                PUSH    DX
                MOV     DX, 3C4H
                MOV     AX, 0202H
                OUT     DX, AX
                POP     DX
                PUSH    DX
                PUSH    DI
                MOV     BL, cs:[DAT_0000_2af0]
                XOR     BH, BH
                MOV     BP, BX
                MOV     BH, DH
                MOV     DH, CL
                SUB     CL, 8
                NEG     CL
                MOV     BL, CL
                PUSH    SI
hbsp_p3_outer:
                MOV     CH, BH
                XOR     AH, AH
                TEST    byte ptr cs:[DAT_0000_2aef], 1
                JZ      SHORT hbsp_p3_inner
                MOV     AH, [SI - 1]
                OR      CH, CH
                JZ      SHORT hbsp_p3_tail
hbsp_p3_inner:
                MOV     CL, DH
                LODSB
                ROR     AX, CL
                MOV     DL, ES:[DI]
                STOSB
                MOV     CL, BL
                SHR     AH, CL
                DEC     CH
                JNZ     SHORT hbsp_p3_inner
                TEST    byte ptr cs:[DAT_0000_2aee], 1
                JNZ     SHORT hbsp_p3_done
hbsp_p3_tail:
                MOV     CL, DH
                XOR     AL, AL
                ROR     AX, CL
                MOV     AH, ES:[DI]
                STOSB
                MOV     CL, BL
hbsp_p3_done:
                POP     SI
                POP     DI
                ADD     SI, cs:[DAT_0000_2ae8]
                ADD     DI, 50H
                PUSH    DI
                PUSH    SI
                DEC     BP
                JNZ     SHORT hbsp_p3_outer
                MOV     CL, DH
                ADD     SP, 2
                POP     DI
                POP     DX
                POP     DI
                POP     SI
                ADD     SI, cs:[DAT_0000_2aea]
                ; ---- pass 4 ----
                PUSH    SI
                PUSH    DI
                PUSH    DX
                MOV     DX, 3C4H
                MOV     AX, 0402H
                OUT     DX, AX
                POP     DX
                PUSH    DX
                PUSH    DI
                MOV     BL, cs:[DAT_0000_2af0]
                XOR     BH, BH
                MOV     BP, BX
                MOV     BH, DH
                MOV     DH, CL
                SUB     CL, 8
                NEG     CL
                MOV     BL, CL
                PUSH    SI
hbsp_p4_outer:
                MOV     CH, BH
                XOR     AH, AH
                TEST    byte ptr cs:[DAT_0000_2aef], 1
                JZ      SHORT hbsp_p4_inner
                MOV     AH, [SI - 1]
                OR      CH, CH
                JZ      SHORT hbsp_p4_tail
hbsp_p4_inner:
                MOV     CL, DH
                LODSB
                ROR     AX, CL
                MOV     DL, ES:[DI]
                STOSB
                MOV     CL, BL
                SHR     AH, CL
                DEC     CH
                JNZ     SHORT hbsp_p4_inner
                TEST    byte ptr cs:[DAT_0000_2aee], 1
                JNZ     SHORT hbsp_p4_done
hbsp_p4_tail:
                MOV     CL, DH
                XOR     AL, AL
                ROR     AX, CL
                MOV     AH, ES:[DI]
                STOSB
                MOV     CL, BL
hbsp_p4_done:
                POP     SI
                POP     DI
                ADD     SI, cs:[DAT_0000_2ae8]
                ADD     DI, 50H
                PUSH    DI
                PUSH    SI
                DEC     BP
                JNZ     SHORT hbsp_p4_outer
                MOV     CL, DH
                ADD     SP, 2
                POP     DI
                POP     DX
                POP     DI
                POP     SI
                ADD     SI, cs:[DAT_0000_2aea]
                ; ---- pass 5 ----
                PUSH    SI
                PUSH    DI
                PUSH    DX
                MOV     DX, 3C4H
                MOV     AX, 0802H
                OUT     DX, AX
                POP     DX
                PUSH    DX
                PUSH    DI
                MOV     BL, cs:[DAT_0000_2af0]
                XOR     BH, BH
                MOV     BP, BX
                MOV     BH, DH
                MOV     DH, CL
                SUB     CL, 8
                NEG     CL
                MOV     BL, CL
                PUSH    SI
hbsp_p5_outer:
                MOV     CH, BH
                XOR     AH, AH
                TEST    byte ptr cs:[DAT_0000_2aef], 1
                JZ      SHORT hbsp_p5_inner
                MOV     AH, [SI - 1]
                OR      CH, CH
                JZ      SHORT hbsp_p5_tail
hbsp_p5_inner:
                MOV     CL, DH
                LODSB
                ROR     AX, CL
                MOV     DL, ES:[DI]
                STOSB
                MOV     CL, BL
                SHR     AH, CL
                DEC     CH
                JNZ     SHORT hbsp_p5_inner
                TEST    byte ptr cs:[DAT_0000_2aee], 1
                JNZ     SHORT hbsp_p5_done
hbsp_p5_tail:
                MOV     CL, DH
                XOR     AL, AL
                ROR     AX, CL
                MOV     AH, ES:[DI]
                STOSB
                MOV     CL, BL
hbsp_p5_done:
                POP     SI
                POP     DI
                ADD     SI, cs:[DAT_0000_2ae8]
                ADD     DI, 50H
                PUSH    DI
                PUSH    SI
                DEC     BP
                JNZ     SHORT hbsp_p5_outer
                MOV     CL, DH
                ADD     SP, 2
                POP     DI
                POP     DX
                ADD     SP, 4
hbsp_clipped_exit:
                MOV     DX, 3CEH
                MOV     AX, 0205H
                OUT     DX, AX
                MOV     AX, 3
                OUT     DX, AX
                MOV     DX, 3C4H
                MOV     AX, 0F02H
                OUT     DX, AX
                POP     DS
                POP     ES
                POP     DI
                POP     SI
                ADD     SP, 0AH
                POP     BP
                RETF
heg_blit_sprite_planar ENDP

; ----------------------------------------------------------------------------
; Chunk-local scratch globals at chunk:0x2AE8..0x2AF0 (9 bytes), embedded
; inside the heg_blit_sprite_planar segment. Reset / written by that
; function during the prologue and read by the per-plane loops. Distinct
; from the dispatcher's 0x1710..0x171F scratch block.
;
; - 0x2AE8 DW : byte-width of source row (W / 8) -- pass row stride
; - 0x2AEA DW : (W/8) * H -- inter-pass advance
; - 0x2AEC DW : source DS (descriptor.segment, [BP-A] local copy)
; - 0x2AEE DB : right-clip active flag
; - 0x2AEF DB : left-clip active flag
; - 0x2AF0 DB : height in scanlines (decremented by clipping if needed)
; ----------------------------------------------------------------------------
DAT_0000_2ae8   DW      0
DAT_0000_2aea   DW      0
DAT_0000_2aec   DW      0
DAT_0000_2aee   DB      0
DAT_0000_2aef   DB      0
DAT_0000_2af0   DB      0

; ============================================================================
; heg_tail_retf_stub -- 1-byte RETF placeholder for vtable slot 24.
; chunk:0x2AF1
;
; Vtable slot 24.
;
; Structurally identical to heg_unimplemented_slot at chunk:0x0252 -- two
; distinct 1-byte RETF stubs in different file locations are an artifact
; of the original C source layout (two `void f(void){}` definitions, or
; a forward-declared placeholder somewhere ending up here at link time).
; ============================================================================
heg_tail_retf_stub PROC FAR
                RETF
heg_tail_retf_stub ENDP

; ============================================================================
; heg_set_border_color -- set EGA overscan-border colour via BIOS INT 10h
; AH=10h / AL=01h. chunk:0x2AF2..0x2B1A (41 bytes).
;
; Vtable slot 25.
;
; __cdecl16far(int color). Reads `[BP+6]`, low nybble. If the runtime
; mode (DS:[0x1D]) == 2 and the colour is >= 8, ORs 0x8 into the high bit
; (intensity bit for some EGA-class modes). Calls INT 10h AX=1001h with
; the resulting color in BH.
; ============================================================================
heg_set_border_color PROC FAR
                PUSH    BP
                MOV     BP, SP
                PUSH    DS
                MOV     DS, cs:[g_wHegChunkDataSeg]
                MOV     BX, [BP + 6]
                MOV     BH, BL
                AND     BH, 0FH
                CMP     byte ptr ds:[GfxContext.bVideoAdapter], 2
                JNZ     SHORT hsbc_skip
                CMP     BH, 8
                JC      SHORT hsbc_skip
                ADD     BH, 8
hsbc_skip:
                MOV     AH, 10H
                MOV     AL, 1
                INT     10H
                POP     DS
                POP     BP
                RETF
heg_set_border_color ENDP

                END

; ============================================================================
; Glossary
;
; Hardware-specific abbreviations used throughout this file:
;
;   EGA  -- IBM Enhanced Graphics Adapter (1984). Up to 640x350x16 colours
;           via planar 4-bit-per-pixel framebuffer at A000:0000.
;   VGA  -- IBM Video Graphics Array (1987). Superset of EGA; this driver
;           uses mode 12h (640x480x16) on VGA hardware via planar 4bpp.
;   CRTC -- Cathode Ray Tube Controller. The chip that generates the
;           video timing (horizontal/vertical sync, display enable).
;           Programmed via index port 0x3D4 / data port 0x3D5. HEG tweaks
;           registers 0x0C/0x0D (start address hi/lo), 0x12 (vertical
;           display end), 0x15/0x16 (vertical blanking start/end) to
;           shrink the visible viewport for the 640x400 mode.
;   GC   -- Graphics Controller. Manages how the CPU's writes to the
;           framebuffer reach the 4 planes. Index port 0x3CE / data 0x3CF.
;           Key indices used here:
;             0x04 -- read map select (which plane CPU reads return)
;             0x05 -- graphics mode (read modes 0/1, write modes 0..3)
;             0x08 -- bit mask (which of the 8 horizontal pixels in a
;                     byte the write affects)
;   SEQ / SC -- Sequencer. Index port 0x3C4 / data 0x3C5. Index 0x02 is
;           the "map mask" -- which of the 4 planes the CPU's write goes
;           to. (0x0F = all planes; 0x01/0x02/0x04/0x08 = one plane.)
;   AC   -- Attribute Controller. Port 0x3C0. 16-entry palette mapping
;           4-bit framebuffer values to 6-bit DAC indices. The flip-flop
;           that distinguishes index writes from data writes is reset by
;           a READ from 0x3DA (the status register).
;   DAC  -- Digital-to-Analog Converter palette. 256 entries of 18-bit
;           RGB (6 bits per channel). Index port 0x3C8 (write index) /
;           0x3C7 (read index) / 0x3C9 (data). VGA only -- on plain EGA
;           the 16 colours are fixed by hardware.
;
; Planar 4bpp framebuffer terminology:
;
;   "Plane"      -- one of 4 separate 64-KB bit-planes overlaid at the
;                   same address (A000:0000 etc.). A pixel's 4-bit
;                   colour comes from reading the same bit position
;                   across all 4 planes.
;   "Latch"      -- a 4-byte (1-per-plane) CPU-side register inside the
;                   GC, loaded by ANY read from VRAM. Subsequent VRAM
;                   writes can combine the new value with the latch.
;   "Write mode" -- the GC has 4 write modes (idx 0x05 low 2 bits):
;                     0 = direct (data + bit-mask -> all planes)
;                     1 = latch-copy (writes whatever's in the latch
;                         to all 4 planes, regardless of CPU data)
;                     2 = data-as-colour (4 low bits of CPU data become
;                         the colour for each pixel within the byte)
;                     3 = data + set/reset XOR (rare; not used here)
;   "Read mode"  -- 0 = plane-select read (returns the byte in the
;                   plane selected by GC idx 0x04); 1 = colour-compare
;                   (returns a mask of pixels matching GC idx 0x02).
;
; DUDE / OVL chunk terminology:
;
;   Vmcode.OVL   -- a flat archive of video-driver chunks, one per
;                   adapter. The engine selects a chunk at runtime.
;   chunk        -- a self-contained, position-independent piece of
;                   code+data. Has a vtable template that the engine
;                   stamps with the chunk's load segment after init.
;   vtable       -- array of 50 (offset, segment) pairs at chunk:0x013E.
;                   Slot N is a far function pointer for renderer
;                   operation N. The host calls them via CALLF
;                   [g_renderer_vtable + N*4].
;   "scratch DS" -- a private working segment allocated by the host
;                   `paragraph_count` paragraphs past the caller's DS.
;                   Holds the scanline LUT, framebuffer-segment shadow
;                   words, and per-slot scratch state. Reloaded from
;                   cs:[g_wHegChunkDataSeg] on entry to each slot that
;                   needs it.
;   "dual-use storage" -- a 2-byte cell embedded in the chunk's .CODE
;                   segment that is both written by an instruction in
;                   init (as a `MOV CS:[imm16], reg`) and later read
;                   back as a CS-relative global. HEG has only two
;                   such cells (g_wHegChunkDataSeg at 0x013A and
;                   g_wHegInitParagraphs at 0x013C).
;
; BIOS INT 10h subfunctions called:
;
;   AX=000Eh   set video mode 0Eh (640x200x16 EGA)
;   AX=0010h   set video mode 10h (640x350x16 EGA)
;   AX=0012h   set video mode 12h (640x480x16 VGA)
;   AX=1001h   set border (overscan) colour from BH
;   AX=1013h   palette page select (BL=00h identity, BL=01h paged)
;
; DOS INT 21h subfunction called:
;
;   AH=49h     free memory block (ES = paragraph segment to free)
; ============================================================================
