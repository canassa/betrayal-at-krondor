// Full-zone assembly: T<zz><xx><yy>.WLD tile placements over TBL shapes.
//
// A zone's map is not one resource: each 64000-unit tile has a
// T<zz><xx><yy>.WLD file (czone_load_actors, CZONE.C:103) holding up to 300
// 20-byte placement records:
//   u16 wId        shape index (ts_get_shape; in practice always within the
//                  zone's own Z<nn>.TBL — table 0 of the runtime id space)
//   i16 nVariant   payload word 0
//   i16 nPayload_w0
//   i16 nPayload_w1  Z rotation, binary angle 0x10000/turn (debug "Rotz",
//                    WORLDFRM.C:114-138; quarter turns in practice)
//   i32 nWorld_x, nWorld_y   absolute world coordinates (z is always ground)
//   u32 unused
//
// The zone renderer builds each referenced TBL model once (mesh.js
// buildModel) and clones it per placement under a shared BaK->three root.
// Placements are recentered on the zone's bounding-box middle so float32 and
// OrbitControls stay comfortable.

import * as THREE from 'three';

import { parseTbl } from './tbl.js';
import { buildModel } from './mesh.js';
import { loadPaletteFor, loadRemapFor } from './pal.js';
import { loadSpriteBanksFor } from './bmx.js';
import { loadGroundAtlasFor } from './scx.js';

/**
 * @typedef {Object} WldRecord
 * @property {number} id     shape index into the zone TBL
 * @property {number} variant
 * @property {number} w0
 * @property {number} rotZ   binary angle (0x10000 per turn)
 * @property {number} x      world x
 * @property {number} y      world y
 */

/**
 * List the zones present in the archive with their tile files.
 * @param {import('./rmf.js').Archive} archive
 * @returns {{zone:string, tiles:string[], placements:number}[]}
 */
export function listZones(archive) {
  const byZone = new Map();
  for (const name of archive.names()) {
    const m = name.match(/^T(\d\d)(\d\d)(\d\d)\.WLD$/);
    if (!m) continue;
    let z = byZone.get(m[1]);
    if (!z) {
      z = { zone: m[1], tiles: [], placements: 0 };
      byZone.set(m[1], z);
    }
    z.tiles.push(name);
    z.placements += Math.floor(archive.getResource(name).length / 20);
  }
  return [...byZone.values()].sort((a, b) => a.zone.localeCompare(b.zone));
}

/**
 * Parse one .WLD tile file into placement records.
 * @param {Uint8Array} bytes
 * @returns {WldRecord[]}
 */
export function parseWld(bytes) {
  const view = new DataView(bytes.buffer, bytes.byteOffset, bytes.byteLength);
  const out = [];
  for (let off = 0; off + 20 <= bytes.length; off += 20) {
    out.push({
      id: view.getUint16(off, true),
      variant: view.getInt16(off + 2, true),
      w0: view.getInt16(off + 4, true),
      rotZ: view.getInt16(off + 6, true),
      x: view.getInt32(off + 8, true),
      y: view.getInt32(off + 12, true),
    });
  }
  return out;
}

/**
 * Assemble a full zone.
 *
 * @param {import('./rmf.js').Archive} archive
 * @param {string} zone   two-digit zone id, e.g. "01"
 * @param {Object} opts
 * @param {'solid'|'wireframe'|'both'} opts.mode
 * @param {'day'|'night'} opts.palette
 * @param {boolean} [opts.grid]   start with the tile-grid overlay visible
 * @param {string[]} [opts.tiles]  restrict to these "xxyy" tile ids (debug)
 * @param {Object[]} [opts.spawns] self-spawned objects (gamedata selfSpawns);
 *                    rendered as instances alongside .WLD placements
 * @returns {{group:THREE.Group, stats:Object, skyColor:THREE.Color|null,
 *            groundColor:THREE.Color|null,
 *            placements:{index,id,variant,rotZ,worldX,worldY,name,tileFile,
 *                        instanceGroup}[],
 *            spawns:{index,shapeId,worldX,worldY,name,chapterMin,chapterMax,
 *                    record,source,offset,instanceGroup}[]}}
 */
export function buildZone(archive, zone, opts) {
  const tblName = `Z${zone}.TBL`;
  const tblBytes = archive.getResource(tblName);
  if (!tblBytes) throw new Error(`resource not found: ${tblName}`);
  const table = parseTbl(tblBytes);
  const palette = loadPaletteFor(archive, tblName);
  const remap = loadRemapFor(archive, tblName);
  const banks = loadSpriteBanksFor(archive, tblName);

  const buildOpts = {
    mode: opts.mode || 'solid',
    palette: opts.palette || 'day',
    remap: remap.table,
    banks: banks.images,
    atlas: loadGroundAtlasFor(archive, tblName),
  };

  // Gather all placements first (for recentering + model usage).
  const records = [];
  const tiles = [];
  for (const name of archive.names()) {
    const m = name.match(/^T(\d\d)(\d\d)(\d\d)\.WLD$/);
    if (!m || m[1] !== zone) continue;
    if (opts.tiles && !opts.tiles.includes(m[2] + m[3])) continue;
    tiles.push(name);
    for (const r of parseWld(archive.getResource(name))) {
      r.tileFile = name;
      records.push(r);
    }
  }
  if (!records.length) throw new Error(`zone ${zone}: no .WLD tiles`);

  let minX = Infinity, maxX = -Infinity, minY = Infinity, maxY = -Infinity;
  for (const r of records) {
    if (r.x < minX) minX = r.x;
    if (r.x > maxX) maxX = r.x;
    if (r.y < minY) minY = r.y;
    if (r.y > maxY) maxY = r.y;
  }
  const cx = Math.round((minX + maxX) / 2);
  const cy = Math.round((minY + maxY) / 2);

  const root = new THREE.Group();
  root.rotation.x = -Math.PI / 2; // BaK Z-up -> three Y-up

  const stats = {
    zone,
    tiles: tiles.length,
    placements: records.length,
    instanced: 0,
    outOfRange: 0,
    duplicates: 0,
    emptyModels: 0,
    distinctModels: new Set(),
    modelErrors: 0,
    spawned: 0,
    spawnSkipped: 0,
  };

  // One template per shape id; instances are clones sharing geometry/materials.
  const templates = new Map(); // id -> THREE.Group|null
  const templateFor = (id) => {
    if (templates.has(id)) return templates.get(id);
    let tpl = null;
    const model = table.models[id];
    if (model && !model.empty && !model.error && model.lods.length) {
      try {
        const built = buildModel(model, 0, palette.rgb, buildOpts);
        tpl = built.group;
        // Model space is BaK coords; the zone root applies the axis flip once.
        tpl.rotation.set(0, 0, 0);
        // Sprite-pose cycle metadata holds live object refs, which
        // Object3D.clone()'s JSON userData copy cannot survive. A zone shows
        // pose 0 statically.
        delete tpl.userData.spriteCycle;
      } catch (e) {
        stats.modelErrors++;
        tpl = null;
      }
    } else if (model && model.empty) {
      stats.emptyModels++;
    }
    templates.set(id, tpl);
    return tpl;
  };

  // Layering: the engine paints shapes with nonzero bPriority FIRST, highest
  // priority first (vislist_sort, VISLIST.C:20-59) — ground (priority 8)
  // under the t-prefixed road overlays (7) under the r-prefixed river
  // overlays (6), all coplanar at z=0; priority-0 objects paint afterwards
  // (so e.g. the fall1 waterfall pool covers the river overlay it sits on).
  // Under a z-buffer each priority level becomes a layer, priority-0 the
  // topmost: a tiny +z lift makes the geometric order match the paint order
  // at close range, and renderOrder reproduces the paint sequence so
  // LessEqualDepth ties go to the upper layer when the lift quantizes away
  // at aerial distances. 1 unit is invisible at any angle; the log depth
  // buffer still resolves it out to mid-zone distances, and beyond that the
  // renderOrder tie-break takes over.
  const STACK_LIFT = 1;
  let maxPrio = 0;
  for (const m of table.models) {
    if (m.bPriority > maxPrio) maxPrio = m.bPriority;
  }
  // Build one cloned, positioned, priority-lifted instance for a shape id at a
  // world coordinate. Shared by .WLD placements and self-spawned objects so both
  // honor the identical priority-0 lift + renderOrder rules. Returns the
  // three.js group (userData.placementIndex/spawnIndex is set by the caller,
  // AFTER clone(), per the clone-copies-userData gotcha), or null if the shape
  // has no renderable template.
  const makeInstance = (id, worldX, worldY, rotZ) => {
    const tpl = templateFor(id);
    if (!tpl) return null;
    const prio = table.models[id].bPriority;
    const layer = prio > 0 ? maxPrio - prio : maxPrio + 1;
    const inst = tpl.clone();
    inst.position.set(worldX - cx, worldY - cy, layer * STACK_LIFT);
    inst.rotation.z = (rotZ * Math.PI * 2) / 0x10000;
    if (layer > 0) inst.traverse((o) => { o.renderOrder = layer; });
    return inst;
  };

  // Placement descriptors for the inspector: every rendered instance gets an
  // entry, keyed by its index in this array (== inst.userData.placementIndex).
  const placements = [];
  const placedCoords = new Set(); // "x:y" of every rendered .WLD placement
  const seen = new Set();
  for (const r of records) {
    if (r.id >= table.models.length) {
      stats.outOfRange++;
      continue;
    }
    // Exact-duplicate placements z-fight as two coplanar copies — drop them.
    const key = `${r.id}:${r.x}:${r.y}:${r.rotZ}`;
    if (seen.has(key)) {
      stats.duplicates++;
      continue;
    }
    seen.add(key);
    const inst = makeInstance(r.id, r.x, r.y, r.rotZ);
    if (!inst) continue;
    // clone() deep-copies userData via JSON; set the back-reference AFTER the
    // clone and keep it a plain scalar so future clones stay cheap and safe.
    const index = placements.length;
    inst.userData.placementIndex = index;
    root.add(inst);
    placedCoords.add(`${r.x}:${r.y}`);
    placements.push({
      index,
      id: r.id,
      variant: r.variant,
      w0: r.w0,
      rotZ: r.rotZ,
      worldX: r.x,
      worldY: r.y,
      name: table.models[r.id].name,
      tileFile: r.tileFile,
      instanceGroup: inst,
    });
    stats.instanced++;
    stats.distinctModels.add(r.id);
  }

  // Self-spawned objects (records with no .WLD placement; ACTSPAWN.C). Built as
  // instances of their own shapeId at (worldX, worldY), rotation 0. Chapter
  // gating is a visibility toggle applied by the caller, not a filter here.
  const spawns = [];
  for (const s of opts.spawns || []) {
    // Honor the ?tiles= filter by the object's own tile.
    if (opts.tiles) {
      const tx = String(Math.floor(s.x / 64000)).padStart(2, '0');
      const ty = String(Math.floor(s.y / 64000)).padStart(2, '0');
      if (!opts.tiles.includes(tx + ty)) continue;
    }
    if (s.shapeId >= table.models.length) {
      stats.outOfRange++;
      continue;
    }
    // A .WLD placement at the same coordinate wins; skip the spawn (not seen in
    // shipped data, but the engine would double-render otherwise).
    if (placedCoords.has(`${s.x}:${s.y}`)) {
      stats.spawnSkipped++;
      continue;
    }
    const inst = makeInstance(s.shapeId, s.x, s.y, 0);
    if (!inst) continue;
    const index = spawns.length;
    inst.userData.spawnIndex = index;
    root.add(inst);
    spawns.push({
      index,
      shapeId: s.shapeId,
      worldX: s.x,
      worldY: s.y,
      name: table.models[s.shapeId].name,
      chapterMin: s.chapterMin,
      chapterMax: s.chapterMax,
      record: s.record,
      source: s.source,
      offset: s.offset,
      instanceGroup: inst,
    });
    stats.spawned++;
    stats.distinctModels.add(s.shapeId);
  }

  // --- Tile-boundary grid overlay (Z<nn>MAP.DAT) ---
  // The zone's 400-byte 50x50 tile-presence bitmap (zone_map_data_load,
  // ZONE.C:287; bit(x,y) = byte[y*8+(x>>3)] & 1<<(x&7)). One outlined square
  // per existing 64000-unit tile, floating slightly above ground; visibility
  // is toggled from the UI without rebuilding.
  const mapBytes = archive.getResource(`Z${zone}MAP.DAT`);
  if (mapBytes && mapBytes.length >= 400) {
    const T = 64000;
    const pos = [];
    let gridTiles = 0;
    for (let ty = 0; ty < 50; ty++) {
      for (let tx = 0; tx < 50; tx++) {
        if (!(mapBytes[ty * 8 + (tx >> 3)] & (1 << (tx & 7)))) continue;
        gridTiles++;
        const x0 = tx * T - cx;
        const y0 = ty * T - cy;
        pos.push(
          x0, y0, 0, x0 + T, y0, 0,
          x0 + T, y0, 0, x0 + T, y0 + T, 0,
          x0 + T, y0 + T, 0, x0, y0 + T, 0,
          x0, y0 + T, 0, x0, y0, 0,
        );
      }
    }
    const geo = new THREE.BufferGeometry();
    geo.setAttribute('position', new THREE.Float32BufferAttribute(pos, 3));
    const grid = new THREE.LineSegments(geo, new THREE.LineBasicMaterial({
      color: 0x7fb4ff, transparent: true, opacity: 0.6,
    }));
    grid.name = 'tileGrid';
    grid.position.z = 60; // above the layer lifts; terrain may still occlude
    grid.renderOrder = 50;
    grid.visible = !!opts.grid;
    root.add(grid);
    stats.gridTiles = gridTiles;
  }

  // Ground plane + sky from the Z<nn>.DAT sky-band palette indices (the
  // engine clears the frame with them, WORLDFRM.C:220). Slightly below z=0
  // so road/floor quads in the models win the depth test.
  let skyColor = null;
  let groundColor = null;
  if (remap.sky) {
    skyColor = palColor(palette.rgb, remap.sky[0]);
    groundColor = palColor(palette.rgb, remap.sky[1]);
  }
  // With the band atlas active, the terrain fades to the grass band's far
  // (dark) rows with distance — color the backdrop plane to match so the
  // beyond-the-tiles ground blends instead of glowing lighter.
  if (buildOpts.atlas) {
    const strip = buildOpts.atlas.stripFor(0);
    if (strip) {
      const row = strip.base + strip.rows - 1;
      let r = 0, g = 0, b = 0;
      for (let x = 0; x < 320; x++) {
        const c = buildOpts.atlas.pixels[row * 320 + x] & 0xff;
        r += palette.rgb[c * 3];
        g += palette.rgb[c * 3 + 1];
        b += palette.rgb[c * 3 + 2];
      }
      groundColor = new THREE.Color(r / 320 / 255, g / 320 / 255, b / 320 / 255);
    }
  }
  const margin = 64000;
  const w = maxX - minX + margin * 2;
  const h = maxY - minY + margin * 2;
  const ground = new THREE.Mesh(
    new THREE.PlaneGeometry(w, h),
    new THREE.MeshBasicMaterial({ color: groundColor || new THREE.Color(0x33392c) })
  );
  ground.position.z = -20;
  ground.renderOrder = -1; // backdrop: draw first, lose every depth tie
  root.add(ground);

  stats.distinctModels = stats.distinctModels.size;
  // center offset lets callers place root-local markers from world coordinates.
  return { group: root, stats, skyColor, groundColor, placements, spawns, center: { x: cx, y: cy } };
}

function palColor(palRgb, idx) {
  const i = (idx & 0xff) * 3;
  return new THREE.Color(palRgb[i] / 255, palRgb[i + 1] / 255, palRgb[i + 2] / 255);
}
