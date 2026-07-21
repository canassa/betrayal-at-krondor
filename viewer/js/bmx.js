// Z<nn>SLOT<d>.BMX sprite-bank decoder.
//
// The zone loader (ZONE.C:136-144) reads up to 7 Z<nn>SLOT<d>.BMX resources
// into g_spriteBanks[slot] via resblit_load_asset_table (RESBLIT.C:70). Textured
// world polygons (poly flag 0x10) index these banks by a texture index; because
// zone shape tables carry spriteBank == -1 (ts_load_shape_tbl), the index is a
// GLOBAL index across the concatenation of all loaded slot banks in slot order
// (worldrender_paged_array_get, WORLDRND.C:89-101).
//
// BMX layout (resblit_load_asset_table + struct BmxHeader/ImageRecord):
//   header (12 bytes):
//     u16 wMagic (=0x1066)  u16 wCompression  u16 wImageCount
//     u16 wCompressedSize   u32 dwDecompressedSize
//   directory: wImageCount x 8 bytes (bak_fread(&rec->wImageOff, 2, 4)):
//     u16 chunkSize   u16 flags   i16 nWidth   i16 nHeight
//   payload: routed by header wCompression (resblit_load_asset_table,
//     RESBLIT.C:137-165):
//       0 -> codec-tagged stream (stream_open: leading codec byte + u32
//            uncompressed size, then codec data; Z01 slots use codec 2 = LZW)
//       2 -> raw byte-RLE stream, no prefix (decomp_rle, DECOMP.ASM)
//       else (1) -> raw LZSS stream, no prefix (decomp_lzss, DECOMP.ASM);
//            zones 10-12 use this.
//     The decompressed payload is the concatenation of per-image blocks,
//     each `chunkSize` bytes; each block is either raw 8bpp pixels (flags &
//     0x80 == 0) or an engine sprite-RLE stream (flags & 0x80) that expands to
//     nWidth*nHeight 8bpp pixels (POLYRAST.ASM L_rle_run/L_rle_loop_top).
//
// Pixel blocks are COLUMN-major: nWidth columns of nHeight bytes each, texel
// (x, y) = block[x * nHeight + y]. Both engine samplers address them that way —
// the scaled sprite blit (POLYRAST.ASM 169d:14e8, SI = data + x_acc*height +
// y_acc) and the textured-quad rasterizer (GOURAUD.ASM row table stepping
// quad[4] = nHeight per u). The layout matches Mode X blitting, which walks the
// screen column-by-column (one plane-select OUT per column). parseBmx
// transposes each block to conventional row-major for the GL pipeline.
//
// Pixel value 0 is transparent (the blit skips color-0 texels).

/**
 * @typedef {Object} BmxImage
 * @property {number} width
 * @property {number} height
 * @property {Uint8Array} pixels   width*height 8bpp palette indices, row-major
 *                                 (transposed from the on-disk column-major block;
 *                                 0 = transparent)
 */

/** Codec byte 2 = compress-style LZW (STREAM CODEC vtable slot 2). */
const CODEC_LZW = 2;

/**
 * @typedef {Object} SpriteBanks
 * @property {BmxImage[]} images   global index -> image (slot banks concatenated)
 * @property {string[]} slots      resource names actually loaded
 * @property {(modelIndex:number) => BmxImage[]} [forModel]
 *   COMBAT.TBL only: per-model image bank (combatant sheet or FIGS.BMX)
 */

/**
 * Load and flatten the Z<nn>SLOT0..6.BMX sprite banks for a zone TBL.
 *
 * Zone shape tables carry spriteBank == -1, so a textured poly's texture index
 * is a global index across the concatenation of all slot banks in slot order
 * (worldrender_paged_array_get). COMBAT.TBL / interior M-tables have no slot
 * banks; the returned array is empty and textured faces fall back to flat fill.
 * @param {import('./rmf.js').Archive} archive
 * @param {string} tblName
 * @returns {SpriteBanks}
 */
export function loadSpriteBanksFor(archive, tblName) {
  if (tblName.toUpperCase() === 'COMBAT.TBL') return combatBanks(archive);
  const m = tblName.toUpperCase().match(/^Z(\d+)M?\.TBL$/);
  const images = [];
  const slots = [];
  if (m) {
    for (let slot = 0; slot < 7; slot++) {
      const name = `Z${m[1]}SLOT${slot}.BMX`;
      const bytes = archive.getResource(name);
      if (!bytes) break; // zone loader stops at the first missing slot
      try {
        const bank = parseBmx(bytes);
        for (const img of bank) {
          img.bank = slot; // slot this global index resolves to
          images.push(img);
        }
        slots.push(name);
      } catch (e) {
        break;
      }
    }
  }
  return { images, slots };
}

/**
 * COMBAT.TBL sprite banks. During combat the engine swaps FIGS.BMX into
 * sprite bank slot 0 (COMBAT.C:155-156) — that serves the prop/effect models
 * (spells, rocks, crystals). Combatant models instead get their own sheet
 * swapped in per actor (WORLDHIT.C:713): `<base><digit>.BMX`, where the base
 * name and variant digits come from BNAMES.DAT indexed by the model index,
 * plus an optional CS<d>.DAT 256-byte pixel remap
 * (combat_actor_bnames_load_cached, CACTOR.C:481; resblit_list_remap_palette).
 * @param {import('./rmf.js').Archive} archive
 * @returns {SpriteBanks}
 */
function combatBanks(archive) {
  const parse = (name) => {
    const bytes = archive.getResource(name);
    if (!bytes) return null;
    try {
      const imgs = parseBmx(bytes);
      imgs.forEach((im) => { im.bank = 0; });
      return imgs;
    } catch (e) {
      return null;
    }
  };

  const figs = parse('FIGS.BMX') || [];
  let bnames = null;
  const bnBytes = archive.getResource('BNAMES.DAT');
  if (bnBytes) {
    try {
      bnames = parseBnames(bnBytes);
    } catch (e) {
      bnames = null;
    }
  }

  const cache = new Map(); // "<file>:<csx>" -> BmxImage[]|null
  const forModel = (modelIndex) => {
    const e = bnames && bnames[modelIndex];
    if (!e) return figs;
    const fname = `${e.name}${e.variants[0]}.BMX`.toUpperCase();
    const key = `${fname}:${e.csx}`;
    if (cache.has(key)) return cache.get(key) || figs;
    let imgs = parse(fname);
    if (imgs && e.csx >= 0) {
      const lut = archive.getResource(`CS${e.csx}.DAT`);
      if (lut && lut.length >= 256) {
        for (const im of imgs) {
          const px = im.pixels;
          for (let i = 0; i < px.length; i++) px[i] = lut[px[i]];
        }
      }
    }
    cache.set(key, imgs);
    return imgs || figs;
  };

  return { images: figs, slots: figs.length ? ['FIGS.BMX'] : [], forModel };
}

/**
 * Parse BNAMES.DAT: u16 count, u16 offsets[count], u16 blobSize, blob.
 * Each 8-byte entry at blob+offset: char name[4] (NUL-padded) +
 * i8 meta[4] = three sprite-sheet variant digits + CSX palette index (-1 =
 * none). Empty names mark non-combatant models (they use FIGS.BMX).
 * @param {Uint8Array} bytes
 * @returns {({name:string, variants:number[], csx:number}|null)[]}
 */
export function parseBnames(bytes) {
  const view = new DataView(bytes.buffer, bytes.byteOffset, bytes.byteLength);
  const count = view.getUint16(0, true);
  const blobStart = 2 + count * 2 + 2;
  const out = [];
  for (let i = 0; i < count; i++) {
    const off = blobStart + view.getUint16(2 + i * 2, true);
    let name = '';
    for (let k = 0; k < 4 && bytes[off + k]; k++) name += String.fromCharCode(bytes[off + k]);
    if (!name) {
      out.push(null);
      continue;
    }
    out.push({
      name,
      variants: [bytes[off + 4], bytes[off + 5], bytes[off + 6]],
      csx: view.getInt8(off + 7),
    });
  }
  return out;
}

/**
 * Decode a whole BMX resource into an array of images (in on-disk order).
 * @param {Uint8Array} bytes
 * @returns {BmxImage[]}
 */
export function parseBmx(bytes) {
  const view = new DataView(bytes.buffer, bytes.byteOffset, bytes.byteLength);
  const wMagic = view.getUint16(0, true);
  if (wMagic !== 0x1066) throw new Error(`BMX magic ${wMagic.toString(16)}`);
  const wCompression = view.getUint16(2, true);
  const wImageCount = view.getUint16(4, true);
  const dwDecompressedSize = view.getUint32(8, true);

  const dir = [];
  let p = 12;
  for (let i = 0; i < wImageCount; i++) {
    dir.push({
      chunk: view.getUint16(p, true),
      flags: view.getUint16(p + 2, true),
      width: view.getInt16(p + 4, true),
      height: view.getInt16(p + 6, true),
    });
    p += 8;
  }

  let payload;
  if (wCompression === 0) {
    // Payload stream: leading codec byte + u32 size, then codec data.
    const codec = bytes[p];
    const streamData = bytes.subarray(p + 5);
    if (codec === CODEC_LZW) {
      payload = lzwDecode(streamData, dwDecompressedSize);
    } else if (codec === 0) {
      payload = streamData.subarray(0, dwDecompressedSize);
    } else {
      throw new Error(`unsupported BMX stream codec ${codec}`);
    }
  } else if (wCompression === 2) {
    payload = engineRleDecode(bytes.subarray(p), dwDecompressedSize);
  } else {
    payload = lzssDecode(bytes.subarray(p), dwDecompressedSize);
  }

  const images = [];
  let off = 0;
  for (const d of dir) {
    const block = payload.subarray(off, off + d.chunk);
    off += d.chunk;
    // Flag bits: 0x80 = sprite-RLE compression; 0x20 = COLUMN-major pixel
    // layout (the Mode X column-walk blitters sample block[x*height + y] —
    // all zone textures/sprites carry it, RLE or raw). Images without 0x20
    // (the TTM scene panels like G_LAMUT, flags 0x40/0x00) are row-major
    // scanlines — transposing them produces diagonal-stripe garbage.
    let pixels = d.flags & 0x80
      ? spriteRle(block, d.width * d.height)
      : block.subarray(0, d.width * d.height);
    if (d.flags & 0x20) {
      pixels = columnToRowMajor(pixels, d.width, d.height);
    }
    images.push({ width: d.width, height: d.height, pixels });
  }
  return images;
}

/** Transpose an engine column-major pixel block to row-major. */
function columnToRowMajor(colMajor, width, height) {
  const out = new Uint8Array(width * height);
  for (let x = 0; x < width; x++) {
    const col = x * height;
    for (let y = 0; y < height; y++) {
      out[y * width + x] = colMajor[col + y] || 0;
    }
  }
  return out;
}

/**
 * Compress-style LZW decode (STREAM CODEC codec 2; LZWDEC.ASM).
 * Variable-width 9->12-bit codes, LSB-first, refilled `codeBits` bytes per
 * block; CLEAR = 0x100 resets the dictionary (first free code 0x101).
 * @param {Uint8Array} src   code stream (past the codec id + size prefix)
 * @param {number} outSize
 * @returns {Uint8Array}
 */
export function lzwDecode(src, outSize) {
  const out = new Uint8Array(outSize);
  let outLen = 0;
  const prefix = new Uint16Array(4096);
  const suffix = new Uint8Array(4096);
  const stack = new Uint8Array(4096);

  let pos = 0;
  let codeBits = 9;
  let maxCode = (1 << 9) - 1;
  let nextCode = 0x101;
  let resetPending = false;

  // Bit cursor over a `codeBits`-byte refill buffer.
  let buf = new Uint8Array(0);
  let inBitPos = 0;
  let inBufBits = 0;

  function extract() {
    let val = 0;
    for (let k = 0; k < codeBits; k++) {
      const bit = inBitPos + k;
      const b = buf[bit >> 3] || 0;
      if ((b >> (bit & 7)) & 1) val |= 1 << k;
    }
    inBitPos += codeBits;
    return val;
  }

  function refill() {
    const nb = Math.min(codeBits, src.length - pos);
    if (nb <= 0) {
      inBufBits = 0;
      return 0xffff;
    }
    buf = src.subarray(pos, pos + nb);
    pos += nb;
    inBitPos = 0;
    inBufBits = nb * 8 - (codeBits - 1);
    return extract();
  }

  function getCode() {
    if (nextCode > maxCode) {
      codeBits++;
      maxCode = codeBits === 12 ? 0x1000 : (1 << codeBits) - 1;
      if (resetPending) {
        codeBits = 9;
        maxCode = 0x1ff;
        resetPending = false;
        return refill();
      }
    } else if (resetPending) {
      codeBits = 9;
      maxCode = 0x1ff;
      resetPending = false;
      return refill();
    }
    if (inBitPos >= inBufBits) return refill();
    return extract();
  }

  let code = getCode();
  if (code === 0xffff) return out.subarray(0, outLen);
  let prevCode = code;
  let lastByte = code & 0xff;
  out[outLen++] = lastByte;

  while (outLen < outSize) {
    code = getCode();
    if (code === 0xffff) break;
    if (code === 0x100) {
      resetPending = true;
      nextCode = 0x101;
      code = getCode();
      if (code === 0xffff) break;
      prevCode = code;
      lastByte = code & 0xff;
      out[outLen++] = lastByte;
      continue;
    }
    let c = code;
    let sp = 0;
    if (c >= nextCode) {
      stack[sp++] = lastByte;
      c = prevCode;
    }
    while (c >= 0x100) {
      stack[sp++] = suffix[c];
      c = prefix[c];
    }
    stack[sp++] = c;
    lastByte = c & 0xff;
    while (sp > 0 && outLen < outSize) out[outLen++] = stack[--sp];
    if (nextCode < 0x1000) {
      prefix[nextCode] = prevCode;
      suffix[nextCode] = lastByte;
      nextCode++;
    }
    prevCode = code;
  }
  return out.subarray(0, outLen);
}

/**
 * LZSS decompressor (decomp_lzss, DECOMP.ASM; BMX header wCompression 1).
 * Flag byte = 8 bits LSB-first: 1 = literal byte, 0 = back-reference of
 * 3 bytes {u16 absolute output offset, u8 len} copying len+5 bytes from
 * earlier output. The engine copies back-references with REP MOVSW (word
 * granularity), which differs from byte-at-a-time on self-overlapping
 * copies — replicated here.
 * @param {Uint8Array} src
 * @param {number} outSize
 * @returns {Uint8Array}
 */
function lzssDecode(src, outSize) {
  const out = new Uint8Array(outSize);
  let o = 0;
  let p = 0;
  while (o < outSize && p < src.length) {
    const flag = src[p++];
    for (let bit = 0; bit < 8 && o < outSize && p < src.length; bit++) {
      if ((flag >> bit) & 1) {
        out[o++] = src[p++];
      } else {
        if (p + 3 > src.length) {
          p = src.length;
          break;
        }
        let ref = src[p] | (src[p + 1] << 8);
        const n = src[p + 2] + 5;
        p += 3;
        for (let k = n >> 1; k > 0 && o < outSize; k--) {
          const b0 = out[ref];
          const b1 = out[ref + 1];
          out[o++] = b0;
          if (o < outSize) out[o++] = b1;
          ref += 2;
        }
        if (n & 1 && o < outSize) out[o++] = out[ref];
      }
    }
  }
  return out;
}

/**
 * Payload byte-RLE (decomp_rle, DECOMP.ASM; BMX header wCompression 2).
 * Token low 7 bits = count (0 = end of stream, even with the high bit set);
 * high bit set = repeat the next byte `count` times, clear = literal run.
 * Same family as the per-image sprite RLE below, but the end condition
 * differs (sprite RLE only ends on a full-zero token).
 * @param {Uint8Array} src
 * @param {number} outSize
 * @returns {Uint8Array}
 */
function engineRleDecode(src, outSize) {
  const out = new Uint8Array(outSize);
  let o = 0;
  let p = 0;
  while (p < src.length && o < outSize) {
    const tok = src[p++];
    const cnt = tok & 0x7f;
    if (cnt === 0) break;
    if (tok & 0x80) {
      const val = src[p++];
      for (let k = 0; k < cnt && o < outSize; k++) out[o++] = val;
    } else {
      for (let k = 0; k < cnt && o < outSize && p < src.length; k++) out[o++] = src[p++];
    }
  }
  return out;
}

/**
 * Engine sprite RLE (POLYRAST.ASM, flags & 0x80). A byte `n`:
 *   n & 0x80 -> run: (n & 0x7f) copies of the following byte;
 *   n == 0   -> end;
 *   else     -> literal run of `n` bytes.
 * @param {Uint8Array} block
 * @param {number} outSize   width*height
 * @returns {Uint8Array}
 */
function spriteRle(block, outSize) {
  const out = new Uint8Array(outSize);
  let o = 0;
  let i = 0;
  while (i < block.length && o < outSize) {
    const n = block[i++];
    if (n & 0x80) {
      const cnt = n & 0x7f;
      const val = block[i++];
      for (let k = 0; k < cnt && o < outSize; k++) out[o++] = val;
    } else if (n === 0) {
      break;
    } else {
      for (let k = 0; k < n && o < outSize && i < block.length; k++) out[o++] = block[i++];
    }
  }
  return out;
}
