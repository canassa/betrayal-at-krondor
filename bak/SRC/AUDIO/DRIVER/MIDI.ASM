; ============================================================================
; MIDI.ASM -- KRONDOR.EXE segment 0x32c8: the software MIDI / music
;                sequencer + voice allocator ("the midi_ segment")
;
; The whole segment is one TASM module: all 69 functions plus the segment's
; CS-resident data block (offsets 0x01c2..0x03c6). Base linear address is
; 0x32c80 (paragraph 0x32c8, offset 0x0000).
;
; What this module does (high level)
; ----------------------------------
; A sound driver turns a "play this note" request into hardware register writes.
; This module sits one layer ABOVE that: it is a software MIDI *sequencer*. It
; reads the game's compiled music scripts (streams of MIDI-ish status/data
; bytes), advances them on a periodic timer tick, decodes the events, keeps
; per-channel state (program, volume, pitch bend, controllers), runs volume
; fades, and -- because a song can ask for more simultaneous notes than the
; sound card has physical "voices" -- arbitrates a fixed pool of hardware
; voices among the logically-active notes. It NEVER touches a sound chip
; directly: every actual sound action is emitted by an indirect far CALL through
; a driver-dispatch vector (see the "Driver-dispatch ABI" primer below), into
; whichever hardware driver (AdLib/SB/MT-32/...) was installed at boot.
;
; The same per-track record type doubles as a generic cooperative
; task/animation scheduler (the fade/ramp engine), so "the scheduler" and "the
; sequencer" are two faces of one data structure.
;
; Reference docs beside this file:
;   reference/midi_32c8_behavior.md     -- algorithms & data model
;   reference/midi_32c8_integration.md  -- callers + the hardware-driver handoff
;   reference/midi_32c8_inventory.md    -- function inventory
;   repo-root segment-docs.md           -- the 32c8 = midi_ segment registry
;   repo-root driver.md                 -- the AdLib driver / DUDE slot ABI
;
; The g_bMusicDriverInstalled word (0x0645) and the three
; _snddrv_dispatch_cached far-call sites (0x0f46, 0x1c20, 0x1c3d) are extern
; fixups resolved by the linker's relocation.
;
; Toolchain conventions
; ---------------------
; 1. The module assembles under NOSMART, and the 25 command-handler procs the
;    wrappers reach via same-segment far calls are typed "proc far" (their
;    bodies end in explicit "retf"). NOSMART stops TASM pre-converting those
;    calls, so each wrapper site emits a real far-call FIXUPP (TLINK's pass-1
;    header estimate counts them, then its backward far->near collapse rewrites
;    every site to 90 0e e8 = NOP + PUSH CS + near CALL). Procs only ever
;    entered by far CALL from OUTSIDE the segment stay "proc near" with explicit
;    "retf" (no same-segment call sites exist for them, so no fixup is at stake).
;
; 2. The driver-dispatch vector is referenced as "[_cs_drvvec]" (a CS-resident
;    label) under "assume cs:S32c8_TEXT". These encode as CS-relative indirect
;    calls -- byte 0x2E (CS: segment-override prefix) followed by "FF 1E <addr>".
;    Naming the CS label and letting "assume" drive the override makes TASM emit
;    the 2E FF 1E ... bytes. All ~50 driver-vector calls use this.
;
; 3. CS-resident labels are declared with "db" (raw bytes), so TASM infers byte
;    size for them. Every memory access through such a label therefore carries
;    an explicit "word ptr" / "dword ptr" / "byte ptr" size specifier to fix the
;    operand width.
;
; 4. A handful of instructions are emitted as raw "db/dw" with an explanatory
;    comment (e.g. "db 081h,0e6h / dw 0000fh   ; and SI,0xf"). "AND SI, 0x0F"
;    uses a forced imm16 (81 E6 0F 00) rather than the shorter imm8 sign-extended
;    form (83 E6 0F); the db/dw forces the long form.
;
; CS-resident data block label map (all addresses are CS-relative within 32c8)
; ---------------------------------------------------------------------------
;   _cs_track_registry    0x01c2  16 x far-ptr: priority-ordered active tracks
;   _cs_pending_track     0x0202  16 x far-ptr: SFX/streaming-track mirror list
;   _cs_voice_track_table 0x0242  16 x far-ptr: owning track of each voice
;   _cs_prog_scratch      0x02c2  program-table parse scratch (16 words)
;   _cs_voice_ch_table    0x02e2  16 x voice -> (track<<2 | channel), 0xFF=free
;   _cs_voice_flags       0x02f2  16 x per-voice drum/percussion flag
;   _cs_voice_priority    0x0302  16 x per-voice age/idle counter (steal pick)
;   _cs_voice_credit      0x0312  16 x per-voice cost (note-count weight)
;   _cs_voice_note        0x0322  16 x recompute staging copy of voice owner
;   _cs_voice_snap        0x0332  save/restore band for rollback during arbitr.
;   _cs_voice_ch_cache    0x0372  16 x per-voice channel nibble
;   _cs_voice_refresh     0x0382  16 x pending-action queue (scheduler_advance)
;   _cs_drvvec            0x03a1  far ptr to installed hardware driver entry
;   _cs_cmd_slots         0x03a5  6-word command-argument staging area
;   _cs_pause_refcount    0x03b3  master lock + a packed block of global scalars
;
; NOTE on _cs_pause_refcount: byte +0 is the pause/lock refcount, but offsets
; +1..+19 from this label are a contiguous block of unrelated module globals
; that the original placed adjacently (voice-range bounds, default program /
; channel, the global tempo knob, the voices-dirty flag, the seek-in-progress
; flag, etc.). They are addressed as "[_cs_pause_refcount + N]" throughout;
; each such access is annotated at its use site.
; ============================================================================

.386P

; ----------------------------------------------------------------------------
; The hardware-driver dispatch ABI (what [_cs_drvvec] and _snddrv_dispatch_cached
; reach, and how)
;
; This module produces sound by calling DOWN into an installed hardware driver
; through two far function pointers. The driver itself is a Dynamix "DUDE"
; sound-driver chunk (one per card: AdLib/OPL2, Sound Blaster, MT-32, GenMIDI,
; PC speaker, ...) decompressed from Sx.ovl into the heap at boot and bound by
; far pointer. The driver sources (with the full DUDE slot ABI) are the hand-
; written TASM modules under SRC\DRIVERS\SX\.
;
;   1. Primary per-event vector  _cs_drvvec (CS:0x03a1)
;        Patched at install time by midi_cmd0_program_change (MOV CS:[03a1],AX /
;        MOV CS:[03a3],ES). Called as  CALL DWORD PTR [_cs_drvvec]  from ~50
;        sites. It is a REGISTER ABI, not a C stack call:
;            BP = slot / sub-command selector (loaded just before the CALL)
;            AL = MIDI channel (AL & 0x0f)
;            CH = data byte 1 (note / program / controller)
;            CL = data byte 2 (velocity / value)
;            AH (on return from BP=0 install) = card capability/voice nibble
;        Observed selectors: BP=0 init/probe, 4 note-off, 5 note-on, 6 aftertouch/
;        bend, 7 controller, 8 program, 9 channel-pressure, 0x0a pitch word,
;        0x0b set-global, 0x0c/0x02 reset pair, 0x0d one-shot. The caller wraps
;        every dispatch in PUSH BP / MOV BP,<sel> / CALL / POP BP.
;
;   2. Companion cached vector  _snddrv_dispatch_cached (segment 3626:0029)
;        A C-callable __cdecl16far shim (the only external this module links
;        against). Used by midi_track_release and the SFX/streaming pump for the
;        streamed-sample path. Gated on g_bMusicDriverInstalled; caches its AX
;        return. Resolved at link time.
; ----------------------------------------------------------------------------

; --- External functions (not in this module) ---
; snddrv_dispatch_cached = segment 3626:0029
; C-callable __cdecl16far shim into the installed driver; see ABI primer above.
	extrn _snddrv_dispatch_cached:far

; --- DGROUP global references ---
; Nonzero when a music driver has been successfully installed and bound. Read by
; midi_cmd0_program_change to OR in the "drum capable" mode bit. Referenced via
; the DS-relative (relocated) form.
	extrn _g_bMusicDriverInstalled:word

; WORD-aligned, content only: the module starts at the segment's first content
; byte (offset 0x0e). Frame bytes 0x0000-0x000d are the TAIL of a function whose
; body lives in the PRECEDING segment (it far-CALLs 0x32AD:0006 and returns) --
; that segment's module emits them; they are not emitted here. Label references
; carry segment-relative fixups resolved against the frame, so the frame offsets
; land at link time.
S32c8_TEXT	segment word public use16 'CODE'
	assume cs:S32c8_TEXT

; ==============================================================
; FAR-ENTRY THUNK BAND  (offsets 0x000e .. 0x01be, ~18 functions)
;
; This run of small, near-identical functions is the public far-callable
; surface the rest of the engine links against. Each thunk does the same thing:
;   - standard far-entry prologue: PUSH BP / MOV BP,SP, save DS/DI/SI;
;   - marshal the caller's STACK arguments at [BP+06h], [BP+0ah], ... into the
;     register ABI the internal handler expects (LES AX,[BP+6] loads the track
;     far-ptr handle into ES:AX; byte/word args go to CL/CH/CX/DL);
;   - a single NOP (placeholder);
;   - PUSH CS + CALL <internal handler>  (a same-segment near call, hence the
;     explicit PUSH CS and the "proc near" trick -- see file header quirk #1);
;   - restore registers and RETF.
; The plate on each thunk names only WHICH internal handler it wraps; the
; handler's own plate (further down) documents the actual behaviour.
; ==============================================================

; ==============================================================
; midi_stub_return_cx_via_nop_alt  off 0x000e  size 21
; Far thunk -> midi_stub_nop. Loads track handle (ES:AX), returns CX in AX
; (the track's +0x152 marker/cue counter). See thunk-band note above.
; ==============================================================
	public _midi_stub_return_cx_via_nop_alt
_midi_stub_return_cx_via_nop_alt proc near
	push bp
	mov bp, sp
	push ds
	push di
	push si
	les ax, dword ptr [bp+06h]
	nosmart
	call far ptr _midi_stub_nop	; real far-call FIXUPP; 90 0e e8 after TLINK's backward collapse
	smart
	mov ax, cx
	pop si
	pop di
	pop ds
	pop bp
	retf
_midi_stub_return_cx_via_nop_alt endp

; ==============================================================
; midi_chord_event_thunk_0b6e  off 0x0023  size 22
; Far thunk -> midi_chord_propagate_setting. Marshals handle (ES:AX) + priority
; byte (CL <- [BP+0a]). Sets a track's priority and re-sorts the registry.
; ==============================================================
	public _midi_chord_event_thunk_0b6e
_midi_chord_event_thunk_0b6e proc near
	push bp
	mov bp, sp
	push ds
	push di
	push si
	les ax, dword ptr [bp+06h]
	mov cl, byte ptr [bp+0ah]
	nosmart
	call far ptr _midi_chord_propagate_setting	; real far-call FIXUPP; 90 0e e8 after TLINK's backward collapse
	smart
	pop si
	pop di
	pop ds
	pop bp
	retf
_midi_chord_event_thunk_0b6e endp

; ==============================================================
; midi_stub_return_cx_via_nop  off 0x0039  size 23
; Far thunk -> midi_stub_return_ax. Returns the track's elapsed-time readout
; (computed as min:sec) with DH zeroed and the result moved into AX.
; ==============================================================
	public _midi_stub_return_cx_via_nop
_midi_stub_return_cx_via_nop proc near
	push bp
	mov bp, sp
	push ds
	push di
	push si
	les ax, dword ptr [bp+06h]
	nosmart
	call far ptr _midi_stub_return_ax	; real far-call FIXUPP; 90 0e e8 after TLINK's backward collapse
	smart
	xor dh, dh
	mov ax, cx
	pop si
	pop di
	pop ds
	pop bp
	retf
_midi_stub_return_cx_via_nop endp

; ==============================================================
; midi_seek_volume_preserve_thunk  off 0x0050  size 19
; Far thunk -> midi_seek_with_volume_preserve (cmd 5). Fast-forwards a track to
; its current tick while muting output, so volume/state survive the seek.
; ==============================================================
	public _midi_seek_volume_preserve_thunk
_midi_seek_volume_preserve_thunk proc near
	push bp
	mov bp, sp
	push ds
	push di
	push si
	les ax, dword ptr [bp+06h]
	nosmart
	call far ptr _midi_seek_with_volume_preserve	; real far-call FIXUPP; 90 0e e8 after TLINK's backward collapse
	smart
	pop si
	pop di
	pop ds
	pop bp
	retf
_midi_seek_volume_preserve_thunk endp

; ==============================================================
; midi_cmd6_far_wrapper  off 0x0063  size 19
; Far thunk -> midi_call_dispatch_cmd_13000 (cmd 6). Passes a word arg in CX;
; clamps it to <=0x0f and fires the driver "13000" dispatch selector.
; ==============================================================
	public _midi_cmd6_far_wrapper
_midi_cmd6_far_wrapper proc near
	push bp
	mov bp, sp
	push ds
	push di
	push si
	mov cx, word ptr [bp+06h]
	nosmart
	call far ptr _midi_call_dispatch_cmd_13000	; real far-call FIXUPP; 90 0e e8 after TLINK's backward collapse
	smart
	pop si
	pop di
	pop ds
	pop bp
	retf
_midi_cmd6_far_wrapper endp

; ==============================================================
; midi_event_callback_thunk_0a8b  off 0x0076  size 22
; Far thunk -> midi_cmd0a_adjust_hold_count (cmd 0x0a). Handle in ES:AX, +/-
; selector in CL. Pauses/resumes one track (or all if handle is null).
; ==============================================================
	public _midi_event_callback_thunk_0a8b
_midi_event_callback_thunk_0a8b proc near
	push bp
	mov bp, sp
	push ds
	push di
	push si
	les ax, dword ptr [bp+06h]
	mov cl, byte ptr [bp+0ah]
	nosmart
	call far ptr _midi_cmd0a_adjust_hold_count	; real far-call FIXUPP; 90 0e e8 after TLINK's backward collapse
	smart
	pop si
	pop di
	pop ds
	pop bp
	retf
_midi_event_callback_thunk_0a8b endp

; ==============================================================
; midi_driver_install_dispatch  off 0x008c  size 19
; Far thunk -> midi_cmd0_program_change. Install path: LES AX,[BP+6] loads the
; freshly-loaded driver chunk's far-ptr, which cmd0 writes into _cs_drvvec and
; then probes (BP=0). Called by audio_drivers_install (3592) at bind time.
; ==============================================================
	public _midi_driver_install_dispatch
_midi_driver_install_dispatch proc near
	push bp
	mov bp, sp
	push ds
	push di
	push si
	les ax, dword ptr [bp+06h]
	nosmart
	call far ptr _midi_cmd0_program_change	; real far-call FIXUPP; 90 0e e8 after TLINK's backward collapse
	smart
	pop si
	pop di
	pop ds
	pop bp
	retf
_midi_driver_install_dispatch endp

; ==============================================================
; midi_cmd1_save_cx_303b4_thunk  off 0x009f  size 23
; Far thunk -> midi_cmd1_save_cx_303b4 (cmd 1). Zeroes BX, loads handle. cmd1
; saves CX into the voice-range bounds (low/high voice index for arbitration).
; ==============================================================
	public _midi_cmd1_save_cx_303b4_thunk
_midi_cmd1_save_cx_303b4_thunk proc near
	push bp
	mov bp, sp
	push ds
	push di
	push si
	push bx
	xor bx, bx
	les ax, dword ptr [bp+06h]
	nosmart
	call far ptr _midi_cmd1_save_cx_303b4	; real far-call FIXUPP; 90 0e e8 after TLINK's backward collapse
	smart
	pop bx
	pop si
	pop di
	pop ds
	pop bp
	retf
_midi_cmd1_save_cx_303b4_thunk endp

; ==============================================================
; midi_track_init_thunk  off 0x00b6  size 22
; Far thunk -> midi_track_init (cmd 8, "start/play a track"). Handle in ES:AX,
; mode word in CX. Builds per-channel state and registers the track.
; ==============================================================
	public _midi_track_init_thunk
_midi_track_init_thunk proc near
	push bp
	mov bp, sp
	push ds
	push di
	push si
	les ax, dword ptr [bp+06h]
	mov cx, word ptr [bp+0ah]
	nosmart
	call far ptr _midi_track_init	; real far-call FIXUPP; 90 0e e8 after TLINK's backward collapse
	smart
	pop si
	pop di
	pop ds
	pop bp
	retf
_midi_track_init_thunk endp

; ==============================================================
; midi_fade_queue_handle  off 0x00cc  size 28
; Far thunk -> midi_fade_program (cmd 0x0b). Marshals target(DL), step(CL),
; direction(CH). Called by music_fade @ 3589 to program a per-handle fade.
; ==============================================================
	public _midi_fade_queue_handle
_midi_fade_queue_handle proc near
	push bp
	mov bp, sp
	push ds
	push di
	push si
	les ax, dword ptr [bp+06h]
	mov dl, byte ptr [bp+0ah]
	mov cl, byte ptr [bp+0ch]
	mov ch, byte ptr [bp+0eh]
	nosmart
	call far ptr _midi_fade_program	; real far-call FIXUPP; 90 0e e8 after TLINK's backward collapse
	smart
	pop si
	pop di
	pop ds
	pop bp
	retf
_midi_fade_queue_handle endp

; ==============================================================
; midi_cmd4_far_wrapper  off 0x00e8  size 19
; Far thunk -> midi_cmd4_call_driver_13000 (cmd 4). Word arg in CX; single
; driver dispatch with the "13000" (BP=0x0d) selector.
; ==============================================================
	public _midi_cmd4_far_wrapper
_midi_cmd4_far_wrapper proc near
	push bp
	mov bp, sp
	push ds
	push di
	push si
	mov cx, word ptr [bp+06h]
	nosmart
	call far ptr _midi_cmd4_call_driver_13000	; real far-call FIXUPP; 90 0e e8 after TLINK's backward collapse
	smart
	pop si
	pop di
	pop ds
	pop bp
	retf
_midi_cmd4_far_wrapper endp

; ==============================================================
; midi_track_apply_intensity  off 0x00fb  size 22
; Far thunk -> midi_cmd0e_apply_vel_track (cmd 0x0e). Handle + value
; (CL). Pushes a new velocity/volume to all of a track's active voices.
; ==============================================================
	public _midi_track_apply_intensity
_midi_track_apply_intensity proc near
	push bp
	mov bp, sp
	push ds
	push di
	push si
	les ax, dword ptr [bp+06h]
	mov cl, byte ptr [bp+0ah]
	nosmart
	call far ptr _midi_cmd0e_apply_vel_track	; real far-call FIXUPP; 90 0e e8 after TLINK's backward collapse
	smart
	pop si
	pop di
	pop ds
	pop bp
	retf
_midi_track_apply_intensity endp

; ==============================================================
; midi_track_set_word_bc_far  off 0x0111  size 25
; Far thunk -> midi_track_set_word_bc (cmd 0x17). Handle + word(CX) + flag(DL).
; Sets a channel's +0xbc pitch/sustain word and re-keys matching voices.
; ==============================================================
	public _midi_track_set_word_bc_far
_midi_track_set_word_bc_far proc near
	push bp
	mov bp, sp
	push ds
	push di
	push si
	les ax, dword ptr [bp+06h]
	mov cx, word ptr [bp+0ah]
	mov dl, byte ptr [bp+0ch]
	nosmart
	call far ptr _midi_track_set_word_bc	; real far-call FIXUPP; 90 0e e8 after TLINK's backward collapse
	smart
	pop si
	pop di
	pop ds
	pop bp
	retf
_midi_track_set_word_bc_far endp

; ==============================================================
; midi_active_release_thunk  off 0x012a  size 19
; Far thunk -> midi_cmd9_release_and_recompute (cmd 9, "stop"). Handle in ES:AX.
; Releases the track from the registry and re-arbitrates voices.
; ==============================================================
	public _midi_active_release_thunk
_midi_active_release_thunk proc near
	push bp
	mov bp, sp
	push ds
	push di
	push si
	les ax, dword ptr [bp+06h]
	nosmart
	call far ptr _midi_cmd9_release_and_recompute	; real far-call FIXUPP; 90 0e e8 after TLINK's backward collapse
	smart
	pop si
	pop di
	pop ds
	pop bp
	retf
_midi_active_release_thunk endp

; ==============================================================
; midi_track_set_byte_15a  off 0x013d  size 22
; Far thunk -> midi_track_write_byte_15a_inner (cmd 0x0c). Handle + value (CL).
; Sets the track's loop/cue id byte (+0x15a), compared by controller 0x52.
; ==============================================================
	public _midi_track_set_byte_15a
_midi_track_set_byte_15a proc near
	push bp
	mov bp, sp
	push ds
	push di
	push si
	les ax, dword ptr [bp+06h]
	mov cl, byte ptr [bp+0ah]
	nosmart
	call far ptr _midi_track_write_byte_15a_inner	; real far-call FIXUPP; 90 0e e8 after TLINK's backward collapse
	smart
	pop si
	pop di
	pop ds
	pop bp
	retf
_midi_track_set_byte_15a endp

; ==============================================================
; midi_track_read_byte_158_far  off 0x0153  size 23
; Far thunk -> midi_track_read_byte_158_inner (cmd 0x10). Reads the track's
; +0x158 status/marker byte; returns it zero-extended in AX (XOR AH / MOV AL,CL).
; ==============================================================
	public _midi_track_read_byte_158_far
_midi_track_read_byte_158_far proc near
	push bp
	mov bp, sp
	push ds
	push di
	push si
	les ax, dword ptr [bp+06h]
	nosmart
	call far ptr _midi_track_read_byte_158_inner	; real far-call FIXUPP; 90 0e e8 after TLINK's backward collapse
	smart
	pop si
	pop di
	pop ds
	pop bp
	xor ah, ah
	mov al, cl
	retf
_midi_track_read_byte_158_far endp

; ==============================================================
; midi_set_note_velocity_thunk  off 0x016a  size 19
; Far thunk -> midi_cmd7_set_global_clamped (cmd 7). Byte arg in CL (0xFF =
; query). Sets the global tempo/speed knob, clamped 0..10.
; ==============================================================
	public _midi_set_note_velocity_thunk
_midi_set_note_velocity_thunk proc near
	push bp
	mov bp, sp
	push ds
	push di
	push si
	mov cl, byte ptr [bp+06h]
	nosmart
	call far ptr _midi_cmd7_set_global_clamped	; real far-call FIXUPP; 90 0e e8 after TLINK's backward collapse
	smart
	pop si
	pop di
	pop ds
	pop bp
	retf
_midi_set_note_velocity_thunk endp

; ==============================================================
; midi_apply_ctrl_change_thunk  off 0x017d  size 28
; Far thunk -> midi_apply_controller_change (cmd 0x15). Marshals controller#
; (CH), value (CL), channel (DL). Command-driven mirror of the per-tick CC path.
; ==============================================================
	public _midi_apply_ctrl_change_thunk
_midi_apply_ctrl_change_thunk proc near
	push bp
	mov bp, sp
	push ds
	push di
	push si
	les ax, dword ptr [bp+06h]
	mov ch, byte ptr [bp+0ah]
	mov cl, byte ptr [bp+0ch]
	mov dl, byte ptr [bp+0eh]
	nosmart
	call far ptr _midi_apply_controller_change	; real far-call FIXUPP; 90 0e e8 after TLINK's backward collapse
	smart
	pop si
	pop di
	pop ds
	pop bp
	retf
_midi_apply_ctrl_change_thunk endp

; ==============================================================
; midi_init_thunk_0678  off 0x0199  size 19
; Far thunk -> midi_cmd2_driver_dispatch_pair (cmd 2). Handle in ES:AX. Paired
; all-channels driver dispatch (BP=0x0c then 0x02) -- reset / all-notes-off.
; ==============================================================
	public _midi_init_thunk_0678
_midi_init_thunk_0678 proc near
	push bp
	mov bp, sp
	push ds
	push di
	push si
	les ax, dword ptr [bp+06h]
	nosmart
	call far ptr _midi_cmd2_driver_dispatch_pair	; real far-call FIXUPP; 90 0e e8 after TLINK's backward collapse
	smart
	pop si
	pop di
	pop ds
	pop bp
	retf
_midi_init_thunk_0678 endp

; ==============================================================
; midi_pitch_bend_step_far_thunk  off 0x01ac  size 22
; Far thunk -> midi_pitch_bend_step (cmd 0x0d). Handle + direction word (CX).
; Nudges every channel's coarse pitch-bend nibble up or down by one step.
; ==============================================================
	public _midi_pitch_bend_step_far_thunk
_midi_pitch_bend_step_far_thunk proc near
	push bp
	mov bp, sp
	push ds
	push di
	push si
	les ax, dword ptr [bp+06h]
	mov cx, word ptr [bp+0ah]
	nosmart
	call far ptr _midi_pitch_bend_step	; real far-call FIXUPP; 90 0e e8 after TLINK's backward collapse
	smart
	pop si
	pop di
	pop ds
	pop bp
	retf
_midi_pitch_bend_step_far_thunk endp

; ==============================================================
; CS-RESIDENT DATA BLOCK  0x01c2 .. 0x03c6 (517 bytes)
;
; The module keeps all of its mutable state right here, inside the code
; segment (so every access goes through a CS: override -- see file header
; quirk #2). It is laid out as several parallel 16-entry arrays. The static
; image below is the power-on state: free voices are 0xFF, counters are 0.
;
; The two big logical groups are:
;   - the TRACK REGISTRY (0x01c2/0x0202/0x0242): far-pointer lists of the
;     currently-playing tracks (the per-track record itself is heap-resident,
;     pointed to from here).
;   - the VOICE POOL (0x02e2 band): the physical output voices the sequencer
;     arbitrates among competing notes.
; Full layout + semantics: reference/midi_32c8_behavior.md sections 2b/2c.
; ==============================================================
; CS:0x01c2 -- active-track registry: 16 slots x far-ptr (off@+0, seg@+2) to a
; playing track record, priority-ordered. The caller's far-ptr handle IS the
; key; claimed by midi_track_init, freed/compacted by midi_track_release.
_cs_track_registry:
	db 000h, 000h, 000h, 000h, 000h, 000h, 000h, 000h, 000h, 000h, 000h, 000h, 000h, 000h, 000h, 000h
	db 000h, 000h, 000h, 000h, 000h, 000h, 000h, 000h, 000h, 000h, 000h, 000h, 000h, 000h, 000h, 000h
	db 000h, 000h, 000h, 000h, 000h, 000h, 000h, 000h, 000h, 000h, 000h, 000h, 000h, 000h, 000h, 000h
	db 000h, 000h, 000h, 000h, 000h, 000h, 000h, 000h, 000h, 000h, 000h, 000h, 000h, 000h, 000h, 000h
; CS:0x0202 -- SFX/streaming-track mirror registry: 16 x far-ptr, same shape as
; the 0x1c2 list but for one-shot streamed sounds. Pumped by
; midi_track_tick_loop_16channel.
_cs_pending_track:
	db 000h, 000h, 000h, 000h, 000h, 000h, 000h, 000h, 000h, 000h, 000h, 000h, 000h, 000h, 000h, 000h
	db 000h, 000h, 000h, 000h, 000h, 000h, 000h, 000h, 000h, 000h, 000h, 000h, 000h, 000h, 000h, 000h
	db 000h, 000h, 000h, 000h, 000h, 000h, 000h, 000h, 000h, 000h, 000h, 000h, 000h, 000h, 000h, 000h
	db 000h, 000h, 000h, 000h, 000h, 000h, 000h, 000h, 000h, 000h, 000h, 000h, 000h, 000h, 000h, 000h
; CS:0x0242 -- per-voice owning-track far-ptr: 16 x dword, mirrors which 0x1c2
; track currently owns each physical voice. Rebuilt at the end of recompute.
_cs_voice_track_table:
	db 000h, 000h, 000h, 000h, 000h, 000h, 000h, 000h, 000h, 000h, 000h, 000h, 000h, 000h, 000h, 000h
	db 000h, 000h, 000h, 000h, 000h, 000h, 000h, 000h, 000h, 000h, 000h, 000h, 000h, 000h, 000h, 000h
	db 000h, 000h, 000h, 000h, 000h, 000h, 000h, 000h, 000h, 000h, 000h, 000h, 000h, 000h, 000h, 000h
	db 000h, 000h, 000h, 000h, 000h, 000h, 000h, 000h, 000h, 000h, 000h, 000h, 000h, 000h, 000h, 000h
	db 000h, 000h, 000h, 000h, 000h, 000h, 000h, 000h, 000h, 000h, 000h, 000h, 000h, 000h, 000h, 000h
	db 000h, 000h, 000h, 000h, 000h, 000h, 000h, 000h, 000h, 000h, 000h, 000h, 000h, 000h, 000h, 000h
	db 000h, 000h, 000h, 000h, 000h, 000h, 000h, 000h, 000h, 000h, 000h, 000h, 000h, 000h, 000h, 000h
	db 000h, 000h, 000h, 000h, 000h, 000h, 000h, 000h, 000h, 000h, 000h, 000h, 000h, 000h, 000h, 000h
; CS:0x02c2 -- scratch buffer (16 words) used only by
; midi_track_parse_program_table while flattening the script's program table.
_cs_prog_scratch:
	db 000h, 000h, 000h, 000h, 000h, 000h, 000h, 000h, 000h, 000h, 000h, 000h, 000h, 000h, 000h, 000h
	db 000h, 000h, 000h, 000h, 000h, 000h, 000h, 000h, 000h, 000h, 000h, 000h, 000h, 000h, 000h, 000h
; CS:0x02e2 -- VOICE POOL, committed assignment: voice -> (track<<2 | channel),
; 0xFF = free. The authoritative "who owns each physical voice" table.
_cs_voice_ch_table:
	db 0ffh, 0ffh, 0ffh, 0ffh, 0ffh, 0ffh, 0ffh, 0ffh, 0ffh, 0ffh, 0ffh, 0ffh, 0ffh, 0ffh, 0ffh, 0ffh
; CS:0x02f2 -- per-voice drum/percussion flag (16 bytes).
_cs_voice_flags:
	db 000h, 000h, 000h, 000h, 000h, 000h, 000h, 000h, 000h, 000h, 000h, 000h, 000h, 000h, 000h, 000h
; CS:0x0302 -- per-voice age/idle counter (16 bytes): the recompute picks the
; voice with the highest value to steal when it runs out of free voices.
_cs_voice_priority:
	db 000h, 000h, 000h, 000h, 000h, 000h, 000h, 000h, 000h, 000h, 000h, 000h, 000h, 000h, 000h, 000h
; CS:0x0312 -- per-voice cost / note-count weight (16 bytes), debited from the
; arbitration budget and refunded when a voice is freed or stolen.
_cs_voice_credit:
	db 000h, 000h, 000h, 000h, 000h, 000h, 000h, 000h, 000h, 000h, 000h, 000h, 000h, 000h, 000h, 000h
; CS:0x0322 -- recompute STAGING copy of the voice-owner table (16 bytes,
; 0xFF=free). The new assignment is built here, then diffed against the live
; 0x2e2 table so only changed voices are re-keyed.
_cs_voice_note:
	db 0ffh, 0ffh, 0ffh, 0ffh, 0ffh, 0ffh, 0ffh, 0ffh, 0ffh, 0ffh, 0ffh, 0ffh, 0ffh, 0ffh, 0ffh, 0ffh
; CS:0x0332 -- save/restore band (64 bytes) holding snapshot copies of the
; flags/priority/credit/owner staging arrays, so a failed voice allocation can
; roll the whole pool back to its pre-attempt state.
_cs_voice_snap:
	db 000h, 000h, 000h, 000h, 000h, 000h, 000h, 000h, 000h, 000h, 000h, 000h, 000h, 000h, 000h, 000h
	db 000h, 000h, 000h, 000h, 000h, 000h, 000h, 000h, 000h, 000h, 000h, 000h, 000h, 000h, 000h, 000h
	db 000h, 000h, 000h, 000h, 000h, 000h, 000h, 000h, 000h, 000h, 000h, 000h, 000h, 000h, 000h, 000h
	db 0ffh, 0ffh, 0ffh, 0ffh, 0ffh, 0ffh, 0ffh, 0ffh, 0ffh, 0ffh, 0ffh, 0ffh, 0ffh, 0ffh, 0ffh, 0ffh
; CS:0x0372 -- per-voice channel nibble (16 bytes); a denormalized copy of the
; low nibble of the owner table, used to skip re-keying unchanged voices.
_cs_voice_ch_cache:
	db 00fh, 00fh, 00fh, 00fh, 00fh, 00fh, 00fh, 00fh, 00fh, 00fh, 00fh, 00fh, 00fh, 00fh, 00fh, 00fh
; CS:0x0382 -- per-voice pending-action queue (16 bytes, 0xFF=none). Deferred
; driver re-key requests that midi_task_scheduler_advance drains a few per tick.
_cs_voice_refresh:
	db 0ffh, 0ffh, 0ffh, 0ffh, 0ffh, 0ffh, 0ffh, 0ffh, 0ffh, 0ffh, 0ffh, 0ffh, 0ffh, 0ffh, 0ffh, 0ffh
	db 000h, 000h, 000h, 000h, 000h, 000h, 000h, 000h, 000h, 000h, 000h, 000h, 000h, 000h, 000h
; CS:0x03a1 -- _cs_drvvec: far ptr (off@+0, seg@+2) to the installed hardware
; driver's entry. Patched by midi_cmd0_program_change; the target of every
; "CALL DWORD PTR [_cs_drvvec]" in this file. See the driver-dispatch ABI primer.
_cs_drvvec:
	db 000h, 000h, 000h, 000h
; CS:0x03a5 -- _cs_cmd_slots: 6-word (12-byte, +2 pad) command-argument staging
; area. midi_queue_command writes the caller's 6 word args here; the dispatcher
; and individual handlers read parameters back out of these slots.
_cs_cmd_slots:
	db 000h, 000h, 000h, 000h, 000h, 000h, 000h, 000h, 000h, 000h, 000h, 000h, 000h, 000h
; CS:0x03b3 -- _cs_pause_refcount: byte +0 is the pause/lock refcount (nonzero
; locks out the tick). Offsets +1..+19 are a packed block of module globals the
; original placed adjacently; each is documented at its use site. Key ones:
;   +1/+2  voice-range low/high bounds (cmd1)    +9   global tempo/speed knob
;   +3/+6/+7 default channel/program/mode-nibble +0x0b voices-dirty flag
;   +0x10  seek-in-progress flag  +0x0d scheduler cursor  +0x13 program-table id
; The 0x0f at +2 and 0xff at +4 are the static defaults (high-bound, an init
; sentinel); the rest power on as 0.
_cs_pause_refcount:
	db 000h, 000h, 00fh, 000h, 0ffh, 000h, 000h, 000h, 000h, 000h, 000h, 000h, 000h, 000h, 000h, 000h
	db 000h, 000h, 000h, 000h

; ==============================================================
; midi_queue_command  off 0x03c7  size 98
;
;   The public __cdecl16far entry the C wrapper layer calls. Stages 6 word
;   arguments from the C stack into the CS-resident _cs_cmd_slots, then invokes
;   the opcode dispatcher. Reached through FBOV overlay thunks.
;
;   Inputs (stack):  [bp+06]=opcode word (CL used), [bp+08]=arg0/handle far-ptr,
;                    [bp+0c..16]=the 6 slot words.
;   Quirk: for opcodes 3/4/6/7 it overwrites slot0 with the arg-handle word --
;   those commands take a scalar in slot0 rather than a track handle.
; ==============================================================
	public _midi_queue_command
_midi_queue_command proc near
	push bp
	mov bp, sp
	push es
	push ds
	push di
	push si
	; Copy the caller's 6 word arguments ([bp+0c]..[bp+16]) into the
	; CS-resident command-slot staging area, where the dispatcher and the
	; per-opcode handlers will read them back out.
	les ax, dword ptr [bp+08h]
	mov cx, word ptr [bp+0ch]
	mov word ptr [_cs_cmd_slots], cx
	mov cx, word ptr [bp+0eh]
	mov word ptr [_cs_cmd_slots + 2], cx
	mov cx, word ptr [bp+10h]
	mov word ptr [_cs_cmd_slots + 4], cx
	mov cx, word ptr [bp+12h]
	mov word ptr [_cs_cmd_slots + 6], cx
	mov cx, word ptr [bp+14h]
	mov word ptr [_cs_cmd_slots + 8], cx
	mov cx, word ptr [bp+16h]
	mov word ptr [_cs_cmd_slots + 10], cx
	; For opcodes 3/4/6/7, slot0 must hold the scalar arg (from [bp+08]),
	; not the track handle. Override it before dispatching.
	mov cx, word ptr [bp+06h]
	cmp cl, 06h
	jz loc_0418
	cmp cl, 03h
	jz loc_0418
	cmp cl, 04h
	jz loc_0418
	cmp cl, 07h
	jnz loc_0420
loc_0418:
	mov dx, word ptr [bp+08h]
	mov word ptr [_cs_cmd_slots], dx
loc_0420:
	call _midi_dispatch_command
	pop si
	pop di
	pop ds
	pop es
	pop bp
	retf
_midi_queue_command endp

; ==============================================================
; midi_dispatch_command  off 0x0429  size 499
;
;   The command interface: a dense switch on the opcode in CL (0x00..0x19),
;   a chain of CMP/JNZ equality tests (not a jump table). Each arm
;   reloads the handler's register arguments from the _cs_cmd_slots staging area
;   and PUSH CS / CALLs the matching internal handler. Most arms RETN straight
;   after (this is a near function called from midi_queue_command and the seek
;   handler); a few fall through, which the per-arm comments call out.
;
;   The full opcode->handler table is in reference/midi_32c8_behavior.md s5 and
;   the per-thunk plates above. Inline comments below just name each arm.
; ==============================================================
	public _midi_dispatch_command
_midi_dispatch_command proc near
	; opcode 0: install driver / program change
	cmp cl, 00h
	jnz loc_0465
	nosmart
	call far ptr _midi_cmd0_program_change	; real far-call FIXUPP; 90 0e e8 after TLINK's backward collapse
	smart
	; cmd0 returns the driver's default program in AL (0xFF = none). Build a
	; word in (AH:AL) where AH mirrors AL only when it's the 0xFF sentinel,
	; then write the captured default program/channel/mode bytes back out
	; through the caller-supplied far pointers in slots 0/4/8.
	xor ah, ah
	cmp al, 0ffh
	jnz loc_043b
	mov ah, al
loc_043b:
	xor cx, cx
	mov cl, byte ptr [_cs_pause_refcount + 6]
	les bx, dword ptr [_cs_cmd_slots]
	mov word ptr es:[bx], cx
	mov cl, byte ptr [_cs_pause_refcount + 7]
	les bx, dword ptr [_cs_cmd_slots + 4]
	mov word ptr es:[bx], cx
	mov cl, byte ptr [_cs_pause_refcount + 3]
	les bx, dword ptr [_cs_cmd_slots + 8]
	mov word ptr es:[bx], cx
	retn
loc_0465:
	cmp cl, 01h
	jnz loc_0475
	mov bx, word ptr [_cs_cmd_slots]
	nosmart
	call far ptr _midi_cmd1_save_cx_303b4	; real far-call FIXUPP; 90 0e e8 after TLINK's backward collapse
	smart
	retn
loc_0475:
	cmp cl, 02h
	jnz loc_0480
	nosmart
	call far ptr _midi_cmd2_driver_dispatch_pair	; real far-call FIXUPP; 90 0e e8 after TLINK's backward collapse
	smart
	retn
loc_0480:
	cmp cl, 03h
	jnz loc_0490
	mov cx, word ptr [_cs_cmd_slots]
	nosmart
	call far ptr _midi_scheduler_pause_refcount	; real far-call FIXUPP; 90 0e e8 after TLINK's backward collapse
	smart
	retn
loc_0490:
	cmp cl, 04h
	jnz loc_04a0
	mov cx, word ptr [_cs_cmd_slots]
	nosmart
	call far ptr _midi_cmd4_call_driver_13000	; real far-call FIXUPP; 90 0e e8 after TLINK's backward collapse
	smart
	retn
loc_04a0:
	cmp cl, 05h
	jnz loc_04ab
	nosmart
	call far ptr _midi_seek_with_volume_preserve	; real far-call FIXUPP; 90 0e e8 after TLINK's backward collapse
	smart
	retn
loc_04ab:
	cmp cl, 06h
	jnz loc_04bb
	mov cx, word ptr [_cs_cmd_slots]
	nosmart
	call far ptr _midi_call_dispatch_cmd_13000	; real far-call FIXUPP; 90 0e e8 after TLINK's backward collapse
	smart
	retn
loc_04bb:
	cmp cl, 07h
	jnz loc_04cb
	mov cx, word ptr [_cs_cmd_slots]
	nosmart
	call far ptr _midi_cmd7_set_global_clamped	; real far-call FIXUPP; 90 0e e8 after TLINK's backward collapse
	smart
	retn
loc_04cb:
	cmp cl, 08h
	jnz loc_04db
	mov cx, word ptr [_cs_cmd_slots]
	nosmart
	call far ptr _midi_track_init	; real far-call FIXUPP; 90 0e e8 after TLINK's backward collapse
	smart
	retn
loc_04db:
	cmp cl, 09h
	jnz loc_04e6
	nosmart
	call far ptr _midi_cmd9_release_and_recompute	; real far-call FIXUPP; 90 0e e8 after TLINK's backward collapse
	smart
	retn
loc_04e6:
	cmp cl, 0ah
	jnz loc_04f6
	mov cl, byte ptr [_cs_cmd_slots]
	nosmart
	call far ptr _midi_cmd0a_adjust_hold_count	; real far-call FIXUPP; 90 0e e8 after TLINK's backward collapse
	smart
	retn
loc_04f6:
	cmp cl, 0bh
	jnz loc_0510
	mov dl, byte ptr [_cs_cmd_slots]
	mov cl, byte ptr [_cs_cmd_slots + 2]
	mov ch, byte ptr [_cs_cmd_slots + 4]
	nosmart
	call far ptr _midi_fade_program	; real far-call FIXUPP; 90 0e e8 after TLINK's backward collapse
	smart
	retn
loc_0510:
	cmp cl, 0ch
	jnz loc_0520
	mov cl, byte ptr [_cs_cmd_slots]
	nosmart
	call far ptr _midi_track_write_byte_15a_inner	; real far-call FIXUPP; 90 0e e8 after TLINK's backward collapse
	smart
	retn
loc_0520:
	cmp cl, 0dh
	jnz loc_0530
	mov cx, word ptr [_cs_cmd_slots]
	nosmart
	call far ptr _midi_pitch_bend_step	; real far-call FIXUPP; 90 0e e8 after TLINK's backward collapse
	smart
	retn
loc_0530:
	cmp cl, 0eh
	jnz loc_0540
	mov cx, word ptr [_cs_cmd_slots]
	nosmart
	call far ptr _midi_cmd0e_apply_vel_track	; real far-call FIXUPP; 90 0e e8 after TLINK's backward collapse
	smart
	retn
loc_0540:
	cmp cl, 0fh
	jnz loc_054f
	mov cx, word ptr [_cs_cmd_slots]
	nosmart
	call far ptr _midi_chord_propagate_setting	; real far-call FIXUPP; 90 0e e8 after TLINK's backward collapse
	smart
	; NB: opcode 0x0f does NOT RETN here -- it falls through into the 0x11
	; test. Since CL still holds 0x0f, that compare fails and the next ones
	; run too.
loc_054f:
	cmp cl, 11h
	jnz loc_055b
	nosmart
	call far ptr _midi_stub_nop	; real far-call FIXUPP; 90 0e e8 after TLINK's backward collapse
	smart
	mov ax, cx
	; opcode 0x11 also falls through (no RETN) into the 0x10 test below.
loc_055b:
	cmp cl, 10h
	jnz loc_056a
	nosmart
	call far ptr _midi_track_read_byte_158_inner	; real far-call FIXUPP; 90 0e e8 after TLINK's backward collapse
	smart
	mov al, cl
	xor ah, ah
	retn
loc_056a:
	cmp cl, 19h
	jnz loc_0579
	nosmart
	call far ptr _midi_sound_slot_unlock	; real far-call FIXUPP; 90 0e e8 after TLINK's backward collapse
	smart
	mov al, cl
	xor ah, ah
	retn
loc_0579:
	cmp cl, 12h
	jnz loc_05a3
	nosmart
	call far ptr _midi_stub_return_ax	; real far-call FIXUPP; 90 0e e8 after TLINK's backward collapse
	smart
	xor ah, ah
	les bx, dword ptr [_cs_cmd_slots]
	mov al, dl
	mov word ptr es:[bx], ax
	les bx, dword ptr [_cs_cmd_slots + 4]
	mov al, ch
	mov word ptr es:[bx], ax
	les bx, dword ptr [_cs_cmd_slots + 8]
	mov al, cl
	mov word ptr es:[bx], ax
	; opcode 0x12 falls through into the 0x13 test (no RETN).
loc_05a3:
	cmp cl, 13h
	jnz loc_05bd
	mov dl, byte ptr [_cs_cmd_slots]
	mov ch, byte ptr [_cs_cmd_slots + 2]
	mov cl, byte ptr [_cs_cmd_slots + 4]
	nosmart
	call far ptr _midi_cmd13_voice_release	; real far-call FIXUPP; 90 0e e8 after TLINK's backward collapse
	smart
	retn
loc_05bd:
	cmp cl, 14h
	jnz loc_05d7
	mov dl, byte ptr [_cs_cmd_slots]
	mov ch, byte ptr [_cs_cmd_slots + 2]
	mov cl, byte ptr [_cs_cmd_slots + 4]
	nosmart
	call far ptr _midi_cmd14_voice_set_value	; real far-call FIXUPP; 90 0e e8 after TLINK's backward collapse
	smart
	retn
loc_05d7:
	cmp cl, 15h
	jnz loc_05f1
	mov dl, byte ptr [_cs_cmd_slots]
	mov ch, byte ptr [_cs_cmd_slots + 2]
	mov cl, byte ptr [_cs_cmd_slots + 4]
	nosmart
	call far ptr _midi_apply_controller_change	; real far-call FIXUPP; 90 0e e8 after TLINK's backward collapse
	smart
	retn
loc_05f1:
	cmp cl, 16h
	jnz loc_0606
	mov dl, byte ptr [_cs_cmd_slots]
	mov cl, byte ptr [_cs_cmd_slots + 2]
	nosmart
	call far ptr _midi_cmd16_voice_set_state	; real far-call FIXUPP; 90 0e e8 after TLINK's backward collapse
	smart
	retn
loc_0606:
	cmp cl, 17h
	jnz loc_061b
	mov dl, byte ptr [_cs_cmd_slots]
	mov cx, word ptr [_cs_cmd_slots + 2]
	nosmart
	call far ptr _midi_track_set_word_bc	; real far-call FIXUPP; 90 0e e8 after TLINK's backward collapse
	smart
	retn
loc_061b:
	retn
_midi_dispatch_command endp

; ==============================================================
; midi_cmd0_program_change  off 0x061c  size 55
;
;   Driver INSTALL + capability-probe. Writes the driver chunk's far-ptr (ES:AX)
;   into the dispatch vector _cs_drvvec, then calls it with BP=0 to initialise/
;   probe. Captures the returned defaults: program (CL) -> +6, channel (CH) ->
;   +3, and the high nibble of AH (the card's voice/mode nibble) -> +7, ORing in
;   bit0 when a music driver is installed. The +3/+6/+7 globals seed later
;   playback. Entered both directly (dispatcher opcode 0) and via the install
;   thunk midi_driver_install_dispatch.
; ==============================================================
	public _midi_cmd0_program_change
_midi_cmd0_program_change proc near
	; Bind the installed driver entry into the per-event dispatch vector...
	mov word ptr [_cs_drvvec], ax
	mov word ptr [_cs_drvvec + 2], es
	; ...then probe it (BP=0 = init/info selector of the DUDE slot ABI).
	push bp
	mov bp, 00h
	call dword ptr [_cs_drvvec]
	pop bp
	mov byte ptr [_cs_pause_refcount + 6], cl   ; default program
	mov byte ptr [_cs_pause_refcount + 3], ch   ; default channel
	; mode nibble = AH >> 4; set bit0 if a music driver is present.
	mov dl, ah
	shr dl, 01h
	shr dl, 01h
	shr dl, 01h
	shr dl, 01h
	cmp word ptr [_g_bMusicDriverInstalled], 00h
	jz loc_064d
	or dl, 01h
loc_064d:
	mov byte ptr [_cs_pause_refcount + 7], dl
	retf
_midi_cmd0_program_change endp

; ==============================================================
; midi_cmd1_save_cx_303b4  off 0x0653  size 37
;
;   Calls the driver (BP=1) and saves the returned CX as the low/high voice-
;   index bounds (+1/+2) that bound voice arbitration. Then issues a second
;   driver call (BP=0x0b, CL=0) to push the new range down to the hardware.
; ==============================================================
	public _midi_cmd1_save_cx_303b4
_midi_cmd1_save_cx_303b4 proc near
	push cx
	push bp
	mov bp, 01h
	call dword ptr [_cs_drvvec]
	pop bp
	mov byte ptr [_cs_pause_refcount + 1], cl
	mov byte ptr [_cs_pause_refcount + 2], ch
	push ax
	xor cl, cl
	push bp
	mov bp, 0bh
	call dword ptr [_cs_drvvec]
	pop bp
	pop ax
	pop cx
	retf
_midi_cmd1_save_cx_303b4 endp

; ==============================================================
; midi_cmd2_driver_dispatch_pair  off 0x0678  size 31
;
;   All-channels reset: issues two driver calls in sequence -- BP=0x0c with
;   CL=0x0f (all 16 channels) then BP=0x02 -- an all-notes-off / reset pair.
; ==============================================================
	public _midi_cmd2_driver_dispatch_pair
_midi_cmd2_driver_dispatch_pair proc near
	push bx
	push cx
	push es
	push si
	mov cl, 0fh
	push bp
	mov bp, 0ch
	call dword ptr [_cs_drvvec]
	pop bp
	push bp
	mov bp, 02h
	call dword ptr [_cs_drvvec]
	pop bp
	pop si
	pop es
	pop cx
	pop bx
	retf
_midi_cmd2_driver_dispatch_pair endp

; ==============================================================
; midi_scheduler_pause_refcount  off 0x0697  size 25
;
;   Pause/resume the whole sequencer by adjusting the master lock refcount
;   (_cs_pause_refcount +0). CX==0 -> increment (pause); CX!=0 -> decrement if
;   nonzero (resume). While the refcount is nonzero, the tick is gated off.
; ==============================================================
	public _midi_scheduler_pause_refcount
_midi_scheduler_pause_refcount proc near
	cmp cx, 00h
	jnz loc_06a2
	inc byte ptr [_cs_pause_refcount]
	retf
loc_06a2:
	cmp byte ptr [_cs_pause_refcount], 00h
	jz loc_06af
	dec byte ptr [_cs_pause_refcount]
loc_06af:
	retf
_midi_scheduler_pause_refcount endp

; ==============================================================
; midi_cmd4_call_driver_13000  off 0x06b0  size 11
;
;   One-shot driver call with BP=0x0d. (The "13000" name comes from the timer
;   slot id this selector relates to; see integration.md.)
; ==============================================================
	public _midi_cmd4_call_driver_13000
_midi_cmd4_call_driver_13000 proc near
	push bp
	mov bp, 0dh
	call dword ptr [_cs_drvvec]
	pop bp
	retf
_midi_cmd4_call_driver_13000 endp

; ==============================================================
; midi_seek_with_volume_preserve  off 0x06bb  size 144 (cmd 5)
;
;   Fast-forwards a track to its current tick clock WITHOUT producing sound, so
;   pitch/volume/controller state is rebuilt as if the track had played from the
;   start. Saves the per-channel CC-0x4E nibbles, re-inits the track, sets the
;   seek-in-progress flag (+0x10, which makes the event handlers skip every
;   driver call), then runs midi_tick in a loop until the clock catches back up
;   to where it was, restores the saved state, and re-arbitrates voices.
;
;   Wrapped in PUSHF/CLI..POPF so the IRQ-0 tick can't run mid-seek.
; ==============================================================
	public _midi_seek_with_volume_preserve
_midi_seek_with_volume_preserve proc near
	pushf
	cli
	push si
	push ax
	push bx
	push cx
	push dx
	mov bx, ax
	; Save the high nibble of each of the 16 channels' CC-0x4E byte (+0x143)
	; into the _cs_voice_refresh scratch band, so re-init doesn't lose it.
	xor ch, ch
	mov cl, byte ptr es:[bx+0159h]
	dec cl
	mov si, 0eh
loc_06d0:
	mov dl, byte ptr es:[bx+si+0143h]
	and dl, 0f0h
	mov byte ptr cs:[si + _cs_voice_refresh + 16], dl
	dec si
	jns loc_06d0
	; Enter "seek in progress": event handlers will update state but emit no
	; sound while this flag is set.
	mov byte ptr [_cs_pause_refcount + 16], 01h
	nosmart
	call far ptr _midi_track_init	; real far-call FIXUPP; 90 0e e8 after TLINK's backward collapse
	smart
	; Reset the clock to 0, remember the target (old clock) in CX, force the
	; loop-id byte to 1, then tick forward until the clock reaches the target.
	mov cx, word ptr es:[bx+0154h]
	mov word ptr es:[bx+0154h], 00h
	mov al, byte ptr es:[bx+015dh]
	mov byte ptr es:[bx+015dh], 01h
	cmp cx, 00h
	jz loc_0726
loc_0707:
	mov dx, word ptr es:[bx+0154h]
	call _midi_tick
	cmp dx, word ptr es:[bx+0154h]
	jc loc_071f
	jz loc_0726
	sub dx, word ptr es:[bx+0154h]
	sub cx, dx
loc_071f:
	cmp cx, word ptr es:[bx+0154h]
	jnz loc_0707
loc_0726:
	; Done seeking: restore the saved loop-id, clear the seek flag, and OR the
	; saved CC-0x4E nibbles back into +0x143 for all 16 channels.
	mov byte ptr es:[bx+015dh], al
	mov byte ptr [_cs_pause_refcount + 16], 00h
	mov si, 0eh
loc_0734:
	mov dl, byte ptr cs:[si + _cs_voice_refresh + 16]
	or byte ptr es:[bx+si+0143h], dl
	dec si
	jns loc_0734
	call _midi_recompute_active_voices
	pop dx
	pop cx
	pop bx
	pop ax
	pop si
	popf
	retf
_midi_seek_with_volume_preserve endp

; ==============================================================
; midi_call_dispatch_cmd_13000  off 0x074b  size 23 (cmd 6)
;
;   Clamps the voice-count arg in CL to [0..0x0f] (0xFF passes through as a
;   sentinel) and issues a driver call with BP=0x0c.
; ==============================================================
	public _midi_call_dispatch_cmd_13000
_midi_call_dispatch_cmd_13000 proc near
	cmp cl, 0ffh
	jz loc_0757
	cmp cl, 0fh
	jbe loc_0757
	mov cl, 0fh
loc_0757:
	push bp
	mov bp, 0ch
	call dword ptr [_cs_drvvec]
	pop bp
	retf
_midi_call_dispatch_cmd_13000 endp

; ==============================================================
; midi_cmd7_set_global_clamped  off 0x0762  size 75 (cmd 7)
;
;   Sets the global tempo/speed knob (+9). CL==0xFF queries the driver (BP=0x0b)
;   and returns; CL>0x0a is out of range and just returns the current value.
;   Otherwise stores CL as the new knob, and if the head track's +0x15f is the
;   default 0x7F, re-pushes it to the driver so the change takes effect live.
; ==============================================================
	public _midi_cmd7_set_global_clamped
_midi_cmd7_set_global_clamped proc near
	cmp cl, 0ffh
	jnz loc_0772
	push bp
	mov bp, 0bh
	call dword ptr [_cs_drvvec]
	pop bp
	retf
loc_0772:
	cmp cl, 0ah
	jbe loc_077e
	mov al, byte ptr [_cs_pause_refcount + 9]
	xor ah, ah
	retf
loc_077e:
	mov al, byte ptr [_cs_pause_refcount + 9]
	push es
	push ax
	push bx
	push dx
	mov byte ptr [_cs_pause_refcount + 9], cl
	les bx, dword ptr [_cs_track_registry]
	mov dx, es
	or dx, bx
	jz loc_07a8
	cmp byte ptr es:[bx+015fh], 7fh
	jnz loc_07a8
	push bp
	mov bp, 0bh
	call dword ptr [_cs_drvvec]
	pop bp
loc_07a8:
	pop dx
	pop bx
	pop ax
	pop es
	retf
_midi_cmd7_set_global_clamped endp

; ==============================================================
; midi_track_init  off 0x07ad  size 724 (cmd 8, "start / play a track")
;
;   The track loader. Given a track record far-ptr (ES:AX) and a mode word (CX),
;   it (1) releases any existing registry entry for the same handle so a replay
;   re-triggers cleanly, (2) zero-initialises all 16 per-channel state arrays in
;   the record, (3) parses the script's program table (midi_track_parse_program_
;   table) and walks the channel-setup stream to seed channel/program/flag bytes,
;   then (4) inserts the record into the 0x1c2 registry priority-sorted by the
;   record's +0x15c priority byte (lower-priority entries shift up to make room),
;   and (5) re-arbitrates voices.
;
;   Wrapped in PUSHF/CLI..POPF (interrupt-safe registry edit). The big es:[bx+N]
;   stores in the middle are the per-channel array initialisers (offsets per the
;   track-record map in behavior.md s2b).
; ==============================================================
	public _midi_track_init
_midi_track_init proc near
	pushf
	cli
	push cx
	push cx
	; Phase 1: if this handle (AX:ES) is already in the registry, release it
	; first (re-trigger semantics) and recompute.
	mov cx, es
	xor di, di
loc_07b5:
	cmp word ptr cs:[di + _cs_track_registry], ax
	jnz loc_07cb
	cmp word ptr cs:[di + _cs_track_registry + 2], cx
	jnz loc_07cb
	call _midi_track_release
	call _midi_recompute_active_voices
	jmp loc_07d3
loc_07cb:
	add di, 04h
	cmp di, 40h
	jnz loc_07b5
loc_07d3:
	pop cx
	mov bx, ax
	mov byte ptr es:[bx+0159h], 01h
	cmp cx, 00h
	jz loc_07e6
	inc byte ptr es:[bx+0159h]
loc_07e6:
	; Phase 2/3: parse the script's program table, then zero/seed the 16
	; per-channel arrays. CX is set up as ch=0xFF (loop sentinel) / cl=0.
	call _midi_track_parse_program_table
	mov bx, ax
	xor si, si
	xor cx, cx
	dec ch
loc_07f1:
	shl si, 01h
	mov word ptr es:[bx+si+0ch], 0dh
	mov word ptr es:[bx+si+2ch], 03h
	mov word ptr es:[bx+si+4ch], 00h
	mov word ptr es:[bx+si+6ch], 00h
	mov word ptr es:[bx+si+0bch], 2000h	; 2000h pitch-bend center seed into track[+0bc]
	shr si, 01h
	mov byte ptr es:[bx+si+8ch], ch
	mov byte ptr es:[bx+si+9ch], cl
	mov byte ptr es:[bx+si+0ach], cl
	mov byte ptr es:[bx+si+0dah], ch
	mov byte ptr es:[bx+si+0e9h], cl
	mov byte ptr es:[bx+si+0116h], ch
	mov byte ptr es:[bx+si+0107h], ch
	mov byte ptr es:[bx+si+0f8h], ch
	mov byte ptr es:[bx+si+0125h], ch
	mov byte ptr es:[bx+si+0134h], cl
	mov byte ptr es:[bx+si+0143h], cl
	inc si
	cmp si, 0fh
	jnz loc_07f1
	mov byte ptr es:[bx+si+8ch], ch
	mov byte ptr es:[bx+si+9ch], cl
	mov byte ptr es:[bx+si+0ach], cl
	mov byte ptr es:[bx+0165h], cl
	mov byte ptr es:[bx+015ah], cl
	mov byte ptr es:[bx+015fh], 7fh
	shl si, 01h
	mov word ptr es:[bx+si+0ch], 0dh
	mov word ptr es:[bx+si+2ch], 03h
	mov word ptr es:[bx+si+4ch], 00h
	mov word ptr es:[bx+0156h], 00h
	push ax
	push bp
	push ds
	xor si, si
	; Load the MIDI script header. +0x08 is a far pointer-to-pointer: the
	; first LDS loads a far ptr to the header-ptr; the second dereferences it
	; to DS:BP = base of the script's event tables. (This double indirection
	; recurs throughout the module wherever the script is read.)
	lds bp, es:[bx+08h]
	lds bp, ds:[bp+00h]
	cmp byte ptr ds:[bp+20h], 0ffh
	jz loc_08b0
	cmp byte ptr es:[bx+015bh], 00h
	jnz loc_08b0
	mov cl, byte ptr ds:[bp+20h]
	mov byte ptr es:[bx+015ch], cl
loc_08b0:
	mov cx, bp
loc_08b2:
	mov dx, word ptr ds:[bp+00h]
	cmp dx, 00h
	jz loc_08f1
	mov bp, cx
	add bp, dx
	mov dl, byte ptr ds:[bp+00h]
	cmp dl, 0feh
	jnz loc_08f4
	cmp byte ptr [_cs_pause_refcount + 7], 00h
	jnz loc_08e9
	shl si, 01h
	mov word ptr es:[bx+si+0ch], 00h
	mov word ptr es:[bx+si+2ch], 00h
	shr si, 01h
	mov byte ptr es:[bx+si+8ch], 0feh
	jmp loc_09c4
loc_08e9:
	mov dx, si
	inc dx
	mov byte ptr es:[bx+0165h], dl
loc_08f1:
	jmp loc_09d5
loc_08f4:
	mov byte ptr es:[bx+si+8ch], dl
	mov dh, dl
	or dh, 0b0h
	mov byte ptr es:[bx+si+9ch], dh
	mov dl, byte ptr ds:[bp+0ch]
	xor dh, dh
	cmp dl, 0f8h
	jnz loc_0912
	mov dl, 0f0h
	mov dh, 80h
loc_0912:
	shl si, 01h
	mov word ptr es:[bx+si+4ch], dx
	shr si, 01h
	push si
	mov dl, byte ptr es:[bx+si+8ch]
	and byte ptr es:[bx+si+8ch], 0fh
	test dl, 10h
	jz loc_0949
	shl si, 01h
	mov word ptr es:[bx+si+0ch], 03h
	mov word ptr es:[bx+si+4ch], 00h
	xor dh, dh
	mov si, dx
	db 081h, 0e6h
	dw 0000fh   ; and SI,0xf (imm16 forced)
	or byte ptr es:[bx+si+0134h], 02h
	jmp loc_09c3
loc_0949:
	xor dh, dh
	mov si, dx
	db 081h, 0e6h
	dw 0000fh   ; and SI,0xf (imm16 forced)
	test dl, 20h
	jz loc_095c
	or byte ptr es:[bx+si+0134h], 01h
loc_095c:
	test dl, 40h
	jz loc_0967
	mov byte ptr es:[bx+si+0143h], 01h
loc_0967:
	cmp si, 0fh
	jnz loc_097f
	cmp byte ptr es:[bx+015fh], 7fh
	jnz loc_09b2
	mov al, byte ptr ds:[bp+08h]
	mov byte ptr es:[bx+015fh], al
	jmp loc_09c3
loc_097f:
	cmp byte ptr es:[bx+si+0dah], 0ffh
	jnz loc_0990
	mov al, byte ptr ds:[bp+01h]
	mov byte ptr es:[bx+si+0dah], al
loc_0990:
	cmp byte ptr es:[bx+si+0116h], 0ffh
	jnz loc_09a1
	mov al, byte ptr ds:[bp+04h]
	mov byte ptr es:[bx+si+0116h], al
loc_09a1:
	cmp byte ptr es:[bx+si+0107h], 0ffh
	jnz loc_09b2
	mov al, byte ptr ds:[bp+08h]
	mov byte ptr es:[bx+si+0107h], al
loc_09b2:
	cmp byte ptr es:[bx+si+0f8h], 0ffh
	jnz loc_09c3
	mov al, byte ptr ds:[bp+0bh]
	mov byte ptr es:[bx+si+0f8h], al
loc_09c3:
	pop si
loc_09c4:
	inc si
	shl si, 01h
	mov bp, cx
	add bp, si
	shr si, 01h
	cmp si, 10h
	jz loc_09d5
	jmp loc_08b2
loc_09d5:
	pop ds
	pop bp
	pop ax
	cmp byte ptr es:[bx+0159h], 02h
	jnz loc_09ec
	mov di, 0eh
loc_09e3:
	or byte ptr es:[bx+di+0134h], 01h
	dec di
	jns loc_09e3
loc_09ec:
	; Phase 4: insert this record (AX:saved-ES) into the 0x1c2 registry,
	; priority-sorted by the +0x15c byte (DL = our priority). Scan for the
	; first slot whose occupant has priority <= ours; that's our insert point.
	mov ax, bx
	mov dl, byte ptr es:[bx+015ch]
	push es
	xor di, di
loc_09f6:
	cmp word ptr cs:[di + _cs_track_registry + 2], 00h
	jz loc_0a3a
	les bx, dword ptr cs:[di + _cs_track_registry]
	cmp byte ptr es:[bx+015ch], dl
	jbe loc_0a15
	add di, 04h
	cmp di, 40h
	jnz loc_09f6
	pop es
	jmp loc_0a7e
loc_0a15:
	; Shift every entry from DI down to the tail up by one slot (4 bytes) to
	; open a hole at DI for the new record. Copies from the end backward.
	mov si, 38h
loc_0a18:
	mov bx, si
	add bx, 04h
	cmp bx, di
	jz loc_0a3a
	mov bx, word ptr cs:[si + _cs_track_registry]
	mov word ptr cs:[si + _cs_track_registry + 4], bx
	mov bx, word ptr cs:[si + _cs_track_registry + 2]
	mov word ptr cs:[si + _cs_track_registry + 6], bx
	sub si, 04h
	jmp loc_0a18
loc_0a3a:
	pop es
	mov bx, ax
	mov ax, es
	mov word ptr cs:[di + _cs_track_registry], bx
	mov word ptr cs:[di + _cs_track_registry + 2], ax
	cmp byte ptr [_cs_pause_refcount + 16], 00h
	jnz loc_0a7e
	xor cx, cx
	mov word ptr es:[bx+0152h], cx
	mov word ptr es:[bx+0154h], cx
	mov byte ptr es:[bx+0158h], cl
	mov byte ptr es:[bx+0160h], cl
	mov byte ptr es:[bx+0161h], cl
	mov byte ptr es:[bx+0162h], cl
	mov byte ptr es:[bx+0163h], cl
	mov byte ptr es:[bx+0164h], cl
	call _midi_recompute_active_voices
loc_0a7e:
	pop cx
	popf
	retf
_midi_track_init endp

; ==============================================================
; midi_cmd9_release_and_recompute  off 0x0a81  size 10 (cmd 9, "stop")
;
;   Stop a track: release it from the registry then re-arbitrate voices.
;   Interrupt-safe (PUSHF/CLI).
; ==============================================================
	public _midi_cmd9_release_and_recompute
_midi_cmd9_release_and_recompute proc near
	pushf
	cli
	call _midi_track_release
	call _midi_recompute_active_voices
	popf
	retf
_midi_cmd9_release_and_recompute endp

; ==============================================================
; midi_cmd0a_adjust_hold_count  off 0x0a8b  size 104 (cmd 0x0a)
;
;   Pause/resume tracks via each record's +0x164 hold-count. CL!=0 increments
;   (pause), CL==0 decrements toward 0 (resume). If the handle (ES:AX) is null,
;   it applies to EVERY registered track (the loop over the 0x1c2 registry,
;   including the special index-0/index-4 pair); otherwise just the one. Then
;   re-arbitrates voices. Interrupt-safe.
; ==============================================================
	public _midi_cmd0a_adjust_hold_count
_midi_cmd0a_adjust_hold_count proc near
	pushf
	cli
	push ax
	push bx
	push si
	mov bx, es
	or bx, ax
	jnz loc_0ad0
	xor si, si
loc_0a98:
	les bx, dword ptr cs:[si + _cs_track_registry]
	mov ax, es
	or ax, bx
	jnz loc_0aad
	cmp si, 00h
	jnz loc_0aeb
	mov si, 04h
	jmp loc_0a98
loc_0aad:
	mov al, byte ptr es:[bx+0164h]
	cmp cl, 00h
	jz loc_0abb
	inc al
	jmp loc_0ac1
loc_0abb:
	cmp al, 00h
	jz loc_0ac1
	dec al
loc_0ac1:
	mov byte ptr es:[bx+0164h], al
	add si, 04h
	cmp si, 40h
	jnz loc_0a98
	jmp loc_0aeb
loc_0ad0:
	mov bx, ax
	mov al, byte ptr es:[bx+0164h]
	cmp cl, 00h
	jz loc_0ae0
	inc al
	jmp loc_0ae6
loc_0ae0:
	cmp al, 00h
	jz loc_0ae6
	dec al
loc_0ae6:
	mov byte ptr es:[bx+0164h], al
loc_0aeb:
	call _midi_recompute_active_voices
	pop si
	pop bx
	pop ax
	popf
	retf
_midi_cmd0a_adjust_hold_count endp

; ==============================================================
; midi_fade_program  off 0x0af3  size 36 (cmd 0x0b)
;
;   Programs a volume fade on a track by writing the fade quad into the record:
;   target (DL) -> +0x160 (bit7 = "release track when the fade completes"),
;   step/period (CL) -> +0x161, direction (CH) -> +0x163, and clears the per-
;   tick countdown +0x162. The fade engine (task_tick_one_slot) consumes these.
;   No-op if the target already equals the current setting (+0x15e). Int-safe.
; ==============================================================
	public _midi_fade_program
_midi_fade_program proc near
	pushf
	cli
	push bx
	mov bx, ax
	cmp byte ptr es:[bx+015eh], dl
	jz loc_0b14
	mov byte ptr es:[bx+0160h], dl
	mov byte ptr es:[bx+0161h], cl
	mov byte ptr es:[bx+0163h], ch
	mov byte ptr es:[bx+0162h], 00h
loc_0b14:
	pop bx
	popf
	retf
_midi_fade_program endp

; ==============================================================
; midi_track_write_byte_15a_inner  off 0x0b17  size 10 (cmd 0x0c)
;
;   Stores CL into the track's loop/cue id byte (+0x15a), which controller 0x52
;   ('R') later compares against to decide whether to rewind.
; ==============================================================
	public _midi_track_write_byte_15a_inner
_midi_track_write_byte_15a_inner proc near
	push bx
	mov bx, ax
	mov byte ptr es:[bx+015ah], cl
	pop bx
	retf
_midi_track_write_byte_15a_inner endp

; ==============================================================
; midi_pitch_bend_step  off 0x0b21  size 61 (cmd 0x0d)
;
;   Nudges the coarse pitch-bend nibble (high nibble of +0x143) of all 16
;   channels by one step. CX!=0 raises (add 0x10, clamp at 0xF0), CX==0 lowers
;   (sub 0x10, clamp at 0x0f). Brackets the work with pause-refcount inc/dec and
;   re-arbitrates voices so the change is heard at once.
; ==============================================================
	public _midi_pitch_bend_step
_midi_pitch_bend_step proc near
	push bx
	push dx
	push si
	inc byte ptr [_cs_pause_refcount]
	mov bx, ax
	mov si, 0eh
loc_0b2e:
	mov dl, byte ptr es:[bx+si+0143h]
	cmp cx, 00h
	jnz loc_0b42
	cmp dl, 0fh
	jbe loc_0b4a
	sub dl, 10h
	jmp loc_0b4a
loc_0b42:
	cmp dl, 0f0h
	jnc loc_0b4a
	add dl, 10h
loc_0b4a:
	mov byte ptr es:[bx+si+0143h], dl
	dec si
	jns loc_0b2e
	call _midi_recompute_active_voices
	dec byte ptr [_cs_pause_refcount]
	pop si
	pop dx
	pop bx
	retf
_midi_pitch_bend_step endp

; ==============================================================
; midi_cmd0e_apply_vel_track  off 0x0b5e  size 16 (cmd 0x0e)
;
;   Resolves the handle to its registry slot (SI), then pushes a new master
;   velocity/volume (CL) to every active voice of that track via
;   midi_apply_vel_change_active (with the "immediate" flag CH=0).
; ==============================================================
	public _midi_cmd0e_apply_vel_track
_midi_cmd0e_apply_vel_track proc near
	pushf
	cli
	push bx
	mov bx, ax
	call _midi_lookup_track_state
	xor ch, ch
	call _midi_apply_vel_change_active
	pop bx
	popf
	retf
_midi_cmd0e_apply_vel_track endp

; ==============================================================
; midi_chord_propagate_setting  off 0x0b6e  size 190 (cmd 0x0f)
;
;   Sets a track's priority byte (+0x15c) and re-sorts the registry so the
;   chord-linked tracks keep their relative ordering. Removes the track from its
;   current registry slot (shifting the rest down), then re-inserts it priority-
;   sorted (the 0x38.. down-copy loop, mirror of the insert in midi_track_init),
;   and re-arbitrates voices. No-op if the priority is unchanged. Int-safe.
; ==============================================================
	public _midi_chord_propagate_setting
_midi_chord_propagate_setting proc near
	pushf
	cli
	push bx
	push cx
	push dx
	push si
	push di
	mov bx, ax
	cmp byte ptr es:[bx+015ch], cl
	jnz loc_0b81
	jmp loc_0c25
loc_0b81:
	mov byte ptr es:[bx+015ch], cl
	call _midi_lookup_track_state
	cmp si, 0ffh
	jnz loc_0b92
	jmp loc_0c25
loc_0b92:
	mov word ptr cs:[si + _cs_track_registry], 00h
	mov word ptr cs:[si + _cs_track_registry + 2], 00h
	cmp si, 3ch
	jz loc_0bcf
loc_0ba5:
	mov cx, word ptr cs:[si + _cs_track_registry + 4]
	mov word ptr cs:[si + _cs_track_registry], cx
	mov cx, word ptr cs:[si + _cs_track_registry + 6]
	mov word ptr cs:[si + _cs_track_registry + 2], cx
	add si, 04h
	cmp si, 3ch
	jnz loc_0ba5
	mov word ptr cs:[si + _cs_track_registry], 00h
	mov word ptr cs:[si + _cs_track_registry + 2], 00h
loc_0bcf:
	mov dl, byte ptr es:[bx+015ch]
	push es
	xor di, di
loc_0bd7:
	cmp word ptr cs:[di + _cs_track_registry + 2], 00h
	jz loc_0c15
	les bx, dword ptr cs:[di + _cs_track_registry]
	mov byte ptr es:[bx+015ch], dl
	jbe loc_0bf0
	add di, 04h
	jmp loc_0bd7
loc_0bf0:
	mov si, 38h
loc_0bf3:
	mov bx, si
	add bx, 04h
	cmp bx, di
	jz loc_0c15
	mov bx, word ptr cs:[si + _cs_track_registry]
	mov word ptr cs:[si + _cs_track_registry + 4], bx
	mov bx, word ptr cs:[si + _cs_track_registry + 2]
	mov word ptr cs:[si + _cs_track_registry + 6], bx
	sub si, 04h
	jmp loc_0bf3
loc_0c15:
	pop es
	mov word ptr cs:[di + _cs_track_registry], ax
	mov cx, es
	mov word ptr cs:[di + _cs_track_registry + 2], cx
	call _midi_recompute_active_voices
loc_0c25:
	pop di
	pop si
	pop dx
	pop cx
	pop bx
	popf
	retf
_midi_chord_propagate_setting endp

; ==============================================================
; midi_track_read_byte_158_inner  off 0x0c2c  size 10 (cmd 0x10)
;
;   Reads the track's +0x158 status/marker byte into CL (the far thunk returns
;   it in AX). 0xFF means the track has stopped.
; ==============================================================
	public _midi_track_read_byte_158_inner
_midi_track_read_byte_158_inner proc near
	push bx
	mov bx, ax
	mov cl, byte ptr es:[bx+0158h]
	pop bx
	retf
_midi_track_read_byte_158_inner endp

; ==============================================================
; midi_sound_slot_unlock  off 0x0c36  size 12 (cmd 0x19)
;
;   Atomically reads-and-clears the track's +0x158 status byte (XCHG with 0),
;   returning the old value in CL. Used to "unlock"/consume a one-shot status.
; ==============================================================
	public _midi_sound_slot_unlock
_midi_sound_slot_unlock proc near
	push bx
	mov bx, ax
	xor cl, cl
	xchg byte ptr es:[bx+0158h], cl
	pop bx
	retf
_midi_sound_slot_unlock endp

; ==============================================================
; midi_stub_nop  off 0x0c42  size 10 (cmd 0x11)
;
;   Returns the track's +0x152 marker/cue-hit counter in CX. (Named "nop"
;   because it has no side effect; it is purely a query.)
; ==============================================================
	public _midi_stub_nop
_midi_stub_nop proc near
	push bx
	mov bx, ax
	mov cx, word ptr es:[bx+0152h]
	pop bx
	retf
_midi_stub_nop endp

; ==============================================================
; midi_stub_return_ax  off 0x0c4c  size 33 (cmd 0x12)
;
;   Converts the track's tick clock (+0x154) into an elapsed time-of-play,
;   returned as (minutes-ish in AX kept by caller, seconds-derived in CH/CL).
;   0xE10 = 3600 ticks; dividing the clock by 3600 splits whole units from a
;   remainder, the remainder is divided by 60 (0x3C), and the seconds field is
;   halved. Used by the "song position" readout.
; ==============================================================
	public _midi_stub_return_ax
_midi_stub_return_ax proc near
	push ax
	push bx
	mov bx, ax
	mov ax, word ptr es:[bx+0154h]
	xor dx, dx
	mov cx, 0e10h	; 0e10h div divisor=3600 ticks/unit (next insn div cx)
	div cx                              ; AX = units, DX = remainder ticks
	push ax
	mov ax, dx
	mov cl, 3ch                         ; 60
	div cl                              ; AL = sub-units, AH = remainder
	mov cl, ah
	shr cl, 01h
	mov ch, al
	pop dx
	pop bx
	pop ax
	retf
_midi_stub_return_ax endp

; ==============================================================
; midi_cmd13_voice_release  off 0x0c6d  size 82 (cmd 0x13)
;
;   Releases one note voice: resolves the handle to a track slot, clears the
;   active-key slot (+0x125[ch]=0xFF), builds the voice key (track<<2|channel),
;   scans the voice-owner table (0x2e2) for the matching voice, and if found
;   issues a driver note-off (BP=4) for it. Bracketed by pause-refcount inc/dec.
;   cmd13/14/16 are a near-identical family (release / set-value / set-state);
;   only the byte they poke and the driver selector differ.
; ==============================================================
	public _midi_cmd13_voice_release
_midi_cmd13_voice_release proc near
	push ax
	push bx
	push dx
	push si
	inc byte ptr [_cs_pause_refcount]
	mov bx, ax
	call _midi_lookup_track_state
	cmp si, 0ffh
	jz loc_0cb5
	push si
	xor dh, dh
	mov si, dx
	mov byte ptr es:[bx+si+0125h], 0ffh
	mov ax, si
	pop si
	mov dx, si
	shl dl, 01h
	shl dl, 01h
	or dl, al
	xor si, si
	jmp loc_0ca2
	; A lone 0x90 (NOP) between the JMP and the loop body -- unreachable padding.
	db 90h
loc_0c9c:
	inc si
	cmp si, 10h
	jz loc_0cb5
loc_0ca2:
	; Scan the voice-owner table for the voice whose key equals DL.
	cmp byte ptr cs:[si + _cs_voice_ch_table], dl
	jnz loc_0c9c
	mov ax, si
	push bp
	mov bp, 04h
	call dword ptr [_cs_drvvec]
	pop bp
loc_0cb5:
	dec byte ptr [_cs_pause_refcount]
	pop dx
	pop bx
	pop ax
	pop si
	retf
_midi_cmd13_voice_release endp

; ==============================================================
; midi_cmd14_voice_set_value  off 0x0cbf  size 81 (cmd 0x14)
;
;   Sibling of cmd13: writes CH into the channel's active-key slot (+0x125),
;   then finds the matching voice in 0x2e2 and issues a driver call with BP=5
;   (note-on). Bracketed by pause-refcount inc/dec.
; ==============================================================
	public _midi_cmd14_voice_set_value
_midi_cmd14_voice_set_value proc near
	push ax
	push bx
	push dx
	push si
	inc byte ptr [_cs_pause_refcount]
	mov bx, ax
	call _midi_lookup_track_state
	cmp si, 0ffh
	jz loc_0d06
	push si
	xor dh, dh
	mov si, dx
	mov byte ptr es:[bx+si+0125h], ch
	mov ax, si
	pop si
	mov dx, si
	shl dl, 01h
	shl dl, 01h
	or dl, al
	xor si, si
	jmp loc_0cf3
	db 90h
loc_0ced:
	inc si
	cmp si, 10h
	jz loc_0d06
loc_0cf3:
	cmp byte ptr cs:[si + _cs_voice_ch_table], dl
	jnz loc_0ced
	mov ax, si
	push bp
	mov bp, 05h
	call dword ptr [_cs_drvvec]
	pop bp
loc_0d06:
	dec byte ptr [_cs_pause_refcount]
	pop dx
	pop bx
	pop ax
	pop si
	retf
_midi_cmd14_voice_set_value endp

; ==============================================================
; midi_apply_controller_change  off 0x0d10  size 222 (cmd 0x15)
;
;   Command-driven controller change (the mirror of the per-tick CC handler
;   midi_apply_ctrl_change_per_tick). Resolves the handle to a track slot,
;   then dispatches on the controller number in CH:
;     0x07 volume (re-scaled by master vol), 0x0A pan, 0x01 modulation,
;     0x40 sustain (bit15 of +0xbc), 0x4E (per-tick pitch nibble + recompute),
;     0x7F program. After updating per-channel state it finds the owning voice
;     in 0x2e2 and fires the matching driver selector (7 normally, 8 for 0x7F).
;   Interrupt-safe.
; ==============================================================
	public _midi_apply_controller_change
_midi_apply_controller_change proc near
	pushf
	cli
	push ax
	push bx
	push cx
	push dx
	push si
	mov bx, ax
	call _midi_lookup_track_state
	cmp si, 0ffh
	jnz loc_0d25
	jmp loc_0de7
loc_0d25:
	push si
	xor dh, dh
	mov si, dx
	cmp ch, 07h
	jnz loc_0d3e
	mov byte ptr es:[bx+si+0107h], cl
	mov dl, byte ptr es:[bx+015eh]
	call _midi_scale_velocity
	jmp loc_0dae
loc_0d3e:
	cmp ch, 0ah
	jnz loc_0d4a
	mov byte ptr es:[bx+si+0f8h], cl
	jmp loc_0dae
loc_0d4a:
	cmp ch, 01h
	jnz loc_0d56
	mov byte ptr es:[bx+si+0e9h], cl
	jmp loc_0dae
loc_0d56:
	cmp ch, 40h
	jnz loc_0d76
	shl si, 01h
	mov ax, word ptr es:[bx+si+0bch]
	and ah, 7fh
	cmp cl, 00h
	jz loc_0d6d
	or ah, 80h
loc_0d6d:
	mov word ptr es:[bx+si+0bch], ax
	shr si, 01h
	jmp loc_0dae
loc_0d76:
	cmp ch, 4eh
	jnz loc_0da4
	push dx
	mov dl, byte ptr es:[bx+si+0143h]
	cmp cl, 00h
	jnz loc_0d90
	cmp dl, 0fh
	jbe loc_0da0
	sub dl, 10h
	jmp loc_0d98
loc_0d90:
	cmp dl, 0f0h
	jnc loc_0da0
	add dl, 10h
loc_0d98:
	mov byte ptr es:[bx+si+0143h], dl
	call _midi_recompute_active_voices
loc_0da0:
	pop dx
	pop si
	jmp loc_0de7
loc_0da4:
	cmp ch, 7fh
	jnz loc_0dae
	mov byte ptr es:[bx+si+0116h], cl
loc_0dae:
	mov ax, si
	pop si
	mov dx, si
	shl dl, 01h
	shl dl, 01h
	or dl, al
	xor si, si
loc_0dbb:
	cmp byte ptr cs:[si + _cs_voice_ch_table], dl
	jz loc_0dca
	inc si
	cmp si, 10h
	jnz loc_0dbb
	jmp loc_0de7
loc_0dca:
	mov ax, si
	cmp ch, 7fh
	jnz loc_0ddd
	push bp
	mov bp, 08h
	call dword ptr [_cs_drvvec]
	pop bp
	jmp loc_0de7
loc_0ddd:
	push bp
	mov bp, 07h
	call dword ptr [_cs_drvvec]
	pop bp
loc_0de7:
	pop si
	pop dx
	pop cx
	pop bx
	pop ax
	popf
	retf
_midi_apply_controller_change endp

; ==============================================================
; midi_cmd16_voice_set_state  off 0x0dee  size 81 (cmd 0x16)
;
;   Sibling of cmd13/14: writes CL into the channel's program byte (+0x116),
;   finds the matching voice in 0x2e2, and issues a driver program-change
;   (BP=8). Bracketed by pause-refcount inc/dec.
; ==============================================================
	public _midi_cmd16_voice_set_state
_midi_cmd16_voice_set_state proc near
	push ax
	push bx
	push dx
	push si
	inc byte ptr [_cs_pause_refcount]
	mov bx, ax
	call _midi_lookup_track_state
	cmp si, 0ffh
	jz loc_0e35
	push si
	xor dh, dh
	mov si, dx
	mov byte ptr es:[bx+si+0116h], cl
	mov ax, si
	pop si
	mov dx, si
	shl dl, 01h
	shl dl, 01h
	or dl, al
	xor si, si
	jmp loc_0e22
	nop
loc_0e1c:
	inc si
	cmp si, 10h
	jz loc_0e35
loc_0e22:
	cmp byte ptr cs:[si + _cs_voice_ch_table], dl
	jnz loc_0e1c
	mov ax, si
	push bp
	mov bp, 08h
	call dword ptr [_cs_drvvec]
	pop bp
loc_0e35:
	dec byte ptr [_cs_pause_refcount]
	pop dx
	pop bx
	pop ax
	pop si
	retf
_midi_cmd16_voice_set_state endp

; ==============================================================
; midi_track_set_word_bc  off 0x0e3f  size 102 (cmd 0x17)
;
;   Sets a channel's +0xbc pitch/sustain word from CX (preserving the bit15
;   sustain latch already present), then if the channel currently owns a voice,
;   repacks the 14-bit value into the driver's (LSB,MSB) format and pushes it
;   with a driver call (BP=0x0a, the pitch-word selector).
; ==============================================================
	public _midi_track_set_word_bc
_midi_track_set_word_bc proc near
	push ax
	push bx
	push cx
	push dx
	push si
	mov bx, ax
	call _midi_lookup_track_state
	cmp si, 0ffh
	jz loc_0e9f
	push si
	xor dh, dh
	mov si, dx
	shl si, 01h
	mov ax, cx
	cmp byte ptr es:[bx+si+0bdh], 80h
	jc loc_0e63
	or ah, 80h
loc_0e63:
	mov word ptr es:[bx+si+0bch], ax
	shr si, 01h
	mov dx, si
	pop si
	shl si, 01h
	shl si, 01h
	or dx, si
	xor si, si
loc_0e75:
	cmp byte ptr cs:[si + _cs_voice_ch_table], dl
	jz loc_0e84
	inc si
	cmp si, 10h
	jnz loc_0e75
	jmp loc_0e9f
loc_0e84:
	shl ch, 01h
	cmp cl, 80h
	jc loc_0e8e
	or ch, 01h
loc_0e8e:
	and cl, 7fh
	xchg ch, cl
	mov ax, si
	push bp
	mov bp, 0ah
	call dword ptr [_cs_drvvec]
	pop bp
loc_0e9f:
	pop si
	pop dx
	pop cx
	pop bx
	pop ax
	retf
_midi_track_set_word_bc endp

; ==============================================================
; midi_track_release  off 0x0ea5  size 175
;
;   Removes a track from the 0x1c2 registry and tears down its playback. Finds
;   the slot whose far-ptr key equals (AX,ES), zeros it, then compacts the list
;   by shifting all following entries DOWN one slot (no holes) and clearing the
;   tail. Writes stop markers into the record (+0x158=0xFF, +0x159=0). If the
;   record is a streaming-SFX track (+0x165 set, high bit), it also fires a
;   final _snddrv_dispatch_cached call (selector 5) to stop the stream.
;
;   Inputs:  AX:ES = track far-ptr handle.  Returns near (RETN) -- it is only
;   ever called internally, never through the far-thunk band.
; ==============================================================
	public _midi_track_release
_midi_track_release proc near
	push si
	push es
	push ax
	push bx
	push ds
	push bp
	; Locate the registry slot matching (AX=offset, ES=segment).
	xor si, si
	mov cx, es
loc_0eaf:
	cmp ax, word ptr cs:[si + _cs_track_registry]
	jnz loc_0ebd
	cmp cx, word ptr cs:[si + _cs_track_registry + 2]
	jz loc_0ec8
loc_0ebd:
	add si, 04h
	cmp si, 40h
	jnz loc_0eaf
	jmp loc_0f4d
loc_0ec8:
	mov word ptr cs:[si + _cs_track_registry], 00h
	mov word ptr cs:[si + _cs_track_registry + 2], 00h
	cmp si, 3ch
	jz loc_0f05
loc_0edb:
	mov cx, word ptr cs:[si + _cs_track_registry + 4]
	mov word ptr cs:[si + _cs_track_registry], cx
	mov cx, word ptr cs:[si + _cs_track_registry + 6]
	mov word ptr cs:[si + _cs_track_registry + 2], cx
	add si, 04h
	cmp si, 3ch
	jnz loc_0edb
	mov word ptr cs:[si + _cs_track_registry], 00h
	mov word ptr cs:[si + _cs_track_registry + 2], 00h
loc_0f05:
	; Write stop markers into the record.
	mov bx, ax
	mov byte ptr es:[bx+0158h], 0ffh
	mov byte ptr es:[bx+0159h], 00h
	; If this is a streaming-SFX track (+0x165 set, with bit7 = active stream),
	; walk into its script to find the stream-stop entry and tell the cached
	; driver shim (selector 5) to stop it.
	cmp byte ptr es:[bx+0165h], 00h
	jz loc_0f4d
	lds bp, es:[bx+08h]
	lds bp, ds:[bp+00h]
	mov al, byte ptr es:[bx+0165h]
	cmp al, 80h
	jc loc_0f4d
	and ax, 0fh
	dec ax
	shl ax, 01h
	push bp
	add bp, ax
	mov ax, word ptr ds:[bp+00h]
	pop bp
	add bp, ax
	mov ax, bp
	xor ax, ax
	push ax
	mov ax, 05h
	push ax
	call far ptr _snddrv_dispatch_cached
	add sp, 04h
loc_0f4d:
	pop bp
	pop ds
	pop bx
	pop ax
	pop es
	pop si
	retn
_midi_track_release endp

; ==============================================================
; midi_recompute_active_voices  off 0x0f54  size 2495
;
;   THE VOICE ARBITER -- the largest function in the module. The output device
;   has a fixed, bounded number of physical voices (the +1/+2 low/high index
;   range set by cmd1), but the sum of all playing tracks' channels can want
;   more notes than that. This function decides which logical notes get a
;   physical voice. It runs lazily: it is triggered by the voices-dirty flag
;   (+0x0b), which is set by anything that changes voice demand (track start/
;   stop, hold-count change, priority/chord change, the 0x4B/0x4E controllers,
;   end-of-track), so several state changes in one frame coalesce into one pass.
;
;   Flow (full detail in reference/midi_32c8_behavior.md s6):
;     1. Bump the pause-refcount (locks out the tick) and clear voices-dirty.
;     2. Clear the voice pool: owners (0x2e2/staging 0x322) -> 0xFF (free),
;        age/cost/flag arrays -> 0.
;     3. If the registry is empty, leave everything free and return.
;     4. Walk every registered track (skip held ones); for each channel compute
;        a voice cost (low nibble of +0xda) and priority bias (high nibble),
;        then find or STEAL a voice -- stealing the stalest (max-age) voice when
;        none is free, with a full save/restore of the staging band so a failed
;        allocation rolls back. (The long repeated mov-word blocks below are that
;        bulk snapshot/restore of the staging arrays.)
;     5. Diff the new staging owner table against the live 0x2e2 and re-key only
;        the voices that changed (program-change + scaled velocity + note).
;     6. Compact into the final 0x2e2/0x242/0x372 tables.
;     7. Drop the pause-refcount and return (RETN; internal-only).
; ==============================================================
	public _midi_recompute_active_voices
_midi_recompute_active_voices proc near
	push ax
	push bx
	push cx
	push dx
	push di
	push si
	push bp
	push es
	; Step 1: lock out the tick, clear the voices-dirty flag.
	inc byte ptr [_cs_pause_refcount]
	mov byte ptr [_cs_pause_refcount + 11], 00h
	; Step 2: clear the voice pool (owner table to 0xFFFF=free, the
	; cost/flag/priority arrays to 0). The unrolled stores below cover all 16
	; entries of each array.
	xor ax, ax
	mov bx, 0ffffh
	mov word ptr [_cs_voice_ch_table], bx
	mov word ptr [_cs_voice_ch_table + 2], bx
	mov word ptr [_cs_voice_ch_table + 4], bx
	mov word ptr [_cs_voice_ch_table + 6], bx
	mov word ptr [_cs_voice_ch_table + 8], bx
	mov word ptr [_cs_voice_ch_table + 10], bx
	mov word ptr [_cs_voice_ch_table + 12], bx
	mov word ptr [_cs_voice_ch_table + 14], bx
	mov word ptr [_cs_voice_credit], ax
	mov word ptr [_cs_voice_credit + 2], ax
	mov word ptr [_cs_voice_credit + 4], ax
	mov word ptr [_cs_voice_credit + 6], ax
	mov word ptr [_cs_voice_credit + 8], ax
	mov word ptr [_cs_voice_credit + 10], ax
	mov word ptr [_cs_voice_credit + 12], ax
	mov word ptr [_cs_voice_credit + 14], ax
	mov word ptr [_cs_voice_flags], ax
	mov word ptr [_cs_voice_flags + 2], ax
	mov word ptr [_cs_voice_flags + 4], ax
	mov word ptr [_cs_voice_flags + 6], ax
	mov word ptr [_cs_voice_flags + 8], ax
	mov word ptr [_cs_voice_flags + 10], ax
	mov word ptr [_cs_voice_flags + 12], ax
	mov word ptr [_cs_voice_flags + 14], ax
	mov word ptr [_cs_voice_priority], ax
	mov word ptr [_cs_voice_priority + 2], ax
	mov word ptr [_cs_voice_priority + 4], ax
	mov word ptr [_cs_voice_priority + 6], ax
	mov word ptr [_cs_voice_priority + 8], ax
	mov word ptr [_cs_voice_priority + 10], ax
	mov word ptr [_cs_voice_priority + 12], ax
	mov word ptr [_cs_voice_priority + 14], ax
	mov word ptr [_cs_voice_note], bx
	mov word ptr [_cs_voice_note + 2], bx
	mov word ptr [_cs_voice_note + 4], bx
	mov word ptr [_cs_voice_note + 6], bx
	mov word ptr [_cs_voice_note + 8], bx
	mov word ptr [_cs_voice_note + 10], bx
	mov word ptr [_cs_voice_note + 12], bx
	mov word ptr [_cs_voice_note + 14], bx
	mov word ptr [_cs_pending_track], ax
	mov word ptr [_cs_pending_track + 2], ax
	les bx, dword ptr [_cs_track_registry]
	mov dx, es
	or dx, bx
	jnz loc_105d
	mov dx, 0ffffh
	mov word ptr [_cs_voice_ch_table], dx
	mov word ptr [_cs_voice_ch_table + 2], dx
	mov word ptr [_cs_voice_ch_table + 4], dx
	mov word ptr [_cs_voice_ch_table + 6], dx
	mov word ptr [_cs_voice_ch_table + 8], dx
	mov word ptr [_cs_voice_ch_table + 10], dx
	mov word ptr [_cs_voice_ch_table + 12], dx
	mov word ptr [_cs_voice_ch_table + 14], dx
	jmp loc_182b
loc_105d:
	mov cl, byte ptr es:[bx+015fh]
	cmp cl, 7fh
	jnz loc_106c
	mov cl, byte ptr [_cs_pause_refcount + 9]
loc_106c:
	push bp
	mov bp, 0bh
	call dword ptr [_cs_drvvec]
	pop bp
	xor bp, bp
	xor si, si
	mov al, byte ptr [_cs_pause_refcount + 6]
loc_107e:
	les bx, dword ptr cs:[si + _cs_track_registry]
	mov dx, es
	or dx, bx
	jnz loc_108c
	jmp loc_1576
loc_108c:
	les bx, dword ptr cs:[si + _cs_track_registry]
	cmp byte ptr es:[bx+0164h], 00h
	jz loc_109c
	jmp loc_1568
loc_109c:
	cmp byte ptr es:[bx+0165h], 00h
	jz loc_10c9
	cmp word ptr [_cs_pending_track], 00h
	jz loc_10af
	jmp loc_1568
loc_10af:
	cmp word ptr [_cs_pending_track + 2], 00h
	jz loc_10ba
	jmp loc_1568
loc_10ba:
	mov word ptr [_cs_pending_track], bx
	mov bx, es
	mov word ptr [_cs_pending_track + 2], bx
	jmp loc_1568
loc_10c9:
	; Snapshot the whole staging band (note/priority/credit/flags) into the
	; _cs_voice_snap save area so a failed allocation for this track can roll
	; back. The mirror restore block is at loc_1462.
	push ax
	mov ax, word ptr [_cs_voice_note]
	mov word ptr [_cs_voice_snap + 48], ax
	mov ax, word ptr [_cs_voice_note + 2]
	mov word ptr [_cs_voice_snap + 50], ax
	mov ax, word ptr [_cs_voice_note + 4]
	mov word ptr [_cs_voice_snap + 52], ax
	mov ax, word ptr [_cs_voice_note + 6]
	mov word ptr [_cs_voice_snap + 54], ax
	mov ax, word ptr [_cs_voice_note + 8]
	mov word ptr [_cs_voice_snap + 56], ax
	mov ax, word ptr [_cs_voice_note + 10]
	mov word ptr [_cs_voice_snap + 58], ax
	mov ax, word ptr [_cs_voice_note + 12]
	mov word ptr [_cs_voice_snap + 60], ax
	mov ax, word ptr [_cs_voice_note + 14]
	mov word ptr [_cs_voice_snap + 62], ax
	mov ax, word ptr [_cs_voice_priority]
	mov word ptr [_cs_voice_snap + 16], ax
	mov ax, word ptr [_cs_voice_priority + 2]
	mov word ptr [_cs_voice_snap + 18], ax
	mov ax, word ptr [_cs_voice_priority + 4]
	mov word ptr [_cs_voice_snap + 20], ax
	mov ax, word ptr [_cs_voice_priority + 6]
	mov word ptr [_cs_voice_snap + 22], ax
	mov ax, word ptr [_cs_voice_priority + 8]
	mov word ptr [_cs_voice_snap + 24], ax
	mov ax, word ptr [_cs_voice_priority + 10]
	mov word ptr [_cs_voice_snap + 26], ax
	mov ax, word ptr [_cs_voice_priority + 12]
	mov word ptr [_cs_voice_snap + 28], ax
	mov ax, word ptr [_cs_voice_priority + 14]
	mov word ptr [_cs_voice_snap + 30], ax
	mov ax, word ptr [_cs_voice_credit]
	mov word ptr [_cs_voice_snap + 32], ax
	mov ax, word ptr [_cs_voice_credit + 2]
	mov word ptr [_cs_voice_snap + 34], ax
	mov ax, word ptr [_cs_voice_credit + 4]
	mov word ptr [_cs_voice_snap + 36], ax
	mov ax, word ptr [_cs_voice_credit + 6]
	mov word ptr [_cs_voice_snap + 38], ax
	mov ax, word ptr [_cs_voice_credit + 8]
	mov word ptr [_cs_voice_snap + 40], ax
	mov ax, word ptr [_cs_voice_credit + 10]
	mov word ptr [_cs_voice_snap + 42], ax
	mov ax, word ptr [_cs_voice_credit + 12]
	mov word ptr [_cs_voice_snap + 44], ax
	mov ax, word ptr [_cs_voice_credit + 14]
	mov word ptr [_cs_voice_snap + 46], ax
	mov ax, word ptr [_cs_voice_flags]
	mov word ptr [_cs_voice_snap], ax
	mov ax, word ptr [_cs_voice_flags + 2]
	mov word ptr [_cs_voice_snap + 2], ax
	mov ax, word ptr [_cs_voice_flags + 4]
	mov word ptr [_cs_voice_snap + 4], ax
	mov ax, word ptr [_cs_voice_flags + 6]
	mov word ptr [_cs_voice_snap + 6], ax
	mov ax, word ptr [_cs_voice_flags + 8]
	mov word ptr [_cs_voice_snap + 8], ax
	mov ax, word ptr [_cs_voice_flags + 10]
	mov word ptr [_cs_voice_snap + 10], ax
	mov ax, word ptr [_cs_voice_flags + 12]
	mov word ptr [_cs_voice_snap + 12], ax
	mov ax, word ptr [_cs_voice_flags + 14]
	mov word ptr [_cs_voice_snap + 14], ax
	pop ax
	mov byte ptr [_cs_pause_refcount + 10], al
	xor di, di
loc_11d1:
	mov cl, byte ptr es:[bx+di+8ch]
	cmp cl, 0ffh
	jnz loc_11de
	jmp loc_1456
loc_11de:
	cmp cl, 0feh
	jnz loc_11e6
	jmp loc_1456
loc_11e6:
	cmp cl, 0fh
	jnz loc_11ee
	jmp loc_1456
loc_11ee:
	push di
	mov di, cx
	and di, 0ffh
	test byte ptr es:[bx+di+0134h], 02h
	jz loc_1201
	pop di
	jmp loc_1456
loc_1201:
	test byte ptr es:[bx+di+0143h], 0ffh
	pop di
	jz loc_120d
	jmp loc_1456
loc_120d:
	mov dx, si
	shl dl, 01h
	shl dl, 01h
	or dl, cl
	push di
	mov di, cx
	and di, 0ffh
	mov ah, byte ptr es:[bx+di+0dah]
	and ah, 0fh
	mov ch, byte ptr es:[bx+di+0dah]
	pop di
	shr ch, 01h
	shr ch, 01h
	shr ch, 01h
	shr ch, 01h
	jz loc_123f
	push dx
	mov dx, 10h
	sub dl, ch
	add dx, bp
	mov ch, dl
	pop dx
loc_123f:
	push di
	mov di, cx
	and di, 0ffh
	test byte ptr es:[bx+di+0134h], 01h
	jz loc_125c
	cmp byte ptr cs:[di + _cs_voice_note], 0ffh
	jnz loc_125c
	pop di
	mov dh, cl
	jmp loc_12ec
loc_125c:
	pop di
	mov dh, 0ffh
	push bx
	xor bx, bx
loc_1262:
	cmp byte ptr cs:[bx + _cs_voice_note], 0ffh
	jz loc_1275
	cmp byte ptr cs:[bx + _cs_voice_note], dl
	jnz loc_1285
	pop bx
	jmp loc_1456
loc_1275:
	cmp bl, byte ptr [_cs_pause_refcount + 1]
	jc loc_1285
	cmp bl, byte ptr [_cs_pause_refcount + 2]
	ja loc_1285
	mov dh, bl
loc_1285:
	inc bl
	cmp bl, 10h
	jnz loc_1262
	pop bx
	cmp dh, 0ffh
	jnz loc_12ec
	cmp ch, 00h
	jz loc_129a
	jmp loc_1568
loc_129a:
	push di
	push cx
	push ax
	mov dh, 0ffh
	xor ax, ax
	xor di, di
loc_12a3:
	cmp al, byte ptr cs:[di + _cs_voice_priority]
	jnc loc_12b3
	mov al, byte ptr cs:[di + _cs_voice_priority]
	mov cx, di
	mov dh, cl
loc_12b3:
	inc di
	cmp di, 10h
	jnz loc_12a3
	pop ax
	cmp dh, 0ffh
	jz loc_12e2
	xor cx, cx
	mov cl, dh
	mov di, cx
	add al, byte ptr cs:[di + _cs_voice_credit]
	mov byte ptr cs:[di + _cs_voice_note], 0ffh
	mov byte ptr cs:[di + _cs_voice_credit], 00h
	mov byte ptr cs:[di + _cs_voice_priority], 00h
	mov byte ptr cs:[di + _cs_voice_flags], 00h
loc_12e2:
	pop cx
	pop di
	cmp dh, 0ffh
	jnz loc_12ec
	jmp loc_1462
loc_12ec:
	cmp ah, al
	jbe loc_134e
	cmp ch, 00h
	jz loc_12f8
	jmp loc_1456
loc_12f8:
	push di
	push cx
	push ax
	mov dh, 0ffh
	xor ax, ax
	xor di, di
loc_1301:
	cmp al, byte ptr cs:[di + _cs_voice_priority]
	jnc loc_1311
	mov al, byte ptr cs:[di + _cs_voice_priority]
	mov cx, di
	mov dh, cl
loc_1311:
	inc di
	cmp di, 10h
	jnz loc_1301
	pop ax
	cmp dh, 0ffh
	jz loc_1340
	xor cx, cx
	mov cl, dh
	mov di, cx
	add al, byte ptr cs:[di + _cs_voice_credit]
	mov byte ptr cs:[di + _cs_voice_note], 0ffh
	mov byte ptr cs:[di + _cs_voice_credit], 00h
	mov byte ptr cs:[di + _cs_voice_priority], 00h
	mov byte ptr cs:[di + _cs_voice_flags], 00h
loc_1340:
	pop cx
	pop di
	cmp dh, 0ffh
	jnz loc_134a
	jmp loc_1462
loc_134a:
	cmp ah, al
	ja loc_12f8
loc_134e:
	push di
	xchg dl, dh
	mov di, dx
	xchg dl, dh
	and di, 0ffh
	mov byte ptr cs:[di + _cs_voice_note], dl
	mov byte ptr cs:[di + _cs_voice_credit], ah
	sub al, ah
	mov byte ptr cs:[di + _cs_voice_priority], ch
	push di
	mov di, cx
	and di, 0ffh
	test byte ptr es:[bx+di+0134h], 01h
	pop di
	jnz loc_1384
	mov byte ptr cs:[di + _cs_voice_flags], 00h
	pop di
	jmp loc_1456
loc_1384:
	mov byte ptr cs:[di + _cs_voice_flags], 01h
	cmp dh, cl
	jnz loc_1392
	pop di
	jmp loc_1456
loc_1392:
	push si
	mov si, cx
	and si, 0ffh
	cmp byte ptr cs:[si + _cs_voice_flags], 00h
	jnz loc_13f7
	push ax
	mov al, byte ptr cs:[di + _cs_voice_note]
	mov ah, byte ptr cs:[si + _cs_voice_note]
	mov byte ptr cs:[di + _cs_voice_note], ah
	mov byte ptr cs:[si + _cs_voice_note], al
	mov al, byte ptr cs:[di + _cs_voice_priority]
	mov ah, byte ptr cs:[si + _cs_voice_priority]
	mov byte ptr cs:[di + _cs_voice_priority], ah
	mov byte ptr cs:[si + _cs_voice_priority], al
	mov al, byte ptr cs:[di + _cs_voice_credit]
	mov ah, byte ptr cs:[si + _cs_voice_credit]
	mov byte ptr cs:[di + _cs_voice_credit], ah
	mov byte ptr cs:[si + _cs_voice_credit], al
	mov al, byte ptr cs:[di + _cs_voice_flags]
	mov ah, byte ptr cs:[si + _cs_voice_flags]
	mov byte ptr cs:[di + _cs_voice_flags], ah
	mov byte ptr cs:[si + _cs_voice_flags], al
	pop ax
	pop si
	pop di
	jmp loc_1456
loc_13f7:
	cmp ch, 00h
	jz loc_141a
	mov byte ptr cs:[di + _cs_voice_note], 0ffh
	mov byte ptr cs:[di + _cs_voice_priority], 00h
	mov byte ptr cs:[di + _cs_voice_credit], 00h
	mov byte ptr cs:[di + _cs_voice_flags], 00h
	add al, ah
	pop si
	pop di
	jmp loc_1456
loc_141a:
	cmp byte ptr cs:[si + _cs_voice_priority], 00h
	jnz loc_1426
	pop si
	pop di
	jmp loc_1462
loc_1426:
	add al, byte ptr cs:[si + _cs_voice_credit]
	mov byte ptr cs:[di + _cs_voice_note], 0ffh
	mov byte ptr cs:[di + _cs_voice_credit], 00h
	mov byte ptr cs:[di + _cs_voice_priority], 00h
	mov byte ptr cs:[di + _cs_voice_flags], 00h
	mov byte ptr cs:[si + _cs_voice_note], dl
	mov byte ptr cs:[si + _cs_voice_priority], ch
	mov byte ptr cs:[si + _cs_voice_credit], ah
	sub al, ah
	pop si
	pop di
loc_1456:
	inc di
	cmp di, 10h
	jnz loc_145f
	jmp loc_1568
loc_145f:
	jmp loc_11d1
loc_1462:
	; ROLLBACK: restore the staging band from the _cs_voice_snap snapshot taken
	; at loc_10c9 (this track's allocation attempt failed; undo it).
	push ax
	mov ax, word ptr [_cs_voice_snap + 48]
	mov word ptr [_cs_voice_note], ax
	mov ax, word ptr [_cs_voice_snap + 50]
	mov word ptr [_cs_voice_note + 2], ax
	mov ax, word ptr [_cs_voice_snap + 52]
	mov word ptr [_cs_voice_note + 4], ax
	mov ax, word ptr [_cs_voice_snap + 54]
	mov word ptr [_cs_voice_note + 6], ax
	mov ax, word ptr [_cs_voice_snap + 56]
	mov word ptr [_cs_voice_note + 8], ax
	mov ax, word ptr [_cs_voice_snap + 58]
	mov word ptr [_cs_voice_note + 10], ax
	mov ax, word ptr [_cs_voice_snap + 60]
	mov word ptr [_cs_voice_note + 12], ax
	mov ax, word ptr [_cs_voice_snap + 62]
	mov word ptr [_cs_voice_note + 14], ax
	mov ax, word ptr [_cs_voice_snap + 16]
	mov word ptr [_cs_voice_priority], ax
	mov ax, word ptr [_cs_voice_snap + 18]
	mov word ptr [_cs_voice_priority + 2], ax
	mov ax, word ptr [_cs_voice_snap + 20]
	mov word ptr [_cs_voice_priority + 4], ax
	mov ax, word ptr [_cs_voice_snap + 22]
	mov word ptr [_cs_voice_priority + 6], ax
	mov ax, word ptr [_cs_voice_snap + 24]
	mov word ptr [_cs_voice_priority + 8], ax
	mov ax, word ptr [_cs_voice_snap + 26]
	mov word ptr [_cs_voice_priority + 10], ax
	mov ax, word ptr [_cs_voice_snap + 28]
	mov word ptr [_cs_voice_priority + 12], ax
	mov ax, word ptr [_cs_voice_snap + 30]
	mov word ptr [_cs_voice_priority + 14], ax
	mov ax, word ptr [_cs_voice_snap + 32]
	mov word ptr [_cs_voice_credit], ax
	mov ax, word ptr [_cs_voice_snap + 34]
	mov word ptr [_cs_voice_credit + 2], ax
	mov ax, word ptr [_cs_voice_snap + 36]
	mov word ptr [_cs_voice_credit + 4], ax
	mov ax, word ptr [_cs_voice_snap + 38]
	mov word ptr [_cs_voice_credit + 6], ax
	mov ax, word ptr [_cs_voice_snap + 40]
	mov word ptr [_cs_voice_credit + 8], ax
	mov ax, word ptr [_cs_voice_snap + 42]
	mov word ptr [_cs_voice_credit + 10], ax
	mov ax, word ptr [_cs_voice_snap + 44]
	mov word ptr [_cs_voice_credit + 12], ax
	mov ax, word ptr [_cs_voice_snap + 46]
	mov word ptr [_cs_voice_credit + 14], ax
	mov ax, word ptr [_cs_voice_snap]
	mov word ptr [_cs_voice_flags], ax
	mov ax, word ptr [_cs_voice_snap + 2]
	mov word ptr [_cs_voice_flags + 2], ax
	mov ax, word ptr [_cs_voice_snap + 4]
	mov word ptr [_cs_voice_flags + 4], ax
	mov ax, word ptr [_cs_voice_snap + 6]
	mov word ptr [_cs_voice_flags + 6], ax
	mov ax, word ptr [_cs_voice_snap + 8]
	mov word ptr [_cs_voice_flags + 8], ax
	mov ax, word ptr [_cs_voice_snap + 10]
	mov word ptr [_cs_voice_flags + 10], ax
	mov ax, word ptr [_cs_voice_snap + 12]
	mov word ptr [_cs_voice_flags + 12], ax
	mov ax, word ptr [_cs_voice_snap + 14]
	mov word ptr [_cs_voice_flags + 14], ax
	pop ax
	mov al, byte ptr [_cs_pause_refcount + 10]
loc_1568:
	add bp, 10h
	add si, 04h
	cmp si, 40h
	jz loc_1576
	jmp loc_107e
loc_1576:
	xor si, si
loc_1578:
	cmp byte ptr cs:[si + _cs_voice_note], 0ffh
	jnz loc_1583
	jmp loc_170b
loc_1583:
	cmp byte ptr cs:[si + _cs_voice_flags], 00h
	jnz loc_158e
	jmp loc_169c
loc_158e:
	xor ax, ax
	mov al, byte ptr cs:[si + _cs_voice_note]
	mov byte ptr cs:[si + _cs_voice_note], 0ffh
	mov byte ptr cs:[si + _cs_voice_ch_table], al
	mov di, ax
	and di, 0f0h
	shr di, 01h
	shr di, 01h
	les bx, dword ptr cs:[di + _cs_track_registry]
	and al, 0fh
	cmp byte ptr cs:[si + _cs_voice_ch_cache], al
	jnz loc_15d1
	mov di, si
	shl di, 01h
	shl di, 01h
	cmp word ptr cs:[di + _cs_voice_track_table], bx
	jnz loc_15d1
	mov cx, es
	cmp word ptr cs:[di + _cs_voice_track_table + 2], cx
	jnz loc_15d1
	jmp loc_170b
loc_15d1:
	; Step 5: this voice's owner changed -> re-key it on the hardware. The
	; sequence of CALL [_cs_drvvec] with BP=7 (controller) / 8 (program) and the
	; 0x7b00/0x4b00 magic CX values pushes the full per-voice patch: program,
	; sound-controllers 6/9, volume (scaled), pan, modulation, pitch word, then a
	; CC-0x4E (sel BP=7, CH=0x4e). Only voices that actually changed reach here.
	push ax
	push dx
	push si
	xor ah, ah
	xchg si, ax
	mov cx, 7b00h
	push bp
	mov bp, 07h
	call dword ptr [_cs_drvvec]
	pop bp
	mov cl, byte ptr es:[bx+si+0dah]
	and cl, 0fh
	mov ch, 4bh
	push bp
	mov bp, 07h
	call dword ptr [_cs_drvvec]
	pop bp
	mov cl, byte ptr es:[bx+si+0116h]
	push bp
	mov bp, 08h
	call dword ptr [_cs_drvvec]
	pop bp
	push si
	mov si, ax
	mov byte ptr cs:[si + _cs_voice_refresh], 0ffh
	pop si
	mov cl, byte ptr es:[bx+si+0107h]
	mov dl, byte ptr es:[bx+015eh]
	call _midi_scale_velocity
	mov ch, 07h
	push bp
	mov bp, 07h
	call dword ptr [_cs_drvvec]
	pop bp
	mov ch, 0ah
	mov cl, byte ptr es:[bx+si+0f8h]
	push bp
	mov bp, 07h
	call dword ptr [_cs_drvvec]
	pop bp
	mov ch, 01h
	mov cl, byte ptr es:[bx+si+0e9h]
	push bp
	mov bp, 07h
	call dword ptr [_cs_drvvec]
	pop bp
	shl si, 01h
	mov cx, 4000h	; 4000h MIDI ctrl 0x40 cmd word (CL=val) -> drvvec call
	cmp byte ptr es:[bx+si+0bdh], 80h
	jc loc_165b
	mov cl, 7fh
loc_165b:
	push bp
	mov bp, 07h
	call dword ptr [_cs_drvvec]
	pop bp
	mov cx, word ptr es:[bx+si+0bch]
	shr si, 01h
	xchg cl, ch
	shl cl, 01h
	cmp ch, 80h
	jc loc_1678
	or cl, 01h
loc_1678:
	and cx, 7f7fh
	push bp
	mov bp, 0ah
	call dword ptr [_cs_drvvec]
	pop bp
	mov cl, byte ptr es:[bx+si+0125h]
	mov ch, 4eh
	push bp
	mov bp, 07h
	call dword ptr [_cs_drvvec]
	pop bp
	pop si
	pop dx
	pop ax
	jmp loc_170b
loc_169c:
	mov al, byte ptr cs:[si + _cs_voice_note]
	mov bl, al
	and ax, 0fh
	and bx, 0f0h
	shr bl, 01h
	shr bl, 01h
	les bx, dword ptr cs:[bx + _cs_track_registry]
	mov cl, byte ptr [_cs_pause_refcount + 1]
	xor ch, ch
	mov di, cx
	shl di, 01h
	shl di, 01h
loc_16c0:
	cmp word ptr cs:[di + _cs_voice_track_table], bx
	jnz loc_16df
	mov cx, es
	cmp word ptr cs:[di + _cs_voice_track_table + 2], cx
	jnz loc_16df
	shr di, 01h
	shr di, 01h
	cmp byte ptr cs:[di + _cs_voice_ch_cache], al
	jz loc_16f3
	shl di, 01h
	shl di, 01h
loc_16df:
	add di, 04h
	mov cx, di
	shr cl, 01h
	shr cl, 01h
	dec cl
	cmp byte ptr [_cs_pause_refcount + 2], cl
	jnz loc_16c0
	jmp loc_170b
loc_16f3:
	cmp byte ptr cs:[di + _cs_voice_flags], 00h
	jnz loc_170b
	mov cl, byte ptr cs:[si + _cs_voice_note]
	mov byte ptr cs:[di + _cs_voice_ch_table], cl
	mov byte ptr cs:[si + _cs_voice_note], 0ffh
loc_170b:
	inc si
	cmp si, 10h
	jz loc_1714
	jmp loc_1578
loc_1714:
	mov al, byte ptr [_cs_pause_refcount + 2]
	inc al
	xor ah, ah
	mov di, ax
	xor al, al
	xor si, si
loc_1722:
	cmp byte ptr cs:[si + _cs_voice_note], 0ffh
	jnz loc_172d
	jmp loc_1822
loc_172d:
	mov bx, di
loc_172f:
	dec bx
	cmp byte ptr cs:[bx + _cs_voice_ch_table], 0ffh
	jnz loc_172f
	mov di, bx
	mov al, byte ptr cs:[si + _cs_voice_note]
	mov byte ptr cs:[di + _cs_voice_ch_table], al
	mov bl, al
	and al, 0fh
	and bx, 0f0h
	shr bx, 01h
	shr bx, 01h
	les bx, dword ptr cs:[bx + _cs_track_registry]
	push si
	mov si, di
	push ax
	push dx
	push si
	xor ah, ah
	xchg si, ax
	mov cx, 7b00h
	push bp
	mov bp, 07h
	call dword ptr [_cs_drvvec]
	pop bp
	mov cl, byte ptr es:[bx+si+0dah]
	and cl, 0fh
	mov ch, 4bh
	push bp
	mov bp, 07h
	call dword ptr [_cs_drvvec]
	pop bp
	mov cl, byte ptr es:[bx+si+0116h]
	push bp
	mov bp, 08h
	call dword ptr [_cs_drvvec]
	pop bp
	push si
	mov si, ax
	mov byte ptr cs:[si + _cs_voice_refresh], 0ffh
	pop si
	mov cl, byte ptr es:[bx+si+0107h]
	mov dl, byte ptr es:[bx+015eh]
	call _midi_scale_velocity
	mov ch, 07h
	push bp
	mov bp, 07h
	call dword ptr [_cs_drvvec]
	pop bp
	mov ch, 0ah
	mov cl, byte ptr es:[bx+si+0f8h]
	push bp
	mov bp, 07h
	call dword ptr [_cs_drvvec]
	pop bp
	mov ch, 01h
	mov cl, byte ptr es:[bx+si+0e9h]
	push bp
	mov bp, 07h
	call dword ptr [_cs_drvvec]
	pop bp
	shl si, 01h
	mov cx, 4000h	; 4000h MIDI ctrl 0x40 cmd word (CL=val) -> drvvec call
	cmp byte ptr es:[bx+si+0bdh], 80h
	jc loc_17e2
	mov cl, 7fh
loc_17e2:
	push bp
	mov bp, 07h
	call dword ptr [_cs_drvvec]
	pop bp
	mov cx, word ptr es:[bx+si+0bch]
	shr si, 01h
	xchg cl, ch
	shl cl, 01h
	cmp ch, 80h
	jc loc_17ff
	or cl, 01h
loc_17ff:
	and cx, 7f7fh
	push bp
	mov bp, 0ah
	call dword ptr [_cs_drvvec]
	pop bp
	mov cl, byte ptr es:[bx+si+0125h]
	mov ch, 4eh
	push bp
	mov bp, 07h
	call dword ptr [_cs_drvvec]
	pop bp
	pop si
	pop dx
	pop ax
	pop si
loc_1822:
	inc si
	cmp si, 10h
	jz loc_182b
	jmp loc_1722
loc_182b:
	mov si, 0fh
loc_182e:
	cmp byte ptr cs:[si + _cs_voice_ch_cache], 0fh
	jz loc_1867
	cmp byte ptr cs:[si + _cs_voice_ch_table], 0ffh
	jnz loc_1867
	mov ax, si
	mov cx, 4000h	; 4000h MIDI ctrl 0x40 reset cmd word -> drvvec call
	push bp
	mov bp, 07h
	call dword ptr [_cs_drvvec]
	pop bp
	mov cx, 7b00h
	push bp
	mov bp, 07h
	call dword ptr [_cs_drvvec]
	pop bp
	mov cx, 4b00h	; 4b00h MIDI ctrl 0x4b reset cmd word -> drvvec call
	push bp
	mov bp, 07h
	call dword ptr [_cs_drvvec]
	pop bp
loc_1867:
	dec si
	jns loc_182e
	mov ax, word ptr [_cs_voice_ch_table]
	and ax, 0f0fh
	mov word ptr [_cs_voice_ch_cache], ax
	mov ax, word ptr [_cs_voice_ch_table + 2]
	and ax, 0f0fh
	mov word ptr [_cs_voice_ch_cache + 2], ax
	mov ax, word ptr [_cs_voice_ch_table + 4]
	and ax, 0f0fh
	mov word ptr [_cs_voice_ch_cache + 4], ax
	mov ax, word ptr [_cs_voice_ch_table + 6]
	and ax, 0f0fh
	mov word ptr [_cs_voice_ch_cache + 6], ax
	mov ax, word ptr [_cs_voice_ch_table + 8]
	and ax, 0f0fh
	mov word ptr [_cs_voice_ch_cache + 8], ax
	mov ax, word ptr [_cs_voice_ch_table + 10]
	and ax, 0f0fh
	mov word ptr [_cs_voice_ch_cache + 10], ax
	mov ax, word ptr [_cs_voice_ch_table + 12]
	and ax, 0f0fh
	mov word ptr [_cs_voice_ch_cache + 12], ax
	mov ax, word ptr [_cs_voice_ch_table + 14]
	and ax, 0f0fh
	mov word ptr [_cs_voice_ch_cache + 14], ax
	; Step 6: compact -- for each voice, copy its owning track's far-ptr from
	; the 0x1c2 registry into the per-voice owner table 0x242 (or zero it if the
	; voice is free). Lets later code map a voice back to its track in O(1).
	xor si, si
	xor di, di
loc_18c6:
	mov bl, byte ptr cs:[si + _cs_voice_ch_table]
	cmp bl, 0ffh
	jnz loc_18e0
	mov word ptr cs:[di + _cs_voice_track_table], 00h
	mov word ptr cs:[di + _cs_voice_track_table + 2], 00h
	jmp loc_18fc
loc_18e0:
	and bx, 0f0h
	shr bx, 01h
	shr bx, 01h
	mov ax, word ptr cs:[bx + _cs_track_registry]
	mov word ptr cs:[di + _cs_voice_track_table], ax
	mov ax, word ptr cs:[bx + _cs_track_registry + 2]
	mov word ptr cs:[di + _cs_voice_track_table + 2], ax
loc_18fc:
	add di, 04h
	inc si
	cmp si, 10h
	jnz loc_18c6
	dec byte ptr [_cs_pause_refcount]
	pop es
	pop bp
	pop si
	pop di
	pop dx
	pop cx
	pop bx
	pop ax
	retn
_midi_recompute_active_voices endp

; ==============================================================
; midi_task_tick_one_slot  off 0x1913  size 192
;
;   The fade/ramp step (the "task scheduler" face of a track record). Once per
;   tick for a track with a fade armed: decrement the +0x162 countdown; on
;   expiry reload it from the +0x161 period and step the track master volume
;   +0x15e one increment toward the target +0x160 (clamped by the step size
;   +0x163), re-scaling every active voice via midi_apply_velocity_change_to_
;   active. When the target is reached, clears the fade and -- if the "release
;   on completion" bit (+0x160 & 0x80) is set -- releases the track and marks
;   voices dirty (this is the "fade out then auto-stop" used for transitions).
; ==============================================================
	public _midi_task_tick_one_slot
_midi_task_tick_one_slot proc near
	push bx
	push cx
	cmp byte ptr es:[bx+0162h], 00h
	jz loc_1925
	dec byte ptr es:[bx+0162h]
	jmp loc_19d0
loc_1925:
	mov cl, byte ptr es:[bx+0161h]
	mov byte ptr es:[bx+0162h], cl
	mov cl, byte ptr es:[bx+0160h]
	and cl, 7fh
	cmp cl, byte ptr es:[bx+015eh]
	jz loc_19ac
	ja loc_1976
	mov cl, byte ptr es:[bx+015eh]
	mov ch, byte ptr es:[bx+0160h]
	and ch, 7fh
	sub cl, ch
	cmp cl, byte ptr es:[bx+0163h]
	ja loc_1965
	mov cl, byte ptr es:[bx+0160h]
	and cl, 7fh
	mov ch, 01h
	call _midi_apply_vel_change_active
	jmp loc_19ac
loc_1965:
	mov cl, byte ptr es:[bx+015eh]
	sub cl, byte ptr es:[bx+0163h]
	mov ch, 01h
	call _midi_apply_vel_change_active
	jmp loc_19d0
loc_1976:
	mov cl, byte ptr es:[bx+0160h]
	and cl, 7fh
	mov ch, byte ptr es:[bx+015eh]
	sub cl, ch
	cmp cl, byte ptr es:[bx+0163h]
	ja loc_199b
	mov cl, byte ptr es:[bx+0160h]
	and cl, 7fh
	mov ch, 01h
	call _midi_apply_vel_change_active
	jmp loc_19ac
loc_199b:
	mov cl, byte ptr es:[bx+015eh]
	add cl, byte ptr es:[bx+0163h]
	mov ch, 01h
	call _midi_apply_vel_change_active
	jmp loc_19d0
loc_19ac:
	mov byte ptr es:[bx+0158h], 0feh
	mov byte ptr es:[bx+0163h], 00h
	mov cl, byte ptr es:[bx+0160h]
	and cl, 80h
	cmp cl, 00h
	jz loc_19d0
	mov ax, bx
	call _midi_track_release
	mov byte ptr [_cs_pause_refcount + 11], 01h
loc_19d0:
	pop cx
	pop bx
	retn
_midi_task_tick_one_slot endp

; ==============================================================
; midi_apply_vel_change_active  off 0x19d3  size 221
;
;   Re-applies a new track master volume (CL) to every voice currently sounding
;   for this track, by re-running each voice's channel volume (+0x107) through
;   midi_scale_velocity against the new master. CH selects the mode: CH!=0 just
;   queues the new value in the pending-action band (+0x382) for the scheduler
;   to flush later; CH==0 sends it to the driver (BP=7) immediately. No-op if
;   the master is unchanged. Walks both the voice-owner table (0x2e2) and the
;   channel-kind array (+0x8c) so drum and melodic voices both update.
; ==============================================================
	public _midi_apply_vel_change_active
_midi_apply_vel_change_active proc near
	push ax
	push bx
	push cx
	push dx
	push si
	push di
	mov byte ptr [_cs_pause_refcount + 12], ch
	cmp cl, byte ptr es:[bx+015eh]
	jnz loc_19e8
	jmp loc_1aa9
loc_19e8:
	mov byte ptr es:[bx+015eh], cl
	cmp si, 0ffh
	jnz loc_19f6
	jmp loc_1aa9
loc_19f6:
	mov dx, si
	shl dl, 01h
	shl dl, 01h
	xor si, si
loc_19fe:
	mov cl, byte ptr cs:[si + _cs_voice_ch_table]
	cmp cl, 0ffh
	jz loc_1a4b
	mov ch, cl
	and cl, 0f0h
	cmp cl, dl
	jnz loc_1a4b
	mov cl, ch
	db 081h, 0e1h
	dw 0000fh   ; and CX,0xf (imm16 forced)
	mov di, cx
	mov cl, byte ptr es:[bx+di+0107h]
	push dx
	mov dl, byte ptr es:[bx+015eh]
	call _midi_scale_velocity
	cmp byte ptr [_cs_pause_refcount + 12], 00h
	jz loc_1a36
	mov byte ptr cs:[si + _cs_voice_refresh], cl
	jmp loc_1a4a
loc_1a36:
	mov ch, 07h
	mov ax, si
	mov byte ptr cs:[si + _cs_voice_refresh], 0ffh
	push bp
	mov bp, 07h
	call dword ptr [_cs_drvvec]
	pop bp
loc_1a4a:
	pop dx
loc_1a4b:
	inc si
	cmp si, 10h
	jnz loc_19fe
	xor ch, ch
	xor si, si
loc_1a55:
	mov cl, byte ptr es:[bx+si+8ch]
	cmp cl, 0ffh
	jz loc_1aa9
	mov di, cx
	test byte ptr es:[bx+di+0134h], 02h
	jz loc_1aa3
	cmp byte ptr cs:[di + _cs_voice_ch_table], 0ffh
	jnz loc_1aa3
	mov al, cl
	mov cl, byte ptr es:[bx+di+0107h]
	mov dl, byte ptr es:[bx+015eh]
	call _midi_scale_velocity
	cmp byte ptr [_cs_pause_refcount + 12], 00h
	jz loc_1a8f
	mov byte ptr cs:[di + _cs_voice_refresh], cl
	jmp loc_1aa3
loc_1a8f:
	mov ch, 07h
	mov ax, di
	mov byte ptr cs:[di + _cs_voice_refresh], 0ffh
	push bp
	mov bp, 07h
	call dword ptr [_cs_drvvec]
	pop bp
loc_1aa3:
	inc si
	cmp si, 10h
	jnz loc_1a55
loc_1aa9:
	pop di
	pop si
	pop dx
	pop cx
	pop bx
	pop ax
	retn
_midi_apply_vel_change_active endp

; ==============================================================
; midi_task_scheduler_advance  off 0x1ab0  size 72
;
;   Drains the per-voice pending-action queue (+0x382). Starting from a saved
;   round-robin cursor (+0x0d), it sends up to TWO queued voice updates to the
;   driver (BP=7) per tick, clearing each as it goes, then saves the new cursor.
;   The 2-per-tick throttle spreads driver traffic out so a big re-key doesn't
;   stall one tick.
; ==============================================================
	public _midi_task_scheduler_advance
_midi_task_scheduler_advance proc near
	xor bl, bl
	mov al, byte ptr [_cs_pause_refcount + 13]
	xor ah, ah
	mov si, ax
loc_1aba:
	mov cl, byte ptr cs:[si + _cs_voice_refresh]
	cmp cl, 0ffh
	jz loc_1adf
	mov byte ptr cs:[si + _cs_voice_refresh], 0ffh
	mov ch, 07h
	mov ax, si
	push bp
	mov bp, 07h
	call dword ptr [_cs_drvvec]
	pop bp
	inc bl
	cmp bl, 02h
	jz loc_1af1
loc_1adf:
	inc si
	cmp si, 10h
	jnz loc_1ae7
	xor si, si
loc_1ae7:
	mov al, byte ptr [_cs_pause_refcount + 13]
	xor ah, ah
	cmp si, ax
	jnz loc_1aba
loc_1af1:
	mov ax, si
	mov byte ptr [_cs_pause_refcount + 13], al
	retn
_midi_task_scheduler_advance endp

; ==============================================================
; midi_task_scheduler_tick  off 0x1af8  size 132
;
;   The per-tick pump -- the top of the sequencer's clock. (Normal playback
;   reaches it via the IRQ-0 timer callback; the only direct callers are the
;   teardown-drain path in audio_release_stream_buffers.) It:
;     1. Bails if the master lock (_cs_pause_refcount +0) is held.
;     2. If voices are dirty (+0x0b), recomputes voices first.
;     3. Walks the 0x1c2 registry; per active, non-held track: run the fade step
;        (task_tick_one_slot) if a fade is armed, then advance the track --
;        midi_tick for a MIDI track, or midi_track_verify_or_release for an SFX
;        track. (The si-=4 backstep handles a track that released mid-walk so the
;        next slot, shifted down by the compaction, isn't skipped.)
;     4. Pump the streaming-SFX list (midi_track_tick_loop_16channel), drain the
;        pending-action queue (task_scheduler_advance), and give the driver its
;        per-tick service call (BP=3).
;   Interrupt-safe (PUSHF/CLI..POPF).
; ==============================================================
	public _midi_task_scheduler_tick
_midi_task_scheduler_tick proc near
	cmp byte ptr [_cs_pause_refcount], 00h
	jz loc_1b01
	retf
loc_1b01:
	pushf
	cli
	push si
	push di
	push es
	push ds
	push bp
	cmp byte ptr [_cs_pause_refcount + 11], 00h
	jz loc_1b13
	call _midi_recompute_active_voices
loc_1b13:
	xor si, si
	xor di, di
loc_1b17:
	les bx, dword ptr cs:[si + _cs_track_registry]
	mov ax, es
	or ax, bx
	jz loc_1b65
	cmp byte ptr es:[bx+0164h], 00h
	jnz loc_1b5a
	cmp byte ptr es:[bx+0163h], 00h
	jz loc_1b42
	call _midi_task_tick_one_slot
	cmp byte ptr es:[bx+0158h], 0ffh
	jnz loc_1b42
	sub si, 04h
	jmp loc_1b5a
loc_1b42:
	cmp byte ptr es:[bx+0165h], 00h
	jz loc_1b4f
	call _midi_track_verify_or_release
	jmp loc_1b52
loc_1b4f:
	call _midi_tick
loc_1b52:
	cmp byte ptr es:[bx+0158h], 0ffh
	jz loc_1b5d
loc_1b5a:
	add si, 04h
loc_1b5d:
	add di, 04h
	cmp si, 40h
	jnz loc_1b17
loc_1b65:
	call _midi_track_tick_loop_16channel
	call _midi_task_scheduler_advance
	push bp
	mov bp, 03h
	call dword ptr [_cs_drvvec]
	pop bp
	pop bp
	pop ds
	pop es
	pop di
	pop si
	popf
	retf
_midi_task_scheduler_tick endp

; ==============================================================
; midi_track_verify_or_release  off 0x1b7c  size 44
;
;   The SFX-track tick guard. Confirms a streaming-SFX track (BX:ES) is still
;   present in the streaming registry (0x202); if it has vanished, releases it
;   and marks voices dirty. (For real MIDI tracks the scheduler calls midi_tick
;   instead of this.)
; ==============================================================
	public _midi_track_verify_or_release
_midi_track_verify_or_release proc near
	push cx
	push si
	push ax
	mov cx, es
	xor si, si
loc_1b83:
	cmp word ptr cs:[si + _cs_pending_track], bx
	jnz loc_1b91
	cmp word ptr cs:[si + _cs_pending_track + 2], cx
	jz loc_1ba4
loc_1b91:
	add si, 04h
	cmp si, 40h
	jnz loc_1b83
	mov ax, bx
	call _midi_track_release
	mov byte ptr [_cs_pause_refcount + 11], 01h
loc_1ba4:
	pop ax
	pop si
	pop cx
	retn
_midi_track_verify_or_release endp

; ==============================================================
; midi_track_tick_loop_16channel  off 0x1ba8  size 202
;
;   The streaming-SFX pump: a second tick loop over the 0x202 registry (the
;   streamed-sample tracks). For each, it bumps the clock, walks into the
;   script, and calls _snddrv_dispatch_cached (selector 3 to feed the stream, 4
;   to poll it). A nonzero high byte of the poll result resets the clock; a
;   nonzero low byte means the sound finished -> release + voices dirty. This is
;   how one-shot streamed SFX coexist with the looping music tracks.
; ==============================================================
	public _midi_track_tick_loop_16channel
_midi_track_tick_loop_16channel proc near
	push ds
	xor si, si
loc_1bab:
	les bx, dword ptr cs:[si + _cs_pending_track]
	mov cx, es
	cmp cx, 00h
	jnz loc_1bbf
	cmp bx, 00h
	jnz loc_1bbf
	jmp loc_1c70
loc_1bbf:
	inc word ptr es:[bx+0154h]
	lds bp, es:[bx+08h]
	lds bp, ds:[bp+00h]
	mov cl, byte ptr es:[bx+0165h]
	and cl, 0fh
	dec cl
	shl cl, 01h
	xor ch, ch
	push bp
	add bp, cx
	mov cx, word ptr ds:[bp+00h]
	pop bp
	add bp, cx
	mov ax, bp
	cmp byte ptr es:[bx+0165h], 10h
	ja loc_1c2a
	or byte ptr es:[bx+0165h], 80h
	push bx
	mov bx, ax
	inc bx
	cmp byte ptr [bx], 0feh
	jnz loc_1bfe
	inc bx
loc_1bfe:
	inc bx
	mov ax, word ptr [bx+02h]
	push ax
	push ds
	mov ax, bx
	add ax, 08h
	push ax
	mov ax, word ptr [bx]
	push ax
	mov cl, byte ptr es:[bx+015eh]
	mov ch, byte ptr es:[bx+015dh]
	push cx
	mov ax, sp
	push ax
	mov ax, 03h
	push ax
	call far ptr _snddrv_dispatch_cached
	add sp, 0eh
	pop bx
	jmp loc_1c65
loc_1c2a:
	mov ch, byte ptr es:[bx+015dh]
	mov cl, byte ptr es:[bx+015eh]
	push cx
	mov ax, sp
	push ax
	mov ax, 04h
	push ax
	call far ptr _snddrv_dispatch_cached
	add sp, 06h
	cmp ah, 00h
	jz loc_1c50
	mov word ptr es:[bx+0154h], 00h
loc_1c50:
	cmp al, 00h
	jz loc_1c65
	mov byte ptr es:[bx+0165h], 00h
	mov ax, bx
	call _midi_track_release
	mov byte ptr [_cs_pause_refcount + 11], 01h
loc_1c65:
	add si, 04h
	cmp si, 40h
	jz loc_1c70
	jmp loc_1bab
loc_1c70:
	pop ds
	retn
_midi_track_tick_loop_16channel endp

; ==============================================================
; midi_tick  off 0x1c72  size 580
;
;   Advances ONE MIDI track (BX:ES) by one tick. Increments the track clock
;   (+0x154), then walks the 16 channels. For each channel:
;     - read the channel-kind byte +0x8c[ch]: 0xFF ends the walk, 0xFE skips.
;     - if the delta-time countdown +0x4c[ch] is nonzero, decrement it (handling
;       the 0x8000-biased extended-delay sentinel and the 0xF8 reload) and fire
;       no events this tick.
;     - if the countdown is zero, run the event loop: read the stream byte at
;       (script_base + table[ch] + cursor[ch]). A byte < 0x80 reuses the saved
;       RUNNING STATUS +0x9c[ch]; >= 0x80 is a new status byte. Dispatch by high
;       nibble to midi_note_off/on, poly-AT, CC, program, channel-press, pitch-
;       bend, or sysex/meta. 0xFC stops the channel; 0xF8 reloads an extended
;       delay; otherwise the trailing byte minus 1 becomes the new delta.
;   After all channels, a second pass checks for end-of-track: if every cursor
;   is 0 and no loop is armed -> release; else LOOP by restoring the saved
;   cursor/delta/running-status arrays and the saved clock.
;
;   DI on entry = this track's slot index (used to derive the channel base in
;   +8). Internal-only (RETN).
; ==============================================================
	public _midi_tick
_midi_tick proc near
	push si
	push di
	push bp
	push ax
	push bx
	push cx
	push dx
	push ds
	; Stash slot*4 (the voice-key base for this track) in +8 for the handlers.
	shl di, 01h
	shl di, 01h
	mov cx, di
	mov byte ptr [_cs_pause_refcount + 8], cl
	inc word ptr es:[bx+0154h]            ; tick the track clock
	; Load the script event-table base (double-indirect via +8) and cache it.
	lds bp, es:[bx+08h]
	lds bp, ds:[bp+00h]
	mov word ptr [_cs_cmd_slots + 12], bp
	xor si, si
loc_1c99:
	mov al, byte ptr es:[bx+si+8ch]
	cmp al, 0ffh
	jnz loc_1ca5
	jmp loc_1e43
loc_1ca5:
	cmp al, 0feh
	jnz loc_1cac
	jmp loc_1e3a
loc_1cac:
	mov byte ptr [_cs_pause_refcount + 4], 0ffh
	mov byte ptr [_cs_pause_refcount + 5], 00h
	push si
	mov si, ax
	and si, 0ffh
	test byte ptr es:[bx+si+0134h], 02h
	pop si
	jz loc_1cd4
	mov byte ptr [_cs_pause_refcount + 4], al
	mov byte ptr [_cs_pause_refcount + 5], 01h
	jmp loc_1cf5
loc_1cd4:
	and al, 0fh
	mov cl, al
	or cl, byte ptr [_cs_pause_refcount + 8]
	xor di, di
loc_1cdf:
	cmp byte ptr cs:[di + _cs_voice_ch_table], cl
	jz loc_1cee
	inc di
	cmp di, 10h
	jnz loc_1cdf
	jmp loc_1cf5
loc_1cee:
	mov dx, di
	mov byte ptr [_cs_pause_refcount + 4], dl
loc_1cf5:
	mov bp, word ptr [_cs_cmd_slots + 12]
	shl si, 01h
	mov dx, word ptr ds:[bp+si]
	add bp, dx
	add bp, word ptr es:[bx+si+0ch]
	cmp word ptr es:[bx+si+0ch], 00h
	jnz loc_1d11
	shr si, 01h
	jmp loc_1e3a
loc_1d11:
	shr si, 01h
	shl si, 01h
	cmp word ptr es:[bx+si+4ch], 00h
	jz loc_1d4d
	dec word ptr es:[bx+si+4ch]
	cmp word ptr es:[bx+si+4ch], 8000h
	jnz loc_1d48
	xor dh, dh
	shr si, 01h
	mov dl, byte ptr ds:[bp+00h]
	inc bp
	shl si, 01h
	inc word ptr es:[bx+si+0ch]
	shr si, 01h
	shl si, 01h
	cmp dl, 0f8h
	jnz loc_1d44
	mov dl, 0f0h
	mov dh, 80h
loc_1d44:
	mov word ptr es:[bx+si+4ch], dx
loc_1d48:
	shr si, 01h
	jmp loc_1e3a
loc_1d4d:
	shr si, 01h
loc_1d4f:
	mov dl, byte ptr ds:[bp+00h]
	inc bp
	shl si, 01h
	inc word ptr es:[bx+si+0ch]
	shr si, 01h
	cmp dl, 80h
	jc loc_1d68
	mov byte ptr es:[bx+si+9ch], dl
	jmp loc_1d76
loc_1d68:
	mov dl, byte ptr es:[bx+si+9ch]
	dec bp
	shl si, 01h
	dec word ptr es:[bx+si+0ch]
	shr si, 01h
loc_1d76:
	mov al, dl
	mov ah, al
	and ah, 0f0h
	and al, 0fh
	cmp dl, 0fch
	jnz loc_1d91
	shl si, 01h
	mov word ptr es:[bx+si+0ch], 00h
	shr si, 01h
	jmp loc_1e3a
loc_1d91:
	cmp al, 0fh
	jnz loc_1da8
	call _midi_dispatch_meta_or_control
	shl si, 01h
	mov dx, word ptr es:[bx+si+0ch]
	shr si, 01h
	cmp dx, 00h
	jnz loc_1e08
	jmp loc_1e3a
loc_1da8:
	; Dispatch a channel-voice event by status high nibble (AH = status & 0xf0).
	mov al, byte ptr [_cs_pause_refcount + 4]
	cmp ah, 80h
	jnz loc_1db6
	call _midi_note_off
	jmp loc_1e08
loc_1db6:
	cmp ah, 90h
	jnz loc_1dc0
	call _midi_note_on
	jmp loc_1e08
loc_1dc0:
	cmp ah, 0a0h
	jnz loc_1dca
	call _midi_poly_aftertouch
	jmp loc_1e08
loc_1dca:
	cmp ah, 0b0h
	jnz loc_1dd4
	call _midi_apply_ctrl_change_per_tick
	jmp loc_1e08
loc_1dd4:
	cmp ah, 0c0h
	jnz loc_1dde
	call _midi_program_change
	jmp loc_1e08
loc_1dde:
	cmp ah, 0d0h
	jnz loc_1de8
	call _midi_track_advance_event
	jmp loc_1e08
loc_1de8:
	cmp ah, 0e0h
	jnz loc_1df2
	call _midi_pitch_bend
	jmp loc_1e08
loc_1df2:
	cmp ah, 0f0h
	jnz loc_1dfc
	call _midi_dispatch_sysex
	jmp loc_1e08
loc_1dfc:
	shl si, 01h
	mov word ptr es:[bx+si+0ch], 00h
	shr si, 01h
	jmp loc_1e3a
loc_1e08:
	mov dl, byte ptr ds:[bp+00h]
	inc bp
	shl si, 01h
	inc word ptr es:[bx+si+0ch]
	shr si, 01h
	cmp dl, 00h
	jnz loc_1e1d
	jmp loc_1d4f
loc_1e1d:
	shl si, 01h
	cmp dl, 0f8h
	jnz loc_1e30
	mov dl, 0efh
	mov dh, 80h
	mov word ptr es:[bx+si+4ch], dx
	shr si, 01h
	jmp loc_1e3a
loc_1e30:
	xor dh, dh
	dec dl
	mov word ptr es:[bx+si+4ch], dx
	shr si, 01h
loc_1e3a:
	inc si
	cmp si, 10h
	jz loc_1e43
	jmp loc_1c99
loc_1e43:
	xor si, si
loc_1e45:
	cmp byte ptr es:[bx+si+8ch], 0ffh
	jz loc_1e5e
	shl si, 01h
	cmp word ptr es:[bx+si+0ch], 00h
	jnz loc_1ead
	shr si, 01h
	inc si
	cmp si, 10h
	jnz loc_1e45
loc_1e5e:
	cmp byte ptr es:[bx+015ah], 00h
	jnz loc_1e7b
	cmp byte ptr es:[bx+015dh], 00h
	jnz loc_1e7b
	mov ax, bx
	call _midi_track_release
	mov byte ptr [_cs_pause_refcount + 11], 01h
	jmp loc_1ead
loc_1e7b:
	; LOOP restart: restore the saved clock (+0x156 -> +0x154) and, for all 16
	; channels, copy the saved cursor/delta/running-status (+0x2c->+0xc,
	; +0x6c->+0x4c, +0xac->+0x9c) so the track replays from its cue point.
	mov dx, word ptr es:[bx+0156h]
	mov word ptr es:[bx+0154h], dx
	xor si, si
loc_1e87:
	mov dx, word ptr es:[bx+si+2ch]
	mov word ptr es:[bx+si+0ch], dx
	mov dx, word ptr es:[bx+si+6ch]
	mov word ptr es:[bx+si+4ch], dx
	shr si, 01h
	mov dl, byte ptr es:[bx+si+0ach]
	mov byte ptr es:[bx+si+9ch], dl
	shl si, 01h
	add si, 02h
	cmp si, 20h
	jnz loc_1e87
loc_1ead:
	pop ds
	pop dx
	pop cx
	pop bx
	pop ax
	pop bp
	pop di
	pop si
	retn
_midi_tick endp

; ==============================================================
; midi_note_off  off 0x1eb6  size 79
;
;   Status 0x8n handler. Reads note (CH) and velocity (CL) from the stream
;   (advancing the cursor), clears the channel's active-key slot (+0x125[ch]) if
;   it matches this note, and -- unless the channel is voice-suppressed or a seek
;   is in progress -- issues a driver note-off (BP=4). One of the per-tick event
;   handlers called by midi_tick; they all take BX:ES=record, BP=stream ptr,
;   SI=channel and return near.
; ==============================================================
	public _midi_note_off
_midi_note_off proc near
	push si
	; READ-STREAM-BYTE idiom (recurs in every event handler below): read the
	; byte at DS:BP into a register, advance the stream pointer (INC BP), and
	; bump THIS channel's event-cursor counter +0x0c[ch]. SI holds the channel
	; index; the SHL/SHR pair scales it by 2 because +0x0c is a word[16] array.
	; Here: CH = note number, CL = velocity.
	mov ch, byte ptr ds:[bp+00h]
	inc bp
	shl si, 01h
	inc word ptr es:[bx+si+0ch]
	shr si, 01h
	mov cl, byte ptr ds:[bp+00h]
	inc bp
	shl si, 01h
	inc word ptr es:[bx+si+0ch]
	shr si, 01h
	push ax
	mov al, byte ptr es:[bx+si+8ch]
	mov si, ax
	db 081h, 0e6h
	dw 0000fh   ; and SI,0xf (imm16 forced)
	pop ax
	cmp byte ptr es:[bx+si+0125h], ch
	jnz loc_1eeb
	mov byte ptr es:[bx+si+0125h], 0ffh
loc_1eeb:
	cmp al, 0ffh
	jz loc_1f03
	cmp byte ptr [_cs_pause_refcount + 16], 00h
	jnz loc_1f03
	and al, 0fh
	push bp
	mov bp, 04h
	call dword ptr [_cs_drvvec]
	pop bp
loc_1f03:
	pop si
	retn
_midi_note_off endp

; ==============================================================
; midi_note_on  off 0x1f05  size 115
;
;   Status 0x9n handler. Reads note (CH) and velocity (CL). Velocity != 0 stores
;   the key in +0x125[ch] and fires a driver note-on (BP=5). Velocity == 0 is the
;   standard MIDI "note-on as note-off": clears the key slot and fires note-off
;   (BP=4). Suppressed during seek or when the channel owns no voice.
; ==============================================================
	public _midi_note_on
_midi_note_on proc near
	push si
	mov ch, byte ptr ds:[bp+00h]
	inc bp
	shl si, 01h
	inc word ptr es:[bx+si+0ch]
	shr si, 01h
	mov cl, byte ptr ds:[bp+00h]
	inc bp
	shl si, 01h
	inc word ptr es:[bx+si+0ch]
	shr si, 01h
	push ax
	mov al, byte ptr es:[bx+si+8ch]
	mov si, ax
	db 081h, 0e6h
	dw 0000fh   ; and SI,0xf (imm16 forced)
	pop ax
	cmp cl, 00h
	jz loc_1f51
	mov byte ptr es:[bx+si+0125h], ch
	cmp al, 0ffh
	jz loc_1f76
	cmp byte ptr [_cs_pause_refcount + 16], 00h
	jnz loc_1f76
	and al, 0fh
	push bp
	mov bp, 05h
	call dword ptr [_cs_drvvec]
	pop bp
	jmp loc_1f76
loc_1f51:
	cmp byte ptr es:[bx+si+0125h], ch
	jnz loc_1f5e
	mov byte ptr es:[bx+si+0125h], 0ffh
loc_1f5e:
	cmp al, 0ffh
	jz loc_1f76
	cmp byte ptr [_cs_pause_refcount + 16], 00h
	jnz loc_1f76
	and al, 0fh
	push bp
	mov bp, 04h
	call dword ptr [_cs_drvvec]
	pop bp
loc_1f76:
	pop si
	retn
_midi_note_on endp

; ==============================================================
; midi_poly_aftertouch  off 0x1f78  size 49
;
;   Status 0xAn handler. Reads note (CH) + pressure (CL) from the stream; keeps
;   no local state, just forwards to the driver (BP=6). Suppressed during seek.
; ==============================================================
	public _midi_poly_aftertouch
_midi_poly_aftertouch proc near
	mov ch, byte ptr ds:[bp+00h]
	inc bp
	shl si, 01h
	inc word ptr es:[bx+si+0ch]
	shr si, 01h
	mov cl, byte ptr ds:[bp+00h]
	inc bp
	shl si, 01h
	inc word ptr es:[bx+si+0ch]
	shr si, 01h
	cmp al, 0ffh
	jz loc_1fa8
	cmp byte ptr [_cs_pause_refcount + 16], 00h
	jnz loc_1fa8
	push bp
	mov bp, 06h
	call dword ptr [_cs_drvvec]
	pop bp
loc_1fa8:
	retn
_midi_poly_aftertouch endp

; ==============================================================
; midi_apply_ctrl_change_per_tick  off 0x1fa9  size 257
;
;   Status 0xBn handler (the per-tick controller-change path; the command-driven
;   twin is midi_apply_controller_change). Reads controller# (CH) + value (CL),
;   then per controller: 0x07 volume (re-scaled by master, queues a +0x382 voice
;   action), 0x0A pan -> +0xf8, 0x01 modulation -> +0xe9, 0x40 sustain -> bit15
;   of +0xbc, 0x4B (sound-ctrl-6) -> +0xda low nibble + voices-dirty, 0x4E
;   (sound-ctrl-9) -> +0x143 low bit + voices-dirty. The last two change voice
;   demand, hence the dirty flag. Then drives the hardware (BP=7) if not muted.
; ==============================================================
	public _midi_apply_ctrl_change_per_tick
_midi_apply_ctrl_change_per_tick proc near
	push si
	mov ch, byte ptr ds:[bp+00h]
	inc bp
	shl si, 01h
	inc word ptr es:[bx+si+0ch]
	shr si, 01h
	mov cl, byte ptr ds:[bp+00h]
	inc bp
	shl si, 01h
	inc word ptr es:[bx+si+0ch]
	shr si, 01h
	test byte ptr [_cs_pause_refcount + 5], 0ffh
	jz loc_1fdf
	push si
	mov si, ax
	db 081h, 0e6h
	dw 0000fh   ; and SI,0xf (imm16 forced)
	cmp byte ptr cs:[si + _cs_voice_ch_table], 0ffh
	pop si
	jz loc_1fdf
	jmp loc_20a8
loc_1fdf:
	push ax
	mov al, byte ptr es:[bx+si+8ch]
	mov si, ax
	db 081h, 0e6h
	dw 0000fh   ; and SI,0xf (imm16 forced)
	pop ax
	cmp ch, 07h
	jnz loc_2015
	mov byte ptr es:[bx+si+0107h], cl
	mov dl, byte ptr es:[bx+015eh]
	call _midi_scale_velocity
	cmp al, 20h
	jc loc_2005
	jmp loc_20a8
loc_2005:
	push si
	mov si, ax
	and si, 0ffh
	mov byte ptr cs:[si + _cs_voice_refresh], 0ffh
	pop si
	jmp loc_2090
loc_2015:
	cmp ch, 0ah
	jnz loc_2021
	mov byte ptr es:[bx+si+0f8h], cl
	jmp loc_2090
loc_2021:
	cmp ch, 01h
	jnz loc_202d
	mov byte ptr es:[bx+si+0e9h], cl
	jmp loc_2090
loc_202d:
	cmp ch, 40h
	jnz loc_204f
	push dx
	shl si, 01h
	mov dx, word ptr es:[bx+si+0bch]
	or dh, 80h
	cmp cl, 00h
	jnz loc_2045
	and dh, 7fh
loc_2045:
	mov word ptr es:[bx+si+0bch], dx
	shr si, 01h
	pop dx
	jmp loc_2090
loc_204f:
	cmp ch, 4bh
	jnz loc_206d
	push cx
	mov ch, byte ptr es:[bx+si+0dah]
	and ch, 0f0h
	or ch, cl
	mov byte ptr es:[bx+si+0dah], ch
	pop cx
	mov byte ptr [_cs_pause_refcount + 11], 01h
	jmp loc_2090
loc_206d:
	cmp ch, 4eh
	jnz loc_2090
	push cx
	mov ch, byte ptr es:[bx+si+0143h]
	and ch, 0f0h
	test cl, 0ffh
	jz loc_2082
	mov cl, 01h
loc_2082:
	or ch, cl
	mov byte ptr es:[bx+si+0143h], ch
	pop cx
	mov byte ptr [_cs_pause_refcount + 11], 01h
loc_2090:
	cmp al, 0ffh
	jnc loc_20a8
	cmp byte ptr [_cs_pause_refcount + 16], 00h
	jnz loc_20a8
	and al, 0fh
	push bp
	mov bp, 07h
	call dword ptr [_cs_drvvec]
	pop bp
loc_20a8:
	pop si
	retn
_midi_apply_ctrl_change_per_tick endp

; ==============================================================
; midi_program_change  off 0x20aa  size 84
;
;   Status 0xCn handler. Reads the program number (CL), stores it in +0x116[ch],
;   and forwards a driver program-change (BP=8) unless suppressed.
; ==============================================================
	public _midi_program_change
_midi_program_change proc near
	push si
	mov cl, byte ptr ds:[bp+00h]
	inc bp
	shl si, 01h
	inc word ptr es:[bx+si+0ch]
	shr si, 01h
	test byte ptr [_cs_pause_refcount + 5], 0ffh
	jz loc_20d2
	push si
	mov si, ax
	db 081h, 0e6h
	dw 0000fh   ; and SI,0xf (imm16 forced)
	cmp byte ptr cs:[si + _cs_voice_ch_table], 0ffh
	pop si
	jz loc_20d2
	jmp loc_20fc
loc_20d2:
	push ax
	mov al, byte ptr es:[bx+si+8ch]
	mov si, ax
	db 081h, 0e6h
	dw 0000fh   ; and SI,0xf (imm16 forced)
	pop ax
	mov byte ptr es:[bx+si+0116h], cl
	cmp al, 0ffh
	jnc loc_20fc
	cmp byte ptr [_cs_pause_refcount + 16], 00h
	jnz loc_20fc
	and al, 0fh
	push bp
	mov bp, 08h
	call dword ptr [_cs_drvvec]
	pop bp
loc_20fc:
	pop si
	retn
_midi_program_change endp

; ==============================================================
; midi_track_advance_event  off 0x20fe  size 36
;
;   Status 0xDn (channel-pressure) handler. Reads its 1 data byte (CL), advances
;   the cursor, and forwards to the driver (BP=9) unless suppressed. (0xDn is
;   folded into this generic "read one byte + dispatch" routine.)
; ==============================================================
	public _midi_track_advance_event
_midi_track_advance_event proc near
	mov cl, byte ptr ds:[bp+00h]
	inc bp
	shl si, 01h
	inc word ptr es:[bx+si+0ch]
	shr si, 01h
	cmp al, 0ffh
	jnc loc_2121
	cmp byte ptr [_cs_pause_refcount + 16], 00h
	jnz loc_2121
	push bp
	mov bp, 09h
	call dword ptr [_cs_drvvec]
	pop bp
loc_2121:
	retn
_midi_track_advance_event endp

; ==============================================================
; midi_pitch_bend  off 0x2122  size 124
;
;   Status 0xEn handler. Reads the 14-bit bend (LSB=CH, MSB=CL), packs it into
;   +0xbc[ch] as (MSB>>1, LSB) while preserving the bit15 sustain-pedal latch,
;   and forwards to the driver (BP=0x0a) unless suppressed.
; ==============================================================
	public _midi_pitch_bend
_midi_pitch_bend proc near
	push si
	mov ch, byte ptr ds:[bp+00h]
	inc bp
	shl si, 01h
	inc word ptr es:[bx+si+0ch]
	shr si, 01h
	mov cl, byte ptr ds:[bp+00h]
	inc bp
	shl si, 01h
	inc word ptr es:[bx+si+0ch]
	shr si, 01h
	test byte ptr [_cs_pause_refcount + 5], 0ffh
	jz loc_2157
	push si
	mov si, ax
	db 081h, 0e6h
	dw 0000fh   ; and SI,0xf (imm16 forced)
	cmp byte ptr cs:[si + _cs_voice_ch_table], 0ffh
	pop si
	jz loc_2157
	jmp loc_219c
loc_2157:
	push ax
	mov al, byte ptr es:[bx+si+8ch]
	mov si, ax
	db 081h, 0e6h
	dw 0000fh   ; and SI,0xf (imm16 forced)
	pop ax
	push cx
	xchg ch, cl
	shr ch, 01h
	jnc loc_216e
	or cl, 80h
loc_216e:
	shl si, 01h
	cmp word ptr es:[bx+si+0bch], 8000h
	jc loc_217c
	or ch, 80h
loc_217c:
	mov word ptr es:[bx+si+0bch], cx
	shr si, 01h
	pop cx
	cmp al, 0ffh
	jnc loc_219c
	cmp byte ptr [_cs_pause_refcount + 16], 00h
	jnz loc_219c
	and al, 0fh
	push bp
	mov bp, 0ah
	call dword ptr [_cs_drvvec]
	pop bp
loc_219c:
	pop si
	retn
_midi_pitch_bend endp

; ==============================================================
; midi_dispatch_sysex  off 0x219e  size 4
;
;   Status 0xFn entry from midi_tick's nibble dispatch: a thin tail-call into
;   midi_consume_event_sysex_f0 (the stream-skip walker).
; ==============================================================
	public _midi_dispatch_sysex
_midi_dispatch_sysex proc near
	call _midi_consume_event_sysex_f0
	retn
_midi_dispatch_sysex endp

; ==============================================================
; midi_dispatch_meta_or_control  off 0x21a2  size 272
;
;   The "status byte was 0x0F" path (reached from midi_tick when the low nibble
;   is 0x0F, i.e. a meta/control event), dispatched on the running-status AH:
;     AH 0xC0: sub-code 0x7F = END-OF-TRACK / loop commit -- snapshots all 16
;              channels' cursor/delta/status into the save arrays and +0x154->
;              +0x156 (arming the loop), then rewinds; any other sub-code stores
;              a marker byte into +0x158.
;     AH 0xB0: 0x50 'P' = set loop value +0x15f (+ driver call); 0x60 '`' = bump
;              the marker/cue counter +0x152; 0x52 'R' = conditional rewind (zero
;              all 16 cursors if +0x15a == arg).
;     anything else -> midi_consume_event_sysex_f0 (skip).
; ==============================================================
	public _midi_dispatch_meta_or_control
_midi_dispatch_meta_or_control proc near
	cmp ah, 0c0h
	jz loc_21b5
	cmp ah, 0b0h
	jnz loc_21af
	jmp loc_2243
loc_21af:
	call _midi_consume_event_sysex_f0
	jmp loc_22b1
loc_21b5:
	mov ch, byte ptr ds:[bp+00h]
	inc bp
	shl si, 01h
	inc word ptr es:[bx+si+0ch]
	shr si, 01h
	cmp ch, 7fh
	jnz loc_2234
	push dx
	mov dl, byte ptr ds:[bp+00h]
	inc bp
	shl si, 01h
	inc word ptr es:[bx+si+0ch]
	shr si, 01h
	xor dh, dh
	cmp dl, 0f8h
	jnz loc_21e0
	mov dh, 80h
	mov dl, 0f0h
loc_21e0:
	shl si, 01h
	mov word ptr es:[bx+si+4ch], dx
	shr si, 01h
	pop dx
	mov byte ptr es:[bx+si+9ch], 0cfh
	push si
	push dx
	xor si, si
loc_21f3:
	shl si, 01h
	mov dx, word ptr es:[bx+si+0ch]
	mov word ptr es:[bx+si+2ch], dx
	mov dx, word ptr es:[bx+si+4ch]
	mov word ptr es:[bx+si+6ch], dx
	shr si, 01h
	mov dl, byte ptr es:[bx+si+9ch]
	mov byte ptr es:[bx+si+0ach], dl
	inc si
	cmp si, 10h
	jnz loc_21f3
	mov dx, word ptr es:[bx+0154h]
	mov word ptr es:[bx+0156h], dx
	pop dx
	pop si
	shl si, 01h
	dec word ptr es:[bx+si+0ch]
	dec bp
	mov word ptr es:[bx+si+4ch], 00h
	shr si, 01h
	jmp loc_22b1
loc_2234:
	cmp byte ptr [_cs_pause_refcount + 16], 00h
	jnz loc_22b1
	mov byte ptr es:[bx+0158h], ch
	jmp loc_22b1
loc_2243:
	mov ch, byte ptr ds:[bp+00h]
	inc bp
	shl si, 01h
	inc word ptr es:[bx+si+0ch]
	shr si, 01h
	mov cl, byte ptr ds:[bp+00h]
	inc bp
	shl si, 01h
	inc word ptr es:[bx+si+0ch]
	shr si, 01h
	cmp ch, 50h
	jnz loc_227f
	cmp cl, 7fh
	jnz loc_226c
	mov cl, byte ptr [_cs_pause_refcount + 9]
loc_226c:
	mov byte ptr es:[bx+015fh], cl
	push ax
	push bp
	mov bp, 0bh
	call dword ptr [_cs_drvvec]
	pop bp
	pop ax
	jmp loc_22b1
loc_227f:
	cmp ch, 60h
	jnz loc_2293
	cmp byte ptr [_cs_pause_refcount + 16], 00h
	jnz loc_22b1
	inc word ptr es:[bx+0152h]
	jmp loc_22b1
loc_2293:
	cmp ch, 52h
	jnz loc_22b1
	cmp byte ptr es:[bx+015ah], cl
	jnz loc_22b1
	push si
	xor si, si
loc_22a2:
	mov word ptr es:[bx+si+0ch], 00h
	add si, 02h
	cmp si, 20h
	jnz loc_22a2
	pop si
loc_22b1:
	retn
_midi_dispatch_meta_or_control endp

; ==============================================================
; midi_consume_event_sysex_f0  off 0x22b2  size 61
;
;   SysEx / unknown-event stream skipper. For 0xF0 (SysEx start), consume bytes
;   until 0xF7 (EOX), bumping the cursor each byte. For 0xC0/0xD0 consume 1 data
;   byte, otherwise 2. Pure cursor-advance -- the game never acts on SysEx
;   payloads, it just steps past them.
; ==============================================================
	public _midi_consume_event_sysex_f0
_midi_consume_event_sysex_f0 proc near
	cmp ah, 0f0h
	jnz loc_22ca
loc_22b7:
	mov ch, byte ptr ds:[bp+00h]
	inc bp
	shl si, 01h
	inc word ptr es:[bx+si+0ch]
	shr si, 01h
	cmp ch, 0f7h
	jnz loc_22b7
	retn
loc_22ca:
	cmp ah, 0c0h
	jz loc_22e1
	cmp ah, 0d0h
	jz loc_22e1
	mov ch, byte ptr ds:[bp+00h]
	inc bp
	shl si, 01h
	inc word ptr es:[bx+si+0ch]
	shr si, 01h
loc_22e1:
	mov ch, byte ptr ds:[bp+00h]
	inc bp
	shl si, 01h
	inc word ptr es:[bx+si+0ch]
	shr si, 01h
	retn
_midi_consume_event_sysex_f0 endp

; ==============================================================
; midi_scale_velocity  off 0x22ef  size 24
;
;   Scales a channel volume by the track master volume: CL_out = clamp(((CL+1) *
;   (DL+1)) >> 7, 1..). It is an (a+1)*(b+1)/128 product with the result biased
;   down by 1 (so a nonzero product never reads as silence). CL = channel volume
;   in, DL = master volume; result back in CL. Used everywhere a voice's
;   effective loudness is computed.
; ==============================================================
	public _midi_scale_velocity
_midi_scale_velocity proc near
	push ax
	mov al, cl
	xor ah, ah
	inc al                              ; (CL+1)
	inc dl                              ; (DL+1)
	mul dl                              ; AX = (CL+1)*(DL+1)
	shl ah, 01h                         ; AH = product >> 7 (high byte * 2)
	mov cl, ah
	cmp cl, 00h
	jz loc_2305
	dec cl                              ; bias down by 1, but keep >= 0
loc_2305:
	pop ax
	retn
_midi_scale_velocity endp

; ==============================================================
; midi_lookup_track_state  off 0x2307  size 34
;
;   Resolves a track far-ptr handle (BX:ES) back to its registry slot index.
;   Linear scan of the 0x1c2 registry; returns SI = index*4 (0,4,8,..,0x3c) on a
;   hit, or the sentinel SI=0xFF if the handle is not registered. Every per-
;   channel command handler calls this first to turn a handle into a slot.
; ==============================================================
	public _midi_lookup_track_state
_midi_lookup_track_state proc near
	push cx
	mov cx, es
	xor si, si
loc_230c:
	cmp word ptr cs:[si + _cs_track_registry], bx      ; match offset half of the far-ptr key
	jnz loc_231c
	cmp word ptr cs:[si + _cs_track_registry + 2], cx      ; ...and the segment half
	jnz loc_231c
	jmp loc_2327
loc_231c:
	add si, 04h
	cmp si, 40h
	jnz loc_230c
	mov si, 0ffh                        ; not found
loc_2327:
	pop cx
	retn
_midi_lookup_track_state endp

; ==============================================================
; midi_track_parse_program_table  off 0x2329  size 218
;
;   Flattens the script's per-channel program table into the script header,
;   once per track-init. Walks the script looking for the row whose id matches
;   the default channel (+3); copies that row's 16 program words into the
;   _cs_prog_scratch buffer, then writes them back into the header followed by
;   the program-table id (+0x13). A 0xFC/0xFD/0xFE 3-byte signature at +0x21..23
;   marks the header as already-parsed, so the work is skipped on replays.
;   Returns the record ptr unchanged in AX.
; ==============================================================
	public _midi_track_parse_program_table
_midi_track_parse_program_table proc near
	push bx
	push cx
	push dx
	push bp
	push ds
	; Bail if the script pointer (+8) is the -1/-1 "no script" sentinel.
	mov bx, ax
	cmp word ptr es:[bx+08h], -01h
	jnz loc_2341
	cmp word ptr es:[bx+0ah], -01h
	jnz loc_2341
	jmp loc_23fd
loc_2341:
	lds bp, es:[bx+08h]
	lds bp, ds:[bp+00h]
	cmp byte ptr ds:[bp+23h], 0feh
	jnz loc_2361
	cmp byte ptr ds:[bp+22h], 0fdh
	jnz loc_2361
	cmp byte ptr ds:[bp+21h], 0fch
	jnz loc_2361
	jmp loc_23fd
loc_2361:
	push bp
	mov si, 20h
loc_2365:
	sub si, 02h
	mov word ptr cs:[si + _cs_prog_scratch], 00h
	cmp si, 00h
	jnz loc_2365
	mov byte ptr [_cs_pause_refcount + 19], 0ffh
	cmp byte ptr ds:[bp+00h], 0f0h
	jnz loc_238d
	mov cl, byte ptr ds:[bp+01h]
	mov byte ptr [_cs_pause_refcount + 19], cl
	add bp, 08h
loc_238d:
	mov cl, byte ptr ds:[bp+00h]
	cmp cl, byte ptr [_cs_pause_refcount + 3]
	jz loc_23af
	cmp cl, 0ffh
	jz loc_23cc
	inc bp
loc_239e:
	mov cl, byte ptr ds:[bp+00h]
	inc bp
	cmp cl, 0ffh
	jnz loc_23aa
	jmp loc_238d
loc_23aa:
	add bp, 05h
	jmp loc_239e
loc_23af:
	inc bp
loc_23b0:
	mov cl, byte ptr ds:[bp+00h]
	inc bp
	cmp cl, 0ffh
	jz loc_23cc
	inc bp
	mov cx, word ptr ds:[bp+00h]
	add bp, 04h
	mov word ptr cs:[si + _cs_prog_scratch], cx
	add si, 02h
	jmp loc_23b0
loc_23cc:
	pop bp
	push bp
	xor si, si
loc_23d0:
	mov cx, word ptr cs:[si + _cs_prog_scratch]
	mov word ptr ds:[bp+00h], cx
	add si, 02h
	add bp, 02h
	cmp si, 20h
	jnz loc_23d0
	mov cl, byte ptr [_cs_pause_refcount + 19]
	mov byte ptr ds:[bp+00h], cl
	pop bp
	mov byte ptr ds:[bp+21h], 0fch
	mov byte ptr ds:[bp+22h], 0fdh
	mov byte ptr ds:[bp+23h], 0feh
loc_23fd:
	pop ds
	pop bp
	pop dx
	pop cx
	pop bx
	retn
_midi_track_parse_program_table endp

; ==============================================================
; The module ends here, at the tail of _midi_track_parse_program_table. The
; bytes that follow in KRONDOR.EXE (a PUSH BP / MOV BP,SP / far-entry prologue)
; are the HEAD of the NEXT segment's first function (sfx_event_call_32c8_0063,
; segment 3508) — they do not belong to this TU, so this module does not emit
; them.
; ==============================================================

S32c8_TEXT	ends
	end