#ifndef BAK_CBTAI_H
#define BAK_CBTAI_H

#include "structs.h"

extern int combat_ai_try_cast_heal(CombatActor *caster);
extern int combat_ai_turn_kind6(CombatActor *actor);
extern int combat_ai_turn_packet_10006(CombatActor *actor);
extern int combat_ai_turn_packet_20006(CombatActor *actor);
extern int combat_ai_turn_packet_40006(CombatActor *actor);
extern int combat_ai_turn_packet_50006(CombatActor *actor);
extern int combat_ai_turn_packet_30006(CombatActor *actor);
extern int combat_ai_try_aoe_cast_spell_7(CombatActor *actor);
extern void combat_ai_actor_cast_spell(CombatActor *caster, CombatActor *target, int spell_id);
extern void combat_ai_resolve_attack_attempt(CombatActor *attacker, CombatActor *target,
                                             int spell_id);
extern void combat_ai_resolve_hit(CombatActor *attacker, CombatActor *target, int damage, int dir);
extern int combat_ai_pick_action(CombatActor *actor);
extern int combat_ai_execute_turn(CombatActor *actor, int param_2, unsigned int param_3);
extern int combat_ai_pick_heal_spell(CombatActor *caster, CombatActor *target);
extern void combat_ai_take_turn(CombatActor *actor);

#endif
