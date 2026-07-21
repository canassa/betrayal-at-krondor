#ifndef BAK_STRMLOAD_H
#define BAK_STRMLOAD_H

#include "structs.h"

extern void far *stream_load_to_buffer(BakFile *file, ulong size, ulong *out_desc,
                                       ushort codec_kind);

#endif
