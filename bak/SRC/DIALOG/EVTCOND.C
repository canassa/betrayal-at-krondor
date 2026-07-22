#include <dos.h>
#include <stdlib.h>
#include "globals.h"
#include "structs.h"

#include "SRC/DIALOG/EVTCOND.H"
#include "SRC/SYS/RAND.H"
#include "SRC/GAME/GSTATE.H"
#include "SRC/CHAR/STAT.H"
#include "SRC/GAME/TIMERPL.H"
#include "SRC/DIALOG/DIALOG.H"
#include "SRC/SCREENS/CMBINV.H"
#include "SRC/SCREENS/ITEMTBL.H"
#include "SRC/SCREENS/ITEMUSE.H"
#include "SRC/WORLD/ACTOR/ACTSPAWN.H"
#include "SRC/WORLD/ENC/RGNENC.H"


void evtcond_pty_inv_repair_cnt(int *count_out, int *repair_out, int do_repair) {
    int member;
    int i;
    int loaded;
    Actor far *actor;
    ItemSlot far *slot;

    loaded = itemtbl_load();
    *count_out = *repair_out = 0;
    for (member = 0; member < g_gameState.party_count; member++) {
        actor = gstate_party_member_record(member)->actor_record;
        i = 0;
        slot = ACTOR_ITEMS(actor);
        for (; i < actor->itemCount; i++, slot++) {
            if (itemtbl_record_ptr(slot)->wCategory == 4) {
                if (slot->condition < 100) {
                    (*repair_out)++;
                    if (do_repair != 0) {
                        slot->condition = 100;
                        slot->flags &= ~0x20;
                    }
                }
            }
            if (slot->item_id == '0' && slot->condition >= 0x46) {
                (*count_out)++;
            }
        }
    }
    g_gameState.lEvtArgValue = (long)*repair_out;
    g_gameState.lEvtArgGoldCost = g_gameState.lEvtArgGoldCost * g_gameState.lEvtArgValue;
    if (loaded != 0) {
        itemtbl_free();
    }
}

int evtcond_range_d_read_handler(uint cond) {
    int i;
    int j;
    int c4res;

    if (cond >= 0xc738 && cond < 0xc79c) {
        Actor far *actor;
        ItemSlot far *slot;
        /* 0x38c8 arithmetic bias mapping the event-condition id
           into the item-condition value space (cond compared to slot->condition) */
        cond += 0x38c8;
        for (i = 0; i < (int)g_gameState.party_count; i++) {
            actor = g_gameState.party_members[g_gameState.party_roster[i]].actor_record;
            j = 0;
            slot = ACTOR_ITEMS(actor);
            for (; j < (int)actor->itemCount; j++, slot++) {
                if (slot->item_id == 'x' && (uint)slot->condition == cond) {
                L_match:
                    return 1;
                }
            }
        }
        goto L_def0;
    }
    switch (cond) {
    case 0x9c42: /* idx1 */
        for (i = 0; i < (int)g_gameState.party_count; i++) {
            if (g_gameState.abActorStatusRanks[g_gameState.party_roster[i]][1] != 0)
                return 1;
        }
        goto L_def0;
    case 0x9c41: /* idx0 */
        for (i = 0; i < (int)g_gameState.party_count; i++) {
            if (!(char)g_gameState.abActorStatusRanks[g_gameState.party_roster[i]][5])
                goto L_def0;
        }
        goto L_match;
    case 0x9c43: /* idx2 */
        evtcond_pty_inv_repair_cnt(&i, &j, 0);
        return i > 5;
    case 0x9c44: /* idx3 */
        evtcond_pty_inv_repair_cnt(&i, &j, 0);
        return j > 0;
    case 0x9c45: { /* idx4 */
        Actor far *actor;
        c4res = 1;
        actor = actorspawn_objfixed(5, 0x16b2fbL, 0x111547L);
        if (itemtbl_inv_count_by_kind(actor, 0x49) == 0)
            c4res = 0;
        actorspawn_destroy_and_persist(actor);
        actor = actorspawn_objfixed(5, 0x16b2fbL, 0x110f20L);
        if (itemtbl_inv_count_by_kind(actor, 0x49) == 0)
            c4res = 0;
        actorspawn_destroy_and_persist(actor);
        actor = actorspawn_objfixed(5, 0x16b33aL, 0x11083cL);
        if (itemtbl_inv_count_by_kind(actor, 0x49) == 0)
            c4res = 0;
        actorspawn_destroy_and_persist(actor);
        return c4res;
    }
    case 0x9c46: { /* idx5 */
        int loaded;
        loaded = itemtbl_load();
        i = cmbinv_find_equipped_in_category(g_gameState.party_members[CHR_OWYN].actor_record, 3) !=
            0;
        j = cmbinv_find_equipped_in_category(g_gameState.party_members[CHR_GORATH].actor_record,
                                             1) != 0;
        if (loaded != 0)
            itemtbl_free();
        return i != 0 && j != 0;
    }
    case 0x9c49: /* idx8 */
        for (i = 0; i < (int)g_gameState.party_count; i++) {
            j = 0;
            do {
                if (j != 4 && g_gameState.abActorStatusRanks[g_gameState.party_roster[i]][j] != 0)
                    goto L_match;
                j++;
            } while (j < 7);
        }
        goto L_def0;
    case 0x9c4a: /* idx9 */
        if (evtcond_range_d_read_handler(0x9c49) != 0)
            goto L_match;
        for (i = 0; i < (int)g_gameState.party_count; i++) {
            if (stat_actor_get(gstate_party_member_record(i), 0x10, 0) !=
                stat_actor_get(gstate_party_member_record(i), 0x10, 1))
                goto L_match;
        }
        goto L_def0;
    case 0x9c4b: /* idx10 */
        for (i = 0; i < (int)g_gameState.party_count; i++) {
            if (itemtbl_inv_count_by_kind(gstate_party_member_record(i)->actor_record, 0x59) == 0)
                goto L_def0;
        }
        goto L_match;
    case 0x9c4c: { /* idx11 */
        Actor far *actor;
        int res;
        actor = actorspawn_objfixed(3, 0x13f560L, 0xf4ba0L);
        res = itemtbl_inv_count_by_kind(actor, 0x48);
        actorspawn_destroy_and_persist(actor);
        return res;
    }
    case 0x9c4d: { /* idx12 */
        Actor far *actor;
        int res;
        actor = actorspawn_objfixed(3, 0x13f560L, 0xf4ba0L);
        res = (itemtbl_inv_count_by_kind(actor, 0x49) != 0 ||
               itemtbl_inv_count_by_kind(actor, 0x4a) != 0);
        actorspawn_destroy_and_persist(actor);
        return res;
    }
    }
L_def0:
    return 0;
}

void evtcond_range_d_write_stub(uint event_id, uint value) {
    (void)event_id;
    (void)value;
    return;
}

void evtcond_dialog_action_dispatch(DdxOp far *action_record) {
    int temp;

    switch ((unsigned int)action_record->nA1) {
    case 0:
        g_gameState.nParty_gold = g_gameState.nParty_gold >= g_gameState.lEvtArgGoldCost
                                      ? g_gameState.nParty_gold - g_gameState.lEvtArgGoldCost
                                      : 0;
        break;
    case 1:
        g_gameState.nParty_gold += g_gameState.lEvtArgValue;
        break;
    case 2:
        evtcond_pty_inv_repair_cnt(&temp, &temp, 1);
        break;
    case 3:
        rgnenc_complete_consume((ulong)(unsigned int)action_record->nA2);
        break;
    case 4:
        rgnenc_mark_defended((ulong)(unsigned int)action_record->nA2);
        break;
    case 5: {
        Actor far *actor = actorspawn_objfixed(0, 0x14L, 0L);
        itemuse_actor_spawn_clone_inv(actor, 1, 2L, 3L);
        actorspawn_destroy_and_persist(actor);
    }

    case 6: {
        Actor far *actor = actorspawn_objfixed(0, 0x14L, 0L);
        itemuse_actor_spawn_clone_inv(actor, 1, 2L, 3L);
        actorspawn_destroy_and_persist(actor);
        break;
    }
    case 7:
        g_gameState.lEvtArgValue += (long)(unsigned int)action_record->nA2;
        break;
    case 8: {
        g_gameState.lEvtArgValue = RND((unsigned int)action_record->nA2);
        g_gameState.lEvtArgAuxValue = RND((unsigned int)action_record->nA3);
        if (g_gameState.lEvtArgValue > g_gameState.lEvtArgAuxValue) {

            temp =
                (int)(g_gameState.lEvtArgGoldCost * (long)(unsigned int)action_record->nA4 / 100);
            g_gameState.nEvtArgCount = 0;
            g_gameState.nParty_gold += temp;
            if (g_gameState.dwPopup_retry_state < (unsigned)temp) {
                g_gameState.dwPopup_retry_state = 0;
            } else {
                g_gameState.dwPopup_retry_state -= temp;
            }
        } else if (g_gameState.lEvtArgValue < g_gameState.lEvtArgAuxValue) {

            g_gameState.nEvtArgCount = 1;
            g_gameState.nParty_gold -= g_gameState.lEvtArgGoldCost;
            g_gameState.dwPopup_retry_state =
                g_gameState.dwPopup_retry_state + (g_gameState.dwPopup_retry_state < 0xea60
                                                       ? (unsigned)g_gameState.lEvtArgGoldCost
                                                       : 0);
        } else if (g_gameState.lEvtArgValue < g_gameState.lEvtArgAuxValue) {

            g_gameState.nEvtArgCount = 2;
        }
        break;
    }
    case 9: {
        int loaded = itemtbl_load();
        int slot;
        for (slot = 0; slot < g_gameState.party_count; slot++) {
            Actor far *actor = gstate_party_member_record(slot)->actor_record;
            int i = 0;
            ItemSlot far *islot = ACTOR_ITEMS(actor);
            for (; i < (int)actor->itemCount; i++, islot++) {
                if ((islot->flags & 0x40) != 0 && itemtbl_record_ptr(islot)->wCategory == 1) {
                    islot->condition = 100;
                    islot->flags &= 0x1fff;
                    islot->flags |= 0x8000;
                }
            }
        }
        if (loaded != 0) {
            itemtbl_free();
        }
        break;
    }
    case 10: {
        Actor far *actor = actorspawn_objfixed(0, 0x14L, 1L);
        Actor far *actor2 = actorspawn_objfixed(0, 0x1eL, 1L);
        itemuse_actor_spawn_clone_inv(actor, 0xf, 0x3cL, 3L);
        itemuse_actor_spawn_clone_inv(actor2, 0xf, 0x40L, 3L);
        actorspawn_destroy_and_persist(actor);
        actorspawn_destroy_and_persist(actor2);
        break;
    }
    case 11:
        if ((unsigned int)action_record->nA2 > g_gameState.dwPopup_retry_state) {
            g_gameState.dwPopup_retry_state = (unsigned int)action_record->nA2;
        }
        break;
    case 12:
        g_nHotspotActivateRequest = 1;
        break;
    case 13: {
        int i;
        for (i = 0; i < g_gameState.nTimerEventPoolCount; i++) {
            if (g_gameState.aTimerEventPool[i].bKind == 1 &&
                g_gameState.aTimerEventPool[i].wSub_id == 0) {
                g_gameState.aTimerEventPool[i].nValue = 0;
            }
        }
        timerpool_tick(0);
        break;
    }
    case 14: {
        Actor far *actor = actorspawn_objfixed(3, 0x13f560L, 0xf4ba0L);
        if (actor == (Actor far *)0) {
            return;
        }
        actor->itemCount = 0;
        actor->dirty_flag = 1;
        actorspawn_destroy_and_persist(actor);
        break;
    }
    case 15:
        stat_combatant_modify(&g_gameState.party_members[g_gameState.nEvtArgActor0],
                              (int)g_gameState.lEvtArgValue, 0x200L, 0);
        break;
    case 16: {
        int i;
        for (i = 0; i < 3; i++) {
            temp = g_gameState.party_members[CHR_OWYN].pSpellsKnown[i] |
                   g_gameState.party_members[CHR_PUG].pSpellsKnown[i];
            g_gameState.party_members[CHR_OWYN].pSpellsKnown[i] = temp;
            g_gameState.party_members[CHR_PUG].pSpellsKnown[i] = temp;
        }
        break;
    }
    }
}

void evtcond_pty_dirty_flags_process(void) {
    int member_idx;
    int slot_idx;
    unsigned int affected_members_mask;
    unsigned int affected_slots_mask;
    int affected_members_count;
    register int affected_slots_count;
    register unsigned int event_addr;

    affected_members_mask = 0;
    affected_slots_mask = 0;
    affected_members_count = 0;
    affected_slots_count = 0;
    if (g_gameState.bCombatExitRequest != 0) {
        return;
    }
    if ((g_gameState.bPartyDirtyFlags & 1) != 0) {
        for (member_idx = 0; member_idx < (int)g_gameState.party_count; member_idx++) {
            for (slot_idx = 2; slot_idx < 0x11; slot_idx++) {
                event_addr = g_gameState.party_roster[member_idx] * 0x11 + slot_idx;
                if (gstate_event_read(SKILL_IMPROVED(event_addr)) != 0) {
                    if ((affected_members_mask & (1 << member_idx)) == 0) {
                        affected_members_mask |= (1 << member_idx);
                        affected_members_count++;
                        g_gameState.nEvtArgActor0 = g_gameState.party_roster[member_idx];
                    }
                    if ((affected_slots_mask & (1 << slot_idx)) == 0) {
                        affected_slots_mask |= (1 << slot_idx);
                        affected_slots_count++;
                        g_gameState.lEvtArgAuxValue = (long)slot_idx;
                    }
                }
            }
        }
        if (affected_slots_count == 1 && g_gameState.lEvtArgAuxValue == 0xb) {
            affected_members_count = 3;
        }
        if (affected_members_count > 1) {
            dialog_play_record(affected_slots_count > 1 ? 0x200b31 : 0x200b30, 0);
        } else if (affected_slots_count != 0) {
            dialog_play_record(affected_slots_count > 1 ? 0x200b33 : 0x200b32, 0);
        }
    }
    if ((g_gameState.bPartyDirtyFlags & 2) != 0) {
        member_idx = 0;
        do {
            slot_idx = g_gameState.nEvtArgCount = 0;
            g_gameState.nEvtArgActor0 = g_gameState.nEvtArgActor1 = -1;
            for (; slot_idx < g_gameState.party_count; slot_idx++) {
                event_addr = CONDITION(g_gameState.party_roster[slot_idx] * 7 + member_idx);
                if (gstate_event_read(event_addr) != 0) {
                    gstate_event_write(event_addr, 0);
                    if (g_gameState.nEvtArgActor0 < 0) {
                        g_gameState.nEvtArgActor0 = g_gameState.party_roster[slot_idx];
                    } else {
                        g_gameState.nEvtArgActor1 = g_gameState.party_roster[slot_idx];
                    }
                    g_gameState.nEvtArgCount++;
                }
            }
            if (g_gameState.nEvtArgCount != 0) {
                switch (member_idx) {
                case 5:
                    dialog_play_record(0x3f, 0);
                    break;
                case 0:
                    dialog_play_record(0xf6, 0);
                    break;
                case 1:
                    dialog_play_record(0x146, 0);
                    break;
                case 2:
                    dialog_play_record(0xf7, 0);
                    break;
                case 6:
                    dialog_play_record(0x41, 0);

                case 3:
                case 4:;
                }
            }
            member_idx++;
        } while (member_idx < 7);
    }
    g_gameState.bPartyDirtyFlags = 0;
}

void evtcond_dispatch_key_to_handler(uint event_id) {
    switch (event_id) {
    case 0x4a:
        dialog_play_record(0x1cfdf1, 0);
        return;
    case 0x83:
    case 0x84:
    case 0x85:
    case 0x86:
    case 0x87:
        if (!gstate_event_read(0x14e7))
            return;
        if (!gstate_event_read(0x14e8))
            return;
        if (!gstate_event_read(0x14e9))
            return;
        if (!gstate_event_read(0x14ea))
            return;
        if (!gstate_event_read(0x14eb))
            return;
        gstate_event_write(0xdb1c, 1);
        return;
    case 0xeb:
    case 0xf5:
    case 0x123:
    case 0x125:
    case 0x14f:
    case 0x151:
    case 0x152:
    case 0x177:
    case 0x19a:
    case 0x1ad:
    case 0x1ae:
        rgnenc_complete_consume((ulong)event_id);
        return;
    case 0x262:
    case 0x265:
    case 0x267:
    case 0x26a:
    case 0x26b:
    case 0x26d:
        if (!gstate_event_read(0x16c6))
            return;
        if (!gstate_event_read(0x16c9))
            return;
        if (!gstate_event_read(0x16cb))
            return;
        if (!gstate_event_read(0x16ce))
            return;
        if (!gstate_event_read(0x16cf))
            return;
        if (!gstate_event_read(0x16d1))
            return;
        gstate_event_write(0x1d17, 1);
        return;
    }
}
