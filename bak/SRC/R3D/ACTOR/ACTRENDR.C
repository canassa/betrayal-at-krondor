#include <dos.h>
#include <stdlib.h>

#include "structs.h"
#include "SRC/GEN/GFXCTX.H"
#include "r3d.h"
#include "SRC/R3D/ACTOR/ACTRENDR.H"
#include "SRC/R3D/SPRITE/WORLDRND.H"
#include "SRC/R3D/CORE/R3D.H"
#include "SRC/R3D/TBLSTORE/SHAPETBL.H"

char actorrender_frustum_cull(void) {
    long scale;
    int recScale;
    int recScaleClamp;

    struct {
        long nProjX;
        long nProjY;
        long nProjZ;
    } out;
    PerspDiv2Args args;

    if ((long)g_abR3dState.nActorFarClipThreshold >
        g_abR3dState.nActorCamZ + g_abR3dState.nMeshBoundHalfExtent)
        return 1;

    args.nNumX = g_abR3dState.nMeshBoundHalfExtent;
    args.nDenom = g_abR3dState.nActorCamZ - g_abR3dState.nMeshBoundHalfExtent;
    if ((long)g_abR3dState.nActorFarClipThreshold > args.nDenom)
        args.nDenom = (long)g_abR3dState.nActorFarClipThreshold;

    scale = r3d_actor_proj_scale_compute(&args);
    if (scale > SHAPE_SCALE_UNITY) {
        g_abR3dState.wActorProjScale = SHAPE_SCALE_UNITY;
    } else if (!(g_abR3dState.wActorProjScale = (unsigned short)scale)) {
        return 1;
    }

    args.nNumX = labs(g_abR3dState.nActorCamX) - g_abR3dState.nMeshBoundHalfExtent;
    args.nNumY = labs(g_abR3dState.nActorCamY) - g_abR3dState.nMeshBoundHalfExtent;
    args.nDenom = g_abR3dState.nActorCamZ + g_abR3dState.nMeshBoundHalfExtent;
    r3d_vec2_perspective_divide(&args, (PerspDiv2Result *)&out);
    r3d_vec2_long_translate_yflip((long *)&out);

    if ((long)g_graphics_context.clip.xmax < out.nProjX)
        return 1;
    if ((long)g_graphics_context.clip.ymin > out.nProjY)
        return 1;

    g_abR3dState.bActorViewportClip = 0;

    if (g_abR3dState.bSkipFarEdgeCull != 0)
        goto set_clip;
    args.nDenom = g_abR3dState.nActorCamZ - g_abR3dState.nMeshBoundHalfExtent;
    if ((long)g_abR3dState.nActorFarClipThreshold > args.nDenom)
        goto set_clip;

    args.nNumX = labs(g_abR3dState.nActorCamX) + g_abR3dState.nMeshBoundHalfExtent;
    args.nNumY = labs(g_abR3dState.nActorCamY) + g_abR3dState.nMeshBoundHalfExtent;
    r3d_vec2_perspective_divide(&args, (PerspDiv2Result *)&out);
    r3d_vec2_long_translate_yflip((long *)&out);
    if ((long)g_graphics_context.clip.xmax < out.nProjX)
        goto set_clip;
    if ((long)g_graphics_context.clip.ymin <= out.nProjY)
        goto scale_adjust;
set_clip:
    g_abR3dState.bActorViewportClip = 1;
scale_adjust:

    recScale = g_shapeTables[g_abR3dState.nCurModelIdx].scale;
    recScaleClamp = g_shapeTables[g_abR3dState.nCurModelIdx].scaleClamp;

    if (recScale == SHAPE_SCALE_UNITY)
        goto done;
    if (recScale == -1) {
        g_abR3dState.wActorProjScale = (unsigned short)recScaleClamp;
        goto done;
    }

    scale = r3d_imul_full32(g_abR3dState.wActorProjScale, recScale) >> 8;
    if (scale < 0L)
        scale = 0L;
    else if ((long)recScaleClamp < scale)
        scale = (long)recScaleClamp;
    g_abR3dState.wActorProjScale = (unsigned short)scale;
done:
    return 0;
}

#define MESH_PART_VISIBLE(p)                                                                       \
    (g_abR3dState.pCurMeshPartVisTable == 0 || *(p) == 0xff ||                                     \
     g_abR3dState.pCurMeshPartVisTable[*(p)] != 0xff)

int actorrender_mesh_parts_cull_sort(int part_off, int part_count, int *parts) {
    int count;
    int *pRead;
    int *pWrite;
    unsigned char far *pPart;
    Vec3Short far *pPool;
    long key;
    int maxIdx;
    Vec3Short anchor;
    Vec3Short edge;
    int sh;
    long keys[48];
    int i;

    if (part_count < 2) {
        if (part_count == 0)
            return 0;

        pPart =
            (unsigned char far *)MK_FP(FP_SEG(g_abR3dState.pCurActorPagedRec), (unsigned)*parts);
        if (!MESH_PART_VISIBLE(pPart))
            return 0;
        return 1;
    }

    if (*(unsigned char far *)g_abR3dState.pCurActorPagedRec & 0x40) {

        long *pKey;

        count = 0;
        pRead = parts;
        pWrite = parts;
        pKey = keys;
        for (i = 0; i < part_count; i++) {
            pPart = (unsigned char far *)MK_FP(FP_SEG(g_abR3dState.pCurActorPagedRec),
                                               (unsigned)*pRead);
            pRead++;
            if (MESH_PART_VISIBLE(pPart)) {
                if (part_off == (int)FP_OFF(pPart) ||
                    ((MeshPartRecord far *)pPart)->bEdgeVtxIdx == 0xff) {

                    key = 0;
                } else {
                    pPool = (Vec3Short
                             far *)MK_FP(FP_SEG(g_abR3dState.pCurActorPagedRec),
                                         (unsigned)((MeshPartRecord far *)pPart)->wVertexPoolOff);
                    if (((MeshPartRecord far *)pPart)->bAnchorVtxIdx == 0xff) {

                        anchor = *(Vec3Short far *)&g_abR3dState.nMeshCamOriginX;
                    } else {

                        sh = -(int)g_abR3dState.wMeshScaleResidual;
                        anchor = pPool[(unsigned)((MeshPartRecord far *)pPart)->bAnchorVtxIdx];
                        anchor.nX = (anchor.nX >> sh) + g_abR3dState.nMeshCamOriginX;
                        anchor.nY = (anchor.nY >> sh) + g_abR3dState.nMeshCamOriginY;
                        anchor.nZ = (anchor.nZ >> sh) + g_abR3dState.nMeshCamOriginZ;
                    }
                    edge = pPool[(unsigned)((MeshPartRecord far *)pPart)->bEdgeVtxIdx];
                    key = r3d_dot3_long_far((int *)&anchor, (int *)&edge);
                }
                *pWrite = (int)FP_OFF(pPart);
                pWrite++;
                *pKey = key;
                pKey++;
                count++;
            }
        }

        for (i = 0; i < count - 1; i++) {
            int j;
            pKey = keys + i;
            maxIdx = i;
            key = *pKey++;
            for (j = i + 1; j < count; j++, pKey++) {
                if (key < *pKey) {
                    maxIdx = j;
                    key = *pKey;
                }
            }
            if (maxIdx != i) {
                key = keys[i];
                keys[i] = keys[maxIdx];
                keys[maxIdx] = key;
                j = parts[i];
                parts[i] = parts[maxIdx];
                parts[maxIdx] = j;
            }
        }
        return count;
    }

    count = 0;
    pRead = parts;
    pWrite = parts;
    for (i = 0; i < part_count; i++) {
        pPart =
            (unsigned char far *)MK_FP(FP_SEG(g_abR3dState.pCurActorPagedRec), (unsigned)*pRead);
        pRead++;
        if (MESH_PART_VISIBLE(pPart)) {
            *pWrite = (int)FP_OFF(pPart);
            pWrite++;
            count++;
        }
    }
    return count;
}

int actorrender_mesh_part_ptr_arr(int extra, int count, int base, int *output) {
    register int i;

    for (i = 0; i < count; i++) {
        *output++ = base;
        base += 0xe;
    }
    if (extra != 0) {
        *output = extra;
        count++;
    }
    return count;
}

void actorrender_mesh_parts(int part_off, int part_count, int *part_ptr_array) {
    unsigned char far *pPart;
    int i;
    unsigned variantIdx;
    int subCount;

    part_count = actorrender_mesh_parts_cull_sort(part_off, part_count, part_ptr_array);
    for (i = 0; i < part_count; i++) {
        pPart =
            (unsigned char far *)MK_FP(FP_SEG(g_abR3dState.pCurActorPagedRec), part_ptr_array[i]);
        if (part_ptr_array[i] != part_off && (subCount = ((MeshPartRecord far *)pPart)->nSub) > 0) {
            int *pTail = part_ptr_array + part_count;
            subCount = actorrender_mesh_part_ptr_arr(
                part_ptr_array[i], subCount, ((MeshPartRecord far *)pPart)->wSubArrOff, pTail);
            actorrender_mesh_parts(part_ptr_array[i], subCount, pTail);
        } else {
            unsigned char far *pPoly;
            unsigned char far *poly_list;
            g_abR3dState.wMeshVertexPoolOff = ((MeshPartRecord far *)pPart)->wVertexPoolOff;
            g_abR3dState.wMeshPartVertexCount =
                (unsigned short)((MeshPartRecord far *)pPart)->bVertexCount;
            if (g_abR3dState.pCurMeshPartVisTable != 0 &&
                ((MeshPartRecord far *)pPart)->bGroupId != 0xff) {
                for (variantIdx =
                         g_abR3dState.pCurMeshPartVisTable[((MeshPartRecord far *)pPart)->bGroupId];
                     ((MeshPartRecord far *)pPart)->nField6 <= (int)variantIdx;
                     variantIdx -= (unsigned)((MeshPartRecord far *)pPart)->nField6) {
                }
            } else {
                variantIdx = 0;
            }
            pPoly = (unsigned char far *)MK_FP(FP_SEG(g_abR3dState.pCurActorPagedRec),
                                               ((MeshPartRecord far *)pPart)->wPolyListOff);
            *(unsigned *)&pPoly += variantIdx * 8;
            if (pPoly[0] == 0) {
                poly_list = pPoly + 2;
                g_graphics_context.bClip_enabled = 0;
                if (!g_abR3dState.bCurMeshLod) {
                    r3d_mesh_part_polygons(poly_list);
                } else if (g_abR3dState.bCurMeshLod == 3) {
                    r3d_mesh_part_polygons_lod3((unsigned short far *)poly_list);
                } else {
                    r3d_mesh_polygons(poly_list);
                }
            } else if (pPoly[0] == 1) {
                worldrender_world_point_as_circ((CircObj far *)(pPoly + 2));
            } else {
                worldrender_sprite_billboard(pPoly + 2);
            }
        }
    }
}

void actorrender_entity(WorldObject far *entry) {
    Shape far *pRec;
    struct LodDescriptor far *pDesc;
    unsigned short recordId;
    int nPage;
    int nDesc;
    int nParts;
    int parts[48];

    recordId = entry->shapeId;
    pRec = (Shape far *)0;
    for (nPage = 0; nPage < g_shapeTableCount; nPage++) {
        if ((int)recordId < g_shapeTables[nPage].count) {
            g_abR3dState.nCurModelIdx = nPage;
            pRec = (Shape far *)(g_abR3dState.pCurActorPagedRec =
                                     (void far *)g_shapeTables[nPage].records[recordId]);
            break;
        }
        recordId -= g_shapeTables[nPage].count;
    }
    if (pRec == (Shape far *)0) {
        return;
    }

    g_abR3dState.pCurMeshPartVisTable = (unsigned char *)entry->state.stateBits;
    g_abR3dState.wMeshScaleShift = pRec->shift;
    g_abR3dState.nMeshBoundHalfExtent = (long)(short)pRec->radius << g_abR3dState.wMeshScaleShift;

    r3d_setup_actor_in_camera_space((WorldObject *)entry, FP_SEG(entry));
    if (actorrender_frustum_cull() != 0) {
        return;
    }
    r3d_compose_actor_camera_matrix();

    if (g_abR3dState.wMeshScaleShift != 0 || 0x3fac < g_abR3dState.nMeshBoundHalfExtent ||
        32000 < (long)(g_abR3dState.nActorBoundExtent + g_abR3dState.nMeshBoundHalfExtent)) {
        r3d_actor_compute_lod_z();
        if (g_abR3dState.nActorLodZ >> g_abR3dState.bMeshRenormCount >
            (long)g_abR3dState.nActorFarClipThreshold) {
            g_abR3dState.wMeshScaleShift = g_abR3dState.wMeshScaleResidual;
            g_abR3dState.nActorClampedCamZ = (long)g_abR3dState.nMeshNormOriginX;
            g_abR3dState.nActorCamX = (long)g_abR3dState.nMeshOriginX;
            g_abR3dState.nActorCamZ = (long)g_abR3dState.nMeshOriginY;
            g_abR3dState.nActorCamY = (long)g_abR3dState.nMeshOriginZ;
            if (g_abR3dState.wMeshScaleShift != 0) {
                g_abR3dState.bCurMeshLod = 3;
            } else {
                g_abR3dState.bCurMeshLod = 0;
            }
        } else {
            if (g_abR3dState.nMeshBoundHalfExtent < 0x3fac) {
                g_abR3dState.bCurMeshLod = 1;
            } else {
                g_abR3dState.bCurMeshLod = 2;
            }
        }
    } else {
        g_abR3dState.bCurMeshLod = 0;
    }

    nDesc = pRec->lodCount;
    pDesc = (struct LodDescriptor far *)MK_FP(FP_SEG(pRec), (unsigned)pRec->lodArray);

    nPage = 0;
    while (nPage < nDesc) {
        if ((int)g_abR3dState.wActorProjScale <= pDesc->nThreshold) {
            break;
        }
        nPage++;
        pDesc++;
    }
    if (nPage == nDesc) {
        pDesc--;
    }
    g_abR3dState.dwMeshVertexFarPtrCache = 0;
    g_abR3dState.wMeshVertexPoolOff = 0;
    nParts = actorrender_mesh_part_ptr_arr(0, pDesc->nPartCount, pDesc->wPartBaseOff, parts);
    actorrender_mesh_parts(0, nParts, parts);
}
