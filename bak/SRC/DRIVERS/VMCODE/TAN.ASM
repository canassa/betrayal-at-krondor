; ============================================================================
; Vmcode.OVL.TAN -- Tandy 1000 / PCjr video driver chunk (6501 bytes, 0x1965)
;
; Shipped with "Betrayal at Krondor" (Dynamix / Sierra, 1993). Image base
; 0000:0000.
;
; The chunk is one of eight interchangeable graphics drivers in Vmcode.ovl.
; KRONDOR.EXE loads it via the RES-archive loader, runs its init prologue
; once, then snapshots its 50-slot vtable template into the host's
; g_renderer_vtable @ 39ae:2ac6 for ordinary far-call dispatch.
;
; The `tan_slotN` suffix is the actual vtable index (0..49). The vtable
; starts at chunk:0x020A; the first 10 bytes are init scratch. See "How the
; engine dispatches into this chunk" below for the vtable layout.
; ----------------------------------------------------------------------------
; Content: 44 functions, the 50-slot vtable template, the 19-entry
;   callback-table mirror, the inter-function mask LUTs, the 256-byte
;   XLAT LUT @ 0x11A3, the 4-entry sprite-blit dispatch table, and the
;   scratch-global blocks.
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
; This file is the Tandy 1000 / IBM PCjr driver. The engine talks to
; it through a vtable of far function pointers (see "How the engine
; dispatches" below): 50 slots, each slot a different request like
; "draw a line", "blit a sprite", "set the palette". When a slot is
; invoked, this code translates that high-level request into the
; specific byte patterns the Tandy/PCjr video gate-array expects.
;
; Roughly half this file is the dispatch / mode-set / palette / memory-
; management plumbing; the other half is pixel-pushing loops written
; for tight 8086-era cycle budgets (2-pixel-per-byte 4-bpp packing,
; manual partial-byte masks, hand-unrolled inner loops, bank-
; interleaved framebuffer arithmetic).
; ----------------------------------------------------------------------------

; ----------------------------------------------------------------------------
; About the Tandy 1000 / PCjr video hardware
;
; The IBM PCjr (1983-1985) and the Tandy 1000 family (1984-1991)
; both display graphics through a custom ASIC IBM called the
; "Video Gate Array" -- a chip that extends CGA's 4-colour 320x200
; mode with a 16-colour 320x200 mode (BIOS mode 9, this driver's
; target), a 16-colour 160x200 mode (8), and a 4-colour 640x200
; mode (A). The two machines are software-similar but NOT register-
; level identical, which matters a lot for this driver -- see the
; "Tandy-only" caveat below.
;
; The chip name "Video Gate Array" predates IBM's later "Video
; Graphics Array" (VGA, 1987) by roughly four years. They are
; completely unrelated, despite both being abbreviated "VGA" in
; some old documents. In this file, "gate array" or "Video Gate
; Array" always refers to the PCjr/Tandy chip, never to VGA.
;
; --- Tandy-only caveat: this driver does NOT work on a real PCjr ---
;
; The Tandy 1000 and the PCjr expose their gate-array internal
; registers (mode, palette, border, etc.) through DIFFERENT I/O-port
; mechanisms:
;
;   * Tandy 1000: SPLIT-PORT. Write the register *index* to port
;     0x3DA, then write the *data* byte to port 0x3DE. The two
;     ports are physically distinct; you can re-write 0x3DE
;     repeatedly to update the same register.
;     (Tandy 1000 Computer Service Manual (1985), Page 53,
;     "Address 3DA is an address register for port selection inside
;     the Video Array. Address 3DE is the data port.")
;
;   * IBM PCjr: SINGLE-PORT + FLIP-FLOP. Both index and data go to
;     port 0x3DA. An internal flip-flop alternates between "address"
;     and "data" state on every write; reading 0x3DA forces the
;     flip-flop back to "address" state. Port 0x3DE does not
;     exist on PCjr -- it is not in the PCjr Tech Ref's I/O map.
;     (IBM PCjr Technical Reference (Nov 1983), Page 2-63,
;     "is programmed by first writing a register address to port
;     hex 3DA and then writing the data to port hex 3DA. Any I/O
;     'write' operations to hex address 3DA continuously toggle
;     an internal address/data flip-flop.")
;
; This driver writes its palette and gate-array index using the
; Tandy split-port idiom (see tan_slot20 at ~0x0B9E and tan_slot26
; at ~0x16FE, both of which emit `OUT 0x3DA, idx` followed by
; `OUT 0x3DE, value`). On a real PCjr those `OUT 0x3DE` writes
; would land on open bus and the palette would never change. So
; despite the driver name "TAN" being shorthand for the whole
; Tandy/PCjr family, in practice this binary is Tandy-only.
;
; The CRT/Processor Page Register at port 0x3DF (see below) is
; identical on Tandy and PCjr -- the page-flip writes in init,
; tan_slot8 and tan_slot28 would work on both machines. But the
; palette path would not, so we treat the driver as Tandy.
;
; --- I/O ports used by this driver ---
;
; The Tandy gate-array exposes TWO unrelated register spaces to
; the CPU:
;
;   A) Gate-array internal registers (mode-control, palette mask,
;      border colour, the 16 palette entries 0x10..0x1F, etc.),
;      addressed via the Tandy split-port index/data pair on
;      0x3DA / 0x3DE.
;   B) The CRT/Processor Page Register, a STANDALONE 8-bit
;      write-only register at its own dedicated port 0x3DF.
;
; This driver touches (B) on the hot path (the four `OUT 0x3DF, 0xNN`
; writes in init, tan_slot8, tan_slot28) and (A) only for palette
; programming (tan_slot20, tan_slot26).
;
;   Port 0x3DA  -- (A) On WRITE: Video Gate Array index register
;                  (Tandy split-port mode). Writing a byte here
;                  selects which gate-array internal register the
;                  NEXT write to 0x3DE will program.
;                  -- On READ: the CRTC-compatible display-status
;                  register. Per IBM PCjr Tech Ref Page 2-73 and
;                  Tandy 1000 Service Manual Page 59:
;                      bit 0 = +Display Enable (1 while beam is on
;                              screen, 0 during ANY blanking -- H-
;                              or V-blank). Cannot distinguish
;                              H-blank from V-blank by itself.
;                      bit 1 = Light-pen trigger set.
;                      bit 2 = Light-pen switch made.
;                      bit 3 = +Vertical Retrace (1 only during the
;                              vertical retrace period each frame).
;                  Read and write share the same port number but
;                  are separate hardware cycles, so the two roles
;                  do not conflict.
;   Port 0x3DE  -- (A) Video Gate Array data register (Tandy
;                  split-port mode only). Writing a byte here
;                  programs the gate-array register whose index
;                  was previously written to 0x3DA. Used at
;                  runtime only by the palette path (tan_slot20,
;                  tan_slot26) to load palette entries 0x10..0x1F.
;                  Does NOT exist on a real PCjr (see "Tandy-only
;                  caveat" above).
;   Port 0x3DF  -- (B) CRT/Processor Page Register. SEPARATE from
;                  the gate-array index/data ports above. 8-bit
;                  write-only; you cannot read this register back.
;                  Per IBM PCjr Tech Ref Page 2-79 and Tandy 1000
;                  Service Manual Page 60:
;                      bits 0-2  CRT Page    (which 16-KiB block
;                                             of physical RAM the
;                                             gate array scans out
;                                             to the monitor)
;                      bits 3-5  Processor Page (which 16-KiB
;                                             block the CPU sees
;                                             at the B800: window)
;                      bits 6-7  Video Address Mode
;                                  00 = alpha / text modes
;                                  01 = low-res graphics
;                                       (CGA-compat 4-colour, 16K)
;                                  10 = high-res graphics
;                                       (PCjr 16-colour, 32K --
;                                       this is what mode 9 uses)
;                                  11 = unused / reserved
;                  In 32-KiB modes (mode 9 included) bit 0 of the
;                  CRT-page field is ignored: the gate array
;                  fetches two consecutive 16-KiB banks together.
;                  (Note on PCjr quirks: the PCjr's Tech Ref names
;                  the CPU-page field's bits "Processor Page 1, 2,
;                  3" -- the LSB is hard-wired to zero, so PCjr can
;                  only place the CPU window on even 16-KiB
;                  boundaries. Tandy treats bits 3-5 as a plain
;                  3-bit field and allows every boundary. This
;                  driver only emits values that have the
;                  low-bit-zero pattern anyway, so it happens to
;                  produce valid CRT/Processor selections on both
;                  machines.)
;
; The status-port polling in tan_set_crt_page_and_wait_vsync (mask
; 0x08 = bit 3 = vertical retrace) waits specifically for V-blank.
; The poll in tan_slot26 (mask 0x01 = bit 0 = "display enable")
; goes low during EITHER H- or V-blank, so it returns at the next
; *any-kind* retrace edge -- a wider window that the palette write
; tolerates because gate-array palette writes are also legal
; during horizontal retrace.
; (Both bit interpretations: IBM PCjr Tech Ref Page 2-73.)
;
; --- Decoding the 0x3DF byte values used in this driver ---
;
; Every `OUT 0x3DF, 0xNN` in this driver programs the CRT/Processor
; Page Register described above. Bits 7:6 = 11b in every byte we
; emit, which selects "high-resolution graphics" address mode
; (i.e. 32-KiB-aperture mode-9 layout). Bits 5:3 = CPU page and
; bits 2:0 = CRT page. The four bytes that appear:
;
;   0xE4 = 11_100_100b -> mode=3, CPU page=4, CRT page=4
;   0xE6 = 11_100_110b -> mode=3, CPU page=4, CRT page=6
;   0xF4 = 11_110_100b -> mode=3, CPU page=6, CRT page=4
;   0xF6 = 11_110_110b -> mode=3, CPU page=6, CRT page=6
;
; Pages 4 and 6 each occupy two consecutive 16-KiB banks of the
; gate array's address space (32 KiB total per page-pair), which
; is the natural unit for mode 9's 32-KiB framebuffer. Pages 4+5
; vs 6+7 are the two physical "buffers" used for double-buffered
; page-flipping. CRT and CPU page can be chosen independently --
; you can have the CRT scan one page while the CPU writes into
; the other. tan_slot28 composes the byte at runtime by starting
; from 0xE4 and OR'ing in bit 1 (CRT page +2 -> page 6) and bit 4
; (CPU page +2 -> page 6) according to which combination is
; needed.
;
; --- Gate-array palette / overscan programming ---
;
; To set a palette entry on Tandy (tan_slot20 and tan_slot26):
;   1. OUT 0x3DA, 0x10+idx   -- gate-array palette regs live at
;                               internal indices 0x10..0x1F (one
;                               per palette slot 0..15). Writing
;                               the index selects which one is
;                               targeted by the next data write.
;                               (IBM PCjr Tech Ref Page 2-71;
;                               Tandy 1000 Service Manual Page 53.)
;   2. OUT 0x3DE, colour     -- write the 4-bit IRGB value
;                               (bit 0 = Blue, bit 1 = Green,
;                               bit 2 = Red, bit 3 = Intensity).
; The overscan / border colour can also be written through gate-
; array internal register 0x02 (same 4-bit IRGB format), but this
; driver delegates it to the BIOS via INT 10h AX=1001h (forwarded
; by the BIOS to the gate-array overscan latch).
; tan_slot26 additionally rate-limits the palette pair to a
; retrace edge so the on-screen colour change is glitch-free --
; required because the gate array's palette table is read by the
; pixel-shift logic in real time, and unsynchronised writes can
; produce visible flicker (Tandy 1000 Service Manual Page 55:
; "the palette should be accessed during vertical or horizontal
; blanking").
;
; --- Framebuffer layout ---
;
; Mode 9 (320x200, 16-colour) framebuffer is 32 KiB total (= 320
; * 200 * 4 bits / 8 = 32000 bytes, with 768 unused bytes padding
; out the 32-KiB aperture). The gate array maps it into the CPU's
; B800: segment via the CRT/Processor Page Register described
; above. Each byte holds two horizontally-adjacent pixels:
;
;       bit 7 6 5 4 | 3 2 1 0
;       pixel 0     | pixel 1     (high nibble = left, low = right)
;
; (Convention. IBM's Tech Ref does not state nibble order
; explicitly, but every contemporary emulator (DOSBox, MAME's
; pc_t1t, PCem) and every Tandy-era game we have inspected,
; including this driver, packs high-nibble-left.)
;
; Each 4-bit field is an INDEX into one of the 16 gate-array
; palette registers at internal indices 0x10..0x1F, each holding
; a 4-bit IRGB screen colour. So a pixel value of 0x5 in the
; framebuffer looks up palette register 0x15, and the screen
; shows whatever IRGB colour 0..15 was loaded there.
;
; Page-flip / double-buffering: the CRT/Processor Page Register
; remaps which 32 KiB of physical RAM the CPU sees at B800: and
; which the CRT scans. The 16-colour 320x200 mode uses TWO
; adjacent 16-KiB banks (32 KiB total) per surface, hence the
; CRT-page=4 / CPU-page=4 init pair: CRT scans pages 4+5 while
; the CPU also writes into pages 4+5, viewed through B800:.
; Page flip moves CRT to pages 6+7 and CPU to pages 6+7 (i.e.
; the 0xF6 byte). When no separate physical page is available
; (only ~32 KiB total), this driver falls back to a CPU-side
; alias at 0xB000 (see tan_init step 6 + g_wTanPageFlipExtraBit).
; The alias swap is centralised in tan_slot28.
;
; --- Bank-interleaved scanlines (same trick as CGA, extended) ---
;
; The gate array (like CGA, but extended) splits the mode-9
; framebuffer into 4 banks of 8 KiB each, by scanline modulo 4.
; This wires the 200-line display to a 50-line CRTC row counter:
;
;       rows  0, 4,  8, ..., 196 -> base 0x0000, +160 per step-of-4
;       rows  1, 5,  9, ..., 197 -> base 0x2000, +160 per step-of-4
;       rows  2, 6, 10, ..., 198 -> base 0x4000, +160 per step-of-4
;       rows  3, 7, 11, ..., 199 -> base 0x6000, +160 per step-of-4
;
; Per Tandy 1000 Service Manual Page 50 (verbatim layout of
; banks): "0000-1F3FH: 00 Scans (0,4,8,...196); 2000-3F3FH: 01
; Scans (1,5,9,...197); ...". Address of pixel (x, y) within a
; 32-KiB page:
;       bank   = y & 3
;       row    = y >> 2
;       offset = bank*0x2000 + row*160 + (x >> 1)
;       nibble = (x & 1) == 0 ? high : low
;
; Consecutive vertical pixels are NOT contiguous in memory: row
; N+1 is 0x2000 bytes away from row N within the same "row
; quad", and the jump from row 3 back to row 4 wraps via
; `-0x5F60` (which is `0x6000 - 0xA0`, i.e. "step out of bank 3
; then add one full row of 160 = 0xA0 bytes"). Every
; line/rect/sprite blitter in this file deals with this via:
;   (a) a precomputed 200-entry scanline-offset LUT built in
;       tan_init at scratch:[0x6F2] (each row's flat byte offset
;       stamped through 4 banks at +0x2000 each, with -0x5F60
;       wrap between quads); and
;   (b) a runtime `ADD DI, 0x2000` + bank-wrap test
;       (`TEST DI, 0x8000 / AND DI, 0x7FFF / ADD DI, 0xA0`)
;       which is the per-row 4-bank step pattern visible inside
;       tan_slot2 / tan_slot29 / tan_slot30 inner loops.
;
; Each row is 320 pixels * 4 bits = 160 bytes; per bank, 50 rows
; * 160 bytes = 8000 bytes plus 192 bytes of pad to the bank's
; 8-KiB boundary.
;
; (See cga.asm "About the CGA hardware" for the underlying
; rationale; TAN extends CGA's 2-bank, 2-bpp scheme to 4-bank,
; 4-bpp.)
;
; --- Primary-source references summary ---
;
;   * IBM PCjr Technical Reference (Nov 1983), §2 "Display
;     Subsystem", Pages 2-63 to 2-80 -- canonical for the PCjr
;     gate-array register layout, port map, and status-bit
;     definitions.
;   * Tandy 1000 Computer Service Manual (1985), §"Video
;     Subsystem", Pages 50-60 -- canonical for the Tandy
;     split-port mechanism (Page 53), bank layout (Page 50),
;     palette procedure (Page 53), retrace-sync rule (Page 55),
;     status bits (Page 59), and 0x3DF bit layout (Page 60).
; ----------------------------------------------------------------------------

; ----------------------------------------------------------------------------
; How the engine dispatches into this chunk
;
; Vmcode.OVL is a flat archive of driver chunks; one chunk per
; supported adapter. The host engine:
;
;   1. Loads the selected chunk into a freshly-allocated segment.
;   2. Calls the chunk's `_start` (tan_init) as a far function,
;      passing two args on the stack: a paragraph count for the
;      driver's private working segment, and a far pointer to the
;      host's "service callback" table (19 host-provided routines
;      this code needs from the engine, e.g. file I/O, palette
;      callbacks, etc.).
;   3. tan_init copies the 19 host callbacks into chunk-local mirror
;      slots at CS:0x02AA (g_apfnTanHostCallbacks), configures the
;      framebuffer, then returns DX:SI = (CS, 0x020A) -- a far
;      pointer to the vtable template at g_apfnTanVtable+10.
;   4. The host stamps the chunk's load segment into every segment-
;      half of that template (50 slots * 4 bytes = 200 bytes) and
;      copies the result into a global renderer vtable at 39ae:2ac6
;      in host RAM.
;   5. Every subsequent rendering call from the game is a far CALL
;      through that vtable -- never a direct CALL into this file.
;      The TAN driver thus only sees a stream of slot invocations
;      after init.
;
; Slot calling convention: most slots are __cdecl16far (push args
; right-to-left, far call, caller cleans the stack). A handful of
; inner functions (tan_slot10, tan_slot37, tan_slot36,
; tan_slot16, tan_slot38) instead take register-passed args because
; they're called from within this chunk for speed. Each function's
; plate comment lists the actual arg convention.
;
; The 50-slot vtable layout: the FIRST 10 bytes of g_apfnTanVtable
; (chunk:0x200..0x209) are scratch words used by init itself; the
; host snapshot begins at chunk:0x20A. Slot N occupies bytes
; [0x20A + N*4 .. 0x20A + N*4 + 3] (a 16-bit offset followed by a
; 16-bit segment placeholder the host stamps with the chunk seg).
;
; See SRC\DRIVERS\VMCODE\CGA.ASM for the worked pilot example.
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
; - Memory accesses use one of three segments (same conventions as
;   CGA):
;     CS:  -- chunk-local globals, dispatch tables, mask LUTs, the
;             XLAT LUT, runtime scratch words.
;     DS:  -- usually the chunk's "scratch DS", a private working
;             segment allocated `paragraph_count` paragraphs past the
;             caller's DS at init time. Every function that needs
;             scratch loads DS from `CS:[0x206]` (g_wTanChunkDataSeg)
;             on entry and restores the caller's DS before returning.
;     ES:  -- usually the Tandy framebuffer (B800, or the B000 alias
;             when in page-flip-not-available mode) or, for capture/
;             save-rect helpers, the caller-supplied destination
;             buffer.
;
; - Forward-reference labels: a handful of NEAR functions are called
;   from before their PROC appears in source order. They're declared
;   via `LABEL NEAR` at an ORG'd address (then ORG snapped back to 0)
;   so the assembler's pass-1 symbol resolution sees the correct
;   offset; the actual function body further down ends up at the
;   same offset via linear ORG progression. See the
;   "Forward-reference NEAR labels" block below.
;
; - Local labels inside a function use one of two styles, both with
;   a short per-function prefix to avoid namespace collisions:
;     * `<fn>_<verb>:`  (e.g. `tan_slot2_pure_vert:`,
;       `tan_pgscan_loop:`)
;     * `@@b<hex>_<verb>:` for the four near-identical sprite-row
;       sub-cores in tan_slot29 (so the labels stay short while the
;       hex disambiguates between the otherwise-identical bodies
;       at 0x144E / 0x14BB / 0x1528 / 0x15A1).
;
; - Calling conventions vary per function. Each function's plate
;   comment lists Inputs / Outputs / register ABI in domain terms.
;   Do not assume cdecl stack args -- inner cores use register
;   passing, host-callable slots use __cdecl16far.
;
; - The right-column hex sequences (e.g. `; 8B EC`) are the encoded
;   instruction bytes. They are NOT part of the source the assembler
;   consumes (they're TASM line comments).
; ----------------------------------------------------------------------------

                .8086
                .MODEL  TINY
                .CODE

; Shared engine graphics-context STRUC (field names -> the raw struct-
; relative offsets this driver reads/writes through its scratch DS).
                INCLUDE gfxctx.inc

                ORG     0
                ASSUME  ds:NOTHING, es:NOTHING

; ----------------------------------------------------------------------------
; Forward-reference NEAR labels for functions called before their PROC
; appears in source order. We use a `LABEL NEAR` at an ORG'd address,
; then immediately ORG back, so the label exists with the right offset
; for the assembler's pass-1 symbol resolution. The actual function body
; further down ends up at the same offset (via the linear ORG progression)
; and gets a different PROC-style label that aliases here.
; ----------------------------------------------------------------------------
                ORG     0F13H
tan_helper_0f13_fwd LABEL NEAR
                ORG     0F87H
tan_slot28_fwd      LABEL NEAR
                ORG     12A3H
tan_slot29_fwd      LABEL NEAR
                ORG     1618H
tan_slot29_skip     LABEL NEAR
                ORG     0

; ----------------------------------------------------------------------------
; Dual-use storage equates.
;
; Unlike CGA (which packs its dual-use globals INSIDE the init prologue's
; instruction bytes), TAN's dual-use scratch lives in the FIRST 10 bytes
; of the vtable region itself: chunk:[0x200..0x209]. Those bytes are
; addressed as `CS:[0x200]` etc. by init, then the host snapshot starts
; from chunk:0x20A (init returns SI=0x20A).
; ----------------------------------------------------------------------------
g_wTanMemConvEndSeg     equ 0200H        ; ushort -- total - requested paragraphs
g_wTanMemConvBaseSeg    equ 0202H        ; ushort -- total conv. mem (paragraphs)
g_wTanMemConvOkFlag     equ 0204H        ; ushort -- tan_alloc_backbuffer_pages result
g_wTanChunkDataSeg      equ 0206H        ; ushort -- scratch-DS paragraph
g_wTanChunkDataBaseOff  equ 0208H        ; ushort -- saved paragraph count

; ============================================================================
; tan_init -- chunk initialiser (PROC FAR, called via the host's video_init).
; chunk:0x0000..0x00E5
;
; CALLER ABI (host-side far call, __cdecl16far):
;   [BP+0x06]  ushort  backbuffer_paragraphs  (e.g. 0x400 = 16 KiB / 16)
;   [BP+0x08]  ushort  host_callbacks_off
;   [BP+0x0a]  ushort  host_callbacks_seg
;
; INIT SEQUENCE:
;   1. [0x00..0x18]  Copy 0x26 words (76 bytes = 19 far ptrs) from
;      DS:SI = host_callbacks_seg:host_callbacks_off into chunk-local
;      mirror at CS:0x02AA (g_apfnTanHostCallbacks).
;      NOTE: target DI=0x2AA differs from CGA (0x2A0) -- see vtable
;      region for layout. Other chunk slots later CALLF [0x02AA+N].
;   2. [0x19..0x32]  Save paragraph count to g_wTanChunkDataBaseOff,
;      compute scratch-DS as caller_DS + count/16, store to
;      g_wTanChunkDataSeg, load into DS.
;   3. [0x34..0x3D]  scratch:[0x21] := 0x10. BIOS INT 10h AX=0x0009
;      sets Tandy/PCjr 16-colour 320x200 mode.
;   4. [0x3E..0x5D]  Configure CRT/Processor Page Register at 0x3DF
;      (NOT a gate-array internal write -- this is the standalone
;      page register; see hardware primer above):
;        OUT 0x3DF, 0xE4 -- CRT page 4 + CPU page 4 + addr mode 3
;                           (the 16-colour 320x200 page-pair).
;      Then zero the entire 32 KiB B800: framebuffer.
;        OUT 0x3DF, 0xF6 -- swap to CRT page 6 + CPU page 6.
;      Then zero another 32 KiB at B800: (the alt page).
;   5. [0x5E..0x61]  Call tan_select_display_pages (far) to probe
;      separate display + processor pages via tan_find_free_b800_page.
;   6. [0x62..0x7E]  If both probes returned 0xB800 (i.e. no usable
;      separate pages found), force processor page to 0xB000 (alias)
;      and set g_wTanPageFlipExtraBit = 1.
;   7. [0x80..0x90]  Otherwise call tan_alloc_backbuffer_pages(0x0C00)
;      to reserve 48 KiB up top; on AL==0 (alloc failed) -> bail.
;   8. [0x91..0x9C]  Copy probed display/processor segments into
;      scratch:[0x14] and scratch:[0x12] (publicly readable mirrors).
;   9. [0x9D..0xB8]  INT 21h/AH=48h alloc 0x800 paragraphs (32 KiB),
;      stash at scratch:[0x10], zero it.
;  10. [0xB9..0xD7]  Build Tandy bank-interleaved row-offset LUT at
;      scratch:[0x6F2] (50 entries x 8 bytes = 400 bytes), each entry
;      stamping 4 banks at +0x2000 then wrapping (mod 0x8000).
;  11. [0xD8..0xE4]  AL := 3, write scratch:[0x1D] (mode flag).
;      Return (DX=CS, SI=0x20A) -- far pointer to vtable.
;
; RETURN:
;   AL    -- 3 on success, 0 on memory failure (one of three early exits).
;   DX:SI -- CS:0x020A, far pointer to g_apfnTanVtable.
; ============================================================================
_start          LABEL   BYTE
tan_init        PROC    FAR
                PUSH    BP                      ; 55
                MOV     BP, SP                  ; 8B EC
                PUSH    DS                      ; 1E
                PUSH    SI                      ; 56
                PUSH    DI                      ; 57
                MOV     DI, 02AAH               ; BF AA 02  <- g_apfnTanHostCallbacks
                PUSH    CS                      ; 0E
                POP     ES                      ; 07
                MOV     SI, [BP+8]              ; 8B 76 08  arg1.off
                MOV     DS, [BP+0AH]            ; 8E 5E 0A  arg1.seg
                MOV     CX, 0026H               ; B9 26 00  38 words = 76 bytes
                REP     MOVSW                   ; F3 A5
                POP     DI                      ; 5F
                POP     SI                      ; 5E
                POP     DS                      ; 1F
                MOV     AX, [BP+6]              ; 8B 46 06  arg0: paragraph count

                MOV     cs:[208H], AX           ; 2E A3 08 02  g_wTanChunkDataBaseOff
                SHR     AX, 1                   ; D1 E8
                SHR     AX, 1                   ; D1 E8
                SHR     AX, 1                   ; D1 E8
                SHR     AX, 1                   ; D1 E8   AX /= 16
                PUSH    DS                      ; 1E
                PUSH    DI                      ; 57
                MOV     BX, DS                  ; 8C DB
                ADD     AX, BX                  ; 03 C3
                MOV     cs:[206H], AX           ; 2E A3 06 02  g_wTanChunkDataSeg
                MOV     DS, AX                  ; 8E D8         DS = scratch segment

                MOV     BYTE PTR ds:[GfxContext.bActiveVgaMode], 10H  ; C6 06 21 00 10   active-mode marker
                MOV     AX, 0009H               ; B8 09 00
                INT     10H                     ; CD 10            BIOS mode 9 (Tandy 320x200x16)

                ; ----- Set CRT/Processor Page Register (port 0x3DF) -----
                ; 0xE4 = mode 3, CPU page 4, CRT page 4. See hardware
                ; primer above for the bit layout; BIOS mode 9 leaves
                ; the gate-array's internal mode register already in
                ; the 16-colour 320x200 state, so all we need to do
                ; here is point CRT and CPU at the same 32 KiB page.
                MOV     DX, 03DFH               ; BA DF 03
                MOV     AL, 0E4H                ; B0 E4
                OUT     DX, AL                  ; EE

                ; ----- Zero 32 KiB at B800:0000 (page 4) -----
                MOV     AX, 0B800H              ; B8 00 B8
                MOV     ES, AX                  ; 8E C0
                MOV     CX, 4000H               ; B9 00 40
                XOR     AX, AX                  ; 33 C0
                XOR     DI, DI                  ; 33 FF
                REP     STOSW                   ; F3 AB

                ; ----- Swap to the alternate page pair, zero again -----
                ; 0xF6 = mode 3, CPU page 6, CRT page 6.
                MOV     AL, 0F6H                ; B0 F6
                OUT     DX, AL                  ; EE
                MOV     CX, 4000H               ; B9 00 40
                XOR     AX, AX                  ; 33 C0
                XOR     DI, DI                  ; 33 FF
                REP     STOSW                   ; F3 AB

                ; ----- Probe display + processor pages -----
                PUSH    CS                      ; 0E    fake far-call return seg
                CALL    NEAR PTR tan_select_display_pages   ; E8 84 00  near call, callee RETFs

                CMP     WORD PTR ds:[06E4H], 0B800H  ; 81 3E E4 06 00 B8
                JNZ     SHORT tan_init_try_alloc     ; 75 16
                CMP     WORD PTR ds:[06E6H], 0B800H  ; 81 3E E6 06 00 B8
                JNZ     SHORT tan_init_try_alloc     ; 75 0E
                ; Both probes landed at 0xB800 -> no separate pages found.
                ; Use B000 alias for the processor page and flag it.
                MOV     WORD PTR ds:[06E2H], 1       ; C7 06 E2 06 01 00
                MOV     WORD PTR ds:[06E4H], 0B000H  ; C7 06 E4 06 00 B0
                JMP     SHORT tan_init_copy_pages    ; EB 11

tan_init_try_alloc:
                MOV     AX, 0C00H               ; B8 00 0C
                PUSH    AX                      ; 50
                PUSH    CS                      ; 0E
                CALL    NEAR PTR tan_alloc_backbuffer_pages ; E8 0E 01
                ADD     SP, 2                   ; 83 C4 02
                OR      AL, AL                  ; 0A C0
                JNZ     SHORT tan_init_copy_pages ; 75 02
                JMP     SHORT tan_init_exit     ; EB 49

tan_init_copy_pages:
                MOV     AX, ds:[06E4H]          ; A1 E4 06
                MOV     ds:[GfxContext.wVgaFrontPageBase], AX            ; A3 14 00
                MOV     AX, ds:[06E6H]          ; A1 E6 06
                MOV     ds:[GfxContext.wVgaPage2Base], AX            ; A3 12 00

                ; ----- Alloc 32 KiB (0x800 paragraphs) scratch buffer -----
                MOV     AX, 4800H               ; B8 00 48
                MOV     BX, 0800H               ; BB 00 08
                INT     21H                     ; CD 21
                JNC     SHORT tan_init_zero_scratch ; 73 04
                XOR     AX, AX                  ; 33 C0
                JMP     SHORT tan_init_exit     ; EB 2F

tan_init_zero_scratch:
                MOV     ds:[GfxContext.wVgaPage1Base], AX            ; A3 10 00
                MOV     ES, AX                  ; 8E C0
                MOV     CX, 4000H               ; B9 00 40
                XOR     AX, AX                  ; 33 C0
                XOR     DI, DI                  ; 33 FF
                REP     STOSW                   ; F3 AB

                ; ----- Build Tandy row-offset LUT at scratch:[0x6F2] -----
                ; 50 row-quad iterations; each writes 4 STOSWs at +0x2000
                ; then subtracts 0x5F60 to wrap to the next quad's base.
                MOV     CX, 0032H               ; B9 32 00       50 iterations
                MOV     DI, GfxContext.pRow_offset_lut               ; BF F2 06
                MOV     AX, DS                  ; 8C D8
                MOV     ES, AX                  ; 8E C0           ES = scratch DS
                XOR     AX, AX                  ; 33 C0
                CLD                             ; FC
tan_init_lut_loop:
                STOSW                           ; AB              bank 0 entry
                ADD     AX, 2000H               ; 05 00 20
                STOSW                           ; AB              bank 1 entry
                ADD     AX, 2000H               ; 05 00 20
                STOSW                           ; AB              bank 2 entry
                ADD     AX, 2000H               ; 05 00 20
                STOSW                           ; AB              bank 3 entry
                SUB     AX, 5F60H               ; 2D 60 5F
                LOOP    SHORT tan_init_lut_loop ; E2 EE

                MOV     AL, 3                   ; B0 03           success
tan_init_exit:
                MOV     ds:[GfxContext.bVideoAdapter], AL            ; A2 1D 00        driver-installed flag
                MOV     DX, CS                  ; 8C CA
                MOV     SI, 020AH               ; BE 0A 02        offset of vtable template
                POP     DI                      ; 5F
                POP     DS                      ; 1F
                POP     BP                      ; 5D
                RETF                            ; CB
tan_init        ENDP

; ============================================================================
; tan_select_display_pages -- probe two Tandy free pages via page register.
; chunk:0x00E6..0x010C
;
; Twice:
;   1. Re-program the CRT/Processor Page Register at port 0x3DF, picking
;      a CPU page (and corresponding marker word) for the probe.
;   2. Call tan_find_free_b800_page(marker) to scan B800: for that
;      marker pattern; on hit, that 16 KiB page is "free".
;   3. Stash result in scratch:[0x6E4] (display) or scratch:[0x6E6]
;      (processor).
;
; ABI: __cdecl16far, no args. RETF.
; Called from tan_init at 0x005F.
; ============================================================================
tan_select_display_pages PROC FAR
                MOV     DX, 03DFH               ; BA DF 03
                MOV     AL, 0E4H                ; B0 E4
                OUT     DX, AL                  ; EE              page reg = 0xE4 (CRT 4 / CPU 4)
                MOV     AX, 1414H               ; B8 14 14        marker
                PUSH    AX                      ; 50
                CALL    NEAR PTR tan_find_free_b800_page ; E8 62 00
                ADD     SP, 2                   ; 83 C4 02
                MOV     ds:[06E4H], AX          ; A3 E4 06

                MOV     DX, 03DFH               ; BA DF 03
                MOV     AL, 0F4H                ; B0 F4           page reg = 0xF4 (CRT 4 / CPU 6)
                OUT     DX, AL                  ; EE
                MOV     AX, 1515H               ; B8 15 15        marker
                PUSH    AX                      ; 50
                CALL    NEAR PTR tan_find_free_b800_page ; E8 4F 00
                ADD     SP, 2                   ; 83 C4 02
                MOV     ds:[06E6H], AX          ; A3 E6 06
                RETF                            ; CB
tan_select_display_pages ENDP

; ============================================================================
; tan_set_pages_and_clear -- (re)set Tandy pages and zero them.
; chunk:0x010D..0x013F
;
; Used by the chunk's mode-set / present-rect plumbing to (re-)establish
; the page pair after a mode change. Same sequence as init: set CRT/CPU
; pages, find a free B800 page via marker scan, store seg in scratch
; globals; finally hard-code processor segment to B800.
;
; ABI: __cdecl16far, no args. RETF. Reachable via vtable.
; ============================================================================
tan_set_pages_and_clear PROC FAR
                MOV     BX, 0607H               ; BB 07 06    BL=7 (CPU page) BH=6 (CRT page)
                CALL    NEAR PTR tan_set_crt_page_and_wait_vsync ; E8 2D 00
                MOV     AX, 1414H               ; B8 14 14
                PUSH    AX                      ; 50
                CALL    NEAR PTR tan_find_free_b800_page ; E8 3B 00
                ADD     SP, 2                   ; 83 C4 02
                MOV     ds:[06E6H], AX          ; A3 E6 06
                MOV     BX, 0706H               ; BB 06 07    BL=6 (CPU page) BH=7 (CRT page)
                CALL    NEAR PTR tan_set_crt_page_and_wait_vsync ; E8 1A 00
                MOV     AX, 1515H               ; B8 15 15
                PUSH    AX                      ; 50
                CALL    NEAR PTR tan_find_free_b800_page ; E8 28 00
                ADD     SP, 2                   ; 83 C4 02
                MOV     ds:[06E4H], AX          ; A3 E4 06
                MOV     AX, ds:[06E6H]          ; A1 E6 06
                MOV     ds:[GfxContext.wVgaFrontPageBase], AX            ; A3 14 00
                MOV     WORD PTR ds:[GfxContext.wVgaPage2Base], 0B800H ; C7 06 12 00 00 B8
                RETF                            ; CB
tan_set_pages_and_clear ENDP

; ============================================================================
; tan_set_crt_page_and_wait_vsync -- set CRT/CPU page, wait vblank.
; chunk:0x0140..0x0154
;
; INT 10h AX=0x0583 (Tandy/PCjr: set both CRT and CPU page
; registers from BX). The BL=CPU-page / BH=CRT-page convention is
; the prevailing one across PCjr/Tandy game-engine source and is
; consistent with the bit ordering of port 0x3DF itself (low bits
; = CRT, high bits = CPU), but we could not locate a primary IBM
; document that states the register assignment verbatim -- treat
; this register binding as inferred from usage (the INT 10h AH=05h
; AL=83h register binding is unresolved).
;
; Then poll 0x3DA bit 3 to align with vertical retrace -- first
; wait until NOT in retrace (mid-frame), then wait until bit 3
; sets again, so we return at the start of the next vertical
; retrace period (tear-free updates). Bit 3 is the canonical
; vertical-retrace status flag per IBM PCjr Tech Ref Page 2-73
; and Tandy 1000 Service Manual Page 59.
;
; ABI: register-passed (BL = CPU page, BH = CRT page). RETF. Far call.
; ============================================================================
tan_set_crt_page_and_wait_vsync PROC FAR
                MOV     AX, 0583H               ; B8 83 05
                INT     10H                     ; CD 10
                MOV     CL, 8                   ; B1 08      bit-3 mask
                MOV     DX, 03DAH               ; BA DA 03   status port
tan_vsync_wait_active:
                IN      AL, DX                  ; EC
                AND     AL, CL                  ; 22 C1
                JNZ     SHORT tan_vsync_wait_active ; 75 FB  wait until NOT in retrace
tan_vsync_wait_blank:
                IN      AL, DX                  ; EC
                AND     AL, CL                  ; 22 C1
                JZ      SHORT tan_vsync_wait_blank  ; 74 FB  wait for retrace start
                RETF                            ; CB
tan_set_crt_page_and_wait_vsync ENDP

; ============================================================================
; tan_find_free_b800_page -- scan B800: for a marker-matching 16 KiB page.
; chunk:0x0155..0x0195
;
; Stamps a 40-word marker (AX value passed in [BP+4]) at B800:0000,
; then scans every paragraph of conventional memory for a 40-word run
; that matches; returns the matching segment paragraph or 0.
;
; Unlike CGA's twin function (which lives at 0x019B with a dual-use
; instruction prologue), TAN's is a plain NEAR PROC with a single
; PUSH BP / PUSH BP prologue and POP ES / POP BP epilogue (the second
; PUSH BP balances against POP ES).
;
; ABI: NEAR call, [BP+4] = ushort marker. Returns AX = matched seg, or 0.
;      Note RET (not RETF).
; ============================================================================
tan_find_free_b800_page PROC NEAR
                PUSH    BP                      ; 55
                MOV     BP, SP                  ; 8B EC
                PUSH    BP                      ; 55          balances POP ES below
                MOV     AX, 0B800H              ; B8 00 B8
                MOV     ES, AX                  ; 8E C0
                MOV     AX, [BP+4]              ; 8B 46 04    marker word
                XOR     DI, DI                  ; 33 FF
                MOV     CX, 0028H               ; B9 28 00
                REP     STOSW                   ; F3 AB        stamp 40 words at B800:0
                XOR     DI, DI                  ; 33 FF
tan_pgscan_new_seg:
                MOV     CX, 0028H               ; B9 28 00
                MOV     ES, DI                  ; 8E C7        ES = scan segment
                MOV     DI, 0FFFEH              ; BF FE FF
tan_pgscan_loop:
                ADD     DI, 2                   ; 83 C7 02
                CMP     AX, ES:[DI]             ; 26 3B 05
                LOOPZ   SHORT tan_pgscan_loop   ; E1 F8
                JCXZ    SHORT tan_pgscan_found  ; E3 0C
                MOV     DI, ES                  ; 8C C7
                ADD     DI, 0400H               ; 81 C7 00 04  advance 16 KiB
                JNZ     SHORT tan_pgscan_new_seg ; 75 E6        until DI wraps to 0
                XOR     AX, AX                  ; 33 C0        not found
                JMP     SHORT tan_pgscan_exit   ; EB 0B
tan_pgscan_found:
                XOR     AX, AX                  ; 33 C0
                XOR     DI, DI                  ; 33 FF
                MOV     CX, 0028H               ; B9 28 00
                REP     STOSW                   ; F3 AB        clear matched page
                MOV     AX, ES                  ; 8C C0
tan_pgscan_exit:
                POP     ES                      ; 07
                POP     BP                      ; 5D
                RET                             ; C3
tan_find_free_b800_page ENDP

; ============================================================================
; tan_alloc_backbuffer_pages -- "is there room above BX paragraphs?" probe.
; chunk:0x0196..0x01FF
;
; INT 12h to query conventional-memory total in KB; shift left by 6 to
; convert KB->paragraphs; store in g_wTanMemConvBaseSeg. Subtract the
; requested paragraph count from the total; store at g_wTanMemConvEndSeg.
; Allocates 1 paragraph via INT 21h/AH=48h, walks the MCB chain to find
; the trailing MCB, and verifies it sits at the conventional-memory tail.
; On success shrinks the trailing MCB by [BP+6] paragraphs to reserve
; space and sets g_wTanMemConvOkFlag := 1; on failure := 0. Frees the
; probe handle, returns AX = g_wTanMemConvOkFlag.
;
; Functionally identical to cga_dos_alloc_far; the differences are the
; CS-relative addresses of the scratch-globals (0x200/0x202/0x204 here
; versus 0xE0/0xE2/0xE4/0xE6 in CGA).
;
; ABI: __cdecl16far(ushort para_count_needed). RETF. AX = 1 / 0.
; ============================================================================
tan_alloc_backbuffer_pages PROC FAR
                PUSH    BP                      ; 55
                MOV     BP, SP                  ; 8B EC
                INT     12H                     ; CD 12       AX = conv mem in KB
                MOV     CL, 6                   ; B1 06
                SHL     AX, CL                  ; D3 E0       KB -> paragraphs
                MOV     cs:[202H], AX           ; 2E A3 02 02  g_wTanMemConvBaseSeg
                SUB     AX, [BP+6]              ; 2B 46 06
                MOV     cs:[200H], AX           ; 2E A3 00 02  g_wTanMemConvEndSeg
                MOV     AH, 48H                 ; B4 48
                MOV     BX, 1                   ; BB 01 00
                INT     21H                     ; CD 21       alloc 1-para probe handle
                MOV     DX, AX                  ; 8B D0
                DEC     AX                      ; 48          back up to MCB
                MOV     BX, 0                   ; BB 00 00
                MOV     ES, AX                  ; 8E C0
                MOV     CL, ES:[BX]             ; 26 8A 0F    MCB.type ('M' / 'Z')
tan_dos_walk_chain:
                MOV     ES, AX                  ; 8E C0
                MOV     BX, 3                   ; BB 03 00
                ADD     AX, ES:[BX]             ; 26 03 07    += MCB.size
                INC     AX                      ; 40
                MOV     BX, 0                   ; BB 00 00
                CMP     ES:[BX], CL             ; 26 38 0F
                JZ      SHORT tan_dos_walk_chain ; 74 EF
                CMP     AX, cs:[200H]           ; 2E 3B 06 00 02
                JBE     SHORT tan_dos_mark_ok   ; 76 10
                CMP     AX, cs:[202H]           ; 2E 3B 06 02 02
                JNZ     SHORT tan_dos_mark_fail ; 75 12
                MOV     BX, 3                   ; BB 03 00
                MOV     AX, [BP+6]              ; 8B 46 06
                SUB     ES:[BX], AX             ; 26 29 07
tan_dos_mark_ok:
                MOV     WORD PTR cs:[204H], 1   ; 2E C7 06 04 02 01 00
                JMP     SHORT tan_dos_free_probe ; EB 07
tan_dos_mark_fail:
                MOV     WORD PTR cs:[204H], 0   ; 2E C7 06 04 02 00 00
tan_dos_free_probe:
                MOV     ES, DX                  ; 8E C2
                MOV     AH, 49H                 ; B4 49
                INT     21H                     ; CD 21       free probe handle
                MOV     AX, cs:[204H]           ; 2E A1 04 02
                POP     BP                      ; 5D
                RETF                            ; CB
tan_alloc_backbuffer_pages ENDP

; ============================================================================
; g_apfnTanVtable -- 50-slot renderer-vtable template (with leading scratch).
; chunk:0x0200..0x02C7
;
; Layout differs slightly from CGA: the first 10 bytes (0x0200..0x0209)
; are scratch words used by init (g_wTanMemConvEndSeg etc.); the host
; snapshot begins at chunk:0x020A (init returns SI=0x020A) and the
; vtable proper is 50 4-byte slots from there.
;
; Each entry: (offset_word, segment_placeholder_word=0); the host
; STOSWs the chunk's load segment into every segment half post-init.
; ============================================================================
g_apfnTanVtable LABEL DWORD
                ; --- 0x0200..0x0209: scratch words (zero-initialised) ---
                DW      0, 0                    ; 0x200/0x202 -- g_wTanMemConvEndSeg / BaseSeg
                DW      0, 0                    ; 0x204/0x206 -- g_wTanMemConvOkFlag / ChunkDataSeg
                DW      0                       ; 0x208       -- g_wTanChunkDataBaseOff
                ; --- 0x020A..0x02D1: 50-slot vtable proper.
                ; Host snapshot begins here (init returns SI=0x020A).
                ; Each slot: (offset, segment_placeholder_zero). The
                ; function-name suffixes ("tan_slotN") follow the host's
                ; vtable index — slot index N maps to vtable offset N*4
                ; from 0x020A. Slots 0..1 are NULL.
                DW      0,      0               ; slot 0  -- NULL
                DW      0C8EH,  0               ; slot 1  -- tan_slot1 @ 0x0C8E (host name)
                DW      05F6H,  0               ; slot 2  -- tan_slot2 @ 0x05F6
                DW      0C74H,  0               ; slot 3  -- tan_slot3 @ 0x0C74
                DW      0FDDH,  0               ; slot 4  -- tan_slot4 @ 0x0FDD
                DW      0DB0H,  0               ; slot 5  -- tan_slot5 @ 0x0DB0
                DW      0E30H,  0               ; slot 6  -- tan_slot6 @ 0x0E30
                DW      0E4FH,  0               ; slot 7  -- tan_slot7 @ 0x0E4F
                DW      0F46H,  0               ; slot 8  -- tan_slot8 @ 0x0F46
                DW      02F6H,  0               ; slot 9  -- tan_unimplemented_slot
                DW      0319H,  0               ; slot 10 -- tan_slot10 @ 0x0319
                DW      02FEH,  0               ; slot 11 -- tan_slot11 @ 0x02FE
                DW      02F6H,  0               ; slot 12 -- tan_unimplemented_slot
                DW      0BEFH,  0               ; slot 13 -- tan_slot13 @ 0x0BEF
                DW      0C30H,  0               ; slot 14 -- tan_slot14 @ 0x0C30
                DW      02F6H,  0               ; slot 15 -- tan_unimplemented_slot
                DW      04B6H,  0               ; slot 16 -- tan_slot16 @ 0x04B6
                DW      1125H,  0               ; slot 17 -- tan_slot17 @ 0x1125
                DW      02F6H,  0               ; slot 18 -- tan_unimplemented_slot
                DW      0B55H,  0               ; slot 19 -- tan_slot19 @ 0x0B55
                DW      0B9EH,  0               ; slot 20 -- tan_slot20 @ 0x0B9E
                DW      0EC7H,  0               ; slot 21 -- tan_slot21 @ 0x0EC7
                DW      0EEAH,  0               ; slot 22 -- tan_slot22 @ 0x0EEA
                DW      02F6H,  0               ; slot 23 -- tan_unimplemented_slot
                DW      1907H,  0               ; slot 24 -- tan_slot24 @ 0x1907
                DW      1908H,  0               ; slot 25 -- tan_slot25 @ 0x1908
                DW      1918H,  0               ; slot 26 -- tan_slot26 @ 0x1918
                DW      08EDH,  0               ; slot 27 -- tan_slot27 @ 0x08ED
                DW      0F87H,  0               ; slot 28 -- tan_slot28 @ 0x0F87
                DW      12A3H,  0               ; slot 29 -- tan_slot29 @ 0x12A3
                DW      1634H,  0               ; slot 30 -- tan_slot30 @ 0x1634
                DW      16FEH,  0               ; slot 31 -- tan_slot31 @ 0x16FE
                DW      1706H,  0               ; slot 32 -- tan_slot32 @ 0x1706
                DW      1715H,  0               ; slot 33 -- tan_slot33 @ 0x1715
                DW      02F6H,  0               ; slot 34 -- tan_unimplemented_slot
                DW      02F6H,  0               ; slot 35 -- tan_unimplemented_slot
                DW      0425H,  0               ; slot 36 -- tan_slot36 @ 0x0425
                DW      03BEH,  0               ; slot 37 -- tan_slot37 @ 0x03BE
                DW      053FH,  0               ; slot 38 -- tan_slot38 @ 0x053F
                DW      0,      0               ; slot 39 -- NULL
                ; --- Slot 40..49 overlap the callback-table copy region; ---
                ; --- they hold pointers to the RETF stub @ 0x02F6 ---
                DW      02F6H,  0               ; slot 40
                DW      02F6H,  0               ; slot 41
                DW      02F6H,  0               ; slot 42
                DW      02F6H,  0               ; slot 43
                DW      02F6H,  0               ; slot 44
                DW      02F6H,  0               ; slot 45
                DW      02F6H,  0               ; slot 46
                DW      02F6H,  0               ; slot 47
                DW      02F6H,  0               ; slot 48
                DW      02F6H,  0               ; slot 49

; ============================================================================
; g_abTanCallbackTableTail (continuation) -- 0x02D2..0x02F5 (36 bytes).
;
; The "callback table mirror" conceptually covers 0x02AA..0x02F5 (76
; bytes = 19 far ptrs); the first 40 bytes (slots 40..49 of the vtable)
; were already emitted above as part of the 50-slot vtable block, so
; only the trailing 36 bytes appear here. Init's REP MOVSW (CX=0x26
; words at DI=0x02AA) overwrites the whole 76-byte mirror at runtime.
;
; Every entry is initialised to (tan_unimplemented_slot=0x02F6, 0).
; ============================================================================
                DW      02F6H,  0               ; 0x02D2  cb #10
                DW      02F6H,  0               ; 0x02D6  cb #11
                DW      02F6H,  0               ; 0x02DA  cb #12
                DW      02F6H,  0               ; 0x02DE  cb #13
                DW      02F6H,  0               ; 0x02E2  cb #14
                DW      02F6H,  0               ; 0x02E6  cb #15
                DW      02F6H,  0               ; 0x02EA  cb #16
                DW      02F6H,  0               ; 0x02EE  cb #17
                DW      02F6H,  0               ; 0x02F2  cb #18

; ============================================================================
; tan_unimplemented_slot -- 1-byte RETF stub.
; chunk:0x02F6
;
; The unimplemented-slot stub. Any vtable slot that the chunk doesn't
; implement points here.
; ============================================================================
tan_unimplemented_slot PROC FAR
                RETF                            ; CB
tan_unimplemented_slot ENDP

; ============================================================================
; g_abTanPad02f7 -- 7 bytes of padding before tan_slot11.
; chunk:0x02F7..0x02FD
;
; Contents: 00 00 F0 FF 0F 00 00. Likely leftover alignment / data slot.
; The next code starts at 0x02FE.
; ============================================================================
g_abTanPad02f7  LABEL   BYTE
                DB      000H, 000H, 0F0H, 0FFH, 00FH, 000H, 000H

; ============================================================================
; tan_slot11 -- dither-phase shuffler for the per-row pixel colour.
; chunk:0x02FE..0x0317
;
; Toggles scratch:[0x2A] (dither phase flag) via `XOR [2A], 1`. After
; the XOR, ZF reflects the new value of the flag:
;   new phase = 0 -> ZF = 1, JZ taken     -> colour byte in AL kept
;   new phase = 1 -> ZF = 0, JZ not taken -> AL rotated right 4 bits
;                                            (4x ROR) to swap nibbles
; The nibble-swap on alternate calls is the same dither trick used by
; cga_fill_pixel_run_dithered. AH is set to AL up front so on both
; paths AX ends up with the appropriately-shuffled byte.
;
; ABI: register-passed, AL = colour byte in. Returns AX = shuffled
;      colour word, falls through to common epilogue inside tan_slot10.
;
; NOTE: structurally similar to the CGA dither prologue; the falls-
; through to the shared epilogue at 0x032F via JMP is the TAN-side
; equivalent of cga_fill_pixel_run_dithered's internal control flow.
; ============================================================================
tan_slot11      PROC    FAR
                PUSH    DS                      ; 1E
                MOV     AH, AL                  ; 8A E0
                MOV     DS, cs:[206H]           ; 2E 8E 1E 06 02   scratch DS
                XOR     WORD PTR ds:[2AH], 1    ; 83 36 2A 00 01
                POP     DS                      ; 1F
                JZ      SHORT tan_slot11_done   ; 74 21    -> 0x032F (inside tan_slot10)
                ROR     AX, 1                   ; D1 C8
                ROR     AX, 1                   ; D1 C8
                ROR     AX, 1                   ; D1 C8
                ROR     AX, 1                   ; D1 C8
                JMP     SHORT tan_slot11_done   ; EB 17    -> 0x032F
tan_slot11      ENDP

; ============================================================================
; tan_slot10_early_ret -- 1-byte RETF stub at 0x0318.
;
; Mirrors cga_fill_pixel_run_early_ret @ 0x02FA: the JLE inside
; tan_slot10 at 0x031B jumps backward to this 1-byte RETF when the
; pixel count in CX is <= 0. Falls between tan_slot11 and tan_slot10.
; ============================================================================
tan_slot10_early_ret:
                RETF                            ; CB

; ============================================================================
; tan_slot10 -- fill CX pixels of colour AL into 4-bpp Tandy framebuffer.
; chunk:0x0319..0x03BD
;
; Tandy 16-colour analogue of cga_fill_pixel_run_dithered. The framebuffer
; is 4 bits per pixel (2 pixels per byte, high nibble = left pixel, low
; nibble = right pixel), so the byte-edge keep-mask LUTs at chunk:[0x2F8]
; and chunk:[0x2FA] index 0..2 (CGA had 0..4 for 2-bpp).
;
; ABI (register-passed, no BP frame):
;   CX  -- pixel count (<= 0 early-exits via the RETF stub at 0x0318).
;   AL  -- colour nibble (the byte that arrives here had its high nibble
;          already cleared / shuffled by tan_slot11).
;   BX  -- starting pixel cursor (BX/2 = byte offset, BX&1 = pixel within
;          byte: 0=high nibble, 1=low nibble).
;   ES:DI -- destination byte address in Tandy framebuffer.
; ============================================================================
tan_slot10      PROC    FAR
                OR      CX, CX                  ; 0B C9
                JLE     SHORT tan_slot10_early_ret ; 7E FB   -> 0x0318
                TEST    AL, 0F0H                ; A8 F0
                JNZ     tan_slot11              ; 75 DD     -> 0x02FE (re-enter shuffler)
                MOV     AH, AL                  ; 8A E0
                SHL     AH, 1                   ; D0 E4
                SHL     AH, 1                   ; D0 E4
                SHL     AH, 1                   ; D0 E4
                SHL     AH, 1                   ; D0 E4
                OR      AL, AH                  ; 0A C4     replicate nibble into byte
                MOV     AH, AL                  ; 8A E0
tan_slot11_done:
                MOV     DX, AX                  ; 8B D0     DX = replicated colour
                MOV     AX, BX                  ; 8B C3
                SHR     AX, 1                   ; D1 E8     AX = BX/2 byte offset
                ADD     DI, AX                  ; 03 F8
                AND     BX, 1                   ; 83 E3 01  BL = starting pixel within byte
                MOV     AX, DX                  ; 8B C2
                MOV     DX, BX                  ; 8B D3
                ADD     DX, CX                  ; 03 D1     DX = end pixel within byte
                CMP     DX, 2                   ; 83 FA 02
                JGE     SHORT tan_slot10_multi  ; 7D 21
                ; ----- Single-byte path (run fits in one byte) -----
                MOV     CX, AX                  ; 8B C8     CL = colour byte
                MOV     AH, cs:[BX+2F8H]        ; 2E 8A A7 F8 02  left-keep mask
                MOV     BX, DX                  ; 8B DA
                MOV     AL, cs:[BX+2FAH]        ; 2E 8A 87 FA 02  right-keep mask
                OR      AH, AL                  ; 0A E0
                MOV     AL, ES:[DI]             ; 26 8A 05
                AND     AL, AH                  ; 22 C4
                XOR     AH, 0FFH                ; 80 F4 FF
                AND     CL, AH                  ; 22 CC
                OR      AL, CL                  ; 0A C1
                MOV     ES:[DI], AL             ; 26 88 05
                JMP     SHORT tan_slot10_ret    ; EB 57
tan_slot10_multi:
                MOV     DX, 2                   ; BA 02 00
                SUB     DX, BX                  ; 2B D3     DX = pixels to fill leading byte
                SUB     CX, DX                  ; 2B CA
                MOV     DX, AX                  ; 8B D0
                MOV     AL, ES:[DI]             ; 26 8A 05
                MOV     AH, cs:[BX+2F8H]        ; 2E 8A A7 F8 02  left-keep mask
                AND     AL, AH                  ; 22 C4
                MOV     AH, cs:[BX+2FAH]        ; 2E 8A A7 FA 02  right-keep mask
                MOV     BL, DL                  ; 8A DA
                AND     BL, AH                  ; 22 DC
                OR      AL, BL                  ; 0A C3
                STOSB                           ; AA
                MOV     AX, DX                  ; 8B C2
                MOV     DX, CX                  ; 8B D1
                AND     CX, 0FFFCH              ; 83 E1 FC
                JZ      SHORT tan_slot10_no_stosw ; 74 06
                SHR     CX, 1                   ; D1 E9
                SHR     CX, 1                   ; D1 E9
                REP     STOSW                   ; F3 AB
tan_slot10_no_stosw:
                MOV     CX, DX                  ; 8B CA
                AND     CX, 2                   ; 83 E1 02
                JZ      SHORT tan_slot10_no_stosb ; 74 01
                STOSB                           ; AA
tan_slot10_no_stosb:
                MOV     CX, DX                  ; 8B CA
                AND     CX, 1                   ; 83 E1 01
                JZ      SHORT tan_slot10_ret    ; 74 1A
                MOV     DX, AX                  ; 8B D0
                MOV     BX, CX                  ; 8B D9
                MOV     AH, cs:[BX+2FAH]        ; 2E 8A A7 FA 02  right-keep mask
                MOV     AL, ES:[DI]             ; 26 8A 05
                AND     AL, AH                  ; 22 C4
                MOV     AH, cs:[BX+2F8H]        ; 2E 8A A7 F8 02  left-keep mask
                AND     DL, AH                  ; 22 D4
                OR      AL, DL                  ; 0A C2
                MOV     ES:[DI], AL             ; 26 88 05
tan_slot10_ret:
                RETF                            ; CB
tan_slot10      ENDP

; ============================================================================
; tan_slot37 -- textured-polygon scanline span helper.
; chunk:0x03BE..0x0424
;
; Vtable slot 37 -- the textured-pixel-run fill primitive. The host
; (draw_polygon_textured @ 180c:2d50) temporarily swaps the contents of
; two vtable slots around the polygon span loop, so this is the
; "textured" sibling of the plain pixel-run fill at the corresponding
; non-textured slot (tan_slot10, the chunky/Tandy fill at slot 10).
;
; ABI (register-passed):
;   CX  -- pixel count
;   AL  -- starting texture byte
;   DX  -- starting pixel index (used to seed the byte/nibble split)
;   AH  -- direction / flip flags (signed checks via JS / JNS)
;   ES:DI -- destination byte address in the Tandy framebuffer
;   DS:BP -- caller's stack-allocated texel index walker (advance by 2
;            per outer-loop iteration; high/low bit of each word picks
;            a colour mask)
;   SI    -- texture base offset (added to BX index into the texture)
;
; OUTPUT: returns via RETF with AL clobbered. The two early-RETF paths
;   target chunk:0x03BD (tan_slot10_ret, a free RETF byte we can reach
;   from here in a 2-byte SHORT JZ).
;
; READS:
;   g_abTanPixelXlatLut @ 0x11A3 -- 256-byte XLAT LUT via XLAT CS:BX.
; ============================================================================
tan_slot37      PROC    FAR
                XOR     BX, BX                  ; 33 DB
                SHR     DX, 1                   ; D1 EA
                RCR     BL, 1                   ; D0 DB     BX:BL holds (byte,nibble)
                ADD     DI, DX                  ; 03 FA     bump DI by byte offset
                MOV     DX, BX                  ; 8B D3
                DEC     DI                      ; 4F
tan_slot37_next_col:
                INC     DI                      ; 47
                DEC     CX                      ; 49
                JZ      SHORT tan_slot10_ret    ; 74 F0     -> 0x03BD
tan_slot37_inner:
                MOV     AX, 0F0F0H              ; B8 F0 F0
                MOV     BX, [BP+0]              ; 8B 5E 00  texel index walker
                ADD     BP, 2                   ; 83 C5 02
                SHR     BX, 1                   ; D1 EB
                JNC     SHORT tan_slot37_skip_not ; 73 02
                NOT     AX                      ; F7 D0
tan_slot37_skip_not:
                ADD     BX, SI                  ; 03 DE
                AND     AL, [BX]                ; 22 07
                XOR     DL, 0FFH                ; 80 F2 FF
                JNS     SHORT tan_slot37_low_nib ; 79 1E    -> 0x0403
                OR      AH, AH                  ; 0A E4
                JS      SHORT tan_slot37_keep_hi ; 78 08    -> 0x03F1
                SHL     AL, 1                   ; D0 E0
                SHL     AL, 1                   ; D0 E0
                SHL     AL, 1                   ; D0 E0
                SHL     AL, 1                   ; D0 E0
tan_slot37_keep_hi:
                MOV     DH, AL                  ; 8A F0
                LOOP    SHORT tan_slot37_inner  ; E2 D8     -> 0x03CD
                OR      AL, AL                  ; 0A C0
                JZ      SHORT tan_slot10_ret    ; 74 C4     -> 0x03BD
                MOV     AH, ES:[DI]             ; 26 8A 25
                AND     AH, 0FH                 ; 80 E4 0F
                OR      AL, AH                  ; 0A C4
                STOSB                           ; AA
                RETF                            ; CB
tan_slot37_low_nib:
                OR      AH, AH                  ; 0A E4
                JNS     SHORT tan_slot37_keep_lo ; 79 08    -> 0x040F
                SHR     AL, 1                   ; D0 E8
                SHR     AL, 1                   ; D0 E8
                SHR     AL, 1                   ; D0 E8
                SHR     AL, 1                   ; D0 E8
tan_slot37_keep_lo:
                OR      DH, AL                  ; 0A F0
                JZ      SHORT tan_slot37_next_col ; 74 B6   -> 0x03C9
                MOV     AL, DH                  ; 8A C6
                MOV     BX, 11A3H               ; BB A3 11  g_abTanPixelXlatLut
                ; XLAT defaults to DS:[BX+AL]; we need CS:. TASM accepts
                ; an explicit-operand form `XLAT BYTE PTR CS:[BX]` which
                ; emits the CS-override prefix (2Eh) followed by the bare
                ; XLAT opcode (D7h) -- same bytes as a hand-rolled
                ; `DB 2EH / XLAT` pair, but expressed as a single
                ; mnemonic.
                XLAT    BYTE PTR CS:[BX]        ; 2E D7     AL = CS:[BX+AL]
                MOV     AH, ES:[DI]             ; 26 8A 25
                AND     AL, AH                  ; 22 C4
                OR      AL, DH                  ; 0A C6
                STOSB                           ; AA
                LOOP    SHORT tan_slot37_inner  ; E2 A9     -> 0x03CD
                RETF                            ; CB
tan_slot37      ENDP

; ============================================================================
; tan_slot36 -- chunky pixel-run blit with column-offset table.
; chunk:0x0425..0x04B5
;
; Likely a polygon-scanline / sprite-row helper invoked by another
; in-chunk dispatcher (tan_slot2 / tan_slot27 candidates).
;
; ABI (hybrid stack + register, with BP frame):
;   [BP+6]  far ptr  source descriptor (DS:offset pair to fetch)
;   [BP+8]  ushort   x base
;   [BP+0Ah] short   x adjustment / clip start
;   CX      pixel count
;   DX      starting x offset (negative -> shift source forward, clip)
;   DI      row base byte offset within ES:framebuffer
;   AH      flip-flag (bit7 -> low nibble vs high nibble pump)
;
; Algorithm:
;   1. Negative DX -> consume |DX| leading pixels by advancing the
;      column-offset list ([BP+0Ah] += DX*2), reset DX=0.
;   2. Split DX into byte offset (DX>>1, added to DI) and pixel-in-byte
;      bit (RCL into SI).
;   3. Each iteration: read next column word from [BP+0], advance BP by 2,
;      use AX=0x0F0F or NOT-of (0xF0F0) depending on column parity bit;
;      AND with source byte; alternate nibble path (XOR DL,1) selects
;      whether the high or low nibble pumps this iteration; merge into
;      DH; on full byte (DH != 0), XLAT through g_abTanPixelXlatLut and
;      store.
;   4. On exit restore DS from SS, POP BP, RETF.
; ============================================================================
tan_slot36      PROC    FAR
                PUSH    BP                      ; 55
                MOV     BP, SP                  ; 8B EC
                OR      DX, DX                  ; 0B D2
                JNS     SHORT tan_slot36_pos    ; 79 0D
                NEG     DX                      ; F7 DA
                SUB     CX, DX                  ; 2B CA
                JLE     SHORT tan_slot36_ret    ; 7E 7E
                SHL     DX, 1                   ; D1 E2
                ADD     [BP+0AH], DX            ; 01 56 0A
                XOR     DX, DX                  ; 33 D2
tan_slot36_pos:
                XOR     SI, SI                  ; 33 F6
                SHR     DX, 1                   ; D1 EA
                RCL     SI, 1                   ; D1 D6
                ADD     DI, DX                  ; 03 FA
                MOV     BX, [BP+8]              ; 8B 5E 08
                MOV     DX, [BP+0AH]            ; 8B 56 0A
                MOV     BP, [BP+6]              ; 8B 6E 06
                MOV     DS, [BP+0]              ; 8E 5E 00     load far-ptr seg
                MOV     AX, [BP+2]              ; 8B 46 02
                SHL     AX, 1                   ; D1 E0
                ADD     BX, AX                  ; 03 D8
                MOV     BP, DX                  ; 8B EA
                MOV     DX, SI                  ; 8B D6        DL = nibble phase
                DEC     DI                      ; 4F
tan_slot36_next_col:
                INC     DI                      ; 47
                DEC     CX                      ; 49
                JZ      SHORT tan_slot36_ret    ; 74 53
tan_slot36_inner:
                MOV     AX, 0F0FH               ; B8 0F 0F
                MOV     SI, [BP+0]              ; 8B 76 00
                ADD     BP, 2                   ; 83 C5 02
                ADD     SI, BX                  ; 03 F3
                SHR     SI, 1                   ; D1 EE
                JC      SHORT tan_slot36_keep_mask ; 72 02
                NOT     AX                      ; F7 D0
tan_slot36_keep_mask:
                AND     AL, [SI]                ; 22 04
                XOR     DL, 1                   ; 80 F2 01
                JZ      SHORT tan_slot36_low_nib ; 74 16
                OR      AH, AH                  ; 0A E4
                JS      SHORT tan_slot36_skip_shl ; 78 08
                SHL     AL, 1                   ; D0 E0
                SHL     AL, 1                   ; D0 E0
                SHL     AL, 1                   ; D0 E0
                SHL     AL, 1                   ; D0 E0
tan_slot36_skip_shl:
                MOV     DH, AL                  ; 8A F0
                LOOP    SHORT tan_slot36_inner  ; E2 D8
                MOV     AX, SS                  ; 8C D0
                MOV     DS, AX                  ; 8E D8
                POP     BP                      ; 5D
                RETF                            ; CB
tan_slot36_low_nib:
                OR      AH, AH                  ; 0A E4
                JNS     SHORT tan_slot36_skip_shr ; 79 08
                SHR     AL, 1                   ; D0 E8
                SHR     AL, 1                   ; D0 E8
                SHR     AL, 1                   ; D0 E8
                SHR     AL, 1                   ; D0 E8
tan_slot36_skip_shr:
                OR      DH, AL                  ; 0A F0
                JZ      SHORT tan_slot36_next_col ; 74 BE
                MOV     AL, DH                  ; 8A C6
                MOV     SI, BX                  ; 8B F3
                MOV     BX, 11A3H               ; BB A3 11
                XLAT    BYTE PTR CS:[BX]        ; 2E D7     AL = CS:[BX+AL]
                MOV     BX, SI                  ; 8B DE
                MOV     AH, ES:[DI]             ; 26 8A 25
                AND     AL, AH                  ; 22 C4
                OR      AL, DH                  ; 0A C6
                STOSB                           ; AA
                LOOP    SHORT tan_slot36_inner  ; E2 AD
tan_slot36_ret:
                MOV     AX, SS                  ; 8C D0
                MOV     DS, AX                  ; 8E D8
                POP     BP                      ; 5D
tan_slot36_retf_byte:                            ; 0x04B5 (alias target for tan_slot16 JZ)
                RETF                            ; CB
tan_slot36      ENDP

; ============================================================================
; tan_slot16 -- textured pixel-run with z-test.
; chunk:0x04B6..0x053E
;
; Mode-conscious chunky blit with per-pixel z-test against a
; depth-buffer byte at scratch:[0x6BC]. The loop mirrors tan_slot37's
; texture-pump but additionally fetches a z-byte from the
; scratch-DS at offset 0x10 (a far ptr to the depth buffer) and
; masks the destination nibbles based on whether each half passes
; the z-test against scratch:[0x6BC].
; ============================================================================
tan_slot16      PROC    FAR
                XOR     BX, BX                  ; 33 DB
                SHR     DX, 1                   ; D1 EA
                RCR     BL, 1                   ; D0 DB
                ADD     DI, DX                  ; 03 FA
                MOV     DX, BX                  ; 8B D3
                DEC     DI                      ; 4F
tan_slot16_next_col:
                INC     DI                      ; 47
                DEC     CX                      ; 49
                JZ      SHORT tan_slot36_retf_byte ; 74 F0  -> 0x04B5
tan_slot16_inner:
                MOV     AX, 0F0F0H              ; B8 F0 F0
                MOV     BX, [BP+0]              ; 8B 5E 00
                ADD     BP, 2                   ; 83 C5 02
                SHR     BX, 1                   ; D1 EB
                JNC     SHORT tan_slot16_skip_not ; 73 02
                NOT     AX                      ; F7 D0
tan_slot16_skip_not:
                ADD     BX, SI                  ; 03 DE
                AND     AL, [BX]                ; 22 07
                XOR     DL, 0FFH                ; 80 F2 FF
                JS      SHORT tan_slot16_low_nib ; 78 11
                OR      AH, AH                  ; 0A E4
                JS      SHORT tan_slot16_keep_hi ; 78 08
                SHL     AL, 1                   ; D0 E0
                SHL     AL, 1                   ; D0 E0
                SHL     AL, 1                   ; D0 E0
                SHL     AL, 1                   ; D0 E0
tan_slot16_keep_hi:
                MOV     DH, AL                  ; 8A F0
                LOOP    SHORT tan_slot16_inner  ; E2 D8
                RETF                            ; CB
tan_slot16_low_nib:
                OR      AH, AH                  ; 0A E4
                JNS     SHORT tan_slot16_keep_lo ; 79 08
                SHR     AL, 1                   ; D0 E8
                SHR     AL, 1                   ; D0 E8
                SHR     AL, 1                   ; D0 E8
                SHR     AL, 1                   ; D0 E8
tan_slot16_keep_lo:
                OR      DH, AL                  ; 0A F0
                MOV     BX, DS                  ; 8C DB
                MOV     DS, cs:[206H]           ; 2E 8E 1E 06 02   scratch DS
                MOV     AH, BYTE PTR ds:[GfxContext.wTextureIdx]  ; 8A 26 BC 06      z-threshold
                MOV     DS, ds:[GfxContext.wVgaPage1Base]            ; 8E 1E 10 00      depth-buffer DS
                MOV     AL, [DI]                ; 8A 05            z-sample byte
                MOV     DS, BX                  ; 8E DB            restore caller DS
                MOV     BL, AL                  ; 8A D8
                AND     AL, 0FH                 ; 24 0F            low-nib z
                CMP     AH, AL                  ; 3A E0
                JNC     SHORT tan_slot16_test_hi ; 73 03
                AND     DH, 0F0H                ; 80 E6 F0         z fails low-nib -> zero it
tan_slot16_test_hi:
                SHR     BL, 1                   ; D0 EB
                SHR     BL, 1                   ; D0 EB
                SHR     BL, 1                   ; D0 EB
                SHR     BL, 1                   ; D0 EB            BL = high-nib z
                CMP     AH, BL                  ; 3A E3
                JNC     SHORT tan_slot16_z_done ; 73 03
                AND     DH, 0FH                 ; 80 E6 0F         z fails high-nib
tan_slot16_z_done:
                OR      DH, DH                  ; 0A F6
                JZ      SHORT tan_slot16_next_col ; 74 94
                MOV     AL, DH                  ; 8A C6
                MOV     BX, 11A3H               ; BB A3 11
                XLAT    BYTE PTR CS:[BX]        ; 2E D7     AL = CS:[BX+AL]
                MOV     AH, ES:[DI]             ; 26 8A 25
                AND     AL, AH                  ; 22 C4
                OR      AL, DH                  ; 0A C6
                STOSB                           ; AA
                LOOP    SHORT tan_slot16_inner  ; E2 87
                RETF                            ; CB
tan_slot16      ENDP

; ============================================================================
; tan_slot38 -- forward / reverse run-copy with nibble alignment.
; chunk:0x053F..0x05F1
;
; Structure:
;   - Branch on CF (set by entry-side flag): forward path 0x0541..0x0590,
;     reverse path 0x0591..0x05F1. Each path has the same shape:
;        * leading partial byte (high or low nibble aligned)
;        * REP-style middle loop using LODSW + 4-bit shift
;        * trailing partial byte
;   - Forward path uses STOSB (DI++); reverse path uses MOV ES:[DI],AL +
;     DEC DI (DI--). Both walk a 2-pixel-per-byte 4-bpp pixel stream.
; ============================================================================
tan_slot38      PROC    FAR
                JC      tan_slot38_reverse      ; 72 50    -> 0x0591
                SHR     BX, 1                   ; D1 EB
                JNC     SHORT tan_slot38_f_no_lead ; 73 0F
                ADD     DI, BX                  ; 03 FB
                XOR     BX, BX                  ; 33 DB
                LODSB                           ; AC
                MOV     AH, ES:[DI]             ; 26 8A 25
                AND     AH, 0F0H                ; 80 E4 F0
                OR      AL, AH                  ; 0A C4
                STOSB                           ; AA
                DEC     CX                      ; 49
tan_slot38_f_no_lead:
                JZ      SHORT tan_slot38_f_ret  ; 74 19
                ADD     DI, BX                  ; 03 FB
                CMP     CX, 1                   ; 83 F9 01
                JZ      tan_slot38_f_tail       ; 74 21    -> 0x057E
                SHR     CX, 1                   ; D1 E9
                JC      SHORT tan_slot38_f_mid_odd ; 72 0F
tan_slot38_f_mid_even:
                LODSW                           ; AD
                SHL     AL, 1                   ; D0 E0
                SHL     AL, 1                   ; D0 E0
                SHL     AL, 1                   ; D0 E0
                SHL     AL, 1                   ; D0 E0
                OR      AL, AH                  ; 0A C4
                STOSB                           ; AA
                LOOP    SHORT tan_slot38_f_mid_even ; E2 F2
tan_slot38_f_ret:
                RETF                            ; CB
tan_slot38_f_mid_odd:
                LODSW                           ; AD
                SHL     AL, 1                   ; D0 E0
                SHL     AL, 1                   ; D0 E0
                SHL     AL, 1                   ; D0 E0
                SHL     AL, 1                   ; D0 E0
                OR      AL, AH                  ; 0A C4
                STOSB                           ; AA
                LOOP    SHORT tan_slot38_f_mid_odd ; E2 F2
tan_slot38_f_tail:
                LODSB                           ; AC
                SHL     AL, 1                   ; D0 E0
                SHL     AL, 1                   ; D0 E0
                SHL     AL, 1                   ; D0 E0
                SHL     AL, 1                   ; D0 E0
                MOV     AH, ES:[DI]             ; 26 8A 25
                AND     AH, 0FH                 ; 80 E4 0F
                OR      AL, AH                  ; 0A C4
                STOSB                           ; AA
                RETF                            ; CB
tan_slot38_reverse:
                SHR     BX, 1                   ; D1 EB
                JC      SHORT tan_slot38_r_no_lead ; 72 1A
                ADD     DI, BX                  ; 03 FB
                XOR     BX, BX                  ; 33 DB
                LODSB                           ; AC
                SHL     AL, 1                   ; D0 E0
                SHL     AL, 1                   ; D0 E0
                SHL     AL, 1                   ; D0 E0
                SHL     AL, 1                   ; D0 E0
                MOV     AH, ES:[DI]             ; 26 8A 25
                AND     AH, 0FH                 ; 80 E4 0F
                OR      AL, AH                  ; 0A C4
                MOV     ES:[DI], AL             ; 26 88 05
                DEC     DI                      ; 4F
                DEC     CX                      ; 49
tan_slot38_r_no_lead:
                JZ      SHORT tan_slot38_r_ret  ; 74 1C
                ADD     DI, BX                  ; 03 FB
                CMP     CX, 1                   ; 83 F9 01
                JZ      tan_slot38_r_tail       ; 74 27    -> 0x05DF
                SHR     CX, 1                   ; D1 E9
                JC      SHORT tan_slot38_r_mid_odd ; 72 12
tan_slot38_r_mid_even:
                LODSW                           ; AD
                SHL     AH, 1                   ; D0 E4
                SHL     AH, 1                   ; D0 E4
                SHL     AH, 1                   ; D0 E4
                SHL     AH, 1                   ; D0 E4
                OR      AL, AH                  ; 0A C4
                MOV     ES:[DI], AL             ; 26 88 05
                DEC     DI                      ; 4F
                LOOP    SHORT tan_slot38_r_mid_even ; E2 EF
tan_slot38_r_ret:
                RETF                            ; CB
tan_slot38_r_mid_odd:
                LODSW                           ; AD
                SHL     AH, 1                   ; D0 E4
                SHL     AH, 1                   ; D0 E4
                SHL     AH, 1                   ; D0 E4
                SHL     AH, 1                   ; D0 E4
                OR      AL, AH                  ; 0A C4
                MOV     ES:[DI], AL             ; 26 88 05
                DEC     DI                      ; 4F
                LOOP    SHORT tan_slot38_r_mid_odd ; E2 EF
tan_slot38_r_tail:
                LODSB                           ; AC
                MOV     AH, ES:[DI]             ; 26 8A 25
                SHL     AH, 1                   ; D0 E4
                SHL     AH, 1                   ; D0 E4
                SHL     AH, 1                   ; D0 E4
                SHL     AH, 1                   ; D0 E4
                OR      AL, AH                  ; 0A C4
                MOV     ES:[DI], AL             ; 26 88 05
                DEC     DI                      ; 4F
                RETF                            ; CB
tan_slot38      ENDP

; ============================================================================
; g_awTanSlot4ColumnNibbleMaskLut -- 4-byte column nibble mask pair.
; chunk:0x05F2..0x05F5
;
; Contents: FF 0F FF F0. Consumed by tan_slot2 starting at 0x05F6.
; These look like nibble-keep masks indexed by a 2-bit selector.
; ============================================================================
g_awTanSlot4ColumnNibbleMaskLut LABEL BYTE
                DB      0FFH, 00FH, 0FFH, 0F0H

; ============================================================================
; tan_slot2 -- line / rect-edge plotter (Bresenham split paths).
; chunk:0x05F6..0x08E0 (747 bytes -- largest function in chunk)
;
; Vtable slot 2. Renders a line / rect edge with Tandy's bank-interleaved
; framebuffer layout. The body has four explicit cases:
;
;   1. Single-pixel (BX==DX && CX==SI)      -> 0x065B
;   2. Pure horizontal (BX!=DX, CX==SI)     -> 0x0672  (REP-ish nibble pump)
;   3. Pure vertical   (BX==DX, CX!=SI)     -> 0x06F3  (bank-stepping unrolled x5)
;   4. Diagonal / sloped (BX!=DX, CX!=SI)   -> 0x0799  (Bresenham split into
;                                                       horizontal-major and
;                                                       vertical-major branches)
;
; The bank-step bookkeeping at every "DI += BP" step compensates for
; Tandy's 0x2000-banked rows: when DI walks off the top of its 16-KiB
; bank (bit 0x8000 set) the code clears the bank bit and adds
; scratch:[0x6C4] (initialised to 0x00A0 or its NEG) to advance to the
; next row band.
;
; Reads:
;   scratch:[0x6E2]    page-flip extra bit (set by tan_init when no
;                      separate display page was found).
;   scratch:[0x18]     stashed back-buffer segment (passed to tan_slot28).
;   scratch:[0xE]      current pixel colour (replicated to a byte via
;                      4x SHL+OR).
;   scratch:[0x6F2..]  bank-interleaved row LUT.
;   g_awTanSlot4ColumnNibbleMaskLut @ 0x05F2 (4 bytes, indexed by BX&1).
;
; Writes (scratch globals):
;   [0x6C0]  inverted nibble mask  (AH:AL replicated colour)
;   [0x6C2]  raw nibble mask
;   [0x6C4]  row-bank step (signed; NEGed on rising-DY paths)
;   [0x6C8]  2*minor (Bresenham accumulator constant)
; ============================================================================
tan_slot2       PROC    FAR
                PUSH    DS                      ; 1E
                MOV     DS, cs:[206H]           ; 2E 8E 1E 06 02
                CMP     WORD PTR ds:[6E2H], 0   ; 83 3E E2 06 00
                JZ      SHORT tan_slot2_no_flip ; 74 0D
                PUSH    WORD PTR ds:[GfxContext.wGfxBlitDstPage]       ; FF 36 18 00
                PUSH    CS                      ; 0E
                CALL    tan_slot28_fwd          ; E8 .. ..
                ADD     SP, 2                   ; 83 C4 02
                MOV     ES, AX                  ; 8E C0
tan_slot2_no_flip:
                MOV     AL, ds:[GfxContext.bGfx_outline_color]            ; A0 0E 00          colour nibble
                MOV     AH, AL                  ; 8A E0
                SHL     AH, 1                   ; D0 E4
                SHL     AH, 1                   ; D0 E4
                SHL     AH, 1                   ; D0 E4
                SHL     AH, 1                   ; D0 E4
                OR      AL, AH                  ; 0A C4
                MOV     AH, AL                  ; 8A E0
                MOV     ds:[6C0H], AX           ; A3 C0 06
                MOV     DI, BX                  ; 8B FB
                AND     DI, 1                   ; 83 E7 01
                SHL     DI, 1                   ; D1 E7
                MOV     AX, cs:[DI+5F2H]        ; 2E 8B 85 F2 05    nibble mask
                MOV     ds:[6C2H], AX           ; A3 C2 06
                XOR     AX, 0FFFFH              ; 35 FF FF
                AND     ds:[6C0H], AX           ; 21 06 C0 06
                MOV     DI, GfxContext.pRow_offset_lut                ; BF F2 06
                ADD     DI, CX                  ; 03 F9
                ADD     DI, CX                  ; 03 F9
                MOV     DI, [DI]                ; 8B 3D
                MOV     AX, BX                  ; 8B C3
                SHR     AX, 1                   ; D1 E8
                ADD     DI, AX                  ; 03 F8
                CMP     BX, DX                  ; 3B DA
                JNZ     SHORT tan_slot2_bx_ne_dx ; 75 07
                CMP     CX, SI                  ; 3B CE
                JZ      SHORT tan_slot2_single  ; 74 0A
                JMP     tan_slot2_pure_vert     ; E9 9F 00
tan_slot2_bx_ne_dx:
                CMP     CX, SI                  ; 3B CE
                JZ      SHORT tan_slot2_pure_horiz ; 74 1A
                JMP     tan_slot2_diag          ; E9 3E 01
tan_slot2_single:
                MOV     AX, ds:[6C2H]           ; A1 C2 06
                MOV     BX, AX                  ; 8B D8
                MOV     AX, ds:[6C0H]           ; A1 C0 06
                MOV     DX, AX                  ; 8B D0
                MOV     AL, ES:[DI]             ; 26 8A 05
                AND     AL, BH                  ; 22 C7
                OR      AL, DH                  ; 0A C6
                MOV     ES:[DI], AL             ; 26 88 05
                JMP     tan_slot2_done          ; E9 6D 02
tan_slot2_pure_horiz:
                SUB     DX, BX                  ; 2B D3
                MOV     CX, DX                  ; 8B CA
                MOV     AX, ds:[6C2H]           ; A1 C2 06
                MOV     BX, AX                  ; 8B D8
                MOV     AX, ds:[6C0H]           ; A1 C0 06
                MOV     DX, AX                  ; 8B D0
                MOV     AX, ES:[DI]             ; 26 8B 05
                XCHG    AH, AL                  ; 86 E0
                AND     AX, BX                  ; 23 C3
                OR      AX, DX                  ; 0B C2
tan_slot2_h_step:
                ROR     DX, 1                   ; D1 CA
                ROR     DX, 1                   ; D1 CA
                ROR     DX, 1                   ; D1 CA
                ROR     DX, 1                   ; D1 CA
                ROR     BX, 1                   ; D1 CB
                ROR     BX, 1                   ; D1 CB
                ROR     BX, 1                   ; D1 CB
                ROR     BX, 1                   ; D1 CB
                JNC     SHORT tan_slot2_h_carry ; 73 3B
                AND     AX, BX                  ; 23 C3
                OR      AX, DX                  ; 0B C2
                DEC     CX                      ; 49
                JZ      SHORT tan_slot2_h_done  ; 74 49
                ROR     DX, 1                   ; D1 CA
                ROR     DX, 1                   ; D1 CA
                ROR     DX, 1                   ; D1 CA
                ROR     DX, 1                   ; D1 CA
                ROR     BX, 1                   ; D1 CB
                ROR     BX, 1                   ; D1 CB
                ROR     BX, 1                   ; D1 CB
                ROR     BX, 1                   ; D1 CB
                JNC     SHORT tan_slot2_h_carry ; 73 22
                AND     AX, BX                  ; 23 C3
                OR      AX, DX                  ; 0B C2
                DEC     CX                      ; 49
                JZ      SHORT tan_slot2_h_done  ; 74 30
                ROR     DX, 1                   ; D1 CA
                ROR     DX, 1                   ; D1 CA
                ROR     DX, 1                   ; D1 CA
                ROR     DX, 1                   ; D1 CA
                ROR     BX, 1                   ; D1 CB
                ROR     BX, 1                   ; D1 CB
                ROR     BX, 1                   ; D1 CB
                ROR     BX, 1                   ; D1 CB
                JNC     SHORT tan_slot2_h_carry ; 73 09
                AND     AX, BX                  ; 23 C3
                OR      AX, DX                  ; 0B C2
                DEC     CX                      ; 49
                JZ      SHORT tan_slot2_h_done  ; 74 17
                JMP     SHORT tan_slot2_h_step  ; EB B3
tan_slot2_h_carry:
                XCHG    AH, AL                  ; 86 E0
                MOV     ES:[DI], AX             ; 26 89 05
                INC     DI                      ; 47
                INC     DI                      ; 47
                MOV     AX, ES:[DI]             ; 26 8B 05
                XCHG    AH, AL                  ; 86 E0
                AND     AX, BX                  ; 23 C3
                OR      AX, DX                  ; 0B C2
                DEC     CX                      ; 49
                JZ      SHORT tan_slot2_h_done  ; 74 02
                JMP     SHORT tan_slot2_h_step  ; EB 9E
tan_slot2_h_done:
                XCHG    AH, AL                  ; 86 E0
                MOV     ES:[DI], AX             ; 26 89 05
                JMP     tan_slot2_done          ; E9 EC 01
tan_slot2_pure_vert:
                MOV     AX, 2000H               ; B8 00 20
                MOV     BP, AX                  ; 8B E8
                MOV     WORD PTR ds:[6C4H], 0A0H ; C7 06 C4 06 A0 00
                SUB     SI, CX                  ; 2B F1
                JG      SHORT tan_slot2_v_pos   ; 7F 08
                NEG     SI                      ; F7 DE
                NEG     BP                      ; F7 DD
                NEG     WORD PTR ds:[6C4H]      ; F7 1E C4 06
tan_slot2_v_pos:
                MOV     CX, SI                  ; 8B CE
                MOV     AX, ds:[6C2H]           ; A1 C2 06
                MOV     BX, AX                  ; 8B D8
                MOV     AX, ds:[6C0H]           ; A1 C0 06
                MOV     DX, AX                  ; 8B D0
tan_slot2_v_loop_top:
                MOV     AL, ES:[DI]             ; 26 8A 05
                AND     AL, BH                  ; 22 C7
                OR      AL, DH                  ; 0A C6
tan_slot2_v_loop_tail:                           ; 0x071D - target of EB 8A
                MOV     ES:[DI], AL             ; 26 88 05
                DEC     CX                      ; 49
                JS      tan_slot2_v_final       ; 78 70   -> 0x0793
                ADD     DI, BP                  ; 03 FD
                TEST    DI, 8000H               ; F7 C7 00 80
                JZ      SHORT tan_slot2_v_s1    ; 74 08
                AND     DI, 7FFFH               ; 81 E7 FF 7F
                ADD     DI, ds:[6C4H]           ; 03 3E C4 06
tan_slot2_v_s1:
                MOV     AL, ES:[DI]             ; 26 8A 05
                AND     AL, BH                  ; 22 C7
                OR      AL, DH                  ; 0A C6
                MOV     ES:[DI], AL             ; 26 88 05
                DEC     CX                      ; 49
                JS      tan_slot2_v_final       ; 78 53
                ADD     DI, BP                  ; 03 FD
                TEST    DI, 8000H               ; F7 C7 00 80
                JZ      SHORT tan_slot2_v_s2    ; 74 08
                AND     DI, 7FFFH               ; 81 E7 FF 7F
                ADD     DI, ds:[6C4H]           ; 03 3E C4 06
tan_slot2_v_s2:
                MOV     AL, ES:[DI]             ; 26 8A 05
                AND     AL, BH                  ; 22 C7
                OR      AL, DH                  ; 0A C6
                MOV     ES:[DI], AL             ; 26 88 05
                DEC     CX                      ; 49
                JS      tan_slot2_v_final       ; 78 36
                ADD     DI, BP                  ; 03 FD
                TEST    DI, 8000H               ; F7 C7 00 80
                JZ      SHORT tan_slot2_v_s3    ; 74 08
                AND     DI, 7FFFH               ; 81 E7 FF 7F
                ADD     DI, ds:[6C4H]           ; 03 3E C4 06
tan_slot2_v_s3:
                MOV     AL, ES:[DI]             ; 26 8A 05
                AND     AL, BH                  ; 22 C7
                OR      AL, DH                  ; 0A C6
                MOV     ES:[DI], AL             ; 26 88 05
                DEC     CX                      ; 49
                JS      SHORT tan_slot2_v_final ; 78 19
                ADD     DI, BP                  ; 03 FD
                TEST    DI, 8000H               ; F7 C7 00 80
                JZ      SHORT tan_slot2_v_s4    ; 74 08
                AND     DI, 7FFFH               ; 81 E7 FF 7F
                ADD     DI, ds:[6C4H]           ; 03 3E C4 06
tan_slot2_v_s4:
                MOV     AL, ES:[DI]             ; 26 8A 05
                AND     AL, BH                  ; 22 C7
                OR      AL, DH                  ; 0A C6
                JMP     SHORT tan_slot2_v_loop_tail ; EB 8A    -> 0x071D
tan_slot2_v_final:
                MOV     ES:[DI], AL             ; 26 88 05
                JMP     tan_slot2_done          ; E9 46 01
tan_slot2_diag:
                MOV     AX, 2000H               ; B8 00 20
                MOV     BP, AX                  ; 8B E8
                MOV     WORD PTR ds:[6C4H], 0A0H ; C7 06 C4 06 A0 00
                SUB     DX, BX                  ; 2B D3
                SUB     SI, CX                  ; 2B F1
                JG      SHORT tan_slot2_d_pos   ; 7F 08
                NEG     SI                      ; F7 DE
                NEG     BP                      ; F7 DD
                NEG     WORD PTR ds:[6C4H]      ; F7 1E C4 06
tan_slot2_d_pos:
                MOV     CX, SI                  ; 8B CE
                CMP     CX, DX                  ; 3B CA
                JZ      SHORT tan_slot2_d_eq    ; 74 05
                JC      SHORT tan_slot2_d_hmaj  ; 72 4B
                JMP     tan_slot2_d_vmaj        ; E9 C0 00
tan_slot2_d_eq:
                MOV     CX, DX                  ; 8B CA
                MOV     AX, ds:[6C2H]           ; A1 C2 06
                MOV     BX, AX                  ; 8B D8
                MOV     AX, ds:[6C0H]           ; A1 C0 06
                MOV     DX, AX                  ; 8B D0
                MOV     AL, ES:[DI]             ; 26 8A 05
                AND     AL, BH                  ; 22 C7
                OR      AL, DH                  ; 0A C6
tan_slot2_d_eq_loop:
                MOV     ES:[DI], AL             ; 26 88 05
                DEC     CX                      ; 49
                JZ      SHORT tan_slot2_d_eq_done ; 74 2C
                ADD     DI, BP                  ; 03 FD
                TEST    DI, 8000H               ; F7 C7 00 80
                JZ      SHORT tan_slot2_d_eq_skip ; 74 08
                AND     DI, 7FFFH               ; 81 E7 FF 7F
                ADD     DI, ds:[6C4H]           ; 03 3E C4 06
tan_slot2_d_eq_skip:
                ROR     DH, 1                   ; D0 CE
                ROR     DH, 1                   ; D0 CE
                ROR     DH, 1                   ; D0 CE
                ROR     DH, 1                   ; D0 CE
                ROR     BH, 1                   ; D0 CF
                ROR     BH, 1                   ; D0 CF
                ROR     BH, 1                   ; D0 CF
                ROR     BH, 1                   ; D0 CF
                JC      SHORT tan_slot2_d_eq_nostep ; 72 01
                INC     DI                      ; 47
tan_slot2_d_eq_nostep:
                MOV     AL, ES:[DI]             ; 26 8A 05
                AND     AL, BH                  ; 22 C7
                OR      AL, DH                  ; 0A C6
                JMP     SHORT tan_slot2_d_eq_loop ; EB CE   (back to 0x07D0)
tan_slot2_d_eq_done:
                JMP     tan_slot2_done          ; E9 DA 00
tan_slot2_d_hmaj:
                MOV     BX, CX                  ; 8B D9
                MOV     CX, DX                  ; 8B CA
                MOV     AX, BX                  ; 8B C3
                SHL     AX, 1                   ; D1 E0
                MOV     ds:[6C8H], AX           ; A3 C8 06
                SUB     AX, CX                  ; 2B C1
                MOV     SI, AX                  ; 8B F0
                SUB     AX, CX                  ; 2B C1
                MOV     BX, BP                  ; 8B DD
                MOV     BP, AX                  ; 8B E8
                MOV     AX, ds:[6C2H]           ; A1 C2 06
                MOV     DX, ds:[6C0H]           ; 8B 16 C0 06
                MOV     AL, ES:[DI]             ; 26 8A 05
                AND     AL, AH                  ; 22 C4
                OR      AL, DH                  ; 0A C6
                MOV     ES:[DI], AL             ; 26 88 05
                ROR     DH, 1                   ; D0 CE
                ROR     DH, 1                   ; D0 CE
                ROR     DH, 1                   ; D0 CE
                ROR     DH, 1                   ; D0 CE
                ROR     AH, 1                   ; D0 CC
                ROR     AH, 1                   ; D0 CC
                ROR     AH, 1                   ; D0 CC
                ROR     AH, 1                   ; D0 CC
                CMC                             ; F5
                ADC     DI, 0                   ; 83 D7 00
tan_slot2_d_hmaj_step:
                OR      SI, SI                  ; 0B F6
                JS      SHORT tan_slot2_d_hmaj_minor ; 78 14
                ADD     DI, BX                  ; 03 FB
                TEST    DI, 8000H               ; F7 C7 00 80
                JZ      SHORT tan_slot2_d_hmaj_no_bank ; 74 08
                AND     DI, 7FFFH               ; 81 E7 FF 7F
                ADD     DI, ds:[6C4H]           ; 03 3E C4 06
tan_slot2_d_hmaj_no_bank:
                ADD     SI, BP                  ; 03 F5
                JMP     SHORT tan_slot2_d_hmaj_pix ; EB 04
tan_slot2_d_hmaj_minor:
                ADD     SI, ds:[6C8H]           ; 03 36 C8 06
tan_slot2_d_hmaj_pix:
                MOV     AL, ES:[DI]             ; 26 8A 05
                AND     AL, AH                  ; 22 C4
                OR      AL, DH                  ; 0A C6
                MOV     ES:[DI], AL             ; 26 88 05
                ROR     DH, 1                   ; D0 CE
                ROR     DH, 1                   ; D0 CE
                ROR     DH, 1                   ; D0 CE
                ROR     DH, 1                   ; D0 CE
                ROR     AH, 1                   ; D0 CC
                ROR     AH, 1                   ; D0 CC
                ROR     AH, 1                   ; D0 CC
                ROR     AH, 1                   ; D0 CC
                CMC                             ; F5
                ADC     DI, 0                   ; 83 D7 00
                LOOP    SHORT tan_slot2_d_hmaj_step ; E2 C4
                JMP     SHORT tan_slot2_done    ; EB 62
tan_slot2_d_vmaj:
                MOV     BX, DX                  ; 8B DA
                MOV     AX, BX                  ; 8B C3
                SHL     AX, 1                   ; D1 E0
                MOV     ds:[6C8H], AX           ; A3 C8 06
                SUB     AX, CX                  ; 2B C1
                MOV     SI, AX                  ; 8B F0
                SUB     AX, CX                  ; 2B C1
                MOV     BX, BP                  ; 8B DD
                MOV     BP, AX                  ; 8B E8
                MOV     AX, ds:[6C2H]           ; A1 C2 06
                MOV     DX, ds:[6C0H]           ; 8B 16 C0 06
                MOV     AL, ES:[DI]             ; 26 8A 05
                AND     AL, AH                  ; 22 C4
                OR      AL, DH                  ; 0A C6
                MOV     ES:[DI], AL             ; 26 88 05
tan_slot2_d_vmaj_step:
                ADD     DI, BX                  ; 03 FB
                TEST    DI, 8000H               ; F7 C7 00 80
                JZ      SHORT tan_slot2_d_vmaj_no_bank ; 74 08
                AND     DI, 7FFFH               ; 81 E7 FF 7F
                ADD     DI, ds:[6C4H]           ; 03 3E C4 06
tan_slot2_d_vmaj_no_bank:
                OR      SI, SI                  ; 0B F6
                JS      SHORT tan_slot2_d_vmaj_minor ; 78 18
                ROR     DH, 1                   ; D0 CE
                ROR     DH, 1                   ; D0 CE
                ROR     DH, 1                   ; D0 CE
                ROR     DH, 1                   ; D0 CE
                ROR     AH, 1                   ; D0 CC
                ROR     AH, 1                   ; D0 CC
                ROR     AH, 1                   ; D0 CC
                ROR     AH, 1                   ; D0 CC
                CMC                             ; F5
                ADC     DI, 0                   ; 83 D7 00
                ADD     SI, BP                  ; 03 F5
                JMP     SHORT tan_slot2_d_vmaj_pix ; EB 04
tan_slot2_d_vmaj_minor:
                ADD     SI, ds:[6C8H]           ; 03 36 C8 06
tan_slot2_d_vmaj_pix:
                MOV     AL, ES:[DI]             ; 26 8A 05
                AND     AL, AH                  ; 22 C4
                OR      AL, DH                  ; 0A C6
                MOV     ES:[DI], AL             ; 26 88 05
                LOOP    SHORT tan_slot2_d_vmaj_step ; E2 C4
                JMP     SHORT tan_slot2_done    ; EB 00
tan_slot2_done:
                POP     DS                      ; 1F
                RETF                            ; CB
tan_slot2       ENDP

; ============================================================================
; g_abTanSpanBoundaryMaskLut -- 4-byte span boundary mask LUT.
; chunk:0x08E1..0x08E4
;
; Contents: 00 F0 FF 0F. Indexed by BX&1 for left-edge mask, by DX&1 for
; right-edge mask. Consumed by tan_slot27 / its child blits to render
; partial-byte edges of polygon-bound sprite scans.
; ============================================================================
g_abTanSpanBoundaryMaskLut LABEL BYTE
                DB      000H, 0F0H, 0FFH, 00FH

; ============================================================================
; g_abTanSlot4Scratch -- 8-byte runtime scratch used by tan_slot27.
; chunk:0x08E5..0x08EC
;
; Layout (offset relative to chunk start):
;   0x08E5  ushort  remaining-rows counter           (decremented by 1 per row)
;   0x08E7  ushort  primary nibble-replicated colour (high-nibble mode)
;   0x08E9  ushort  alternate nibble-replicated colour (vertical-flip mode)
;   0x08EB  ushort  bank-LUT base offset (0x6F2 + row-base) into scratch DS
;
; The consumer is tan_slot27 (vtable slot 27). Zero-initialised; each
; slot is written from inside tan_slot27.
; ============================================================================
g_abTanSlot4Scratch LABEL BYTE
                DB      8 DUP (0)

; ============================================================================
; tan_slot27 -- polygon span fill from edge-descriptor records.
; chunk:0x08ED..0x0B54
;
; Cross-driver role: this is vtable slot 27, the "render spans/polygon
; from per-row (left_x, right_x) descriptor records" entry point.
; Sibling implementations in the other drivers:
;
;   vga.asm  slot 27 -- vga_fill_spans_dithered_modey
;   cga.asm  slot 27 -- cga_fill_spans_dithered
;   ega.asm  slot 27 -- ega_polygon_span_fill
;   mcg.asm  slot 27 -- mcg_polygon_span_fill
;   heg.asm  slot 27 -- heg_span_fill
;   evg.asm  slot 27 -- evg_polygon_span_fill
;   eva.asm  slot 27 -- eva_unimplemented_slot (stubbed)
;
; The TAN implementation looks "sprite-like" because the per-row
; descriptor it consumes is laid out the same way a sprite scanline
; record is — but the operation is identical to the other drivers':
; emit one scanline span per iteration, partial-byte-mask aware, into
; the 16-colour Tandy framebuffer.
;
; Largest non-slot-4 function (616 bytes). Three control-flow bands,
; each running a row-loop that emits one scanline span per iteration:
;
;   - tan_slot27_path_a  @ 0x0950   -- non-XLAT (solid-colour) span,
;                                       used when colour byte has its
;                                       high nibble clear.
;   - tan_slot27_path_b  @ 0x0a06   -- alternating-nibble span,
;                                       horizontal-flip-aware.
;   - tan_slot27_path_c  @ 0x0aac   -- alternating-nibble span using
;                                       the secondary colour at [0x8e9].
;
; All three paths share an inner loop with the same shape:
;   1. LODSW BX <- left X    LODSW AX <- right X    AX -= BX
;   2. If AX < 0, this scanline is a no-op (skip to row-decrement tail).
;   3. Otherwise, AX+1 = pixel count. Resolve DI = page-base + row LUT
;      [BP+CS:[0x8eb]] + (left_x >> 1); pick keep mask for left/right
;      byte boundaries from g_abTanSpanBoundaryMaskLut @ 0x8e1/0x8e3.
;   4. Pump nibble pairs into ES:[DI] via the same single-byte /
;      multi-byte split used by tan_slot10 (CGA's CGA-dither helper
;      mirror).
;
; ABI: __cdecl16far(edge_descriptor_ptr_far, x_base, ...). DS:SI on
; entry walks the per-row (left_x, right_x) descriptor records.
; ============================================================================
tan_slot27      PROC    FAR
                PUSH    DS                      ; 1E
                MOV     CX, ES                  ; 8C C1
                MOV     DS, CX                  ; 8E D9       DS = caller ES
                LODSW                           ; AD
                SHL     AX, 1                   ; D1 E0
                MOV     BP, AX                  ; 8B E8
                LODSW                           ; AD
                MOV     DS, cs:[206H]           ; 2E 8E 1E 06 02
                MOV     cs:[8E5H], AX           ; 2E A3 E5 08    remaining rows
                MOV     AX, ds:[GfxContext.wGfxBlitDstPage]            ; A1 18 00
                CMP     WORD PTR ds:[6E2H], 0   ; 83 3E E2 06 00
                JZ      SHORT tan_slot27_no_flip ; 74 0B
                PUSH    WORD PTR ds:[GfxContext.wGfxBlitDstPage]       ; FF 36 18 00
                PUSH    CS                      ; 0E
                CALL    tan_slot28_fwd          ; E8 .. ..
                ADD     SP, 2                   ; 83 C4 02
tan_slot27_no_flip:
                MOV     ES, AX                  ; 8E C0
                MOV     AX, GfxContext.pRow_offset_lut                ; B8 F2 06
                ADD     AX, cs:[208H]           ; 2E 03 06 08 02
                MOV     cs:[8EBH], AX           ; 2E A3 EB 08
                MOV     AL, ds:[GfxContext.bGfx_fill_color]            ; A0 0D 00
                MOV     AH, AL                  ; 8A E0
                MOV     DS, CX                  ; 8E D9       DS = caller ES again
                TEST    AL, 0F0H                ; A8 F0
                JZ      SHORT tan_slot27_lo_nib ; 74 0F
                MOV     cs:[8E7H], AX           ; 2E A3 E7 08
                ROR     AX, 1                   ; D1 C8
                ROR     AX, 1                   ; D1 C8
                ROR     AX, 1                   ; D1 C8
                ROR     AX, 1                   ; D1 C8
                JMP     tan_slot27_alt          ; E9 B7 00
tan_slot27_lo_nib:
                SHL     AL, 1                   ; D0 E0
                SHL     AL, 1                   ; D0 E0
                SHL     AL, 1                   ; D0 E0
                SHL     AL, 1                   ; D0 E0
                OR      AL, AH                  ; 0A C4
                MOV     AH, AL                  ; 8A E0
                MOV     cs:[8E7H], AX           ; 2E A3 E7 08
                JMP     SHORT tan_slot27_path_a ; EB 00
tan_slot27_path_a:
                LODSW                           ; AD
                MOV     BX, AX                  ; 8B D8
                LODSW                           ; AD
                SUB     AX, BX                  ; 2B C3
                JGE     SHORT tan_slot27_pa_run ; 7D 03
                JMP     tan_slot27_pa_tail      ; E9 8A 00
tan_slot27_pa_run:
                INC     AX                      ; 40
                MOV     CX, AX                  ; 8B C8
                MOV     DI, cs:[8EBH]           ; 2E 8B 3E EB 08
                MOV     DI, [BP+DI]             ; 8B 3B
                MOV     AX, cs:[8E7H]           ; 2E A1 E7 08
                MOV     DX, AX                  ; 8B D0
                MOV     AX, BX                  ; 8B C3
                SHR     AX, 1                   ; D1 E8
                ADD     DI, AX                  ; 03 F8
                AND     BX, 1                   ; 83 E3 01
                MOV     AX, DX                  ; 8B C2
                MOV     DX, BX                  ; 8B D3
                ADD     DX, CX                  ; 03 D1
                CMP     DX, 2                   ; 83 FA 02
                JGE     SHORT tan_slot27_pa_multi ; 7D 1E
                MOV     CX, AX                  ; 8B C8
                MOV     AH, cs:[BX+8E1H]        ; 2E 8A A7 E1 08
                MOV     BX, DX                  ; 8B DA
                MOV     AL, cs:[BX+8E3H]        ; 2E 8A 87 E3 08
                OR      AH, AL                  ; 0A E0
                MOV     AL, ES:[DI]             ; 26 8A 05
                AND     AL, AH                  ; 22 C4
                NOT     AH                      ; F6 D4
                AND     CL, AH                  ; 22 CC
                OR      AL, CL                  ; 0A C1
                STOSB                           ; AA
                JMP     SHORT tan_slot27_pa_tail ; EB 48
tan_slot27_pa_multi:
                MOV     DX, 2                   ; BA 02 00
                SUB     DX, BX                  ; 2B D3
                SUB     CX, DX                  ; 2B CA
                MOV     DX, AX                  ; 8B D0
                MOV     AL, ES:[DI]             ; 26 8A 05
                MOV     AH, cs:[BX+8E1H]        ; 2E 8A A7 E1 08
                AND     AL, AH                  ; 22 C4
                NOT     AH                      ; F6 D4
                MOV     BL, DL                  ; 8A DA
                AND     BL, AH                  ; 22 DC
                OR      AL, BL                  ; 0A C3
                STOSB                           ; AA
                MOV     AX, DX                  ; 8B C2
                MOV     DX, CX                  ; 8B D1
                SHR     CX, 1                   ; D1 E9
                SHR     CX, 1                   ; D1 E9
                REP     STOSW                   ; F3 AB
                MOV     CX, DX                  ; 8B CA
                AND     CX, 2                   ; 83 E1 02
                JZ      SHORT tan_slot27_pa_no_stosb ; 74 01
                STOSB                           ; AA
tan_slot27_pa_no_stosb:
                AND     DX, 1                   ; 83 E2 01
                JZ      SHORT tan_slot27_pa_tail ; 74 15
                MOV     CX, AX                  ; 8B C8
                MOV     BX, DX                  ; 8B DA
                MOV     AH, cs:[BX+8E3H]        ; 2E 8A A7 E3 08
                MOV     AL, ES:[DI]             ; 26 8A 05
                AND     AL, AH                  ; 22 C4
                NOT     AH                      ; F6 D4
                AND     CL, AH                  ; 22 CC
                OR      AL, CL                  ; 0A C1
                STOSB                           ; AA
tan_slot27_pa_tail:
                SUB     WORD PTR cs:[8E5H], 1   ; 2E 83 2E E5 08 01
                JLE     SHORT tan_slot27_pa_done ; 7E 06
                ADD     BP, 2                   ; 83 C5 02
                JMP     tan_slot27_path_a       ; E9 5D FF
tan_slot27_pa_done:
                POP     DS                      ; 1F
                RETF                            ; CB
tan_slot27_alt:
                MOV     cs:[8E9H], AX           ; 2E A3 E9 08
                MOV     BX, BP                  ; 8B DD
                SHR     BX, 1                   ; D1 EB
                ADD     BX, [SI]                ; 03 1C
                SHR     BX, 1                   ; D1 EB
                JC      SHORT tan_slot27_pc_entry ; 72 03
                JMP     tan_slot27_path_c       ; E9 AC 00
tan_slot27_pc_entry:
                LODSW                           ; AD
                MOV     BX, AX                  ; 8B D8
                LODSW                           ; AD
                SUB     AX, BX                  ; 2B C3
                JGE     SHORT tan_slot27_pb_run ; 7D 03
                JMP     tan_slot27_pb_tail      ; E9 8E 00
tan_slot27_pb_run:
                INC     AX                      ; 40
                MOV     CX, AX                  ; 8B C8
                MOV     DI, cs:[8EBH]           ; 2E 8B 3E EB 08
                MOV     DI, [BP+DI]             ; 8B 3B
                MOV     AX, cs:[8E7H]           ; 2E A1 E7 08
                MOV     DX, AX                  ; 8B D0
                MOV     AX, BX                  ; 8B C3
                SHR     AX, 1                   ; D1 E8
                ADD     DI, AX                  ; 03 F8
                AND     BX, 1                   ; 83 E3 01
                MOV     AX, DX                  ; 8B C2
                MOV     DX, BX                  ; 8B D3
                ADD     DX, CX                  ; 03 D1
                CMP     DX, 2                   ; 83 FA 02
                JGE     SHORT tan_slot27_pb_multi ; 7D 1E
                MOV     CX, AX                  ; 8B C8
                MOV     AH, cs:[BX+8E1H]        ; 2E 8A A7 E1 08
                MOV     BX, DX                  ; 8B DA
                MOV     AL, cs:[BX+8E3H]        ; 2E 8A 87 E3 08
                OR      AH, AL                  ; 0A E0
                MOV     AL, ES:[DI]             ; 26 8A 05
                AND     AL, AH                  ; 22 C4
                NOT     AH                      ; F6 D4
                AND     CL, AH                  ; 22 CC
                OR      AL, CL                  ; 0A C1
                STOSB                           ; AA
                JMP     SHORT tan_slot27_pb_tail ; EB 4C
tan_slot27_pb_multi:
                MOV     DX, 2                   ; BA 02 00
                SUB     DX, BX                  ; 2B D3
                SUB     CX, DX                  ; 2B CA
                MOV     DX, AX                  ; 8B D0
                MOV     AL, ES:[DI]             ; 26 8A 05
                MOV     AH, cs:[BX+8E1H]        ; 2E 8A A7 E1 08
                AND     AL, AH                  ; 22 C4
                NOT     AH                      ; F6 D4
                MOV     BL, DL                  ; 8A DA
                AND     BL, AH                  ; 22 DC
                OR      AL, BL                  ; 0A C3
                STOSB                           ; AA
                MOV     AX, DX                  ; 8B C2
                MOV     DX, CX                  ; 8B D1
                SHR     CX, 1                   ; D1 E9
                SHR     CX, 1                   ; D1 E9
                JZ      SHORT tan_slot27_pb_no_stosw ; 74 02
                REP     STOSW                   ; F3 AB
tan_slot27_pb_no_stosw:
                MOV     CX, DX                  ; 8B CA
                AND     CX, 2                   ; 83 E1 02
                JZ      SHORT tan_slot27_pb_no_stosb ; 74 01
                STOSB                           ; AA
tan_slot27_pb_no_stosb:
                MOV     CX, DX                  ; 8B CA
                AND     CX, 1                   ; 83 E1 01
                JZ      SHORT tan_slot27_pb_tail ; 74 15
                MOV     DX, AX                  ; 8B D0
                MOV     BX, CX                  ; 8B D9
                MOV     AH, cs:[BX+8E3H]        ; 2E 8A A7 E3 08
                MOV     AL, ES:[DI]             ; 26 8A 05
                AND     AL, AH                  ; 22 C4
                NOT     AH                      ; F6 D4
                AND     DL, AH                  ; 22 D4
                OR      AL, DL                  ; 0A C2
                STOSB                           ; AA
tan_slot27_pb_tail:
                SUB     WORD PTR cs:[8E5H], 1   ; 2E 83 2E E5 08 01
                JG      SHORT tan_slot27_pb_continue ; 7F 02
                POP     DS                      ; 1F
                RETF                            ; CB
tan_slot27_pb_continue:
                ADD     BP, 2                   ; 83 C5 02
tan_slot27_path_c:
                LODSW                           ; AD
                MOV     BX, AX                  ; 8B D8
                LODSW                           ; AD
                SUB     AX, BX                  ; 2B C3
                JGE     SHORT tan_slot27_pc_run ; 7D 03
                JMP     tan_slot27_pc_tail      ; E9 8E 00
tan_slot27_pc_run:
                INC     AX                      ; 40
                MOV     CX, AX                  ; 8B C8
                MOV     DI, cs:[8EBH]           ; 2E 8B 3E EB 08
                MOV     DI, [BP+DI]             ; 8B 3B
                MOV     AX, cs:[8E9H]           ; 2E A1 E9 08    secondary colour
                MOV     DX, AX                  ; 8B D0
                MOV     AX, BX                  ; 8B C3
                SHR     AX, 1                   ; D1 E8
                ADD     DI, AX                  ; 03 F8
                AND     BX, 1                   ; 83 E3 01
                MOV     AX, DX                  ; 8B C2
                MOV     DX, BX                  ; 8B D3
                ADD     DX, CX                  ; 03 D1
                CMP     DX, 2                   ; 83 FA 02
                JGE     SHORT tan_slot27_pc_multi ; 7D 1E
                MOV     CX, AX                  ; 8B C8
                MOV     AH, cs:[BX+8E1H]        ; 2E 8A A7 E1 08
                MOV     BX, DX                  ; 8B DA
                MOV     AL, cs:[BX+8E3H]        ; 2E 8A 87 E3 08
                OR      AH, AL                  ; 0A E0
                MOV     AL, ES:[DI]             ; 26 8A 05
                AND     AL, AH                  ; 22 C4
                NOT     AH                      ; F6 D4
                AND     CL, AH                  ; 22 CC
                OR      AL, CL                  ; 0A C1
                STOSB                           ; AA
                JMP     SHORT tan_slot27_pc_tail ; EB 4C
tan_slot27_pc_multi:
                MOV     DX, 2                   ; BA 02 00
                SUB     DX, BX                  ; 2B D3
                SUB     CX, DX                  ; 2B CA
                MOV     DX, AX                  ; 8B D0
                MOV     AL, ES:[DI]             ; 26 8A 05
                MOV     AH, cs:[BX+8E1H]        ; 2E 8A A7 E1 08
                AND     AL, AH                  ; 22 C4
                NOT     AH                      ; F6 D4
                MOV     BL, DL                  ; 8A DA
                AND     BL, AH                  ; 22 DC
                OR      AL, BL                  ; 0A C3
                STOSB                           ; AA
                MOV     AX, DX                  ; 8B C2
                MOV     DX, CX                  ; 8B D1
                SHR     CX, 1                   ; D1 E9
                SHR     CX, 1                   ; D1 E9
                JZ      SHORT tan_slot27_pc_no_stosw ; 74 02
                REP     STOSW                   ; F3 AB
tan_slot27_pc_no_stosw:
                MOV     CX, DX                  ; 8B CA
                AND     CX, 2                   ; 83 E1 02
                JZ      SHORT tan_slot27_pc_no_stosb ; 74 01
                STOSB                           ; AA
tan_slot27_pc_no_stosb:
                MOV     CX, DX                  ; 8B CA
                AND     CX, 1                   ; 83 E1 01
                JZ      SHORT tan_slot27_pc_tail ; 74 15
                MOV     DX, AX                  ; 8B D0
                MOV     BX, CX                  ; 8B D9
                MOV     AH, cs:[BX+8E3H]        ; 2E 8A A7 E3 08
                MOV     AL, ES:[DI]             ; 26 8A 05
                AND     AL, AH                  ; 22 C4
                NOT     AH                      ; F6 D4
                AND     DL, AH                  ; 22 D4
                OR      AL, DL                  ; 0A C2
                STOSB                           ; AA
tan_slot27_pc_tail:
                SUB     WORD PTR cs:[8E5H], 1   ; 2E 83 2E E5 08 01
                JLE     SHORT tan_slot27_pc_done ; 7E 06
                ADD     BP, 2                   ; 83 C5 02
                JMP     tan_slot27_pc_entry     ; E9 B3 FE  -> 0x0A06 (path_b body re-entry)
tan_slot27_pc_done:
                POP     DS                      ; 1F
                RETF                            ; CB
tan_slot27      ENDP

; ============================================================================
; tan_slot19 -- getpixel(x, y) for Tandy 16-colour mode 9.
; chunk:0x0B55..0x0B9D
;
; Host tail-calls here from getpixel (180c:29dc). Returns the pixel
; value in DX:AX (DX=0, AX=0..15) by allocating a 32-byte DOS buffer
; and asking host callback #10 (CALLF cs:[0x2D2]) to write the demangled
; pixel into the buffer's far ptr.
;
; ABI (__cdecl16far):
;   [BP+6] = x, [BP+8] = y. Returns pixel index in DX:AX.
; ============================================================================
tan_slot19      PROC    FAR
                PUSH    BP                      ; 55
                MOV     BP, SP                  ; 8B EC
                SUB     SP, 12H                 ; 83 EC 12
                PUSH    SI                      ; 56
                PUSH    DI                      ; 57
                MOV     BX, 2                   ; BB 02 00
                MOV     AH, 48H                 ; B4 48
                INT     21H                     ; CD 21
                JNC     SHORT tan_slot19_alloc_ok ; 73 06
                XOR     AX, AX                  ; 33 C0
                XOR     DX, DX                  ; 33 D2
                JMP     SHORT tan_slot19_exit   ; EB 2B
tan_slot19_alloc_ok:
                MOV     DX, AX                  ; 8B D0
                XOR     AX, AX                  ; 33 C0
                PUSH    AX                      ; 50
                PUSH    DX                      ; 52
                MOV     AX, [BP+6]              ; 8B 46 06
                PUSH    AX                      ; 50
                MOV     AX, 11H                 ; B8 11 00
                PUSH    AX                      ; 50
                MOV     AX, 1                   ; B8 01 00
                PUSH    AX                      ; 50
                MOV     SI, BP                  ; 8B F5
                SUB     SI, 12H                 ; 83 EE 12
                PUSH    SI                      ; 56
                CALL    DWORD PTR cs:[2D2H]     ; 2E FF 1E D2 02
                ADD     SP, 8                   ; 83 C4 08
                POP     ES                      ; 07
                POP     DI                      ; 5F
                MOV     AX, DI                  ; 8B C7
                MOV     DX, ES                  ; 8C C2
                MOV     CX, 9                   ; B9 09 00
                REP     MOVSW                   ; F3 A5    dead store (result unused)
tan_slot19_exit:
                POP     DI                      ; 5F
                POP     SI                      ; 5E
                ADD     SP, 12H                 ; 83 C4 12
                POP     BP                      ; 5D
                RETF                            ; CB
tan_slot19      ENDP

; ============================================================================
; tan_slot20 -- Tandy hardware palette set (slot repurposed from putpixel).
; chunk:0x0B9E..0x0BEE
;
; STRUCTURAL DIVERGENCE: this slot is "putpixel" on other drivers but
; programs the Tandy palette here.
;
; ABI: __cdecl16far(BorlandFarPtr palette_src_far) -> void.
;
; Programs the 16 gate-array palette regs (internal indices
; 0x10..0x1F) using the Tandy split-port index/data idiom:
;   OUT 0x3DA, 0x10+idx    -- select palette reg idx (0..15)
;   OUT 0x3DE, irgb_byte   -- 4-bit IRGB value
; (Tandy 1000 Service Manual Page 53; this is Tandy-specific --
; on PCjr the data byte would have to go to 0x3DA, not 0x3DE.
; See file-header "Tandy-only caveat".)
;
; Each input byte is in an 8-bit "I-shifted-up" format: bit 4 = the
; intensity bit, bits 0..2 = R/G/B. The loop body remaps bit 4 -> bit
; 3 and ANDs with 0x0F to produce the 4-bit IRGB byte the gate-array
; wants (bit 0 = Blue, bit 1 = Green, bit 2 = Red, bit 3 = Intensity --
; IBM PCjr Tech Ref Page 2-71). After all 16 entries, reads byte #17
; from the source as the overscan colour and forwards it through
; INT 10h AX=0x1001 (BIOS "Set Border Colour Register" -- the BIOS
; in turn programs gate-array internal register 0x02).
; ============================================================================
tan_slot20      PROC    FAR
                PUSH    BP                      ; 55
                MOV     BP, SP                  ; 8B EC
                PUSH    SI                      ; 56
                PUSH    DI                      ; 57
                PUSH    DS                      ; 1E
                MOV     DS, cs:[206H]           ; 2E 8E 1E 06 02
                MOV     SI, [BP+6]              ; 8B 76 06
                MOV     AX, [BP+8]              ; 8B 46 08
                OR      AX, AX                  ; 0B C0
                JZ      SHORT tan_slot20_exit   ; 74 37
                MOV     ds:[GfxContext.pPaletteScratchBuf], SI           ; 89 36 9E 01    save palette src ptr
                MOV     ds:[GfxContext.pPaletteScratchBuf+2], AX           ; A3 A0 01
                MOV     DS, AX                  ; 8E D8
                XOR     DI, DI                  ; 33 FF
                MOV     CX, 03DAH               ; B9 DA 03       gate-array index port
                MOV     BP, 03DEH               ; BD DE 03       gate-array data port
tan_slot20_loop:
                MOV     AX, DI                  ; 8B C7
                ADD     AL, 10H                 ; 04 10          0x10+idx selects palette reg N
                MOV     DX, CX                  ; 8B D1
                OUT     DX, AL                  ; EE
                LODSB                           ; AC
                TEST    AL, 10H                 ; A8 10          bit 4 of input = I (intensity)
                JZ      SHORT tan_slot20_no_int ; 74 02
                OR      AL, 8                   ; 0C 08          move it down to bit 3
tan_slot20_no_int:
                AND     AL, 0FH                 ; 24 0F          keep 4-bit IRGB
                MOV     DX, BP                  ; 8B D5
                OUT     DX, AL                  ; EE
                INC     DI                      ; 47
                CMP     DI, 10H                 ; 83 FF 10
                JL      SHORT tan_slot20_loop   ; 7C E7
                MOV     DX, CX                  ; 8B D1
                XOR     AL, AL                  ; 32 C0
                OUT     DX, AL                  ; EE              park gate-array index at reg 0
                LODSB                           ; AC
                MOV     BH, AL                  ; 8A F8
                MOV     AX, 1001H               ; B8 01 10
                INT     10H                     ; CD 10
tan_slot20_exit:
                POP     DS                      ; 1F
                POP     DI                      ; 5F
                POP     SI                      ; 5E
                POP     BP                      ; 5D
                RETF                            ; CB
tan_slot20      ENDP

; ============================================================================
; tan_slot13 -- sum sprite memory footprint across a list.
; chunk:0x0BEF..0x0C2F
;
; Walks a NULL-terminated list of sprite descriptor near-pointers passed
; via [BP+6]; for each descriptor accumulates (width / 8) * height bytes
; into a 32-bit total (CX:BX), then multiplies by 4 and writes the high
; word into the caller's out-slot [BP+8]+0 (zero on success). The low
; word is returned in AX.
;
; ABI: __cdecl16far(near_sprite_list, ushort *out_slot).
; ============================================================================
tan_slot13      PROC    FAR
                PUSH    BP                      ; 55
                MOV     BP, SP                  ; 8B EC
                PUSH    SI                      ; 56
                PUSH    DI                      ; 57
                MOV     DI, [BP+6]              ; 8B 7E 06
                XOR     BX, BX                  ; 33 DB
                XOR     CX, CX                  ; 33 C9
tan_slot13_loop:
                MOV     SI, [DI]                ; 8B 35
                OR      SI, SI                  ; 0B F6
                JZ      SHORT tan_slot13_done   ; 74 18
                MOV     AX, [SI+6]              ; 8B 44 06         width
                SHR     AX, 1                   ; D1 E8
                SHR     AX, 1                   ; D1 E8
                SHR     AX, 1                   ; D1 E8            /8
                MOV     DX, [SI+8]              ; 8B 54 08         height
                MUL     DX                      ; F7 E2
                ADD     BX, AX                  ; 03 D8
                ADC     CX, 0                   ; 83 D1 00
                ADD     DI, 2                   ; 83 C7 02
                JMP     SHORT tan_slot13_loop   ; EB E2
tan_slot13_done:
                MOV     DX, CX                  ; 8B D1
                MOV     AX, BX                  ; 8B C3
                SHL     AX, 1                   ; D1 E0
                RCL     DX, 1                   ; D1 D2
                SHL     AX, 1                   ; D1 E0
                RCL     DX, 1                   ; D1 D2            *4
                MOV     SI, [BP+8]              ; 8B 76 08
                MOV     WORD PTR [SI], 0        ; C7 04 00 00
                POP     DI                      ; 5F
                POP     SI                      ; 5E
                POP     BP                      ; 5D
                RETF                            ; CB
tan_slot13      ENDP

; ============================================================================
; tan_slot14 -- install / assign segment+offset slots from a sprite list.
; chunk:0x0C30..0x0C73
;
; Walks a NULL-terminated list of descriptor pointers (BX = list head =
; [BP+6]). For each non-NULL descriptor at *BX, writes [BP+0Ah] as the
; descriptor's segment ([SI+0]) and [BP+8] as the descriptor's offset
; ([SI+2]). Then advances the running cursor: pixels = (width/2)*height,
; bytes = pixels+offset; advance segment by (bytes>>4) paragraphs and
; offset to (bytes & 0xF).
;
; ABI: __cdecl16far(near sprite_list, ushort *base_off, ushort *base_seg).
; ============================================================================
tan_slot14      PROC    FAR
                PUSH    BP                      ; 55
                MOV     BP, SP                  ; 8B EC
                PUSH    SI                      ; 56
                PUSH    DI                      ; 57
                MOV     BX, [BP+6]              ; 8B 5E 06
tan_slot14_loop:
                MOV     SI, [BX]                ; 8B 37
                OR      SI, SI                  ; 0B F6
                JNZ     SHORT tan_slot14_assign ; 75 02
                JMP     SHORT tan_slot14_done   ; EB 30
tan_slot14_assign:
                MOV     AX, [BP+0AH]            ; 8B 46 0A
                MOV     [SI], AX                ; 89 04
                MOV     AX, [BP+8]              ; 8B 46 08
                MOV     [SI+2], AX              ; 89 44 02
                MOV     AX, [SI+6]              ; 8B 44 06         width
                SHR     AX, 1                   ; D1 E8
                MOV     DX, [SI+8]              ; 8B 54 08         height
                MUL     DX                      ; F7 E2
                ADD     AX, [BP+8]              ; 03 46 08
                MOV     DX, AX                  ; 8B D0
                SHR     DX, 1                   ; D1 EA
                SHR     DX, 1                   ; D1 EA
                SHR     DX, 1                   ; D1 EA
                SHR     DX, 1                   ; D1 EA
                ADD     [BP+0AH], DX            ; 01 56 0A
                AND     AX, 0FH                 ; 25 0F 00
                MOV     [BP+8], AX              ; 89 46 08
                ADD     BX, 2                   ; 83 C3 02
                JMP     SHORT tan_slot14_loop   ; EB C8
tan_slot14_done:
                POP     DI                      ; 5F
                POP     SI                      ; 5E
                POP     BP                      ; 5D
                RETF                            ; CB
tan_slot14      ENDP

; ============================================================================
; tan_slot3 -- flags=0 wrapper around tan_slot29 (sprite blit, no flip).
; chunk:0x0C74..0x0C8D
;
; Forwards the caller's 3 args (sprite_ptr, x, y) into tan_slot29 with
; an extra leading flip_flags=0 argument. Effectively: this slot is the
; "no-flip" sprite-blit entry, while slot 29 (tan_slot29) is the full
; flip-aware entry.
;
; Stack action: pushes (0, [BP+0A], [BP+8], [BP+6]) onto stack, far-
; calls tan_slot29, then `ADD SP, 8` removes the 4 pushed args. The
; trailing `MOV BP, SP / POP BP` is redundant (BP is already at the
; right place after ADD SP, 8).
;
; ABI: __cdecl16far(sprite_ptr_seg, sprite_ptr_off, xy_pair) -> void.
;   (Same first 3 args as tan_slot29; flip_flags forced to 0.)
; ============================================================================
tan_slot3       PROC    FAR
                PUSH    BP                      ; 55
                MOV     BP, SP                  ; 8B EC
                XOR     AX, AX                  ; 33 C0
                PUSH    AX                      ; 50
                PUSH    WORD PTR [BP+0AH]       ; FF 76 0A
                PUSH    WORD PTR [BP+8]         ; FF 76 08
                PUSH    WORD PTR [BP+6]         ; FF 76 06
                PUSH    CS                      ; 0E
                CALL    tan_slot29_fwd          ; E8 .. ..
                ADD     SP, 8                   ; 83 C4 08
                MOV     BP, SP                  ; 8B EC
                POP     BP                      ; 5D
                RETF                            ; CB
tan_slot3       ENDP

; ============================================================================
; tan_slot1 -- glyph-row / sprite blit (1-bpp -> 4-bpp expand).
; chunk:0x0C8E..0x0DAD
;
; ABI (register + DS-load):
;   DS:SI -- sprite/glyph descriptor pointer (caller's DS)
;   BP    -- row index (multiplied by 2, used as row LUT index)
;   DX    -- starting column (split into byte offset + pixel parity)
;   CX    -- row count for the outer loop (CX is moved into BP at
;            the top so CX itself can be reused as the per-byte bit
;            counter (CL = 8) by the inner LODSB / LOOP pump).
;   AX (entry) -- mask / colour byte
;
; The function reads bytes [DS:0..2]:
;   [0] foreground colour (low nibble); replicates to fill a byte in BL/BH
;   [1] tile-row pattern selector / dither byte (loaded into DH)
;   [2] mode flag: 0 -> simple 1-bpp expand (high path),
;                 nonzero -> dithered/textured pump (low path)
; ============================================================================
tan_slot1       PROC    FAR
                PUSH    DI                      ; 57
                PUSH    BP                      ; 55
                PUSH    DS                      ; 1E
                PUSH    ES                      ; 06
                PUSH    AX                      ; 50
                MOV     DS, cs:[206H]           ; 2E 8E 1E 06 02
                MOV     AX, ds:[GfxContext.wGfxBlitDstPage]            ; A1 18 00
                CMP     WORD PTR ds:[6E2H], 0   ; 83 3E E2 06 00
                JZ      SHORT tan_slot1_no_flip ; 74 08
                PUSH    AX                      ; 50
                PUSH    CS                      ; 0E
                CALL    tan_slot28_fwd          ; E8 .. ..
                ADD     SP, 2                   ; 83 C4 02
tan_slot1_no_flip:
                MOV     ES, AX                  ; 8E C0
                POP     AX                      ; 58
                SHL     BP, 1                   ; D1 E5
                MOV     DI, ds:[BP].pRow_offset_lut        ; 3E 8B BE F2 06   row LUT
                MOV     BP, DX                  ; 8B EA
                SHR     BP, 1                   ; D1 ED
                ADD     DI, BP                  ; 03 FD
                MOV     BP, CX                  ; 8B E9
                AND     DL, 1                   ; 80 E2 01
                MOV     DH, CL                  ; 8A F1
                MOV     BL, ds:[GfxContext.bText_fg_color]              ; 8A 1E 00 00     fg colour byte
                MOV     BH, BL                  ; 8A FB
                SHL     BH, 1                   ; D0 E7
                SHL     BH, 1                   ; D0 E7
                SHL     BH, 1                   ; D0 E7
                SHL     BH, 1                   ; D0 E7
                AND     BX, 0F00FH              ; 81 E3 0F F0
                MOV     DH, ds:[GfxContext.bText_bg_color]              ; 8A 36 01 00
                MOV     AH, ds:[GfxContext.bText_style_flags]              ; 8A 26 02 00
                POP     DS                      ; 1F
                OR      AH, AH                  ; 0A E4
                JZ      tan_slot1_dith          ; 74 52   -> 0x0D32
tan_slot1_plain_row:
                MOV     CL, 8                   ; B1 08
                LODSB                           ; AC
                MOV     AH, AL                  ; 8A E0
tan_slot1_p_step:
                SHL     AH, 1                   ; D0 E4
                JC      SHORT tan_slot1_p_set   ; 72 0C
                TEST    DL, 1                   ; F6 C2 01
                JZ      SHORT tan_slot1_p_no_advance ; 74 01
                INC     DI                      ; 47
tan_slot1_p_no_advance:
                INC     DL                      ; FE C2
                LOOP    SHORT tan_slot1_p_step  ; E2 F2
                JMP     SHORT tan_slot1_p_eor   ; EB 24
tan_slot1_p_set:
                TEST    DL, 1                   ; F6 C2 01
                JNZ     SHORT tan_slot1_p_set_low ; 75 10
                MOV     AL, ES:[DI]             ; 26 8A 05
                AND     AL, 0FH                 ; 24 0F
                OR      AL, BH                  ; 0A C7
                MOV     ES:[DI], AL             ; 26 88 05
                INC     DL                      ; FE C2
                LOOP    SHORT tan_slot1_p_step  ; E2 DD
                JMP     SHORT tan_slot1_p_eor   ; EB 0F
tan_slot1_p_set_low:
                MOV     AL, ES:[DI]             ; 26 8A 05
                AND     AL, 0F0H                ; 24 F0
                OR      AL, BL                  ; 0A C3
                MOV     ES:[DI], AL             ; 26 88 05
                INC     DL                      ; FE C2
                INC     DI                      ; 47
                LOOP    SHORT tan_slot1_p_step  ; E2 CC
tan_slot1_p_eor:
                ADD     DI, 1FFCH               ; 81 C7 FC 1F
                TEST    DI, 8000H               ; F7 C7 00 80
                JZ      SHORT tan_slot1_p_no_bank ; 74 08
                AND     DI, 7FFFH               ; 81 E7 FF 7F
                ADD     DI, 0A0H                ; 81 C7 A0 00
tan_slot1_p_no_bank:
                DEC     BP                      ; 4D
                JNZ     tan_slot1_plain_row     ; 75 B2
                POP     DS                      ; 1F
                POP     BP                      ; 5D
                POP     DI                      ; 5F
                RETF                            ; CB
tan_slot1_dith:
                MOV     CL, 8                   ; B1 08
                LODSB                           ; AC
                MOV     AH, AL                  ; 8A E0
tan_slot1_d_step:
                SHL     AH, 1                   ; D0 E4
                JC      tan_slot1_d_set         ; 72 36
                TEST    DL, 1                   ; F6 C2 01
                JNZ     SHORT tan_slot1_d_low   ; 75 20
                MOV     AL, ES:[DI]             ; 26 8A 05
                AND     AL, 0FH                 ; 24 0F
                SHL     DH, 1                   ; D0 E6
                SHL     DH, 1                   ; D0 E6
                SHL     DH, 1                   ; D0 E6
                SHL     DH, 1                   ; D0 E6
                OR      AL, DH                  ; 0A C6
                SHR     DH, 1                   ; D0 EE
                SHR     DH, 1                   ; D0 EE
                SHR     DH, 1                   ; D0 EE
                SHR     DH, 1                   ; D0 EE
                MOV     ES:[DI], AL             ; 26 88 05
                INC     DL                      ; FE C2
                LOOP    SHORT tan_slot1_d_step  ; E2 D9
                JMP     SHORT tan_slot1_d_eor   ; EB 35
tan_slot1_d_low:
                MOV     AL, ES:[DI]             ; 26 8A 05
                AND     AL, 0F0H                ; 24 F0
                OR      AL, DH                  ; 0A C6
                MOV     ES:[DI], AL             ; 26 88 05
                INC     DI                      ; 47
                INC     DL                      ; FE C2
                LOOP    SHORT tan_slot1_d_step  ; E2 C8
                JMP     SHORT tan_slot1_d_eor   ; EB 24
tan_slot1_d_set:
                TEST    DL, 1                   ; F6 C2 01
                JNZ     SHORT tan_slot1_d_set_low ; 75 10
                MOV     AL, ES:[DI]             ; 26 8A 05
                AND     AL, 0FH                 ; 24 0F
                OR      AL, BH                  ; 0A C7
                MOV     ES:[DI], AL             ; 26 88 05
                INC     DL                      ; FE C2
                LOOP    SHORT tan_slot1_d_step  ; E2 B3
                JMP     SHORT tan_slot1_d_eor   ; EB 0F
tan_slot1_d_set_low:
                MOV     AL, ES:[DI]             ; 26 8A 05
                AND     AL, 0F0H                ; 24 F0
                OR      AL, BL                  ; 0A C3
                MOV     ES:[DI], AL             ; 26 88 05
                INC     DL                      ; FE C2
                INC     DI                      ; 47
                LOOP    SHORT tan_slot1_d_step  ; E2 A2
tan_slot1_d_eor:
                ADD     DI, 1FFCH               ; 81 C7 FC 1F
                TEST    DI, 8000H               ; F7 C7 00 80
                JZ      SHORT tan_slot1_d_no_bank ; 74 08
                AND     DI, 7FFFH               ; 81 E7 FF 7F
                ADD     DI, 0A0H                ; 81 C7 A0 00
tan_slot1_d_no_bank:
                DEC     BP                      ; 4D
                JNZ     tan_slot1_dith          ; 75 88
                POP     DS                      ; 1F
                POP     BP                      ; 5D
                POP     DI                      ; 5F
                RETF                            ; CB
tan_slot1       ENDP

; ============================================================================
; g_wTanSlot3Filler0dae -- 2-byte scratch slot used by tan_slot5.
; chunk:0x0DAE..0x0DAF
;
; Holds the resolved framebuffer page (B800 or B000 alias) for the
; duration of one tan_slot5 call. Written at 0x0DCE, read at 0x0E13.
; Zero-initialised.
; ============================================================================
g_wTanSlot3Filler0dae DW 0

; ============================================================================
; tan_slot5 -- rect copy from scratch DS to framebuffer (display page).
; chunk:0x0DB0..0x0E2F
;
; ABI: __cdecl16far(x_src, y_src_seg_pair, x_dst, y_dst, w, h).
;   [BP+6]  ushort  source byte offset within source segment
;   [BP+8]  ushort  source segment paragraph
;   [BP+0A] ushort  starting x (in pixels) on destination
;   [BP+0C] ushort  starting y (row index on destination)
;   [BP+0E] ushort  destination x_end (exclusive)
;   [BP+10] ushort  row count
;
; Algorithm:
;   1. Resolve framebuffer ES segment (B800 or B000 alias) and stash
;      in CS:[0x0DAE].
;   2. Convert (x_src/16 + [BP+8]) to ES paragraph; DI := x & 0xF.
;   3. Walk row LUT at scratch:[6F2 + 2*y_dst]; per row, REP MOVSW
;      width words from source DS:SI to ES:DI.
; ============================================================================
tan_slot5       PROC    FAR
                PUSH    BP                      ; 55
                MOV     BP, SP                  ; 8B EC
                PUSH    SI                      ; 56
                PUSH    DI                      ; 57
                PUSH    DS                      ; 1E
                PUSH    ES                      ; 06
                MOV     DS, cs:[206H]           ; 2E 8E 1E 06 02
                MOV     AX, ds:[GfxContext.wGfxBlitSrcPage]            ; A1 16 00
                CMP     WORD PTR ds:[6E2H], 0   ; 83 3E E2 06 00
                JZ      SHORT tan_slot5_no_flip ; 74 08
                PUSH    AX                      ; 50
                PUSH    CS                      ; 0E
                CALL    tan_slot28_fwd          ; E8 BC 01
                ADD     SP, 2                   ; 83 C4 02
tan_slot5_no_flip:
                MOV     cs:[0DAEH], AX          ; 2E A3 AE 0D
                MOV     AX, [BP+6]              ; 8B 46 06
                MOV     DI, AX                  ; 8B F8
                SHR     AX, 1                   ; D1 E8
                SHR     AX, 1                   ; D1 E8
                SHR     AX, 1                   ; D1 E8
                SHR     AX, 1                   ; D1 E8
                AND     DI, 0FH                 ; 83 E7 0F
                ADD     AX, [BP+8]              ; 03 46 08
                MOV     ES, AX                  ; 8E C0
                MOV     SI, [BP+0AH]            ; 8B 76 0A
                MOV     AX, SI                  ; 8B C6
                SHR     SI, 1                   ; D1 EE
                MOV     BX, [BP+0EH]            ; 8B 5E 0E
                ADD     BX, AX                  ; 03 D8
                SHR     BX, 1                   ; D1 EB
                SUB     BX, SI                  ; 2B DE
                INC     BX                      ; 43
                MOV     AX, BX                  ; 8B C3
                SHR     BX, 1                   ; D1 EB
                AND     AX, 1                   ; 25 01 00
                JZ      SHORT tan_slot5_no_odd  ; 74 01
                INC     BX                      ; 43
tan_slot5_no_odd:
                MOV     DX, [BP+10H]            ; 8B 56 10
                MOV     BP, [BP+0CH]            ; 8B 6E 0C
                SHL     BP, 1                   ; D1 E5
                LEA     BP, [BP].pRow_offset_lut           ; 8D AE F2 06
                ADD     BP, cs:[208H]           ; 2E 03 2E 08 02
                MOV     AX, cs:[0DAEH]          ; 2E A1 AE 0D
                MOV     DS, AX                  ; 8E D8
                MOV     AX, SI                  ; 8B C6
tan_slot5_row:
                MOV     CX, BX                  ; 8B CB
                MOV     SI, [BP+0]              ; 8B 76 00
                ADD     SI, AX                  ; 03 F0
                REP     MOVSW                   ; F3 A5
                ADD     BP, 2                   ; 83 C5 02
                DEC     DX                      ; 4A
                JNZ     SHORT tan_slot5_row     ; 75 F1
                POP     ES                      ; 07
                POP     DS                      ; 1F
                POP     DI                      ; 5F
                POP     SI                      ; 5E
                POP     BP                      ; 5D
                RETF                            ; CB
tan_slot5       ENDP

; ============================================================================
; tan_slot6 -- compute byte count for a rect-copy area.
; chunk:0x0E30..0x0E4E
;
; ABI: __cdecl16far(ushort width, ushort height) -> ushort byte_count.
;   byte_count = ((width / 2) + 1, rounded up to even) * height
; ============================================================================
tan_slot6       PROC    FAR
                PUSH    BP                      ; 55
                MOV     BP, SP                  ; 8B EC
                MOV     AX, [BP+6]              ; 8B 46 06
                MOV     BX, AX                  ; 8B D8
                SHR     BX, 1                   ; D1 EB
                INC     BX                      ; 43
                AND     AX, 1                   ; 25 01 00
                JZ      SHORT tan_slot6_no_odd  ; 74 01
                INC     BX                      ; 43
tan_slot6_no_odd:
                TEST    BX, 1                   ; F7 C3 01 00
                JZ      SHORT tan_slot6_even    ; 74 01
                INC     BX                      ; 43
tan_slot6_even:
                MOV     AX, [BP+8]              ; 8B 46 08
                MUL     BX                      ; F7 E3
                POP     BP                      ; 5D
                RETF                            ; CB
tan_slot6       ENDP

; ============================================================================
; tan_slot7 -- rect copy from framebuffer to scratch DS (save-rect).
; chunk:0x0E4F..0x0EC6
;
; Inverse of tan_slot5: reads framebuffer rect into a destination
; buffer in caller's segment.
;
; ABI: __cdecl16far(x_dst, y_dst_seg_pair, x_src, y_src, x_end, h).
; ============================================================================
tan_slot7       PROC    FAR
                PUSH    BP                      ; 55
                MOV     BP, SP                  ; 8B EC
                PUSH    SI                      ; 56
                PUSH    DI                      ; 57
                PUSH    DS                      ; 1E
                PUSH    ES                      ; 06
                MOV     DS, cs:[206H]           ; 2E 8E 1E 06 02
                MOV     AX, ds:[GfxContext.wGfxBlitDstPage]            ; A1 18 00
                CMP     WORD PTR ds:[6E2H], 0   ; 83 3E E2 06 00
                JZ      SHORT tan_slot7_no_flip ; 74 08
                PUSH    AX                      ; 50
                PUSH    CS                      ; 0E
                CALL    tan_slot28_fwd          ; E8 1D 01
                ADD     SP, 2                   ; 83 C4 02
tan_slot7_no_flip:
                MOV     ES, AX                  ; 8E C0
                MOV     AX, [BP+6]              ; 8B 46 06
                MOV     SI, AX                  ; 8B F0
                SHR     AX, 1                   ; D1 E8
                SHR     AX, 1                   ; D1 E8
                SHR     AX, 1                   ; D1 E8
                SHR     AX, 1                   ; D1 E8
                AND     SI, 0FH                 ; 83 E6 0F
                ADD     AX, [BP+8]              ; 03 46 08
                MOV     DS, AX                  ; 8E D8
                MOV     DI, [BP+0AH]            ; 8B 7E 0A
                MOV     AX, DI                  ; 8B C7
                SHR     DI, 1                   ; D1 EF
                MOV     BX, [BP+0EH]            ; 8B 5E 0E
                ADD     BX, AX                  ; 03 D8
                SHR     BX, 1                   ; D1 EB
                SUB     BX, DI                  ; 2B DF
                INC     BX                      ; 43
                MOV     AX, BX                  ; 8B C3
                SHR     BX, 1                   ; D1 EB
                AND     AX, 1                   ; 25 01 00
                JZ      SHORT tan_slot7_no_odd  ; 74 01
                INC     BX                      ; 43
tan_slot7_no_odd:
                MOV     DX, [BP+10H]            ; 8B 56 10
                MOV     BP, [BP+0CH]            ; 8B 6E 0C
                SHL     BP, 1                   ; D1 E5
                LEA     BP, [BP].pRow_offset_lut           ; 8D AE F2 06
                ADD     BP, cs:[208H]           ; 2E 03 2E 08 02
                MOV     AX, DI                  ; 8B C7
tan_slot7_row:
                MOV     CX, BX                  ; 8B CB
                MOV     DI, [BP+0]              ; 8B 7E 00
                ADD     DI, AX                  ; 03 F8
                REP     MOVSW                   ; F3 A5
                ADD     BP, 2                   ; 83 C5 02
                DEC     DX                      ; 4A
                JNZ     SHORT tan_slot7_row     ; 75 F1
                POP     ES                      ; 07
                POP     DS                      ; 1F
                POP     DI                      ; 5F
                POP     SI                      ; 5E
                POP     BP                      ; 5D
                RETF                            ; CB
tan_slot7       ENDP

; ============================================================================
; tan_slot21 -- read one pixel from a saved-rect descriptor.
; chunk:0x0EC7..0x0EE9
;
; Helper that asks tan_helper_0f13 to resolve a (col, row) into ES:BX
; and a shift-count CL, then reads the framebuffer byte and shifts to
; extract the pixel nibble.
; ============================================================================
tan_slot21      PROC    FAR
                PUSH    BP                      ; 55
                MOV     BP, SP                  ; 8B EC
                MOV     CX, [BP+8]              ; 8B 4E 08
                MOV     BX, [BP+6]              ; 8B 5E 06
                MOV     DS, cs:[206H]           ; 2E 8E 1E 06 02
                MOV     AX, ds:[GfxContext.wGfxBlitSrcPage]            ; A1 16 00
                CALL    tan_helper_0f13_fwd     ; E8 38 00
                MOV     AL, ES:[BX]             ; 26 8A 07
                SHR     AL, CL                  ; D2 E8
                AND     AL, AH                  ; 22 C4
                XOR     AH, AH                  ; 32 E4
                MOV     DX, SS                  ; 8C D2
                MOV     DS, DX                  ; 8E DA
                POP     BP                      ; 5D
                RETF                            ; CB
tan_slot21      ENDP

; ============================================================================
; tan_slot22 -- write one pixel via the helper-resolved descriptor.
; chunk:0x0EEA..0x0F12
;
; Mirror of tan_slot21 but writes pixel value [BP+0Ah] & 0xF after
; appropriately shifting and masking.
; ============================================================================
tan_slot22      PROC    FAR
                PUSH    BP                      ; 55
                MOV     BP, SP                  ; 8B EC
                MOV     CX, [BP+8]              ; 8B 4E 08
                MOV     BX, [BP+6]              ; 8B 5E 06
                MOV     DS, cs:[206H]           ; 2E 8E 1E 06 02
                MOV     AX, ds:[GfxContext.wGfxBlitDstPage]            ; A1 18 00
                CALL    tan_helper_0f13_fwd     ; E8 15 00
                MOV     AL, [BP+0AH]            ; 8A 46 0A
                AND     AL, 0FH                 ; 24 0F
                SHL     AX, CL                  ; D3 E0
                NOT     AH                      ; F6 D4
                AND     ES:[BX], AH             ; 26 20 27
                OR      ES:[BX], AL             ; 26 08 07
                MOV     DX, SS                  ; 8C D2
                MOV     DS, DX                  ; 8E DA
                POP     BP                      ; 5D
                RETF                            ; CB
tan_slot22      ENDP

; ============================================================================
; tan_helper_0f13 -- pixel-address resolver (NEAR PROC, RET not RETF).
; chunk:0x0F13..0x0F41
;
; Resolves (col, row) given in BX:CX (and a candidate framebuffer
; segment in AX) to ES:BX byte address + CL shift count.
;
; ABI:
;   AX (in)   -- candidate framebuffer segment
;   BX (in)   -- column (pixel x)
;   CX (in)   -- row (y)
;   ES (out)  -- framebuffer segment after possible alias swap
;   BX (out)  -- byte address within ES
;   CL (out)  -- 0 or 4 (shift count for the pixel nibble)
;   AH (out)  -- 0x0F mask
; ============================================================================
tan_helper_0f13 PROC    NEAR
                CMP     WORD PTR ds:[6E2H], 0   ; 83 3E E2 06 00
                JZ      SHORT tan_helper_0f13_no_flip ; 74 08
                PUSH    AX                      ; 50
                PUSH    CS                      ; 0E
                CALL    tan_slot28_fwd          ; E8 68 00
                ADD     SP, 2                   ; 83 C4 02
tan_helper_0f13_no_flip:
                MOV     ES, AX                  ; 8E C0
                MOV     AX, CX                  ; 8B C1
                XCHG    AX, BX                  ; 93
                SHL     BX, 1                   ; D1 E3
                LEA     BX, [BX].pRow_offset_lut           ; 8D 9F F2 06
                MOV     BX, [BX]                ; 8B 1F            row LUT[2*y]
                MOV     CL, AL                  ; 8A C8
                SHR     AX, 1                   ; D1 E8
                ADD     BX, AX                  ; 03 D8            BX = row + col/2
                MOV     AH, 0FH                 ; B4 0F
                MOV     AL, CL                  ; 8A C1
                MOV     CL, 4                   ; B1 04
                AND     AL, 1                   ; 24 01
                JZ      SHORT tan_helper_0f13_ret ; 74 02
                XOR     CL, CL                  ; 32 C9            CL = 0 for low-nibble
tan_helper_0f13_ret:
                RET                             ; C3
tan_helper_0f13 ENDP

; ============================================================================
; g_wTanPageFlipExtraBit / g_wTanCurrentDisplayPage
; chunk:0x0F42 / 0x0F44 -- 2 + 2 bytes runtime scratch.
;
; Runtime state holding the current display-page flip bit and CRT
; page number.
; ============================================================================
g_wTanPageFlipExtraBit   DW 0       ; initial: no flip
g_wTanCurrentDisplayPage DW 1       ; initial display page = 1

; ============================================================================
; tan_slot8 -- page-flip (toggle the Tandy display page).
; chunk:0x0F46..0x0F86
;
; The "show the back buffer / start drawing into the now-hidden old
; front" operation. Toggles the CRT/Processor Page Register at 0x3DF
; and updates the chunk-local mirrors of "which segment is currently
; being scanned by the CRT" (scratch:[0x14]) vs "which segment the
; CPU should write into" (scratch:[0x12]).
;
; Algorithm:
;   1. Save current g_wTanPageFlipExtraBit to g_wTanCurrentDisplayPage.
;   2. XOR g_wTanPageFlipExtraBit with 1 (toggle).
;   3. Emit `OUT 0x3DF, 0xF4` when the new bit is 1, else 0xE6.
;      0xF4 = CPU page 6 / CRT page 4; 0xE6 = CPU page 4 / CRT page 6
;      (in both cases addr mode 3 = 32-KiB-aperture mode 9). The two
;      values swap which physical page the CRT scans vs which the CPU
;      writes -- i.e. classic page flip.
;   4. Index the page-pair table at scratch:[0x6E4]/[0x6E6] using the
;      new flip bit (BX*2 picks one of the two saved segs) and store
;      into scratch:[0x14] (display = visible). XOR the bit and repeat
;      to store the OTHER seg into scratch:[0x12] (processor = back
;      buffer).
;
; ABI: __cdecl16far -> void. Reachable via vtable.
; ============================================================================
tan_slot8      PROC    FAR
                PUSH    DS                      ; 1E
                MOV     DS, cs:[206H]           ; 2E 8E 1E 06 02
                MOV     DX, 03DFH               ; BA DF 03
                MOV     AL, 0F4H                ; B0 F4
                MOV     AH, cs:[0F42H]          ; 2E 8A 26 42 0F
                MOV     cs:[0F44H], AH          ; 2E 88 26 44 0F  save current page
                XOR     BYTE PTR cs:[0F42H], 1  ; 2E 80 36 42 0F 01
                JZ      SHORT tan_slot8_emit   ; 74 02
                MOV     AL, 0E6H                ; B0 E6
tan_slot8_emit:
                OUT     DX, AL                  ; EE
                MOV     BX, cs:[0F42H]          ; 2E 8B 1E 42 0F
                MOV     AX, BX                  ; 8B C3
                SHL     BX, 1                   ; D1 E3
                MOV     BX, [BX+6E4H]           ; 8B 9F E4 06
                MOV     ds:[GfxContext.wVgaFrontPageBase], BX            ; 89 1E 14 00
                MOV     BX, AX                  ; 8B D8
                XOR     BL, 1                   ; 80 F3 01
                SHL     BX, 1                   ; D1 E3
                MOV     AX, [BX+6E4H]           ; 8B 87 E4 06
                MOV     ds:[GfxContext.wVgaPage2Base], AX            ; A3 12 00
                POP     DS                      ; 1F
                RETF                            ; CB
tan_slot8      ENDP

; ============================================================================
; tan_slot28 -- resolve framebuffer segment respecting page-flip state.
; chunk:0x0F87..0x0FDC
;
; ABI (__cdecl16far):
;   [BP+6]  ushort  requested segment (B000 alias or B800)
;   Returns AX = resolved segment (after applying the alias swap
;   based on g_wTanPageFlipExtraBit + g_wTanCurrentDisplayPage).
;
; Also writes the CRT/Processor Page Register at port 0x3DF, composing
; the byte from a base of 0xE4 by OR'ing in bit 4 (CPU page +2 -> page
; 6) when the requested segment maps to the "alt" page, and bit 1 (CRT
; page +2 -> page 6) when g_wTanPageFlipExtraBit is set. This yields
; one of 0xE4 / 0xF4 / 0xE6 / 0xF6 -- the four (CRT page, CPU page)
; combinations of {4, 6} x {4, 6} at addr mode 3.
;
; Called from tan_slot2/tan_slot27/tan_slot1/tan_slot5/tan_slot7/
; tan_slot20/tan_helper_0f13 -- 6 in-chunk callers.
; ============================================================================
tan_slot28      PROC    FAR
                PUSH    BP                      ; 55
                MOV     BP, SP                  ; 8B EC
                PUSH    BX                      ; 53
                PUSH    DX                      ; 52
                MOV     BL, 0E4H                ; B3 E4
                MOV     AX, [BP+6]              ; 8B 46 06
                CMP     AX, 0B000H              ; 3D 00 B0
                JZ      SHORT tan_slot28_b000   ; 74 16
                CMP     AX, 0B800H              ; 3D 00 B8
                JNZ     SHORT tan_slot28_done   ; 75 3B
                CMP     WORD PTR cs:[0F44H], 1  ; 2E 83 3E 44 0F 01
                JZ      SHORT tan_slot28_done   ; 74 33
                MOV     WORD PTR cs:[0F44H], 1  ; 2E C7 06 44 0F 01 00
                JMP     SHORT tan_slot28_alt    ; EB 16
tan_slot28_b000:
                MOV     WORD PTR [BP+6], 0B800H ; C7 46 06 00 B8
                CMP     WORD PTR cs:[0F44H], 0  ; 2E 83 3E 44 0F 00
                JZ      SHORT tan_slot28_done   ; 74 1D
                MOV     WORD PTR cs:[0F44H], 0  ; 2E C7 06 44 0F 00 00
                JMP     SHORT tan_slot28_after  ; EB 03
tan_slot28_alt:
                OR      BL, 10H                 ; 80 CB 10
tan_slot28_after:
                CMP     WORD PTR cs:[0F42H], 0  ; 2E 83 3E 42 0F 00
                JZ      SHORT tan_slot28_emit   ; 74 03
                OR      BL, 2                   ; 80 CB 02
tan_slot28_emit:
                MOV     AL, BL                  ; 8A C3
                MOV     DX, 03DFH               ; BA DF 03
                OUT     DX, AL                  ; EE
tan_slot28_done:
                MOV     AX, [BP+6]              ; 8B 46 06
                POP     DX                      ; 5A
                POP     BX                      ; 5B
                POP     BP                      ; 5D
                RETF                            ; CB
tan_slot28      ENDP

; ============================================================================
; tan_slot4 -- rect copy between framebuffer-or-buffer pages.
; chunk:0x0FDD..0x1124
;
; Big rect copier with two paths: a plain REP MOVSW path when source and
; destination are both in scratch DS (or one alias resolved away), and a
; page-flipping path when both source and dest reference B-band frame-
; buffer segments and we need to ping-pong the CRT/Processor Page
; Register at 0x3DF between "source page mapped to CPU" and "dest page
; mapped to CPU" between each pair of reads/writes so a single B800:
; aperture can address two physically-distinct 16 KiB pages within one
; inner iteration.
;
; ABI: __cdecl16far(x_dst, x_src, y_pair, h, w_pair, ...).
; ============================================================================
tan_slot4       PROC    FAR
                PUSH    BP                      ; 55
                MOV     BP, SP                  ; 8B EC
                SUB     SP, 8                   ; 83 EC 08
                PUSH    SI                      ; 56
                PUSH    DI                      ; 57
                PUSH    DS                      ; 1E
                PUSH    ES                      ; 06
                MOV     DS, cs:[206H]           ; 2E 8E 1E 06 02
                MOV     BX, [BP+0AH]            ; 8B 5E 0A
                MOV     AX, [BP+6]              ; 8B 46 06
                ADD     BX, AX                  ; 03 D8
                ADD     BX, 1                   ; 83 C3 01
                AND     BX, 0FFFEH              ; 83 E3 FE
                AND     AX, 0FFFEH              ; 25 FE FF
                SUB     BX, AX                  ; 2B D8
                SHR     BX, 1                   ; D1 EB
                SHR     AX, 1                   ; D1 E8
                MOV     SI, AX                  ; 8B F0
                MOV     DX, [BP+0CH]            ; 8B 56 0C
                MOV     DI, [BP+8]              ; 8B 7E 08
                SHL     DI, 1                   ; D1 E7
                LEA     DI, [DI].pRow_offset_lut           ; 8D BD F2 06
                CMP     BYTE PTR ds:[6E2H], 0   ; 80 3E E2 06 00
                JZ      SHORT tan_slot4_plain   ; 74 3C
                MOV     AX, ds:[GfxContext.wGfxBlitDstPage]            ; A1 18 00
                MOV     CX, AX                  ; 8B C8
                OR      AX, ds:[GfxContext.wGfxBlitSrcPage]            ; 0B 06 16 00
                AND     AX, 0B000H              ; 25 00 B0
                CMP     AX, 0B000H              ; 3D 00 B0
                JNZ     SHORT tan_slot4_plain   ; 75 2B
                MOV     AX, ds:[GfxContext.wGfxBlitSrcPage]            ; A1 16 00
                CMP     CX, 0B000H              ; 81 F9 00 B0
                JC      SHORT tan_slot4_a       ; 72 09
                CMP     AX, 0B000H              ; 3D 00 B0
                JNC     tan_slot4_pingpong      ; 73 5E
                MOV     AX, CX                  ; 8B C1
                XOR     CX, CX                  ; 33 C9
tan_slot4_a:
                PUSH    AX                      ; 50
                PUSH    CS                      ; 0E
                CALL    tan_slot28_fwd          ; E8 47 FF
                ADD     SP, 2                   ; 83 C4 02
                OR      CX, CX                  ; 0B C9
                JZ      SHORT tan_slot4_no_cx   ; 74 07
                MOV     CX, AX                  ; 8B C8
                MOV     AX, ds:[GfxContext.wGfxBlitDstPage]            ; A1 18 00
                JMP     SHORT tan_slot4_set_segs ; EB 0D
tan_slot4_no_cx:
                MOV     CX, ds:[GfxContext.wGfxBlitSrcPage]            ; 8B 0E 16 00
                JMP     SHORT tan_slot4_set_segs ; EB 07
tan_slot4_plain:
                MOV     AX, ds:[GfxContext.wGfxBlitDstPage]            ; A1 18 00
                MOV     CX, ds:[GfxContext.wGfxBlitSrcPage]            ; 8B 0E 16 00
tan_slot4_set_segs:
                MOV     ES, AX                  ; 8E C0
                MOV     DS, CX                  ; 8E D9
                MOV     BP, DI                  ; 8B EF
                ADD     BP, cs:[208H]           ; 2E 03 2E 08 02
                MOV     AX, SI                  ; 8B C6
                SHR     BX, 1                   ; D1 EB
                JC      SHORT tan_slot4_odd     ; 72 14
tan_slot4_even_row:
                MOV     CX, BX                  ; 8B CB
                MOV     DI, [BP+0]              ; 8B 7E 00
                ADD     DI, AX                  ; 03 F8
                MOV     SI, DI                  ; 8B F7
                REP     MOVSW                   ; F3 A5
                ADD     BP, 2                   ; 83 C5 02
                DEC     DX                      ; 4A
                JNZ     SHORT tan_slot4_even_row ; 75 EF
                JMP     tan_slot4_exit          ; E9 9C 00
tan_slot4_odd:
tan_slot4_odd_row:
                MOV     CX, BX                  ; 8B CB
                MOV     DI, [BP+0]              ; 8B 7E 00
                ADD     DI, AX                  ; 03 F8
                MOV     SI, DI                  ; 8B F7
                REP     MOVSW                   ; F3 A5
                MOVSB                           ; A4
                ADD     BP, 2                   ; 83 C5 02
                DEC     DX                      ; 4A
                JNZ     SHORT tan_slot4_odd_row ; 75 EE
                JMP     tan_slot4_exit          ; E9 87 00
tan_slot4_pingpong:
                MOV     CX, 0E4E4H              ; B9 E4 E4
                MOV     AL, cs:[0F42H]          ; 2E A0 42 0F
                OR      AL, AL                  ; 0A C0
                JZ      SHORT tan_slot4_p1      ; 74 04
                OR      CX, 0202H               ; 81 C9 02 02
tan_slot4_p1:
                MOV     AX, ds:[GfxContext.wGfxBlitSrcPage]            ; A1 16 00
                CMP     AX, ds:[6E4H]           ; 3B 06 E4 06
                JZ      SHORT tan_slot4_p2      ; 74 03
                OR      CL, 10H                 ; 80 C9 10
tan_slot4_p2:
                MOV     AX, ds:[GfxContext.wGfxBlitDstPage]            ; A1 18 00
                CMP     AX, ds:[6E4H]           ; 3B 06 E4 06
                JZ      SHORT tan_slot4_p3      ; 74 03
                OR      CH, 10H                 ; 80 CD 10
tan_slot4_p3:
                MOV     AX, CX                  ; 8B C1
                AND     CH, 10H                 ; 80 E5 10
                SHR     CH, 1                   ; D0 ED
                SHR     CH, 1                   ; D0 ED
                SHR     CH, 1                   ; D0 ED
                SHR     CH, 1                   ; D0 ED
                MOV     cs:[0F44H], CH          ; 2E 88 2E 44 0F
                SHR     BX, 1                   ; D1 EB
                JNC     SHORT tan_slot4_b1      ; 73 01
                INC     BX                      ; 43
tan_slot4_b1:
                SHR     BX, 1                   ; D1 EB
                JNC     SHORT tan_slot4_b2      ; 73 01
                INC     BX                      ; 43
tan_slot4_b2:
                MOV     [BP-4], BX              ; 89 5E FC
                MOV     [BP-2], DL              ; 88 56 FE
                MOV     [BP-6], SI              ; 89 76 FA
                MOV     [BP-8], DI              ; 89 7E F8
                MOV     DX, 0B800H              ; BA 00 B8
                MOV     ES, DX                  ; 8E C2
                MOV     DX, 03DFH               ; BA DF 03
tan_slot4_outer:
                MOV     BX, [BP-8]              ; 8B 5E F8
                MOV     SI, [BX]                ; 8B 37
                ADD     SI, [BP-6]              ; 03 76 FA
                ADD     BX, 2                   ; 83 C3 02
                MOV     [BP-8], BX              ; 89 5E F8
                MOV     DI, [BP-4]              ; 8B 7E FC
tan_slot4_inner:
                OUT     DX, AL                  ; EE     page reg: map source page to B800
                MOV     BX, ES:[SI]             ; 26 8B 1C
                MOV     CX, ES:[SI+2]           ; 26 8B 4C 02
                XCHG    AL, AH                  ; 86 C4
                OUT     DX, AL                  ; EE     page reg: map dest page to B800
                XCHG    AL, AH                  ; 86 C4
                MOV     ES:[SI], BX             ; 26 89 1C
                MOV     ES:[SI+2], CX           ; 26 89 4C 02
                ADD     SI, 4                   ; 83 C6 04
                DEC     DI                      ; 4F
                JNZ     SHORT tan_slot4_inner   ; 75 E6
                DEC     BYTE PTR [BP-2]         ; FE 4E FE
                JNZ     SHORT tan_slot4_outer   ; 75 D0
tan_slot4_exit:
                POP     ES                      ; 07
                POP     DS                      ; 1F
                POP     DI                      ; 5F
                POP     SI                      ; 5E
                ADD     SP, 8                   ; 83 C4 08
                POP     BP                      ; 5D
                RETF                            ; CB
tan_slot4       ENDP

; ============================================================================
; tan_slot17 -- rect copy from caller-supplied source far-ptr to framebuffer.
; chunk:0x1125..0x11A2
;
; Despite the slot's CGA neighbour being a palette-set, in TAN slot 17 is
; another rect-copy variant -- it copies width/2 word-sized pixel runs
; from a caller-supplied far-ptr source into the framebuffer (DS being
; resolved from B-band aliases via tan_slot28).
;
; ABI (__cdecl16far):
;   [BP+0Eh] x_src      (split into byte/nibble like other rect copies)
;   [BP+10h] src_seg
;   [BP+12h] y_src
;   [BP+14h] y_dst
;   [BP+16h] width
;   [BP+18h] row_count
; ============================================================================
tan_slot17      PROC    FAR
                PUSH    BP                      ; 55
                PUSH    DS                      ; 1E
                PUSH    SI                      ; 56
                PUSH    ES                      ; 06
                PUSH    DI                      ; 57
                MOV     BP, SP                  ; 8B EC
                MOV     DS, cs:[206H]           ; 2E 8E 1E 06 02
                MOV     AX, ds:[GfxContext.wGfxBlitDstPage]            ; A1 18 00
                CMP     WORD PTR ds:[6E2H], 0   ; 83 3E E2 06 00
                JZ      SHORT tan_slot17_no_flip ; 74 08
                PUSH    AX                      ; 50
                PUSH    CS                      ; 0E
                CALL    tan_slot28_fwd          ; E8 47 FE
                ADD     SP, 2                   ; 83 C4 02
tan_slot17_no_flip:
                MOV     ES, AX                  ; 8E C0
                MOV     AX, [BP+16H]            ; 8B 46 16
                SHR     AX, 1                   ; D1 E8
                MOV     [BP+16H], AX            ; 89 46 16
                MOV     AX, [BP+12H]            ; 8B 46 12
                SHR     AX, 1                   ; D1 E8
                MOV     [BP+12H], AX            ; 89 46 12
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
                MOV     DX, [BP+18H]            ; 8B 56 18
tan_slot17_row:
                MOV     AX, [BP+14H]            ; 8B 46 14
                SHL     AX, 1                   ; D1 E0
                MOV     BX, GfxContext.pRow_offset_lut                ; BB F2 06
                ADD     BX, cs:[208H]           ; 2E 03 1E 08 02
                ADD     BX, AX                  ; 03 D8
                MOV     AX, SS:[BX]             ; 36 8B 07
                ADD     AX, [BP+12H]            ; 03 46 12
                MOV     DI, AX                  ; 8B F8
                MOV     CX, [BP+16H]            ; 8B 4E 16
                SHR     CX, 1                   ; D1 E9
                REP     MOVSW                   ; F3 A5
                RCL     CX, 1                   ; D1 D1
                REP     MOVSB                   ; F3 A4
                MOV     AX, [BP+14H]            ; 8B 46 14
                ADD     AX, 1                   ; 05 01 00
                MOV     [BP+14H], AX            ; 89 46 14
                DEC     DX                      ; 4A
                JNZ     SHORT tan_slot17_row    ; 75 D2
                POP     DI                      ; 5F
                POP     ES                      ; 07
                POP     SI                      ; 5E
                POP     DS                      ; 1F
                POP     BP                      ; 5D
                RETF                            ; CB
tan_slot17      ENDP

; ============================================================================
; g_abTanPixelXlatLut -- 256-byte pixel translation LUT.
; chunk:0x11A3..0x12A2
;
; Indexed by a byte that has at most one nibble non-zero in each input
; byte, the LUT maps it to a sparse-keep mask used when merging textured
; pixel runs into the framebuffer. Used by tan_slot37, tan_slot36,
; tan_slot16, tan_slot29's sub-blits etc. via XLAT CS:BX.
;
; Layout: 16 rows of 16 bytes. Row 0 = first non-zero entry is 0xFF then
; 15 x 0xF0 (high-nibble keep masks); rows 1..15 each begin with 0x0F
; then 15 zero bytes (low-nibble keep masks aligned to row*16 index).
; ============================================================================
g_abTanPixelXlatLut LABEL BYTE
                DB      0FFH, 0F0H, 0F0H, 0F0H, 0F0H, 0F0H, 0F0H, 0F0H
                DB      0F0H, 0F0H, 0F0H, 0F0H, 0F0H, 0F0H, 0F0H, 0F0H
                DB       00FH, 0,0,0,0,0,0,0, 0,0,0,0,0,0,0,0
                DB       00FH, 0,0,0,0,0,0,0, 0,0,0,0,0,0,0,0
                DB       00FH, 0,0,0,0,0,0,0, 0,0,0,0,0,0,0,0
                DB       00FH, 0,0,0,0,0,0,0, 0,0,0,0,0,0,0,0
                DB       00FH, 0,0,0,0,0,0,0, 0,0,0,0,0,0,0,0
                DB       00FH, 0,0,0,0,0,0,0, 0,0,0,0,0,0,0,0
                DB       00FH, 0,0,0,0,0,0,0, 0,0,0,0,0,0,0,0
                DB       00FH, 0,0,0,0,0,0,0, 0,0,0,0,0,0,0,0
                DB       00FH, 0,0,0,0,0,0,0, 0,0,0,0,0,0,0,0
                DB       00FH, 0,0,0,0,0,0,0, 0,0,0,0,0,0,0,0
                DB       00FH, 0,0,0,0,0,0,0, 0,0,0,0,0,0,0,0
                DB       00FH, 0,0,0,0,0,0,0, 0,0,0,0,0,0,0,0
                DB       00FH, 0,0,0,0,0,0,0, 0,0,0,0,0,0,0,0
                DB       00FH, 0,0,0,0,0,0,0, 0,0,0,0,0,0,0,0
                DB       00FH, 0,0,0,0,0,0,0, 0,0,0,0,0,0,0,0

; ============================================================================
; tan_slot29 -- sprite blit master (clipped, with flip flags).
; chunk:0x12A3..0x144D
;
; The real sprite-flip dispatcher in TAN. After clipping the sprite
; rect against the host's viewport bounds at scratch:[0x4..0xA], reads
; flip_flags from the local frame and dispatches to one of four
; flip-variant sub-cores via the near-pointer table at chunk:[0x1623]:
;
;   flip=0 -> tan_blit_sub_144e (no flip)
;   flip=1 -> tan_blit_sub_14bb (h-flip)
;   flip=2 -> tan_blit_sub_1528 (v-flip)
;   flip=3 -> tan_blit_sub_15a1 (hv-flip)
;
; The fully-clipped-out path jumps to tan_blit_sub_1618 (RETF stub).
;
; Shared state at chunk:[0x162B..0x1633]:
;   0x162B  ds_src_seg (saved DS for sub-cores)
;   0x162D  src_pre_step (negative correction if y < 0)
;   0x162F  flag: y top-clipped
;   0x1630  flag: x left-clipped
;   0x1631  flip_flags
;   0x1633  row count after y clipping
;
; And at 0x1621: width-words; 0x1623..0x162A: 4-entry dispatch table.
; ============================================================================
tan_slot29      PROC    FAR
                PUSH    BP                      ; 55
                MOV     BP, SP                  ; 8B EC
                SUB     SP, 0AH                 ; 83 EC 0A
                PUSH    SI                      ; 56
                PUSH    DI                      ; 57
                PUSH    ES                      ; 06
                PUSH    DS                      ; 1E
                MOV     SI, [BP+6]              ; 8B 76 06       sprite ptr arg
                MOV     DI, BP                  ; 8B FD
                SUB     DI, 0AH                 ; 83 EF 0A
                MOV     AX, DS                  ; 8C D8
                MOV     ES, AX                  ; 8E C0
                MOV     CX, 5                   ; B9 05 00
                REP     MOVSW                   ; F3 A5          5 words = sprite header
                MOV     DS, cs:[206H]           ; 2E 8E 1E 06 02
                MOV     AX, ds:[GfxContext.wGfxBlitDstPage]            ; A1 18 00
                CMP     WORD PTR ds:[6E2H], 0   ; 83 3E E2 06 00
                JZ      SHORT tan_slot29_no_flip ; 74 08
                PUSH    AX                      ; 50
                PUSH    CS                      ; 0E
                CALL    tan_slot28_fwd          ; E8 B5 FC
                ADD     SP, 2                   ; 83 C4 02
tan_slot29_no_flip:
                MOV     ES, AX                  ; 8E C0
                MOV     AL, [BP+0CH]            ; 8A 46 0C       flip_flags
                MOV     cs:[1631H], AL          ; 2E A2 31 16
                MOV     BX, [BP+0AH]            ; 8B 5E 0A       y arg
                SHL     BX, 1                   ; D1 E3
                JNS     SHORT tan_slot29_y_pos  ; 79 0D
                SAR     BX, 1                   ; D1 FB
                NEG     BX                      ; F7 DB
                MOV     cs:[162DH], BX          ; 2E 89 1E 2D 16
                XOR     DI, DI                  ; 33 FF
                JMP     SHORT tan_slot29_after_y ; EB 0B
tan_slot29_y_pos:
                MOV     WORD PTR cs:[162DH], 0  ; 2E C7 06 2D 16 00 00
                MOV     DI, [BX].pRow_offset_lut           ; 8B BF F2 06    row LUT base
tan_slot29_after_y:
                MOV     AX, [BP+8]              ; 8B 46 08       x arg
                MOV     CH, AL                  ; 8A E8
                SAR     AX, 1                   ; D1 F8
                ADD     DI, AX                  ; 03 F8
                AND     CH, 1                   ; 80 E5 01
                SHL     CH, 1                   ; D0 E5
                SHL     CH, 1                   ; D0 E5
                MOV     AX, [BP-4]              ; 8B 46 FC       width
                MOV     DX, AX                  ; 8B D0
                SHR     AX, 1                   ; D1 E8
                MOV     cs:[1621H], AX          ; 2E A3 21 16
                ADD     DX, 1                   ; 83 C2 01
                SHR     DX, 1                   ; D1 EA
                MOV     DH, DL                  ; 8A F2
                MOV     AL, [BP-2]              ; 8A 46 FE       height
                MOV     cs:[1633H], AL          ; 2E A2 33 16
                MOV     AX, [BP-0AH]            ; 8B 46 F6       sprite seg
                MOV     cs:[162BH], AX          ; 2E A3 2B 16
                MOV     SI, [BP-8]              ; 8B 76 F8       sprite off
                XOR     AX, AX                  ; 33 C0
                MOV     cs:[162FH], AL          ; 2E A2 2F 16
                MOV     cs:[1630H], AL          ; 2E A2 30 16
                TEST    BYTE PTR cs:[1631H], 1  ; 2E F6 06 31 16 01
                JZ      SHORT tan_slot29_no_hflip ; 74 12
                PUSH    DX                      ; 52
                MOV     AL, cs:[1633H]          ; 2E A0 33 16
                XOR     AH, AH                  ; 32 E4
                DEC     AX                      ; 48
                XOR     DX, DX                  ; 33 D2
                MUL     WORD PTR cs:[1621H]     ; 2E F7 26 21 16
                ADD     SI, AX                  ; 03 F0
                POP     DX                      ; 5A
tan_slot29_no_hflip:
                TEST    BYTE PTR cs:[1631H], 2  ; 2E F6 06 31 16 02
                JZ      SHORT tan_slot29_no_vflip ; 74 07
                MOV     AX, cs:[1621H]          ; 2E A1 21 16
                DEC     AX                      ; 48
                ADD     SI, AX                  ; 03 F0
tan_slot29_no_vflip:
                MOV     AL, ds:[GfxContext.bClip_enabled]              ; A0 03 00
                OR      AL, AL                  ; 0A C0
                JNZ     SHORT tan_slot29_clip   ; 75 03
                JMP     tan_slot29_dispatch     ; E9 CC 00
tan_slot29_clip:
                MOV     AX, ds:[GfxContext.nClip_xmax]              ; A1 06 00       clip right
                INC     AX                      ; 40
                MOV     BX, [BP+8]              ; 8B 5E 08
                ADD     BX, [BP-4]              ; 03 5E FC
                SUB     AX, BX                  ; 2B C3
                JG      SHORT tan_slot29_clip_xtail ; 7F 14
                NEG     AX                      ; F7 D8
                CMP     AX, [BP-4]              ; 3B 46 FC
                JL      SHORT tan_slot29_clip_x_partial ; 7C 03
                JMP     tan_slot29_skip         ; E9 93 02
tan_slot29_clip_x_partial:
                SHR     AX, 1                   ; D1 E8
                SUB     DH, AL                  ; 2A F0
                MOV     BYTE PTR cs:[162FH], 1  ; 2E C6 06 2F 16 01
tan_slot29_clip_xtail:
                MOV     AX, [BP+8]              ; 8B 46 08
                SUB     AX, ds:[GfxContext.nClip_xmin]              ; 2B 06 04 00
                JNS     SHORT tan_slot29_clip_ytop ; 79 27
                MOV     BX, AX                  ; 8B D8
                ADD     AX, [BP-4]              ; 03 46 FC
                JG      SHORT tan_slot29_clip_x_in ; 7F 03
                JMP     tan_slot29_skip         ; E9 76 02
tan_slot29_clip_x_in:
                MOV     BYTE PTR cs:[1630H], 1  ; 2E C6 06 30 16 01
                NEG     BX                      ; F7 DB
                ADD     BX, 1                   ; 83 C3 01
                SHR     BX, 1                   ; D1 EB
                SUB     DH, BL                  ; 2A F3
                ADD     DI, BX                  ; 03 FB
                TEST    BYTE PTR cs:[1631H], 2  ; 2E F6 06 31 16 02
                JZ      SHORT tan_slot29_clip_x_nv ; 74 02
                NEG     BX                      ; F7 DB
tan_slot29_clip_x_nv:
                ADD     SI, BX                  ; 03 F3
tan_slot29_clip_ytop:
                MOV     AX, [BP+0AH]            ; 8B 46 0A
                ADD     AX, [BP-2]              ; 03 46 FE
                SUB     AX, ds:[GfxContext.nClip_ymax]            ; 2B 06 0A 00
                JLE     SHORT tan_slot29_clip_ybot ; 7E 0F
                CMP     AX, [BP-2]              ; 3B 46 FE
                JS      SHORT tan_slot29_clip_y_partial ; 78 03
                JMP     tan_slot29_skip         ; E9 45 02
tan_slot29_clip_y_partial:
                DEC     AL                      ; FE C8
                SUB     cs:[1633H], AL          ; 2E 28 06 33 16
tan_slot29_clip_ybot:
                MOV     AX, ds:[GfxContext.nClip_ymin]              ; A1 08 00
                SUB     AX, [BP+0AH]            ; 2B 46 0A
                JS      SHORT tan_slot29_dispatch ; 78 57
                CMP     AX, [BP-2]              ; 3B 46 FE
                JS      SHORT tan_slot29_clip_y_top_partial ; 78 03
                JMP     tan_slot29_skip         ; E9 2E 02
tan_slot29_clip_y_top_partial:
                SUB     cs:[1633H], AL          ; 2E 28 06 33 16
                MOV     BX, AX                  ; 8B D8
                MUL     BYTE PTR cs:[1621H]     ; 2E F6 26 21 16
                TEST    BYTE PTR cs:[1631H], 1  ; 2E F6 06 31 16 01
                JZ      SHORT tan_slot29_no_neg_si ; 74 02
                NEG     AX                      ; F7 D8
tan_slot29_no_neg_si:
                ADD     SI, AX                  ; 03 F0
                MOV     AX, BX                  ; 8B C3
                SUB     AX, cs:[162DH]          ; 2E 2B 06 2D 16
                MOV     BX, AX                  ; 8B D8
                AND     AX, 3                   ; 25 03 00
                JZ      SHORT tan_slot29_bank_done ; 74 11
tan_slot29_bank_loop:
                ADD     DI, 2000H               ; 81 C7 00 20
                JNS     SHORT tan_slot29_bank_no_wrap ; 79 08
                SHL     DI, 1                   ; D1 E7
                SHR     DI, 1                   ; D1 EF
                ADD     DI, 0A0H                ; 81 C7 A0 00
tan_slot29_bank_no_wrap:
                DEC     AX                      ; 48
                JNZ     SHORT tan_slot29_bank_loop ; 75 EF
tan_slot29_bank_done:
                MOV     AX, BX                  ; 8B C3
                SHR     AX, 1                   ; D1 E8
                SHR     AX, 1                   ; D1 E8
                SHL     AX, 1                   ; D1 E0
                SHL     AX, 1                   ; D1 E0
                SHL     AX, 1                   ; D1 E0
                SHL     AX, 1                   ; D1 E0
                SHL     AX, 1                   ; D1 E0
                ADD     DI, AX                  ; 03 F8
                SHL     AX, 1                   ; D1 E0
                SHL     AX, 1                   ; D1 E0
                ADD     DI, AX                  ; 03 F8
tan_slot29_dispatch:
                MOV     BL, cs:[1631H]          ; 2E 8A 1E 31 16
                XOR     BH, BH                  ; 32 FF
                SHL     BX, 1                   ; D1 E3
                MOV     AX, cs:[BX+1623H]       ; 2E 8B 87 23 16
                MOV     DS, cs:[162BH]          ; 2E 8E 1E 2B 16
                JMP     AX                      ; FF E0     -> tan_blit_sub_{144e/14bb/1528/15a1}
tan_slot29      ENDP

; ============================================================================
; tan_blit_sub_144e -- no-flip sprite row engine.
; chunk:0x144E..0x14BA
;
; Entered via `JMP AX` from tan_slot29_dispatch when flip_flags = 0.
; This and the next three subs (tan_blit_sub_14bb / _1528 / _15a1)
; share an almost-identical structure -- the differences are isolated
; to two operations:
;     * the per-source-byte nibble swap (none / none / 4xROL / 4xROL)
;     * the per-row source pointer step (`ADD BP, AX` / `SUB BP, AX`)
; Each sub PUSHes BP/SI/DI on entry to checkpoint the row base, runs
; the inner xclip-aware pump loop, POPs the checkpoint, advances by
; `cs:[1621H]` words and re-PUSHes for the next row. On exit each sub
; cleans its 6 bytes of pushed state then `JMP tan_slot29_skip` to the
; shared epilogue at tan_blit_sub_1618.
;
; Local labels use `@@b144e_*` prefix (the hex disambiguates from the
; otherwise-identical labels in the three sister subs).
; ============================================================================
tan_blit_sub_144e PROC NEAR
                PUSH    BP                      ; 55
                PUSH    SI                      ; 56
                PUSH    DI                      ; 57
                MOV     BX, 011A3H              ; BB A3 11        XLAT LUT
                MOV     CL, CH                  ; 8A CD
tan_blit_sub_144e_row:
                MOV     DL, DH                  ; 8A D6
                XOR     AH, AH                  ; 32 E4
                TEST    BYTE PTR cs:[1630H], 1  ; 2E F6 06 30 16 01
                JZ      SHORT @@b144e_no_xclip  ; 74 07
                MOV     AH, [SI-1]              ; 8A 64 FF
                OR      DL, DL                  ; 0A D2
                JZ      SHORT @@b144e_after_run ; 74 1B
@@b144e_no_xclip:
                LODSB                           ; AC
                ROR     AX, CL                  ; D3 C8
                MOV     CH, AL                  ; 8A E8
                XLAT    BYTE PTR CS:[BX]        ; 2E D7     AL = CS:[BX+AL]
                AND     AL, ES:[DI]             ; 26 22 05
                OR      AL, CH                  ; 0A C5
                STOSB                           ; AA
                SHR     AH, CL                  ; D2 EC
                DEC     DL                      ; FE CA
                JNZ     SHORT @@b144e_no_xclip  ; 75 ED
                TEST    BYTE PTR cs:[162FH], 1  ; 2E F6 06 2F 16 01
                JNZ     SHORT @@b144e_no_tail   ; 75 0E
@@b144e_after_run:
                XOR     AL, AL                  ; 32 C0
                SHR     AX, CL                  ; D3 E8
                MOV     CH, AL                  ; 8A E8
                XLAT    BYTE PTR CS:[BX]        ; 2E D7     AL = CS:[BX+AL]
                AND     AL, ES:[DI]             ; 26 22 05
                OR      AL, CH                  ; 0A C5
                STOSB                           ; AA
@@b144e_no_tail:
                POP     DI                      ; 5F
                ADD     DI, 02000H              ; 81 C7 00 20
                JNS     SHORT @@b144e_no_wrap   ; 79 08
                SHL     DI, 1                   ; D1 E7
                SHR     DI, 1                   ; D1 EF
                ADD     DI, 0A0H                ; 81 C7 A0 00
@@b144e_no_wrap:
                POP     SI                      ; 5E
                POP     BP                      ; 5D
                MOV     AX, cs:[1621H]          ; 2E A1 21 16
                ADD     BP, AX                  ; 03 E8
                ADD     SI, AX                  ; 03 F0
                PUSH    BP                      ; 55
                PUSH    SI                      ; 56
                PUSH    DI                      ; 57
                DEC     BYTE PTR cs:[1633H]     ; 2E FE 0E 33 16
                JNZ     SHORT tan_blit_sub_144e_row ; 75 A1
                ADD     SP, 6                   ; 83 C4 06
                JMP     tan_slot29_skip         ; E9 5D 01
tan_blit_sub_144e ENDP

; ============================================================================
; tan_blit_sub_14bb -- h-flip sprite row engine.
; chunk:0x14BB..0x1527
;
; Mirrors tan_blit_sub_144e but advances BP/SI backward via SUB.
; ============================================================================
tan_blit_sub_14bb PROC NEAR
                PUSH    BP                      ; 55
                PUSH    SI                      ; 56
                PUSH    DI                      ; 57
                MOV     BX, 011A3H              ; BB A3 11
                MOV     CL, CH                  ; 8A CD
tan_blit_sub_14bb_row:
                MOV     DL, DH                  ; 8A D6
                XOR     AH, AH                  ; 32 E4
                TEST    BYTE PTR cs:[1630H], 1  ; 2E F6 06 30 16 01
                JZ      SHORT @@b14bb_no_xclip  ; 74 07
                MOV     AH, [SI-1]              ; 8A 64 FF
                OR      DL, DL                  ; 0A D2
                JZ      SHORT @@b14bb_after_run ; 74 1B
@@b14bb_no_xclip:
                LODSB                           ; AC
                ROR     AX, CL                  ; D3 C8
                MOV     CH, AL                  ; 8A E8
                XLAT    BYTE PTR CS:[BX]        ; 2E D7     AL = CS:[BX+AL]
                AND     AL, ES:[DI]             ; 26 22 05
                OR      AL, CH                  ; 0A C5
                STOSB                           ; AA
                SHR     AH, CL                  ; D2 EC
                DEC     DL                      ; FE CA
                JNZ     SHORT @@b14bb_no_xclip  ; 75 ED
                TEST    BYTE PTR cs:[162FH], 1  ; 2E F6 06 2F 16 01
                JNZ     SHORT @@b14bb_no_tail   ; 75 0E
@@b14bb_after_run:
                XOR     AL, AL                  ; 32 C0
                SHR     AX, CL                  ; D3 E8
                MOV     CH, AL                  ; 8A E8
                XLAT    BYTE PTR CS:[BX]        ; 2E D7     AL = CS:[BX+AL]
                AND     AL, ES:[DI]             ; 26 22 05
                OR      AL, CH                  ; 0A C5
                STOSB                           ; AA
@@b14bb_no_tail:
                POP     DI                      ; 5F
                ADD     DI, 02000H              ; 81 C7 00 20
                JNS     SHORT @@b14bb_no_wrap   ; 79 08
                SHL     DI, 1                   ; D1 E7
                SHR     DI, 1                   ; D1 EF
                ADD     DI, 0A0H                ; 81 C7 A0 00
@@b14bb_no_wrap:
                POP     SI                      ; 5E
                POP     BP                      ; 5D
                MOV     AX, cs:[1621H]          ; 2E A1 21 16
                SUB     BP, AX                  ; 2B E8
                SUB     SI, AX                  ; 2B F0
                PUSH    BP                      ; 55
                PUSH    SI                      ; 56
                PUSH    DI                      ; 57
                DEC     BYTE PTR cs:[1633H]     ; 2E FE 0E 33 16
                JNZ     SHORT tan_blit_sub_14bb_row ; 75 A1
                ADD     SP, 6                   ; 83 C4 06
                JMP     tan_slot29_skip         ; E9 F0 00
tan_blit_sub_14bb ENDP

; ============================================================================
; tan_blit_sub_1528 -- v-flip sprite row engine.
; chunk:0x1528..0x15A0
;
; Each source byte is nybble-swapped via 4xROL, SI moved BACK by 2 each
; iteration (read right-to-left).
; ============================================================================
tan_blit_sub_1528 PROC NEAR
                PUSH    BP                      ; 55
                PUSH    SI                      ; 56
                PUSH    DI                      ; 57
                MOV     BX, 011A3H              ; BB A3 11
                MOV     CL, CH                  ; 8A CD
tan_blit_sub_1528_row:
                MOV     DL, DH                  ; 8A D6
                XOR     AH, AH                  ; 32 E4
                TEST    BYTE PTR cs:[1630H], 1  ; 2E F6 06 30 16 01
                JZ      SHORT @@b1528_no_xclip  ; 74 07
                MOV     AH, [SI-1]              ; 8A 64 FF
                OR      DL, DL                  ; 0A D2
                JZ      SHORT @@b1528_after_run ; 74 26
@@b1528_no_xclip:
                LODSB                           ; AC
                ROL     AL, 1                   ; D0 C0
                ROL     AL, 1                   ; D0 C0
                ROL     AL, 1                   ; D0 C0
                ROL     AL, 1                   ; D0 C0
                SUB     SI, 2                   ; 83 EE 02
                ROR     AX, CL                  ; D3 C8
                MOV     CH, AL                  ; 8A E8
                XLAT    BYTE PTR CS:[BX]        ; 2E D7     AL = CS:[BX+AL]
                AND     AL, ES:[DI]             ; 26 22 05
                OR      AL, CH                  ; 0A C5
                STOSB                           ; AA
                SHR     AH, CL                  ; D2 EC
                DEC     DL                      ; FE CA
                JNZ     SHORT @@b1528_no_xclip  ; 75 E2
                TEST    BYTE PTR cs:[162FH], 1  ; 2E F6 06 2F 16 01
                JNZ     SHORT @@b1528_no_tail   ; 75 0E
@@b1528_after_run:
                XOR     AL, AL                  ; 32 C0
                SHR     AX, CL                  ; D3 E8
                MOV     CH, AL                  ; 8A E8
                XLAT    BYTE PTR CS:[BX]        ; 2E D7     AL = CS:[BX+AL]
                AND     AL, ES:[DI]             ; 26 22 05
                OR      AL, CH                  ; 0A C5
                STOSB                           ; AA
@@b1528_no_tail:
                POP     DI                      ; 5F
                ADD     DI, 02000H              ; 81 C7 00 20
                JNS     SHORT @@b1528_no_wrap   ; 79 08
                SHL     DI, 1                   ; D1 E7
                SHR     DI, 1                   ; D1 EF
                ADD     DI, 0A0H                ; 81 C7 A0 00
@@b1528_no_wrap:
                POP     SI                      ; 5E
                POP     BP                      ; 5D
                MOV     AX, cs:[1621H]          ; 2E A1 21 16
                ADD     BP, AX                  ; 03 E8
                ADD     SI, AX                  ; 03 F0
                PUSH    BP                      ; 55
                PUSH    SI                      ; 56
                PUSH    DI                      ; 57
                DEC     BYTE PTR cs:[1633H]     ; 2E FE 0E 33 16
                JZ      SHORT @@b1528_done      ; 74 02
                JMP     SHORT tan_blit_sub_1528_row ; EB 94
@@b1528_done:
                ADD     SP, 6                   ; 83 C4 06
                JMP     SHORT tan_slot29_skip   ; EB 77
tan_blit_sub_1528 ENDP

; ============================================================================
; tan_blit_sub_15a1 -- hv-flip sprite row engine.
; chunk:0x15A1..0x1617
;
; Combines tan_blit_sub_14bb's backward row stride with tan_blit_sub_1528's
; nibble-swap.
; ============================================================================
tan_blit_sub_15a1 PROC NEAR
                PUSH    BP                      ; 55
                PUSH    SI                      ; 56
                PUSH    DI                      ; 57
                MOV     BX, 011A3H              ; BB A3 11
                MOV     CL, CH                  ; 8A CD
tan_blit_sub_15a1_row:
                MOV     DL, DH                  ; 8A D6
                XOR     AH, AH                  ; 32 E4
                TEST    BYTE PTR cs:[1630H], 1  ; 2E F6 06 30 16 01
                JZ      SHORT @@b15a1_no_xclip  ; 74 07
                MOV     AH, [SI-1]              ; 8A 64 FF
                OR      DL, DL                  ; 0A D2
                JZ      SHORT @@b15a1_after_run ; 74 26
@@b15a1_no_xclip:
                LODSB                           ; AC
                ROL     AL, 1                   ; D0 C0
                ROL     AL, 1                   ; D0 C0
                ROL     AL, 1                   ; D0 C0
                ROL     AL, 1                   ; D0 C0
                SUB     SI, 2                   ; 83 EE 02
                ROR     AX, CL                  ; D3 C8
                MOV     CH, AL                  ; 8A E8
                XLAT    BYTE PTR CS:[BX]        ; 2E D7     AL = CS:[BX+AL]
                AND     AL, ES:[DI]             ; 26 22 05
                OR      AL, CH                  ; 0A C5
                STOSB                           ; AA
                SHR     AH, CL                  ; D2 EC
                DEC     DL                      ; FE CA
                JNZ     SHORT @@b15a1_no_xclip  ; 75 E2
                TEST    BYTE PTR cs:[162FH], 1  ; 2E F6 06 2F 16 01
                JNZ     SHORT @@b15a1_no_tail   ; 75 0E
@@b15a1_after_run:
                XOR     AL, AL                  ; 32 C0
                SHR     AX, CL                  ; D3 E8
                MOV     CH, AL                  ; 8A E8
                XLAT    BYTE PTR CS:[BX]        ; 2E D7     AL = CS:[BX+AL]
                AND     AL, ES:[DI]             ; 26 22 05
                OR      AL, CH                  ; 0A C5
                STOSB                           ; AA
@@b15a1_no_tail:
                POP     DI                      ; 5F
                ADD     DI, 02000H              ; 81 C7 00 20
                JNS     SHORT @@b15a1_no_wrap   ; 79 08
                SHL     DI, 1                   ; D1 E7
                SHR     DI, 1                   ; D1 EF
                ADD     DI, 0A0H                ; 81 C7 A0 00
@@b15a1_no_wrap:
                POP     SI                      ; 5E
                POP     BP                      ; 5D
                MOV     AX, cs:[1621H]          ; 2E A1 21 16
                SUB     BP, AX                  ; 2B E8
                SUB     SI, AX                  ; 2B F0
                PUSH    BP                      ; 55
                PUSH    SI                      ; 56
                PUSH    DI                      ; 57
                DEC     BYTE PTR cs:[1633H]     ; 2E FE 0E 33 16
                JZ      SHORT @@b15a1_done      ; 74 02
                JMP     SHORT tan_blit_sub_15a1_row ; EB 94
@@b15a1_done:
                ADD     SP, 6                   ; 83 C4 06
tan_blit_sub_15a1 ENDP

; ============================================================================
; tan_blit_sub_1618 -- skip / cleanup epilogue for tan_slot29.
; chunk:0x1618..0x1620
;
; Entered when the sprite was fully clipped out, or when any sub-core
; finished its row loop. Restores the 5-PUSH preamble of tan_slot29 and
; the 10-byte local frame, then RETF.
; ============================================================================
tan_blit_sub_1618:
                POP     DS                      ; 1F
                POP     ES                      ; 07
                POP     DI                      ; 5F
                POP     SI                      ; 5E
                ADD     SP, 0AH                 ; 83 C4 0A
                POP     BP                      ; 5D
                RETF                            ; CB

; ============================================================================
; g_wTanSpriteBlitFiller1621 -- filler (becomes g_wTanSpriteWidth at
; runtime; written by tan_slot29 before dispatch).
; chunk:0x1621..0x1622
; ============================================================================
g_wTanSpriteBlitFiller1621 DW 0

; ============================================================================
; g_apfnTanSpriteFlipDispatch -- 4-entry near-pointer table for the
; flip-variant sub-cores. Indexed by (flip_flags & 3).
; chunk:0x1623..0x162A
; ============================================================================
g_apfnTanSpriteFlipDispatch LABEL WORD
                DW      offset tan_blit_sub_144e        ; flip=0 -> 0x144E
                DW      offset tan_blit_sub_14bb        ; flip=1 -> 0x14BB
                DW      offset tan_blit_sub_1528        ; flip=2 -> 0x1528
                DW      offset tan_blit_sub_15a1        ; flip=3 -> 0x15A1

; ============================================================================
; g_abTanSpriteBlitState -- 9 bytes runtime scratch for tan_slot29.
; chunk:0x162B..0x1633
;
; 0x162B  word  ds_src_seg (saved DS for sub-cores)
; 0x162D  word  src_pre_step (negative correction if y < 0)
; 0x162F  byte  flag: top-clipped
; 0x1630  byte  flag: left-clipped
; 0x1631  byte  flip_flags
; 0x1632  byte  pad
; 0x1633  byte  remaining row count
; ============================================================================
g_abTanSpriteBlitState LABEL BYTE
                DB      9 DUP (0)

; ============================================================================
; tan_slot30 -- rect copy with 6x-unrolled bank-step row loop.
; chunk:0x1634..0x16FD
;
; ABI (__cdecl16far):
;   [BP+0]   far ptr to source
;   [BP+2]   source offset (inside source DS)
;   [BP+6]   width (bytes)
;   [BP+8]   row count
;   [BP+0Ah] starting y (row LUT index)
; ============================================================================
tan_slot30      PROC    FAR
                PUSH    BP                      ; 55
                MOV     BP, SP                  ; 8B EC
                PUSH    SI                      ; 56
                PUSH    DI                      ; 57
                PUSH    DS                      ; 1E
                MOV     DS, cs:[206H]           ; 2E 8E 1E 06 02
                MOV     DI, [BP+0AH]            ; 8B 7E 0A
                SHL     DI, 1                   ; D1 E7
                MOV     DI, ds:[DI].pRow_offset_lut        ; 8B BD F2 06
                MOV     AX, [BP+8]              ; 8B 46 08
                SHR     AX, 1                   ; D1 E8
                ADD     DI, AX                  ; 03 F8
                MOV     BP, [BP+6]              ; 8B 6E 06
                MOV     AX, ds:[GfxContext.wGfxBlitDstPage]            ; A1 18 00
                CMP     WORD PTR ds:[6E2H], 0   ; 83 3E E2 06 00
                JZ      SHORT @@b1634_no_flip   ; 74 08
                PUSH    AX                      ; 50
                PUSH    CS                      ; 0E
                CALL    tan_slot28_fwd          ; E8 26 F9
                ADD     SP, 2                   ; 83 C4 02
@@b1634_no_flip:
                MOV     ES, AX                  ; 8E C0
                MOV     DX, [BP+8]              ; 8B 56 08
                MOV     BX, [BP+6]              ; 8B 5E 06
                SHR     BX, 1                   ; D1 EB
                MOV     SI, [BP+2]              ; 8B 76 02
                MOV     DS, [BP+0]              ; 8E 5E 00
                MOV     BP, BX                  ; 8B EB
                SHR     BX, 1                   ; D1 EB
                MOV     AX, 2000H               ; B8 00 20
@@b1634_loop:
                MOV     CX, BX                  ; 8B CB
                REP     MOVSW                   ; F3 A5
                SUB     DI, BP                  ; 2B FD
                ADD     DI, AX                  ; 03 F8
                JNS     SHORT @@b1634_s1        ; 79 08
                SHL     DI, 1                   ; D1 E7
                SHR     DI, 1                   ; D1 EF
                ADD     DI, 0A0H                ; 81 C7 A0 00
@@b1634_s1:
                DEC     DX                      ; 4A
                JZ      @@b1634_done            ; 74 69
                MOV     CX, BX                  ; 8B CB
                REP     MOVSW                   ; F3 A5
                SUB     DI, BP                  ; 2B FD
                ADD     DI, AX                  ; 03 F8
                JNS     SHORT @@b1634_s2        ; 79 08
                SHL     DI, 1                   ; D1 E7
                SHR     DI, 1                   ; D1 EF
                ADD     DI, 0A0H                ; 81 C7 A0 00
@@b1634_s2:
                DEC     DX                      ; 4A
                JZ      @@b1634_done            ; 74 54
                MOV     CX, BX                  ; 8B CB
                REP     MOVSW                   ; F3 A5
                SUB     DI, BP                  ; 2B FD
                ADD     DI, AX                  ; 03 F8
                JNS     SHORT @@b1634_s3        ; 79 08
                SHL     DI, 1                   ; D1 E7
                SHR     DI, 1                   ; D1 EF
                ADD     DI, 0A0H                ; 81 C7 A0 00
@@b1634_s3:
                DEC     DX                      ; 4A
                JZ      @@b1634_done            ; 74 3F
                MOV     CX, BX                  ; 8B CB
                REP     MOVSW                   ; F3 A5
                SUB     DI, BP                  ; 2B FD
                ADD     DI, AX                  ; 03 F8
                JNS     SHORT @@b1634_s4        ; 79 08
                SHL     DI, 1                   ; D1 E7
                SHR     DI, 1                   ; D1 EF
                ADD     DI, 0A0H                ; 81 C7 A0 00
@@b1634_s4:
                DEC     DX                      ; 4A
                JZ      @@b1634_done            ; 74 2A
                MOV     CX, BX                  ; 8B CB
                REP     MOVSW                   ; F3 A5
                SUB     DI, BP                  ; 2B FD
                ADD     DI, AX                  ; 03 F8
                JNS     SHORT @@b1634_s5        ; 79 08
                SHL     DI, 1                   ; D1 E7
                SHR     DI, 1                   ; D1 EF
                ADD     DI, 0A0H                ; 81 C7 A0 00
@@b1634_s5:
                DEC     DX                      ; 4A
                JZ      @@b1634_done            ; 74 15
                MOV     CX, BX                  ; 8B CB
                REP     MOVSW                   ; F3 A5
                SUB     DI, BP                  ; 2B FD
                ADD     DI, AX                  ; 03 F8
                JNS     SHORT @@b1634_s6        ; 79 08
                SHL     DI, 1                   ; D1 E7
                SHR     DI, 1                   ; D1 EF
                ADD     DI, 0A0H                ; 81 C7 A0 00
@@b1634_s6:
                DEC     DX                      ; 4A
                JNZ     @@b1634_loop            ; 75 82
@@b1634_done:
                POP     DS                      ; 1F
                POP     DI                      ; 5F
                POP     SI                      ; 5E
                POP     BP                      ; 5D
                RETF                            ; CB
tan_slot30      ENDP

; ============================================================================
; tan_slot31 -- return first arg (paragraph passthrough).
; chunk:0x16FE..0x1705
;
; Trivial pass-through: AX = [BP+6]. Likely the "report-something" hook
; that on TAN reports the host-supplied value verbatim (slot semantics
; vary per driver; on TAN it appears to be an identity function used by
; the engine to report e.g. the chunk's own scratch paragraph count
; without the chunk doing any computation).
;
; ABI: __cdecl16far(ushort arg) -> ushort (returned in AX).
; ============================================================================
tan_slot31      PROC    FAR
                PUSH    BP                      ; 55
                MOV     BP, SP                  ; 8B EC
                MOV     AX, [BP+6]              ; 8B 46 06
                POP     BP                      ; 5D
                RETF                            ; CB
tan_slot31      ENDP

; ============================================================================
; tan_slot32 -- free a DOS allocation block.
; chunk:0x1706..0x1714
;
; Frees a previously-DOS-allocated paragraph block back to DOS.
;
; Reads the far-pointer-to-far-pointer at [BP+6]: i.e. [BP+6] is a
; near pointer (in caller's DS) to a 2-word slot whose [0]/[1] hold
; the (seg, off) of the block to free. Loads the segment half into
; ES and issues `INT 21h AH=49h` (DOS FreeMemory). The function does
; not propagate the carry-flag error indication back to the caller.
;
; ABI: __cdecl16far(ushort *near_handle_slot) -> void.
;
; See RBIL INT 21h AH=49h (Free Memory). Allocations made via
; `INT 21h AH=48h` (used by tan_init and tan_slot19) are released
; this way.
; ============================================================================
tan_slot32      PROC    FAR
                PUSH    BP                      ; 55
                MOV     BP, SP                  ; 8B EC
                MOV     BP, [BP+6]              ; 8B 6E 06
                MOV     ES, [BP+0]              ; 8E 46 00
                MOV     AH, 49H                 ; B4 49
                INT     21H                     ; CD 21
                POP     BP                      ; 5D
                RETF                            ; CB
tan_slot32      ENDP

; ============================================================================
; tan_slot33 -- alternate sprite blit master (8-bpp variant with bit-shift
;               masks). chunk:0x1715..0x18FA
;
; Structurally similar to tan_slot29 but instead of dispatching to four
; flip-variant cores, has a single inline pump loop that handles all
; flip cases via a bit-mask BH carrying the per-iteration "live" mask.
; ============================================================================
tan_slot33      PROC    FAR
                PUSH    BP                      ; 55
                MOV     BP, SP                  ; 8B EC
                SUB     SP, 0AH                 ; 83 EC 0A
                PUSH    SI                      ; 56
                PUSH    DI                      ; 57
                PUSH    ES                      ; 06
                PUSH    DS                      ; 1E
                MOV     SI, [BP+6]              ; 8B 76 06
                MOV     DI, BP                  ; 8B FD
                SUB     DI, 0AH                 ; 83 EF 0A
                MOV     AX, DS                  ; 8C D8
                MOV     ES, AX                  ; 8E C0
                MOV     CX, 5                   ; B9 05 00
                REP     MOVSW                   ; F3 A5
                MOV     DS, cs:[206H]           ; 2E 8E 1E 06 02
                MOV     AX, ds:[GfxContext.wGfxBlitDstPage]            ; A1 18 00
                CMP     WORD PTR ds:[6E2H], 0   ; 83 3E E2 06 00
                JZ      SHORT @@s33_no_flip     ; 74 08
                PUSH    AX                      ; 50
                PUSH    CS                      ; 0E
                CALL    tan_slot28_fwd          ; E8 43 F8
                ADD     SP, 2                   ; 83 C4 02
@@s33_no_flip:
                MOV     ES, AX                  ; 8E C0
                MOV     AL, [BP+0CH]            ; 8A 46 0C
                MOV     BX, [BP+0AH]            ; 8B 5E 0A
                SHL     BX, 1                   ; D1 E3
                JNS     SHORT @@s33_y_pos       ; 79 0D
                SAR     BX, 1                   ; D1 FB
                NEG     BX                      ; F7 DB
                MOV     cs:[1901H], BX          ; 2E 89 1E 01 19
                XOR     DI, DI                  ; 33 FF
                JMP     SHORT @@s33_after_y     ; EB 0B
@@s33_y_pos:
                MOV     WORD PTR cs:[1901H], 0  ; 2E C7 06 01 19 00 00
                MOV     DI, [BX].pRow_offset_lut           ; 8B BF F2 06
@@s33_after_y:
                MOV     AX, [BP+8]              ; 8B 46 08
                MOV     CH, AL                  ; 8A E8
                SAR     AX, 1                   ; D1 F8
                ADD     DI, AX                  ; 03 F8
                AND     CH, 1                   ; 80 E5 01
                SHL     CH, 1                   ; D0 E5
                SHL     CH, 1                   ; D0 E5
                MOV     AX, [BP-4]              ; 8B 46 FC
                MOV     DX, AX                  ; 8B D0
                SHR     AX, 1                   ; D1 E8
                MOV     cs:[18FBH], AX          ; 2E A3 FB 18
                INC     DX                      ; 42
                SHR     DX, 1                   ; D1 EA
                MOV     DH, DL                  ; 8A F2
                MOV     AL, [BP-2]              ; 8A 46 FE
                MOV     cs:[1906H], AL          ; 2E A2 06 19
                MOV     AX, [BP-0AH]            ; 8B 46 F6
                MOV     cs:[18FDH], AX          ; 2E A3 FD 18
                MOV     SI, [BP-8]              ; 8B 76 F8
                MOV     AX, [BP-6]              ; 8B 46 FA
                MOV     cs:[18FFH], AX          ; 2E A3 FF 18
                XOR     AX, AX                  ; 33 C0
                MOV     cs:[1903H], AL          ; 2E A2 03 19
                MOV     cs:[1904H], AL          ; 2E A2 04 19
                MOV     AL, ds:[GfxContext.bClip_enabled]              ; A0 03 00
                OR      AL, AL                  ; 0A C0
                JNZ     SHORT @@s33_clip        ; 75 03
                JMP     @@s33_dispatch          ; E9 BC 00
@@s33_clip:
                MOV     AX, ds:[GfxContext.nClip_xmax]              ; A1 06 00
                INC     AX                      ; 40
                MOV     BX, [BP+8]              ; 8B 5E 08
                ADD     BX, [BP-4]              ; 03 5E FC
                SUB     AX, BX                  ; 2B C3
                JG      SHORT @@s33_clip_xtail  ; 7F 14
                NEG     AX                      ; F7 D8
                CMP     AX, [BP-4]              ; 3B 46 FC
                JL      SHORT @@s33_clip_x_partial ; 7C 03
                JMP     @@s33_skip              ; E9 23 01
@@s33_clip_x_partial:
                SHR     AX, 1                   ; D1 E8
                SUB     DH, AL                  ; 2A F0
                MOV     BYTE PTR cs:[1903H], 1  ; 2E C6 06 03 19 01
@@s33_clip_xtail:
                MOV     AX, [BP+8]              ; 8B 46 08
                SUB     AX, ds:[GfxContext.nClip_xmin]              ; 2B 06 04 00
                JNS     SHORT @@s33_clip_ytop   ; 79 20
                MOV     BX, AX                  ; 8B D8
                ADD     AX, [BP-4]              ; 03 46 FC
                JG      SHORT @@s33_clip_x_in   ; 7F 03
                JMP     @@s33_skip              ; E9 06 01
@@s33_clip_x_in:
                MOV     BYTE PTR cs:[1904H], 1  ; 2E C6 06 04 19 01
                NEG     BX                      ; F7 DB
                INC     BX                      ; 43
                SHR     BX, 1                   ; D1 EB
                SUB     DH, BL                  ; 2A F3
                ADD     DI, BX                  ; 03 FB
                ADD     SI, BX                  ; 03 F3
                ADD     cs:[18FFH], BX          ; 2E 01 1E FF 18
@@s33_clip_ytop:
                MOV     AX, [BP+0AH]            ; 8B 46 0A
                ADD     AX, [BP-2]              ; 03 46 FE
                SUB     AX, ds:[GfxContext.nClip_ymax]            ; 2B 06 0A 00
                JS      SHORT @@s33_clip_ybot   ; 78 0F
                CMP     AX, [BP-2]              ; 3B 46 FE
                JS      SHORT @@s33_clip_ytop_in ; 78 03
                JMP     @@s33_skip              ; E9 DC 00
@@s33_clip_ytop_in:
                DEC     AL                      ; FE C8
                SUB     cs:[1906H], AL          ; 2E 28 06 06 19
@@s33_clip_ybot:
                MOV     AX, ds:[GfxContext.nClip_ymin]              ; A1 08 00
                SUB     AX, [BP+0AH]            ; 2B 46 0A
                JS      SHORT @@s33_clip_ybot_skip ; 78 4E
                CMP     AX, [BP-2]              ; 3B 46 FE
                JS      SHORT @@s33_clip_ybot_in ; 78 03
                JMP     @@s33_skip              ; E9 C5 00
@@s33_clip_ybot_in:
                SUB     cs:[1906H], AL          ; 2E 28 06 06 19
                MOV     BX, AX                  ; 8B D8
                SUB     AX, cs:[1901H]          ; 2E 2B 06 01 19
                SHR     AX, 1                   ; D1 E8
                JNC     SHORT @@s33_no_bank1    ; 73 04
                ADD     DI, 2000H               ; 81 C7 00 20
@@s33_no_bank1:
                SHR     AX, 1                   ; D1 E8
                JNC     SHORT @@s33_no_bank2    ; 73 04
                ADD     DI, 4000H               ; 81 C7 00 40
@@s33_no_bank2:
                OR      DI, DI                  ; 0B FF
                JNS     SHORT @@s33_no_wrap     ; 79 05
                AND     DI, 7FFFH               ; 81 E7 FF 7F
                INC     AX                      ; 40
@@s33_no_wrap:
                INC     AX                      ; 40
                SHL     AX, 1                   ; D1 E0
                SHL     AX, 1                   ; D1 E0
                SHL     AX, 1                   ; D1 E0
                SHL     AX, 1                   ; D1 E0
                SHL     AX, 1                   ; D1 E0
                ADD     DI, AX                  ; 03 F8
                SHL     AX, 1                   ; D1 E0
                SHL     AX, 1                   ; D1 E0
                ADD     DI, AX                  ; 03 F8
                MOV     AX, BX                  ; 8B C3
                MUL     BYTE PTR cs:[18FBH]     ; 2E F6 26 FB 18
                ADD     SI, AX                  ; 03 F0
                ADD     cs:[18FFH], AX          ; 2E 01 06 FF 18
@@s33_clip_ybot_skip:
@@s33_dispatch:
                MOV     DS, cs:[18FDH]          ; 2E 8E 1E FD 18
                MOV     BP, cs:[18FFH]          ; 2E 8B 2E FF 18
                PUSH    BP                      ; 55
                PUSH    SI                      ; 56
                PUSH    DI                      ; 57
@@s33_outer:
                MOV     DL, DH                  ; 8A D6
                XOR     AH, AH                  ; 32 E4
                MOV     BH, 0FFH                ; B7 FF
                TEST    BYTE PTR cs:[1904H], 1  ; 2E F6 06 04 19 01
                JZ      SHORT @@s33_no_xclip    ; 74 09
                XOR     BH, BH                  ; 32 FF
                MOV     AH, [SI-1]              ; 8A 64 FF
                OR      DL, DL                  ; 0A D2
                JZ      SHORT @@s33_after_run   ; 74 25
@@s33_no_xclip:
                MOV     CL, CH                  ; 8A CD
                XOR     BL, BL                  ; 32 DB
                INC     BP                      ; 45
                ROR     BX, CL                  ; D3 CB
                AND     BL, ES:[DI]             ; 26 22 1D
                LODSB                           ; AC
                ROR     AX, CL                  ; D3 C8
                OR      AL, BL                  ; 0A C3
                STOSB                           ; AA
                SUB     CL, 8                   ; 80 E9 08
                NEG     CL                      ; F6 D9
                SHR     AH, CL                  ; D2 EC
                SHR     BH, CL                  ; D2 EF
                DEC     DL                      ; FE CA
                JNZ     SHORT @@s33_no_xclip    ; 75 E3
                TEST    BYTE PTR cs:[1903H], 1  ; 2E F6 06 03 19 01
                JNZ     SHORT @@s33_no_tail     ; 75 10
@@s33_after_run:
                MOV     CL, CH                  ; 8A CD
                MOV     BL, 0FFH                ; B3 FF
                XOR     AL, AL                  ; 32 C0
                SHR     BX, CL                  ; D3 EB
                AND     BL, ES:[DI]             ; 26 22 1D
                SHR     AX, CL                  ; D3 E8
                OR      AL, BL                  ; 0A C3
                STOSB                           ; AA
@@s33_no_tail:
                POP     DI                      ; 5F
                ADD     DI, 2000H               ; 81 C7 00 20
                JNS     SHORT @@s33_no_wrap2    ; 79 08
                SHL     DI, 1                   ; D1 E7
                SHR     DI, 1                   ; D1 EF
                ADD     DI, 0A0H                ; 81 C7 A0 00
@@s33_no_wrap2:
                POP     SI                      ; 5E
                POP     BP                      ; 5D
                MOV     AX, cs:[18FBH]          ; 2E A1 FB 18
                ADD     BP, AX                  ; 03 E8
                ADD     SI, AX                  ; 03 F0
                PUSH    BP                      ; 55
                PUSH    SI                      ; 56
                PUSH    DI                      ; 57
                DEC     BYTE PTR cs:[1906H]     ; 2E FE 0E 06 19
                JNZ     @@s33_outer             ; 75 91
                ADD     SP, 6                   ; 83 C4 06
@@s33_skip:
                POP     DS                      ; 1F
                POP     ES                      ; 07
                POP     DI                      ; 5F
                POP     SI                      ; 5E
                ADD     SP, 0AH                 ; 83 C4 0A
                POP     BP                      ; 5D
                RETF                            ; CB
tan_slot33      ENDP

; ============================================================================
; g_abTanPaletteScratch -- 12 bytes runtime scratch for tan_slot33.
; chunk:0x18FB..0x1906
;
; 0x18FB  word  width_words
; 0x18FD  word  src_seg
; 0x18FF  word  src_off
; 0x1901  word  y_prestep
; 0x1903  byte  top_clipped flag
; 0x1904  byte  left_clipped flag
; 0x1905  byte  pad
; 0x1906  byte  remaining row count
; ============================================================================
g_abTanPaletteScratch LABEL BYTE
                DB      12 DUP (0)

; ============================================================================
; tan_slot24 -- 1-byte RETF stub.
; chunk:0x1907
;
; Empty slot: a single RETF. This is a separate label from
; tan_unimplemented_slot (0x02F6) only because tan_slot25's body starts
; immediately after at 0x1908 -- the RETF byte at 0x1907 serves as
; vtable slot 24's no-op handler AND is the byte that tan_slot25 falls
; through to / is adjacent to in source order.
;
; ABI: __cdecl16far -> void.
; ============================================================================
tan_slot24      PROC    FAR
                RETF                            ; CB
tan_slot24      ENDP

; ============================================================================
; tan_slot25 -- BIOS set-border-colour (overscan).
; chunk:0x1908..0x1917
;
; Sets the border / overscan colour via BIOS. The arg's low byte is
; the colour index (0..15); the high byte is dropped. The code reads
; BX = arg, copies the low byte BL into BH (the high byte of arg is
; thrown away), then issues INT 10h AX=1001h which expects BH = colour
; value. (On EGA/VGA hardware INT 10h AX=1001h is "Set Border Colour
; Register"; the Tandy BIOS implements the same entry against the
; gate-array overscan latch.)
;
; ABI: __cdecl16far(ushort colour) -> void.
;   [BP+6] = colour; only low byte matters
;
; See RBIL INT 10h AX=1001h (Set Overscan / Border Colour).
; ============================================================================
tan_slot25      PROC    FAR
                PUSH    BP                      ; 55
                MOV     BP, SP                  ; 8B EC
                MOV     BX, [BP+6]              ; 8B 5E 06
                MOV     BH, BL                  ; 8A FB
                MOV     AH, 10H                 ; B4 10
                MOV     AL, 1                   ; B0 01
                INT     10H                     ; CD 10
                POP     BP                      ; 5D
                RETF                            ; CB
tan_slot25      ENDP

; ============================================================================
; tan_slot26 -- retrace-aligned single-palette-entry write.
; chunk:0x1918..0x1964
;
; Programs ONE palette register, with the write scheduled to land
; during a display-retrace interval so the on-screen change is
; glitch-free.
;
; The function looks unusual at first glance: it does the Tandy
; gate-array palette pair (OUT 0x3DA, idx / OUT 0x3DE, colour) AND
; a write to port 0x3C0 value 0x20 that's specific to EGA/VGA hardware
; (the Attribute Controller "video enable" sentinel that re-enables
; the AC after a palette load). On a Tandy 1000 no hardware lives at
; 0x3C0, so that write is harmless; this routine appears to have
; been authored to be safely shared between the Tandy and an EGA
; driver, with the EGA-only sentinel retained.
;
; Algorithm:
;   1. SI := caller arg [BP+8] (colour value) AND 0x0F.
;   2. DI := caller arg [BP+6] (register index) + 0x10 (the gate-array
;      palette-register base, internal indices 0x10..0x1F).
;   3. Read the active CRTC base address from BIOS data area 40:63
;      and add 6 -> status port address (0x3DA on CGA/Tandy/EGA-color,
;      0x3BA on MDA/Herc/EGA-mono). Stash in BP.
;   4. CLI to keep the timing window predictable; poll the status
;      port bit 0 ("display enable") in a two-edge sequence: wait
;      until bit 0 clears (some kind of blanking has started -- bit
;      0 is low during BOTH H- and V-blank), then wait until bit 0
;      sets again. The combined effect is "return at the next
;      retrace edge, either H or V". Either edge is acceptable
;      because Tandy's manual permits palette writes during
;      either kind of blank (Service Manual Page 55). Note that
;      the gate-array status bit 0 cannot distinguish H- from
;      V-blank -- it's low during both.
;      The first IN AL, DX (at label
;      tan_slot26_wait_blank) is a one-shot initial read of the
;      status port. On EGA/VGA it resets the Attribute Controller's
;      internal address/data flip-flop ahead of the 0x3C0 write
;      in step 6 (this routine was written to be safely shared
;      with EGA); on Tandy gate-array hardware there is no flip-
;      flop on the split-port 0x3DA/0x3DE pair, so the read is
;      harmless (just a status snapshot that the body discards).
;   5. At the retrace edge: write `OUT 0x3DA, 0x10+idx` then
;      `OUT 0x3DE, colour` -- the Tandy split-port gate-array
;      palette pair (Tandy 1000 Service Manual Page 53).
;   6. Read once from the status port (BP = stashed status-port DX)
;      to reset the EGA Attribute Controller's address/data flip-
;      flop, then write 0x20 to 0x3C0. On EGA/VGA this is the AC
;      "re-enable video output after a palette write" sentinel; on
;      Tandy nothing is wired up at 0x3C0 and the write is a no-op.
;      The construction is `DL := BL = 0xC0` (DH still holds 0x03
;      from the status-port DX in step 3) which yields 0x3C0;
;      `AL := BH = 0x20` is the AC value.
;   7. STI.
;
; ABI: __cdecl16far(ushort palette_register_index, ushort colour) -> void.
;
; Sources:
;   - BIOS data area 40:63 word = "active video I/O port" -- see RBIL
;     "BIOS Data Area" reference, offset 63h.
;   - Tandy gate-array palette procedure: Tandy 1000 Service Manual
;     Page 53 (verbatim: "To load the palette, write the hex address
;     to the video array address register at 3DA ... then the new
;     palette color is written to 3DE."). PCjr Tech Ref Page 2-71
;     for the index-range definition (palette regs at 0x10..0x1F).
;   - Palette timing rule: Tandy 1000 Service Manual Page 55 ("the
;     palette should be accessed during vertical or horizontal
;     blanking").
;   - EGA Attribute Controller 0x3C0 sentinel: FreeVGA "Attribute
;     Controller Registers" -- writing 0x20 to the AC index port
;     re-enables video output after palette programming.
; ============================================================================
tan_slot26      PROC    FAR
                PUSH    BP                      ; 55
                MOV     BP, SP                  ; 8B EC
                PUSH    SI                      ; 56
                PUSH    DI                      ; 57
                PUSH    ES                      ; 06
                MOV     SI, [BP+8]              ; 8B 76 08
                AND     SI, 0FH                 ; 83 E6 0F
                MOV     DI, [BP+6]              ; 8B 7E 06
                ADD     DI, 10H                 ; 83 C7 10
                MOV     AX, 40H                 ; B8 40 00
                MOV     ES, AX                  ; 8E C0
                MOV     DX, ES:[63H]            ; 26 8B 16 63 00
                ADD     DL, 6                   ; 80 C2 06
                MOV     BP, DX                  ; 8B EA
                MOV     BL, 0C0H                ; B3 C0
                MOV     BH, 20H                 ; B7 20
                MOV     CL, 1                   ; B1 01
                CLI                             ; FA
tan_slot26_wait_blank:
                IN      AL, DX                  ; EC
tan_slot26_wait_active:
                IN      AL, DX                  ; EC
                TEST    AL, CL                  ; 84 C1
                JNZ     SHORT tan_slot26_wait_active ; 75 FB
tan_slot26_wait_retrace:
                IN      AL, DX                  ; EC
                TEST    AL, CL                  ; 84 C1
                JZ      SHORT tan_slot26_wait_retrace ; 74 FB
                MOV     AX, DI                  ; 8B C7
                MOV     DX, 03DAH               ; BA DA 03
                OUT     DX, AL                  ; EE
                MOV     AX, SI                  ; 8B C6
                MOV     DX, 03DEH               ; BA DE 03
                OUT     DX, AL                  ; EE
                MOV     DX, BP                  ; 8B D5
                IN      AL, DX                  ; EC
                MOV     DL, BL                  ; 8A D3
                MOV     AL, BH                  ; 8A C7
                OUT     DX, AL                  ; EE
                STI                             ; FB
                POP     ES                      ; 07
                POP     DI                      ; 5F
                POP     SI                      ; 5E
                POP     BP                      ; 5D
                RETF                            ; CB
tan_slot26      ENDP

                END     _start
