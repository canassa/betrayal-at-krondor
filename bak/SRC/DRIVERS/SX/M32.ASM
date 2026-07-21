; ============================================================================
; Sx.SSM.M32.bin -- Dynamix DUDE-format Roland MT-32 (MPU-401) sound driver,
;                   v1.08
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
; Sound Blaster, Roland MT-32, etc.) and picks the right one at runtime
; based on the user's "sound setup" choice.
;
; This file is the Roland MT-32 driver. Unlike the AdLib driver, which has
; to do all FM synthesis itself, the MT-32 is an external hardware
; synthesizer that handles every aspect of sound generation -- voice
; allocation, envelope shaping, polyphony, the lot. The driver here is
; therefore tiny: most slot handlers translate a few register-passed MIDI
; arguments into the standard 1-, 2-, or 3-byte MIDI messages that the
; MT-32 expects, then push those bytes out through the MPU-401 MIDI
; interface card.
;
; A few twists on top of that pass-through model:
;
;   - The driver maintains a "shadow" of every per-channel controller it
;     sets (program, volume, pan, sustain-pedal value, pitch bend,
;     modulation, plus a couple of patch-info bytes) so it can answer
;     "what's the current value of X?" queries (slot 17) without round-
;     tripping to the hardware.
;
;   - Channel 9 is the General-MIDI percussion channel. The driver uses a
;     128-byte "drum filter" table to map percussion notes -- some notes
;     are dropped, some are remapped, depending on what drum kit is
;     loaded.
;
;   - Slot 1 ("load patch bank") uploads a Dynamix-format patch bank to
;     the MT-32 via System Exclusive (SysEx) MIDI, then reseeds the
;     driver's internal shadow tables and forces a CC#7 (volume)
;     refresh on every channel.
;
;   - A "master enable" flag (0x04C0) gates output. When clear, the driver
;     short-circuits every CC#7 (volume) message to zero before sending.
;     Clearing the flag from slot 13 sends 9 explicit zero-volume CCs --
;     one per channel in the loop range 1..9 inclusive (drums included)
;     -- and is the way the game silences the MT-32 without unloading
;     the driver. Slot 12 (master volume) re-emits CC#7 on the same 1..9
;     range so a change to the master scalar propagates immediately to
;     every active channel.
;
; The file is laid out exactly as it appears on disk, which is also the
; order it sits in memory once the game loads it: first the DUDE header
; that identifies the driver, then a 1153-byte patch-bank buffer, then a
; small block of pad / global-state bytes, then per-channel state arrays,
; then the function-pointer table, then the dispatch trampoline, then the
; function bodies.
; ----------------------------------------------------------------------------

; ----------------------------------------------------------------------------
; About the Roland MT-32 and the MPU-401 interface
;
; The Roland MT-32 is a 1987-vintage external multi-timbral synthesizer.
; It's a self-contained box that speaks MIDI: you send it standard MIDI
; messages (note on / note off / control change / program change / pitch
; bend / system exclusive), it makes the sounds.
;
; The host PC talks to the MT-32 indirectly, via the Roland MPU-401 MIDI
; interface card. The MPU-401 exposes two 8-bit I/O ports to the CPU:
;
;   port 0x330  (the "data" port)     -- read or write a single byte of MIDI
;                                        traffic (one direction at a time;
;                                        the card has internal FIFOs).
;   port 0x331  (the "status/command" -- read for status (busy/ready bits),
;                 port)                  write to issue MPU-401 commands.
;
; This driver uses the MPU-401 in **UART mode** -- the card acts as a
; transparent byte pipe: every byte the driver writes to the data port
; is shifted out onto the MIDI cable, and that's it. There is no host-
; side sequencer, no timing assistance, no "intelligent" event
; scheduling. The card is bootstrapped into UART mode by writing the
; command 0x3F to the command port (port 0x331); after the MPU-401
; ACKs (returning 0xFE on the data port), every subsequent byte is
; sent out as raw MIDI.
;
; (The MPU-401 also has a more elaborate "intelligent mode" in which
; the card schedules MIDI events with its own clock, but this driver
; does not use it -- intelligent mode would require setup, IRQ wiring,
; and per-event timestamping that the game doesn't need. UART mode is
; both simpler and cheaper.)
;
; The bootstrap dance happens once, at slot 1 (patch-bank load): the
; driver first issues a full reset (command 0xFF), then three back-to-
; back 0x3F commands with delays in between. The triple-0x3F sequence
; comes from the MT-32 owner's manual and is the official belt-and-
; suspenders way to put the card into UART mode regardless of its
; previous state.
;
; The two write-side helpers in this driver are:
;
;   m32_mpu_send_cmd   -- writes a *command* byte to port 0x331. The
;                         protocol requires polling the status port until
;                         bit 6 ("output ready") clears, then writing the
;                         command, then optionally waiting for an
;                         acknowledge byte (0xFE) on the data port. Used
;                         only at bootstrap (0xFF reset, 0x3F UART entry).
;
;   m32_mpu_send_data  -- writes a *MIDI data* byte to port 0x330. Same
;                         polling pattern: wait for status bit 6 to clear,
;                         then write. Used for every MIDI byte the driver
;                         emits at runtime (note-on / off, CC, program
;                         change, pitch bend, SysEx).
;
; Both helpers wrap the I/O sequence in PUSHF/CLI ... POPF so that no
; hardware IRQ can land between the "is the port ready?" status read
; and the "here is the byte" data write. A split sequence would leave
; the MPU-401 in a half-written state.
;
; Both helpers use a *bounded* poll: they try a fixed number of times
; (0xFFFF for commands, 0xFF for data) and silently bail on timeout.
; The game prefers a brief audio glitch on broken hardware to a hung
; sound system, so neither helper signals failure to its caller -- the
; rest of the driver just keeps going.
;
; A "send MIDI message" in this driver (m32_send_midi) is therefore one to
; three calls to m32_mpu_send_data: status byte (e.g. 0x90+ch for note-on),
; then the one or two data bytes (note, velocity). The status-byte
; categories 0xC0..0xCF (program change) and 0xD0..0xDF (channel pressure)
; are 2-byte messages; everything else is 3-byte.
;
; The MPU-401 sits at base 0x330, the factory default and the only address
; this driver knows about.
;
; For deeper material, see:
;   - The MT-32 owner's manual ("LAPC-I / MT-32 Operations Manual" via
;     archive.org).
;   - The MPU-401 technical reference (multiple scans exist).
;   - The MT-32 SysEx control map at mt32.cmamod.com.
; ----------------------------------------------------------------------------

; ----------------------------------------------------------------------------
; About the DUDE dispatch ABI
;
; "DUDE" is Dynamix's internal sound-driver format. Every Dynamix sound
; driver of this generation is a flat binary that begins with a 0x37-byte
; header containing two magic numbers (0x87654321 and 0xFEDCBA98), the
; ASCII tag "dude", a human-readable device-name string, and a version
; tag. See the data section below for the literal layout.
;
; The game communicates with this driver in exactly one way: a far call
; into the *dispatch trampoline* at offset 0x05A7. Before the call, the
; game sets registers:
;
;   BP    = slot index (0..17) -- which operation we want
;   AL    = MIDI channel (0..15) for slots that need one
;   CL    = MIDI data byte 1   (velocity / CC value / pitch-bend low)
;   CH    = MIDI data byte 2   (note / CC# / pitch-bend high)
;   ES:AX = far pointer to a patch bank (slot 1 only)
;
; The dispatch trampoline (12 bytes) is just:
;
;   PUSH DX
;   SHL  BP, 1                       ; index -> byte offset
;   MOV  DX, CS:[BP + m32_func_table]
;   CALL DX                          ; near call to the slot's handler
;   POP  DX
;   RETF                             ; far return to the game
;
; Note that this driver uses DX as the scratch register for the indirect
; call; the AdLib driver uses BP for the same job. The choice is local --
; whichever register the slot handlers don't depend on for input.
;
; The handlers themselves are near procedures (`PROC NEAR ... ENDP`); the
; trampoline is the only thing that does a far return.
;
; The 18 slots in this driver, in order:
;
;   Slot  0  m32_get_info                 -- returns AH/AL/CH/CL descriptor
;   Slot  1  m32_load_patch_bank          -- ES:AX = src; uploads SysEx
;   Slot  2  m32_reset_voices             -- MPU "all notes off" reset
;   Slot  3  m32_slot_unused_ret          -- (no-op stub)
;   Slot  4  m32_midi_note_off            -- AL=ch, CH=note
;   Slot  5  m32_midi_note                -- AL=ch, CH=note, CL=vel (0=off)
;   Slot  6  m32_slot_unused_ret          -- (no-op stub)
;   Slot  7  m32_midi_control_change      -- AL=ch, CH=cc, CL=val
;   Slot  8  m32_midi_program_change      -- AL=ch, CL=program
;   Slot  9  m32_slot_unused_ret          -- (no-op stub)
;   Slot 10  m32_midi_pitch_bend          -- AL=ch, CX=bend (BE-packed)
;   Slot 11  m32_set_global_param         -- CL=val (0xFF=query)
;   Slot 12  m32_set_master_volume        -- CL=val (0xFF=query)
;   Slot 13  m32_set_master_enable        -- CL=val (0xFF=query)
;   Slot 14  m32_slot_unused_ret          -- (no-op stub)
;   Slot 15  m32_slot_unused_ret          -- (no-op stub)
;   Slot 16  m32_slot_unused_ret          -- (no-op stub)
;   Slot 17  m32_query_state              -- read-side of the setter ABI
;
; Slots 3, 6, 9, 14, 15, 16 all point at a shared one-byte `RET` stub --
; they're reserved in the cross-driver ABI but this particular driver
; doesn't implement them. The driver has no internal timer or IRQ hook;
; every MIDI write is initiated by a game-side call into one of these
; slots.
; ----------------------------------------------------------------------------

; ----------------------------------------------------------------------------
; How to read this source
;
; - Lines like `MOV BX, AX` are CPU instructions. The first operand is
;   the destination, the second is the source -- read it as "BX = AX".
;   This is "Intel" order; AT&T-style "MOV AX, BX" with destination
;   second is a different convention and is not used here.
;
; - Lines like `m32_ch_program  DB 16 DUP(0FFH)` declare data: the
;   label names this address, `DB` says "the following are bytes", and
;   `16 DUP(0FFH)` means "sixteen copies of the value 0xFF". `DW` is the
;   16-bit equivalent (two bytes per entry, little-endian on x86).
;
; - `CS:[BX + label]` is a memory access where:
;     * `CS:` says "use the Code Segment register as the base"
;     * `[BX + label]` is the offset, computed at runtime as the contents
;       of register BX plus the constant `label`.
;   In this flat single-segment driver, every read/write uses CS: because
;   the data and code share one segment (the `.MODEL TINY` directive sets
;   that up).
;
; - Every function below begins with `<name> PROC NEAR` and ends with
;   `<name> ENDP`. Inside, labels like `noteoff_test:` are jump targets
;   local to that function (we prefix them with a 4-letter function
;   nickname so they don't collide with labels in other functions).
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
;                           pointers into arrays.
;     BP                 -- 16-bit base pointer; we use it as the slot
;                           index in the dispatch trampoline.
;     CS, DS, ES, SS     -- 16-bit segment registers. In TINY model
;                           CS=DS=SS, and the game arranges ES separately
;                           for slot 1 (the patch-bank loader).
;
; - Calling convention used in this driver: every "slot handler" is
;   reached via the dispatch trampoline with BP = slot index. Per-slot
;   register arguments are documented at each handler's prologue.
;   Internal helpers also pass arguments in registers, but the
;   convention varies per helper -- documented at each helper's prologue.
;
; - The two MPU-401 send helpers (m32_mpu_send_cmd, m32_mpu_send_data)
;   wrap their work in PUSHF/CLI ... POPF. The CLI disables interrupts
;   for the duration of the I/O sequence, because an interrupt arriving
;   mid-protocol could leave the MPU-401 in a half-written state.
; ----------------------------------------------------------------------------

; ----------------------------------------------------------------------------
; Glossary of acronyms used in this file (alphabetical)
;
;   CC        MIDI Continuous Controller (e.g. CC#7 = main volume)
;   DUDE      Dynamix's universal sound-driver container format
;   MIDI      Musical Instrument Digital Interface (the wire protocol)
;   MPU-401   Roland's MIDI Processing Unit ISA card, the host-side
;             interface to external MIDI hardware
;   MT-32     Roland's "Multi Timbre 32" hardware synthesizer
;   SOA       Struct-Of-Arrays (storage layout where each "field" is its
;             own array indexed by the same index)
;   SysEx     System-Exclusive MIDI message, a variable-length packet
;             used to send vendor-specific data (instrument uploads,
;             configuration, etc.) framed by 0xF0..0xF7
;   UART      Universal Asynchronous Receiver/Transmitter; here, the
;             MPU-401's pass-through mode where the card is just a byte
;             pipe to the external MIDI device
; ----------------------------------------------------------------------------

                .8086
                .MODEL  TINY
                .CODE
                ORG     0

; ============================================================================
; 0x0000  --  DUDE header
; ============================================================================
_start          LABEL   BYTE
                JMP     m32_dispatch                ; E9 A4 05

                DB      0                           ; pad_03

dude_magic_a    DD      87654321H
dude_iface_ver  DB      1, 4
dude_tag        DB      'dude'

device_name_len DB      30
device_name     DB      'Roland MT32 with MPU interface'

dude_magic_b    DD      0FEDCBA98H
dude_driver_kind DD     0200H
driver_ver_str  DB      'v1.08'

; ============================================================================
; 0x003A..0x04BA  --  patch-bank buffer (1153 bytes = 0x481)
;
;   Slot 1 (m32_load_patch_bank) overwrites this region with a Dynamix-
;   format patch bank uploaded from the game-side. The first 1153 bytes
;   of the bank are copied here verbatim; subsequent bytes (a SysEx
;   stream) are forwarded directly to the MPU-401 without going through
;   this buffer.
;
;   The buffer is sub-divided into five 128-byte tables (the bytes per
;   table are layered: low, mid, hi, drum-filter, extra) plus one
;   single byte of patch-set metadata at offset 0x200 in the bank
;   (which is offset 0x023A here), plus four trailing pad bytes.
;
;   Default contents on cold boot:
;
;     0x003A-0x00B9  (128 B all 0xFF)   m32_patch_table_0
;       Indexed by [si+3Ah] where si = patch # & 0x7F. Patch-change low
;       byte. 0xFF means "no patch loaded here yet", so until a bank is
;       loaded, every program change short-circuits to "send default
;       CC#7=12 to MT-32" and skips the program write.
;
;     0x00BA-0x0139  (128 B all 0x00)   m32_patch_table_1
;       Indexed by [si+0BAh]. Drum-table transpose offset.
;
;     0x013A-0x01B9  (128 B all 0x00)   m32_patch_table_2
;       Indexed by [si+13Ah]. Patch-change high byte.
;
;     0x01BA-0x0239  (128 B all 0x00)   m32_drum_filter
;       Indexed by note number for channel 9 (the GM percussion channel).
;       Each entry maps an incoming MIDI drum note to an MT-32 drum
;       note; 0xFF means "drop this drum hit entirely".
;
;     0x023A          (1 B = 0x00)      m32_drum_kit_id
;       After a bank load this byte is copied into the drum channel's
;       patch_hi slot. Default 0x00.
;
;     0x023B-0x02BA  (128 B all 0x00)   m32_patch_table_4
;       Indexed by [si+23Bh]. Per-patch flag / extra byte.
;
;     0x02BB-0x04BA  (512 B all 0x00)   m32_drum_velocity_table
;       Indexed by [di+2BBh] where di = patch_extra[ch] * 128 + note.
;       Drum velocity remap (for percussion channel). Sized to hold
;       four 128-byte drum kits.
;
; The whole region zeroes out cleanly except for the first 128 bytes
; which are 0xFF on cold boot.
; ============================================================================
m32_patch_table_0       DB 128 DUP(0FFH)
m32_patch_table_1       DB 128 DUP(000H)
m32_patch_table_2       DB 128 DUP(000H)
m32_drum_filter         DB 128 DUP(000H)
m32_drum_kit_id         DB 000H
m32_patch_table_4       DB 128 DUP(000H)
m32_drum_velocity_table DB 512 DUP(000H)

; ============================================================================
; 0x04BB  --  alignment pad / bank-tail (4 bytes of 0x00)
;
;   Four zero bytes between the end of the patch-bank buffer (0x04BA) and
;   the master-volume scalar at 0x04BF. These look like alignment padding
;   that lets m32_master_volume land on a nice address.
; ============================================================================
pad_4bb                 DB 4 DUP(000H)

; ============================================================================
; 0x04BF  --  global driver state (two scalar bytes)
;
;   m32_master_volume  -- master volume scaler 0..0x7F. Applied multipli-
;                         catively to every channel's CC#7 value before
;                         forwarding to the MT-32. Default 0x0F. Read in
;                         m32_midi_control_change (CC#7 path) and
;                         m32_set_master_volume. Setting it with slot 12
;                         (`MUL CC#7 / 0x0F`) re-emits CC#7 on every
;                         non-drum channel.
;
;   m32_master_enable  -- 0 = driver silenced, 1 = active. Read in
;                         m32_midi_control_change and m32_set_master_volume
;                         as a gate. Slot 13 toggles this; when toggled
;                         off, the driver iterates every non-drum channel
;                         emitting an explicit "CC#7 value 0" before
;                         setting the flag (so the MT-32 actually goes
;                         silent rather than holding the previous level).
; ============================================================================
m32_master_volume       DB 00FH
m32_master_enable       DB 001H

; ============================================================================
; 0x04C1..0x04F0  --  per-MIDI-channel state, 16 channels x 2 fields
;
;   m32_ch_program       -- currently-selected patch number (set via
;                           program change, slot 8). Default 0xFF so the
;                           first program change actually fires the
;                           MT-32 reload path even if the game ships a
;                           value of 0.
;
;   m32_ch_pitchbend     -- packed 14-bit pitch-bend value, two bytes
;                           per channel (low then high). Default
;                           0xFF/0xFF so the first pitch-bend always
;                           re-emits. The driver doesn't bother with
;                           the "centered = 0x2000" interpretation; it
;                           just shadow-stores the last (lsb, msb) pair
;                           the game sent.
; ============================================================================
m32_ch_program          DB 16 DUP(0FFH)
m32_ch_pitchbend        DB 32 DUP(0FFH)     ; 16 channels x (lsb, msb)

; ============================================================================
; 0x04F1..0x0530  --  per-MIDI-channel CC shadows, 16 ch x 4 fields
;
;   m32_ch_modulation    -- CC#1 (modulation wheel). Default 0xFF.
;   m32_ch_volume        -- CC#7 (main volume). Default 0xFF (= refresh
;                           on first set).
;   m32_ch_pan_cc10      -- CC#10 (pan). Default 0xFF.
;   m32_ch_sustain_cc64  -- CC#64 (sustain-pedal *value*; not to be
;                           confused with the note-active latch
;                           m32_ch_sustain_pedal below, which is a
;                           separate single-byte boolean). Default 0xFF.
;
;   The driver only shadows these four CCs. CC#11 (expression) is
;   *not* shadowed -- the CC-number suffix on the pan / sustain symbols
;   is a deliberate disambiguation of the code paths in
;   m32_midi_control_change and m32_query_state.
;
;   Read by m32_query_state (slot 17) and the redundancy-suppression
;   checks in m32_midi_control_change.
; ============================================================================
m32_ch_modulation       DB 16 DUP(0FFH)
m32_ch_volume           DB 16 DUP(0FFH)
m32_ch_pan_cc10         DB 16 DUP(0FFH)
m32_ch_sustain_cc64     DB 16 DUP(0FFH)

; ============================================================================
; 0x0531..0x0540  --  per-MIDI-channel sustain-pedal latch (16 bytes)
;
;   m32_ch_sustain_pedal -- 1 if any note is currently held on this
;                           channel, 0 if quiescent. Default 0x01.
;                           Cleared by CC#123 (all-notes-off, value
;                           0x7B); set by note-on. The driver short-
;                           circuits CC#123 when the latch is already
;                           clear, saving an MT-32 round trip.
; ============================================================================
m32_ch_sustain_pedal    DB 16 DUP(001H)

; ============================================================================
; 0x0541..0x0580  --  per-MIDI-channel patch shadows, 16 ch x 4 fields
;
;   m32_ch_transpose     -- semitone transpose offset from
;                           patch_table_1[program]. Added to outgoing
;                           note numbers. When the high bit is set
;                           (>= 0x80), the transpose is *negative*; the
;                           note-on loop adjusts wrap-around behavior
;                           accordingly (octave-down vs octave-up).
;                           All zero on cold boot.
;
;   m32_ch_patch_hi      -- patch_table_2[program] cached. Set on
;                           program change, re-sent as CC#0 (bank
;                           select MSB) when needed.
;
;   m32_ch_patch_extra   -- patch_table_4[program] cached. Used as a
;                           multiplier into m32_drum_velocity_table for
;                           the percussion channel.
;
;   m32_ch_program_lo    -- patch_table_0[program] cached. Whichever
;                           value the bank-loaded patch table currently
;                           holds for this channel's program number;
;                           0xFF means "no patch in this slot"
;                           (default).
; ============================================================================
m32_ch_transpose        DB 16 DUP(000H)
m32_ch_patch_hi         DB 16 DUP(000H)
m32_ch_patch_extra      DB 16 DUP(000H)
m32_ch_program_lo       DB 16 DUP(000H)

; ============================================================================
; 0x0581  --  m32_last_status: cached running-status byte
;
;   m32_send_midi stores AL|AH here just before it streams the message
;   out, so subsequent calls can implement MIDI "running status" (omit
;   the status byte if it's the same as last time). The current
;   implementation always sends the status byte; this is preserved
;   bookkeeping rather than active running-status logic.
; ============================================================================
m32_last_status         DB 000H

; ============================================================================
; 0x0582  --  m32_global_param: opaque driver-wide knob
;
;   Slot 11 reads / writes this byte (semantics unconfirmed, mirrors the
;   similar register in the AdLib driver). It's not consumed by any
;   other code path in this binary.
; ============================================================================
m32_global_param        DB 000H

; ============================================================================
; 0x0583  --  m32_func_table  (18 near pointers)
;
;   Indexed by slot number; the dispatch trampoline at offset 0x05A7
;   computes `slot * 2` and looks up the handler's near address here.
;   Six slots (3, 6, 9, 14, 15, 16) share a one-byte RET stub
;   (m32_slot_unused_ret) for unused entries.
; ============================================================================
m32_func_table  LABEL   WORD
                DW      m32_get_info                ; slot  0  driver descriptor
                DW      m32_load_patch_bank         ; slot  1  upload patch bank
                DW      m32_reset_voices            ; slot  2  silence + reset
                DW      m32_slot_unused_ret         ; slot  3  (reserved)
                DW      m32_midi_note_off           ; slot  4  MIDI note-off
                DW      m32_midi_note               ; slot  5  MIDI note (vel=0=off)
                DW      m32_slot_unused_ret         ; slot  6  (reserved)
                DW      m32_midi_control_change     ; slot  7  MIDI CC
                DW      m32_midi_program_change     ; slot  8  MIDI prog change
                DW      m32_slot_unused_ret         ; slot  9  (reserved)
                DW      m32_midi_pitch_bend         ; slot 10  MIDI pitch bend
                DW      m32_set_global_param        ; slot 11  set/query 0x0582
                DW      m32_set_master_volume       ; slot 12  master volume
                DW      m32_set_master_enable       ; slot 13  master enable
                DW      m32_slot_unused_ret         ; slot 14  (reserved)
                DW      m32_slot_unused_ret         ; slot 15  (reserved)
                DW      m32_slot_unused_ret         ; slot 16  (reserved)
                DW      m32_query_state             ; slot 17  query mirror

; ============================================================================
; 0x05A7  --  m32_dispatch  --  the trampoline
;
;   This is the ONLY entry point the game ever calls. The game does:
;
;       MOV  BP, <slot index>
;       <set up AL/CH/CL/etc per the slot's convention>
;       CALL FAR m32_seg:m32_dispatch
;
;   We:
;     - Save DX (used as the scratch register for the indirect call)
;     - Convert slot index to byte offset by shifting BP left 1
;     - Look up the slot's handler pointer in m32_func_table into DX
;     - Call DX as a near function
;     - Restore DX and return far to the game
;
;   The trampoline is 12 bytes: PUSH (1) + SHL (2) + MOV (5) + CALL (2)
;   + POP (1) + RETF (1).
; ============================================================================
m32_dispatch    PROC    NEAR
                PUSH    DX                      ; save scratch
                SHL     BP, 1                   ; slot * 2 = byte offset
                MOV     DX, CS:[BP + m32_func_table]
                CALL    DX                      ; near call to slot handler
                POP     DX                      ; restore for the game
                RETF                            ; far return to game
m32_dispatch    ENDP

; ============================================================================
; 0x05B3  --  m32_slot_unused_ret
;
;   A single-byte RET (opcode 0xC3). Shared by six "reserved but
;   unimplemented" slots (3, 6, 9, 14, 15, 16) in the function-pointer
;   table above. Calling any of them is a fast no-op.
; ============================================================================
m32_slot_unused_ret PROC NEAR
                RET
m32_slot_unused_ret ENDP

; ============================================================================
; ============================================================================
; FUNCTION BODIES below this line
; ============================================================================
; ============================================================================

; ----------------------------------------------------------------------------
; 0x05B4  --  m32_set_global_param  (slot 11)
;
;   Get / set the opaque scalar at 0x0582. The "0xFF means query"
;   convention is the standard one across DUDE drivers.
;
;   Type:        Slot handler
;   Category:    Global state
;   Dispatch:    Slot 11 (called as: BP=11, CL = value or 0xFF=query)
;
;   Inputs:
;     CL  --  new value, or 0xFF to read the current value
;
;   Outputs:
;     AX  --  previous value (zero-extended)
; ----------------------------------------------------------------------------
m32_set_global_param PROC NEAR
                MOV     AL, CS:[m32_global_param]
                XOR     AH, AH                  ; zero-extend old value
                CMP     CL, 0FFH                ; query mode?
                JNE     SHORT sgp_store
                RET
sgp_store:      MOV     CS:[m32_global_param], CL
                RET
m32_set_global_param ENDP

; ----------------------------------------------------------------------------
; 0x05C6  --  m32_midi_note_off  (slot 4)
;
;   The MIDI "note off" message. Forwards a 3-byte MIDI 0x80+ch event to
;   the MT-32 after channel-specific preprocessing.
;
;   Type:        Slot handler
;   Category:    MIDI dispatch
;   Dispatch:    Slot 4 (called as: BP=4, AL=channel, CH=note)
;
;   Inputs:
;     AL  --  MIDI channel (0..15). Channel 9 is the percussion channel
;             and triggers the drum-filter path below.
;     CH  --  MIDI note number (0..127)
;
;   Outputs:     none
;
;   Side effects:
;     For channel 9: looks up CH in m32_drum_filter; if 0xFF, drops the
;     event entirely; otherwise replaces CH with the filter value.
;     For other channels: drops the event if m32_ch_program_lo[ch] is
;     0xFF (no patch loaded); otherwise adds m32_ch_transpose[ch] to CH
;     (wrapping the result back into the 0..0x7F MIDI note range), then
;     calls m32_send_midi with AH=0x90 CL=0 (note-on with velocity 0,
;     which the MIDI spec defines as note-off).
; ----------------------------------------------------------------------------
m32_midi_note_off PROC NEAR
                PUSH    AX
                PUSH    SI
                PUSH    CX
                CMP     AL, 9                   ; percussion channel?
                JNE     SHORT noff_pitched
                XCHG    CH, CL                  ; swap so SI's low byte = note
                MOV     SI, CX
                XCHG    CH, CL                  ; restore CH = note
                AND     SI, 007FH               ; mask MIDI 7-bit
                MOV     CH, CS:[SI + m32_drum_filter]
                CMP     CH, 0FFH                ; filter says "drop"?
                JE      SHORT noff_done
                JMP     SHORT noff_emit
noff_pitched:   MOV     SI, AX
                AND     SI, 000FH               ; SI = channel
                CMP     BYTE PTR CS:[SI + m32_ch_program_lo], 0FFH
                JE      SHORT noff_done
                ADD     CH, CS:[SI + m32_ch_transpose]
                MOV     AH, 0F4H                ; signed step: -12 (negative xpose)
                CMP     BYTE PTR CS:[SI + m32_ch_transpose], 80H
                JB      SHORT noff_clamp        ; positive xpose -> step = +12
                MOV     AH, 0CH                 ; signed step: +12 (positive xpose)
noff_clamp:     CMP     CH, 80H                 ; note in MIDI range?
                JB      SHORT noff_emit
                ADD     CH, AH                  ; step by AH (12 semitones)
                JMP     SHORT noff_clamp
noff_emit:      MOV     AH, 90H                 ; MIDI note-on status
                MOV     CL, 0                   ; velocity 0 = note-off
                CALL    m32_send_midi
noff_done:      POP     CX
                POP     SI
                POP     AX
                RET
m32_midi_note_off ENDP

; ----------------------------------------------------------------------------
; 0x0614  --  m32_midi_note  (slot 5)
;
;   The MIDI "note on" message. Same shape as note-off but additionally
;   marks the channel's sustain-pedal latch and consults a drum-velocity
;   remap table for the percussion channel.
;
;   Type:        Slot handler
;   Category:    MIDI dispatch
;   Dispatch:    Slot 5 (called as: BP=5, AL=channel, CH=note, CL=velocity)
;
;   Inputs:
;     AL  --  MIDI channel (0..15)
;     CH  --  MIDI note number (0..127)
;     CL  --  velocity (0..127); a velocity of 0 in standard MIDI means
;             note-off, but this driver still goes through the normal
;             note path with CL=0 -- the MT-32 itself interprets the
;             0-velocity special case.
;
;   Outputs:     none
;
;   Side effects:
;     m32_ch_sustain_pedal[ch] <- 1
;     For drums (channel 9): look up CH in m32_drum_filter; if 0xFF,
;       drop; else replace CH; remap CL via m32_drum_velocity_table.
;     For other channels: drop if program_lo[ch] is 0xFF; else apply
;       transpose; emit MIDI 0x90+ch CH CL.
; ----------------------------------------------------------------------------
m32_midi_note   PROC    NEAR
                PUSH    AX
                PUSH    SI
                PUSH    CX
                PUSH    DI
                CMP     AL, 9                   ; percussion channel?
                JNE     SHORT non_pitched
                XCHG    CH, CL
                MOV     SI, CX
                XCHG    CH, CL
                AND     SI, 007FH               ; SI = drum note
                MOV     CH, CS:[SI + m32_drum_filter]
                CMP     CH, 0FFH                ; filter says "drop"?
                JE      SHORT non_done
                MOV     SI, AX
                AND     SI, 000FH
                JMP     SHORT non_drum_vel
non_pitched:    MOV     SI, AX
                AND     SI, 000FH
                CMP     BYTE PTR CS:[SI + m32_ch_program_lo], 0FFH
                JE      SHORT non_done
                ADD     CH, CS:[SI + m32_ch_transpose]
                MOV     AH, 0F4H
                CMP     BYTE PTR CS:[SI + m32_ch_transpose], 80H
                JB      SHORT non_clamp
                MOV     AH, 0CH
non_clamp:      CMP     CH, 80H
                JB      SHORT non_drum_vel
                ADD     CH, AH
                JMP     SHORT non_clamp
non_drum_vel:   PUSH    AX
                ; DI = m32_ch_patch_extra[ch] * 128 + (note & 0x7F)
                ; -- index into m32_drum_velocity_table (0x80 entries
                ; per drum-kit, kit selected by patch_extra).
                MOV     AL, 80H
                MUL     BYTE PTR CS:[SI + m32_ch_patch_extra]
                MOV     DI, CX
                AND     DI, 007FH
                ADD     DI, AX
                POP     AX
                MOV     CL, CS:[DI + m32_drum_velocity_table]
                MOV     BYTE PTR CS:[SI + m32_ch_sustain_pedal], 1
                MOV     AH, 90H                 ; MIDI note-on status
                CALL    m32_send_midi
non_done:       POP     DI
                POP     CX
                POP     SI
                POP     AX
                RET
m32_midi_note   ENDP

; ----------------------------------------------------------------------------
; 0x0682  --  m32_midi_control_change  (slot 7)
;
;   The MIDI "control change" (CC) message. Caches the new value in the
;   relevant shadow array and forwards a 3-byte MIDI 0xB0+ch event to
;   the MT-32 -- with one twist: CC#7 (main volume) gets multiplied by
;   m32_master_volume / 0x0F so a global "master volume" knob is applied
;   transparently to every CC#7.
;
;   Type:        Slot handler
;   Category:    MIDI dispatch
;   Dispatch:    Slot 7 (called as: BP=7, AL=ch, CH=cc#, CL=value)
;
;   Recognized CCs:
;     CC#7  (main volume)     -- shadow + scaled forward (or short-
;                                circuit if master_enable is 0)
;     CC#10 (pan)             -- shadow + redundancy-checked forward
;     CC#64 (sustain pedal)   -- shadow + redundancy-checked forward
;     CC#123 (all notes off)  -- short-circuit if sustain_pedal latch
;                                is already 0
;     other CCs               -- silently dropped (the driver doesn't
;                                shadow them; the MT-32 may or may not
;                                care).
;
;   Inputs:
;     AL  --  MIDI channel
;     CH  --  CC number (0..127)
;     CL  --  CC value (0..127)
;
;   Outputs:     none
;
;   Notes:
;     This function is *also* called internally from
;     m32_midi_program_change to re-emit the channel's volume after a
;     program change, and from m32_set_master_volume to scale every
;     channel's volume when the master is moved. In both cases the
;     caller has set CH=7 and CL=<the channel's current shadow volume>.
; ----------------------------------------------------------------------------
m32_midi_control_change PROC NEAR
                PUSH    AX
                PUSH    SI
                MOV     SI, AX
                AND     SI, 000FH               ; SI = channel
                AND     CL, 7FH                 ; clamp value to 7-bit
                CMP     CH, 7                   ; CC#7 = main volume?
                JNE     SHORT cc_check_pan
                MOV     CS:[SI + m32_ch_volume], CL
                CMP     BYTE PTR CS:[m32_master_enable], 0
                JNE     SHORT cc_vol_scale
                JMP     SHORT cc_done
cc_vol_scale:   ADD     CL, CS:[SI + m32_ch_patch_hi]
                CMP     CL, 80H
                JB      SHORT cc_vol_lo
                MOV     CL, 7FH
                CMP     BYTE PTR CS:[SI + m32_ch_patch_hi], 80H
                JB      SHORT cc_vol_lo
                MOV     CL, 1
cc_vol_lo:      MOV     CH, AL
                MOV     AL, CS:[m32_master_volume]
                MUL     CL                      ; AX = master_volume * vol
                MOV     CL, 0FH
                DIV     CL                      ; AL = AX / 0x0F
                MOV     CL, AL
                MOV     AL, CH
                MOV     CH, 7                   ; CC# = 7
                OR      CL, CL
                JNE     SHORT cc_emit
                OR      AH, AH                  ; if master_volume==0 and CL==0,
                JE      SHORT cc_emit           ; emit CL=0
                INC     CL                      ; else nudge to CL=1 so the
                JMP     SHORT cc_emit           ; channel isn't dead silent
cc_check_pan:   CMP     CH, 0AH                 ; CC#10 = pan?
                JNE     SHORT cc_check_sustain
                CMP     CS:[SI + m32_ch_pan_cc10], CL
                JE      SHORT cc_done
                MOV     CS:[SI + m32_ch_pan_cc10], CL
                JMP     SHORT cc_emit
cc_check_sustain: CMP   CH, 40H                 ; CC#64 = sustain pedal?
                JNE     SHORT cc_check_anoff
                CMP     CS:[SI + m32_ch_sustain_cc64], CL
                JE      SHORT cc_done
                MOV     CS:[SI + m32_ch_sustain_cc64], CL
                JMP     SHORT cc_emit
cc_check_anoff: CMP     CH, 7BH                 ; CC#123 = all notes off?
                JNE     SHORT cc_done
                CMP     BYTE PTR CS:[SI + m32_ch_sustain_pedal], 0
                JE      SHORT cc_done
                MOV     BYTE PTR CS:[SI + m32_ch_sustain_pedal], 0
cc_emit:        MOV     AH, 0B0H                ; MIDI CC status
                CALL    m32_send_midi
cc_done:        POP     SI
                POP     AX
                RET
m32_midi_control_change ENDP

; ----------------------------------------------------------------------------
; 0x0715  --  m32_midi_program_change  (slot 8)
;
;   The MIDI "program change" message. Updates the channel's program
;   number and replays the cached "patch" tables so the MT-32 knows
;   which timbre to use.
;
;   Type:        Slot handler
;   Category:    MIDI dispatch
;   Dispatch:    Slot 8 (called as: BP=8, AL=channel, CL=program)
;
;   Inputs:
;     AL  --  MIDI channel (0..15). Channel 9 (drums) ignores program
;             changes (drums always use the MT-32's "rhythm part").
;     CL  --  program number (0..127)
;
;   Outputs:     none
;
;   Side effects:
;     m32_ch_program[ch] <- program (if different)
;     m32_ch_program_lo[ch] <- m32_patch_table_0[program]
;     m32_ch_transpose[ch]  <- m32_patch_table_1[program]
;     m32_ch_patch_hi[ch]   <- m32_patch_table_2[program]
;     m32_ch_patch_extra[ch] <- m32_patch_table_4[program]
;     If new program_lo is 0xFF: emit CC#123 (all-notes-off) and CC#64=0
;       (sustain pedal off) on the channel, then bail.
;     If transpose differs from previous: emit CC#123 / CC#64=0.
;     If patch_hi differs from previous OR sustain_pedal stayed clear:
;       call m32_midi_control_change(CH=7) to re-send the channel's
;       volume, then emit MIDI 0xC0+ch <program> via m32_send_midi.
;
;   Notes:
;     The internal CALL to m32_midi_control_change (with CH=7) at
;     offset 0x07AD is the only non-game caller of slot 7's handler.
; ----------------------------------------------------------------------------
m32_midi_program_change PROC NEAR
                PUSH    AX
                PUSH    SI
                PUSH    CX
                PUSH    BX
                CMP     AL, 9                   ; drums?
                JE      SHORT pc_skip           ; drums never change program
                MOV     SI, AX
                AND     SI, 000FH               ; SI = channel
                CMP     CS:[SI + m32_ch_program], CL
                JE      SHORT pc_skip           ; no-op if program unchanged
                MOV     CS:[SI + m32_ch_program], CL

                ; Look up the four shadow values for this program.
                MOV     SI, CX
                AND     SI, 007FH               ; SI = program & 0x7F
                MOV     CL, CS:[SI + m32_patch_table_0]
                MOV     CH, CS:[SI + m32_patch_table_1]
                MOV     BH, CS:[SI + m32_patch_table_2]
                MOV     BL, CS:[SI + m32_patch_table_4]

                ; Restore SI = channel; store extra and check program_lo.
                MOV     SI, AX
                AND     SI, 000FH
                MOV     CS:[SI + m32_ch_patch_extra], BL
                XOR     BL, BL                  ; BL = "patch reload needed" flag
                CMP     BYTE PTR CS:[SI + m32_ch_program_lo], 0FFH
                JNE     SHORT pc_have_prog
                INC     BL                      ; previously unloaded -> mark reload
pc_have_prog:   MOV     CS:[SI + m32_ch_program_lo], CL
                CMP     CL, 0FFH                ; new value also unloaded?
                JNE     SHORT pc_check_xpose
                MOV     AH, 0B0H
                MOV     CH, 7BH                 ; CC#123 all notes off
                XOR     CL, CL
                CALL    m32_send_midi
                MOV     CH, 40H                 ; CC#64 sustain pedal off
                CALL    m32_send_midi
pc_skip:        JMP     SHORT pc_done
pc_check_xpose: CMP     CH, CS:[SI + m32_ch_transpose]
                JE      SHORT pc_check_hi       ; transpose unchanged
                MOV     CS:[SI + m32_ch_transpose], CH
                PUSH    CX
                MOV     AH, 0B0H
                MOV     CH, 7BH                 ; CC#123 all notes off
                XOR     CL, CL
                CALL    m32_send_midi
                MOV     CH, 40H                 ; CC#64 sustain pedal off
                CALL    m32_send_midi
                POP     CX
                INC     BL                      ; force volume re-emit below
pc_check_hi:    OR      BL, BL
                JNE     SHORT pc_emit_prog      ; reload needed
                CMP     BH, CS:[SI + m32_ch_patch_hi]
                JE      SHORT pc_send_prog      ; no change at all
pc_emit_prog:   MOV     CS:[SI + m32_ch_patch_hi], BH
                PUSH    CX
                MOV     CL, CS:[SI + m32_ch_volume]
                MOV     CH, 7                   ; CC#7 = main volume
                CALL    m32_midi_control_change
                POP     CX
pc_send_prog:   MOV     AH, 0C0H                ; MIDI program-change status
                CALL    m32_send_midi
pc_done:        POP     BX
                POP     CX
                POP     SI
                POP     AX
                RET
m32_midi_program_change ENDP

; ----------------------------------------------------------------------------
; 0x07BB  --  m32_midi_pitch_bend  (slot 10)
;
;   The MIDI "pitch bend" message. Two data bytes are sent (LSB first,
;   then MSB); the driver caches the pair and only re-emits when either
;   byte changes.
;
;   Type:        Slot handler
;   Category:    MIDI dispatch
;   Dispatch:    Slot 10 (called as: BP=10, AL=ch, CL=bend_lo, CH=bend_hi)
;
;   Inputs:
;     AL  --  MIDI channel
;     CL  --  bend LSB (0..127)
;     CH  --  bend MSB (0..127)
;
;   Outputs:     none
; ----------------------------------------------------------------------------
m32_midi_pitch_bend PROC NEAR
                PUSH    AX
                PUSH    SI
                MOV     SI, AX
                AND     SI, 000FH               ; SI = channel
                SHL     SI, 1                   ; word-aligned
                CMP     CS:[SI + m32_ch_pitchbend], CL
                JNE     SHORT pb_update
                CMP     CS:[SI + m32_ch_pitchbend + 1], CH
                JE      SHORT pb_done
pb_update:      MOV     CS:[SI + m32_ch_pitchbend], CL
                MOV     CS:[SI + m32_ch_pitchbend + 1], CH
                MOV     AH, 0E0H                ; MIDI pitch-bend status
                CALL    m32_send_midi
pb_done:        POP     SI
                POP     AX
                RET
m32_midi_pitch_bend ENDP

; ----------------------------------------------------------------------------
; 0x07E4  --  m32_send_midi
;
;   The unified "emit a MIDI message" primitive. Every slot handler that
;   needs to talk to the MT-32 ends up here.
;
;   The MIDI message is built from its status byte (AH | AL = channel-
;   combined high nibble) and one or two data bytes (CH and possibly CL).
;
;   Status-byte categories 0xC0 (program change) and 0xD0 (channel
;   pressure) are 2-byte MIDI messages -- they need only one data byte
;   (CL). All others are 3-byte messages: status, CH, CL.
;
;   Type:        Internal helper
;   Callers:     m32_midi_note_off, m32_midi_note, m32_midi_control_change,
;                m32_midi_program_change, m32_midi_pitch_bend,
;                m32_set_master_enable
;
;   Inputs:
;     AH  --  status high nibble (0x80, 0x90, 0xB0, 0xC0, 0xE0, ...)
;     AL  --  channel (0..15), OR'd into AH to form the status byte
;     CH  --  MIDI data byte 1 (note / cc# / bend_hi / etc.)
;     CL  --  MIDI data byte 2 (vel / cc value / bend_lo / etc.)
;
;   Outputs:     none
;
;   Touches:     DL clobbered; BX, AX, CX preserved across the call by
;                m32_mpu_send_data internally
; ----------------------------------------------------------------------------
m32_send_midi   PROC    NEAR
                PUSH    BX
                MOV     DL, AL
                OR      DL, AH                  ; status byte = AH | channel
                MOV     CS:[m32_last_status], DL
                MOV     BL, DL
                CALL    m32_mpu_send_data       ; emit status byte
                CMP     AH, 0C0H                ; 2-byte (program change)?
                JE      SHORT smid_one_data
                CMP     AH, 0D0H                ; 2-byte (channel pressure)?
                JE      SHORT smid_one_data
                MOV     BL, CH                  ; data 1 (note/cc#/bend_hi)
                CALL    m32_mpu_send_data
smid_one_data:  MOV     BL, CL                  ; data 2 (vel/cc val/bend_lo)
                CALL    m32_mpu_send_data
                POP     BX
                RET
m32_send_midi   ENDP

; ----------------------------------------------------------------------------
; 0x0809  --  m32_reset_voices  (slot 2)
;
;   "Reset / silence" handler. Issues an MPU-401 0xFF (full reset)
;   command. The actual work is delegated to m32_mpu_reset.
;
;   Type:        Slot handler
;   Dispatch:    Slot 2 (called as: BP=2)
;
;   Inputs:      none
;   Outputs:     none
; ----------------------------------------------------------------------------
m32_reset_voices PROC NEAR
                PUSH    BX
                CALL    m32_mpu_reset
                POP     BX
                RET
m32_reset_voices ENDP

; ----------------------------------------------------------------------------
; 0x080F  --  m32_mpu_send_cmd
;
;   Send a single command byte to the MPU-401 command port (0x331).
;   Implements the standard "wait for output-ready, write, wait for ACK"
;   protocol with bounded polling.
;
;   Type:        Internal helper (MPU-401 driver primitive)
;   Callers:     m32_mpu_reset, m32_load_patch_bank
;
;   Inputs:
;     BL  --  command byte to send
;
;   Outputs:     none (best-effort; if the MPU-401 doesn't ACK, we move
;                on after timeout)
;
;   Side effects:
;     - PUSHF/CLI: interrupts are disabled across the protocol
;     - Writes BL to port 0x331
;     - Reads (and discards) data bytes from 0x330 while waiting for ACK
;     - Final read from port 0x330 to consume the ACK byte (0xFE)
; ----------------------------------------------------------------------------
m32_mpu_send_cmd PROC NEAR
                PUSHF
                CLI                             ; no interrupts during MPU I/O
                PUSH    AX
                PUSH    CX
                PUSH    DX
                MOV     CX, 0FFFFH              ; outer timeout
                MOV     DX, 0331H               ; status / command port
msc_wait_rdy:   IN      AL, DX
                TEST    AL, 40H                 ; bit 6 clear = output ready
                JE      SHORT msc_write_cmd
                DEC     CX
                CMP     CX, 0
                JNE     SHORT msc_wait_rdy
                JMP     SHORT msc_done          ; timed out -- bail
msc_write_cmd:  MOV     AL, BL
                OUT     DX, AL                  ; write the command byte
                MOV     CX, 0FFFFH              ; inner timeout for ACK
msc_wait_ack:   IN      AL, DX
                ROL     AL, 1                   ; rotate bit 7 into CF
                JAE     SHORT msc_read_ack      ; CF=0 means high bit was 0
                                                ; = data available
                DEC     CX
                CMP     CX, 0
                JNE     SHORT msc_wait_ack
                ; Fallthrough: even on timeout we drain the data port.
msc_read_ack:   MOV     DX, 0330H               ; data port
                IN      AL, DX
                CMP     AL, 0FEH                ; expect 0xFE ACK
                JE      SHORT msc_done
msc_done:       POP     DX
                POP     CX
                POP     AX
                POPF
                RET
m32_mpu_send_cmd ENDP

; ----------------------------------------------------------------------------
; 0x0845  --  m32_mpu_send_data
;
;   Send a single MIDI data byte to the MPU-401 data port (0x330).
;   Polls the status port (0x331) until the "output ready" flag clears,
;   then writes the data byte.
;
;   Type:        Internal helper (MPU-401 driver primitive)
;   Callers:     m32_send_midi, m32_load_patch_bank
;
;   Inputs:
;     BL  --  MIDI data byte to send
;
;   Outputs:     none
;
;   Side effects:
;     - PUSHF/CLI: interrupts are disabled during the I/O sequence
;     - Polls port 0x331 up to ~255 times waiting for the output-ready bit
;     - Writes BL to port 0x330
;     - If the MPU-401 is reporting "input data available" mid-poll
;       (status bit 7 = 0), drains one byte from port 0x330 and keeps
;       polling
; ----------------------------------------------------------------------------
m32_mpu_send_data PROC NEAR
                PUSHF
                CLI
                PUSH    AX
                PUSH    CX
                PUSH    DX
                MOV     DX, 0331H               ; status port
                MOV     CX, 00FFH               ; bounded poll count
msd_wait:       IN      AL, DX
                TEST    AL, 40H                 ; bit 6 clear = output ready
                JE      SHORT msd_write
                DEC     CX
                ROL     AL, 1                   ; rotate bit 7 into CF
                JB      SHORT msd_loop_test     ; CF=1 means bit 7 was 1
                                                ; (no input pending)
                MOV     DX, 0330H               ; drain one input byte
                IN      AL, DX
                MOV     DX, 0331H               ; restore status-port DX
msd_loop_test:  CMP     CX, 1
                JGE     SHORT msd_wait
                JMP     SHORT msd_done          ; timed out
msd_write:      MOV     DX, 0330H               ; data port
                MOV     AL, BL
                OUT     DX, AL
msd_done:       POP     DX
                POP     CX
                POP     AX
                POPF
                RET
m32_mpu_send_data ENDP

; ----------------------------------------------------------------------------
; 0x0873  --  m32_set_master_volume  (slot 12)
;
;   Sets the global master-volume scalar at 0x04BF. If the driver is
;   currently enabled (m32_master_enable != 0), iterates channels 1..9
;   and re-emits each channel's CC#7 so the new master takes effect
;   immediately.
;
;   Type:        Slot handler
;   Dispatch:    Slot 12 (called as: BP=12, CL=value or 0xFF=query)
;
;   Inputs:
;     CL  --  new value (0..127), or 0xFF = query current value
;
;   Outputs:
;     AX  --  previous master volume (zero-extended)
;
;   Notes:
;     The loop runs AL = 1..9, SI = 1..9 (skipping channel 0). The
;     skip is presumably because channel 0 is reserved / silent in the
;     game's MIDI assignment.
; ----------------------------------------------------------------------------
m32_set_master_volume PROC NEAR
                PUSH    BX
                PUSH    CX
                PUSH    SI
                MOV     AL, CS:[m32_master_volume]
                XOR     AH, AH
                CMP     CL, 0FFH                ; query?
                JE      SHORT smv_done
                MOV     CS:[m32_master_volume], CL
                CMP     BYTE PTR CS:[m32_master_enable], 0
                JE      SHORT smv_done          ; muted -- don't re-emit yet
                PUSH    AX
                MOV     AL, 1                   ; AL = channel index 1..9
                MOV     SI, 1                   ; SI = same as AL
                MOV     CH, 7                   ; CC#7 = main volume
smv_loop:       MOV     CL, CS:[SI + m32_ch_volume]
                CMP     CL, 0FFH                ; no shadow value yet?
                JE      SHORT smv_next
                CALL    m32_midi_control_change
smv_next:       INC     AL
                INC     SI
                CMP     AL, 0AH                 ; stop after channel 9
                JNE     SHORT smv_loop
                POP     AX
smv_done:       POP     SI
                POP     CX
                POP     BX
                RET
m32_set_master_volume ENDP

; ----------------------------------------------------------------------------
; 0x08AF  --  m32_set_master_enable  (slot 13)
;
;   Toggle the global "driver enabled" flag at 0x04C0. When clearing it
;   (CL == 0), explicitly send CC#7 value 0 on channels 1..9 so the
;   MT-32 goes silent; when setting it (CL != 0), re-emit all channel
;   volumes via m32_set_master_volume so the MT-32 picks up the current
;   levels.
;
;   Type:        Slot handler
;   Dispatch:    Slot 13 (called as: BP=13, CL=value or 0xFF=query)
;
;   Inputs:
;     CL  --  new enable state, or 0xFF = query
;
;   Outputs:
;     AL  --  previous master_enable value (with AH=0 because XOR is at
;             top)
; ----------------------------------------------------------------------------
m32_set_master_enable PROC NEAR
                XOR     AH, AH
                MOV     AL, CS:[m32_master_enable]
                CMP     CL, 0FFH                ; query?
                JNE     SHORT sme_set
                RET
sme_set:        PUSH    AX
                PUSH    CX
                CMP     CL, 0
                JNE     SHORT sme_enable
                ; Disable path: silence first, then flip flag.
                MOV     BYTE PTR CS:[m32_master_enable], 0
                MOV     AL, 1                   ; AL = channel 1..9
                MOV     AH, 0B0H                ; MIDI CC status
                MOV     CH, 7                   ; CC#7 = main volume
                MOV     CL, 0                   ; value 0 = silent
sme_disable_loop: CALL  m32_send_midi
                INC     AL
                CMP     AL, 0AH
                JNE     SHORT sme_disable_loop
                POP     CX
                POP     AX
                RET
sme_enable:     MOV     BYTE PTR CS:[m32_master_enable], 1
                MOV     CL, CS:[m32_master_volume]
                CALL    m32_set_master_volume   ; re-emit all channel vols
                POP     CX
                POP     AX
                RET
m32_set_master_enable ENDP

; ----------------------------------------------------------------------------
; 0x08ED  --  m32_mpu_reset
;
;   Issue the MPU-401 0xFF "system reset" command. After this, the
;   MPU-401 returns to its power-on state, from which command 0x3F
;   selects UART mode.
;
;   Type:        Internal helper
;   Callers:     m32_reset_voices (slot 2), m32_load_patch_bank (slot 1)
;
;   Inputs:      none
;   Outputs:     none
; ----------------------------------------------------------------------------
m32_mpu_reset   PROC    NEAR
                PUSH    BX
                MOV     BL, 0FFH                ; 0xFF = MPU-401 reset
                CALL    m32_mpu_send_cmd
                POP     BX
                RET
m32_mpu_reset   ENDP

; ----------------------------------------------------------------------------
; 0x08F5  --  m32_query_state  (slot 17)
;
;   The read-side of the setter ABI. Given (status_high_nibble AH,
;   channel AL, sub-index CH), return the cached shadow value the
;   driver believes it last sent to the MT-32 for that (channel,
;   parameter).
;
;   Type:        Slot handler
;   Dispatch:    Slot 17 (called as: BP=17, AH=status, AL=ch, CH=sub-index)
;
;   Recognized (AH, CH) pairs:
;     0xE0, *      -- pitch bend; returns packed (lsb, msb) as a word,
;                     re-encoded with bit 7 of lsb folded onto bit 7 of msb
;     0xC0, *      -- program change; returns m32_ch_program[ch]
;     0xB0, 0x01   -- CC#1 (modulation)
;     0xB0, 0x07   -- CC#7 (main volume)
;     0xB0, 0x0A   -- CC#10 (pan)
;     0xB0, 0x40   -- CC#64 (sustain pedal)
;     anything else -> AX = 0xFFFF (unknown)
;
;   Outputs:
;     AX  --  the queried value, or 0xFFFF if the query isn't recognized
;
;   Notes:
;     The 0xB0/0x4B case is unhandled (jumps directly to the "0xFFFF
;     fallthrough"); 0x4B is CC#75. Probably "not interesting to the
;     game".
; ----------------------------------------------------------------------------
m32_query_state PROC NEAR
                PUSH    SI
                MOV     SI, AX
                AND     SI, 000FH               ; SI = channel
                CMP     AH, 0E0H                ; pitch bend?
                JNE     SHORT qs_check_cprog
                SHL     SI, 1                   ; word-stride
                MOV     AX, WORD PTR CS:[SI + m32_ch_pitchbend]
                DB      083H, 0F8H, 0FFH        ; CMP AX, 0FFFFH (imm8 sign-extended encoding)
                JE      SHORT qs_done
                XCHG    AH, AL                  ; swap to (lsb in AL, msb in AH)
                SHR     AH, 1                   ; rotate AH bit 0 into CF
                JAE     SHORT qs_skip           ; CF=0: no high bit to fold
                OR      AL, 80H                 ; CF=1: re-fold bit into AL
qs_skip:        JMP     SHORT qs_done
qs_check_cprog: CMP     AH, 0C0H                ; program change?
                JNE     SHORT qs_check_cc
                MOV     AL, CS:[SI + m32_ch_program]
                JMP     SHORT qs_done
qs_check_cc:    CMP     AH, 0B0H                ; CC?
                JNE     SHORT qs_unknown
                CMP     CH, 4BH                 ; CC#75 -- unhandled
                JE      SHORT qs_unknown
                CMP     CH, 1                   ; CC#1?
                JNE     SHORT qs_check_cc7
                MOV     AL, CS:[SI + m32_ch_modulation]
                JMP     SHORT qs_done
qs_check_cc7:   CMP     CH, 7                   ; CC#7?
                JNE     SHORT qs_check_cc10
                MOV     AL, CS:[SI + m32_ch_volume]
                JMP     SHORT qs_done
qs_check_cc10:  CMP     CH, 0AH                 ; CC#10?
                JNE     SHORT qs_check_cc64
                MOV     AL, CS:[SI + m32_ch_pan_cc10]
                JMP     SHORT qs_done
qs_check_cc64:  CMP     CH, 40H                 ; CC#64?
                JNE     SHORT qs_unknown
                MOV     AL, CS:[SI + m32_ch_sustain_cc64]
                JMP     SHORT qs_done
qs_unknown:     MOV     AX, 0FFFFH
qs_done:        POP     SI
                RET
m32_query_state ENDP

; ----------------------------------------------------------------------------
; 0x0961  --  m32_load_patch_bank  (slot 1)
;
;   Upload a Dynamix-format patch bank to the MT-32. The bank consists
;   of:
;     - 1153 bytes of "patch tables" that the driver caches into its
;       in-memory buffer at 0x003A
;     - one byte at bank offset 0x200 (file offset 0x023A) which is
;       the drum-kit ID; written to m32_ch_patch_hi[9]
;     - a length-prefixed SysEx blob (LE u16 length, then that many
;       bytes ending in 0xF7) which is streamed verbatim to the MT-32
;       via the data port. After each 0xF7 (end-of-SysEx) byte, the
;       driver pauses (m32_mpu_delay) for ~30000 dummy reads to let
;       the MT-32 process the command before the next one starts.
;
;   The function also resets the MPU, issues three MPU-401 0x3F (start-
;   uart-mode) commands separated by delays (the MT-32 docs recommend
;   this), then proceeds to copy the bank.
;
;   After streaming the SysEx, m32_set_master_volume is called with
;   CL=0x0C to set the master volume to a default mid-range value.
;
;   Type:        Slot handler
;   Dispatch:    Slot 1 (called as: BP=1, ES:AX = src ptr to bank)
;
;   Inputs:
;     ES:AX  --  far pointer to the start of the patch bank
;
;   Outputs:
;     AX  --  0x0961 (= the address of this function; appears to be a
;             debug "we got here" signature)
;     CX  --  0x0801 (CL=01, CH=08; meaning unknown)
; ----------------------------------------------------------------------------
m32_load_patch_bank PROC NEAR
                PUSH    SI
                CALL    m32_mpu_reset           ; full MPU reset
                MOV     BX, 003FH               ; MPU-401 cmd 0x3F = "UART mode"
                CALL    m32_mpu_send_cmd
                CALL    m32_mpu_delay
                MOV     BX, 003FH
                CALL    m32_mpu_send_cmd
                CALL    m32_mpu_delay
                MOV     BX, 003FH
                CALL    m32_mpu_send_cmd
                CALL    m32_mpu_delay
                CALL    m32_mpu_delay
                MOV     SI, AX                  ; SI = src offset (within ES)
                MOV     DI, 0                   ; DI = dst index into bank buffer
lpb_copy:       MOV     BL, ES:[SI]
                MOV     CS:[DI + m32_patch_table_0], BL
                INC     DI
                INC     SI
                CMP     DI, 0481H               ; 1153 bytes total
                JNE     SHORT lpb_copy

                ; Pull the drum-kit ID out of the bank and stash it.
                MOV     BL, CS:[m32_drum_kit_id]
                MOV     CS:[m32_ch_patch_hi + 9], BL

                ; Read the SysEx length (LE u16) from the source stream.
                MOV     CL, ES:[SI]
                INC     SI
                MOV     CH, ES:[SI]
                INC     SI
                CMP     CX, 0                   ; empty SysEx blob?
                JE      SHORT lpb_finalize
lpb_sysex:      MOV     BL, ES:[SI]
                INC     SI
                CALL    m32_mpu_send_data
                CMP     BL, 0F7H                ; end-of-SysEx?
                JNE     SHORT lpb_next
                CALL    m32_mpu_delay
                CALL    m32_mpu_delay
lpb_next:       LOOP    lpb_sysex
lpb_finalize:   MOV     CL, 0CH                 ; default master volume
                CALL    m32_set_master_volume

                ; Return-value setup: AX=0x0961, CL=01, CH=08.
                MOV     AX, 0961H
                MOV     CL, 01H
                MOV     CH, 08H
                POP     SI
                RET
m32_load_patch_bank ENDP

; ----------------------------------------------------------------------------
; 0x09D1  --  m32_mpu_delay
;
;   Spin for ~30000 dummy IN reads from port 0x331. Used by
;   m32_load_patch_bank between MPU-401 commands and after end-of-
;   SysEx bytes to give the MT-32 time to digest each event.
;
;   Type:        Internal helper
;   Inputs:      none
;   Outputs:     none
; ----------------------------------------------------------------------------
m32_mpu_delay   PROC    NEAR
                PUSH    AX
                PUSH    DX
                PUSH    DI
                MOV     DX, 0331H               ; status port (harmless read)
                MOV     DI, 7500H               ; ~30000 iterations
mdly_loop:      IN      AL, DX
                DEC     DI
                CMP     DI, 0
                JNE     SHORT mdly_loop
                POP     DI
                POP     DX
                POP     AX
                RET
m32_mpu_delay   ENDP

; ----------------------------------------------------------------------------
; 0x09E5  --  m32_get_info  (slot 0)
;
;   The "what driver am I?" descriptor. Returns four bytes packed into
;   AX and CX:
;
;     AH = 0x01    -- driver category (0x01 = "real synthesizer with
;                     hardware-side voice management"?)
;     AL = 0x01    -- minor category
;     CH = 0x0C    -- "max polyphony" hint (12 simultaneous notes,
;                     matching the MT-32's official spec)
;     CL = 0x20    -- ???
;
;   Type:        Slot handler
;   Dispatch:    Slot 0
;
;   Inputs:      none
;   Outputs:     AH=01, AL=01, CH=0C, CL=20
;
;   Notes:
;     The byte values are different per-driver; this is the descriptor
;     the game uses to decide which driver to load and how to budget
;     polyphony.
; ----------------------------------------------------------------------------
m32_get_info    PROC    NEAR
                MOV     AH, 01H
                MOV     AL, 01H
                MOV     CH, 0CH
                MOV     CL, 20H
                RET
m32_get_info    ENDP

; ============================================================================
; Glossary  --  domain terms and protocol details used throughout this file
;
;   This block fleshes out the short acronym table near the top of the
;   file (around line 270). A reader who lands at any function header
;   should be able to come here and resolve every domain-specific term
;   without leaving the file.
;
; --- Hardware ---------------------------------------------------------------
;
;   Roland MT-32
;       A 1987 external multi-timbral synthesizer built around the LA
;       (Linear Arithmetic) synthesis architecture. The box accepts
;       standard MIDI on one DIN-5 cable and produces 9 melodic
;       channels of polyphonic sound plus 1 dedicated rhythm/drum
;       channel. Polyphony is limited to ~32 partials (small notes can
;       use 1 partial, complex timbres can use 4) -- the driver caps
;       advertised polyphony at 12 simultaneous notes in m32_get_info,
;       matching the manufacturer's safe number. Each of the MT-32's
;       9 melodic parts is independently assignable to a MIDI channel
;       and can hold a different timbre.
;
;   MPU-401
;       Roland's MIDI Processing Unit ISA card -- the host-side
;       interface between the PC and the external MIDI device. The
;       card exposes two 8-bit I/O ports at base 0x330 (the factory
;       default and the only address this driver knows about):
;
;           port 0x330  data port    (read/write a single MIDI byte)
;           port 0x331  status/cmd   (status reads, command writes)
;
;       Status port bits relevant to this driver:
;
;           bit 6  (0x40)  "output ready" -- when CLEAR, the host can
;                          write the next byte; when SET, the card is
;                          still digesting the previous byte.
;           bit 7  (0x80)  "input data ready" -- when CLEAR, there is
;                          a byte available to read on the data port.
;
;   MPU-401 UART mode
;       The pass-through mode used by this driver. The card is bootstrapped
;       into UART mode by writing the command 0x3F to port 0x331; from
;       that point on, every byte the host writes to port 0x330 is
;       transmitted out on the MIDI cable verbatim, and every byte the
;       MT-32 sends back is buffered on the data port for the host to
;       read. (The card also has a more elaborate "intelligent mode"
;       that schedules MIDI events autonomously, but this driver does
;       NOT use it -- intelligent mode requires IRQ hookup and
;       per-event timestamping that the game doesn't need.) The
;       0xFE byte returned on the data port after a command write is
;       the MPU-401's "command acknowledged" reply.
;
; --- MIDI wire protocol -----------------------------------------------------
;
;   MIDI channel
;       0..15 (4 bits). Encoded as the low nibble of every "channel
;       voice" status byte. By GM (General MIDI) convention, channel
;       9 (zero-indexed) is the rhythm / drum channel; this driver
;       follows that convention and special-cases AL=9 in note-on,
;       note-off, and program-change handlers.
;
;   MIDI note number
;       0..127 (7 bits). Middle C is 60. The MT-32 ignores notes
;       outside ~12..108 on melodic parts. On the drum channel the
;       note number is a *drum sound selector* (kick, snare, etc.)
;       rather than a pitch, and the MT-32 silently ignores notes
;       outside the kit's installed range.
;
;   MIDI velocity
;       0..127 (7 bits). Note-on with velocity 0 is, per spec, a
;       note-off. The driver still sends 0-velocity note-on through
;       m32_midi_note (rather than re-routing to note-off) and lets
;       the MT-32 apply the spec.
;
;   MIDI status byte
;       The first byte of every MIDI message. High nibble = category,
;       low nibble = channel:
;
;           0x80+ch  note-off            (3-byte: note, velocity)
;           0x90+ch  note-on             (3-byte: note, velocity)
;           0xB0+ch  control change      (3-byte: cc#, value)
;           0xC0+ch  program change      (2-byte: program)
;           0xD0+ch  channel pressure    (2-byte: pressure)
;           0xE0+ch  pitch bend          (3-byte: lsb, msb)
;           0xF0..   system common /     (variable; SysEx framing)
;                    system exclusive
;
;       m32_send_midi inspects the high nibble to decide whether to
;       send one or two data bytes after the status byte.
;
;   MIDI CC (Continuous Controller)
;       A 0xB0+ch message that says "set parameter <cc#> on this
;       channel to <value>". The cc# is itself a 7-bit number.
;
;       FOUR controllers are actively handled by
;       m32_midi_control_change; every other CC# falls through to
;       cc_done silently before the MIDI emit:
;
;           CC#7   main volume      -> m32_ch_volume (+ scaled by
;                                      master_volume / 0x0F before
;                                      forwarding to MT-32)
;           CC#10  pan              -> m32_ch_pan_cc10
;           CC#64  sustain value    -> m32_ch_sustain_cc64
;                  (a 7-bit *value*; 0..63 = off, 64..127 = on; the
;                   driver shadows the value byte verbatim)
;           CC#123 all-notes-off    -> not shadowed; consults
;                                      m32_ch_sustain_pedal (a
;                                      separate single-byte note-active
;                                      latch, NOT the CC#64 value
;                                      shadow) and short-circuits the
;                                      message if no notes are held.
;
;       One additional CC is exposed via slot 17 (m32_query_state)
;       but has no write path:
;
;           CC#1   modulation       -> m32_ch_modulation (always
;                                      returns the default 0xFF; the
;                                      shadow is never updated by this
;                                      driver, so the slot is a
;                                      placeholder wired through the
;                                      query ABI but otherwise inert.
;                                      Likely vestigial from a richer
;                                      M32 driver.)
;
;       Note that CC#11 (expression) is NOT shadowed by this driver.
;
;   MIDI pitch bend
;       A 0xE0+ch message carrying a 14-bit value (CL=lsb, CH=msb,
;       both 7-bit). 0x2000 is the centered ("no bend") value. This
;       driver does not interpret the value; it just shadow-stores the
;       (lsb, msb) pair in m32_ch_pitchbend so slot 17 can answer
;       "what's the channel's current bend?" without round-tripping.
;
;   MIDI program / patch / instrument
;       A program change (0xC0+ch <prog>) selects which timbre the
;       channel plays. The MT-32 holds 128 internal timbres plus 64
;       user-programmable ones; "patch" and "program" are
;       interchangeable terms. This driver wraps the program-change
;       message with cached lookups into four 128-byte tables
;       (m32_patch_table_0..2, _4) that the *bank* supplies, so the
;       game's notion of "program 5" can be remapped on disk per-bank
;       without touching the song data.
;
;   SysEx (System Exclusive)
;       A variable-length MIDI message framed by 0xF0 ("start of
;       SysEx") and 0xF7 ("end of SysEx"), with vendor-specific bytes
;       in between. Used to send data the wire protocol's fixed
;       message types can't express -- in this driver's case, complete
;       instrument-bank uploads to the MT-32 during slot 1.
;
; --- Driver protocol --------------------------------------------------------
;
;   DUDE
;       Dynamix's universal sound-driver container format. Each driver
;       is a flat binary that begins with a 0x37-byte header (two
;       magic dwords, a 'dude' tag, a device-name string, a version
;       string) and is loaded into the game's address space verbatim.
;       The game enters the driver through a fixed-offset trampoline
;       (offset 0x05A7 in this driver) and selects an operation via
;       BP = slot index (0..17). See section "About the DUDE dispatch
;       ABI" at the top of the file.
;
;   Patch-bank upload (slot 1, m32_load_patch_bank)
;       The driver's heaviest operation. The game passes ES:AX -> a
;       Dynamix-format bank file in its address space; the driver
;       does, in order:
;
;         1. Reset the MPU-401 (command 0xFF on port 0x331).
;         2. Boot the MPU-401 into UART mode by issuing command 0x3F
;            three times, each separated by an m32_mpu_delay (~30000
;            dummy port reads). The triple-repeat comes from Roland's
;            MT-32 manual and ensures the card is in UART regardless
;            of its previous state.
;         3. Copy 1153 bytes (0x481) from ES:[AX..AX+0x481) into the
;            driver's in-memory bank buffer at 0x003A. Those 1153
;            bytes are five tables of 128 entries each plus a
;            512-byte drum-velocity table plus a single drum-kit-ID
;            byte plus a trailing pad.
;         4. Stash the drum-kit ID into m32_ch_patch_hi[9] so that
;            future drum-channel note-ons pick it up.
;         5. Read a little-endian u16 SysEx length from ES:[AX+0x481],
;            then stream that many bytes byte-by-byte to the MT-32
;            via m32_mpu_send_data. After every 0xF7 ("end of SysEx")
;            byte the driver pauses for two m32_mpu_delay slices
;            (~60000 dummy reads) so the MT-32 has time to digest
;            each SysEx packet before the next one arrives. Real
;            MT-32 hardware can otherwise drop bytes if its SysEx
;            buffer overflows.
;         6. Reset the master volume to 0x0C (a tame default) so the
;            game starts at a known level.
;
;       The return values (AX=0x0961, CL=01, CH=08) appear to be
;       leftover scratch from the function's prologue, not deliberate
;       outputs; no caller observes them.
;
;   Shadow arrays
;       A bookkeeping technique used throughout the driver: for every
;       per-channel value the driver sends to the MT-32, it keeps a
;       cached copy in CS:-relative memory. Two benefits:
;
;         (a) slot 17 (m32_query_state) answers "what is the current
;             value of X on channel C?" instantly without round-
;             tripping to the MT-32 (which would require turning
;             around the MPU-401 byte pipe and waiting for a SysEx
;             dump response).
;         (b) the redundancy-suppression checks in
;             m32_midi_control_change skip the actual MIDI emit if
;             the new value equals the cached value, sparing the
;             MIDI bus a redundant byte sequence.
;
;       The cost is 16 bytes of RAM per shadowed parameter; cheap
;       even on this driver's tiny memory budget.
;
; --- Miscellaneous ----------------------------------------------------------
;
;   SOA (Struct-Of-Arrays)
;       Storage layout where logically-grouped fields are stored as
;       separate parallel arrays rather than as an array of structs.
;       Example in this driver: m32_ch_program, m32_ch_volume,
;       m32_ch_pan_cc10, etc. are each their own 16-byte array
;       indexed by channel, instead of one 16-entry array of
;       struct-per-channel. SOA is friendlier to byte-stride indexing
;       (each access is one MOV with SI = channel).
;
;   CS-relative
;       Every memory access in this driver uses the CS (Code Segment)
;       register as the implicit base: `CS:[SI + label]`. The .MODEL
;       TINY directive arranges for CS, DS, and SS to all hold the
;       same value at runtime, so the code can put data anywhere in
;       its segment and refer to it via CS: regardless of where it
;       physically sits.
; ============================================================================

                END     _start
