#ifndef BAK_LOADCHNK_H
#define BAK_LOADCHNK_H

#include "structs.h"
#include "SRC/IO/IO.H"

extern void far *bak_load_chunk(BakFileRef *file, char *chunk_id, int mode);

#endif
