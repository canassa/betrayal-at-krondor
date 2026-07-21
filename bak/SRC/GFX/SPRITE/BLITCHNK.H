#ifndef BAK_BLITCHNK_H
#define BAK_BLITCHNK_H

#include "structs.h"

extern void blit_chunky(uchar far *src, int dst_x, int dst_y, int width_bytes, int height);
extern void blit_chunky_planar_4bit();

#endif
