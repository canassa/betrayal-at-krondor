#ifndef BAK_LOADCHNK_H
#define BAK_LOADCHNK_H

#include "structs.h"

extern void far *bak_load_chunk(BakFileRef *file, char *chunk_id, int mode);

#endif
