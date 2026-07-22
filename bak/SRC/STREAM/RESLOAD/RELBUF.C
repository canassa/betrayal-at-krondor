#include "SRC/STREAM/RESLOAD/RELBUF.H"
#include "SRC/SYS/FARTHUNK.H"
#include "SRC/AUDIO/RES/POOL.H"
#include "SRC/SYS/DOSMEM.H"

void release_buffer(void far *ptr, int allocTag) {
    if (pool_is_managed_ptr((unsigned long)ptr) != 0)
        return;
    if (allocTag == 6 || allocTag == 8) {
        my_free((void *)ptr);
        return;
    }
    if (allocTag != 4) {
        _freemem(ptr);
    }
    return;
}
