#ifndef BAK_AUDRESLD_H
#define BAK_AUDRESLD_H

#include "structs.h"
#include "SRC/IO/RESOURCE.H"

extern ResFile *audio_resource_load_chunk(FileRef *file, int chunk_id);

#endif
