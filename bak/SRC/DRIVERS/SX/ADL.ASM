; ============================================================================
; Sx.SSM.ADL.bin -- Dynamix DUDE-format AdLib (OPL2) sound driver, v2.24
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
; This file is the AdLib (OPL2 chip) driver. The game communicates with it
; through a tiny dispatch ABI (see "About the DUDE dispatch ABI" below):
; one entry point at offset 0x1945, eighteen "slots", each slot a different
; request like "play this note" or "change this controller". When a slot is
; invoked, this code translates the MIDI-style request into the specific
; byte sequences the OPL2 chip understands.
;
; Roughly two thirds of this file is data tables (note-to-frequency lookups,
; default instrument patches, per-voice state); the remaining third is the
; code that orchestrates the chip. The file is laid out exactly as it
; appears on disk, which is also the order it sits in memory once the game
; loads it: first the header that identifies the driver, then the lookup
; tables and state arrays, then the function-pointer table, then the
; dispatch trampoline, then the function bodies.
; ----------------------------------------------------------------------------

; ----------------------------------------------------------------------------
; About the OPL2 (Yamaha YM3812) chip
;
; The AdLib card is built around the YM3812 "OPL2" FM-synthesis chip. The
; chip is a black box with about 250 internal 8-bit registers, exposed to
; the host CPU via just two I/O ports:
;
;   port 0x388  (the "index" port)  --  write the # of the register you
;                                       want to change. Also readable for
;                                       status (timer flags, busy bit).
;   port 0x389  (the "data" port)   --  write the new value for that
;                                       register.
;
; A single write to one of the chip's internal registers is therefore a
; *pair* of OUT instructions: select the register, then send its value.
; The chip needs about 3.3 microseconds to absorb the index write and 23 us
; to absorb the data write -- on the 6-MHz 286 of the era that's "do about
; five dummy reads then move on". The code below uses an empty IN AL, DX
; loop for that delay; see adl_opl_write at the bottom for the canonical
; write sequence.
;
; The chip produces sound by FM synthesis. It has 9 polyphonic "voices",
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
; the latter mode "additive" (see adl_voice_additive).
;
; There are 18 operators in total (9 voices x 2). The operators are
; numbered with an irregular layout because the chip's internal register
; addressing wasn't a flat array:
;
;   voice 0  ->  ops  0,  3        voice 3  ->  ops  8, 11
;   voice 1  ->  ops  1,  4        voice 4  ->  ops  9, 12
;   voice 2  ->  ops  2,  5        voice 5  ->  ops 10, 13
;   voice 6  ->  ops 12, 15        voice 7  ->  ops 13, 16
;   voice 8  ->  ops 14, 17
;
; The mapping is baked into the table at adl_voice_oppair below.
;
; Most chip parameters live in one of these register groups. Each group
; spans 18 entries (one per operator), except 0xA0/0xB0/0xC0 which span 9
; (one per voice):
;
;   0x01       Test register; bit 5 enables the per-op waveform-select reg
;   0x02-0x04  Timer registers (this driver doesn't use them)
;   0x08       CSM (Composite Sine Mode) + NOTE-SEL
;   0x20-0x35  AM/Vib/EG-type/KSR/freq-multiplier (per operator)
;   0x40-0x55  Key-Scale Level (KSL) and Total Level (TL) (per operator)
;   0x60-0x75  Attack Rate (AR) and Decay Rate (DR) (per operator)
;   0x80-0x95  Sustain Level (SL) and Release Rate (RR) (per operator)
;   0xA0-0xA8  Voice F-number low byte (per voice)
;   0xB0-0xB8  Voice F-number high bits + block (octave) + KEY-ON bit
;              (per voice)
;   0xBD       Rhythm mode + AM/Vib depth (global)
;   0xC0-0xC8  Per-voice feedback and additive/FM connection bit
;   0xE0-0xF5  Per-operator waveform selector (when reg 0x01 bit 5 is on)
;
; A few terms confuse new readers:
;
;   "Total level" (TL) is an *attenuation*, not a volume: 0 = loudest,
;   0x3F = silent. Same for "key-scale level" (KSL).
;
;   "F-number" is the OPL's encoding of pitch. It's a 10-bit value that,
;   together with the 3-bit "block" (octave), maps to a frequency. The
;   driver has a precomputed table at adl_note_fnum_table giving 48
;   F-numbers, one per note-within-octave. The block is computed as
;   note / 48 (see adl_voice_render_freq).
;
;   "Key-on" is the bit that says "begin sounding". Setting it triggers
;   the attack phase of the envelope; clearing it triggers release. The
;   driver toggles it via reg 0xB0+v bit 5.
;
; For the full register-level reference, see Yamaha's YM3812 datasheet or
; the OPL chip page at moddingwiki.shikadi.net/wiki/OPL_chip.
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
; into the *dispatch trampoline* at offset 0x1945. Before the call, the
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
;   MOV  BP, CS:[BP + adl_func_table]
;   CALL BP                          ; near call to the slot's handler
;   POP  BP
;   RETF                             ; far return to the game
;
; The handlers themselves are near procedures (`PROC NEAR ... ENDP`); the
; trampoline is the only thing that does a far return.
;
; The 18 slots in this driver, in order:
;
;   Slot  0  adl_get_info                 -- returns AH/AL/CH/CL descriptor
;   Slot  1  adl_load_patch_bank          -- ES:AX = src; copies into bank
;   Slot  2  adl_reset_voices             -- silence all + reset OPL
;   Slot  3  adl_slot_unused_ret          -- (no-op stub)
;   Slot  4  adl_midi_note_off            -- AL=ch, CH=note
;   Slot  5  adl_midi_note                -- AL=ch, CH=note, CL=vel (0=off)
;   Slot  6  adl_slot_unused_ret          -- (no-op stub)
;   Slot  7  adl_midi_control_change      -- AL=ch, CH=cc, CL=val
;   Slot  8  adl_midi_program_change      -- AL=ch, CL=program
;   Slot  9  adl_slot_unused_ret          -- (no-op stub)
;   Slot 10  adl_midi_pitch_bend          -- AL=ch, CX=bend (BE-packed)
;   Slot 11  adl_set_global_param_11d     -- CL=val (0xFF=query)
;   Slot 12  adl_set_master_volume        -- CL=val (0xFF=query)
;   Slot 13  adl_set_master_enable        -- CL=val (0xFF=query)
;   Slot 14  adl_slot_unused_ret          -- (no-op stub)
;   Slot 15  adl_slot_unused_ret          -- (no-op stub)
;   Slot 16  adl_slot_unused_ret          -- (no-op stub)
;   Slot 17  adl_query_state              -- read-side of the setter ABI
;
; Slots 3, 6, 9, 14, 15, 16 all point at a shared one-byte `RET` stub --
; they're reserved in the cross-driver ABI but this particular driver
; doesn't implement them. The driver has no internal timer or IRQ hook;
; every OPL write is initiated by a game-side call into one of these
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
; - Lines like `adl_voice_note    DB 9 DUP(0FFH)` declare data: the
;   label names this address, `DB` says "the following are bytes", and
;   `9 DUP(0FFH)` means "nine copies of the value 0xFF". `DW` is the
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
; ----------------------------------------------------------------------------

; ----------------------------------------------------------------------------
; Glossary of acronyms used in this file (alphabetical)
;
;   ALG       Algorithm (FM connection between two operators: additive
;             vs. modulator->carrier)
;   AM        Amplitude Modulation depth (tremolo)
;   AR        Attack Rate (operator envelope)
;   CC        MIDI Continuous Controller (e.g. CC#7 = main volume)
;   CSM       Composite Sine Mode (an OPL feature this driver doesn't use)
;   DR        Decay Rate (operator envelope)
;   DUDE      Dynamix's universal sound-driver container format
;   EG-type   Envelope-type bit: 0=percussive, 1=sustained
;   FB        Feedback (per-voice modulator self-feedback amount)
;   F-num     F-number, the 10-bit OPL pitch encoding
;   FM        Frequency Modulation (the dominant OPL synthesis mode)
;   KEY-ON    Bit 5 of reg 0xB0+v; begins / sustains a note
;   KSL       Key-Scale Level (per-operator attenuation that increases
;             with note pitch -- imitates acoustic instruments getting
;             quieter at higher pitches)
;   KSR       Key-Scale Rate (per-operator envelope speed-up with pitch)
;   LRU       Least Recently Used (the voice-allocation policy)
;   MULT      Frequency multiplier (per-operator integer ratio of op
;             frequency to voice F-number)
;   OPL2      Yamaha YM3812 FM synthesizer chip
;   RR        Release Rate (operator envelope)
;   SL        Sustain Level (operator envelope)
;   SOA       Struct-Of-Arrays (storage layout where each "field" is its
;             own array indexed by the same index)
;   SysEx     System-Exclusive MIDI message (not used by this driver)
;   TL        Total Level (per-operator attenuation: 0=loud, 0x3F=silent)
;   VIB       Vibrato depth
; ----------------------------------------------------------------------------

                .8086
                .MODEL  TINY
                .CODE
                ORG     0

; ============================================================================
; 0x0000  --  DUDE header
; ============================================================================
_start          LABEL   BYTE
                JMP     adl_dispatch                ; E9 42 19

                DB      0                           ; pad_03

dude_magic_a    DD      87654321H
dude_iface_ver  DB      1, 4
dude_tag        DB      'dude'

device_name_len DB      28
device_name     DB      'AdLib Music Synthesizer Card'

dude_magic_b    DD      0FEDCBA98H
dude_driver_kind DD     2
driver_ver_str  DB      '2.24'

; ============================================================================
; 0x0037  --  OPL2 I/O port constants
;
;   The AdLib card sits at base 0x388. Writing the index port selects which
;   internal register to talk to; writing the data port sets its value.
;   Both share the same physical address (the chip distinguishes them by
;   the data-vs-index latch, not by port number) -- which is why
;   adl_port_reg and adl_port_status both read 0x388. The chip ignores
;   reads on the data port; the only useful read is the status port, which
;   we use as a portable busy-wait delay loop.
; ============================================================================
adl_port_reg    DW      0388H                   ; index/select port (write)
adl_port_status DW      0388H                   ; status port (read, used
                                                ; only for timing delays)
adl_port_data   DW      0389H                   ; data port (write)

; ============================================================================
; 0x003D  --  OPL2 F-number table, 48 entries (each entry is one WORD)
;
;   The OPL's pitch input is a 10-bit "F-number" plus a 3-bit "block"
;   (octave). Together they pick the actual frequency in Hz. The table
;   below gives one F-number per *note within an octave* -- but the
;   driver indexes it with `(midi_note * 4) mod 48`, not just
;   `midi_note mod 12`, so there are 4 F-numbers per semitone. That
;   extra resolution is used by adl_voice_pitchbend_apply to slide
;   smoothly between semitones when the channel's pitch wheel is
;   anywhere other than centered.
;
;   The block (octave) is computed as `(midi_note * 4) / 48` and OR'd
;   into the high bits of OPL register 0xB0+v. See adl_voice_render_freq.
;
;   This table is 48 entries; the four bytes after this region are the
;   first four bytes of adl_volcurve_a, not extensions of the F-num
;   table.
; ============================================================================
adl_note_fnum_table LABEL WORD
                DW      0157H, 015CH, 0161H, 0166H, 016BH, 0171H, 0176H, 017BH
                DW      0181H, 0186H, 018CH, 0192H, 0198H, 019EH, 01A4H, 01AAH
                DW      01B0H, 01B6H, 01BDH, 01C3H, 01CAH, 01D0H, 01D7H, 01DEH
                DW      01E5H, 01ECH, 01F3H, 01FAH, 0202H, 0209H, 0211H, 0218H
                DW      0220H, 0228H, 0230H, 0238H, 0241H, 0249H, 0252H, 025AH
                DW      0263H, 026CH, 0275H, 027EH, 0287H, 0290H, 029AH, 02A4H

; ============================================================================
; 0x009D  --  volume curve A: 64-byte ascending TL ramp (0x00 .. 0x3F)
;
;   Maps a 6-bit linear "loudness index" to an OPL "total level"
;   attenuation. The curve is hand-rolled so the human-perceived
;   loudness is roughly linear in the index. Bytes 0..63 are sorted
;   ascending: index 0 -> TL 0 (loudest), index 63 -> TL 0x3F (silent).
;
;   Read in adl_voice_render_freq as `volcurve_a[voice_velocity]` to
;   scale velocity into TL units before combining with channel volume
;   and master volume.
;
;   The curve starts at 0x009D, read by adl_voice_render_freq as
;   `MOV CL, CS:[DI + 0x009D]`.
; ============================================================================
adl_volcurve_a  DB      000H, 00CH, 00DH, 00EH, 00FH, 011H, 012H, 013H
                DB      014H, 016H, 017H, 018H, 01AH, 01BH, 01CH, 01DH
                DB      01FH, 020H, 021H, 022H, 023H, 024H, 025H, 026H
                DB      027H, 028H, 029H, 02AH, 02BH, 02DH, 02DH, 02EH
                DB      02FH, 030H, 031H, 032H, 032H, 033H, 034H, 034H
                DB      035H, 036H, 036H, 037H, 038H, 038H, 039H, 03AH
                DB      03BH, 03BH, 03BH, 03CH, 03CH, 03CH, 03DH, 03DH
                DB      03DH, 03EH, 03EH, 03EH, 03EH, 03FH, 03FH, 03FH

; ============================================================================
; 0x00DD  --  volume curve B: 64-byte velocity-to-TL lookup
;
;   Similar shape to curve A but with a steeper early slope. Read in
;   adl_voice_render_volume as `volcurve_b[vol_index]` to translate
;   the effective volume index into a TL attenuation when writing
;   register 0x40+op.
;
;   The two curves differ in their use of the modulator vs. carrier
;   ops: the renderer paths in adl_voice_render_freq /
;   adl_voice_render_volume apply curve A on the velocity side and
;   curve B on the volume-index side, then combine them with the
;   per-voice TL base/max values populated from the loaded patch.
; ============================================================================
adl_volcurve_b  DB      000H, 014H, 015H, 016H, 017H, 018H, 019H, 01AH
                DB      01BH, 01CH, 01DH, 01EH, 01FH, 020H, 021H, 021H
                DB      022H, 023H, 024H, 025H, 026H, 027H, 028H, 029H
                DB      02AH, 02BH, 02CH, 02DH, 02EH, 02FH, 02FH, 030H
                DB      031H, 032H, 032H, 033H, 034H, 034H, 035H, 036H
                DB      036H, 037H, 038H, 038H, 039H, 039H, 03AH, 03AH
                DB      03BH, 03BH, 03BH, 03CH, 03CH, 03CH, 03DH, 03DH
                DB      03DH, 03EH, 03EH, 03EH, 03EH, 03FH, 03FH, 03FH

; ============================================================================
; 0x011D  --  global driver state (three scalar bytes)
;
;   adl_global_param_11d -- semantics unconfirmed. Slot 11 stores into it
;     and slot 17 (query) reads it; no other code path touches it. May
;     be tempo, transpose, or another driver-wide knob (unresolved).
;   adl_master_enable -- 0 = driver muted, 1 = active. Read in
;     adl_voice_keyon and adl_voice_render_freq as a gate; cleared by
;     slot 13.
;   adl_master_volume -- master attenuation 0..0x3F, applied multipli-
;     catively to every voice's TL by adl_voice_render_freq. Default
;     0x0F = midrange. Cleared via slot 12 or slot 13.
; ============================================================================
adl_global_param_11d DB 000H                   ; (semantics unconfirmed)
adl_master_enable    DB 001H                   ; 0 = driver muted, 1 = on
adl_master_volume    DB 00FH                   ; master TL, 0..3F

; ============================================================================
; 0x0120..0x016F  --  per-MIDI-channel state, 16 channels x 5 arrays
;
;   These are five parallel 16-byte arrays indexed by MIDI channel
;   (0..15). Each holds one byte per channel:
;
;     adl_ch_program          -- currently-selected patch number (CC0/PC)
;     adl_ch_volume           -- channel volume (CC#7), stored as CL>>1
;                                so 0..7F (7-bit MIDI) becomes 0..3F
;                                (6-bit OPL TL space). Default 0x3F = max.
;     adl_ch_pan              -- pan / expression (CC#10), 0..7F. OPL2
;                                is mono so this is currently advisory;
;                                may be consumed by the renderer in a
;                                way we haven't fully traced. Default
;                                0x40 = center.
;     adl_ch_sustain_pedal    -- sustain pedal (CC#64). When non-zero
;                                in adl_midi_note_off, note-off is
;                                deferred by setting adl_voice_sustain_held.
;     adl_ch_sustain_count    -- per-channel "owed sustain reservations"
;                                used by the sustain-pool subsystem
;                                (see adl_sustain_pool_*).
;
;   Parallel per-channel arrays (SOA), indexed like `[SI + adl_ch_program]`,
;   rather than an array of one AdlChannel struct.
; ============================================================================
adl_ch_program       DB 16 DUP(000H)           ; channel -> patch number
adl_ch_volume        DB 16 DUP(03FH)           ; channel -> volume (CC7/2)
adl_ch_pan           DB 16 DUP(040H)           ; channel -> pan (CC10)
adl_ch_sustain_pedal DB 16 DUP(000H)           ; channel -> sustain pedal
adl_ch_sustain_count DB 16 DUP(000H)           ; channel -> sustain pool debt

; ============================================================================
; 0x0170  --  per-channel pitch-bend (16 words)
;
;   Each entry is a 14-bit MIDI pitch-bend value packed into 16 bits,
;   centered at 0x2000. The renderer (adl_voice_pitchbend_apply) shifts
;   it down to an F-number delta to add/subtract from the base pitch.
; ============================================================================
adl_ch_pitchbend     DW 16 DUP(02000H)         ; channel -> bend (default
                                                ; 0x2000 = centered)

; ============================================================================
; 0x0190..0x01C6  --  per-voice state (9-entry SOA arrays, 2-byte pads)
;
;   Five parallel arrays indexed by OPL2 voice (0..8). Each is 9 bytes
;   long, followed by 2 bytes of padding. The pad slots are not addressed
;   by any code; they just shift the next array onto a slightly easier
;   address (every array starts at an offset whose low byte happens to
;   end in -0, -B, -6, etc. -- alignment for human readability rather
;   than CPU performance).
;
;     adl_voice_channel       -- which MIDI channel owns this voice
;                                (0xFF = voice is idle/free)
;     adl_voice_note          -- currently-playing MIDI note number
;                                (0xFF = voice has no live note)
;     adl_voice_velocity      -- the note's velocity (or aftertouch
;                                value); 0 if voice is idle.
;     adl_voice_sustain_held  -- 1 = "we got a note-off but the sustain
;                                pedal is held, so I'm keeping this note
;                                ringing; release me when the pedal lifts"
;     adl_voice_program       -- which patch is loaded in this voice's
;                                two OPL operators (0xFF = no patch).
;                                Lets adl_voice_keyon skip the reload
;                                step when the new note happens to want
;                                the same patch this voice already has.
;
;   Parallel per-voice arrays (SOA), not one `AdlVoice voices[9]` struct.
; ============================================================================
adl_voice_channel      DB 9 DUP(0FFH)          ; voice -> MIDI channel (FF=idle)
                       DB 2 DUP(0FFH)          ; pad_199
adl_voice_note         DB 9 DUP(0FFH)          ; voice -> MIDI note (FF=idle)
                       DB 2 DUP(0FFH)          ; pad_1a4
adl_voice_velocity     DB 9 DUP(000H)          ; voice -> velocity
                       DB 2 DUP(000H)          ; pad_1af
adl_voice_sustain_held DB 9 DUP(000H)          ; voice -> release-deferred
                       DB 2 DUP(000H)          ; pad_1ba
adl_voice_program      DB 9 DUP(0FFH)          ; voice -> loaded patch #
                       DB 2 DUP(0FFH)          ; pad_1c5

; ============================================================================
; 0x01C7..0x01DC  --  voice-allocator scratch (two 11-byte arrays)
;
;   adl_voice_lru     -- a 9-slot Least-Recently-Used queue plus 2 extra
;                        bytes of padding. Head (slot 0) is the oldest
;                        voice, tail (slot 8) is the youngest. Used by
;                        adl_voice_allocate to pick which voice to reuse
;                        when no free voice fits the bill, and by
;                        adl_voice_lru_remove to age a voice down to
;                        "youngest" after every key-on/release.
;
;                        Initial layout 00..08 means voice 0 is oldest,
;                        voice 8 is youngest -- arbitrary; the order
;                        adapts immediately as notes are played.
;
;   adl_voice_sustain_ch -- voice -> "which MIDI channel reserved this
;                        voice through CC#75 polyphony budgeting". 0xFF
;                        means "not reserved for anyone". Driven by
;                        adl_sustain_pool_resize / _reserve / _release.
; ============================================================================
adl_voice_lru          DB 000H, 001H, 002H, 003H, 004H, 005H
                       DB 006H, 007H, 008H, 009H, 00AH
adl_voice_sustain_ch   DB 11 DUP(0FFH)         ; voice -> reservation owner

; ============================================================================
; 0x01DD..0x01FD  --  per-channel polyphony budget + 1-byte pad
;
;   adl_ch_poly_max    -- per-channel "maximum simultaneous notes". A
;                         channel may not own more voices than this at
;                         once. Set indirectly via the sustain-pool
;                         routines when CC#75 is received.
;   adl_ch_poly_active -- per-channel "voices currently sounding". An
;                         even-newer note-on triggers voice-stealing
;                         when this would exceed poly_max.
; ============================================================================
adl_ch_poly_max        DB 16 DUP(000H)         ; channel -> max polyphony
adl_ch_poly_active     DB 16 DUP(000H)         ; channel -> active voices
                       DB 000H                 ; pad_1fd

; ============================================================================
; 0x01FE..0x0257  --  OPL2 operator-topology lookup tables
;
;   The OPL2's 18 operators are not addressed by a flat 0..17 index;
;   different register groups use slightly different offsets. These five
;   18-byte tables flatten that addressing irregularity into "look it up"
;   form, indexed by a linear operator number 0..17 throughout the
;   driver code:
;
;     adl_op_perm        -- a permutation of 0..17. Read by the volume
;                           renderer to walk operators in the order the
;                           OPL prefers (modulator first within each
;                           voice).
;     adl_op_iscarrier   -- 0 if this op is the modulator of its pair,
;                           1 if it is the carrier. The pattern (three
;                           modulators followed by three carriers,
;                           repeating) reflects the chip's voice-to-op
;                           layout described in the OPL2 primer above.
;     adl_op_regoff      -- maps linear op index to its OPL register
;                           offset (the offset added to 0x20, 0x40, 0x60,
;                           0x80, 0xE0 register-group bases). Note the
;                           jumps of 3 (00,01,02, then 08,09,0A, then
;                           10,11,12, ...): the chip's per-op registers
;                           leave 3-byte gaps between each group of three.
;     adl_op_voice       -- maps linear op index to its owning voice 0..8.
;                           Used by adl_opl_write_voice_feedback to find
;                           which 0xC0+ch register to write.
;     adl_voice_oppair   -- pairs of (mod_op, car_op) for each of the 9
;                           voices, packed flat: 9 x 2 = 18 entries. Used
;                           by adl_voice_apply_patch to address both
;                           operators of a voice when loading a patch.
; ============================================================================
adl_op_perm            DB 003H, 004H, 005H, 009H, 00AH, 00BH
                       DB 00FH, 010H, 011H, 000H, 001H, 002H
                       DB 006H, 007H, 008H, 00CH, 00DH, 00EH

adl_op_iscarrier       DB 000H, 000H, 000H, 001H, 001H, 001H
                       DB 000H, 000H, 000H, 001H, 001H, 001H
                       DB 000H, 000H, 000H, 001H, 001H, 001H

adl_op_regoff          DB 000H, 001H, 002H, 003H, 004H, 005H
                       DB 008H, 009H, 00AH, 00BH, 00CH, 00DH
                       DB 010H, 011H, 012H, 013H, 014H, 015H

adl_op_voice           DB 000H, 001H, 002H, 000H, 001H, 002H
                       DB 003H, 004H, 005H, 003H, 004H, 005H
                       DB 006H, 007H, 008H, 006H, 007H, 008H

adl_voice_oppair       DB 000H, 003H, 001H, 004H, 002H, 005H
                       DB 006H, 009H, 007H, 00AH, 008H, 00BH
                       DB 00CH, 00FH, 00DH, 010H, 00EH, 011H

; ============================================================================
; 0x0258 / 0x0266  --  default operator patches (14 bytes each)
;
;   Used by adl_silence_and_reset to put every operator in a known
;   sensible state after a chip reset. The 14-byte layout is what
;   adl_op_patch_load expects: each field is one of the OPL register
;   bits the chip cares about (KSL, MULT, FB/ALG, AR, SL, EG-type, DR,
;   RR, TL, AM, VIB, KSR, stereo, waveform -- in that fixed order,
;   one byte per field).
;
;   The patch labeled "mod" has its non-zero TL (byte 8 = 0x0F) so it
;   sounds at moderate level; the patch labeled "car" has TL = 0 so
;   it's at full level. Standard OPL programming convention: the
;   carrier is the audible output, the modulator's job is to bend the
;   carrier's frequency, so the modulator can sit at any TL while the
;   carrier wants TL = 0 for full output.
; ============================================================================
adl_default_patch_mod  DB 001H, 001H, 003H, 00FH, 005H, 000H, 001H
                       DB 003H, 00FH, 000H, 000H, 000H, 001H, 000H

adl_default_patch_car  DB 000H, 001H, 001H, 00FH, 007H, 000H, 002H
                       DB 004H, 000H, 000H, 000H, 001H, 000H, 000H

; ============================================================================
; 0x0274..0x036F  --  OPL register shadow (252 bytes)
;
;   18 operators x 14 bytes/op. Each 14-byte slot holds the most recent
;   value written for that operator's patch fields, so that helpers
;   like adl_opl_write_op_level can re-derive the OPL register byte by
;   reading the shadow rather than the chip (which is write-only).
;   Initialised to zero; populated by adl_op_patch_load.
; ============================================================================
adl_op_shadow          DB 252 DUP(000H)

; ============================================================================
; 0x0370  --  bank-size pseudo-instruction (a 4-byte oddity)
;
;   The four bytes here are: 0x00, 0xB8, 0x07, 0x15. They were emitted
;   by the original .ASM as a single conceptual unit: the byte 0xB8 at
;   offset 0x371 is the opcode of `MOV AX, imm16`, and the WORD at
;   0x0372..0x0373 is its immediate operand. That instruction is *never
;   executed* -- nothing branches here -- but its presence puts the
;   16-bit value at a known fixed offset, which is exactly what
;   adl_load_patch_bank reads as `CS:[adl_bank_size]` to learn how many
;   bytes to copy.
;
;   In other words: this is a single 16-bit constant (`adl_bank_size`)
;   wrapped in dead instruction bytes so that the slot's address is
;   stable.
; ============================================================================
                       DB 000H                 ; pad_370
                       DB 0B8H                 ; (MOV AX opcode; dead code)
adl_bank_size          DW 01507H               ; doubles as MOV AX immediate;
                                                ; 5383 = max bank payload bytes

; ============================================================================
; 0x0374..0x183B  --  patch bank buffer (5320 bytes)
;
;   Filled at runtime by slot 1 (adl_load_patch_bank). Holds an array of
;   AdlPatch records (each 28 bytes) keyed by program number. The game
;   uploads the bank exactly once per song, before the first note plays.
; ============================================================================
adl_bank_buf           DB 5320 DUP(000H)

; ============================================================================
; 0x183C  --  velocity-clamp LUT (62 bytes, all 0x3C)
;
;   Read by adl_voice_render_freq as `lut[clamp(vel, 0x1B, 0x58) - 0x1B]`
;   to remap velocities into a smaller range before the volume math.
;   Every byte is 0x3C in the shipping driver -- the LUT is effectively
;   a no-op constant. It exists as a per-driver tunable; future versions
;   could plug in a real curve here.
; ============================================================================
adl_vel_to_tl_lut      DB 62 DUP(03CH)

; ============================================================================
; 0x187A  --  patch staging buffer (13 bytes)
;
;   Scratch area used by adl_op_patch_stage_load to copy a default patch
;   from CS into a known location before forwarding the CS-relative
;   pointer to adl_op_patch_load. Not really "state" -- it's a temporary
;   holding buffer that gets overwritten on every patch-load call.
; ============================================================================
adl_patch_stage        DB 13 DUP(000H)

                       DB 000H                 ; pad_1887

; ============================================================================
; 0x1888..0x188E  --  OPL chip-state mirrors (4 bytes of scalars + 2 words)
;
;   The OPL2 has a handful of "global" registers that don't fit the
;   per-op layout. We mirror them in RAM so adl_op_apply_all_regs can
;   re-push them whenever a patch is reloaded.
;
;     adl_opl_notesel     -- reg 0x08 bit 6 (NOTE-SEL: shifts the
;                            key-scaling boundary between MIDI notes).
;     adl_opl_amdepth     -- reg 0xBD bit 7 (AM depth: deep/shallow).
;     adl_opl_vibdepth    -- reg 0xBD bit 6 (VIB depth: deep/shallow).
;                            Stored as a 16-bit value but only the low
;                            byte is meaningful.
;     adl_opl_rhythm      -- reg 0xBD bits 5..0 (rhythm-mode on plus
;                            BD/SD/TT/CY/HH key-ons). Unused in this
;                            driver but written by adl_opl_write_rhythm.
;     adl_wave_select_en  -- reg 0x01 bit 5 (enables the waveform-select
;                            register group at 0xE0..0xF5). Set to
;                            0x0020 by adl_silence_and_reset; without
;                            this bit the chip ignores all 0xE0 writes
;                            and only plays sine waves.
; ============================================================================
adl_opl_notesel        DB 000H                 ; reg 0x08 bit 6 mirror
adl_opl_amdepth        DB 000H                 ; reg 0xBD bit 7 mirror
adl_opl_vibdepth       DW 0000H                ; reg 0xBD bit 6 mirror (word)
adl_opl_rhythm         DB 000H                 ; reg 0xBD bits 5..0 mirror
adl_wave_select_en     DW 0000H                ; reg 0x01 bit 5 mirror;
                                                ; set to 0x20 by reset

                       DB 3 DUP(000H)          ; pad_188f

; ============================================================================
; 0x1892..0x1920  --  per-voice OPL working tables (six 11-entry arrays)
;
;   Seven parallel arrays indexed by voice (0..8), padded to 11 slots.
;   Six are 16-bit (WORD) and one is 8-bit (BYTE). They cache pre-computed
;   values derived from the currently-loaded patch, so the per-note
;   render path doesn't have to redo divisions every key-on.
;
;     adl_voice_mod_tl_base   -- modulator TL "base" (the patch byte at
;                                offset 0 of the AdlPatch record)
;     adl_voice_mod_tl_max    -- 0x3F minus the modulator KSL byte
;     adl_voice_mod_tl_step   -- (mod_tl_max / 15), the per-velocity step
;     adl_voice_car_tl_base   -- carrier TL base (patch byte at offset 0xD)
;     adl_voice_car_tl_max    -- 0x3F minus the carrier KSL byte
;     adl_voice_additive      -- 0 = modulator-only audible; 1 = both ops
;                                audible (additive synthesis)
;     adl_voice_car_tl_step   -- (car_tl_max / 15)
;
;   The "step" tables let the renderer scale velocity into the TL range
;   with multiplication only (no division at render time): the actual
;   formula is `TL = base + velocity_index * step`, computed by
;   adl_voice_render_volume.
; ============================================================================
adl_voice_mod_tl_base  DW 11 DUP(0000H)        ; voice -> modulator TL base
adl_voice_mod_tl_max   DW 11 DUP(0000H)        ; voice -> 0x3F - mod KSL
adl_voice_mod_tl_step  DW 11 DUP(0000H)        ; voice -> mod_tl_max / 15
adl_voice_car_tl_base  DW 11 DUP(0000H)        ; voice -> carrier TL base
adl_voice_car_tl_max   DW 11 DUP(0000H)        ; voice -> 0x3F - car KSL
adl_voice_additive     DB 11 DUP(000H)         ; voice -> additive flag
adl_voice_car_tl_step  DW 11 DUP(0000H)        ; voice -> car_tl_max / 15

; ============================================================================
; 0x1921  --  dispatch function-pointer table (18 near pointers)
;
;   The dispatch trampoline below indexes this table by `BP * 2`. Each
;   entry is a 16-bit near pointer to a slot handler. Six slots (3, 6,
;   9, 14, 15, 16) point at adl_slot_unused_ret -- a one-byte RET stub
;   -- because the DUDE family reserves those slot indices but this
;   driver doesn't implement them.
;
;   The labels in the DW directives are forward references; TASM
;   resolves them on its second pass once the function bodies have
;   been laid out below.
; ============================================================================
adl_func_table  LABEL   WORD
                DW      adl_get_info                 ; slot  0  driver descriptor
                DW      adl_load_patch_bank          ; slot  1  upload patch bank
                DW      adl_reset_voices             ; slot  2  silence + reset
                DW      adl_slot_unused_ret          ; slot  3  (reserved)
                DW      adl_midi_note_off            ; slot  4  MIDI note-off
                DW      adl_midi_note                ; slot  5  MIDI note (vel=0=off)
                DW      adl_slot_unused_ret          ; slot  6  (reserved)
                DW      adl_midi_control_change      ; slot  7  MIDI CC
                DW      adl_midi_program_change      ; slot  8  MIDI prog change
                DW      adl_slot_unused_ret          ; slot  9  (reserved)
                DW      adl_midi_pitch_bend          ; slot 10  MIDI pitch bend
                DW      adl_set_global_param_11d     ; slot 11  set/query 0x011D
                DW      adl_set_master_volume        ; slot 12  master volume
                DW      adl_set_master_enable        ; slot 13  master enable
                DW      adl_slot_unused_ret          ; slot 14  (reserved)
                DW      adl_slot_unused_ret          ; slot 15  (reserved)
                DW      adl_slot_unused_ret          ; slot 16  (reserved)
                DW      adl_query_state              ; slot 17  query mirror

; ============================================================================
; 0x1945  --  adl_dispatch  --  the trampoline
;
;   This is the ONLY entry point the game ever calls. The game does:
;
;       MOV  BP, <slot index>
;       <set up AL/CH/CL/etc per the slot's convention>
;       CALL FAR adl_seg:adl_dispatch
;
;   We:
;     - Save the slot index (the game expects BP preserved across the call)
;     - Convert slot index to byte offset by shifting left 1
;     - Look up the slot's handler pointer in adl_func_table
;     - Call the handler as a near function
;     - Restore BP and return far to the game
;
;   The trampoline itself is 12 bytes: PUSH (1) + SHL (2) + MOV (5) +
;   CALL (2) + POP (1) + RETF (1).
; ============================================================================
adl_dispatch    PROC    NEAR
                PUSH    BP                      ; save game's slot index
                SHL     BP, 1                   ; slot * 2 = byte offset
                MOV     BP, CS:[BP + adl_func_table]
                CALL    BP                      ; near call to slot handler
                POP     BP                      ; restore for the game
                RETF                            ; far return to game
adl_dispatch    ENDP

; ============================================================================
; 0x1951  --  adl_slot_unused_ret
;
;   A single-byte RET (opcode 0xC3). Shared by six "reserved but
;   unimplemented" slots (3, 6, 9, 14, 15, 16) in the function-pointer
;   table above. Calling any of them is a fast no-op.
; ============================================================================
adl_slot_unused_ret PROC NEAR
                RET
adl_slot_unused_ret ENDP

; ============================================================================
; ============================================================================
; FUNCTION BODIES below this line
;
; Each function gets a header block describing its role, the registers it
; consumes and produces, what it modifies, and any quirks worth flagging.
; ============================================================================
; ============================================================================
; ----------------------------------------------------------------------------
; 0x1952  --  adl_midi_note_off
;
;   The MIDI "note off" message. Tells the driver "stop playing this note
;   on this channel". The driver walks all 9 OPL voices looking for any
;   voice currently sounding the (channel, note) pair, and either:
;
;     - if the channel's sustain pedal is held, marks the voice as
;       "release deferred" so it'll keep ringing and only get released
;       when the pedal lifts (see adl_cc_sustain_pedal); or
;     - if no pedal, calls adl_voice_release to silence the voice now.
;
;   Multiple voices may match (chorus / unison patches); we keep looking
;   after the first match. The function is also called internally from
;   adl_midi_note when a "note on" with velocity 0 is received (per
;   MIDI's running-status convention).
;
;   Type:        Slot handler
;   Category:    MIDI dispatch
;   Dispatch:    Slot 4 (called as: BP=4, AL=channel, CH=note)
;   Callers:     Game (via dispatch), adl_midi_note (slot 5 fallthrough)
;   Callees:     adl_voice_release
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
;       - else: adl_voice_release(v) -- which writes the OPL to release
;         the envelope and clears voice_note[v] / voice_program[v] /
;         voice_velocity[v].
; ----------------------------------------------------------------------------
adl_midi_note_off PROC    NEAR
                PUSH    BX
                PUSH    SI
                XOR     BX, BX
                JMP     SHORT noteoff_test
noteoff_body:   CMP     CS:[BX + adl_voice_channel], AL
                JNE     SHORT noteoff_next
                CMP     CS:[BX + adl_voice_note], CH
                JNE     SHORT noteoff_next
                MOV     SI, AX
                AND     SI, 00FFH
                CMP     BYTE PTR CS:[SI + adl_ch_sustain_pedal], 0
                JE      SHORT noteoff_release
                MOV     BYTE PTR CS:[BX + adl_voice_sustain_held], 1
                JMP     SHORT noteoff_next
noteoff_release: CALL   adl_voice_release
noteoff_next:   INC     BX
noteoff_test:   CMP     BX, 9
                JB      SHORT noteoff_body
                POP     SI
                POP     BX
                RET
adl_midi_note_off ENDP
; ----------------------------------------------------------------------------
; 0x1988  --  adl_midi_note
;
;   The MIDI "note on" message. By convention a note-on with velocity 0
;   means the same thing as a note-off, so this function handles both:
;
;     1. If CL (velocity) == 0, fall through to adl_midi_note_off and
;        return.
;     2. Otherwise, clamp the note to the playable range [0x0C, 0x6B]
;        and drop the request if it's out of range.
;     3. Halve the velocity (MIDI's 7-bit velocity becomes a 6-bit OPL
;        attenuation step).
;     4. Look for a voice already playing (this channel, this note).
;        If found, restart it cleanly: release then key-on with the
;        new velocity. This gives consistent attack on rapid retriggers.
;     5. Otherwise allocate a new voice via adl_voice_allocate. If no
;        voice is available (allocator returned 0xFF), drop the request
;        silently.
;     6. Key on the chosen voice via adl_voice_keyon.
;
;   Type:        Slot handler
;   Category:    MIDI dispatch
;   Dispatch:    Slot 5 (called as: BP=5, AL=channel, CH=note, CL=velocity)
;   Callers:     Game (via dispatch)
;   Callees:     adl_midi_note_off, adl_voice_release, adl_voice_keyon,
;                adl_voice_allocate
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
;     - Writes OPL registers via the renderer chain for key-on.
; ----------------------------------------------------------------------------
adl_midi_note   PROC    NEAR
                PUSH    BX
                PUSH    SI
                OR      CL, CL
                JNZ     SHORT note_have_vel
                CALL    adl_midi_note_off
                JMP     SHORT note_end
note_have_vel:  CMP     CH, 0CH
                JB      SHORT note_oor
                CMP     CH, 6BH
                JBE     SHORT note_in_range
note_oor:       JMP     SHORT note_end
note_in_range:  SHR     CL, 1
                XOR     BX, BX
                JMP     SHORT note_scan_test
note_scan_body: CMP     CS:[BX + adl_voice_channel], AL
                JNE     SHORT note_scan_next
                CMP     CS:[BX + adl_voice_note], CH
                JNE     SHORT note_scan_next
                CALL    adl_voice_release
                CALL    adl_voice_keyon
                JMP     SHORT note_end
note_scan_next: INC     BX
note_scan_test: CMP     BX, 9
                JB      SHORT note_scan_body
                CALL    adl_voice_allocate
                CMP     BL, 0FFH
                JE      SHORT note_end
                CALL    adl_voice_keyon
note_end:       POP     SI
                POP     BX
                RET
adl_midi_note   ENDP
; ----------------------------------------------------------------------------
; 0x19CF  --  adl_midi_control_change
;
;   The MIDI "control change" message. CH selects which controller the
;   game is changing; we dispatch on CH to a per-controller helper:
;
;     CC#7   (main volume)        -> adl_cc_main_volume
;     CC#10  (pan / expression)   -> adl_cc_pan
;     CC#64  (sustain pedal)      -> adl_cc_sustain_pedal
;     CC#75  (polyphony budget)   -> adl_sustain_pool_resize
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
;   Callees:     adl_cc_main_volume, adl_cc_pan, adl_cc_sustain_pedal,
;                adl_sustain_pool_resize, adl_voice_release
;
;   Inputs:
;     AL  --  MIDI channel (0..15)
;     CH  --  MIDI controller number (0..127)
;     CL  --  controller value (0..127)
;
;   Outputs:     none
; ----------------------------------------------------------------------------
adl_midi_control_change PROC NEAR
                PUSH    BX
                CMP     CH, 07H                 ; CC#7  main volume
                JNE     SHORT cc_not_vol
                CALL    adl_cc_main_volume
                JMP     SHORT cc_end
cc_not_vol:     CMP     CH, 0AH                 ; CC#10 pan
                JNE     SHORT cc_not_pan
                CALL    adl_cc_pan
                JMP     SHORT cc_end
cc_not_pan:     CMP     CH, 40H                 ; CC#64 sustain pedal
                JNE     SHORT cc_not_sus
                CALL    adl_cc_sustain_pedal
                JMP     SHORT cc_end
cc_not_sus:     CMP     CH, 4BH                 ; CC#75 polyphony budget
                JNE     SHORT cc_not_pool
                CALL    adl_sustain_pool_resize
                JMP     SHORT cc_end
cc_not_pool:    CMP     CH, 7BH                 ; CC#123 all-notes-off
                JNE     SHORT cc_end
                XOR     BX, BX
                JMP     SHORT cc_scan_test
cc_scan_body:   CMP     CS:[BX + adl_voice_channel], AL
                JNE     SHORT cc_scan_next
                CMP     BYTE PTR CS:[BX + adl_voice_note], 0FFH
                JE      SHORT cc_scan_next
                CALL    adl_voice_release
cc_scan_next:   INC     BX
cc_scan_test:   CMP     BX, 9
                JB      SHORT cc_scan_body
cc_end:         POP     BX
                RET
adl_midi_control_change ENDP
; ----------------------------------------------------------------------------
; 0x1A1B  --  adl_midi_program_change
;
;   The game-side equivalent of MIDI's "Program Change" message: tells
;   the driver "from now on, channel <ch> should play notes using
;   instrument <prog>". The driver doesn't reprogram any voice
;   *immediately*; it just caches the new program number. The next time
;   a note is played on this channel (slot 5), adl_voice_keyon will see
;   that the requested patch differs from the patch currently loaded in
;   the assigned voice and reload it from the bank then.
;
;   The lazy approach (cache, don't reload) is important because songs
;   typically issue program-change messages between notes, not during
;   them; reprogramming an idle OPL voice would be wasted work. The
;   next note-on pays the reload cost only if the patch actually differs.
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
;     adl_ch_program[channel] <- patch_number
; ----------------------------------------------------------------------------
adl_midi_program_change PROC NEAR
                PUSH    SI
                MOV     SI, AX
                AND     SI, 00FFH
                MOV     CS:[SI + adl_ch_program], CL
                POP     SI
                RET
adl_midi_program_change ENDP

; ----------------------------------------------------------------------------
; 0x1A29  --  adl_midi_pitch_bend
;
;   The MIDI "pitch wheel" message. A 14-bit value centered at 0x2000
;   (no bend); below center bends down, above center bends up. The
;   game packs the 14 bits across two MIDI data bytes that arrive in
;   CL (LSB, 7 bits) and CH (MSB, 7 bits), and we have to repack them
;   into a clean 16-bit word stored at adl_ch_pitchbend[channel].
;
;   After the store, we walk every voice currently playing on the
;   affected channel and call adl_voice_render_freq to recompute the
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
;   Callees:     adl_voice_render_freq (per live voice on channel)
;
;   Inputs:
;     AL  --  MIDI channel (0..15)
;     CX  --  14-bit bend packed as (CH = MSB, CL = LSB)
;
;   Outputs:     none
;
;   Side effects:
;     - adl_ch_pitchbend[channel] <- repacked CX
;     - For every voice playing on this channel: writes OPL regs
;       0xA0+v and 0xB0+v with the new F-number.
; ----------------------------------------------------------------------------
adl_midi_pitch_bend PROC NEAR
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
                MOV     CS:[BX + adl_ch_pitchbend], CX
                XOR     BX, BX
                JMP     SHORT pb_scan_test
pb_scan_body:   CMP     CS:[BX + adl_voice_channel], AL
                JNE     SHORT pb_scan_next
                CMP     BYTE PTR CS:[BX + adl_voice_note], 0FFH
                JE      SHORT pb_scan_next
                MOV     CL, CS:[BX + adl_voice_note]
                MOV     DX, 0001H
                CALL    adl_voice_render_freq
pb_scan_next:   INC     BX
pb_scan_test:   CMP     BX, 9
                JB      SHORT pb_scan_body
                POP     DX
                POP     CX
                POP     BX
                RET
adl_midi_pitch_bend ENDP

; ----------------------------------------------------------------------------
; 0x1A68  --  adl_set_master_enable
;
;   The driver's "master enable" gate. When 0, adl_voice_keyon skips the
;   patch-reload step and the chip stays silent on note-ons; when 1, the
;   driver behaves normally. The caller passes 0xFF in CL to query the
;   current value without changing it (standard DUDE setter convention).
;
;   When the value changes, we also refresh every live voice via
;   adl_set_master_volume so the master-volume gain math sees the new
;   state. Slightly unusual: the function also clobbers master_volume
;   along the way (it restores it from the called function's
;   return value), which is why the implementation is more elaborate
;   than a simple store.
;
;   Type:        Slot handler
;   Category:    Global state
;   Dispatch:    Slot 13 (called as: BP=13, CL=value or 0xFF=query)
;   Callers:     Game (via dispatch)
;   Callees:     adl_set_master_volume
;
;   Inputs:
;     CL  --  new master-enable value, or 0xFF to query without change
;
;   Outputs:
;     AX  --  previous master-enable value (high byte 0)
;
;   Side effects (when CL != 0xFF):
;     - adl_master_enable <- CL
;     - adl_master_volume gets temporarily clobbered then restored
;     - every live voice refreshed via adl_voice_render_freq
; ----------------------------------------------------------------------------
adl_set_master_enable PROC NEAR
                MOV     AL, CS:adl_master_enable
                XOR     AH, AH
                CMP     CL, 0FFH
                JE      SHORT sme_end
                PUSH    CX
                PUSH    AX
                MOV     CS:adl_master_enable, CL
                OR      CL, CL
                JZ      SHORT sme_skip_load
                MOV     CL, CS:adl_master_volume
sme_skip_load:  CALL    adl_set_master_volume
                MOV     CS:adl_master_volume, AL
                POP     AX
                POP     CX
sme_end:        RET
adl_set_master_enable ENDP

; ----------------------------------------------------------------------------
; 0x1A8D  --  adl_set_master_volume
;
;   Sets the driver's master volume (an OPL TL attenuation, 0..0x3F).
;   Like adl_set_master_enable, the convention is "CL = 0xFF means
;   query without changing"; otherwise CL is the new value.
;
;   When the value changes, refresh every live voice's OPL state so the
;   new master volume takes audible effect immediately (rather than
;   waiting for the next note-on).
;
;   Type:        Slot handler
;   Category:    Global state
;   Dispatch:    Slot 12 (called as: BP=12, CL=value or 0xFF=query)
;   Callers:     Game (via dispatch), adl_set_master_enable, slot-1 load
;   Callees:     adl_voice_render_freq (per live voice)
;
;   Inputs:
;     CL  --  new master volume (0..0x3F), or 0xFF to query
;
;   Outputs:
;     AX  --  previous master volume (high byte 0)
;
;   Side effects (when CL != 0xFF):
;     - adl_master_volume <- CL
;     - every voice with a live note: writes OPL regs 0xA0/0xB0 with
;       new pitch+volume.
; ----------------------------------------------------------------------------
adl_set_master_volume PROC NEAR
                PUSH    BX
                PUSH    DX
                MOV     AL, CS:adl_master_volume
                XOR     AH, AH
                CMP     CL, 0FFH
                JE      SHORT smv_end
                MOV     CS:adl_master_volume, CL
                XOR     BX, BX
                JMP     SHORT smv_scan_test
smv_scan_body:  CMP     BYTE PTR CS:[BX + adl_voice_note], 0FFH
                JE      SHORT smv_scan_next
                MOV     CL, CS:[BX + adl_voice_note]
                MOV     DX, 0001H
                CALL    adl_voice_render_freq
smv_scan_next:  INC     BX
smv_scan_test:  CMP     BX, 9
                JB      SHORT smv_scan_body
smv_end:        POP     DX
                POP     BX
                RET
adl_set_master_volume ENDP

; ----------------------------------------------------------------------------
; 0x1ABF  --  adl_set_global_param_11d
;
;   Pure get/set on the byte at adl_global_param_11d. CL = 0xFF means
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
;
;   Notes:
;     The semantics of adl_global_param_11d are unresolved (possibly
;     tempo, transpose, or another driver-wide knob).
; ----------------------------------------------------------------------------
adl_set_global_param_11d PROC NEAR
                MOV     AL, CS:adl_global_param_11d
                XOR     AH, AH
                CMP     CL, 0FFH
                JE      SHORT sgp_end
                MOV     CS:adl_global_param_11d, CL
sgp_end:        RET
adl_set_global_param_11d ENDP

; ----------------------------------------------------------------------------
; 0x1AD0  --  adl_reset_voices
;
;   A two-instruction wrapper that just calls adl_silence_and_reset.
;   Exists as a separate slot entry because the DUDE ABI requires a
;   dedicated "stop / reset" slot at index 2. The work happens in
;   adl_silence_and_reset.
;
;   Type:        Slot handler
;   Category:    Global state
;   Dispatch:    Slot 2 (called as: BP=2; no other arguments)
;   Callers:     Game (via dispatch)
;   Callees:     adl_silence_and_reset
;
;   Inputs:      none
;   Outputs:     none
; ----------------------------------------------------------------------------
adl_reset_voices PROC NEAR
                CALL    adl_silence_and_reset
                RET
adl_reset_voices ENDP
; ----------------------------------------------------------------------------
; 0x1AD4  --  adl_voice_allocate
;
;   Picks which of the 9 OPL voices should receive a new note. Three-phase
;   search, increasingly aggressive:
;
;     Phase 1 (best case)
;       Walk voices in LRU order. Pick the first idle voice (note=0xFF)
;       that already has the right patch loaded for the requested
;       channel. Saves a patch reload.
;
;     Phase 2 (still cheap)
;       Walk voices in LRU order again. Pick any idle voice (note=0xFF),
;       even if it has a different patch loaded. The caller will reload.
;
;     Phase 3 (expensive: voice stealing)
;       Find the MIDI channel that's most over its polyphony budget --
;       i.e. the channel with the largest `poly_active - poly_max`. Then
;       walk voices in LRU order looking for one owned by that channel,
;       silence it, and reuse it. If no channel is over budget, steal
;       from the caller's own channel.
;
;     If even phase 3 fails (very rare; only if BX never matched a voice
;     owned by the worst channel), return 0xFFFF to signal failure.
;
;   The "LRU order" is the adl_voice_lru array: head = oldest voice,
;   tail = youngest. Picking from the head naturally steals from
;   long-silent voices first.
;
;   Type:        Subroutine
;   Category:    Voice management
;   Callers:     adl_midi_note (slot 5)
;   Callees:     adl_voice_release (only in the voice-steal path)
;
;   Inputs:
;     AL  --  MIDI channel that wants the new voice (0..15)
;
;   Outputs:
;     BX  --  chosen voice index 0..8, or 0xFFFF on failure
;
;   Side effects:
;     adl_voice_channel[chosen] <- AL  (binds the voice to the channel)
;     Possibly releases an existing note on a different voice if Phase 3
;     fires.
; ----------------------------------------------------------------------------
adl_voice_allocate PROC NEAR
                PUSH    CX
                PUSH    DX
                PUSH    SI
                MOV     DH, 0
                MOV     AH, 0
                MOV     SI, AX                  ; SI = channel
                ; ---- Phase 1: idle voice with matching patch ----
                XOR     BX, BX
                MOV     DL, CS:[SI + adl_ch_program]
                XOR     SI, SI                  ; LRU iterator
                JMP     SHORT va_p1_test
va_p1_body:     MOV     BL, CS:[SI + adl_voice_lru]
                CMP     BYTE PTR CS:[BX + adl_voice_note], 0FFH
                JNE     SHORT va_p1_next
                CMP     CS:[BX + adl_voice_program], DL
                JNE     SHORT va_p1_next
                MOV     CS:[BX + adl_voice_channel], AL
                JMP     SHORT va_end
va_p1_next:     INC     SI
va_p1_test:     CMP     SI, 9
                JB      SHORT va_p1_body
                ; ---- Phase 2: any idle voice ----
                XOR     SI, SI
                XOR     BX, BX
                JMP     SHORT va_p2_test
va_p2_body:     MOV     BL, CS:[SI + adl_voice_lru]
                CMP     BYTE PTR CS:[BX + adl_voice_note], 0FFH
                JNE     SHORT va_p2_next
                MOV     CS:[BX + adl_voice_channel], AL
                JMP     SHORT va_end
va_p2_next:     INC     SI
va_p2_test:     CMP     SI, 9
                JB      SHORT va_p2_body
                ; ---- Phase 3a: find worst (poly_active - poly_max) ----
                XOR     SI, SI
                XOR     BX, BX                  ; BL = best_over so far
                XOR     CX, CX
                XOR     DX, DX                  ; DX = worst_channel
                JMP     SHORT va_p3_test
va_p3_body:     MOV     CL, CS:[SI + adl_ch_poly_active]
                CMP     CL, CS:[SI + adl_ch_poly_max]
                JBE     SHORT va_p3_next
                SUB     CL, CS:[SI + adl_ch_poly_max]
                CMP     BL, CL
                JAE     SHORT va_p3_next
                MOV     BL, CL
                MOV     DX, SI
va_p3_next:     INC     SI
va_p3_test:     CMP     SI, 10H
                JB      SHORT va_p3_body
                ; ---- Phase 3b: steal a voice from worst_channel ----
                MOV     CL, AL
                CMP     BL, 0
                JBE     SHORT va_p3b_use_caller
                MOV     CL, DL
va_p3b_use_caller: XOR  SI, SI
                XOR     BX, BX
                JMP     SHORT va_p3b_test
va_p3b_body:    MOV     BL, CS:[SI + adl_voice_lru]
                CMP     CS:[BX + adl_voice_channel], CL
                JNE     SHORT va_p3b_next
                CALL    adl_voice_release
                MOV     CS:[BX + adl_voice_channel], AL
                JMP     SHORT va_end
va_p3b_next:    INC     SI
va_p3b_test:    CMP     SI, 9
                JB      SHORT va_p3b_body
                MOV     BX, 0FFFFH
va_end:         POP     SI
                POP     DX
                POP     CX
                RET
adl_voice_allocate ENDP
; ----------------------------------------------------------------------------
; 0x1B84  --  adl_sustain_pool_resize
;
;   Handler for MIDI controller CC#75 ("Sound Controller 6 / Decay"
;   in the GM spec, but repurposed by Dynamix as a per-channel
;   polyphony budget). The caller asks for `CL` voices to be reserved
;   for channel AL.
;
;   Implementation:
;     1. Walk the 9 voices, counting how many are already marked
;        reserved-for-AL in adl_voice_sustain_ch.
;     2. Add the channel's "owed reservations" counter
;        (adl_ch_sustain_count[ch]) to that count.
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
;   Callers:     adl_midi_control_change (CC#75 branch)
;   Callees:     adl_sustain_pool_reserve, adl_sustain_pool_release,
;                adl_sustain_pool_drain
;
;   Inputs:
;     AL  --  MIDI channel (0..15)
;     CL  --  target reservation count
;
;   Outputs:     none
;   Touches:     caller registers preserved (saves SI, CX, DX)
;
;   Side effects:
;     adl_voice_sustain_ch, adl_ch_sustain_count, adl_ch_poly_max all
;     updated to reflect the new budget. May release active notes in
;     the shrink path.
; ----------------------------------------------------------------------------
adl_sustain_pool_resize PROC NEAR
                PUSH    SI
                PUSH    CX
                PUSH    DX
                XOR     SI, SI
                XOR     DX, DX
                JMP     SHORT spr_count_test
spr_count_body: CMP     CS:[SI + adl_voice_sustain_ch], AL
                JNE     SHORT spr_count_next
                INC     DL
spr_count_next: INC     SI
spr_count_test: CMP     SI, 9
                JB      SHORT spr_count_body
                MOV     SI, AX
                AND     SI, 00FFH
                ADD     DL, CS:[SI + adl_ch_sustain_count]
                CMP     DL, CL
                JE      SHORT spr_end
                CMP     DL, CL
                JAE     SHORT spr_shrink
                SUB     CL, DL
                CALL    adl_sustain_pool_reserve
                JMP     SHORT spr_end
spr_shrink:     SUB     DL, CL
                MOV     CL, DL
                CALL    adl_sustain_pool_release
                CALL    adl_sustain_pool_drain
spr_end:        POP     DX
                POP     CX
                POP     SI
                RET
adl_sustain_pool_resize ENDP
; ----------------------------------------------------------------------------
; 0x1BC4  --  adl_sustain_pool_drain
;
;   After a sustain-pool shrink, some voice reservations may have come
;   free (their owner channel no longer needs them). This function
;   "drains" those free slots: any channel that had outstanding owed
;   reservations (adl_ch_sustain_count[ch] > 0) gets first claim on
;   the freed slots.
;
;   Algorithm:
;     1. Count free reservation slots (voice_sustain_ch[v] == 0xFF)
;        into CL.
;     2. If CL == 0, nothing to do; return.
;     3. Walk channels 0..15. For each whose adl_ch_sustain_count > 0:
;          - If the channel's debt is smaller than our remaining free
;            slots, fully satisfy it and zero out the counter.
;          - Otherwise satisfy it partially with all our remaining
;            slots and return early.
;        Each satisfied portion is forwarded to _reserve() so the
;        voices actually get bound to the channel.
;
;   Type:        Subroutine
;   Category:    Sustain pool
;   Callers:     adl_sustain_pool_resize
;   Callees:     adl_sustain_pool_reserve
;
;   Inputs:      (reads driver state only; no register args)
;   Outputs:     none
;
;   Side effects:
;     Bound voices and their owning channels updated. May change
;     adl_voice_sustain_ch and adl_ch_sustain_count for multiple
;     channels.
; ----------------------------------------------------------------------------
adl_sustain_pool_drain PROC NEAR
                PUSH    AX
                PUSH    CX
                PUSH    SI
                XOR     CL, CL                  ; CL = free sustain slots
                XOR     SI, SI
                JMP     SHORT spd_count_test
spd_count_body: CMP     BYTE PTR CS:[SI + adl_voice_sustain_ch], 0FFH
                JNE     SHORT spd_count_next
                INC     CL
spd_count_next: INC     SI
spd_count_test: CMP     SI, 9
                JB      SHORT spd_count_body
                OR      CL, CL
                JZ      SHORT spd_end
                XOR     SI, SI
                JMP     SHORT spd_loop_test
spd_loop_body:  MOV     CH, CS:[SI + adl_ch_sustain_count]
                CMP     CH, 0
                JBE     SHORT spd_next_ch
                CMP     CH, CL
                JAE     SHORT spd_partial
                ; channel debt smaller than remaining drain: take all of it
                SUB     CL, CH
                PUSH    CX
                MOV     CL, CH
                MOV     BYTE PTR CS:[SI + adl_ch_sustain_count], 0
                MOV     AX, SI
                CALL    adl_sustain_pool_reserve
                POP     CX
                JMP     SHORT spd_next_ch
spd_partial:    SUB     CH, CL
                MOV     CS:[SI + adl_ch_sustain_count], CH
                MOV     AX, SI
                CALL    adl_sustain_pool_reserve
                JMP     SHORT spd_end
spd_next_ch:    INC     SI
spd_loop_test:  CMP     SI, 10H
                JB      SHORT spd_loop_body
spd_end:        POP     SI
                POP     CX
                POP     AX
                RET
adl_sustain_pool_drain ENDP
; ----------------------------------------------------------------------------
; 0x1C1E  --  adl_sustain_pool_reserve
;
;   Claims `CL` voice slots for channel AL. Walks voices, picks any
;   that are currently free for reservation (voice_sustain_ch == 0xFF),
;   releases any note they happen to be playing (since we're taking
;   them over), and marks them as reserved for AL.
;
;   If fewer than CL voices are available to reserve, the remaining
;   shortfall is added to adl_ch_sustain_count[AL] -- the "owed
;   reservations" counter that gets paid down by future _drain() calls.
;
;   Type:        Subroutine
;   Category:    Sustain pool
;   Callers:     adl_sustain_pool_resize, adl_sustain_pool_drain
;   Callees:     adl_voice_release
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
adl_sustain_pool_reserve PROC NEAR
                PUSH    CX
                PUSH    BX
                PUSH    SI
                XOR     BX, BX
                JMP     SHORT spres_loop_test
spres_loop_body: CMP    BYTE PTR CS:[BX + adl_voice_sustain_ch], 0FFH
                JNE     SHORT spres_next_voice
                CMP     BYTE PTR CS:[BX + adl_voice_note], 0FFH
                JE      SHORT spres_assign
                CALL    adl_voice_release
spres_assign:   MOV     CS:[BX + adl_voice_sustain_ch], AL
                XOR     AH, AH
                MOV     SI, AX
                INC     BYTE PTR CS:[SI + adl_ch_poly_max]
                DEC     CL
spres_next_voice: INC   BX
spres_loop_test: CMP    BX, 9
                JAE     SHORT spres_done
                CMP     CL, 0
                JA      SHORT spres_loop_body
spres_done:     MOV     SI, AX
                AND     SI, 00FFH
                ADD     CS:[SI + adl_ch_sustain_count], CL
                POP     SI
                POP     BX
                POP     CX
                RET
adl_sustain_pool_reserve ENDP
; ----------------------------------------------------------------------------
; 0x1C62  --  adl_sustain_pool_release
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
;        For each, call adl_voice_release to silence the note, then
;        free the reservation.
;
;   Type:        Subroutine
;   Category:    Sustain pool
;   Callers:     adl_sustain_pool_resize
;   Callees:     adl_voice_release
;
;   Inputs:
;     AL  --  channel relinquishing reservations
;     CL  --  number of slots to release
;
;   Outputs:     none
; ----------------------------------------------------------------------------
adl_sustain_pool_release PROC NEAR
                PUSH    BX
                PUSH    CX
                PUSH    SI
                MOV     SI, AX
                AND     SI, 00FFH
                CMP     CS:[SI + adl_ch_sustain_count], CL
                JB      SHORT sprl_partial
                SUB     CS:[SI + adl_ch_sustain_count], CL
                JMP     SHORT sprl_end
sprl_partial:   SUB     CL, CS:[SI + adl_ch_sustain_count]
                MOV     BYTE PTR CS:[SI + adl_ch_sustain_count], 0
                XOR     BX, BX
                JMP     SHORT sprl_p1_test
sprl_p1_body:   CMP     CS:[BX + adl_voice_sustain_ch], AL
                JNE     SHORT sprl_p1_next
                CMP     BYTE PTR CS:[BX + adl_voice_note], 0FFH
                JNE     SHORT sprl_p1_next
                MOV     BYTE PTR CS:[BX + adl_voice_sustain_ch], 0FFH
                XOR     AH, AH
                MOV     SI, AX
                DEC     BYTE PTR CS:[SI + adl_ch_poly_max]
                DEC     CL
                JZ      SHORT sprl_end
sprl_p1_next:   INC     BX
sprl_p1_test:   CMP     BX, 9
                JB      SHORT sprl_p1_body
                XOR     BX, BX
                JMP     SHORT sprl_p2_test
sprl_p2_body:   CMP     CS:[BX + adl_voice_sustain_ch], AL
                JNE     SHORT sprl_p2_next
                CALL    adl_voice_release
                MOV     BYTE PTR CS:[BX + adl_voice_sustain_ch], 0FFH
                XOR     AH, AH
                MOV     SI, AX
                DEC     BYTE PTR CS:[SI + adl_ch_poly_max]
                DEC     CL
                JZ      SHORT sprl_end
sprl_p2_next:   INC     BX
sprl_p2_test:   CMP     BX, 9
                JB      SHORT sprl_p2_body
sprl_end:       POP     SI
                POP     CX
                POP     BX
                RET
adl_sustain_pool_release ENDP
; ----------------------------------------------------------------------------
; 0x1CDB  --  adl_cc_main_volume
;
;   Handler for MIDI CC#7 ("Main Volume"). The MIDI value (0..127) is
;   first halved into the OPL TL range (0..63), then stored in
;   adl_ch_volume[channel]. Then every voice playing on this channel
;   is refreshed via adl_voice_render_freq so the new volume takes
;   effect.
;
;   Type:        Subroutine
;   Category:    MIDI CC handler
;   Callers:     adl_midi_control_change (CC#7 branch)
;   Callees:     adl_voice_render_freq
;
;   Inputs:
;     AL  --  channel (0..15)
;     CL  --  volume (0..127)
;
;   Outputs:     none
;
;   Side effects:
;     adl_ch_volume[ch] <- CL >> 1
;     Live voices on this channel refreshed (OPL 0xA0+v, 0xB0+v writes).
; ----------------------------------------------------------------------------
adl_cc_main_volume PROC NEAR
                PUSH    BX
                PUSH    CX
                PUSH    DX
                PUSH    SI
                SHR     CL, 1
                MOV     SI, AX
                AND     SI, 00FFH
                MOV     CS:[SI + adl_ch_volume], CL
                XOR     CX, CX
                MOV     DX, 0001H
                XOR     BX, BX
                JMP     SHORT ccv_test
ccv_body:       CMP     CS:[BX + adl_voice_channel], AL
                JNE     SHORT ccv_next
                MOV     CL, CS:[BX + adl_voice_note]
                CMP     CL, 0FFH
                JE      SHORT ccv_next
                CALL    adl_voice_render_freq
ccv_next:       INC     BX
ccv_test:       CMP     BX, 9
                JB      SHORT ccv_body
                POP     SI
                POP     DX
                POP     CX
                POP     BX
                RET
adl_cc_main_volume ENDP

; ----------------------------------------------------------------------------
; 0x1D14  --  adl_cc_pan
;
;   Handler for MIDI CC#10 ("Pan"). Stores the raw value (0..127) in
;   adl_ch_pan[channel] and refreshes live voices. OPL2 is mono, so the
;   pan value has no direct audible effect on this chip; the refresh
;   loop is still done in case a future register-write helper consumes
;   it (e.g. the stereo bit in reg 0xC0+v that OPL3 added).
;
;   Type:        Subroutine
;   Category:    MIDI CC handler
;   Callers:     adl_midi_control_change (CC#10 branch)
;   Callees:     adl_voice_render_freq
;
;   Inputs:
;     AL  --  channel (0..15)
;     CL  --  pan value (0..127)
;
;   Outputs:     none
;
;   Side effects:
;     adl_ch_pan[ch] <- CL (raw)
;     Live voices on this channel refreshed.
; ----------------------------------------------------------------------------
adl_cc_pan      PROC    NEAR
                PUSH    SI
                PUSH    BX
                MOV     SI, AX
                AND     SI, 00FFH
                MOV     CS:[SI + adl_ch_pan], CL
                XOR     CX, CX
                MOV     DX, 0001H
                XOR     BX, BX
                JMP     SHORT ccp_test
ccp_body:       CMP     CS:[BX + adl_voice_channel], AL
                JNE     SHORT ccp_next
                MOV     CL, CS:[BX + adl_voice_note]
                CMP     CL, 0FFH
                JE      SHORT ccp_next
                CALL    adl_voice_render_freq
ccp_next:       INC     BX
ccp_test:       CMP     BX, 9
                JB      SHORT ccp_body
                POP     BX
                POP     SI
                RET
adl_cc_pan      ENDP

; ----------------------------------------------------------------------------
; 0x1D47  --  adl_cc_sustain_pedal
;
;   Handler for MIDI CC#64 ("Damper / Sustain Pedal"). When CL != 0
;   the pedal is held: just record the state. When CL == 0 the pedal
;   is released, which means any voices that were waiting on the
;   pedal (voice_sustain_held = 1, set by adl_midi_note_off) should
;   now actually be released.
;
;   This implements the classic piano-pedal behavior: notes you played
;   while holding the pedal keep ringing even after you lift the keys,
;   and they all stop together when you lift the pedal.
;
;   Type:        Subroutine
;   Category:    MIDI CC handler
;   Callers:     adl_midi_control_change (CC#64 branch)
;   Callees:     adl_voice_release (only when pedal lifts)
;
;   Inputs:
;     AL  --  channel (0..15)
;     CL  --  pedal state: 0 = off, non-zero = held
;
;   Outputs:     none
;
;   Side effects:
;     adl_ch_sustain_pedal[ch] <- CL
;     On pedal-off: every voice with voice_sustain_held set on this
;     channel is released.
; ----------------------------------------------------------------------------
adl_cc_sustain_pedal PROC NEAR
                PUSH    BX
                PUSH    SI
                MOV     SI, AX
                AND     SI, 00FFH
                MOV     CS:[SI + adl_ch_sustain_pedal], CL
                OR      CL, CL
                JNZ     SHORT ccsp_end
                XOR     BX, BX
                JMP     SHORT ccsp_test
ccsp_body:      CMP     CS:[BX + adl_voice_channel], AL
                JNE     SHORT ccsp_next
                CMP     BYTE PTR CS:[BX + adl_voice_sustain_held], 0
                JE      SHORT ccsp_next
                CALL    adl_voice_release
ccsp_next:      INC     BX
ccsp_test:      CMP     BX, 9
                JB      SHORT ccsp_body
ccsp_end:       POP     SI
                POP     BX
                RET
adl_cc_sustain_pedal ENDP
; ----------------------------------------------------------------------------
; 0x1D77  --  adl_voice_keyon
;
;   Starts a note on a chosen voice. The caller (adl_midi_note) has
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
;        adl_bank_buf + program * 28; we compute that offset by
;        shift-and-add (since 8086 has no fast multiply-by-immediate).
;     5. Cache the velocity in voice_velocity[v].
;     6. Call adl_voice_render_freq with DX = 1 (the "key on" flag)
;        to push the new pitch + key-on bit to the OPL.
;
;   Type:        Subroutine
;   Category:    Voice management
;   Callers:     adl_midi_note
;   Callees:     adl_voice_lru_remove, adl_voice_apply_patch,
;                adl_voice_render_freq
;
;   Inputs:
;     BX  --  voice index 0..8
;     CH  --  MIDI note number (0..127)
;     CL  --  pre-halved velocity (0..63)
;
;   Outputs:     none
;
;   Side effects:
;     - adl_ch_poly_active[ch]++
;     - LRU updated
;     - voice_velocity[v], possibly voice_program[v] and op_shadow[v*2]
;       updated; OPL registers 0x20..0xE0 written (via the patch reload
;       chain) and 0xA0+v / 0xB0+v written (via render_freq).
; ----------------------------------------------------------------------------
adl_voice_keyon PROC    NEAR
                PUSH    CX
                PUSH    DX
                PUSH    DI
                PUSH    SI
                XOR     DH, DH
                MOV     DL, CS:[BX + adl_voice_channel]
                MOV     SI, DX
                MOV     DL, CS:[SI + adl_ch_program]
                INC     BYTE PTR CS:[SI + adl_ch_poly_active]
                CALL    adl_voice_lru_remove
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
vkon_not_drum:  CMP     DL, CS:[BX + adl_voice_program]
                JE      SHORT vkon_no_reload
                CMP     BYTE PTR CS:adl_master_enable, 0
                JE      SHORT vkon_no_reload
                PUSH    CX
                MOV     CS:[BX + adl_voice_program], DL
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
                LEA     CX, [DI + adl_bank_buf]
                CALL    adl_voice_apply_patch
                POP     CX
vkon_no_reload: MOV     CS:[BX + adl_voice_velocity], CL
                MOV     CL, CH
                MOV     DX, 0001H
                CALL    adl_voice_render_freq
                POP     SI
                POP     DI
                POP     DX
                POP     CX
                RET
adl_voice_keyon ENDP
; ----------------------------------------------------------------------------
; 0x1DF6  --  adl_voice_release
;
;   Stops a voice cleanly:
;
;     1. Clear voice_sustain_held flag (we're releasing now, no longer
;        deferred).
;     2. Call adl_voice_render_freq with DX = 0 (no key-on bit). This
;        writes OPL reg 0xB0+v without the KEY-ON bit, which tells the
;        chip to begin the release-rate envelope.
;     3. Mark voice_note[v] = 0xFF (the voice is now idle).
;     4. Remove from LRU (so the next allocator pass treats it as old).
;     5. Decrement adl_ch_poly_active for the owning channel.
;
;   Type:        Subroutine
;   Category:    Voice management
;   Callers:     adl_midi_note_off, adl_midi_note (retrigger path),
;                adl_voice_allocate (voice-steal path), adl_cc_sustain_pedal,
;                adl_midi_control_change (CC#123 all-notes-off path),
;                adl_sustain_pool_release, adl_sustain_pool_reserve
;   Callees:     adl_voice_render_freq, adl_voice_lru_remove
;
;   Inputs:
;     BX  --  voice index 0..8
;
;   Outputs:     none
;
;   Side effects:
;     OPL register 0xB0+v written (key-off). Internal state for this
;     voice and its owning channel updated.
; ----------------------------------------------------------------------------
adl_voice_release PROC NEAR
                PUSH    CX
                PUSH    DX
                PUSH    SI
                MOV     BYTE PTR CS:[BX + adl_voice_sustain_held], 0
                XOR     CH, CH
                MOV     CL, CS:[BX + adl_voice_note]
                XOR     DX, DX
                CALL    adl_voice_render_freq
                MOV     BYTE PTR CS:[BX + adl_voice_note], 0FFH
                CALL    adl_voice_lru_remove
                MOV     DL, CS:[BX + adl_voice_channel]
                XOR     DH, DH
                MOV     SI, DX
                DEC     BYTE PTR CS:[SI + adl_ch_poly_active]
                POP     SI
                POP     DX
                POP     CX
                RET
adl_voice_release ENDP
; ----------------------------------------------------------------------------
; 0x1E26  --  adl_voice_lru_remove
;
;   "Bump this voice to the youngest position" in the LRU queue.
;   Implementation: find the entry whose value equals BL, shift every
;   entry after it down by one, then store BL at the tail (slot 8).
;
;   After this function: adl_voice_lru[8] is BL, and the order of the
;   other entries is preserved relative to each other. The next time
;   the voice allocator walks LRU from head to tail, this voice will
;   be the last one it considers (i.e. the freshest).
;
;   The implementation is a tight linear search + shift loop. The
;   loop structure (find entry; on match enter shift loop; shift loop
;   falls through to the same INC SI / outer test as the find loop)
;   reuses the outer test to confirm we ran off the end of the array.
;
;   Type:        Subroutine
;   Category:    Voice management
;   Callers:     adl_voice_keyon, adl_voice_release
;   Callees:     none
;
;   Inputs:
;     BL  --  voice index 0..8 to move to "youngest"
;
;   Outputs:     none
;
;   Side effects:
;     adl_voice_lru rearranged.
; ----------------------------------------------------------------------------
adl_voice_lru_remove PROC NEAR
                PUSH    SI
                PUSH    AX
                XOR     SI, SI
                JMP     SHORT vlru_outer
vlru_find:      CMP     CS:[SI + adl_voice_lru], BL
                JNE     SHORT vlru_next
                JMP     SHORT vlru_shift_test
vlru_shift:     MOV     AH, CS:[SI + adl_voice_lru + 1]
                MOV     CS:[SI + adl_voice_lru], AH
                INC     SI
vlru_shift_test: CMP    SI, 8
                JB      SHORT vlru_shift
vlru_next:      INC     SI
vlru_outer:     CMP     SI, 9
                JB      SHORT vlru_find
                XOR     BH, BH
                MOV     CS:[adl_voice_lru + 8], BL
                POP     AX
                POP     SI
                RET
adl_voice_lru_remove ENDP
; ----------------------------------------------------------------------------
; 0x1E55  --  adl_voice_render_freq
;
;   The big one. Pushes a voice's *current state* to the chip: pitch,
;   block (octave), key-on bit, and effective volume. Called whenever
;   anything that affects a sounding voice changes (note-on, note-off,
;   master volume, channel volume, pitch bend).
;
;   The work, in order:
;
;     1. Cache the note in voice_note[v] (so other code paths know
;        what's playing here).
;     2. Look up the voice's MIDI channel.
;     3. If this voice has a "drum" patch loaded (voice_program >= 0x80),
;        clamp the note to [0x1B, 0x58] and remap via adl_vel_to_tl_lut.
;        Drum patches map note number to drum-kit index, not pitch.
;     4. Convert the note into the F-num + block representation the
;        OPL2 wants:
;          - CX = note * 4 (the F-num table has 4 entries per semitone)
;          - call pitchbend_apply, which adjusts CX up or down based on
;            the channel's pitch wheel and returns 0xFFFF if the bend
;            sent us out of range.
;          - AL = CX / 48 (the block / octave number)
;          - AH = CX mod 48 (the offset into the F-num table)
;          - CX = adl_note_fnum_table[AH * 2] (the F-number)
;     5. Write OPL reg 0xA0+v with the F-num low byte (CL).
;     6. Build the 0xB0+v byte: (block << 2) | F-num_high | (KEY-ON if DX!=0)
;     7. Compute effective volume:
;          - lookup adl_volcurve_a[voice_velocity]
;          - multiply by (channel_volume + 1)
;          - shift right 6 to scale back to 6-bit range
;          - multiply by (master_volume + 1)
;          - shift right 4
;          - If master_enable is 0, force the result to 0
;        Call adl_voice_render_volume with AL = result.
;     8. Write OPL reg 0xB0+v with the byte from step 6.
;
;   Type:        Subroutine
;   Category:    OPL rendering
;   Callers:     adl_voice_release, adl_voice_keyon, adl_midi_pitch_bend,
;                adl_set_master_volume, adl_cc_main_volume, adl_cc_pan
;   Callees:     adl_voice_pitchbend_apply, adl_voice_render_volume,
;                adl_opl_write
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
;     adl_voice_note[v] <- CL
;     Writes OPL regs 0xA0+v (F-num lo) and 0xB0+v (F-num hi + block +
;     key-on bit). Also calls render_volume which writes 0x40+op.
; ----------------------------------------------------------------------------
adl_voice_render_freq PROC NEAR
                PUSH    SI
                PUSH    DI
                PUSH    AX
                PUSH    BX
                PUSH    CX
                PUSH    DX
                MOV     CS:[BX + adl_voice_note], CL
                XOR     AH, AH
                MOV     AL, CS:[BX + adl_voice_channel]
                MOV     SI, AX                  ; SI = channel
                XOR     CH, CH
                MOV     AL, CS:[BX + adl_voice_program]
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
                MOV     CL, CS:[SI + adl_vel_to_tl_lut]
                POP     SI
vrf_have_note:  SHL     CX, 1
                SHL     CX, 1                   ; CX = note * 4
                CALL    adl_voice_pitchbend_apply
                CMP     CX, 0FFFFH
                JNE     SHORT vrf_in_range
                JMP     SHORT vrf_end
vrf_in_range:   MOV     AX, CX
                MOV     DH, 30H                 ; divisor = 48
                DIV     DH                      ; AL = block, AH = note_in_octave
                XOR     CH, CH
                MOV     CL, AH
                MOV     DI, CX
                SHL     DI, 1
                MOV     CX, CS:[DI + adl_note_fnum_table]
                ADD     BX, 00A0H               ; BX = OPL reg 0xA0+v
                CALL    adl_opl_write
                CMP     AL, 0
                JBE     SHORT vrf_block_ok
                DEC     AL
vrf_block_ok:   MOV     CL, 02H
                SHL     AL, CL
                OR      AL, CH                  ; combine block << 2 with F-num hi
                OR      DL, DL
                JZ      SHORT vrf_no_keyon
                OR      AL, 20H                 ; KEY-ON bit
vrf_no_keyon:   XOR     CX, CX
                MOV     CL, AL
                ADD     BX, 10H                 ; BX = 0xB0+v
                PUSH    BX
                PUSH    CX
                SUB     BX, 00B0H               ; BX = voice index again
                MOV     AL, CS:[SI + adl_ch_volume]
                INC     AL
                XOR     CH, CH
                MOV     CL, CS:[BX + adl_voice_velocity]
                MOV     DI, CX
                MOV     CL, CS:[DI + adl_volcurve_a]
                INC     CL
                MUL     CL
                MOV     CL, 06H
                SHR     AX, CL
                MOV     CL, CS:adl_master_volume
                INC     CL
                MUL     CL
                MOV     CL, 04H
                SHR     AX, CL
                OR      AL, AL
                JZ      SHORT vrf_skip_dec
                DEC     AL
vrf_skip_dec:   CMP     BYTE PTR CS:adl_master_enable, 0
                JNE     SHORT vrf_apply_vol
                XOR     AL, AL
vrf_apply_vol:  CALL    adl_voice_render_volume
                POP     CX
                POP     BX
                CALL    adl_opl_write           ; write 0xB0+v
vrf_end:        POP     DX
                POP     CX
                POP     BX
                POP     AX
                POP     DI
                POP     SI
                RET
adl_voice_render_freq ENDP
; ----------------------------------------------------------------------------
; 0x1F20  --  adl_voice_pitchbend_apply
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
;   After the bend, CX is clamped to 0x01FC (the OPL2's 10-bit F-num
;   maximum, with a small safety margin). If the bend wraps CX past
;   that limit, the caller (adl_voice_render_freq) checks for the
;   sentinel 0xFFFF and short-circuits.
;
;   Type:        Subroutine
;   Category:    OPL rendering
;   Callers:     adl_voice_render_freq
;   Callees:     none
;
;   Inputs:
;     BX  --  voice index 0..8
;     CX  --  base F-num for the requested note
;
;   Outputs:
;     CX  --  bent F-num
;     DL  --  sign of the applied bend: 0 = none, 1 = positive,
;             0xFF = negative.  Used by render_freq to set the KEY-ON
;             bit unconditionally on any non-zero bend.
; ----------------------------------------------------------------------------
adl_voice_pitchbend_apply PROC NEAR
                PUSH    AX
                PUSH    BX
                PUSH    DX
                PUSH    SI
                PUSH    DI
                XOR     AH, AH
                MOV     AL, CS:[BX + adl_voice_channel]
                MOV     SI, AX
                SHL     SI, 1
                MOV     DI, CS:[SI + adl_ch_pitchbend]
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
adl_voice_pitchbend_apply ENDP
; ----------------------------------------------------------------------------
; 0x1F77  --  adl_voice_render_volume
;
;   Translates an 8-bit "effective volume index" into an OPL register
;   write for the voice's modulator operator (always), and additionally
;   for the carrier operator if the voice's algorithm uses both ops
;   audibly (additive synthesis, voice_additive[v] != 0).
;
;   The math is:
;     vol = volcurve_b[AL]                  (look up the curve)
;     tl_byte = base + vol_index * step     (linear interp from patch)
;     reg_value = (KSL << 6) | (0x3F - tl_byte)
;
;   We do this once for the modulator (writing reg 0x40 + op_offset_mod)
;   and conditionally once for the carrier (writing reg 0x40 +
;   op_offset_car). The KSL bits come from the patch's op-shadow byte
;   at offset 0; the per-op offset comes from adl_op_perm + adl_op_regoff.
;
;   Type:        Subroutine
;   Category:    OPL rendering
;   Callers:     adl_voice_render_freq
;   Callees:     adl_opl_write
;
;   Inputs:
;     BX  --  voice index 0..8
;     AL  --  effective volume index 0..63
;
;   Outputs:     none
;
;   Side effects:
;     Writes OPL register 0x40 + carrier_op (always)
;     Writes OPL register 0x40 + modulator_op (only when voice is
;     additive)
; ----------------------------------------------------------------------------
adl_voice_render_volume PROC NEAR
                PUSH    AX
                PUSH    CX
                PUSH    DX
                PUSH    DI
                XOR     AH, AH
                MOV     DI, AX
                MOV     AL, CS:[DI + adl_volcurve_b]
                PUSH    AX
                SHL     BX, 1
                MOV     CX, CS:[BX + adl_voice_mod_tl_max]
                MUL     CL
                MOV     CL, 3FH
                DIV     CL
                SUB     CL, AL
                MOV     AX, CS:[BX + adl_voice_mod_tl_base]
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
                MOV     DL, CS:[BX + adl_op_perm]
                MOV     DI, DX
                MOV     BL, CS:[DI + adl_op_regoff]
                XOR     BH, BH
                ADD     BX, 40H
                CALL    adl_opl_write
                POP     BX
                POP     AX
                CMP     BYTE PTR CS:[BX + adl_voice_additive], 0
                JZ      SHORT vrv_end
                SHL     BX, 1
                MOV     CX, CS:[BX + adl_voice_car_tl_max]
                MUL     CL
                MOV     CL, 3FH
                DIV     CL
                SUB     CL, AL
                MOV     AX, CS:[BX + adl_voice_car_tl_base]
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
                MOV     DL, CS:[BX + adl_op_perm + 9]
                MOV     DI, DX
                MOV     BL, CS:[DI + adl_op_regoff]
                XOR     BH, BH
                ADD     BX, 40H
                CALL    adl_opl_write
                POP     BX
vrv_end:        POP     DI
                POP     DX
                POP     CX
                POP     AX
                RET
adl_voice_render_volume ENDP
; ----------------------------------------------------------------------------
; 0x2013  --  adl_voice_apply_patch
;
;   Loads a 28-byte "instrument patch" into a voice. Called by
;   adl_voice_keyon when the desired patch differs from the one
;   already loaded.
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
;        to adl_op_patch_load, one per operator. Each call also writes
;        the OPL chip with the new envelope/timbre values.
;
;   Type:        Subroutine
;   Category:    Voice management
;   Callers:     adl_voice_keyon
;   Callees:     adl_op_patch_load (twice -- once per operator)
;
;   Inputs:
;     BX  --  voice index 0..8
;     CX  --  CS-relative pointer to the 28-byte patch record (inside
;             adl_bank_buf for non-default patches)
;
;   Outputs:     none
;
;   Side effects:
;     voice_additive[v], voice_mod_tl_*[v], voice_car_tl_*[v] all
;     updated. Both operators' OPL register banks rewritten via
;     adl_op_patch_load -> adl_op_apply_all_regs.
; ----------------------------------------------------------------------------
adl_voice_apply_patch PROC NEAR
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
                MOV     BYTE PTR CS:[BX + adl_voice_additive], 1
                CMP     BYTE PTR CS:[DI + 0CH], 0
                JE      SHORT vap_additive
                MOV     BYTE PTR CS:[BX + adl_voice_additive], 0
                JMP     SHORT vap_modonly
vap_additive:   SHL     BX, 1
                MOV     AH, 0
                MOV     AL, CS:[DI]
                MOV     CS:[BX + adl_voice_car_tl_base], AX
                MOV     AL, 3FH
                MOV     AH, CS:[DI + 8]
                SUB     AL, AH
                MOV     AH, 0
                MOV     CS:[BX + adl_voice_car_tl_max], AX
                MOV     DX, 0
                MOV     CX, 0FH
                DIV     CX
                MOV     CS:[BX + adl_voice_car_tl_step], AX
                JMP     SHORT vap_mod_pass
vap_modonly:    SHL     BX, 1
vap_mod_pass:   MOV     AH, 0
                MOV     AL, CS:[DI + 0DH]
                MOV     CS:[BX + adl_voice_mod_tl_base], AX
                MOV     AL, 3FH
                MOV     AH, CS:[DI + 15H]
                SUB     AL, AH
                MOV     AH, 0
                MOV     CS:[BX + adl_voice_mod_tl_max], AX
                MOV     DX, 0
                MOV     CX, 0FH
                DIV     CX
                MOV     CS:[BX + adl_voice_mod_tl_step], AX
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
                MOV     BL, CS:[DI + adl_voice_oppair]
                PUSH    DX
                MOV     DX, AX
                CALL    adl_op_patch_load
                POP     DX
                INC     DI
                MOV     BH, 0
                MOV     BL, CS:[DI + adl_voice_oppair]
                MOV     CX, SI
                CALL    adl_op_patch_load
                POP     DI
                POP     SI
                POP     DX
                POP     CX
                POP     BX
                POP     AX
                RET
adl_voice_apply_patch ENDP
; ----------------------------------------------------------------------------
; 0x20C0  --  adl_opl_write
;
;   The hardware-write primitive. EVERY communication with the OPL2
;   chip goes through this function. Implements the standard AdLib
;   write sequence:
;
;     1. OUT 0x388, BL     -- select internal register #BL
;     2. IN  AL, 0x388 x5  -- dummy reads (~3.3 us delay, the chip's
;                             register-select settling time)
;     3. OUT 0x389, CL     -- send the data byte
;     4. IN  AL, 0x388     -- loop 33 times for the data-write settling
;                             time (~23 us total)
;
;   The IN-loop technique is the canonical way to delay on early-PC
;   hardware: every IN AL,DX from a real port takes 4-5 bus cycles
;   regardless of CPU speed, because the bus stalls waiting for the
;   ISA card. 33 iterations is the empirically-derived count for the
;   slowest expected CPU clock (and faster CPUs just waste a little
;   time -- harmless).
;
;   The OPL2 will silently corrupt your write if you don't wait long
;   enough between the index and data writes. That's why every single
;   chip access goes through this one function -- to centralize the
;   timing discipline.
;
;   Type:        Subroutine
;   Category:    OPL register I/O (the chip-access primitive)
;   Callers:     14 sites across the driver (every helper that needs
;                to write a chip register)
;   Callees:     none (this is the hardware primitive)
;
;   Inputs:
;     BL  --  OPL register number (0x00..0xF5)
;     CL  --  value to write
;
;   Outputs:     none
;
;   Side effects:
;     OUTs to ports 0x388 and 0x389. INs from port 0x388 (used purely
;     for timing -- the value is discarded).
; ----------------------------------------------------------------------------
adl_opl_write   PROC    NEAR
                PUSH    AX
                PUSH    DX
                PUSH    CX
                MOV     DX, CS:adl_port_reg
                MOV     AX, BX
                OUT     DX, AL
                IN      AL, DX
                IN      AL, DX
                IN      AL, DX
                IN      AL, DX
                IN      AL, DX
                MOV     DX, CS:adl_port_data
                MOV     AX, CX
                OUT     DX, AL
                MOV     CX, 21H
                MOV     DX, CS:adl_port_status
opl_wr_delay:   IN      AL, DX
                LOOP    opl_wr_delay
                POP     CX
                POP     DX
                POP     AX
                RET
adl_opl_write   ENDP
; ----------------------------------------------------------------------------
; 0x20E7  --  adl_opl_init_all_ops
;
;   Walks all 18 OPL2 operators and loads each with one of the two
;   default patches:
;     - if op is a modulator (adl_op_iscarrier[i] == 0): default_patch_mod
;     - if op is a carrier   (adl_op_iscarrier[i] == 1): default_patch_car
;
;   This puts the chip in a known-quiet but valid state -- every
;   envelope cleared, every operator pointed at a sensible waveform.
;   Called only from adl_silence_and_reset.
;
;   Type:        Subroutine
;   Category:    Driver init
;   Callers:     adl_silence_and_reset
;   Callees:     adl_op_patch_stage_load
;
;   Inputs:      none
;   Outputs:     none
;
;   Side effects:
;     Writes the OPL register banks for every operator (50+ register
;     writes total: 18 ops * (~6 regs each + timing-mirror writes)).
; ----------------------------------------------------------------------------
adl_opl_init_all_ops PROC NEAR
                PUSH    BX
                PUSH    CX
                PUSH    DX
                PUSH    DI
                MOV     DI, 0
init_loop:      MOV     BX, DI
                MOV     DX, 0
                CMP     BYTE PTR CS:[DI + adl_op_iscarrier], 0
                JE      SHORT init_modulator
                MOV     CX, OFFSET adl_default_patch_car
                CALL    adl_op_patch_stage_load
                JMP     SHORT init_next
init_modulator: MOV     CX, OFFSET adl_default_patch_mod
                CALL    adl_op_patch_stage_load
init_next:      INC     DI
                CMP     DI, 12H
                JNE     SHORT init_loop
                POP     DI
                POP     DX
                POP     CX
                POP     BX
                RET
adl_opl_init_all_ops ENDP
; ----------------------------------------------------------------------------
; 0x2114  --  adl_op_patch_stage_load
;
;   Copies a 13-byte patch from a CS-relative source into the shared
;   adl_patch_stage scratch buffer, then forwards to adl_op_patch_load
;   pointing at the stage buffer. Used by adl_opl_init_all_ops when
;   loading the two built-in default patches into every operator.
;
;   The stage step exists because adl_op_patch_load doesn't know how
;   to read from arbitrary CS offsets cleanly when the source is in
;   the read-only part of the code segment; copying through the stage
;   buffer normalizes the read path.
;
;   Type:        Subroutine
;   Category:    Driver init
;   Callers:     adl_opl_init_all_ops
;   Callees:     adl_op_patch_load
;
;   Inputs:
;     BX  --  operator index 0..17
;     CX  --  CS-relative pointer to a 13-byte patch
;
;   Outputs:     none
;
;   Side effects:
;     adl_patch_stage[0..12] overwritten. Then adl_op_patch_load's
;     side effects: op_shadow[op*14..op*14+13] populated, OPL chip
;     re-pushed for this operator.
; ----------------------------------------------------------------------------
adl_op_patch_stage_load PROC NEAR
                PUSH    BX
                PUSH    CX
                PUSH    DX
                PUSH    DI
                PUSH    SI
                MOV     DI, 0
                MOV     SI, CX
                MOV     CH, 0
stage_copy:     MOV     CL, CS:[SI]
                MOV     CS:[DI + adl_patch_stage], CL
                INC     SI
                INC     DI
                CMP     DI, 0DH
                JNE     SHORT stage_copy
                POP     SI
                MOV     CX, OFFSET adl_patch_stage
                CALL    adl_op_patch_load
                POP     DI
                POP     DX
                POP     CX
                POP     BX
                RET
adl_op_patch_stage_load ENDP
; ----------------------------------------------------------------------------
; 0x213B  --  adl_op_patch_load
;
;   Loads a 13-byte patch into the operator's shadow slot and tail-
;   calls adl_op_apply_all_regs to push every affected OPL register.
;
;   Steps:
;     1. Compute the byte offset within adl_op_shadow as op_index * 14.
;        The shift+add sequence is the hand-rolled 8086 way to multiply
;        by 14 (= 2 + 4 + 8).
;     2. Copy 13 bytes from CS:[CX..CX+12] into op_shadow[op*14..op*14+12].
;     3. Store (DL & 0x03) into op_shadow[op*14+13] (the 14th byte,
;        which holds the FB / algorithm bits for the voice this op
;        belongs to).
;     4. Call adl_op_apply_all_regs, which walks the 8 per-op write
;        helpers and pushes every relevant OPL register for this op.
;
;   Type:        Subroutine
;   Category:    Operator patch programming
;   Callers:     adl_voice_apply_patch (twice per call; once per op),
;                adl_op_patch_stage_load
;   Callees:     adl_op_apply_all_regs
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
;     this op rewritten via adl_op_apply_all_regs.
; ----------------------------------------------------------------------------
adl_op_patch_load PROC NEAR
                PUSH    CX
                PUSH    DX
                PUSH    SI
                PUSH    DI
                MOV     SI, BX
                PUSH    AX
                PUSH    BX
                PUSH    CX
                MOV     AX, SI                  ; compute op * 14 (= op*2 + op*4 + op*8)
                SHL     AX, 1
                MOV     BX, AX
                SHL     AX, 1
                MOV     CX, AX
                SHL     AX, 1
                ADD     AX, BX
                ADD     AX, CX
                MOV     SI, AX
                POP     CX
                POP     BX
                POP     AX
                PUSH    DX
                MOV     DI, 0
opl_copy:       PUSH    DI
                MOV     DI, CX
                MOV     DL, CS:[DI]
                MOV     CS:[SI + adl_op_shadow], DL
                POP     DI
                INC     SI
                INC     CX
                INC     DI
                CMP     DI, 0DH
                JNE     SHORT opl_copy
                POP     DX
                AND     DL, 03H
                MOV     CS:[SI + adl_op_shadow], DL
                PUSH    BX
                CALL    adl_op_apply_all_regs
                POP     BX
                POP     DI
                POP     SI
                POP     DX
                POP     CX
                RET
adl_op_patch_load ENDP
; ----------------------------------------------------------------------------
; 0x2184  --  adl_op_apply_all_regs
;
;   Calls each of the eight per-op OPL write helpers in sequence. Pushes
;   every OPL register that this operator's patch can affect, in order:
;
;     0xBD              (rhythm-mode + AM/Vib depth)         [global]
;     0x08              (CSM / NOTE-SEL)                     [global]
;     0x40 + op_offset  (Key Scale Level + Total Level)      [per op]
;     0xC0 + voice      (Feedback + algorithm + stereo bit)  [per voice]
;     0x60 + op_offset  (Attack Rate + Decay Rate)           [per op]
;     0x80 + op_offset  (Sustain Level + Release Rate)       [per op]
;     0x20 + op_offset  (AM/Vib/EG-type/KSR + frequency mult) [per op]
;     0xE0 + op_offset  (waveform select, if reg 0x01 bit 5) [per op]
;
;   Two of these (0xBD and 0x08) are global to the chip, not per-op --
;   but we re-push them anyway because the patch could potentially
;   include depth bits that need to be re-sent. The per-voice 0xC0
;   write only fires on the modulator op of the pair (see the body of
;   adl_opl_write_voice_feedback).
;
;   Type:        Subroutine
;   Category:    Operator patch programming
;   Callers:     adl_op_patch_load
;   Callees:     adl_opl_write_rhythm, adl_opl_write_notesel,
;                adl_opl_write_op_level, adl_opl_write_voice_feedback,
;                adl_opl_write_op_ar_dr, adl_opl_write_op_sl_rr,
;                adl_opl_write_op_flags_mult, adl_opl_write_op_waveform
;
;   Inputs:
;     BX  --  operator index 0..17 (passed through to each callee)
;
;   Outputs:     none
;
;   Side effects:
;     ~8 OPL register writes per call.
; ----------------------------------------------------------------------------
adl_op_apply_all_regs PROC NEAR
                CALL    adl_opl_write_rhythm
                CALL    adl_opl_write_notesel
                CALL    adl_opl_write_op_level
                CALL    adl_opl_write_voice_feedback
                CALL    adl_opl_write_op_ar_dr
                CALL    adl_opl_write_op_sl_rr
                CALL    adl_opl_write_op_flags_mult
                CALL    adl_opl_write_op_waveform
                RET
adl_op_apply_all_regs ENDP
; ----------------------------------------------------------------------------
; 0x219D  --  adl_opl_write_rhythm
;
;   Writes OPL register 0xBD (rhythm-mode flags + AM/Vib depth) from the
;   three RAM mirrors. The composed byte is:
;
;     bit 7  AM depth          (from adl_opl_amdepth)
;     bit 6  VIB depth         (from adl_opl_vibdepth)
;     bits 5..0  rhythm-mode + BD/SD/TT/CY/HH key-ons
;                              (from adl_opl_rhythm)
;
;   Type:        Subroutine
;   Category:    OPL register I/O (per-register writer)
;   Callers:     adl_op_apply_all_regs
;   Callees:     adl_opl_write
;
;   Inputs:      none (reads driver state mirrors only)
;   Outputs:     none
;
;   Side effects:
;     OPL register 0xBD written.
; ----------------------------------------------------------------------------
adl_opl_write_rhythm PROC NEAR
                PUSH    BX
                PUSH    CX
                MOV     CX, 0
                CMP     BYTE PTR CS:adl_opl_amdepth, 0
                JE      SHORT rh_no_am
                OR      CL, 80H
rh_no_am:       CMP     BYTE PTR CS:adl_opl_vibdepth, 0
                JE      SHORT rh_no_vib
                OR      CL, 40H
rh_no_vib:      OR      CL, CS:adl_opl_rhythm
                MOV     BX, 0BDH
                CALL    adl_opl_write
                POP     CX
                POP     BX
                RET
adl_opl_write_rhythm ENDP

; ----------------------------------------------------------------------------
; 0x21C6  --  adl_opl_write_notesel
;
;   Writes OPL register 0x08 (CSM / NOTE-SEL). The driver only ever
;   uses NOTE-SEL (bit 6): from the mirror adl_opl_notesel, write 0x40
;   if non-zero else 0. NOTE-SEL shifts the key-scaling boundary
;   between MIDI notes; useful only when KSR is enabled in operator
;   patches.
;
;   Type:        Subroutine
;   Category:    OPL register I/O (per-register writer)
;   Callers:     adl_op_apply_all_regs
;   Callees:     adl_opl_write
;
;   Inputs:      none
;   Outputs:     none
;
;   Side effects:
;     OPL register 0x08 written.
; ----------------------------------------------------------------------------
adl_opl_write_notesel PROC NEAR
                PUSH    BX
                PUSH    CX
                MOV     CX, 0
                CMP     BYTE PTR CS:adl_opl_notesel, 0
                JE      SHORT ns_no
                MOV     CL, 40H
ns_no:          MOV     BX, 8
                CALL    adl_opl_write
                POP     CX
                POP     BX
                RET
adl_opl_write_notesel ENDP

; ----------------------------------------------------------------------------
; 0x21DE  --  adl_opl_write_op_level
;
;   Writes OPL register 0x40 + op_offset (the per-op Key Scale Level +
;   Total Level register). The byte value is:
;
;     bits 7..6  KSL  (from op_shadow[op*14 + 0])
;     bits 5..0  TL   (from op_shadow[op*14 + 8], masked to 6 bits)
;
;   KSL controls how much the level decreases with rising pitch
;   (mimicking acoustic instruments getting quieter at higher notes).
;   TL is the operator's attenuation: 0 = loudest, 0x3F = silent.
;
;   Type:        Subroutine
;   Category:    OPL register I/O (per-register writer)
;   Callers:     adl_op_apply_all_regs
;   Callees:     adl_opl_write
;
;   Inputs:
;     BX  --  operator index 0..17
;
;   Outputs:     none
;
;   Side effects:
;     OPL register 0x40 + adl_op_regoff[op] written.
; ----------------------------------------------------------------------------
adl_opl_write_op_level PROC NEAR
                PUSH    AX
                PUSH    BX
                PUSH    CX
                PUSH    DI
                MOV     DI, BX
                PUSH    AX
                PUSH    BX
                PUSH    CX
                MOV     AX, DI
                SHL     AX, 1
                MOV     BX, AX
                SHL     AX, 1
                MOV     CX, AX
                SHL     AX, 1
                ADD     AX, BX
                ADD     AX, CX
                MOV     DI, AX                  ; DI = op * 14
                POP     CX
                POP     BX
                POP     AX
                MOV     AH, 0
                MOV     AL, CS:[DI + adl_op_shadow]
                MOV     CL, 06H
                SHL     AL, CL                  ; AL = KSL << 6
                MOV     CX, AX
                MOV     AL, CS:[DI + adl_op_shadow + 8]
                AND     AL, 3FH                 ; TL (6 bits)
                OR      CL, AL
                MOV     BH, 0
                MOV     DI, BX
                MOV     BL, CS:[DI + adl_op_regoff]
                ADD     BL, 40H
                CALL    adl_opl_write
                POP     DI
                POP     CX
                POP     BX
                POP     AX
                RET
adl_opl_write_op_level ENDP

; ----------------------------------------------------------------------------
; 0x2226  --  adl_opl_write_voice_feedback
;
;   Writes OPL register 0xC0 + voice (per-voice feedback + algorithm
;   + stereo bit). The register lives per *voice*, not per-op, so we
;   only fire on the modulator op of the pair to avoid double-writing.
;
;   The byte value is:
;     bits 3..1  feedback (FB, from op_shadow[op*14 + 2])
;     bit 0      OPL3 stereo bit: 1 if not-stereo, 0 if stereo
;                (the driver writes the inverse of patch[+12]).
;     bits 7..4  reserved on OPL2, but we mask them off anyway.
;
;   The voice number is found via adl_op_voice[op].
;
;   Type:        Subroutine
;   Category:    OPL register I/O (per-register writer)
;   Callers:     adl_op_apply_all_regs
;   Callees:     adl_opl_write
;
;   Inputs:
;     BX  --  operator index 0..17
;
;   Outputs:     none
;
;   Side effects:
;     OPL register 0xC0 + adl_op_voice[op] written -- but ONLY when op
;     is the modulator of its pair (adl_op_iscarrier[op] == 0). Carrier
;     ops fall through to the function's epilogue without writing.
; ----------------------------------------------------------------------------
adl_opl_write_voice_feedback PROC NEAR
                PUSH    BX
                PUSH    CX
                PUSH    DI
                MOV     DI, BX
                CMP     BYTE PTR CS:[DI + adl_op_iscarrier], 0
                JNE     SHORT fb_skip
                PUSH    AX
                PUSH    BX
                PUSH    CX
                MOV     AX, DI
                SHL     AX, 1
                MOV     BX, AX
                SHL     AX, 1
                MOV     CX, AX
                SHL     AX, 1
                ADD     AX, BX
                ADD     AX, CX
                MOV     DI, AX                  ; DI = op * 14
                POP     CX
                POP     BX
                POP     AX
                MOV     AH, 0
                MOV     AL, CS:[DI + adl_op_shadow + 2]
                SHL     AX, 1
                MOV     CX, AX
                CMP     BYTE PTR CS:[DI + adl_op_shadow + 12], 0
                JNE     SHORT fb_no_stereo
                INC     CL
fb_no_stereo:   MOV     DI, BX
                MOV     BH, 0
                MOV     BL, CS:[DI + adl_op_voice]
                ADD     BL, 0C0H
                AND     CL, 0FH
                CALL    adl_opl_write
fb_skip:        POP     DI
                POP     CX
                POP     BX
                RET
adl_opl_write_voice_feedback ENDP
; ----------------------------------------------------------------------------
; 0x2276  --  adl_opl_write_op_ar_dr
;
;   Writes OPL register 0x60 + op_offset (Attack Rate + Decay Rate
;   for one operator). Byte layout:
;
;     bits 7..4  AR  (from op_shadow[op*14 + 3])
;     bits 3..0  DR  (from op_shadow[op*14 + 6])
;
;   AR/DR are 4-bit values: higher = faster envelope.
;
;   Type:        Subroutine
;   Category:    OPL register I/O (per-register writer)
;   Callers:     adl_op_apply_all_regs
;   Callees:     adl_opl_write
;
;   Inputs:
;     BX  --  operator index 0..17
;
;   Outputs:     none
;
;   Side effects:
;     OPL register 0x60 + adl_op_regoff[op] written.
; ----------------------------------------------------------------------------
adl_opl_write_op_ar_dr PROC NEAR
                PUSH    BX
                PUSH    CX
                PUSH    DI
                MOV     DI, BX
                PUSH    AX
                PUSH    BX
                PUSH    CX
                MOV     AX, DI
                SHL     AX, 1
                MOV     BX, AX
                SHL     AX, 1
                MOV     CX, AX
                SHL     AX, 1
                ADD     AX, BX
                ADD     AX, CX
                MOV     DI, AX                  ; DI = op * 14
                POP     CX
                POP     BX
                POP     AX
                MOV     AH, 0
                MOV     AL, CS:[DI + adl_op_shadow + 3]
                MOV     CL, 04H
                SHL     AL, CL
                MOV     CX, AX
                MOV     AL, CS:[DI + adl_op_shadow + 6]
                AND     AL, 0FH
                OR      CL, AL
                MOV     DI, BX
                MOV     BH, 0
                MOV     BL, CS:[DI + adl_op_regoff]
                ADD     BL, 60H
                CALL    adl_opl_write
                POP     DI
                POP     CX
                POP     BX
                RET
adl_opl_write_op_ar_dr ENDP

; ----------------------------------------------------------------------------
; 0x22BC  --  adl_opl_write_op_sl_rr
;
;   Writes OPL register 0x80 + op_offset (Sustain Level + Release Rate
;   for one operator). Byte layout:
;
;     bits 7..4  SL  (from op_shadow[op*14 + 4])
;     bits 3..0  RR  (from op_shadow[op*14 + 7])
;
;   SL is the amplitude the envelope decays *to* before holding;
;   RR is the rate at which the envelope decays *after* key-off.
;
;   Type:        Subroutine
;   Category:    OPL register I/O (per-register writer)
;   Callers:     adl_op_apply_all_regs
;   Callees:     adl_opl_write
;
;   Inputs:
;     BX  --  operator index 0..17
;
;   Outputs:     none
;
;   Side effects:
;     OPL register 0x80 + adl_op_regoff[op] written.
; ----------------------------------------------------------------------------
adl_opl_write_op_sl_rr PROC NEAR
                PUSH    BX
                PUSH    CX
                PUSH    DI
                MOV     DI, BX
                PUSH    AX
                PUSH    BX
                PUSH    CX
                MOV     AX, DI
                SHL     AX, 1
                MOV     BX, AX
                SHL     AX, 1
                MOV     CX, AX
                SHL     AX, 1
                ADD     AX, BX
                ADD     AX, CX
                MOV     DI, AX                  ; DI = op * 14
                POP     CX
                POP     BX
                POP     AX
                MOV     AH, 0
                MOV     AL, CS:[DI + adl_op_shadow + 4]
                MOV     CL, 04H
                SHL     AL, CL
                MOV     CX, AX
                MOV     AL, CS:[DI + adl_op_shadow + 7]
                AND     AL, 0FH
                OR      CL, AL
                MOV     DI, BX
                MOV     BH, 0
                MOV     BL, CS:[DI + adl_op_regoff]
                ADD     BL, 80H
                CALL    adl_opl_write
                POP     DI
                POP     CX
                POP     BX
                RET
adl_opl_write_op_sl_rr ENDP

; ----------------------------------------------------------------------------
; 0x2302  --  adl_opl_write_op_flags_mult
;
;   Writes OPL register 0x20 + op_offset (the operator's four boolean
;   flags + frequency multiplier). Byte layout:
;
;     bit 7      AM   (tremolo enable; from shadow[+9])
;     bit 6      VIB  (vibrato enable; from shadow[+10])
;     bit 5      EG-type (0=percussive 1=sustained; from shadow[+5])
;     bit 4      KSR  (key-scaling rate enable; from shadow[+11])
;     bits 3..0  MULT (multiplier 0..15; from shadow[+1])
;
;   MULT scales the operator's frequency relative to the voice's
;   F-number; non-1 values are used for FM "harmonic" sounds.
;
;   Type:        Subroutine
;   Category:    OPL register I/O (per-register writer)
;   Callers:     adl_op_apply_all_regs
;   Callees:     adl_opl_write
;
;   Inputs:
;     BX  --  operator index 0..17
;
;   Outputs:     none
;
;   Side effects:
;     OPL register 0x20 + adl_op_regoff[op] written.
; ----------------------------------------------------------------------------
adl_opl_write_op_flags_mult PROC NEAR
                PUSH    CX
                PUSH    DI
                MOV     DI, BX
                PUSH    AX
                PUSH    BX
                PUSH    CX
                MOV     AX, DI
                SHL     AX, 1
                MOV     BX, AX
                SHL     AX, 1
                MOV     CX, AX
                SHL     AX, 1
                ADD     AX, BX
                ADD     AX, CX
                MOV     DI, AX                  ; DI = op * 14
                POP     CX
                POP     BX
                POP     AX
                MOV     AH, 0
                MOV     AL, CS:[DI + adl_op_shadow + 9]
                MOV     CX, 0
                CMP     AL, 0
                JE      SHORT fm_no_am
                OR      CL, 80H
fm_no_am:       MOV     AL, CS:[DI + adl_op_shadow + 10]
                CMP     AL, 0
                JE      SHORT fm_no_vib
                OR      CL, 40H
fm_no_vib:      MOV     AL, CS:[DI + adl_op_shadow + 5]
                CMP     AL, 0
                JE      SHORT fm_no_eg
                OR      CL, 20H
fm_no_eg:       MOV     AL, CS:[DI + adl_op_shadow + 11]
                CMP     AL, 0
                JE      SHORT fm_no_ksr
                OR      CL, 10H
fm_no_ksr:      MOV     AL, CS:[DI + adl_op_shadow + 1]
                AND     AL, 0FH
                OR      CL, AL
                PUSH    BX
                MOV     DI, BX
                MOV     BH, 0
                MOV     BL, CS:[DI + adl_op_regoff]
                ADD     BL, 20H
                CALL    adl_opl_write
                POP     BX
                POP     DI
                POP     CX
                RET
adl_opl_write_op_flags_mult ENDP

; ----------------------------------------------------------------------------
; 0x2370  --  adl_opl_write_op_waveform
;
;   Writes OPL register 0xE0 + op_offset (operator waveform select).
;   The OPL2 supports four waveforms beyond the default sine: half-sine,
;   absolute-sine, quarter-sine, and (on some clones) others. Reg 0xE0
;   selects which one this operator outputs.
;
;   This register is only honored by the chip when reg 0x01 bit 5 is
;   set (the "wave select enable" gate). If that gate is off,
;   adl_silence_and_reset hasn't run yet -- skip the write.
;
;   Byte layout: bits 1..0 = waveform (0..3); other bits are reserved.
;   The shadow byte is at op_shadow[op*14 + 13].
;
;   Type:        Subroutine
;   Category:    OPL register I/O (per-register writer)
;   Callers:     adl_op_apply_all_regs
;   Callees:     adl_opl_write
;
;   Inputs:
;     BX  --  operator index 0..17
;
;   Outputs:     none
;
;   Side effects:
;     OPL register 0xE0 + adl_op_regoff[op] written -- only if
;     adl_wave_select_en != 0.
; ----------------------------------------------------------------------------
adl_opl_write_op_waveform PROC NEAR
                PUSH    BX
                PUSH    CX
                PUSH    DI
                CMP     WORD PTR CS:adl_wave_select_en, 0
                JE      SHORT wf_skip
                XOR     BH, BH
                MOV     DI, BX
                PUSH    AX
                PUSH    BX
                PUSH    CX
                MOV     AX, DI
                SHL     AX, 1
                MOV     BX, AX
                SHL     AX, 1
                MOV     CX, AX
                SHL     AX, 1
                ADD     AX, BX
                ADD     AX, CX
                MOV     DI, AX                  ; DI = op * 14
                POP     CX
                POP     BX
                POP     AX
                XOR     CH, CH
                MOV     CL, CS:[DI + adl_op_shadow + 13]
                MOV     DI, BX
                MOV     BL, CS:[DI + adl_op_regoff]
                ADD     BL, 0E0H
                CALL    adl_opl_write
wf_skip:        POP     DI
                POP     CX
                POP     BX
                RET
adl_opl_write_op_waveform ENDP
; ----------------------------------------------------------------------------
; 0x23AF  --  adl_silence_and_reset
;
;   The full "reset the chip" sequence. Three phases:
;
;     1. Write 0 to every OPL register from 0x00 to 0xF5 (246 writes).
;        This clears every envelope, mutes every operator, and turns
;        off every key.
;     2. Set adl_wave_select_en = 0x20 in RAM and write 0x20 to OPL
;        register 0x01. This enables the per-op waveform-select group
;        (regs 0xE0..0xF5) so non-sine waveforms become available.
;     3. Re-load every operator with one of the two default patches via
;        adl_opl_init_all_ops.
;
;   Called from slot 2 (game-initiated reset) and from inside slot 1
;   (after a new patch bank is uploaded).
;
;   Type:        Subroutine
;   Category:    Driver init / global state
;   Callers:     adl_reset_voices (slot 2), adl_load_patch_bank (slot 1)
;   Callees:     adl_opl_write (247 times), adl_opl_init_all_ops
;
;   Inputs:      none
;   Outputs:     none
;
;   Side effects:
;     247 OPL register writes; adl_wave_select_en updated; every
;     operator's patch state reset to defaults.
;
;   Notes:
;     Quirk: this function pushes BX, CX (in that order) and pops
;     BX, CX in the SAME order, not the symmetric CX, BX. Net effect:
;     caller's BX and CX are swapped on return. Harmless because
;     neither caller observes those registers after the call.
; ----------------------------------------------------------------------------
adl_silence_and_reset PROC NEAR
                PUSH    BX
                PUSH    CX
                XOR     BX, BX
                XOR     CX, CX
                JMP     SHORT sar_test
sar_body:       CALL    adl_opl_write
                INC     BX
sar_test:       CMP     BX, 0F6H
                JB      SHORT sar_body
                MOV     WORD PTR CS:adl_wave_select_en, 0020H
                MOV     BX, 0001H
                MOV     CX, CS:adl_wave_select_en
                CALL    adl_opl_write
                CALL    adl_opl_init_all_ops
                POP     BX
                POP     CX
                RET
adl_silence_and_reset ENDP

; ----------------------------------------------------------------------------
; 0x23D9  --  adl_query_state
;
;   The read side of the slot ABI: tells the game what value the driver
;   is currently holding for a given MIDI-state field. The query selects
;   what to read via the MIDI-status high nibble in AH:
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
;   Each branch reads from the same per-channel byte array that the
;   corresponding setter (slot 7, 8, or 10) writes to, so the result is
;   always consistent with what the game last set.
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
;     Contains an unreachable JMP SHORT to the "unknown" label -- the
;     two surrounding paths already JMP elsewhere, so control never
;     reaches it.
; ----------------------------------------------------------------------------
adl_query_state PROC NEAR
                PUSH    SI
                MOV     SI, AX
                AND     SI, 00FFH
                CMP     AH, 0E0H
                JNE     SHORT qry_not_e0
                SHL     SI, 1
                MOV     AX, CS:[SI + adl_ch_pitchbend]
                JMP     SHORT qry_end
qry_not_e0:     CMP     AH, 0C0H
                JNE     SHORT qry_not_c0
                XOR     AH, AH
                MOV     AL, CS:[SI + adl_ch_program]
                JMP     SHORT qry_end
qry_not_c0:     CMP     AH, 0B0H
                JNE     SHORT qry_unknown
                XOR     AH, AH
                CMP     CH, 07H
                JNE     SHORT qry_not_07
                MOV     AL, CS:[SI + adl_ch_volume]
                JMP     SHORT qry_end
qry_not_07:     CMP     CH, 0AH
                JNE     SHORT qry_not_0a
                MOV     AL, CS:[SI + adl_ch_pan]
                JMP     SHORT qry_end
qry_not_0a:     CMP     CH, 40H
                JNE     SHORT qry_not_40
                MOV     AL, CS:[SI + adl_ch_sustain_pedal]
                JMP     SHORT qry_end
qry_not_40:     CMP     CH, 4BH
                JNE     SHORT qry_unknown
                CMP     CL, 0FFH
                JE      SHORT qry_use_max
                MOV     AL, CS:[SI + adl_ch_sustain_count]
                JMP     SHORT qry_end
                JMP     SHORT qry_unknown
qry_use_max:    MOV     AL, CS:[SI + adl_ch_poly_max]
                JMP     SHORT qry_end
qry_unknown:    MOV     AX, 0FFFFH
qry_end:        POP     SI
                RET
adl_query_state ENDP

; ----------------------------------------------------------------------------
; 0x2446  --  adl_load_patch_bank
;
;   Uploads a patch bank from the game's address space into the driver's
;   internal adl_bank_buf, then resets the chip so the new bank takes
;   effect on the next note-on.
;
;   The game passes a far pointer: segment in ES, offset in AX. We copy
;   adl_bank_size bytes (a 16-bit constant baked into the driver at
;   adl_bank_size; the on-disk value is 0x1507 = 5383 bytes) byte-by-byte
;   from ES:[AX..AX+size-1] into CS:[adl_bank_buf..adl_bank_buf+size-1].
;
;   After the copy:
;     - Call adl_silence_and_reset to fully reset the chip with the new
;       bank's default patches.
;     - Call adl_set_master_volume(0x0F) to restore master volume to a
;       sane mid-level value.
;
;   Returns a "self-id handshake" in AX and CX -- the game can check
;   AX == 0x2446 (this function's own offset) to confirm slot 1 is
;   actually wired up in this driver. CX = 0x0800 may indicate the
;   chunk-size or bank-format version; we don't have full confirmation.
;
;   Type:        Slot handler
;   Category:    Bank loading
;   Dispatch:    Slot 1 (called as: BP=1, ES:AX = src far ptr)
;   Callers:     Game (via dispatch)
;   Callees:     adl_silence_and_reset, adl_set_master_volume
;
;   Inputs:
;     ES:AX  --  far pointer to source bank in the game's memory
;
;   Outputs:
;     AX  --  0x2446 (self-id)
;     CX  --  0x0800 (format/version handshake)
;
;   Side effects:
;     adl_bank_buf overwritten with adl_bank_size bytes from ES:AX.
;     Chip reset + master volume forced to 0x0F.
; ----------------------------------------------------------------------------
adl_load_patch_bank PROC NEAR
                PUSH    BX
                PUSH    DX
                PUSH    SI
                PUSH    DI
                MOV     SI, AX
                XOR     DI, DI
                MOV     CX, CS:adl_bank_size
                JMP     SHORT lpb_test
lpb_body:       MOV     BL, ES:[SI]
                MOV     CS:[DI + adl_bank_buf], BL
                INC     SI
                INC     DI
                DEC     CX
lpb_test:       OR      CX, CX
                JNZ     SHORT lpb_body
                CALL    adl_silence_and_reset
                MOV     CL, 0FH
                CALL    adl_set_master_volume
                MOV     AX, 2446H
                MOV     CL, 0
                MOV     CH, 8
                POP     DI
                POP     SI
                POP     DX
                POP     BX
                RET
adl_load_patch_bank ENDP

; ----------------------------------------------------------------------------
; 0x2478  --  adl_get_info
;
;   The "what are you?" query. The DUDE family reserves slot 0 for a
;   short capability descriptor returned in four byte registers.
;
;     AH = 1   -- DUDE interface version
;     AL = 3   -- device identifier (3 = AdLib / OPL2 in Dynamix's
;                 driver catalog). Sister drivers (SBP, MT-32, etc.)
;                 return different AL values.
;     CH = 0   -- auxiliary capability flags. 0 here means "plain
;                 melodic FM, no extras".
;     CL = 9   -- number of melodic voices the driver supports. 9 for
;                 the OPL2 (and 11 in OPL3 rhythm mode, which we don't
;                 use).
;
;   The game reads these to know how many voices to allocate, which
;   icon to show in the sound-setup menu, etc.
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
;     AL  --  3 (device id, AdLib)
;     CH  --  0 (no extra capabilities)
;     CL  --  9 (voice count)
; ----------------------------------------------------------------------------
adl_get_info   PROC    NEAR
                MOV     AH, 1
                MOV     AL, 3
                MOV     CH, 0
                MOV     CL, 9
                RET
adl_get_info   ENDP

                END     _start
