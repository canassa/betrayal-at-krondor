#include <dos.h>
#include "globals.h"
#include "structs.h"
#include "SRC/UI/UIWIDGET.H"
#include "SRC/GFX/FONT/FONT.H"
#include "SRC/GFX/SPRITE/RESBLIT.H"
#include "SRC/GFX/SPRITE/RECTSPR.H"
#include "SRC/GFX/RASTER/DRAWLINE.H"
#include "SRC/GFX/RASTER/PIXEL.H"
#include "SRC/STREAM/RESLOAD/IMGLOAD.H"
#include "SRC/GFX/SPRITE/SPRTHNKS.H"


ImageRecord **g_tile_sprite;
ImageRecord **g_pCompassSpriteSheet;

unsigned short g_nSkyHorizonRowCached = 0xffff;
unsigned short g_bTexturedPolyEnabled = 0x0001;
short g_nGlyphColorShift = 0;

void uiwidget_tile_sprite_load(void) {
    g_tile_sprite = resblit_load_asset_table("pat.bmp", 0);
    return;
}

void uiwidget_tile_sprite_free(void) {
    free_image_record(g_tile_sprite);
    return;
}

static void uiwidget_tile_sprite_fill_rect(int x, int y, int w, int h, int sprite_index) {
    int step_x;
    int step_y;
    int ix;
    int iy;

    g_graphics_context.bClip_enabled = 1;
    g_graphics_context.clip.xmin = x;
    g_graphics_context.clip.xmax = x + w - 1;
    g_graphics_context.clip.ymin = y;
    g_graphics_context.clip.ymax = y + h - 1;
    step_x = g_tile_sprite[sprite_index]->nWidth;
    step_y = g_tile_sprite[sprite_index]->nHeight;
    ix = 0;
    if (ix < g_graphics_context.clip.xmax) {
        do {
            iy = 0;
            if (iy < g_graphics_context.clip.ymax) {
                do {
                    blit_sprite_indirect((ushort)g_tile_sprite[sprite_index], x + ix, y + iy, 0);
                    iy += step_y;
                } while (iy < g_graphics_context.clip.ymax);
            }
            ix += step_x;
        } while (ix < g_graphics_context.clip.xmax);
    }
    g_graphics_context.bClip_enabled = 0;
}

static uint uiwidget_glyph_blit(uchar ch, int x, int y) {
    byte far *glyph_data;
    uint row;
    byte mask;
    uint width;
    uint height;
    byte pixel;
    int glyph_index;
    uint color;
    byte prev_pixel;
    uint col;

    glyph_index = (uint)ch - (uint)g_graphics_context.pFont_base_char[0];
    if (g_font_glyph_offset_table[0] != 0) {
        width = (uint)g_font_width_table[0][glyph_index];
        height = (uint)g_graphics_context.pFont_height[0];
        glyph_data = g_font_bitmap_data[0] + g_font_glyph_offset_table[0][glyph_index];
    } else {
        width = (uint)g_graphics_context.pFont_glyph_width_bits[0];
        height = (uint)g_graphics_context.pFont_height[0];
        glyph_data = g_font_bitmap_data[0] + glyph_index * ((width + 7) >> 3) * height;
    }
    row = 0;
    if (row < height) {
        do {
            prev_pixel = 0;
            mask = 0x80;
            col = 0;
            if (col < width) {
                do {
                    if (!mask) {
                        mask = 0x80;
                        (*(unsigned *)&glyph_data)++;
                    }
                    pixel = *glyph_data & mask;
                    if ((pixel != 0) ||
                        ((prev_pixel != 0) && ((g_graphics_context.bText_style_flags & 2) != 0))) {
                        color = getpixel(x + col, y);
                        color += g_nGlyphColorShift;
                        putpixel(x + col, y, color);
                    } else if (((glyph_index = (char)g_graphics_context.bText_style_flags) & 1) ==
                               0) {
                        putpixel(x + col, y, (int)(char)g_graphics_context.bText_bg_color);
                    }
                    prev_pixel = pixel;
                    col = col + 1;
                    mask >>= 1;
                } while (col < width);
            }
            row++;
            y = y + 1;
            (*(unsigned *)&glyph_data)++;
        } while (row < height);
    }
    return width;
}

static void far uiwidget_draw_text_string(uchar *str, int x, int y) {
    while (*str != '\0') {
        x += uiwidget_glyph_blit(*str++, x, y);
        if ((g_graphics_context.bText_style_flags & 2) != 0) {
            x = x + 1;
        }
    }
    return;
}

void uiwidget_draw_text_shadowed_dflt(char *text, int shadow_color, int color, int x, int y) {
    if ((color == -1) && (text != (char *)0x0)) {
        g_graphics_context.bText_fg_color = '\t';
        font_draw_text_ds(text, x, y);
        g_graphics_context.bText_fg_color = '\x0e';
    } else {
        if (text == (char *)0x0) {
            return;
        }
        g_graphics_context.bText_fg_color = (uchar)color;
    }
    font_draw_text_ds(text, x, y + -1);
    return;
}

void uiwidget_draw_text_shadowed(char *text, int shadow_color, int main_color, int x, int y) {
    if (text != (char *)0x0) {
        g_graphics_context.bText_fg_color = shadow_color;
        font_draw_text_ds(text, x, y);
        g_graphics_context.bText_fg_color = main_color;
        font_draw_text_ds(text, x, y + -1);
    }
    return;
}

int uiwidget_midpoint_int(int a, int b) {
    int r;

    if (b < a) {
        r = b;
        b = a;
        a = r;
    }
    r = b - a;
    r = a + (r >> 1);
    return r;
}

void uiwidget_panel_draw_3edge_bevel(int x, int y, int width, int height, int fill_color,
                                     int color1, int color2, int color3, int color4) {
    g_graphics_context.bGfx_fill_enabled = '\x01';
    g_graphics_context.bGfx_fill_color = (uchar)fill_color;
    g_graphics_context.bGfx_outline_color = (uchar)color1;
    draw_rect_filled(x, y, width, height);
    g_graphics_context.bGfx_outline_color = (uchar)color2;
    draw_line(x, y + 1, x, y + height - 1);
    g_graphics_context.bGfx_outline_color = (uchar)color3;
    draw_line(x + width - 1, y, x + width - 1, y + height - 1);
    g_graphics_context.bGfx_outline_color = (uchar)color4;
    draw_line(x, y + height - 1, x + width - 1, y + height - 1);
    putpixel(x, y, uiwidget_midpoint_int(color1, color2));
    putpixel(x + width - 1, y, uiwidget_midpoint_int(color1, color3));
    putpixel(x, y + height - 1, uiwidget_midpoint_int(color2, color4));
    putpixel(x + width - 1, y + height - 1, uiwidget_midpoint_int(color3, color4));
    g_graphics_context.bGfx_fill_enabled = '\x01';
}

void uiwidget_panel_draw_inset(int x, int y, int width, int height, int color) {
    int c1 = color;
    int c2 = color + 2;
    int c3 = color + 5;
    int c4 = color + 6;

    uiwidget_panel_draw_3edge_bevel(x, y, width, height, color, c1, c2, c3, c4);
    return;
}

void uiwidget_panel_inset_inverted(int x, int y, int width, int height, int color_offset) {
    g_graphics_context.bGfx_fill_enabled = '\0';
    g_graphics_context.bGfx_fill_color = '\0';
    uiwidget_panel_draw_inset(x, y, width, height, 0xa9 - color_offset);
    g_graphics_context.bGfx_fill_enabled = '\x01';
    return;
}

void uiwidget_compass_load(void) {
    g_pCompassSpriteSheet = resblit_load_asset_table("compass.bmp", 0);
}

void uiwidget_compass_free(void) {
    free_image_record(g_pCompassSpriteSheet);
}

void uiwidget_compass_draw(void) {
    int compassOffset;

    compassOffset = g_world_camera->base.orientation.yaw;
    if (compassOffset != 0) {
        compassOffset >>= 8;
        compassOffset |= 0xff00;
    }
    g_graphics_context.bClip_enabled = '\x01';
    g_graphics_context.clip.xmin = 0x90;
    g_graphics_context.clip.ymin = 0x79;
    g_graphics_context.clip.xmax = 0xaf;
    g_graphics_context.clip.ymax = 0x83;
    gfx_putsprite_fp(*g_pCompassSpriteSheet, compassOffset + 0x90, 0x79);

    gfx_putsprite_fp(*g_pCompassSpriteSheet, compassOffset + 400, 0x79);
    return;
}

void uiwidget_draw_beveled_button(int x, int y, int w, int h) {
    g_graphics_context.bGfx_fill_enabled = '\x01';
    g_graphics_context.bGfx_fill_color = '\x0e';
    g_graphics_context.bGfx_outline_color = '\x04';
    draw_rect_filled(x, y, w, h);
    g_graphics_context.bGfx_fill_enabled = '\0';
    g_graphics_context.bGfx_outline_color = '\x01';
    draw_line(x, y, x, y + h + -1);
    draw_line(x, y + h + -1, x + w + -1, y + h + -1);
    return;
}
