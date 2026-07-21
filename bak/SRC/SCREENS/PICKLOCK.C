#include "globals.h"
#include "structs.h"
#include "SRC/WORLD/ACTOR/ACTOR.H"
extern int picklock_screen_run(int score, int mode, Actor far *record);
extern void picklock_lock_slide_animation(int dir);
extern int picklock_screen_handle_drop(int item_kind, int slot);
extern void picklock_inv_info_query_disp(void);
#include "SRC/SYS/RAND.H"
#include "SRC/AUDIO/ENGINE/AUDIO.H"
#include "SRC/GFX/SPRITE/RESBLIT.H"
#include "SRC/GFX/SPRITE/RECTSPR.H"
#include "SRC/GFX/SCREEN/SCREEN.H"
#include "SRC/GAME/GSTATE.H"
#include "SRC/CHAR/STAT.H"
#include "SRC/DIALOG/DIALOG.H"
#include "SRC/SCREENS/CMBINV.H"
#include "SRC/SCREENS/ITEMTBL.H"


unsigned char g_bPicklockSuccess;
short g_nPicklockMode;
unsigned char far *g_pPicklockWorkingInv;
Actor far *g_pPicklockOwnerActor;
short g_nPicklockScore;
short g_nPicklockDiffTier;

unsigned char g_bInventoryShopMode = 0x00;
unsigned char g_abInvQuizAnswerTable[13] = {0x00, 0x32, 0x5a, 0x65, 0x66, 0x67, 0x68,
                                            0x46, 0x3c, 0x50, 0x69, 0x6a, 0x00};

void far picklock_lock_slide_animation(int dir) {
    int lockWidth;
    int shackleOffset;
    int slideOffset;

    lockWidth = g_pInvLockAssetTable[g_nPicklockDiffTier]->nWidth;
    if (dir != 0) {
        for (slideOffset = 0; slideOffset <= 0x18; slideOffset = slideOffset + 2) {
            shackleOffset = (slideOffset == 0x18) ? slideOffset - 2 : slideOffset;
            g_graphics_context.bGfx_fill_color = g_graphics_context.bGfx_outline_color = '\0';
            g_graphics_context.bGfx_fill_enabled = '\x01';
            draw_rect_filled(0xd, 0xb, 0x52, 0x79);
            resblit_sprite(*g_pInvLockAssetTable, 0x1d, 0x22 - shackleOffset);
            resblit_sprite(g_pInvLockAssetTable[g_nPicklockDiffTier], (0x52 - lockWidth) / 2 + 0xd,
                           0x3f);
            screen_frame_present();
        }
    } else {
        resblit_sprite(*g_pInvLockAssetTable, 0x1d, 0x22);
        resblit_sprite(g_pInvLockAssetTable[g_nPicklockDiffTier], (0x52 - lockWidth) / 2 + 0xd,
                       0x3f);
    }
    return;
}

typedef struct {
    unsigned char b[0x86];
} ActorWorkBuf;

int far picklock_screen_run(int score, int mode, Actor far *record) {
    short memberIdx;
    int pickCount;
    unsigned char items[0x70];
    Actor workActor;

    stat_party_find_extreme(0xd, 0, &memberIdx);
    g_gameState.nEvtArgCount = mode;
    g_gameState.nEvtArgActor0 = memberIdx;
    g_pPicklockWorkingInv = (unsigned char far *)&workActor;
    if (dialog_play_record(0x4f, 1) == 0) {
        g_nPicklockDiffTier = (score > 0x64) ? 4 : (score > 0x50) ? 3 : (score > 0x32) ? 2 : 1;
        workActor.bResidence = RES_PICKLOCK_BUFFER;
        *(ActorWorkBuf far *)&workActor = *(ActorWorkBuf far *)g_gameState.shared_inventory;
        if ((pickCount = itemtbl_party_count_by_kind(0x50)) > 0) {
            ItemSlot far *pickSlot = (ItemSlot far *)&((ItemSlot *)items)[workActor.itemCount++];
            pickSlot->item_id = 0x50;
            pickSlot->flags = 0;
            pickSlot->condition = pickCount;
        }
        if (workActor.itemCount == 0) {
            dialog_play_record(0x56, 0);
        } else {
            g_bInventoryShopMode = '\x01';
            g_bPicklockSuccess = 0;
            g_nPicklockScore = score;
            g_nPicklockMode = mode;
            g_pPicklockOwnerActor = record;
            cmbinv_inventory_screen_run(
                (Actor far *)&workActor,
                gstate_find_party_slot(&g_gameState.party_members[memberIdx]) + 1, 0);
            g_bInventoryShopMode = '\0';
            screen_render_main_frame(0);
            g_nSceneReloadPending = 0;
            return (uint)g_bPicklockSuccess;
        }
    } else {
        g_bInventoryShopMode = '\0';
    }
    return 0;
}

int far picklock_screen_handle_drop(int item_kind, int slot) {
    int skill;
    int threshold;

    skill = stat_actor_get(gstate_party_member_record(slot - 1), 0xd, 0);
    g_gameState.nEvtArgActor0 = slot = g_gameState.party_roster[slot - 1];
    g_gameState.nEvtArgCount = g_nPicklockMode;

    if (item_kind != 0) {

        audio_play(5);
        g_nFrameTickCountdown = 0xaf;
        while (g_nFrameTickCountdown) {
        }

        if (g_abInvQuizAnswerTable[item_kind] == g_nPicklockScore) {

            audio_play(0x29);
            picklock_lock_slide_animation(1);
            dialog_play_record(0x51, 1);
            g_bInventoryShopMode = 0;
            g_bPicklockSuccess = 1;

            gstate_event_write(LOCK_PICKED_WITH(item_kind), 1);
            return 1;
        }

        threshold = (100 - g_abInvQuizAnswerTable[item_kind] - skill / 3) * 2 / 3;
        if ((int)RND(100) <= threshold) {

            audio_play(0x2b);
            itemtbl_inv_consume_one_by_kind(g_pPicklockWorkingInv, item_kind + 0x3c);
            itemtbl_inv_consume_one_by_kind(g_gameState.shared_inventory, item_kind + 0x3c);
            dialog_play_record(0xf5, 1);
        } else {

            dialog_play_record(0x52, 1);
        }
    } else {

        audio_play(0x1e);
        g_nFrameTickCountdown = 0xaf;
        while (g_nFrameTickCountdown) {
        }

        if (g_nPicklockScore <= 100 && g_nPicklockScore < skill) {

            stat_combatant_modify(&g_gameState.party_members[g_gameState.nEvtArgActor0], 0xd, 2L,
                                  3);
            audio_play(0x16);
            picklock_lock_slide_animation(1);
            dialog_play_record(0x53, 1);
            g_bInventoryShopMode = 0;
            g_bPicklockSuccess = 1;
            return 1;
        }

        if (RND(100) <= 40) {

            stat_combatant_modify(&g_gameState.party_members[g_gameState.nEvtArgActor0], 0xd, 1L,
                                  3);
        }

        if ((int)RND(100) <= (g_nPicklockScore - skill) * 2 / 3) {

            audio_play(0x2b);
            itemtbl_inv_consume_one_by_kind(g_pPicklockWorkingInv, 0x50);
            itemtbl_pty_consum_one_kind(0x50);
            g_gameState.nEvtArgActor0 = slot;
            dialog_play_record(0x55, 1);
        } else {

            dialog_play_record(0x54, 1);
        }
    }
    return 0;
}

void far picklock_inv_info_query_disp(void) {
    int matchedKind;
    short i;

    for (i = 1, matchedKind = 0; i < 0xc; i++) {
        if (g_abInvQuizAnswerTable[i] == g_nPicklockScore) {
            matchedKind = i;
        }
    }
    if (gstate_event_read(LOCK_PICKED_WITH(matchedKind)) != 0) {
        g_gameState.nEvtArgItemId = matchedKind + 0x3c;
        g_gameState.nEvtArgCount = itemtbl_party_count_by_kind(g_gameState.nEvtArgItemId);
        dialog_play_record(0x1b776a, 0);
        return;
    }
    g_gameState.nEvtArgCount = (short)((int)stat_party_find_extreme(0xd, 0, &i) < g_nPicklockScore);
    if (100 < g_nPicklockScore) {
        g_gameState.nEvtArgCount = 2;
    }
    if (0x6a < g_nPicklockScore) {
        g_gameState.nEvtArgCount = 3;
    }
    dialog_play_record(0x1b776b, 0);
    return;
}
