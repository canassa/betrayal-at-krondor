// TBL model -> THREE.Object3D builder.
//
// BaK world is Z-up; three.js is Y-up. We wrap everything in a group rotated
// -PI/2 about X so BaK +Z becomes three.js +Y.
//
// Polygon flags (R3D.ASM):
//   bits 0-1  type: 0 two-sided, 1/3 one-sided, 2 skip (POLY_TYPE_SKIP)
//   bit 0x10  POLY_FLAG_TEXTURED — day/night bytes are a texture index, not a
//             fill color; the face is drawn as a textured quad
//   bit 0x20  back-face/normal flip test (only meaningful, not a cull key)
//   bit 0x80  fill-enabled (r3d_polygon_resolve_shade_color R3D.ASM:2905); a
//             face without it draws its outline only, no fill
//
// Culling: one-sided faces are (flags & 3) == 1 or 3. The engine culls them by
// the projected signed area of the STORED index order (screen winding), so the
// port keeps the stored order and picks the matching side: shipped lists wind
// CLOCKWISE seen from the visible side -> THREE.BackSide. Never derive the
// orientation from the +5 operand: it is a normal-vertex index only on 0x20
// faces (on textured faces it is a corner index). Type 0 = DoubleSide;
// type 2 skipped.
//
// Textured faces (0x10): the two day (or night) color bytes form a 16-bit
// texture index (outlineByte | fillByte<<8, R3D.ASM:3147-3150) into the zone's
// concatenated sprite banks; we build a palette-resolved DataTexture and map it
// corner-to-corner over the quad. Missing bank/index -> flat fill fallback.
// Color-0 texels are transparent (the engine rasterizer skips them,
// GOURAUD.ASM) — that is how e.g. the bridge arch openings work.
//
// Non-mesh parts: poly-list tag 2 = sprite billboard (trees, signs, props) —
// rendered as a THREE.Sprite of the referenced bank image, anchored and sized
// per worldrender_sprite_billboard; tag 1 = point/circle — a camera-facing
// disc of the day/night fill color (worldrender_world_point_as_circ). Parts
// whose image can't be resolved fall back to a wireframe placeholder.
//
// A model with several sprite parts (combatant pose sets) carries one part
// per animation pose; in-game the visibility table picks one per frame. The
// viewer cycles through them (spriteCycleUpdate) instead of overlaying.
//
// Depth: normal z-buffered rendering. The 1993 engine painted with no z-buffer,
// so models freely stack coplanar overlay polys; to avoid z-fighting those are
// clustered by plane and displaced along their face normal by
// rank-within-cluster * eps.

import * as THREE from 'three';

// ---- Ground band-atlas shader (the engine's "grass shader") ----------------
// The DOS renderer filled strip-keyed polygons per screen scanline from a
// Z<nn>L.SCX row band; the row a scanline sampled encoded distance (dark
// far, bright near) and the x offset jittered per frame. The 3D port picks
// the band row from camera distance per fragment and anchors the pattern to
// world space (fract of world x, decorrelated per 40-unit world row) so it
// doesn't swim with the camera.

/** World distance at which a band reaches its far (dark) row. */
const ATLAS_FAR_DIST = 40000;

const ATLAS_VERT = /* glsl */ `
#include <common>
#include <logdepthbuf_pars_vertex>
varying vec3 vWorld;
void main() {
  vec4 wp = modelMatrix * vec4(position, 1.0);
  vWorld = wp.xyz;
  gl_Position = projectionMatrix * viewMatrix * wp;
  #include <logdepthbuf_vertex>
}
`;

const ATLAS_FRAG = /* glsl */ `
#include <common>
#include <logdepthbuf_pars_fragment>
uniform sampler2D uAtlas;
uniform float uRowNear;
uniform float uRowFar;
uniform float uFarDist;
varying vec3 vWorld;
void main() {
  #include <logdepthbuf_fragment>
  float d = distance(vWorld.xz, cameraPosition.xz);
  float t = clamp(d / uFarDist, 0.0, 1.0);
  float row = mix(uRowNear, uRowFar, t);
  float u = fract(vWorld.x / 12800.0 + floor(vWorld.z / 40.0) * 0.618);
  vec3 c = texture2D(uAtlas, vec2(u, (row + 0.5) / 200.0)).rgb;
  gl_FragColor = vec4(c, 1.0);
  // Match the built-in materials' output transform (sRGB working space),
  // or band surfaces render darker than the rest of the scene.
  #include <colorspace_fragment>
}
`;

/**
 * Build a THREE.Group for one parsed model + LOD.
 *
 * @param {import('./tbl.js').Model} model
 * @param {number} lodIndex
 * @param {Uint8Array} palRgb        256*3 palette
 * @param {Object} opts
 * @param {'solid'|'wireframe'|'both'} opts.mode
 * @param {'day'|'night'} opts.palette
 * @param {Uint8Array|null} opts.remap  256-entry zone color remap (or null = identity)
 * @param {import('./bmx.js').BmxImage[]} [opts.banks]  global texture-index -> image
 * @param {ReturnType<import('./scx.js').loadGroundAtlasFor>} [opts.atlas]
 *   Z<nn>L.SCX ground band atlas: flat fills whose remapped color maps to a
 *   strip render with the band shader instead of flat color (the engine's
 *   "grass shader", sky_polygon_draw_dispatch SKY.C:119)
 * @returns {{group:THREE.Group, stats:Object}}
 */
export function buildModel(model, lodIndex, palRgb, opts) {
  const mode = opts.mode || 'both';
  const useNight = opts.palette === 'night';
  const remap = opts.remap || null;
  const banks = opts.banks || [];
  const atlas = opts.atlas || null;

  const worldGroup = new THREE.Group();
  worldGroup.rotation.x = -Math.PI / 2; // BaK Z-up -> three Y-up

  const stats = {
    parts: 0,
    verts: 0,
    polys: 0,
    tris: 0,
    lines: 0,
    points: 0,
    nonMesh: 0,
    sprites: 0,          // billboard parts rendered with their real image
    circles: 0,          // point/circle parts rendered as discs
    spriteFallback: 0,   // tag-1/2 parts without a usable image (placeholder)
    textured: 0,        // textured quads actually rendered
    texturedFallback: 0, // 0x10 faces that fell back to flat fill
    bandFills: 0,       // flat fills rendered with the ground band shader
    banksUsed: new Set(),
  };

  /** Sprite-billboard parts, in part order, for the pose cycle. */
  const cycleSprites = [];

  const lod = model.lods[lodIndex];
  if (!lod) return { group: worldGroup, stats };

  // Model space is pool << bShift (R3D.ASM:3492, out = vec << g_wMeshScaleShift):
  // raw pool coords equal world units only for shift-0 records. Zone assembly
  // depends on the absolute scale (terrain patches like zero1 are shift-2).
  const scaleF = Math.pow(2, model.bShift || 0);
  const parts = scaleF === 1 ? lod.parts : lod.parts.map((p) => ({
    ...p,
    vertices: p.vertices.map((v) => [v[0] * scaleF, v[1] * scaleF, v[2] * scaleF]),
  }));

  // Zone color remap: fill = remap[fill], outline = remap[outline], applied
  // after day/night selection (engine: explore_color_remap_load + R3D).
  const colorOf = (idx) => {
    const m = remap ? remap[idx & 0xff] : idx & 0xff;
    return [palRgb[m * 3] / 255, palRgb[m * 3 + 1] / 255, palRgb[m * 3 + 2] / 255];
  };

  // Palette-resolved RGBA texture cache (one DataTexture per texture index).
  const texCache = new Map();
  const textureFor = (idx) => {
    if (idx < 0 || idx >= banks.length) return null;
    let tex = texCache.get(idx);
    if (tex !== undefined) return tex;
    const img = banks[idx];
    if (!img || img.width <= 0 || img.height <= 0) {
      texCache.set(idx, null);
      return null;
    }
    const n = img.width * img.height;
    const rgba = new Uint8Array(n * 4);
    for (let i = 0; i < n; i++) {
      const c = img.pixels[i] & 0xff;
      const m = remap ? remap[c] : c;
      rgba[i * 4] = palRgb[m * 3];
      rgba[i * 4 + 1] = palRgb[m * 3 + 1];
      rgba[i * 4 + 2] = palRgb[m * 3 + 2];
      rgba[i * 4 + 3] = c === 0 ? 0 : 255; // color 0 is transparent
    }
    tex = new THREE.DataTexture(rgba, img.width, img.height, THREE.RGBAFormat);
    // Point sampling, no mips — the 1993 rasterizer point-sampled, and mip
    // filtering both smears the pixel art and averages away the alpha holes
    // (arch openings) that alphaTest needs. NOTE: flipY does NOT work for
    // typed-array uploads (UNPACK_FLIP_Y_WEBGL ignores ArrayBufferView), so
    // the image top-row-first orientation is handled in the quad UVs instead.
    tex.magFilter = THREE.NearestFilter;
    tex.minFilter = THREE.NearestFilter;
    tex.generateMipmaps = false;
    tex.needsUpdate = true;
    texCache.set(idx, tex);
    return tex;
  };

  const scaledRadius = Math.abs(model.nRadius) * Math.pow(2, model.bShift || 0);
  const biasEps = Math.max(scaledRadius, 100) * 2e-4;

  // Ground band atlas (Z<nn>L.SCX): one palette-resolved 320x200 texture and
  // one ShaderMaterial per (strip band, side). Atlas pixels are final
  // palette indices — no zone remap.
  let _atlasTex = null;
  const atlasTexture = () => {
    if (_atlasTex) return _atlasTex;
    const rgba = new Uint8Array(320 * 200 * 4);
    for (let i = 0; i < 64000; i++) {
      const c = atlas.pixels[i] & 0xff;
      rgba[i * 4] = palRgb[c * 3];
      rgba[i * 4 + 1] = palRgb[c * 3 + 1];
      rgba[i * 4 + 2] = palRgb[c * 3 + 2];
      rgba[i * 4 + 3] = 255;
    }
    _atlasTex = new THREE.DataTexture(rgba, 320, 200, THREE.RGBAFormat);
    _atlasTex.wrapS = THREE.RepeatWrapping;
    _atlasTex.magFilter = THREE.NearestFilter;
    _atlasTex.minFilter = THREE.NearestFilter;
    _atlasTex.generateMipmaps = false;
    _atlasTex.needsUpdate = true;
    return _atlasTex;
  };

  /** Mean luminance of one atlas row (to orient a band near->far). */
  const rowLuma = (row) => {
    let s = 0;
    for (let x = 0; x < 320; x++) {
      const c = atlas.pixels[row * 320 + x] & 0xff;
      s += palRgb[c * 3] * 2 + palRgb[c * 3 + 1] * 3 + palRgb[c * 3 + 2];
    }
    return s;
  };

  const atlasMatCache = new Map();
  const atlasMat = (strip, side) => {
    const key = `${strip.base}:${strip.rows}:${side}`;
    let mat = atlasMatCache.get(key);
    if (mat) return mat;
    // The engine's band rows run dark (far scanlines, high on screen) to
    // bright (near); orient by luminance so distance always fades darker.
    const first = strip.base;
    const last = strip.base + strip.rows - 1;
    const nearRow = rowLuma(first) >= rowLuma(last) ? first : last;
    const farRow = nearRow === first ? last : first;
    mat = new THREE.ShaderMaterial({
      side,
      uniforms: {
        uAtlas: { value: atlasTexture() },
        uRowNear: { value: nearRow },
        uRowFar: { value: farRow },
        uFarDist: { value: ATLAS_FAR_DIST },
      },
      vertexShader: ATLAS_VERT,
      fragmentShader: ATLAS_FRAG,
    });
    atlasMatCache.set(key, mat);
    return mat;
  };

  // Sprite billboards need the image bottom-row-first (THREE.Sprite UVs put
  // v=0 at the quad bottom and flipY is a no-op for typed arrays), so they
  // get their own row-flipped texture cache.
  const spriteTexCache = new Map();
  const spriteTextureFor = (idx) => {
    if (idx < 0 || idx >= banks.length) return null;
    let tex = spriteTexCache.get(idx);
    if (tex !== undefined) return tex;
    const img = banks[idx];
    if (!img || img.width <= 0 || img.height <= 0) {
      spriteTexCache.set(idx, null);
      return null;
    }
    const w = img.width, h = img.height;
    const rgba = new Uint8Array(w * h * 4);
    for (let y = 0; y < h; y++) {
      const src = (h - 1 - y) * w;
      for (let x = 0; x < w; x++) {
        const c = img.pixels[src + x] & 0xff;
        const m = remap ? remap[c] : c;
        const o = (y * w + x) * 4;
        rgba[o] = palRgb[m * 3];
        rgba[o + 1] = palRgb[m * 3 + 1];
        rgba[o + 2] = palRgb[m * 3 + 2];
        rgba[o + 3] = c === 0 ? 0 : 255; // color 0 is transparent
      }
    }
    tex = new THREE.DataTexture(rgba, w, h, THREE.RGBAFormat);
    tex.magFilter = THREE.NearestFilter;
    tex.minFilter = THREE.NearestFilter;
    tex.generateMipmaps = false;
    tex.needsUpdate = true;
    spriteTexCache.set(idx, tex);
    return tex;
  };

  /** Anchor pool vertex, or the mesh origin when the index is 0xff/missing. */
  const anchorOf = (part, vi) =>
    (vi !== 0xff && part.vertices[vi]) || [0, 0, 0];

  /**
   * Billboard part (tag 2) -> THREE.Sprite (worldrender_sprite_billboard,
   * WORLDRND.C:131-201). Size: the image's larger axis spans the model
   * bounding diameter (2 * radius<<shift == 2*scaledRadius), scaled by
   * entry.scale/256 when nonzero (wScale = projScale*scale>>8). Anchor:
   * image pixel (offX, adjY) sits at the anchor vertex (the blit subtracts
   * the scaled offsets from the projected point).
   */
  const makeSprite = (part) => {
    const s = part.sprite;
    if (!s) return null;
    const img = banks[s.imageIndex];
    const tex = spriteTextureFor(s.imageIndex);
    if (!img || !tex) return null;
    const nHalf = Math.floor(Math.max(img.width, img.height) / 2);
    if (nHalf <= 0) return null;
    const k = (scaledRadius * (s.scale ? s.scale / 256 : 1)) / nHalf;
    const mat = new THREE.SpriteMaterial({ map: tex, transparent: true, alphaTest: 0.5 });
    const spr = new THREE.Sprite(mat);
    spr.scale.set(img.width * k, img.height * k, 1);
    // Sprite.center is (0,0) = bottom-left; adjY counts rows from the top.
    spr.center.set(s.offX / img.width, 1 - s.adjY / img.height);
    const a = anchorOf(part, s.vertexIdx);
    spr.position.set(a[0], a[1], a[2]);
    return spr;
  };

  /**
   * Point/circle part (tag 1) -> camera-facing disc
   * (worldrender_world_point_as_circ, WORLDRND.C:329). Filled circle of the
   * (remapped) day/night color at the anchor vertex; radius is in raw pool
   * units like the vertices.
   */
  const makeCircle = (part) => {
    const c = part.circ;
    if (!c || c.radius <= 0) return null;
    const col = colorOf(useNight ? c.nightColor : c.dayColor);
    const mat = new THREE.SpriteMaterial({
      map: discTexture(),
      transparent: true,
      alphaTest: 0.5,
      color: new THREE.Color(col[0], col[1], col[2]),
    });
    const spr = new THREE.Sprite(mat);
    // Circle radius is in raw pool units — scales with the vertices.
    spr.scale.set(c.radius * 2 * scaleF, c.radius * 2 * scaleF, 1);
    const a = anchorOf(part, c.vertexIdx);
    spr.position.set(a[0], a[1], a[2]);
    return spr;
  };

  /** Raw unit normal of a triangle (winding-dependent sign), or null. */
  const rawNormal = (a, b, c) => {
    const ux = b[0] - a[0], uy = b[1] - a[1], uz = b[2] - a[2];
    const vx = c[0] - a[0], vy = c[1] - a[1], vz = c[2] - a[2];
    let nx = uy * vz - uz * vy, ny = uz * vx - ux * vz, nz = ux * vy - uy * vx;
    const len = Math.hypot(nx, ny, nz);
    if (len < 1e-9) return null;
    return [nx / len, ny / len, nz / len];
  };

  /** First non-degenerate fan triangle of a polygon, or null. */
  const firstTri = (part, poly) => {
    const idx = poly.indices;
    const v0 = part.vertices[idx[0]];
    if (!v0) return null;
    for (let k = 1; k + 1 < idx.length; k++) {
      const a = part.vertices[idx[k]];
      const b = part.vertices[idx[k + 1]];
      if (!a || !b) continue;
      const n = rawNormal(v0, a, b);
      if (n) return { v0, a, b, n };
    }
    return null;
  };

  /** Outward-oriented normal (away from model origin) for the z-bias. */
  const outwardNormal = (t) => {
    let [nx, ny, nz] = t.n;
    const cx = (t.v0[0] + t.a[0] + t.b[0]) / 3;
    const cy = (t.v0[1] + t.a[1] + t.b[1]) / 3;
    const cz = (t.v0[2] + t.a[2] + t.b[2]) / 3;
    if (nx * cx + ny * cy + nz * cz < 0) { nx = -nx; ny = -ny; nz = -nz; }
    return [nx, ny, nz];
  };

  /** Quantized canonical plane key: sign-normalized normal + distance. */
  const planeKey = (t) => {
    let [nx, ny, nz] = t.n;
    if (nx < -1e-6 || (Math.abs(nx) <= 1e-6 && (ny < -1e-6 || (Math.abs(ny) <= 1e-6 && nz < 0)))) {
      nx = -nx; ny = -ny; nz = -nz;
    }
    const d = nx * t.v0[0] + ny * t.v0[1] + nz * t.v0[2];
    return `${Math.round(nx * 500)},${Math.round(ny * 500)},${Math.round(nz * 500)}:${Math.round(d)}`;
  };

  // Coplanar-overlay ranks: a poly is displaced only when it genuinely
  // OVERLAPS an earlier poly in the same plane (rank = deepest overlapped
  // rank + 1). Same-plane faces that merely tile an area — the 25 road
  // segments of a t-overlay model — must all stay at rank 0: ranking every
  // cluster member incrementally floated long road chains ~180 units up.
  const polyRank = new Map();
  {
    const clusters = new Map(); // planeKey -> {u, v, members:[{pts, rank}]}
    for (const part of parts) {
      if (part.nonMesh) continue;
      for (const poly of part.polygons) {
        if (poly.type === 2 || poly.indices.length < 3) continue;
        const t = firstTri(part, poly);
        if (!t) continue;
        const key = planeKey(t);
        let c = clusters.get(key);
        if (!c) {
          c = { ...planeAxes(t.n), members: [] };
          clusters.set(key, c);
        }
        const pts = [];
        for (const vi of poly.indices) {
          const p = part.vertices[vi];
          if (p) {
            pts.push([
              p[0] * c.u[0] + p[1] * c.u[1] + p[2] * c.u[2],
              p[0] * c.v[0] + p[1] * c.v[1] + p[2] * c.v[2],
            ]);
          }
        }
        let rank = 0;
        for (const m of c.members) {
          if (m.rank >= rank && convexOverlap2D(m.pts, pts)) rank = m.rank + 1;
        }
        polyRank.set(poly, rank);
        c.members.push({ pts, rank });
      }
    }
  }

  const displace = (v, n, amt) =>
    n && amt ? [v[0] + n[0] * amt, v[1] + n[1] * amt, v[2] + n[2] * amt] : v;

  const solidMat = (side) =>
    new THREE.MeshBasicMaterial({
      vertexColors: true,
      side,
    });
  const lineMat = () =>
    new THREE.LineBasicMaterial({
      vertexColors: true,
    });
  const texMat = (tex, side) =>
    new THREE.MeshBasicMaterial({
      map: tex,
      side,
      transparent: true,
      alphaTest: 0.5,
    });

  for (const part of parts) {
    stats.parts++;
    stats.verts += part.vertexCount;

    if (part.nonMesh) {
      stats.nonMesh++;
      const spr = part.polyTag === 2 ? makeSprite(part) : makeCircle(part);
      if (spr) {
        if (part.polyTag === 2) {
          stats.sprites++;
          cycleSprites.push(spr);
        } else {
          stats.circles++;
        }
        worldGroup.add(spr);
      } else {
        stats.spriteFallback++;
        worldGroup.add(makePlaceholder(part));
      }
      continue;
    }

    // Two solid batches: back-face-culled (one-sided, wound to the +5
    // normal) and uncullable (two-sided, DoubleSide).
    const culled = { pos: [], col: [] };
    const unculled = { pos: [], col: [] };
    const wirePos = [], wireCol = [];
    const linePos = [], lineCol = [];
    const pointPos = [], pointCol = [];
    // Textured quads: one geometry per texture index (batched by texture).
    const texByIdx = new Map(); // idx -> {culled:{pos,uv}, unculled:{pos,uv}}
    // Band-atlas fills: one geometry per strip band (grass/dirt/water).
    const atlasByStrip = new Map(); // "base:rows" -> {strip, culled, unculled}

    for (const poly of part.polygons) {
      if (poly.type === 2) continue; // SKIP polygons

      const idx = poly.indices;
      stats.polys++;

      // Engine picks the day pair when bGfxRenderStateFlag != 0; we follow the
      // UI day/night toggle: day -> dayFill/dayOutline, night -> night pair.
      const fillC = colorOf(useNight ? poly.nightFill : poly.dayFill);
      const outlineC = colorOf(useNight ? poly.nightOutline : poly.dayOutline);

      // One-sidedness keys on (flags & 3): 1 or 3 = one-sided (cull), 0 =
      // two-sided (DoubleSide). Bit 0x20 is only a flip-test variant.
      const oneSided = poly.type === 1 || poly.type === 3;
      const filled = (poly.flags & 0x80) !== 0;
      const textured = (poly.flags & 0x10) !== 0;

      if (idx.length >= 3) {
        const r0 = part.vertices[idx[0]];
        if (!r0) continue;
        const ft = firstTri(part, poly);

        // One-sided faces (kind 1/3) cull by the STORED winding — the engine
        // tests the projected signed area, nothing else. Stored order winds
        // clockwise from the visible side; the culled batch renders BackSide.
        const flip = false;
        const batchKey = oneSided ? 'culled' : 'unculled';

        // Textured face -> textured quad (needs a 4-vertex index list).
        if (textured && idx.length === 4) {
          const texIdx = useNight
            ? poly.nightOutline | (poly.nightFill << 8)
            : poly.dayOutline | (poly.dayFill << 8);
          const tex = textureFor(texIdx);
          if (tex) {
            stats.textured++;
            stats.banksUsed.add(bankOf(banks, texIdx));
            let bucket = texByIdx.get(texIdx);
            if (!bucket) {
              bucket = { tex, culled: { pos: [], uv: [] }, unculled: { pos: [], uv: [] } };
              texByIdx.set(texIdx, bucket);
            }
            const dst = bucket[batchKey];
            addTexturedQuad(dst, part, idx, flip);
            continue;
          }
          stats.texturedFallback++;
          // fall through to flat fill using the (remapped) fill color
        }

        const rank = polyRank.get(poly) || 0;
        // Coplanar-overlay displacement direction: toward the face's VISIBLE
        // side. One-sided faces define it — stored order winds clockwise seen
        // from the visible side, so the CCW cross product points away from
        // it: negate. (outwardNormal's away-from-origin heuristic is
        // degenerate for ground planes through the origin — it left road
        // overlay polys displaced DOWNWARD, burying them under the terrain.)
        const n = ft
          ? (oneSided ? [-ft.n[0], -ft.n[1], -ft.n[2]] : outwardNormal(ft))
          : null;
        const amt = rank * biasEps;
        const wamt = (rank + 0.5) * biasEps;
        const batch = batchKey === 'culled' ? culled : unculled;

        // Band-atlas fill (SKY.C:119): the POST-REMAP fill color keys the
        // strip map; mapped flat fills render with the band shader.
        let atlasDst = null;
        if (atlas && filled && mode !== 'wireframe') {
          const rawFill = (useNight ? poly.nightFill : poly.dayFill) & 0xff;
          const strip = atlas.stripFor(remap ? remap[rawFill] : rawFill);
          if (strip) {
            const skey = `${strip.base}:${strip.rows}`;
            let ab = atlasByStrip.get(skey);
            if (!ab) {
              ab = { strip, culled: { pos: [] }, unculled: { pos: [] } };
              atlasByStrip.set(skey, ab);
            }
            atlasDst = ab[batchKey];
            stats.bandFills++;
          }
        }

        for (let k = 1; k + 1 < idx.length; k++) {
          const ra = part.vertices[idx[k]];
          const rb = part.vertices[idx[k + 1]];
          if (!ra || !rb) continue;
          if (filled) {
            const p0 = displace(r0, n, amt);
            const pa = displace(flip ? rb : ra, n, amt);
            const pb = displace(flip ? ra : rb, n, amt);
            if (atlasDst) {
              atlasDst.pos.push(p0[0], p0[1], p0[2], pa[0], pa[1], pa[2], pb[0], pb[1], pb[2]);
            } else {
              pushTri(batch.pos, batch.col, p0, pa, pb, fillC);
            }
            stats.tris++;
          }
        }
        // Outline: a closed loop over the polygon's vertices, in the
        // (remapped) outline color. Filled faces draw it as a wire overlay
        // (mode 'both'); unfilled faces draw it as the primary geometry.
        const loopTarget = filled ? { pos: wirePos, col: wireCol, amt: wamt }
                                   : { pos: linePos, col: lineCol, amt: 0 };
        const nn = filled ? n : null;
        for (let k = 0; k < idx.length; k++) {
          const a = part.vertices[idx[k]];
          const b = part.vertices[idx[(k + 1) % idx.length]];
          if (a && b) {
            pushEdge(loopTarget.pos, loopTarget.col,
              displace(a, nn, loopTarget.amt), displace(b, nn, loopTarget.amt), outlineC);
          }
        }
        if (!filled) stats.lines++;
      } else if (idx.length === 2) {
        const a = part.vertices[idx[0]];
        const b = part.vertices[idx[1]];
        if (a && b) {
          pushEdge(linePos, lineCol, a, b, outlineC);
          stats.lines++;
        }
      } else if (idx.length === 1) {
        const a = part.vertices[idx[0]];
        if (a) {
          pointPos.push(a[0], a[1], a[2]);
          pointCol.push(...fillC);
          stats.points++;
        }
      }
    }

    const addSolid = (batch, side) => {
      if (!batch.pos.length) return;
      const geo = new THREE.BufferGeometry();
      geo.setAttribute('position', new THREE.Float32BufferAttribute(batch.pos, 3));
      geo.setAttribute('color', new THREE.Float32BufferAttribute(batch.col, 3));
      if (mode === 'solid' || mode === 'both') {
        worldGroup.add(new THREE.Mesh(geo, solidMat(side)));
      }
      if (mode === 'wireframe') {
        const mat = solidMat(THREE.DoubleSide);
        mat.vertexColors = false;
        mat.color = new THREE.Color(0x66ff66);
        mat.wireframe = true;
        worldGroup.add(new THREE.Mesh(geo, mat));
      }
    };
    addSolid(unculled, THREE.DoubleSide);
    addSolid(culled, THREE.BackSide);

    // Band-atlas fills (solid / both modes).
    if (mode === 'solid' || mode === 'both') {
      for (const ab of atlasByStrip.values()) {
        const addAtlas = (dst, side) => {
          if (!dst.pos.length) return;
          const geo = new THREE.BufferGeometry();
          geo.setAttribute('position', new THREE.Float32BufferAttribute(dst.pos, 3));
          worldGroup.add(new THREE.Mesh(geo, atlasMat(ab.strip, side)));
        };
        addAtlas(ab.unculled, THREE.DoubleSide);
        addAtlas(ab.culled, THREE.BackSide);
      }
    }

    // Textured quads (solid / both modes; wireframe uses the outline overlay).
    if (mode !== 'wireframe') {
      for (const bucket of texByIdx.values()) {
        const addTex = (dst, side) => {
          if (!dst.pos.length) return;
          const geo = new THREE.BufferGeometry();
          geo.setAttribute('position', new THREE.Float32BufferAttribute(dst.pos, 3));
          geo.setAttribute('uv', new THREE.Float32BufferAttribute(dst.uv, 2));
          worldGroup.add(new THREE.Mesh(geo, texMat(bucket.tex, side)));
        };
        addTex(bucket.unculled, THREE.DoubleSide);
        addTex(bucket.culled, THREE.BackSide);
      }
    } else {
      // Wireframe mode: render textured quads as green wire outlines too.
      for (const bucket of texByIdx.values()) {
        for (const dst of [bucket.unculled, bucket.culled]) {
          if (!dst.pos.length) continue;
          const geo = new THREE.BufferGeometry();
          geo.setAttribute('position', new THREE.Float32BufferAttribute(dst.pos, 3));
          const mat = new THREE.MeshBasicMaterial({
            color: 0x66ff66, wireframe: true, side: THREE.DoubleSide,
          });
          worldGroup.add(new THREE.Mesh(geo, mat));
        }
      }
    }

    if (mode === 'both' && wirePos.length) {
      const geo = new THREE.BufferGeometry();
      geo.setAttribute('position', new THREE.Float32BufferAttribute(wirePos, 3));
      geo.setAttribute('color', new THREE.Float32BufferAttribute(wireCol, 3));
      worldGroup.add(new THREE.LineSegments(geo, lineMat()));
    }
    if (linePos.length) {
      const geo = new THREE.BufferGeometry();
      geo.setAttribute('position', new THREE.Float32BufferAttribute(linePos, 3));
      geo.setAttribute('color', new THREE.Float32BufferAttribute(lineCol, 3));
      worldGroup.add(new THREE.LineSegments(geo, lineMat()));
    }
    if (pointPos.length) {
      const geo = new THREE.BufferGeometry();
      geo.setAttribute('position', new THREE.Float32BufferAttribute(pointPos, 3));
      geo.setAttribute('color', new THREE.Float32BufferAttribute(pointCol, 3));
      const mat = new THREE.PointsMaterial({ vertexColors: true, size: 200 });
      worldGroup.add(new THREE.Points(geo, mat));
    }
  }

  // Several sprite parts = one per animation pose: show them one at a time.
  if (cycleSprites.length > 1) {
    cycleSprites.forEach((s, i) => { s.visible = i === 0; });
    worldGroup.userData.spriteCycle = cycleSprites;
  }

  stats.banksUsed.delete(-1);
  return { group: worldGroup, stats };
}

/** Milliseconds each sprite pose stays visible in the cycle. */
const SPRITE_CYCLE_MS = 500;

/**
 * Advance the sprite pose cycle for a built model group. Call once per
 * rendered frame with a monotonic time (e.g. performance.now()).
 */
export function spriteCycleUpdate(group, timeMs) {
  const list = group.userData.spriteCycle;
  if (!list) return;
  const idx = Math.floor(timeMs / SPRITE_CYCLE_MS) % list.length;
  if (idx === group.userData.spriteCycleIdx) return;
  group.userData.spriteCycleIdx = idx;
  list.forEach((s, i) => { s.visible = i === idx; });
}

/** Which slot bank a global texture index falls in (for the info panel). */
function bankOf(banks, idx) {
  return idx >= 0 && idx < banks.length ? (banks[idx].bank ?? -1) : -1;
}

/**
 * Append a textured quad (two triangles) to a batch, UV-mapped corner to
 * corner in index order. Winding keeps the stored order; one-sided batches
 * render BackSide (stored lists wind clockwise from the visible side).
 */
function addTexturedQuad(dst, part, idx, flip) {
  const v = idx.map((i) => part.vertices[i]);
  if (v.some((p) => !p)) return;
  // UVs: corner-to-corner over the quad in index-list order, matching the
  // engine rasterizer's corner tuple (gfx_gouraud_span_dispatch: v0=TL v1=TR
  // v2=BR v3=BL). The pixel data is uploaded top-row-first with no flip, so
  // v=0 samples the image TOP; quads are authored starting at their top edge
  // (idx 0/1 = top corners), hence top corners get v=0 and bottom corners v=1.
  const uv = [
    [0, 0], [1, 0], [1, 1], [0, 1],
  ];
  const order = flip ? [0, 2, 1, 0, 3, 2] : [0, 1, 2, 0, 2, 3];
  for (const k of order) {
    dst.pos.push(v[k][0], v[k][1], v[k][2]);
    dst.uv.push(uv[k][0], uv[k][1]);
  }
}

/** Two in-plane orthonormal axes for a plane normal. */
function planeAxes(n) {
  const pick = Math.abs(n[2]) < 0.9 ? [0, 0, 1] : [1, 0, 0];
  let u = [
    n[1] * pick[2] - n[2] * pick[1],
    n[2] * pick[0] - n[0] * pick[2],
    n[0] * pick[1] - n[1] * pick[0],
  ];
  const l = Math.hypot(u[0], u[1], u[2]) || 1;
  u = [u[0] / l, u[1] / l, u[2] / l];
  const v = [
    n[1] * u[2] - n[2] * u[1],
    n[2] * u[0] - n[0] * u[2],
    n[0] * u[1] - n[1] * u[0],
  ];
  return { u, v };
}

/**
 * Convex polygon overlap in 2D via separating axes. Shared edges / touching
 * boundaries count as NOT overlapping (adjacent tiles of a road stay rank 0).
 */
function convexOverlap2D(a, b) {
  if (a.length < 3 || b.length < 3) return false;
  for (const [p, q] of [[a, b], [b, a]]) {
    for (let i = 0; i < p.length; i++) {
      const [x1, y1] = p[i];
      const [x2, y2] = p[(i + 1) % p.length];
      const nx = y2 - y1;
      const ny = x1 - x2;
      let minP = Infinity, maxP = -Infinity;
      for (const [x, y] of p) {
        const d = nx * x + ny * y;
        if (d < minP) minP = d;
        if (d > maxP) maxP = d;
      }
      let minQ = Infinity, maxQ = -Infinity;
      for (const [x, y] of q) {
        const d = nx * x + ny * y;
        if (d < minQ) minQ = d;
        if (d > maxQ) maxQ = d;
      }
      // Tolerance keeps edge-adjacent polys (exactly touching intervals)
      // classified as separated despite float noise.
      const eps = (maxP - minP + maxQ - minQ) * 1e-6 + 1e-9;
      if (maxP <= minQ + eps || maxQ <= minP + eps) return false;
    }
  }
  return true;
}

function pushTri(pos, col, a, b, c, rgb) {
  pos.push(a[0], a[1], a[2], b[0], b[1], b[2], c[0], c[1], c[2]);
  col.push(...rgb, ...rgb, ...rgb);
}

function pushEdge(pos, col, a, b, rgb) {
  pos.push(a[0], a[1], a[2], b[0], b[1], b[2]);
  col.push(...rgb, ...rgb);
}

/** Shared white disc alpha texture for point/circle (tag 1) parts. */
let _discTex = null;
function discTexture() {
  if (_discTex) return _discTex;
  const N = 64;
  const rgba = new Uint8Array(N * N * 4);
  const r = N / 2 - 0.5;
  for (let y = 0; y < N; y++) {
    for (let x = 0; x < N; x++) {
      const dx = x - (N - 1) / 2;
      const dy = y - (N - 1) / 2;
      const o = (y * N + x) * 4;
      rgba[o] = rgba[o + 1] = rgba[o + 2] = 255;
      rgba[o + 3] = dx * dx + dy * dy <= r * r ? 255 : 0;
    }
  }
  _discTex = new THREE.DataTexture(rgba, N, N, THREE.RGBAFormat);
  _discTex.needsUpdate = true;
  return _discTex;
}

/** Wireframe octahedron fallback for tag-1/2 parts with no usable image. */
function makePlaceholder(part) {
  const geo = new THREE.OctahedronGeometry(400);
  const mat = new THREE.MeshBasicMaterial({
    color: 0xffaa00,
    wireframe: true,
    side: THREE.DoubleSide,
  });
  const mesh = new THREE.Mesh(geo, mat);
  if (part.vertices && part.vertices.length) {
    const v = part.vertices[0];
    mesh.position.set(v[0], v[1], v[2]);
  }
  return mesh;
}

/**
 * Frame the camera on a group's bounding box.
 * @returns {{center:THREE.Vector3, radius:number}}
 */
export function frameObject(group, camera, controls) {
  const box = new THREE.Box3().setFromObject(group);
  if (box.isEmpty()) {
    controls.target.set(0, 0, 0);
    camera.position.set(0, 0, 1000);
    controls.update();
    return { center: new THREE.Vector3(), radius: 1000 };
  }
  const center = box.getCenter(new THREE.Vector3());
  const sphere = box.getBoundingSphere(new THREE.Sphere());
  const radius = Math.max(sphere.radius, 1);

  controls.target.copy(center);
  const dist = radius * 2.2;
  camera.position.set(center.x + dist * 0.6, center.y + dist * 0.6, center.z + dist);
  camera.near = Math.max(1, radius / 100);
  camera.far = Math.max(200000, radius * 20);
  camera.updateProjectionMatrix();
  controls.update();
  return { center, radius };
}
