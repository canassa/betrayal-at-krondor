#include <dos.h>

#include "SRC/GEN/GFXCTX.H"
#include "SRC/DIALOG/DIALOG.H"
#include "structs.h"
#include "SRC/GEN/RNDVTBL.H"
#include "SRC/GFX/FONT/FONT.H"
#include "SRC/GFX/RASTER/DRAWLINE.H"
#include "SRC/GFX/RASTER/PIXEL.H"

unsigned char g_font_underline_offset[20];
int far *g_font_glyph_offset_table[20];
unsigned char far *g_font_width_table[20];
unsigned char far *g_font_bitmap_data[20];
unsigned char g_font_format[20];

unsigned char g_abFontColorRemap[5] = {0x00, 0x01, 0x02, 0x03, 0x04};
unsigned char g_saved_text_fg_color = 0xff;

int far font_activate(int slot) {
    unsigned long ref;
    unsigned char far **p;
    int i;

    i = 0;
    if (slot == 0) {
        if ((ref = *(unsigned long *)&g_font_bitmap_data[0]) != 0) {
            for (i = 1, p = &g_font_bitmap_data[i]; i < 20; i++, p++) {
                if (*(unsigned long *)p == ref)
                    break;
            }
        } else {
            i = 0;
        }
    } else {
        if (font_slot_in_use(slot) != 0) {
            i = slot;
            g_font_format[0] = g_font_format[slot];
            g_graphics_context.pFont_glyph_width_bits[0] =
                g_graphics_context.pFont_glyph_width_bits[slot];
            g_graphics_context.pFont_height[0] = g_graphics_context.pFont_height[slot];
            g_font_underline_offset[0] = g_font_underline_offset[slot];
            g_graphics_context.pFont_base_char[0] = g_graphics_context.pFont_base_char[slot];
            g_graphics_context.pFont_glyph_count[0] = g_graphics_context.pFont_glyph_count[slot];
            g_font_bitmap_data[0] = g_font_bitmap_data[slot];
            g_font_glyph_offset_table[0] = g_font_glyph_offset_table[slot];
            g_font_width_table[0] = g_font_width_table[slot];
        }
    }
    return i;
}

int font_get_line_height(int slot) {
    unsigned char widthBits;

    if (font_slot_in_use(slot) != 0 || slot == 0)
        widthBits = g_graphics_context.pFont_glyph_width_bits[slot];
    else
        widthBits = 0;
    return (unsigned int)widthBits;
}

int font_height_get(int slot) {
    unsigned char height;

    if (font_slot_in_use(slot) != 0 || slot == 0)
        height = g_graphics_context.pFont_height[slot];
    else
        height = 0;
    return (unsigned int)height;
}

int font_slot_in_use(int slot) {

    return (slot > 0 && slot < 0x14 && g_font_bitmap_data[slot] != 0) ? 1 : 0;
}

int font_text_width_ds(char *text) {
    return font_text_pixel_width((unsigned char far *)text);
}

int font_text_pixel_width(char far *str) {
    int total;
    int has_width_table;
    int idx;
    total = 0;
    has_width_table = (*(unsigned long *)&g_font_glyph_offset_table[0] != 0);
    while (*str != '\0') {
        idx = (unsigned char)*str - g_graphics_context.pFont_base_char[0];
        str++;
        if (idx >= 0 && idx < g_graphics_context.pFont_glyph_count[0]) {
            total += has_width_table ? g_font_width_table[0][idx]
                                     : g_graphics_context.pFont_glyph_width_bits[0];
        }
    }
    return total;
}

unsigned int font_draw_char(unsigned char ch, int x, int y) {
    unsigned char far *glyph_ptr;
    unsigned char saved_fg;
    unsigned char pix;
    unsigned int col;
    unsigned int row;
    int pixel_x;
    unsigned char bit_mask;
    char is_packed;
    unsigned int width;
    unsigned int height;
    PutpixelFn putpixel_fp;
    register int i;
    int styleFlags;

    saved_fg = g_graphics_context.bText_fg_color;
    i = ch - g_graphics_context.pFont_base_char[0];
    if (i < 0 || g_graphics_context.pFont_glyph_count[0] <= i)
        return 0;

    if (g_font_format[0] & 1) {
        width = g_font_width_table[0][i];
        height = g_graphics_context.pFont_height[0];
        glyph_ptr = g_font_bitmap_data[0] + g_font_glyph_offset_table[0][i];
    } else if (g_font_format[0] == 2) {
        width = g_graphics_context.pFont_glyph_width_bits[0];
        height = g_graphics_context.pFont_height[0];
        glyph_ptr = g_font_bitmap_data[0] + i * width * height;
    } else {
        width = g_graphics_context.pFont_glyph_width_bits[0];
        height = g_graphics_context.pFont_height[0];
        glyph_ptr = g_font_bitmap_data[0] + i * ((width + 7) >> 3) * height;
    }

    if (x < g_graphics_context.clip.xmin || y < g_graphics_context.clip.ymin ||
        (unsigned int)g_graphics_context.clip.xmax < x + width ||
        (unsigned int)g_graphics_context.clip.ymax < y + height) {
        putpixel_fp = putpixel;
    } else {
        putpixel_fp = (PutpixelFn)g_renderer_vtable.pfn_putpixel;
    }

    if (g_font_format[0] <= 1)
        is_packed = 1;
    else
        is_packed = 0;

    if (g_graphics_context.bText_style_flags & 4)
        x += g_font_underline_offset[0] / 3;

    row = 0;
    while (row < height) {
        if (((styleFlags = (char)g_graphics_context.bText_style_flags) & 1) == 0) {
            g_graphics_context.bGfx_outline_color = g_graphics_context.bText_bg_color;
            draw_line(x, y, x + width, y);
        }
        bit_mask = 0x80;
        col = 0;
        while (col < width) {
            if (is_packed) {
                if (!bit_mask) {
                    bit_mask = 0x80;
                    glyph_ptr++;
                }
                pix = *glyph_ptr & bit_mask;
                bit_mask >>= 1;
            } else {
                if ((pix = *glyph_ptr) != 0) {
                    if (pix < 5)
                        g_graphics_context.bText_fg_color = g_abFontColorRemap[pix];
                    else
                        g_graphics_context.bText_fg_color = pix;
                }
                if (width - 1 > col)
                    glyph_ptr++;
            }
            pixel_x = x + col;
            if (pix != 0) {
                if ((g_graphics_context.bText_style_flags & 0x10) != 0) {
                    if (((pixel_x + y) & 1) != 0) {
                        (*putpixel_fp)(pixel_x, y, (char)g_graphics_context.bText_fg_color);
                    } else if ((g_graphics_context.bText_style_flags & 2) != 0) {
                        (*putpixel_fp)(pixel_x + 1, y, (char)g_graphics_context.bText_fg_color);
                    }
                } else {
                    (*putpixel_fp)(pixel_x, y, (char)g_graphics_context.bText_fg_color);
                    if ((g_graphics_context.bText_style_flags & 2) != 0) {
                        (*putpixel_fp)(pixel_x + 1, y, (char)g_graphics_context.bText_fg_color);
                    }
                }
            } else {
                if ((g_graphics_context.bText_style_flags & 8) != 0 &&
                    g_font_underline_offset[0] + 2 == row) {
                    (*putpixel_fp)(pixel_x, y, saved_fg);
                }
            }
            col++;
        }
        if ((g_graphics_context.bText_style_flags & 4) != 0 && row % 3 == 2)
            x--;
        row++;
        y++;
        glyph_ptr++;
    }
    g_graphics_context.bText_fg_color = saved_fg;
    return width;
}

int font_render_glyph_or_ctrl(char ch, int x, int y) {
    int c;
    int hi;
    unsigned width;
    int height;
    int i;
    int glyph_size;
    unsigned char far *glyph_ptr;

    c = (unsigned char)ch;
    hi = c & 0xf0;
    if (hi == 0xf0 || hi == 0xe0) {
        int nib;

        nib = c & 0x0f;
        switch (nib) {
        case 0:
            g_graphics_context.bText_style_flags = 1;
            g_graphics_context.bText_fg_color = g_saved_text_fg_color;
            break;
        case 1:
            g_graphics_context.bText_style_flags = 5;
            if (g_graphics_context.bText_fg_color != 1 && g_graphics_context.bText_fg_color != 10)
                g_graphics_context.bText_fg_color = 5;
            else
                g_graphics_context.bText_fg_color -= (g_graphics_context.bText_fg_color == 1);
            break;
        case 2:
            if (g_graphics_context.bText_fg_color != 1 && g_graphics_context.bText_fg_color != 10)
                g_graphics_context.bText_fg_color = 5;
            else
                g_graphics_context.bText_fg_color -= (g_graphics_context.bText_fg_color == 1);
            g_graphics_context.bText_style_flags = 5;
            break;
        case 3:
            g_graphics_context.bText_style_flags = 5;
            break;
        case 4:
            g_graphics_context.bText_fg_color = (g_graphics_context.bText_fg_color == 0)    ? 10
                                                : (g_graphics_context.bText_fg_color == 1)  ? 10
                                                : (g_graphics_context.bText_fg_color == 10) ? 1
                                                                                            : 10;

        case 5:
            g_graphics_context.bText_fg_color = (g_graphics_context.bText_fg_color == 0)    ? 1
                                                : (g_graphics_context.bText_fg_color == 1)  ? 11
                                                : (g_graphics_context.bText_fg_color == 10) ? 0
                                                                                            : 1;
            break;
        }
        return 0;
    }

    width = g_graphics_context.pFont_glyph_width_bits[0];
    if ((char)g_graphics_context.bText_style_flags <= 1 &&
        !(char)g_graphics_context.bClip_enabled && g_font_format[0] <= 1 && width <= 8) {
        i = (unsigned char)c - g_graphics_context.pFont_base_char[0];
        if (*(unsigned long *)&g_font_glyph_offset_table[0] != 0) {
            width = g_font_width_table[0][i];
            height = g_graphics_context.pFont_height[0];
            glyph_ptr = g_font_bitmap_data[0] + g_font_glyph_offset_table[0][i];
        } else {
            width = g_graphics_context.pFont_glyph_width_bits[0];
            height = g_graphics_context.pFont_height[0];
            glyph_size = ((width + 7) >> 3) * height;
            glyph_ptr = g_font_bitmap_data[0] + i * glyph_size;
        }
        asm {
            push bp
            push si
            push di
            mov es, word ptr glyph_ptr+2
            mov si, word ptr glyph_ptr
            mov bx, width
            mov cx, height
            mov dx, x
            mov bp, y
            call dword ptr [g_pfn_blit_glyph_row]
            pop di
            pop si
            pop bp
        }
    } else {
        width = font_draw_char((unsigned char)c, x, y);
        if (g_graphics_context.bText_style_flags & 2)
            width++;
    }
    return width;
}

void font_draw_text_ds(char *text, int x, int y) {
    font_draw_text_far((unsigned char far *)text, x, y);
    return;
}

void font_draw_text_far(char far *text, int x, int y) {
    g_saved_text_fg_color = g_graphics_context.bText_fg_color;
    font_render_glyph_or_ctrl(-0x10, 0, 0);
    if (text != (char far *)0) {
        while (*text != '\0') {
            if (*text == ' ') {
                font_render_glyph_or_ctrl(-0x10, 0, 0);
            }
            if (*text == '\t') {
                x += g_nTabWidth;
            } else {
                x += font_render_glyph_or_ctrl(*text, x, y);
            }
            ++text;
        }
        font_render_glyph_or_ctrl(-0x10, 0, 0);
    }
    g_graphics_context.bText_fg_color = g_saved_text_fg_color;
}

int font_glyph_metrics(register int ch, unsigned int *out_width, unsigned int *out_height) {
    unsigned int width;
    register unsigned int height;

    width = 0;
    ch -= (unsigned int)g_graphics_context.pFont_base_char[0];
    if (ch < 0 || g_graphics_context.pFont_glyph_count[0] <= ch) {
        if (ch + (unsigned int)g_graphics_context.pFont_base_char[0] == 9) {
            width = g_nTabWidth;
        }
        if (out_width != 0) {
            *out_width = width;
        }
        if (out_height != 0) {
            *out_height = 0;
        }
        return 0;
    }
    if (*(unsigned long *)&g_font_glyph_offset_table[0] != 0) {
        width = g_font_width_table[0][ch];
    } else {
        width = g_graphics_context.pFont_glyph_width_bits[0];
    }
    height = g_graphics_context.pFont_height[0];
    if (out_width != 0) {
        *out_width = width;
    }
    if (out_height != 0) {
        *out_height = height;
    }
    return 1;
}
