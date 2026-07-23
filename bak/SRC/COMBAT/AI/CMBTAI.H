#ifndef BAK_CMBTAI_H
#define BAK_CMBTAI_H

#include "structs.h"

extern CombatAiActionFn far *g_combat_ai_action_table[8];
extern unsigned short g_bActorAdjacentToTarget;
extern unsigned char __dat_1492[138];

extern int combataipath_actor_walk_path(CombatActor *actor, int ranged);
extern int combataipath_low_health_action(CombatActor *actor);
extern int combataipath_action_6(CombatActor *actor);
extern int combataipath_action_100_1(CombatActor *actor);
extern int combataipath_action_100_2(CombatActor *actor);
extern int combataipath_action_60064(CombatActor *actor);
extern int combataipath_action_50064(CombatActor *actor);
extern int combataipath_action_30064(CombatActor *actor);
extern int combataipath_action_40064(CombatActor *actor);
extern void combataipath_select_target(CombatActor *actor, int max_dist, int target_mode);
extern void combataipath_followup_action(CombatActor *actor);
extern int combataipath_follow_tgt_check(CombatActor *actor, int max_dist, int target_mode);
extern void combataipath_select_action(CombatActor *actor);

#endif
