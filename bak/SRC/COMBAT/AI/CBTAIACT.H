#ifndef BAK_CBTAIACT_H
#define BAK_CBTAIACT_H

#include "structs.h"

extern void combataiact_pick_melee_or_missl(CombatActor *actor);
extern void combataiact_random_move_attack(CombatActor *actor);
extern void combataiact_ranged_attack_turn(CombatActor *actor);
extern void combataiact_actor_melee_attack(CombatActor *actor);
extern void combataiact_action_charge_near(CombatActor *actor);
extern void combataiact_melee_random_attack(CombatActor *actor);
extern void combataiact_ranged_attack(CombatActor *actor);
extern void combataiact_bhood_revive_cycle(CombatActor *actor);
extern int combataiact_cnt_pty_stat_22(void);
extern void combataiact_party_tick_status(void);

#endif
