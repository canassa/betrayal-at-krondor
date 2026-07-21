; ============================================================================
; Sx.SSM.APA.bin -- Dynamix DUDE-format Pro AudioSpectrum digital DAC driver
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
; Sound Blaster, Pro AudioSpectrum, Roland MT-32, etc.) and picks the right
; one at runtime based on the user's "sound setup" choice.
;
; This file is the Pro AudioSpectrum (PAS) digital-sample driver. Unlike
; the AdLib driver -- which feeds MIDI-style note events into an FM-synth
; chip -- this driver streams pre-recorded digital audio samples (the
; sound effects and speech) from disk to the PAS's DAC. The game just
; tells it "play this sample file" and the driver does the rest: open
; the file, decode its header, set up the playback timer at the chip's
; sample-rate divisor, prime a ring buffer, hook the IRQ, and let the
; interrupt-driven streaming engine refill the buffer until end-of-file.
;
; About half the file is the streaming engine (DOS file I/O, ring-buffer
; refill, format decoding); the other half is hardware setup: detecting
; the chip's interface version, picking the right I/O-port base for the
; user's hardware revision (PAS Plus / PAS 16 / Sound Blaster compat),
; programming the rate-divisor timer, and installing the IRQ handler.
;
; The driver also hooks INT 10h and INT 33h with thin stubs. Those
; interrupts may be invoked by the game *during* PAS IRQs, which would
; re-enter critical sections; the stubs set a "do not start a buffer
; pump while the BIOS/mouse driver is running" flag.
; ----------------------------------------------------------------------------

; ----------------------------------------------------------------------------
; About the Pro AudioSpectrum (MV101 ASIC)
;
; The Pro AudioSpectrum is Media Vision's family of sound cards: PAS,
; PAS Plus, PAS 16, and PAS Studio. All four are built around Media
; Vision's MV101 mixer/timer ASIC plus a separate FM-synth chip (an
; OPL2 or OPL3) and a DAC stage. This driver controls only the DAC and
; the MV101's sample-rate timer; the OPL FM-synth is the job of a
; sibling driver (Sx.SSM.PRO.bin / Sx.SSM.PS1.bin).
;
; The MV101 exposes itself through a *relocatable* I/O port block. The
; block's base is chosen by the user via a jumper / config file:
;   Default:  base 0x388 (registers at 0xB88..0xB8B)  -- "PAS native"
;   Alt 1:    base 0x788
;   Alt 2:    base 0x988
;   Alt 3:    base 0xF8B  -- shifted layout used by PAS 16/Studio
; The user-side selection arrives in BL when the driver is loaded (see
; apa_detect_mv101). The driver caches the chosen ports in the data
; section: sample-rate timer (cs:[6C], cs:[6E], cs:[6A]), DAC FIFO ports
; (cs:[64], cs:[68]), filter/mixer port (cs:[72]), and an IRQ status
; register (cs:[7A]).
;
; Programming model for sample playback:
;
;   1. Detect the chip and pick port bases  (apa_detect_mv101)
;   2. Load timer 2 (sample-rate timer) by writing a divisor to
;      port [6Ch..6Eh] in mode 3 via port [6Ah]               (apa_timer_program)
;   3. Mask the IRQ during setup; install IRQ vector at the user's
;      chosen IRQ line (e.g. IRQ 5 or 7)                       (apa_irq_install)
;   4. Program the filter/mixer at port [72h] for the requested
;      sample rate.
;   5. Prime the DAC FIFO and unmask the IRQ. Each IRQ pops a buffer
;      pump that streams more samples from disk.               (apa_irq_handler)
;
; Sample format: the driver supports 8-bit unsigned PCM with an optional
; "encoded" header. If the first byte of the sample file is 0x8D, the
; file uses Dynamix's compact ".SOL" packed sample format (a small
; header: marker + length + marker "SOL\0" + rate + flags + length),
; and the driver decodes the header before starting playback. Otherwise
; the file is raw PCM.
;
; The state byte at cs:[34] selects "stereo flip" (interleave swap),
; cs:[49] selects "smooth" filtering, cs:[4A] inverts samples (PAS's
; sign-flipping playback mode), cs:[4B] does sample doubling
; (interpolation), cs:[4C] enables byte-swap, and cs:[44] toggles ADPCM
; decompression. Flags arrive packed into AL on the slot-3 init call.
; ----------------------------------------------------------------------------

; ----------------------------------------------------------------------------
; About the DUDE dispatch ABI
;
; "DUDE" is Dynamix's internal sound-driver format. Every driver in the
; family is a flat binary that begins with a 0x34-byte header containing
; two magic numbers (0x87654321 and 0xFEDCBA98), an ASCII subsystem tag,
; a human-readable device-name string, and a driver kind.
;
; Note that the APA driver uses the version-2 header (interface 2.6)
; rather than the version-1 header that the AdLib driver uses. The
; v2 header replaces the 4-char "dude" tag with a 6-char "audpro" tag
; (signaling this is an audio-streaming driver) and adds an 8-byte
; trailing config block at the end of the header (apa_init_table).
;
; The game communicates with this driver through a far call into the
; dispatch trampoline at offset 0x08BC. Before the call:
;
;   AX    = slot index (0..15)                  -- which operation
;   SS:SI = pointer to slot arguments           -- per-slot argument block
;
; The dispatch trampoline (18 bytes, 0x08BC..0x08CD inclusive) is:
;
;   PUSH DS
;   MOV  BX, AX
;   SHL  BX, 1                                  ; index -> byte offset
;   MOV  AX, CS
;   MOV  DS, AX                                 ; DS := CS for the handler
;   CALL CS:[BX + apa_func_table]               ; near indirect
;   POP  DS
;   OR   AX, AX                                 ; set flags from result
;   RETF                                        ; far return
;
; The 16 slots:
;
;   Slot  0  apa_get_info                  -- one-time: detect chip, hook ints
;   Slot  1  apa_play_sound                -- begin playing a buffered sound
;   Slot  2  apa_shutdown                  -- restore vectors, mask IRQ
;   Slot  3  apa_init_playback             -- set up rate + ring buffer
;   Slot  4  apa_query_status              -- read playback state into AX
;   Slot  5  apa_slot5_stop                -- thin wrapper of apa_stop
;   Slot  6  apa_slot6                     -- set sample rate from arg
;   Slot  7  apa_slot_ret_a                -- single-byte RET stub
;   Slot  8  apa_clear_busy                -- clear busy flag
;   Slot  9  apa_slot9_load_chunk          -- load sample chunk from file
;   Slot 10  apa_slot10_resume             -- resume after pause
;   Slot 11  apa_slot11_irq_setup          -- reset IRQ + key state
;   Slot 12  apa_stop                      -- stop playback, mask IRQ
;   Slot 13  apa_query_pos                 -- read current playback position
;   Slot 14  apa_slot14_zero               -- xor ax,ax; ret  (no-op)
;   Slot 15  apa_slot_ret_b                -- single-byte RET stub
;
; Slots 7 and 15 are no-op RETs. Slots 14 returns AX=0. These are
; reserved-but-unused entries in the cross-driver ABI.
; ----------------------------------------------------------------------------

; ----------------------------------------------------------------------------
; How to read this source
;
; - Lines like `MOV BX, AX` are CPU instructions. The first operand is
;   the destination, the second is the source -- read it as "BX = AX".
;   This is "Intel" order; AT&T-style "MOV AX, BX" with destination
;   second is a different convention and is not used here.
;
; - Lines like `apa_state DB 100 DUP(0)` declare data: the label names
;   this address, `DB` says "the following are bytes", and `100 DUP(0)`
;   means "100 copies of zero". `DW` is the 16-bit equivalent (two
;   bytes per entry, little-endian on x86).
;
; - `CS:[offset]` is a memory access using the Code Segment register as
;   the base. The dispatch trampoline sets DS := CS up front, so DS and
;   CS reference the same data; the CS: prefix is one byte per
;   instruction.
;
; - Functions are wrapped in `name PROC NEAR ... name ENDP`. Inside,
;   labels use a 2-3 letter nickname prefix derived from the function
;   name (e.g. `pl_done` inside apa_play_sound, `bp_check_ok` inside
;   apa_buffer_pump). The prefix avoids label collisions across
;   functions and acts as a breadcrumb identifying which function a
;   label belongs to.
;
; - Numbers ending in `H` are hexadecimal (3FH = 63). Plain numbers are
;   decimal. Hex numbers beginning with a letter need a leading `0`
;   (0AH, 0FFH) -- TASM uses the first character to distinguish
;   identifiers from numbers, so `AH` would parse as a register name.
;
; - Registers used in this driver:
;     AX, BX, CX, DX     -- general 16-bit registers, each splittable
;                           into a high and low 8-bit half (AH/AL,
;                           BH/BL, CH/CL, DH/DL).
;     SI, DI             -- 16-bit "index" registers, often used as
;                           pointers into arrays or DOS I/O buffers.
;     BP                 -- 16-bit base pointer; rarely used directly
;                           here -- v2.6 DUDE puts the slot index in
;                           AX, not BP (the v1.x ABI ADL uses).
;     CS, DS, ES, SS     -- 16-bit segment registers. In TINY model
;                           CS=DS=SS. The dispatch trampoline saves DS
;                           on entry and forces DS := CS so handlers
;                           can address the data section without an
;                           explicit CS: override. ES is set up
;                           separately for DOS file I/O reads.
;
; - Calling convention used in this driver:
;     * Slot handlers are reached via the dispatch trampoline with
;       AX = slot index and SS:SI = pointer to slot arguments. The
;       handler returns through `OR AX,AX / RETF`, which sets the
;       zero-flag from the result so the FAR caller can branch on it.
;     * Six helpers (apa_timer_arm, apa_timer_stop_short,
;       apa_irq_install, apa_irq_uninstall, apa_unmask_irq_emit,
;       apa_dx_ax_divrev) end in `RETF` rather than `RET`. They are
;       invoked via `PUSH CS / CALL <func>` -- the PUSH places a
;       fake "return segment" on the stack so the helper's RETF pops
;       both the segment and the offset, behaving like a regular
;       near-CALL from the caller's perspective. This is a one-byte
;       code-density trick.
;     * Internal near-call helpers (the majority) pass arguments in
;       registers; the convention varies per helper and is documented
;       at each helper's header.
;
; - IRQ-handler entry points use IRET (not RET). Trampoline calls into
;   the chained INT 10h / INT 33h vectors use FAR pushf+call+IRET.
; ----------------------------------------------------------------------------

                .8086
                .MODEL  TINY
                .CODE
                ORG     0

; ----------------------------------------------------------------------------
; Port and state-offset constants
;
; Plain-numeric EQUs that name the recurring magic literals in the file.
; The EQU is a textual substitution at assemble time, not a typed alias.
;
; PAS hardware ports (all I/O ports, read/written via IN/OUT DX):
;   apa_pcm_port         PAS DAC data port (8-bit unsigned PCM). The
;                        IRQ "ack" sequence writes 0xE1 here to permit
;                        the next sample-rate IRQ, and 0x21 to silence.
;   apa_pcm_mode_port    Chip-revision read port; also the PCM mode-8
;                        write target during init / shutdown.
;   apa_pcm_status_port  PAS IRQ-status read register (bit 3 = our IRQ).
;   apa_pic_unmask_port  Per-chip-rev IRQ enable mask register; writes
;                        0xF9 here to permit IRQ delivery to the PIC.
;   apa_master_timer_ctrl    PAS master-timer control-word port. Used
;                            by apa_timer_arm and apa_set_rate to select
;                            counter mode (0x74 / 0x36).
;   apa_master_timer_div_lo  PAS master-timer divisor write port (low
;                            byte first, then high byte after a chip
;                            pause). Used by apa_set_rate.
;   apa_master_timer_div_hi  PAS master-timer alt divisor write port
;                            used by apa_timer_arm.
;
; State-byte offsets (CS-relative; into the apa_state block at 0x0032):
;   apa_state_in_pump_off  Offset of the apa_in_pump re-entry guard byte
;                          (set on entry to apa_buffer_pump, cleared on
;                          exit). Used as a CS-relative absolute address
;                          rather than as an [SI + off] index.
; ----------------------------------------------------------------------------
apa_pcm_port            EQU 0B8AH
apa_pcm_mode_port       EQU 0B8BH
apa_pcm_status_port     EQU 0B89H
apa_pic_unmask_port     EQU 0F8AH
apa_master_timer_ctrl   EQU 138BH
apa_master_timer_div_lo EQU 1388H
apa_master_timer_div_hi EQU 1389H
apa_state_in_pump_off   EQU 3EH

; ============================================================================
; 0x0000  --  DUDE v2 header  (interface 2.6, tag "audpro")
; ============================================================================
_start          LABEL   BYTE
                JMP     apa_dispatch                ; E9 B9 08

                DB      0                           ; pad_03

dude_magic_a    DD      87654321H
dude_iface_ver  DB      2, 6
dude_tag        DB      'audpro'

device_name_len DB      17
device_name     DB      'Pro AudioSpectrum'

dude_magic_b    DD      0FEDCBA98H
dude_driver_kind DD     2000H

; ----------------------------------------------------------------------------
; 0x002A  --  apa_init_table  (8 bytes; meaning TBD -- looks like a small
;             threshold/index table the engine references at runtime)
; ----------------------------------------------------------------------------
apa_init_table  DB      00H, 01H, 02H, 03H, 06H, 0AH, 0FH, 15H

; ============================================================================
; 0x0032  --  data section / state (zero-initialized; engine populates at
;             runtime)
;
; This region is one big block of mostly-zero state. The engine reaches
; into specific offsets via `CS:[<const>]` instructions throughout the
; code. We declare the whole region as a single zero-filled block so the
; binary layout matches.
;
; Notable offsets (deduced from access patterns; subject to revision):
;
;   0x32  apa_pause1_dl          1B    short/long pause control
;   0x33  apa_pause2_dl          1B
;   0x34  apa_stereo_swap        1B    1=swap stereo channels
;   0x35  apa_adpcm_seed         1B    ADPCM step accumulator
;   0x36  apa_irq_mask           1B    OR-mask for IRQ controller
;   0x37  apa_filter_byte        1B    filter/mixer register value
;   0x38  apa_irq_line           1B    selected IRQ line (1..3)
;   0x39  apa_dma_byte           1B    DMA / SoundBlaster compat byte
;   0x3A  apa_state_active       1B    1=playback running
;   0x3B  apa_buffer_half        1B    which half of ring buffer is hot
;   0x3C  apa_in_mouseint        1B    1=inside INT 33h chain
;   0x3D  apa_in_swap            1B    re-entry guard for apa_buffer_swap
;                                       (set on entry; only that function
;                                       touches it)
;   0x3E  apa_in_pump            1B    re-entry guard for apa_buffer_pump
;                                       (set on entry; only that function
;                                       touches it). EQU as
;                                       apa_state_in_pump_off above.
;   0x3F  apa_in_bios            1B    1=inside INT 10h chain
;   0x40  apa_use_eob_kick       1B    1=kick on EOF, 0=stop on EOF
;   0x41  apa_chip_rev           1B    MV101 revision (from INT 2F probe)
;   0x42  apa_query_aux          1B
;   0x43  apa_active_bank        1B    0/1 = which DAC bank to write
;   0x44  apa_adpcm_enable       1B    1=ADPCM decode
;   0x45  apa_busy_flag          1B
;   0x46  apa_buffer_dirty       1B    1=buffer needs reload before play
;   0x47  apa_active_half        1B    which ring half the IRQ is consuming
;   0x48  apa_paused             1B
;   0x49  apa_smooth             1B    1=smooth (no zero-stuffing)
;   0x4A  apa_signed             1B    1=invert MSB (signed playback)
;   0x4B  apa_dbl_rate           1B    1=double-rate (interpolation)
;   0x4C  apa_byte_swap          1B    1=swap byte order
;   0x4D  apa_playing            1B    1=engine is in active playback
;   0x4E  apa_chunk_lo           2B    first half: chunk length
;   0x50  apa_buffer_size        2B    sample count per buffer half
;   0x52  apa_chunk_hi           2B    second half: chunk length
;   0x54  apa_buffer_size2       2B    second-half size
;   0x56  apa_bank_seg_lo        2B    buffer segment (low)
;   0x58  apa_bank_seg_hi        2B    buffer segment (high)
;   0x5A  apa_total_chunk_len    2B    full chunk length
;   0x5C  apa_bytes_streamed     4B    32-bit running counter (low/hi)
;   0x5E    ...continues
;   0x60  apa_chunk_consumed     2B    bytes the pump consumed so far
;   0x62  apa_chunk_remainder    2B    spillover when chunk > 0x800
;   0x64  apa_dac_data_port      2B    DAC FIFO data port (chip-rev dependent)
;   0x66  apa_dac_count          2B    expected IRQ count for this chunk
;   0x68  apa_dac_count_port     2B    DAC counter readback port
;   0x6A  apa_timer_ctrl_port    2B    timer-control port
;   0x6C  apa_timer_data_port    2B    timer-data port
;   0x6E  apa_timer_mode_port    2B    timer-mode port
;   0x70  apa_timer_div          2B    timer divisor (rate-dependent)
;   0x72  apa_filter_port        2B    filter/mixer port
;   0x74  apa_file_handle        2B    DOS file handle (FFFFh = none)
;   0x76  apa_seek_pos_lo        2B    file seek pos (low)
;   0x78  apa_seek_pos_hi        2B    file seek pos (high)
;   0x7A  apa_irq_mask_port      2B    PIC mask register (21h or A1h)
;   0x7C  apa_sample_rate        2B    desired playback rate (Hz)
;   0x7E  apa_chunk_total_hi     2B    initial chunk length (high)
;   0x80  apa_chunk_total_lo     2B    initial chunk length (low)
;   0x82  apa_rate_div           2B    cached rate divisor
;   0x84  apa_remaining_lo       2B    bytes remaining in current chunk (lo)
;   0x86  apa_remaining_hi       2B    bytes remaining in current chunk (hi)
;   0x88  apa_irq_save_buf       4B    saved original IRQ vector
;   0x8C  apa_int1c_seg          4B    saved INT 1Ch vector
;   0x90  apa_int_save_4         4B    saved misc vector (INT 34h)
;   0x94  apa_int33_orig         4B    saved INT 33h vector
;   0x98  apa_int10_orig         4B    saved INT 10h vector
;   0x9C  apa_dma_buffer       2048B   double-buffer for DMA pump (0x9C..0x89B)
; ============================================================================
apa_state       DB      866 DUP(00H)   ; 0x0032..0x0393 (866 bytes)

; (the data block above is sized so the next label lands at 0x089C, the
; function-pointer table)
                DB      1288 DUP(00H)  ; 0x0394..0x089B (1288 bytes) DMA buffer tail

; ============================================================================
; 0x089C  --  apa_func_table  (16 entries; 32 bytes)
;
; The 16 slot handlers. The dispatch trampoline indexes this table with
; the slot number (AX*2) and does a near indirect CALL.
; ============================================================================
apa_func_table  LABEL   WORD
                DW      apa_get_info                ; slot  0  -- 0x126F
                DW      apa_play_sound              ; slot  1  -- 0x08CE
                DW      apa_shutdown                ; slot  2  -- 0x09FC
                DW      apa_init_playback           ; slot  3  -- 0x093A
                DW      apa_query_status            ; slot  4  -- 0x09D3
                DW      apa_slot5_stop              ; slot  5  -- 0x09F8
                DW      apa_slot6                   ; slot  6  -- 0x08F0
                DW      apa_slot_ret_a              ; slot  7  -- 0x08FD
                DW      apa_clear_busy              ; slot  8  -- 0x0907
                DW      apa_slot9_load_chunk        ; slot  9  -- 0x0C55
                DW      apa_slot10_resume           ; slot 10  -- 0x0E73
                DW      apa_slot11_irq_setup        ; slot 11  -- 0x0E8E
                DW      apa_stop                    ; slot 12  -- 0x0910
                DW      apa_query_pos               ; slot 13  -- 0x1194
                DW      apa_slot14_zero             ; slot 14  -- 0x0C52
                DW      apa_slot_ret_b              ; slot 15  -- 0x08EF

; ============================================================================
; 0x08BC  --  apa_dispatch  --  the trampoline
;
; Called by the game as `CALL FAR apa_seg:apa_dispatch`. The trampoline
; saves DS, sets DS := CS so the handler can use the data section
; through DS without a CS: override, does a near indirect CALL through
; apa_func_table, restores DS, sets flags from AX, and far-returns to
; the caller.
;
;   Type:        Dispatch trampoline
;   Category:    DUDE v2.6 ABI
;   Callers:     Game engine, via FAR call to apa_seg:0x08BC
;   Callees:     Any of apa_func_table[0..15]
;
;   Inputs:
;     AX     --  slot index (0..15); which operation to invoke
;     SS:SI  --  pointer to slot-specific argument block (used by
;                slot handlers that need >2 register-args worth of
;                data; otherwise unread)
;
;   Outputs:
;     AX     --  slot handler's return value; flags reflect AX (Z if 0).
;
;   Touches:     BX, DS clobbered/restored. AX preserved (the OR is a
;                no-op modifier of flags only).
;
;   Notes:
;     The 18-byte trampoline body 0x08BC..0x08CD is the version-2.6
;     DUDE entry. v1.x DUDE drivers (e.g. ADL) use a different ABI
;     with BP-indexed dispatch and no DS save -- do not confuse the
;     two when reading sibling drivers.
; ============================================================================
apa_dispatch    PROC    NEAR
                PUSH    DS
                MOV     BX, AX
                SHL     BX, 1
                MOV     AX, CS
                MOV     DS, AX
                CALL    WORD PTR CS:[BX + apa_func_table]
                POP     DS
                OR      AX, AX
                RETF
apa_dispatch    ENDP

; ============================================================================
; 0x08CE  --  apa_play_sound  (slot 1)
;
; Begin (or resume) sample playback. The body of slot 1 is just a quick
; check: if the engine is already playing AND the previous chunk has
; finished, kick off the next buffer swap; otherwise just pump the next
; buffer half. Returns AX = 0.
;
;   Type:        Slot handler
;   Category:    Streaming engine entry point
;   Dispatch:    Slot 1 (AX=1; no slot-args read)
;   Callers:     Game (via apa_dispatch)
;   Callees:     apa_buffer_swap, apa_buffer_pump
;
;   Inputs:      (none beyond global engine state)
;   Outputs:     AX = 0
;
;   Side effects:
;     - May call apa_buffer_swap (which can toggle cs:[47h] and call
;       apa_timer_program).
;     - Always calls apa_buffer_pump on the active half.
; ============================================================================
apa_play_sound  PROC    NEAR
                CMP     BYTE PTR CS:[4DH], 1
                JE      SHORT pl_done
                CMP     BYTE PTR CS:[3AH], 1
                JNE     SHORT pl_done
                CMP     BYTE PTR CS:[45H], 0
                JNE     SHORT pl_pump
                CALL    apa_buffer_swap
pl_pump:        CALL    apa_buffer_pump
pl_done:        XOR     AX, AX
                RET
apa_play_sound  ENDP

; ============================================================================
; 0x08EF  --  apa_slot_ret_b  (slot 15)
;
; Reserved no-op slot -- a single-byte RET stub.
;
;   Type:        Slot handler (stub)
;   Category:    Reserved / no-op
;   Dispatch:    Slot 15 (AX=15)
;   Inputs:      (none)
;   Outputs:     undefined (AX is unchanged; flags from caller)
;   Notes:       Shared one-byte RET with several other reserved slots
;                in the cross-driver DUDE v2.6 ABI.
; ============================================================================
apa_slot_ret_b  PROC    NEAR
                RET
apa_slot_ret_b  ENDP

; ============================================================================
; 0x08F0  --  apa_slot6  (slot 6)  --  set sample rate from arg
;
; Reads the desired sample rate from SS:[SI], caches it in
; apa_sample_rate (cs:[7C]), and reprograms the timer.
;
;   Type:        Slot handler
;   Category:    Timer / rate
;   Dispatch:    Slot 6 (AX=6; SS:[SI] = sample rate in Hz)
;   Callers:     Game (via apa_dispatch)
;   Callees:     apa_set_rate
;
;   Inputs:
;     SS:[SI]  --  desired sample rate (16-bit unsigned, Hz)
;
;   Outputs:     AX = 0
;
;   Side effects:
;     - cs:[7Ch] (apa_sample_rate) <- new rate
;     - Issues the PAS rate-divisor sequence to ports 138BH / 1388H.
; ============================================================================
apa_slot6       PROC    NEAR
                MOV     AX, SS:[SI]
                MOV     CS:[7CH], AX
                CALL    apa_set_rate
                XOR     AX, AX
                RET
apa_slot6       ENDP

; ============================================================================
; 0x08FD  --  apa_slot_ret_a  (slot 7)
;
; Reserved no-op slot -- a single-byte RET stub.
;
;   Type:        Slot handler (stub)
;   Category:    Reserved / no-op
;   Dispatch:    Slot 7 (AX=7)
;   Inputs:      (none)
;   Outputs:     undefined
;   Notes:       See apa_slot_ret_b. Two distinct labels share the
;                same one-byte body; the bytes are duplicated rather
;                than pointing two table entries at one address.
; ============================================================================
apa_slot_ret_a  PROC    NEAR
                RET
apa_slot_ret_a  ENDP

; ============================================================================
; 0x08FE  --  apa_set_busy
;
; Sets the busy flag at cs:[45h] to 1 and returns. Nothing calls it --
; the function-table slot 8 resolves to 0x0907, the "clear busy"
; function.
;
;   Type:        Helper (unreferenced)
;   Category:    Engine state
;   Callers:     None
;   Inputs:      (none)
;   Side effects: cs:[45h] <- 1
;
;   Notes:
;     Likely an editor leftover from an earlier driver version that
;     had a two-state "busy" slot.
; ============================================================================
apa_set_busy    PROC    NEAR
                MOV     BYTE PTR CS:[45H], 1
                XOR     AX, AX
                RET
apa_set_busy    ENDP

; ============================================================================
; 0x0907  --  apa_clear_busy  (slot 8)
;
; Mirror of apa_set_busy: clear the busy flag at cs:[45h].
;
;   Type:        Slot handler
;   Category:    Engine state
;   Dispatch:    Slot 8 (AX=8; no slot-args read)
;   Callers:     Game (via apa_dispatch)
;
;   Inputs:      (none)
;   Outputs:     AX = 0
;   Side effects: cs:[45h] (apa_busy_flag) <- 0
; ============================================================================
apa_clear_busy  PROC    NEAR
                MOV     BYTE PTR CS:[45H], 0
                XOR     AX, AX
                RET
apa_clear_busy  ENDP

; ============================================================================
; 0x0910  --  apa_stop  (slot 12)
;
; Stop playback: silence the DAC, mask the IRQ, reset state. Idempotent
; (returns immediately if already stopped). Returns AX=0.
;
;   Type:        Slot handler
;   Category:    Engine teardown
;   Dispatch:    Slot 12 (AX=12; no slot-args read)
;   Callers:     Game (via apa_dispatch), apa_buffer_swap (engine-driven
;                EOF), apa_slot5_stop (slot-5 wrapper),
;                apa_init_playback (re-init), apa_slot9_load_chunk
;                (re-init), apa_shutdown.
;   Callees:     apa_unmask_irq_emit, apa_timer_stop_short,
;                apa_irq_uninstall.
;
;   Inputs:      (none beyond global state)
;   Outputs:     AX = 0
;
;   Side effects:
;     - Sets cs:[4Dh] (apa_playing) = 1, the "stopped" sentinel.
;     - Writes 0x21 to apa_pcm_port (PAS "stop sample" command).
;     - Writes mode byte to timer ctrl port (stops the rate timer).
;     - Writes 0 to apa_pcm_mode_port (DAC reset).
;     - Calls apa_irq_uninstall to restore the vector and remask
;       the IRQ at the PIC.
; ============================================================================
apa_stop        PROC    NEAR
                CMP     BYTE PTR CS:[4DH], 1
                JE      SHORT st_done
                MOV     BYTE PTR CS:[4DH], 1
                PUSH    CS
                CALL    apa_unmask_irq_emit
                PUSH    CS
                CALL    apa_timer_stop_short
                MOV     DX, apa_pcm_mode_port
                XOR     AL, AL
                OUT     DX, AL
                MOV     AL, CS:[41H]
                MOV     BX, 88H
                PUSH    CS
                CALL    apa_irq_uninstall
st_done:        XOR     AX, AX
                RET
apa_stop        ENDP

; ============================================================================
; 0x093A  --  apa_init_playback  (slot 3)
;
; The biggest initialization slot: set up the engine for a new sample.
; Reads format flags, sample rate, buffer parameters from SS:[SI+0..],
; programs the timer, computes the chunk size in halves, and arms the
; IRQ.
;
;   Type:        Slot handler
;   Category:    Engine setup
;   Dispatch:    Slot 3 (AX=3; SS:SI -> 10-byte argument block)
;   Callers:     Game (via apa_dispatch)
;   Callees:     apa_stop, apa_set_rate, apa_dx_ax_divrev,
;                apa_irq_install, apa_timer_program.
;
;   Inputs:
;     SS:[SI+0]   --  bank-select word (high byte selects active bank)
;     SS:[SI+2]   --  sample rate (Hz)
;     SS:[SI+4]   --  total sample count low word (passed as AX to
;                     apa_dx_ax_divrev)
;     SS:[SI+6]   --  total sample count high word (passed as DX)
;     SS:[SI+8]   --  half-buffer size in samples
;
;   Outputs:     (no explicit return value)
;
;   Side effects:
;     - cs:[43h] (apa_active_bank) selected.
;     - cs:[32h], cs:[33h] (pause budgets) seeded.
;     - cs:[50h], cs:[4Eh], cs:[52h], cs:[54h] (per-half chunk
;       sizes) populated.
;     - IRQ vector installed at cs:[41h].
;     - cs:[47h] (apa_active_half) <- 0.
;     - cs:[3Ah] (apa_state_active) <- 0 (not yet running).
;     - cs:[4Dh] (apa_playing) <- 0.
;     - cs:[42h] (apa_query_aux) <- 0.
;     - Calls apa_timer_program to arm the rate timer.
; ============================================================================
apa_init_playback PROC  NEAR
                PUSH    SI
                CALL    apa_stop
                POP     SI
                MOV     DX, apa_pcm_mode_port
                MOV     AL, 8
                OUT     DX, AL
                MOV     AX, SS:[SI]
                OR      AH, AH
                JNE     SHORT in_bank1
                MOV     BYTE PTR CS:[43H], 0
                JMP     SHORT in_after_bank
in_bank1:       MOV     BYTE PTR CS:[43H], 1
in_after_bank:  MOV     AX, SS:[SI + 2]
                CALL    apa_set_rate
                MOV     AX, SS:[SI + 4]
                MOV     DX, SS:[SI + 6]
                PUSH    CS
                CALL    apa_dx_ax_divrev
                MOV     CS:[32H], DL
                MOV     CS:[50H], AX
                MOV     AX, SS:[SI + 8]
                MOV     CS:[5AH], AX
                MOV     CS:[4EH], AX
                ADD     AX, CS:[50H]
                JAE     SHORT in_no_carry
                MOV     CS:[52H], AX
                SUB     CS:[4EH], AX
                MOV     WORD PTR CS:[54H], 0
                INC     DL
                MOV     CS:[33H], DL
                JMP     SHORT in_arm_irq
in_no_carry:    MOV     WORD PTR CS:[52H], 0
in_arm_irq:     MOV     AL, CS:[41H]
                MOV     DX, OFFSET apa_irq_handler
                MOV     BX, 88H
                PUSH    CS
                CALL    apa_irq_install
                MOV     BYTE PTR CS:[47H], 0
                MOV     BYTE PTR CS:[3AH], 0
                CALL    apa_timer_program
                MOV     BYTE PTR CS:[4DH], 0
                MOV     BYTE PTR CS:[42H], 0
                RET
apa_init_playback ENDP

; ============================================================================
; 0x09D3  --  apa_query_status  (slot 4)
;
; Reads two state bytes (active bank + query aux) into AX and clears
; the aux byte.
;
;   Type:        Slot handler
;   Category:    Engine state query
;   Dispatch:    Slot 4 (AX=4; SS:[SI] = bank-select word)
;   Callers:     Game (via apa_dispatch)
;
;   Inputs:
;     SS:[SI]  --  bank-select (high byte 0=bank0, non-0=bank1)
;
;   Outputs:
;     AL  --  cs:[4Dh] (apa_playing) snapshot
;     AH  --  cs:[42h] (apa_query_aux) snapshot
;
;   Side effects:
;     - cs:[43h] updated to selected bank.
;     - cs:[42h] cleared after read (read-and-clear protocol so the
;       game can detect IRQ-side state transitions without missing
;       any).
; ============================================================================
apa_query_status PROC   NEAR
                MOV     AX, SS:[SI]
                OR      AH, AH
                JNE     SHORT qs_bank1
                MOV     BYTE PTR CS:[43H], 0
                JMP     SHORT qs_load
qs_bank1:       MOV     BYTE PTR CS:[43H], 1
qs_load:        MOV     AL, CS:[4DH]
                MOV     AH, CS:[42H]
                MOV     BYTE PTR CS:[42H], 0
                RET
apa_query_status ENDP

; ============================================================================
; 0x09F8  --  apa_slot5_stop  (slot 5)
;
; Thin wrapper: just call apa_stop, drop AX, RET.
;
;   Type:        Slot handler
;   Category:    Engine teardown (wrapper)
;   Dispatch:    Slot 5 (AX=5; no slot-args read)
;   Callers:     Game (via apa_dispatch), apa_irq_handler (engine self-
;                stop on end-of-sample).
;   Callees:     apa_stop
; ============================================================================
apa_slot5_stop  PROC    NEAR
                CALL    apa_stop
                RET
apa_slot5_stop  ENDP

; ============================================================================
; 0x09FC  --  apa_shutdown  (slot 2)
;
; Final shutdown: stop playback, restore INT 10h + INT 33h vectors, close
; the file handle. Called when the game exits.
;
;   Type:        Slot handler
;   Category:    Driver teardown
;   Dispatch:    Slot 2 (AX=2; no slot-args read)
;   Callers:     Game-exit cleanup (via apa_dispatch)
;   Callees:     apa_stop, INT 21h (AH=25h set-vector, AH=3Eh close)
;
;   Inputs:      (none beyond global state)
;   Outputs:     AX = 0
;
;   Side effects:
;     - Restores the original INT 10h vector from cs:[98h].
;     - Restores the original INT 33h vector from cs:[94h].
;     - Closes the .SOL file handle at cs:[74h] (if open) and sets
;       cs:[74h] = 0xFFFF (the "no file" sentinel).
; ============================================================================
apa_shutdown    PROC    NEAR
                CALL    apa_stop
                PUSH    DS
                LDS     DX, CS:[98H]
                MOV     AH, 25H
                MOV     AL, 10H
                INT     21H
                POP     DS
                PUSH    DS
                LDS     DX, CS:[94H]
                MOV     AH, 25H
                MOV     AL, 33H
                INT     21H
                POP     DS
                CMP     WORD PTR CS:[74H], 0FFFFH
                JE      SHORT sd_done
                MOV     BX, CS:[74H]
                MOV     AH, 3EH
                INT     21H
                MOV     WORD PTR CS:[74H], 0FFFFH
sd_done:        XOR     AX, AX
                RET
apa_shutdown    ENDP

; ============================================================================
; 0x0A34  --  apa_timer_program
;
; Decide which half of the ring buffer the IRQ should fire next on, then
; program the MV101 sample-rate timer to count down to it. Also tracks
; the "expected IRQ count" so the engine can detect drift.
;
;   Type:        Helper
;   Category:    Timer / rate
;   Callers:     apa_init_playback, apa_irq_handler, apa_buffer_swap.
;   Callees:     apa_timer_arm (via PUSH CS / CALL).
;
;   Inputs:      (reads cs:[47h] = which half is active)
;   Outputs:     (none)
;
;   Side effects:
;     - cs:[66h] (apa_dac_count)  <- chosen half's expected IRQ count
;     - cs:[37h] (apa_filter_byte) <- chosen half's filter mode
;     - cs:[70h] (apa_timer_div)   <- chosen half's rate divisor
;     - Calls apa_timer_arm to push the values to the chip.
; ============================================================================
apa_timer_program PROC  NEAR
                CMP     BYTE PTR CS:[47H], 0
                JNE     SHORT tp_half2
                MOV     DL, CS:[32H]
                MOV     AX, CS:[50H]
                MOV     CX, CS:[4EH]
                JMP     SHORT tp_load
tp_half2:       MOV     DL, CS:[33H]
                MOV     AX, CS:[54H]
                MOV     CX, CS:[52H]
tp_load:        MOV     CS:[66H], CX
                MOV     CS:[37H], DL
                MOV     CS:[70H], AX
                PUSH    CS
                CALL    apa_timer_arm
                RET
apa_timer_program ENDP

; ============================================================================
; 0x0A6D  --  apa_timer_arm
;
; Push the chosen rate/divisor into the chip registers: mode byte to the
; timer-control port, then divisor low/high, then trigger byte, etc.
; The pattern is "OUT to chip-rev-specific port, then OUT data". Ends in
; RETF (called via PUSH CS / CALL).
;
;   Type:        Helper (RETF-style)
;   Category:    DAC / chip I/O
;   Calling convention: invoked as `PUSH CS / CALL apa_timer_arm`;
;                ends in RETF.
;   Callers:     apa_timer_program.
;   Callees:     none (pure I/O).
;
;   Inputs:      cs:[36h] (timer mode byte), cs:[6Ch], cs:[6Ah],
;                cs:[39h], cs:[6Eh], cs:[70h], cs:[64h], cs:[66h],
;                cs:[68h], cs:[37h], cs:[72h], cs:[38h] (all pre-
;                populated by the timer-setup chain).
;
;   Outputs:     (none)
;
;   Side effects:
;     - Writes 12+ bytes to the MV101 timer / DAC / filter / IRQ
;       ports in the exact order required by the chip's programming
;       sequence.
;     - Writes 0x74 to apa_pcm_mode_port (PCM start mode).
;     - Writes the rate divisor to port 1389h.
;     - Writes 0xE1 to apa_pcm_port (unmask / kick).
;     - Writes 0xF9 to apa_pic_unmask_port (PIC unmask for the IRQ
;       line).
;
;   Notes:
;     The `JMP SHORT ta_pause` (EB 00) at 0x0AB7 is a deliberate
;     2-byte chip-pause: between the rate-divisor low/high writes
;     the chip needs a few CPU cycles to latch the low byte before
;     the high byte arrives. The smallest "do nothing" the era's
;     style guide allowed was `JMP SHORT next-instruction`, which
;     burns ~5 CPU cycles on an 8086.
; ============================================================================
apa_timer_arm   PROC    NEAR
                MOV     AL, CS:[36H]
                MOV     DX, CS:[6CH]
                OUT     DX, AL
                MOV     DX, CS:[6AH]
                OUT     DX, AL
                MOV     AL, CS:[39H]
                MOV     DX, CS:[6EH]
                OUT     DX, AL
                MOV     AX, CS:[70H]
                MOV     DX, CS:[64H]
                OUT     DX, AL
                MOV     AL, AH
                OUT     DX, AL
                MOV     AX, CS:[66H]
                DEC     AX
                MOV     DX, CS:[68H]
                OUT     DX, AL
                MOV     AL, AH
                OUT     DX, AL
                MOV     AL, CS:[37H]
                MOV     DX, CS:[72H]
                OUT     DX, AL
                MOV     AL, CS:[38H]
                MOV     DX, CS:[6CH]
                OUT     DX, AL
                MOV     DX, apa_master_timer_ctrl
                MOV     AL, 74H
                OUT     DX, AL
                MOV     AX, CS:[66H]
                DEC     AX
                JNE     SHORT ta_have_div
                MOV     AX, 2
ta_have_div:    MOV     DX, apa_master_timer_div_hi
                OUT     DX, AL
                JMP     SHORT ta_pause          ; EB 00 -- 2-byte pause for chip timing
ta_pause:       MOV     AL, AH
                OUT     DX, AL
                MOV     DX, 0F88H
                MOV     AL, 80H
                OUT     DX, AL
                MOV     DX, apa_pcm_port
                MOV     AL, 0E1H
                OUT     DX, AL
                MOV     DX, apa_pic_unmask_port
                MOV     AL, 0F9H
                OUT     DX, AL
                RETF
apa_timer_arm   ENDP

; ============================================================================
; 0x0AE2  --  apa_timer_stop_short
;
; Quick disable: write the timer-control port's "stop" byte. Ends in
; RETF (called via PUSH CS / CALL).
;
;   Type:        Helper (RETF-style)
;   Category:    DAC / chip I/O
;   Calling convention: `PUSH CS / CALL apa_timer_stop_short`; RETF.
;   Callers:     apa_stop, apa_irq_handler.
;
;   Inputs:      cs:[36h] (timer mode byte)
;   Outputs:     (none)
;
;   Side effects: writes the mode byte to the rate timer's control
;                port (cs:[6Ch]), which halts the timer immediately.
; ============================================================================
apa_timer_stop_short PROC NEAR
                MOV     AL, CS:[36H]
                MOV     DX, CS:[6CH]
                OUT     DX, AL
                RETF
apa_timer_stop_short ENDP

; ============================================================================
; 0x0AED  --  apa_irq_handler
;
; The IRQ entry. Saves every register, sets DS := CS, polls the chip
; for "I asked you a question, what's the answer" status, and depending
; on the engine state either swaps the ring-buffer half, pumps the next
; chunk, or does nothing. Ends in IRET; chains to the previous handler
; on entry via a flag check.
;
;   Type:        IRQ handler
;   Category:    DAC / sample-rate timer
;   Dispatch:    Hardware IRQ (vector at 0x08+cs:[41h] for PIC1 IRQs,
;                0x70+cs:[41h]-8 for PIC2 IRQs).
;   Callers:     PIC (hardware-driven; entered via INT vector that
;                apa_irq_install set up).
;   Callees:     apa_timer_stop_short, apa_swap_and_kick,
;                apa_timer_program, apa_slot5_stop.
;
;   Inputs:      (entered on hardware IRQ; reads PAS IRQ-status
;                register and engine state)
;   Outputs:     (none)
;
;   Touches:     all caller registers preserved (saves DS, DX, AX,
;                CX, BX, SI, DI, ES, BP; restores in reverse order).
;
;   Side effects:
;     - Reads apa_pcm_status_port; if bit 3 is clear, the IRQ was
;       not ours (ih_chain path) -- EOI the PIC and return without
;       further work.
;     - Writes EOI 0x20 to PIC1 (port 0x20); on PIC2-side IRQs also
;       writes 0x20 to PIC2 (port 0xA0).
;     - Writes 0x79 to apa_pic_unmask_port and 0x21 to apa_pcm_port
;       (PAS-side IRQ acknowledge sequence).
;     - Advances cs:[5Eh]/cs:[5Ch] (32-bit "bytes streamed" counter)
;       by the previous chunk's expected IRQ count.
;     - Either calls apa_swap_and_kick (end-of-chunk), or
;       apa_timer_program (start next half), or apa_slot5_stop
;       (engine self-terminate).
;
;   Notes:
;     - CLD at entry forces direction-flag clear because we use
;       LODSB/STOSB in the buffer-pump path.
;     - The "not-our-IRQ" chain path (`ih_chain`) does the PIC EOI
;       but does NOT chain to the previous IRQ-vector handler --
;       this driver assumes its IRQ is dedicated. If you're seeing
;       another card on the same IRQ line dropping events, that's
;       why.
; ============================================================================
apa_irq_handler PROC    NEAR
                PUSH    DS
                PUSH    DX
                PUSH    AX
                PUSH    CX
                PUSH    BX
                PUSH    SI
                PUSH    DI
                PUSH    ES
                PUSH    BP
                CLD
                MOV     AX, CS
                MOV     DS, AX
                MOV     DX, apa_pcm_status_port
                IN      AL, DX
                AND     AL, 8
                JE      SHORT ih_chain
                MOV     AL, 20H
                OUT     20H, AL
                MOV     DX, apa_pic_unmask_port
                MOV     AL, 79H
                OUT     DX, AL
                MOV     DX, apa_pcm_port
                MOV     AL, 21H
                OUT     DX, AL
                CMP     BYTE PTR CS:[3AH], 1
                JNE     SHORT ih_check_h2
                MOV     AX, CS:[66H]
                ADD     CS:[5EH], AX
                ADC     WORD PTR CS:[5CH], 0
                PUSH    CS
                CALL    apa_timer_stop_short
                CMP     BYTE PTR CS:[4DH], 1
                JE      SHORT ih_unmask
                CALL    apa_swap_and_kick
                JMP     SHORT ih_unmask
ih_check_h2:    CMP     WORD PTR CS:[52H], 0
                JE      SHORT ih_no_half2
                XOR     BYTE PTR CS:[47H], 1
                JE      SHORT ih_no_half2
                CALL    apa_timer_program
                JMP     SHORT ih_unmask
ih_no_half2:    CMP     BYTE PTR CS:[43H], 1
                JNE     SHORT ih_slot5
                CALL    apa_timer_program
                MOV     BYTE PTR CS:[42H], 1
                JMP     SHORT ih_unmask
ih_slot5:       CALL    apa_slot5_stop
ih_unmask:      MOV     DX, apa_pcm_port
                MOV     AL, 0E1H
                OUT     DX, AL
                MOV     DX, apa_pcm_status_port
                OUT     DX, AL
ih_chain:       MOV     AL, 20H
                CMP     BYTE PTR CS:[41H], 7
                JBE     SHORT ih_pic1_only
                MOV     DX, 0A0H
                OUT     DX, AL
ih_pic1_only:   OUT     20H, AL
                POP     BP
                POP     ES
                POP     DI
                POP     SI
                POP     BX
                POP     CX
                POP     AX
                POP     DX
                POP     DS
                IRET
apa_irq_handler ENDP

; ============================================================================
; 0x0B8A  --  apa_set_rate
;
; Cache the requested sample rate, then program the chip's master timer
; with the divisor 0x3428 / rate. (0x3428 = 13352 ~ PIT base / target Hz
; for the chip's clock domain.)
;
;   Type:        Helper
;   Category:    Timer / rate
;   Callers:     apa_slot6, apa_init_playback, apa_read_chunk,
;                apa_slot11_irq_setup, apa_get_info.
;   Callees:     none
;
;   Inputs:
;     AX  --  desired sample rate (Hz, 1..0xFFFF)
;
;   Outputs:     (none)
;
;   Side effects:
;     - cs:[82h] (apa_rate_div) <- requested rate
;     - Writes 0x36 to port 138Bh (PCM mode = rate-divisor write).
;     - Writes the 16-bit divisor 0x3428/rate to port 1388h (low) /
;       1388h (high) -- a chip-pause (EB 00) separates the two byte
;       writes, the same idiom as apa_timer_arm.
; ============================================================================
apa_set_rate    PROC    NEAR
                MOV     CS:[82H], AX
                MOV     CX, AX
                MOV     DX, apa_master_timer_ctrl
                MOV     AL, 36H
                OUT     DX, AL
                MOV     DX, 12H
                MOV     AX, 3428H
                DIV     CX
                MOV     DX, apa_master_timer_div_lo
                OUT     DX, AL
                JMP     SHORT sr_pause      ; EB 00 chip-pause
sr_pause:       MOV     AL, AH
                OUT     DX, AL
                RET
apa_set_rate    ENDP

; ============================================================================
; 0x0BA8  --  apa_dx_ax_divrev
;
; A small helper: rotates DX left 4 nybbles, splits it into a 4-bit-low
; and an upper-shifted-right-12 word, then adds the upper into AX (with
; carry into the new DX). Used to compose a sample-count expressed as a
; 20-bit (paragraph + offset) pointer into a flat 32-bit count.
;
;   Type:        Helper (RETF-style)
;   Category:    Hand-rolled arithmetic
;   Calling convention: `PUSH CS / CALL apa_dx_ax_divrev`; RETF.
;   Callers:     apa_init_playback, apa_slot9_load_chunk.
;
;   Inputs:
;     DX:AX  --  20-bit segment:offset combination (DX = segment,
;                AX = offset)
;
;   Outputs:
;     DX:AX  --  flat 20-bit byte count (DX = high 4 bits, AX = low
;                16 bits)
;
;   Touches:     CX preserved (saved/restored on stack).
;
;   Notes:
;     The formula: rotate DX left 4 -> nybble that was high now low,
;     mask 0x0F for the new DX (top 4 bits), mask 0xFFF0 + add to AX
;     with carry propagation for the low 16 bits.
; ============================================================================
apa_dx_ax_divrev PROC   NEAR
                PUSH    CX
                MOV     CL, 4
                ROL     DX, CL
                MOV     CX, DX
                AND     DX, 0FH
                AND     CX, 0FFF0H
                ADD     AX, CX
                ADC     DX, 0
                POP     CX
                RETF
apa_dx_ax_divrev ENDP

; ============================================================================
; 0x0BBC  --  apa_unmask_irq_emit
;
; Single-purpose: write 0x21 to PAS 0xB8A (this is the "stop sample"
; command). RETF (push-CS-call calling convention).
;
;   Type:        Helper (RETF-style)
;   Category:    DAC / chip I/O
;   Calling convention: `PUSH CS / CALL apa_unmask_irq_emit`; RETF.
;   Callers:     apa_stop.
;
;   Inputs:      (none)
;   Outputs:     (none)
;   Side effects: writes 0x21 to apa_pcm_port.
;
;   Notes:
;     The function name is misleading -- it does NOT unmask the IRQ.
;     It writes the PAS "stop sample" command.
; ============================================================================
apa_unmask_irq_emit PROC NEAR
                MOV     DX, apa_pcm_port
                MOV     AL, 21H
                OUT     DX, AL
                RETF
apa_unmask_irq_emit ENDP

; ============================================================================
; 0x0BC3  --  apa_irq_install
;
; Install our IRQ handler at the user's chosen IRQ line (AL = IRQ#).
; Saves the old vector at cs:[bx] (4 bytes), then unmasks the PIC bit
; for that line. The PUSHF/CLI prologue serializes the install.
;
;   Type:        Helper (RETF-style)
;   Category:    IRQ install
;   Calling convention: `PUSH CS / CALL apa_irq_install`; RETF.
;   Callers:     apa_init_playback, apa_slot11_irq_setup.
;
;   Inputs:
;     AL  --  IRQ line (0..15)
;     DX  --  handler offset (within CS)
;     BX  --  state offset where the saved vector should be stashed
;             (passed as 0x88 so the original vector lands at
;             cs:[88h]).
;
;   Outputs:     (none)
;   Touches:     BX, CX, DX preserved; flags restored from PUSHF.
;
;   Side effects:
;     - Writes the IDT slot for the chosen IRQ vector (offset + segment)
;       so that incoming hardware interrupts vector to our handler.
;     - Reads the PIC mask register (cs:[7Ah]), clears the bit for
;       this IRQ line, and writes the new mask back -- this is what
;       *allows* the IRQ to fire.
;     - Saves the prior vector at cs:[BX..BX+3] for later restore.
;
;   Notes:
;     CLI -> install vector -> POPF protects the install from being
;     pre-empted partway through (the partial-write would crash on the
;     next IRQ).
; ============================================================================
apa_irq_install PROC    NEAR
                PUSH    BX
                PUSH    CX
                PUSH    DX
                PUSHF
                CLI
                MOV     CL, AL
                CMP     AL, 8
                JAE     SHORT ii_pic2
                ADD     AL, 8
                JMP     SHORT ii_vec
ii_pic2:        ADD     AL, 68H
ii_vec:         CBW
                SHL     AX, 1
                SHL     AX, 1
                MOV     DI, AX
                PUSH    ES
                SUB     AX, AX
                MOV     ES, AX
                MOV     AX, ES:[DI]
                MOV     CS:[BX], AX
                MOV     ES:[DI], DX
                MOV     AX, ES:[DI + 2]
                MOV     CS:[BX + 2], AX
                MOV     ES:[DI + 2], CS
                POP     ES
                MOV     AX, 1
                SHL     AX, CL
                CMP     CL, 8
                JAE     SHORT ii_no_swap
                MOV     AH, AL
ii_no_swap:     NOT     AH
                MOV     DX, CS:[7AH]
                IN      AL, DX
                AND     AL, AH
                OUT     DX, AL
                POPF
                POP     DX
                POP     CX
                POP     BX
                RETF
apa_irq_install ENDP

; ============================================================================
; 0x0C12  --  apa_irq_uninstall
;
; Restore the saved IRQ vector and remask the PIC bit. Note this is the
; mirror of apa_irq_install: no register saves around it because callers
; pre-cleared the registers they care about.
;
;   Type:        Helper (RETF-style)
;   Category:    IRQ teardown
;   Calling convention: `PUSH CS / CALL apa_irq_uninstall`; RETF.
;   Callers:     apa_stop.
;
;   Inputs:
;     AL  --  IRQ line (0..15)
;     BX  --  state offset where the saved vector was stashed (0x88)
;
;   Outputs:     (none)
;
;   Side effects:
;     - Writes the previously-saved 4-byte vector from cs:[BX..BX+3]
;       back to the IDT slot.
;     - Reads PIC mask, sets the bit for our IRQ line (masking it),
;       writes back.
; ============================================================================
apa_irq_uninstall PROC  NEAR
                PUSHF
                CLI
                MOV     CL, AL
                CMP     AL, 8
                JAE     SHORT iu_pic2
                ADD     AL, 8
                JMP     SHORT iu_vec
iu_pic2:        ADD     AL, 68H
iu_vec:         CBW
                SHL     AX, 1
                SHL     AX, 1
                MOV     DI, AX
                PUSH    ES
                SUB     AX, AX
                MOV     ES, AX
                MOV     AX, CS:[BX]
                MOV     ES:[DI], AX
                MOV     AX, CS:[BX + 2]
                MOV     ES:[DI + 2], AX
                POP     ES
                MOV     AX, 1
                SHL     AX, CL
                CMP     CL, 8
                JAE     SHORT iu_no_swap
                MOV     AH, AL
iu_no_swap:     MOV     DX, CS:[7AH]
                IN      AL, DX
                OR      AL, AH
                OUT     DX, AL
                POPF
                RETF
apa_irq_uninstall ENDP

; ============================================================================
; 0x0C52  --  apa_slot14_zero  (slot 14)
;
; Reserved slot -- just XOR AX, AX; RET.
;
;   Type:        Slot handler (stub)
;   Category:    Reserved / no-op
;   Dispatch:    Slot 14 (AX=14)
;   Inputs:      (none)
;   Outputs:     AX = 0
;   Notes:       Distinct from apa_slot_ret_a/b in that it explicitly
;                returns AX=0 (the others leave AX undefined).
; ============================================================================
apa_slot14_zero PROC    NEAR
                XOR     AX, AX
                RET
apa_slot14_zero ENDP

; ============================================================================
; 0x0C55  --  apa_slot9_load_chunk  (slot 9)
;
; Open the sample file, decode its header, set up chunk pointers, and
; queue the first buffer-read for playback. Big function (~290 bytes)
; that drives the file-I/O state machine.
;
;   Type:        Slot handler
;   Category:    File I/O, engine setup
;   Dispatch:    Slot 9 (AX=9; SS:SI -> 20-byte argument block)
;   Callers:     Game (via apa_dispatch)
;   Callees:     apa_stop, apa_decode_flags, apa_dx_ax_divrev,
;                apa_read_chunk, INT 21h (AH=3Dh open, 3Eh close,
;                42h seek).
;
;   Inputs:
;     SS:[SI+0]   --  offset of pathname or pre-opened handle (see
;                     SS:[SI+2] discriminator below).
;     SS:[SI+2]   --  if 0xFFFF: SS:[SI+0] is an already-open file
;                     handle. Else: segment of pathname (with offset
;                     in SS:[SI+0]).
;     SS:[SI+4]   --  seek position (low word)
;     SS:[SI+6]   --  seek position (high word)
;     SS:[SI+8]   --  remaining-chunk length (low)
;     SS:[SI+0Ah] --  remaining-chunk length (high)
;     SS:[SI+0Ch] --  buffer destination offset
;     SS:[SI+0Eh] --  buffer destination segment
;     SS:[SI+10h] --  buffer size in bytes
;     SS:[SI+12h] --  end-of-buffer behaviour (0 = stop on EOB,
;                     non-0 = kick / continue)
;     SS:[SI+13h] --  packed format flags (-> apa_decode_flags)
;
;   Outputs:
;     AX  --  0 on failure (file open / seek error)
;             0xFFFE if computed sample-count overflowed 16 bits
;             otherwise the byte-count-per-sample reciprocal needed
;             for query-pos arithmetic.
;
;   Side effects:
;     - cs:[40h] (apa_use_eob_kick) <- per arg.
;     - cs:[84h], cs:[86h] (remaining bytes) <- per arg.
;     - cs:[56h], cs:[58h] (buffer destination) <- per arg.
;     - cs:[74h] (file handle) <- newly-opened or arg-supplied handle.
;     - cs:[76h], cs:[78h] (seek pos) <- per arg.
;     - File handle from cs:[74h] closed before opening a new file
;       (releases the previous sample).
;     - May call apa_decode_flags (mutates cs:[34h], cs:[35h],
;       cs:[44h], cs:[49h]..cs:[4Ch]).
; ============================================================================
apa_slot9_load_chunk PROC NEAR
                PUSH    SI
                CALL    apa_stop
                POP     SI
                CMP     BYTE PTR SS:[SI + 12H], 0
                JNE     SHORT lc_eob_on
                MOV     BYTE PTR CS:[40H], 0
                JMP     SHORT lc_setflags
lc_eob_on:      MOV     BYTE PTR CS:[40H], 1
lc_setflags:    MOV     AL, SS:[SI + 13H]
                CALL    apa_decode_flags
                MOV     AX, SS:[SI + 8]
                MOV     CS:[84H], AX
                MOV     AX, SS:[SI + 0AH]
                MOV     CS:[86H], AX
                MOV     AX, SS:[SI + 0CH]
                MOV     CS:[56H], AX
                MOV     DX, SS:[SI + 0EH]
                MOV     CS:[58H], DX
                PUSH    CS
                CALL    apa_dx_ax_divrev
                MOV     CS:[32H], DL
                MOV     CS:[33H], DL
                MOV     CS:[50H], AX
                MOV     AX, SS:[SI + 10H]
                SHR     AX, 1
                MOV     CS:[5AH], AX
                ADD     AX, CS:[50H]
                MOV     CS:[54H], AX
                JAE     SHORT lc_no_inc
                INC     BYTE PTR CS:[33H]
lc_no_inc:      MOV     AX, SS:[SI]
                OR      AX, SS:[SI + 2]
                JNE     SHORT lc_have_path
                MOV     BX, CS:[74H]
                JMP     SHORT lc_have_handle
lc_have_path:   CMP     WORD PTR SS:[SI + 2], 0FFFFH
                JNE     SHORT lc_open_file
                MOV     BX, SS:[SI]
                JMP     SHORT lc_set_handle
lc_open_file:   CMP     WORD PTR CS:[74H], 0FFFFH
                JE      SHORT lc_close_done
                MOV     BX, CS:[74H]
                MOV     AH, 3EH
                INT     21H
                MOV     WORD PTR CS:[74H], 0FFFFH
lc_close_done:  PUSH    DS
                MOV     DX, SS:[SI]
                MOV     AX, SS:[SI + 2]
                MOV     DS, AX
                MOV     AL, 0
                MOV     AH, 3DH
                INT     21H
                POP     DS
                JAE     SHORT lc_open_ok
                XOR     AX, AX
                RET
lc_open_ok:     MOV     BX, AX
lc_set_handle:  MOV     CS:[74H], BX
lc_have_handle: MOV     DX, SS:[SI + 4]
                MOV     CS:[76H], DX
                MOV     CX, SS:[SI + 6]
                MOV     CS:[78H], CX
                MOV     AL, 0
                MOV     AH, 42H
                INT     21H
                JAE     SHORT lc_seek_ok
                XOR     AX, AX
                RET
lc_seek_ok:     CALL    apa_read_chunk
                MOV     BYTE PTR CS:[48H], 0
                MOV     AX, CS:[84H]
                MOV     BX, CS:[86H]
                MOV     CS:[80H], AX
                MOV     CS:[7EH], BX
                CMP     BYTE PTR CS:[34H], 1
                JNE     SHORT lc_no_double
                SHL     AX, 1
                RCL     BX, 1
lc_no_double:   MOV     CX, 3CH
                MUL     CX
                PUSH    AX
                PUSH    DX
                MOV     AX, BX
                MUL     CX
                POP     DX
                ADD     DX, AX
                POP     AX
                CMP     DX, CS:[82H]
                JAE     SHORT lc_overflow
                DIV     WORD PTR CS:[82H]
                JMP     SHORT lc_done
lc_overflow:    MOV     AX, 0FFFEH
lc_done:        RET
apa_slot9_load_chunk ENDP

; ============================================================================
; 0x0D79  --  apa_decode_flags
;
; Unpack the byte in AL into 6 separate state bytes: bit 0 -> [34h],
; bit 1 -> [49h], bit 2 -> [4Bh], bit 3 -> [4Ah], bit 4 -> [4Ch], bit
; 7 -> [44h]. Also initializes [35h] to 0x80 (ADPCM seed value).
;
;   Type:        Helper
;   Category:    Sample-format flags
;   Callers:     apa_slot9_load_chunk, apa_read_chunk.
;
;   Inputs:
;     AL  --  packed flags byte:
;             bit 0 -> apa_stereo_swap (cs:[34h])
;             bit 1 -> apa_smooth (cs:[49h])
;             bit 2 -> apa_dbl_rate (cs:[4Bh])
;             bit 3 -> apa_signed (cs:[4Ah])
;             bit 4 -> apa_byte_swap (cs:[4Ch])
;             bit 7 -> apa_adpcm_enable (cs:[44h])
;             bits 5/6 are unused.
;
;   Outputs:     (none)
;
;   Side effects:
;     - cs:[35h] (apa_adpcm_seed) <- 0x80 (silence midpoint).
;     - The six format flag bytes <- their respective input bit.
; ============================================================================
apa_decode_flags PROC   NEAR
                MOV     BYTE PTR CS:[35H], 80H
                TEST    AL, 1
                JE      SHORT df_bit0_off
                MOV     BYTE PTR CS:[34H], 1
                JMP     SHORT df_test_bit1
df_bit0_off:    MOV     BYTE PTR CS:[34H], 0
df_test_bit1:   TEST    AL, 2
                JE      SHORT df_bit1_off
                MOV     BYTE PTR CS:[49H], 1
                JMP     SHORT df_test_bit2
df_bit1_off:    MOV     BYTE PTR CS:[49H], 0
df_test_bit2:   TEST    AL, 4
                JE      SHORT df_bit2_off
                MOV     BYTE PTR CS:[4BH], 1
                JMP     SHORT df_test_bit3
df_bit2_off:    MOV     BYTE PTR CS:[4BH], 0
df_test_bit3:   TEST    AL, 8
                JE      SHORT df_bit3_off
                MOV     BYTE PTR CS:[4AH], 1
                JMP     SHORT df_test_bit4
df_bit3_off:    MOV     BYTE PTR CS:[4AH], 0
df_test_bit4:   TEST    AL, 10H
                JE      SHORT df_bit4_off
                MOV     BYTE PTR CS:[4CH], 1
                JMP     SHORT df_test_bit7
df_bit4_off:    MOV     BYTE PTR CS:[4CH], 0
df_test_bit7:   TEST    AL, 80H
                JE      SHORT df_bit7_off
                MOV     BYTE PTR CS:[44H], 1
                JMP     SHORT df_done
df_bit7_off:    MOV     BYTE PTR CS:[44H], 0
df_done:        RET
apa_decode_flags ENDP

; ============================================================================
; 0x0DEC  --  apa_read_chunk
;
; Read 2 bytes from the file into the dest buffer. If the first byte is
; 0x8D (the .SOL marker), read the rest of the SOL header (length + tag
; "SOL\0" + rate + flags) and update the chunk parameters. Otherwise
; rewind by 2 and treat the file as raw PCM.
;
;   Type:        Helper
;   Category:    File I/O, sample-format detection
;   Callers:     apa_slot9_load_chunk.
;   Callees:     INT 21h (AH=3Fh read, 42h seek), apa_decode_flags,
;                apa_set_rate.
;
;   Inputs:      cs:[74h] (file handle), cs:[56h]/cs:[58h] (dest
;                offset/segment).
;
;   Outputs:     If a .SOL header was decoded:
;                  cs:[84h], cs:[86h] <- decoded length
;                  cs:[7Ch]           <- decoded sample rate
;                  cs:[76h], cs:[78h] <- advanced past header
;                  flags applied via apa_decode_flags
;                Otherwise: file is rewound by 2 (so the read pointer
;                is back at the start) and the caller's chunk
;                parameters are untouched.
;
;   Side effects:
;     - 2 or up to 8 bytes read from the open file into the dest
;       buffer.
;     - File seek pointer modified (advance for SOL or rewind for
;       raw PCM).
;     - DS clobbered/restored across the I/O.
; ============================================================================
apa_read_chunk  PROC    NEAR
                MOV     BX, CS:[74H]
                MOV     CX, 2
                MOV     DX, CS:[56H]
                MOV     AX, CS:[58H]
                PUSH    DS
                MOV     DS, AX
                MOV     SI, DX
                MOV     AH, 3FH
                INT     21H
                LODSB
                CMP     AL, 8DH
                JNE     SHORT rc_not_sol
                LODSB
                MOV     CL, AL
                MOV     SI, DX
                MOV     AH, 3FH
                INT     21H
                LODSB
                CMP     AL, 53H
                JNE     SHORT rc_not_sol
                LODSB
                CMP     AL, 4FH
                JNE     SHORT rc_not_sol
                LODSB
                CMP     AL, 4CH
                JNE     SHORT rc_not_sol
                LODSB
                CMP     AL, 0
                JE      SHORT rc_decode_sol
rc_not_sol:     POP     DS
                MOV     DX, CS:[76H]
                MOV     CX, CS:[78H]
                MOV     AL, 0
                MOV     AH, 42H
                INT     21H
                RET
rc_decode_sol:  ADD     CX, 2
                ADD     CS:[76H], CX
                ADC     WORD PTR CS:[78H], 0
                LODSB
                MOV     AH, AL
                LODSB
                XCHG    AL, AH
                PUSH    AX
                LODSB
                MOV     CL, AL
                LODSW
                MOV     BX, AX
                LODSW
                MOV     DX, AX
                POP     AX
                POP     DS
                MOV     CS:[84H], BX
                MOV     CS:[86H], DX
                PUSH    AX
                MOV     AL, CL
                CALL    apa_decode_flags
                POP     AX
                MOV     CS:[7CH], AX
                CALL    apa_set_rate
                RET
apa_read_chunk  ENDP

; ============================================================================
; 0x0E73  --  apa_slot10_resume  (slot 10)
;
; Resume playback after a pause. Sets paused flag, then pumps two
; buffers back-to-back to refill both halves.
;
;   Type:        Slot handler
;   Category:    Engine resume
;   Dispatch:    Slot 10 (AX=10; no slot-args read)
;   Callers:     Game (via apa_dispatch)
;   Callees:     apa_buffer_pump (twice)
;
;   Inputs:      (none beyond global state)
;   Outputs:     AX = 0
;
;   Side effects:
;     - cs:[48h] (apa_paused) <- 1
;     - cs:[47h] (apa_active_half) <- 0xFF (force first-pump path)
;     - cs:[3Bh] (apa_buffer_half) <- 0
;     - Both ring-buffer halves refilled.
; ============================================================================
apa_slot10_resume PROC  NEAR
                MOV     BYTE PTR CS:[48H], 1
                MOV     BYTE PTR CS:[47H], 0FFH
                MOV     BYTE PTR CS:[3BH], 0
                CALL    apa_buffer_pump
                CALL    apa_buffer_pump
                XOR     AX, AX
                RET
apa_slot10_resume ENDP

; ============================================================================
; 0x0E8E  --  apa_slot11_irq_setup  (slot 11)
;
; Final setup: install IRQ vector, optionally re-set the sample rate,
; and signal the chip to begin streaming. Drains the buffer pump
; pipeline.
;
;   Type:        Slot handler
;   Category:    Engine activation
;   Dispatch:    Slot 11 (AX=11; no slot-args read)
;   Callers:     Game (via apa_dispatch, after slot 3 and slot 9)
;   Callees:     apa_irq_install, apa_set_rate, apa_buffer_pump (twice
;                or skip if paused), apa_buffer_swap.
;
;   Inputs:      (none beyond global state)
;   Outputs:     AX = 0
;
;   Side effects:
;     - IRQ vector installed (re-installs if slot 3 already did).
;     - cs:[3Ah] (apa_state_active) <- 1 (engine now running).
;     - cs:[46h] (apa_buffer_dirty) <- 1.
;     - cs:[47h] (apa_active_half) <- 1.
;     - cs:[5Eh]/cs:[5Ch] (bytes-streamed counter) <- 0.
;     - cs:[45h] (apa_busy_flag) <- 0.
;     - cs:[4Dh] (apa_playing) <- 0.
;     - Buffer halves primed by two apa_buffer_pump calls.
; ============================================================================
apa_slot11_irq_setup PROC NEAR
                MOV     AL, CS:[41H]
                MOV     DX, OFFSET apa_irq_handler
                MOV     BX, 88H
                PUSH    CS
                CALL    apa_irq_install
                MOV     DX, apa_pcm_mode_port
                MOV     AL, 8
                OUT     DX, AL
                MOV     AX, CS:[7CH]
                CMP     AX, CS:[82H]
                JE      SHORT is_rate_ok
                CALL    apa_set_rate
is_rate_ok:     MOV     BYTE PTR CS:[3AH], 1
                MOV     BYTE PTR CS:[46H], 1
                CMP     BYTE PTR CS:[48H], 1
                JE      SHORT is_paused
                MOV     BYTE PTR CS:[47H], 0FFH
                MOV     BYTE PTR CS:[3BH], 0
                CALL    apa_buffer_pump
                CALL    apa_buffer_pump
                JMP     SHORT is_after_pump
is_paused:      MOV     BYTE PTR CS:[48H], 0
is_after_pump:  MOV     BYTE PTR CS:[47H], 1
                MOV     WORD PTR CS:[5EH], 0
                MOV     WORD PTR CS:[5CH], 0
                MOV     AL, CS:[3BH]
                PUSH    AX
                MOV     BYTE PTR CS:[3BH], 0FFH
                CALL    apa_buffer_swap
                POP     AX
                MOV     CS:[3BH], AL
                MOV     BYTE PTR CS:[45H], 0
                MOV     BYTE PTR CS:[4DH], 0
                XOR     AX, AX
                RET
apa_slot11_irq_setup ENDP

; ============================================================================
; 0x0F14  --  apa_buffer_pump
;
; The streaming engine's "give me more samples" call. Checks re-entrancy
; (cs:[3Eh]), then reads up to one buffer-half worth of bytes from the
; file, optionally decompresses/inverts/swaps them, and writes them
; into the active ring half. Big function (~568 bytes).
;
;   Type:        Helper (engine workhorse)
;   Category:    File I/O, sample format conversion, ring buffer
;   Callers:     apa_play_sound, apa_slot10_resume, apa_slot11_irq_setup,
;                apa_buffer_swap (indirect through apa_swap_and_kick).
;   Callees:     apa_int_check, INT 21h (AH=3Fh read, 42h seek).
;
;   Inputs:      (reads global state; cs:[84h]/cs:[86h] = remaining
;                bytes, cs:[5Ah] = half-buffer size, cs:[3Bh] = which
;                half, cs:[47h] = active half, plus the format flags
;                at cs:[34h]/cs:[44h]/cs:[49h]..cs:[4Ch]).
;
;   Outputs:     (none -- early-returns if re-entered or out of data)
;
;   Side effects:
;     - Sets cs:[3Eh] (apa_in_pump) = 1 on entry; clears on exit
;       (re-entry guard).
;     - Decrements cs:[84h]/cs:[86h] by the consumed byte count.
;     - Toggles cs:[3Bh] (apa_buffer_half).
;     - Writes the per-half size into cs:[4Eh] or cs:[52h] when the
;       buffer is finalized (consumed-bytes tracker).
;     - Reads bytes from the open file via INT 21h AH=3Fh.
;     - Optionally seeks to loop-point (if apa_use_eob_kick set).
;
;   Notes:
;     The body has six format-conversion sub-passes that may all be
;     active at once:
;       1. Re-entrancy guard + early-exit.
;       2. Sample double-rate (interpolation) -- splits long reads
;          across two seek windows since each pass takes 800h bytes.
;       3. Raw file read into the dest buffer.
;       4. Sign-flip pass (cs:[4Ah]=1: inverts MSB to convert
;          signed->unsigned PCM).
;       5. Smooth pass (cs:[49h]=1: rotates samples).
;       6. ADPCM stereo demux (cs:[34h]=1: uses apa_init_table as a
;          delta-step lookup to expand 4-bit nybbles into 8-bit
;          samples; running accumulator stored at cs:[35h]).
;     Each sub-pass is bypassed when its flag is 0.
; ============================================================================
apa_buffer_pump PROC    NEAR
                CMP     BYTE PTR CS:[apa_state_in_pump_off], 1
                JE      SHORT bp_done
                MOV     AX, CS:[84H]
                OR      AX, CS:[86H]
                JE      SHORT bp_done
                MOV     AL, CS:[3BH]
                CMP     AL, CS:[47H]
                JE      SHORT bp_done
                CALL    apa_int_check
                JE      SHORT bp_check_ok
bp_done:        RET
bp_check_ok:    MOV     BYTE PTR CS:[apa_state_in_pump_off], 1
                PUSHF
                STI
                MOV     WORD PTR CS:[60H], 0
                MOV     CX, CS:[5AH]
                CMP     BYTE PTR CS:[3BH], 0
                JNE     SHORT bp_half_b
                MOV     DX, 0
                JMP     SHORT bp_after_half
bp_half_b:      MOV     DX, CX
bp_after_half:  CMP     BYTE PTR CS:[4BH], 1
                JNE     SHORT bp_no_dbl
                SHL     CX, 1
bp_no_dbl:      CMP     BYTE PTR CS:[34H], 1
                JNE     SHORT bp_no_stereo
                SHR     CX, 1
bp_no_stereo:   CMP     WORD PTR CS:[86H], 0
                JNE     SHORT bp_full_chunk
                CMP     CX, CS:[84H]
                JBE     SHORT bp_full_chunk
                MOV     CX, CS:[84H]
bp_full_chunk:  SUB     CS:[84H], CX
                SBB     WORD PTR CS:[86H], 0
                MOV     DI, DX
                CMP     BYTE PTR CS:[34H], 1
                JNE     SHORT bp_no_dbl2
                ADD     DX, CX
bp_no_dbl2:     MOV     BX, CS:[74H]
                MOV     AX, CS:[58H]
                CMP     BYTE PTR CS:[4BH], 1
                JNE     SHORT bp_no_split
                MOV     ES, AX
                MOV     DX, 9CH
                MOV     AX, DS
                CMP     CX, 800H
                JBE     SHORT bp_no_split_cx
                MOV     CS:[62H], CX
                MOV     CX, 800H
                SUB     CS:[62H], CX
                JMP     SHORT bp_no_split
bp_no_split_cx: MOV     WORD PTR CS:[62H], 0
bp_no_split:    MOV     SI, DX
                PUSH    DS
                MOV     DS, AX
                MOV     AH, 3FH
                INT     21H
                POP     DS
                JAE     SHORT bp_read_ok
                MOV     AX, CX
bp_read_ok:     CMP     BYTE PTR CS:[4BH], 1
                JNE     SHORT bp_no_invert
                SHR     AX, 1
                PUSH    AX
                PUSH    SI
                PUSH    DI
                MOV     CX, AX
bp_invert_loop: LODSW
                CMP     BYTE PTR CS:[4AH], 1
                JNE     SHORT bp_no_signflip
                MOV     AL, 7FH
                SUB     AL, AH
                JMP     SHORT bp_store_inv
bp_no_signflip: MOV     AL, AH
bp_store_inv:   STOSB
                LOOP    bp_invert_loop
                POP     DI
                POP     SI
                POP     AX
bp_no_invert:   CMP     BYTE PTR CS:[49H], 1
                JNE     SHORT bp_no_smooth
                PUSH    AX
                PUSH    SI
                PUSH    DI
                PUSH    DS
                MOV     CX, AX
                MOV     AX, CS:[58H]
                MOV     DS, AX
                MOV     ES, AX
bp_smooth_loop: LODSB
                ROL     AX, 1
                STOSB
                LOOP    bp_smooth_loop
                POP     DS
                POP     DI
                POP     SI
                POP     AX
bp_no_smooth:   CMP     BYTE PTR CS:[34H], 1
                JNE     SHORT bp_no_stereo2
                PUSH    AX
                PUSH    BX
                PUSH    DX
                PUSH    SI
                PUSH    DI
                PUSH    DS
                MOV     CX, AX
                MOV     DL, CS:[35H]
                MOV     AX, CS:[58H]
                MOV     DS, AX
                MOV     ES, AX
                MOV     AH, DL
bp_stereo_loop: LODSB
                MOV     DL, AL
                SHR     AL, 1
                SHR     AL, 1
                SHR     AL, 1
                SHR     AL, 1
                CMP     AL, 8
                JL      SHORT bp_lo_pos
                MOV     BX, 0FH
                SUB     BL, AL
                SUB     AH, CS:[BX + apa_init_table]
                JMP     SHORT bp_lo_done
bp_lo_pos:      MOV     BL, AL
                XOR     BH, BH
                ADD     AH, CS:[BX + apa_init_table]
bp_lo_done:     MOV     AL, AH
                STOSB
                AND     DL, 0FH
                CMP     DL, 8
                JL      SHORT bp_hi_pos
                MOV     BX, 0FH
                SUB     BL, DL
                SUB     AH, CS:[BX + apa_init_table]
                JMP     SHORT bp_hi_done
bp_hi_pos:      MOV     BL, DL
                XOR     BH, BH
                ADD     AH, CS:[BX + apa_init_table]
bp_hi_done:     MOV     AL, AH
                STOSB
                LOOP    bp_stereo_loop
                POP     DS
                MOV     CS:[35H], AH
                POP     DI
                POP     SI
                POP     DX
                POP     BX
                POP     AX
                SHL     AX, 1
bp_no_stereo2:  ADD     CS:[60H], AX
                CMP     BYTE PTR CS:[4BH], 1
                JNE     SHORT bp_check_eof
                CMP     WORD PTR CS:[62H], 0
                JE      SHORT bp_check_eof
                ADD     DI, AX
                MOV     CX, CS:[62H]
                JMP     bp_no_dbl2
bp_check_eof:   CMP     BYTE PTR CS:[40H], 1
                JNE     SHORT bp_finalize
                MOV     CX, CS:[84H]
                OR      CX, CS:[86H]
                JNE     SHORT bp_finalize
                MOV     CS:[5EH], CX
                MOV     CS:[5CH], CX
                PUSH    AX
                PUSH    DX
                MOV     DX, CS:[76H]
                MOV     CX, CS:[78H]
                MOV     AL, 0
                MOV     AH, 42H
                INT     21H
                POP     DX
                POP     AX
                MOV     CX, CS:[80H]
                MOV     CS:[84H], CX
                MOV     CX, CS:[7EH]
                MOV     CS:[86H], CX
                CMP     BYTE PTR CS:[34H], 1
                JNE     SHORT bp_no_re_seed
                MOV     BYTE PTR CS:[35H], 80H
                SHR     AX, 1
bp_no_re_seed:  MOV     CX, CS:[5AH]
                SUB     CX, CS:[60H]
                JE      SHORT bp_finalize
                ADD     DX, AX
                JMP     bp_after_half
bp_finalize:    MOV     AX, CS:[60H]
                CMP     BYTE PTR CS:[3BH], 0
                JNE     SHORT bp_half_b_store
                MOV     CS:[4EH], AX
                JMP     SHORT bp_clear_dirty
bp_half_b_store: MOV    CS:[52H], AX
bp_clear_dirty: XOR     BYTE PTR CS:[3BH], 1
                MOV     BYTE PTR CS:[apa_state_in_pump_off], 0
                POPF
                RET
apa_buffer_pump ENDP

; ============================================================================
; 0x1141  --  apa_swap_and_kick
;
; Tiny wrapper called from the IRQ handler when the engine has finished
; consuming the current sample and we need to ask the buffer-swap path
; to recycle. Sets the "buffer dirty" flag at cs:[46h]=1 so swap can
; tell that a kick is owed, then tail-calls into apa_buffer_swap.
;
;   Type:        Helper
;   Category:    Ring buffer
;   Callers:     apa_irq_handler.
;   Callees:     apa_buffer_swap.
;
;   Inputs:      (none)
;   Outputs:     (none)
;   Side effects: cs:[46h] (apa_buffer_dirty) <- 1; tail-effects of
;                apa_buffer_swap apply (see that function).
; ============================================================================
apa_swap_and_kick PROC  NEAR
                MOV     BYTE PTR CS:[46H], 1
                CALL    apa_buffer_swap
                RET
apa_swap_and_kick ENDP

; ============================================================================
; 0x114B  --  apa_buffer_swap
;
; Toggle which ring half is "live" when the IRQ fires: if engine is
; idle, kick playback to a stop; otherwise flip the live half and pump
; the freshly-emptied one.
;
;   Type:        Helper
;   Category:    Ring buffer
;   Callers:     apa_play_sound, apa_slot11_irq_setup,
;                apa_swap_and_kick.
;   Callees:     apa_stop, apa_timer_program.
;
;   Inputs:      (none beyond global state)
;   Outputs:     (none)
;
;   Side effects:
;     - Re-entry guard: cs:[3Dh] (apa_in_swap) set on entry,
;       cleared on exit; early-returns if already set.
;     - Either: cs:[47h] (apa_active_half) toggled, cs:[46h]
;       (apa_buffer_dirty) cleared, and apa_timer_program called
;       (regular swap path);
;     - Or: apa_stop called (engine has no more bytes; EOF reached).
; ============================================================================
apa_buffer_swap PROC    NEAR
                CMP     BYTE PTR CS:[3DH], 1
                JE      SHORT bs_done
                CMP     BYTE PTR CS:[46H], 1
                JNE     SHORT bs_done
                MOV     BYTE PTR CS:[3DH], 1
                MOV     AL, CS:[47H]
                XOR     AL, 1
                CMP     AL, CS:[3BH]
                JNE     SHORT bs_flip
                MOV     AX, CS:[84H]
                OR      AX, CS:[86H]
                JNE     SHORT bs_unmark
                CALL    apa_stop
                JMP     SHORT bs_unmark
bs_flip:        MOV     BYTE PTR CS:[46H], 0
                XOR     BYTE PTR CS:[47H], 1
                CALL    apa_timer_program
bs_unmark:      MOV     BYTE PTR CS:[3DH], 0
bs_done:        RET
apa_buffer_swap ENDP

; ============================================================================
; 0x1194  --  apa_query_pos  (slot 13)
;
; Read the current playback position: if paused, return zeros. If
; stopped, return all-ones. Otherwise read the chip's playback counter,
; subtract from the stored bytes-streamed count, and store as a 32-bit
; result at SS:[SI+0..6].
;
;   Type:        Slot handler
;   Category:    Engine state query
;   Dispatch:    Slot 13 (AX=13; SS:SI -> 6-byte result buffer)
;   Callers:     Game (via apa_dispatch)
;
;   Inputs:      cs:[68h] (DAC counter readback port), cs:[5Eh]/
;                cs:[5Ch] (bytes-streamed), cs:[82h] (rate divisor).
;
;   Outputs:     AX = 0 (paused), 0xFFFE (overflow), or normalized
;                position.
;     SS:[SI+0..1]  --  position (samples played).
;     SS:[SI+2..3]  --  byte counter low word.
;     SS:[SI+4..5]  --  byte counter high word.
;
;   Side effects:
;     - Briefly disables interrupts (PUSHF/CLI) around the chip
;       readback so the value isn't torn by an IRQ landing midway.
; ============================================================================
apa_query_pos   PROC    NEAR
                CMP     BYTE PTR CS:[48H], 1
                JNE     SHORT qp_check_stop
                MOV     WORD PTR SS:[SI], 0
                MOV     WORD PTR SS:[SI + 2], 0
                MOV     WORD PTR SS:[SI + 4], 0
                XOR     AX, AX
                RET
qp_check_stop:  CMP     BYTE PTR CS:[4DH], 1
                JNE     SHORT qp_read_chip
                MOV     WORD PTR SS:[SI], 0FFFFH
                MOV     WORD PTR SS:[SI + 2], 0FFFFH
                MOV     WORD PTR SS:[SI + 4], 0FFFFH
                XOR     AX, AX
                RET
qp_read_chip:   PUSHF
                CLI
                MOV     DX, CS:[68H]
                IN      AL, DX
                MOV     CL, AL
                IN      AL, DX
                MOV     CH, AL
                MOV     DX, CS:[66H]
                MOV     AX, CS:[5EH]
                MOV     BX, CS:[5CH]
                POPF
                SUB     DX, CX
                ADD     AX, DX
                ADC     BX, 0
                CMP     BYTE PTR CS:[4BH], 1
                JNE     SHORT qp_no_dbl
                SHL     AX, 1
                RCL     BX, 1
                MOV     CX, 1EH
                JMP     SHORT qp_have_div
qp_no_dbl:      MOV     CX, 3CH
qp_have_div:    MOV     SS:[SI + 2], AX
                MOV     SS:[SI + 4], BX
                MUL     CX
                PUSH    AX
                PUSH    DX
                MOV     AX, BX
                MUL     CX
                POP     DX
                ADD     DX, AX
                POP     AX
                CMP     DX, CS:[82H]
                JAE     SHORT qp_overflow
                DIV     WORD PTR CS:[82H]
                JMP     SHORT qp_store
qp_overflow:    MOV     AX, 0FFFEH
qp_store:       MOV     SS:[SI], AX
                XOR     AX, AX
                RET
apa_query_pos   ENDP

; ============================================================================
; 0x122E  --  apa_int_check
;
; Quick check that we're not re-entering during a BIOS or mouse-driver
; interrupt: OR the four "in handler" flag bytes together and return the
; result in AL (ZF set if all clear).
;
;   Type:        Helper
;   Category:    Re-entrancy guard
;   Callers:     apa_buffer_pump.
;
;   Inputs:      cs:[8Ch] (INT 1Ch flag pointer FAR), cs:[90h] (INT
;                34h flag pointer FAR), cs:[3Fh] (in-INT-10h flag),
;                cs:[3Ch] (in-INT-33h flag).
;
;   Outputs:
;     AL  --  bitwise OR of the four flags
;     ZF  --  set if all four flags are zero (safe to pump)
;
;   Notes:
;     LES BX,CS:[8Ch] reads the 32-bit FAR pointer at cs:[8Ch] into
;     ES:BX in one instruction. ES:[BX] is then the byte the pointer
;     references. The same idiom appears for the cs:[90h] pointer.
; ============================================================================
apa_int_check   PROC    NEAR
                LES     BX, CS:[8CH]
                MOV     AL, ES:[BX]
                LES     BX, CS:[90H]
                OR      AL, ES:[BX]
                OR      AL, CS:[3FH]
                OR      AL, CS:[3CH]
                RET
apa_int_check   ENDP

; ============================================================================
; 0x1249  --  apa_int10_hook
;
; Installed as the new INT 10h vector. Sets the "inside INT 10h" flag,
; chains to the original handler via a far call, clears the flag.
;
;   Type:        Interrupt-vector hook
;   Category:    Re-entrancy guard
;   Dispatch:    INT 10h (any caller in the system)
;   Callers:     Game's BIOS-video code (via INT 10h).
;   Callees:     The previously-installed INT 10h handler at cs:[98h].
;
;   Inputs:      (whatever the caller put in registers; we don't touch)
;   Outputs:     (passed through; the chain handler decides)
;
;   Side effects:
;     - cs:[3Fh] (apa_in_bios) <- 1 across the chained call.
;       apa_int_check ORs this into its result so the buffer pump
;       won't run while the BIOS is mid-call.
; ============================================================================
apa_int10_hook  PROC    NEAR
                MOV     BYTE PTR CS:[3FH], 1
                PUSHF
                CALL    DWORD PTR CS:[98H]
                MOV     BYTE PTR CS:[3FH], 0
                IRET
apa_int10_hook  ENDP

; ============================================================================
; 0x125C  --  apa_int33_hook
;
; Installed as the new INT 33h vector. Same pattern as INT 10h but for
; the mouse driver.
;
;   Type:        Interrupt-vector hook
;   Category:    Re-entrancy guard
;   Dispatch:    INT 33h (any caller in the system)
;   Callers:     Game's mouse-driver code (via INT 33h).
;   Callees:     The previously-installed INT 33h handler at cs:[94h].
;
;   Inputs:      (whatever the caller put in registers; we don't touch)
;   Outputs:     (passed through)
;
;   Side effects:
;     - cs:[3Ch] (apa_in_mouseint) <- 1 across the chained call.
; ============================================================================
apa_int33_hook  PROC    NEAR
                MOV     BYTE PTR CS:[3CH], 1
                PUSHF
                CALL    DWORD PTR CS:[94H]
                MOV     BYTE PTR CS:[3CH], 0
                IRET
apa_int33_hook  ENDP

; ============================================================================
; 0x126F  --  apa_get_info  (slot 0)
;
; The one-time bring-up call. Probes the MV101 chip, hooks INT 10h and
; INT 33h, captures the active critical-section flag pointers, and sets
; up the PC's DOS busy-flag pointer. Returns AX=0 on failure or
; AX=0x126F on success (the latter is "I am alive, here's my entry
; address back").
;
;   Type:        Slot handler (one-shot init)
;   Category:    Driver bring-up
;   Dispatch:    Slot 0 (AX=0; no slot-args read)
;   Callers:     Game's driver-loader (via apa_dispatch, once at boot).
;   Callees:     apa_detect_mv101, apa_set_rate, INT 21h (AH=19h
;                getdrive, 25h set-vector, 34h get-InDOS, 35h
;                get-vector), INT 2Fh (AX=150Bh -- multiplex InDOS).
;
;   Inputs:      (none beyond global state)
;   Outputs:     AX = OFFSET apa_get_info (0x126Fh) on success,
;                AX = 0 on failure (chip absent, or InDOS probe
;                returned an unexpected value).
;
;   Side effects:
;     - cs:[4Dh] (apa_playing) <- 1 (so apa_stop is a no-op until
;       slot 11 clears it).
;     - cs:[98h]/cs:[9Ah] (saved INT 10h vector) <- original handler.
;     - cs:[94h]/cs:[96h] (saved INT 33h vector) <- original handler.
;     - cs:[90h]/cs:[92h] (INT 34h read-only flag pointer FAR) <- per
;       DOS's AH=34h getCriticalFlag.
;     - cs:[8Ch]/cs:[8Eh] (read-only flag pointer FAR, one byte
;       before the InDOS flag) <- same as cs:[90h] minus 1.
;     - INT 10h vector redirected to apa_int10_hook.
;     - INT 33h vector redirected to apa_int33_hook.
;     - cs:[7Ch] (apa_sample_rate) <- 0x2B11 (the default).
;     - cs:[74h] (apa_file_handle) <- 0xFFFF (no file).
;
;   Notes:
;     The InDOS-probe path (gi_init -> gi_indos_ok) is dead at
;     runtime because the byte at 0x1501 is 0xDC (not 0xCD), so the
;     CMP at gi_init fails and the function falls through to the
;     gi_no_indos vector-install path. See the trailing byte block at
;     0x1501.
; ============================================================================
apa_get_info    PROC    NEAR
                CALL    apa_detect_mv101
                OR      AX, AX
                JE      SHORT gi_init
                XOR     AX, AX
                RET
gi_init:        MOV     BYTE PTR CS:[4DH], 1
                CMP     BYTE PTR CS:[1501H], 0CDH
                JNE     SHORT gi_no_indos
                MOV     AH, 19H
                INT     21H
                XOR     AH, AH
                MOV     CX, AX
                MOV     BX, 0
                MOV     AX, 150BH
                INT     2FH
                CMP     BX, 0ADADH
                JE      SHORT gi_indos_ok
                XOR     AX, AX
                RET
gi_indos_ok:    OR      AX, AX
                JNE     SHORT gi_no_indos
                XOR     AX, AX
                RET
gi_no_indos:    MOV     AH, 35H
                MOV     AL, 10H
                INT     21H
                MOV     CS:[98H], BX
                MOV     CS:[9AH], ES
                PUSH    DS
                MOV     DX, OFFSET apa_int10_hook
                MOV     AX, CS
                MOV     DS, AX
                MOV     AH, 25H
                MOV     AL, 10H
                INT     21H
                POP     DS
                MOV     AH, 35H
                MOV     AL, 33H
                INT     21H
                MOV     CS:[94H], BX
                MOV     CS:[96H], ES
                PUSH    DS
                MOV     DX, OFFSET apa_int33_hook
                MOV     AX, CS
                MOV     DS, AX
                MOV     AH, 25H
                MOV     AL, 33H
                INT     21H
                POP     DS
                MOV     AH, 34H
                INT     21H
                MOV     CS:[90H], BX
                MOV     CS:[92H], ES
                DEC     BX
                MOV     CS:[8CH], BX
                MOV     CS:[8EH], ES
                MOV     AX, 2B11H
                MOV     CS:[7CH], AX
                CALL    apa_set_rate
                MOV     BYTE PTR CS:[apa_state_in_pump_off], 0
                MOV     BYTE PTR CS:[3DH], 0
                MOV     WORD PTR CS:[74H], 0FFFFH
                MOV     AX, OFFSET apa_get_info
                RET
apa_get_info    ENDP

; ============================================================================
; 0x131F  --  apa_detect_mv101
;
; INT 2Fh with AX=BC04h is Media Vision's "are you out there?" probe.
; The driver-side returns 'VM' (0x4D56) in AX if MV101 is present. We
; check that, then read the chip's revision byte from port 0xB8B, then
; switch on CL (chip revision) and BL (selected I/O block) to choose
; the right set of port bases.
;
;   Type:        Helper
;   Category:    Chip probe / hardware config
;   Callers:     apa_get_info.
;   Callees:     INT 2Fh AX=BC04h (Media Vision's MV101 probe).
;
;   Inputs:
;     BL  --  user-selected I/O block (1..7; 0 means "no card", 4 is
;             reserved). Comes in from the host's config file via the
;             game's loader.
;
;   Outputs:
;     AX  --  0 on success (chip present, port-base set)
;             0xFFFF on failure (chip absent, BL out of range, or
;             BL=0 / BL=4 -- both rejected).
;     cs:[41h] (apa_chip_rev) <- CL on success.
;
;   Side effects (success path):
;     - cs:[7Ah] <- PIC mask port (0x21 for IRQs 0..7, 0xA1 for 8..15).
;     - cs:[72h] (filter port), cs:[64h]/cs:[68h] (DAC ports),
;       cs:[6Ah]/cs:[6Ch]/cs:[6Eh] (timer ports) all loaded for the
;       selected BL configuration.
;     - cs:[36h], cs:[38h], cs:[39h] (chip-config bytes) seeded.
;     - On success, writes the PAS stop-sample command, IRQ unmask,
;       and DAC mode-8 select bytes to kick the chip into a known
;       resting state.
; ============================================================================
apa_detect_mv101 PROC   NEAR
                MOV     AX, 0BC04H
                INT     2FH
                SUB     AX, 4D56H
                JE      SHORT dm_chip_present
                RET
dm_chip_present:
                MOV     DX, apa_pcm_mode_port
                IN      AL, DX
                MOV     CS:[41H], CL
                CMP     CL, 8
                JAE     SHORT dm_pic2
                MOV     WORD PTR CS:[7AH], 21H
                JMP     SHORT dm_after_pic
dm_pic2:        MOV     WORD PTR CS:[7AH], 0A1H
dm_after_pic:   OR      BL, BL
                JNE     SHORT dm_bl_nz
                MOV     AX, 0FFFFH
                RET
dm_bl_nz:       CMP     BL, 1
                JNE     SHORT dm_not_1
                MOV     WORD PTR CS:[72H], 83H
                MOV     WORD PTR CS:[6CH], 0AH
                MOV     WORD PTR CS:[6EH], 0BH
                MOV     WORD PTR CS:[6AH], 0CH
                MOV     WORD PTR CS:[64H], 2
                MOV     WORD PTR CS:[68H], 3
                MOV     BYTE PTR CS:[39H], 49H
                MOV     BYTE PTR CS:[36H], 5
                MOV     BYTE PTR CS:[38H], 1
dm_not_1:       CMP     BL, 2
                JNE     SHORT dm_not_2
                MOV     WORD PTR CS:[72H], 81H
                MOV     WORD PTR CS:[6CH], 0AH
                MOV     WORD PTR CS:[6EH], 0BH
                MOV     WORD PTR CS:[6AH], 0CH
                MOV     WORD PTR CS:[64H], 4
                MOV     WORD PTR CS:[68H], 5
                MOV     BYTE PTR CS:[39H], 4AH
                MOV     BYTE PTR CS:[36H], 6
                MOV     BYTE PTR CS:[38H], 2
dm_not_2:       CMP     BL, 3
                JNE     SHORT dm_not_3
                MOV     WORD PTR CS:[72H], 82H
                MOV     WORD PTR CS:[6CH], 0AH
                MOV     WORD PTR CS:[6EH], 0BH
                MOV     WORD PTR CS:[6AH], 0CH
                MOV     WORD PTR CS:[64H], 6
                MOV     WORD PTR CS:[68H], 7
                MOV     BYTE PTR CS:[39H], 4BH
                MOV     BYTE PTR CS:[36H], 7
                MOV     BYTE PTR CS:[38H], 3
dm_not_3:       CMP     BL, 4
                JNE     SHORT dm_not_4
                MOV     AX, 0FFFFH
                RET
dm_not_4:       CMP     BL, 5
                JNE     SHORT dm_not_5
                MOV     WORD PTR CS:[72H], 8BH
                MOV     WORD PTR CS:[6CH], 0D4H
                MOV     WORD PTR CS:[6EH], 0D6H
                MOV     WORD PTR CS:[6AH], 0D8H
                MOV     WORD PTR CS:[64H], 0C4H
                MOV     WORD PTR CS:[68H], 0C6H
                MOV     BYTE PTR CS:[39H], 49H
                MOV     BYTE PTR CS:[36H], 5
                MOV     BYTE PTR CS:[38H], 1
dm_not_5:       CMP     BL, 6
                JNE     SHORT dm_not_6
                MOV     WORD PTR CS:[72H], 89H
                MOV     WORD PTR CS:[6CH], 0D4H
                MOV     WORD PTR CS:[6EH], 0D6H
                MOV     WORD PTR CS:[6AH], 0D8H
                MOV     WORD PTR CS:[64H], 0C8H
                MOV     WORD PTR CS:[68H], 0CAH
                MOV     BYTE PTR CS:[39H], 4AH
                MOV     BYTE PTR CS:[36H], 6
                MOV     BYTE PTR CS:[38H], 2
dm_not_6:       CMP     BL, 7
                JNE     SHORT dm_not_7
                MOV     WORD PTR CS:[72H], 8AH
                MOV     WORD PTR CS:[6CH], 0D4H
                MOV     WORD PTR CS:[6EH], 0D6H
                MOV     WORD PTR CS:[6AH], 0D8H
                MOV     WORD PTR CS:[64H], 0CCH
                MOV     WORD PTR CS:[68H], 0CEH
                MOV     BYTE PTR CS:[39H], 4BH
                MOV     BYTE PTR CS:[36H], 7
                MOV     BYTE PTR CS:[38H], 3
dm_not_7:       CMP     BL, 7
                JBE     SHORT dm_arm
                MOV     AX, 0FFFFH
                RET
dm_arm:         MOV     DX, apa_pcm_port
                MOV     AL, 21H
                OUT     DX, AL
                MOV     DX, apa_pic_unmask_port
                MOV     AL, 0F9H
                OUT     DX, AL
                MOV     DX, apa_pcm_status_port
                OUT     DX, AL
                MOV     DX, apa_pcm_mode_port
                MOV     AL, 8
                OUT     DX, AL
                XOR     AX, AX
                RET
apa_detect_mv101 ENDP

; ============================================================================
; 0x1501  --  trailing magic byte
;
; Read by apa_get_info to detect whether DOS's "InDOS" critical-section
; flag is reachable. The value is 0xDC -- which does NOT match the
; expected 0xCD, so the InDOS detection path is skipped at runtime.
; This byte is the very last byte of the binary.
; ============================================================================
                DB      0DCH

                END     _start

; ============================================================================
; Glossary of acronyms and domain terms used in this file (alphabetical)
;
;   ADPCM     Adaptive Differential Pulse-Code Modulation. A simple
;             compression scheme where each sample is encoded as a 4-bit
;             "step index" into a delta table, applied to the running
;             value. apa_init_table is the 8-entry step table; the
;             stereo-demux loop in apa_buffer_pump uses it.
;
;   DAC       Digital-to-Analog Converter. The PAS's output stage. This
;             driver writes 8-bit unsigned PCM samples to the DAC FIFO
;             at apa_pcm_port and the DAC plays them at the rate the
;             sample-rate timer dictates.
;
;   DMA       Direct Memory Access. The original PAS programming model
;             would use an 8237 DMA controller to feed the DAC; this
;             driver instead uses interrupt-driven manual transfers
;             ("software FIFO") through apa_buffer_pump. The 2KB data
;             region at 0x9C..0x89B is still called "DMA buffer" by
;             convention even though no DMA hardware is involved.
;
;   DOS       The host operating system (MS-DOS / PC-DOS 3.x..6.x).
;             Reached via "INT 21h" software interrupts: AH=3Dh opens a
;             file, AH=3Eh closes it, AH=3Fh reads, AH=42h seeks.
;
;   DUDE      Dynamix's Universal-Driver Engine -- the cross-driver
;             binary format and dispatch ABI. APA is a v2.6 DUDE
;             driver (AX-indexed dispatch, DS save/restore) rather than
;             the v1.x form ADL uses (BP-indexed dispatch, no DS work).
;
;   DUDE v2.6 ABI quirks  (relative to the v1.x ABI ADL uses):
;             - 16 slots in the function table (not 18).
;             - The slot index arrives in AX (not BP).
;             - The trampoline saves DS on entry, sets DS := CS so the
;               handler can use 16-bit memory operands without a CS:
;               prefix, then restores DS on exit.
;             - The trampoline's epilogue is `OR AX, AX / RETF` -- the
;               OR sets the zero flag from the handler's return code so
;               the FAR caller can branch on it without testing AX.
;
;   EOB / EOF End-Of-Buffer / End-Of-File. The streaming engine
;             distinguishes two end conditions: hitting the end of the
;             current chunk (EOB, kick the next chunk), and hitting the
;             end of the underlying sample file (EOF, either stop or
;             loop -- controlled by cs:[40h], apa_use_eob_kick).
;
;   EOI       End-Of-Interrupt. A specific byte (0x20) the CPU writes
;             to the PIC's command port (0x20 or 0xA0) to acknowledge
;             that the IRQ has been handled and the PIC may now deliver
;             the next one. Forgetting the EOI hangs the entire system.
;
;   FBOV      The MZ-overlay format used by Dynamix's KRONDOR.EXE.
;             FBOV does not apply to the standalone driver binary.
;
;   FIFO      First-In-First-Out queue. The PAS DAC has a small
;             internal sample FIFO; we feed it by writing successive
;             bytes to apa_pcm_port.
;
;   FM        Frequency Modulation. The synthesis technique used by the
;             AdLib / OPL2 chip. Not used by APA -- APA is the digital-
;             sample driver. The PAS card includes an OPL2/OPL3 chip
;             for FM synthesis; that is a *separate* driver (PRO / PS1)
;             living in a different file. Important: the "PAS PRO"
;             driver does FM, the "APA" driver does PCM -- they don't
;             share code.
;
;   InDOS     A flag byte inside DOS that is non-zero whenever DOS is
;             executing a system call on the foreground task's behalf.
;             apa_get_info would normally use it to refuse re-entering
;             DOS from the IRQ handler, but the file's magic byte at
;             0x1501 is 0xDC (not 0xCD) so the InDOS path is dead.
;
;   IRQ       Interrupt Request line. A hardware signal that the CPU
;             pre-empts whatever it's doing and jumps to a handler. The
;             PAS asserts its IRQ when its sample-rate timer expires.
;             "PIC" is the Programmable Interrupt Controller, the 8259
;             chip that arbitrates among the 16 IRQ lines.
;             PIC1 manages IRQs 0..7 at ports 0x20/0x21.
;             PIC2 manages IRQs 8..15 at ports 0xA0/0xA1, cascaded
;             through PIC1's IRQ 2.
;
;   MV101     Media Vision's audio ASIC. The brain of the PAS family.
;             Detected via INT 2Fh AX=0xBC04 which returns 'VM' (0x4D56)
;             in AX if present.
;
;   PAS       Pro AudioSpectrum. Media Vision's family of sound cards
;             (PAS, PAS Plus, PAS 16, PAS Studio). All four use the
;             MV101 ASIC plus a separate FM chip plus a DAC.
;
;   PAS DAC   The 8-bit DAC integrated into the PAS card. Programmed by
;             writing samples to apa_pcm_port at the rate the chip's
;             timer dictates. Output is 8-bit unsigned PCM (silence =
;             0x80, full positive = 0xFF, full negative = 0x00); the
;             apa_signed flag inverts the MSB to convert from 2's-comp
;             signed samples to unsigned.
;
;   PCM       Pulse-Code Modulation. Raw uncompressed digital audio --
;             one byte (or word) per sample, the value being the
;             instantaneous amplitude. The PAS DAC consumes 8-bit
;             unsigned PCM.
;
;   PIT       Programmable Interval Timer. The Intel 8253/8254 chip on
;             the IBM PC motherboard. The PAS uses its own on-card
;             timer (not the system PIT) for sample-rate generation,
;             but the timer programming idiom (mode-byte, divisor-low,
;             divisor-high) is the same as the system PIT.
;
;   .SOL      Dynamix's compact sample-file container. Begins with the
;             marker byte 0x8D followed by 'SOL\0' and a small header
;             carrying rate + flags + length. Used by KRONDOR for
;             speech and effects. apa_read_chunk parses this header.
;
;   slot      A function-pointer entry in apa_func_table. The game
;             selects a handler by passing the slot index in AX. There
;             are 16 slots (0..15) in the v2.6 ABI.
;
; ============================================================================
