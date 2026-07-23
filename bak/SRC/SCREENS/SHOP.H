#ifndef BAK_SHOP_H
#define BAK_SHOP_H

#include "structs.h"
#include "SRC/WORLD/ACTOR/ACTOR.H"

extern void shop_items_compute_actor_prices(Actor far *actor);
extern int shop_sell_item(Actor far *shop_inv, Actor far *actor, ItemSlot far *item_slot);
extern int shop_npc_transaction(Actor far *actor, Actor far *merchant, ItemSlot far *item);
extern int shop_haggle_attempt_purchase(Actor far *actor, CombatActor *combatant,
                                        ItemSlot far *item, int mode);

#endif
