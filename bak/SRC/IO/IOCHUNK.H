#ifndef BAK_IOCHUNK_H
#define BAK_IOCHUNK_H

#include "structs.h"
#include "SRC/IO/RESOURCE.H"

extern long res_fread_chunked(unsigned char huge *dest, long size, long count, ResFile *fp);
extern unsigned long res_fwrite_chunked(unsigned char huge *src_far, unsigned long elem_size, unsigned long count, ResFile *file);

#endif
