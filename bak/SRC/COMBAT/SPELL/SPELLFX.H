#ifndef BAK_SPELLFX_H
#define BAK_SPELLFX_H

#include "structs.h"

extern void spellfx_cast_and_dispatch(void);
extern void spellfx_palette_fade_slot0(short caster_slot, short damage, int effect_param);
extern void spellfx_combat_play_hit_effect(short caster_slot, short damage, int effect_param);
extern void spellfx_overworld_pal_fade_slot2(short caster_slot, short damage, int effect_param);
extern void spellfx_combat_damage_flash_sfx(short param_1, short param_2, int param_3);
extern void spellfx_palette_event_with_sound(short param_1, short param_2, int param_3);
extern void spellfx_show_msg_pal_fade(short param_1, short param_2, int param_3);
extern void spellfx_save_then_cmap_recs(short target, short damage);
extern void spellfx_combat_roll_outcome(short param_1, short param_2);
extern void spellfx_save_cmap_scene_events(short target, short damage);
extern TimerEventEntry *spellfx_pal_event_timer_upsert(unsigned short param_1, long param_2);
extern void spellfx_pal_event_mask_upd(TimerEventEntry *entry);
extern int spellfx_event_mask_test_bit(int param_1);
extern short spellfx_actor_has_ration(WorldObject far *entry);
extern short spellfx_actor_has_special_item(WorldObject far *entry);
extern void spellfx_run_request_cmap_dialog(int request_type);
extern void spellfx_cast_bmp_load(void);
extern void spellfx_cast_bmp_free(void);
extern void spellfx_draw_events_caption(void);
extern void spellfx_party_member_take_damage(short roster_slot, short damage);

#endif
