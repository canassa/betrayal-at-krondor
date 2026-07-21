#ifndef BAK_MEM_H
#define BAK_MEM_H

#include "structs.h"

extern void *galloc_safe_zcalloc(uint size);
extern void galloc_zfree(void *ptr);
extern uchar far *galloc_calloc_far(ulong size, int flags);
extern void galloc_safe_farfree(void huge *ptr);

#endif
