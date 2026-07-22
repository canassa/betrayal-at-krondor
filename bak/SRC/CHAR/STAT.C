#include "globals.h"
#include "structs.h"
#include "SRC/WORLD/ACTOR/ACTOR.H"

#include "SRC/CHAR/STAT.H"
#include "SRC/GAME/GSTATE.H"
#include "SRC/SCREENS/ITEMTBL.H"

void stat_apply_modifier(ushort *mod, int *stat) {
    if (((*mod & 0x100) == 0) || (g_wInCombatMode != 0)) {
        if (((*mod & 0x200) != 0) && (*(unsigned long *)(mod + 5) < g_gameState.game_time)) {
            *mod = 0;
        }
        if (*mod != 0) {
            if ((*mod & 0x400) == 0) {
            }
            if ((*mod & 0x800) != 0) {
                *stat = (long)(int)(*stat * (mod[2] + 100)) / 100;
            } else {
                *stat += (short)mod[2];
            }
        }
    }
}

void stat_actor_recalc_equip_bonuses(CombatActor *actor) {
    int statIdx;
    int statVal;
    Actor far *actorRec;
    ItemRecord far *itemRec;
    int i;

    actorRec = actor->actor_record;
    for (statIdx = 0; statIdx < 0x10; statIdx++)
        actor->stats[statIdx].perm_mod = 0;
    for (i = 0; (int)(unsigned int)actorRec->itemCount > i; i++) {

        itemRec = itemtbl_record_ptr_by_id(
            (unsigned int)*(unsigned char far *)(ACTOR_ITEMS(actorRec) + (unsigned int)i));
        if (itemRec->wPlayer_stat_mask != 0) {
            statVal = itemRec->nStat_value;
            statIdx = 0;
            do {
                if (itemRec->wPlayer_stat_mask & (1U << statIdx))
                    actor->stats[statIdx].perm_mod = actor->stats[statIdx].perm_mod + (char)statVal;
                statIdx++;
            } while (statIdx < 0x10);
        }
    }
}

ConditionInfo far g_aConditionInfo[7] = {
    {"Sick", 1, -1, {0, 0, 0, 0}},     {"Plagued", 1, -2, {0, 0, 0, 0}},
    {"Poisoned", 1, -3, {0, 0, 0, 0}}, {"Drunk", -2, 0, {-14, -60, 0, 0}},
    {"Healing", -3, 1, {0, 0, 0, 0}},  {"Starving", 0, -2, {0, 0, 0, 0}},
    {"Near-death", 0, 0, {0, 0, 0, 0}}};

uint stat_actor_get(CombatActor *actor, int stat_idx, int mode) {
    uint value;
    int rowIdx;
    uint n;
    uint statMask;
    ushort *modPtr;
    ConditionInfo far *cond;
    int rank;
    uint ratio;
    uint wMax;
    /* The local `a = actor` copy is the mechanism that forces `actor` into the
     * persistent DI register; `st` takes SI. Declaration order (st then a) fixes
     * SI/DI. */
    register StatSlot *st;
    register CombatActor *a = actor;

    rowIdx = a->cParty_slot + -1;
    st = &a->stats[stat_idx];
    if (stat_idx == 0x10) {
        return stat_actor_get(a, 0, mode) + stat_actor_get(a, 1, mode);
    }
    if (mode == 3) {
        return (uint)st->base;
    }
    if (mode == 1) {
        return (uint)st->max;
    }

    value = (st->cached = st->base);
    if (st->perm_mod != 0) {
        value += (int)st->perm_mod;
        if ((int)value < 0) {
            value = 0;
        }
        st->cached = (uchar)value;
    }
    if (a->cParty_slot != 0) {
        statMask = 1 << (byte)stat_idx;
        n = 0;
        modPtr = (ushort *)&g_gameState.aActorStatModifiers[rowIdx][0];
        while ((int)n < 8) {
            if ((*modPtr != 0) && ((modPtr[1] & statMask) != 0)) {
                stat_apply_modifier(modPtr, (int *)&value);
            }
            n++;
            modPtr += 7;
        }
        n = 0;
        cond = g_aConditionInfo;
        while ((int)n < 7) {
            if (0 < (rank = (char)g_gameState.abActorStatusRanks[rowIdx][n])) {
                if ((cond->pExtra[0] & statMask) != 0) {
                    value =
                        (uint)(((long)(int)value * ((long)(cond->pExtra[1] * rank) / 100 + 100)) /
                               100);
                }
                if ((cond->pExtra[2] & statMask) != 0) {
                    value =
                        (uint)(((long)(int)value * ((long)(cond->pExtra[3] * rank) / 100 + 100)) /
                               100);
                }
            }
            n++;
            cond += 1;
        }
    }
    if (mode != 4) {
        ratio = (uint)g_abStatRatio[stat_idx];
        if (ratio != 0) {
            n = (uint)a->stats[0].base;
            wMax = (uint)a->stats->max;
            if (1 < (int)ratio) {
                n = (int)(n + wMax * (ratio - 1)) / (int)ratio;
            }
            if (wMax != 0) {
                value = (int)((wMax + value * n) - 1) / (int)wMax;
            } else {
                value = 0;
            }
        }
    }
    if (st->max == 0) {
        value = 0;
    }
    if ((int)value < (int)(uint)g_abStatMin[stat_idx]) {
        value = (uint)g_abStatMin[stat_idx];
    }
    if ((int)g_awStatMax[stat_idx] < (int)value) {
        value = g_awStatMax[stat_idx];
    }
    st->cached = (uchar)((int)value > 0xfa ? 0xfa : value);
    return value;
}

uint far stat_combatant_modify(CombatActor *actor, int stat_idx, long delta, int mode) {
    StatSlot *slot;
    int origBase;
    int rowIdx;
    uint sum;
    uint uMaxSum;

    slot = actor->stats + stat_idx;
    origBase = (uint)slot->base;
    rowIdx = actor->cParty_slot + -1;
    if (stat_idx == 0x10) {
        uint target;
        int rank;
        sum = (uint)actor->stats[1].base + (uint)actor->stats[0].base;
        uMaxSum = (uint)(actor->stats + 1)->max + (uint)actor->stats->max;
        target = (uint)((long)(int)(mode * uMaxSum) / 100L);
        if (actor->cParty_slot != 0) {
            rank = (char)g_gameState.abActorStatusRanks[rowIdx][6];
            if (rank != 0) {
                target = ((100 - rank) * 0x1e) / 100 + 1;
            }
        }
        if (0 < delta) {
            if ((int)sum < (int)target) {
                sum = sum + (int)(delta / 0x100);
                if ((int)sum > (int)target) {
                    sum = target;
                }
            }
        } else {
            sum = sum + (int)(delta / 0x100);
            if ((int)sum <= 0) {
                sum = 0;
                if (actor->cParty_slot != 0) {
                    stat_combatant_apply_delta(actor, 6, 100);
                }
            }
        }
        if ((int)(uint)actor->stats->max < (int)sum) {
            actor->stats[1].base = (uchar)sum - actor->stats->max;
            actor->stats[0].base = actor->stats->max;
        } else {
            actor->stats[1].base = 0;
            actor->stats[0].base = (uchar)sum;
        }
        return sum;
    }
    if (slot->max == 0) {
        return 0;
    }
    if (mode == 3) {
        int ratioVal;
        ratioVal = (uint)g_abStatRatioBase[stat_idx] +
                   (int)(((uint)g_abStatRatioMax[stat_idx] - (uint)g_abStatRatioBase[stat_idx]) *
                         (uint)slot->base) /
                       100;
        if (ratioVal > 0) {
            delta = (delta == 0) ? (long)ratioVal : delta * ratioVal;
        } else {
            delta = 0;
        }
    } else if (mode == 2) {
        delta = (int)(100 - (uint)slot->base) * delta;
    } else if (mode == 1) {
        delta = ((int)(uint)slot->base * delta) / 100;
    }

    if ((actor->cParty_slot != 0) &&
        (gstate_event_read(SKILL_SELECTED(rowIdx * 0x11 + stat_idx)) != 0)) {
        delta += (delta * (short)g_gameState.aConditionTickAdvance[rowIdx]) / 0x34;
    }
    delta += (int)(uint)slot->frac;
    slot->frac = (uchar)(delta % 0x100);
    /* Magnitude compare against the underflow amount. The inner nested ternary is
     * the abs()-macro expansion (x<0 ? (x==INT_MIN ? INT_MAX : -x) : x). When the
     * decrement would drop base below zero, base is pinned to 0 and control joins
     * the shared clamp/finalize tail below, skipping the normal base += (delta/0x100)
     * add. */
    if (delta / 0x100 < 0) {
        if ((long)(ulong)slot->base <
            (delta / 0x100 < 0 ? (delta / 0x100 == -0x8000L ? 0x7fffL : -(delta / 0x100))
                               : delta / 0x100)) {
            slot->base = 0;
            goto clamp_finalize;
        }
    }
    slot->base = slot->base + (char)(delta / 0x100);
clamp_finalize:
    if (slot->base < g_abStatClampMin[stat_idx]) {
        slot->base = g_abStatClampMin[stat_idx];
    }
    if (slot->base > g_abStatClampMax[stat_idx]) {
        slot->base = g_abStatClampMax[stat_idx];
    }
    if (slot->max < slot->base) {
        slot->max = slot->base;
    }
    if (((actor->cParty_slot != 0) && ((uint)slot->base != (uint)origBase)) && (stat_idx != 0x10)) {
        if ((1 < stat_idx) || (origBase < slot->base)) {

            gstate_event_write(SKILL_IMPROVED(rowIdx * 0x11 + stat_idx), 1);
        }
        if (origBase < slot->base) {
            g_gameState.bPartyDirtyFlags |= 1;
        }
    }
    return (uint)slot->base;
}

uint far stat_party_find_extreme(int stat_id, int mode, short *result_out) {
    int member_idx;
    uint cur_val;
    uint extreme;
    int i;

    if (stat_id == 0xf) {
        i = 0;
        extreme = 30000;
        for (; i < g_gameState.party_count; i++) {
            member_idx = g_gameState.party_roster[i];
            cur_val = stat_actor_get(&g_gameState.party_members[member_idx], stat_id, mode);
            if ((int)cur_val < (int)extreme) {
                extreme = cur_val;
                g_gameState.nEvtArgStat = member_idx;
            }
        }
    } else {
        i = extreme = 0;
        for (; i < g_gameState.party_count; i++) {
            member_idx = g_gameState.party_roster[i];
            cur_val = stat_actor_get(&g_gameState.party_members[member_idx], stat_id, mode);
            if ((int)cur_val > (int)extreme) {
                extreme = cur_val;
                g_gameState.nEvtArgStat = member_idx;
            }
        }
    }
    if (result_out != (short *)0) {
        *result_out = g_gameState.nEvtArgStat;
    }
    return extreme;
}

void far stat_party_broadcast_status_op(int stat_idx, long delta, int mode) {
    int i;

    for (i = 0; i < g_gameState.party_count; i++) {
        stat_combatant_modify(&g_gameState.party_members[g_gameState.party_roster[i]], stat_idx,
                              delta, mode);
    }
}

uint stat_combatant_apply_delta(CombatActor *actor, int stat_idx, int amount) {
    int slot_idx;
    int new_val;
    int old_val;

    slot_idx = actor->cParty_slot - 1;
    if (actor->cParty_slot != 0 && amount != 0) {
        new_val = (signed char)g_gameState.abActorStatusRanks[slot_idx][stat_idx];
        old_val = new_val;
        new_val = new_val + amount;
        if (new_val < 0) {
            new_val = 0;
        }
        if (100 < new_val) {
            new_val = 100;
        }
        g_gameState.abActorStatusRanks[slot_idx][stat_idx] = (char)new_val;
        if (stat_idx != 4 && stat_idx != 3 && (stat_idx != 6 || g_wInCombatMode == 0)) {
            if (old_val == 0 && new_val != 0) {

                gstate_event_write(CONDITION(slot_idx * 7 + stat_idx), 1);
                g_gameState.bPartyDirtyFlags |= 2;
            } else if (old_val != 0 && new_val == 0) {
                gstate_event_write(CONDITION(slot_idx * 7 + stat_idx), 0);
            }
        }
        if (stat_idx != 6)
            return;
        for (stat_idx = 0, g_gameState.bCombatExitRequest = 1; stat_idx < g_gameState.party_count;
             stat_idx++) {
            if (!(signed char)
                     g_gameState.abActorStatusRanks[g_gameState.party_roster[stat_idx]][6]) {
                g_gameState.bCombatExitRequest = 0;
            }
        }
        if (0 < amount) {
            for (stat_idx = 0; stat_idx < 7; stat_idx++) {
                if (stat_idx != 6) {
                    g_gameState.abActorStatusRanks[slot_idx][stat_idx] = 0;
                    gstate_event_write(CONDITION(slot_idx * 7 + stat_idx), 0);
                }
            }
            actor->stats[1].base = actor->stats[0].base = 0;
            return stat_combatant_modify(actor, 0x10, 0x7fff, 100);
        }
    }
}

void far stat_modifier_table_insert(CombatActor *actor, ActorStatModifier *pNewMod) {
    int bestCost;
    int i;
    int row;
    int cost;
    ActorStatModifier *pBest;
    ActorStatModifier *pSlot;

    row = actor->cParty_slot - 1;
    if (!actor->cParty_slot)
        return;
    i = 0;

    bestCost = 999;
    pBest = (ActorStatModifier *)0;
    for (pSlot = &g_gameState.aActorStatModifiers[row][0]; i < 8; pSlot++) {
        cost = pSlot->wMaskFlags & 0xff;
        if (pSlot->wMaskFlags == 0) {
            pBest = pSlot;
            break;
        }
        if (cost < bestCost) {
            pBest = pSlot;
            bestCost = cost;
        }
        i++;
    }
    *pBest = *pNewMod;
}

void far stat_actor_clear_mods_mask(CombatActor *actor, ushort mask) {
    int party_slot_idx;
    int i;

    party_slot_idx = actor->cParty_slot - 1;
    if (actor->cParty_slot != 0) {
        i = 0;
        do {
            if (g_gameState.aActorStatModifiers[party_slot_idx][i].wMaskFlags & mask) {
                g_gameState.aActorStatModifiers[party_slot_idx][i].wMaskFlags = 0;
            }
            i++;
        } while (i < 8);
    }
}

int far stat_party_all_above_pct(int percent) {
    int memberIdx;
    uint current;
    uint max_val;
    int threshold;
    int i;

    i = 0;
    while (i < g_gameState.party_count) {
        memberIdx = g_gameState.party_roster[i];
        current = stat_actor_get(&g_gameState.party_members[memberIdx], 0x10, 3);
        max_val = stat_actor_get(&g_gameState.party_members[memberIdx], 0x10, 1);
        threshold = (int)((long)(percent * (int)max_val) / 100L);
        if ((int)current < threshold) {
            return 0;
        }
        i++;
    }
    return 1;
}

void far stat_combatant_heal(CombatActor *combatant, int amount_pct) {
    long delta;
    int stat_idx;

    if (amount_pct == 100) {
        g_gameState.dwLastActionTimeSnapshot = g_gameState.game_time;
        stat_idx = 0;
        do {
            stat_combatant_apply_delta(combatant, stat_idx, -100);
            stat_idx++;
        } while (stat_idx < 7);
    }
    stat_combatant_modify(combatant, 0x10, 0x7fff, 100);
    if (amount_pct < 100) {
        delta = (long)(int)stat_actor_get(combatant, 0x10, 0) * -20L / 100L;
        stat_combatant_modify(combatant, 0x10, delta << 8, 100);
    }
}

void far stat_party_heal_all(int amount) {
    int i;

    for (i = 0; i < g_gameState.party_count; i++) {
        stat_combatant_heal(&g_gameState.party_members[g_gameState.party_roster[i]], amount);
    }
}
