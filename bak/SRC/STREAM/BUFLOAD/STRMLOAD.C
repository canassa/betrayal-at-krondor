#include "SRC/STREAM/BUFLOAD/STRMLOAD.H"
#include "SRC/SYS/POOL.H"
#include "SRC/STREAM/RESLOAD/RELBUF.H"
#include "SRC/STREAM/CODEC/STREAM.H"

void far *stream_load_to_buffer(BakFile *file, unsigned long size, unsigned long *out_desc,
                                unsigned short codec_kind) {
    register int stream_id;
    unsigned long stream_size_full;
    void far *block_far;

    block_far = (void far *)0;
    if ((stream_id = stream_open(0, file, "r", size)) >= 0) {

        stream_size_full = stream_size(stream_id);

        if ((block_far = pool_acquire_buffer(stream_size_full, codec_kind)) != (void far *)0) {

            if ((unsigned long)stream_read(stream_id, block_far, (unsigned short)stream_size_full) !=
                stream_size_full) {
                release_buffer(block_far, codec_kind);
                block_far = (void far *)0;
            }
        }
        stream_close(stream_id);
    }
    if ((out_desc != (unsigned long *)0) && (block_far != (void far *)0)) {
        *out_desc = stream_size_full;
    }
    return block_far;
}
