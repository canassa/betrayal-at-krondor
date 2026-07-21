#ifndef BAK_FARPTR_H
#define BAK_FARPTR_H

#include "structs.h"

extern dword near normalize_far_ptr(ushort offset, ushort seg);
extern void near normalize_far_ptr_flatten();
extern ulong near far_ptr_add_offset(uint ptr_lo, uint addend, uint rotate, uint ptr_hi);
extern void near far_ptr_sub_offset(void);
extern void near memcpy_far_backward(void);
extern void near memcpy_far_forward(void);
extern void fmemmove(uchar far *dst, uchar far *src, ulong n);
extern void fmemcpy_far(ulong dst, ulong src, uint count);
extern void memset_far(void far *dst, int value, ulong count);
extern int far_ptr_cmp(void far *a, void far *b);
extern uchar far *normalize_far_ptr_thunk(uchar far *p);

#endif
