#ifndef BAK_CACTOR_H
#define BAK_CACTOR_H

#include "structs.h"

extern void combat_actor_init_pool(void);
extern void combat_actor_pool_teardown(void);
extern void combat_actor_place_on_free_tile(CombatActor *actor);
extern CombatActor *combat_actor_party_add(int class_id);
extern void combat_actor_remove(CombatActor *actor);
extern void combat_actor_register(CombatActor *actor);
extern void combat_actor_grid_remove(CombatActor *actor);
extern CombatActor *combat_actor_visible_at_tile(int tile_x, int tile_y);
extern CombatActor *combat_actor_encounter_at_tile(int tile_x, int tile_y);
extern int combat_actor_is_visible(CombatActor *actor);
extern void combat_actor_deploy_encounter(void);
extern int combat_actor_bitmap_set_bit(int bitmap, int bit_index);
extern void combat_actor_flag_bitset_clear(int record, int bit);
extern int combat_actor_cnt_qrls_kind(CombatActor *actor, int kind);
extern ImageRecord **combat_actor_bnames_load_cached(int class_id, int col);
extern void combat_actor_rsrc_load_3values(int class_id, ImageRecord ***table);
extern void combat_actor_release_anim_images(int class_id);
extern ImageRecord **far combat_actor_rsrc_cache_val(int class_id, int param_2);
extern int combat_actor_cursor_distance(CombatActor *actor);
extern ItemRecord far *combat_actor_qrl_rec_kind(int kind);
extern int combat_actor_calc_weapon_damage(CombatActor *actor, int kind);
extern int combat_actor_stat_percent(CombatActor *actor, int with_modifier);
extern uint combat_actor_terr_under_cur(void);
extern int combat_actor_cur_tile_block(void);
extern void combat_actor_move_to_cursor(CombatActor *actor);
extern int combat_actor_find_by_subrec_id(int class_id);
extern int combat_actor_find_by_id(int class_id);
extern void combat_actor_apply_render_table(CombatActor *actor);
extern void combat_actor_anim_step(uchar *anim_state_buf, CombatActor *actor);
extern void combat_actor_draw_float_damage(CombatActor *actor);
extern void combat_actor_play_short_cine(CombatActor *actor, int overlay_id);
extern void combat_actor_tile_entry_effect(int tile_x, int tile_y, int *p_status, int do_apply,
                                           int extra_flag);
extern int combat_actor_trace_proj_path(CombatActor *shooter, CombatActor *target, int flags);
extern void combat_actor_redraw_at_tile(int tile_x, int tile_y);
extern void combat_actor_grid_render(WorldObject *focus_actor);
extern void combat_actor_place_all_free(void);
extern void combat_actor_refresh_all_stats(void);
extern void combat_actor_pick_next(void);
extern void combat_actor_show_push_prompt(void);
extern void combat_actor_path_blocked_anim(void);
extern void combat_actor_draw_stats_panel(CombatActor *actor);
extern int combat_actor_step_to_tgt_adj(CombatActor *attacker, CombatActor *defender);
extern int combat_actor_melee_approach(CombatActor *attacker, CombatActor *defender);
extern int combat_actor_direction_to_cursor(void);
extern int combat_actor_heading_from_to(CombatActor *from, CombatActor *to);
extern void combat_actor_face_cursor(void);
extern void combat_actor_anim7_field2_var(CombatActor *actor, int direction);
extern void combat_actor_anim0_if_not_dead(CombatActor *actor, int direction);
extern void combat_actor_anim_rand_phase(CombatActor *actor);
extern void combat_actor_play_anim_sprite4(CombatActor *actor, int direction);
extern void combat_actor_play_anim_sprite3(CombatActor *actor, int direction);
extern void combat_actor_play_anim_sprite1(CombatActor *actor, int direction);
extern void combat_actor_anim_spr1_alt(CombatActor *actor, int direction);
extern void combat_actor_play_ranged_windup(CombatActor *actor, int direction);
extern void combat_actor_play_melee_swing(CombatActor *actor, int direction);
extern void combat_actor_anim_mark_dirty(CombatActor *actor, int frame);
extern void combat_actor_play_anim_sprite5(CombatActor *actor, int frame);
extern void combat_actor_play_anim_sprite6(CombatActor *actor, int frame);
extern int combat_actor_enc_lookup_field2(CombatActor *actor);
extern int combat_actor_lookup_param_rec(CombatActor *actor);
extern void combat_actor_debug_restore_stats(void);
extern void combat_actor_kill_remaining_enc(void);
extern void combat_actor_kill_remaining(void);

#endif
