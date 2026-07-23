#include "structs.h"
#include "SRC/R3D/SCENE/WORLDHIT.H"
#include "SRC/AUDIO/RES/AUDRESIN.H"
#include "SRC/AUDIO/ENGINE/AUDIO.H"
#include "SRC/AUDIO/RES/POOL.H"
#include "SRC/SYS/FARTHUNK.H"
#include "SRC/SYS/DOSMEM.H"
#include "SRC/SYS/FARPTR.H"
#include "SRC/AUDIO/RES/AUDRESLD.H"
#include "SRC/AUDIO/ENGINE/AUDSTOP.H"

/*
 * The pool cursor is a packed seg:off value held as unsigned long, not a
 * far pointer, so that pool_alloc and pool_is_managed_ptr can do full 32-bit
 * add/sub/cmp (every alloc_far block is seg:0000, so the range check must
 * compare segments).
 */
unsigned long g_pool_base = 0;
unsigned long g_pool_top;
unsigned long g_nPoolSize;

unsigned long pool_get_size(void) {
    return g_pool_top - g_pool_base;
}

void pool_compute_size_from_music(void) {
    unsigned long maxUsage;
    unsigned long usage;
    int chunkId;

    maxUsage = 0;
    g_nPoolSize = 0x6000;
    g_pool_base = (unsigned long)alloc_far(g_nPoolSize, 0L);
    g_alloc_to_pool = 1;

    for (chunkId = 0x3e9; chunkId <= 0x426; chunkId++) {
        pool_reset();
        audio_resource_load_chunk(g_pSfxArchiveStream, chunkId);
        usage = pool_get_size();
        if (usage > maxUsage)
            maxUsage = usage;
        audio_stop(chunkId);
    }
    g_alloc_to_pool = 0;
    pool_reset();
    _freemem((unsigned char far *)g_pool_base);
    g_nPoolSize = maxUsage + 0x5ff;
}

void pool_init(void) {
    pool_compute_size_from_music();
    g_pool_base = (unsigned long)alloc_far(g_nPoolSize, 0L);
}

void pool_reset(void) {
    if (g_pool_base == 0)
        pool_init();
    g_pool_top = g_pool_base;
}

void far *pool_alloc(unsigned long size) {
    g_pool_top += size;
    return (void far *)(g_pool_top - size);
}

int pool_is_managed_ptr(unsigned long ptr) {
    return ptr >= g_pool_base && ptr < g_pool_top;
}

void far *pool_acquire_buffer(unsigned long size, int allocTag) {
    void far *result;
    void *nearp;

    if (g_alloc_to_pool != 0)
        result = pool_alloc(size);
    else if (allocTag == 6 || allocTag == 8) {
        nearp = my_malloc((unsigned int)size);
        result = nearp;
    } else
        result = alloc_far(size, 0L);

    if (result != 0)
        if (allocTag == 2 || allocTag == 3 || allocTag == 4 || allocTag == 7)
            memset_far(result, 0, size);

    if (result == 0)
        g_nAudioBufLastError = 1;

    return result;
}
