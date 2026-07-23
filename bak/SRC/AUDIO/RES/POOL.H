#ifndef BAK_POOL_H
#define BAK_POOL_H

#include "structs.h"

extern unsigned long g_pool_base;
extern unsigned long g_pool_top;
extern unsigned long g_nPoolSize;

extern unsigned long pool_get_size(void);
extern void pool_compute_size_from_music(void);
extern void pool_init(void);
extern void pool_reset(void);
extern void far *pool_alloc(unsigned long size);
extern int pool_is_managed_ptr(unsigned long ptr);
extern void far *pool_acquire_buffer(unsigned long size, int kind);

#endif
