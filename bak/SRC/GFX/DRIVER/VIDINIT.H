#ifndef BAK_VIDINIT_H
#define BAK_VIDINIT_H

#include "structs.h"

extern void cga_rect_paste_from_buffer(uchar far *pDest, int x, int row, int width, int height);
extern int video_init(int mode, int b, char *driver_name);

#endif
