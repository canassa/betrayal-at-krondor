#include <alloc.h>
#include <mem.h>
#include "structs.h"
#include "SRC/SYS/MEM.H"
#include "SRC/SYS/FARTHUNK.H"
#include "SRC/SYS/PANIC.H"
#include "SRC/SYS/DOSMEM.H"
#include "SRC/SYS/FARPTR.H"

unsigned char _dgroup_lead_14a[2] = {0x00, 0x00};

char far g_skyHorizonStripsMemHdr[4] = {0x4d, 0x45, 0x4d};

void *galloc_safe_zcalloc(unsigned int size) {
    void *block;

    heapcheck() != -1 || panic_fatal_error_exit(g_skyHorizonStripsMemHdr, 34, "Heap Corrupt!");
    if (size == 0) {
        size++;
    }
    block = my_malloc(size);
    if (block != (void *)0) {
        memset(block, 0, size);
    }
    return block;
}

void galloc_zfree(void *ptr) {
    my_free(ptr);
}

unsigned char far *galloc_calloc_far(unsigned long size, int flags) {
    unsigned char huge *ptr;

    ptr = alloc_far(size, flags);

    if (ptr && size != 0xffffffffUL) {
        memset_far(ptr, 0, size);
    }
    return ptr;
}

void galloc_safe_farfree(void huge *ptr) {
    if (ptr) {
        _freemem(ptr);
    }
}
