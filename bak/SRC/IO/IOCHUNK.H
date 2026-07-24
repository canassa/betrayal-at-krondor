#ifndef BAK_IOCHUNK_H
#define BAK_IOCHUNK_H

#include "structs.h"
#include "SRC/IO/IO.H"

extern long bak_fread_chunked(unsigned char huge *dest, long size, long count, IoFile *fp);
extern unsigned long bak_fwrite_chunked(unsigned char huge *src_far, unsigned long elem_size, unsigned long count, IoFile *stream);

#endif
