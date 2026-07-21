; ============================================================================
; Sx.SSM.SBP.bin -- Dynamix DUDE-format Sound Blaster Pro (OPL2) sound driver, v2.24
;
; Shipped with "Betrayal at Krondor" (Dynamix / Sierra, 1993).
;
; Packing: TASM + TLINK produce an MZ .EXE; PACKOVL strips the MZ header to
; the flat ORG-0 image, then LZW-packs it into SX.OVL.
; ============================================================================

; ----------------------------------------------------------------------------
; What this driver is
;
; This is the Dynamix DUDE-format sound driver for the Sound Blaster Pro v1
; (1991). The SB Pro v1 is built around the same Yamaha YM3812 OPL2 FM-
; synthesis chip used by the AdLib card (at the same I/O ports 0x388/
; 0x389) plus a stereo mixer chip at 0x224/0x225. This driver controls
; the OPL portion and uses the mixer for master volume; the SB's DAC is
; the responsibility of a separate driver.
;
; The driver communicates with the game through the DUDE dispatch ABI:
; one entry point at offset 0x194A, eighteen "slots", each slot a
; different request like "play this note" or "change this controller".
;
; The SB Pro v1's defining feature beyond AdLib is *stereo*: the chip
; pair has two OPL-style register banks (left and right), and the
; driver computes a separate Total-Level value for each side based on
; the MIDI pan controller. The two banks are mapped to different I/O
; ports (left = 0x220/0x222, right = 0x222/0x224), which is what the
; "mixer table" in the data section catalogues.
; ----------------------------------------------------------------------------

; ----------------------------------------------------------------------------
; About the OPL2 (Yamaha YM3812) chip
;
; The OPL2 is an FM synthesizer with 9 polyphonic voices, each built from
; 2 operators (a modulator + a carrier). The host CPU talks to it via two
; I/O ports per side (the AdLib has one side; the SB Pro v1 has two):
;
;   port 0x388  (the "index" port)  -- write the # of the register to set
;   port 0x389  (the "data" port)   -- write the value
;
; A single write to one of the chip's internal registers is therefore a
; pair of OUT instructions. The chip needs ~3.3 us between the index and
; data writes; this driver uses dummy IN reads as a portable busy-wait.
;
; Most chip parameters live in one of these register groups:
;   0x20-0x35  AM/Vib/EG/KSR/MULT (per operator)
;   0x40-0x55  KSL + TL (per operator)
;   0x60-0x75  AR + DR
;   0x80-0x95  SL + RR
;   0xA0-0xA8  F-number low byte (per voice)
;   0xB0-0xB8  F-number high + block + KEY-ON
;   0xBD       Rhythm + AM/Vib depth
;   0xC0-0xC8  Feedback + ALG + stereo
;   0xE0-0xF5  Waveform select (when reg 0x01 bit 5 is on)
;
; "Total level" (TL) is an attenuation: 0 = loud, 0x3F = silent.
; "F-number" is the 10-bit OPL pitch encoding. The 3-bit "block" (octave)
; combines with F-num to set frequency.
;
; The SB Pro adds a *mixer chip* at 0x224/0x225 alongside the OPL ports.
; Mixer reg 0x26 packs the FM-channel volume as 4 bits left + 4 bits
; right into one byte; the driver writes the mixer (not the OPL) to
; implement master volume.
;
; The SB Pro also exposes the OPL2 twice -- as a left bank at
; 0x220/0x222 and a right bank at 0x222/0x224 -- so the driver can
; write different per-side TL values for each operator to implement
; stereo panning. The two writers below (sbp_opl_write_op_level_l and
; sbp_opl_write_op_level_r) route through these alternate port pairs.
; ----------------------------------------------------------------------------

; ----------------------------------------------------------------------------
; About the DUDE dispatch ABI
;
; The game does:
;
;   MOV  BP, <slot index>
;   <set up AL/CH/CL/etc per slot's convention>
;   CALL FAR sbp_seg:sbp_dispatch
;
; Where:
;   BP    = slot index (0..17)
;   AL    = MIDI channel (0..15) for slots that use one
;   CL    = MIDI data byte 1   (vel / CC value / pitch-bend low)
;   CH    = MIDI data byte 2   (note / CC# / pitch-bend high)
;   ES:AX = far pointer to a patch bank (slot 1 only)
;
; The dispatch trampoline (12 bytes) at 0x194A does:
;   PUSH BP
;   SHL  BP, 1
;   MOV  BP, CS:[BP + sbp_func_table]
;   CALL BP
;   POP  BP
;   RETF
;
; Slot list (same conventions as the ADL driver):
;   Slot  0  sbp_get_info               -- driver descriptor
;   Slot  1  sbp_load_patch_bank        -- ES:AX = src
;   Slot  2  sbp_reset_voices           -- silence + reset + mixer init
;   Slot  4  sbp_midi_note_off
;   Slot  5  sbp_midi_note
;   Slot  7  sbp_midi_control_change
;   Slot  8  sbp_midi_program_change
;   Slot 10  sbp_midi_pitch_bend
;   Slot 11  sbp_set_global_param_11d
;   Slot 12  sbp_set_master_volume      -- writes SB Pro mixer reg 0x26
;   Slot 13  sbp_set_master_enable
;   Slot 17  sbp_query_state
;
; Slots 3, 6, 9, 14, 15, 16 all share a 1-byte RET stub (sbp_slot_unused_ret).
; ----------------------------------------------------------------------------

; ----------------------------------------------------------------------------
; How to read this source
;
; - Lines like `MOV BX, AX` are CPU instructions ("opcodes"). The first
;   operand is the destination, the second is the source -- read it as
;   "BX = AX". This is the "Intel" order; AT&T-style "MOV AX, BX" with
;   the destination second is a different convention and not used here.
;
; - Lines like `sbp_voice_note DB 11 DUP(0FFH)` declare data: the
;   label `sbp_voice_note` names this address, `DB` says "the
;   following are bytes", `DW` would say "the following are 16-bit
;   words", and `11 DUP(0FFH)` means "eleven copies of the value 0xFF
;   (255)".
;
; - `CS:[BX + label]` is a memory access where:
;     * `CS:` says "use the Code Segment register as the base"
;     * `[BX + label]` is the offset, computed at runtime as the
;       contents of register BX plus the constant `label`.
;   In our flat single-segment driver, every read/write uses CS:
;   because the data and code share one segment (TASM `.MODEL TINY`).
;
; - Every function below begins with `<name> PROC NEAR` and ends with
;   `<name> ENDP`. Inside, labels like `noteoff_test:` are jump
;   targets local to the function (prefixed with a 4-letter function
;   nickname so they don't collide).
;
; - Numbers ending in `H` are hexadecimal (3FH = 63). Plain numbers
;   are decimal. Numbers starting with a letter (`0AH`) need a leading
;   `0` to satisfy TASM's parser, which uses the first character to
;   disambiguate identifiers from numbers.
;
; - Calling convention: every slot handler is reached via the dispatch
;   trampoline with BP = slot index. Per-slot register arguments are
;   documented at each handler's prologue. Internal helpers pass
;   arguments in registers too (BX = voice index; CL = value; etc.);
;   the exact convention is documented at each helper's prologue.
;
; - Anywhere you see five identical `IN AL, DX` instructions in a row,
;   that's a hardware-timing busy-wait (see sbp_opl_write). The chip
;   needs a few microseconds between the index write and the data
;   write, and dummy port reads are the canonical period-correct
;   delay primitive.
; ----------------------------------------------------------------------------

; ----------------------------------------------------------------------------
; Glossary of acronyms used in this file (alphabetical)
;
;   ALG       Algorithm (FM connection between two operators: additive
;             vs. modulator->carrier)
;   AM        Amplitude Modulation depth (tremolo)
;   AR        Attack Rate (operator envelope)
;   CC        MIDI Continuous Controller (e.g. CC#7 = main volume)
;   CSM       Composite Sine Mode (an OPL feature this driver doesn't
;             use; reg 0x08 bit 7)
;   DAC       Digital-to-Analog Converter. The SB Pro has a separate
;             8-bit DAC for sample playback; this driver does NOT touch
;             it -- a different DUDE driver (.DAC family) handles that.
;   DR        Decay Rate (operator envelope)
;   DUDE      Dynamix's Universal Driver-Engine -- a small per-card
;             sound-driver container format. Each driver exposes a
;             fixed 18-slot dispatch ABI behind a single FAR entry
;             point; see the dispatch-ABI section above. "DUDE format" is the
;             on-disk shape (header + slot table + handlers); "DUDE
;             dispatch" is the ABI by which the game calls into them.
;   EG-type   Envelope-type bit: 0 = percussive, 1 = sustained
;   far       A 32-bit `segment:offset` pointer (vs. "near" = 16-bit
;             offset only). The game calls the trampoline with `CALL
;             FAR`; everything inside this file is "near".
;   FB        Feedback (per-voice modulator self-feedback amount)
;   F-num     F-number, the 10-bit OPL pitch encoding
;   FM        Frequency Modulation (the dominant OPL synthesis mode)
;   KEY-ON    Bit 5 of reg 0xB0+v; begins / sustains a note
;   KSL       Key-Scale Level (per-operator attenuation that increases
;             with note pitch -- imitates acoustic instruments getting
;             quieter at higher pitches)
;   KSR       Key-Scale Rate (per-operator envelope speed-up with pitch)
;   LRU       Least Recently Used (the voice-allocation policy)
;   Mixer     The SB Pro's CT1335/CT1345 mixer chip at ports
;             0x224/0x225, separate from the OPL2 chip(s). Its registers
;             control input/output volumes (DAC, FM, line, mic, master,
;             ...) and a handful of stereo / filter switches. This
;             driver writes only reg 0x26 (FM volume); see
;             sbp_mixer_write. Distinct from the *Sound Blaster mixer*
;             concept of "summing two audio sources" -- this is the
;             on-board volume / routing chip.
;   MULT      Frequency multiplier (per-operator integer ratio of op
;             frequency to voice F-number)
;   near      A 16-bit offset-only pointer; the dispatch trampoline and
;             every handler in this file is a `PROC NEAR`.
;   OPL2      Yamaha YM3812 FM synthesizer chip. The SB Pro v1 has
;             *two* of these wired side-by-side (one per stereo
;             channel) at non-overlapping I/O ports, which is what
;             makes the card "stereo OPL2" rather than OPL3. The two
;             banks share their bus interface with the AdLib at 0x388
;             so a SB-Pro-aware driver can transparently fall back to
;             AdLib semantics by writing only the 0x388 pair.
;   RR        Release Rate (operator envelope)
;   SB Pro    Sound Blaster Pro (Creative Labs, 1991). The "Pro" model
;             adds stereo OPL (two OPL2 chips), an 8-bit stereo DAC, a
;             mixer chip, and an extended I/O port layout to the
;             original Sound Blaster.
;   SL        Sustain Level (operator envelope)
;   SOA       Struct-Of-Arrays (storage layout where each "field" is
;             its own array indexed by the same index)
;   SysEx     System-Exclusive MIDI message (not used by this driver)
;   TL        Total Level (per-operator attenuation: 0 = loud,
;             0x3F = silent)
;   VIB       Vibrato depth
;   volcurve  One of the two hand-rolled tables (`sbp_volcurve_a`,
;             `sbp_volcurve_b`) that translates a 6-bit linear loudness
;             index into a 6-bit OPL TL attenuation. The two curves
;             differ in slope and are applied at different points of
;             the velocity/volume pipeline.
; ----------------------------------------------------------------------------

                .8086
                .MODEL  TINY
                .CODE
                ORG     0

; ============================================================================
; 0x0000  --  DUDE header
;
;   Every DUDE driver starts with a 3-byte JMP into its dispatch trampoline
;   followed by a fixed-shape header the game's loader reads to identify
;   the driver: a 4-byte magic word, a 2-byte interface version, a 4-byte
;   'dude' tag, a length-prefixed device-name string, a second magic word,
;   the driver-kind ID, and the version string. The loader matches its
;   internal slot conventions against the iface version and refuses
;   incompatible drivers.
; ============================================================================
_start                   LABEL   BYTE
                         JMP     sbp_dispatch

pad_03                   DB      00H                  ; alignment pad
dude_magic_a             DD      87654321H            ; first DUDE magic word
dude_iface_ver           DB      01H, 04H             ; iface version 1.4
dude_tag                 DB      'dude'               ; 4-byte ASCII tag
device_name_len          DB      11H                  ; device name length (17)
device_name              DB      'Sound Blaster Pro'  ; human-readable device id
dude_magic_b             DD      0FEDCBA98H           ; second DUDE magic word
dude_driver_kind         DD      00000100H            ; driver-kind = SB Pro / OPL
driver_ver_str           DB      '2.24'               ; driver semver string

; ============================================================================
; 0x0031  --  OPL2 / mixer I/O port constants
;
;   The standard AdLib-compatible OPL2 port pair lives at 0x388/0x389.
;   Writing the index port selects an internal OPL register; writing the
;   data port sets its value. The chip is write-only -- the only useful
;   read is on the status port (which shares 0x388) used as a portable
;   busy-wait clock.
;
;   sbp_port_mixer_table is the SB Pro-specific port-routing catalogue.
;   The SB Pro v1 exposes the OPL2 chip pair *twice* -- as a "left" bank
;   at 0x220/0x222 and a "right" bank at 0x222/0x224 -- and the on-board
;   mixer chip at 0x224/0x225. This table puts every per-side port in
;   a single 16-byte block so each of the stereo writers below
;   (sbp_opl_write_op_level_l, sbp_opl_write_op_level_r, sbp_mixer_write)
;   reads its base via a fixed offset into the same table:
;
;       offset  meaning                  value
;       +0      left index               0x220
;       +2      left status              0x221  (delay-loop port)
;       +4      left data                0x222
;       +6      right index              0x222
;       +8      right status             0x223
;       +10     right data               0x224
;       +12     mixer index              0x224
;       +14     mixer data               0x225
; ============================================================================
sbp_port_reg             DW      0388H                ; OPL index port (write)
sbp_port_status          DW      0388H                ; OPL status port (read,
                                                      ; used only for timing)
sbp_port_data            DW      0389H                ; OPL data port (write)
sbp_port_mixer_table     DW      0220H, 0220H, 0221H, 0222H, 0222H, 0223H, 0224H, 0225H

; ============================================================================
; 0x0049  --  OPL2 F-number table, 48 entries (each entry is one WORD)
;
;   The OPL's pitch input is a 10-bit "F-number" plus a 3-bit "block"
;   (octave). The table below gives one F-number per *note within an
;   octave* -- but the driver indexes it with `(midi_note * 4) mod 48`,
;   not `midi_note mod 12`, giving 4 F-numbers per semitone. The extra
;   resolution is used by sbp_voice_pitchbend_apply to slide smoothly
;   between semitones when the channel's pitch wheel is anywhere other
;   than centered.
;
;   The block (octave) is computed as `(midi_note * 4) / 48` and OR'd
;   into the high bits of OPL reg 0xB0+v. See sbp_voice_render_freq.
;
;   Range: 0x0157 (note 0 mod 48) .. 0x02A4 (note 47 mod 48).
; ============================================================================
sbp_note_fnum_table      DW      0157H, 015CH, 0161H, 0166H, 016BH, 0171H, 0176H, 017BH
                         DW      0181H, 0186H, 018CH, 0192H, 0198H, 019EH, 01A4H, 01AAH
                         DW      01B0H, 01B6H, 01BDH, 01C3H, 01CAH, 01D0H, 01D7H, 01DEH
                         DW      01E5H, 01ECH, 01F3H, 01FAH, 0202H, 0209H, 0211H, 0218H
                         DW      0220H, 0228H, 0230H, 0238H, 0241H, 0249H, 0252H, 025AH
                         DW      0263H, 026CH, 0275H, 027EH, 0287H, 0290H, 029AH, 02A4H

; ============================================================================
; 0x00A9  --  volume curve A: 64-byte ascending TL ramp (0x00 .. 0x3F)
;
;   Maps a 6-bit linear "loudness index" to an OPL "total level"
;   attenuation. The curve is hand-rolled so the human-perceived
;   loudness is roughly linear in the index. Bytes 0..63 are sorted
;   ascending: index 0 -> TL 0 (loudest), index 63 -> TL 0x3F (silent).
;
;   Read in sbp_voice_render_freq as `volcurve_a[voice_velocity]` to
;   scale velocity into TL units before combining with channel volume.
; ============================================================================
sbp_volcurve_a           DB      00H, 0CH, 0DH, 0EH, 0FH, 11H, 12H, 13H, 14H, 16H, 17H, 18H
                         DB      1AH, 1BH, 1CH, 1DH, 1FH, 20H, 21H, 22H, 23H, 24H, 25H, 26H
                         DB      27H, 28H, 29H, 2AH, 2BH, 2DH, 2DH, 2EH, 2FH, 30H, 31H, 32H
                         DB      32H, 33H, 34H, 34H, 35H, 36H, 36H, 37H, 38H, 38H, 39H, 3AH
                         DB      3BH, 3BH, 3BH, 3CH, 3CH, 3CH, 3DH, 3DH, 3DH, 3EH, 3EH, 3EH
                         DB      3EH, 3FH, 3FH, 3FH

; ============================================================================
; 0x00E9  --  volume curve B: 64-byte velocity-to-TL lookup
;
;   Similar shape to curve A but with a steeper early slope. Used by the
;   stereo renderer (sbp_voice_render_volume) for two distinct passes:
;     1. `volcurve_b[pan/2]` -- to derive a left/right pan weight.
;     2. `volcurve_b[final_vol]` -- to convert the panned volume into a
;        TL attenuation when writing OPL reg 0x40+op via the L/R writers.
; ============================================================================
sbp_volcurve_b           DB      00H, 14H, 15H, 16H, 17H, 18H, 19H, 1AH, 1BH, 1CH, 1DH, 1EH
                         DB      1FH, 20H, 21H, 21H, 22H, 23H, 24H, 25H, 26H, 27H, 28H, 29H
                         DB      2AH, 2BH, 2CH, 2DH, 2EH, 2FH, 2FH, 30H, 31H, 32H, 32H, 33H
                         DB      34H, 34H, 35H, 36H, 36H, 37H, 38H, 38H, 39H, 39H, 3AH, 3AH
                         DB      3BH, 3BH, 3BH, 3CH, 3CH, 3CH, 3DH, 3DH, 3DH, 3EH, 3EH, 3EH
                         DB      3EH, 3FH, 3FH, 3FH

; ============================================================================
; 0x0129  --  global driver state (three scalar bytes)
;
;   sbp_global_param_11d -- semantics unconfirmed. Slot 11 stores into it
;     and slot 17 (query) reads it; no other code path touches it. May
;     be tempo, transpose, or another driver-wide knob.
;   sbp_master_enable -- 0 = driver muted, 1 = active. Read in
;     sbp_voice_keyon as a gate. Cleared/set by slot 13.
;   sbp_master_volume -- master volume 0..0x0F (4 bits), applied via the
;     SB Pro mixer's FM-volume register (reg 0x26) rather than per-op TL.
;     Default 0x0F = max.
; ============================================================================
sbp_global_param_11d     DB      00H                  ; (semantics unconfirmed)
sbp_master_enable        DB      01H                  ; 0 = muted, 1 = active
sbp_master_volume        DB      0FH                  ; master volume, 0..0x0F

; ============================================================================
; 0x012C..0x017B  --  per-MIDI-channel state, 16 channels x 5 arrays
;
;   Five parallel 16-byte arrays indexed by MIDI channel (0..15):
;
;     sbp_ch_program       -- currently-selected patch number (PC msg)
;     sbp_ch_volume        -- channel volume (CC#7), stored as CL>>1
;                             so 0..7F (7-bit MIDI) -> 0..3F (6-bit OPL
;                             TL space). Default 0x3F = max.
;     sbp_ch_pan           -- pan (CC#10), 0..7F. UNLIKE the ADL driver
;                             this one actually uses pan -- the SB Pro
;                             is stereo, and sbp_voice_render_volume
;                             splits each per-operator TL write into
;                             L/R halves weighted by pan. Default 0x40 =
;                             center.
;     sbp_ch_sustain_pedal -- sustain pedal (CC#64). When non-zero in
;                             sbp_midi_note_off, the note-off is deferred
;                             by setting sbp_voice_sustain_held.
;     sbp_ch_sustain_count -- per-channel "owed sustain reservations"
;                             used by the sustain-pool subsystem (see
;                             sbp_sustain_pool_*).
;
;   Parallel per-channel arrays (SOA), not one struct-of-channels.
; ============================================================================
sbp_ch_program           DB      16 DUP(00H)          ; channel -> patch number
sbp_ch_volume            DB      16 DUP(3FH)          ; channel -> volume (CC7/2)
sbp_ch_pan               DB      16 DUP(40H)          ; channel -> pan (CC10)
sbp_ch_sustain_pedal     DB      16 DUP(00H)          ; channel -> sustain pedal
sbp_ch_sustain_count     DB      16 DUP(00H)          ; channel -> sustain debt

; ============================================================================
; 0x017C  --  per-channel pitch-bend (16 words)
;
;   Each entry is a 14-bit MIDI pitch-bend value packed into 16 bits,
;   centered at 0x2000. The renderer (sbp_voice_pitchbend_apply) shifts
;   it down to an F-number delta to add to (or subtract from) the base
;   pitch.
; ============================================================================
sbp_ch_pitchbend         DW      16 DUP(2000H)        ; channel -> bend (default
                                                      ; 0x2000 = centered)

; ============================================================================
; 0x019C..0x01D2  --  per-voice state (5 parallel 11-byte SOA arrays)
;
;   Five parallel 11-byte arrays indexed by OPL2 voice. The chip has 9
;   voices (0..8); the trailing 2 slots are unused padding (see ADL's
;   equivalent: same 9+2 layout, kept for cross-driver compatibility).
;
;     sbp_voice_channel       -- which MIDI channel owns this voice
;                                (0xFF = voice is idle/free)
;     sbp_voice_note          -- currently-playing MIDI note number
;                                (0xFF = voice has no live note)
;     sbp_voice_velocity      -- the note's velocity (pre-halved to 0..63)
;     sbp_voice_sustain_held  -- 1 = "got a note-off but sustain pedal is
;                                held; release me when the pedal lifts"
;     sbp_voice_program       -- which patch is currently loaded in this
;                                voice's two OPL operators (0xFF = none).
;                                Lets sbp_voice_keyon skip the reload
;                                step when the new note happens to want
;                                the same patch.
; ============================================================================
sbp_voice_channel        DB      11 DUP(0FFH)         ; voice -> MIDI channel
                                                      ; (FF = idle)
sbp_voice_note           DB      11 DUP(0FFH)         ; voice -> MIDI note
                                                      ; (FF = idle)
sbp_voice_velocity       DB      11 DUP(00H)          ; voice -> velocity (0..63)
sbp_voice_sustain_held   DB      11 DUP(00H)          ; voice -> release-deferred
sbp_voice_program        DB      11 DUP(0FFH)         ; voice -> loaded patch #
                                                      ; (FF = none)

; ============================================================================
; 0x01D3..0x01E8  --  voice-allocator scratch (two 11-byte arrays)
;
;   sbp_voice_lru        -- a 9-slot Least-Recently-Used queue plus 2
;                           extra slots of padding. Head (slot 0) is the
;                           oldest voice, tail (slot 8) is the youngest.
;                           Used by sbp_voice_allocate to pick a victim;
;                           bumped to youngest by sbp_voice_lru_remove
;                           after every key-on/release.
;
;                           Initial 00..0A means voice 0 is oldest, voice
;                           8 is youngest; adapts immediately at runtime.
;
;   sbp_voice_sustain_ch -- voice -> "which MIDI channel reserved this
;                           voice through CC#75 polyphony budgeting".
;                           0xFF = not reserved. Driven by
;                           sbp_sustain_pool_resize / _reserve / _release.
; ============================================================================
sbp_voice_lru            DB      00H, 01H, 02H, 03H, 04H, 05H, 06H, 07H, 08H, 09H, 0AH
sbp_voice_sustain_ch     DB      11 DUP(0FFH)         ; voice -> reservation owner

; ============================================================================
; 0x01E9..0x0202  --  per-channel polyphony budget + 1-byte pad
;
;   sbp_ch_poly_max    -- per-channel maximum simultaneous notes. A
;                         channel may not own more voices than this.
;                         Adjusted indirectly via the sustain-pool
;                         routines when CC#75 is received.
;   sbp_ch_poly_active -- per-channel "voices currently sounding". An
;                         even-newer note-on triggers voice-stealing
;                         when this would exceed poly_max.
;                         The trailing 17th byte (index 16) is used by
;                         sbp_opl_write_op_level_l/_r as a *stereo-routing
;                         flag*: non-zero enables the OPL3 L/R-bit OR
;                         applied to writes of regs 0xC0..0xC8. The flag
;                         shares this region (logically it is unrelated
;                         to polyphony).
; ============================================================================
sbp_ch_poly_max          DB      16 DUP(00H)          ; channel -> max polyphony
sbp_ch_poly_active       DB      17 DUP(00H)          ; channel -> active voices
                                                      ; (+ 17th = stereo flag)

; ============================================================================
; 0x0203..0x0256  --  OPL2 operator-topology lookup tables (five 18-byte
;                     tables)
;
;   The OPL2's 18 operators are not addressed by a flat 0..17 index;
;   different register groups use slightly different offsets. These five
;   tables flatten that addressing irregularity into "look it up" form,
;   indexed by a linear operator number 0..17:
;
;     sbp_op_perm        -- a permutation of 0..17. Read by the volume
;                           renderer to walk operators in the order the
;                           OPL prefers (modulators first within each
;                           voice).
;     sbp_op_iscarrier   -- 0 if this op is the modulator of its pair,
;                           1 if it is the carrier.
;     sbp_op_regoff      -- maps linear op index to its OPL register
;                           offset (added to 0x20, 0x40, 0x60, 0x80,
;                           0xE0 register-group bases). Note the jumps
;                           of 3 (00,01,02, 08,09,0A, 10,11,12, ...):
;                           the chip's per-op registers leave 3-byte
;                           gaps between each group of three.
;     sbp_op_voice       -- maps linear op index to its owning voice
;                           0..8. Used by sbp_opl_write_voice_feedback
;                           to find which 0xC0+v register to write.
;     sbp_voice_oppair   -- pairs of (mod_op, car_op) for each of the 9
;                           voices, packed flat: 9 * 2 = 18 entries.
;                           Used by sbp_voice_apply_patch to address
;                           both operators of a voice when loading a
;                           patch.
; ============================================================================
sbp_op_perm              DB      03H, 04H, 05H, 09H, 0AH, 0BH, 0FH, 10H, 11H, 00H, 01H, 02H
                         DB      06H, 07H, 08H, 0CH, 0DH, 0EH
sbp_op_iscarrier         DB      00H, 00H, 00H, 01H, 01H, 01H, 00H, 00H, 00H, 01H, 01H, 01H
                         DB      00H, 00H, 00H, 01H, 01H, 01H
sbp_op_regoff            DB      00H, 01H, 02H, 03H, 04H, 05H, 08H, 09H, 0AH, 0BH, 0CH, 0DH
                         DB      10H, 11H, 12H, 13H, 14H, 15H
sbp_op_voice             DB      00H, 01H, 02H, 00H, 01H, 02H, 03H, 04H, 05H, 03H, 04H, 05H
                         DB      06H, 07H, 08H, 06H, 07H, 08H
sbp_voice_oppair         DB      00H, 03H, 01H, 04H, 02H, 05H, 06H, 09H, 07H, 0AH, 08H, 0BH
                         DB      0CH, 0FH, 0DH, 10H, 0EH, 11H

; ============================================================================
; 0x0257 / 0x0265  --  default operator patches (14 bytes each)
;
;   Used by sbp_opl_init_all_ops (via sbp_op_patch_stage_load) to put
;   every operator in a known sensible state after a chip reset. The
;   14-byte layout is what sbp_op_patch_load expects: each field is one
;   of the OPL register bits the chip cares about (KSL, MULT, FB/ALG,
;   AR, SL, EG-type, DR, RR, TL, AM, VIB, KSR, stereo, waveform -- in
;   that fixed order).
;
;   The "mod" patch has TL = 0x0F (byte 8) so the modulator sits at a
;   moderate level; the "car" patch has TL = 0 so the carrier sits at
;   full output. Standard OPL convention: the carrier is the audible
;   output, the modulator's job is to bend the carrier's frequency.
; ============================================================================
sbp_default_patch_mod    DB      01H, 01H, 03H, 0FH, 05H, 00H, 01H, 03H, 0FH, 00H, 00H, 00H
                         DB      01H, 00H
sbp_default_patch_car    DB      00H, 01H, 01H, 0FH, 07H, 00H, 02H, 04H, 00H, 00H, 00H, 01H
                         DB      00H, 00H

; ============================================================================
; 0x0273..0x036E  --  OPL register shadow (252 bytes)
;
;   18 operators * 14 bytes/op. Each 14-byte slot holds the most recent
;   value written for that operator's patch fields, so helpers like
;   sbp_opl_write_op_level can re-derive the OPL register byte by
;   reading the shadow rather than the chip (which is write-only).
;   Initialised to zero; populated by sbp_op_patch_load.
; ============================================================================
sbp_op_shadow            DB      252 DUP(00H)

; ============================================================================
; 0x036F  --  bank-size constant
;
;   The four bytes here are 0x00, 0xB8, 0x07, 0x15. The 0xB8 at offset
;   0x370 is the opcode of `MOV AX, imm16` and the WORD at 0x371..0x372
;   is its immediate operand; nothing branches to the MOV, so the WORD
;   serves purely as the bank-size constant. sbp_load_patch_bank reads it
;   as `CS:[sbp_bank_size]` to learn how many bytes to copy from the
;   patch-bank source.
; ============================================================================
pad_375                  DB      00H, 0B8H            ; pad + MOV AX opcode
sbp_bank_size            DW      1507H                ; 5383 = max bank payload

; ============================================================================
; 0x0373..0x183A  --  patch bank buffer (5320 bytes)
;
;   Filled at runtime by slot 1 (sbp_load_patch_bank). Holds an array of
;   28-byte SbpPatch records keyed by program number. The game uploads
;   the bank exactly once per song, before the first note plays. On
;   disk every byte is 0.
; ============================================================================
sbp_bank_buf             DB      5320 DUP(00H)

; ============================================================================
; 0x183B  --  velocity-clamp LUT (62 bytes, all 0x3C)
;
;   Read by sbp_voice_render_freq as `lut[clamp(note, 0x1B, 0x58) - 0x1B]`
;   to remap drum-channel notes into a smaller range before the volume
;   math. Every byte is 0x3C -- the LUT is effectively a no-op constant.
;   It exists as a per-driver tunable.
; ============================================================================
sbp_vel_to_tl_lut        DB      62 DUP(3CH)

; ============================================================================
; 0x1879  --  patch staging buffer (13 bytes)
;
;   Scratch area used by sbp_op_patch_stage_load to copy a default patch
;   from CS into a known location before forwarding the CS-relative
;   pointer to sbp_op_patch_load. Not state -- it's a temporary holding
;   buffer that gets overwritten on every patch-load call.
; ============================================================================
sbp_patch_stage          DB      13 DUP(00H)

pad_188c                 DB      00H                  ; alignment pad

; ============================================================================
; 0x1887..0x188D  --  OPL chip-state mirrors (3 scalars + 2 words)
;
;   The OPL2 has a handful of "global" registers that don't fit the
;   per-op layout. The driver mirrors them in RAM so sbp_op_apply_all_regs
;   can re-push them whenever a patch is reloaded.
;
;     sbp_opl_notesel    -- reg 0x08 bit 6 (NOTE-SEL: shifts the
;                           key-scaling boundary between MIDI notes).
;     sbp_opl_amdepth    -- reg 0xBD bit 7 (AM depth: deep/shallow).
;     sbp_opl_vibdepth   -- reg 0xBD bit 6 (VIB depth). Stored as a
;                           16-bit value but only the low byte is
;                           meaningful.
;     sbp_opl_rhythm     -- reg 0xBD bits 5..0 (rhythm-mode key-ons).
;                           Unused at runtime but composed by
;                           sbp_opl_write_rhythm.
;     sbp_wave_select_en -- reg 0x01 bit 5 (enables the waveform-select
;                           register group at 0xE0..0xF5). Set to
;                           0x0020 by sbp_silence_and_reset; without
;                           this bit the chip ignores all 0xE0 writes
;                           and plays only sine waves.
; ============================================================================
sbp_opl_notesel          DB      00H                  ; reg 0x08 bit 6 mirror
sbp_opl_amdepth          DB      00H                  ; reg 0xBD bit 7 mirror
sbp_opl_vibdepth         DW      0000H                ; reg 0xBD bit 6 mirror (word)
sbp_opl_rhythm           DB      00H                  ; reg 0xBD bits 5..0 mirror
sbp_wave_select_en       DW      0000H                ; reg 0x01 bit 5 mirror;
                                                      ; set to 0x20 by reset
pad_1894                 DB      3 DUP(00H)           ; alignment pad

; ============================================================================
; 0x1891..0x191D  --  per-voice OPL working tables (seven 11-entry arrays)
;
;   Seven parallel arrays indexed by voice (0..8), padded to 11 slots.
;   Six are 16-bit (WORD) and one is 8-bit (BYTE). They cache pre-
;   computed values derived from the currently-loaded patch, so the
;   per-note render path doesn't have to redo divisions every key-on.
;
;     sbp_voice_mod_tl_base -- modulator TL "base" (patch byte at
;                              offset 0xD of the SbpPatch record)
;     sbp_voice_mod_tl_max  -- 0x3F minus the modulator KSL byte
;     sbp_voice_mod_tl_step -- (mod_tl_max / 15), the per-step delta
;     sbp_voice_car_tl_base -- carrier TL base (patch byte at offset 0)
;     sbp_voice_car_tl_max  -- 0x3F minus the carrier KSL byte
;     sbp_voice_additive    -- 0 = modulator-only audible; 1 = both ops
;                              audible (additive synthesis)
;     sbp_voice_car_tl_step -- (car_tl_max / 15)
;
;   The "step" tables let the renderer scale velocity into the TL range
;   with multiplication only (no division at render time):
;     TL = base + velocity_index * step
; ============================================================================
sbp_voice_mod_tl_base    DW      11 DUP(0000H)        ; voice -> mod TL base
sbp_voice_mod_tl_max     DW      11 DUP(0000H)        ; voice -> 0x3F - mod KSL
sbp_voice_mod_tl_step    DW      11 DUP(0000H)        ; voice -> mod step / 15
sbp_voice_car_tl_base    DW      11 DUP(0000H)        ; voice -> car TL base
sbp_voice_car_tl_max     DW      11 DUP(0000H)        ; voice -> 0x3F - car KSL
sbp_voice_additive       DB      11 DUP(00H)          ; voice -> additive flag
sbp_voice_car_tl_step    DW      11 DUP(0000H)        ; voice -> car step / 15

; ============================================================================
; 0x191E  --  dispatch function-pointer table (18 near pointers)
;
;   The dispatch trampoline below indexes this table by `BP * 2`. Each
;   entry is a 16-bit near pointer to a slot handler. Six slots (3, 6,
;   9, 14, 15, 16) point at sbp_slot_unused_ret -- a one-byte RET stub
;   -- because the DUDE family reserves those slot indices but this
;   driver doesn't implement them.
;
;   The labels in the DW directives are forward references; TASM
;   resolves them on its second pass once the function bodies have
;   been laid out below.
; ============================================================================
sbp_func_table           LABEL   WORD
                DW      sbp_get_info                    ; slot  0
                DW      sbp_load_patch_bank             ; slot  1
                DW      sbp_reset_voices                ; slot  2
                DW      sbp_slot_unused_ret             ; slot  3
                DW      sbp_midi_note_off               ; slot  4
                DW      sbp_midi_note                   ; slot  5
                DW      sbp_slot_unused_ret             ; slot  6
                DW      sbp_midi_control_change         ; slot  7
                DW      sbp_midi_program_change         ; slot  8
                DW      sbp_slot_unused_ret             ; slot  9
                DW      sbp_midi_pitch_bend             ; slot 10
                DW      sbp_set_global_param_11d        ; slot 11
                DW      sbp_set_master_volume           ; slot 12
                DW      sbp_set_master_enable           ; slot 13
                DW      sbp_slot_unused_ret             ; slot 14
                DW      sbp_slot_unused_ret             ; slot 15
                DW      sbp_slot_unused_ret             ; slot 16
                DW      sbp_query_state                 ; slot 17

; ============================================================================
; 0x194A  --  sbp_dispatch  --  the trampoline
;
;   The ONLY entry point the game ever calls. The game does:
;
;       MOV  BP, <slot index>
;       <set up AL/CH/CL/etc per the slot's convention>
;       CALL FAR sbp_seg:sbp_dispatch
;
;   The trampoline saves BP, converts slot index to byte offset (shift
;   left 1), loads the slot's handler pointer from sbp_func_table,
;   near-calls it, restores BP, and returns far to the game.
;
;   Type:        Trampoline (the dispatch ABI entry point)
;   Dispatch:    Slot N/A -- this is the trampoline ITSELF, not a handler
;
;   Inputs:
;     BP      --  slot index (0..17)
;     AL/CH/CL/ES:AX  --  per-slot convention (see file preamble)
;
;   Outputs:    whatever the dispatched handler returns
;   Side effects:  none directly; whatever the handler does
; ============================================================================
sbp_dispatch    PROC    NEAR
                PUSH    BP                      ; save game's slot index
                SHL     BP, 1                   ; slot * 2 = byte offset
                MOV     BP, CS:[BP + sbp_func_table]
                CALL    BP                      ; near call to slot handler
                POP     BP                      ; restore for the game
                RETF                            ; far return to game
sbp_dispatch    ENDP

; ============================================================================
; 0x1956  --  sbp_slot_unused_ret
;
;   One-byte RET stub installed in every dispatch-table slot the driver
;   doesn't implement (slots 3, 6, 9, 14, 15, 16). Lets the game's
;   DUDE-aware caller invoke any slot index uniformly without checking
;   for missing handlers: this handler just returns immediately.
;
;   Type:        Slot handler (no-op)
;   Dispatch:    Slots 3, 6, 9, 14, 15, 16 (all reserved/unused)
;
;   Inputs:      ignored
;   Outputs:     none
; ============================================================================
sbp_slot_unused_ret PROC NEAR
                RET
sbp_slot_unused_ret ENDP

; ----------------------------------------------------------------------------
; 0x1957  --  sbp_midi_note_off  (slot 4)
;
;   Walks all 9 OPL voices looking for any voice playing this (channel,
;   note) pair. If the channel's sustain pedal is held, marks the voice
;   for deferred release; otherwise calls sbp_voice_release immediately.
;
;   Type:        Slot handler
;   Category:    MIDI dispatch
;   Dispatch:    Slot 4 (called as: BP=4, AL=channel, CH=note)
;   Callers:     Game (via dispatch), sbp_midi_note (vel=0 fallthrough)
;   Callees:     sbp_voice_release
;
;   Inputs:
;     AL  --  MIDI channel (0..15)
;     CH  --  MIDI note number (0..127)
;
;   Outputs:     none
; ----------------------------------------------------------------------------
sbp_midi_note_off PROC NEAR
                PUSH    BX
                PUSH    SI
                XOR     BX, BX
                JMP     SHORT noteoff_test
noteoff_body:   CMP     CS:[BX + sbp_voice_channel], AL
                JNE     SHORT noteoff_next
                CMP     CS:[BX + sbp_voice_note], CH
                JNE     SHORT noteoff_next
                MOV     SI, AX
                AND     SI, 00FFH
                CMP     BYTE PTR CS:[SI + sbp_ch_sustain_pedal], 0
                JE      SHORT noteoff_release
                MOV     BYTE PTR CS:[BX + sbp_voice_sustain_held], 1
                JMP     SHORT noteoff_next
noteoff_release: CALL   sbp_voice_release
noteoff_next:   INC     BX
noteoff_test:   CMP     BX, 9
                JB      SHORT noteoff_body
                POP     SI
                POP     BX
                RET
sbp_midi_note_off ENDP

; ----------------------------------------------------------------------------
; 0x198D  --  sbp_midi_note  (slot 5)
;
;   The MIDI "note on" message. CL=0 is note-off per MIDI's running-
;   status convention. Otherwise clamps the note to [0x0C, 0x6B], halves
;   the velocity (0..127 -> 0..63 for the 6-bit OPL TL range), and either
;   retriggers an already-playing voice or allocates a fresh one via
;   sbp_voice_allocate.
;
;   Type:        Slot handler
;   Category:    MIDI dispatch
;   Dispatch:    Slot 5 (called as: BP=5, AL=channel, CH=note, CL=velocity)
;   Callers:     Game (via dispatch)
;   Callees:     sbp_midi_note_off (vel=0 path), sbp_voice_release,
;                sbp_voice_keyon, sbp_voice_allocate
;
;   Inputs:
;     AL  --  MIDI channel (0..15)
;     CH  --  MIDI note number; silently dropped if outside [0x0C, 0x6B]
;     CL  --  velocity (0..127); 0 retriggers the note-off path
;
;   Outputs:     none
;
;   Side effects:
;     - May call sbp_voice_release + sbp_voice_keyon to retrigger an
;       already-playing (channel, note) pair.
;     - May allocate a new voice via sbp_voice_allocate (which can steal
;       a voice from an over-budget channel).
; ----------------------------------------------------------------------------
sbp_midi_note   PROC    NEAR
                PUSH    BX
                PUSH    SI
                OR      CL, CL
                JNZ     SHORT note_have_vel
                CALL    sbp_midi_note_off
                JMP     SHORT note_end
note_have_vel:  CMP     CH, 0CH
                JB      SHORT note_oor
                CMP     CH, 6BH
                JBE     SHORT note_in_range
note_oor:       JMP     SHORT note_end
note_in_range:  SHR     CL, 1
                XOR     BX, BX
                JMP     SHORT note_scan_test
note_scan_body: CMP     CS:[BX + sbp_voice_channel], AL
                JNE     SHORT note_scan_next
                CMP     CS:[BX + sbp_voice_note], CH
                JNE     SHORT note_scan_next
                CALL    sbp_voice_release
                CALL    sbp_voice_keyon
                JMP     SHORT note_end
note_scan_next: INC     BX
note_scan_test: CMP     BX, 9
                JB      SHORT note_scan_body
                CALL    sbp_voice_allocate
                CMP     BL, 0FFH
                JE      SHORT note_end
                CALL    sbp_voice_keyon
note_end:       POP     SI
                POP     BX
                RET
sbp_midi_note   ENDP

; ----------------------------------------------------------------------------
; 0x19D4  --  sbp_midi_control_change  (slot 7)
;
;   Dispatches MIDI controller-change messages by CC number:
;     CC#7   main volume          -> sbp_cc_main_volume
;     CC#10  pan                  -> sbp_cc_pan
;     CC#64  sustain pedal        -> sbp_cc_sustain_pedal
;     CC#75  polyphony budget     -> sbp_sustain_pool_resize
;     CC#123 all notes off        -> inline release loop
;   All other CC numbers are silently dropped.
;
;   Type:        Slot handler
;   Category:    MIDI dispatch
;   Dispatch:    Slot 7 (called as: BP=7, AL=channel, CH=CC#, CL=value)
;   Callers:     Game (via dispatch)
;   Callees:     sbp_cc_main_volume, sbp_cc_pan, sbp_cc_sustain_pedal,
;                sbp_sustain_pool_resize, sbp_voice_release
;
;   Inputs:
;     AL  --  MIDI channel (0..15)
;     CH  --  controller number (0..127)
;     CL  --  controller value (0..127)
;
;   Outputs:     none
; ----------------------------------------------------------------------------
sbp_midi_control_change PROC NEAR
                PUSH    BX
                CMP     CH, 07H
                JNE     SHORT cc_not_vol
                CALL    sbp_cc_main_volume
                JMP     SHORT cc_end
cc_not_vol:     CMP     CH, 0AH
                JNE     SHORT cc_not_pan
                CALL    sbp_cc_pan
                JMP     SHORT cc_end
cc_not_pan:     CMP     CH, 40H
                JNE     SHORT cc_not_sus
                CALL    sbp_cc_sustain_pedal
                JMP     SHORT cc_end
cc_not_sus:     CMP     CH, 4BH
                JNE     SHORT cc_not_pool
                CALL    sbp_sustain_pool_resize
                JMP     SHORT cc_end
cc_not_pool:    CMP     CH, 7BH
                JNE     SHORT cc_end
                XOR     BX, BX
                JMP     SHORT cc_scan_test
cc_scan_body:   CMP     CS:[BX + sbp_voice_channel], AL
                JNE     SHORT cc_scan_next
                CMP     BYTE PTR CS:[BX + sbp_voice_note], 0FFH
                JE      SHORT cc_scan_next
                CALL    sbp_voice_release
cc_scan_next:   INC     BX
cc_scan_test:   CMP     BX, 9
                JB      SHORT cc_scan_body
cc_end:         POP     BX
                RET
sbp_midi_control_change ENDP

; ----------------------------------------------------------------------------
; 0x1A20  --  sbp_midi_program_change  (slot 8)
;
;   MIDI "Program Change" message: tells the driver "from now on, channel
;   <ch> should play notes using instrument <prog>". The driver doesn't
;   reprogram any voice immediately; it just caches the new program
;   number. The next time a note is played on this channel,
;   sbp_voice_keyon will see the requested patch differs from the patch
;   currently loaded in the assigned voice and reload it from the bank
;   then.
;
;   Type:        Slot handler
;   Category:    MIDI dispatch
;   Dispatch:    Slot 8 (called as: BP=8, AL=channel, CL=patch#)
;   Callers:     Game (via dispatch)
;
;   Inputs:
;     AL  --  MIDI channel (0..15)
;     CL  --  patch / program number (0..127); semantics depend on the
;             currently-loaded bank
;
;   Outputs:     none
;
;   Side effects:
;     sbp_ch_program[channel] <- patch_number
;
;   Notes:
;     The lazy "cache, don't reload" approach matters because a song
;     typically issues program-change messages between notes rather
;     than during them; reprogramming an idle OPL voice would be wasted
;     work. The next note-on pays the reload cost only if the patch
;     actually differs.
; ----------------------------------------------------------------------------
sbp_midi_program_change PROC NEAR
                PUSH    SI
                MOV     SI, AX
                AND     SI, 00FFH
                MOV     CS:[SI + sbp_ch_program], CL
                POP     SI
                RET
sbp_midi_program_change ENDP

; ----------------------------------------------------------------------------
; 0x1A2E  --  sbp_midi_pitch_bend  (slot 10)
;
;   Repacks the BE-packed 14-bit MIDI pitch wheel into one LE word, stores
;   it at sbp_ch_pitchbend[ch], and refreshes every live voice on the
;   channel via sbp_voice_render_freq (with DX=1 to preserve KEY-ON).
;
;   Type:        Slot handler
;   Category:    MIDI dispatch
;   Dispatch:    Slot 10 (called as: BP=10, AL=channel, CH=msb, CL=lsb)
;   Callers:     Game (via dispatch)
;   Callees:     sbp_voice_render_freq
;
;   Inputs:
;     AL  --  MIDI channel (0..15)
;     CH  --  pitch-bend MSB (high 7 bits of 14-bit value)
;     CL  --  pitch-bend LSB (low 7 bits of 14-bit value)
;
;   Outputs:     none
;
;   Side effects:
;     sbp_ch_pitchbend[channel] <- repacked 14-bit value (center = 0x2000)
;     Each live voice on this channel has its OPL F-number rewritten.
; ----------------------------------------------------------------------------
sbp_midi_pitch_bend PROC NEAR
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
                MOV     CS:[BX + sbp_ch_pitchbend], CX
                XOR     BX, BX
                JMP     SHORT pb_scan_test
pb_scan_body:   CMP     CS:[BX + sbp_voice_channel], AL
                JNE     SHORT pb_scan_next
                CMP     BYTE PTR CS:[BX + sbp_voice_note], 0FFH
                JE      SHORT pb_scan_next
                MOV     CL, CS:[BX + sbp_voice_note]
                MOV     DX, 0001H
                CALL    sbp_voice_render_freq
pb_scan_next:   INC     BX
pb_scan_test:   CMP     BX, 9
                JB      SHORT pb_scan_body
                POP     DX
                POP     CX
                POP     BX
                RET
sbp_midi_pitch_bend ENDP

; ----------------------------------------------------------------------------
; 0x1A6D  --  sbp_set_master_enable  (slot 13)
;
;   Sets sbp_master_enable to a new value (or queries the current one
;   when CL=0xFF). On any state change, re-applies the master volume via
;   sbp_set_master_volume so the SB Pro mixer reg 0x26 write picks up
;   the new gate -- enabling the driver routes the cached
;   sbp_master_volume to the mixer; disabling routes 0.
;
;   Type:        Slot handler
;   Category:    Master control
;   Dispatch:    Slot 13 (called as: BP=13, CL=value or 0xFF=query)
;   Callers:     Game (via dispatch)
;   Callees:     sbp_set_master_volume
;
;   Inputs:
;     CL  --  new value (0 = mute, non-zero = active), or 0xFF to query
;
;   Outputs:
;     AX  --  previous master-enable value (high byte 0)
;
;   Side effects:
;     When CL != 0xFF: sbp_master_enable <- CL; mixer reg 0x26 updated.
; ----------------------------------------------------------------------------
sbp_set_master_enable PROC NEAR
                MOV     AL, CS:sbp_master_enable
                XOR     AH, AH
                CMP     CL, 0FFH
                JE      SHORT sme_end
                PUSH    CX
                PUSH    AX
                MOV     CS:sbp_master_enable, CL
                OR      CL, CL
                JZ      SHORT sme_skip_load
                MOV     CL, CS:sbp_master_volume
sme_skip_load:  CALL    sbp_set_master_volume
                MOV     CS:sbp_master_volume, AL
                POP     AX
                POP     CX
sme_end:        RET
sbp_set_master_enable ENDP

; ----------------------------------------------------------------------------
; 0x1A92  --  sbp_set_master_volume  (slot 12)
;
;   Sets the driver's master volume by writing the SB Pro mixer chip's
;   FM-volume register (0x26). The mixer expects a byte where the high
;   nibble is left-channel volume and the low nibble is right-channel
;   volume; the driver packs (vol << 4) | vol so both halves agree.
;
;   The trick: shift CL left by 4 (four `SHL CL, 1` instructions) then
;   `OR CL, [sbp_master_volume]` -- because we wrote the *new* value into
;   sbp_master_volume in step 1, this combines (new << 4) | new in one
;   byte ready for the mixer.
;
;   Type:        Slot handler
;   Category:    Master control (writes SB Pro mixer)
;   Dispatch:    Slot 12 (called as: BP=12, CL=value or 0xFF=query)
;   Callers:     Game (via dispatch), sbp_set_master_enable,
;                sbp_load_patch_bank
;   Callees:     sbp_mixer_write
;
;   Inputs:
;     CL  --  new volume (0..0x0F), or 0xFF to query
;
;   Outputs:
;     AL  --  previous master volume (high byte 0)
;
;   Side effects (when CL != 0xFF):
;     sbp_master_volume <- CL
;     SB Pro mixer reg 0x26 <- (CL << 4) | CL
; ----------------------------------------------------------------------------
sbp_set_master_volume PROC NEAR
                PUSH    BX
                PUSH    DX
                MOV     AL, CS:sbp_master_volume
                XOR     AH, AH
                CMP     CL, 0FFH
                JE      SHORT smv_end
                MOV     CS:sbp_master_volume, CL

                ; Pack (CL << 4) | CL by shifting then OR'ing with the
                ; just-stored mirror.
                PUSH    CX
                SHL     CL, 1
                SHL     CL, 1
                SHL     CL, 1
                SHL     CL, 1
                OR      CL, CS:sbp_master_volume
                MOV     BX, 0026H               ; mixer reg 0x26 (FM volume)
                CALL    sbp_mixer_write
                POP     CX
smv_end:        POP     DX
                POP     BX
                RET
sbp_set_master_volume ENDP

; ----------------------------------------------------------------------------
; 0x1ABC  --  sbp_set_global_param_11d  (slot 11)
;
;   Pure get/set on the scalar at sbp_global_param_11d. Domain semantics
;   are not confirmed (see data-section banner). When CL=0xFF the handler
;   queries (returns the current value); otherwise it stores CL.
;
;   Type:        Slot handler
;   Category:    Global state
;   Dispatch:    Slot 11 (called as: BP=11, CL=value or 0xFF=query)
;   Callers:     Game (via dispatch)
;
;   Inputs:
;     CL  --  new value, or 0xFF to query
;
;   Outputs:
;     AL  --  previous value (high byte 0)
;
;   Side effects:
;     When CL != 0xFF: sbp_global_param_11d <- CL.
; ----------------------------------------------------------------------------
sbp_set_global_param_11d PROC NEAR
                MOV     AL, CS:sbp_global_param_11d
                XOR     AH, AH
                CMP     CL, 0FFH
                JE      SHORT sgp_end
                MOV     CS:sbp_global_param_11d, CL
sgp_end:        RET
sbp_set_global_param_11d ENDP

; ----------------------------------------------------------------------------
; 0x1ACD  --  sbp_reset_voices  (slot 2)
;
;   Silence the chip via sbp_silence_and_reset, then prime the SB Pro
;   mixer's FM-volume register (0x26) with 0x99 (nibble 9 in both halves)
;   so the chip outputs audio at a moderate level after reset. Unlike
;   slot 12 (set_master_volume), this writes the mixer directly without
;   touching the cached sbp_master_volume.
;
;   Type:        Slot handler
;   Category:    Voice / chip reset
;   Dispatch:    Slot 2 (called as: BP=2; no other arguments)
;   Callers:     Game (via dispatch)
;   Callees:     sbp_silence_and_reset, sbp_mixer_write
;
;   Inputs:      none (BP=2 is the only thing the game sets)
;   Outputs:     none
;
;   Side effects:
;     - Every OPL register from 0x00..0xF5 reset to 0.
;     - Every operator reloaded with the default mod/car patch.
;     - SB Pro mixer reg 0x26 <- 0x99.
; ----------------------------------------------------------------------------
sbp_reset_voices PROC NEAR
                CALL    sbp_silence_and_reset
                PUSH    BX
                PUSH    CX
                OR      CL, 99H                 ; force both nibbles to 9
                MOV     BX, 0026H
                CALL    sbp_mixer_write
                POP     CX
                POP     BX
                RET
sbp_reset_voices ENDP

; ----------------------------------------------------------------------------
; 0x1ADE  --  sbp_voice_allocate
;
;   Picks an OPL voice for a new note. Two-phase search (the AdLib
;   driver's three-phase "idle voice with matching patch" phase has been
;   dropped):
;
;     Phase 1: walk voices in LRU order, pick any idle voice.
;     Phase 2: find the channel most over its polyphony budget and steal
;              one of its voices. If no channel is over budget, steal
;              from the caller's own channel.
;
;     If both phases fail, return 0xFFFF.
;
;   Type:        Subroutine
;   Category:    Voice management
;   Callers:     sbp_midi_note
;   Callees:     sbp_voice_release (in voice-steal path)
;
;   Inputs:
;     AL  --  MIDI channel asking for a voice
;
;   Outputs:
;     BX  --  chosen voice index 0..8, or 0xFFFF on failure
;
;   Side effects:
;     The chosen voice's sbp_voice_channel[v] is set to AL.
;     In the steal path: the prior occupant is released
;     (sbp_voice_release: note silenced, LRU bumped, owning channel's
;     poly_active decremented).
; ----------------------------------------------------------------------------
sbp_voice_allocate PROC NEAR
                PUSH    CX
                PUSH    DX
                PUSH    SI

                ; ---- Phase 1: any idle voice (LRU order) ----
                XOR     SI, SI
                XOR     BX, BX
                JMP     SHORT va_p1_test
va_p1_body:     MOV     BL, CS:[SI + sbp_voice_lru]
                CMP     BYTE PTR CS:[BX + sbp_voice_note], 0FFH
                JNE     SHORT va_p1_next
                MOV     CS:[BX + sbp_voice_channel], AL
                JMP     SHORT va_end
va_p1_next:     INC     SI
va_p1_test:     CMP     SI, 9
                JB      SHORT va_p1_body

                ; ---- Phase 2a: find worst (poly_active - poly_max) ----
                XOR     SI, SI
                XOR     BX, BX
                XOR     CX, CX
                XOR     DX, DX
                JMP     SHORT va_p2_test
va_p2_body:     MOV     CL, CS:[SI + sbp_ch_poly_active]
                CMP     CL, CS:[SI + sbp_ch_poly_max]
                JBE     SHORT va_p2_next
                SUB     CL, CS:[SI + sbp_ch_poly_max]
                CMP     BL, CL
                JAE     SHORT va_p2_next
                MOV     BL, CL
                MOV     DX, SI
va_p2_next:     INC     SI
va_p2_test:     CMP     SI, 10H
                JB      SHORT va_p2_body

                ; ---- Phase 2b: steal from worst_channel (or caller's) ----
                MOV     CL, AL
                CMP     BL, 0
                JBE     SHORT va_p2b_use_caller
                MOV     CL, DL
va_p2b_use_caller: XOR  SI, SI
                XOR     BX, BX
                JMP     SHORT va_p2b_test
va_p2b_body:    MOV     BL, CS:[SI + sbp_voice_lru]
                CMP     CS:[BX + sbp_voice_channel], CL
                JNE     SHORT va_p2b_next
                CALL    sbp_voice_release
                MOV     CS:[BX + sbp_voice_channel], AL
                JMP     SHORT va_end
va_p2b_next:    INC     SI
va_p2b_test:    CMP     SI, 9
                JB      SHORT va_p2b_body
                MOV     BX, 0FFFFH
va_end:         POP     SI
                POP     DX
                POP     CX
                RET
sbp_voice_allocate ENDP

; ----------------------------------------------------------------------------
; 0x1B5C  --  sbp_sustain_pool_resize
;
;   CC#75 handler. Counts voices currently held by the channel (sum of
;   sbp_voice_sustain_ch entries matching this channel, plus
;   sbp_ch_sustain_count), then grows or shrinks the pool to match CL by
;   calling reserve / release as needed. The pool tracks "polyphony
;   reservations" -- a per-channel commitment to keep some number of
;   voices owned by the channel even when nominally idle.
;
;   Type:        Subroutine (CC handler dispatched from
;                sbp_midi_control_change)
;   Category:    Sustain / polyphony pool
;   Callers:     sbp_midi_control_change (CC#75 branch)
;   Callees:     sbp_sustain_pool_reserve, sbp_sustain_pool_release,
;                sbp_sustain_pool_drain
;
;   Inputs:
;     AL  --  MIDI channel (0..15)
;     CL  --  requested pool size (new ch_sustain_count target)
;
;   Outputs:     none
;
;   Side effects:
;     sbp_ch_sustain_count[channel], sbp_voice_sustain_ch[],
;     sbp_ch_poly_max[] all adjusted to honour the new pool size.
; ----------------------------------------------------------------------------
sbp_sustain_pool_resize PROC NEAR
                PUSH    SI
                PUSH    CX
                PUSH    DX
                XOR     SI, SI
                XOR     DX, DX
                JMP     SHORT spr_count_test
spr_count_body: CMP     CS:[SI + sbp_voice_sustain_ch], AL
                JNE     SHORT spr_count_next
                INC     DL
spr_count_next: INC     SI
spr_count_test: CMP     SI, 9
                JB      SHORT spr_count_body
                MOV     SI, AX
                AND     SI, 00FFH
                ADD     DL, CS:[SI + sbp_ch_sustain_count]
                CMP     DL, CL
                JE      SHORT spr_end
                CMP     DL, CL
                JAE     SHORT spr_shrink
                SUB     CL, DL
                CALL    sbp_sustain_pool_reserve
                JMP     SHORT spr_end
spr_shrink:     SUB     DL, CL
                MOV     CL, DL
                CALL    sbp_sustain_pool_release
                CALL    sbp_sustain_pool_drain
spr_end:        POP     DX
                POP     CX
                POP     SI
                RET
sbp_sustain_pool_resize ENDP

; ----------------------------------------------------------------------------
; 0x1B9C  --  sbp_sustain_pool_drain
;
;   Cleanup pass after sbp_sustain_pool_release: counts how many voice
;   slots became unreserved (sbp_voice_sustain_ch == 0xFF) and walks the
;   16 MIDI channels, redistributing those freed slots to any channel
;   whose ch_sustain_count > 0 by calling sbp_sustain_pool_reserve. The
;   effect: shrinking one channel's pool returns the freed voices to
;   other channels with outstanding reservations.
;
;   Type:        Subroutine
;   Category:    Sustain / polyphony pool
;   Callers:     sbp_sustain_pool_resize
;   Callees:     sbp_sustain_pool_reserve
;
;   Inputs:      none (walks global state directly)
;   Outputs:     none
;
;   Side effects:
;     - Reassigns sbp_voice_sustain_ch[] slots to channels that need them.
;     - Decrements those channels' ch_sustain_count by the reserved
;       amount.
; ----------------------------------------------------------------------------
sbp_sustain_pool_drain PROC NEAR
                PUSH    AX
                PUSH    CX
                PUSH    SI
                XOR     CL, CL
                XOR     SI, SI
                JMP     SHORT spd_count_test
spd_count_body: CMP     BYTE PTR CS:[SI + sbp_voice_sustain_ch], 0FFH
                JNE     SHORT spd_count_next
                INC     CL
spd_count_next: INC     SI
spd_count_test: CMP     SI, 9
                JB      SHORT spd_count_body
                OR      CL, CL
                JZ      SHORT spd_end
                XOR     SI, SI
                JMP     SHORT spd_loop_test
spd_loop_body:  MOV     CH, CS:[SI + sbp_ch_sustain_count]
                CMP     CH, 0
                JBE     SHORT spd_next_ch
                CMP     CH, CL
                JAE     SHORT spd_partial
                SUB     CL, CH
                PUSH    CX
                MOV     CL, CH
                MOV     BYTE PTR CS:[SI + sbp_ch_sustain_count], 0
                MOV     AX, SI
                CALL    sbp_sustain_pool_reserve
                POP     CX
                JMP     SHORT spd_next_ch
spd_partial:    SUB     CH, CL
                MOV     CS:[SI + sbp_ch_sustain_count], CH
                MOV     AX, SI
                CALL    sbp_sustain_pool_reserve
                JMP     SHORT spd_end
spd_next_ch:    INC     SI
spd_loop_test:  CMP     SI, 10H
                JB      SHORT spd_loop_body
spd_end:        POP     SI
                POP     CX
                POP     AX
                RET
sbp_sustain_pool_drain ENDP

; ----------------------------------------------------------------------------
; 0x1BF6  --  sbp_sustain_pool_reserve
;
;   Reserves up to CL voices for channel AL. Walks all 9 voice slots; for
;   each currently unreserved slot (sbp_voice_sustain_ch == 0xFF) it
;   marks the slot as belonging to AL, releases any live note the slot
;   was holding, and bumps the channel's ch_poly_max budget. Any
;   surplus that can't be satisfied because all 9 slots are spoken for
;   is added to ch_sustain_count as "owed reservations".
;
;   Type:        Subroutine
;   Category:    Sustain / polyphony pool
;   Callers:     sbp_sustain_pool_resize, sbp_sustain_pool_drain
;   Callees:     sbp_voice_release
;
;   Inputs:
;     AL  --  MIDI channel requesting reservations
;     CL  --  number of voices to reserve
;
;   Outputs:     none
;
;   Side effects:
;     sbp_voice_sustain_ch[] entries set to AL.
;     sbp_ch_poly_max[AL] incremented per voice claimed.
;     sbp_ch_sustain_count[AL] absorbs any unsatisfied remainder.
; ----------------------------------------------------------------------------
sbp_sustain_pool_reserve PROC NEAR
                PUSH    CX
                PUSH    BX
                PUSH    SI
                XOR     BX, BX
                JMP     SHORT spres_loop_test
spres_loop_body: CMP    BYTE PTR CS:[BX + sbp_voice_sustain_ch], 0FFH
                JNE     SHORT spres_next_voice
                CMP     BYTE PTR CS:[BX + sbp_voice_note], 0FFH
                JE      SHORT spres_assign
                CALL    sbp_voice_release
spres_assign:   MOV     CS:[BX + sbp_voice_sustain_ch], AL
                XOR     AH, AH
                MOV     SI, AX
                INC     BYTE PTR CS:[SI + sbp_ch_poly_max]
                DEC     CL
spres_next_voice: INC   BX
spres_loop_test: CMP    BX, 9
                JAE     SHORT spres_done
                CMP     CL, 0
                JA      SHORT spres_loop_body
spres_done:     MOV     SI, AX
                AND     SI, 00FFH
                ADD     CS:[SI + sbp_ch_sustain_count], CL
                POP     SI
                POP     BX
                POP     CX
                RET
sbp_sustain_pool_reserve ENDP

; ----------------------------------------------------------------------------
; 0x1C3A  --  sbp_sustain_pool_release
;
;   Releases up to CL reservations for channel AL. First draws from
;   sbp_ch_sustain_count (the channel's "owed" reservations); any
;   remainder is released by walking voices in two phases:
;     phase 1: release reservations on slots that are NOT currently
;              playing (voice_note == 0xFF) -- the cheap case.
;     phase 2: if more must go, release reservations on slots that ARE
;              playing, calling sbp_voice_release on each before
;              clearing the reservation.
;
;   Type:        Subroutine
;   Category:    Sustain / polyphony pool
;   Callers:     sbp_sustain_pool_resize
;   Callees:     sbp_voice_release
;
;   Inputs:
;     AL  --  MIDI channel releasing reservations
;     CL  --  number to release
;
;   Outputs:     none
;
;   Side effects:
;     sbp_voice_sustain_ch[] entries cleared (set to 0xFF).
;     sbp_ch_poly_max[AL] decremented per voice released.
;     sbp_ch_sustain_count[AL] drained first, then the voice slots.
; ----------------------------------------------------------------------------
sbp_sustain_pool_release PROC NEAR
                PUSH    BX
                PUSH    CX
                PUSH    SI
                MOV     SI, AX
                AND     SI, 00FFH
                CMP     CS:[SI + sbp_ch_sustain_count], CL
                JB      SHORT sprl_partial
                SUB     CS:[SI + sbp_ch_sustain_count], CL
                JMP     SHORT sprl_end
sprl_partial:   SUB     CL, CS:[SI + sbp_ch_sustain_count]
                MOV     BYTE PTR CS:[SI + sbp_ch_sustain_count], 0
                XOR     BX, BX
                JMP     SHORT sprl_p1_test
sprl_p1_body:   CMP     CS:[BX + sbp_voice_sustain_ch], AL
                JNE     SHORT sprl_p1_next
                CMP     BYTE PTR CS:[BX + sbp_voice_note], 0FFH
                JNE     SHORT sprl_p1_next
                MOV     BYTE PTR CS:[BX + sbp_voice_sustain_ch], 0FFH
                XOR     AH, AH
                MOV     SI, AX
                DEC     BYTE PTR CS:[SI + sbp_ch_poly_max]
                DEC     CL
                JZ      SHORT sprl_end
sprl_p1_next:   INC     BX
sprl_p1_test:   CMP     BX, 9
                JB      SHORT sprl_p1_body
                XOR     BX, BX
                JMP     SHORT sprl_p2_test
sprl_p2_body:   CMP     CS:[BX + sbp_voice_sustain_ch], AL
                JNE     SHORT sprl_p2_next
                CALL    sbp_voice_release
                MOV     BYTE PTR CS:[BX + sbp_voice_sustain_ch], 0FFH
                XOR     AH, AH
                MOV     SI, AX
                DEC     BYTE PTR CS:[SI + sbp_ch_poly_max]
                DEC     CL
                JZ      SHORT sprl_end
sprl_p2_next:   INC     BX
sprl_p2_test:   CMP     BX, 9
                JB      SHORT sprl_p2_body
sprl_end:       POP     SI
                POP     CX
                POP     BX
                RET
sbp_sustain_pool_release ENDP

; ----------------------------------------------------------------------------
; 0x1CB3  --  sbp_cc_main_volume
;
;   MIDI CC#7 handler. Halves CL (0..127 -> 0..63), stores it in
;   sbp_ch_volume[ch], and refreshes live voices by calling
;   sbp_voice_render_freq with DX=1 for each voice on this channel.
;
;   Type:        Subroutine (CC handler)
;   Category:    MIDI dispatch -> render
;   Callers:     sbp_midi_control_change (CC#7 branch)
;   Callees:     sbp_voice_render_freq
;
;   Inputs:
;     AL  --  MIDI channel (0..15)
;     CL  --  volume value (0..127)
;
;   Outputs:     none
;
;   Side effects:
;     sbp_ch_volume[channel] <- CL/2
;     Every live voice on this channel has its OPL TL writes refreshed.
; ----------------------------------------------------------------------------
sbp_cc_main_volume PROC NEAR
                PUSH    BX
                PUSH    CX
                PUSH    DX
                PUSH    SI
                SHR     CL, 1
                MOV     SI, AX
                AND     SI, 00FFH
                MOV     CS:[SI + sbp_ch_volume], CL
                XOR     CX, CX
                MOV     DX, 0001H
                XOR     BX, BX
                JMP     SHORT ccv_test
ccv_body:       CMP     CS:[BX + sbp_voice_channel], AL
                JNE     SHORT ccv_next
                MOV     CL, CS:[BX + sbp_voice_note]
                CMP     CL, 0FFH
                JE      SHORT ccv_next
                CALL    sbp_voice_render_freq
ccv_next:       INC     BX
ccv_test:       CMP     BX, 9
                JB      SHORT ccv_body
                POP     SI
                POP     DX
                POP     CX
                POP     BX
                RET
sbp_cc_main_volume ENDP

; ----------------------------------------------------------------------------
; 0x1CEC  --  sbp_cc_pan
;
;   MIDI CC#10 handler. Stores raw pan (0..127) in sbp_ch_pan[ch] and
;   refreshes live voices. The SB Pro driver -- unlike the ADL one --
;   actually uses the value: sbp_voice_render_volume splits each TL
;   write into L/R halves weighted by pan, sending them through
;   different I/O port pairs (the left and right OPL banks).
;
;   Type:        Subroutine (CC handler)
;   Category:    MIDI dispatch -> render
;   Callers:     sbp_midi_control_change (CC#10 branch)
;   Callees:     sbp_voice_render_freq
;
;   Inputs:
;     AL  --  MIDI channel (0..15)
;     CL  --  pan value (0..127; 64 = center)
;
;   Outputs:     none
;
;   Side effects:
;     sbp_ch_pan[channel] <- CL
;     Every live voice on this channel has its L/R OPL TL pair rewritten.
; ----------------------------------------------------------------------------
sbp_cc_pan      PROC    NEAR
                PUSH    SI
                PUSH    BX
                MOV     SI, AX
                AND     SI, 00FFH
                MOV     CS:[SI + sbp_ch_pan], CL
                XOR     CX, CX
                MOV     DX, 0001H
                XOR     BX, BX
                JMP     SHORT ccp_test
ccp_body:       CMP     CS:[BX + sbp_voice_channel], AL
                JNE     SHORT ccp_next
                MOV     CL, CS:[BX + sbp_voice_note]
                CMP     CL, 0FFH
                JE      SHORT ccp_next
                CALL    sbp_voice_render_freq
ccp_next:       INC     BX
ccp_test:       CMP     BX, 9
                JB      SHORT ccp_body
                POP     BX
                POP     SI
                RET
sbp_cc_pan      ENDP

; ----------------------------------------------------------------------------
; 0x1D1F  --  sbp_cc_sustain_pedal
;
;   MIDI CC#64 handler. Stores the pedal state in sbp_ch_sustain_pedal[ch].
;   When the pedal goes from held to released (CL=0), releases every
;   voice on this channel whose voice_sustain_held flag is set (i.e.
;   notes that received a note-off while the pedal was down and were
;   parked pending release).
;
;   Type:        Subroutine (CC handler)
;   Category:    MIDI dispatch -> voice control
;   Callers:     sbp_midi_control_change (CC#64 branch)
;   Callees:     sbp_voice_release
;
;   Inputs:
;     AL  --  MIDI channel (0..15)
;     CL  --  pedal state (0 = released, non-zero = held)
;
;   Outputs:     none
;
;   Side effects:
;     sbp_ch_sustain_pedal[channel] <- CL
;     On pedal release: deferred notes flushed via sbp_voice_release.
; ----------------------------------------------------------------------------
sbp_cc_sustain_pedal PROC NEAR
                PUSH    BX
                PUSH    SI
                MOV     SI, AX
                AND     SI, 00FFH
                MOV     CS:[SI + sbp_ch_sustain_pedal], CL
                OR      CL, CL
                JNZ     SHORT ccsp_end
                XOR     BX, BX
                JMP     SHORT ccsp_test
ccsp_body:      CMP     CS:[BX + sbp_voice_channel], AL
                JNE     SHORT ccsp_next
                CMP     BYTE PTR CS:[BX + sbp_voice_sustain_held], 0
                JE      SHORT ccsp_next
                CALL    sbp_voice_release
ccsp_next:      INC     BX
ccsp_test:      CMP     BX, 9
                JB      SHORT ccsp_body
ccsp_end:       POP     SI
                POP     BX
                RET
sbp_cc_sustain_pedal ENDP

; ----------------------------------------------------------------------------
; 0x1D4F  --  sbp_voice_keyon
;
;   Starts a note on a chosen voice. Bumps poly_active, removes from
;   LRU, remaps drum-channel notes (channel 9), reloads the patch if the
;   program differs (and master_enable is on), then calls
;   sbp_voice_render_freq with DX=1 to set KEY-ON.
;
;   Type:        Subroutine
;   Category:    Voice management
;   Callers:     sbp_midi_note (both retrigger and fresh-allocate paths)
;   Callees:     sbp_voice_lru_remove, sbp_voice_apply_patch,
;                sbp_voice_render_freq
;
;   Inputs:
;     BX  --  voice index 0..8
;     CH  --  MIDI note number
;     CL  --  pre-halved velocity (0..63)
;
;   Outputs:     none
;
;   Side effects:
;     sbp_ch_poly_active[channel]++
;     sbp_voice_lru bumped (the voice moves to the youngest LRU slot)
;     On patch reload: sbp_voice_program[v] set; per-voice TL tables
;     repopulated; OPL operator registers rewritten.
;     OPL reg 0xA0+v and 0xB0+v written via sbp_voice_render_freq.
; ----------------------------------------------------------------------------
sbp_voice_keyon PROC    NEAR
                PUSH    CX
                PUSH    DX
                PUSH    DI
                PUSH    SI
                XOR     DH, DH
                MOV     DL, CS:[BX + sbp_voice_channel]
                MOV     SI, DX
                MOV     DL, CS:[SI + sbp_ch_program]
                INC     BYTE PTR CS:[SI + sbp_ch_poly_active]
                CALL    sbp_voice_lru_remove
                CMP     SI, 9
                JNE     SHORT vkon_not_drum

                ; Drum channel: clamp note to [0x1B, 0x58] + 0x65 for patch index.
                MOV     DL, CH
                CMP     DL, 1BH
                JAE     SHORT vkon_drum_hi
                MOV     DL, 1BH
                JMP     SHORT vkon_drum_done
vkon_drum_hi:   CMP     DL, 58H
                JBE     SHORT vkon_drum_done
                MOV     DL, 58H
vkon_drum_done: ADD     DL, 65H
vkon_not_drum:  CMP     DL, CS:[BX + sbp_voice_program]
                JE      SHORT vkon_no_reload
                CMP     BYTE PTR CS:sbp_master_enable, 0
                JE      SHORT vkon_no_reload

                ; Reload the patch. Patch offset in bank = program * 28.
                ; 28 = 4 + 8 + 16 (shift-add multiply, no IMUL).
                PUSH    CX
                MOV     CS:[BX + sbp_voice_program], DL
                PUSH    BX
                XOR     BH, BH
                MOV     BL, DL
                PUSH    CX
                PUSH    AX
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
                LEA     CX, [DI + sbp_bank_buf]
                CALL    sbp_voice_apply_patch
                POP     CX
vkon_no_reload: MOV     CS:[BX + sbp_voice_velocity], CL
                MOV     CL, CH
                MOV     DX, 0001H
                CALL    sbp_voice_render_freq
                POP     SI
                POP     DI
                POP     DX
                POP     CX
                RET
sbp_voice_keyon ENDP

; ----------------------------------------------------------------------------
; 0x1DCE  --  sbp_voice_release
;
;   Stops a voice cleanly: clears its sustain_held flag, calls
;   sbp_voice_render_freq with DX=0 (so KEY-ON is cleared in OPL reg
;   0xB0+v -- the chip's gate-off signal), marks voice_note=0xFF (idle),
;   bumps the voice down through LRU, and decrements the owning
;   channel's poly_active counter.
;
;   Type:        Subroutine
;   Category:    Voice management
;   Callers:     sbp_midi_note_off, sbp_midi_note (retrigger path),
;                sbp_voice_allocate (steal path),
;                sbp_midi_control_change (CC#123 all-notes-off),
;                sbp_cc_sustain_pedal, sbp_sustain_pool_reserve,
;                sbp_sustain_pool_release
;   Callees:     sbp_voice_render_freq, sbp_voice_lru_remove
;
;   Inputs:
;     BX  --  voice index 0..8
;
;   Outputs:     none
;
;   Side effects:
;     OPL reg 0xB0+v written with KEY-ON=0.
;     sbp_voice_sustain_held[v] = 0
;     sbp_voice_note[v] = 0xFF
;     sbp_ch_poly_active[v's channel]--
;     LRU bumped.
; ----------------------------------------------------------------------------
sbp_voice_release PROC NEAR
                PUSH    CX
                PUSH    DX
                PUSH    SI
                MOV     BYTE PTR CS:[BX + sbp_voice_sustain_held], 0
                XOR     CH, CH
                MOV     CL, CS:[BX + sbp_voice_note]
                XOR     DX, DX
                CALL    sbp_voice_render_freq
                MOV     BYTE PTR CS:[BX + sbp_voice_note], 0FFH
                CALL    sbp_voice_lru_remove
                MOV     DL, CS:[BX + sbp_voice_channel]
                XOR     DH, DH
                MOV     SI, DX
                DEC     BYTE PTR CS:[SI + sbp_ch_poly_active]
                POP     SI
                POP     DX
                POP     CX
                RET
sbp_voice_release ENDP

; ----------------------------------------------------------------------------
; 0x1DFE  --  sbp_voice_lru_remove
;
;   Bumps voice BL to the youngest LRU position (slot 8). Find-and-shift
;   loop: locate BL in the 9-entry LRU array, shift trailing entries
;   down by 1, store BL at slot 8. The "remove" in the name is from the
;   caller's perspective ("remove this voice from its current LRU
;   position"); the value itself is reinserted at the tail.
;
;   Type:        Subroutine
;   Category:    Voice management (LRU bookkeeping)
;   Callers:     sbp_voice_keyon, sbp_voice_release
;
;   Inputs:
;     BL  --  voice index 0..8
;
;   Outputs:     none
;
;   Side effects:
;     sbp_voice_lru reshuffled: BL moves to the tail (slot 8); the
;     entries that were behind BL each shift one slot toward the head.
; ----------------------------------------------------------------------------
sbp_voice_lru_remove PROC NEAR
                PUSH    SI
                PUSH    AX
                XOR     SI, SI
                JMP     SHORT vlru_outer
vlru_find:      CMP     CS:[SI + sbp_voice_lru], BL
                JNE     SHORT vlru_next
                JMP     SHORT vlru_shift_test
vlru_shift:     MOV     AH, CS:[SI + sbp_voice_lru + 1]
                MOV     CS:[SI + sbp_voice_lru], AH
                INC     SI
vlru_shift_test: CMP    SI, 8
                JB      SHORT vlru_shift
vlru_next:      INC     SI
vlru_outer:     CMP     SI, 9
                JB      SHORT vlru_find
                XOR     BH, BH
                MOV     CS:[sbp_voice_lru + 8], BL
                POP     AX
                POP     SI
                RET
sbp_voice_lru_remove ENDP

; ----------------------------------------------------------------------------
; 0x1E2D  --  sbp_voice_render_freq
;
;   Pushes a voice's current pitch + key-on bit to the OPL chip and
;   re-applies the per-op volume via sbp_voice_render_volume.
;
;   Smaller than ADL's equivalent (170 vs 203 bytes) because the SB Pro
;   driver delegates master-volume gain to the mixer chip (slot 12 writes
;   the SB Pro mixer's FM-volume register; we don't multiply it into TL
;   here). Instead the master-volume signal is purely the mixer setting,
;   and per-voice TL only encodes velocity + patch volume + pan.
;
;   Steps:
;     1. Cache voice_note[v] <- CL.
;     2. If drum patch loaded (program >= 0x80): clamp note to [0x1B, 0x58]
;        and remap via sbp_vel_to_tl_lut.
;     3. CX = note * 4 (F-num table is 4 entries per semitone).
;     4. Call pitchbend_apply (returns 0xFFFF on out-of-range bend).
;     5. Divide by 48 -> AL = block, AH = note_in_octave.
;     6. Look up sbp_note_fnum_table[note_in_octave] into CX.
;     7. Write OPL reg 0xA0+v with F-num low byte.
;     8. Build the 0xB0+v byte: (block-1)<<2 | F-num_hi | (KEY-ON if DX).
;     9. Write OPL reg 0xB0+v.
;    10. Compute the velocity-scaled volume index and call
;        sbp_voice_render_volume to write the L/R TL halves.
;
;   Type:        Subroutine
;   Category:    OPL rendering
;   Callers:     sbp_voice_keyon, sbp_voice_release,
;                sbp_midi_pitch_bend, sbp_cc_main_volume, sbp_cc_pan
;   Callees:     sbp_voice_pitchbend_apply, sbp_opl_write,
;                sbp_voice_render_volume
;
;   Inputs:
;     BX  --  voice index 0..8
;     CL  --  MIDI note number
;     DX  --  non-zero = set KEY-ON bit in reg 0xB0; zero = clear it
;
;   Outputs:     none
;
;   Side effects:
;     sbp_voice_note[v] <- CL
;     OPL reg 0xA0+v and 0xB0+v written.
;     Calls into sbp_voice_render_volume which writes OPL reg 0x40+op
;     through the L and R port pairs.
; ----------------------------------------------------------------------------
sbp_voice_render_freq PROC NEAR
                PUSH    SI
                PUSH    DI
                PUSH    AX
                PUSH    BX
                PUSH    CX
                PUSH    DX
                MOV     CS:[BX + sbp_voice_note], CL
                XOR     AH, AH
                MOV     AL, CS:[BX + sbp_voice_channel]
                MOV     SI, AX                  ; SI = channel
                XOR     CH, CH
                MOV     AL, CS:[BX + sbp_voice_program]
                CMP     AL, 80H
                JB      SHORT vrf_have_note

                ; Drum-channel remap into [0x1B, 0x58] -> LUT lookup.
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
                MOV     CL, CS:[SI + sbp_vel_to_tl_lut]
                POP     SI
vrf_have_note:  SHL     CX, 1
                SHL     CX, 1                   ; CX = note * 4
                CALL    sbp_voice_pitchbend_apply
                CMP     CX, 0FFFFH
                JNE     SHORT vrf_in_range
                JMP     SHORT vrf_end
vrf_in_range:   MOV     AX, CX
                MOV     DH, 30H                 ; divisor = 48
                DIV     DH                      ; AL=block, AH=note_in_octave
                XOR     CH, CH
                MOV     CL, AH
                MOV     DI, CX
                SHL     DI, 1
                MOV     CX, CS:[DI + sbp_note_fnum_table]
                ADD     BX, 00A0H               ; BX = OPL reg 0xA0+v
                CALL    sbp_opl_write
                CMP     AL, 0
                JBE     SHORT vrf_block_ok
                DEC     AL
vrf_block_ok:   MOV     CL, 02H
                SHL     AL, CL
                OR      AL, CH                  ; combine block<<2 with F-num hi
                OR      DL, DL
                JZ      SHORT vrf_no_keyon
                OR      AL, 20H                 ; KEY-ON bit
vrf_no_keyon:   XOR     CX, CX
                MOV     CL, AL
                ADD     BX, 10H                 ; BX = 0xB0+v
                CALL    sbp_opl_write           ; write 0xB0+v

                ; Compute velocity-scaled volume index for the L/R writer.
                SUB     BX, 00B0H               ; BX = voice index again
                MOV     AL, CS:[SI + sbp_ch_volume]
                INC     AL
                XOR     CH, CH
                MOV     CL, CS:[BX + sbp_voice_velocity]
                MOV     DI, CX
                MOV     CL, CS:[DI + sbp_volcurve_a]
                INC     CL
                MUL     CL
                MOV     CL, 06H
                SHR     AX, CL
                CALL    sbp_voice_render_volume
vrf_end:        POP     DX
                POP     CX
                POP     BX
                POP     AX
                POP     DI
                POP     SI
                RET
sbp_voice_render_freq ENDP

; ----------------------------------------------------------------------------
; 0x1ED7  --  sbp_voice_pitchbend_apply
;
;   Adjusts the (note * 4) F-number-table index in CX by the channel's
;   current pitch-wheel offset. Computes ((bend - 0x2000) / 0xAB) and
;   adds (positive bend) or subtracts (negative bend). Result clamped
;   to 0x01FC. The divisor 0xAB is chosen so a maximum bend (0x4000
;   range) shifts roughly two semitones (the standard MIDI default).
;
;   Type:        Subroutine
;   Category:    OPL rendering (pitch computation)
;   Callers:     sbp_voice_render_freq
;
;   Inputs:
;     BX  --  voice index (to look up the channel)
;     CX  --  F-num-table index (note * 4)
;
;   Outputs:
;     CX  --  adjusted F-num-table index, or 0xFFFF if the bend would
;             have moved the result negative (caller treats as
;             out-of-range and bails out of the render).
;
;   Side effects:  none
; ----------------------------------------------------------------------------
sbp_voice_pitchbend_apply PROC NEAR
                PUSH    AX
                PUSH    BX
                PUSH    DX
                PUSH    SI
                PUSH    DI
                XOR     AH, AH
                MOV     AL, CS:[BX + sbp_voice_channel]
                MOV     SI, AX
                SHL     SI, 1
                MOV     DI, CS:[SI + sbp_ch_pitchbend]
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
sbp_voice_pitchbend_apply ENDP

; ----------------------------------------------------------------------------
; 0x1F2E  --  sbp_voice_render_volume
;
;   STEREO-AWARE per-voice TL writer. For each of the LEFT and RIGHT
;   sides, and for each of (modulator, carrier-if-additive), we compute:
;
;     pan_factor = volcurve_b[pan/2] (left)  or  volcurve_b[(0x7F-pan)/2] (right)
;     scaled_vol = vol * (0x3F - pan_factor) / 0x3F
;     final_vol  = vol - scaled_vol            (clamped >= 0 for right)
;     curve_vol  = volcurve_b[final_vol]
;     tl_byte    = base + (curve_vol * tl_max / 0x3F)
;     reg_byte   = (tl_byte << 6) | (0x3F - curve_vol * tl_max / 0x3F)
;
;   Each composed byte goes through sbp_opl_write_op_level_l (for left)
;   or sbp_opl_write_op_level_r (for right), which routes the OPL
;   register write through the SB Pro's per-side port pair.
;
;   The four passes (mod-L, car-L, mod-R, car-R) are nearly identical;
;   the right-side pass also handles a potential negative-volume case
;   from the `vol - scaled_vol` subtraction.
;
;   Type:        Subroutine
;   Category:    OPL rendering (SB Pro stereo extension)
;   Callers:     sbp_voice_render_freq
;   Callees:     sbp_opl_write_op_level_l, sbp_opl_write_op_level_r
;
;   Inputs:
;     BX  --  voice index 0..8
;     AL  --  velocity-scaled volume index (already clamped to 0x3F by
;             caller)
;
;   Outputs:     none
;
;   Side effects:
;     OPL reg 0x40 + op_offset written for the modulator op via the L
;     port pair AND via the R port pair (one write per side).
;     If sbp_voice_additive[v] != 0, the carrier op gets the same
;     treatment.
; ----------------------------------------------------------------------------
sbp_voice_render_volume PROC NEAR
                PUSH    AX
                PUSH    CX
                PUSH    DX
                PUSH    SI
                PUSH    DI

                ; Saturate AL at 0x3F.
                CMP     AL, 3FH
                JBE     SHORT vrv_vol_ok
                MOV     AL, 3FH
vrv_vol_ok:     XOR     DH, DH
                MOV     DL, CS:[BX + sbp_voice_channel]
                MOV     SI, DX                  ; SI = channel

                ; ============== LEFT MODULATOR ==============
                PUSH    AX
                PUSH    AX
                MOV     DL, CS:[SI + sbp_ch_pan]
                SHR     DL, 1                   ; DL = pan / 2
                CMP     DL, 3FH
                JBE     SHORT vrv_lm_pan_ok
                MOV     DL, 3FH
vrv_lm_pan_ok:  PUSH    BX
                MOV     BL, DL
                XOR     BH, BH
                MOV     BL, CS:[BX + sbp_volcurve_b]    ; volcurve_b[pan/2]
                MOV     DL, 3FH
                SUB     DL, BL                  ; DL = 0x3F - curve(pan/2)
                POP     BX
                MUL     DL                      ; AX = vol * factor
                MOV     DL, 3FH
                DIV     DL                      ; AL = AX / 0x3F
                MOV     DL, AL                  ; DL = scaled
                POP     AX                      ; restore vol
                SUB     AL, DL                  ; AL = vol - scaled (left-side)
                CMP     DL, 3FH
                JBE     SHORT vrv_lm_dlclamp_ok
                MOV     DL, 3FH
vrv_lm_dlclamp_ok: XOR  AH, AH
                MOV     DI, AX
                MOV     AL, CS:[DI + sbp_volcurve_b]
                PUSH    AX
                SHL     BX, 1
                MOV     CX, CS:[BX + sbp_voice_mod_tl_max]
                MUL     CL
                MOV     CL, 3FH
                DIV     CL
                SUB     CL, AL
                MOV     AX, CS:[BX + sbp_voice_mod_tl_base]
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
                MOV     DL, CS:[BX + sbp_op_perm]
                MOV     DI, DX
                MOV     BL, CS:[DI + sbp_op_regoff]
                XOR     BH, BH
                ADD     BX, 40H
                CALL    sbp_opl_write_op_level_l
                POP     BX
                POP     AX

                ; ============== LEFT CARRIER (if additive) ==============
                CMP     BYTE PTR CS:[BX + sbp_voice_additive], 0
                JE      SHORT vrv_lm_skip_car
                SHL     BX, 1
                MOV     CX, CS:[BX + sbp_voice_car_tl_max]
                MUL     CL
                MOV     CL, 3FH
                DIV     CL
                SUB     CL, AL
                MOV     AX, CS:[BX + sbp_voice_car_tl_base]
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
                MOV     DL, CS:[BX + sbp_op_perm + 9]
                MOV     DI, DX
                MOV     BL, CS:[DI + sbp_op_regoff]
                XOR     BH, BH
                ADD     BX, 40H
                CALL    sbp_opl_write_op_level_l
                POP     BX
vrv_lm_skip_car:

                ; ============== RIGHT MODULATOR ==============
                POP     AX                      ; restore original vol
                PUSH    AX
                MOV     DL, 7FH
                SUB     DL, CS:[SI + sbp_ch_pan]
                SHR     DL, 1                   ; DL = (0x7F - pan)/2
                CMP     DL, 3FH
                JBE     SHORT vrv_rm_pan_ok
                MOV     DL, 3FH
vrv_rm_pan_ok:  PUSH    BX
                MOV     BL, DL
                XOR     BH, BH
                MOV     BL, CS:[BX + sbp_volcurve_b]
                MOV     DL, 3FH
                SUB     DL, BL
                POP     BX
                MUL     DL
                MOV     DL, 3FH
                DIV     DL
                MOV     DL, AL
                POP     AX
                SUB     AL, DL
                CMP     AL, 0
                JAE     SHORT vrv_rm_alok
                XOR     AL, AL
vrv_rm_alok:    XOR     AH, AH
                CMP     DL, 3FH
                JBE     SHORT vrv_rm_dlok
                MOV     DL, 3FH
vrv_rm_dlok:    MOV     DI, AX
                MOV     AL, CS:[DI + sbp_volcurve_b]
                PUSH    AX
                SHL     BX, 1
                MOV     CX, CS:[BX + sbp_voice_mod_tl_max]
                MUL     CL
                MOV     CL, 3FH
                DIV     CL
                SUB     CL, AL
                MOV     AX, CS:[BX + sbp_voice_mod_tl_base]
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
                MOV     DL, CS:[BX + sbp_op_perm]
                MOV     DI, DX
                MOV     BL, CS:[DI + sbp_op_regoff]
                XOR     BH, BH
                ADD     BX, 40H
                CALL    sbp_opl_write_op_level_r
                POP     BX
                POP     AX

                ; ============== RIGHT CARRIER (if additive) ==============
                CMP     BYTE PTR CS:[BX + sbp_voice_additive], 0
                JE      SHORT vrv_rm_skip_car
                SHL     BX, 1
                MOV     CX, CS:[BX + sbp_voice_car_tl_max]
                MUL     CL
                MOV     CL, 3FH
                DIV     CL
                SUB     CL, AL
                MOV     AX, CS:[BX + sbp_voice_car_tl_base]
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
                MOV     DL, CS:[BX + sbp_op_perm + 9]
                MOV     DI, DX
                MOV     BL, CS:[DI + sbp_op_regoff]
                XOR     BH, BH
                ADD     BX, 40H
                CALL    sbp_opl_write_op_level_r
                POP     BX
vrv_rm_skip_car:
                POP     DI
                POP     SI
                POP     DX
                POP     CX
                POP     AX
                RET
sbp_voice_render_volume ENDP

; ----------------------------------------------------------------------------
; 0x20D8  --  sbp_voice_apply_patch
;
;   Loads a 28-byte instrument patch into a voice's two operators. Patch
;   byte at offset 0xC: 0 -> additive (both ops audible), non-zero ->
;   modulator only. Populates the per-voice TL base/max/step working
;   tables from patch bytes 0/8 (carrier) and 0xD/0x15 (modulator), then
;   calls sbp_op_patch_load twice -- once for each op in
;   sbp_voice_oppair[v].
;
;   Type:        Subroutine
;   Category:    Voice management (patch loading)
;   Callers:     sbp_voice_keyon (when program differs from current)
;   Callees:     sbp_op_patch_load
;
;   Inputs:
;     BX  --  voice index 0..8
;     CX  --  CS-relative pointer to 28-byte patch record
;
;   Outputs:     none
;
;   Side effects:
;     sbp_voice_additive[v], sbp_voice_mod_tl_base/max/step[v],
;     sbp_voice_car_tl_base/max/step[v] all populated.
;     OPL reg writes happen indirectly through sbp_op_patch_load ->
;     sbp_op_apply_all_regs.
; ----------------------------------------------------------------------------
sbp_voice_apply_patch PROC NEAR
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
                MOV     BYTE PTR CS:[BX + sbp_voice_additive], 1
                CMP     BYTE PTR CS:[DI + 0CH], 0
                JE      SHORT vap_additive
                MOV     BYTE PTR CS:[BX + sbp_voice_additive], 0
                JMP     SHORT vap_modonly
vap_additive:   SHL     BX, 1
                MOV     AH, 0
                MOV     AL, CS:[DI]
                MOV     CS:[BX + sbp_voice_car_tl_base], AX
                MOV     AL, 3FH
                MOV     AH, CS:[DI + 8]
                SUB     AL, AH
                MOV     AH, 0
                MOV     CS:[BX + sbp_voice_car_tl_max], AX
                MOV     DX, 0
                MOV     CX, 0FH
                DIV     CX
                MOV     CS:[BX + sbp_voice_car_tl_step], AX
                JMP     SHORT vap_mod_pass
vap_modonly:    SHL     BX, 1
vap_mod_pass:   MOV     AH, 0
                MOV     AL, CS:[DI + 0DH]
                MOV     CS:[BX + sbp_voice_mod_tl_base], AX
                MOV     AL, 3FH
                MOV     AH, CS:[DI + 15H]
                SUB     AL, AH
                MOV     AH, 0
                MOV     CS:[BX + sbp_voice_mod_tl_max], AX
                MOV     DX, 0
                MOV     CX, 0FH
                DIV     CX
                MOV     CS:[BX + sbp_voice_mod_tl_step], AX
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
                MOV     BL, CS:[DI + sbp_voice_oppair]
                PUSH    DX
                MOV     DX, AX
                CALL    sbp_op_patch_load
                POP     DX
                INC     DI
                MOV     BH, 0
                MOV     BL, CS:[DI + sbp_voice_oppair]
                MOV     CX, SI
                CALL    sbp_op_patch_load
                POP     DI
                POP     SI
                POP     DX
                POP     CX
                POP     BX
                POP     AX
                RET
sbp_voice_apply_patch ENDP

; ----------------------------------------------------------------------------
; 0x2185  --  sbp_opl_write
;
;   Hardware-write primitive for the OPL2 chip via the standard AdLib
;   port pair (0x388/0x389). Five dummy IN reads for the chip's
;   settling time (~3.3 us index-to-data); 33-iteration busy-wait after
;   the data write so the chip can absorb the value (~23 us).
;
;   This is the AdLib-compatible mono path. The SB Pro stereo paths
;   sbp_opl_write_op_level_l / _r write the same OPL2 chip pair but
;   through the alternate per-side port pairs at 0x220/0x222 and
;   0x222/0x224.
;
;   Type:        Subroutine (hardware primitive)
;   Category:    OPL register I/O (mono / AdLib-compatible)
;   Callers:     sbp_voice_render_freq, sbp_silence_and_reset,
;                sbp_opl_write_rhythm, sbp_opl_write_notesel,
;                sbp_opl_write_op_level, sbp_opl_write_voice_feedback,
;                sbp_opl_write_op_ar_dr, sbp_opl_write_op_sl_rr,
;                sbp_opl_write_op_flags_mult, sbp_opl_write_op_waveform
;
;   Inputs:
;     BL  --  OPL register number (0x00..0xF5)
;     CL  --  value to write
;
;   Outputs:     none
;
;   Side effects:
;     OPL reg BL <- CL (via two OUT instructions on ports 0x388, 0x389).
; ----------------------------------------------------------------------------
sbp_opl_write   PROC    NEAR
                PUSH    AX
                PUSH    DX
                PUSH    CX
                MOV     DX, CS:sbp_port_reg
                MOV     AX, BX
                OUT     DX, AL
                IN      AL, DX
                IN      AL, DX
                IN      AL, DX
                IN      AL, DX
                IN      AL, DX
                MOV     DX, CS:sbp_port_data
                MOV     AX, CX
                OUT     DX, AL
                MOV     CX, 21H
                MOV     DX, CS:sbp_port_status
opl_wr_delay:   IN      AL, DX
                LOOP    opl_wr_delay
                POP     CX
                POP     DX
                POP     AX
                RET
sbp_opl_write   ENDP

; ----------------------------------------------------------------------------
; 0x21AC  --  sbp_mixer_write
;
;   Hardware-write primitive for the SB Pro mixer chip (CT1335 / CT1345
;   on revision 1 cards). Same timing pattern as sbp_opl_write but uses
;   the mixer's port pair: index port = 0x224, data port = 0x225, both
;   read out of sbp_port_mixer_table at offsets +12 and +14. The status-
;   port delay still uses the OPL status (0x388).
;
;   Type:        Subroutine (hardware primitive)
;   Category:    Mixer register I/O (SB Pro only)
;   Callers:     sbp_set_master_volume, sbp_reset_voices
;
;   Inputs:
;     BL  --  mixer register number (e.g. 0x26 = FM channel volume)
;     CL  --  value to write
;
;   Outputs:     none
;
;   Side effects:
;     SB Pro mixer reg BL <- CL.
; ----------------------------------------------------------------------------
sbp_mixer_write PROC    NEAR
                PUSH    AX
                PUSH    DX
                PUSH    CX
                MOV     DX, CS:[sbp_port_mixer_table + 12]  ; mixer index 0x224
                MOV     AX, BX
                OUT     DX, AL
                IN      AL, DX
                IN      AL, DX
                IN      AL, DX
                IN      AL, DX
                IN      AL, DX
                MOV     DX, CS:[sbp_port_mixer_table + 14]  ; mixer data 0x225
                MOV     AX, CX
                OUT     DX, AL
                MOV     CX, 21H
                MOV     DX, CS:sbp_port_status              ; shared status 0x388
mix_wr_delay:   IN      AL, DX
                LOOP    mix_wr_delay
                POP     CX
                POP     DX
                POP     AX
                RET
sbp_mixer_write ENDP

; ----------------------------------------------------------------------------
; 0x21D3  --  sbp_opl_write_op_level_l
;
;   Writes one OPL register through the SB Pro's *left* port bank
;   (index 0x220, data 0x222, status 0x221). If a stereo-routing flag
;   in the 17th byte of sbp_ch_poly_active (i.e. the table's pad slot
;   at offset 0x0202 -- see data-section banner) is set AND the
;   register is in [0xC0..0xC8] (per-voice feedback regs), the OPL3
;   LEFT-channel bit (0x20) is OR'd into the data byte before the write.
;
;   Type:        Subroutine (hardware primitive)
;   Category:    OPL register I/O (SB Pro left bank)
;   Callers:     sbp_voice_render_volume (per-op TL writes only)
;
;   Inputs:
;     BL  --  OPL register number
;     CL  --  value to write
;
;   Outputs:     none
;
;   Side effects:
;     OPL2 (left bank) reg BL <- CL (possibly OR'd with 0x20 on C0..C8).
; ----------------------------------------------------------------------------
sbp_opl_write_op_level_l PROC NEAR
                PUSH    AX
                PUSH    DX
                PUSH    CX
                CMP     BYTE PTR CS:[sbp_ch_poly_active + 16], 0
                JE      SHORT opl_l_write
                CMP     BL, 0C0H
                JB      SHORT opl_l_write
                CMP     BL, 0C8H
                JA      SHORT opl_l_write
                OR      CL, 20H                 ; OPL3 LEFT-channel bit
opl_l_write:    MOV     DX, CS:[sbp_port_mixer_table + 0]   ; left index 0x220
                MOV     AX, BX
                OUT     DX, AL
                IN      AL, DX
                IN      AL, DX
                IN      AL, DX
                IN      AL, DX
                IN      AL, DX
                MOV     DX, CS:[sbp_port_mixer_table + 4]   ; left data 0x222
                MOV     AX, CX
                OUT     DX, AL
                MOV     CX, 21H
                MOV     DX, CS:[sbp_port_mixer_table + 2]   ; status 0x221
opl_l_delay:    IN      AL, DX
                LOOP    opl_l_delay
                POP     CX
                POP     DX
                POP     AX
                RET
sbp_opl_write_op_level_l ENDP

; ----------------------------------------------------------------------------
; 0x220F  --  sbp_opl_write_op_level_r
;
;   Writes one OPL register through the SB Pro's *right* port bank
;   (index 0x222, data 0x224, status 0x223). Same logic as the L variant
;   but with the OPL3 RIGHT-channel bit (0x10) for the C0..C8 case.
;
;   Type:        Subroutine (hardware primitive)
;   Category:    OPL register I/O (SB Pro right bank)
;   Callers:     sbp_voice_render_volume (per-op TL writes only)
;
;   Inputs:
;     BL  --  OPL register number
;     CL  --  value to write
;
;   Outputs:     none
;
;   Side effects:
;     OPL2 (right bank) reg BL <- CL (possibly OR'd with 0x10 on C0..C8).
; ----------------------------------------------------------------------------
sbp_opl_write_op_level_r PROC NEAR
                PUSH    AX
                PUSH    DX
                PUSH    CX
                CMP     BYTE PTR CS:[sbp_ch_poly_active + 16], 0
                JE      SHORT opl_r_write
                CMP     BL, 0C0H
                JB      SHORT opl_r_write
                CMP     BL, 0C8H
                JA      SHORT opl_r_write
                OR      CL, 10H                 ; OPL3 RIGHT-channel bit
opl_r_write:    MOV     DX, CS:[sbp_port_mixer_table + 6]   ; right index 0x222
                MOV     AX, BX
                OUT     DX, AL
                IN      AL, DX
                IN      AL, DX
                IN      AL, DX
                IN      AL, DX
                IN      AL, DX
                MOV     DX, CS:[sbp_port_mixer_table + 10]  ; right data 0x223
                MOV     AX, CX
                OUT     DX, AL
                MOV     CX, 21H
                MOV     DX, CS:[sbp_port_mixer_table + 8]   ; status 0x222
opl_r_delay:    IN      AL, DX
                LOOP    opl_r_delay
                POP     CX
                POP     DX
                POP     AX
                RET
sbp_opl_write_op_level_r ENDP

; ----------------------------------------------------------------------------
; 0x224B  --  sbp_opl_init_all_ops
;
;   Walks all 18 operators and loads each with default_patch_mod (for
;   modulators) or default_patch_car (for carriers) via
;   sbp_op_patch_stage_load. Called at chip-reset time to put every op
;   in a known sensible state.
;
;   Type:        Subroutine
;   Category:    Chip initialization
;   Callers:     sbp_silence_and_reset
;   Callees:     sbp_op_patch_stage_load
;
;   Inputs:      none
;   Outputs:     none
;
;   Side effects:
;     All 18 entries of sbp_op_shadow populated with default patch data.
;     All 18 operators' OPL registers rewritten via sbp_op_apply_all_regs.
; ----------------------------------------------------------------------------
sbp_opl_init_all_ops PROC NEAR
                PUSH    BX
                PUSH    CX
                PUSH    DX
                PUSH    DI
                MOV     DI, 0

                ; Loop body restarts here. Each iteration handles one
                ; operator (DI = 0..17) and falls into one of the two
                ; branches below based on whether the op is a modulator
                ; or carrier.
init_loop:      MOV     BX, DI
                MOV     DX, 0
                CMP     BYTE PTR CS:[DI + sbp_op_iscarrier], 0
                JE      SHORT init_modulator
                MOV     CX, OFFSET sbp_default_patch_car
                CALL    sbp_op_patch_stage_load
                JMP     SHORT init_next
init_modulator: MOV     CX, OFFSET sbp_default_patch_mod
                CALL    sbp_op_patch_stage_load
init_next:      INC     DI
                CMP     DI, 12H
                JNE     SHORT init_loop
                POP     DI
                POP     DX
                POP     CX
                POP     BX
                RET
sbp_opl_init_all_ops ENDP

; ----------------------------------------------------------------------------
; 0x2278  --  sbp_opl_write_rhythm
;
;   Composes OPL register 0xBD (rhythm-mode + AM/Vib depth) from the
;   global mirrors and writes it. ADL has the same byte structure --
;   pre-OPL3 the high bits gate AM and Vib depth.
;
;   Bits in the composed value:
;     bit 7  AM depth   (1 if sbp_opl_amdepth != 0)
;     bit 6  Vib depth  (1 if sbp_opl_vibdepth != 0 -- low byte only)
;     bits 5..0  rhythm/BD/SD/TT/CY/HH key-ons (from sbp_opl_rhythm)
;
;   Type:        Subroutine (per-register OPL writer)
;   Category:    OPL register I/O
;   Callers:     sbp_op_apply_all_regs
;   Callees:     sbp_opl_write
;
;   Inputs:      none (reads global mirrors)
;   Outputs:     none
;
;   Side effects:
;     OPL reg 0xBD written via sbp_opl_write.
; ----------------------------------------------------------------------------
sbp_opl_write_rhythm PROC NEAR
                PUSH    BX
                PUSH    CX
                MOV     CX, 0
                CMP     BYTE PTR CS:sbp_opl_amdepth, 0
                JE      SHORT rh_no_am
                OR      CL, 80H
rh_no_am:       CMP     BYTE PTR CS:sbp_opl_vibdepth, 0
                JE      SHORT rh_no_vib
                OR      CL, 40H
rh_no_vib:      OR      CL, CS:sbp_opl_rhythm
                MOV     BX, 0BDH
                CALL    sbp_opl_write
                POP     CX
                POP     BX
                RET
sbp_opl_write_rhythm ENDP

; ----------------------------------------------------------------------------
; 0x22A1  --  sbp_op_patch_stage_load
;
;   Copies a 13-byte source patch (from CS:CX) into sbp_patch_stage and
;   forwards to sbp_op_patch_load with the stage buffer as the source.
;   Used by sbp_opl_init_all_ops to push the two default patches into
;   each operator.
;
;   Type:        Subroutine
;   Category:    Patch loading
;   Callers:     sbp_opl_init_all_ops
;   Callees:     sbp_op_patch_load
;
;   Inputs:
;     BX  --  operator index 0..17
;     CX  --  CS-relative pointer to 13-byte source patch
;
;   Outputs:     none
;
;   Side effects:
;     sbp_patch_stage[0..12] <- source bytes.
;     OPL registers for the operator updated via sbp_op_patch_load.
; ----------------------------------------------------------------------------
sbp_op_patch_stage_load PROC NEAR
                PUSH    BX
                PUSH    CX
                PUSH    DX
                PUSH    DI
                PUSH    SI
                MOV     DI, 0
                MOV     SI, CX
                MOV     CH, 0
stage_copy:     MOV     CL, CS:[SI]
                MOV     CS:[DI + sbp_patch_stage], CL
                INC     SI
                INC     DI
                CMP     DI, 0DH
                JNE     SHORT stage_copy
                POP     SI
                MOV     CX, OFFSET sbp_patch_stage
                CALL    sbp_op_patch_load
                POP     DI
                POP     DX
                POP     CX
                POP     BX
                RET
sbp_op_patch_stage_load ENDP

; ----------------------------------------------------------------------------
; 0x22C8  --  sbp_op_patch_load
;
;   Loads a 13-byte patch into sbp_op_shadow[op*14..op*14+12], stores
;   (DL & 3) at sbp_op_shadow[op*14+13], then calls sbp_op_apply_all_regs
;   to push every affected OPL register.
;
;   Type:        Subroutine
;   Category:    Patch loading
;   Callers:     sbp_voice_apply_patch, sbp_op_patch_stage_load
;   Callees:     sbp_op_apply_all_regs
;
;   Inputs:
;     BX  --  operator index 0..17
;     CX  --  CS-relative pointer to the 13-byte patch
;     DL  --  feedback/algorithm byte (low 2 bits stored at shadow[+13])
;
;   Outputs:     none
;
;   Side effects:
;     sbp_op_shadow[op*14 + 0..13] overwritten.
;     All eight per-register OPL writers fired via sbp_op_apply_all_regs.
; ----------------------------------------------------------------------------
sbp_op_patch_load PROC NEAR
                PUSH    CX
                PUSH    DX
                PUSH    SI
                PUSH    DI
                MOV     SI, BX
                PUSH    AX
                PUSH    BX
                PUSH    CX
                ; Compute SI = op * 14, used to index into the 14-byte-
                ; per-operator shadow table at sbp_op_shadow. The 8086
                ; has no fast multiply-by-immediate, so the driver uses
                ; the shift-add identity
                ;     op * 14 = op*2 + op*4 + op*8
                ; carrying intermediate values in BX (op*2) and CX (op*4)
                ; while AX accumulates the running result.
                ;
                ; This same 9-instruction sequence is inlined verbatim
                ; at five other call sites (sbp_opl_write_op_level,
                ; sbp_opl_write_voice_feedback, sbp_opl_write_op_ar_dr,
                ; sbp_opl_write_op_sl_rr, sbp_opl_write_op_flags_mult,
                ; sbp_opl_write_op_waveform); the comment is shortened
                ; there to ``; op * 14 (see sbp_op_patch_load)``.
                MOV     AX, SI
                SHL     AX, 1                   ; AX = op * 2
                MOV     BX, AX                  ; BX = op * 2
                SHL     AX, 1                   ; AX = op * 4
                MOV     CX, AX                  ; CX = op * 4
                SHL     AX, 1                   ; AX = op * 8
                ADD     AX, BX                  ; AX = op*8 + op*2 = op*10
                ADD     AX, CX                  ; AX = op*10 + op*4 = op*14
                MOV     SI, AX
                POP     CX
                POP     BX
                POP     AX
                PUSH    DX
                MOV     DI, 0
opl_copy:       PUSH    DI
                MOV     DI, CX
                MOV     DL, CS:[DI]
                MOV     CS:[SI + sbp_op_shadow], DL
                POP     DI
                INC     SI
                INC     CX
                INC     DI
                CMP     DI, 0DH
                JNE     SHORT opl_copy
                POP     DX
                AND     DL, 03H
                MOV     CS:[SI + sbp_op_shadow], DL
                PUSH    BX
                CALL    sbp_op_apply_all_regs
                POP     BX
                POP     DI
                POP     SI
                POP     DX
                POP     CX
                RET
sbp_op_patch_load ENDP

; ----------------------------------------------------------------------------
; 0x2311  --  sbp_op_apply_all_regs
;
;   Walks the eight OPL register-write helpers in order:
;     rhythm -> notesel -> op_level -> voice_feedback ->
;     op_ar_dr -> op_sl_rr -> op_flags_mult -> op_waveform
;   Each helper reads its slice of sbp_op_shadow[op*14..+13] and writes
;   the corresponding OPL register through sbp_opl_write.
;
;   Type:        Subroutine (fanout)
;   Category:    OPL register I/O
;   Callers:     sbp_op_patch_load
;   Callees:     sbp_opl_write_rhythm, sbp_opl_write_notesel,
;                sbp_opl_write_op_level, sbp_opl_write_voice_feedback,
;                sbp_opl_write_op_ar_dr, sbp_opl_write_op_sl_rr,
;                sbp_opl_write_op_flags_mult, sbp_opl_write_op_waveform
;
;   Inputs:
;     BX  --  operator index 0..17 (forwarded to each helper)
;
;   Outputs:     none
;   Side effects:  all relevant OPL registers for this op are rewritten.
; ----------------------------------------------------------------------------
sbp_op_apply_all_regs PROC NEAR
                CALL    sbp_opl_write_rhythm
                CALL    sbp_opl_write_notesel
                CALL    sbp_opl_write_op_level
                CALL    sbp_opl_write_voice_feedback
                CALL    sbp_opl_write_op_ar_dr
                CALL    sbp_opl_write_op_sl_rr
                CALL    sbp_opl_write_op_flags_mult
                CALL    sbp_opl_write_op_waveform
                RET
sbp_op_apply_all_regs ENDP

; ----------------------------------------------------------------------------
; 0x232A  --  sbp_opl_write_op_level
;
;   Writes OPL register 0x40 + op_offset (KSL + TL) for one operator.
;   The byte composition:
;     bits 7..6  KSL  (from op_shadow[op*14 + 0])
;     bits 5..0  TL   (from op_shadow[op*14 + 8], masked to 6 bits)
;
;   Note: this is the mono / AdLib-compatible TL writer used at patch-
;   load time. The stereo per-side TL writers (sbp_opl_write_op_level_l
;   / _r) are different functions called from sbp_voice_render_volume
;   to handle the pan-weighted L/R split during note rendering.
;
;   Type:        Subroutine (per-register OPL writer)
;   Category:    OPL register I/O
;   Callers:     sbp_op_apply_all_regs
;   Callees:     sbp_opl_write
;
;   Inputs:
;     BX  --  operator index 0..17
;
;   Outputs:     none
;
;   Side effects:
;     OPL reg (0x40 + sbp_op_regoff[op]) <- KSL<<6 | TL.
; ----------------------------------------------------------------------------
sbp_opl_write_op_level PROC NEAR
                PUSH    AX
                PUSH    BX
                PUSH    CX
                PUSH    DI
                MOV     DI, BX
                PUSH    AX
                PUSH    BX
                PUSH    CX

                ; DI = op * 14 (shadow-table stride; see sbp_op_patch_load
                ; for the full op*14 = op*2 + op*4 + op*8 explanation).
                MOV     AX, DI
                SHL     AX, 1                   ; AX = op * 2
                MOV     BX, AX
                SHL     AX, 1                   ; AX = op * 4
                MOV     CX, AX
                SHL     AX, 1                   ; AX = op * 8
                ADD     AX, BX                  ; AX = op*8 + op*2 = op*10
                ADD     AX, CX                  ; AX = op*10 + op*4 = op*14
                MOV     DI, AX
                POP     CX
                POP     BX
                POP     AX
                MOV     AH, 0
                MOV     AL, CS:[DI + sbp_op_shadow]
                MOV     CL, 06H
                SHL     AL, CL                  ; AL = KSL << 6
                MOV     CX, AX
                MOV     AL, CS:[DI + sbp_op_shadow + 8]
                AND     AL, 3FH                 ; TL (6 bits)
                OR      CL, AL
                MOV     BH, 0
                MOV     DI, BX
                MOV     BL, CS:[DI + sbp_op_regoff]
                ADD     BL, 40H
                CALL    sbp_opl_write
                POP     DI
                POP     CX
                POP     BX
                POP     AX
                RET
sbp_opl_write_op_level ENDP

; ----------------------------------------------------------------------------
; 0x2372  --  sbp_opl_write_notesel
;
;   Writes OPL reg 0x08 (CSM / NOTE-SEL): 0x40 if sbp_opl_notesel != 0,
;   else 0. NOTE-SEL controls which MIDI note value the key-scale logic
;   "rolls over" at; CSM (bit 7) is unused in this driver.
;
;   Type:        Subroutine (per-register OPL writer)
;   Category:    OPL register I/O
;   Callers:     sbp_op_apply_all_regs
;   Callees:     sbp_opl_write
;
;   Inputs:      none (reads sbp_opl_notesel)
;   Outputs:     none
;
;   Side effects:
;     OPL reg 0x08 written.
; ----------------------------------------------------------------------------
sbp_opl_write_notesel PROC NEAR
                PUSH    BX
                PUSH    CX
                MOV     CX, 0
                CMP     BYTE PTR CS:sbp_opl_notesel, 0
                JE      SHORT ns_no
                MOV     CL, 40H
ns_no:          MOV     BX, 8
                CALL    sbp_opl_write
                POP     CX
                POP     BX
                RET
sbp_opl_write_notesel ENDP

; ----------------------------------------------------------------------------
; 0x238A  --  sbp_opl_write_voice_feedback
;
;   Writes OPL reg 0xC0+voice (FB + ALG + stereo bit). The "voice" here
;   is sbp_op_voice[op] (each pair of ops maps to one voice). Skips
;   carrier ops -- only the modulator of each pair triggers a write,
;   since both ops share the voice-level 0xC0+v register. Reads
;   FB/ALG from op_shadow[op*14+2] and a stereo flag from
;   op_shadow[op*14+12].
;
;   Type:        Subroutine (per-register OPL writer)
;   Category:    OPL register I/O
;   Callers:     sbp_op_apply_all_regs
;   Callees:     sbp_opl_write
;
;   Inputs:
;     BX  --  operator index 0..17
;
;   Outputs:     none
;
;   Side effects:
;     For modulator ops: OPL reg (0xC0 + sbp_op_voice[op]) written.
;     For carrier ops: nothing.
; ----------------------------------------------------------------------------
sbp_opl_write_voice_feedback PROC NEAR
                PUSH    BX
                PUSH    CX
                PUSH    DI
                MOV     DI, BX
                CMP     BYTE PTR CS:[DI + sbp_op_iscarrier], 0
                JNE     SHORT fb_skip
                PUSH    AX
                PUSH    BX
                PUSH    CX

                ; DI = op * 14 (shadow-table stride; see sbp_op_patch_load).
                MOV     AX, DI
                SHL     AX, 1                   ; AX = op * 2
                MOV     BX, AX
                SHL     AX, 1                   ; AX = op * 4
                MOV     CX, AX
                SHL     AX, 1                   ; AX = op * 8
                ADD     AX, BX                  ; AX = op*10
                ADD     AX, CX                  ; AX = op*14
                MOV     DI, AX
                POP     CX
                POP     BX
                POP     AX
                MOV     AH, 0
                MOV     AL, CS:[DI + sbp_op_shadow + 2]
                SHL     AX, 1
                MOV     CX, AX
                CMP     BYTE PTR CS:[DI + sbp_op_shadow + 12], 0
                JNE     SHORT fb_no_stereo
                INC     CL
fb_no_stereo:   MOV     DI, BX
                MOV     BH, 0
                MOV     BL, CS:[DI + sbp_op_voice]
                ADD     BL, 0C0H
                AND     CL, 0FH
                CALL    sbp_opl_write
fb_skip:        POP     DI
                POP     CX
                POP     BX
                RET
sbp_opl_write_voice_feedback ENDP

; ----------------------------------------------------------------------------
; 0x23DA  --  sbp_opl_write_op_ar_dr
;
;   Writes OPL reg 0x60 + op_offset (AR + DR).
;     bits 7..4  AR  (from shadow[op*14 + 3])
;     bits 3..0  DR  (from shadow[op*14 + 6])
;
;   Type:        Subroutine (per-register OPL writer)
;   Category:    OPL register I/O
;   Callers:     sbp_op_apply_all_regs
;   Callees:     sbp_opl_write
;
;   Inputs:
;     BX  --  operator index 0..17
;
;   Outputs:     none
;
;   Side effects:
;     OPL reg (0x60 + sbp_op_regoff[op]) <- AR<<4 | DR.
; ----------------------------------------------------------------------------
sbp_opl_write_op_ar_dr PROC NEAR
                PUSH    BX
                PUSH    CX
                PUSH    DI
                MOV     DI, BX
                PUSH    AX
                PUSH    BX
                PUSH    CX

                ; DI = op * 14 (shadow-table stride; see sbp_op_patch_load).
                MOV     AX, DI
                SHL     AX, 1                   ; AX = op * 2
                MOV     BX, AX
                SHL     AX, 1                   ; AX = op * 4
                MOV     CX, AX
                SHL     AX, 1                   ; AX = op * 8
                ADD     AX, BX                  ; AX = op*10
                ADD     AX, CX                  ; AX = op*14
                MOV     DI, AX
                POP     CX
                POP     BX
                POP     AX
                MOV     AH, 0
                MOV     AL, CS:[DI + sbp_op_shadow + 3]
                MOV     CL, 04H
                SHL     AL, CL
                MOV     CX, AX
                MOV     AL, CS:[DI + sbp_op_shadow + 6]
                AND     AL, 0FH
                OR      CL, AL
                MOV     DI, BX
                MOV     BH, 0
                MOV     BL, CS:[DI + sbp_op_regoff]
                ADD     BL, 60H
                CALL    sbp_opl_write
                POP     DI
                POP     CX
                POP     BX
                RET
sbp_opl_write_op_ar_dr ENDP

; ----------------------------------------------------------------------------
; 0x2420  --  sbp_opl_write_op_sl_rr
;
;   Writes OPL reg 0x80 + op_offset (SL + RR).
;     bits 7..4  SL  (from shadow[op*14 + 4])
;     bits 3..0  RR  (from shadow[op*14 + 7])
;
;   Type:        Subroutine (per-register OPL writer)
;   Category:    OPL register I/O
;   Callers:     sbp_op_apply_all_regs
;   Callees:     sbp_opl_write
;
;   Inputs:
;     BX  --  operator index 0..17
;
;   Outputs:     none
;
;   Side effects:
;     OPL reg (0x80 + sbp_op_regoff[op]) <- SL<<4 | RR.
; ----------------------------------------------------------------------------
sbp_opl_write_op_sl_rr PROC NEAR
                PUSH    BX
                PUSH    CX
                PUSH    DI
                MOV     DI, BX
                PUSH    AX
                PUSH    BX
                PUSH    CX

                ; DI = op * 14 (shadow-table stride; see sbp_op_patch_load).
                MOV     AX, DI
                SHL     AX, 1                   ; AX = op * 2
                MOV     BX, AX
                SHL     AX, 1                   ; AX = op * 4
                MOV     CX, AX
                SHL     AX, 1                   ; AX = op * 8
                ADD     AX, BX                  ; AX = op*10
                ADD     AX, CX                  ; AX = op*14
                MOV     DI, AX
                POP     CX
                POP     BX
                POP     AX
                MOV     AH, 0
                MOV     AL, CS:[DI + sbp_op_shadow + 4]
                MOV     CL, 04H
                SHL     AL, CL
                MOV     CX, AX
                MOV     AL, CS:[DI + sbp_op_shadow + 7]
                AND     AL, 0FH
                OR      CL, AL
                MOV     DI, BX
                MOV     BH, 0
                MOV     BL, CS:[DI + sbp_op_regoff]
                ADD     BL, 80H
                CALL    sbp_opl_write
                POP     DI
                POP     CX
                POP     BX
                RET
sbp_opl_write_op_sl_rr ENDP

; ----------------------------------------------------------------------------
; 0x2466  --  sbp_opl_write_op_flags_mult
;
;   Writes OPL reg 0x20 + op_offset (AM/Vib/EG/KSR/MULT).
;     bit 7      AM       (from shadow[op*14 + 9])
;     bit 6      Vib      (from shadow[op*14 + 10])
;     bit 5      EG-type  (from shadow[op*14 + 5])
;     bit 4      KSR      (from shadow[op*14 + 11])
;     bits 3..0  MULT     (from shadow[op*14 + 1])
;
;   Type:        Subroutine (per-register OPL writer)
;   Category:    OPL register I/O
;   Callers:     sbp_op_apply_all_regs
;   Callees:     sbp_opl_write
;
;   Inputs:
;     BX  --  operator index 0..17
;
;   Outputs:     none
;
;   Side effects:
;     OPL reg (0x20 + sbp_op_regoff[op]) written with the composed byte.
; ----------------------------------------------------------------------------
sbp_opl_write_op_flags_mult PROC NEAR
                PUSH    CX
                PUSH    DI
                MOV     DI, BX
                PUSH    AX
                PUSH    BX
                PUSH    CX

                ; DI = op * 14 (shadow-table stride; see sbp_op_patch_load).
                MOV     AX, DI
                SHL     AX, 1                   ; AX = op * 2
                MOV     BX, AX
                SHL     AX, 1                   ; AX = op * 4
                MOV     CX, AX
                SHL     AX, 1                   ; AX = op * 8
                ADD     AX, BX                  ; AX = op*10
                ADD     AX, CX                  ; AX = op*14
                MOV     DI, AX
                POP     CX
                POP     BX
                POP     AX
                MOV     AH, 0
                MOV     AL, CS:[DI + sbp_op_shadow + 9]
                MOV     CX, 0
                CMP     AL, 0
                JE      SHORT fm_no_am
                OR      CL, 80H
fm_no_am:       MOV     AL, CS:[DI + sbp_op_shadow + 10]
                CMP     AL, 0
                JE      SHORT fm_no_vib
                OR      CL, 40H
fm_no_vib:      MOV     AL, CS:[DI + sbp_op_shadow + 5]
                CMP     AL, 0
                JE      SHORT fm_no_eg
                OR      CL, 20H
fm_no_eg:       MOV     AL, CS:[DI + sbp_op_shadow + 11]
                CMP     AL, 0
                JE      SHORT fm_no_ksr
                OR      CL, 10H
fm_no_ksr:      MOV     AL, CS:[DI + sbp_op_shadow + 1]
                AND     AL, 0FH
                OR      CL, AL
                PUSH    BX
                MOV     DI, BX
                MOV     BH, 0
                MOV     BL, CS:[DI + sbp_op_regoff]
                ADD     BL, 20H
                CALL    sbp_opl_write
                POP     BX
                POP     DI
                POP     CX
                RET
sbp_opl_write_op_flags_mult ENDP

; ----------------------------------------------------------------------------
; 0x24D4  --  sbp_opl_write_op_waveform
;
;   Writes OPL reg 0xE0 + op_offset (waveform select). Only if the
;   wave-select-enable global (sbp_wave_select_en, mirror of reg 0x01
;   bit 5) is non-zero -- otherwise the OPL ignores 0xE0 writes and
;   produces sine waves regardless. Reads the waveform code from
;   sbp_op_shadow[op*14 + 13].
;
;   Type:        Subroutine (per-register OPL writer)
;   Category:    OPL register I/O
;   Callers:     sbp_op_apply_all_regs
;   Callees:     sbp_opl_write
;
;   Inputs:
;     BX  --  operator index 0..17
;
;   Outputs:     none
;
;   Side effects:
;     When sbp_wave_select_en != 0:
;       OPL reg (0xE0 + sbp_op_regoff[op]) <- shadow[+13].
;     When sbp_wave_select_en == 0: nothing.
; ----------------------------------------------------------------------------
sbp_opl_write_op_waveform PROC NEAR
                PUSH    BX
                PUSH    CX
                PUSH    DI
                CMP     WORD PTR CS:sbp_wave_select_en, 0
                JE      SHORT wf_skip
                XOR     BH, BH
                MOV     DI, BX
                PUSH    AX
                PUSH    BX
                PUSH    CX

                ; DI = op * 14 (shadow-table stride; see sbp_op_patch_load).
                MOV     AX, DI
                SHL     AX, 1                   ; AX = op * 2
                MOV     BX, AX
                SHL     AX, 1                   ; AX = op * 4
                MOV     CX, AX
                SHL     AX, 1                   ; AX = op * 8
                ADD     AX, BX                  ; AX = op*10
                ADD     AX, CX                  ; AX = op*14
                MOV     DI, AX
                POP     CX
                POP     BX
                POP     AX
                XOR     CH, CH
                MOV     CL, CS:[DI + sbp_op_shadow + 13]
                MOV     DI, BX
                MOV     BL, CS:[DI + sbp_op_regoff]
                ADD     BL, 0E0H
                CALL    sbp_opl_write
wf_skip:        POP     DI
                POP     CX
                POP     BX
                RET
sbp_opl_write_op_waveform ENDP

; ----------------------------------------------------------------------------
; 0x2513  --  sbp_silence_and_reset
;
;   Full chip reset: write 0 to OPL regs 0x00..0xF5, set the waveform-
;   select-enable mirror to 0x20 (and write it through), then reload
;   every operator with the default mod/car patch via
;   sbp_opl_init_all_ops.
;
;   Quirk: PUSH BX/CX then POP BX/CX in the SAME order (not reversed).
;   Caller's BX and CX are swapped on return.
;
;   Type:        Subroutine
;   Category:    Chip initialization
;   Callers:     sbp_reset_voices, sbp_load_patch_bank
;   Callees:     sbp_opl_write, sbp_opl_init_all_ops
;
;   Inputs:      none
;   Outputs:     none
;
;   Side effects:
;     - OPL regs 0x00..0xF5 cleared (246 writes via sbp_opl_write).
;     - sbp_wave_select_en <- 0x0020; OPL reg 0x01 <- 0x20.
;     - All 18 operators reloaded with their default patches.
;     - Caller's BX and CX swapped on return (see Quirk above).
; ----------------------------------------------------------------------------
sbp_silence_and_reset PROC NEAR
                PUSH    BX
                PUSH    CX
                XOR     BX, BX
                XOR     CX, CX
                JMP     SHORT sar_test
sar_body:       CALL    sbp_opl_write
                INC     BX
sar_test:       CMP     BX, 0F6H
                JB      SHORT sar_body
                MOV     WORD PTR CS:sbp_wave_select_en, 0020H
                MOV     BX, 0001H
                MOV     CX, CS:sbp_wave_select_en
                CALL    sbp_opl_write
                CALL    sbp_opl_init_all_ops
                POP     BX
                POP     CX
                RET
sbp_silence_and_reset ENDP

; ----------------------------------------------------------------------------
; 0x253D  --  sbp_query_state  (slot 17)
;
;   Read side of the slot ABI: lets the game inspect the driver's cached
;   per-channel state. AH selects the field family (pitchbend / program /
;   CC), CH selects the CC# within the CC family. Returns 0xFFFF on
;   any unknown selector.
;
;   Selector map:
;     AH=0xE0           -> AX = sbp_ch_pitchbend[AL]
;     AH=0xC0           -> AL = sbp_ch_program[AL]
;     AH=0xB0, CH=0x07  -> AL = sbp_ch_volume[AL]
;     AH=0xB0, CH=0x0A  -> AL = sbp_ch_pan[AL]
;     AH=0xB0, CH=0x40  -> AL = sbp_ch_sustain_pedal[AL]
;     AH=0xB0, CH=0x4B  -> AL = sbp_ch_sustain_count[AL]
;                          or sbp_ch_poly_max[AL] if CL=0xFF
;     anything else     -> AX = 0xFFFF
;
;   Type:        Slot handler
;   Category:    State query
;   Dispatch:    Slot 17 (called as: BP=17, AL=channel, AH=field family,
;                CH=CC selector, CL=sub-selector)
;   Callers:     Game (via dispatch)
;
;   Inputs:
;     AL  --  MIDI channel (0..15)
;     AH  --  field family selector
;     CH  --  CC# within the 0xB0 family
;     CL  --  sub-selector for the 0x4B sustain-count query
;
;   Outputs:
;     AX  --  the requested value, or 0xFFFF if the selector wasn't
;             recognised.
; ----------------------------------------------------------------------------
sbp_query_state PROC NEAR
                PUSH    SI
                MOV     SI, AX
                AND     SI, 00FFH
                CMP     AH, 0E0H
                JNE     SHORT qry_not_e0
                SHL     SI, 1
                MOV     AX, CS:[SI + sbp_ch_pitchbend]
                JMP     SHORT qry_end
qry_not_e0:     CMP     AH, 0C0H
                JNE     SHORT qry_not_c0
                XOR     AH, AH
                MOV     AL, CS:[SI + sbp_ch_program]
                JMP     SHORT qry_end
qry_not_c0:     CMP     AH, 0B0H
                JNE     SHORT qry_unknown
                XOR     AH, AH
                CMP     CH, 07H
                JNE     SHORT qry_not_07
                MOV     AL, CS:[SI + sbp_ch_volume]
                JMP     SHORT qry_end
qry_not_07:     CMP     CH, 0AH
                JNE     SHORT qry_not_0a
                MOV     AL, CS:[SI + sbp_ch_pan]
                JMP     SHORT qry_end
qry_not_0a:     CMP     CH, 40H
                JNE     SHORT qry_not_40
                MOV     AL, CS:[SI + sbp_ch_sustain_pedal]
                JMP     SHORT qry_end
qry_not_40:     CMP     CH, 4BH
                JNE     SHORT qry_unknown
                CMP     CL, 0FFH
                JE      SHORT qry_use_max
                MOV     AL, CS:[SI + sbp_ch_sustain_count]
                JMP     SHORT qry_end
                JMP     SHORT qry_unknown
qry_use_max:    MOV     AL, CS:[SI + sbp_ch_poly_max]
                JMP     SHORT qry_end
qry_unknown:    MOV     AX, 0FFFFH
qry_end:        POP     SI
                RET
sbp_query_state ENDP

; ----------------------------------------------------------------------------
; 0x25AA  --  sbp_load_patch_bank  (slot 1)
;
;   Copies sbp_bank_size (5383) bytes from ES:AX into sbp_bank_buf,
;   resets the chip, then re-applies master_volume = 0x0F. Returns a
;   self-id handshake: AX=0x25AA, CL=0, CH=8. The game uses the AX value
;   to confirm the bank uploaded successfully and the CH=8 to learn the
;   driver's per-patch record size as 0x800 / 256 = ... (the exact
;   semantics of the 0x0800 return live in the DUDE loader, not here).
;
;   Type:        Slot handler
;   Category:    Patch bank upload
;   Dispatch:    Slot 1 (called as: BP=1, ES:AX = source pointer)
;   Callers:     Game (via dispatch)
;   Callees:     sbp_silence_and_reset, sbp_set_master_volume
;
;   Inputs:
;     ES:AX  --  far pointer to a 5383-byte patch bank in the game's
;                memory
;
;   Outputs:
;     AX  --  0x25AA handshake
;     CL  --  0
;     CH  --  8
;
;   Side effects:
;     sbp_bank_buf[0..5382] <- ES:AX[0..5382].
;     Chip reset (all OPL regs, all per-op shadow state, default patch
;     reloaded).
;     SB Pro mixer reg 0x26 reset via sbp_set_master_volume(0x0F).
; ----------------------------------------------------------------------------
sbp_load_patch_bank PROC NEAR
                PUSH    BX
                PUSH    DX
                PUSH    SI
                PUSH    DI
                MOV     SI, AX
                XOR     DI, DI
                MOV     CX, CS:sbp_bank_size
                JMP     SHORT lpb_test
lpb_body:       MOV     BL, ES:[SI]
                MOV     CS:[DI + sbp_bank_buf], BL
                INC     SI
                INC     DI
                DEC     CX
lpb_test:       OR      CX, CX
                JNZ     SHORT lpb_body
                CALL    sbp_silence_and_reset
                MOV     CL, 0FH
                CALL    sbp_set_master_volume
                MOV     AX, 25AAH
                MOV     CL, 0
                MOV     CH, 8
                POP     DI
                POP     SI
                POP     DX
                POP     BX
                RET
sbp_load_patch_bank ENDP

; ----------------------------------------------------------------------------
; 0x25DC  --  sbp_get_info  (slot 0)
;
;   Driver descriptor read by the game's loader to confirm what the
;   driver claims to be. The values:
;     AH = 1  -- DUDE iface major version
;     AL = 3  -- device id (OPL2-family, SB Pro variant)
;     CH = 0  -- no extra capability bits
;     CL = 9  -- voice count (9 OPL2 voices)
;
;   Type:        Slot handler
;   Category:    Identification
;   Dispatch:    Slot 0 (called as: BP=0)
;   Callers:     Game (via dispatch)
;
;   Inputs:      none
;   Outputs:
;     AH=1, AL=3, CH=0, CL=9
; ----------------------------------------------------------------------------
sbp_get_info    PROC    NEAR
                MOV     AH, 1
                MOV     AL, 3
                MOV     CH, 0
                MOV     CL, 9
                RET
sbp_get_info    ENDP

                END     _start
