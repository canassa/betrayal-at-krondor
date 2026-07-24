/**
 * @file    IO.H
 * @brief   Resource-archive I/O layer: stdio-shaped `bak_*` wrappers over
 *          loose files and the `KRONDOR.RMF`-mapped archive resources.
 */
#ifndef BAK_IO_H
#define BAK_IO_H

#include "structs.h"

/**
 * @brief One record of the `KRONDOR.RMF` resource-index directory.
 *
 * An 8-byte packed `(hash, offset)` pair; @ref bak_init_resources loads a
 * per-archive array of them into @ref Archive::directory, terminated by an
 * all-zero slot (@ref RmfEntry::hash of 0). @ref bak_resource_lookup hashes a
 * resource name and linear-scans for the matching @ref RmfEntry::hash.
 */
typedef struct RmfEntry {
    /** 0x00: @ref bak_filename_hash of the uppercased resource name. */
    unsigned long hash;
    /** 0x04: offset in `KRONDOR.001` of the 17-byte entry header. */
    unsigned long headerOffset;
} RmfEntry;

/**
 * @brief Runtime descriptor for one open resource archive (`KRONDOR.001`).
 *
 * Built by @c bak_init_resources  (TBD-ref: not yet documented) from the
 * `KRONDOR.RMF` index and held in @ref g_bak_archives (up to 11, indexed
 * 1-based; slot 0 is the "loose file / no archive" sentinel). It pairs the
 * archive identity taken from the RMF (@ref Archive::fileName and the
 * @ref Archive::directory of @ref RmfEntry records) with live stdio state
 * (@ref Archive::fp — a genuine CRT `FILE *`, not a @ref IoFile token — and
 * @ref Archive::filePos). Not an on-disk record: only @ref Archive::fileName
 * arrives in bulk, so the two never-touched fields are just free space.
 * Byte-packed; `sizeof` is 28.
 */
typedef struct Archive {
    char fileName[13];        /**< 0x00: NUL-padded payload name. */
    char padUnused;           /**< 0x0d: alignment filler; unused. */
    short slotIndex;          /**< 0x0e: own pool slot; write-once, unread. */
    FILE *fp;                 /**< 0x10: open CRT stream on the payload. */
    unsigned long filePos;    /**< 0x12: cached fp seek offset. */
    unsigned short unused;    /**< 0x16: never read or written. */
    RmfEntry far *directory;  /**< 0x18: loaded hash->offset table. */
} Archive;

/**
 * @brief A pooled open-file handle: a loose stdio file or an archive window.
 *
 * @ref bak_fopen returns a @ref IoFile token that is really the address of one
 * of these @ref g_ioHandles slots. Two states, told apart by
 * @ref FileHandle::stdioFile: non-zero is a loose file (every op delegates to
 * CRT stdio); zero is a byte window into `KRONDOR.001` described by
 * @ref FileHandle::archiveIndex, @ref FileHandle::baseOffset,
 * @ref FileHandle::length and @ref FileHandle::curOffset. An in-memory pool,
 * not a disk record; byte-packed, `sizeof` 18.
 */
typedef struct FileHandle {
    short archiveIndex;       /**< 0x00: 1-based archive index; 0 = loose. */
    unsigned long baseOffset; /**< 0x02: payload start in KRONDOR.001. */
    unsigned long length;     /**< 0x06: resource payload size. */
    unsigned long curOffset;  /**< 0x0a: read cursor within the window. */
    bool16 inUse;             /**< 0x0e: pool slot occupied. */
    FILE *stdioFile;          /**< 0x10: loose stream; 0 = archive window. */
} FileHandle;

/**
 * @brief Opaque file token from bak_fopen()/cached_file_open().
 *
 * Really a CRT `FILE *` or a @ref FileHandle pool slot; bak_find_handle() tells
 * them apart on every bak_* call. Store it, compare it, pass it back — never
 * dereference it or hand it to CRT stdio. Intentionally has no definition.
 */
typedef struct IoFile IoFile;
/**
 * @brief A file reference: either a filename (`char *`) or an open ::IoFile token.
 *
 * is_file_cached() tells the two apart at runtime by pointer identity. Plain void
 * underneath, so both kinds pass without casts.
 */
typedef void FileRef;

extern unsigned char g_bak_initialized;
extern short g_bak_io_error;
extern void far *g_int24_old_vector;
extern FileHandle g_ioHandles[10];
extern Archive g_bak_archives[11];
extern IoFile *g_pBakFgetcLastStream;
extern FILE *g_pBakActiveFgetcStream;
extern unsigned char g_bak_in_fopen;
extern unsigned char g_bak_fopen_retry;
extern unsigned char g_bak_archives_dirty;
extern unsigned char g_ioOpenHandleCount;
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
extern FileHandle *g_pBakFindHandleCacheVal;
extern IoFile *g_pBakFindHandleCacheKey;

extern IoFile *bak_fopen(char *filename, char *mode);
extern int bak_fclose(IoFile *stream);
extern int bak_fread(void *ptr, int size, int count, IoFile *stream);
extern int bak_fseek(IoFile *stream, long offset, int whence);
extern long bak_ftell(IoFile *stream);
extern long bak_filelength(IoFile *stream);
extern void bak_rewind(IoFile *stream);
extern int bak_fgetc(IoFile *stream);
extern int bak_feof(IoFile *stream);
extern int bak_fwrite(void *ptr, int size, int count, IoFile *stream);
extern int bak_putc(int c, IoFile *stream);
extern void bak_setbuf(IoFile *stream, char *buffer);
extern void bak_init_resources(void);
extern void bak_shutdown_resources(void);
extern void bak_invalidate_archives(void);
extern unsigned long bak_filename_hash(char *filename);
extern int bak_resource_lookup(FileHandle *slot);
extern void bak_select_archive(int archive_index);
extern void bak_archive_seek(unsigned long absolute_offset);
extern FileHandle *bak_find_handle(IoFile *stream);

extern void interrupt far bak_int24_critical_handler();

extern long far dos_read(unsigned char far *buf, long count, int fd);
extern long far dos_write(unsigned char far *buf, long count, int fd);

#endif
