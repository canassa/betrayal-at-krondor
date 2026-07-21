#ifndef BAK_CHUNKRD_H
#define BAK_CHUNKRD_H

#include "structs.h"

extern ulong chunkread_fread_far_large(char far *dst, ulong len, BakFile *file);
extern int chunkread_session_close(BakFile *file);
extern BakFile *chunkread_session_open(BakFileRef *file, char *chunk_id);
extern void far *chunkread_read_all_far(BakFileRef *file, char *chunk_id);

#endif
