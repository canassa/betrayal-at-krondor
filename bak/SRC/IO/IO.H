/**
 * @file    IO.H
 * @brief   Resource-archive I/O layer: stdio-shaped `bak_*` wrappers over
 *          loose files and the `KRONDOR.RMF`-mapped archive resources.
 */
#ifndef BAK_IO_H
#define BAK_IO_H

#include "structs.h"

typedef struct BakIndexEntry {
    unsigned long dwHash;
    unsigned long dwBase_offset;
} BakIndexEntry;

typedef struct BakArchive {
    char name[13];
    char _pad;
    short ordinal;
    FILE *fp;
    unsigned long pos;
    unsigned short flags;
    BakIndexEntry far *index;
} BakArchive;

typedef struct BakArchiveTable {
    BakArchive entries[10];
} BakArchiveTable;

typedef struct BakHandle {
    short archive_idx;
    unsigned long base_offset;
    unsigned long length;
    unsigned long cur_offset;
    unsigned short valid;
    FILE *real_fp;
} BakHandle;

/**
 * @brief Opaque file token from bak_fopen()/cached_file_open().
 *
 * Really a CRT `FILE *` or a ::BakHandle pool slot; bak_find_handle() tells
 * them apart on every bak_* call. Store it, compare it, pass it back — never
 * dereference it or hand it to CRT stdio. Intentionally has no definition.
 */
typedef struct BakFile BakFile;
/**
 * @brief A file reference: either a filename (`char *`) or an open ::BakFile token.
 *
 * is_file_cached() tells the two apart at runtime by pointer identity. Plain void
 * underneath, so both kinds pass without casts.
 */
typedef void BakFileRef;

extern unsigned char g_bak_initialized;
extern short g_bak_io_error;
extern void far *g_int24_old_vector;
extern BakHandle g_bak_handles[10];
extern BakArchive g_bak_archives[11];
extern BakFile *g_pBakFgetcLastStream;
extern FILE *g_pBakActiveFgetcStream;
extern unsigned char g_bak_in_fopen;
extern unsigned char g_bak_fopen_retry;
extern unsigned char g_bak_archives_dirty;
extern unsigned char g_bak_open_handles;
extern unsigned long g_bak_lookup_hash;
extern short g_bak_current_archive;

/**
 * @brief Number of archives registered from `KRONDOR.RMF` (slots `1..count`
 *        of @c g_bak_archives  (TBD-ref: not yet documented)).
 *
 * 0 until the resource map is read — or for good if it cannot be opened —
 * and while 0 every `bak_*` wrapper passes straight through to CRT stdio.
 */
extern int g_ioArchiveCount;

extern short g_bak_hash_seed;
extern unsigned short g_bak_hash_rotate;
extern BakHandle *g_pBakFindHandleCacheVal;
extern BakFile *g_pBakFindHandleCacheKey;

extern BakFile *bak_fopen(char *filename, char *mode);
extern int bak_fclose(BakFile *stream);
extern int bak_fread(void *ptr, int size, int count, BakFile *stream);
extern int bak_fseek(BakFile *stream, long offset, int whence);
extern long bak_ftell(BakFile *stream);
extern long bak_filelength(BakFile *stream);
extern void bak_rewind(BakFile *stream);
extern int bak_fgetc(BakFile *stream);
extern int bak_feof(BakFile *stream);
extern int bak_fwrite(void *ptr, int size, int count, BakFile *stream);
extern int bak_putc(int c, BakFile *stream);
extern void bak_setbuf(BakFile *stream, char *buffer);
extern void bak_init_resources(void);
extern void bak_shutdown_resources(void);
extern void bak_invalidate_archives(void);
extern unsigned long bak_filename_hash(char *filename);
extern int bak_resource_lookup(BakHandle *slot);
extern void bak_select_archive(int archive_index);
extern void bak_archive_seek(unsigned long absolute_offset);
extern BakHandle *bak_find_handle(BakFile *stream);

extern void interrupt far bak_int24_critical_handler();

extern long far dos_read(unsigned char far *buf, long count, int fd);
extern long far dos_write(unsigned char far *buf, long count, int fd);

#endif
