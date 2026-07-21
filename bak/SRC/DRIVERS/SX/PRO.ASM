; ============================================================================
; Sx.SSM.PRO.bin -- Dynamix DUDE-format Pro AudioSpectrum sound driver, v2.24
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
; Sound Blaster, Roland MT-32, Pro AudioSpectrum, etc.) and picks the right
; one at runtime based on the user's "sound setup" choice.
;
; This file is the Pro AudioSpectrum (PAS) driver. The PAS card from Media
; Vision (1991) contains the same Yamaha FM-synthesis chip family as the
; AdLib (OPL2/YM3812 or stereo dual-OPL2) at I/O ports 0x388 and 0x38A.
;
; This driver is closely related to the AdLib driver (Sx.SSM.ADL.bin) because
; both use the same OPL chip family. The two main differences are:
;
;   1. STEREO. The PAS card has two OPL chips wired as left/right banks.
;      Every "OPL write" in this driver actually fans out to BOTH chips so
;      that voices can be panned across the stereo field. The dual-bank
;      port pair lives at 0x388/0x389 (bank A) and 0x38A/0x38B (bank B).
;
;   2. PAS DETECTION. When the patch bank is uploaded (slot 1), the driver
;      first probes for the Media Vision PAS Multiplex API via INT 0x2F,
;      function AX=0x4D56. If a PAS card is present, the multiplex returns
;      pointers to PAS-internal helpers; the driver stashes those at
;      pro_pas_handler_a and pro_pas_handler_b (the 8 zero bytes at offset
;      0x3E in the data section) and uses them for setup writes that
;      need to go through the PAS BIOS rather than directly to OPL ports.
;
; The high-level shape -- 18-slot dispatch ABI, 9 OPL voices, MIDI-style
; per-channel state, per-voice OPL register shadows -- is identical to the
; AdLib driver. If you understand adl.asm you can read this file as
; "adl.asm + stereo + PAS detect path".
; ----------------------------------------------------------------------------

; ----------------------------------------------------------------------------
; About the OPL2 (Yamaha YM3812) chip on the Pro AudioSpectrum
;
; The Pro AudioSpectrum (1991) and PAS+/PAS-16 (1992+) cards from Media
; Vision included a Yamaha FM-synthesis chip. The PAS shipped with a
; dual-OPL2 setup wired as left/right banks for true-stereo FM output --
; the same hardware idea that OPL3 would later integrate into a single chip.
; The driver below treats the card as "two OPL2s in parallel" rather than
; as an OPL3 -- there's no use of the OPL3-only "new mode" enable bit
; (reg 0x05 bit 0) anywhere in this code, and there's no waveform/operator
; addressing beyond the OPL2 range.
;
; Each OPL2 chip is a black box with about 250 internal 8-bit registers,
; exposed to the host CPU via two I/O ports:
;
;   port 0x388  (bank A index)  -- write the # of the register you want
;                                  to change on chip A
;   port 0x389  (bank A data)   -- write the new value for that register
;   port 0x38A  (bank B index)  -- same, for chip B
;   port 0x38B  (bank B data)
;
; A single write to one of the chip's internal registers is therefore a
; pair of OUT instructions: select the register, then send its value. The
; chip needs about 3.3 microseconds to absorb the index write and 23 us to
; absorb the data write -- on the 6-MHz 286 of the era that's "do about
; five dummy reads then move on". The code below uses an empty IN AL, DX
; loop for that delay; see pro_opl_write_a / pro_opl_write_b.
;
; Each chip produces sound by FM synthesis. It has 9 polyphonic "voices",
; meaning 9 different notes can be sounding at once. Each voice is built
; from a pair of "operators" -- think of an operator as a sine-wave
; oscillator with its own envelope (attack / decay / sustain / release)
; and amplitude. Within a voice, the two operators can be connected
; either:
;
;   modulator -> carrier (FM synthesis: op1's output modulates op2's freq)
;   modulator + carrier  (additive synthesis: both sounds simply sum)
;
; ...controlled by the "C0+v" register for that voice. The driver calls
; the latter mode "additive" (see pro_voice_additive).
;
; In addition, when PAS-stereo mode is enabled (pro_pas_mode_flag != 0),
; the per-voice "feedback" register at OPL 0xC0+v carries two new bits in
; this dual-chip setup:
;
;   bit 5  enables "left channel" routing  (chip A only)
;   bit 4  enables "right channel" routing (chip B only)
;
; The OPL write helpers pro_opl_write_a / pro_opl_write_b implicitly OR in
; the appropriate bit when the register is in the 0xC0..0xC8 range.
;
; Voice-to-operator mapping (same as AdLib):
;
;   voice 0  ->  ops  0,  3        voice 3  ->  ops  8, 11
;   voice 1  ->  ops  1,  4        voice 4  ->  ops  9, 12
;   voice 2  ->  ops  2,  5        voice 5  ->  ops 10, 13
;   voice 6  ->  ops 12, 15        voice 7  ->  ops 13, 16
;   voice 8  ->  ops 14, 17
;
; Most chip parameters live in one of these register groups. Each group
; spans 18 entries (one per operator), except 0xA0/0xB0/0xC0 which span 9:
;
;   0x01       Test register; bit 5 enables waveform-select reg
;   0x08       CSM + NOTE-SEL
;   0x20-0x35  AM/Vib/EG-type/KSR/freq-multiplier (per operator)
;   0x40-0x55  Key-Scale Level (KSL) and Total Level (TL) (per operator)
;   0x60-0x75  Attack Rate (AR) and Decay Rate (DR) (per operator)
;   0x80-0x95  Sustain Level (SL) and Release Rate (RR) (per operator)
;   0xA0-0xA8  Voice F-number low byte (per voice)
;   0xB0-0xB8  Voice F-number high bits + block (octave) + KEY-ON bit
;   0xBD       Rhythm mode + AM/Vib depth (global)
;   0xC0-0xC8  Per-voice feedback + algorithm bit (+ stereo bits in PAS)
;   0xE0-0xF5  Per-operator waveform selector
;
; For the full register-level reference, see Yamaha's YM3812 datasheet or
; the OPL chip page at moddingwiki.shikadi.net/wiki/OPL_chip.
; ----------------------------------------------------------------------------

; ----------------------------------------------------------------------------
; About the DUDE dispatch ABI
;
; "DUDE" is Dynamix's internal sound-driver format. Every Dynamix sound
; driver of this generation is a flat binary that begins with a header
; containing two magic numbers (0x87654321 and 0xFEDCBA98), the ASCII tag
; "dude", a human-readable device-name string, and a version tag. See the
; data section below for the literal layout.
;
; The game communicates with this driver in exactly one way: a far call
; into the dispatch trampoline at offset 0x196E. Before the call, the
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
;   PUSH BP
;   SHL  BP, 1                       ; index -> byte offset
;   MOV  BP, CS:[BP + pro_func_table]
;   CALL BP                          ; near call to the slot's handler
;   POP  BP
;   RETF                             ; far return to the game
;
; The handlers themselves are near procedures; the trampoline is the only
; thing that does a far return.
;
; The 18 slots in this driver:
;
;   Slot  0  pro_get_info                 -- returns AH/AL/CH/CL descriptor
;   Slot  1  pro_load_patch_bank          -- ES:AX = src; copies into bank,
;                                            probes PAS via INT 2F
;   Slot  2  pro_reset_voices             -- silence + reset both OPL banks
;                                            and the PAS handlers
;   Slot  3  pro_slot_unused_ret          -- (no-op stub)
;   Slot  4  pro_midi_note_off            -- AL=ch, CH=note
;   Slot  5  pro_midi_note                -- AL=ch, CH=note, CL=vel (0=off)
;   Slot  6  pro_slot_unused_ret          -- (no-op stub)
;   Slot  7  pro_midi_control_change      -- AL=ch, CH=cc, CL=val
;   Slot  8  pro_midi_program_change      -- AL=ch, CL=program
;   Slot  9  pro_slot_unused_ret          -- (no-op stub)
;   Slot 10  pro_midi_pitch_bend          -- AL=ch, CX=bend (BE-packed)
;   Slot 11  pro_set_global_param_146     -- CL=val (0xFF=query)
;   Slot 12  pro_set_master_volume        -- CL=val (0xFF=query)
;   Slot 13  pro_set_master_enable        -- CL=val (0xFF=query)
;   Slot 14  pro_slot_unused_ret          -- (no-op stub)
;   Slot 15  pro_slot_unused_ret          -- (no-op stub)
;   Slot 16  pro_slot_unused_ret          -- (no-op stub)
;   Slot 17  pro_query_state              -- read-side of the setter ABI
; ----------------------------------------------------------------------------

; ----------------------------------------------------------------------------
; How to read this source
;
; - Lines like `MOV BX, AX` are CPU instructions. The first operand is
;   the destination, the second is the source -- read it as "BX = AX".
;   This is "Intel" order; AT&T-style "MOV AX, BX" with destination
;   second is a different convention and is not used here.
;
; - Lines like `pro_voice_note    DB 9 DUP(0FFH)` declare data: the
;   label names this address, `DB` says "the following are bytes", and
;   `9 DUP(0FFH)` means "nine copies of the value 0xFF". `DW` is the
;   16-bit equivalent (two bytes per entry, little-endian on x86). `DD`
;   declares 32-bit doublewords -- used here for the PAS handler far
;   pointers (segment:offset, four bytes each).
;
; - `CS:[BX + label]` is a memory access where:
;     * `CS:` says "use the Code Segment register as the base"
;     * `[BX + label]` is the offset, computed at runtime as the contents
;       of register BX plus the constant `label`.
;   In this flat single-segment driver, every read/write uses CS: because
;   the data and code share one segment (the `.MODEL TINY` directive sets
;   that up). The PAS-handler indirect calls (CALL DWORD PTR CS:...)
;   are the one exception: they're far calls into PAS BIOS code that
;   lives outside this driver's segment.
;
; - Every function below begins with `<name> PROC NEAR` and ends with
;   `<name> ENDP`. Inside, labels like `mno_test:` are jump targets
;   local to that function (we prefix them with a 3-4-letter function
;   nickname so they don't collide with labels in other functions). The
;   nickname decoder mostly follows the function name initials:
;     mno  = midi_note_off       mn   = midi_note
;     cc   = midi_control_change pb   = midi_pitch_bend
;     smv  = set_master_volume   sme  = set_master_enable
;     rv   = reset_voices        va   = voice_allocate
;     spr  = sustain_pool_resize spd  = sustain_pool_drain
;     spres= sustain_pool_reserve sprl = sustain_pool_release
;     ccv  = cc_main_volume      ccp  = cc_pan
;     ccsp = cc_sustain_pedal    vkon = voice_keyon
;     vlru = voice_lru_remove    vrf  = voice_render_freq
;     vpb  = voice_pitchbend_apply vrv = voice_render_volume
;     vap  = voice_apply_patch   plw  = opl_write (plwa/plwb = _a/_b)
;     rh   = opl_write_rhythm    ns   = opl_write_notesel
;     fb   = opl_write_voice_feedback  fm = opl_write_op_flags_mult
;     wf   = opl_write_op_waveform  sar = silence_and_reset
;     qry  = query_state         lpb  = load_patch_bank
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
; - Indirect far calls (CALL DWORD PTR CS:pro_pas_handler_*) reach into
;   PAS BIOS-resident code through far pointers populated by the
;   slot-1 init path. The call passes arguments in registers per the
;   PAS Multiplex calling convention (BX = port-shifted register #,
;   CX = data, DX = sub-function code); see the PAS DOS Multiplex spec.
;
; - Example sites to look up the PAS-specific bits when reading the
;   code: pro_voice_render_volume (lines ~1370+) shows the full stereo
;   pan math; pro_load_patch_bank shows the INT 2F detection path; the
;   `OR CL, 20H` / `OR CL, 10H` inserts at the top of pro_opl_write_a /
;   pro_opl_write_b are where the L/R stereo bits get added to the
;   per-voice feedback register (0xC0..0xC8) writes.
; ----------------------------------------------------------------------------

                .8086
                .MODEL  TINY
                .CODE
                ORG     0

; ============================================================================
; 0x0000  --  DUDE header
; ============================================================================
_start          LABEL   BYTE
                JMP     pro_dispatch                ; E9 6B 19

                DB      0                           ; pad_03

dude_magic_a    DD      87654321H
dude_iface_ver  DB      1, 4
dude_tag        DB      'dude'

device_name_len DB      17
device_name     DB      'Pro AudioSpectrum'

dude_magic_b    DD      0FEDCBA98H
dude_driver_kind DD     3000H
driver_ver_str  DB      '2.24'

; ============================================================================
; 0x002C  --  Dual-OPL port table (9 words = 18 bytes)
;
;   The PAS card has two OPL2 chips wired as left/right banks. The first
;   three words at offsets 0x2C-0x31 appear to be informational/unused
;   (mirrored copies of the bank-A index/data ports). The actively-used
;   ports are at 0x32 (bank A index), 0x34 (bank A status), 0x36 (bank A
;   data), 0x38 (bank B index), 0x3A (bank B status), 0x3C (bank B data).
; ============================================================================
pro_port_info_a DW      0388H                   ; informational
pro_port_info_b DW      0388H
pro_port_info_c DW      0389H
pro_port_reg_a  DW      0388H                   ; bank A index/select port
pro_port_status_a DW    0388H                   ; bank A status port (read)
pro_port_data_a DW      0389H                   ; bank A data port
pro_port_reg_b  DW      038AH                   ; bank B index/select port
pro_port_status_b DW    038AH                   ; bank B status port (read)
pro_port_data_b DW      038BH                   ; bank B data port

; ============================================================================
; 0x003E  --  PAS handler far pointers (populated at runtime)
;
;   When pro_load_patch_bank (slot 1) probes for the Media Vision PAS
;   Multiplex via INT 2F (AH=0x4D, AL=0x56), and a PAS card is present,
;   the multiplex returns a pointer to a table of PAS-specific handler
;   far pointers. The driver stashes two of those handlers here:
;
;     pro_pas_handler_a (at 0x3E)  -- "PAS OPL write" handler. Called
;                                     from reset_voices / set_master_volume
;                                     when PAS mode is active to delegate
;                                     OPL register writes through the PAS
;                                     BIOS instead of going direct to ports.
;     pro_pas_handler_b (at 0x42)  -- "PAS init/setup" handler. Called
;                                     once during slot-1 init and once
;                                     during reset_voices.
;
;   On disk these are zero; they're only meaningful after slot 1 has run.
; ============================================================================
pro_pas_handler_a DD    0                       ; far ptr, populated runtime
pro_pas_handler_b DD    0                       ; far ptr, populated runtime

; ============================================================================
; 0x0046  --  OPL2 F-number table, 48 entries (each entry one WORD)
;
;   The OPL's pitch input is a 10-bit "F-number" plus a 3-bit "block"
;   (octave). Together they pick the actual frequency in Hz. The table
;   below gives one F-number per *note within an octave* -- but the
;   driver indexes it with `(midi_note * 4) mod 48`, not just
;   `midi_note mod 12`, so there are 4 F-numbers per semitone. That
;   extra resolution is used by pro_voice_pitchbend_apply to slide
;   smoothly between semitones when the channel's pitch wheel is
;   anywhere other than centered.
; ============================================================================
pro_note_fnum_table LABEL WORD
                DW      0157H, 015CH, 0161H, 0166H, 016BH, 0171H, 0176H, 017BH
                DW      0181H, 0186H, 018CH, 0192H, 0198H, 019EH, 01A4H, 01AAH
                DW      01B0H, 01B6H, 01BDH, 01C3H, 01CAH, 01D0H, 01D7H, 01DEH
                DW      01E5H, 01ECH, 01F3H, 01FAH, 0202H, 0209H, 0211H, 0218H
                DW      0220H, 0228H, 0230H, 0238H, 0241H, 0249H, 0252H, 025AH
                DW      0263H, 026CH, 0275H, 027EH, 0287H, 0290H, 029AH, 02A4H

; ============================================================================
; 0x00A6  --  volume curve A: 64-byte ascending TL ramp (0x00 .. 0x3F)
;
;   Identical to AdLib's volcurve_a. Maps a 6-bit linear "loudness index"
;   to an OPL "total level" attenuation.
; ============================================================================
pro_volcurve_a  DB      000H, 00CH, 00DH, 00EH, 00FH, 011H, 012H, 013H
                DB      014H, 016H, 017H, 018H, 01AH, 01BH, 01CH, 01DH
                DB      01FH, 020H, 021H, 022H, 023H, 024H, 025H, 026H
                DB      027H, 028H, 029H, 02AH, 02BH, 02DH, 02DH, 02EH
                DB      02FH, 030H, 031H, 032H, 032H, 033H, 034H, 034H
                DB      035H, 036H, 036H, 037H, 038H, 038H, 039H, 03AH
                DB      03BH, 03BH, 03BH, 03CH, 03CH, 03CH, 03DH, 03DH
                DB      03DH, 03EH, 03EH, 03EH, 03EH, 03FH, 03FH, 03FH

; ============================================================================
; 0x00E6  --  volume curve B: 64-byte velocity-to-TL lookup
;
;   Identical to AdLib's volcurve_b.
; ============================================================================
pro_volcurve_b  DB      000H, 014H, 015H, 016H, 017H, 018H, 019H, 01AH
                DB      01BH, 01CH, 01DH, 01EH, 01FH, 020H, 021H, 021H
                DB      022H, 023H, 024H, 025H, 026H, 027H, 028H, 029H
                DB      02AH, 02BH, 02CH, 02DH, 02EH, 02FH, 02FH, 030H
                DB      031H, 032H, 032H, 033H, 034H, 034H, 035H, 036H
                DB      036H, 037H, 038H, 038H, 039H, 039H, 03AH, 03AH
                DB      03BH, 03BH, 03BH, 03CH, 03CH, 03CH, 03DH, 03DH
                DB      03DH, 03EH, 03EH, 03EH, 03EH, 03FH, 03FH, 03FH

; ============================================================================
; 0x0126  --  pan-to-volume curve A (16 entries, left-channel ramp)
; 0x0136  --  pan-to-volume curve B (16 entries, right-channel ramp)
;
;   These two 16-entry tables aren't present in the AdLib driver. They're
;   used by the stereo voice-volume renderer (pro_voice_render_volume) to
;   compute per-bank attenuation when a voice is panned. They map a
;   4-bit "stereo position" index to a 7-bit volume scale; curve A
;   accelerates faster at low values (used for the bank that's facing
;   away from the pan), curve B is smoother (used for the bank facing
;   toward the pan).
; ============================================================================
pro_pan_curve_a DB      000H, 007H, 00DH, 014H, 01BH, 021H, 028H, 02FH
                DB      035H, 03CH, 043H, 049H, 050H, 057H, 05DH, 064H

pro_pan_curve_b DB      000H, 005H, 009H, 00DH, 012H, 016H, 01BH, 01FH
                DB      024H, 028H, 02DH, 031H, 039H, 03AH, 03EH, 043H

; ============================================================================
; 0x0146  --  global driver state (three scalar bytes)
; ============================================================================
pro_global_param_146 DB 000H                   ; (semantics unconfirmed)
pro_master_enable    DB 001H                   ; 0 = driver muted, 1 = on
pro_master_volume    DB 00FH                   ; master TL, 0..3F

; ============================================================================
; 0x0149..0x0198  --  per-MIDI-channel state, 16 channels x 5 arrays
; ============================================================================
pro_ch_program       DB 16 DUP(000H)           ; channel -> patch number
pro_ch_volume        DB 16 DUP(03FH)           ; channel -> volume (CC7/2)
pro_ch_pan           DB 16 DUP(040H)           ; channel -> pan (CC10)
pro_ch_sustain_pedal DB 16 DUP(000H)           ; channel -> sustain pedal
pro_ch_sustain_count DB 16 DUP(000H)           ; channel -> sustain pool debt

; ============================================================================
; 0x0199  --  per-channel pitch-bend (16 words)
; ============================================================================
pro_ch_pitchbend     DW 16 DUP(02000H)         ; channel -> bend (centered)

; ============================================================================
; 0x01B9..0x01EF  --  per-voice state (9-entry SOA arrays, 2-byte pads)
; ============================================================================
pro_voice_channel      DB 9 DUP(0FFH)          ; voice -> MIDI channel (FF=idle)
                       DB 2 DUP(0FFH)          ; pad_1c2
pro_voice_note         DB 9 DUP(0FFH)          ; voice -> MIDI note (FF=idle)
                       DB 2 DUP(0FFH)          ; pad_1cd
pro_voice_velocity     DB 9 DUP(000H)          ; voice -> velocity
                       DB 2 DUP(000H)          ; pad_1d8
pro_voice_sustain_held DB 9 DUP(000H)          ; voice -> release-deferred
                       DB 2 DUP(000H)          ; pad_1e3
pro_voice_program      DB 9 DUP(0FFH)          ; voice -> loaded patch #
                       DB 2 DUP(0FFH)          ; pad_1ee

; ============================================================================
; 0x01F0..0x0205  --  voice-allocator scratch (two 11-byte arrays)
; ============================================================================
pro_voice_lru          DB 000H, 001H, 002H, 003H, 004H, 005H
                       DB 006H, 007H, 008H, 009H, 00AH
pro_voice_sustain_ch   DB 11 DUP(0FFH)         ; voice -> reservation owner

; ============================================================================
; 0x0206..0x0226  --  per-channel polyphony budget + pas_mode flag
;
;   pro_pas_mode_flag at 0x226 is the single-byte runtime flag set by
;   pro_load_patch_bank when it detects a PAS card via INT 2F. When this
;   flag is set, several functions take the PAS-stereo code path
;   (writing the C0+v stereo bits, calling the PAS handlers, etc.).
; ============================================================================
pro_ch_poly_max        DB 16 DUP(000H)         ; channel -> max polyphony
pro_ch_poly_active     DB 16 DUP(000H)         ; channel -> active voices
pro_pas_mode_flag      DB 000H                 ; 0 = no PAS, 1 = PAS active

; ============================================================================
; 0x0227..0x0280  --  OPL2 operator-topology lookup tables (5 x 18 bytes)
; ============================================================================
pro_op_perm            DB 003H, 004H, 005H, 009H, 00AH, 00BH
                       DB 00FH, 010H, 011H, 000H, 001H, 002H
                       DB 006H, 007H, 008H, 00CH, 00DH, 00EH

pro_op_iscarrier       DB 000H, 000H, 000H, 001H, 001H, 001H
                       DB 000H, 000H, 000H, 001H, 001H, 001H
                       DB 000H, 000H, 000H, 001H, 001H, 001H

pro_op_regoff          DB 000H, 001H, 002H, 003H, 004H, 005H
                       DB 008H, 009H, 00AH, 00BH, 00CH, 00DH
                       DB 010H, 011H, 012H, 013H, 014H, 015H

pro_op_voice           DB 000H, 001H, 002H, 000H, 001H, 002H
                       DB 003H, 004H, 005H, 003H, 004H, 005H
                       DB 006H, 007H, 008H, 006H, 007H, 008H

pro_voice_oppair       DB 000H, 003H, 001H, 004H, 002H, 005H
                       DB 006H, 009H, 007H, 00AH, 008H, 00BH
                       DB 00CH, 00FH, 00DH, 010H, 00EH, 011H

; ============================================================================
; 0x0281 / 0x028F  --  default operator patches (14 bytes each)
; ============================================================================
pro_default_patch_mod  DB 001H, 001H, 003H, 00FH, 005H, 000H, 001H
                       DB 003H, 00FH, 000H, 000H, 000H, 001H, 000H

pro_default_patch_car  DB 000H, 001H, 001H, 00FH, 007H, 000H, 002H
                       DB 004H, 000H, 000H, 000H, 001H, 000H, 000H

; ============================================================================
; 0x029D..0x0398  --  OPL register shadow (252 bytes; 18 ops x 14 bytes)
; ============================================================================
pro_op_shadow          DB 252 DUP(000H)

; ============================================================================
; 0x0399  --  bank-size pseudo-instruction (a 4-byte oddity)
;
;   This is the "magic literal doubling as code" pattern. The byte 0xB8
;   at offset 0x39A is the opcode of `MOV AX, imm16`. It's never executed; the WORD at
;   0x39B is the bank-size constant that pro_load_patch_bank reads as
;   `CS:[pro_bank_size]`.
; ============================================================================
                       DB 000H                 ; pad_399
                       DB 0B8H                 ; (MOV AX opcode; dead code)
pro_bank_size          DW 01507H               ; 5383 = max bank payload

; ============================================================================
; 0x039D..0x1864  --  patch bank buffer (5320 bytes)
; ============================================================================
pro_bank_buf           DB 5320 DUP(000H)

; ============================================================================
; 0x1865  --  velocity-clamp LUT (62 bytes, all 0x3C)
; ============================================================================
pro_vel_to_tl_lut      DB 62 DUP(03CH)

; ============================================================================
; 0x18A3  --  patch staging buffer (13 bytes)
; ============================================================================
pro_patch_stage        DB 13 DUP(000H)

                       DB 000H                 ; pad_18b0

; ============================================================================
; 0x18B1..0x18B7  --  OPL chip-state mirrors
; ============================================================================
pro_opl_notesel        DB 000H                 ; reg 0x08 bit 6 mirror
pro_opl_amdepth        DB 000H                 ; reg 0xBD bit 7 mirror
pro_opl_vibdepth       DW 0000H                ; reg 0xBD bit 6 mirror (word)
pro_opl_rhythm         DB 000H                 ; reg 0xBD bits 5..0 mirror
pro_wave_select_en     DW 0000H                ; reg 0x01 bit 5 mirror

                       DB 3 DUP(000H)          ; pad_18b8

; ============================================================================
; 0x18BB..0x1949  --  per-voice OPL working tables
; ============================================================================
pro_voice_mod_tl_base  DW 11 DUP(0000H)        ; voice -> modulator TL base
pro_voice_mod_tl_max   DW 11 DUP(0000H)        ; voice -> 0x3F - mod KSL
pro_voice_mod_tl_step  DW 11 DUP(0000H)        ; voice -> mod_tl_max / 15
pro_voice_car_tl_base  DW 11 DUP(0000H)        ; voice -> carrier TL base
pro_voice_car_tl_max   DW 11 DUP(0000H)        ; voice -> 0x3F - car KSL
pro_voice_additive     DB 11 DUP(000H)         ; voice -> additive flag
pro_voice_car_tl_step  DW 11 DUP(0000H)        ; voice -> car_tl_max / 15

; ============================================================================
; 0x194A  --  dispatch function-pointer table (18 near pointers)
; ============================================================================
pro_func_table  LABEL   WORD
                DW      pro_get_info                 ; slot  0
                DW      pro_load_patch_bank          ; slot  1
                DW      pro_reset_voices             ; slot  2
                DW      pro_slot_unused_ret          ; slot  3
                DW      pro_midi_note_off            ; slot  4
                DW      pro_midi_note                ; slot  5
                DW      pro_slot_unused_ret          ; slot  6
                DW      pro_midi_control_change      ; slot  7
                DW      pro_midi_program_change      ; slot  8
                DW      pro_slot_unused_ret          ; slot  9
                DW      pro_midi_pitch_bend          ; slot 10
                DW      pro_set_global_param_146     ; slot 11
                DW      pro_set_master_volume        ; slot 12
                DW      pro_set_master_enable        ; slot 13
                DW      pro_slot_unused_ret          ; slot 14
                DW      pro_slot_unused_ret          ; slot 15
                DW      pro_slot_unused_ret          ; slot 16
                DW      pro_query_state              ; slot 17

; ----------------------------------------------------------------------------
; 0x196E  --  pro_dispatch  --  the trampoline
;
;   This is the ONLY entry point the game ever calls. The game does:
;
;       MOV  BP, <slot index>
;       <set up AL/CH/CL/etc per the slot's convention>
;       CALL FAR pro_seg:pro_dispatch
;
;   We:
;     - Save the slot index (the game expects BP preserved across the call)
;     - Convert slot index to byte offset by shifting left 1
;     - Look up the slot's handler pointer in pro_func_table
;     - Call the handler as a near function
;     - Restore BP and return far to the game
;
;   The trampoline itself is 12 bytes: PUSH (1) + SHL (2) + MOV (5) +
;   CALL (2) + POP (1) + RETF (1).
;
;   Type:        Trampoline
;   Category:    Dispatch
;   Callers:     Game (the sole external entry point)
;   Callees:     Whatever slot the BP-indexed table cell points to
;
;   Inputs:
;     BP  --  slot index 0..17 (the only "argument" common to all calls)
;     plus per-slot register conventions (AL = channel, CL/CH = data
;     bytes, ES:AX = far ptr for slot 1, ...). See the slot table in
;     the dispatch-ABI section above.
;
;   Outputs:     whatever the slot's handler returns
; ----------------------------------------------------------------------------
pro_dispatch    PROC    NEAR
                PUSH    BP                      ; save game's slot index
                SHL     BP, 1                   ; slot * 2 = byte offset
                MOV     BP, CS:[BP + pro_func_table]
                CALL    BP                      ; near call to slot handler
                POP     BP                      ; restore for the game
                RETF                            ; far return to game
pro_dispatch    ENDP

; ----------------------------------------------------------------------------
; 0x197A  --  pro_slot_unused_ret
;
;   A single-byte RET (opcode 0xC3). Shared by six "reserved but
;   unimplemented" slots (3, 6, 9, 14, 15, 16) in the function-pointer
;   table above. Calling any of them is a fast no-op.
;
;   Type:        Slot handler (stub)
;   Category:    Dispatch placeholder
;   Dispatch:    Slots 3, 6, 9, 14, 15, 16
;   Callers:     Game (via dispatch)
;   Callees:     none
;
;   Inputs:      ignored
;   Outputs:     none
; ----------------------------------------------------------------------------
pro_slot_unused_ret PROC NEAR
                RET
pro_slot_unused_ret ENDP

; ============================================================================
; FUNCTION BODIES below this line
;
; Each function gets a header block describing its role, the registers it
; consumes and produces, and what it modifies.
;
; Most PRO handlers are close relatives of their AdLib counterparts in
; adl.asm; the differences come from stereo (the dual-OPL write path
; through pro_opl_write_a / _b) and from the PAS Multiplex detection path
; in pro_load_patch_bank.
; ============================================================================

; ----------------------------------------------------------------------------
; 0x197B  --  pro_midi_note_off
;
;   The MIDI "note off" message. Tells the driver "stop playing this note
;   on this channel". The driver walks all 9 OPL voices looking for any
;   voice currently sounding the (channel, note) pair, and either:
;
;     - if the channel's sustain pedal is held, marks the voice as
;       "release deferred" so it'll keep ringing and only get released
;       when the pedal lifts (see pro_cc_sustain_pedal); or
;     - if no pedal, calls pro_voice_release to silence the voice now.
;
;   Multiple voices may match (chorus / unison patches); we keep looking
;   after the first match. The function is also called internally from
;   pro_midi_note when a "note on" with velocity 0 is received (per
;   MIDI's running-status convention).
;
;   Behaviour is identical to adl_midi_note_off; the actual silencing
;   work happens in pro_voice_release, which on PAS issues the OPL
;   key-off write through both bank A and bank B.
;
;   Type:        Slot handler
;   Category:    MIDI dispatch
;   Dispatch:    Slot 4 (called as: BP=4, AL=channel, CH=note)
;   Callers:     Game (via dispatch), pro_midi_note (slot 5 fallthrough)
;   Callees:     pro_voice_release
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
;       - if channel sustain pedal != 0: voice_sustain_held[v] <- 1
;       - else: pro_voice_release(v) -- which clears voice state and
;         writes both OPL banks to release the envelope.
; ----------------------------------------------------------------------------
pro_midi_note_off PROC    NEAR
                PUSH    BX
                PUSH    SI
                XOR     BX, BX
                JMP     SHORT mno_test
mno_body:       CMP     CS:[BX + pro_voice_channel], AL
                JNE     SHORT mno_next
                CMP     CS:[BX + pro_voice_note], CH
                JNE     SHORT mno_next
                MOV     SI, AX
                AND     SI, 00FFH
                CMP     BYTE PTR CS:[SI + pro_ch_sustain_pedal], 0
                JE      SHORT mno_release
                MOV     BYTE PTR CS:[BX + pro_voice_sustain_held], 1
                JMP     SHORT mno_next
mno_release:    CALL    pro_voice_release
mno_next:       INC     BX
mno_test:       CMP     BX, 9
                JB      SHORT mno_body
                POP     SI
                POP     BX
                RET
pro_midi_note_off ENDP

; ----------------------------------------------------------------------------
; 0x19B1  --  pro_midi_note
;
;   The MIDI "note on" message. By convention a note-on with velocity 0
;   means the same thing as a note-off, so this function handles both:
;
;     1. If CL (velocity) == 0, fall through to pro_midi_note_off and
;        return.
;     2. Otherwise, clamp the note to the playable range [0x0C, 0x6B]
;        and drop the request if it's out of range.
;     3. Halve the velocity (MIDI's 7-bit velocity becomes a 6-bit OPL
;        attenuation step).
;     4. Look for a voice already playing (this channel, this note).
;        If found, restart it cleanly: release then key-on with the
;        new velocity. This gives consistent attack on rapid retriggers.
;     5. Otherwise allocate a new voice via pro_voice_allocate. If no
;        voice is available (allocator returned 0xFF), drop the request
;        silently.
;     6. Key on the chosen voice via pro_voice_keyon.
;
;   Type:        Slot handler
;   Category:    MIDI dispatch
;   Dispatch:    Slot 5 (called as: BP=5, AL=channel, CH=note, CL=velocity)
;   Callers:     Game (via dispatch)
;   Callees:     pro_midi_note_off, pro_voice_release, pro_voice_keyon,
;                pro_voice_allocate
;
;   Inputs:
;     AL  --  MIDI channel (0..15)
;     CH  --  MIDI note number (0..127); clamped to [0x0C, 0x6B] except
;             on the percussion channel (which the keyon path handles).
;     CL  --  MIDI velocity (0..127); 0 means "note off"
;
;   Outputs:     none
;
;   Touches:     all caller registers preserved (saves BX, SI)
;
;   Side effects:
;     - Possibly assigns or steals a voice (changes voice_channel /
;       voice_note / voice_velocity / voice_program for that voice).
;     - Writes OPL registers on both PAS banks via the renderer chain
;       for key-on.
; ----------------------------------------------------------------------------
pro_midi_note   PROC    NEAR
                PUSH    BX
                PUSH    SI
                OR      CL, CL
                JNZ     SHORT mn_have_vel
                CALL    pro_midi_note_off
                JMP     SHORT mn_end
mn_have_vel:    CMP     CH, 0CH
                JB      SHORT mn_oor
                CMP     CH, 6BH
                JBE     SHORT mn_in_range
mn_oor:         JMP     SHORT mn_end
mn_in_range:    SHR     CL, 1
                XOR     BX, BX
                JMP     SHORT mn_scan_test
mn_scan_body:   CMP     CS:[BX + pro_voice_channel], AL
                JNE     SHORT mn_scan_next
                CMP     CS:[BX + pro_voice_note], CH
                JNE     SHORT mn_scan_next
                CALL    pro_voice_release
                CALL    pro_voice_keyon
                JMP     SHORT mn_end
mn_scan_next:   INC     BX
mn_scan_test:   CMP     BX, 9
                JB      SHORT mn_scan_body
                CALL    pro_voice_allocate
                CMP     BL, 0FFH
                JE      SHORT mn_end
                CALL    pro_voice_keyon
mn_end:         POP     SI
                POP     BX
                RET
pro_midi_note   ENDP

; ----------------------------------------------------------------------------
; 0x19F8  --  pro_midi_control_change
;
;   The MIDI "control change" message. CH selects which controller the
;   game is changing; we dispatch on CH to a per-controller helper:
;
;     CC#7   (main volume)        -> pro_cc_main_volume
;     CC#10  (pan / expression)   -> pro_cc_pan
;     CC#64  (sustain pedal)      -> pro_cc_sustain_pedal
;     CC#75  (polyphony budget)   -> pro_sustain_pool_resize
;                                    (driver-internal repurposing of
;                                    "Sound Controller 6" CC#75)
;     CC#123 (all notes off)      -> inline loop releasing every voice
;                                    on channel AL
;     anything else               -> silently ignored
;
;   Type:        Slot handler
;   Category:    MIDI dispatch
;   Dispatch:    Slot 7 (called as: BP=7, AL=channel, CH=cc#, CL=value)
;   Callers:     Game (via dispatch)
;   Callees:     pro_cc_main_volume, pro_cc_pan, pro_cc_sustain_pedal,
;                pro_sustain_pool_resize, pro_voice_release
;
;   Inputs:
;     AL  --  MIDI channel (0..15)
;     CH  --  MIDI controller number (0..127)
;     CL  --  controller value (0..127)
;
;   Outputs:     none
; ----------------------------------------------------------------------------
pro_midi_control_change PROC NEAR
                PUSH    BX
                CMP     CH, 07H
                JNE     SHORT cc_not_vol
                CALL    pro_cc_main_volume
                JMP     SHORT cc_end
cc_not_vol:     CMP     CH, 0AH
                JNE     SHORT cc_not_pan
                CALL    pro_cc_pan
                JMP     SHORT cc_end
cc_not_pan:     CMP     CH, 40H
                JNE     SHORT cc_not_sus
                CALL    pro_cc_sustain_pedal
                JMP     SHORT cc_end
cc_not_sus:     CMP     CH, 4BH
                JNE     SHORT cc_not_pool
                CALL    pro_sustain_pool_resize
                JMP     SHORT cc_end
cc_not_pool:    CMP     CH, 7BH
                JNE     SHORT cc_end
                XOR     BX, BX
                JMP     SHORT cc_scan_test
cc_scan_body:   CMP     CS:[BX + pro_voice_channel], AL
                JNE     SHORT cc_scan_next
                CMP     BYTE PTR CS:[BX + pro_voice_note], 0FFH
                JE      SHORT cc_scan_next
                CALL    pro_voice_release
cc_scan_next:   INC     BX
cc_scan_test:   CMP     BX, 9
                JB      SHORT cc_scan_body
cc_end:         POP     BX
                RET
pro_midi_control_change ENDP

; ----------------------------------------------------------------------------
; 0x1A44  --  pro_midi_program_change
;
;   The game-side equivalent of MIDI's "Program Change" message: tells
;   the driver "from now on, channel <ch> should play notes using
;   instrument <prog>". The driver doesn't reprogram any voice
;   *immediately*; it just caches the new program number. The next time
;   a note is played on this channel (slot 5), pro_voice_keyon will see
;   that the requested patch differs from the patch currently loaded in
;   the assigned voice and reload it from the bank then.
;
;   The stereo dual-bank path doesn't change this slot at all -- the
;   per-channel patch number is a single byte regardless of which OPL
;   bank the voice eventually ends up on.
;
;   Type:        Slot handler
;   Category:    MIDI dispatch
;   Dispatch:    Slot 8 (called as: BP=8, AL=channel, CL=patch#)
;   Callers:     Game (via dispatch)
;   Callees:     none
;
;   Inputs:
;     AL  --  MIDI channel (0..15)
;     CL  --  patch / program number (0..127); semantics depend on the
;             currently-loaded bank
;
;   Outputs:     none
;
;   Touches:     all caller registers preserved (saves SI)
;
;   Side effects:
;     pro_ch_program[channel] <- patch_number
; ----------------------------------------------------------------------------
pro_midi_program_change PROC NEAR
                PUSH    SI
                MOV     SI, AX
                AND     SI, 00FFH
                MOV     CS:[SI + pro_ch_program], CL
                POP     SI
                RET
pro_midi_program_change ENDP

; ----------------------------------------------------------------------------
; 0x1A52  --  pro_midi_pitch_bend
;
;   The MIDI "pitch wheel" message. A 14-bit value centered at 0x2000
;   (no bend); below center bends down, above center bends up. The
;   game packs the 14 bits across two MIDI data bytes that arrive in
;   CL (LSB, 7 bits) and CH (MSB, 7 bits), and we have to repack them
;   into a clean 16-bit word stored at pro_ch_pitchbend[channel].
;
;   After the store, we walk every voice currently playing on the
;   affected channel and call pro_voice_render_freq to recompute the
;   OPL F-number using the new bend value. That's the actual audible
;   effect.
;
;   The repacking math:
;     - XCHG puts MSB in CL, LSB in CH
;     - SHR CH, 1 splits CH into "carry bit + 6 useful bits"
;     - If carry was 1, OR CL's bit 7 with that lost bit (folds the
;       low bit of MSB back onto the high bit of LSB)
;     - Result: CX is the 14-bit bend left-aligned to 14 bits
;
;   Type:        Slot handler
;   Category:    MIDI dispatch
;   Dispatch:    Slot 10 (called as: BP=10, AL=channel, CX=bend14_be)
;   Callers:     Game (via dispatch)
;   Callees:     pro_voice_render_freq (per live voice on channel)
;
;   Inputs:
;     AL  --  MIDI channel (0..15)
;     CX  --  14-bit bend packed as (CH = MSB, CL = LSB)
;
;   Outputs:     none
;
;   Side effects:
;     - pro_ch_pitchbend[channel] <- repacked CX
;     - For every voice playing on this channel: writes OPL regs
;       0xA0+v and 0xB0+v with the new F-number (both banks).
; ----------------------------------------------------------------------------
pro_midi_pitch_bend PROC NEAR
                PUSH    BX
                PUSH    CX
                PUSH    DX
                XCHG    CH, CL
                SHR     CH, 1
                JNC     SHORT pb_no_fold
                OR      CL, 80H
pb_no_fold:     MOV     BX, AX
                XOR     BH, BH
                SHL     BX, 1
                MOV     CS:[BX + pro_ch_pitchbend], CX
                XOR     BX, BX
                JMP     SHORT pb_scan_test
pb_scan_body:   CMP     CS:[BX + pro_voice_channel], AL
                JNE     SHORT pb_scan_next
                CMP     BYTE PTR CS:[BX + pro_voice_note], 0FFH
                JE      SHORT pb_scan_next
                MOV     CL, CS:[BX + pro_voice_note]
                MOV     DX, 0001H
                CALL    pro_voice_render_freq
pb_scan_next:   INC     BX
pb_scan_test:   CMP     BX, 9
                JB      SHORT pb_scan_body
                POP     DX
                POP     CX
                POP     BX
                RET
pro_midi_pitch_bend ENDP

; ----------------------------------------------------------------------------
; 0x1A91  --  pro_set_master_enable
;
;   The driver's "master enable" gate. When 0, pro_voice_keyon skips the
;   patch-reload step and the chip stays silent on note-ons; when 1, the
;   driver behaves normally. The caller passes 0xFF in CL to query the
;   current value without changing it (standard DUDE setter convention).
;
;   When the value changes, we also refresh every live voice via
;   pro_set_master_volume so the master-volume gain math sees the new
;   state. Slightly unusual: the function also clobbers master_volume
;   along the way (it restores it from the called function's
;   return value), which is why the implementation is more elaborate
;   than a simple store.
;
;   Type:        Slot handler
;   Category:    Global state
;   Dispatch:    Slot 13 (called as: BP=13, CL=value or 0xFF=query)
;   Callers:     Game (via dispatch)
;   Callees:     pro_set_master_volume
;
;   Inputs:
;     CL  --  new master-enable value, or 0xFF to query without change
;
;   Outputs:
;     AX  --  previous master-enable value (high byte 0)
;
;   Side effects (when CL != 0xFF):
;     - pro_master_enable <- CL
;     - pro_master_volume gets temporarily clobbered then restored
;     - every live voice refreshed via the master-volume path (which on
;       PAS also fans the four PAS-handler writes if PAS mode is active)
; ----------------------------------------------------------------------------
pro_set_master_enable PROC NEAR
                MOV     AL, CS:pro_master_enable
                XOR     AH, AH
                CMP     CL, 0FFH
                JE      SHORT sme_end
                PUSH    CX
                PUSH    AX
                MOV     CS:pro_master_enable, CL
                OR      CL, CL
                JZ      SHORT sme_skip_load
                MOV     CL, CS:pro_master_volume
sme_skip_load:  CALL    pro_set_master_volume
                MOV     CS:pro_master_volume, AL
                POP     AX
                POP     CX
sme_end:        RET
pro_set_master_enable ENDP

; ----------------------------------------------------------------------------
; 0x1AB6  --  pro_set_master_volume
;
;   Sets the driver's master volume (an OPL TL attenuation, 0..0x3F).
;   Like pro_set_master_enable, the convention is "CL = 0xFF means
;   query without changing"; otherwise CL is the new value.
;
;   This is the AdLib set_master_volume (50 bytes) with 35 additional
;   bytes of PAS-specific code: when CL != 0xFF, the function ALSO
;   issues four pre-configured "master TL" register writes through the
;   PAS BIOS via pro_pas_handler_a (using pro_pan_curve_a / _b as the
;   scale arguments). These four writes are the PAS-side master-volume
;   gain that lives outside the OPL chips themselves.
;
;   Type:        Slot handler
;   Category:    Global state (PAS-aware)
;   Dispatch:    Slot 12 (called as: BP=12, CL=value or 0xFF=query)
;   Callers:     Game (via dispatch), pro_set_master_enable, slot-1 init
;   Callees:     pro_pas_handler_a (4 times when CL != 0xFF)
;
;   Inputs:
;     CL  --  new master volume (0..0x3F), or 0xFF to query
;
;   Outputs:
;     AX  --  previous master volume (high byte 0)
;
;   Side effects (when CL != 0xFF):
;     - pro_master_volume <- CL
;     - four PAS-handler far calls (BX from pan_curve_a/b, DX = 1/8/6/0xD)
; ----------------------------------------------------------------------------
pro_set_master_volume PROC NEAR
                PUSH    BX
                PUSH    DX
                MOV     AL, CS:pro_master_volume
                XOR     AH, AH
                CMP     CL, 0FFH
                JE      SHORT smv_end
                MOV     CS:pro_master_volume, CL
                PUSH    DI
                PUSH    CX
                PUSH    DX
                MOV     DI, CX
                AND     DI, 00FFH
                XOR     BH, BH
                MOV     BL, CS:[DI + pro_pan_curve_a]
                XOR     CX, CX
                MOV     DX, 0001H
                CALL    DWORD PTR CS:pro_pas_handler_a
                XOR     CX, CX
                MOV     DX, 0008H
                CALL    DWORD PTR CS:pro_pas_handler_a
                MOV     BL, CS:[DI + pro_pan_curve_b]
                XOR     CX, CX
                MOV     DX, 0006H
                CALL    DWORD PTR CS:pro_pas_handler_a
                XOR     CX, CX
                MOV     DX, 000DH
                CALL    DWORD PTR CS:pro_pas_handler_a
                POP     DX
                POP     CX
                POP     DI
smv_end:        POP     DX
                POP     BX
                RET
pro_set_master_volume ENDP

; ----------------------------------------------------------------------------
; 0x1B0B  --  pro_set_global_param_146
;
;   Pure get/set on the byte at pro_global_param_146. CL = 0xFF means
;   "query"; otherwise CL is the new value. The byte's semantics are
;   unconfirmed -- no other code path inside this driver reads it
;   (only slot 17 / query_state echoes it back). Most likely a tempo
;   or transpose value that the game uses for its own bookkeeping
;   without expecting the driver to act on it.
;
;   Type:        Slot handler
;   Category:    Global state
;   Dispatch:    Slot 11 (called as: BP=11, CL=value or 0xFF=query)
;   Callers:     Game (via dispatch)
;   Callees:     none
;
;   Inputs:
;     CL  --  new value, or 0xFF to query
;
;   Outputs:
;     AL  --  previous value
; ----------------------------------------------------------------------------
pro_set_global_param_146 PROC NEAR
                MOV     AL, CS:pro_global_param_146
                XOR     AH, AH
                CMP     CL, 0FFH
                JE      SHORT sgp_end
                MOV     CS:pro_global_param_146, CL
sgp_end:        RET
pro_set_global_param_146 ENDP

; ----------------------------------------------------------------------------
; 0x1B1C  --  pro_reset_voices
;
;   The DUDE "stop / reset" slot. Calls pro_silence_and_reset to mute
;   every OPL operator, and then -- on PAS hardware -- additionally
;   fires the PAS init handler followed by four sequential PAS "master
;   TL" writes via the PAS write handler. The four writes reset the
;   PAS-internal master-gain registers to a known mid-level value so
;   the next note isn't lost in residual gain state.
;
;   Type:        Slot handler
;   Category:    Global state (PAS-aware)
;   Dispatch:    Slot 2 (called as: BP=2; no other arguments)
;   Callers:     Game (via dispatch)
;   Callees:     pro_silence_and_reset, pro_pas_handler_a (4x),
;                pro_pas_handler_b (when PAS active)
;
;   Inputs:      none
;   Outputs:     none
;
;   Side effects:
;     ~250 OPL register writes via pro_silence_and_reset. On PAS: five
;     additional far calls through the PAS BIOS far pointers.
; ----------------------------------------------------------------------------
pro_reset_voices PROC NEAR
                CALL    pro_silence_and_reset
                PUSH    BX
                PUSH    CX
                PUSH    DX
                CMP     BYTE PTR CS:pro_pas_mode_flag, 0
                JNZ     SHORT rv_skip_pas_init
                MOV     BX, 0064H
                MOV     CX, 0001H
                CALL    DWORD PTR CS:pro_pas_handler_b
rv_skip_pas_init:
                XOR     BH, BH
                MOV     BL, 64H
                XOR     CX, CX
                MOV     DX, 0001H
                CALL    DWORD PTR CS:pro_pas_handler_a
                XOR     CX, CX
                MOV     DX, 0008H
                CALL    DWORD PTR CS:pro_pas_handler_a
                MOV     BL, 64H
                XOR     CX, CX
                MOV     DX, 0006H
                CALL    DWORD PTR CS:pro_pas_handler_a
                XOR     CX, CX
                MOV     DX, 000DH
                CALL    DWORD PTR CS:pro_pas_handler_a
                POP     DX
                POP     CX
                POP     BX
                RET
pro_reset_voices ENDP

; ----------------------------------------------------------------------------
; 0x1B67  --  pro_voice_allocate
;
;   Picks which of the 9 OPL voices should receive a new note. Three-phase
;   search, increasingly aggressive:
;
;     Phase 1 (best case)
;       Walk voices in LRU order. Pick the first idle voice (note=0xFF).
;       (The PRO variant skips AdLib's "matching patch" sub-check that
;       is present in adl_voice_allocate; the PRO allocator picks the
;       first idle slot regardless of currently-loaded patch.)
;
;     Phase 2 (expensive: voice stealing)
;       Find the MIDI channel that's most over its polyphony budget --
;       i.e. the channel with the largest `poly_active - poly_max`. Then
;       walk voices in LRU order looking for one owned by that channel,
;       silence it, and reuse it. If no channel is over budget, steal
;       from the caller's own channel.
;
;     If even phase 2 fails (very rare; only if BX never matched a voice
;     owned by the worst channel), return 0xFFFF to signal failure.
;
;   The "LRU order" is the pro_voice_lru array: head = oldest voice,
;   tail = youngest. Picking from the head naturally steals from
;   long-silent voices first.
;
;   Type:        Subroutine
;   Category:    Voice management
;   Callers:     pro_midi_note (slot 5)
;   Callees:     pro_voice_release (only in the voice-steal path)
;
;   Inputs:
;     AL  --  MIDI channel that wants the new voice (0..15)
;
;   Outputs:
;     BX  --  chosen voice index 0..8, or 0xFFFF on failure
;
;   Side effects:
;     pro_voice_channel[chosen] <- AL  (binds the voice to the channel)
;     Possibly releases an existing note on a different voice if Phase 2
;     fires.
; ----------------------------------------------------------------------------
pro_voice_allocate PROC NEAR
                PUSH    CX
                PUSH    DX
                PUSH    SI
                XOR     SI, SI
                XOR     BX, BX
                JMP     SHORT va_p2_test
va_p2_body:     MOV     BL, CS:[SI + pro_voice_lru]
                CMP     BYTE PTR CS:[BX + pro_voice_note], 0FFH
                JNE     SHORT va_p2_next
                MOV     CS:[BX + pro_voice_channel], AL
                JMP     SHORT va_end
va_p2_next:     INC     SI
va_p2_test:     CMP     SI, 9
                JB      SHORT va_p2_body
                XOR     SI, SI
                XOR     BX, BX
                XOR     CX, CX
                XOR     DX, DX
                JMP     SHORT va_p3_test
va_p3_body:     MOV     CL, CS:[SI + pro_ch_poly_active]
                CMP     CL, CS:[SI + pro_ch_poly_max]
                JBE     SHORT va_p3_next
                SUB     CL, CS:[SI + pro_ch_poly_max]
                CMP     BL, CL
                JAE     SHORT va_p3_next
                MOV     BL, CL
                MOV     DX, SI
va_p3_next:     INC     SI
va_p3_test:     CMP     SI, 10H
                JB      SHORT va_p3_body
                MOV     CL, AL
                CMP     BL, 0
                JBE     SHORT va_p3b_use_caller
                MOV     CL, DL
va_p3b_use_caller: XOR  SI, SI
                XOR     BX, BX
                JMP     SHORT va_p3b_test
va_p3b_body:    MOV     BL, CS:[SI + pro_voice_lru]
                CMP     CS:[BX + pro_voice_channel], CL
                JNE     SHORT va_p3b_next
                CALL    pro_voice_release
                MOV     CS:[BX + pro_voice_channel], AL
                JMP     SHORT va_end
va_p3b_next:    INC     SI
va_p3b_test:    CMP     SI, 9
                JB      SHORT va_p3b_body
                MOV     BX, 0FFFFH
va_end:         POP     SI
                POP     DX
                POP     CX
                RET
pro_voice_allocate ENDP

; ----------------------------------------------------------------------------
; 0x1BE5  --  pro_sustain_pool_resize
;
;   Handler for MIDI controller CC#75 ("Sound Controller 6 / Decay"
;   in the GM spec, but repurposed by Dynamix as a per-channel
;   polyphony budget). The caller asks for `CL` voices to be reserved
;   for channel AL.
;
;   Implementation:
;     1. Walk the 9 voices, counting how many are already marked
;        reserved-for-AL in pro_voice_sustain_ch.
;     2. Add the channel's "owed reservations" counter
;        (pro_ch_sustain_count[ch]) to that count.
;     3. Compare with the target CL:
;          actual == target: nothing to do
;          actual <  target: grow -- reserve more via _reserve()
;          actual >  target: shrink -- _release() the excess, then
;                            _drain() any leftover free slots into
;                            other channels' debts.
;
;   The "owed" counter exists because we can't physically reserve more
;   voices than the chip has (9). If a channel asks for 12 reservations,
;   the first 9 become real voice reservations and the remaining 3 sit
;   in the owed counter to be picked up later (via _drain) when other
;   reservations free up.
;
;   Type:        Subroutine
;   Category:    Sustain pool (polyphony budgeting)
;   Callers:     pro_midi_control_change (CC#75 branch)
;   Callees:     pro_sustain_pool_reserve, pro_sustain_pool_release,
;                pro_sustain_pool_drain
;
;   Inputs:
;     AL  --  MIDI channel (0..15)
;     CL  --  target reservation count
;
;   Outputs:     none
;   Touches:     caller registers preserved (saves SI, CX, DX)
;
;   Side effects:
;     pro_voice_sustain_ch, pro_ch_sustain_count, pro_ch_poly_max all
;     updated to reflect the new budget. May release active notes in
;     the shrink path.
; ----------------------------------------------------------------------------
pro_sustain_pool_resize PROC NEAR
                PUSH    SI
                PUSH    CX
                PUSH    DX
                XOR     SI, SI
                XOR     DX, DX
                JMP     SHORT spr_count_test
spr_count_body: CMP     CS:[SI + pro_voice_sustain_ch], AL
                JNE     SHORT spr_count_next
                INC     DL
spr_count_next: INC     SI
spr_count_test: CMP     SI, 9
                JB      SHORT spr_count_body
                MOV     SI, AX
                AND     SI, 00FFH
                ADD     DL, CS:[SI + pro_ch_sustain_count]
                CMP     DL, CL
                JE      SHORT spr_end
                CMP     DL, CL
                JAE     SHORT spr_shrink
                SUB     CL, DL
                CALL    pro_sustain_pool_reserve
                JMP     SHORT spr_end
spr_shrink:     SUB     DL, CL
                MOV     CL, DL
                CALL    pro_sustain_pool_release
                CALL    pro_sustain_pool_drain
spr_end:        POP     DX
                POP     CX
                POP     SI
                RET
pro_sustain_pool_resize ENDP

; ----------------------------------------------------------------------------
; 0x1C25  --  pro_sustain_pool_drain
;
;   After a sustain-pool shrink, some voice reservations may have come
;   free (their owner channel no longer needs them). This function
;   "drains" those free slots: any channel that had outstanding owed
;   reservations (pro_ch_sustain_count[ch] > 0) gets first claim on
;   the freed slots.
;
;   Algorithm:
;     1. Count free reservation slots (voice_sustain_ch[v] == 0xFF)
;        into CL.
;     2. If CL == 0, nothing to do; return.
;     3. Walk channels 0..15. For each whose pro_ch_sustain_count > 0:
;          - If the channel's debt is smaller than our remaining free
;            slots, fully satisfy it and zero out the counter.
;          - Otherwise satisfy it partially with all our remaining
;            slots and return early.
;
;   Type:        Subroutine
;   Category:    Sustain pool
;   Callers:     pro_sustain_pool_resize
;   Callees:     pro_sustain_pool_reserve
;
;   Inputs:      (reads driver state only; no register args)
;   Outputs:     none
;
;   Side effects:
;     Bound voices and their owning channels updated.
; ----------------------------------------------------------------------------
pro_sustain_pool_drain PROC NEAR
                PUSH    AX
                PUSH    CX
                PUSH    SI
                XOR     CL, CL
                XOR     SI, SI
                JMP     SHORT spd_count_test
spd_count_body: CMP     BYTE PTR CS:[SI + pro_voice_sustain_ch], 0FFH
                JNE     SHORT spd_count_next
                INC     CL
spd_count_next: INC     SI
spd_count_test: CMP     SI, 9
                JB      SHORT spd_count_body
                OR      CL, CL
                JZ      SHORT spd_end
                XOR     SI, SI
                JMP     SHORT spd_loop_test
spd_loop_body:  MOV     CH, CS:[SI + pro_ch_sustain_count]
                CMP     CH, 0
                JBE     SHORT spd_next_ch
                CMP     CH, CL
                JAE     SHORT spd_partial
                SUB     CL, CH
                PUSH    CX
                MOV     CL, CH
                MOV     BYTE PTR CS:[SI + pro_ch_sustain_count], 0
                MOV     AX, SI
                CALL    pro_sustain_pool_reserve
                POP     CX
                JMP     SHORT spd_next_ch
spd_partial:    SUB     CH, CL
                MOV     CS:[SI + pro_ch_sustain_count], CH
                MOV     AX, SI
                CALL    pro_sustain_pool_reserve
                JMP     SHORT spd_end
spd_next_ch:    INC     SI
spd_loop_test:  CMP     SI, 10H
                JB      SHORT spd_loop_body
spd_end:        POP     SI
                POP     CX
                POP     AX
                RET
pro_sustain_pool_drain ENDP

; ----------------------------------------------------------------------------
; 0x1C7F  --  pro_sustain_pool_reserve
;
;   Claims `CL` voice slots for channel AL. Walks voices, picks any
;   that are currently free for reservation (voice_sustain_ch == 0xFF),
;   releases any note they happen to be playing (since we're taking
;   them over), and marks them as reserved for AL.
;
;   If fewer than CL voices are available to reserve, the remaining
;   shortfall is added to pro_ch_sustain_count[AL] -- the "owed
;   reservations" counter that gets paid down by future _drain() calls.
;
;   Type:        Subroutine
;   Category:    Sustain pool
;   Callers:     pro_sustain_pool_resize, pro_sustain_pool_drain
;   Callees:     pro_voice_release
;
;   Inputs:
;     AL  --  channel claiming the reservations
;     CL  --  number of voices to reserve
;
;   Outputs:     none
;
;   Side effects:
;     For each successfully reserved voice:
;       voice_sustain_ch[v]   <- AL
;       ch_poly_max[AL]       <- ch_poly_max[AL] + 1
;     Spillover: ch_sustain_count[AL] += unfulfilled count
; ----------------------------------------------------------------------------
pro_sustain_pool_reserve PROC NEAR
                PUSH    CX
                PUSH    BX
                PUSH    SI
                XOR     BX, BX
                JMP     SHORT spres_loop_test
spres_loop_body: CMP    BYTE PTR CS:[BX + pro_voice_sustain_ch], 0FFH
                JNE     SHORT spres_next_voice
                CMP     BYTE PTR CS:[BX + pro_voice_note], 0FFH
                JE      SHORT spres_assign
                CALL    pro_voice_release
spres_assign:   MOV     CS:[BX + pro_voice_sustain_ch], AL
                XOR     AH, AH
                MOV     SI, AX
                INC     BYTE PTR CS:[SI + pro_ch_poly_max]
                DEC     CL
spres_next_voice: INC   BX
spres_loop_test: CMP    BX, 9
                JAE     SHORT spres_done
                CMP     CL, 0
                JA      SHORT spres_loop_body
spres_done:     MOV     SI, AX
                AND     SI, 00FFH
                ADD     CS:[SI + pro_ch_sustain_count], CL
                POP     SI
                POP     BX
                POP     CX
                RET
pro_sustain_pool_reserve ENDP

; ----------------------------------------------------------------------------
; 0x1CC3  --  pro_sustain_pool_release
;
;   The opposite of _reserve(). Drops `CL` voice slots from channel AL's
;   reservation pool. Three sub-paths in order of cost:
;
;     1. If ch_sustain_count[AL] >= CL, the channel has enough "owed"
;        reservations to absorb the drop without touching any real
;        voices. Just subtract CL from the counter.
;
;     2. Otherwise, zero out ch_sustain_count[AL] (which absorbs some)
;        and reduce the remaining CL. Then walk voices looking for
;        idle reserved voices (sustain_ch == AL && note == 0xFF) and
;        free them.
;
;     3. If we still owe releases after that, walk voices again, now
;        accepting reserved voices that are currently playing notes.
;        For each, call pro_voice_release to silence the note, then
;        free the reservation.
;
;   Type:        Subroutine
;   Category:    Sustain pool
;   Callers:     pro_sustain_pool_resize
;   Callees:     pro_voice_release
;
;   Inputs:
;     AL  --  channel relinquishing reservations
;     CL  --  number of slots to release
;
;   Outputs:     none
; ----------------------------------------------------------------------------
pro_sustain_pool_release PROC NEAR
                PUSH    BX
                PUSH    CX
                PUSH    SI
                MOV     SI, AX
                AND     SI, 00FFH
                CMP     CS:[SI + pro_ch_sustain_count], CL
                JB      SHORT sprl_partial
                SUB     CS:[SI + pro_ch_sustain_count], CL
                JMP     SHORT sprl_end
sprl_partial:   SUB     CL, CS:[SI + pro_ch_sustain_count]
                MOV     BYTE PTR CS:[SI + pro_ch_sustain_count], 0
                XOR     BX, BX
                JMP     SHORT sprl_p1_test
sprl_p1_body:   CMP     CS:[BX + pro_voice_sustain_ch], AL
                JNE     SHORT sprl_p1_next
                CMP     BYTE PTR CS:[BX + pro_voice_note], 0FFH
                JNE     SHORT sprl_p1_next
                MOV     BYTE PTR CS:[BX + pro_voice_sustain_ch], 0FFH
                XOR     AH, AH
                MOV     SI, AX
                DEC     BYTE PTR CS:[SI + pro_ch_poly_max]
                DEC     CL
                JZ      SHORT sprl_end
sprl_p1_next:   INC     BX
sprl_p1_test:   CMP     BX, 9
                JB      SHORT sprl_p1_body
                XOR     BX, BX
                JMP     SHORT sprl_p2_test
sprl_p2_body:   CMP     CS:[BX + pro_voice_sustain_ch], AL
                JNE     SHORT sprl_p2_next
                CALL    pro_voice_release
                MOV     BYTE PTR CS:[BX + pro_voice_sustain_ch], 0FFH
                XOR     AH, AH
                MOV     SI, AX
                DEC     BYTE PTR CS:[SI + pro_ch_poly_max]
                DEC     CL
                JZ      SHORT sprl_end
sprl_p2_next:   INC     BX
sprl_p2_test:   CMP     BX, 9
                JB      SHORT sprl_p2_body
sprl_end:       POP     SI
                POP     CX
                POP     BX
                RET
pro_sustain_pool_release ENDP

; ----------------------------------------------------------------------------
; 0x1D3C  --  pro_cc_main_volume
;
;   Handler for MIDI CC#7 ("Main Volume"). The MIDI value (0..127) is
;   first halved into the OPL TL range (0..63), then stored in
;   pro_ch_volume[channel]. Then every voice playing on this channel
;   is refreshed via pro_voice_render_freq so the new volume takes
;   effect on both OPL banks.
;
;   Type:        Subroutine
;   Category:    MIDI CC handler
;   Callers:     pro_midi_control_change (CC#7 branch)
;   Callees:     pro_voice_render_freq
;
;   Inputs:
;     AL  --  channel (0..15)
;     CL  --  volume (0..127)
;
;   Outputs:     none
;
;   Side effects:
;     pro_ch_volume[ch] <- CL >> 1
;     Live voices on this channel refreshed (bank-A and bank-B writes).
; ----------------------------------------------------------------------------
pro_cc_main_volume PROC NEAR
                PUSH    BX
                PUSH    CX
                PUSH    DX
                PUSH    SI
                SHR     CL, 1
                MOV     SI, AX
                AND     SI, 00FFH
                MOV     CS:[SI + pro_ch_volume], CL
                XOR     CX, CX
                MOV     DX, 0001H
                XOR     BX, BX
                JMP     SHORT ccv_test
ccv_body:       CMP     CS:[BX + pro_voice_channel], AL
                JNE     SHORT ccv_next
                MOV     CL, CS:[BX + pro_voice_note]
                CMP     CL, 0FFH
                JE      SHORT ccv_next
                CALL    pro_voice_render_freq
ccv_next:       INC     BX
ccv_test:       CMP     BX, 9
                JB      SHORT ccv_body
                POP     SI
                POP     DX
                POP     CX
                POP     BX
                RET
pro_cc_main_volume ENDP

; ----------------------------------------------------------------------------
; 0x1D75  --  pro_cc_pan
;
;   Handler for MIDI CC#10 ("Pan"). Stores the raw value (0..127) in
;   pro_ch_pan[channel] and refreshes live voices. On PAS the pan value
;   has a real audible effect: it controls the per-bank attenuation in
;   pro_voice_render_volume. (On plain mono AdLib this same code is
;   harmless busywork; the PAS variant is where pan actually pans.)
;
;   Type:        Subroutine
;   Category:    MIDI CC handler
;   Callers:     pro_midi_control_change (CC#10 branch)
;   Callees:     pro_voice_render_freq
;
;   Inputs:
;     AL  --  channel (0..15)
;     CL  --  pan value (0..127)
;
;   Outputs:     none
;
;   Side effects:
;     pro_ch_pan[ch] <- CL (raw)
;     Live voices on this channel refreshed (rewrites OPL 0x40+op on
;     both banks via the stereo render path).
; ----------------------------------------------------------------------------
pro_cc_pan      PROC    NEAR
                PUSH    SI
                PUSH    BX
                MOV     SI, AX
                AND     SI, 00FFH
                MOV     CS:[SI + pro_ch_pan], CL
                XOR     CX, CX
                MOV     DX, 0001H
                XOR     BX, BX
                JMP     SHORT ccp_test
ccp_body:       CMP     CS:[BX + pro_voice_channel], AL
                JNE     SHORT ccp_next
                MOV     CL, CS:[BX + pro_voice_note]
                CMP     CL, 0FFH
                JE      SHORT ccp_next
                CALL    pro_voice_render_freq
ccp_next:       INC     BX
ccp_test:       CMP     BX, 9
                JB      SHORT ccp_body
                POP     BX
                POP     SI
                RET
pro_cc_pan      ENDP

; ----------------------------------------------------------------------------
; 0x1DA8  --  pro_cc_sustain_pedal
;
;   Handler for MIDI CC#64 ("Damper / Sustain Pedal"). When CL != 0
;   the pedal is held: just record the state. When CL == 0 the pedal
;   is released, which means any voices that were waiting on the
;   pedal (voice_sustain_held = 1, set by pro_midi_note_off) should
;   now actually be released.
;
;   This implements the classic piano-pedal behavior: notes you played
;   while holding the pedal keep ringing even after you lift the keys,
;   and they all stop together when you lift the pedal.
;
;   Type:        Subroutine
;   Category:    MIDI CC handler
;   Callers:     pro_midi_control_change (CC#64 branch)
;   Callees:     pro_voice_release (only when pedal lifts)
;
;   Inputs:
;     AL  --  channel (0..15)
;     CL  --  pedal state: 0 = off, non-zero = held
;
;   Outputs:     none
;
;   Side effects:
;     pro_ch_sustain_pedal[ch] <- CL
;     On pedal-off: every voice with voice_sustain_held set on this
;     channel is released.
; ----------------------------------------------------------------------------
pro_cc_sustain_pedal PROC NEAR
                PUSH    BX
                PUSH    SI
                MOV     SI, AX
                AND     SI, 00FFH
                MOV     CS:[SI + pro_ch_sustain_pedal], CL
                OR      CL, CL
                JNZ     SHORT ccsp_end
                XOR     BX, BX
                JMP     SHORT ccsp_test
ccsp_body:      CMP     CS:[BX + pro_voice_channel], AL
                JNE     SHORT ccsp_next
                CMP     BYTE PTR CS:[BX + pro_voice_sustain_held], 0
                JE      SHORT ccsp_next
                CALL    pro_voice_release
ccsp_next:      INC     BX
ccsp_test:      CMP     BX, 9
                JB      SHORT ccsp_body
ccsp_end:       POP     SI
                POP     BX
                RET
pro_cc_sustain_pedal ENDP

; ----------------------------------------------------------------------------
; 0x1DD8  --  pro_voice_keyon
;
;   Starts a note on a chosen voice. The caller (pro_midi_note) has
;   already picked the voice; this function does the bookkeeping and
;   the OPL programming:
;
;     1. Bump the channel's active-note counter (poly_active).
;     2. Remove the voice from the LRU front so it's marked "youngest".
;     3. If the voice is on MIDI channel 9 (the percussion channel),
;        remap the note number: clamp to [0x1B, 0x58] (the GM drum
;        range), then add 0x65 to derive a percussion-patch index.
;        For non-drum channels the note is used directly.
;     4. If the requested patch number is different from what's
;        currently loaded in this voice, AND master_enable is set,
;        reload the patch. The 28-byte patch record lives at
;        pro_bank_buf + program * 28; we compute that offset by
;        shift-and-add (since 8086 has no fast multiply-by-immediate).
;        See the inline comments at the multiply site.
;     5. Cache the velocity in voice_velocity[v].
;     6. Call pro_voice_render_freq with DX = 1 (the "key on" flag)
;        to push the new pitch + key-on bit to the OPL.
;
;   Type:        Subroutine
;   Category:    Voice management
;   Callers:     pro_midi_note
;   Callees:     pro_voice_lru_remove, pro_voice_apply_patch,
;                pro_voice_render_freq
;
;   Inputs:
;     BX  --  voice index 0..8
;     CH  --  MIDI note number (0..127)
;     CL  --  pre-halved velocity (0..63)
;
;   Outputs:     none
;
;   Side effects:
;     - pro_ch_poly_active[ch]++
;     - LRU updated
;     - voice_velocity[v], possibly voice_program[v] and op_shadow
;       updated; OPL registers 0x20..0xE0 written on both banks (via
;       the patch reload chain) and 0xA0+v / 0xB0+v written (via
;       render_freq).
; ----------------------------------------------------------------------------
pro_voice_keyon PROC    NEAR
                PUSH    CX
                PUSH    DX
                PUSH    DI
                PUSH    SI
                XOR     DH, DH
                MOV     DL, CS:[BX + pro_voice_channel]
                MOV     SI, DX
                MOV     DL, CS:[SI + pro_ch_program]
                INC     BYTE PTR CS:[SI + pro_ch_poly_active]
                CALL    pro_voice_lru_remove
                CMP     SI, 9
                JNE     SHORT vkon_not_drum
                MOV     DL, CH
                CMP     DL, 1BH
                JAE     SHORT vkon_drum_hi
                MOV     DL, 1BH
                JMP     SHORT vkon_drum_done
vkon_drum_hi:   CMP     DL, 58H
                JBE     SHORT vkon_drum_done
                MOV     DL, 58H
vkon_drum_done: ADD     DL, 65H
vkon_not_drum:  CMP     DL, CS:[BX + pro_voice_program]
                JE      SHORT vkon_no_reload
                CMP     BYTE PTR CS:pro_master_enable, 0
                JE      SHORT vkon_no_reload
                PUSH    CX
                MOV     CS:[BX + pro_voice_program], DL
                PUSH    BX
                XOR     BH, BH
                MOV     BL, DL
                PUSH    CX
                PUSH    AX
                ; Hand-rolled multiply: BX = program * 28 (the patch
                ; record size). Patches live as 28-byte runs in
                ; pro_bank_buf. 28 = 4 + 8 + 16, so:
                MOV     CL, 02H
                SHL     BX, CL                  ; BX = program * 4
                MOV     AX, BX                  ; AX = program * 4
                SHL     BX, 1                   ; BX = program * 8
                MOV     CX, BX                  ; CX = program * 8
                SHL     BX, 1                   ; BX = program * 16
                ADD     BX, AX                  ; BX = program * 20
                ADD     BX, CX                  ; BX = program * 28
                POP     AX
                POP     CX
                MOV     DI, BX
                POP     BX
                LEA     CX, [DI + pro_bank_buf]
                CALL    pro_voice_apply_patch
                POP     CX
vkon_no_reload: MOV     CS:[BX + pro_voice_velocity], CL
                MOV     CL, CH
                MOV     DX, 0001H
                CALL    pro_voice_render_freq
                POP     SI
                POP     DI
                POP     DX
                POP     CX
                RET
pro_voice_keyon ENDP

; ----------------------------------------------------------------------------
; 0x1E57  --  pro_voice_release
;
;   Stops a voice cleanly:
;
;     1. Clear voice_sustain_held flag (we're releasing now, no longer
;        deferred).
;     2. Call pro_voice_render_freq with DX = 0 (no key-on bit). This
;        writes OPL reg 0xB0+v on both banks without the KEY-ON bit,
;        which tells the chip to begin the release-rate envelope.
;     3. Mark voice_note[v] = 0xFF (the voice is now idle).
;     4. Remove from LRU (so the next allocator pass treats it as old).
;     5. Decrement pro_ch_poly_active for the owning channel.
;
;   Type:        Subroutine
;   Category:    Voice management
;   Callers:     pro_midi_note_off, pro_midi_note (retrigger path),
;                pro_voice_allocate (voice-steal path), pro_cc_sustain_pedal,
;                pro_midi_control_change (CC#123 all-notes-off path),
;                pro_sustain_pool_release, pro_sustain_pool_reserve
;   Callees:     pro_voice_render_freq, pro_voice_lru_remove
;
;   Inputs:
;     BX  --  voice index 0..8
;
;   Outputs:     none
;
;   Side effects:
;     OPL register 0xB0+v written (key-off) on both A and B banks.
;     Internal state for this voice and its owning channel updated.
; ----------------------------------------------------------------------------
pro_voice_release PROC NEAR
                PUSH    CX
                PUSH    DX
                PUSH    SI
                MOV     BYTE PTR CS:[BX + pro_voice_sustain_held], 0
                XOR     CH, CH
                MOV     CL, CS:[BX + pro_voice_note]
                XOR     DX, DX
                CALL    pro_voice_render_freq
                MOV     BYTE PTR CS:[BX + pro_voice_note], 0FFH
                CALL    pro_voice_lru_remove
                MOV     DL, CS:[BX + pro_voice_channel]
                XOR     DH, DH
                MOV     SI, DX
                DEC     BYTE PTR CS:[SI + pro_ch_poly_active]
                POP     SI
                POP     DX
                POP     CX
                RET
pro_voice_release ENDP

; ----------------------------------------------------------------------------
; 0x1E87  --  pro_voice_lru_remove
;
;   "Bump this voice to the youngest position" in the LRU queue.
;   Implementation: find the entry whose value equals BL, shift every
;   entry after it down by one, then store BL at the tail (slot 8).
;
;   After this function: pro_voice_lru[8] is BL, and the order of the
;   other entries is preserved relative to each other. The next time
;   the voice allocator walks LRU from head to tail, this voice will
;   be the last one it considers (i.e. the freshest).
;
;   Type:        Subroutine
;   Category:    Voice management
;   Callers:     pro_voice_keyon, pro_voice_release
;   Callees:     none
;
;   Inputs:
;     BL  --  voice index 0..8 to move to "youngest"
;
;   Outputs:     none
;
;   Side effects:
;     pro_voice_lru rearranged.
; ----------------------------------------------------------------------------
pro_voice_lru_remove PROC NEAR
                PUSH    SI
                PUSH    AX
                XOR     SI, SI
                JMP     SHORT vlru_outer
vlru_find:      CMP     CS:[SI + pro_voice_lru], BL
                JNE     SHORT vlru_next
                JMP     SHORT vlru_shift_test
vlru_shift:     MOV     AH, CS:[SI + pro_voice_lru + 1]
                MOV     CS:[SI + pro_voice_lru], AH
                INC     SI
vlru_shift_test: CMP    SI, 8
                JB      SHORT vlru_shift
vlru_next:      INC     SI
vlru_outer:     CMP     SI, 9
                JB      SHORT vlru_find
                XOR     BH, BH
                MOV     CS:[pro_voice_lru + 8], BL
                POP     AX
                POP     SI
                RET
pro_voice_lru_remove ENDP

; ----------------------------------------------------------------------------
; 0x1EB6  --  pro_voice_render_freq
;
;   Pushes a voice's current state to the chip: pitch, block (octave),
;   key-on bit, and effective volume. Called whenever anything that
;   affects a sounding voice changes (note-on, note-off, master
;   volume, channel volume, pitch bend, pan).
;
;   PRO's variant is 29 bytes shorter than AdLib's: it does pitch +
;   key-on bit math the same way, but instead of inline channel-
;   volume / master-volume / master-enable scaling, it delegates ALL
;   volume math to the dual-bank pro_voice_render_volume (which
;   handles stereo pan + master).
;
;   The work, in order:
;     1. Cache the note in voice_note[v].
;     2. Look up the voice's MIDI channel.
;     3. If voice has a "drum" patch loaded (voice_program >= 0x80),
;        clamp the note and remap via pro_vel_to_tl_lut.
;     4. Convert the note into the F-num + block representation the
;        OPL2 wants (using pro_note_fnum_table indexed by note*4 mod 48),
;        applying the channel's pitch wheel via pitchbend_apply.
;     5. Write OPL reg 0xA0+v with the F-num low byte via pro_opl_write
;        (which on PAS dispatches to both bank A and bank B).
;     6. Build the 0xB0+v byte and call pro_voice_render_volume to fan
;        out the per-bank TL writes.
;     7. Write OPL reg 0xB0+v with the composed byte (block + F-num
;        high + key-on bit).
;
;   Type:        Subroutine
;   Category:    OPL rendering
;   Callers:     pro_voice_release, pro_voice_keyon, pro_midi_pitch_bend,
;                pro_cc_main_volume, pro_cc_pan
;   Callees:     pro_voice_pitchbend_apply, pro_voice_render_volume,
;                pro_opl_write
;
;   Inputs:
;     BX  --  voice index 0..8
;     CL  --  MIDI note number
;     DX  --  non-zero = set KEY-ON in the 0xB0 write (begin/sustain
;             note); zero = clear KEY-ON (release the envelope)
;
;   Outputs:     none
;
;   Side effects:
;     pro_voice_note[v] <- CL
;     Writes OPL regs 0xA0+v and 0xB0+v through pro_opl_write (both
;     banks). Calls pro_voice_render_volume which writes 0x40+op on
;     both banks.
; ----------------------------------------------------------------------------
pro_voice_render_freq PROC NEAR
                PUSH    SI
                PUSH    DI
                PUSH    AX
                PUSH    BX
                PUSH    CX
                PUSH    DX
                MOV     CS:[BX + pro_voice_note], CL
                XOR     AH, AH
                MOV     AL, CS:[BX + pro_voice_channel]
                MOV     SI, AX
                XOR     CH, CH
                MOV     AL, CS:[BX + pro_voice_program]
                CMP     AL, 80H
                JB      SHORT vrf_have_note
                CMP     CL, 1BH
                JAE     SHORT vrf_drum_hi
                MOV     CL, 1BH
                JMP     SHORT vrf_drum_done
vrf_drum_hi:    CMP     CL, 58H
                JBE     SHORT vrf_drum_done
                MOV     CL, 58H
vrf_drum_done:  SUB     CL, 1BH
                PUSH    SI
                MOV     SI, CX
                MOV     CL, CS:[SI + pro_vel_to_tl_lut]
                POP     SI
vrf_have_note:  SHL     CX, 1
                SHL     CX, 1
                CALL    pro_voice_pitchbend_apply
                CMP     CX, 0FFFFH
                JNE     SHORT vrf_in_range
                JMP     SHORT vrf_end
vrf_in_range:   MOV     AX, CX
                MOV     DH, 30H
                DIV     DH
                XOR     CH, CH
                MOV     CL, AH
                MOV     DI, CX
                SHL     DI, 1
                MOV     CX, CS:[DI + pro_note_fnum_table]
                ADD     BX, 00A0H
                CALL    pro_opl_write
                CMP     AL, 0
                JBE     SHORT vrf_block_ok
                DEC     AL
vrf_block_ok:   MOV     CL, 02H
                SHL     AL, CL
                OR      AL, CH
                OR      DL, DL
                JZ      SHORT vrf_no_keyon
                OR      AL, 20H
vrf_no_keyon:   XOR     CX, CX
                MOV     CL, AL
                ADD     BX, 10H
                PUSH    BX
                PUSH    CX
                SUB     BX, 00B0H
                MOV     AL, CS:[SI + pro_ch_volume]
                INC     AL
                XOR     CH, CH
                MOV     CL, CS:[BX + pro_voice_velocity]
                MOV     DI, CX
                MOV     CL, CS:[DI + pro_volcurve_a]
                INC     CL
                MUL     CL
                MOV     CL, 06H
                SHR     AX, CL
                CALL    pro_voice_render_volume
                POP     CX
                POP     BX
                CALL    pro_opl_write
vrf_end:        POP     DX
                POP     CX
                POP     BX
                POP     AX
                POP     DI
                POP     SI
                RET
pro_voice_render_freq ENDP

; ----------------------------------------------------------------------------
; 0x1F64  --  pro_voice_pitchbend_apply
;
;   Adjusts an F-num up or down based on the voice's channel pitch wheel.
;   Pure math; doesn't touch the OPL chip.
;
;   The channel's pitch wheel is a 14-bit MIDI value centered at 0x2000:
;     - 0x2000 means "no bend", we leave CX alone.
;     - > 0x2000 means "bend up": CX = CX + (bend - 0x2000) / 0xAB
;     - < 0x2000 means "bend down": CX = CX - (0x2000 - bend) / 0xAB
;   The divisor 0xAB (= 171) gives roughly one semitone over the full
;   wheel range, scaled to F-num units.
;
;   After the bend, CX is clamped to 0x01FC. If the bend wraps CX past
;   that limit, the caller (pro_voice_render_freq) checks for the
;   sentinel 0xFFFF and short-circuits.
;
;   Type:        Subroutine
;   Category:    OPL rendering
;   Callers:     pro_voice_render_freq
;   Callees:     none
;
;   Inputs:
;     BX  --  voice index 0..8
;     CX  --  base F-num for the requested note
;
;   Outputs:
;     CX  --  bent F-num (or 0xFFFF if clamping triggered)
;     DL  --  sign of the applied bend: 0 = none, 1 = positive,
;             0xFF = negative.
; ----------------------------------------------------------------------------
pro_voice_pitchbend_apply PROC NEAR
                PUSH    AX
                PUSH    BX
                PUSH    DX
                PUSH    SI
                PUSH    DI
                XOR     AH, AH
                MOV     AL, CS:[BX + pro_voice_channel]
                MOV     SI, AX
                SHL     SI, 1
                MOV     DI, CS:[SI + pro_ch_pitchbend]
                CMP     DI, 02000H
                JNE     SHORT vpb_not_centered
                XOR     AX, AX
                XOR     DL, DL
                JMP     SHORT vpb_apply
vpb_not_centered: CMP   DI, 02000H
                JBE     SHORT vpb_negative
                MOV     AX, DI
                SUB     AX, 02000H
                MOV     DL, 01H
                JMP     SHORT vpb_apply
vpb_negative:   MOV     AX, 02000H
                SUB     AX, DI
                MOV     DL, 0FFH
vpb_apply:      MOV     BL, 0ABH
                DIV     BL
                XOR     AH, AH
                CMP     DL, 01H
                JNE     SHORT vpb_subtract
                ADD     CX, AX
                JMP     SHORT vpb_clamp
vpb_subtract:   SUB     CX, AX
vpb_clamp:      CMP     CX, 001FCH
                JBE     SHORT vpb_end
                MOV     CX, 001FCH
vpb_end:        POP     DI
                POP     SI
                POP     DX
                POP     BX
                POP     AX
                RET
pro_voice_pitchbend_apply ENDP

; ----------------------------------------------------------------------------
; 0x1FBB  --  pro_voice_render_volume
;
;   STEREO-AWARE per-voice TL writer. The Pro AudioSpectrum (PAS) card
;   routes each OPL voice through two separate dual-OPL2 banks (bank A
;   on ports 0x388/0x389, bank B on ports 0x38A/0x38B) so that left and
;   right audio channels can be driven independently. To produce a
;   stereo pan effect the driver writes the same "total level" (TL)
;   register on both banks but with different attenuations: the bank
;   facing the pan direction stays loud, the other bank is attenuated.
;
;   This function performs the AdLib voice-volume math FOUR times:
;
;     LEFT  modulator -> pro_opl_write_a (bank A, port 0x388/0x389)
;     LEFT  carrier   -> pro_opl_write_a (only if voice is additive)
;     RIGHT modulator -> pro_opl_write_b (bank B, port 0x38A/0x38B)
;     RIGHT carrier   -> pro_opl_write_b (only if voice is additive)
;
;   For each side, the volume passed in AL is first scaled by a pan
;   factor derived from pro_volcurve_b[]:
;
;     left_scale  = volcurve_b[ pan / 2 ]
;     right_scale = volcurve_b[ (0x7F - pan) / 2 ]
;     scaled_vol  = vol * (0x3F - scale) / 0x3F
;     side_vol    = vol - scaled_vol      (clamped >= 0 for right)
;     curve_vol   = volcurve_b[side_vol]
;
;   Then the standard AdLib TL composition (matches adl_voice_render_
;   volume) produces the OPL register byte:
;
;     tl_byte     = base + (curve_vol * tl_max / 0x3F)
;     reg_byte    = (KSL << 6) | (0x3F - curve_vol * tl_max / 0x3F)
;
;   Type:        Subroutine
;   Category:    OPL rendering (PAS / dual-OPL2 stereo extension)
;   Callers:     pro_voice_render_freq
;   Callees:     pro_opl_write_a, pro_opl_write_b
;
;   Inputs:
;     BX  --  voice index 0..8 (selects per-voice TL working tables)
;     AL  --  velocity-scaled volume index, saturated to 0x3F on entry
;
;   Outputs:     (no return value)
;
;   Touches:     all caller registers preserved
;
;   Side effects:
;     Writes OPL register 0x40+op on both banks for the modulator and
;     (if the voice is in additive mode) the carrier.
;
;   Notes:
;     The prologue saves AX, CX, DX, SI, DI; BX is not preserved
;     globally -- every PUSH BX inside the body is locally matched by
;     a corresponding POP BX. The JZ branches that skip each carrier
;     pass land *after* both halves of the local PUSH/POP pair, so
;     the stack stays balanced in either path. The voice index in BX
;     therefore needs to survive each call (pro_opl_write_a/b clobber
;     BX); inside each pass, the original saves it before the call
;     and restores it on the way out.
; ----------------------------------------------------------------------------
pro_voice_render_volume PROC NEAR
                PUSH    AX
                PUSH    CX
                PUSH    DX
                PUSH    SI
                PUSH    DI

                ; Saturate AL at 0x3F (TL range cap).
                CMP     AL, 3FH
                JBE     SHORT vrv_vol_ok
                MOV     AL, 3FH
vrv_vol_ok:     XOR     DH, DH
                MOV     DL, CS:[BX + pro_voice_channel]
                MOV     SI, DX                  ; SI = voice's MIDI channel

; ============================================================================
;     LEFT MODULATOR (writes OPL reg 0x40+mod_op via pro_opl_write_a)
; ============================================================================
                ; Save vol twice: one copy is restored after the
                ; left-pan factor has been applied (gives us the
                ; right-side starting volume); the second copy is
                ; restored at the top of the RIGHT-MODULATOR section.
                PUSH    AX
                PUSH    AX

                ; ---- compute left pan scale: volcurve_b[pan / 2] ----
                MOV     DL, CS:[SI + pro_ch_pan]
                SHR     DL, 1                   ; DL = pan / 2
                CMP     DL, 3FH
                JBE     SHORT vrv_lm_pan_ok
                MOV     DL, 3FH
vrv_lm_pan_ok:  PUSH    BX                      ; save voice index
                MOV     BL, DL
                XOR     BH, BH
                MOV     BL, CS:[BX + pro_volcurve_b]   ; BL = volcurve_b[pan/2]
                MOV     DL, 3FH
                SUB     DL, BL                  ; DL = 0x3F - curve(pan/2)
                POP     BX                      ; restore voice index
                MUL     DL                      ; AX = vol * (0x3F - scale)
                MOV     DL, 3FH
                DIV     DL                      ; AL = AX / 0x3F = scaled
                MOV     DL, AL                  ; stash scaled value
                POP     AX                      ; AL = original vol
                SUB     AL, DL                  ; AL = vol - scaled (left)
                CMP     DL, 3FH                 ; clamp scaled to 0x3F
                JBE     SHORT vrv_lm_dl_ok
                MOV     DL, 3FH
vrv_lm_dl_ok:
                ; ---- LEFT modulator TL math: TL_byte = base + curve(vol)*max/0x3F ----
                XOR     AH, AH
                MOV     DI, AX                  ; DI = side_vol (0..3F)
                MOV     AL, CS:[DI + pro_volcurve_b]   ; AL = volcurve_b[side_vol]
                PUSH    AX                      ; save curve_vol for after the call
                SHL     BX, 1                   ; voice -> word-index for TL tables
                MOV     CX, CS:[BX + pro_voice_mod_tl_max]
                MUL     CL                      ; AX = curve_vol * tl_max
                MOV     CL, 3FH
                DIV     CL                      ; AL = (curve_vol*tl_max)/0x3F
                SUB     CL, AL                  ; CL = 0x3F - that (the TL bits)
                MOV     AX, CS:[BX + pro_voice_mod_tl_base]
                SHR     BX, 1                   ; BX back to voice index
                MOV     CH, AL                  ; KSL bits in CH
                SHL     CH, 1
                SHL     CH, 1
                SHL     CH, 1
                SHL     CH, 1
                SHL     CH, 1
                SHL     CH, 1                   ; CH = KSL << 6
                OR      CL, CH                  ; CL = (KSL<<6) | TL
                XOR     CH, CH
                PUSH    BX                      ; save voice index across call
                XOR     DH, DH
                MOV     DL, CS:[BX + pro_op_perm]       ; modulator op index
                MOV     DI, DX
                MOV     BL, CS:[DI + pro_op_regoff]    ; OPL register offset
                XOR     BH, BH
                ADD     BX, 40H                 ; reg 0x40+op (Level register)
                CALL    pro_opl_write_a
                POP     BX                      ; restore voice index
                POP     AX                      ; AL = curve_vol (saved earlier)

; ============================================================================
;     LEFT CARRIER (writes reg 0x40+car_op via pro_opl_write_a, additive only)
; ============================================================================
                CMP     BYTE PTR CS:[BX + pro_voice_additive], 0
                JZ      SHORT vrv_lm_skip_car
                SHL     BX, 1
                MOV     CX, CS:[BX + pro_voice_car_tl_max]
                MUL     CL
                MOV     CL, 3FH
                DIV     CL
                SUB     CL, AL
                MOV     AX, CS:[BX + pro_voice_car_tl_base]
                SHR     BX, 1
                MOV     CH, AL
                SHL     CH, 1
                SHL     CH, 1
                SHL     CH, 1
                SHL     CH, 1
                SHL     CH, 1
                SHL     CH, 1
                OR      CL, CH
                XOR     CH, CH
                PUSH    BX
                XOR     DH, DH
                MOV     DL, CS:[BX + pro_op_perm + 9]   ; carrier op index
                MOV     DI, DX
                MOV     BL, CS:[DI + pro_op_regoff]
                XOR     BH, BH
                ADD     BX, 40H
                CALL    pro_opl_write_a
                POP     BX

; ============================================================================
;     RIGHT MODULATOR (writes OPL reg 0x40+mod_op via pro_opl_write_b)
; ============================================================================
                ; The L-CARRIER JZ lands on this POP AX, so both paths
                ; (carrier ran / carrier skipped) restore the saved vol
                ; here. The immediate PUSH AX keeps a copy on the stack
                ; for the R-MOD section to consume in turn.
vrv_lm_skip_car: POP    AX
                PUSH    AX

                ; ---- compute right pan scale: volcurve_b[(0x7F - pan) / 2] ----
                MOV     DL, 7FH
                SUB     DL, CS:[SI + pro_ch_pan]
                SHR     DL, 1                   ; DL = (0x7F - pan) / 2
                CMP     DL, 3FH
                JBE     SHORT vrv_rm_pan_ok
                MOV     DL, 3FH
vrv_rm_pan_ok:  PUSH    BX
                MOV     BL, DL
                XOR     BH, BH
                MOV     BL, CS:[BX + pro_volcurve_b]
                MOV     DL, 3FH
                SUB     DL, BL
                POP     BX
                MUL     DL
                MOV     DL, 3FH
                DIV     DL
                MOV     DL, AL
                POP     AX
                SUB     AL, DL                  ; AL = vol - scaled (right)

                ; The right side can underflow because scaled may exceed
                ; vol when pan is far left; clamp the wrapped result to 0.
                CMP     AL, 0
                JAE     SHORT vrv_rm_al_ok
                XOR     AL, AL
vrv_rm_al_ok:   XOR     AH, AH
                CMP     DL, 3FH
                JBE     SHORT vrv_rm_dl_ok
                MOV     DL, 3FH
vrv_rm_dl_ok:   MOV     DI, AX
                MOV     AL, CS:[DI + pro_volcurve_b]
                PUSH    AX
                SHL     BX, 1
                MOV     CX, CS:[BX + pro_voice_mod_tl_max]
                MUL     CL
                MOV     CL, 3FH
                DIV     CL
                SUB     CL, AL
                MOV     AX, CS:[BX + pro_voice_mod_tl_base]
                SHR     BX, 1
                MOV     CH, AL
                SHL     CH, 1
                SHL     CH, 1
                SHL     CH, 1
                SHL     CH, 1
                SHL     CH, 1
                SHL     CH, 1
                OR      CL, CH
                XOR     CH, CH
                PUSH    BX
                XOR     DH, DH
                MOV     DL, CS:[BX + pro_op_perm]
                MOV     DI, DX
                MOV     BL, CS:[DI + pro_op_regoff]
                XOR     BH, BH
                ADD     BX, 40H
                CALL    pro_opl_write_b
                POP     BX
                POP     AX

; ============================================================================
;     RIGHT CARRIER (writes reg 0x40+car_op via pro_opl_write_b, additive only)
; ============================================================================
                CMP     BYTE PTR CS:[BX + pro_voice_additive], 0
                JZ      SHORT vrv_rm_skip_car
                SHL     BX, 1
                MOV     CX, CS:[BX + pro_voice_car_tl_max]
                MUL     CL
                MOV     CL, 3FH
                DIV     CL
                SUB     CL, AL
                MOV     AX, CS:[BX + pro_voice_car_tl_base]
                SHR     BX, 1
                MOV     CH, AL
                SHL     CH, 1
                SHL     CH, 1
                SHL     CH, 1
                SHL     CH, 1
                SHL     CH, 1
                SHL     CH, 1
                OR      CL, CH
                XOR     CH, CH
                PUSH    BX
                XOR     DH, DH
                MOV     DL, CS:[BX + pro_op_perm + 9]
                MOV     DI, DX
                MOV     BL, CS:[DI + pro_op_regoff]
                XOR     BH, BH
                ADD     BX, 40H
                CALL    pro_opl_write_b
                POP     BX                      ; balances the PUSH BX above;
                                                ; the JZ above skips both
vrv_rm_skip_car: POP    DI
                POP     SI
                POP     DX
                POP     CX
                POP     AX
                RET
pro_voice_render_volume ENDP

; ----------------------------------------------------------------------------
; 0x2165  --  pro_voice_apply_patch
;
;   Loads a 28-byte "instrument patch" into a voice. Called by
;   pro_voice_keyon when the desired patch differs from the one already
;   loaded.
;
;   A patch is 28 bytes = 14 bytes for the modulator op + 14 bytes for
;   the carrier op (a modulator/carrier operator-pair patch record).
;
;   Steps:
;     1. Read patch[0x0C] (the "additive" flag for the modulator op):
;          0 -> voice plays additive (both ops audible)
;          non-zero -> voice plays modulator-only
;        Store the result in voice_additive[voice].
;     2. If additive: precompute the carrier-side TL math:
;          car_tl_base[v]  <- patch[0x00]
;          car_tl_max[v]   <- 0x3F - patch[0x08]
;          car_tl_step[v]  <- car_tl_max[v] / 15
;     3. Always: precompute the modulator-side TL math (same formulas
;        but reading patch[0x0D] and patch[0x15]).
;     4. Push the two 14-byte sub-patches into op_shadow via two calls
;        to pro_op_patch_load, one per operator. Each call also writes
;        the OPL chip with the new envelope/timbre values (both banks
;        via pro_opl_write).
;
;   Type:        Subroutine
;   Category:    Voice management
;   Callers:     pro_voice_keyon
;   Callees:     pro_op_patch_load (twice -- once per operator)
;
;   Inputs:
;     BX  --  voice index 0..8
;     CX  --  CS-relative pointer to the 28-byte patch record
;
;   Outputs:     none
;
;   Side effects:
;     voice_additive[v], voice_mod_tl_*[v], voice_car_tl_*[v] all
;     updated. Both operators' OPL register banks rewritten via
;     pro_op_patch_load -> pro_op_apply_all_regs.
; ----------------------------------------------------------------------------
pro_voice_apply_patch PROC NEAR
                PUSH    AX
                PUSH    BX
                PUSH    CX
                PUSH    DX
                PUSH    SI
                PUSH    DI
                MOV     DI, CX
                PUSH    BX
                PUSH    CX
                PUSH    DX
                MOV     BYTE PTR CS:[BX + pro_voice_additive], 1
                CMP     BYTE PTR CS:[DI + 0CH], 0
                JE      SHORT vap_additive
                MOV     BYTE PTR CS:[BX + pro_voice_additive], 0
                JMP     SHORT vap_modonly
vap_additive:   SHL     BX, 1
                MOV     AH, 0
                MOV     AL, CS:[DI]
                MOV     CS:[BX + pro_voice_car_tl_base], AX
                MOV     AL, 3FH
                MOV     AH, CS:[DI + 8]
                SUB     AL, AH
                MOV     AH, 0
                MOV     CS:[BX + pro_voice_car_tl_max], AX
                MOV     DX, 0
                MOV     CX, 0FH
                DIV     CX
                MOV     CS:[BX + pro_voice_car_tl_step], AX
                JMP     SHORT vap_mod_pass
vap_modonly:    SHL     BX, 1
vap_mod_pass:   MOV     AH, 0
                MOV     AL, CS:[DI + 0DH]
                MOV     CS:[BX + pro_voice_mod_tl_base], AX
                MOV     AL, 3FH
                MOV     AH, CS:[DI + 15H]
                SUB     AL, AH
                MOV     AH, 0
                MOV     CS:[BX + pro_voice_mod_tl_max], AX
                MOV     DX, 0
                MOV     CX, 0FH
                DIV     CX
                MOV     CS:[BX + pro_voice_mod_tl_step], AX
                POP     DX
                POP     CX
                POP     BX
                ADD     DI, 1AH
                MOV     AL, CS:[DI]
                INC     DI
                XOR     DH, DH
                MOV     DL, CS:[DI]
                MOV     SI, CX
                ADD     SI, 0DH
                SHL     BX, 1
                MOV     DI, BX
                MOV     BH, 0
                MOV     BL, CS:[DI + pro_voice_oppair]
                PUSH    DX
                MOV     DX, AX
                CALL    pro_op_patch_load
                POP     DX
                INC     DI
                MOV     BH, 0
                MOV     BL, CS:[DI + pro_voice_oppair]
                MOV     CX, SI
                CALL    pro_op_patch_load
                POP     DI
                POP     SI
                POP     DX
                POP     CX
                POP     BX
                POP     AX
                RET
pro_voice_apply_patch ENDP

; ----------------------------------------------------------------------------
; 0x2212  --  pro_opl_write
;
;   The OPL-write dispatcher. On PAS, every OPL chip access goes here
;   and is then fanned out to BOTH bank A (pro_opl_write_a) and bank B
;   (pro_opl_write_b) so that stereo voices remain synchronized.
;
;   The one exception is register 0x01 (wave-select enable) when PAS
;   mode is active: that register is owned by the PAS-side init code,
;   so this dispatcher short-circuits the write to a no-op when
;   (pas_mode_flag != 0 && BL == 0x01). The bytes for the wave-select
;   enable do still get written, but via the PAS BIOS path, not
;   directly here.
;
;   Type:        Subroutine
;   Category:    OPL register I/O (dispatcher)
;   Callers:     Every per-register writer (pro_opl_write_rhythm,
;                pro_opl_write_notesel, pro_opl_write_op_level,
;                pro_opl_write_voice_feedback, pro_opl_write_op_ar_dr,
;                pro_opl_write_op_sl_rr, pro_opl_write_op_flags_mult,
;                pro_opl_write_op_waveform), pro_voice_render_freq,
;                pro_silence_and_reset
;   Callees:     pro_opl_write_a, pro_opl_write_b
;
;   Inputs:
;     BL  --  OPL register number (0x00..0xF5)
;     CL  --  value to write
;
;   Outputs:     none
;
;   Side effects:
;     One OPL register written on each bank (two register writes
;     total), unless the short-circuit fires.
; ----------------------------------------------------------------------------
pro_opl_write   PROC    NEAR
                CMP     BYTE PTR CS:pro_pas_mode_flag, 0
                JZ      SHORT plw_both
                CMP     BL, 01H
                JNE     SHORT plw_both
                RET
plw_both:       CALL    pro_opl_write_a
                CALL    pro_opl_write_b
                RET
pro_opl_write   ENDP

; ----------------------------------------------------------------------------
; 0x2227  --  pro_opl_write_a
;
;   The hardware-write primitive for OPL bank A (the LEFT channel on
;   PAS). Implements the canonical OPL write sequence:
;
;     1. (PAS-only) if BL is in the per-voice feedback band (0xC0..0xC8),
;        OR bit 5 (0x20) into CL -- this is the "left channel enable"
;        flag in the dual-OPL2 stereo wiring.
;     2. OUT pro_port_reg_a, BL   -- select internal register #BL
;     3. IN  AL, port_reg_a x 5   -- dummy reads (~3.3 us settling delay
;                                    after the register-select write)
;     4. OUT pro_port_data_a, CL  -- send the data byte
;     5. IN  AL, port_status_a x 33  -- post-write settling loop (~23 us
;                                       total, matches OPL2 spec)
;
;   Type:        Subroutine
;   Category:    OPL register I/O (chip-access primitive, bank A)
;   Callers:     pro_opl_write (dispatcher), pro_voice_render_volume
;                (left channel), pro_load_patch_bank (PAS wake-up)
;   Callees:     none
;
;   Inputs:
;     BL  --  OPL register number
;     CL  --  value to write
;
;   Outputs:     none
;
;   Side effects:
;     OUTs to ports 0x388 / 0x389; INs from ports 0x388 / 0x388 (status)
;     used purely for timing.
; ----------------------------------------------------------------------------
pro_opl_write_a PROC NEAR
                PUSH    AX
                PUSH    DX
                PUSH    CX
                CMP     BYTE PTR CS:pro_pas_mode_flag, 0
                JE      SHORT plwa_no_stereo
                CMP     BL, 0C0H
                JB      SHORT plwa_no_stereo
                CMP     BL, 0C8H
                JA      SHORT plwa_no_stereo
                OR      CL, 20H                 ; bit 5 = "left channel on"
                                                ; (PAS dual-OPL2 stereo bit
                                                ; added to per-voice feedback
                                                ; register 0xC0..0xC8 only)
plwa_no_stereo: MOV     DX, CS:pro_port_reg_a
                MOV     AX, BX
                OUT     DX, AL
                ; OPL chip-ready delay: five IN AL, DX reads after the
                ; index write give the chip ~3.3 us to absorb the new
                ; register-select value before we send the data byte.
                ; Each IN AL,DX stalls the bus for 4-5 cycles regardless
                ; of CPU speed, so this works on every 286/386/etc.
                IN      AL, DX
                IN      AL, DX
                IN      AL, DX
                IN      AL, DX
                IN      AL, DX
                MOV     DX, CS:pro_port_data_a
                MOV     AX, CX
                OUT     DX, AL
                MOV     CX, 21H
                MOV     DX, CS:pro_port_status_a
plwa_delay:     IN      AL, DX                  ; post-write settling: 33
                LOOP    plwa_delay              ; reads from status port
                                                ; (~23 us total per OPL2 spec)
                POP     CX
                POP     DX
                POP     AX
                RET
pro_opl_write_a ENDP

; ----------------------------------------------------------------------------
; 0x2263  --  pro_opl_write_b
;
;   Identical to pro_opl_write_a but for bank B (the RIGHT channel on
;   PAS). The PAS stereo enable bit is 0x10 here (bit 4 = right) versus
;   0x20 (bit 5 = left) in bank A; the I/O ports are 0x38A / 0x38B
;   (vs. 0x388 / 0x389 for bank A).
;
;   Type:        Subroutine
;   Category:    OPL register I/O (chip-access primitive, bank B)
;   Callers:     pro_opl_write (dispatcher), pro_voice_render_volume
;                (right channel), pro_load_patch_bank (PAS wake-up)
;   Callees:     none
;
;   Inputs:
;     BL  --  OPL register number
;     CL  --  value to write
;
;   Outputs:     none
;
;   Side effects:
;     OUTs to ports 0x38A / 0x38B; INs from those same ports for timing.
; ----------------------------------------------------------------------------
pro_opl_write_b PROC NEAR
                PUSH    AX
                PUSH    DX
                PUSH    CX
                CMP     BYTE PTR CS:pro_pas_mode_flag, 0
                JE      SHORT plwb_no_stereo
                CMP     BL, 0C0H
                JB      SHORT plwb_no_stereo
                CMP     BL, 0C8H
                JA      SHORT plwb_no_stereo
                OR      CL, 10H                 ; bit 4 = "right channel on"
                                                ; (PAS dual-OPL2 stereo bit
                                                ; for the right-side bank)
plwb_no_stereo: MOV     DX, CS:pro_port_reg_b
                MOV     AX, BX
                OUT     DX, AL
                ; OPL chip-ready delay: five dummy reads = ~3.3 us
                ; settling time after the register-select write. See
                ; pro_opl_write_a for the full explanation.
                IN      AL, DX
                IN      AL, DX
                IN      AL, DX
                IN      AL, DX
                IN      AL, DX
                MOV     DX, CS:pro_port_data_b
                MOV     AX, CX
                OUT     DX, AL
                MOV     CX, 21H
                MOV     DX, CS:pro_port_status_b
plwb_delay:     IN      AL, DX                  ; post-write settling: 33
                LOOP    plwb_delay              ; reads (~23 us total)
                POP     CX
                POP     DX
                POP     AX
                RET
pro_opl_write_b ENDP

; ----------------------------------------------------------------------------
; 0x229F  --  pro_opl_init_all_ops
;
;   Walks all 18 OPL operators and loads each with one of the two
;   default patches:
;     - if op is a modulator (pro_op_iscarrier[i] == 0): default_patch_mod
;     - if op is a carrier   (pro_op_iscarrier[i] == 1): default_patch_car
;
;   This puts both chips in a known-quiet but valid state -- every
;   envelope cleared, every operator pointed at a sensible waveform.
;   Called only from pro_silence_and_reset. On PAS each OPL write fans
;   out to both banks, so this also implicitly initializes the chip on
;   the right channel.
;
;   Type:        Subroutine
;   Category:    Driver init
;   Callers:     pro_silence_and_reset
;   Callees:     pro_op_patch_stage_load
;
;   Inputs:      none
;   Outputs:     none
;
;   Side effects:
;     ~140+ OPL register writes per bank (18 ops * several regs each).
; ----------------------------------------------------------------------------
pro_opl_init_all_ops PROC NEAR
                PUSH    BX
                PUSH    CX
                PUSH    DX
                PUSH    DI
                MOV     DI, 0
init_loop:      MOV     BX, DI
                MOV     DX, 0
                CMP     BYTE PTR CS:[DI + pro_op_iscarrier], 0
                JE      SHORT init_modulator
                MOV     CX, OFFSET pro_default_patch_car
                CALL    pro_op_patch_stage_load
                JMP     SHORT init_next
init_modulator: MOV     CX, OFFSET pro_default_patch_mod
                CALL    pro_op_patch_stage_load
init_next:      INC     DI
                CMP     DI, 12H
                JNE     SHORT init_loop
                POP     DI
                POP     DX
                POP     CX
                POP     BX
                RET
pro_opl_init_all_ops ENDP

; ----------------------------------------------------------------------------
; 0x22CC  --  pro_op_patch_stage_load
;
;   Copies a 13-byte patch from a CS-relative source into the shared
;   pro_patch_stage scratch buffer, then forwards to pro_op_patch_load
;   pointing at the stage buffer. Used by pro_opl_init_all_ops when
;   loading the two built-in default patches into every operator.
;
;   The stage step exists because pro_op_patch_load doesn't know how
;   to read from arbitrary CS offsets cleanly when the source is in
;   the read-only part of the code segment; copying through the stage
;   buffer normalizes the read path.
;
;   Type:        Subroutine
;   Category:    Driver init
;   Callers:     pro_opl_init_all_ops
;   Callees:     pro_op_patch_load
;
;   Inputs:
;     BX  --  operator index 0..17
;     CX  --  CS-relative pointer to a 13-byte patch
;
;   Outputs:     none
;
;   Side effects:
;     pro_patch_stage[0..12] overwritten; then pro_op_patch_load's
;     side effects fire (op_shadow updated, both OPL banks rewritten).
; ----------------------------------------------------------------------------
pro_op_patch_stage_load PROC NEAR
                PUSH    BX
                PUSH    CX
                PUSH    DX
                PUSH    DI
                PUSH    SI
                MOV     DI, 0
                MOV     SI, CX
                MOV     CH, 0
stage_copy:     MOV     CL, CS:[SI]
                MOV     CS:[DI + pro_patch_stage], CL
                INC     SI
                INC     DI
                CMP     DI, 0DH
                JNE     SHORT stage_copy
                POP     SI
                MOV     CX, OFFSET pro_patch_stage
                CALL    pro_op_patch_load
                POP     DI
                POP     DX
                POP     CX
                POP     BX
                RET
pro_op_patch_stage_load ENDP

; ----------------------------------------------------------------------------
; 0x22F3  --  pro_op_patch_load
;
;   Loads a 13-byte patch into the operator's shadow slot and tail-
;   calls pro_op_apply_all_regs to push every affected OPL register
;   (on both banks via the pro_opl_write dispatcher).
;
;   Steps:
;     1. Compute the byte offset within pro_op_shadow as op_index * 14.
;        The shift+add sequence is the hand-rolled 8086 way to multiply
;        by 14 (= 2 + 4 + 8). This same
;        pattern appears in each per-register writer below.
;     2. Copy 13 bytes from CS:[CX..CX+12] into op_shadow.
;     3. Store (DL & 0x03) into op_shadow[+13] (FB/algorithm bits).
;     4. Call pro_op_apply_all_regs, which walks the 8 per-op write
;        helpers and pushes every relevant OPL register for this op.
;
;   Type:        Subroutine
;   Category:    Operator patch programming
;   Callers:     pro_voice_apply_patch (twice per call; once per op),
;                pro_op_patch_stage_load
;   Callees:     pro_op_apply_all_regs
;
;   Inputs:
;     BX  --  operator index 0..17
;     CX  --  CS-relative pointer to the 13-byte patch
;     DL  --  algorithm/feedback byte (low 2 bits stored at shadow[+13])
;
;   Outputs:     none
;
;   Side effects:
;     op_shadow[op*14..op*14+13] updated. All 8 OPL register groups for
;     this op rewritten on both banks via pro_op_apply_all_regs.
; ----------------------------------------------------------------------------
pro_op_patch_load PROC NEAR
                PUSH    CX
                PUSH    DX
                PUSH    SI
                PUSH    DI
                MOV     SI, BX
                PUSH    AX
                PUSH    BX
                PUSH    CX
                ; Hand-rolled multiply: AX = op_index * 14 = 2 + 4 + 8.
                ; The op_shadow array stores 14 bytes per operator;
                ; we need the byte offset into it. Same pattern (with
                ; different working registers) recurs in every per-
                ; register writer below.
                MOV     AX, SI
                SHL     AX, 1                   ; AX = op * 2
                MOV     BX, AX
                SHL     AX, 1                   ; AX = op * 4
                MOV     CX, AX
                SHL     AX, 1                   ; AX = op * 8
                ADD     AX, BX                  ; AX = op * 10
                ADD     AX, CX                  ; AX = op * 14
                MOV     SI, AX
                POP     CX
                POP     BX
                POP     AX
                PUSH    DX
                MOV     DI, 0
opl_copy:       PUSH    DI
                MOV     DI, CX
                MOV     DL, CS:[DI]
                MOV     CS:[SI + pro_op_shadow], DL
                POP     DI
                INC     SI
                INC     CX
                INC     DI
                CMP     DI, 0DH
                JNE     SHORT opl_copy
                POP     DX
                AND     DL, 03H
                MOV     CS:[SI + pro_op_shadow], DL
                PUSH    BX
                CALL    pro_op_apply_all_regs
                POP     BX
                POP     DI
                POP     SI
                POP     DX
                POP     CX
                RET
pro_op_patch_load ENDP

; ----------------------------------------------------------------------------
; 0x233C  --  pro_op_apply_all_regs
;
;   Calls each of the eight per-op OPL write helpers in sequence,
;   re-pushing every OPL register affected by this op's patch:
;
;     0xBD              (rhythm-mode + AM/Vib depth)         [global]
;     0x08              (CSM / NOTE-SEL)                     [global]
;     0x40 + op_offset  (KSL + TL)                           [per op]
;     0xC0 + voice      (Feedback + algorithm + stereo bit)  [per voice]
;     0x60 + op_offset  (Attack Rate + Decay Rate)           [per op]
;     0x80 + op_offset  (Sustain Level + Release Rate)       [per op]
;     0x20 + op_offset  (AM/Vib/EG-type/KSR + freq mult)     [per op]
;     0xE0 + op_offset  (waveform select, gated by reg 0x01) [per op]
;
;   Type:        Subroutine
;   Category:    Operator patch programming
;   Callers:     pro_op_patch_load
;   Callees:     The eight per-register writers below.
;
;   Inputs:
;     BX  --  operator index 0..17
;
;   Outputs:     none
;
;   Side effects:
;     ~8 OPL register writes per call (each fanned to both banks).
; ----------------------------------------------------------------------------
pro_op_apply_all_regs PROC NEAR
                CALL    pro_opl_write_rhythm
                CALL    pro_opl_write_notesel
                CALL    pro_opl_write_op_level
                CALL    pro_opl_write_voice_feedback
                CALL    pro_opl_write_op_ar_dr
                CALL    pro_opl_write_op_sl_rr
                CALL    pro_opl_write_op_flags_mult
                CALL    pro_opl_write_op_waveform
                RET
pro_op_apply_all_regs ENDP

; ----------------------------------------------------------------------------
; 0x2355  --  pro_opl_write_rhythm
;
;   Writes OPL register 0xBD (rhythm-mode flags + AM/Vib depth) from the
;   three RAM mirrors. Composed byte:
;
;     bit 7  AM depth   (from pro_opl_amdepth)
;     bit 6  VIB depth  (from pro_opl_vibdepth)
;     bits 5..0  rhythm-mode + BD/SD/TT/CY/HH key-ons (from pro_opl_rhythm)
;
;   Type:        Subroutine
;   Category:    OPL register I/O (per-register writer)
;   Callers:     pro_op_apply_all_regs
;   Callees:     pro_opl_write (dispatches to both banks)
;
;   Inputs:      none (reads driver state mirrors only)
;   Outputs:     none
;
;   Side effects:
;     OPL register 0xBD written on both banks.
; ----------------------------------------------------------------------------
pro_opl_write_rhythm PROC NEAR
                PUSH    BX
                PUSH    CX
                MOV     CX, 0
                CMP     BYTE PTR CS:pro_opl_amdepth, 0
                JE      SHORT rh_no_am
                OR      CL, 80H
rh_no_am:       CMP     BYTE PTR CS:pro_opl_vibdepth, 0
                JE      SHORT rh_no_vib
                OR      CL, 40H
rh_no_vib:      OR      CL, CS:pro_opl_rhythm
                MOV     BX, 0BDH
                CALL    pro_opl_write
                POP     CX
                POP     BX
                RET
pro_opl_write_rhythm ENDP

; ----------------------------------------------------------------------------
; 0x237E  --  pro_opl_write_notesel
;
;   Writes OPL register 0x08 (CSM / NOTE-SEL). The driver only ever
;   uses NOTE-SEL (bit 6): from the mirror pro_opl_notesel, write 0x40
;   if non-zero else 0. NOTE-SEL shifts the key-scaling boundary
;   between MIDI notes; useful only when KSR is enabled in operator
;   patches.
;
;   Type:        Subroutine
;   Category:    OPL register I/O (per-register writer)
;   Callers:     pro_op_apply_all_regs
;   Callees:     pro_opl_write
;
;   Inputs:      none
;   Outputs:     none
;
;   Side effects:
;     OPL register 0x08 written on both banks.
; ----------------------------------------------------------------------------
pro_opl_write_notesel PROC NEAR
                PUSH    BX
                PUSH    CX
                MOV     CX, 0
                CMP     BYTE PTR CS:pro_opl_notesel, 0
                JE      SHORT ns_no
                MOV     CL, 40H
ns_no:          MOV     BX, 8
                CALL    pro_opl_write
                POP     CX
                POP     BX
                RET
pro_opl_write_notesel ENDP

; ----------------------------------------------------------------------------
; 0x2396  --  pro_opl_write_op_level
;
;   Writes OPL register 0x40 + op_offset (per-op KSL + TL). Composed:
;     bits 7..6  KSL  (from op_shadow[op*14 + 0])
;     bits 5..0  TL   (from op_shadow[op*14 + 8])
;
;   Type:        Subroutine
;   Category:    OPL register I/O (per-register writer)
;   Callers:     pro_op_apply_all_regs
;   Callees:     pro_opl_write
;
;   Inputs:
;     BX  --  operator index 0..17
;
;   Outputs:     none
;
;   Side effects:
;     OPL register 0x40 + pro_op_regoff[op] written on both banks.
; ----------------------------------------------------------------------------
pro_opl_write_op_level PROC NEAR
                PUSH    AX
                PUSH    BX
                PUSH    CX
                PUSH    DI
                MOV     DI, BX
                PUSH    AX
                PUSH    BX
                PUSH    CX
                ; AX = op_index * 14 (hand-rolled multiply; see
                ; pro_op_patch_load for the full explanation. 14 = 2+4+8).
                MOV     AX, DI
                SHL     AX, 1                   ; AX = op * 2
                MOV     BX, AX
                SHL     AX, 1                   ; AX = op * 4
                MOV     CX, AX
                SHL     AX, 1                   ; AX = op * 8
                ADD     AX, BX                  ; AX = op * 10
                ADD     AX, CX                  ; AX = op * 14
                MOV     DI, AX
                POP     CX
                POP     BX
                POP     AX
                MOV     AH, 0
                MOV     AL, CS:[DI + pro_op_shadow]
                MOV     CL, 06H
                SHL     AL, CL
                MOV     CX, AX
                MOV     AL, CS:[DI + pro_op_shadow + 8]
                AND     AL, 3FH
                OR      CL, AL
                MOV     BH, 0
                MOV     DI, BX
                MOV     BL, CS:[DI + pro_op_regoff]
                ADD     BL, 40H
                CALL    pro_opl_write
                POP     DI
                POP     CX
                POP     BX
                POP     AX
                RET
pro_opl_write_op_level ENDP

; ----------------------------------------------------------------------------
; 0x23DE  --  pro_opl_write_voice_feedback
;
;   Writes OPL register 0xC0 + voice (per-voice feedback + algorithm
;   + stereo bit). The register is per-voice not per-op, so we only
;   fire on the modulator op of the pair to avoid double-writing.
;
;   The 0xC0+v register is also where bank A's "left enable" (bit 5)
;   and bank B's "right enable" (bit 4) flags live in PAS stereo
;   mode. Those bits are ORed in by the bank-specific pro_opl_write_a /
;   pro_opl_write_b, not here.
;
;   Type:        Subroutine
;   Category:    OPL register I/O (per-register writer)
;   Callers:     pro_op_apply_all_regs
;   Callees:     pro_opl_write
;
;   Inputs:
;     BX  --  operator index 0..17
;
;   Outputs:     none
;
;   Side effects:
;     OPL register 0xC0 + pro_op_voice[op] written on both banks --
;     but ONLY when op is the modulator of its pair.
; ----------------------------------------------------------------------------
pro_opl_write_voice_feedback PROC NEAR
                PUSH    BX
                PUSH    CX
                PUSH    DI
                MOV     DI, BX
                CMP     BYTE PTR CS:[DI + pro_op_iscarrier], 0
                JNE     SHORT fb_skip
                PUSH    AX
                PUSH    BX
                PUSH    CX
                ; AX = op_index * 14 (hand-rolled multiply, same
                ; pattern as pro_op_patch_load).
                MOV     AX, DI
                SHL     AX, 1                   ; AX = op * 2
                MOV     BX, AX
                SHL     AX, 1                   ; AX = op * 4
                MOV     CX, AX
                SHL     AX, 1                   ; AX = op * 8
                ADD     AX, BX                  ; AX = op * 10
                ADD     AX, CX                  ; AX = op * 14
                MOV     DI, AX
                POP     CX
                POP     BX
                POP     AX
                MOV     AH, 0
                MOV     AL, CS:[DI + pro_op_shadow + 2]
                SHL     AX, 1
                MOV     CX, AX
                CMP     BYTE PTR CS:[DI + pro_op_shadow + 12], 0
                JNE     SHORT fb_no_stereo
                INC     CL
fb_no_stereo:   MOV     DI, BX
                MOV     BH, 0
                MOV     BL, CS:[DI + pro_op_voice]
                ADD     BL, 0C0H
                AND     CL, 0FH
                CALL    pro_opl_write
fb_skip:        POP     DI
                POP     CX
                POP     BX
                RET
pro_opl_write_voice_feedback ENDP

; ----------------------------------------------------------------------------
; 0x242E  --  pro_opl_write_op_ar_dr
;
;   Writes OPL register 0x60 + op_offset (Attack Rate + Decay Rate).
;     bits 7..4  AR  (from op_shadow[op*14 + 3])
;     bits 3..0  DR  (from op_shadow[op*14 + 6])
;   Higher AR/DR values = faster envelope.
;
;   Type:        Subroutine
;   Category:    OPL register I/O (per-register writer)
;   Callers:     pro_op_apply_all_regs
;   Callees:     pro_opl_write
;
;   Inputs:
;     BX  --  operator index 0..17
;
;   Outputs:     none
;
;   Side effects:
;     OPL register 0x60 + pro_op_regoff[op] written on both banks.
; ----------------------------------------------------------------------------
pro_opl_write_op_ar_dr PROC NEAR
                PUSH    BX
                PUSH    CX
                PUSH    DI
                MOV     DI, BX
                PUSH    AX
                PUSH    BX
                PUSH    CX
                ; AX = op_index * 14 (hand-rolled multiply).
                MOV     AX, DI
                SHL     AX, 1                   ; AX = op * 2
                MOV     BX, AX
                SHL     AX, 1                   ; AX = op * 4
                MOV     CX, AX
                SHL     AX, 1                   ; AX = op * 8
                ADD     AX, BX                  ; AX = op * 10
                ADD     AX, CX                  ; AX = op * 14
                MOV     DI, AX
                POP     CX
                POP     BX
                POP     AX
                MOV     AH, 0
                MOV     AL, CS:[DI + pro_op_shadow + 3]
                MOV     CL, 04H
                SHL     AL, CL
                MOV     CX, AX
                MOV     AL, CS:[DI + pro_op_shadow + 6]
                AND     AL, 0FH
                OR      CL, AL
                MOV     DI, BX
                MOV     BH, 0
                MOV     BL, CS:[DI + pro_op_regoff]
                ADD     BL, 60H
                CALL    pro_opl_write
                POP     DI
                POP     CX
                POP     BX
                RET
pro_opl_write_op_ar_dr ENDP

; ----------------------------------------------------------------------------
; 0x2474  --  pro_opl_write_op_sl_rr
;
;   Writes OPL register 0x80 + op_offset (Sustain Level + Release Rate).
;     bits 7..4  SL  (from op_shadow[op*14 + 4])
;     bits 3..0  RR  (from op_shadow[op*14 + 7])
;
;   Type:        Subroutine
;   Category:    OPL register I/O (per-register writer)
;   Callers:     pro_op_apply_all_regs
;   Callees:     pro_opl_write
;
;   Inputs:
;     BX  --  operator index 0..17
;
;   Outputs:     none
;
;   Side effects:
;     OPL register 0x80 + pro_op_regoff[op] written on both banks.
; ----------------------------------------------------------------------------
pro_opl_write_op_sl_rr PROC NEAR
                PUSH    BX
                PUSH    CX
                PUSH    DI
                MOV     DI, BX
                PUSH    AX
                PUSH    BX
                PUSH    CX
                ; AX = op_index * 14 (hand-rolled multiply).
                MOV     AX, DI
                SHL     AX, 1                   ; AX = op * 2
                MOV     BX, AX
                SHL     AX, 1                   ; AX = op * 4
                MOV     CX, AX
                SHL     AX, 1                   ; AX = op * 8
                ADD     AX, BX                  ; AX = op * 10
                ADD     AX, CX                  ; AX = op * 14
                MOV     DI, AX
                POP     CX
                POP     BX
                POP     AX
                MOV     AH, 0
                MOV     AL, CS:[DI + pro_op_shadow + 4]
                MOV     CL, 04H
                SHL     AL, CL
                MOV     CX, AX
                MOV     AL, CS:[DI + pro_op_shadow + 7]
                AND     AL, 0FH
                OR      CL, AL
                MOV     DI, BX
                MOV     BH, 0
                MOV     BL, CS:[DI + pro_op_regoff]
                ADD     BL, 80H
                CALL    pro_opl_write
                POP     DI
                POP     CX
                POP     BX
                RET
pro_opl_write_op_sl_rr ENDP

; ----------------------------------------------------------------------------
; 0x24BA  --  pro_opl_write_op_flags_mult
;
;   Writes OPL register 0x20 + op_offset (the operator's four boolean
;   flags + frequency multiplier).
;     bit 7      AM   (tremolo enable; from shadow[+9])
;     bit 6      VIB  (vibrato enable; from shadow[+10])
;     bit 5      EG-type (0=percussive 1=sustained; from shadow[+5])
;     bit 4      KSR  (key-scaling rate enable; from shadow[+11])
;     bits 3..0  MULT (multiplier 0..15; from shadow[+1])
;
;   Type:        Subroutine
;   Category:    OPL register I/O (per-register writer)
;   Callers:     pro_op_apply_all_regs
;   Callees:     pro_opl_write
;
;   Inputs:
;     BX  --  operator index 0..17
;
;   Outputs:     none
;
;   Side effects:
;     OPL register 0x20 + pro_op_regoff[op] written on both banks.
; ----------------------------------------------------------------------------
pro_opl_write_op_flags_mult PROC NEAR
                PUSH    CX
                PUSH    DI
                MOV     DI, BX
                PUSH    AX
                PUSH    BX
                PUSH    CX
                ; AX = op_index * 14 (hand-rolled multiply).
                MOV     AX, DI
                SHL     AX, 1                   ; AX = op * 2
                MOV     BX, AX
                SHL     AX, 1                   ; AX = op * 4
                MOV     CX, AX
                SHL     AX, 1                   ; AX = op * 8
                ADD     AX, BX                  ; AX = op * 10
                ADD     AX, CX                  ; AX = op * 14
                MOV     DI, AX
                POP     CX
                POP     BX
                POP     AX
                MOV     AH, 0
                MOV     AL, CS:[DI + pro_op_shadow + 9]
                MOV     CX, 0
                CMP     AL, 0
                JE      SHORT fm_no_am
                OR      CL, 80H
fm_no_am:       MOV     AL, CS:[DI + pro_op_shadow + 10]
                CMP     AL, 0
                JE      SHORT fm_no_vib
                OR      CL, 40H
fm_no_vib:      MOV     AL, CS:[DI + pro_op_shadow + 5]
                CMP     AL, 0
                JE      SHORT fm_no_eg
                OR      CL, 20H
fm_no_eg:       MOV     AL, CS:[DI + pro_op_shadow + 11]
                CMP     AL, 0
                JE      SHORT fm_no_ksr
                OR      CL, 10H
fm_no_ksr:      MOV     AL, CS:[DI + pro_op_shadow + 1]
                AND     AL, 0FH
                OR      CL, AL
                PUSH    BX
                MOV     DI, BX
                MOV     BH, 0
                MOV     BL, CS:[DI + pro_op_regoff]
                ADD     BL, 20H
                CALL    pro_opl_write
                POP     BX
                POP     DI
                POP     CX
                RET
pro_opl_write_op_flags_mult ENDP

; ----------------------------------------------------------------------------
; 0x2528  --  pro_opl_write_op_waveform
;
;   Writes OPL register 0xE0 + op_offset (operator waveform select).
;   The OPL2 supports four waveforms beyond the default sine; reg 0xE0
;   selects which one this operator outputs. The register is only
;   honored when reg 0x01 bit 5 (the "wave select enable" gate) is on,
;   so if that mirror is zero we skip the write entirely.
;
;   Type:        Subroutine
;   Category:    OPL register I/O (per-register writer)
;   Callers:     pro_op_apply_all_regs
;   Callees:     pro_opl_write
;
;   Inputs:
;     BX  --  operator index 0..17
;
;   Outputs:     none
;
;   Side effects:
;     OPL register 0xE0 + pro_op_regoff[op] written on both banks --
;     only if pro_wave_select_en != 0.
; ----------------------------------------------------------------------------
pro_opl_write_op_waveform PROC NEAR
                PUSH    BX
                PUSH    CX
                PUSH    DI
                CMP     WORD PTR CS:pro_wave_select_en, 0
                JE      SHORT wf_skip
                XOR     BH, BH
                MOV     DI, BX
                PUSH    AX
                PUSH    BX
                PUSH    CX
                ; AX = op_index * 14 (hand-rolled multiply).
                MOV     AX, DI
                SHL     AX, 1                   ; AX = op * 2
                MOV     BX, AX
                SHL     AX, 1                   ; AX = op * 4
                MOV     CX, AX
                SHL     AX, 1                   ; AX = op * 8
                ADD     AX, BX                  ; AX = op * 10
                ADD     AX, CX                  ; AX = op * 14
                MOV     DI, AX
                POP     CX
                POP     BX
                POP     AX
                XOR     CH, CH
                MOV     CL, CS:[DI + pro_op_shadow + 13]
                MOV     DI, BX
                MOV     BL, CS:[DI + pro_op_regoff]
                ADD     BL, 0E0H
                CALL    pro_opl_write
wf_skip:        POP     DI
                POP     CX
                POP     BX
                RET
pro_opl_write_op_waveform ENDP

; ----------------------------------------------------------------------------
; 0x2567  --  pro_silence_and_reset
;
;   The full "reset the chip" sequence. Three phases:
;
;     1. Write 0 to every OPL register from 0x00 to 0xF5 (~246 writes
;        per bank). On PAS each write fans out to both banks via
;        pro_opl_write.
;     2. Set pro_wave_select_en = 0x20 in RAM and write 0x20 to OPL
;        register 0x01. This enables the per-op waveform-select group
;        (regs 0xE0..0xF5) so non-sine waveforms become available.
;     3. Re-load every operator with one of the two default patches via
;        pro_opl_init_all_ops.
;
;   Called from slot 2 (game-initiated reset) and from inside slot 1
;   (after a new patch bank is uploaded).
;
;   Type:        Subroutine
;   Category:    Driver init / global state
;   Callers:     pro_reset_voices (slot 2), pro_load_patch_bank (slot 1)
;   Callees:     pro_opl_write (~247 times), pro_opl_init_all_ops
;
;   Inputs:      none
;   Outputs:     none
;
;   Side effects:
;     ~250 OPL writes per bank; pro_wave_select_en updated; every
;     operator's patch state reset to defaults.
;
;   Notes:
;     This function pushes BX, CX (in that order) and pops BX, CX in the
;     SAME order, not the symmetric CX, BX. Net effect: caller's BX and
;     CX are swapped on return. Harmless because neither caller observes
;     those registers after the call.
; ----------------------------------------------------------------------------
pro_silence_and_reset PROC NEAR
                PUSH    BX
                PUSH    CX
                XOR     BX, BX
                XOR     CX, CX
                JMP     SHORT sar_test
sar_body:       CALL    pro_opl_write
                INC     BX
sar_test:       CMP     BX, 0F6H
                JB      SHORT sar_body
                MOV     WORD PTR CS:pro_wave_select_en, 0020H
                MOV     BX, 0001H
                MOV     CX, CS:pro_wave_select_en
                CALL    pro_opl_write
                CALL    pro_opl_init_all_ops
                ; Asymmetric POP order: BX, CX (same as the PUSH order
                ; above). Swaps caller's BX and CX -- harmless.
                POP     BX
                POP     CX
                RET
pro_silence_and_reset ENDP

; ----------------------------------------------------------------------------
; 0x2591  --  pro_query_state
;
;   The read side of the slot ABI: tells the game what value the driver
;   is currently holding for a given MIDI-state field. The query
;   selects what to read via the MIDI-status high nibble in AH:
;
;     AH = 0xE0   -- pitch-bend wheel for channel AL
;     AH = 0xC0   -- program number for channel AL
;     AH = 0xB0   -- a controller value; CH selects which:
;                       CH = 0x07  main volume
;                       CH = 0x0A  pan
;                       CH = 0x40  sustain pedal
;                       CH = 0x4B  polyphony budget (CL=0xFF: max; else cur)
;     anything else -> return 0xFFFF (the "unknown selector" sentinel)
;
;   Type:        Slot handler
;   Category:    MIDI dispatch (read-side mirror)
;   Dispatch:    Slot 17 (called as: BP=17, AL=idx, AH=class,
;                CH=cc# if class=0xB0, CL=sub if cc=0x4B)
;   Callers:     Game (via dispatch)
;   Callees:     none
;
;   Inputs:
;     AL  --  index (channel or voice; 0..15 or 0..8)
;     AH  --  status class (0xE0/0xC0/0xB0)
;     CH  --  controller# (when AH=0xB0)
;     CL  --  sub-selector (when CH=0x4B)
;
;   Outputs:
;     AX  --  the queried value, or 0xFFFF on unknown selector
;
;   Notes:
;     Contains 2 bytes of dead code (a JMP SHORT to the "unknown" label
;     that's unreachable because both surrounding paths already JMP
;     elsewhere).
; ----------------------------------------------------------------------------
pro_query_state PROC NEAR
                PUSH    SI
                MOV     SI, AX
                AND     SI, 00FFH
                CMP     AH, 0E0H
                JNE     SHORT qry_not_e0
                SHL     SI, 1
                MOV     AX, CS:[SI + pro_ch_pitchbend]
                JMP     SHORT qry_end
qry_not_e0:     CMP     AH, 0C0H
                JNE     SHORT qry_not_c0
                XOR     AH, AH
                MOV     AL, CS:[SI + pro_ch_program]
                JMP     SHORT qry_end
qry_not_c0:     CMP     AH, 0B0H
                JNE     SHORT qry_unknown
                XOR     AH, AH
                CMP     CH, 07H
                JNE     SHORT qry_not_07
                MOV     AL, CS:[SI + pro_ch_volume]
                JMP     SHORT qry_end
qry_not_07:     CMP     CH, 0AH
                JNE     SHORT qry_not_0a
                MOV     AL, CS:[SI + pro_ch_pan]
                JMP     SHORT qry_end
qry_not_0a:     CMP     CH, 40H
                JNE     SHORT qry_not_40
                MOV     AL, CS:[SI + pro_ch_sustain_pedal]
                JMP     SHORT qry_end
qry_not_40:     CMP     CH, 4BH
                JNE     SHORT qry_unknown
                CMP     CL, 0FFH
                JE      SHORT qry_use_max
                MOV     AL, CS:[SI + pro_ch_sustain_count]
                JMP     SHORT qry_end
                JMP     SHORT qry_unknown       ; dead JMP: this branch is
                                                ; unreachable (both arms of
                                                ; the if/else above already JMP
                                                ; to qry_end).
qry_use_max:    MOV     AL, CS:[SI + pro_ch_poly_max]
                JMP     SHORT qry_end
qry_unknown:    MOV     AX, 0FFFFH
qry_end:        POP     SI
                RET
pro_query_state ENDP

; ----------------------------------------------------------------------------
; 0x25FE  --  pro_load_patch_bank
;
;   The major PAS-specific function. Steps:
;
;     1. Copy ES:[AX..AX+bank_size-1] into CS:[pro_bank_buf...].
;     2. Call pro_silence_and_reset.
;     3. INT 0x2F with AX=0xBC01 -- Media Vision PAS Multiplex API
;        "are you present?" call. Returns AH=0x4D AL=0x56 if PAS is
;        installed.
;     4. If not PAS: return AX=0xFFFF (sentinel).
;     5. If PAS and DX > 0:
;          a. Set pro_pas_mode_flag = 1.
;          b. Make a "wake-up" write to OPL bank B (BX=0x05, CX=0x0001).
;     6. INT 0x2F with AX=0xBC03 -- "give me the driver function table".
;        Returns ES:BX pointing to a table of far pointers.
;     7. Copy ES:[BX] (4 bytes) into pro_pas_handler_a.
;        Copy ES:[BX+0x24] (4 bytes) into pro_pas_handler_b.
;     8. If PAS mode active: call pro_pas_handler_b(BX=0, CX=1).
;     9. CL=0x0F; call pro_set_master_volume (force master to mid-level).
;    10. Return AX=0x25FE (self-id), CX=0x0800.
;
;   Type:        Slot handler
;   Category:    Bank loading + PAS detection (the unique-to-PRO slot)
;   Dispatch:    Slot 1 (called as: BP=1, ES:AX = src far ptr)
;   Callers:     Game (via dispatch)
;   Callees:     pro_silence_and_reset, pro_opl_write_b,
;                pro_set_master_volume, pro_pas_handler_b
;
;   Inputs:
;     ES:AX  --  far pointer to source bank in the game's memory
;
;   Outputs:
;     AX  --  0x25FE on success (self-id) or 0xFFFF if PAS detect failed
;     CX  --  0x0800 (format/version handshake)
;
;   Side effects:
;     pro_bank_buf overwritten with pro_bank_size bytes from ES:AX.
;     Chip reset + master volume forced to 0x0F. On PAS: populates
;     pro_pas_handler_a and pro_pas_handler_b from the Multiplex
;     function table, and arms pro_pas_mode_flag.
; ----------------------------------------------------------------------------
pro_load_patch_bank PROC NEAR
                PUSH    BX
                PUSH    DX
                PUSH    SI
                PUSH    DI
                MOV     SI, AX
                XOR     DI, DI
                MOV     CX, CS:pro_bank_size
                JMP     SHORT lpb_test
lpb_body:       MOV     BL, ES:[SI]
                MOV     CS:[DI + pro_bank_buf], BL
                INC     SI
                INC     DI
                DEC     CX
lpb_test:       OR      CX, CX
                JNZ     SHORT lpb_body
                CALL    pro_silence_and_reset
                MOV     AX, 0BC01H
                INT     2FH
                CMP     AH, 4DH
                JNE     SHORT lpb_no_pas
                CMP     AL, 56H
                JE      SHORT lpb_pas_found
lpb_no_pas:     MOV     AX, 0FFFFH
                JMP     SHORT lpb_end
lpb_pas_found:  CMP     DX, 0
                JBE     SHORT lpb_skip_init
                MOV     AL, 1
                MOV     CS:pro_pas_mode_flag, AL
                MOV     BX, 0005H
                MOV     CX, 0001H
                CALL    pro_opl_write_b
lpb_skip_init:  MOV     AX, 0BC03H
                INT     2FH
                PUSH    ES
                MOV     ES, DX
                MOV     AX, ES:[BX]
                MOV     CX, ES:[BX + 2]
                MOV     CS:WORD PTR pro_pas_handler_a, AX
                MOV     CS:WORD PTR pro_pas_handler_a + 2, CX
                MOV     AX, ES:[BX + 24H]
                MOV     CX, ES:[BX + 26H]
                MOV     CS:WORD PTR pro_pas_handler_b, AX
                MOV     CS:WORD PTR pro_pas_handler_b + 2, CX
                POP     ES
                CMP     BYTE PTR CS:pro_pas_mode_flag, 0
                JNZ     SHORT lpb_no_pas_init
                XOR     BX, BX
                MOV     CX, 0001H
                CALL    DWORD PTR CS:pro_pas_handler_b
lpb_no_pas_init: MOV    CL, 0FH
                CALL    pro_set_master_volume
                MOV     AX, 25FEH
lpb_end:        MOV     CL, 0
                MOV     CH, 8
                POP     DI
                POP     SI
                POP     DX
                POP     BX
                RET
pro_load_patch_bank ENDP

; ----------------------------------------------------------------------------
; 0x2693  --  pro_get_info
;
;   The "what are you?" query. The DUDE family reserves slot 0 for a
;   short capability descriptor returned in four byte registers.
;
;     AH = 1   -- DUDE interface version
;     AL = 3   -- device identifier (same as AdLib: 3 = OPL2-family).
;                 The PAS driver reuses the AdLib device-id because
;                 from a game-script perspective both expose the same
;                 9-voice FM interface; the PAS-specific bits live
;                 below the DUDE ABI.
;     CH = 0   -- auxiliary capability flags. 0 here means "plain
;                 melodic FM, no extras".
;     CL = 9   -- number of melodic voices the driver supports.
;
;   Type:        Slot handler
;   Category:    Capability query
;   Dispatch:    Slot 0 (called as: BP=0; no other arguments)
;   Callers:     Game (via dispatch)
;   Callees:     none
;
;   Inputs:      none
;
;   Outputs:
;     AH  --  1 (DUDE iface version)
;     AL  --  3 (device id, OPL2-family)
;     CH  --  0 (no extra capabilities)
;     CL  --  9 (voice count)
; ----------------------------------------------------------------------------
pro_get_info   PROC    NEAR
                MOV     AH, 1
                MOV     AL, 3
                MOV     CH, 0
                MOV     CL, 9
                RET
pro_get_info   ENDP

; ----------------------------------------------------------------------------
; Glossary of acronyms used in this file (alphabetical)
;
;   ALG       Algorithm (FM connection between two operators: additive
;             vs. modulator->carrier).
;   AM        Amplitude Modulation depth (tremolo).
;   AR        Attack Rate (operator envelope).
;   bank A    PAS's left-channel OPL2, addressed at ports 0x388/0x389
;             (and status port 0x388). All "bank A" register writes
;             go through pro_opl_write_a.
;   bank B    PAS's right-channel OPL2, addressed at ports 0x38A/0x38B
;             (status 0x38A). All "bank B" writes go through
;             pro_opl_write_b.
;   CC        MIDI Continuous Controller (e.g. CC#7 = main volume,
;             CC#10 = pan, CC#64 = sustain pedal, CC#75 = polyphony
;             budget).
;   CSM       Composite Sine Mode (an OPL feature this driver doesn't use).
;   DR        Decay Rate (operator envelope).
;   dual-OPL2 The PAS card's stereo design: two YM3812 chips wired as
;             left/right banks. The OPL3 chip from Yamaha later
;             integrated this dual-OPL design into a single die, but
;             the PAS predates OPL3 and uses two physical OPL2s.
;   DUDE      Dynamix's universal sound-driver container format. The
;             file begins with the magic numbers 0x87654321 and
;             0xFEDCBA98, the ASCII tag "dude", and a device-name
;             string. See the dispatch-ABI section above.
;   EG-type   Envelope-type bit: 0=percussive, 1=sustained.
;   FB        Feedback (per-voice modulator self-feedback amount).
;   F-num     F-number, the 10-bit OPL pitch encoding (used together
;             with the 3-bit "block" to pick the actual frequency).
;   FBOV      Unrelated to this driver; noted only because FBOV-style
;             overlays appear elsewhere in the game -- the PRO driver
;             itself is a flat single-segment binary.
;   FM        Frequency Modulation (the dominant OPL synthesis mode).
;   INT 2F    DOS Multiplex interrupt. Used here to talk to the Media
;             Vision PAS BIOS via the "PAS Multiplex API" (AX=0xBC01
;             for "are you present?", AX=0xBC03 for "give me the
;             function table"). See pro_load_patch_bank.
;   KEY-ON    Bit 5 of reg 0xB0+v; begins / sustains a note.
;   KSL       Key-Scale Level (per-operator attenuation that increases
;             with note pitch -- imitates acoustic instruments getting
;             quieter at higher pitches).
;   KSR       Key-Scale Rate (per-operator envelope speed-up with pitch).
;   LRU       Least Recently Used (the voice-allocation policy; see
;             pro_voice_lru and pro_voice_lru_remove).
;   MIDI      Musical Instrument Digital Interface. The "byte stream"
;             convention this driver consumes. Channels 0..15, notes
;             0..127, velocities 0..127, controllers 0..127.
;   Multiplex Term used by Media Vision for their INT 2F API. Not a
;             general DOS term -- "PAS Multiplex" specifically means
;             the AX=0xBC0x calls.
;   MULT      Frequency multiplier (per-operator integer ratio of op
;             frequency to voice F-number).
;   OPL2      Yamaha YM3812 FM synthesizer chip. The PAS contains two
;             of these (one per stereo bank).
;   OPL3      Yamaha YMF262, OPL2's stereo successor. NOT what the
;             PAS uses -- the PAS predates OPL3 and uses two discrete
;             OPL2s in parallel.
;   PAS       Pro AudioSpectrum (Media Vision, 1991). The card this
;             driver targets. Also covers PAS+ (1992) and PAS-16
;             (1992+), which all expose the same stereo dual-OPL2
;             interface from the driver's perspective.
;   PAS handlers
;             Far pointers populated at runtime by pro_load_patch_bank
;             into pro_pas_handler_a (PAS OPL-write helper) and
;             pro_pas_handler_b (PAS init/setup helper). Used by
;             pro_set_master_volume and pro_reset_voices to delegate
;             specific writes through the PAS BIOS rather than going
;             direct to OPL ports.
;   patch     A 28-byte instrument descriptor (14 bytes per operator).
;             Patches live in pro_bank_buf, indexed by program number.
;   program   In MIDI, the "instrument" number (0..127). The driver
;             caches per-channel program numbers in pro_ch_program;
;             the next note-on may trigger a patch reload.
;   RR        Release Rate (operator envelope).
;   SL        Sustain Level (operator envelope).
;   SOA       Struct-Of-Arrays (storage layout where each "field" is
;             its own array indexed by the same index).
;   stereo bit
;             In PAS mode, the 0xC0+v feedback register's bit 5 (left)
;             and bit 4 (right) act as per-bank channel enables. ORed
;             in by pro_opl_write_a / pro_opl_write_b automatically.
;   TL        Total Level (per-operator attenuation: 0=loud, 0x3F=silent).
;             "Total level" is misleading: it's a *cut*, not a gain.
;   VIB       Vibrato depth.
;   voice     One of the chip's 9 polyphonic slots. On PAS, a voice
;             exists on BOTH banks simultaneously (same voice number,
;             different attenuations) -- pan is achieved by writing
;             different TL values to the same voice on each bank.
;
; If you encounter a term not in this glossary, check adl.asm's
; glossary (the AdLib driver) -- the OPL-side terminology is shared.
; ----------------------------------------------------------------------------

                END     _start
