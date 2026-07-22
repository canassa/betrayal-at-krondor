#ifndef BAK_CMBTGRID_H
#define BAK_CMBTGRID_H

#include "structs.h"

extern void combatgrid_cmbts_tbl_alloc(void);
extern void combatgrid_combatants_table_free(void);
extern int combatgrid_coord_valid(int x, int y);
extern void combatgrid_remove_cmbt_at_tile(int tile_x, int tile_y);
extern void combatgrid_kill_cmbt_at_tile(int tile_x, int tile_y);
extern unsigned int combatgrid_tile_terrain(char tile_x, char tile_y);
extern GridCombatant *combatgrid_find_cmbt_at_tile(char tile_x, char tile_y);
extern unsigned int combatgrid_tile_blockd_cmbt(char tile_x, char tile_y);
extern unsigned int combatgrid_tile_is_blocked(char tile_x, char tile_y);
extern void combatgrid_tile_set_word(char x, char y, unsigned int value);
extern unsigned int combatgrid_tile_terrain_field(char x, char y);
extern int combatgrid_tile_field4(char x, char y);
extern void combatgrid_tick_tile_effect(char x, char y);
extern void combatgrid_set_tile_effect(char x, char y, unsigned short type, int timer);
extern int combatgrid_prox_check_kind_set(WorldPos2 *pos);
extern void combatgrid_world_to_view_2d(WorldPos2 *origin, int angle, WorldPos2 far *point,
                                        int *out_xy);
extern int combatgrid_tile_cam_near_wedge(int tile_x, int tile_y);
extern int combatgrid_obj_kind_prox_actv(int kind);
extern int combatgrid_cmbt_block_kind(int kind);
extern int combatgrid_plr_prox_sweep_cnt(void);
extern int combatgrid_tiles_match_ctr_px(void);
extern int combatgrid_tiles_over_thresh(void);
extern void combatgrid_build_combatant_list(WorldPos2 *pWorldPos, short *pViewState);
extern void combatgrid_tile_to_world_rotated(WorldPos2 *p_out, int tile_x, int tile_y);
extern void combatgrid_actor_set_grid_pos(int actor_idx, int new_x, int new_y);
extern void combatgrid_load_traps_dat(void);
extern void combatgrid_clear_combatants(void);
extern void combatgrid_tile_fx_init_walk(void);
extern void combatgrid_classify_tiles_px(void);
extern void combatgrid_tile_fx_init_pass(void);
extern void combatgrid_load_and_init(void);
extern void combatgrid_draw_terrain_walls(void);
extern void combatgrid_apply_tile_status_fx(int tile_x, int tile_y, int target_actor);
extern void combatgrid_mark_engagement_line(int x1, int y1, int x2, int y2, short paged_id,
                                            int do_register);
extern int combatgrid_place_actor_on_tile(int tile_x, int tile_y, int new_tile_x, int new_tile_y);
extern void combatgrid_find_adj_pass_tile(int x, int y, unsigned int terrain_mask, int *out_dx,
                                          int *out_dy);
extern void combatgrid_spread_tile_fx_line(int x, int y);
extern void combatgrid_line_effect_propagate(int x, int y);
extern int combatgrid_tile_walkable_kind(int x, int y, int kind);
extern int combatgrid_nbr_probe_diag(int x, int y, int kind);
extern void combatgrid_kill_adj_cmbt_team(int tile_x, int tile_y, int team);
extern void combatgrid_push_back_actor(int tile_x, int tile_y);
extern void combatgrid_shove_until_unblocked(int tile_x, int tile_y);
extern int combatgrid_nbr_probe_orthogonal(int x, int y, int kind);
extern int combatgrid_is_combatant_type(int paged_id);
extern void combatgrid_clear_tile_effects(void);
extern void combatgrid_save_traps_terr(int encounter_idx);
extern int combatgrid_can_engage_same_kind(int idx_a, int idx_b);
extern void combatgrid_apply_engage_links(int start_idx);
extern void combatgrid_place_tile_fx_at_cur(unsigned short type, int timer);
extern void combatgrid_clear_terr_6_effects(void);
extern int combatgrid_actor_past_terr6_row(void);
extern int combatgrid_any_terrain_6(void);
extern void combatgrid_cur_tile_world(void);
extern int combatgrid_chebyshev_distance(char x1, char y1, char x2, char y2);
extern int combatgrid_actors_ortho_adj(CombatActor *actor_a, CombatActor *actor_b);
extern int combatgrid_is_pure_diagonal(CombatActor *actor, int target_x, int target_y);
extern int combatgrid_actor_try_step_tile(CombatActor *actor, int tx, int ty);
extern void combatgrid_build_move_attack_map(CombatActor *actor);
extern int combatgrid_cursor_tile_movable(void);
extern int combatgrid_tile_has_terr_bit2(CombatActor *actor);
extern void combatgrid_actor_step_to_tile(CombatActor *mover, int tile_x, int tile_y);
extern void combatgrid_pathfind_from_tile(int tx, int ty, int dest);
extern int combatgrid_tile_blockd_kind10(CombatActor *actor);
extern int combatgrid_tile_passable_check(int required_terrain, int tile_x, int tile_y,
                                          CombatActor *mover);
extern void combatgrid_step_search(CombatActor *actor, int preferred_dir);
extern void combatgrid_rndr_engagement_lines(void);
extern void combatgrid_unhighlight_terr_type(unsigned short terrain);
extern int combatgrid_tile_has_mobility(int col, int row, int tile_count);

#endif
