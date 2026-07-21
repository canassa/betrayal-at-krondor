#include "structs.h"
#include "globals.h"
extern void bookview_init(void);
extern void bookview_shutdown(void);
extern int bookview_show(char *filename, int page_number);
extern BookPage far *bookview_find_page_by_number(PageDirectory far *page_directory,
                                                  int page_number);

BookViewerState *g_pBookViewer;

unsigned short g_wTextWrapXAccum = 0x0000;
unsigned short g_wTextWrapLinesDrawn = 0x0000;
unsigned short g_wTextWrapLinesRemaining = 0x0000;

extern void *calloc(unsigned nitems, unsigned size);
extern void free(void *block);

#include "SRC/STREAM/RESLOAD/FONTLOAD.H"
#include "SRC/SYS/EMS.H"
#include "SRC/IO/IO.H"
#include "SRC/IO/IOCHUNK.H"
#include "SRC/STREAM/CODEC/STREAM.H"
#include "SRC/GAME/BOOT.H"
#include "SRC/GFX/DRIVER/VTHUNKS.H"
#include "SRC/GFX/SPRITE/BLITCHNK.H"
#include "SRC/STREAM/RESLOAD/IMGLOAD.H"
#include "SRC/GFX/DRIVER/PALDRV.H"
#include "SRC/SYS/DOSMEM.H"
#include "SRC/SCREENS/BOOKTEXT.H"
#include "SRC/GFX/PALETTE/PALETTE.H"
#include "SRC/INPUT/KEYBOARD.H"
#include "SRC/GFX/RASTER/PRESENT.H"
#include "SRC/GFX/SCREEN/SCREEN.H"
#include "SRC/AUDIO/ENGINE/AUDIO.H"
#include "SRC/INPUT/MOUSE.H"
#include "SRC/INPUT/JOYSTICK.H"

void bookview_init(void) {
    BakFile *file;
    int stream;
    uchar far *p;
    int row;
    int stride;

    g_pBookViewer = (BookViewerState *)calloc(1, 100);
    g_pBookViewer->pFontSlots[1] = font_load("BOOK.FNT");
    g_pBookViewer->nEmsPage0 = ems_alloc_pages(0xffffL);
    g_pBookViewer->nEmsPage1 = ems_alloc_pages(0xffffL);
    if ((file = bak_fopen("BOOK.SCX", "rb")) != 0) {
        if ((stream = stream_open(-1, file, "r", 0xcd2dL)) != -1) {
            p = ems_map_resource_pages(g_pBookViewer->nEmsPage0);
            stream_read(stream, p, 56000U);
            p = ems_map_resource_pages(g_pBookViewer->nEmsPage1);
            stream_read(stream, p, 56000U);
            stream_close(stream);
        }
        bak_fclose(file);
    }
    boot_video_init_for_mode(1);
    g_graphics_context.wGfxBlitSrcPage = g_graphics_context.wGfxBlitDstPage =
        g_graphics_context.wVgaPage2Base;

    p = ems_map_resource_pages(g_pBookViewer->nEmsPage0);
    row = 0;
    do {
        blit_chunky(p, 0, row, 0x280, 1);
        row++;
        p += 0x140;
    } while (row < 0xaf);

    p = ems_map_resource_pages(g_pBookViewer->nEmsPage1);
    row = 0xaf;
    while (row < 0x15e) {
        blit_chunky(p, 0, row, 0x280, 1);
        row++;
        p += 0x140;
    }

    stride = (int)rect_byte_size(0x280, 1) + 8;

    p = ems_map_resource_pages(g_pBookViewer->nEmsPage0);
    row = 0;
    do {
        cga_save_rect_to_buffer(p, 0, row, 0x27f, 1);
        row++;
        p += stride;
    } while (row < 0xaf);

    p = ems_map_resource_pages(g_pBookViewer->nEmsPage1);
    row = 0xaf;
    while (row < 0x15e) {
        cga_save_rect_to_buffer(p, 0, row, 0x27f, 1);
        row++;
        p += stride;
    }

    g_pBookViewer->pImageRecord = (ImageRecord **)bak_load_image_record_chunked("BOOK.BMX");
    g_pBookViewer->pPalette = chunk_load_into_slot("BOOK.PAL");
}

void bookview_shutdown(void) {
    cache_release(g_pBookViewer->pPalette);
    free_image_record(g_pBookViewer->pImageRecord);
    boot_video_init_for_mode(0);
    ems_free_pages(g_pBookViewer->nEmsPage1);
    ems_free_pages(g_pBookViewer->nEmsPage0);
    font_unload(g_pBookViewer->pFontSlots[1]);
    free(g_pBookViewer);
    g_pBookViewer = (BookViewerState *)0x0;
    return;
}

static PageDirectory far *bookview_load_page_directory(char *filename) {
    PageDirectory far *dir;
    ulong size;
    BakFile *stream;
    int i;

    stream = bak_fopen(filename, "rb");
    if (!stream) {
        return (PageDirectory far *)0;
    }
    bak_fread(&size, 1, 4, stream);
    dir = (PageDirectory far *)alloc_far(size, 0L);
    bak_fread_chunked((uchar huge *)dir, 1L, (long)size, stream);
    bak_fclose(stream);
    for (i = 0; i < dir->nCount; i++) {
        dir->pPages[i] = (BookPage far *)((char huge *)dir + (ulong)dir->pPages[i]);
    }
    return dir;
}

static void bookview_freemem_if_not_null(uchar far *ptr) {
    if ((ulong)ptr != 0) {
        _freemem(ptr);
    }
    return;
}

BookPage far *bookview_find_page_by_number(PageDirectory far *page_directory, int page_number) {
    int i;

    for (i = 0; page_directory->nCount > i; i++) {
        if (page_directory->pPages[i]->wPageNumber == page_number)
            return page_directory->pPages[i];
    }
    return (BookPage far *)0L;
}

int bookview_show(char *filename, int page_number) {
    int firstPage;
    int needRender;
    PageDirectory far *dir;
    BookPage far *page;
    BookPage far *next;
    register int i;
    register int rc;

    firstPage = 1;
    needRender = 1;
    rc = 0;
    if ((dir = bookview_load_page_directory(filename)) != 0) {
        if (page_number <= 0) {
            page = dir->pPages[0];
        } else {
            page = bookview_find_page_by_number(dir, page_number);
        }
        if (page == 0) {
        set_rc_terminate:
            rc = 1;
        }
        while (rc == 0) {
            if (needRender) {
                needRender = 0;
                g_graphics_context.wGfxBlitDstPage = g_graphics_context.wVgaPage2Base;
                booktext_render_page(dir, page, page->w_pad12 == 0);
                palette_set(g_pBookViewer->pPalette);
                if (firstPage) {
                    firstPage = 0;
                    palette_set_scaled(0, 0x10, 0, 0);
                    vsync_hook(1);
                    for (i = 2; i < 0x40; i += 2) {
                        palette_set_scaled(0, 0x10, 0, i);
                    }
                    g_nFrameTickCountdown = 5;
                    while (g_nFrameTickCountdown != 0) {
                        if (kbhit_read() >> 8 != 0) {
                            g_nFrameTickCountdown = 5;
                        }
                    }
                } else {
                    vsync_hook(1);
                }
                g_graphics_context.wGfxBlitSrcPage = g_graphics_context.wVgaFrontPageBase;
                g_graphics_context.wGfxBlitDstPage = g_graphics_context.wVgaPage2Base;
                gfx_present_dispatch(0, 0, 0x280, 0x15e);
                screen_cursor_hide();

                if (page->wDisplayNumber == 0x1d5) {
                    audio_music_play(0x425);
                } else if (page->wDisplayNumber == 0x1dc) {
                    audio_music_play(0x411);
                }
            }
            do {
                if (kbhit_read() >> 8 != 0 ||
                    (g_mouse_installed != 0 &&
                     (mouse_button_pressed(0) != 0 || mouse_button_pressed(1) != 0))) {
                    break;
                }
            } while (g_bJoystick0Installed == 0 ||
                     (joystick_button_pressed(0) == 0 && joystick_button_pressed(1) == 0));
            while ((g_mouse_installed != 0 &&
                    (mouse_button_pressed(0) != 0 || mouse_button_pressed(1) != 0)) ||
                   (g_bJoystick0Installed != 0 &&
                    (joystick_button_pressed(0) != 0 || joystick_button_pressed(1) != 0))) {
            }
            if ((short)page->wNextPageNumber == -2 ||
                (page->wNextPageNumber == page->wPagePointer && g_pBookViewer->nTerminate != 0)) {
                goto set_rc_terminate;
            }
            if ((next = bookview_find_page_by_number(dir, page->wNextPageNumber)) != 0) {
                page = next;
                needRender = 1;
            }
        }
    }
    if (dir != 0) {
        for (i = 0x3e; i >= 0; i -= 2) {
            palette_set_scaled(0, 0x10, 0, i);
        }
        bookview_freemem_if_not_null((uchar far *)dir);
        return rc;
    }
    return 0;
}
