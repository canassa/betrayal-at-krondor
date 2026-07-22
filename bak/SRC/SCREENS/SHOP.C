#include "globals.h"
#include "structs.h"
#include "SRC/SCREENS/SHOP.H"
#include "SRC/SYS/RAND.H"
#include "SRC/AUDIO/ENGINE/AUDIO.H"
#include "SRC/GAME/GSTATE.H"
#include "SRC/CHAR/STAT.H"
#include "SRC/DIALOG/DIALOG.H"
#include "SRC/SCREENS/CMBINV.H"
#include "SRC/SCREENS/ITEMTBL.H"
#include "SRC/WORLD/ACTOR/ACTORREC.H"


static int shop_rand_max_of_3(unsigned int modulus) {
    int i;
    int max;
    int roll;

    max = 0;
    if (modulus != 0) {
        for (i = 0; i < 3; i++) {
            if ((roll = RND(modulus)) > max)
                max = roll;
        }
    }
    return max;
}

void far shop_items_compute_actor_prices(Actor far *actor) {
    long itemId;
    long priceScale;
    ItemRecord far *rec;
    ActorSubrecord far *sub;
    long *prices;

    priceScale = 100;
    prices = itemtbl_count();
    sub = actorrec_get_subrecord(actor, SUBREC_EVENT_STATE);
    if ((g_gameState.nZoneId == '\x03') && (sub->interact_msg.bKind_or_id == 2)) {
        if (gstate_event_read(0xdc29) != 0) {
            if (gstate_event_read(0xdc2a) == 0) {
                priceScale = 600;
            }
        }
    }
    for (itemId = 0; itemId < 0x8a; itemId++) {
        rec = itemtbl_record_ptr_by_id((int)itemId);
        prices[(int)itemId] =
            ((long)(unsigned short)rec->nBase_price * ((long)(int)sub->interact_msg.bFlags + 100)) /
            100;
        prices[(int)itemId] = (prices[(int)itemId] * priceScale) / 100;
    }
    return;
}

int far shop_haggle_attempt_purchase(Actor far *actor, CombatActor *combatant, ItemSlot far *item,
                                     int mode) {
    register long *prices;
    int partyRoll;
    int merchantRoll;
    long price;
    ItemRecord far *rec;
    ActorSubrecord far *sub;

    prices = itemtbl_count();
    rec = itemtbl_record_ptr(item);
    sub = actorrec_get_subrecord(actor, SUBREC_EVENT_STATE);
    merchantRoll = sub->event_state.bTemple_filter;
    price =
        (long)(unsigned int)rec->nBase_price * ((long)(int)sub->interact_msg.bFlags + 100) / 100;
    if ((unsigned char)sub->interact_msg.dwMessage_id != 0 && prices[item->item_id] == price) {
        g_gameState.nEvtArgStat = combatant->cParty_slot - 1;
        partyRoll = stat_actor_get(combatant, 0xc, 0);
        partyRoll = shop_rand_max_of_3(partyRoll);
        merchantRoll = shop_rand_max_of_3(merchantRoll);
        if (partyRoll > merchantRoll) {
            int iDiscount;
            iDiscount = (int)(unsigned char)sub->interact_msg.dwMessage_id / 2;
            iDiscount += partyRoll - merchantRoll;
            iDiscount = shop_rand_max_of_3(iDiscount);
            if ((int)(unsigned char)sub->interact_msg.dwMessage_id < iDiscount) {
                iDiscount = (unsigned char)sub->interact_msg.dwMessage_id;
            }
            prices[item->item_id] -= prices[item->item_id] * (long)iDiscount / 100;
            if (prices[item->item_id] < 1) {
                prices[item->item_id] = 1;
            }
            stat_party_broadcast_status_op(0xc, 1, 3);
            stat_combatant_modify(combatant, 0xc, 1, 3);
            return 1;
        }
    }
    if (RND(100) < (100 - partyRoll) / 5) {
        stat_party_broadcast_status_op(0xc, 1, 3);
    }
    if (RND(100) < (unsigned)sub->event_state.bTeleport_cost_msb) {
        prices[item->item_id] = -1;
    }
    return 0;
}

int far shop_npc_transaction(Actor far *actor, Actor far *merchant, ItemSlot far *item) {
    ItemRecord far *rec;
    long *prices;
    int purchased;
    ItemSlot pickupItem;
    unsigned savedCount;
    int partySlot;
    int done;

    rec = itemtbl_record_ptr(item);
    actorrec_get_subrecord(actor, SUBREC_EVENT_STATE);
    prices = itemtbl_count();
    partySlot = merchant->loc.party_slot.wSlot_id - 1;
    done = 0;
    purchased = 0;
    if (prices[(unsigned)item->item_id] < 0) {
        return 0;
    }
    if (item->item_id == 0x86) {
        pickupItem.item_id = 'H';
        pickupItem.condition = 1;
        pickupItem.flags = 0;
        rec = itemtbl_record_ptr(&pickupItem);
    } else {
        pickupItem = *item;
    }
    if (rec->wCategory != 0x18 && cmbinv_actor_classify_pickup(merchant, &pickupItem) == 0) {
        g_gameState.nEvtArgCount = 0;
        dialog_play_record(0x1b7748, 0);
        return 0;
    }
    while (!done) {
        done = 1;
        g_gameState.lEvtArgGoldCost = itemtbl_compute_value(item);
        dialog_play_record(0x1b7757, 0);

        if (gstate_event_read(0x104) != 0) {
            purchased = 1;
            g_gameState.nParty_gold -= g_gameState.lEvtArgGoldCost;
            if (item->item_id >= 0x87 && item->item_id <= 0x89) {
                if (g_gameState.abActorStatusRanks[partySlot][3] == 'd') {
                    purchased = 0;
                    g_gameState.nParty_gold += g_gameState.lEvtArgGoldCost;
                    dialog_play_record(0x1b775c, 0);
                } else {
                    if (rec->wUse_sfx != 0) {
                        audio_sfx_play_n_times(rec->wUse_sfx & 0xff, rec->wUse_sfx >> 8, 1);
                    }
                    stat_combatant_apply_delta(&g_gameState.party_members[partySlot], 3,
                                               rec->wEffect_arg_b);
                    stat_combatant_apply_delta(&g_gameState.party_members[partySlot], 5, -100);
                    stat_combatant_modify(&g_gameState.party_members[partySlot], 0x10, 0x300, 0x3c);
                }
            } else {
                if (item->flags & 2) {
                    item->flags &= ~2;
                    cmbinv_actor_pickup_item(merchant, actor, &pickupItem);
                } else {
                    savedCount = actor->itemCount;
                    actor->itemCount = 0;
                    cmbinv_actor_pickup_item(merchant, actor, &pickupItem);
                    actor->itemCount = savedCount;
                }
                if (rec->wCategory == 0x17) {
                    int slot = merchant->loc.party_slot.wSlot_id - 1;
                    if (g_gameState.abActorStatusRanks[slot][5] != 0) {
                        gstate_member_consume_rations(slot, 1);
                    }
                }
            }
        } else {
            if (gstate_event_read(0x106) == 0) {
                continue;
            }
            if (item->item_id == 0x85) {
                dialog_play_record(0x1b775f, 0);
                done = 0;
            } else if (shop_haggle_attempt_purchase(actor, &g_gameState.party_members[partySlot],
                                                    item, 0) != 0) {
                dialog_play_record(0x1b7755, 0);
                done = 0;
            } else {
                dialog_play_record(0x1b7754, 0);
                done = 1;
            }
        }
    }
    return purchased;
}

int far shop_sell_item(Actor far *shop_inv, Actor far *actor, ItemSlot far *item_slot) {
    ItemRecord far *rec;
    ActorSubrec04_EventState far *sub;
    ItemSlot far *best_slot;
    int is_new_slot;
    int i;
    long price;

    rec = itemtbl_record_ptr(item_slot);
    sub = (ActorSubrec04_EventState far *)actorrec_get_subrecord(shop_inv, SUBREC_EVENT_STATE);
    best_slot = (ItemSlot far *)0;
    is_new_slot = 0;
    if (((rec->nBase_price == 0) || ((rec->wSub_flags & sub->wShop_disposition_flags) == 0)) &&
        (itemtbl_inv_count_by_kind(shop_inv, (unsigned int)item_slot->item_id) == 0)) {
        dialog_play_record(0x1b7759, 0);
        return 0;
    } else {
        if (shop_inv->itemCount < shop_inv->itemCapacity) {
            best_slot = &ACTOR_ITEM(shop_inv, shop_inv->itemCount);
            is_new_slot = 1;
        } else {
            for (i = 0; i < (int)(unsigned int)shop_inv->itemCount; i++) {
                if ((ACTOR_ITEM(shop_inv, i).flags & 2) != 0) {
                    if (best_slot != (ItemSlot far *)0) {
                        if ((unsigned int)itemtbl_record_ptr(best_slot)->nBase_price >=
                            (unsigned int)itemtbl_record_ptr(&ACTOR_ITEM(shop_inv, i))->nBase_price) {
                            continue;
                        }
                    }
                    best_slot = &ACTOR_ITEM(shop_inv, i);
                }
            }
        }
        if (best_slot == (ItemSlot far *)0) {
            g_gameState.nEvtArgCount = 10;
            dialog_play_record(0x1b7748, 0);
            return 0;
        }
        price = itemtbl_compute_value(item_slot) * (long)(int)(unsigned int)sub->bArg3 / 100;
        if (itemtbl_record_ptr(item_slot)->wCategory == 4) {
            price /= 2;
        }
        if (price < 1) {
            price = 1;
        }
        g_gameState.lEvtArgGoldCost = price;
        dialog_play_record(0x1b7756, 0);
        if (gstate_event_read(0x104) != 0) {
            *best_slot = *item_slot;
            best_slot->flags |= 2;
            shop_inv->itemCount = shop_inv->itemCount + is_new_slot;
            g_gameState.nParty_gold += price;
            cmbinv_actor_inv_remove_item(actor, item_slot);
            return 1;
        }
        return 0;
    }
}
