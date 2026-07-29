#ifndef BAK_CBTAITRN_H
#define BAK_CBTAITRN_H

#include "structs.h"

extern EncounterAiActionFn far *g_encounter_ai_action_table[8];
extern unsigned char __dat_15dc[128];

extern int combataiturn_sel_consum_qrl(Combatant *actor, int kind, int consume_flag);
extern void combataiturn_ranged_attack(Combatant *attacker, Combatant *target,
                                       int quarrel_type);
extern int combataiturn_armor_eff_stat(Combatant *actor);
extern int combataiturn_thunk_action_6(Combatant *actor);
extern int combataiturn_action_kind6(Combatant *actor);
extern int combataiturn_action_1000a(Combatant *actor);
extern int combataiturn_action_2000a(Combatant *actor);
extern int combataiturn_action_4000a(Combatant *actor);
extern int combataiturn_action_5000a(Combatant *actor);
extern int combataiturn_action_3000a(Combatant *actor);
extern int combataiturn_select_and_engage(Combatant *actor);
extern int combataiturn_pick_tile_or_attack(Combatant *actor, int min_score_threshold,
                                            int may_attack);
extern int combataiturn_action_disp_base(Combatant *actor, int param_2, unsigned int param_3);
extern void combataiturn_take_actor_turn(Combatant *actor);

#endif
