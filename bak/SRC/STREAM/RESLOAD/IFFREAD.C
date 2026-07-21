#include "globals.h"
#include "structs.h"
#include "SRC/STREAM/RESLOAD/IFFREAD.H"
#include "SRC/IO/IO.H"

IffResReader *near iff_reader_find(BakFileRef *key) {
    int i;

    i = 4;
    while (--i >= 0) {
        if (g_iff_reader_pool[i].pStream == key) {
            return &g_iff_reader_pool[i];
        }
    }
    return 0;
}

void near bakfile_reset_preserve_cursor(IffResReader *reader) {
    BakFile *stream;
    long end;
    register char *p;
    register int count;

    p = (char *)reader;
    count = sizeof(IffResReader);
    stream = reader->pStream;
    end = *(long *)&reader->pLevel_cache[0];
    while (--count >= 0) {
        *p = 0;
        p++;
    }
    *(long *)&reader->pLevel_cache[0] = end;
    bak_rewind(reader->pStream = stream);
}

int near strncmp_eq(char *a, char *b, int n) {
    while ((*a != '\0' || *b != '\0') && n-- != 0) {
        if (*a++ != *b++) {
            return 0;
        }
    }
    return 1;
}

IffResReader *cache_slot_read(IffResReader *dst, BakFileRef *key) {
    IffResReader *src;
    if (key == 0 || dst == 0 || (src = iff_reader_find(key)) == 0)
        return 0;
    *dst = *src;
    return dst;
}

int cache_slot_write(IffResReader *record) {
    IffResReader *slot;

    if (record == 0 || record->pStream == 0 || (slot = iff_reader_find(record->pStream)) == 0)
        return 0;
    *slot = *record;
    bak_fseek(slot->pStream, slot->nCursor, 0);
    return 1;
}

BakFile *far cached_file_open(char *filename) {
    IffResReader *reader;

    if ((reader = iff_reader_find((void *)0)) == 0)
        return (BakFile *)0;
    if ((reader->pStream = bak_fopen(filename, "rb")) == 0)
        return (BakFile *)0;
    bak_fseek(reader->pStream, 0L, 2);
    *(long *)&reader->pLevel_cache[0] = bak_ftell(reader->pStream) | 0x80000000L;
    bakfile_reset_preserve_cursor(reader);
    return reader->pStream;
}

long near chunk_seek_rollback(IffResReader *reader) {
    *reader = g_chunkSeekSaveIffReader;
    bak_fseek(reader->pStream, reader->nCursor, 0);
    return -1L;
}

long chunk_seek(BakFile *handle, char *chunk_id, int mode) {
    IffResReader *reader;
    int len;
    short saved_skip_count;

    if ((handle == 0) || ((reader = iff_reader_find(handle)) == 0)) {
        return -1L;
    }

    len = -1;
    while (chunk_id[++len] != '\0')
        ;
    if ((len == 0) || ((len & 3) != 0)) {
        return -1L;
    }

    g_chunkSeekSaveIffReader = *reader;

    if (strncmp_eq(chunk_id, reader->pChunk_id_stack, 0x19)) {

        if (mode == 0) {
            if (bak_ftell(reader->pStream) == reader->nCursor) {
                return reader->nCursor;
            }
        }
        if (mode == -1) {
            bak_fseek(reader->pStream, reader->nCursor, 0);
            return reader->nCursor;
        }
        if (reader->nSkip_count != 0) {
            if (mode != 0) {
                saved_skip_count = mode;
                if (reader->nSkip_count < mode) {
                    mode -= reader->nSkip_count;
                } else if (reader->nSkip_count > mode) {
                    bakfile_reset_preserve_cursor(reader);
                } else {
                    bak_fseek(reader->pStream, reader->nCursor, 0);
                    return reader->nCursor;
                }
            } else {
                saved_skip_count = reader->nSkip_count + (mode = 1);
            }
        } else {
            if ((saved_skip_count = mode) != 0) {
                bakfile_reset_preserve_cursor(reader);
            } else {
                mode = 1;
            }
        }
    } else {
        if (mode > 0) {
            bakfile_reset_preserve_cursor(reader);
            saved_skip_count = mode;
        } else {
            mode = 1;
            saved_skip_count = 0;
        }
    }

    if (!(*(long *)&reader->pLevel_cache[reader->nDepth >> 2] & 0x80000000L)) {
        reader->nCursor += *(long *)&reader->wChunk_size_lo;
    }
    bak_fseek(reader->pStream, reader->nCursor, 0);

    while (mode-- != 0) {
        for (;;) {
            if ((*(long *)&reader->pLevel_cache[reader->nDepth >> 2] & 0x7fffffffL) ==
                reader->nCursor) {
                if (reader->nDepth == 0) {
                    return chunk_seek_rollback(reader);
                }
                reader->nDepth -= 4;
                continue;
            }
            if (!(*(long *)&reader->pLevel_cache[reader->nDepth >> 2] & 0x80000000L)) {
                reader->nCursor += *(long *)&reader->wChunk_size_lo;
                bak_fseek(reader->pStream, reader->nCursor, 0);
                continue;
            }

            if (bak_fread(reader->pChunk_id_stack + reader->nDepth, 1, 4, reader->pStream) != 4) {
                return chunk_seek_rollback(reader);
            }
            if ((reader->nDepth += 4) >= 0x18) {
                return chunk_seek_rollback(reader);
            }
            reader->pChunk_id_stack[reader->nDepth] = 0;
            reader->nCursor += 8;

            if (bak_fread(&reader->wChunk_size_lo, 4, 1, reader->pStream) != 1) {
                return chunk_seek_rollback(reader);
            }

            *(long *)&reader->pLevel_cache[reader->nDepth >> 2] =
                reader->nCursor + *(long *)&reader->wChunk_size_lo;
            *(long *)&reader->wChunk_size_lo &= 0x7fffffffL;
            if ((*(long *)&reader->wChunk_size_lo < 0L) ||
                (*(unsigned long *)&reader->wChunk_size_lo >=
                 (*(unsigned long *)&reader->pLevel_cache[0] & 0x7fffffffUL))) {
                return chunk_seek_rollback(reader);
            }

            if ((reader->nDepth != len) || !strncmp_eq(reader->pChunk_id_stack, chunk_id, len)) {
                continue;
            }
            break;
        }
    }

    reader->nSkip_count = saved_skip_count;
    return reader->nCursor;
}

unsigned long far cached_file_chunk_size(register BakFile *file) {
    IffResReader *reader;
    if (!file || !((reader = iff_reader_find(file)) != 0))
        return 0xFFFFFFFFUL;
    return (unsigned long)reader->wChunk_size_hi_flags << 16 | reader->wChunk_size_lo;
}

int far cached_file_close(BakFile *stream) {
    register IffResReader *reader;
    if (!stream || !((reader = iff_reader_find(stream)) != 0))
        return 0;
    reader->pStream = 0;
    bak_fclose(stream);
    return 1;
}

int is_file_cached(BakFileRef *key) {
    return iff_reader_find(key) ? 1 : 0;
}
