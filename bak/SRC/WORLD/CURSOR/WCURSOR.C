#include <dos.h>
#include <stdlib.h>
#include "SRC/GAME/GMAIN.H"
#include "SRC/GEN/GFXCTX.H"
#include "SRC/WORLD/ZONE/ZONE.H"
#include "SRC/WORLD/LOOP/WORLDLP.H"
#include "SRC/WORLD/ZONE/CZONE.H"
#include "SRC/WORLD/ZONE/PROXIM.H"
#include "SRC/WORLD/ENC/RGNENC.H"
#include "SRC/R3D/ACTOR/ACTOROVL.H"
#include "structs.h"
#include "SRC/WORLD/CURSOR/WCURSOR.H"
#include "SRC/IO/IO.H"
#include "SRC/SYS/MEM.H"
#include "SRC/AUDIO/ENGINE/AUDIO.H"
#include "SRC/GFX/DRIVER/PALDRV.H"
#include "SRC/R3D/SCENE/WORLDHIT.H"
#include "SRC/GFX/SCREEN/SCREEN.H"
#include "SRC/UI/MENUPAGE.H"
#include "SRC/R3D/TBLSTORE/SHAPETBL.H"
#include "SRC/GAME/GSTATE.H"
#include "SRC/CHAR/STAT.H"
#include "SRC/DIALOG/DIALOG.H"
#include "SRC/SCREENS/TOWNSCN.H"
#include "SRC/SCREENS/CMBINV.H"
#include "SRC/SCREENS/ITEMTBL.H"
#include "SRC/WORLD/ACTOR/ACTSPAWN.H"
#include "SRC/WORLD/ACTOR/ACTORREC.H"
#include "SRC/SCREENS/PICKLOCK.H"
#include "SRC/COMBAT/ENC/CBENC.H"
#include "SRC/COMBAT/SPELL/SPELLFX.H"
#include "SRC/WORLD/ENC/HOTSPOT.H"
#include "SRC/SCREENS/CIPHER.H"
#include "SRC/WORLD/MOVE/WORLDCRS.H"
#include "defines.h"

WorldHotspot *g_pWorldHitTestTable;
long g_anEntityKindRenderDist[43];

unsigned short g_nHitTestEntryCount = 0x0000;
unsigned short g_nHitTestWriteSlot = 0x0000;

void far wcursor_load_detect_dat(void) {
    BakFile *stream;

    stream = bak_fopen("detect.dat", "rb");
    if (g_game_mode == 2) {
        bak_fseek(stream, 0xacL, 1);
    }
    bak_fread(g_anEntityKindRenderDist, 4, 0x2b, stream);
    bak_fclose(stream);
    g_pWorldHitTestTable = galloc_safe_zcalloc(0xa0);
}

void wcursor_free_detect_dat(void) {
    galloc_zfree(g_pWorldHitTestTable);
}

int far wcursor_dispatch_action(void) {
    short cursor_x;
    short cursor_y;
    int slot_index;
    int dispatch_idx;
    int scan_count;
    int idx;
    int cx_diff;
    int cy_diff;

    cursor_x = screen_cursor_get_x();
    cursor_y = screen_cursor_get_y();
    g_graphics_context.wGfxBlitSrcPage = g_graphics_context.wGfxBlitDstPage =
        g_graphics_context.wVgaPage2Base;
    world_render_tick_objects();
    scan_count = 0;
    slot_index = ((g_nHitTestWriteSlot != 0) ? g_nHitTestWriteSlot : 10) - 1;
    if (scan_count < (int)g_nHitTestEntryCount) {
        do {
            cx_diff = cursor_x - g_pWorldHitTestTable[slot_index].rect.x;
            cy_diff = cursor_y - g_pWorldHitTestTable[slot_index].rect.y;
            if (cx_diff >= 0 && cx_diff < g_pWorldHitTestTable[slot_index].rect.width &&
                cy_diff >= 0 && cy_diff < g_pWorldHitTestTable[slot_index].rect.height) {
                if ((&g_pWorldHitTestTable[slot_index])->pEntity->shapeId ==
                    g_nProximityTableCount) {
                    idx = ((EncounterAnimScratch *)(&g_pWorldHitTestTable[slot_index])
                               ->pEntity->state.animationState)
                              ->nEncObjStateIdx;
                    if ((g_pEncounterObjectState[idx].wKind_state & 0xff08) >> 8 == 4)
                        wcursor_loot_corpse(&g_pWorldHitTestTable[slot_index], idx);
                    else
                        wcursor_encounter_hint(&g_pWorldHitTestTable[slot_index], idx);
                    return 1;
                }
                switch ((int)((unsigned)ts_get_shape(
                                  (&g_pWorldHitTestTable[slot_index])->pEntity->shapeId)
                                  ->kind -
                              6)) {
                default:
                    goto loop_continue;
                case 35:
                    wcursor_zone_loot_body(&g_pWorldHitTestTable[slot_index]);
                    break;
                case 10:
                    wcursor_zone_open_container(&g_pWorldHitTestTable[slot_index]);
                    break;
                case 4:
                    wcursor_click_fixedobj_full(&g_pWorldHitTestTable[slot_index]);
                    break;
                case 20:
                case 21:
                case 22:
                    wcursor_interact_container_event(&g_pWorldHitTestTable[slot_index]);
                    break;
                case 13:
                    wcursor_click_blocked_path(&g_pWorldHitTestTable[slot_index]);
                    break;
                case 30:
                    wcursor_script_summon_actor(&g_pWorldHitTestTable[slot_index]);
                    break;
                case 0:
                    wcursor_click_inn_or_lock_npc(&g_pWorldHitTestTable[slot_index]);
                    break;
                case 31:
                    wcursor_click_fixedobj_examine(&g_pWorldHitTestTable[slot_index]);
                    break;
                case 12:
                    wcursor_click_locked_or_sealed(&g_pWorldHitTestTable[slot_index]);
                    break;
                case 29:
                    wcursor_click_fixedobj(&g_pWorldHitTestTable[slot_index]);
                    break;
                case 17:
                    wcursor_object_toggle_open_close(&g_pWorldHitTestTable[slot_index]);
                    break;
                case 14:
                case 33:
                    wcursor_click_npc_or_trap(&g_pWorldHitTestTable[slot_index]);
                    break;
                case 6:
                    wcursor_click_door_or_secret(&g_pWorldHitTestTable[slot_index]);
                    break;
                case 36:
                    wcursor_click_fixedobj_picklock(&g_pWorldHitTestTable[slot_index]);
                    break;
                case 11:
                    wcursor_open_container_at_cursor(&g_pWorldHitTestTable[slot_index]);
                    break;
                case 19:
                    wcursor_click_locked_stub(&g_pWorldHitTestTable[slot_index]);
                    break;
                case 9:
                    worldcross_hotspot_use_rope(&g_pWorldHitTestTable[slot_index]);
                    break;
                case 18:
                    wcursor_interact_fixedobj_variant_a(&g_pWorldHitTestTable[slot_index]);
                    break;
                case 3:
                    wcursor_click_dig_or_use_shovel(&g_pWorldHitTestTable[slot_index]);
                    break;
                case 28:
                    wcursor_click_body(&g_pWorldHitTestTable[slot_index]);
                    break;
                case 27:
                    wcursor_interact_fixedobj_container(&g_pWorldHitTestTable[slot_index]);
                    break;
                case 7:
                    wcursor_fixedobj_examine_var_a(&g_pWorldHitTestTable[slot_index]);
                    break;
                case 23:
                    wcursor_fixedobj_examine_var_b(&g_pWorldHitTestTable[slot_index]);
                    break;
                case 24:
                    wcursor_click_fixedobj_open(&g_pWorldHitTestTable[slot_index]);
                    break;
                case 25:
                    wcursor_fixedobj_examine_var_c(&g_pWorldHitTestTable[slot_index]);
                    break;
                }
                return 1;
            }
        loop_continue:
            scan_count = scan_count + 1;
            if (slot_index != 0)
                slot_index = slot_index - 1;
            else
                slot_index = 9;
        } while (scan_count < (int)g_nHitTestEntryCount);
    }
    return 0;
}

void far wcursor_zone_loot_body(WorldHotspot *pHotspot) {
    Actor far *actor_record;
    ActorSubrecord far *pSub;

    audio_play(0x30);
    dialog_viewport_clip_point(pHotspot->rect.x + pHotspot->rect.width / 2,
                               pHotspot->rect.y + pHotspot->rect.height / 2);
    if (menupage_state_0e7c() == 1) {
        actor_record =
            actorspawn_objfixed((unsigned int)g_gameState.nZoneId, pHotspot->pEntity->pos.xy.nWorld_x,
                                pHotspot->pEntity->pos.xy.nWorld_y);
        if (actor_record == 0 || actor_record->bResidence != RES_ENCOUNTER) {
            dialog_play_record(0x9a, 1);
        } else {
            pSub = actorrec_get_subrecord(actor_record, SUBREC_INTERACT_MSG);
            if (pSub != 0 && pSub->interact_msg.dwMessage_id != 0)
                dialog_play_record(pSub->interact_msg.dwMessage_id, 1);
            else
                dialog_play_record(0x9e, 1);
            actorspawn_npc_prox_periodic(actor_record);
            cmbinv_inventory_screen_run(actor_record, 0, 0);
        }
        if (actor_record != 0)
            actorspawn_destroy_and_persist(actor_record);
        return;
    }
    dialog_play_record(0x5d, 1);
}

void far wcursor_zone_open_container(WorldHotspot *pHotspot) {
    Actor far *actor_record;
    ActorSubrecord far *pSub;
    long dist_threshold;

    if (g_game_mode != 2) {
        dist_threshold = 7000;
    } else {
        dist_threshold = 0x9c4;
    }
    if ((long)pHotspot->dwDist <= dist_threshold) {
        audio_play(0x30);
        dialog_viewport_clip_point(pHotspot->rect.x + pHotspot->rect.width / 2,
                                   pHotspot->rect.y + pHotspot->rect.height / 2);
        if (menupage_state_0e7c() == 1) {
            actor_record =
                actorspawn_objfixed((unsigned int)g_gameState.nZoneId, pHotspot->pEntity->pos.xy.nWorld_x,
                                    pHotspot->pEntity->pos.xy.nWorld_y);
            if (actor_record == 0 || (actor_record->bResidence != RES_BODY &&
                                      actor_record->bResidence != RES_SELF_SPAWN)) {
                dialog_play_record(0x9a, 1);
            } else {
                pSub = actorrec_get_subrecord(actor_record, SUBREC_INTERACT_MSG);
                if (pSub != 0 && pSub->interact_msg.dwMessage_id != 0) {
                    dialog_play_record(pSub->interact_msg.dwMessage_id, 1);
                } else {
                    dialog_play_record(0x4e, 1);
                }
                actorspawn_npc_prox_periodic(actor_record);
                cmbinv_inventory_screen_run(actor_record, 0, 0);
            }
            if (actor_record != 0)
                actorspawn_destroy_and_persist(actor_record);
        } else {
            dialog_play_record(0x5e, 1);
        }
    }
}

void far wcursor_click_fixedobj_full(WorldHotspot *pHotspot) {
    long pos_x;
    long pos_y;
    int nDispatchResult;
    int lookupkey;
    Actor far *actor;
    ActorSubrecord far *pSub2;
    ActorSubrecord far *pSub1;
    ActorSubrecord far *pSub8;
    unsigned char bHotspot_x;
    unsigned char bHotspot_y;
    unsigned char bWarp_kind;
    unsigned char bWarp_dest;
    int bGo;
    int bFlag1Clear;
    unsigned short uEventFlag;

    pos_x = pHotspot->pEntity->pos.xy.nWorld_x;
    pos_y = pHotspot->pEntity->pos.xy.nWorld_y;
    bGo = 1;
    actor = actorspawn_objfixed((unsigned int)g_gameState.nZoneId, pos_x, pos_y);
    if (actor == 0 || actor->bResidence != RES_FIXED_OBJECT ||
        (pSub2 = actorrec_get_subrecord(actor, SUBREC_INTERACT_MSG)) == 0) {
        dialog_play_record(0x9aUL, 1);
        goto cleanup;
    }
    pSub8 = actorrec_get_subrecord(actor, SUBREC_HOTSPOT);
    if (pSub8 != 0 && pSub8->hotspot_action.bHas_hotspot != 0 &&
        (pos_x / 64000L != (unsigned long)g_apCombat_zone_actor_lists[0]->bParty_x ||
         pos_y / 64000L != (unsigned long)g_apCombat_zone_actor_lists[0]->bParty_y))
        goto cleanup;

    audio_play(0x30);
    dialog_viewport_clip_point(pHotspot->rect.x + pHotspot->rect.width / 2,
                               pHotspot->rect.y + pHotspot->rect.height / 2);
    if (menupage_state_0e7c() != 1)
        goto cancel;

    if ((pSub2->interact_msg.bFlags & 0x20) != 0) {
        if (dialog_play_record(pSub2->interact_msg.dwMessage_id, 0) < 0) {
            pSub8 = 0;
            bGo = 0;
        }
    }
    if (pSub8 != 0 && pSub8->hotspot_action.bHas_hotspot != 0) {
        bHotspot_x = pSub8->hotspot_action.bHotspot_x;
        bHotspot_y = pSub8->hotspot_action.bHotspot_y;
        actorspawn_destroy_and_persist(actor);
        actor = 0;
        if (hotspotevt_dispatch_at_point(7, bHotspot_x, bHotspot_y, &nDispatchResult) != 0) {
            if (nDispatchResult != 0)
                bGo = 0;
        } else {
            dialog_play_record(0x9aUL, 1);
            bGo = 0;
        }
        actor = actorspawn_objfixed((unsigned int)g_gameState.nZoneId, pos_x, pos_y);
        pSub2 = actorrec_get_subrecord(actor, SUBREC_INTERACT_MSG);
        pSub8 = actorrec_get_subrecord(actor, SUBREC_HOTSPOT);
    }
    if (!bGo)
        goto cleanup;

    pSub1 = actorrec_get_subrecord(actor, SUBREC_PARAMS);
    lookupkey = (pSub1 != 0) ? pSub1->params.door_or_npc_key.bLookup_key : 0;
    bFlag1Clear = !(pSub2->interact_msg.bFlags & 1);
    uEventFlag = gstate_event_read(0x753a);
    if (bFlag1Clear || uEventFlag != 0)
        g_gameState.nEvtArgCount = 0;
    else
        g_gameState.nEvtArgCount = 1;

    if (lookupkey != 0) {
        if (picklock_screen_run(lookupkey, 2, (Actor far *)0) == 0)
            goto cleanup;
        if (pSub2->interact_msg.dwMessage_id != 0) {
            if ((pSub2->interact_msg.bFlags & 0x20) == 0) {
                if (dialog_play_record(pSub2->interact_msg.dwMessage_id, 0) == -1)
                    goto cleanup;
            }
            if (bFlag1Clear) {
                if ((pSub2->interact_msg.bFlags & 2) != 0)
                    cmbinv_inventory_screen_run(actor, 0, 0);
                goto cleanup;
            }
            if (uEventFlag != 0)
                goto cleanup;
            if ((pSub2->interact_msg.bFlags & 2) != 0)
                cmbinv_inventory_screen_run(actor, 0, 0);
            goto cleanup;
        }
        dialog_play_record(0x9aUL, 1);
        goto cleanup;
    } else {
        if (pSub2->interact_msg.dwMessage_id != 0) {
            if ((pSub2->interact_msg.bFlags & 0x20) == 0) {
                if (dialog_play_record(pSub2->interact_msg.dwMessage_id, 0) == -1)
                    goto cleanup;
            }
            if (!bFlag1Clear && uEventFlag == 0)
                goto cleanup;
            if (pSub8 != 0 && pSub8->hotspot_action.bWarp_kind != 0) {
                bWarp_kind = pSub8->hotspot_action.bWarp_kind;
                bWarp_dest = pSub8->hotspot_action.bWarp_dest;
                actorspawn_destroy_and_persist(actor);
                actor = 0;
                townscene_main_loop(bWarp_kind, bWarp_dest);
                if (!g_gameState.abTeleportRecord[0])
                    g_nSceneReloadPending = 1;
                goto cleanup;
            }
            if ((pSub2->interact_msg.bFlags & 2) != 0)
                cmbinv_inventory_screen_run(actor, 0, 0);
            goto cleanup;
        }
        dialog_play_record(0x9aUL, 1);
        goto cleanup;
    }

cancel:
    g_gameState.nEvtArgCount = pSub2->interact_msg.bKind_or_id;
    dialog_play_record(0x60UL, 1);
cleanup:
    if (actor != 0)
        actorspawn_destroy_and_persist(actor);
    return;
}

void far wcursor_interact_container_event(WorldHotspot *pHotspot) {
    int bKind;
    Actor far *actor;
    ActorSubrec02_InteractMsg far *pMsg;
    unsigned long dwRecord;

    dwRecord = 0;
    bKind = ts_get_shape(pHotspot->pEntity->shapeId)->kind;
    audio_play(0x30);
    dialog_viewport_clip_point(pHotspot->rect.x + pHotspot->rect.width / 2,
                               pHotspot->rect.y + pHotspot->rect.height / 2);
    if (menupage_state_0e7c() == 1) {
        actor = actorspawn_objfixed(g_gameState.nZoneId, pHotspot->pEntity->pos.xy.nWorld_x,
                                    pHotspot->pEntity->pos.xy.nWorld_y);
        if (actor == 0 || actor->bResidence != RES_FIXED_OBJECT) {
            dialog_play_record(0x9a, 1);
        } else {
            pMsg = actorrec_get_subrecord(actor, SUBREC_INTERACT_MSG);
            if (pMsg != 0 && pMsg->dwMessage_id != 0) {
                dwRecord = pMsg->dwMessage_id;
            } else {
                switch (bKind) {
                case 0x1a:
                    dwRecord = 0x9f;
                    break;
                case 0x1c:
                    dwRecord = 0xa0;
                    break;
                case 0x1b:
                    dwRecord = 0xa1;
                    break;
                }
            }
            dialog_play_record(dwRecord, 1);
            cmbinv_inventory_screen_run(actor, 0, 0);
        }
        if (actor != 0)
            actorspawn_destroy_and_persist(actor);
    } else {
        switch (bKind) {
        case 0x1a:
            dwRecord = 0xa2;
            break;
        case 0x1c:
            dwRecord = 0xa3;
            break;
        case 0x1b:
            dwRecord = 0xa4;
            break;
        }
        dialog_play_record(dwRecord, 1);
    }
    return;
}

void far wcursor_click_blocked_path(WorldHotspot *pHotspot) {
    audio_play(0x30);
    dialog_viewport_clip_point(pHotspot->rect.x + pHotspot->rect.width / 2,
                               pHotspot->rect.y + pHotspot->rect.height / 2);
    if (menupage_state_0e7c() == 1) {
        dialog_play_record(0xa5UL, 1);
    } else {
        dialog_play_record(0xa6UL, 1);
    }
}

void far wcursor_script_summon_actor(WorldHotspot *pHotspot) {
    Actor far *actor_record;
    ActorSubrecord far *pSub2;
    ActorSubrecord far *pSub8;
    unsigned int uAnim_state;
    unsigned int uFrame;

    uAnim_state = pHotspot->pEntity->state.animationState;
    audio_play(0x30);
    dialog_viewport_clip_point(pHotspot->rect.x + pHotspot->rect.width / 2,
                               pHotspot->rect.y + pHotspot->rect.height / 2);
    if (menupage_state_0e7c() != 1)
        goto cancel;

    actor_record =
        actorspawn_objfixed((unsigned int)g_gameState.nZoneId, pHotspot->pEntity->pos.xy.nWorld_x,
                            pHotspot->pEntity->pos.xy.nWorld_y);
    if (actor_record == 0 || actor_record->bResidence != RES_FIXED_OBJECT ||
        (pSub2 = actorrec_get_subrecord(actor_record, SUBREC_INTERACT_MSG)) == 0 ||
        pSub2->interact_msg.dwMessage_id == 0 ||
        (pSub8 = actorrec_get_subrecord(actor_record, SUBREC_HOTSPOT)) == 0 ||
        pSub8->hotspot_action.wPad_0 == 0) {
        dialog_play_record(0x9a, 1);
    } else {
        dialog_play_record(pSub2->interact_msg.dwMessage_id, 1);
        if (gstate_event_read(pSub8->hotspot_action.wPad_0) != 0) {
            screen_cursor_show_busy();
            g_graphics_context.wGfxBlitDstPage = g_graphics_context.wGfxBlitSrcPage =
                g_graphics_context.wVgaPage2Base;
            world_render_scene_dispatch(0);
            screen_frame_flip();
            g_graphics_context.wGfxBlitDstPage = g_graphics_context.wGfxBlitSrcPage =
                g_graphics_context.wVgaPage2Base;
            world_render_scene_dispatch(0);
            audio_sfx_register_45();
            for (uFrame = 1; (int)uFrame >= 0; uFrame--) {
                uAnim_state = uAnim_state & 0xff00 | uFrame;
                pHotspot->pEntity->state.animationState = uAnim_state;
                g_graphics_context.wGfxBlitDstPage = g_graphics_context.wGfxBlitSrcPage =
                    g_graphics_context.wVgaPage2Base;
                world_render_scene_dispatch(0);
                screen_frame_present();
            }
            uFrame = 0;
            do {
                uAnim_state = uAnim_state & 0xff00 | uFrame;
                pHotspot->pEntity->state.animationState = uAnim_state;
                g_graphics_context.wGfxBlitDstPage = g_graphics_context.wGfxBlitSrcPage =
                    g_graphics_context.wVgaPage2Base;
                world_render_scene_dispatch(0);
                screen_frame_present();
                uFrame++;
            } while ((int)uFrame < 2);
            audio_sfx_play_n_times(0x2d, 0, 0);
            g_graphics_context.wGfxBlitDstPage = g_graphics_context.wGfxBlitSrcPage =
                g_graphics_context.wVgaPage2Base;
            world_render_scene_dispatch(0);
            audio_sfx_stop_45();
            screen_cursor_restore_shape();
        }
    }
    if (actor_record != 0) {
        actorspawn_destroy_and_persist(actor_record);
    }
    return;

cancel:
    dialog_play_record(0xa7, 1);
}

void far wcursor_click_inn_or_lock_npc(WorldHotspot *pHotspot) {
    Actor far *pActor;
    ActorSubrecord far *pInteract;
    ActorSubrecord far *pMsgRec;
    int bRunProx;
    int bHandled;
    int bDenied;
    int sfx_handle;
    short member_idx;
    int stat_val;
    unsigned long deferred_msg;
    ActorSubrecord far *pHotspotRec;

    int frame;
    unsigned int interact_kind;

    bRunProx = 1;
    bHandled = 0;
    bDenied = 0;
    member_idx = -1;
    deferred_msg = 0;

    audio_play(0x30);
    dialog_viewport_clip_point(pHotspot->rect.x + pHotspot->rect.width / 2,
                               pHotspot->rect.y + pHotspot->rect.height / 2);

    pActor = actorspawn_objfixed((unsigned int)g_gameState.nZoneId, pHotspot->pEntity->pos.xy.nWorld_x,
                                 pHotspot->pEntity->pos.xy.nWorld_y);

    if (pActor == 0 ||
        (pActor->bResidence != RES_CONTAINER && pActor->bResidence != RES_SELF_SPAWN)) {
        dialog_play_record(0x9a, 1);
        goto cleanup;
    }

    pInteract = actorrec_get_subrecord(pActor, SUBREC_PARAMS);

    if (pInteract != 0) {
        if (pInteract->interact_msg.bKind_or_id & 4) {
            interact_kind = 0;
        } else if ((char)pInteract->interact_msg.dwMessage_id != '\0') {
            interact_kind = 1;
        } else {
            interact_kind = 2;
        }
    } else {
        interact_kind = 3;
    }

    if (menupage_state_0e7c() == 1) {
        switch (interact_kind) {
        case 0:
            g_gameState.nEvtArgCount = 0;
            if (spellfx_event_mask_test_bit(5) &&
                *((unsigned char far *)&pInteract->interact_msg.dwMessage_id + 1) != '\0') {
                if (dialog_play_record(0xbe, 1) == 0) {
                    stat_val = stat_party_find_extreme(0xd, 0, &member_idx);
                    g_gameState.nEvtArgActor0 = member_idx;
                    if ((int)(unsigned int)pInteract->interact_msg.bFlags < (int)(unsigned int)stat_val) {
                        dialog_play_record(0xbf, 1);
                        *((unsigned char far *)&pInteract->interact_msg.dwMessage_id + 1) = 0;
                        pActor->needsFlush = TRUE;
                        stat_combatant_modify(&g_gameState.party_members[member_idx], 0xd, 2, 3);
                    apply_bonus:
                        bHandled = 1;
                        bRunProx = 0;
                    } else {
                        bDenied = 1;
                    }
                }
            } else if (*((unsigned char far *)&pInteract->interact_msg.dwMessage_id + 1) != '\0') {
                if (dialog_play_record(0x4f, 1) == 0)
                    bDenied = 1;
            } else {
                if (dialog_play_record(0x13d, 1) == 0)
                    goto apply_bonus;
            }
            break;

        case 1:
            bHandled =
                cipher_dial_puzzle_run((unsigned int)(unsigned char)pInteract->interact_msg.dwMessage_id);
            break;
        case 2:
            picklock_screen_run((unsigned int)pInteract->interact_msg.bFlags, 0, pActor);
            break;
        case 3:
            dialog_play_record(0xc2, 1);
            bHandled = 1;
            break;
        }

        if (bHandled != 0) {
            if (bRunProx != 0) {
                actorspawn_npc_prox_periodic(pActor);
            }
            pHotspotRec = actorrec_get_subrecord(pActor, SUBREC_HOTSPOT);
            if (pHotspotRec != 0 && pHotspotRec->hotspot_action.wGame_state_event_id == 0x7541) {
                g_gameState.nWorldLoopExitRequest = '\x01';
            }
            if (!g_gameState.nWorldLoopExitRequest) {
                cmbinv_inventory_screen_run(pActor, 0, 0);
            }
            if ((pMsgRec = actorrec_get_subrecord(pActor, SUBREC_INTERACT_MSG)) != 0 &&
                pMsgRec->interact_msg.dwMessage_id != 0) {
                deferred_msg = pMsgRec->interact_msg.dwMessage_id;
            }
        } else {
            if (bDenied != 0) {
                sfx_handle = audio_sfx_play_n_times(0x39, 0, 0);
                frame = 0;
                do {
                    pHotspot->pEntity->state.animationState = frame + 1;
                    g_graphics_context.wGfxBlitDstPage = g_graphics_context.wGfxBlitSrcPage =
                        g_graphics_context.wVgaPage2Base;
                    world_render_scene_dispatch(1);
                    screen_frame_present();
                    if (frame == 1) {
                        palette_set_scaled(0x70, 0x90, 0x2c, 0x30);
                    } else if (frame == 2) {
                        palette_set_scaled(0x70, 0x90, 0x2c, 0x20);
                    }
                    frame = frame + 1;
                } while (frame < 3);
                for (frame = 1; frame >= 0; frame = frame - 1) {
                    pHotspot->pEntity->state.animationState = frame + 1;
                    g_graphics_context.wGfxBlitDstPage = g_graphics_context.wGfxBlitSrcPage =
                        g_graphics_context.wVgaPage2Base;
                    world_render_scene_dispatch(1);
                    screen_frame_present();
                    if (frame == 1) {
                        palette_set_scaled(0x70, 0x90, 0x2c, 0x30);
                    } else if (frame == 0) {
                        palette_set_scaled(0x70, 0x90, 0x2c, 0x3f);
                    }
                }
                pHotspot->pEntity->state.animationState = 0;
                frame = 0;
                do {
                    g_graphics_context.wGfxBlitDstPage = g_graphics_context.wGfxBlitSrcPage =
                        g_graphics_context.wVgaPage2Base;
                    world_render_scene_dispatch(1);
                    screen_frame_present();
                    frame = frame + 1;
                } while (frame < 2);
                if (sfx_handle != 0) {
                    audio_sfx_stop(0x39);
                }
                dialog_play_record(0xc0, 1);
                stat_party_broadcast_status_op(
                    0x10,
                    -(long)((unsigned long) *
                                ((unsigned char far *)&pInteract->interact_msg.dwMessage_id + 1)
                            << 8),
                    100);
                *((unsigned char far *)&pInteract->interact_msg.dwMessage_id + 1) = 0;
                pActor->needsFlush = TRUE;
            }
        }
        goto cleanup;
    }

    /* Out-of-world-view fallback dispatch on interact_kind. case 0 and case 2
     * carry identical bodies (dialog_play_record 0x5b). */
    switch (interact_kind) {
    case 0:
        dialog_play_record(0x5b, 1);
        break;
    case 1:
        dialog_play_record(0x5c, 1);
        break;
    case 2:
        dialog_play_record(0x5b, 1);
        break;
    case 3:
        dialog_play_record(0xc3, 1);
        break;
    }

cleanup:
    if (pActor != 0) {
        actorspawn_destroy_and_persist(pActor);
    }
    if (deferred_msg != 0) {
        dialog_play_record(deferred_msg, 1);
    }
    return;
}

void far wcursor_click_fixedobj_examine(WorldHotspot *hotspot) {
    Actor far *actor_record;
    ActorSubrecord far *pSubrec;

    audio_play(0x30);
    dialog_viewport_clip_point(hotspot->rect.x + hotspot->rect.width / 2,
                               hotspot->rect.y + hotspot->rect.height / 2);
    if (menupage_state_0e7c() != 1)
        goto cancel;

    actor_record = actorspawn_objfixed((unsigned int)g_gameState.nZoneId, hotspot->pEntity->pos.xy.nWorld_x,
                                       hotspot->pEntity->pos.xy.nWorld_y);
    if (actor_record == 0 || actor_record->bResidence != RES_FIXED_OBJECT ||
        (pSubrec = actorrec_get_subrecord(actor_record, SUBREC_INTERACT_MSG)) == 0 ||
        pSubrec->interact_msg.dwMessage_id == 0) {
        dialog_play_record(0x9aUL, 1);
    } else {
        dialog_play_record(pSubrec->interact_msg.dwMessage_id, 1);
    }
    if (actor_record != 0) {
        actorspawn_destroy_and_persist(actor_record);
    }
    return;

cancel:
    dialog_play_record(0xa8UL, 1);
}

void far wcursor_click_locked_or_sealed(WorldHotspot *pHotspot) {
    audio_play(0x30);
    dialog_viewport_clip_point(pHotspot->rect.x + pHotspot->rect.width / 2,
                               pHotspot->rect.y + pHotspot->rect.height / 2);
    if (menupage_state_0e7c() == 1) {
        dialog_play_record(0xa9UL, 1);
    } else {
        dialog_play_record(0xaaUL, 1);
    }
}

void far wcursor_click_fixedobj(WorldHotspot *pHotspot) {
    Actor far *actor_record;
    ActorSubrec02_InteractMsg far *pSubrec;

    audio_play(0x30);
    dialog_viewport_clip_point(pHotspot->rect.x + pHotspot->rect.width / 2,
                               pHotspot->rect.y + pHotspot->rect.height / 2);
    if (menupage_state_0e7c() != 1)
        goto cancel;

    actor_record =
        actorspawn_objfixed((unsigned int)g_gameState.nZoneId, pHotspot->pEntity->pos.xy.nWorld_x,
                            pHotspot->pEntity->pos.xy.nWorld_y);
    if (actor_record == 0 || actor_record->bResidence != RES_FIXED_OBJECT) {
        dialog_play_record(0x9aUL, 1);
    } else {
        pSubrec = (ActorSubrec02_InteractMsg far *)actorrec_get_subrecord(actor_record,
                                                                          SUBREC_INTERACT_MSG);
        if (pSubrec != 0 && pSubrec->dwMessage_id != 0) {
            dialog_play_record(pSubrec->dwMessage_id, 1);
        } else {
            dialog_play_record(0xabUL, 1);
        }
        cmbinv_inventory_screen_run(actor_record, 0, 0);
    }
destroy:
    if (actor_record != 0)
        actorspawn_destroy_and_persist(actor_record);
    return;
cancel:
    dialog_play_record(0xacUL, 1);
}

int far wcursor_object_toggle_open_close(WorldHotspot *pHotspot) {
    unsigned int state_word;
    unsigned int id;
    int yaw_lock;
    int i;

    state_word = pHotspot->pEntity->state.animationState;
    id = (state_word & 0x7f8) >> 3;
    i = menupage_state_0e7c() == 2;
    yaw_lock = pHotspot->pEntity->orientation.pitch;
    audio_play(0x30);
    if (state_word == 0)
        return;

    if (gstate_event_read((unsigned short)DOOR_OPEN(id)) != 0) {

        if (i != 0) {
            dialog_viewport_clip_point(pHotspot->rect.x + pHotspot->rect.width / 2,
                                       pHotspot->rect.y + pHotspot->rect.height / 2);
            dialog_play_record(99UL, 1);
            return;
        }
        if (g_world_camera->base.pos.xy.nWorld_x >= pHotspot->pEntity->pos.xy.nWorld_x - 800 &&
            g_world_camera->base.pos.xy.nWorld_x <= pHotspot->pEntity->pos.xy.nWorld_x + 800 &&
            g_world_camera->base.pos.xy.nWorld_y >= pHotspot->pEntity->pos.xy.nWorld_y - 800 &&
            g_world_camera->base.pos.xy.nWorld_y <= pHotspot->pEntity->pos.xy.nWorld_y + 800) {
            dialog_viewport_clip_point(pHotspot->rect.x + pHotspot->rect.width / 2,
                                       pHotspot->rect.y + pHotspot->rect.height / 2);
            return dialog_play_record(0x9dUL, 1);
        }
        screen_cursor_show_busy();
        audio_sfx_register_pair_38_39();
        gstate_event_write((unsigned short)DOOR_OPEN(id), 0);
        state_word &= 0xf7ff;
        audio_play(0x26);
        for (i = 7; i >= 0; i--) {
            state_word = state_word & 0xfff8 | i;
            pHotspot->pEntity->state.animationState = state_word;
            world_render_scene_dispatch(0);
            screen_frame_present();
        }
        world_render_scene_dispatch(0);
        audio_sfx_play_n_times(0x27, 0, 1);
    } else {

        if (yaw_lock != 0 || i != 0)
            dialog_viewport_clip_point(pHotspot->rect.x + pHotspot->rect.width / 2,
                                       pHotspot->rect.y + pHotspot->rect.height / 2);
        if (i != 0) {
            dialog_play_record(100UL, 1);
            return;
        }
        if (yaw_lock != 0 && picklock_screen_run(yaw_lock, 1, (Actor far *)0) == 0)
            return;
        screen_cursor_show_busy();
        audio_sfx_register_pair_38_39();
        gstate_event_write((unsigned short)DOOR_OPEN(id), 1);
        state_word |= 0x800;
        audio_play(0x26);
        i = 0;
        do {
            state_word = state_word & 0xfff8 | i;
            pHotspot->pEntity->state.animationState = state_word;
            world_render_scene_dispatch(0);
            screen_frame_present();
            i++;
        } while (i < 8);
        world_render_scene_dispatch(0);
    }
    audio_sfx_stop_pair_38_39();
    screen_cursor_restore_shape();
}

void far wcursor_click_npc_or_trap(WorldHotspot *pHotspot) {
    Actor far *actor_record;
    ActorSubrecord far *pSub08;
    ActorSubrecord far *pSub02;
    unsigned char x;
    unsigned char y;
    int extra;

    if (pHotspot->pEntity->pos.xy.nWorld_x / 64000L !=
            (unsigned long)g_apCombat_zone_actor_lists[0]->bParty_x ||
        pHotspot->pEntity->pos.xy.nWorld_y / 64000L !=
            (unsigned long)g_apCombat_zone_actor_lists[0]->bParty_y)
        return;

    audio_play(0x30);
    dialog_viewport_clip_point(pHotspot->rect.x + pHotspot->rect.width / 2,
                               pHotspot->rect.y + pHotspot->rect.height / 2);
    if (menupage_state_0e7c() != 1)
        goto cancel;

    actor_record =
        actorspawn_objfixed((unsigned int)g_gameState.nZoneId, pHotspot->pEntity->pos.xy.nWorld_x,
                            pHotspot->pEntity->pos.xy.nWorld_y);
    if (actor_record != 0 && actor_record->bResidence == RES_FIXED_OBJECT) {
        if ((pSub08 = actorrec_get_subrecord(actor_record, SUBREC_HOTSPOT)) == 0 ||
            !pSub08->hotspot_action.bHas_hotspot) {
            if ((pSub02 = actorrec_get_subrecord(actor_record, SUBREC_INTERACT_MSG)) == 0 ||
                pSub02->interact_msg.dwMessage_id == 0)
                goto play_9a;
        }
        goto dispatch;
    }

play_9a:
    dialog_play_record(0x9aUL, 1);
    goto destroy;

dispatch:
    if (pSub08 != 0 && pSub08->hotspot_action.bHas_hotspot != 0) {
        x = pSub08->hotspot_action.bHotspot_x;
        y = pSub08->hotspot_action.bHotspot_y;
        actorspawn_destroy_and_persist(actor_record);
#ifdef V102CD
        actor_record = 0;
#endif
        if (hotspotevt_dispatch_at_point(8, x, y, &extra) == 0)
            goto play_9a;
        goto destroy;
    }

play_msg:
    dialog_play_record(pSub02->interact_msg.dwMessage_id, 1);

destroy:
    if (actor_record != 0)
        actorspawn_destroy_and_persist(actor_record);
    return;

cancel:
    dialog_play_record(0x62UL, 1);
}

void far wcursor_click_door_or_secret(WorldHotspot *pHotspot) {
    Actor far *actor_record;
    ActorSubrecord far *pSub02;
    ActorSubrecord far *pSub08;
    long pos_x;
    long pos_y;
    unsigned char x;
    unsigned char y;
    int extra;
    int bShouldConsume;

    pos_x = pHotspot->pEntity->pos.xy.nWorld_x;
    pos_y = pHotspot->pEntity->pos.xy.nWorld_y;
    bShouldConsume = 1;
    actor_record = actorspawn_objfixed((unsigned int)g_gameState.nZoneId, pos_x, pos_y);
    if (actor_record == 0 || actor_record->bResidence != RES_FIXED_OBJECT ||
        (pSub02 = actorrec_get_subrecord(actor_record, SUBREC_INTERACT_MSG)) == 0 ||
        pSub02->interact_msg.dwMessage_id == 0) {
        dialog_play_record(0x9aUL, 1);
    } else if ((pSub02->interact_msg.bFlags & 2) != 0 || (pSub02->interact_msg.bFlags & 4) != 0 ||
               (pSub02->interact_msg.bFlags & 8) != 0) {
        pSub08 = actorrec_get_subrecord(actor_record, SUBREC_HOTSPOT);
        if (pSub08 == 0 || pSub08->hotspot_action.bHas_hotspot == 0 ||
            (pos_x / 64000L == (unsigned long)g_apCombat_zone_actor_lists[0]->bParty_x &&
             pos_y / 64000L == (unsigned long)g_apCombat_zone_actor_lists[0]->bParty_y)) {
            audio_play(0x30);
            dialog_viewport_clip_point(pHotspot->rect.x + pHotspot->rect.width / 2,
                                       pHotspot->rect.y + pHotspot->rect.height / 2);
            if (menupage_state_0e7c() == 1) {
                if (dialog_play_record(pSub02->interact_msg.dwMessage_id, 1) == 0) {
                    if (itemtbl_party_count_by_kind(0x53) != 0) {
                        if (pSub08 != 0 && pSub08->hotspot_action.bHas_hotspot != 0) {
                            x = pSub08->hotspot_action.bHotspot_x;
                            y = pSub08->hotspot_action.bHotspot_y;
                            actorspawn_destroy_and_persist(actor_record);
                            actor_record = 0;
                            if (hotspotevt_dispatch_at_point(7, x, y, &extra) != 0) {
                                if (extra != 0)
                                    bShouldConsume = 0;
                            } else {
                                dialog_play_record(0x9aUL, 1);
                                bShouldConsume = 0;
                            }
                            actor_record =
                                actorspawn_objfixed((unsigned int)g_gameState.nZoneId, pos_x, pos_y);
                            pSub02 = actorrec_get_subrecord(actor_record, SUBREC_INTERACT_MSG);
                        }
                        if (bShouldConsume) {
                            itemtbl_pty_consum_one_kind(0x53);
                            if ((pSub02->interact_msg.bFlags & 2) != 0) {
                                cmbinv_inventory_screen_run(actor_record, 0, 0);
                            } else if ((pSub02->interact_msg.bFlags & 4) != 0) {
                                dialog_play_record(0x44UL, 1);
                            } else {
                                dialog_play_record(0x43UL, 1);
                            }
                        }
                    } else {
                        dialog_play_record(0x42UL, 1);
                    }
                }
            } else {
                dialog_play_record(0xadUL, 1);
            }
        }
    } else {
        audio_play(0x30);
        dialog_viewport_clip_point(pHotspot->rect.x + pHotspot->rect.width / 2,
                                   pHotspot->rect.y + pHotspot->rect.height / 2);
        if (menupage_state_0e7c() == 1) {
            dialog_play_record(pSub02->interact_msg.dwMessage_id, 1);
        } else {
            dialog_play_record(0xadUL, 1);
        }
    }
    if (actor_record != 0)
        actorspawn_destroy_and_persist(actor_record);
    return;
}

void far wcursor_click_fixedobj_picklock(WorldHotspot *hotspot) {
    Actor far *actor_record;
    ActorSubrecord far *pSubrec1;
    ActorSubrecord far *pSubrec2;

    audio_play(0x30);
    dialog_viewport_clip_point(hotspot->rect.x + hotspot->rect.width / 2,
                               hotspot->rect.y + hotspot->rect.height / 2);
    if (menupage_state_0e7c() == 1) {
        actor_record =
            actorspawn_objfixed((unsigned int)g_gameState.nZoneId, hotspot->pEntity->pos.xy.nWorld_x,
                                hotspot->pEntity->pos.xy.nWorld_y);
        if (actor_record != 0 && actor_record->bResidence == RES_FIXED_OBJECT &&
            (pSubrec1 = actorrec_get_subrecord(actor_record, SUBREC_PARAMS)) != 0) {
            if (picklock_screen_run(pSubrec1->params.door_or_npc_key.bLookup_key, 3,
                                    (Actor far *)0) != 0) {
                pSubrec2 = actorrec_get_subrecord(actor_record, SUBREC_INTERACT_MSG);
                if (pSubrec2 != 0 && pSubrec2->interact_msg.dwMessage_id != 0)
                    dialog_play_record(pSubrec2->interact_msg.dwMessage_id, 1);
                else
                    dialog_play_record(0x9aUL, 1);
            }
        } else {
            dialog_play_record(0x9aUL, 1);
        }
        if (actor_record != 0)
            actorspawn_destroy_and_persist(actor_record);
    } else {
        dialog_play_record(0xaeUL, 1);
    }
}

void far wcursor_open_container_at_cursor(WorldHotspot *p_hotspot) {
    Actor far *actor;
    ActorSubrecord far *pSubrec;

    audio_play(0x30);
    dialog_viewport_clip_point(p_hotspot->rect.x + p_hotspot->rect.width / 2,
                               p_hotspot->rect.y + p_hotspot->rect.height / 2);
    if (menupage_state_0e7c() == 1) {
        actor = actorspawn_objfixed(g_gameState.nZoneId, p_hotspot->pEntity->pos.xy.nWorld_x,
                                    p_hotspot->pEntity->pos.xy.nWorld_y);
        if (actor == 0 ||
            (actor->bResidence != RES_FIXED_OBJECT && actor->bResidence != RES_SELF_SPAWN)) {
            dialog_play_record(0x9aUL, 1);
        } else {
            pSubrec = actorrec_get_subrecord(actor, SUBREC_INTERACT_MSG);
            if (pSubrec != 0 && pSubrec->interact_msg.dwMessage_id != 0)
                dialog_play_record(pSubrec->interact_msg.dwMessage_id, 1);
            else
                dialog_play_record(0xfUL, 1);
            actorspawn_npc_prox_periodic(actor);
            cmbinv_inventory_screen_run(actor, 0, 0);
        }
        if (actor != 0)
            actorspawn_destroy_and_persist(actor);
    } else {
        dialog_play_record(0x9bUL, 1);
    }
}

void far wcursor_click_locked_stub(WorldHotspot *hotspot) {
    audio_play(0x30);
    dialog_viewport_clip_point(hotspot->rect.x + hotspot->rect.width / 2,
                               hotspot->rect.y + hotspot->rect.height / 2);
    if (menupage_state_0e7c() == 1) {
        dialog_play_record(0xaf, 1);
        return;
    }
    dialog_play_record(0xb0, 1);
}

void far wcursor_interact_fixedobj_variant_a(WorldHotspot *p_hotspot) {
    Actor far *actor;
    ActorSubrecord far *pSubrec;

    audio_play(0x30);
    dialog_viewport_clip_point(p_hotspot->rect.x + p_hotspot->rect.width / 2,
                               p_hotspot->rect.y + p_hotspot->rect.height / 2);
    if (menupage_state_0e7c() != 1)
        goto cancel;

    actor = actorspawn_objfixed(g_gameState.nZoneId, p_hotspot->pEntity->pos.xy.nWorld_x,
                                p_hotspot->pEntity->pos.xy.nWorld_y);
    if (actor == 0 || actor->bResidence != RES_FIXED_OBJECT) {
        dialog_play_record(0x9aUL, 1);
    } else {
        pSubrec = actorrec_get_subrecord(actor, SUBREC_INTERACT_MSG);
        if (pSubrec != 0 && pSubrec->interact_msg.dwMessage_id != 0)
            dialog_play_record(pSubrec->interact_msg.dwMessage_id, 1);
        else
            dialog_play_record(0xb2UL, 1);
        cmbinv_inventory_screen_run(actor, 0, 0);
    }
    if (actor != 0)
        actorspawn_destroy_and_persist(actor);
    return;
cancel:
    dialog_play_record(0xb3UL, 1);
}

void far wcursor_click_dig_or_use_shovel(WorldHotspot *pHotspot) {
    Actor far *actor_record;
    ActorSubrecord far *pMsgSub;
    ActorSubrecord far *pEventSub;
    int sfx_started;

    audio_play(0x30);
    dialog_viewport_clip_point(pHotspot->rect.x + pHotspot->rect.width / 2,
                               pHotspot->rect.y + pHotspot->rect.height / 2);
    if (menupage_state_0e7c() != 1)
        goto cancel;

    actor_record =
        actorspawn_objfixed((unsigned int)g_gameState.nZoneId, pHotspot->pEntity->pos.xy.nWorld_x,
                            pHotspot->pEntity->pos.xy.nWorld_y);
    if (actor_record == 0 ||
        (actor_record->bResidence != RES_FIXED_OBJECT &&
         actor_record->bResidence != RES_SELF_SPAWN) ||
        (pMsgSub = actorrec_get_subrecord(actor_record, SUBREC_INTERACT_MSG)) == 0 ||
        pMsgSub->interact_msg.dwMessage_id == 0 ||
        (pEventSub = actorrec_get_subrecord(actor_record, SUBREC_HOTSPOT)) == 0 ||
        pEventSub->hotspot_action.wPad_0 == 0) {
        dialog_play_record(0x9a, 1);
    } else {
        dialog_play_record(pMsgSub->interact_msg.dwMessage_id, 1);
        if (gstate_event_read(pEventSub->hotspot_action.wPad_0) != 0) {
            int i;
            screen_cursor_show_busy();
            g_bShakeActorEnabled = 1;
            sfx_started = audio_sfx_play_n_times(0x2e, 0, 0);
            i = 0;
            do {
                world_render_scene_dispatch(0);
                screen_frame_present();
                i++;
            } while (i < 10);
            g_bShakeActorEnabled = 0;
            i = 0;
            do {
                world_render_scene_dispatch(0);
                screen_frame_present();
                i++;
            } while (i < 2);
            if (sfx_started != 0)
                audio_sfx_stop(0x2e);
            screen_cursor_restore_shape();
        }
    }
    if (actor_record != 0)
        actorspawn_destroy_and_persist(actor_record);
    return;
cancel:
    dialog_play_record(0xb4, 1);
}

void far wcursor_click_body(WorldHotspot *pHotspot) {
    Actor far *pActor;
    ActorSubrecord far *pSubrec;

    audio_play(0x30);
    dialog_viewport_clip_point(pHotspot->rect.x + pHotspot->rect.width / 2,
                               pHotspot->rect.y + pHotspot->rect.height / 2);
    if (menupage_state_0e7c() != 1)
        goto play_b6;
    pActor = actorspawn_objfixed((unsigned int)g_gameState.nZoneId, pHotspot->pEntity->pos.xy.nWorld_x,
                                 pHotspot->pEntity->pos.xy.nWorld_y);
    if (pActor == (Actor far *)0 || pActor->bResidence != RES_FIXED_OBJECT ||
        (pSubrec = actorrec_get_subrecord(pActor, SUBREC_INTERACT_MSG)) ==
            (ActorSubrecord far *)0 ||
        pSubrec->interact_msg.dwMessage_id == 0) {
        dialog_play_record(0xb5UL, 1);
    } else {
        dialog_play_record(pSubrec->interact_msg.dwMessage_id, 1);
    }
    if (pActor != (Actor far *)0)
        actorspawn_destroy_and_persist(pActor);
    return;
play_b6:
    dialog_play_record(0xb6UL, 1);
}

void far wcursor_interact_fixedobj_container(WorldHotspot *pHotspot) {
    Actor far *actor;
    ActorSubrecord far *pSubrec;

    audio_play(0x30);
    dialog_viewport_clip_point(pHotspot->rect.x + pHotspot->rect.width / 2,
                               pHotspot->rect.y + pHotspot->rect.height / 2);
    if (menupage_state_0e7c() != 1)
        goto cancel;

    actor = actorspawn_objfixed(g_gameState.nZoneId, pHotspot->pEntity->pos.xy.nWorld_x,
                                pHotspot->pEntity->pos.xy.nWorld_y);
    if (actor == 0 || actor->bResidence != RES_FIXED_OBJECT) {
        dialog_play_record(0x9aUL, 1);
    } else {
        pSubrec = actorrec_get_subrecord(actor, SUBREC_INTERACT_MSG);
        if (pSubrec != 0 && pSubrec->interact_msg.dwMessage_id != 0)
            dialog_play_record(pSubrec->interact_msg.dwMessage_id, 1);
        else
            dialog_play_record(0xb7UL, 1);
        cmbinv_inventory_screen_run(actor, 0, 0);
    }
    if (actor != 0)
        actorspawn_destroy_and_persist(actor);
    return;
cancel:
    dialog_play_record(0xb8UL, 1);
}

void far wcursor_fixedobj_examine_var_a(WorldHotspot *pHotspot) {
    Actor far *actor;
    ActorSubrecord far *pSubrec;

    audio_play(0x30);
    dialog_viewport_clip_point(pHotspot->rect.x + pHotspot->rect.width / 2,
                               pHotspot->rect.y + pHotspot->rect.height / 2);
    if (menupage_state_0e7c() != 1)
        goto not_zone;

    actor = actorspawn_objfixed((unsigned int)g_gameState.nZoneId, pHotspot->pEntity->pos.xy.nWorld_x,
                                pHotspot->pEntity->pos.xy.nWorld_y);
    if (actor == 0 || actor->bResidence != RES_FIXED_OBJECT ||
        (pSubrec = actorrec_get_subrecord(actor, SUBREC_INTERACT_MSG)) == 0 ||
        pSubrec->interact_msg.dwMessage_id == 0) {
        dialog_play_record(0x9aUL, 1);
    } else {
        dialog_play_record(pSubrec->interact_msg.dwMessage_id, 1);
    }
    if (actor != 0)
        actorspawn_destroy_and_persist(actor);
    return;
not_zone:
    dialog_play_record(0x61UL, 1);
}

void far wcursor_fixedobj_examine_var_b(WorldHotspot *pHotspot) {
    Actor far *actor;
    ActorSubrecord far *pSubrec;

    audio_play(0x30);
    dialog_viewport_clip_point(pHotspot->rect.x + pHotspot->rect.width / 2,
                               pHotspot->rect.y + pHotspot->rect.height / 2);
    if (menupage_state_0e7c() != 1)
        goto cancel;

    actor = actorspawn_objfixed(g_gameState.nZoneId, pHotspot->pEntity->pos.xy.nWorld_x,
                                pHotspot->pEntity->pos.xy.nWorld_y);
    if (actor == 0 || actor->bResidence != RES_FIXED_OBJECT ||
        (pSubrec = actorrec_get_subrecord(actor, SUBREC_INTERACT_MSG)) == 0 ||
        pSubrec->interact_msg.dwMessage_id == 0) {
        dialog_play_record(0x9aUL, 1);
    } else {
        dialog_play_record(pSubrec->interact_msg.dwMessage_id, 1);
    }
    if (actor != 0)
        actorspawn_destroy_and_persist(actor);
    return;
cancel:
    dialog_play_record(0xb9UL, 1);
}

void far wcursor_click_fixedobj_open(WorldHotspot *pHotspot) {
    Actor far *actor;
    ActorSubrecord far *pSubrec;

    audio_play(0x30);
    dialog_viewport_clip_point(pHotspot->rect.x + pHotspot->rect.width / 2,
                               pHotspot->rect.y + pHotspot->rect.height / 2);
    if (menupage_state_0e7c() != 1)
        goto cancel;

    actor = actorspawn_objfixed(g_gameState.nZoneId, pHotspot->pEntity->pos.xy.nWorld_x,
                                pHotspot->pEntity->pos.xy.nWorld_y);
    if (actor == 0 || actor->bResidence != RES_FIXED_OBJECT) {
        dialog_play_record(0x9aUL, 1);
    } else {
        pSubrec = actorrec_get_subrecord(actor, SUBREC_INTERACT_MSG);
        if (pSubrec != 0 && pSubrec->interact_msg.dwMessage_id != 0)
            dialog_play_record(pSubrec->interact_msg.dwMessage_id, 1);
        else
            dialog_play_record(0xbaUL, 1);
        cmbinv_inventory_screen_run(actor, 0, 0);
    }
    if (actor != 0)
        actorspawn_destroy_and_persist(actor);
    return;
cancel:
    dialog_play_record(0xbbUL, 1);
}

void far wcursor_loot_corpse(WorldHotspot *pHotspot, int nSlot) {
    Actor far *actor;
    ActorSubrecord far *pSubrec;
    long budget;
    long record_id;

    if (g_game_mode != 2)
        budget = 7000;
    else
        budget = 2500;
    if ((long)pHotspot->dwDist > budget)
        return;

    audio_play(0x30);
    dialog_viewport_clip_point(pHotspot->rect.x + pHotspot->rect.width / 2,
                               pHotspot->rect.y + pHotspot->rect.height / 2);
    g_gameState.nEvtArgAux1 =
        g_pEncounterRecordTemplates[nSlot / 7].pActors[nSlot % 7].nPaged_record_delta;
    if (menupage_state_0e7c() != 1)
        goto refuse;

    record_id = g_anEncounterRecordIds[nSlot / 7];
    actor = combatenc_corpse_tbl_spawn_actor(record_id, nSlot % 7);
    if (actor == 0 || actor->bResidence != RES_COMBAT) {
        dialog_play_record(0x9aUL, 1);
    } else {
        pSubrec = actorrec_get_subrecord(actor, SUBREC_INTERACT_MSG);
        if (pSubrec != 0 && pSubrec->interact_msg.dwMessage_id != 0)
            dialog_play_record(pSubrec->interact_msg.dwMessage_id, 1);
        else
            dialog_play_record(0x4eUL, 1);
        actorspawn_npc_prox_periodic(actor);
        cmbinv_inventory_screen_run(actor, 0, 0);
    }
    if (actor != 0)
        actorspawn_destroy_and_persist(actor);
    return;
refuse:
    dialog_play_record(0x5fUL, 1);
}

void far wcursor_encounter_hint(WorldHotspot *pHotspot, int nSlot) {
    long record_id;
    long last_time;

    audio_play(0x30);
    dialog_viewport_clip_point(pHotspot->rect.x + pHotspot->rect.width / 2,
                               pHotspot->rect.y + pHotspot->rect.height / 2);
    g_gameState.nEvtArgAux1 =
        g_pEncounterRecordTemplates[nSlot / 7].pActors[nSlot % 7].nPaged_record_delta;
    if (menupage_state_0e7c() == 1) {
        record_id = g_anEncounterRecordIds[nSlot / 7];
        if (record_id == 0x3f)
            goto lbl_dispatch;
        if (record_id == 0x40)
            goto lbl_dispatch;
        if (!hotspotevt_trap_gates_pass(nSlot / 7))
            return;
        gstate_temp_file_read_at((unsigned char far *)&last_time, GAM_ENC_VISITED_TIME(record_id), 4);
        if ((last_time == 0) || ((g_gameState.game_time - last_time) / 0xa8c0 >= 1)) {
            g_wLastTempWriteRecordKind = 1;
            gstate_temp_file_write_at((unsigned char far *)&g_gameState.game_time,
                                      GAM_ENC_VISITED_TIME(record_id), 4);
            dialog_play_record(0xfbUL, 1);
            return;
        }
        dialog_play_record(0xfcUL, 1);
        return;
    lbl_dispatch:
        if (record_id == 0x3f) {
            dialog_play_record(0x130UL, 1);
            return;
        }
        if (record_id != 0x40)
            return;
        hotspotevt_play_sound_zone_entry(nSlot / 7);
        return;
    } else {
        dialog_play_record(0xfaUL, 1);
    }
}

void far wcursor_fixedobj_examine_var_c(WorldHotspot *pHotspot) {
    Actor far *actor;
    ActorSubrec02_InteractMsg far *pSubrec;

    audio_play(0x30);
    dialog_viewport_clip_point(pHotspot->rect.x + pHotspot->rect.width / 2,
                               pHotspot->rect.y + pHotspot->rect.height / 2);
    if (menupage_state_0e7c() == 1) {
        actor = actorspawn_objfixed(g_gameState.nZoneId, pHotspot->pEntity->pos.xy.nWorld_x,
                                    pHotspot->pEntity->pos.xy.nWorld_y);
        if (!(actor != 0 && actor->bResidence == RES_FIXED_OBJECT &&
              (pSubrec = (ActorSubrec02_InteractMsg
                          far *)actorrec_get_subrecord(actor, SUBREC_INTERACT_MSG)) != 0 &&
              pSubrec->dwMessage_id != 0))
            dialog_play_record(0xbcUL, 1);
        else
            dialog_play_record(pSubrec->dwMessage_id, 1);
        if (actor != 0)
            actorspawn_destroy_and_persist(actor);
        return;
    }
    dialog_play_record(0xbdUL, 1);
}
