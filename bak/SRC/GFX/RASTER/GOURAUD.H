#ifndef BAK_GOURAUD_H
#define BAK_GOURAUD_H

#include "structs.h"

extern void gfx_gouraud_blit_quad(ushort *quad, int *vy_array, int *vx_array);
extern void near gfx_gouraud_span_dispatch(int v0, int v1, ushort *quad, int *out_a, int *out_b,
                                           int *out_c, int *out_d);
extern int near compare_edge_slopes(int x1, int x2, int y_base, int y1, int x3, int x4);
extern void edge_step_init(long *step, int count);

#endif
