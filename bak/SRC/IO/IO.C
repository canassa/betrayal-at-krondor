#include <ctype.h>
#include <dos.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "globals.h"
#include "structs.h"
#include "SRC/IO/IO.H"
#include "SRC/SYS/DOSMEM.H"

short g_bak_io_error;
void far *g_int24_old_vector;
BakHandle g_bak_handles[10];
BakArchive g_bak_archives[11];
BakFile *g_pBakFgetcLastStream;
FILE *g_pBakActiveFgetcStream;
unsigned char g_bak_in_fopen;
unsigned char g_bak_fopen_retry;
unsigned char g_bak_archives_dirty;
unsigned char g_bak_open_handles;
unsigned long g_bak_lookup_hash;
short g_bak_current_archive;
short g_bak_archive_count;
short g_bak_hash_seed;
unsigned short g_bak_hash_rotate;
BakHandle *g_pBakFindHandleCacheVal;
BakFile *g_pBakFindHandleCacheKey;

unsigned char g_bak_initialized = 0x00;

BakFile *bak_fopen(char *filename, char *mode) {
    char name[14];
    int count;
    register BakHandle *slot;
    register FILE *fp;

    if (g_bak_archives_dirty) {
        bak_select_archive(0);
    }
    bak_init_resources();
    g_bak_io_error = 0;
    if (g_bak_archive_count == 0) {
        return (BakFile *)fopen(filename, mode);
    }
    g_pBakActiveFgetcStream = 0;
    g_pBakFgetcLastStream = 0;
    slot = g_bak_handles;
    count = 10;
    while (count != 0 && slot->valid != 0) {
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
        slot->archive_idx = 0;
        slot->base_offset = slot->length = slot->cur_offset = 0UL;
        slot->valid = 1;
        slot->real_fp = fp;
    } else {
        if (!bak_resource_lookup(slot)) {
            return 0;
        }
        bak_select_archive(slot->archive_idx);
        bak_archive_seek(slot->base_offset + slot->cur_offset);
        fp = g_bak_archives[g_bak_current_archive].fp;
        fread(name, 0xd, 1, fp);
        fread(&slot->length, 4, 1, fp);
        g_bak_archives[g_bak_current_archive].pos = slot->base_offset = ftell(fp);
        if (stricmp(name, filename) != 0) {
            return 0;
        }
        slot->cur_offset = 0;
        slot->real_fp = 0;
        slot->valid = 1;
    }
    g_bak_open_handles++;
    return (BakFile *)slot;
}

int bak_fclose(BakFile *stream) {
    int result;
    BakHandle *handle;

    result = 0;
    if (stream == 0)
        return -1;
    if ((g_bak_archive_count == 0) || (handle = bak_find_handle(stream)) == 0) {
        result = fclose((FILE *)stream);
    } else {
        bak_find_handle(0);
        if (handle->real_fp != 0)
            result = fclose(handle->real_fp);
        handle->valid = 0;
        g_bak_open_handles--;
    }
    g_bak_io_error |= (result == -1 ? 1 : 0);
    return result;
}

int bak_fread(void *ptr, int size, int count, BakFile *stream) {
    int n_read;
    int single_obj;
    unsigned nbytes;
    BakHandle *handle;

    single_obj = 0;
    if (g_bak_archive_count == 0 || (handle = bak_find_handle(stream)) == 0) {
        return fread(ptr, size, count, (FILE *)stream);
    }
    if (handle->real_fp != 0) {
        return fread(ptr, size, count, handle->real_fp);
    }
    if (count == 1) {
        count = size;
        size = 1;
        single_obj = 1;
    }
    nbytes = size * count;
    while (nbytes != 0 && nbytes > handle->length - handle->cur_offset) {
        count--;
        nbytes -= size;
    }
    bak_select_archive(handle->archive_idx);
    bak_archive_seek(handle->base_offset + handle->cur_offset);
    stream = (BakFile *)g_bak_archives[handle->archive_idx].fp;
    n_read = fread(ptr, size, count, (FILE *)stream);
    nbytes = n_read * size;
    handle->cur_offset += nbytes;
    g_bak_archives[handle->archive_idx].pos += nbytes;
    if (single_obj != 0 && n_read == count) {
        n_read = 1;
    }
    return n_read;
}

int bak_fseek(BakFile *stream, long offset, int whence) {
    BakHandle *handle;

    if (g_bak_archive_count == 0 || (handle = bak_find_handle(stream)) == 0)
        return fseek((FILE *)stream, offset, whence);
    if (handle->real_fp != 0)
        return fseek(handle->real_fp, offset, whence);
    if (whence == 1) {
        offset += handle->cur_offset;
    } else if (whence == 2) {
        if ((unsigned long)offset >= handle->length)
            offset = 0;
        else
            offset = handle->length - offset;
    }
    if ((unsigned long)offset > handle->length)
        offset = handle->length;
    handle->cur_offset = offset;
    return 0;
}

long bak_ftell(BakFile *stream) {
    BakHandle *handle;

    if (g_bak_archive_count == 0 || (handle = bak_find_handle(stream)) == 0)
        return ftell((FILE *)stream);
    if (handle->real_fp != 0)
        return ftell(handle->real_fp);
    else
        return handle->cur_offset;
}

long bak_filelength(BakFile *stream) {
    long saved_pos;
    long result;
    BakHandle *handle;

    if (g_bak_archive_count == 0 || (handle = bak_find_handle(stream)) == 0 ||
        (stream = (BakFile *)handle->real_fp) != 0) {
        saved_pos = ftell((FILE *)stream);
        fseek((FILE *)stream, 0L, 2);
        result = ftell((FILE *)stream);
        fseek((FILE *)stream, saved_pos, 0);
    } else {
        result = handle->length;
    }
    return result;
}

void bak_rewind(BakFile *stream) {
    bak_fseek(stream, 0L, 0);
}

int bak_fgetc(BakFile *stream) {
    int result;
    BakHandle *handle;

    g_pBakFgetcLastStream = stream;
    if (g_bak_archive_count == 0 || (handle = bak_find_handle(stream)) == 0)
        return fgetc(g_pBakActiveFgetcStream = (FILE *)stream);
    if (handle->real_fp != 0)
        return fgetc(g_pBakActiveFgetcStream = handle->real_fp);
    if (handle->cur_offset >= handle->length)
        return -1;
    bak_select_archive(handle->archive_idx);
    bak_archive_seek(handle->base_offset + handle->cur_offset);
    stream = (BakFile *)g_bak_archives[handle->archive_idx].fp;
    result = fgetc(g_pBakActiveFgetcStream = (FILE *)stream);
    handle->cur_offset++;
    g_bak_archives[handle->archive_idx].pos++;
    return result;
}

int bak_feof(BakFile *stream) {
    BakHandle *handle;

    if (g_bak_archive_count == 0 || (handle = bak_find_handle(stream)) == 0)
        return ((FILE *)stream)->flags & 0x20;
    if (handle->real_fp != 0)
        return handle->real_fp->flags & 0x20;
    else
        return handle->cur_offset >= handle->length ? 1 : 0;
}

int bak_fwrite(void *ptr, int size, int count, BakFile *stream) {
    void *buf;
    BakHandle *handle;
    int written;

    buf = ptr;
    if (g_bak_archive_count == 0 || (handle = bak_find_handle(stream)) == 0) {
        written = fwrite(buf, size, count, (FILE *)stream);
    } else if (handle->real_fp != 0) {
        written = fwrite(buf, size, count, handle->real_fp);
    } else {
        written = 0;
    }
    g_bak_io_error |= (written != count);
    return written;
}

int bak_putc(int c, BakFile *stream) {
    BakHandle *handle;
    int result;

    if (g_bak_archive_count == 0 || (handle = bak_find_handle(stream)) == 0) {
        result = fputc(c, (FILE *)stream);
    } else {
        if (handle->real_fp != 0) {
            result = fputc(c, handle->real_fp);
        } else {
            result = -1;
        }
    }
    g_bak_io_error |= (result == -1) ? 1 : 0;
    return result;
}

void bak_setbuf(BakFile *stream, char *buffer) {
    BakHandle *handle;

    if (g_bak_archive_count == 0 || (handle = bak_find_handle(stream)) == 0) {
        setbuf((FILE *)stream, buffer);
    } else {
        if (handle->real_fp != 0)
            setbuf(handle->real_fp, buffer);
    }
}

void bak_init_resources(void) {
    BakIndexEntry far *entry;
    short archive_idx;
    short read_count;
    ulong hashVal;
    ulong offsetVal;
    char *filename_ptr;
    register FILE *fp;
    register BakArchive *arc;

    if (g_bak_initialized != 0)
        return;

    g_int24_old_vector = (void far *)getvect(0x24);

    setvect(0x24, bak_int24_critical_handler);

    g_bak_initialized = 1;

    filename_ptr = "krondor.rmf";
    if ((fp = fopen(filename_ptr, "rb")) == 0)
        return;

    fread(&read_count, 2, 1, fp);
    fread(&g_bak_hash_seed, 2, 1, fp);
    fread(&g_bak_hash_rotate, 2, 1, fp);

    g_bak_archive_count += read_count;
    archive_idx = g_bak_archive_count - read_count + 1;

    while (archive_idx <= g_bak_archive_count) {
        arc = &g_bak_archives[archive_idx];

        fread(arc, 13, 1, fp);
        fread(&read_count, 2, 1, fp);

        entry = alloc_far((ulong)((ushort)(read_count + 1) * 8), ALLOC_FAR_ZERO_FILL);
        arc->index = entry;
        arc->ordinal = archive_idx;

        while (read_count--) {
            fread(&hashVal, 4, 1, fp);
            fread(&offsetVal, 4, 1, fp);
            entry->dwHash = hashVal;
            entry->dwBase_offset = offsetVal;
            entry++;
        }

        archive_idx++;
    }

    fclose(fp);
}

void bak_shutdown_resources(void) {
    int i;

    i = 0;
    while (i <= 10) {
        if (g_bak_archives[i].index != 0) {
            _freemem(g_bak_archives[i].index);
            g_bak_archives[i].index = 0;
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

ulong bak_filename_hash(char *filename) {
    unsigned long val;

    val = g_bak_hash_seed;
    if (filename == 0)
        return g_bak_lookup_hash = 0;
    while ((*filename = toupper(*filename)) != 0) {
        val += *filename;
        filename++;
        val = _lrotl(val, g_bak_hash_rotate);
    }
    return g_bak_lookup_hash = val;
}

int bak_resource_lookup(BakHandle *slot) {
    BakIndexEntry far *entry;
    ulong hash;
    int above;
    int below;
    int i;

    hash = g_bak_lookup_hash;

    if ((i = g_bak_current_archive) == 0)
        i = 1;

    entry = g_bak_archives[i].index;
    while (entry->dwHash != 0 && entry->dwHash != hash)
        entry++;

    above = g_bak_current_archive + 1;
    below = g_bak_current_archive - 1;

    while (entry->dwHash != hash && (below > 0 || above <= g_bak_archive_count)) {
        if (above <= g_bak_archive_count) {
            i = above;
            above++;
            entry = g_bak_archives[i].index;
            while (entry->dwHash != 0 && entry->dwHash != hash)
                entry++;
        }

        if (entry->dwHash != hash) {
            if (below > 0) {
                i = below;
                below--;
                entry = g_bak_archives[i].index;
                while (entry->dwHash != 0 && entry->dwHash != hash)
                    entry++;
            }
        }
    }

    if (entry->dwHash == hash) {
        slot->archive_idx = i;
        slot->base_offset = entry->dwBase_offset;
        slot->length = slot->cur_offset = 0;
        return 1;
    } else {
        return 0;
    }
}

void bak_select_archive(int archive_index) {
    int probe_failed;
    BakArchive *arc;

    probe_failed = 0;
    if (!(char)g_bak_open_handles && archive_index) {
        if (fclose(fopen(g_bak_archives[archive_index].name, "rb")))
            probe_failed = 1;
    }
    if (archive_index != g_bak_current_archive || probe_failed || g_bak_archives_dirty) {
        arc = &g_bak_archives[g_bak_current_archive];
        if (arc->fp) {
            fclose(arc->fp);
            arc->fp = 0;
        }
        g_bak_current_archive = archive_index;
        arc = &g_bak_archives[g_bak_current_archive];
        if (archive_index) {
            g_bak_in_fopen = 1;
            while ((arc->fp = fopen(arc->name, "rb")) == 0)
                g_bak_in_fopen = 0;
        }
        arc->pos = 0;
        bak_find_handle(0);
        g_bak_archives_dirty = 0;
    }
}

void bak_archive_seek(ulong absolute_offset) {
    BakArchive *ar;

    ar = &g_bak_archives[g_bak_current_archive];
    if (ar->pos != absolute_offset) {
        fseek(ar->fp, absolute_offset, 0);
        ar->pos = absolute_offset;
    }
}

BakHandle *bak_find_handle(BakFile *stream) {
    BakHandle *slot;
    int count;

    if (stream == 0) {
        g_pBakFindHandleCacheKey = 0;
        g_pBakFindHandleCacheVal = 0;
        return 0;
    }
    if (g_bak_archive_count == 0)
        return 0;
    if (stream == g_pBakFindHandleCacheKey)
        return g_pBakFindHandleCacheVal;
    g_pBakFindHandleCacheKey = stream;
    slot = g_bak_handles;
    count = 10;
    while (count != 0 && slot != (BakHandle *)stream) {
        slot++;
        count--;
    }
    if (count == 0 || slot->valid == 0) {
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
