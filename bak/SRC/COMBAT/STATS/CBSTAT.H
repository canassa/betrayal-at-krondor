#ifndef BAK_CBSTAT_H
#define BAK_CBSTAT_H

#include "structs.h"

extern int cbstat_item_get_condition(ItemSlot far *slot);
extern void cbstat_spell_tables_load(void);
extern void cbstat_spell_tables_free(void);
extern int cbstat_char_bitmap_3w_test(int char_idx, int bit_idx);
extern int cbstat_char_bitmap_3w_test_170c(int char_idx, int bit_idx);
extern uint cbstat_actor_class_table_1802(CombatActor *actor);
extern int cbstat_apply_proficiency_bonus(CombatActor *actor, int value, uint proficiency_mask);
extern int cbstat_apply_weakness_penalty(CombatActor *actor, int value, uint weakness_mask);
extern void cbstat_apply_drain_tick(CombatActor *actor);
extern uint cbstat_armor_coverage_mask(CombatActor *combat_actor);
extern int cbstat_scale_base_stat_pct(CombatActor *actor, int percent);
extern int cbstat_apply_equipped_item_mult(CombatActor *actor, int value, int category);
extern int cbstat_damage_apply_protection(CombatActor *actor, int damage, int damage_type);
extern int cbstat_armor_absorption_by_class(CombatActor *attacker, CombatActor *defender,
                                            int attack_type);
extern int cbstat_compute_attack_damage(ItemRecord far *weapon, CombatActor *attacker,
                                        CombatActor *defender, int attack_type);
extern ItemRecord far *cbstat_find_intact_equip_cat(CombatActor *actor, int category);
extern void cbstat_damage_equipped_items(CombatActor *actor, int category, int severity);
extern int cbstat_magic_attack_bonus(CombatActor *actor);
extern int cbstat_magic_defense_bonus(CombatActor *actor);
extern int cbstat_to_hit_roll(CombatActor *attacker, CombatActor *target, int roll,
                              ItemRecord far *weapon_item);
extern int cbstat_inv_item_condition_rec(ItemRecord far *target_far, CombatActor *actor);

#endif
