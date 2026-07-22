#ifndef BAK_IOCHUNK_H
#define BAK_IOCHUNK_H

#include "structs.h"

extern long bak_fread_chunked(unsigned char huge *dest, long size, long count, BakFile *fp);
extern unsigned long bak_fwrite_chunked(unsigned char huge *src_far, unsigned long elem_size, unsigned long count, BakFile *stream);

#endif
