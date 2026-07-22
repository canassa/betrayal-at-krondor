#ifndef BAK_ITEMUSE_H
#define BAK_ITEMUSE_H

#include "structs.h"

extern int itemuse_dispatch_on_target(Actor far *param_1, ItemSlot far *param_2,
                                      ItemSlot far *param_3, int param_4);
extern void itemuse_apply_stat_effects(CombatActor *actor, ItemSlot far *item,
                                       ItemRecord far *record);
extern void itemuse_actor_spawn_clone_inv(Actor far *src_actor, uint kind, long world_x,
                                          long world_y);
extern void itemuse_ground_pile_open_inv(void);
extern void itemuse_party_tick_temporary(void);
extern void itemuse_view_look_south_modal(void);
extern void itemuse_cam_vert_raise_anim(long amplitude_z, int apex_hold_frames);

#endif
