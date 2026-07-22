#ifndef BAK_FARPTR_H
#define BAK_FARPTR_H

#include "structs.h"

extern unsigned long near normalize_far_ptr(unsigned short offset, unsigned short seg);
extern void near normalize_far_ptr_flatten();
extern unsigned long near far_ptr_add_offset(unsigned int ptr_lo, unsigned int addend, unsigned int rotate, unsigned int ptr_hi);
extern void near far_ptr_sub_offset(void);
extern void near memcpy_far_backward(void);
extern void near memcpy_far_forward(void);
extern void fmemmove(unsigned char far *dst, unsigned char far *src, unsigned long n);
extern void fmemcpy_far(unsigned long dst, unsigned long src, unsigned int count);
extern void memset_far(void far *dst, int value, unsigned long count);
extern int far_ptr_cmp(void far *a, void far *b);
extern unsigned char far *normalize_far_ptr_thunk(unsigned char far *p);

#endif
