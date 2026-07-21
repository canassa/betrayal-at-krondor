// .TBL model-table parser. Pure data, no three.js.
//
// Container chunks (IFF-style, no preamble): MAP: APP: GID: DAT:, all leaves.
//   +0 char[4] tag  (trailing ':' included)
//   +4 u32     size (bit31 = has-children; low 31 = payload size)
//   +8 body
//
// MAP: model names (authoring). DAT: model records + 3D mesh (what we render).
//
// Key rule: every inner near
// pointer is a u16 offset RELATIVE TO THE RECORD'S SEGMENT BASE, where
//   segbase = ((v >> 16) & 0xffff) * 16      (v = the DAT: pointer-table entry)
// i.e. a byte offset inside the DAT: chunk body, NOT relative to the record start.

/**
 * @typedef {Object} Polygon
 * @property {number} flags
 * @property {number} type       flags & 3: 0 two-sided, 1/3 one-sided, 2 skip
 * @property {number} dayFill    palette index (operand +2)
 * @property {number} dayOutline palette index (operand +1)
 * @property {number} nightFill  palette index (operand +4)
 * @property {number} nightOutline palette index (operand +3)
 * @property {number} normalVtxIdx operand +5, vertex used as face normal
 * @property {number[]} indices  vertex-pool indices (0xff-terminated list)
 */

/**
 * @typedef {Object} SpriteRef  billboard payload (tag 2, WORLDRND.C:131-201)
 * @property {number} imageIndex  global sprite-bank image index (u16)
 * @property {number} adjY        anchor pixel row within the image
 * @property {number} offX        anchor pixel column within the image
 * @property {number} scale       size byte: /256 of the model diameter; 0 = full
 * @property {number} vertexIdx   anchor pool vertex (0xff = mesh origin)
 */

/**
 * @typedef {Object} CircRef  point/circle payload (tag 1, CircObj)
 * @property {number} radius     world radius, raw pool units (i16)
 * @property {number} vertexIdx  center pool vertex (0xff = mesh origin)
 * @property {number} dayColor
 * @property {number} nightColor
 */

/**
 * @typedef {Object} Part
 * @property {number} groupId
 * @property {number} vertexCount
 * @property {[number,number,number][]} vertices  raw i16 Vec3Short pool
 * @property {number} polyTag     0 mesh, 1 point/circle, 2 sprite billboard
 * @property {Polygon[]} polygons
 * @property {boolean} nonMesh    true for tag 1/2
 * @property {SpriteRef} [sprite] tag 2 payload
 * @property {CircRef} [circ]     tag 1 payload
 */

/**
 * @typedef {Object} Lod
 * @property {number} threshold
 * @property {number} partCount
 * @property {Part[]} parts       flattened (sub-parts recursed into this list)
 */

/**
 * @typedef {Object} Model
 * @property {number} index
 * @property {string} name
 * @property {number} bFlags
 * @property {number} bKind
 * @property {number} bPriority
 * @property {number} bShift
 * @property {number} nLodCount
 * @property {number} nRadius
 * @property {Lod[]} lods
 * @property {boolean} empty       nLodCount==0 / no geometry
 * @property {string|null} error   per-model parse error, if any
 */

/** Parse container chunks into a name -> {start,size} map (body offsets). */
function readChunks(bytes) {
  const view = new DataView(bytes.buffer, bytes.byteOffset, bytes.byteLength);
  const chunks = {};
  let p = 0;
  while (p + 8 <= bytes.length) {
    const tag = String.fromCharCode(
      bytes[p], bytes[p + 1], bytes[p + 2], bytes[p + 3]
    );
    const size = view.getUint32(p + 4, true) & 0x7fffffff;
    chunks[tag] = { start: p + 8, size };
    p += 8 + size;
  }
  return chunks;
}

/** Parse the MAP: chunk into model names (1:1 with model index). */
function readNames(bytes, chunk) {
  const view = new DataView(bytes.buffer, bytes.byteOffset, bytes.byteLength);
  const base = chunk.start;
  const count = view.getUint16(base + 2, true); // +0 is a duplicate count
  const offsets = [];
  for (let i = 0; i < count; i++) {
    offsets.push(view.getUint16(base + 4 + 2 * i, true));
  }
  const strBase = base + 6 + 2 * count;
  const names = [];
  for (let i = 0; i < count; i++) {
    let o = strBase + offsets[i];
    let s = '';
    while (o < bytes.length && bytes[o] !== 0) {
      s += String.fromCharCode(bytes[o]);
      o++;
    }
    names.push(s);
  }
  return names;
}

/**
 * Parse a .TBL resource.
 * @param {Uint8Array} bytes
 * @returns {{names:string[], models:Model[], parseErrors:number}}
 */
export function parseTbl(bytes) {
  const chunks = readChunks(bytes);
  if (!chunks['DAT:']) throw new Error('no DAT: chunk');

  const names = chunks['MAP:'] ? readNames(bytes, chunks['MAP:']) : [];

  const datChunk = chunks['DAT:'];
  // A view whose offset 0 is the start of the DAT: body — near offsets and
  // segbase are all relative to this body.
  const d = new DataView(
    bytes.buffer,
    bytes.byteOffset + datChunk.start,
    datChunk.size
  );

  // Pointer table: seg:off entries, 0-terminated.
  const ptrs = [];
  let i = 0;
  while (i + 4 <= d.byteLength) {
    const v = d.getUint32(i, true);
    i += 4;
    if (v === 0) break;
    ptrs.push(v);
  }

  const models = [];
  let parseErrors = 0;

  for (let idx = 0; idx < ptrs.length; idx++) {
    const v = ptrs[idx];
    const segbase = ((v >>> 16) & 0xffff) * 16;
    const recOff = segbase + (v & 0xffff);
    const name = names[idx] !== undefined ? names[idx] : `#${idx}`;

    /** @type {Model} */
    const model = {
      index: idx,
      name,
      bFlags: 0,
      bKind: 0,
      bPriority: 0,
      bShift: 0,
      nLodCount: 0,
      nRadius: 0,
      lods: [],
      empty: false,
      error: null,
    };

    try {
      model.bFlags = d.getUint8(recOff + 0x0);
      model.bKind = d.getUint8(recOff + 0x1);
      model.bPriority = d.getUint8(recOff + 0x2);
      model.bShift = d.getUint8(recOff + 0x3);
      model.nLodCount = d.getInt16(recOff + 0x8, true);
      const pLod = d.getUint16(recOff + 0xa, true);
      model.nRadius = d.getInt16(recOff + 0xc, true);

      if (model.nLodCount <= 0 || pLod === 0) {
        model.empty = true;
      } else {
        model.lods = parseLods(d, segbase, pLod, model.nLodCount);
      }
    } catch (e) {
      model.error = String(e && e.message ? e.message : e);
      parseErrors++;
    }

    models.push(model);
  }

  return { names, models, parseErrors };
}

/** LOD descriptor array: nLod entries x 6 bytes at segbase+pLod. */
function parseLods(d, segbase, pLod, nLod) {
  const lods = [];
  for (let li = 0; li < nLod; li++) {
    const lo = segbase + pLod + li * 6;
    const threshold = d.getInt16(lo, true);
    const partCount = d.getInt16(lo + 2, true);
    const partBaseNear = d.getUint16(lo + 4, true);

    const parts = [];
    for (let pi = 0; pi < partCount; pi++) {
      parsePart(d, segbase, segbase + partBaseNear + pi * 0xe, parts);
    }
    lods.push({ threshold, partCount, parts });
  }
  return lods;
}

/**
 * Parse one MeshPartRecord (14 bytes). If it is a group (nSub > 0), recurse
 * into its sub-parts; otherwise append the concrete part to `out`.
 */
function parsePart(d, segbase, po, out) {
  const edgeVtxIdx = d.getUint8(po + 0x1);   // painter depth-sort key vector (0xff = none)
  const anchorVtxIdx = d.getUint8(po + 0x2); // sort anchor point (0xff = mesh origin)
  const vertexCount = d.getUint8(po + 0x3);
  const wVertexPoolOff = d.getUint16(po + 0x4, true);
  const nField6 = d.getInt16(po + 0x6, true); // visibility-group frame stride
  const wPolyListOff = d.getUint16(po + 0x8, true);
  const nSub = d.getInt16(po + 0xa, true);
  const wSubArrOff = d.getUint16(po + 0xc, true);

  if (nSub > 0) {
    for (let s = 0; s < nSub; s++) {
      parsePart(d, segbase, segbase + wSubArrOff + s * 0xe, out);
    }
    return;
  }

  // Vertex pool: vertexCount x Vec3Short (3 x i16).
  const vertices = [];
  const va = segbase + wVertexPoolOff;
  for (let k = 0; k < vertexCount; k++) {
    const o = va + k * 6;
    vertices.push([
      d.getInt16(o, true),
      d.getInt16(o + 2, true),
      d.getInt16(o + 4, true),
    ]);
  }

  const pla = segbase + wPolyListOff;
  const polyTag = d.getUint8(pla);

  const part = {
    groupId: d.getUint8(po + 0x0),
    edgeVtxIdx,
    anchorVtxIdx,
    nField6,
    vertexCount,
    vertices,
    polyTag,
    polygons: [],
    nonMesh: polyTag !== 0,
  };

  if (polyTag === 2) {
    // Sprite billboard entry (worldrender_sprite_billboard, WORLDRND.C:131):
    //   +2 u16 image index, +4 u8 anchor row, +5 u8 anchor column,
    //   +6 u8 scale byte, +7 u8 anchor vertex index.
    part.sprite = {
      imageIndex: d.getUint16(pla + 2, true),
      adjY: d.getUint8(pla + 4),
      offX: d.getUint8(pla + 5),
      scale: d.getUint8(pla + 6),
      vertexIdx: d.getUint8(pla + 7),
    };
  } else if (polyTag === 1) {
    // CircObj (worldrender_world_point_as_circ, WORLDRND.C:329):
    //   +2 i16 radius, +4 u8 vertex index, +5 u8 day color, +6 u8 night color.
    part.circ = {
      radius: d.getInt16(pla + 2, true),
      vertexIdx: d.getUint8(pla + 4),
      dayColor: d.getUint8(pla + 5),
      nightColor: d.getUint8(pla + 6),
    };
  }

  if (polyTag === 0) {
    const polyCount = d.getUint16(pla + 2, true);
    const firstPolyNear = d.getUint16(pla + 4, true);
    const fa = segbase + firstPolyNear;
    for (let gi = 0; gi < polyCount; gi++) {
      const go = fa + gi * 8;
      const flags = d.getUint8(go);
      const idxListNear = d.getUint16(go + 6, true);

      // 0xff-terminated vertex-index list.
      const indices = [];
      let j = segbase + idxListNear;
      while (j < d.byteLength) {
        const b = d.getUint8(j);
        if (b === 0xff) break;
        indices.push(b);
        j++;
      }

      part.polygons.push({
        flags,
        type: flags & 3,
        dayOutline: d.getUint8(go + 1),
        dayFill: d.getUint8(go + 2),
        nightOutline: d.getUint8(go + 3),
        nightFill: d.getUint8(go + 4),
        normalVtxIdx: d.getUint8(go + 5),
        indices,
      });
    }
  }

  out.push(part);
}
