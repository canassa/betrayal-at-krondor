#ifndef BAK_IFFREAD_H
#define BAK_IFFREAD_H

#include "structs.h"

extern IffResReader *near iff_reader_find(BakFileRef *key);
extern void near bakfile_reset_preserve_cursor(IffResReader *reader);
extern int near strncmp_eq(char *a, char *b, int n);
extern IffResReader *cache_slot_read(IffResReader *dst, BakFileRef *key);
extern int cache_slot_write(IffResReader *record);
extern BakFile *cached_file_open(char *filename);
extern long near chunk_seek_rollback(IffResReader *reader);
extern long chunk_seek(BakFile *handle, char *chunk_id, int mode);
extern unsigned long cached_file_chunk_size(BakFile *file);
extern int cached_file_close(BakFile *stream);
extern int is_file_cached(BakFileRef *key);

#endif
