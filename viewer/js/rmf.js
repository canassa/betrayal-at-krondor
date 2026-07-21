// RMF archive reader for Betrayal at Krondor.
//
// KRONDOR.RMF is the index, KRONDOR.001 is the data blob. All little-endian.
//
// RMF layout:
//   u32      magic (=1)
//   u16      (=4)
//   char[13] archive name ("krondor.001")
//   u16      numResources
//   numResources x { u32 hashkey, u32 offset }   // offset points into the .001
//
// At each offset inside the .001:
//   char[13] resource name, NUL-padded ("Z01.TBL")
//   u32      size
//   u8[size] raw resource bytes

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

export class Archive {
  /**
   * @param {ArrayBuffer} rmfBuf  KRONDOR.RMF bytes
   * @param {ArrayBuffer} datBuf  KRONDOR.001 bytes
   */
  constructor(rmfBuf, datBuf) {
    this.dat = new Uint8Array(datBuf);
    const rmf = new DataView(rmfBuf);

    const magic = rmf.getUint32(0, true);
    if (magic !== 1) throw new Error(`RMF magic mismatch: ${magic}`);

    this.archiveName = readCString(rmf, 6, 13);
    const numResources = rmf.getUint16(19, true);

    /** @type {Map<string, {offset:number, size:number}>} */
    this.entries = new Map();

    const datView = new DataView(datBuf);
    let p = 21;
    for (let i = 0; i < numResources; i++) {
      // hashkey at p (unused), offset at p+4
      const offset = rmf.getUint32(p + 4, true);
      p += 8;

      const name = readCString(datView, offset, 13).toUpperCase();
      const size = datView.getUint32(offset + 13, true);
      // Store data offset (past the 13-byte name + u32 size).
      this.entries.set(name, { offset: offset + 17, size });
    }
  }

  /** All resource names. */
  names() {
    return [...this.entries.keys()];
  }

  hasResource(name) {
    return this.entries.has(name.toUpperCase());
  }

  /**
   * Return a resource's bytes as a Uint8Array view into the archive buffer
   * (no copy — do not mutate), or null if absent.
   * @returns {Uint8Array|null}
   */
  getResource(name) {
    const e = this.entries.get(name.toUpperCase());
    if (!e) return null;
    return this.dat.subarray(e.offset, e.offset + e.size);
  }

  /** All *.TBL resource names, sorted with COMBAT first then Z-order. */
  tableNames() {
    const tbls = this.names().filter((n) => n.endsWith('.TBL'));
    tbls.sort();
    return tbls;
  }
}

/**
 * Fetch both archive files whole and build an Archive.
 * @param {string} rmfUrl
 * @param {string} datUrl
 */
export async function loadArchive(rmfUrl, datUrl) {
  const [rmf, dat] = await Promise.all([
    fetch(rmfUrl).then((r) => {
      if (!r.ok) throw new Error(`fetch ${rmfUrl}: ${r.status}`);
      return r.arrayBuffer();
    }),
    fetch(datUrl).then((r) => {
      if (!r.ok) throw new Error(`fetch ${datUrl}: ${r.status}`);
      return r.arrayBuffer();
    }),
  ]);
  return new Archive(rmf, dat);
}
