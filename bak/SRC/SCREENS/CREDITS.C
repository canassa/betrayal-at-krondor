#include "globals.h"
#include "SRC/INPUT/TIMER.H"
#include "structs.h"
#include "SRC/SCREENS/CREDITS.H"
#include "SRC/SYS/RAND.H"
#include "SRC/IO/IO.H"
#include "SRC/SYS/MEM.H"
#include "SRC/GFX/FONT/FONT.H"
#include "SRC/GFX/SPRITE/RESBLIT.H"
#include "SRC/GFX/RASTER/PRESENT.H"
#include "SRC/INPUT/KEYBOARD.H"
#include "SRC/GFX/DRIVER/VTHUNKS.H"
#include "SRC/GFX/RASTER/PIXEL.H"
#include "SRC/COMBAT/ARENA/COMBAT.H"

unsigned char *g_pCreditsBlob;
char **g_credits_strings;
short g_credits_pair_count;
short g_credits_scroll_y;

unsigned short g_nCreditsPassCount = 0x0000;

void credits_load(void) {
    BakFile *stream;
    int i;
    unsigned short blobSize;

    stream = bak_fopen("cred.dat", "rb");
    bak_fread(&g_credits_pair_count, 2, 1, stream);
    g_credits_strings = galloc_safe_zcalloc(g_credits_pair_count << 1);
    bak_fread(g_credits_strings, 2, g_credits_pair_count, stream);
    bak_fread(&blobSize, 2, 1, stream);
    g_pCreditsBlob = galloc_safe_zcalloc(blobSize);
    bak_fread(g_pCreditsBlob, 1, blobSize, stream);
    bak_fclose(stream);
    for (i = 0; i < g_credits_pair_count; i++) {
        g_credits_strings[i] += (int)g_pCreditsBlob;
    }
    return;
}

void credits_free(void) {
    if (g_credits_strings != 0) {
        galloc_zfree(g_credits_strings);
        g_credits_strings = 0;
    }
    if (g_pCreditsBlob != 0) {
        galloc_zfree(g_pCreditsBlob);
        g_pCreditsBlob = 0;
    }
    return;
}

int credits_draw_scroll_pass(int x_left, int width, int reset) {
    int pair_idx;
    int y;
    int x;
    int right_col_x;
    int drew_something;
    int is_name_swap;
    int x_start;
    int x_end;
    int bot_fade_shade;
    int top_fade_shade;
    int band_kind;

    drew_something = 0;
    if (reset != 0) {
        g_credits_scroll_y = -0x10;
        g_nCreditsPassCount++;
    }
    y = 0x36 - g_credits_scroll_y;
    for (pair_idx = 1; pair_idx < g_credits_pair_count; pair_idx += 2) {
        if (g_credits_strings[pair_idx][0] == 'L' && g_credits_strings[pair_idx][1] == 'O' &&
            (int)g_nCreditsPassCount % 0x1e != 8) {
            y -= 0xb;
        } else if (y > g_graphics_context.clip.ymin && y < g_graphics_context.clip.ymax &&
                   (g_credits_strings[pair_idx][0] != '\0' ||
                    g_credits_strings[pair_idx + 1][0] != '\0')) {
            is_name_swap = (((int)g_nCreditsPassCount % 0x1e == 8 || key_is_down(0x31) != 0) &&
                            g_credits_strings[pair_idx + 1][0] == 'N' &&
                            g_credits_strings[pair_idx + 1][5] == 'B')
                               ? 1
                               : 0;

            if (y < g_graphics_context.clip.ymin + 0x10) {
                top_fade_shade = (y + 0x6f) - g_graphics_context.clip.ymin;
                band_kind = 0;
            } else if (g_graphics_context.clip.ymax - 0x11 < y) {
                band_kind = 1;
                bot_fade_shade = 0x7f - (y - (g_graphics_context.clip.ymax - 0x10));
            } else if (is_name_swap != 0) {
                band_kind = 2;
            } else {
                band_kind = 3;
            }

            drew_something = 1;
            switch (band_kind) {
            case 0:
                g_graphics_context.bText_fg_color = (unsigned char)top_fade_shade;
                break;
            case 1:
                g_graphics_context.bText_fg_color = (unsigned char)bot_fade_shade;
                break;
            case 2:
                g_graphics_context.bText_fg_color = RND2(0x100);
                break;
            default:
                g_graphics_context.bText_fg_color = 0;
                break;
            }

            if (g_credits_strings[pair_idx][0] != '\0') {
                int col_x;
                if (g_credits_pair_count - 5 < pair_idx) {
                    col_x =
                        (0xa0 - x_left) - (font_text_width_ds(g_credits_strings[pair_idx]) >> 1);
                } else {
                    col_x = 0x16;
                }
                font_draw_text_ds(g_credits_strings[pair_idx], x_left + col_x, y);
            }

            if (g_credits_strings[pair_idx + 1][0] != '\0') {
                right_col_x =
                    (x_left + width - 0x17) - font_text_width_ds(g_credits_strings[pair_idx + 1]);
                font_draw_text_ds(g_credits_strings[pair_idx + 1], right_col_x, y);
            }

            if (g_credits_strings[pair_idx][0] != '\0' &&
                g_credits_strings[pair_idx + 1][0] != '\0') {
                g_graphics_context.bClip_enabled = 1;
                switch (band_kind) {
                case 0:
                    g_graphics_context.bText_fg_color = (unsigned char)top_fade_shade;
                    break;
                case 1:
                    g_graphics_context.bText_fg_color = (unsigned char)bot_fade_shade;
                    break;
                case 2:
                    g_graphics_context.bText_fg_color = RND2(0x100);
                    break;
                default:
                    g_graphics_context.bText_fg_color = 0;
                    break;
                }
                g_graphics_context.clip.xmax = right_col_x - 4;
                g_graphics_context.clip.xmin =
                    x_left + font_text_width_ds(g_credits_strings[pair_idx]) + 0x18;
                g_graphics_context.clip.ymax = 199;
                x_start = g_graphics_context.clip.xmin - g_graphics_context.clip.xmin % 4;
                x_end = g_graphics_context.clip.xmax + g_graphics_context.clip.xmax % 4 + 3;
                for (x = x_start; x < x_end; x += 4) {
                    int dy;
                    if (band_kind == 2) {
                        g_graphics_context.bText_fg_color = RND2(0x100);
                        dy = (y + x / 4) % 4 + 3;
                    } else {
                        dy = 7;
                    }
                    putpixel(x, y + dy, (int)(char)g_graphics_context.bText_fg_color);
                }
                g_graphics_context.clip.ymax = 0x9e;
                g_graphics_context.bClip_enabled = 0;
            }
        }
        if ((y = y + 0xb) > g_graphics_context.clip.ymax) {
            break;
        }
    }
    g_credits_scroll_y++;
    return !drew_something;
}

int far credits_run(void) {
    int scroll_done;
    unsigned int sc;

    scroll_done = 0;

    g_nFrameTickCountdown = 0x2ee;
    credits_load();
    g_graphics_context.wGfxBlitDstPage = g_graphics_context.wVgaPage1Base;
    resblit_load_pal_or_stream("blank.scx");
    do {
    } while (g_nFrameTickCountdown != 0);
    g_graphics_context.bClip_enabled = 0;
    g_graphics_context.clip.xmin = 0;
    g_graphics_context.clip.xmax = 0x13f;
    g_graphics_context.clip.ymax = 0x9e;
    g_graphics_context.clip.ymin = 0x36;
    g_graphics_context.bText_fg_color = 0;
    font_draw_text_ds(*g_credits_strings, 0xa0 - (font_text_width_ds(*g_credits_strings) >> 1),
                      0x29);
    g_graphics_context.wGfxBlitSrcPage = g_graphics_context.wVgaPage1Base;
    g_graphics_context.wGfxBlitDstPage = g_graphics_context.wVgaPage2Base;
    gfx_present_dispatch(0, 0, 0x140, 200);
    credits_draw_scroll_pass(0x14, 0x118, 1);
    sc = kbhit_read() >> 8;
    while (combat_arena_wait_confirm_cancel() == 0 && sc != 1 && sc != 0x39 && scroll_done == 0) {
        sc = kbhit_read() >> 8;
        g_nFrameTickCountdown = 10;
        g_graphics_context.wGfxBlitSrcPage = g_graphics_context.wVgaPage1Base;
        g_graphics_context.wGfxBlitDstPage = g_graphics_context.wVgaPage2Base;
        gfx_present_dispatch(0x15, 0x35, 0x118, g_graphics_context.clip.ymax - 0x2c);
        scroll_done = credits_draw_scroll_pass(0x14, 0x118, 0);
        vsync_hook(1);
        do {
        } while (g_nFrameTickCountdown != 0);
    }
    while (combat_arena_wait_confirm_cancel() != 0)
        ;
    credits_free();
    return !scroll_done;
}
