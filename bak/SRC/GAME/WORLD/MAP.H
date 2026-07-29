#ifndef BAK_MAP_H
#define BAK_MAP_H

#include "structs.h"

extern unsigned short g_full_redraw_needed;
extern short g_nMapReloadPending;
extern unsigned char *g_pColorRemap;
extern unsigned short g_wExploreCameraYawSaved;
extern long g_lWorldZMin;
extern long g_lWorldZMax;
extern long g_lWorldZStep;
extern long g_lExploreCameraZSaved;
extern MenuPage *g_pReqMapPage;

extern void map_req_map_screen_load(void);
extern void map_req_map_screen_free(void);
extern void map_color_remap_load(char *filename);
extern void map_color_remap_free(void);
extern void map_main_loop(void);
extern void map_camera_snap_face_south(long *pSavedZ, short *pSavedYaw);
extern void map_camera_restore_z_yaw(long new_pos_z, short new_yaw);
extern void map_animate_camera_to_tile(TileMoveRecord *ptr);

#endif
