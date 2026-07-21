#ifndef BAK_RECTSPR_H
#define BAK_RECTSPR_H

#include "structs.h"

extern void draw_rect_filled(int x, int y, int w, int h);
extern void blit_sprite_flipped_clipped(void *sprite, int x, int y, int flags);

#endif
