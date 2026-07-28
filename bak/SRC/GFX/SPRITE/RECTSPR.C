/*
 * RECTSPR.C -- blit_sprite_flipped_clipped (180c:0fc9 / 0x19089, 1212 bytes).
 *
 * Blits a sprite with optional horizontal (flags&2) / vertical (flags&1) flip
 * and clipping. Sprite stream format (packed nibble/RLE): byte & 0x80 == 0 is a
 * low-opcode (end-of-row, x-skip, or end-of-sprite), byte & 0xC0 == 0x80 is a
 * solid-colour fill run, byte & 0xC0 == 0xC0 is a nibble-pair pixel run. Each
 * run is drawn through the active renderer's register-convention vtable slots --
 * pfn_blit_sprite_chunky_flip (+0x98) and pfn_fill_run_a (+0x28) -- via inline-
 * asm dispatch blocks (args in CL/CH/AH/SI/DI/BX/ES/DX, carry = horizontal-flip
 * boolean). The two slots take a register calling convention, so they cannot be
 * plain C calls; the dispatch goes through the g_pfn_* scalar slot-labels
 * (RNDVTBL.ASM), the same idiom STRBLIT.C uses for g_pfn_blit_stretched.
 *
 * The sprite param is an ImageRecord: pixel data at wImageData:wImageOff, size
 * nWidth x nHeight.
 *
 * Split from RECTSPR.ASM (draw_rect_filled, the other half, stays asm in
 * DRAWRECT.ASM, linked immediately before this object).
 */
#include "SRC/GEN/GFXCTX.H"
#include "SRC/GEN/RNDVTBL.H"
#include "structs.h"
#include "SRC/GFX/SPRITE/RECTSPR.H"

void blit_sprite_flipped_clipped(void *sprite, int x, int y, int flags) {
    char op;              /* [bp-1]  current stream opcode / run counter */
    char cnt;             /* [bp-2]  pixel-run length for the dispatch  */
    unsigned char far *p; /* [bp-6]  sprite stream read pointer         */
    int skip;             /* [bp-8]  coarse x-skip (<<6)                */
    int yStep;            /* [bp-a]  +1, or -1 when vertically flipped  */
    int xEnd;             /* [bp-c]  x after the current run            */
    int delta;            /* [bp-e]  clip adjustment                    */
    char *bufPtr;         /* [bp-10] run-buffer cursor                  */
    char rowVisible;      /* [bp-11] current row inside the y clip band */
    char clipped;         /* [bp-12] clipping active for this blit      */
    unsigned rowOfs;      /* [bp-14] row start offset from the LUT      */
    int dstPage;          /* [bp-16] destination page segment           */
    char colorBase;       /* [bp-17] palette base from the stream head  */
    char dataByte;        /* [bp-18] current stream data byte           */
    char buf[320];        /* [bp-158] decoded pixel run                 */

    dstPage = g_graphics_context.wGfxBlitDstPage;
    if ((clipped = g_graphics_context.bClip_enabled) != 0 && x >= g_graphics_context.clip.xmin &&
        x + ((ImageRecord *)sprite)->nWidth <= g_graphics_context.clip.xmax &&
        y >= g_graphics_context.clip.ymin &&
        y + ((ImageRecord *)sprite)->nHeight <= g_graphics_context.clip.ymax)
        clipped = 0;

    if ((char)flags & 1) {
        yStep = -1;
        y += ((ImageRecord *)sprite)->nHeight - 1;
    } else {
        yStep = 1;
    }
    if ((char)flags & 2)
        x += ((ImageRecord *)sprite)->nWidth - 1;

    if (!clipped || (rowVisible = y <= g_graphics_context.clip.ymax &&
                                  y >= g_graphics_context.clip.ymin) != 0)
        rowOfs = g_pRow_offset_lut[y];

    p = (unsigned char far *)(((unsigned long)(int)((ImageRecord *)sprite)->wImageData << 16) |
                              (unsigned)((ImageRecord *)sprite)->wImageOff);
    colorBase = *p++;

    for (;;) {
        op = *p++;
        if ((op & 0x80) == 0)
            goto low_opcode;
        if ((op & 0x40) == 0)
            goto solid_run;

        /* nibble-pair pixel run: unpack into buf, then dispatch */
        op &= 0x3f;
        cnt = op;
        bufPtr = buf;
        while (op != 0) {
            dataByte = *p++;
            *bufPtr++ = (char)((unsigned char)dataByte >> 4) + colorBase;
            op--;
            if (op != 0) {
                *bufPtr++ = (dataByte & 0x0f) + colorBase;
                op--;
            }
        }
        bufPtr = buf;
        if ((char)flags & 2) {
            xEnd = x - cnt;
            if (!clipped)
                goto blit_flip;
            if (rowVisible == 0)
                goto run_next;
            if (xEnd < g_graphics_context.clip.xmin || x >= g_graphics_context.clip.xmax)
                goto flip_fixup;
        blit_flip:
            asm push si;
            asm push di;
            asm mov cl, cnt;
            asm xor ah, ah;
            asm mov ch, ah;
            asm mov si, bufPtr;
            asm mov di, rowOfs;
            asm mov bx, x;
            asm mov es, dstPage;
            asm stc;
            asm mov dx, y;
            asm call dword ptr [g_pfn_blit_sprite_chunky_flip];
            asm pop di;
            asm pop si;
            goto run_next;
        flip_fixup:
            if (xEnd < g_graphics_context.clip.xmin) {
                if ((delta = g_graphics_context.clip.xmin - xEnd) > 0x3f)
                    goto run_next;
                if ((cnt -= delta) > 0)
                    goto retry_flip;
                goto run_next;
            retry_flip:
                goto blit_flip;
            } else {
                if ((delta = x - g_graphics_context.clip.xmax) > 0x3f)
                    goto run_next;
                if ((cnt -= delta) <= 0)
                    goto run_next;
                bufPtr += delta;
                x = g_graphics_context.clip.xmax;
                goto blit_flip;
            }
        } else {
            xEnd = x + cnt;
            if (!clipped)
                goto blit_norm;
            if (rowVisible == 0)
                goto run_next;
            if (x < g_graphics_context.clip.xmin || xEnd > g_graphics_context.clip.xmax)
                goto blit_fixup;
        blit_norm:
            asm push si;
            asm push di;
            asm mov cl, cnt;
            asm xor ah, ah;
            asm mov ch, ah;
            asm mov si, bufPtr;
            asm mov di, rowOfs;
            asm mov bx, x;
            asm mov es, dstPage;
            asm clc;
            asm mov dx, y;
            asm call dword ptr [g_pfn_blit_sprite_chunky_flip];
            asm pop di;
            asm pop si;
            goto run_next;
        blit_fixup:
            if (x < g_graphics_context.clip.xmin) {
                if ((delta = g_graphics_context.clip.xmin - x) > 0x3f)
                    goto run_next;
                if ((cnt -= delta) <= 0)
                    goto run_next;
                bufPtr += delta;
                x = g_graphics_context.clip.xmin;
                goto blit_norm;
            } else {
                if ((delta = xEnd - g_graphics_context.clip.xmax - 1) > 0x3f)
                    goto run_next;
                if ((cnt -= delta) <= 0)
                    goto run_next;
                goto blit_norm;
            }
        }
    run_next:
        x = xEnd;
        continue;

    solid_run:
        /* solid-colour fill run */
        op &= 0x3f;
        dataByte = *p++;
        if ((char)flags & 2) {
            xEnd = x - op;
            if (!clipped)
                goto fill_flip;
            if (rowVisible == 0)
                goto solid_next;
            if (xEnd < g_graphics_context.clip.xmin || x >= g_graphics_context.clip.xmax)
                goto fill_flip_fixup;
        fill_flip:
            asm push di;
            asm mov al, colorBase;
            asm add al, dataByte;
            asm xor ah, ah;
            asm mov ch, ah;
            asm mov bx, x;
            asm mov cl, op;
            asm sub bx, cx;
            asm inc bx;
            asm mov di, rowOfs;
            asm mov es, dstPage;
            asm mov dx, y;
            asm call dword ptr [g_pfn_fill_run_a];
            asm pop di;
            goto solid_next;
        fill_flip_fixup:
            if (xEnd < g_graphics_context.clip.xmin) {
                if ((delta = g_graphics_context.clip.xmin - xEnd) > 0x3f)
                    goto solid_next;
                if ((op -= delta) > 0)
                    goto retry_fill;
                goto solid_next;
            retry_fill:
                goto fill_flip;
            } else {
                if ((delta = x - g_graphics_context.clip.xmax) > 0x3f)
                    goto solid_next;
                if ((op -= delta) <= 0)
                    goto solid_next;
                x = g_graphics_context.clip.xmax;
                goto fill_flip;
            }
        } else {
            xEnd = x + op;
            if (!clipped)
                goto fill_norm;
            if (rowVisible == 0)
                goto solid_next;
            if (x < g_graphics_context.clip.xmin || xEnd > g_graphics_context.clip.xmax)
                goto fill_fixup;
        fill_norm:
            asm push di;
            asm mov al, dataByte;
            asm add al, colorBase;
            asm xor ah, ah;
            asm mov ch, ah;
            asm mov bx, x;
            asm mov cl, op;
            asm mov di, rowOfs;
            asm mov es, dstPage;
            asm mov dx, y;
            asm call dword ptr [g_pfn_fill_run_a];
            asm pop di;
            goto solid_next;
        fill_fixup:
            if (x < g_graphics_context.clip.xmin) {
                if ((delta = g_graphics_context.clip.xmin - x) > 0x3f)
                    goto solid_next;
                if ((op -= delta) <= 0)
                    goto solid_next;
                x += delta;
                goto fill_norm;
            } else {
                if ((delta = xEnd - g_graphics_context.clip.xmax - 1) > 0x3f)
                    goto solid_next;
                if ((op -= delta) <= 0)
                    goto solid_next;
                goto fill_norm;
            }
        }
    solid_next:
        x = xEnd;
        continue;

    low_opcode:
        if (op & 0x40) {
            /* coarse x-skip */
            if ((op &= 0x3f) == 0)
                return; /* end of sprite */
            if ((char)flags & 2)
                x -= op;
            else
                x += op;
            continue;
        }
        /* end of row */
        op &= 0x3f;
        y += yStep;
        if (!clipped || (rowVisible = y <= g_graphics_context.clip.ymax &&
                                      y >= g_graphics_context.clip.ymin) != 0)
            rowOfs = g_pRow_offset_lut[y];
        if ((char)flags & 2)
            x += op;
        else
            x -= op;
        if (!((op = *p) & 0xc0)) {
            if ((skip = op & 0x3f) != 0) {
                p++;
                skip <<= 6;
                if ((char)flags & 2)
                    x = x + skip;
                else
                    x = x - skip;
            }
        }
    }
}
