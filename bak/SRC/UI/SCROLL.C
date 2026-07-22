#include "globals.h"
#include "structs.h"
#include "SRC/UI/SCROLL.H"

#include "SRC/GFX/RASTER/PRESENT.H"
#include <conio.h>

short g_nVgaScrollPageCount;
short g_nVgaScrollPanStep;
unsigned char far *g_pVgaScrollScratchBuf;

void far scrolltrans_scroll_fast(int direction, int speed, int distance) {
    uchar far *front_end;
    uchar far *page2_end;
    uchar far *page1_end;
    uchar far *scratch;
    int xOff;
    int screen_width;
    int x_step;
    int y_step;
    int absStep;
    int fallback;
    int y;
    int set_split;

    fallback = 0;
    if (distance > 0x140) {
        scrolltrans_scroll(direction, speed, distance);
        return;
    }
    if (direction < 0 || direction > 3 || speed < 1 || distance < 0 ||
        (g_graphics_context.bVideoAdapter != '\x02' &&
         g_graphics_context.bVideoAdapter != '\x08')) {
        fallback = 1;
    }
    if (fallback) {
        g_graphics_context.wGfxBlitDstPage = g_graphics_context.wVgaFrontPageBase;
        g_graphics_context.wGfxBlitSrcPage = g_graphics_context.wVgaPage2Base;
        gfx_present_dispatch(0, 0, 0x140, 200);
        g_graphics_context.wGfxBlitDstPage = g_graphics_context.wVgaPage2Base;
        g_graphics_context.wGfxBlitSrcPage = g_graphics_context.wVgaFrontPageBase;
        return;
    }

    outpw(0x3c4, 0xf02);
    outpw(0x3ce, g_graphics_context.bVideoAdapter == '\x08' ? 0x4105 : 0x105);

    screen_width = (g_graphics_context.bVideoAdapter == '\x08') ? 0x50 : 0x28;

    {
        int sw200 = screen_width * 200;
        front_end =
            (uchar far *)((unsigned long)((long)(int)g_graphics_context.wVgaFrontPageBase << 16) +
                          (unsigned)sw200 - 1);
        page2_end =
            (uchar far *)((unsigned long)((long)(int)g_graphics_context.wVgaPage2Base << 16) +
                          (unsigned)sw200 - 1);
        page1_end =
            (uchar far *)((unsigned long)((long)(int)g_graphics_context.wVgaPage1Base << 16) +
                          (unsigned)sw200 - 1);
        scratch = (uchar far *)((unsigned long)(unsigned int)(sw200 << 1) + 0xa8000050UL - 1);
    }

    if (direction == 0) {
        for (y = screen_width * 200; y != 0; y--) {
            *scratch-- = *page2_end;
            *page2_end-- = *page1_end--;
        }
        for (y = screen_width * 200; y != 0; y--) {
            *scratch-- = *front_end--;
        }
        distance = distance > 200 ? 200 : distance;
        xOff = 0;
        y = 0;
        x_step = 0;
        y_step = 1;
    } else if (direction == 1) {
        for (y = screen_width * 200; y != 0; y--) {
            *scratch-- = *front_end--;
        }
        for (y = screen_width * 200; y != 0; y--) {
            *scratch-- = *page2_end;
            *page2_end-- = *page1_end--;
        }
        distance = distance > 200 ? 200 : distance;
        xOff = 0;
        y = 200;
        x_step = 0;
        y_step = -1;
    } else if (direction == 2) {
        for (y = 200; y != 0; y--) {
            for (xOff = screen_width; xOff != 0; xOff--) {
                *scratch-- = *page2_end;
                *page2_end-- = *page1_end--;
            }
            for (xOff = screen_width; xOff != 0; xOff--) {
                *scratch-- = *front_end--;
            }
        }
        distance = distance > 0x140 ? 0x140 : distance;
        xOff = 0;
        y = 0;
        x_step = 1;
        y_step = 0;
    } else {
        if (direction != 3)
            goto lab_320;
        for (y = 200; y != 0; y--) {
            for (xOff = screen_width; xOff != 0; xOff--) {
                *scratch-- = *front_end--;
            }
            for (xOff = screen_width; xOff != 0; xOff--) {
                *scratch-- = *page2_end;
                *page2_end-- = *page1_end--;
            }
        }
        distance = distance > 0x140 ? 0x140 : distance;
        xOff = 0x140;
        y = 0;
        x_step = -1;
        y_step = 0;
    }

lab_320:
    g_pVgaScrollScratchBuf = scratch + 1;
    g_nVgaScrollPanStep = -0x7fb0;
    g_nVgaScrollPageCount = 2;

    speed = speed > distance ? distance : speed;

    x_step = x_step * (distance / speed);
    y_step = y_step * (distance / speed);

    outpw(0x3ce, g_graphics_context.bVideoAdapter == '\x08' ? 0x4005 : 5);

    absStep = (x_step + y_step < 0) ? -(x_step + y_step) : (x_step + y_step);

    set_split = (direction >= 2) ? 1 : 0;
    while (distance != 0) {
        scrolltrans_pageflip_pan(xOff, y, screen_width, set_split);
        if (absStep > distance) {
            if (x_step != 0) {
                x_step = (x_step < 0) ? -distance : distance;
            }
            if (y_step != 0) {
                y_step = (y_step < 0) ? -distance : distance;
            }
            absStep = distance;
        }
        xOff += x_step;
        y += y_step;
        distance -= absStep;
        set_split = 0;
    }

    scrolltrans_pageflip_pan(xOff, y, screen_width, set_split);
    scrolltrans_planar_blit_pageflip(direction, xOff, y, screen_width);
}

void far scrolltrans_scroll(int direction, int duration, int distance) {
    uchar far *front_end;
    uchar far *page2_end;
    uchar far *page1_end;
    uchar far *scratch;
    int xOff;
    int screen_width;
    int absStep;
    ulong fy_idx;
    int x_step;
    int y_step;
    uint y;
    int set_split;
    int fallback;

    fallback = 0;
    if (direction < 0 || direction > 3 || duration < 1 || distance < 0 ||
        (g_graphics_context.bVideoAdapter != '\x02' &&
         g_graphics_context.bVideoAdapter != '\x08')) {
        fallback = 1;
    }
    if (fallback) {
        g_graphics_context.wGfxBlitDstPage = g_graphics_context.wVgaFrontPageBase;
        g_graphics_context.wGfxBlitSrcPage = g_graphics_context.wVgaPage1Base;
        gfx_present_dispatch(0, 0, 0x140, 200);
        g_graphics_context.wGfxBlitDstPage = g_graphics_context.wVgaPage2Base;
        g_graphics_context.wGfxBlitSrcPage = g_graphics_context.wVgaFrontPageBase;
        gfx_present_dispatch(0, 0, 0x140, 200);
        return;
    }

    outpw(0x3c4, 0xf02);
    outpw(0x3ce, g_graphics_context.bVideoAdapter == '\x08' ? 0x4105 : 0x105);

    screen_width = (g_graphics_context.bVideoAdapter == '\x08') ? 0x50 : 0x28;

    {
        int sw200 = screen_width * 200;
        g_nVgaScrollPageCount = 3;
        front_end = (uchar far *)((ulong)(g_graphics_context.wVgaFrontPageBase << 4) +
                                  (ulong)(unsigned)sw200 + 0xa0000000UL - 1);
        page2_end = (uchar far *)((ulong)(g_graphics_context.wVgaPage2Base << 4) +
                                  (ulong)(unsigned)sw200 + 0xa0000000UL - 1);
        page1_end = (uchar far *)((ulong)(g_graphics_context.wVgaPage1Base << 4) +
                                  (ulong)(unsigned)sw200 + 0xa0000000UL - 1);
    }
    scratch = (uchar far *)0xa000ffffUL;
    g_nVgaScrollPanStep = -(screen_width * 600);

    if (direction == 0 || direction == 2) {
        for (y = screen_width * 200; y != 0; y--) {
            *scratch-- = *page1_end--;
        }
        for (y = screen_width * 200; y != 0; y--) {
            *scratch-- = *page2_end--;
        }
        for (y = screen_width * 200; y != 0; y--) {
            *scratch-- = *front_end--;
        }
    } else {
        for (y = screen_width * 200; y != 0; y--) {
            *scratch-- = *front_end--;
        }
        for (y = screen_width * 200; y != 0; y--) {
            *scratch-- = *page2_end;
            *page2_end-- = *page1_end--;
        }
        page2_end += screen_width * 200;
        for (y = screen_width * 200; y != 0; y--) {
            *scratch-- = *page2_end--;
        }
    }

    scratch++;
    g_pVgaScrollScratchBuf = scratch;

    if (direction == 2 || direction == 3) {
        front_end = scratch;
        y = 0;
        do {
            fy_idx = y;
            while ((fy_idx = (fy_idx * 200) % 599) < y) {
            }
            if (y < fy_idx) {
                page2_end = front_end + (int)(fy_idx * (unsigned)screen_width);
                page1_end = front_end - 1;
                for (xOff = screen_width; xOff != 0; xOff--) {
                    *page1_end = *page2_end;
                    *page2_end++ = *scratch;
                    *scratch++ = *page1_end;
                }
            } else {
                scratch += screen_width;
            }
            y++;
        } while (y < 599);
    }

    if (direction == 0) {
        distance = distance > 400 ? 400 : distance;
        xOff = 0;
        y = 0;
        x_step = 0;
        y_step = 1;
    } else if (direction == 1) {
        distance = distance > 400 ? 400 : distance;
        xOff = 0;
        y = 400;
        x_step = 0;
        y_step = -1;
    } else if (direction == 2) {
        distance = distance > 0x280 ? 0x280 : distance;
        xOff = 0;
        y = 0;
        x_step = 1;
        y_step = 0;
    } else if (direction == 3) {
        distance = distance > 0x280 ? 0x280 : distance;
        xOff = 0x280;
        y = 0;
        x_step = -1;
        y_step = 0;
    }

    duration = duration > distance ? distance : duration;

    x_step = x_step * (distance / duration);
    y_step = y_step * (distance / duration);

    outpw(0x3ce, g_graphics_context.bVideoAdapter == '\x08' ? 0x4005 : 5);

    absStep = (x_step + y_step < 0) ? -(x_step + y_step) : (x_step + y_step);

    set_split = (direction >= 2) ? 1 : 0;
    while (distance != 0) {
        scrolltrans_pageflip_pan(xOff, y, screen_width, set_split);
        if ((uint)absStep > distance) {
            if (x_step != 0) {
                x_step = (x_step < 0) ? -distance : distance;
            }
            if (y_step != 0) {
                y_step = (y_step < 0) ? -distance : distance;
            }
            absStep = distance;
        }
        xOff += x_step;
        y += y_step;
        distance -= absStep;
        set_split = 0;
    }

    scrolltrans_pageflip_pan(xOff, y, screen_width, set_split);
    scrolltrans_planar_blit_pageflip(direction, xOff, y, screen_width);
}

void scrolltrans_pageflip_pan(int x_off, int line, int screen_width, int set_split) {
    int pan;
    int start_addr;

    start_addr = x_off / (0x140 / screen_width) + line * screen_width + g_nVgaScrollPanStep;
    pan = (x_off & (0x140 / screen_width - 1)) * (screen_width / 0x28);

    while (inp(0x3da) & 8)
        ;
    outp(0x3d4, 0x0c);
    outp(0x3d5, (char)((unsigned)start_addr >> 8));
    outp(0x3d4, 0x0d);
    outp(0x3d5, (char)start_addr & 0xff);
    while (!(inp(0x3da) & 8))
        ;
    inp(0x3da);
    outp(0x3c0, 0x13);
    outp(0x3c0, (char)pan);
    outp(0x3c0, 0x20);
    if (set_split != 0) {
        outpw(0x3d4, (screen_width * g_nVgaScrollPageCount / 2) * 0x100 + 0x13);
    }
}

void far scrolltrans_planar_blit_pageflip(int direction, int x_off, int y, int screen_width) {
    uchar far *dst;
    uchar far *src;

    src = g_pVgaScrollScratchBuf + x_off / (0x140 / screen_width) + y * screen_width;
    dst = (uchar far *)((unsigned long)((long)(int)g_graphics_context.wVgaFrontPageBase) << 16);

    outpw(0x3c4, 0xf02);
    outpw(0x3ce, g_graphics_context.bVideoAdapter == '\b' ? 0x4105 : 0x105);

    for (y = 200; y != 0; y--) {
        for (x_off = screen_width; x_off != 0; x_off--) {
            *dst++ = *src++;
        }
        if (direction >= 2) {
            src += screen_width * (g_nVgaScrollPageCount - 1);
        }
    }

    outpw(0x3ce, g_graphics_context.bVideoAdapter == '\b' ? 0x4005 : 5);

    while (inp(0x3da) & 8)
        ;

    {
        int crtc_val = (g_graphics_context.wVgaFrontPageBase - 0xa000) << 4;
        outp(0x3d4, 0xc);
        outp(0x3d5, (char)(crtc_val >> 8));
        outp(0x3d4, 0xd);
        outp(0x3d5, (char)(crtc_val & 0xff));
    }

    while (!(inp(0x3da) & 8))
        ;
    inp(0x3da);

    outp(0x3c0, 0x13);
    outp(0x3c0, 0);
    outp(0x3c0, 0x20);

    if (direction >= 2) {
        outpw(0x3d4, (screen_width / 2) * 0x100 + 0x13);
    }

    g_graphics_context.wGfxBlitSrcPage = g_nVgaScrollPageCount > 2
                                             ? g_graphics_context.wVgaFrontPageBase
                                             : g_graphics_context.wVgaPage2Base;
    g_graphics_context.wGfxBlitDstPage = g_graphics_context.wVgaPage1Base;
    gfx_present_dispatch(0, 0, 0x140, 200);
    g_graphics_context.wGfxBlitSrcPage = g_graphics_context.wVgaFrontPageBase;
    g_graphics_context.wGfxBlitDstPage = g_graphics_context.wVgaPage2Base;
    gfx_present_dispatch(0, 0, 0x140, 200);
}
