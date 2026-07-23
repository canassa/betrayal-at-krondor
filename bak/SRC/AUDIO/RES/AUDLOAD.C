#include "structs.h"
#include "SRC/AUDIO/RES/AUDRESIN.H"
#include "SRC/AUDIO/RES/AUDLOAD.H"
#include "SRC/IO/IO.H"
#include "SRC/IO/IOCHUNK.H"
#include "SRC/AUDIO/RES/POOL.H"
#include "SRC/STREAM/RESLOAD/RELBUF.H"
#include "SRC/AUDIO/RES/AUDRES.H"
#include "SRC/STREAM/BUFLOAD/STRMLOAD.H"

int music_chunk_load_and_link(BakFile *file, char mode) {
    long size;
    unsigned short out_size[2];
    AudioListNode far *node;
    unsigned short scratch;
    int allocTag;

    bak_fread(&size, 4, 1, file);
    bak_fread(&scratch, 2, 1, file);

    if ((node = pool_acquire_buffer(sizeof(AudioListNode), 3)) == 0)
        return 0;

    node->wId = scratch;
    bak_fread(&scratch, 1, 1, file);
    *(unsigned short far *)&node->bPriority = (unsigned char)scratch;
    bak_fread(&scratch, 1, 1, file);
    node->wFlags = (unsigned char)scratch;

    allocTag = (node->wFlags & 1) ? 4 : 7;

    size = size - 4;
    node->pData = 0;

    if (mode == 'c') {
        if ((node->pData = pool_acquire_buffer(size, allocTag)) == 0 ||
            bak_fread_chunked(node->pData, size, 1, file) != 1) {
            release_buffer(node, 3);
            return 0;
        }
    } else if (g_nAudioStreamCodec != 0) {
        if ((node->pData = audres_load_chunk_by_mode(file, (unsigned)size,
                                                     (unsigned)((unsigned long)size >> 16),
                                                     (unsigned *)out_size, allocTag)) == 0) {
            release_buffer(node, 3);
            return 0;
        }
    } else {
        if ((node->pData =
                 stream_load_to_buffer(file, size, (unsigned long *)out_size, allocTag)) == 0) {
            release_buffer(node, 3);
            return 0;
        }
    }

    node->pNext = g_pActiveAudioListHead;
    node->wSortKey = out_size[0];
    g_pActiveAudioListHead = node;
    return 1;
}
