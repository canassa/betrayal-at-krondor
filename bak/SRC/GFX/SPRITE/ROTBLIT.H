#ifndef BAK_ROTBLIT_H
#define BAK_ROTBLIT_H

#include "structs.h"

extern void near stretch_walk_x_clipped(int *out_xs, int x_start, int count, int x_step, int span);
extern void vga_reset_gc_default_thunk(void);
extern void jmp_via_2f48(uchar *sprite, int x, int y, int angle, int dx, int dy, int flag1,
                         int flag2);
extern void read_4words_from_2tables(ushort *a, ushort *b, ushort *c, ushort *d);

#endif
