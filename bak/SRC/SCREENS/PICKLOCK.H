#ifndef BAK_PICKLOCK_H
#define BAK_PICKLOCK_H

#include "structs.h"

extern int picklock_screen_run(int score, int mode, Actor far *record);
extern void picklock_lock_slide_animation(int dir);
extern int picklock_screen_handle_drop(int item_kind, int slot);
extern void picklock_inv_info_query_disp(void);

#endif
