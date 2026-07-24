#include <ctype.h>
#include <dos.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "structs.h"
#include "SRC/IO/IO.H"
#include "SRC/SYS/DOSMEM.H"
#ifdef V102CD
#include "SRC/GAME/CFGPARSE.H"
#endif

short g_bak_io_error;
void far *g_int24_old_vector;
FileHandle g_ioHandles[IO_HANDLE_POOL_SIZE];
Archive g_ioArchives[IO_ARCHIVE_MAX + 1];
IoFile *g_pBakFgetcLastStream;
FILE *g_pBakActiveFgetcStream;
unsigned char g_bak_in_fopen;
unsigned char g_bak_fopen_retry;
unsigned char g_bak_archives_dirty;
unsigned char g_ioOpenHandleCount;
unsigned long g_ioLookupHash;
short g_bak_current_archive;
int g_ioArchiveCount;
short g_ioHashSeed;
unsigned short g_ioHashRotate;
FileHandle *g_pBakFindHandleCacheVal;
IoFile *g_pBakFindHandleCacheKey;

unsigned char g_bak_initialized = 0x00;

IoFile *bak_fopen(char *filename, char *mode) {
    char name[14];
    int count;
    register FileHandle *slot;
    register FILE *fp;

    if (g_bak_archives_dirty) {
        bak_select_archive(0);
    }
    bak_init_resources();
    g_bak_io_error = 0;
    if (g_ioArchiveCount == 0) {
        return (IoFile *)fopen(filename, mode);
    }
    g_pBakActiveFgetcStream = 0;
    g_pBakFgetcLastStream = 0;
    slot = g_ioHandles;
    count = IO_HANDLE_POOL_SIZE;
    while (count != 0 && slot->inUse != 0) {
        slot++;
        count--;
    }
    if (count == 0) {
        return 0;
    }
    bak_filename_hash(filename);
    g_bak_in_fopen = 1;
    do {
        g_bak_fopen_retry = 0;
        fp = fopen(filename, mode);
    } while (g_bak_fopen_retry != 0);
    g_bak_in_fopen = 0;
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
        bak_archive_seek(slot->baseOffset + slot->curOffset);
        fp = g_ioArchives[g_bak_current_archive].fp;
        fread(name, 0xd, 1, fp);
        fread(&slot->length, 4, 1, fp);
        g_ioArchives[g_bak_current_archive].filePos = slot->baseOffset = ftell(fp);
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

int bak_fclose(IoFile *stream) {
    int result;
    FileHandle *handle;

    result = 0;
    if (stream == 0)
        return -1;
    if ((g_ioArchiveCount == 0) || (handle = bak_find_handle(stream)) == 0) {
        result = fclose((FILE *)stream);
    } else {
        bak_find_handle(0);
        if (handle->stdioFile != 0)
            result = fclose(handle->stdioFile);
        handle->inUse = FALSE;
        g_ioOpenHandleCount--;
    }
    g_bak_io_error |= (result == -1 ? 1 : 0);
    return result;
}

int bak_fread(void *ptr, int size, int count, IoFile *stream) {
    int n_read;
    int single_obj;
    unsigned nbytes;
    FileHandle *handle;

    single_obj = 0;
    if (g_ioArchiveCount == 0 || (handle = bak_find_handle(stream)) == 0) {
        return fread(ptr, size, count, (FILE *)stream);
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
    bak_archive_seek(handle->baseOffset + handle->curOffset);
    stream = (IoFile *)g_ioArchives[handle->archiveIndex].fp;
    n_read = fread(ptr, size, count, (FILE *)stream);
    nbytes = n_read * size;
    handle->curOffset += nbytes;
    g_ioArchives[handle->archiveIndex].filePos += nbytes;
    if (single_obj != 0 && n_read == count) {
        n_read = 1;
    }
    return n_read;
}

int bak_fseek(IoFile *stream, long offset, int whence) {
    FileHandle *handle;

    if (g_ioArchiveCount == 0 || (handle = bak_find_handle(stream)) == 0)
        return fseek((FILE *)stream, offset, whence);
    if (handle->stdioFile != 0)
        return fseek(handle->stdioFile, offset, whence);
    if (whence == 1) {
        offset += handle->curOffset;
    } else if (whence == 2) {
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

long bak_ftell(IoFile *stream) {
    FileHandle *handle;

    if (g_ioArchiveCount == 0 || (handle = bak_find_handle(stream)) == 0)
        return ftell((FILE *)stream);
    if (handle->stdioFile != 0)
        return ftell(handle->stdioFile);
    else
        return handle->curOffset;
}

long bak_filelength(IoFile *stream) {
    long saved_pos;
    long result;
    FileHandle *handle;

    if (g_ioArchiveCount == 0 || (handle = bak_find_handle(stream)) == 0 ||
        (stream = (IoFile *)handle->stdioFile) != 0) {
        saved_pos = ftell((FILE *)stream);
        fseek((FILE *)stream, 0L, 2);
        result = ftell((FILE *)stream);
        fseek((FILE *)stream, saved_pos, 0);
    } else {
        result = handle->length;
    }
    return result;
}

void bak_rewind(IoFile *stream) {
    bak_fseek(stream, 0L, 0);
}

int bak_fgetc(IoFile *stream) {
    int result;
    FileHandle *handle;

    g_pBakFgetcLastStream = stream;
    if (g_ioArchiveCount == 0 || (handle = bak_find_handle(stream)) == 0)
        return fgetc(g_pBakActiveFgetcStream = (FILE *)stream);
    if (handle->stdioFile != 0)
        return fgetc(g_pBakActiveFgetcStream = handle->stdioFile);
    if (handle->curOffset >= handle->length)
        return -1;
    bak_select_archive(handle->archiveIndex);
    bak_archive_seek(handle->baseOffset + handle->curOffset);
    stream = (IoFile *)g_ioArchives[handle->archiveIndex].fp;
    result = fgetc(g_pBakActiveFgetcStream = (FILE *)stream);
    handle->curOffset++;
    g_ioArchives[handle->archiveIndex].filePos++;
    return result;
}

int bak_feof(IoFile *stream) {
    FileHandle *handle;

    if (g_ioArchiveCount == 0 || (handle = bak_find_handle(stream)) == 0)
        return ((FILE *)stream)->flags & 0x20;
    if (handle->stdioFile != 0)
        return handle->stdioFile->flags & 0x20;
    else
        return handle->curOffset >= handle->length ? 1 : 0;
}

int bak_fwrite(void *ptr, int size, int count, IoFile *stream) {
    void *buf;
    FileHandle *handle;
    int written;

    buf = ptr;
    if (g_ioArchiveCount == 0 || (handle = bak_find_handle(stream)) == 0) {
        written = fwrite(buf, size, count, (FILE *)stream);
    } else if (handle->stdioFile != 0) {
        written = fwrite(buf, size, count, handle->stdioFile);
    } else {
        written = 0;
    }
    g_bak_io_error |= (written != count);
    return written;
}

int bak_putc(int c, IoFile *stream) {
    FileHandle *handle;
    int result;

    if (g_ioArchiveCount == 0 || (handle = bak_find_handle(stream)) == 0) {
        result = fputc(c, (FILE *)stream);
    } else {
        if (handle->stdioFile != 0) {
            result = fputc(c, handle->stdioFile);
        } else {
            result = -1;
        }
    }
    g_bak_io_error |= (result == -1) ? 1 : 0;
    return result;
}

void bak_setbuf(IoFile *stream, char *buffer) {
    FileHandle *handle;

    if (g_ioArchiveCount == 0 || (handle = bak_find_handle(stream)) == 0) {
        setbuf((FILE *)stream, buffer);
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

    if (g_bak_initialized != 0)
        return;

    g_int24_old_vector = (void far *)getvect(0x24);

    setvect(0x24, bak_int24_critical_handler);

    g_bak_initialized = 1;

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
    if (g_int24_old_vector != 0) {
        setvect(0x24, (void interrupt(far *) ())g_int24_old_vector);
        g_int24_old_vector = 0;
    }
    g_bak_initialized = 0;
}

void bak_invalidate_archives(void) {
    g_bak_archives_dirty = 1;
}

unsigned long bak_filename_hash(char *filename) {
    unsigned long val;

    val = g_ioHashSeed;
    if (filename == 0)
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

    if ((i = g_bak_current_archive) == 0)
        i = 1;

    entry = g_ioArchives[i].directory;
    while (entry->hash != 0 && entry->hash != hash)
        entry++;

    above = g_bak_current_archive + 1;
    below = g_bak_current_archive - 1;

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
    if (archive_index != g_bak_current_archive || probe_failed || g_bak_archives_dirty) {
        arc = &g_ioArchives[g_bak_current_archive];
        if (arc->fp) {
            fclose(arc->fp);
            arc->fp = 0;
        }
        g_bak_current_archive = archive_index;
        arc = &g_ioArchives[g_bak_current_archive];
        if (archive_index) {
#ifdef V102CD
            strcpy(path, g_cfgResourceDrivePrefix);
            strcat(path, arc->fileName);
            g_bak_in_fopen = 1;
            while ((arc->fp = fopen(path, "rb")) == 0)
                g_bak_in_fopen = 0;
#else
            g_bak_in_fopen = 1;
            while ((arc->fp = fopen(arc->fileName, "rb")) == 0)
                g_bak_in_fopen = 0;
#endif
        }
        arc->filePos = 0;
        bak_find_handle(0);
        g_bak_archives_dirty = 0;
    }
}

void bak_archive_seek(unsigned long absolute_offset) {
    Archive *ar;

    ar = &g_ioArchives[g_bak_current_archive];
    if (ar->filePos != absolute_offset) {
        fseek(ar->fp, absolute_offset, 0);
        ar->filePos = absolute_offset;
    }
}

FileHandle *bak_find_handle(IoFile *stream) {
    FileHandle *slot;
    int count;

    if (stream == 0) {
        g_pBakFindHandleCacheKey = 0;
        g_pBakFindHandleCacheVal = 0;
        return 0;
    }
    if (g_ioArchiveCount == 0)
        return 0;
    if (stream == g_pBakFindHandleCacheKey)
        return g_pBakFindHandleCacheVal;
    g_pBakFindHandleCacheKey = stream;
    slot = g_ioHandles;
    count = IO_HANDLE_POOL_SIZE;
    while (count != 0 && slot != (FileHandle *)stream) {
        slot++;
        count--;
    }
    if (count == 0 || slot->inUse == 0) {
        slot = 0;
        g_pBakFindHandleCacheKey = 0;
    }
    return g_pBakFindHandleCacheVal = slot;
}

void interrupt far bak_int24_critical_handler(unsigned reg_bp, unsigned reg_di, unsigned reg_si,
                                              unsigned reg_ds, unsigned reg_es, unsigned reg_dx,
                                              unsigned reg_cx, unsigned reg_bx, unsigned ax) {
    ax = g_bak_in_fopen ? 3 : 1;
    g_bak_fopen_retry = 1;
    g_bak_archives_dirty = 1;
}
