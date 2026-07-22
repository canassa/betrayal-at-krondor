#ifndef BAK_SNDDRV_H
#define BAK_SNDDRV_H

#include "structs.h"

extern void snddrv_patch_farptr(unsigned short offset, unsigned short segment);
extern unsigned short snddrv_dispatch_cached(int cmd, int data);
extern void snddrv_dispatch(int cmd, int data);

#endif
