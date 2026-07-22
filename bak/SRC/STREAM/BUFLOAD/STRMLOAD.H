#ifndef BAK_STRMLOAD_H
#define BAK_STRMLOAD_H

#include "structs.h"

extern void far *stream_load_to_buffer(BakFile *file, unsigned long size, unsigned long *out_desc,
                                       unsigned short codec_kind);

#endif
