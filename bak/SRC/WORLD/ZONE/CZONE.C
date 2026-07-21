#include "globals.h"
#include "structs.h"
#include "SRC/WORLD/ZONE/CZONE.H"
#include "SRC/IO/IO.H"
#include "SRC/SYS/MEM.H"
#include "SRC/SYS/DOSMEM.H"
#include "SRC/R3D/TBLSTORE/SHAPETBL.H"
#include "SRC/WORLD/ZONE/ZONE.H"
#include "SRC/WORLD/ENC/HOTSPOT.H"
#include "SRC/WORLD/ENC/RGNENC.H"
#include "SRC/WORLD/CURSOR/WORLDDOR.H"
#include "SRC/R3D/VIS/VISENTRY.H"

VisibleEntryList *g_apCombat_zone_actor_lists[9];
short g_nCombat_zone_count;
unsigned char g_abOpenZoneTileX[9];
unsigned char g_abOpenZoneTileY[9];
long g_lZoneDefaultZ;
unsigned short g_wZoneDefaultYaw;

unsigned char g_nOpenZoneTileCount = 0x00;
char g_szZoneWldFilename[12] = "Tzzxxyy.WLD";

void far czone_subsystem_init(void) {
    ulong sz;
    WorldObject far *p;
    VisibleEntryList *list;
    int i;

    list = galloc_safe_zcalloc(0x5a);
    sz = 0xf308;
    p = (WorldObject far *)alloc_far(sz, 0);
    i = 0;
    do {
        list->bZone = 0;
        list->pEntries = (WorldObject far *)p;

        p += 300;
        g_apCombat_zone_actor_lists[i] = list;
        list = list + 1;
        i = i + 1;
    } while (i < 9);
    g_pFixed_object_entries = p;

    g_pVisible_entry_pool = p + 35;
    g_nCombat_zone_count = 0;
    czone_load_actors(g_gameState.nZoneId, g_gameState.nPlayerTileX, g_gameState.nPlayerTileY,
                      g_apCombat_zone_actor_lists[0]);
    czone_rebuild_actor_list();
    rgnenc_alloc_3bufs_init();
    if (g_gameState.nZoneId != g_gameState.nPrevZoneId) {
        czone_spell_state_reset_pair();
        rgnenc_savefile_init_35slot_tbl();
    }
    czone_region_encounters_load();
}

void far czone_cache_evict_lru_slot(void) {
    int i;
    VisibleEntryList *lowest_list;

    lowest_list = g_apCombat_zone_actor_lists[0];
    rgnenc_release_anim_images_slot4();
    rgnenc_free_3bufs_clear();
    g_gameState.nPlayerTileX = g_apCombat_zone_actor_lists[0]->bParty_x;
    g_gameState.nPlayerTileY = g_apCombat_zone_actor_lists[0]->bParty_y;
    for (i = 1; i < 9; i = i + 1) {
        if (g_apCombat_zone_actor_lists[i] < lowest_list) {
            lowest_list = g_apCombat_zone_actor_lists[i];
        }
    }
    _freemem(lowest_list->pEntries);
    galloc_zfree(lowest_list);
}

void far czone_resync_on_world_move(void) {
    int found_idx;
    VisibleEntryList *swap_tmp;
    byte key1;
    byte key2;

    key1 = (byte)(g_world_camera->base.pos.xy.nWorld_x / 64000);
    key2 = (byte)(g_world_camera->base.pos.xy.nWorld_y / 64000);
    if ((g_apCombat_zone_actor_lists[0]->bParty_x != key1) ||
        (g_apCombat_zone_actor_lists[0]->bParty_y != key2)) {
        if (czone_find_combat_table_entry(key1, key2, &found_idx) != 0) {
            rgnenc_zone_rectr_save_objects();
            swap_tmp = g_apCombat_zone_actor_lists[found_idx];
            g_apCombat_zone_actor_lists[found_idx] = g_apCombat_zone_actor_lists[0];
            g_apCombat_zone_actor_lists[0] = swap_tmp;
            czone_rebuild_actor_list();
            czone_spell_state_reset_pair();
            czone_region_encounters_load();
        }
    }
}

struct ZoneActorRecord {
    unsigned short wId;
    EulerAngles variant;
    WorldPos worldpos;
};

void far czone_load_actors(byte zone, byte x, byte y, VisibleEntryList *list) {
    ushort count;
    BakFile *fp;
    int i;
    int throttle_reset;
    int throttle;
    WorldObject far *cur;
    Shape far *prec;
    struct ZoneActorRecord rec;

    cur = list->pEntries;
    g_szZoneWldFilename[1] = 0x30 | zone / 10;
    g_szZoneWldFilename[2] = 0x30 | zone % 10;
    g_szZoneWldFilename[3] = 0x30 | x / 10;
    g_szZoneWldFilename[4] = 0x30 | x % 10;
    g_szZoneWldFilename[5] = 0x30 | y / 10;
    g_szZoneWldFilename[6] = 0x30 | y % 10;
    fp = bak_fopen(g_szZoneWldFilename, "rb");
    count = (ushort)(bak_filelength(fp) / 0x14);

    if (300 < (int)count) {
        count = 300;
    }
    list->bZone = zone;
    list->bParty_x = x;
    list->bParty_y = y;
    list->wEntry_count = count;
    throttle_reset = throttle =
        g_engine_prefs->detail_level > 1 ? 300 : (g_engine_prefs->detail_level != 0 ? 5 : 2);
    i = 0;
    if (i < (int)count) {
        do {
            bak_fread(&rec, 0x14, 1, fp);
            prec = ts_get_shape(rec.wId);
            if (prec->kind != 5 || throttle-- > 0) {
                cur->shapeId = rec.wId;
                cur->orientation = rec.variant;
                cur->pos = rec.worldpos;
                cur->state.stateBits = 0;
                cur++;
            } else {
                throttle = throttle_reset;
                list->wEntry_count--;
            }
            i++;
        } while (i < (int)count);
    }
    bak_fclose(fp);
    list->bRef_pair_index = zone_ref_find_pair_index(zone, x, y);
    if (g_game_mode == 2) {
        worlddoor_load_door_records(list);
    } else {
        visentry_mark_dollar_flag14(list);
    }
}

void czone_rebuild_actor_list(void) {
    VisibleEntryList *swap_tmp;
    int nUpper;
    register int i;
    register int next_slot;
    unsigned char x[8];
    unsigned char y[8];
    int found_index;
    uint open_enabled;
    int needs_spawn[8];
    unsigned char partyX;
    unsigned char partyY;

    partyX = g_apCombat_zone_actor_lists[0]->bParty_x;
    partyY = g_apCombat_zone_actor_lists[0]->bParty_y;
    next_slot = 1;
    open_enabled = g_wZoneFlags & 4;
    g_nOpenZoneTileCount = 0;

    x[0] = x[3] = x[5] = partyX - 1;
    x[1] = x[6] = partyX;
    x[2] = x[4] = x[7] = partyX + 1;

    y[5] = y[6] = y[7] = partyY - 1;
    y[3] = y[4] = partyY;
    y[0] = y[1] = y[2] = partyY + 1;

    for (i = 0; i < 8; i = i + 1) {
        needs_spawn[i] = 0;
        if (zone_grid_bit_get(x[i], y[i]) != 0) {
            if (czone_find_combat_table_entry(x[i], y[i], &found_index) != 0) {
                swap_tmp = g_apCombat_zone_actor_lists[found_index];
                g_apCombat_zone_actor_lists[found_index] = g_apCombat_zone_actor_lists[next_slot];
                g_apCombat_zone_actor_lists[next_slot] = swap_tmp;
                next_slot = next_slot + 1;
            } else {
                needs_spawn[i] = 1;
            }
        } else {
            if ((open_enabled != 0) && (g_nOpenZoneTileCount < 9)) {
                g_abOpenZoneTileX[g_nOpenZoneTileCount] = x[i];
                g_abOpenZoneTileY[g_nOpenZoneTileCount] = y[i];
                g_nOpenZoneTileCount++;
            }
        }
    }

    i = next_slot;
    nUpper = 8;
    if (i < nUpper) {
        do {
            if (!g_apCombat_zone_actor_lists[nUpper]->bZone) {
                swap_tmp = g_apCombat_zone_actor_lists[nUpper];
                g_apCombat_zone_actor_lists[nUpper] = g_apCombat_zone_actor_lists[i];
                g_apCombat_zone_actor_lists[i] = swap_tmp;
                i = i + 1;
            }
            nUpper = nUpper + -1;
        } while (i < nUpper);
    }

    i = 0;
    do {
        if (needs_spawn[i] != 0) {
            czone_load_actors(g_gameState.nZoneId, x[i], y[i],
                              g_apCombat_zone_actor_lists[next_slot++]);
        }
        i = i + 1;
    } while (i < 8);

    g_nCombat_zone_count = next_slot;
    return;
}

int czone_find_combat_table_entry(byte key1, byte key2, int *out_index) {
    VisibleEntryList **list_cursor;
    int *pOut;
    int i;

    pOut = out_index;
    list_cursor = g_apCombat_zone_actor_lists;
    list_cursor = list_cursor + 1;
    i = 1;
    while (i < 9) {
        if ((((*list_cursor)->bZone != 0) && ((*list_cursor)->bParty_x == key1)) &&
            ((*list_cursor)->bParty_y == key2)) {
            *pOut = i;
            return 1;
        }
        i = i + 1;
        list_cursor = list_cursor + 1;
    }
    return 0;
}

void far czone_region_encounters_load(void) {
    hotspotevt_monst_load_tbl_cur_id();
    rgnenc_load_encounter_actors();
}

void far czone_spell_state_reset_pair(void) {
    hotspotevt_scout_tried_clear_all();
    hotspotevt_scouted_clear_all();
}

void far czone_save_persist_zone_plr(void) {
    rgnenc_persist_zone_snapshot();
    g_gameState.nPlayerTileX = g_apCombat_zone_actor_lists[0]->bParty_x;
    g_gameState.nPlayerTileY = g_apCombat_zone_actor_lists[0]->bParty_y;
}

void far czone_reset_and_reload(void) {
    int i;

    g_gameState.nPlayerTileX = g_apCombat_zone_actor_lists[0]->bParty_x;
    g_gameState.nPlayerTileY = g_apCombat_zone_actor_lists[0]->bParty_y;
    i = 0;
    do {
        g_apCombat_zone_actor_lists[i]->bZone = 0;
        i++;
    } while (i < 9);
    czone_load_actors(g_gameState.nZoneId, g_gameState.nPlayerTileX, g_gameState.nPlayerTileY,
                      g_apCombat_zone_actor_lists[0]);
    czone_rebuild_actor_list();
}

void czone_get_party_tile_xy(byte *out_x, byte *out_y) {
    *out_x = g_apCombat_zone_actor_lists[0]->bParty_x;
    *out_y = g_apCombat_zone_actor_lists[0]->bParty_y;
}

void czone_world_pos_to_grid_xy(char *out_tile_x, char *out_tile_y) {
    *out_tile_x = (char)((g_world_camera->base.pos.xy.nWorld_x / 0x640) % 0x28);
    *out_tile_y = (char)((g_world_camera->base.pos.xy.nWorld_y / 0x640) % 0x28);
}

void czone_world_pos_from_tile(uchar tile_x, uchar tile_y, uchar sub_x, uchar sub_y,
                               WorldPos2 *out_pos) {
    out_pos->nWorld_x = (long)tile_x * 64000 + (long)sub_x * 0x640;
    out_pos->nWorld_y = (long)tile_y * 64000 + (long)sub_y * 0x640;
}

void far czone_world_pos_tile_sub_ctr(uchar tile_x, uchar tile_y, uchar sub_x, uchar sub_y,
                                      WorldPos2 *out_pos) {
    czone_world_pos_from_tile(tile_x, tile_y, sub_x, sub_y, out_pos);
    out_pos->nWorld_x += 800L;
    out_pos->nWorld_y += 800L;
}
