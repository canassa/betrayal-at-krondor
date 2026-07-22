#ifndef BAK_POLYRAST_H
#define BAK_POLYRAST_H

#include "structs.h"

extern void polyrast_edge_init_step(long *edge, unsigned int steps);
extern void polyrast_gouraud_blit_clipped(unsigned int *page_ptr, int *xs, int *ys);
extern void polyrast_spr_scaled_blit_planar(void *sprite, int x, int y, unsigned int flags, int w, int h,
                                            int colour);

#endif
