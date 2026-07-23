#include "globals.h"
#include "SRC/GEN/GFXCTX.H"
#include "SRC/SYS/BIOSCHK.H"

int bios_compat_check(void) {
    asm push es;
    asm push bx;
    asm mov bx, 0F000h;
    asm mov es, bx;
    asm mov bx, 0FFFEh;
    asm mov al, byte ptr es : [bx];
    asm cmp al, 0FFh;
    asm jne done;
    asm mov bx, 0C000h;
    asm mov al, byte ptr es : [bx];
    asm cmp al, 21h;
    asm jne done;
    asm mov byte ptr[g_graphics_context.bBiosCompatible], 1;
done:
    asm mov al, byte ptr[g_graphics_context.bBiosCompatible];
    asm cbw;
    asm pop bx;
    asm pop es;
    return _AX;
}
