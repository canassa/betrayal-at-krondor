#include "structs.h"
#include "SRC/GEN/GFXCTX.H"
#include <conio.h>
#include "SRC/GFX/RASTER/VGARESET.H"

void vga_reset_gc_default(void) {
    unsigned v;
    if (g_graphics_context.bActiveVgaMode == '\x10') {

        outpw(0x3ce, v = 0x0205);
        outpw(0x3ce, v = 0xff08);
        outpw(0x3c4, 0x0f02);
    }
}

void gfx_retf_stub() {
}
