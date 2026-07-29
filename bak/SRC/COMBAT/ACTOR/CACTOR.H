#ifndef BAK_CACTOR_H
#define BAK_CACTOR_H

#include "structs.h"

extern unsigned short g_wCombatSpinnerYaw;
extern int g_combat_count_A;
extern Combatant *g_combat_actors_A;
extern AnimSlot *g_anim_pool_A;
extern unsigned char g_bssgap_5028[2];
extern Combatant **g_active_combatants;
extern ImageRecord **g_aCombatInnerPool[7][11];
extern CombatResCacheCol g_aCombatResCacheKindFlag;
extern CombatResCacheCol g_aCombatResCacheRefcount;
extern unsigned short g_aCombatResCacheKey[8];
extern ImageRecord **g_aCombatResCacheValue[8][3];

extern void combat_actor_deploy_encounter(void);
extern int combat_actor_step_to_tgt_adj(Combatant *attacker, Combatant *defender);
extern Combatant *combat_actor_encounter_at_tile(int tile_x, int tile_y);
extern Combatant *combat_actor_visible_at_tile(int tile_x, int tile_y);
extern void combat_actor_grid_remove(Combatant *actor);
extern void combat_actor_register(Combatant *actor);
extern void combat_actor_kill_remaining(void);
extern void combat_actor_kill_remaining_enc(void);
extern void combat_actor_debug_restore_stats(void);
#ifdef V102CD
extern Combatant *combat_actor_remove(Combatant *actor);
#else
extern void combat_actor_remove(Combatant *actor);
#endif
extern Combatant *combat_actor_party_add(int creatureType);
extern void combat_actor_release_anim_images(int creatureType);
extern ImageRecord **far combat_actor_rsrc_cache_val(int creatureType, int param_2);
extern void combat_actor_play_short_cine(Combatant *actor, int overlay_id);
extern ItemRecord far *combat_actor_qrl_rec_kind(int kind);
extern int combat_actor_cnt_qrls_kind(Combatant *actor, int kind);
extern void combat_actor_place_on_free_tile(Combatant *actor);
extern void combat_actor_face_cursor(void);
extern void combat_actor_anim_mark_dirty(Combatant *actor, int frame);
extern void combat_actor_anim_rand_phase(Combatant *actor);
extern int combat_actor_lookup_param_rec(Combatant *actor);
extern int combat_actor_enc_lookup_field2(Combatant *actor);
extern int combat_actor_find_by_subrec_id(int creatureType);
extern int combat_actor_bitmap_set_bit(int bitmap, int bit_index);
extern void combat_actor_flag_bitset_clear(int record, int bit);
extern int combat_actor_heading_from_to(Combatant *from, Combatant *to);
extern void combat_actor_play_anim_sprite4(Combatant *actor, int direction);
extern void combat_actor_play_anim_sprite3(Combatant *actor, int direction);
extern void combat_actor_play_anim_sprite1(Combatant *actor, int direction);
extern void combat_actor_anim_spr1_alt(Combatant *actor, int direction);
extern void combat_actor_anim7_field2_var(Combatant *actor, int direction);
extern void combat_actor_anim0_if_not_dead(Combatant *actor, int direction);
extern void combat_actor_play_anim_sprite5(Combatant *actor, int frame);
extern void combat_actor_play_anim_sprite6(Combatant *actor, int frame);
extern void combat_actor_play_ranged_windup(Combatant *actor, int direction);
extern void combat_actor_play_melee_swing(Combatant *actor, int direction);
extern void combat_actor_path_blocked_anim(void);
extern void combat_actor_show_push_prompt(void);
extern void combat_actor_draw_stats_panel(Combatant *actor);
extern int combat_actor_calc_weapon_damage(Combatant *actor, int kind);
extern int combat_actor_melee_approach(Combatant *attacker, Combatant *defender);
extern void combat_actor_refresh_all_stats(void);
extern unsigned int combat_actor_terr_under_cur(void);
extern int combat_actor_cur_tile_block(void);
extern int combat_actor_cursor_distance(Combatant *actor);
extern int combat_actor_stat_percent(Combatant *actor, int with_modifier);
extern void combat_actor_grid_render(WorldObject *focus_actor);
extern void combat_actor_move_to_cursor(Combatant *actor);
extern void combat_actor_place_all_free(void);
extern void combat_actor_pick_next(void);
extern int combat_actor_trace_proj_path(Combatant *shooter, Combatant *target, int flags);
extern void combat_actor_rsrc_load_3values(int creatureType, ImageRecord ***table);
extern void combat_actor_init_pool(void);
extern void combat_actor_pool_teardown(void);
extern int combat_actor_is_visible(Combatant *actor);
extern ImageRecord **combat_actor_bnames_load_cached(int creatureType, int col);
extern int combat_actor_find_by_id(int creatureType);
extern void combat_actor_apply_render_table(Combatant *actor);
extern void combat_actor_anim_step(unsigned char *anim_state_buf, Combatant *actor);
extern void combat_actor_draw_float_damage(Combatant *actor);
extern void combat_actor_tile_entry_effect(int tile_x, int tile_y, int *p_status, int do_apply,
                                           int extra_flag);
extern void combat_actor_redraw_at_tile(int tile_x, int tile_y);
extern int combat_actor_direction_to_cursor(void);

#endif
