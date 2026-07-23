#include <dos.h>

#include "structs.h"
#include "globals.h"
#include "SRC/WORLD/ZONE/ZONE.H"
#include "SRC/R3D/ACTOR/ACTMOTN.H"
#include "r3d.h"
#include "SRC/R3D/SPRITE/WORLDRND.H"
#include "SRC/GFX/SPRITE/RESBLIT.H"
#include "SRC/R3D/CORE/DISTDIR.H"
#include "SRC/GFX/RASTER/CIRCLE.H"
#include "SRC/STREAM/RESLOAD/IMGLOAD.H"
#include "SRC/GFX/RASTER/POLYGON.H"
#include "SRC/R3D/CORE/R3D.H"
#include "SRC/SYS/EMSIMG.H"
#include "gfx169d.h"
#include "SRC/R3D/TBLSTORE/SHAPETBL.H"

unsigned short g_spriteBankCount;
PagedArrayEntry *g_spriteBanks;
ImageRecord *g_pBillboardSpriteImg;
short g_nBillboardScrX;
short g_nBillboardScrY;
short g_nBillboardW;
short g_nBillboardH;
unsigned short g_nFogRemapTableCount;
unsigned short g_wSpriteFogBucketWidth;
unsigned long g_lSpriteFogOnsetDist;
long g_lSpriteFogFarDist;
unsigned short g_nLodBucketWidth;
unsigned long g_dwLodNearThreshold;
unsigned long g_lFarCullDist;

ImageRecord **worldrender_table_swap(int slot, ImageRecord **new_table_ptr) {
    ImageRecord **old_table_ptr;

    old_table_ptr = 0;
    if (new_table_ptr != 0) {
        old_table_ptr = g_spriteBanks[slot].imageRecord;
        g_spriteBanks[slot].imageRecord = new_table_ptr;
        g_spriteBanks[slot].nCount = null_terminated_count(new_table_ptr);
    }
    return old_table_ptr;
}

void worldrender_swap_record_table(int slot_a, int slot_b) {
    int a = slot_a;
    int b = slot_b;
    Shape far *far *tmpRecords;
    int tmpScale;
    int tmpScaleClamp;
    int tmpSpriteBank;
    int tmpCount;

    tmpRecords = g_shapeTables[a].records;
    tmpScale = g_shapeTables[a].scale;
    tmpScaleClamp = g_shapeTables[a].scaleClamp;
    tmpSpriteBank = g_shapeTables[a].spriteBank;
    tmpCount = g_shapeTables[a].count;

    g_shapeTables[a].records = g_shapeTables[b].records;
    g_shapeTables[a].scale = g_shapeTables[b].scale;
    g_shapeTables[a].scaleClamp = g_shapeTables[b].scaleClamp;
    g_shapeTables[a].spriteBank = g_shapeTables[b].spriteBank;
    g_shapeTables[a].count = g_shapeTables[b].count;

    g_shapeTables[b].records = tmpRecords;
    g_shapeTables[b].scale = tmpScale;
    g_shapeTables[b].scaleClamp = tmpScaleClamp;
    g_shapeTables[b].spriteBank = tmpSpriteBank;
    g_shapeTables[b].count = tmpCount;
}

ImageRecord **worldrender_table_load(int slot, char *fname) {
    ImageRecord **table;

    table = resblit_load_asset_table(fname, 1);
    if (table != 0) {
        g_spriteBanks[slot].imageRecord = table;
        g_spriteBanks[slot].nCount = null_terminated_count(table);
    }
    return table;
}

void worldrender_table_unload(int slot) {
    emsimg_free_paged(g_spriteBanks[slot].imageRecord);
    g_spriteBanks[slot].imageRecord = 0;
    g_spriteBanks[slot].nCount = 0;
}

ImageRecord *worldrender_paged_array_get(int index) {
    int i;

    if (index < 0)
        return 0;
    for (i = 0; i < (int)g_spriteBankCount; i++) {
        if (index < g_spriteBanks[i].nCount) {
            return g_spriteBanks[i].imageRecord[index];
        }
        index -= g_spriteBanks[i].nCount;
    }
    return 0;
}

int *worldrender_mesh_vertex_to_world(unsigned char idx, int *out_vec3) {
    struct {
        Vec3Short far *vp;
        short vx;
        short vy;
        short vz;
    } L;
    Mat3x3 mat;

    if (idx != 0xff) {
        short neg_shift = -(short)g_abR3dState.wMeshScaleResidual;
        L.vp = (Vec3Short far *)MK_FP(FP_SEG(g_abR3dState.pCurActorPagedRec),
                                      g_abR3dState.wMeshVertexPoolOff);
        *(Vec3Short near *)&L.vx = L.vp[idx];
        L.vx >>= neg_shift;
        L.vy >>= neg_shift;
        L.vz >>= neg_shift;
        mat = g_abR3dState.mat3x3ActorRot;
        r3d_mat3_xform_vec3_wrap((int *)&L.vx, &mat, out_vec3);
        *out_vec3 += g_abR3dState.nMeshOriginX;
        out_vec3[1] += g_abR3dState.nMeshOriginY;
        out_vec3[2] += g_abR3dState.nMeshOriginZ;
    } else {
        *(Vec3Short *)out_vec3 = *(Vec3Short far *)&g_abR3dState.nMeshOriginX;
    }
    return out_vec3;
}

/* entry points at a SpriteBillboard (structs.h) — the tag-2 poly-list payload.
 * Fields are read by raw offset here: the +2 word is deliberately punned to pull
 * both yAdjust (low byte) and xOffset (high byte), so the accessors stay raw. */
void worldrender_sprite_billboard(unsigned char far *entry) {
    int spriteBank;
    int scaleQ10;
    int nOffX;
    register int nHalf;
    unsigned short wScale;
    int nAdjY;
    int nScrX;
    int nScrY;
    unsigned long lDist;
    int vec3[3];

    spriteBank = g_shapeTables[g_nCurModelIdx].spriteBank;
    if (spriteBank == -1) {
        g_pBillboardSpriteImg = worldrender_paged_array_get(*(int far *)entry);
    } else if ((*(int far *)entry >= 0) && (g_spriteBanks[spriteBank].nCount > *(int far *)entry)) {
        g_pBillboardSpriteImg = g_spriteBanks[spriteBank].imageRecord[*(int far *)entry];
    } else {
        g_pBillboardSpriteImg = 0;
    }
    if (g_pBillboardSpriteImg == 0) {
        return;
    }

    worldrender_mesh_vertex_to_world(entry[5], vec3);
    if (vec3[1] < g_nActorFarClipThreshold) {
        return;
    }

    if (entry[4] != 0) {
        wScale = (unsigned short)(r3d_imul_full32(g_wActorProjScale,
                                                  (unsigned int)(unsigned char)entry[4]) >>
                                  8);
    } else {
        wScale = g_wActorProjScale;
    }

    g_nBillboardW = g_pBillboardSpriteImg->nWidth;
    g_nBillboardH = g_pBillboardSpriteImg->nHeight;
    nHalf = (g_nBillboardW > g_nBillboardH) ? g_nBillboardW : g_nBillboardH;
    nHalf >>= 1;

    if (wScale != 0) {
        if (nHalf == 0) {
            return;
        }
        scaleQ10 = (int)(((long)(int)wScale << 10) / (long)nHalf);
        g_nBillboardW = (short)((long)g_nBillboardW * (long)scaleQ10 >> 10);
        g_nBillboardH = (short)((long)g_nBillboardH * (long)scaleQ10 >> 10);

        nScrX = g_nViewportCenterX + (int)(((long)vec3[0] << g_nScreenShift) / (long)vec3[1]);
        nScrY = g_nViewportCenterY - (int)(((long)vec3[2] << g_nScreenShift) / (long)vec3[1]);

        nOffX = (unsigned char)((*(int far *)(entry + 2) >> 8) & 0xff);
        nAdjY = (unsigned char)(entry[2] & 0xff);
        if (g_nActorSpriteFlip == 0) {
            nOffX = (int)((long)nOffX * (long)scaleQ10 >> 10);
        } else {
            nOffX = g_nBillboardW - (int)((long)nOffX * (long)scaleQ10 >> 10);
        }
        nAdjY = (int)((long)nAdjY * (long)scaleQ10 >> 10);

        g_graphics_context.bClip_enabled = 1;
        lDist = distdir_octagonal_distance_dxdy(g_abR3dState.nActorRelX, g_abR3dState.nActorRelY);
        if (lDist < 0x5dc) {
            return;
        }

        g_nBillboardScrX = (nScrX - nOffX) - g_nActorShakeX;
        g_nBillboardScrY = (nScrY - nAdjY) - g_nActorShakeY;

        if (g_nActorKnockbackColorIdx != 0) {
            g_nActorKnockbackColorIdx = g_nActorKnockbackColorIdx % 5;
            g_polyRasterState.nRemapTableOff =
                g_nActorKnockbackColorIdx * 0x100 + CURSOR_REMAP_TAB_OFF;
            emsimg_sprite_blit_scaled_paged(g_pBillboardSpriteImg, g_nBillboardScrX,
                                            g_nBillboardScrY, g_nActorSpriteFlip, g_nBillboardW,
                                            g_nBillboardH);
        } else if (lDist < g_lSpriteFogOnsetDist) {
            g_polyRasterState.nRemapTableOff = 0;
            emsimg_sprite_blit_scaled_paged(g_pBillboardSpriteImg, g_nBillboardScrX,
                                            g_nBillboardScrY, g_nActorSpriteFlip, g_nBillboardW,
                                            g_nBillboardH);
        } else if (g_game_mode == 2) {
            if (lDist < g_lFarCullDist) {
                if (lDist != 0) {
                    lDist = lDist / 0x640;
                    lDist = lDist << 1;
                }
                if ((unsigned long)(long)(int)(g_nFogRemapTableCount + 1) > lDist) {
                    if (lDist != 0) {
                        g_polyRasterState.nRemapTableOff =
                            (int)lDist * 0x100 + (FOG_REMAP_TAB_OFF - 0x100);
                    } else {
                        g_polyRasterState.nRemapTableOff = 0;
                    }
                    emsimg_sprite_blit_scaled_paged(g_pBillboardSpriteImg, g_nBillboardScrX,
                                                    g_nBillboardScrY, g_nActorSpriteFlip,
                                                    g_nBillboardW, g_nBillboardH);
                }
            }
        } else {
            lDist =
                (lDist - g_lSpriteFogOnsetDist) / (unsigned long)(long)(int)g_wSpriteFogBucketWidth;
            if ((unsigned long)(long)(int)g_nFogRemapTableCount <= lDist) {
                lDist = (unsigned long)(int)(g_nFogRemapTableCount - 1);
            }
            g_polyRasterState.nRemapTableOff = (int)lDist * 0x100 + FOG_REMAP_TAB_OFF;
            emsimg_sprite_blit_scaled_paged(g_pBillboardSpriteImg, g_nBillboardScrX,
                                            g_nBillboardScrY, g_nActorSpriteFlip, g_nBillboardW,
                                            g_nBillboardH);
        }
        g_graphics_context.bClip_enabled = 0;
    }
}

void worldrender_textured_quad_lod(int texture_index, int *xs, int *ys) {
    unsigned int *pHandle;
    unsigned long lDist;
    int spriteBank;

    spriteBank = g_shapeTables[g_abR3dState.nCurModelIdx].spriteBank;

    if (spriteBank == -1) {
        pHandle = (unsigned int *)worldrender_paged_array_get(texture_index);
    } else {
        if (texture_index >= 0 && g_spriteBanks[spriteBank].nCount > texture_index) {
            pHandle = (unsigned int *)g_spriteBanks[spriteBank].imageRecord[texture_index];
        } else {
            pHandle = 0;
        }
    }

    if (pHandle == 0)
        return;

    if (xs[0] < g_graphics_context.clip.xmin && xs[1] < g_graphics_context.clip.xmin &&
        xs[2] < g_graphics_context.clip.xmin && xs[3] < g_graphics_context.clip.xmin)
        return;

    if (xs[0] > g_graphics_context.clip.xmax && xs[1] > g_graphics_context.clip.xmax &&
        xs[2] > g_graphics_context.clip.xmax && xs[3] > g_graphics_context.clip.xmax)
        return;

    if (ys[0] < g_graphics_context.clip.ymin && ys[1] < g_graphics_context.clip.ymin &&
        ys[2] < g_graphics_context.clip.ymin && ys[3] < g_graphics_context.clip.ymin)
        return;

    if (ys[0] > g_graphics_context.clip.ymax && ys[1] > g_graphics_context.clip.ymax &&
        ys[2] > g_graphics_context.clip.ymax && ys[3] > g_graphics_context.clip.ymax)
        return;

    g_graphics_context.bClip_enabled = 1;

    if (g_bForceOverlay) {
        g_graphics_context.bGfx_fill_color = g_graphics_context.bGfx_outline_color =
            (unsigned char)texture_index;
        g_graphics_context.bGfx_fill_enabled = 1;
        draw_polygon(4, xs, ys);
    } else if (g_game_mode == 2) {

        lDist = (unsigned long)distdir_octagonal_distance_dxdy(g_abR3dState.nActorRelX,
                                                               g_abR3dState.nActorRelY);
        if (lDist < g_lFarCullDist) {
            if (lDist != 0) {
                lDist = lDist / 0x640;
                lDist = lDist << 1;
            }
            if ((short)g_nFogRemapTableCount + 1 > lDist) {
                if (lDist != 0) {
                    g_polyRasterState.nRemapTableOff =
                        ((int)lDist << 8) + (FOG_REMAP_TAB_OFF - 0x100);
                } else {
                    g_polyRasterState.nRemapTableOff = 0;
                }
                emsimg_gouraud_blit_paged(pHandle, xs, ys);
            }
        }
    } else {

        lDist = (unsigned long)distdir_octagonal_distance_dxdy(g_abR3dState.nActorRelX,
                                                               g_abR3dState.nActorRelY);
        if (lDist < g_dwLodNearThreshold) {
            g_polyRasterState.nRemapTableOff = 0;
            emsimg_gouraud_blit_paged(pHandle, xs, ys);
        } else if (lDist < g_lFarCullDist) {
            lDist = (lDist - g_dwLodNearThreshold) / (short)g_nLodBucketWidth;
            if ((short)g_nFogRemapTableCount <= lDist) {
                lDist = (unsigned long)((short)g_nFogRemapTableCount - 1);
            }
            g_polyRasterState.nRemapTableOff = ((int)lDist << 8) + FOG_REMAP_TAB_OFF;
            emsimg_gouraud_blit_paged(pHandle, xs, ys);
        }
    }
    g_graphics_context.bClip_enabled = 0;
}

void worldrender_world_point_as_circ(CircObj far *obj) {
    int radius;
    int nScreenX;
    int nScreenY;
    int nHalfWidth;
    int out_vec3[3];

    worldrender_mesh_vertex_to_world(obj->bVertexIdx, out_vec3);
    if (g_abR3dState.nActorFarClipThreshold <= out_vec3[1]) {
        nScreenX = g_abR3dState.nViewportCenterX +
                   (int)(((long)out_vec3[0] << g_abR3dState.bScreenShift) / (long)out_vec3[1]);
        nScreenY = g_abR3dState.nViewportCenterY -
                   (int)(((long)out_vec3[2] << g_abR3dState.bScreenShift) / (long)out_vec3[1]);
        radius = obj->nRadiusSrc >> (-(char)g_abR3dState.wMeshScaleResidual);
        radius = (int)(((long)radius << g_abR3dState.bScreenShift) / (long)out_vec3[1]);

        radius = (radius < 0x100) ? radius : 0x100;

        if (radius == 0)
            return;
        nHalfWidth = radius + (radius >> 2);
        if ((nScreenX <= g_graphics_context.clip.xmax) &&
            (g_graphics_context.clip.xmin < nScreenX + nHalfWidth) &&
            (nScreenY <= g_graphics_context.clip.ymax) &&
            (g_graphics_context.clip.ymin < nScreenY + radius)) {
            g_graphics_context.bClip_enabled = 1;
            g_graphics_context.bGfx_fill_enabled = 1;
            if (g_graphics_context.bGfxRenderStateFlag != 0) {
                g_graphics_context.bGfx_fill_color = obj->bDayColor;
            } else {
                g_graphics_context.bGfx_fill_color = obj->bNightColor;
            }
            g_graphics_context.bGfx_outline_color = g_graphics_context.bGfx_fill_color =
                (g_pColorRemapTable != 0) ? g_pColorRemapTable[g_graphics_context.bGfx_fill_color]
                                          : g_graphics_context.bGfx_fill_color;
            draw_circle(radius, nScreenX, nScreenY);
            g_graphics_context.bClip_enabled = 0;
        }
    }
    return;
}
