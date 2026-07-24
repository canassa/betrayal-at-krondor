#ifndef BAK_DECOMP_H
#define BAK_DECOMP_H

#include "structs.h"
#include "SRC/IO/IO.H"

extern void decomp_lzss(unsigned char far *dst, int remaining, void *inbuf, int buf_size, IoFile *fp);
extern void decomp_rle(unsigned char far *dst, int refill_count, int buf_ptr, int buf_size, IoFile *fp);

#endif
