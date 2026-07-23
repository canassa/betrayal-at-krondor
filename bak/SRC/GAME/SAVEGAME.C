#include <stdio.h>
#include <io.h>
#include "globals.h"
#include "SRC/R3D/SCENE/WORLDHIT.H"
#include "SRC/SCREENS/MAINMENU.H"
#include "SRC/INPUT/TIMER.H"
#include "structs.h"
#include "SRC/GAME/SAVEGAME.H"
#include "SRC/IO/IO.H"
#include "SRC/GFX/PALETTE/PALETTE.H"
#include "SRC/GAME/GSTATE.H"
#include "SRC/CHAR/STAT.H"
#include "SRC/GAME/TIMERPL.H"
#include "SRC/DIALOG/DIALOG.H"
#include "SRC/SCREENS/ITEMUSE.H"
#include "SRC/WORLD/ACTOR/ACTSPAWN.H"
#include "SRC/WORLD/ZONE/ZONE.H"
#include "SRC/WORLD/ENC/HOTSPOT.H"
#include "SRC/GAME/CFGPARSE.H"

int far savegame_write(char *filename) {
    int dest_fd;
    int ok;
    int chunk;
    int src_fd;
    long remaining;
    unsigned short version;
    char temp_path[50];

    ok = 1;
    remaining = 0x51aa9;
    version = 0x16;
    gstate_temp_file_close();
    if (g_cfgTempDrive != 0) {
        sprintf(temp_path, "%c:%s", g_cfgTempDrive, "TEMP.GAM");
    } else {
        sprintf(temp_path, "%s", "TEMP.GAM");
    }
    g_nFrameTickCountdown = 30000;
    if ((src_fd = open(temp_path, -0x7fff)) >= 0) {
        if ((dest_fd = open(filename, -0x7cfe, 0x180)) >= 0) {
            if (!(write(dest_fd, g_abSaveFileHeader, 0x5a) == 0x5a &&
                  write(dest_fd, &g_gameState, 2) == 2 &&
                  write(dest_fd, &g_wBookmarkFmapX, 2) == 2 &&
                  write(dest_fd, &g_wBookmarkFmapY, 2) == 2 &&
                  write(dest_fd, &g_wBookmarkCompassIcon, 2) == 2 &&
                  write(dest_fd, &version, 2) == 2))
                ok = 0;

            while (ok != 0 && remaining != 0) {
                chunk = (remaining > 0x3a98) ? 15000 : (int)remaining;
                remaining -= chunk;
                if (dos_read(g_pMainScratchBuf, (long)chunk, src_fd) != (long)chunk) {
                    ok = 0;
                } else if (dos_write(g_pMainScratchBuf, (long)chunk, dest_fd) != (long)chunk) {
                    ok = 0;
                }
            }
            if (close(dest_fd) != 0)
                ok = 0;
            if (ok == 0)
                remove(filename);
            goto close_src;
        }
        ok = 0;
    close_src:
        if (close(src_fd) == 0)
            goto done;
    }
    ok = 0;
done:
    gstate_temp_file_open();
    return ok;
}

int far savegame_read(char *filename) {
    int src_fd;
    int dest_fd;
    long remaining;
    unsigned short far *version_ptr;
    char temp_path[50];
    int ok;
    int chunk;

    ok = 1;
    remaining = 0x51aa9;

    if (g_cfgTempDrive != 0) {
        sprintf(temp_path, "%c:%s", g_cfgTempDrive, "TEMP.GAM");
    } else {
        sprintf(temp_path, "%s", "TEMP.GAM");
    }

    if ((dest_fd = open(temp_path, 0x8302, 0x180)) >= 0) {
        if ((src_fd = open(filename, -0x7fff)) >= 0) {
            if (dos_read(g_pMainScratchBuf, 100, src_fd) != 100)
                ok = 0;
            version_ptr = (unsigned short far *)((char huge *)g_pMainScratchBuf + 0x62);
            if (ok != 0 && *version_ptr != 0x16)
                ok = 0;
            while (ok != 0 && remaining != 0) {
                chunk = (remaining > 0x3a98) ? 15000 : (int)remaining;
                remaining -= chunk;
                if (dos_read(g_pMainScratchBuf, (long)chunk, src_fd) != (long)chunk) {
                    ok = 0;
                    continue;
                }
                if (dos_write(g_pMainScratchBuf, (long)chunk, dest_fd) != (long)chunk) {
                    ok = 0;
                }
            }
            if (close(src_fd) != 0)
                goto src_close_fail;
            goto close_dest;
        }
    src_close_fail:
        ok = 0;
    close_dest:
        if (close(dest_fd) != 0) {
            ok = 0;
        }
        if (ok == 0) {
            remove(temp_path);
        }
    } else {
        ok = 0;
    }
    return ok;
}

char *g_pChapDatFilename = "CHAPx.DAT";

void far savegame_chapter_start_dispatch(int chapter) {
    PlayerSpawnRecord spawn_rec;
    unsigned long round_time;
    long saved_gold;
    Actor far *actor_ptr;
    Actor far *src_actor;
    int i;

    saved_gold = g_gameState.nParty_gold;
    g_gameState.game_time += 0xa8c0;
    g_gameState.game_time -= g_gameState.game_time % 0xa8c0;
    round_time = g_gameState.game_time;

    for (i = 0; i < 0x50; i++) {
        timerpool_tick(30000);
    }

    if (chapter > 1) {
        g_wLastTempWriteRecordKind = 1;
        gstate_temp_file_write_at((unsigned char *)&g_gameState.nParty_gold,
                                  (unsigned long)(unsigned int)((chapter - 1) * 4 + 0x12f7), 4);
    }

    g_pChapDatFilename[4] = (char)chapter + '0';
    {
        BakFile *stream = bak_fopen(g_pChapDatFilename, "rb");
        bak_fread(&g_gameState, 1, 0x10, stream);
        bak_fread(&spawn_rec, 7, 1, stream);
        bak_fclose(stream);
    }

    zone_set_plr_pos_rec(&spawn_rec);

    g_gameState.nParty_gold += saved_gold;
    g_gameState.game_time += round_time;

    g_gameState.dwLastActionTimeSnapshot = g_gameState.game_time;
    g_gameState.nPrevZoneId = '\0';

    hotspotevt_done_reset_all();
    g_gameState.wPalEventMask = 0;
    g_gameState.nSpellMenuCasterSlot = -1;
    g_gameState.nSpellMenuPreselect = -1;
    palette_state_reset();

    switch (chapter) {
    case 2:
        itemuse_actor_spawn_clone_inv(g_gameState.party_members[CHR_LOCKLEAR].actor_record, 0xf, 2L,
                                      2L);
        break;

    case 4:
        itemuse_actor_spawn_clone_inv(g_gameState.party_members[CHR_OWYN].actor_record, 0xc,
                                      0xa9a10L, 0xab180L);
        itemuse_actor_spawn_clone_inv(g_gameState.party_members[CHR_GORATH].actor_record, 0xc,
                                      0xaa820L, 0xaa1e0L);
        for (i = 1; i <= 2; i++) {
            actor_ptr = (Actor far *)((unsigned char far *)g_gameState.party_members[i].actor_record +
                                      sizeof(Actor));
            ((ItemSlot far *)actor_ptr)->item_id = 0x54;
            ((ItemSlot far *)actor_ptr)->condition = 0x06;

            ((ItemSlot far *)actor_ptr)->flags = (i == 1) ? 1 : 0;
            g_gameState.party_members[i].actor_record->itemCount = 1;
        }
        palette_fade_run_scheduled(palette_fade_schedule(0, 0x2a30L));
        g_gameState.nParty_gold = 0;
        break;

    case 5:
        actor_ptr = actorspawn_objfixed(0, 10L, 0L);
        g_gameState.party_members[CHR_LOCKLEAR].actor_record->itemCount = actor_ptr->itemCount;
        for (i = 0; i < (int)(unsigned int)actor_ptr->itemCount; i++) {
            ACTOR_ITEM(g_gameState.party_members[CHR_LOCKLEAR].actor_record, i) =
                ACTOR_ITEM(actor_ptr, i);
        }
        actorspawn_destroy_and_persist(actor_ptr);

    case 6:

        if (chapter == 6) {
            actor_ptr = actorspawn_objfixed(0, 20L, 1L);
            src_actor = actorspawn_objfixed(0, 30L, 1L);
            itemuse_actor_spawn_clone_inv(actor_ptr, 0xf, 0x3cL, 3L);
            itemuse_actor_spawn_clone_inv(src_actor, 0xf, 0x40L, 3L);
            actorspawn_destroy_and_persist(actor_ptr);
            actorspawn_destroy_and_persist(src_actor);
#ifdef V102CD
            gstate_event_write(0x1959, 0);
            gstate_event_write(0x195a, 0);
#endif
        }

    case 7:
    case 8:
        gstate_temp_file_read_at((unsigned char *)&g_gameState.nParty_gold,
                                 (unsigned long)(unsigned int)((chapter - 2) * 4 + 0x12f7), 4);
        break;
    }

    if (g_gameState.nChapter == 3) {
        gstate_event_write(0x1fbc, 0);
    }
    if (g_gameState.nChapter == 7) {
        gstate_event_write(0x1ab1, 1);
    }

    stat_party_heal_all(100);
    dialog_play_record(0x1e8497L, 0);
    g_gameState.bPartyDirtyFlags = '\0';
}
