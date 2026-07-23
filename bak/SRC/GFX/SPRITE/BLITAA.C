#include <dos.h>

#include "SRC/GEN/GFXCTX.H"
#include "SRC/R3D/SCENE/WORLDHIT.H"
#include "structs.h"
#include "SRC/GFX/SPRITE/BLITAA.H"
#include "SRC/GFX/SPRITE/RESBLIT.H"
#include "SRC/GFX/SPRITE/PALBLEND.H"
#include "SRC/GFX/RASTER/PIXEL.H"

unsigned long g_pAaPaletteBuf;

void blit_sprite_aa_edges(ImageRecord *sprite, int dst_x, int dst_y, unsigned char far *palette) {
    unsigned char far *src;
    int y;
    int cur;
    int color;
    int x;
    int prev;

    g_graphics_context.wGfxBlitSrcPage = g_graphics_context.wGfxBlitDstPage;
    *(unsigned char far **)&g_pAaPaletteBuf = palette;
    resblit_sprite(sprite, dst_x, dst_y);
    src = g_pMainScratchBuf;
    y = 0;
    while (sprite->nHeight > y) {
        x = 0;
        prev = 0;
        while (x < sprite->nWidth) {
            cur = (char)*((unsigned char far *)MK_FP(FP_SEG(src), x * sprite->nHeight + y) + FP_OFF(src));
            if (prev == 0 && cur != 0) {
                if (0 < (color = palette_blend_lookup(getpixel(dst_x + x + -2, dst_y), cur))) {
                    putpixel(dst_x + x + -1, dst_y, color);
                }
            } else if (prev != 0 && cur == 0) {
                if (0 < (color = palette_blend_lookup(getpixel(dst_x + x + 1, dst_y), prev))) {
                    putpixel(dst_x + x, dst_y, color);
                }
            }
            x = x + 1;
            prev = cur;
        }
        y++;
        dst_y++;
    }
}
