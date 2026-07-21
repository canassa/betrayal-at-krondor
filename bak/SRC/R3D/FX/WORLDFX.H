#ifndef BAK_WORLDFX_H
#define BAK_WORLDFX_H

#include "structs.h"

extern void worldfx_sparkle_burst(CombatActor *actor, int color);
extern void worldfx_flux_vortex_step_particle(int slot, int base_ang_step);
extern void worldfx_render_particle_blast(CombatActor *actor, int color);
extern void worldfx_flux_vortex_play(int color);
extern void worldfx_ptcl_overlay_step_back(CombatActor *pActor);
extern void worldfx_ptcl_overlay_render_front(CombatActor *pActor);
extern void worldfx_rndr_rand_flash_at_actor(CombatActor *actor);
extern void worldfx_render_world_100_frames(void);
extern void worldfx_combat_damage_ptcl_burst(CombatActor *actor, int spread);
extern void worldfx_render_star(int index);
extern void worldfx_sparkle_update_particles(int y_max, int y_min);
extern void worldfx_sparkle_tick(void);
extern void worldfx_sparkle_render(void);
extern void worldfx_render_flame_at_actor(CombatActor *actor);
extern void worldfx_actor_box_scr_verts(Vec3Short *vertex_buf, CombatActor *actor);
extern void worldfx_draw_actor_box_wireframe(CombatActor *actor, int color_idx);
extern void worldfx_draw_actor_box_wireframe_front(CombatActor *entity, int color_mod);
extern void worldfx_state_arm_minus2(void);
extern void worldfx_depth_clip_actor_scr_y(CombatActor *actor);
extern void worldfx_clip_rect_restore(void);
extern void worldfx_rndr_spr_shadow(short shadow_palette_idx);
extern void worldfx_draw_path_segment(int grid_x, int grid_y);
extern void worldfx_draw_world_line(int x1, int y1, int x2, int y2);
extern void worldfx_draw_world_line_color(int x1, int y1, int x2, int y2, int color);

#endif
