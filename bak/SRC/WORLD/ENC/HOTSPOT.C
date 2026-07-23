#include "SRC/GAME/GMAIN.H"
#include "SRC/GEN/GFXCTX.H"
#include "structs.h"
#include "SRC/WORLD/ENC/HOTSPOT.H"
#include "SRC/SYS/RAND.H"
#include "SRC/IO/IO.H"
#include "SRC/AUDIO/ENGINE/AUDIO.H"
#include "SRC/R3D/SCENE/WORLDHIT.H"
#include "SRC/R3D/ACTOR/ACTMOTN.H"
#include "SRC/R3D/CORE/R3D.H"
#include "SRC/COMBAT/GRID/CMBTGRID.H"
#include "SRC/DIALOG/EVTCOND.H"
#include "SRC/GAME/GSTATE.H"
#include "SRC/CHAR/STAT.H"
#include "SRC/R3D/VIS/VISLIST.H"
#include "SRC/R3D/VIS/PROXSCAN.H"
#include "SRC/DIALOG/DIALOG.H"
#include "SRC/SCREENS/TOWNSCN.H"
#include "SRC/COMBAT/ARENA/COMBAT.H"
#include "SRC/WORLD/LOOP/WORLDLP.H"
#include "SRC/COMBAT/SPELL/SPELLFX.H"
#include "SRC/WORLD/LOOP/MAP.H"
#include "SRC/WORLD/MOVE/WORLDMOV.H"
#include "SRC/WORLD/ZONE/CZONE.H"
#include "SRC/WORLD/ZONE/ZONE.H"
#include "SRC/WORLD/ENC/RGNENC.H"
#include <stdlib.h>

ZoneHotspot g_aZoneHotspots[10];
unsigned short g_awHotspotPendingFlags[10];

unsigned short g_nHotspotCount = 0x0000;
unsigned short g_wHotspotIterIdx = 0x0000;
unsigned short g_wHotspotMatchIdx = 0x0000;
unsigned short g_wHotspotEventEnabled = 0x0001;
unsigned short g_bZoneEntryInProgress = 0x0000;
unsigned short g_wHotspotIterCursor = 0x0000;
char g_monst_filename_buf[12] = "Tzzxxyy.DAT";
char g_aDefFileNames[12][13] = {
    0x64, 0x65, 0x66, 0x5f, 0x62, 0x6b, 0x67, 0x72, 0x2e, 0x64, 0x61, 0x74, 0x00, 0x64, 0x65, 0x66,
    0x5f, 0x63, 0x6f, 0x6d, 0x62, 0x2e, 0x64, 0x61, 0x74, 0x00, 0x64, 0x65, 0x66, 0x5f, 0x63, 0x6f,
    0x6d, 0x6d, 0x2e, 0x64, 0x61, 0x74, 0x00, 0x64, 0x65, 0x66, 0x5f, 0x64, 0x69, 0x61, 0x6c, 0x2e,
    0x64, 0x61, 0x74, 0x00, 0x64, 0x65, 0x66, 0x5f, 0x68, 0x65, 0x61, 0x6c, 0x2e, 0x64, 0x61, 0x74,
    0x00, 0x64, 0x65, 0x66, 0x5f, 0x73, 0x6f, 0x75, 0x6e, 0x2e, 0x64, 0x61, 0x74, 0x00, 0x64, 0x65,
    0x66, 0x5f, 0x74, 0x6f, 0x77, 0x6e, 0x2e, 0x64, 0x61, 0x74, 0x00, 0x64, 0x65, 0x66, 0x5f, 0x74,
    0x72, 0x61, 0x70, 0x2e, 0x64, 0x61, 0x74, 0x00, 0x64, 0x65, 0x66, 0x5f, 0x7a, 0x6f, 0x6e, 0x65,
    0x2e, 0x64, 0x61, 0x74, 0x00, 0x64, 0x65, 0x66, 0x5f, 0x64, 0x69, 0x73, 0x61, 0x2e, 0x64, 0x61,
    0x74, 0x00, 0x64, 0x65, 0x66, 0x5f, 0x65, 0x6e, 0x61, 0x62, 0x2e, 0x64, 0x61, 0x74, 0x00, 0x64,
    0x65, 0x66, 0x5f, 0x62, 0x6c, 0x6f, 0x63, 0x2e, 0x64, 0x61, 0x74, 0x00};
short g_aDefRecordSizes[12] = {21, 399, 10, 8, 13, 7, 21, 409, 19, 7, 7, 8};

void far hotspotevt_monst_load_tbl_cur_id(void) {
    BakFile *stream;
    VisibleEntryList *p;

    p = g_apCombat_zone_actor_lists[0];
    g_monst_filename_buf[1] = 0x30 | p->bZone / 10;
    g_monst_filename_buf[2] = 0x30 | p->bZone % 10;
    g_monst_filename_buf[3] = 0x30 | p->bParty_x / 10;
    g_monst_filename_buf[4] = 0x30 | p->bParty_x % 10;
    g_monst_filename_buf[5] = 0x30 | p->bParty_y / 10;
    g_monst_filename_buf[6] = 0x30 | p->bParty_y % 10;
    stream = bak_fopen(g_monst_filename_buf, "rb");
    if (stream != (BakFile *)0) {
        bak_fseek(stream, (unsigned long)((g_gameState.nChapter - 1) * 0xc0), 1);
        bak_fread(&g_nHotspotCount, 2, 1, stream);
        bak_fread(g_aZoneHotspots, 0x13, g_nHotspotCount, stream);
        bak_fclose(stream);
    } else {
        g_nHotspotCount = 0;
    }
}

void hotspotevt_flags_clear(void) {
    unsigned short *pFlag;
    int i;

    pFlag = g_awHotspotPendingFlags;
    i = 0;
    if (i < (int)g_nHotspotCount) {
        do {
            *pFlag = 0;
            i = i + 1;
            pFlag = pFlag + 1;
        } while (i < (int)g_nHotspotCount);
    }
}

int hotspotevt_activate_at_player(void) {
    ZoneHotspot *evt;
    unsigned int *pOut_accepted;
    int allNoInteraction;
    int noInteraction;
    int ambushArmed;
    int ambushOut;

    evt = hotspotevt_find_at_player_tile(1);
    allNoInteraction = 1;
    ambushArmed = 0;
    hotspotevt_flags_clear();
    while (evt != (ZoneHotspot *)0) {
        pOut_accepted = (unsigned int *)&g_awHotspotPendingFlags[g_wHotspotMatchIdx];
        switch (evt->wKind) {
        case 0:
            hotspotevt_dialog_popup_run(evt, &noInteraction, (int *)pOut_accepted);
            break;
        case 1:
            if (ambushArmed != 0) {
                hotspotevt_skill_check_trigger(1, evt, &ambushOut, &noInteraction,
                                               (int *)pOut_accepted);
            } else {
                hotspotevt_skill_check_trigger(0, evt, &ambushOut, &noInteraction,
                                               (int *)pOut_accepted);
                ambushArmed |= ambushOut;
            }
            break;
        case 6:
            hotspotevt_show_record_message(evt, &noInteraction, (int *)pOut_accepted);
            break;
        case 7:
            if (ambushArmed != 0) {
                hotspotevt_trap_prefire_scout(1, evt, &ambushOut, &noInteraction,
                                              (int *)pOut_accepted);
            } else {
                hotspotevt_trap_prefire_scout(0, evt, &ambushOut, &noInteraction,
                                              (int *)pOut_accepted);
                ambushArmed |= ambushOut;
            }
            break;
        case 8:
            hotspotevt_action_try_enter_zone(evt, &noInteraction, pOut_accepted);
            break;
        case 11:
            hotspotevt_dlg_run_msg_event(evt, &noInteraction);
            break;
        default:
            noInteraction = *pOut_accepted = 1;
            break;
        }
        allNoInteraction &= noInteraction;
        evt = hotspotevt_find_at_player_tile(2);
    }
    return allNoInteraction;
}

unsigned short far hotspotevt_disp_pending_events(void) {
    int running;
    unsigned short wEventMask;
    unsigned short *pPendingFlag;
    unsigned short wHaltFlag;
    unsigned int eventBit;
    ZoneHotspot *evt;

    running = 1;
    wEventMask = 0;
    pPendingFlag = g_awHotspotPendingFlags;
    g_wHotspotMatchIdx = 0;
    while (running && (int)g_wHotspotMatchIdx < (int)g_nHotspotCount) {
        if (*pPendingFlag != 0) {
            evt = g_aZoneHotspots + g_wHotspotMatchIdx;
            switch (evt->wKind) {
            case 0:
                hotspotevt_load_record0_town(evt);
                eventBit = 1;
                goto done_mask;
            case 1:
                hotspotevt_type1_encounter_run(evt, (int *)&wHaltFlag);
                if (wHaltFlag != 0) {
                    running = 0;
                }
                eventBit = 0;
                break;
            case 3:
                eventBit = hotspotevt_monst_load_speak(evt);
                goto done_mask;
            case 5:
                hotspotevt_maybe_play_random_sfx(evt);
                eventBit = 0;
                break;
            case 6:
                hotspotevt_action_enter_town(evt);
                eventBit = 1;
                goto done_mask;
            case 7:
                hotspotevt_trap_main_fire(evt, &wHaltFlag);
                if (wHaltFlag != 0) {
                    running = 0;
                }
                eventBit = 0;
                break;
            case 8:
                hotspotevt_action_enter_zone(evt);
                running = 0;
                eventBit = 1;
                goto done_mask;
            case 9:
                hotspotevt_combat_play_sfx_voice(evt);
                eventBit = 0;
                break;
            case 10:
                hotspotevt_chance_trigger(evt);
                eventBit = 0;
                break;
            default:
                eventBit = 0;
                break;
            }
        done_mask:
            wEventMask |= eventBit;
        }
        g_wHotspotMatchIdx++;
        pPendingFlag++;
    }
    return wEventMask;
}

int hotspotevt_dispatch_at_point(int target_type, unsigned char x, unsigned char y, int *out_flag) {
    ZoneHotspot *hotspot;
    int result;
    int more;
    unsigned short statusFlag;
    unsigned int shouldFire;

    hotspot = hotspotevt_find_at_point(1, x, y);
    result = 0;
    more = 1;
    while (more != 0 && hotspot != (ZoneHotspot *)0x0) {
        if (hotspot->wKind == target_type) {
            switch (hotspot->wKind) {
            case 7:
                hotspotevt_trap_prefire_scout(0, hotspot, out_flag, (int *)&statusFlag,
                                              (int *)&shouldFire);
                if (shouldFire != 0) {
                    g_wHotspotEventEnabled = 0;
                    hotspotevt_trap_main_fire(hotspot, &statusFlag);
                    g_wHotspotEventEnabled = 1;
                    *out_flag = 1;
                }
            LAB_759a_036c:
                result = 1;
                break;
            case 8:
                hotspotevt_action_try_enter_zone(hotspot, (int *)&statusFlag, &shouldFire);
                if (shouldFire != 0) {
                    hotspotevt_action_enter_zone(hotspot);
                }
                *out_flag = shouldFire;
                goto LAB_759a_036c;
            }
            more = 0;
        }
        hotspot = hotspotevt_find_at_point(2, x, y);
    }
    return result;
}

int far hotspotevt_play_sound_zone_entry(int index) {
    ZoneHotspot *p;
    int count;
    int found;
    int running;
    char buf[409];

    p = hotspotevt_next_entry_19byte(1);
    count = 0;
    found = 0;
    running = 1;
    while (running && p != (ZoneHotspot *)0) {
        switch (p->wKind) {
        case 1:
            if (count == index) {
                hotspotevt_bak_load_indexed_rec(1, buf + 10, p->dwDef_record_offset);
                if (*(long *)(buf + 16) != 0) {
                    dialog_play_record(*(long *)(buf + 16), 1);
                }
                found = 1;
                running = 0;
            } else {
                count++;
            }
            break;
        case 7:
            if (count == index) {
                hotspotevt_bak_load_indexed_rec(7, buf, p->dwDef_record_offset);
                if (*(long *)(buf + 6) != 0) {
                    dialog_play_record(*(long *)(buf + 6), 1);
                }
                found = 1;
                running = 0;
            } else {
                count++;
            }
            break;
        }
        p = hotspotevt_next_entry_19byte(2);
    }
    return found;
}

int far hotspotevt_trap_gates_pass(int nIndex) {
    ZoneHotspot *pHotspot;
    int nCombatTrapIdx;
    int bGatesPass;
    int running;

    pHotspot = hotspotevt_next_entry_19byte(1);
    nCombatTrapIdx = 0;
    bGatesPass = 1;
    running = 1;

    while (running && pHotspot) {
        switch (pHotspot->wKind) {
        case 1:
            if (nCombatTrapIdx == nIndex) {
                if (pHotspot->wEvent_flag_pre2 == 0 ||
                    gstate_event_read(pHotspot->wEvent_flag_pre2) == 0) {
                    if (pHotspot->wEvent_flag_pre1 != 0) {
                        if (gstate_event_read(pHotspot->wEvent_flag_pre1) == 0)
                            goto fail;
                    }
                } else {
                fail:
                    bGatesPass = 0;
                }
                running = 0;
            } else {
                nCombatTrapIdx++;
            }
            break;
        case 7:
            if (nCombatTrapIdx == nIndex) {
                if (pHotspot->wEvent_flag_pre2 == 0 ||
                    gstate_event_read(pHotspot->wEvent_flag_pre2) == 0) {
                    if (pHotspot->wEvent_flag_pre1 != 0) {
                        if (gstate_event_read(pHotspot->wEvent_flag_pre1) == 0)
                            goto fail;
                    }
                } else {
                    goto fail;
                }
                running = 0;
            } else {
                nCombatTrapIdx++;
            }
            break;
        }
        pHotspot = hotspotevt_next_entry_19byte(2);
    }
    return bGatesPass;
}

int far hotspotevt_available(ZoneHotspot *pHotspot) {
    if (pHotspot == (ZoneHotspot *)0x0 || hotspotevt_done_read() != 0 ||
        hotspotevt_scout_tried_read() != 0 ||
        (pHotspot->wEvent_flag_pre2 != 0 && gstate_event_read(pHotspot->wEvent_flag_pre2) != 0) ||
        (pHotspot->wEvent_flag_pre1 != 0 && gstate_event_read(pHotspot->wEvent_flag_pre1) == 0)) {
        return 0;
    }
    return 1;
}

void far hotspotevt_dialog_popup_run(ZoneHotspot *pHotspot, int *out_skipped,
                                     int *out_user_confirmed) {
    unsigned char buf[22];

    if (hotspotevt_available(pHotspot) != 0) {
        hotspotevt_bak_load_indexed_rec(0, buf, pHotspot->dwDef_record_offset);
        *out_skipped = 0;
        if (*(unsigned long *)(buf + 6) != 0) {
            *out_user_confirmed = (dialog_play_record(*(unsigned long *)(buf + 6), 0) == 0);
        } else {
            *out_user_confirmed = 0;
        }
    } else {
        *out_skipped = 1;
        *out_user_confirmed = 0;
    }
}

void far hotspotevt_load_record0_town(ZoneHotspot *pHotspot) {
    char buf[21];

    hotspotevt_bak_load_indexed_rec(0, buf, pHotspot->dwDef_record_offset);
    if (buf[0x12] != '\0') {
        map_animate_camera_to_tile((TileMoveRecord *)(buf + 0xE));
    }
    townscene_main_loop(*(unsigned int *)(buf + 2), 1);
    if (pHotspot->wEvent_key_post != 0) {
        gstate_event_write(pHotspot->wEvent_key_post, 1);
    }
    if (!(int)g_gameState.abTeleportRecord[0]) {
        g_nSceneReloadPending = 1;
        g_nMapReloadPending = 1;
    }
    return;
}

void far hotspotevt_skill_check_trigger(int isAuto, ZoneHotspot *pHotspot, int *out_a, int *out_b,
                                        int *out_c) {
    char buf[0x190];
    register int *pOutB = out_b;
    register int *pOutC = out_c;

    *out_a = 0;
    if (hotspotevt_done_read() != 0 ||
        (pHotspot->wEvent_flag_pre2 != 0 && gstate_event_read(pHotspot->wEvent_flag_pre2) != 0) ||
        (pHotspot->wEvent_flag_pre1 != 0 && gstate_event_read(pHotspot->wEvent_flag_pre1) == 0)) {
        *pOutC = 0;
        *pOutB = 1;
        return;
    }
    hotspotevt_bak_load_indexed_rec(1, buf, pHotspot->dwDef_record_offset);
    if (hotspotevt_enc_fought_read(*(unsigned long *)(buf + 2)) != 0) {
        *pOutC = 0;
        *pOutB = 1;
        return;
    }
    if (*(unsigned int *)(buf + 0x18d) & 1) {
        if (isAuto != 0) {
            *pOutC = 0;
            *pOutB = 1;
            return;
        }
        *out_a = 1;
        if (hotspotevt_scout_tried_read() == 0) {
            hotspotevt_scout_tried_set();
            if (RND(100) <= stat_party_find_extreme(0xe, 0, (short *)0x0)) {
                stat_party_broadcast_status_op(0xe, 1, 3);
                if (*(unsigned long *)(buf + 0xa) != 0)
                    dialog_play_record(*(unsigned long *)(buf + 0xa), 1);
                else
                    dialog_play_record(0x2fL, 1);
                hotspotevt_scouted_set();
                *pOutC = 0;
                *pOutB = 0;
                return;
            }
        }
    }
    *pOutC = 1;
    *pOutB = 1;
}

void far hotspotevt_type1_encounter_run(ZoneHotspot *pHotspot, int *out_moved) {
    int combatStatus;
    int hasFired;
    short landingHeading;
    long landingY;
    long landingX;
    unsigned char tileX;
    unsigned char tileY;
    long visitedTime;
    short origHeading;
    int facing;
    char buf[0x190];
    char worldCtr[12];

    unsigned int chance;
    int n;

    hasFired = 0;
    *out_moved = 0;
    hotspotevt_bak_load_indexed_rec(1, buf, pHotspot->dwDef_record_offset);
    if ((n = hotspotevt_monst_dispatch_by_tag(*(unsigned long *)(buf + 2))) == 0) {
        if ((*(unsigned int *)(buf + 0x18d) & 1) != 0) {
            if (hotspotevt_scouted_read() != 0)
                goto do_chance_check;
        }
        if ((*(unsigned int *)(buf + 0x18d) & 1) != 0)
            goto skip_event_check;
        if (spellfx_event_mask_test_bit(0) == 0)
            goto skip_event_check;
    do_chance_check:
        if ((n = worldmove_step_tick_get()) == 0) {
            return;
        }
        chance = stat_party_find_extreme(0xf, 0, (short *)0x0);
        g_gameState.nEvtArgActor0 = g_gameState.nEvtArgStat;
        if ((int)chance < 0x5a) {
            chance = chance + (int)(chance * 0x1e) / 100;
            if (0x5a < (int)chance) {
                chance = 0x5a;
            }
        }
        if ((*(unsigned int *)(buf + 0x18d) & 1) != 0 && spellfx_event_mask_test_bit(0) != 0) {
            chance = chance + (int)(100 - chance) / 2;
        }
        if (RND(100) <= chance) {
            stat_party_broadcast_status_op(0xf, 1, 3);
            return;
        }
    skip_event_check:;
    }
    if (g_game_mode == 2) {
        origHeading = g_world_camera->base.orientation.yaw;
        hotspotevt_tile_rect_world_ctr(&pHotspot->bbox.minX, (long *)worldCtr);
        facing =
            actormotion_atan2_long(*(long *)worldCtr - g_world_camera->base.pos.xy.nWorld_x,
                                   *(long *)(worldCtr + 4) - g_world_camera->base.pos.xy.nWorld_y);

        g_world_camera->base.orientation.yaw = (unsigned)(facing + R3D_DEG(45)) & 0xc000;
        if (combatgrid_tiles_over_thresh() == 0) {
            g_world_camera->base.orientation.yaw = origHeading;
            g_graphics_context.wGfxBlitDstPage = g_graphics_context.wVgaPage2Base;
            world_render_scene_dispatch(0);
            return;
        }
    } else {
        if (combatgrid_tiles_over_thresh() == 0) {
            return;
        }
    }
    gstate_temp_file_read_at((unsigned char far *)&visitedTime, GAM_ENC_VISITED_TIME(*(unsigned long *)(buf + 2)),
                             4);
    if ((g_gameState.game_time - visitedTime) / 0x1e <= 0x1e) {
        if (RND(100) <= stat_party_find_extreme(0xf, 0, (short *)0x0)) {
            stat_party_broadcast_status_op(0xf, 1, 3);
            hasFired = 1;
            g_gameState.nEvtArgCount = 0;
        } else {
            g_gameState.nEvtArgCount = 1;
        }
    } else {
        g_gameState.nEvtArgCount = 2;
    }
    g_gameState.nEvtArgAux1 = *(short *)(buf + 0x3b);
    if (*(unsigned long *)(buf + 6) != 0) {
        dialog_play_record(*(unsigned long *)(buf + 6), 1);
    }
    combat_arena_actor_turn_loop((unsigned short) * (unsigned long *)(buf + 2), &combatStatus, hasFired);
    g_wLastTempWriteRecordKind = 1;
    gstate_temp_file_write_at((unsigned char far *)&g_gameState.game_time,
                              GAM_ENC_FOUGHT_TIME(*(unsigned long *)(buf + 2)), 4);
    if (combatStatus == 2) {
        *out_moved = 1;
        switch (worldmove_aabb_outcode_rotated(&pHotspot->bbox.minX)) {
        case 1:
            *(GamePositionAndHeading *)&landingX = *(GamePositionAndHeading *)(buf + 0x12);
            break;
        case 2:
            *(GamePositionAndHeading *)&landingX = *(GamePositionAndHeading *)(buf + 0x1c);
            break;
        case 4:
            *(GamePositionAndHeading *)&landingX = *(GamePositionAndHeading *)(buf + 0x26);
            break;
        case 8:
            *(GamePositionAndHeading *)&landingX = *(GamePositionAndHeading *)(buf + 0x30);
            break;
        default:
            *(GamePositionAndHeading *)&landingX = *(GamePositionAndHeading *)(buf + 0x12);
            break;
        }
        czone_get_party_tile_xy(&tileX, &tileY);
        g_world_camera->base.pos.xy.nWorld_x = (unsigned long)tileX * 64000 + landingX;
        g_world_camera->base.pos.xy.nWorld_y = (unsigned long)tileY * 64000 + landingY;
        g_world_camera->base.orientation.yaw = landingHeading;
        proxscan_full(g_world_widget);
        vislist_sort(g_wVisibleEntrySegment, g_pwVisibleEntryOffsets, g_pVisibleEntryDistances,
                     g_nVisibleEntryCount);
        worldmove_camera_crossing_apply();
        worldloop_party_move_done_clr();
        goto LAB_759a_0a9c;
    }
    if (combatStatus == 1) {
        if (pHotspot->wEvent_key_post != 0) {
            gstate_event_write(pHotspot->wEvent_key_post, 1);
        }
        hotspotevt_done_set();
        hotspotevt_enc_fought_set(*(unsigned long *)(buf + 2));
        evtcond_dispatch_key_to_handler((unsigned short) * (unsigned long *)(buf + 2));
    }
LAB_759a_0a9c:
    if (combatStatus != 0 && combatStatus != 3) {
        g_nSceneReloadPending = 1;
        g_nMapReloadPending = 1;
    }
    return;
}

int far hotspotevt_monst_load_speak(ZoneHotspot *pHotspot) {
    char buf[8];

    if (hotspotevt_available(pHotspot)) {
        hotspotevt_bak_load_indexed_rec(3, buf, pHotspot->dwDef_record_offset);
        if (*(unsigned long *)(buf + 2) != 0) {
            dialog_play_record(*(unsigned long *)(buf + 2), 1);
        }
        if (pHotspot->wEvent_key_post != 0) {
            gstate_event_write(pHotspot->wEvent_key_post, 1);
        }
        if (pHotspot->wRepeat == 0) {
            if (pHotspot->bInhibitChapter != 0) {
                hotspotevt_done_set();
            }
            hotspotevt_scout_tried_set();
        }
        return 1;
    }
    return 0;
}

void far hotspotevt_maybe_play_random_sfx(ZoneHotspot *pHotspot) {
    char buf[8];

    if (hotspotevt_available(pHotspot)) {
        hotspotevt_bak_load_indexed_rec(5, buf, pHotspot->dwDef_record_offset);
        if (RND(100) <= (unsigned char)buf[2]) {
            audio_sfx_play_n_times(*(int *)(buf + 3), 0, 1);
            if (pHotspot->wEvent_key_post != 0) {
                gstate_event_write(pHotspot->wEvent_key_post, 1);
            }
        }
        if (pHotspot->bInhibitChapter != 0) {
            hotspotevt_done_set();
        }
    }
}

void far hotspotevt_show_record_message(ZoneHotspot *pHotspot, int *out_skipped,
                                        int *out_confirmed) {
    unsigned char buf[22];

    if (hotspotevt_available(pHotspot) != 0) {
        hotspotevt_bak_load_indexed_rec(6, buf, pHotspot->dwDef_record_offset);
        *out_skipped = 0;
        if (*(unsigned long *)(buf + 6) != 0) {
            *out_confirmed = (dialog_play_record(*(unsigned long *)(buf + 6), 0) == 0);
        } else {
            *out_confirmed = 0;
        }
    } else {
        *out_skipped = 1;
        *out_confirmed = 0;
    }
}

void far hotspotevt_action_enter_town(ZoneHotspot *evt) {
    char buf[21];

    hotspotevt_bak_load_indexed_rec(6, buf, evt->dwDef_record_offset);
    if (buf[0x12] != '\0') {
        map_animate_camera_to_tile((TileMoveRecord *)(buf + 0xE));
    }
    townscene_main_loop(*(unsigned int *)(buf + 2), 1);
    if (evt->wEvent_key_post != 0) {
        gstate_event_write(evt->wEvent_key_post, 1);
    }
    if (!(int)g_gameState.abTeleportRecord[0]) {
        g_nSceneReloadPending = 1;
        g_nMapReloadPending = 1;
    }
    return;
}

void far hotspotevt_trap_prefire_scout(int nReentry, ZoneHotspot *evt, int *pOut_ambush_just_armed,
                                       int *pOut_handled, int *pOut_should_fire) {
    DefTrapRecord trapRec;
    register int *pOutHandled = pOut_handled;
    register int *pOutFire = pOut_should_fire;

    *pOut_ambush_just_armed = 0;
    if (hotspotevt_done_read() != 0 ||
        (evt->wEvent_flag_pre2 != 0 && gstate_event_read(evt->wEvent_flag_pre2) != 0) ||
        (evt->wEvent_flag_pre1 != 0 && gstate_event_read(evt->wEvent_flag_pre1) == 0)) {
        *pOutFire = 0;
        *pOutHandled = 1;
        return;
    }
    hotspotevt_bak_load_indexed_rec(7, &trapRec, evt->dwDef_record_offset);
    if (hotspotevt_enc_fought_read(trapRec.dwCombat_index) != 0) {
        *pOutFire = 0;
        *pOutHandled = 1;
        return;
    }
    if ((trapRec.wIs_ambush & 1) != 0) {
        if (nReentry != 0) {
            *pOutFire = 0;
            *pOutHandled = 1;
            return;
        }
        *pOut_ambush_just_armed = 1;
        if (hotspotevt_scout_tried_read() == 0) {
            hotspotevt_scout_tried_set();
            if (RND(100) <= stat_party_find_extreme(0xe, 0, (short *)0)) {
                stat_party_broadcast_status_op(0xe, 1L, 3);
                if (trapRec.dwScout_dialog != 0)
                    dialog_play_record(trapRec.dwScout_dialog, 1);
                else
                    dialog_play_record(0x2fL, 1);
                hotspotevt_scouted_set();
                *pOutFire = 0;
                *pOutHandled = 0;
                return;
            }
        }
    }
    *pOutFire = 1;
    *pOutHandled = 1;
}

typedef struct {
    long pos_x;
    long pos_y;
    long pos_z;
} CamPos;

void far hotspotevt_trap_main_fire(ZoneHotspot *pHotspot, unsigned short *pOut_status) {
    short wOrig_heading;
    int combat_status;
    int wHas_fired;
    GamePositionAndHeading landing_chosen;
    unsigned char tileX;
    unsigned char tileY;
    long visitedTime;
    DefTrapRecord trapRec;
    unsigned char originalCamera[12];

    *(CamPos far *)originalCamera = *(CamPos far *)&g_world_camera->base.pos.xy.nWorld_x;
    wOrig_heading = g_world_camera->base.orientation.yaw;
    wHas_fired = 0;
    *pOut_status = 0;

    hotspotevt_bak_load_indexed_rec(7, &trapRec, pHotspot->dwDef_record_offset);

    if (hotspotevt_monst_dispatch_by_tag(trapRec.dwCombat_index) == 0) {
        if (((trapRec.wIs_ambush & 1) != 0 && hotspotevt_scouted_read() != 0) ||
            ((trapRec.wIs_ambush & 1) == 0 && spellfx_event_mask_test_bit(0) != 0)) {
            if (g_wHotspotEventEnabled != 0) {
                unsigned int uStat;
                if (worldmove_step_tick_get() == 0) {
                    return;
                }
                uStat = stat_party_find_extreme(0xf, 0, (short *)0);
                g_gameState.nEvtArgActor0 = g_gameState.nEvtArgStat;
                if ((int)uStat < 0x5a) {
                    uStat = uStat + (int)(uStat * 0x1e) / 100;
                    if (0x5a < (int)uStat) {
                        uStat = 0x5a;
                    }
                }
                if ((trapRec.wIs_ambush & 1) != 0 && spellfx_event_mask_test_bit(0) != 0)
                    uStat = uStat + (int)(100 - uStat) / 2;
                if (RND(100) <= uStat) {
                    stat_party_broadcast_status_op(0xf, 1, 3);
                    return;
                }
            }
        }
    }

    czone_get_party_tile_xy(&tileX, &tileY);
    g_world_camera->base.pos.xy.nWorld_x =
        (long)(int)(unsigned int)tileX * 64000 + trapRec.landing_primary.nX;
    g_world_camera->base.pos.xy.nWorld_y =
        (long)(int)(unsigned int)tileY * 64000 + trapRec.landing_primary.nY;
    g_world_camera->base.orientation.yaw = trapRec.landing_primary.wHeading_raw;

    if (combatgrid_tiles_over_thresh() == 0) {
        *(CamPos far *)&g_world_camera->base.pos.xy.nWorld_x = *(CamPos far *)originalCamera;
        g_world_camera->base.orientation.yaw = wOrig_heading;
        return;
    }

    gstate_temp_file_read_at((unsigned char far *)&visitedTime, GAM_ENC_VISITED_TIME(trapRec.dwCombat_index),
                             4);

    if ((g_gameState.game_time - visitedTime) / 0x1e <= 0x1e) {
        if (RND(100) <= stat_party_find_extreme(0xf, 0, (short *)0)) {
            stat_party_broadcast_status_op(0xf, 1, 3);
            wHas_fired = 1;
            g_gameState.nEvtArgCount = 0;
        } else {
            g_gameState.nEvtArgCount = 1;
        }
    } else {
        g_gameState.nEvtArgCount = 2;
    }

    g_gameState.nEvtArgAux1 = trapRec.pCombatants[0].wMonster_index;

    if (trapRec.dwEntry_dialog != 0)
        dialog_play_record(trapRec.dwEntry_dialog, 1);

    combat_arena_actor_turn_loop((unsigned short)trapRec.dwCombat_index, &combat_status, wHas_fired);

    if (combat_status == 2) {
        *(CamPos far *)&g_world_camera->base.pos.xy.nWorld_x = *(CamPos far *)originalCamera;
        g_world_camera->base.orientation.yaw = wOrig_heading;
    }
    g_wLastTempWriteRecordKind = 1;
    gstate_temp_file_write_at((unsigned char far *)&g_gameState.game_time,
                              GAM_ENC_FOUGHT_TIME(trapRec.dwCombat_index), 4);

    if (combat_status == 2) {
        *pOut_status = 1;
        switch (worldmove_aabb_outcode_rotated(&pHotspot->bbox.minX) - 1) {
        case 0:
            *(GamePositionAndHeading far *)&landing_chosen =
                *(GamePositionAndHeading far *)&trapRec.landing_dir1;
            break;
        case 1:
            *(GamePositionAndHeading far *)&landing_chosen =
                *(GamePositionAndHeading far *)&trapRec.landing_dir2;
            break;
        case 3:
            *(GamePositionAndHeading far *)&landing_chosen =
                *(GamePositionAndHeading far *)&trapRec.landing_dir4;
            break;
        case 7:
            *(GamePositionAndHeading far *)&landing_chosen =
                *(GamePositionAndHeading far *)&trapRec.landing_dir8;
            break;
        default:
            *(GamePositionAndHeading far *)&landing_chosen =
                *(GamePositionAndHeading far *)&trapRec.landing_dir1;
            break;
        }
        czone_get_party_tile_xy(&tileX, &tileY);
        g_world_camera->base.pos.xy.nWorld_x = (unsigned long)tileX * 64000 + landing_chosen.nX;
        g_world_camera->base.pos.xy.nWorld_y = (unsigned long)tileY * 64000 + landing_chosen.nY;
        g_world_camera->base.orientation.yaw = landing_chosen.wHeading_raw;
    } else if (combat_status == 1) {
        if (pHotspot->wEvent_key_post != 0)
            gstate_event_write(pHotspot->wEvent_key_post, 1);
        hotspotevt_done_set();
        hotspotevt_enc_fought_set(trapRec.dwCombat_index);
        evtcond_dispatch_key_to_handler((unsigned short)trapRec.dwCombat_index);
    }

    if ((combat_status != 0) && (combat_status != 3)) {
        proxscan_full(g_world_widget);
        vislist_sort(g_wVisibleEntrySegment, g_pwVisibleEntryOffsets, g_pVisibleEntryDistances,
                     g_nVisibleEntryCount);
        worldmove_camera_crossing_apply();
        worldloop_party_move_done_clr();
        g_nSceneReloadPending = 1;
        g_nMapReloadPending = 1;
    }
}

void far hotspotevt_action_try_enter_zone(ZoneHotspot *evt, int *pOut_handled,
                                          unsigned int *pOut_accepted) {
    char buf[20];

    if (hotspotevt_available(evt) != 0) {
        hotspotevt_bak_load_indexed_rec(8, buf, evt->dwDef_record_offset);
        *pOut_handled = 0;
        if (((ZoneEntryRecord *)buf)->dwPromptDlgKey != 0) {
            *pOut_accepted =
                (unsigned int)(dialog_play_record(((ZoneEntryRecord *)buf)->dwPromptDlgKey, 0) == 0);
            goto done;
        }
        *pOut_accepted = 0;
    } else {
        *pOut_handled = 1;
        *pOut_accepted = 0;
    }
done:
    if (*pOut_accepted != 0) {
        g_bZoneEntryInProgress = 1;
    }
    return;
}

void far hotspotevt_action_enter_zone(ZoneHotspot *evt) {
    char buf[19];

    hotspotevt_bak_load_indexed_rec(8, buf, evt->dwDef_record_offset);
    if (((ZoneEntryRecord *)buf)->dwEntryDlgKey != 0) {
        dialog_play_record(((ZoneEntryRecord *)buf)->dwEntryDlgKey, 0);
    }
    rgnenc_zone_rectr_save_objects();

    if (buf[2] != g_gameState.nZoneId) {
        zone_world_scene_teardown();
        zone_set_plr_pos_rec(&((ZoneEntryRecord *)buf)->spawn);
        zone_load();
    } else {
        zone_combat_camera_set_world_pos(&((ZoneEntryRecord *)buf)->spawn);
    }
    if (evt->wEvent_key_post != 0) {
        gstate_event_write(evt->wEvent_key_post, 1);
    }
    if (evt->bInhibitChapter != 0) {
        hotspotevt_done_set();
    }
    g_bZoneEntryInProgress = 0;
    dialog_input_wait_with_cooldown(2);
    return;
}

void far hotspotevt_combat_play_sfx_voice(ZoneHotspot *evt) {
    char buf[8];

    if (hotspotevt_available(evt) != 0) {
        hotspotevt_bak_load_indexed_rec(9, buf, evt->dwDef_record_offset);
        if (RND(100) <= (unsigned char)buf[2]) {
            if (*(unsigned short *)(buf + 3) != 0) {
                gstate_event_write(*(unsigned short *)(buf + 3), 0);
            }
        }
        if (evt->wEvent_key_post != 0) {
            gstate_event_write(evt->wEvent_key_post, 1);
        }
        if (evt->bInhibitChapter != 0) {
            hotspotevt_done_set();
        }
    }
}

void far hotspotevt_chance_trigger(ZoneHotspot *evt) {
    char buf[8];

    if (hotspotevt_available(evt) != 0) {
        hotspotevt_bak_load_indexed_rec(10, buf, evt->dwDef_record_offset);
        if (RND(100) <= (unsigned char)buf[2]) {
            if (*(unsigned short *)(buf + 3) != 0) {
                gstate_event_write(*(unsigned short *)(buf + 3), 1);
            }
        }
        if (evt->wEvent_key_post != 0) {
            gstate_event_write(evt->wEvent_key_post, 1);
        }
        if (evt->bInhibitChapter != 0) {
            hotspotevt_done_set();
        }
    }
    return;
}

void far hotspotevt_dlg_run_msg_event(ZoneHotspot *evt, int *out_status) {
    char buf[8];

    if (hotspotevt_available(evt) != 0) {
        hotspotevt_bak_load_indexed_rec(0xb, buf, evt->dwDef_record_offset);
        *out_status = 0;
        if (*(unsigned long *)(buf + 2) != 0) {
            dialog_play_record(*(unsigned long *)(buf + 2), 1);
        }
        if (evt->wEvent_key_post != 0) {
            gstate_event_write(evt->wEvent_key_post, 1);
        }
        if (evt->bInhibitChapter != 0) {
            hotspotevt_done_set();
        }
    } else {
        *out_status = 1;
    }
    return;
}

ZoneHotspot *far hotspotevt_find_at_player_tile(int mode) {
    unsigned char gridX;
    unsigned char gridY;

    czone_world_pos_to_grid_xy((char *)&gridX, (char *)&gridY);
    return hotspotevt_find_at_point(mode, gridX, gridY);
}

ZoneHotspot *hotspotevt_find_at_point(int mode, unsigned char x, unsigned char y) {
    ZoneHotspot *match;
    ZoneHotspot *cur;

    match = (ZoneHotspot *)0x0;
    if ((mode == 1) || (mode == 0)) {
        g_wHotspotIterIdx = 0;
    }
    cur = g_aZoneHotspots + g_wHotspotIterIdx;
    if (mode != 0) {
        for (; (match == (ZoneHotspot *)0x0 && ((int)g_wHotspotIterIdx < (int)g_nHotspotCount));) {
            if ((cur->bbox.minX <= x) &&
                (((x <= cur->bbox.maxX && (y <= cur->bbox.maxY)) && (cur->bbox.minY <= y)))) {
                match = cur;
                g_wHotspotMatchIdx = g_wHotspotIterIdx;
            }
            ++g_wHotspotIterIdx;
            cur = cur + 1;
        }
    }
    return match;
}

ZoneHotspot *hotspotevt_next_entry_19byte(int mode) {
    ZoneHotspot *entry;

    entry = (ZoneHotspot *)0x0;
    if ((mode == 1) || (mode == 0)) {
        g_wHotspotIterCursor = 0;
    }
    if ((mode != 0) && ((int)g_wHotspotIterCursor < (int)g_nHotspotCount)) {
        entry = g_aZoneHotspots + g_wHotspotIterCursor;
        ++g_wHotspotIterCursor;
    }
    return entry;
}

void hotspotevt_done_reset_all(void) {
    unsigned short *p;

    p = (unsigned short *)0;
    do {
        gstate_event_write((unsigned)(p + 200), 0);
        p = (unsigned short *)((int)p + 1);
    } while (p < (unsigned short *)0x12c0);
}

void far hotspotevt_done_set(void) {
    unsigned short slot;
    slot = (g_gameState.nZoneId - 1) * 400;
    slot += (unsigned int)g_apCombat_zone_actor_lists[0]->bRef_pair_index * 10;
    slot += g_wHotspotMatchIdx;

    gstate_event_write(slot + 400, 1);
}

void far hotspotevt_done_clear(void) {
    unsigned short slot;
    slot = (g_gameState.nZoneId - 1) * 400;
    slot += (unsigned int)g_apCombat_zone_actor_lists[0]->bRef_pair_index * 10;
    slot += g_wHotspotMatchIdx;
    gstate_event_write(slot + 400, 0);
}

int far hotspotevt_done_read(void) {
    unsigned short slot;
    slot = (g_gameState.nZoneId - 1) * 400;
    slot += (unsigned int)g_apCombat_zone_actor_lists[0]->bRef_pair_index * 10;
    slot += g_wHotspotMatchIdx;
    return gstate_event_read(slot + 400);
}

void hotspotevt_scout_tried_clear_all(void) {
    unsigned i = 0;

    do {
        gstate_event_write(HOTSPOT_SCOUT_TRIED(i), 0);
        i = i + 1;
    } while (i < 10);
    return;
}

void hotspotevt_scout_tried_set(void) {
    int base = (int)g_wHotspotMatchIdx;
    gstate_event_write(HOTSPOT_SCOUT_TRIED(base), 1);
    return;
}

void hotspotevt_scout_tried_clear(void) {
    int base = (int)g_wHotspotMatchIdx;
    gstate_event_write(HOTSPOT_SCOUT_TRIED(base), 0);
    return;
}

unsigned short far hotspotevt_scout_tried_read(void) {
    int key = g_wHotspotMatchIdx;
    return gstate_event_read(HOTSPOT_SCOUT_TRIED(key));
}

void hotspotevt_scouted_clear_all(void) {
    unsigned i = 0;

    do {
        gstate_event_write(HOTSPOT_SCOUTED(i), 0);
        i = i + 1;
    } while (i < 10);
    return;
}

void hotspotevt_scouted_set(void) {
    int key = g_wHotspotMatchIdx;
    gstate_event_write(HOTSPOT_SCOUTED(key), 1);
    return;
}

void far hotspotevt_scouted_clear(void) {
    int key = g_wHotspotMatchIdx;
    gstate_event_write(HOTSPOT_SCOUTED(key), 0);
    return;
}

unsigned short far hotspotevt_scouted_read(void) {
    int key = g_wHotspotMatchIdx;
    return gstate_event_read(HOTSPOT_SCOUTED(key));
}

void hotspotevt_enc_fought_set(unsigned long key) {
    int lo = (int)key;

    if ((long)key < 1000) {
        gstate_event_write(ENCOUNTER_FOUGHT(lo), 1);
    }
    return;
}

void hotspotevt_enc_fought_clear(unsigned long key) {
    int lo = (int)key;
    if ((long)key < 1000) {
        gstate_event_write(ENCOUNTER_FOUGHT(lo), 0);
    }
    return;
}

unsigned short far hotspotevt_enc_fought_read(unsigned long key) {
    int lo = (int)key;
    if ((long)key < 1000) {
        return gstate_event_read(ENCOUNTER_FOUGHT(lo));
    }
    return 1;
}

void far hotspotevt_tile_rect_world_ctr(unsigned char *tile_rect, long *out_world_xy) {
    unsigned char chunk_x;
    unsigned char chunk_y;

    czone_get_party_tile_xy(&chunk_x, &chunk_y);
    *out_world_xy = (long)(int)(unsigned int)chunk_x * 64000 +
                    ((long)((unsigned long)*tile_rect * 0x640 + ((unsigned long)tile_rect[2] + 1) * 0x640) >> 1);
    out_world_xy[1] =
        (long)(int)(unsigned int)chunk_y * 64000 +
        ((long)((unsigned long)tile_rect[3] * 0x640 + ((unsigned long)tile_rect[1] + 1) * 0x640) >> 1);
}

int far hotspotevt_monst_dispatch_by_tag(long tag) {
    int result;

    result = 0;
    switch (tag) {
    case 0x97L:
    case 0x98L:
    case 0xebL:
    case 0xf5L:
    case 0x123L:
    case 0x125L:
    case 0x14fL:
    case 0x151L:
    case 0x152L:
    case 0x177L:
    case 0x19aL:
    case 0x1adL:
    case 0x1aeL:
        result = 1;
        break;
    }
    return result;
}

void hotspotevt_bak_indexed_rec_info(int record_id, char **out_filename, int *out_record_size) {
    *out_filename = g_aDefFileNames[record_id];
    *out_record_size = g_aDefRecordSizes[record_id];
    return;
}

char far hotspotevt_bak_load_indexed_rec(int record_id, void *dest, long offset) {
    char *filename;
    int record_size;
    char header[4];
    char present;
    BakFile *stream;

    hotspotevt_bak_indexed_rec_info(record_id, &filename, &record_size);
    stream = bak_fopen(filename, "rb");
    bak_fread(header, 4, 1, stream);
    bak_fseek(stream, (unsigned long)(unsigned int)(record_size + 1) * offset, 1);
    bak_fread(&present, 1, 1, stream);
    if (present != '\0') {
        bak_fread(dest, record_size, 1, stream);
    }
    bak_fclose(stream);
    return present;
}
