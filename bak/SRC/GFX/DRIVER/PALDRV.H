#ifndef BAK_PALDRV_H
#define BAK_PALDRV_H

#include "structs.h"

extern unsigned char far *chunk_load_into_slot(BakFileRef *file);
extern unsigned char far *palette_set_active(unsigned char far *palette);
extern void cache_release(unsigned char far *buf_farptr);
extern void palette_set_scaled(unsigned int first_color, unsigned int last_color, int target_color, int intensity);
extern int palette_cycle_add(int start, int count, int target);
extern void palette_cycle_tick(void);
extern void near memcpy_inline(unsigned char far *src, unsigned char far *dst, int count);

#endif
