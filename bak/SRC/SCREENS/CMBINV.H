#ifndef BAK_CMBINV_H
#define BAK_CMBINV_H

#include "structs.h"

extern void cmbinv_combat_encounter_begin(MenuPage *param_1, Actor far *param_2, int param_3);
extern int cmbinv_inventory_screen_run(Actor far *actor, int idx, int flag);
extern int cmbinv_item_field_32_or_1(ItemSlot far *slot);
extern void cmbinv_combat_sort_initiative(Actor far *actor);
extern void cmbinv_consolidate_stacks(Actor far *actor);
extern ItemSlot far *cmbinv_find_equipped_in_category(Actor far *actor, int item_category);
extern int cmbinv_actor_classify_pickup(Actor far *actor, ItemSlot far *item);
extern void cmbinv_actor_inv_remove_item(Actor far *actor, ItemSlot far *item_slot);
extern int cmbinv_actor_transfer_item(Actor far *src, Actor far *dst, ItemSlot far *item);
extern int cmbinv_pty_distribute_item_stack(Actor far *src, ItemSlot far *item);
extern int cmbinv_actor_pickup_item(Actor far *dst_actor, Actor far *src_actor, ItemSlot far *item);
extern int cmbinv_actor_acquire_item(Actor far *actor, ItemSlot far *item);
extern int cmbinv_actor_drop_item_at_pos(Actor far *src_actor, ItemSlot far *item);
extern int cmbinv_member_can_equip_cat(int party_slot_plus_1, ItemSlot far *item);

#endif
