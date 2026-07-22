/**
 * @file  DOSMEM.C
 * @brief Far (conventional-memory) allocator over DOS INT 21h AH=48h/49h.
 *
 * @details Inline-asm implementations of @ref alloc_far and @ref _freemem; both
 *          are documented at their declarations in @ref DOSMEM.H. @ref alloc_far
 *          converts a byte size to paragraphs by a shr/rcr shift with a
 *          round-up on any 0..15-byte remainder, and reuses the AH=48h call in
 *          two ways: a normal allocation, and a deliberately-oversized 0xFFFF
 *          paragraph request whose failure reports the largest free block.
 */

#include "structs.h"
#include "SRC/SYS/DOSMEM.H"
#include "SRC/SYS/FARPTR.H" /* memset_far — referenced only in inline asm below */

void far *alloc_far(unsigned long size, long flags) {
    asm mov ax, word ptr size + 2;
    asm mov bx, word ptr size;
    if (_AX == _BX && _AX == 0xFFFF)
        goto query_free;
    _DX = _BX;
    asm shr ax, 1;
    asm rcr bx, 1;
    asm shr ax, 1;
    asm rcr bx, 1;
    asm shr ax, 1;
    asm rcr bx, 1;
    asm shr ax, 1;
    asm rcr bx, 1;
    _DX &= 0x0f;
    asm jz do_alloc;
    _BX++;
do_alloc:
    asm mov ah, 48h;
    asm int 21h;
    asm jnc alloc_ok;
    _AX = 0;
    _DX = 0;
    return;

alloc_ok:
    _DX = _AX;
    asm mov ax, word ptr flags + 2;
    _AX &= 1;
    asm jz done;

    asm push dx;
    asm mov ax, word ptr size + 2;
    asm push ax;
    asm mov ax, word ptr size;
    asm push ax;
    _AX = 0;
    asm push ax;
    asm push dx;
    asm push ax;
    asm call far ptr memset_far;
    asm add sp, 0ah;
    asm pop dx;
    _AX = 0;
    return;

query_free:
    asm mov ah, 48h;
    asm int 21h;
    _AX = _BX;
    _BX = 0;
    asm shl ax, 1;
    asm rcl bx, 1;
    asm shl ax, 1;
    asm rcl bx, 1;
    asm shl ax, 1;
    asm rcl bx, 1;
    asm shl ax, 1;
    asm rcl bx, 1;
    _DX = _BX;
done:;
}

int _freemem(void far *block) {
    asm push es;
    asm mov ax, word ptr block + 2;
    asm mov es, ax;
    asm mov ah, 49h;
    asm int 21h;
    asm pop es;
    return _AX;
}
