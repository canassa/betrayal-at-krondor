#ifndef BAK_STREAM_H
#define BAK_STREAM_H

#include "structs.h"

extern int stream_open(int codec_kind, BakFile *file, char *mode, unsigned long size);
extern int stream_open_from_memory(int codec_id, unsigned char huge *pSrc, char *mode, unsigned long size);
extern int stream_close(int stream_id);
extern unsigned int stream_read(int handle, void far *dest, unsigned int count);
extern unsigned int stream_write(int stream_id, void far *pSrc, unsigned int count);
extern unsigned long stream_size(int stream_id);
extern long stream_seek(int handle, long position, int origin);
extern int stream_rewind(int stream_id);

#endif
