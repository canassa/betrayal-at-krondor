#include <stdio.h>
#include <stdlib.h>
#include "structs.h"
#include "globals.h"
#include "SRC/GEN/GFXCTX.H"
#include "SRC/GFX/RASTER/ILBMSAVE.H"
#include "SRC/GFX/RASTER/ILBMPACK.H"
#include "SRC/GFX/DRIVER/PALDAC.H"
#include "SRC/GFX/RASTER/PIXEL.H"

static char s_iff_form[] = "FORM";
static char s_iff_ilbm[] = "ILBM";
static char s_iff_bmhd[] = "BMHD";

static void far ilbmsave_iff_fwrite_be(void *data, int count, int elem_size, FILE *stream) {
    register void *p = data;
    register FILE *fp = stream;
    while (count--) {
        if (elem_size == 4) {
            ilbmsave_iff_fwrite_be((char *)p + 2, 1, 2, fp);
            ilbmsave_iff_fwrite_be(p, 1, 2, fp);
        } else {
            if (elem_size == 2) {
                fwrite((char *)p + 1, 1, 1, fp);
            } else if (elem_size != 1)
                goto skip_write;
            fwrite(p, 1, 1, fp);
        }
    skip_write:
        p = (char *)p + elem_size;
    }
}

static void ilbmsave_write_cmap_chunk(FILE *stream) {
    int i;
    unsigned char palette[768];
    long sizeBe;

    fwrite("CMAP", 1, 4, stream);
    vga_read_palette(palette, 0, 0x100);
    sizeBe = 0x300;
    ilbmsave_iff_fwrite_be(&sizeBe, 1, 4, stream);
    i = 0;
    do {
        palette[i] <<= 2;
        i = i + 1;
    } while (i < 0x300);
    fwrite(palette, 0x300, 1, stream);
    return;
}

static void far ilbmsave_write_body_chunk(FILE *stream) {
    register unsigned int *src;
    register int x;
    int y;
    unsigned char *p;
    long size_be;

    fwrite("BODY", 4, 1, stream);
    size_be = 64000;
    ilbmsave_iff_fwrite_be(&size_be, 1, 4, stream);

    src = malloc(0x280);
    y = 0;
    do {
        p = (unsigned char *)src;
        x = 0;
        do {
            *p++ = (unsigned char)getpixel(x, y);
            x++;
        } while (x < 0x140);
        ilbm_pack_row_to_planes(src, (unsigned char *)(src + 0xa0));
        fwrite(src + 0xa0, 0x140, 1, stream);
        y++;
    } while (y < 200);
    free(src);
}

static void far ilbmsave_screen_save(char *filename) {
    register FILE *fp;
    unsigned long dwordBe;
    unsigned short wordBe;

    if ((fp = fopen(filename, "wb")) != 0) {
        fwrite(s_iff_form, 4, 1, fp);
        dwordBe = 0xfd30;
        ilbmsave_iff_fwrite_be(&dwordBe, 1, 4, fp);
        fwrite(s_iff_ilbm, 4, 1, fp);
        fwrite(s_iff_bmhd, 4, 1, fp);
        dwordBe = 0x14;
        ilbmsave_iff_fwrite_be(&dwordBe, 1, 4, fp);
        wordBe = 0x140;
        ilbmsave_iff_fwrite_be(&wordBe, 1, 2, fp);
        wordBe = 200;
        ilbmsave_iff_fwrite_be(&wordBe, 1, 2, fp);
        dwordBe = 0;
        ilbmsave_iff_fwrite_be(&dwordBe, 1, 4, fp);
        dwordBe = 0x8000000;
        ilbmsave_iff_fwrite_be(&dwordBe, 1, 4, fp);
        dwordBe = 0x101;
        ilbmsave_iff_fwrite_be(&dwordBe, 1, 4, fp);
        wordBe = 0x140;
        ilbmsave_iff_fwrite_be(&wordBe, 1, 2, fp);
        wordBe = 200;
        ilbmsave_iff_fwrite_be(&wordBe, 1, 2, fp);
        ilbmsave_write_cmap_chunk(fp);
        ilbmsave_write_body_chunk(fp);
        fclose(fp);
    }
}

void far ilbmsave_draw_unclipped_alt_buf(char *filename) {
    unsigned short saved_dst_page;
    int saved_clip_enabled;

    saved_dst_page = g_graphics_context.wGfxBlitDstPage;
    saved_clip_enabled = (char)g_graphics_context.bClip_enabled;
    g_graphics_context.bClip_enabled = '\0';
    g_graphics_context.wGfxBlitDstPage = g_graphics_context.wGfxBlitSrcPage;
    ilbmsave_screen_save(filename);
    g_graphics_context.bClip_enabled = saved_clip_enabled;
    g_graphics_context.wGfxBlitDstPage = saved_dst_page;
}
