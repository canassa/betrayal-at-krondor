#include "globals.h"
#include "SRC/GAME/GMAIN.H"
#include "SRC/GEN/GFXCTX.H"
#include "SRC/WORLD/ZONE/ZONE.H"
#include "SRC/COMBAT/GRID/CMBTGRID.H"
#include "SRC/SYS/SYSLOWIO.H"
#include "SRC/WORLD/ZONE/CZONE.H"
#include "structs.h"
#include "SRC/SCREENS/FMAP.H"
#include "SRC/IO/IO.H"
#include "SRC/SYS/MEM.H"
#include "SRC/GFX/PALETTE/PALCYC.H"
#include "SRC/GFX/FONT/FONT.H"
#include "SRC/GFX/SPRITE/RESBLIT.H"
#include "SRC/GFX/DRIVER/PALDRV.H"
#include "SRC/GFX/RASTER/PRESENT.H"
#include "SRC/GFX/DRIVER/VTHUNKS.H"
#include "SRC/SYS/DOSMEM.H"
#include "SRC/GFX/DRIVER/VIDINIT.H"
#include "SRC/STREAM/RESLOAD/IMGLOAD.H"
#include "SRC/GFX/SPRITE/SPRTHNKS.H"
#include "SRC/GFX/SCREEN/SCREEN.H"
#include "SRC/UI/MENUPAGE.H"
#include "SRC/GFX/PALETTE/PALETTE.H"
#include "SRC/DIALOG/DIALOG.H"
#include "SRC/R3D/CORE/R3D.H"

unsigned short g_wFmapMapWidth;
unsigned short g_wFmapMapHeight;
unsigned short g_wFmapHotspotW;
unsigned short g_wFmapHotspotH;
unsigned short g_wFmapTownCount;
unsigned short g_wFmapLabelRectW;
unsigned short g_wFmapLabelRectH;
unsigned char far *g_pFmapLabelRectBuf;

ImageRecord **g_pFmapIconTable = {0};
unsigned short *g_pFmapTownXCoords = {0};
unsigned short *g_pFmapTownYCoords = {0};
unsigned short *g_pFmapTownLabels = {0};

void far fmap_screen_run(void) {
    int curTown;
    int pasteCounter;
    unsigned short savedBlendMode;
    unsigned char far *savedPal;
    unsigned char far *palBuf;
    MenuPage *page;
    int running;
    int needFullRedraw;
    unsigned short menuConsumed;
    int redrawMenuCounter;
    int needSaveRect;
    int drawLabelCounter;
    int haveHover;
    int prevTown;
    int prevLabelX;
    int prevLabelY;
    int labelX;
    int labelY;
    int haveMarker;
    int markerX;
    int markerY;
    int iconBase;
    int animFrame;
    unsigned long lastTick;
    unsigned int action;
    int heading;

    running = 1;
    needFullRedraw = 1;
    menuConsumed = 0;
    redrawMenuCounter = 0;
    pasteCounter = 0;
    needSaveRect = 0;
    drawLabelCounter = 0;
    haveHover = 0;
    curTown = -1;
    prevLabelX = 0;
    prevLabelY = 0;
    labelX = 0;
    labelY = 0;
    haveMarker = 0;
    animFrame = 0;
    lastTick = 0;
    palette_cycle_eb_toggle(0);
    fmap_twn_load();
    page = menupage_load("req_fmap.dat");
    menupage_begin(page);
    if (fmap_xy_lookup_for_chapter(&markerX, &markerY) != 0) {
        heading = g_world_camera->base.orientation.yaw;
        fmap_farptr_normalize(&heading);
        iconBase = ((unsigned short)heading >> 13) << 2;
        haveMarker = 1;
    }
    while (running != 0) {
        if (needFullRedraw != 0) {
            screen_cursor_show_busy();
            palette_fade_out(0, 0x100, -1, 0);
            screen_cursor_restore_shape();
            screen_cursor_hide();
            palette_screen_clear_black();
            savedBlendMode = g_nPalBlendMode;
            g_nPalBlendMode = 0;
            savedPal = palette_set((unsigned char far *)0x0);
            palBuf = chunk_load_into_slot("fullmap.pal");
            g_pPalQueuedForFlip = palBuf;
            screen_frame_flip();
            palette_set_scaled(0, 0x100, 0, 0);
            screen_cursor_show_busy();
            g_graphics_context.wGfxBlitDstPage = g_graphics_context.wGfxBlitSrcPage =
                g_graphics_context.wVgaPage2Base;
            resblit_load_pal_or_stream("fullmap.scr");
            if (haveMarker != 0) {
                blit_sprite_indirect((unsigned short)g_pFmapIconTable[iconBase], markerX - 3, markerY - 3,
                                     0);
            }
            menupage_draw(page);
            screen_cursor_restore_shape();
            screen_frame_flip();
            g_graphics_context.wGfxBlitSrcPage = g_graphics_context.wVgaFrontPageBase;
            g_graphics_context.wGfxBlitDstPage = g_graphics_context.wVgaPage2Base;
            gfx_present_dispatch(0, 0, 0x140, 200);
            screen_cursor_hide();
            screen_cursor_show_busy();
            palette_fade_in(0, 0x100, -1, 0);
            screen_cursor_restore_shape();
            needFullRedraw = 0;
            menuConsumed = 0;
            redrawMenuCounter = 0;
        } else {
            g_graphics_context.wGfxBlitDstPage = g_graphics_context.wGfxBlitSrcPage =
                g_graphics_context.wVgaPage2Base;
            g_graphics_context.clip.ymin = g_graphics_context.clip.xmin = 0;

            g_graphics_context.clip.xmax = 0x13f;
            g_graphics_context.clip.ymax = 199;
            g_graphics_context.bClip_enabled = '\x01';
            if (pasteCounter != 0) {
                cga_rect_paste_from_buffer(g_pFmapLabelRectBuf, prevLabelX, prevLabelY,
                                           g_wFmapLabelRectW, g_wFmapLabelRectH);
                pasteCounter--;
            }
            if (haveMarker != 0) {
                if (lastTick + 6 <= g_timer_ticks) {
                    lastTick = g_timer_ticks;
                    animFrame++;
                    animFrame = (short)animFrame % 4;
                }
                blit_sprite_indirect((unsigned short)g_pFmapIconTable[iconBase + animFrame], markerX - 3,
                                     markerY - 3, 0);
            }
            if ((pasteCounter == 0) && (needSaveRect != 0)) {
                cga_save_rect_to_buffer(g_pFmapLabelRectBuf, labelX, labelY, g_wFmapLabelRectW,
                                        g_wFmapLabelRectH);
                needSaveRect = 0;
            }
            if (drawLabelCounter != 0) {
                g_graphics_context.bText_style_flags = '\x01';
                g_graphics_context.bText_fg_color = '\0';
                font_draw_text_ds((char *)g_pFmapTownLabels[curTown], labelX, labelY);
                drawLabelCounter--;
            }
            if (redrawMenuCounter != 0) {
                menupage_draw(page);
                redrawMenuCounter--;
            }
            screen_frame_present();
        }
        action = menupage_run(page, &menuConsumed);
        if (menuConsumed != 0) {
            redrawMenuCounter = 2;
            menuConsumed = 0;
        }
        if (((pasteCounter == 0) && (needSaveRect == 0)) && (drawLabelCounter == 0)) {
            prevTown = curTown;
            curTown = fmap_hit_test_cursor();
            if (curTown != -1) {
                if (haveHover != 0) {
                    if (prevTown != curTown) {
                        prevLabelX = labelX;
                        prevLabelY = labelY;
                        labelX = (int)g_pFmapTownXCoords[curTown] + ((short)g_wFmapMapWidth >> 1) -
                                 (font_text_width_ds((char *)g_pFmapTownLabels[curTown]) >> 1);
                        labelY = g_pFmapTownYCoords[curTown] - g_wFmapLabelRectH;
                        pasteCounter = 2;
                        needSaveRect = 1;
                        drawLabelCounter = 2;
                    } else {
                        drawLabelCounter = 2;
                    }
                } else {
                    labelX = (int)g_pFmapTownXCoords[curTown] + ((short)g_wFmapMapWidth >> 1) -
                             (font_text_width_ds((char *)g_pFmapTownLabels[curTown]) >> 1);
                    labelY = g_pFmapTownYCoords[curTown] - g_wFmapLabelRectH;
                    needSaveRect = 1;
                    drawLabelCounter = 2;
                    haveHover = 1;
                }
            } else if (haveHover != 0) {
                prevLabelX = labelX;
                prevLabelY = labelY;
                pasteCounter = 2;
                haveHover = 0;
            }
        }
        if (action == 0x12) {
            if (menupage_state_0e7c() == 2) {
                dialog_play_record(0x80, 1);
                continue;
            }
            running = 0;
        } else if (action != 1) {
            continue;
        } else {
            running = 0;
        }
    }
    screen_cursor_hide();
    menupage_end(page);
    menupage_free(page);
    cache_release(palBuf);
    g_nPalBlendMode = savedBlendMode;
    g_pPalQueuedForFlip = savedPal;
    fmap_hotspots_unload();
}

void fmap_twn_load(void) {
    BakFile *stream;
    unsigned short *labelPtr;
    int i;
    unsigned short *xPtr;
    unsigned short *yPtr;
    unsigned short len;

    g_wFmapLabelRectW = 0xffff;
    stream = bak_fopen("fmap_twn.dat", "rb");
    bak_fread(&g_wFmapMapWidth, 2, 1, stream);
    bak_fread(&g_wFmapMapHeight, 2, 1, stream);
    bak_fread(&g_wFmapHotspotW, 2, 1, stream);
    bak_fread(&g_wFmapHotspotH, 2, 1, stream);
    bak_fread(&g_wFmapTownCount, 2, 1, stream);
    if (g_wFmapTownCount != 0) {
        g_pFmapTownLabels = labelPtr = galloc_safe_zcalloc(g_wFmapTownCount << 1);
        g_pFmapTownXCoords = xPtr = galloc_safe_zcalloc(g_wFmapTownCount << 1);
        g_pFmapTownYCoords = yPtr = galloc_safe_zcalloc(g_wFmapTownCount << 1);
        i = 0;
        while (i < (int)g_wFmapTownCount) {
            bak_fread(&len, 2, 1, stream);
            *labelPtr = (unsigned short)galloc_safe_zcalloc(len);
            bak_fread((void *)*labelPtr, 1, len, stream);
            bak_fread(xPtr, 2, 1, stream);
            bak_fread(yPtr, 2, 1, stream);
            len = font_text_width_ds((char *)*labelPtr);
            if ((int)len > (int)g_wFmapLabelRectW) {
                g_wFmapLabelRectW = len;
            }
            i++;
            labelPtr++;
            xPtr++;
            yPtr++;
        }
    }
    bak_fclose(stream);
    g_wFmapLabelRectH = g_graphics_context.pFont_height[0] + 1;
    g_pFmapLabelRectBuf =
        alloc_far((unsigned long)(unsigned short)rect_byte_size(g_wFmapLabelRectW, g_wFmapLabelRectH), 0L);
    g_pFmapIconTable = resblit_load_asset_table("fmap_icn.bmp", 0);
    return;
}

void fmap_hotspots_unload(void) {
    int i;

    free_image_record(g_pFmapIconTable);
    _freemem(g_pFmapLabelRectBuf);
    for (i = g_wFmapTownCount - 1; 0 <= i; i--) {
        galloc_zfree((void *)g_pFmapTownLabels[i]);
    }
    galloc_zfree(g_pFmapTownYCoords);
    galloc_zfree(g_pFmapTownXCoords);
    galloc_zfree(g_pFmapTownLabels);
    return;
}

int far fmap_hit_test_cursor(void) {
    unsigned short *px = g_pFmapTownXCoords;
    unsigned short *py = g_pFmapTownYCoords;
    int halfW = (int)(g_wFmapHotspotW - g_wFmapMapWidth) >> 1;
    int halfH = (int)(g_wFmapHotspotH - g_wFmapMapHeight) >> 1;
    short cx = screen_cursor_get_x();
    short cy = screen_cursor_get_y();
    register int i;
    i = 0;
    if (i < (int)g_wFmapTownCount) {
        do {
            register int x0 = (int)*px - halfW;
            register int y0 = (int)*py - halfH;
            if (cx >= x0 && cx <= x0 + (int)g_wFmapHotspotW && cy >= y0 &&
                cy <= y0 + (int)g_wFmapHotspotH)
                return i;
            i++;
            px++;
            py++;
        } while (i < (int)g_wFmapTownCount);
    }
    return -1;
}

int far fmap_xy_lookup_for_chapter(int *out_x, int *out_y) {
    unsigned int i;
    int entry_chapter;
    unsigned char refIndex;
    register BakFile *stream;
    register int found;

    found = 0;
    refIndex = g_apCombat_zone_actor_lists[0]->bRef_pair_index;
    stream = bak_fopen("fmap_xy.dat", "rb");
    if (stream != (BakFile *)0x0) {
        for (i = 1; (int)i <= 0xc; i++) {
            bak_fread(&entry_chapter, 2, 1, stream);
            if (g_gameState.nZoneId == i) {
                if ((int)(unsigned int)refIndex < entry_chapter) {
                    if (refIndex != 0) {
                        bak_fseek(stream, (unsigned long)(unsigned int)(refIndex << 2), 1);
                    }
                    bak_fread(out_x, 2, 1, stream);
                    bak_fread(out_y, 2, 1, stream);
                    found = 1;
                }
                break;
            }
            if (entry_chapter != 0) {
                bak_fseek(stream, (unsigned long)(unsigned int)(entry_chapter << 2), 1);
            }
        }
        bak_fclose(stream);
    }
    if (((found != 0) && (*out_x == -1)) && (*out_y == -1)) {
        found = 0;
    }
    return found;
}

int far fmap_farptr_normalize(unsigned int *pHeading) {
    unsigned long heading;
    int i;
    int bound;
    unsigned long boundary;

    heading = (unsigned long)*pHeading;
    boundary = 0;
    bound = 9;
    i = 0;
    while (i < bound) {
        if (boundary != heading) {
            if ((long)heading < (long)boundary) {
                *pHeading = (unsigned int)boundary;
                if ((long)heading < (long)(boundary + 0xfffff000)) {

                    *pHeading -= R3D_DEG(45);
                }
                return 1;
            }
            boundary += R3D_DEG(45);
            i++;
            continue;
        }
        break;
    }
    return 0;
}
