#ifndef BAK_SHAPETBL_H
#define BAK_SHAPETBL_H

#include "structs.h"

extern unsigned char g_lightDirNotInit;
extern int g_shapeTableCount;
extern int g_shapeOverrideLen;

/**
 * @file  SHAPETBL.H
 * @brief Table Store: loads and serves @ref Shape records from .TBL `DAT:` chunks.
 *
 * Owns the @ref ShapeTable slot array (@ref g_shapeTables), addresses individual @ref Shape
 * records by a global index across all slots (@ref ts_get_shape / @ref ts_set_shape), and
 * provides the sprite-bank and @ref ViewContext view-creation helpers the render path uses.
 */


/**
 * @brief One model record from a .TBL `DAT:` chunk — classifier, 3D mesh, and optional bounds.
 *
 * Variable-length record for a single model, addressed by a global index across the loaded
 * @ref ShapeTable slots (see @ref ts_get_shape). The fixed fields run through @ref radius (offset 0xc);
 * the mesh that follows is reached by *following* @ref lodArray, so the record has no fixed
 * size — never assume a prefix length.
 *
 * Animated models (combat billboard sprites, the boom explosion, animated props) additionally
 * carry a per-animation-group frame-count table (@ref animGroupCount / @ref animFrameCounts):
 * animFrameCounts[gid] is the frame count of visibility-group @c gid. It is an authoring-side
 * precompute that duplicates @c MeshPartRecord::nField6 (TBD-ref: the field is undocumented in STRUCTS.H) (the per-part variant count the renderer
 * actually uses) and has no surviving runtime reader — its only accessors,
 * @ref ts_get_anim_group_count and @ref ts_get_anim_frame_count, are never called. Non-animated
 * models leave @ref animGroupCount at 0.
 *
 * Inner pointers (@ref animFrameCounts, @ref lodArray) are near offsets resolved against the
 * record's own segment: MK_FP(FP_SEG(record), offset).
 *
 * @note The declared 26-byte size is the maximum, AABB-present form. Records without an AABB
 *       occupy a 14-byte fixed prefix (through @ref radius) and are equally valid; nothing
 *       parses the record by size, only by following @ref lodArray.
 */
struct Shape {
    /** 0x00, 1B: flag bits; 0x40 = depth-sort mesh parts (rest authoring-time, unread). */
    unsigned char flags;

    /** 0x01, 1B: model archetype/behavior class; raw dispatch-table index. */
    unsigned char kind;

    /** 0x02, 1B: mesh depth-sort key; doubles as collision flat-flag in the proximity view. */
    unsigned char priority;

    /** 0x03, 1B: binary scale exponent; forms `radius << shift`. */
    unsigned char shift;

    /** 0x04, 2B: animation-group count (maxGroupId+1); 0 for non-animated models. */
    int animGroupCount;

    /** 0x06, 2B near: per-group frame counts (animFrameCounts[gid]); precompute, unread — see brief. */
    unsigned char *animFrameCounts;

    /** 0x08, 2B: LOD-descriptor count. */
    short lodCount;

    /** 0x0A, 2B near: LOD-descriptor array. */
    void *lodArray;

    /** 0x0C, 2B: signed bounding half-extent; `radius << shift` = cull/LOD extent. */
    short radius;

    /** 0x0E, 6B: bbox min; runtime-built meshes only, unread by render/collision. */
    Vec3Short aabbMin;

    /** 0x14, 6B: bbox max; present with aabbMin. */
    Vec3Short aabbMax;
};


/** 6B LOD descriptor — @ref Shape::lodArray points to @ref Shape::lodCount of these; the renderer
 *  picks the first whose @ref LodDescriptor::nThreshold >= the projected actor scale (last entry = fallback). */
struct LodDescriptor {
    short nThreshold;            /**< +0x0 selected when projScale <= threshold (last = fallback) */
    short nPartCount;            /**< +0x2 number of @ref MeshPartRecord */
    unsigned short wPartBaseOff; /**< +0x4 near offset to the @ref MeshPartRecord array */
};


typedef struct ShapeTable ShapeTable;

/**
 * @brief One table-store slot: a loaded group of Shape records plus its render tuning.
 *
 * The world keeps a small fixed array of these (@ref g_shapeTables); each slot owns the
 * models loaded from one .TBL chunk (zone geometry, combat models, ...). @ref ts_get_shape and
 * @ref ts_set_shape address individual models by a global index that runs across all slots.
 *
 * @note @ref scale, @ref scaleClamp and @ref spriteBank are read on the render path but
 *       no loader ever assigns them off their defaults (0x100 / 0x100 / -1), so their
 *       non-default branches stay inert. Treat them as reserved tuning hooks, not live state.
 */
struct ShapeTable {
    Shape far *far
    *records;  /**< 0-terminated table of far pointers to this slot's @ref Shape records. */
    int count; /**< Number of records in @ref records. */
    int scale; /**< Q8 actor projection-scale multiplier (0x100 = x1.0); -1 forces @ref scaleClamp. */
    int scaleClamp; /**< Upper clamp on the projected actor scale (also the exact value used when @ref scale is -1). */
    int spriteBank; /**< Index into @c g_spriteBanks (TBD-ref: GLOBALS.H lacks a file block) for billboard images; -1 = fetch them from the global paged image array (@c worldrender_paged_array_get (TBD-ref: WORLDRND.H lacks a file block)) instead. */
};


/** Q8 unity scale (x1.0): the default for @ref ShapeTable::scale and @ref ShapeTable::scaleClamp. */
#define SHAPE_SCALE_UNITY 0x100

extern ShapeTable *g_shapeTables;


/**
 * @brief Whole-store override: one flat table serving the entire shape index space.
 *
 * When non-null, @ref ts_get_shape and @ref ts_set_shape take every lookup from this single
 * 0-terminated table of far @ref Shape pointers (bounded by @c g_shapeOverrideLen (TBD-ref: canonical extern in GLOBALS.H, which lacks a file block))
 * and the per-slot walk over @ref g_shapeTables is never reached. The layout is
 * exactly a @ref ShapeTable::records table, so one loaded `DAT:` chunk can
 * drive the whole store without any slot configured.
 *
 * @note Dormant: nothing ever assigns the pair, so both stay 0 and every
 *       lookup takes the slot walk.
 */
extern Shape far *far *g_shapeOverride;


/**
 * @brief Allocate and reset the table store: @ref ShapeTable slots plus sprite banks.
 *
 * Sizes the two global slot arrays — @ref g_shapeTables (one @ref ShapeTable per loadable
 * .TBL chunk, filled by @ref ts_load_shape_tbl) and @c g_spriteBanks (TBD-ref: GLOBALS.H lacks a file block)
 * (billboard image tables, filled by @c worldrender_table_load (TBD-ref: WORLDRND.H lacks a file block)) —
 * and resets every slot to its empty defaults:
 * no records, @ref ShapeTable::scale / @ref ShapeTable::scaleClamp at 0x100,
 * @ref ShapeTable::spriteBank at -1 (the same state @ref ts_free_shape_tbl restores).
 *
 * The very first call also sets the R3D light direction to its default
 * (+45°, -135°); a one-shot latch keeps later re-inits from touching the light.
 *
 * @param[in] shapeTableCapacity Number of @ref ShapeTable slots; clamped to >= 1.
 *                               The zone subsystem uses 3 (zone / combat / town-interior).
 * @param[in] spriteBankCapacity Number of sprite-bank slots; clamped to >= 1.
 * @warning   Panics if either slot array cannot be allocated.
 * @see       @ref ts_shutdown, which frees both arrays.
 */
extern void ts_init(int shapeTableCapacity, int spriteBankCapacity);


/**
 * @brief Free the table store; counterpart of @ref ts_init.
 *
 * Releases only the slot arrays, not their contents — every loaded slot must
 * already be freed (@ref ts_free_shape_tbl, @c worldrender_table_unload (TBD-ref: WORLDRND.H lacks a file block)).
 */
extern void ts_shutdown(void);


/**
 * @brief Load a .TBL resource's `DAT:` chunk into shape-table slot @p tblIdx.
 *
 * Fills the slot with the chunk's @ref Shape records (tuning fields at their
 * defaults) and returns the record table, or 0 if the resource can't be read.
 * Does not free a previously loaded slot — pair with @ref ts_free_shape_tbl.
 *
 * @param[in] tblIdx Slot to fill, 0..capacity-1 from @ref ts_init; not bounds-checked.
 * @param[in] fname  Resource filename of the .TBL to read (e.g. "combat.tbl").
 */
extern Shape far *far *ts_load_shape_tbl(int tblIdx, char *fname);


/**
 * @brief Unload shape-table slot @p tblIdx; inverse of @ref ts_load_shape_tbl.
 *
 * The slot's @ref Shape records are freed and the slot is left empty, ready to
 * be reloaded.
 *
 * @param[in] tblIdx Slot to unload, 0..capacity-1 from @ref ts_init; not bounds-checked.
 */
extern void ts_free_shape_tbl(int tblIdx);


/**
 * @brief Fetch the Shape at global index @p shapeIdx; read counterpart of @ref ts_set_shape.
 *
 * @param[in] shapeIdx Global shape index across all loaded slots; a running index that
 *                     spans slot 0, then slot 1, and so on.
 * @return    Far pointer to the @ref Shape, or 0 if @p shapeIdx is out of range.
 */
extern Shape far *ts_get_shape(int shapeIdx);


/**
 * @brief Replace the Shape at global index @p shapeIdx; write counterpart of @ref ts_get_shape.
 *
 * @param[in] shapeIdx Global shape index across all loaded slots (same index space
 *                     as @ref ts_get_shape); out of range writes nothing.
 * @param[in] shape    Far pointer to store; kept as-is, never dereferenced.
 * @return    @p shape on success, or 0 if @p shapeIdx is out of range.
 */
extern Shape far *ts_set_shape(int shapeIdx, Shape far *shape);


/**
 * @brief Allocate a full-screen @ref ViewContext bound to @p camera — a new 3D view of the world.
 *
 * Builds the render context the R3D engine reads each frame (@ref r3d_camera_setup_view): a
 * full-screen VGA viewport at default zoom, no extra view rotation, and the optional
 * face-material / color-remap tables left null (zone/render setup fills those in later).
 *
 * @param[in] camera Entity whose position and orientation the view renders from; stored by
 *                   reference (not copied), so it must outlive the returned context.
 * @return    The new far-heap @ref ViewContext, or NULL if allocation fails.
 * @see       @ref ts_my_free, which releases it.
 */
extern ViewContext *ts_create_fullscreen_view(WorldEntity *camera);


/**
 * @brief Far-callable free for a far-heap allocation; thin wrapper over @c my_free (TBD-ref: FARTHUNK.H lacks a file block).
 *
 * Used to release a @ref ViewContext from @ref ts_create_fullscreen_view (its callers free
 * @c g_world_widget / @c g_active_window (TBD-ref: GLOBALS.H lacks a file block)), but frees any far-heap pointer.
 *
 * @param[in] ptr Pointer previously returned by the far allocator (@c my_malloc (TBD-ref: FARTHUNK.H lacks a file block) and friends).
 */
extern void ts_my_free(void *ptr);


/**
 * @brief Animation-group count of the Shape at global index @p shapeIdx (@ref Shape::animGroupCount).
 *
 * Returns maxGroupId+1 for animated models, 0 otherwise. Reads the authoring-side precompute
 * described in the @ref Shape brief — retained for completeness, but never actually called.
 *
 * @param[in] shapeIdx Global shape index (same space as @ref ts_get_shape); out of range yields 0.
 * @return    Animation-group count, or 0 if @p shapeIdx is invalid or the model is not animated.
 */
extern int ts_get_anim_group_count(int shapeIdx);


/**
 * @brief Frame count of animation group @p groupId for the Shape at global index @p shapeIdx.
 *
 * Reads @ref Shape::animFrameCounts at [@p groupId]. Like @ref ts_get_anim_group_count, it consults
 * the unused authoring-side precompute; the renderer uses @c MeshPartRecord::nField6 (TBD-ref: the field is undocumented in STRUCTS.H) instead.
 *
 * @param[in] shapeIdx Global shape index (same space as @ref ts_get_shape); out of range yields 0.
 * @param[in] groupId  Animation-group id, 0..animGroupCount-1; out of range yields 0.
 * @return    Frame count for the group, or 0 if @p shapeIdx or @p groupId is out of range.
 */
extern int ts_get_anim_frame_count(int shapeIdx, int groupId);


/**
 * @brief Model-space bounding half-extent of the Shape at @p shapeIdx (`radius << shift`); never called.
 *
 * @param[in] shapeIdx Global shape index (same space as @ref ts_get_shape); out of range yields 0.
 * @return    Scaled half-extent (0 if @p shapeIdx is invalid).
 */
extern long ts_get_scaled_radius(int shapeIdx);


/**
 * @brief Binary scale exponent (`shift`) of the Shape at @p shapeIdx — the power-of-two factor @ref ts_get_scaled_radius applies to the radius; never called.
 *
 * @param[in] shapeIdx Global shape index (same space as @ref ts_get_shape); out of range yields 0.
 * @return    The shift exponent, or 0 if @p shapeIdx is invalid.
 */
extern int ts_get_shift(int shapeIdx);

#endif
