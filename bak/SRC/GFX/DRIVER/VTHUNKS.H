#ifndef BAK_VTHUNKS_H
#define BAK_VTHUNKS_H

#include "structs.h"

extern void gfx_dispatch_noop(void);
extern void set_border_color(int color);
extern void renderer_vslot26_dispatch();
extern void vsync_hook(int a);
extern void cga_save_rect_to_buffer(uchar far *pDest, int x_start, int row, int width,
                                    int row_count);
extern long rect_byte_size(int width, int height);

#endif
