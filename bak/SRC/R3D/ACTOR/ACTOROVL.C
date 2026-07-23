#include "globals.h"
#include "SRC/WORLD/ZONE/ZONE.H"
#include "structs.h"
#include "SRC/R3D/ACTOR/ACTOROVL.H"
#include "SRC/GFX/SPRITE/RESBLIT.H"
#include "SRC/R3D/SPRITE/WORLDRND.H"
#include "SRC/R3D/ACTOR/ACTRENDR.H"
#include "SRC/SYS/EMSIMG.H"

unsigned char g_nEncounterMarkerColorIdx = 0xff;
unsigned char _dgroup_encmark_tail_1fd5[9] = {0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff};

unsigned char g_render_actor_wstate_scratch[2] = {0xff, 0xff};
unsigned char _dgroup_wstate_tail_1fe0[8] = {0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff};

unsigned short g_bShakeActorEnabled = 0x0000;

unsigned char g_bShakeJitterX = 0xff;
unsigned char g_bShakeJitterY = 0xff;
unsigned char _dgroup_jitter_tail_1fec[8] = {0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff};

ImageRecord **g_pAssetTable2 = {0};

unsigned char g_bOverlaySpriteIdxScratch = 0xff;
unsigned char _dgroup_overlay_tail_1ff7[9] = {0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff};

void actoroverlay_image_1ff4_load(void) {
    g_pAssetTable2 = resblit_load_asset_table("boom.bmp", 2);
    return;
}

void actoroverlay_image_1ff4_free(void) {
    emsimg_free_paged(g_pAssetTable2);
    g_pAssetTable2 = 0;
    return;
}

void actoroverlay_render_actor(WorldObject far *visible_entry) {
    unsigned short savedRecordId;
    unsigned short savedState;
    ImageRecord **new_table_ptr;

    if (visible_entry->state.stateBits != 0) {
        savedRecordId = visible_entry->shapeId;
        savedState = visible_entry->state.stateBits;
        visible_entry->state.stateBits = 0;
        actorrender_entity(visible_entry);
        if (g_game_mode == 2) {
            visible_entry->shapeId = 0x8e;
        } else {
            visible_entry->shapeId = 0xb6;
        }
        g_bOverlaySpriteIdxScratch = savedState;
        g_bOverlaySpriteIdxScratch--;
        visible_entry->state.stateBits = (unsigned short)&g_bOverlaySpriteIdxScratch;
        new_table_ptr = worldrender_table_swap(0, g_pAssetTable2);
        actorrender_entity(visible_entry);
        worldrender_table_swap(0, new_table_ptr);
        visible_entry->shapeId = savedRecordId;
        visible_entry->state.stateBits = savedState;
    } else {
        actorrender_entity(visible_entry);
    }
    return;
}
