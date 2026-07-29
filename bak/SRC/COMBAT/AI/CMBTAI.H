#ifndef BAK_CMBTAI_H
#define BAK_CMBTAI_H

#include "structs.h"

extern CombatAiActionFn far *g_combat_ai_action_table[8];
extern unsigned short g_bActorAdjacentToTarget;
extern unsigned char __dat_1492[138];

extern int combataipath_actor_walk_path(Combatant *actor, int ranged);
extern int combataipath_low_health_action(Combatant *actor);
extern int combataipath_action_6(Combatant *actor);
extern int combataipath_action_100_1(Combatant *actor);
extern int combataipath_action_100_2(Combatant *actor);
extern int combataipath_action_60064(Combatant *actor);
extern int combataipath_action_50064(Combatant *actor);
extern int combataipath_action_30064(Combatant *actor);
extern int combataipath_action_40064(Combatant *actor);
extern void combataipath_select_target(Combatant *actor, int max_dist, int target_mode);
extern void combataipath_followup_action(Combatant *actor);
extern int combataipath_follow_tgt_check(Combatant *actor, int max_dist, int target_mode);
extern void combataipath_select_action(Combatant *actor);

#endif
