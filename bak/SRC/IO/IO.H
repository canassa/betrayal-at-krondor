/**
 * @file    IO.H
 * @brief   Resource-archive I/O layer: stdio-shaped `bak_*` wrappers over
 *          loose files and the `KRONDOR.RMF`-mapped archive resources.
 */
#ifndef BAK_IO_H
#define BAK_IO_H

#include "structs.h"


/** @brief Number of slots in the @ref g_ioHandles pool — the cap on
 *         simultaneously-open @ref bak_fopen handles. */
#define IO_HANDLE_POOL_SIZE 10


/** @brief Max archives registerable from `KRONDOR.RMF`; @ref g_ioArchives
 *         has one more slot (index 0 is the "no archive" sentinel). */
#define IO_ARCHIVE_MAX 10


/**
 * @brief One record of the `KRONDOR.RMF` resource-index directory: a resource
 *        name's hash and where its data lives.
 *
 * Stored as a per-archive array in @ref Archive::directory, ended by an
 * all-zero terminator entry.
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
 * Held in @ref g_ioArchives (1-based; slot 0 is the "loose file / no archive"
 * sentinel). Pairs the archive's identity from the RMF (@ref Archive::fileName,
 * @ref Archive::directory) with its live stdio stream (@ref Archive::fp,
 * @ref Archive::filePos). A runtime object, not an on-disk record.
 * Byte-packed; `sizeof` is 28.
 */
typedef struct Archive {
    char fileName[14];        /**< 0x00: NUL-padded payload name (13B used). */
    short slotIndex;          /**< 0x0e: own pool slot; write-once, unread. */
    FILE *fp;                 /**< 0x10: open CRT stream on the payload. */
    unsigned long filePos;    /**< 0x12: cached fp seek offset. */
    unsigned short unused;    /**< 0x16: never read or written. */
    RmfEntry far *directory;  /**< 0x18: loaded hash->offset table. */
} Archive;

/**
 * @brief A pooled open-file handle: either a loose stdio file or a byte-window
 *        into the archive.
 *
 * @ref FileHandle::stdioFile is the discriminant — non-zero for a loose file,
 * zero for an archive window (then @ref FileHandle::archiveIndex,
 * @ref FileHandle::baseOffset, @ref FileHandle::length and
 * @ref FileHandle::curOffset locate it). Byte-packed; `sizeof` 18.
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
 * @brief Opaque file token returned by @ref bak_fopen.
 *
 * Also produced by @c cached_file_open  (TBD-ref: IFFREAD.H lacks @file).
 * Under the hood a CRT `FILE *` or a @ref FileHandle slot; treat it as opaque —
 * pass it only to the `bak_*` functions, never dereference it. No definition.
 */
typedef struct IoFile IoFile;


/**
 * @brief A file reference: either a filename (`char *`) or an open @ref IoFile
 *        token.
 *
 * Typed `void` so both kinds pass without a cast.
 */
typedef void FileRef;

extern unsigned char g_bak_initialized;
extern short g_bak_io_error;
extern void far *g_int24_old_vector;


/**
 * @brief Fixed pool of @ref IO_HANDLE_POOL_SIZE open-file handle slots
 *        (@ref FileHandle) shared by all @ref bak_fopen streams.
 */
extern FileHandle g_ioHandles[IO_HANDLE_POOL_SIZE];


/**
 * @brief The registered resource archives (@ref Archive), indexed 1-based;
 *        index 0 is the "no archive" / loose-file sentinel.
 */
extern Archive g_ioArchives[IO_ARCHIVE_MAX + 1];


extern IoFile *g_pBakFgetcLastStream;
extern FILE *g_pBakActiveFgetcStream;
extern unsigned char g_bak_in_fopen;
extern unsigned char g_bak_fopen_retry;
extern unsigned char g_bak_archives_dirty;


/**
 * @brief Number of currently-open @ref g_ioHandles slots; gates the archive
 *        drive-probe in @ref bak_select_archive.
 */
extern unsigned char g_ioOpenHandleCount;


/**
 * @brief The query filename's hash, passed from @ref bak_filename_hash to
 *        @ref bak_resource_lookup as the directory-scan key.
 */
extern unsigned long g_ioLookupHash;


extern short g_bak_current_archive;


/**
 * @brief Number of archives registered from `KRONDOR.RMF` (indices `1..count`
 *        of @ref g_ioArchives).
 *
 * 0 before the map is read, or if it cannot be opened — which leaves the whole
 * archive layer disabled.
 */
extern int g_ioArchiveCount;


/**
 * @brief Initial accumulator for @ref bak_filename_hash, from the
 *        `KRONDOR.RMF` header (0 in shipped data).
 *
 * Signed — sign-extended into the 32-bit hash, so the type is load-bearing.
 */
extern short g_ioHashSeed;


/**
 * @brief Per-character left-rotate count for @ref bak_filename_hash, from the
 *        `KRONDOR.RMF` header (4 in shipped data).
 */
extern unsigned short g_ioHashRotate;


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
