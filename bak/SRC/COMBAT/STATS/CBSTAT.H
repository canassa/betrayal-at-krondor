#ifndef BAK_CBSTAT_H
#define BAK_CBSTAT_H

#include "structs.h"

extern int g_anHexVertexX0[6];
extern int g_anHexVertexY0[6];
extern int g_anHexVertexX2[6];
extern int g_anHexVertexY2[6];
extern int g_anHexVertexX3[6];
extern int g_anHexVertexY3[6];
extern int g_anHexVertexX4[6];
extern int g_anHexVertexY4[6];
extern int g_anHexVertexX5[6];
extern int g_anHexVertexY5[6];
extern int g_anHexVertexX1[6];
extern int g_anHexVertexY1[6];
extern int g_anHexVertexX6[6];
extern int g_anHexVertexY6[6];
extern int *g_apHexVertexX[7];
extern int *g_apHexVertexY[7];
extern short g_aClassGroupModifier[3][4];
extern unsigned short g_aClassCombatGroup[59];
extern unsigned short g_aClassProficiencyMask[64];
extern unsigned short g_aClassWeaknessMask[64];
extern unsigned char *g_pSpellWeaTable;
extern unsigned char *g_pSpellResTable;

extern void cbstat_apply_drain_tick(CombatActor *actor);
extern int cbstat_to_hit_roll(CombatActor *attacker, CombatActor *target, int roll,
                              ItemRecord far *weapon_item);
extern int cbstat_armor_absorption_by_class(CombatActor *attacker, CombatActor *defender,
                                            int attack_type);
extern int cbstat_compute_attack_damage(ItemRecord far *weapon, CombatActor *attacker,
                                        CombatActor *defender, int attack_type);
extern ItemRecord far *cbstat_find_intact_equip_cat(CombatActor *actor, int category);
extern void cbstat_damage_equipped_items(CombatActor *actor, int category, int severity);
extern int cbstat_magic_defense_bonus(CombatActor *actor);
extern int cbstat_magic_attack_bonus(CombatActor *actor);
extern unsigned int cbstat_actor_class_table_1802(CombatActor *actor);
extern int cbstat_scale_base_stat_pct(CombatActor *actor, int percent);
extern int cbstat_apply_proficiency_bonus(CombatActor *actor, int value, unsigned int proficiency_mask);
extern unsigned int cbstat_armor_coverage_mask(CombatActor *combat_actor);
extern int cbstat_apply_weakness_penalty(CombatActor *actor, int value, unsigned int weakness_mask);
extern void cbstat_spell_tables_load(void);
extern void cbstat_spell_tables_free(void);
extern int cbstat_char_bitmap_3w_test_170c(int char_idx, int bit_idx);
extern int cbstat_char_bitmap_3w_test(int char_idx, int bit_idx);
extern int cbstat_inv_item_condition_rec(ItemRecord far *target_far, CombatActor *actor);
extern int cbstat_damage_apply_protection(CombatActor *actor, int damage, int damage_type);
extern int cbstat_item_get_condition(ItemSlot far *slot);
extern int cbstat_apply_equipped_item_mult(CombatActor *actor, int value, int category);

#endif
