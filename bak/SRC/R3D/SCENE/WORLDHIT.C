#include <dos.h>

#include "structs.h"
#ifdef V102CD
#define g_szVersionString g_szVersionString_decl13
#endif
#include "globals.h"
#include "SRC/WORLD/ZONE/ZONE.H"
#include "SRC/SCREENS/MAINMENU.H"
#include "SRC/WORLD/LOOP/MAP.H"
#include "SRC/COMBAT/ENC/CBENC.H"
#include "SRC/WORLD/CURSOR/WCURSOR.H"
#include "SRC/WORLD/ZONE/CZONE.H"
#include "SRC/WORLD/ZONE/PROXIM.H"
#include "SRC/UI/UIWIDGET.H"
#include "SRC/INPUT/TIMER.H"
#ifdef V102CD
#undef g_szVersionString
extern char g_szVersionString[16];
#endif
#include "r3d.h"
#include "SRC/R3D/SCENE/WORLDHIT.H"
#include "SRC/SYS/RAND.H"
#include "SRC/AUDIO/ENGINE/AUDIO.H"
#include "SRC/AUDIO/RES/AUDRESIN.H"
#include "SRC/GFX/SPRITE/RESBLIT.H"
#include "SRC/R3D/CORE/DISTDIR.H"
#include "SRC/GFX/RASTER/CIRCLE.H"
#include "SRC/GFX/SPRITE/RECTSPR.H"
#include "SRC/GFX/SPRITE/STRBLIT.H"
#include "SRC/GFX/RASTER/PRESENT.H"
#include "SRC/STREAM/RESLOAD/IMGLOAD.H"
#include "SRC/R3D/SPRITE/WORLDRND.H"
#include "SRC/R3D/CORE/R3D.H"
#include "SRC/R3D/ACTOR/ACTMOTN.H"
#include "SRC/R3D/ACTOR/ACTRENDR.H"
#include "SRC/GFX/SCREEN/SCREEN.H"
#include "SRC/R3D/PROJECT/PROJECT.H"
#include "SRC/COMBAT/GRID/CMBTGRID.H"
#include "SRC/R3D/TBLSTORE/SHAPETBL.H"
#include "SRC/R3D/VIS/VISLIST.H"
#include "SRC/R3D/VIS/PROXSCAN.H"
#include "SRC/R3D/SCENE/WORLDFRM.H"
#include "SRC/R3D/SKY/SKYREND.H"
#include "SRC/COMBAT/ACTOR/CACTOR.H"
#include "SRC/COMBAT/ARENA/COMBAT.H"
#include "SRC/WORLD/ENC/RGNENC.H"
#include "SRC/R3D/VIS/VISENTRY.H"
#include "SRC/R3D/ACTOR/ACTSHAKE.H"
#include "SRC/R3D/ACTOR/ACTOROVL.H"
#include "defines.h"
#ifdef V102CD
#include "SRC/GFX/SPRITE/SPRTHNKS.H"
#include "SRC/GAME/CFGPARSE.H"
#endif

short g_nPolygonTextureMode = 1;
unsigned short g_nWorldRenderJitter = 0x0000;
char *g_pszCombatModalTitle = (char *)g_szVersionString;

unsigned char _dgroup_gap_3e8[4] = {0, 0, 0, 0};
SoundDriverId g_sound_driver = SNDDRV_NONE;
BakFile *g_pSfxArchiveStream = {0};
unsigned int _ovrbuffer = 0x0d48;
unsigned char far *g_pMainScratchBuf = {0};
#ifdef V102CD
char g_szVersionString[16] = "Version 1.02 CD";
#else
char g_szVersionString[13] = "Version 1.00";

unsigned char _dgroup_pad_403 = 0;
#endif
unsigned short g_wSkyColorR = 0x00d7;
unsigned short g_wSkyColorG = 0x00e4;
unsigned short g_wSkyColorB = 0x00a8;
ImageRecord **g_pMapIconsTable = {0};
unsigned char g_abActorAnimTemplateDefault[10] = {0xff, 0xff, 0xff, 0xff, 0xff,
                                                  0xff, 0xff, 0xff, 0xff, 0xff};
unsigned char g_abActorAnimTemplateRanged[10] = {0x0c, 0xff, 0xff, 0xff, 0xff,
                                                 0xff, 0xff, 0xff, 0xff, 0xff};

void world_render_scene_dispatch(int animate) {
#ifdef V102CD
    short saved_heading;
    if (animate != 0) {
        rgnenc_corpse_tbl_iterate_22byte();
    }
    if (g_full_redraw_needed != 0) {
        saved_heading = g_world_camera->base.orientation.yaw;
        if (g_cfgNonRotatingMap) {
            g_world_camera->base.orientation.yaw = 0;
        }
        switch (g_game_mode) {
        case 0:
            world_render_frame_full();
            break;
        case 1:
            world_render_frame_full();
            break;
        case 2:
            worldframe_render_chapter_full();
            break;
        }
        g_world_camera->base.orientation.yaw = saved_heading;
        if (g_cfgNonRotatingMap) {
            if (g_pMapIconsTable != 0) {
                ((BlitSpriteFn)blit_sprite)(
                    (int)g_pMapIconsTable[((unsigned)(saved_heading + 0x800)) >> 12],
                    g_world_widget->viewport.x + (g_world_widget->viewport.width >> 1) - 4,
                    g_world_widget->viewport.y + (g_world_widget->viewport.height >> 1) - 3);
            }
        } else {
            if (g_pMapIconsTable != 0) {
                blit_image_scaled_centered(
                    *g_pMapIconsTable,
                    g_world_widget->viewport.x + (g_world_widget->viewport.width >> 1),
                    g_world_widget->viewport.y + (g_world_widget->viewport.height >> 1), 0x4000000);
            }
        }
    } else {
        switch (g_game_mode) {
        case 0:
            world_render_frame(animate);
            break;
        case 1:
            world_render_frame(animate);
            break;
        case 2:
            worldframe_render_chapter(animate);
            break;
        }
    }
    g_polyRasterState.nRemapTableOff = 0;
#else
    if (animate != 0) {
        rgnenc_corpse_tbl_iterate_22byte();
    }
    if (g_full_redraw_needed != 0) {
        switch (g_game_mode) {
        case 0:
            world_render_frame_full();
            break;
        case 1:
            world_render_frame_full();
            break;
        case 2:
            worldframe_render_chapter_full();
            break;
        }
    } else {
        switch (g_game_mode) {
        case 0:
            world_render_frame(animate);
            break;
        case 1:
            world_render_frame(animate);
            break;
        case 2:
            worldframe_render_chapter(animate);
            break;
        }
    }
    g_polyRasterState.nRemapTableOff = 0;
#endif
}

void far world_render_frame(int animate) {
    WorldObject far *pVis;
    unsigned short *pOff;
    int i;

    pOff = g_pwVisibleEntryOffsets;
    r3d_camera_setup_view(g_world_widget);
    g_graphics_context.wGfxBlitDstPage = g_graphics_context.wGfxBlitSrcPage =
        g_graphics_context.wVgaPage2Base;
    skyrender_sky_and_ground(g_wSkyColorR, g_wSkyColorG, g_wSkyColorB, g_camViewAngles.yaw,
                             g_camViewAngles.pitch);
    proxscan_full(g_world_widget);
    vislist_sort(g_wVisibleEntrySegment, g_pwVisibleEntryOffsets, g_pVisibleEntryDistances,
                 g_nVisibleEntryCount);
    for (i = 0; i < g_nVisibleEntryCount; i++, pOff++) {
        unsigned char bKind;
        pVis = MK_FP(g_wVisibleEntrySegment, *pOff);
        bKind = ts_get_shape(pVis->shapeId)->kind;
        if (pVis->shapeId == g_nProximityTableCount) {
            rgnenc_render_object(pVis, animate);
        } else if (bKind == 6) {
            actoroverlay_render_actor(pVis);
        } else if (bKind == 0x24) {
            visentry_render_actor_tmp_anim(pVis);
        } else if (bKind == 9) {
            render_actor_with_shake(pVis);
        } else {
            actorrender_entity(pVis);
        }
        if (i & 1) {
            screen_cur_refr_during_long_op();
        }
    }
}

void world_render_sky_texture_load(void) {
    g_pMapIconsTable = resblit_load_asset_table("mapicons.bmp", 0);
    return;
}

void world_render_sky_texture_free(void) {
    free_image_record(g_pMapIconsTable);
    return;
}

void world_render_frame_full(void) {
    unsigned short *pOff;
    WorldObject entry;
    WorldObject far *pVis;
    WorldObject far *pEntry;
    int i;

    pEntry = &entry;
    pOff = g_pwVisibleEntryOffsets;
    g_nPolygonTextureMode = 0;
    r3d_camera_setup_view(g_world_widget);
    g_graphics_context.wGfxBlitDstPage = g_graphics_context.wGfxBlitSrcPage =
        g_graphics_context.wVgaPage2Base;
    g_graphics_context.bGfx_fill_enabled = 1;
    g_graphics_context.bGfx_outline_color = g_graphics_context.bGfx_fill_color = g_wSkyColorG;
    g_graphics_context.bGfx_dither_color = g_wSkyColorB;
    draw_rect_filled(g_world_widget->viewport.x, g_world_widget->viewport.y,
                     g_world_widget->viewport.width, g_world_widget->viewport.height);
    g_graphics_context.bGfx_dither_color = 0;
    proxscan_all_zones_for_encounter(g_world_widget);
    vislist_sort(g_wVisibleEntrySegment, g_pwVisibleEntryOffsets, g_pVisibleEntryDistances,
                 g_nVisibleEntryCount);

    entry.shapeId = 0xb5;
    entry.pos.nWorld_z = 0;
    entry.orientation.pitch = entry.orientation.roll = entry.orientation.yaw = 0;
    entry.state.stateBits = 0;
    for (i = 0; i < g_nOpenZoneTileCount; i++) {
        entry.pos.xy.nWorld_x = g_abOpenZoneTileX[i] * 64000L + 32000;
        entry.pos.xy.nWorld_y = g_abOpenZoneTileY[i] * 64000L + 32000;
        actorrender_entity(pEntry);
        if (i & 1) {
            screen_cur_refr_during_long_op();
        }
    }
    for (i = 0; i < g_nVisibleEntryCount; i++, pOff++) {
        pVis = MK_FP(g_wVisibleEntrySegment, *pOff);
        actorrender_entity(pVis);
        if (i & 1) {
            screen_cur_refr_during_long_op();
        }
    }

    g_nPolygonTextureMode = 1;
#ifndef V102CD
    if (g_pMapIconsTable != 0) {
        blit_image_scaled_centered(
            *g_pMapIconsTable, g_world_widget->viewport.x + (g_world_widget->viewport.width >> 1),
            g_world_widget->viewport.y + (g_world_widget->viewport.height >> 1), 0x4000000);
    }
#endif
}

void world_render_tick_objects(void) {
    switch (g_game_mode) {
    case 0:
        world_render_frame_with_hittest();
        break;
    case 1:
        world_render_frame_with_hittest();
        break;
    case 2:
        worldframe_chapter_tick_objects();
        break;
    }
}

void far world_render_frame_with_hittest(void) {
    unsigned int i;
    int screenShift;
    int iX, iY;
    long *dist;
    unsigned int kind;
    WorldObject far *pVis;
    unsigned short *pOff;

    pOff = g_pwVisibleEntryOffsets;
    dist = g_pVisibleEntryDistances;
    g_nHitTestEntryCount = 0;
    g_nHitTestWriteSlot = 0;
    screenShift = g_world_widget->zoom;

    r3d_camera_setup_view(g_world_widget);
    g_graphics_context.wGfxBlitDstPage = g_graphics_context.wGfxBlitSrcPage =
        g_graphics_context.wVgaPage2Base;
    skyrender_sky_and_ground(g_wSkyColorR, g_wSkyColorG, g_wSkyColorB, g_camViewAngles.yaw,
                             g_camViewAngles.pitch);
    proxscan_full(g_world_widget);
    vislist_sort(g_wVisibleEntrySegment, g_pwVisibleEntryOffsets, g_pVisibleEntryDistances,
                 g_nVisibleEntryCount);

    for (i = 0; (int)i < g_nVisibleEntryCount; i++, pOff++, dist++) {
        pVis = MK_FP(g_wVisibleEntrySegment, *pOff);
        kind = ts_get_shape(pVis->shapeId)->kind;
        g_nBillboardScrX = -1;

        if (pVis->shapeId == g_nProximityTableCount) {
            rgnenc_render_object(pVis, 0);
        } else if (kind == 6) {
            actoroverlay_render_actor(pVis);
        } else if (kind == 0x24) {
            visentry_render_actor_tmp_anim(pVis);
        } else if (kind == 9) {
            render_actor_with_shake(pVis);
        } else {
            actorrender_entity(pVis);
        }

        if (i & 1) {
            screen_cur_refr_during_long_op();
        }

        if (pVis->shapeId == g_nProximityTableCount) {
            kind = 0x10;
        }

        if (*dist <= g_anEntityKindRenderDist[kind]) {
            switch (kind) {

            case 6:
            case 9:
            case 10:
            case 15:
            case 18:
            case 20:
            case 23:
            case 24:
            case 36:
            case 39: {
                Mat3x3 mat;
                int in[3];
                int out[3];

                mat = g_mat3x3ViewRot;
                in[0] = pVis->pos.xy.nWorld_x - g_world_camera->base.pos.xy.nWorld_x;
                in[1] = pVis->pos.xy.nWorld_y - g_world_camera->base.pos.xy.nWorld_y;
                in[2] = pVis->pos.nWorld_z - g_world_camera->base.pos.nWorld_z;
                r3d_mat3_xform_vec3_wrap(in, &mat, out);
                if ((1 << screenShift) <= out[1]) {

                    int nScale;

                    iX = g_nViewportCenterX + (int)(((long)out[0] << screenShift) / (long)out[1]);
                    iY = g_nViewportCenterY - (int)(((long)out[2] << screenShift) / (long)out[1]);
                    nScale = g_wActorProjScale;

                    g_pWorldHitTestTable[g_nHitTestWriteSlot].pEntity = pVis;
                    g_pWorldHitTestTable[g_nHitTestWriteSlot].dwDist = *dist;
                    g_pWorldHitTestTable[g_nHitTestWriteSlot].rect.x = iX - nScale;
                    g_pWorldHitTestTable[g_nHitTestWriteSlot].rect.y = iY - nScale;
                    g_pWorldHitTestTable[g_nHitTestWriteSlot].rect.width = nScale << 1;
                    g_pWorldHitTestTable[g_nHitTestWriteSlot].rect.height = nScale << 1;

                    g_nHitTestWriteSlot++;
                    g_nHitTestWriteSlot = (int)g_nHitTestWriteSlot % 10;

                    if ((int)g_nHitTestEntryCount < 10)
                        g_nHitTestEntryCount++;
                    break;
                }
                break;
            }

            case 12:
            case 13:
            case 16:
            case 17:
            case 19:
            case 25:
            case 26:
            case 27:
            case 28:
            case 29:
            case 30:
            case 31:
            case 33:
            case 34:
            case 35:
            case 37:
            case 41:
            case 42:
                if (g_nBillboardScrX != -1) {
                    g_pWorldHitTestTable[g_nHitTestWriteSlot].pEntity = pVis;
                    g_pWorldHitTestTable[g_nHitTestWriteSlot].dwDist = *dist;
                    g_pWorldHitTestTable[g_nHitTestWriteSlot].rect.x = g_nBillboardScrX;
                    g_pWorldHitTestTable[g_nHitTestWriteSlot].rect.y = g_nBillboardScrY;
                    g_pWorldHitTestTable[g_nHitTestWriteSlot].rect.width = g_nBillboardW;
                    g_pWorldHitTestTable[g_nHitTestWriteSlot].rect.height = g_nBillboardH;

                    g_nHitTestWriteSlot++;
                    g_nHitTestWriteSlot = (int)g_nHitTestWriteSlot % 10;
                    if ((int)g_nHitTestEntryCount < 10)
                        g_nHitTestEntryCount++;
                }
            }
        }
    }
}

void world_rndr_apply_window_vport(void) {
    g_graphics_context.clip.xmin = g_active_window->viewport.x;
    g_graphics_context.clip.ymin = g_active_window->viewport.y;
    g_graphics_context.clip.xmax =
        g_graphics_context.clip.xmin + g_active_window->viewport.width - 1;
    g_graphics_context.clip.ymax =
        g_graphics_context.clip.ymin + g_active_window->viewport.height - 1;
    g_graphics_context.bClip_enabled = 1;
}

void far world_render_actor_at_position(int actor_kind, int grid_x, int grid_y) {
    WorldObject entry;
    unsigned char animState[2];

    g_nPolygonTextureMode = 0;
    world_rndr_apply_window_vport();
    animState[0] = (unsigned char)actor_kind;
    entry.shapeId = 0;
    entry.orientation.pitch = entry.orientation.roll = entry.orientation.yaw = 0;
    entry.state.stateBits = (unsigned short)animState;
    if (grid_x == -1) {
        if (screen_cursor_get_y() > 0x8c) {
            entry.pos.xy.nWorld_y = 0;
        } else {
            project_cursor_to_world_tile(&entry.pos.xy.nWorld_x);
        }
    } else {
        entry.pos.xy.nWorld_x =
            (long)(grid_x * g_grid_tile_size + (g_grid_tile_size >> 1) + (-0x4b0));

        entry.pos.xy.nWorld_y = (long)(grid_y * g_grid_tile_size + (g_grid_tile_size >> 1) + 0xc80);
        entry.pos.nWorld_z = 0;
    }
    if (entry.pos.xy.nWorld_y != 0) {
        actorrender_entity(&entry);
    }
}

typedef struct {
    unsigned char b[10];
} ActorAnimBuf;

void far world_render_actor_at_tile(int actor_id, int tile_x, int tile_y, int z, unsigned int yaw,
                                    CombatActor *override_actor) {
    ActorAnimBuf animBuf;
    Shape far *pShape;
    WorldObject entry;

    animBuf = *(ActorAnimBuf far *)MK_FP(FP_SEG(g_pMapIconsTable),
                                         (unsigned)g_abActorAnimTemplateDefault);
    pShape = ts_get_shape(actor_id);
    entry.shapeId = actor_id;
    entry.orientation.pitch = entry.orientation.roll = 0;
    entry.orientation.yaw = yaw;
    entry.state.stateBits = (unsigned short)animBuf.b;
    entry.pos.xy.nWorld_x = (long)(tile_x * g_grid_tile_size + (g_grid_tile_size >> 1) + (-0x4b0));
    entry.pos.xy.nWorld_y = (long)(tile_y * g_grid_tile_size + (g_grid_tile_size >> 1) + 0xc80);
    entry.pos.nWorld_z = z;
    if (override_actor != 0 && override_actor->inner->class_id != -1) {
        combat_actor_anim_step(animBuf.b, override_actor);
    }
    if (pShape->kind != 0) {
        worldrender_table_swap(0, g_combat_sprites);
    }
    actorrender_entity(&entry);
}

void far world_render_actor_swap_textures(int actor_id, int nGrid_x, int nGrid_y) {
    ImageRecord **pSavedTable;
    WorldObject entry;

    worldrender_swap_record_table(0, 1);
    pSavedTable = worldrender_table_swap(0, g_combat_render_table_prev);
    entry.shapeId = actor_id;
    entry.orientation.pitch = entry.orientation.roll = entry.orientation.yaw = 0;
    entry.state.stateBits = 0;
    entry.pos.xy.nWorld_x = (long)(nGrid_x * g_grid_tile_size + (g_grid_tile_size >> 1) + -0x4b0);
    entry.pos.xy.nWorld_y = (long)(nGrid_y * g_grid_tile_size + (g_grid_tile_size >> 1) + 0xc80);
    entry.pos.nWorld_z = 0;
    actorrender_entity(&entry);
    worldrender_swap_record_table(0, 1);
    worldrender_table_swap(0, pSavedTable);
}

void far world_render_with_overlay(void far *overlay_target) {
    g_bTexturedPolyEnabled = 1;
    combatgrid_cur_tile_world();
    g_nFrameTickCountdown = 0xe;
    g_nPolygonTextureMode = 0;
    g_graphics_context.wGfxBlitDstPage = g_graphics_context.wVgaPage2Base;
    g_graphics_context.wGfxBlitSrcPage = g_graphics_context.wVgaPage1Base;
    g_graphics_context.bClip_enabled = 0;
    gfx_present_dispatch(g_active_window->viewport.x, g_active_window->viewport.y,
                         g_active_window->viewport.width + -1, g_active_window->viewport.height);
    g_render_camera_scratch->base.pos.xy.nWorld_y = 0;
    g_render_camera_scratch->base.pos.xy.nWorld_x = 0;
    g_render_camera_scratch->base.orientation.yaw = 0;
    g_render_camera_scratch->base.orientation.roll = 0;
    r3d_camera_setup_view(g_active_window);
    world_render_actor_at_position(FP_OFF(overlay_target), g_cursor_tile_x, g_cursor_tile_y);
    combat_actor_grid_render((WorldObject *)FP_SEG(overlay_target));
    combat_arena_tick_status_timers();
    do {
    } while (g_nFrameTickCountdown != 0);
    g_nPolygonTextureMode = 1;
    g_polyRasterState.nRemapTableOff = 0;
    return;
}

void far world_render_view(int force_overlay, int chapter_split) {
    int bKind;
    WorldObject far *pVis;
    int i;

    g_bTexturedPolyEnabled = 1;
    g_graphics_context.wGfxBlitSrcPage = g_graphics_context.wVgaPage2Base;
    g_graphics_context.wGfxBlitDstPage = g_graphics_context.wVgaPage1Base;
    gfx_present_dispatch(0, 0, 0x140, 200);
    g_graphics_context.bClip_enabled = 0;
    g_graphics_context.bGfx_fill_enabled = 1;
    g_graphics_context.bGfx_outline_color = g_graphics_context.bGfx_fill_color = 0;
    draw_rect_filled(g_active_window->viewport.x, g_active_window->viewport.y,
                     g_active_window->viewport.width, g_active_window->viewport.height);

    g_render_camera_scratch->base.pos.xy.nWorld_x = g_world_camera->base.pos.xy.nWorld_x;
    g_render_camera_scratch->base.pos.xy.nWorld_y = g_world_camera->base.pos.xy.nWorld_y;
    if (g_game_mode != 2) {
        g_render_camera_scratch->base.pos.nWorld_z = (long)g_nWorldViewFovNormal;
    } else {
        g_render_camera_scratch->base.pos.nWorld_z = (long)*(short *)&g_nWorldViewFovChapter;
    }
    g_render_camera_scratch->base.orientation.roll = 0;
    g_render_camera_scratch->base.orientation.yaw = g_world_camera->base.orientation.yaw;
    if (g_game_mode != 2) {
        g_render_camera_scratch->base.orientation.pitch = g_nWorldViewYawNormal;
    } else if (chapter_split != 0) {
        g_render_camera_scratch->base.orientation.pitch = R3D_DEG(270);
    } else {
        g_render_camera_scratch->base.orientation.pitch = g_nWorldViewYawChapter;
    }

    r3d_camera_setup_view(g_active_window);
    proxscan_visibility(g_active_window);
    vislist_sort(g_wVisibleEntrySegment, g_pwVisibleEntryOffsets, g_pVisibleEntryDistances,
                 g_nVisibleEntryCount);

    if (force_overlay != 0) {
        g_bForceOverlay = 1;
    }

    for (i = 0; i < g_nVisibleEntryCount; i++) {
        pVis = MK_FP(g_wVisibleEntrySegment, g_pwVisibleEntryOffsets[i]);
        bKind = ts_get_shape(pVis->shapeId)->kind;
        if (!g_engine_prefs->detail_level && bKind == 4) {
            g_nPolygonTextureMode = 0;
        } else {
            g_nPolygonTextureMode = 1;
        }
        actorrender_entity(pVis);
    }

    if (g_encounter_id == 0x221 && g_bForceOverlay == 0) {
        resblit_load_pal_or_stream("fcombat.scx");
    }
    g_bForceOverlay = 0;
    if (g_game_mode == 2) {
        g_render_camera_scratch->base.pos.nWorld_z += 0x1fe;
        g_render_camera_scratch->base.orientation.yaw = 0;
        r3d_camera_setup_view(g_active_window);
    }
}

int far world_rndr_actor_angle_actor(CombatActor *from, CombatActor *to) {
    long dx, dy;
    int result;
    Vec3Long from_pos;
    Vec3Long to_pos;

    from_pos.nX =
        (long)(from->inner->grid_x * g_grid_tile_size + (g_grid_tile_size >> 1) + (-0x4b0));
    from_pos.nY = (long)(from->inner->grid_y * g_grid_tile_size + (g_grid_tile_size >> 1) + 0xc80);
    to_pos.nX = (long)(to->inner->grid_x * g_grid_tile_size + (g_grid_tile_size >> 1) + (-0x4b0));
    to_pos.nY = (long)(to->inner->grid_y * g_grid_tile_size + (g_grid_tile_size >> 1) + 0xc80);
    dx = to_pos.nX - from_pos.nX;
    dy = to_pos.nY - from_pos.nY;
    result = actormotion_atan2_long(dx, dy);
    return result;
}

typedef struct {
    unsigned char b[10];
} AnimBuf10;

#pragma option -O-b
CombatActor *world_rndr_ranged_attack_anim(CombatActor *attacker, CombatActor *target,
                                           int *p_hit_out, unsigned short action_id, int speed,
                                           char anim_override) {
    CombatActor *tgt;
    CombatActor *hit;
    Shape far *pShape;
    int scr[3]; /* projected screen pos; scr[2] never read */
    char animBuf[10];
    long travelDist;
    long dx;
    long dy;
    int tileX;
    int tileY;
    int stepCount;
    int step;
    int deflectAngle;
    int r_local; /* [bp-0x2c] — rand()&1 deflection sign (0 → -1) */
    unsigned int targetIsActionClass;
    int radius;
    int arcDelta;
    int canHitOthers;
    WorldEntity projectile;
    Vec3Long startPos; /* target world position; nZ=250, unused by 2D distance */

    tgt = target;
    hit = 0;

    *(AnimBuf10 *)animBuf =
        *(AnimBuf10 far *)MK_FP(FP_SEG(g_pMapIconsTable), (unsigned)g_abActorAnimTemplateRanged);
    targetIsActionClass = (unsigned int)(tgt->inner->class_id == (short)action_id);

    /* No random deflection once the shot already hit, or when the target has
     * no class record; otherwise deflect the heading by a random ±[0x400,0x700). */
    if (*p_hit_out != 0 || tgt->inner->class_id == -1) {
        deflectAngle = 0;
    } else {
        r_local = RND2(2);
        if (r_local == 0)
            r_local = -1;
        deflectAngle = (int)RNDR(0x400, 0x6ff) * r_local;
    }

    projectile.base.shapeId = (short)action_id;
    if (targetIsActionClass == 0) {
        projectile.base.state.animationState = 0;
    } else {
        projectile.base.state.animationState = (short)(unsigned int)(unsigned char *)animBuf;
        if (anim_override != -1) {
            animBuf[0] = anim_override;
        }
    }
    projectile.base.pos.xy.nWorld_x =
        (long)(attacker->inner->grid_x * g_grid_tile_size + (g_grid_tile_size >> 1) + (-0x4b0));
    projectile.base.pos.xy.nWorld_y =
        (long)(attacker->inner->grid_y * g_grid_tile_size + (g_grid_tile_size >> 1) + 0xc80);
    if ((targetIsActionClass == 0) && (action_id != 4)) {
        projectile.base.pos.nWorld_z = 200;
    } else {
        projectile.base.pos.nWorld_z = 0;
    }
    startPos.nX =
        (long)(tgt->inner->grid_x * g_grid_tile_size + (g_grid_tile_size >> 1) + (-0x4b0));
    startPos.nY = (long)(tgt->inner->grid_y * g_grid_tile_size + (g_grid_tile_size >> 1) + 0xc80);
    startPos.nZ = (long)250; /* z set but never read — the 2D distance below only uses nX/nY */
    projectile.base.orientation.pitch = projectile.base.orientation.roll = 0;
    projectile.base.orientation.yaw =
        (short)world_rndr_actor_angle_actor(attacker, tgt) + (short)deflectAngle;
    if ((action_id == 0x26) || (action_id == 3)) {
        projectile.angularVelocity.roll =
            3000; /* 0xbb8 pitch-delta scalar (3000) stored to struct field */
    } else {
        projectile.angularVelocity.roll = 0;
    }
    projectile.angularVelocity.pitch = projectile.angularVelocity.yaw = 0;
    projectile.linearVelocity.nX = projectile.linearVelocity.nY = projectile.linearVelocity.nZ = 0;
    projectile.forwardVelocity = (short)speed;
    dx = startPos.nX - projectile.base.pos.xy.nWorld_x;
    travelDist =
        distdir_octagonal_distance_dxdy(dx, dy = (startPos.nY - projectile.base.pos.xy.nWorld_y));
    if (*p_hit_out != 0) {
        stepCount = (int)(travelDist / (long)projectile.forwardVelocity);
    } else {
        stepCount = 10000; /* 0x2710 step-count sentinel (10000) */
    }
    pShape = ts_get_shape((int)action_id);
    radius = (int)pShape->radius;
    if (action_id == 0x14) {
        /* 0x190 arc divisor numerator (400) in integer division */
        arcDelta = (stepCount < 10000) ? 400 / (stepCount + 4) : (int)RND(0x14) - 5;
        projectile.base.pos.nWorld_z += 200;
    }
    canHitOthers = (targetIsActionClass == 0) && ((unsigned short)action_id != 5);
    for (step = 0; step < stepCount; step++) {
        if (action_id == 4) {
            if (stepCount >> 2 < step) {
                *(int far *)&pShape->radius = (step * radius) / stepCount;
            } else {
                *(int far *)&pShape->radius = radius >> 2;
            }
            projectile.base.pos.nWorld_z = (long)((int)pShape->radius - radius);
        }
        actormotion_integrate(&projectile);
        if (action_id == 0x14) {
            projectile.base.pos.nWorld_z += arcDelta;
            if (projectile.base.pos.nWorld_z <= 0) {
                arcDelta = -arcDelta;
                projectile.base.pos.nWorld_z = 1;
                audio_play(0x48);
            }
            arcDelta -= 6;
        }
        world_render_with_overlay(MK_FP((unsigned)&projectile, -1));
        screen_frame_present();
        tileX = (projectile.base.pos.xy.nWorld_x + 0x4b0) / g_grid_tile_size;
        tileY = (projectile.base.pos.xy.nWorld_y + (-0xc80)) / g_grid_tile_size;
        hit = (CombatActor *)combatgrid_tile_terrain((char)tileX, (char)tileY);
        if ((hit == attacker) || (hit == tgt) || (canHitOthers == 0) ||
            (hit != 0 && (hit->inner->flags & CAF_DEAD) != 0) || (*p_hit_out != 0)) {
            hit = 0;
        }
        project_world_to_screen((int)projectile.base.pos.xy.nWorld_x,
                                (int)projectile.base.pos.xy.nWorld_y, 0, scr, g_active_window);
        if (scr[0] > 0x140) /* 0x140 screen-X bound (320) */
            break;
        if (scr[0] < 0)
            break;
        if (scr[1] > 0x96)
            break;
        if (scr[1] < 0)
            break;
        if ((short)projectile.base.shapeId == -1)
            break;
        if (hit != 0)
            break;
    }
    if ((short)projectile.base.shapeId == -1) {
        *p_hit_out = 0;
    }
    *(int far *)&pShape->radius = radius;
    if (hit == 0) {
        hit = tgt;
    } else {
        *p_hit_out = 1;
    }
    return hit;
}
#pragma option -Ob

void far world_render_combat_grid_sprite(WorldObject *actor) {
    Shape far *pShape;
    short savedFlip;
    WorldObject entry;
    int actorIdx;

    savedFlip = g_nActorSpriteFlip;
    pShape = ts_get_shape((int)actor->shapeId);
    actorIdx = combat_actor_find_by_id((int)actor->shapeId);

    if ((int)actor->shapeId == 1) {
        entry.shapeId = 0xe;
    } else if (actorIdx == -1) {
        entry.shapeId = 6;

        if ((int)actor->shapeId != 4)
            g_nActorSpriteFlip = RND2(4);
        else
            g_nActorSpriteFlip = RND2(2) << 1;
    }

    if (actorIdx == -1 && (int)actor->shapeId != 4) {

        *(WorldPos far *)&entry.pos = *(WorldPos far *)&actor->pos;
        entry.pos.nWorld_z = 0;
        *(EulerAngles far *)&entry.orientation = *(EulerAngles far *)&actor->orientation;
        entry.state.stateBits = 0;
        actorrender_entity((WorldObject far *)&entry);
        goto after_flip;
    }

    if (actorIdx == -1)
        goto after_flip;

    if (actorIdx < 100) {
        worldrender_table_swap(0, *g_anim_pool_A[actorIdx].sprite_header);
        if (g_anim_pool_A[actorIdx].facing > 4)
            g_nActorSpriteFlip = 2;
        else
            g_nActorSpriteFlip = 0;
    } else {
        worldrender_table_swap(0, *g_anim_pool_B[actorIdx - 100].sprite_header);
        if (g_anim_pool_B[actorIdx - 100].facing > 4)
            g_nActorSpriteFlip = 2;
        else
            g_nActorSpriteFlip = 0;
    }
after_flip:
    if (pShape->kind != 0)
        worldrender_table_swap(0, g_combat_sprites);
    actorrender_entity((WorldObject far *)actor);

    if (actorIdx != -1) {
        if (actorIdx < 100)
            combat_actor_draw_float_damage(&g_combat_actors_A[actorIdx]);
        else
            combat_actor_draw_float_damage(&g_combat_actors_B[actorIdx - 100]);
    }

    g_nActorSpriteFlip = savedFlip;
}

void world_render_record_marker_dot(WorldObject far *entry) {
    int dx;
    int dy;
    long rx;
    long ry;
    int cx;
    int cy;

    dx = (int)(((entry->pos.xy.nWorld_x - g_world_camera->base.pos.xy.nWorld_x) *
                (long)(1 << g_world_widget->zoom)) /
               g_world_camera->base.pos.nWorld_z);
    dy = (int)(((entry->pos.xy.nWorld_y - g_world_camera->base.pos.xy.nWorld_y) *
                (long)(1 << g_world_widget->zoom)) /
               g_world_camera->base.pos.nWorld_z);

    rx = (r3d_imul_full32(dx, r3d_tbl_cos(-g_world_camera->base.orientation.yaw)) -
          r3d_imul_full32(dy, r3d_tbl_sin(-g_world_camera->base.orientation.yaw))) >>
         0xe;
    ry = (r3d_imul_full32(dy, r3d_tbl_cos(-g_world_camera->base.orientation.yaw)) +
          r3d_imul_full32(dx, r3d_tbl_sin(-g_world_camera->base.orientation.yaw))) >>
         0xe;

    cx = g_viewportCenter.x + (int)rx;
    cy = g_viewportCenter.y - (int)ry;

    if (g_graphics_context.clip.xmin + -2 <= cx && cx <= g_graphics_context.clip.xmax + 2 &&
        g_graphics_context.clip.ymin + -2 <= cy && cy <= g_graphics_context.clip.ymax + 2) {
        g_graphics_context.bGfx_fill_enabled = 1;
        g_graphics_context.wGfxBlitDstPage = g_graphics_context.wGfxBlitSrcPage =
            g_graphics_context.wVgaPage2Base;
        g_graphics_context.bGfx_outline_color = g_graphics_context.bGfx_fill_color = 0x6f;
        draw_circle(2, cx, cy);
    }
    return;
}
