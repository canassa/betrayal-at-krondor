#ifndef BAK_POOL_H
#define BAK_POOL_H

#include "structs.h"

extern ulong pool_get_size(void);
extern void pool_compute_size_from_music(void);
extern void pool_init(void);
extern void pool_reset(void);
extern void far *pool_alloc(ulong size);
extern int pool_is_managed_ptr(ulong ptr);
extern void far *pool_acquire_buffer(ulong size, int kind);

#endif
