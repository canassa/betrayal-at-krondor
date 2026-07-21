// Game-data loader and world-object join for the editor inspector.
//
// A world object is the join, keyed by exact (zone, worldX, worldY), of its
// .WLD placement (position/shape, handled by zone.js) with its mutable/static
// STATE record:
//   - STARTUP.GAM temp blocks hold the mutable container records (chests, the
//     current game's contents) for each zone.
//   - OBJFIXED.DAT holds the static text objects (signs, epitaphs, buildings)
//     as one file with a per-zone count-prefixed block.
//
// Both use the identical container/fixed-object record layout (schema.js
// CONTAINER_RECORD). STARTUP.GAM is fetched separately from ./data/STARTUP.GAM;
// if it 404s the join degrades to OBJFIXED-only and every consumer is told so
// through `available`.
//
// STARTUP.GAM directory: 20 entries x 0x16 bytes at file offset 0x1177, each
// {u16 locationId, u8[4], u32 tempOffset, u32 objfixedOffset, u8[8]}. tempOffset
// is a direct STARTUP.GAM file offset; objfixedOffset indexes OBJFIXED.DAT.
// STARTUP.GAM temp blocks contain some insane records near the block start, so
// they are parsed with a validating/resyncing walker (gap pseudo-records);
// OBJFIXED.DAT blocks walk cleanly.

import { decode, containerRecordSize, SUBREC_SIZE, DEF_SCHEMA_BY_KIND } from './schema.js';
import { loadDialogDb } from './dialog.js';
import { parseTbl } from './tbl.js';

const GAM_URL = './data/STARTUP.GAM';

/** OBJINFO.DAT: 138 item records x 80 bytes from offset 0. */
const OBJINFO_STRIDE = 80;
const OBJINFO_NAME_LEN = 32;
const OBJINFO_COUNT = 138;
/** Magical Scroll: its slot condition is a spell id, not a quantity/percent. */
const ITEM_MAGICAL_SCROLL = 0x85;
/** Item categories whose slot condition is a percent condition (weapon/armor). */
const CONDITION_CATEGORIES = new Set([1, 2, 3, 4]);
/** cipherPuzzleId -> dialog key base (Moredhel wordlock: key = base + id - 1). */
const CIPHER_KEY_BASE = 0x19F0A1;
const GAM_DIR_OFF = 0x1177;
const GAM_DIR_COUNT = 20;
const GAM_DIR_STRIDE = 0x16;
const TILE = 64000;

/** Coordinate sanity window for the resync scan (spec). */
const COORD_MIN = 500000;
const COORD_MAX = 3300000;

/** DEF database table indexed by hotspot kind: {name, recordSize}. */
const DEF_TABLE = [
  { name: 'DEF_BKGR.DAT', size: 21 }, // 0
  { name: 'DEF_COMB.DAT', size: 399 }, // 1
  { name: 'DEF_COMM.DAT', size: 10 }, // 2
  { name: 'DEF_DIAL.DAT', size: 8 }, // 3
  { name: 'DEF_HEAL.DAT', size: 13 }, // 4
  { name: 'DEF_SOUN.DAT', size: 7 }, // 5
  { name: 'DEF_TOWN.DAT', size: 21 }, // 6
  { name: 'DEF_TRAP.DAT', size: 409 }, // 7
  { name: 'DEF_ZONE.DAT', size: 19 }, // 8
  { name: 'DEF_DISA.DAT', size: 7 }, // 9
  { name: 'DEF_ENAB.DAT', size: 7 }, // 10
  { name: 'DEF_BLOC.DAT', size: 8 }, // 11
];

/** Read a NUL-terminated ASCII string from a fixed-width field. */
function readCString(view, off, maxLen) {
  let s = '';
  for (let i = 0; i < maxLen; i++) {
    const c = view.getUint8(off + i);
    if (c === 0) break;
    s += String.fromCharCode(c);
  }
  return s;
}

/** A container record is sane for the given block locationId. */
function saneAt(view, off, loc) {
  if (off + 16 > view.byteLength) return false;
  const zone = view.getUint8(off);
  const residence = view.getUint8(off + 12);
  const filled = view.getUint8(off + 13);
  const cap = view.getUint8(off + 14);
  return zone === loc
    && (residence === 0 || residence === 4 || residence === 5 || residence === 6 || residence === 9)
    && cap <= 24 && filled <= cap;
}

/** True when the record at `off` also has plausible world coordinates. */
function saneWithCoords(view, off, loc) {
  if (!saneAt(view, off, loc)) return false;
  const x = view.getInt32(off + 4, true);
  const y = view.getInt32(off + 8, true);
  return x > COORD_MIN && x < COORD_MAX && y > COORD_MIN && y < COORD_MAX;
}

/** Decode one container record into {fields, size} plus a few pulled scalars. */
function decodeContainer(view, off) {
  const dec = decode('containerRecord', view, off);
  const size = containerRecordSize(view, off);
  return {
    fields: dec.fields,
    size,
    view, // shared DataView over the source file; item slots read on demand
    zone: view.getUint8(off),
    shapeId: view.getUint16(off + 2, true),
    worldX: view.getInt32(off + 4, true),
    worldY: view.getInt32(off + 8, true),
    residence: view.getUint8(off + 12),
    filledSlots: view.getUint8(off + 13),
    capacity: view.getUint8(off + 14),
    subrecMask: view.getUint8(off + 15),
  };
}

/**
 * Validating walker over a STARTUP.GAM temp block [start, end).
 * Emits {records, gaps}; a gap pseudo-record captures the offset + hex of an
 * insane run up to the next sane header found by a byte-by-byte forward scan.
 */
function walkTempBlock(view, start, end, loc) {
  const records = [];
  const gaps = [];
  if (start + 2 > end) return { records, gaps };
  let off = start + 2; // u16 count
  while (off < end && off + 16 <= view.byteLength) {
    if (!saneAt(view, off, loc)) {
      const gapStart = off;
      off += 1;
      while (off < end && off + 16 <= view.byteLength && !saneWithCoords(view, off, loc)) off += 1;
      const n = Math.min(off, end) - gapStart;
      const bytes = [];
      for (let i = 0; i < n; i++) bytes.push(view.getUint8(gapStart + i));
      gaps.push({ offset: gapStart, bytes });
      continue;
    }
    const rec = decodeContainer(view, off);
    if (rec.size <= 0) break;
    rec.offset = off;
    records.push(rec);
    off += rec.size;
  }
  return { records, gaps };
}

/** Clean count-prefixed walk over one OBJFIXED.DAT block (no gaps expected). */
function walkObjfixedBlock(view, start, loc) {
  const records = [];
  if (start + 2 > view.byteLength) return records;
  const count = view.getUint16(start, true);
  let off = start + 2;
  for (let i = 0; i < count; i++) {
    if (off + 16 > view.byteLength) break;
    const rec = decodeContainer(view, off);
    if (rec.size <= 0) break;
    rec.offset = off;
    records.push(rec);
    off += rec.size;
  }
  return records;
}

/**
 * Fetch STARTUP.GAM and index every zone's state records.
 * @param {import('./rmf.js').Archive} archive
 * @returns {Promise<GameData>}
 */
export async function loadGameData(archive) {
  const objfixed = archive.getResource('OBJFIXED.DAT');
  let gam = null;
  try {
    const res = await fetch(GAM_URL);
    if (res.ok) gam = new Uint8Array(await res.arrayBuffer());
  } catch (e) {
    gam = null;
  }

  const available = { startup: !!gam, objfixed: !!objfixed };
  const objView = objfixed
    ? new DataView(objfixed.buffer, objfixed.byteOffset, objfixed.byteLength)
    : null;
  const gamView = gam ? new DataView(gam.buffer, gam.byteOffset, gam.byteLength) : null;

  // ---- Parse the GAM directory (validate; resync base if it looks wrong). ----
  let dirBase = GAM_DIR_OFF;
  const dir = gamView ? readDirectory(gamView, dirBase, objView) : [];
  if (gamView && !directoryValid(dir, objView)) {
    for (let base = 0x10c0; base <= 0x1400; base += 2) {
      const cand = readDirectory(gamView, base, objView);
      if (directoryValid(cand, objView)) { dirBase = base; dir.length = 0; dir.push(...cand); break; }
    }
  }

  // ---- Index per-zone state records. ----
  /** @type {Map<number, {records:Object[], gaps:Object[]}>} */
  const byZone = new Map();
  const zoneOf = (loc) => {
    let z = byZone.get(loc);
    if (!z) { z = { records: [], gaps: [] }; byZone.set(loc, z); }
    return z;
  };

  // STARTUP.GAM temp blocks. The block extent is [tempOffset, nextTempOffset).
  if (gamView) {
    const temps = dir
      .filter((e) => e.tempOffset !== 0xffffffff && e.tempOffset < gam.length)
      .sort((a, b) => a.tempOffset - b.tempOffset);
    for (let i = 0; i < temps.length; i++) {
      const e = temps[i];
      if (e.locationId < 1 || e.locationId > 15) continue;
      const end = i + 1 < temps.length ? temps[i + 1].tempOffset : gam.length;
      const { records, gaps } = walkTempBlock(gamView, e.tempOffset, end, e.locationId);
      const z = zoneOf(e.locationId);
      for (const r of records) { r.source = 'startup'; z.records.push(r); }
      for (const g of gaps) z.gaps.push(g);
    }
  }

  // OBJFIXED.DAT blocks (581 records total; clean walk asserted).
  let objfixedTotal = 0;
  if (objView) {
    for (const e of dir) {
      if (e.objfixedOffset === 0xffffffff || e.objfixedOffset >= objfixed.length) continue;
      if (e.locationId < 1 || e.locationId > 15) continue;
      const recs = walkObjfixedBlock(objView, e.objfixedOffset, e.locationId);
      const z = zoneOf(e.locationId);
      for (const r of recs) { r.source = 'objfixed'; z.records.push(r); }
      objfixedTotal += recs.length;
    }
    if (objfixedTotal !== 581) {
      console.warn(`gamedata: OBJFIXED.DAT walked ${objfixedTotal} records (expected 581)`);
    }
  }

  // ---- Coordinate index for join and coordinate-nearest select. ----
  /** @type {Map<string, Object>} */
  const byCoord = new Map();
  for (const [, z] of byZone) {
    for (const r of z.records) {
      byCoord.set(`${r.zone}:${r.worldX}:${r.worldY}`, r);
    }
  }

  return new GameData({
    archive, available, dirBase, dir, byZone, byCoord,
  });
}

/** Read the 20-entry GAM directory at `base`. */
function readDirectory(view, base, objView) {
  const dir = [];
  for (let i = 0; i < GAM_DIR_COUNT; i++) {
    const o = base + i * GAM_DIR_STRIDE;
    if (o + GAM_DIR_STRIDE > view.byteLength) break;
    dir.push({
      locationId: view.getUint16(o, true),
      tempOffset: view.getUint32(o + 6, true),
      objfixedOffset: view.getUint32(o + 10, true),
    });
  }
  return dir;
}

/** Validate: objfixed offsets ascending and < OBJFIXED.DAT size. */
function directoryValid(dir, objView) {
  if (!objView) return true; // nothing to check against
  let prev = -1;
  let seen = 0;
  for (const e of dir) {
    if (e.objfixedOffset === 0xffffffff) continue;
    if (e.objfixedOffset >= objView.byteLength) return false;
    if (e.objfixedOffset < prev) return false;
    prev = e.objfixedOffset;
    seen++;
  }
  return seen >= 8;
}

/** Joined game-data accessor. */
export class GameData {
  constructor({ archive, available, dirBase, dir, byZone, byCoord }) {
    this._archive = archive;
    this.available = available;
    this.dirBase = dirBase;
    this.dir = dir;
    this._byZone = byZone;
    this._byCoord = byCoord;
    this._hotspotCache = new Map(); // "zz:xx:yy" -> parsed or null
    this._defCache = new Map();
    this._objinfo = undefined; // DataView over OBJINFO.DAT, null if absent
    this._monsterNames = undefined; // MNAMES.DAT string table, null if absent
    this._dialogDb = undefined; // full DDX graph (dialog.js), built lazily
  }

  /**
   * The full parsed dialog graph (dialog.js DialogDb), built once and cached.
   * Resolves offset-addressed (bit-31 clear) targets that the old directory-only
   * lookup could not. Uses this GameData for external roots.
   */
  dialogDb() {
    if (this._dialogDb === undefined) {
      this._dialogDb = loadDialogDb(this._archive, this);
    }
    return this._dialogDb;
  }

  /**
   * Monster class name for a combatant's monsterIndex, or null. MNAMES.DAT
   * (CBENC.C:210): u16 count, count x u16 offsets, u16 blobSize, then a blob
   * of NUL-terminated strings; name[i] = string at blob + offsets[i].
   * monsterIndex indexes this table directly (== actor class_id).
   */
  monsterName(index) {
    if (this._monsterNames === undefined) {
      const bytes = this._archive.getResource('MNAMES.DAT');
      this._monsterNames = bytes ? parseNameTable(bytes) : null;
    }
    if (!this._monsterNames) return null;
    const name = this._monsterNames[index];
    // MNAMES has an explicit "INVALID MONSTER" sentinel for unused class ids.
    if (!name || name === 'INVALID MONSTER') return null;
    return name;
  }

  /** Lazily fetched DataView over OBJINFO.DAT, or null if the file is absent. */
  _objinfoView() {
    if (this._objinfo === undefined) {
      const bytes = this._archive.getResource('OBJINFO.DAT');
      this._objinfo = bytes
        ? new DataView(bytes.buffer, bytes.byteOffset, bytes.byteLength)
        : null;
    }
    return this._objinfo;
  }

  /** Decoded OBJINFO.DAT record for an item id, or null. */
  itemRecord(id) {
    const view = this._objinfoView();
    if (!view || id < 0 || id >= OBJINFO_COUNT) return null;
    const base = id * OBJINFO_STRIDE;
    if (base + OBJINFO_STRIDE > view.byteLength) return null;
    const dec = decode('itemRecord', view, base);
    return {
      id,
      offset: base,
      name: readCString(view, base, OBJINFO_NAME_LEN),
      maxStack: view.getUint8(base + 54),
      category: view.getUint16(base + 60, true),
      fields: dec.fields,
    };
  }

  /** Display name for an item id (empty string if unknown). */
  itemName(id) {
    const r = this.itemRecord(id);
    return r ? r.name : '';
  }

  /** True when this item's slot condition should read as a percent. */
  itemIsConditioned(id) {
    const r = this.itemRecord(id);
    return !!r && CONDITION_CATEGORIES.has(r.category);
  }

  /** True when this item stacks (slot condition is a quantity). */
  itemIsStackable(id) {
    const r = this.itemRecord(id);
    return !!r && r.maxStack > 1;
  }

  /**
   * Decode a dialog record by DIRECTORY key. Resolves through the full DDX graph
   * (dialog.js) so nodes reached only via offset links are available. Returns
   * {style, speakerId, flags, choices[], ops[], textBytes, file, offset,
   * fileNumber} or null when the file/key is absent. `choices[].targetKey`
   * carries bit 31; use dialogChild() to follow it with correct file context.
   */
  dialogRecord(key) {
    const node = this.dialogDb().nodeByKey(key);
    return node ? dialogNodeToRecord(node) : null;
  }

  /**
   * Follow a choice/entry targetKey (bit 31: SET = global key, CLEAR = same-file
   * offset) from a parent record and return the child record, or null. This is
   * the offset-aware resolution the old key-only lookup could not do.
   */
  dialogChild(parentRecord, targetKey) {
    if (!parentRecord) return null;
    const res = this.dialogDb().resolveTarget(parentRecord.fileNumber, targetKey);
    return res ? dialogNodeToRecord(res.node) : null;
  }

  /** State record for an exact (zone, x, y), or null. */
  stateFor(zone, x, y) {
    const z = Number(zone);
    const r = this._byCoord.get(`${z}:${x}:${y}`);
    if (!r) return null;
    return { source: r.source, offset: r.offset, record: r };
  }

  /** All state records for a zone (both files; startup first), or []. */
  zoneRecords(zone) {
    const z = this._byZone.get(Number(zone));
    if (!z) return [];
    return z.records;
  }

  /**
   * Self-spawned objects for a zone: the container records the engine spawns
   * directly from the game-state file on zone entry (ACTSPAWN.C:54-86), which
   * have NO .WLD placement. A record self-spawns iff `(subrecMask & 0x80) != 0
   * OR residence == 9`, AND `residence != 0`. Its visual is the record's own
   * shapeId at (worldX, worldY). Chapter gating (chapterMin..chapterMax from the
   * chapterBand nibbles) is NOT applied here — every eligible record is returned
   * so the caller can toggle visibility on chapter change.
   * @returns {{record, source, offset, shapeId, x, y, chapterMin, chapterMax}[]}
   */
  selfSpawns(zone) {
    const out = [];
    for (const r of this.zoneRecords(zone)) {
      if (r.source !== 'startup') continue;
      if (r.residence === 0) continue;
      if (!((r.subrecMask & 0x80) || r.residence === 9)) continue;
      const band = r.view.getUint8(r.offset + 1);
      out.push({
        record: r,
        source: r.source,
        offset: r.offset,
        shapeId: r.shapeId,
        x: r.worldX,
        y: r.worldY,
        chapterMin: (band >> 4) & 0xf,
        chapterMax: band & 0xf,
      });
    }
    return out;
  }

  /** Gap pseudo-records seen in a zone's STARTUP.GAM temp block. */
  gaps(zone) {
    const z = this._byZone.get(Number(zone));
    return z ? z.gaps : [];
  }

  /**
   * Nearest state record to a world coordinate within a zone (for
   * ?selectat=). Returns the record or null.
   */
  nearestRecord(zone, x, y) {
    const recs = this.zoneRecords(zone);
    let best = null;
    let bestD = Infinity;
    for (const r of recs) {
      const dx = r.worldX - x;
      const dy = r.worldY - y;
      const d = dx * dx + dy * dy;
      if (d < bestD) { bestD = d; best = r; }
    }
    return best;
  }

  /**
   * Parsed tile hotspots for a chapter (1-based), or []. `T<zz><xx><yy>.DAT`
   * holds 10 chapter slots x 0xC0 bytes; each slot is u16 count + 19-byte
   * ZoneHotspot records.
   */
  hotspotsFor(zone, tileX, tileY, chapter) {
    const zz = String(Number(zone)).padStart(2, '0');
    const xx = String(tileX).padStart(2, '0');
    const yy = String(tileY).padStart(2, '0');
    const name = `T${zz}${xx}${yy}.DAT`;
    let parsed = this._hotspotCache.get(name);
    if (parsed === undefined) {
      const bytes = this._archive.getResource(name);
      parsed = bytes ? parseTileHotspots(bytes, name) : null;
      this._hotspotCache.set(name, parsed);
    }
    if (!parsed) return [];
    const ch = Math.min(Math.max(Number(chapter) || 1, 1), 10) - 1;
    return parsed[ch] || [];
  }

  /**
   * DEF database record for a hotspot kind + index, or null if the DEF file is
   * absent. File layout (hotspotevt_bak_load_indexed_rec, HOTSPOT.C): 4-byte
   * file header, then records at stride (recordSize+1) starting at offset 4,
   * each prefixed by a 1-byte `present` flag; the record body is `recordSize`
   * bytes after it. Returns {file, offset, size, present, bytes|null}; `offset`
   * points at the record body (past the present byte) for provenance display.
   */
  defRecord(kind, index) {
    const def = DEF_TABLE[kind];
    if (!def) return null;
    let bytes = this._defCache.get(def.name);
    if (bytes === undefined) {
      bytes = this._archive.getResource(def.name);
      this._defCache.set(def.name, bytes);
    }
    if (!bytes) return null;
    const slot = 4 + index * (def.size + 1); // present byte + record body
    const offset = slot + 1;
    if (offset + def.size > bytes.length) {
      return { file: def.name, offset, size: def.size, present: 0, bytes: null };
    }
    return {
      file: def.name, offset, size: def.size,
      present: bytes[slot],
      bytes: bytes.subarray(offset, offset + def.size),
    };
  }

  /**
   * Decode a DEF record for a hotspot kind + index against its schema
   * (schema.js DEF_SCHEMA_BY_KIND). Returns {file, offset, size, present,
   * bytes, kind, schema, fields[]} or null when the file is absent / OOB.
   * COMM (2) / HEAL (4) have no schema consumer in dispatch and stay hex-only.
   */
  defRecordDecoded(kind, index) {
    const rec = this.defRecord(kind, index);
    if (!rec || !rec.bytes) return rec;
    const schema = DEF_SCHEMA_BY_KIND[kind];
    if (!schema) return { ...rec, kind, schema: null, fields: [] };
    const view = new DataView(rec.bytes.buffer, rec.bytes.byteOffset, rec.bytes.byteLength);
    const dec = decode(schema, view, 0);
    return { ...rec, kind, schema, fields: dec.fields };
  }

  /** DEF file name for a hotspot kind (for display). */
  defName(kind) {
    return DEF_TABLE[kind] ? DEF_TABLE[kind].name : null;
  }

  /** Model name from the zone's Z<zz>.TBL for a shape id ('' if unknown). */
  shapeName(zone, shapeId) {
    if (!this._tblNames) this._tblNames = new Map();
    const z = Number(zone);
    let names = this._tblNames.get(z);
    if (names === undefined) {
      const bytes = this._archive.getResource(`Z${String(z).padStart(2, '0')}.TBL`);
      names = bytes ? parseTbl(bytes).names : null;
      this._tblNames.set(z, names);
    }
    if (!names) return '';
    const n = names[shapeId];
    return n && n !== 'null' ? n : '';
  }

  /**
   * Fixed-object CLICK source for a tile hotspot, or null. Kind-7/8 hotspots
   * can be fired by clicking a fixed object instead of walking into the bbox:
   * WCURSOR.C reads the object's hotspot-action subrecord (ActorSubrec08) and
   * dispatches the tile hotspot whose bbox contains its stored grid point
   * (hotspotevt_dispatch_at_point). Click-only transitions park the bbox on
   * unreachable terrain — typically the (37-39,37-39) tile corner — so the
   * walk path can never fire them; the bbox is a lookup key, not a location.
   * Takes a hotspot as parsed by hotspotsFor (zone/tile come from hs.file).
   */
  hotspotClickSource(hs) {
    if (hs.kind !== 7 && hs.kind !== 8) return null;
    const m = /^T(\d\d)(\d\d)(\d\d)\.DAT$/.exec(hs.file || '');
    if (!m) return null;
    const zone = parseInt(m[1], 10);
    const tileX = parseInt(m[2], 10);
    const tileY = parseInt(m[3], 10);
    for (const r of this.zoneRecords(zone)) {
      if (worldToTile(r.worldX) !== tileX || worldToTile(r.worldY) !== tileY) continue;
      const pt = hotspotActionPoint(r);
      if (!pt) continue;
      if (pt.x >= hs.bboxMinX && pt.x <= hs.bboxMaxX
        && pt.y >= hs.bboxMinY && pt.y <= hs.bboxMaxY) {
        return {
          record: r, source: r.source, worldX: r.worldX, worldY: r.worldY,
          shapeId: r.shapeId, name: this.shapeName(zone, r.shapeId),
          gridX: pt.x, gridY: pt.y,
        };
      }
    }
    return null;
  }
}

/**
 * Stored hotspot-action grid point of a state record, or null. Reads the raw
 * ActorSubrec08_HotspotAction {u16 pad, u16 eventId, u8 warpKind, u8 warpDest,
 * u8 hasHotspot, u8 x, u8 y} past the item slots and lower-bit subrecords.
 */
function hotspotActionPoint(r) {
  if (!(r.subrecMask & 0x08)) return null;
  let off = r.offset + 16 + r.capacity * 4;
  for (const bit of [0x01, 0x02, 0x04]) if (r.subrecMask & bit) off += SUBREC_SIZE[bit];
  if (off + 9 > r.view.byteLength) return null;
  if (r.view.getUint8(off + 6) === 0) return null; // hasHotspot
  return { x: r.view.getUint8(off + 7), y: r.view.getUint8(off + 8) };
}

/**
 * Parse a BaK name table (MNAMES.DAT / same shape as BNAMES header): u16 count,
 * count x u16 offsets, u16 blobSize, then a blob of NUL-terminated strings.
 * Returns an array `name[i] = string at blob + offsets[i]`.
 */
function parseNameTable(bytes) {
  const view = new DataView(bytes.buffer, bytes.byteOffset, bytes.byteLength);
  if (view.byteLength < 2) return [];
  const count = view.getUint16(0, true);
  const blobStart = 2 + count * 2 + 2;
  const out = [];
  for (let i = 0; i < count; i++) {
    const off = blobStart + view.getUint16(2 + i * 2, true);
    let s = '';
    for (let k = 0; off + k < view.byteLength && bytes[off + k]; k++) {
      s += String.fromCharCode(bytes[off + k]);
    }
    out.push(s);
  }
  return out;
}

/**
 * Convert a dialog.js graph node into the legacy record shape the inspector
 * consumes: choices[] (cond/rangeMinOrMask/rangeMaxOrChapbits/targetKey),
 * ops[] (op/a1..a4), textBytes[], plus file/offset/fileNumber for child
 * resolution. The node object is shared across calls, so the mapping is cheap.
 */
function dialogNodeToRecord(node) {
  if (!node) return null;
  return {
    file: `DIAL_Z${String(node.file).padStart(2, '0')}.DDX`,
    fileNumber: node.file,
    offset: node.offset,
    key: node.key,
    style: node.style,
    speakerId: node.speakerId,
    flags: node.flags,
    choices: node.entries.map((e) => ({
      cond: e.cond,
      rangeMinOrMask: e.min,
      rangeMaxOrChapbits: e.max,
      targetKey: e.target,
    })),
    ops: node.ops.map((o) => ({ op: o.op, a1: o.a1, a2: o.a2, a3: o.a3, a4: o.a4 })),
    textBytes: node.textBytes,
  };
}

/** cipherPuzzleId (nonzero) -> its Moredhel wordlock dialog key. */
export function cipherDialogKey(id) {
  return (CIPHER_KEY_BASE + id - 1) >>> 0;
}

/** Item slot condition is a spell id (item 0x85 Magical Scroll). */
export function itemIsSpellScroll(id) {
  return id === ITEM_MAGICAL_SCROLL;
}

/** Parse a T<zz><xx><yy>.DAT into 10 chapter arrays of decoded hotspots. */
function parseTileHotspots(bytes, name) {
  const view = new DataView(bytes.buffer, bytes.byteOffset, bytes.byteLength);
  const SLOT = 0xC0;
  const chapters = [];
  for (let ch = 0; ch < 10; ch++) {
    const slotBase = ch * SLOT;
    const list = [];
    if (slotBase + 2 <= view.byteLength) {
      const count = view.getUint16(slotBase, true);
      let off = slotBase + 2;
      for (let i = 0; i < count && off + 19 <= slotBase + SLOT; i++) {
        const dec = decode('zoneHotspot', view, off);
        list.push({
          fields: dec.fields,
          offset: off,
          file: name,
          kind: view.getUint16(off, true),
          bboxMinX: view.getUint8(off + 2),
          bboxMaxY: view.getUint8(off + 3),
          bboxMaxX: view.getUint8(off + 4),
          bboxMinY: view.getUint8(off + 5),
          defRecordIndex: view.getUint32(off + 6, true),
        });
        off += 19;
      }
    }
    chapters.push(list);
  }
  return chapters;
}

/** World coordinate -> tile index (64000-unit tiles). */
export function worldToTile(v) {
  return Math.floor(v / TILE);
}
