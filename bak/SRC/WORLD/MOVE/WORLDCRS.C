#include "SRC/GAME/GMAIN.H"
#include "SRC/GEN/GFXCTX.H"
#include "SRC/WORLD/ZONE/ZONE.H"
#include "SRC/WORLD/LOOP/MAP.H"
#include "structs.h"
#include "SRC/WORLD/MOVE/WORLDCRS.H"
#include "SRC/AUDIO/ENGINE/AUDIO.H"
#include "SRC/INPUT/KEYBOARD.H"
#include "SRC/R3D/SCENE/WORLDHIT.H"
#include "SRC/GFX/SCREEN/SCREEN.H"
#include "SRC/UI/MENUPAGE.H"
#include "SRC/R3D/TBLSTORE/SHAPEBLD.H"
#include "SRC/CHAR/STAT.H"
#include "SRC/R3D/VIS/PROXSCAN.H"
#include "SRC/R3D/CORE/R3D.H"
#include "SRC/UI/UIWIDGET.H"
#include "SRC/DIALOG/DIALOG.H"
#include "SRC/SCREENS/ITEMTBL.H"
#include "SRC/WORLD/MOVE/WORLDMOV.H"
#include "SRC/WORLD/ZONE/CZONE.H"

void far worldcross_dungeon_descent_anim(void) {
    unsigned short probe_kind;
    int sfx_handle;
    int descent_steps;
    int waiting_for_key;
    unsigned long probe_coord;
    long saved_z;
    WorldObject far *pFound;
    int i;
    unsigned int scancode;

    waiting_for_key = 0;
    if (g_game_mode == 2) {
        worldmove_cross_get_probe_result(&probe_kind, &probe_coord);
        if (probe_kind == 0xf) {
            for (i = 0; i < (int)g_gameState.party_count; i++) {
                stat_combatant_apply_delta(
                    &g_gameState.party_members[(int)g_gameState.party_roster[i]], 6, 100);
            }
            if (g_full_redraw_needed == 0 && proxscan_paged_find_next_type0f(&pFound) != 0) {
                screen_cursor_show_busy();
                saved_z = g_world_camera->base.pos.nWorld_z;
                g_world_camera->base.pos.xy.nWorld_x = pFound->pos.xy.nWorld_x;
                g_world_camera->base.pos.xy.nWorld_y = pFound->pos.xy.nWorld_y;
                if (key_is_down(0x19)) {
                    waiting_for_key = 1;
                    descent_steps = 0xd;
                } else {
                    descent_steps = 9;
                }
                sfx_handle = audio_sfx_play_n_times(0x2f, 0, 0);
                i = 0;
                while (i < descent_steps) {
                    g_world_camera->base.pos.nWorld_z = saved_z - (long)(i * 0x50);
                    g_graphics_context.wGfxBlitDstPage = g_graphics_context.wGfxBlitSrcPage =
                        g_graphics_context.wVgaPage2Base;
                    world_render_scene_dispatch(1);
                    screen_frame_present();
                    i++;
                }
                g_graphics_context.wGfxBlitDstPage = g_graphics_context.wGfxBlitSrcPage =
                    g_graphics_context.wVgaPage2Base;
                world_render_scene_dispatch(0);
                screen_frame_present();
                kbhit_read();
                while (waiting_for_key != 0) {
                    scancode = kbhit_read() >> 8;
                    if (scancode != 0 && scancode != 0x19) {
                        waiting_for_key = 0;
                    }
                    screen_frame_present();
                }
                if (sfx_handle != 0) {
                    audio_sfx_stop(0x2f);
                }
                screen_cursor_restore_shape();
            } else {
                audio_sfx_play_n_times(0x2f, 0, 1);
            }
            dialog_play_record(0x115, 0);
            g_gameState.bCombatExitRequest = 2;
        }
    }
    return;
}

void far worldcross_hotspot_use_rope(WorldHotspot *pHotspot) {
    long saved_z;
    long target_x;
    long target_y;
    long final_x;
    long final_y;
    long centerDist;
    int crossing_found;
    int targetHeading;
    int axisIsEW;
    int beyondStart;
    int sfx_played;

    crossing_found = 0;
    sfx_played = 0;
    dialog_viewport_clip_point(pHotspot->rect.x + pHotspot->rect.width / 2,
                               pHotspot->rect.y + pHotspot->rect.height / 2);
    if (menupage_state_0e7c() == 1) {
        if (itemtbl_party_count_by_kind(0x52) != 0) {

            if ((pHotspot->pEntity->orientation.yaw == 0) ||
                (pHotspot->pEntity->orientation.yaw == R3D_DEG(-180))) {

                if ((g_world_camera->base.pos.xy.nWorld_x >
                     pHotspot->pEntity->pos.xy.nWorld_x - 300) &&
                    (g_world_camera->base.pos.xy.nWorld_x <
                     pHotspot->pEntity->pos.xy.nWorld_x + 300)) {
                    target_x = final_x = pHotspot->pEntity->pos.xy.nWorld_x;
                    axisIsEW = 0;
                    if (g_world_camera->base.pos.xy.nWorld_y > pHotspot->pEntity->pos.xy.nWorld_y) {

                        target_y = pHotspot->pEntity->pos.xy.nWorld_y + 900;
                        final_y = pHotspot->pEntity->pos.xy.nWorld_y - 900;
                        targetHeading = R3D_DEG(-180);
                        beyondStart = g_world_camera->base.pos.xy.nWorld_y >
                                      pHotspot->pEntity->pos.xy.nWorld_y + 900;
                    } else {

                        target_y = pHotspot->pEntity->pos.xy.nWorld_y - 900;
                        final_y = pHotspot->pEntity->pos.xy.nWorld_y + 900;
                        targetHeading = 0;
                        beyondStart = g_world_camera->base.pos.xy.nWorld_y <
                                      pHotspot->pEntity->pos.xy.nWorld_y - 900;
                    }
                    crossing_found = 1;
                }
            } else if ((pHotspot->pEntity->orientation.yaw == R3D_DEG(90)) ||
                       (pHotspot->pEntity->orientation.yaw == R3D_DEG(-90))) {

                if ((g_world_camera->base.pos.xy.nWorld_y >
                     pHotspot->pEntity->pos.xy.nWorld_y - 300) &&
                    (g_world_camera->base.pos.xy.nWorld_y <
                     pHotspot->pEntity->pos.xy.nWorld_y + 300)) {
                    target_y = final_y = pHotspot->pEntity->pos.xy.nWorld_y;
                    axisIsEW = 1;
                    if (g_world_camera->base.pos.xy.nWorld_x > pHotspot->pEntity->pos.xy.nWorld_x) {

                        target_x = pHotspot->pEntity->pos.xy.nWorld_x + 900;
                        final_x = pHotspot->pEntity->pos.xy.nWorld_x - 900;
                        targetHeading = R3D_DEG(90);
                        beyondStart = g_world_camera->base.pos.xy.nWorld_x >
                                      pHotspot->pEntity->pos.xy.nWorld_x + 900;
                    } else {

                        target_x = pHotspot->pEntity->pos.xy.nWorld_x - 900;
                        final_x = pHotspot->pEntity->pos.xy.nWorld_x + 900;
                        targetHeading = R3D_DEG(-90);
                        beyondStart = g_world_camera->base.pos.xy.nWorld_x <
                                      pHotspot->pEntity->pos.xy.nWorld_x - 900;
                    }
                    crossing_found = 1;
                }
            }
            if (!crossing_found) {
                return;
            }

            if (dialog_play_record(0xc5, 1) != 0) {
                return;
            }
            screen_cursor_show_busy();
            audio_sfx_register_50();
            saved_z = g_world_camera->base.pos.nWorld_z;

            if (g_world_camera->base.orientation.yaw != targetHeading) {
                if ((unsigned int)(targetHeading - g_world_camera->base.orientation.yaw) < 0x8000) {
                    worldmove_animate_hdg_tgt(2, targetHeading);
                } else {
                    worldmove_animate_hdg_tgt(3, targetHeading);
                }
                g_graphics_context.wGfxBlitDstPage = g_graphics_context.wGfxBlitSrcPage =
                    g_graphics_context.wVgaPage2Base;
                world_render_scene_dispatch(0);
                uiwidget_compass_draw();
                screen_frame_present();
                g_graphics_context.wGfxBlitDstPage = g_graphics_context.wGfxBlitSrcPage =
                    g_graphics_context.wVgaPage2Base;
                world_render_scene_dispatch(0);
                uiwidget_compass_draw();
                screen_frame_present();
            }

            if (axisIsEW != 0) {
                g_world_camera->base.pos.xy.nWorld_y = target_y;
            } else {
                g_world_camera->base.pos.xy.nWorld_x = target_x;
            }

            g_graphics_context.wGfxBlitDstPage = g_graphics_context.wGfxBlitSrcPage =
                g_graphics_context.wVgaPage2Base;
            world_render_scene_dispatch(0);
            screen_frame_present();
            while ((axisIsEW != 0 && (g_world_camera->base.pos.xy.nWorld_x < target_x - 0x32 ||
                                      g_world_camera->base.pos.xy.nWorld_x > target_x + 0x32)) ||
                   g_world_camera->base.pos.xy.nWorld_y < target_y - 0x32 ||
                   g_world_camera->base.pos.xy.nWorld_y > target_y + 0x32) {
                if (beyondStart != 0) {
                    worldmove_vec2_rotate_add_q14(&g_world_camera->base.pos.xy.nWorld_x,
                                                  targetHeading, 100);
                } else {
                    worldmove_vec2_rotate_add_q14(&g_world_camera->base.pos.xy.nWorld_x,
                                                  targetHeading + R3D_DEG(180), 100);
                }
                g_world_camera->base.pos.nWorld_z = saved_z;
                g_graphics_context.wGfxBlitDstPage = g_graphics_context.wGfxBlitSrcPage =
                    g_graphics_context.wVgaPage2Base;
                world_render_scene_dispatch(1);
                screen_frame_present();
            }

            if (axisIsEW != 0) {
                g_world_camera->base.pos.xy.nWorld_x = target_x;
            } else {
                g_world_camera->base.pos.xy.nWorld_y = target_y;
            }

            while ((g_world_camera->base.pos.xy.nWorld_x != final_x) ||
                   (g_world_camera->base.pos.xy.nWorld_y != final_y)) {
                worldmove_vec2_rotate_add_q14(&g_world_camera->base.pos.xy.nWorld_x, targetHeading,
                                              100);
                if (axisIsEW != 0) {
                    centerDist =
                        g_world_camera->base.pos.xy.nWorld_x - pHotspot->pEntity->pos.xy.nWorld_x;
                } else {
                    centerDist =
                        g_world_camera->base.pos.xy.nWorld_y - pHotspot->pEntity->pos.xy.nWorld_y;
                }
                if (centerDist < 0) {
                    centerDist = -centerDist;
                }
                if (centerDist < 600) {

                    if ((!sfx_played) && (centerDist == 0)) {
                        audio_play(0x32);
                        sfx_played = 1;
                    }
                    centerDist = 0x4def9 - centerDist * centerDist;
                    g_world_camera->base.pos.nWorld_z = 0x1c2 - ts_isqrt_long(centerDist);
                } else {
                    g_world_camera->base.pos.nWorld_z = saved_z;
                }
                g_graphics_context.wGfxBlitDstPage = g_graphics_context.wGfxBlitSrcPage =
                    g_graphics_context.wVgaPage2Base;
                world_render_scene_dispatch(1);
                screen_frame_present();
            }

            g_graphics_context.wGfxBlitDstPage = g_graphics_context.wGfxBlitSrcPage =
                g_graphics_context.wVgaPage2Base;
            world_render_scene_dispatch(0);
            screen_frame_present();
            audio_sfx_stop_50();
            czone_resync_on_world_move();
            screen_cursor_restore_shape();
            itemtbl_pty_consum_one_kind(0x52);
            if (itemtbl_party_count_by_kind(0x52) == 0) {
                dialog_play_record(0x114, 1);
            }
        } else {
            dialog_play_record(0xc6, 1);
        }
    } else {
        dialog_play_record(0xb1, 1);
    }
}
