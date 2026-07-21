// Z<nn>L.SCX ground band atlas + the engine's fill-color -> strip mapping.
//
// The "grass shader": in explore mode every flat-filled world polygon's
// POST-REMAP fill color is looked up in a color->strip table
// (sky_polygon_draw_dispatch, SKY.C:119); mapped polygons are filled from
// row bands of Z<nn>L.SCX — a 320x200 atlas loaded into a spare VGA page
// (zone_load_scx_image, ZONE.C:352) — instead of flat color. Each band is a
// noise pattern with a vertical brightness gradient that doubles as the
// distance shading (the engine picks the row by screen scanline; the viewer
// picks it by camera distance, which is what the screen row encoded).
//
// SCX container: u16 magic 0x27B6, u8 codec (0 raw / 2 LZW), u32
// decompressed size, payload. 64000 bytes = 320x200 row-major.

import { lzwDecode } from './bmx.js';

/**
 * The engine's 27 SkyStrip records (g_skyHorizonStrips initializer,
 * SKY.C:11): fill-color key -> atlas row band. Entries with flags&2 (the
 * remapped terrain greens 0xe0-0xe7 and palette-animated water colors
 * 0xf7-0xff) are only enabled at detail_level > 1 (sky_horizon_strips_init)
 * — the viewer always renders max detail, so all are active.
 */
const SKY_STRIPS = [
  { key: 0x00, base: 10, rows: 55 },
  { key: 0x01, base: 70, rows: 20 },
  { key: 0x02, base: 110, rows: 30 },
  { key: 0x03, base: 162, rows: 27 },
  { key: 0x04, base: 162, rows: 27 },
  { key: 0x05, base: 142, rows: 20 },
  { key: 0x06, base: 90, rows: 20 },
  { key: 0x07, base: 90, rows: 20 },
  { key: 0x08, base: 0, rows: 48 },
  { key: 0x09, base: 50, rows: 49 },
  { key: 0xe0, base: 0, rows: 50 },
  { key: 0xe1, base: 3, rows: 50 },
  { key: 0xe2, base: 6, rows: 50 },
  { key: 0xe3, base: 9, rows: 50 },
  { key: 0xe4, base: 12, rows: 50 },
  { key: 0xe5, base: 15, rows: 50 },
  { key: 0xe6, base: 18, rows: 50 },
  { key: 0xe7, base: 21, rows: 48 },
  { key: 0xff, base: 0, rows: 50 },
  { key: 0xfe, base: 3, rows: 50 },
  { key: 0xfd, base: 6, rows: 50 },
  { key: 0xfc, base: 9, rows: 50 },
  { key: 0xfb, base: 12, rows: 50 },
  { key: 0xfa, base: 15, rows: 50 },
  { key: 0xf9, base: 18, rows: 50 },
  { key: 0xf8, base: 21, rows: 48 },
  { key: 0xf7, base: 21, rows: 48 },
];

/**
 * Decode an SCX screen resource into 64000 8bpp palette indices (320x200,
 * row-major, top row first).
 * @param {Uint8Array} bytes
 * @returns {Uint8Array}
 */
export function parseScx(bytes) {
  const view = new DataView(bytes.buffer, bytes.byteOffset, bytes.byteLength);
  const magic = view.getUint16(0, true);
  if (magic !== 0x27b6) throw new Error(`SCX magic ${magic.toString(16)}`);
  const codec = bytes[2];
  const size = view.getUint32(3, true);
  const data = bytes.subarray(7);
  if (codec === 2) return lzwDecode(data, size);
  if (codec === 0) return data.subarray(0, size);
  throw new Error(`unsupported SCX codec ${codec}`);
}

/**
 * Decode any screen resource into indexed pixels. Two shipped layouts:
 *  - standard (RESBLIT.C:259): u16 magic 0x27B6, u8 codec, u32 size, payload —
 *    64000 bytes = 320x200 8bpp;
 *  - headerless codec-tagged stream (BOOK.SCX only, BOOKVIEW.C:49): u8 codec,
 *    u32 size, payload. The book viewer runs in video mode 1 — 640x350
 *    16-color — so the 112000-byte spread is 4bpp packed, two pixels per
 *    byte, high nibble first; unpacked here to one index per byte.
 * @param {Uint8Array} bytes
 * @returns {{pixels:Uint8Array, width:number, height:number, codec:number,
 *            bpp:number, headered:boolean}}
 */
export function decodeScreen(bytes) {
  const view = new DataView(bytes.buffer, bytes.byteOffset, bytes.byteLength);
  const headered = view.getUint16(0, true) === 0x27b6;
  const at = headered ? 2 : 0;
  const codec = bytes[at];
  const size = view.getUint32(at + 1, true);
  const data = bytes.subarray(at + 5);
  let pixels;
  if (codec === 2) pixels = lzwDecode(data, size);
  else if (codec === 0) pixels = data.subarray(0, size);
  else throw new Error(`unsupported screen codec ${codec}`);
  if (size === 112000) {
    const out = new Uint8Array(size * 2);
    for (let i = 0; i < size; i++) {
      out[i * 2] = pixels[i] >> 4;
      out[i * 2 + 1] = pixels[i] & 0xf;
    }
    return { pixels: out, width: 640, height: 350, codec, bpp: 4, headered };
  }
  return { pixels, width: 320, height: Math.floor(size / 320), codec, bpp: 8, headered };
}

/**
 * Load the ground band atlas for a zone TBL.
 * @param {import('./rmf.js').Archive} archive
 * @param {string} tblName
 * @returns {{name:string, pixels:Uint8Array,
 *            stripFor:(color:number)=>{base:number,rows:number}|null}|null}
 */
export function loadGroundAtlasFor(archive, tblName) {
  const m = tblName.toUpperCase().match(/^Z(\d+)M?\.TBL$/);
  if (!m) return null;
  const name = `Z${m[1]}L.SCX`;
  const bytes = archive.getResource(name);
  if (!bytes) return null;
  let pixels;
  try {
    pixels = parseScx(bytes);
  } catch (e) {
    return null;
  }
  if (pixels.length < 64000) return null;

  const map = new Array(256).fill(null);
  for (const s of SKY_STRIPS) map[s.key] = { base: s.base, rows: s.rows };
  return { name, pixels, stripFor: (color) => map[color & 0xff] };
}
