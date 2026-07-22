#ifndef BAK_ITEMTBL_H
#define BAK_ITEMTBL_H

#include "structs.h"

extern int itemtbl_slot_value_modifier(ItemSlot far *slot);
extern void itemtbl_free(void);
extern int itemtbl_load(void);
extern ItemRecord far *itemtbl_record_ptr(ItemSlot far *slot_ptr);
extern ItemRecord far *itemtbl_record_ptr_by_id(int id);
extern long *itemtbl_count(void);
extern long itemtbl_compute_value(ItemSlot far *slot);
extern int itemtbl_find_by_full_record(ItemRecord far *record);
extern int itemtbl_inv_count_by_kind(Actor far *inv, uint kind);
extern int itemtbl_party_count_by_kind(uint kind);
extern int itemtbl_inv_consume_one_by_kind(Actor far *inv, uint kind);
extern int itemtbl_pty_consum_one_kind(uint kind);

#endif
