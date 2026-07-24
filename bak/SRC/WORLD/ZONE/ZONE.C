#include <stdio.h>
#include "SRC/GAME/GMAIN.H"
#include "SRC/GEN/GFXCTX.H"
#include "structs.h"
#include "SRC/WORLD/ZONE/ZONE.H"
#include "SRC/IO/IO.H"
#include "SRC/IO/IOCHUNK.H"
#include "SRC/SYS/MEM.H"
#include "SRC/AUDIO/ENGINE/AUDIO.H"
#include "SRC/GFX/SPRITE/RESBLIT.H"
#include "SRC/R3D/SCENE/WORLDHIT.H"
#include "SRC/R3D/SPRITE/WORLDRND.H"
#include "SRC/R3D/ACTOR/ACTMOTN.H"
#include "SRC/WORLD/ZONE/PROXIM.H"
#include "SRC/GFX/PALETTE/PALETTE.H"
#include "SRC/R3D/TBLSTORE/SHAPETBL.H"
#include "SRC/SYS/EMSIMG.H"
#include "SRC/R3D/VIS/VISLIST.H"
#include "SRC/R3D/VIS/PROXSCAN.H"
#include "SRC/R3D/SCENE/WORLDFRM.H"
#include "SRC/UI/UIWIDGET.H"
#include "SRC/COMBAT/ARENA/COMBAT.H"
#include "SRC/WORLD/LOOP/WORLDLP.H"
#include "SRC/WORLD/LOOP/MAP.H"
#include "SRC/WORLD/MOVE/WORLDMOV.H"
#include "SRC/WORLD/ZONE/CZONE.H"
#include "SRC/WORLD/ENC/RGNENC.H"
#include "SRC/WORLD/CURSOR/WCURSOR.H"
#include "SRC/R3D/ACTOR/ACTOROVL.H"
#include "gfx169d.h"

short g_game_mode;
WorldEntity *g_world_camera;
ViewContext *g_world_widget;
unsigned char g_bZoneSkyColor;
unsigned char g_bZoneGroundColor;
void *g_pZoneGridData;
short g_nZoneRenderTableCount;
char g_szZoneMapFilename[13];

unsigned short g_wZoneFlags = 0x0000;
char g_szZoneRefFilenameTmpl[11] = "ZzzREF.DAT";

void far zone_subsystem_init(void) {
    IoFile *stream;

    ts_init(3, 10);
    g_world_camera = actormotion_vec_alloc(0);
    g_world_widget = ts_create_fullscreen_view(g_world_camera);
    stream = bak_fopen("zone.dat", "rb");
    bak_fread(&g_world_widget->viewport.x, 2, 1, stream);
    bak_fread(&g_world_widget->viewport.y, 2, 1, stream);
    bak_fread(&g_world_widget->viewport.width, 2, 1, stream);
    bak_fread(&g_world_widget->viewport.height, 2, 1, stream);
    bak_fclose(stream);
    worldmove_dat_load();
    proxscan_filter_table_load();
    rgnenc_chap_shp_init();
}

void far zone_subsystem_shutdown(void) {
    rgnenc_release_sfx_slot_table();
    ts_my_free(g_world_widget);
    actormotion_xzfree(g_world_camera);
    ts_shutdown();
}

void far zone_load(void) {
    IoFile *stream;
    short slot;
    long inset_z;
    ImageRecord **render_table;

    sprintf(g_szZoneMapFilename, "Z%02uDEF.DAT", (unsigned int)g_gameState.nZoneId);
    stream = bak_fopen(g_szZoneMapFilename, "rb");
    bak_fread(&g_game_mode, 2, 1, stream);
    bak_fread(g_world_widget, 2, 1, stream);
    bak_fread(&g_lZoneDefaultZ, 4, 1, stream);
    bak_fread(&g_wZoneDefaultYaw, 2, 1, stream);
    bak_fread(&g_wZoneFlags, 2, 1, stream);
    bak_fread(&g_bZoneSkyColor, 1, 1, stream);
    bak_fread(&g_bZoneGroundColor, 1, 1, stream);
    bak_fread(&g_lWorldZMin, 4, 1, stream);
    bak_fread(&inset_z, 4, 1, stream);
    bak_fread(&g_lWorldZMax, 4, 1, stream);
    bak_fread(&g_lWorldZStep, 4, 1, stream);
    bak_fread(&g_nFogRemapTableCount, 2, 1, stream);
    bak_fread(&g_wSpriteFogBucketWidth, 2, 1, stream);
    bak_fread(&g_lSpriteFogOnsetDist, 4, 1, stream);
    bak_fread(&g_lSpriteFogFarDist, 4, 1, stream);
    bak_fread(&g_nLodBucketWidth, 2, 1, stream);
    bak_fread(&g_dwLodNearThreshold, 4, 1, stream);
    bak_fread(&g_lFarCullDist, 4, 1, stream);
    bak_fclose(stream);
    if (g_game_mode == 2) {
        audio_music_play(0x3ec);
    } else if (g_gameState.nZoneId == '\x06') {

        audio_music_play(0x3fe);
    } else if ((int)g_gameState.nChapter == 8) {

        audio_music_play(0x405);
    } else {
        audio_music_play(-1);
    }
    if (g_gameState.nZoneId != g_gameState.nPrevZoneId) {
        g_gameState.lInsetCameraPosZ = inset_z;
    }
    g_world_camera->base.pos.xy.nWorld_x = g_gameState.zoneDefaultCameraPos.nWorld_x;
    g_world_camera->base.pos.xy.nWorld_y = g_gameState.zoneDefaultCameraPos.nWorld_y;
    if (g_full_redraw_needed != 0) {
        g_world_camera->base.pos.nWorld_z = g_gameState.lInsetCameraPosZ;
        g_lExploreCameraZSaved = g_lZoneDefaultZ;
        g_wExploreCameraYawSaved = g_wZoneDefaultYaw;
    } else {
        g_world_camera->base.pos.nWorld_z = g_lZoneDefaultZ;
        g_world_camera->base.orientation.pitch = g_wZoneDefaultYaw;
    }
    g_world_camera->base.orientation.roll = 0;
    g_world_camera->base.orientation.yaw = g_gameState.wZoneDefaultCameraHeading;
    sprintf(g_szZoneMapFilename, "Z%02u.RMP", (unsigned int)g_gameState.nZoneId);
    stream = bak_fopen(g_szZoneMapFilename, "rb");
    bak_fread_chunked(g_abFogRemapTable, 0x100, (long)(int)g_nFogRemapTableCount, stream);
    bak_fclose(stream);
    combat_arena_load_remap_pals();
    sprintf(g_szZoneMapFilename, "Z%02u.PAL", (unsigned int)g_gameState.nZoneId);
    palette_buffers_alloc(g_szZoneMapFilename);
    uiwidget_compass_load();
    world_render_sky_texture_load();
    if ((g_wZoneFlags & 1) == 0) {
        sprintf(g_szZoneMapFilename, "Z%02uH.BMX", (unsigned int)g_gameState.nZoneId);
        g_pSkyPanoAssetTable = (unsigned short *)resblit_load_asset_table(g_szZoneMapFilename, 1);
    } else {
        g_pSkyPanoAssetTable = (unsigned short *)0x0;
    }
    actoroverlay_image_1ff4_load();
    slot = 0;
    do {
        sprintf(g_szZoneMapFilename, "Z%02uSLOT%d.BMX", (unsigned int)g_gameState.nZoneId, slot);
        render_table = worldrender_table_load(slot, g_szZoneMapFilename);
        if (render_table == 0)
            break;
        slot = slot + 1;
    } while (slot < 7);
    g_nZoneRenderTableCount = slot;
    sprintf(g_szZoneMapFilename, "Z%02u.TBL", (unsigned int)g_gameState.nZoneId);
    ts_load_shape_tbl(0, g_szZoneMapFilename);
    ts_load_shape_tbl(1, "combat.tbl");
    if (g_game_mode == 2) {
        sprintf(g_szZoneMapFilename, "Z%02uM.TBL", (unsigned int)g_gameState.nZoneId);
        ts_load_shape_tbl(2, g_szZoneMapFilename);
    }
    zone_load_scx_image();
    zone_alloc_400byte_buffer();
    zone_map_data_load(g_gameState.nZoneId);
    sprintf(g_szZoneMapFilename, "Z%02u.DAT", (unsigned int)g_gameState.nZoneId);
    map_color_remap_load(g_szZoneMapFilename);
    proxscan_scratch_alloc();
    vislist_alloc();
    wcursor_load_detect_dat();
    if (g_game_mode == 2) {
        worldframe_encounter_table_load();
    }
    zone_load_shape_sprite();
    zone_load_audio_proximity();
    proxscan_full(g_world_widget);
    vislist_sort(g_wVisibleEntrySegment, g_pwVisibleEntryOffsets, g_pVisibleEntryDistances,
                 g_nVisibleEntryCount);
    worldmove_camera_crossing_apply();
    if (g_gameState.nZoneId != g_gameState.nPrevZoneId) {
        worldmove_step_tick_reset();
    } else {
        if (g_gameState.nWorldStepPending != 0) {
            worldloop_step_or_final_movement();
            goto LAB_74fb_04ad;
        }
    }
    worldloop_party_move_done_clr();
LAB_74fb_04ad:
    worldmove_rgn_chap_trans_apply();
    g_gameState.nPrevZoneId = g_gameState.nZoneId;
    return;
}

void far zone_world_scene_teardown(void) {
    int slot;

    zone_scene_runtime_teardown();
    zone_release_object_states();
    if (g_game_mode == 2) {
        worldframe_encounter_table_apply();
    }
    wcursor_free_detect_dat();
    vislist_free();
    proxscan_scratch_free();
    map_color_remap_free();
    zone_free_400byte_buffer();
    if (g_game_mode == 2) {
        ts_free_shape_tbl(2);
    }
    ts_free_shape_tbl(1);
    ts_free_shape_tbl(0);
    for (slot = g_nZoneRenderTableCount - 1; slot >= 0; slot--) {
        worldrender_table_unload(slot);
    }
    actoroverlay_image_1ff4_free();
    if ((g_wZoneFlags & 1) == 0) {
        emsimg_free_paged(g_pSkyPanoAssetTable);
        g_pSkyPanoAssetTable = (unsigned short *)0x0;
    }
    world_render_sky_texture_free();
    uiwidget_compass_free();
    palette_buffers_free();
}

void far zone_combat_camera_set_world_pos(PlayerSpawnRecord *pos) {
    g_world_camera->base.pos.xy.nWorld_x =
        (long)(int)(unsigned int)pos->bTileX * 64000 + (long)(int)(unsigned int)pos->bSubX * 0x640 + 800;
    g_world_camera->base.pos.xy.nWorld_y =
        (long)(int)(unsigned int)pos->bTileY * 64000 + (long)(int)(unsigned int)pos->bSubY * 0x640 + 800;
    if (g_full_redraw_needed == 0) {
        g_world_camera->base.pos.nWorld_z = g_lZoneDefaultZ;
        g_world_camera->base.orientation.pitch = g_wZoneDefaultYaw;
    }
    g_world_camera->base.orientation.roll = 0;
    g_world_camera->base.orientation.yaw = pos->wCameraHeading;
    czone_load_actors(g_gameState.nZoneId, pos->bTileX, pos->bTileY,
                      g_apCombat_zone_actor_lists[0]);
    czone_rebuild_actor_list();
    czone_spell_state_reset_pair();
    czone_region_encounters_load();
    proxscan_full(g_world_widget);
    vislist_sort(g_wVisibleEntrySegment, g_pwVisibleEntryOffsets, g_pVisibleEntryDistances,
                 g_nVisibleEntryCount);
    worldmove_camera_crossing_apply();
    worldloop_party_move_done_clr();
}

void far zone_load_shape_sprite(void) {
    sprintf(g_szZoneMapFilename, "Z%02uSHP.DAT", (unsigned int)g_gameState.nZoneId);
    rgnenc_load_zone_shape_index(g_szZoneMapFilename);
}

void far zone_release_object_states(void) {
    rgnenc_rel_object_state_group();
}

void far zone_load_audio_proximity(void) {
    audio_sfx_register_world_bank();
    sprintf(g_szZoneMapFilename, "Z%02u.TBL", (unsigned int)g_gameState.nZoneId);
    proximity_table_load(g_szZoneMapFilename);
    czone_subsystem_init();
}

void far zone_scene_runtime_teardown(void) {
    czone_cache_evict_lru_slot();
    proximity_table_free();
    audio_sfx_stop_scene_sounds();
}

void far zone_teardown(int free_resources) {
    rgnenc_persist_zone_snapshot();
    zone_scene_runtime_teardown();
    if (free_resources != 0) {
        zone_release_object_states();
    }
}

void far zone_refresh_visible(int reload_shapes) {
    if (reload_shapes != 0) {
        zone_load_shape_sprite();
    }
    zone_load_audio_proximity();
    proxscan_full(g_world_widget);
    vislist_sort(g_wVisibleEntrySegment, g_pwVisibleEntryOffsets, g_pVisibleEntryDistances,
                 g_nVisibleEntryCount);
}

void far zone_alloc_400byte_buffer(void) {

    g_pZoneGridData = galloc_safe_zcalloc(400);
}

void zone_free_400byte_buffer(void) {
    galloc_zfree(g_pZoneGridData);
}

void far zone_map_data_load(unsigned char zone_id) {
    IoFile *stream;

    sprintf(g_szZoneMapFilename, "Z%02uMAP.DAT", (unsigned int)zone_id);
    stream = bak_fopen(g_szZoneMapFilename, "rb");
    bak_fread(g_pZoneGridData, 400, 1, stream);
    bak_fclose(stream);
}

int far zone_grid_bit_get(unsigned char x, unsigned char y) {
    int offset;
    unsigned char mask;

    if (x >= 50 || y >= 50)
        return 0;

    offset = y * 8 + (x >> 3);
    mask = 1 << (x % 8);
    return ((unsigned char *)g_pZoneGridData)[offset] & mask;
}

unsigned char zone_ref_find_pair_index(unsigned char zone, unsigned char key1, unsigned char key2) {
    IoFile *stream;
    unsigned char record_count;
    unsigned char index;
    unsigned char rec_key1;
    unsigned char rec_key2;

    g_szZoneRefFilenameTmpl[1] = 0x30 | zone / 10;
    g_szZoneRefFilenameTmpl[2] = 0x30 | zone % 10;
    stream = bak_fopen(g_szZoneRefFilenameTmpl, "rb");
    bak_fread(&record_count, 1, 1, stream);
    index = 0;
    if (index < record_count) {
        do {
            bak_fread(&rec_key1, 1, 1, stream);
            bak_fread(&rec_key2, 1, 1, stream);
            if ((key1 == rec_key1) && (key2 == rec_key2))
                break;
            index++;
        } while (index < record_count);
    }
    bak_fclose(stream);
    return index;
}

void far zone_set_plr_pos_rec(PlayerSpawnRecord *pRecord) {
    g_gameState.nZoneId = pRecord->bZoneId;
    g_gameState.nPlayerTileX = pRecord->bTileX;
    g_gameState.nPlayerTileY = pRecord->bTileY;
    czone_world_pos_tile_sub_ctr(pRecord->bTileX, pRecord->bTileY, pRecord->bSubX, pRecord->bSubY,
                                 &g_gameState.zoneDefaultCameraPos);
    g_gameState.wZoneDefaultCameraHeading = pRecord->wCameraHeading;
    g_nSkyHorizonRowCached = 0xffff;
}

void far zone_savegame_snap_world_state(void) {
    *(Vec3Long *)&g_gameState.zoneDefaultCameraPos.nWorld_x =
        *(Vec3Long *)&g_world_camera->base.pos.xy.nWorld_x;
    g_gameState.wZoneDefaultCameraHeading = g_world_camera->base.orientation.yaw;
    worldmove_combat_zone_snap_pos();
    czone_save_persist_zone_plr();
    worldframe_enc_tbl_reapply_chap();
}

void far zone_load_scx_image(void) {
    g_graphics_context.wGfxBlitDstPage = g_wVgaScratchPageBase;
    sprintf(g_szZoneMapFilename, "Z%02uL.SCX", (unsigned int)g_gameState.nZoneId);
    resblit_load_pal_or_stream(g_szZoneMapFilename);
}
