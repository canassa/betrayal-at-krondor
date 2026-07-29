#ifndef BAK_CBTAI_H
#define BAK_CBTAI_H

#include "structs.h"

extern EncounterAiTurnFn far *g_encounter_ai_turn_table[8];
extern unsigned char __dat_153c[128];

extern int combat_ai_try_cast_heal(Combatant *caster);
extern int combat_ai_turn_kind6(Combatant *actor);
extern int combat_ai_turn_packet_10006(Combatant *actor);
extern int combat_ai_turn_packet_20006(Combatant *actor);
extern int combat_ai_turn_packet_40006(Combatant *actor);
extern int combat_ai_turn_packet_50006(Combatant *actor);
extern int combat_ai_turn_packet_30006(Combatant *actor);
extern int combat_ai_try_aoe_cast_spell_7(Combatant *actor);
extern void combat_ai_actor_cast_spell(Combatant *caster, Combatant *target, int spell_id);
extern void combat_ai_resolve_attack_attempt(Combatant *attacker, Combatant *target,
                                             int spell_id);
#ifndef V102CD
extern void combat_ai_resolve_hit(Combatant *attacker, Combatant *target, int damage, int dir);
#endif
extern int combat_ai_pick_action(Combatant *actor);
extern int combat_ai_execute_turn(Combatant *actor, int param_2, unsigned int param_3);
extern int combat_ai_pick_heal_spell(Combatant *caster, Combatant *target);
extern void combat_ai_take_turn(Combatant *actor);

#endif
