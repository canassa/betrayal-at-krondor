#ifndef BAK_FMAP_H
#define BAK_FMAP_H

#include "structs.h"

extern void fmap_screen_run(void);
extern void fmap_twn_load(void);
extern void fmap_hotspots_unload(void);
extern int fmap_hit_test_cursor(void);
extern int fmap_xy_lookup_for_chapter(int *out_x, int *out_y);
extern int fmap_farptr_normalize(unsigned int *pHeading);

#endif
