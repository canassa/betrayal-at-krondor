#include "globals.h"
#include "structs.h"
#include "SRC/GFX/SPRITE/STRBLIT.H"
#include "SRC/GFX/RASTER/VGARESET.H"

int stretch_step_init(register int *step, register int dest_steps) {
    char negate = 0;

    if (dest_steps <= 0) {
        step[3] = 0;
        step[2] = 0;
        return (*step = 0);
    }
    *step = 0;
    step[2] = 0;
    *(long *)&step[2] -= *(long *)&step[0];
    *(long *)&step[2] = *(long *)&step[2] / (long)dest_steps;
    if (*(long *)&step[2] < 0) {
        *(long *)&step[2] = -*(long *)&step[2];
        negate = 1;
    }
    if ((*(unsigned long *)&step[2] & 0xffff8000UL) == 0)
        *step = 0x8000;
    else
        *step = step[2];
    if (negate)
        *(long *)&step[2] = -*(long *)&step[2];
    return 1;
}

void blit_image_stretched(ImageRecord *image, int dst_x, int dst_y, uint flags, int dst_w,
                          int dst_h) {
    ushort srcSeg;
    ushort srcOff;
    int i;
    int row;
    int rowStride;
    int imageBytes;
    int dstRight;
    int dstBottom;
    int srcY;
    int local_16;
    int local_18;
    int dstLeft;
    int step[4];

    if (dst_w < 0) {

        asm mov ax, dst_w;
        asm cwd;
        asm xor ax, dx;
        asm sub ax, dx;
        asm mov dst_w, ax;
        flags |= 2;
    }
    if (dst_h < 0) {
        asm mov ax, dst_h;
        asm cwd;
        asm xor ax, dx;
        asm sub ax, dx;
        asm mov dst_h, ax;
        flags |= 1;
    }

    dstRight = (dst_w < 0x280) ? dst_w : 0x280;
    dstBottom = (dst_h < 0x190) ? dst_h : 0x190;

    if (flags & 2) {
        step[1] = image->nWidth - 1;
        step[3] = 0;
    } else {
        step[1] = 0;
        step[3] = image->nWidth - 1;
    }
    stretch_step_init(step, dst_w - 1);
    for (i = 0; i < dstRight; i++) {
        g_aStretchXSrcTable[i] = step[1];
        *(long *)&step[0] += *(long *)&step[2];
    }
    g_aStretchXSrcTable[i]++;

    step[1] = 0;
    step[3] = image->nHeight - 1;
    stretch_step_init(step, dst_h - 1);
    rowStride = image->nWidth >> g_abAdapterRowStrideShift[(char)g_graphics_context.bVideoAdapter];
    imageBytes = image->nHeight * rowStride;
    row = local_16 = local_18 = 0;
    for (; row < dstBottom; row++) {
        srcY = step[1];
        *(long *)&step[0] += *(long *)&step[2];
        while (srcY > local_16) {
            local_16++;
            local_18 += rowStride;
        }
        if (flags & 1)
            g_aStretchYSrcTable[dstBottom - row - 1] = local_18;
        else
            g_aStretchYSrcTable[row] = local_18;
    }

    dstBottom += dst_y;
    dstRight += dst_x;
    local_18 = dst_y;
    dstLeft = dst_x;
    local_16 = 0;
    if (g_graphics_context.bClip_enabled != 0) {
        if (dstRight > g_graphics_context.clip.xmax)
            dstRight -= dstRight - g_graphics_context.clip.xmax - 1;
        if (dstBottom > g_graphics_context.clip.ymax)
            dstBottom -= dstBottom - g_graphics_context.clip.ymax - 1;
        if (local_18 < g_graphics_context.clip.ymin)
            local_18 = g_graphics_context.clip.ymin;
        if (dstLeft < g_graphics_context.clip.xmin) {
            local_16 = g_graphics_context.clip.xmin - dstLeft;
            dstLeft = g_graphics_context.clip.xmin;
        }
    }

    *(long *)&srcOff = ((long)(short)image->wImageData << 16) | image->wImageOff;
    if (0 < dstBottom - local_18 && 1 < dstRight - dstLeft) {
        if (g_graphics_context.bActiveVgaMode == 0x10) {

            asm mov dx, 0x3ce;
            asm mov ax, 1;
            asm out dx, ax;
            asm mov ax, 5;
            asm out dx, ax;
            asm mov al, 8;
            asm out dx, al;
        }
        asm mov ax, word ptr[g_wGfxBlitDstPage];
        asm mov es, ax;
        asm mov ax, local_18;
        asm mov row, ax;
    draw_loop:
        asm mov ax, ss;
        asm mov ds, ax;
        asm mov bx, row;
        asm mov cx, bx;
        asm shl bx, 1;
        asm mov di, word ptr[bx + g_pRow_offset_lut];
        asm mov ax, dst_y;
        asm shl ax, 1;
        asm sub bx, ax;
        asm mov ax, imageBytes;
        asm mov si, word ptr[bx + g_aStretchYSrcTable];
        asm mov bx, cx;
        asm add si, srcOff;
        asm mov ds, srcSeg;
        asm mov dx, dstLeft;
        asm mov cx, dstRight;
        asm sub cx, dx;
        asm push bp;
        asm mov bp, local_16;
        asm shl bp, 1;
        asm lea bp, [bp + g_aStretchXSrcTable];
        asm call dword ptr ss : [g_pfn_blit_stretched];
        asm pop bp;
        asm mov ax, row;
        asm inc ax;
        asm cmp ax, dstBottom;
        asm mov row, ax;
        asm jl draw_loop;
        asm mov ax, ss;
        asm mov ds, ax;
        vga_reset_gc_default();
    }
}

void blit_image_scaled_centered(register ImageRecord *image, int cx, int cy, ulong scale_q16) {
    register int scale_hi;
    int dst_w;
    int dst_h;

    scale_hi = (int)(scale_q16 >> 16);
    dst_w = (int)((long)image->nWidth * (long)scale_hi >> 10);
    dst_h = (int)((long)image->nHeight * (long)scale_hi >> 10);
    blit_image_stretched(image, cx - (dst_w >> 1), cy - (dst_h >> 1), (uint)scale_q16, dst_w,
                         dst_h);
    return;
}
