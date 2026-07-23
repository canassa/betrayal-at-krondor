#include <stdio.h>
#include "globals.h"
#include "structs.h"
#include "SRC/WORLD/ACTOR/ACTOR.H"
#include "SRC/WORLD/LOOP/MAP.H"
#include "SRC/IO/IO.H"
#include "SRC/SYS/MEM.H"
#include "SRC/GFX/PALETTE/PALCYC.H"
#include "SRC/GFX/SPRITE/RESBLIT.H"
#include "SRC/GFX/DRIVER/PALDRV.H"
#include "SRC/GFX/RASTER/PRESENT.H"
#include "SRC/INPUT/KEYBOARD.H"
#include "SRC/R3D/SCENE/WORLDHIT.H"
#include "SRC/R3D/CORE/R3D.H"
#include "SRC/GFX/SCREEN/SCREEN.H"
#include "SRC/UI/MENUPAGE.H"
#include "SRC/GFX/PALETTE/PALETTE.H"
#include "SRC/DIALOG/EVTCOND.H"
#include "SRC/GAME/GSTATE.H"
#include "SRC/UI/UIWIDGET.H"
#include "SRC/DIALOG/DIALOG.H"
#include "SRC/SCREENS/TOWNSCN.H"
#include "SRC/UI/MODALSCR.H"
#include "SRC/SCREENS/CMBINV.H"
#include "SRC/CHAR/CHARSCRN.H"
#include "SRC/SCREENS/ITEMUSE.H"
#include "SRC/WORLD/LOOP/WORLDLP.H"
#include "SRC/COMBAT/SPELL/SPELLFX.H"
#include "SRC/SCREENS/ENCAMP.H"
#include "SRC/SCREENS/FMAP.H"
#include "SRC/WORLD/MOVE/WORLDMOV.H"
#include "SRC/WORLD/ZONE/CZONE.H"
#include "SRC/WORLD/ENC/HOTSPOT.H"
#include "SRC/WORLD/MOVE/WORLDCRS.H"
#ifdef V102CD
#include "v102.h"
#endif

#include "globals.h"
#include "structs.h"

void far map_req_map_screen_load(void) {
    g_pReqMapPage = menupage_load("req_map.dat");
    return;
}

void far map_req_map_screen_free(void) {
    menupage_free(g_pReqMapPage);
    return;
}

void map_color_remap_load(char *filename) {
    int i;
    unsigned char idx;
    unsigned char val;
    BakFile *stream;

    g_pColorRemap = galloc_safe_zcalloc(256);
    i = 0;
    do {
        g_pColorRemap[i] = (unsigned char)i;
        i++;
    } while (i < 256);
    stream = bak_fopen(filename, "rb");
    bak_fread(&g_wSkyColorR, 2, 1, stream);
    bak_fread(&g_wSkyColorG, 2, 1, stream);
    bak_fread(&g_wSkyColorB, 2, 1, stream);
    bak_fread(&i, 2, 1, stream);
    for (; i != 0; i--) {
        bak_fread(&idx, 1, 1, stream);
        bak_fread(&val, 1, 1, stream);
        g_pColorRemap[idx] = val;
    }
    bak_fclose(stream);
    if (g_full_redraw_needed != 0) {
        g_world_widget->colorRemap = g_pColorRemap;
    }
    return;
}

void map_color_remap_free(void) {
    if (g_pColorRemap != (unsigned char *)0x0) {
        galloc_zfree(g_pColorRemap);
        g_pColorRemap = (unsigned char *)0x0;
    }
    return;
}

#include "globals.h"
#include "structs.h"

void far map_main_loop(void) {
    int keep_running;
    int moved;
    unsigned short redraw_menu;
    int redraw_caption;
    unsigned short pending_events;
    int key_repeat_armed;
    MenuEntry *focused_entry;
    MenuEntry *prev_focused_entry;
    unsigned int action_id;
    unsigned char far *saved_pal;
    int render_dirty;
    unsigned int refusal_mode;

    keep_running = 1;
    moved = 0;
    redraw_menu = 0;
    render_dirty = 0;
    redraw_caption = 0;
    pending_events = 0;
    key_repeat_armed = 0;
    focused_entry = (MenuEntry *)0;
    g_nHotspotActivateRequest = 0;
    map_camera_snap_face_south(&g_lExploreCameraZSaved, (short *)&g_wExploreCameraYawSaved);
    g_full_redraw_needed = 1;
    menupage_begin(g_pReqMapPage);
    g_nMapReloadPending = 1;

    while (keep_running != 0) {
        if ((g_gameState.bPartyDirtyFlags != 0) && (g_nMapReloadPending == 0)) {
            evtcond_pty_dirty_flags_process();
            render_dirty = 1;
        }
        if (g_lWorldZMin <= g_world_camera->base.pos.nWorld_z - g_lWorldZStep) {
            g_pReqMapPage->pEntries[7].wEnable_gate = 0;
        } else {
            g_pReqMapPage->pEntries[7].wEnable_gate = 1;
        }
        if (g_world_camera->base.pos.nWorld_z + g_lWorldZStep <= g_lWorldZMax) {
            g_pReqMapPage->pEntries[6].wEnable_gate = 0;
        } else {
            g_pReqMapPage->pEntries[6].wEnable_gate = 1;
        }
        if (g_nMapReloadPending != 0) {
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
            menupage_draw(g_pReqMapPage);
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
            g_nMapReloadPending = 0;
            redraw_menu = 0;
            redraw_caption = 0;
            render_dirty = 0;
        } else if (g_bZoneEntryInProgress == 0) {
            g_graphics_context.wGfxBlitDstPage = g_graphics_context.wGfxBlitSrcPage =
                g_graphics_context.wVgaPage2Base;
            if (redraw_menu != 0) {
                menupage_draw(g_pReqMapPage);
            }
            if (redraw_caption) {
                spellfx_draw_events_caption();
            }
            if (render_dirty) {
                world_render_scene_dispatch(moved);
                uiwidget_compass_draw();
            }
            screen_frame_present();
            g_graphics_context.wGfxBlitDstPage = g_graphics_context.wGfxBlitSrcPage =
                g_graphics_context.wVgaPage2Base;
            if (redraw_menu != 0) {
                menupage_draw(g_pReqMapPage);
                redraw_menu = 0;
            }
            if (redraw_caption) {
                spellfx_draw_events_caption();
                redraw_caption = 0;
            }
            if (render_dirty != 0) {
                screen_frame_sync_buffers_rect(0xb, 0x80);
                render_dirty = 0;
            }
        }
        if (g_gameState.ground_pile->itemCount != 0) {
            itemuse_ground_pile_open_inv();
            redraw_menu = render_dirty = 0;
        }
        if (moved != 0) {
            worldcross_dungeon_descent_anim();
        }
        if (!g_gameState.bCombatExitRequest) {
            if ((moved == 0) && (g_nHotspotActivateRequest != 0)) {
                hotspotevt_activate_at_player();
                g_nHotspotActivateRequest = 0;
                moved = 1;
            }
            if (moved != 0) {
                pending_events = hotspotevt_disp_pending_events();
                if (g_game_mode != 2) {
                    if (gstate_advance_time(g_lWorldTimePerStep, 1, 1, 1, 0) != 0) {
                        render_dirty = redraw_menu = 1;
                    }
                } else {
                    if (gstate_advance_time(g_lWorldTimePerStep / 4, 1, 1, 1, 0) != 0) {
                        render_dirty = redraw_menu = 1;
                    }
                }
                if (g_nMapReloadPending == 0) {
                    palette_apply_pending_load();
                }
                redraw_caption = 1;
                moved = 0;
            }
            g_dwDialogInputCooldown = 0;
            action_id = menupage_run(g_pReqMapPage, &redraw_menu);
            prev_focused_entry = focused_entry;
            focused_entry = menupage_focused_entry();
            if ((prev_focused_entry != focused_entry) && key_repeat_armed) {
                redraw_menu = 1;
                key_repeat_armed = 0;
            }

            switch (action_id) {
            case 0x48:
            case 0x49:
            case 0x4b:
            case 0x4d:
            case 0x50:
            case 0x51:
                if (key_repeat_armed) {
                    action_id = 0;
                    key_repeat_armed = 0;
                    redraw_menu = 1;
                }
                break;
            case 0:
                if (focused_entry != (MenuEntry *)0) {
                    switch (focused_entry->wAction_id) {
                    case 0x48:
                    case 0x49:
                    case 0x4b:
                    case 0x4d:
                    case 0x50:
                    case 0x51:
                        if (!key_repeat_armed) {
                            key_repeat_armed = 1;
                            g_nFrameTickCountdown = 0x5a;
                        } else if (g_nFrameTickCountdown == 0) {
                            action_id = focused_entry->wAction_id;
                            redraw_menu = 1;
                        }
                        break;
                    default:
                        break;
                    }
                }
                break;
            default:
                key_repeat_armed = 0;
                break;
            }

            if (action_id != 0) {
                refusal_mode = (unsigned int)(menupage_state_0e7c() == 2);
            }

            switch (action_id) {
            case 0x48:
                if (refusal_mode != 0) {
                    dialog_play_record(0xdf, 1);
                } else {
                    moved = worldmove_party_attempt_move(1);
                    if (moved != 0) {
                        worldloop_set_flag_8b_preds();
                        render_dirty = 1;
                    }
                }
                break;
            case 0x50:
                if (refusal_mode != 0) {
                    dialog_play_record(0xe0, 1);
                } else {
                    moved = worldmove_party_attempt_move(4);
                    if (moved != 0) {
                        worldloop_set_flag_8b_preds();
                        render_dirty = 1;
                    }
                }
                break;
            case 0x4b:
                if (refusal_mode != 0) {
                    dialog_play_record(0xe1, 1);
                } else {
                    worldmove_apply_turn_step(2);
                    render_dirty = 1;
                }
                break;
            case 0x4d:
                if (refusal_mode != 0) {
                    dialog_play_record(0xe2, 1);
                } else {
                    worldmove_apply_turn_step(3);
                    render_dirty = 1;
                }
                break;
            case 0x51:
                if (refusal_mode != 0) {
                    dialog_play_record(0xe9, 1);
                } else {
                    g_world_camera->base.pos.nWorld_z -= g_lWorldZStep;
                    redraw_menu = 1;
                    render_dirty = 1;
                }
                break;
            case 0x49:
                if (refusal_mode != 0) {
                    dialog_play_record(0xea, 1);
                } else {
                    g_world_camera->base.pos.nWorld_z += g_lWorldZStep;
                    redraw_menu = 1;
                    render_dirty = 1;
                }
                break;
            case 0x4f:
                if (refusal_mode != 0) {
                    dialog_play_record(0xe9, 1);
                } else {
                    g_world_camera->base.pos.nWorld_z -= g_lWorldZStep * 5;
                    if (g_world_camera->base.pos.nWorld_z < g_lWorldZMin) {
                        g_world_camera->base.pos.nWorld_z = g_lWorldZMin;
                    }
                    redraw_menu = 1;
                    render_dirty = 1;
                }
                break;
            case 0x47:
                if (refusal_mode != 0) {
                    dialog_play_record(0xea, 1);
                } else {
                    g_world_camera->base.pos.nWorld_z += g_lWorldZStep * 5;
                    if (g_lWorldZMax < g_world_camera->base.pos.nWorld_z) {
                        g_world_camera->base.pos.nWorld_z = g_lWorldZMax;
                    }
                    redraw_menu = 1;
                    render_dirty = 1;
                }
                break;
            case 0x13:
                if (refusal_mode != 0) {
                    dialog_play_record(0xe3, 1);
                } else {
                    if (worldmove_step_pending_get() != 0) {
                        worldloop_party_move_done_clr();
                    } else {
                        worldloop_step_or_final_movement();
                    }
                    render_dirty = 1;
                }
                break;
#ifdef V102CD
            case 0x31:
                g_bNonRotatingMap = !g_bNonRotatingMap;
                render_dirty = 1;
                break;
#endif
            case 0x21:
                if (refusal_mode != 0) {
                    dialog_play_record(0xeb, 1);
                } else {
                    fmap_screen_run();
                    g_nMapReloadPending = 1;
                }
                break;
            case 0x12:
                if (refusal_mode != 0) {
                    dialog_play_record(0xe5, 1);
                } else {
                    encamp_run();
                    redraw_caption = 1;
                }
                break;
            case 0x32:
                if (refusal_mode != 0) {
                    dialog_play_record(0xec, 1);
                } else {
                    keep_running = 0;
                }
                break;
            case 2:
            case 3:
            case 4: {
                int member_idx = action_id - 2;
                if (member_idx < g_gameState.party_count) {
                    if ((menupage_state_0e7c() == 2) || (key_is_down(0x2a) != 0) ||
                        (key_is_down(0x36) != 0)) {
                        charscreen_info_loop(gstate_party_member_record(member_idx));
                    } else {

                        cmbinv_inventory_screen_run((Actor far *)0, member_idx + 1, 0);
                    }
                    g_nMapReloadPending = 1;
                }
            } break;
            case 1:
                keep_running = 0;
                break;
            case 0x29:
                if ((key_is_down(0x2a) == 0) && (key_is_down(0x36) != 0) &&
                    (key_is_down(0x1d) == 0) && (key_is_down(0x38) != 0)) {
                    long spin = 500000;
                    do {
                        if (key_is_down(0x29) == 0) {
                            break;
                        }
                    } while (--spin > 0);
                    if (spin <= 0) {
                        townscene_chest_open_with_cipher();
                    }
                }
                break;
            default:
                break;
            }
        }

        if (pending_events != 0) {
            redraw_menu = 1;
            render_dirty = 1;
            pending_events = 0;
        }
        if ((g_gameState.bCombatExitRequest != 0) || (g_gameState.nWorldLoopExitRequest != 0)) {
            keep_running = 0;
        }
        if (g_gameState.abTeleportRecord[0] != 0) {
            g_nMapReloadPending = modalscreen_pending_scene_trans();
        }
    }

    if (g_gameState.bCombatExitRequest == 1) {
        dialog_play_record(0x145, 0);
    }
    menupage_end(g_pReqMapPage);
    g_full_redraw_needed = 0;
    map_camera_restore_z_yaw(g_lExploreCameraZSaved, g_wExploreCameraYawSaved);
    worldmove_camera_crossing_apply();
    return;
}

#include "structs.h"
#include "globals.h"

void far map_camera_snap_face_south(long *pSavedZ, short *pSavedYaw) {
    if (g_full_redraw_needed == 0) {
        if (g_pColorRemap != (unsigned char *)0x0) {
            g_world_widget->colorRemap = g_pColorRemap;
        }
        *pSavedZ = g_world_camera->base.pos.nWorld_z;
        *pSavedYaw = g_world_camera->base.orientation.pitch;
        g_world_camera->base.pos.nWorld_z = g_gameState.lInsetCameraPosZ;
        g_world_camera->base.orientation.pitch = R3D_DEG(-90);
    }
    return;
}

void map_camera_restore_z_yaw(long new_pos_z, short new_yaw) {
    if (g_full_redraw_needed == 0) {
        g_gameState.lInsetCameraPosZ = g_world_camera->base.pos.nWorld_z;
        g_world_camera->base.pos.nWorld_z = new_pos_z;
        g_world_camera->base.orientation.pitch = new_yaw;
        g_world_widget->colorRemap = NULL;
    }
    return;
}

#include "globals.h"
#include "structs.h"

unsigned short g_full_redraw_needed = 0x0000;
short g_nMapReloadPending = 1;
unsigned char *g_pColorRemap = {0};

unsigned short g_wExploreCameraYawSaved;
long g_lWorldZMin;
long g_lWorldZMax;
long g_lWorldZStep;
long g_lExploreCameraZSaved;
MenuPage *g_pReqMapPage;

void far map_animate_camera_to_tile(TileMoveRecord *ptr) {
    long savedCameraZ;
    long saved_z;
    short savedCameraYaw;
    short step_speed;
    int saved_redraw;
    int out_target;
    unsigned char tile_x;
    unsigned char tile_y;
    int out_dir;
    WorldPos saved_pos;

    saved_z = g_world_camera->base.pos.nWorld_z;
    saved_redraw = g_full_redraw_needed;
    step_speed = g_nWorldStepSpeed;
    map_camera_snap_face_south(&savedCameraZ, &savedCameraYaw);
    g_full_redraw_needed = 1;
    if (saved_redraw == 0) {
        g_world_camera->base.pos.nWorld_z = saved_z = 0x1b968L;
    }
    czone_get_party_tile_xy(&tile_x, &tile_y);
    czone_world_pos_tile_sub_ctr(tile_x, tile_y, ptr->bSubX, ptr->bSubY,
                                 &g_world_camera->base.pos.xy);
    g_world_camera->base.orientation.yaw = ptr->nHeading;
    saved_pos = g_world_camera->base.pos;
    if (g_game_mode == 2) {
        step_speed >>= 1;
    }
    g_bWorldCrossing = 1;
    g_graphics_context.wGfxBlitDstPage = g_graphics_context.wGfxBlitSrcPage =
        g_graphics_context.wVgaPage2Base;
    world_render_scene_dispatch(0);
    uiwidget_compass_draw();
    screen_frame_present();
    while (worldmove_crossing_check_8dir(&g_world_camera->base.pos,
                                         g_world_camera->base.orientation.yaw, (long)step_speed, 1,
                                         &out_dir, &out_target)) {
        g_world_camera->base.pos.nWorld_z = saved_z;
        if (out_dir == 2 || out_dir == 3) {
            worldmove_animate_hdg_tgt(out_dir, out_target);
        }
        g_graphics_context.wGfxBlitDstPage = g_graphics_context.wGfxBlitSrcPage =
            g_graphics_context.wVgaPage2Base;
        world_render_scene_dispatch(1);
        uiwidget_compass_draw();
        screen_frame_present();
    }
    g_graphics_context.wGfxBlitDstPage = g_graphics_context.wGfxBlitSrcPage =
        g_graphics_context.wVgaPage2Base;
    world_render_scene_dispatch(0);
    uiwidget_compass_draw();
    screen_frame_present();
    g_bWorldCrossing = 0;
    g_world_camera->base.pos = saved_pos;
    g_world_camera->base.orientation.yaw = ptr->nHeading + R3D_DEG(180);
    g_full_redraw_needed = saved_redraw;
    map_camera_restore_z_yaw(savedCameraZ, savedCameraYaw);
    return;
}
