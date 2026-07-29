#ifndef BAK_CBENC_H
#define BAK_CBENC_H

#include "structs.h"
#include "SRC/GAME/ACTOR/ACTOR.H"

extern short g_anStatCheckThreshold[9];
extern unsigned short g_ai_flee_threshold_table[10];
extern unsigned char g_bssgap_5128[2];
extern Combatant *g_combat_actors_B;
extern AnimSlot *g_anim_pool_B;
extern int g_combat_count_B;
extern unsigned char g_bssgap_511e[4];
extern Combatant *g_actors_B_origin;
extern short g_chapter_roster[7];
extern ImageRecord **g_abCombatInnerPoolB[7][11];
extern char g_combat_save_filename[14];
extern unsigned short g_inner_pool_B;

extern void combatenc_chap_load_party_grn(int chapter);
extern void combatenc_actor_flee_tile_east(Combatant *actor);
extern void combatenc_apply_flee_tile_team(int team_id);
extern void combatenc_mnames_lookup_dest(int index, char **p_dest);
extern void combatenc_draw_actor_roster_idx(Combatant *actor);
extern void combatenc_actor_face_target(Combatant *actor);
extern void combatenc_refr_actor_flags_far(void);
extern int combatenc_actor_can_act(Combatant *actor, int strict);
extern int combatenc_count_active_enemies(void);
extern int combatenc_party_within_cheby(Combatant *actor, int range);
extern int combatenc_alive_actor_count(void);
extern int combatenc_actor_id_eq_22(Combatant *actor);
extern int combatenc_actor_has_spell_1or4(Combatant *actor);
extern void combatenc_save_state(void);
extern void combatenc_ai_attempt_melee(Combatant *actor);
extern void combatenc_set_flag8_clear_flag1(Combatant *actor);
extern void combatenc_actor_enter_defense(Combatant *actor);
extern void combatenc_anim_actor_stat_rolls(Combatant *actor);
extern Combatant *combatenc_find_nearest_actor(Combatant *from, int *out_dist);
extern int combatenc_show_missile_stat_row(Combatant *actor);
extern int combatenc_actor_can_cast_spells(Combatant *actor, int find_nearest);
extern int combatenc_compute_hit_chance(Combatant *attacker, Combatant *target, int base_skill,
                                        int quarrel_kind);
extern int combatenc_skill_check_random(Combatant *attacker, Combatant *target, int base_skill,
                                        int quarrel_kind);
extern void combatenc_ai_pick_target_by_role(Combatant *actor, int max_distance, unsigned int role_filter,
                                             int min_party_clearance);
extern int combatenc_actor_stat_above_table(int threshold_idx, Combatant *actor);
extern void combatenc_ai_run_turn(void);
extern void combatenc_place_b_free_tiles(void);
extern void combatenc_clear_pty_grid_occ(void);
extern int combatenc_is_encounter_actor(Combatant *actor);
extern void combatenc_spawns_load_zones_tmp(void);
extern void combatenc_init_actor_anim_pool(void);
extern char *combatenc_build_save_filename(int slot);
extern void combatenc_pty_load_chap_state(void);
extern void combatenc_persist_actors_to_temp(int param_1);
extern void combatenc_vis_actors_call_rev(void);
extern void combatenc_release_actors(void);
extern void combatenc_ai_morale_flee_check(Combatant *actor);
extern void combatenc_pick_next_active_actor(void);
extern void combatenc_refresh_actor_flags(void);
extern void combatenc_ai_suicide_on_arrival(Combatant *actor);
extern void combatenc_ai_sel_execute_action(Combatant *actor);
extern Actor far *combatenc_corpse_tbl_spawn_actor(long record_id, int slot);
extern void combatenc_saves_migr_all_slots(void);

#endif
