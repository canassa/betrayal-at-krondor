#include <stdlib.h>
#include <string.h>

#include "globals.h"
#include "SRC/GAME/GMAIN.H"
#include "SRC/GEN/GFXCTX.H"
#include "SRC/INPUT/TIMER.H"
#include "structs.h"
#include "SRC/SCREENS/ENCAMP.H"
#include "SRC/IO/IO.H"
#include "SRC/SYS/MEM.H"
#include "SRC/GFX/FONT/FONT.H"
#include "SRC/GFX/SPRITE/RESBLIT.H"
#include "SRC/GFX/RASTER/PRESENT.H"
#include "SRC/GFX/RASTER/POLYFILL.H"
#include "SRC/R3D/SCENE/WORLDHIT.H"
#include "SRC/GFX/SCREEN/SCREEN.H"
#include "SRC/UI/MENUPAGE.H"
#include "SRC/GFX/PALETTE/PALETTE.H"
#include "SRC/SYS/EMSIMG.H"
#include "SRC/GAME/GSTATE.H"
#include "SRC/CHAR/STAT.H"
#include "SRC/R3D/VIS/PROXSCAN.H"
#include "SRC/DIALOG/DIALOG.H"
#include "SRC/SCREENS/ITEMTBL.H"

unsigned short g_wEncampHotspotSubW;
unsigned short g_wEncampHotspotSubH;
unsigned short g_wEncampHotspotBoxW;
unsigned short g_wEncampHotspotBoxH;
unsigned short g_wEncampHotspotCount;
unsigned short g_wEncampClockVertexCount;

unsigned short *g_pEncampBmpAssetTable = {0};
unsigned short *g_pEncampHotspotX = {0};
unsigned short *g_pEncampHotspotY = {0};
unsigned short *g_pClockHandVertsX = {0};
unsigned short *g_pClockHandVertsY = {0};
unsigned char *g_pEncampPaletteRemapLut = {0};

void far encamp_run(void) {
    int running;
    unsigned short menuSelChanged;
    int menuRedrawFrames;
    int bgRedrawFrames;
    int hoverHotspot;
    int prevHotspot;
    int advancing;
    int showCancelBtn;
    int showCampBtn;
    unsigned int restUntilHealed;
    int trailFrames;
    unsigned int menuAction;
    int i;
    int sickCurePending;
    unsigned int restStartTime;
    unsigned int targetTime;
    unsigned int prevTime;
    unsigned long startGameTime;
    MenuPage *page;
    unsigned int time_in_period;

    running = 1;
    menuSelChanged = 0;
    menuRedrawFrames = 0;
    bgRedrawFrames = 0;
    hoverHotspot = -1;
    prevHotspot = -1;
    advancing = 0;
    showCancelBtn = 0;
    showCampBtn = 0;
    restUntilHealed = 0;
    trailFrames = 2;
    sickCurePending = 1;
    restStartTime = (unsigned int)((g_gameState.game_time % 0xa8c0) / 0x708 * 0x708);
    time_in_period = restStartTime;
    targetTime = restStartTime;
    startGameTime = g_gameState.game_time;
    if (proxscan_vis_rec_kind_0e3e() != 0) {
        dialog_play_record(0x65, 1);
    } else {
        page = menupage_load("req_camp.dat");
        menupage_begin(page);
        if (stat_party_all_above_pct(0x50) != 0) {
            page->pEntries->bActive_flag = 0;
            page->pEntries->wEnable_gate = 1;
            page->pEntries[2].rect.x = 0xbe;
            page->pEntries[2].rect.y = 0x4d;
        }
        encamp_load();
        g_graphics_context.wGfxBlitDstPage = g_graphics_context.wGfxBlitSrcPage =
            g_graphics_context.wVgaPage2Base;
        encamp_restore_screen_background();
        encamp_draw_clock_hand(time_in_period);
        encamp_draw_party_stats();
        menupage_draw(page);
        encamp_proj_trail_emit_facing(0, 1, -1, restStartTime, time_in_period, targetTime);
        screen_wipe_horizontal(0xd, 0xb, 0x126, 0x65);
        while (running != 0) {
            g_graphics_context.wGfxBlitDstPage = g_graphics_context.wGfxBlitSrcPage =
                g_graphics_context.wVgaPage2Base;
            if (bgRedrawFrames != 0) {
                encamp_restore_screen_background();
                encamp_draw_clock_hand(time_in_period);
                encamp_draw_party_stats();
                bgRedrawFrames--;
            }
            if (menuRedrawFrames != 0) {
                menupage_draw(page);
                menuRedrawFrames--;
            }
            if (trailFrames != 0) {
                encamp_proj_trail_emit_facing(restUntilHealed, 1, hoverHotspot, restStartTime,
                                              time_in_period, targetTime);
                if (advancing) {
                    trailFrames--;
                }
            } else {
                encamp_proj_trail_emit_facing(restUntilHealed, 0, hoverHotspot, restStartTime,
                                              time_in_period, targetTime);
            }
            screen_frame_present();
            menuAction = menupage_run(page, &menuSelChanged);
            if (menuSelChanged != 0) {
                menuRedrawFrames = 2;
                menuSelChanged = 0;
            }
            if (advancing) {
                if (trailFrames == 0 && time_in_period == targetTime) {
                    if (restUntilHealed == 0) {
                        if (bgRedrawFrames == 0 && menuRedrawFrames == 0) {
                            g_nFrameTickCountdown = 0x6e;
                            while (g_nFrameTickCountdown != 0) {
                                screen_frame_present();
                            }
                            running = 0;
                        }
                    } else {
                        trailFrames = 2;
                    }
                } else if (restUntilHealed == 0 || stat_party_all_above_pct(0x50) == 0) {
                    prevTime = time_in_period;

                    time_in_period += 900;
                    if (time_in_period >= 0xa8c0) {

                        time_in_period += 0x5740;
                    }
                    if ((long)prevTime / 0x708 != (long)time_in_period / 0x708) {
                        gstate_advance_half_hours(1, 0x50, 100);
                        if (sickCurePending &&
                            g_gameState.game_time / 0x708 - (long)startGameTime / 0x708 >= 0xd) {
                            for (i = 0; i < g_gameState.party_count; i++) {
                                stat_combatant_apply_delta(
                                    &g_gameState.party_members[g_gameState.party_roster[i]], 0,
                                    -100);
                            }
                            sickCurePending = 0;
                        }
                        if (g_gameState.bCombatExitRequest != '\0') {
                            running = 0;
                        }
                    }
                    bgRedrawFrames = 2;
                    menuRedrawFrames = 2;
                } else if (bgRedrawFrames == 0 && menuRedrawFrames == 0) {
                    restUntilHealed = 0;
                    hoverHotspot = -1;
                    advancing = 0;
                    showCampBtn = 1;
                    restStartTime = targetTime = time_in_period;
                    trailFrames = 2;
                }
            } else {
                hoverHotspot = encamp_hotspot_at_cursor();
                if (hoverHotspot != -1) {
                    switch (screen_input_poll_confirm_cancel()) {
                    case 0:
                        if (prevHotspot == hoverHotspot) {
                            targetTime = (long)(short)hoverHotspot * 0x708;
                            hoverHotspot = -1;
                            advancing = 1;
                            showCancelBtn = 1;
                        }
                        break;
                    case 1:
                        prevHotspot = hoverHotspot;
                        break;
                    case 2:
                        dialog_play_record(0xf0, 1);
                        bgRedrawFrames = menuRedrawFrames = 2;
                        break;
                    }
                } else {
                    prevHotspot = -1;
                }
            }
            switch (menuAction) {
            case 0xc2:
                if (menupage_state_0e7c() == 1) {
                    running = 0;
                } else {
                    dialog_play_record(0xef, 1);
                    bgRedrawFrames = menuRedrawFrames = 2;
                }
                break;
            case 0xc1:
                if (menupage_state_0e7c() == 1) {
                    restUntilHealed = 1;
                    hoverHotspot = -1;
                    advancing = 1;
                    showCancelBtn = 1;
                } else {
                    dialog_play_record(0xee, 1);
                    bgRedrawFrames = menuRedrawFrames = 2;
                }
                break;
            case 0xc0:
                if (menupage_state_0e7c() == 1) {
                    running = 0;
                } else {
                    dialog_play_record(0xed, 1);
                    bgRedrawFrames = menuRedrawFrames = 2;
                }
                break;
            }
            if (showCancelBtn || showCampBtn) {
                if (showCancelBtn) {
                    page->pEntries->bActive_flag = 0;
                    page->pEntries->wEnable_gate = 1;
                    page->pEntries[1].bActive_flag = 1;
                    page->pEntries[1].wEnable_gate = 0;
                    page->pEntries[2].bActive_flag = 0;
                    page->pEntries[2].wEnable_gate = 1;
                } else {
                    page->pEntries->bActive_flag = 0;
                    page->pEntries->wEnable_gate = 1;
                    page->pEntries[1].bActive_flag = 0;
                    page->pEntries[1].wEnable_gate = 1;
                    page->pEntries[2].bActive_flag = 1;
                    page->pEntries[2].wEnable_gate = 0;
                    page->pEntries[2].rect.x = 0xbe;
                    page->pEntries[2].rect.y = 0x4d;
                }
                bgRedrawFrames = 2;
                menuRedrawFrames = 2;
                showCancelBtn = 0;
                showCampBtn = 0;
            }
        }
        palette_apply_pending_load();
        g_graphics_context.wGfxBlitDstPage = g_graphics_context.wGfxBlitSrcPage =
            g_graphics_context.wVgaPage2Base;
        world_render_scene_dispatch(0);
        screen_wipe_horizontal(0xd, 0xb, 0x126, 0x65);
        encamp_teardown();
        menupage_end(page);
        menupage_free(page);
    }
    return;
}

void far encamp_load(void) {
    register BakFile *stream;
    unsigned short *ptx;
    unsigned short *pty;
    register int i;

    g_pEncampBmpAssetTable = (unsigned short *)resblit_load_asset_table("encamp.bmp", 2);
    g_graphics_context.wGfxBlitDstPage = g_graphics_context.wVgaPage1Base;
    resblit_load_pal_or_stream("encamp.scx");
    stream = bak_fopen("encamp.dat", "rb");
    bak_fread(&g_wEncampHotspotSubW, 2, 1, stream);
    bak_fread(&g_wEncampHotspotSubH, 2, 1, stream);
    bak_fread(&g_wEncampHotspotBoxW, 2, 1, stream);
    bak_fread(&g_wEncampHotspotBoxH, 2, 1, stream);
    bak_fread(&g_wEncampHotspotCount, 2, 1, stream);
    g_pEncampHotspotX = ptx = galloc_safe_zcalloc(g_wEncampHotspotCount << 1);
    g_pEncampHotspotY = pty = galloc_safe_zcalloc(g_wEncampHotspotCount << 1);
    i = 0;
    if (i < (int)g_wEncampHotspotCount) {
        do {
            bak_fread(ptx, 2, 1, stream);
            bak_fread(pty, 2, 1, stream);
            i++;
            ptx++;
            pty++;
        } while (i < (int)g_wEncampHotspotCount);
    }
    bak_fread(&g_wEncampClockVertexCount, 2, 1, stream);
    g_pClockHandVertsX = ptx = galloc_safe_zcalloc(g_wEncampClockVertexCount << 1);
    g_pClockHandVertsY = pty = galloc_safe_zcalloc(g_wEncampClockVertexCount << 1);
    i = 0;
    if (i < (int)g_wEncampClockVertexCount) {
        do {
            bak_fread(ptx, 2, 1, stream);
            bak_fread(pty, 2, 1, stream);
            i++;
            ptx++;
            pty++;
        } while (i < (int)g_wEncampClockVertexCount);
    }
    bak_fclose(stream);
    encamp_build_palette_remap_lut();
}

void far encamp_teardown(void) {
    encamp_free_buffer();
    galloc_zfree(g_pClockHandVertsY);
    galloc_zfree(g_pClockHandVertsX);
    galloc_zfree(g_pEncampHotspotY);
    galloc_zfree(g_pEncampHotspotX);
    emsimg_free_paged(g_pEncampBmpAssetTable);
}

void encamp_restore_screen_background(void) {
    g_graphics_context.wGfxBlitSrcPage = g_graphics_context.wVgaPage1Base;
    gfx_present_dispatch(0xd, 0xb, 0x125, 0x65);
    return;
}

void encamp_proj_trail_emit_facing(int a, int b, int c, unsigned int d, unsigned int e, unsigned int f) {
    unsigned int startHour;
    unsigned int curHour;
    unsigned int targetHour;
    int ascending;
    int bmpIdx;
    unsigned int i;
    unsigned short *px;
    unsigned short *py;

    startHour = (long)d / 0x708;
    curHour = (long)e / 0x708;
    targetHour = (long)f / 0x708;
    ascending = ((int)startHour < (int)curHour) ? 1 : 0;
    px = g_pEncampHotspotX;
    py = g_pEncampHotspotY;
    i = 0;
    while ((int)i < (int)g_wEncampHotspotCount) {
        if (a != 0) {
            if (i == curHour) {
                bmpIdx = 3;
            } else {
                bmpIdx = 1;
            }
        } else {
            if (c != -1 && i == c) {
                bmpIdx = 2;
            } else if (i == targetHour) {
                bmpIdx = 3;
            } else if ((b != 0) && (startHour == curHour)) {
                if (i == startHour) {
                    bmpIdx = 3;
                } else {
                    bmpIdx = 1;
                }
            } else if (ascending && (int)i >= (int)startHour && (int)i <= (int)curHour) {
                bmpIdx = 3;
            } else if (ascending) {
                bmpIdx = 1;
            } else if ((int)i >= (int)startHour || (int)i <= (int)curHour) {
                bmpIdx = 3;
            } else {
                bmpIdx = 1;
            }
        }
        emsimg_map_then_call_180c((unsigned int *)g_pEncampBmpAssetTable[bmpIdx], *px, *py, 0);
        i++;
        px++;
        py++;
    }
}

int encamp_hotspot_at_cursor(void) {
    unsigned short *px;
    unsigned short *py;
    int halfW;
    int halfH;
    int curX;
    int curY;
    register int x0;
    register int y0;
    register int i;

    px = g_pEncampHotspotX;
    py = g_pEncampHotspotY;
    halfW = (int)(g_wEncampHotspotBoxW - g_wEncampHotspotSubW) >> 1;
    halfH = (int)(g_wEncampHotspotBoxH - g_wEncampHotspotSubH) >> 1;
    curX = screen_cursor_get_x();
    curY = screen_cursor_get_y();
    for (i = 0; i < (int)g_wEncampHotspotCount; i++, px++, py++) {
        x0 = *px - halfW;
        y0 = *py - halfH;
        if (curX >= x0 && (int)(x0 + g_wEncampHotspotBoxW) >= curX && curY >= y0 &&
            (int)(y0 + g_wEncampHotspotBoxH) >= curY) {
            return i;
        }
    }
    return -1;
}

void far encamp_build_palette_remap_lut(void) {
    unsigned char *pLut;
    unsigned char far *pPal;
    int i;

    pPal = g_graphics_context.pPaletteScratchBuf;

    g_pEncampPaletteRemapLut = pLut = galloc_safe_zcalloc(0x100);
    i = 0;
    do {
        if (i < 0x70) {
            *pLut = (unsigned char)encamp_palette_nearest_color(pPal, -10);
        } else {
            *pLut = (unsigned char)i;
        }
        i++;
        pPal += 3;
        pLut++;
    } while (i < 0x100);
}

void encamp_free_buffer(void) {
    galloc_zfree(g_pEncampPaletteRemapLut);
}

unsigned int far encamp_palette_nearest_color(unsigned char far *palette_ptr, int bias) {
    unsigned int best_idx;
    unsigned int best_dist;
    unsigned char far *p;
    unsigned int i;

    best_dist = 0x301;
    p = g_graphics_context.pPaletteScratchBuf;
    for (i = 0; i < 0x70; i++, p += 3) {
        unsigned int dist = (unsigned int)(abs((int)(char)palette_ptr[0] + bias - (int)(char)p[0]) +
                           abs((int)(char)palette_ptr[1] + bias - (int)(char)p[1]) +
                           abs((int)(char)palette_ptr[2] + bias - (int)(char)p[2]));
        if (dist < best_dist) {
            best_dist = dist;
            best_idx = i;
        }
    }
    return best_idx;
}

void far encamp_draw_clock_hand(unsigned int time_in_period) {
    unsigned int vertIdx;

    if ((time_in_period >= 0x2a30) && (time_in_period <= 0x7e90)) {
        vertIdx = (unsigned int)((long)(time_in_period << 1) / 0x708) + 0xfff4u;
        if (vertIdx != 0xc) {
            g_graphics_context.bClip_enabled = '\0';
            g_graphics_context.bGfx_fill_enabled = '\x01';
            g_graphics_context.bGfx_fill_color = '\0';
            g_graphics_context.bGfx_outline_color = '\0';
            g_graphics_context.bGfx_dither_color = '\0';
            if (vertIdx > 0xc) {
                vertIdx--;
            }
            g_pClockHandVertsX[2] = g_pClockHandVertsX[vertIdx + 3];
            g_pClockHandVertsY[2] = g_pClockHandVertsY[vertIdx + 3];
            draw_polygon_textured(3, (int *)g_pClockHandVertsX, (int *)g_pClockHandVertsY,
                                  (int)g_pEncampPaletteRemapLut);
        }
    }
    return;
}

void far encamp_draw_party_stats(void) {
    register int iVar1;
    register int p;
    char text[30];
    char numBuf[10];
    unsigned int healthStamina;
    unsigned int maxHealthStamina;
    unsigned int rations;
    int x;
    int y;

    g_graphics_context.bText_fg_color = '\0';
    g_graphics_context.bText_style_flags = '\x01';
    g_graphics_context.bClip_enabled = '\0';
    iVar1 = 0;
    do {
        x = (g_anEncampStatColX[iVar1] + 0x86) -
            (font_text_width_ds(g_apszEncampStatColHeaders[iVar1]) >> 1);
        y = 0x15;
        font_draw_text_ds(g_apszEncampStatColHeaders[iVar1], x, y);
        iVar1 = iVar1 + 1;
    } while (iVar1 < 2);
    p = 0;
    goto LAB_check;
LAB_body:
    iVar1 = g_gameState.party_roster[p];
    healthStamina = stat_actor_get(&g_gameState.party_members[iVar1], 0x10, 0);
    maxHealthStamina = stat_actor_get(&g_gameState.party_members[iVar1], 0x10, 1);
    rations = itemtbl_inv_count_by_kind(g_gameState.party_members[iVar1].actor_record, 0x48);
    rations += itemtbl_inv_count_by_kind(g_gameState.party_members[iVar1].actor_record, 0x4a);
    rations += itemtbl_inv_count_by_kind(g_gameState.party_members[iVar1].actor_record, 0x49);
    y = p * 0x10 + 0x25;
    if ((g_gameState.abActorStatusRanks[iVar1][0] != '\0') ||
        (g_gameState.abActorStatusRanks[iVar1][1] != '\0') ||
        (g_gameState.abActorStatusRanks[iVar1][2] != '\0') ||
        (g_gameState.abActorStatusRanks[iVar1][3] != '\0') ||
        (g_gameState.abActorStatusRanks[iVar1][5] != '\0') ||
        (g_gameState.abActorStatusRanks[iVar1][6] != '\0')) {
        g_graphics_context.bText_fg_color = 'k';
    }
    font_draw_text_ds(g_gameState.pParty_names[iVar1], 0x8b, y);
    g_graphics_context.bText_fg_color = '\0';
    iVar1 = 0;
    do {
        switch (iVar1) {
        case 0:
            itoa(healthStamina, text, 10);
            strcat(text, g_pszHpSeparator);
            itoa(maxHealthStamina, numBuf, 10);
            strcat(text, numBuf);
            itoa(healthStamina, numBuf, 10);
            break;
        case 1:
            itoa(rations, text, 10);
            break;
        }
        x = (g_anEncampStatColX[iVar1] + 0x86) - (font_text_width_ds(text) >> 1);
        font_draw_text_ds(text, x, y);
        if ((iVar1 == 0) && ((int)healthStamina < (int)(maxHealthStamina * 0x50) / 100)) {
            g_graphics_context.bText_fg_color = 'k';
            font_draw_text_ds(numBuf, x, y);
            g_graphics_context.bText_fg_color = '\0';
        }
        iVar1 = iVar1 + 1;
    } while (iVar1 < 2);
    p = p + 1;
LAB_check:
    if (g_gameState.party_count > p)
        goto LAB_body;
    return;
}

char *g_apszEncampStatColHeaders[2] = {"Health/Stamina", "Rations"};
char *g_pszHpSeparator = " of ";
unsigned short g_anEncampStatColX[2] = {0x0054, 0x0090};
