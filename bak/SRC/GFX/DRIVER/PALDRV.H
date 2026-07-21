#ifndef BAK_PALDRV_H
#define BAK_PALDRV_H

#include "structs.h"

extern uchar far *chunk_load_into_slot(BakFileRef *file);
extern uchar far *palette_set_active(uchar far *palette);
extern void cache_release(uchar far *buf_farptr);
extern void palette_set_scaled(uint first_color, uint last_color, int target_color, int intensity);
extern int palette_cycle_add(int start, int count, int target);
extern void palette_cycle_tick(void);
extern void near memcpy_inline(uchar far *src, uchar far *dst, int count);

#endif
