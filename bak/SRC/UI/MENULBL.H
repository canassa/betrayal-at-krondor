#ifndef BAK_MENULBL_H
#define BAK_MENULBL_H

#include "structs.h"

extern short g_nCreditsScrollYOffset;
extern short g_nCreditsMaxLabelHeight;

extern void menulbl_calc_max_label_width(void);
extern void menulbl_scroll_step_and_draw(int a, int b, int c);

#endif
