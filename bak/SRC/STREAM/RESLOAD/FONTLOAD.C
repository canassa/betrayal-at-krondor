#define FP_OFF(fp) (*(unsigned *)&(fp))
#include "globals.h"
#include "structs.h"
#include "SRC/STREAM/RESLOAD/FONTLOAD.H"
#include "SRC/IO/IO.H"
#include "SRC/SYS/FARTHUNK.H"
#include "SRC/GFX/FONT/FONT.H"
#include "SRC/SYS/DOSMEM.H"
#include "SRC/STREAM/RESLOAD/IFFREAD.H"
#include "SRC/STREAM/CODEC/STREAM.H"

unsigned short g_font_chunk_tag_ptr = (unsigned short)"FNT:";

int font_load(BakFileRef *filename) {
    int openedCache;
    int dataSize;
    int stream_id;
    int error_flag;
    void far *buf;
    void *malloc_result;
    int slot;

    for (slot = 2; *(long *)&g_font_bitmap_data[slot] && slot < 0x14; slot++)
        ;
    if (slot >= 0x14)
        goto full;

    if (is_file_cached(filename) == 0) {
        openedCache = 1;
        filename = cached_file_open(filename);
    } else {
        openedCache = 0;
    }

    if (chunk_seek(filename, (char *)g_font_chunk_tag_ptr, 0) == -1L)
        goto fail;

    bak_fread(&g_graphics_context.pFont_glyph_width_bits[slot], 1, 1, filename);

    if ((char)g_graphics_context.pFont_glyph_width_bits[slot] == -3 ||
        (char)g_graphics_context.pFont_glyph_width_bits[slot] == -1) {

        g_font_format[slot] = -(char)g_graphics_context.pFont_glyph_width_bits[slot];
        bak_fread(&g_graphics_context.pFont_glyph_width_bits[slot], 1, 1, filename);
        bak_fread(&g_graphics_context.pFont_height[slot], 1, 1, filename);
        bak_fread(&g_font_underline_offset[slot], 1, 1, filename);
        bak_fread(&g_graphics_context.pFont_base_char[slot], 1, 1, filename);
        bak_fread(&g_graphics_context.pFont_glyph_count[slot], 1, 1, filename);
        bak_fread(&dataSize, 1, 2, filename);

        error_flag =
            ((stream_id = stream_open(-1, filename, "r", cached_file_chunk_size(filename))) < 0);

        if (error_flag == 0) {
            error_flag = ((uint)stream_size(stream_id) != (uint)dataSize);
        }

        if (error_flag == 0) {
            error_flag = ((buf = alloc_far((ulong)(uint)dataSize, 0L)) == 0);
        }

        if (error_flag == 0) {
            error_flag = (stream_read(stream_id, buf, dataSize) != (uint)dataSize);
        }

        if (error_flag == 0) {
            g_font_glyph_offset_table[slot] = (int far *)buf;
            FP_OFF(buf) += (uint)g_graphics_context.pFont_glyph_count[slot] * 2;
            g_font_width_table[slot] = (uchar far *)buf;
            FP_OFF(buf) += (uint)g_graphics_context.pFont_glyph_count[slot];
            g_font_bitmap_data[slot] = (uchar far *)buf;
        }

        stream_close(stream_id);
        if (error_flag == 0)
            goto epilogue;
        asm mov ax, word ptr buf;
        asm or ax, word ptr buf + 2;
        asm jz comp_stub;
        _freemem(buf);
        goto comp_fail;
    comp_stub:;
    } else {

        if ((char)g_graphics_context.pFont_glyph_width_bits[slot] == -2) {
            g_font_format[slot] = 2;
            bak_fread(&g_graphics_context.pFont_glyph_width_bits[slot], 1, 1, filename);
            dataSize = (uint)g_graphics_context.pFont_glyph_width_bits[slot];
        } else {
            g_font_format[slot] = 0;
            dataSize = ((int)g_graphics_context.pFont_glyph_width_bits[slot] + 7) >> 3;
        }
        bak_fread(&g_graphics_context.pFont_height[slot], 1, 1, filename);
        bak_fread(&g_graphics_context.pFont_base_char[slot], 1, 1, filename);
        bak_fread(&g_graphics_context.pFont_glyph_count[slot], 1, 1, filename);

        dataSize *= (int)(uchar)g_graphics_context.pFont_height[slot] *
                    (int)(uchar)g_graphics_context.pFont_glyph_count[slot];

        error_flag = !((malloc_result = my_malloc(dataSize)));

        if (error_flag == 0) {
            bak_fread(malloc_result, dataSize, 1, filename);
        }

        if (error_flag == 0) {
            g_font_bitmap_data[slot] = (uchar far *)malloc_result;
            *(long *)&g_font_glyph_offset_table[slot] = 0L;
            *(long *)&g_font_width_table[slot] = 0L;
        }
        if (error_flag == 0) {
            goto epilogue;
        }
        if (malloc_result != 0) {
            my_free(malloc_result);
            goto uncomp_fail;
        }
    uncomp_stub:
        asm db 0xeb, 0x00;
    }
comp_fail:
uncomp_fail:
fail:
    slot = 0;
epilogue:
    if (openedCache != 0) {
        cached_file_close(filename);
    }
    goto done;
full:
    slot = 0;
done:
    return slot;
}

void font_unload(register int slot) {
    if (font_slot_in_use(slot)) {
        if (((void far *far *)g_font_bitmap_data)[slot] ==
            ((void far *far *)g_font_bitmap_data)[0]) {
            g_font_format[0] = 0;
            g_graphics_context.pFont_base_char[0] = g_graphics_context.pFont_glyph_count[0] = 0;
            g_graphics_context.pFont_glyph_width_bits[0] = g_graphics_context.pFont_height[0] =
                g_font_underline_offset[0] = 0;
            *(long *)&g_font_glyph_offset_table[0] = 0L;
            *(long *)&g_font_width_table[0] = 0L;
            *(long *)&g_font_bitmap_data[0] = 0L;
        }

        if (*(unsigned long *)&g_font_glyph_offset_table[slot]) {
            _freemem(((uchar far *far *)g_font_glyph_offset_table)[slot]);
        } else {
            my_free((void *)FP_OFF(g_font_bitmap_data[slot]));
        }

        g_font_format[slot] = 0;
        *(long *)&g_font_bitmap_data[slot] = 0L;
        *(long *)&g_font_glyph_offset_table[slot] = 0L;
        *(long *)&g_font_width_table[slot] = 0L;
    }
}
