#ifndef BAK_SHAPEBLD_H
#define BAK_SHAPEBLD_H

/**
 * @file  SHAPEBLD.H
 * @brief Runtime shape builder (Table Store build side): a beam/bolt-style ribbon-mesh generator.
 *
 * Builds a flat two-tone mesh ribbon from a 3D polyline and registers it as a @ref Shape via
 * @ref ts_set_shape. DEAD CODE in the shipped game — nothing calls @ref ts_build_shape; only
 * @ref ts_isqrt_long, which happens to live in this module, is reached (from @c WORLDCRS.C (TBD-ref: WORLDCRS.C lacks a file block)).
 */

#include "structs.h"
#include "SRC/R3D/TBLSTORE/SHAPETBL.H"

/**
 * @brief The shape builder's transient working state (one _BSS struct at DGROUP 0x5f7a, 34B).
 *
 * @ref ShapeBuilder::builtShape is the @ref Shape under construction; the rest is scratch for a single build call.
 * @note Kept as one struct rather than separate globals — do not split.
 */
typedef struct ShapeBuilder {
    short nSegmentRadius;               /**< +0x00 */
    unsigned char far *bumpCursor;      /**< +0x02, 4B: allocation cursor into the shape block. */
    unsigned char bFirstVtxFlag;        /**< +0x06 */
    unsigned char bReserved_07;         /**< +0x07 dead alignment pad */
    unsigned char far *pEdgePoolCursor; /**< +0x08 */
    Shape far *builtShape;              /**< +0x0c @ref Shape under construction */
    Vec3Short aVtx1Packed;              /**< +0x10 */
    Vec3Short aVtx2Packed;              /**< +0x16 */
    Vec3Short aVtx3Packed;              /**< +0x1c */
} ShapeBuilder;                         /* sizeof = 0x22 = 34 */
/** The module's single, transient build-state instance (see @ref ShapeBuilder); scratch only. */
extern ShapeBuilder g_builder;

/**
 * @brief Integer square root of a 32-bit magnitude.
 *
 * The module's only live function — called by worldcrs (@c WORLDCRS.C (TBD-ref: WORLDCRS.C lacks a file block)) for world-camera Z,
 * not by the (dead) shape builder.
 *
 * @param[in] n Value to root; treated as a non-negative magnitude.
 * @return    floor(sqrt(@p n)).
 */
extern long ts_isqrt_long(long n);

/**
 * @brief Append one polyline joint's pair of ribbon vertices and extend the shape's bounding box.
 *
 * Helper of @ref ts_build_shape — dead code.
 *
 * @param[in] anchorXy The joint position (a packed input vertex); only X/Y are used.
 */
extern void ts_emit_ribbon_joint(Vec3Short *anchorXy);

/**
 * @brief Scale a long vertex down into a short vertex by the builder's shift exponent.
 *
 * Helper of @ref ts_build_shape — dead code.
 *
 * @param[out] dstShort3 Destination packed vertex.
 * @param[in]  srcLong3  Source unpacked vertex.
 */
extern void ts_pack_vertex(Vec3Short far *dstShort3, Vec3Long far *srcLong3);

/**
 * @brief Populate the shape's ribbon geometry, scale, and bounding radius from the input polyline.
 *
 * Helper of @ref ts_build_shape — dead code.
 *
 * @param[in] vtxData  Near offset of the input vertex array in segment @p vtxSeg.
 * @param[in] vtxSeg   Segment of @p vtxData.
 * @param[in] vtxCount Number of input vertices (>= 3).
 * @param[in] radiusIn Ribbon half-width, before scaling.
 */
extern void ts_project_shape(Vec3Long *vtxData, unsigned int vtxSeg, int vtxCount, int radiusIn);

/**
 * @brief Reserve @p size bytes from the shape block (bump allocation; never individually freed).
 *
 * Helper of @ref ts_build_shape — dead code.
 *
 * @param[in] size Number of bytes to reserve.
 * @return    Far pointer to the reserved run.
 */
extern void far *ts_bump_alloc(int size);

/**
 * @brief Allocate and zero the single far block that backs the whole shape.
 *
 * Sized for @p recordCount input vertices. Helper of @ref ts_build_shape — dead code.
 *
 * @param[in] recordCount Number of input vertices the shape is built from.
 * @warning Panics ("ts_build_shape") if the allocation fails.
 */
extern void ts_alloc_shape_block(int recordCount);

/**
 * @brief Build a flat two-tone ribbon-mesh @ref Shape (a beam/bolt-style streak) from a polyline and
 *        register it in a shape-table slot.
 *
 * The shape-builder entry point.
 *
 * @note DEAD CODE: nothing in the shipped game calls this or its helpers (except @ref ts_isqrt_long);
 *       the builder survives only because SHAPEBLD.OBJ is directly linked.
 *
 * @param[in] slot        Shape-table slot to register the built @ref Shape in.
 * @param[in] vtxData     Near offset of the input vertex array in segment @p vtxSeg.
 * @param[in] vtxSeg      Segment of @p vtxData.
 * @param[in] vtxCount    Input vertex count; must be >= 3, otherwise returns NULL.
 * @param[in] ribbonWidth Ribbon half-width.
 * @param[in] color1      First fill color of the ribbon.
 * @param[in] color2      Second fill color of the ribbon.
 * @return    The built @ref Shape (also stored in @p slot), or NULL if @p vtxCount < 3 or the slot rejects it.
 */
extern Shape far *ts_build_shape(int slot, Vec3Long *vtxData, unsigned int vtxSeg, int vtxCount,
                                 int ribbonWidth, int color1, int color2);

#endif
