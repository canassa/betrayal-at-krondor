#ifndef BAK_CBTAITRN_H
#define BAK_CBTAITRN_H

#include "structs.h"

extern EncounterAiActionFn far *g_encounter_ai_action_table[8];
extern unsigned char __dat_15dc[128];

extern int combataiturn_sel_consum_qrl(CombatActor *actor, int kind, int consume_flag);
extern void combataiturn_ranged_attack(CombatActor *attacker, CombatActor *target,
                                       int quarrel_type);
extern int combataiturn_armor_eff_stat(CombatActor *actor);
extern int combataiturn_thunk_action_6(CombatActor *actor);
extern int combataiturn_action_kind6(CombatActor *actor);
extern int combataiturn_action_1000a(CombatActor *actor);
extern int combataiturn_action_2000a(CombatActor *actor);
extern int combataiturn_action_4000a(CombatActor *actor);
extern int combataiturn_action_5000a(CombatActor *actor);
extern int combataiturn_action_3000a(CombatActor *actor);
extern int combataiturn_select_and_engage(CombatActor *actor);
extern int combataiturn_pick_tile_or_attack(CombatActor *actor, int min_score_threshold,
                                            int may_attack);
extern int combataiturn_action_disp_base(CombatActor *actor, int param_2, unsigned int param_3);
extern void combataiturn_take_actor_turn(CombatActor *actor);

#endif
