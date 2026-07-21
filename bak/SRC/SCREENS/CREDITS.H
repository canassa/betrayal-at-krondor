#ifndef BAK_CREDITS_H
#define BAK_CREDITS_H

#include "structs.h"

extern void credits_load(void);
extern void credits_free(void);
extern int credits_draw_scroll_pass(int x_left, int width, int reset);
extern int credits_run(void);

#endif
