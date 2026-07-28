/*
 * VIDMODE.C -- BIOS video-mode field get/set (segment 180c).
 *
 * bios_set_video_mode_bits (0x1adc2, 35 bytes) writes mode_bits<<4 into the BDA
 * equipment-word bits 5:4 (0040:0010), preserving the rest, then INT 10h AX=3
 * BX=3. bios_get_video_mode_bits (0x1ade5, 24 bytes) reads that field back and
 * returns it right-aligned in the low nibble (0=EGA/VGA, 1=CGA-40, 2=CGA-80,
 * 3=MDA). Both are near, .cas pseudo-register bodies (bc31 -O2). set takes an
 * int (the word-wide [bp+4] load, not uchar); get's C statements give it the
 * frame and the load-form 32 E4 zero-extend from `_AH ^= _AH`.
 *
 * Split from VIDMODE.ASM; the third proc bios_video_int10_helper needs a
 * different recipe (-O2 without -k, frameless) and lives in VIDINT10.C, linked
 * immediately after this object.
 */
#include "structs.h"
#include "SRC/GFX/DRIVER/VIDMODE.H"

void near bios_set_video_mode_bits(mode_bits)
int mode_bits;
{
    _ES = 0x40;
    _AX = mode_bits;
    _AX <<= 4;
    _BX = 0x10;
    asm and byte ptr es : [bx], 0xcf;
    asm or byte ptr es : [bx], al;
    _AX = 3;
    _BX = 3;
    asm int 0x10;
}

int near bios_get_video_mode_bits(void) {
    _ES = 0x40;
    _BX = 0x10;
    asm mov al, byte ptr es : [bx];
    _AL &= 0x30;
    _AL >>= 4;
    _AH ^= _AH;
    return _AX;
}
