; ============================================================================
; Sx.SSM.ADS.bin -- Dynamix DUDE-format Disney Sound Source driver, v2.8
;
; Shipped with "Betrayal at Krondor" (Dynamix / Sierra, 1993).
;
; Packing: TASM + TLINK produce an MZ .EXE; PACKOVL strips the MZ header to
; the flat ORG-0 image, then LZW-packs it into SX.OVL.
; ============================================================================

; ----------------------------------------------------------------------------
; What this driver is
;
; A sound driver is a small piece of code that the game loads at startup and
; calls every time it wants to make a sound. Different sound cards need
; different code, so the game ships one driver per supported card (AdLib,
; Sound Blaster, Pro AudioSpectrum, Roland MT-32, Disney Sound Source, ...)
; and picks the right one at runtime based on the user's "sound setup"
; choice.
;
; This file is the Disney Sound Source (DSS) driver. The DSS is *not* a
; synthesizer; it is a Covox-style 8-bit DAC that plugs into the PC's
; parallel printer port (LPT1) and plays back pre-recorded digital audio
; samples. Unlike the AdLib driver (which feeds MIDI-style note events to
; an FM-synth chip), this driver streams raw PCM bytes from a .SOL sample
; file on disk and clocks them out to the DAC at the chip's fixed playback
; rate.
;
; About a third of the file is hardware control (detect-LPT probe, FIFO
; toggling, sample clock-out loop); a third is sample-rate decimation
; (the .SOL files arrive at the original-recording rate -- 11 kHz, 22 kHz,
; etc. -- and have to be down-sampled to the DSS's fixed ~7000 Hz on the
; fly); and a third is bookkeeping (DOS file I/O, double-buffering, IRQ
; re-entry guards). The slot-handler dispatch table at offset 0x0891
; routes the game's 16 ABI calls to the right entry points.
;
; The driver also hooks INT 10h (BIOS video) and INT 33h (mouse) with thin
; stubs that set a "do not re-enter the buffer pump while a BIOS/mouse
; call is running" flag. See ads_int10_stub / ads_int33_stub.
; ----------------------------------------------------------------------------

; ----------------------------------------------------------------------------
; About the Disney Sound Source hardware
;
; The Disney Sound Source (DSS) is a $15 dongle Disney sold in 1992 for the
; Sound Source line of children's games. Mechanically it is a parallel-port
; pass-through (the printer cable plugs into it, the dongle plugs into the
; PC's LPT port), so the host CPU talks to it by writing bytes to the LPT
; data-port range -- there are no card-specific I/O ports.
;
; The dongle contains:
;
;   * a 16-byte internal FIFO buffer, and
;   * an 8-bit DAC clocked at a fixed ~7000 Hz by an internal oscillator.
;
; Each FIFO entry is a 7-bit unsigned PCM sample (top bit ignored). The
; FIFO drains to the DAC at the fixed rate; the host's job is to keep it
; full. The host writes one sample at a time by:
;
;   1. Writing the sample byte to the LPT data port (base + 0).
;   2. "Clocking" the FIFO by toggling LPT control-port bits 2/3:
;        first write 0x0C to the control port,
;        then write 0x04 to the control port.
;      This rising edge is what tells the dongle "latch the data byte
;      into the FIFO".
;   3. Polling the LPT status port (base + 1) bit 6 to know whether the
;      FIFO has space for the next sample (bit 6 set = ready / empty
;      slot available; bit 6 clear = FIFO is full, host must wait).
;
; The LPT base address (typically 0x378 for LPT1, 0x278 for LPT2) is read
; from the BIOS data area (40:08, 40:0A) at driver init time -- see
; ads_detect_wrapper / ads_detect_lpt.
;
;   I/O port           Offset    Bit     Meaning
;   -----------------  --------  ------  -------------------------------
;   LPT base + 0       data      n/a     7-bit unsigned PCM sample byte
;   LPT base + 1       status    bit 6   1 = FIFO ready (write more)
;                                        0 = FIFO full (wait)
;   LPT base + 2       control   bit 2   bit-2 = strobe (0x04)
;                                bit 3   bit-3 = data-latch (0x08)
;                                        host writes 0x0C (both set)
;                                        then 0x04 (drop bit 3) to clock
;
; A successful DSS detection at ads_detect_lpt looks like:
;
;     write 0x7F to data port      ; harmless mid-scale sample byte
;     write 0x0C to control port   ; strobe high + latch high
;     delay ~1000 cycles           ; let the dongle settle
;     write 0x04 to control port   ; drop latch (clock the sample in)
;     poll status port bit 6       ; expect bit 6 set within 100 retries
;
; ----------------------------------------------------------------------------

; ----------------------------------------------------------------------------
; About the DUDE dispatch ABI (interface 2.8, "auddisny" tag)
;
; "DUDE" is Dynamix's internal sound-driver format. Every driver in the
; family is a flat binary that begins with a 0x36-byte header containing
; two magic numbers (0x87654321 and 0xFEDCBA98), an ASCII subsystem tag,
; a human-readable device-name string, a driver-kind dword, and an 8-byte
; initial-state / curve table.
;
; The v2.8 variant used here (the same variant as APA / SBP / ASB)
; distinguishes itself from earlier 2.x drivers by carrying an 8-byte
; ASCII tag instead of 6. The byte at offset 0x09 is the tag-length (8),
; not an interface-minor version as in some other drivers. The 8 bytes
; at 0x0A are the tag itself, "auddisny" -- "AUDio DISNeY".
;
; The game communicates with this driver through a far call into the
; dispatch trampoline at offset 0x08B1. Before the call:
;
;   AX    = slot index (0..15)               -- which operation
;   SS:SI = pointer to slot arguments        -- per-slot argument block
;
; The 18-byte trampoline at 0x08B1:
;
;     PUSH DS                                ; save caller's DS
;     MOV  BX, AX
;     SHL  BX, 1                             ; index -> byte offset
;     MOV  AX, CS
;     MOV  DS, AX                            ; DS := CS for the handler
;     CALL CS:[BX + ads_func_table]          ; near indirect
;     POP  DS
;     OR   AX, AX                            ; set flags from result
;     RETF                                   ; far return
;
; The 16 slots:
;
;   Slot  0  ads_slot_00_init     -- detect chip, hook INT 10h / INT 33h
;   Slot  1  ads_slot_01_play     -- begin / continue playback
;   Slot  2  ads_slot_02          -- shutdown: unhook ints, close file
;   Slot  3  ads_slot_03          -- init playback (rate + buffer geometry)
;   Slot  4  ads_slot_04          -- read state, write playback-end flag
;   Slot  5  ads_slot_05          -- stop-playback wrapper of slot_12
;   Slot  6  ads_slot_06          -- set sample rate from arg
;   Slot  7  ads_slot_07          -- no-op RET stub
;   Slot  8  ads_slot_08          -- clear "no kick on EOF" flag
;   Slot  9  ads_slot_09          -- load chunk from file (large handler)
;   Slot 10  ads_slot_10          -- resume from paused
;   Slot 11  ads_slot_11          -- IRQ setup / reset key state
;   Slot 12  ads_slot_12_helper_set_flag -- set "playback stopped" flag
;   Slot 13  ads_slot_13          -- query position (3 dwords into SS:SI)
;   Slot 14  ads_slot_14          -- xor ax,ax; ret  (no-op)
;   Slot 15  ads_slot_15          -- 1-byte RET stub
; ----------------------------------------------------------------------------

; ----------------------------------------------------------------------------
; How to read this source
;
; - Lines like `MOV BX, AX` are CPU instructions ("opcodes"). The first
;   operand is the destination, the second is the source -- read it as
;   "BX = AX". This is the "Intel" order; AT&T-style "MOV AX, BX" with
;   the destination second is a different convention and is not used
;   here.
;
; - Lines like `ads_state DB 2139 DUP(0)` declare data: the label names
;   this address, `DB` says "the following are bytes", and `2139 DUP(0)`
;   means "2139 copies of zero". `DW` is the 16-bit equivalent (two
;   bytes per entry, little-endian on x86).
;
; - `CS:[offset]` is a memory access using the Code Segment register as
;   the base. The dispatch trampoline sets DS := CS up front, so DS and
;   CS reference the same data; we keep the CS: prefix because that's
;   how the original assembler wrote it (one byte per instruction).
;
; - Functions are wrapped in `name PROC NEAR ... name ENDP`. Inside,
;   labels like `plp_inner:` or `s9_open_ok:` are jump targets local to
;   that function. We prefix every local label with a short nickname
;   for the enclosing function (`pl_` for slot_01_play, `plp_` for
;   play_loop, `s9_` for slot_09, `rs_` for recompute_stream, etc.) so
;   the labels don't collide across functions and a reader can tell at
;   a glance which function a jump target belongs to.
;
; - Numbers ending in `H` are hexadecimal (3FH = 63). Plain numbers are
;   decimal. Hex numbers beginning with a letter need a leading `0`
;   (0AH, 0FFH) because TASM uses the first character to distinguish
;   identifiers from numbers.
;
; - Registers used in this driver:
;     AX, BX, CX, DX     -- general 16-bit registers, each splittable
;                           into a high and low 8-bit half (AH/AL, BH/BL,
;                           CH/CL, DH/DL).
;     SI, DI             -- 16-bit "index" registers, often used as
;                           pointers into arrays or as the source/dest
;                           of LODSB / STOSB / MOVSW string ops.
;     BP                 -- 16-bit base pointer; this driver doesn't
;                           use it (the AdLib driver uses BP as a slot
;                           index, but ADS dispatches via AX instead).
;     CS, DS, ES, SS     -- 16-bit segment registers. In TINY model
;                           CS=DS=SS, and the dispatch trampoline
;                           explicitly does `MOV DS, CS` so handlers
;                           can address the data section through DS.
;                           ES is loaded per-need (e.g. LES BX, [...] to
;                           dereference a far pointer; or `MOV ES, AX`
;                           to point at the playback ring buffer).
;
; - Calling convention used in this driver: every "slot handler" is
;   reached via the dispatch trampoline with AX = slot index and
;   SS:SI = pointer to a packed argument block (see section "About
;   the DUDE dispatch ABI"). Internal helpers also pass arguments in
;   registers, but the convention varies per helper -- documented at
;   each helper's prologue.
;
; - IRQ-style stubs (the INT 10h and INT 33h chained handlers) use
;   IRET instead of RET, and use `PUSHF / CALL FAR [vec]` to invoke
;   the previous handler in the chain. They appear as `PROC NEAR` for
;   TASM's benefit even though the calling convention is interrupt-
;   gate, not a normal subroutine.
; ----------------------------------------------------------------------------

                .8086
                .MODEL  TINY
                .CODE

; ----------------------------------------------------------------------------
; Symbolic constants for the DSS / LPT hardware idioms used throughout
; this file. Defined as EQUs (no bytes emitted) so they don't shift the
; on-disk layout.
;
;   ads_fifo_ready_mask  -- bit 6 of the LPT status port (base+1). When
;                           set, the DSS's 16-byte FIFO has room for at
;                           least one more sample. Polled by
;                           ads_play_loop's FIFO-flush phase and by
;                           ads_detect_lpt.
;   ads_dss_ctrl_latch   -- value written to the LPT control port
;                           (base+2) to raise the strobe and latch the
;                           data byte into the DSS. Step 2 of the 3-step
;                           write sequence (see Hardware primer above).
;   ads_dss_ctrl_clock   -- value written to the LPT control port to
;                           drop the latch, which clocks the latched
;                           sample into the FIFO. Step 3 of the 3-step
;                           write sequence.
;   ads_dac_midscale     -- mid-scale 8-bit unsigned sample (0..0xFF).
;                           Written during the detect handshake and
;                           used by the engine's sign-flip path to
;                           invert signed samples (out = 0x7F - in).
; ----------------------------------------------------------------------------
ads_fifo_ready_mask EQU 40H
ads_dss_ctrl_latch  EQU 0CH
ads_dss_ctrl_clock  EQU 04H
ads_dac_midscale    EQU 7FH

                ORG     0

; ============================================================================
; 0x0000  --  DUDE v2.8 header  (interface 2, tag-length 8, tag "auddisny")
; ============================================================================
_start          LABEL   BYTE
                JMP     ads_dispatch                ; E9 AE 08

                ; pad_03: a single zero byte between the entry JMP
                ; (3 bytes: E9 AE 08) and the DUDE magic at offset 0x04,
                ; so the next field (dude_magic_a, a DD) lands at a
                ; DWORD-aligned offset. This is a structural padding byte
                ; of the on-disk header.
                DB      0                           ; pad_03

dude_magic_a    DD      87654321H
dude_iface_ver  DB      2, 8                        ; iface_major=2, tag_len=8
dude_tag        DB      'auddisny'

device_name_len DB      19
device_name     DB      'DISNEY SOUND SOURCE'

dude_magic_b    DD      0FEDCBA98H
dude_driver_kind DD     0400H

; ----------------------------------------------------------------------------
; 0x002E  --  ads_init_curve  (8 bytes)
;
; A small step-table the rate-decimation code reaches into. The values
; (0, 1, 2, 3, 6, 10, 15, 21) form a curve used by ads_playback_engine
; when applying the smoothing / interpolation step (see code at 0x0FE6
; and 0x0FF1, both of which do `[CS:BX + 2EH]` indexed loads).
; ----------------------------------------------------------------------------
ads_init_curve  DB      00H, 01H, 02H, 03H, 06H, 0AH, 0FH, 15H

; ============================================================================
; 0x0036  --  data section  (zero-initialized; the engine populates each
;             field at runtime).
;
; The bytes at 0x0036..0x0890 are all zero in the on-disk image. They
; serve as the driver's working memory: per-stream state, ring-buffer
; pointers, saved interrupt vectors, file handles, the sample-rate
; decimation step, and so on. Code throughout the rest of the file
; reaches into specific offsets via `CS:[<const>]` addressing.
;
; A partial map of the fields:
;
;   0x0036  ads_dbl_rate           1B   1 = double-rate (interpolation on)
;   0x0037  ads_smooth_accum       1B   delta-encoding accumulator
;   0x0038  ads_step               1B   rate-decimation step (1..6)
;   0x0039  ads_step_extra         1B   secondary step (0..2)
;   0x003A  ads_decimate_one       1B   1 = drop one sample per cycle
;   0x003B  ads_lpt_armed          1B   1 = LPT clocked at least once
;   0x003C  ads_init_done          1B   1 = slot_03 completed
;   0x003D  ads_active_bank        1B   0 / 1 = which ring half is hot
;   0x003E  ads_in_mouseint        1B   1 = inside INT 33h chain
;   0x003F  ads_in_pump            1B   1 = re-entry guard for engine
;   0x0040  ads_busy_engine        1B   1 = playback engine running
;   0x0041  ads_in_videoint        1B   1 = inside INT 10h chain
;   0x0042  ads_use_remainder      1B   1 = file > 0x800 chunk, use remainder
;   0x0043  ads_bank1_init         1B   slot_03 init flag (from arg AH)
;   0x0044  ads_state_eob          1B   end-of-buffer state byte
;   0x0045  ads_flag_high_bit      1B   bit-7 of slot_09's flags byte
;   0x0046  ads_no_kick_eof        1B   1 = swallow end-of-file
;   0x0047  ads_step_countdown     1B   per-tick countdown of ads_step
;   0x0048  ads_target_bank        1B   target value of active_bank
;   0x0049  ads_pause_pending      1B   1 = slot_10 pause requested
;   0x004A  ads_sign_invert        1B   1 = invert top bit of samples
;   0x004B  ads_subt_from_max      1B   1 = AL = 0x7F - sample
;   0x004C  ads_byteswap           1B   1 = swap bytes on read
;   0x004D  ads_unknown_4d         1B
;   0x004E  ads_playback_stopped   1B   1 = ads_slot_12_helper has fired
;   0x004F  ads_ring_size_lo       2B   words in ring half (LSB)
;   0x0051  ads_ring_size_hi       2B   words in ring half (alt half)
;   0x0053  ads_ring_pos_lo        2B   ring-fill position (lower)
;   0x0055  ads_ring_pos_hi        2B   ring-fill position (upper bound)
;   0x0057  ads_ring_step          2B   adds to ring_pos per chunk
;   0x0059  ads_buf_off            2B   far ptr buffer offset
;   0x005B  ads_play_si            2B   current play-cursor in ES:SI
;   0x005D  ads_play_seg           2B   current play-cursor in ES:SI
;   0x005F  ads_buf_seg            2B   far ptr buffer segment
;   0x0061  ads_chunk_words        2B   words/chunk; halved if dbl_rate
;   0x0063  ads_bytes_streamed_hi  2B   32-bit count -- high word
;   0x0065  ads_bytes_streamed_lo  2B   32-bit count -- low word
;   0x0067  ads_engine_consumed    2B   bytes the engine consumed
;   0x0069  ads_engine_extra       2B   spillover when chunk > 0x800
;   0x006B  ads_sample_rate_in     2B   incoming sample-rate (Hz)
;   0x006D  ads_file_handle        2B   DOS file handle (FFFFh = none)
;   0x006F  ads_seek_pos_lo        2B   file seek pos (low word)
;   0x0071  ads_seek_pos_hi        2B   file seek pos (high word)
;   0x0073  ads_total_len_hi       2B   total sample length, high
;   0x0075  ads_total_len_lo       2B   total sample length, low
;   0x0077  ads_lpt_data_port      2B   LPT data port (base + 0)
;   0x0079  ads_disney_rate        2B   ~7000 Hz, the DSS's fixed rate
;   0x007B  ads_remaining_lo       2B   bytes remaining in current chunk (lo)
;   0x007D  ads_remaining_hi       2B   bytes remaining in current chunk (hi)
;   0x007F  ads_irq_countdown      2B   countdown for slot_01 "kick" path
;   0x0081  ads_indos_p_lo         2B   InDOS flag pointer offset
;   0x0083  ads_indos_p_hi         2B   InDOS flag pointer segment
;   0x0085  ads_critical_p_lo      2B   critical-section ptr offset
;   0x0087  ads_critical_p_hi      2B   critical-section ptr segment
;   0x0089  ads_int33_orig_off     2B   saved INT 33h original vector off
;   0x008B  ads_int33_orig_seg     2B   saved INT 33h original vector seg
;   0x008D  ads_int10_orig_off     2B   saved INT 10h original vector off
;   0x008F  ads_int10_orig_seg     2B   saved INT 10h original vector seg
;   0x0091..0x0890                      ring buffer + scratch (2048 bytes)
; ============================================================================
ads_state       DB      2139 DUP(00H)               ; 0x0036..0x0890

; ============================================================================
; 0x0891  --  ads_func_table  (16 entries x 2 bytes = 32 bytes)
;
; The 16 slot handlers. The dispatch trampoline indexes this table with
; the slot number (AX*2) and does a near indirect CALL.
; ============================================================================
ads_func_table  LABEL   WORD
                DW      ads_slot_00_init            ; slot  0  -- 0x11E1
                DW      ads_slot_01_play            ; slot  1  -- 0x08C3
                DW      ads_slot_02                 ; slot  2  -- 0x09C3
                DW      ads_slot_03                 ; slot  3  -- 0x094B
                DW      ads_slot_04                 ; slot  4  -- 0x099A
                DW      ads_slot_05                 ; slot  5  -- 0x09BF
                DW      ads_slot_06                 ; slot  6  -- 0x0922
                DW      ads_slot_07                 ; slot  7  -- 0x092F
                DW      ads_slot_08                 ; slot  8  -- 0x0939
                DW      ads_slot_09                 ; slot  9  -- 0x0C23
                DW      ads_slot_10                 ; slot 10  -- 0x0E1E
                DW      ads_slot_11                 ; slot 11  -- 0x0E39
                DW      ads_slot_12_helper_set_flag ; slot 12  -- 0x0942
                DW      ads_slot_13                 ; slot 13  -- 0x110D
                DW      ads_slot_14                 ; slot 14  -- 0x0C20
                DW      ads_slot_15                 ; slot 15  -- 0x0921

; ============================================================================
; 0x08B1  --  ads_dispatch  --  the trampoline
;
; Called by the game as `CALL FAR ads_seg:ads_dispatch` with:
;     AX    = slot index (0..15)
;     SS:SI = pointer to slot arguments
;
; Saves DS, sets DS := CS so the handler can use the data section
; through DS without a CS: override, does a near indirect CALL through
; ads_func_table, restores DS, sets flags from AX, and far-returns to
; the caller.
;
;   Type:        Dispatch trampoline (far entry point)
;   Category:    DUDE ABI
;   Callers:     Game engine (far call from outside the driver)
;   Callees:     Every slot handler in ads_func_table
;
;   Inputs:
;     AX     --  slot index, 0..15
;     SS:SI  --  far pointer to the per-slot argument block; the SS
;                segment is preserved across the call so the handler
;                can read its args directly
;
;   Outputs:
;     AX     --  whatever the slot returned (flags set via OR AX, AX
;                before the far return so the caller can JE/JNE on it)
;
;   Touches:     BX (used as the scaled table index, not restored)
; ============================================================================
ads_dispatch    PROC    NEAR
                PUSH    DS
                MOV     BX, AX
                SHL     BX, 1
                MOV     AX, CS
                MOV     DS, AX
                CALL    WORD PTR CS:[BX + ads_func_table]
                POP     DS
                OR      AX, AX
                RETF
ads_dispatch    ENDP

; ============================================================================
; 0x08C3  --  ads_slot_01_play  (slot 1)
;
; "Play" -- but in this driver "play" is also the engine-pump tick. The
; behaviour depends on the playback state:
;
;   * If playback has already been stopped (4Eh = 1) but the LPT is
;     still armed (3Bh = 1), decrement the IRQ countdown and call
;     ads_lpt_stop when it hits zero. This is how the driver flushes
;     the remaining samples out of the FIFO after the .SOL file ends.
;   * If init_done (3Ch) is zero, do the very first buffer pump:
;     call ads_play_loop to push samples to the LPT, then arm the
;     two state bytes (4Eh, 44h) so subsequent calls take the
;     normal pump path. As a special case, when bank1_init (43h)
;     is set, also call ads_recompute_stream first.
;   * Normal case (init done, not stopped): if buffer-needs-reload
;     (46h) is zero, run a pump cycle (ads_play_loop) and tick the
;     bank-swap engine; otherwise just fall through to the engine.
;
; Returns AX = 0.
;
;   Type:        Slot handler
;   Category:    Playback pump / engine tick
;   Dispatch:    Slot 1 (AX=1, no SS:SI args read)
;   Callers:     Game (via dispatch); called repeatedly as the timer tick
;   Callees:     ads_lpt_stop, ads_play_loop, ads_recompute_stream,
;                ads_tick, ads_playback_engine
;
;   Inputs:      none from caller; reads ads_state flags 3Bh, 3Ch, 43h,
;                46h, 4Eh
;
;   Outputs:
;     AX     --  always 0
;
;   Side effects:
;     ads_playback_stopped (4Eh), ads_state_eob (44h), ads_irq_countdown
;     (7Fh) may all be written; the LPT FIFO is potentially clocked via
;     ads_play_loop; the bank-swap may flip via ads_tick.
; ============================================================================
ads_slot_01_play PROC   NEAR
                CMP     BYTE PTR CS:[4EH], 1
                JNE     SHORT pl_not_stopped
                CMP     BYTE PTR CS:[3BH], 1
                JNE     SHORT pl_exit_xor
                DEC     WORD PTR CS:[7FH]
                JNE     SHORT pl_skip_stop
                CALL    ads_lpt_stop
pl_skip_stop:   JMP     SHORT pl_exit_xor
pl_not_stopped: CMP     BYTE PTR CS:[3CH], 1
                JE      SHORT pl_init_done
                ; first pump: try to feed samples; if the LPT couldn't
                ; absorb any (ZF set on return), bail.
                CALL    ads_play_loop
                JNE     SHORT pl_exit_xor
                MOV     BYTE PTR CS:[4EH], 1
                CMP     BYTE PTR CS:[43H], 1
                JNE     SHORT pl_no_recompute
                CALL    ads_recompute_stream
                MOV     BYTE PTR CS:[4EH], 0
                MOV     BYTE PTR CS:[44H], 1
pl_no_recompute: JMP    SHORT pl_exit_xor
pl_init_done:   CMP     BYTE PTR CS:[46H], 0
                JNE     SHORT pl_engine_only
                CALL    ads_play_loop
                JNE     SHORT pl_engine_only
                CALL    ads_tick
pl_engine_only: CALL    ads_playback_engine
pl_exit_xor:    XOR     AX, AX
                RET
ads_slot_01_play ENDP

; ============================================================================
; 0x0921  --  ads_slot_15
;
; Reserved no-op slot -- a single-byte RET stub.
;
;   Type:        Slot handler (no-op stub)
;   Category:    DUDE ABI reserved
;   Dispatch:    Slot 15 (AX=15)
;   Callers:     Game (via dispatch)
;   Inputs:      none
;   Outputs:     none (AX retains whatever the caller passed in)
;   Notes:       Reserved-but-unimplemented slot; the cross-driver ABI
;                reserves 16 entries and this driver doesn't use this one.
; ============================================================================
ads_slot_15     PROC    NEAR
                RET
ads_slot_15     ENDP

; ============================================================================
; 0x0922  --  ads_slot_06  --  set sample rate from arg
;
; Reads the desired sample rate from SS:[SI], caches it in
; ads_sample_rate_in (cs:[6Bh]), and reprograms the decimation
; pipeline via ads_pick_decimation. Returns AX = 0.
;
;   Type:        Slot handler
;   Category:    Sample-rate control
;   Dispatch:    Slot 6 (AX=6, SS:[SI] = input rate in Hz, 16-bit)
;   Callers:     Game (via dispatch)
;   Callees:     ads_pick_decimation
;
;   Inputs:
;     SS:[SI]  --  WORD, requested input sample rate in Hz
;
;   Outputs:
;     AX     --  0
;
;   Side effects:
;     ads_sample_rate_in (6Bh) <- requested rate
;     ads_step (38h), ads_step_extra (39h), ads_decimate_one (3Ah)
;     reprogrammed by ads_pick_decimation
; ============================================================================
ads_slot_06     PROC    NEAR
                MOV     AX, SS:[SI]
                MOV     CS:[6BH], AX                ; cache new input rate
                CALL    ads_pick_decimation
                XOR     AX, AX
                RET
ads_slot_06     ENDP

; ============================================================================
; 0x092F  --  ads_slot_07
;
; Reserved no-op slot -- a single-byte RET stub.
;
;   Type:        Slot handler (no-op stub)
;   Category:    DUDE ABI reserved
;   Dispatch:    Slot 7 (AX=7)
;   Callers:     Game (via dispatch)
;   Inputs:      none
;   Outputs:     none (AX unchanged)
; ============================================================================
ads_slot_07     PROC    NEAR
                RET
ads_slot_07     ENDP

; ============================================================================
; 0x0930  --  ads_set_no_kick_eof
;
; This 9-byte function sets ads_no_kick_eof (cs:[46h]) to 1. It is not
; referenced from anywhere in the live code path (the function table
; routes slot 8 to ads_slot_08 just below, which CLEARS the same flag).
; The "set" companion to slot 8's "clear".
;
;   Type:        Dead subroutine
;   Category:    State-flag setter
;   Callers:     none (unreferenced in this build)
;   Inputs:      none
;
;   Outputs:
;     AX     --  0
;
;   Side effects:
;     ads_no_kick_eof (46h) <- 1
;
;   Notes:       The unused twin of ads_slot_08 (which clears the same
;                byte).
; ============================================================================
ads_set_no_kick_eof PROC NEAR
                MOV     BYTE PTR CS:[46H], 1
                XOR     AX, AX
                RET
ads_set_no_kick_eof ENDP

; ============================================================================
; 0x0939  --  ads_slot_08  --  clear no-kick-eof flag
;
;   Type:        Slot handler
;   Category:    State-flag setter
;   Dispatch:    Slot 8 (AX=8, no SS:SI args)
;   Callers:     Game (via dispatch)
;   Inputs:      none
;
;   Outputs:
;     AX     --  0
;
;   Side effects:
;     ads_no_kick_eof (46h) <- 0  (re-enable the natural EOF kick path
;     in ads_playback_engine).
; ============================================================================
ads_slot_08     PROC    NEAR
                MOV     BYTE PTR CS:[46H], 0
                XOR     AX, AX
                RET
ads_slot_08     ENDP

; ============================================================================
; 0x0942  --  ads_slot_12_helper_set_flag  (slot 12 + internal helper)
;
; Sets the "playback stopped" flag at cs:[4Eh] to 1. This is the canonical
; way to *stop* playback in this driver: slots 2, 5, and 9 all call it
; as their first action, and slot 1 checks the same flag to know whether
; it should flush the FIFO.
;
;   Type:        Slot handler + internal helper
;   Category:    State-flag setter
;   Dispatch:    Slot 12 (AX=12, no SS:SI args)
;   Callers:     Game (via dispatch); ads_slot_02, ads_slot_03,
;                ads_slot_05, ads_slot_09, ads_tick
;   Inputs:      none
;
;   Outputs:
;     AX     --  0
;
;   Side effects:
;     ads_playback_stopped (4Eh) <- 1
; ============================================================================
ads_slot_12_helper_set_flag PROC NEAR
                MOV     BYTE PTR CS:[4EH], 1
                XOR     AX, AX
                RET
ads_slot_12_helper_set_flag ENDP

; ============================================================================
; 0x094B  --  ads_slot_03  --  init playback (rate + buffer geometry)
;
; The big initialization slot. Reads slot arguments from SS:[SI..SI+8]:
;
;   SS:[SI]      AX -- if AH != 0, bank1_init = 1 else 0
;   SS:[SI+2]    AX -- desired input sample rate, passed to ads_pick_decimation
;   SS:[SI+4]    AX -- ads_buf_off    (buffer offset)
;   SS:[SI+6]    AX -- ads_buf_seg    (buffer segment)
;   SS:[SI+8]    AX -- ads_chunk_words (chunk size in words)
;
; Then clears init_done (3Ch), calls ads_recompute_stream to set up the
; ring pointers, and clears the "playback-stopped" and "state-EOB" flags.
;
;   Type:        Slot handler
;   Category:    Playback init
;   Dispatch:    Slot 3 (AX=3, SS:SI = 10-byte arg block as documented above)
;   Callers:     Game (via dispatch)
;   Callees:     ads_slot_12_helper_set_flag, ads_pick_decimation,
;                ads_recompute_stream
;
;   Inputs:
;     SS:[SI]      WORD  -- bank-init flag in the high byte (AH != 0)
;     SS:[SI + 2]  WORD  -- desired input sample rate (Hz)
;     SS:[SI + 4]  WORD  -- buf_off (ring-buffer offset)
;     SS:[SI + 6]  WORD  -- buf_seg (ring-buffer segment)
;     SS:[SI + 8]  WORD  -- chunk_words
;
;   Outputs:
;     AX     --  (no explicit value; the trampoline reads AX and ORs
;                it for flags -- callers typically ignore the result of
;                slot 3 since it's an init call)
;
;   Side effects:
;     ads_playback_stopped (4Eh) <- 1, then <- 0
;     ads_bank1_init (43h) <- decoded AH
;     ads_chunk_words (61h), ads_buf_off (59h), ads_buf_seg (5Fh)
;     populated from arg block
;     ads_init_done (3Ch) <- 0, ads_state_eob (44h) <- 0
;     decimation pipeline + ring pointers reprogrammed
; ============================================================================
ads_slot_03     PROC    NEAR
                PUSH    SI
                CALL    ads_slot_12_helper_set_flag ; stop any current playback
                POP     SI

                ; Decode the bank-init flag from the high byte of arg[0].
                MOV     AX, SS:[SI]
                OR      AH, AH
                JNE     SHORT s3_bank1
                MOV     BYTE PTR CS:[43H], 0
                JMP     SHORT s3_after_bank
s3_bank1:       MOV     BYTE PTR CS:[43H], 1

s3_after_bank:  ; Program the sample-rate decimation pipeline.
                MOV     AX, SS:[SI + 2]
                CALL    ads_pick_decimation

                ; Stash buffer geometry into the data section.
                MOV     AX, SS:[SI + 8]
                MOV     CS:[61H], AX                ; chunk_words
                MOV     AX, SS:[SI + 4]
                MOV     CS:[59H], AX                ; buf_off
                MOV     AX, SS:[SI + 6]
                MOV     CS:[5FH], AX                ; buf_seg

                ; Clear init_done, then build the ring-pointer state.
                MOV     BYTE PTR CS:[3CH], 0
                CALL    ads_recompute_stream

                ; Clear "playback stopped" and "state-EOB" so slot_01
                ; takes the live-pump path on its next invocation.
                MOV     BYTE PTR CS:[4EH], 0
                MOV     BYTE PTR CS:[44H], 0
                RET
ads_slot_03     ENDP

; ============================================================================
; 0x099A  --  ads_slot_04  --  read state, write playback-end flag
;
; Same bank-init dispatch as slot_03 (decoded from arg[0].AH), but
; instead of priming a new playback this returns the current playback-
; -stopped flag in AL and the state-EOB byte in AH, then clears the
; state-EOB byte. Used by the game to poll "did playback finish?".
;
;   Type:        Slot handler
;   Category:    State query
;   Dispatch:    Slot 4 (AX=4, SS:[SI] = bank-init flag in AH)
;   Callers:     Game (via dispatch)
;
;   Inputs:
;     SS:[SI]  WORD  -- bank-init flag in the high byte
;
;   Outputs:
;     AL     --  ads_playback_stopped (4Eh)
;     AH     --  ads_state_eob (44h) at entry
;
;   Side effects:
;     ads_bank1_init (43h) <- decoded AH from arg
;     ads_state_eob (44h) <- 0  (read-clears)
; ============================================================================
ads_slot_04     PROC    NEAR
                MOV     AX, SS:[SI]
                OR      AH, AH
                JNE     SHORT s4_bank1
                MOV     BYTE PTR CS:[43H], 0
                JMP     SHORT s4_after_bank
s4_bank1:       MOV     BYTE PTR CS:[43H], 1
s4_after_bank:  MOV     AL, CS:[4EH]                ; AL = playback_stopped
                MOV     AH, CS:[44H]                ; AH = state_eob
                MOV     BYTE PTR CS:[44H], 0        ; clear EOB on read
                RET
ads_slot_04     ENDP

; ============================================================================
; 0x09BF  --  ads_slot_05  --  thin wrapper around slot_12 helper
;
;   Type:        Slot handler
;   Category:    State-flag setter
;   Dispatch:    Slot 5 (AX=5, no SS:SI args)
;   Callers:     Game (via dispatch)
;   Callees:     ads_slot_12_helper_set_flag
;   Inputs:      none
;
;   Outputs:
;     AX     --  0 (from the helper)
;
;   Side effects:
;     ads_playback_stopped (4Eh) <- 1  (same as slot 12)
;
;   Notes:       Provides a second slot index that means "stop
;                playback", for callers that expect slot 5 == stop.
; ============================================================================
ads_slot_05     PROC    NEAR
                CALL    ads_slot_12_helper_set_flag
                RET
ads_slot_05     ENDP

; ============================================================================
; 0x09C3  --  ads_slot_02  --  shutdown
;
; Halt playback, restore the saved INT 10h and INT 33h vectors (so our
; stubs aren't called after we unload), close the open .SOL file (if
; any), and zero AX on return.
;
;   Type:        Slot handler
;   Category:    Driver shutdown
;   Dispatch:    Slot 2 (AX=2, no SS:SI args)
;   Callers:     Game (via dispatch), at driver-unload time
;   Callees:     ads_lpt_stop, ads_slot_12_helper_set_flag,
;                DOS INT 21h (AH=25h Set-Vector, AH=3Eh Close-Handle)
;
;   Inputs:      none
;
;   Outputs:
;     AX     --  0
;
;   Side effects:
;     LPT control port pulled to idle; ads_lpt_armed (3Bh) <- 0
;     ads_playback_stopped (4Eh) <- 1
;     INT 10h vector restored from saved (8Dh:8Fh)
;     INT 33h vector restored from saved (89h:8Bh)
;     .SOL file handle (6Dh) closed and set to 0xFFFF if it was open
; ============================================================================
ads_slot_02     PROC    NEAR
                CALL    ads_lpt_stop
                CALL    ads_slot_12_helper_set_flag

                ; Restore INT 10h from saved offset/seg at cs:[8Dh].
                PUSH    DS
                LDS     DX, CS:[8DH]                ; DS:DX = orig INT 10h
                MOV     AH, 25H                     ; DOS Set-Vector
                MOV     AL, 10H
                INT     21H
                POP     DS

                ; Restore INT 33h from saved offset/seg at cs:[89h].
                PUSH    DS
                LDS     DX, CS:[89H]                ; DS:DX = orig INT 33h
                MOV     AH, 25H
                MOV     AL, 33H
                INT     21H
                POP     DS

                ; If a .SOL file is open, close it.
                CMP     WORD PTR CS:[6DH], 0FFFFH
                JE      SHORT s2_done
                MOV     BX, CS:[6DH]
                MOV     AH, 3EH                     ; DOS Close-Handle
                INT     21H
                MOV     WORD PTR CS:[6DH], 0FFFFH
s2_done:        XOR     AX, AX
                RET
ads_slot_02     ENDP

; ============================================================================
; 0x09FE  --  ads_recompute_stream
;
; Recomputes ring-buffer position state when slot_03 sets up a new
; playback or when ads_play_loop wraps the buffer:
;
;   * Loads buf_off (59h) / buf_seg (5Fh) into AX / DX.
;   * If init_done (3Ch) is set, picks the correct half of the ring
;     buffer based on target_bank (48h) and folds chunk_words (61h)
;     into the segment via the AX += chunk_words; if carry, DX += 0x1000
;     trick (so the buffer wraps across a 64K paragraph boundary).
;   * Otherwise just uses chunk_words for CX.
;   * Normalizes the 16-byte-aligned offset into AX (segment) and the
;     low nibble into DX (intra-paragraph offset) -- this is what the
;     `XOR DX, DX / MOV BX, 16 / DIV BX` block is doing.
;   * Stores play_seg (5Dh), ring_pos_lo (5Bh, 53h), ring_step (57h),
;     ring_pos_hi (55h), and primes step_countdown (47h) from step (38h).
;   * Calls ads_play_loop to actually push samples out.
;
;   Type:        Internal helper
;   Category:    Ring-buffer setup
;   Callers:     ads_slot_01_play (first-pump path), ads_slot_03 (init),
;                ads_tick (bank-swap)
;   Callees:     ads_play_loop
;
;   Inputs:      none (reads ads_state buf_off / buf_seg / chunk_words /
;                target_bank / ring_size_lo / ring_size_hi / step / init_done)
;
;   Outputs:     none
;
;   Touches:     AX, BX, CX, DX (not restored)
;
;   Side effects:
;     ads_play_seg (5Dh), ads_ring_pos_lo (5Bh, 53h), ads_ring_step (57h),
;     ads_ring_pos_hi (55h), ads_step_countdown (47h) all written.
;     ads_play_loop is then invoked to push the first batch of samples.
; ============================================================================
ads_recompute_stream PROC NEAR
                MOV     DX, CS:[5FH]                ; DX = buf_seg
                MOV     AX, CS:[59H]                ; AX = buf_off
                CMP     BYTE PTR CS:[3CH], 1
                JNE     SHORT rs_first_chunk
                CMP     BYTE PTR CS:[48H], 0
                JNE     SHORT rs_target_one
                MOV     CX, CS:[4FH]                ; CX = ring_size_lo
                JMP     SHORT rs_have_cx
rs_target_one:  MOV     CX, CS:[51H]                ; CX = ring_size_hi
                ADD     AX, CS:[61H]                ; AX += chunk_words
                JAE     SHORT rs_no_carry
                ADD     DX, 1000H                   ; carry into segment
rs_no_carry:    JMP     SHORT rs_have_cx
rs_first_chunk: MOV     CX, CS:[61H]                ; CX = chunk_words

rs_have_cx:     MOV     CS:[5DH], DX                ; play_seg scratch
                ; Normalize AX:0 to AX = paragraph-aligned offset,
                ; DX = intra-paragraph remainder.
                XOR     DX, DX
                MOV     BX, 10H
                DIV     BX
                ADD     AX, CS:[5DH]                ; AX += saved seg
                MOV     CS:[5DH], AX                ; play_seg final

                MOV     CS:[5BH], DX                ; ring_pos_lo
                MOV     CS:[53H], DX
                MOV     CS:[57H], CX                ; ring_step = CX
                ADD     DX, CX
                MOV     CS:[55H], DX                ; ring_pos_hi

                ; Prime the per-sample countdown from the configured step.
                MOV     AL, CS:[38H]                ; AL = ads_step
                MOV     CS:[47H], AL                ; step_countdown = step

                CALL    ads_play_loop
                RET
ads_recompute_stream ENDP

; ============================================================================
; 0x0A6C  --  ads_play_loop
;
; The hot inner pump: read one PCM sample at ES:SI via ads_sample_read,
; write it to the LPT data port, toggle the LPT control port (0x0C
; then 0x04) to clock it into the FIFO, then either continue (LOOP
; until CX=0) or busy-wait on FIFO-ready (status bit 6).
;
; First invocation per slot_03 cycle: ARM the LPT (calls ads_lpt_start)
; unless it's already armed (3Bh = 1).
;
; On return ZF reflects whether the loop bailed out (end-of-sample).
;
;   Type:        Internal helper (hot path)
;   Category:    LPT-DAC clock-out
;   Callers:     ads_slot_01_play, ads_recompute_stream
;   Callees:     ads_lpt_start, ads_sample_read
;
;   Inputs:      none from caller; reads ads_play_seg / ads_play_si /
;                ads_lpt_data_port / ads_ring_pos_hi
;
;   Outputs:
;     ZF     --  reflects "end-of-buffer reached" (set by the final
;                CMP via ads_sample_read's RET ZF) so callers can
;                JE/JNE on it
;
;   Touches:     AX, BX, CX, DX, SI, ES (not restored)
;
;   Side effects:
;     Writes 7-bit PCM bytes to the LPT data port + control-port FIFO
;     clock toggles (see Disney Sound Source primer above).
;     Advances ads_play_si (5Bh); on chunk-end wraps the ring pointers
;     and accumulates ads_ring_step into ads_bytes_streamed (65h:63h).
;     First call per slot_03 cycle: ads_lpt_armed (3Bh) <- 1 via
;     ads_lpt_start.
; ============================================================================
ads_play_loop   PROC    NEAR
                CMP     BYTE PTR CS:[3BH], 1
                JE      SHORT plp_lpt_armed
                CALL    ads_lpt_start
plp_lpt_armed:  MOV     WORD PTR CS:[7FH], 0        ; reset IRQ countdown

                MOV     AX, CS:[5DH]                ; ES:SI = play_seg : play_off
                MOV     ES, AX
                MOV     CX, 1                       ; outer count = 1 (single)
                MOV     SI, CS:[5BH]

plp_inner:      CALL    ads_sample_read
                JE      SHORT plp_end               ; ZF=1 => end-of-buffer
                MOV     DX, CS:[77H]                ; DX = LPT data port
                OUT     DX, AL                      ; write PCM sample
                ADD     DX, 2                       ; -> control port (base+2)
                MOV     AL, ads_dss_ctrl_latch
                OUT     DX, AL                      ; strobe high + latch
                NOP                                 ; ~7 cycle settle delay
                NOP
                NOP
                MOV     AL, ads_dss_ctrl_clock
                OUT     DX, AL                      ; drop latch -> clock
                PUSH    AX                          ; settling delay (see the
                POP     AX                          ; Timing loop glossary entry)
                PUSH    AX
                POP     AX
                LOOP    plp_inner                   ; (CX was 1; this falls)

                ; FIFO-flush phase: try up to 0x20 more samples while the
                ; status port says "FIFO has room". The INC DX at the
                ; top runs once to advance DX from the data port (base+0)
                ; to the status port (base+1); the loop body keeps DX
                ; on the status port across iterations.
                MOV     CX, 20H
                MOV     DX, CS:[77H]
                INC     DX                          ; DX = status port
plp_drain:      IN      AL, DX                      ; read LPT status
                TEST    AL, ads_fifo_ready_mask     ; bit 6 = FIFO ready
                JNE     SHORT plp_eob_chunk         ; FIFO full -> back off
                CALL    ads_sample_read
                JE      SHORT plp_end
                DEC     DX                          ; DX = data port
                OUT     DX, AL
                ADD     DX, 2
                MOV     AL, ads_dss_ctrl_latch
                OUT     DX, AL
                NOP
                NOP
                NOP
                MOV     AL, ads_dss_ctrl_clock
                OUT     DX, AL
                PUSH    AX
                POP     AX
                PUSH    AX
                POP     AX
                DEC     DX
                JMP     SHORT plp_loop_tail         ; (always taken)
plp_eob_chunk:  JMP     SHORT plp_end
plp_loop_tail:  LOOP    plp_drain

plp_end:        MOV     CS:[5BH], SI                ; persist play_si
                CMP     SI, CS:[55H]                ; reached ring_pos_hi?
                JNE     SHORT plp_done
                ; Chunk fully consumed -- accumulate it into the 32-bit
                ; total-bytes-streamed counter and wrap the ring pointers.
                MOV     AX, CS:[57H]
                ADD     CS:[65H], AX                ; bytes_streamed_lo += step
                ADC     WORD PTR CS:[63H], 0        ; bytes_streamed_hi += C
                XOR     AX, AX
                MOV     CS:[53H], AX                ; ring_pos_lo = 0
                MOV     CS:[55H], AX
                MOV     CS:[5BH], AX
                MOV     CS:[57H], AX
plp_done:       RET
ads_play_loop   ENDP

; ============================================================================
; 0x0B03  --  ads_sample_read
;
; Read one sample byte at ES:SI into AL, advance SI, decrement
; step_countdown (47h). When the countdown reaches zero, reload it
; from step (38h) and either:
;
;   * decimate_one (3Ah): roll SI back one and exit (re-read same byte)
;   * step_extra (39h): add the extra-step value to SI and retry from
;     the start, but only if SI hasn't passed ring_pos_hi (55h).
;
; ZF on return indicates "the countdown rolled and the buffer is empty
; for this tick" -- the caller (ads_play_loop) uses this to bail.
;
;   Type:        Internal helper (hot path)
;   Category:    Sample-rate decimation
;   Callers:     ads_play_loop (calls into the middle of the play loop)
;
;   Inputs:
;     ES:SI  --  read cursor into the ring buffer
;     CS:[55h] (ring_pos_hi) bounds the buffer; CS:[47h] is the
;     per-tick countdown.
;
;   Outputs:
;     AL     --  next sample byte read from ES:[SI]
;     SI     --  advanced (possibly retried via the step_extra path)
;     ZF     --  set when the countdown rolled to zero (caller uses
;                this to know "no fresh sample produced this tick")
;
;   Touches:     AH, BX (not restored)
;
;   Side effects:
;     ads_step_countdown (47h) decremented (and reloaded from step
;     (38h) when it hits zero).
; ============================================================================
ads_sample_read PROC    NEAR
                CMP     SI, CS:[55H]                ; SI == ring_pos_hi ?
                JNE     SHORT sr_load
                RET                                 ; ZF=1, AL = whatever
sr_load:        MOV     AL, ES:[SI]                 ; AL = next sample
                INC     SI
                DEC     BYTE PTR CS:[47H]           ; step_countdown--
                JNE     SHORT sr_test_zero_47       ; not yet zero; return
                MOV     AH, CS:[38H]
                MOV     CS:[47H], AH                ; reload countdown
                CMP     BYTE PTR CS:[3AH], 0
                JE      SHORT sr_check_extra
                DEC     SI                          ; decimate one
                JMP     SHORT sr_test_zero_47
sr_check_extra: CMP     BYTE PTR CS:[39H], 0
                JE      SHORT sr_test_zero_47
                DEC     SI
                MOV     BL, CS:[39H]
                XOR     BH, BH
                ADD     SI, BX                      ; SI += step_extra
                CMP     SI, CS:[55H]
                JBE     SHORT sr_no_clamp
                MOV     SI, CS:[55H]
sr_no_clamp:    JMP     SHORT ads_sample_read       ; retry read
sr_test_zero_47: CMP    BYTE PTR CS:[47H], 0
                RET                                 ; ZF set iff countdown==0
ads_sample_read ENDP

; ============================================================================
; 0x0B52  --  ads_pick_decimation
;
; Given an input sample rate in AX (Hz), compute the decimation step
; (38h), step_extra (39h), and decimate_one (3Ah) flags that down-
; sample the input to the DSS's ~7000 Hz fixed rate. This is a stack of
; magic-number CMP/JA/JB checks tuned to specific common rates
; (44.1 kHz, 22050 Hz, 11025 Hz, 8000 Hz, etc.).
;
; Returns: nothing of interest; caches the input rate at cs:[79h].
;
; Rate bands (boundaries are inclusive on the lower side):
;
;   > 0x4B32  (~19250 Hz)  -> step=2, step_extra+=2          (high rates)
;   > 0x3D86  (~15750 Hz)  -> step=4, step_extra+=1          (mid-high)
;   > 0x2FDA  (~12250 Hz)  -> step=3                         (mid)
;   ...
;   < 0x1004  (~4100 Hz)   -> decimate_one++                 (low rates)
;
; The fifteen explicit thresholds are tuned to map the recording-rate
; choices Dynamix's tools could output onto the DSS's playback rate
; without producing audible aliasing.
;
;   Type:        Internal helper
;   Category:    Sample-rate decimation
;   Callers:     ads_slot_06, ads_slot_03, ads_slot_11,
;                ads_dos_file_open_sol, ads_slot_00_init
;
;   Inputs:
;     AX     --  input sample rate in Hz (1..~50000)
;
;   Outputs:     none (decimation triple cached in ads_state)
;
;   Touches:     AX, BX, CX, DX (per the CMP chain; not restored)
;
;   Side effects:
;     ads_disney_rate (79h) <- requested rate (cached for later DIVs
;     in slot 09 / slot 13).
;     ads_step (38h), ads_step_extra (39h), ads_decimate_one (3Ah)
;     programmed per the band the input rate falls into.
; ============================================================================
ads_pick_decimation PROC NEAR
                MOV     CS:[79H], AX                ; cache requested rate

                ; Default the decimation triple to (step=2, extra=0, one=0).
                MOV     BYTE PTR CS:[38H], 2
                MOV     BYTE PTR CS:[39H], 0
                MOV     BYTE PTR CS:[3AH], 0

                CMP     AX, 4B32H
                JA      SHORT pd_extra_plus2        ; very high rate
                CMP     AX, 3D86H
                JA      SHORT pd_step4_extra2       ; high rate
                CMP     AX, 1004H
                JB      SHORT pd_decimate_one       ; very low rate
                CMP     AX, 2FDAH
                JA      SHORT pd_extra_plus1
                INC     BYTE PTR CS:[38H]           ; step = 3
                CMP     AX, 1356H
                JB      SHORT pd_decimate_one
                CMP     AX, 26ACH
                JA      SHORT pd_extra_plus1
                INC     BYTE PTR CS:[38H]           ; step = 4
                CMP     AX, 1518H
                JB      SHORT pd_decimate_one
                CMP     AX, 2341H
                JA      SHORT pd_extra_plus1
                INC     BYTE PTR CS:[38H]           ; step = 5
                CMP     AX, 1644H
                JB      SHORT pd_decimate_one
                CMP     AX, 217FH
                JA      SHORT pd_extra_plus1
                INC     BYTE PTR CS:[38H]           ; step = 6
                CMP     AX, 170CH
                JB      SHORT pd_decimate_one
                CMP     AX, 206CH
                JA      SHORT pd_extra_plus1
                INC     BYTE PTR CS:[38H]           ; step = 7
                CMP     AX, 1964H
                JB      SHORT pd_decimate_one
                CMP     AX, 1FA4H
                JA      SHORT pd_extra_plus1
                INC     BYTE PTR CS:[38H]           ; step = 8
                CMP     AX, 1D4CH
                JA      SHORT pd_extra_plus1
                RET
                ; pd_step4_extra2 sets step = 4 and then falls into
                ; pd_extra_plus2 (step_extra += 2). pd_extra_plus2
                ; falls into pd_extra_plus1 (one more step_extra++).
pd_step4_extra2: MOV    BYTE PTR CS:[38H], 4
pd_extra_plus2: INC     BYTE PTR CS:[39H]           ; step_extra++
pd_extra_plus1: INC     BYTE PTR CS:[39H]           ; step_extra++
                RET
pd_decimate_one: INC    BYTE PTR CS:[3AH]           ; decimate_one++
                RET
ads_pick_decimation ENDP

; ============================================================================
; 0x0BE9  --  ads_lpt_start
;
; First-time LPT prime: write 0x0C then 0x04 to the control port to
; latch the FIFO's initial state, then mark "armed" by setting
; ads_lpt_armed (3Bh) = 1. Saves and restores AX / DX so callers
; don't have to.
;
;   Type:        Internal helper
;   Category:    LPT-DAC hardware I/O
;   Callers:     ads_play_loop, ads_detect_lpt
;
;   Inputs:      none (reads ads_lpt_data_port at 77h)
;   Outputs:     none
;
;   Touches:     all caller registers preserved (saves AX, DX)
;
;   Side effects:
;     Writes 0x0C then 0x04 to LPT control port (base + 2) -- this is
;     the "clock the FIFO" handshake described in the DSS primer.
;     ads_lpt_armed (3Bh) <- 1.
; ============================================================================
ads_lpt_start   PROC    NEAR
                PUSH    AX
                PUSH    DX
                MOV     DX, CS:[77H]
                ADD     DX, 2                       ; DX = control port
                MOV     AL, ads_dss_ctrl_latch
                OUT     DX, AL
                NOP
                NOP
                NOP
                NOP
                MOV     AL, ads_dss_ctrl_clock
                OUT     DX, AL
                PUSH    AX                          ; brief delay
                POP     AX
                PUSH    AX
                POP     AX
                POP     DX
                POP     AX
                MOV     BYTE PTR CS:[3BH], 1
                RET
ads_lpt_start   ENDP

; ============================================================================
; 0x0C0A  --  ads_lpt_stop
;
; Pull the control port back to 0x0C (latch high, strobe low) -- this
; effectively idles the DAC -- and clear ads_lpt_armed.
;
;   Type:        Internal helper
;   Category:    LPT-DAC hardware I/O
;   Callers:     ads_slot_01_play, ads_slot_02, ads_detect_lpt
;
;   Inputs:      none (reads ads_lpt_data_port at 77h)
;   Outputs:     none
;
;   Touches:     all caller registers preserved (saves AX, DX)
;
;   Side effects:
;     LPT control port (base + 2) <- 0x0C
;     ads_lpt_armed (3Bh) <- 0
; ============================================================================
ads_lpt_stop    PROC    NEAR
                PUSH    AX
                PUSH    DX
                MOV     DX, CS:[77H]
                ADD     DX, 2
                MOV     AL, ads_dss_ctrl_latch
                OUT     DX, AL
                POP     DX
                POP     AX
                MOV     BYTE PTR CS:[3BH], 0
                RET
ads_lpt_stop    ENDP

; ============================================================================
; 0x0C20  --  ads_slot_14
;
; XOR AX, AX; RET. A reserved-but-unused slot returning zero.
;
;   Type:        Slot handler (no-op stub returning zero)
;   Category:    DUDE ABI reserved
;   Dispatch:    Slot 14 (AX=14)
;   Callers:     Game (via dispatch)
;   Inputs:      none
;
;   Outputs:
;     AX     --  0
; ============================================================================
ads_slot_14     PROC    NEAR
                XOR     AX, AX
                RET
ads_slot_14     ENDP

; ============================================================================
; 0x0C23  --  ads_slot_09  --  load chunk from file
;
; The biggest slot handler. Loads a chunk of PCM samples from a .SOL
; file on disk for streaming playback. Slot arguments:
;
;   SS:[SI]      filename ptr offset (or 0 if reusing current handle)
;   SS:[SI+2]    filename ptr segment (or 0FFFFh = re-use, see below)
;   SS:[SI+4]    seek pos (low word)
;   SS:[SI+6]    seek pos (high word)
;   SS:[SI+8]    total length, low word
;   SS:[SI+0Ah]  total length, high word
;   SS:[SI+0Ch]  buffer offset
;   SS:[SI+0Eh]  buffer segment
;   SS:[SI+10h]  chunk words
;   SS:[SI+12h]  bank flag (0 = primary, !=0 = secondary)
;   SS:[SI+13h]  format flags (bitfield, see ads_apply_flags_bitfield)
;
; The handler stops any currently-playing sound (via slot_12 helper),
; decodes the bank flag and format flags, stashes the buffer geometry
; into ads_state, opens or reuses the file, seeks to seek_pos, parses
; the .SOL header if present (via ads_dos_file_open_sol), and finally
; sets the input rate via ads_pick_decimation.
;
;   Type:        Slot handler (largest in the file)
;   Category:    File loader / playback start
;   Dispatch:    Slot 9 (AX=9, SS:SI = 20-byte arg block as above)
;   Callers:     Game (via dispatch)
;   Callees:     ads_slot_12_helper_set_flag, ads_apply_flags_bitfield,
;                ads_dos_file_open_sol, ads_pick_decimation,
;                DOS INT 21h (AH=3Dh Open, AH=3Eh Close, AH=42h LSEEK)
;
;   Inputs:      see SS:[SI...SI+13h] table in the prose above
;
;   Outputs:
;     AX     --  estimated playback duration in ticks (or 0xFFFE on
;                overflow, or 0 on open/seek failure)
;
;   Side effects:
;     ads_playback_stopped (4Eh) <- 1
;     ads_use_remainder (42h), all 32-bit length and seek-pos fields,
;     buffer geometry (59h/5Fh/61h), and the format-flags byte all
;     written. ads_file_handle (6Dh) potentially closed/reopened.
;     INT 21h is invoked (Open, Seek; the .SOL parse calls Close).
; ============================================================================
ads_slot_09     PROC    NEAR
                PUSH    SI
                CALL    ads_slot_12_helper_set_flag ; stop current playback
                POP     SI

                ; Decode the bank flag at +0x12.
                CMP     BYTE PTR SS:[SI + 12H], 0
                JNE     SHORT s9_bank_one
                MOV     BYTE PTR CS:[42H], 0
                JMP     SHORT s9_after_bank
s9_bank_one:    MOV     BYTE PTR CS:[42H], 1

s9_after_bank:  ; Apply the format-flags bitfield (sample sign, byte
                ; swap, double-rate, etc.).
                MOV     AL, SS:[SI + 13H]
                CALL    ads_apply_flags_bitfield

                ; Copy buffer geometry into ads_state.
                MOV     AX, SS:[SI + 8]
                MOV     CS:[7BH], AX                ; remaining_lo / total_len_lo
                MOV     AX, SS:[SI + 0AH]
                MOV     CS:[7DH], AX                ; remaining_hi / total_len_hi
                MOV     AX, SS:[SI + 0CH]
                MOV     CS:[59H], AX                ; buf_off
                MOV     AX, SS:[SI + 0EH]
                MOV     CS:[5FH], AX                ; buf_seg
                MOV     AX, SS:[SI + 10H]
                SHR     AX, 1                       ; chunk_bytes -> chunk_words
                MOV     CS:[61H], AX

                ; Decode the filename pointer (offset:segment at +0..+2).
                ; (0:0) = reuse current handle, (X:0FFFFh) = "interp X
                ; as already-open handle", otherwise open it via INT 21h.
                MOV     AX, SS:[SI]
                OR      AX, SS:[SI + 2]
                JNE     SHORT s9_have_name
                MOV     BX, CS:[6DH]                ; BX = current handle
                JMP     SHORT s9_have_handle
s9_have_name:   CMP     WORD PTR SS:[SI + 2], 0FFFFH
                JNE     SHORT s9_open
                MOV     BX, SS:[SI]
                JMP     SHORT s9_save_handle
s9_open:        CMP     WORD PTR CS:[6DH], 0FFFFH
                JE      SHORT s9_do_open
                MOV     BX, CS:[6DH]                ; close prior handle first
                MOV     AH, 3EH
                INT     21H
                MOV     WORD PTR CS:[6DH], 0FFFFH
s9_do_open:     PUSH    DS
                MOV     DX, SS:[SI]                 ; DX = name offset
                MOV     AX, SS:[SI + 2]             ; AX = name segment
                MOV     DS, AX
                MOV     AL, 0
                MOV     AH, 3DH                     ; DOS Open-Handle, R/O
                INT     21H
                POP     DS
                JAE     SHORT s9_open_ok
                XOR     AX, AX
                RET
s9_open_ok:     MOV     BX, AX                      ; BX = new handle
s9_save_handle: MOV     CS:[6DH], BX

s9_have_handle: ; Seek to start of chunk (LSEEK absolute, from arg+4/+6).
                MOV     DX, SS:[SI + 4]
                MOV     CS:[6FH], DX                ; seek_pos_lo
                MOV     CX, SS:[SI + 6]
                MOV     CS:[71H], CX                ; seek_pos_hi
                MOV     AL, 0                       ; SEEK_SET
                MOV     AH, 42H                     ; DOS LSEEK
                INT     21H
                JAE     SHORT s9_seek_ok
                XOR     AX, AX
                RET

s9_seek_ok:     ; Read the file's first byte and parse a .SOL header
                ; (if present).
                CALL    ads_dos_file_open_sol

                ; Clear the smoothing/sign-invert flag and seed the
                ; running total fields from the slot's total-length.
                MOV     BYTE PTR CS:[49H], 0
                MOV     AX, CS:[7BH]
                MOV     BX, CS:[7DH]
                MOV     CS:[75H], AX                ; total_len_lo
                MOV     CS:[73H], BX                ; total_len_hi

                ; If double-rate (36h = 1), halve the running length so
                ; the engine's word counters track playback samples
                ; rather than file bytes.
                CMP     BYTE PTR CS:[36H], 1
                JNE     SHORT s9_no_dbl
                SHL     AX, 1
                RCL     BX, 1
s9_no_dbl:      MOV     CX, 3CH                     ; CX = 60 (= 60 Hz units?)
                MUL     CX                          ; DX:AX = AX * CX
                PUSH    AX
                PUSH    DX
                MOV     AX, BX
                MUL     CX
                POP     DX
                ADD     DX, AX
                POP     AX
                CMP     DX, CS:[79H]                ; overflow vs disney rate?
                JAE     SHORT s9_overflow
                DIV     WORD PTR CS:[79H]           ; AX = bytes/sample @ DSS rate
                JMP     SHORT s9_return
s9_overflow:    MOV     AX, 0FFFEH                  ; clamp
s9_return:      RET
ads_slot_09     ENDP

; ============================================================================
; 0x0D24  --  ads_apply_flags_bitfield
;
; Decodes a packed flags byte (AL) into six 1-byte booleans in the
; ads_state region. The bit assignments:
;
;   bit 0  ->  ads_dbl_rate          (36h)   1 = double the sample rate
;   bit 1  ->  ads_sign_invert       (4Ah)   1 = flip top bit of samples
;   bit 2  ->  ads_byteswap          (4Ch)   1 = swap bytes on file read
;   bit 3  ->  ads_subt_from_max     (4Bh)   1 = AL = 0x7F - sample
;   bit 4  ->  ads_unknown_4d        (4Dh)
;   bit 7  ->  ads_flag_high_bit     (45h)
;
; The very first action also seeds ads_smooth_accum (37h) = 0x80 (the
; midpoint of the 7-bit DAC range), so smoothing always starts centred.
;
;   Type:        Internal helper
;   Category:    Format-flags decode
;   Callers:     ads_slot_09, ads_dos_file_open_sol
;
;   Inputs:
;     AL     --  packed flags byte; bits 0-4 + bit 7 each map to a
;                separate ads_state byte (see table above)
;
;   Outputs:     none
;
;   Touches:     AL (not restored)
;
;   Side effects:
;     ads_smooth_accum (37h) <- 0x80 (always reseeds the smoothing
;     state)
;     ads_dbl_rate (36h), ads_sign_invert (4Ah), ads_byteswap (4Ch),
;     ads_subt_from_max (4Bh), ads_unknown_4d (4Dh),
;     ads_flag_high_bit (45h) <- 1 or 0 per the bits in AL
; ============================================================================
ads_apply_flags_bitfield PROC NEAR
                MOV     BYTE PTR CS:[37H], 80H      ; seed smoothing accum

                TEST    AL, 1
                JE      SHORT af_bit0_clr
                MOV     BYTE PTR CS:[36H], 1
                JMP     SHORT af_bit1
af_bit0_clr:    MOV     BYTE PTR CS:[36H], 0

af_bit1:        TEST    AL, 2
                JE      SHORT af_bit1_clr
                MOV     BYTE PTR CS:[4AH], 1
                JMP     SHORT af_bit2
af_bit1_clr:    MOV     BYTE PTR CS:[4AH], 0

af_bit2:        TEST    AL, 4
                JE      SHORT af_bit2_clr
                MOV     BYTE PTR CS:[4CH], 1
                JMP     SHORT af_bit3
af_bit2_clr:    MOV     BYTE PTR CS:[4CH], 0

af_bit3:        TEST    AL, 8
                JE      SHORT af_bit3_clr
                MOV     BYTE PTR CS:[4BH], 1
                JMP     SHORT af_bit4
af_bit3_clr:    MOV     BYTE PTR CS:[4BH], 0

af_bit4:        TEST    AL, 10H
                JE      SHORT af_bit4_clr
                MOV     BYTE PTR CS:[4DH], 1
                JMP     SHORT af_bit7
af_bit4_clr:    MOV     BYTE PTR CS:[4DH], 0

af_bit7:        TEST    AL, 80H
                JE      SHORT af_bit7_clr
                MOV     BYTE PTR CS:[45H], 1
                JMP     SHORT af_done
af_bit7_clr:    MOV     BYTE PTR CS:[45H], 0
af_done:        RET
ads_apply_flags_bitfield ENDP

; ============================================================================
; 0x0D97  --  ads_dos_file_open_sol
;
; Read the first byte of the opened .SOL file. If it equals 0x8D, the
; file uses Dynamix's compact .SOL-format header:
;
;   off  size  field
;   ---  ----  -----------------------------------------
;    0   1     marker byte 0x8D
;    1   1     header length (in 16-bit words after the marker, big-end)
;    2   3     ASCII "SOL"
;    5   1     0x00 terminator
;    6   2     sample-rate-related value (big-endian, see LODSW below)
;    8   1     length / flags byte
;    9   2     ads_state[7B,7D] -- chunk length (low / high words)
;    B   2     misc 16-bit field
;
; If the marker doesn't match, the file is treated as raw PCM and the
; driver just seeks back to where it was (cs:[6F]/[71]) and returns.
;
; On a successful header parse this updates ads_remaining_{lo,hi}
; (7Bh/7Dh) with the parsed chunk lengths and reprograms the rate
; (via ads_pick_decimation).
;
;   Type:        Internal helper
;   Category:    .SOL file parser
;   Callers:     ads_slot_09 (after opening + seeking the file)
;   Callees:     ads_apply_flags_bitfield, ads_pick_decimation,
;                DOS INT 21h (AH=3Fh Read, AH=42h LSEEK)
;
;   Inputs:      none (reads ads_file_handle at 6Dh,
;                ads_buf_off / ads_buf_seg, saved seek pos at 6Fh:71h)
;
;   Outputs:     none
;
;   Touches:     AX, BX, CX, DX, SI, DS (DS pushed/popped)
;
;   Side effects:
;     Two INT 21h reads (first 2 bytes, then header tail) plus possibly
;     an LSEEK to back up to the original chunk position if the file
;     turns out to be raw PCM (no .SOL header).
;     On successful header parse:
;       ads_seek_pos_lo (6Fh), ads_seek_pos_hi (71h) advanced past header
;       ads_remaining_lo (7Bh), ads_remaining_hi (7Dh) <- parsed length
;       format-flags byte applied via ads_apply_flags_bitfield
;       ads_sample_rate_in (6Bh) <- parsed rate; decimation reprogrammed
; ============================================================================
ads_dos_file_open_sol PROC NEAR
                MOV     BX, CS:[6DH]                ; BX = file handle
                MOV     CX, 2
                MOV     DX, CS:[59H]                ; DX = buf_off
                MOV     AX, CS:[5FH]                ; AX = buf_seg
                PUSH    DS
                MOV     DS, AX
                MOV     SI, DX
                MOV     AH, 3FH                     ; DOS Read-Handle
                INT     21H

                LODSB
                CMP     AL, 8DH                     ; .SOL marker?
                JNE     SHORT ds_raw_pcm
                LODSB                               ; AL = header length
                MOV     CL, AL
                MOV     SI, DX
                MOV     AH, 3FH
                INT     21H                         ; read CX more bytes
                LODSB
                CMP     AL, 53H                     ; 'S'
                JNE     SHORT ds_raw_pcm
                LODSB
                CMP     AL, 4FH                     ; 'O'
                JNE     SHORT ds_raw_pcm
                LODSB
                CMP     AL, 4CH                     ; 'L'
                JNE     SHORT ds_raw_pcm
                LODSB
                CMP     AL, 0                       ; 'NUL'
                JE      SHORT ds_parse_header
ds_raw_pcm:     POP     DS
                ; Raw PCM: just seek back to the original chunk start.
                MOV     DX, CS:[6FH]                ; saved seek_pos_lo
                MOV     CX, CS:[71H]
                MOV     AL, 0
                MOV     AH, 42H                     ; DOS LSEEK
                INT     21H
                RET

ds_parse_header: ; Advance the saved seek pos by CX+2 (header length).
                ADD     CX, 2
                ADD     CS:[6FH], CX
                ADC     WORD PTR CS:[71H], 0
                LODSB
                MOV     AH, AL                      ; AH = first rate-byte
                LODSB
                XCHG    AL, AH                      ; swap to little-endian
                PUSH    AX                          ; save the 16-bit rate
                LODSB
                MOV     CL, AL                      ; CL = length / flags
                LODSW                               ; AX = chunk_lo
                MOV     BX, AX
                LODSW
                MOV     DX, AX                      ; DX = misc field
                POP     AX                          ; AX = saved rate
                POP     DS

                MOV     CS:[7BH], BX                ; remaining_lo
                MOV     CS:[7DH], DX                ; remaining_hi
                PUSH    AX
                MOV     AL, CL                      ; AL = flags byte
                CALL    ads_apply_flags_bitfield
                POP     AX
                MOV     CS:[6BH], AX                ; cache input rate
                CALL    ads_pick_decimation
                RET
ads_dos_file_open_sol ENDP

; ============================================================================
; 0x0E1E  --  ads_slot_10  --  resume from paused
;
; Sets pause_pending (49h), forces target_bank to 0xFF (sentinel), clears
; active_bank (3Dh), and calls the engine twice to flush both halves of
; the ring buffer.
;
;   Type:        Slot handler
;   Category:    Playback resume
;   Dispatch:    Slot 10 (AX=10, no SS:SI args)
;   Callers:     Game (via dispatch)
;   Callees:     ads_playback_engine (twice)
;
;   Inputs:      none
;
;   Outputs:
;     AX     --  0
;
;   Side effects:
;     ads_pause_pending (49h) <- 1
;     ads_target_bank (48h) <- 0xFF (sentinel)
;     ads_active_bank (3Dh) <- 0
;     Engine invoked twice (fills both halves of the ring buffer).
; ============================================================================
ads_slot_10     PROC    NEAR
                MOV     BYTE PTR CS:[49H], 1
                MOV     BYTE PTR CS:[48H], 0FFH
                MOV     BYTE PTR CS:[3DH], 0
                CALL    ads_playback_engine
                CALL    ads_playback_engine
                XOR     AX, AX
                RET
ads_slot_10     ENDP

; ============================================================================
; 0x0E39  --  ads_slot_11  --  IRQ setup / reset key state
;
; If the input rate isn't already programmed (cs:[6Bh] != cs:[79h]),
; reprogram via ads_pick_decimation. Then prime init_done (3Ch=1),
; clear running totals (65h/63h), bounce the engine, and set
; target_bank = 1.
;
;   Type:        Slot handler
;   Category:    IRQ setup / key-state reset
;   Dispatch:    Slot 11 (AX=11, no SS:SI args)
;   Callers:     Game (via dispatch)
;   Callees:     ads_pick_decimation, ads_playback_engine, ads_tick
;
;   Inputs:      none
;
;   Outputs:
;     AX     --  0
;
;   Side effects:
;     ads_init_done (3Ch) <- 1
;     ads_target_bank (48h) <- 0xFF then 1 (sentinel-then-program)
;     ads_active_bank (3Dh) bounced through 0xFF during ads_tick
;     ads_bytes_streamed (65h:63h) <- 0
;     ads_no_kick_eof (46h) <- 0
;     ads_playback_stopped (4Eh) <- 0
;     ads_pause_pending (49h) <- 0 (in the "paused" branch)
;     Engine + tick invoked.
; ============================================================================
ads_slot_11     PROC    NEAR
                MOV     AX, CS:[6BH]                ; cached input rate
                CMP     AX, CS:[79H]                ; current pick value
                JE      SHORT s11_rate_ok
                CALL    ads_pick_decimation
s11_rate_ok:    MOV     BYTE PTR CS:[3CH], 1        ; init_done
                CMP     BYTE PTR CS:[49H], 1        ; pause_pending?
                JE      SHORT s11_paused
                MOV     BYTE PTR CS:[48H], 0FFH
                MOV     BYTE PTR CS:[3DH], 0
                CALL    ads_playback_engine
                CALL    ads_playback_engine
                JMP     SHORT s11_continue
s11_paused:     MOV     BYTE PTR CS:[49H], 0
s11_continue:   MOV     BYTE PTR CS:[48H], 1
                MOV     WORD PTR CS:[65H], 0
                MOV     WORD PTR CS:[63H], 0
                MOV     AL, CS:[3DH]                ; save active_bank
                PUSH    AX
                MOV     BYTE PTR CS:[3DH], 0FFH     ; sentinel
                CALL    ads_tick
                POP     AX
                MOV     CS:[3DH], AL                ; restore
                MOV     BYTE PTR CS:[46H], 0
                MOV     BYTE PTR CS:[4EH], 0
                XOR     AX, AX
                RET
ads_slot_11     ENDP

; ============================================================================
; 0x0EA5  --  ads_playback_engine
;
; The big sample-streaming engine. Called by the slot_01 pump-tick
; path, by slot_10 (resume), and by slot_11 (IRQ setup). Reads the
; next chunk of bytes from the open .SOL file via INT 21h, applies any
; format conversions configured in ads_state (byteswap, sign-invert,
; smoothing with the 8-byte init curve), pushes the resulting PCM
; samples into the ring buffer, and bumps the running counter at
; 65h:63h.
;
; The body is large and dense -- it inlines the byte-swap loop, the
; sign-invert loop, and the 4-bit-per-sample smoothing-curve unpack.
;
; Returns: no explicit value (last op is POPF / RET).
;
;   Type:        Internal helper (hot path; the streaming engine)
;   Category:    Sample format conversion + ring-buffer fill
;   Callers:     ads_slot_01_play, ads_slot_10, ads_slot_11
;   Callees:     ads_query_status, DOS INT 21h (AH=3Fh Read,
;                AH=42h LSEEK)
;
;   Inputs:      none (reads engine state across ads_state)
;
;   Outputs:     none
;
;   Touches:     all GPRs and DS / ES used (saved/restored around the
;                conversion sub-loops; the outer flags are saved with
;                PUSHF / POPF so the caller's IF is preserved)
;
;   Side effects:
;     ads_busy_engine (40h) set during execution, cleared at exit.
;     Reads the next chunk from ads_file_handle (6Dh) via INT 21h.
;     Optionally byteswaps + sign-inverts + dbl-rate-smooths the bytes
;     into the ring buffer at (ads_buf_seg : ads_buf_off + DI).
;     ads_active_bank (3Dh) flipped at exit; ring_size_lo (4Fh) or
;     ring_size_hi (51h) updated; ads_engine_consumed (67h) tracks
;     bytes for end-of-stream re-seed; ads_smooth_accum (37h) updated.
; ============================================================================
ads_playback_engine PROC NEAR
                CMP     BYTE PTR CS:[40H], 1        ; busy_engine set?
                JE      SHORT pe_already_busy
                MOV     AX, CS:[7BH]
                OR      AX, CS:[7DH]                ; remaining == 0?
                JE      SHORT pe_already_busy
                MOV     AL, CS:[3DH]
                CMP     AL, CS:[48H]                ; active_bank == target?
                JE      SHORT pe_already_busy
                ; Query the int-busy flags; if all clear (ZF=1) we
                ; jump past the early RET and into the engine body.
                CALL    ads_query_status
                JE      SHORT pe_run                ; AL=0 idle -> continue
pe_already_busy: RET
pe_run:         MOV     BYTE PTR CS:[40H], 1        ; mark engine busy
                PUSHF
                STI                                 ; allow interrupts

                MOV     WORD PTR CS:[67H], 0        ; consumed = 0
                MOV     CX, CS:[61H]                ; CX = chunk_words

                ; If active_bank is "primary half" (0), DX = 0 (start
                ; of ring); else DX = CX (start of second half).
                CMP     BYTE PTR CS:[3DH], 0
                JNE     SHORT pe_bank_one
                MOV     DX, 0
                JMP     SHORT pe_have_dx
pe_bank_one:    MOV     DX, CX

pe_have_dx:     ; byteswap (4Ch) doubles the byte count; dbl_rate (36h)
                ; halves it (the engine works in "playback samples"
                ; throughout).
                CMP     BYTE PTR CS:[4CH], 1
                JNE     SHORT pe_no_byteswap_x2
                SHL     CX, 1
pe_no_byteswap_x2: CMP   BYTE PTR CS:[36H], 1
                JNE     SHORT pe_no_dbl_halve
                SHR     CX, 1

pe_no_dbl_halve: ; Don't read beyond the remaining count.
                CMP     WORD PTR CS:[7DH], 0
                JNE     SHORT pe_have_count
                CMP     CX, CS:[7BH]
                JBE     SHORT pe_have_count
                MOV     CX, CS:[7BH]

pe_have_count:  ; Subtract this read from remaining_{lo,hi}.
                SUB     CS:[7BH], CX
                SBB     WORD PTR CS:[7DH], 0
                MOV     DI, DX
                CMP     BYTE PTR CS:[36H], 1
                JNE     SHORT pe_no_dbl_add
                ADD     DX, CX

pe_no_dbl_add:
pe_read_setup:  MOV     BX, CS:[6DH]                ; BX = file handle
                MOV     AX, CS:[5FH]                ; AX = buf_seg

                ; Byteswap path: read CX bytes into a tmp buffer at
                ; DS:0x91, then walk it word-by-word writing the
                ; byteswapped output via STOSB.
                CMP     BYTE PTR CS:[4CH], 1
                JNE     SHORT pe_no_byteswap_read
                MOV     ES, AX
                MOV     DX, 91H                     ; tmp buffer offset
                MOV     AX, DS                      ; AX = current DS
                CMP     CX, 800H                    ; >2048?
                JBE     SHORT pe_under_2048
                MOV     CS:[69H], CX                ; save total
                MOV     CX, 800H                    ; cap at 2048
                SUB     CS:[69H], CX
                JMP     SHORT pe_no_byteswap_read
pe_under_2048:  MOV     WORD PTR CS:[69H], 0

pe_no_byteswap_read: MOV SI, DX
                PUSH    DS
                MOV     DS, AX
                MOV     AH, 3FH
                INT     21H                         ; DOS read CX bytes
                POP     DS
                JAE     SHORT pe_read_ok
                MOV     AX, CX                      ; on error, assume CX
pe_read_ok:     CMP     BYTE PTR CS:[4CH], 1
                JNE     SHORT pe_after_byteswap
                ; Byteswap stage: AX = bytes read; halve it (word
                ; count) and walk SI/DI doing the swap.
                SHR     AX, 1
                PUSH    AX
                PUSH    SI
                PUSH    DI
                MOV     CX, AX
pe_swap_loop:   LODSW
                CMP     BYTE PTR CS:[4BH], 1
                JNE     SHORT pe_no_subt
                MOV     AL, ads_dac_midscale
                SUB     AL, AH
                JMP     SHORT pe_write_swap
pe_no_subt:     MOV     AL, AH
pe_write_swap:  STOSB
                LOOP    pe_swap_loop
                POP     DI
                POP     SI
                POP     AX

pe_after_byteswap: CMP  BYTE PTR CS:[4AH], 1        ; sign-invert?
                JNE     SHORT pe_after_sign
                PUSH    AX
                PUSH    SI
                PUSH    DI
                PUSH    DS
                MOV     CX, AX
                MOV     AX, CS:[5FH]
                MOV     DS, AX
                MOV     ES, AX
pe_sign_loop:   LODSB
                ROL     AX, 1                       ; (only AL meaningful)
                STOSB
                LOOP    pe_sign_loop
                POP     DS
                POP     DI
                POP     SI
                POP     AX

pe_after_sign:  CMP     BYTE PTR CS:[36H], 1        ; dbl_rate?
                JNE     SHORT pe_after_dbl
                PUSH    AX
                PUSH    BX
                PUSH    DX
                PUSH    SI
                PUSH    DI
                PUSH    DS
                MOV     CX, AX
                MOV     DL, CS:[37H]                ; DL = smoothing accum
                MOV     AX, CS:[5FH]
                MOV     DS, AX
                MOV     ES, AX
                MOV     AH, DL                      ; AH = scratch accum
pe_dbl_loop:    LODSB
                MOV     DL, AL                      ; DL = nibble carrier
                SHR     AL, 1
                SHR     AL, 1
                SHR     AL, 1
                SHR     AL, 1                       ; AL = high nibble
                CMP     AL, 8
                JL      SHORT pe_hi_pos
                MOV     BX, 0FH
                SUB     BL, AL
                SUB     AH, CS:[BX + ads_init_curve]
                JMP     SHORT pe_hi_done
pe_hi_pos:      MOV     BL, AL
                XOR     BH, BH
                ADD     AH, CS:[BX + ads_init_curve]
pe_hi_done:     MOV     AL, AH
                STOSB
                AND     DL, 0FH                     ; AL = low nibble
                CMP     DL, 8
                JL      SHORT pe_lo_pos
                MOV     BX, 0FH
                SUB     BL, DL
                SUB     AH, CS:[BX + ads_init_curve]
                JMP     SHORT pe_lo_done
pe_lo_pos:      MOV     BL, DL
                XOR     BH, BH
                ADD     AH, CS:[BX + ads_init_curve]
pe_lo_done:     MOV     AL, AH
                STOSB
                LOOP    pe_dbl_loop
                POP     DS
                MOV     CS:[37H], AH                ; persist accum
                POP     DI
                POP     SI
                POP     DX
                POP     BX
                POP     AX
                SHL     AX, 1                       ; bytes -> playback bytes

pe_after_dbl:   ADD     CS:[67H], AX                ; consumed += bytes
                CMP     BYTE PTR CS:[4CH], 1
                JNE     SHORT pe_after_split
                CMP     WORD PTR CS:[69H], 0
                JE      SHORT pe_after_split
                ; Byteswap split: still more bytes left in 0x800+ chunk.
                ADD     DI, AX
                MOV     CX, CS:[69H]
                JMP     pe_read_setup

pe_after_split: CMP     BYTE PTR CS:[42H], 1        ; use_remainder?
                JNE     SHORT pe_after_remainder
                MOV     CX, CS:[7BH]
                OR      CX, CS:[7DH]
                JNE     SHORT pe_after_remainder
                ; End-of-stream: write the running totals into the
                ; 32-bit byte counters, then re-seek the file to
                ; the saved seek position and replay the chunk.
                MOV     CS:[65H], CX                ; both zero
                MOV     CS:[63H], CX
                PUSH    AX
                PUSH    DX
                MOV     DX, CS:[6FH]
                MOV     CX, CS:[71H]
                MOV     AL, 0
                MOV     AH, 42H                     ; LSEEK
                INT     21H
                POP     DX
                POP     AX
                MOV     CX, CS:[75H]
                MOV     CS:[7BH], CX
                MOV     CX, CS:[73H]
                MOV     CS:[7DH], CX
                CMP     BYTE PTR CS:[36H], 1
                JNE     SHORT pe_no_reseed
                MOV     BYTE PTR CS:[37H], 80H      ; reseed smoothing
                SHR     AX, 1
pe_no_reseed:   MOV     CX, CS:[61H]
                SUB     CX, CS:[67H]
                JE      SHORT pe_after_remainder
                ADD     DX, AX
                JMP     pe_have_dx                  ; restart pump

pe_after_remainder: MOV AX, CS:[67H]
                CMP     BYTE PTR CS:[3DH], 0
                JNE     SHORT pe_to_size_hi
                MOV     CS:[4FH], AX                ; ring_size_lo = consumed
                JMP     SHORT pe_finalize
pe_to_size_hi:  MOV     CS:[51H], AX                ; ring_size_hi = consumed
pe_finalize:    XOR     BYTE PTR CS:[3DH], 1        ; flip active_bank
                MOV     BYTE PTR CS:[40H], 0        ; engine no longer busy
                POPF
                RET
ads_playback_engine ENDP

; ============================================================================
; 0x10D2  --  ads_tick
;
; The slot_01 sub-tick. If a video INT is in progress (41h), skip;
; otherwise:
;
;   * Save in_videoint = 1.
;   * If (target_bank XOR 1) == active_bank, the ring is exactly half
;     swapped; if remaining bytes are zero we've reached EOF and we
;     fire the "playback stopped" helper. Otherwise we flip
;     target_bank and tick the recompute engine.
;   * Clear in_videoint.
;
;   Type:        Internal helper
;   Category:    Bank-swap scheduling
;   Callers:     ads_slot_01_play (per pump tick), ads_slot_11
;   Callees:     ads_slot_12_helper_set_flag, ads_recompute_stream
;
;   Inputs:      none (reads ads_in_pump (3Fh), ads_target_bank (48h),
;                ads_active_bank (3Dh), ads_remaining_lo/hi (7Bh/7Dh))
;
;   Outputs:     none
;
;   Touches:     AX (not restored)
;
;   Side effects:
;     ads_in_pump (3Fh) toggled around the body (re-entry guard).
;     If EOF: ads_playback_stopped (4Eh) <- 1.
;     Otherwise ads_target_bank (48h) toggled; ads_recompute_stream
;     potentially called.
; ============================================================================
ads_tick        PROC    NEAR
                CMP     BYTE PTR CS:[3FH], 1
                JE      SHORT tk_skip
                MOV     BYTE PTR CS:[3FH], 1
                MOV     AL, CS:[48H]
                XOR     AL, 1
                CMP     AL, CS:[3DH]
                JNE     SHORT tk_flip
                MOV     AX, CS:[7BH]
                OR      AX, CS:[7DH]
                JNE     SHORT tk_unlock
                CALL    ads_slot_12_helper_set_flag
                JMP     SHORT tk_unlock
tk_flip:        XOR     BYTE PTR CS:[48H], 1
                CALL    ads_recompute_stream
tk_unlock:      MOV     BYTE PTR CS:[3FH], 0
tk_skip:        RET
ads_tick        ENDP

; ============================================================================
; 0x110D  --  ads_slot_13  --  query position (3 dwords into SS:SI)
;
; Three states:
;
;   * If pause_pending (49h) is set, zero out three dwords at SS:[SI..SI+5]
;     and return.
;   * If playback_stopped (4Eh) is set, write 0xFFFF into all three dwords.
;   * Otherwise: compute current play position as
;       (bytes_streamed + ring_pos - ring_lo) and write it back, plus
;       a scaled "samples played" value.
;
;   Type:        Slot handler
;   Category:    State query
;   Dispatch:    Slot 13 (AX=13, SS:SI = pointer to 3-dword output area)
;   Callers:     Game (via dispatch), to poll "where are we in the song"
;
;   Inputs:
;     SS:SI  --  pointer to a 6-word output buffer (3 dwords)
;
;   Outputs:
;     AX     --  0
;     SS:[SI..SI+5]  --  three dwords describing current play position
;                        (see body for the per-state semantics)
;
;   Side effects:
;     Briefly disables interrupts (PUSHF/CLI/POPF) while reading the
;     32-bit running counters atomically.
; ============================================================================
ads_slot_13     PROC    NEAR
                CMP     BYTE PTR CS:[49H], 1
                JNE     SHORT s13_not_paused
                MOV     WORD PTR SS:[SI], 0
                MOV     WORD PTR SS:[SI + 2], 0
                MOV     WORD PTR SS:[SI + 4], 0
                XOR     AX, AX
                RET
s13_not_paused: CMP     BYTE PTR CS:[4EH], 1
                JNE     SHORT s13_playing
                MOV     WORD PTR SS:[SI], 0FFFFH
                MOV     WORD PTR SS:[SI + 2], 0FFFFH
                MOV     WORD PTR SS:[SI + 4], 0FFFFH
                XOR     AX, AX
                RET
s13_playing:    PUSHF
                CLI
                MOV     AX, CS:[65H]                ; bytes_streamed_lo
                MOV     BX, CS:[63H]                ; bytes_streamed_hi
                ADD     AX, CS:[5BH]                ; + ring_pos_lo
                ADC     BX, 0
                SUB     AX, CS:[53H]
                SBB     BX, 0
                POPF
                CMP     BYTE PTR CS:[4CH], 1
                JNE     SHORT s13_no_dbl
                SHL     AX, 1
                RCL     BX, 1
                MOV     CX, 1EH                     ; 30 (= 60/2)
                JMP     SHORT s13_have_cx
s13_no_dbl:     MOV     CX, 3CH                     ; 60
s13_have_cx:    MOV     SS:[SI + 2], AX
                MOV     SS:[SI + 4], BX
                MUL     CX
                PUSH    AX
                PUSH    DX
                MOV     AX, BX
                MUL     CX
                POP     DX
                ADD     DX, AX
                POP     AX
                CMP     DX, CS:[79H]
                JAE     SHORT s13_overflow
                DIV     WORD PTR CS:[79H]
                JMP     SHORT s13_store
s13_overflow:   MOV     AX, 0FFFEH
s13_store:      MOV     SS:[SI], AX
                XOR     AX, AX
                RET
ads_slot_13     ENDP

; ============================================================================
; 0x11A0  --  ads_query_status
;
; Read the byte pointed to by ads_indos_p (81h:83h, the InDOS flag) and
; OR in the critical-section byte at (85h:87h), then OR in the
; in_videoint (41h) and in_mouseint (3Eh) flags. Returns the result
; in AL; ZF reflects "all idle".
;
;   Type:        Internal helper
;   Category:    Re-entry guard
;   Callers:     ads_playback_engine
;
;   Inputs:      none (reads ads_indos_p (81h:83h),
;                ads_critical_p (85h:87h), ads_in_videoint (41h),
;                ads_in_mouseint (3Eh))
;
;   Outputs:
;     AL     --  OR of all four busy / in-int byte flags
;     ZF     --  set when all four are clear (i.e. it's safe to run
;                the engine right now)
;
;   Touches:     AL, BX, ES (not restored)
; ============================================================================
ads_query_status PROC   NEAR
                LES     BX, CS:[81H]
                MOV     AL, ES:[BX]                 ; AL = *indos
                LES     BX, CS:[85H]
                OR      AL, ES:[BX]                 ; OR *critical
                OR      AL, CS:[41H]                ; OR in_videoint
                OR      AL, CS:[3EH]                ; OR in_mouseint
                RET
ads_query_status ENDP

; ============================================================================
; 0x11BB  --  ads_int10_stub  (hooked into INT 10h)
;
; Installed by ads_slot_00_init via DOS Set-Vector. Sets in_videoint
; (41h) for the duration of the chained call, invokes the previously-
; saved INT 10h handler at cs:[8Dh], and clears the flag on return.
; The flag lets ads_query_status and ads_playback_engine know "the
; engine must not run right now -- a BIOS-video call has us busy".
; Returns to the original caller via IRET (interrupt return).
;
;   Type:        Interrupt handler (INT 10h hook, IRET-terminated)
;   Category:    BIOS / mouse re-entry guard
;   Callers:     CPU (via the INT 10h vector, installed in
;                ads_slot_00_init)
;   Callees:     The previously-saved INT 10h handler at cs:[8Dh]
;
;   Inputs:      whatever the BIOS INT 10h caller put in registers
;                (we pass them through unchanged via PUSHF / CALL FAR)
;
;   Outputs:     whatever the chained INT 10h handler returns
;
;   Side effects:
;     ads_in_videoint (41h) <- 1 around the chained call, <- 0 after.
;
;   Notes:       Uses PROC NEAR for TASM's benefit but actually
;                returns via IRET because this is an interrupt-gate
;                entry, not a normal subroutine. The caller is the
;                CPU's interrupt mechanism, not a CALL instruction.
; ============================================================================
ads_int10_stub  PROC    NEAR
                MOV     BYTE PTR CS:[41H], 1
                PUSHF
                CALL    DWORD PTR CS:[8DH]
                MOV     BYTE PTR CS:[41H], 0
                IRET
ads_int10_stub  ENDP

; ============================================================================
; 0x11CE  --  ads_int33_stub  (hooked into INT 33h)
;
; The mouse-int counterpart of ads_int10_stub. Sets in_mouseint (3Eh),
; chains to the saved INT 33h handler at cs:[89h], clears the flag,
; and IRETs.
;
;   Type:        Interrupt handler (INT 33h hook, IRET-terminated)
;   Category:    BIOS / mouse re-entry guard
;   Callers:     CPU (via the INT 33h vector, installed in
;                ads_slot_00_init)
;   Callees:     The previously-saved INT 33h handler at cs:[89h]
;
;   Inputs:      whatever the mouse-int caller put in registers
;                (passed through unchanged via PUSHF / CALL FAR)
;
;   Outputs:     whatever the chained INT 33h handler returns
;
;   Side effects:
;     ads_in_mouseint (3Eh) <- 1 around the chained call, <- 0 after.
;
;   Notes:       Same PROC NEAR / IRET trick as ads_int10_stub above.
; ============================================================================
ads_int33_stub  PROC    NEAR
                MOV     BYTE PTR CS:[3EH], 1
                PUSHF
                CALL    DWORD PTR CS:[89H]
                MOV     BYTE PTR CS:[3EH], 0
                IRET
ads_int33_stub  ENDP

; ============================================================================
; 0x11E1  --  ads_slot_00_init  --  detect chip, hook INT 10h / INT 33h
;
; Called once at driver-load time.
;
;   1. Probe for LPT-port presence via ads_detect_wrapper (returns ZF=1
;      if some LPT base is usable). On failure, return AX=0.
;   2. Set "playback stopped" so no engine runs while we're setting up.
;   3. If the byte at 0x12FD ("trailing magic") is 0xCD, ask DOS for
;      the InDOS flag pointer (INT 21h AH=19h then AX=150Bh INT 2Fh)
;      and bail out if the result doesn't match 0xADAD. (See note at
;      ads_trailing_magic.) The 0x12FD byte is 0xDC in the released
;      build so this path is NOT taken.
;   4. Save and replace INT 10h vector -> ads_int10_stub.
;   5. Save and replace INT 33h vector -> ads_int33_stub.
;   6. Get DOS critical-section flag (INT 21h AH=34h) -> cs:[85h] and a
;      copy at cs:[81h] (offset -1 from BX so the OR in ads_query_status
;      walks one byte earlier).
;   7. Seed input rate to 11025 Hz (0x2B11) and call ads_pick_decimation.
;   8. Clear busy/in-int flags, reset file handle to 0xFFFFh, return
;      AX = (11E1h | 8000h) -- the driver's "I'm initialized" magic.
;
;   Type:        Slot handler (one-time init)
;   Category:    Driver init / hardware detection
;   Dispatch:    Slot 0 (AX=0, no SS:SI args)
;   Callers:     Game (via dispatch), at driver-load time only
;   Callees:     ads_detect_wrapper, ads_pick_decimation,
;                DOS INT 21h (AH=19h, 25h, 34h, 35h), INT 2Fh AX=150Bh
;
;   Inputs:      none
;
;   Outputs:
;     AX     --  on failure: 0
;                on success: 0x91E1 (= ads_slot_00_init offset 0x11E1
;                            OR'd with 0x8000 "I am resident" flag)
;
;   Side effects:
;     INT 10h, INT 33h vectors replaced with our stubs; the originals
;     are saved at cs:[8Dh]/[8Fh] and cs:[89h]/[8Bh] respectively.
;     ads_indos_p (81h:83h), ads_critical_p (85h:87h) populated from
;     DOS INT 21h AH=34h.
;     ads_sample_rate_in (6Bh) <- 0x2B11 (11025 Hz); decimation
;     programmed accordingly.
;     ads_file_handle (6Dh) <- 0xFFFF (no file open).
;     ads_busy_engine (40h), ads_in_pump (3Fh) <- 0.
;     ads_playback_stopped (4Eh) <- 1.
; ============================================================================
ads_slot_00_init PROC   NEAR
                CALL    ads_detect_wrapper
                JE      SHORT s0_chip_ok
                XOR     AX, AX
                RET
s0_chip_ok:     MOV     BYTE PTR CS:[4EH], 1        ; stop any playback

                ; Optional InDOS probe path (skipped in the released
                ; build because the byte at 12FDh is 0xDC, not 0xCD).
                CMP     BYTE PTR CS:[12FDH], 0CDH
                JNE     SHORT s0_install_vec
                MOV     AH, 19H                     ; (dummy DOS call)
                INT     21H
                XOR     AH, AH
                MOV     CX, AX
                MOV     BX, 0
                MOV     AX, 150BH                   ; INT 2Fh "Get Share"
                INT     2FH
                CMP     BX, 0ADADH
                JE      SHORT s0_indos_ok
                XOR     AX, AX
                RET
s0_indos_ok:    OR      AX, AX
                JNE     SHORT s0_install_vec
                XOR     AX, AX
                RET

s0_install_vec: ; Save current INT 10h vector, install our stub.
                MOV     AH, 35H                     ; DOS Get-Vector
                MOV     AL, 10H
                INT     21H
                MOV     CS:[8DH], BX
                MOV     CS:[8FH], ES
                PUSH    DS
                MOV     DX, OFFSET ads_int10_stub   ; = 11BBH
                MOV     AX, CS
                MOV     DS, AX
                MOV     AH, 25H                     ; DOS Set-Vector
                MOV     AL, 10H
                INT     21H
                POP     DS

                ; Save current INT 33h, install our stub.
                MOV     AH, 35H
                MOV     AL, 33H
                INT     21H
                MOV     CS:[89H], BX
                MOV     CS:[8BH], ES
                PUSH    DS
                MOV     DX, OFFSET ads_int33_stub   ; = 11CEH
                MOV     AX, CS
                MOV     DS, AX
                MOV     AH, 25H
                MOV     AL, 33H
                INT     21H
                POP     DS

                ; Get DOS critical-section flag (ES:BX).
                MOV     AH, 34H                     ; DOS Get-CritFlag
                INT     21H
                MOV     CS:[85H], BX
                MOV     CS:[87H], ES
                DEC     BX                          ; back one byte
                MOV     CS:[81H], BX
                MOV     CS:[83H], ES

                ; Seed the input rate to 11025 Hz and program decimation.
                MOV     AX, 2B11H                   ; 11025 Hz
                MOV     CS:[6BH], AX
                CALL    ads_pick_decimation

                ; Clear in-int / busy flags, mark no file open.
                MOV     BYTE PTR CS:[40H], 0
                MOV     BYTE PTR CS:[3FH], 0
                MOV     WORD PTR CS:[6DH], 0FFFFH

                ; Return AX = 0x91E1 -- the "init OK" magic the loader
                ; expects to see. The high bit (0x8000) is the "I'm
                ; resident, leave me alive" flag.
                MOV     AX, OFFSET ads_slot_00_init ; = 11E1H
                OR      AX, 8000H
                RET
ads_slot_00_init ENDP

; ============================================================================
; 0x1292  --  ads_detect_wrapper
;
; Read BIOS data-area LPT base addresses at 0040:0008 (LPT1) and
; 0040:000A (LPT2), and try each with ads_detect_lpt. Returns ZF=1
; if either probe succeeded.
;
;   Type:        Internal helper
;   Category:    LPT-DAC detection
;   Callers:     ads_slot_00_init
;   Callees:     ads_detect_lpt
;
;   Inputs:      none (reads BIOS data area at segment 0x40)
;
;   Outputs:
;     ZF     --  set when a probe succeeded (mirrors the inner probe's
;                final OR AX, AX)
;     AX     --  0 on failure, 0xFFFF on success (from ads_detect_lpt)
;
;   Touches:     AX, DX, ES (not restored)
;
;   Side effects:
;     ads_lpt_data_port (77h) <- the base address that succeeded
;     (written inside ads_detect_lpt).
; ============================================================================
ads_detect_wrapper PROC NEAR
                MOV     AX, 40H
                MOV     ES, AX                      ; ES = BIOS data segment
                MOV     DX, ES:[8]                  ; DX = LPT1 base (or 0)
                CALL    ads_detect_lpt
                JE      SHORT dw_done
                MOV     DX, ES:[0AH]                ; DX = LPT2 base (or 0)
                CALL    ads_detect_lpt
dw_done:        RET
ads_detect_wrapper ENDP

; ============================================================================
; 0x12AA  --  ads_detect_lpt
;
; Probe a specific LPT base (in DX) to see if a Disney Sound Source
; dongle is attached. Sequence:
;
;   1. Write 0x7F (mid-scale sample) to LPT data port.
;   2. Write 0x0C to LPT control port (strobe + latch high).
;   3. Delay ~1000 cycles (DEC AX / JNE loop on AX=0x3E8).
;   4. Write 0x04 to LPT control port (drop latch -> clock sample).
;   5. Delay ~0xEA60 cycles.
;   6. Read LPT status port. If bit 6 (FIFO-ready) is set, the dongle
;      latched our sample -- success path goes to LAB_12EF and
;      returns AX = 0xFFFF (success).
;   7. Otherwise loop up to 0x64 times more, clocking 0x7F samples
;      and polling status; eventually return AX = 0 (failure).
;
; Reset to idle (ads_lpt_stop) before returning either way. ZF reflects
; (AX != 0), i.e. success: ZF = 0; failure: ZF = 1.
;
;   Type:        Internal helper
;   Category:    LPT-DAC detection / handshake
;   Callers:     ads_detect_wrapper
;   Callees:     ads_lpt_start, ads_lpt_stop
;
;   Inputs:
;     DX     --  LPT base port to probe (0 if BIOS doesn't have one)
;
;   Outputs:
;     AX     --  0xFFFF on success (FIFO acknowledged within 100 retries)
;                0 on failure
;     ZF     --  reflects OR AX, AX
;
;   Touches:     AX, CX, DX (not restored)
;
;   Side effects:
;     ads_lpt_data_port (77h) <- DX (saved before the handshake even
;     starts, so a partial probe still leaves the address cached).
;     LPT armed during probe, then idled via ads_lpt_stop.
;     Two long delay loops (~1000 and ~60000 iterations) to satisfy
;     the DSS's settle time.
; ============================================================================
ads_detect_lpt  PROC    NEAR
                MOV     CS:[77H], DX                ; remember LPT base
                CALL    ads_lpt_start
                MOV     AL, ads_dac_midscale        ; mid-scale sample
                OUT     DX, AL
                ADD     DX, 2                       ; -> control port
                MOV     AL, ads_dss_ctrl_latch
                OUT     DX, AL
                MOV     AX, 3E8H                    ; ~1000-cycle delay
dl_delay1:      DEC     AX
                JNE     SHORT dl_delay1
                MOV     AL, ads_dss_ctrl_clock
                OUT     DX, AL
                MOV     AX, 0EA60H                  ; ~60000-cycle delay
dl_delay2:      DEC     AX
                JNE     SHORT dl_delay2
                DEC     DX                          ; -> status port
                IN      AL, DX
                TEST    AL, ads_fifo_ready_mask     ; FIFO ready?
                JNE     SHORT dl_success
                DEC     DX                          ; -> data port
                MOV     CX, 64H
dl_retry:       MOV     AL, ads_dac_midscale
                OUT     DX, AL
                ADD     DX, 2
                MOV     AL, ads_dss_ctrl_latch
                OUT     DX, AL
                PUSH    AX                          ; settling delay (see the
                POP     AX                          ; Timing loop glossary entry)
                MOV     AL, ads_dss_ctrl_clock
                OUT     DX, AL
                PUSH    AX
                POP     AX
                PUSH    AX
                POP     AX
                DEC     DX                          ; -> status
                IN      AL, DX
                TEST    AL, ads_fifo_ready_mask
                JNE     SHORT dl_loop_ok
                DEC     DX
                LOOP    dl_retry
                ; Fall through to failure.
dl_success:     MOV     AX, 0FFFFH
                JMP     SHORT dl_finish
dl_loop_ok:     MOV     AX, 0
dl_finish:      CALL    ads_lpt_stop
                OR      AX, AX
                RET
ads_detect_lpt  ENDP

; ============================================================================
; 0x12FD  --  ads_trailing_magic
;
; The very last byte of the binary. Read by ads_slot_00_init to gate
; the optional InDOS-pointer probe: the probe only runs if this byte
; is 0xCD. In this build the byte is 0xDC, so the probe is skipped at
; runtime.
;
; This is a data byte read as data (a CMP byte-compare in
; ads_slot_00_init). The choice of 0xDC (rather than 0xCD) is what
; disables the probe; the byte itself is just a configuration flag.
; ============================================================================
                DB      0DCH

; ============================================================================
; Glossary of terms and acronyms used in this file (alphabetical)
;
;   Bank          One of the two halves of the playback ring buffer.
;                 The engine streams into the "inactive" half while
;                 the LPT pump drains samples out of the "active" half;
;                 ads_tick swaps them at the right moment.
;
;   BIOS          Basic Input/Output System -- the ROM firmware on the
;                 motherboard. The driver reads BIOS data-area memory
;                 at segment 0x40 (offsets 0x08 and 0x0A) to find the
;                 LPT base addresses, and it hooks INT 10h (the BIOS
;                 video service) to guard against re-entering its own
;                 buffer pump while a video call is in flight.
;
;   Covox         The original Covox Speech Thing (1987) was a passive
;                 8-bit DAC plugged into LPT. "Covox-style" describes
;                 any parallel-port DAC built the same way; the DSS is
;                 a Covox descendant with an added 16-byte FIFO.
;
;   DAC           Digital-to-Analog Converter. Hardware that turns a
;                 numeric sample value into a voltage. The DSS uses
;                 a 7-bit resistor-ladder DAC clocked at ~7000 Hz.
;
;   Decimation    Throwing samples away to lower the effective sample
;                 rate. ads_pick_decimation programs how many input
;                 samples per output sample we drop. The opposite
;                 (interpolation / "double-rate") is also supported
;                 via the ads_init_curve smoothing path.
;
;   DOS           Disk Operating System (MS-DOS / PC-DOS, the era's
;                 OS). Reached via INT 21h with a function number in
;                 AH (e.g. AH=3Dh = Open, 3Eh = Close, 3Fh = Read,
;                 42h = LSEEK, 25h = Set Interrupt Vector).
;
;   DSS           Disney Sound Source. The hardware this driver
;                 targets: a Covox-style 8-bit parallel-port DAC with
;                 a 16-byte internal FIFO and a fixed ~7000 Hz playback
;                 clock. Disney shipped it as a $15 dongle for their
;                 Sound Source line of children's games in 1992.
;
;   DUDE          Dynamix's universal sound-driver container format.
;                 Every Dynamix audio driver of this generation is a
;                 flat DUDE binary; the v2.8 variant used here has an
;                 8-char "auddisny" tag and a 16-slot dispatch table.
;
;   EOB           End of Buffer. ads_state_eob (44h) latches "the
;                 last ring half just emptied"; slot 4 reads + clears it
;                 so the game can poll "did playback finish".
;
;   FIFO          First-In, First-Out queue. The DSS has a tiny 16-byte
;                 hardware FIFO between the host's LPT writes and the
;                 DAC's clock-out. The host fills it; the dongle drains
;                 it at its own ~7000 Hz rate. The host must NOT write
;                 faster than the FIFO can absorb, so the play loop
;                 reads the LPT status port (base + 1) and only writes
;                 the next sample when bit 6 is set (= "FIFO has room").
;
;   InDOS         A DOS internal flag byte (one byte; address obtained
;                 from INT 21h AH=34h) that DOS sets while it is busy
;                 processing a system call. The driver reads it via
;                 ads_query_status to know "DOS is busy right now, do
;                 not call into DOS or run the engine".
;
;   IRQ           Interrupt Request. The CPU stops the running code,
;                 jumps to a handler in the interrupt vector table,
;                 then resumes when the handler IRETs. The ADS driver
;                 hooks two software interrupts (INT 10h, INT 33h)
;                 to set "busy" flags around BIOS calls; it does NOT
;                 hook a hardware-timer IRQ to pump samples (that
;                 work happens in ads_slot_01_play, which the game
;                 calls explicitly).
;
;   LPT           Line Printer port. The PC's parallel printer port.
;                 The DSS plugs into LPT1 (typical base 0x378) or
;                 LPT2 (0x278). The three I/O ports are:
;
;                   LPT base + 0  data    -- write the next PCM byte
;                   LPT base + 1  status  -- bit 6 = "FIFO has room"
;                   LPT base + 2  control -- bits 2/3 latch the FIFO
;
;                 The LPT-DAC writeup earlier in this file describes the
;                 0x0C / 0x04 control-port "rising edge" handshake
;                 that clocks a byte from the data port into the FIFO.
;
;   LPT-DAC       The category name for parallel-port-based DACs --
;                 i.e. Covox, DSS, Sound Master, Stereo-on-1, etc.
;                 They all share the "host bit-bangs samples to LPT"
;                 model.
;
;   LRU           Least Recently Used. Not used in this driver (the
;                 AdLib driver uses LRU for voice allocation; DSS
;                 doesn't have voices).
;
;   LSEEK         DOS function (AH=42h) to seek within an open file.
;                 Used by slots 3 and 9 to position the file pointer
;                 at the start of the chunk we're about to stream.
;
;   MIDI          Musical Instrument Digital Interface. The DSS driver
;                 does NOT speak MIDI; the AdLib (.ADL) driver does.
;                 The two drivers share the DUDE-2.x dispatch ABI but
;                 the per-slot semantics are completely different.
;
;   MZ            The "MZ" 2-byte signature at the start of a DOS .EXE
;                 file. Every code driver (video and sound alike) is linked
;                 as an .EXE; the packer strips the MZ header + relocation
;                 table to recover the flat ORG-0 image before compressing.
;
;   PCM           Pulse Code Modulation. The "raw" representation of
;                 audio as a stream of integer samples taken at a
;                 regular rate. ADS streams 7-bit unsigned PCM (one
;                 sample per byte; top bit ignored by the FIFO).
;
;   Ring buffer   A fixed-size buffer treated as a circle: writes
;                 wrap from the end back to the start. The ADS engine
;                 uses a two-half ring; one half is "playing" while
;                 the other is "being filled" from disk.
;
;   Sample rate   How many samples per second the DAC plays. The DSS
;                 is hardwired to ~7000 Hz; the .SOL files supply
;                 audio at higher rates (11025, 22050, etc.) and
;                 ads_pick_decimation maps the input rate down to the
;                 DSS's fixed playback rate.
;
;   SOA           Struct-Of-Arrays (storage layout where each "field"
;                 is its own array indexed by the same index). The
;                 AdLib driver uses SOA heavily; the DSS driver mostly
;                 doesn't.
;
;   .SOL          Dynamix's compressed/wrapped sample file format.
;                 Begins with a 0x8D marker byte and an "SOL\0" tag
;                 followed by rate, length, and format-flags fields
;                 (see ads_dos_file_open_sol). Files without the
;                 marker are treated as raw PCM.
;
;   Sound Source  Short for "Disney Sound Source" (the DSS). Disney
;                 picked the name to evoke the dongle being a "source"
;                 of speech and sound effects.
;
;   Timing loop   A busy-wait CPU loop used to introduce a precise
;                 delay where no hardware timer is available. The
;                 DSS detection sequence (ads_detect_lpt) uses two:
;                 a ~1000-iteration delay after the first latch
;                 toggle, and a ~60000-iteration delay before
;                 polling the status port for FIFO-ready. Each
;                 `DEC AX / JNE` iteration is about 5 CPU cycles on
;                 a 4.77-MHz 8088, so the long loop is ~63 ms --
;                 comfortably more than the DSS's worst-case settle
;                 time. The play loop uses a much shorter pattern
;                 (`NOP / NOP / NOP / PUSH AX / POP AX / ...`) to
;                 give the FIFO ~7 cycles between latch toggles.
;
;   TINY model    Borland's smallest memory model: code and data
;                 share one 64K segment (CS = DS = SS). The whole
;                 driver fits comfortably in 5 KB so this is the
;                 obvious choice and lets `CS:[offset]` reach every
;                 byte of the driver.
;
;   VROOMM        Borland's overlay-manager runtime, used elsewhere
;                 in KRONDOR.EXE but NOT relevant to the sound
;                 drivers (which are plain flat binaries loaded as a
;                 whole, not as overlays).
; ============================================================================

                END     _start
