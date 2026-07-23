#ifndef BAK_MDACON_H
#define BAK_MDACON_H

#include "structs.h"

extern unsigned short g_bMdaEnabled;

extern void mdacon_clear_screen(void);
extern void mdacon_write_string(int col, int row, char *str);
extern void mdacon_printf(int col, int row, char *fmt, ...);
extern void mdacon_draw_window_frame(int x, int y, int w, int h, int fill_interior);

#endif
