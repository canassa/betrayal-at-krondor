#include "structs.h"
#include "SRC/GEN/GFXCTX.H"
#include "SRC/SCREENS/BOOKTEXT.H"
#include "SRC/GFX/FONT/FONT.H"
#include "SRC/GFX/DRIVER/VTHUNKS.H"
#include "SRC/GFX/DRIVER/VIDINIT.H"
#include "SRC/STREAM/RESLOAD/IMGLOAD.H"
#include "SRC/GFX/SPRITE/SPRTHNKS.H"
#include "SRC/SYS/EMS.H"
#include "SRC/SCREENS/BOOKVIEW.H"


char g_szRomanDigits[7] = "MDCLXVI";
short g_anRomanValues[7] = {1000, 500, 100, 50, 10, 5, 1};
short g_anRomanSubPair[7] = {100, 100, 10, 10, 1, 1, 0};

struct BookStyleBlock {
    short nFontSlot;
    short nBaselineYOff;
    short nFgColor;
    short nBgColor;
    unsigned short wStyleFlags;
};

struct BookLayoutHdr {
    short nMarginTop;
    short nMarginBottom;
    short nLineHeight;
    short nVStepIndent;
    short nVStepWrap;
    short nVStepRetract;
    short nVStepUndo;
    unsigned short wAlignment;
};

typedef struct {
    unsigned char b[16];
} Block16;
typedef struct {
    unsigned char b[10];
} Block10;

static void bookview_render_hook_noop(BookPage far *page) {
    return;
}

static void bookview_text_render_hook_noop(int nXHint) {
    return;
}

static void booktext_font_select(int slot) {
    if ((slot != 0) && (g_pBookViewer->pFontSlots[slot] != 0)) {
        font_activate(g_pBookViewer->pFontSlots[slot]);
    }
    return;
}

int booktext_layout_next_run(BookPage far *page, int y0, int y1, int y_bot) {
    int avail;
    BookReservedRect far *r;
    BookPage far *pPage;
    int xMin;
    int xMax;
    register int i;

    pPage = page;
    xMin = pPage->rect.x + g_pBookViewer->nMarginTop;
    xMax = (pPage->rect.x + pPage->rect.width) - g_pBookViewer->nMarginBottom;
    avail = 0;
    while (!avail) {
        r = (BookReservedRect far *)(page + 1);
        avail = 1;
        if (y0 < xMin) {
            y0 = xMin;
        }
        if (y0 > xMax) {
            y0 = xMin;
            y1 += g_pBookViewer->nLineHeight;
            y_bot += g_pBookViewer->nLineHeight;
            if (pPage->rect.y + pPage->rect.height + -1 <= y_bot) {
                return 0;
            }
        }
        for (i = 0; i < (int)page->wReservedCount; i++, r++) {
            if ((((r->y0 < y1) && (y1 < r->y1)) || ((r->y0 < y_bot) && (y_bot < r->y1))) &&
                ((r->x0 <= y0) && (y0 <= r->x1))) {
                y0 = r->x1 + 1;
                i = 999;
                avail = 0;
            }
        }
    }
    r = (BookReservedRect far *)(page + 1);
    avail = xMax - y0;
    for (i = 0; i < (int)page->wReservedCount; i++, r++) {
        if ((((r->y0 < y1) && (y1 < r->y1)) || ((r->y0 < y_bot) && (y_bot < r->y1))) &&
            ((y0 < r->x0) && (r->x0 - y0 < avail))) {
            avail = r->x0 - y0;
        }
    }
    g_pBookViewer->nCursorX = y0;
    g_pBookViewer->nLineY1 = y1;
    g_pBookViewer->nLineHeightActual = avail;
    g_pBookViewer->nLineYNext = y0 + avail + 1;
    return 1;
}

static void booktext_compute_justify_spacing(int remaining_pixels) {
    unsigned char huge *pCur;
    int spaces;
    int chars;
    int rem;

    spaces = 0;
    chars = 0;
    pCur = g_pBookViewer->pCurChar;

    while (g_pBookViewer->pBreakSave >= pCur) {
        if (((char)*pCur & 0xf0) == 0xf0) {
            switch ((char)*pCur & 0xf) {
            case 4:
                pCur += 0xb;
                break;
            case 1:
                pCur += 0x11;
                break;
            case 3:
                pCur += 3;
                break;
            }
        } else {
            if (*pCur == 0x20) {
                spaces++;
            } else {
                chars++;
            }
            pCur += 1;
        }
    }

    g_pBookViewer->nSpaceExtra = 0;
    g_pBookViewer->nSpaceExtraStep = 30000;
    g_pBookViewer->nCharExtra = 0;
    g_pBookViewer->nCharExtraStep = 30000;
    if (g_pBookViewer->nJustifyOn == 0) {
        return;
    }
    if (spaces != 0) {
        g_pBookViewer->nSpaceExtra = remaining_pixels / spaces;
        rem = remaining_pixels % spaces;
        if (rem != 0) {
            g_pBookViewer->nSpaceExtraStep = (spaces * 0x32) / rem;
        }
    }
    if (g_pBookViewer->nSpaceExtra > 10 || spaces == 0) {
        if (g_pBookViewer->nSpaceExtra > 10) {
            g_pBookViewer->nSpaceExtra = 10;
            g_pBookViewer->nSpaceExtraStep = 30000;
        }
        remaining_pixels -= g_pBookViewer->nSpaceExtra * spaces;
        if (--chars > 0) {
            g_pBookViewer->nCharExtra = remaining_pixels / chars;
            rem = remaining_pixels % chars;
            if (rem != 0) {
                g_pBookViewer->nCharExtraStep = (chars * 0x32) / rem;
            }
        }
    }
    g_pBookViewer->nCharExtraCount = g_pBookViewer->nCharExtraStep;
    g_pBookViewer->nSpaceExtraCount = g_pBookViewer->nSpaceExtraStep;
}

static int booktext_draw_glyph_kerned(char ch, int x, int y) {
    unsigned int width;
    unsigned int height;

    font_render_glyph_or_ctrl(ch, x, y + g_pBookViewer->nBaselineYOff);
    font_glyph_metrics(ch, &width, &height);

    x += (int)(width + (g_pBookViewer->wStyleFlags & 2));

    if (g_pBookViewer->nJustifyOn != 0) {
        if (ch == ' ') {
            x += g_pBookViewer->nSpaceExtra;
            if ((g_pBookViewer->nSpaceExtraCount -= 50) < 0) {
                x++;
                g_pBookViewer->nSpaceExtraCount = g_pBookViewer->nSpaceExtraStep;
            }
        } else {
            x += g_pBookViewer->nCharExtra;
            if ((g_pBookViewer->nCharExtraCount -= 50) < 0) {
                x++;
                g_pBookViewer->nCharExtraCount = g_pBookViewer->nCharExtraStep;
            }
        }
    }

    return x;
}

static void booktext_render_line_aligned(void) {
    unsigned char huge *pCur;
    int wordHook;
    unsigned int alignment;
    int slack;

    wordHook = 0;
    alignment = g_pBookViewer->wAlignment;
    slack = g_pBookViewer->nLineHeightActual - g_pBookViewer->nLineWidthCur;
    pCur = g_pBookViewer->pCurChar;

    if (alignment == 3) {
        booktext_compute_justify_spacing(slack);
    } else {
        g_pBookViewer->nJustifyOn = 0;
        if (alignment == 4) {
            g_pBookViewer->nCursorX += slack / 2;
        } else if (alignment == 2) {
            g_pBookViewer->nCursorX += slack;
        }
    }

    booktext_font_select(g_pBookViewer->nFontSlot);
    g_graphics_context.bText_style_flags = (unsigned char)g_pBookViewer->wStyleFlags;

    while (g_pBookViewer->pBreakSave >= pCur) {
        if (((char)*pCur & 0xf0) == 0xf0) {
            switch ((char)*pCur & 0xf) {
            case 4:
                *(struct BookStyleBlock *)&g_pBookViewer->nFontSlot =
                    *(struct BookStyleBlock huge *)(pCur + 1);
                booktext_font_select(g_pBookViewer->nFontSlot);
                g_graphics_context.bText_fg_color = (unsigned char)g_pBookViewer->nFgColor;
                g_graphics_context.bText_bg_color = (unsigned char)g_pBookViewer->nBgColor;
                g_graphics_context.bText_style_flags = (unsigned char)g_pBookViewer->wStyleFlags;
                pCur += 0xb;
                break;
            case 1:
                pCur += 0x11;
                break;
            case 3:
                wordHook = *(int huge *)(pCur + 1) + 0x80;
                pCur += 3;
                bookview_text_render_hook_noop(wordHook);
                break;
            }
        } else {
            if (wordHook != 0) {
                bookview_text_render_hook_noop(wordHook);
                if (*pCur == ' ' || *pCur == '-' || *pCur == '.' || *pCur == '"' || *pCur == '\n' ||
                    *pCur == '\r') {
                    wordHook = 0;
                }
            }
            g_pBookViewer->nCursorX =
                booktext_draw_glyph_kerned(*pCur, g_pBookViewer->nCursorX, g_pBookViewer->nLineY1);
            pCur += 1;
        }
    }
}

int booktext_is_break_char(char c) {
    return (c == '-' || c == '.' || c == '\n' || c == '\r') ? 1 : 0;
}

static int booktext_layout_rndr_one_line(BookPage far *pPage) {
    unsigned char huge *pCur;
    int xCur;
    int done;
    int firstRun;
    unsigned int width;
    unsigned int height;
    struct BookStyleBlock style;

    pCur = g_pBookViewer->pCurChar;
    firstRun = 0;
    done = 0;
    xCur = 0;
    style = *(struct BookStyleBlock huge *)&g_pBookViewer->nFontSlot;
    g_pBookViewer->nJustifyOn = 1;
    g_pBookViewer->nLineWidthCur = 0;
    g_pBookViewer->pBreakSave = pCur;

    while (!done) {
        if (((char)*pCur & 0xf0) == 0xf0) {
            switch ((char)*pCur & 0xf) {
            case 4:
                style = *(struct BookStyleBlock huge *)(pCur + 1);
                booktext_font_select(style.nFontSlot);
                pCur += 0xb;
                continue;
            case 1:
                if (firstRun != 0)
                    goto break_and_finish;
                do {
                    if (booktext_layout_next_run(
                            pPage, g_pBookViewer->nLineYNext, g_pBookViewer->nLineY1,
                            g_pBookViewer->nLineY1 + g_pBookViewer->nLineHeight) == 0)
                        return 0;
                } while (g_pBookViewer->nLineHeightActual < 0xf);
                *(struct BookLayoutHdr *)g_pBookViewer = *(struct BookLayoutHdr huge *)(pCur + 1);
                g_pBookViewer->nCursorX = g_pBookViewer->nLineYNext =
                    pPage->rect.x + g_pBookViewer->nMarginTop + g_pBookViewer->nVStepWrap;
                g_pBookViewer->nLineY1 += g_pBookViewer->nVStepIndent;
                g_pBookViewer->nCursorX += g_pBookViewer->nVStepRetract;
                g_pBookViewer->nLineY1 += g_pBookViewer->nVStepUndo;
                pCur += 0x11;
                continue;
            case 3:
                pCur += 3;
                continue;
            case 0:
                g_pBookViewer->nTerminate = 1;
                if (firstRun == 0)
                    return 0;
            break_and_finish:
                done = 1;
                g_pBookViewer->nJustifyOn = 0;
                g_pBookViewer->pBreakSave = pCur - 1;
                g_pBookViewer->nLineWidthCur = xCur;
                continue;
            }
            continue;
        }

        if (firstRun == 0) {
            firstRun = 1;
            do {
                if (booktext_layout_next_run(
                        pPage, g_pBookViewer->nLineYNext, g_pBookViewer->nLineY1,
                        g_pBookViewer->nLineY1 + g_pBookViewer->nLineHeight) == 0)
                    return 0;
            } while (g_pBookViewer->nLineHeightActual < 0xf);
        }

        font_glyph_metrics((char)*pCur, &width, &height);
        xCur += (int)(width + (style.wStyleFlags & 2));
        if (g_pBookViewer->nLineHeightActual < xCur)
            done = 1;

        if (!done) {
            if (*(pCur + 1) == ' ' && *pCur != ' ') {
                g_pBookViewer->pBreakSave = pCur;
                g_pBookViewer->nLineWidthCur = xCur;
            } else if (booktext_is_break_char(*pCur) && booktext_is_break_char(*(pCur + 1)) == 0) {
                g_pBookViewer->pBreakSave = pCur;
                g_pBookViewer->nLineWidthCur = xCur;
            }
            if (*pCur == '\n')
                g_pBookViewer->nJustifyOn = 0;
        }
        pCur += 1;
    }

    pCur = (unsigned char huge *)(g_pBookViewer->pResumeSave =
                                      (unsigned char far *)(g_pBookViewer->pBreakSave + 1));
    while (*pCur == ' ') {
        pCur += 1;
        g_pBookViewer->pResumeSave = (unsigned char far *)pCur;
    }
    return 1;
}

static void booktext_int_to_roman(char *out, int value) {
    int i;
    int j;

    while (value != 0) {
        for (i = 0; i < 7; i++) {
            if (g_anRomanValues[i] <= value) {
                *out++ = g_szRomanDigits[i];
                value -= g_anRomanValues[i];
                break;
            }
            if (g_anRomanSubPair[i] != 0 && g_anRomanValues[i] - g_anRomanSubPair[i] <= value) {
                for (j = 6; j > i; j--) {
                    if (g_anRomanValues[i] - g_anRomanValues[j] <= value) {
                        *out++ = g_szRomanDigits[j];
                        value += g_anRomanValues[j];
                        break;
                    }
                }
                break;
            }
        }
    }
    *out = '\0';
}

static void booktext_draw_page_number(BookPage far *page) {
    int saved_fg;
    int saved_style;
    int width;
    char roman[30];
    unsigned short value;
    int y;

    saved_fg = (char)g_graphics_context.bText_fg_color;
    saved_style = (char)g_graphics_context.bText_style_flags;
    g_graphics_context.bText_fg_color = 0;
    g_graphics_context.bText_style_flags = 1;
    booktext_font_select(1);
    if ((page->wShowPageNumber & 1) != 0) {
        value = page->wDisplayNumber;
        y = g_wScreen_height + -0x13;
        booktext_int_to_roman(roman, value);
        width = font_text_width_ds(roman);
        if ((int)value % 2 != 0) {
            font_draw_text_ds(roman, ((page->rect.x + page->rect.width) - width) + -2, y);
        } else {
            font_draw_text_ds(roman, page->rect.x + 2, y);
        }
    }
    g_graphics_context.bText_fg_color = (unsigned char)saved_fg;
    g_graphics_context.bText_style_flags = (unsigned char)saved_style;
    return;
}

static unsigned char far *booktext_page_entry_offset(BookPage far *page) {
    char far *p;

    p = (char far *)page + page->wReservedCount * sizeof(BookReservedRect) + (int)sizeof(BookPage);
    p = p + page->wImageCount * sizeof(BookImage);
    return (unsigned char far *)p;
}

int booktext_render_page(PageDirectory far *page_directory, BookPage far *page, int redraw_bg) {
    BookPage far *pageFirst;
    BookImage far *pImg;
    unsigned char far *pRes;
    register int result;
    register int i;

    result = 1;
    pageFirst = page;

    if (redraw_bg) {
        unsigned char far *pSrc;
        int rowStride;
        int rowBias;
        int rowStep;

        if ((short)page->wPageNumber % 2 != 0) {
            rowBias = 0x15d;
            rowStep = -1;
        } else {
            rowBias = 0;
            rowStep = 1;
        }

        rowStride = (int)rect_byte_size(0x280, 1) + 8;

        pSrc = ems_map_resource_pages(g_pBookViewer->nEmsPage0);
        i = 0;
        do {
            cga_rect_paste_from_buffer(pSrc, 0, i * rowStep + rowBias, 0x27f, 1);
            i++;
            pSrc += rowStride;
        } while (i < 0xaf);

        pSrc = ems_map_resource_pages(g_pBookViewer->nEmsPage1);
        i = 0xaf;
        while (i < 0x15e) {
            cga_rect_paste_from_buffer(pSrc, 0, i * rowStep + rowBias, 0x27f, 1);
            i++;
            pSrc += rowStride;
        }
    }

    g_graphics_context.bClip_enabled = 1;
    booktext_draw_page_number(page);
    bookview_render_hook_noop(page);

    do {
        g_graphics_context.bGfx_fill_enabled = 0;

        i = 0;
        pRes = (unsigned char far *)page + sizeof(BookPage);
        while ((short)page->wReservedCount > i) {
            i++;
            pRes += sizeof(BookReservedRect);
        }

        i = 0;
        pImg = (BookImage far *)pRes;
        while ((short)page->wImageCount > i) {
            if (null_terminated_count(g_pBookViewer->pImageRecord) > (short)pImg->wImage) {
                blit_sprite_indirect((unsigned short)g_pBookViewer->pImageRecord[pImg->wImage], pImg->nX,
                                     pImg->nY, pImg->wMirroring);
            }
            i++;
            pImg++;
        }

        g_pBookViewer->nTerminate = 0;
        g_pBookViewer->nCursorX = g_pBookViewer->nLineYNext = pageFirst->rect.x;
        g_pBookViewer->nLineY1 = pageFirst->rect.y;

        if ((*(int far *)&page->pReserved[0] | *(int far *)&page->pReserved[2]) != 0) {

            g_pBookViewer->pCurChar = *(unsigned char far *far *)&page->pReserved[0];
            *(Block16 *)&g_pBookViewer->nMarginTop = *(Block16 far *)&page->pReserved[4];
            *(Block10 *)&g_pBookViewer->nFontSlot = *(Block10 far *)&page->pReserved[20];
            booktext_font_select(g_pBookViewer->nFontSlot);
            g_graphics_context.bText_style_flags = (unsigned char)g_pBookViewer->wStyleFlags;
        } else {
            g_pBookViewer->pCurChar = booktext_page_entry_offset(page);
        }

        g_graphics_context.bClip_enabled = 0;
        g_pBookViewer->nCursorX = g_pBookViewer->nLineYNext = pageFirst->rect.x;
        g_pBookViewer->nLineY1 = pageFirst->rect.y;

        while (booktext_layout_rndr_one_line(page)) {
            booktext_render_line_aligned();
            g_pBookViewer->pCurChar = g_pBookViewer->pResumeSave;
            g_pBookViewer->nCursorX = g_pBookViewer->nLineYNext;
        }

        if ((short)page->wPagePointer >= 0) {
            BookPage far *pNext;

            pNext = bookview_find_page_by_number(page_directory, page->wPagePointer);
            if (pNext != 0) {

                *(unsigned char far *far *)&pNext->pReserved[0] = g_pBookViewer->pResumeSave;
                *(Block10 far *)&pNext->pReserved[20] = *(Block10 *)&g_pBookViewer->nFontSlot;
                *(Block16 far *)&pNext->pReserved[4] = *(Block16 *)&g_pBookViewer->nMarginTop;
            }
            if (g_pBookViewer->nTerminate != 0) {
                result = 0;
            }
            if (page->w_pad12 != 0) {
                page = pNext;
            } else {
                page = 0;
            }
        } else {
            page = 0;
        }
    } while (page != 0 && result != 0);

    return result;
}
