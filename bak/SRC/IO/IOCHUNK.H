#ifndef BAK_IOCHUNK_H
#define BAK_IOCHUNK_H

#include "structs.h"

extern long bak_fread_chunked(uchar huge *dest, long size, long count, BakFile *fp);
extern ulong bak_fwrite_chunked(uchar huge *src_far, ulong elem_size, ulong count, BakFile *stream);

#endif
