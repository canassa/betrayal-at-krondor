#include "SRC/GAME/GMAIN.H"
#include "SRC/GEN/GFXCTX.H"
#include "SRC/WORLD/ZONE/ZONE.H"
#include "SRC/WORLD/ZONE/CZONE.H"
#include "SRC/INPUT/TIMER.H"
#include "structs.h"
#include "SRC/WORLD/ACTOR/ACTOR.H"
#include "SRC/WORLD/LOOP/WORLDLP.H"
#include "SRC/GFX/PALETTE/PALCYC.H"
#include "SRC/AUDIO/ENGINE/AUDIO.H"
#include "SRC/GFX/SPRITE/RESBLIT.H"
#include "SRC/GFX/DRIVER/PALDRV.H"
#include "SRC/GFX/RASTER/PRESENT.H"
#include "SRC/INPUT/KEYBOARD.H"
#include "SRC/R3D/SCENE/WORLDHIT.H"
#include "SRC/GFX/SCREEN/SCREEN.H"
#include "SRC/UI/MENUPAGE.H"
#include "SRC/GFX/PALETTE/PALETTE.H"
#include "SRC/DIALOG/EVTCOND.H"
#include "SRC/GAME/GSTATE.H"
#include "SRC/CHAR/STAT.H"
#include "SRC/UI/UIWIDGET.H"
#include "SRC/DIALOG/DIALOG.H"
#include "SRC/SCREENS/TOWNSCN.H"
#include "SRC/UI/MODALSCR.H"
#include "SRC/SCREENS/CMBINV.H"
#include "SRC/CHAR/CHARSCRN.H"
#include "SRC/SCREENS/ITEMUSE.H"
#include "SRC/COMBAT/SPELL/SPELLFX.H"
#include "SRC/WORLD/LOOP/MAP.H"
#include "SRC/SCREENS/MAINMENU.H"
#include "SRC/SCREENS/ENCAMP.H"
#include "SRC/SCREENS/FMAP.H"
#include "SRC/WORLD/MOVE/WORLDMOV.H"
#include "SRC/WORLD/ENC/HOTSPOT.H"
#include "SRC/WORLD/CURSOR/WCURSOR.H"
#include "SRC/WORLD/MOVE/WORLDCRS.H"
#include "SRC/GAME/CFGPARSE.H"

MenuPage *g_pReqMainPage = {0};
short g_nSceneReloadPending = 0;
short g_nHotspotActivateRequest = 0;

void far worldloop_req_main_screen_load(void) {
    g_pReqMainPage = menupage_load("req_main.dat");
    map_req_map_screen_load();
    spellfx_cast_bmp_load();
    return;
}

void far worldloop_req_main_screen_unload(void) {
    spellfx_cast_bmp_free();
    map_req_map_screen_free();
    menupage_free(g_pReqMainPage);
    g_pReqMainPage = (MenuPage *)0x0;
    return;
}

short far world3d_main_loop(void) {

    short exit_mode;
    int keep_running;
    unsigned short redraw_menu;
    int redraw_caption;
    unsigned short pending_events;
    unsigned short key_repeat_armed;
    unsigned short refusal_mode;
    MenuEntry *focused_entry;
    MenuEntry *prev_focused_entry;
    unsigned int action_id;
    unsigned char far *saved_pal;
    /* This pair must stay `register`: render_dirty is allocated to SI,
       hotspot_active to DI. */
    register int render_dirty;   /* party-dirty / render-scene flag */
    register int hotspot_active; /* hotspot / descent / entered flag */

    exit_mode = 0;
    keep_running = 1;
    hotspot_active = 0;
    redraw_menu = 0;
    render_dirty = 0;
    redraw_caption = 0;
    pending_events = 0;
    key_repeat_armed = 0;
    focused_entry = (MenuEntry *)0;
    g_nHotspotActivateRequest = 0;
    g_bZoneEntryInProgress = 0;
    menupage_begin(g_pReqMainPage);
    worldloop_pty_stat7_flag_cd();
    hotspotevt_flags_clear();
    g_nSceneReloadPending = 1;

    while (keep_running != 0) {
        if (g_gameState.abTeleportRecord[0] != '\0') {
            g_nSceneReloadPending = modalscreen_pending_scene_trans();
        }
        if (g_gameState.bPartyDirtyFlags != '\0' && g_nSceneReloadPending == 0) {
            evtcond_pty_dirty_flags_process();
            render_dirty = 1;
        }
        audio_ambient_tick();
        if (g_nSceneReloadPending != 0) {

            saved_pal = g_pPalQueuedForFlip;
            g_pPalQueuedForFlip = (unsigned char far *)0;
            screen_cursor_show_busy();
            palette_fade_out(0, 0x100, -1, 0);
            screen_cursor_restore_shape();
            screen_cursor_hide();
            palette_screen_clear_black();
            g_pPalQueuedForFlip = saved_pal;
            screen_frame_flip();
            palette_daylight_tick();
            palette_apply_pending_load();
            palette_set_scaled(0, 0x100, 0, 0);
            screen_cursor_show_busy();
            g_graphics_context.wGfxBlitDstPage = g_graphics_context.wGfxBlitSrcPage =
                g_graphics_context.wVgaPage2Base;
            resblit_load_pal_or_stream("frame.scr");
            if (g_wSaveSlotDirValid != 0) {
                g_pReqMainPage->pEntries[7].wEnable_gate = 0;
            } else {
                g_pReqMainPage->pEntries[7].wEnable_gate = 1;
            }
            menupage_draw(g_pReqMainPage);
            spellfx_draw_events_caption();
            world_render_scene_dispatch(0);
            uiwidget_compass_draw();
            screen_cursor_restore_shape();
            screen_frame_flip();
            g_graphics_context.wGfxBlitSrcPage = g_graphics_context.wVgaFrontPageBase;
            g_graphics_context.wGfxBlitDstPage = g_graphics_context.wVgaPage2Base;
            gfx_present_dispatch(0, 0, 0x140, 200);
            screen_cursor_hide();
            palette_cycle_eb_toggle(1);
            screen_cursor_show_busy();
            palette_fade_in(0, 0x100, -1, 0);
            screen_cursor_restore_shape();
            g_nSceneReloadPending = 0;
            redraw_menu = 0;
            redraw_caption = 0;
            render_dirty = 0;
            goto skip_render;
        }
        if (g_bZoneEntryInProgress != 0)
            goto skip_render;

        g_graphics_context.wGfxBlitDstPage = g_graphics_context.wGfxBlitSrcPage =
            g_graphics_context.wVgaPage2Base;
        if (redraw_menu != 0) {
            menupage_draw(g_pReqMainPage);
        }
        if (redraw_caption != 0) {
            spellfx_draw_events_caption();
        }
        if (render_dirty != 0) {
            world_render_scene_dispatch(hotspot_active);
            uiwidget_compass_draw();
        }
        screen_frame_present();
        g_graphics_context.wGfxBlitDstPage = g_graphics_context.wGfxBlitSrcPage =
            g_graphics_context.wVgaPage2Base;
        if (redraw_menu != 0) {
            menupage_draw(g_pReqMainPage);
            redraw_menu = 0;
        }
        if (redraw_caption != 0) {
            spellfx_draw_events_caption();
            redraw_caption = 0;
        }
        if (render_dirty != 0) {
            screen_frame_sync_buffers_rect(0xb, 0x80);
            render_dirty = 0;
        }
    skip_render:

        if (g_gameState.ground_pile->itemCount != '\0') {
            itemuse_ground_pile_open_inv();
            redraw_menu = render_dirty = 0;
        }
        if (hotspot_active != 0) {
            worldcross_dungeon_descent_anim();
        }
        if (!g_gameState.bCombatExitRequest) {
            if (hotspot_active == 0 && g_nHotspotActivateRequest != 0) {
                hotspotevt_activate_at_player();
                g_nHotspotActivateRequest = 0;
                hotspot_active = 1;
            }
            if (hotspot_active != 0) {
                pending_events = hotspotevt_disp_pending_events();
                if (g_game_mode != 2) {
                    if (gstate_advance_time(g_lWorldTimePerStep, 1, 1, 1, 0) != 0) {
                        render_dirty = redraw_menu = 1;
                    }
                } else if (gstate_advance_time(g_lWorldTimePerStep / 4, 1, 1, 1, 0) != 0) {
                    render_dirty = redraw_menu = 1;
                }
                if (g_nSceneReloadPending == 0) {
                    palette_apply_pending_load();
                }
                redraw_caption = 1;
                hotspot_active = 0;
            }
            g_dwDialogInputCooldown = 0;
            action_id = menupage_run(g_pReqMainPage, &redraw_menu);
            prev_focused_entry = focused_entry;
            focused_entry = menupage_focused_entry();
            if (prev_focused_entry != focused_entry && key_repeat_armed != 0) {
                redraw_menu = 1;
                key_repeat_armed = 0;
            }

            switch (action_id) {
            case 0x48:
            case 0x4b:
            case 0x4d:
            case 0x50:
                if (key_repeat_armed != 0) {
                    action_id = 0;
                    key_repeat_armed = 0;
                    redraw_menu = 1;
                }
                goto after_scan1;
            case 0:
                if (focused_entry != 0) {
                    switch (focused_entry->wAction_id) {
                    case 0x48:
                    case 0x4b:
                    case 0x4d:
                    case 0x50:
                        if (key_repeat_armed == 0) {
                            key_repeat_armed = 1;
                            g_nFrameTickCountdown = 0x5a;
                        } else {
                            if (g_nFrameTickCountdown == 0) {
                                action_id = focused_entry->wAction_id;
                                redraw_menu = 1;
                                goto after_scan1;
                            }
                        }
                        break;
                    default:
                        break;
                    }
                }
                goto after_scan1;
            default:
                key_repeat_armed = 0;
                break;
            }

        after_scan1:
            if (action_id != 0) {
                refusal_mode = (menupage_state_0e7c() == 2) ? 1 : 0;
            }

            switch (action_id) {
            case 0x48:
                if (refusal_mode != 0) {
                    dialog_play_record(0xdf, 1);
                    goto post_dispatch;
                }
                hotspot_active = worldmove_party_attempt_move(1);
                if (hotspot_active != 0) {
                    worldloop_set_flag_8b_preds();
                    goto after_move;
                }
                goto post_dispatch;
            case 0x50:
                if (refusal_mode != 0) {
                    dialog_play_record(0xe0, 1);
                    goto post_dispatch;
                }
                hotspot_active = worldmove_party_attempt_move(4);
                if (hotspot_active != 0) {
                    worldloop_set_flag_8b_preds();
                    goto after_move;
                }
                goto post_dispatch;
            case 0x4b:
                if (refusal_mode != 0) {
                    dialog_play_record(0xe1, 1);
                    goto post_dispatch;
                }
                worldmove_apply_turn_step(2);
                goto after_move;
            case 0x4d:
                if (refusal_mode != 0) {
                    dialog_play_record(0xe2, 1);
                    goto post_dispatch;
                }
                worldmove_apply_turn_step(3);
                goto after_move;
            case 0x13:
                if (refusal_mode != 0) {
                    dialog_play_record(0xe3, 1);
                    goto post_dispatch;
                }
                if (worldmove_step_pending_get() != 0) {
                    worldloop_party_move_done_clr();
                    goto after_move;
                }
                worldloop_step_or_final_movement();
                goto after_move;
            case 0x2e:
                if (refusal_mode != 0) {
                    dialog_play_record(0xe4, 1);
                    goto post_dispatch;
                }
                spellfx_cast_and_dispatch();
                redraw_menu = 1;
                render_dirty = 1;
                redraw_caption = 1;
                goto post_dispatch;
            case 0x32:
                if (refusal_mode != 0) {
                    dialog_play_record(0xe8, 1);
                    goto post_dispatch;
                }
                map_main_loop();
                g_nSceneReloadPending = 1;
                goto post_dispatch;
            case 0x21:
                fmap_screen_run();
                g_nSceneReloadPending = 1;
                goto post_dispatch;
            case 0x12:
                if (refusal_mode != 0) {
                    dialog_play_record(0xe5, 1);
                    goto post_dispatch;
                }
                encamp_run();
                redraw_caption = 1;
                goto post_dispatch;
            case 0x30:
                if (refusal_mode != 0) {
                    dialog_play_record(0xe6, 1);
                    goto after_move;
                }
                mainmenu_save_bookmark();
                goto after_move;
            case 0x18:
                if (refusal_mode != 0) {
                    dialog_play_record(0xe7, 1);
                    goto post_dispatch;
                }
                exit_mode = mainmenu_save_main_menu(1);
                if (exit_mode == 0) {
                    g_nSceneReloadPending = 1;
                } else {
                    keep_running = 0;
                }
                goto post_dispatch;
            case 2:
            case 3:
            case 4: {
                unsigned int chap_sub = action_id - 2;
                if (g_gameState.party_count > (short)chap_sub) {
                    if (menupage_state_0e7c() == 2 || key_is_down(0x2a) != 0 ||
                        key_is_down(0x36) != 0) {

                        charscreen_info_loop(gstate_party_member_record((int)chap_sub));
                        g_nSceneReloadPending = 1;
                    } else {

                        cmbinv_inventory_screen_run((Actor far *)0, (int)chap_sub + 1, 0);
                    }
                    redraw_menu = render_dirty = redraw_caption = 1;
                }
                goto post_dispatch;
            }
            case 0xc0:
                if (wcursor_dispatch_action() != 0) {
                    redraw_menu = 1;
                    goto after_move;
                }
                goto post_dispatch;
            case 0x29:
                if (g_cfgKnockKnock && key_is_down(0x2a) == 0 && key_is_down(0x36) != 0 &&
                    key_is_down(0x1d) == 0 && key_is_down(0x38) != 0) {
                    townscene_cheat_menu_screen();
                }
                redraw_menu = 1;
            after_move:
                render_dirty = 1;
                goto post_dispatch;
            default:
                break;
            }
        }

    post_dispatch:
        if (pending_events != 0) {
            redraw_menu = 1;
            render_dirty = 1;
            pending_events = 0;
        }
        if (g_gameState.bCombatExitRequest != '\0') {
            exit_mode = 6;
            keep_running = 0;
        } else if (g_gameState.nWorldLoopExitRequest != '\0') {
            g_nChapterAtLoopExit = g_gameState.nChapter;
            if (g_gameState.nWorldLoopExitRequest == '\x01') {
                exit_mode = 5;
            } else {
                exit_mode = 7;
            }
            keep_running = 0;
        }
    }

    if (g_gameState.bCombatExitRequest == '\x01') {
        dialog_play_record(0x145, 0);
    }
    palette_cycle_eb_toggle(0);
    menupage_end(g_pReqMainPage);
    return exit_mode;
}

void worldloop_camera_snap_reset(long *pSavedZ, short *pSavedYaw) {
    if (g_full_redraw_needed != 0) {
        g_world_widget->colorRemap = NULL;
        *pSavedZ = g_world_camera->base.pos.nWorld_z;
        *pSavedYaw = g_world_camera->base.orientation.pitch;
        g_world_camera->base.pos.nWorld_z = g_lZoneDefaultZ;
        g_world_camera->base.orientation.pitch = g_wZoneDefaultYaw;
    }
    return;
}

void worldloop_camera_set_pos_z_yaw(long pos_z, short yaw) {
    if (g_full_redraw_needed != 0) {
        if (g_pColorRemap != (unsigned char *)0x0) {
            g_world_widget->colorRemap = g_pColorRemap;
        }
        g_world_camera->base.pos.nWorld_z = pos_z;
        g_world_camera->base.orientation.pitch = yaw;
    }
    return;
}

void far worldloop_party_move_done_clr(void) {
    worldmove_step_pending_clear();
    g_pReqMainPage->pEntries[4].wSub_state = 0;
    g_pReqMapPage->pEntries[4].wSub_state = 0;
    worldloop_set_flag_8b_preds();
    return;
}

void far worldloop_step_or_final_movement(void) {
    if (worldmove_step_once_along_axis() != 0) {
        g_pReqMainPage->pEntries[4].wSub_state = 1;
        g_pReqMapPage->pEntries[4].wSub_state = 1;
        worldloop_set_flag_8b_preds();
        return;
    }
    worldloop_party_move_done_clr();
}

void far worldloop_set_flag_8b_preds(void) {
    if (worldmove_step_pending_get() != 0)
        goto disable;
    if (worldmove_cross_walkable_kind() == 0)
        goto enable;
disable:
    g_pReqMainPage->pEntries[4].wEnable_gate = 0;
    g_pReqMapPage->pEntries[4].wEnable_gate = 0;
    return;
enable:
    g_pReqMainPage->pEntries[4].wEnable_gate = 1;
    g_pReqMapPage->pEntries[4].wEnable_gate = 1;
    return;
}

void far worldloop_pty_stat7_flag_cd(void) {
    int found;
    int i;

    found = 0;
    if (g_pReqMainPage != (MenuPage *)0x0) {
        i = 0;
        do {
            if (i < g_gameState.party_count) {
                if (stat_actor_get(&g_gameState.party_members[g_gameState.party_roster[i]], 7, 1) !=
                    0) {
                    found = 1;
                    break;
                }
            }
            i = i + 1;
        } while (i < 3);
        if (found) {
            g_pReqMainPage->pEntries[6].wEnable_gate = 0;
        } else {
            g_pReqMainPage->pEntries[6].wEnable_gate = 1;
        }
    }
}
