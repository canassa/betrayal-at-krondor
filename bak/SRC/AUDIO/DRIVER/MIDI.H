#ifndef BAK_MIDI_H
#define BAK_MIDI_H

#include "structs.h"

extern ushort midi_stub_return_cx_via_nop_alt(void far *ptr);
extern void midi_chord_event_thunk_0b6e(void far *ptr, int note);
extern int midi_stub_return_cx_via_nop(void far *ptr);
extern void midi_seek_volume_preserve_thunk(void far *midi_state);
extern void midi_cmd6_far_wrapper(ushort voice_count);
extern void midi_event_callback_thunk_0a8b(void far *ptr, int count);
extern uchar midi_driver_install_dispatch(uint offset, uint seg);
extern ushort midi_cmd1_save_cx_303b4_thunk(void far *ptr);
extern void midi_track_init_thunk(AudioTrackHandle far *handle, int start_flag);
extern void midi_fade_queue_handle(AudioTrackHandle far *handle, int target, int step, int dir);
extern void midi_cmd4_far_wrapper(int a);
extern void midi_track_apply_intensity(void far *track, int intensity);
extern void midi_track_set_word_bc_far(void far *ptr, int word_val, int byte_val);
extern void midi_active_release_thunk(AudioTrackHandle far *ptr);
extern void midi_track_set_byte_15a(void far *track_ptr, int nValue);
extern uchar midi_track_read_byte_158_far(void far *ptr);
extern void midi_set_note_velocity_thunk(int velocity);
extern void midi_apply_ctrl_change_thunk(void far *state, int ctrl_num, int value, int channel);
extern void midi_init_thunk_0678(void);
extern void midi_pitch_bend_step_far_thunk(void far *midi_obj, int direction);
extern void midi_queue_command(char kind, ushort arg2, ushort arg3, ushort slot0, ushort slot1,
                               ushort slot2, ushort slot3, ushort slot4, ushort slot5);
extern int near midi_dispatch_command(int cmd);
extern void midi_cmd0_program_change(void);
extern ushort midi_cmd1_save_cx_303b4(void);
extern void midi_cmd2_driver_dispatch_pair(void);
extern void midi_scheduler_pause_refcount(ushort flag);
extern void midi_cmd4_call_driver_13000(void);
extern int midi_seek_with_volume_preserve(void);
extern void midi_call_dispatch_cmd_13000(void);
extern ushort midi_cmd7_set_global_clamped(void);
extern void midi_track_init(void);
extern void midi_cmd9_release_and_recompute(void);
extern int midi_cmd0a_adjust_hold_count(void);
extern void midi_fade_program(void);
extern void midi_track_write_byte_15a_inner(void);
extern int midi_pitch_bend_step(ushort base_off, ushort direction);
extern void midi_cmd0e_apply_vel_track(void);
extern void midi_chord_propagate_setting(int track_near, uchar setting_UNUSED);
extern uchar midi_track_read_byte_158_inner(void);
extern uchar midi_sound_slot_unlock(ushort offset, ushort seg);
extern void midi_stub_nop(void);
extern ushort midi_stub_return_ax(void);
extern void midi_cmd13_voice_release(void);
extern void midi_cmd14_voice_set_value(void);
extern void midi_apply_controller_change();
extern void midi_cmd16_voice_set_state(void);
extern int midi_track_set_word_bc(void);
extern void near midi_track_release(void);
extern void near midi_recompute_active_voices(void);
extern void near midi_task_tick_one_slot(void);
extern void near midi_apply_vel_change_active(void);
extern void near midi_task_scheduler_advance(void);
extern void midi_task_scheduler_tick(void);
extern void near midi_track_verify_or_release(void);
extern void near midi_track_tick_loop_16channel(void);
extern void near midi_tick(void);
extern void near midi_note_off();
extern void near midi_note_on(void);
extern void near midi_poly_aftertouch(void);
extern void near midi_apply_ctrl_change_per_tick(void);
extern void near midi_program_change();
extern void near midi_track_advance_event(void);
extern void near midi_pitch_bend();
extern void near midi_dispatch_sysex(void);
extern void near midi_dispatch_meta_or_control();
extern void near midi_consume_event_sysex_f0();
extern uchar near midi_scale_velocity(uchar velocity, uchar volume);
extern ushort near midi_lookup_track_state(ushort match_off, ushort match_seg);
extern void *near midi_track_parse_program_table(void *track);

#endif
