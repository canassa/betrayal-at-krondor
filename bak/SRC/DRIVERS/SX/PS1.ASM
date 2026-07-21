; ============================================================================
; Sx.SSM.PS1.bin -- Dynamix DUDE-format IBM PS/1 Audio/Joystick Card driver,
;                   v2.10
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
; This file is the IBM PS/1 Audio/Joystick Card driver. The PS/1 audio
; card is a 1990 ISA card built around a Texas Instruments SN76496-style
; PSG (Programmable Sound Generator) plus an 8-bit DAC, sharing I/O space
; with the joystick interface. The driver talks to the PSG only; the DAC
; is unused by the in-game music engine.
;
; The game communicates with this driver through a tiny dispatch ABI (see
; "About the DUDE dispatch ABI" below): one entry point at offset 0x07BD,
; eighteen "slots", each slot a different request like "play this note"
; or "change this controller". When a slot is invoked, this code
; translates the MIDI-style request into the specific byte sequences the
; SN76496 PSG understands.
;
; This driver is much smaller than the OPL-based AdLib driver (4 KB vs.
; 9 KB) because the PS/1 PSG only has three tone voices (plus one noise
; channel that this driver doesn't use), so the voice-management state
; arrays are three entries instead of nine, and there are no per-operator
; tables (the PSG has no operators -- each tone channel is just a square
; wave with a 10-bit pitch divisor and a 4-bit attenuation).
; ----------------------------------------------------------------------------

; ----------------------------------------------------------------------------
; About the IBM PS/1 Audio Card (1990) and its SN76496-style PSG
;
; The IBM PS/1 Audio/Joystick Card was a low-cost ISA add-in card shipped
; with IBM's PS/1 line of home PCs. It contains:
;
;   * A Texas Instruments SN76496-style PSG (Programmable Sound Generator)
;     with 4 channels: 3 square-wave tone channels plus 1 noise channel.
;   * An 8-bit unsigned DAC for raw PCM playback, timed by interrupts.
;   * A joystick / paddle interface.
;
; This driver uses only the PSG. The DAC path is unused.
;
; PSG programming model
; ---------------------
;
; The PSG has a single 8-bit data port (this driver writes 0x205). The CPU
; writes ONE byte at a time; the chip latches the byte into a different
; internal register depending on the top bits of the byte:
;
;   Top bit  Bits      Meaning
;   -------  --------  -----------------------------------------------------
;   1        1RRR0XXX  "First byte" of a frequency-low or attenuation
;                      write. RRR is a 3-bit channel/register select:
;                          000  channel 0 tone freq low 4 bits
;                          001  channel 0 attenuation (low 4 bits = value)
;                          010  channel 1 tone freq low 4 bits
;                          011  channel 1 attenuation
;                          100  channel 2 tone freq low 4 bits
;                          101  channel 2 attenuation
;                          110  noise control (low 3 bits)
;                          111  noise attenuation
;                      XXX = low 4 bits of frequency or 4-bit attenuation
;   0        0XXXXXXX  "Second byte": upper 6 bits of frequency for the
;                      last-addressed tone channel. Only valid after a
;                      freq-low first byte; ignored after an attenuation
;                      write.
;
; A single tone-channel frequency change is therefore TWO byte writes:
; first byte (0x80 | (ch*0x20) | low4) then a second byte (high 6 bits).
; The divisor itself is a 10-bit value: tone_freq_hz = clock_hz / (32 *
; divisor).
;
; Attenuation values are 0..15 where 0 is loudest and 15 is silent (the
; PSG attenuates in 2 dB steps, so 15 steps = -30 dB).
;
; What this driver does with the PSG
; ----------------------------------
;
; The 3 tone channels are each assigned to a "voice". A note-on chooses
; an idle voice (or steals via LRU) and writes a frequency word then an
; attenuation byte for that channel. A note-off sets the channel's
; attenuation to 15 (silent). The driver maintains its own LRU queue
; (the SN76496 has no idle-status query) and a per-channel polyphony
; budget that gates note stealing.
; ----------------------------------------------------------------------------

; ----------------------------------------------------------------------------
; About the DUDE dispatch ABI
;
; "DUDE" is Dynamix's internal sound-driver format. Every Dynamix sound
; driver of this generation is a flat binary that begins with a header
; containing two magic numbers (0x87654321 and 0xFEDCBA98), a short
; family-tag string, a human-readable device-name Pascal string, a
; driver-kind integer, and a version tag.
;
; HEADER QUIRK (PS/1 specific): the family-tag length and content differ
; from the AdLib / SoundBlaster / MT-32 drivers. Where ADL has a 4-byte
; 'dude' tag, this driver has a SINGLE-byte tag containing one space
; character. The tag is preceded by a one-byte length field at offset
; 0x09 (value 0x01 in PS/1, 0x04 in ADL/SBP/M32, 0x06 in STD).
;
; The game communicates with this driver in exactly one way: a far call
; into the dispatch trampoline at offset 0x07BD. Before the call, the
; game sets registers:
;
;   BP    = slot index (0..17)
;   AL    = MIDI channel (0..15) for slots that need one
;   CL    = MIDI data byte 1   (velocity / CC value / pitch-bend low)
;   CH    = MIDI data byte 2   (note / CC# / pitch-bend high)
;   ES:AX = far pointer to a patch bank (slot 1 only)
;
; The dispatch trampoline is 12 bytes:
;
;   PUSH DX
;   SHL  BP, 1                       ; index -> byte offset
;   MOV  DX, CS:[BP + ps1_func_table]
;   CALL DX                          ; near call to the slot's handler
;   POP  DX
;   RETF                             ; far return to the game
;
; Note: this PS/1 driver pushes/pops DX rather than BP across the call,
; unlike the ADL driver which pushes/pops BP. Either choice is fine --
; whichever register the slot handlers don't depend on for input.
;
; The 18 slots in this driver, in order:
;
;   Slot  0  ps1_get_info                 -- returns descriptor word
;   Slot  1  ps1_load_patch_bank          -- ES:AX = src; copies into bank
;   Slot  2  ps1_reset_voices             -- silence all + reset PSG
;   Slot  3  ps1_slot3_handler            -- per-voice tick (real body)
;   Slot  4  ps1_midi_note_off            -- AL=ch, CH=note
;   Slot  5  ps1_midi_note                -- AL=ch, CH=note, CL=vel
;   Slot  6  ps1_slot_unused_ret          -- (reserved no-op)
;   Slot  7  ps1_midi_control_change      -- AL=ch, CH=cc, CL=val
;   Slot  8  ps1_midi_program_change      -- AL=ch, CL=program
;   Slot  9  ps1_slot_unused_ret          -- (reserved no-op)
;   Slot 10  ps1_midi_pitch_bend          -- AL=ch, CX=bend (BE-packed)
;   Slot 11  ps1_set_global_param         -- CL=val (0xFF=query)
;   Slot 12  ps1_set_master_volume        -- CL=val (0xFF=query)
;   Slot 13  ps1_set_master_enable        -- CL=val (0xFF=query)
;   Slot 14  ps1_slot_unused_ret          -- (reserved no-op)
;   Slot 15  ps1_slot_unused_ret          -- (reserved no-op)
;   Slot 16  ps1_slot_unused_ret          -- (reserved no-op)
;   Slot 17  ps1_query_state              -- read-side of the setter ABI
;
; PS/1 slot 3 has a real function body at 0x0DC9 (unlike ADL/SBP where
; slot 3 just dispatches to the RET stub). It's the per-voice tick: the
; game calls it from its sequencer interrupt to advance the playback
; cursor inside each voice's currently-active note table.
; ----------------------------------------------------------------------------

; ----------------------------------------------------------------------------
; How to read this source
;
; - Lines like `MOV BX, AX` are CPU instructions. The first operand is
;   the destination, the second is the source -- read it as "BX = AX".
;   This is "Intel" order; AT&T-style "MOV AX, BX" with destination
;   second is a different convention and is not used here.
;
; - Lines like `ps1_voice_note  DB 3 DUP(0FFH)` declare data: the label
;   names this address, `DB` says "the following are bytes", and
;   `3 DUP(0FFH)` means "three copies of the value 0xFF". `DW` is the
;   16-bit equivalent (two bytes per entry, little-endian on x86).
;
; - `CS:[BX + label]` is a memory access using the Code Segment register
;   as the base. In this flat single-segment driver, every read/write
;   uses CS: because the data and code share one segment (the
;   `.MODEL TINY` directive sets that up).
;
; - Every function below begins with `<name> PROC NEAR` and ends with
;   `<name> ENDP`. Inside, labels like `noff_test:` are jump targets
;   local to the function (prefixed with a short nickname so they don't
;   collide with labels in other functions).
;
; - Numbers ending in `H` are hexadecimal (3FH = 63). Plain numbers are
;   decimal. Hex numbers beginning with a letter need a leading `0`
;   (0AH, 0FFH) because TASM uses the first character to distinguish
;   identifiers from numbers.
; ----------------------------------------------------------------------------

; ----------------------------------------------------------------------------
; Glossary of acronyms used in this file (alphabetical)
;
;   CC        MIDI Continuous Controller (e.g. CC#7 = main volume)
;   DAC       Digital-to-Analog Converter (PS/1 has an 8-bit one; unused)
;   DUDE      Dynamix's universal sound-driver container format
;   LRU       Least Recently Used (the voice-allocation policy)
;   PSG       Programmable Sound Generator (the SN76496-style chip)
;   SOA       Struct-Of-Arrays (storage layout where each "field" is its
;             own array indexed by the same index)
;   TI        Texas Instruments (manufacturer of the SN76496 PSG)
; ----------------------------------------------------------------------------


PS1_PORT_DATA   EQU     0205H       ; PSG single data-port (PS/1 base + 5)


                .8086
                .MODEL  TINY
                .CODE
                ORG     0

_start          LABEL   BYTE

; ============================================================================
; 0x0000  --  DUDE header
; ============================================================================

                JMP     ps1_dispatch        ; 3 bytes: E9 BA 07

pad_03          DB      0                   ; alignment to 4-byte boundary

dude_magic_a    DD      87654321H

dude_iface_ver  DB      1
dude_tag_len    DB      1

dude_tag        DB      ' '                 ; single space (PS/1 quirk: ADL
                                            ; uses 'dude', STD uses 'stddrv')

device_name_len DB      28
device_name     DB      'IBM PS/1 Audio/Joystick Card'

dude_magic_b    DD      0FEDCBA98H

dude_driver_kind DD     40H                 ; 0x40 (PS/1); ADL=2, STD=1

driver_ver_str  DB      '2.10'


; ============================================================================
; 0x0034  --  ps1_freq_table  (290 words = 580 bytes)
; ============================================================================
;
;   PSG 10-bit-divisor lookup, indexed by `(midi_note - 0x2D) * 4 + bend`
;   in ps1_psg_write_freq. Each entry is the divisor value written to the PSG
;   as a pair of bytes (low4 + high6). The 4x oversampling per semitone
;   is the bend-resolution mechanism: pitch-bend offsets the table
;   index by [0, 0x1AF] sub-steps.

ps1_freq_table  LABEL WORD
                DW      003F9H, 003EAH, 003DCH, 003CEH, 003C0H, 003B2H, 003A4H, 00397H
                DW      0038AH, 0037DH, 00370H, 00363H, 00357H, 0034BH, 0033FH, 00333H
                DW      00327H, 0031BH, 00310H, 00305H, 002FAH, 002EFH, 002E4H, 002D9H
                DW      002CFH, 002C5H, 002BAH, 002B0H, 002A7H, 0029DH, 00293H, 0028AH
                DW      00280H, 00277H, 0026EH, 00265H, 0025DH, 00254H, 0024BH, 00243H
                DW      0023BH, 00232H, 0022AH, 00222H, 0021BH, 00213H, 0020BH, 00204H
                DW      001FCH, 001F5H, 001EEH, 001E7H, 001E0H, 001D9H, 001D2H, 001CBH
                DW      001C5H, 001BEH, 001B8H, 001B2H, 001ABH, 001A5H, 0019FH, 00199H
                DW      00193H, 0018EH, 00188H, 00182H, 0017DH, 00177H, 00172H, 0016DH
                DW      00167H, 00162H, 0015DH, 00158H, 00153H, 0014EH, 0014AH, 00145H
                DW      00140H, 0013CH, 00137H, 00133H, 0012EH, 0012AH, 00126H, 00121H
                DW      0011DH, 00119H, 00115H, 00111H, 0010DH, 00109H, 00106H, 00102H
                DW      000FEH, 000FAH, 000F7H, 000F3H, 000F0H, 000ECH, 000E9H, 000E6H
                DW      000E2H, 000DFH, 000DCH, 000D9H, 000D6H, 000D3H, 000D0H, 000CDH
                DW      000CAH, 000C7H, 000C4H, 000C1H, 000BEH, 000BCH, 000B9H, 000B6H
                DW      000B4H, 000B1H, 000AFH, 000ACH, 000AAH, 000A7H, 000A5H, 000A2H
                DW      000A0H, 0009EH, 0009CH, 00099H, 00097H, 00095H, 00093H, 00091H
                DW      0008FH, 0008DH, 0008BH, 00089H, 00087H, 00085H, 00083H, 00081H
                DW      0007FH, 0007DH, 0007BH, 0007AH, 00078H, 00076H, 00074H, 00073H
                DW      00071H, 00070H, 0006EH, 0006CH, 0006BH, 00069H, 00068H, 00066H
                DW      00065H, 00063H, 00062H, 00061H, 0005FH, 0005EH, 0005CH, 0005BH
                DW      0005AH, 00059H, 00057H, 00056H, 00055H, 00054H, 00052H, 00051H
                DW      00050H, 0004FH, 0004EH, 0004DH, 0004CH, 0004AH, 00049H, 00048H
                DW      00047H, 00046H, 00045H, 00044H, 00043H, 00042H, 00041H, 00040H
                DW      0003FH, 0003FH, 0003EH, 0003DH, 0003CH, 0003BH, 0003AH, 00039H
                DW      00039H, 00038H, 00037H, 00036H, 00035H, 00035H, 00034H, 00033H
                DW      00032H, 00032H, 00031H, 00030H, 00030H, 0002FH, 0002EH, 0002EH
                DW      0002DH, 0002CH, 0002CH, 0002BH, 0002AH, 0002AH, 00029H, 00029H
                DW      00028H, 00027H, 00027H, 00026H, 00026H, 00025H, 00025H, 00024H
                DW      00024H, 00023H, 00023H, 00022H, 00022H, 00021H, 00021H, 00020H
                DW      00020H, 0001FH, 0001FH, 0001EH, 0001EH, 0001EH, 0001DH, 0001DH
                DW      0001CH, 0001CH, 0001BH, 0001BH, 0001BH, 0001AH, 0001AH, 0001AH
                DW      00019H, 00019H, 00018H, 00018H, 00018H, 00017H, 00017H, 00017H
                DW      00016H, 00016H, 00016H, 00015H, 00015H, 00015H, 00015H, 00014H
                DW      00014H, 00014H, 00013H, 00013H, 00013H, 00013H, 00012H, 00012H
                DW      00012H, 00012H, 00011H, 00011H, 00011H, 00011H, 00010H, 00010H
                DW      00010H, 00010H


; ============================================================================
; 0x0278  --  Velocity / patch lookup tables
; ============================================================================

ps1_vel_curve_a DB      00FH, 000H, 00FH, 000H, 00FH, 000H, 00FH, 000H
                DB      00FH, 000H, 00EH, 000H, 00EH, 000H, 001H, 003H
                                                ; continuation of vel_curve_a
                                                ; (16 bytes total; one DB
                                                ; statement per visual row)

ps1_vel_curve_b DB      006H, 008H, 009H, 00AH, 00BH, 00CH, 00CH, 00DH
                DB      00DH, 00EH, 00EH, 00EH, 00FH, 00FH, 000H, 001H
                                                ; continuation of vel_curve_b
                                                ; (16 bytes total)


; ============================================================================
; 0x0298  --  ps1_patch_index  (14 bytes of program-to-bank slot mapping)
; ============================================================================
;
;   These 14 entries are read at note-on time to translate a MIDI
;   program number into an index in the loaded patch bank below.

ps1_patch_index DB      002H, 002H, 003H, 004H, 004H, 005H, 006H, 006H
                DB      007H, 008H, 008H, 009H, 00AH, 00AH
                                                ; continuation of patch_index
                                                ; (14 bytes total)


; ============================================================================
; 0x02A6  --  ps1_patch_bank  (1026-byte buffer for the loaded patch bank)
; ============================================================================
;
;   Slot 1 (ps1_load_patch_bank) copies the game's patch bank into this
;   buffer. The bank starts with a 128-word lookup table (256 bytes)
;   followed by up to 40 variable-length per-patch byte streams, each
;   terminated by 0xFF. The default contents installed at link time are
;   a tiny "all silent" bank that exercises the layout.

ps1_patch_bank  DB      128 DUP(000H, 001H) ; 256 bytes of (0, 1) pairs:
                                            ; a "stub" patch index where
                                            ; every entry points at slot 1
                                            ; (the second 0-byte entry).
                DB      00FH, 0FEH, 0FFH    ; bank terminator + 2 sentinel
                                            ; bytes
                DB      767 DUP(000H)       ; remainder of the buffer
                                            ; (zeroed by linker)


; ============================================================================
; 0x06A8  --  Per-channel state (16 channels x several SOA arrays)
; ============================================================================
;
;   These eight 16-byte byte/word arrays are indexed by MIDI channel
;   (0..15). They are kept as separate top-level globals (SOA), not one
;   array of per-channel structs.

ps1_ch_program  DB      16 DUP(000H)        ; CC#0 / Program Change

ps1_ch_volume   DB      16 DUP(00FH)        ; CC#7 (channel volume, default 15)

ps1_ch_pan      DB      16 DUP(040H)        ; CC#10 (pan, default 0x40)

ps1_ch_cc40     DB      16 DUP(000H)        ; CC#0x40 (foot / sustain mirror)

ps1_ch_pool     DB      16 DUP(000H)        ; CC#0x4B "sustain pool" counter

ps1_ch_pitchbend DW     16 DUP(2000H)       ; CC pitch-bend packed word
                                            ; (default centre 0x2000)

ps1_ch_pb_amount DB     16 DUP(000H)        ; quantised bend offset
                                            ; (used by ps1_pitchbend_apply)

ps1_ch_pb_dir   DB      16 DUP(000H)        ; bend direction (0=down, 1=up)


; ============================================================================
; 0x0738  --  Per-voice state (3 voices = PSG tone channels 0..2)
; ============================================================================

ps1_voice_channel DB    0FFH, 0FFH, 0FFH    ; voice -> MIDI ch (FF=idle)

ps1_voice_note  DB      0FFH, 0FFH, 0FFH    ; voice -> MIDI note (FF=idle)

ps1_voice_sustain DB    0FFH, 0FFH, 0FFH    ; voice held by sustain pedal?

; Per-voice working state. Each entry is touched only when its voice is
; in use; the SOA layout means a single BX register can hit any field
; via `[BX + <field_label>]`.
ps1_voice_inst_lo  DW   0, 0, 0             ; "age" word low half
ps1_voice_inst_hi  DW   0, 0, 0             ; "age" word high half
ps1_voice_note_tbl DW   0, 0, 0             ; pointer into ps1_patch_bank
ps1_voice_pos     DB    0, 0, 0             ; current note-table index
ps1_voice_dur     DB    0, 0, 0             ; remaining ticks for cur note
ps1_voice_last    DB    0, 0, 0             ; last note shipped to PSG
ps1_voice_held    DB    0, 0, 0             ; "release pending" flag
ps1_voice_vel    DB     0, 0, 0             ; per-voice attenuation

; LRU queue: ps1_voice_lru[0..2] hold the 3 voices in last-used order;
; remaining bytes are reserved (the original code only touches [0..2]).
ps1_voice_lru   DB      000H, 001H, 002H, 003H, 004H, 005H
                DB      006H, 007H, 008H, 009H, 00AH, 00BH
                                                ; continuation of voice_lru
                                                ; (reserved tail; 12 bytes
                                                ; although the chip only has
                                                ; 3 voices)

ps1_voice_pool_ch DB    0FFH, 0FFH, 0FFH    ; voice -> sustain-pool channel
                                            ; (FF = voice is available to
                                            ; the pool, otherwise the ch
                                            ; that holds the pool seat)

ps1_ch_poly_max  DB     16 DUP(000H)        ; per-channel polyphony budget

ps1_ch_poly_active DB   16 DUP(000H)        ; per-channel active voice count


; ============================================================================
; 0x0791  --  Global driver state
; ============================================================================

ps1_global_param  DB    000H                ; slot 11 store/query byte
ps1_master_enable DB    001H                ; slot 13 master-enable flag
ps1_master_volume DW    000FH               ; slot 12 master-volume word
                                            ; (default 15 = max)
                DB      4 DUP(000H)         ; pad before func_table


; ============================================================================
; 0x0799  --  Function dispatch table  (18 NEAR pointers, 36 bytes)
; ============================================================================

ps1_func_table  LABEL WORD
                DW      ps1_get_info             ; 0  -- 0x0FA9
                DW      ps1_load_patch_bank      ; 1  -- 0x0F71
                DW      ps1_reset_voices         ; 2  -- 0x0954
                DW      ps1_slot3_handler        ; 3  -- 0x0DC9 (real body)
                DW      ps1_midi_note_off        ; 4  -- 0x07CA
                DW      ps1_midi_note            ; 5  -- 0x0804
                DW      ps1_slot_unused_ret      ; 6  -- 0x07C9
                DW      ps1_midi_control_change  ; 7  -- 0x084E
                DW      ps1_midi_program_change  ; 8  -- 0x08BF
                DW      ps1_slot_unused_ret      ; 9  -- 0x07C9
                DW      ps1_midi_pitch_bend      ; 10 -- 0x08CD
                DW      ps1_set_global_param     ; 11 -- 0x097A
                DW      ps1_set_master_volume    ; 12 -- 0x098C
                DW      ps1_set_master_enable    ; 13 -- 0x09A1
                DW      ps1_slot_unused_ret      ; 14 -- 0x07C9
                DW      ps1_slot_unused_ret      ; 15 -- 0x07C9
                DW      ps1_slot_unused_ret      ; 16 -- 0x07C9
                DW      ps1_query_state          ; 17 -- 0x0EFA


; ============================================================================
; 0x07BD  --  Dispatch trampoline
; ============================================================================

; ----------------------------------------------------------------------------
; 0x07BD  --  ps1_dispatch
;
;   The single entry point for the entire driver. The game `CALL FAR`s
;   here with BP holding a slot index (0..17); we double the index into a
;   word offset, load the slot's near-handler pointer from ps1_func_table,
;   `CALL`  it, then `RETF` back to the game.
;
;   Type:        Dispatch trampoline
;   Category:    DUDE ABI
;   Callers:     Game (only call site of this driver, via FAR CALL)
;   Callees:     Every slot handler in ps1_func_table (indirect via DX)
;
;   Inputs:
;     BP  --  slot index (0..17). 18 slots; see DUDE ABI section above.
;     AL  --  MIDI channel (slots that need one)
;     CL  --  MIDI data byte 1 (per slot: velocity / CC value / etc.)
;     CH  --  MIDI data byte 2 (per slot: note / CC# / etc.)
;     ES:AX -- far pointer to patch bank (slot 1 only)
;
;   Outputs:     varies per slot (returned in AX / CL / CH; see handlers)
;
;   Touches:     BP (shifted left in place; caller doesn't observe), DX
;                (saved+restored across CALL).
;
;   Notes:
;     Unlike the ADL trampoline (which pushes BP across the CALL), this
;     PS/1 trampoline pushes DX. Functionally equivalent -- whichever
;     spare register survives the CALL.
; ----------------------------------------------------------------------------
ps1_dispatch    PROC NEAR
                PUSH    DX                  ; preserve caller's DX
                SHL     BP, 1               ; word-index into table
                MOV     DX, CS:[BP + ps1_func_table]
                CALL    DX                  ; near indirect call
                POP     DX
                RETF                        ; back to game (FAR caller)
ps1_dispatch    ENDP


; ============================================================================
; 0x07C9  --  Slot bodies
; ============================================================================

; ----------------------------------------------------------------------------
; 0x07C9  --  ps1_slot_unused_ret
;
;   Shared one-byte RET. Slots 6, 9, 14, 15, 16 dispatch here.
; ----------------------------------------------------------------------------
ps1_slot_unused_ret LABEL NEAR
                RET                         ; 0xC3


; ----------------------------------------------------------------------------
; 0x07CA  --  ps1_midi_note_off  (slot 4)
;
;   MIDI "note off". Scan the 3 voices for one assigned to (channel AL,
;   note CH); if found, the action depends on whether the channel's
;   CC#64 (sustain) flag is set:
;     - CC#64 != 0:  defer the release. The voice's "sustain" flag is set
;       so a later "pedal up" can drop it.
;     - CC#64 == 0:  mark the voice "held" so the periodic tick (slot 3)
;       runs the release on its next pass.
;
;   Type:        Slot handler
;   Category:    MIDI dispatch
;   Dispatch:    Slot 4 (called as: BP=4, AL=channel, CH=note)
;   Callers:     Game (via dispatch), ps1_midi_note (vel=0 fall-through)
;   Callees:     none
;
;   Inputs:
;     AL  --  MIDI channel (0..15)
;     CH  --  MIDI note number (0..127)
;
;   Outputs:     none
;
;   Touches:     all caller registers preserved (saves BX and SI)
;
;   Side effects:
;     For every matching voice:
;       - if ps1_ch_cc40[ch] != 0: ps1_voice_sustain[v] <- 1
;       - else:                    ps1_voice_held[v]    <- 1
;     (No PSG write here; the periodic tick performs the release later.)
; ----------------------------------------------------------------------------
ps1_midi_note_off PROC NEAR
                PUSH    BX
                PUSH    SI

                MOV     BX, 0
noff_test:      CMP     CS:[BX + ps1_voice_channel], AL
                JNE     SHORT noff_next
                CMP     CS:[BX + ps1_voice_note], CH
                JNE     SHORT noff_next

                ; SI = AL zero-extended (channel index into CC arrays).
                MOV     SI, AX
                AND     SI, 00FFH

                CMP     BYTE PTR CS:[SI + ps1_ch_cc40], 0
                JE      SHORT noff_release
                MOV     BYTE PTR CS:[BX + ps1_voice_sustain], 1
                JMP     SHORT noff_done

noff_release:   MOV     BYTE PTR CS:[BX + ps1_voice_held], 1
                JMP     SHORT noff_done

noff_next:      INC     BX
                CMP     BX, 3
                JNE     SHORT noff_test

noff_done:      POP     SI
                POP     BX
                RET
ps1_midi_note_off ENDP


; ----------------------------------------------------------------------------
; 0x0804  --  ps1_midi_note  (slot 5)
;
;   MIDI "note on", or "note off" via the velocity=0 convention. If the
;   note is outside the playable range (0x15..0x74), or vel=0, we fall
;   through to the note-off path. Otherwise we look for an existing
;   matching voice (re-trigger -- release then re-commit) or, if none
;   matches, allocate a fresh voice via ps1_voice_allocate then commit
;   it via ps1_voice_commit_note.
;
;   Type:        Slot handler
;   Category:    MIDI dispatch
;   Dispatch:    Slot 5 (called as: BP=5, AL=channel, CH=note, CL=velocity)
;   Callers:     Game (via dispatch)
;   Callees:     ps1_midi_note_off (vel=0), ps1_voice_release,
;                ps1_voice_commit_note, ps1_voice_allocate
;
;   Inputs:
;     AL  --  MIDI channel (0..15)
;     CH  --  MIDI note number (range-checked: must be 0x15..0x74)
;     CL  --  MIDI velocity (0 -> note off; >0 -> note on)
;
;   Outputs:     none
;
;   Touches:     all caller registers preserved (saves BX and SI)
;
;   Side effects:
;     - On retrigger: clears ps1_voice_sustain[v], calls
;       ps1_voice_release (full tear-down), then ps1_voice_commit_note
;       (re-stamp + emit freq).
;     - On fresh allocate: ps1_voice_allocate updates LRU and
;       ps1_voice_channel[v]; ps1_voice_commit_note ships freq + volume
;       to the PSG.
; ----------------------------------------------------------------------------
ps1_midi_note   PROC NEAR
                PUSH    BX
                PUSH    SI

                CMP     CH, 15H             ; range-check note low end
                JB      SHORT note_done
                CMP     CH, 74H             ; range-check note high end
                JA      SHORT note_done
                CMP     CL, 0               ; vel=0 -> behave as note off
                JNE     SHORT note_search
                CALL    ps1_midi_note_off
                JMP     SHORT note_done

note_search:    MOV     BX, 0
note_scan:      CMP     CS:[BX + ps1_voice_channel], AL
                JNE     SHORT note_scan_next
                CMP     CS:[BX + ps1_voice_note], CH
                JNE     SHORT note_scan_next
                MOV     BYTE PTR CS:[BX + ps1_voice_sustain], 0
                CALL    ps1_voice_release
                CALL    ps1_voice_commit_note
                JMP     SHORT note_done
note_scan_next: INC     BX
                CMP     BX, 3
                JNE     SHORT note_scan

                CALL    ps1_voice_allocate
                CMP     BX, 00FFH
                JE      SHORT note_done
                CALL    ps1_voice_commit_note

note_done:      POP     SI
                POP     BX
                RET
ps1_midi_note   ENDP


; ----------------------------------------------------------------------------
; 0x084E  --  ps1_midi_control_change  (slot 7)
;
;   MIDI CC handler. Recognised CC numbers:
;     CC#0x07 -- channel volume (scaled by >>3 and floored to 1)
;     CC#0x0A -- channel pan (stored verbatim into ps1_ch_pan)
;     CC#0x40 -- foot/legacy controller -> ps1_cc40_sustain_apply
;     CC#0x4B -- per-channel pool counter -> ps1_cc4b_pool_apply
;     CC#0x7B -- all-notes-off; force release on all matching voices
;   Unknown CC numbers are silently dropped.
;
;   Type:        Slot handler
;   Category:    MIDI dispatch
;   Dispatch:    Slot 7 (called as: BP=7, AL=channel, CH=cc#, CL=value)
;   Callers:     Game (via dispatch)
;   Callees:     ps1_cc40_sustain_apply, ps1_cc4b_pool_apply,
;                ps1_voice_release (for CC#0x7B "all notes off")
;
;   Inputs:
;     AL  --  MIDI channel (0..15)
;     CH  --  MIDI controller number
;     CL  --  controller value (0..127); semantics depend on CH
;
;   Outputs:     none
;
;   Touches:     BX is saved/restored; DI saved/restored within branches
;
;   Side effects:
;     CC#7  -> ps1_ch_volume[ch]  <- value (or value>>3, min 1, if value>0)
;     CC#10 -> ps1_ch_pan[ch]     <- value
;     CC#40 -> via ps1_cc40_sustain_apply
;     CC#4B -> via ps1_cc4b_pool_apply
;     CC#7B -> ps1_voice_release on every voice playing on this channel
; ----------------------------------------------------------------------------
ps1_midi_control_change PROC NEAR
                PUSH    BX

                CMP     CH, 7
                JNE     SHORT cc_0a_test
                CMP     CL, 0
                JE      SHORT cc_7_store
                ; Scale 0..127 -> 0..15 (right-shift by 3); bump 0 to 1.
                SHR     CL, 1
                SHR     CL, 1
                SHR     CL, 1
                CMP     CL, 0
                JNE     SHORT cc_7_store
                INC     CL
cc_7_store:     PUSH    DI
                MOV     DI, AX
                AND     DI, 00FFH
                MOV     CS:[DI + ps1_ch_volume], CL
                POP     DI
                JMP     SHORT cc_done

cc_0a_test:     CMP     CH, 0AH
                JNE     SHORT cc_40_test
                PUSH    DI
                MOV     DI, AX
                AND     DI, 00FFH
                MOV     CS:[DI + ps1_ch_pan], CL
                POP     DI
                JMP     SHORT cc_done

cc_40_test:     CMP     CH, 40H
                JNE     SHORT cc_4b_test
                CALL    ps1_cc40_sustain_apply
                JMP     SHORT cc_done

cc_4b_test:     CMP     CH, 4BH
                JNE     SHORT cc_7b_test
                CALL    ps1_cc4b_pool_apply
                JMP     SHORT cc_done

cc_7b_test:     CMP     CH, 7BH
                JNE     SHORT cc_done
                MOV     BX, 0
cc_7b_scan:     CMP     CS:[BX + ps1_voice_channel], AL
                JNE     SHORT cc_7b_next
                CMP     BYTE PTR CS:[BX + ps1_voice_note], 0FFH
                JE      SHORT cc_7b_next
                CALL    ps1_voice_release     ; force release
cc_7b_next:     INC     BX
                CMP     BX, 3
                JNE     SHORT cc_7b_scan

cc_done:        POP     BX
                RET
ps1_midi_control_change ENDP


; ----------------------------------------------------------------------------
; 0x08BF  --  ps1_midi_program_change  (slot 8)
;
;   MIDI Program Change. Caches program# in ps1_ch_program[ch]; the next
;   note-on on this channel re-reads it (via ps1_voice_commit_note) when
;   choosing which patch-bank entry to use.
;
;   Type:        Slot handler
;   Category:    MIDI dispatch
;   Dispatch:    Slot 8 (called as: BP=8, AL=channel, CL=program#)
;   Callers:     Game (via dispatch), ps1_pool_claim (during pool claim
;                its housekeeping re-asserts the channel's current program)
;   Callees:     none
;
;   Inputs:
;     AL  --  MIDI channel (0..15)
;     CL  --  patch / program number (0..127)
;
;   Outputs:     none
;
;   Touches:     all caller registers preserved (saves SI)
;
;   Side effects:
;     ps1_ch_program[channel] <- patch_number
; ----------------------------------------------------------------------------
ps1_midi_program_change PROC NEAR
                PUSH    SI
                MOV     SI, AX
                AND     SI, 00FFH
                MOV     CS:[SI + ps1_ch_program], CL
                POP     SI
                RET
ps1_midi_program_change ENDP


; ----------------------------------------------------------------------------
; 0x08CD  --  ps1_midi_pitch_bend  (slot 10)
;
;   MIDI pitch-bend. CH:CL is a 14-bit value (centred at 0x2000) sent as
;   two 7-bit MIDI data bytes. We re-pack to a 16-bit word, cache it,
;   compute the quantised bend offset (0..0x4B sub-steps) + direction
;   byte, then re-tune every voice currently sounding on this channel
;   immediately via ps1_psg_write_freq.
;
;   Type:        Slot handler
;   Category:    MIDI dispatch
;   Dispatch:    Slot 10 (called as: BP=10, AL=channel, CH=msb_7bit, CL=lsb_7bit)
;   Callers:     Game (via dispatch)
;   Callees:     ps1_psg_write_freq
;
;   Inputs:
;     AL  --  MIDI channel (0..15)
;     CH  --  pitch-bend MSB (top 7 bits of the 14-bit value)
;     CL  --  pitch-bend LSB (low 7 bits)
;
;   Outputs:     none
;
;   Touches:     all caller registers preserved (saves BX/CX/DX/SI/AX)
;
;   Side effects:
;     ps1_ch_pitchbend[ch] <- packed 14-bit word
;     ps1_ch_pb_amount[ch] <- |bend - 0x2000| / 0xAA  (quantised offset)
;     ps1_ch_pb_dir[ch]    <- 1 if bend >= 0x2000 else 0
;     For each voice on this channel that's playing: calls
;     ps1_psg_write_freq -> writes the PSG.
; ----------------------------------------------------------------------------
ps1_midi_pitch_bend PROC NEAR
                PUSH    BX
                PUSH    CX
                PUSH    DX
                PUSH    SI
                PUSH    AX
                PUSH    CX
                PUSH    SI

                MOV     SI, AX
                AND     SI, 00FFH
                SHL     SI, 1               ; SI = ch * 2 (word index)

                ; Repack CH:CL into one 16-bit word: swap bytes, shift
                ; the top byte right by 1 and route carry into CL bit 7.
                XCHG    CH, CL
                SHR     CH, 1
                JNC     SHORT pb_no_carry1
                OR      CL, 80H
pb_no_carry1:   MOV     CS:[SI + ps1_ch_pitchbend], CX
                POP     SI
                POP     CX

                ; Recompute the packed AX (without using up SI which we
                ; need for the byte-indexed arrays).
                MOV     SI, AX
                AND     SI, 00FFH
                MOV     AH, CL
                MOV     AL, CH
                SHR     AH, 1
                JNC     SHORT pb_no_carry2
                OR      AL, 80H
pb_no_carry2:   MOV     BYTE PTR CS:[SI + ps1_ch_pb_dir], 0
                MOV     BYTE PTR CS:[SI + ps1_ch_pb_amount], 0
                CMP     AX, 2000H
                JE      SHORT pb_apply
                JA      SHORT pb_up

                ; bend < 0x2000: downward.
                MOV     CX, AX
                MOV     AX, 2000H
                SUB     AX, CX
                MOV     CL, 0AAH
                DIV     CL
                MOV     CS:[SI + ps1_ch_pb_amount], AL
                JMP     SHORT pb_apply
pb_up:          SUB     AX, 2000H
                MOV     CL, 0AAH
                DIV     CL
                MOV     CS:[SI + ps1_ch_pb_amount], AL
                MOV     BYTE PTR CS:[SI + ps1_ch_pb_dir], 1

pb_apply:       POP     AX
                MOV     BX, 0
pb_scan:        CMP     CS:[BX + ps1_voice_channel], AL
                JNE     SHORT pb_scan_next
                CMP     BYTE PTR CS:[BX + ps1_voice_note], 0FFH
                JE      SHORT pb_scan_next
                CALL    ps1_psg_write_freq         ; commit new freq for this voice
pb_scan_next:   INC     BX
                CMP     BX, 3
                JNE     SHORT pb_scan

                POP     SI
                POP     DX
                POP     CX
                POP     BX
                RET
ps1_midi_pitch_bend ENDP


; ----------------------------------------------------------------------------
; 0x0954  --  ps1_reset_voices  (slot 2)
;
;   Initialise / silence: write attenuation 0xF (silent) to all three
;   PSG tone channels by OR'ing (voice<<5) | 0x90 | 0x0F and shipping
;   the byte out PS1_PORT_DATA. After this returns, every tone channel
;   is muted; the driver's in-memory voice state is NOT cleared (that
;   stays for whatever the next note-on does).
;
;   Type:        Slot handler
;   Category:    PSG I/O
;   Dispatch:    Slot 2 (called as: BP=2; no other inputs)
;   Callers:     Game (via dispatch, typically once at startup/shutdown)
;   Callees:     none (writes PSG directly)
;
;   Inputs:      none
;
;   Outputs:     none
;
;   Touches:     all caller registers preserved (saves AX/CX/DX/DI)
;
;   Side effects:
;     For voice = 0, 1, 2: write byte (voice<<5)|0x90|0x0F to PS1_PORT_DATA
;     (PSG-attenuation register, value 15 = silent).
; ----------------------------------------------------------------------------
ps1_reset_voices PROC NEAR
                PUSH    AX
                PUSH    CX
                PUSH    DX
                PUSH    DI
                MOV     CL, 5
                MOV     DI, 0
rv_loop:        MOV     DX, DI
                SHL     DL, CL              ; DL = voice << 5
                OR      DL, 90H             ; attenuation-register select
                OR      DL, 0FH             ; value = 15 (silent)
                MOV     AL, DL
                PUSH    DX
                MOV     DX, PS1_PORT_DATA
                OUT     DX, AL
                POP     DX
                INC     DI
                CMP     DI, 3
                JNE     SHORT rv_loop
                POP     DI
                POP     DX
                POP     CX
                POP     AX
                RET
ps1_reset_voices ENDP


; ----------------------------------------------------------------------------
; 0x097A  --  ps1_set_global_param  (slot 11)
;
;   Setter / query for the single-byte ps1_global_param. The convention
;   shared with slots 12 and 13: CL=0xFF means "query" (return current
;   value in AX), any other value means "store CL into the slot".
;
;   Type:        Slot handler
;   Category:    Global state
;   Dispatch:    Slot 11 (called as: BP=11, CL=value or 0xFF for query)
;   Callers:     Game (via dispatch)
;   Callees:     none
;
;   Inputs:
;     CL  --  new value, or 0xFF to query
;
;   Outputs:
;     AX  --  current ps1_global_param (whether queried or just stored)
;
;   Touches:     AX (return value), AH zeroed
;
;   Side effects:
;     If CL != 0xFF: ps1_global_param <- CL.
; ----------------------------------------------------------------------------
ps1_set_global_param PROC NEAR
                MOV     AL, CS:[ps1_global_param]
                XOR     AH, AH
                CMP     CL, 0FFH
                JNE     SHORT sgp_store
                RET
sgp_store:      MOV     CS:[ps1_global_param], CL
                RET
ps1_set_global_param ENDP


; ----------------------------------------------------------------------------
; 0x098C  --  ps1_set_master_volume  (slot 12)
;
;   Setter / query for ps1_master_volume (a word, 0..15). The factor is
;   applied by ps1_voice_emit_volume as one stage of the mul/div-by-15
;   chain that produces the per-voice attenuation. CL=0xFF means query.
;
;   Type:        Slot handler
;   Category:    Global state
;   Dispatch:    Slot 12 (called as: BP=12, CL=value or 0xFF for query)
;   Callers:     Game (via dispatch)
;   Callees:     none
;
;   Inputs:
;     CL  --  new master volume (0..15), or 0xFF to query
;
;   Outputs:
;     AX  --  current ps1_master_volume
;
;   Touches:     AX (return), CX (saved+restored)
;
;   Side effects:
;     If CL != 0xFF: ps1_master_volume <- (CL zero-extended to word).
; ----------------------------------------------------------------------------
ps1_set_master_volume PROC NEAR
                PUSH    CX
                MOV     AX, CS:[ps1_master_volume]
                CMP     CL, 0FFH
                JNE     SHORT smv_store
                JMP     SHORT smv_done
smv_store:      XOR     CH, CH
                MOV     CS:[ps1_master_volume], CX
smv_done:       POP     CX
                RET
ps1_set_master_volume ENDP


; ----------------------------------------------------------------------------
; 0x09A1  --  ps1_set_master_enable  (slot 13)
;
;   Setter / query for ps1_master_enable (0 = driver muted, 1 = active).
;   CL=0xFF means query; CL=0 stores 0; any other value stores 1.
;
;   Type:        Slot handler
;   Category:    Global state
;   Dispatch:    Slot 13 (called as: BP=13, CL=value or 0xFF for query)
;   Callers:     Game (via dispatch)
;   Callees:     none
;
;   Inputs:
;     CL  --  new master enable (0=mute, !=0=active), or 0xFF to query
;
;   Outputs:
;     AX  --  current ps1_master_enable
;
;   Touches:     AX (return), AH zeroed
;
;   Side effects:
;     If CL = 0:        ps1_master_enable <- 0
;     If CL not 0,FF:   ps1_master_enable <- 1
;     ps1_voice_emit_volume zeroes its AL output when master_enable=0,
;     so the next attenuation write to the PSG silences the channel.
; ----------------------------------------------------------------------------
ps1_set_master_enable PROC NEAR
                MOV     AL, CS:[ps1_master_enable]
                XOR     AH, AH
                CMP     CL, 0FFH
                JNE     SHORT sme_clear
                RET
sme_clear:      MOV     BYTE PTR CS:[ps1_master_enable], 0
                CMP     CL, 0
                JNE     SHORT sme_set
                RET
sme_set:        MOV     BYTE PTR CS:[ps1_master_enable], 1
                RET
ps1_set_master_enable ENDP


; ----------------------------------------------------------------------------
; 0x09C0  --  ps1_voice_allocate
;
;   Pick a voice for a new note. Two-pass:
;     Pass 1: walk the LRU queue for any voice whose voice_note is FF
;             (idle); claim it for the requesting channel.
;     Pass 2: if none idle, find the MIDI channel with the largest
;             (active - max) polyphony overage; the loser is the one
;             whose voice we steal (LRU order). If no channel is over
;             budget, the requesting channel steals its own LRU voice.
;             If the steal also fails (no voices belong to the loser
;             channel), return 0xFFFF.
;
;   Type:        Internal helper (voice management)
;   Category:    Voice management
;   Callers:     ps1_midi_note
;   Callees:     ps1_voice_release  (for the steal path: tear down the
;                                    victim before reusing it)
;
;   Inputs:
;     AL  --  MIDI channel requesting the voice
;
;   Outputs:
;     BX  --  voice index in [0, 2], or 0xFFFF if none could be allocated
;
;   Touches:     CX, DX, SI are saved+restored; BX is the return value.
;
;   Side effects:
;     On success: ps1_voice_channel[v] <- AL (claim).
;     On steal:   ps1_voice_release(v) first (zeroes per-voice state,
;                 rotates LRU, decrements that channel's poly_active).
; ----------------------------------------------------------------------------
ps1_voice_allocate PROC NEAR
                PUSH    CX
                PUSH    DX
                PUSH    SI

                XOR     SI, SI
                XOR     BX, BX
                JMP     SHORT va_p1_test
va_p1_body:     MOV     BL, CS:[SI + ps1_voice_lru]
                CMP     BYTE PTR CS:[BX + ps1_voice_note], 0FFH
                JNE     SHORT va_p1_next
                MOV     CS:[BX + ps1_voice_channel], AL
                JMP     SHORT va_done
va_p1_next:     INC     SI
va_p1_test:     CMP     SI, 3
                JB      SHORT va_p1_body

                XOR     SI, SI
                XOR     BX, BX
                XOR     CX, CX
                XOR     DX, DX
                JMP     SHORT va_p2_test
va_p2_body:     MOV     CL, CS:[SI + ps1_ch_poly_active]
                CMP     CL, CS:[SI + ps1_ch_poly_max]
                JBE     SHORT va_p2_next
                SUB     CL, CS:[SI + ps1_ch_poly_max]
                CMP     BL, CL
                JAE     SHORT va_p2_next
                MOV     BL, CL
                MOV     DX, SI
va_p2_next:     INC     SI
va_p2_test:     CMP     SI, 10H
                JB      SHORT va_p2_body

                MOV     CL, AL
                CMP     BL, 0
                JBE     SHORT va_p3_init
                MOV     CL, DL

va_p3_init:     XOR     SI, SI
                XOR     BX, BX
                JMP     SHORT va_p3_test
va_p3_body:     MOV     BL, CS:[SI + ps1_voice_lru]
                CMP     CS:[BX + ps1_voice_channel], CL
                JNE     SHORT va_p3_next
                CALL    ps1_voice_release
                MOV     CS:[BX + ps1_voice_channel], AL
                JMP     SHORT va_done
va_p3_next:     INC     SI
va_p3_test:     CMP     SI, 3
                JB      SHORT va_p3_body
                MOV     BX, 0FFFFH

va_done:        POP     SI
                POP     DX
                POP     CX
                RET
ps1_voice_allocate ENDP


; ----------------------------------------------------------------------------
; 0x0A3E  --  ps1_cc4b_pool_apply
;
;   CC#0x4B "pool counter" handler. The PS/1 driver gives each MIDI
;   channel a configurable polyphony budget (its share of the 3 PSG
;   voices). CC#0x4B sets that budget; this function reconciles the
;   new target (CL) against the channel's current claim (count of
;   voices in the channel pool + the "owed" counter ps1_ch_pool).
;
;   If CL > current: claim more voices from the global pool
;     (ps1_pool_claim).
;   If CL < current: release the excess back to the global pool
;     (ps1_pool_release + ps1_pool_redistribute).
;
;   Type:        Internal helper (CC dispatch)
;   Category:    Voice management
;   Callers:     ps1_midi_control_change (CC#0x4B branch)
;   Callees:     ps1_pool_claim, ps1_pool_release, ps1_pool_redistribute
;
;   Inputs:
;     AL  --  MIDI channel
;     CL  --  new pool budget (target count of voices owned)
;
;   Outputs:     none
;
;   Touches:     all caller registers preserved (saves SI/CX/DX)
;
;   Side effects:
;     Adjusts ps1_voice_pool_ch / ps1_ch_pool / ps1_ch_poly_max as
;     described above; may force ps1_voice_release on stolen voices.
; ----------------------------------------------------------------------------
ps1_cc4b_pool_apply     PROC NEAR
                PUSH    SI
                PUSH    CX
                PUSH    DX

                XOR     SI, SI
                XOR     DX, DX
cc4b_count:     CMP     CS:[SI + ps1_voice_pool_ch], AL
                JNE     SHORT cc4b_count_next
                INC     DL
cc4b_count_next:
                INC     SI
                CMP     SI, 3
                JNE     SHORT cc4b_count

                MOV     SI, AX
                AND     SI, 00FFH

                ADD     DL, CS:[SI + ps1_ch_pool]
                CMP     DL, CL
                JE      SHORT cc4b_done
                JA      SHORT cc4b_refill
                SUB     CL, DL
                CALL    ps1_pool_claim
                JMP     SHORT cc4b_done
cc4b_refill:    SUB     DL, CL
                MOV     CL, DL
                CALL    ps1_pool_release
                CALL    ps1_pool_redistribute

cc4b_done:      POP     DX
                POP     CX
                POP     SI
                RET
ps1_cc4b_pool_apply     ENDP


; ----------------------------------------------------------------------------
; 0x0A7A  --  ps1_pool_redistribute
;
;   After voices have been released back to the global pool by
;   ps1_pool_release, this helper hands them out to other channels
;   whose ps1_ch_pool counter is non-zero (i.e. channels with
;   outstanding "I'd like extra voices" requests). Walks channels in
;   order; for each, either consumes all of ps1_ch_pool[c] or as much
;   as fits in the remaining unassigned-voice count CL.
;
;   Type:        Internal helper (pool management)
;   Category:    Voice management
;   Callers:     ps1_cc4b_pool_apply
;   Callees:     ps1_pool_claim
;
;   Inputs:      none (uses globals; computes count internally)
;
;   Outputs:     none
;
;   Touches:     all caller registers preserved (saves AX/CX/SI)
;
;   Side effects:
;     For each channel with ps1_ch_pool[c] > 0: ps1_pool_claim
;     re-acquires voices for that channel until either CL or
;     ps1_ch_pool[c] runs out; ps1_ch_pool[c] is then decremented.
; ----------------------------------------------------------------------------
ps1_pool_redistribute     PROC NEAR
                PUSH    AX
                PUSH    CX
                PUSH    SI

                XOR     CL, CL
                XOR     SI, SI
pred_count:     CMP     BYTE PTR CS:[SI + ps1_voice_pool_ch], 0FFH
                JNE     SHORT pred_count_next
                INC     CL
pred_count_next:
                INC     SI
                CMP     SI, 3
                JNE     SHORT pred_count

                CMP     CL, 0
                JE      SHORT pred_done

                XOR     SI, SI
pred_scan:      MOV     CH, CS:[SI + ps1_ch_pool]
                CMP     CH, 0
                JE      SHORT pred_skip
                CMP     CH, CL
                JAE     SHORT pred_partial
                SUB     CL, CH
                PUSH    CX
                MOV     CL, CH
                MOV     BYTE PTR CS:[SI + ps1_ch_pool], 0
                MOV     AX, SI
                CALL    ps1_pool_claim
                POP     CX
                JMP     SHORT pred_skip
pred_partial:   SUB     CH, CL
                MOV     CS:[SI + ps1_ch_pool], CH
                MOV     AX, SI
                CALL    ps1_pool_claim
                JMP     SHORT pred_done
pred_skip:      INC     SI
                CMP     SI, 10H
                JNE     SHORT pred_scan

pred_done:      POP     SI
                POP     CX
                POP     AX
                RET
ps1_pool_redistribute     ENDP


; ----------------------------------------------------------------------------
; 0x0AD1  --  ps1_pool_claim
;
;   Assign CL voices from the global pool (voices with pool_ch=0xFF) to
;   the requesting channel AL. Each claimed voice's pool_ch is set to AL
;   and ps1_ch_poly_max[ch] is incremented. If a candidate voice is still
;   playing a note, ps1_voice_release runs first to tear it down.
;
;   If not enough free voices exist, the unsatisfied remainder is
;   parked into ps1_ch_pool[ch] for later redistribution. Finally the
;   channel's current program is re-asserted (ps1_midi_program_change)
;   so the next note picks the right patch.
;
;   Type:        Internal helper (pool management)
;   Category:    Voice management
;   Callers:     ps1_cc4b_pool_apply, ps1_pool_redistribute
;   Callees:     ps1_voice_release, ps1_midi_program_change
;
;   Inputs:
;     AL  --  MIDI channel claiming the voices
;     CL  --  number of voices to claim
;
;   Outputs:     none
;
;   Touches:     all caller registers preserved (saves CX/BX/SI)
;
;   Side effects:
;     ps1_voice_pool_ch[v]  <- AL  (for each claimed voice)
;     ps1_ch_poly_max[ch]   <- +1  (per claim)
;     ps1_ch_pool[ch]       <- +(unfilled remainder)
;     plus any ps1_voice_release side effects on stolen voices.
; ----------------------------------------------------------------------------
ps1_pool_claim     PROC NEAR
                PUSH    CX
                PUSH    BX
                PUSH    SI
                XOR     BX, BX
pcla_scan:      CMP     BYTE PTR CS:[BX + ps1_voice_pool_ch], 0FFH
                JNE     SHORT pcla_next
                CMP     BYTE PTR CS:[BX + ps1_voice_note], 0FFH
                JE      SHORT pcla_take
                CALL    ps1_voice_release     ; release first
pcla_take:      MOV     CS:[BX + ps1_voice_pool_ch], AL
                XOR     AH, AH
                MOV     SI, AX
                INC     BYTE PTR CS:[SI + ps1_ch_poly_max]
                DEC     CL
                CMP     CL, 0
                JE      SHORT pcla_done
pcla_next:      INC     BX
                CMP     BX, 3
                JNE     SHORT pcla_scan
pcla_done:      MOV     SI, AX
                AND     SI, 00FFH
                ADD     CS:[SI + ps1_ch_pool], CL
                MOV     CL, CS:[SI + ps1_ch_program]
                CALL    ps1_midi_program_change
                POP     SI
                POP     BX
                POP     CX
                RET
ps1_pool_claim     ENDP


; ----------------------------------------------------------------------------
; 0x0B1B  --  ps1_pool_release
;
;   Release CL voices owned by channel AL back to the global pool.
;
;   First we try to satisfy the request out of ps1_ch_pool[AL] (the
;   channel's "owed" counter). Any leftover demand is paid by:
;     Phase 1: release idle voices (ps1_voice_note == 0xFF) first --
;              cheap; just clear pool_ch and decrement poly_max.
;     Phase 2: release the currently-playing voice with the OLDEST age
;              key (inst_hi:inst_lo) via ps1_voice_release. Repeat
;              until CL satisfied.
;
;   Type:        Internal helper (pool management)
;   Category:    Voice management
;   Callers:     ps1_cc4b_pool_apply
;   Callees:     ps1_voice_release
;
;   Inputs:
;     AL  --  MIDI channel relinquishing voices
;     CL  --  number of voices to release
;
;   Outputs:     none
;
;   Touches:     all caller registers preserved (saves AX/BX/CX/DX/SI)
;
;   Side effects:
;     ps1_ch_pool[AL] decremented (or zeroed) first.
;     For each released voice: pool_ch <- 0xFF, ps1_ch_poly_max[AL]--,
;     and (Phase 2 only) full ps1_voice_release tear-down.
; ----------------------------------------------------------------------------
ps1_pool_release     PROC NEAR
                PUSH    AX
                PUSH    BX
                PUSH    CX
                PUSH    DX
                PUSH    SI

                MOV     SI, AX
                AND     SI, 00FFH

                CMP     CS:[SI + ps1_ch_pool], CL
                JNE     SHORT prel_partial
                MOV     BYTE PTR CS:[SI + ps1_ch_pool], 0
                JMP     prel_done
prel_partial:   JB      SHORT prel_short
                SUB     CS:[SI + ps1_ch_pool], CL
                JMP     prel_done

prel_short:     SUB     CL, CS:[SI + ps1_ch_pool]
                MOV     BYTE PTR CS:[SI + ps1_ch_pool], 0

                ; Phase 1: release idle voices (note==FF) first.
                XOR     BX, BX
prel_p1:        CMP     CS:[BX + ps1_voice_pool_ch], AL
                JNE     SHORT prel_p1_next
                CMP     BYTE PTR CS:[BX + ps1_voice_note], 0FFH
                JNE     SHORT prel_p1_next
                MOV     BYTE PTR CS:[BX + ps1_voice_pool_ch], 0FFH
                XOR     AH, AH
                MOV     SI, AX
                DEC     BYTE PTR CS:[SI + ps1_ch_poly_max]
                DEC     CL
                CMP     CL, 0
                JE      SHORT prel_done
prel_p1_next:   INC     BX
                CMP     BX, 3
                JNE     SHORT prel_p1

                ; Phase 2: find the voice with the largest age word
                ; and release it. Repeat until CL satisfied.
prel_p2_top:    XOR     DX, DX
                XOR     BX, BX
prel_p2:        CMP     CS:[BX + ps1_voice_pool_ch], AL
                JNE     SHORT prel_p2_next
                PUSH    AX
                SHL     BX, 1
                MOV     AX, CS:[BX + ps1_voice_inst_hi]
                DB      83H, 0F8H, 000H     ; CMP AX, 0
                JE      SHORT prel_lo
                ADD     AX, 8000H
                JMP     SHORT prel_cmp
prel_lo:        MOV     AX, CS:[BX + ps1_voice_inst_lo]
prel_cmp:       SHR     BX, 1
                CMP     AX, DX
                JB      SHORT prel_p2_pop
                MOV     SI, BX
                MOV     DX, AX
prel_p2_pop:    POP     AX
prel_p2_next:   INC     BX
                CMP     BX, 3
                JNE     SHORT prel_p2

                MOV     BX, SI
                MOV     BYTE PTR CS:[BX + ps1_voice_sustain], 0
                CALL    ps1_voice_release
                MOV     BYTE PTR CS:[BX + ps1_voice_pool_ch], 0FFH
                XOR     AH, AH
                MOV     SI, AX
                DEC     BYTE PTR CS:[SI + ps1_ch_poly_max]
                DEC     CL
                CMP     CL, 0
                JE      SHORT prel_done
                JMP     SHORT prel_p2_top ; round-trip back to phase 2

prel_done:      POP     SI
                POP     DX
                POP     CX
                POP     BX
                POP     AX
                RET
ps1_pool_release     ENDP


; ----------------------------------------------------------------------------
; 0x0BD4  --  ps1_cc40_sustain_apply
;
;   CC#0x40 handler (foot / legacy "sustain" controller). Stashes the
;   incoming CL into ps1_ch_cc40[ch]. If CL == 0 ("pedal up"), every
;   voice on this channel whose ps1_voice_sustain flag was set gets
;   that flag cleared AND its "held" flag raised, which means the
;   periodic tick (slot 3) will perform the deferred release on its
;   next pass.
;
;   Type:        Internal helper (CC dispatch)
;   Category:    MIDI dispatch
;   Callers:     ps1_midi_control_change (CC#0x40 branch)
;   Callees:     none
;
;   Inputs:
;     AL  --  MIDI channel
;     CL  --  controller value (0 = pedal up, !=0 = pedal down)
;
;   Outputs:     none
;
;   Touches:     all caller registers preserved (saves BX/SI)
;
;   Side effects:
;     ps1_ch_cc40[ch] <- CL.
;     If CL == 0: for each voice on this channel with sustain=1,
;     sustain <- 0 and held <- 1 (defers actual release to slot 3).
; ----------------------------------------------------------------------------
ps1_cc40_sustain_apply     PROC NEAR
                PUSH    BX
                PUSH    SI
                MOV     SI, AX
                AND     SI, 00FFH
                MOV     CS:[SI + ps1_ch_cc40], CL
                CMP     CL, 0
                JNE     SHORT cc40_done
                MOV     BX, 0
cc40_scan:      CMP     CS:[BX + ps1_voice_channel], AL
                JNE     SHORT cc40_next
                CMP     BYTE PTR CS:[BX + ps1_voice_sustain], 0
                JE      SHORT cc40_next
                MOV     BYTE PTR CS:[BX + ps1_voice_sustain], 0
                MOV     BYTE PTR CS:[BX + ps1_voice_held], 1
cc40_next:      INC     BX
                CMP     BX, 3
                JNE     SHORT cc40_scan
cc40_done:      POP     SI
                POP     BX
                RET
ps1_cc40_sustain_apply     ENDP


; ----------------------------------------------------------------------------
; 0x0C0D  --  ps1_voice_commit_note
;
;   Commit a freshly-allocated (or re-triggered) voice. Steps:
;     1. Stamp ps1_voice_note[v] and zero the per-voice counters
;        (held / pos / dur / inst_lo / inst_hi).
;     2. Bump the channel's poly_active and call ps1_lru_rotate to
;        move this voice to the most-recently-used slot.
;     3. Look up the channel's current program, dereference into
;        ps1_patch_bank to get this voice's note-table base pointer.
;     4. Convert the MIDI velocity into a 4-bit attenuation via
;        ps1_vel_curve_b (with the `-2` offset quirk).
;     5. Call ps1_psg_write_freq -> writes the PSG with the initial
;        frequency for this note.
;
;   Type:        Internal helper (voice setup)
;   Category:    Voice management
;   Callers:     ps1_midi_note (both the retrigger and fresh-allocate paths)
;   Callees:     ps1_lru_rotate, ps1_psg_write_freq
;
;   Inputs:
;     BX  --  voice index (0..2)
;     AL  --  MIDI channel
;     CH  --  MIDI note number
;     CL  --  MIDI velocity (0..127); 0 path is dead-handled by caller
;
;   Outputs:     none
;
;   Touches:     all caller registers preserved (saves SI/DX)
;
;   Side effects:
;     ps1_voice_note[v]       <- CH
;     ps1_voice_held[v]       <- 0
;     ps1_voice_pos[v]        <- 0
;     ps1_voice_dur[v]        <- 0
;     ps1_voice_inst_lo[v]    <- 0
;     ps1_voice_inst_hi[v]    <- 0
;     ps1_voice_note_tbl[v]   <- &ps1_patch_bank[bank_index]
;     ps1_voice_vel[v]        <- ps1_vel_curve_b[(vel>>3) - 2]
;     ps1_ch_poly_active[ch]  <- +1
;     ps1_lru_rotate(v) updates ps1_voice_lru.
;     ps1_psg_write_freq writes 2 bytes to PS1_PORT_DATA.
; ----------------------------------------------------------------------------
ps1_voice_commit_note     PROC NEAR
                PUSH    SI
                PUSH    DX

                MOV     CS:[BX + ps1_voice_note], CH
                MOV     BYTE PTR CS:[BX + ps1_voice_held], 0
                MOV     BYTE PTR CS:[BX + ps1_voice_pos], 0
                MOV     BYTE PTR CS:[BX + ps1_voice_dur], 0

                SHL     BX, 1
                MOV     WORD PTR CS:[BX + ps1_voice_inst_lo], 0
                MOV     WORD PTR CS:[BX + ps1_voice_inst_hi], 0
                SHR     BX, 1

                MOV     DL, CS:[BX + ps1_voice_channel]
                XOR     DH, DH
                MOV     SI, DX
                MOV     DL, CS:[SI + ps1_ch_volume]
                XOR     DH, DH
                INC     BYTE PTR CS:[SI + ps1_ch_poly_active]
                CALL    ps1_lru_rotate

                PUSH    DX
                MOV     DL, CS:[SI + ps1_ch_program]
                XOR     DH, DH
                MOV     SI, DX
                SHL     SI, 1
                MOV     DX, WORD PTR CS:[SI + ps1_patch_bank]
                ADD     DX, OFFSET ps1_patch_bank  ; absolute offset
                SHL     BX, 1
                MOV     CS:[BX + ps1_voice_note_tbl], DX
                SHR     BX, 1
                POP     DX
                PUSH    SI

                CMP     CL, 0
                JE      SHORT cmtn_no_vel
                SHR     CL, 1
                SHR     CL, 1
                SHR     CL, 1
                MOV     SI, CX
                AND     SI, 00FFH
                ; The original uses base = vel_curve_b - 2 here. With
                ; SI in [2..15] (CL>>3 where CL was >0), this hits the
                ; same bytes as `[SI-2 + ps1_vel_curve_b]`; with SI=0/1
                ; the read straddles into the last 2 bytes of curve_a.
                MOV     CL, CS:[SI + ps1_vel_curve_b - 2]
cmtn_no_vel:    MOV     CS:[BX + ps1_voice_vel], CL
                POP     SI
                CALL    ps1_psg_write_freq

                POP     DX
                POP     SI
                RET
ps1_voice_commit_note     ENDP


; ----------------------------------------------------------------------------
; 0x0C92  --  ps1_voice_release
;
;   The voice "tear-down" / silence path. Zeroes all per-voice state for
;   the voice in BX, calls ps1_voice_emit_volume (re-stripes the channel
;   volume; with vel/note cleared this writes attenuation 15 to the PSG,
;   silencing the channel), runs the LRU rotation, and decrements the
;   channel's poly_active counter.
;
;   The function was historically misnamed "voice_keyon"; it is in fact
;   the release/tear-down path.
;
;   Type:        Internal helper (voice management)
;   Category:    Voice management
;   Callers:     ps1_midi_note (retrigger path), ps1_midi_control_change
;                (CC#0x7B), ps1_voice_allocate (steal path), ps1_pool_claim,
;                ps1_pool_release, ps1_silence_and_reset (note-table EOT)
;   Callees:     ps1_voice_emit_volume, ps1_lru_rotate
;
;   Inputs:
;     BX  --  voice index (0..2)
;
;   Outputs:     none
;
;   Touches:     all caller registers preserved (saves BX/DI/SI)
;
;   Side effects:
;     ps1_voice_vel[v]     <- 0
;     ps1_voice_note[v]    <- 0xFF
;     ps1_voice_sustain[v] <- 0
;     ps1_voice_held[v]    <- 0
;     ps1_voice_pos[v]     <- 0
;     ps1_voice_dur[v]     <- 0
;     ps1_voice_last[v]    <- 0
;     ps1_voice_inst_lo[v] <- 0
;     ps1_voice_inst_hi[v] <- 0
;     ps1_voice_emit_volume writes PSG attenuation byte (silent).
;     ps1_lru_rotate moves this voice to MRU.
;     ps1_ch_poly_active[ch] -= 1.
; ----------------------------------------------------------------------------
ps1_voice_release PROC NEAR
                PUSH    BX
                PUSH    DI
                PUSH    SI
                MOV     BYTE PTR CS:[BX + ps1_voice_vel], 0
                MOV     BYTE PTR CS:[BX + ps1_voice_note], 0FFH
                MOV     BYTE PTR CS:[BX + ps1_voice_sustain], 0
                MOV     BYTE PTR CS:[BX + ps1_voice_held], 0
                MOV     BYTE PTR CS:[BX + ps1_voice_pos], 0
                MOV     BYTE PTR CS:[BX + ps1_voice_dur], 0
                MOV     BYTE PTR CS:[BX + ps1_voice_last], 0
                SHL     BX, 1
                MOV     WORD PTR CS:[BX + ps1_voice_inst_lo], 0
                MOV     WORD PTR CS:[BX + ps1_voice_inst_hi], 0
                SHR     BX, 1
                MOV     DI, BX
                CALL    ps1_voice_emit_volume
                CALL    ps1_lru_rotate
                MOV     DL, CS:[BX + ps1_voice_channel]
                XOR     DH, DH
                MOV     SI, DX
                DEC     BYTE PTR CS:[SI + ps1_ch_poly_active]
                POP     SI
                POP     DI
                POP     BX
                RET
ps1_voice_release ENDP


; ----------------------------------------------------------------------------
; 0x0CEB  --  ps1_lru_rotate
;
;   Move the voice index in BL to the most-recently-used slot of the LRU
;   queue (ps1_voice_lru[2]). Shifts the queue down to fill the gap.
;   Does NOT touch the PSG -- it's a pure in-memory bookkeeping helper.
;
;   The function was historically misnamed "psg_write"; it has been
;   renamed to ps1_lru_rotate to match its actual job. The bytes are
;   unchanged.
;
;   Type:        Internal helper (LRU bookkeeping)
;   Category:    Voice management
;   Callers:     ps1_voice_commit_note, ps1_voice_release
;   Callees:     none
;
;   Inputs:
;     BL  --  voice index to move to MRU position
;
;   Outputs:     BH zeroed; otherwise none.
;
;   Touches:     SI and AX are saved+restored.
;
;   Side effects:
;     ps1_voice_lru[0..2] permuted so that BL appears in slot 2;
;     the voices it displaced shift down by one.
; ----------------------------------------------------------------------------
ps1_lru_rotate   PROC NEAR
                PUSH    SI
                PUSH    AX
                XOR     SI, SI
                JMP     SHORT lrot_test
lrot_match:     CMP     CS:[SI + ps1_voice_lru], BL
                JNE     SHORT lrot_next
                JMP     SHORT lrot_inner_test
lrot_inner_body:
                MOV     AH, CS:[SI + 1 + ps1_voice_lru]
                MOV     CS:[SI + ps1_voice_lru], AH
                INC     SI
lrot_inner_test:
                CMP     SI, 2
                JB      SHORT lrot_inner_body
lrot_next:      INC     SI
lrot_test:      CMP     SI, 3
                JB      SHORT lrot_match
                XOR     BH, BH
                MOV     CS:[ps1_voice_lru + 2], BL
                POP     AX
                POP     SI
                RET
ps1_lru_rotate   ENDP


; ----------------------------------------------------------------------------
; 0x0D1A  --  ps1_psg_write_freq
;
;   Compute and ship the 10-bit PSG divisor for this voice's current
;   note. Steps:
;     1. Clamp the note into the table range [0x2D, 0x77] by adding /
;        subtracting 0x0C (one octave) until in range.
;     2. Index ps1_freq_table (4 sub-entries per semitone for bend
;        resolution).
;     3. Apply the channel's quantised pitch-bend offset via
;        ps1_pitchbend_apply.
;     4. Split the 10-bit divisor into low 4 bits and high 6 bits.
;     5. Write the "first byte" (channel-select + low-4) to
;        PS1_PORT_DATA; wait ~255 LOOP cycles for the chip to latch;
;        then write the "second byte" (high 6 bits).
;
;   Type:        Internal helper (PSG I/O)
;   Category:    PSG I/O
;   Callers:     ps1_midi_pitch_bend, ps1_voice_commit_note
;   Callees:     ps1_pitchbend_apply
;
;   Inputs:
;     BX  --  voice index (0..2)
;
;   Outputs:     none
;
;   Touches:     all caller registers preserved (saves AX/BX/CX/DX/SI/DI)
;
;   Side effects:
;     2 bytes written to PS1_PORT_DATA (PSG tone-frequency first/second
;     byte pair, channel = BX, divisor = freq_table[idx] with bend).
;
;   Notes:
;     The inter-byte LOOP delay matches the PSG's "wait for last byte
;     to latch" timing.
; ----------------------------------------------------------------------------
ps1_psg_write_freq     PROC NEAR
                PUSH    AX
                PUSH    BX
                PUSH    CX
                PUSH    DX
                PUSH    SI
                PUSH    DI

                XOR     DH, DH
                MOV     DL, CS:[BX + ps1_voice_note]
                MOV     DI, BX
                CMP     DL, 2DH
                JAE     SHORT pwrf_hi_test
pwrf_oct_up:    ADD     DL, 0CH
                CMP     DL, 2DH
                JB      SHORT pwrf_oct_up
pwrf_hi_test:   CMP     DL, 77H
                JBE     SHORT pwrf_in_range
pwrf_oct_dn:    SUB     DL, 0CH
                CMP     DL, 77H
                JA      SHORT pwrf_oct_dn

pwrf_in_range:  MOV     AX, DI
                MOV     CL, 5
                SHL     AX, CL
                OR      AL, 80H
                SUB     DX, 2DH
                SHL     DX, 1
                SHL     DX, 1
                PUSH    DI
                PUSH    AX
                MOV     AL, CS:[DI + ps1_voice_channel]
                XOR     AH, AH
                MOV     DI, AX
                CALL    ps1_pitchbend_apply
                POP     AX
                POP     DI
                SHL     DX, 1
                PUSH    DI
                MOV     DI, DX
                MOV     BX, CS:[DI + ps1_freq_table]
                POP     DI
                MOV     CX, BX
                XOR     BH, BH
                AND     BL, 0FH
                PUSH    BX
                MOV     BX, CX
                SHR     BX, 1
                SHR     BX, 1
                SHR     BX, 1
                SHR     BX, 1
                MOV     CX, BX
                POP     BX
                AND     CL, 3FH
                OR      AL, BL

                MOV     DX, PS1_PORT_DATA
                OUT     DX, AL

                PUSH    CX
                MOV     CX, 00FFH
pwrf_delay:     NOP
                LOOP    pwrf_delay
                POP     CX

                MOV     AL, CL
                OUT     DX, AL

                POP     DI
                POP     SI
                POP     DX
                POP     CX
                POP     BX
                POP     AX
                RET
ps1_psg_write_freq     ENDP


; ----------------------------------------------------------------------------
; 0x0D9D  --  ps1_pitchbend_apply
;
;   Adjust the freq-table sub-step index in DX by the per-channel pitch-
;   bend offset (ps1_ch_pb_amount[ch]). The direction byte
;   (ps1_ch_pb_dir[ch]) chooses add (1 = up) or subtract (0 = down).
;   Underflow (DX > 0xF000 after subtract) is clamped to 0; overflow
;   (DX > 0x1AF) is clamped to 0x1AF (the table covers 432 sub-entries).
;
;   Type:        Internal helper (pitch-bend)
;   Category:    PSG I/O
;   Callers:     ps1_psg_write_freq
;   Callees:     none
;
;   Inputs:
;     DX  --  raw freq-table sub-step index (before bend)
;     DI  --  MIDI channel (used to index ps1_ch_pb_amount / ps1_ch_pb_dir)
;
;   Outputs:
;     DX  --  bent and clamped sub-step index
;
;   Touches:     CX saved+restored.
; ----------------------------------------------------------------------------
ps1_pitchbend_apply     PROC NEAR
                PUSH    CX
                XOR     CH, CH
                MOV     CL, CS:[DI + ps1_ch_pb_amount]
                CMP     BYTE PTR CS:[DI + ps1_ch_pb_dir], 1
                JNE     SHORT pbap_sub
                ADD     DX, CX
                JMP     SHORT pbap_clamp
pbap_sub:       SUB     DX, CX
pbap_clamp:     CMP     DX, 0F000H
                JBE     SHORT pbap_hi_test
                MOV     DX, 0
                JMP     SHORT pbap_done
pbap_hi_test:   CMP     DX, 01AFH
                JBE     SHORT pbap_done
                MOV     DX, 01AFH
pbap_done:      POP     CX
                RET
ps1_pitchbend_apply     ENDP


; ----------------------------------------------------------------------------
; 0x0DC9  --  ps1_slot3_handler  (slot 3)
;
;   The periodic per-voice tick. The game calls this from its sequencer
;   interrupt; the driver advances each voice's note-table cursor and
;   re-stripes its volume. Specifically, for each voice with
;   ps1_voice_note != 0xFF:
;     - inst_lo (low half of the "age" word) is incremented; if the
;       "held" flag is set, inst_hi is also incremented so held voices
;       sort to the top of the age key used by ps1_pool_release.
;     - ps1_silence_and_reset steps the note-table cursor (driving the
;       per-note duration timer).
;     - ps1_voice_emit_volume re-stripes the PSG attenuation for this
;       voice (so any change in CC#7 / master volume takes effect).
;
;   PS/1 is unique among the DUDE drivers in that slot 3 has a real
;   body; ADL/SBP/M32 stub it as a no-op.
;
;   Type:        Slot handler
;   Category:    Periodic tick
;   Dispatch:    Slot 3 (called as: BP=3; no other inputs)
;   Callers:     Game (via dispatch, from the sequencer ISR)
;   Callees:     ps1_silence_and_reset, ps1_voice_emit_volume
;
;   Inputs:      none
;
;   Outputs:     none
;
;   Touches:     all caller registers preserved (saves SI/DI)
;
;   Side effects:
;     For every playing voice: bumps age word, possibly advances note
;     position (which can in turn ps1_voice_release if the note table
;     terminated), and writes one PSG attenuation byte.
; ----------------------------------------------------------------------------
ps1_slot3_handler PROC NEAR
                PUSH    SI
                PUSH    DI
                MOV     DI, 0
sh3_loop:       CMP     BYTE PTR CS:[DI + ps1_voice_note], 0FFH
                JE      SHORT sh3_next
                SHL     DI, 1
                INC     WORD PTR CS:[DI + ps1_voice_inst_lo]
                SHR     DI, 1
                CMP     BYTE PTR CS:[DI + ps1_voice_held], 0
                JE      SHORT sh3_after_held
                SHL     DI, 1
                INC     WORD PTR CS:[DI + ps1_voice_inst_hi]
                SHR     DI, 1
sh3_after_held: CALL    ps1_silence_and_reset
                CALL    ps1_voice_emit_volume
sh3_next:       INC     DI
                CMP     DI, 3
                JNE     SHORT sh3_loop
                POP     DI
                POP     SI
                RET
ps1_slot3_handler ENDP


; ----------------------------------------------------------------------------
; 0x0DFF  --  ps1_silence_and_reset
;
;   Note-table step. Each voice has a pointer into its program's note-
;   table (a packed `(note, duration)` byte pair stream terminated by a
;   0xFF note byte). On every tick this function:
;     - decrements ps1_voice_dur; while > 0, do nothing else.
;     - when dur hits 0 (or the special 0xFE sentinel + held=0), pull
;       the next `(note, duration)` word out of the table at
;       ps1_voice_note_tbl + ps1_voice_pos and advance pos by 2.
;     - if the new note byte is 0xFF (end of table), call
;       ps1_voice_release to silence the voice.
;     - otherwise stash the new note in ps1_voice_last (so
;       ps1_voice_emit_volume knows what to ship).
;
;   Type:        Internal helper (note-table stepper)
;   Category:    Periodic tick
;   Callers:     ps1_slot3_handler
;   Callees:     ps1_voice_release  (only on end-of-table)
;
;   Inputs:
;     DI  --  voice index (0..2)
;
;   Outputs:     none
;
;   Touches:     SI/BX saved+restored (inside the sr_run branch).
;
;   Side effects:
;     ps1_voice_dur[v]  decremented or refilled from the table.
;     ps1_voice_pos[v]  advanced by 2 when a new (note, dur) pair is
;                       pulled.
;     ps1_voice_last[v] <- new note byte (when it changes).
;     On end-of-table: full ps1_voice_release tear-down.
; ----------------------------------------------------------------------------
ps1_silence_and_reset PROC NEAR
                CMP     BYTE PTR CS:[DI + ps1_voice_dur], 0
                JE      SHORT sr_run
                CMP     BYTE PTR CS:[DI + ps1_voice_dur], 0FEH
                JE      SHORT sr_held_q
                DEC     BYTE PTR CS:[DI + ps1_voice_dur]
                RET
sr_held_q:      CMP     BYTE PTR CS:[DI + ps1_voice_held], 0
                JNE     SHORT sr_run2
                RET
sr_run2:        MOV     BYTE PTR CS:[DI + ps1_voice_dur], 0
sr_run:         PUSH    SI
                PUSH    BX
                MOV     BL, CS:[DI + ps1_voice_pos]
                MOV     BH, 0
                MOV     SI, BX
                SHL     DI, 1
                MOV     BX, CS:[DI + ps1_voice_note_tbl]
                SHR     DI, 1
                MOV     CX, CS:[BX + SI]
                INC     SI
                INC     SI
                CMP     CL, 0FFH
                JNE     SHORT sr_no_eot
                MOV     CX, 0
                PUSH    BX
                MOV     BX, DI
                CALL    ps1_voice_release
                POP     BX
                DEC     SI
                DEC     SI
sr_no_eot:      MOV     BX, SI
                MOV     CS:[DI + ps1_voice_pos], BL
                MOV     CS:[DI + ps1_voice_dur], CH
                CMP     CL, CS:[DI + ps1_voice_last]
                JE      SHORT sr_skip_emit
                MOV     CS:[DI + ps1_voice_last], CL
sr_skip_emit:   POP     BX
                POP     SI
                RET
ps1_silence_and_reset ENDP


; ----------------------------------------------------------------------------
; 0x0E69  --  ps1_voice_emit_volume
;
;   Compute the 4-bit PSG attenuation for this voice and ship a single
;   byte to PS1_PORT_DATA (the "attenuation" register for the voice's
;   tone channel).
;
;   The attenuation is a product of four 0..15 factors, computed as a
;   chain of MUL CL / DIV 15 stages:
;     factor1 = ps1_voice_vel[v]
;     factor2 = ps1_ch_volume[ch]                  (CC#7)
;     factor3 = ps1_voice_last[v]                  (per-note dynamic)
;     factor4 = ps1_master_volume                  (slot 12)
;   If any factor is 0, the output is 0 (silent). If the master enable
;   flag is 0, we override to 0 unconditionally. The product is then
;   used to index ps1_vel_curve_b + 0x0E for a final 0..15 attenuation,
;   inverted (0xF - x) because PSG attenuation is "loss" not gain.
;
;   Type:        Internal helper (PSG I/O)
;   Category:    PSG I/O
;   Callers:     ps1_voice_commit_note, ps1_voice_release,
;                ps1_slot3_handler
;   Callees:     none (writes PSG directly)
;
;   Inputs:
;     DI  --  voice index (0..2)
;
;   Outputs:     none
;
;   Touches:     all caller registers preserved (saves AX/BX/CX/DX/SI)
;
;   Side effects:
;     1 byte written to PS1_PORT_DATA (PSG attenuation register for
;     voice DI: top bits = (DI<<5)|0x90, low 4 = computed attenuation).
; ----------------------------------------------------------------------------
ps1_voice_emit_volume     PROC NEAR
                PUSH    AX
                PUSH    BX
                PUSH    CX
                PUSH    DX
                PUSH    SI

                MOV     CL, CS:[DI + ps1_voice_channel]
                XOR     CH, CH
                MOV     SI, CX
                MOV     CL, CS:[SI + ps1_ch_volume]
                MOV     AL, CS:[DI + ps1_voice_vel]
                CMP     CL, 0
                JNE     SHORT e69_have_cc7
                XOR     AL, AL
                JMP     SHORT e69_emit
e69_have_cc7:   CMP     AL, 0
                JNE     SHORT e69_mul1
                XOR     AL, AL
                JMP     SHORT e69_emit
e69_mul1:       MUL     CL
                MOV     CL, 0FH
                DIV     CL
                MOV     CL, CS:[DI + ps1_voice_last]
                CMP     CL, 0
                JNE     SHORT e69_mul2
                XOR     AL, AL
                JMP     SHORT e69_emit
e69_mul2:       MUL     CL
                MOV     CL, 0FH
                DIV     CL
                MOV     CX, CS:[ps1_master_volume]
                CMP     CL, 0
                JNE     SHORT e69_mul3
                XOR     AL, AL
                JMP     SHORT e69_emit
e69_mul3:       MUL     CL
                MOV     CL, 0FH
                DIV     CL
                CMP     AL, 0
                JNE     SHORT e69_emit
                INC     AL
e69_emit:       CMP     BYTE PTR CS:[ps1_master_enable], 0
                JNE     SHORT e69_have_enable
                MOV     AL, 0
e69_have_enable:
                PUSH    SI
                XOR     AH, AH
                MOV     SI, AX
                MOV     AL, CS:[SI + ps1_vel_curve_b + 0EH]
                POP     SI
                MOV     DH, AL
                MOV     AL, 0FH
                SUB     AL, DH
                MOV     CL, 5
                MOV     DX, DI
                SHL     DL, CL
                OR      DL, 90H
                OR      DL, AL
                MOV     AL, DL
                PUSH    DX
                MOV     DX, PS1_PORT_DATA
                OUT     DX, AL
                POP     DX

                POP     SI
                POP     DX
                POP     CX
                POP     BX
                POP     AX
                RET
ps1_voice_emit_volume     ENDP


; ----------------------------------------------------------------------------
; 0x0EFA  --  ps1_query_state  (slot 17)
;
;   The read-side of the setter ABI. AH selects a "class"; CH/CL further
;   qualify when needed.
;     AH = 0xE0  -> ps1_ch_pitchbend[AL]    (word)
;     AH = 0xC0  -> ps1_ch_program[AL]      (byte)
;     AH = 0xB0  -> further dispatch on CH:
;                     CH = 0x07  -> ps1_ch_volume[AL]
;                     CH = 0x0A  -> ps1_ch_poly_active[AL]  (see quirk note)
;                     CH = 0x40  -> ps1_ch_cc40[AL]
;                     CH = 0x4B  -> ps1_ch_pool[AL] (or count of voices
;                                   in this channel's pool, if CL=0xFF)
;     other      -> AX = 0xFFFF
;
;   Type:        Slot handler
;   Category:    Query
;   Dispatch:    Slot 17 (called as: BP=17, AH=class, AL=channel, CH/CL=sub-id)
;   Callers:     Game (via dispatch)
;   Callees:     none
;
;   Inputs:
;     AH  --  query class (0xE0 / 0xC0 / 0xB0 -> dispatched)
;     AL  --  MIDI channel
;     CH  --  sub-id for AH = 0xB0 class
;     CL  --  further qualifier for AH = 0xB0 / CH = 0x4B (0xFF -> count)
;
;   Outputs:
;     AX  --  queried value, or 0xFFFF on "unknown query"
;
;   Touches:     SI saved+restored.
;
;   Notes:
;     AH=0xB0/CH=0x0A nominally reads "pan" but the original reads
;     ps1_ch_poly_active instead. See the inline quirk comment.
; ----------------------------------------------------------------------------
ps1_query_state PROC NEAR
                PUSH    SI
                MOV     SI, AX
                AND     SI, 00FFH
                CMP     AH, 0E0H
                JNE     SHORT q_c0
                SHL     SI, 1
                MOV     AX, CS:[SI + ps1_ch_pitchbend]
                JMP     SHORT q_done
q_c0:           CMP     AH, 0C0H
                JNE     SHORT q_b0
                MOV     AL, CS:[SI + ps1_ch_program]
                JMP     SHORT q_done
q_b0:           CMP     AH, 0B0H
                JNE     SHORT q_unknown
                CMP     CH, 7
                JNE     SHORT q_b0_0a
                MOV     AL, CS:[SI + ps1_ch_volume]
                JMP     SHORT q_done
q_b0_0a:        CMP     CH, 0AH
                JNE     SHORT q_b0_40
                ; Likely-quirk: AH=B0 CH=0A (CC#10, pan) is documented
                ; as "pan", but the original reads ps1_ch_poly_active
                ; (0x781) rather than ps1_ch_pan (0x6C8). Preserved.
                MOV     AL, CS:[SI + ps1_ch_poly_active]
                JMP     SHORT q_done
q_b0_40:        CMP     CH, 40H
                JNE     SHORT q_b0_4b
                MOV     AL, CS:[SI + ps1_ch_cc40]
                JMP     SHORT q_done
q_b0_4b:        CMP     CH, 4BH
                JNE     SHORT q_unknown
                CMP     CL, 0FFH
                JZ      SHORT q_count_voices
                MOV     AL, CS:[SI + ps1_ch_pool]
                JMP     SHORT q_done
q_count_voices: XOR     AH, AH
                XOR     SI, SI
q_count_loop:   CMP     CS:[SI + ps1_voice_pool_ch], AL
                JNE     SHORT q_count_next
                INC     AH
q_count_next:   INC     SI
                CMP     SI, 3
                JNE     SHORT q_count_loop
                MOV     AL, AH
                JMP     SHORT q_done
q_unknown:      MOV     AX, 0FFFFH
q_done:         POP     SI
                RET
ps1_query_state ENDP


; ----------------------------------------------------------------------------
; 0x0F71  --  ps1_load_patch_bank  (slot 1)
;
;   Copy the patch bank from the game's address ES:AX into our local
;   ps1_patch_bank buffer. The bank layout is:
;     - 256 bytes of word-pairs (the patch index)
;     - up to 40 per-patch byte streams, each terminated by 0xFF
;   The copy stops once 40 0xFF terminators have been seen.
;
;   Type:        Slot handler
;   Category:    Patch / bank management
;   Dispatch:    Slot 1 (called as: BP=1, ES:AX = far ptr to source bank)
;   Callers:     Game (via dispatch, typically once at song load)
;   Callees:     none
;
;   Inputs:
;     ES:AX --  far pointer to source patch bank
;
;   Outputs:
;     AX  --  0x0F71 (this function's offset; used by the game as a
;             liveness signature)
;     CL  --  1
;     CH  --  15
;
;   Touches:     SI saved+restored; BX/CX used as scratch.
;
;   Side effects:
;     ps1_patch_bank[0..N] overwritten with the bytes at ES:AX..ES:AX+N
;     where N runs until the 40th 0xFF byte.
; ----------------------------------------------------------------------------
ps1_load_patch_bank PROC NEAR
                PUSH    SI
                MOV     BX, AX
                XOR     SI, SI

lpb_word_loop:  MOV     CX, ES:[BX + SI]
                MOV     WORD PTR CS:[SI + ps1_patch_bank], CX
                ADD     SI, 2
                CMP     SI, 0100H
                JNE     SHORT lpb_word_loop

                XOR     CH, CH
lpb_byte_loop:  MOV     CL, ES:[BX + SI]
                MOV     CS:[SI + ps1_patch_bank], CL
                INC     SI
                CMP     CL, 0FFH
                JE      SHORT lpb_term
                JMP     SHORT lpb_byte_loop
lpb_term:       INC     CH
                CMP     CH, 28H
                JNE     SHORT lpb_byte_loop

                MOV     AX, 0F71H
                MOV     CL, 1
                MOV     CH, 0FH
                POP     SI
                RET
ps1_load_patch_bank ENDP


; ----------------------------------------------------------------------------
; 0x0FA9  --  ps1_get_info  (slot 0)
;
;   Driver capability probe. The game uses this as a sanity check during
;   sound-setup negotiation. Returns four constants describing this
;   driver's identity and slot count.
;
;   Type:        Slot handler
;   Category:    DUDE ABI
;   Dispatch:    Slot 0 (called as: BP=0; no other inputs)
;   Callers:     Game (via dispatch)
;   Callees:     none
;
;   Inputs:      none
;
;   Outputs:
;     AH = 1        --  driver-kind major (audio-output driver)
;     AL = 0x65     --  PS/1 sub-kind
;     CH = 0x13     --  max slot index = 19 (cross-driver convention)
;     CL = 3        --  number of tone channels (= 3 voices)
;
;   Touches:     AX and CX written; no others.
; ----------------------------------------------------------------------------
ps1_get_info    PROC NEAR
                MOV     AH, 1
                MOV     AL, 65H
                MOV     CH, 13H
                MOV     CL, 3
                RET
ps1_get_info    ENDP


; ============================================================================
; END-OF-FILE GLOSSARY
; ============================================================================
;
; This glossary expands the short list near the top of the file with the
; domain-specific concepts a reader needs to follow the function bodies
; above. (The short list at top covers acronyms only.)
;
; ----------------------------------------------------------------------------
; The IBM PS/1 Audio Card (1990)
;
;   A low-cost ISA add-in card shipped with the IBM PS/1 home-computer
;   line. It packages:
;     - a Texas Instruments SN76489 / SN76496-style PSG (programmable
;       sound generator) with 3 square-wave tone channels plus 1
;       noise channel,
;     - an 8-bit unsigned DAC for raw PCM, and
;     - a joystick / paddle interface.
;
;   The PSG family is the same lineage as the IBM PCjr and Tandy 1000
;   sound chips (and the Sega Master System / Game Gear). The chip is
;   monophonic per channel: each tone channel produces ONE square wave
;   at one frequency with one attenuation. Polyphony is achieved by
;   driving the 3 tone channels independently -- there are no
;   "operators" the way an FM synth has (so no envelope hardware, no
;   modulator/carrier pair, no waveform selector).
;
;   The card is documented in IBM's "PS/1 Audio/Joystick Card Technical
;   Reference" (1990); see also the VOGONS wiki PS/1 page for the
;   register-level details this driver depends on.
;
; ----------------------------------------------------------------------------
; PSG (SN76489/SN76496-style) programming model
;
;   PSG: Programmable Sound Generator. The chip is a black box behind a
;   SINGLE I/O port (this driver uses 0x205, PS/1 base + 5). The CPU
;   writes ONE byte at a time; the chip's response depends on the top
;   bit of the byte:
;
;     0x80 | (ch << 5) | low_4  -- "first byte" for tone/attenuation
;                                  channel ch in {0,1,2,3=noise} and
;                                  register {0=freq_lo, 1=att}.
;     0x00 | high_6             -- "second byte": high 6 bits of the
;                                  10-bit frequency divisor for the
;                                  last-addressed tone channel.
;
;   Tone frequency: a 10-bit divisor over a fixed clock.
;     freq_hz = clock_hz / (32 * divisor)
;   The 3 tone channels are addressable separately; this driver writes
;   the divisor as the (first byte) + (second byte) pair shown above.
;
;   Attenuation: 4-bit, 2 dB steps. 0 = full amplitude, 15 = silent
;   (-30 dB total). Each tone channel has its own attenuation register.
;
;   The driver maintains:
;     - PS1_PORT_DATA (= 0x205): the chip's only I/O port.
;     - ps1_freq_table (290 words): MIDI-note + bend-sub-step -> divisor.
;     - ps1_voice_*: per-voice shadow state, 3 entries each.
;     - ps1_voice_lru: the in-memory LRU queue used to pick which voice
;       to evict on overflow (the chip cannot tell us which channel is
;       "least recently played").
;
; ----------------------------------------------------------------------------
; The DUDE 18-slot BP-indexed dispatch (this driver's variant)
;
;   "DUDE" is Dynamix's universal sound-driver container. Every driver
;   exposes the same fixed ABI: ONE far entry point (here 0x07BD), with
;   BP holding a slot index in [0..17] and other registers carrying the
;   slot-specific arguments.
;
;   18 slots, in this driver:
;        0  get_info                    1  load_patch_bank
;        2  reset_voices                3  slot3_handler (real body!)
;        4  midi_note_off               5  midi_note (on)
;        6  -- (unused RET stub)        7  midi_control_change
;        8  midi_program_change         9  -- (unused)
;       10  midi_pitch_bend            11  set_global_param
;       12  set_master_volume          13  set_master_enable
;       14..16 -- (unused)             17  query_state
;
;   PS/1-specific quirks vs. the AdLib / Sound Blaster / MT-32 drivers:
;
;     (a) Slot 3 has a real function body (the per-voice tick). ADL/SBP/
;         M32 stub slot 3 as a no-op. The PS/1's lack of envelope
;         hardware forces the driver to step note tables in software,
;         and slot 3 is where that work happens.
;
;     (b) The dispatch trampoline pushes/pops DX across the inner
;         indirect CALL rather than BP (as ADL does). Functionally
;         equivalent -- just a different scratch register.
;
;     (c) The DUDE header's family-tag length is 1 (a single space
;         character ' '), not 4 ('dude') as in ADL/SBP/M32.
;
;   This driver advertises "DUDE v2.10" -- close to but distinct from
;   the v2.x versions in the sibling drivers; the wire-level slot ABI
;   is the same.
;
; ----------------------------------------------------------------------------
; Voice topology
;
;   "Voice" in this driver = one of the 3 PSG tone channels. A voice
;   has a 1:1 mapping to a hardware tone-frequency / tone-attenuation
;   pair, and each is fully described by the SOA arrays at 0x0738:
;
;     ps1_voice_channel[v]   -- which MIDI channel owns this voice
;                               (0xFF if idle).
;     ps1_voice_note[v]      -- the MIDI note currently sounding
;                               (0xFF if idle).
;     ps1_voice_sustain[v]   -- 1 = a note-off arrived but CC#64 is
;                               held, so release is deferred.
;     ps1_voice_held[v]      -- 1 = release armed for slot 3's tick to
;                               run.
;     ps1_voice_inst_lo[v]   -- low 16 bits of "voice age" key, used
;     ps1_voice_inst_hi[v]    -- high 16 bits (held voices age faster)
;                               by ps1_pool_release's eviction sort.
;     ps1_voice_note_tbl[v]  -- pointer into ps1_patch_bank for this
;                               voice's per-note (note, dur) stream.
;     ps1_voice_pos[v]       -- current byte index inside that stream.
;     ps1_voice_dur[v]       -- ticks remaining at the current note.
;     ps1_voice_last[v]      -- the note byte we most recently shipped
;                               (used by ps1_voice_emit_volume).
;     ps1_voice_vel[v]       -- final 4-bit attenuation factor.
;     ps1_voice_lru[0..2]    -- voices sorted oldest-first; slot 2 is
;                               most recently used.
;     ps1_voice_pool_ch[v]   -- which MIDI channel claimed this voice
;                               via its CC#0x4B pool budget; 0xFF if
;                               the voice is in the global pool.
;
;   A note-on (slot 5) flows roughly:
;     ps1_midi_note
;       -> ps1_voice_allocate          (find/steal a voice; sets channel)
;       -> ps1_voice_commit_note       (stamp state, load patch, set vel)
;          -> ps1_lru_rotate           (voice becomes MRU)
;          -> ps1_psg_write_freq       (writes 2 PSG bytes: freq pair)
;
;   The corresponding emission of attenuation happens on the periodic
;   tick (slot 3) via ps1_voice_emit_volume, OR immediately if the
;   release path is invoked (ps1_voice_release).
; ============================================================================


                END     _start
