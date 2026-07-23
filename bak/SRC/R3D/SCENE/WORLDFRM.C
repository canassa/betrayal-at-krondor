#include "SRC/GEN/GFXCTX.H"
#include "SRC/WORLD/ZONE/ZONE.H"
#include "SRC/R3D/SCENE/WORLDHIT.H"
#include "SRC/WORLD/CURSOR/WCURSOR.H"
#include "SRC/WORLD/ZONE/CZONE.H"
#include "SRC/WORLD/ZONE/PROXIM.H"
#include "SRC/UI/UIWIDGET.H"
#include "structs.h"
#include "SRC/R3D/SCENE/WORLDFRM.H"
#include "SRC/SYS/MEM.H"
#include "SRC/GFX/SPRITE/RECTSPR.H"
#include "SRC/GFX/SPRITE/STRBLIT.H"
#include "SRC/R3D/SPRITE/WORLDRND.H"
#include "SRC/R3D/CORE/R3D.H"
#include "SRC/R3D/ACTOR/ACTRENDR.H"
#include "SRC/GFX/SCREEN/SCREEN.H"
#include "SRC/R3D/TBLSTORE/SHAPETBL.H"
#include "SRC/SYS/MDACON.H"
#include "SRC/GAME/GSTATE.H"
#include "SRC/R3D/VIS/VISLIST.H"
#include "SRC/R3D/VIS/PROXSCAN.H"
#include "SRC/R3D/SKY/SKYREND.H"
#include "SRC/WORLD/ENC/RGNENC.H"
#include "SRC/WORLD/CURSOR/WORLDDOR.H"
#include "SRC/R3D/ACTOR/ACTOROVL.H"
#include "r3d.h"
#include <dos.h>

EncounterTable *g_pEncounterTable = {0};

void far worldframe_encounter_table_load(void) {
    g_pEncounterTable = galloc_safe_zcalloc(0x668);
    gstate_temp_file_read_at((unsigned char far *)g_pEncounterTable, GAM_ENCOUNTER_TABLE, 0x668);
}

void far worldframe_encounter_table_apply(void) {
    g_wLastTempWriteRecordKind = 1;
    gstate_temp_file_write_at((unsigned char far *)g_pEncounterTable, GAM_ENCOUNTER_TABLE, 0x668);
    galloc_zfree(g_pEncounterTable);
    g_pEncounterTable = 0;
}

void worldframe_enc_tbl_reapply_chap(void) {
    if (g_game_mode == 2 && g_pEncounterTable != 0) {

        g_wLastTempWriteRecordKind = 1;
        gstate_temp_file_write_at((unsigned char far *)g_pEncounterTable, GAM_ENCOUNTER_TABLE,
                                  sizeof(EncounterTable));
    }
}

void worldframe_enc_rec_prox(unsigned char *record, int direction) {
    int i;
    int found;

    for (i = found = 0; i < 0x28; i++) {
        if ((record[0] == g_pEncounterTable->xCoord[i]) &&
            (record[1] == g_pEncounterTable->yCoord[i]) &&
            (record[2] == g_pEncounterTable->zCoord[i])) {
            found = 1;
            break;
        }
    }
    if (!found) {
        i = 0;
        do {
            if ((g_pEncounterTable->xCoord[i] == 0xff) && (g_pEncounterTable->yCoord[i] == 0xff) &&
                (g_pEncounterTable->zCoord[i] == 0xff)) {
                found = 1;
                g_pEncounterTable->xCoord[i] = record[0];
                g_pEncounterTable->yCoord[i] = record[1];
                g_pEncounterTable->zCoord[i] = record[2];
                break;
            }
            i++;
        } while (i < 0x28);
    }
    if (found) {
        g_pEncounterTable->flags[i][direction >> 3] |= (unsigned char)(1 << ((unsigned char)direction & 7));
    }
}

int worldframe_enc_check_visited(unsigned char *pRecord, int bitIndex) {
    int i;

    for (i = 0; i < 40; i++) {
        if (*pRecord == g_pEncounterTable->xCoord[i] &&
            pRecord[1] == g_pEncounterTable->yCoord[i] &&
            pRecord[2] == g_pEncounterTable->zCoord[i]) {
            return (unsigned int)g_pEncounterTable->flags[i][bitIndex >> 3] & 1 << ((unsigned char)bitIndex & 7);
        }
    }
    return 0;
}

static unsigned int far worldframe_compass_classifier(WorldObject far *entry) {
    unsigned int mask;
    int rot;
    int n;

    mask = 0;
    rot = 0;
    n = entry->shapeId;
    if ((int)n >= 0 && (int)n <= 0x13) {
        mask = 10;
    } else if ((int)n >= 0x14 && (int)n <= 0x1d) {
        mask = 2;
    } else if ((int)n >= 0x1e && (int)n <= 0x25) {
        mask = 3;
    } else if ((int)n >= 0x26 && (int)n <= 0x2d) {
        mask = 0xb;
    } else if ((int)n >= 0x5c && (int)n <= 0x65) {
        mask = 10;
    } else if ((int)n >= 0x66 && (int)n <= 0x6f) {
        mask = 10;
    } else if ((int)n >= 0x70 && (int)n <= 0x79) {
        mask = 0xb;
    }
    if (mask != 0) {
        if (entry->orientation.yaw == R3D_DEG(90)) {
            rot = 1;
        } else if (entry->orientation.yaw == R3D_DEG(180)) {
            rot = 2;
        } else if (entry->orientation.yaw == R3D_DEG(270)) {
            rot = 3;
        }
        n = 0;
        while (n < rot) {
            mask <<= 1;
            if ((mask & 0x10) != 0) {
                mask = (mask | 1) & 0xf;
            }
            n = n + 1;
        }
    }
    return mask;
}

void far worldframe_debug_print_compass(WorldObject far *entry) {
    int mask;

    mask = worldframe_compass_classifier(entry);
    mdacon_printf(0x14, 0x11, "ShpNo: %6d", entry->shapeId);
    mdacon_printf(0x14, 0x12, " Rotz: %6d", entry->orientation.yaw);
    mdacon_printf(0x14, 0x13, "North: %s", (mask & 1) ? "WALL" : "    ");
    mdacon_printf(0x14, 0x14, "West : %s", (mask & 2) ? "WALL" : "    ");
    mdacon_printf(0x14, 0x15, "South: %s", (mask & 4) ? "WALL" : "    ");
    mdacon_printf(0x14, 0x16, "East : %s", (mask & 8) ? "WALL" : "    ");
}

void far worldframe_vislist_cull_occl(unsigned short seg, unsigned short *offsets, long *data, int *count) {
    long boundNorth = 0x7fffffff;
    long boundEast = 0x7fffffff;
    long boundSouth = 0;
    long boundWest = 0;
    long refX;
    long refY;
    WorldObject far *pEntry;
    unsigned int mask;
    register int i;

    if (*count >= 2) {
        pEntry = (WorldObject far *)MK_FP(seg, offsets[*count - 1]);
        refX = pEntry->pos.xy.nWorld_x;
        refY = pEntry->pos.xy.nWorld_y;
        mask = worldframe_compass_classifier(pEntry);
        if ((mask & 1) != 0) {
            boundNorth = pEntry->pos.xy.nWorld_y + 1000;
        }
        if ((mask & 4) != 0) {
            boundSouth = pEntry->pos.xy.nWorld_y + -1000;
        }
        if ((mask & 8) != 0) {
            boundEast = pEntry->pos.xy.nWorld_x + 1000;
        }
        if ((mask & 2) != 0) {
            boundWest = pEntry->pos.xy.nWorld_x + -1000;
        }
        for (i = *count - 2; i >= 0; i = i - 1) {
            pEntry = (WorldObject far *)MK_FP(seg, offsets[i]);
            if ((pEntry->pos.xy.nWorld_y == refY) || (pEntry->pos.xy.nWorld_x == refX)) {
                mask = worldframe_compass_classifier(pEntry);
                if (((mask & 1) != 0) &&
                    ((boundNorth == 0x7fffffff && (refY < pEntry->pos.xy.nWorld_y)) &&
                     (pEntry->pos.xy.nWorld_x == refX))) {
                    boundNorth = pEntry->pos.xy.nWorld_y + 1000;
                }
                if ((((mask & 4) != 0) && (boundSouth == 0)) &&
                    ((pEntry->pos.xy.nWorld_y < refY) && (pEntry->pos.xy.nWorld_x == refX))) {
                    boundSouth = pEntry->pos.xy.nWorld_y + -1000;
                }
                if ((((mask & 8) != 0) && (boundEast == 0x7fffffff)) &&
                    ((refX < pEntry->pos.xy.nWorld_x) && (pEntry->pos.xy.nWorld_y == refY))) {
                    boundEast = pEntry->pos.xy.nWorld_x + 1000;
                }
                if (((((mask & 2) != 0) && (boundWest == 0)) && (pEntry->pos.xy.nWorld_x < refX)) &&
                    (pEntry->pos.xy.nWorld_y == refY)) {
                    boundWest = pEntry->pos.xy.nWorld_x + -1000;
                }
                if ((boundEast < pEntry->pos.xy.nWorld_x) ||
                    (pEntry->pos.xy.nWorld_x < boundWest) ||
                    (boundNorth < pEntry->pos.xy.nWorld_y) ||
                    (pEntry->pos.xy.nWorld_y < boundSouth)) {
                    offsets[i] = offsets[*count - 1];
                    data[i] = data[*count - 1];
                    --(*count);
                }
            }
        }
        vislist_sort(seg, offsets, data, *count);
    }
}

void far worldframe_render_chapter_full(void) {
    int zoneIdx;
    int uCount;
    WorldObject far *pEntry;
    int bitIndex;

    g_bTexturedPolyEnabled = 1;
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
    worldrender_swap_record_table(0, 2);
    for (zoneIdx = 0; zoneIdx < g_nCombat_zone_count; zoneIdx++) {
        uCount = g_apCombat_zone_actor_lists[zoneIdx]->wEntry_count;
        pEntry = g_apCombat_zone_actor_lists[zoneIdx]->pEntries;
        for (bitIndex = 0; bitIndex < uCount; bitIndex++, pEntry++) {
            if (worldframe_enc_check_visited((unsigned char *)g_apCombat_zone_actor_lists[zoneIdx],
                                             bitIndex) != 0) {
                if (pEntry->shapeId == 0x5d || pEntry->shapeId == 0x5c) {
                    worlddoor_rndr_enc_mark_actor(pEntry);
                } else {
                    actorrender_entity(pEntry);
                }
                if (bitIndex & 4) {
                    screen_cur_refr_during_long_op();
                }
            }
        }
    }
    worldrender_swap_record_table(0, 2);
    g_nPolygonTextureMode = 1;
#ifndef V102CD
    if (g_pMapIconsTable != 0) {
        blit_image_scaled_centered(
            *g_pMapIconsTable, g_world_widget->viewport.x + (g_world_widget->viewport.width >> 1),
            g_world_widget->viewport.y + (g_world_widget->viewport.height >> 1), 0x4000000);
    }
#endif
    return;
}

void far worldframe_render_chapter(int animate) {
    WorldObject far *pEntry;
    int i;
    unsigned short *slotPtr;

    slotPtr = g_pwVisibleEntryOffsets;
    r3d_camera_setup_view(g_world_widget);
    g_graphics_context.wGfxBlitDstPage = g_graphics_context.wGfxBlitSrcPage =
        g_graphics_context.wVgaPage2Base;
    skyrender_sky_and_ground(g_wSkyColorR, g_wSkyColorG, g_wSkyColorB, g_camViewAngles.yaw,
                             g_camViewAngles.pitch);
    proxscan_full(g_world_widget);
    vislist_sort(g_wVisibleEntrySegment, g_pwVisibleEntryOffsets, g_pVisibleEntryDistances,
                 g_nVisibleEntryCount);
    worldframe_vislist_cull_occl(g_wVisibleEntrySegment, g_pwVisibleEntryOffsets,
                                 g_pVisibleEntryDistances, (int *)&g_nVisibleEntryCount);
    worldframe_vislist_reorder(g_wVisibleEntrySegment, g_pwVisibleEntryOffsets,
                               g_nVisibleEntryCount);
    i = 0;
    while (i < g_nVisibleEntryCount) {
        pEntry = (WorldObject far *)MK_FP(g_wVisibleEntrySegment, *slotPtr);
        if (pEntry->shapeId == g_nProximityTableCount) {
            rgnenc_render_object(pEntry, animate);
        } else if ((int)pEntry->shapeId >= 0x84 && (int)pEntry->shapeId <= 0x88) {
            actoroverlay_render_actor(pEntry);
        } else {
            if ((pEntry->shapeId == 0x5d) || (pEntry->shapeId == 0x5c)) {
                worlddoor_rndr_enc_mark_actor(pEntry);
            } else {
                actorrender_entity(pEntry);
            }
        }
        if (i & 1) {
            screen_cur_refr_during_long_op();
        }
        i++;
        slotPtr++;
    }
    return;
}

void far worldframe_chapter_tick_objects(void) {
    int zoom;
    int screen_x;
    int screen_y;
    WorldObject far *pEntry;
    unsigned short *slot_ptr;
    int in[3];
    int out[3];
    Mat3x3 viewRot;
    register long *plDist;
    register int i;
    unsigned int kind;
    int scale;

    slot_ptr = g_pwVisibleEntryOffsets;
    plDist = g_pVisibleEntryDistances;
    g_nHitTestEntryCount = 0;
    g_nHitTestWriteSlot = 0;
    zoom = g_world_widget->zoom;
    r3d_camera_setup_view(g_world_widget);
    g_graphics_context.wGfxBlitDstPage = g_graphics_context.wGfxBlitSrcPage =
        g_graphics_context.wVgaPage2Base;
    skyrender_sky_and_ground(g_wSkyColorR, g_wSkyColorG, g_wSkyColorB, g_camViewAngles.yaw,
                             g_camViewAngles.pitch);
    proxscan_full(g_world_widget);
    vislist_sort(g_wVisibleEntrySegment, g_pwVisibleEntryOffsets, g_pVisibleEntryDistances,
                 g_nVisibleEntryCount);
    worldframe_vislist_cull_occl(g_wVisibleEntrySegment, g_pwVisibleEntryOffsets,
                                 g_pVisibleEntryDistances, (int *)&g_nVisibleEntryCount);
    worldframe_vislist_reorder(g_wVisibleEntrySegment, g_pwVisibleEntryOffsets,
                               g_nVisibleEntryCount);
    for (i = 0; i < g_nVisibleEntryCount;) {
        pEntry = (WorldObject far *)MK_FP(g_wVisibleEntrySegment, *slot_ptr);
        g_nBillboardScrX = -1;
        if (pEntry->shapeId == g_nProximityTableCount) {
            rgnenc_render_object(pEntry, 0);
        } else if ((int)pEntry->shapeId >= 0x84 && (int)pEntry->shapeId <= 0x88) {
            actoroverlay_render_actor(pEntry);
        } else if ((pEntry->shapeId == 0x5d) || (pEntry->shapeId == 0x5c)) {
            worlddoor_rndr_enc_mark_actor(pEntry);
        } else {
            actorrender_entity(pEntry);
        }
        if (i & 1) {
            screen_cur_refr_during_long_op();
        }
        if (pEntry->shapeId == g_nProximityTableCount) {
            kind = 0x10;
        } else {
            kind = ts_get_shape(pEntry->shapeId)->kind;
        }
        if (*plDist > g_anEntityKindRenderDist[kind]) {
            goto next;
        }
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
        case 39:
            viewRot = g_mat3x3ViewRot;
            in[0] = pEntry->pos.xy.nWorld_x - g_world_camera->base.pos.xy.nWorld_x;
            in[1] = pEntry->pos.xy.nWorld_y - g_world_camera->base.pos.xy.nWorld_y;
            in[2] = pEntry->pos.nWorld_z - g_world_camera->base.pos.nWorld_z;
            r3d_mat3_xform_vec3_wrap(in, &viewRot, out);
            if ((1 << zoom) <= out[1]) {
                screen_x = g_nViewportCenterX + (int)(((long)out[0] << zoom) / out[1]);
                screen_y = g_nViewportCenterY - (int)(((long)out[2] << zoom) / out[1]);
                scale = g_wActorProjScale;
                g_pWorldHitTestTable[g_nHitTestWriteSlot].pEntity = pEntry;
                g_pWorldHitTestTable[g_nHitTestWriteSlot].dwDist = *plDist;
                g_pWorldHitTestTable[g_nHitTestWriteSlot].rect.x = screen_x - scale;
                g_pWorldHitTestTable[g_nHitTestWriteSlot].rect.y = screen_y - scale;
                g_pWorldHitTestTable[g_nHitTestWriteSlot].rect.width = scale * 2;
                g_pWorldHitTestTable[g_nHitTestWriteSlot].rect.height = scale * 2;
                g_nHitTestWriteSlot++;
                g_nHitTestWriteSlot = (short)g_nHitTestWriteSlot % 10;
                if ((short)g_nHitTestEntryCount < 10) {
                    goto commit;
                }
            }
            break;
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
            if (g_nBillboardScrX == -1) {
                goto next;
            }
            g_pWorldHitTestTable[g_nHitTestWriteSlot].pEntity = pEntry;
            g_pWorldHitTestTable[g_nHitTestWriteSlot].dwDist = *plDist;
            g_pWorldHitTestTable[g_nHitTestWriteSlot].rect.x = g_nBillboardScrX;
            g_pWorldHitTestTable[g_nHitTestWriteSlot].rect.y = g_nBillboardScrY;
            g_pWorldHitTestTable[g_nHitTestWriteSlot].rect.width = g_nBillboardW;
            g_pWorldHitTestTable[g_nHitTestWriteSlot].rect.height = g_nBillboardH;
            g_nHitTestWriteSlot++;
            g_nHitTestWriteSlot = (short)g_nHitTestWriteSlot % 10;
            if ((short)g_nHitTestEntryCount < 10) {
            commit:
                g_nHitTestEntryCount++;
            }
            break;
        default:
            break;
        }
    next:
        i++;
        slot_ptr++;
        plDist++;
    }
    return;
}

void far worldframe_vislist_reorder(unsigned short visible_seg, unsigned short *visible_offsets, int count) {
    int outerIdx;
    int innerIdx;
    unsigned short *pOuterSlot;
    unsigned short savedSlot;
    WorldObject far *pOuter;
    WorldObject far *pInner;
    unsigned short *pDst;
    unsigned short *pInnerSlot;
    unsigned int outerKind;
    unsigned int innerKind;
    int i;

    pOuterSlot = &visible_offsets[count - 1];
    outerIdx = count - 1;
    while (outerIdx >= 0) {
        pOuter = (WorldObject far *)MK_FP(visible_seg, *pOuterSlot);
        if (pOuter->shapeId == g_nProximityTableCount) {
            outerKind = 0x10;
        } else {
            outerKind = (unsigned int)ts_get_shape(pOuter->shapeId)->kind;
        }
        switch (outerKind) {
        case 6:
        case 12:
        case 13:
        case 16:
        case 17:
        case 18:
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
            for (pInnerSlot = &visible_offsets[count - 1], innerIdx = count - 1;
                 innerIdx > outerIdx; innerIdx--, pInnerSlot--) {
                pInner = (WorldObject far *)MK_FP(visible_seg, *pInnerSlot);
                if (pInner->shapeId == g_nProximityTableCount) {
                    innerKind = 0x10;
                } else {
                    innerKind = (unsigned int)ts_get_shape(pInner->shapeId)->kind;
                }
                if ((((innerKind != 0xe) && (innerKind != 0xf)) && (innerKind != 0x14) &&
                     (innerKind != 0x17)) ||
                    (((pOuter->pos.xy.nWorld_x < pInner->pos.xy.nWorld_x + -0x4b0 ||
                       pOuter->pos.xy.nWorld_x > pInner->pos.xy.nWorld_x + 0x4b0) ||
                      (pOuter->pos.xy.nWorld_y < pInner->pos.xy.nWorld_y + -0x4b0 ||
                       pOuter->pos.xy.nWorld_y > pInner->pos.xy.nWorld_y + 0x4b0)))) {
                    continue;
                }
                savedSlot = *pOuterSlot;
                pDst = pOuterSlot;
                pInnerSlot = pDst + 1;
                i = outerIdx;
                while (i < innerIdx) {
                    *pDst = *pInnerSlot;
                    i = i + 1;
                    pDst = pDst + 1;
                    pInnerSlot = pInnerSlot + 1;
                }
                *pDst = savedSlot;
                break;
            }
            break;
        }
        outerIdx--;
        pOuterSlot--;
    }
}
