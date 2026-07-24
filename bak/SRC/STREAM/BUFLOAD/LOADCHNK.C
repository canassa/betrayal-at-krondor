#include "structs.h"
#include "SRC/STREAM/BUFLOAD/LOADCHNK.H"
#include "SRC/STREAM/RESLOAD/IFFREAD.H"
#include "SRC/STREAM/BUFLOAD/STRMLOAD.H"

void far *bak_load_chunk(FileRef *file, char *chunk_id, int mode) {
    void far *out_buf;
    int opened;
    IoFile *fp;

    opened = 0;
    out_buf = 0;
    if (is_file_cached(file) == 0) {
        opened = 1;
        fp = cached_file_open(file);
    } else {
        fp = file;
    }
    if (fp != 0 && chunk_seek(fp, chunk_id, mode) != -1L) {
        out_buf = stream_load_to_buffer(fp, cached_file_chunk_size(fp), (unsigned long *)0, 1);
    }
    if (opened) {
        cached_file_close(fp);
    }
    return out_buf;
}
