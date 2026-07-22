#ifndef BAK_MEM_H
#define BAK_MEM_H

#include "structs.h"

extern void *galloc_safe_zcalloc(unsigned int size);
extern void galloc_zfree(void *ptr);
extern unsigned char far *galloc_calloc_far(unsigned long size, int flags);
extern void galloc_safe_farfree(void huge *ptr);

#endif
