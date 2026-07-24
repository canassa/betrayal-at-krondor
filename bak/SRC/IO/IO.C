#include <ctype.h>
#include <dos.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "structs.h"
#include "defines.h"
#include "SRC/IO/IO.H"
#include "SRC/SYS/DOSMEM.H"
#ifdef V102CD
#include "SRC/GAME/CFGPARSE.H"
#endif

bool16 g_ioError;
IsrVector g_ioPrevInt24Vector;
FileHandle g_ioHandles[IO_HANDLE_POOL_SIZE];
Archive g_ioArchives[IO_ARCHIVE_MAX + 1];
IoFile *g_ioLastFgetcFile;
FILE *g_ioLastFgetcCrtFile;
bool8 g_ioInFopen;
bool8 g_ioFopenRetry;
bool8 g_ioArchivesDirty;
unsigned char g_ioOpenHandleCount;
unsigned long g_ioLookupHash;
int g_ioCurrentArchive;
int g_ioArchiveCount;
short g_ioHashSeed;
unsigned short g_ioHashRotate;
FileHandle *g_ioFindHandleCacheVal;
IoFile *g_ioFindHandleCacheKey;

bool8 g_ioInitialized = FALSE;

IoFile *bak_fopen(char *filename, char *mode) {
    char name[14];
    int count;
    register FileHandle *slot;
    register FILE *fp;

    if (g_ioArchivesDirty) {
        bak_select_archive(0);
    }
    bak_init_resources();
    g_ioError = FALSE;
    if (g_ioArchiveCount == 0) {
        return (IoFile *)fopen(filename, mode);
    }
    g_ioLastFgetcCrtFile = NULL;
    g_ioLastFgetcFile = NULL;
    slot = g_ioHandles;
    count = IO_HANDLE_POOL_SIZE;
    while (count != 0 && slot->inUse) {
        slot++;
        count--;
    }
    if (count == 0) {
        return 0;
    }
    io_filename_hash(filename);
    g_ioInFopen = TRUE;
    do {
        g_ioFopenRetry = FALSE;
        fp = fopen(filename, mode);
    } while (g_ioFopenRetry);
    g_ioInFopen = FALSE;
    if (fp != 0) {
        slot->archiveIndex = 0;
        slot->baseOffset = slot->length = slot->curOffset = 0UL;
        slot->inUse = TRUE;
        slot->stdioFile = fp;
    } else {
        if (!bak_resource_lookup(slot)) {
            return 0;
        }
        bak_select_archive(slot->archiveIndex);
        io_archive_seek(slot->baseOffset + slot->curOffset);
        fp = g_ioArchives[g_ioCurrentArchive].fp;
        fread(name, 0xd, 1, fp);
        fread(&slot->length, 4, 1, fp);
        g_ioArchives[g_ioCurrentArchive].filePos = slot->baseOffset = ftell(fp);
        if (stricmp(name, filename) != 0) {
            return 0;
        }
        slot->curOffset = 0;
        slot->stdioFile = 0;
        slot->inUse = TRUE;
    }
    g_ioOpenHandleCount++;
    return (IoFile *)slot;
}

int bak_fclose(IoFile *file) {
    int result;
    FileHandle *handle;

    result = 0;
    if (file == 0)
        return -1;
    if ((g_ioArchiveCount == 0) || (handle = bak_find_handle(file)) == 0) {
        result = fclose((FILE *)file);
    } else {
        bak_find_handle(0);
        if (handle->stdioFile != 0)
            result = fclose(handle->stdioFile);
        handle->inUse = FALSE;
        g_ioOpenHandleCount--;
    }
    g_ioError |= (result == -1 ? TRUE : FALSE);
    return result;
}

int bak_fread(void *ptr, int size, int count, IoFile *file) {
    int n_read;
    int single_obj;
    unsigned nbytes;
    FileHandle *handle;

    single_obj = 0;
    if (g_ioArchiveCount == 0 || (handle = bak_find_handle(file)) == 0) {
        return fread(ptr, size, count, (FILE *)file);
    }
    if (handle->stdioFile != 0) {
        return fread(ptr, size, count, handle->stdioFile);
    }
    if (count == 1) {
        count = size;
        size = 1;
        single_obj = 1;
    }
    nbytes = size * count;
    while (nbytes != 0 && nbytes > handle->length - handle->curOffset) {
        count--;
        nbytes -= size;
    }
    bak_select_archive(handle->archiveIndex);
    io_archive_seek(handle->baseOffset + handle->curOffset);
    file = (IoFile *)g_ioArchives[handle->archiveIndex].fp;
    n_read = fread(ptr, size, count, (FILE *)file);
    nbytes = n_read * size;
    handle->curOffset += nbytes;
    g_ioArchives[handle->archiveIndex].filePos += nbytes;
    if (single_obj != 0 && n_read == count) {
        n_read = 1;
    }
    return n_read;
}

int bak_fseek(IoFile *file, long offset, int whence) {
    FileHandle *handle;

    if (g_ioArchiveCount == 0 || (handle = bak_find_handle(file)) == 0)
        return fseek((FILE *)file, offset, whence);
    if (handle->stdioFile != 0)
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

long bak_ftell(IoFile *file) {
    FileHandle *handle;

    if (g_ioArchiveCount == 0 || (handle = bak_find_handle(file)) == 0)
        return ftell((FILE *)file);
    if (handle->stdioFile != 0)
        return ftell(handle->stdioFile);
    else
        return handle->curOffset;
}

long bak_filelength(IoFile *file) {
    long saved_pos;
    long result;
    FileHandle *handle;

    if (g_ioArchiveCount == 0 || (handle = bak_find_handle(file)) == 0 ||
        (file = (IoFile *)handle->stdioFile) != 0) {
        saved_pos = ftell((FILE *)file);
        fseek((FILE *)file, 0L, SEEK_END);
        result = ftell((FILE *)file);
        fseek((FILE *)file, saved_pos, SEEK_SET);
    } else {
        result = handle->length;
    }
    return result;
}

void bak_rewind(IoFile *file) {
    bak_fseek(file, 0L, SEEK_SET);
}

int bak_fgetc(IoFile *file) {
    int result;
    FileHandle *handle;

    g_ioLastFgetcFile = file;
    if (g_ioArchiveCount == 0 || (handle = bak_find_handle(file)) == 0)
        return fgetc(g_ioLastFgetcCrtFile = (FILE *)file);
    if (handle->stdioFile != 0)
        return fgetc(g_ioLastFgetcCrtFile = handle->stdioFile);
    if (handle->curOffset >= handle->length)
        return -1;
    bak_select_archive(handle->archiveIndex);
    io_archive_seek(handle->baseOffset + handle->curOffset);
    file = (IoFile *)g_ioArchives[handle->archiveIndex].fp;
    result = fgetc(g_ioLastFgetcCrtFile = (FILE *)file);
    handle->curOffset++;
    g_ioArchives[handle->archiveIndex].filePos++;
    return result;
}

int bak_feof(IoFile *file) {
    FileHandle *handle;

    if (g_ioArchiveCount == 0 || (handle = bak_find_handle(file)) == 0)
        return ((FILE *)file)->flags & 0x20;
    if (handle->stdioFile != 0)
        return handle->stdioFile->flags & 0x20;
    else
        return handle->curOffset >= handle->length ? 1 : 0;
}

int bak_fwrite(void *ptr, int size, int count, IoFile *file) {
    void *buf;
    FileHandle *handle;
    int written;

    buf = ptr;
    if (g_ioArchiveCount == 0 || (handle = bak_find_handle(file)) == 0) {
        written = fwrite(buf, size, count, (FILE *)file);
    } else if (handle->stdioFile != 0) {
        written = fwrite(buf, size, count, handle->stdioFile);
    } else {
        written = 0;
    }
    g_ioError |= (written != count);
    return written;
}

int bak_putc(int c, IoFile *file) {
    FileHandle *handle;
    int result;

    if (g_ioArchiveCount == 0 || (handle = bak_find_handle(file)) == 0) {
        result = fputc(c, (FILE *)file);
    } else {
        if (handle->stdioFile != 0) {
            result = fputc(c, handle->stdioFile);
        } else {
            result = -1;
        }
    }
    g_ioError |= (result == -1) ? TRUE : FALSE;
    return result;
}

void bak_setbuf(IoFile *file, char *buffer) {
    FileHandle *handle;

    if (g_ioArchiveCount == 0 || (handle = bak_find_handle(file)) == 0) {
        setbuf((FILE *)file, buffer);
    } else {
        if (handle->stdioFile != 0)
            setbuf(handle->stdioFile, buffer);
    }
}

void bak_init_resources(void) {
    RmfEntry far *entry;
    short archive_idx;
    short read_count;
    unsigned long hashVal;
    unsigned long offsetVal;
    char *filename_ptr;
    register FILE *fp;
    register Archive *arc;
#ifdef V102CD
    char path[80];
#endif

    if (g_ioInitialized != 0)
        return;

    g_ioPrevInt24Vector = getvect(INT_CRITICAL_ERROR);

    setvect(INT_CRITICAL_ERROR, io_critical_error_handler);

    g_ioInitialized = TRUE;

#ifdef V102CD
    strcpy(path, g_cfgResourceDrivePrefix);
    strcat(path, "krondor.rmf");
    filename_ptr = path;
    if ((fp = fopen(filename_ptr, "rb")) == 0)
        return;
#else
    filename_ptr = "krondor.rmf";
    if ((fp = fopen(filename_ptr, "rb")) == 0)
        return;
#endif

    fread(&read_count, 2, 1, fp);
    fread(&g_ioHashSeed, 2, 1, fp);
    fread(&g_ioHashRotate, 2, 1, fp);

    g_ioArchiveCount += read_count;
    archive_idx = g_ioArchiveCount - read_count + 1;

    while (archive_idx <= g_ioArchiveCount) {
        arc = &g_ioArchives[archive_idx];

        fread(arc, 13, 1, fp);
        fread(&read_count, 2, 1, fp);

        entry = alloc_far((unsigned long)((unsigned short)(read_count + 1) * 8), ALLOC_FAR_ZERO_FILL);
        arc->directory = entry;
        arc->slotIndex = archive_idx;

        while (read_count--) {
            fread(&hashVal, 4, 1, fp);
            fread(&offsetVal, 4, 1, fp);
            entry->hash = hashVal;
            entry->headerOffset = offsetVal;
            entry++;
        }

        archive_idx++;
    }

    fclose(fp);
}

void bak_shutdown_resources(void) {
    int i;

    i = 0;
    while (i <= IO_ARCHIVE_MAX) {
        if (g_ioArchives[i].directory != 0) {
            _freemem(g_ioArchives[i].directory);
            g_ioArchives[i].directory = 0;
        }
        i++;
    }
    if (g_ioPrevInt24Vector != NULL) {
        setvect(INT_CRITICAL_ERROR, g_ioPrevInt24Vector);
        g_ioPrevInt24Vector = NULL;
    }
    g_ioInitialized = FALSE;
}

void io_invalidate_archives(void) {
    g_ioArchivesDirty = TRUE;
}

unsigned long io_filename_hash(char *filename) {
    unsigned long val;

    val = g_ioHashSeed;
    if (filename == NULL)
        return g_ioLookupHash = 0;

    while ((*filename = toupper(*filename)) != 0) {
        val += *filename;
        filename++;
        val = _lrotl(val, g_ioHashRotate);
    }

    return g_ioLookupHash = val;
}

int bak_resource_lookup(FileHandle *slot) {
    RmfEntry far *entry;
    unsigned long hash;
    int above;
    int below;
    int i;

    hash = g_ioLookupHash;

    if ((i = g_ioCurrentArchive) == 0)
        i = 1;

    entry = g_ioArchives[i].directory;
    while (entry->hash != 0 && entry->hash != hash)
        entry++;

    above = g_ioCurrentArchive + 1;
    below = g_ioCurrentArchive - 1;

    while (entry->hash != hash && (below > 0 || above <= g_ioArchiveCount)) {
        if (above <= g_ioArchiveCount) {
            i = above;
            above++;
            entry = g_ioArchives[i].directory;
            while (entry->hash != 0 && entry->hash != hash)
                entry++;
        }

        if (entry->hash != hash) {
            if (below > 0) {
                i = below;
                below--;
                entry = g_ioArchives[i].directory;
                while (entry->hash != 0 && entry->hash != hash)
                    entry++;
            }
        }
    }

    if (entry->hash == hash) {
        slot->archiveIndex = i;
        slot->baseOffset = entry->headerOffset;
        slot->length = slot->curOffset = 0;
        return 1;
    } else {
        return 0;
    }
}

void bak_select_archive(int archive_index) {
    int probe_failed;
    Archive *arc;
#ifdef V102CD
    char path[80];
#endif

    probe_failed = 0;
#ifdef V102CD
    strcpy(path, g_cfgResourceDrivePrefix);
    strcat(path, g_ioArchives[archive_index].fileName);
    if (!(char)g_ioOpenHandleCount && archive_index) {
        if (fclose(fopen(path, "rb")))
            probe_failed = 1;
    }
#else
    if (!(char)g_ioOpenHandleCount && archive_index) {
        if (fclose(fopen(g_ioArchives[archive_index].fileName, "rb")))
            probe_failed = 1;
    }
#endif
    if (archive_index != g_ioCurrentArchive || probe_failed || g_ioArchivesDirty) {
        arc = &g_ioArchives[g_ioCurrentArchive];
        if (arc->fp) {
            fclose(arc->fp);
            arc->fp = 0;
        }
        g_ioCurrentArchive = archive_index;
        arc = &g_ioArchives[g_ioCurrentArchive];
        if (archive_index) {
#ifdef V102CD
            strcpy(path, g_cfgResourceDrivePrefix);
            strcat(path, arc->fileName);
            g_ioInFopen = TRUE;
            while ((arc->fp = fopen(path, "rb")) == 0)
                g_ioInFopen = FALSE;
#else
            g_ioInFopen = TRUE;
            while ((arc->fp = fopen(arc->fileName, "rb")) == 0)
                g_ioInFopen = FALSE;
#endif
        }
        arc->filePos = 0;
        bak_find_handle(0);
        g_ioArchivesDirty = FALSE;
    }
}

void io_archive_seek(long offset) {
    Archive *ar;

    ar = &g_ioArchives[g_ioCurrentArchive];
    if (ar->filePos != offset) {
        fseek(ar->fp, offset, SEEK_SET);
        ar->filePos = offset;
    }
}

FileHandle *bak_find_handle(IoFile *file) {
    FileHandle *slot;
    int count;

    if (file == 0) {
        g_ioFindHandleCacheKey = NULL;
        g_ioFindHandleCacheVal = NULL;
        return NULL;
    }
    if (g_ioArchiveCount == 0)
        return 0;
    if (file == g_ioFindHandleCacheKey)
        return g_ioFindHandleCacheVal;
    g_ioFindHandleCacheKey = file;
    slot = g_ioHandles;
    count = IO_HANDLE_POOL_SIZE;
    while (count != 0 && slot != (FileHandle *)file) {
        slot++;
        count--;
    }
    if (count == 0 || !slot->inUse) {
        slot = NULL;
        g_ioFindHandleCacheKey = NULL;
    }
    return g_ioFindHandleCacheVal = slot;
}

/**
 * @brief DOS INT 24h (critical-error) ISR: while a resource open is in flight
 *        (@ref g_ioInFopen), fail the DOS call so @ref bak_fopen retries in C.
 *
 * Returns @ref INT24_FAIL when @ref g_ioInFopen is set, else @ref INT24_RETRY,
 * and raises @ref g_ioFopenRetry and @ref g_ioArchivesDirty. A Borland
 * `interrupt` function: the params are the pushed register frame; only @p ax is
 * used.
 *
 * @param bp,di,si,ds,es,dx,cx,bx  Saved registers; unused (positions @p ax).
 * @param ax  Saved AX; overwritten with the INT 24h return code.
 */
void interrupt far io_critical_error_handler(unsigned bp, unsigned di, unsigned si,
                                             unsigned ds, unsigned es, unsigned dx,
                                             unsigned cx, unsigned bx, unsigned ax) {
    ax = g_ioInFopen ? INT24_FAIL : INT24_RETRY;
    g_ioFopenRetry = TRUE;
    g_ioArchivesDirty = TRUE;
}
