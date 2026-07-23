#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <ctype.h>
#include <dir.h>
#include <io.h>

#include "globals.h"
#include "SRC/GEN/GFXCTX.H"
#include "SRC/R3D/SCENE/WORLDHIT.H"
#include "SRC/SYS/SYSLOWIO.H"
#include "structs.h"
#include "SRC/SCREENS/MAINMENU.H"
#include "SRC/IO/IO.H"
#include "SRC/SYS/MEM.H"
#include "SRC/AUDIO/ENGINE/AUDIO.H"
#include "SRC/GFX/FONT/FONT.H"
#include "SRC/GFX/SPRITE/RESBLIT.H"
#include "SRC/GFX/DRIVER/PALDRV.H"
#include "SRC/GFX/RASTER/PRESENT.H"
#include "SRC/INPUT/KEYBOARD.H"
#include "SRC/STREAM/RESLOAD/IMGLOAD.H"
#include "SRC/INPUT/MOUSE.H"
#include "SRC/GFX/SPRITE/SPRTHNKS.H"
#include "SRC/GAME/GMAIN.H"
#include "SRC/GFX/SCREEN/SCREEN.H"
#include "SRC/UI/MENUPAGE.H"
#include "SRC/GFX/PALETTE/PALETTE.H"
#include "SRC/GAME/SAVEGAME.H"
#include "SRC/GAME/GSTATE.H"
#include "SRC/R3D/VIS/PROXSCAN.H"
#include "SRC/UI/UIWIDGET.H"
#include "SRC/UI/DLGWIDG.H"
#include "SRC/UI/NAMEDTBL.H"
#include "SRC/UI/LISTWDG.H"
#include "SRC/DIALOG/DIALOG.H"
#include "SRC/WORLD/ACTOR/ACTSPAWN.H"
#include "SRC/COMBAT/ARENA/COMBAT.H"
#include "SRC/SCREENS/FMAP.H"
#include "SRC/WORLD/MOVE/WORLDMOV.H"
#include "SRC/WORLD/ZONE/CZONE.H"
#include "SRC/WORLD/ZONE/ZONE.H"
#include "SRC/GAME/CFGPARSE.H"
#include "defines.h"

EnginePrefs *g_engine_prefs = {0};
int g_nMenuReentering = 0;
unsigned short g_wSaveSlotDirValid = 0x0000;
unsigned short g_wSaveFileValid = 0x0000;
unsigned short g_wMenuCursorPreset = 0x0001;

unsigned short g_wCurrentSaveSlotKey;
unsigned short g_wCurrentSaveFileKey;
int g_wBookmarkFmapX;
int g_wBookmarkFmapY;
unsigned short g_wBookmarkCompassIcon;
char g_szSaveSlotDirName_51cc[13];
unsigned char g_abSaveFileHeader[90];

int mainmenu_save_cfg_load_settings(void) {
    BakFile *stream;

    g_engine_prefs = galloc_safe_zcalloc(5);
    if (g_engine_prefs != (EnginePrefs *)0x0) {
        stream = bak_fopen("KRONDOR.CFG", "rb");
        if (stream == (BakFile *)0x0) {
#ifdef V102CD
            if (g_cd_present != 0) {
                stream = bak_fopen("CDEFAULT.DAT", "rb");
            } else {
                stream = bak_fopen("DEFAULT.DAT", "rb");
            }
#else
            stream = bak_fopen("DEFAULT.DAT", "rb");
#endif
        }
        bak_fread(g_engine_prefs, 5, 1, stream);
        bak_fclose(stream);
        mainmenu_save_request_load_game();
        return 1;
    }
    return 0;
}

void mainmenu_save_cfg_free_settings(void) {
    if (g_engine_prefs != 0) {
        galloc_zfree(g_engine_prefs);
    }
}

int mainmenu_save_main_menu(int reentering) {
    int bRunning = 1;
    int bFirstFade = 1;
    int bFullRender = 1;
    int bRecheckSaves = 1;
    unsigned short wRedraw = 0;
    unsigned int overlay;
    int track_id;
    unsigned int key;
    int result;
    unsigned char far *pPalSaved;
    unsigned char far *pal;
    MenuPage *page;

    pal = (unsigned char far *)0;
    g_nMenuReentering = reentering;

    track_id = audio_music_play(0x3f7);
    if (reentering != 0) {
        page = menupage_load("req_opt1.dat");
    } else {
        audio_music_play(0x3f7);
        font_activate(g_wGameFontSlot);
        pal = chunk_load_into_slot("options.pal");
        g_pPalQueuedForFlip = (unsigned char far *)0;
        palette_set(pal);
        g_graphics_context.wGfxBlitDstPage = g_wVgaScratchPageBase;
        resblit_load_pal_or_stream("z01l.scr");
        page = menupage_load("req_opt0.dat");
    }
    menupage_begin(page);

    while (bRunning != 0) {
        if (bFullRender != 0) {
            pPalSaved = g_pPalQueuedForFlip;
            g_pPalQueuedForFlip = (unsigned char far *)0;
            if (g_wMenuCursorPreset == 0) {
                screen_cursor_show_busy();
            }
            if (bFirstFade != 0) {
                palette_fade_out(0, 0x100, -1, 0);
            } else {
                palette_fade_out(0, 0x100, 4, 0);
            }
            if (g_wMenuCursorPreset != 0) {
                g_wMenuCursorPreset = 0;
            } else {
                screen_cursor_restore_shape();
            }
            screen_cursor_hide();
            palette_screen_clear_black();
            g_pPalQueuedForFlip = pPalSaved;
            screen_frame_flip();
            palette_set_scaled(0, 0x100, 0, 0);
            screen_cursor_show_busy();
            if (bRecheckSaves != 0) {
                if (mainmenu_save_any_exists() != 0) {
                    page->pEntries[1].wEnable_gate = 0;
                } else {
                    page->pEntries[1].wEnable_gate = 1;
                }
                bRecheckSaves = 0;
            }
            g_graphics_context.wGfxBlitDstPage = g_graphics_context.wGfxBlitSrcPage =
                g_graphics_context.wVgaPage2Base;
            if (reentering != 0) {
                resblit_load_pal_or_stream("options1.scr");
            } else {
                resblit_load_pal_or_stream("options0.scr");
            }
            menupage_draw(page);
            screen_cursor_restore_shape();
            screen_frame_flip();
            g_graphics_context.wGfxBlitSrcPage = g_graphics_context.wVgaFrontPageBase;
            g_graphics_context.wGfxBlitDstPage = g_graphics_context.wVgaPage2Base;
            gfx_present_dispatch(0, 0, 0x140, 200);
            screen_cursor_hide();
            screen_cursor_show_busy();
            if (bFirstFade != 0) {
                palette_fade_in(0, 0x100, -1, 0);
                bFirstFade = 0;
            } else {
                palette_fade_in(0, 0x100, 4, 1);
            }
            screen_cursor_restore_shape();
            bFullRender = 0;
            wRedraw = 0;
        } else {
            g_graphics_context.wGfxBlitDstPage = g_graphics_context.wGfxBlitSrcPage =
                g_graphics_context.wVgaPage2Base;
            if (wRedraw != 0) {
                menupage_draw(page);
            }
            screen_frame_present();
            g_graphics_context.wGfxBlitDstPage = g_graphics_context.wGfxBlitSrcPage =
                g_graphics_context.wVgaPage2Base;
            if (wRedraw != 0) {
                menupage_draw(page);
                wRedraw = 0;
            }
        }

        key = menupage_run(page, &wRedraw);
        if (key != 0) {
            overlay = (menupage_state_0e7c() == 2);
        }

        switch (key) {
        case 0x31:
            if (overlay != 0) {
                dialog_play_record(0x73, 1);
                continue;
            }
            if (mainmenu_save_confirm_abort() != 0) {
                result = 2;
                bRunning = 0;
            }
            continue;
        case 0x13:
            if (overlay != 0) {
                dialog_play_record(0x74, 1);
                continue;
            }
            if (mainmenu_save_load_game_dialog() != 0) {
                result = 3;
                bRunning = 0;
                continue;
            }
            bFullRender = 1;
            continue;
        case 0x1f:
            if (overlay != 0) {
                dialog_play_record(0x75, 1);
                continue;
            }
            if (mainmenu_save_save_game_dialog() != 0) {
                result = 0;
                bRunning = 0;
                continue;
            }
            bRecheckSaves = 1;
            bFullRender = 1;
            continue;
        case 0x19:
            if (overlay != 0) {
                dialog_play_record(0x76, 1);
                continue;
            }
            if (mainmenu_save_prefs_menu_run() != 0 && reentering != 0) {
                result = 0;
                bRunning = 0;
                continue;
            }
            bFullRender = 1;
            continue;
        case 0x2e:
            if (overlay != 0) {
                dialog_play_record(0x77, 1);
                continue;
            }
            if (reentering != 0) {
                mainmenu_save_party_to_tmp();
                result = 4;
                bRunning = 0;
                continue;
            }
            gmain_restart_from_save_flow();
            bFullRender = 1;
            continue;
        case 0x20:
            if (overlay != 0) {
                dialog_play_record(0x78, 1);
                continue;
            }
            if (dialog_play_record(0x6e, 1) == 0) {
                screen_cursor_show_busy();
                palette_fade_out(0, 0x100, 2, 1);
                palette_screen_clear_black();
                screen_cursor_restore_shape();
                result = 1;
                bRunning = 0;
            }
            continue;
        case 0x12:
            if (overlay != 0) {
                dialog_play_record(0x79, 1);
                continue;
            }
            result = 0;
            bRunning = 0;
            continue;
        case 0x01:
            if (reentering != 0) {
                result = 0;
                bRunning = 0;
            }
            continue;
        case 0x2f:
            mainmenu_save_show_ctrd_modal();
            bFullRender = 1;
            continue;
        default:
            continue;
        }
    }

    menupage_end(page);
    menupage_free(page);
    if (pal != (unsigned char far *)0) {
        cache_release(pal);
    }
    if (reentering != 0 && result != 1 && result != 2 && result != 3 && result != 4) {
        audio_music_play(track_id);
    }
    return result;
}

int mainmenu_save_confirm_abort(void) {
    if (g_nMenuReentering != 0 && dialog_play_record(0x6f, 1) != 0) {
        return 0;
    }
    return 1;
}

int mainmenu_save_load_game_dialog(void) {
    MenuPage *page;
    int *label_tbl;
    int need_slot_sel;
    int need_file_sel;
    int load_ok;
    int running;
    int slot_dirty;
    int redraw_slot;
    int first_draw;
    int file_dirty;
    int labels_dirty;
    int page_active;
    unsigned short slot_key;
    unsigned short file_key;
    unsigned short file_click;
    int nav_a;
    int nav_b;
    int nav_c;
    int action_key;
    char *slot_text;
    char *file_text;
    unsigned long click_ticks;
    ListWidget *slot_list;
    ListWidget *file_list;

    need_slot_sel = 1;
    need_file_sel = 1;
    load_ok = 0;
    running = 1;
    slot_dirty = 1;
    redraw_slot = 1;
    first_draw = 1;
    file_dirty = 0;
    labels_dirty = 0;
    nav_a = 0;
    nav_b = 0;
    nav_c = 0;
    click_ticks = 0;

    page = menupage_load("req_load.dat");
    menupage_begin(page);
    slot_list = listwidget_attach(0x21, 0x31, 0x55, 5, 0x14, page, 0);
    file_list = listwidget_attach(0x7d, 0x31, 0x9f, 5, 0x15, page, 1);
    label_tbl = namedtbl_load("lbl_load.dat");

    while (running) {

        if (redraw_slot || slot_dirty) {
            while (listwidget_remove_item(file_list, 0))
                ;
        }
        if (slot_dirty) {
            while (listwidget_remove_item(slot_list, 0))
                ;
        }
        if (slot_dirty) {
            mainmenu_save_enum_directories(slot_list);
            if (need_slot_sel) {
                if (g_wSaveSlotDirValid) {
                    int sel = mainmenu_savelist_find_by_text(slot_list, g_szSaveSlotDirName_51cc);
                    if (sel != -1)
                        listwidget_set_selection(slot_list, sel);
                }
                need_slot_sel = 0;
            }
            redraw_slot = 1;
            slot_dirty = 0;
        }
        if (redraw_slot) {
            if (listwidget_get_current_entry(slot_list, &slot_text, &slot_key))
                mainmenu_save_enum_files_slot(file_list, slot_text, slot_key);
            if (need_file_sel) {
                if (g_wSaveFileValid) {
                    int sel = mainmenu_savelist_find_by_name(file_list, (char *)g_abSaveFileHeader);
                    if (sel != -1)
                        listwidget_set_selection(file_list, sel);
                }
                need_file_sel = 0;
            }
            file_dirty = 1;
            redraw_slot = 0;
            nav_a = 0;
            nav_b = 0;
            nav_c = 0;
        }

        if (first_draw) {

            screen_cursor_show_busy();
            g_graphics_context.wGfxBlitDstPage = g_graphics_context.wGfxBlitSrcPage =
                g_graphics_context.wVgaPage2Base;
            resblit_load_pal_or_stream("options2.scr");
            menupage_draw(page);
            listwidget_draw(slot_list);
            listwidget_draw(file_list);
            namedtbl_labels_draw_all(label_tbl);
            palette_fade_out(0, 0x100, 4, 0);
            screen_cursor_restore_shape();
            screen_frame_flip();
            g_graphics_context.wGfxBlitSrcPage = g_graphics_context.wVgaFrontPageBase;
            g_graphics_context.wGfxBlitDstPage = g_graphics_context.wVgaPage2Base;
            gfx_present_dispatch(0, 0, 0x140, 0xc8);
            screen_cursor_hide();
            screen_cursor_show_busy();
            palette_fade_in(0, 0x100, 4, 1);
            screen_cursor_restore_shape();
            first_draw = 0;
            file_dirty = 0;
            labels_dirty = 0;
        } else {

            g_graphics_context.wGfxBlitDstPage = g_graphics_context.wGfxBlitSrcPage =
                g_graphics_context.wVgaPage2Base;
            if (file_dirty) {
                menupage_draw(page);
                listwidget_draw(slot_list);
                listwidget_draw(file_list);
            }
            if (labels_dirty)
                namedtbl_labels_draw_all(label_tbl);
            screen_frame_present();
            g_graphics_context.wGfxBlitDstPage = g_graphics_context.wGfxBlitSrcPage =
                g_graphics_context.wVgaPage2Base;
            if (file_dirty) {
                menupage_draw(page);
                listwidget_draw(slot_list);
                listwidget_draw(file_list);
                file_dirty = 0;
            }
            if (labels_dirty) {
                namedtbl_labels_draw_all(label_tbl);
                labels_dirty = 0;
            }
        }

        page_active = 0;
        action_key = menupage_run(page, (unsigned short *)&file_dirty);
        if (action_key) {
            page_active = (menupage_state_0e7c() == 2) ? 1 : 0;
        } else {

            if (listwidget_handle_click(slot_list, 0)) {
                action_key = 0xc5;
            } else if (listwidget_handle_click(file_list, &file_click)) {
                if (file_click != 0) {
                    if (nav_a != 0 || nav_b != 0 || nav_c != 0) {
                        if (nav_b == 0)
                            goto dispatch;
                        nav_a = 0;
                        nav_b = 0;
                        nav_c = 1;
                        goto dispatch;
                    }
                }
                click_ticks = g_timer_ticks;
                nav_a = 1;
                nav_b = 0;
                nav_c = 0;
                action_key = 0xc4;
            } else {
                if (nav_a != 0) {
                    nav_a = 0;
                    nav_b = 1;
                    nav_c = 0;
                    goto dispatch;
                }
                if (nav_c != 0) {
                    if (click_ticks <= g_timer_ticks && click_ticks + 0x15 >= g_timer_ticks) {
                        action_key = 0xc1;
                        goto dispatch;
                    }
                    nav_a = 0;
                    nav_b = 0;
                    nav_c = 0;
                    action_key = 0xc4;
                    goto dispatch;
                }
                if (nav_b != 0) {
                    if (click_ticks > g_timer_ticks || click_ticks + 0x15 < g_timer_ticks) {
                        nav_b = 0;
                    }
                }
            }
        }

    dispatch:
        switch (action_key) {
        case 0x48:
            if (key_is_down(0x1d)) {
                redraw_slot = listwidget_scroll_up(slot_list);
            } else {
                file_dirty = listwidget_scroll_up(file_list);
            }
            break;
        case 0x50:
            if (key_is_down(0x1d)) {
                redraw_slot = listwidget_scroll_down(slot_list);
            } else {
                file_dirty = listwidget_scroll_down(file_list);
            }
            break;
        case 0xc5:
            redraw_slot = 1;
            break;
        case 0xc4:
            file_dirty = 1;
            break;
        case 0x1c:
        case 0xc1:
            if (page_active) {
                dialog_play_record(0x88, 1);
                file_dirty = 1;
            } else {

                if (listwidget_get_current_entry(file_list, 0, &file_key)) {
                    g_wCurrentSaveFileKey = file_key;
                    load_ok = 1;
                    running = 0;
                } else {
                    dialog_play_record(0x8b, 1);
                }
            }
            break;
        case 0x01:
        case 0xc0:
            if (page_active) {
                dialog_play_record(0x89, 1);
            } else {
                running = 0;
            }
            break;
        }
    }

    g_wSaveSlotDirValid = 1;
    listwidget_get_current_entry(slot_list, &slot_text, &slot_key);
    strcpy(g_szSaveSlotDirName_51cc, slot_text);
    g_wCurrentSaveSlotKey = slot_key;
    if (listwidget_get_current_entry(file_list, &file_text, &file_key)) {
        strcpy((char *)g_abSaveFileHeader, file_text);
        g_wCurrentSaveFileKey = file_key;
        g_wSaveFileValid = 1;
    } else {
        g_wSaveFileValid = 0;
    }

    namedtbl_free(label_tbl);
    listwidget_destroy(file_list);
    listwidget_destroy(slot_list);
    menupage_end(page);
    menupage_free(page);
    return load_ok;
}

int mainmenu_save_save_game_dialog(void) {

    Dialog *dialog;
    ListWidget *slot_list;

    MenuPage *page;
    ListWidget *file_list;
    int *label_tbl;
    int need_slot_sel;
    int need_file_sel;
    int save_ok;
    int running;
    int slot_dirty;
    int slot_reload;
    int file_dirty;
    int file_reload;
    int first_draw;
    int lbl_dirty;
    int labels_dirty;
    int page_active;
    int slot_key;
    int file_key;
    int name_nonempty;
    unsigned int click_out;
    int dbl_armed;
    int dbl_pending;
    int dbl_single;
    int names_match;
    int dispatch_key;
    char *slot_text;
    char *file_text;
    unsigned long dbl_ticks;
    char sprintf_buf[49];

    int rc;
    int file_nonempty;

    need_slot_sel = 1;
    need_file_sel = 1;
    save_ok = 0;
    running = 1;
    slot_dirty = 1;
    slot_reload = 1;
    file_dirty = 1;
    file_reload = 1;
    first_draw = 1;
    lbl_dirty = 0;
    labels_dirty = 0;
    dbl_armed = 0;
    dbl_pending = 0;
    dbl_single = 0;
    dbl_ticks = 0;

    if (mainmenu_save_games_dir_exists() == 0 && mainmenu_save_games_dir_create() == 0) {
        dialog_play_record(0x86, 1);
        return 0;
    }

    page = menupage_load("req_save.dat");
    menupage_begin(page);
    slot_list = listwidget_attach(0x21, 0x31, 0x55, 5, 0x14, page, 0);
    file_list = listwidget_attach(0x7d, 0x31, 0x9f, 5, 0x15, page, 1);
    dialog = dlgwidget_dialog_load("in_save.dat");
    dlgwidget_dlg_focus_first_wdg(dialog);
    label_tbl = namedtbl_load("lbl_save.dat");

    while (running) {
        if (slot_reload != 0 || slot_dirty != 0) {
            while (listwidget_remove_item(file_list, 0))
                ;
        }
        if (slot_dirty != 0) {
            while (listwidget_remove_item(slot_list, 0))
                ;
        }
        if (slot_dirty != 0) {
            mainmenu_save_enum_directories(slot_list);
            if (need_slot_sel != 0) {
                if (g_wSaveSlotDirValid != 0) {
                    rc = mainmenu_savelist_find_by_text(slot_list, g_szSaveSlotDirName_51cc);
                    if (rc != -1)
                        listwidget_set_selection(slot_list, rc);
                }
                need_slot_sel = 0;
            }
            slot_reload = 1;
            slot_dirty = 0;
        }
        if (slot_reload != 0) {
            if (listwidget_get_current_entry(slot_list, &slot_text, (unsigned short *)&slot_key)) {
                mainmenu_save_enum_files_slot(file_list, slot_text, slot_key);
            }
            if (need_file_sel != 0) {
                if (g_wSaveFileValid != 0) {
                    rc = mainmenu_savelist_find_by_name(file_list, (char *)g_abSaveFileHeader);
                    if (rc != -1)
                        listwidget_set_selection(file_list, rc);
                }
                need_file_sel = 0;
            }
            lbl_dirty = 1;
            slot_reload = 0;
            dbl_armed = 0;
            dbl_pending = 0;
            dbl_single = 0;
        }
        if (file_dirty != 0) {
            if (listwidget_get_current_entry(slot_list, (char **)0, (unsigned short *)0) != 0) {
                page->pEntries[2].wEnable_gate = 0;
                if (listwidget_get_current_entry(file_list, (char **)0, (unsigned short *)0) != 0)
                    page->pEntries[3].wEnable_gate = 0;
                else
                    page->pEntries[3].wEnable_gate = 1;
            } else {
                page->pEntries[2].wEnable_gate = 1;
                page->pEntries[3].wEnable_gate = 1;
            }
            file_dirty = 0;
        }
        if (file_reload != 0) {
            if (listwidget_get_current_entry(slot_list, &slot_text, (unsigned short *)0) != 0) {
                dlgwidget_dialog_focus_widget(dialog, 1);
                dlgwidget_dialog_set_widget_text(dialog, 0, slot_text);
                if (listwidget_get_current_entry(file_list, &file_text, (unsigned short *)0) != 0)
                    dlgwidget_dialog_set_widget_text(dialog, 1, file_text);
                else
                    dlgwidget_dialog_set_widget_text(dialog, 1, "");
            } else {
                dlgwidget_dialog_focus_widget(dialog, 0);
                dlgwidget_dialog_set_widget_text(dialog, 0, "");
                dlgwidget_dialog_set_widget_text(dialog, 1, "");
            }
            file_reload = 0;
        }

        if (first_draw != 0) {
            screen_cursor_show_busy();
            g_graphics_context.wGfxBlitDstPage = g_graphics_context.wGfxBlitSrcPage =
                g_graphics_context.wVgaPage2Base;
            resblit_load_pal_or_stream("options2.scr");
            menupage_draw(page);
            listwidget_draw(slot_list);
            listwidget_draw(file_list);
            namedtbl_labels_draw_all(label_tbl);
            dlgwidget_dialog_render(dialog, 1);
            palette_fade_out(0, 0x100, 4, 0);
            screen_cursor_restore_shape();
            screen_frame_flip();
            g_graphics_context.wGfxBlitSrcPage = g_graphics_context.wVgaFrontPageBase;
            g_graphics_context.wGfxBlitDstPage = g_graphics_context.wVgaPage2Base;
            gfx_present_dispatch(0, 0, 0x140, 200);
            screen_cursor_hide();
            screen_cursor_show_busy();
            palette_fade_in(0, 0x100, 4, 1);
            screen_cursor_restore_shape();
            first_draw = 0;
            lbl_dirty = 0;
        } else {
            g_graphics_context.wGfxBlitDstPage = g_graphics_context.wGfxBlitSrcPage =
                g_graphics_context.wVgaPage2Base;
            if (lbl_dirty != 0) {
                menupage_draw(page);
                listwidget_draw(slot_list);
                listwidget_draw(file_list);
            }
            dlgwidget_dialog_render(dialog, 1);
            if (labels_dirty != 0)
                namedtbl_labels_draw_all(label_tbl);
            screen_frame_present();
            g_graphics_context.wGfxBlitDstPage = g_graphics_context.wGfxBlitSrcPage =
                g_graphics_context.wVgaPage2Base;
            if (lbl_dirty != 0) {
                menupage_draw(page);
                listwidget_draw(slot_list);
                listwidget_draw(file_list);
                lbl_dirty = 0;
            }
            dlgwidget_dialog_render(dialog, 1);
            if (labels_dirty == 0)
                goto skip_labels_reset;
            namedtbl_labels_draw_all(label_tbl);
        }
        labels_dirty = 0;
    skip_labels_reset:

        page_active = 0;
        dispatch_key = menupage_run(page, (unsigned short *)&lbl_dirty);
        if (dlgwidget_text_input_dialog_pump(dialog) != 0) {
            dispatch_key = 0xc1;
        } else if (dispatch_key != 0) {
            page_active = (menupage_state_0e7c() == 2);
            goto dispatch;
        } else if (listwidget_handle_click(slot_list, (unsigned short *)&click_out) != 0) {
            if (click_out != 0)
                file_reload = 1;
            else
                dispatch_key = 0xc5;
            goto dispatch;
        } else if (listwidget_handle_click(file_list, (unsigned short *)&click_out) != 0) {
            if (click_out != 0 && (dbl_armed != 0 || dbl_pending != 0 || dbl_single != 0)) {
                if (dbl_pending != 0) {
                    dbl_armed = 0;
                    dbl_pending = 0;
                    dbl_single = 1;
                }
                goto dispatch;
            }
            dbl_ticks = g_timer_ticks;
            dbl_armed = 1;
            dbl_pending = 0;
            dbl_single = 0;
            dispatch_key = 0xc4;
        } else {
            if (dbl_armed != 0) {
                dbl_armed = 0;
                dbl_pending = 1;
                dbl_single = 0;
                goto dispatch;
            }
            if (dbl_single != 0) {
                names_match = 0;
                if (listwidget_get_current_entry(slot_list, &slot_text, (unsigned short *)0) != 0 &&
                    listwidget_get_current_entry(file_list, &file_text, (unsigned short *)0) != 0) {
                    char *p;
                    dlgwidget_dialog_rstrip_widgets(dialog);
                    p = dlgwidget_dialog_widget_text_ptr(dialog, 0);
                    if (stricmp(p, slot_text) == 0) {
                        p = dlgwidget_dialog_widget_text_ptr(dialog, 1);
                        if (strcmp(p, file_text) == 0)
                            names_match = 1;
                    }
                }
                if (names_match != 0 && dbl_ticks <= g_timer_ticks &&
                    dbl_ticks + 0x15 >= g_timer_ticks) {
                    dispatch_key = 0xc1;
                    goto dispatch;
                }
                dbl_armed = 0;
                dbl_pending = 0;
                dbl_single = 0;
                dispatch_key = 0xc4;
            } else {
                if (dbl_pending != 0 &&
                    (dbl_ticks > g_timer_ticks || dbl_ticks + 0x15 < g_timer_ticks))
                    dbl_pending = 0;
                goto dispatch;
            }
        }

    dispatch:
        switch (dispatch_key) {
        case 0x48:
            if (key_is_down(0x1d) != 0)
                slot_reload = listwidget_scroll_up(slot_list);
            else
                lbl_dirty = listwidget_scroll_up(file_list);
            file_reload = 1;
            continue;

        case 0x50:
            if (key_is_down(0x1d) != 0)
                slot_reload = listwidget_scroll_down(slot_list);
            else
                lbl_dirty = listwidget_scroll_down(file_list);
            file_reload = 1;
            continue;

        case 0xc5:
            file_reload = 1;
            slot_reload = 1;
            continue;

        case 0xc4:
            file_reload = 1;
            lbl_dirty = 1;
            continue;

        case 0xc3:
            if (page_active != 0) {
                dialog_play_record(0x7a, 1);
            } else if (dialog_play_record(0x70, 1) == 0) {
                if (listwidget_get_current_entry(slot_list, &slot_text,
                                                 (unsigned short *)&slot_key) != 0) {
                    sprintf(sprintf_buf, "%s\\%s.G%02d", "GAMES", slot_text, slot_key);
                    if (mainmenu_save_rmdir_recursive(sprintf_buf) == 0)
                        dialog_play_record(0x7f, 1);
                    slot_dirty = 1;
                    file_dirty = 1;
                    file_reload = 1;
                    lbl_dirty = 1;
                    continue;
                } else {
                    dialog_play_record(0x7e, 1);
                }
            }
            lbl_dirty = 1;
            continue;

        case 0xc2:
            if (page_active != 0) {
                dialog_play_record(0x7b, 1);
            } else if (dialog_play_record(0x71, 1) == 0) {
                if (listwidget_get_current_entry(slot_list, &slot_text,
                                                 (unsigned short *)&slot_key) != 0 &&
                    listwidget_get_current_entry(file_list, (char **)0,
                                                 (unsigned short *)&file_key) != 0) {
                    sprintf(sprintf_buf, "%s\\%s.G%02d\\SAVE%02d.GAM", "GAMES", slot_text, slot_key,
                            file_key);
                    remove(sprintf_buf);
                    slot_reload = 1;
                    file_dirty = 1;
                    file_reload = 1;
                    lbl_dirty = 1;
                    continue;
                } else {
                    dialog_play_record(0x87, 1);
                }
            }
            lbl_dirty = 1;
            continue;

        case 0xc1:
            if (page_active != 0) {
                dialog_play_record(0x7c, 1);
                goto redraw_and_loop;
            }
            g_graphics_context.wGfxBlitDstPage = g_graphics_context.wGfxBlitSrcPage =
                g_graphics_context.wVgaPage2Base;
            dlgwidget_dialog_render(dialog, 0);
            screen_frame_present();
            g_graphics_context.wGfxBlitDstPage = g_graphics_context.wGfxBlitSrcPage =
                g_graphics_context.wVgaPage2Base;
            dlgwidget_dialog_render(dialog, 0);
            screen_cursor_show_busy();
            dlgwidget_dialog_rstrip_widgets(dialog);
            slot_text = dlgwidget_dialog_widget_text_ptr(dialog, 0);
            name_nonempty = (*slot_text != '\0');
            if (name_nonempty != 0 && mainmenu_save_filename_validate(slot_text) == 0) {
                dialog_play_record(0x92, 1);
                continue;
            }
            file_text = dlgwidget_dialog_widget_text_ptr(dialog, 1);
            file_nonempty = (*file_text != '\0');
            if (name_nonempty == 0)
                goto report_name_error;
            if (file_nonempty == 0)
                goto report_name_error;

            while (listwidget_remove_item(file_list, 0))
                ;
            rc = mainmenu_savelist_find_by_text(slot_list,
                                                dlgwidget_dialog_widget_text_ptr(dialog, 0));
            if (rc == -1) {
                slot_text = dlgwidget_dialog_widget_text_ptr(dialog, 0);
                slot_key = mainmenu_savelist_nextfree_key(slot_list);
                if (slot_key == -1) {
                    dialog_play_record(0x93, 1);
                    continue;
                }
                sprintf(sprintf_buf, "%s\\%s.G%02d", "GAMES", slot_text, slot_key);
                if (mkdir(sprintf_buf) != 0) {
                    dialog_play_record(0x94, 1);
                    continue;
                }
                while (listwidget_remove_item(slot_list, 0))
                    ;
                mainmenu_save_enum_directories(slot_list);
                rc = mainmenu_savelist_find_by_text(slot_list, slot_text);
            }
            listwidget_set_selection(slot_list, rc);
            if (listwidget_get_current_entry(slot_list, &slot_text, (unsigned short *)&slot_key) !=
                0) {
                mainmenu_save_enum_files_slot(file_list, slot_text, slot_key);
            }
            rc = mainmenu_savelist_find_by_name(file_list,
                                                dlgwidget_dialog_widget_text_ptr(dialog, 1));
            if (rc == -1) {
                file_text = dlgwidget_dialog_widget_text_ptr(dialog, 1);
                file_key = mainmenu_savelist_nextfree_nobm(file_list);
                if (file_key == -1) {
                    dialog_play_record(0x95, 1);
                    continue;
                }
            } else {
                listwidget_set_selection(file_list, rc);
                listwidget_get_current_entry(file_list, &file_text, (unsigned short *)&file_key);
            }
            mainmenu_save_party_to_tmp();
            strcpy((char *)g_abSaveFileHeader, file_text);
            g_wCurrentSaveFileKey = file_key;
            sprintf(sprintf_buf, "%s\\%s.G%02d\\SAVE%02d.GAM", "GAMES", slot_text, slot_key,
                    file_key);
            if (fmap_xy_lookup_for_chapter(&g_wBookmarkFmapX, &g_wBookmarkFmapY) != 0) {
                unsigned int cam_heading = g_world_camera->base.orientation.yaw;
                fmap_farptr_normalize(&cam_heading);
                g_wBookmarkCompassIcon = (cam_heading >> 0xd) << 2;
            } else {
                g_wBookmarkFmapX = g_wBookmarkFmapY = -1;
                g_wBookmarkCompassIcon = 0;
            }
            if (savegame_write(sprintf_buf) != 0)
                goto save_committed;
            dialog_play_record(0x96, 1);
        redraw_and_loop:
            lbl_dirty = 1;
            continue;
        save_committed:
            save_ok = 1;
            running = 0;
            goto commit_slot_selection;

        report_name_error:

            if (name_nonempty != 0) {
                dialog_play_record(0x97, 1);
                dlgwidget_dialog_focus_widget(dialog, 1);
            } else {
                if (file_nonempty != 0)
                    dialog_play_record(0x98, 1);
                else
                    dialog_play_record(0x99, 1);
                dlgwidget_dialog_focus_widget(dialog, 0);
            }
            continue;

        commit_slot_selection:
            if (running == 0) {
                if (listwidget_get_current_entry(slot_list, &slot_text,
                                                 (unsigned short *)&slot_key) != 0) {
                    strcpy(g_szSaveSlotDirName_51cc, slot_text);
                    g_wCurrentSaveSlotKey = slot_key;
                    g_wSaveSlotDirValid = 1;
                    g_wSaveFileValid = 1;
                } else {
                    g_wSaveSlotDirValid = 0;
                    g_wSaveFileValid = 0;
                }
            }
            continue;

        case 0x01:
        case 0xc0:
            if (page_active != 0) {
                dialog_play_record(0x7d, 1);
                continue;
            }
            if (listwidget_get_current_entry(slot_list, &slot_text, (unsigned short *)&slot_key) !=
                0) {
                strcpy(g_szSaveSlotDirName_51cc, slot_text);
                g_wCurrentSaveSlotKey = slot_key;
                g_wSaveSlotDirValid = 1;
                if (listwidget_get_current_entry(file_list, &file_text,
                                                 (unsigned short *)&file_key) != 0) {
                    strcpy((char *)g_abSaveFileHeader, file_text);
                    g_wCurrentSaveFileKey = file_key;
                    g_wSaveFileValid = 1;
                } else {
                    g_wSaveFileValid = 0;
                }
            } else {
                g_wSaveSlotDirValid = 0;
                g_wSaveFileValid = 0;
            }
            running = 0;
            continue;

        default:
            continue;
        }
    }

    namedtbl_free(label_tbl);
    dlgwidget_dialog_destroy_bgs(dialog);
    listwidget_destroy(file_list);
    listwidget_destroy(slot_list);
    menupage_end(page);
    menupage_free(page);
    return save_ok;
}

int mainmenu_save_prefs_menu_run(void) {
    EnginePrefs prefs;
    int *labels;
    int ret_value;
    int loop_continue;
    int big_render;
    int dirty_checkbox;
    int dirty_screen;
    int dirty_text;
    int dirty_audio;
    int dirty_combat;
    unsigned short menupage_redraw;
    int labels_redraw;
    int overlay_mode;
    int file_error;
    unsigned int event_code;
    MenuPage *page;
    MenuEntry *pe;
    unsigned int i;
    BakFile *fp;

    prefs = *g_engine_prefs;
    ret_value = 0;
    loop_continue = 1;
    big_render = 1;
    dirty_checkbox = 1;
    dirty_screen = 1;
    dirty_text = 1;
    dirty_audio = 1;
    dirty_combat = 1;
    menupage_redraw = 0;
    labels_redraw = 0;
    file_error = 0;
    g_nSkyHorizonRowCached = 0xffff;
    page = menupage_load("req_pref.dat");
    menupage_begin(page);
    labels = namedtbl_load("lbl_pref.dat");

    while (loop_continue != 0) {
        if (dirty_checkbox != 0) {

            page->pEntries[0x10].wSub_state = prefs.flags & 1;
            page->pEntries[0x11].wSub_state = prefs.flags & 2;
            page->pEntries[0x12].wSub_state = prefs.flags & 4;
#ifdef V102CD
            if (g_cd_present == 0)
                prefs.flags &= 0xef;
            page->pEntries[0x13].wSub_state = prefs.flags & 0x10;
            page->pEntries[0x14].wSub_state = prefs.flags & 8;
#else
            page->pEntries[0x13].wSub_state = prefs.flags & 8;
#endif
            dirty_checkbox = 0;
        }
        if (dirty_screen != 0) {
            pe = page->pEntries + 3;
            i = 0;
            do {
                pe->wSub_state = (unsigned int)(prefs.step_speed == i);
                i++;
                pe++;
            } while ((int)i < 3);
            dirty_screen = 0;
        }
        if (dirty_text != 0) {
            pe = page->pEntries + 6;
            i = 0;
            do {
                pe->wSub_state = (unsigned int)(prefs.combat_step_speed == i);
                i++;
                pe++;
            } while ((int)i < 3);
            dirty_text = 0;
        }
        if (dirty_audio != 0) {
            pe = page->pEntries + 9;
            i = 0;
            do {
                pe->wSub_state = (unsigned int)(prefs.detail_level == i);
                i++;
                pe++;
            } while ((int)i < 4);
            dirty_audio = 0;
        }
        if (dirty_combat != 0) {
            pe = page->pEntries + 0xd;
            i = 0;
            do {
                pe->wSub_state = (unsigned int)(prefs.text_speed == i);
                i++;
                pe++;
            } while ((int)i < 3);
            dirty_combat = 0;
        }

        if (big_render != 0) {
            screen_cursor_show_busy();
            g_graphics_context.wGfxBlitDstPage = g_graphics_context.wGfxBlitSrcPage =
                g_graphics_context.wVgaPage2Base;
            resblit_load_pal_or_stream("options2.scr");
            menupage_draw(page);
            namedtbl_labels_draw_all(labels);
            palette_fade_out(0, 0x100, 4, 0);
            screen_cursor_restore_shape();
            screen_frame_flip();
            g_graphics_context.wGfxBlitSrcPage = g_graphics_context.wVgaFrontPageBase;
            g_graphics_context.wGfxBlitDstPage = g_graphics_context.wVgaPage2Base;
            gfx_present_dispatch(0, 0, 0x140, 200);
            screen_cursor_hide();
            screen_cursor_show_busy();
            palette_fade_in(0, 0x100, 4, 1);
            screen_cursor_restore_shape();
            big_render = 0;
            menupage_redraw = 0;
            labels_redraw = 0;
        } else {
            g_graphics_context.wGfxBlitDstPage = g_graphics_context.wGfxBlitSrcPage =
                g_graphics_context.wVgaPage2Base;
            if (menupage_redraw != 0)
                menupage_draw(page);
            if (labels_redraw != 0)
                namedtbl_labels_draw_all(labels);
            screen_frame_present();
            g_graphics_context.wGfxBlitDstPage = g_graphics_context.wGfxBlitSrcPage =
                g_graphics_context.wVgaPage2Base;
            if (menupage_redraw != 0) {
                menupage_draw(page);
                menupage_redraw = 0;
            }
            if (labels_redraw != 0) {
                namedtbl_labels_draw_all(labels);
                labels_redraw = 0;
            }
        }

        event_code = menupage_run(page, &menupage_redraw);
        if (event_code != 0)
            overlay_mode = (menupage_state_0e7c() == 2);

        if (event_code >= 0xc0 && event_code < 0xc3) {
            prefs.step_speed = (unsigned char)(event_code - 0xc0);
            dirty_screen = 1;
            menupage_redraw = 1;
            continue;
        }
        if (event_code >= 0xc3 && event_code < 0xc6) {
            prefs.combat_step_speed = (unsigned char)(event_code - 0xc3);
            dirty_text = 1;
            menupage_redraw = 1;
            continue;
        }
        if (event_code >= 0xc6 && event_code < 0xca) {
            prefs.detail_level = (unsigned char)(event_code - 0xc6);
            dirty_audio = 1;
            menupage_redraw = 1;
            continue;
        }
        if (event_code >= 0xca && event_code < 0xcd) {
            prefs.text_speed = (unsigned char)(event_code - 0xca);
            dirty_combat = 1;
            menupage_redraw = 1;
            continue;
        }

        switch (event_code) {
        case 0x18:
            if (overlay_mode != 0) {
                dialog_play_record(0x8c, 1);
                break;
            }
            prefs.flags = 0;
            if (page->pEntries[0x10].wSub_state != 0)
                prefs.flags |= 1;
            if (page->pEntries[0x11].wSub_state != 0)
                prefs.flags |= 2;
            if (page->pEntries[0x12].wSub_state != 0)
                prefs.flags |= 4;
#ifdef V102CD
            if (page->pEntries[0x13].wSub_state != 0 && g_cd_present != 0)
                prefs.flags |= 0x10;
            if (page->pEntries[0x14].wSub_state != 0)
                prefs.flags |= 8;
#else
            if (page->pEntries[0x13].wSub_state != 0)
                prefs.flags |= 8;
#endif
            if ((g_engine_prefs->flags & 2) != 0) {
                if (!(prefs.flags & 2))
                    audio_music_fade_out_and_stop();
            } else if ((prefs.flags & 2) != 0) {
                audio_music_fade_in_current();
            }
#ifdef V102CD
            if ((g_engine_prefs->flags & 0x10) != 0) {
                if (!(prefs.flags & 0x10)) {
                    audio_music_fade_out_and_stop();
                    g_engine_prefs->flags &= 0xef;
                    if ((prefs.flags & 2) != 0)
                        audio_music_fade_in_current();
                }
            } else if ((prefs.flags & 0x10) != 0) {
                audio_music_fade_out_and_stop();
                g_engine_prefs->flags |= 0x10;
                if ((prefs.flags & 2) != 0)
                    audio_music_fade_in_current();
            }
#endif
            *g_engine_prefs = prefs;
            if ((fp = bak_fopen("KRONDOR.CFG", "wb")) == (BakFile *)0) {
                file_error = 1;
            } else {
                if (bak_fwrite(g_engine_prefs, 5, 1, fp) != 1)
                    file_error = 1;
                if (bak_fclose(fp) != 0)
                    file_error = 1;
            }
            if (file_error) {
                remove("KRONDOR.CFG");
                dialog_play_record(0x13c, 1);
            }
            if (g_nMenuReentering != 0) {
                screen_cursor_show_busy();
                worldmove_combat_zone_snap_pos();
                worldmove_dat_load();
                worldmove_rgn_chap_trans_apply();
                proxscan_filter_table_load();
                if (g_game_mode != 2)
                    czone_reset_and_reload();
                screen_cursor_restore_shape();
            }
            ret_value = 1;
            loop_continue = 0;
            continue;
        case 0x01:
        case 0x2e:
            if (overlay_mode != 0) {
                dialog_play_record(0x8d, 1);
                break;
            }
            loop_continue = 0;
            continue;
        case 0x20:
            if (overlay_mode != 0) {
                dialog_play_record(0x8e, 1);
                break;
            }
            if (dialog_play_record(0x72, 1) == 0) {
#ifdef V102CD
                if (g_cd_present != 0)
                    fp = bak_fopen("CDEFAULT.DAT", "rb");
                else
                    fp = bak_fopen("DEFAULT.DAT", "rb");
#else
                fp = bak_fopen("DEFAULT.DAT", "rb");
#endif
                bak_fread(&prefs, 5, 1, fp);
                bak_fclose(fp);
                dirty_checkbox = 1;
                dirty_screen = 1;
                dirty_text = 1;
                dirty_audio = 1;
                dirty_combat = 1;
            }
            continue;
#ifdef V102CD
        case 0xd1:
            if (g_cd_present != 0)
                prefs.flags ^= 0x10;
            continue;
#endif
        }
    }

    namedtbl_free(labels);
    menupage_end(page);
    menupage_free(page);
    return ret_value;
}

int mainmenu_save_rmdir_recursive(char *dir_path) {
    struct ffblk dta;
    char glob_path[50];
    int rc;

    sprintf(glob_path, "%s\\*.*", dir_path);
    rc = findfirst(glob_path, &dta, 0);
    while (rc == 0) {
        sprintf(glob_path, "%s\\%s", dir_path, dta.ff_name);
        remove(glob_path);
        rc = findnext(&dta);
    }
    return rmdir(dir_path) == 0;
}

int mainmenu_save_filename_validate(char *filename) {

    static char szForbiddenChars[] = "*+={[}]|\\:;\"<,>.?/ ";
    char *p;
    char *bad;

    for (p = filename; *p != '\0'; p++) {
        for (bad = szForbiddenChars; *bad != '\0'; bad++) {
            if (*p == *bad) {
                return 0;
            }
        }
    }
    if (stricmp(filename, "CON") == 0)
        return 0;
    if (stricmp(filename, "AUX") == 0)
        return 0;
    if (stricmp(filename, "NUL") == 0)
        return 0;
    if (strlen(filename) == 4) {
        if (isdigit(filename[3])) {
            if (strnicmp(filename, "LPT", 3) == 0)
                return 0;
            if (strnicmp(filename, "COM", 3) == 0)
                return 0;
        }
    }
    return 1;
}

void far mainmenu_save_show_ctrd_modal(void) {
    ImageRecord **record;
    int textWidth;

    record = resblit_load_asset_table("cret.bmx", 0);
    g_graphics_context.wGfxBlitDstPage = g_graphics_context.wVgaPage2Base;
    g_graphics_context.bClip_enabled = '\0';
    uiwidget_panel_draw_inset(0x6e, 0x36, 100, 0xc, 0xa9);
    textWidth = font_text_width_ds(g_pszCombatModalTitle);
    uiwidget_draw_text_shadowed_dflt(g_pszCombatModalTitle, 0xaa, 0xae, 0xa0 - (textWidth >> 1),
                                     0x38);
    if (record != (ImageRecord **)0x0) {
        blit_sprite_indirect((unsigned short)*record, 0xa0 - ((*record)->nWidth >> 1), 100, 0);
    }
    screen_frame_present();
    while (combat_arena_wait_confirm_cancel() == 0)
        ;
    free_image_record(record);
    return;
}

int mainmenu_save_games_dir_exists(void) {
    if (chdir("GAMES") != 0) {
        return 0;
    }
    if (!chdir("..")) {
    }
    return 1;
}

int mainmenu_save_games_dir_create(void) {
    char szPath[50];

    if (mkdir("GAMES") == 0) {
        sprintf(szPath, "%s\\%s", "GAMES", "SAVES.G01");
        mkdir(szPath);
        return 1;
    }
    return 0;
}

int mainmenu_save_any_exists(void) {
    int outer_r;
    int inner_r;
    unsigned int slotKey;
    int saveId;
    int state;
    char slotName[14];
    char slotDta[30];
    char fileName[14];
    char fileDta[30];
    char slotBase[50];
    char filePath[90];

    if (mainmenu_save_games_dir_exists() != 0) {
        sprintf(slotBase, "%s\\*.G??", "GAMES");
        outer_r = findfirst(slotBase, slotDta, 0x10);
        while (outer_r == 0) {
            if (mainmenu_save_parse_filename(slotName, slotBase, (int *)&slotKey) != 0) {
                sprintf(filePath, "%s\\%s\\SAVE??.GAM", "GAMES", slotName);
                inner_r = findfirst(filePath, fileDta, 0);
                while (inner_r == 0) {
                    if (mainmenu_save_parse_read_title(fileName, filePath, &saveId, slotBase,
                                                       slotKey, &state) != 0) {
                        return 1;
                    }
                    inner_r = findnext(fileDta);
                }
            }
            outer_r = findnext(slotDta);
        }
    }
    return 0;
}

void far mainmenu_save_bookmark(void) {
    unsigned int key;
    char path[50];
    unsigned int heading;

    if (g_wSaveSlotDirValid != 0) {
        if (g_cfgBookmarkVerify) {
            dialog_input_wait_release(0, 1);
            dialog_play_record(0x14c, 0);
            do {
                screen_frame_present();
                key = kbhit_read() >> 8;
                if (g_mouse_installed != '\0') {
                    if (mouse_button_pressed(0) != 0) {
                        key = 0x1c;
                    } else {
                        if (mouse_button_pressed(1) != 0) {
                            key = 1;
                        }
                    }
                }
            } while (key == 0);
            if (((key != 0x1c) && (key != 0x4c)) && (key != 0x52)) {
                dialog_play_record(0x14d, 0);
                return;
            }
            dialog_play_record(0x14e, 0);
        }
        screen_cursor_show_busy();
        mainmenu_save_party_to_tmp();
        sprintf((char *)g_abSaveFileHeader, "Copied Bookmark");
        sprintf(path, "%s\\%s.G%02d\\SAVE00.GAM", "GAMES", g_szSaveSlotDirName_51cc,
                g_wCurrentSaveSlotKey);
        if (fmap_xy_lookup_for_chapter(&g_wBookmarkFmapX, &g_wBookmarkFmapY) != 0) {
            heading = g_world_camera->base.orientation.yaw;
            fmap_farptr_normalize(&heading);
            g_wBookmarkCompassIcon = (heading >> 0xd) << 2;
        } else {
            g_wBookmarkFmapX = g_wBookmarkFmapY = -1;
            g_wBookmarkCompassIcon = 0;
        }
        if (savegame_write(path) != 0) {
            g_wSaveFileValid = 0;
            return;
        }
        dialog_play_record(0x90, 1);
        return;
    }
    dialog_play_record(0x8f, 1);
    return;
}

void mainmenu_save_party_to_tmp(void) {
    int i;

    zone_savegame_snap_world_state();
    g_wLastTempWriteRecordKind = 0;

    gstate_temp_file_write_at((unsigned char far *)&g_gameState, 0L, 0xad7);
    g_gameState.shared_inventory->needsFlush = TRUE;
    actorspawn_persist_to_temp(g_gameState.shared_inventory);
    g_gameState.ground_pile->needsFlush = TRUE;
    actorspawn_persist_to_temp(g_gameState.ground_pile);
    for (i = 0; i < 6; i++) {
        g_gameState.party_members[i].actor_record->needsFlush = TRUE;
        actorspawn_persist_to_temp(g_gameState.party_members[i].actor_record);
    }
}

int mainmenu_save_file_read_header(char *path, void *sig_block, int *ds_state_1, int *ds_state_2,
                                   int *ds_state_3, int *ds_state_4) {
    BakFile *stream;
    register int ok;
    int version;

    ok = 1;
    stream = bak_fopen(path, "rb");
    if (stream != (BakFile *)0x0) {
        if (!(bak_fread(sig_block, 1, 0x5a, stream) == 0x5a &&
              bak_fread(ds_state_1, 2, 1, stream) == 1 &&
              bak_fread(ds_state_2, 2, 1, stream) == 1 &&
              bak_fread(ds_state_3, 2, 1, stream) == 1 &&
              bak_fread(ds_state_4, 2, 1, stream) == 1 && bak_fread(&version, 2, 1, stream) == 1 &&
              version == 0x16))
            ok = 0;
        if (!bak_fclose(stream))
            return ok;
    }
    ok = 0;
    return ok;
}

int mainmenu_save_scan_highest_slot(void) {
    int highest;
    int state;
    int save_id;
    char title[14];
    char dta[30];
    char path[90];
    int rc;

    highest = 1;
    if (g_wSaveSlotDirValid != 0) {
        sprintf(path, "%s\\%s.G%02d\\SAVE??.GAM", "GAMES", g_szSaveSlotDirName_51cc,
                g_wCurrentSaveSlotKey);
        rc = findfirst(path, (struct ffblk *)dta, 0);
        while (rc == 0) {
            if (mainmenu_save_parse_read_title(title, path, &save_id, g_szSaveSlotDirName_51cc,
                                               g_wCurrentSaveSlotKey, &state)) {
                if (state > highest) {
                    highest = state;
                }
            } else if (mainmenu_save_slot_is_at_cap(title)) {
                highest = 10;
                break;
            }
            rc = findnext((struct ffblk *)dta);
        }
    }
    if (g_nMenuReentering != 0 && g_gameState.nChapter > highest) {
        highest = g_gameState.nChapter;
    }
    return highest;
}

int mainmenu_save_slot_is_at_cap(char *entry) {
    int saveId;
    char numStr[50];

    strcpy(numStr, entry + 4);
    numStr[2] = '\0';
    if (isdigit(numStr[0]) && isdigit(numStr[1])) {
        saveId = atoi(numStr);
        if (saveId == 21)
            return 1;
    }
    return 0;
}

void mainmenu_save_slot_exists(void) {
    char local[90];
    BakFile *stream;

    if (g_wSaveSlotDirValid != 0) {
        sprintf(local, "%s\\%s.G%02d\\SAVE%02d.GAM", "GAMES", g_szSaveSlotDirName_51cc,
                g_wCurrentSaveSlotKey, 0x15);
        stream = bak_fopen(local, "wb");
        if (stream != 0) {
            bak_fclose(stream);
        }
    }
}

void mainmenu_save_request_load_game(void) {
    MenuPage *page;
    ListWidget *list;
    unsigned short slotKey;
    char *slotText;

    if (mainmenu_save_games_dir_exists() == 0)
        goto done;
    page = menupage_load("req_save.dat");
    menupage_begin(page);
    list = listwidget_attach(0x21, 0x31, 0x55, 5, 0x14, page, 0);
    mainmenu_save_enum_directories(list);
    if (listwidget_get_current_entry(list, &slotText, &slotKey) != 0) {
        strcpy(g_szSaveSlotDirName_51cc, slotText);
        g_wCurrentSaveSlotKey = slotKey;
        g_wSaveSlotDirValid = 1;
    }
    listwidget_destroy(list);
    menupage_end(page);
    menupage_free(page);
done:;
}

int mainmenu_save_enum_directories(ListWidget *list) {
    unsigned short slotKey;
    struct ffblk dta;
    char local_path[50];
    int rc;

    if (list == (ListWidget *)0)
        goto fail;
    sprintf(local_path, "%s\\*.G??", "GAMES");
    rc = findfirst(local_path, &dta, 0x10);
    while (rc == 0) {
        if (mainmenu_save_parse_filename(dta.ff_name, local_path, (int *)&slotKey))
            mainmenu_savelist_insert_sorted(list, local_path, slotKey);
        rc = findnext(&dta);
    }
    return 1;
fail:
    return 0;
}

int mainmenu_save_parse_filename(char *filename, char *out_name, int *out_slot) {
    for (; *filename != '\0'; filename++, out_name++) {
        if (*filename == '.') {
            if ((((unsigned char *)_ctype)[filename[2] + 1] & _IS_DIG) == 0) {
                return 0;
            }
            if ((((unsigned char *)_ctype)[filename[3] + 1] & _IS_DIG) == 0) {
                return 0;
            }
            *out_name = '\0';
            filename += 2;
            *out_slot = atoi(filename);
            if (*out_slot < 1 || *out_slot > 20) {
                return 0;
            }
            return 1;
        }
        *out_name = *filename;
    }
    return 0;
}

int mainmenu_save_enum_files_slot(ListWidget *list, char *slot_name, int slot_id) {
    unsigned short key;
    int state;
    char title[14];
    char dta[30];
    char path[90];
    int rc;

    if (!list)
        goto fail;
    sprintf(path, "%s\\%s.G%02d\\SAVE??.GAM", "GAMES", slot_name, slot_id);
    rc = findfirst(path, (struct ffblk *)dta, 0);
    while (rc == 0) {
        if (mainmenu_save_parse_read_title(title, path, (int *)&key, slot_name, slot_id, &state))
            mainmenu_savelist_insert_sorted(list, path, key);
        rc = findnext((struct ffblk *)dta);
    }
    return 1;
fail:
    return 0;
}

int mainmenu_save_parse_read_title(char *title_buf, char *sig_block, int *out_save_id,
                                   char *slot_name, int slot_id, int *ds_state) {
    int scratch;
    char scratchBuf[50];

    strcpy(scratchBuf, title_buf + 4);
    scratchBuf[2] = '\0';
    if (isdigit(scratchBuf[0]) && isdigit(scratchBuf[1])) {
        *out_save_id = atoi(scratchBuf);
        if (*out_save_id >= 0 && *out_save_id <= 20) {
            sprintf(scratchBuf, "%s\\%s.G%02d\\SAVE%02d.GAM", "GAMES", slot_name, slot_id,
                    *out_save_id);
            if (mainmenu_save_file_read_header(scratchBuf, sig_block, ds_state, &scratch, &scratch,
                                               &scratch)) {
                if (*out_save_id == 0)
                    strcpy(sig_block, "Bookmark");
                return 1;
            }
        }
    }
    return 0;
}

int mainmenu_savelist_insert_sorted(ListWidget *list, char *label, unsigned short key) {
    int count;
    unsigned short entryKey;
    int index;

    count = listwidget_count(list);
    index = 0;
    while (index < count) {
        if (listwidget_get_entry_at(list, index, 0, &entryKey) != 0) {
            if ((int)key < (int)entryKey)
                break;
            if (key == entryKey) {
                return 0;
            }
        }
        index = index + 1;
    }
    return listwidget_insert_item(list, index, label, key);
}

int mainmenu_savelist_nextfree_key(ListWidget *list) {
    int count;
    int prev_key;
    int i;
    unsigned short key;

    count = listwidget_count(list);
    prev_key = 0;
    i = 0;
    if (i < count) {
        do {
            if (listwidget_get_entry_at(list, i, (char **)0x0, &key) != 0) {
                if (prev_key + 1 != key) {
                    if ((int)key <= 0x14) {
                        return prev_key + 1;
                    }
                    return -1;
                }
                prev_key = key;
            }
            i++;
        } while (i < count);
    }
    prev_key++;
    if (prev_key > 0x14) {
        goto neg1;
    }
    return prev_key;
neg1:
    return -1;
}

int mainmenu_savelist_nextfree_nobm(ListWidget *list) {
    int count;
    int prev_key;
    int i;
    unsigned short key;

    count = listwidget_count(list);
    prev_key = 0;
    i = 0;
    if (i < count) {
        do {
            if ((listwidget_get_entry_at(list, i, (char **)0x0, &key) != 0) && (key != 0)) {
                if (prev_key + 1 != key) {
                    if ((int)key <= 0x14) {
                        return prev_key + 1;
                    }
                    return -1;
                }
                prev_key = key;
            }
            i++;
        } while (i < count);
    }
    prev_key++;
    if (prev_key > 0x14) {
        goto neg1;
    }
    return prev_key;
neg1:
    return -1;
}

int mainmenu_savelist_find_by_text(ListWidget *list, char *text) {
    int count;
    int index;
    char *label;

    count = listwidget_count(list);
    index = 0;
    if (index < count) {
        do {
            if (listwidget_get_entry_at(list, index, &label, (unsigned short *)0) != 0 &&
                stricmp(label, text) == 0) {
                return index;
            }
            index = index + 1;
        } while (index < count);
    }
    return -1;
}

int mainmenu_savelist_find_by_name(ListWidget *list, char *name) {
    int count;
    int index;
    char *entry_text;

    count = listwidget_count(list);
    index = 0;
    if (index < count) {
        do {
            if ((listwidget_get_entry_at(list, index, &entry_text, 0) != 0) &&
                (strcmp(entry_text, name) == 0)) {
                return index;
            }
            index = index + 1;
        } while (index < count);
    }
    return -1;
}
