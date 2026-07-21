#include <dos.h>

#include "globals.h"
#include "structs.h"
#include "SRC/GFX/RASTER/CIRCLE.H"
#include "SRC/GFX/RASTER/POLYGON.H"

short g_nCircleCenterX;
short g_nCircleClipCenterY;
short g_nCircleClipDyMax;
short g_nCircleClipDyMin;
short g_nCircleClipTopY;
unsigned short far *g_pSpanBufCursor;
CirclePlotterFn *g_pfnCirclePlotter;

void far draw_circle(int radius, int cx, int cy) {
    void far *spanBuf;

    if (g_graphics_context.bGfx_fill_enabled != 0) {
        g_pfnCirclePlotter = (CirclePlotterFn *)record_circle_span;
        if ((spanBuf = (void far *)draw_circle_bresenham(radius, cx, cy)) != 0) {
            fill_spans_dispatch(FP_OFF(spanBuf), FP_SEG(spanBuf));
        }
    }
    if ((g_graphics_context.bGfx_outline_color != g_graphics_context.bGfx_fill_color) ||
        !((char)g_graphics_context.bGfx_fill_enabled)) {
        g_pfnCirclePlotter = (CirclePlotterFn *)circle_plot_mirror_pair;
        draw_circle_bresenham(radius, cx, cy);
    }
}

typedef void(near *NearPlotterFn)(int x, int y);

ulong near draw_circle_bresenham(int radius, int cx, int cy) {
    register int x;
    register int r;
    int d;
    ushort rows;
    ushort far *p;

    p = g_pSpanBufCursor =
        (ushort far *)((long)(int)g_graphics_context_render.wSpanTableBufSeg << 16);
    x = 0;
    r = radius;
    d = 3 - radius * 2;
    *g_pSpanBufCursor = g_nCircleClipTopY =
        (cy - radius < g_graphics_context.clip.ymin) ? g_graphics_context.clip.ymin : (cy - radius);
    g_pSpanBufCursor++;
    rows = (cy - g_nCircleClipTopY) + radius + 1;
    *g_pSpanBufCursor = rows = ((g_graphics_context.clip.ymax - g_nCircleClipTopY) + 1 > (int)rows)
                                   ? rows
                                   : (g_graphics_context.clip.ymax - g_nCircleClipTopY) + 1;
    g_pSpanBufCursor++;
    if (g_nCircleClipTopY > g_graphics_context.clip.ymax) {
        return 0;
    }
    if ((int)(g_nCircleClipTopY + rows) < g_graphics_context.clip.ymin) {
        return 0;
    }
    g_nCircleClipDyMin = g_graphics_context.clip.ymin - g_nCircleClipTopY;
    g_nCircleClipDyMax = g_graphics_context.clip.ymax - g_nCircleClipTopY;
    g_nCircleCenterX = cx;
    g_nCircleClipCenterY = cy - g_nCircleClipTopY;
    for (; x <= r; x++) {
        (*(NearPlotterFn *)&g_pfnCirclePlotter)(x, -r);
        (*(NearPlotterFn *)&g_pfnCirclePlotter)(x, r);
        (*(NearPlotterFn *)&g_pfnCirclePlotter)(r, -x);
        (*(NearPlotterFn *)&g_pfnCirclePlotter)(r, x);
        if (d < 0) {
            d += (x << 1 << 1) + 6;
        } else {
            d += ((x - r) << 1 << 1) + 10;
            r--;
        }
    }
    return (ulong)p;
}

void near record_circle_span(int dx, int dy) {
    int left;
    int right;
    ushort far *p;

    left = (g_nCircleCenterX - dx) - (dx >> 1 >> 1 >> 1);
    right = g_nCircleCenterX + dx + (dx >> 1 >> 1 >> 1);
    dy += g_nCircleClipCenterY;

    if (g_graphics_context.bClip_enabled != 0) {
        if (dy < g_nCircleClipDyMin) {
            return;
        }
        if (dy > g_nCircleClipDyMax) {
            return;
        }
        if (left < g_graphics_context.clip.xmin) {
            left = g_graphics_context.clip.xmin;
            if (right < g_graphics_context.clip.xmin) {
                right = g_graphics_context.clip.xmin;
            }
        }
        if (right > g_graphics_context.clip.xmax) {
            right = g_graphics_context.clip.xmax;
            if (left > g_graphics_context.clip.xmax) {
                left = right = 0;
            }
        }
    }

    p = g_pSpanBufCursor + dy * 2;
    *p = left;
    p++;
    *p = right;
}

void near circle_plot_mirror_pair(int dx, int dy) {
    int left_x;
    int right_x;

    left_x = (g_nCircleCenterX - dx) - (dx >> 1 >> 1 >> 1);
    right_x = g_nCircleCenterX + dx + (dx >> 1 >> 1 >> 1);
    dy += g_nCircleClipCenterY;
    if (g_graphics_context.bClip_enabled != 0) {
        if (dy < g_nCircleClipDyMin || dy > g_nCircleClipDyMax)
            return;
        dy += g_nCircleClipTopY;
        if (left_x >= g_graphics_context.clip.xmin && left_x <= g_graphics_context.clip.xmax)
            (*(PutpixelFn)g_renderer_vtable.pfn_putpixel)(
                left_x, dy, (char)g_graphics_context.bGfx_outline_color);
        if (right_x >= g_graphics_context.clip.xmin && right_x <= g_graphics_context.clip.xmax) {
            (*(PutpixelFn)g_renderer_vtable.pfn_putpixel)(
                right_x, dy, (char)g_graphics_context.bGfx_outline_color);
            return;
        }
    } else {
        dy += g_nCircleClipTopY;
        (*(PutpixelFn)g_renderer_vtable.pfn_putpixel)(left_x, dy,
                                                      (char)g_graphics_context.bGfx_outline_color);
        (*(PutpixelFn)g_renderer_vtable.pfn_putpixel)(right_x, dy,
                                                      (char)g_graphics_context.bGfx_outline_color);
    }
}
