// .PAL palette parser.
//
// A .PAL resource is an IFF-style container. We locate the "VGA:" chunk:
//   +0 char[4] "VGA:"
//   +4 u32     size
//   +8 data    256 x 3 bytes of 6-bit VGA RGB
// 6-bit components are scaled <<2 to 8-bit.

const VGA_TAG = [0x56, 0x47, 0x41, 0x3a]; // "VGA:"

/**
 * Parse a .PAL resource into 256 RGB triples (0..255).
 * @param {Uint8Array} bytes
 * @returns {Uint8Array} length 256*3, [r,g,b, r,g,b, ...]
 */
export function parsePalette(bytes) {
  const at = findTag(bytes);
  if (at < 0) throw new Error('no VGA: chunk in palette');

  const view = new DataView(bytes.buffer, bytes.byteOffset, bytes.byteLength);
  const size = view.getUint32(at + 4, true);
  const dataStart = at + 8;
  const count = Math.min(256, Math.floor(size / 3));

  const rgb = new Uint8Array(256 * 3);
  for (let i = 0; i < count; i++) {
    const src = dataStart + i * 3;
    // 6-bit -> 8-bit. Use <<2 | >>4 to fill the low bits for a fuller range.
    for (let c = 0; c < 3; c++) {
      const v = bytes[src + c];
      rgb[i * 3 + c] = (v << 2) | (v >> 4);
    }
  }
  return rgb;
}

function findTag(bytes) {
  for (let i = 0; i + 4 <= bytes.length; i++) {
    if (
      bytes[i] === VGA_TAG[0] &&
      bytes[i + 1] === VGA_TAG[1] &&
      bytes[i + 2] === VGA_TAG[2] &&
      bytes[i + 3] === VGA_TAG[3]
    ) {
      return i;
    }
  }
  return -1;
}

/**
 * Parse a Z<nn>.DAT explore color-remap resource.
 *
 * At zone load the engine reads Z<nn>.DAT and applies fill = remap[fill],
 * outline = remap[outline] to every polygon, after day/night selection
 * (ZONE.C -> explore_color_remap_load, applied in R3D). Layout (LE):
 *   u16 skyR, u16 skyG, u16 skyB   sky-band PALETTE INDICES (not RGB)
 *   u16 count
 *   count x { u8 idx, u8 val }     sparse overrides over identity[256]
 *
 * @param {Uint8Array} bytes
 * @returns {{table:Uint8Array, count:number, sky:[number,number,number]}}
 */
export function parseRemap(bytes) {
  const view = new DataView(bytes.buffer, bytes.byteOffset, bytes.byteLength);
  const sky = [
    view.getUint16(0, true),
    view.getUint16(2, true),
    view.getUint16(4, true),
  ];
  const count = view.getUint16(6, true);
  if (8 + count * 2 > bytes.length) throw new Error('remap table truncated');

  const table = new Uint8Array(256);
  for (let i = 0; i < 256; i++) table[i] = i;
  for (let i = 0; i < count; i++) {
    table[bytes[8 + i * 2]] = bytes[9 + i * 2];
  }
  return { table, count, sky };
}

/**
 * Resolve and parse the color remap for a TBL resource.
 * Zone tables (Z<nn>.TBL / Z<nn>M.TBL) use Z<nn>.DAT; COMBAT.TBL uses the
 * identity (the arena remap is a separate combat path, out of scope here).
 * @param {import('./rmf.js').Archive} archive
 * @param {string} tblName
 * @returns {{name:string|null, table:Uint8Array|null, count:number, sky:number[]|null}}
 */
export function loadRemapFor(archive, tblName) {
  const m = tblName.toUpperCase().match(/^Z(\d+)M?\.TBL$/);
  if (m) {
    const name = `Z${m[1]}.DAT`;
    const bytes = archive.getResource(name);
    if (bytes) {
      const r = parseRemap(bytes);
      return { name, table: r.table, count: r.count, sky: r.sky };
    }
  }
  return { name: null, table: null, count: 0, sky: null }; // identity
}

/**
 * Choose and parse the palette for a given TBL resource name.
 * Returns { name, rgb } — name is the resource actually loaded.
 * @param {import('./rmf.js').Archive} archive
 * @param {string} tblName e.g. "Z01.TBL", "Z10M.TBL", "COMBAT.TBL"
 */
export function loadPaletteFor(archive, tblName) {
  const candidates = [];
  const up = tblName.toUpperCase();

  if (up === 'COMBAT.TBL') {
    // There is no COMBAT.PAL: in-game, combat keeps the current zone's
    // palette. Z01.PAL is the static stand-in (character sprites live in
    // the 118-143 band, which the arbitrary-fallback palettes render black).
    candidates.push('COMBAT.PAL', 'Z01.PAL');
  } else {
    // Z<nn>.TBL and Z<nn>M.TBL both use Z<nn>.PAL.
    const m = up.match(/^Z(\d+)M?\.TBL$/);
    if (m) candidates.push(`Z${m[1]}.PAL`);
  }

  for (const name of candidates) {
    const bytes = archive.getResource(name);
    if (bytes) {
      try {
        return { name, rgb: parsePalette(bytes) };
      } catch (e) {
        /* fall through to fallback */
      }
    }
  }

  // Fallback: any .PAL that parses.
  for (const name of archive.names()) {
    if (!name.endsWith('.PAL')) continue;
    const bytes = archive.getResource(name);
    try {
      return { name, rgb: parsePalette(bytes), fallback: true };
    } catch (e) {
      /* keep looking */
    }
  }

  throw new Error('no usable palette found in archive');
}
