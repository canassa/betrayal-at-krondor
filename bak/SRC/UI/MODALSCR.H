#ifndef BAK_MODALSCR_H
#define BAK_MODALSCR_H

#include "structs.h"

extern void modalscreen_teleport_dat_load(int n_index);
extern int modalscreen_pending_scene_trans(void);
extern int modalscreen_teleport_spell_run(int current_city, long cost_base, int cost_per_unit);
extern void modalscreen_req_inv_run(int kind_or_id, int tax, int qty_mult, int char_slot);
extern void modalscreen_inventory_request(uint category_mask, int discount_pct);
extern void modalscreen_rest_until_time(Actor far *pActor);

#endif
