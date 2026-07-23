#ifndef BAK_WORLDHIT_H
#define BAK_WORLDHIT_H

#include "structs.h"

extern short g_nPolygonTextureMode;
extern unsigned short g_nWorldRenderJitter;
extern char *g_pszCombatModalTitle;
extern BakFile *g_pSfxArchiveStream;
extern unsigned int _ovrbuffer;
extern unsigned char far *g_pMainScratchBuf;
#ifdef V102CD
extern char g_szVersionString[16];
#else
extern char g_szVersionString[13];
#endif
extern unsigned short g_wSkyColorR;
extern unsigned short g_wSkyColorG;
extern unsigned short g_wSkyColorB;
extern ImageRecord **g_pMapIconsTable;
extern unsigned char g_abActorAnimTemplateDefault[10];
extern unsigned char g_abActorAnimTemplateRanged[10];

extern void world_render_scene_dispatch(int animate);
extern void world_render_frame(int animate);
extern void world_render_sky_texture_load(void);
extern void world_render_sky_texture_free(void);
extern void world_render_frame_full(void);
extern void world_render_tick_objects(void);
extern void world_render_frame_with_hittest(void);
extern void world_rndr_apply_window_vport(void);
extern void world_render_actor_at_position(int actor_kind, int grid_x, int grid_y);
extern void world_render_actor_at_tile(int actor_id, int tile_x, int tile_y, int z, unsigned int yaw,
                                       CombatActor *override_actor);
extern void world_render_actor_swap_textures(int actor_id, int nGrid_x, int nGrid_y);
extern void world_render_with_overlay(void far *overlay_target);
extern void world_render_view(int force_overlay, int chapter_split);
extern int world_rndr_actor_angle_actor(CombatActor *from, CombatActor *to);
extern CombatActor *world_rndr_ranged_attack_anim(CombatActor *attacker, CombatActor *target,
                                                  int *p_hit_out, unsigned short action_id, int speed,
                                                  char anim_override);
extern void world_render_combat_grid_sprite(WorldObject *actor);
extern void world_render_record_marker_dot(WorldObject far *entry);

#endif
