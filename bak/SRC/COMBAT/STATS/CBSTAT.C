#include <dos.h>
#include <stdlib.h>
#include "structs.h"
#include "SRC/WORLD/ACTOR/ACTOR.H"
#include "SRC/COMBAT/STATS/CBSTAT.H"
#include "SRC/SYS/RAND.H"
#include "SRC/IO/IO.H"
#include "SRC/SYS/MEM.H"
#include "SRC/AUDIO/ENGINE/AUDIO.H"
#include "SRC/CHAR/STAT.H"
#include "SRC/SCREENS/ITEMTBL.H"
#include "SRC/COMBAT/ACTOR/CACTOR.H"
#include "SRC/COMBAT/ENC/CBENC.H"
#include "defines.h"

unsigned char *g_pSpellWeaTable;
unsigned char *g_pSpellResTable;

int g_anHexVertexX0[6] = {71, 95, 123, 19, 49, 59};
int g_anHexVertexY0[6] = {16, 101, 61, 61, 101, 61};
int g_anHexVertexX2[6] = {124, 71, 40, 104, 71, 19};
int g_anHexVertexY2[6] = {62, 16, 97, 97, 16, 62};
int g_anHexVertexX3[6] = {104, 19, 105, 39, 123, 41};
int g_anHexVertexY3[6] = {98, 62, 26, 26, 61, 98};
int g_anHexVertexX4[6] = {37, 37, 107, 107, 37, 107};
int g_anHexVertexY4[6] = {29, 96, 29, 96, 96, 96};
int g_anHexVertexX5[6] = {75, 114, 75, 75, 31, 75};
int g_anHexVertexY5[6] = {72, 89, 17, 72, 89, 17};
int g_anHexVertexX1[6] = {19, 47, 108, 34, 92, 123};
int g_anHexVertexY1[6] = {70, 22, 93, 93, 20, 70};
int g_anHexVertexX6[6] = {70, 115, 117, 72, 26, 25};
int g_anHexVertexY6[6] = {16, 37, 83, 107, 86, 40};
int *g_apHexVertexX[7] = {(int *)g_anHexVertexX0, (int *)g_anHexVertexX1, (int *)g_anHexVertexX2,
                          (int *)g_anHexVertexX3, (int *)g_anHexVertexX4, (int *)g_anHexVertexX5,
                          (int *)g_anHexVertexX6};
int *g_apHexVertexY[7] = {(int *)g_anHexVertexY0, (int *)g_anHexVertexY1, (int *)g_anHexVertexY2,
                          (int *)g_anHexVertexY3, (int *)g_anHexVertexY4, (int *)g_anHexVertexY5,
                          (int *)g_anHexVertexY6};
short g_aClassGroupModifier[3][4] = {0, -1, -1, -2, -1, 0, -1, -2, -1, -1, 0, -2};
unsigned short g_aClassCombatGroup[59] = {
    0x0000, 0x0000, 0x0000, 0x0000, 0x0000, 0x0000, 0x0000, 0x0000, 0x0000, 0x0000, 0x0000, 0x0000,
    0x0000, 0x0000, 0x0000, 0x0002, 0x0000, 0x0000, 0x0002, 0x0000, 0x0000, 0x0002, 0x0000, 0x0000,
    0x0000, 0x0000, 0x0000, 0x0000, 0x0000, 0x0000, 0x0000, 0x0000, 0x0000, 0x0000, 0x0000, 0x0000,
    0x0000, 0x0000, 0x0000, 0x0000, 0x0000, 0x0000, 0x0000, 0x0000, 0x0000, 0x0000, 0x0000, 0x0000,
    0x0000, 0x0000, 0x0000, 0x0000, 0x0000, 0x0000, 0x0000, 0x0000, 0x0000, 0x0000, 0x0000};

unsigned short g_aClassProficiencyMask[64] = {
    0x0000, 0x0000, 0x0000, 0x0000, 0x0000, 0x0000, 0x0000, 0x0000, 0x0000, 0x0000, 0x0000,
    0x0000, 0x0000, 0x0000, 0x0000, 0x0000, 0x0000, 0x0000, 0x0000, 0x0001, 0x0000, 0x0000,
    0x0000, 0x0000, 0x0000, 0x0010, 0x0200, 0x0000, 0x0002, 0x0000, 0x0100, 0x0000, 0x0000,
    0x0000, 0x0000, 0x0000, 0x0000, 0x0000, 0x0000, 0x0000, 0x0000, 0x0002, 0x000c, 0x0020,
    0x0000, 0x0000, 0x0000, 0x0000, 0x0200, 0x0000, 0x0000, 0x0000, 0x0000, 0x0000, 0x0000,
    0x0000, 0x0000, 0x0000, 0x0040, 0x0000, 0x0000, 0x0000, 0x0000, 0x0000};
unsigned short g_aClassWeaknessMask[64] = {
    0x0000, 0x0000, 0x0000, 0x0000, 0x0000, 0x0000, 0x0000, 0x0000, 0x0000, 0x0000, 0x0000,
    0x0000, 0x0000, 0x0000, 0x0000, 0x0001, 0x0200, 0x0000, 0x0001, 0x0000, 0x0000, 0x0001,
    0x00c0, 0x0001, 0x0000, 0x0000, 0x00c0, 0x0200, 0x000c, 0x0000, 0x0000, 0x0000, 0x0000,
    0x0002, 0x0000, 0x0000, 0x0000, 0x0000, 0x0000, 0x0001, 0x0000, 0x000c, 0x0002, 0x0000,
    0x0001, 0x0200, 0x0000, 0x0200, 0x0100, 0x0300, 0x0001, 0x0001, 0x0000, 0x0000, 0x0000,
    0x0000, 0x00c0, 0x00c0, 0x0000, 0x0000, 0x0000, 0x0300, 0x0000, 0x0000};

int cbstat_item_get_condition(ItemSlot far *slot) {
    int condition;
    ItemRecord far *item_rec;

    item_rec = itemtbl_record_ptr(slot);
    condition = (item_rec->wFlags & 0x1000) != 0 ? slot->condition : 'd';
    if ((slot->flags & 0x10) != 0) {
        condition = '\0';
    }
    return condition;
}

static int far cbstat_actor_find_equipped_item(CombatActor *actor, ItemRecord far *item) {
    Actor far *actor_record;
    int i;
    int result;

    actor_record = actor->actor_record;
    result = 100;
    if (actor_record == (Actor far *)0) {
        return 0;
    }
    for (i = 0; i < (int)(unsigned char)actor_record->itemCount; i++) {
        if (((ItemSlot far *)(&actor_record[1]))[i].flags & 0x40) {
            if (itemtbl_record_ptr((ItemSlot far *)(&actor_record[1]) + i) == item) {
                result = cbstat_item_get_condition((ItemSlot far *)(&actor_record[1]) + i);
            }
        }
    }
    return result;
}

void cbstat_spell_tables_load(void) {
    IoFile *file;
    int count;

    file = bak_fopen("spellwea.dat", "rb");
    bak_fread(&count, 2, 1, file);
    g_pSpellWeaTable = galloc_safe_zcalloc((count << 1) * 3);
    bak_fread(g_pSpellWeaTable, 6, count, file);
    bak_fclose(file);
    file = bak_fopen("spellres.dat", "rb");
    bak_fread(&count, 2, 1, file);
    g_pSpellResTable = galloc_safe_zcalloc((count << 1) * 3);
    bak_fread(g_pSpellResTable, 6, count, file);
    bak_fclose(file);
}

void cbstat_spell_tables_free(void) {
    galloc_zfree(g_pSpellResTable);
    galloc_zfree(g_pSpellWeaTable);
}

int cbstat_char_bitmap_3w_test(int char_idx, int bit_idx) {
    int quotient;
    unsigned int mask;
    int result;

    quotient = bit_idx / 16;
    mask = 1 << (bit_idx % 16);
    if ((((unsigned int *)g_pSpellResTable)[char_idx * 3 + quotient] & mask) == 0)
        result = 0;
    else
        result = 1;
    return result;
}

int cbstat_char_bitmap_3w_test_170c(int char_idx, int bit_idx) {
    int quotient = bit_idx / 16;
    int mask = 1 << (bit_idx % 16);
    int result;

    if (!(((unsigned int *)g_pSpellWeaTable)[char_idx * 3 + quotient] & mask))
        result = 0;
    else
        result = 1;
    return result;
}

unsigned int cbstat_actor_class_table_1802(CombatActor *actor) {
    return g_aClassCombatGroup[actor->inner->class_id];
}

int far cbstat_apply_proficiency_bonus(CombatActor *actor, int value, unsigned int proficiency_mask) {
    unsigned int entry;
    entry = g_aClassProficiencyMask[actor->inner->class_id];
    if ((entry & proficiency_mask) != 0) {
        value = value + (value >> 1);
    }
    return value;
}

int cbstat_apply_weakness_penalty(CombatActor *actor, int value, unsigned int weakness_mask) {
    unsigned int entry;
    entry = g_aClassWeaknessMask[actor->inner->class_id];
    if ((entry & weakness_mask) != 0) {
        value = value >> 1;
    }
    return value;
}

void far cbstat_apply_drain_tick(CombatActor *actor) {
    if ((g_aClassWeaknessMask[actor->inner->class_id] & 1) == 0) {
        if (cbstat_damage_apply_protection(actor, 1, 0x80) != 0) {
            actor->inner->flags |= CAF_POISON;
            stat_combatant_apply_delta(actor, 2, RNDR(10, 59));
        }
    }
}

unsigned int cbstat_armor_coverage_mask(CombatActor *combat_actor) {
    Actor far *actor_record;
    ItemSlot far *slot;
    ItemRecord far *item_rec;
    int i;
    unsigned int mask;

    mask = 0x580;
    actor_record = combat_actor->actor_record;
    i = 0;
    while (i < (int)(unsigned char)actor_record->itemCount) {
        if (((ItemSlot far *)(&actor_record[1]))[i].flags & 0x40) {
            item_rec = itemtbl_record_ptr((ItemSlot far *)(&actor_record[1]) + i);
            if (item_rec->wCategory == 1) {
                slot = (ItemSlot far *)(&actor_record[1]) + i;
                if (slot->flags & 0x2000) {
                    mask |= 0x800;
                }
                if (slot->flags & 0x4000) {
                    mask |= 0x800;
                }
                if (slot->flags & 0x8000) {
                    mask |= 0x800;
                }
                if (slot->flags & 0x80) {
                    mask |= 1;
                }
                if (slot->flags & 0x100) {
                    mask |= 4;
                }
                if (slot->flags & 0x200) {
                    mask |= 4;
                }
                if (slot->flags & 0x400) {
                    mask |= 2;
                }
                if (slot->flags & 0x800) {
                    mask |= 0x10;
                }
                if (slot->flags & 0x1000) {
                    mask |= 0x20;
                }
                break;
            }
        }
        i++;
    }
    return mask;
}

int far cbstat_scale_base_stat_pct(CombatActor *actor, int percent) {
    int result;
    int base;

    base = combat_actor_stat_percent(actor, 0);
    result = (percent * base + 90) / 100;
    return result;
}

int cbstat_apply_equipped_item_mult(CombatActor *actor, int value, int category) {
    int result;
    Actor far *actor_record;
    ItemSlot far *slot;
    ItemRecord far *item_rec;
    int i;

    result = value;
    actor_record = actor->actor_record;
    if (actor_record == (Actor far *)0) {
        return 0;
    }
    i = 0;
    while (i < (int)(unsigned char)actor_record->itemCount) {
        if (((ItemSlot far *)(&actor_record[1]))[i].flags & 0x40) {
            item_rec = itemtbl_record_ptr((ItemSlot far *)(&actor_record[1]) + i);
            if (item_rec->wCategory == category) {
                slot = (ItemSlot far *)(&actor_record[1]) + i;
                if (slot->flags & 0x2000) {
                    result = value * 0x69 / 100;
                }
                if (slot->flags & 0x4000) {
                    result = value * 0x6e / 100;
                }
                if (slot->flags & 0x8000) {
                    result = value * 0x73 / 100;
                }
                break;
            }
        }
        i++;
    }
    return result;
}

static int far cbstat_compute_defense_value(CombatActor *actor) {
    int value;

    if (combatenc_actor_can_act(actor, 0) != 0) {
        value = (int)stat_actor_get(actor, 4, 0) >> 2;
    } else {
        value = 0;
    }
    value = cbstat_apply_equipped_item_mult(actor, value, 4);
    if (value > 0x62) {
        value = 0x62;
    }
    if (value < 0) {
        value = 0;
    }
    return value;
}

int cbstat_damage_apply_protection(CombatActor *actor, int damage, int damage_type) {
    Actor far *actor_record;
    int i;
    ItemSlot far *slot;
    ItemRecord far *item_rec;
    int pct;

    pct = 0;
    actor_record = actor->actor_record;
    i = 0;
    while (i < (int)(unsigned char)actor_record->itemCount) {
        if (((ItemSlot far *)(&actor_record[1]))[i].flags & 0x40) {
            item_rec = itemtbl_record_ptr((ItemSlot far *)(&actor_record[1]) + i);
            if (item_rec->wCategory == 4) {
                slot = (ItemSlot far *)(&actor_record[1]) + i;
                if ((slot->flags & 0x80) && damage_type == 0x80) {
                    pct = 100;
                }
                if ((slot->flags & 0x100) && damage_type == 0x200) {
                    pct = 100;
                }
                if ((slot->flags & 0x200) && damage_type == 0x200) {
                    pct = 100;
                }
                if ((slot->flags & 0x400) && damage_type == 0x400) {
                    pct = 100;
                }
                if ((slot->flags & 0x800) && damage_type == 0x800) {
                    pct = 100;
                }
                if ((slot->flags & 0x1000) && damage_type == 0x1000) {
                    pct = 100;
                }
                break;
            }
        }
        i++;
    }
    if (pct != 0) {
        damage -= (damage * pct) / 100;
    }
    return damage;
}

int far cbstat_armor_absorption_by_class(CombatActor *attacker, CombatActor *defender,
                                         int attack_type) {
    int i;
    Actor far *actor_record;
    ItemSlot far *slot;
    ItemRecord far *item_rec;
    int base;
    int damage;
    int damage_type;

    damage = 0;
    damage_type = 0;
    actor_record = attacker->actor_record;
    i = 0;
    while (i < (int)(unsigned char)actor_record->itemCount) {
        if (((ItemSlot far *)(&actor_record[1]))[i].flags & 0x40) {
            item_rec = itemtbl_record_ptr((ItemSlot far *)(&actor_record[1]) + i);
            if (attack_type != 0) {
                base = item_rec->nThrust_damage;
            } else {
                base = item_rec->nSwing_damage;
            }
            if (item_rec->wCategory == 1) {
                slot = (ItemSlot far *)(&actor_record[1]) + i;
                if (slot->flags & 0x80) {
                    damage = 10;
                    damage_type = 0x80;
                }
                if (slot->flags & 0x100) {
                    damage = (base * 0x4b) / 100;
                    damage_type = 0x100;
                }
                if (slot->flags & 0x200) {
                    damage = base;
                    damage_type = 0x200;
                }
                if (slot->flags & 0x400) {
                    damage = base >> 1;
                    damage_type = 0x400;
                }
                if (slot->flags & 0x800) {
                    damage = base << 1;
                    damage_type = 0x800;
                }
                if (slot->flags & 0x1000) {
                    damage = (base * 0x4b) / 100;
                    damage_type = 0x1000;
                }
                goto LAB_077a;
            }
        }
        i++;
    }
LAB_077a:
    if (damage_type != 0) {
        damage = cbstat_damage_apply_protection(defender, damage, damage_type);
    }
    return damage;
}

int far cbstat_compute_attack_damage(ItemRecord far *weapon, CombatActor *attacker,
                                     CombatActor *defender, int attack_type) {
    int mult;
    int damage;

    damage = stat_actor_get(attacker, 3, 0);
    if (weapon != (ItemRecord far *)0) {
        mult = cbstat_actor_find_equipped_item(attacker, weapon);
        if (attack_type != 0)
            damage = (weapon->nThrust_damage * mult) / 100 + damage;
        else
            damage = (weapon->nSwing_damage * mult) / 100 + damage;
    } else {
    }
    damage += cbstat_armor_absorption_by_class(attacker, defender, attack_type);
    if (defender->inner->class_id == 0x12 || defender->inner->class_id == 0x15)
        if (itemtbl_find_by_full_record(weapon) == 0x16)
            damage <<= 1;
    if (damage < 1)
        damage = 1;
#ifdef V102CD
    if (damage > 0xff)
        damage = 0xff;
#endif
    return damage;
}

ItemRecord far *cbstat_find_intact_equip_cat(CombatActor *actor, int category) {
    Actor far *actor_record;
    ItemRecord far *pItem;
    int altcategory;
    int i;

    actor_record = actor->actor_record;
    altcategory = (category == 1) ? 3 : category;
    if (actor_record == (Actor far *)0) {
        return (ItemRecord far *)0;
    }
    for (i = 0; i < (int)(unsigned char)actor_record->itemCount; i++) {
        if (((ItemSlot far *)(&actor_record[1]))[i].flags & 0x40) {
            pItem = itemtbl_record_ptr((ItemSlot far *)(&actor_record[1]) + i);
            if (pItem->wCategory == category || pItem->wCategory == altcategory) {
                if (cbstat_item_get_condition((ItemSlot far *)(&actor_record[1]) + i) > 0) {
                    return pItem;
                }
            }
        }
    }
    return (ItemRecord far *)0;
}

void cbstat_damage_equipped_items(CombatActor *actor, int category, int severity) {
    Actor far *actor_record;
    ItemRecord far *item_rec;
    int altcategory;
    int break_amount;
    unsigned int new_condition;
    int i;

    actor_record = actor->actor_record;
    altcategory = (category == 1) ? 3 : category;
    if (actor_record == (Actor far *)0) {
        return;
    }
    i = 0;
    while (i < (int)(unsigned char)actor_record->itemCount) {
        if (((ItemSlot far *)(&actor_record[1]))[i].flags & 0x40) {
            item_rec = itemtbl_record_ptr((ItemSlot far *)(&actor_record[1]) + i);
            if (((item_rec->wCategory == category) || (item_rec->wCategory == altcategory)) &&
                (item_rec->wFlags & 0x1000)
#ifndef V102CD
                && (RND(100) < item_rec->wWeapon_break_chance_pct)
#endif
            ) {
#ifdef V102CD
                ((ItemSlot far *)(&actor_record[1]))[i].flags |= 0x4;
                if (RND(100) < item_rec->wWeapon_break_chance_pct) {
#endif
                    break_amount = (item_rec->nWeapon_break_amount > 1)
                                       ? RND(item_rec->nWeapon_break_amount - 1) + 1
                                       : 1;
                    new_condition = (unsigned int)((ItemSlot far *)(&actor_record[1]))[i].condition -
                                    (int)((long)(break_amount * severity) / 0x100L);
                    if ((item_rec->wCategory == 2) && (new_condition <= RND(0x32))) {
                        audio_play(0x43);
                        new_condition = 0;
                    }
#ifdef V102CD
                    ((ItemSlot far *)(&actor_record[1]))[i].flags |= 0x20;
#else
                    ((ItemSlot far *)(&actor_record[1]))[i].flags |= 0x24;
#endif
                    if ((int)new_condition < (int)item_rec->wCondition_floor) {
                        new_condition = item_rec->wCondition_floor;
                    }
                    if ((int)new_condition <= 0) {
                        ((ItemSlot far *)(&actor_record[1]))[i].flags |= 0x10;
                    }
                    ((ItemSlot far *)(&actor_record[1]))[i].condition = (unsigned char)new_condition;
#ifdef V102CD
                }
#endif
            }
        }
        i++;
    }
    return;
}

int far cbstat_magic_attack_bonus(CombatActor *actor) {
    int interim;
    int class_group;
    int modifier;
    ItemRecord far *item_rec;
    Actor far *actor_record;
    int i;

    actor_record = actor->actor_record;
    i = 0;
    while (i < (int)(unsigned char)actor_record->itemCount) {
        if (((ItemSlot far *)(&actor_record[1]))[i].flags & 0x40) {
            item_rec = itemtbl_record_ptr((ItemSlot far *)(&actor_record[1]) + i);
            if (item_rec->wCategory & 4) {
                interim = (cbstat_item_get_condition((ItemSlot far *)(&actor_record[1]) + i) *
                           item_rec->nAttack_or_range_long) /
                          100;
                class_group = cbstat_actor_class_table_1802(actor);
                modifier = g_aClassGroupModifier[class_group][item_rec->wRace_mask];
                interim = (interim * (modifier + 100)) / 100;
                return interim;
            }
        }
        i++;
    }
    return 0;
}

int far cbstat_magic_defense_bonus(CombatActor *actor) {
    int class_group;
    int modifier;
    ItemRecord far *item_rec;
    Actor far *actor_record;
    int i;
    int result;

    actor_record = actor->actor_record;
    if (actor_record == (Actor far *)0) {
        return 0;
    }
    result = (int)stat_actor_get(actor, 4, 0) >> 2;
    i = 0;
    while (i < (int)(unsigned char)actor_record->itemCount) {
        if (((ItemSlot far *)(&actor_record[1]))[i].flags & 0x40) {
            item_rec = itemtbl_record_ptr((ItemSlot far *)(&actor_record[1]) + i);
            if (item_rec->wCategory & 4) {
                result =
                    result + (cbstat_item_get_condition((ItemSlot far *)(&actor_record[1]) + i) *
                              item_rec->nDefense_or_range_close) /
                                 100;
                class_group = cbstat_actor_class_table_1802(actor);
                modifier = g_aClassGroupModifier[class_group][item_rec->wRace_mask];
                result = (result * (modifier + 100)) / 100;
                if (result > 0x62) {
                    result = 0x62;
                }
                break;
            }
        }
        i++;
    }
    return result;
}

int cbstat_to_hit_roll(CombatActor *attacker, CombatActor *target, int roll,
                       ItemRecord far *weapon_item) {
    unsigned int class_idx;
    int table_acc;
    unsigned threshold;
    int defense;
    int accuracy;
    int roll_r;
    int result;

    roll_r = roll;
    threshold = RND(100);
    if (target->inner->flags & CAF_PARRY) {
        threshold += 0x14;
    }
    if (weapon_item != (ItemRecord far *)0) {
        class_idx = cbstat_actor_class_table_1802(attacker);
        table_acc = g_aClassGroupModifier[class_idx][weapon_item->wRace_mask];
        roll_r = (roll_r * (table_acc + 100)) / 100;
        roll_r = (roll_r * cbstat_inv_item_condition_rec(weapon_item, attacker)) / 100;
    } else {
        roll_r = 0;
    }
    accuracy = stat_actor_get(attacker, 6, 0) + roll_r;
    if (weapon_item != (ItemRecord far *)0) {
        accuracy = cbstat_apply_equipped_item_mult(attacker, accuracy, 1);
    }
    defense = cbstat_compute_defense_value(target);
    accuracy -= defense;
    if (accuracy < 2) {
        accuracy = 2;
    }
    if (0x62 < accuracy) {
        accuracy = 0x62;
    }
    if ((int)threshold < accuracy) {
        cbstat_damage_equipped_items(target, 4, 0x100);
        result = 1;
    } else {
        result = 0;
    }
    return result;
}

int cbstat_inv_item_condition_rec(ItemRecord far *target_far, CombatActor *actor) {
    Actor far *actor_record;
    int i;
    int condition;
    ItemRecord far *rec;

    actor_record = actor->actor_record;
    for (i = 0; i < (int)(unsigned int)actor_record->itemCount; i++) {
        rec = itemtbl_record_ptr((ItemSlot far *)(&actor_record[1]) + i);
        if (rec == target_far)
            break;
    }
    condition = cbstat_item_get_condition((ItemSlot far *)(&actor_record[1]) + i);
    return condition;
}
