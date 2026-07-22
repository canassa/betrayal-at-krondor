#include <stdlib.h>
#include <string.h>

#include "globals.h"
#include "structs.h"
#include "SRC/SCREENS/TOWNSCN.H"
#include "SRC/IO/IO.H"
#include "SRC/SYS/MEM.H"
#include "SRC/GFX/PALETTE/PALCYC.H"
#include "SRC/AUDIO/ENGINE/AUDIO.H"
#include "SRC/GFX/SPRITE/RESBLIT.H"
#include "SRC/GFX/DRIVER/PALDRV.H"
#include "SRC/GFX/RASTER/PRESENT.H"
#include "SRC/INPUT/KEYBOARD.H"
#include "SRC/GFX/SCREEN/SCREEN.H"
#include "SRC/UI/MENUPAGE.H"
#include "SRC/GFX/PALETTE/PALETTE.H"
#include "SRC/AUDIO/CHAN/AUDSETIN.H"
#include "SRC/GAME/GSTATE.H"
#include "SRC/CHAR/STAT.H"
#include "SRC/DIALOG/DIALOG.H"
#include "SRC/UI/MODALSCR.H"
#include "SRC/SCRIPT/ANIMSCR.H"
#include "SRC/SCRIPT/ADSCRIPT.H"
#include "SRC/SCREENS/CMBINV.H"
#include "SRC/SCREENS/INVENTOR.H"
#include "SRC/CHAR/CHARSCRN.H"
#include "SRC/WORLD/ACTOR/ACTSPAWN.H"
#include "SRC/WORLD/ACTOR/ACTORREC.H"
#include "SRC/WORLD/ZONE/ZONE.H"
#include "SRC/SCREENS/CIPHER.H"
#include "defines.h"


unsigned short g_dialog_anim_channel;

TownScene *g_pCurrentTownScene = {0};
MenuPage *g_pTownMenuPage = {0};
short g_nTownSceneAnimHandle = -1;
unsigned short g_dialog_in_scene = 0x0000;

static void far townscene_story_actors_destr(void) {
    int actor;

    if (g_pCurrentTownScene != (TownScene *)0x0) {
        if (g_pCurrentTownScene->pActor != (void far *)0) {
            actorspawn_destroy_and_persist(g_pCurrentTownScene->pActor);
        }
        if (g_pCurrentTownScene->pDdxRecord != (void far *)0) {
            dialog_freemem_if_not_null(g_pCurrentTownScene->pDdxRecord);
        }
        for (actor = 0; actor < g_pCurrentTownScene->nActorCount; actor++) {
            if (g_pCurrentTownScene->pAActors[actor].pDdxRecord) {
                dialog_freemem_if_not_null(g_pCurrentTownScene->pAActors[actor].pDdxRecord);
            }
        }
        if (0 < g_nTownSceneAnimHandle) {
            anim_script_close(g_nTownSceneAnimHandle);
            anim_script_close_all();
            adscript_renderer_reset();
            g_nTownSceneAnimHandle = -1;
        }
        galloc_zfree(g_pCurrentTownScene);
        g_pCurrentTownScene = (TownScene *)0x0;
    }
    return;
}

static int far townscene_load(int chapter, int sub, int preserve) {

    static char s_szGdsPrefix[4] = "GDS";
    static char g_szTownSceneFilenameSuffix[6] = "?.DAT";
    char fname[16];
    int i;
    unsigned int size;
    MenuEntry *pEntry;
    BakFile *stream;
    TownSceneActor *pActor;
    ActorSubrecord far *pSub;

    if ((chapter == 0x40) && (sub == 1) && (gstate_event_read(0x1c86) != 0)) {
        sub = 7;
    } else if ((chapter == 1) && (sub == 1) && (gstate_event_read(0x7539) != 0)) {
        sub = 4;
    }

    townscene_story_actors_destr();

    strcpy(fname, s_szGdsPrefix);
    itoa(chapter, fname + 3, 10);
    g_szTownSceneFilenameSuffix[0] = (char)sub + '@';
    strcat(fname, g_szTownSceneFilenameSuffix);

    stream = bak_fopen(fname, "rb");
    bak_fread(&size, 2, 1, stream);
    g_pCurrentTownScene = galloc_safe_zcalloc(size);
    bak_fread(g_pCurrentTownScene, size, 1, stream);
    bak_fclose(stream);

    g_nTownSceneAnimHandle = -1;
    if (g_pCurrentTownScene->pAnimPrefix[0] != '\0') {
        strcpy(fname, g_pCurrentTownScene->pAnimPrefix);
        strcat(fname, ".ADS");
        if (0 < (g_nTownSceneAnimHandle = anim_script_open(fname, 0))) {
            anim_script_activate(g_nTownSceneAnimHandle);
        }
    }

    pEntry = g_pTownMenuPage->pEntries;
    pActor = g_pCurrentTownScene->pAActors;
    g_pTownMenuPage->wEntry_count = 0;
    for (i = 0; i < g_pCurrentTownScene->nActorCount; i++) {
        g_pCurrentTownScene->pAActors[i].pDdxRecord =
            (preserve != 0) ? (void far *)dialog_load_record_by_key(
                                  g_pCurrentTownScene->pAActors[i].dwDialogKey, 0)
                            : (void far *)0;
        if ((preserve != 0) || ((pActor->wChapterMask & (1 << (g_gameState.nChapter - 1))) == 0)) {
            if ((pActor->nGateEventId == 0) ||
                (((unsigned int)pActor->nGateMin <= gstate_event_read(pActor->nGateEventId)) &&
                 (gstate_event_read(pActor->nGateEventId) <= (unsigned int)pActor->nGateMax))) {
                pEntry->rect.x = pActor->rect.x - g_pTownMenuPage->rect.x;
                pEntry->rect.y = pActor->rect.y - g_pTownMenuPage->rect.y;
                pEntry->rect.width = pActor->rect.width;
                pEntry->rect.height = pActor->rect.height;
                pEntry->wCursor_shape = pActor->nCursorShape - 1;
                pEntry->wAction_id = i + 0x80;
                g_pTownMenuPage->wEntry_count++;
                pEntry++;
            }
        }
        pActor->cClickCount = '\0';
        pActor = pActor + 1;
    }

    g_pCurrentTownScene->pDdxRecord =
        (void far *)dialog_load_record_by_key(g_pCurrentTownScene->dwDialogKey, 0);
    g_pCurrentTownScene->pActor = (void far *)actorspawn_objfixed(0xf, chapter, sub);
    if (g_pCurrentTownScene->pActor != (void far *)0) {
        pSub = actorrec_get_subrecord(g_pCurrentTownScene->pActor, SUBREC_EVENT_STATE);
        if ((pSub != (ActorSubrecord far *)0) &&
            (pSub->event_state.bRest_last_chapter_done < g_gameState.nChapter)) {
            ((Actor far *)g_pCurrentTownScene->pActor)->needsFlush = TRUE;
            {
                int q;
                q = (int)((long)((unsigned long)pSub->event_state.bRest_gold_unit *
                                 ((unsigned long)g_gameState.nChapter + 9)) /
                          10);
                pSub->event_state.bPopup_retry_counter = (q > 0xfa) ? 0xfa : (unsigned char)q;
            }
            pSub->event_state.bRest_last_chapter_done = (unsigned char)g_gameState.nChapter;
        }
    }

    if (preserve == 0) {
        g_pCurrentTownScene->nMusicIntensity =
            (g_pCurrentTownScene->nMusicIntensity < 0x19) ? 0x4b : 0x3c;
    }
    return 1;
}

void townscene_anim_channel_play_sync(int channel_id) {
    if ((0 < g_nTownSceneAnimHandle) && (0 < channel_id)) {
        g_graphics_context.wGfxBlitSrcPage = g_graphics_context.wVgaPage1Base;
        g_graphics_context.wGfxBlitDstPage = g_graphics_context.wVgaPage2Base;
        gfx_present_dispatch(0, 0, 0x140, 200);
        anim_script_channel_start(channel_id);
        do {
        } while (anim_script_tick() != 0);
        anim_script_channel_stop(channel_id);
        g_dialog_anim_channel = channel_id;
    }
    return;
}

static void far townscene_shop_menu_open(void) {
    g_pTownMenuPage = menupage_load("req_gds.dat");
    menupage_begin(g_pTownMenuPage);
    return;
}

static void far townscene_shop_menu_close(void) {
    menupage_end(g_pTownMenuPage);
    menupage_free(g_pTownMenuPage);
    return;
}

static void far townscene_dlg_play_rec_bubble(DDXRecord far *record) {
    unsigned char far *p;
    unsigned char far *start_text;

    if (record != (DDXRecord far *)0) {
        p = (unsigned char far *)record + (unsigned int)record->bCnt1 * 10 +
            (unsigned int)record->bCnt2 * 10 + 9;
        townscene_anim_channel_play_sync(g_dialog_anim_channel);
        if (*p == '#') {
            p++;
            start_text = p;
            while (*p != '\0' && *p != '#')
                p++;
            *p = '\0';
            p++;
            dialog_draw_speech_bubble(start_text, 0);
        }
        dialog_combatant_name_table_init();
        dialog_render_text_with_tokens(record, p, -1, 0, 0, 0);
    }
    return;
}

static void far townscene_cursor_wait_for_drag(void) {
    short saved_x;
    short saved_y;
    short cur_x;
    short cur_y;
    int abs_sum;

    saved_x = screen_cursor_get_x();
    saved_y = screen_cursor_get_y();
    screen_frame_present();
    screen_frame_sync_buffers_rect(0, 200);
    dialog_input_wait_release(1, 0);
    do {
        screen_frame_present();
        if (dialog_poll_arrow_or_button() != 0)
            break;
        screen_cursor_get_position(&cur_x, &cur_y);
        cur_x -= saved_x;
        cur_y -= saved_y;
        abs_sum = (cur_x < 0 ? (cur_x == (short)-0x8000 ? 0x7fff : -cur_x) : cur_x) +
                  (cur_y < 0 ? (cur_y == (short)-0x8000 ? 0x7fff : -cur_y) : cur_y);
    } while (abs_sum <= 0xa);
    dialog_input_wait_release(1, 0);
    return;
}

static int far townscene_resolv_enc_outcome(Actor far *actor) {
    ActorSubrecord far *pSub;
    unsigned int statValue;
    unsigned int gold;
    int musicTrack;
    int outcome;
    int dlgRecord;
    int savedMusic;

    gold = 0;
    outcome = 1;
    pSub = actorrec_get_subrecord(actor, SUBREC_EVENT_STATE);
    screen_cursor_set_shape(0);
    if (pSub->event_state.bPopup_retry_counter != 0) {
        statValue = stat_party_find_extreme(0xb, 0, (short *)0x0);
        g_gameState.nEvtArgActor0 = g_gameState.nEvtArgStat;

        if ((int)statValue < 0x2d) {
            musicTrack = 0x3f0;
        } else if ((int)statValue < 0x41) {
            musicTrack = 0x410;
        } else if ((int)statValue < 0x55) {
            musicTrack = 0x40f;
        } else {
            musicTrack = 0x3ef;
        }
        if (pSub->event_state.b_pad06 < (int)statValue) {
            stat_party_broadcast_status_op(0xb, 2, 3);
            if ((int)statValue >= (int)((pSub->event_state.b_pad06 + 100) / 2)) {
                dlgRecord = 0x5a;
                gold = pSub->event_state.bPopup_retry_counter * 10;
            } else {
                dlgRecord = 0x59;
                gold = (pSub->event_state.bPopup_retry_counter * 10) / 2;
            }
        } else {
            stat_party_broadcast_status_op(0xb, 1, 3);
            if ((int)statValue < (int)((pSub->event_state.b_pad06 * 3) / 4)) {
                dlgRecord = 0x49;
                outcome = 0;
            } else {
                dlgRecord = 0x58;
                gold = (pSub->event_state.bPopup_retry_counter * 10) / 4;
            }
        }
        if (gold != 0) {
            pSub->event_state.bPopup_retry_counter = 0;
            actor->needsFlush = TRUE;
            g_gameState.nParty_gold += (long)(int)gold;
            g_gameState.lEvtArgGoldCost = (long)(int)gold;
        }
        savedMusic = audio_music_play(musicTrack);
        dialog_play_record((long)dlgRecord, 0);
        audio_music_play(savedMusic);
        if (0 < savedMusic) {
            audio_set_intensity(savedMusic, g_pCurrentTownScene->nMusicIntensity);
        }
    } else {
        dialog_play_record(0x47, 0);
    }
    return outcome;
}

void far townscene_main_loop(unsigned int scene_kind, int scene_index) {
    int idx;
    int action;
    int fadeFlag;
    int dialogLoaded;
    int exitFlag;
    int sceneIdx;
    int savedMusic;
    int musicTrack;
    unsigned short savedBlendMode;
    unsigned char far *pPalSaved;
    int needRefresh;
    TownSceneActor *pA;
    int di;

    fadeFlag = 1;
    dialogLoaded = 0;
    exitFlag = 0;
    sceneIdx = scene_index;
    savedMusic = audio_music_play(-999);
    musicTrack = -1;
    savedBlendMode = g_nPalBlendMode;
    pPalSaved = palette_set((unsigned char far *)0);

    if ((scene_kind & 0xff00) != 0) {
        sceneIdx = (int)scene_kind >> 8;
        scene_kind &= 0xff;
    }
    zone_teardown(0);
    g_dialog_in_scene = 1;
    g_dialog_anim_channel = 0;
    g_nPalBlendMode = 0;
    g_nChapterSnapshotDeadStore = g_gameState.nChapter;
    *((unsigned short *)&g_anim_slots[1] + 1) = g_gameState.nChapter;
    screen_cursor_state_push_pop(1);
    screen_cursor_load_pack(1);
    palette_cycle_eb_toggle(0);
    townscene_shop_menu_open();

    while (exitFlag == 0) {
        action = 0;
        if (sceneIdx > 0) {
            screen_cursor_hide();
            screen_cursor_show_busy();
            townscene_load((int)scene_kind, sceneIdx, 0);
            palette_cycle_eb_toggle(0);
            townscene_anim_channel_play_sync(g_pCurrentTownScene->nEntryAnim);
            dialog_input_wait_with_cooldown(2);
            if (dialogLoaded == 0) {
                dialogLoaded = 1;
                g_graphics_context.wGfxBlitDstPage = g_graphics_context.wVgaPage1Base;
                resblit_load_pal_or_stream("Dialog.scr");
                g_graphics_context.wGfxBlitDstPage = g_graphics_context.wVgaPage2Base;
            }
            if ((g_pCurrentTownScene->wFlags & 0x80) != 0) {

                gstate_event_write(TOWN_VISITED(g_pCurrentTownScene->wFlags & 0x7f), 1);
            }
            if (g_pCurrentTownScene->nMusicTrack > 0) {
                musicTrack = g_pCurrentTownScene->nMusicTrack;
                audio_music_play(musicTrack);
            }
            if (musicTrack > 0) {
                audio_set_intensity(musicTrack, g_pCurrentTownScene->nMusicIntensity);
            }
            screen_cursor_restore_shape();
            if (fadeFlag) {
                palette_fade_out(0, 0x100, 4, 0);
                palette_screen_clear_black();
                screen_cursor_hide();
            }
            g_dialog_anim_channel = 0;
            townscene_anim_channel_play_sync(g_pCurrentTownScene->nIdleAnim);
            sceneIdx = 0;
            for (idx = 0; idx < g_pCurrentTownScene->nActorCount; idx++) {
                pA = &g_pCurrentTownScene->pAActors[idx];
                if ((pA->wChapterMask & 0x8000) != 0 &&
                    (pA->wChapterMask & (1 << (g_gameState.nChapter - 1))) == 0) {
                    action = idx + 0x80;
                }
            }
            if (action == 0) {
                townscene_dlg_play_rec_bubble(g_pCurrentTownScene->pDdxRecord);
            }
            if (g_pPendingPalette != 0) {
                g_pPalQueuedForFlip = g_pPendingPalette;
                g_pPendingPalette = 0;
            }
            if (fadeFlag) {
                fadeFlag = 0;
                if (g_pPalQueuedForFlip != 0) {
                    palette_set(g_pPalQueuedForFlip);
                }
                g_pPalQueuedForFlip = 0;
                palette_set_scaled(0, 0x100, 0, 0);
                screen_frame_present();
                screen_frame_sync_buffers_rect(0, 200);
                palette_fade_in(0, 0x100, 4, 1);
            } else {
                screen_frame_present();
                screen_frame_sync_buffers_rect(0, 200);
            }
        }

        /* Menu-run loop: block on the menu until the user picks an action. */
        while (action == 0) {
            action = menupage_run(g_pTownMenuPage, (unsigned short *)&idx);
            if (screen_input_poll_confirm_cancel() == 2) {
                screen_cursor_set_shape(3);
            }
            screen_frame_present();
        }

        /* action < 0x80 skips the actor dispatch below. */
        if (action >= 0x80) {

            needRefresh = 0;
            pA = &g_pCurrentTownScene->pAActors[action - 0x80];
            if (menupage_state_0e7c() == 2) {

                ActorSubrecord far *pSub;
                if (pA->dwDialogKey != 0) {
                    if (g_pCurrentTownScene->pActor != 0) {
                        pSub = actorrec_get_subrecord((Actor far *)g_pCurrentTownScene->pActor,
                                                      SUBREC_EVENT_STATE);
                        if (pSub != 0) {
                            g_gameState.lEvtArgAuxValue =
                                (long)(int)(unsigned int)pSub->event_state.bInvreq_arg_x;
                        }
                    }
                    if (pA->pDdxRecord == 0) {
                        pA->pDdxRecord = (void far *)dialog_load_record_by_key(pA->dwDialogKey, 0);
                    }
                    if (pA->pDdxRecord != 0) {
                        if (((DDXRecord far *)pA->pDdxRecord)->bStyle - 1 == 5 ||
                            ((DDXRecord far *)pA->pDdxRecord)->bCnt1 != 0) {
                            dialog_play_record(pA->dwDialogKey, 0);
                        } else {
                            townscene_dlg_play_rec_bubble((DDXRecord far *)pA->pDdxRecord);
                            townscene_cursor_wait_for_drag();
                            g_pPendingPalette = 0;
                        }
                        needRefresh = 1;
                    }
                }
            } else {

                di = (int)pA->cKind;
                g_gameState.lEvtArgGoldCost = 0;
                if (pA->dwAltDialogKey != 0 && di != 0xd) {
                    int teleport0 = (int)g_gameState.abTeleportRecord[0];
                    ActorSubrecord far *pSub;
                    townscene_anim_channel_play_sync(pA->nAnimChannel != 0 ? pA->nAnimChannel
                                                                           : g_dialog_anim_channel);
                    g_pPendingPalette = 0;
                    screen_cursor_set_shape(0);
                    g_gameState.nEvtArgCount = (short)pA->cClickCount;
                    g_gameState.dwPopup_retry_state = 0;
                    if (g_pCurrentTownScene->pActor != 0) {
                        pSub = actorrec_get_subrecord((Actor far *)g_pCurrentTownScene->pActor,
                                                      SUBREC_EVENT_STATE);
                        if (pSub != 0) {
                            g_gameState.dwPopup_retry_state =
                                pSub->event_state.bPopup_retry_counter;
                            g_gameState.lEvtArgAuxValue =
                                (long)(int)(unsigned int)pSub->event_state.bInvreq_arg_x;
                        }
                    }
                    switch (dialog_play_record(pA->dwAltDialogKey, 0)) {
                    case -1:
                        di = 0;
                        break;
                    case -2:
                        di = 5;
                        g_pPalQueuedForFlip = 0;
                        break;
                    case -3:
                        di = 7;
                        break;
                    case -4:
                        di = 3;
                        break;
                    case -5:
                        di = 0xa;
                        break;
                    }
                    if (musicTrack > 0) {
                        audio_set_intensity(musicTrack, g_pCurrentTownScene->nMusicIntensity);
                    }
                    if (g_pCurrentTownScene->pActor != 0) {
                        pSub = actorrec_get_subrecord((Actor far *)g_pCurrentTownScene->pActor,
                                                      SUBREC_EVENT_STATE);
                        if (pSub != 0) {
                            pSub->event_state.bPopup_retry_counter =
                                (g_gameState.dwPopup_retry_state > 0xfa)
                                    ? 0xfa
                                    : (unsigned char)g_gameState.dwPopup_retry_state;
                        }
                    }
                    g_gameState.dwPopup_retry_state = 0;
                    if ((int)g_gameState.abTeleportRecord[0] != teleport0 &&
                        g_gameState.abTeleportRecord[0] != 0xff) {
                        exitFlag = 1;
                    } else {
                        needRefresh = 1;
                    }
                }
                {
                    ActorSubrecord far *pSub;
                    if (di == 6) {
                        cmbinv_inventory_screen_run((Actor far *)g_pCurrentTownScene->pActor, 0, 0);
                        g_graphics_context.wGfxBlitDstPage = g_graphics_context.wVgaPage1Base;
                        resblit_load_pal_or_stream("Dialog.scx");
                        g_graphics_context.wGfxBlitDstPage = g_graphics_context.wVgaPage2Base;
                        needRefresh = fadeFlag = 1;
                    }
                    if (di == 8) {
                        cmbinv_inventory_screen_run((Actor far *)g_pCurrentTownScene->pActor, 0, 0);
                        g_graphics_context.wGfxBlitDstPage = g_graphics_context.wVgaPage1Base;
                        resblit_load_pal_or_stream("Dialog.scx");
                        g_graphics_context.wGfxBlitDstPage = g_graphics_context.wVgaPage2Base;
                        needRefresh = fadeFlag = 1;
                    }
                    if (di == 9) {
                        townscene_anim_channel_play_sync(pA->nAnimChannel);
                        g_pPendingPalette = 0;
                        if (townscene_resolv_enc_outcome(
                                (Actor far *)g_pCurrentTownScene->pActor) == 0) {
                            di = 3;
                        } else {
                            needRefresh = 1;
                        }
                    }
                    if (di == 5) {
                        cmbinv_inventory_screen_run((Actor far *)g_pCurrentTownScene->pActor, 0, 0);
                        g_graphics_context.wGfxBlitDstPage = g_graphics_context.wVgaPage1Base;
                        resblit_load_pal_or_stream("Dialog.scx");
                        g_graphics_context.wGfxBlitDstPage = g_graphics_context.wVgaPage2Base;
                        needRefresh = fadeFlag = 1;
                    }
                    if (di == 7) {
                        pSub = actorrec_get_subrecord((Actor far *)g_pCurrentTownScene->pActor,
                                                      SUBREC_EVENT_STATE);
                        if (scene_kind == 0x3e && scene_index == 5) {
                            pSub->event_state.bRest_gold_cost =
                                gstate_event_read(0xdb1c) != 0 ? 0xa : 0x48;
                        }
                        modalscreen_rest_until_time((Actor far *)g_pCurrentTownScene->pActor);
                        needRefresh = fadeFlag = 1;
                    }
                    if (di == 0xa) {
                    }
                    if (di == 0x10) {
                        pSub = actorrec_get_subrecord((Actor far *)g_pCurrentTownScene->pActor,
                                                      SUBREC_EVENT_STATE);
                        modalscreen_inventory_request((unsigned int)pSub->event_state.bInvreq_arg_x,
                                                      (int)(unsigned int)pSub->event_state.bInvreq_arg_y);
                        needRefresh = 1;
                    }
                    if (di == 0xf) {
                        g_gameState.nWorldLoopExitRequest = 1;
                        exitFlag = 1;
                    }
                    if (di == 0xb) {
                        pSub = actorrec_get_subrecord((Actor far *)g_pCurrentTownScene->pActor,
                                                      SUBREC_EVENT_STATE);
                        modalscreen_teleport_spell_run(
                            (int)pSub->event_state.bArg0,
                            (long)pSub->event_state.wShop_disposition_flags,
                            (int)pSub->event_state.bTeleport_cost_msb);
                        if (*(unsigned short *)&g_gameState.abTeleportRecord[7] != 0) {
                            scene_kind = *(unsigned short *)&g_gameState.abTeleportRecord[7];
                            sceneIdx = *(unsigned short *)&g_gameState.abTeleportRecord[9];
                            *(unsigned short *)&g_gameState.abTeleportRecord[7] =
                                *(unsigned short *)&g_gameState.abTeleportRecord[9] = 0;
                        } else {
                            needRefresh = 1;
                        }
                    }
                    if (di == 0xd) {
                        int dx;
                        pSub = actorrec_get_subrecord((Actor far *)g_pCurrentTownScene->pActor,
                                                      SUBREC_EVENT_STATE);
                        needRefresh = 1;
                        g_dialog_anim_channel = pA->nAnimChannel;
                        screen_cursor_set_shape(0);
                        g_gameState.nEvtArgCount = pSub->event_state.bArg0;
                        while ((dx = dialog_play_record(pA->dwAltDialogKey, 0)) != 3) {
                            if (dx == 1) {
                                charscreen_temple_heal_menu((int)pSub->event_state.bTemple_filter,
                                                            (int)pSub->event_state.bArg0);
                            } else if (dx == 2) {
                                modalscreen_req_inv_run(
                                    (int)pSub->event_state.bArg0, (int)pSub->event_state.bArg1,
                                    (int)pSub->event_state.bArg2, (int)pSub->event_state.bArg3);
                            }
                        }
                    }
                    if (di == 3 || di == 4) {
                        needRefresh = 0;
                        townscene_anim_channel_play_sync(g_pCurrentTownScene->nExitAnim);
                        g_pPendingPalette = g_pPalQueuedForFlip = 0;
                        if (di == 3)
                            sceneIdx = g_pCurrentTownScene->nExitScene;
                        else
                            sceneIdx = pA->nNextScene;
                        if (sceneIdx <= 0)
                            exitFlag = 1;
                    }
                    pA->cClickCount = pA->cClickCount + (pA->cClickCount < 0x64);
                }
            }

            /* Post-dispatch frame present. */
            if (needRefresh != 0) {
                if (fadeFlag) {
                    palette_fade_out(0, 0x100, 8, 0);
                    palette_screen_clear_black();
                    screen_cursor_hide();
                }
                townscene_anim_channel_play_sync(g_pCurrentTownScene->nIdleAnim);
                townscene_dlg_play_rec_bubble(g_pCurrentTownScene->pDdxRecord);
                if (g_pPendingPalette != 0) {
                    g_pPalQueuedForFlip = g_pPendingPalette;
                    g_pPendingPalette = 0;
                }
                if (fadeFlag) {
                    fadeFlag = 0;
                    if (g_pPalQueuedForFlip != 0) {
                        palette_set(g_pPalQueuedForFlip);
                    }
                    g_pPalQueuedForFlip = 0;
                    palette_set_scaled(0, 0x100, 0, 0);
                    screen_frame_present();
                    screen_frame_sync_buffers_rect(0, 200);
                    palette_fade_in(0, 0x100, 4, 1);
                } else {
                    screen_frame_present();
                    screen_frame_sync_buffers_rect(0, 200);
                }
            }
        } /* end if (action >= 0x80) */

        /* The action < 0x80 skip lands here: handle the "leave scene" action. */
        if (action == 1) {
            townscene_anim_channel_play_sync(g_pCurrentTownScene->nExitAnim);
            g_pPendingPalette = 0;
            sceneIdx = g_pCurrentTownScene->nExitScene;
            if (sceneIdx <= 0)
                exitFlag = 1;
        }
    }

    /* Loop exit: tear down the scene and restore the prior game state. */
    g_pPalQueuedForFlip = 0;
    townscene_story_actors_destr();
    townscene_shop_menu_close();
    screen_scene_reset_clip_cur();
    screen_cursor_unload_pack();
    screen_cursor_state_push_pop(0);
    screen_cursor_show_busy();
    audio_music_play(savedMusic);
    zone_refresh_visible(0);
    screen_cursor_restore_shape();
    g_nPalBlendMode = savedBlendMode;
    if (pPalSaved[0] == 0 && pPalSaved[1] == 0 && pPalSaved[2] == 0) {
        g_pPalQueuedForFlip = pPalSaved;
    }
    palette_cycle_eb_toggle(1);
    g_dialog_in_scene = 0;
    g_nSceneReloadPending = 1;
    g_nExploreReloadPending = 1;
}

void far townscene_cheat_menu_screen(void) {
    unsigned int sel;
    unsigned short redraw;
    Actor far *actor;
    unsigned short saved_chapter;
    int i;
    MenuPage *page;

    redraw = 1;
    page = menupage_load("req_knoc.dat");
    menupage_begin(page);
    menupage_draw(page);
    screen_render_main_frame("DIALOG.SCX");
    do {
        if (redraw != 0) {
            invui_draw_text_aligned_shadow((unsigned char far *)"-> CHEAT CENTRAL <-", 0xa0, 0x14, 1, 10,
                                           1);
            invui_draw_text_aligned_shadow((unsigned char far *)"Enjoy with caution...", 0xa0, 0x23, 1, 10,
                                           1);
            menupage_draw(page);
            screen_frame_present();
            screen_frame_sync_buffers_rect(0, 200);
        }
        screen_frame_present();
        sel = menupage_run(page, &redraw);
        switch (sel) {
        case 0x81:
            g_gameState.nParty_gold += 5000;
            break;
        case 0x82:
            actor = actorspawn_objfixed(0, 50L, 0L);
            saved_chapter = g_gameState.nChapter;
            g_gameState.nChapter = 9;
            cmbinv_inventory_screen_run(actor, 0, 0);
            actorspawn_destroy_and_persist(actor);
            screen_render_main_frame("DIALOG.SCX");
            g_gameState.nChapter = saved_chapter;
            break;
        case 0x83:
            dialog_play_record(0x249f1bL, 0);
            screen_render_main_frame("DIALOG.SCX");
            break;
        case 0x84:
            g_gameState.nWorldLoopExitRequest = 1;
            sel = 1;
            break;
        case 0x85:
            stat_party_heal_all(100);
            break;
        case 0x86:
            for (i = 0; g_gameState.party_count > i; i++) {
                gstate_party_member_record(i)->pSpellsKnown[0] = 0xffff;
                gstate_party_member_record(i)->pSpellsKnown[1] = 0xffff;
                gstate_party_member_record(i)->pSpellsKnown[2] = 0xffff;
            }
            break;
        case 0x87:
            for (i = 0; i < 15; i++) {
                gstate_event_write(TOWN_VISITED(i), 1);
            }
        }
    } while (sel != 1);
    menupage_end(page);
    menupage_free(page);
    g_nSceneReloadPending = 1;
    g_nExploreReloadPending = 1;
}

void far townscene_chest_open_with_cipher(void) {
    unsigned short redraw;
    Actor far *actor;
    ActorSubrec01_Cipher far *pSub;
    MenuPage *page;
    unsigned int sel;

    redraw = 1;
    actor = actorspawn_objfixed(0, 0x3cL, (long)g_gameState.nChapter);
    pSub = (ActorSubrec01_Cipher far *)actorrec_get_subrecord(actor, SUBREC_PARAMS);
    if (actor != (Actor far *)0 && pSub != (ActorSubrec01_Cipher far *)0 &&
        pSub->bCipher_puzzle_id != 0) {
        dialog_input_wait_release(0, 0);
        dialog_play_record(0x249f1cL, 0);
        if (cipher_dial_puzzle_run((unsigned int)pSub->bCipher_puzzle_id) != 0) {
            /* Cipher solved: run the chest menu. The failure path is the
             * else arm below. */
            dialog_play_record(0x249f1dL, 0);
            page = menupage_load("req_chet.dat");
            menupage_begin(page);
            menupage_draw(page);
            screen_render_main_frame("DIALOG.SCX");
            do {
                if (redraw != 0) {
                    invui_draw_text_aligned_shadow((unsigned char far *)"-> CHEAT CENTRAL <-", 0xa0, 0x14,
                                                   1, 10, 1);
                    invui_draw_text_aligned_shadow((unsigned char far *)"Enjoy with caution...", 0xa0, 0x23,
                                                   1, 10, 1);
                    menupage_draw(page);
                    screen_frame_present();
                    screen_frame_sync_buffers_rect(0, 200);
                }
                screen_frame_present();
                sel = menupage_run(page, &redraw);
                switch (sel) {
                case 0x81:
                    stat_party_heal_all(100);
                    break;
                case 0x82:
                    cmbinv_inventory_screen_run(actor, 0, 0);
                    screen_render_main_frame("DIALOG.SCX");
                    break;
                case 0x31:
                    if (key_is_down(0x2a) != 0)
                        break;
                    if (key_is_down(0x36) == 0)
                        break;
                    if (key_is_down(0x1d) != 0)
                        break;
                    if (key_is_down(0x38) == 0)
                        break;
                    if (dialog_play_record(0x249f1fL, 0) == 0) {
                        g_gameState.nWorldLoopExitRequest = 1;
                        sel = 1;
                    } else {
                        screen_render_main_frame("DIALOG.SCX");
                    }
                    redraw = 1;
                    break;
                }
            } while (sel != 1);
            menupage_end(page);
            menupage_free(page);
        } else {
            dialog_play_record(0x249f1eL, 0);
        }
        actorspawn_destroy_and_persist(actor);
        g_nSceneReloadPending = 1;
        g_nExploreReloadPending = 1;
    }
    return;
}
