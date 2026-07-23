#include "structs.h"
#include "globals.h"
#include "SRC/GEN/GFXCTX.H"
#include "SRC/GFX/FONT/FONT.H"
#include "SRC/GFX/SCREEN/DISSOLV.H"

static unsigned int tap_table[62] = {
    0x0003, 0x0000, 0x0006, 0x0000, 0x000C, 0x0000, 0x0014, 0x0000, 0x0030, 0x0000, 0x0060,
    0x0000, 0x00B8, 0x0000, 0x0110, 0x0000, 0x0240, 0x0000, 0x0500, 0x0000, 0x0CA0, 0x0000,
    0x1B00, 0x0000, 0x3500, 0x0000, 0x6000, 0x0000, 0xB400, 0x0000, 0x2000, 0x0001, 0x0400,
    0x0002, 0x2000, 0x0007, 0x0000, 0x0009, 0x0000, 0x0014, 0x0000, 0x0030, 0x0000, 0x0040,
    0x0000, 0x00D8, 0x0000, 0x0120, 0x0000, 0x0388, 0x0000, 0x0720, 0x0000, 0x0900, 0x0000,
    0x1400, 0x0000, 0x3280, 0x0000, 0x4800, 0x0000, 0xA300};

unsigned short dissolve_transition_lfsr(int origin_x, int origin_y, unsigned int width, unsigned int height) {
    unsigned int width_m1;
    unsigned int height_m1;
    unsigned int x_coord;
    unsigned int y_coord;
    unsigned long lfsr_mask;
    unsigned long taps;
    unsigned long lfsr_state;
    int height_bits;
    unsigned int s;
    int total_bits;

    lfsr_mask = 0;
    lfsr_state = 0;
    height_bits = 0;
    total_bits = -2;

    width_m1 = width - 1;
    height_m1 = height - 1;

    s = width;
    while (s != 0) {
        s >>= 1;
        total_bits++;
    }

    s = height;
    while (s != 0) {
        lfsr_mask = lfsr_mask * 2 + 1;
        s >>= 1;
        total_bits++;
        height_bits++;
    }

    taps = *(unsigned long *)(tap_table + total_bits * 2);
    lfsr_state = 1;

    g_graphics_context.wGfxBlitDstPage = g_graphics_context.wVgaFrontPageBase;
    g_graphics_context.wGfxBlitSrcPage = g_graphics_context.wVgaPage2Base;

    do {
        if (((unsigned int)lfsr_state & lfsr_mask) <= height_m1 &&
            (unsigned int)(lfsr_state >> height_bits) <= width_m1) {
            y_coord = ((unsigned int)lfsr_state & lfsr_mask) + origin_y;
            x_coord = (unsigned int)(lfsr_state >> height_bits) + origin_x;
            (*(void(far *)(unsigned int, unsigned int, unsigned int))g_renderer_vtable.pfn_putpixel)(
                x_coord, y_coord,
                (*(unsigned int(far *)(unsigned int, unsigned int))g_renderer_vtable.pfn_getpixel)(x_coord, y_coord));
        }
        if ((unsigned int)lfsr_state & 1)
            lfsr_state = (lfsr_state >> 1) ^ taps;
        else
            lfsr_state = lfsr_state >> 1;
    } while (lfsr_state != 1);

    (*(void(far *)(int, int, unsigned int))g_renderer_vtable.pfn_putpixel)(
        origin_x, origin_y,
        (*(unsigned int(far *)(int, int))g_renderer_vtable.pfn_getpixel)(origin_x, origin_y));
    return 1;
}
