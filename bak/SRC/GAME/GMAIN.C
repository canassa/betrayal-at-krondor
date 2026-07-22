#include <stdio.h>
#include <string.h>
#include "globals.h"
#include "structs.h"
#include "SRC/GAME/GMAIN.H"
#include "SRC/IO/IO.H"
#include "SRC/AUDIO/ENGINE/AUDIO.H"
#include "SRC/GFX/FONT/FONT.H"
#include "SRC/GFX/SPRITE/RESBLIT.H"
#include "SRC/GFX/DRIVER/PALDRV.H"
#include "SRC/GFX/SPRITE/RECTSPR.H"
#include "SRC/GFX/RASTER/PRESENT.H"
#include "SRC/INPUT/KEYBOARD.H"
#include "SRC/GFX/DRIVER/VTHUNKS.H"
#include "SRC/STREAM/RESLOAD/FONTLOAD.H"
#include "SRC/STREAM/RESLOAD/IMGLOAD.H"
#include "SRC/INPUT/MOUSE.H"
#include "SRC/GFX/SPRITE/SPRTHNKS.H"
#include "SRC/GFX/SCREEN/SCREEN.H"
#include "SRC/UI/MENUPAGE.H"
#include "SRC/GFX/PALETTE/PALETTE.H"
#include "SRC/COMBAT/GRID/CMBTGRID.H"
#include "SRC/SCREENS/CREDITS.H"
#include "SRC/GAME/BOOT.H"
#include "SRC/GAME/SAVEGAME.H"
#include "SRC/GAME/GSTATE.H"
#include "SRC/GAME/CFGPARSE.H"
#include "SRC/UI/UIWIDGET.H"
#include "SRC/DIALOG/DIALOG.H"
#include "SRC/SCREENS/BOOKVIEW.H"
#include "SRC/SCRIPT/ANIMSCR.H"
#include "SRC/SCRIPT/ADSCRIPT.H"
#include "SRC/WORLD/LOOP/WORLDLP.H"
#include "SRC/SCREENS/MAINMENU.H"
#include "SRC/WORLD/ZONE/ZONE.H"

unsigned char g_bssgap_4863[3];
GameState g_gameState;
unsigned short g_bPaletteCycleEbActive;
unsigned short g_wVgaScratchPageBase;
unsigned short g_wGameFontSlot;
unsigned short *g_pSkyPanoAssetTable;
WorldEntity *g_render_camera_scratch;
ViewContext *g_active_window;
unsigned short g_nChapterAtLoopExit;

unsigned long g_nVec3DistResult = 0x00000000UL;

PolyRasterState g_polyRasterState = {0};
unsigned char g_bCutsceneEscPressed = 0x00;

int far gmain_start_dispatch(int mode) {
    register int iMode;
    register char *path;
    unsigned char far *pal;
    int chapter;
    int iconX;
    int iconY;
    int iconIndex;
    int doFullmap;
    ImageRecord **iconTable;
    char pathBuf[50];
    char sig_block[90];

    iMode = mode;
    path = (char *)0;
    chapter = 0;
    iconX = -1;
    doFullmap = 0;

    if (iMode != 4) {
        palette_fade_out(0, 0x100, -1, 0);
        palette_screen_clear_black();
    }
    g_graphics_context.wGfxBlitDstPage = g_wVgaScratchPageBase;
    resblit_load_pal_or_stream("Z01L.SCR");

    if (iMode == 2) {
        strcpy(pathBuf, "STARTUP.GAM");
        path = pathBuf;
        chapter = 1;
        iconX = 0x74;
        iconY = 0x4b;
        iconIndex = 0x12;
        doFullmap = 1;
    } else if (iMode == 3) {
        sprintf(pathBuf, "%s\\%s.G%02d\\SAVE%02d.GAM", "GAMES", g_szSaveSlotDirName_51cc,
                g_wCurrentSaveSlotKey, g_wCurrentSaveFileKey);
        path = pathBuf;
        if (mainmenu_save_file_read_header(path, sig_block, &chapter, &iconX, &iconY, &iconIndex) !=
            0) {
            iconIndex += 2;
            doFullmap = 1;
        }
    } else if (iMode == 4) {

    } else if (iMode == 5) {
        chapter = g_nChapterAtLoopExit + 1;
        switch ((unsigned)chapter - 2) {
        case 0:
            iconX = 0xa8;
            iconY = 0x93;
        LAB_010b:
            iconIndex = 0x12;
            break;
        case 1:

            iconX = 0x100;
            iconY = 0x72;
            iconIndex = 2;
            break;
        case 2:
            iconX = 0xa7;
            iconY = 0x18;
            iconIndex = 0x1a;
            break;
        case 3:
            iconX = 0xea;
            iconY = 0x34;
            iconIndex = 2;
            break;
        case 4:
            iconX = 0xa8;
            iconY = 0x94;
            iconIndex = 2;
            break;
        case 5:
            iconX = 0xb8;
            iconY = 0x5c;
            goto LAB_010b;
        case 7:
            iconX = 0xcb;
            iconY = 0x80;
            iconIndex = 2;
            break;
        case 6:
            break;
        }
        doFullmap = 1;
    } else if (iMode == 7) {
    }

    if (doFullmap != 0) {
        font_activate(g_wGameFontSlot);
        pal = chunk_load_into_slot("FULLMAP.PAL");
        palette_set(pal);
        g_pPalQueuedForFlip = (unsigned char far *)0;
        palette_set_scaled(0, 0x100, 0, 0);
        g_graphics_context.wGfxBlitDstPage = g_graphics_context.wVgaPage2Base;
        resblit_load_pal_or_stream("FULLMAP.SCX");
        if (iconX != -1 && iconY != -1) {
            iconTable = resblit_load_asset_table("fmap_icn.bmp", 0);
            g_graphics_context.wGfxBlitSrcPage = g_graphics_context.wGfxBlitDstPage =
                g_graphics_context.wVgaPage2Base;
            blit_sprite_indirect((unsigned short)iconTable[iconIndex], iconX - 3, iconY - 3, 0);
            free_image_record(iconTable);
        }
        vsync_hook(1);
        g_graphics_context.wGfxBlitSrcPage = g_graphics_context.wVgaFrontPageBase;
        g_graphics_context.wGfxBlitDstPage = g_graphics_context.wVgaPage2Base;
        gfx_present_dispatch(0, 0, 0x140, 200);
        if (chapter >= 1 && chapter <= 9) {

            dialog_play_record((long)(chapter + 0x125), 0);
        }
        cache_release(pal);
    }

    if (iMode != 4) {
        screen_cursor_show_busy();
        palette_fade_in(0, 0x100, -1, 0);
    }

    if (path != (char *)0) {
        if (savegame_read(path) == 0) {
            dialog_play_record(0x13b, 1);
            palette_fade_out(0, 0x100, -1, 0);
            palette_screen_clear_black();
            return 6;
        }
    }

    gstate_temp_file_open();
    uiwidget_tile_sprite_load();
    boot_party_state_load_from_temp();
    g_nSpellFontSlot = font_load("spell.fnt");

    if (iMode == 2) {
        savegame_chapter_start_dispatch(1);
    } else if (iMode == 5) {
        savegame_chapter_start_dispatch(g_nChapterAtLoopExit + 1);
    } else if (iMode == 7) {
        g_gameState.nWorldLoopExitRequest = '\0';
    }

    zone_subsystem_init();
    worldloop_req_main_screen_load();
    boot_start_dat_load();
    combatgrid_cmbts_tbl_alloc();
    zone_load();
    palette_set_scaled(0, 0x100, 0, 0x3f);
    font_activate(g_wGameFontSlot);
    iMode = worldloop_main();
    g_pPalQueuedForFlip = (unsigned char far *)0;
    zone_world_scene_teardown();
    combatgrid_combatants_table_free();
    boot_active_window_free();
    worldloop_req_main_screen_unload();
    zone_subsystem_shutdown();
    font_unload(g_nSpellFontSlot);
    boot_party_state_save_to_temp();
    uiwidget_tile_sprite_free();
    gstate_temp_file_close();
    return iMode;
}

void far gmain_play_intro_animation(void) {
    int scriptHandle;
    unsigned char far *pal;
    unsigned long deadline;
    register int done;
    register int channel;

    channel = 1;
    done = 0;
    while (done == 0) {
        pal = chunk_load_into_slot("INT_DYN.PAL");
        palette_set(pal);
        cache_release(pal);
        scriptHandle = anim_script_open("INTRO.ADS", 0);
        anim_script_activate(scriptHandle);
        anim_script_channel_start(channel);
        if (anim_script_has_channel(channel)) {
            while (anim_script_tick()) {
                adscript_apply_pending_palette();
                vsync_hook(1);
                g_graphics_context.wGfxBlitDstPage = g_graphics_context.wVgaPage2Base;
                g_graphics_context.wGfxBlitSrcPage = g_graphics_context.wVgaPage1Base;
                gfx_present_dispatch(0, 0, 0x140, 200);
                if (kbhit_read() >> 8 != 0)
                    goto LAB_20932_interrupt;
                if (g_mouse_installed != '\0') {
                    if (mouse_button_pressed(0) != 0)
                        goto LAB_20932_interrupt;
                    if (mouse_button_pressed(1) != 0)
                        goto LAB_20932_interrupt;
                }
                continue;
            LAB_20932_interrupt:
                done = 1;
                break;
            }
        }
        anim_script_channel_stop(channel);
        anim_script_close(scriptHandle);
        anim_script_close_all();
        adscript_renderer_reset();
        if (done == 0) {
            done = credits_run();
            deadline = g_timer_ticks + 0x8c;
            while (g_timer_ticks < deadline) {
                if (g_mouse_installed != '\0') {
                    if (mouse_button_pressed(0) != 0)
                        break;
                    if (mouse_button_pressed(1) != 0)
                        break;
                }
                if (kbhit_read() >> 8 != 0)
                    break;
            }
        }
        palette_fade_out(0, 0x100, -1, 0);
        palette_screen_clear_black();
        palette_set_scaled(0, 0x100, 0, 0x3f);
    }
}

int far gmain_play_chapter_intro(int chapter, int part) {
    BakFile *stream;
    int result;
    int trackId;
    char bookName[20];

    trackId = -999;
    result = 1;
    if ((part == 1) || (part == 2)) {
        stream = bak_fopen("chapsong.dat", "rb");
        bak_fseek(stream, (long)(unsigned int)((part + (chapter - 1) * 2 - 1) * 2), 0);
        bak_fread(&trackId, 2, 1, stream);
        bak_fclose(stream);
    }
    bookview_init();
    audio_music_play(trackId);
    strcpy(bookName, "C00.BOK");
    bookName[1] = bookName[1] + (char)chapter;
    bookName[2] = bookName[2] + (char)part;
    if (bookview_show(bookName, -1) < 0)
        result = 0;
    bookview_shutdown();
    return result;
}

int far gmain_play_chapter_cutscene(int chapter_num, int channel_1, int channel_2) {
    register int scriptHandle;
    register int ch2;
    int result;
    char adsName[20];

    ch2 = channel_2;
    g_pPalQueuedForFlip = (unsigned char far *)0x0;
    g_bCutsceneEscPressed = '\0';
    sprintf(adsName, "CHAPTER%d.ADS", chapter_num);
    scriptHandle = anim_script_open(adsName, 0);
    anim_script_activate(scriptHandle);
    if (anim_script_has_channel(channel_1)) {

        audio_music_play(0x3f7);
        anim_script_channel_start(channel_1);
        while (anim_script_tick()) {
            adscript_apply_pending_palette();
            vsync_hook(1);
            g_graphics_context.wGfxBlitDstPage = g_graphics_context.wVgaPage2Base;
            g_graphics_context.wGfxBlitSrcPage = g_graphics_context.wVgaPage1Base;
            gfx_present_dispatch(0, 0, 0x140, 200);
            if (kbhit_read() >> 8 == 1) {
                g_bCutsceneEscPressed = '\x01';
            }
        }
        anim_script_channel_stop(1);
    }
    anim_script_close(scriptHandle);
    anim_script_close_all();
    adscript_renderer_reset();
    result = gmain_play_chapter_intro(chapter_num, channel_1);
    strcpy(adsName, "C00.");
    adsName[1] = adsName[1] + (char)chapter_num;
    adsName[2] = adsName[2] + (char)channel_1;
    strcpy(&adsName[4], "ADS");
    scriptHandle = anim_script_open(adsName, 0);
    anim_script_activate(scriptHandle);
    if (anim_script_has_channel(ch2)) {
        anim_script_channel_start(ch2);
        while (anim_script_tick()) {
            adscript_apply_pending_palette();
            vsync_hook(1);
            g_graphics_context.wGfxBlitDstPage = g_graphics_context.wVgaPage2Base;
            g_graphics_context.wGfxBlitSrcPage = g_graphics_context.wVgaPage1Base;
            gfx_present_dispatch(0, 0, 0x140, 200);
        }
        anim_script_channel_stop(ch2);
        if (kbhit_read() >> 8 == 1) {
            g_bCutsceneEscPressed = '\x01';
        }
    }
    anim_script_close(scriptHandle);
    anim_script_close_all();
    adscript_renderer_reset();
    return result;
}

void far gmain_screen_fade_to_black(void) {
    palette_fade_out(0, 0x100, -1, 0);
    screen_cursor_hide();
    g_graphics_context.wGfxBlitDstPage = g_graphics_context.wVgaPage2Base;
    g_graphics_context.bGfx_fill_color = g_graphics_context.bGfx_outline_color = '\0';
    g_graphics_context.bClip_enabled = '\0';
    g_graphics_context.bGfx_fill_enabled = '\x01';
    draw_rect_filled(0, 0, 0x140, 200);
    vsync_hook(1);
    g_graphics_context.wGfxBlitDstPage = g_graphics_context.wVgaPage2Base;
    g_graphics_context.wGfxBlitSrcPage = g_graphics_context.wVgaFrontPageBase;
    gfx_present_dispatch(0, 0, 0x140, 200);
    return;
}

void far gmain_cutsc_play_fullmap_scene(int scene_index) {
    unsigned char far *pal = (unsigned char far *)0;

    gmain_screen_fade_to_black();
    pal = chunk_load_into_slot("fullmap.pal");
    g_graphics_context.wGfxBlitDstPage = g_wVgaScratchPageBase;
    resblit_load_pal_or_stream("Z01L.SCR");
    g_graphics_context.wGfxBlitDstPage = g_graphics_context.wVgaPage2Base;
    screen_cursor_hide();
    resblit_load_pal_or_stream("fullmap.scx");
    palette_set(pal);
    palette_set_scaled(0, 0x100, 0, 0);
    screen_frame_present();
    g_graphics_context.wGfxBlitSrcPage = g_graphics_context.wVgaFrontPageBase;
    g_graphics_context.wGfxBlitDstPage = g_graphics_context.wVgaPage2Base;
    gfx_present_dispatch(0, 0, 0x140, 200);
    palette_fade_in(0, 0x100, -1, 0);
    font_activate(g_wGameFontSlot);
    screen_cursor_set_hidden_flag(0);
    dialog_play_record((long)scene_index + 0x186ab5, 1);
    screen_cursor_set_hidden_flag(1);
    cache_release(pal);
    gmain_screen_fade_to_black();
}

void far gmain_restart_from_save_flow(void) {
    unsigned int run_result;
    unsigned short do_cutscene;
    int chapter_arg;
    int channel_arg;
    int sec_ch_arg;
    int highest_slot;
    int track_id;
    int state_eq2;
    int exit_flag;
    unsigned char far *palette_result;
    unsigned char far *chunk_ptr;
    register MenuPage *page;
    register int scene_index;
    int i;
    int presentY;

    scene_index = -1;
    highest_slot = mainmenu_save_scan_highest_slot();
    exit_flag = 0;
    chunk_ptr = (unsigned char far *)0;
    track_id = audio_music_play(-999);
    gmain_screen_fade_to_black();
    palette_result = palette_set((unsigned char far *)0);
    chunk_ptr = chunk_load_into_slot("contents.pal");
    g_graphics_context.wGfxBlitDstPage = g_graphics_context.wVgaPage2Base;
    screen_cursor_hide();
    resblit_load_pal_or_stream("contents.scx");
    if (highest_slot < 10) {
        g_graphics_context.wGfxBlitDstPage = g_wVgaScratchPageBase;
        resblit_load_pal_or_stream("cont2.scx");
        g_graphics_context.wGfxBlitSrcPage = g_wVgaScratchPageBase;
        g_graphics_context.wGfxBlitDstPage = g_graphics_context.wVgaPage2Base;
        presentY = highest_slot * 0x10 + 0x14;
        gfx_present_dispatch(0x3f, presentY, 0xef, 0xb4 - presentY);
    }
    g_graphics_context.wGfxBlitDstPage = g_wVgaScratchPageBase;
    resblit_load_pal_or_stream("Z01L.SCR");
    palette_set(chunk_ptr);
    palette_set_scaled(0, 0x100, 0, 0);
    screen_frame_present();
    g_graphics_context.wGfxBlitSrcPage = g_graphics_context.wVgaFrontPageBase;
    g_graphics_context.wGfxBlitDstPage = g_graphics_context.wVgaPage2Base;
    gfx_present_dispatch(0, 0, 0x140, 200);
    palette_fade_in(0, 0x100, -1, 0);
    page = menupage_load("contents.dat");
    for (i = highest_slot; i < (int)page->wEntry_count; i++) {
        if (page->pEntries[i].wAction_id != 1) {
            page->pEntries[i].wEnable_gate = 1;
        }
    }
    while (exit_flag == 0) {
        run_result = menupage_run(page, &do_cutscene);
        if (run_result != 0) {
            state_eq2 = (menupage_state_0e7c() == 2);
        }
        switch (run_result) {
        case 2:
            if (state_eq2 != 0) {
                dialog_play_record(0x149, 1);
                goto L_no_cutscene;
            }
            if (page->pEntries[0].wEnable_gate != 0) {
                break;
            }
            chapter_arg = 1;
            channel_arg = 1;
            if (highest_slot > 1) {
                scene_index = 1;
                goto L_sec_ch;
            }
            scene_index = -1;
            do_cutscene = 1;
            break;
        case 3:
            if (state_eq2 != 0) {
                dialog_play_record(0x149, 1);
                goto L_no_cutscene;
            }
            if (page->pEntries[1].wEnable_gate != 0) {
                break;
            }
            chapter_arg = 2;
            channel_arg = 1;
            if (highest_slot > 2) {
                scene_index = 2;
                goto L_sec_ch;
            }
            scene_index = -1;
            do_cutscene = 1;
            break;
        case 4:
            if (state_eq2 != 0) {
                dialog_play_record(0x149, 1);
                goto L_no_cutscene;
            }
            if (page->pEntries[2].wEnable_gate != 0) {
                break;
            }
            chapter_arg = 3;
            channel_arg = 1;
            if (highest_slot > 3) {
                scene_index = 3;
                goto L_sec_ch;
            }
            scene_index = -1;
            do_cutscene = 1;
            break;
        case 5:
            if (state_eq2 != 0) {
                dialog_play_record(0x149, 1);
                goto L_no_cutscene;
            }
            if (page->pEntries[3].wEnable_gate != 0) {
                break;
            }
            chapter_arg = 4;
            channel_arg = 1;
            if (highest_slot > 4) {
                scene_index = 4;
                goto L_sec_ch;
            }
            scene_index = -1;
            do_cutscene = 1;
            break;
        case 6:
            if (state_eq2 != 0) {
                dialog_play_record(0x149, 1);
                goto L_no_cutscene;
            }
            if (page->pEntries[4].wEnable_gate != 0) {
                break;
            }
            chapter_arg = 5;
            channel_arg = 1;
            if (highest_slot > 5) {
                scene_index = 5;
                goto L_sec_ch;
            }
            scene_index = -1;
            do_cutscene = 1;
            break;
        case 7:
            if (state_eq2 != 0) {
                dialog_play_record(0x149, 1);
                goto L_no_cutscene;
            }
            if (page->pEntries[5].wEnable_gate != 0) {
                break;
            }
            chapter_arg = 6;
            channel_arg = 1;
            if (highest_slot > 6) {
                scene_index = 6;
                goto L_sec_ch;
            }
            scene_index = -1;
            do_cutscene = 1;
            break;
        case 8:
            if (state_eq2 != 0) {
                dialog_play_record(0x149, 1);
                goto L_no_cutscene;
            }
            if (page->pEntries[6].wEnable_gate != 0) {
                break;
            }
            chapter_arg = 7;
            channel_arg = 1;
            if (highest_slot > 7) {
                scene_index = 7;
                goto L_sec_ch;
            }
            scene_index = -1;
            do_cutscene = 1;
            break;
        case 9:
            if (state_eq2 != 0) {
                dialog_play_record(0x149, 1);
                goto L_no_cutscene;
            }
            if (page->pEntries[7].wEnable_gate != 0) {
                break;
            }
            chapter_arg = 8;
            channel_arg = 1;
            if (highest_slot > 8) {
                scene_index = 8;
                goto L_sec_ch;
            }
            scene_index = -1;
            do_cutscene = 1;
            break;
        case 10:
            if (state_eq2 != 0) {
                dialog_play_record(0x149, 1);
                goto L_no_cutscene;
            }

            if (page->pEntries[8].wEnable_gate != 0) {
                break;
            }
            chapter_arg = 9;
            channel_arg = 1;
            if (highest_slot > 9) {
                scene_index = 9;
            L_sec_ch:
                sec_ch_arg = 2;
                do_cutscene = 1;
                break;
            }
            scene_index = -1;
            do_cutscene = 1;
            break;
        case 1:
            do_cutscene = 0;
            if (state_eq2 != 0) {
                dialog_play_record(0x14a, 1);
            } else {
                exit_flag = 1;
            }
            break;
        default:
        L_no_cutscene:
            do_cutscene = 0;
            break;
        }
        if (do_cutscene != 0) {
            gmain_screen_fade_to_black();
            gmain_play_chapter_cutscene(chapter_arg, channel_arg, 1);
            if (scene_index != -1) {
                gmain_cutsc_play_fullmap_scene(scene_index);
                gmain_play_chapter_cutscene(scene_index, sec_ch_arg, 1);
            }
            audio_music_play(track_id);
            g_graphics_context.wGfxBlitDstPage = g_graphics_context.wVgaPage2Base;
            g_graphics_context.bGfx_fill_color = g_graphics_context.bGfx_outline_color = '\0';
            g_graphics_context.bClip_enabled = '\0';
            g_graphics_context.bGfx_fill_enabled = '\x01';
            draw_rect_filled(0, 0, 0x140, 200);
            if (chunk_ptr != (unsigned char far *)0) {
                cache_release(chunk_ptr);
            }
            chunk_ptr = chunk_load_into_slot("contents.pal");
            screen_frame_present();
            palette_set(chunk_ptr);
            g_graphics_context.wGfxBlitDstPage = g_graphics_context.wVgaPage2Base;
            g_graphics_context.wGfxBlitSrcPage = g_graphics_context.wVgaFrontPageBase;
            gfx_present_dispatch(0, 0, 0x140, 200);
            palette_set_scaled(0, 0x100, 0, 0);
            screen_cursor_hide();
            g_graphics_context.wGfxBlitDstPage = g_graphics_context.wVgaPage2Base;
            screen_cursor_hide();
            resblit_load_pal_or_stream("contents.scx");
            if (highest_slot < 10) {
                g_graphics_context.wGfxBlitDstPage = g_wVgaScratchPageBase;
                resblit_load_pal_or_stream("cont2.scx");
                g_graphics_context.wGfxBlitSrcPage = g_wVgaScratchPageBase;
                g_graphics_context.wGfxBlitDstPage = g_graphics_context.wVgaPage2Base;
                presentY = highest_slot * 0x10 + 0x14;
                gfx_present_dispatch(0x3f, presentY, 0xef, 0xb4 - presentY);
            }
            g_graphics_context.wGfxBlitDstPage = g_wVgaScratchPageBase;
            resblit_load_pal_or_stream("Z01L.SCR");
            screen_frame_present();
            g_graphics_context.wGfxBlitSrcPage = g_graphics_context.wVgaFrontPageBase;
            g_graphics_context.wGfxBlitDstPage = g_graphics_context.wVgaPage2Base;
            gfx_present_dispatch(0, 0, 0x140, 200);
            palette_fade_in(0, 0x100, -1, 0);
            do_cutscene = 0;
        }
        menupage_draw_entries(page->pEntries, page->wEntry_count, page->rect.x, page->rect.y);
        menupage_draw(page);
        screen_frame_present();
    }
    screen_cursor_show_busy();
    menupage_free(page);
    cache_release(chunk_ptr);
    g_pPalQueuedForFlip = palette_result;
    font_activate(g_wGameFontSlot);
    g_graphics_context.wGfxBlitDstPage = g_wVgaScratchPageBase;
    resblit_load_pal_or_stream("Z01L.SCR");
}

#pragma option -O-l

void far gmain_parse_cmdline_sound_flag(int argc, char **argv) {
    int i;
    char *arg;

    for (i = 1; i < argc; i++) {
        if (*(arg = argv[i]) == '-' || *(arg = argv[i]) == '/') {
            switch (*++arg) {
            case 'S':
            case 's':
                g_sound_driver = (int)*++arg - 0x30;
            }
        }
    }
}

#pragma option -Ol

void far main(int argc, char **argv) {
    register int mode;

    mode = 6;
    parse_krondor_cfg();
    gmain_parse_cmdline_sound_flag(argc, argv);
    boot_subsystems_init();
    if (g_engine_prefs != (EnginePrefs *)0x0) {
        if (g_engine_prefs->flags & 8) {
            gmain_play_intro_animation();
        }
    }

    /* Menu/chapter dispatch loop. mode==1 is the loop's exit sentinel. */
    while (mode != 1) {
        if (mode == 6) {
            mode = mainmenu_save_main_menu(0);
        }
        if (mode == 2) {
            gmain_play_chapter_cutscene(1, 1, 1);
            goto dispatch;
        }
        if (mode == 3)
            goto dispatch;
        if (mode == 4) {
            gmain_restart_from_save_flow();
            goto dispatch;
        }
        if (mode == 5) {
            gmain_play_chapter_cutscene(g_nChapterAtLoopExit, 2, 1);
            if (g_nChapterAtLoopExit == 9) {
                mainmenu_save_slot_exists();
                mode = 6;
                continue;
            }
            gmain_play_chapter_cutscene(g_nChapterAtLoopExit + 1, 1, 1);
            goto dispatch;
        }
        if (mode != 7)
            break;
        gmain_play_chapter_cutscene(g_nChapterAtLoopExit, 3, 1);

    dispatch:
        mode = gmain_start_dispatch(mode);
    }
    boot_main_menu_resources_free();
}
