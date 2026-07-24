#include <mem.h>
#include "SRC/GAME/GMAIN.H"
#include "structs.h"
#include "SRC/WORLD/ACTOR/ACTOR.H"
#include "SRC/SCREENS/ITEMTBL.H"
#include "SRC/IO/IO.H"
#include "SRC/IO/IOCHUNK.H"
#include "SRC/SYS/FARTHUNK.H"
#include "SRC/SYS/DOSMEM.H"
#include "SRC/GAME/GSTATE.H"
#include "SRC/SCREENS/CMBINV.H"
#include "defines.h"


ItemRecord far *g_pItemDefTable = {0};
unsigned long *g_pItemPriceTable = {0};

ItemRecord far *itemtbl_record_ptr(ItemSlot far *slot_ptr) {
    return g_pItemDefTable + slot_ptr->item_id;
}

ItemRecord far *itemtbl_record_ptr_by_id(int id) {
    return g_pItemDefTable + id;
}

int itemtbl_find_by_full_record(ItemRecord far *record) {
    int i;

    for (i = 0; i < 0x8a; i++) {
        if (_fmemcmp(record, g_pItemDefTable + i, sizeof(ItemRecord)) == 0) {
            return i;
        }
    }
    return 0;
}

long *itemtbl_count(void) {
    return (long *)g_pItemPriceTable;
}

void itemtbl_free(void) {
    my_free(g_pItemPriceTable);
    _freemem(g_pItemDefTable);
    g_pItemPriceTable = (unsigned long *)0x0;
    g_pItemDefTable = (ItemRecord far *)0x0;
    return;
}

int itemtbl_load(void) {
    IoFile *fp;
    int size;

    if (g_pItemDefTable == (ItemRecord far *)0) {

        size = 0x2b7a;
        fp = bak_fopen("OBJINFO.DAT", "rb");
        g_pItemDefTable = (ItemRecord far *)alloc_far((long)size, 0);
        bak_fread_chunked((unsigned char far *)g_pItemDefTable, 1, (long)size, fp);
        bak_fclose(fp);
        g_pItemPriceTable = (unsigned long *)my_malloc(0x228);
        return 1;
    }
    return 0;
}

long itemtbl_compute_value(ItemSlot far *slot) {
    long value;
    ItemRecord far *rec;
    int far *sub;

    rec = g_pItemDefTable + slot->item_id;
    value = g_pItemPriceTable[slot->item_id];
    if (slot->item_id == 0x85) {

        sub = (int far *)((char far *)g_pItemDefTable + 0x2b20);
        value = sub[slot->condition];
    } else if (value >= 0) {
        if (rec->wFlags & 0x1000) {
            value = value * itemtbl_slot_value_modifier(slot) / 100L;
        } else if (rec->wFlags & 0xa000) {
            value = value * slot->condition / (long)(unsigned long)rec->bCharges_per_use;
        }
    }
    if ((long)g_pItemPriceTable[slot->item_id] >= 0) {
        if (value <= 1) {
            value = 1;
        }
    }
    return value;
}

int itemtbl_inv_count_by_kind(Actor far *inv, unsigned int kind) {
    int total;
    int i;

    i = total = 0;
    for (; i < (int)inv->itemCount; i++) {
        if (ACTOR_ITEM(inv, i).item_id == kind) {
            if (ACTOR_ITEM(inv, i).condition != 0) {
                total += ACTOR_ITEM(inv, i).condition;
            } else {
                total++;
            }
        }
    }
    return total;
}

int itemtbl_party_count_by_kind(unsigned int kind) {
    int n;
    int slot;
    int total;

    total = 0;
    g_gameState.nEvtArgActor0 = g_gameState.party_roster[0];
    for (slot = 0; slot < g_gameState.party_count; slot = slot + 1) {
        if (0 <
            (n = itemtbl_inv_count_by_kind(gstate_party_member_record(slot)->actor_record, kind))) {
            g_gameState.nEvtArgActor0 = g_gameState.party_roster[slot];
            total += n;
        }
    }
    total += itemtbl_inv_count_by_kind(g_gameState.shared_inventory, kind);
    return total;
}

int far itemtbl_slot_value_modifier(ItemSlot far *slot) {
    ItemRecord far *rec;
    int val;

    rec = itemtbl_record_ptr(slot);
    val = (rec->wFlags & 0x1000) ? slot->condition : 100;
    if (slot->flags & 0x2000) {
        val = (val * 6) / 4;
    }
    if (slot->flags & 0x4000) {
        val = (val * 7) / 4;
    }
    if (slot->flags & 0x8000) {
        val = (val << 3) / 4;
    }
    if (slot->flags & 0x10) {
        val = 0;
    }
    return val;
}

int itemtbl_inv_consume_one_by_kind(Actor far *inv, unsigned int kind) {
    int old_count;
    int i;

    inv->needsFlush = TRUE;
    for (i = 0; i < (int)inv->itemCount; i++) {
        if (ACTOR_ITEM(inv, i).item_id != kind || kind == 0x54) {
            continue;
        }
        if (ACTOR_ITEM(inv, i).condition > 1) {
            ACTOR_ITEM(inv, i).condition--;
            return 1;
        }
        {
            int wf;
            wf = g_pItemDefTable ? (int)g_pItemDefTable[kind].wFlags : 0;
            if ((wf & 0x2000) && !(wf & 0x10)) {
                old_count = ACTOR_ITEM(inv, i).condition;
                ACTOR_ITEM(inv, i).condition = 0;
                if (old_count != 0) {
                    return 1;
                }
            } else {
                cmbinv_actor_inv_remove_item(inv, ACTOR_ITEMS(inv) + i);
                return 1;
            }
        }
    }
    return 0;
}

int itemtbl_pty_consum_one_kind(unsigned int kind) {
    int slot;

    g_gameState.nEvtArgActor0 = g_gameState.party_roster[0];
    for (slot = 0; slot < g_gameState.party_count; slot++) {
        if (itemtbl_inv_consume_one_by_kind(gstate_party_member_record(slot)->actor_record, kind) !=
            0) {
            g_gameState.nEvtArgActor0 = g_gameState.party_roster[slot];
            return 1;
        }
    }
    return 0;
}
