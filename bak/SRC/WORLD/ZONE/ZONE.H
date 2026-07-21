#ifndef BAK_ZONE_H
#define BAK_ZONE_H

#include "structs.h"

extern void zone_subsystem_init(void);
extern void zone_subsystem_shutdown(void);
extern void zone_load(void);
extern void zone_world_scene_teardown(void);
extern void zone_combat_camera_set_world_pos(PlayerSpawnRecord *pos);
extern void zone_load_shape_sprite(void);
extern void zone_release_object_states(void);
extern void zone_load_audio_proximity(void);
extern void zone_scene_runtime_teardown(void);
extern void zone_teardown(int free_resources);
extern void zone_refresh_visible(int reload_shapes);
extern void zone_alloc_400byte_buffer(void);
extern void zone_free_400byte_buffer(void);
extern void zone_map_data_load(uchar zone_id);
extern int zone_grid_bit_get(uchar x, uchar y);
extern uchar zone_ref_find_pair_index(uchar zone, byte key1, byte key2);
extern void zone_set_plr_pos_rec(PlayerSpawnRecord *pRecord);
extern void zone_savegame_snap_world_state(void);
extern void zone_load_scx_image(void);

#endif
