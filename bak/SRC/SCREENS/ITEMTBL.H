#ifndef BAK_ITEMTBL_H
#define BAK_ITEMTBL_H

#include "structs.h"
#include "SRC/WORLD/ACTOR/ACTOR.H"

extern ItemRecord far *g_pItemDefTable;
extern unsigned long *g_pItemPriceTable;

extern int itemtbl_slot_value_modifier(ItemSlot far *slot);
extern void itemtbl_free(void);
extern int itemtbl_load(void);
extern ItemRecord far *itemtbl_record_ptr(ItemSlot far *slot_ptr);
extern ItemRecord far *itemtbl_record_ptr_by_id(int id);
extern long *itemtbl_count(void);
extern long itemtbl_compute_value(ItemSlot far *slot);
extern int itemtbl_find_by_full_record(ItemRecord far *record);
extern int itemtbl_inv_count_by_kind(Actor far *inv, unsigned int kind);
extern int itemtbl_party_count_by_kind(unsigned int kind);
extern int itemtbl_inv_consume_one_by_kind(Actor far *inv, unsigned int kind);
extern int itemtbl_pty_consum_one_kind(unsigned int kind);

#endif
