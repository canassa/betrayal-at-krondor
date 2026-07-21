#ifndef BAK_SCROLL_H
#define BAK_SCROLL_H

#include "structs.h"

extern void scrolltrans_scroll_fast(int direction, int speed, int distance);
extern void scrolltrans_scroll(int direction, int duration, int distance);
extern void scrolltrans_pageflip_pan(int x_off, int line, int screen_width, int set_split);
extern void scrolltrans_planar_blit_pageflip(int direction, int x_off, int y, int screen_width);

#endif
