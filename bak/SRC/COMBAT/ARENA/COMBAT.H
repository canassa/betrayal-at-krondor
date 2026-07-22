#ifndef BAK_COMBAT_H
#define BAK_COMBAT_H

#include "structs.h"

extern void combat_arena_mode_enter(void);
extern void combat_arena_mode_exit(void);
extern void combat_arena_tick_status_timers(void);
extern void combat_arena_actor_turn_loop(int encounter_id, int *p_status, int b_has_fired);
extern void combat_arena_suspend_char_screen(CombatActor *actor, int *p_spell_result,
                                             int *p_spell_out);
extern void combat_arena_splash_dmg_near(CombatActor *source_actor, int damage);
extern void combat_arena_actor_set_anim_pose(CombatActor *actor, uchar frame);
extern void combat_arena_swap_tgt_state(void);
extern int combat_arena_wait_confirm_cancel(void);
extern void combat_arena_resolve_melee_swing(CombatActor *attacker, CombatActor *defender,
                                             int damage);
extern void combat_arena_melee_attack(CombatActor *attacker, CombatActor *defender, int damage);
extern void combat_arena_apply_damage(CombatActor *actor, int damage, int apply_magic_defense,
                                      int knockback, uint flags, int source_type);
extern void combat_arena_actor_poison_tick(CombatActor *actor);
extern void combat_arena_actor_die(CombatActor *actor, int play_anim);
extern void combat_arena_load_remap_pals(void);
extern void combat_arena_remove_flagd_actors(void);
extern int combat_arena_all_targets_immune(void);
extern ushort combat_arena_anim_tbl_lookup_2d(int row, int col);
extern void combat_arena_round_trans_show(int param_1);
extern void combat_arena_draw_tgt_info_hud(CombatActor *param_1, int param_2, int param_3,
                                           int param_4);
extern void combat_arena_draw_tgt_info_panel(void);
extern void combat_arena_hud_melee_panel(void);
extern int combat_arena_cnt_actors_combat(void);
extern int combat_arena_cnt_actors_flag_10(void);
extern void combat_arena_resume_dispatch(int command_id, int *p_spell_result,
                                         int *out_spell_result);
extern int combat_arena_dist_actors_by_id(int actor_id_a, int actor_id_b);
extern void combat_arena_show_message_by_id(int message_id, unsigned short *p_menu, int *p_param3,
                                            int *p_param4, int *p_param5, int *p_spell_result,
                                            int *p_spell_out, int *p_param8, MenuPage **p_menu_slot,
                                            int *p_param10, int *p_param11);
extern CombatActor *combat_arena_disp_spell_action(int *param_1, int *param_2, int *param_3,
                                                   int param_4, int *param_5, int *param_6);
extern void combat_arena_turn_actor_inact(uint *p_far_offset, int *p_turn_done, int *p_hud_state,
                                          int *p_ai_flag);
extern void combat_arena_resolve_menu_action(int *p_state_a, int *p_move_cost, int *p_state_b,
                                             int b_input_locked, int b_input_gate, int *p_dirty_hud,
                                             CombatActor **pp_cursor_target, int arg8,
                                             int spell_record_id, int arg10,
                                             MenuPage **pp_menu_slot);

#endif
