/**
 * @file  SHAPEBLD.C
 * @brief Runtime shape builder — see @ref SHAPEBLD.H. Also the storage owner of @ref g_builder
 *        (the _BSS @ref ShapeBuilder cluster).
 */
#include <dos.h>
#include <stdlib.h>
#include "structs.h"
#include "gtypes.h"
#include "SRC/R3D/TBLSTORE/SHAPEBLD.H"
#include "SRC/SYS/DOSMEM.H"
#include "SRC/R3D/CORE/R3D.H"
#include "SRC/R3D/TBLSTORE/SHAPETBL.H"
#include "SRC/SYS/PANICF.H"

/**
 * @brief Poly-list block — 8B animation-variant stride; @c actorrender_mesh_parts (TBD-ref: ACTRENDR.H lacks a file block) advances by
 *        variantIdx*8 before reading @ref PolyListBlock::bTag.
 *
 * @ref PolyListBlock::bTag selects the @ref PolyListBlock::u arm; the renderer hands block+2 to the matching handler:
 * tag 0 -> @ref r3d_mesh_part_polygons, tag 1 -> @c worldrender_world_point_as_circ (TBD-ref: WORLDRND.H lacks a file block),
 * tag 2 -> @c worldrender_sprite_billboard (TBD-ref: WORLDRND.H lacks a file block). The builder only ever emits tag 0.
 */
struct PolyListBlock {
    unsigned char bTag; /**< +0x0, 1B: payload discriminator (0/1/2). */
    unsigned char bPad; /**< +0x1, 1B: pad. */
    union {             /**< +0x2..+0x7, 6B: active arm (widest is @ref SpriteBillboard, 6B). */
        /** tag 0: face count + near offset to the @ref MeshPolygon array. */
        struct MeshPolyHeader {
            unsigned short polyCount, firstPolyOff;
        } poly;
        CircObj circ;           /**< tag 1: world-point circle. */
        SpriteBillboard sprite; /**< tag 2: sprite billboard. */
    } u; /**< +0x2..+0x7, 6B: payload; active arm chosen by @ref PolyListBlock::bTag. */
};

/**
 * @brief One mesh face — 8B, mirroring the @c R3D.ASM FACE struc.
 */
struct MeshPolygon {
    unsigned char bFlags; /**< +0x0, 1B: low 2 bits = type; 0x20 = back-face test; 0x80 = fill. */
    unsigned char abShadeOp
        [5]; /**< +0x1, 5B: shade/color operands -> @ref r3d_polygon_resolve_shade_color. */
    unsigned short
        wIdxListOff; /**< +0x6, 2B: near offset to the 0xff-terminated vertex-index list. */
};

/* The wireframe-builder state cluster (DGROUP 0x5f7a..0x5f9b), gathered into one
 * struct. This TU is the block's sole referencer and owns its storage. */
ShapeBuilder g_builder;

long ts_isqrt_long(long n) {
    long x;
    long quot;

    x = n;
    quot = 1L;
    while (x > quot) {
        x = (x + quot) >> 1;
        quot = n / x;
    }
    return x;
}

void ts_emit_ribbon_joint(Vec3Short *anchorXy) {
    int dxOff;
    int t;
    uint a1, a2, base;
    int delta;
    Vec3Short vtx;
    int i;

    dxOff = g_builder.aVtx1Packed.nX - g_builder.aVtx2Packed.nX;
    t = g_builder.aVtx1Packed.nY - g_builder.aVtx2Packed.nY;
    a1 = r3d_tbl_atan2(dxOff, t);

    dxOff = g_builder.aVtx3Packed.nX - g_builder.aVtx2Packed.nX;
    t = g_builder.aVtx3Packed.nY - g_builder.aVtx2Packed.nY;
    a2 = r3d_tbl_atan2(dxOff, t);

    if (a1 > a2) {
        delta = a1 - a2;
        if (delta < 0)
            base = a1;
        else
            base = a2;
    } else {
        delta = a2 - a1;
        if (delta < 0)
            base = a2;
        else
            base = a1;
    }

    base += abs(delta >> 1);

    base -= R3D_DEG(90); /* rotate the bisector to the ribbon-normal direction */

    dxOff = -r3d_tbl_sin(base);
    t = r3d_tbl_cos(base);
    dxOff = r3d_imul_full32(dxOff, g_builder.nSegmentRadius) >> 14;
    t = r3d_imul_full32(t, g_builder.nSegmentRadius) >> 14;

    if (delta < 0) {
        dxOff = -dxOff;
        t = -t;
    }

    vtx.nX = anchorXy->nX + dxOff;
    vtx.nY = anchorXy->nY + t;
    vtx.nZ = 0;

    for (i = 0; i < 2; i++) {

        *(Vec3Short far *)g_builder.pEdgePoolCursor = vtx;
        g_builder.pEdgePoolCursor += 6;

        if (g_builder.bFirstVtxFlag) {

            g_builder.builtShape->aabbMin = vtx;
            g_builder.builtShape->aabbMax = vtx;
            g_builder.bFirstVtxFlag = 0;
        } else {

            g_builder.builtShape->aabbMin.nX = g_builder.builtShape->aabbMin.nX > vtx.nX
                                                   ? vtx.nX
                                                   : g_builder.builtShape->aabbMin.nX;
            g_builder.builtShape->aabbMin.nY = g_builder.builtShape->aabbMin.nY > vtx.nY
                                                   ? vtx.nY
                                                   : g_builder.builtShape->aabbMin.nY;
            g_builder.builtShape->aabbMin.nZ = g_builder.builtShape->aabbMin.nZ > vtx.nZ
                                                   ? vtx.nZ
                                                   : g_builder.builtShape->aabbMin.nZ;
            g_builder.builtShape->aabbMax.nX = g_builder.builtShape->aabbMax.nX < vtx.nX
                                                   ? vtx.nX
                                                   : g_builder.builtShape->aabbMax.nX;
            g_builder.builtShape->aabbMax.nY = g_builder.builtShape->aabbMax.nY < vtx.nY
                                                   ? vtx.nY
                                                   : g_builder.builtShape->aabbMax.nY;
            g_builder.builtShape->aabbMax.nZ = g_builder.builtShape->aabbMax.nZ < vtx.nZ
                                                   ? vtx.nZ
                                                   : g_builder.builtShape->aabbMax.nZ;
        }

        vtx.nX = anchorXy->nX - dxOff;
        vtx.nY = anchorXy->nY - t;
    }
}

void ts_pack_vertex(Vec3Short far *dstShort3, Vec3Long far *srcLong3) {
    dstShort3->nX = srcLong3->nX >> g_builder.builtShape->shift;
    dstShort3->nY = srcLong3->nY >> g_builder.builtShape->shift;
    dstShort3->nZ = srcLong3->nZ >> g_builder.builtShape->shift;
}

void ts_project_shape(Vec3Long *vtxData, uint vtxSeg, int vtxCount, int radiusIn) {
    Vec3Long far *vtxCur;
    int tmp;
    long maxMag;
    long curMag;
    int absZ, absY, absX;
    long labZ, labY, labX;
    int i;

    maxMag = 0;

    vtxCur = MK_FP(vtxSeg, (unsigned)vtxData);

    for (i = 0; i < vtxCount; i++, vtxCur++) {
        labX = labs(vtxCur->nX);
        labY = labs(vtxCur->nY);
        labZ = labs(vtxCur->nZ);

        curMag = (labX > labY) ? labX : labY;

        curMag = (curMag > labZ) ? curMag : labZ;

        if (curMag > maxMag)
            maxMag = curMag;
    }

    g_builder.builtShape->shift = 0;
    curMag = maxMag;

    while (curMag > 0x3FACL) {
        curMag >>= 1;
        g_builder.builtShape->shift++;
    }

    g_builder.nSegmentRadius = radiusIn >> (g_builder.builtShape->shift + 1);

    vtxCur = MK_FP(vtxSeg, (unsigned)vtxData);

    ts_pack_vertex(&g_builder.aVtx1Packed, vtxCur++);
    ts_pack_vertex(&g_builder.aVtx2Packed, vtxCur++);
    ts_pack_vertex(&g_builder.aVtx3Packed, vtxCur++);

    g_builder.bFirstVtxFlag = 1;

    ts_emit_ribbon_joint(&g_builder.aVtx1Packed);

    for (i = 3; i <= vtxCount; i++) {
        ts_emit_ribbon_joint(&g_builder.aVtx2Packed);

        if (i < vtxCount) {

            g_builder.aVtx1Packed = g_builder.aVtx2Packed;
            g_builder.aVtx2Packed = g_builder.aVtx3Packed;
            ts_pack_vertex(&g_builder.aVtx3Packed, vtxCur++);
        }
    }

    ts_emit_ribbon_joint(&g_builder.aVtx3Packed);

    absX = abs(g_builder.builtShape->aabbMin.nX);
    tmp = abs(g_builder.builtShape->aabbMax.nX);
    if (tmp > absX)
        absX = tmp;

    absY = abs(g_builder.builtShape->aabbMin.nY);
    tmp = abs(g_builder.builtShape->aabbMax.nY);
    if (tmp > absY)
        absY = tmp;

    absZ = abs(g_builder.builtShape->aabbMin.nZ);
    tmp = abs(g_builder.builtShape->aabbMax.nZ);
    if (tmp > absZ)
        absZ = tmp;

    curMag = r3d_imul_full32(absX, absX);
    curMag += r3d_imul_full32(absY, absY);
    curMag += r3d_imul_full32(absZ, absZ);
    g_builder.builtShape->radius = ts_isqrt_long(curMag);
}

void far *ts_bump_alloc(int size) {
    unsigned char far *p;

    p = g_builder.bumpCursor;
    g_builder.bumpCursor += size;
    return p;
}

void ts_alloc_shape_block(int recordCount) {
    unsigned char far *p;
    unsigned int i;
    unsigned int size;

    /* Fixed prefix: Shape + LOD descriptor + one mesh part + one poly-list block. */
    size = sizeof(Shape) + sizeof(struct LodDescriptor) + sizeof(MeshPartRecord) +
           sizeof(struct PolyListBlock);
    /* Per segment: one MeshPolygon face + its 5-byte quad index list. */
    size += (recordCount - 1) * (sizeof(struct MeshPolygon) + 5);
    /* Vertex pool: two ring vertices per input vertex. */
    size += recordCount * 2 * sizeof(Vec3Short);
    g_builder.bumpCursor = alloc_far(size, 1L);
    if (g_builder.bumpCursor == NULL) {
        panic("ts_build_shape");
    }
    p = g_builder.bumpCursor;
    for (i = 0; i < size; i++) {
        *p = 0;
        p++;
    }
}

Shape far *ts_build_shape(int slot, Vec3Long *vtxData, uint vtxSeg, int vtxCount, int ribbonWidth,
                          int color1, int color2) {
    int idxBase;
    struct LodDescriptor far *pLod;
    MeshPartRecord far *pPart;
    struct PolyListBlock far *pPolyBlock;
    struct MeshPolyHeader far *pPolyHeader;
    struct MeshPolygon far *pFace;
    uchar far *pIndices;
    int i;

    if (vtxCount >= 3) {

        ts_alloc_shape_block(vtxCount);

        g_builder.builtShape = ts_bump_alloc(sizeof(Shape));
        g_builder.builtShape->lodCount = 1;
        g_builder.builtShape->lodArray = (void *)FP_OFF(g_builder.bumpCursor);
        g_builder.builtShape->priority = 0xff;
        g_builder.builtShape->shift = 0;

        pLod = ts_bump_alloc(sizeof(struct LodDescriptor));
        pLod->nPartCount = 1;
        pLod->wPartBaseOff = FP_OFF(g_builder.bumpCursor);

        pPart = ts_bump_alloc(sizeof(MeshPartRecord));
        pPart->wVertexPoolOff = FP_OFF(g_builder.bumpCursor);
        pPart->bVertexCount = vtxCount * 2;

        g_builder.pEdgePoolCursor = ts_bump_alloc(pPart->bVertexCount * sizeof(Vec3Short));

        ts_project_shape(vtxData, vtxSeg, vtxCount, ribbonWidth);

        pPart->bGroupId = 0xff;
        pPart->bEdgeVtxIdx = 0xff;
        pPart->nField6 = 1;
        pPart->wPolyListOff = FP_OFF(g_builder.bumpCursor);

        pPolyBlock = ts_bump_alloc(sizeof(struct PolyListBlock));
        pPolyBlock->bTag = 0;
        /* Fill the tag-0 header through its own pointer: the reference materializes a
         * distinct far pointer to block+2, so the header fields are addressed off that
         * pointer rather than off pPolyBlock. */
        pPolyHeader = &pPolyBlock->u.poly;
        pPolyHeader->polyCount = vtxCount - 1;
        pPolyHeader->firstPolyOff = FP_OFF(g_builder.bumpCursor);

        idxBase = 0;
        pFace = ts_bump_alloc((vtxCount - 1) * sizeof(struct MeshPolygon));

        i = 0;
        while (i < vtxCount - 1) {

            pFace->bFlags = 0x80;
            pFace->abShadeOp[2] = color1;
            pFace->abShadeOp[0] = color1;
            pFace->abShadeOp[3] = color2;
            pFace->abShadeOp[1] = color2;
            pFace->abShadeOp[4] = 0xff;

            pIndices = ts_bump_alloc(5);
            pFace->wIdxListOff = FP_OFF(pIndices);

            /* One quad face bridging this segment's 2-vertex ring
             * (idxBase+0, idxBase+1) to the next ring (idxBase+2, idxBase+3).
             * Wind it as a closed loop — this ring's v0,v1 then the NEXT ring's
             * v1,v0 — so the order runs 0,1,3,2, not 0,1,2,3. The cross-over on
             * the far edge is deliberate: it keeps the quad convex instead of
             * pinching into a bow-tie. 0xff terminates the index list. */
            *pIndices++ = idxBase;     /* this ring, v0 */
            *pIndices++ = idxBase + 1; /* this ring, v1 */
            *pIndices++ = idxBase + 3; /* next ring, v1 */
            *pIndices++ = idxBase + 2; /* next ring, v0 */
            *pIndices++ = 0xff;        /* end of index list */

            i++;
            pFace++;
            idxBase += 2;
        }

        if (ts_set_shape(slot, g_builder.builtShape) != 0)
            return g_builder.builtShape;
        _freemem(g_builder.builtShape);
    }
    return NULL;
}
