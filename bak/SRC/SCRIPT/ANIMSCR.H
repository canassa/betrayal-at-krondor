#ifndef BAK_ANIMSCR_H
#define BAK_ANIMSCR_H

#include "structs.h"

extern int anim_script_subsystem_init(void);
extern void anim_script_close_all(void);
extern int anim_script_open(char *filename, int mode);
extern int anim_script_activate(int slot_plus_one);
extern void anim_script_close(int slot_plus_one);
extern int anim_script_tick(void);
extern void anim_script_rndr_all_objs(void);
extern int anim_script_channel_is_busy(int channel_id);
extern void anim_script_channel_start(int channel_id);
extern void anim_script_chan_request_pause(int channel_id);
extern void anim_script_channel_stop(int channel_id);
extern void anim_script_channel_pause_after(int channel_id);
extern void anim_script_start_all_channels(int channel_ref);
extern void anim_script_pause_all_channels(int script_object_id);
extern void anim_script_stop_all_channels(int script_object_id);
extern void anim_script_pause_all_chans(int script_object_id);
extern void anim_script_delete_all_channels(int script_object_id);
extern int anim_script_has_channel(int channel_id);
extern void anim_script_reset_all_objects(void);
extern ScriptAnimNode *anim_script_find_object(ushort wTag, ushort wIdB);
extern int far *anim_script_combat_resolve_loop(int far *script_pc);
extern int anim_script_find_channel(int channel_id);
extern ushort far *anim_script_channel_step(ushort far *script_pc);
extern ushort far *anim_script_dispatch_opcode(ushort far *script_pc);
extern int anim_script_iter_next_object(uint *out_id);
extern void anim_script_iter_first_object(uint *out_id);

#endif
