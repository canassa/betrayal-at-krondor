#ifndef BAK_EXPLORE_H
#define BAK_EXPLORE_H

#include "structs.h"

extern void explore_req_map_screen_load(void);
extern void explore_req_map_screen_free(void);
extern void explore_color_remap_load(char *filename);
extern void explore_color_remap_free(void);
extern void explore_main_loop(void);
extern void explore_camera_snap_face_south(long *pSavedZ, short *pSavedYaw);
extern void explore_camera_restore_z_yaw(long new_pos_z, short new_yaw);
extern void explore_animate_camera_to_tile(TileMoveRecord *ptr);

#endif
