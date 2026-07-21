; ============================================================================
; Sx.SSM.STD.bin -- Dynamix DUDE-format PC-speaker sound driver, v2.00
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
; different code, so the game ships one driver per supported card and picks
; the right one at runtime based on the user's "sound setup" choice.
;
; This file is the driver for the IBM PC's built-in INTERNAL SPEAKER. The
; internal speaker is a tiny piezo / magnetic-coil speaker wired directly to
; the motherboard. It can only produce ONE pitch at a time (no polyphony,
; no envelopes, no timbre control). All this driver does is "play this note"
; and "shut up".
;
; The 18-slot DUDE dispatch ABI (shared across all 14 of BAK's sound
; drivers) is mostly stubbed-out here -- only a handful of slots do
; anything. The driver tracks ONE current note, ONE pitch-bend value, and
; a few enable/volume bits. Because there's no polyphony, MIDI "note on"
; just overrides whatever was playing before.
;
; At 1465 bytes this is the smallest of the 14 drivers, by a wide margin.
; ----------------------------------------------------------------------------

; ----------------------------------------------------------------------------
; About the IBM PC internal speaker
;
; The internal speaker is a single 1-bit output line driven by two pieces of
; motherboard hardware acting together:
;
;   1. PIT (Programmable Interval Timer) channel 2 -- a 16-bit countdown
;      timer fed by a 1.193182 MHz clock. In "mode 3" (square-wave
;      generator) it toggles its output at a programmable frequency.
;
;   2. The "speaker gate" bit on PPI port B (I/O port 0x61, bit 1) --
;      when set, the speaker is driven by PIT channel 2's output. When
;      clear, the speaker is silent. PPI port B bit 0 enables the PIT
;      channel 2 gate input; both bits must be set for sound.
;
; To play a note at frequency F Hz:
;
;   1. Send 0xB6 to port 0x43 (PIT control word):
;        binary 1011 0110 = channel 2, latch lo+hi, mode 3 (square wave),
;        binary mode.
;
;   2. Send the 16-bit divisor (LSB then MSB) to port 0x42:
;        divisor = (PIT_clock_Hz) / F
;        The PIT then toggles its output at F Hz.
;
;   3. Set bits 0 and 1 of port 0x61 to route the PIT output to the
;      speaker.
;
; To stop: clear bits 0 and 1 of port 0x61. (The PIT keeps running but its
; output isn't connected to the speaker any more.)
;
; This driver computes the PIT divisor at note-on time as:
;
;        divisor = 0x144F38 / freq_table[index]
;
; where 0x144F38 = 1,331,000 and the freq table is indexed by
; "(MIDI-note - 24) * 4 + pitchbend_offset". 0x144F38 is NOT the PIT input
; clock -- the real PIT clock is 1,193,182 Hz (= 0x1234DE, derived from
; 14.31818 MHz NTSC subcarrier / 12). The two numbers differ by ~11.5 %,
; so the table entries are NOT raw "Hz for this note": they have the
; 0x144F38 / 1,193,182 = 1.1155 scale baked in, so that the produced PIT
; output lands on the right pitch anyway.
;
; The choice of 0x144F38 is non-canonical -- a typical PC-speaker driver
; would just use the real PIT clock and store true Hz in the table. The
; original authors evidently transcribed someone else's table (or made an
; arithmetic slip) and compensated by adjusting the dividend rather than
; recomputing every entry. Once that scale is applied, the resulting
; tuning still misses equal temperament: empirically, taking entry 0x01EE
; for MIDI 69 (A4 / 440 Hz target) yields divisor 1,331,000 / 494 = 2694,
; and 1,193,182 / 2694 = 442.90 Hz, which is 442.90 / 440 - 1 = ~0.66 %
; sharp (+11.4 cents). Spot-checks at MIDI 48, 60, 72, 84 show the same
; ~0.6-0.7 % sharp / +11-13 cents bias (extremes at MIDI 24 hit ~+25
; cents). Acceptable for a beeper.
;
; Note range: MIDI 24 .. 119 (8 octaves: roughly C1 .. B8). Notes outside
; this range are silently dropped. The table has 4 sub-entries per note,
; selected by the current pitch-bend offset, giving 2-cent pitch-bend
; resolution.
;
; The PIT input clock 1.193182 MHz comes from the original PC's NTSC
; subcarrier (14.318 MHz / 12). It's the same clock that drives the
; system timer interrupt (channel 0) and the DRAM-refresh tick (channel 1);
; we mustn't touch those channels here, only channel 2.
; ----------------------------------------------------------------------------

; ----------------------------------------------------------------------------
; The DUDE dispatch ABI (same across all 14 drivers)
;
; "DUDE" is Dynamix's name for this multi-driver sound-system framework.
; The game calls into each driver through a single 12-byte trampoline that
; dispatches to one of 18 "slots" via a function-pointer table. The slot
; selector arrives in BP.
;
; Game-side caller:
;     BP = slot index (0..17)
;     AL = MIDI channel    (0..15) if slot uses one
;     CL = MIDI data byte 1 (vel, CC value, bend lo)
;     CH = MIDI data byte 2 (note, cc#, bend hi)
;     ES:AX = far ptr to bank (slot 1 only)
;     CALL FAR std_seg:std_dispatch
;
; The dispatch in THIS driver uses DX (not BP) to do the indirect call --
; small difference from the AdLib driver, same effect:
;
;     PUSH DX
;     SHL  BP, 1
;     MOV  DX, CS:[BP + std_func_table]
;     CALL DX
;     POP  DX
;     RETF
;
; Slots in this driver (most are no-ops because the PC speaker has nothing
; to control):
;
;     0   get_info                  - returns driver info (AH/AL/CH/CL)
;     1   load_patch_bank           - no-op (returns canned values)
;     2   reset_voices              - silence the speaker
;     3   (unused -> RET)
;     4   midi_note_off             - silence if matching note
;     5   midi_note                 - play note (or silence if vel=0)
;     6   (unused -> RET)
;     7   midi_control_change       - handles CC#75 (sustain), CC#78
;                                     (legato-trigger), CC#123 (all-off),
;                                     CC#7 (channel volume)
;     8   (unused -> RET)
;     9   (unused -> RET)
;    10   midi_pitch_bend           - sets pitch-bend amount + direction
;    11   set_global_param          - stores CL at [349h] (no audible effect)
;    12   set_master_volume         - stores CL as 0/1 flag
;    13   set_master_enable         - 0 silences, 1 re-enables
;    14   (unused -> RET)
;    15   (unused -> RET)
;    16   (unused -> RET)
;    17   query_state               - reads back various state bytes
; ----------------------------------------------------------------------------

; ----------------------------------------------------------------------------
; How to read this source
;
; - Lines like `MOV BX, AX` are CPU instructions. The first operand is the
;   destination, the second is the source -- read it as "BX = AX". (This is
;   "Intel order"; AT&T order is the opposite.)
;
; - x86 16-bit register reference card (everything you'll see in this file):
;
;     AX, BX, CX, DX  -- 16-bit general-purpose registers. Each splits into
;                        two 8-bit halves: AX = AH:AL (high:low byte), and
;                        likewise BX = BH:BL, CX = CH:CL, DX = DH:DL. The
;                        DUDE ABI packs MIDI data into these halves: AL =
;                        channel, CH = note/cc#, CL = velocity/cc-value.
;     SI, DI          -- 16-bit "index" registers (source / destination).
;                        We use DI here as a scratch 16-bit holding cell
;                        for the divisor lookup; SI is unused.
;     BP              -- 16-bit base-pointer register. The DUDE ABI passes
;                        the slot index in BP.
;     SP              -- stack pointer; managed implicitly by PUSH/POP/CALL.
;     CS, DS, ES, SS  -- 16-bit "segment" registers. Real-mode 8086 needs
;                        these to address >64KB of RAM: a memory access
;                        like `CS:[0x100]` means "byte at (CS*16 + 0x100)".
;                        For this tiny-model driver we always use CS,
;                        because the game loads our code and data into
;                        one shared segment (see next bullet).
;     FLAGS           -- condition bits set by arithmetic / comparison
;                        and consumed by Jxx (JNE, JBE, JC, ...).
;
; - `CS:[addr]` is a memory access using the Code Segment register as the
;   base. This driver is "tiny model" -- the game loads its code + data
;   into one shared segment, so every read/write of state goes through
;   the CS register. (We can't use DS because we don't know what the game
;   has it set to when it calls us.)
;
; - "I/O port" is an 8086 concept distinct from memory. The CPU has two
;   separate address spaces: memory (accessed by MOV) and "I/O" (accessed
;   by IN / OUT). When this driver writes `OUT 43H, AL` it's pulsing a
;   dedicated CPU pin that the PIT chip listens on; the value in AL ends
;   up in the PIT's control register, NOT at memory address 0x43. The
;   four ports this driver touches are:
;     0x42  -- PIT channel 2 counter (latch low byte, then high byte)
;     0x43  -- PIT control register (write the control word here)
;     0x61  -- PPI port B (bits 0 + 1 = speaker gate + drive)
;
; - Numbers ending in `H` are hexadecimal (3FH = 63). Plain numbers are
;   decimal. Numbers that start with a letter need a leading `0` for
;   TASM's parser to tell number-from-identifier (0B6H, not B6H).
;
; - `PROC NEAR ... ENDP` brackets a function. Local labels inside use a
;   short prefix to avoid colliding with labels in other functions.
;
; - Calling convention: slot handlers receive (BP, AL, CL, CH, sometimes
;   ES:AX) and return whatever the slot's contract specifies. Internal
;   helpers pass data in registers -- documented per-helper.
;
; - "PIT" = Programmable Interval Timer (the 8253/8254 chip).
;   "PPI" = Programmable Peripheral Interface (the 8255 chip, port 0x61).
;   "Mode 3" = the PIT's square-wave generator mode.
;   For the full glossary, see the bottom of this file.
; ----------------------------------------------------------------------------


                .8086
                .MODEL  TINY
                .CODE
                ORG     0

_start          LABEL   BYTE

; ============================================================================
; 0x0000  --  DUDE header
; ============================================================================
;
; The header is identical-in-shape across all 14 drivers; only the tag, the
; device-name string, the driver-kind word, and the version string differ.
; The first three bytes are a near JMP to the dispatch trampoline -- so a
; caller can `CALL FAR std_seg:0` after loading, without knowing where the
; trampoline ended up.

                JMP     std_dispatch          ; 3 bytes: E9 6B 03

pad_03          DB      0                     ; alignment to a 4-byte boundary

; "Magic A" -- four-byte signature shared by every DUDE driver.
dude_magic_a    DD      87654321H

; Interface version byte + length-prefix for the tag string below.
; (Other DUDE drivers use length=4 + tag="dude". STD uses length=6 +
; tag="stddrv", presumably to identify this as a "standard" / built-in
; driver.)
dude_iface_ver  DB      1
dude_tag_len    DB      6

; Tag string. The game scans for this to identify drivers in DUDE format.
dude_tag        DB      'stddrv'

; Human-readable device name, as a Pascal string (1-byte length + chars).
; Setup utilities display this to the user.
device_name_len DB      37
device_name     DB      'IBM PC or Compatible Internal Speaker'

; "Magic B" -- four-byte signature ending the header proper.
dude_magic_b    DD      0FEDCBA98H

; Driver kind (?). 1 here; ADL = 2, MT-32 = 0x00020000, GMD = 0x00020000.
dude_driver_kind DD     1

; Version string. ADL is "2.24"; this is "2.00".
driver_ver_str  DB      '2.00'


; ============================================================================
; 0x0042  --  Note-to-frequency lookup table (381 words = 762 bytes)
; ============================================================================
;
;   Indexed by  bx = ((midi_note - 24) * 4) + pitch_bend_offset
;   then shifted left by 1 (so byte index = bx * 2 from this label).
;
;   Each table entry is the "frequency Hz" operand for:
;
;        PIT_divisor = 0x144F38 / table_entry
;
;   The table covers MIDI notes 24..119 (95 full notes + 1 trailing entry
;   for note 119). For each note there are 4 sub-entries selected by the
;   pitch-bend amount (giving roughly 25-cent resolution at +/- max bend).
;   Note 119 is special -- only sub-entry 0 is in the table; sub-entries
;   1..3 would read into the state-variable area below and the driver
;   relies on bend never being applied at that top extreme.
;
;   NOTE: the dividend 0x144F38 = 1,331,000 is NOT the real PIT clock
;   (1,193,182 Hz = 14.31818 MHz / 12); entries here have a 1.1155x
;   scale baked in and the resulting tuning runs ~+11.4 cents sharp at
;   A4. See the hardware primer above for the full derivation.
; ----------------------------------------------------------------------------

std_note_freq_table LABEL WORD
                DW      0025H, 0025H, 0026H, 0026H, 0027H, 0027H, 0028H, 0029H      ; midi 24..25 (~33-35 Hz)
                DW      0029H, 002AH, 002AH, 002BH, 002CH, 002CH, 002DH, 002EH      ; midi 26..27
                DW      002EH, 002FH, 0030H, 0030H, 0031H, 0032H, 0032H, 0033H      ; midi 28..29
                DW      0034H, 0035H, 0035H, 0036H, 0037H, 0038H, 0039H, 0039H      ; midi 30..31
                DW      003AH, 003BH, 003CH, 003DH, 003EH, 003FH, 003FH, 0040H      ; midi 32..33
                DW      0041H, 0042H, 0043H, 0044H, 0045H, 0046H, 0047H, 0048H      ; midi 34..35
                DW      0049H, 004AH, 004CH, 004DH, 004EH, 004FH, 0050H, 0051H      ; midi 36..37 (C2 / 65 Hz)
                DW      0052H, 0054H, 0055H, 0056H, 0057H, 0059H, 005AH, 005BH      ; midi 38..39
                DW      005CH, 005EH, 005FH, 0061H, 0062H, 0063H, 0065H, 0066H      ; midi 40..41
                DW      0068H, 0069H, 006BH, 006CH, 006EH, 0070H, 0071H, 0073H      ; midi 42..43
                DW      0074H, 0076H, 0078H, 007AH, 007BH, 007DH, 007FH, 0081H      ; midi 44..45
                DW      0083H, 0085H, 0087H, 0089H, 008BH, 008DH, 008FH, 0091H      ; midi 46..47
                DW      0093H, 0095H, 0097H, 0099H, 009CH, 009EH, 00A0H, 00A2H      ; midi 48..49 (C3)
                DW      00A5H, 00A7H, 00AAH, 00ACH, 00AFH, 00B1H, 00B4H, 00B6H      ; midi 50..51
                DW      00B9H, 00BCH, 00BEH, 00C1H, 00C4H, 00C7H, 00CAH, 00CDH      ; midi 52..53
                DW      00D0H, 00D3H, 00D6H, 00D9H, 00DCH, 00DFH, 00E2H, 00E6H      ; midi 54..55
                DW      00E9H, 00ECH, 00F0H, 00F3H, 00F7H, 00FAH, 00FEH, 0102H      ; midi 56..57
                DW      0106H, 0109H, 010DH, 0111H, 0115H, 0119H, 011DH, 0121H      ; midi 58..59
                DW      0126H, 012AH, 012EH, 0133H, 0137H, 013CH, 0140H, 0145H      ; midi 60..61 (C4 / middle C)
                DW      014AH, 014EH, 0153H, 0158H, 015DH, 0162H, 0167H, 016DH      ; midi 62..63
                DW      0172H, 0177H, 017DH, 0182H, 0188H, 018EH, 0193H, 0199H      ; midi 64..65
                DW      019FH, 01A5H, 01ABH, 01B2H, 01B8H, 01BEH, 01C5H, 01CBH      ; midi 66..67
                DW      01D2H, 01D9H, 01E0H, 01E7H, 01EEH, 01F5H, 01FCH, 0204H      ; midi 68..69 (A4 / 440 Hz)
                DW      020BH, 0213H, 021BH, 0222H, 022AH, 0232H, 023BH, 0243H      ; midi 70..71
                DW      024BH, 0254H, 025CH, 0265H, 026EH, 0277H, 0280H, 028AH      ; midi 72..73 (C5)
                DW      0293H, 029DH, 02A7H, 02B0H, 02BAH, 02C5H, 02CFH, 02D9H      ; midi 74..75
                DW      02E4H, 02EFH, 02FAH, 0305H, 0310H, 031BH, 0327H, 0333H      ; midi 76..77
                DW      033FH, 034BH, 0357H, 0363H, 0370H, 037DH, 038AH, 0397H      ; midi 78..79
                DW      03A4H, 03B2H, 03C0H, 03CEH, 03DCH, 03EAH, 03F9H, 0407H      ; midi 80..81
                DW      0416H, 0426H, 0435H, 0445H, 0455H, 0465H, 0475H, 0486H      ; midi 82..83
                DW      0497H, 04A8H, 04B9H, 04CBH, 04DCH, 04EFH, 0501H, 0514H      ; midi 84..85 (C6)
                DW      0526H, 053AH, 054DH, 0561H, 0575H, 0589H, 059EH, 05B3H      ; midi 86..87
                DW      05C8H, 05DDH, 05F3H, 0609H, 0620H, 0637H, 064EH, 0665H      ; midi 88..89
                DW      067DH, 0695H, 06AEH, 06C7H, 06E0H, 06FAH, 0714H, 072EH      ; midi 90..91
                DW      0749H, 0764H, 077FH, 079BH, 07B7H, 07D4H, 07F1H, 080FH      ; midi 92..93
                DW      082DH, 084BH, 086AH, 088AH, 08A9H, 08CAH, 08EAH, 090CH      ; midi 94..95
                DW      092DH, 094FH, 0972H, 0995H, 09B9H, 09DDH, 0A02H, 0A27H      ; midi 96..97 (C7)
                DW      0A4DH, 0A73H, 0A9AH, 0AC2H, 0AEAH, 0B12H, 0B3CH, 0B65H      ; midi 98..99
                DW      0B90H, 0BBBH, 0BE7H, 0C13H, 0C40H, 0C6EH, 0C9CH, 0CCBH      ; midi 100..101
                DW      0CFAH, 0D2BH, 0D5CH, 0D8DH, 0DC0H, 0DF3H, 0E27H, 0E5CH      ; midi 102..103
                DW      0E91H, 0EC7H, 0EFFH, 0F36H, 0F6FH, 0FA8H, 0FE3H, 101EH      ; midi 104..105
                DW      105AH, 1097H, 10D5H, 1113H, 1153H, 1193H, 11D5H, 1217H      ; midi 106..107
                DW      125BH, 129FH, 12E4H, 132BH, 1372H, 13BAH, 1404H, 144EH      ; midi 108..109 (C8)
                DW      149AH, 14E7H, 1535H, 1583H, 15D4H, 1625H, 1677H, 16CBH      ; midi 110..111
                DW      1720H, 1776H, 17CDH, 1826H, 1880H, 18DBH, 1938H, 1996H      ; midi 112..113
                DW      19F5H, 1A55H, 1AB8H, 1B1BH, 1B80H, 1BE6H, 1C4EH, 1CB8H      ; midi 114..115
                DW      1D23H, 1D8FH, 1DFDH, 1E6DH, 1EDEH, 1F50H, 1FC6H, 203CH      ; midi 116..117
                DW      20B4H, 212EH, 21AAH, 2226H                                  ; midi 118 (all 4 entries)
                DW      22A6H                                                       ; midi 119 sub-0 only


; ============================================================================
; 0x033C  --  Driver state variables
; ============================================================================

; Raw pitch-bend value (centred at 0x2000, MIDI 14-bit range). Stored as a
; word when slot 10 (pitch_bend) is invoked so slot 17 (query_state) can
; read it back. Initialised to "no bend".
std_pitchbend_raw  DW   2000H

; Two unused / reserved words.
pad_33e         DW      0, 0

; Distilled pitch-bend offset: abs(bend - 0x2000) / 0xAB. The value 0xAB
; (= 171) sets the per-step quantisation: roughly 8192 / 171 ~ 48 steps
; full-bend, matching the 4 sub-entries per note times ~12 semitones of
; in-table reach.
std_pitchbend_amount    DB 0

; Direction flag: 0 = bend down (subtract from base index),
;                 1 = bend up   (add to base index).
std_pitchbend_direction DB 0

; The MIDI note currently being played (0 = "nothing playing", or the
; 7-bit note number 0x18..0x77 if a note is on). Set by midi_note (slot 5)
; and cleared by speaker_off.
std_current_note   DB   0

; Master volume slot. Treated as a boolean by the speaker_play_note path:
; if zero, the speaker isn't turned on. Initialised to 0x0F (probably a
; legacy default-volume value the original tooling expected).
std_master_volume  DB   0FH

; Master enable. 1 = honour note-on; 0 = stay silent.
std_master_enable  DB   1

; CC#7 (channel volume) enable: gated by midi_control_change. 0 = silent,
; 1 = enabled.
std_cc7_enable     DB   0

; Sustain-pedal channel: holds the AL (MIDI-channel) value of the channel
; whose sustain pedal is currently DOWN, or 0xFF if no pedal is held.
std_sustain_pedal_ch    DB 0FFH

; A free-form "global parameter" slot. The driver stores whatever the game
; writes here and reads it back via query_state; nothing else looks at it.
std_global_param_349    DB 0


; ============================================================================
; 0x034A  --  Function dispatch table  (18 NEAR pointers, 36 bytes)
; ============================================================================
;
; Indexed by BP (slot number). Several entries point at the shared 1-byte
; RET stub at std_slot_unused_ret; the rest go to real handlers.
;
; The dispatch trampoline below reads `CS:[BP*2 + std_func_table]` and
; CALLs the result.

std_func_table  LABEL WORD
                DW      std_get_info             ; 0  -- 0x05B0
                DW      std_load_patch_bank      ; 1  -- 0x05A8
                DW      std_reset_voices         ; 2  -- 0x0525
                DW      std_slot_unused_ret      ; 3  -- 0x037A
                DW      std_midi_note_off        ; 4  -- 0x037B
                DW      std_midi_note            ; 5  -- 0x0386
                DW      std_slot_unused_ret      ; 6
                DW      std_midi_control_change  ; 7  -- 0x03A1
                DW      std_slot_unused_ret      ; 8
                DW      std_slot_unused_ret      ; 9
                DW      std_midi_pitch_bend      ; 10 -- 0x0410
                DW      std_set_global_param_349 ; 11 -- 0x0549
                DW      std_set_master_volume    ; 12 -- 0x0529
                DW      std_set_master_enable    ; 13 -- 0x055B
                DW      std_slot_unused_ret      ; 14
                DW      std_slot_unused_ret      ; 15
                DW      std_slot_unused_ret      ; 16
                DW      std_query_state          ; 17 -- 0x057D


; ============================================================================
; 0x036E  --  Dispatch trampoline (12 bytes; JMP from offset 0 lands here)
; ============================================================================

; ----------------------------------------------------------------------------
; 0x036E  --  std_dispatch
;
;   The single entry point. The game calls `CALL FAR std_seg:0` which lands
;   on the JMP at offset 0, which jumps here. BP holds the slot number
;   (0..17); we look up std_func_table[BP] and CALL through it.
;
;   Unlike the AdLib driver (which saves BP), this one saves DX and uses
;   DX for the indirect CALL. Same idea, smaller stack churn for this
;   driver's tighter handlers.
;
;   Type:        Dispatch trampoline (FAR entry point)
;   Category:    DUDE ABI
;   Callers:     game-side code, via `CALL FAR std_seg:0`
;                (the JMP at offset 0 lands here)
;   Callees:     any of the 18 slot handlers in std_func_table (indirect
;                NEAR call through DX)
;
;   Inputs:
;     BP  --  slot index (0..17)
;     AL, CL, CH, ES:AX -- per-slot arguments (see the DUDE dispatch ABI
;                          primer above and each handler's prologue)
;
;   Outputs:
;     varies per slot (see each handler)
;
;   Touches:
;     BP  --  shifted left by 1 in place; not restored before the slot
;             body runs. (The slot handlers don't observe BP.)
;     DX  --  used for the indirect CALL, but PUSHed and POPped here so
;             the caller sees its DX preserved.
;     Other registers as the called slot handler leaves them.
;
;   Side effects:
;     none directly; whatever the called slot handler does.
;
;   Notes:
;     RETF at the bottom returns to the FAR caller. The dispatched slot
;     handler returns to us with a NEAR RET, not RETF.
; ----------------------------------------------------------------------------
std_dispatch    PROC NEAR
                PUSH    DX                      ; preserve caller's DX
                SHL     BP, 1                   ; word-index into table
                MOV     DX, CS:[BP + std_func_table]
                CALL    DX                      ; near indirect call
                POP     DX                      ; restore caller's DX
                RETF                            ; back to game (FAR caller)
std_dispatch    ENDP


; ============================================================================
; 0x037A  --  Slot bodies
; ============================================================================

; ----------------------------------------------------------------------------
; 0x037A  --  std_slot_unused_ret
;
;   One-byte RET stub. Seven slots that have no useful work to do on the
;   PC speaker dispatch here for a no-op return.
;
;   Type:        Shared NEAR RET stub (LABEL NEAR, not PROC -- the
;                following PROC starts at the next address)
;   Category:    DUDE ABI (no-op slot handler)
;   Callers:     slots 3, 6, 8, 9, 14, 15, 16 (via std_func_table)
;   Callees:     none
;
;   Inputs:      ignored
;   Outputs:     ignored
;   Touches:     no register state changed; the slot handler caller (the
;                dispatch trampoline) sees nothing modified except FLAGS.
;
;   Side effects:
;     none
;
;   Notes:
;     Declared as `LABEL NEAR` rather than its own PROC because the same
;     RET byte is shared as the prologue of the next PROC -- the assembler
;     just needs a label to fill std_func_table entries with.
; ----------------------------------------------------------------------------
std_slot_unused_ret LABEL NEAR
                RET                             ; 0xC3


; ----------------------------------------------------------------------------
; 0x037B  --  std_midi_note_off  (slot 4)
;
;   MIDI "note off": if the requested note matches the note we're currently
;   playing, silence the speaker. The slot 5 (note-on) path also calls
;   speaker_off unconditionally before starting a new note, so this slot
;   mainly matters when the game sends explicit note-off rather than
;   note-on-with-velocity-0.
;
;   Type:        Slot handler
;   Category:    MIDI dispatch
;   Dispatch:    Slot 4 (BP=4, AL=channel, CH=note)
;   Callers:     std_func_table[4] -> game via std_dispatch
;   Callees:     std_speaker_off (only on a matching-note hit)
;
;   Inputs:
;     AL  --  MIDI channel (0..15). IGNORED -- there's only one voice,
;             no per-channel state to track.
;     CH  --  MIDI note number to silence
;
;   Outputs:     none
;   Touches:     no caller-visible registers modified.
;
;   Side effects:
;     If CH == [std_current_note], silences the speaker (clears port
;     0x61 bits 0,1 and zeros [std_current_note]).
; ----------------------------------------------------------------------------
std_midi_note_off PROC NEAR
                CMP     CS:[std_current_note], CH
                JNE     SHORT noff_skip
                CALL    std_speaker_off
noff_skip:      RET
std_midi_note_off ENDP


; ----------------------------------------------------------------------------
; 0x0386  --  std_midi_note  (slot 5)
;
;   MIDI "note on", or "note off" if velocity is zero (per MIDI convention).
;   This is the main entry: silence whatever was playing, then start the
;   new note (unless we're muted by master_enable=0 or by a sustain-pedal
;   gate).
;
;   Type:        Slot handler
;   Category:    MIDI dispatch
;   Dispatch:    Slot 5 (BP=5, AL=channel, CH=note, CL=velocity)
;   Callers:     std_func_table[5] -> game via std_dispatch
;   Callees:     std_speaker_off       (always, before retriggering)
;                std_speaker_play_note (when actually starting a note)
;
;   Inputs:
;     AL  --  MIDI channel (0..15). Used only to gate against the
;             sustain-pedal channel: if a different channel is holding
;             its sustain pedal, this note is dropped.
;     CH  --  MIDI note number (0..127)
;     CL  --  MIDI velocity (0 = release; 1..127 = trigger). NOTE: this
;             driver actually checks CH == 0 (not CL == 0) for the
;             "abort" path; velocity is unused in practice.
;
;   Outputs:     none
;   Touches:     all caller registers preserved (BX saved on stack).
;
;   Side effects:
;     Always silences the speaker before retriggering. If the channel
;     gate passes, programs PIT channel 2 and re-enables the speaker
;     for the new note.
;
;   Notes:
;     Monophonic: the previous note (if any) is unconditionally
;     released. There is no voice-stealing logic because there's
;     only one "voice".
; ----------------------------------------------------------------------------
std_midi_note   PROC NEAR
                ; Sustain-pedal gate: if the saved channel-with-pedal-down
                ; matches our channel, we're allowed to play; otherwise
                ; (and the saved channel is 0xFF for "no pedal"), abort.
                CMP     CS:[std_sustain_pedal_ch], AL
                JE      SHORT note_proceed
                RET
note_proceed:   CMP     CH, 0                   ; CH = note 0 means stop too
                JNE     SHORT note_play
                RET
note_play:      PUSH    BX
                MOV     BL, CH                  ; BL = note number
                XOR     BH, BH                  ; zero-extend to 16 bits
                CALL    std_speaker_off         ; silence previous note
                CALL    std_speaker_play_note   ; start new note (BL=note)
                POP     BX
                RET
std_midi_note   ENDP


; ----------------------------------------------------------------------------
; 0x03A1  --  std_midi_control_change  (slot 7)
;
;   MIDI Control Change (CC) handler. The PC speaker can't honour most CCs
;   in any audible way; we only act on a handful that affect mute/play
;   state. All four sub-cases ultimately exit via the shared `cc_done` RET.
;
;   Type:        Slot handler
;   Category:    MIDI dispatch
;   Dispatch:    Slot 7 (BP=7, AL=channel, CH=cc#, CL=value)
;   Callers:     std_func_table[7] -> game via std_dispatch
;   Callees:     std_speaker_off       (every sub-branch that mutes)
;                std_speaker_play_note (CC#78 legato-note path only)
;
;   Inputs:
;     AL  --  MIDI channel (0..15)
;     CH  --  MIDI controller number
;     CL  --  controller value (0..127, or 0xFF for CC#78 "abort")
;
;   Outputs:     none
;   Touches:     BX preserved (PUSHed in CC#78 path); other caller
;                registers preserved.
;
;   Side effects (per controller):
;     CC#0x7B (123, "All notes off"):
;       always silences the speaker.
;     CC#0x4B  (75, sustain pedal):
;       value!=0: silences (unless AL already owns the pedal), then
;                 stores AL in [std_sustain_pedal_ch].
;       value==0: if AL owns the pedal, silences and resets
;                 [std_sustain_pedal_ch] = 0xFF.
;     CC#0x4E  (78, legato note-on):
;       silences and retriggers note CL on the pedal channel; ignored
;       if AL doesn't own the pedal or if CL==0xFF.
;     CC#0x07   (7, channel volume):
;       sets [std_cc7_enable] = 1 for any non-zero value;
;       value==0 silences and clears [std_cc7_enable].
;
;   Recognised controllers:
;     CC#0x7B (123)  -- "All notes off". Always silences the speaker.
;     CC#0x4B  (75)  -- Drives the sustain-pedal-channel register. value=0
;                       silences and clears the pedal; value!=0 silences
;                       and remembers AL as the gating channel.
;     CC#0x4E  (78)  -- Legato/portamento trigger? value=0xFF aborts;
;                       otherwise start playing note CL on the current
;                       pedal channel.
;     CC#0x07   (7)  -- Channel volume. Anything but value=0 sets the
;                       CC7-enable flag to 1; value=0 silences and clears
;                       it.
; ----------------------------------------------------------------------------
std_midi_control_change PROC NEAR
                ; CC#123 ("All notes off")
                CMP     CH, 7BH
                JNE     SHORT cc_4b
                CALL    std_speaker_off
                JMP     SHORT cc_done           ; rel8 (=0x64) to 0x040F

                ; CC#75 (sustain-pedal channel)
cc_4b:          CMP     CH, 4BH
                JNE     SHORT cc_4e
                CMP     CL, 0
                JE      SHORT cc_4b_zero
                ; Non-zero value: assume "pedal pressed". If we're already
                ; bound to this channel, do nothing -- otherwise silence
                ; and remember AL as the new sustain-pedal channel.
                CMP     CS:[std_sustain_pedal_ch], AL
                JE      SHORT cc_done
                CALL    std_speaker_off
                MOV     CS:[std_sustain_pedal_ch], AL
                JMP     SHORT cc_done           ; rel8 to 0x040F
cc_4b_zero:     ; value=0: pedal released. Only act if AL matches the
                ; channel currently holding the pedal; otherwise ignore.
                CMP     CS:[std_sustain_pedal_ch], AL
                JNE     SHORT cc_done
                CALL    std_speaker_off
                MOV     BYTE PTR CS:[std_sustain_pedal_ch], 0FFH
                JMP     SHORT cc_done

                ; CC#78 (legato note?)
cc_4e:          CMP     CH, 4EH
                JNE     SHORT cc_07
                CMP     CL, 0FFH                ; 0xFF = abort
                JE      SHORT cc_done
                CMP     CS:[std_sustain_pedal_ch], AL
                JNE     SHORT cc_done
                PUSH    BX
                MOV     BL, CL                  ; BL = note (in CL here)
                XOR     BH, BH
                CALL    std_speaker_off
                CALL    std_speaker_play_note
                POP     BX
                JMP     SHORT cc_done

                ; CC#7 (channel volume)
cc_07:          CMP     CH, 7
                JNE     SHORT cc_done
                MOV     BYTE PTR CS:[std_cc7_enable], 1
                CMP     CL, 0
                JNE     SHORT cc_done           ; non-zero: enabled, done
                CALL    std_speaker_off
                MOV     BYTE PTR CS:[std_cc7_enable], 0

cc_done:        RET
std_midi_control_change ENDP


; ----------------------------------------------------------------------------
; 0x0410  --  std_midi_pitch_bend  (slot 10)
;
;   MIDI pitch-bend. CH:CL is a 14-bit bend value (centred at 0x2000) sent
;   as two 7-bit MIDI data bytes; we re-pack to a normal 16-bit word, then
;   compute (offset, direction) used by the note-lookup index.
;
;   Type:        Slot handler
;   Category:    MIDI dispatch
;   Dispatch:    Slot 10 (BP=10, AL=channel, CH=bend_msb_7bit,
;                CL=bend_lsb_7bit)
;   Callers:     std_func_table[10] -> game via std_dispatch
;   Callees:     std_speaker_play_note (if a note is currently playing,
;                                       to retune it immediately)
;
;   Inputs:
;     AL  --  MIDI channel (0..15). Bend is ignored unless AL owns the
;             current sustain-pedal channel.
;     CH  --  pitch-bend MSB (7-bit MIDI byte)
;     CL  --  pitch-bend LSB (7-bit MIDI byte)
;
;   Outputs:     none
;   Touches:     all caller registers preserved (AX/BX/CX/DX saved).
;
;   Side effects:
;     [std_pitchbend_raw]      <- packed bend word (16-bit)
;     [std_pitchbend_amount]   <- abs(bend - 0x2000) / 0xAB    (0..47)
;     [std_pitchbend_direction]<- 0 if bend < 0x2000 else 1
;     If a note is currently playing, immediately re-tunes it with the
;     new bend.
;
;   Notes:
;     The MSB/LSB repack at the top is performed twice -- once for the
;     write to [std_pitchbend_raw], once for the local compare against
;     0x2000 -- instead of reloading from memory.
; ----------------------------------------------------------------------------
std_midi_pitch_bend PROC NEAR
                PUSH    AX
                PUSH    BX
                PUSH    CX
                PUSH    DX
                PUSH    CX                      ; save raw CX for later
                ; Repack CH:CL (two 7-bit MIDI bytes) into one 14-bit
                ; binary word. Each MIDI byte uses only bits 0..6.
                ; CH becomes the high 7 bits, CL the low 7. Net effect:
                ;   new_word = ((old_ch & 0x7F) << 7) | (old_cl & 0x7F)
                ; Implemented as a swap + 1-bit shift + carry rotate.
                XCHG    CH, CL                  ; swap MSB and LSB halves
                SHR     CH, 1                   ; CH's top bit out of CL
                JNC     SHORT pb_no_carry
                OR      CL, 80H                 ; set CL bit 7 if needed
pb_no_carry:    MOV     CS:[std_pitchbend_raw], CX
                POP     CX                      ; restore raw CX

                ; Only apply the bend if this MIDI channel happens to be
                ; the one currently holding the sustain pedal (otherwise
                ; we'd retune notes that another channel is sustaining).
                CMP     CS:[std_sustain_pedal_ch], AL
                JNE     SHORT pb_done

                ; Reset the direction flag to "down" pending the sign
                ; test below.
                MOV     BYTE PTR CS:[std_pitchbend_direction], 0
                ; Reload CX as the packed bend value: CH was overwritten
                ; by the XCHG above, so re-pack from [pitchbend_raw].
                MOV     CH, CL                  ; ch = low byte (CL)
                MOV     CL, 0
                SHR     CH, 1                   ; >> 1, carry := old bit0
                JNC     SHORT pb_no_carry2
                MOV     CL, 80H
pb_no_carry2:   CMP     CX, 2000H               ; compare to centre
                JNE     SHORT pb_nonzero
                ; bend == 0x2000: zero offset, both halves clear
                MOV     BYTE PTR CS:[std_pitchbend_amount], 0
                JMP     SHORT pb_apply
pb_nonzero:     JBE     SHORT pb_below          ; bend < 0x2000?
                ; bend > 0x2000: upward bend
                MOV     AX, CX
                SUB     AX, 2000H               ; AX = bend - 0x2000
                MOV     BYTE PTR CS:[std_pitchbend_direction], 1
                JMP     SHORT pb_divide
pb_below:       ; bend < 0x2000: downward bend
                MOV     AX, 2000H
                SUB     AX, CX                  ; AX = 0x2000 - bend
pb_divide:      ; AX is the unsigned magnitude (0..0x2000). Divide by
                ; 0xAB to get the quantised offset in [0, 47].
                MOV     BX, 0ABH                ; divisor = 171
                MOV     DX, 0
                DIV     BX                      ; AX = AX / 0xAB
                MOV     CS:[std_pitchbend_amount], AL

pb_apply:       ; If a note is playing, re-tune it now with the new bend.
                CMP     BYTE PTR CS:[std_current_note], 0
                JE      SHORT pb_done
                MOV     BH, 0
                MOV     BL, CS:[std_current_note]
                CALL    std_speaker_play_note

pb_done:        POP     DX
                POP     CX
                POP     BX
                POP     AX
                RET
std_midi_pitch_bend ENDP


; ----------------------------------------------------------------------------
; 0x0480  --  std_speaker_off
;
;   Silence the speaker, if it's on. Clears bits 0 and 1 of PPI port B
;   (port 0x61), which disconnects PIT channel 2 from the speaker.
;
;   We track "the speaker is on" by `std_current_note != 0`: skipping the
;   OUT when no note is playing avoids unnecessary speaker-bit churn (and
;   the AND/OR sequence would leave a transient wrong state if the OUTs
;   were interrupted).
;
;   Type:        Internal helper
;   Category:    Hardware I/O (PPI port B)
;   Callers:     std_midi_note_off, std_midi_note, std_midi_control_change
;                (CC#7B / CC#4B / CC#4E / CC#7), std_midi_pitch_bend
;                (indirectly via re-trigger), std_reset_voices,
;                std_set_master_volume (value=0 path),
;                std_set_master_enable (value=0 path)
;   Callees:     none
;
;   Inputs:      none (reads [std_current_note] internally)
;   Outputs:     none
;   Touches:     AL preserved (PUSHed/POPped); all other caller registers
;                untouched.
;
;   Side effects:
;     Reads PPI port B (port 0x61), clears bits 0,1, writes it back.
;     Zeros [std_current_note].
;
;   Notes:
;     Bit 0 of 0x61 is the PIT2 "gate" (when 0, PIT channel 2's countdown
;     is held -- but for mode 3 the gate enables output). Bit 1 is the
;     "speaker drive" -- 0 disconnects the speaker from the PIT2 output.
;     Clearing both is the standard PC-speaker-mute sequence.
; ----------------------------------------------------------------------------
std_speaker_off PROC NEAR
                CMP     BYTE PTR CS:[std_current_note], 0
                JE      SHORT spk_off_already
                PUSH    AX
                ; PPI port B (0x61): bit 0 = PIT2 gate, bit 1 = speaker
                ; drive. Mask both off.
                IN      AL, 61H
                AND     AL, 0FCH                ; clear bits 0,1
                OUT     61H, AL
                POP     AX
                MOV     BYTE PTR CS:[std_current_note], 0
spk_off_already: RET
std_speaker_off ENDP


; ----------------------------------------------------------------------------
; 0x0497  --  std_speaker_play_note
;
;   Start playing MIDI note BL. Range-clamped to [0x18, 0x77] (24..119);
;   anything outside that range is silently ignored.
;
;   Computes the PIT channel-2 divisor from the note-frequency table,
;   programs the PIT, and enables the speaker.
;
;   Type:        Internal helper
;   Category:    Hardware I/O (PIT + PPI)
;   Callers:     std_midi_note (slot 5 trigger path),
;                std_midi_control_change (CC#4E legato path),
;                std_midi_pitch_bend (retune-on-bend path)
;   Callees:     std_apply_pitchbend (only if a bend is currently active)
;
;   Inputs:
;     BL  --  MIDI note number (range-checked against [0x18, 0x77])
;
;   Outputs:     none
;   Touches:     BX preserved (PUSHed/POPped). AX, DX, DI clobbered --
;                callers either don't observe them or save them
;                themselves (std_midi_pitch_bend saves AX/DX).
;
;   Side effects:
;     Sets [std_current_note] = BL.
;     Programs the PIT channel-2 control register (port 0x43) and the
;     16-bit divisor (port 0x42, twice).
;     Sets bits 0,1 of PPI port B (port 0x61) to route PIT2 to the speaker.
;     SKIPS the actual hardware writes entirely if any of:
;       - note BL is outside [0x18, 0x77]
;       - the post-bend table index is out of range
;       - [std_master_volume], [std_cc7_enable], or [std_master_enable]
;         is zero
;     ...in which case [std_current_note] is still updated (the speaker
;     just stays silent).
;
;   Notes:
;     The dividend 0x144F38 is loaded as DX:AX = 0x0014:0x4F38 because
;     8086 DIV is a 32-bit-by-16-bit unsigned divide -- the high half
;     of the dividend must be in DX. See the hardware primer above for
;     why 0x144F38 is NOT the PIT clock.
; ----------------------------------------------------------------------------
std_speaker_play_note PROC NEAR
                PUSH    BX
                CMP     BL, 18H                 ; below 24?
                JAE     SHORT play_check_hi
                JMP     SHORT play_skip
play_check_hi:  CMP     BL, 77H                 ; above 119?
                JBE     SHORT play_ok
                JMP     SHORT play_skip
play_ok:        MOV     CS:[std_current_note], BL
                SUB     BL, 18H                 ; bl = note - 24
                SHL     BX, 1
                SHL     BX, 1                   ; bx = (note-24)*4 (sub-entry)
                ; Apply pitch-bend if any.
                CMP     BYTE PTR CS:[std_pitchbend_amount], 0
                JE      SHORT play_no_bend
                CALL    std_apply_pitchbend     ; may set BX=FFFF on OOR
play_no_bend:   CMP     BX, 0FFFFH              ; out-of-range marker?
                JNE     SHORT play_idx_ok
                JMP     SHORT play_skip
play_idx_ok:    SHL     BX, 1                   ; bx = bx*2 (byte offset)

                ; Gate the whole "actually make sound" path on three
                ; enable bits all being non-zero: master_volume,
                ; cc7_enable, master_enable. Any zero -> stay silent.
                CMP     BYTE PTR CS:[std_master_volume], 0
                JE      SHORT play_skip
                CMP     BYTE PTR CS:[std_cc7_enable], 0
                JE      SHORT play_skip
                CMP     BYTE PTR CS:[std_master_enable], 0
                JE      SHORT play_skip

                ; Program PIT channel 2: control word 0xB6 = channel 2,
                ; latch lo+hi, mode 3 (square wave), binary.
                MOV     AL, 0B6H
                OUT     43H, AL
                ; Compute divisor = 0x144F38 / freq_table_entry.
                ; DX:AX = 0x0014:0x4F38 = the magic dividend.
                MOV     DX, 14H
                MOV     AX, 4F38H
                MOV     DI, CS:[BX + std_note_freq_table]
                DIV     DI                      ; AX = quotient
                OUT     42H, AL                 ; LSB of divisor
                MOV     AL, AH
                OUT     42H, AL                 ; MSB of divisor

                ; Enable the speaker: set PPI port B bits 0 (PIT2 gate)
                ; and 1 (speaker drive).
                IN      AL, 61H
                OR      AL, 3
                OUT     61H, AL

play_skip:      POP     BX
                RET
std_speaker_play_note ENDP


; ----------------------------------------------------------------------------
; 0x04FD  --  std_apply_pitchbend
;
;   Shift the (note-24)*4 index in BX by the current pitchbend offset,
;   in the appropriate direction. Returns BX = 0xFFFF if the result is
;   outside the table's valid range [0x18, 0x1DC].
;
;   Type:        Internal helper
;   Category:    Pitch arithmetic
;   Callers:     std_speaker_play_note (only when bend != 0)
;   Callees:     none
;
;   Inputs:
;     BX  --  current sub-entry index ((midi_note - 24) * 4)
;             Reads [std_pitchbend_amount] and [std_pitchbend_direction].
;
;   Outputs:
;     BX  --  adjusted index, or 0xFFFF on out-of-range
;
;   Touches:     CX preserved (PUSHed/POPped). All other caller registers
;                untouched.
;
;   Side effects:
;     none (pure register transform; doesn't program hardware)
;
;   Notes:
;     The "[0x18, 0x1DC]" range is in WORD-index units, i.e.
;     ((midi_note - 24) * 4) -- BX is shifted to a byte offset by the
;     caller AFTER this helper returns.
; ----------------------------------------------------------------------------
std_apply_pitchbend PROC NEAR
                PUSH    CX
                MOV     CH, 0
                MOV     CL, CS:[std_pitchbend_amount]
                CMP     BYTE PTR CS:[std_pitchbend_direction], 0
                JE      SHORT pb_down
                ADD     BX, CX                  ; bend up
                JMP     SHORT pb_check
pb_down:        SUB     BX, CX                  ; bend down
pb_check:       CMP     BX, 18H
                JB      SHORT pb_oor
                CMP     BX, 1DCH
                JA      SHORT pb_oor
                JMP     SHORT pb_ret
pb_oor:         MOV     BX, 0FFFFH
pb_ret:         POP     CX
                RET
std_apply_pitchbend ENDP


; ----------------------------------------------------------------------------
; 0x0525  --  std_reset_voices  (slot 2)
;
;   Stop the currently playing note. The DUDE ABI calls this on driver
;   init / shutdown / song change.
;
;   Type:        Slot handler
;   Category:    Global state
;   Dispatch:    Slot 2 (BP=2, args ignored)
;   Callers:     std_func_table[2] -> game via std_dispatch
;   Callees:     std_speaker_off
;
;   Inputs:      none
;   Outputs:     none
;   Touches:     same as std_speaker_off (AL preserved)
;
;   Side effects:
;     Silences the speaker (clears port 0x61 bits 0,1; zeros
;     [std_current_note]).
; ----------------------------------------------------------------------------
std_reset_voices PROC NEAR
                CALL    std_speaker_off
                RET
std_reset_voices ENDP


; ----------------------------------------------------------------------------
; 0x0529  --  std_set_master_volume  (slot 12)
;
;   Set or query the master-volume flag. CL=0xFF means "query only",
;   any other CL value is stored (after coercing to 0 or 1).
;
;   Type:        Slot handler
;   Category:    Global state
;   Dispatch:    Slot 12 (BP=12, AL ignored, CL=value-or-0xFF)
;   Callers:     std_func_table[12] -> game via std_dispatch
;   Callees:     std_speaker_off (only on store-zero path)
;
;   Inputs:
;     CL  --  0xFF to query without modifying, or a new value to store
;             (zero/non-zero is the only meaningful distinction)
;
;   Outputs:
;     AX  --  previous [std_master_volume], coerced to 0 or 1
;
;   Touches:     no other caller registers modified.
;
;   Side effects:
;     If CL != 0xFF, writes CL to [std_master_volume]. If CL == 0,
;     additionally silences the speaker.
; ----------------------------------------------------------------------------
std_set_master_volume PROC NEAR
                MOV     AL, CS:[std_master_volume]
                XOR     AH, AH                  ; AX = previous value
                CMP     AL, 0                   ; coerce return to 0/1
                JE      SHORT smv_ret_zero
                MOV     AL, 1
smv_ret_zero:   CMP     CL, 0FFH                ; query only?
                JNE     SHORT smv_store
                RET
smv_store:      MOV     CS:[std_master_volume], CL
                CMP     CL, 0
                JNE     SHORT smv_done
                CALL    std_speaker_off
smv_done:       RET
std_set_master_volume ENDP


; ----------------------------------------------------------------------------
; 0x0549  --  std_set_global_param_349  (slot 11)
;
;   Store / query the byte at [std_global_param_349]. Nothing else in this
;   driver reads it; the slot exists for symmetry with the other drivers.
;
;   Type:        Slot handler
;   Category:    Global state (vestigial)
;   Dispatch:    Slot 11 (BP=11, CL=value-or-0xFF)
;   Callers:     std_func_table[11] -> game via std_dispatch
;   Callees:     none
;
;   Inputs:
;     CL  --  0xFF to query without modifying, or a new value to store
;
;   Outputs:
;     AX  --  previous [std_global_param_349], zero-extended
;
;   Touches:     no other caller registers modified.
;
;   Side effects:
;     If CL != 0xFF, writes CL to [std_global_param_349]. No audible
;     effect -- nothing else in this driver reads that byte.
;
;   Notes:
;     Slot exists for cross-driver ABI symmetry. The handler is the
;     only thing that touches [std_global_param_349], so the byte
;     functions as a tiny write/read scratch register accessible to
;     the game but with no in-driver meaning.
; ----------------------------------------------------------------------------
std_set_global_param_349 PROC NEAR
                MOV     AL, CS:[std_global_param_349]
                XOR     AH, AH
                CMP     CL, 0FFH
                JNE     SHORT sgp_store
                RET
sgp_store:      MOV     CS:[std_global_param_349], CL
                RET
std_set_global_param_349 ENDP


; ----------------------------------------------------------------------------
; 0x055B  --  std_set_master_enable  (slot 13)
;
;   Master-enable: 0 silences the speaker, 1 re-enables future notes.
;   Same query convention (CL=0xFF) as master_volume above.
;
;   Type:        Slot handler
;   Category:    Global state
;   Dispatch:    Slot 13 (BP=13, CL=value-or-0xFF)
;   Callers:     std_func_table[13] -> game via std_dispatch
;   Callees:     std_speaker_off (only on store-zero path)
;
;   Inputs:
;     CL  --  0xFF to query without modifying, 0 to silence + disable,
;             non-zero to enable
;
;   Outputs:
;     AX  --  previous [std_master_enable], zero-extended
;
;   Touches:     no other caller registers modified.
;
;   Side effects:
;     CL == 0:     zeros [std_master_enable] and silences the speaker.
;     CL != 0,0xFF: sets [std_master_enable] = 1.
;     CL == 0xFF:  no state change (query-only).
; ----------------------------------------------------------------------------
std_set_master_enable PROC NEAR
                MOV     AL, CS:[std_master_enable]
                XOR     AH, AH
                CMP     CL, 0FFH
                JNE     SHORT sme_store
                RET
sme_store:      CMP     CL, 0
                JNE     SHORT sme_set
                ; CL = 0: clear flag, silence
                MOV     BYTE PTR CS:[std_master_enable], 0
                CALL    std_speaker_off
                RET
sme_set:        MOV     BYTE PTR CS:[std_master_enable], 1
                RET
std_set_master_enable ENDP


; ----------------------------------------------------------------------------
; 0x057D  --  std_query_state  (slot 17)
;
;   Read back various pieces of driver state. The query is identified by
;   (AH = class, CH = sub-id, CL = sub-id-2).
;
;   Type:        Slot handler
;   Category:    Global state (query)
;   Dispatch:    Slot 17 (BP=17, AL/AH/CH/CL select what to return)
;   Callers:     std_func_table[17] -> game via std_dispatch
;   Callees:     none
;
;   Inputs:
;     AH  --  query class
;     AL  --  per-class argument (e.g. MIDI channel for the pedal query)
;     CH  --  query sub-id
;     CL  --  query sub-id-2
;
;   Outputs:
;     AX  --  the queried value, or 0xFFFF if the (AH, CH, CL) tuple is
;             not recognised
;
;   Touches:     no other caller registers modified.
;
;   Side effects:
;     none (pure read).
;
;   Currently recognised:
;     AH = 0xE0           -> return raw pitch-bend word [std_pitchbend_raw]
;     AH = 0xB0, CH = 0x4B, CL = 0xFF
;                         -> return 1 if AL == sustain_pedal_channel,
;                            else 0
;     anything else       -> return 0xFFFF
; ----------------------------------------------------------------------------
std_query_state PROC NEAR
                CMP     AH, 0E0H
                JNE     SHORT qry_pedal
                MOV     AX, CS:[std_pitchbend_raw]
                RET
qry_pedal:      CMP     AH, 0B0H
                JNE     SHORT qry_unknown
                CMP     CH, 4BH
                JNE     SHORT qry_unknown
                CMP     CL, 0FFH
                JNE     SHORT qry_unknown
                CMP     AL, CS:[std_sustain_pedal_ch]
                JNE     SHORT qry_pedal_no
                MOV     AX, 1
                RET
qry_pedal_no:   XOR     AX, AX
                RET
qry_unknown:    MOV     AX, 0FFFFH
                RET
std_query_state ENDP


; ----------------------------------------------------------------------------
; 0x05A8  --  std_load_patch_bank  (slot 1)
;
;   The PC speaker has no patches to load -- one square wave is all you
;   get. The slot still exists for ABI symmetry. The returned values look
;   like a status pair (AX = pointer / cookie? CL=0, CH=15).
;
;   Type:        Slot handler
;   Category:    DUDE ABI (stub)
;   Dispatch:    Slot 1 (BP=1; ES:AX = bank far-pointer per ABI, ignored)
;   Callers:     std_func_table[1] -> game via std_dispatch
;   Callees:     none
;
;   Inputs:      ignored (ES:AX bank pointer is discarded -- there's
;                nothing to load)
;
;   Outputs:
;     AX  --  0x05A8 (this handler's own offset; appears to be a "status
;             OK" cookie the game checks)
;     CL  --  0 (??)
;     CH  --  0x0F (15) (??)
;
;   Touches:     AX, CL, CH overwritten as part of the return contract.
;
;   Side effects:
;     none (no state mutated, no hardware touched).
; ----------------------------------------------------------------------------
std_load_patch_bank PROC NEAR
                MOV     AX, 5A8H                ; this function's address
                MOV     CL, 0
                MOV     CH, 0FH
                RET
std_load_patch_bank ENDP


; ----------------------------------------------------------------------------
; 0x05B0  --  std_get_info  (slot 0)
;
;   Driver capability/identity probe. Returns a fixed set of bytes that
;   advertise: AH=1 (driver category), AL=0xFF (?), CH=18 (max slot
;   index), CL=1 (driver version major?).
;
;   Type:        Slot handler
;   Category:    DUDE ABI (probe)
;   Dispatch:    Slot 0 (BP=0; no other arguments)
;   Callers:     std_func_table[0] -> game via std_dispatch
;   Callees:     none
;
;   Inputs:      none
;
;   Outputs:
;     AH  --  1     (driver category -- PC-speaker-class)
;     AL  --  0xFF  (capability bitmask? meaning unconfirmed)
;     CH  --  0x12  (18 -- max slot index supported)
;     CL  --  1     (driver-version-major? matches the "1" in
;                    dude_iface_ver above)
;
;   Touches:     no other caller registers modified.
;
;   Side effects:
;     none (no state mutated, no hardware touched).
; ----------------------------------------------------------------------------
std_get_info    PROC NEAR
                MOV     AH, 1
                MOV     AL, 0FFH
                MOV     CH, 12H
                MOV     CL, 1
                RET
std_get_info    ENDP


; ============================================================================
; 11. GLOSSARY
; ============================================================================
;
; Every acronym and bit of jargon this file uses, in one place. Sorted
; loosely from "thing the file talks about most" outward.
;
; --- Hardware ---
;
; PC speaker
;     The small piezo / magnetic-coil speaker built into every IBM PC and
;     PC-compatible motherboard from the original 5150 onward. It is a
;     1-bit DAC: the only thing the CPU can do with it is toggle its
;     output between "pushed out" and "pulled in". To produce a TONE,
;     the CPU has to toggle that bit at the desired frequency -- which
;     in practice means letting a hardware timer do it for you. See
;     "square-wave trick" below.
;
; PIT  (Programmable Interval Timer)
;     The Intel 8253 chip (replaced by the upward-compatible 8254 in
;     later PCs) that lives on the motherboard. It contains THREE
;     independent 16-bit countdown timers ("channels"), all clocked
;     from the same 1.193182 MHz input clock derived from the NTSC
;     subcarrier (14.31818 MHz / 12). The channels are:
;
;       Channel 0  -- system timer tick (~18.2 Hz IRQ0). DO NOT TOUCH.
;       Channel 1  -- DRAM refresh request line.         DO NOT TOUCH.
;       Channel 2  -- gated to the speaker.              This driver.
;
;     Each channel has its own counter at I/O ports 0x40 (ch0), 0x41
;     (ch1), 0x42 (ch2). The shared control register is at port 0x43.
;
; PIT channel 2 register layout (the only one this driver programs):
;
;       Port 0x43 (write-only control register):
;         A "control word" byte selects the channel + mode + access
;         pattern + radix. For this driver we always send 0xB6:
;
;             bits 7-6: 10 = "this control word configures channel 2"
;             bits 5-4: 11 = "I will write the low byte then the high
;                              byte of the divisor in two sequential
;                              OUTs to the channel's data port"
;             bits 3-1: 011 = "mode 3 = square-wave generator"
;             bit 0:    0  = "binary, not BCD"
;
;       Port 0x42 (channel-2 data, two-byte access):
;         After the control-word write above, the next two writes set
;         the 16-bit divisor: divisor LSB first, then divisor MSB. The
;         PIT divides its 1.193182 MHz input clock by this divisor and
;         toggles its OUT line at the resulting frequency.
;
;     "Mode 3 = square-wave generator" means the PIT's output line
;     spends roughly half the divisor cycles high and half low (50%
;     duty cycle), inverting on every (divisor/2) input clocks. That
;     square wave is what drives the speaker -- see next entry.
;
; PPI  (Programmable Peripheral Interface)
;     The Intel 8255 chip on the original PC's motherboard. It exposes
;     three 8-bit parallel ports (A, B, C) at I/O ports 0x60-0x62. We
;     only care about port B.
;
; Port 0x61 (PPI port B):
;     Eight bits' worth of miscellaneous on-motherboard signals. The
;     two we touch are bit 0 and bit 1:
;
;       bit 0  -- PIT channel 2 GATE. When 1, PIT channel 2's counter
;                 is allowed to run (in mode 3, the gate must be high
;                 for the channel to output its square wave).
;       bit 1  -- "Speaker drive" enable. When 1, PIT channel 2's
;                 OUT line is routed to the speaker. When 0, the
;                 speaker is disconnected (silent) regardless of what
;                 the PIT is doing.
;
;     Both bits must be 1 simultaneously for sound to come out. To
;     mute the speaker we clear both. The other six bits of port 0x61
;     control unrelated things (parity-check enable, keyboard clock
;     line, etc.); we MUST preserve them, which is why this driver
;     reads port 0x61, masks bits 0,1, and writes it back rather than
;     just writing a fresh byte.
;
; I/O port
;     A second address space on x86 distinct from memory. The IN
;     instruction reads a byte (or word) from a port; OUT writes one.
;     Ports are wired to peripheral chips, not RAM. There are 64K of
;     them on the 8086.
;
; --- The square-wave-as-tone trick ---
;
;     The PC speaker is binary: it can only be pushed out or pulled in.
;     To make it produce a pitch at frequency F Hz, we have to flip its
;     drive bit 2*F times per second (once for each transition of a
;     square wave at F). Doing that from software would require an
;     interrupt at 2*F Hz, which gets unreasonable above a few kilohertz.
;
;     Instead, the PIT channel-2 trick: program PIT channel 2 in mode 3
;     to oscillate at F Hz, route its output to the speaker via PPI
;     port B bit 1, and let the chip do the toggling. The PIT runs
;     entirely in hardware; the CPU is free to do other work. To stop
;     the note, clear PPI port B bits 0,1 -- the speaker disconnects
;     and the PIT keeps running but is no longer audible.
;
;     The reason this driver doesn't try to play SAMPLED sounds (PCM
;     wave data) is that doing so on a 1-bit speaker requires PDM
;     (pulse-density modulation) -- driving the speaker bit at very
;     high frequency with carefully timed pulses so that the time-
;     average roughly approximates the analog waveform. PDM was used
;     by some games of the era (Access's Wolfenstein 3D digitised
;     sound, the Future Crew speaker driver, etc.) but it requires
;     tight CPU-bound timing loops and produces a buzzy, low-fidelity
;     output. The DUDE/Krondor PC-speaker driver doesn't bother --
;     it only plays tonal music via the square-wave trick.
;
; --- MIDI ---
;
; MIDI
;     Musical Instrument Digital Interface. The 1983 industry-standard
;     protocol for representing musical-performance events as small
;     binary messages. The game's music data is a stream of MIDI
;     events; each driver translates those events into its target
;     sound chip's native language.
;
; MIDI channel (0..15)
;     16 logical "instrument slots". In a multi-timbral driver each
;     channel maps to its own patch/voice; in this PC-speaker driver
;     channels are mostly ignored because we only have one voice.
;
; MIDI note number (0..127)
;     The pitch, semitones above C-1. Middle C is 60. A4 (440 Hz) is
;     69. Each unit step is one semitone (an equal-tempered twelfth-
;     of-an-octave). This driver covers MIDI 24..119 (~33 Hz to
;     ~16 kHz); notes outside that range are dropped.
;
; MIDI velocity (0..127)
;     "How hard the key was struck". By convention, velocity 0 means
;     "note off" (a release rather than an attack). Velocity is
;     largely ignored by this driver (the PC speaker has no dynamic
;     range).
;
; MIDI CC  (Control Change)
;     Auxiliary parameter updates. Each MIDI channel has 128
;     "controllers" (CC#0..CC#127). The ones this driver recognises
;     are CC#7 (channel volume), CC#75 (custom: sustain-pedal channel
;     binder), CC#78 (custom: legato trigger), and CC#123 (All Notes
;     Off). The "custom" ones are Dynamix's own use of MIDI's vendor-
;     defined CC range, not standard MIDI semantics.
;
; MIDI pitch bend
;     A continuous 14-bit value centred at 0x2000 that shifts the
;     channel's notes up or down by some implementation-defined
;     amount. Transmitted as two 7-bit MIDI data bytes (LSB then MSB).
;     This driver quantises the bend to one of 49 steps (0..48,
;     covering up to ~+/-12 semitones depending on table coverage).
;
; --- DUDE ABI ---
;
; DUDE
;     Dynamix's name for this multi-driver sound system. A DUDE driver
;     is a flat blob of code+data with a fixed-shape header followed
;     by a 12-byte dispatch trampoline. The game calls into the driver
;     via a single FAR entry point (offset 0) and demultiplexes to one
;     of 18 "slots" using the slot number in BP.
;
; slot
;     A named entry point in the DUDE ABI. There are 18 of them
;     (indices 0..17). Each slot has a fixed register-argument
;     convention and a fixed semantic role (get-info, load-bank,
;     reset, note-off, note-on, ...). Slots that don't apply to the
;     PC speaker are stubbed out as no-op RETs.
;
; --- Pitch arithmetic for this driver ---
;
; Divisor
;     In the PIT context (NOT arithmetic), the 16-bit countdown value
;     that PIT channel 2 reloads each cycle. Output frequency =
;     1,193,182 / divisor. Used here to set the pitch of the speaker
;     tone.
;
; Pitch-bend offset (std_pitchbend_amount)
;     Quantised distance from the centred-bend value 0x2000, computed
;     as abs(bend - 0x2000) / 0xAB. Range 0..48. Used as a signed
;     offset added to the (note-24)*4 table index, in the direction
;     given by std_pitchbend_direction.
;
; 0x2000 ("centre value" for pitch bend)
;     The 14-bit MIDI pitch-bend midpoint = "no bend". Values below
;     0x2000 mean "bend down", above mean "bend up".
;
; Sustain-pedal channel
;     This driver's idiosyncratic notion: CC#75 designates ONE MIDI
;     channel as the "channel allowed to play notes right now"; the
;     others are gated off. CC#78 issues a note-on on whichever
;     channel currently owns the pedal. Used by the game's music
;     engine to route monophonic playback through a chosen channel.
;
; --- Memory model ---
;
; near
;     A 16-bit code or data offset, relative to a segment register.
;     A "near" CALL or JMP only changes IP, not CS.
;
; far
;     A 32-bit segment:offset code or data pointer. A "far" CALL
;     changes both CS and IP and is returned to with RETF (which
;     pops both). The DUDE entry point is far so the game can call
;     us regardless of where we were loaded in memory.
;
; CS-relative
;     A memory access that adds the value of the CS (code segment)
;     register to the offset. Used throughout this driver because we
;     keep both code and data in the same segment (tiny model).
;
; tiny model
;     A Borland / DOS memory-model name for "one segment holds code,
;     data, and stack". Maximum program size 64 KB (1 segment); all
;     pointers can be 16-bit "near" offsets.
;
; ============================================================================

                END     _start
