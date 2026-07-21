; ============================================================================
; Sx.SSM.GMD.bin -- Dynamix DUDE-format General-MIDI (MPU-401) sound driver,
; v1.08.
;
; Shipped with "Betrayal at Krondor" (Dynamix / Sierra, 1993).
;
; Packing: TASM + TLINK produce an MZ .EXE; PACKOVL strips the MZ header to
; the flat ORG-0 image, then LZW-packs it into SX.OVL.
;
; Cross-references:
;   SRC\DRIVERS\SX\ADL.ASM  -- companion AdLib driver (different chip, same DUDE shell)
; ============================================================================

; ----------------------------------------------------------------------------
; What this driver is
;
; A sound driver is a small piece of code that the game loads at startup and
; calls every time it wants to make a sound. Different sound cards need
; different code, so the game ships one driver per supported card and
; selects the right one at runtime based on the user's "sound setup" choice.
;
; This file is the "General MIDI for Roland MPU interface" driver: it
; targets any General-MIDI-compatible synthesizer (Roland Sound Canvas,
; SC-55, Yamaha MU-series, etc.) connected through an MPU-401 (or
; compatible) MIDI interface.
;
; Unlike the AdLib driver -- which has to synthesize sound itself from a
; bank of FM patches -- a General-MIDI synth already knows how to play
; every standard instrument. The driver's job is therefore simple: take
; the slot-based commands the game emits ("play this note", "change this
; controller") and forward them on the wire as MIDI bytes. The bulk of
; the file is bookkeeping for things MIDI itself doesn't do (master
; volume scaling, per-channel program-translation tables, percussion
; note remapping).
; ----------------------------------------------------------------------------

; ----------------------------------------------------------------------------
; About MPU-401 and General MIDI
;
; The Roland MPU-401 is an external MIDI interface that exposes two 8-bit
; I/O ports to the CPU:
;
;   port 0x330  (data port)         -- writes go onto the MIDI wire as raw
;                                       MIDI bytes; reads return incoming
;                                       MIDI bytes
;   port 0x331  (status / cmd port) -- writes are MPU-401 commands;
;                                       reads return a status byte whose
;                                       bits indicate "output buffer
;                                       full" (0x40) and "input buffer
;                                       empty" (0x80, active low)
;
; To send a MIDI message we (1) poll bit 0x40 of the status port until it
; is clear (output buffer ready), then (2) write the byte to port 0x330.
; To send an MPU-401 command we do the same, but write to 0x331 instead
; and then wait for the chip's ACK (0xFE) on the data port.
;
; The driver runs the MPU in "UART mode" (entered via command 0x3F), in
; which the MPU is just a transparent MIDI byte pipe -- exactly what we
; want for forwarding game-side MIDI messages to a General-MIDI synth.
;
; MIDI status bytes used here:
;   0x80 + ch  Note Off            (note, velocity)
;   0x90 + ch  Note On             (note, velocity; velocity=0 == Note Off)
;   0xB0 + ch  Control Change      (cc#, value)
;   0xC0 + ch  Program Change      (program)              -- 1 data byte!
;   0xD0 + ch  Channel Pressure    (value)                -- 1 data byte!
;   0xE0 + ch  Pitch Bend          (lsb, msb)
;   0xF7       SysEx end-of-message
;
; "ch" is a 4-bit MIDI channel (0..15). Channel 9 is GM's percussion
; channel by convention; this driver special-cases it for drum-note
; remapping (see gmd_drum_note_xlat below).
;
; The driver caches the most recent status byte (gmd_last_status) but
; never actually relies on MIDI running status -- every message it sends
; emits the status byte explicitly. The cache is informational only.
;
; For the full MPU-401 protocol, see "Roland MPU-401 Technical Reference
; Manual" (1984). For General MIDI, see the GM-1 spec from the MMA.
; ----------------------------------------------------------------------------

; ----------------------------------------------------------------------------
; The DUDE dispatch ABI
;
; "DUDE" (Dynamix Universal Driver Engine?) is the multi-driver soundsystem
; shared by every Sx.SSM.*.bin in this game. Every driver in the family
; has the same on-disk header, the same 18-slot dispatch table, and the
; same calling convention.
;
; Header layout (cross-driver):
;
;   0x00  E9 lo hi 00            JMP rel16 to dispatch trampoline (+ pad 0)
;   0x04  21 43 65 87             dude_magic_a = 0x87654321 (LE)
;   0x08  01 04                   DUDE interface version (1.04?)
;   0x0A  64 75 64 65             dude_tag = "dude"
;   0x0E  <len>                   length of device-name Pascal string
;   0x0F  <name...>               device-name characters (no trailing NUL)
;   ...   98 BA DC FE             dude_magic_b = 0xFEDCBA98
;   ...   <u32 LE>                driver kind (= 0x00000200 for GMD)
;   ...   <ASCII>                 driver version string (length implied by
;                                 distance to the first per-driver data)
;
; Game-side call:
;
;     BP = slot index (0..17)
;     AL = MIDI channel (0..15)        ; if this slot needs one
;     CL = MIDI data byte 1            ; depends on the slot
;     CH = MIDI data byte 2            ; depends on the slot
;     ES:AX = far ptr to bank          ; only used by slot 1 (load_patch_bank)
;     CALL FAR gmd_seg:gmd_dispatch
;
; Dispatch trampoline (12 bytes; see gmd_dispatch below):
;
;     PUSH DX
;     SHL  BP, 1                       ; word index -> byte offset
;     MOV  DX, CS:[BP + gmd_func_table]
;     CALL DX                          ; near indirect to the handler
;     POP  DX
;     RETF
;
; The function table has 18 entries (`ushort[18]`). Slots that this driver
; does not implement point at a single shared 1-byte RET stub
; (gmd_slot_unused_ret).
;
; Per-slot semantics (this driver):
;
;   Slot | Handler                    | Args                              |
;   -----|----------------------------|-----------------------------------|
;   0    | gmd_get_info               | -                                 |
;   1    | gmd_load_patch_bank        | ES:AX = src                       |
;   2    | gmd_reset_voices           | -                                 |
;   3    | (unused)                   | -                                 |
;   4    | gmd_midi_note_off          | AL=ch, CH=note                    |
;   5    | gmd_midi_note (on)         | AL=ch, CH=note, CL=vel            |
;   6    | (unused)                   | -                                 |
;   7    | gmd_midi_control_change    | AL=ch, CH=cc#, CL=val             |
;   8    | gmd_midi_program_change    | AL=ch, CL=prog                    |
;   9    | (unused)                   | -                                 |
;   10   | gmd_midi_pitch_bend        | AL=ch, CL=lsb, CH=msb             |
;   11   | gmd_set_global_param       | CL=val (0xFF = query)             |
;   12   | gmd_apply_master_volume    | CL=val (0xFF = query)             |
;   13   | gmd_set_master_enable      | CL=val (0xFF = query)             |
;   14-16| (unused)                   | -                                 |
;   17   | gmd_query_state            | AL=ch, AH=class, CH=cc#, CL=sub   |
; ----------------------------------------------------------------------------

; ----------------------------------------------------------------------------
; How to read this source
;
; - `MOV BX, AX` is an instruction: destination first, then source. Read
;   it as "BX = AX".
;
; - `CS:[reg + label]` is a memory access using the Code Segment register
;   as base. In our flat single-segment driver, every read and write
;   goes through CS: because all data lives in the same segment as the
;   code.
;
; - Each function begins with `<name> PROC NEAR` and ends with
;   `<name> ENDP`. Inside, labels like `noteon_skip:` are jump targets
;   local to that function (prefixed with the handler's short name to
;   avoid collisions).
;
; - Numbers ending in `H` are hex (3FH = 63). Plain numbers are decimal.
;
; - This driver does not use a calling convention with stack arguments:
;   the dispatch trampoline puts the slot's data in registers (AL, CL,
;   CH, ES:AX) before calling the handler. Internal helpers also pass
;   arguments in registers; the per-helper conventions are documented
;   at each prologue.
; ----------------------------------------------------------------------------

                .8086
                .MODEL  TINY
                .CODE
                ORG     0

; ============================================================================
; 0x0000  --  Module entry point
; ============================================================================
_start          LABEL   BYTE

                JMP     gmd_dispatch

; ============================================================================
; 0x0003  --  DUDE header
; ============================================================================
pad_03          DB      000H                    ; pad byte (always 0)

dude_magic_a    DD      87654321H               ; "is this a DUDE driver?" #1
dude_iface_ver  DB      001H, 004H              ; interface version (1.04)
dude_tag        DB      'dude'                  ; ASCII tag (4 bytes)
device_name_len DB      25H                     ; length of name below (37)
device_name     DB      'General MIDI for Roland MPU interface'
dude_magic_b    DD      0FEDCBA98H              ; "is this a DUDE driver?" #2
dude_driver_kind DD     000000200H              ; driver kind (GMD = 0x200)
driver_ver_str  DB      'v1.08'                 ; build/version string

; ============================================================================
; 0x0041  --  Patch / program translation tables (loaded by slot 1)
;
; The DUDE bank that slot 1 (gmd_load_patch_bank) copies into the driver
; is 0x481 (1153) bytes long and lands at CS:[0x0041..0x04C1]. The first
; 4 * 128 = 512 bytes form four parallel 128-entry program-translation
; tables, indexed by the game-side MIDI program number (0..127):
;
;     program  ----> patch_prog_xlat[prog]    -- translated GM program
;                    patch_msb_xlat[prog]     -- note-transpose offset
;                    patch_lsb_xlat[prog]     -- channel main-volume bias
;                    patch_transpose_xlat[prog] -- velocity-curve selector
;
; At program-change time, gmd_midi_program_change looks up all four bytes
; and stages them into the per-channel state region at 0x0548..0x0577.
;
; Between the 3rd and 4th 128-byte block there is a 128-entry drum-note
; remapping table (gmd_drum_note_xlat) for MIDI channel 9: the game's
; percussion note number maps through this table to the General-MIDI
; drum-kit note number actually emitted.
;
; All of these are initialized FF/00 in the on-disk binary because they
; are *runtime* state, populated by gmd_load_patch_bank before any notes
; play. The persistent program disk file is what supplies the actual
; mapping data.
; ============================================================================

gmd_patch_prog_xlat     DB      128 DUP(0FFH)   ; program -> translated GM prog
gmd_patch_msb_xlat      DB      128 DUP(000H)   ; program -> note-offset bias
gmd_patch_lsb_xlat      DB      128 DUP(000H)   ; program -> volume bias
gmd_drum_note_xlat      DB      128 DUP(000H)   ; ch9 drum-note remap
gmd_patch_extra_xlat0   DB      000H            ; 1-byte field before next
                                                ; table; staged into [0x0561]
                                                ; by gmd_load_patch_bank
gmd_patch_transpose_xlat DB     128 DUP(000H)   ; program -> velocity-curve sel.

; ============================================================================
; 0x02C2  --  Bank tail: velocity-curve table region
;
; gmd_midi_note (slot 5) computes a velocity-curve index as:
;
;     vel_idx = (vel & 0x7F) + (gmd_ch_state_568[ch] * 0x80)
;     translated_vel = CS:[vel_idx + 0x02C2]
;
; That is: gmd_ch_state_568[ch] picks one of several 128-byte velocity
; curves, and the 0..127 raw MIDI velocity indexes into the chosen curve.
; The whole region 0x02C2..0x04C1 (512 bytes) is therefore four 128-entry
; velocity-curve tables, loaded as part of the same 0x481-byte patch
; bank. On-disk they are zero -- they only become meaningful after
; gmd_load_patch_bank has populated them.
; ============================================================================

gmd_bank_tail   DB      512 DUP(000H)           ; velocity-curve tables

; ============================================================================
; 0x04C2  --  Post-bank globals
; ============================================================================

gmd_post_bank_pad DB    4 DUP(000H)             ; 4-byte pad (always 0)
gmd_master_volume DB    00FH                    ; master volume (0..15)
gmd_master_enable DB    001H                    ; master enable: 0 = mute

; ============================================================================
; 0x04C8  --  Per-channel state (struct-of-arrays, 16 channels each)
; ============================================================================

gmd_ch_program        DB      16 DUP(0FFH)      ; channel -> cached program #
gmd_ch_pitchbend      DB      32 DUP(0FFH)      ; 16 ch x 2 bytes (lsb, msb)
gmd_ch_modulation     DB      16 DUP(0FFH)      ; cc 0x01 (modulation wheel)
gmd_ch_volume         DB      16 DUP(0FFH)      ; cc 0x07 (main volume)
gmd_ch_pan            DB      16 DUP(0FFH)      ; cc 0x0A (pan)
gmd_ch_sustain        DB      16 DUP(0FFH)      ; cc 0x40 (sustain pedal)
gmd_ch_active         DB      16 DUP(001H)      ; 1 = at least one note alive
gmd_ch_note_offset    DB      16 DUP(000H)      ; per-channel note transpose
gmd_ch_state_558      DB      16 DUP(000H)      ; staged xlat_c value
gmd_ch_state_568      DB      16 DUP(000H)      ; velocity-curve selector
gmd_ch_program_loaded DB      16 DUP(000H)      ; current translated program

gmd_last_status       DB      000H              ; running-status cache (info)
gmd_global_param_589  DB      000H              ; slot-11 scratch param

; ============================================================================
; 0x058A  --  Function-pointer dispatch table (18 near-pointers)
;
; Indexed by the slot number (BP) the game passes to dispatch. Each
; entry is a 16-bit code offset relative to the start of this binary.
; Unused slots all point at the shared 1-byte RET stub
; (gmd_slot_unused_ret).
; ============================================================================

gmd_func_table  LABEL   WORD
                DW      gmd_get_info             ; slot 0
                DW      gmd_load_patch_bank      ; slot 1
                DW      gmd_reset_voices         ; slot 2
                DW      gmd_slot_unused_ret      ; slot 3
                DW      gmd_midi_note_off        ; slot 4
                DW      gmd_midi_note            ; slot 5
                DW      gmd_slot_unused_ret      ; slot 6
                DW      gmd_midi_control_change  ; slot 7
                DW      gmd_midi_program_change  ; slot 8
                DW      gmd_slot_unused_ret      ; slot 9
                DW      gmd_midi_pitch_bend      ; slot 10
                DW      gmd_set_global_param     ; slot 11
                DW      gmd_apply_master_volume  ; slot 12
                DW      gmd_set_master_enable    ; slot 13
                DW      gmd_slot_unused_ret      ; slot 14
                DW      gmd_slot_unused_ret      ; slot 15
                DW      gmd_slot_unused_ret      ; slot 16
                DW      gmd_query_state          ; slot 17

; ============================================================================
; 0x05AE  --  gmd_dispatch  -- the trampoline jumped to from offset 0
;
; The game's far-call lands at offset 0 (the JMP rel16); the JMP comes
; here. We use the slot index in BP to fetch the handler's near offset
; from gmd_func_table and call it. DX is saved/restored because the
; trampoline clobbers it during the indirect call; BP is *not* saved
; because the trampoline restores it implicitly via SHL.
;
; Borland convention notes:
; - SHL BP, 1 turns the word-index BP into a byte offset (each entry is
;   2 bytes wide).
; - CS-relative addressing (`CS:[BP+...]`) is necessary because BP
;   normally defaults to the SS segment.
;
;   Type:        Subroutine (dispatch trampoline)
;   Category:    Dispatch
;   Callers:     Game (via the far JMP at offset 0)
;   Callees:     Indirect via gmd_func_table -- any of the 18 slot
;                handlers, including the shared gmd_slot_unused_ret
;
;   Inputs:
;     BP  --  slot index (0..17)
;     AL, CL, CH, ES:AX -- forwarded to the handler per slot
;
;   Outputs:
;     Whatever the dispatched handler returns (typically AX).
;
;   Touches:
;     DX preserved (saved/restored); BP left shifted to 2*slot on exit.
; ============================================================================

gmd_dispatch    PROC    NEAR
                PUSH    DX
                SHL     BP, 1
                MOV     DX, CS:[BP + gmd_func_table]
                CALL    DX
                POP     DX
                RETF
gmd_dispatch    ENDP

; ============================================================================
; 0x05BA  --  gmd_slot_unused_ret
;
; The shared 1-byte RET stub. Every unused entry in gmd_func_table
; points here, so calling an unsupported slot is harmless: the
; trampoline calls this, this returns, and dispatch RETFs back to the
; game with no state change.
;
;   Type:        Slot handler (shared no-op)
;   Category:    Dispatch
;   Dispatch:    Slots 3, 6, 9, 14, 15, 16 (called as: BP=that slot)
;   Callers:     Game (via dispatch, through gmd_func_table)
;   Callees:     none
;
;   Inputs:      none used
;   Outputs:     none
;   Touches:     none (single RET)
;   Side effects: none
; ============================================================================

gmd_slot_unused_ret PROC NEAR
                RET
gmd_slot_unused_ret ENDP

; ============================================================================
; 0x05BB  --  gmd_set_global_param  (slot 11)
;
;   Single 8-bit "global parameter" with set/query semantics. We don't
;   know what this parameter means to the game; we just store and
;   return it. CL=0xFF is the query (return current value, don't
;   change it); any other value is a set (store and return previous).
;
;   Type:        Slot handler
;   Category:    Driver state
;   Dispatch:    Slot 11 (BP=11, CL=value or 0xFF for query)
;   Callers:     Game (via dispatch)
;   Callees:     none
;
;   Inputs:
;     CL  --  new value, or 0xFF to query
;   Outputs:
;     AL  --  previous (or current) value, zero-extended into AX
;   Touches:     AX overwritten with the return value; CL preserved.
;
;   Side effects:
;     gmd_global_param_589 <- CL (unless CL=0xFF, then no write).
; ============================================================================

gmd_set_global_param PROC NEAR
                MOV     AL, CS:[gmd_global_param_589]
                XOR     AH, AH                   ; zero-extend return value
                CMP     CL, 0FFH                 ; query?
                JNZ     SHORT sgp_store
                RET
sgp_store:      MOV     CS:[gmd_global_param_589], CL
                RET
gmd_set_global_param ENDP

; ============================================================================
; 0x05CD  --  gmd_midi_note_off  (slot 4)
;
;   Emit a MIDI Note Off for one note on one channel. To stay in
;   "Note On with velocity=0" running-status form (which is identical
;   in effect to Note Off but lets the synth keep its running-status
;   parser primed), we always emit 0x90+ch with velocity 0 -- never
;   0x80+ch.
;
;   Channel 9 is the GM percussion channel: instead of using the raw
;   note number, we look it up in gmd_drum_note_xlat. An xlat result
;   of 0xFF means "drop this drum" -- no MIDI traffic.
;
;   For non-percussion channels we transpose the note by
;   gmd_ch_note_offset[ch] (signed in [-128..+127]), then clamp the
;   result into MIDI's valid range 0..127 by adding/subtracting one
;   octave (12 semitones) until in-range. The clamp direction is
;   picked by the sign of the offset.
;
;   Type:        Slot handler
;   Category:    MIDI dispatch
;   Dispatch:    Slot 4 (BP=4, AL=ch, CH=note)
;   Callers:     Game (via dispatch)
;   Callees:     gmd_mpu_send_msg
;
;   Inputs:
;     AL  --  MIDI channel (0..15)
;     CH  --  MIDI note number (0..127)
;   Outputs:
;     AX  --  preserved (game expects no return)
;   Touches:     all caller registers preserved (saves AX, SI, CX).
;
;   Side effects:
;     Up to one MPU-401 Note On message (0x90 ch, note, 0) on the wire.
;     gmd_last_status updated to the emitted status byte (via send_msg).
; ============================================================================

gmd_midi_note_off PROC NEAR
                PUSH    AX
                PUSH    SI
                PUSH    CX

                ; If channel == 9 (drum), translate the note via the
                ; drum-remap table; an xlat result of 0xFF means
                ; "silently drop this drum hit".
                CMP     AL, 9
                JNZ     SHORT noff_melodic
                XCHG    CH, CL                  ; CL = note (was CH)
                MOV     SI, CX
                XCHG    CH, CL                  ; restore CH
                AND     SI, 007FH               ; SI = note & 0x7F
                MOV     CH, CS:[SI + gmd_drum_note_xlat]
                CMP     CH, 0FFH
                JZ      SHORT noff_done
                JMP     SHORT noff_emit

                ; Melodic path: look up per-channel state, transpose,
                ; clamp into 0..127.
noff_melodic:   MOV     SI, AX
                AND     SI, 000FH               ; SI = channel
                CMP     byte ptr CS:[SI + gmd_ch_program_loaded], 0FFH
                JZ      SHORT noff_done         ; no program loaded -> drop

                ADD     CH, CS:[SI + gmd_ch_note_offset]
                MOV     AH, 0F4H                ; -12 (subtract one octave)
                CMP     byte ptr CS:[SI + gmd_ch_note_offset], 080H
                JB      SHORT noff_clamp_loop
                MOV     AH, 00CH                ; +12 (add one octave)

noff_clamp_loop:
                CMP     CH, 080H                ; note >= 0x80 (out of range)?
                JB      SHORT noff_emit
                ADD     CH, AH
                JMP     SHORT noff_clamp_loop

                ; Send "Note On vel=0" via gmd_mpu_send_msg. AH=0x90
                ; selects Note On; CL=0 is the velocity; CH is the
                ; note number; AL is the channel.
noff_emit:      MOV     AH, 090H                ; status: Note On
                MOV     CL, 0                   ; velocity 0 -> Note Off
                CALL    gmd_mpu_send_msg

noff_done:      POP     CX
                POP     SI
                POP     AX
                RET
gmd_midi_note_off ENDP

; ============================================================================
; 0x061B  --  gmd_midi_note  (slot 5)
;
;   Emit a MIDI Note On (velocity > 0 -> note on; velocity == 0 is
;   effectively a Note Off but is *not* synthesised by this slot --
;   slot 4 handles that explicitly).
;
;   Same percussion / transpose handling as gmd_midi_note_off (slot
;   4). Additionally, the raw velocity is run through one of four
;   128-entry velocity-curve tables (gmd_bank_tail at 0x02C2);
;   gmd_ch_state_568[ch] selects which curve. The translated
;   velocity is what actually goes on the MIDI wire.
;
;   We also set gmd_ch_active[ch] = 1 to mark the channel as "has at
;   least one live note", which gmd_midi_control_change consults when
;   handling "all notes off" (CC 0x7B).
;
;   Type:        Slot handler
;   Category:    MIDI dispatch
;   Dispatch:    Slot 5 (BP=5, AL=ch, CH=note, CL=velocity)
;   Callers:     Game (via dispatch)
;   Callees:     gmd_mpu_send_msg
;
;   Inputs:
;     AL  --  MIDI channel (0..15)
;     CH  --  MIDI note number (0..127)
;     CL  --  MIDI velocity (1..127; 0 is technically allowed but the
;             game uses slot 4 for off)
;   Outputs:
;     AX  --  preserved
;   Touches:     all caller registers preserved (saves AX, SI, CX, DI).
;
;   Side effects:
;     gmd_ch_active[ch] <- 1
;     One MPU-401 Note On message on the wire (unless dropped early).
;     gmd_last_status updated (via send_msg).
; ============================================================================

gmd_midi_note   PROC    NEAR
                PUSH    AX
                PUSH    SI
                PUSH    CX
                PUSH    DI

                CMP     AL, 9
                JNZ     SHORT non_melodic
                XCHG    CH, CL
                MOV     SI, CX
                XCHG    CH, CL
                AND     SI, 007FH
                MOV     CH, CS:[SI + gmd_drum_note_xlat]
                CMP     CH, 0FFH
                JZ      SHORT non_done
                MOV     SI, AX
                AND     SI, 000FH
                JMP     SHORT non_velocity

non_melodic:    MOV     SI, AX
                AND     SI, 000FH
                CMP     byte ptr CS:[SI + gmd_ch_program_loaded], 0FFH
                JZ      SHORT non_done
                ADD     CH, CS:[SI + gmd_ch_note_offset]
                MOV     AH, 0F4H                ; -12
                CMP     byte ptr CS:[SI + gmd_ch_note_offset], 080H
                JB      SHORT non_clamp_loop
                MOV     AH, 00CH                ; +12

non_clamp_loop: CMP     CH, 080H
                JB      SHORT non_velocity
                ADD     CH, AH
                JMP     SHORT non_clamp_loop

                ; Map the raw velocity through one of four 128-entry
                ; curves at 0x02C2. The curve index is
                ; gmd_ch_state_568[ch] * 0x80, plus the velocity & 0x7F.
non_velocity:   PUSH    AX
                MOV     AL, 080H
                MUL     byte ptr CS:[SI + gmd_ch_state_568]
                MOV     DI, CX
                AND     DI, 007FH
                ADD     DI, AX
                POP     AX
                MOV     CL, CS:[DI + gmd_bank_tail]
                MOV     byte ptr CS:[SI + gmd_ch_active], 1
                MOV     AH, 090H                ; status: Note On
                CALL    gmd_mpu_send_msg

non_done:       POP     DI
                POP     CX
                POP     SI
                POP     AX
                RET
gmd_midi_note   ENDP

; ============================================================================
; 0x0689  --  gmd_midi_control_change  (slot 7)
;
;   Handle a MIDI Control Change (cc#, value) for one channel.
;   Supported controllers:
;
;     0x07  Main Volume   -- cached in gmd_ch_volume[ch], then scaled by
;                            (master_volume / 15) and biased by
;                            gmd_ch_state_558[ch] before being sent.
;     0x0A  Pan           -- cached and forwarded if changed.
;     0x40  Sustain pedal -- cached and forwarded if changed.
;     0x7B  All Notes Off -- forwarded only if gmd_ch_active[ch] != 0;
;                            also clears the active flag.
;     other -- silently dropped (no MIDI traffic).
;
;   Type:        Slot handler
;   Category:    MIDI dispatch
;   Dispatch:    Slot 7 (BP=7, AL=ch, CH=cc#, CL=value)
;   Callers:     Game (via dispatch); gmd_midi_program_change (for the
;                CC 7 re-emit on volume-bias change); gmd_apply_master_volume
;                (re-emits CC 7 across channels 1..9).
;   Callees:     gmd_mpu_send_msg
;
;   Inputs:
;     AL  --  MIDI channel
;     CH  --  controller number (0..127)
;     CL  --  controller value  (0..127; 0x7F mask applied)
;   Outputs:
;     AX  --  preserved
;   Touches:     all caller registers preserved (saves AX, SI). CL, CH
;                are mutated as scratch for the volume-scaling math.
;
;   Side effects:
;     CC 7  -> gmd_ch_volume[ch] cached; CC 7 message scaled by master
;              volume and sent (unless muted).
;     CC 10 -> gmd_ch_pan[ch] cached; message forwarded only on change.
;     CC 64 -> gmd_ch_sustain[ch] cached; forwarded only on change.
;     CC 123-> gmd_ch_active[ch] cleared; message forwarded only when
;              the channel had at least one active note.
;     Other CCs: silently dropped.
;     gmd_last_status updated (via send_msg) when a message is emitted.
; ============================================================================

gmd_midi_control_change PROC NEAR
                PUSH    AX
                PUSH    SI

                MOV     SI, AX
                AND     SI, 000FH
                AND     CL, 07FH                ; clamp value to 0..127

                CMP     CH, 007H                ; CC 7 (main volume)?
                JNZ     SHORT cc_not_volume

                ; Cache the unscaled volume. If master mute is on, we're
                ; done: don't emit anything.
                MOV     CS:[SI + gmd_ch_volume], CL
                CMP     byte ptr CS:[gmd_master_enable], 0
                JNZ     SHORT cc_vol_scale
                JMP     cc_done

                ; Apply the channel's bias (gmd_ch_state_558[ch]).
                ; If the bias is in the [+1..+127] range we add it and
                ; clamp at 0x7F; if in [-128..-1] we sub-clamp at 0x01.
cc_vol_scale:   ADD     CL, CS:[SI + gmd_ch_state_558]
                CMP     CL, 080H
                JB      SHORT cc_vol_have_biased
                MOV     CL, 07FH                ; positive overflow -> 0x7F
                CMP     byte ptr CS:[SI + gmd_ch_state_558], 080H
                JB      SHORT cc_vol_have_biased
                MOV     CL, 1                   ; negative overflow -> 0x01

cc_vol_have_biased:
                MOV     CH, AL                  ; CH = channel (temp save)
                MOV     AL, CS:[gmd_master_volume]
                MUL     CL                      ; AX = master_vol * biased
                MOV     CL, 0FH
                DIV     CL                      ; AL = AX / 15
                MOV     CL, AL                  ; CL = scaled volume
                MOV     AL, CH                  ; AL = channel (restore)
                MOV     CH, 7                   ; CH = CC 7 (main volume)

                ; If the scaled volume is zero but the raw was nonzero,
                ; bump to 1 so the channel doesn't go fully mute on a
                ; rounding-to-zero scaling.
                OR      CL, CL
                JNZ     SHORT cc_emit
                OR      AH, AH
                JZ      SHORT cc_emit
                INC     CL
                JMP     SHORT cc_emit

cc_not_volume:  CMP     CH, 00AH                ; CC 10 (pan)?
                JNZ     SHORT cc_not_pan
                CMP     byte ptr CS:[SI + gmd_ch_pan], CL
                JZ      SHORT cc_done
                MOV     CS:[SI + gmd_ch_pan], CL
                JMP     SHORT cc_emit

cc_not_pan:     CMP     CH, 040H                ; CC 64 (sustain)?
                JNZ     SHORT cc_not_sustain
                CMP     byte ptr CS:[SI + gmd_ch_sustain], CL
                JZ      SHORT cc_done
                MOV     CS:[SI + gmd_ch_sustain], CL
                JMP     SHORT cc_emit

cc_not_sustain: CMP     CH, 07BH                ; CC 123 (all notes off)?
                JNZ     SHORT cc_done
                CMP     byte ptr CS:[SI + gmd_ch_active], 0
                JZ      SHORT cc_done           ; no active notes -> drop
                MOV     byte ptr CS:[SI + gmd_ch_active], 0

cc_emit:        MOV     AH, 0B0H                ; status: Control Change
                CALL    gmd_mpu_send_msg

cc_done:        POP     SI
                POP     AX
                RET
gmd_midi_control_change ENDP

; ============================================================================
; 0x071C  --  gmd_midi_program_change  (slot 8)
;
;   Handle a MIDI Program Change. The game-side program number is
;   indexed into four parallel translation tables (loaded by slot 1)
;   to produce:
;
;     xlat_a (CL)  -- translated GM program (0xFF = "do not load")
;     xlat_b (CH)  -- per-channel note-offset (signed)
;     xlat_c (BH)  -- volume bias for the next CC 7 we send
;     xlat_d (BL)  -- velocity-curve selector (0..3)
;
;   We cache the raw game-side program in gmd_ch_program[ch]; if it
;   already equals the incoming CL we do nothing (no MIDI traffic).
;
;   When the previously-loaded program slot was empty (0xFF), or when
;   xlat_b / xlat_c changes value, we emit CC 0x7B + CC 0x40 (all
;   notes off + sustain off) to flush any lingering notes before the
;   new instrument starts playing. If xlat_c changed we additionally
;   re-emit a CC 7 (main volume) so the synth picks up the new bias.
;   Finally we emit the Program Change itself.
;
;   Channel 9 (percussion) bypasses program-change entirely: drum
;   sounds are selected by note number alone in GM, not by program.
;
;   Type:        Slot handler
;   Category:    MIDI dispatch
;   Dispatch:    Slot 8 (BP=8, AL=ch, CL=game-side program 0..127)
;   Callers:     Game (via dispatch)
;   Callees:     gmd_mpu_send_msg, gmd_midi_control_change
;
;   Inputs:
;     AL  --  MIDI channel
;     CL  --  program number
;   Outputs:     AX preserved.
;   Touches:     all caller registers preserved (saves AX, SI, CX, BX).
;
;   Side effects:
;     gmd_ch_program[ch]        <- CL (raw game-side program)
;     gmd_ch_state_568[ch]      <- xlat_d (velocity-curve selector)
;     gmd_ch_program_loaded[ch] <- xlat_a (translated GM program)
;     gmd_ch_note_offset[ch]    <- xlat_b (signed transpose; on change)
;     gmd_ch_state_558[ch]      <- xlat_c (volume bias; on change)
;     Up to 4 MIDI messages on the wire: CC 0x7B (all notes off),
;     CC 0x40 (sustain off), CC 0x07 (main volume re-emit), and the
;     Program Change itself. gmd_last_status updated (via send_msg).
; ============================================================================

gmd_midi_program_change PROC NEAR
                PUSH    AX
                PUSH    SI
                PUSH    CX
                PUSH    BX

                CMP     AL, 9
                JZ      SHORT pc_done_jmp       ; ch 9 -> no program change

                MOV     SI, AX
                AND     SI, 000FH
                CMP     byte ptr CS:[SI + gmd_ch_program], CL
                JZ      SHORT pc_done_jmp       ; same program -> no-op
                MOV     CS:[SI + gmd_ch_program], CL

                ; Look up all four translation bytes from the bank.
                MOV     SI, CX
                AND     SI, 007FH               ; SI = program & 0x7F
                MOV     CL, CS:[SI + gmd_patch_prog_xlat]
                MOV     CH, CS:[SI + gmd_patch_msb_xlat]
                MOV     BH, CS:[SI + gmd_patch_lsb_xlat]
                MOV     BL, CS:[SI + gmd_patch_transpose_xlat]

                ; Stage xlat_d into gmd_ch_state_568[ch] (velocity-
                ; curve selector).
                MOV     SI, AX
                AND     SI, 000FH
                MOV     CS:[SI + gmd_ch_state_568], BL

                ; If the channel had no program loaded yet, mark that
                ; a "first load" is happening (BL=1) so we don't gate
                ; the CC 7 re-emit on xlat_c-changed below.
                XOR     BL, BL
                CMP     byte ptr CS:[SI + gmd_ch_program_loaded], 0FFH
                JNZ     SHORT pc_has_prev
                INC     BL
pc_has_prev:    MOV     CS:[SI + gmd_ch_program_loaded], CL

                ; xlat_a == 0xFF: the bank explicitly disables this
                ; program -- we still flush the channel (notes-off,
                ; sustain-off) but do not emit a Program Change.
                CMP     CL, 0FFH
                JNZ     SHORT pc_normal

                MOV     AH, 0B0H                ; status: CC
                MOV     CH, 07BH                ; CC 123 (all notes off)
                XOR     CL, CL
                CALL    gmd_mpu_send_msg
                MOV     CH, 040H                ; CC 64 (sustain off)
                CALL    gmd_mpu_send_msg
pc_done_jmp:    JMP     SHORT pc_done

                ; Normal program-change path. If xlat_b changed,
                ; emit notes-off + sustain-off and treat as "first
                ; load" so the CC 7 re-emit happens regardless of
                ; xlat_c's value.
pc_normal:      CMP     CH, CS:[SI + gmd_ch_note_offset]
                JZ      SHORT pc_skip_flush
                MOV     CS:[SI + gmd_ch_note_offset], CH
                PUSH    CX
                MOV     AH, 0B0H
                MOV     CH, 07BH
                XOR     CL, CL
                CALL    gmd_mpu_send_msg
                MOV     CH, 040H
                CALL    gmd_mpu_send_msg
                POP     CX
                INC     BL                      ; force the CC 7 below

pc_skip_flush:  OR      BL, BL                  ; first load or flush?
                JNZ     SHORT pc_volume_reemit
                CMP     BH, CS:[SI + gmd_ch_state_558]
                JZ      SHORT pc_emit_prog
pc_volume_reemit:
                MOV     CS:[SI + gmd_ch_state_558], BH
                PUSH    CX
                MOV     CL, CS:[SI + gmd_ch_volume]
                MOV     CH, 7                   ; CC 7 (main volume)
                CALL    gmd_midi_control_change
                POP     CX

pc_emit_prog:   MOV     AH, 0C0H                ; status: Program Change
                CALL    gmd_mpu_send_msg

pc_done:        POP     BX
                POP     CX
                POP     SI
                POP     AX
                RET
gmd_midi_program_change ENDP

; ============================================================================
; 0x07C2  --  gmd_midi_pitch_bend  (slot 10)
;
;   Forward a MIDI Pitch Bend (lsb, msb) for one channel. Cached per
;   channel so identical re-issues don't generate wire traffic.
;
;   Type:        Slot handler
;   Category:    MIDI dispatch
;   Dispatch:    Slot 10 (BP=10, AL=ch, CL=lsb, CH=msb)
;   Callers:     Game (via dispatch)
;   Callees:     gmd_mpu_send_msg
;
;   Inputs:
;     AL  --  MIDI channel
;     CL  --  bend LSB (0..127)
;     CH  --  bend MSB (0..127)
;   Outputs:
;     AX  --  preserved
;   Touches:     all caller registers preserved (saves AX, SI).
;
;   Side effects:
;     gmd_ch_pitchbend[ch * 2 + 0] <- CL
;     gmd_ch_pitchbend[ch * 2 + 1] <- CH
;     One MPU-401 Pitch Bend message on the wire if either byte differs
;     from the cached value (otherwise no traffic). gmd_last_status
;     updated (via send_msg) when emitted.
; ============================================================================

gmd_midi_pitch_bend PROC NEAR
                PUSH    AX
                PUSH    SI
                MOV     SI, AX
                AND     SI, 000FH
                SHL     SI, 1                   ; SI = ch * 2
                CMP     byte ptr CS:[SI + gmd_ch_pitchbend], CL
                JNZ     SHORT pb_changed
                CMP     byte ptr CS:[SI + gmd_ch_pitchbend + 1], CH
                JZ      SHORT pb_done
pb_changed:     MOV     CS:[SI + gmd_ch_pitchbend], CL
                MOV     CS:[SI + gmd_ch_pitchbend + 1], CH
                MOV     AH, 0E0H                ; status: Pitch Bend
                CALL    gmd_mpu_send_msg
pb_done:        POP     SI
                POP     AX
                RET
gmd_midi_pitch_bend ENDP

; ============================================================================
; 0x07EB  --  gmd_mpu_send_msg
;
;   Write a complete MIDI message (status byte + 1 or 2 data bytes)
;   out the MPU-401 data port. The number of data bytes is determined
;   by the high nibble of the status byte:
;
;     0xC0+ch (Program Change)     -- 1 data byte  (CL = program)
;     0xD0+ch (Channel Pressure)   -- 1 data byte  (CL = value)
;     anything else                -- 2 data bytes (CH=byte1, CL=byte2)
;
;   The caller already supplies the channel low-nibble in AL; we OR
;   it into AH to form the full status byte. The status byte is also
;   cached in gmd_last_status for any external observer.
;
;   Type:        Subroutine (MIDI helper)
;   Category:    MIDI helper
;   Callers:     gmd_midi_note_off, gmd_midi_note,
;                gmd_midi_control_change, gmd_midi_program_change,
;                gmd_midi_pitch_bend, gmd_set_master_enable
;   Callees:     gmd_mpu_write_data
;
;   Inputs:
;     AL  --  MIDI channel (0..15)
;     AH  --  MIDI status high-nibble (0x80, 0x90, 0xB0, 0xC0, 0xD0, 0xE0)
;     CL  --  first / only data byte
;     CH  --  second data byte (ignored for C0/D0)
;   Outputs:
;     (none -- pure side effect on MPU output)
;   Touches:
;     BX saved and restored; DL clobbered.
;
;   Side effects:
;     gmd_last_status <- (AH | AL)  (full status byte cached for query).
;     Two or three bytes written out the MPU-401 data port (0x330).
; ============================================================================

gmd_mpu_send_msg PROC NEAR
                PUSH    BX
                MOV     DL, AL                  ; DL = channel
                OR      DL, AH                  ; DL = status | channel
                MOV     CS:[gmd_last_status], DL
                MOV     BL, DL
                CALL    gmd_mpu_write_data      ; emit status byte

                ; Status 0xC0 and 0xD0 take only one data byte (the
                ; one in CL); anything else gets the CH byte first.
                CMP     AH, 0C0H
                JZ      SHORT sm_one_data
                CMP     AH, 0D0H
                JZ      SHORT sm_one_data
                MOV     BL, CH
                CALL    gmd_mpu_write_data
sm_one_data:    MOV     BL, CL
                CALL    gmd_mpu_write_data
                POP     BX
                RET
gmd_mpu_send_msg ENDP

; ============================================================================
; 0x0810  --  gmd_reset_voices  (slot 2)
;
;   Reset the MPU-401 to a known idle state. Just a thin wrapper
;   over gmd_mpu_reset.
;
;   Type:        Slot handler
;   Category:    Driver state
;   Dispatch:    Slot 2 (BP=2)
;   Callers:     Game (via dispatch)
;   Callees:     gmd_mpu_reset
;
;   Inputs:      none
;   Outputs:     none
;   Touches:     BX saved and restored.
;
;   Side effects:
;     One MPU-401 "reset" command (0xFF) issued on port 0x331.
; ============================================================================

gmd_reset_voices PROC NEAR
                PUSH    BX
                CALL    gmd_mpu_reset
                POP     BX
                RET
gmd_reset_voices ENDP

; ============================================================================
; 0x0816  --  gmd_mpu_write_cmd
;
;   Send one byte to the MPU-401 *command* port (0x331). The MPU's
;   handshake for a command write is:
;     1. Poll status port (0x331 for read): wait for bit 0x40 to be
;        clear, meaning the input buffer is ready to receive.
;     2. Write the command byte to port 0x331.
;     3. Poll status port: wait for bit 0x80 to be set, meaning the
;        MPU has produced output for us.
;     4. Read one byte from the data port (0x330) -- the MPU's ACK
;        byte (0xFE).
;
;   Both polls are bounded by a 16-bit countdown so a hung MPU
;   doesn't lock the machine.
;
;   The whole thing runs with interrupts disabled (CLI / PUSHF / POPF)
;   because the MPU is timing-sensitive and a stray IRQ between the
;   status check and the I/O write would corrupt the handshake.
;
;   Type:        Subroutine (MPU I/O)
;   Category:    MPU I/O
;   Callers:     gmd_mpu_reset, gmd_load_patch_bank
;   Callees:     none
;
;   Inputs:
;     BL  --  command byte to send
;   Outputs:     none (the MPU's ACK is read and discarded).
;   Touches:
;     AX, CX, DX preserved (PUSHed/POPped). Flags restored via POPF.
;
;   Side effects:
;     One byte written to MPU command port 0x331; one ACK byte read
;     from MPU data port 0x330. Interrupts disabled for the duration
;     of the handshake.
; ============================================================================

gmd_mpu_write_cmd PROC NEAR
                PUSHF
                CLI
                PUSH    AX
                PUSH    CX
                PUSH    DX

                MOV     CX, 0FFFFH              ; spin-loop budget for poll #1
                MOV     DX, 0331H               ; MPU command/status port
wcmd_wait_rdy:  IN      AL, DX                  ; read status
                TEST    AL, 040H                ; output-buffer-full?
                JZ      SHORT wcmd_ready
                DEC     CX
                CMP     CX, 0
                JNZ     SHORT wcmd_wait_rdy
                JMP     SHORT wcmd_done         ; timed out -- give up silently

wcmd_ready:     MOV     AL, BL                  ; command byte
                OUT     DX, AL                  ; write to 0x331

                MOV     CX, 0FFFFH              ; spin-loop budget for poll #2
wcmd_wait_ack:  IN      AL, DX                  ; read status
                ROL     AL, 1                   ; bit 7 -> CF (input-data-avail)
                JNC     SHORT wcmd_consume      ; ack received (CF=0)
                DEC     CX
                CMP     CX, 0
                JNZ     SHORT wcmd_wait_ack
                                                ; CX exhausted: fall through
                                                ; into the consume path (no
                                                ; explicit timeout branch).

wcmd_consume:   MOV     DX, 0330H               ; MPU data port
                IN      AL, DX                  ; consume MPU's ACK byte
                CMP     AL, 0FEH                ; ACK should be 0xFE
                JZ      SHORT wcmd_done

wcmd_done:      POP     DX
                POP     CX
                POP     AX
                POPF
                RET
gmd_mpu_write_cmd ENDP

; ============================================================================
; 0x084C  --  gmd_mpu_write_data
;
;   Send one byte to the MPU-401 *data* port (0x330). Simpler
;   handshake than the command port: wait for the output-buffer-ready
;   flag, then write the byte. We also drain any incoming MIDI byte
;   that arrives while we wait (the MPU buffers input separately, but
;   reading clears the buffer-full flag).
;
;   Type:        Subroutine (MPU I/O)
;   Category:    MPU I/O
;   Callers:     gmd_mpu_send_msg, gmd_load_patch_bank
;   Callees:     none
;
;   Inputs:
;     BL  --  data byte to send
;   Outputs:     none.
;   Touches:
;     AX, CX, DX preserved. Flags restored via POPF.
;
;   Side effects:
;     One byte written to MPU data port 0x330. May read and discard
;     one incoming MIDI byte from the same port while waiting for the
;     output buffer. If the spin-loop budget exhausts, the byte is
;     silently dropped (rare; the MPU is normally ready immediately).
;     Interrupts disabled for the duration of the handshake.
; ============================================================================

gmd_mpu_write_data PROC NEAR
                PUSHF
                CLI
                PUSH    AX
                PUSH    CX
                PUSH    DX

                MOV     DX, 0331H               ; MPU status port
                MOV     CX, 00FFH               ; spin-loop budget

wdat_loop:      IN      AL, DX                  ; read status
                TEST    AL, 040H                ; output-buffer-full?
                JZ      SHORT wdat_ready
                DEC     CX
                ROL     AL, 1                   ; bit 7 -> CF
                JC      SHORT wdat_no_input
                MOV     DX, 0330H
                IN      AL, DX                  ; drain incoming byte
                MOV     DX, 0331H
wdat_no_input:  CMP     CX, 1
                JGE     SHORT wdat_loop
                JMP     SHORT wdat_done

wdat_ready:     MOV     DX, 0330H               ; MPU data port
                MOV     AL, BL
                OUT     DX, AL                  ; write data byte

wdat_done:      POP     DX
                POP     CX
                POP     AX
                POPF
                RET
gmd_mpu_write_data ENDP

; ============================================================================
; 0x087A  --  gmd_apply_master_volume  (slot 12)
;
;   Set / query the driver's master volume (0..15). On a set with
;   master-enable on, we re-issue CC 7 (main volume) on channels 1..9
;   so the synth picks up the new scaling immediately. Channels 0
;   and 10..15 are never refreshed -- channel 0 is reserved and
;   channels 10..15 are unused by the game's music engine.
;
;   Type:        Slot handler
;   Category:    Driver state
;   Dispatch:    Slot 12 (BP=12, CL=value or 0xFF for query)
;   Callers:     Game (via dispatch); gmd_set_master_enable (on un-mute);
;                gmd_load_patch_bank (after bank upload).
;   Callees:     gmd_midi_control_change
;
;   Inputs:
;     CL  --  new master volume, or 0xFF to query (return current, no
;             write)
;   Outputs:
;     AL  --  previous (or current) master volume, zero-extended
;   Touches:     all caller registers preserved (saves BX, CX, SI).
;
;   Side effects:
;     gmd_master_volume <- CL  (unless CL=0xFF query).
;     When master_enable is set, re-issues CC 7 (main volume) on each
;     of channels 1..9 that has a cached gmd_ch_volume[ch] != 0xFF.
;     Each re-issue routes through gmd_midi_control_change and produces
;     one MIDI message on the wire.
; ============================================================================

gmd_apply_master_volume PROC NEAR
                PUSH    BX
                PUSH    CX
                PUSH    SI
                MOV     AL, CS:[gmd_master_volume]
                XOR     AH, AH
                CMP     CL, 0FFH                ; query?
                JZ      SHORT amv_done
                MOV     CS:[gmd_master_volume], CL
                CMP     byte ptr CS:[gmd_master_enable], 0
                JZ      SHORT amv_done          ; muted -> don't refresh CCs
                PUSH    AX                      ; save return value
                MOV     AL, 1                   ; AL = channel iterator
                MOV     SI, 1                   ; SI = channel index
                MOV     CH, 7                   ; CC 7 (main volume)
amv_loop:       MOV     CL, CS:[SI + gmd_ch_volume]
                CMP     CL, 0FFH                ; no volume cached -> skip
                JZ      SHORT amv_next
                CALL    gmd_midi_control_change
amv_next:       INC     AL
                INC     SI
                CMP     AL, 0AH                 ; stop after channel 9
                JNZ     SHORT amv_loop
                POP     AX
amv_done:       POP     SI
                POP     CX
                POP     BX
                RET
gmd_apply_master_volume ENDP

; ============================================================================
; 0x08B6  --  gmd_set_master_enable  (slot 13)
;
;   Master enable / mute flag. CL=0 mutes (silences channels 1..9
;   by sending each CC 7 = 0, then sets the enable flag to 0).
;   CL=1 un-mutes (sets the enable flag and re-applies the master
;   volume via gmd_apply_master_volume). CL=0xFF queries.
;
;   Type:        Slot handler
;   Category:    Driver state
;   Dispatch:    Slot 13 (BP=13, CL=0/1/0xFF)
;   Callers:     Game (via dispatch)
;   Callees:     gmd_mpu_send_msg (mute path), gmd_apply_master_volume
;                (un-mute path).
;
;   Inputs:
;     CL  --  0 = mute, 1 = enable, 0xFF = query
;   Outputs:
;     AL  --  previous (or current) enable flag, zero-extended into AX
;   Touches:     all caller registers preserved (saves AX, CX in the
;                set path); CL preserved.
;
;   Side effects:
;     gmd_master_enable <- 0 or 1 (unless query).
;     Mute path: emits CC 7 = 0 on channels 1..9 (9 MIDI messages).
;     Un-mute path: calls gmd_apply_master_volume which re-issues CC 7
;     on each active channel.
; ============================================================================

gmd_set_master_enable PROC NEAR
                XOR     AH, AH
                MOV     AL, CS:[gmd_master_enable]
                CMP     CL, 0FFH                ; query?
                JNZ     SHORT sme_setval
                RET
sme_setval:     PUSH    AX
                PUSH    CX
                CMP     CL, 0
                JNZ     SHORT sme_enable

                ; Mute path: walk channels 1..9 sending CC 7 = 0,
                ; then clear the master-enable flag.
                MOV     byte ptr CS:[gmd_master_enable], 0
                MOV     AL, 1                   ; channel iterator
                MOV     AH, 0B0H                ; status: CC
                MOV     CH, 7                   ; CC 7 (main volume)
                MOV     CL, 0                   ; value 0 = silence
sme_mute_loop:  CALL    gmd_mpu_send_msg
                INC     AL
                CMP     AL, 0AH
                JNZ     SHORT sme_mute_loop
                POP     CX
                POP     AX
                RET

sme_enable:     MOV     byte ptr CS:[gmd_master_enable], 1
                MOV     CL, CS:[gmd_master_volume]
                CALL    gmd_apply_master_volume
                POP     CX
                POP     AX
                RET
gmd_set_master_enable ENDP

; ============================================================================
; 0x08F4  --  gmd_mpu_reset
;
;   Send the MPU-401 "reset" command (0xFF) -- this drops the MPU
;   into its idle state and clears any pending I/O. Used by
;   gmd_reset_voices (slot 2) and gmd_load_patch_bank (slot 1)
;   before bank upload.
;
;   Type:        Subroutine (MPU I/O)
;   Category:    MPU I/O
;   Callers:     gmd_reset_voices, gmd_load_patch_bank
;   Callees:     gmd_mpu_write_cmd
;
;   Inputs:      none
;   Outputs:     none
;   Touches:     BX saved and restored.
;
;   Side effects:
;     One MPU-401 "reset" command (0xFF) issued on port 0x331; the
;     chip's ACK is read by gmd_mpu_write_cmd.
; ============================================================================

gmd_mpu_reset   PROC    NEAR
                PUSH    BX
                MOV     BL, 0FFH                ; MPU "reset"
                CALL    gmd_mpu_write_cmd
                POP     BX
                RET
gmd_mpu_reset   ENDP

; ============================================================================
; 0x08FC  --  gmd_query_state  (slot 17)
;
;   Return the current cached value of a specific MIDI parameter on
;   a specific channel. The game uses this to read back the synth's
;   shadow state without triggering any MIDI traffic.
;
;   AH selects what to query:
;
;     0xC0  -- program number (returns gmd_ch_program[ch] in AL)
;     0xE0  -- pitch bend     (returns 14-bit value packed in AX)
;     0xB0  -- a controller, selected by CH:
;               CH=0x01 modulation
;               CH=0x07 main volume
;               CH=0x0A pan
;               CH=0x40 sustain
;               CH=0x4B -> always returns 0xFFFF (sentinel)
;               other   -> returns 0xFFFF
;
;   Pitch Bend formatting: cached as two bytes (LSB, MSB). To return,
;   we XCHG to put bytes in conventional order, then re-pack the bit-7
;   the MIDI spec puts at the *low* bit of the MSB. This matches the
;   layout the game-side expects.
;
;   Type:        Slot handler
;   Category:    Driver state
;   Dispatch:    Slot 17 (BP=17, AL=ch, AH=class, CH=cc#, CL=sub)
;   Callers:     Game (via dispatch)
;   Callees:     none
;
;   Inputs:
;     AL  --  MIDI channel (0..15)
;     AH  --  query class: 0xC0=program, 0xE0=pitch-bend, 0xB0=CC
;     CH  --  controller number when AH=0xB0
;   Outputs:
;     AX  --  parameter value, or 0xFFFF if unknown
;   Touches:     SI saved and restored; AX overwritten with the result.
;   Side effects: none (pure read of cached shadow state).
; ============================================================================

gmd_query_state PROC    NEAR
                PUSH    SI
                MOV     SI, AX
                AND     SI, 000FH               ; SI = channel

                CMP     AH, 0E0H                ; Pitch Bend?
                JNZ     SHORT qs_not_pb
                SHL     SI, 1
                MOV     AX, word ptr CS:[SI + gmd_ch_pitchbend]
                DB      083H, 0F8H, 0FFH        ; CMP AX, -1 (sign-ext form)
                JZ      SHORT qs_done
                XCHG    AH, AL                  ; swap to (msb, lsb) order
                SHR     AH, 1                   ; CF = original bit 0 of MSB
                JNC     SHORT qs_pb_no_b7       ; bit was 0 -> nothing to do
                OR      AL, 080H                ; restore bit 7 into LSB
qs_pb_no_b7:    JMP     SHORT qs_done

qs_not_pb:      CMP     AH, 0C0H                ; Program Change?
                JNZ     SHORT qs_not_pc
                MOV     AL, CS:[SI + gmd_ch_program]
                JMP     SHORT qs_done

qs_not_pc:      CMP     AH, 0B0H                ; Control Change?
                JNZ     SHORT qs_unknown
                CMP     CH, 04BH                ; CC 0x4B -> sentinel
                JZ      SHORT qs_unknown
                CMP     CH, 001H                ; CC modulation
                JNZ     SHORT qs_cc_not_mod
                MOV     AL, CS:[SI + gmd_ch_modulation]
                JMP     SHORT qs_done
qs_cc_not_mod:  CMP     CH, 007H                ; CC main volume
                JNZ     SHORT qs_cc_not_vol
                MOV     AL, CS:[SI + gmd_ch_volume]
                JMP     SHORT qs_done
qs_cc_not_vol:  CMP     CH, 00AH                ; CC pan
                JNZ     SHORT qs_cc_not_pan
                MOV     AL, CS:[SI + gmd_ch_pan]
                JMP     SHORT qs_done
qs_cc_not_pan:  CMP     CH, 040H                ; CC sustain
                JNZ     SHORT qs_unknown
                MOV     AL, CS:[SI + gmd_ch_sustain]
                JMP     SHORT qs_done

qs_unknown:     MOV     AX, 0FFFFH
qs_done:        POP     SI
                RET
gmd_query_state ENDP

; ============================================================================
; 0x0968  --  gmd_load_patch_bank  (slot 1)
;
;   Copy a 0x481-byte patch bank from ES:[AX] into the driver's
;   internal tables at CS:[0x0041..0x04C1], then process the
;   bank's "init MIDI" tail.
;
;   Steps:
;     1. Reset the MPU.
;     2. Send the "set UART mode" command (0x3F) three times --
;        belt-and-braces because the MPU can be in arbitrary state
;        from a previous driver / boot.
;     3. Delay loops between each command (the chip needs settling
;        time after a reset).
;     4. Copy 0x481 bytes from ES:[SI] to CS:[DI + 0x41].
;     5. Stage one byte from the bank ([0x0241]) into runtime
;        state at [0x0561].
;     6. Read a 16-bit "init message length" from ES:[SI], then
;        forward that many bytes as raw MIDI data via
;        gmd_mpu_write_data. Each 0xF7 byte (SysEx end-of-message)
;        gets an extra double delay so the synth can absorb the
;        message before the next one starts.
;     7. Re-apply the master volume via gmd_apply_master_volume so
;        any per-channel CC 7s get re-issued.
;
;   Returns AX = the offset of this very function (0x0968). The game
;   side doesn't appear to use this value, but it's part of the slot's
;   contract.
;
;   Notes:
;     The patch bank's init tail typically contains the GM Reset SysEx
;     `F0 7E 7F 09 01 F7` (Universal Real Time -> Sub-ID 09 = General
;     MIDI -> Sub-ID 01 = GM On). This driver doesn't generate that
;     SysEx itself; it forwards whatever bank bytes the game supplies
;     through gmd_mpu_write_data at step 6 below. The literal bytes
;     therefore appear at runtime rather than as a static DB literal in
;     this source -- see the glossary entry "GM Reset SysEx".
;
;   Type:        Slot handler
;   Category:    Bank loading
;   Dispatch:    Slot 1 (BP=1, ES:AX = far ptr to bank)
;   Callers:     Game (via dispatch)
;   Callees:     gmd_mpu_reset, gmd_mpu_write_cmd, gmd_mpu_delay,
;                gmd_mpu_write_data, gmd_apply_master_volume
;
;   Inputs:
;     ES:AX --  far pointer to the bank in main memory
;   Outputs:
;     AX  --  0x0968 (this function's offset; self-id handshake)
;     CL  --  1
;     CH  --  8
;   Touches:     SI saved and restored; AX, BX, CX, DI clobbered as
;                scratch.
;
;   Side effects:
;     0x481 bytes copied from ES:[AX] into CS:[gmd_patch_prog_xlat..].
;     gmd_ch_state_558[9] <- gmd_patch_extra_xlat0.
;     Up to N raw MIDI bytes from the bank's init-message tail emitted
;     via gmd_mpu_write_data (with an extra delay after each 0xF7 SysEx
;     EOX). MPU set into UART mode (three 0x3F commands). Master volume
;     forced to 0x0C via gmd_apply_master_volume, which then re-issues
;     CC 7 across active channels.
; ============================================================================

gmd_load_patch_bank PROC NEAR
                PUSH    SI
                CALL    gmd_mpu_reset
                MOV     BX, 003FH               ; MPU "set UART mode"
                CALL    gmd_mpu_write_cmd
                CALL    gmd_mpu_delay
                MOV     BX, 003FH
                CALL    gmd_mpu_write_cmd
                CALL    gmd_mpu_delay
                MOV     BX, 003FH
                CALL    gmd_mpu_write_cmd
                CALL    gmd_mpu_delay
                CALL    gmd_mpu_delay

                MOV     SI, AX                  ; SI = bank src offset
                MOV     DI, 0                   ; DI = bank dst offset
lpb_copy_loop:  MOV     BL, ES:[SI]
                MOV     CS:[DI + gmd_patch_prog_xlat], BL
                INC     DI
                INC     SI
                CMP     DI, 0481H
                JNZ     SHORT lpb_copy_loop

                ; The bank's byte at offset 0x0241 (inside the patch
                ; tables, between the drum-remap and the velocity-
                ; curve selector blocks) is also mirrored into the
                ; runtime state at 0x0561 (gmd_ch_state_558 + 9 ?).
                MOV     BL, CS:[gmd_patch_extra_xlat0]
                MOV     CS:[gmd_ch_state_558 + 9], BL

                ; Read the 16-bit "init-message" byte count from
                ; the bank's tail.
                MOV     CL, ES:[SI]
                INC     SI
                MOV     CH, ES:[SI]
                INC     SI
                CMP     CX, 0
                JZ      SHORT lpb_init_done

lpb_init_loop:  MOV     BL, ES:[SI]
                INC     SI
                CALL    gmd_mpu_write_data
                CMP     BL, 0F7H                ; SysEx EOX?
                JNZ     SHORT lpb_init_next
                CALL    gmd_mpu_delay
                CALL    gmd_mpu_delay
lpb_init_next:  LOOP    lpb_init_loop

lpb_init_done:  MOV     CL, 00CH
                CALL    gmd_apply_master_volume
                MOV     AX, OFFSET gmd_load_patch_bank ; return self-offset
                MOV     CL, 1
                MOV     CH, 8
                POP     SI
                RET
gmd_load_patch_bank ENDP

; ============================================================================
; 0x09D8  --  gmd_mpu_delay
;
;   Spin in a tight read-status loop for ~0x7500 (30,000) iterations.
;   At an 8088's ~0.5 MIPS rate, this is ~60 ms; on a 286 / 386 /
;   486 it's much shorter, but every period-correct setup is fine
;   with that.
;
;   The reads from port 0x331 inside the loop are not just busywork
;   -- reading the status port is the way you signal the MPU "I'm
;   still here" while it processes a previous reset/UART command.
;
;   Type:        Subroutine (timing helper)
;   Category:    MPU I/O
;   Callers:     gmd_load_patch_bank
;   Callees:     none
;
;   Inputs:      none
;   Outputs:     none
;   Touches:     AX, DX, DI saved and restored.
;
;   Side effects:
;     ~30,000 status-port reads on 0x331. No state change visible to
;     the rest of the driver; the only purpose is wall-clock delay.
; ============================================================================

gmd_mpu_delay   PROC    NEAR
                PUSH    AX
                PUSH    DX
                PUSH    DI
                MOV     DX, 0331H
                MOV     DI, 07500H
dly_loop:       IN      AL, DX
                DEC     DI
                CMP     DI, 0
                JNZ     SHORT dly_loop
                POP     DI
                POP     DX
                POP     AX
                RET
gmd_mpu_delay   ENDP

; ============================================================================
; 0x09EC  --  gmd_get_info  (slot 0)
;
;   The game's driver-introspection slot. Returns four register
;   values that identify the driver to the music engine:
;
;     AX = 0x0104  -- a version / capability word
;     CX = 0x0720  -- another capability word
;                     (CH = 7 = output bytes/second class? CL = 0x20)
;
;   The exact bit-level meaning of each word is unknown; the driver
;   just returns these fixed capability values.
;
;   Type:        Slot handler
;   Category:    Capability query
;   Dispatch:    Slot 0 (BP=0; no other arguments)
;   Callers:     Game (via dispatch)
;   Callees:     none
;
;   Inputs:      none
;   Outputs:
;     AH  --  1
;     AL  --  4
;     CH  --  7
;     CL  --  0x20
;   Touches:     AX, CX overwritten with the return values.
;   Side effects: none
; ============================================================================

gmd_get_info    PROC    NEAR
                MOV     AH, 1
                MOV     AL, 4
                MOV     CH, 7
                MOV     CL, 020H
                RET
gmd_get_info    ENDP

; ============================================================================
; Glossary of acronyms used in this file (alphabetical)
;
;   ACK            "Acknowledge" -- a one-byte response (0xFE) that the
;                  MPU-401 sends back on the data port after it has
;                  finished processing a command-port write.
;   CC             MIDI Continuous Controller. A two-byte payload (cc#,
;                  value) that follows a 0xB0+ch status byte. GM
;                  reserves certain cc#'s by convention:
;                    CC#1   Modulation Wheel
;                    CC#7   Channel Main Volume   (0..127)
;                    CC#10  Pan position          (0=left, 64=center,
;                                                  127=right)
;                    CC#11  Expression (a finer-grained per-passage
;                           volume scaler -- not used by this driver)
;                    CC#64  Sustain Pedal         (0..63 off, 64..127 on)
;                    CC#123 All Notes Off (driver-emitted "panic stop")
;                  This driver caches and forwards CC#1, CC#7, CC#10,
;                  CC#64; emits CC#123 + CC#64-off on program change;
;                  silently drops every other cc#.
;   CS-relative    Memory access that uses the Code Segment (CS) register
;                  as the segment base. In this driver every read/write
;                  is CS-relative because data and code share one
;                  segment.
;   DUDE           Dynamix Universal Driver Engine (probable expansion).
;                  The container format every Sx.SSM.*.bin in the game
;                  shares -- common header, 18-slot dispatch table.
;   EOX            End-of-Exclusive. The 0xF7 byte that terminates a
;                  SysEx message on the MIDI wire.
;   GM (General    A 1991 MMA / AMEI standard that fixes which patch
;    MIDI)         number plays which instrument, that channel 9 is
;                  always drums, that pitch-bend range is +/- 2
;                  semitones, etc. A "GM synth" is any synth that
;                  follows this mapping -- Roland Sound Canvas,
;                  Yamaha MU-series, the GM mode of the Roland SC-55,
;                  and many software synths today. Because the mapping
;                  is standardised, the driver doesn't need to ship FM
;                  patch parameters the way the AdLib driver does; it
;                  only needs a small game-program -> GM-program
;                  translation table per song.
;   GM Reset       A 6-byte SysEx message (F0 7E 7F 09 01 F7) that puts
;    SysEx         any GM-compliant synth back into its default state
;                  (all controllers zeroed, all programs reset). This
;                  driver does not emit it directly; it is one of the
;                  messages a bank's init-message tail may contain
;                  (see gmd_load_patch_bank).
;   MIDI           Musical Instrument Digital Interface. The 1983
;                  serial-wire protocol every electronic music device
;                  speaks. A MIDI byte is either a "status" byte
;                  (high bit set, encodes message-type + 4-bit channel)
;                  or a "data" byte (high bit clear, 7-bit payload).
;   MIDI channel   One of 16 independent voices on a MIDI wire.
;                  Encoded as the low 4 bits of every status byte. GM
;                  reserves channel 9 (zero-based) for percussion.
;   MIDI note      0..127, where 60 = middle C. Each integer is one
;                  semitone.
;   MPU-401        Roland's 1984 MIDI interface card. The original
;                  hardware had a small CPU on-board that handled MIDI
;                  timing in "Intelligent mode"; the cheaper "UART
;                  mode" (entered with command 0x3F) turns it into a
;                  transparent byte pipe -- which is what this driver
;                  uses. Almost every PC MIDI card of the era cloned
;                  the MPU-401 UART-mode interface.
;   MPU-401 UART   The two-port "send a byte, get a byte" mode entered
;    mode          by command 0x3F. Unlike Intelligent mode (which
;                  needs per-event timing data + an IRQ handler) UART
;                  mode is symmetric with the MIDI wire: every write
;                  to the data port becomes a MIDI byte. This is the
;                  *same* hardware path the MT-32 driver uses; the
;                  difference between GMD and M32 is what bytes the
;                  driver chooses to send, not how they're physically
;                  delivered. (M32 in particular uploads a custom
;                  patch bank via SysEx; GMD does not because GM
;                  standardises the patches.)
;   Patch / patch  In the FM-synthesis world ("patch" = a set of
;    bank          oscillator parameters defining one timbre) the bank
;                  is the full set of patches. For GM the patches are
;                  baked into the synth's ROM, so the "bank" this
;                  driver loads is really four translation tables
;                  (game-program -> GM-program + transpose + volume
;                  bias + velocity-curve selector) plus four 128-byte
;                  velocity-curve tables.
;   Pitch bend     A 14-bit (LSB+MSB) signed offset applied to every
;                  note on a channel. 0x2000 is center / no bend;
;                  0x0000 = -2 semitones; 0x3FFF = +2 semitones (the
;                  GM default range).
;   Program        The MIDI command "from now on, play notes on this
;    Change        channel using instrument <program>" (1 data byte,
;                  0..127). In GM, program 0 = Acoustic Grand Piano,
;                  program 40 = Violin, etc.
;   Running        A bandwidth optimisation in the MIDI spec: after a
;    status        status byte is sent, subsequent messages with the
;                  same status can omit the status byte and just send
;                  data bytes. This driver does *not* exploit this on
;                  the wire (every message emits the status byte
;                  explicitly); gmd_last_status is a cache only.
;   SysEx          System Exclusive. A variable-length MIDI message
;                  framed by 0xF0 ... 0xF7, used for synth-specific
;                  payloads the standard doesn't cover. The GM Reset
;                  message above is one example.
;   UART           Universal Asynchronous Receiver/Transmitter -- the
;                  standard serial-port chip family. In the MPU-401
;                  context the term is used loosely to mean "act like
;                  a transparent serial port".
;   Velocity       0..127. How "hard" a note was struck. GM defines no
;                  specific mapping to volume -- each synth is free to
;                  shape the velocity-to-loudness curve. This driver
;                  applies its own 128-byte curve (one of four,
;                  selected per-channel) before sending the velocity
;                  on the wire.
; ============================================================================

                END     _start
