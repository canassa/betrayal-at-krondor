#ifndef BAK_CBTAITRN_H
#define BAK_CBTAITRN_H

#include "structs.h"

extern int combataiturn_pick_tile_or_attack(CombatActor *actor, int min_score_threshold,
                                            int may_attack);
extern int combataiturn_armor_eff_stat(CombatActor *actor);
extern void combataiturn_ranged_attack(CombatActor *attacker, CombatActor *target,
                                       int quarrel_type);
extern int combataiturn_sel_consum_qrl(CombatActor *actor, int kind, int consume_flag);
extern int combataiturn_action_disp_base(CombatActor *actor, int param_2, uint param_3);
extern int combataiturn_thunk_action_6(CombatActor *actor);
extern int combataiturn_action_kind6(CombatActor *actor);
extern int combataiturn_action_1000a(CombatActor *actor);
extern int combataiturn_action_2000a(CombatActor *actor);
extern int combataiturn_action_4000a(CombatActor *actor);
extern int combataiturn_action_5000a(CombatActor *actor);
extern int combataiturn_action_3000a(CombatActor *actor);
extern int combataiturn_select_and_engage(CombatActor *actor);
extern void combataiturn_take_actor_turn(CombatActor *actor);

#endif
