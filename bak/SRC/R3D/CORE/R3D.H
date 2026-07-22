#ifndef BAK_R3D_H
#define BAK_R3D_H

#include "structs.h"

/**
 * @file  R3D.H
 * @brief Fixed-point 3D renderer core (KRONDOR.EXE segment 0x233e).
 *
 * Actor/mesh transform pipeline: camera setup, rotation-matrix math, vertex
 * transform and perspective projection, near-plane and viewport polygon
 * clipping, shading, and rasterizer submission. Two fixed-point angle
 * conventions coexist: the rotation-matrix builder takes 512-steps-per-turn
 * angles, while the r3d_tbl_* trig entry points take 65536-units-per-turn
 * binary angles; matrices are Q14 (0x4000 == 1.0).
 *
 * Declarations marked "register convention" are near helpers whose real
 * arguments travel in registers; C cannot express that, so they are declared
 * void/empty here and their register interface is given in a @note.
 * Declaration order here is significant — append, never reorder.
 */

/* Whole degrees -> the renderer's binary angle (0x10000 per turn, 0x4000 == 90 deg). */
#define R3D_DEG(deg) ((short)((long)(deg) * 0x10000L / 360))

/* As R3D_DEG, but the unsigned binary angle (0..0xffff), for headings that are
 * carried and combined in unsigned form (where the >=180 deg half is positive). */
#define R3D_UDEG(deg) ((unsigned)((long)(deg) * 0x10000L / 360))

/**
 * Prepares one world-space visible entity for actor rendering by moving it
 * into the camera's coordinate frame. It copies the entity's orientation
 * angles into the rotation-matrix input buffer, subtracts the current camera
 * world position from the entity's world position to form the actor-relative
 * offset, rotates that offset through the camera view matrix to produce the
 * actor's camera-space X/Y/Z, and floors the camera-space Z at the projection
 * depth threshold so downstream projection never divides by a too-small
 * depth. The results are left in module scratch for the matrix-composition
 * and culling passes that follow.
 *
 * @note The (entry, entry_seg) pair is one far pointer split into offset and
 *       segment words; the caller passes (ptr, FP_SEG(ptr)).
 */
extern void r3d_setup_actor_in_camera_space(WorldObject *entry, unsigned short entry_seg);

/**
 * Assembles the transform that places one actor's mesh into camera space.
 * It converts the actor's orientation angles into a 3x3 rotation matrix,
 * combines that with the current camera view rotation to produce the
 * actor-to-camera matrix, and transposes a working copy for the vertex
 * transform. It then measures the actor's bounding extent in camera space,
 * chooses a renormalization shift that keeps magnitudes within fixed-point
 * headroom, and rescales the actor's camera-space origin and relative
 * position deltas by that shift so mesh vertex projection stays in range.
 * Finally it rotates the world directional-light vector
 * (g_vec3LightDirWorld) through the transposed actor matrix into
 * g_vec3LightDirObj, the object-space light direction the face shader dots
 * against per-face normals. All input and output flows through the shared
 * actor-transform globals.
 */
extern void r3d_compose_actor_camera_matrix(void);

/**
 * Computes the current actor mesh's camera-space forward depth and stores it
 * in the renderer state's LOD-Z field, which the actor-render path shifts and
 * compares against the depth threshold to choose a level-of-detail variant
 * and draw order. For a mesh flagged "simple" (header bit 0x20) the depth is
 * the actor origin's camera Z minus its bound half-extent; otherwise it
 * projects the object-space bounding-box intervals onto the camera-forward
 * axis, sums the nearest endpoints, rescales by the mesh scale shift, and
 * biases by the actor's camera Z.
 */
extern void r3d_actor_compute_lod_z(void);

/**
 * Back-face orientation test for mesh faces: computes the signed dot product
 * of two mesh vertices selected by index from the current mesh's vertex
 * table. The first indexed row is taken as-is (the face's normal vector);
 * the second is renormalized by the mesh scale residual and shifted into
 * camera space (a point on the face). The sign of the 32-bit result decides
 * whether a one-sided face is culled or a two-sided face has its normal
 * flipped toward the camera. The name reflects what it computes: a back-face
 * dot test between two index-selected vertices, with no projection.
 *
 * @note Register convention: AL = normal-vertex index (copied raw),
 *       AH = face-vertex index (scaled + origin-biased), ES:BP = vertex-table
 *       far base (6-byte rows). Returns the dot in DX:AX; callers test DX.
 */
extern long r3d_backface_dot_indexed(void);

/**
 * Renders one mesh part at full (LOD-0) detail: walks the part's polygon
 * list and, for each face, back-face-culls it, transforms and
 * perspective-projects each referenced vertex into screen space, and submits
 * the result to the rasterizer. Per-vertex transform and clip results are
 * memoized in module scratch keyed to the mesh's vertex pool, so vertices
 * shared between faces are projected once. Faces straddling the near plane
 * are near-Z clipped first, with a special case that emits flat textured
 * floor quads directly in one game mode. part_header points at a small
 * header: polygon count, then the offset of the 8-byte polygon-record array.
 */
extern void r3d_mesh_part_polygons(unsigned char far *part_header);

/**
 * Second pass of the mesh-polygon pipeline, run per polygon after its
 * vertices are transformed and clip-classified. For each vertex it copies
 * one coordinate pair into the polygon draw arrays: a projected vertex
 * contributes its screen (x, y); a vertex behind the near plane (which has
 * no valid projection) contributes its raw camera-space (x, z) instead, so
 * the near-clip interpolation step has real 3-D data to work from. If no
 * vertex qualifies as kept, the polygon is discarded by zeroing its vertex
 * count.
 *
 * @note Register convention: no arguments; reads/writes module globals only
 *       and preserves all registers.
 */
extern void near r3d_poly_emit_screen_or_world(void);

/**
 * Establishes the 3D camera transform for the current render frame from a
 * window's ViewContext descriptor. It copies the camera's world position
 * and view angles out of the window's WorldEntity into the renderer's
 * working camera state, derives the projection depth threshold and
 * color-remap table from the view's zoom and colorRemap fields, and
 * configures the viewport clip rectangle and center. It then builds the
 * world-to-view rotation matrix from the view angles: it first builds a
 * scratch rotation matrix from those angles, and if that matrix's type byte
 * reports it is non-identity it composes it with the actor rotation and
 * recovers the Euler view angles from the result; otherwise it takes the fast
 * path and builds the view matrix directly. Finally it stores the transposed
 * matrix used to rotate world geometry into view space.
 */
extern void r3d_camera_setup_view(ViewContext *widget);

/**
 * Sets the world-space directional-light vector used for mesh face shading.
 * It loads the two supplied angles into the first and third slots of the
 * rotation-matrix builder's Euler-angle input (the middle axis stays zero),
 * builds the 3x3 rotation matrix, and rotates the +Y unit vector through it,
 * caching the result in g_vec3LightDirWorld. Downstream,
 * r3d_compose_actor_camera_matrix rotates that world light vector into each
 * actor's object space and r3d_polygon_resolve_shade_color dots face normals
 * against it for the Lambert shade. The sole caller, ts_init, initializes
 * the sun direction once at table-store startup with a constant angle pair
 * (0x2000, -0x6000).
 *
 * @note The two angles are the light's elevation and azimuth: the first
 *       drives the builder's X slot and the second its Z slot; the middle
 *       Y axis is forced to zero.
 */
extern void r3d_light_set_direction(short elevation, short azimuth);

/**
 * Builds a 3x3 rotation matrix, in Q14 fixed point (0x4000 == 1.0), from a
 * three-component Euler-angle vector (X/pitch, Y/yaw, Z/roll over a 512-step
 * circle) and stores it into the caller's matrix, tagging it with a
 * classification byte that records whether it is an identity, a pure Z
 * (roll) rotation, or a full three-axis rotation. This is the renderer's
 * angle-to-orientation primitive; all trig goes through a code-resident
 * cosine table. Returns the pointer to the matrix it filled.
 */
extern Mat3x3 *r3d_build_rotation_matrix(int *angles, Mat3x3 *matrix);

/**
 * Decomposes a 3x3 rotation matrix into a triple of 16-bit fixed-point Euler
 * angles (0x10000 per turn, 0x4000 == 90 degrees) and writes them into the
 * caller's output triple. The pitch angle comes from an asin of one matrix
 * element and the other two from atan2 of matrix columns; at pitch == +/-90
 * degrees a gimbal-lock path zeroes one angle and folds the other two into a
 * single atan2. Used by camera setup to recover view angles from a composed
 * rotation matrix when the composed view matrix is non-identity. Returns the
 * output pointer.
 */
extern int *r3d_matrix_to_euler(Mat3x3 *matrix3x3, int *out_xyz);

/**
 * Transposes a 3x3 fixed-point rotation matrix in place, swapping the three
 * off-diagonal element pairs and leaving the diagonal and the type byte
 * unchanged. Because the renderer's orientation matrices are orthonormal,
 * the transpose is also the inverse, so this is how the pipeline turns a
 * view or actor rotation into its inverse. The matrix pointer is returned
 * for convenience but every caller uses the buffer in place.
 */
extern Mat3x3 *r3d_matrix3x3_transpose(Mat3x3 *m);

/**
 * Composes two Q14 3x3 rotation matrices, writing pMatOut = pMatA * pMatB
 * and returning pMatOut. Each output element is the dot of a row of A with a
 * column of B, accumulated at 32-bit precision and rescaled to Q14. The
 * per-matrix type tag selects fast paths (identity operands are copied
 * through; pure z-rotations touch only the 2x2 block), and the result's tag
 * records the least-specialized form. Used to fold an actor's rotation into
 * the camera view rotation.
 */
extern Mat3x3 far *r3d_matrix3x3_multiply(Mat3x3 far *pMatA, Mat3x3 far *pMatB,
                                          Mat3x3 far *pMatOut);

/**
 * Applies a 3x3 fixed-point rotation matrix to a 3-component 16-bit vector,
 * producing the transformed 16-bit vector. The matrix's type byte selects a
 * fast path: identity copies the vector through, a planar (z-rotation) type
 * rotates X and Y and passes Z straight through, and anything else performs
 * the full transform. Each output component is a Q14 dot product accumulated
 * at 32 bits and rescaled. This is the core short-precision vector-rotation
 * primitive of the renderer.
 *
 * @note Register convention: AX = &input vec3 (short[3]), BX = &Mat3x3,
 *       CX = &output vec3 (short[3]).
 */
extern void near r3d_matrix3x3_transform_vec3(void);

/**
 * Applies a 3x3 orientation matrix to a 3-component integer vector, writing
 * the rotated vector to a caller-supplied output buffer and returning that
 * buffer. This is the stack-argument entry point used by the projection and
 * world-space routines; it forwards its three pointers to the
 * register-convention transform kernel. Used throughout the game to move
 * points between world and camera/view space.
 */
extern int *r3d_mat3_xform_vec3_wrap(int *vec, Mat3x3 *matrix, int *out_vec);

/**
 * Resolves and stores the outline/fill color pair used to draw the current
 * mesh polygon. It selects the polygon's two color bytes according to the
 * active render state, marks whether the face is filled, and — for filled,
 * shadeable faces whose material id is in range — applies a light ramp by
 * dotting the face normal against the object-space light direction
 * (g_vec3LightDirObj) and looking the
 * result up in the lighting table. The chosen colors pass through the active
 * palette remap table before being written into the graphics context.
 *
 * @note Register convention: ES:DI = polygon face record, BP = per-mesh
 *       normal-table base. Falls through into
 *       r3d_polygon_resolve_shade_color_lit; the two labels form one routine
 *       with a single return.
 */
extern void near r3d_polygon_resolve_shade_color(void);

/**
 * The lit continuation of r3d_polygon_resolve_shade_color — NOT an
 * independently called function; control reaches it only by fall-through
 * once a valid material id (1..8) is in hand (the two labels share a single
 * return, and nothing ever calls this label directly). It fetches the face's
 * normal from the per-mesh normal table (negating it when the mesh normal is
 * flipped), dots it against the object-space light direction
 * (g_vec3LightDirObj) to derive a shade level, indexes the lighting-ramp LUT
 * by material and shade to produce the shaded fill color, and stores the
 * final remapped outline/fill pair into the graphics context.
 *
 * @note Register convention: AX = material id, ES:DI = face record,
 *       BP = normal-table base, CL/CH = outline/fill colors.
 */
extern void near r3d_polygon_resolve_shade_color_lit(void);

/**
 * Submits the current mesh polygon to the rasterizer: copies the polygon's
 * projected screen X and Y vertices from the renderer's scratch arrays into
 * the graphics context's polygon buffers, records the vertex count, and
 * hands the polygon to the sky/fill draw dispatcher, which performs either a
 * textured sky-strip fill or a plain filled-polygon draw depending on the
 * active texture mode. Invoked at the end of each polygon's clipping
 * pipeline; does nothing when the polygon has no vertices.
 *
 * @note Register convention: no arguments; globals in, far draw call out.
 */
extern void near r3d_polygon_submit_to_rasterizer(void);

/**
 * Submits the current mesh polygon to the world textured-quad renderer, but
 * only when it is a quadrilateral (exactly four vertices); other polygons
 * are silently skipped. It copies the projected screen coordinates into the
 * graphics context's vertex buffers, selects the polygon's texture index
 * from its day or night slot according to the render-state flag, and
 * dispatches to the textured-quad draw path.
 *
 * @note Register convention: ES:DI = current polygon record.
 */
extern void near r3d_polygon_submit_textured_quad(void);

/**
 * Scales two 32-bit fixed-point values in place by a signed ratio, using a
 * normalize-then-divide long-division kernel that keeps extra fractional
 * precision, avoiding the overflow a naive multiply-then-divide would risk.
 * It is the shared perspective-divide and edge-interpolation primitive:
 * callers use it to project camera-space coordinates to the screen, to
 * compute an actor's projection scale, and to find clip-edge intersections.
 *
 * @note Non-C ABI, called via hand-written push/pop marshaling only (hence
 *       the empty parens — do not "fix" to (void) or call from C). Stack
 *       frame: [BP+4]=long A, [BP+8]=long B (both value-result, scaled in
 *       place), [BP+12]=long P, [BP+16]=long Q; computes A*=Q/P, B*=Q/P.
 *       When |Q| >= |P| (by high-word compare) A and B are left UNTOUCHED;
 *       |Q| == |P| applies sign only.
 */
extern void near r3d_ldiv_helper();

/**
 * Rotates one mesh vertex from object space into actor space using the
 * actor's type-tagged 3x3 matrix, producing an extended-precision result:
 * each transformed component is a full 32-bit fixed-point integer in the
 * caller's out triple plus a 16-bit fractional residue left in the
 * g_matXOut/g_matYOut/g_matZOut globals, additionally scaled by the current
 * mesh scale shift. Identity and planar matrix types take fast paths. This
 * is the high-precision per-vertex transform of the LOD-1/2 mesh renderer;
 * the short-output sibling is r3d_matrix3x3_transform_vec3.
 *
 * @note Register convention: AX = &vec (int16[3]), BX = &Mat3x3,
 *       CX = &out (long[3]). The pseudo-parameters document the registers.
 */
extern void near r3d_mat3_xform_vec3_long(int *vec, Mat3x3 *matrix, long *out);

/**
 * Renders one mesh part's polygon list for the reduced levels of detail
 * (LOD 1 and 2), using extended 32-bit fixed-point arithmetic throughout.
 * Like its LOD-0 sibling r3d_mesh_part_polygons it walks the 8-byte face
 * records, back-face-culls, transforms and projects vertices with a
 * per-vertex cache, near-clips crossing faces, and submits survivors to the
 * rasterizer — but it transforms through the long-precision matrix routine,
 * accumulates camera coordinates as full 32-bit longs, divides via the
 * long-division helper, and omits the LOD-0 textured-quad special cases.
 * The near-Z and viewport clippers it calls are chosen by LOD (1 vs 2).
 */
extern void r3d_mesh_polygons(unsigned char far *part_header);

/**
 * Renders one mesh part's polygon list at LOD 3, the simplest of the three
 * LOD dispatch targets: back-face cull, 16-bit camera-space transform,
 * perspective divide with a per-vertex clip cache, and submission of each
 * surviving face as a textured quad or flat-shaded polygon. Unlike the
 * LOD-0 producer it omits the near-Z clip path and floor-tile special case;
 * unlike the LOD-1/2 producer it uses 16-bit rather than 32-bit camera
 * coordinates. The argument has the same layout as the siblings' part
 * header: polygon count, then the polygon-record array offset.
 */
extern void r3d_mesh_part_polygons_lod3(unsigned short far *part_header);

/**
 * Maps a projected 2D point into screen space in place: adds the viewport
 * center X to the point's X component and replaces the Y component with
 * viewport-center-Y minus Y, flipping the axis so screen Y grows downward.
 * The point is a pair of 32-bit fixed-point longs; anything following is
 * untouched. Returns the same pointer. Called right after the perspective
 * divide to turn projected actor-bound coordinates into clip-test
 * coordinates.
 */
extern long *r3d_vec2_long_translate_yflip(long *pt);

/**
 * Perspective-projects a 2D vector: both numerators from *args are scaled by
 * the fixed-point ratio viewDistance / depth (the projection threshold over
 * args->nDenom) via the shared long divide helper, and the two results are
 * written to out->nProjX and out->nProjY. This is the standard
 * screen = coordinate * distance / depth projection. Returns out.
 */
extern PerspDiv2Result *r3d_vec2_perspective_divide(PerspDiv2Args *args, PerspDiv2Result *out);

/**
 * Computes an actor's screen-space projection scale as the fixed-point ratio
 * nNumX * viewDistance / nDenom: the caller supplies the actor's mesh
 * half-extent as nNumX and a clamped camera-space depth as nDenom, so the
 * result shrinks with distance. The caller clamps the returned long to
 * 0x100 and stores it as the actor's projection scale; zero means the actor
 * is culled. Only the nNumX and nDenom fields of the shared PerspDiv2Args
 * are consulted.
 */
extern long r3d_actor_proj_scale_compute(PerspDiv2Args *args);

/**
 * Computes the full 32-bit signed product of two 16-bit integers. Unlike a
 * plain C int multiply, which keeps only the low 16 bits, this returns all
 * 32, so callers can multiply coordinates by fixed-point sine/cosine values
 * and shift the result down without overflow. No shifting, rounding, or
 * saturation is performed here.
 */
extern long r3d_imul_full32(int a, int b);

/**
 * Computes a mixed-precision 3-element dot product: three 16-bit signed
 * coefficients against a vector of three 32-bit signed longs, each term a
 * full 16x32 product, accumulated at 48 bits. Returns the upper 32 bits of
 * the total, and skips the third term when its coefficient is zero. Used by
 * r3d_mat3_xform_vec3_ll to transform a long-precision point by each row
 * of a 16-bit rotation matrix; r3d_dot3_long is the plain 16x16 sibling.
 *
 * @note Register convention: AX/CX/DX = the three coefficients, BX = near
 *       pointer to the long[3] vector. Result in DX:AX.
 */
extern long near r3d_dot3_coeff16_vec32(void);

/**
 * Transforms a vec3 of signed 32-bit fixed-point longs by a 3x3 matrix of
 * Q14 shorts, writing three longs to the output vector. The matrix's type
 * byte selects the work: identity copy, two-row planar transform with Z
 * passed through, or the full three-row transform; each component is a
 * signed dot product renormalized by a fixed shift. The "_ll" suffix marks
 * the long-in/long-out variant of the mat3_xform_vec3 family. Its one use is
 * rotating an actor's world-relative position into camera space with the
 * view matrix — the routine itself is a general long-vector transform.
 *
 * @note Register convention: AX = &inVec (long[3]), BX = &matrix
 *       (9 shorts + type byte), CX = &outVec (long[3]).
 */
extern void near r3d_mat3_xform_vec3_ll();

/**
 * Clips the current mesh polygon against the 2D viewport rectangle with a
 * two-pass Sutherland-Hodgman sweep — left/right edges first, then
 * top/bottom — over the already-projected 16-bit screen vertex arrays,
 * rewriting them and the shared vertex count in place. Runs as a final
 * scissor before rasterization when actor viewport clipping is enabled.
 * The name reflects what it does: a screen-space rectangle scissor, unlike
 * the genuine depth clippers (r3d_polygon_clip_near_z and friends).
 *
 * @note Register convention: no arguments; polygon arrays and
 *       g_graphics_context clip bounds in, arrays + count out.
 */
extern void near r3d_polygon_scissor_2d();

/**
 * Interpolates the edge between two camera-space vertices onto the depth
 * clip plane and writes the crossing point's projected coordinates into the
 * clipped vertex's screen slots. The vertex being clipped has its X and Z
 * linearly interpolated toward the other endpoint by the fraction of the
 * depth span that reaches the clip threshold. This is the 16-bit variant;
 * r3d_interp_vertex_at_zclip_long does the same over the 32-bit arrays.
 *
 * @note Register convention: SI = other-endpoint offset, BX = offset of the
 *       vertex to clip (both index*2); writes g_aVertexScrX/Y[BX].
 */
extern void near r3d_interp_vertex_at_zclip(void);

/**
 * Clips the current mesh polygon against the near depth plane using a
 * Sutherland-Hodgman walk over its vertex ring (16-bit path). Edges fully
 * in front pass their vertex through; an edge entering the visible
 * half-space emits the interpolated intersection plus the current vertex;
 * an edge leaving emits only the intersection; fully-behind edges emit
 * nothing. The clipped outline and its new vertex count replace the
 * polygon's screen-space vertex list.
 *
 * @note Register convention: no arguments; operates on the module's polygon
 *       ring, clip-state, and screen-coordinate globals.
 */
extern void near r3d_polygon_clip_near_z(void);

/**
 * Biases the current polygon's projected screen vertices into viewport
 * space in place: X gains the viewport center X, and Y becomes
 * viewport-center-Y minus Y (the math-to-screen Y flip), over the module's
 * two parallel 16-bit vertex scratch arrays. Returns immediately when the
 * vertex count is zero. The _long sibling performs the same transform on
 * 32-bit split-word coordinates.
 *
 * @note Register convention: no arguments.
 */
extern void near r3d_apply_viewport_offset();

/**
 * Clips one polygon edge against a vertical viewport boundary (left or
 * right, selected by the outcode bits) inside r3d_clip_polygon_to_viewport's
 * Sutherland-Hodgman loop. It writes the boundary X into the output vertex
 * and linearly interpolates the corresponding Y along the edge, in 32-bit
 * split-word fixed point with 16-bit intersection math. Emits nothing when
 * neither X bit is set.
 *
 * @note Register convention: CL = outcode (bit0 xmin, bit1 xmax),
 *       BP = inside-vertex offset, SI = outside-vertex offset, DI = output
 *       slot offset (advanced by 2 on emit).
 */
extern void near r3d_clip_interp_x_edge(void);

/**
 * Clips one polygon edge against a horizontal viewport boundary (top or
 * bottom, selected by the outcode bits), the exact mirror of
 * r3d_clip_interp_x_edge: it fixes Y at the boundary and interpolates X
 * along the edge in 32-bit split-word fixed point. Emits nothing when
 * neither Y bit is set.
 *
 * @note Register convention: CL = outcode (bit3 ymin, bit2 ymax),
 *       BP = inside-vertex offset, SI = outside-vertex offset, DI = output
 *       slot offset (advanced by 2 on emit).
 */
extern void near r3d_clip_interp_y_edge();

/**
 * Clips the current mesh polygon against the four viewport edges by running
 * Sutherland-Hodgman in two passes — x bounds, then y bounds — rewriting the
 * polygon in place and updating its vertex count, with an early-out that
 * copies the first pass's result back when fewer than two vertices survive.
 * Vertices are 32-bit fixed point in parallel low/high word arrays;
 * intersections come from the 16-bit-math edge helpers. Selected by the
 * LOD-1/2 mesh renderer when the LOD is 1; r3d_polygon_clip_rect_2d handles
 * the other case with higher-precision intersection math.
 *
 * @note Register convention: no arguments; same clip bounds
 *       (g_graphics_context.nClip_*) as the other viewport clippers.
 */
extern void near r3d_clip_polygon_to_viewport(void);

/**
 * Interpolates one vertex of a mesh polygon onto the depth clip plane using
 * the full 32-bit camera-space arrays: it computes the fraction of the depth
 * span from the anchor vertex to the clip threshold and applies it to the X
 * and Z spans, storing the crossing point into the anchor vertex's 32-bit
 * screen slots. Long-precision counterpart of r3d_interp_vertex_at_zclip,
 * called by the LOD-1 near-plane clipper on crossing edges.
 *
 * @note Register convention: BP = anchor vertex offset (receives the
 *       result), SI = far vertex offset.
 */
extern void near r3d_interp_vertex_at_zclip_long(void);

/**
 * Clips the current mesh polygon against the near depth plane for the
 * 32-bit (LOD-1) render path: a Sutherland-Hodgman walk over the vertex
 * ring that keeps in-front vertices, inserts interpolated intersections via
 * r3d_interp_vertex_at_zclip_long wherever an edge crosses the plane, and
 * appends results as 32-bit lo/hi pairs to the output arrays, rewriting the
 * vertex count. The 16-bit counterpart is r3d_polygon_clip_near_z; the
 * LOD-2 twin is r3d_polygon_clip_near_z_lod2.
 *
 * @note Register convention: no arguments.
 */
extern void near r3d_polygon_clip_against_zplane();

/**
 * Intersects one polygon edge with a vertical viewport clip line inside
 * r3d_polygon_clip_rect_2d's loop, appending the clipped vertex to the
 * output buffer. Bit 0 of the flag byte selects the left boundary, bit 1
 * the right; neither set is a no-op. The output vertex takes the boundary X
 * directly, and its Y is interpolated along the edge through the 32-bit
 * muldiv helper, stored as split low/high words.
 *
 * @note Register convention: CL = clip flags, BP = origin-endpoint offset,
 *       SI = other-endpoint offset, DI = output cursor (advanced by 2).
 */
extern void near r3d_polygon_clip_edge_intersect(void);

/**
 * Clips one polygon edge against the top or bottom viewport clip line
 * inside r3d_polygon_clip_rect_2d's loop — the Y-axis counterpart of
 * r3d_polygon_clip_edge_intersect. The fixed Y comes from the ymin or ymax
 * bound (outcode bits 3/2), the X is interpolated at that crossing through
 * the 32-bit muldiv helper, and the pair is appended to the output buffer
 * as split low/high words.
 *
 * @note Register convention: CL = clip flags, BP = prev-vertex offset,
 *       SI = cur-vertex offset, DI = output cursor (advanced by 2).
 */
extern void near r3d_clip_polygon_edge_y(void);

/**
 * Clips the working polygon to the 2D screen clip rectangle with two-pass
 * Sutherland-Hodgman — x bounds then y bounds of g_graphics_context.nClip_*
 * — rewriting the 32-bit split-word vertex arrays and the vertex count in
 * place, with the same fewer-than-two-vertices early-out as its sibling.
 * Edge crossings are delegated to the 32-bit muldiv helpers
 * (r3d_polygon_clip_edge_intersect / r3d_clip_polygon_edge_y). It is the
 * alternative to r3d_clip_polygon_to_viewport, selected by the LOD-1/2 mesh
 * renderer when the LOD is not 1; both clip the identical rectangle.
 *
 * @note Register convention: no arguments.
 */
extern void near r3d_polygon_clip_rect_2d(void);

/**
 * Computes the near-clip-plane intersection of one polygon edge in the
 * 32-bit split-word vertex path — the long-precision counterpart of
 * r3d_interp_vertex_at_zclip. It forms the fraction of the edge's depth
 * span that reaches the clip threshold, scales the edge's X and Z deltas by
 * it through the long divide helper, and adds them to the reference vertex,
 * writing the crossing point into that vertex's screen-coordinate slots.
 * Used only by the LOD-2 near-plane clip pass, whose two call sites swap
 * the register roles to steer which endpoint receives the result.
 *
 * @note Register convention: BP = reference-vertex offset (receives the
 *       result), SI = other-endpoint offset.
 */
extern void near r3d_poly_clip_calc_isect(void);

/**
 * Performs the in-place near-plane clip pass over the current mesh
 * polygon's vertex ring for the LOD-2 path: a Sutherland-Hodgman walk that
 * keeps vertices in front of the plane, drops those marked behind it
 * (clip-state 3), and inserts boundary intersections computed by
 * r3d_poly_clip_calc_isect where edges cross, updating the vertex count.
 * It is the structural twin of r3d_polygon_clip_against_zplane, differing
 * only in the intersection helper used. The name parallels that twin: this
 * is the LOD-2 near-Z clip pass (the drop condition is the internal
 * clip-state value 3 for behind-the-plane vertices).
 *
 * @note Register convention: no arguments.
 */
extern void near r3d_polygon_clip_near_z_lod2(void);

/**
 * Applies the viewport center to every projected screen vertex of the
 * polygon batch in the 32-bit path: X gains the viewport center X and Y
 * becomes viewport-center-Y minus Y, computed as full 32-bit adds and
 * subtracts across the split low/high word arrays. Processes the shared
 * vertex count in place; returns immediately when it is zero. The 16-bit
 * sibling is r3d_apply_viewport_offset.
 *
 * @note Register convention: no arguments.
 */
extern void near r3d_apply_viewport_offset_long(void);

/**
 * Returns the sine of a 16-bit binary angle as a Q14 short (0x4000 == 1.0),
 * where a full turn spans 65536 angle units. It reads the module's shared
 * cosine lookup table with a quarter-turn phase shift (sin x == cos(x - 90
 * degrees)); the angle wraps naturally, so negative and out-of-range values
 * are fine.
 */
extern short r3d_tbl_sin(int angle);

/**
 * Returns the cosine of a 16-bit binary angle as a Q14 short (0x4000 ==
 * 1.0), read directly from the module's shared cosine lookup table with
 * half-period folding, so cos(-x) == cos(x) holds and any angle wraps
 * naturally. Full turn = 65536 angle units. r3d_tbl_sin shares the same
 * table via a phase shift.
 */
extern short r3d_tbl_cos(int angle);

/**
 * Computes the arcsine of a Q14 sine value (0x4000 == 1.0) by table lookup,
 * returning a signed 16-bit binary angle where 0x4000 == 90 degrees.
 * Negative inputs are reflected so the result carries the input's sign.
 * Inputs outside [-1.0, 1.0] are not clamped and index past the table, so
 * callers must pass a normalized value (e.g. a rotation-matrix element).
 */
extern int r3d_tbl_asin(int sin_value);

/**
 * Computes the four-quadrant arctangent of y and x, returning the vector's
 * direction as a 16-bit binary angle (full circle 0x10000, 0x4000 == 90
 * degrees). Standard atan2(y, x) convention: 0 along +x, 0x4000 along +y,
 * counterclockwise, with (0, 0) returning 0. Derived from the first-octant
 * arctangent table with sign/octant folding.
 */
extern int r3d_tbl_atan2(int y, int x);

/**
 * Returns one raw entry from the renderer's first-octant arctangent table:
 * idx quantizes a tangent ratio in [0, 1) into 512 steps, and the entry is
 * a binary angle in 0x000..0x1ff. Callers form the index as
 * (smaller << 9) / larger and do all octant and sign folding themselves; no
 * bounds check is performed.
 */
extern short r3d_tbl_atan_lookup_raw(int idx);

/**
 * Computes the signed 3-element dot product of two 16-bit vectors,
 * returning a 32-bit long so no precision is lost: three signed 16x16
 * products summed with full 32-bit addition. Callers use the wide result
 * whole or test its high word — e.g. for the light-ramp shade or the sign
 * of a projected normal.
 *
 * @note Register convention: AX = &a, BX = &b (the pseudo-parameters
 *       document the registers). Result in DX:AX.
 */
extern long near r3d_dot3_long(int *a, int *b);

/**
 * Far-callable entry for the signed 32-bit dot product of two 3-element
 * short vectors: a thin thunk that forwards its two pointers to
 * r3d_dot3_long and adds no arithmetic. The actor mesh-part sorter uses it
 * to derive a depth-ordering key from a part's anchor and edge vertices.
 */
extern long r3d_dot3_long_far(int *pVecA, int *pVecB);

#endif
