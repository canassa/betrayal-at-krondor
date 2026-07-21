; ============================================================================
; Sx.SSM.NLD.bin -- Dynamix DUDE-format MT-32/GM "no-load" MIDI driver, v1.06
;
; *** DEVELOPER / DEBUG BUILD -- "(not for shipping)" ***
;
; The Pascal-string device name embedded in this driver's header reads:
;
;     "MT32GM MPU noload (not for shipping)"
;
; This was a developer test build that accidentally shipped with the retail
; *Betrayal at Krondor* CD. It is the Roland MT-32 / General-
; MIDI driver (Sx.SSM.M32.bin v1.08) with one structural change: the
; "load_patch_bank" slot (slot 1) DOES NOT upload the SysEx instrument
; patches to the MT-32 hardware. The MPU-401 reset commands still fire and
; the per-channel program-map metadata still gets copied into the driver's
; local state, but the slow SysEx upload that would teach the MT-32 the
; game's custom instruments is silently elided.
;
; The driver is therefore "playable but wrong-sounding" on a real MT-32:
; notes go out the wire, but the MT-32 plays them using its factory ROM
; presets instead of the game's authored timbres. On an MT-32-GM hybrid
; (e.g. the SC-55's MT-32 mode), the GM ROM presets are the fallback. The
; net effect is a developer/QA mode for testing MIDI logic without paying
; the multi-second cost of re-uploading 480-byte SysEx blobs every time
; the game restarts.
;
; This file shouldn't have shipped. It did anyway.
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
; This file is the Roland MT-32 / General-MIDI driver in its "no-SysEx-
; upload" developer-test variant. Unlike the AdLib driver which has to
; synthesize FM voices in software-controlled OPL2 hardware, an MT-32-style
; driver mostly just packages MIDI events into wire-format bytes and feeds
; them out the MPU-401 UART. The MPU-401 is a small ISA card with a UART
; that bridges the host's I/O ports to a 31.25 kbaud MIDI cable; the MT-32
; lives on the other end of the cable and does the synthesis.
;
; The game communicates with this driver through the same tiny dispatch ABI
; used by every Dynamix DUDE driver (see "About the DUDE dispatch ABI"
; below): one entry point at offset 0x05A9, eighteen "slots", each slot a
; different request like "play this note" or "change this controller".
; When a slot is invoked, this code translates the MIDI-style request into
; the appropriate wire-format MIDI message and pushes it out the MPU-401.
;
; The first ~1.2 KB of this file is uninitialized buffer space for a patch
; bank that the game would normally upload to us, and per-channel state
; arrays (programs, volumes, pans, pitch bends). The remaining ~1 KB is
; code: 18 slot handlers plus a handful of MPU-401-talking helpers.
; ----------------------------------------------------------------------------

; ----------------------------------------------------------------------------
; About the Roland MT-32 + MPU-401 setup
;
; The MT-32 (and its descendents -- MT-100, CM-32L, CM-64, plus the LAPC-I
; ISA-card variant that bundles everything) is a hardware MIDI synthesizer
; from 1987. It takes MIDI bytes over a serial cable and produces audio out
; the back. From the host PC's perspective it is a "remote synthesizer":
; once you've sent it a note-on, the synthesizer keeps that note ringing
; on its own until you send a corresponding note-off; the host doesn't
; need to do any DSP work.
;
; The MT-32 connects to a PC through the **MPU-401** card. The MPU-401 is
; a small ISA card with a UART that bridges the host's CPU I/O ports to
; the MT-32's MIDI cable. It exposes two 8-bit I/O ports:
;
;   port 0x330  (the "data" port)     -- write bytes to be sent on MIDI
;                                        out, or read bytes the MT-32 sent
;                                        back.
;   port 0x331  (the "command/status" port) -- read for status (bit 6 set =
;                                              not ready), write for
;                                              commands (mode-switch
;                                              etc.) and SysEx framing.
;
; The MPU-401 has two operating modes: "intelligent" (where it does its
; own timing and clocking via its dedicated MIDI-FIFO + IRQ) and "UART"
; (where the host transmits raw bytes and times them itself). This driver
; uses UART mode -- simpler, no IRQ hook needed, host pays the byte-rate
; cost on every note.
;
; To send a single MIDI byte, the host:
;   1. Polls port 0x331 until bit 6 ("not-ready") clears, then
;   2. Writes the byte to port 0x330.
; See nld_mpu_send_data below for the canonical sequence.
;
; To send a command to the MPU-401 itself (rather than to the MT-32 on
; the other end of the cable), use port 0x331 instead. Two commands
; matter here:
;
;   0x3F  -- "enter UART mode"     (the driver issues this 3 times in a
;                                   row at startup to ensure we're in
;                                   UART mode regardless of prior state)
;   0xFF  -- "reset MPU"            (issued before the 0x3F sequence to
;                                   force the card to a known state)
;
; The MT-32 itself accepts standard MIDI messages: note-on (0x90..0x9F),
; note-off (0x80..0x8F), CC (0xB0..0xBF), program-change (0xC0..0xCF),
; pitch-bend (0xE0..0xEF), and SysEx (0xF0..0xF7). The driver speaks all
; of these except SysEx -- which is exactly the "noload" difference vs.
; the production M32 driver (see Notes at top of file).
;
; One MIDI idiom worth knowing up front: a note-on (0x9n) with velocity
; 0 is interpreted by every conformant MIDI receiver as a note-OFF for
; that note. This was added to the spec so that "MIDI running status"
; (where consecutive same-status messages can omit the status byte)
; works for streams that mix note-ons and note-offs. This driver uses
; it: nld_midi_note_off below emits 0x9n with velocity 0 rather than
; 0x8n, matching what the production M32 driver does.
;
; "MT32GM" in the device-name string refers to the MT-32's GM-mode
; emulation: in this driver's worldview, the patch numbers we send out
; are interpreted by the receiver as either MT-32 patches OR General-MIDI
; patches depending on which mode the receiver is in. The driver itself
; is agnostic.
; ----------------------------------------------------------------------------

; ----------------------------------------------------------------------------
; About the DUDE dispatch ABI
;
; "DUDE" is Dynamix's internal sound-driver format. Every Dynamix sound
; driver of this generation is a flat binary that begins with a header
; containing two magic numbers (0x87654321 and 0xFEDCBA98), the ASCII
; tag "dude", a human-readable device-name string, and a version tag.
; See the data section below for the literal layout.
;
; The game communicates with this driver in exactly one way: a far call
; into the *dispatch trampoline* at offset 0x05A9. Before the call, the
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
;   MOV  DX, CS:[BP + nld_func_table]
;   CALL DX                          ; near call to the slot's handler
;   POP  DX
;   RETF                             ; far return to the game
;
; The handlers themselves are near procedures (`PROC NEAR ... ENDP`); the
; trampoline is the only thing that does a far return.
;
; Note this driver, unlike ADL, does *not* preserve the caller's BP across
; the trampoline. ADL's trampoline saves BP (`PUSH BP / ... / POP BP`); NLD
; uses DX as the scratch register for the indirect call and never restores
; BP, so on return BP = (slot * 2). No observed game-side caller reads BP
; back across this far call, so the discrepancy is invisible in practice --
; but this is a real semantic difference, not just stylistic. The MT-32 /
; M32 family (which NLD is derived from) uses the DX form; ADL/SBP went
; with the BP-save form independently.
;
; The 18 slots in this driver, in order:
;
;   Slot  0  nld_get_info                 -- returns AH/AL/CH/CL descriptor
;   Slot  1  nld_load_patch_bank          -- ES:AX = src; MPU reset + copy
;                                            patch-map metadata into local
;                                            state, but *skip* SysEx upload
;                                            (the "noload" deviation)
;   Slot  2  nld_reset_voices             -- send MPU reset (0xFF)
;   Slot  3  nld_slot_unused_ret          -- (no-op stub)
;   Slot  4  nld_midi_note_off            -- AL=ch, CH=note, CL=vel
;   Slot  5  nld_midi_note                -- AL=ch, CH=note, CL=vel (0=off)
;   Slot  6  nld_slot_unused_ret          -- (no-op stub)
;   Slot  7  nld_midi_control_change      -- AL=ch, CH=cc, CL=val
;   Slot  8  nld_midi_program_change      -- AL=ch, CL=program
;   Slot  9  nld_slot_unused_ret          -- (no-op stub)
;   Slot 10  nld_midi_pitch_bend          -- AL=ch, CL=lo, CH=hi
;   Slot 11  nld_set_global_param_11d     -- CL=val (0xFF=query)
;   Slot 12  nld_set_master_volume        -- CL=val (0xFF=query)
;   Slot 13  nld_set_master_enable        -- CL=val (0xFF=query)
;   Slot 14  nld_slot_unused_ret          -- (no-op stub)
;   Slot 15  nld_slot_unused_ret          -- (no-op stub)
;   Slot 16  nld_slot_unused_ret          -- (no-op stub)
;   Slot 17  nld_query_state              -- read-side of the setter ABI
;
; Slots 3, 6, 9, 14, 15, 16 all point at a shared one-byte `RET` stub --
; they're reserved in the cross-driver ABI but this particular driver
; doesn't implement them. The driver has no internal timer or IRQ hook;
; every MPU-401 write is initiated by a game-side call into one of these
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
; - Lines like `nld_ch_program  DB 16 DUP(0FFH)` declare data: the
;   label names this address, `DB` says "the following are bytes", and
;   `16 DUP(0FFH)` means "sixteen copies of the value 0xFF". `DW` is the
;   16-bit equivalent (two bytes per entry, little-endian on x86).
;
; - `CS:[SI + label]` is a memory access where:
;     * `CS:` says "use the Code Segment register as the base"
;     * `[SI + label]` is the offset, computed at runtime as the contents
;       of register SI plus the constant `label`.
;   In this flat single-segment driver, every read/write to driver state
;   uses CS: because the data and code share one segment (the
;   `.MODEL TINY` directive sets that up). Reads from the patch bank use
;   ES: instead, because the game-supplied pointer was loaded into ES.
;
; - Every function below begins with `<name> PROC NEAR` and ends with
;   `<name> ENDP`. Inside, labels like `noff_drum:` are jump targets
;   local to that function (we prefix them with a short function nickname
;   so they don't collide with labels in other functions).
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
; Glossary of acronyms and terms used in this file
;
; MIDI primitives:
;   Channel     One of 16 logical sub-streams (0..15) inside a MIDI cable.
;               Each channel has its own program, volume, pan, pitch-bend,
;               etc. Channel 9 (0-indexed; "channel 10" in 1-indexed
;               literature) is by convention the percussion channel and
;               handled specially throughout this driver.
;   Note        A pitch identifier (0..127). 60 = middle C; +1 = one
;               semitone up. On the drum channel, the note number selects
;               which drum sound rather than a pitch.
;   Velocity    The "how hard was the key pressed" byte (0..127). A
;               note-on with velocity 0 is interpreted as a note-off
;               (see the hardware primer above).
;   Controller  See "CC" below.
;   Program     A patch number (0..127). MIDI's "Program Change" message
;               tells a synth "from now on, channel X should play notes
;               with patch Y". The mapping from program number to actual
;               instrument sound is the receiver's job.
;   Pitch bend  A 14-bit signed offset (split across two 7-bit MIDI
;               bytes) that detunes notes on a channel. Zero = center.
;
; Acronyms:
;   CC        MIDI Continuous Controller (e.g. CC#7 = main volume,
;             CC#10 = pan, CC#123 = all-notes-off).
;   DUDE      Dynamix's universal sound-driver container format. Every
;             driver is a flat binary beginning with DUDE header magic;
;             see the dispatch-ABI section above for the ABI it defines.
;   GM        General MIDI -- a 1991 standardization of patch numbers
;             and drum-map note numbers across MIDI synthesizers.
;   MPU-401   The Roland-defined ISA card that bridges the PC bus to
;             MIDI. Operates in "intelligent" or "UART" mode; this
;             driver uses UART mode.
;   MT-32     The Roland MT-32 multi-timbral synthesizer (1987). The
;             target receiver of every MIDI byte this driver emits.
;   PC        Program Change (MIDI). Also Personal Computer.
;   SysEx     System-Exclusive MIDI message: a vendor-defined byte
;             stream beginning with 0xF0 and ending with 0xF7.
;             *This driver does not emit any SysEx* -- that's the
;             "noload" deviation from the production M32 driver.
;   UART      Universal Asynchronous Receiver/Transmitter. The MPU-401's
;             "raw" mode where the host clocks bytes manually.
;
; Synthesis terms:
;   Patch /   Used interchangeably here. The set of synthesis parameters
;   Instrument that produce a specific sound. The MT-32 ships with 128
;   /Program  factory patches; the game uploads its own custom set via
;             SysEx in the production M32 driver (not in NLD). When the
;             game asks "play note 60 on channel 3 using program 17",
;             the receiver looks up program 17's patch and synthesizes
;             note 60 with those parameters.
;             (Note: this driver does NOT have "voices" or "operators"
;             in the FM-synthesis sense -- those are AdLib/OPL2 concepts.
;             The MT-32 is a remote synth; voice allocation happens
;             inside the MT-32, not in this driver.)
;
; x86 / DOS terms used below:
;   Segment   A 64 KB region of physical memory. Real-mode addresses
;             are `segment:offset` pairs; the physical address is
;             segment*16 + offset.
;   Near call A subroutine call whose target is in the SAME segment as
;             the caller (uses a 16-bit offset only). PROC NEAR
;             functions in this file are called with near calls.
;   Far call  A call across segments (uses a 32-bit `seg:off` target).
;             The game invokes the dispatch trampoline with a far call;
;             RETF returns to the corresponding return address.
;   CS:[...]  A memory access that uses the Code Segment register as
;             the base. In our TINY model CS = DS = SS, so reading
;             driver state via CS: is equivalent to reading via DS:. (ES
;             is used separately for the patch-bank load in slot 1.)
; ----------------------------------------------------------------------------

                .8086
                .MODEL  TINY
                .CODE
                ORG     0

; ============================================================================
; 0x0000  --  DUDE header
; ============================================================================
_start          LABEL   BYTE
                JMP     nld_dispatch                ; E9 A6 05

                DB      0                           ; pad_03

dude_magic_a    DD      87654321H               ; "this is a DUDE file" sentinel
dude_iface_ver  DB      1, 4                    ; major=1, minor=4 (DUDE ABI ver)
dude_tag        DB      'dude'                  ; ASCII tag

device_name_len DB      36
device_name     DB      'MT32GM MPU noload (not for shipping)'

dude_magic_b    DD      0FEDCBA98H
dude_driver_kind DD     200H                        ; = 0x200 (MIDI class)
driver_ver_str  DB      'v1.06'

; ============================================================================
; 0x0040..0x04BF  --  patch-bank scratch buffer (uninitialized, 0xFF)
;
;   The game's slot-1 caller hands us a far pointer (ES:AX) to a patch
;   bank in its address space. The driver copies the first 0x481 bytes
;   into this region. Layout, inferred from the access patterns in the
;   slot handlers:
;
;     0x0040..0x00BF  (128 bytes)  patch-bank table A  -- read at
;                                  [cs:si+0x40] in program-change handler
;     0x00C0..0x013F  (128 bytes)  patch-bank table B  -- read at
;                                  [cs:si+0xC0]
;     0x0140..0x01BF  (128 bytes)  patch-bank table C  -- read at
;                                  [cs:si+0x140]
;     0x01C0..0x023F  (128 bytes)  drum-map note remap -- read at
;                                  [cs:si+0x1C0] in note handlers when
;                                  channel == 9 (drums)
;     0x0240..0x02BF  (128 bytes)  patch-bank table D  -- read at
;                                  [cs:si+0x241]; byte 0x240 is also
;                                  separately copied to 0x55C at the
;                                  end of load_patch_bank
;     0x02C0..0x03FF  (320 bytes)  patch-bank table E (160 words) -- read
;                                  at [cs:di+0x2C1] (word, stride 2)
;     0x0400..0x04BF  (192 bytes)  patch-bank trailing region
;
;   These regions are filled to 0xFF at link time so that the "no patch
;   bank loaded yet" state behaves like a sentinel (every program is
;   "not yet defined").
;
;   In the production M32 driver, slot 1 (load_patch_bank) ALSO walks a
;   SysEx upload table appended after offset 0x4C0 of the source buffer
;   and forwards each block out the MPU-401 to teach the MT-32 the
;   game's custom timbres. THIS DRIVER DOES NOT DO THAT -- see Notes at
;   top of file.
; ============================================================================
nld_bank_buf    DB      128 DUP(0FFH)           ; 0x40..0xBF (FF-init)
                DB      1024 DUP(000H)          ; 0xC0..0x4BF (zero-init)

; Symbolic offsets into nld_bank_buf for the named subregions used below.
nld_bank_drum_remap EQU nld_bank_buf + 180H     ; +0x1C0 = drum note remap
nld_bank_drum_vel   EQU nld_bank_buf + 280H     ; +0x2C0 = drum velocity (word)

; ============================================================================
; 0x04C0  --  global driver state (three scalar bytes)
;
;   nld_global_param        -- reserved scalar (semantics unconfirmed).
;                              Initialized to 0. Not currently read by
;                              any code in this driver; this is the byte
;                              that load_patch_bank writes into via the
;                              tail "0x4C0 area" copy from the patch
;                              bank's 0x481st byte (i.e. position 0 of
;                              the trailing globals region).
;   nld_master_volume       -- master attenuation, 0..0x7F. Initialized
;                              to 0x0F = midrange. Slot 12 reads/writes
;                              this; subsequent program-change handling
;                              uses it to scale the per-channel volume
;                              we forward to the MT-32.
;   nld_master_enable       -- 0 = driver muted, 1 = active. Initialized
;                              to 1. Slot 13 toggles it; when cleared,
;                              the driver synthesizes all-notes-off CCs
;                              for every channel before silencing.
; ============================================================================
nld_global_param     DB 000H
nld_master_volume    DB 00FH
nld_master_enable    DB 001H

; ============================================================================
; 0x04C3..0x04D2  --  per-MIDI-channel current program (16 bytes)
;
;   nld_ch_program[ch] is the last patch number we forwarded to the MT-32
;   on channel `ch`. Initialized to 0xFF to mean "no program set yet".
;   Slot 8 (program change) caches new values here and forwards them
;   immediately as a wire-format 0xCn message.
;
;   Slot 17 (query) returns this when asked for AH=0xC0 ("program-change
;   class").
; ============================================================================
nld_ch_program       DB 16 DUP(0FFH)

; ============================================================================
; 0x04D3..0x04F2  --  per-MIDI-channel pitch-bend (16 words, 32 bytes)
;
;   nld_ch_pitchbend[ch] caches the last pitch-bend value we sent on
;   channel `ch`. Stored as a 14-bit MIDI value packed into one word
;   little-endian. Initialized to 0xFFFF (= "not yet set"; treated as
;   sentinel by the renderer).
;
;   Slot 10 (pitch bend) caches new values here and forwards them as a
;   wire-format 0xEn message.
;
;   Slot 17 returns this when asked for AH=0xE0 ("pitch-bend class");
;   the high/low halves are swapped on return so the caller receives
;   them in the protocol's natural MSB-first order rather than the
;   wire's LSB-first order.
; ============================================================================
nld_ch_pitchbend     DW 16 DUP(0FFFFH)

; ============================================================================
; 0x04F3..0x0502  --  per-MIDI-channel modulation / CC#1 (16 bytes)
;
;   Slot 17 returns this when asked for AH=0xB0, CH=0x01 ("modulation
;   controller"). The driver does not currently write into this array
;   from any non-query path, so the read returns the initial 0xFF
;   sentinel until set externally. (Possibly stubbed for a controller
;   the production driver implements but this no-load test build does
;   not.)
; ============================================================================
nld_ch_modulation    DB 16 DUP(0FFH)

; ============================================================================
; 0x0503..0x0512  --  per-MIDI-channel main volume (CC#7) (16 bytes)
;
;   nld_ch_volume[ch] is the last main-volume CC value we forwarded to
;   the MT-32 on channel `ch`. Initialized to 0xFF = "not yet set".
;   Slot 7 caches CC#7 here, then forwards a wire-format 0xBn message
;   (subject to master-enable gating). The master-volume helper at
;   nld_set_master_volume also re-forwards every channel's cached
;   volume whenever master is unmuted.
;
;   Slot 17 returns this when asked for AH=0xB0, CH=0x07.
; ============================================================================
nld_ch_volume        DB 16 DUP(0FFH)

; ============================================================================
; 0x0513..0x0522  --  per-MIDI-channel pan (CC#10) (16 bytes)
;
;   nld_ch_pan[ch] caches CC#10. Slot 17 returns this when asked for
;   AH=0xB0, CH=0x0A.
; ============================================================================
nld_ch_pan           DB 16 DUP(0FFH)

; ============================================================================
; 0x0523..0x0532  --  per-MIDI-channel CC#40 cache (16 bytes)
;
;   Caches CC#40 (data-entry LSB / various). Slot 17 returns this when
;   asked for AH=0xB0, CH=0x40. The driver does not appear to use this
;   beyond mirroring it to the query API.
; ============================================================================
nld_ch_cc40          DB 16 DUP(0FFH)

; ============================================================================
; 0x0533..0x0542  --  per-MIDI-channel "enabled" flag (16 bytes)
;
;   nld_ch_enabled[ch] = 1 -> channel is responding to messages, 0 ->
;   channel is suppressed. Default = 1 for all 16 channels. The
;   control-change handler clears this on CC#123 ("all notes off" /
;   "all sound off") so subsequent program-changes for that channel are
;   suppressed until a fresh note-on revives it.
; ============================================================================
nld_ch_enabled       DB 16 DUP(001H)

; ============================================================================
; 0x0543..0x0552  --  per-MIDI-channel transpose offset (16 bytes)
;
;   nld_ch_transpose[ch]: semitone transpose offset added to every outgoing
;   note number on this channel. Cached from patch-bank table B (byte at
;   bank+0x80+program) by the program-change handler, then applied by the
;   note-on and note-off handlers via a wrap-around clamp into [0x00,0x7F].
;
;   The byte is signed in MIDI "8-bit two's complement" style: values
;   0x00..0x7F are positive semitone offsets, values 0x80..0xFF are
;   negative (= byte - 0x100). The note handlers detect the sign by
;   comparing against 0x80 and pick the wrap direction (octave-down for
;   positive, octave-up for negative) accordingly.
;
;   Cold-boot default 0 = identity transpose.
; ============================================================================
nld_ch_transpose     DB 16 DUP(000H)

; ============================================================================
; 0x0553..0x0562  --  per-MIDI-channel extra state A (16 bytes)
;
;   Read by the program-change handler from offset 0x553. Semantics
;   unconfirmed; default 0.
; ============================================================================
nld_ch_extra1        DB 16 DUP(000H)

; ============================================================================
; 0x0563..0x0572  --  per-MIDI-channel extra state B (16 bytes)
;
;   Read by the program-change handler as `[si+0x563]` and used in a
;   multiply (`mul byte [cs:si+0x563]`) in the note-on path. Looks like
;   a per-channel scaling factor applied to drum-channel velocities.
; ============================================================================
nld_ch_extra2        DB 16 DUP(000H)

; ============================================================================
; 0x0573..0x0582  --  per-MIDI-channel voice-active flag (16 bytes)
;
;   nld_ch_voice_active[ch]: a per-channel "have we sent a program-change
;   yet?" flag. The program-change handler initializes the channel's
;   state when this is 0xFF and clears it otherwise; the note handlers
;   check it before sending a note-on (no note without a known patch).
; ============================================================================
nld_ch_voice_active  DB 16 DUP(000H)

; ============================================================================
; 0x0583  --  last-MIDI-status byte (running-status cache)
;
;   nld_midi_send writes the (status|channel) byte it just sent to the
;   MPU here. Currently the cache is written but never read; in the
;   production M32 driver the same byte is presumably consulted to skip
;   redundant status bytes on the wire ("running status"), but this
;   no-load test build doesn't actually do that suppression.
; ============================================================================
nld_last_status      DB 000H

; ============================================================================
; 0x0584  --  global parameter 11 (slot-11 storage)
;
;   Slot 11 (set_global_param_11d) reads from and writes to this byte.
;   When CL == 0xFF the slot returns the current value in AL without
;   modifying it (query mode); otherwise it stores CL here. Semantics
;   unconfirmed -- likely a tempo or transpose knob (unresolved).
; ============================================================================
nld_global_param_11d DB 000H

; ============================================================================
; 0x0585  --  dispatch function table (18 near pointers)
;
;   One word per slot, indexed by `BP * 2` from the dispatch trampoline.
;   Reserved slots (3, 6, 9, 14, 15, 16) all point at the shared
;   nld_slot_unused_ret stub.
; ============================================================================
nld_func_table  LABEL WORD
                DW      nld_get_info                ; slot 0
                DW      nld_load_patch_bank         ; slot 1
                DW      nld_reset_voices            ; slot 2
                DW      nld_slot_unused_ret         ; slot 3
                DW      nld_midi_note_off           ; slot 4
                DW      nld_midi_note               ; slot 5
                DW      nld_slot_unused_ret         ; slot 6
                DW      nld_midi_control_change     ; slot 7
                DW      nld_midi_program_change     ; slot 8
                DW      nld_slot_unused_ret         ; slot 9
                DW      nld_midi_pitch_bend         ; slot 10
                DW      nld_set_global_param_11d    ; slot 11
                DW      nld_set_master_volume       ; slot 12
                DW      nld_set_master_enable       ; slot 13
                DW      nld_slot_unused_ret         ; slot 14
                DW      nld_slot_unused_ret         ; slot 15
                DW      nld_slot_unused_ret         ; slot 16
                DW      nld_query_state             ; slot 17

; ============================================================================
; 0x05A9  --  dispatch trampoline
;
;   The game's only entry point. Receives BP = slot index plus per-slot
;   argument registers and CALLs through the function table. The handlers
;   are NEAR procs; this trampoline turns the NEAR result back into the
;   FAR return the game-side caller expects.
;
;   Type:        Trampoline (entry point)
;   Category:    DUDE dispatch
;   Callers:     Game (via `CALL FAR nld_seg:nld_dispatch`)
;   Callees:     One of the 18 handler PROCs, selected via nld_func_table.
;
;   Inputs:
;     BP  --  slot index (0..17). The game multiplies/scales nothing;
;             this trampoline shifts left to convert to a byte offset.
;     AL/CL/CH/ES:AX -- per-slot argument registers; see individual
;                        handlers and the slot table in the preamble.
;
;   Outputs:
;     AX/CX  --  per-slot return values; see individual handlers.
;
;   Touches:
;     DX is used as the indirect-call scratch register (saved/restored).
;     BP is NOT preserved -- on return BP = (slot * 2). See the
;     dispatch-ABI comment above for the discussion vs ADL's BP-saving
;     trampoline.
;
;   Side effects:
;     Whatever the selected handler does.
; ============================================================================
nld_dispatch    PROC NEAR
                PUSH    DX
                SHL     BP, 1
                MOV     DX, CS:[BP + nld_func_table]
                CALL    DX
                POP     DX
                RETF
nld_dispatch    ENDP

; ============================================================================
; 0x05B5  --  nld_slot_unused_ret  (shared no-op stub)
;
;   Slots 3, 6, 9, 14, 15, 16 all dispatch here. One byte (0xC3 = RET).
;   The cross-driver ABI reserves these slot numbers for features this
;   driver doesn't implement (e.g. percussion-only stops, drum-kit
;   select, polyphonic aftertouch); calling them is a fast no-op.
;
;   Type:        Slot handler (shared stub)
;   Category:    Reserved-slot placeholder
;   Dispatch:    Slots 3, 6, 9, 14, 15, 16 (all six share this entry)
;
;   Inputs:      none used
;   Outputs:     none
;   Side effects:none
; ============================================================================
nld_slot_unused_ret PROC NEAR
                RET
nld_slot_unused_ret ENDP

; ----------------------------------------------------------------------------
; 0x05B6  --  nld_set_global_param_11d  (slot 11)
;
;   Per the cross-driver ABI, slot 11 is the read/write port for a
;   driver-defined "global parameter" byte. The query convention is:
;   pass CL=0xFF to read the current value (returned in AL), pass any
;   other value to overwrite the cached byte.
;
;   Type:        Slot handler
;   Category:    Global state I/O
;   Dispatch:    Slot 11 (called by game as: BP=11, CL=value or 0xFF=query)
;
;   Inputs:
;     CL  --  new value, or 0xFF to query without modifying
;
;   Outputs:
;     AL  --  current value (after potential update)
;     AH  --  0 (cleared)
;
;   Side effects:
;     nld_global_param_11d <- CL (when CL != 0xFF)
; ----------------------------------------------------------------------------
nld_set_global_param_11d PROC NEAR
                MOV     AL, CS:[nld_global_param_11d]
                XOR     AH, AH
                CMP     CL, 0FFH                ; 0xFF = query mode
                JNE     SHORT sgp_write
                RET
sgp_write:      MOV     CS:[nld_global_param_11d], CL
                RET
nld_set_global_param_11d ENDP

; ----------------------------------------------------------------------------
; 0x05C8  --  nld_midi_note_off  (slot 4)
;
;   Forwards a MIDI note-off (0x8n) to the MT-32 via the MPU-401. On
;   the drum channel (channel 9) the incoming note is first remapped
;   through the drum-map table at offset 0x1C0 of the patch bank; this
;   lets the game use logical drum IDs that the bank translates to
;   physical MT-32 percussion notes. Off-bank drums (mapped entry =
;   0xFF) are silently dropped.
;
;   For melodic channels, the per-channel "voice-active" sentinel is
;   consulted: if the channel never received a program-change, the
;   note-off is dropped. A post-pitch wrap-around clamp drags out-of-
;   range notes back into [0x00, 0x7F] by adding 0x0C (one octave) or
;   0xF4 (one octave down) until they land in range.
;
;   Type:        Slot handler
;   Category:    MIDI dispatch
;   Dispatch:    Slot 4 (called by game as: BP=4, AL=ch, CH=note, CL=vel)
;
;   Inputs:
;     AL  --  MIDI channel (0..15)
;     CH  --  MIDI note number (0..127); drum notes are bank-remapped
;     CL  --  release velocity
;
;   Outputs:     none
;
;   Side effects:
;     Sends "0x80|ch, note, vel" out the MPU-401 (or nothing if dropped).
; ----------------------------------------------------------------------------
nld_midi_note_off PROC NEAR
                PUSH    AX
                PUSH    SI
                PUSH    CX

                ; Drum channel? Take the remap path.
                CMP     AL, 9
                JNE     SHORT noff_melodic

                ; Drum: remap CH (note) through bank table at 0x1C0.
                ; SI = note (low 7 bits); CH = bank[SI+0x1C0].
                XCHG    CH, CL
                MOV     SI, CX
                XCHG    CH, CL
                AND     SI, 7FH
                MOV     CH, CS:[SI + nld_bank_drum_remap]
                CMP     CH, 0FFH
                JE      SHORT noff_done
                JMP     SHORT noff_send_90      ; (sic) drum off goes via 0x90

noff_melodic:   MOV     SI, AX
                AND     SI, 0FH

                ; Drop if channel never had a program-change.
                CMP     BYTE PTR CS:[SI + nld_ch_voice_active], 0FFH
                JE      SHORT noff_done

                ; Apply per-channel transpose, then wrap-around clamp to
                ; [0x00, 0x7F]. The clamp step (AH) is chosen by the SIGN
                ; of the transpose: positive transpose (< 0x80) may push
                ; the note above 0x7F, so we wrap *down* by 12 semitones
                ; (AH = -12 = 0xF4); a negative transpose (>= 0x80) may
                ; push the note below 0x00 (i.e. above 0x7F after byte
                ; wrap), so we wrap *up* by 12 (AH = +12 = 0x0C). The loop
                ; iterates because a single 12-semitone correction may
                ; not be enough for extreme inputs.
                ADD     CH, CS:[SI + nld_ch_transpose]
                MOV     AH, 0F4H                ; default -12 (positive xpose)
                CMP     BYTE PTR CS:[SI + nld_ch_transpose], 80H
                JB      SHORT noff_clamploop    ; xpose positive: keep -12
                MOV     AH, 0CH                 ; xpose negative: use +12
noff_clamploop: CMP     CH, 80H
                JB      SHORT noff_send_90
                ADD     CH, AH
                JMP     SHORT noff_clamploop

                ; Note-off is implemented by sending a note-on with
                ; velocity 0 (MIDI running-status idiom). That's why
                ; AH becomes 0x90 here, not 0x80.
noff_send_90:   MOV     AH, 90H
                MOV     CL, 0
                CALL    nld_midi_send

noff_done:      POP     CX
                POP     SI
                POP     AX
                RET
nld_midi_note_off ENDP

; ----------------------------------------------------------------------------
; 0x0616  --  nld_midi_note  (slot 5)
;
;   Forwards a MIDI note-on (0x9n) to the MT-32. Mirror of note-off
;   plus an extra step on the drum channel: the bank holds a per-drum
;   velocity scale at byte 0x2C1 (word-strided, two bytes per drum), and
;   the incoming velocity is replaced with that scaled value before
;   sending. Sets the channel's "enabled" flag to 1 as a side effect so
;   subsequent CC#123 ("all notes off") can clear it.
;
;   Type:        Slot handler
;   Category:    MIDI dispatch
;   Dispatch:    Slot 5 (called by game as: BP=5, AL=ch, CH=note, CL=vel)
;
;   Inputs:
;     AL  --  MIDI channel (0..15)
;     CH  --  MIDI note number (0..127); drum notes are bank-remapped
;     CL  --  velocity (0..127)
;
;   Outputs:     none
;
;   Side effects:
;     Sends "0x90|ch, note, vel" out the MPU-401 (or nothing if dropped).
;     nld_ch_enabled[channel] <- 1 (set unconditionally on every note-on,
;     both drum and melodic; the post-clamp join point is shared -- see
;     the non_vel_remap rejoin below for the actual write site).
; ----------------------------------------------------------------------------
nld_midi_note   PROC NEAR
                PUSH    AX
                PUSH    SI
                PUSH    CX
                PUSH    DI

                CMP     AL, 9
                JNE     SHORT non_melodic

                ; Drum path: remap CH through bank table at 0x1C0.
                XCHG    CH, CL
                MOV     SI, CX
                XCHG    CH, CL
                AND     SI, 7FH
                MOV     CH, CS:[SI + nld_bank_drum_remap]
                CMP     CH, 0FFH
                JE      SHORT non_done

                ; SI = channel index (= 9, but kept as a 16-bit-clean
                ; index into the 16-byte per-channel arrays).
                MOV     SI, AX
                AND     SI, 0FH
                JMP     SHORT non_vel_remap

non_melodic:    MOV     SI, AX
                AND     SI, 0FH

                ; Drop if channel never had a program-change.
                CMP     BYTE PTR CS:[SI + nld_ch_voice_active], 0FFH
                JE      SHORT non_done

                ; Apply per-channel transpose + wrap-around clamp,
                ; same as note-off. See nld_midi_note_off for the
                ; explanation of the sign-dependent AH choice.
                ADD     CH, CS:[SI + nld_ch_transpose]
                MOV     AH, 0F4H                ; default -12 (positive xpose)
                CMP     BYTE PTR CS:[SI + nld_ch_transpose], 80H
                JB      SHORT non_clamp_mel ; xpose positive: keep -12
                MOV     AH, 0CH                 ; xpose negative: use +12
non_clamp_mel:  CMP     CH, 80H
                JB      SHORT non_vel_remap
                ADD     CH, AH
                JMP     SHORT non_clamp_mel

                ; Velocity remap + send. BOTH the drum path (JMP above) and
                ; the melodic path (fall-through here once the clamp loop
                ; exits) end up at this label; the name is "vel_remap"
                ; rather than "drum_vel" because it serves both.
                ;
                ;   DI = (orig_vel & 0x7F) + (0x80 * nld_ch_extra2[ch])
                ;   CL = nld_bank_drum_vel[DI*2 + 1]    ; word-strided
                ;
                ; For the drum channel `extra2[ch]` selects a velocity
                ; sub-table within the bank's 0x2C1 region, so different
                ; drum patches can have different velocity curves. For
                ; melodic channels `extra2[ch]` is typically 0, so the MUL
                ; produces 0, DI = velocity & 0x7F, and the look-up
                ; degenerates to `bank_drum_vel[velocity * 2 + 1]` -- still
                ; a remap, but applied uniformly per-velocity rather than
                ; per-drum.
                ;
                ; nld_ch_enabled[ch] is then set to 1 for every note-on so
                ; subsequent CC#123 ("all notes off") has a flag to clear.
non_vel_remap:  PUSH    AX
                MOV     AL, 80H
                MUL     BYTE PTR CS:[SI + nld_ch_extra2]
                MOV     DI, CX
                AND     DI, 7FH
                ADD     DI, AX
                POP     AX
                MOV     CL, CS:[DI + nld_bank_drum_vel + 1]
                MOV     BYTE PTR CS:[SI + nld_ch_enabled], 1
                MOV     AH, 90H
                CALL    nld_midi_send

non_done:       POP     DI
                POP     CX
                POP     SI
                POP     AX
                RET
nld_midi_note   ENDP

; ----------------------------------------------------------------------------
; 0x0684  --  nld_midi_control_change  (slot 7)
;
;   Forwards a MIDI control-change (0xBn) to the MT-32 and caches a few
;   well-known controllers in our per-channel state. Recognized:
;
;     CC#0x07  Main Volume       -- scaled by master_volume and stored
;     CC#0x0A  Pan               -- stored only if changed
;     CC#0x40  Sustain Pedal     -- stored only if changed
;     CC#0x7B  All Notes Off     -- clears the channel "enabled" flag
;     others   passed through unchanged
;
;   Type:        Slot handler
;   Category:    MIDI dispatch
;   Dispatch:    Slot 7 (called by game as: BP=7, AL=ch, CH=cc#, CL=value)
;
;   Inputs:
;     AL  --  MIDI channel (0..15)
;     CH  --  controller number (0..127)
;     CL  --  controller value (0..127)
;
;   Outputs:     none
;
;   Side effects:
;     Mirror the appropriate per-channel cache slot; emit a wire 0xBn
;     message (subject to master-enable gate and short-circuits).
; ----------------------------------------------------------------------------
nld_midi_control_change PROC NEAR
                PUSH    AX
                PUSH    SI
                MOV     SI, AX
                AND     SI, 0FH
                AND     CL, 7FH

                ; CC#7 = Main Volume -- the most common path, so it's
                ; checked first and has its own scaling logic.
                CMP     CH, 7
                JNE     SHORT cc_check_pan

                MOV     CS:[SI + nld_ch_volume], CL

                ; Test master_enable. JNE branches to the scaler when
                ; the master is active (= 1, the common case); otherwise
                ; fall into the JMP that skips the wire send.
                CMP     BYTE PTR CS:[nld_master_enable], 0
                JNE     SHORT cc_vol_scale      ; active -> scale and send
                JMP     SHORT cc_done           ; muted  -> drop on the floor

                ; Scale: CL = clamp((CL + extra1[ch]), 1..0x7F),
                ; then CL = (CL * master_volume) / 15.
cc_vol_scale:   ADD     CL, CS:[SI + nld_ch_extra1]
                CMP     CL, 80H
                JB      SHORT cc_vol_havemul
                MOV     CL, 7FH                 ; clamp to max
                CMP     BYTE PTR CS:[SI + nld_ch_extra1], 80H
                JB      SHORT cc_vol_havemul
                MOV     CL, 1                   ; floor when underflow
cc_vol_havemul: MOV     CH, AL                  ; save channel
                MOV     AL, CS:[nld_master_volume]
                MUL     CL
                MOV     CL, 0FH
                DIV     CL                      ; AL = (AL*CL)/15
                MOV     CL, AL
                MOV     AL, CH                  ; restore channel
                MOV     CH, 7                   ; CC# for the wire
                OR      CL, CL                  ; if 0, set to 1
                JNE     SHORT cc_send
                OR      AH, AH                  ; (AH is "high half" left
                                                ; from MUL; if both clean
                                                ; jump to send with
                                                ; vel=0)
                JE      SHORT cc_send
                INC     CL
                JMP     SHORT cc_send

                ; CC#10 = Pan -- skip wire send if unchanged.
cc_check_pan:   CMP     CH, 0AH
                JNE     SHORT cc_check_cc40
                CMP     CS:[SI + nld_ch_pan], CL
                JE      SHORT cc_done
                MOV     CS:[SI + nld_ch_pan], CL
                JMP     SHORT cc_send

                ; CC#40 -- skip wire send if unchanged.
cc_check_cc40:  CMP     CH, 40H
                JNE     SHORT cc_check_anoff
                CMP     CS:[SI + nld_ch_cc40], CL
                JE      SHORT cc_done
                MOV     CS:[SI + nld_ch_cc40], CL
                JMP     SHORT cc_send

                ; CC#0x7B = All Notes Off -- only emit if the channel
                ; is currently flagged enabled, then clear that flag.
                ; Unrecognized CC#s (anything other than 7/10/40/7B) skip
                ; the wire send entirely.
cc_check_anoff: CMP     CH, 7BH
                JNE     SHORT cc_done
                CMP     BYTE PTR CS:[SI + nld_ch_enabled], 0
                JE      SHORT cc_done
                MOV     BYTE PTR CS:[SI + nld_ch_enabled], 0

cc_send:        MOV     AH, 0B0H
                CALL    nld_midi_send
cc_done:        POP     SI
                POP     AX
                RET
nld_midi_control_change ENDP

; ----------------------------------------------------------------------------
; 0x0717  --  nld_midi_program_change  (slot 8)
;
;   Forwards a MIDI program-change (0xCn) to the MT-32 and updates a
;   pile of per-channel caches from the patch bank: program number,
;   bank-table A/B/C/D entries, and re-emits cached volume/sustain if
;   they changed. Channel 9 (drums) does not need a program-change at
;   all and short-circuits early.
;
;   Type:        Slot handler
;   Category:    MIDI dispatch
;   Dispatch:    Slot 8 (called by game as: BP=8, AL=ch, CL=program)
;
;   Inputs:
;     AL  --  MIDI channel (0..15)
;     CL  --  patch / program number (0..127)
;
;   Outputs:     none
;
;   Side effects:
;     Caches CL in nld_ch_program[ch], populates extra1/extra2/etc. from
;     the patch bank, optionally re-forwards 0xBn,0x7B,0 (all notes off)
;     and re-forwards updated volume/sustain.
; ----------------------------------------------------------------------------
nld_midi_program_change PROC NEAR
                PUSH    AX
                PUSH    SI
                PUSH    CX
                PUSH    BX

                CMP     AL, 9
                JE      SHORT pc_done  ; drums: nothing to do

                MOV     SI, AX
                AND     SI, 0FH

                ; Skip if program already set to this value.
                CMP     CS:[SI + nld_ch_program], CL
                JE      SHORT pc_done
                MOV     CS:[SI + nld_ch_program], CL

                ; SI = program index for the patch-bank lookups.
                MOV     SI, CX
                AND     SI, 7FH
                MOV     CL, CS:[SI + nld_bank_buf]              ; bank_A
                MOV     CH, CS:[SI + nld_bank_buf + 80H]        ; bank_B
                MOV     BH, CS:[SI + nld_bank_buf + 100H]       ; bank_C
                MOV     BL, CS:[SI + nld_bank_buf + 201H]       ; bank_D+1

                ; Switch SI back to channel index.
                MOV     SI, AX
                AND     SI, 0FH

                MOV     CS:[SI + nld_ch_extra2], BL

                ; If channel was previously inactive (0xFF) we need to
                ; re-emit volume after the program change.
                XOR     BL, BL
                CMP     BYTE PTR CS:[SI + nld_ch_voice_active], 0FFH
                JNE     SHORT pc_remember_act
                INC     BL                      ; mark "was inactive"
pc_remember_act: MOV    CS:[SI + nld_ch_voice_active], CL

                ; bank_A == 0xFF -> patch is undefined; turn channel off
                ; and don't send the program change.
                CMP     CL, 0FFH
                JNE     SHORT pc_emit
                MOV     AH, 0B0H
                MOV     CH, 7BH
                XOR     CL, CL
                CALL    nld_midi_send
pc_done:        JMP     SHORT pc_finish

                ; Refresh the channel's transpose offset from bank table B
                ; (byte at bank+0x80+program, currently in CH). If it
                ; changed, send an "all notes off" (CC#123 = 0x7B) on
                ; the channel so any still-ringing notes don't play out
                ; at the new transpose.
pc_emit:        CMP     CH, CS:[SI + nld_ch_transpose]
                JE      SHORT pc_check_extra1
                MOV     CS:[SI + nld_ch_transpose], CH
                PUSH    CX
                MOV     AH, 0B0H
                MOV     CH, 7BH
                XOR     CL, CL
                CALL    nld_midi_send
                POP     CX
                INC     BL

pc_check_extra1: OR     BL, BL
                JNE     SHORT pc_force_vol
                CMP     BH, CS:[SI + nld_ch_extra1]
                JE      SHORT pc_send_pc
pc_force_vol:   MOV     CS:[SI + nld_ch_extra1], BH
                PUSH    CX
                MOV     CL, CS:[SI + nld_ch_volume]
                MOV     CH, 7
                CALL    nld_midi_control_change
                POP     CX

pc_send_pc:     MOV     AH, 0C0H
                CALL    nld_midi_send

                ; Re-emit pan if any of the above mutated things.
                OR      BL, BL
                JE      SHORT pc_finish
                MOV     AH, 0B0H
                MOV     CH, 0AH
                MOV     CL, CS:[SI + nld_ch_pan]
                AND     CL, 7FH
                CALL    nld_midi_send

                ; Re-emit pitch-bend.
                SHL     SI, 1
                MOV     CL, BYTE PTR CS:[SI + nld_ch_pitchbend]
                AND     CL, 7FH
                MOV     CH, BYTE PTR CS:[SI + nld_ch_pitchbend + 1]
                AND     CH, 7FH
                MOV     AH, 0E0H
                CALL    nld_midi_send

pc_finish:      POP     BX
                POP     CX
                POP     SI
                POP     AX
                RET
nld_midi_program_change ENDP

; ----------------------------------------------------------------------------
; 0x07DD  --  nld_midi_pitch_bend  (slot 10)
;
;   Forwards a MIDI pitch-bend (0xEn) to the MT-32 if the cached value
;   for the channel changes. The wire format puts the low 7 bits first
;   (CL) and the high 7 bits second (CH).
;
;   Type:        Slot handler
;   Category:    MIDI dispatch
;   Dispatch:    Slot 10 (called by game as: BP=10, AL=ch, CL=lo, CH=hi)
;
;   Inputs:
;     AL  --  MIDI channel (0..15)
;     CL  --  pitch-bend low 7 bits
;     CH  --  pitch-bend high 7 bits
;
;   Outputs:     none
;
;   Side effects:
;     nld_ch_pitchbend[channel] <- CX (when different); sends 0xEn pair.
; ----------------------------------------------------------------------------
nld_midi_pitch_bend PROC NEAR
                PUSH    AX
                PUSH    SI
                MOV     SI, AX
                AND     SI, 0FH
                SHL     SI, 1                   ; word-stride
                CMP     BYTE PTR CS:[SI + nld_ch_pitchbend], CL
                JNE     SHORT pb_update
                CMP     BYTE PTR CS:[SI + nld_ch_pitchbend + 1], CH
                JE      SHORT pb_done
pb_update:      MOV     BYTE PTR CS:[SI + nld_ch_pitchbend], CL
                MOV     BYTE PTR CS:[SI + nld_ch_pitchbend + 1], CH
                MOV     AH, 0E0H
                CALL    nld_midi_send
pb_done:        POP     SI
                POP     AX
                RET
nld_midi_pitch_bend ENDP

; ----------------------------------------------------------------------------
; 0x0806  --  nld_midi_send  (internal helper)
;
;   The single point through which every outgoing MIDI byte leaves this
;   driver. Receives:
;     AH = MIDI status base (e.g. 0x90 for note-on)
;     AL = MIDI channel (low 4 bits matter)
;     CH = first data byte (e.g. note number)
;     CL = second data byte (e.g. velocity), or unused for 1-byte
;          program-change / channel-pressure messages
;
;   Combines AH|AL into the status byte, writes it via the MPU-data
;   helper, then writes CH (if applicable) and CL.
;
;   Type:        Helper
;   Category:    MPU-401 framing
;
;   Inputs:
;     AH  --  status base (top 4 bits identify the message type)
;     AL  --  MIDI channel (only low 4 bits used)
;     CH  --  first data byte
;     CL  --  second data byte (skipped for 0xCn and 0xDn)
;
;   Outputs:     none
;
;   Side effects:
;     Writes 2 or 3 bytes to MPU-401 port 0x330.
;     nld_last_status <- combined status byte.
;
;   Notes:
;     0xCn (program change) and 0xDn (channel aftertouch) are 1-data-byte
;     messages; this routine special-cases them to skip CH.
; ----------------------------------------------------------------------------
nld_midi_send   PROC NEAR
                PUSH    BX

                ; Combine status + channel and cache it.
                MOV     DL, AL
                OR      DL, AH
                MOV     CS:[nld_last_status], DL

                ; Send status byte.
                MOV     BL, DL
                CALL    nld_mpu_send_data

                ; 0xCn and 0xDn are 1-byte; skip CH for them.
                CMP     AH, 0C0H
                JE      SHORT ms_send_cl
                CMP     AH, 0D0H
                JE      SHORT ms_send_cl
                MOV     BL, CH
                CALL    nld_mpu_send_data

ms_send_cl:     MOV     BL, CL
                CALL    nld_mpu_send_data
                POP     BX
                RET
nld_midi_send   ENDP

; ----------------------------------------------------------------------------
; 0x082B  --  nld_reset_voices  (slot 2)
;
;   Sends the MPU-401's own reset command (0xFF on the *command* port,
;   not on the MIDI wire). Followed by re-entering UART mode would
;   normally happen in slot 1; the bare reset here puts the MPU back in
;   a known state and silences any in-flight notes the MT-32 was holding.
;
;   Type:        Slot handler
;   Category:    Hardware reset
;   Dispatch:    Slot 2 (called by game as: BP=2)
;
;   Inputs:      none
;   Outputs:     none
;
;   Side effects:
;     Writes 0xFF to MPU-401 command port 0x331 via nld_mpu_reset.
; ----------------------------------------------------------------------------
nld_reset_voices PROC NEAR
                PUSH    BX
                CALL    nld_mpu_reset
                POP     BX
                RET
nld_reset_voices ENDP

; ----------------------------------------------------------------------------
; 0x0831  --  nld_mpu_send_command  (internal helper, MPU command port)
;
;   Sends BL to the MPU-401's *command* port (0x331). Compare with
;   nld_mpu_send_data, which sends to the *data* port (0x330).
;
;   The protocol: poll port 0x331 for "ready" (bit 6 clear), write BL,
;   then poll for the ACK byte (0xFE) from port 0x330. Both polls have
;   a 0xFFFF-iteration timeout so a missing MPU doesn't hang the game.
;
;   Type:        Helper
;   Category:    MPU-401 hardware I/O
;
;   Inputs:
;     BL  --  command byte
;
;   Outputs:     none
;
;   Side effects:
;     One write to port 0x331; up to 0x1FFFE polled reads of port
;     0x331/0x330. CLI/STI bracket; interrupts are masked across the
;     entire transaction.
; ----------------------------------------------------------------------------
nld_mpu_send_command PROC NEAR
                PUSHF
                CLI
                PUSH    AX
                PUSH    CX
                PUSH    DX

                MOV     CX, 0FFFFH              ; ready-poll budget
                MOV     DX, 331H                ; command/status port
msc_ready:      IN      AL, DX
                TEST    AL, 40H                 ; bit 6 = "not ready"
                JE      SHORT msc_ready_ok
                DEC     CX
                CMP     CX, 0
                JNE     SHORT msc_ready
                JMP     SHORT msc_done          ; timed out

msc_ready_ok:   MOV     AL, BL
                OUT     DX, AL                  ; write command byte
                MOV     CX, 0FFFFH              ; ack-poll budget
msc_ack:        IN      AL, DX
                ROL     AL, 1                   ; CF = bit 7 (data avail)
                JAE     SHORT msc_check_ack     ; if no data, ROL puts 0 in CF
                DEC     CX
                CMP     CX, 0
                JNE     SHORT msc_ack
                ; Fall through to msc_check_ack (no explicit jmp). Both
                ; the "ack-poll timed out" path and the "data byte is
                ; available" path land at the same tail block, which
                ; reads port 0x330 for the actual byte the MPU sent us.
                ;
                ; The CMP/JE on 0xFE below is functionally a no-op: both
                ; arms (`JE msc_done` and the fall-through) end up at
                ; msc_done anyway.

msc_check_ack:  MOV     DX, 330H                ; data port
                IN      AL, DX
                CMP     AL, 0FEH                ; ACK byte
                JE      SHORT msc_done

msc_done:       POP     DX
                POP     CX
                POP     AX
                POPF
                RET
nld_mpu_send_command ENDP

; ----------------------------------------------------------------------------
; 0x0867  --  nld_mpu_send_data  (internal helper, MPU data port)
;
;   Sends BL out the MIDI cable via the MPU-401's data port (0x330).
;   This is what every outbound MIDI byte ends up calling.
;
;   Protocol: poll port 0x331 for ready (bit 6 clear), draining any
;   stray input bytes the MPU has buffered (bit 7 set in the status
;   byte means "input available on 0x330"; we read and discard each).
;   Once ready, write BL to 0x330.
;
;   Type:        Helper
;   Category:    MPU-401 hardware I/O
;
;   Inputs:
;     BL  --  byte to send
;
;   Outputs:     none
;
;   Side effects:
;     One write to port 0x330; up to 0xFF polled reads of port 0x331,
;     plus any number of drain-reads of port 0x330. CLI/STI bracket.
; ----------------------------------------------------------------------------
nld_mpu_send_data PROC NEAR
                PUSHF
                CLI
                PUSH    AX
                PUSH    CX
                PUSH    DX

                MOV     DX, 331H
                MOV     CX, 0FFH
msd_ready:      IN      AL, DX
                TEST    AL, 40H                 ; bit 6 = not-ready
                JE      SHORT msd_send
                DEC     CX
                ROL     AL, 1                   ; carry = bit 7 (input avail)
                JB      SHORT msd_skip_drain
                MOV     DX, 330H
                IN      AL, DX                  ; drain
                MOV     DX, 331H
msd_skip_drain: CMP     CX, 1
                JGE     SHORT msd_ready
                JMP     SHORT msd_done

msd_send:       MOV     DX, 330H
                MOV     AL, BL
                OUT     DX, AL

msd_done:       POP     DX
                POP     CX
                POP     AX
                POPF
                RET
nld_mpu_send_data ENDP

; ----------------------------------------------------------------------------
; 0x0895  --  nld_set_master_volume  (slot 12)
;
;   Read/write the master-volume byte. Query convention (CL=0xFF returns
;   without modifying) matches slot 11. When the master is also enabled
;   and a real value is being written, walk channels 1..9 and re-emit
;   each one's cached CC#7 (main volume) so the listener immediately
;   hears the new master scaling.
;
;   Type:        Slot handler
;   Category:    Global state
;   Dispatch:    Slot 12 (called by game as: BP=12, CL=value or 0xFF)
;
;   Inputs:
;     CL  --  new master volume, or 0xFF to query
;
;   Outputs:
;     AL  --  current master volume
;     AH  --  0
;
;   Side effects:
;     nld_master_volume <- CL (when not 0xFF); re-forwards CC#7 for
;     channels 1..9 when master is enabled.
; ----------------------------------------------------------------------------
nld_set_master_volume PROC NEAR
                PUSH    BX
                PUSH    CX
                PUSH    SI

                MOV     AL, CS:[nld_master_volume]
                XOR     AH, AH
                CMP     CL, 0FFH
                JE      SHORT smv_done          ; query mode

                MOV     CS:[nld_master_volume], CL

                ; Only re-emit if master is enabled.
                CMP     BYTE PTR CS:[nld_master_enable], 0
                JE      SHORT smv_done

                PUSH    AX
                MOV     AL, 1                   ; ch counter (1..9)
                MOV     SI, 1
                MOV     CH, 7                   ; CC# main volume
smv_each_ch:    MOV     CL, CS:[SI + nld_ch_volume]
                CMP     CL, 0FFH
                JE      SHORT smv_next
                CALL    nld_midi_control_change
smv_next:       INC     AL
                INC     SI
                CMP     AL, 0AH
                JNE     SHORT smv_each_ch
                POP     AX

smv_done:       POP     SI
                POP     CX
                POP     BX
                RET
nld_set_master_volume ENDP

; ----------------------------------------------------------------------------
; 0x08D1  --  nld_set_master_enable  (slot 13)
;
;   Read/write the master-enable flag. Query convention matches slot
;   11/12. When the flag transitions from 1 to 0, all 9 melodic channels
;   are explicitly silenced via CC#7=0 (volume=0). When it transitions
;   from 0 to 1, the set_master_volume path is replayed to re-establish
;   the cached per-channel volumes.
;
;   Type:        Slot handler
;   Category:    Global state
;   Dispatch:    Slot 13 (called by game as: BP=13, CL=value or 0xFF)
;
;   Inputs:
;     CL  --  new master-enable (0 = mute, 1 = active), or 0xFF to query
;
;   Outputs:
;     AL  --  current master-enable byte
;     AH  --  0 (cleared)
;
;   Side effects:
;     nld_master_enable <- CL when not 0xFF.
;     On 1->0 transition: 8 wire 0xBn 0x07 0x00 (CC#7=0) messages, one
;       per channel 1..8, to silence everything currently sounding.
;     On 0->1 transition: re-runs nld_set_master_volume(current_master)
;       to re-emit each channel's cached CC#7 at the new master scale.
; ----------------------------------------------------------------------------
nld_set_master_enable PROC NEAR
                XOR     AH, AH
                MOV     AL, CS:[nld_master_enable]
                CMP     CL, 0FFH
                JNE     SHORT sme_write
                RET
sme_write:      PUSH    AX
                PUSH    CX

                CMP     CL, 0
                JNE     SHORT sme_enable

                ; Disable: silence each of channels 1..8 via CC#7=0.
                MOV     BYTE PTR CS:[nld_master_enable], 0
                MOV     AL, 1
                MOV     AH, 0B0H
                MOV     CH, 7
                MOV     CL, 0
sme_silence:    CALL    nld_midi_send
                INC     AL
                CMP     AL, 9
                JNE     SHORT sme_silence
                POP     CX
                POP     AX
                RET

sme_enable:     MOV     BYTE PTR CS:[nld_master_enable], 1
                MOV     CL, CS:[nld_master_volume]
                CALL    nld_set_master_volume
                POP     CX
                POP     AX
                RET
nld_set_master_enable ENDP

; ----------------------------------------------------------------------------
; 0x090F  --  nld_mpu_reset  (internal helper)
;
;   Sends the MPU-401 reset command (0xFF on port 0x331). Wrapper
;   around nld_mpu_send_command that supplies the canonical reset byte.
;
;   Type:        Helper
;   Category:    MPU-401 hardware I/O
;   Callers:     nld_reset_voices (slot 2), nld_load_patch_bank (slot 1)
;   Callees:     nld_mpu_send_command
;
;   Inputs:      none
;   Outputs:     none
;
;   Side effects:
;     Writes 0xFF to MPU-401 command port 0x331; awaits ACK 0xFE on
;     port 0x330 (subject to the helper's poll-timeout budget).
; ----------------------------------------------------------------------------
nld_mpu_reset   PROC NEAR
                PUSH    BX
                MOV     BL, 0FFH
                CALL    nld_mpu_send_command
                POP     BX
                RET
nld_mpu_reset   ENDP

; ----------------------------------------------------------------------------
; 0x0917  --  nld_query_state  (slot 17)
;
;   Read-side of the per-channel setter ABI. Given (AH = MIDI-style
;   status class, AL = channel, CH = sub-selector), returns the current
;   cached value in AL or 0xFFFF if not recognized / not set.
;
;   Recognized classes:
;     AH = 0xE0  --  pitch bend (returned as one word, hi/lo swapped)
;     AH = 0xC0  --  program-change
;     AH = 0xB0  --  control-change, sub-selector in CH:
;                      CH = 0x01  -> modulation
;                      CH = 0x07  -> volume
;                      CH = 0x0A  -> pan
;                      CH = 0x40  -> CC40
;                      CH = 0x4B  -> always 0xFFFF (refusal)
;
;   Type:        Slot handler
;   Category:    Read-side API
;   Dispatch:    Slot 17 (called by game as: BP=17, AL=ch, AH=class, CH=sub)
;
;   Inputs:
;     AL  --  MIDI channel (0..15)
;     AH  --  MIDI status class (0xE0 / 0xC0 / 0xB0)
;     CH  --  sub-selector for the 0xB0 (CC) class
;
;   Outputs:
;     AX  --  cached value for the (channel, class, sub) query, or
;             0xFFFF when the class/sub isn't recognized or the
;             channel never set this property. For the 0xE0 class AX
;             is the pitch-bend packed as MSB-first wire bytes (NOT
;             the cached LSB-first form).
;
;   Side effects: none (pure read).
; ----------------------------------------------------------------------------
nld_query_state PROC NEAR
                PUSH    SI
                MOV     SI, AX
                AND     SI, 0FH

                CMP     AH, 0E0H
                JNE     SHORT qs_check_c0
                SHL     SI, 1
                MOV     AX, CS:[SI + nld_ch_pitchbend]
                ; `CMP AX, 0FFFFH` in the 8-bit-sign-extended form
                ; (83 F8 FF). TASM 3.1 would otherwise assemble the
                ; 16-bit-imm encoding (3D FF FF), so emit it manually.
                DB      83H, 0F8H, 0FFH
                ; If the channel never had a pitch bend, AX is already
                ; 0xFFFF so we don't need to JMP through qs_unknown to
                ; load that value into AX; we can just jump straight to
                ; the epilogue.
                JE      SHORT qs_done
                XCHG    AH, AL                  ; swap to MSB-first wire order
                SHR     AH, 1                   ; bit 0 -> CF, AH = top 7 bits
                JNB     SHORT qs_pb_no_low_bit
                OR      AL, 80H                 ; pack the carried bit into AL
qs_pb_no_low_bit: JMP   SHORT qs_done

qs_check_c0:    CMP     AH, 0C0H
                JNE     SHORT qs_check_b0
                MOV     AL, CS:[SI + nld_ch_program]
                JMP     SHORT qs_done

qs_check_b0:    CMP     AH, 0B0H
                JNE     SHORT qs_unknown
                CMP     CH, 4BH
                JE      SHORT qs_unknown
                CMP     CH, 1
                JNE     SHORT qs_check_07
                MOV     AL, CS:[SI + nld_ch_modulation]
                JMP     SHORT qs_done
qs_check_07:    CMP     CH, 7
                JNE     SHORT qs_check_0a
                MOV     AL, CS:[SI + nld_ch_volume]
                JMP     SHORT qs_done
qs_check_0a:    CMP     CH, 0AH
                JNE     SHORT qs_check_40
                MOV     AL, CS:[SI + nld_ch_pan]
                JMP     SHORT qs_done
qs_check_40:    CMP     CH, 40H
                JNE     SHORT qs_unknown
                MOV     AL, CS:[SI + nld_ch_cc40]
                JMP     SHORT qs_done

qs_unknown:     MOV     AX, 0FFFFH
qs_done:        POP     SI
                RET
nld_query_state ENDP

; ----------------------------------------------------------------------------
; 0x0983  --  nld_load_patch_bank  (slot 1)
;
;   *** This is the slot whose missing-functionality gave this driver
;   its "noload" suffix. ***
;
;   In the production M32 driver, slot 1 (load_patch_bank):
;     (a) resets the MPU and re-enters UART mode (3x 0x3F),
;     (b) copies the first 0x481 bytes of the supplied bank into local
;         scratch at 0x40..0x4C0,
;     (c) copies byte 0x240 of the bank to byte 0x55C of local state, and
;     (d) walks an appended (cnt, byte0, byte1, ..., 0xF7) SysEx upload
;         table at offset 0x481 of the bank and forwards each block via
;         the MPU so the MT-32 receives the game's custom patches.
;
;   This driver does (a), (b), and (c) -- but NOT (d). That makes it a
;   developer-test build: the channel maps work, programs map correctly
;   to MT-32 patch numbers, but the MT-32's own ROM presets are heard
;   instead of the game's authored timbres.
;
;   Type:        Slot handler
;   Category:    Driver init
;   Dispatch:    Slot 1 (called by game as: BP=1, ES:AX = bank src)
;
;   Inputs:
;     ES:AX  --  far pointer to the source patch bank
;
;   Outputs:
;     AX  --  0x0983 (this function's own offset; self-id handshake --
;             the game can check that AX equals the slot 1 entry point
;             advertised in the function table to confirm slot 1 is
;             actually wired up in this driver).
;     CX  --  0x0801 (CL=01, CH=08; format/version handshake, identical
;             to M32's slot 1). The exact field meanings are unconfirmed
;             but CH=8 matches across all DUDE drivers (ADL returns
;             AX=0x2446 / CX=0x0800, M32 returns AX=0x0961 / CX=0x0801).
;
;   Side effects:
;     Copies 0x481 bytes from ES:AX into local scratch at 0x40.
;     Copies one byte from bank+0x240 to 0x55C.
;     Calls set_master_volume(0x0C) to set master to 0x0C.
;
;   Notes:
;     The only thing MISSING vs M32 is the SysEx upload loop that M32
;     runs between the master-volume call and the self-id return-value
;     writes.
; ----------------------------------------------------------------------------
nld_load_patch_bank PROC NEAR
                PUSH    SI

                ; Reset MPU and enter UART mode 3 times. The 3x repeat
                ; is defensive: the MPU's "enter UART" command is also
                ; the command it sends to acknowledge reset, so the
                ; first attempt may itself be the ACK and not a state
                ; change. Three tries is "definitely UART now".
                CALL    nld_mpu_reset
                MOV     BX, 3FH
                CALL    nld_mpu_send_command
                CALL    nld_mpu_delay
                MOV     BX, 3FH
                CALL    nld_mpu_send_command
                CALL    nld_mpu_delay
                MOV     BX, 3FH
                CALL    nld_mpu_send_command
                ; Double-length wait after the third 0x3F so the MT-32
                ; has fully reset and is ready to receive bank data
                ; before the copy loop below starts streaming.
                CALL    nld_mpu_delay
                CALL    nld_mpu_delay

                ; Copy 0x481 bytes from ES:AX to CS:0x40+...
                MOV     SI, AX
                MOV     DI, 0
lpb_copy:       MOV     BL, ES:[SI]
                MOV     CS:[DI + nld_bank_buf], BL
                INC     DI
                INC     SI
                CMP     DI, 481H
                JNE     SHORT lpb_copy

                ; Copy bank[0x240] (now at our local 0x240) to 0x55C.
                MOV     BL, CS:[nld_bank_buf + 200H]
                MOV     CS:[nld_ch_extra1 + 9], BL

                ; In M32 this is where the SysEx upload loop would
                ; start, walking the bank's trailing (length, bytes...,
                ; 0xF7) blocks and streaming each one out the MPU to
                ; teach the MT-32 the game's custom timbres. NLD elides
                ; that loop entirely -- master volume to 0x0C, then
                ; straight to the self-id return values.
                MOV     CL, 0CH
                CALL    nld_set_master_volume

                ; Self-id handshake return values. The game side can
                ; verify that slot 1 is wired up by checking AX against
                ; the function table's slot-1 entry (= 0x0983, this
                ; function's own offset). CL=1, CH=8 is the
                ; format/version pair; M32 returns the identical CX
                ; (AX=0x0961, CX=0x0801) and ADL returns the same
                ; shape (AX=0x2446 = own offset, CX=0x0800). These
                ; three writes are LIVE return values, not dead code
                ; -- they fall through to POP SI / RET and BP-saving
                ; trampolines preserve AX/CX back to the game-side
                ; caller. See adl.asm:3474-3476 and m32.asm:1414-1416
                ; for the cross-driver pattern.
                MOV     AX, 0983H               ; AX = own offset (self-id)
                MOV     CL, 1                   ; format byte
                MOV     CH, 8                   ; version byte

                POP     SI
                RET
nld_load_patch_bank ENDP

; ----------------------------------------------------------------------------
; 0x09D2  --  nld_mpu_delay  (internal helper)
;
;   Spin-loop delay. Polls port 0x331 (status) 0x7500 times so the MPU
;   has time to absorb a command before the next one is issued. The
;   IN result is discarded; the read serves only as a slow no-op (each
;   `IN AL, DX` on a 286-class bus is ~5 cycles, so ~30000 * 5 ~= 150k
;   bus cycles ~= ~30 ms at a 4 MHz effective rate -- well above any
;   documented MPU command-latency budget).
;
;   Type:        Helper
;   Category:    Timing
;   Callers:     nld_load_patch_bank (between each 0x3F command, and
;                twice after the third)
;
;   Inputs:      none
;   Outputs:     none (AL is clobbered inside the loop but restored)
;
;   Side effects:
;     None on the MPU (reads only); spins CPU for the delay window.
; ----------------------------------------------------------------------------
nld_mpu_delay   PROC NEAR
                PUSH    AX
                PUSH    DX
                PUSH    DI
                MOV     DX, 331H
                MOV     DI, 7500H
mdy_spin:       IN      AL, DX
                DEC     DI
                CMP     DI, 0
                JNE     SHORT mdy_spin
                POP     DI
                POP     DX
                POP     AX
                RET
nld_mpu_delay   ENDP

; ----------------------------------------------------------------------------
; 0x09E6  --  nld_get_info  (slot 0)
;
;   Returns the driver's "ID card" to the caller. The cross-driver ABI
;   for slot 0 is "load a few literal bytes into AH/AL/CH/CL and
;   return"; what those bytes mean is driver-specific. For this driver:
;
;     AH = 0x01   driver class (MIDI)
;     AL = 0x01   capability flags (low bit = "supports note-on/off")
;     CH = 0x0C   default master volume (0x0C = preferred init value)
;     CL = 0x20   misc (possibly "max simultaneous notes")
;
;   Type:        Slot handler
;   Category:    Driver info
;   Dispatch:    Slot 0 (called by game as: BP=0)
;
;   Inputs:      none
;
;   Outputs:
;     AH  --  0x01 (driver class = MIDI)
;     AL  --  0x01 (capability flags)
;     CH  --  0x0C (default master volume)
;     CL  --  0x20 (misc; possibly max voices / 32)
;
;   Side effects: none.
; ----------------------------------------------------------------------------
nld_get_info    PROC NEAR
                MOV     AH, 1
                MOV     AL, 1
                MOV     CH, 0CH
                MOV     CL, 20H
                RET
nld_get_info    ENDP

                END     _start
