#ifndef BAK_DECOMP_H
#define BAK_DECOMP_H

#include "structs.h"

extern void decomp_lzss(uchar far *dst, int remaining, void *inbuf, int buf_size, BakFile *fp);
extern void decomp_rle(uchar far *dst, int refill_count, int buf_ptr, int buf_size, BakFile *fp);

#endif
