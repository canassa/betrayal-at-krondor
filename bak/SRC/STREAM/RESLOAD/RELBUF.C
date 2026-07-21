#include "SRC/STREAM/RESLOAD/RELBUF.H"
#include "SRC/SYS/FARTHUNK.H"
#include "SRC/SYS/POOL.H"
#include "SRC/SYS/DOSMEM.H"

void release_buffer(void far *ptr, int kind) {
    if (pool_is_managed_ptr((ulong)ptr) != 0)
        return;
    if (kind == 6 || kind == 8) {
        my_free((void *)ptr);
        return;
    }
    if (kind != 4) {
        _freemem(ptr);
    }
    return;
}
