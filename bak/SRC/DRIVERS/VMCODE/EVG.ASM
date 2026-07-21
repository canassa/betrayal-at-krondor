; ============================================================================
; Vmcode.OVL.EVG -- Video Seven V7VGA / Headland SVGA video driver chunk
; (7975 bytes, 0x1F27).
;
; Shipped with "Betrayal at Krondor" (Dynamix / Sierra, 1993).
;
; EVG = Sierra/Dynamix's three-letter driver tag, sibling of CGA/EGA/VGA/MCG/
; TAN/HGC.  Most likely an abbreviation along the lines of "Enhanced Video
; Graphics" or "Extended VGA"; no Sierra-internal string survives in the
; chunk to settle it.  The CHIP it targets,
; on the other hand, is conclusively a Video Seven V7VGA-class part
; (V7VGA / HT-208 / HT-209 / HT-216 -- all members of the Video-Seven
; family respond identically to the BIOS API used here).  Evidence:
;   - INT 10h AX=6F00h is the canonical Video Seven installation-check
;     (returns BX = 0x5637 = 'V7' ASCII).  See RBIL 106F00h and
;     Ferraro Ch. 22 §22.7.1.  Tseng ET4000 uses AX=1A00h + CRTC 0x33
;     read, not this probe.
;   - INT 10h AX=6F05h BL=0x66 -- the V7 "Set Super Mode State" call
;     with BL = mode 0x66.  Per Ferraro Table 22.7, vgadoc VIDEO7.TXT
;     line 411, and Mendelson videomodes.txt this mode is 640x400 at
;     256 colours (P8 packed, V7VGA-with-VRAM mode).
;   - Sequencer index 0xF6 ("1 MB RAM Bank Select") and Sequencer
;     index 0xFF ("16-bit Interface Control") -- both Video Seven
;     extensions of the standard VGA sequencer (Ferraro §22.5.2,
;     §22.5).  The Tseng-equivalent register is port 0x3CD, which
;     this chunk NEVER touches.  This chunk also has
;     none of the Tseng KEY-unlock idiom (`OUT 0x3BF,0x03;
;     OUT 0x3D8,0xA0`).
;   - Standard VGA register groups (Sequencer 0x3C4/0x3C5, Graphics
;     Controller 0x3CE/0x3CF, CRTC 0x3D4/0x3D5, Input Status 1 0x3DA)
;     are used for planar bit-plane work after the BIOS mode-set.
;
; *** Critical mode detail (the bit that's easy to get wrong) ***
;
; V7 mode 0x66 is *natively* 640x400x256 packed (one byte per pixel,
; stride 640).  Immediately after the BIOS mode-set the chunk
; reconfigures the chip into the well-known "Mode X" / unchained-256
; layout: clear the Sequencer Memory-Mode chain-4 bit (3C4:04 bit 3)
; and the Graphics-Controller chain-odd/even bit (3CE:06 bit 1).
; The result is the same 640x400x256 mode, but with the 256 KB of
; video memory mapped as 4 planes of 64,000 bytes each (160 byte
; stride x 400 rows), and the host CPU selects which plane it
; writes via the Sequencer Map-Mask (3C4:02).  Every primitive in
; this chunk works against that layout:
;
;   - byte_offset_within_plane = y * 160 + (x / 4)
;   - plane                    = x & 3                (selects map mask)
;   - pixel_colour             = full 8-bit byte (0..255), NOT 4-bit
;
; The stride constant 0xA0 (= 160) you see everywhere is 640 / 4 -- four
; pixels of one row share one byte position across the four planes.
; The `AND CL,3 / SHL AH,CL` idiom (e.g. in evg_putpixel, evg_draw_line,
; evg_pixel_run_fill_a) is "select the plane that owns pixel x", not a
; 16-colour bit-packing trick.  This is Michael Abrash's Mode X
; extended to V7's 640x400x256 mode -- the same trick, with a wider
; framebuffer.
;
; *** Banking ***
;
; The framebuffer is 4 planes x 64,000 bytes = 256,000 bytes per page.
; A single plane fits in the 64 KB CPU window at A000:0000 with room
; to spare (64,000 < 65,536), so banking is *not* required for a
; single page -- each plane's bytes for the whole 640x400 frame live
; in one 64 KB bank.  Banking *is* required when the driver wants
; more than one page of video memory (front + back buffers, off-
; screen image caches, sprite scratch).  The Sequencer index F6 lets
; the chunk select which 64 KB slice of the up-to-1 MB on the card
; the CPU window currently aliases; see evg_set_sequencer_bank
; @ 0x1D26 and evg_vsync_wait @ 0x1CD9.
;
; The chunk is one of eight interchangeable graphics drivers in Vmcode.ovl.
; KRONDOR.EXE loads it via the RES-archive loader, runs its init prologue
; once, then snapshots its 50-slot vtable template into the host's
; g_renderer_vtable @ 39ae:2ac6 for ordinary far-call dispatch.
;
; *** STRUCTURAL LAYOUT NOTE: vtable is at chunk:0x0138 here, NOT the
; spec's documented standard offset 0x0200 (as used by CGA/VGA).  This
; layout deviation means the callback-table copy region at 0x01D8..0x0223
; (76 bytes = 19 far ptrs, see evg_init INIT SEQUENCE step 1) overlaps
; vtable slots 40..49 (the chunk-end slots), not the chunk-start slots.
; All core primitives (glyph, line, sprite, present, save/paste, vsync)
; have valid pointers in EVG; the overlapped slots 40..49 are dead.
;
; Cross-references:
;   Chipset references     -- Ferraro Programmer's Guide Ch. 22, the V7
;                              VGA Technical Reference (Jun 1988), and
;                              Finn Thogersen's vgadoc VIDEO7.TXT.  Treat
;                              as the authoritative chipset reference.
;
; Image base 0000:0000.
; ============================================================================

; ----------------------------------------------------------------------------
; What this driver is
;
; This is one of eight graphics drivers shipped inside Krondor's
; "Vmcode.ovl" (the engine's swappable video-mode archive).  The
; engine picks one at startup based on the user's "video setup"
; choice -- CGA, EGA, VGA-256, MCGA, Hercules, Tandy, etc. -- loads
; it into a free DOS paragraph, runs its init prologue once, and then
; dispatches every subsequent drawing request through a 50-entry
; "vtable" that the chunk publishes at chunk:0x0138.
;
; This particular chunk targets the **Video Seven V7VGA** family of
; Super-VGA chips (V7VGA, HT-208, HT-209, HT-216 -- all post-merger
; Headland Technology parts respond identically to the BIOS API used
; here).  Evidence the driver is V7-specific (and not a generic VGA
; driver):
;
;   - The init prologue probes with INT 10h AX=6F00h -- the canonical
;     V7 installation-check call -- and bails unless BX comes back as
;     0x5637 ("V7" in ASCII).
;   - It then sets video mode 0x66 via INT 10h AX=6F05h ("Set Super
;     Mode State"), which on V7 cards yields 640x400 at 256 colours
;     with a packed (one-byte-per-pixel) memory layout.
;   - After mode-set, the chunk clears the chain-4 bit in Sequencer
;     reg 04 to switch the chip into "Mode X" / unchained-256
;     layout (4 planes x 64,000 bytes), then drives the standard VGA
;     sequencer (0x3C4) Map-Mask register to pick one plane per
;     pixel.
;   - The bank-switching primitive everywhere else in the chunk is
;     a read-modify-write against Sequencer index 0xF6 -- the V7
;     "1 MB RAM Bank Select" register (Ferraro Fig 22.11).  This is
;     not a standard VGA register; it is a V7 extension.  Note the
;     read-modify-write idiom is required because SR-F6 carries
;     CRTC-bank and wrap-control bits in addition to the CPU bank
;     bits, so the chunk has to preserve the other bits.
;   - Drawing primitives talk to the standard VGA sequencer
;     (0x3C4/0x3C5), graphics controller (0x3CE/0x3CF), CRT
;     controller (0x3D4/0x3D5), and Input Status 1 (0x3DA).
;
; In rough numbers: ~25 % of the chunk is data (vtable, mask LUTs,
; per-call scratch, the 400-row scanline-offset LUT).  The other
; ~75 % is code -- one mid-sized init function, a small swarm of
; vtable-dispatched primitives (glyph, line, polygon, palette, paste,
; vsync, present), and a *huge* sprite-blitting subsystem with four
; near-identical flip-variant tails (h-flip / v-flip / vh-flip / no-
; flip).  The four sprite-blit-variant tails are the source of most
; of the file's line count.
; ----------------------------------------------------------------------------

; ----------------------------------------------------------------------------
; A primer on the hardware this driver talks to
;
; ## The video mode at runtime: 640x400x256, unchained ("Mode X")
;
; Mode 0x66 set via INT 10h AX=6F05h is documented in three primary
; sources -- Ferraro Ch. 22 Table 22.7, Finn Thogersen's
; vgadoc/VIDEO7.TXT line 411, and Mendelson's videomodes.txt -- as
; 640x400 at 256 colours (one byte per pixel, packed P8).  Frame
; size = 640 x 400 = 256,000 bytes.
;
; Immediately after the BIOS mode-set the chunk clears the chain-4
; bit (Sequencer reg 0x04 bit 3) and the chain-odd/even bit
; (Graphics Controller reg 0x06 bit 1).  This switches the chip
; into the well-known "Mode X" / unchained-256 layout that Michael
; Abrash popularised for the standard VGA mode 13h, applied here
; to V7's wider 640x400 framebuffer:
;
;   - Video RAM is logically four 64,000-byte planes (plane 0..3).
;   - One CPU byte at A000:[byte_offset] addresses ONE plane,
;     selected by the Sequencer Map-Mask register (3C4:02).  The
;     byte holds the full 8-bit colour for ONE pixel.
;   - The pixel at (x, y) lives at:
;         plane       = x & 3
;         byte_offset = y * 160 + (x / 4)
;     i.e. four horizontal pixels share one byte offset and differ
;     only in which plane the byte belongs to.
;   - Total framebuffer per page = 4 planes x (160 byte stride x
;     400 rows) = 256,000 bytes.  One plane (64,000 bytes) fits
;     in the 64 KB CPU window at A000:0000 with 1,536 bytes to
;     spare.
;
; The 0xA0 (= 160) stride constant you see everywhere is 640 / 4.
; The `MOV CX, BX / AND CL, 3 / MOV AX, 0x0102 / SHL AH, CL /
; OUT 0x3C4, AX` idiom (e.g. evg_putpixel, evg_draw_line's single-
; pixel case, evg_pixel_run_fill_a) is "select the plane that owns
; pixel x by setting map-mask = (1 << (x & 3))".  This is NOT a
; 16-colour 4-bit-per-pixel encoding -- the colour byte being
; written is a full 8-bit value (0..255).
;
; ## The standard VGA register banks
;
; All four banks use a 2-port "index, then data" protocol: write
; the register number to the index port, then read/write the
; register's contents through the data port.
;
;   Sequencer        index=0x3C4, data=0x3C5
;     reg 0x02  Map-Mask        which of the 4 planes accept CPU
;                               writes (bits 0..3 = planes 0..3).
;                               In Mode X this is "which plane
;                               does the next byte-write go to."
;     reg 0x04  Memory Mode     chain-4 (bit 3), odd-even (bit 2,
;                               note: this driver SETS bit 2 = ext-
;                               mem on), chain-odd-even (bit 0).
;                               The driver clears chain-4 to switch
;                               to Mode X.
;     reg 0x06  V7 Extensions   write 0xEA = unlock V7 extension
;                               registers; write 0xAE = re-lock.
;                               (V7 extension; Ferraro Fig 22.5.)
;     reg 0xF6  V7 Bank Select  the central V7 banking register.
;                               Bits 1-0 = CPU Write Bank, bits 3-2
;                               = CPU Read Bank, bits 5-4 = CRTC
;                               Display Bank, bit 6 = counter-bank-
;                               enable, bit 7 = line-compare bank-
;                               enable.  Every bit field has its
;                               own meaning, so every write to F6
;                               must be a read-modify-write.
;                               (V7 extension; Ferraro Fig 22.11.)
;     reg 0xFF  V7 16-bit Ctrl  bit 0 = enable 16-bit memory cycles
;                               to A000:0000-AFFFF (fast REP MOVSW),
;                               bit 4 = enable bank selection.  The
;                               init code OR-sets bit 4 here to
;                               turn banking on.  (V7 extension;
;                               Ferraro Table 22.8.)
;
;   Graphics Ctrl    index=0x3CE, data=0x3CF  (standard VGA -- the V7
;                                              does not extend this
;                                              register group)
;     reg 0x01  Enable Set/Reset (we keep at 0 = write CPU byte
;                                 unmodified)
;     reg 0x04  Read-Map-Select  which plane an A000-segment READ
;                                returns
;     reg 0x05  Mode             read-mode + write-mode + chain-odd-
;                                even; we set write-mode 1 (latch
;                                copy) in evg_present
;     reg 0x06  Miscellaneous    we clear bit 1 (chain-odd-even off)
;                                during init
;     reg 0x08  Bit Mask         8-bit "which CPU bits are allowed to
;                                modify the corresponding plane bit"
;
;   CRT Controller   index=0x3D4, data=0x3D5
;     reg 0x14  Underline Loc    we clear bit 6 (DW = doubleword
;                                addressing) during init so the CRTC
;                                steps the address counter by 1
;                                instead of 4 per byte fetched.
;     reg 0x17  CRTC Mode Ctrl   we set bit 6 (byte mode) so the
;                                CRTC's address-counter wrap matches
;                                Mode X's byte-per-pixel layout.
;
;   Input Status 1   read-only at port 0x3DA
;     bit 3 = "vertical retrace in progress" -- polled by vsync.
;     bit 0 = "display enable inhibited" -- polled for hblank.
;
; ## How V7 banking fits in
;
; A single 256,000-byte page fits across 4 planes of which each
; needs 64,000 bytes -- and 64,000 < 65,536 -- so a single page
; does NOT require bank switching.  But the V7VGA cards Krondor
; targets typically had 256 KB or 512 KB or 1 MB of video memory
; (Ferraro Ch. 22 §2.3, §2.5), enough for several pages plus
; off-screen sprite caches.  To reach beyond the first 64 KB
; window the chunk reprograms Sequencer index 0xF6 -- the V7 "1 MB
; RAM Bank Select" register.
;
; Because SR-F6's bank fields share the register with display-
; counter bits, every bank update is a read-modify-write
; (Ferraro Listing 22.6).  evg_set_sequencer_bank @ 0x1D26 does
; the OR-with-readback dance: it reads the current F6 value,
; OR-merges the requested bank bits into it, and writes it back.
; (It does NOT clear the old bank bits -- the caller is expected
; to have arranged for those bits to already be zero, or to want
; the OR-merge.)
;
; evg_init zeroes the first 64 KB of A000:0000 once with Map-Mask
; = 0x0F (writes propagate to all four planes simultaneously, so
; one STOSW clears 4 bytes of video RAM), switches the bank via
; F6 = 0x40, and zeroes 64 KB again -- in effect clearing two
; bank slots worth of memory at boot.
;
; evg_vsync_wait flips the displayed bank by writing the new
; bank index to F6 (this updates the CRTB field, picking the bank
; the CRTC scans out from).
;
; ## The 400-row scanline LUT
;
; The framebuffer byte offset for row Y is just Y * 160 (160 = 640
; / 4 bytes per row).  8086 multiplies are slow and the row
; index is used on virtually every primitive in this file.
; evg_init builds a 400-entry word LUT at DS:[0x6F2] holding
; row * 160 for row in [0, 400); every primitive then does a
; single word load (`MOV DI, [BX + 0x6F2]`) to get the row's base
; offset.  The LUT lives in scratch memory (the chunk's data
; segment), not in CS.
;
; ## Why row-doubling shows up everywhere
;
; Several primitives (evg_putpixel, evg_chunky_blit,
; evg_chunky_blit_doubled) write each pixel byte at both ES:[DI]
; and ES:[DI + 0xA0].  Krondor renders most of its world to a
; logical 320x200 framebuffer (the de-facto Sierra/Dynamix
; resolution of the era) and scales it 2x in both axes for
; 640x400 display.  The +0xA0 doubles the line; the doubling on
; the horizontal axis is handled by the source being chunky-2-
; pixel-per-byte and the destination being one of 4 plane
; offsets at the same byte position (consecutive output pixels
; on a single row share their plane-byte offset and differ only
; in plane index).
;
; ## References
;
; - Ferraro, *Programmer's Guide to the EGA, VGA, and Super VGA*
;   3rd ed., Ch. 22 (Video Seven)                  -- the authoritative
;   reference for the Video Seven register set.
; - V7 VGA Technical Reference Manual (Jun 1988, p/n 700-0242)
;                                                  -- Video Seven's own
;   246-page datasheet.
; - vgadoc/VIDEO7.TXT                              -- Finn Thogersen's
;   Video Seven chapter.  Brief and trustworthy.
; - vgadoc/VGAREGS.TXT                             -- standard VGA
;   registers the V7 extends.
; - FreeVGA (osdever.net/FreeVGA/home.htm)         -- encyclopedic
;   reference for every standard VGA register / mode mentioned above.
; - The bbcelite.com "deep dive" pattern           -- model for how
;   this file's comments are structured.
; ----------------------------------------------------------------------------

; ----------------------------------------------------------------------------
; How to read this source
;
; - TASM-specific: hex literals must start with a digit -- write
;   0AH not AH (the latter parses as a register).  H suffix marks
;   hex.  No suffix = decimal.
;
; - The whole driver is one flat code segment (`.MODEL TINY` +
;   one `.CODE` segment).  CS-relative addressing is the rule for
;   every chunk-local read/write because DS rarely points at the
;   chunk: the host calls in with DS pointing at its own state
;   blob, and the chunk swaps DS to a scratch segment (cached in
;   CS:[0x134] = g_wEvgChunkDataSeg) for chunk-local globals.
;   You will see `MOV cs:[NNNNH], AX` and `MOV ds:[NNNNH], AX`
;   constantly; the prefix tells you which segment the access
;   targets.
;
; - Local labels inside each PROC are prefixed with a short
;   nickname for the enclosing function -- e.g. `evg_dl_*`
;   inside evg_draw_line, `evg_sba_p0_*` inside the
;   sprite-blit no-flip variant for plane 0.  Cross-function
;   collisions are avoided by these prefixes (we don't use
;   anonymous `@@:` labels because they're hard to refer to from
;   prose).
;
; - PROC FAR vs PROC NEAR: the vtable-published primitives are all
;   FAR (the host calls them by far-pointer through the renderer
;   vtable).  Internal helpers like evg_set_sequencer_bank and
;   evg_sprite_blit_cleanup are NEAR -- the chunk's own code
;   reaches them with CALL NEAR.  When the chunk far-calls one of
;   its own near procs (because the call has to go through a
;   PUSH CS / CALL NEAR sequence to return via RETF), you'll see
;   the explicit `PUSH CS / CALL NEAR PTR foo` pair.
;
; - Calling conventions are mixed.  Some functions take stack
;   arguments at fixed [BP+N] slots (Borland's __cdecl16far);
;   others take register-passed arguments (typically BX, CX, DX,
;   SI as drawing coordinates).  Every function's plate comment
;   above the PROC lists the convention; do not assume cdecl.
;
; - The `; XX XX XX` at the end of each instruction is the
;   instruction's byte encoding.  Treat it as commentary, not as
;   restating the mnemonic.
;
; - NOSMART/SMART surrounds a few `LEA reg, ds:[NNNNH]` sites
;   where TASM 3.1's "smart" optimiser would otherwise downgrade
;   `LEA DI, [imm16]` to `MOV DI, imm16` and change the encoded
;   bytes.  The LEA opcode must be preserved, so those specific lines
;   are wrapped.
; ----------------------------------------------------------------------------

                .8086
                .MODEL  TINY
                .CODE

; Shared engine graphics-context STRUC (host scratch struct the driver
; overlays through DS after computing scratch_DS = caller_DS + base/16).
; A STRUC definition emits no bytes.
                INCLUDE gfxctx.inc

                ORG     0
                ASSUME  ds:NOTHING, es:NOTHING

; All forward-reference helper functions (evg_set_sequencer_bank,
; evg_sprite_blit_master, evg_sprite_blit_cleanup, etc.) are defined
; later in this file.  TASM resolves them via two-pass assembly.

; ============================================================================
; evg_init -- chunk initialiser (PROC FAR, called via the host's video_init).
; chunk:0x0000..0x0133
;
; CALLER ABI (host-side far call):
;   [BP+0x06]  ushort  backbuffer_paragraphs  (stashed to CS:[0x136])
;   [BP+0x08]  ushort  host_callbacks_off
;   [BP+0x0a]  ushort  host_callbacks_seg
;
; INIT SEQUENCE:
;   1. [0x00..0x18]  Copy 0x26 words (76 bytes = 19 far ptrs) from
;      DS:SI = host_callbacks_seg:host_callbacks_off into the chunk-
;      local mirror at CS:0x01D8 -- this overwrites vtable slots
;      40..49 (which on disk are RETF-stub pointers) AND the 9-entry
;      tail at 0x0200..0x0223.  The cells hold host callback far-
;      pointers at runtime; the overlapped vtable slots 40..49 are
;      never dispatched.
;   2. [0x19..0x33]  Save backbuffer_paragraphs to CS:[0x136]; derive
;      g_wEvgChunkDataSeg = (backbuffer_paragraphs >> 4) + CS and stash
;      to CS:[0x134]; load DS := scratch segment.
;   3. [0x34..0x3C]  Mark DS:[0x21] = 0xFF (mouse-active marker) and
;      INC DS:[0x1F] (mode flag).
;   4. [0x3D..0x4E]  INT 10h AX=6F00h -- Video Seven installation-check
;      (RBIL 106F00h, Ferraro §22.7.1).  BX must = 0x5637 ('V7' ASCII)
;      else bail to skip-init at 0x127 with AX=0 (driver-not-installed
;      return code).
;   5. [0x4F..0x56]  INT 10h AX=6F05h BL=0x66 -- V7 "Set Super Mode
;      State" (Ferraro §22.7.4) -> mode 66h = 640x400x256 packed P8
;      (Ferraro Table 22.7, vgadoc/VIDEO7.TXT:411).  This is the
;      *native* mode the BIOS programs; we will reconfigure into
;      unchained-Mode-X in the next steps.
;   6. [0x57..0x96]  Direct VGA programming (post BIOS mode-set):
;        Sequencer (0x3C4):
;          reg 0x06 = 0xEA -- unlock V7 extension registers
;                              (Ferraro Fig 22.5).
;          reg 0xFF readback then OR 0x10 -- enable V7 bank selection
;                                            (Ferraro Table 22.8 bit 4,
;                                            see the hardware primer
;                                            entry "Sequencer 0xFF").
;          reg 0xF6 = 0 -- reset V7 bank-select to bank 0
;                          (Ferraro Fig 22.11).
;          reg 0x04 readback & 0xF7 | 0x04 -- Memory Mode: clear
;                              chain-4 (bit 3) and set ext-mem (bit 2).
;                              This is THE step that switches the chip
;                              from packed P8 to unchained-256 layout.
;          reg 0x02 = 0x0F -- map mask = all 4 planes enabled (every
;                              CPU byte propagates to all four planes
;                              in parallel, used by the memory-clear
;                              below).
;        Graphics Controller (0x3CE):
;          reg 0x05 readback & 0xEF -- Mode: clear bit 4 (host odd/even
;                                      disable).
;          reg 0x06 readback & 0xFD -- Misc: clear bit 1
;                                      (chain-odd/even off).
;   7. [0x97..0xB6]  Zero 64 KB of A000:0000 in two 32-KW halves,
;      switching V7 bank (sequencer 0xF6 = 0x40) between halves --
;      i.e. clears bank 0 and bank 1, covering two pages.
;   8. [0xB7..0xE0]  CRTC + GC programming:
;        CRTC (0x3D4):
;          reg 0x14 readback & 0xBF -- Underline Location: clear bit 6
;                                      (DW = doubleword addressing off).
;          reg 0x17 readback | 0x40 -- CRTC Mode Control: set bit 6
;                                      (byte addressing on).
;        GC (0x3CE):
;          reg 0x05 = 0x40 -- Mode: write-mode 0, read-mode 0, the
;                              "256-colour shift" bit (bit 6) set
;                              -- present in the standard VGA mode 13h
;                              configuration too.
;          reg 0x01 = 0 -- Enable Set/Reset: all 0, so CPU writes pass
;                          unchanged.
;          reg 0x08 = 0xFF -- Bit Mask: all 8 bits writable.
;   9. [0xE1..0xF0]  Init DS state block:
;        DS:[0x14] = 0, DS:[0x10] = 0, DS:[0x12] = 1
;        DS:[0x6E2]++ (frame counter init)
;  10. [0xF1..0x10B] Build two 256-byte 0..255 LUTs at DS:[0x1BC] and
;       DS:[0x43C] (per-pixel mask tables, used by glyph blit).
;  11. [0x10C..0x11F] Build the 400-row scanline-offset LUT at DS:[0x6F2]
;      (400 entries x 2 bytes; stride 0xA0 = 160 bytes per row for the
;      unchained-Mode-X plane layout: 640 px wide / 4 px-per-plane-byte
;      = 160 byte stride per plane).
;  12. [0x120..0x126] AL := 9 (success); DS:[0x6E8] = 1 (mouse refresh
;      flag).
;  13. [0x127..0x133] Tail: DS:[0x1D] = AL; SI := 0x0138 (vtable);
;      DX := CS; restore regs; RETF.  Caller reads DX:SI as the
;      vtable far-pointer.
;
; RETURN:
;   AX    -- 9 on success, 0 on capability-probe failure
;            (i.e. AX=6F00h didn't return BX='V7').
;   DX:SI -- CS:0x0138, far pointer to g_apfnEvgVtable.
; ============================================================================
_start          LABEL   BYTE
evg_init        PROC    FAR
                PUSH    BP                      ; 55
                MOV     BP, SP                  ; 8B EC
                PUSH    DS                      ; 1E
                PUSH    SI                      ; 56
                PUSH    DI                      ; 57
                MOV     DI, 01D8H               ; BF D8 01
                PUSH    CS                      ; 0E
                POP     ES                      ; 07
                MOV     SI, [BP+8]              ; 8B 76 08
                MOV     DS, [BP+0AH]            ; 8E 5E 0A
                MOV     CX, 0026H               ; B9 26 00  38 words = 76 bytes
                REP     MOVSW                   ; F3 A5
                POP     DI                      ; 5F
                POP     SI                      ; 5E
                POP     DS                      ; 1F
                MOV     AX, [BP+6]              ; 8B 46 06

                MOV     cs:[0136H], AX          ; 2E A3 36 01
                SHR     AX, 1                   ; D1 E8
                SHR     AX, 1                   ; D1 E8
                SHR     AX, 1                   ; D1 E8
                SHR     AX, 1                   ; D1 E8   AX /= 16
                PUSH    DS                      ; 1E
                PUSH    DI                      ; 57
                MOV     BX, DS                  ; 8C DB
                ADD     AX, BX                  ; 03 C3
                MOV     cs:[0134H], AX          ; 2E A3 34 01
                MOV     DS, AX                  ; 8E D8   DS = scratch segment

                MOV     BYTE PTR ds:[GfxContext.bActiveVgaMode], 0FFH ; C6 06 21 00 FF
                INC     BYTE PTR ds:[GfxContext.bGfxRenderStateFlag]       ; FE 06 1F 00

                XOR     CX, CX                  ; 33 C9
                MOV     AX, 6F00H               ; B8 00 6F
                INT     10H                     ; CD 10   V7 install-check
                XOR     AX, AX                  ; 33 C0
                CMP     BX, 5637H               ; 81 FB 37 56  "V7" sig
                JZ      SHORT evg_init_probe_ok ; 74 03
                JMP     evg_init_exit           ; E9 D8 00   not V7 -> bail
evg_init_probe_ok:
                MOV     AX, 6F05H               ; B8 05 6F
                MOV     BL, 66H                 ; B3 66
                INT     10H                     ; CD 10   set V7 mode 0x66
                                                ;         (640x400x256
                                                ;         packed P8)

                ; --- Sequencer programming (port 0x3C4) ---
                MOV     DX, 03C4H               ; BA C4 03
                MOV     AX, 0EA06H              ; B8 06 EA  reg 0x06 = 0xEA:
                OUT     DX, AX                  ; EF       unlock V7 extensions
                                                ;         (Ferraro Fig 22.5)

                ; Sequencer 0xFF (V7 16-bit Interface Control,
                ; Ferraro Table 22.8): OR bit 4 -- enable bank
                ; selection.  Bit 4 = 0 would route all CPU accesses
                ; to a linear 256-KB region, bypassing F6 banking.
                MOV     DX, 03C4H               ; BA C4 03
                MOV     AL, 0FFH                ; B0 FF
                OUT     DX, AL                  ; EE       index = 0xFF
                INC     DX                      ; 42       data port (0x3C5)
                IN      AL, DX                  ; EC
                OR      AL, 10H                 ; 0C 10
                OUT     DX, AL                  ; EE       readback | 0x10

                ; Sequencer 0xF6 = 0 (V7 RAM Bank Select,
                ; Ferraro Fig 22.11): reset read-bank, write-bank,
                ; and CRTC-bank fields to 0 so the CPU window aliases
                ; the lowest 64-KB slice of video memory.
                DEC     DX                      ; 4A       index port
                MOV     AL, 0F6H                ; B0 F6
                OUT     DX, AL                  ; EE       index = 0xF6
                INC     DX                      ; 42
                XOR     AX, AX                  ; 33 C0
                OUT     DX, AL                  ; EE       bank = 0

                ; Sequencer 0x04 (Memory Mode, standard VGA): clear
                ; bit 3 (Chain-4) and set bit 2 (Extended Memory).
                ; Clearing Chain-4 is the step that converts the
                ; native packed P8 mode 66h into unchained-256
                ; ("Mode X") -- one CPU byte now writes ONE plane
                ; only, selected by the Map-Mask register below.
                MOV     DX, 03C4H               ; BA C4 03
                MOV     AL, 04H                 ; B0 04
                OUT     DX, AL                  ; EE       index = 0x04 (mem mode)
                INC     DX                      ; 42
                IN      AL, DX                  ; EC
                AND     AL, 0F7H                ; 24 F7    clear Chain-4
                OR      AL, 04H                 ; 0C 04    set Ext-Mem
                OUT     DX, AL                  ; EE

                ; --- Graphics Controller programming (port 0x3CE) ---
                MOV     DX, 03CEH               ; BA CE 03
                MOV     AL, 05H                 ; B0 05
                OUT     DX, AL                  ; EE       index = 0x05 (mode)
                INC     DX                      ; 42
                IN      AL, DX                  ; EC
                AND     AL, 0EFH                ; 24 EF    clear bit 4
                DEC     DX                      ; 4A
                MOV     AL, 06H                 ; B0 06
                OUT     DX, AL                  ; EE       index = 0x06 (misc)
                INC     DX                      ; 42
                IN      AL, DX                  ; EC
                AND     AL, 0FDH                ; 24 FD    clear chain-odd/even
                OUT     DX, AL                  ; EE

                ; --- Map-mask = all 4 planes, clear 64 KB video RAM ---
                ; With Map-Mask = 0x0F every CPU byte-write goes to
                ; all four planes at once.  STOSW for 32K words =
                ; 64 KB clears 256 KB of physical video memory
                ; (64 KB x 4 planes) per bank.  We do this twice,
                ; toggling F6 bit 6 (CRTB1 / WB1 -- one of the upper
                ; bank-select bits) between to cover bank 0 then
                ; bank 1.
                MOV     DX, 03C4H               ; BA C4 03
                MOV     AX, 0F02H               ; B8 02 0F  reg 0x02 = 0x0F
                OUT     DX, AX                  ; EF
                MOV     AX, 0A000H              ; B8 00 A0
                MOV     ES, AX                  ; 8E C0
                MOV     CX, 8000H               ; B9 00 80  32 KW
                XOR     AX, AX                  ; 33 C0
                MOV     DI, AX                  ; 8B F8
                CLD                             ; FC
                REP     STOSW                   ; F3 AB    zero bank 0
                MOV     AX, 40F6H               ; B8 F6 40  reg 0xF6 = 0x40
                OUT     DX, AX                  ; EF       switch to bank 1
                MOV     CX, 8000H               ; B9 00 80
                XOR     AX, AX                  ; 33 C0
                MOV     DI, AX                  ; 8B F8
                REP     STOSW                   ; F3 AB    zero bank 1
                MOV     AX, 00F6H               ; B8 F6 00  reg 0xF6 = 0
                OUT     DX, AX                  ; EF       back to bank 0

                ; --- CRTC programming (port 0x3D4) ---
                MOV     DX, 03D4H               ; BA D4 03
                MOV     AL, 14H                 ; B0 14
                OUT     DX, AL                  ; EE       index = 0x14 (underline)
                INC     DX                      ; 42
                IN      AL, DX                  ; EC
                AND     AL, 0BFH                ; 24 BF    clear DW
                OUT     DX, AL                  ; EE
                DEC     DX                      ; 4A
                MOV     AL, 17H                 ; B0 17
                OUT     DX, AL                  ; EE       index = 0x17 (mode ctrl)
                INC     DX                      ; 42
                IN      AL, DX                  ; EC
                OR      AL, 40H                 ; 0C 40    set byte mode
                OUT     DX, AL                  ; EE

                ; --- GC reg 0x05 = 0x40 (Mode reg = write-mode 0,
                ; read-mode 0, 256-colour-shift bit set; standard VGA
                ; semantics, see FreeVGA "Graphics Mode Register") ---
                MOV     DX, 03CEH               ; BA CE 03
                MOV     AL, 05H                 ; B0 05
                OUT     DX, AL                  ; EE       index
                INC     DX                      ; 42
                MOV     AL, 40H                 ; B0 40
                OUT     DX, AL                  ; EE       data
                DEC     DX                      ; 4A
                MOV     AX, 0001H               ; B8 01 00  reg 0x01 = 0 word write
                OUT     DX, AX                  ; EF
                MOV     AL, 08H                 ; B0 08
                OUT     DX, AL                  ; EE       index = 0x08 (bit mask)
                INC     DX                      ; 42
                MOV     AL, 0FFH                ; B0 FF
                OUT     DX, AL                  ; EE       data = 0xFF

                ; --- DS state init ---
                XOR     AX, AX                  ; 33 C0
                MOV     ds:[GfxContext.wVgaFrontPageBase], AX          ; A3 14 00
                MOV     ds:[GfxContext.wVgaPage1Base], AX          ; A3 10 00
                INC     AX                      ; 40
                MOV     ds:[GfxContext.wVgaPage2Base], AX          ; A3 12 00
                INC     WORD PTR ds:[06E2H]     ; FF 06 E2 06

                ; --- Build two 256-byte 0..255 LUTs at DS:[0x1BC]
                ; and DS:[0x43C]. Each iteration writes one word
                ; (i, i+0x101) into each LUT, advancing SI by 2.
                ; The ADD AX,0x101 / JNC / XOR AX,AX trick zeros AX
                ; whenever the increment carries past 0xFF, keeping
                ; the LSB tracking 0..255 modulo. ---
                XOR     AX, AX                  ; 33 C0
                MOV     SI, AX                  ; 8B F0
                MOV     CX, 0100H               ; B9 00 01
evg_init_byte_lut:
                MOV     [WORD PTR SI+01BCH], AX ; 89 84 BC 01
                MOV     [WORD PTR SI+043CH], AX ; 89 84 3C 04
                ADD     AX, 0101H               ; 05 01 01
                JNC     SHORT evg_init_byte_lut_nocarry ; 73 02
                XOR     AX, AX                  ; 33 C0
evg_init_byte_lut_nocarry:
                ADD     SI, 2                   ; 83 C6 02
                LOOP    SHORT evg_init_byte_lut ; E2 EC

                ; --- Build 400-row scanline offset LUT at DS:[0x6F2].
                ; row k -> 0xA0 * k.  In the unchained-Mode-X layout
                ; 0xA0 = 160 = 640 px / 4 px-per-plane-byte; the LUT
                ; gives you the byte offset of row k WITHIN one plane.
                MOV     CX, 0190H               ; B9 90 01  400
                NOSMART
                LEA     DI, ds:[GfxContext.pRow_offset_lut]          ; 8D 3E F2 06
                SMART
                MOV     AX, DS                  ; 8C D8
                MOV     ES, AX                  ; 8E C0
                XOR     AX, AX                  ; 33 C0
                CLD                             ; FC
evg_init_scanline_lut:
                STOSW                           ; AB
                ADD     AX, 00A0H               ; 05 A0 00
                LOOP    SHORT evg_init_scanline_lut ; E2 FA

                MOV     AL, 9                   ; B0 09
                MOV     BYTE PTR ds:[GfxContext.bYResDoubled], 1  ; C6 06 E8 06 01
evg_init_exit:
                MOV     DX, CS                  ; 8C CA
                NOSMART
                LEA     SI, ds:[0138H]          ; 8D 36 38 01  vtable offset
                SMART
                MOV     ds:[GfxContext.bVideoAdapter], AL          ; A2 1D 00     driver-installed flag
                POP     DI                      ; 5F
                POP     DS                      ; 1F
                POP     BP                      ; 5D
                RETF                            ; CB
evg_init        ENDP

; ============================================================================
; chunk:0x0134..0x0137 -- chunk-local globals stashed by evg_init.
; ============================================================================
g_wEvgChunkDataSeg          DW 0    ; 0x0134  scratch-DS paragraph
g_wEvgBackbufferParagraphs  DW 0    ; 0x0136  saved arg0

; ============================================================================
; g_apfnEvgVtable -- 50-slot renderer-vtable template (200 bytes).
; chunk:0x0138..0x01FF
;
; Snapshotted by the host into g_renderer_vtable @ 39ae:2ac6 after
; evg_init returns.  Each entry: (offset, segment-placeholder); the
; host stamps the chunk's load-segment paragraph into every segment
; half before activating the table.
;
; Slots 40..49 (offsets 0x01D8..0x01FF) overlap the host-callback-copy
; region.  On disk they hold pointers to the in-chunk RETF stub
; (evg_unimplemented_slot @ 0x0224); at runtime the chunk's init
; prologue overwrites this range with the host callback table.  The
; host never dispatches through those slots, so they are dead.
; ============================================================================
; Slots are declared as literal offsets (rather than `OFFSET evg_xxx`)
; to keep the table's layout readable as raw words; the table has
; several `dw 0224H` entries pointing at the unimpl-RETF stub.  Every
; literal offset here is annotated with the PROC label it resolves to
; at runtime.
g_apfnEvgVtable:
    dw 0000H, 0                              ; slot  0 -- null
    dw 0A9DH, 0                              ; slot  1 -- evg_glyph_row_blit
    dw 0225H, 0                              ; slot  2 -- evg_draw_line
    dw 0DCBH, 0                              ; slot  3 -- evg_sprite_blit_noflip
    dw 1D48H, 0                              ; slot  4 -- evg_present
    dw 1DAFH, 0                              ; slot  5 -- evg_save_rect_to_buffer
    dw 1E20H, 0                              ; slot  6 -- evg_sprite_buffer_size
    dw 1E36H, 0                              ; slot  7 -- evg_paste_rect_from_buffer
    dw 1CD9H, 0                              ; slot  8 -- evg_vsync_wait
    dw 0224H, 0                              ; slot  9 -- unimpl
    dw 0438H, 0                              ; slot 10 -- evg_pixel_run_fill_a
    dw 042FH, 0                              ; slot 11 -- evg_pixel_run_fill_b
    dw 0BBBH, 0                              ; slot 12 -- evg_save_rect_dos_buffer
    dw 084FH, 0                              ; slot 13 -- evg_image_install
    dw 0882H, 0                              ; slot 14 -- evg_image_decode_a
    dw 097DH, 0                              ; slot 15 -- evg_image_decode_b_nibbles
    dw 09D1H, 0                              ; slot 16 -- evg_image_install_list
    dw 0C77H, 0                              ; slot 17 -- evg_chunky_blit
    dw 0D12H, 0                              ; slot 18 -- evg_chunky_blit_doubled
    dw 0757H, 0                              ; slot 19 -- evg_palette_load
    dw 07AFH, 0                              ; slot 20 -- evg_palette_set
    dw 1EA9H, 0                              ; slot 21 -- evg_getpixel
    dw 1EE0H, 0                              ; slot 22 -- evg_putpixel
    dw 0224H, 0                              ; slot 23 -- unimpl
    dw 0224H, 0                              ; slot 24 -- unimpl
    dw 0224H, 0                              ; slot 25 -- unimpl
    dw 0224H, 0                              ; slot 26 -- unimpl
    dw 04C6H, 0                              ; slot 27 -- evg_polygon_span_fill
    dw 1D19H, 0                              ; slot 28 -- evg_set_bank_trivial
    dw 10DAH, 0                              ; slot 29 -- evg_sprite_blit_master
    dw 0224H, 0                              ; slot 30 -- unimpl
    dw 0224H, 0                              ; slot 31 -- unimpl
    dw 0224H, 0                              ; slot 32 -- unimpl
    dw 0224H, 0                              ; slot 33 -- unimpl
    dw 07DAH, 0                              ; slot 34 -- evg_palette_blend_upload
    dw 0000H, 0                              ; slot 35 -- null
    dw 0000H, 0                              ; slot 36 -- null
    dw 0000H, 0                              ; slot 37 -- null
    dw 0000H, 0                              ; slot 38 -- null
    dw 0000H, 0                              ; slot 39 -- null
    ; ---- slots 40..49 overlap host-callback-copy region ----
    dw 0224H, 0                              ; slot 40 @ 0x01D8
    dw 0224H, 0                              ; slot 41
    dw 0224H, 0                              ; slot 42
    dw 0224H, 0                              ; slot 43
    dw 0224H, 0                              ; slot 44
    dw 0224H, 0                              ; slot 45
    dw 0224H, 0                              ; slot 46
    dw 0224H, 0                              ; slot 47
    dw 0224H, 0                              ; slot 48
    dw 0224H, 0                              ; slot 49

; ============================================================================
; g_apHostCallbacksTail -- 9 far-ptr tail of the host-callback copy region.
; chunk:0x0200..0x0223
;
; On disk these 9 slots are pointers to evg_unimplemented_slot @ 0x0224
; (so dispatch through them is a no-op RETF in case the host inspects
; the vtable before evg_init runs).  At runtime evg_init's MOVSW loop
; overwrites this entire span with the tail of the 76-byte host-
; callback table, so the host never sees the initial values past
; chunk init.
; ============================================================================
g_apHostCallbacksTail:
    dw 0224H, 0                              ; cb tail #0 @ 0x0200
    dw 0224H, 0                              ; cb tail #1
    dw 0224H, 0                              ; cb tail #2
    dw 0224H, 0                              ; cb tail #3
    dw 0224H, 0                              ; cb tail #4
    dw 0224H, 0                              ; cb tail #5
    dw 0224H, 0                              ; cb tail #6
    dw 0224H, 0                              ; cb tail #7
    dw 0224H, 0                              ; cb tail #8

; ============================================================================
; evg_unimplemented_slot -- inert vtable target (just RETF).
; chunk:0x0224
;
; Slots in the vtable template for which the chunk supplies no
; implementation point here; this stub RETFs immediately if the
; host ever dispatches through one of those vacant slots.
; ============================================================================
evg_unimplemented_slot PROC FAR
                RETF                            ; CB
evg_unimplemented_slot ENDP

; ============================================================================
; evg_draw_line -- Bresenham line plot for unchained-Mode-X (640x400x256).
; chunk:0x0225..0x0421
;
; Vtable slot 2.
; Mirrors cga_draw_line in structure.  Each pixel write selects the
; owning plane via map-mask = (1 << (x & 3)) (sequencer reg 0x02 via
; port 0x3C4), then writes the full 8-bit colour byte to byte offset
; (y * 160 + x/4) in that plane.
;
; ABI (register-passed, called via host renderer vtable):
;   BX = x0, CX = y0, DX = x1, SI = y1.
; All four are SHL-1'd at entry (so subsequent shifts work on 2*coord).
; ES:DI must point at the active drawing surface (set by caller).
; DS is loaded from CS:[g_wEvgChunkDataSeg] (scratch state segment).
;
; Cases (see CMP/CMP+JNZ tree at 0x024e..0x025d):
;   single pixel     (BX==DX, CX==SI)  -> 0x0260 evg_dl_single
;   horizontal run   (BX!=DX, CX==SI)  -> 0x0277 evg_dl_horiz (tail-calls
;                                                  evg_pixel_run_fill_a)
;   vertical run     (BX==DX, CX!=SI)  -> 0x028f evg_dl_vertical
;   diagonal Bresen. (BX!=DX, CX!=SI)  -> 0x02ba evg_dl_diag
;       diag-equal   (|dy|==|dx|)      -> 0x02d4 evg_dl_diag_eq
;       diag x-major (|dy| <|dx|)      -> 0x030d evg_dl_diag_xmaj
;       diag y-major (|dy| >|dx|)      -> 0x038b evg_dl_diag_ymaj
;
; Returns via single POP DS / RETF at 0x0420.
;
; Note: at 0x0233 calls evg_set_sequencer_bank @ 0x1D26 (V7 bank
; select via sequencer 0xF6) so the line is plotted into the correct
; 64 KB window of A000:0000.
; ============================================================================
evg_draw_line   PROC    FAR
                PUSH    DS                      ; 1E
                SHL     BX, 1                   ; D1 E3
                SHL     CX, 1                   ; D1 E1
                SHL     DX, 1                   ; D1 E2
                SHL     SI, 1                   ; D1 E6
                MOV     DS, cs:[0134H]          ; 2E 8E 1E 34 01
                CALL    evg_set_sequencer_bank  ; E8 F0 1A
                XOR     AH, AH                  ; 32 E4
                MOV     AL, ds:[GfxContext.bGfx_outline_color]          ; A0 0E 00
                MOV     ds:[0022H], AX          ; A3 22 00
                MOV     DI, CX                  ; 8B F9
                SHL     DI, 1                   ; D1 E7
                MOV     DI, [WORD PTR DI+pRow_offset_lut] ; 8B BD F2 06
                MOV     AX, BX                  ; 8B C3
                SHR     AX, 1                   ; D1 E8
                SHR     AX, 1                   ; D1 E8
                ADD     DI, AX                  ; 03 F8
                CMP     BX, DX                  ; 3B DA
                JNZ     SHORT evg_dl_test_y     ; 75 07
                CMP     CX, SI                  ; 3B CE
                JZ      SHORT evg_dl_single     ; 74 0A
                JMP     SHORT evg_dl_vertical   ; EB 37
                NOP                             ; 90    alignment filler
evg_dl_test_y:
                CMP     CX, SI                  ; 3B CE
                JZ      SHORT evg_dl_horiz      ; 74 1A
                JMP     SHORT evg_dl_diag       ; EB 5B
                NOP                             ; 90    alignment filler

evg_dl_single:                                  ; chunk:0x0260
                MOV     CX, BX                  ; 8B CB
                MOV     AX, 0102H               ; B8 02 01
                AND     CL, 3                   ; 80 E1 03
                SHL     AH, CL                  ; D2 E4
                MOV     DX, 03C4H               ; BA C4 03
                OUT     DX, AX                  ; EF      seq[02] = plane mask
                MOV     AX, ds:[0022H]          ; A1 22 00
                MOV     ES:[DI], AL             ; 26 88 05
                JMP     evg_dl_exit             ; E9 A9 01

evg_dl_horiz:                                   ; chunk:0x0277
                MOV     AX, BX                  ; 8B C3
                SHR     AX, 1                   ; D1 E8
                SHR     AX, 1                   ; D1 E8
                SUB     DI, AX                  ; 2B F8
                MOV     AX, ds:[0022H]          ; A1 22 00
                MOV     AH, AL                  ; 8A E0
                SUB     DX, BX                  ; 2B D3
                MOV     CX, DX                  ; 8B CA
                PUSH    CS                      ; 0E
                CALL    NEAR PTR evg_pixel_run_fill_a ; E8 AC 01
                JMP     evg_dl_exit             ; E9 91 01

evg_dl_vertical:                                ; chunk:0x028f
                MOV     AX, 00A0H               ; B8 A0 00
                MOV     BP, AX                  ; 8B E8
                SUB     SI, CX                  ; 2B F1
                JG      SHORT evg_dl_vert_pos   ; 7F 04
                NEG     SI                      ; F7 DE
                NEG     BP                      ; F7 DD
evg_dl_vert_pos:
                MOV     CX, BX                  ; 8B CB
                MOV     AX, 0102H               ; B8 02 01
                AND     CL, 3                   ; 80 E1 03
                SHL     AH, CL                  ; D2 E4
                MOV     DX, 03C4H               ; BA C4 03
                OUT     DX, AX                  ; EF
                MOV     CX, SI                  ; 8B CE
                MOV     AX, ds:[0022H]          ; A1 22 00
                INC     CX                      ; 41
evg_dl_vert_loop:
                MOV     ES:[DI], AL             ; 26 88 05
                ADD     DI, BP                  ; 03 FD
                LOOP    SHORT evg_dl_vert_loop  ; E2 F9
                JMP     evg_dl_exit             ; E9 66 01

evg_dl_diag:                                    ; chunk:0x02ba
                MOV     AX, 00A0H               ; B8 A0 00
                MOV     BP, AX                  ; 8B E8
                SUB     DX, BX                  ; 2B D3
                SUB     SI, CX                  ; 2B F1
                JG      SHORT evg_dl_diag_pos   ; 7F 04
                NEG     SI                      ; F7 DE
                NEG     BP                      ; F7 DD
evg_dl_diag_pos:
                MOV     CX, SI                  ; 8B CE
                CMP     CX, DX                  ; 3B CA
                JZ      SHORT evg_dl_diag_eq    ; 74 05
                JC      SHORT evg_dl_diag_xmaj  ; 72 3C
                JMP     evg_dl_diag_ymaj        ; E9 B7 00

evg_dl_diag_eq:                                 ; chunk:0x02d4  |dy|==|dx|
                PUSH    CX                      ; 51
                MOV     CX, BX                  ; 8B CB
                AND     CL, 3                   ; 80 E1 03
                MOV     AX, 0102H               ; B8 02 01
                SHL     AH, CL                  ; D2 E4
                MOV     DX, 03C4H               ; BA C4 03
                OUT     DX, AX                  ; EF
                POP     CX                      ; 59
                MOV     BX, ds:[0022H]          ; 8B 1E 22 00
                INC     DX                      ; 42      DX = 0x3C5 (seq data)
                MOV     AL, AH                  ; 8A C4
                MOV     ES:[DI], BL             ; 26 88 1D
evg_dl_diag_eq_step:                            ; chunk:0x02EE
                SHL     AL, 1                   ; D0 E0
                TEST    AL, 10H                 ; A8 10
                JNZ     SHORT evg_dl_diag_eq_wrap ; 75 0B
                OUT     DX, AL                  ; EE
                MOV     ES:[DI], BL             ; 26 88 1D
                ADD     DI, BP                  ; 03 FD
                LOOP    SHORT evg_dl_diag_eq_step ; E2 F2
                JMP     SHORT evg_dl_diag_eq_done ; EB 0C
                NOP                             ; 90
evg_dl_diag_eq_wrap:                            ; chunk:0x02FF
                INC     DI                      ; 47
                MOV     AL, 1                   ; B0 01
                OUT     DX, AL                  ; EE
                MOV     ES:[DI], BL             ; 26 88 1D
                ADD     DI, BP                  ; 03 FD
                LOOP    SHORT evg_dl_diag_eq_step ; E2 E4
evg_dl_diag_eq_done:                            ; chunk:0x030A
                JMP     evg_dl_exit             ; E9 13 01

evg_dl_diag_xmaj:                               ; chunk:0x030D  |dy|<|dx|  X-major
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
                MOV     CX, BX                  ; 8B CB
                AND     CL, 3                   ; 80 E1 03
                MOV     AX, 0102H               ; B8 02 01
                SHL     AH, CL                  ; D2 E4
                MOV     DX, 03C4H               ; BA C4 03
                OUT     DX, AX                  ; EF
                INC     DX                      ; 42
                MOV     AL, AH                  ; 8A C4
                MOV     BX, ds:[0022H]          ; 8B 1E 22 00
                MOV     CX, ds:[GfxContext.wTextureIdx]          ; 8B 0E BC 06
                INC     CX                      ; 41
                MOV     ES:[DI], BL             ; 26 88 1D
evg_dl_xmaj_loop:                               ; chunk:0x0342
                MOV     ds:[06C0H], SI          ; 89 36 C0 06
                SUB     SI, CX                  ; 2B F1
                JGE     SHORT evg_dl_xmaj_si_ok ; 7D 06
                MOV     CX, ds:[06C0H]          ; 8B 0E C0 06
                XOR     SI, SI                  ; 33 F6
evg_dl_xmaj_si_ok:                              ; chunk:0x0350
                SHL     AL, 1                   ; D0 E0
                TEST    AL, 10H                 ; A8 10
                JNZ     SHORT evg_dl_xmaj_wrap  ; 75 27
                OUT     DX, AL                  ; EE
                MOV     ES:[DI], BL             ; 26 88 1D
                LOOP    SHORT evg_dl_xmaj_si_ok ; E2 F4
evg_dl_xmaj_si_check:                           ; chunk:0x035C
                CMP     SI, 0                   ; 83 FE 00
                JZ      SHORT evg_dl_xmaj_done  ; 74 27
                ADD     DI, BP                  ; 03 FD
                MOV     ES:[DI], BL             ; 26 88 1D
                MOV     CX, ds:[06BEH]          ; 8B 0E BE 06
                ADD     ds:[06C2H], CX          ; 01 0E C2 06
                JNC     SHORT evg_dl_xmaj_nc    ; 73 07
                MOV     CX, ds:[GfxContext.wTextureIdx]          ; 8B 0E BC 06
                INC     CX                      ; 41
                JMP     SHORT evg_dl_xmaj_loop  ; EB CB
evg_dl_xmaj_nc:                                 ; chunk:0x0377
                MOV     CX, ds:[GfxContext.wTextureIdx]          ; 8B 0E BC 06
                JMP     SHORT evg_dl_xmaj_loop  ; EB C5
evg_dl_xmaj_wrap:                               ; chunk:0x037D
                MOV     AL, 1                   ; B0 01
                INC     DI                      ; 47
                OUT     DX, AL                  ; EE
                MOV     ES:[DI], BL             ; 26 88 1D
                LOOP    SHORT evg_dl_xmaj_si_ok ; E2 CA
                JMP     SHORT evg_dl_xmaj_si_check ; EB D4
evg_dl_xmaj_done:                               ; chunk:0x0388
                JMP     evg_dl_exit             ; E9 95 00

evg_dl_diag_ymaj:                               ; chunk:0x038B  |dy|>|dx|  Y-major
                XCHG    CX, DX                  ; 87 CA
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
                MOV     CX, BX                  ; 8B CB
                AND     CL, 3                   ; 80 E1 03
                MOV     AX, 0102H               ; B8 02 01
                SHL     AH, CL                  ; D2 E4
                MOV     DX, 03C4H               ; BA C4 03
                OUT     DX, AX                  ; EF
                INC     DX                      ; 42
                MOV     AL, AH                  ; 8A C4
                MOV     BX, ds:[0022H]          ; 8B 1E 22 00
                MOV     CX, ds:[GfxContext.wTextureIdx]          ; 8B 0E BC 06
                INC     CX                      ; 41
                OUT     DX, AL                  ; EE
                MOV     ES:[DI], BL             ; 26 88 1D
evg_dl_ymaj_loop:                               ; chunk:0x03C3
                MOV     ds:[06C0H], SI          ; 89 36 C0 06
                SUB     SI, CX                  ; 2B F1
                JGE     SHORT evg_dl_ymaj_si_ok ; 7D 06
                MOV     CX, ds:[06C0H]          ; 8B 0E C0 06
                XOR     SI, SI                  ; 33 F6
evg_dl_ymaj_si_ok:                              ; chunk:0x03D1
                ADD     DI, BP                  ; 03 FD
                OUT     DX, AL                  ; EE
                MOV     ES:[DI], BL             ; 26 88 1D
                DEC     CX                      ; 49
                JZ      SHORT evg_dl_ymaj_si_chk ; 74 02
                JMP     SHORT evg_dl_ymaj_si_ok ; EB F5
evg_dl_ymaj_si_chk:                             ; chunk:0x03DC
                CMP     SI, 0                   ; 83 FE 00
                JZ      SHORT evg_dl_ymaj_done  ; 74 3F
                SHL     AL, 1                   ; D0 E0
                TEST    AL, 10H                 ; A8 10
                JNZ     SHORT evg_dl_ymaj_wrap  ; 75 1B
                OUT     DX, AL                  ; EE
                MOV     ES:[DI], BL             ; 26 88 1D
                MOV     CX, ds:[06BEH]          ; 8B 0E BE 06
                ADD     ds:[06C2H], CX          ; 01 0E C2 06
                JNC     SHORT evg_dl_ymaj_nc1   ; 73 07
                MOV     CX, ds:[GfxContext.wTextureIdx]          ; 8B 0E BC 06
                INC     CX                      ; 41
                JMP     SHORT evg_dl_ymaj_loop  ; EB C7
evg_dl_ymaj_nc1:                                ; chunk:0x03FC
                MOV     CX, ds:[GfxContext.wTextureIdx]          ; 8B 0E BC 06
                JMP     SHORT evg_dl_ymaj_loop  ; EB C1
evg_dl_ymaj_wrap:                               ; chunk:0x0402
                MOV     AL, 1                   ; B0 01
                INC     DI                      ; 47
                OUT     DX, AL                  ; EE
                MOV     ES:[DI], BL             ; 26 88 1D
                MOV     CX, ds:[06BEH]          ; 8B 0E BE 06
                ADD     ds:[06C2H], CX          ; 01 0E C2 06
                JNC     SHORT evg_dl_ymaj_nc2   ; 73 07
                MOV     CX, ds:[GfxContext.wTextureIdx]          ; 8B 0E BC 06
                INC     CX                      ; 41
                JMP     SHORT evg_dl_ymaj_loop  ; EB A9
evg_dl_ymaj_nc2:                                ; chunk:0x041A
                MOV     CX, ds:[GfxContext.wTextureIdx]          ; 8B 0E BC 06
                JMP     SHORT evg_dl_ymaj_loop  ; EB A3
evg_dl_ymaj_done:                               ; chunk:0x041F  fall to exit
evg_dl_exit:                                    ; chunk:0x0420
                POP     DS                      ; 1F
                RETF                            ; CB
evg_draw_line   ENDP

; ============================================================================
; g_abEvgRunFillMaskLut -- 12-byte mask LUT consumed by pixel_run_fill_a
; chunk:0x0422..0x042D
;
; Three 4-byte tables packed back-to-back:
;   +0  (0x0F,0x0E,0x0C,0x08) -- leading 4-bit plane-mask for left edge
;   +4  (0x0F,0x01,0x03,0x07) -- single-byte / right-edge mask
;   +8  (0x00,0x01,0x03,0x07) -- trailing 4-bit plane-mask for right edge
; Indexed by (x & 3) -- the four possible plane-positions of a pixel.
; In unchained-Mode-X every 4 horizontal pixels share one byte offset
; and differ only in plane; a run that begins at x mod 4 = 1 has only
; planes 1, 2, 3 to fill on its leading byte, hence mask 0x0E.  A
; second copy lives at 0x04B2 (g_abEvgRunFillMaskLut2).
; ============================================================================
g_abEvgRunFillMaskLut:
                DB      0FH, 0EH, 0CH, 08H
                DB      0FH, 01H, 03H, 07H
                DB      00H, 01H, 03H, 07H

; ============================================================================
; evg_pixel_run_fill_b -- alternating-state wrapper around fill_a.
; chunk:0x042F..0x0437 (9 bytes), vtable slot 11.
;
; The whole function is three real instructions plus a fall-through.
; It toggles bit 0 of DS:[0x2A] (a 1-bit "phase" flag):
;
;   * if the flag is now 0 (XOR result zero, ZF=1)  -> JZ to
;     evg_pixel_run_fill_a unchanged: the fill uses the AX the caller
;     supplied (low byte = run length, high byte = pixel value).
;   * if the flag is now 1 (ZF=0)  -> fall through `MOV AX, DX` first,
;     overwriting AX with DX before entering fill_a.  Effectively the
;     caller's second argument selects the pixel value on every other
;     call.
;
; Net result: alternating calls pick the colour either from the AX
; the caller staged or from DX, giving a cheap 2-colour dither when
; both colours are pre-loaded in AX/DX.
;
; The standalone `evg_pixel_run_fill_shared_retf` (one RETF byte) sits
; at chunk:0x042E and is shared by fill_a's "size <= 0" early-exit
; (saves one byte versus emitting a RETF inside fill_a itself).
; ============================================================================
evg_pixel_run_fill_shared_retf:                 ; chunk:0x042E
                RETF                            ; CB     shared early-exit

evg_pixel_run_fill_b PROC FAR
                XOR     WORD PTR ds:[002AH], 1  ; 83 36 2A 00 01
                JZ      SHORT evg_pixel_run_fill_a ; 74 02
                MOV     AX, DX                  ; 8B C2
evg_pixel_run_fill_b ENDP
                                                ; falls through into _a

; ============================================================================
; evg_pixel_run_fill_a -- run-of-pixels horizontal fill into Mode-X planes.
; chunk:0x0438..0x04B1 (122 bytes)
;
; Vtable slot 10.  Also tail-called from evg_draw_line's horizontal-line
; case at 0x0289 (PUSH CS / CALL near).
;
; Register ABI:
;   BX = x_start, CX = run_length, ES:DI = framebuffer cursor.
;   AX (high byte = pixel value byte, low byte = run length on entry).
;   The function dispatches on whether the run stays within one byte
;   offset (i.e. all four planes' bytes at that offset cover the whole
;   run -- the "4-pixel cluster" case) or crosses into the bulk-fill
;   path that strides through byte offsets.
; ============================================================================
evg_pixel_run_fill_a PROC FAR
                OR      CX, CX                  ; 0B C9
                JLE     SHORT evg_pixel_run_fill_shared_retf ; 7E F2   ; jumps to 0x42E
                MOV     DX, AX                  ; 8B D0
                MOV     AX, BX                  ; 8B C3
                ADD     AX, CX                  ; 03 C1
                DEC     AX                      ; 48
                XOR     AX, BX                  ; 33 C3
                AND     AX, 0FFCH               ; 25 FC 0F
                JNZ     SHORT evg_prf_bulk      ; 75 28
                MOV     AX, BX                  ; 8B C3
                SHR     AX, 1                   ; D1 E8
                SHR     AX, 1                   ; D1 E8
                ADD     DI, AX                  ; 03 F8
                MOV     AX, BX                  ; 8B C3
                ADD     BX, CX                  ; 03 D9
                AND     AX, 3                   ; 25 03 00
                AND     BX, 3                   ; 81 E3 03 00
                MOV     CL, AL                  ; 8A C8
                MOV     AX, 0FF02H              ; B8 02 FF
                SHL     AH, CL                  ; D2 E4
                AND     AH, [BYTE PTR cs:BX+0426H] ; 2E 22 A7 26 04
                MOV     BX, DX                  ; 8B DA
                MOV     DX, 03C4H               ; BA C4 03
                OUT     DX, AX                  ; EF
                MOV     AX, BX                  ; 8B C3
                STOSB                           ; AA
                RETF                            ; CB

evg_prf_bulk:                                   ; chunk:0x0472
                MOV     AX, BX                  ; 8B C3
                SHR     AX, 1                   ; D1 E8
                SHR     AX, 1                   ; D1 E8
                ADD     DI, AX                  ; 03 F8
                AND     BX, 3                   ; 81 E3 03 00
                SUB     CX, 4                   ; 83 E9 04
                ADD     CX, BX                  ; 03 CB
                MOV     AH, [BYTE PTR cs:BX+0422H] ; 2E 8A A7 22 04
                MOV     AL, 2                   ; B0 02
                MOV     BX, DX                  ; 8B DA
                MOV     DX, 03C4H               ; BA C4 03
                OUT     DX, AX                  ; EF
                INC     DX                      ; 42
                MOV     AX, BX                  ; 8B C3
                STOSB                           ; AA
                MOV     AL, 0FH                 ; B0 0F
                OUT     DX, AL                  ; EE
                MOV     AL, AH                  ; 8A C4
                MOV     BX, CX                  ; 8B D9
                SHR     CX, 1                   ; D1 E9
                SHR     CX, 1                   ; D1 E9
                SHR     CX, 1                   ; D1 E9
                JNC     SHORT evg_prf_no_stosb  ; 73 01
                STOSB                           ; AA
evg_prf_no_stosb:                               ; chunk:0x04A3
                REP     STOSW                   ; F3 AB
                AND     BX, 3                   ; 81 E3 03 00
                MOV     AL, [BYTE PTR cs:BX+042AH] ; 2E 8A 87 2A 04
                OUT     DX, AL                  ; EE
                MOV     AL, AH                  ; 8A C4
                STOSB                           ; AA
                RETF                            ; CB
evg_pixel_run_fill_a ENDP

; ============================================================================
; g_abEvgRunFillMaskLut2 -- duplicate of g_abEvgRunFillMaskLut.
; chunk:0x04B2..0x04BD
;
; Consumed by evg_polygon_span_fill (the polygon span fill inlines the
; same fill core as evg_pixel_run_fill_a, so the CS-relative LUT lives
; near the function body).
; ============================================================================
g_abEvgRunFillMaskLut2:
                DB      0FH, 0EH, 0CH, 08H
                DB      0FH, 01H, 03H, 07H
                DB      00H, 01H, 03H, 07H

; ============================================================================
; chunk:0x04BE..0x04C5 -- 8 bytes of mutable per-call scratch globals
; touched by evg_polygon_span_fill.
;   0x04BE  remaining_lines  -- decremented by the outer loop
;   0x04C0  fill_value_low   -- cached AX from CS:[0x4C0]
;   0x04C2  fill_value_high  -- cached AX from CS:[0x4C2]
;   0x04C4  row_lut_off      -- LEA result for DS:[0x6F2] + bb-paragraphs
; All on disk = 0 because evg_polygon_span_fill overwrites them on
; first call.
; ============================================================================
g_wEvgSpanRemaining     DW 0    ; 0x04BE
g_wEvgSpanFillLow       DW 0    ; 0x04C0
g_wEvgSpanFillHigh      DW 0    ; 0x04C2
g_wEvgSpanRowLutOff     DW 0    ; 0x04C4

; ============================================================================
; evg_polygon_span_fill -- scan-converter polygon scanline fill.
; chunk:0x04C6..0x0704 (575 bytes).
;
; Vtable slot 27.
; Inlines a copy of evg_pixel_run_fill_a's fast core three times,
; once per polygon segment (top edge / middle / bottom edge).
;
; ABI (register/stack via caller; reads source span data from DS:SI):
;   DS:SI -- pointer to span descriptor: [count, x0, x1, x0, x1, ...]
;   ES    -- framebuffer segment (A000:0000)
;
; Outer state in CS:[0x04BE..0x04C5] is the per-call mutable cache so
; the three near-identical body copies don't keep recomputing it.
; ============================================================================
evg_polygon_span_fill PROC FAR
                PUSH    DS                      ; 1E
                MOV     CX, ES                  ; 8C C1
                MOV     DS, CX                  ; 8E D9
                LODSW                           ; AD
                SHL     AX, 1                   ; D1 E0
                MOV     BP, AX                  ; 8B E8
                LODSW                           ; AD
                MOV     DS, cs:[0134H]          ; 2E 8E 1E 34 01
                MOV     cs:[04BEH], AX          ; 2E A3 BE 04
                CALL    evg_set_sequencer_bank  ; E8 49 18
                NOSMART
                LEA     AX, ds:[GfxContext.pRow_offset_lut]          ; 8D 06 F2 06
                SMART
                ADD     AX, cs:[0136H]          ; 2E 03 06 36 01
                MOV     cs:[04C4H], AX          ; 2E A3 C4 04
                MOV     AL, ds:[GfxContext.bGfx_fill_color]          ; A0 0D 00
                SUB     AH, AH                  ; 2A E4
                MOV     BX, AX                  ; 8B D8
                SHL     BX, 1                   ; D1 E3
                MOV     AX, [WORD PTR BX+01BCH] ; 8B 87 BC 01
                MOV     cs:[04C0H], AX          ; 2E A3 C0 04
                MOV     DX, AX                  ; 8B D0
                MOV     AX, [WORD PTR BX+043CH] ; 8B 87 3C 04
                CMP     AX, DX                  ; 3B C2
                MOV     DS, CX                  ; 8E D9
                JZ      SHORT evg_psf_top       ; 74 03
                JMP     evg_psf_mid_entry       ; E9 9F 00

evg_psf_top:                                    ; chunk:0x050A
                LODSW                           ; AD
                MOV     BX, AX                  ; 8B D8
                LODSW                           ; AD
                SUB     AX, BX                  ; 2B C3
                JGE     SHORT evg_psf_top_ok    ; 7D 03
                JMP     evg_psf_top_step        ; E9 84 00
evg_psf_top_ok:                                 ; chunk:0x0515
                INC     AX                      ; 40
                MOV     CX, AX                  ; 8B C8
                MOV     DI, cs:[04C4H]          ; 2E 8B 3E C4 04
                MOV     DI, [WORD PTR BP+DI]    ; 8B 3B
                MOV     AX, cs:[04C0H]          ; 2E A1 C0 04
                MOV     DX, AX                  ; 8B D0
                MOV     AX, BX                  ; 8B C3
                ADD     AX, CX                  ; 03 C1
                DEC     AX                      ; 48
                XOR     AX, BX                  ; 33 C3
                AND     AX, 0FFCH               ; 25 FC 0F
                JNZ     SHORT evg_psf_top_bulk  ; 75 29
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
                AND     AH, [BYTE PTR cs:BX+04B6H] ; 2E 22 A7 B6 04
                MOV     BX, DX                  ; 8B DA
                MOV     DX, 03C4H               ; BA C4 03
                OUT     DX, AX                  ; EF
                MOV     AX, BX                  ; 8B C3
                STOSB                           ; AA
                JMP     SHORT evg_psf_top_step  ; EB 3F
evg_psf_top_bulk:                               ; chunk:0x055A
                MOV     AX, BX                  ; 8B C3
                SHR     AX, 1                   ; D1 E8
                SHR     AX, 1                   ; D1 E8
                ADD     DI, AX                  ; 03 F8
                AND     BX, 3                   ; 83 E3 03
                SUB     CX, 4                   ; 83 E9 04
                ADD     CX, BX                  ; 03 CB
                MOV     AH, [BYTE PTR cs:BX+04B2H] ; 2E 8A A7 B2 04
                MOV     AL, 2                   ; B0 02
                MOV     BX, DX                  ; 8B DA
                MOV     DX, 03C4H               ; BA C4 03
                OUT     DX, AX                  ; EF
                INC     DX                      ; 42
                MOV     AX, BX                  ; 8B C3
                STOSB                           ; AA
                MOV     AL, 0FH                 ; B0 0F
                OUT     DX, AL                  ; EE
                MOV     AL, AH                  ; 8A C4
                MOV     BX, CX                  ; 8B D9
                SHR     CX, 1                   ; D1 E9
                SHR     CX, 1                   ; D1 E9
                SHR     CX, 1                   ; D1 E9
                JNC     SHORT evg_psf_top_no_stosb ; 73 01
                STOSB                           ; AA
evg_psf_top_no_stosb:                           ; chunk:0x058B
                REP     STOSW                   ; F3 AB
                AND     BX, 3                   ; 83 E3 03
                MOV     AL, [BYTE PTR cs:BX+04BAH] ; 2E 8A 87 BA 04
                OUT     DX, AL                  ; EE
                MOV     AL, AH                  ; 8A C4
                STOSB                           ; AA
evg_psf_top_step:                               ; chunk:0x0599
                SUB     WORD PTR cs:[04BEH], 1  ; 2E 83 2E BE 04 01
                JLE     SHORT evg_psf_top_done  ; 7E 06
                ADD     BP, 2                   ; 83 C5 02
                JMP     evg_psf_top             ; E9 63 FF
evg_psf_top_done:                               ; chunk:0x05A7
                POP     DS                      ; 1F
                RETF                            ; CB

evg_psf_mid_entry:                              ; chunk:0x05A9
                MOV     cs:[04C2H], AX          ; 2E A3 C2 04
                MOV     BX, BP                  ; 8B DD
                SHR     BX, 1                   ; D1 EB
                JPO     SHORT evg_psf_mid       ; 7B 03   JPO == JNP
                JMP     evg_psf_bot_entry       ; E9 9C 00
evg_psf_mid:                                    ; chunk:0x05B6
                LODSW                           ; AD
                MOV     BX, AX                  ; 8B D8
                LODSW                           ; AD
                SUB     AX, BX                  ; 2B C3
                JGE     SHORT evg_psf_mid_ok    ; 7D 03
                JMP     evg_psf_mid_step        ; E9 84 00
evg_psf_mid_ok:                                 ; chunk:0x05C1
                INC     AX                      ; 40
                MOV     CX, AX                  ; 8B C8
                MOV     DI, cs:[04C4H]          ; 2E 8B 3E C4 04
                MOV     DI, [WORD PTR BP+DI]    ; 8B 3B
                MOV     AX, cs:[04C0H]          ; 2E A1 C0 04
                MOV     DX, AX                  ; 8B D0
                MOV     AX, BX                  ; 8B C3
                ADD     AX, CX                  ; 03 C1
                DEC     AX                      ; 48
                XOR     AX, BX                  ; 33 C3
                AND     AX, 0FFCH               ; 25 FC 0F
                JNZ     SHORT evg_psf_mid_bulk  ; 75 29
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
                AND     AH, [BYTE PTR cs:BX+04B6H] ; 2E 22 A7 B6 04
                MOV     BX, DX                  ; 8B DA
                MOV     DX, 03C4H               ; BA C4 03
                OUT     DX, AX                  ; EF
                MOV     AX, BX                  ; 8B C3
                STOSB                           ; AA
                JMP     SHORT evg_psf_mid_step  ; EB 3F
evg_psf_mid_bulk:                               ; chunk:0x0606
                MOV     AX, BX                  ; 8B C3
                SHR     AX, 1                   ; D1 E8
                SHR     AX, 1                   ; D1 E8
                ADD     DI, AX                  ; 03 F8
                AND     BX, 3                   ; 83 E3 03
                SUB     CX, 4                   ; 83 E9 04
                ADD     CX, BX                  ; 03 CB
                MOV     AH, [BYTE PTR cs:BX+04B2H] ; 2E 8A A7 B2 04
                MOV     AL, 2                   ; B0 02
                MOV     BX, DX                  ; 8B DA
                MOV     DX, 03C4H               ; BA C4 03
                OUT     DX, AX                  ; EF
                INC     DX                      ; 42
                MOV     AX, BX                  ; 8B C3
                STOSB                           ; AA
                MOV     AL, 0FH                 ; B0 0F
                OUT     DX, AL                  ; EE
                MOV     AL, AH                  ; 8A C4
                MOV     BX, CX                  ; 8B D9
                SHR     CX, 1                   ; D1 E9
                SHR     CX, 1                   ; D1 E9
                SHR     CX, 1                   ; D1 E9
                JNC     SHORT evg_psf_mid_no_stosb ; 73 01
                STOSB                           ; AA
evg_psf_mid_no_stosb:                           ; chunk:0x0637
                REP     STOSW                   ; F3 AB
                AND     BX, 3                   ; 83 E3 03
                MOV     AL, [BYTE PTR cs:BX+04BAH] ; 2E 8A 87 BA 04
                OUT     DX, AL                  ; EE
                MOV     AL, AH                  ; 8A C4
                STOSB                           ; AA
evg_psf_mid_step:                               ; chunk:0x0645
                SUB     WORD PTR cs:[04BEH], 1  ; 2E 83 2E BE 04 01
                JG      SHORT evg_psf_mid_advance ; 7F 02
                POP     DS                      ; 1F
                RETF                            ; CB
evg_psf_mid_advance:                            ; chunk:0x064F
                ADD     BP, 2                   ; 83 C5 02
evg_psf_bot_entry:                              ; chunk:0x0652
                LODSW                           ; AD
                MOV     BX, AX                  ; 8B D8
                LODSW                           ; AD
                SUB     AX, BX                  ; 2B C3
                JGE     SHORT evg_psf_bot_ok    ; 7D 03
                JMP     evg_psf_bot_step        ; E9 84 00
evg_psf_bot_ok:                                 ; chunk:0x065D
                INC     AX                      ; 40
                MOV     CX, AX                  ; 8B C8
                MOV     DI, cs:[04C4H]          ; 2E 8B 3E C4 04
                MOV     DI, [WORD PTR BP+DI]    ; 8B 3B
                MOV     AX, cs:[04C2H]          ; 2E A1 C2 04
                MOV     DX, AX                  ; 8B D0
                MOV     AX, BX                  ; 8B C3
                ADD     AX, CX                  ; 03 C1
                DEC     AX                      ; 48
                XOR     AX, BX                  ; 33 C3
                AND     AX, 0FFCH               ; 25 FC 0F
                JNZ     SHORT evg_psf_bot_bulk  ; 75 29
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
                AND     AH, [BYTE PTR cs:BX+04B6H] ; 2E 22 A7 B6 04
                MOV     BX, DX                  ; 8B DA
                MOV     DX, 03C4H               ; BA C4 03
                OUT     DX, AX                  ; EF
                MOV     AX, BX                  ; 8B C3
                STOSB                           ; AA
                JMP     SHORT evg_psf_bot_step  ; EB 3F
evg_psf_bot_bulk:                               ; chunk:0x06A2
                MOV     AX, BX                  ; 8B C3
                SHR     AX, 1                   ; D1 E8
                SHR     AX, 1                   ; D1 E8
                ADD     DI, AX                  ; 03 F8
                AND     BX, 3                   ; 83 E3 03
                SUB     CX, 4                   ; 83 E9 04
                ADD     CX, BX                  ; 03 CB
                MOV     AH, [BYTE PTR cs:BX+04B2H] ; 2E 8A A7 B2 04
                MOV     AL, 2                   ; B0 02
                MOV     BX, DX                  ; 8B DA
                MOV     DX, 03C4H               ; BA C4 03
                OUT     DX, AX                  ; EF
                INC     DX                      ; 42
                MOV     AX, BX                  ; 8B C3
                STOSB                           ; AA
                MOV     AL, 0FH                 ; B0 0F
                OUT     DX, AL                  ; EE
                MOV     AL, AH                  ; 8A C4
                MOV     BX, CX                  ; 8B D9
                SHR     CX, 1                   ; D1 E9
                SHR     CX, 1                   ; D1 E9
                SHR     CX, 1                   ; D1 E9
                JNC     SHORT evg_psf_bot_no_stosb ; 73 01
                STOSB                           ; AA
evg_psf_bot_no_stosb:                           ; chunk:0x06D3
                REP     STOSW                   ; F3 AB
                AND     BX, 3                   ; 83 E3 03
                MOV     AL, [BYTE PTR cs:BX+04BAH] ; 2E 8A 87 BA 04
                OUT     DX, AL                  ; EE
                MOV     AL, AH                  ; 8A C4
                STOSB                           ; AA
evg_psf_bot_step:                               ; chunk:0x06E1
                SUB     WORD PTR cs:[04BEH], 1  ; 2E 83 2E BE 04 01
                JLE     SHORT evg_psf_bot_done  ; 7E 06
                ADD     BP, 2                   ; 83 C5 02
                JMP     evg_psf_mid             ; E9 C7 FE
evg_psf_bot_done:                               ; chunk:0x06EF
                POP     DS                      ; 1F
                RETF                            ; CB
evg_polygon_span_fill ENDP

; ============================================================================
; g_apEvgPaletteCache -- palette cache pointer slots.
; chunk:0x06F1..0x0704 (20 bytes, 10 word slots).
;
; Each slot caches the buffer pointer returned by the host RES-archive
; asset-open callback for palette ID `slot_index`.  Indexed by
; (palette_id * 2).  Slot 0 (at 0x06F1) doubles as the "active palette
; pointer" cached by evg_palette_set.
; ============================================================================
g_apEvgPaletteCache:
                DB      20 DUP (0)

; ============================================================================
; evg_dac_palette_write -- DAC palette bank upload.
; chunk:0x0705..0x073F (59 bytes).
;
; ABI (__cdecl16far, called via PUSH SI / PUSH BX / PUSH AX / CALLF):
;   [BP+6]   ushort  src_off       -- offset of RGB byte triples in DS
;   [BP+8]   ushort  start_index   -- DAC start register
;   [BP+0A]  ushort  entry_count   -- number of RGB triples
;
; Waits for vsync (port 0x3DA bit 3) and then bursts entries into the
; VGA DAC starting at start_index.  CLI/STI around the inner loop to
; avoid mid-burst interrupts that would mis-time the 6-bit DAC writes.
; ============================================================================
evg_dac_palette_write PROC FAR
                PUSH    BP                      ; 55
                MOV     BP, SP                  ; 8B EC
                PUSH    SI                      ; 56
                MOV     SI, [BP+6]              ; 8B 76 06
                MOV     CX, [BP+0AH]            ; 8B 4E 0A
                MOV     AX, CX                  ; 8B C1
                SHL     CX, 1                   ; D1 E1
                ADD     CX, AX                  ; 03 C8   CX = entry_count * 3
                MOV     BX, [BP+8]              ; 8B 5E 08
                MOV     DX, 03DAH               ; BA DA 03
evg_dac_vsync:                                  ; chunk:0x071B
                IN      AL, DX                  ; EC
                AND     AL, 8                   ; 24 08
                JZ      SHORT evg_dac_vsync     ; 74 FB
                MOV     DX, 03C7H               ; BA C7 03
                IN      AL, DX                  ; EC
                AND     AL, 3                   ; 24 03
                CMP     AL, 3                   ; 3C 03
                JZ      SHORT evg_dac_skip3     ; 74 04
                MOV     DX, 03C9H               ; BA C9 03
                OUT     DX, AL                  ; EE
evg_dac_skip3:                                  ; chunk:0x072E
                MOV     DX, 03C8H               ; BA C8 03
                MOV     AX, BX                  ; 8B C3
                OUT     DX, AL                  ; EE
                MOV     DX, 03C9H               ; BA C9 03
                CLI                             ; FA
evg_dac_loop:                                   ; chunk:0x0738
                LODSB                           ; AC
                OUT     DX, AL                  ; EE
                LOOP    SHORT evg_dac_loop      ; E2 FC
                STI                             ; FB
                POP     SI                      ; 5E
                POP     BP                      ; 5D
                RETF                            ; CB
evg_dac_palette_write ENDP

; ============================================================================
; evg_dac_palette_write_one -- single-entry wrapper around evg_dac_palette_write.
; chunk:0x0740..0x0756 (23 bytes).
;
; ABI:
;   [BP+6,7,8]  uchar[3]  rgb_triple (passed by value, 4-byte slot)
;   [BP+0A]     ushort    dac_index
; Stacks a count of 1, the dac_index, and a near pointer to the inline
; RGB then far-calls evg_dac_palette_write.
; ============================================================================
evg_dac_palette_write_one PROC FAR
                PUSH    BP                      ; 55
                MOV     BP, SP                  ; 8B EC
                PUSH    SI                      ; 56
                MOV     BX, [BP+0AH]            ; 8B 5E 0A
                NOSMART
                LEA     SI, [BP+6]              ; 8D 76 06
                SMART
                MOV     AX, 1                   ; B8 01 00
                PUSH    AX                      ; 50
                PUSH    BX                      ; 53
                PUSH    SI                      ; 56
                PUSH    CS                      ; 0E
                CALL    NEAR PTR evg_dac_palette_write ; E8 B1 FF
                POP     SI                      ; 5E
                POP     BP                      ; 5D
                RETF                            ; CB
evg_dac_palette_write_one ENDP

; ============================================================================
; evg_palette_load -- RES-archive palette load by palette ID.
; chunk:0x0757..0x07AE (88 bytes).
;
; Indirect via CS:[0x208] (asset open) and CS:[0x200] (asset read) host
; callbacks.  Caches the loaded buffer pointer at CS:[BX*2 + 0x6F1].
; ============================================================================
evg_palette_load PROC FAR
                PUSH    BP                      ; 55
                MOV     BP, SP                  ; 8B EC
                SUB     SP, 2                   ; 83 EC 02
                PUSH    SI                      ; 56
                PUSH    DI                      ; 57
                MOV     BX, [BP+8]              ; 8B 5E 08
                SHL     BX, 1                   ; D1 E3
                MOV     AX, [WORD PTR cs:BX+06F1H] ; 2E 8B 87 F1 06
                OR      AX, AX                  ; 0B C0
                JNZ     SHORT evg_pl_have       ; 75 10
                MOV     AX, 0300H               ; B8 00 03
                PUSH    AX                      ; 50
                CALL    [DWORD PTR cs:0208H]    ; 2E FF 1E 08 02
                ADD     SP, 2                   ; 83 C4 02
                OR      AX, AX                  ; 0B C0
                JZ      SHORT evg_pl_exit       ; 74 2B
evg_pl_have:                                    ; chunk:0x077D
                MOV     [BP-2], AX              ; 89 46 FE
                MOV     AX, [BP+6]              ; 8B 46 06
                PUSH    AX                      ; 50
                MOV     AX, 0300H               ; B8 00 03
                PUSH    AX                      ; 50
                MOV     AX, 1                   ; B8 01 00
                PUSH    AX                      ; 50
                MOV     AX, [BP-2]              ; 8B 46 FE
                PUSH    AX                      ; 50
                CALL    [DWORD PTR cs:0200H]    ; 2E FF 1E 00 02
                ADD     SP, 8                   ; 83 C4 08
                MOV     BX, [BP+8]              ; 8B 5E 08
                SHL     BX, 1                   ; D1 E3
                MOV     AX, [BP-2]              ; 8B 46 FE
                MOV     [WORD PTR cs:BX+06F1H], AX ; 2E 89 87 F1 06
                MOV     AX, [BP+8]              ; 8B 46 08
evg_pl_exit:                                    ; chunk:0x07A8
                POP     DI                      ; 5F
                POP     SI                      ; 5E
                ADD     SP, 2                   ; 83 C4 02
                POP     BP                      ; 5D
                RETF                            ; CB
evg_palette_load ENDP

; ============================================================================
; evg_palette_set -- activate a previously-loaded palette.
; chunk:0x07AF..0x07D9 (43 bytes).
; Looks up the per-id buffer pointer at CS:[BX*2 + 0x6F1], stashes it
; as the active-palette pointer at CS:[0x6F1], and bursts the 256-entry
; palette via evg_dac_palette_write(buf, 0, 256).
; ============================================================================
evg_palette_set PROC FAR
                PUSH    BP                      ; 55
                MOV     BP, SP                  ; 8B EC
                MOV     BX, [BP+6]              ; 8B 5E 06
                SHL     BX, 1                   ; D1 E3
                MOV     AX, [WORD PTR cs:BX+06F1H] ; 2E 8B 87 F1 06
                OR      AX, AX                  ; 0B C0
                JZ      SHORT evg_ps_exit       ; 74 18
                MOV     cs:[06F1H], AX          ; 2E A3 F1 06
                MOV     BX, AX                  ; 8B D8
                MOV     AX, 0100H               ; B8 00 01
                PUSH    AX                      ; 50
                XOR     AX, AX                  ; 33 C0
                PUSH    AX                      ; 50
                PUSH    BX                      ; 53
                PUSH    CS                      ; 0E
                CALL    NEAR PTR evg_dac_palette_write ; E8 33 FF
                ADD     SP, 6                   ; 83 C4 06
                MOV     AX, [BP+6]              ; 8B 46 06
evg_ps_exit:                                    ; chunk:0x07D8
                POP     BP                      ; 5D
                RETF                            ; CB
evg_palette_set ENDP

; ============================================================================
; evg_palette_blend_upload -- alpha-blended palette upload.
; chunk:0x07DA..0x084E (117 bytes).
;
; Linearly blends two palette banks (`from_index` and `to_index`) by
; the (alpha / 63) ratio in DL, allocating a 3*count RGB scratch buffer
; on the stack, computing each channel as `(from*alpha + to*(63-alpha))
; / 63`, and burst-uploading via evg_dac_palette_write.
; ============================================================================
evg_palette_blend_upload PROC FAR
                PUSH    BP                      ; 55
                MOV     BP, SP                  ; 8B EC
                PUSH    DS                      ; 1E
                PUSH    DI                      ; 57
                PUSH    SI                      ; 56
                MOV     CX, [BP+8]              ; 8B 4E 08
                MOV     DX, [BP+0CH]            ; 8B 56 0C
                MOV     DH, 3FH                 ; B6 3F
                MOV     AX, CX                  ; 8B C1
                SHL     CX, 1                   ; D1 E1
                ADD     CX, AX                  ; 03 C8   CX = count*3
                SUB     SP, CX                  ; 2B E1
                MOV     BX, SP                  ; 8B DC
                PUSH    CX                      ; 51
                PUSH    AX                      ; 50
                PUSH    [WORD PTR BP+6]         ; FF 76 06
                PUSH    BX                      ; 53
                MOV     SI, cs:[06F1H]          ; 2E 8B 36 F1 06
                MOV     AX, [BP+6]              ; 8B 46 06
                ADD     SI, AX                  ; 03 F0
                SHL     AX, 1                   ; D1 E0
                ADD     SI, AX                  ; 03 F0
                MOV     AX, [BP+0AH]            ; 8B 46 0A
                MOV     BP, cs:[06F1H]          ; 2E 8B 2E F1 06
                ADD     BP, AX                  ; 03 E8
                SHL     AX, 1                   ; D1 E0
                ADD     BP, AX                  ; 03 E8
                XOR     DI, DI                  ; 33 FF
evg_pbu_loop:                                   ; chunk:0x0816
                XOR     AH, AH                  ; 32 E4
                LODSB                           ; AC
                MUL     DL                      ; F6 E2
                DIV     DH                      ; F6 F6
                MOV     [BX], AL                ; 88 07
                MOV     AL, DL                  ; 8A C2
                MOV     DL, DH                  ; 8A D6
                SUB     DL, AL                  ; 2A D0
                XOR     AH, AH                  ; 32 E4
                MOV     AL, [BP+DI]             ; 8A 03
                MUL     DL                      ; F6 E2
                DIV     DH                      ; F6 F6
                ADD     [BX], AL                ; 00 07
                INC     BX                      ; 43
                MOV     AL, DL                  ; 8A C2
                MOV     DL, DH                  ; 8A D6
                SUB     DL, AL                  ; 2A D0
                INC     DI                      ; 47
                CMP     DI, 3                   ; 83 FF 03
                JNZ     SHORT evg_pbu_no_reset  ; 75 02
                XOR     DI, DI                  ; 33 FF
evg_pbu_no_reset:                               ; chunk:0x083E
                LOOP    SHORT evg_pbu_loop      ; E2 D6
                PUSH    CS                      ; 0E
                CALL    NEAR PTR evg_dac_palette_write ; E8 C1 FE
                ADD     SP, 6                   ; 83 C4 06
                POP     CX                      ; 59
                ADD     SP, CX                  ; 03 E1
                POP     SI                      ; 5E
                POP     DI                      ; 5F
                POP     DS                      ; 1F
                POP     BP                      ; 5D
                RETF                            ; CB
evg_palette_blend_upload ENDP

; ============================================================================
; evg_image_install -- compute aggregate size of an image-descriptor list.
; chunk:0x084F..0x0881 (51 bytes), vtable slot 13.
;
; ABI:
;   [BP+6]  ushort  desc_list_off  -- ptr to NULL-terminated descriptor
;                                     pointer list (each descriptor has
;                                     width@+6 / height@+8)
;   [BP+8]  ushort  out_zero_off   -- ptr to ushort that's written 0
;                                     (caller's "next free segment" reset)
; Returns DX:AX = total_pixels (running ADD/ADC into DX:BX, copied to
; DX:AX at exit -- the upper-32-bit DX is fall-through from final ADC).
; ============================================================================
evg_image_install PROC FAR
                PUSH    BP                      ; 55
                MOV     BP, SP                  ; 8B EC
                PUSH    SI                      ; 56
                PUSH    DI                      ; 57
                MOV     DI, [BP+6]              ; 8B 7E 06
                XOR     BX, BX                  ; 33 DB
                XOR     DX, DX                  ; 33 D2
evg_ii_loop:                                    ; chunk:0x085B
                MOV     SI, [DI]                ; 8B 35
                OR      SI, SI                  ; 0B F6
                JZ      SHORT evg_ii_done       ; 74 14
                PUSH    DX                      ; 52
                XOR     DX, DX                  ; 33 D2
                MOV     AX, [SI+6]              ; 8B 44 06
                MUL     WORD PTR [SI+8]         ; F7 64 08
                POP     DX                      ; 5A
                ADD     BX, AX                  ; 03 D8
                ADC     DX, 0                   ; 83 D2 00
                ADD     DI, 2                   ; 83 C7 02
                JMP     SHORT evg_ii_loop       ; EB E6
evg_ii_done:                                    ; chunk:0x0875
                MOV     AX, BX                  ; 8B C3
                MOV     SI, [BP+8]              ; 8B 76 08
                MOV     WORD PTR [SI], 0        ; C7 04 00 00
                POP     DI                      ; 5F
                POP     SI                      ; 5E
                POP     BP                      ; 5D
                RETF                            ; CB
evg_image_install ENDP

; ============================================================================
; evg_image_decode_a -- LZ-style runtime image installer (vtable slot 14).
; chunk:0x0882..0x097C (251 bytes).
;
; Walks a list of image descriptors, writes the chosen scratch segment
; into each descriptor's first word, then unpacks a nibble-packed
; payload backwards from the input cursor.  Output goes ES:DI->SI in
; a top-down sweep.  Mode-tier branches use chained SHL CL, 1 / RCR
; CX, 1 to manage carry-driven seg arithmetic.
; ============================================================================
evg_image_decode_a PROC FAR
                PUSH    BP                      ; 55
                MOV     BP, SP                  ; 8B EC
                PUSH    SI                      ; 56
                PUSH    DI                      ; 57
                PUSH    DS                      ; 1E
                MOV     DI, [BP+8]              ; 8B 7E 08
                MOV     ES, [BP+0AH]            ; 8E 46 0A
evg_ida_install:                                ; chunk:0x088E
                MOV     SI, [BP+6]              ; 8B 76 06
                MOV     SI, [SI]                ; 8B 34
                OR      SI, SI                  ; 0B F6
                JZ      SHORT evg_ida_unpack    ; 74 34
                MOV     DX, DI                  ; 8B D7
                MOV     AX, ES                  ; 8C C0
                MOV     CL, 4                   ; B1 04
                SHR     DX, CL                  ; D3 EA
                ADD     AX, DX                  ; 03 C2
                MOV     [SI], AX                ; 89 04
                MOV     DX, DI                  ; 8B D7
                AND     DX, 0FH                 ; 83 E2 0F
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
                JMP     SHORT evg_ida_install   ; EB C3
evg_ida_unpack:                                 ; chunk:0x08CB
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
                JNC     SHORT evg_ida_no_borrow ; 73 03
                SUB     AX, 1000H               ; 2D 00 10
evg_ida_no_borrow:                              ; chunk:0x08F5
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
                JNC     SHORT evg_ida_no_borrow2 ; 73 04
                SUB     DX, 1000H               ; 81 EA 00 10
evg_ida_no_borrow2:                             ; chunk:0x091C
                SHL     DX, 1                   ; D1 E2
                JNC     SHORT evg_ida_no_carry  ; 73 04
                ADD     BX, 1000H               ; 81 C3 00 10
evg_ida_no_carry:                               ; chunk:0x0924
                ADD     DI, DX                  ; 03 FA
                RCR     CX, 1                   ; D1 D9
                SHR     CX, 1                   ; D1 E9
                SHR     CX, 1                   ; D1 E9
                SHR     CX, 1                   ; D1 E9
                ADD     BX, CX                  ; 03 D9
                ADD     AX, BX                  ; 03 C3
                MOV     ES, AX                  ; 8E C0
evg_ida_unpack_loop:                            ; chunk:0x0934
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
                MOV     ES:[DI], AX             ; 26 89 05
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
                JNZ     SHORT evg_ida_unpack_loop ; 75 BC
                POP     DS                      ; 1F
                POP     DI                      ; 5F
                POP     SI                      ; 5E
                POP     BP                      ; 5D
                RETF                            ; CB
evg_image_decode_a ENDP

; ============================================================================
; evg_image_decode_b_nibbles -- per-nibble OR-blend into ES:DI.
; chunk:0x097D..0x09D0 (84 bytes), vtable slot 15.
;
; Reads CX bytes from DS:SI, expands each byte's two nibbles into AH:AL
; (high nibble shifted to AH<<4), ANDs with 0xF0F0 and ORs into ES:DI.
; ============================================================================
evg_image_decode_b_nibbles PROC FAR
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
evg_idb_loop:                                   ; chunk:0x0992
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
                OR      ES:[DI], AX             ; 26 09 05
                XOR     DX, DX                  ; 33 D2
                ADD     DI, 2                   ; 83 C7 02
                RCR     DX, 1                   ; D1 DA
                SHR     DX, 1                   ; D1 EA
                SHR     DX, 1                   ; D1 EA
                SHR     DX, 1                   ; D1 EA
                MOV     BX, ES                  ; 8C C3
                ADD     BX, DX                  ; 03 DA
                MOV     ES, BX                  ; 8E C3
                LOOP    SHORT evg_idb_loop      ; E2 C6
                POP     DS                      ; 1F
                POP     DI                      ; 5F
                POP     SI                      ; 5E
                POP     BP                      ; 5D
                RETF                            ; CB
evg_image_decode_b_nibbles ENDP

; ============================================================================
; evg_image_install_list -- iterate a list and call evg_image_install_planes
; chunk:0x09D1..0x09EC (28 bytes), vtable slot 16.
;
; ABI:
;   [BP+6]  ushort  list_off  -- pointer to a NULL-terminated word list
; Each non-zero word is pushed onto the stack and evg_image_install_planes
; is called as a NEAR call.
; ============================================================================
evg_image_install_list PROC FAR
                PUSH    BP                      ; 55
                MOV     BP, SP                  ; 8B EC
                PUSH    SI                      ; 56
                MOV     SI, [BP+6]              ; 8B 76 06
                OR      SI, SI                  ; 0B F6
                JZ      SHORT evg_iil_done      ; 74 10
evg_iil_loop:                                   ; chunk:0x09DC
                LODSW                           ; AD
                OR      AX, AX                  ; 0B C0
                JZ      SHORT evg_iil_done      ; 74 09
                PUSH    AX                      ; 50
                CALL    NEAR PTR evg_image_install_planes ; E8 08 00
                ADD     SP, 2                   ; 83 C4 02
                JMP     SHORT evg_iil_loop      ; EB F2
evg_iil_done:                                   ; chunk:0x09EA
                POP     SI                      ; 5E
                POP     BP                      ; 5D
                RETF                            ; CB
evg_image_install_list ENDP

; ============================================================================
; evg_image_install_planes -- DOS-alloc + plane-deinterleave decoder.
; chunk:0x09ED..0x0A74 (136 bytes).  PROC NEAR (called by install_list).
;
; Uses INT 21h AH=48h to allocate a paragraph-aligned block sized to
; cover width*height/16 paragraphs, deinterleaves the source into 4
; consecutive plane buffers via evg_plane_deinterleave_copy, then
; releases the block with INT 21h AH=49h.
; ============================================================================
evg_image_install_planes PROC NEAR
                PUSH    BP                      ; 55
                MOV     BP, SP                  ; 8B EC
                PUSH    DI                      ; 57
                PUSH    SI                      ; 56
                PUSH    DS                      ; 1E
                MOV     BP, [BP+4]              ; 8B 6E 04
                MOV     AX, [BP+6]              ; 8B 46 06
                XOR     DX, DX                  ; 33 D2
                MUL     WORD PTR [BP+8]         ; F7 66 08
                PUSH    AX                      ; 50
                ADD     AX, 0FH                 ; 05 0F 00
                SHR     AX, 1                   ; D1 E8
                SHR     AX, 1                   ; D1 E8
                SHR     AX, 1                   ; D1 E8
                SHR     AX, 1                   ; D1 E8
                MOV     BX, AX                  ; 8B D8
                MOV     CX, AX                  ; 8B C8
                ; DOS "Allocate Memory" API (INT 21h, AH=48h):
                ;   in:  BX = number of paragraphs (16-byte units)
                ;        wanted.
                ;   out: AX = paragraph (segment) of allocated block on
                ;            success, error code on failure.
                ;        BX = on failure, largest block available
                ;             (used here as the success indicator: if
                ;             BX == requested, allocation succeeded;
                ;             if BX != requested, DOS gave us only the
                ;             max-available count instead of memory).
                ;        CF = error indicator (not checked here -- the
                ;             code uses the BX != CX shortcut).
                ; See Ralf Brown's Interrupt List, INT 21h AH=48h.
                MOV     AH, 48H                 ; B4 48
                INT     21H                     ; CD 21
                CMP     BX, CX                  ; 3B D9
                POP     CX                      ; 59
                JNZ     evg_iip_done            ; 75 59   alloc failed -> bail
                MOV     DS, [BP+0]              ; 8E 5E 00
                MOV     SI, [BP+2]              ; 8B 76 02
                MOV     ES, AX                  ; 8E C0
                XOR     DI, DI                  ; 33 FF
                PUSH    SI                      ; 56
                PUSH    DI                      ; 57
                SHR     CX, 1                   ; D1 E9
                PUSH    CX                      ; 51
                JNC     SHORT evg_iip_no_movsb1 ; 73 01
                MOVSB                           ; A4
evg_iip_no_movsb1:                              ; chunk:0x0A29
                REP     MOVSW                   ; F3 A5
                POP     CX                      ; 59
                POP     DI                      ; 5F
                POP     SI                      ; 5E
                SHR     CX, 1                   ; D1 E9
                PUSH    DS                      ; 1E
                PUSH    SI                      ; 56
                PUSH    ES                      ; 06
                PUSH    DI                      ; 57
                PUSH    CX                      ; 51
                CALL    NEAR PTR evg_plane_deinterleave_copy ; E8 3D 00
                POP     CX                      ; 59
                ADD     SP, 8                   ; 83 C4 08
                ADD     SI, CX                  ; 03 F1
                INC     DI                      ; 47
                PUSH    DS                      ; 1E
                PUSH    SI                      ; 56
                PUSH    ES                      ; 06
                PUSH    DI                      ; 57
                PUSH    CX                      ; 51
                CALL    NEAR PTR evg_plane_deinterleave_copy ; E8 2E 00
                POP     CX                      ; 59
                ADD     SP, 8                   ; 83 C4 08
                ADD     SI, CX                  ; 03 F1
                INC     DI                      ; 47
                PUSH    DS                      ; 1E
                PUSH    SI                      ; 56
                PUSH    ES                      ; 06
                PUSH    DI                      ; 57
                PUSH    CX                      ; 51
                CALL    NEAR PTR evg_plane_deinterleave_copy ; E8 1F 00
                POP     CX                      ; 59
                ADD     SP, 8                   ; 83 C4 08
                ADD     SI, CX                  ; 03 F1
                INC     DI                      ; 47
                PUSH    DS                      ; 1E
                PUSH    SI                      ; 56
                PUSH    ES                      ; 06
                PUSH    DI                      ; 57
                PUSH    CX                      ; 51
                CALL    NEAR PTR evg_plane_deinterleave_copy ; E8 10 00
                POP     CX                      ; 59
                ADD     SP, 8                   ; 83 C4 08
                ADD     SI, CX                  ; 03 F1
                INC     DI                      ; 47
                ; DOS "Free Memory" API (INT 21h, AH=49h): ES = segment
                ; of the block to free.  ES still points at the
                ; block allocated above.
                MOV     AH, 49H                 ; B4 49
                INT     21H                     ; CD 21
evg_iip_done:                                   ; chunk:0x0A70
                POP     DS                      ; 1F
                POP     SI                      ; 5E
                POP     DI                      ; 5F
                POP     BP                      ; 5D
                RET                             ; C3
evg_image_install_planes ENDP

; ============================================================================
; evg_plane_deinterleave_copy -- copy every-4th byte from DS:SI to ES:DI.
; chunk:0x0A75..0x0A96 (34 bytes).  PROC NEAR.
;
; Picks every fourth byte from DS:SI and writes the run to ES:DI.
; Inner loop is `MOVSB` (1-byte copy + SI/DI auto-advance by 1) then
; `ADD SI, 3` -- a net stride of 4 over the source, stride 1 over the
; destination.  Used by evg_image_install_planes to demultiplex a
; planar source laid out as p0,p1,p2,p3,p0,p1,p2,p3,... into four
; consecutive plane buffers (one call per plane, with the caller's
; SI offset selecting which plane).
; ============================================================================
evg_plane_deinterleave_copy PROC NEAR
                PUSH    BP                      ; 55
                MOV     BP, SP                  ; 8B EC
                PUSH    SI                      ; 56
                PUSH    DI                      ; 57
                PUSH    DS                      ; 1E
                PUSH    ES                      ; 06
                MOV     CX, [BP+4]              ; 8B 4E 04
                MOV     SI, [BP+6]              ; 8B 76 06
                MOV     DS, [BP+8]              ; 8E 5E 08
                MOV     DI, [BP+0AH]            ; 8B 7E 0A
                MOV     ES, [BP+0CH]            ; 8E 46 0C
evg_pdc_loop:                                   ; chunk:0x0A8B
                MOVSB                           ; A4
                ADD     SI, 3                   ; 83 C6 03
                LOOP    SHORT evg_pdc_loop      ; E2 FA
                POP     ES                      ; 07
                POP     DS                      ; 1F
                POP     DI                      ; 5F
                POP     SI                      ; 5E
                POP     BP                      ; 5D
                RET                             ; C3
evg_plane_deinterleave_copy ENDP

; ============================================================================
; evg_grb_exit -- shared exit / early-exit epilogue for evg_glyph_row_blit.
; chunk:0x0A97..0x0A9C  (6 bytes)
;
; The glyph row-blit places its tear-down code immediately BEFORE its
; entry point so that the two `JS 0xA97` / `JA 0xA97` early-exits at
; the top of the function fall straight into the cleanup with a short
; (2-byte) backward jump.  The body's last instruction also drops into
; this block, so it doubles as the normal exit.
; ============================================================================
evg_grb_exit:                                   ; chunk:0x0A97
                POP     DS                      ; 1F
                POP     BP                      ; 5D
                POP     DI                      ; 5F
                POP     SI                      ; 5E
                POP     DX                      ; 5A
                RETF                            ; CB

; ============================================================================
; evg_glyph_row_blit -- planar glyph row blit using shift-out + plane fan.
; chunk:0x0A9D..0x0BBA (286 bytes), vtable slot 1.
;
; Register ABI (called via vtable slot 1):
;   AL  -- row index within glyph (clipped against DS:[0x5C] / DS:[0x70])
;   DX  -- destination column (in bytes)
;   BP  -- destination row * 4 (pre-shifted by caller)
;   ES:DI -- framebuffer cursor (typically A000:0000)
;   DS:SI -- source glyph row bytes
;
; Reads chunk-state globals:
;   DS:[0x5C]  row clip min
;   DS:[0x70]  row clip max
;   DS:[0x48]  glyph row height in 4-px units (loop count for body)
;   DS:[0x00]  bit pattern for current colour, low byte (CH)
;   DS:[0x01]  bit pattern for current colour, alt byte
;   DS:[0x02]  blit mode flag (0 -> use first half, !=0 -> skip to OR)
;   DS:[0x84]  font glyph segment (loaded into DS for the second half)
;
; Output: writes one row of glyph pixels into the Mode-X framebuffer
; (Sequencer Map-Mask is rewritten for each output byte, so this is
; classic per-byte plane-fan glyph rendering adapted to unchained-256).
; ============================================================================
evg_glyph_row_blit PROC FAR
                PUSH    DX                      ; 52
                PUSH    SI                      ; 56
                PUSH    DI                      ; 57
                PUSH    BP                      ; 55
                PUSH    DS                      ; 1E
                MOV     DS, cs:[0134H]          ; 2E 8E 1E 34 01
                MOV     AH, ds:[GfxContext.pFont_base_char]          ; 8A 26 5C 00
                SUB     AL, AH                  ; 2A C4
                JS      SHORT evg_grb_exit      ; 78 E8
                MOV     AH, ds:[GfxContext.pFont_glyph_count]          ; 8A 26 70 00
                CMP     AL, AH                  ; 3A C4
                JA      SHORT evg_grb_exit      ; 77 E0
                SHL     BP, 1                   ; D1 E5
                SHL     BP, 1                   ; D1 E5
                SHL     DX, 1                   ; D1 E2
                MOV     DI, ds:[BP+pRow_offset_lut]       ; 8B BE F2 06
                XOR     CX, CX                  ; 33 C9
                MOV     CL, ds:[GfxContext.pFont_height]          ; 8A 0E 48 00
                MOV     BP, CX                  ; 8B E9
                XOR     AH, AH                  ; 32 E4
                MUL     CL                      ; F6 E1
                MOV     SI, AX                  ; 8B F0
                MOV     BX, DX                  ; 8B DA
                MOV     DX, 03C4H               ; BA C4 03
                MOV     AL, 2                   ; B0 02
                OUT     DX, AL                  ; EE
                INC     DX                      ; 42
                MOV     AX, BX                  ; 8B C3
                SHR     AX, 1                   ; D1 E8
                SHR     AX, 1                   ; D1 E8
                ADD     DI, AX                  ; 03 F8
                MOV     CL, BL                  ; 8A CB
                AND     CL, 3                   ; 80 E1 03
                MOV     CH, ds:[GfxContext.bText_fg_color] ; 8A 2E 00 00
                CMP     BYTE PTR ds:[GfxContext.bText_style_flags], 0 ; 80 3E 02 00 00
                JNZ     SHORT evg_grb_phase2    ; 75 63
                PUSH    DI                      ; 57
                PUSH    BX                      ; 53
                PUSH    BP                      ; 55
                PUSH    CX                      ; 51
                MOV     CH, ds:[GfxContext.bText_bg_color] ; 8A 2E 01 00
evg_grb_phase1_loop:                            ; chunk:0x0AF9
                MOV     BH, 0FFH                ; B7 FF
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
                ADD     DI, 09DH                ; 81 C7 9D 00
                DEC     BP                      ; 4D
                JNZ     evg_grb_phase1_loop     ; 75 A9
                POP     CX                      ; 59
                POP     BP                      ; 5D
                POP     BX                      ; 5B
                POP     DI                      ; 5F
evg_grb_phase2:                                 ; chunk:0x0B54
                MOV     AX, ds:[0084H]          ; A1 84 00
                MOV     DS, AX                  ; 8E D8
evg_grb_phase2_loop:                            ; chunk:0x0B59
                MOV     BH, [SI]                ; 8A 3C
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
                ADD     DI, 09DH                ; 81 C7 9D 00
                DEC     BP                      ; 4D
                JNZ     evg_grb_phase2_loop     ; 75 A8
                POP     DS                      ; 1F
                POP     BP                      ; 5D
                POP     DI                      ; 5F
                POP     SI                      ; 5E
                POP     DX                      ; 5A
                RETF                            ; CB
evg_glyph_row_blit ENDP

; ============================================================================
; chunk:0x0BB7..0x0BBA -- per-call scratch globals for save_rect_dos_buffer.
;   0x0BB7  DOS-allocated paragraph (saved AX from INT 21h AH=48h)
;   0x0BB9  line counter (3-byte: low word + byte-fan tail)
; All zero on disk; overwritten on first call.
; ============================================================================
g_wEvgSaveRectAllocSeg  DW 0    ; 0x0BB7
g_wEvgSaveRectLineCount DW 0    ; 0x0BB9

; ============================================================================
; evg_save_rect_dos_buffer -- DOS-alloc-backed rect save (vtable slot 12).
; chunk:0x0BBB..0x0C76 (188 bytes).
;
; Saves a region of the framebuffer into a DOS-allocated paragraph
; (INT 21h AH=48h), then drives the host's CALLF [0x200] read-callback
; in 0x50-byte chunks to fill the buffer.  Uses CS:[0xBB7] to hold the
; buffer segment and CS:[0xBB9] for the per-call line counter.
; ============================================================================
evg_save_rect_dos_buffer PROC FAR
                PUSH    BP                      ; 55
                MOV     BP, SP                  ; 8B EC
                PUSH    SI                      ; 56
                PUSH    DI                      ; 57
                PUSH    DS                      ; 1E
                MOV     SI, [BP+8]              ; 8B 76 08
                MOV     DS, cs:[0134H]          ; 2E 8E 1E 34 01
                MOV     AL, [SI+34H]            ; 8A 44 34
                MOV     DL, AL                  ; 8A D0
                SHR     DL, 1                   ; D0 EA
                SHR     DL, 1                   ; D0 EA
                SHR     DL, 1                   ; D0 EA
                AND     AL, 7                   ; 24 07
                JZ      SHORT evg_srdb_no_inc1  ; 74 02
                INC     DL                      ; FE C2
evg_srdb_no_inc1:                               ; chunk:0x0BDA
                MOV     AL, [SI+48H]            ; 8A 44 48
                MUL     DL                      ; F6 E2
                MOV     DL, [SI+70H]            ; 8A 54 70
                MUL     DL                      ; F6 E2
                MOV     cs:[0BB9H], AX          ; 2E A3 B9 0B
                MOV     DX, AX                  ; 8B D0
                SHR     DX, 1                   ; D1 EA
                SHR     DX, 1                   ; D1 EA
                SHR     DX, 1                   ; D1 EA
                SHR     DX, 1                   ; D1 EA
                AND     AX, 0FH                 ; 25 0F 00
                JZ      SHORT evg_srdb_no_inc2  ; 74 01
                INC     DX                      ; 42
evg_srdb_no_inc2:                               ; chunk:0x0BF8
                XCHG    BX, DX                  ; 87 DA
                ; DOS Allocate Memory (BX = paragraphs; see the AH=48h
                ; block in evg_image_install_planes above for details).
                ; Here we check CF for failure rather than BX != CX.
                MOV     AH, 48H                 ; B4 48
                INT     21H                     ; CD 21
                JNC     SHORT evg_srdb_alloc_ok ; 73 05   CF=1 -> alloc failed
                XOR     AX, AX                  ; 33 C0
                JMP     SHORT evg_srdb_exit     ; EB 6E
                NOP                             ; 90
evg_srdb_alloc_ok:                              ; chunk:0x0C05
                SHL     SI, 1                   ; D1 E6
                MOV     [SI+84H], AX            ; 89 44 84
                SHR     SI, 1                   ; D1 EE
                PUSH    SI                      ; 56
                PUSH    SS                      ; 16
                POP     DS                      ; 1F
                MOV     cs:[0BB7H], AX          ; 2E A3 B7 0B
                XOR     DI, DI                  ; 33 FF
                MOV     AX, cs:[0BB9H]          ; 2E A1 B9 0B
                MOV     BL, 50H                 ; B3 50
                DIV     BL                      ; F6 F3
                MOV     cs:[0BB9H], AX          ; 2E A3 B9 0B
                MOV     AX, [BP+6]              ; 8B 46 06
                PUSH    AX                      ; 50
                MOV     AX, 1                   ; B8 01 00
                PUSH    AX                      ; 50
                MOV     AX, 50H                 ; B8 50 00
                PUSH    AX                      ; 50
                MOV     AX, [BP+0AH]            ; 8B 46 0A
                PUSH    AX                      ; 50
evg_srdb_outer:                                 ; chunk:0x0C32
                CALL    [DWORD PTR cs:0200H]    ; 2E FF 1E 00 02
                MOV     ES, cs:[0BB7H]          ; 2E 8E 06 B7 0B
                MOV     SI, [BP+0AH]            ; 8B 76 0A
                MOV     CX, 50H                 ; B9 50 00
                REP     MOVSB                   ; F3 A4
                DEC     BYTE PTR cs:[0BB9H]     ; 2E FE 0E B9 0B
                JZ      SHORT evg_srdb_tail     ; 74 02
                JMP     SHORT evg_srdb_outer    ; EB E5
evg_srdb_tail:                                  ; chunk:0x0C4D
                MOV     AL, cs:[0BBAH]          ; 2E A0 BA 0B
                XOR     AH, AH                  ; 32 E4
                ADD     SP, 4                   ; 83 C4 04
                PUSH    AX                      ; 50
                MOV     AX, [BP+0AH]            ; 8B 46 0A
                PUSH    AX                      ; 50
                CALL    [DWORD PTR cs:0200H]    ; 2E FF 1E 00 02
                ADD     SP, 2                   ; 83 C4 02
                POP     CX                      ; 59
                ADD     SP, 4                   ; 83 C4 04
                MOV     ES, cs:[0BB7H]          ; 2E 8E 06 B7 0B
                MOV     SI, [BP+0AH]            ; 8B 76 0A
                REP     MOVSB                   ; F3 A4
                POP     AX                      ; 58
evg_srdb_exit:                                  ; chunk:0x0C72
                POP     DS                      ; 1F
                POP     DI                      ; 5F
                POP     SI                      ; 5E
                POP     BP                      ; 5D
                RETF                            ; CB
evg_save_rect_dos_buffer ENDP

; ============================================================================
; evg_chunky_blit -- 2-pixel-per-byte chunky blit into Mode X (vtable slot 17).
; chunk:0x0C77..0x0D11 (155 bytes).
;
; Renders a chunky source (one 4-bit pixel per nibble, two pixels per
; source byte) into the unchained-256 framebuffer with 2x2 upscaling.
; The inner loop unpacks one source byte into CH (high nibble) and
; CL (low nibble) -- each 0..15 -- then:
;
;   - Map-Mask = 0x03 (planes 0+1), STOSB the high nibble byte to
;     ES:[DI] and ES:[DI + 0xA0] (row doubling).
;   - Map-Mask = 0x0C (planes 2+3), STOSB the low nibble byte to
;     ES:[DI] and ES:[DI + 0xA0].
;   - INC DI (next plane-byte offset).
;
; Net effect per source byte: 2 source pixels x (2 framebuffer pixels
; per logical pixel horizontally) x (2 rows vertically) = 8 frame-
; buffer pixels.  The colour byte written into the framebuffer is the
; 4-bit nibble value (0..15) -- so the 256-colour palette in use is
; expected to mirror a 16-colour palette in indices 0..15 (the upper
; 240 entries are typically unused or hold blend/fade variants).
; ============================================================================
evg_chunky_blit PROC FAR
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
                MOV     DS, cs:[0134H]          ; 2E 8E 1E 34 01
                CALL    evg_set_sequencer_bank  ; E8 86 10
                ADD     AX, [BP+10H]            ; 03 46 10
                MOV     DS, AX                  ; 8E D8
                MOV     DX, 03C4H               ; BA C4 03
                MOV     AL, 2                   ; B0 02
                OUT     DX, AL                  ; EE
                INC     DX                      ; 42
                MOV     BX, [BP+18H]            ; 8B 5E 18
                SHL     WORD PTR [BP+14H], 1    ; D1 66 14
evg_cb_row:                                     ; chunk:0x0CB2
                MOV     AX, [BP+14H]            ; 8B 46 14
                SHL     AX, 1                   ; D1 E0
                NOSMART
                LEA     DI, ds:[GfxContext.pRow_offset_lut]          ; 8D 3E F2 06
                SMART
                ADD     DI, AX                  ; 03 F8
                ADD     DI, cs:[0136H]          ; 2E 03 3E 36 01
                MOV     DI, [WORD PTR SS:DI]    ; 36 8B 3D
                ADD     DI, [BP+12H]            ; 03 7E 12
                MOV     CX, [BP+16H]            ; 8B 4E 16
                MOV     BH, CL                  ; 8A FD
evg_cb_inner:                                   ; chunk:0x0CCD
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
                MOV     AL, 3                   ; B0 03
                OUT     DX, AL                  ; EE
                MOV     ES:[DI], CH             ; 26 88 2D
                MOV     [BYTE PTR ES:DI+0A0H], CH ; 26 88 AD A0 00
                SHL     AL, 1                   ; D0 E0
                SHL     AL, 1                   ; D0 E0
                OUT     DX, AL                  ; EE
                MOV     ES:[DI], CL             ; 26 88 0D
                MOV     [BYTE PTR ES:DI+0A0H], CL ; 26 88 8D A0 00
                INC     DI                      ; 47
                DEC     BH                      ; FE CF
                JNZ     SHORT evg_cb_inner      ; 75 CE
                MOV     AX, [BP+14H]            ; 8B 46 14
                ADD     AX, 2                   ; 05 02 00
                MOV     [BP+14H], AX            ; 89 46 14
                DEC     BL                      ; FE CB
                JNZ     SHORT evg_cb_row        ; 75 A6
                POP     DI                      ; 5F
                POP     ES                      ; 07
                POP     SI                      ; 5E
                POP     DS                      ; 1F
                POP     BP                      ; 5D
                RETF                            ; CB
evg_chunky_blit ENDP

; ============================================================================
; evg_chunky_blit_doubled -- chunky blit with GC bit-mask preserve.
; chunk:0x0D12..0x0DCA (185 bytes), vtable slot 18.
;
; Sister of evg_chunky_blit: writes 2 source pixels per byte with 2x2
; row-doubling, but first sets GC reg 0x08 (Bit Mask) = 0xF0 so that
; each byte-write modifies only the high four bits of the destination
; byte, preserving the existing low four bits.  Effectively a "merge"
; blit at the byte level.  Restores GC 0x08 = 0xFF at function exit
; so subsequent blits aren't affected.
; ============================================================================
evg_chunky_blit_doubled PROC FAR
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
                MOV     DS, cs:[0134H]          ; 2E 8E 1E 34 01
                CALL    evg_set_sequencer_bank  ; E8 EB 0F
                ADD     AX, [BP+10H]            ; 03 46 10
                MOV     DS, AX                  ; 8E D8
                MOV     DX, 03CEH               ; BA CE 03
                MOV     AL, 8                   ; B0 08
                OUT     DX, AL                  ; EE
                INC     DX                      ; 42
                MOV     AL, 0F0H                ; B0 F0
                OUT     DX, AL                  ; EE
                MOV     DX, 03C4H               ; BA C4 03
                MOV     AL, 2                   ; B0 02
                OUT     DX, AL                  ; EE
                INC     DX                      ; 42
                MOV     BX, [BP+18H]            ; 8B 5E 18
                SHL     WORD PTR [BP+14H], 1    ; D1 66 14
evg_cbd_row:                                    ; chunk:0x0D57
                MOV     AX, [BP+14H]            ; 8B 46 14
                SHL     AX, 1                   ; D1 E0
                NOSMART
                LEA     DI, ds:[GfxContext.pRow_offset_lut]          ; 8D 3E F2 06
                SMART
                ADD     DI, AX                  ; 03 F8
                ADD     DI, cs:[0136H]          ; 2E 03 3E 36 01
                MOV     DI, [WORD PTR SS:DI]    ; 36 8B 3D
                ADD     DI, [BP+12H]            ; 03 7E 12
                MOV     CX, [BP+16H]            ; 8B 4E 16
                MOV     BH, CL                  ; 8A FD
evg_cbd_inner:                                  ; chunk:0x0D72
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
                MOV     AL, 3                   ; B0 03
                OUT     DX, AL                  ; EE
                MOV     AH, ES:[DI]             ; 26 8A 25
                MOV     ES:[DI], CH             ; 26 88 2D
                MOV     [BYTE PTR ES:DI+0A0H], CH ; 26 88 AD A0 00
                SHL     AL, 1                   ; D0 E0
                SHL     AL, 1                   ; D0 E0
                OUT     DX, AL                  ; EE
                MOV     AH, ES:[DI]             ; 26 8A 25
                MOV     ES:[DI], CL             ; 26 88 0D
                MOV     [BYTE PTR ES:DI+0A0H], CL ; 26 88 8D A0 00
                INC     DI                      ; 47
                DEC     BH                      ; FE CF
                JNZ     SHORT evg_cbd_inner     ; 75 C8
                MOV     AX, [BP+14H]            ; 8B 46 14
                ADD     AX, 2                   ; 05 02 00
                MOV     [BP+14H], AX            ; 89 46 14
                DEC     BL                      ; FE CB
                JZ      SHORT evg_cbd_restore   ; 74 02
                JMP     SHORT evg_cbd_row       ; EB 9E
evg_cbd_restore:                                ; chunk:0x0DB9
                MOV     DX, 03CFH               ; BA CF 03
                MOV     AL, 0FFH                ; B0 FF
                OUT     DX, AL                  ; EE
                POP     DI                      ; 5F
                POP     ES                      ; 07
                POP     SI                      ; 5E
                POP     DS                      ; 1F
                POP     BP                      ; 5D
                RETF                            ; CB
evg_chunky_blit_doubled ENDP

; ============================================================================
; chunk:0x0DC5..0x0DCA -- per-call scratch for evg_sprite_clip_plane_inner.
;
; On disk: 6 zero bytes (looks like inter-function padding between
; evg_chunky_blit_doubled @ 0x0D12 and evg_sprite_blit_noflip @ 0x0DCB).
; At runtime: writable mutable storage that evg_sprite_clip_plane_inner
; uses for three per-call WORD globals:
;   0x0DC5  WORD  src_stride        (sprite_w * sprite_h_rem / 4)
;   0x0DC7  WORD  clip_right_minus_dx
;   0x0DC9  WORD  start_x_mod_4     (low byte = mask; the high byte
;                                    at 0x0DCA is unused / always 0)
; See evg_sprite_clip_plane_inner's body comments for the use sites.
; ============================================================================
                DB      6 DUP (0)

; ============================================================================
; evg_sprite_blit_noflip -- vtable slot 3, thin wrapper for blit master.
; chunk:0x0DCB..0x0DE2 (24 bytes).
;
; Stacks (0, dy, dx, sprite_ptr_offset) and far-calls the master sprite
; blit at 0x10DA.  The trailing 0 selects flags=0 (no flip).
; ============================================================================
evg_sprite_blit_noflip PROC FAR
                PUSH    BP                      ; 55
                MOV     BP, SP                  ; 8B EC
                XOR     AX, AX                  ; 33 C0
                PUSH    AX                      ; 50
                PUSH    [WORD PTR BP+0AH]       ; FF 76 0A
                PUSH    [WORD PTR BP+8]         ; FF 76 08
                PUSH    [WORD PTR BP+6]         ; FF 76 06
                PUSH    CS                      ; 0E
                CALL    NEAR PTR evg_sprite_blit_master ; E8 FC 02
                ADD     SP, 8                   ; 83 C4 08
                POP     BP                      ; 5D
                RETF                            ; CB
evg_sprite_blit_noflip ENDP

; ============================================================================
; evg_sprite_clip_plane_inner -- clipped per-plane sprite blit core.
; chunk:0x0DE3..0x10DA-1 (759 bytes).
;
; Heart of the sprite-rendering path.  Computes clipping rectangle
; against globals DS:[0x3..0xB], rotates through the 4 Mode-X planes
; (programmed via Sequencer Map-Mask reg 0x02 -- standard VGA
; register, not a V7 extension) via ROL CH (mask 0xF0) and writes
; one plane per iteration with the transparent-pixel skip
; (LODSB / OR AL,AL / JZ skip / STOSB).  Each plane-pass iterates
; over every byte in the destination scanline; pixels not owned by
; the current plane are left as-is via the OR-AL-AL skip.
;
; CS:[0xDC5..0xDC9] are per-call scratch:
;   0x0DC5  src_stride (sprite_w * sprite_h_remaining / 4)
;   0x0DC7  saved clip-rect.right - dst_x
;   0x0DC9  start_x mod 4 (computed in evg_sblit_compute_left)
;
; The function is one big linear pass; four near-identical copies of
; the plane inner-loop are inlined (planes 0,1,2,3) because each
; iteration also includes a per-plane PUSH/POP shuffle and a special-
; case branch that's expensive to factor out.
; ============================================================================
evg_sprite_clip_plane_inner PROC FAR
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
                SHL     WORD PTR [BP+8], 1      ; D1 66 08
                SHL     WORD PTR [BP+0AH], 1    ; D1 66 0A
                MOV     DS, cs:[0134H]          ; 2E 8E 1E 34 01
                SHL     WORD PTR ds:[0007H], 1  ; D1 26 07 00
                SHL     WORD PTR ds:[0009H], 1  ; D1 26 09 00
                SHL     WORD PTR ds:[0003H], 1  ; D1 26 03 00
                SHL     WORD PTR ds:[0005H], 1  ; D1 26 05 00
                CALL    evg_set_sequencer_bank  ; E8 0A 0F
                MOV     WORD PTR cs:[0DC7H], 0  ; 2E C7 06 C7 0D 00 00
                MOV     SI, [BP-8]              ; 8B 76 F8
                MOV     DI, [BP+0AH]            ; 8B 7E 0A
                SHL     DI, 1                   ; D1 E7
                MOV     DI, [WORD PTR DI+pRow_offset_lut] ; 8B BD F2 06
                MOV     AX, [BP+8]              ; 8B 46 08
                MOV     cs:[0DC9H], AX          ; 2E A3 C9 0D
                OR      AX, AX                  ; 0B C0
                JLE     SHORT evg_scpi_skip_xshift ; 7E 06
                SHR     AX, 1                   ; D1 E8
                SHR     AX, 1                   ; D1 E8
                ADD     DI, AX                  ; 03 F8
evg_scpi_skip_xshift:                           ; chunk:0x0E40
                MOV     DH, [BP-4]              ; 8A 76 FC
                MOV     DL, [BP-2]              ; 8A 56 FE
                XOR     BX, BX                  ; 33 DB
                MOV     AL, ds:[000BH]          ; A0 0B 00
                OR      AL, AL                  ; 0A C0
                JNZ     SHORT evg_scpi_clip     ; 75 03
                JMP     evg_scpi_main_dispatch  ; E9 AF 00
evg_scpi_clip:                                  ; chunk:0x0E52
                MOV     AX, ds:[0005H]          ; A1 05 00
                SUB     AX, [BP+8]              ; 2B 46 08
                MOV     CL, DH                  ; 8A CE
                XOR     CH, CH                  ; 32 ED
                SUB     AX, CX                  ; 2B C1
                JNS     SHORT evg_scpi_clip_y   ; 79 0E
                NEG     AX                      ; F7 D8
                MOV     BX, AX                  ; 8B D8
                SUB     DH, AL                  ; 2A F0
                SUB     AL, [BP-4]              ; 2A 46 FC
                JC      SHORT evg_scpi_clip_y   ; 72 03
                JMP     evg_scpi_done           ; E9 36 02
evg_scpi_clip_y:                                ; chunk:0x0E6E
                MOV     AX, ds:[0009H]          ; A1 09 00
                SUB     AX, [BP+0AH]            ; 2B 46 0A
                MOV     CL, DL                  ; 8A CA
                XOR     CH, CH                  ; 32 ED
                SUB     AX, CX                  ; 2B C1
                JNS     SHORT evg_scpi_clip_top ; 79 0A
                NEG     AX                      ; F7 D8
                DEC     AX                      ; 48
                SUB     DL, AL                  ; 2A D0
                JA      SHORT evg_scpi_clip_top ; 77 03
                JMP     evg_scpi_done           ; E9 1E 02
evg_scpi_clip_top:                              ; chunk:0x0E86
                MOV     AX, ds:[0007H]          ; A1 07 00
                SUB     AX, [BP+0AH]            ; 2B 46 0A
                JLE     SHORT evg_scpi_clip_left ; 7E 2F
                DEC     AX                      ; 48
                SUB     DL, AL                  ; 2A D0
                MUL     BYTE PTR [BP-4]         ; F6 66 FC
                SHR     AX, 1                   ; D1 E8
                SHR     AX, 1                   ; D1 E8
                ADD     SI, AX                  ; 03 F0
                MOV     DI, ds:[0007H]          ; 8B 3E 07 00
                SHL     DI, 1                   ; D1 E7
                MOV     DI, [WORD PTR DI+pRow_offset_lut] ; 8B BD F2 06
                MOV     AX, [BP+8]              ; 8B 46 08
                OR      AX, AX                  ; 0B C0
                JLE     SHORT evg_scpi_no_xadj  ; 7E 06
                SHR     AX, 1                   ; D1 E8
                SHR     AX, 1                   ; D1 E8
                ADD     DI, AX                  ; 03 F8
evg_scpi_no_xadj:                               ; chunk:0x0EB1
                OR      DL, DL                  ; 0A D2
                JNZ     SHORT evg_scpi_chk_top  ; 75 03
                JMP     evg_scpi_done           ; E9 EC 01
evg_scpi_chk_top:                               ; chunk:0x0EB8
                JNS     SHORT evg_scpi_clip_left ; 79 03
                JMP     evg_scpi_done           ; E9 E7 01
evg_scpi_clip_left:                             ; chunk:0x0EBD
                MOV     AX, ds:[0003H]          ; A1 03 00
                SUB     AX, [BP+8]              ; 2B 46 08
                JLE     SHORT evg_scpi_main_dispatch ; 7E 3C
                DEC     AX                      ; 48
                PUSH    AX                      ; 50
                SUB     AL, [BP-4]              ; 2A 46 FC
                POP     AX                      ; 58
                JC      SHORT evg_scpi_clip_inner ; 72 03
                JMP     evg_scpi_done           ; E9 D4 01
evg_scpi_clip_inner:                            ; chunk:0x0ED0
                SUB     DH, AL                  ; 2A F0
                MOV     BX, [BP+8]              ; 8B 5E 08
                AND     BX, 3                   ; 83 E3 03
                MOV     BX, AX                  ; 8B D8
                MOV     cs:[0DC7H], AX          ; 2E A3 C7 0D
                SHR     AX, 1                   ; D1 E8
                SHR     AX, 1                   ; D1 E8
                ADD     SI, AX                  ; 03 F0
                TEST    BX, 3                   ; F7 C3 03 00
                JZ      SHORT evg_scpi_no_si_inc ; 74 01
                INC     SI                      ; 46
evg_scpi_no_si_inc:                             ; chunk:0x0EEB
                MOV     AX, ds:[0003H]          ; A1 03 00
                MOV     cs:[0DC9H], AX          ; 2E A3 C9 0D
                MOV     DI, [BP+0AH]            ; 8B 7E 0A
                SHL     DI, 1                   ; D1 E7
                MOV     DI, [WORD PTR DI+pRow_offset_lut] ; 8B BD F2 06
                SHR     AX, 1                   ; D1 E8
                SHR     AX, 1                   ; D1 E8
                ADD     DI, AX                  ; 03 F8
evg_scpi_main_dispatch:                         ; chunk:0x0F01
                MOV     AX, [BP-0AH]            ; 8B 46 F6
                MOV     DS, AX                  ; 8E D8
                MOV     AL, [BP-4]              ; 8A 46 FC
                XOR     AH, AH                  ; 32 E4
                MUL     BYTE PTR [BP-2]         ; F6 66 FE
                SHR     AX, 1                   ; D1 E8
                SHR     AX, 1                   ; D1 E8
                MOV     cs:[0DC5H], AX          ; 2E A3 C5 0D
                PUSH    DX                      ; 52
                MOV     CL, BYTE PTR cs:[0DC9H] ; 2E 8A 0E C9 0D
                AND     CL, 3                   ; 80 E1 03
                MOV     DX, 03C4H               ; BA C4 03
                MOV     AL, 2                   ; B0 02
                MOV     AH, 1                   ; B4 01
                SHL     AH, CL                  ; D2 E4
                OUT     DX, AX                  ; EF
                POP     DX                      ; 5A
                MOV     CL, DH                  ; 8A CE
                AND     CL, 3                   ; 80 E1 03
                JNZ     SHORT evg_scpi_cl_ok    ; 75 02
                MOV     CL, 4                   ; B1 04
evg_scpi_cl_ok:                                 ; chunk:0x0F33
                MOV     CH, 0F0H                ; B5 F0
                ROL     CH, CL                  ; D2 C5
                ADD     DH, 3                   ; 80 C6 03
                SHR     DH, 1                   ; D0 EE
                SHR     DH, 1                   ; D0 EE
                SHR     BX, 1                   ; D1 EB
                SHR     BX, 1                   ; D1 EB
                MOV     BP, cs:[0DC7H]          ; 2E 8B 2E C7 0D
                AND     BP, 3                   ; 83 E5 03
                JZ      SHORT evg_scpi_plane0   ; 74 0C
                PUSH    CX                      ; 51
                MOV     CX, BP                  ; 8B CD
evg_scpi_si_adv:                                ; chunk:0x0F4F
                ADD     SI, cs:[0DC5H]          ; 2E 03 36 C5 0D
                LOOP    SHORT evg_scpi_si_adv   ; E2 F9
                DEC     SI                      ; 4E
                POP     CX                      ; 59
evg_scpi_plane0:                                ; chunk:0x0F58
                DEC     DH                      ; FE CE
                INC     BX                      ; 43
                PUSH    BX                      ; 53
                PUSH    DX                      ; 52
                PUSH    DI                      ; 57
                PUSH    SI                      ; 56
                XCHG    AL, AH                  ; 86 C4
                SHR     CH, 1                   ; D0 ED
                LAHF                            ; 9F
                SBB     BX, 0                   ; 83 DB 00
                SAHF                            ; 9E
                ADC     DH, 0                   ; 80 D6 00
                XCHG    AL, AH                  ; 86 C4
evg_scpi_p0_row:                                ; chunk:0x0F6D
                MOV     CL, DH                  ; 8A CE
                PUSH    DI                      ; 57
evg_scpi_p0_inner:                              ; chunk:0x0F70
                LODSB                           ; AC
                OR      AL, AL                  ; 0A C0
                JZ      SHORT evg_scpi_p0_skip  ; 74 02
                STOSB                           ; AA
                DEC     DI                      ; 4F
evg_scpi_p0_skip:                               ; chunk:0x0F77
                INC     DI                      ; 47
                DEC     CL                      ; FE C9
                JNZ     SHORT evg_scpi_p0_inner ; 75 F4
                ADD     SI, BX                  ; 03 F3
                POP     DI                      ; 5F
                ADD     DI, 0A0H                ; 81 C7 A0 00
                DEC     DL                      ; FE CA
                JNZ     SHORT evg_scpi_p0_row   ; 75 E6
                POP     SI                      ; 5E
                INC     BP                      ; 45
                CMP     BP, 4                   ; 83 FD 04
                JNZ     SHORT evg_scpi_p1_skip_reset ; 75 0F
                XOR     BP, BP                  ; 33 ED
                PUSH    AX                      ; 50
                MOV     AX, cs:[0DC5H]          ; 2E A1 C5 0D
                SHL     AX, 1                   ; D1 E0
                SHL     AX, 1                   ; D1 E0
                SUB     SI, AX                  ; 2B F0
                POP     AX                      ; 58
                INC     SI                      ; 46
evg_scpi_p1_skip_reset:                         ; chunk:0x0F9D
                ADD     SI, cs:[0DC5H]          ; 2E 03 36 C5 0D
                POP     DI                      ; 5F
                SHL     AH, 1                   ; D0 E4
                CMP     AH, 10H                 ; 80 FC 10
                JNZ     SHORT evg_scpi_p1_ah_ok ; 75 03
                INC     DI                      ; 47
                MOV     AH, 1                   ; B4 01
evg_scpi_p1_ah_ok:                              ; chunk:0x0FAD
                MOV     AL, AH                  ; 8A C4
                MOV     DX, 03C5H               ; BA C5 03
                OUT     DX, AL                  ; EE
                POP     DX                      ; 5A
                POP     BX                      ; 5B
                PUSH    BX                      ; 53
                PUSH    DX                      ; 52
                PUSH    DI                      ; 57
                PUSH    SI                      ; 56
                XCHG    AL, AH                  ; 86 C4
                SHR     CH, 1                   ; D0 ED
                LAHF                            ; 9F
                SBB     BX, 0                   ; 83 DB 00
                SAHF                            ; 9E
                ADC     DH, 0                   ; 80 D6 00
                XCHG    AL, AH                  ; 86 C4
                JNZ     SHORT evg_scpi_p1_body  ; 75 03
                JMP     evg_scpi_postplane      ; E9 D5 00
evg_scpi_p1_body:                               ; chunk:0x0FCC
                MOV     CL, DH                  ; 8A CE
                PUSH    DI                      ; 57
evg_scpi_p1_inner:                              ; chunk:0x0FCF
                LODSB                           ; AC
                OR      AL, AL                  ; 0A C0
                JZ      SHORT evg_scpi_p1_skip  ; 74 02
                STOSB                           ; AA
                DEC     DI                      ; 4F
evg_scpi_p1_skip:                               ; chunk:0x0FD6
                INC     DI                      ; 47
                DEC     CL                      ; FE C9
                JNZ     SHORT evg_scpi_p1_inner ; 75 F4
                ADD     SI, BX                  ; 03 F3
                POP     DI                      ; 5F
                ADD     DI, 0A0H                ; 81 C7 A0 00
                DEC     DL                      ; FE CA
                JNZ     SHORT evg_scpi_p1_body  ; 75 E6
                POP     SI                      ; 5E
                INC     BP                      ; 45
                CMP     BP, 4                   ; 83 FD 04
                JNZ     SHORT evg_scpi_p2_skip_reset ; 75 0F
                XOR     BP, BP                  ; 33 ED
                PUSH    AX                      ; 50
                MOV     AX, cs:[0DC5H]          ; 2E A1 C5 0D
                SHL     AX, 1                   ; D1 E0
                SHL     AX, 1                   ; D1 E0
                SUB     SI, AX                  ; 2B F0
                POP     AX                      ; 58
                INC     SI                      ; 46
evg_scpi_p2_skip_reset:                         ; chunk:0x0FFC
                ADD     SI, cs:[0DC5H]          ; 2E 03 36 C5 0D
                POP     DI                      ; 5F
                SHL     AH, 1                   ; D0 E4
                CMP     AH, 10H                 ; 80 FC 10
                JNZ     SHORT evg_scpi_p2_ah_ok ; 75 03
                INC     DI                      ; 47
                MOV     AH, 1                   ; B4 01
evg_scpi_p2_ah_ok:                              ; chunk:0x100C
                MOV     AL, AH                  ; 8A C4
                MOV     DX, 03C5H               ; BA C5 03
                OUT     DX, AL                  ; EE
                POP     DX                      ; 5A
                POP     BX                      ; 5B
                PUSH    BX                      ; 53
                PUSH    DX                      ; 52
                PUSH    DI                      ; 57
                PUSH    SI                      ; 56
                XCHG    AL, AH                  ; 86 C4
                SHR     CH, 1                   ; D0 ED
                LAHF                            ; 9F
                SBB     BX, 0                   ; 83 DB 00
                SAHF                            ; 9E
                ADC     DH, 0                   ; 80 D6 00
                XCHG    AL, AH                  ; 86 C4
                JNZ     SHORT evg_scpi_p2_body  ; 75 03
                JMP     SHORT evg_scpi_postplane ; EB 77
                NOP                             ; 90    alignment filler
evg_scpi_p2_body:                               ; chunk:0x102B
                MOV     CL, DH                  ; 8A CE
                PUSH    DI                      ; 57
evg_scpi_p2_inner:                              ; chunk:0x102E
                LODSB                           ; AC
                OR      AL, AL                  ; 0A C0
                JZ      SHORT evg_scpi_p2_skip  ; 74 02
                STOSB                           ; AA
                DEC     DI                      ; 4F
evg_scpi_p2_skip:                               ; chunk:0x1035
                INC     DI                      ; 47
                DEC     CL                      ; FE C9
                JNZ     SHORT evg_scpi_p2_inner ; 75 F4
                ADD     SI, BX                  ; 03 F3
                POP     DI                      ; 5F
                ADD     DI, 0A0H                ; 81 C7 A0 00
                DEC     DL                      ; FE CA
                JNZ     SHORT evg_scpi_p2_body  ; 75 E6
                POP     SI                      ; 5E
                INC     BP                      ; 45
                CMP     BP, 4                   ; 83 FD 04
                JNZ     SHORT evg_scpi_p3_skip_reset ; 75 0F
                XOR     BP, BP                  ; 33 ED
                PUSH    AX                      ; 50
                MOV     AX, cs:[0DC5H]          ; 2E A1 C5 0D
                SHL     AX, 1                   ; D1 E0
                SHL     AX, 1                   ; D1 E0
                SUB     SI, AX                  ; 2B F0
                POP     AX                      ; 58
                INC     SI                      ; 46
evg_scpi_p3_skip_reset:                         ; chunk:0x105B
                ADD     SI, cs:[0DC5H]          ; 2E 03 36 C5 0D
                POP     DI                      ; 5F
                SHL     AH, 1                   ; D0 E4
                CMP     AH, 10H                 ; 80 FC 10
                JNZ     SHORT evg_scpi_p3_ah_ok ; 75 03
                INC     DI                      ; 47
                MOV     AH, 1                   ; B4 01
evg_scpi_p3_ah_ok:                              ; chunk:0x106B
                MOV     AL, AH                  ; 8A C4
                MOV     DX, 03C5H               ; BA C5 03
                OUT     DX, AL                  ; EE
                POP     DX                      ; 5A
                POP     BX                      ; 5B
                PUSH    BX                      ; 53
                PUSH    DX                      ; 52
                PUSH    DI                      ; 57
                PUSH    SI                      ; 56
                XCHG    AL, AH                  ; 86 C4
                SHR     CH, 1                   ; D0 ED
                LAHF                            ; 9F
                SBB     BX, 0                   ; 83 DB 00
                SAHF                            ; 9E
                ADC     DH, 0                   ; 80 D6 00
                XCHG    AL, AH                  ; 86 C4
                JZ      SHORT evg_scpi_postplane ; 74 1A
evg_scpi_p3_body_loop:                          ; chunk:0x1087
                MOV     CL, DH                  ; 8A CE
                PUSH    DI                      ; 57
evg_scpi_p3_inner:                              ; chunk:0x108A
                LODSB                           ; AC
                OR      AL, AL                  ; 0A C0
                JZ      SHORT evg_scpi_p3_skip  ; 74 02
                STOSB                           ; AA
                DEC     DI                      ; 4F
evg_scpi_p3_skip:                               ; chunk:0x1091
                INC     DI                      ; 47
                DEC     CL                      ; FE C9
                JNZ     SHORT evg_scpi_p3_inner ; 75 F4
                ADD     SI, BX                  ; 03 F3
                POP     DI                      ; 5F
                ADD     DI, 0A0H                ; 81 C7 A0 00
                DEC     DL                      ; FE CA
                JNZ     SHORT evg_scpi_p3_body_loop ; 75 E6
evg_scpi_postplane:                             ; chunk:0x10A1
                ADD     SP, 8                   ; 83 C4 08
evg_scpi_done:                                  ; chunk:0x10A4
                MOV     DS, cs:[0134H]          ; 2E 8E 1E 34 01
                SHR     WORD PTR ds:[0003H], 1  ; D1 2E 03 00
                SHR     WORD PTR ds:[0005H], 1  ; D1 2E 05 00
                SHR     WORD PTR ds:[0007H], 1  ; D1 2E 07 00
                SHR     WORD PTR ds:[0009H], 1  ; D1 2E 09 00
                POP     DS                      ; 1F
                POP     ES                      ; 07
                POP     SI                      ; 5E
                POP     DI                      ; 5F
                ADD     SP, 0AH                 ; 83 C4 0A
                POP     BP                      ; 5D
                RETF                            ; CB
evg_sprite_clip_plane_inner ENDP

; ============================================================================
; chunk:0x10C2..0x10D1 -- sprite blit state struct (SOA).
;   0x10C2  saved_bx (current left edge after clipping, in pixels)
;   0x10C4  src_stride (src_w/4 * src_h, doubled)
;   0x10C6  saved_si (current source cursor)
;   0x10C8  current_plane (0..3 -- rotated each iteration)
;   0x10CA  plane_shift (current plane mask shift in bits)
;   0x10CC  rows_remaining_after_clip
;   0x10CE  saved_src_w
;   0x10D0  current_dst_cursor (DI)
; ============================================================================
g_wEvgSpriteState_BX        DW 0    ; 0x10C2
g_wEvgSpriteState_Stride    DW 0    ; 0x10C4
g_wEvgSpriteState_SI        DW 0    ; 0x10C6
g_wEvgSpriteState_Plane     DW 0    ; 0x10C8
g_wEvgSpriteState_Shift     DW 0    ; 0x10CA
g_wEvgSpriteState_Rows      DW 0    ; 0x10CC
g_wEvgSpriteState_SrcW      DW 0    ; 0x10CE
g_wEvgSpriteState_DI        DW 0    ; 0x10D0

; ============================================================================
; g_apEvgSpriteFlipDispatch -- 4-entry near-pointer dispatch table.
; chunk:0x10D2..0x10D9
;
; Indexed by (flags & 3) * 2 in evg_sprite_blit_master at 0x124E:
;   flags=0 -> evg_sprite_blit_flip_variant_a @ 0x12F1 (no flip)
;   flags=1 -> evg_sprite_blit_flip_variant_b @ 0x1555 (h-flip)
;   flags=2 -> evg_sprite_blit_flip_variant_c @ 0x17CD (v-flip)
;   flags=3 -> evg_sprite_blit_flip_variant_d @ 0x1A64 (vh-flip)
; ============================================================================
g_apEvgSpriteFlipDispatch:
                DW      evg_sprite_blit_flip_variant_a  ; flags=0  (=0x12F1)
                DW      evg_sprite_blit_flip_variant_b  ; flags=1  (=0x1555)
                DW      evg_sprite_blit_flip_variant_c  ; flags=2  (=0x17CD)
                DW      evg_sprite_blit_flip_variant_d  ; flags=3  (=0x1A64)

; ============================================================================
; evg_sprite_blit_master -- master dispatcher for clipped flip sprites.
; chunk:0x10DA..0x12F0 (535 bytes).
;
; ABI (__cdecl16far):
;   [BP+6]    sprite_desc_off  (DS:[BP+6] points to 10-byte descriptor)
;   [BP+8]    dst_x_doubled
;   [BP+0A]   dst_y
;   [BP+0C]   flags (bit0 = h-flip, bit1 = v-flip)
;
; Snapshots the 10-byte sprite descriptor into BP-local scratch, clips
; against globals DS:[0x3,5,7,9] (l,r,t,b) shifted by 1 (everything's
; in 2-pixel units), then performs the flip-variant tail-jump via the
; near table at 0x10D2.  Two distinct JMP AX instructions live at
; 0x12CC and 0x12EF; the targets for both are the 4 entries of
; g_apEvgSpriteFlipDispatch.
;
; The two tails differ only in whether the post-plane SI advance is
; INC AX (0x12C2) or DEC AX (0x12E5) -- i.e. plane-stepping direction.
; ============================================================================
evg_sprite_blit_master PROC FAR
                PUSH    BP                      ; 55
                MOV     BP, SP                  ; 8B EC
                SUB     SP, 0AH                 ; 83 EC 0A
                PUSH    DI                      ; 57
                PUSH    SI                      ; 56
                PUSH    ES                      ; 06
                PUSH    DS                      ; 1E
                SHR     WORD PTR [BP+8], 1      ; D1 6E 08
                MOV     SI, [BP+6]              ; 8B 76 06
                MOV     DI, BP                  ; 8B FD
                SUB     DI, 0AH                 ; 83 EF 0A
                MOV     AX, SS                  ; 8C D0
                MOV     ES, AX                  ; 8E C0
                MOV     CX, 5                   ; B9 05 00
                REP     MOVSW                   ; F3 A5
                MOV     AX, [BP-4]              ; 8B 46 FC
                MOV     cs:[10CEH], AX          ; 2E A3 CE 10
                SHR     AX, 1                   ; D1 E8
                SHR     AX, 1                   ; D1 E8
                MOV     [BP-4], AX              ; 89 46 FC
                XOR     DX, DX                  ; 33 D2
                MUL     WORD PTR [BP-2]         ; F7 66 FE
                MOV     cs:[10C4H], AX          ; 2E A3 C4 10
                MOV     DS, cs:[0134H]          ; 2E 8E 1E 34 01
                CALL    evg_set_sequencer_bank  ; E8 0F 0C
                XOR     SI, SI                  ; 33 F6
                TEST    BYTE PTR [BP+0CH], 2    ; F6 46 0C 02
                JZ      SHORT evg_sbm_test_hf   ; 74 07
                MOV     SI, [BP-4]              ; 8B 76 FC
                SHL     SI, 1                   ; D1 E6
                SHL     SI, 1                   ; D1 E6
evg_sbm_test_hf:                                ; chunk:0x1126
                TEST    BYTE PTR [BP+0CH], 1    ; F6 46 0C 01
                JZ      SHORT evg_sbm_no_hf     ; 74 0F
                MOV     AX, cs:[10C4H]          ; 2E A1 C4 10
                SHL     AX, 1                   ; D1 E0
                SHL     AX, 1                   ; D1 E0
                SUB     AX, cs:[10CEH]          ; 2E 2B 06 CE 10
                ADD     SI, AX                  ; 03 F0
evg_sbm_no_hf:                                  ; chunk:0x113B
                MOV     DI, [BP+0AH]            ; 8B 7E 0A
                SHL     DI, 1                   ; D1 E7
                MOV     DI, [WORD PTR DI+pRow_offset_lut] ; 8B BD F2 06
                SHL     DI, 1                   ; D1 E7
                ADD     DI, [BP+8]              ; 03 7E 08
                MOV     DX, [BP-4]              ; 8B 56 FC
                SHL     DX, 1                   ; D1 E2
                SHL     DX, 1                   ; D1 E2
                MOV     AX, [BP-2]              ; 8B 46 FE
                MOV     cs:[10CCH], AX          ; 2E A3 CC 10
                MOV     AL, ds:[000BH]          ; A0 0B 00
                XOR     BX, BX                  ; 33 DB
                OR      AL, AL                  ; 0A C0
                JNZ     SHORT evg_sbm_clip      ; 75 03
                JMP     evg_sbm_clip_done       ; E9 AF 00
evg_sbm_clip:                                   ; chunk:0x1163
                MOV     AX, ds:[0005H]          ; A1 05 00
                SHL     AX, 1                   ; D1 E0
                SUB     AX, [BP+8]              ; 2B 46 08
                MOV     CX, DX                  ; 8B CA
                SUB     AX, CX                  ; 2B C1
                JNS     SHORT evg_sbm_clip_top  ; 79 13
                NEG     AX                      ; F7 D8
                DEC     AX                      ; 48
                MOV     BX, AX                  ; 8B D8
                SUB     DX, AX                  ; 2B D0
                SHR     AX, 1                   ; D1 E8
                SHR     AX, 1                   ; D1 E8
                SUB     AX, [BP-4]              ; 2B 46 FC
                JC      SHORT evg_sbm_clip_top  ; 72 03
                JMP     evg_sprite_blit_cleanup      ; E9 4C 0B
evg_sbm_clip_top:                               ; chunk:0x1184
                MOV     AX, ds:[0009H]          ; A1 09 00
                SHL     AX, 1                   ; D1 E0
                SUB     AX, [BP+0AH]            ; 2B 46 0A
                MOV     CX, cs:[10CCH]          ; 2E 8B 0E CC 10
                SUB     AX, CX                  ; 2B C1
                JNS     SHORT evg_sbm_clip_btm  ; 79 0D
                NEG     AX                      ; F7 D8
                DEC     AX                      ; 48
                SUB     cs:[10CCH], AX          ; 2E 29 06 CC 10
                JA      SHORT evg_sbm_clip_btm  ; 77 03
                JMP     evg_sprite_blit_cleanup      ; E9 2E 0B
evg_sbm_clip_btm:                               ; chunk:0x11A2
                MOV     AX, ds:[0007H]          ; A1 07 00
                SHL     AX, 1                   ; D1 E0
                SUB     AX, [BP+0AH]            ; 2B 46 0A
                JLE     SHORT evg_sbm_clip_left ; 7E 3C
                DEC     AX                      ; 48
                SUB     cs:[10CCH], AX          ; 2E 29 06 CC 10
                PUSH    DX                      ; 52
                XOR     DX, DX                  ; 33 D2
                MUL     WORD PTR [BP-4]         ; F7 66 FC
                SHL     AX, 1                   ; D1 E0
                SHL     AX, 1                   ; D1 E0
                POP     DX                      ; 5A
                TEST    BYTE PTR [BP+0CH], 1    ; F6 46 0C 01
                JZ      SHORT evg_sbm_no_neg    ; 74 02
                NEG     AX                      ; F7 D8
evg_sbm_no_neg:                                 ; chunk:0x11C5
                ADD     SI, AX                  ; 03 F0
                MOV     DI, ds:[0007H]          ; 8B 3E 07 00
                SHL     AX, 1                   ; D1 E0
                SHL     DI, 1                   ; D1 E7
                MOV     DI, [WORD PTR DI+pRow_offset_lut] ; 8B BD F2 06
                SHL     DI, 1                   ; D1 E7
                ADD     DI, [BP+8]              ; 03 7E 08
                MOV     AX, cs:[10CCH]          ; 2E A1 CC 10
                OR      AX, AX                  ; 0B C0
                JNZ     SHORT evg_sbm_chk_sgn   ; 75 03
                JMP     evg_sprite_blit_cleanup      ; E9 ED 0A
evg_sbm_chk_sgn:                                ; chunk:0x11E3
                JNS     SHORT evg_sbm_clip_left ; 79 03
                JMP     evg_sprite_blit_cleanup      ; E9 E8 0A
evg_sbm_clip_left:                              ; chunk:0x11E8
                MOV     AX, ds:[0003H]          ; A1 03 00
                SHL     AX, 1                   ; D1 E0
                SUB     AX, [BP+8]              ; 2B 46 08
                JLE     SHORT evg_sbm_clip_done ; 7E 1E
                ADD     DI, AX                  ; 03 F8
                ADD     BX, AX                  ; 03 D8
                TEST    BYTE PTR [BP+0CH], 2    ; F6 46 0C 02
                JZ      SHORT evg_sbm_no_si_sub ; 74 04
                SUB     SI, AX                  ; 2B F0
                SUB     SI, AX                  ; 2B F0
evg_sbm_no_si_sub:                              ; chunk:0x1200
                SUB     DX, AX                  ; 2B D0
                ADD     SI, AX                  ; 03 F0
                SHR     AX, 1                   ; D1 E8
                SHR     AX, 1                   ; D1 E8
                SUB     AX, [BP-4]              ; 2B 46 FC
                JC      SHORT evg_sbm_clip_done ; 72 03
                JMP     evg_sprite_blit_cleanup      ; E9 C0 0A
evg_sbm_clip_done:                              ; chunk:0x1210
                MOV     AX, DI                  ; 8B C7
                AND     AX, 3                   ; 25 03 00
                SHL     AX, 1                   ; D1 E0
                MOV     cs:[10CAH], AX          ; 2E A3 CA 10
                MOV     AX, SI                  ; 8B C6
                TEST    BYTE PTR [BP+0CH], 2    ; F6 46 0C 02
                JZ      SHORT evg_sbm_no_not    ; 74 02
                NOT     AX                      ; F7 D0
evg_sbm_no_not:                                 ; chunk:0x1225
                AND     AX, 3                   ; 25 03 00
                MOV     cs:[10C8H], AX          ; 2E A3 C8 10
                SHR     SI, 1                   ; D1 EE
                SHR     SI, 1                   ; D1 EE
                TEST    BYTE PTR [BP+0CH], 2    ; F6 46 0C 02
                JZ      SHORT evg_sbm_no_dec_si ; 74 01
                DEC     SI                      ; 4E
evg_sbm_no_dec_si:                              ; chunk:0x1237
                MOV     AX, [BP-0AH]            ; 8B 46 F6
                ADD     SI, [BP-8]              ; 03 76 F8
                MOV     cs:[10C6H], SI          ; 2E 89 36 C6 10
                MOV     DS, AX                  ; 8E D8
                MOV     cs:[10C2H], BX          ; 2E 89 1E C2 10
                MOV     BX, [BP+0CH]            ; 8B 5E 0C
                SHL     BX, 1                   ; D1 E3
                MOV     AX, [WORD PTR cs:BX+010D2H] ; 2E 8B 87 D2 10
                MOV     cs:[10D0H], DI          ; 2E 89 3E D0 10
                PUSH    AX                      ; 50
                PUSH    DX                      ; 52
                MOV     DX, 03C4H               ; BA C4 03
                MOV     AL, 2                   ; B0 02
                OUT     DX, AL                  ; EE
                POP     DX                      ; 5A
                PUSH    DX                      ; 52
                MOV     CL, BYTE PTR cs:[10CAH] ; 2E 8A 0E CA 10
                MOV     DI, cs:[10D0H]          ; 2E 8B 3E D0 10
                MOV     AL, 3                   ; B0 03
                SHL     AL, CL                  ; D2 E0
                ADD     WORD PTR cs:[10CAH], 2  ; 2E 83 06 CA 10 02
                OR      AL, AL                  ; 0A C0
                JNZ     SHORT evg_sbm_al_ok     ; 75 10
                INC     DI                      ; 47
                MOV     cs:[10D0H], DI          ; 2E 89 3E D0 10
                MOV     BYTE PTR cs:[10CAH], 2  ; 2E C6 06 CA 10 02
                MOV     AL, 3                   ; B0 03
                JMP     SHORT evg_sbm_emit      ; EB 16
evg_sbm_al_ok:                                  ; chunk:0x128A
                TEST    AL, 0F0H                ; A8 F0
                JZ      SHORT evg_sbm_emit      ; 74 12
                TEST    AL, 0C0H                ; A8 C0
                JNZ     SHORT evg_sbm_shr_al    ; 75 06
                INC     DI                      ; 47
                MOV     cs:[10D0H], DI          ; 2E 89 3E D0 10
evg_sbm_shr_al:                                 ; chunk:0x1298
                SHR     AL, 1                   ; D0 E8
                SHR     AL, 1                   ; D0 E8
                SHR     AL, 1                   ; D0 E8
                SHR     AL, 1                   ; D0 E8
evg_sbm_emit:                                   ; chunk:0x12A0
                MOV     DX, 03C5H               ; BA C5 03
                OUT     DX, AL                  ; EE
                POP     DX                      ; 5A
                TEST    BYTE PTR [BP+0CH], 2    ; F6 46 0C 02
                JNZ     SHORT evg_sbm_tail_dec  ; 75 23
                PUSH    DX                      ; 52
                XOR     DX, DX                  ; 33 D2
                MOV     AX, cs:[10C8H]          ; 2E A1 C8 10
                MUL     WORD PTR cs:[10C4H]     ; 2E F7 26 C4 10
                ADD     AX, cs:[10C6H]          ; 2E 03 06 C6 10
                MOV     SI, AX                  ; 8B F0
                MOV     AX, cs:[10C8H]          ; 2E A1 C8 10
                INC     AX                      ; 40
                AND     AX, 3                   ; 25 03 00
                MOV     cs:[10C8H], AX          ; 2E A3 C8 10
                POP     DX                      ; 5A
                POP     AX                      ; 58
                JMP     AX                      ; FF E0   COMPUTED_JUMP via dispatch table
evg_sbm_tail_dec:                               ; chunk:0x12CE
                PUSH    DX                      ; 52
                XOR     DX, DX                  ; 33 D2
                MOV     AX, cs:[10C8H]          ; 2E A1 C8 10
                MUL     WORD PTR cs:[10C4H]     ; 2E F7 26 C4 10
                ADD     AX, cs:[10C6H]          ; 2E 03 06 C6 10
                MOV     SI, AX                  ; 8B F0
                MOV     AX, cs:[10C8H]          ; 2E A1 C8 10
                DEC     AX                      ; 48
                AND     AX, 3                   ; 25 03 00
                MOV     cs:[10C8H], AX          ; 2E A3 C8 10
                POP     DX                      ; 5A
                POP     AX                      ; 58
                JMP     AX                      ; FF E0   COMPUTED_JUMP via dispatch table
evg_sprite_blit_master ENDP

; ============================================================================
; evg_sprite_blit_flip_variant_a -- no-flip (flags=0) flip-variant tail.
; chunk:0x12F1..0x1554 (612 bytes).
;
; Called as a fall-through after `JMP AX` in evg_sprite_blit_master.
; The body is four near-identical copies (one per plane), each:
;   1. Set BP to 0x140 (line stride bias), save DX, save rows.
;   2. Adjust DX (column delta) and BX (saved BX state) for this plane.
;   3. Shift to byte-aligned counts.
;   4. Inner LODSB / OR / STOSB / DEC DI / INC DI / INC DI / LOOP loop
;      that writes 2 pixels per source byte and doubles the row write.
;   5. Restore DX, advance plane state (SI advance, plane++, mask shift).
;   6. Final tail jumps to evg_sprite_blit_cleanup @ 0x1CD0.
; ============================================================================
evg_sprite_blit_flip_variant_a PROC NEAR
                MOV     BP, 0140H               ; BD 40 01    plane 0 start
                PUSH    DX                      ; 52
                PUSH    [WORD PTR cs:10CCH]     ; 2E FF 36 CC 10
                ADD     DX, 3                   ; 83 C2 03
                MOV     BX, cs:[10C2H]          ; 2E 8B 1E C2 10
                ADD     BX, 0                   ; 83 C3 00
                SHR     BX, 1                   ; D1 EB
                SHR     BX, 1                   ; D1 EB
                SHR     DX, 1                   ; D1 EA
                SHR     DX, 1                   ; D1 EA
                MOV     AX, DX                  ; 8B C2
                SHL     AX, 1                   ; D1 E0
                SUB     BP, AX                  ; 2B E8
evg_sba_p0_row:                                 ; chunk:0x1313
                MOV     CX, DX                  ; 8B CA
evg_sba_p0_inner:                               ; chunk:0x1315
                LODSB                           ; AC
                OR      AL, AL                  ; 0A C0
                JZ      SHORT evg_sba_p0_skip   ; 74 07
                MOV     [BYTE PTR ES:DI+0A0H], AL ; 26 88 85 A0 00
                STOSB                           ; AA
                DEC     DI                      ; 4F
evg_sba_p0_skip:                                ; chunk:0x1321
                INC     DI                      ; 47
                INC     DI                      ; 47
                LOOP    SHORT evg_sba_p0_inner  ; E2 F0
                ADD     SI, BX                  ; 03 F3
                ADD     DI, BP                  ; 03 FD
                DEC     WORD PTR cs:[10CCH]     ; 2E FF 0E CC 10
                JNZ     SHORT evg_sba_p0_row    ; 75 E3
                POP     [WORD PTR cs:10CCH]     ; 2E 8F 06 CC 10
                POP     DX                      ; 5A
                PUSH    DX                      ; 52
                XOR     DX, DX                  ; 33 D2
                MOV     AX, cs:[10C8H]          ; 2E A1 C8 10
                OR      AX, AX                  ; 0B C0
                JNZ     SHORT evg_sba_p0_no_inc ; 75 07
                INC     WORD PTR cs:[10C6H]     ; 2E FF 06 C6 10
                JMP     SHORT evg_sba_p0_after  ; EB 05
evg_sba_p0_no_inc:                              ; chunk:0x1348
                MUL     WORD PTR cs:[10C4H]     ; 2E F7 26 C4 10
evg_sba_p0_after:                               ; chunk:0x134D
                ADD     AX, cs:[10C6H]          ; 2E 03 06 C6 10
                MOV     SI, AX                  ; 8B F0
                MOV     AX, cs:[10C8H]          ; 2E A1 C8 10
                INC     AX                      ; 40
                AND     AX, 3                   ; 25 03 00
                MOV     cs:[10C8H], AX          ; 2E A3 C8 10
                POP     DX                      ; 5A
                PUSH    DX                      ; 52
                MOV     CL, BYTE PTR cs:[10CAH] ; 2E 8A 0E CA 10
                MOV     DI, cs:[10D0H]          ; 2E 8B 3E D0 10
                MOV     AL, 3                   ; B0 03
                SHL     AL, CL                  ; D2 E0
                ADD     WORD PTR cs:[10CAH], 2  ; 2E 83 06 CA 10 02
                OR      AL, AL                  ; 0A C0
                JNZ     SHORT evg_sba_p0_al_ok  ; 75 10
                INC     DI                      ; 47
                MOV     cs:[10D0H], DI          ; 2E 89 3E D0 10
                MOV     BYTE PTR cs:[10CAH], 2  ; 2E C6 06 CA 10 02
                MOV     AL, 3                   ; B0 03
                JMP     SHORT evg_sba_p0_emit   ; EB 16
evg_sba_p0_al_ok:                               ; chunk:0x138A
                TEST    AL, 0F0H                ; A8 F0
                JZ      SHORT evg_sba_p0_emit   ; 74 12
                TEST    AL, 0C0H                ; A8 C0
                JNZ     SHORT evg_sba_p0_shr    ; 75 06
                INC     DI                      ; 47
                MOV     cs:[10D0H], DI          ; 2E 89 3E D0 10
evg_sba_p0_shr:                                 ; chunk:0x1398
                SHR     AL, 1                   ; D0 E8
                SHR     AL, 1                   ; D0 E8
                SHR     AL, 1                   ; D0 E8
                SHR     AL, 1                   ; D0 E8
evg_sba_p0_emit:                                ; chunk:0x13A0
                MOV     DX, 03C5H               ; BA C5 03
                OUT     DX, AL                  ; EE
                POP     DX                      ; 5A
                ; --- plane 1 -------------------------------------------------
                MOV     BP, 0140H               ; BD 40 01
                PUSH    DX                      ; 52
                PUSH    [WORD PTR cs:10CCH]     ; 2E FF 36 CC 10
                ADD     DX, 2                   ; 83 C2 02
                MOV     BX, cs:[10C2H]          ; 2E 8B 1E C2 10
                ADD     BX, 1                   ; 83 C3 01
                SHR     BX, 1                   ; D1 EB
                SHR     BX, 1                   ; D1 EB
                SHR     DX, 1                   ; D1 EA
                SHR     DX, 1                   ; D1 EA
                MOV     AX, DX                  ; 8B C2
                SHL     AX, 1                   ; D1 E0
                SUB     BP, AX                  ; 2B E8
evg_sba_p1_row:                                 ; chunk:0x13C7
                MOV     CX, DX                  ; 8B CA
evg_sba_p1_inner:                               ; chunk:0x13C9
                LODSB                           ; AC
                OR      AL, AL                  ; 0A C0
                JZ      SHORT evg_sba_p1_skip   ; 74 07
                MOV     [BYTE PTR ES:DI+0A0H], AL ; 26 88 85 A0 00
                STOSB                           ; AA
                DEC     DI                      ; 4F
evg_sba_p1_skip:                                ; chunk:0x13D5
                INC     DI                      ; 47
                INC     DI                      ; 47
                LOOP    SHORT evg_sba_p1_inner  ; E2 F0
                ADD     SI, BX                  ; 03 F3
                ADD     DI, BP                  ; 03 FD
                DEC     WORD PTR cs:[10CCH]     ; 2E FF 0E CC 10
                JNZ     SHORT evg_sba_p1_row    ; 75 E3
                POP     [WORD PTR cs:10CCH]     ; 2E 8F 06 CC 10
                POP     DX                      ; 5A
                PUSH    DX                      ; 52
                XOR     DX, DX                  ; 33 D2
                MOV     AX, cs:[10C8H]          ; 2E A1 C8 10
                OR      AX, AX                  ; 0B C0
                JNZ     SHORT evg_sba_p1_no_inc ; 75 07
                INC     WORD PTR cs:[10C6H]     ; 2E FF 06 C6 10
                JMP     SHORT evg_sba_p1_after  ; EB 05
evg_sba_p1_no_inc:                              ; chunk:0x13FC
                MUL     WORD PTR cs:[10C4H]     ; 2E F7 26 C4 10
evg_sba_p1_after:                               ; chunk:0x1401
                ADD     AX, cs:[10C6H]          ; 2E 03 06 C6 10
                MOV     SI, AX                  ; 8B F0
                MOV     AX, cs:[10C8H]          ; 2E A1 C8 10
                INC     AX                      ; 40
                AND     AX, 3                   ; 25 03 00
                MOV     cs:[10C8H], AX          ; 2E A3 C8 10
                POP     DX                      ; 5A
                PUSH    DX                      ; 52
                MOV     CL, BYTE PTR cs:[10CAH] ; 2E 8A 0E CA 10
                MOV     DI, cs:[10D0H]          ; 2E 8B 3E D0 10
                MOV     AL, 3                   ; B0 03
                SHL     AL, CL                  ; D2 E0
                ADD     WORD PTR cs:[10CAH], 2  ; 2E 83 06 CA 10 02
                OR      AL, AL                  ; 0A C0
                JNZ     SHORT evg_sba_p1_al_ok  ; 75 10
                INC     DI                      ; 47
                MOV     cs:[10D0H], DI          ; 2E 89 3E D0 10
                MOV     BYTE PTR cs:[10CAH], 2  ; 2E C6 06 CA 10 02
                MOV     AL, 3                   ; B0 03
                JMP     SHORT evg_sba_p1_emit   ; EB 16
evg_sba_p1_al_ok:                               ; chunk:0x143E
                TEST    AL, 0F0H                ; A8 F0
                JZ      SHORT evg_sba_p1_emit   ; 74 12
                TEST    AL, 0C0H                ; A8 C0
                JNZ     SHORT evg_sba_p1_shr    ; 75 06
                INC     DI                      ; 47
                MOV     cs:[10D0H], DI          ; 2E 89 3E D0 10
evg_sba_p1_shr:                                 ; chunk:0x144C
                SHR     AL, 1                   ; D0 E8
                SHR     AL, 1                   ; D0 E8
                SHR     AL, 1                   ; D0 E8
                SHR     AL, 1                   ; D0 E8
evg_sba_p1_emit:                                ; chunk:0x1454
                MOV     DX, 03C5H               ; BA C5 03
                OUT     DX, AL                  ; EE
                POP     DX                      ; 5A
                ; --- plane 2 -------------------------------------------------
                MOV     BP, 0140H               ; BD 40 01
                PUSH    DX                      ; 52
                PUSH    [WORD PTR cs:10CCH]     ; 2E FF 36 CC 10
                ADD     DX, 1                   ; 83 C2 01
                MOV     BX, cs:[10C2H]          ; 2E 8B 1E C2 10
                ADD     BX, 2                   ; 83 C3 02
                SHR     BX, 1                   ; D1 EB
                SHR     BX, 1                   ; D1 EB
                SHR     DX, 1                   ; D1 EA
                SHR     DX, 1                   ; D1 EA
                MOV     AX, DX                  ; 8B C2
                SHL     AX, 1                   ; D1 E0
                SUB     BP, AX                  ; 2B E8
evg_sba_p2_row:                                 ; chunk:0x147B
                MOV     CX, DX                  ; 8B CA
evg_sba_p2_inner:                               ; chunk:0x147D
                LODSB                           ; AC
                OR      AL, AL                  ; 0A C0
                JZ      SHORT evg_sba_p2_skip   ; 74 07
                MOV     [BYTE PTR ES:DI+0A0H], AL ; 26 88 85 A0 00
                STOSB                           ; AA
                DEC     DI                      ; 4F
evg_sba_p2_skip:                                ; chunk:0x1489
                INC     DI                      ; 47
                INC     DI                      ; 47
                LOOP    SHORT evg_sba_p2_inner  ; E2 F0
                ADD     SI, BX                  ; 03 F3
                ADD     DI, BP                  ; 03 FD
                DEC     WORD PTR cs:[10CCH]     ; 2E FF 0E CC 10
                JNZ     SHORT evg_sba_p2_row    ; 75 E3
                POP     [WORD PTR cs:10CCH]     ; 2E 8F 06 CC 10
                POP     DX                      ; 5A
                PUSH    DX                      ; 52
                XOR     DX, DX                  ; 33 D2
                MOV     AX, cs:[10C8H]          ; 2E A1 C8 10
                OR      AX, AX                  ; 0B C0
                JNZ     SHORT evg_sba_p2_no_inc ; 75 07
                INC     WORD PTR cs:[10C6H]     ; 2E FF 06 C6 10
                JMP     SHORT evg_sba_p2_after  ; EB 05
evg_sba_p2_no_inc:                              ; chunk:0x14B0
                MUL     WORD PTR cs:[10C4H]     ; 2E F7 26 C4 10
evg_sba_p2_after:                               ; chunk:0x14B5
                ADD     AX, cs:[10C6H]          ; 2E 03 06 C6 10
                MOV     SI, AX                  ; 8B F0
                MOV     AX, cs:[10C8H]          ; 2E A1 C8 10
                INC     AX                      ; 40
                AND     AX, 3                   ; 25 03 00
                MOV     cs:[10C8H], AX          ; 2E A3 C8 10
                POP     DX                      ; 5A
                PUSH    DX                      ; 52
                MOV     CL, BYTE PTR cs:[10CAH] ; 2E 8A 0E CA 10
                MOV     DI, cs:[10D0H]          ; 2E 8B 3E D0 10
                MOV     AL, 3                   ; B0 03
                SHL     AL, CL                  ; D2 E0
                ADD     WORD PTR cs:[10CAH], 2  ; 2E 83 06 CA 10 02
                OR      AL, AL                  ; 0A C0
                JNZ     SHORT evg_sba_p2_al_ok  ; 75 10
                INC     DI                      ; 47
                MOV     cs:[10D0H], DI          ; 2E 89 3E D0 10
                MOV     BYTE PTR cs:[10CAH], 2  ; 2E C6 06 CA 10 02
                MOV     AL, 3                   ; B0 03
                JMP     SHORT evg_sba_p2_emit   ; EB 16
evg_sba_p2_al_ok:                               ; chunk:0x14F2
                TEST    AL, 0F0H                ; A8 F0
                JZ      SHORT evg_sba_p2_emit   ; 74 12
                TEST    AL, 0C0H                ; A8 C0
                JNZ     SHORT evg_sba_p2_shr    ; 75 06
                INC     DI                      ; 47
                MOV     cs:[10D0H], DI          ; 2E 89 3E D0 10
evg_sba_p2_shr:                                 ; chunk:0x1500
                SHR     AL, 1                   ; D0 E8
                SHR     AL, 1                   ; D0 E8
                SHR     AL, 1                   ; D0 E8
                SHR     AL, 1                   ; D0 E8
evg_sba_p2_emit:                                ; chunk:0x1508
                MOV     DX, 03C5H               ; BA C5 03
                OUT     DX, AL                  ; EE
                POP     DX                      ; 5A
                ; --- plane 3 -------------------------------------------------
                MOV     BP, 0140H               ; BD 40 01
                PUSH    DX                      ; 52
                PUSH    [WORD PTR cs:10CCH]     ; 2E FF 36 CC 10
                ADD     DX, 0                   ; 83 C2 00
                MOV     BX, cs:[10C2H]          ; 2E 8B 1E C2 10
                ADD     BX, 3                   ; 83 C3 03
                SHR     BX, 1                   ; D1 EB
                SHR     BX, 1                   ; D1 EB
                SHR     DX, 1                   ; D1 EA
                SHR     DX, 1                   ; D1 EA
                MOV     AX, DX                  ; 8B C2
                SHL     AX, 1                   ; D1 E0
                SUB     BP, AX                  ; 2B E8
evg_sba_p3_row:                                 ; chunk:0x152F
                MOV     CX, DX                  ; 8B CA
evg_sba_p3_inner:                               ; chunk:0x1531
                LODSB                           ; AC
                OR      AL, AL                  ; 0A C0
                JZ      SHORT evg_sba_p3_skip   ; 74 07
                MOV     [BYTE PTR ES:DI+0A0H], AL ; 26 88 85 A0 00
                STOSB                           ; AA
                DEC     DI                      ; 4F
evg_sba_p3_skip:                                ; chunk:0x153D
                INC     DI                      ; 47
                INC     DI                      ; 47
                LOOP    SHORT evg_sba_p3_inner  ; E2 F0
                ADD     SI, BX                  ; 03 F3
                ADD     DI, BP                  ; 03 FD
                DEC     WORD PTR cs:[10CCH]     ; 2E FF 0E CC 10
                JNZ     SHORT evg_sba_p3_row    ; 75 E3
                POP     [WORD PTR cs:10CCH]     ; 2E 8F 06 CC 10
                POP     DX                      ; 5A
                JMP     evg_sprite_blit_cleanup      ; E9 7B 07
evg_sprite_blit_flip_variant_a ENDP

; ============================================================================
; evg_sprite_blit_flip_variant_b -- h-flip (flags=1) flip-variant tail.
; chunk:0x1555..0x17CC (632 bytes).
;
; Like _a but with horizontal mirror: BX is computed as
; `(saved_bx + plane_idx) / 2 - src_w / 2`, then SAR'd by 1 — i.e. the
; source-stride math runs in reverse so the sprite reads in the
; opposite direction.
; ============================================================================
evg_sprite_blit_flip_variant_b PROC NEAR
                MOV     BP, 0140H               ; BD 40 01
                PUSH    DX                      ; 52
                PUSH    [WORD PTR cs:10CCH]     ; 2E FF 36 CC 10
                ADD     DX, 3                   ; 83 C2 03
                MOV     BX, cs:[10C2H]          ; 2E 8B 1E C2 10
                ADD     BX, 0                   ; 83 C3 00
                SHR     BX, 1                   ; D1 EB
                SUB     BX, cs:[10CEH]          ; 2E 2B 1E CE 10
                SAR     BX, 1                   ; D1 FB
                SHR     DX, 1                   ; D1 EA
                SHR     DX, 1                   ; D1 EA
                MOV     AX, DX                  ; 8B C2
                SHL     AX, 1                   ; D1 E0
                SUB     BP, AX                  ; 2B E8
evg_sbb_p0_row:                                 ; chunk:0x157C
                MOV     CX, DX                  ; 8B CA
evg_sbb_p0_inner:                               ; chunk:0x157E
                LODSB                           ; AC
                OR      AL, AL                  ; 0A C0
                JZ      SHORT evg_sbb_p0_skip   ; 74 07
                MOV     [BYTE PTR ES:DI+0A0H], AL ; 26 88 85 A0 00
                STOSB                           ; AA
                DEC     DI                      ; 4F
evg_sbb_p0_skip:                                ; chunk:0x158A
                INC     DI                      ; 47
                INC     DI                      ; 47
                LOOP    SHORT evg_sbb_p0_inner  ; E2 F0
                ADD     SI, BX                  ; 03 F3
                ADD     DI, BP                  ; 03 FD
                DEC     WORD PTR cs:[10CCH]     ; 2E FF 0E CC 10
                JNZ     SHORT evg_sbb_p0_row    ; 75 E3
                POP     [WORD PTR cs:10CCH]     ; 2E 8F 06 CC 10
                POP     DX                      ; 5A
                PUSH    DX                      ; 52
                XOR     DX, DX                  ; 33 D2
                MOV     AX, cs:[10C8H]          ; 2E A1 C8 10
                OR      AX, AX                  ; 0B C0
                JNZ     SHORT evg_sbb_p0_no_inc ; 75 07
                INC     WORD PTR cs:[10C6H]     ; 2E FF 06 C6 10
                JMP     SHORT evg_sbb_p0_after  ; EB 05
evg_sbb_p0_no_inc:                              ; chunk:0x15B1
                MUL     WORD PTR cs:[10C4H]     ; 2E F7 26 C4 10
evg_sbb_p0_after:                               ; chunk:0x15B6
                ADD     AX, cs:[10C6H]          ; 2E 03 06 C6 10
                MOV     SI, AX                  ; 8B F0
                MOV     AX, cs:[10C8H]          ; 2E A1 C8 10
                INC     AX                      ; 40
                AND     AX, 3                   ; 25 03 00
                MOV     cs:[10C8H], AX          ; 2E A3 C8 10
                POP     DX                      ; 5A
                PUSH    DX                      ; 52
                MOV     CL, BYTE PTR cs:[10CAH] ; 2E 8A 0E CA 10
                MOV     DI, cs:[10D0H]          ; 2E 8B 3E D0 10
                MOV     AL, 3                   ; B0 03
                SHL     AL, CL                  ; D2 E0
                ADD     WORD PTR cs:[10CAH], 2  ; 2E 83 06 CA 10 02
                OR      AL, AL                  ; 0A C0
                JNZ     SHORT evg_sbb_p0_al_ok  ; 75 10
                INC     DI                      ; 47
                MOV     cs:[10D0H], DI          ; 2E 89 3E D0 10
                MOV     BYTE PTR cs:[10CAH], 2  ; 2E C6 06 CA 10 02
                MOV     AL, 3                   ; B0 03
                JMP     SHORT evg_sbb_p0_emit   ; EB 16
evg_sbb_p0_al_ok:                               ; chunk:0x15F3
                TEST    AL, 0F0H                ; A8 F0
                JZ      SHORT evg_sbb_p0_emit   ; 74 12
                TEST    AL, 0C0H                ; A8 C0
                JNZ     SHORT evg_sbb_p0_shr    ; 75 06
                INC     DI                      ; 47
                MOV     cs:[10D0H], DI          ; 2E 89 3E D0 10
evg_sbb_p0_shr:                                 ; chunk:0x1601
                SHR     AL, 1                   ; D0 E8
                SHR     AL, 1                   ; D0 E8
                SHR     AL, 1                   ; D0 E8
                SHR     AL, 1                   ; D0 E8
evg_sbb_p0_emit:                                ; chunk:0x1609
                MOV     DX, 03C5H               ; BA C5 03
                OUT     DX, AL                  ; EE
                POP     DX                      ; 5A
                ; --- plane 1 -------------------------------------------------
                MOV     BP, 0140H               ; BD 40 01
                PUSH    DX                      ; 52
                PUSH    [WORD PTR cs:10CCH]     ; 2E FF 36 CC 10
                ADD     DX, 2                   ; 83 C2 02
                MOV     BX, cs:[10C2H]          ; 2E 8B 1E C2 10
                ADD     BX, 1                   ; 83 C3 01
                SHR     BX, 1                   ; D1 EB
                SUB     BX, cs:[10CEH]          ; 2E 2B 1E CE 10
                SAR     BX, 1                   ; D1 FB
                SHR     DX, 1                   ; D1 EA
                SHR     DX, 1                   ; D1 EA
                MOV     AX, DX                  ; 8B C2
                SHL     AX, 1                   ; D1 E0
                SUB     BP, AX                  ; 2B E8
evg_sbb_p1_row:                                 ; chunk:0x1635
                MOV     CX, DX                  ; 8B CA
evg_sbb_p1_inner:                               ; chunk:0x1637
                LODSB                           ; AC
                OR      AL, AL                  ; 0A C0
                JZ      SHORT evg_sbb_p1_skip   ; 74 07
                MOV     [BYTE PTR ES:DI+0A0H], AL ; 26 88 85 A0 00
                STOSB                           ; AA
                DEC     DI                      ; 4F
evg_sbb_p1_skip:                                ; chunk:0x1643
                INC     DI                      ; 47
                INC     DI                      ; 47
                LOOP    SHORT evg_sbb_p1_inner  ; E2 F0
                ADD     SI, BX                  ; 03 F3
                ADD     DI, BP                  ; 03 FD
                DEC     WORD PTR cs:[10CCH]     ; 2E FF 0E CC 10
                JNZ     SHORT evg_sbb_p1_row    ; 75 E3
                POP     [WORD PTR cs:10CCH]     ; 2E 8F 06 CC 10
                POP     DX                      ; 5A
                PUSH    DX                      ; 52
                XOR     DX, DX                  ; 33 D2
                MOV     AX, cs:[10C8H]          ; 2E A1 C8 10
                OR      AX, AX                  ; 0B C0
                JNZ     SHORT evg_sbb_p1_no_inc ; 75 07
                INC     WORD PTR cs:[10C6H]     ; 2E FF 06 C6 10
                JMP     SHORT evg_sbb_p1_after  ; EB 05
evg_sbb_p1_no_inc:                              ; chunk:0x166A
                MUL     WORD PTR cs:[10C4H]     ; 2E F7 26 C4 10
evg_sbb_p1_after:                               ; chunk:0x166F
                ADD     AX, cs:[10C6H]          ; 2E 03 06 C6 10
                MOV     SI, AX                  ; 8B F0
                MOV     AX, cs:[10C8H]          ; 2E A1 C8 10
                INC     AX                      ; 40
                AND     AX, 3                   ; 25 03 00
                MOV     cs:[10C8H], AX          ; 2E A3 C8 10
                POP     DX                      ; 5A
                PUSH    DX                      ; 52
                MOV     CL, BYTE PTR cs:[10CAH] ; 2E 8A 0E CA 10
                MOV     DI, cs:[10D0H]          ; 2E 8B 3E D0 10
                MOV     AL, 3                   ; B0 03
                SHL     AL, CL                  ; D2 E0
                ADD     WORD PTR cs:[10CAH], 2  ; 2E 83 06 CA 10 02
                OR      AL, AL                  ; 0A C0
                JNZ     SHORT evg_sbb_p1_al_ok  ; 75 10
                INC     DI                      ; 47
                MOV     cs:[10D0H], DI          ; 2E 89 3E D0 10
                MOV     BYTE PTR cs:[10CAH], 2  ; 2E C6 06 CA 10 02
                MOV     AL, 3                   ; B0 03
                JMP     SHORT evg_sbb_p1_emit   ; EB 16
evg_sbb_p1_al_ok:                               ; chunk:0x16AC
                TEST    AL, 0F0H                ; A8 F0
                JZ      SHORT evg_sbb_p1_emit   ; 74 12
                TEST    AL, 0C0H                ; A8 C0
                JNZ     SHORT evg_sbb_p1_shr    ; 75 06
                INC     DI                      ; 47
                MOV     cs:[10D0H], DI          ; 2E 89 3E D0 10
evg_sbb_p1_shr:                                 ; chunk:0x16BA
                SHR     AL, 1                   ; D0 E8
                SHR     AL, 1                   ; D0 E8
                SHR     AL, 1                   ; D0 E8
                SHR     AL, 1                   ; D0 E8
evg_sbb_p1_emit:                                ; chunk:0x16C2
                MOV     DX, 03C5H               ; BA C5 03
                OUT     DX, AL                  ; EE
                POP     DX                      ; 5A
                ; --- plane 2 -------------------------------------------------
                MOV     BP, 0140H               ; BD 40 01
                PUSH    DX                      ; 52
                PUSH    [WORD PTR cs:10CCH]     ; 2E FF 36 CC 10
                ADD     DX, 1                   ; 83 C2 01
                MOV     BX, cs:[10C2H]          ; 2E 8B 1E C2 10
                ADD     BX, 2                   ; 83 C3 02
                SHR     BX, 1                   ; D1 EB
                SUB     BX, cs:[10CEH]          ; 2E 2B 1E CE 10
                SAR     BX, 1                   ; D1 FB
                SHR     DX, 1                   ; D1 EA
                SHR     DX, 1                   ; D1 EA
                MOV     AX, DX                  ; 8B C2
                SHL     AX, 1                   ; D1 E0
                SUB     BP, AX                  ; 2B E8
evg_sbb_p2_row:                                 ; chunk:0x16EE
                MOV     CX, DX                  ; 8B CA
evg_sbb_p2_inner:                               ; chunk:0x16F0
                LODSB                           ; AC
                OR      AL, AL                  ; 0A C0
                JZ      SHORT evg_sbb_p2_skip   ; 74 07
                MOV     [BYTE PTR ES:DI+0A0H], AL ; 26 88 85 A0 00
                STOSB                           ; AA
                DEC     DI                      ; 4F
evg_sbb_p2_skip:                                ; chunk:0x16FC
                INC     DI                      ; 47
                INC     DI                      ; 47
                LOOP    SHORT evg_sbb_p2_inner  ; E2 F0
                ADD     SI, BX                  ; 03 F3
                ADD     DI, BP                  ; 03 FD
                DEC     WORD PTR cs:[10CCH]     ; 2E FF 0E CC 10
                JNZ     SHORT evg_sbb_p2_row    ; 75 E3
                POP     [WORD PTR cs:10CCH]     ; 2E 8F 06 CC 10
                POP     DX                      ; 5A
                PUSH    DX                      ; 52
                XOR     DX, DX                  ; 33 D2
                MOV     AX, cs:[10C8H]          ; 2E A1 C8 10
                OR      AX, AX                  ; 0B C0
                JNZ     SHORT evg_sbb_p2_no_inc ; 75 07
                INC     WORD PTR cs:[10C6H]     ; 2E FF 06 C6 10
                JMP     SHORT evg_sbb_p2_after  ; EB 05
evg_sbb_p2_no_inc:                              ; chunk:0x1723
                MUL     WORD PTR cs:[10C4H]     ; 2E F7 26 C4 10
evg_sbb_p2_after:                               ; chunk:0x1728
                ADD     AX, cs:[10C6H]          ; 2E 03 06 C6 10
                MOV     SI, AX                  ; 8B F0
                MOV     AX, cs:[10C8H]          ; 2E A1 C8 10
                INC     AX                      ; 40
                AND     AX, 3                   ; 25 03 00
                MOV     cs:[10C8H], AX          ; 2E A3 C8 10
                POP     DX                      ; 5A
                PUSH    DX                      ; 52
                MOV     CL, BYTE PTR cs:[10CAH] ; 2E 8A 0E CA 10
                MOV     DI, cs:[10D0H]          ; 2E 8B 3E D0 10
                MOV     AL, 3                   ; B0 03
                SHL     AL, CL                  ; D2 E0
                ADD     WORD PTR cs:[10CAH], 2  ; 2E 83 06 CA 10 02
                OR      AL, AL                  ; 0A C0
                JNZ     SHORT evg_sbb_p2_al_ok  ; 75 10
                INC     DI                      ; 47
                MOV     cs:[10D0H], DI          ; 2E 89 3E D0 10
                MOV     BYTE PTR cs:[10CAH], 2  ; 2E C6 06 CA 10 02
                MOV     AL, 3                   ; B0 03
                JMP     SHORT evg_sbb_p2_emit   ; EB 16
evg_sbb_p2_al_ok:                               ; chunk:0x1765
                TEST    AL, 0F0H                ; A8 F0
                JZ      SHORT evg_sbb_p2_emit   ; 74 12
                TEST    AL, 0C0H                ; A8 C0
                JNZ     SHORT evg_sbb_p2_shr    ; 75 06
                INC     DI                      ; 47
                MOV     cs:[10D0H], DI          ; 2E 89 3E D0 10
evg_sbb_p2_shr:                                 ; chunk:0x1773
                SHR     AL, 1                   ; D0 E8
                SHR     AL, 1                   ; D0 E8
                SHR     AL, 1                   ; D0 E8
                SHR     AL, 1                   ; D0 E8
evg_sbb_p2_emit:                                ; chunk:0x177B
                MOV     DX, 03C5H               ; BA C5 03
                OUT     DX, AL                  ; EE
                POP     DX                      ; 5A
                ; --- plane 3 -------------------------------------------------
                MOV     BP, 0140H               ; BD 40 01
                PUSH    DX                      ; 52
                PUSH    [WORD PTR cs:10CCH]     ; 2E FF 36 CC 10
                ADD     DX, 0                   ; 83 C2 00
                MOV     BX, cs:[10C2H]          ; 2E 8B 1E C2 10
                ADD     BX, 3                   ; 83 C3 03
                SHR     BX, 1                   ; D1 EB
                SUB     BX, cs:[10CEH]          ; 2E 2B 1E CE 10
                SAR     BX, 1                   ; D1 FB
                SHR     DX, 1                   ; D1 EA
                SHR     DX, 1                   ; D1 EA
                MOV     AX, DX                  ; 8B C2
                SHL     AX, 1                   ; D1 E0
                SUB     BP, AX                  ; 2B E8
evg_sbb_p3_row:                                 ; chunk:0x17A7
                MOV     CX, DX                  ; 8B CA
evg_sbb_p3_inner:                               ; chunk:0x17A9
                LODSB                           ; AC
                OR      AL, AL                  ; 0A C0
                JZ      SHORT evg_sbb_p3_skip   ; 74 07
                MOV     [BYTE PTR ES:DI+0A0H], AL ; 26 88 85 A0 00
                STOSB                           ; AA
                DEC     DI                      ; 4F
evg_sbb_p3_skip:                                ; chunk:0x17B5
                INC     DI                      ; 47
                INC     DI                      ; 47
                LOOP    SHORT evg_sbb_p3_inner  ; E2 F0
                ADD     SI, BX                  ; 03 F3
                ADD     DI, BP                  ; 03 FD
                DEC     WORD PTR cs:[10CCH]     ; 2E FF 0E CC 10
                JNZ     SHORT evg_sbb_p3_row    ; 75 E3
                POP     [WORD PTR cs:10CCH]     ; 2E 8F 06 CC 10
                POP     DX                      ; 5A
                JMP     evg_sprite_blit_cleanup      ; E9 03 05
evg_sprite_blit_flip_variant_b ENDP

; ============================================================================
; evg_sprite_blit_flip_variant_c -- v-flip (flags=2) flip-variant tail.
; chunk:0x17CD..0x1A63 (663 bytes).
;
; Sister of _a but reads the source bytes in REVERSE (MOV AL,[SI]/DEC SI
; instead of LODSB), and the plane-state advance subtracts/decrements
; rather than adds/increments.  BX uses a NEG step so SI walks back
; over the source.
; ============================================================================
evg_sprite_blit_flip_variant_c PROC NEAR
                MOV     BP, 0140H               ; BD 40 01
                PUSH    DX                      ; 52
                PUSH    [WORD PTR cs:10CCH]     ; 2E FF 36 CC 10
                ADD     DX, 3                   ; 83 C2 03
                MOV     BX, cs:[10C2H]          ; 2E 8B 1E C2 10
                ADD     BX, 0                   ; 83 C3 00
                SHR     BX, 1                   ; D1 EB
                SHR     BX, 1                   ; D1 EB
                NEG     BX                      ; F7 DB
                MOV     AX, cs:[10CEH]          ; 2E A1 CE 10
                SHR     AX, 1                   ; D1 E8
                ADD     BX, AX                  ; 03 D8
                SHR     DX, 1                   ; D1 EA
                SHR     DX, 1                   ; D1 EA
                MOV     AX, DX                  ; 8B C2
                SHL     AX, 1                   ; D1 E0
                SUB     BP, AX                  ; 2B E8
evg_sbc_p0_row:                                 ; chunk:0x17F9
                MOV     CX, DX                  ; 8B CA
evg_sbc_p0_inner:                               ; chunk:0x17FB
                MOV     AL, [SI]                ; 8A 04
                DEC     SI                      ; 4E
                OR      AL, AL                  ; 0A C0
                JZ      SHORT evg_sbc_p0_skip   ; 74 07
                MOV     [BYTE PTR ES:DI+0A0H], AL ; 26 88 85 A0 00
                STOSB                           ; AA
                DEC     DI                      ; 4F
evg_sbc_p0_skip:                                ; chunk:0x1809
                INC     DI                      ; 47
                INC     DI                      ; 47
                LOOP    SHORT evg_sbc_p0_inner  ; E2 EE
                ADD     SI, BX                  ; 03 F3
                ADD     DI, BP                  ; 03 FD
                DEC     WORD PTR cs:[10CCH]     ; 2E FF 0E CC 10
                JNZ     SHORT evg_sbc_p0_row    ; 75 E1
                POP     [WORD PTR cs:10CCH]     ; 2E 8F 06 CC 10
                POP     DX                      ; 5A
                PUSH    DX                      ; 52
                XOR     DX, DX                  ; 33 D2
                MOV     AX, cs:[10C8H]          ; 2E A1 C8 10
                CMP     AX, 3                   ; 83 F8 03
                JNZ     SHORT evg_sbc_p0_no_dec ; 75 07
                DEC     WORD PTR cs:[10C6H]     ; 2E FF 0E C6 10
                JMP     SHORT evg_sbc_p0_after  ; EB 05
evg_sbc_p0_no_dec:                              ; chunk:0x1831
                MUL     WORD PTR cs:[10C4H]     ; 2E F7 26 C4 10
evg_sbc_p0_after:                               ; chunk:0x1836
                ADD     AX, cs:[10C6H]          ; 2E 03 06 C6 10
                MOV     SI, AX                  ; 8B F0
                MOV     AX, cs:[10C8H]          ; 2E A1 C8 10
                DEC     AX                      ; 48
                AND     AX, 3                   ; 25 03 00
                MOV     cs:[10C8H], AX          ; 2E A3 C8 10
                POP     DX                      ; 5A
                PUSH    DX                      ; 52
                MOV     CL, BYTE PTR cs:[10CAH] ; 2E 8A 0E CA 10
                MOV     DI, cs:[10D0H]          ; 2E 8B 3E D0 10
                MOV     AL, 3                   ; B0 03
                SHL     AL, CL                  ; D2 E0
                ADD     WORD PTR cs:[10CAH], 2  ; 2E 83 06 CA 10 02
                OR      AL, AL                  ; 0A C0
                JNZ     SHORT evg_sbc_p0_al_ok  ; 75 10
                INC     DI                      ; 47
                MOV     cs:[10D0H], DI          ; 2E 89 3E D0 10
                MOV     BYTE PTR cs:[10CAH], 2  ; 2E C6 06 CA 10 02
                MOV     AL, 3                   ; B0 03
                JMP     SHORT evg_sbc_p0_emit   ; EB 16
evg_sbc_p0_al_ok:                               ; chunk:0x1873
                TEST    AL, 0F0H                ; A8 F0
                JZ      SHORT evg_sbc_p0_emit   ; 74 12
                TEST    AL, 0C0H                ; A8 C0
                JNZ     SHORT evg_sbc_p0_shr    ; 75 06
                INC     DI                      ; 47
                MOV     cs:[10D0H], DI          ; 2E 89 3E D0 10
evg_sbc_p0_shr:                                 ; chunk:0x1881
                SHR     AL, 1                   ; D0 E8
                SHR     AL, 1                   ; D0 E8
                SHR     AL, 1                   ; D0 E8
                SHR     AL, 1                   ; D0 E8
evg_sbc_p0_emit:                                ; chunk:0x1889
                MOV     DX, 03C5H               ; BA C5 03
                OUT     DX, AL                  ; EE
                POP     DX                      ; 5A
                ; --- plane 1 -------------------------------------------------
                MOV     BP, 0140H               ; BD 40 01
                PUSH    DX                      ; 52
                PUSH    [WORD PTR cs:10CCH]     ; 2E FF 36 CC 10
                ADD     DX, 2                   ; 83 C2 02
                MOV     BX, cs:[10C2H]          ; 2E 8B 1E C2 10
                ADD     BX, 1                   ; 83 C3 01
                SHR     BX, 1                   ; D1 EB
                SHR     BX, 1                   ; D1 EB
                NEG     BX                      ; F7 DB
                MOV     AX, cs:[10CEH]          ; 2E A1 CE 10
                SHR     AX, 1                   ; D1 E8
                ADD     BX, AX                  ; 03 D8
                SHR     DX, 1                   ; D1 EA
                SHR     DX, 1                   ; D1 EA
                MOV     AX, DX                  ; 8B C2
                SHL     AX, 1                   ; D1 E0
                SUB     BP, AX                  ; 2B E8
evg_sbc_p1_row:                                 ; chunk:0x18BA
                MOV     CX, DX                  ; 8B CA
evg_sbc_p1_inner:                               ; chunk:0x18BC
                MOV     AL, [SI]                ; 8A 04
                DEC     SI                      ; 4E
                OR      AL, AL                  ; 0A C0
                JZ      SHORT evg_sbc_p1_skip   ; 74 07
                MOV     [BYTE PTR ES:DI+0A0H], AL ; 26 88 85 A0 00
                STOSB                           ; AA
                DEC     DI                      ; 4F
evg_sbc_p1_skip:                                ; chunk:0x18CA
                INC     DI                      ; 47
                INC     DI                      ; 47
                LOOP    SHORT evg_sbc_p1_inner  ; E2 EE
                ADD     SI, BX                  ; 03 F3
                ADD     DI, BP                  ; 03 FD
                DEC     WORD PTR cs:[10CCH]     ; 2E FF 0E CC 10
                JNZ     SHORT evg_sbc_p1_row    ; 75 E1
                POP     [WORD PTR cs:10CCH]     ; 2E 8F 06 CC 10
                POP     DX                      ; 5A
                PUSH    DX                      ; 52
                XOR     DX, DX                  ; 33 D2
                MOV     AX, cs:[10C8H]          ; 2E A1 C8 10
                CMP     AX, 3                   ; 83 F8 03
                JNZ     SHORT evg_sbc_p1_no_dec ; 75 07
                DEC     WORD PTR cs:[10C6H]     ; 2E FF 0E C6 10
                JMP     SHORT evg_sbc_p1_after  ; EB 05
evg_sbc_p1_no_dec:                              ; chunk:0x18F2
                MUL     WORD PTR cs:[10C4H]     ; 2E F7 26 C4 10
evg_sbc_p1_after:                               ; chunk:0x18F7
                ADD     AX, cs:[10C6H]          ; 2E 03 06 C6 10
                MOV     SI, AX                  ; 8B F0
                MOV     AX, cs:[10C8H]          ; 2E A1 C8 10
                DEC     AX                      ; 48
                AND     AX, 3                   ; 25 03 00
                MOV     cs:[10C8H], AX          ; 2E A3 C8 10
                POP     DX                      ; 5A
                PUSH    DX                      ; 52
                MOV     CL, BYTE PTR cs:[10CAH] ; 2E 8A 0E CA 10
                MOV     DI, cs:[10D0H]          ; 2E 8B 3E D0 10
                MOV     AL, 3                   ; B0 03
                SHL     AL, CL                  ; D2 E0
                ADD     WORD PTR cs:[10CAH], 2  ; 2E 83 06 CA 10 02
                OR      AL, AL                  ; 0A C0
                JNZ     SHORT evg_sbc_p1_al_ok  ; 75 10
                INC     DI                      ; 47
                MOV     cs:[10D0H], DI          ; 2E 89 3E D0 10
                MOV     BYTE PTR cs:[10CAH], 2  ; 2E C6 06 CA 10 02
                MOV     AL, 3                   ; B0 03
                JMP     SHORT evg_sbc_p1_emit   ; EB 16
evg_sbc_p1_al_ok:                               ; chunk:0x1934
                TEST    AL, 0F0H                ; A8 F0
                JZ      SHORT evg_sbc_p1_emit   ; 74 12
                TEST    AL, 0C0H                ; A8 C0
                JNZ     SHORT evg_sbc_p1_shr    ; 75 06
                INC     DI                      ; 47
                MOV     cs:[10D0H], DI          ; 2E 89 3E D0 10
evg_sbc_p1_shr:                                 ; chunk:0x1942
                SHR     AL, 1                   ; D0 E8
                SHR     AL, 1                   ; D0 E8
                SHR     AL, 1                   ; D0 E8
                SHR     AL, 1                   ; D0 E8
evg_sbc_p1_emit:                                ; chunk:0x194A
                MOV     DX, 03C5H               ; BA C5 03
                OUT     DX, AL                  ; EE
                POP     DX                      ; 5A
                ; --- plane 2 -------------------------------------------------
                MOV     BP, 0140H               ; BD 40 01
                PUSH    DX                      ; 52
                PUSH    [WORD PTR cs:10CCH]     ; 2E FF 36 CC 10
                ADD     DX, 1                   ; 83 C2 01
                MOV     BX, cs:[10C2H]          ; 2E 8B 1E C2 10
                ADD     BX, 2                   ; 83 C3 02
                SHR     BX, 1                   ; D1 EB
                SHR     BX, 1                   ; D1 EB
                NEG     BX                      ; F7 DB
                MOV     AX, cs:[10CEH]          ; 2E A1 CE 10
                SHR     AX, 1                   ; D1 E8
                ADD     BX, AX                  ; 03 D8
                SHR     DX, 1                   ; D1 EA
                SHR     DX, 1                   ; D1 EA
                MOV     AX, DX                  ; 8B C2
                SHL     AX, 1                   ; D1 E0
                SUB     BP, AX                  ; 2B E8
evg_sbc_p2_row:                                 ; chunk:0x197B
                MOV     CX, DX                  ; 8B CA
evg_sbc_p2_inner:                               ; chunk:0x197D
                MOV     AL, [SI]                ; 8A 04
                DEC     SI                      ; 4E
                OR      AL, AL                  ; 0A C0
                JZ      SHORT evg_sbc_p2_skip   ; 74 07
                MOV     [BYTE PTR ES:DI+0A0H], AL ; 26 88 85 A0 00
                STOSB                           ; AA
                DEC     DI                      ; 4F
evg_sbc_p2_skip:                                ; chunk:0x198B
                INC     DI                      ; 47
                INC     DI                      ; 47
                LOOP    SHORT evg_sbc_p2_inner  ; E2 EE
                ADD     SI, BX                  ; 03 F3
                ADD     DI, BP                  ; 03 FD
                DEC     WORD PTR cs:[10CCH]     ; 2E FF 0E CC 10
                JNZ     SHORT evg_sbc_p2_row    ; 75 E1
                POP     [WORD PTR cs:10CCH]     ; 2E 8F 06 CC 10
                POP     DX                      ; 5A
                PUSH    DX                      ; 52
                XOR     DX, DX                  ; 33 D2
                MOV     AX, cs:[10C8H]          ; 2E A1 C8 10
                CMP     AX, 3                   ; 83 F8 03
                JNZ     SHORT evg_sbc_p2_no_dec ; 75 07
                DEC     WORD PTR cs:[10C6H]     ; 2E FF 0E C6 10
                JMP     SHORT evg_sbc_p2_after  ; EB 05
evg_sbc_p2_no_dec:                              ; chunk:0x19B3
                MUL     WORD PTR cs:[10C4H]     ; 2E F7 26 C4 10
evg_sbc_p2_after:                               ; chunk:0x19B8
                ADD     AX, cs:[10C6H]          ; 2E 03 06 C6 10
                MOV     SI, AX                  ; 8B F0
                MOV     AX, cs:[10C8H]          ; 2E A1 C8 10
                DEC     AX                      ; 48
                AND     AX, 3                   ; 25 03 00
                MOV     cs:[10C8H], AX          ; 2E A3 C8 10
                POP     DX                      ; 5A
                PUSH    DX                      ; 52
                MOV     CL, BYTE PTR cs:[10CAH] ; 2E 8A 0E CA 10
                MOV     DI, cs:[10D0H]          ; 2E 8B 3E D0 10
                MOV     AL, 3                   ; B0 03
                SHL     AL, CL                  ; D2 E0
                ADD     WORD PTR cs:[10CAH], 2  ; 2E 83 06 CA 10 02
                OR      AL, AL                  ; 0A C0
                JNZ     SHORT evg_sbc_p2_al_ok  ; 75 10
                INC     DI                      ; 47
                MOV     cs:[10D0H], DI          ; 2E 89 3E D0 10
                MOV     BYTE PTR cs:[10CAH], 2  ; 2E C6 06 CA 10 02
                MOV     AL, 3                   ; B0 03
                JMP     SHORT evg_sbc_p2_emit   ; EB 16
evg_sbc_p2_al_ok:                               ; chunk:0x19F5
                TEST    AL, 0F0H                ; A8 F0
                JZ      SHORT evg_sbc_p2_emit   ; 74 12
                TEST    AL, 0C0H                ; A8 C0
                JNZ     SHORT evg_sbc_p2_shr    ; 75 06
                INC     DI                      ; 47
                MOV     cs:[10D0H], DI          ; 2E 89 3E D0 10
evg_sbc_p2_shr:                                 ; chunk:0x1A03
                SHR     AL, 1                   ; D0 E8
                SHR     AL, 1                   ; D0 E8
                SHR     AL, 1                   ; D0 E8
                SHR     AL, 1                   ; D0 E8
evg_sbc_p2_emit:                                ; chunk:0x1A0B
                MOV     DX, 03C5H               ; BA C5 03
                OUT     DX, AL                  ; EE
                POP     DX                      ; 5A
                ; --- plane 3 -------------------------------------------------
                MOV     BP, 0140H               ; BD 40 01
                PUSH    DX                      ; 52
                PUSH    [WORD PTR cs:10CCH]     ; 2E FF 36 CC 10
                ADD     DX, 0                   ; 83 C2 00
                MOV     BX, cs:[10C2H]          ; 2E 8B 1E C2 10
                ADD     BX, 3                   ; 83 C3 03
                SHR     BX, 1                   ; D1 EB
                SHR     BX, 1                   ; D1 EB
                NEG     BX                      ; F7 DB
                MOV     AX, cs:[10CEH]          ; 2E A1 CE 10
                SHR     AX, 1                   ; D1 E8
                ADD     BX, AX                  ; 03 D8
                SHR     DX, 1                   ; D1 EA
                SHR     DX, 1                   ; D1 EA
                MOV     AX, DX                  ; 8B C2
                SHL     AX, 1                   ; D1 E0
                SUB     BP, AX                  ; 2B E8
evg_sbc_p3_row:                                 ; chunk:0x1A3C
                MOV     CX, DX                  ; 8B CA
evg_sbc_p3_inner:                               ; chunk:0x1A3E
                MOV     AL, [SI]                ; 8A 04
                DEC     SI                      ; 4E
                OR      AL, AL                  ; 0A C0
                JZ      SHORT evg_sbc_p3_skip   ; 74 07
                MOV     [BYTE PTR ES:DI+0A0H], AL ; 26 88 85 A0 00
                STOSB                           ; AA
                DEC     DI                      ; 4F
evg_sbc_p3_skip:                                ; chunk:0x1A4C
                INC     DI                      ; 47
                INC     DI                      ; 47
                LOOP    SHORT evg_sbc_p3_inner  ; E2 EE
                ADD     SI, BX                  ; 03 F3
                ADD     DI, BP                  ; 03 FD
                DEC     WORD PTR cs:[10CCH]     ; 2E FF 0E CC 10
                JNZ     SHORT evg_sbc_p3_row    ; 75 E1
                POP     [WORD PTR cs:10CCH]     ; 2E 8F 06 CC 10
                POP     DX                      ; 5A
                JMP     evg_sprite_blit_cleanup      ; E9 6C 02
evg_sprite_blit_flip_variant_c ENDP

; ============================================================================
; evg_sprite_blit_flip_variant_d -- vh-flip (flags=3) flip-variant tail.
; chunk:0x1A64..0x1CCF (620 bytes).
;
; Both axes flipped.  BX uses SAR (signed shift) for negative steps,
; SUB SI, BX instead of ADD SI, BX, and the source byte read is the
; reverse direction.  Falls directly into evg_sprite_blit_cleanup at
; 0x1CD0 (no trailing JMP).
; ============================================================================
evg_sprite_blit_flip_variant_d PROC NEAR
                MOV     BP, 0140H               ; BD 40 01
                PUSH    DX                      ; 52
                PUSH    [WORD PTR cs:10CCH]     ; 2E FF 36 CC 10
                ADD     DX, 3                   ; 83 C2 03
                MOV     BX, cs:[10C2H]          ; 2E 8B 1E C2 10
                ADD     BX, 0                   ; 83 C3 00
                SAR     BX, 1                   ; D1 FB
                SAR     BX, 1                   ; D1 FB
                SHR     DX, 1                   ; D1 EA
                SHR     DX, 1                   ; D1 EA
                MOV     AX, DX                  ; 8B C2
                SHL     AX, 1                   ; D1 E0
                SUB     BP, AX                  ; 2B E8
evg_sbd_p0_row:                                 ; chunk:0x1A86
                MOV     CX, DX                  ; 8B CA
evg_sbd_p0_inner:                               ; chunk:0x1A88
                MOV     AL, [SI]                ; 8A 04
                DEC     SI                      ; 4E
                OR      AL, AL                  ; 0A C0
                JZ      SHORT evg_sbd_p0_skip   ; 74 07
                MOV     [BYTE PTR ES:DI+0A0H], AL ; 26 88 85 A0 00
                STOSB                           ; AA
                DEC     DI                      ; 4F
evg_sbd_p0_skip:                                ; chunk:0x1A96
                INC     DI                      ; 47
                INC     DI                      ; 47
                LOOP    SHORT evg_sbd_p0_inner  ; E2 EE
                SUB     SI, BX                  ; 2B F3
                ADD     DI, BP                  ; 03 FD
                DEC     WORD PTR cs:[10CCH]     ; 2E FF 0E CC 10
                JNZ     SHORT evg_sbd_p0_row    ; 75 E1
                POP     [WORD PTR cs:10CCH]     ; 2E 8F 06 CC 10
                POP     DX                      ; 5A
                PUSH    DX                      ; 52
                XOR     DX, DX                  ; 33 D2
                MOV     AX, cs:[10C8H]          ; 2E A1 C8 10
                CMP     AX, 3                   ; 83 F8 03
                JNZ     SHORT evg_sbd_p0_no_dec ; 75 07
                DEC     WORD PTR cs:[10C6H]     ; 2E FF 0E C6 10
                JMP     SHORT evg_sbd_p0_after  ; EB 05
evg_sbd_p0_no_dec:                              ; chunk:0x1ABE
                MUL     WORD PTR cs:[10C4H]     ; 2E F7 26 C4 10
evg_sbd_p0_after:                               ; chunk:0x1AC3
                ADD     AX, cs:[10C6H]          ; 2E 03 06 C6 10
                MOV     SI, AX                  ; 8B F0
                MOV     AX, cs:[10C8H]          ; 2E A1 C8 10
                DEC     AX                      ; 48
                AND     AX, 3                   ; 25 03 00
                MOV     cs:[10C8H], AX          ; 2E A3 C8 10
                POP     DX                      ; 5A
                PUSH    DX                      ; 52
                MOV     CL, BYTE PTR cs:[10CAH] ; 2E 8A 0E CA 10
                MOV     DI, cs:[10D0H]          ; 2E 8B 3E D0 10
                MOV     AL, 3                   ; B0 03
                SHL     AL, CL                  ; D2 E0
                ADD     WORD PTR cs:[10CAH], 2  ; 2E 83 06 CA 10 02
                OR      AL, AL                  ; 0A C0
                JNZ     SHORT evg_sbd_p0_al_ok  ; 75 10
                INC     DI                      ; 47
                MOV     cs:[10D0H], DI          ; 2E 89 3E D0 10
                MOV     BYTE PTR cs:[10CAH], 2  ; 2E C6 06 CA 10 02
                MOV     AL, 3                   ; B0 03
                JMP     SHORT evg_sbd_p0_emit   ; EB 16
evg_sbd_p0_al_ok:                               ; chunk:0x1B00
                TEST    AL, 0F0H                ; A8 F0
                JZ      SHORT evg_sbd_p0_emit   ; 74 12
                TEST    AL, 0C0H                ; A8 C0
                JNZ     SHORT evg_sbd_p0_shr    ; 75 06
                INC     DI                      ; 47
                MOV     cs:[10D0H], DI          ; 2E 89 3E D0 10
evg_sbd_p0_shr:                                 ; chunk:0x1B0E
                SHR     AL, 1                   ; D0 E8
                SHR     AL, 1                   ; D0 E8
                SHR     AL, 1                   ; D0 E8
                SHR     AL, 1                   ; D0 E8
evg_sbd_p0_emit:                                ; chunk:0x1B16
                MOV     DX, 03C5H               ; BA C5 03
                OUT     DX, AL                  ; EE
                POP     DX                      ; 5A
                ; --- plane 1 -------------------------------------------------
                MOV     BP, 0140H               ; BD 40 01
                PUSH    DX                      ; 52
                PUSH    [WORD PTR cs:10CCH]     ; 2E FF 36 CC 10
                ADD     DX, 2                   ; 83 C2 02
                MOV     BX, cs:[10C2H]          ; 2E 8B 1E C2 10
                ADD     BX, 1                   ; 83 C3 01
                SAR     BX, 1                   ; D1 FB
                SAR     BX, 1                   ; D1 FB
                SHR     DX, 1                   ; D1 EA
                SHR     DX, 1                   ; D1 EA
                MOV     AX, DX                  ; 8B C2
                SHL     AX, 1                   ; D1 E0
                SUB     BP, AX                  ; 2B E8
evg_sbd_p1_row:                                 ; chunk:0x1B3D
                MOV     CX, DX                  ; 8B CA
evg_sbd_p1_inner:                               ; chunk:0x1B3F
                MOV     AL, [SI]                ; 8A 04
                DEC     SI                      ; 4E
                OR      AL, AL                  ; 0A C0
                JZ      SHORT evg_sbd_p1_skip   ; 74 07
                MOV     [BYTE PTR ES:DI+0A0H], AL ; 26 88 85 A0 00
                STOSB                           ; AA
                DEC     DI                      ; 4F
evg_sbd_p1_skip:                                ; chunk:0x1B4D
                INC     DI                      ; 47
                INC     DI                      ; 47
                LOOP    SHORT evg_sbd_p1_inner  ; E2 EE
                SUB     SI, BX                  ; 2B F3
                ADD     DI, BP                  ; 03 FD
                DEC     WORD PTR cs:[10CCH]     ; 2E FF 0E CC 10
                JNZ     SHORT evg_sbd_p1_row    ; 75 E1
                POP     [WORD PTR cs:10CCH]     ; 2E 8F 06 CC 10
                POP     DX                      ; 5A
                PUSH    DX                      ; 52
                XOR     DX, DX                  ; 33 D2
                MOV     AX, cs:[10C8H]          ; 2E A1 C8 10
                CMP     AX, 3                   ; 83 F8 03
                JNZ     SHORT evg_sbd_p1_no_dec ; 75 07
                DEC     WORD PTR cs:[10C6H]     ; 2E FF 0E C6 10
                JMP     SHORT evg_sbd_p1_after  ; EB 05
evg_sbd_p1_no_dec:                              ; chunk:0x1B75
                MUL     WORD PTR cs:[10C4H]     ; 2E F7 26 C4 10
evg_sbd_p1_after:                               ; chunk:0x1B7A
                ADD     AX, cs:[10C6H]          ; 2E 03 06 C6 10
                MOV     SI, AX                  ; 8B F0
                MOV     AX, cs:[10C8H]          ; 2E A1 C8 10
                DEC     AX                      ; 48
                AND     AX, 3                   ; 25 03 00
                MOV     cs:[10C8H], AX          ; 2E A3 C8 10
                POP     DX                      ; 5A
                PUSH    DX                      ; 52
                MOV     CL, BYTE PTR cs:[10CAH] ; 2E 8A 0E CA 10
                MOV     DI, cs:[10D0H]          ; 2E 8B 3E D0 10
                MOV     AL, 3                   ; B0 03
                SHL     AL, CL                  ; D2 E0
                ADD     WORD PTR cs:[10CAH], 2  ; 2E 83 06 CA 10 02
                OR      AL, AL                  ; 0A C0
                JNZ     SHORT evg_sbd_p1_al_ok  ; 75 10
                INC     DI                      ; 47
                MOV     cs:[10D0H], DI          ; 2E 89 3E D0 10
                MOV     BYTE PTR cs:[10CAH], 2  ; 2E C6 06 CA 10 02
                MOV     AL, 3                   ; B0 03
                JMP     SHORT evg_sbd_p1_emit   ; EB 16
evg_sbd_p1_al_ok:                               ; chunk:0x1BB7
                TEST    AL, 0F0H                ; A8 F0
                JZ      SHORT evg_sbd_p1_emit   ; 74 12
                TEST    AL, 0C0H                ; A8 C0
                JNZ     SHORT evg_sbd_p1_shr    ; 75 06
                INC     DI                      ; 47
                MOV     cs:[10D0H], DI          ; 2E 89 3E D0 10
evg_sbd_p1_shr:                                 ; chunk:0x1BC5
                SHR     AL, 1                   ; D0 E8
                SHR     AL, 1                   ; D0 E8
                SHR     AL, 1                   ; D0 E8
                SHR     AL, 1                   ; D0 E8
evg_sbd_p1_emit:                                ; chunk:0x1BCD
                MOV     DX, 03C5H               ; BA C5 03
                OUT     DX, AL                  ; EE
                POP     DX                      ; 5A
                ; --- plane 2 -------------------------------------------------
                MOV     BP, 0140H               ; BD 40 01
                PUSH    DX                      ; 52
                PUSH    [WORD PTR cs:10CCH]     ; 2E FF 36 CC 10
                ADD     DX, 1                   ; 83 C2 01
                MOV     BX, cs:[10C2H]          ; 2E 8B 1E C2 10
                ADD     BX, 2                   ; 83 C3 02
                SAR     BX, 1                   ; D1 FB
                SAR     BX, 1                   ; D1 FB
                SHR     DX, 1                   ; D1 EA
                SHR     DX, 1                   ; D1 EA
                MOV     AX, DX                  ; 8B C2
                SHL     AX, 1                   ; D1 E0
                SUB     BP, AX                  ; 2B E8
evg_sbd_p2_row:                                 ; chunk:0x1BF4
                MOV     CX, DX                  ; 8B CA
evg_sbd_p2_inner:                               ; chunk:0x1BF6
                MOV     AL, [SI]                ; 8A 04
                DEC     SI                      ; 4E
                OR      AL, AL                  ; 0A C0
                JZ      SHORT evg_sbd_p2_skip   ; 74 07
                MOV     [BYTE PTR ES:DI+0A0H], AL ; 26 88 85 A0 00
                STOSB                           ; AA
                DEC     DI                      ; 4F
evg_sbd_p2_skip:                                ; chunk:0x1C04
                INC     DI                      ; 47
                INC     DI                      ; 47
                LOOP    SHORT evg_sbd_p2_inner  ; E2 EE
                SUB     SI, BX                  ; 2B F3
                ADD     DI, BP                  ; 03 FD
                DEC     WORD PTR cs:[10CCH]     ; 2E FF 0E CC 10
                JNZ     SHORT evg_sbd_p2_row    ; 75 E1
                POP     [WORD PTR cs:10CCH]     ; 2E 8F 06 CC 10
                POP     DX                      ; 5A
                PUSH    DX                      ; 52
                XOR     DX, DX                  ; 33 D2
                MOV     AX, cs:[10C8H]          ; 2E A1 C8 10
                CMP     AX, 3                   ; 83 F8 03
                JNZ     SHORT evg_sbd_p2_no_dec ; 75 07
                DEC     WORD PTR cs:[10C6H]     ; 2E FF 0E C6 10
                JMP     SHORT evg_sbd_p2_after  ; EB 05
evg_sbd_p2_no_dec:                              ; chunk:0x1C2C
                MUL     WORD PTR cs:[10C4H]     ; 2E F7 26 C4 10
evg_sbd_p2_after:                               ; chunk:0x1C31
                ADD     AX, cs:[10C6H]          ; 2E 03 06 C6 10
                MOV     SI, AX                  ; 8B F0
                MOV     AX, cs:[10C8H]          ; 2E A1 C8 10
                DEC     AX                      ; 48
                AND     AX, 3                   ; 25 03 00
                MOV     cs:[10C8H], AX          ; 2E A3 C8 10
                POP     DX                      ; 5A
                PUSH    DX                      ; 52
                MOV     CL, BYTE PTR cs:[10CAH] ; 2E 8A 0E CA 10
                MOV     DI, cs:[10D0H]          ; 2E 8B 3E D0 10
                MOV     AL, 3                   ; B0 03
                SHL     AL, CL                  ; D2 E0
                ADD     WORD PTR cs:[10CAH], 2  ; 2E 83 06 CA 10 02
                OR      AL, AL                  ; 0A C0
                JNZ     SHORT evg_sbd_p2_al_ok  ; 75 10
                INC     DI                      ; 47
                MOV     cs:[10D0H], DI          ; 2E 89 3E D0 10
                MOV     BYTE PTR cs:[10CAH], 2  ; 2E C6 06 CA 10 02
                MOV     AL, 3                   ; B0 03
                JMP     SHORT evg_sbd_p2_emit   ; EB 16
evg_sbd_p2_al_ok:                               ; chunk:0x1C6E
                TEST    AL, 0F0H                ; A8 F0
                JZ      SHORT evg_sbd_p2_emit   ; 74 12
                TEST    AL, 0C0H                ; A8 C0
                JNZ     SHORT evg_sbd_p2_shr    ; 75 06
                INC     DI                      ; 47
                MOV     cs:[10D0H], DI          ; 2E 89 3E D0 10
evg_sbd_p2_shr:                                 ; chunk:0x1C7C
                SHR     AL, 1                   ; D0 E8
                SHR     AL, 1                   ; D0 E8
                SHR     AL, 1                   ; D0 E8
                SHR     AL, 1                   ; D0 E8
evg_sbd_p2_emit:                                ; chunk:0x1C84
                MOV     DX, 03C5H               ; BA C5 03
                OUT     DX, AL                  ; EE
                POP     DX                      ; 5A
                ; --- plane 3 -------------------------------------------------
                MOV     BP, 0140H               ; BD 40 01
                PUSH    DX                      ; 52
                PUSH    [WORD PTR cs:10CCH]     ; 2E FF 36 CC 10
                ADD     DX, 0                   ; 83 C2 00
                MOV     BX, cs:[10C2H]          ; 2E 8B 1E C2 10
                ADD     BX, 3                   ; 83 C3 03
                SAR     BX, 1                   ; D1 FB
                SAR     BX, 1                   ; D1 FB
                SHR     DX, 1                   ; D1 EA
                SHR     DX, 1                   ; D1 EA
                MOV     AX, DX                  ; 8B C2
                SHL     AX, 1                   ; D1 E0
                SUB     BP, AX                  ; 2B E8
evg_sbd_p3_row:                                 ; chunk:0x1CAB
                MOV     CX, DX                  ; 8B CA
evg_sbd_p3_inner:                               ; chunk:0x1CAD
                MOV     AL, [SI]                ; 8A 04
                DEC     SI                      ; 4E
                OR      AL, AL                  ; 0A C0
                JZ      SHORT evg_sbd_p3_skip   ; 74 07
                MOV     [BYTE PTR ES:DI+0A0H], AL ; 26 88 85 A0 00
                STOSB                           ; AA
                DEC     DI                      ; 4F
evg_sbd_p3_skip:                                ; chunk:0x1CBB
                INC     DI                      ; 47
                INC     DI                      ; 47
                LOOP    SHORT evg_sbd_p3_inner  ; E2 EE
                SUB     SI, BX                  ; 2B F3
                ADD     DI, BP                  ; 03 FD
                DEC     WORD PTR cs:[10CCH]     ; 2E FF 0E CC 10
                JNZ     SHORT evg_sbd_p3_row    ; 75 E1
                POP     [WORD PTR cs:10CCH]     ; 2E 8F 06 CC 10
                POP     DX                      ; 5A
                ; falls through directly into evg_sprite_blit_cleanup @ 0x1CD0
evg_sprite_blit_flip_variant_d ENDP

; ============================================================================
; evg_sprite_blit_cleanup -- shared exit/cleanup for evg_sprite_blit_master.
; chunk:0x1CD0..0x1CD8 (9 bytes).  NEAR.
;
; Restores DS/ES/SI/DI, releases the BP local frame, and RETFs back
; to the master's caller.  Reached either by direct fall-through from
; flip_variant_d or by `JMP evg_sprite_blit_cleanup` from variants a,
; b, c -- AND by `JMP evg_sbm_to_cleanup` calls inside
; evg_sprite_blit_master's clipping branches when the clipped sprite
; ends up empty.
; ============================================================================
evg_sprite_blit_cleanup PROC NEAR
                POP     DS                      ; 1F
                POP     ES                      ; 07
                POP     SI                      ; 5E
                POP     DI                      ; 5F
                ADD     SP, 0AH                 ; 83 C4 0A
                POP     BP                      ; 5D
                RETF                            ; CB
evg_sprite_blit_cleanup ENDP

; ============================================================================
; evg_vsync_wait -- vsync alignment + V7 bank flip (page flip primitive).
; chunk:0x1CD9..0x1D18 (64 bytes), vtable slot 8.
;
; ABI:
;   [BP+6]  ushort  do_wait  -- non-zero = busy-wait for vertical
;                               retrace bit on port 0x3DA.
;
; Side effect: swaps DS:[0x14] with DS:[0x12] (front/back-buffer index),
; programs Sequencer 0xF6 with (DS:[0x12] << 4) -- this puts the new
; page index into the F6.CRTB field (bits 5-4 -- the CRT-bank-select
; bits, see Ferraro Fig 22.11), so the CRTC starts scanning out from
; the newly-flipped page on the next retrace.
; ============================================================================
evg_vsync_wait  PROC    FAR
                PUSH    BP                      ; 55
                MOV     BP, SP                  ; 8B EC
                PUSH    ES                      ; 06
                PUSH    DS                      ; 1E
                MOV     DS, cs:[0134H]          ; 2E 8E 1E 34 01
                MOV     AX, ds:[GfxContext.wVgaPage2Base]          ; A1 12 00
                MOV     CX, AX                  ; 8B C8
                XCHG    ds:[GfxContext.wVgaFrontPageBase], AX          ; 87 06 14 00
                MOV     ds:[GfxContext.wVgaPage2Base], AX          ; A3 12 00
                SHL     CX, 1                   ; D1 E1
                SHL     CX, 1                   ; D1 E1
                SHL     CX, 1                   ; D1 E1
                SHL     CX, 1                   ; D1 E1
                MOV     DX, 03C4H               ; BA C4 03
                MOV     AL, 0F6H                ; B0 F6
                MOV     AH, CL                  ; 8A E1
                OUT     DX, AX                  ; EF
                MOV     AX, [BP+6]              ; 8B 46 06
                OR      AX, AX                  ; 0B C0
                JZ      SHORT evg_vsw_exit      ; 74 0F
                MOV     CL, 8                   ; B1 08
                MOV     DX, 03DAH               ; BA DA 03
evg_vsw_wait_low:                               ; chunk:0x1D0B
                IN      AL, DX                  ; EC
                AND     AL, CL                  ; 22 C1
                JNZ     SHORT evg_vsw_wait_low  ; 75 FB
evg_vsw_wait_high:                              ; chunk:0x1D10
                IN      AL, DX                  ; EC
                AND     AL, CL                  ; 22 C1
                JZ      SHORT evg_vsw_wait_high ; 74 FB
evg_vsw_exit:                                   ; chunk:0x1D15
                POP     DS                      ; 1F
                POP     ES                      ; 07
                POP     BP                      ; 5D
                RETF                            ; CB
evg_vsync_wait  ENDP

; ============================================================================
; evg_set_bank_trivial -- vtable slot 28: trivial bank-select wrapper.
; chunk:0x1D19..0x1D25 (13 bytes).
;
; Loads chunk-scratch DS and tail-calls evg_set_sequencer_bank, then
; reports the active video segment in AX (returns ES on exit).
; ============================================================================
evg_set_bank_trivial PROC FAR
                PUSH    DS                      ; 1E
                MOV     DS, cs:[0134H]          ; 2E 8E 1E 34 01
                CALL    NEAR PTR evg_set_sequencer_bank ; E8 04 00
                MOV     AX, ES                  ; 8C C0
                POP     DS                      ; 1F
                RETF                            ; CB
evg_set_bank_trivial ENDP

; ============================================================================
; evg_set_sequencer_bank -- Video Seven bank-select via Sequencer 0xF6.
; chunk:0x1D26..0x1D47 (34 bytes).  NEAR.
;
; Sets the V7 SR-F6 register's CPU-bank bits to the *bitwise OR* of
; (DS:[0x16] << 2) | DS:[0x18] and the register's *previous* contents
; (IN AL,DX readback then OR + writeback).  This is the simplified
; read-modify-write idiom Ferraro Listing 22.6 documents -- but note
; it only OR-merges; no pre-existing bits in F6 are cleared by this
; routine.  Callers that want to REPLACE (not augment) the previous
; selection must zero F6 first.
;
; Also loads ES with the A000:0000 video segment for subsequent
; writes and preserves DX and AX via PUSH/POP.
;
; Sequencer index 0xF6 is NOT a standard VGA register; it is the
; Video Seven extension "1 MB RAM Bank Select" (Ferraro Fig 22.11,
; vgadoc/VIDEO7.TXT lines 255-260).
; ============================================================================
evg_set_sequencer_bank PROC NEAR
                PUSH    DX                      ; 52
                PUSH    AX                      ; 50
                MOV     DX, 03C4H               ; BA C4 03
                MOV     AL, 0F6H                ; B0 F6
                OUT     DX, AL                  ; EE
                INC     DX                      ; 42
                MOV     AX, ds:[GfxContext.wGfxBlitSrcPage]          ; A1 16 00
                SHL     AX, 1                   ; D1 E0
                SHL     AX, 1                   ; D1 E0
                OR      AX, ds:[GfxContext.wGfxBlitDstPage]          ; 0B 06 18 00
                MOV     AH, AL                  ; 8A E0
                IN      AL, DX                  ; EC
                OR      AL, AH                  ; 0A C4
                OUT     DX, AL                  ; EE
                MOV     AX, 0A000H              ; B8 00 A0
                MOV     ES, AX                  ; 8E C0
                POP     AX                      ; 58
                POP     DX                      ; 5A
                RET                             ; C3
evg_set_sequencer_bank ENDP

; ============================================================================
; evg_present -- present a rect from off-screen to visible buffer.
; chunk:0x1D48..0x1DAE (103 bytes), vtable slot 4.
;
; ABI:
;   [BP+6]   ushort  src_offset
;   [BP+8]   ushort  src_x
;   [BP+0A]  ushort  src_y_lut_idx
;   [BP+0C]  ushort  rows
; Programs Sequencer reg 0x02 (Map-Mask) = 0x0F (all 4 planes
; selected) and GC reg 0x05 = 0x41 (write-mode 1: every CPU write
; copies the contents of the four plane read-latches into the target
; byte; cf. FreeVGA "Graphics Mode Register").  Then performs a
; latch-copy blit: each LODSB reads one source byte AND, as a side
; effect of the read, fills all four plane latches with the source's
; four-plane content at that byte offset.  Each STOSB writes the
; latched four-plane content to the destination's same byte offset
; in one bus cycle.  This is the standard latch-copy idiom that
; works in BOTH 16-colour planar and unchained-256 / Mode X: each
; pair of LODSB+STOSB transfers four pixels (one byte position
; across all four planes) in two CPU instructions.
;
; Steps DI by 0xA0 (160 = 640 px / 4 px-per-plane-byte) per row.
; Restores GC reg 0x05 = 0x40 (write-mode 0) before returning so
; subsequent per-plane writes by other primitives behave normally.
; ============================================================================
evg_present     PROC    FAR
                PUSH    BP                      ; 55
                MOV     BP, SP                  ; 8B EC
                PUSH    SI                      ; 56
                PUSH    DI                      ; 57
                PUSH    DS                      ; 1E
                PUSH    ES                      ; 06
                MOV     DS, cs:[0134H]          ; 2E 8E 1E 34 01
                MOV     SI, [BP+6]              ; 8B 76 06
                MOV     BX, [BP+0AH]            ; 8B 5E 0A
                SHL     BX, 1                   ; D1 E3
                MOV     DX, [BP+0CH]            ; 8B 56 0C
                SHL     DX, 1                   ; D1 E2
                MOV     BP, [BP+8]              ; 8B 6E 08
                SHL     BP, 1                   ; D1 E5
                SHL     BP, 1                   ; D1 E5
                MOV     BP, ds:[WORD PTR BP+pRow_offset_lut] ; 3E 8B AE F2 06
                CALL    NEAR PTR evg_set_sequencer_bank ; E8 B6 FF
                MOV     AX, ES                  ; 8C C0
                MOV     DS, AX                  ; 8E D8
                SHR     SI, 1                   ; D1 EE
                ADD     BX, 3                   ; 83 C3 03
                SHR     BX, 1                   ; D1 EB
                SHR     BX, 1                   ; D1 EB
                ADD     BP, SI                  ; 03 EE
                PUSH    DX                      ; 52
                MOV     DX, 03C4H               ; BA C4 03
                MOV     AX, 0F02H               ; B8 02 0F
                OUT     DX, AX                  ; EF
                MOV     DX, 03CEH               ; BA CE 03
                MOV     AX, 4105H               ; B8 05 41
                OUT     DX, AX                  ; EF
                POP     DX                      ; 5A
evg_pre_row:                                    ; chunk:0x1D8F
                MOV     SI, BP                  ; 8B F5
                MOV     DI, SI                  ; 8B FE
                MOV     CX, BX                  ; 8B CB
evg_pre_inner:                                  ; chunk:0x1D95
                LODSB                           ; AC
                STOSB                           ; AA
                LOOP    SHORT evg_pre_inner     ; E2 FC
                ADD     BP, 0A0H                ; 81 C5 A0 00
                DEC     DX                      ; 4A
                JNZ     SHORT evg_pre_row       ; 75 EF
                MOV     DX, 03CEH               ; BA CE 03
                MOV     AX, 4005H               ; B8 05 40
                OUT     DX, AX                  ; EF
                POP     ES                      ; 07
                POP     DS                      ; 1F
                POP     DI                      ; 5F
                POP     SI                      ; 5E
                POP     BP                      ; 5D
                RETF                            ; CB
evg_present     ENDP

; chunk:0x1DAD..0x1DAE -- 2 bytes of zero padding (compiler-emitted
; alignment after the FAR PROC end).
                DB      2 DUP (0)

; ============================================================================
; evg_save_rect_to_buffer -- vtable slot 5: rect save to far buffer.
; chunk:0x1DAF..0x1E1F (113 bytes).
;
; Pulls a rect from the Mode-X framebuffer back into a caller-supplied
; flat byte buffer at [BP+6]:[BP+8].  Cycles GC reg 0x04 (Read-Map-
; Select) through planes 0, 1, 2, 3 so each read returns the plane's
; byte at the current offset.  Writes the planes interleaved in the
; output buffer: out[0,4,8,...] = plane 0 bytes, out[1,5,9,...] =
; plane 1 bytes, etc.  This produces a packed contiguous byte stream
; that evg_paste_rect_from_buffer can later restore byte-for-byte.
; ============================================================================
evg_save_rect_to_buffer PROC FAR
                PUSH    BP                      ; 55
                MOV     BP, SP                  ; 8B EC
                PUSH    DI                      ; 57
                PUSH    SI                      ; 56
                PUSH    DS                      ; 1E
                MOV     DS, cs:[0134H]          ; 2E 8E 1E 34 01
                MOV     AX, [BP+0AH]            ; 8B 46 0A
                SHL     AX, 1                   ; D1 E0
                MOV     BX, [BP+0CH]            ; 8B 5E 0C
                SHL     BX, 1                   ; D1 E3
                SHL     BX, 1                   ; D1 E3
                MOV     SI, [WORD PTR BX+pRow_offset_lut] ; 8B B7 F2 06
                MOV     BX, AX                  ; 8B D8
                SHR     AX, 1                   ; D1 E8
                SHR     AX, 1                   ; D1 E8
                ADD     SI, AX                  ; 03 F0
                AND     BX, 3                   ; 83 E3 03
                MOV     DX, 03CEH               ; BA CE 03
                MOV     AL, 4                   ; B0 04
                OUT     DX, AL                  ; EE
                INC     DX                      ; 42
                MOV     AX, [BP+0EH]            ; 8B 46 0E
                SHL     AX, 1                   ; D1 E0
                MOV     cs:[1DADH], AX          ; 2E A3 AD 1D
                CALL    NEAR PTR evg_set_sequencer_bank ; E8 3E FF
                MOV     AX, ES                  ; 8C C0
                MOV     DS, AX                  ; 8E D8
                MOV     DI, [BP+6]              ; 8B 7E 06
                MOV     AX, [BP+8]              ; 8B 46 08
                MOV     ES, AX                  ; 8E C0
                MOV     AH, BL                  ; 8A E3
                MOV     BX, [BP+10H]            ; 8B 5E 10
                SHL     BX, 1                   ; D1 E3
                MOV     BP, SI                  ; 8B EE
evg_srtb_row:                                   ; chunk:0x1DFD
                MOV     CX, cs:[1DADH]          ; 2E 8B 0E AD 1D
                MOV     AL, AH                  ; 8A C4
                MOV     SI, BP                  ; 8B F5
evg_srtb_inner:                                 ; chunk:0x1E06
                OUT     DX, AL                  ; EE
                MOVSB                           ; A4
                INC     AL                      ; FE C0
                CMP     AL, 4                   ; 3C 04
                JNZ     SHORT evg_srtb_no_reset ; 75 03
                INC     SI                      ; 46
                XOR     AL, AL                  ; 32 C0
evg_srtb_no_reset:                              ; chunk:0x1E11
                DEC     SI                      ; 4E
                LOOP    SHORT evg_srtb_inner    ; E2 F2
                ADD     BP, 0A0H                ; 81 C5 A0 00
                DEC     BX                      ; 4B
                JNZ     SHORT evg_srtb_row      ; 75 E2
                POP     DS                      ; 1F
                POP     SI                      ; 5E
                POP     DI                      ; 5F
                POP     BP                      ; 5D
                RETF                            ; CB
evg_save_rect_to_buffer ENDP

; ============================================================================
; evg_sprite_buffer_size -- compute byte size for a w*h sprite.
; chunk:0x1E20..0x1E35 (22 bytes), vtable slot 6.
;
; Returns DX:AX = (w * h * 4) -- i.e. width*height in 4-plane bytes.
; ============================================================================
evg_sprite_buffer_size PROC FAR
                PUSH    BP                      ; 55
                MOV     BP, SP                  ; 8B EC
                MOV     AX, [BP+6]              ; 8B 46 06
                CWD                             ; 99
                MUL     WORD PTR [BP+8]         ; F7 66 08
                SHL     AX, 1                   ; D1 E0
                RCL     DX, 1                   ; D1 D2
                SHL     AX, 1                   ; D1 E0
                RCL     DX, 1                   ; D1 D2
                POP     BP                      ; 5D
                RETF                            ; CB
evg_sprite_buffer_size ENDP

; chunk:0x1E34..0x1E35 -- 2 bytes of zero padding before
; evg_paste_rect_from_buffer.
; (Also overlapped by an internal storage write at CS:[0x1E34] inside
; evg_paste_rect_from_buffer that caches the doubled row count.)
                DB      2 DUP (0)

; ============================================================================
; evg_paste_rect_from_buffer -- inverse of evg_save_rect_to_buffer.
; chunk:0x1E36..0x1EA8 (115 bytes), vtable slot 7.
;
; Pastes a previously-saved rect (held in [BP+6]:[BP+8]) back into the
; Mode-X framebuffer.  Cycles the Sequencer Map-Mask through
; (1 << (x & 3)), (1 << ((x+1) & 3)), ... so each successive source
; byte is steered to the next plane.  When the rotating mask wraps
; from plane 3 back to plane 0, DI is bumped to the next byte offset.
; ============================================================================
evg_paste_rect_from_buffer PROC FAR
                PUSH    BP                      ; 55
                MOV     BP, SP                  ; 8B EC
                PUSH    SI                      ; 56
                PUSH    DI                      ; 57
                PUSH    DS                      ; 1E
                MOV     DS, cs:[0134H]          ; 2E 8E 1E 34 01
                MOV     AX, [BP+0AH]            ; 8B 46 0A
                SHL     AX, 1                   ; D1 E0
                MOV     BX, [BP+0CH]            ; 8B 5E 0C
                SHL     BX, 1                   ; D1 E3
                SHL     BX, 1                   ; D1 E3
                MOV     DI, [WORD PTR BX+pRow_offset_lut] ; 8B BF F2 06
                MOV     BX, AX                  ; 8B D8
                SHR     AX, 1                   ; D1 E8
                SHR     AX, 1                   ; D1 E8
                ADD     DI, AX                  ; 03 F8
                AND     BX, 3                   ; 83 E3 03
                MOV     CX, BX                  ; 8B CB
                CALL    NEAR PTR evg_set_sequencer_bank ; E8 C5 FE
                MOV     DX, 03C4H               ; BA C4 03
                MOV     AL, 2                   ; B0 02
                OUT     DX, AL                  ; EE
                INC     DX                      ; 42
                MOV     BX, [BP+10H]            ; 8B 5E 10
                SHL     BX, 1                   ; D1 E3
                MOV     AX, [BP+0EH]            ; 8B 46 0E
                SHL     AX, 1                   ; D1 E0
                MOV     cs:[1E34H], AX          ; 2E A3 34 1E
                MOV     SI, [BP+6]              ; 8B 76 06
                MOV     AX, [BP+8]              ; 8B 46 08
                MOV     DS, AX                  ; 8E D8
                MOV     AL, 1                   ; B0 01
                SHL     AL, CL                  ; D2 E0
                MOV     AH, AL                  ; 8A E0
                MOV     BP, DI                  ; 8B EF
evg_prfb_row:                                   ; chunk:0x1E86
                MOV     CX, cs:[1E34H]          ; 2E 8B 0E 34 1E
                MOV     AL, AH                  ; 8A C4
                MOV     DI, BP                  ; 8B FD
evg_prfb_inner:                                 ; chunk:0x1E8F
                OUT     DX, AL                  ; EE
                MOVSB                           ; A4
                SHL     AL, 1                   ; D0 E0
                CMP     AL, 10H                 ; 3C 10
                JNZ     SHORT evg_prfb_al_ok    ; 75 03
                INC     DI                      ; 47
                MOV     AL, 1                   ; B0 01
evg_prfb_al_ok:                                 ; chunk:0x1E9A
                DEC     DI                      ; 4F
                LOOP    SHORT evg_prfb_inner    ; E2 F2
                ADD     BP, 0A0H                ; 81 C5 A0 00
                DEC     BX                      ; 4B
                JNZ     SHORT evg_prfb_row      ; 75 E2
                POP     DS                      ; 1F
                POP     DI                      ; 5F
                POP     SI                      ; 5E
                POP     BP                      ; 5D
                RETF                            ; CB
evg_paste_rect_from_buffer ENDP

; ============================================================================
; evg_getpixel -- read one pixel from the Mode-X framebuffer.
; chunk:0x1EA9..0x1EDF (55 bytes), vtable slot 21.
;
; ABI:
;   [BP+6]  ushort  x
;   [BP+8]  ushort  y
; Returns AX = pixel value (8-bit colour, 0..255, zero-extended in AH).
;
; Sets GC reg 0x04 (Read-Map-Select) = (x & 3) so the subsequent
; A000-segment read returns the byte from the plane that owns pixel
; (x,y), then loads the byte at offset (y * 160 + x/4) within that
; plane.
; ============================================================================
evg_getpixel    PROC    FAR
                PUSH    BP                      ; 55
                MOV     BP, SP                  ; 8B EC
                PUSH    DS                      ; 1E
                MOV     DS, cs:[0134H]          ; 2E 8E 1E 34 01
                MOV     BX, [BP+8]              ; 8B 5E 08
                SHL     BX, 1                   ; D1 E3
                SHL     BX, 1                   ; D1 E3
                MOV     BX, [WORD PTR BX+pRow_offset_lut] ; 8B 9F F2 06
                MOV     AX, [BP+6]              ; 8B 46 06
                SHL     AX, 1                   ; D1 E0
                MOV     CX, AX                  ; 8B C8
                SHR     CX, 1                   ; D1 E9
                SHR     CX, 1                   ; D1 E9
                ADD     BX, CX                  ; 03 D9
                AND     AX, 3                   ; 25 03 00
                MOV     DX, 03CEH               ; BA CE 03
                MOV     AH, AL                  ; 8A E0
                MOV     AL, 4                   ; B0 04
                OUT     DX, AX                  ; EF
                CALL    NEAR PTR evg_set_sequencer_bank ; E8 4E FE
                MOV     AL, ES:[BX]             ; 26 8A 07
                XOR     AH, AH                  ; 32 E4
                POP     DS                      ; 1F
                POP     BP                      ; 5D
                RETF                            ; CB
evg_getpixel    ENDP

; ============================================================================
; evg_putpixel -- write one *logical* pixel as a 2x2 block of 8-bit colour.
; chunk:0x1EE0..0x1F26 (71 bytes), vtable slot 22.
;
; ABI:
;   [BP+6]   ushort  x        -- logical X in the 320-wide source space
;   [BP+8]   ushort  y        -- logical Y in the 200-tall source space
;   [BP+0A]  uchar   colour   -- full 8-bit colour value (0..255)
;
; Krondor renders to a logical 320x200 surface; the EVG driver scales
; that 2x in each axis to fit the 640x400 mode.  The function therefore
; emits FOUR framebuffer pixels per call -- the 2x2 block at
; physical (2x..2x+1, 2y..2y+1):
;
;   - The two horizontal pixels: Sequencer Map-Mask is set to a
;     2-plane mask (`(0x03 << ((2x) mod 4))`) shifted to the plane
;     pair owning physical pixels 2x and 2x+1; when 2x mod 4 == 3
;     the right pixel crosses a byte boundary, so BX is incremented
;     and the mask wraps to `(1 << 0) | (carry)` -- the `TEST CX,4
;     / INC BX / AND CX,3` branch handles that case.
;   - The two vertical pixels: the colour byte is written at ES:[BX]
;     AND at ES:[BX + 0xA0], i.e. one row below (0xA0 = stride in
;     bytes for one plane).
;
; The colour byte is the full 8-bit palette index, not a 4-bit nibble.
; ============================================================================
evg_putpixel    PROC    FAR
                PUSH    BP                      ; 55
                MOV     BP, SP                  ; 8B EC
                PUSH    DS                      ; 1E
                MOV     DS, cs:[0134H]          ; 2E 8E 1E 34 01
                MOV     BX, [BP+8]              ; 8B 5E 08
                SHL     BX, 1                   ; D1 E3
                SHL     BX, 1                   ; D1 E3
                MOV     BX, [WORD PTR BX+pRow_offset_lut] ; 8B 9F F2 06
                MOV     CX, [BP+6]              ; 8B 4E 06
                SHL     CX, 1                   ; D1 E1
                AND     CX, 7                   ; 83 E1 07
                TEST    CX, 4                   ; F7 C1 04 00
                JZ      SHORT evg_pp_lo         ; 74 04
                AND     CX, 3                   ; 83 E1 03
                INC     BX                      ; 43
evg_pp_lo:                                      ; chunk:0x1F06
                MOV     DX, 03C4H               ; BA C4 03
                MOV     AX, 0302H               ; B8 02 03
                SHL     AH, CL                  ; D2 E4
                OUT     DX, AX                  ; EF
                MOV     AX, [BP+6]              ; 8B 46 06
                SHR     AX, 1                   ; D1 E8
                ADD     BX, AX                  ; 03 D8
                CALL    NEAR PTR evg_set_sequencer_bank ; E8 0D FE
                MOV     AL, [BP+0AH]            ; 8A 46 0A
                MOV     ES:[BX], AL             ; 26 88 07
                MOV     [BYTE PTR ES:BX+0A0H], AL ; 26 88 87 A0 00
                POP     DS                      ; 1F
                POP     BP                      ; 5D
                RETF                            ; CB
evg_putpixel    ENDP

                END     _start
