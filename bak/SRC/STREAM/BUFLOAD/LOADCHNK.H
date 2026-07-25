#ifndef BAK_LOADCHNK_H
#define BAK_LOADCHNK_H

#include "structs.h"
#include "SRC/IO/RESOURCE.H"

extern void far *bak_load_chunk(FileRef *file, char *chunk_id, int mode);

#endif
