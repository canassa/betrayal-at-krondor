#ifndef BAK_CZONE_H
#define BAK_CZONE_H

#include "structs.h"

extern void czone_subsystem_init(void);
extern void czone_cache_evict_lru_slot(void);
extern void czone_resync_on_world_move(void);
extern void czone_load_actors(unsigned char zone, unsigned char x, unsigned char y, VisibleEntryList *list);
extern void czone_rebuild_actor_list(void);
extern int czone_find_combat_table_entry(unsigned char key1, unsigned char key2, int *out_index);
extern void czone_region_encounters_load(void);
extern void czone_spell_state_reset_pair(void);
extern void czone_save_persist_zone_plr(void);
extern void czone_reset_and_reload(void);
extern void czone_get_party_tile_xy(unsigned char *out_x, unsigned char *out_y);
extern void czone_world_pos_to_grid_xy(char *out_tile_x, char *out_tile_y);
extern void czone_world_pos_from_tile(unsigned char tile_x, unsigned char tile_y, unsigned char sub_x, unsigned char sub_y,
                                      WorldPos2 *out_pos);
extern void czone_world_pos_tile_sub_ctr(unsigned char tile_x, unsigned char tile_y, unsigned char sub_x, unsigned char sub_y,
                                         WorldPos2 *out_pos);

#endif
