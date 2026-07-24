#ifndef BAK_IFFREAD_H
#define BAK_IFFREAD_H

#include "structs.h"
#include "SRC/IO/IO.H"

extern IffResReader *near iff_reader_find(FileRef *key);
extern void near bakfile_reset_preserve_cursor(IffResReader *reader);
extern int near strncmp_eq(char *a, char *b, int n);
extern IffResReader *cache_slot_read(IffResReader *dst, FileRef *key);
extern int cache_slot_write(IffResReader *record);
extern IoFile *cached_file_open(char *filename);
extern long near chunk_seek_rollback(IffResReader *reader);
extern long chunk_seek(IoFile *handle, char *chunk_id, int mode);
extern unsigned long cached_file_chunk_size(IoFile *file);
extern int cached_file_close(IoFile *stream);
extern int is_file_cached(FileRef *key);

#endif
