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
    /** 0x00: @ref io_filename_hash of the uppercased resource name. */
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
    int slotIndex;            /**< 0x0e: own pool slot; write-once, unread. */
    FILE *fp;                 /**< 0x10: open CRT stream on the payload. */
    unsigned long filePos;    /**< 0x12: cached fp seek offset. */
    unsigned int unused;      /**< 0x16: never read or written. */
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
    int archiveIndex;         /**< 0x00: 1-based archive index; 0 = loose. */
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

/**
 * @brief Init-once guard for the resource layer: `TRUE` after
 *        @ref bak_init_resources has run its one-time setup.
 *
 * `bak_init_resources` is called from every @ref bak_fopen; this flag makes it
 * idempotent (open `KRONDOR.RMF` + install the INT 24h handler exactly once).
 */
extern bool8 g_ioInitialized;
/**
 * @brief Sticky I/O-error flag: set on a write/close failure, cleared at the
 *        start of each @ref bak_fopen. Set-only — nothing reads it.
 *
 * OR-ed to `TRUE` by @ref bak_fclose, @ref bak_fwrite and @ref bak_putc when
 * their underlying CRT call fails; the `|=` makes it sticky across ops until the
 * next @ref bak_fopen resets it. No code tests, returns, or branches on it in
 * this build, so it is a vestigial accumulator kept for layout fidelity.
 */
extern bool16 g_ioError;

/**
 * @brief Far pointer to a DOS interrupt-service routine — the `getvect` /
 *        `setvect` vector shape, used to save and restore a handler.
 */
typedef void interrupt (far *IsrVector)();

/**
 * @brief Saved previous DOS INT 24h (critical-error) handler vector.
 *
 * Captured by @ref bak_init_resources via `getvect` before it installs
 * @ref io_critical_error_handler, and restored by @ref bak_shutdown_resources,
 * which then zeroes this slot so a second shutdown is a no-op.
 */
extern IsrVector g_ioPrevInt24Vector;


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


/**
 * @brief The @ref IoFile token most recently passed to @ref bak_fgetc.
 *
 * Written on every @ref bak_fgetc call and cleared by @ref bak_fopen, but never
 * read back anywhere in this build — a write-only trace latch, not a lookup
 * cache. Nothing consults it to short-circuit a later call.
 */
extern IoFile *g_ioLastFgetcFile;

/**
 * @brief The CRT `FILE *` that @ref bak_fgetc resolved @ref g_ioLastFgetcFile
 *        to and read a byte through.
 *
 * Mirrors the stdio stream actually handed to `fgetc`; written on every call and
 * cleared by @ref bak_fopen. Like @ref g_ioLastFgetcFile it is never read back,
 * so it too is a write-only trace, not consulted on later calls.
 */
extern FILE *g_ioLastFgetcCrtFile;

/**
 * @brief Reentrancy guard: `TRUE` while the resource layer is inside a `fopen`
 *        it wants to survive a DOS critical error.
 *
 * Read by @ref io_critical_error_handler: while set, the handler fails the DOS
 * call (returns 3) so @ref bak_fopen / @ref bak_select_archive can retry the
 * open in C, rather than letting DOS blindly retry (return 1).
 */
extern bool8 g_ioInFopen;

/**
 * @brief ISR-to-open signal: `TRUE` when a DOS critical error occurred during
 *        the current open, so it should be retried.
 *
 * Raised by @ref io_critical_error_handler and consumed by @ref bak_fopen's
 * retry loop, which clears it at the top of each attempt.
 */
extern bool8 g_ioFopenRetry;
/**
 * @brief The open archive stream is stale — close and reopen before next use.
 *
 * Raised by @ref io_critical_error_handler on a DOS critical error (media
 * change / drive-not-ready) during archive I/O; @ref bak_fopen then resets to
 * the slot-0 sentinel to tear down the suspect stream, clearing the flag.
 */
extern bool8 g_ioArchivesDirty;


/**
 * @brief Number of currently-open @ref g_ioHandles slots; gates the archive
 *        drive-probe in @ref bak_select_archive.
 */
extern char g_ioOpenHandleCount;


/**
 * @brief The query filename's hash, passed from @ref io_filename_hash to
 *        @ref bak_resource_lookup as the directory-scan key.
 */
extern unsigned long g_ioLookupHash;


/**
 * @brief Index into @ref g_ioArchives of the currently-open archive; 0 = none.
 *
 * Set by @ref bak_select_archive, which closes the previous archive's stream
 * before opening the new one; 0 is the loose / no-archive state.
 */
extern int g_ioCurrentArchive;


/**
 * @brief Number of archives registered from `KRONDOR.RMF` (indices `1..count`
 *        of @ref g_ioArchives).
 *
 * 0 before the map is read, or if it cannot be opened — which leaves the whole
 * archive layer disabled.
 */
extern int g_ioArchiveCount;


/**
 * @brief Initial accumulator for @ref io_filename_hash, from the
 *        `KRONDOR.RMF` header (0 in shipped data).
 *
 * Signed — sign-extended into the 32-bit hash, so the type is load-bearing.
 */
extern int g_ioHashSeed;


/**
 * @brief Per-character left-rotate count for @ref io_filename_hash, from the
 *        `KRONDOR.RMF` header (4 in shipped data).
 */
extern unsigned int g_ioHashRotate;


/**
 * @brief Cached result of the last @ref bak_find_handle lookup: the
 *        @ref FileHandle resolved for @ref g_ioFindHandleCacheKey.
 *
 * The value half of a one-entry memoization cache. When @ref bak_find_handle is
 * called again with the same @ref IoFile token it returns this directly,
 * skipping the pool scan.
 */
extern FileHandle *g_ioFindHandleCacheVal;

/**
 * @brief Cache key for @ref bak_find_handle: the @ref IoFile token whose lookup
 *        produced @ref g_ioFindHandleCacheVal.
 *
 * Set on each miss and cleared together with the value on a `NULL` query or a
 * failed lookup; a matching token on the next call is a cache hit.
 */
extern IoFile *g_ioFindHandleCacheKey;

extern IoFile *bak_fopen(char *filename, char *mode);
extern int bak_fclose(IoFile *file);
extern int bak_fread(void *ptr, int size, int count, IoFile *file);
extern int bak_fseek(IoFile *file, long offset, int whence);
extern long bak_ftell(IoFile *file);
extern long bak_filelength(IoFile *file);
extern void bak_rewind(IoFile *file);
extern int bak_fgetc(IoFile *file);
extern int bak_feof(IoFile *file);
extern int bak_fwrite(void *ptr, int size, int count, IoFile *file);
extern int bak_putc(int c, IoFile *file);
extern void bak_setbuf(IoFile *file, char *buffer);
extern void bak_init_resources(void);
extern void bak_shutdown_resources(void);
/**
 * @brief Mark the open archives stale so the next @ref bak_fopen reopens them.
 *
 * A media-change hook that raises @ref g_ioArchivesDirty. Unused in this build;
 * the same recovery is driven live by @ref io_critical_error_handler.
 */
extern void io_invalidate_archives(void);


/**
 * @brief Hash of a resource filename for the `KRONDOR.RMF` directory lookup.
 *
 * Uppercases @p filename in place and folds it into a rotating 32-bit hash
 * (seeded by @ref g_ioHashSeed, rotated by @ref g_ioHashRotate). The result is
 * also written to @ref g_ioLookupHash — the channel @ref bak_resource_lookup
 * actually reads — so the return value is redundant.
 *
 * @param filename Resource name; uppercased in place. NULL yields a 0 hash.
 * @return The 32-bit hash (a mirror of @ref g_ioLookupHash).
 */
extern unsigned long io_filename_hash(char *filename);


extern int bak_resource_lookup(FileHandle *slot);
extern void bak_select_archive(int archive_index);


/**
 * @brief Seek the current archive's stream to an absolute byte offset in
 *        `KRONDOR.001`.
 *
 * Indexes @ref g_ioArchives via @ref g_ioCurrentArchive and moves its
 * @ref Archive::fp there, but only when @ref Archive::filePos shows it isn't
 * already positioned — the cache skips a redundant `fseek`.
 *
 * @param offset Byte position within the archive (window base + read
 *        cursor). `long` to match `fseek`; always a non-negative file position.
 */
extern void io_archive_seek(long offset);


extern FileHandle *bak_find_handle(IoFile *file);


extern long far dos_read(unsigned char far *buf, long count, int fd);
extern long far dos_write(unsigned char far *buf, long count, int fd);

#endif
