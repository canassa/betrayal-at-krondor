#ifndef BAK_WORLDLP_H
#define BAK_WORLDLP_H

#include "structs.h"

extern void worldloop_req_main_screen_load(void);
extern void worldloop_req_main_screen_unload(void);
extern short worldloop_main(void);
extern void worldloop_camera_snap_reset(long *pSavedZ, short *pSavedYaw);
extern void worldloop_camera_set_pos_z_yaw(long pos_z, short yaw);
extern void worldloop_party_move_done_clr(void);
extern void worldloop_step_or_final_movement(void);
extern void worldloop_set_flag_8b_preds(void);
extern void worldloop_pty_stat7_flag_cd(void);

#endif
