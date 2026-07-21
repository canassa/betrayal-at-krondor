#ifndef BAK_SKY_H
#define BAK_SKY_H

#include "structs.h"

extern void sky_horizon_strip_compute_slope(SkyStrip far *pStrip);
extern void sky_horizon_strips_init(int a);
extern void sky_draw_ground_band(void);
extern void sky_polygon_draw_dispatch(uint vcount, int *xs, int *ys);

#endif
