#ifndef BAK_STAT_H
#define BAK_STAT_H

#include "structs.h"

extern unsigned char g_abStatMin[17];
extern unsigned short g_awStatMax[17];
extern unsigned char g_abStatClampMin[17];
extern unsigned char g_abStatClampMax[17];
extern unsigned char g_abStatRatio[17];
extern unsigned char g_abStatRatioBase[17];
extern unsigned char g_abStatRatioMax[17];

extern int stat_party_all_above_pct(int percent);
extern unsigned int stat_actor_get(CombatActor *actor, int stat_idx, int mode);
extern unsigned int stat_combatant_modify(CombatActor *actor, int stat_idx, long delta, int mode);
extern unsigned int stat_party_find_extreme(int stat_id, int param_2, short *result_out);
extern void stat_party_broadcast_status_op(int stat_idx, long delta, int mode);
extern unsigned int stat_combatant_apply_delta(CombatActor *actor, int stat_idx, int amount);
extern void stat_modifier_table_insert(CombatActor *actor, ActorStatModifier *pNewMod);
extern void stat_actor_clear_mods_mask(CombatActor *actor, unsigned short mask);
extern void stat_combatant_heal(CombatActor *combatant, int amount_pct);
extern void stat_party_heal_all(int amount);
extern void stat_actor_recalc_equip_bonuses(CombatActor *actor);
extern void stat_apply_modifier(unsigned short *mod, int *stat);

#endif
