#include "SRC/GAME/GMAIN.H"
#include "SRC/GEN/GFXCTX.H"
#include "SRC/WORLD/ZONE/ZONE.H"
#include "SRC/WORLD/ACTOR/ACTOR.H"
#include "SRC/COMBAT/ACTOR/CACTOR.H"
#include "SRC/SYS/RAND.H"
#include "SRC/IO/IO.H"
#include "SRC/SYS/MEM.H"
#include "SRC/AUDIO/ENGINE/AUDIO.H"
#include "SRC/GFX/FONT/FONT.H"
#include "SRC/GFX/SPRITE/RESBLIT.H"
#include "SRC/GFX/SPRITE/RECTSPR.H"
#include "SRC/INPUT/KEYBOARD.H"
#include "SRC/SYS/DOSMEM.H"
#include "SRC/GFX/SPRITE/SPRTHNKS.H"
#include "SRC/GAME/MAINDATA.H"
#include "SRC/R3D/SCENE/WORLDHIT.H"
#include "SRC/R3D/CORE/R3D.H"
#include "SRC/R3D/SPRITE/WORLDRND.H"
#include "SRC/R3D/ACTOR/ACTMOTN.H"
#include "SRC/GFX/SCREEN/SCREEN.H"
#include "SRC/R3D/PROJECT/PROJECT.H"
#include "SRC/COMBAT/GRID/CMBTGRID.H"
#include "SRC/R3D/FX/WORLDFX.H"
#include "SRC/SYS/EMSIMG.H"
#include "SRC/CHAR/STAT.H"
#include "SRC/SCREENS/ITEMTBL.H"
#include "SRC/COMBAT/ARENA/COMBAT.H"
#include "SRC/COMBAT/ENC/CBENC.H"
#include "SRC/COMBAT/AI/CMBTAI.H"
#include "SRC/COMBAT/SPELL/CSPELL.H"
#include "SRC/COMBAT/AI/CBTAIACT.H"
#include "SRC/COMBAT/STATS/CBSTAT.H"
#include "SRC/WORLD/ENC/RGNENC.H"
#include "defines.h"
#include "structs.h"

#include <dos.h>
#include <stdlib.h>
#include <string.h>

int g_combat_count_A;
CombatActor *g_combat_actors_A;
AnimSlot *g_anim_pool_A;
unsigned char g_bssgap_5028[2];
CombatActor **g_active_combatants;
/* Per-actor sprite tables: 11 near ImageRecord ** asset-table entries per row
   (22 bytes/row). Entries [2] and [10] of each row are never written (BSS zero). */
ImageRecord **g_aCombatInnerPool[7][11];
CombatResCacheCol g_aCombatResCacheKindFlag;
CombatResCacheCol g_aCombatResCacheRefcount;
unsigned short g_aCombatResCacheKey[8];
ImageRecord **g_aCombatResCacheValue[8][3];

#define MAX_COMBAT_ACTORS 7
#define MAX_ACTIVE_COMBATANTS 25
#define COMBAT_GRID_COLS 8
#define COMBAT_GRID_ROWS 13
#define NUM_ACTOR_STATS 16
#define RES_CACHE_SLOTS 8

void far combat_actor_init_pool(void) {
    CombatActorInner *pInnerPool;
    long lSeekOffset;
    BakFile *stream;
    int i;

    g_combat_actors_A = (CombatActor *)galloc_safe_zcalloc(sizeof(CombatActor) * MAX_COMBAT_ACTORS);
    g_combat_count_A = 0;
    for (i = 0; i < g_gameState.party_count; i++) {
        if (g_gameState.party_roster[i] > (char)-1) {
            g_combat_actors_A[i] = g_gameState.party_members[g_gameState.party_roster[i]];
            g_combat_count_A++;
        }
    }

    pInnerPool =
        (CombatActorInner *)galloc_safe_zcalloc(sizeof(CombatActorInner) * MAX_COMBAT_ACTORS);
    g_anim_pool_A = (AnimSlot *)galloc_safe_zcalloc(sizeof(AnimSlot) * MAX_COMBAT_ACTORS);
    stream = bak_fopen("p1.dat", "rb");
    for (i = 0; i < g_combat_count_A; i++) {
        lSeekOffset =
            (long)(unsigned int)((g_combat_actors_A[i].cParty_slot - 1) * sizeof(CombatActorInner));
        bak_fseek(stream, lSeekOffset, 0);
        bak_fread(&pInnerPool[i], sizeof(CombatActorInner), 1, stream);
    }
    bak_fclose(stream);

    i = 0;
    do {
        g_combat_actors_A[i].inner = &pInnerPool[i];
        if ((i < g_nCombatActiveCount) &&
            (g_gameState.abActorStatusRanks[g_gameState.party_roster[i]][2] != 0)) {
            cbstat_apply_drain_tick(&g_combat_actors_A[i]);
        }
        i++;
    } while (i < MAX_COMBAT_ACTORS);

    for (i = 0; i < g_combat_count_A; i++) {
        combat_actor_rsrc_load_3values(g_combat_actors_A[i].inner->class_id, g_aCombatInnerPool[i]);
        g_anim_pool_A[i].sprite_header = g_aCombatInnerPool[i];
        g_combat_actors_A[i].inner->status_head = -1;
    }

    g_active_combatants =
        (CombatActor **)galloc_safe_zcalloc(sizeof(CombatActor *) * MAX_ACTIVE_COMBATANTS);
}

void far combat_actor_pool_teardown(void) {
    Actor far *actor_rec;
    int i;
    int j;

    for (i = g_combat_count_A - 1; i >= 0; i--)
        combat_actor_release_anim_images(g_combat_actors_A[i].inner->class_id);

    galloc_zfree(g_active_combatants);
    galloc_zfree(g_anim_pool_A);
    galloc_zfree(g_combat_actors_A->inner);

    for (i = 0; i < g_combat_count_A; i++) {
        if (g_combat_actors_A[i].cParty_slot != 0) {
            g_combat_actors_A[i].inner = (CombatActorInner *)0;
            g_gameState.party_members[g_gameState.party_roster[i]] = g_combat_actors_A[i];
        }
    }

    galloc_zfree(g_combat_actors_A);

    for (i = 0; i < g_gameState.party_count; i++) {
        actor_rec = g_gameState.party_members[g_gameState.party_roster[i]].actor_record;

        stat_actor_clear_mods_mask(&g_gameState.party_members[g_gameState.party_roster[i]], 0x100);
        for (j = 0; actor_rec->itemCount > j; j++) {
            if (ACTOR_ITEM(actor_rec, j).flags & 4)
                ACTOR_ITEM(actor_rec, j).flags &= 0xe07b;
        }
    }
}

void far combat_actor_place_on_free_tile(CombatActor *actor) {
    int col;
    int row;

    if (combatgrid_any_terrain_6() != 0 || (actor->inner->flags & CAF_DEAD) == 0) {
        for (row = actor->inner->grid_y; row > -1; row--) {
            col = (actor->inner->grid_y == row) ? actor->inner->grid_x : 0;
            for (; col < COMBAT_GRID_COLS; col++) {
                if (combatgrid_tile_is_blocked((char)col, (char)row) == 0 ||
                    (CombatActor *)combatgrid_tile_terrain((char)col, (char)row) == actor) {
                    actor->inner->grid_x = col;
                    actor->inner->grid_y = row;
                    if (actor->inner->flags & CAF_DEAD) {
                        combat_actor_register(actor);
                        return;
                    }
                    combatgrid_tile_set_word((char)col, (char)row, (unsigned int)actor);
                    return;
                }
            }
        }
        row = 0;
        do {
            col = 0;
            do {
                if (combatgrid_tile_is_blocked((char)col, (char)row) == 0 ||
                    (CombatActor *)combatgrid_tile_terrain((char)col, (char)row) == actor) {
                    actor->inner->grid_x = col;
                    actor->inner->grid_y = row;
                    if (actor->inner->flags & CAF_DEAD) {
                        combat_actor_register(actor);
                        return;
                    }
                    combatgrid_tile_set_word((char)col, (char)row, (unsigned int)actor);
                    return;
                }
                col++;
            } while (col < COMBAT_GRID_COLS);
            row--;
        } while (row < COMBAT_GRID_ROWS);
    }
}

CombatActor *combat_actor_party_add(int class_id) {
    int slot;

    if (g_combat_count_A < MAX_COMBAT_ACTORS) {
        slot = g_combat_count_A;
        combat_actor_rsrc_load_3values(class_id, g_aCombatInnerPool[slot]);
        g_anim_pool_A[slot].sprite_header = g_aCombatInnerPool[slot];
        (g_combat_actors_A[slot].inner)->class_id = class_id;
        (g_combat_actors_A[slot].inner)->status_head = -1;
        if (g_aCombatInnerPool[0] == 0)
            return (CombatActor *)0;
        if (g_aCombatInnerPool[1] == 0)
            return (CombatActor *)0;
        if (g_aCombatInnerPool[2] == 0)
            return (CombatActor *)0;
        g_combat_count_A++;
        g_nCombatActiveCount++;
        return &g_combat_actors_A[slot];
    }
    return (CombatActor *)0;
}

#ifdef V102CD
CombatActor *far combat_actor_remove(CombatActor *actor) {
    int i;
    int removed_slot;
    CombatActor tmp;

    i = 0;
    while (i < g_combat_count_A) {
        if (&g_combat_actors_A[i] == actor)
            break;
        i = i + 1;
    }
    g_combat_count_A--;
    g_nCombatActiveCount--;
    if (i != g_combat_count_A) {
        tmp = g_combat_actors_A[i];
        g_combat_actors_A[i] = g_combat_actors_A[g_combat_count_A];
        g_combat_actors_A[g_combat_count_A] = tmp;
        combatgrid_tile_set_word(g_combat_actors_A[i].inner->grid_x,
                                 g_combat_actors_A[i].inner->grid_y,
                                 (unsigned int)(&g_combat_actors_A[i]));
    }
    removed_slot = g_combat_count_A;
    i = 0;
    while (i < g_combat_count_B) {
        if ((g_combat_actors_B[i].inner)->target == actor) {
            (g_combat_actors_B[i].inner)->target = (CombatActor *)0x0;
        }
        i = i + 1;
    }
    combat_actor_release_anim_images(actor->inner->class_id);
    return &g_combat_actors_A[removed_slot];
}
#else
void far combat_actor_remove(CombatActor *actor) {
    int i;

    i = 0;
    while (i < g_combat_count_A) {
        if (&g_combat_actors_A[i] == actor)
            break;
        i = i + 1;
    }
    g_combat_count_A--;
    g_nCombatActiveCount--;
    if (i != g_combat_count_A) {
        g_combat_actors_A[i] = g_combat_actors_A[g_combat_count_A];
        combatgrid_tile_set_word(g_combat_actors_A[i].inner->grid_x,
                                 g_combat_actors_A[i].inner->grid_y, (unsigned int)(&g_combat_actors_A[i]));
    }
    i = 0;
    while (i < g_combat_count_B) {
        if ((g_combat_actors_B[i].inner)->target == actor) {
            (g_combat_actors_B[i].inner)->target = (CombatActor *)0x0;
        }
        i = i + 1;
    }
    combat_actor_release_anim_images(actor->inner->class_id);
}
#endif

void combat_actor_register(CombatActor *actor) {
    int i;

    combatgrid_tile_set_word(actor->inner->grid_x, actor->inner->grid_y, 0);
    i = 0;
    do {
        if (g_active_combatants[i] == 0) {
            g_active_combatants[i] = actor;
            return;
        }
        i = i + 1;
    } while (i < MAX_ACTIVE_COMBATANTS);
    return;
}

void far combat_actor_grid_remove(CombatActor *actor) {
    int i;

#ifdef V102CD
    if (combatgrid_tile_terrain(actor->inner->grid_x, actor->inner->grid_y) == 0)
        combatgrid_tile_set_word(actor->inner->grid_x, actor->inner->grid_y, (unsigned int)actor);
#else
    combatgrid_tile_set_word(actor->inner->grid_x, actor->inner->grid_y, (unsigned int)actor);
#endif
    i = 0;
    do {
        if (g_active_combatants[i] == actor) {
            g_active_combatants[i] = (CombatActor *)0;
            return;
        }
        i = i + 1;
    } while (i < MAX_ACTIVE_COMBATANTS);
}

CombatActor *combat_actor_visible_at_tile(int tile_x, int tile_y) {
    int i;

    i = 0;
    do {
        if (((g_active_combatants[i] != 0) && (g_active_combatants[i]->inner->grid_x == tile_x)) &&
            (g_active_combatants[i]->inner->grid_y == tile_y)) {
            return g_active_combatants[i];
        }
        i = i + 1;
    } while (i < MAX_ACTIVE_COMBATANTS);
    return (CombatActor *)0;
}

CombatActor *combat_actor_encounter_at_tile(int tile_x, int tile_y) {
    int i;

    i = 0;
    do {
        if (((g_active_combatants[i] != 0 && (g_active_combatants[i]->inner->grid_x == tile_x)) &&
             (g_active_combatants[i]->inner->grid_y == tile_y)) &&
            (combatenc_is_encounter_actor(g_active_combatants[i]) != 0)) {
            return g_active_combatants[i];
        }
        i = i + 1;
    } while (i < MAX_ACTIVE_COMBATANTS);
    return (CombatActor *)0;
}

int combat_actor_is_visible(CombatActor *actor) {
    int i;

    i = 0;
    do {
        if (g_active_combatants[i] == actor) {
            return 1;
        }
        i = i + 1;
    } while (i < MAX_ACTIVE_COMBATANTS);
    return 0;
}

void combat_actor_deploy_encounter(void) {
    EncounterObjectPose pose;
    int grid_x;
    int grid_y;
    long world[3];

    int slot_index;
    CombatActor *actor;
    CombatActor *occupant;

    for (slot_index = 0; slot_index < g_combat_count_B; slot_index++) {
        if (combat_actor_is_visible(&g_combat_actors_B[slot_index]) != 0) {
            actor = &g_combat_actors_B[slot_index];
            grid_x = actor->inner->grid_x;
            grid_y = actor->inner->grid_y;
            goto tile_check;
        tile_loop:
            grid_x = (grid_x >= COMBAT_GRID_COLS - 1) ? 0 : grid_x + 1;
            if (grid_x == 0)
                grid_y = (grid_y >= COMBAT_GRID_ROWS - 1) ? 0 : grid_y + 1;
            actor->inner->grid_x = (unsigned char)grid_x;
            actor->inner->grid_y = (unsigned char)grid_y;
        tile_check:
            occupant = combat_actor_visible_at_tile(grid_x, grid_y);
            if (occupant != (CombatActor *)0 && occupant != actor)
                goto tile_loop;
            combatgrid_tile_to_world_rotated((WorldPos2 *)world, grid_x, grid_y);
            pose.nWorld_x_offset = world[0];
            pose.nWorld_y_offset = world[1];
            pose.nFacing = g_anim_pool_B[slot_index].facing * R3D_DEG(45) +
                           (g_world_camera->base.orientation.yaw & 0xe000U) + R3D_DEG(180);
            if ((g_world_camera->base.orientation.yaw & 0x1000U) != 0)
                pose.nFacing += R3D_DEG(45);
            rgnenc_persist_actor_placed((long)(short)g_encounter_id, slot_index,
                                        (EncounterObjectState *)&pose);
        }
    }
}

int combat_actor_bitmap_set_bit(int bitmap, int bit_index) {
    int word_idx;
    unsigned int mask;
    int already_set;

    word_idx = bit_index / 0x10;
    mask = 1 << (bit_index % 0x10);
    already_set = (*(unsigned int *)(bitmap + 2 + word_idx * 2) & mask) != mask;
    *(unsigned int *)(bitmap + 2 + word_idx * 2) |= mask;
    return already_set;
}

void far combat_actor_flag_bitset_clear(int record, int bit) {
    int word_index;
    int mask;

    word_index = bit / 0x10;
    mask = 1 << (bit % 0x10);
    *(unsigned *)(record + word_index * 2 + 2) &= ~mask;
}

int combat_actor_cnt_qrls_kind(CombatActor *actor, int kind) {
    int counts[10];
    Actor far *rec;
    int i;
    int total;

    rec = actor->actor_record;
    for (i = 0; i < 10; i++)
        counts[i] = 0;

    for (i = 0; i < rec->itemCount; i++) {
        switch (ACTOR_ITEM(rec, i).item_id) {
        case 0x24:
            counts[0] += ACTOR_ITEM(rec, i).condition;
            break;
        case 0x25:
            counts[1] += ACTOR_ITEM(rec, i).condition;
            break;
        case 0x26:
            counts[2] += ACTOR_ITEM(rec, i).condition;
            break;
        case 0x27:
            counts[4] += ACTOR_ITEM(rec, i).condition;
            break;
        case 0x28:
            counts[5] += ACTOR_ITEM(rec, i).condition;
            break;
        case 0x29:
            counts[6] += ACTOR_ITEM(rec, i).condition;
            break;
        case 0x2b:
            counts[7] += ACTOR_ITEM(rec, i).condition;
            break;
        case 0x2a:
            counts[3] += ACTOR_ITEM(rec, i).condition;
            break;
        }
    }

    if (kind != -1)
        return counts[kind];

    total = 0;
    for (i = 0; i < 10; i++)
        total += counts[i];
    return total;
}

static void combat_actor_copy_11_words(unsigned short *dst, unsigned short *src) {
    int i;
    for (i = 0; i < 11; i++) {
        dst[i] = src[i];
    }
}

ImageRecord **far combat_actor_bnames_load_cached(int class_id, int col) {

    char nameMeta[4];
    char nameChars[4];
    char idxStr[6];
    char local_ext[5] = ".bmx";
    char local_pfx[8] = "csx.dat";
    unsigned int blobSize;
    int offCount;
    void *offTable;
    void *strBlob;
    unsigned char *palette;
    ImageRecord **assetTable;
    int neg_count;
    char fname[14];

    BakFile *fp;
    int slot;
    int i;

    palette = (unsigned char *)0;
    i = 0;
    do {
        if (g_aCombatResCacheKey[i] == class_id && g_aCombatResCacheValue[i][col] != 0) {
            g_aCombatResCacheRefcount[i][col]++;
            return g_aCombatResCacheValue[i][col];
        }
        i = i + 1;
    } while (i < RES_CACHE_SLOTS);

    fp = bak_fopen("bnames.dat", "rb");
    bak_fread(&offCount, 2, 1, fp);
    offTable = galloc_safe_zcalloc(offCount << 1);
    bak_fread(offTable, 2, offCount, fp);
    bak_fread(&blobSize, 2, 1, fp);
    strBlob = galloc_safe_zcalloc(blobSize);
    bak_fread(strBlob, 1, blobSize, fp);
    bak_fclose(fp);

    ((int *)offTable)[class_id] += (int)strBlob;

    i = 0;
    do {
        nameChars[i] = ((char *)((int *)offTable)[class_id])[i];
        i = i + 1;
    } while (i < 8);

    galloc_zfree(strBlob);
    galloc_zfree(offTable);

    if (nameMeta[col] > 0) {
        if (nameMeta[3] != -1) {

            palette = galloc_safe_zcalloc(0x100);
            local_pfx[2] = nameMeta[3] + '0';
            fp = bak_fopen(local_pfx, "rb");
            if (fp != (BakFile *)0) {
                bak_fread(palette, 1, 0x100, fp);
                bak_fclose(fp);
            } else {
                galloc_zfree(palette);
                palette = (unsigned char *)0;
            }
        }
        itoa(nameMeta[col], idxStr, 10);
        i = 0;
        do {
            fname[i] = nameChars[i];
            i = i + 1;
        } while (i < 5);
        strcat(fname, idxStr);
        strcat(fname, local_ext);
        assetTable = resblit_load_asset_table(fname, 1);
        if (palette != (unsigned char *)0) {
            resblit_list_remap_palette((ResourceRemapDesc **)assetTable, palette);
            galloc_zfree(palette);
        }
    }

    slot = -1;
    i = 0;
    do {
        if (g_aCombatResCacheKey[i] == class_id) {
            slot = i;
            break;
        }
        i++;
    } while (i < RES_CACHE_SLOTS);

    if (slot == -1) {
        i = 0;
        do {
            if (g_aCombatResCacheKey[i] == 0) {
                slot = i;
                break;
            }
            i++;
        } while (i < RES_CACHE_SLOTS);
    }

    if (nameMeta[col] < 0) {

        neg_count = -nameMeta[col];
        assetTable = g_aCombatResCacheValue[slot][col - 1] + neg_count;
        g_aCombatResCacheKey[slot] = class_id;
        g_aCombatResCacheRefcount[slot][col]++;
        g_aCombatResCacheValue[slot][col] = assetTable;
        g_aCombatResCacheKindFlag[slot][col] = 0;
    } else {
        g_aCombatResCacheKey[slot] = class_id;
        g_aCombatResCacheRefcount[slot][col]++;
        g_aCombatResCacheValue[slot][col] = assetTable;
        g_aCombatResCacheKindFlag[slot][col] = 1;
    }
    return assetTable;
}

unsigned short g_wCombatSpinnerYaw = 0;

void far combat_actor_rsrc_load_3values(int class_id, ImageRecord ***table) {
    ImageRecord **loaded[3];
    int i;

    i = 0;
    do {
        loaded[i] = combat_actor_bnames_load_cached(class_id, i);
        i = i + 1;
    } while (i < 3);

    table[0] = loaded[0];
    table[1] = loaded[0];
    table[3] = loaded[1];
    table[4] = loaded[1];
    table[5] = loaded[1];
    table[6] = loaded[1];
    table[7] = loaded[2];
    table[8] = loaded[2];
    table[9] = loaded[2];
}

void far combat_actor_release_anim_images(int class_id) {
    int slot;
    int col;

    slot = 0;
    do {
        if (g_aCombatResCacheKey[slot] == class_id) {
            for (col = 2; col >= 0; col--) {
                if ((int)--g_aCombatResCacheRefcount[slot][col] < 1) {
                    g_aCombatResCacheRefcount[slot][col] = 0;
                    if (g_aCombatResCacheValue[slot][col] != 0) {
                        if (g_aCombatResCacheKindFlag[slot][col] != 0) {
                            emsimg_free_paged((void *)g_aCombatResCacheValue[slot][col]);
                        }
                        g_aCombatResCacheValue[slot][col] = 0;
                    }
                }
            }
            if (g_aCombatResCacheRefcount[slot][0] == 0 &&
                g_aCombatResCacheRefcount[slot][1] == 0 &&
                g_aCombatResCacheRefcount[slot][2] == 0) {
                g_aCombatResCacheKey[slot] = 0;
            }
        }
        slot = slot + 1;
    } while (slot < RES_CACHE_SLOTS);
}

ImageRecord **far combat_actor_rsrc_cache_val(int class_id, int col) {
    int row;

    row = 0;
    do {
        if (g_aCombatResCacheKey[row] == class_id) {
            if ((int)g_aCombatResCacheRefcount[row][col] <= 0) {
                return 0;
            }
            return (ImageRecord **)g_aCombatResCacheValue[row][col];
        }
        row = row + 1;
    } while (row < RES_CACHE_SLOTS);
    return 0;
}

int combat_actor_cursor_distance(CombatActor *actor) {
    int distance;

    if ((((g_cursor_tile_x < 0) || (g_cursor_tile_x >= COMBAT_GRID_COLS)) ||
         (g_cursor_tile_y < 0)) ||
        (g_cursor_tile_y >= COMBAT_GRID_ROWS)) {
        distance = 1000;
    } else {
        distance = combatgrid_chebyshev_distance((char)g_cursor_tile_x, (char)g_cursor_tile_y,
                                                 actor->inner->grid_x, actor->inner->grid_y);
    }
    return distance;
}

ItemRecord far *far combat_actor_qrl_rec_kind(int kind) {
    ItemRecord far *rec;
    ItemSlot far *slot_ptr;

    slot_ptr = (ItemSlot far *)alloc_far(1, 0);
    switch (kind) {
    case 0:
        slot_ptr->item_id = 0x24;
        break;
    case 4:
        slot_ptr->item_id = 0x27;
        break;
    case 5:
        slot_ptr->item_id = 0x28;
        break;
    case 6:
        slot_ptr->item_id = 0x29;
        break;
    case 3:
        slot_ptr->item_id = 0x2a;
        break;
    case 7:
        slot_ptr->item_id = 0x2b;
        break;
    case 1:
        slot_ptr->item_id = 0x25;
        break;
    case 2:
        slot_ptr->item_id = 0x26;
        break;
    default:
        slot_ptr->item_id = 0xff;
        break;
    }
    if (slot_ptr->item_id <= 0x2b) {
        rec = itemtbl_record_ptr(slot_ptr);
    } else {
        rec = (ItemRecord far *)0;
    }
    _freemem(slot_ptr);
    return rec;
}

int far combat_actor_calc_weapon_damage(CombatActor *actor, int kind) {
    ItemRecord far *qrlRec;
    ItemRecord far *weaponRec;
    int damage;

    qrlRec = (ItemRecord far *)0;
    weaponRec = cbstat_find_intact_equip_cat(actor, 2);
    if (kind == 8) {
        damage = RNDR(15, 34);
    } else if (kind == 9) {
        damage = RNDR(5, 11);
    } else {
        qrlRec = combat_actor_qrl_rec_kind(kind);
        if (qrlRec != (ItemRecord far *)0) {
            damage = weaponRec->nSwing_damage + qrlRec->nSwing_damage;
        } else {
            damage = -1;
        }
    }
    return damage;
}

int combat_actor_stat_percent(CombatActor *actor, int with_modifier) {
    unsigned int cur;
    unsigned int maxv;
    int pct;

    if (with_modifier != 0) {
        cur = (unsigned int)actor->stats[SKILL_HEALTH].base + (unsigned int)actor->stats[SKILL_STAMINA].base;
        maxv = (unsigned int)actor->stats[SKILL_HEALTH].max + (unsigned int)actor->stats[SKILL_STAMINA].max;
    } else {
        cur = (unsigned int)actor->stats[SKILL_HEALTH].base;
        maxv = (unsigned int)actor->stats[SKILL_HEALTH].max;
    }
    if ((maxv == 0) || ((actor->inner->flags & CAF_DEAD) != 0)) {
        pct = 0;
    } else {
        pct = (int)(cur * 100) / (int)maxv;
    }
    return pct;
}

unsigned int combat_actor_terr_under_cur(void) {
    unsigned int occupant;

    if ((g_cursor_tile_x >= 0) && (g_cursor_tile_y >= 0)) {
        occupant = combatgrid_tile_terrain((char)g_cursor_tile_x, (char)g_cursor_tile_y);
    } else {
        occupant = 0;
    }
    return occupant;
}

int combat_actor_cur_tile_block(void) {
    int v;

    v = (combatgrid_tile_is_blocked((char)g_cursor_tile_x, (char)g_cursor_tile_y) &&
         combatgrid_tile_terrain((char)g_cursor_tile_x, (char)g_cursor_tile_y) == 0)
            ? 1
            : 0;
    return v;
}

void far combat_actor_move_to_cursor(CombatActor *actor) {
    g_acting_actor_speed++;
    actor->inner->pad_6[0] = (unsigned char)g_cursor_tile_x;
    actor->inner->pad_6[1] = (unsigned char)g_cursor_tile_y;
    combataipath_actor_walk_path(actor, 0);
    return;
}

int far combat_actor_find_by_subrec_id(int class_id) {
    int i;

    for (i = 0; i < g_nCombatActiveCount; i++) {
        if (g_pCombatActiveActors[i].inner->class_id == class_id) {
            break;
        }
    }
    if (i == g_nCombatActiveCount)
        i = 1;
    else
        i = 0;
    return i;
}

int combat_actor_find_by_id(int class_id) {
    int i;
    int f;

    for (i = 0; i < g_combat_count_A; i++) {
        if (g_combat_actors_A[i].inner->class_id != class_id)
            continue;
        if ((f = (signed char)g_combat_actors_A[i].inner->flags) & CAF_DEAD)
            continue;
        if (combatgrid_tile_terrain(g_combat_actors_A[i].inner->grid_x,
                                    g_combat_actors_A[i].inner->grid_y) != 0)
            continue;
        return i;
    }

    for (i = 0; i < g_combat_count_B; i++) {
        if (g_combat_actors_B[i].inner->class_id != class_id)
            continue;
        if ((f = (signed char)g_combat_actors_B[i].inner->flags) & CAF_DEAD)
            continue;
        if (combatgrid_tile_terrain(g_combat_actors_B[i].inner->grid_x,
                                    g_combat_actors_B[i].inner->grid_y) != 0)
            continue;
        return i + 100;
    }

    return -1;
}

void combat_actor_apply_render_table(CombatActor *actor) {
    int is_target;
    int slot;

    is_target = 0;
    if (combatenc_is_encounter_actor(actor) != 0) {
        combat_arena_swap_tgt_state();
        is_target = 1;
    }
    for (slot = 0; slot < g_nCombatActiveCount; slot++) {
        if (&g_pCombatActiveActors[slot] == actor)
            break;
    }
    worldrender_table_swap(
        0, g_pCombatActiveAnimPool[slot].sprite_header[g_pCombatActiveAnimPool[slot].sprite_id]);
    if (is_target != 0) {
        combat_arena_swap_tgt_state();
    }
    return;
}

void combat_actor_anim_step(unsigned char *anim_state_buf, CombatActor *actor) {
    int did_swap;
    int slot;

    did_swap = 0;
    if (combatenc_is_encounter_actor(actor) != 0) {
        did_swap = 1;
        combat_arena_swap_tgt_state();
    }
    slot = 0;
    if (slot < g_nCombatActiveCount) {
        do {
            if (&g_pCombatActiveActors[slot] == actor) {
                break;
            }
            slot = slot + 1;
        } while (slot < g_nCombatActiveCount);
    }
    if (slot < g_nCombatActiveCount) {
        if ((!*(signed char *)&g_pCombatActiveAnimPool[slot].reverse_flag) &&
            (g_pCombatActiveAnimPool[slot].current_frame >
             g_pCombatActiveAnimPool[slot].end_frame)) {
            if (g_pCombatActiveAnimPool[slot].sprite_id == 0) {
                g_pCombatActiveAnimPool[slot].current_frame =
                    g_pCombatActiveAnimPool[slot].end_frame - 1;
                g_pCombatActiveAnimPool[slot].end_frame--;
                g_pCombatActiveAnimPool[slot].reverse_flag = 1;
            } else {
                g_pCombatActiveAnimPool[slot].current_frame =
                    g_pCombatActiveAnimPool[slot].end_frame;
                g_pCombatActiveAnimPool[slot].done_flag = 1;
            }
        }
        if ((g_pCombatActiveAnimPool[slot].reverse_flag != 0) &&
            (g_pCombatActiveAnimPool[slot].current_frame <
             g_pCombatActiveAnimPool[slot].end_frame)) {
            combat_actor_anim0_if_not_dead(actor, -1);
        }
        anim_state_buf[g_pCombatActiveAnimPool[slot].sprite_id] =
            (unsigned char)g_pCombatActiveAnimPool[slot].current_frame;
        if ((g_pCombatActiveAnimPool[slot].done_flag == 0) &&
            (g_pCombatActiveAnimPool[slot].tick_counter %
                 g_pCombatActiveAnimPool[slot].loop_period ==
             0)) {
            if (g_pCombatActiveAnimPool[slot].reverse_flag != 0) {
                g_pCombatActiveAnimPool[slot].current_frame--;
            } else {
                g_pCombatActiveAnimPool[slot].current_frame++;
            }
            if (g_pCombatActiveAnimPool[slot].sprite_id == 0) {
                g_pCombatActiveAnimPool[slot].loop_period = RND2(8) + 8;
            }
            g_pCombatActiveAnimPool[slot].tick_counter = 1;
        } else {
            g_pCombatActiveAnimPool[slot].tick_counter++;
        }
        if (g_pCombatActiveAnimPool[slot].facing > 4) {
            g_nActorSpriteFlip = 2;
        } else {
            g_nActorSpriteFlip = 0;
        }
        if (did_swap != 0) {
            combat_arena_swap_tgt_state();
        }
    }
    return;
}

static void far combat_actor_rndr_stat_vfx_pre(CombatActor *actor) {
    int slot;
    SpellDef *spell;
    unsigned int nTerrain;
    int i;
    unsigned int count;

    for (slot = actor->inner->status_head; slot != -1; slot = g_pStatusEffectPool[slot].nNext) {
        spell = &g_pSpellDefs[g_pStatusEffectPool[slot].nType];
        switch ((unsigned int)spell->nEffect_kind - 3) {
        case 0:
        case 16:

            worldfx_sparkle_tick();
            break;
        case 2:

            worldfx_draw_actor_box_wireframe(actor, g_pStatusEffectPool[slot].nAge_ticks);
            break;
        case 6:
        case 10:

            worldfx_ptcl_overlay_step_back(actor);
            break;
        case 11:

            combat_actor_anim0_if_not_dead(actor, -2);
            break;
        case 13:

            worldfx_depth_clip_actor_scr_y(actor);
            break;
        case 5:

            g_nActorShakeX = RND(3);
            break;
        case 1:

            count = RND2(2);
            for (i = 0; i <= (int)count; ++i) {
                worldfx_render_flame_at_actor(actor);
            }
            break;
        case 3:
        case 4:
        case 7:
        case 8:
        case 9:
        case 12:
        case 14:
        case 15:
            break;
        }
    }

    /* nTerrain homes to [bp-4]. The terrain field is assigned into a real
       local and switched on, so the value is both stored to the slot and left
       in AX for the compare. The store is dead (the switch tests AX, nothing
       reads [bp-4] again), and bcc drops it unless the slot is address-taken --
       so (void)&nTerrain is required to keep the [bp-4] write. The single-case
       switch-on-assignment emits a cmp ax,1 / je / jmp two-jump dispatch. */
    (void)&nTerrain;
    switch (nTerrain = combatgrid_tile_terrain_field(actor->inner->grid_x, actor->inner->grid_y)) {
    case 1:
        g_nActorShakeX = RND(3);
        g_nActorShakeY = RND2(2);
        break;
    }
}

void combat_actor_draw_float_damage(CombatActor *actor) {
    int v;
    int textWidth;
    int x;
    int y;
    int xBound;
    int yBound;
    char buf[10];

    if (actor->inner->dmg_value != 0 && actor->inner->dmg_frames_left != 0) {
        v = (int)actor->inner->dmg_value;
        g_graphics_context.bClip_enabled = 1;
        if ((char)actor->inner->dmg_frames_left > 0) {
            actor->inner->dmg_frames_left--;
            itoa(v < 0 ? (v == -0x8000 ? 0x7fff : -v) : v, buf, 10);
        } else {
            actor->inner->dmg_frames_left++;
            strcpy(buf, "miss");
        }
        if (v > 0) {
            g_graphics_context.bText_fg_color = (char)-0x78 - actor->inner->dmg_frames_left;
        } else {
            g_graphics_context.bText_fg_color = (char)-0x11 - actor->inner->dmg_frames_left;
        }
        textWidth = font_text_width_ds(buf);

        x = (g_nBillboardScrX + (g_nBillboardW >> 1)) - (textWidth >> 1);
        y = g_nBillboardScrY + -5;
        xBound = g_graphics_context.clip.xmin + 2;
        if (x >= xBound) {
            xBound = (g_graphics_context.clip.xmax + -2) - textWidth;
            if (x <= xBound)
                goto L_x_done;
        }
        x = xBound;
    L_x_done:
        yBound = g_graphics_context.clip.ymin + 2;
        if (y >= yBound) {
            yBound = g_graphics_context.clip.ymax + -0xc;
            if (y <= yBound)
                goto L_y_done;
        }
        y = yBound;
    L_y_done:
        font_draw_text_ds(buf, x, y);
    }
    return;
}

static void combat_actor_render_status_vfx(CombatActor *actor) {
    short slot;
    SpellDef *spell;
    int i;
    int n;

    if (g_bShowActorRosterIndex != 0)
        combatenc_draw_actor_roster_idx(actor);
#ifndef V102CD
    combat_actor_draw_float_damage(actor);
#endif

    for (slot = actor->inner->status_head; slot != -1; slot = g_pStatusEffectPool[slot].nNext) {
        spell = &g_pSpellDefs[g_pStatusEffectPool[slot].nType];
        g_pStatusEffectPool[slot].nAge_ticks++;

        switch (spell->nEffect_kind) {
        case 3:
        case 19:
            worldfx_sparkle_render();
            break;
        case 5:
            worldfx_draw_actor_box_wireframe_front(actor, g_pStatusEffectPool[slot].nAge_ticks);
            break;
        case 6:
            worldfx_sparkle_burst(actor, spell->nEffect_sprite_id);
            break;
        case 12:
            worldfx_rndr_rand_flash_at_actor(actor);
            break;
        case 9:
        case 13:
            worldfx_ptcl_overlay_render_front(actor);
            break;
        case 15:
            worldfx_rndr_spr_shadow(spell->nEffect_sprite_id);
            worldfx_sparkle_burst(actor, 0xd0);
            break;
        case 16:
            worldfx_clip_rect_restore();
            break;
        case 4:
            n = RND2(2);
            for (i = 0; i < n; i++)
                worldfx_render_flame_at_actor(actor);
            break;
        }
    }

    g_nActorShakeX = 0;
    g_nActorShakeY = 0;
#ifdef V102CD
    combat_actor_draw_float_damage(actor);
#endif
}

void far combat_actor_play_short_cine(CombatActor *actor, int overlay_id) {
    int i;

    i = 0;
    do {
        if (actor != (CombatActor *)0) {
            combat_arena_actor_set_anim_pose(actor, 3);
        }
        world_render_with_overlay(MK_FP(overlay_id, -1));
        audio_play(0x45);
        screen_frame_present();
        i++;
    } while (i < 10);
}

void far combat_actor_tile_entry_effect(int tile_x, int tile_y, int *p_status, int do_apply,
                                        int extra_flag) {
    unsigned int terrainKind;
    GridCombatant *combatant;

    if (tile_x < 0) {
        return;
    }
    if (tile_x >= COMBAT_GRID_COLS) {
        return;
    }
    if (tile_y < 0) {
        return;
    }
    if (tile_y >= COMBAT_GRID_ROWS) {
        return;
    }
    terrainKind = combatgrid_tile_terrain_field((unsigned char)tile_x, (unsigned char)tile_y);
    switch (terrainKind) {
    default:
        return;
    case 3:
        if (do_apply == 0) {
            return;
        }
        if (combatgrid_find_cmbt_at_tile((unsigned char)tile_x, (unsigned char)tile_y) != (GridCombatant *)0x0) {
            if (*p_status != 2) {
                *p_status = -1;
                return;
            } else {
                combatgrid_shove_until_unblocked(tile_x, tile_y);
            }
        } else {
            combatgrid_spread_tile_fx_line(tile_x, tile_y);
            combat_actor_play_short_cine((CombatActor *)0x0, (int)p_status);
            combatgrid_line_effect_propagate(tile_x, tile_y);
        }
        *p_status = -1;
        return;
    case 7:
        if (do_apply == 0) {
            return;
        }
        g_nCombatTileEffectPending = 1;
        g_nCombatTileX = tile_x;
        g_nCombatTileY = tile_y;
        if (extra_flag != 0) {
            return;
        }
        *p_status = -1;
        return;
    case 5:
    case 14:
        combatant = combatgrid_find_cmbt_at_tile((unsigned char)tile_x, (unsigned char)tile_y);
        if (combatant->paged_id != 9 && combatant->paged_id != 0x28) {
            return;
        }
        if (combatgrid_tile_terrain((unsigned char)tile_x, (unsigned char)tile_y) != 0) {
            return;
        }
        *p_status = -1;
        return;
    case 2:
        *p_status = -1;
        return;
    }
}

int far combat_actor_trace_proj_path(CombatActor *shooter, CombatActor *target, int flags) {
    CombatActor *hitActor;
    WorldEntity motion_state;
    int tile_x;
    int tile_y;
    int result;

    result = 1;
    motion_state.base.pos.xy.nWorld_x =
        (long)(shooter->inner->grid_x * g_grid_tile_size + (g_grid_tile_size >> 1) + -0x4b0);

    motion_state.base.pos.xy.nWorld_y =
        (long)(shooter->inner->grid_y * g_grid_tile_size + (g_grid_tile_size >> 1) + 0xc80);
    motion_state.base.pos.nWorld_z = 0;
    motion_state.base.orientation.pitch = motion_state.base.orientation.roll = 0;
    motion_state.base.orientation.yaw = world_rndr_actor_angle_actor(shooter, target);
    motion_state.angularVelocity.pitch = motion_state.angularVelocity.roll =
        motion_state.angularVelocity.yaw = 0;
    motion_state.linearVelocity.nX = motion_state.linearVelocity.nY =
        motion_state.linearVelocity.nZ = 0;
    motion_state.forwardVelocity = 300;
    motion_state.base.shapeId = 1;
    tile_x = (motion_state.base.pos.xy.nWorld_x + 0x4b0) / g_grid_tile_size;
    tile_y = (motion_state.base.pos.xy.nWorld_y + -0xc80) / g_grid_tile_size;
    while (tile_x >= 0 && tile_x <= COMBAT_GRID_COLS && tile_y >= 0 && tile_y <= COMBAT_GRID_ROWS) {
        actormotion_integrate(&motion_state);
        tile_x = (motion_state.base.pos.xy.nWorld_x + 0x4b0) / g_grid_tile_size;
        tile_y = (motion_state.base.pos.xy.nWorld_y + -0xc80) / g_grid_tile_size;
        combat_actor_tile_entry_effect(tile_x, tile_y, (int *)&motion_state, 0, flags);
        hitActor = (CombatActor *)combatgrid_tile_terrain((char)tile_x, (char)tile_y);
        if ((hitActor != (CombatActor *)0x0) && ((hitActor->inner->flags & CAF_DEAD) != 0)) {
            hitActor = (CombatActor *)0x0;
        }
        if (((short)motion_state.base.shapeId == -1) ||
            (((hitActor != (CombatActor *)0x0 && (hitActor != target)) && (hitActor != shooter)))) {
            result = 0;
            break;
        }
        if (hitActor == target)
            break;
    }
    return result;
}

static void far combat_actor_grid_rndr_terr_prop(GridCombatant *combatant, int col, int row,
                                                 unsigned int terrain_kind, int skip_viewport_setup) {
    short actor_id;
    unsigned short yaw;

    g_nActorSpriteFlip = 0;
    if (skip_viewport_setup == 0) {
        world_rndr_apply_window_vport();
    }
    switch (terrain_kind) {
    case 5:
        g_wCombatSpinnerYaw += 0xa00;
        world_render_actor_at_tile(combatant->paged_id, col, row, 0, g_wCombatSpinnerYaw, 0);
        return;
    case 3:
    case 4:
    case 14:
        if ((combatant->paged_id == 9) || (combatant->paged_id == 10)) {
            combat_actor_grid_rndr_terr_prop(combatant, col, row, 5, 0);
            return;
        }
        world_render_actor_at_tile(combatant->paged_id, col, row, 0, 0, 0);
        return;
    case 10:
        world_render_actor_at_tile(0xb, col, row, skip_viewport_setup, R3D_DEG(90), 0);
        return;
    case 11:
        world_render_actor_at_tile(0xb, col, row, skip_viewport_setup, R3D_UDEG(270), 0);
        return;
    case 12:
        world_render_actor_at_tile(0xb, col, row, skip_viewport_setup, 0, 0);
        return;
    case 13:
        world_render_actor_at_tile(0xb, col, row, skip_viewport_setup, R3D_UDEG(180), 0);
        return;
    default:
    case 6:
    case 7:
    case 8:
    case 9:
        world_render_actor_swap_textures(combatant->paged_id, col, row);
        return;
    }
}

static void far combat_actor_grid_rndr_tile_feat(int cell_kind, int tile_x, int tile_y) {
    int screen[3];
    short world_x;
    short world_y;
    short saved_ymax;
    unsigned int field4;
    GridCombatant *combatant;

    switch (cell_kind) {
    case 4:
        worldfx_draw_path_segment(tile_x, tile_y);
        break;
    case 5:
    case 6:
        break;
    case 7:
        world_render_actor_at_tile(0xc, tile_x, tile_y, 0, 0, 0);
        break;
    case 8:
        g_nPolygonTextureMode = 1;
        world_render_actor_at_tile(0xd, tile_x, tile_y, 0, 0, 0);
        g_nPolygonTextureMode = 0;
        break;
    case 9:
        world_x = tile_x * g_grid_tile_size + (g_grid_tile_size >> 1) + -0x4b0;
        world_y = tile_y * g_grid_tile_size + (g_grid_tile_size >> 1) + 0xc80;
        project_world_to_screen(world_x, world_y, 0, screen, g_active_window);
        g_graphics_context.bClip_enabled = 1;
        saved_ymax = g_graphics_context.clip.ymax;
        g_graphics_context.clip.ymax = screen[1];
        field4 = combatgrid_tile_field4((unsigned char)tile_x, (unsigned char)tile_y);
        combatant = combatgrid_find_cmbt_at_tile((unsigned char)tile_x, (unsigned char)tile_y);
        if (combatant != (GridCombatant *)0x0) {
            if (combatant->paged_id == 0xb) {
                combat_actor_grid_rndr_terr_prop(combatant, tile_x, tile_y,
                                                 combat_arena_anim_tbl_lookup_2d(tile_x, tile_y),
                                                 -(int)field4);
                g_graphics_context.clip.ymax = saved_ymax;
                return;
            }
            world_render_actor_at_tile(combatant->paged_id, tile_x, tile_y, -(int)field4, 0, 0);
        } else {
            combatant = (GridCombatant *)combatgrid_tile_terrain((char)tile_x, (char)tile_y);
            if (combatant != (GridCombatant *)0x0) {
                combat_actor_apply_render_table((CombatActor *)combatant);
                world_render_actor_at_tile(((CombatActor *)combatant)->inner->class_id, tile_x,
                                           tile_y, -(int)field4, 0, (CombatActor *)combatant);
            }
        }
        g_graphics_context.clip.ymax = saved_ymax;
        break;
    }
    return;
}

void far combat_actor_redraw_at_tile(int tile_x, int tile_y) {
    int i;

    i = 0;
    do {
        if (g_active_combatants[i] != (CombatActor *)0 &&
            g_active_combatants[i]->inner->grid_x == tile_x &&
            g_active_combatants[i]->inner->grid_y == tile_y) {
            combat_actor_rndr_stat_vfx_pre(g_active_combatants[i]);
            combat_actor_apply_render_table(g_active_combatants[i]);
            world_render_actor_at_tile(g_active_combatants[i]->inner->class_id, tile_x, tile_y, 0,
                                       0, g_active_combatants[i]);
            combat_actor_render_status_vfx(g_active_combatants[i]);
            g_nActorSpriteFlip = 0;
        }
        i++;
    } while (i < MAX_ACTIVE_COMBATANTS);
}

void far combat_actor_grid_render(WorldObject *focus_actor) {
    int col;
    int row;
    int focus_col;
    int focus_row;
    unsigned int terrain_kind;
    GridCombatant *combatant;
    CombatActor *actor;

    if (g_bCombatGridLinesEnabled != 0) {
        combatgrid_rndr_engagement_lines();
        combatgrid_draw_terrain_walls();
    }
    if (focus_actor != (WorldObject *)0x0) {
        focus_col = (focus_actor->pos.xy.nWorld_x + 0x4b0) / g_grid_tile_size;
        focus_row = (focus_actor->pos.xy.nWorld_y + -0xc80) / g_grid_tile_size;
        if ((focus_col >= COMBAT_GRID_COLS) || (focus_row >= COMBAT_GRID_ROWS)) {
            world_render_combat_grid_sprite(focus_actor);
        }
    }
    for (row = COMBAT_GRID_ROWS - 1; -1 < row; --row) {
        col = 0;
        do {
            terrain_kind = combatgrid_tile_terrain_field((unsigned char)col, (unsigned char)row);
            if ((terrain_kind != 0) && (g_bCombatGridTerrainFeaturesEnabled != 0)) {
                combat_actor_grid_rndr_tile_feat(terrain_kind, col, row);
            }
            actor = (CombatActor *)combatgrid_tile_terrain((unsigned char)col, (unsigned char)row);
            combatant = combatgrid_find_cmbt_at_tile((unsigned char)col, (unsigned char)row);
            if ((focus_actor != (WorldObject *)0x0) && (focus_col == col) && (focus_row == row)) {
                world_render_combat_grid_sprite(focus_actor);
                if (combat_actor_find_by_id((int)focus_actor->shapeId) == -1) {
                    combat_actor_tile_entry_effect(focus_col, focus_row, (int *)focus_actor, 1, 0);
                }
            }
            if ((combatant != 0) && (g_bCombatGridTerrainFeaturesEnabled != 0) &&
                (terrain_kind != 9)) {
                combat_actor_grid_rndr_terr_prop(combatant, col, row, terrain_kind, 0);
            }
            combat_actor_redraw_at_tile(col, row);
            if (actor != (CombatActor *)0x0) {
                if (actor == g_current_actor) {
                    world_render_actor_at_position(2, col, row);
                }
                if ((actor->inner->flags & CAF_KNOCKBACK) != 0) {
                    g_nActorKnockbackColorIdx = (short)(char)actor->inner->knockback_value;
                }
                combat_actor_rndr_stat_vfx_pre(actor);
                if ((actor->inner->class_id != -1) && (terrain_kind != 9)) {
                    combat_actor_apply_render_table(actor);
                    world_render_actor_at_tile(actor->inner->class_id, col, row, 0, 0, actor);
                }
                combat_actor_render_status_vfx(actor);
                g_nActorSpriteFlip = 0;
                g_nActorKnockbackColorIdx = 0;
            }
            ++col;
        } while (col < COMBAT_GRID_COLS);
    }
    if ((focus_actor != (WorldObject *)0x0) && (focus_row < 0)) {
        world_render_combat_grid_sprite(focus_actor);
    }
    return;
}

void combat_actor_place_all_free(void) {
    int i;

    for (i = 0; i < g_combat_count_A; i++) {
        combat_actor_place_on_free_tile(&g_combat_actors_A[i]);
    }
}

void far combat_actor_refresh_all_stats(void) {
    int i;
    int flags;

    i = 0;
    if (i < g_nCombatActiveCount) {
        do {
            /* flags read through (int)(signed char) so the compiler sign-extends
               the byte (MOV AL;CBW) and TESTs the word, rather than folding to a
               byte-ptr TEST. See combat_arena_actor_poison_tick for the same idiom. */
            if ((((flags = (int)(signed char)g_pCombatActiveActors[i].inner->flags) & CAF_DEAD) ==
                 0) &&
                (((flags = (int)(signed char)g_pCombatActiveActors[i].inner->flags) & CAF_FLEE) ==
                 0)) {
                g_pCombatActiveActors[i].inner->flags |= CAF_READY;
                g_pCombatActiveActors[i].inner->flags &= ~CAF_DEFEND_CMD;
            }
            g_pCombatActiveActors[i].stats[2].base = g_pCombatActiveActors[i].stats[2].max;
            stat_actor_get(&g_pCombatActiveActors[i], 0, 0);
            stat_actor_get(&g_pCombatActiveActors[i], 1, 0);
            stat_actor_get(&g_pCombatActiveActors[i], 2, 0);
            stat_actor_get(&g_pCombatActiveActors[i], 3, 0);
            stat_actor_get(&g_pCombatActiveActors[i], 4, 0);
            stat_actor_get(&g_pCombatActiveActors[i], 5, 0);
            stat_actor_get(&g_pCombatActiveActors[i], 6, 0);
            stat_actor_get(&g_pCombatActiveActors[i], 7, 0);
            /* cached read through (unsigned char) into an int so the compiler
               zero-extends the byte (MOV AH,0) before the compare. */
            if ((flags = (unsigned char)g_pCombatActiveActors[i].stats[2].cached) == 0) {
                g_pCombatActiveActors[i].stats[2].cached = 1;
            }
            i++;
        } while (i < g_nCombatActiveCount);
    }
    cspell_tick_actor_stat_fx();
    cspell_tick_damage_terrain();
    combataiact_party_tick_status();
}

void combat_actor_pick_next(void) {
    CombatActor sentinel;
    unsigned int candSpeed;
    CombatActor *candidate;
    CombatActor *actor;
    int i;
    int n_active_alive;
    int n_other_alive;
    unsigned int bestSpeed;
    int flags;

    /* Every flags test below reads the byte through (int)(signed char) so the
       compiler sign-extends it (MOV AL;CBW) and TESTs the word, rather than
       folding to a byte-ptr TEST. The result is never used beyond the mask;
       flags is a scratch. See combat_arena_actor_poison_tick for the same idiom. */
    if (g_current_actor != 0 &&
        ((flags = (int)(signed char)(g_current_actor)->inner->flags) & CAF_DEAD) == 0) {
        combat_arena_actor_poison_tick(g_current_actor);
        if ((g_current_actor)->cParty_slot != 0 &&
            combatenc_actor_can_act(g_current_actor, 1) != 0) {
            g_acting_actor = g_current_actor;
        }
    }

    n_active_alive = 0;
    for (i = 0; i < g_nCombatActiveCount; i++) {
#ifdef V102CD
        if (((flags = (int)(signed char)g_pCombatActiveActors[i].inner->flags) & CAF_DEAD) == 0 &&
            g_pCombatActiveActors[i].cParty_slot != 0)
            n_active_alive++;
#else
        if (((flags = (int)(signed char)g_pCombatActiveActors[i].inner->flags) & CAF_DEAD) == 0)
            n_active_alive++;
#endif
    }

    n_other_alive = 0;
    for (i = 0; i < g_nCombatOtherCount; i++) {
        if (((flags = (int)(signed char)g_pCombatOtherActors[i].inner->flags) & CAF_DEAD) == 0)
            n_other_alive++;
    }

    if (n_active_alive == 0 || (n_other_alive == 0 && combatgrid_any_terrain_6() == 0)) {
        g_current_actor = 0;
        g_picked_actor = (CombatActor *)0;
        return;
    }

    for (i = 0; i < NUM_ACTOR_STATS; i++) {
        sentinel.stats[i].max = 0;
        sentinel.stats[i].base = 0;
        sentinel.stats[i].cached = 0;
        sentinel.stats[i].frac = 0;
        sentinel.stats[i].perm_mod = 0;
    }
    sentinel.cParty_slot = 0;
    sentinel.stats[0].max = 0;

    for (i = 0; i < NUM_ACTOR_STATS; i++) {
        stat_actor_get(&sentinel, i, 0);
    }

    actor = &sentinel;
    for (i = 0; i < g_nCombatActiveCount; i++) {
        candidate = &g_pCombatActiveActors[i];
        candSpeed = stat_actor_get(candidate, 2, 0);
        if (candSpeed == 0 &&
            ((flags = (int)(signed char)candidate->inner->flags) & CAF_DEAD) == 0 &&
            candidate->cParty_slot != 0) {
            candSpeed = 1;
        }
        bestSpeed = stat_actor_get(actor, 2, 0);
        if (bestSpeed == 0 && ((flags = (int)(signed char)actor->inner->flags) & CAF_DEAD) == 0 &&
            actor->cParty_slot != 0) {
            bestSpeed = 1;
        }
        if ((int)candSpeed >= (int)bestSpeed && combatenc_actor_can_act(candidate, 1) != 0) {
            actor = &g_pCombatActiveActors[i];
        }
    }

    for (i = 0; i < g_nCombatOtherCount; i++) {
        candidate = &g_pCombatOtherActors[i];
        candSpeed = stat_actor_get(candidate, 2, 0);
        if ((candSpeed == 0 &&
             ((flags = (int)(signed char)candidate->inner->flags) & CAF_DEAD) == 0) ||
            candidate->inner->class_id == 0x36) {
            candSpeed = 1;
        }
        bestSpeed = stat_actor_get(actor, 2, 0);
        if (bestSpeed == 0 && ((flags = (int)(signed char)actor->inner->flags) & CAF_DEAD) == 0 &&
            actor->cParty_slot != 0) {
            bestSpeed = 1;
        }
        if ((int)candSpeed >= (int)bestSpeed && combatenc_actor_can_act(candidate, 1) != 0) {
            actor = &g_pCombatOtherActors[i];
        }
    }

    if (&sentinel == actor) {
        actor = (CombatActor *)0;
    }
    g_current_actor = actor;
    if (g_current_actor != 0) {
        (g_current_actor)->inner->flags &= ~CAF_PARRY;
        if (((flags = (int)(signed char)(g_current_actor)->inner->flags) & CAF_DEAD) == 0) {
            g_acting_actor_speed = stat_actor_get(g_current_actor, 2, 0);
            if (g_acting_actor_speed == 0 && (g_current_actor)->cParty_slot != 0)
                g_acting_actor_speed = 1;
        } else {
            g_acting_actor_speed = 0;
        }
    }
}

static void combat_actor_draw_bicolor_button(char *text, int x, int y) {
    int cx;
    int w;

    g_graphics_context.bClip_enabled = 0;
    g_graphics_context.bGfx_fill_enabled = 1;
    g_graphics_context.bGfx_fill_color = g_graphics_context.bGfx_outline_color = 0x38;
    draw_rect_filled(x, y, 0x12, 4);
    g_graphics_context.bGfx_fill_color = g_graphics_context.bGfx_outline_color = 0x1f;
    draw_rect_filled(x, y + 4, 0x12, 4);
    w = font_text_width_ds(text);
    cx = (x + 9) - (w >> 1);
    g_graphics_context.bText_fg_color = 0x6f;
    font_draw_text_ds(text, cx, y);
    g_graphics_context.clip.ymin = y + 4;
    g_graphics_context.clip.xmin = 0;
    g_graphics_context.clip.xmax = 0x140;
    g_graphics_context.clip.ymax = 200;
    g_graphics_context.bClip_enabled = 1;
    g_graphics_context.bText_fg_color = 0x6d;
    font_draw_text_ds(text, cx, y);
    return;
}

void far combat_actor_show_push_prompt(void) {
    int y;

    g_graphics_context.wGfxBlitDstPage = g_graphics_context.wVgaPage2Base;
    blit_sprite_indirect((unsigned short)*g_parch_bmx, 0x49, 0x81, 0);
    g_graphics_context.bText_fg_color = 0;
    y = 0x9a;
    font_draw_text_ds("Object will be pushed.", 0x50, y);
}

static void far combat_actor_path_blocked_msg(void) {
    int y;

    g_graphics_context.wGfxBlitDstPage = g_graphics_context.wVgaPage2Base;
    blit_sprite_indirect((unsigned short)*g_parch_bmx, 0x49, 0x81, 0);
    g_graphics_context.bText_fg_color = 0;
    y = 0x9a;
    font_draw_text_ds("Path is blocked!", 0x50, y);
}

void far combat_actor_path_blocked_anim(void) {
    int i;

    i = 0;
    while (combat_arena_wait_confirm_cancel() == 0 && i < 5) {
        g_graphics_context.wGfxBlitDstPage = g_graphics_context.wVgaPage2Base;
        world_render_with_overlay(MK_FP(0, 0xffff));
        combat_actor_path_blocked_msg();
        screen_frame_present();
        i++;
    }
}

void far combat_actor_draw_stats_panel(CombatActor *actor) {
    char numStr[6];
    unsigned int strength;
    int x;
    int y;

    if (actor != (CombatActor *)0 && !!actor->cParty_slot) {
        g_graphics_context.wGfxBlitDstPage = g_graphics_context.wVgaPage2Base;
        resblit_sprite_frame(g_pHeadsBmxAssetTable[(int)actor->cParty_slot - 1], 0xe, 0x8f, 0);
        blit_sprite_indirect((unsigned short)*g_parch_bmx, 0x49, 0x81, 0);
        g_graphics_context.bText_fg_color = 0;
        y = 0x84;
        x = 0x82 - (font_text_width_ds(actor->name) >> 1);
        font_draw_text_ds(actor->name, x, y);
        y += 0xc;
        itoa(stat_actor_get(actor, 0, 0), numStr, 10);
        font_draw_text_ds("Health:", 0x4e, y);
        font_draw_text_ds(numStr, 0x85, y);
        y += 0xa;
        itoa(stat_actor_get(actor, 1, 0), numStr, 10);
        font_draw_text_ds("Stamina:", 0x4e, y);
        font_draw_text_ds(numStr, 0x85, y);
        y += 0xa;
        itoa(stat_actor_get(actor, 2, 0), numStr, 10);
        font_draw_text_ds("Speed:", 0x4e, y);
        font_draw_text_ds(numStr, 0x85, y);
        y += 0xa;
        strength = stat_actor_get(actor, 3, 0);
        itoa(strength, numStr, 10);
        font_draw_text_ds("Strength:", 0x4e, y);
        font_draw_text_ds(numStr, 0x85, y);
    }
}

int far combat_actor_step_to_tgt_adj(CombatActor *attacker, CombatActor *defender) {
    int candX[4];
    int candY[4];
    int dist[4];
    int i;

    if (combatgrid_actors_ortho_adj(attacker, defender) != 0) {
        return 1;
    }
    dist[0] = combatgrid_chebyshev_distance(attacker->inner->grid_x, attacker->inner->grid_y,
                                            defender->inner->grid_x + 1, defender->inner->grid_y);
    dist[1] = combatgrid_chebyshev_distance(attacker->inner->grid_x, attacker->inner->grid_y,
                                            defender->inner->grid_x - 1, defender->inner->grid_y);
    dist[2] = combatgrid_chebyshev_distance(attacker->inner->grid_x, attacker->inner->grid_y,
                                            defender->inner->grid_x, defender->inner->grid_y + 1);
    dist[3] = combatgrid_chebyshev_distance(attacker->inner->grid_x, attacker->inner->grid_y,
                                            defender->inner->grid_x, defender->inner->grid_y - 1);
    {
        unsigned int best = 0;
        for (i = 1; i < 4; i++) {
            if (dist[i] < dist[best]) {
                best = i;
            }
        }
        switch (best) {
        case 0:
            candX[0] = defender->inner->grid_x + 1;
            candY[0] = (int)defender->inner->grid_y;
            candX[1] = (int)defender->inner->grid_x;
            candY[1] = defender->inner->grid_y + 1;
            candX[2] = (int)defender->inner->grid_x;
            candY[2] = defender->inner->grid_y + -1;
            candX[3] = defender->inner->grid_x + -1;

        LAB_5ce3_2703:
            candY[3] = (int)defender->inner->grid_y;
            break;
        case 1:
            candX[0] = defender->inner->grid_x + -1;
            candY[0] = (int)defender->inner->grid_y;
            candX[1] = (int)defender->inner->grid_x;
            candY[1] = defender->inner->grid_y + -1;
            candX[2] = (int)defender->inner->grid_x;
            candY[2] = defender->inner->grid_y + 1;
            candX[3] = defender->inner->grid_x + 1;
            goto LAB_5ce3_2703;
        case 2:
            candX[0] = (int)defender->inner->grid_x;
            candY[0] = defender->inner->grid_y + 1;
            candX[1] = defender->inner->grid_x + 1;
            candY[1] = (int)defender->inner->grid_y;
            candX[2] = defender->inner->grid_x + -1;
            candY[2] = (int)defender->inner->grid_y;
            candX[3] = (int)defender->inner->grid_x;
            candY[3] = defender->inner->grid_y + -1;
            break;
        case 3:
            candX[0] = (int)defender->inner->grid_x;
            candY[0] = defender->inner->grid_y + -1;
            candX[1] = defender->inner->grid_x + -1;
            candY[1] = (int)defender->inner->grid_y;
            candX[2] = defender->inner->grid_x + 1;
            candY[2] = (int)defender->inner->grid_y;
            candX[3] = (int)defender->inner->grid_x;
            candY[3] = defender->inner->grid_y + 1;
        }
    }
LAB_5ce3_27c4: {
    int result = 0;
    i = 0;
    do {
        if (combatgrid_tile_is_blocked((char)candX[i], (char)candY[i]) == 0) {
            attacker->inner->pad_6[0] = (unsigned char)candX[i];
            attacker->inner->pad_6[1] = (unsigned char)candY[i];
            if (combataipath_actor_walk_path(attacker, 1) != 0) {
                result = 1;
                break;
            }
        }
        i++;
    } while (i < 4);
    return result;
}
}

int far combat_actor_melee_approach(CombatActor *attacker, CombatActor *defender) {
    int distance;

    distance = combatgrid_chebyshev_distance(attacker->inner->grid_x, attacker->inner->grid_y,
                                             defender->inner->grid_x, defender->inner->grid_y);
    if (combatgrid_is_pure_diagonal(attacker, (int)defender->inner->grid_x,
                                    (int)defender->inner->grid_y) != 0) {
        ++distance;
    }
    if (2 <= distance)
        goto pathfind;
done:
    (g_current_actor)->inner->flags &= ~CAF_READY;
    return 1;
pathfind:
    attacker->inner->target = defender;
    if (combat_actor_step_to_tgt_adj(attacker, defender) != 0) {
        g_acting_actor_speed++;
        combataipath_actor_walk_path(attacker, 0);
        goto done;
    }
    return 0;
}

static int __cdecl __far combat_actor_heading_from_dxdy(int dx, int dy) {
    int octant;

    if (dx > 0) {
        if (dy == 0)
            octant = 2;
        else if (dy > 0)
            octant = 3;
        else
            octant = 1;
    } else if (dx < 0) {
        if (dy == 0)
            octant = 6;
        else if (dy > 0)
            octant = 5;
        else
            octant = 7;
    } else if (dy > 0) {
        octant = 4;
    } else if (dy < 0) {
        octant = 0;
    } else {
        octant = -1;
    }
    octant *= 0x1000;
    return octant;
}

int combat_actor_direction_to_cursor(void) {
    int heading;

    if ((g_current_actor->inner->grid_x == g_cursor_tile_x) &&
        (g_current_actor->inner->grid_y == g_cursor_tile_y)) {
        heading = -1;
    } else {
        heading = combat_actor_heading_from_dxdy(g_cursor_tile_x - g_current_actor->inner->grid_x,
                                                 g_cursor_tile_y - g_current_actor->inner->grid_y);
    }
    return heading;
}

int far combat_actor_heading_from_to(CombatActor *from, CombatActor *to) {
    int heading;
    char dx, dy;

    if ((to == (CombatActor *)0x0) || (from == (CombatActor *)0x0)) {
        return -1;
    }
    if (from == to) {
        to = combatenc_find_nearest_actor(from, (int *)0x0);
    }
    dx = to->inner->grid_x - from->inner->grid_x;
    dy = to->inner->grid_y - from->inner->grid_y;
    heading = combat_actor_heading_from_dxdy((int)dx, (int)dy);
    return heading;
}

void far combat_actor_face_cursor(void) {
    int direction;

    direction = combat_actor_direction_to_cursor();
    if (combat_actor_lookup_param_rec(g_current_actor) != direction) {
        if (combat_actor_enc_lookup_field2(g_current_actor) == 7) {
            combat_actor_anim7_field2_var(g_current_actor, direction);
        } else {
            combat_actor_anim0_if_not_dead(g_current_actor, direction);
        }
    }
}

static void far combat_actor_anim_wait_rndr_loop(AnimSlot *rec) {
    while (rec->done_flag == 0) {
        world_render_with_overlay(MK_FP(0, 0xffff));
        screen_frame_present();
    }
}

static void far combat_actor_anim_play(CombatActor *actor, unsigned int sprite_id, int speed_mode,
                                       int dir_arg, int dir_mode, int direction, int wait,
                                       unsigned int loop_count) {
    int swapped;
    int i;
    int facing;

    swapped = 0;
    if (combatenc_is_encounter_actor(actor) != 0) {
        swapped = 1;
        combat_arena_swap_tgt_state();
    }

    i = 0;
    if (i < g_nCombatActiveCount) {
        do {
            if (&g_pCombatActiveActors[i] == actor)
                break;
            i++;
        } while (i < g_nCombatActiveCount);
    }

    if (i == g_nCombatActiveCount)
        return;

    switch (direction) {
    case -1:
        facing = g_pCombatActiveAnimPool[i].facing;
        break;
    case -2:
        facing = (g_pCombatActiveAnimPool[i].facing + 1) % 8;
        break;
    default:
        facing = direction / 0x1000;
        break;
    }

    if (dir_mode == 3)
        facing = facing - facing % 2;

    g_pCombatActiveAnimPool[i].facing = facing;

    if (facing > 4)
        facing = 4 - (facing - 4);

    if (dir_arg > 1) {
        if (dir_mode == 3)
            facing = facing * (dir_arg >> 1);
        else
            facing = facing * dir_arg;
    } else {
        facing = facing >> 1;
    }

    g_pCombatActiveAnimPool[i].sprite_id = sprite_id;
    g_pCombatActiveAnimPool[i].end_frame = dir_arg + facing - 1;

    if (speed_mode != 0) {
        g_pCombatActiveAnimPool[i].current_frame = g_pCombatActiveAnimPool[i].end_frame;
        g_pCombatActiveAnimPool[i].loop_period = 1;
    } else {
        g_pCombatActiveAnimPool[i].loop_period = loop_count;
        g_pCombatActiveAnimPool[i].current_frame = facing;
    }

    g_pCombatActiveAnimPool[i].done_flag = 0;
    g_pCombatActiveAnimPool[i].reverse_flag = 0;

    if (wait != 0)
        combat_actor_anim_wait_rndr_loop(&g_pCombatActiveAnimPool[i]);

    if (swapped != 0)
        combat_arena_swap_tgt_state();
}

void far combat_actor_anim7_field2_var(CombatActor *actor, int direction) {
    if (combat_actor_enc_lookup_field2(actor) == 7) {
        combat_actor_anim_play(actor, 7, 1, 4, 5, direction, 1, 4);
        return;
    }
    combat_actor_anim_play(actor, 7, 0, 4, 5, direction, 1, 4);
    return;
}

void far combat_actor_anim0_if_not_dead(CombatActor *actor, int direction) {
    int v;
    if ((v = (char)actor->inner->flags) & CAF_DEAD) {
        return;
    }
    combat_actor_anim_play(actor, 0, 0, 3, 5, direction, 0, 7);
    return;
}

void combat_actor_anim_rand_phase(CombatActor *actor) {
    int swapped;
    int i;

    swapped = 0;
    if (combatenc_is_encounter_actor(actor)) {
        swapped = 1;
        combat_arena_swap_tgt_state();
    }
    i = 0;
    while (i < g_nCombatActiveCount) {
        if (&g_pCombatActiveActors[i] == actor)
            break;
        i++;
    }
    if (i != g_nCombatActiveCount) {
        g_pCombatActiveAnimPool[i].current_frame =
            g_pCombatActiveAnimPool[i].current_frame + RND(3);
        g_pCombatActiveAnimPool[i].tick_counter = rand();
        if (swapped) {
            combat_arena_swap_tgt_state();
        }
    }
    return;
}

void far combat_actor_play_anim_sprite4(CombatActor *actor, int direction) {
    combat_actor_anim_play(actor, 4, 0, 2, 3, direction, 1, 4);
    return;
}

void far combat_actor_play_anim_sprite3(CombatActor *actor, int direction) {
    combat_actor_anim_play(actor, 3, 0, 4, 3, direction, 1, 4);
    return;
}

void far combat_actor_play_anim_sprite1(CombatActor *actor, int direction) {
    combat_actor_anim_play(actor, 1, 0, 4, 3, direction, 1, 4);
    return;
}

void far combat_actor_anim_spr1_alt(CombatActor *actor, int direction) {
    combat_actor_anim_play(actor, 1, 1, 4, 3, direction, 0, 4);
    return;
}

void far combat_actor_play_ranged_windup(CombatActor *actor, int direction) {
    combat_actor_anim_play(actor, 8, 0, 2, 5, direction, 1, 4);
    combat_actor_anim_play(actor, 8, 1, 2, 5, direction, 1, 4);
    return;
}

void far combat_actor_play_melee_swing(CombatActor *actor, int direction) {
    combat_actor_anim_play(actor, 9, 0, 2, 3, direction, 1, 4);
    combat_actor_anim_play(actor, 9, 1, 2, 3, direction, 1, 4);
    return;
}

void combat_actor_anim_mark_dirty(CombatActor *actor, int frame) {
    int encounter = 0;
    int i;

    combat_actor_anim_play(actor, 1, 0, 4, 3, frame, 0, 1);
    if (combatenc_is_encounter_actor(actor)) {
        encounter = 1;
        combat_arena_swap_tgt_state();
    }
    i = 0;
    while (i < g_nCombatActiveCount) {
        if (&g_pCombatActiveActors[i] == actor)
            break;
        i++;
    }
    if (i != g_nCombatActiveCount) {
        g_pCombatActiveAnimPool[i].done_flag = 1;
        g_pCombatActiveAnimPool[i].end_frame = g_pCombatActiveAnimPool[i].current_frame;
        if (encounter != 0) {
            combat_arena_swap_tgt_state();
        }
    }
    return;
}

void far combat_actor_play_anim_sprite5(CombatActor *actor, int frame) {
    combat_actor_anim_play(actor, 5, 1, 1, 3, frame, 0, 4);
    return;
}

void far combat_actor_play_anim_sprite6(CombatActor *actor, int frame) {
    combat_actor_anim_play(actor, 6, 1, 1, 3, frame, 0, 4);
    return;
}

int far combat_actor_enc_lookup_field2(CombatActor *actor) {
    int swapped;
    int result;
    int i;

    swapped = 0;
    if (combatenc_is_encounter_actor(actor)) {
        swapped = 1;
        combat_arena_swap_tgt_state();
    }
    i = 0;
    while (i < g_nCombatActiveCount) {
        if (&g_pCombatActiveActors[i] == actor)
            break;
        i++;
    }
    if (i == g_nCombatActiveCount) {
        return -1;
    }
    result = g_pCombatActiveAnimPool[i].sprite_id;
    if (swapped) {
        combat_arena_swap_tgt_state();
    }
    return result;
}

int far combat_actor_lookup_param_rec(CombatActor *actor) {
    int swapped;
    int result;
    int i;

    swapped = 0;
    if (combatenc_is_encounter_actor(actor)) {
        swapped = 1;
        combat_arena_swap_tgt_state();
    }
    i = 0;
    while (i < g_nCombatActiveCount) {
        if (&g_pCombatActiveActors[i] == actor)
            break;
        i++;
    }
    if (i == g_nCombatActiveCount) {
        return -1;
    }
    result = g_pCombatActiveAnimPool[i].facing << 0xc;
    if (swapped) {
        combat_arena_swap_tgt_state();
    }
    return result;
}

void far combat_actor_debug_restore_stats(void) {
    int i;

    if (key_is_down(0x2a) || key_is_down(0x36)) {
        i = 0;
        while (i < g_combat_count_A) {
            g_combat_actors_A[i].stats[0].base = g_combat_actors_A[i].stats[0].max;
            stat_actor_get(&g_combat_actors_A[i], 0, 0);
            i++;
        }
    } else {
        i = 0;
        while (i < g_combat_count_B) {
            g_combat_actors_B[i].stats[0].base = g_combat_actors_B[i].stats[0].max;
            stat_actor_get(&g_combat_actors_B[i], 0, 0);
            i++;
        }
    }
}

void far combat_actor_kill_remaining_enc(void) {
    int i;
    int flags;

    /* The flags test reads the byte through (int)(signed char) so the compiler
       sign-extends it (MOV AL;CBW) and TESTs the word, rather than folding to a
       byte-ptr TEST. The result is never used beyond the mask; flags is a
       scratch. See combat_arena_actor_poison_tick for the same idiom. */
    for (i = 0; i < g_combat_count_A; i = i + 1) {
        if (((flags = (int)(signed char)(g_combat_actors_A[i].inner)->flags) & CAF_DEAD) == 0) {
            combat_arena_actor_die(&g_combat_actors_A[i], 0);
        }
    }
    g_gameState.bCombatExitRequest = 2;
    return;
}

void far combat_actor_kill_remaining(void) {
    int i;
    int flags;

    /* The flags test reads the byte through (int)(signed char) so the compiler
       sign-extends it (MOV AL;CBW) and TESTs the word, rather than folding to a
       byte-ptr TEST. The result is never used beyond the mask; flags is a
       scratch. See combat_arena_actor_poison_tick for the same idiom. */
    for (i = 0; i < g_combat_count_B; i = i + 1) {
        if (((flags = (int)(signed char)(g_combat_actors_B[i].inner)->flags) & CAF_DEAD) == 0) {
            combat_arena_actor_die(&g_combat_actors_B[i], 1);
        }
    }
    return;
}
