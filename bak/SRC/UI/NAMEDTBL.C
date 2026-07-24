#include "SRC/GEN/GFXCTX.H"
#include "structs.h"
#include "SRC/UI/NAMEDTBL.H"
#include "SRC/IO/IO.H"
#include "SRC/SYS/MEM.H"
#include "SRC/GFX/FONT/FONT.H"

int *namedtbl_load(char *filename) {
    int *ptr;
    IoFile *stream;
    void *strPool;
    unsigned int poolSize;
    int i;

    strPool = (void *)0;
    ptr = galloc_safe_zcalloc(4);
    stream = bak_fopen(filename, "rb");
    bak_fread(ptr, 2, 1, stream);
    ptr[1] = (int)galloc_safe_zcalloc(*ptr * 10);
    bak_fread((void *)ptr[1], 10, *ptr, stream);
    bak_fread(&poolSize, 2, 1, stream);
    if (poolSize != 0) {
        strPool = galloc_safe_zcalloc(poolSize);
        bak_fread(strPool, 1, poolSize, stream);
    }
    bak_fclose(stream);
    for (i = 0; i < *ptr; i++) {
        if (*(int *)(ptr[1] + i * 10) == -1) {
            *(int *)(ptr[1] + i * 10) = 0;
        } else {
            *(int *)(ptr[1] + i * 10) += (int)strPool;
        }
    }
    return ptr;
}

int namedtbl_free(int *table) {
    void *minPtr;
    int i;

    if (table != (int *)0) {
        minPtr = (void *)*(unsigned short *)table[1];
        for (i = 1; i < *table; i = i + 1) {
            if ((*(int *)(table[1] + i * 10) != 0) &&
                ((minPtr == (void *)0) ||
                 ((void *)*(unsigned int *)(table[1] + i * 10) < minPtr))) {
                minPtr = (void *)*(unsigned short *)(table[1] + i * 10);
            }
        }
        if (minPtr != (void *)0) {
            galloc_zfree(minPtr);
        }
        galloc_zfree((void *)table[1]);
        galloc_zfree(table);
        return 1;
    }
    return 0;
}

void far namedtbl_labels_draw_all(int *table) {
    int i;

    if (table != (int *)0) {
        for (i = 0; i < *table; i++) {
            namedtbl_label_draw((int *)(table[1] + i * 10));
        }
    }
    return;
}

void far namedtbl_label_draw(int *label) {
    int x;

    g_graphics_context.clip.xmin = 0;
    g_graphics_context.clip.ymin = 0;

    g_graphics_context.clip.xmax = 0x13f;
    g_graphics_context.clip.ymax = 199;
    g_graphics_context.bClip_enabled = '\x01';
    g_graphics_context.bText_style_flags = '\x01';
    if (label[3] & 2U) {
        x = 0xa0 - (font_text_width_ds((char *)*label) >> 1);
    } else {
        x = label[1];
    }
    if ((label[3] & 1U) != 0) {
        g_graphics_context.bText_fg_color = *(unsigned char *)((int)label + 9);
        font_draw_text_ds((char *)*label, x, label[2] + 1);
    }
    g_graphics_context.bText_fg_color = (unsigned char)label[4];
    font_draw_text_ds((char *)*label, x, label[2]);
    return;
}
