/**
 * @file    RESOURCE.H
 * @brief   The game's resource-I/O layer.
 * @ingroup resource
 */
#ifndef BAK_RESOURCE_H
#define BAK_RESOURCE_H

#include "structs.h"

/**
 * @defgroup resource Resource I/O Layer
 * @brief Open any asset by name, whether it lives as a loose file on disk or
 *        packed inside the CD archive.
 *
 * This module is the single gateway between the game and its data. Every
 * subsystem — screens, dialog, sound, world, combat, save — reads its assets
 * through the stdio-shaped `bak_*` API declared here: a caller names a
 * resource and gets back an opaque @ref ResFile token that acts like an
 * ordinary file.
 *
 * An asset can live in one of two places, and this layer hides which:
 *   - a loose file on disk (dev builds, floppy installs, or a patch), or
 *   - a byte-range packed inside the archive `KRONDOR.001`.
 *
 * A loose file is tried first, so a loose copy transparently shadows the
 * packed one — ship packed, iterate loose.
 *
 * The archive is a pair of files: `KRONDOR.RMF` is the index (it maps each
 * resource name to where its bytes begin) and `KRONDOR.001` holds the packed
 * payload. Bundling the game's many resources behind a single open file keeps
 * it within DOS's open-handle limit while still serving many logical files.
 *
 * Because the data may sit on a CD, the layer also rides out "drive not
 * ready / please insert the disc" errors, retrying the open instead of
 * aborting.
 *
 * Nothing else in the codebase touches `KRONDOR.RMF` / `KRONDOR.001`
 * directly — this header is the entire public contract for reading game data.
 * @{
 */


/** @brief Number of slots in the @ref g_resHandles pool — the cap on
 *         simultaneously-open @ref bak_fopen handles. */
#define RES_HANDLE_POOL_SIZE 10


/** @brief Max archives registerable from `KRONDOR.RMF`; @ref g_resArchives
 *         has one more slot (index 0 is the "no archive" sentinel). */
#define RES_ARCHIVE_MAX 10


/**
 * @brief One record of the `KRONDOR.RMF` resource-index directory: a resource
 *        name's hash and where its data lives.
 *
 * Stored as a per-archive array in @ref Archive::directory, ended by an
 * all-zero terminator entry.
 */
typedef struct RmfEntry {
    /** 0x00: @ref res_filename_hash of the uppercased resource name. */
    unsigned long hash;
    /** 0x04: offset in `KRONDOR.001` of the 17-byte entry header. */
    unsigned long headerOffset;
} RmfEntry;

/**
 * @brief Runtime descriptor for one open resource archive (`KRONDOR.001`).
 *
 * Held in @ref g_resArchives (1-based; slot 0 is the "loose file / no archive"
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
typedef struct ResFile ResFile;


/**
 * @brief A file reference: either a filename (`char *`) or an open @ref ResFile
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
extern bool8 g_resInitialized;
/**
 * @brief Sticky I/O-error flag: set on a write/close failure, cleared at the
 *        start of each @ref bak_fopen. Set-only — nothing reads it.
 *
 * OR-ed to `TRUE` by @ref bak_fclose, @ref bak_fwrite and @ref bak_putc when
 * their underlying CRT call fails; the `|=` makes it sticky across ops until the
 * next @ref bak_fopen resets it. No code tests, returns, or branches on it in
 * this build, so it is a vestigial accumulator kept for layout fidelity.
 */
extern bool16 g_resError;

/**
 * @brief Far pointer to a DOS interrupt-service routine — the `getvect` /
 *        `setvect` vector shape, used to save and restore a handler.
 */
typedef void interrupt (far *IsrVector)();

/**
 * @brief Saved previous DOS INT 24h (critical-error) handler vector.
 *
 * Captured by @ref bak_init_resources via `getvect` before it installs
 * @ref res_critical_error_handler, and restored by @ref bak_shutdown_resources,
 * which then zeroes this slot so a second shutdown is a no-op.
 */
extern IsrVector g_resPrevInt24Vector;


/**
 * @brief Fixed pool of @ref RES_HANDLE_POOL_SIZE open-file handle slots
 *        (@ref FileHandle) shared by all @ref bak_fopen streams.
 */
extern FileHandle g_resHandles[RES_HANDLE_POOL_SIZE];


/**
 * @brief The registered resource archives (@ref Archive), indexed 1-based;
 *        index 0 is the "no archive" / loose-file sentinel.
 */
extern Archive g_resArchives[RES_ARCHIVE_MAX + 1];


/**
 * @brief The @ref ResFile token most recently passed to @ref bak_fgetc.
 *
 * Written on every @ref bak_fgetc call and cleared by @ref bak_fopen, but never
 * read back anywhere in this build — a write-only trace latch, not a lookup
 * cache. Nothing consults it to short-circuit a later call.
 */
extern ResFile *g_resLastFgetcFile;

/**
 * @brief The CRT `FILE *` that @ref bak_fgetc resolved @ref g_resLastFgetcFile
 *        to and read a byte through.
 *
 * Mirrors the stdio stream actually handed to `fgetc`; written on every call and
 * cleared by @ref bak_fopen. Like @ref g_resLastFgetcFile it is never read back,
 * so it too is a write-only trace, not consulted on later calls.
 */
extern FILE *g_resLastFgetcCrtFile;

/**
 * @brief Reentrancy guard: `TRUE` while the resource layer is inside a `fopen`
 *        it wants to survive a DOS critical error.
 *
 * Read by @ref res_critical_error_handler: while set, the handler fails the DOS
 * call (returns 3) so @ref bak_fopen / @ref bak_select_archive can retry the
 * open in C, rather than letting DOS blindly retry (return 1).
 */
extern bool8 g_resInFopen;

/**
 * @brief ISR-to-open signal: `TRUE` when a DOS critical error occurred during
 *        the current open, so it should be retried.
 *
 * Raised by @ref res_critical_error_handler and consumed by @ref bak_fopen's
 * retry loop, which clears it at the top of each attempt.
 */
extern bool8 g_resFopenRetry;
/**
 * @brief The open archive stream is stale — close and reopen before next use.
 *
 * Raised by @ref res_critical_error_handler on a DOS critical error (media
 * change / drive-not-ready) during archive I/O; @ref bak_fopen then resets to
 * the slot-0 sentinel to tear down the suspect stream, clearing the flag.
 */
extern bool8 g_resArchivesDirty;


/**
 * @brief Number of currently-open @ref g_resHandles slots; gates the archive
 *        drive-probe in @ref bak_select_archive.
 */
extern char g_resOpenHandleCount;


/**
 * @brief The query filename's hash, passed from @ref res_filename_hash to
 *        @ref bak_resource_lookup as the directory-scan key.
 */
extern unsigned long g_resLookupHash;


/**
 * @brief Index into @ref g_resArchives of the currently-open archive; 0 = none.
 *
 * Set by @ref bak_select_archive, which closes the previous archive's stream
 * before opening the new one; 0 is the loose / no-archive state.
 */
extern int g_resCurrentArchive;


/**
 * @brief Number of archives registered from `KRONDOR.RMF` (indices `1..count`
 *        of @ref g_resArchives).
 *
 * 0 before the map is read, or if it cannot be opened — which leaves the whole
 * archive layer disabled.
 */
extern int g_resArchiveCount;


/**
 * @brief Initial accumulator for @ref res_filename_hash, from the
 *        `KRONDOR.RMF` header (0 in shipped data).
 *
 * Signed — sign-extended into the 32-bit hash, so the type is load-bearing.
 */
extern int g_resHashSeed;


/**
 * @brief Per-character left-rotate count for @ref res_filename_hash, from the
 *        `KRONDOR.RMF` header (4 in shipped data).
 */
extern int g_resHashRotate;


/**
 * @brief Cached result of the last @ref res_resolve_handle lookup: the
 *        @ref FileHandle resolved for @ref g_resFindHandleCacheKey.
 *
 * The value half of a one-entry memoization cache. When @ref res_resolve_handle is
 * called again with the same @ref ResFile token it returns this directly,
 * skipping the pool scan.
 */
extern FileHandle *g_resFindHandleCacheVal;

/**
 * @brief Cache key for @ref res_resolve_handle: the @ref ResFile token whose lookup
 *        produced @ref g_resFindHandleCacheVal.
 *
 * Set on each miss and cleared together with the value on a `NULL` query or a
 * failed lookup; a matching token on the next call is a cache hit.
 */
extern ResFile *g_resFindHandleCacheKey;

extern ResFile *bak_fopen(char *filename, char *mode);
extern int bak_fclose(ResFile *file);
extern int bak_fread(void *ptr, int size, int count, ResFile *file);
extern int bak_fseek(ResFile *file, long offset, int whence);
extern long bak_ftell(ResFile *file);
extern long bak_filelength(ResFile *file);
extern void bak_rewind(ResFile *file);
extern int bak_fgetc(ResFile *file);
extern int bak_feof(ResFile *file);
extern int bak_fwrite(void *ptr, int size, int count, ResFile *file);
extern int bak_putc(int c, ResFile *file);
extern void bak_setbuf(ResFile *file, char *buffer);
extern void bak_init_resources(void);
extern void bak_shutdown_resources(void);
/**
 * @brief Mark the open archives stale so the next @ref bak_fopen reopens them.
 *
 * A media-change hook that raises @ref g_resArchivesDirty. Unused in this build;
 * the same recovery is driven live by @ref res_critical_error_handler.
 */
extern void res_invalidate_archives(void);


/**
 * @brief Hash of a resource filename for the `KRONDOR.RMF` directory lookup.
 *
 * Uppercases @p filename in place and folds it into a rotating 32-bit hash
 * (seeded by @ref g_resHashSeed, rotated by @ref g_resHashRotate). The result is
 * also written to @ref g_resLookupHash — the channel @ref bak_resource_lookup
 * actually reads — so the return value is redundant.
 *
 * @param filename Resource name; uppercased in place. NULL yields a 0 hash.
 * @return The 32-bit hash (a mirror of @ref g_resLookupHash).
 */
extern unsigned long res_filename_hash(char *filename);


extern int bak_resource_lookup(FileHandle *slot);
extern void bak_select_archive(int archive_index);


/**
 * @brief Seek the current archive's stream to an absolute byte offset in
 *        `KRONDOR.001`.
 *
 * Indexes @ref g_resArchives via @ref g_resCurrentArchive and moves its
 * @ref Archive::fp there, but only when @ref Archive::filePos shows it isn't
 * already positioned — the cache skips a redundant `fseek`.
 *
 * @param offset Absolute byte position within `KRONDOR.001` (window base + read
 *        cursor). Unsigned — always a non-negative file position, never a
 *        relative displacement (the seek is always `SEEK_SET`).
 */
extern void res_archive_seek(unsigned long offset);


extern long far dos_read(unsigned char far *buf, long count, int fd);
extern long far dos_write(unsigned char far *buf, long count, int fd);

/** @} */

#endif
