#ifndef BAK_VISLIST_H
#define BAK_VISLIST_H

#include "structs.h"

extern void vislist_alloc(void);
extern void vislist_free(void);
extern void vislist_sort(ushort seg, ushort *ids, long *vals, int count);

#endif
