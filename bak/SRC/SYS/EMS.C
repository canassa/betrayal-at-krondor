#include <dos.h>
#include "structs.h"
#include "SRC/SYS/EMS.H"
#include "SRC/SYS/FARTHUNK.H"
#include "SRC/SYS/EMSDET.H"
#include "SRC/GAME/BOOT.H"

unsigned short g_free_memory_kb;
unsigned short g_wEmsFreeListHead;
int *g_pEmsPageNextTbl;
int g_anEmsPageMap[8];

int g_ems_present = 0;
unsigned short g_ems_total_pages = 0x0000;
unsigned short g_ems_free_pages = 0x0000;
unsigned short g_ems_frame_segment = 0x0000;
char s_ems_driver_signature[8] = "EMMXXXX0";

int ems_init(void) {
    int *p;
    int i;

    if (ems_detect_driver() != 0) {
        g_pEmsPageNextTbl = my_malloc(g_ems_total_pages << 1);
        if (g_pEmsPageNextTbl == 0)
            boot_engine_exit(0);

        p = g_pEmsPageNextTbl;
        for (i = 0; i < g_ems_total_pages; i++)
            *p++ = i + 1;
        *(p - 1) = -1;

        g_wEmsFreeListHead = 0;
        g_free_memory_kb = g_ems_total_pages;
        return 1;
    }
    return 0;
}

unsigned short ems_get_free_memory(void) {
    return g_free_memory_kb;
}

void ems_shutdown(void) {
    if (g_ems_present) {
        if (g_pEmsPageNextTbl != 0)
            my_free(g_pEmsPageNextTbl);
        asm {
            push si
            push di
            mov dx, g_ems_frame_segment
            mov ah, 45h
            int 67h
        }
        g_ems_present = 0;
        asm {
            pop di
            pop si
        }
    }
}

int ems_alloc_pages(unsigned long size_bytes) {
    int pages;
    int idx;
    int first;

    if (g_ems_present == 0 || size_bytes == 0)
        return 0;

    pages = (int)((long)size_bytes >> 14);
    if (size_bytes & 0x3fff)
        pages++;
    if (pages <= 0 || pages > (int)g_free_memory_kb)
        return 0;

    first = g_wEmsFreeListHead + 1;
    g_free_memory_kb -= pages;

    idx = g_wEmsFreeListHead;
    while (--pages)
        idx = g_pEmsPageNextTbl[idx];

    g_wEmsFreeListHead = g_pEmsPageNextTbl[idx];
    g_pEmsPageNextTbl[idx] = -1;
    return first;
}

void ems_free_pages(int page_chain_1based) {
    int count;
    int cur;

    if (g_ems_present == 0 || page_chain_1based == 0)
        return;

    cur = page_chain_1based - 1;
    count = 1;
    while (g_pEmsPageNextTbl[cur] != -1) {
        cur = g_pEmsPageNextTbl[cur];
        count++;
    }

    g_pEmsPageNextTbl[cur] = g_wEmsFreeListHead;
    g_wEmsFreeListHead = page_chain_1based - 1;
    g_free_memory_kb += count;
}

unsigned char far *ems_map_at_offset(int page_chain_1based, long offset) {
    int page_idx;
    unsigned int within;
    int chain_node;
    int phys_slot;
    int *mapEntry;

    page_idx = (int)(offset >> 14);
    within = (unsigned int)offset & 0x3fff;

    if (g_ems_present == 0 || page_chain_1based == 0)
        return (unsigned char far *)MK_FP(0, 0);

    chain_node = page_chain_1based - 1;
    while (page_idx > 0 && chain_node != -1) {
        chain_node = g_pEmsPageNextTbl[chain_node];
        page_idx--;
    }

    phys_slot = 0;
    mapEntry = g_anEmsPageMap;
    while (phys_slot < 4 && chain_node != -1) {
        *mapEntry++ = chain_node;
        *mapEntry = phys_slot;
        phys_slot++;
        mapEntry++;
        chain_node = g_pEmsPageNextTbl[chain_node];
    }

    asm {
        mov si, offset g_anEmsPageMap
        mov dx, g_ems_frame_segment
        mov cx, phys_slot
        mov ax, 5000h
        int 67h
    }
    return (unsigned char far *)MK_FP(g_ems_free_pages, within);
}

unsigned char far *ems_map_resource_pages(int page_id) {
    int cur;
    int count;
    int *mapEntry;

    if (g_ems_present == 0 || page_id == 0)
        return (unsigned char far *)MK_FP(0, 0);

    cur = page_id - 1;
    count = 0;
    mapEntry = g_anEmsPageMap;
    while (count < 4 && cur != -1) {
        *mapEntry++ = cur;
        *mapEntry = count;
        count++;
        mapEntry++;
        cur = g_pEmsPageNextTbl[cur];
    }

    asm {
        mov si, offset g_anEmsPageMap
        mov dx, g_ems_frame_segment
        mov cx, count
        mov ax, 5000h
        int 67h
    }
    return (unsigned char far *)MK_FP(g_ems_free_pages, 0);
}
