/**
 * @file    RESOURCE.C
 * @brief   Resource-archive I/O layer: the `res_*` stdio wrappers, the
 *          `KRONDOR.RMF` directory loader, and the INT 24h critical-error ISR.
 */
#include <ctype.h>
#include <dos.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "structs.h"
#include "defines.h"
#include "SRC/IO/RESOURCE.H"
#include "SRC/SYS/DOSMEM.H"
#ifdef V102CD
#include "SRC/SYS/CFGPARSE.H"
#endif

bool16 g_resError;
IsrVector g_resPrevInt24Vector;
FileHandle g_resHandles[RES_HANDLE_POOL_SIZE];
Archive g_resArchives[RES_ARCHIVE_MAX + 1];
ResFile *g_resLastFgetcFile;
FILE *g_resLastFgetcCrtFile;
bool8 g_resInFopen;
bool8 g_resFopenRetry;
bool8 g_resArchivesDirty;
char g_resOpenHandleCount;
unsigned long g_resLookupHash;
int g_resCurrentArchive;
int g_resArchiveCount;
int g_resHashSeed;
int g_resHashRotate;
FileHandle *g_resFindHandleCacheVal;
ResFile *g_resFindHandleCacheKey;

bool8 g_resInitialized = FALSE;

static FileHandle *res_resolve_handle(ResFile *file);

ResFile *res_fopen(char *filename, char *mode) {
    char name[14];
    int count;
    register FileHandle *handle;
    register FILE *fp;

    // Recover from a prior media-change error before touching the archive.
    if (g_resArchivesDirty) {
        res_select_archive(0);
    }

    res_setup();
    g_resError = FALSE;
    if (g_resArchiveCount == 0) {
        return (ResFile *)fopen(filename, mode);
    }

    g_resLastFgetcCrtFile = NULL;
    g_resLastFgetcFile = NULL;
    handle = g_resHandles;
    count = RES_HANDLE_POOL_SIZE;

    // Find the first free slot in the handle pool.
    while (count != 0 && handle->inUse) {
        handle++;
        count--;
    }

    // Pool exhausted — no free handle.
    if (count == 0) {
        return NULL;
    }

    res_filename_hash(filename);

    // Try a loose file first, retrying if a critical error interrupts the open.
    g_resInFopen = TRUE;
    do {
        g_resFopenRetry = FALSE;
        fp = fopen(filename, mode);
    } while (g_resFopenRetry);

    g_resInFopen = FALSE;

    // Loose file: hand back a stdio-backed handle.
    if (fp != NULL) {
        handle->archiveIndex = 0;
        handle->baseOffset = handle->length = handle->curOffset = 0UL;
        handle->inUse = TRUE;
        handle->stdioFile = fp;
    } else {
        // Not loose: locate it in the archive by hash.
        if (!res_lookup(handle)) {
            return NULL;
        }

        res_select_archive(handle->archiveIndex);
        res_archive_seek(handle->baseOffset + handle->curOffset);
        fp = g_resArchives[g_resCurrentArchive].fp;
        fread(name, sizeof(name) - 1, 1, fp);
        fread(&handle->length, sizeof(handle->length), 1, fp);
        g_resArchives[g_resCurrentArchive].filePos = handle->baseOffset = ftell(fp);

        // Confirm the hash didn't collide: the stored name must match.
        if (stricmp(name, filename) != 0) {
            return NULL;
        }
        handle->curOffset = 0;
        handle->stdioFile = NULL;
        handle->inUse = TRUE;
    }

    g_resOpenHandleCount++;

    return (ResFile *)handle;
}

int res_fclose(ResFile *file) {
    int result;
    FileHandle *handle;

    result = 0;
    if (file == NULL)
        return -1;
    if ((g_resArchiveCount == 0) || (handle = res_resolve_handle(file)) == NULL) {
        result = fclose((FILE *)file);
    } else {
        res_resolve_handle(NULL);
        if (handle->stdioFile != NULL)
            result = fclose(handle->stdioFile);
        handle->inUse = FALSE;
        g_resOpenHandleCount--;
    }
    g_resError |= (result == -1 ? TRUE : FALSE);
    return result;
}

int res_fread(void *ptr, int size, int count, ResFile *file) {
    int itemsRead;
    bool16 singleObj;
    unsigned byteCount;
    FileHandle *handle;

    singleObj = FALSE;
    if (g_resArchiveCount == 0 || (handle = res_resolve_handle(file)) == NULL) {
        return fread(ptr, size, count, (FILE *)file);
    }
    if (handle->stdioFile != NULL) {
        return fread(ptr, size, count, handle->stdioFile);
    }
    if (count == 1) {
        count = size;
        size = 1;
        singleObj = TRUE;
    }
    byteCount = size * count;
    while (byteCount != 0 && byteCount > handle->length - handle->curOffset) {
        count--;
        byteCount -= size;
    }
    res_select_archive(handle->archiveIndex);
    res_archive_seek(handle->baseOffset + handle->curOffset);
    file = (ResFile *)g_resArchives[handle->archiveIndex].fp;
    itemsRead = fread(ptr, size, count, (FILE *)file);
    byteCount = itemsRead * size;
    handle->curOffset += byteCount;
    g_resArchives[handle->archiveIndex].filePos += byteCount;
    if (singleObj && itemsRead == count) {
        itemsRead = 1;
    }
    return itemsRead;
}

int res_fseek(ResFile *file, long offset, int whence) {
    FileHandle *handle;

    if (g_resArchiveCount == 0 || (handle = res_resolve_handle(file)) == NULL)
        return fseek((FILE *)file, offset, whence);
    if (handle->stdioFile != NULL)
        return fseek(handle->stdioFile, offset, whence);
    if (whence == SEEK_CUR) {
        offset += handle->curOffset;
    } else if (whence == SEEK_END) {
        if ((unsigned long)offset >= handle->length)
            offset = 0;
        else
            offset = handle->length - offset;
    }
    if ((unsigned long)offset > handle->length)
        offset = handle->length;
    handle->curOffset = offset;
    return 0;
}

long res_ftell(ResFile *file) {
    FileHandle *handle;

    if (g_resArchiveCount == 0 || (handle = res_resolve_handle(file)) == NULL)
        return ftell((FILE *)file);
    if (handle->stdioFile != NULL)
        return ftell(handle->stdioFile);
    else
        return handle->curOffset;
}

long res_filelength(ResFile *file) {
    long savedPos;
    long result;
    FileHandle *handle;

    if (g_resArchiveCount == 0 || (handle = res_resolve_handle(file)) == NULL ||
        (file = (ResFile *)handle->stdioFile) != NULL) {
        savedPos = ftell((FILE *)file);
        fseek((FILE *)file, 0L, SEEK_END);
        result = ftell((FILE *)file);
        fseek((FILE *)file, savedPos, SEEK_SET);
    } else {
        result = handle->length;
    }
    return result;
}

void res_rewind(ResFile *file) {
    res_fseek(file, 0L, SEEK_SET);
}

int res_fgetc(ResFile *file) {
    int result;
    FileHandle *handle;

    g_resLastFgetcFile = file;

    // No archive, or a loose token: read straight from the CRT stream.
    if (g_resArchiveCount == 0 || (handle = res_resolve_handle(file)) == NULL)
        return fgetc(g_resLastFgetcCrtFile = (FILE *)file);

    // Loose pooled handle: read from its stdio stream.
    if (handle->stdioFile != NULL)
        return fgetc(g_resLastFgetcCrtFile = handle->stdioFile);

    // Archive window: -1 at end of window, else read the next byte below.
    if (handle->curOffset >= handle->length)
        return -1;

    res_select_archive(handle->archiveIndex);
    res_archive_seek(handle->baseOffset + handle->curOffset);
    file = (ResFile *)g_resArchives[handle->archiveIndex].fp;
    result = fgetc(g_resLastFgetcCrtFile = (FILE *)file);
    handle->curOffset++;
    g_resArchives[handle->archiveIndex].filePos++;

    return result;
}

int res_feof(ResFile *file) {
    FileHandle *handle;

    if (g_resArchiveCount == 0 || (handle = res_resolve_handle(file)) == NULL)
        return feof((FILE *)file);
    if (handle->stdioFile != NULL)
        return feof(handle->stdioFile);
    else
        return handle->curOffset >= handle->length ? 1 : 0;
}

int res_fwrite(void *ptr, int size, int count, ResFile *file) {
    void *buf;
    FileHandle *handle;
    int written;

    buf = ptr;
    if (g_resArchiveCount == 0 || (handle = res_resolve_handle(file)) == NULL) {
        written = fwrite(buf, size, count, (FILE *)file);
    } else if (handle->stdioFile != NULL) {
        written = fwrite(buf, size, count, handle->stdioFile);
    } else {
        written = 0;
    }
    g_resError |= (written != count);
    return written;
}

int res_putc(int c, ResFile *file) {
    FileHandle *handle;
    int result;

    if (g_resArchiveCount == 0 || (handle = res_resolve_handle(file)) == NULL) {
        result = fputc(c, (FILE *)file);
    } else {
        if (handle->stdioFile != NULL) {
            result = fputc(c, handle->stdioFile);
        } else {
            result = -1;
        }
    }
    g_resError |= (result == -1) ? TRUE : FALSE;
    return result;
}

void res_setbuf(ResFile *file, char *buffer) {
    FileHandle *handle;

    if (g_resArchiveCount == 0 || (handle = res_resolve_handle(file)) == NULL) {
        setbuf((FILE *)file, buffer);
    } else {
        if (handle->stdioFile != NULL)
            setbuf(handle->stdioFile, buffer);
    }
}


static void interrupt far res_critical_error_handler();


void res_setup(void) {
    RmfEntry far *entry;
    int archiveIdx;
    int readCount;
    unsigned long hashVal;
    unsigned long offsetVal;
    char *filenamePtr;
    register FILE *fp;
    register Archive *arc;
#ifdef V102CD
    char path[80];
#endif

    // Init-once: called from every res_fopen, but only the first call runs.
    if (g_resInitialized)
        return;

    // Take over the DOS critical-error vector so a not-ready drive is survivable.
    g_resPrevInt24Vector = getvect(INT_CRITICAL_ERROR);
    setvect(INT_CRITICAL_ERROR, res_critical_error_handler);
    g_resInitialized = TRUE;

#ifdef V102CD
    strcpy(path, g_cfgResourceDrivePrefix);
    strcat(path, "krondor.rmf");
    filenamePtr = path;
#else
    filenamePtr = "krondor.rmf";
#endif
    // Open the RMF index; if it's absent the archive layer stays disabled (0 archives).
    if ((fp = fopen(filenamePtr, "rb")) == NULL)
        return;

    fread(&readCount, sizeof(readCount), 1, fp);
    fread(&g_resHashSeed, sizeof(g_resHashSeed), 1, fp);
    fread(&g_resHashRotate, sizeof(g_resHashRotate), 1, fp);

    g_resArchiveCount += readCount;
    archiveIdx = g_resArchiveCount - readCount + 1;

    // Load every archive the header registered.
    while (archiveIdx <= g_resArchiveCount) {
        arc = &g_resArchives[archiveIdx];

        // Read the archive's fixed record (payload name), then its entry count.
        fread(arc, sizeof(arc->fileName) - 1, 1, fp);
        fread(&readCount, sizeof(readCount), 1, fp);

        // Allocate its directory table: one slot per entry plus a zero terminator.
        entry = alloc_far((readCount + 1) * sizeof(RmfEntry), ALLOC_FAR_ZERO_FILL);
        arc->directory = entry;
        arc->slotIndex = archiveIdx;

        // Fill the directory: one hash -> payload-offset record per resource.
        while (readCount--) {
            fread(&hashVal, sizeof(hashVal), 1, fp);
            fread(&offsetVal, sizeof(offsetVal), 1, fp);
            entry->hash = hashVal;
            entry->headerOffset = offsetVal;
            entry++;
        }

        archiveIdx++;
    }

    fclose(fp);
}

void res_cleanup(void) {
    int i;

    // Free each archive's loaded directory table.
    i = 0;
    while (i <= RES_ARCHIVE_MAX) {
        if (g_resArchives[i].directory != NULL) {
            _freemem(g_resArchives[i].directory);
            g_resArchives[i].directory = NULL;
        }
        i++;
    }

    // Restore the previous INT 24h handler; zero the slot so a second call is a no-op.
    if (g_resPrevInt24Vector != NULL) {
        setvect(INT_CRITICAL_ERROR, g_resPrevInt24Vector);
        g_resPrevInt24Vector = NULL;
    }

    // Re-arm the init-once guard so res_setup runs again next time.
    g_resInitialized = FALSE;
}


void res_invalidate_archives(void) {
    g_resArchivesDirty = TRUE;
}


unsigned long res_filename_hash(char *filename) {
    unsigned long val;

    val = g_resHashSeed;
    if (filename == NULL)
        return g_resLookupHash = 0;

    while ((*filename = toupper(*filename)) != 0) {
        val += *filename;
        filename++;
        val = _lrotl(val, g_resHashRotate);
    }

    return g_resLookupHash = val;
}


int res_lookup(FileHandle *handle) {
    RmfEntry far *entry;
    unsigned long hash;
    int above;
    int below;
    int i;

    hash = g_resLookupHash;

    // Start in the current archive (or the first, if none is selected).
    if ((i = g_resCurrentArchive) == 0)
        i = 1;

    // Scan its directory for the hash — stop at a match or the 0 terminator.
    entry = g_resArchives[i].directory;
    while (entry->hash != 0 && entry->hash != hash)
        entry++;

    // Not here — prepare to spiral out to the neighbouring archives.
    above = g_resCurrentArchive + 1;
    below = g_resCurrentArchive - 1;

    // Search outward through the other archives, nearest first, until found.
    while (entry->hash != hash && (below > 0 || above <= g_resArchiveCount)) {
        // Check the next archive above.
        if (above <= g_resArchiveCount) {
            i = above;
            above++;
            entry = g_resArchives[i].directory;
            while (entry->hash != 0 && entry->hash != hash)
                entry++;
        }

        // Still no match — check the next archive below.
        if (entry->hash != hash) {
            if (below > 0) {
                i = below;
                below--;
                entry = g_resArchives[i].directory;
                while (entry->hash != 0 && entry->hash != hash)
                    entry++;
            }
        }
    }

    // Found: record where the resource lives; else report a miss.
    if (entry->hash == hash) {
        handle->archiveIndex = i;
        handle->baseOffset = entry->headerOffset;
        handle->length = handle->curOffset = 0;
        return TRUE;
    } else {
        return FALSE;
    }
}


void res_select_archive(int archiveIndex) {
    bool16 probeFailed;
    Archive *arc;
#ifdef V102CD
    char path[80];
#endif

    probeFailed = FALSE;
#ifdef V102CD
    strcpy(path, g_cfgResourceDrivePrefix);
    strcat(path, g_resArchives[archiveIndex].fileName);
    if (!g_resOpenHandleCount && archiveIndex) {
        if (fclose(fopen(path, "rb")))
            probeFailed = TRUE;
    }
#else
    if (!g_resOpenHandleCount && archiveIndex) {
        if (fclose(fopen(g_resArchives[archiveIndex].fileName, "rb")))
            probeFailed = TRUE;
    }
#endif
    if (archiveIndex != g_resCurrentArchive || probeFailed || g_resArchivesDirty) {
        arc = &g_resArchives[g_resCurrentArchive];
        if (arc->fp) {
            fclose(arc->fp);
            arc->fp = NULL;
        }
        g_resCurrentArchive = archiveIndex;
        arc = &g_resArchives[g_resCurrentArchive];
        if (archiveIndex) {
#ifdef V102CD
            strcpy(path, g_cfgResourceDrivePrefix);
            strcat(path, arc->fileName);
            g_resInFopen = TRUE;
            while ((arc->fp = fopen(path, "rb")) == NULL)
                g_resInFopen = FALSE;
#else
            g_resInFopen = TRUE;
            while ((arc->fp = fopen(arc->fileName, "rb")) == NULL)
                g_resInFopen = FALSE;
#endif
        }
        arc->filePos = 0;
        res_resolve_handle(NULL);
        g_resArchivesDirty = FALSE;
    }
}


void res_archive_seek(unsigned long offset) {
    Archive *ar;

    ar = &g_resArchives[g_resCurrentArchive];
    if (ar->filePos != offset) {
        fseek(ar->fp, (long)offset, SEEK_SET);
        ar->filePos = offset;
    }
}


/**
 * @brief Resolve a @ref ResFile token to its pooled @ref FileHandle, or `NULL`
 *        if it has none (a loose stdio file).
 *
 * Backed by a one-entry cache for hot read loops; a `NULL` token flushes it.
 */
static FileHandle *res_resolve_handle(ResFile *file) {
    FileHandle *handle;
    int count;

    // A NULL token is a request to flush the one-entry lookup cache.
    if (file == NULL) {
        g_resFindHandleCacheKey = NULL;
        g_resFindHandleCacheVal = NULL;
        return NULL;
    }

    // No archive loaded: every file is a loose stdio stream, not a pooled handle.
    if (g_resArchiveCount == 0)
        return NULL;

    // Cache hit: the same token as the last lookup returns its handle directly.
    if (file == g_resFindHandleCacheKey)
        return g_resFindHandleCacheVal;


    g_resFindHandleCacheKey = file;
    handle = g_resHandles;
    count = RES_HANDLE_POOL_SIZE;

    // Scan the handle pool for the handle this token points at.
    while (count != 0 && handle != (FileHandle *)file) {
        handle++;
        count--;
    }

    // Not found, or the handle is no longer in use: a miss.
    if (count == 0 || !handle->inUse) {
        handle = NULL;
        g_resFindHandleCacheKey = NULL;
    }

    return g_resFindHandleCacheVal = handle;
}


/**
 * @brief DOS INT 24h (critical-error) ISR: while a resource open is in flight
 *        (@ref g_resInFopen), fail the DOS call so @ref res_fopen retries in C.
 *
 * Returns @ref INT24_FAIL when @ref g_resInFopen is set, else @ref INT24_RETRY,
 * and raises @ref g_resFopenRetry and @ref g_resArchivesDirty. A Borland
 * `interrupt` function: the params are the pushed register frame; only @p ax is
 * used.
 *
 * @param bp,di,si,ds,es,dx,cx,bx  Saved registers; unused (positions @p ax).
 * @param ax  Saved AX; overwritten with the INT 24h return code.
 */
static void interrupt far res_critical_error_handler(unsigned _bp, unsigned di, unsigned si,
                                             unsigned ds, unsigned es, unsigned dx,
                                             unsigned cx, unsigned bx, unsigned ax) {
    ax = g_resInFopen ? INT24_FAIL : INT24_RETRY;
    g_resFopenRetry = TRUE;
    g_resArchivesDirty = TRUE;
}
