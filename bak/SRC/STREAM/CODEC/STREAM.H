#ifndef BAK_STREAM_H
#define BAK_STREAM_H

#include "structs.h"

extern int stream_open(int codec_kind, BakFile *file, char *mode, ulong size);
extern int stream_open_from_memory(int codec_id, byte huge *pSrc, char *mode, ulong size);
extern int stream_close(int stream_id);
extern uint stream_read(int handle, void far *dest, uint count);
extern uint stream_write(int stream_id, void far *pSrc, uint count);
extern ulong stream_size(int stream_id);
extern long stream_seek(int handle, long position, int origin);
extern int stream_rewind(int stream_id);

#endif
