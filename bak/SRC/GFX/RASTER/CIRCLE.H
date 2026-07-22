#ifndef BAK_CIRCLE_H
#define BAK_CIRCLE_H

#include "structs.h"

extern void draw_circle(int radius, int cx, int cy);
extern unsigned long near draw_circle_bresenham(int radius, int cx, int cy);
extern void near record_circle_span(int dx, int dy);
extern void near circle_plot_mirror_pair(int dx, int dy);

#endif
