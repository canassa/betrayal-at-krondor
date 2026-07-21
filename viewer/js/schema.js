// Schema-driven record decoder for the editor inspector layer.
//
// Every on-disk record in the game data (placements, container/fixed-object
// records, tile hotspots, GAM directory entries, TBL model headers) is
// described here by a declarative schema: a flat list of fields, each with a
// byte offset, a scalar type, an optional human meaning and a confidence tag
// (verified | inferred | unknown). The inspector renders whatever a schema
// yields, so unknown bytes are surfaced as hex fields rather than skipped —
// breadth-first honesty is a project rule.
//
// A schema field is either a static descriptor {name, off, type, meaning?,
// conf?} or a "section" function (view, base, record) => field[] that emits
// fields computed from already-decoded values (used by the container record's
// capacity-driven item array and mask-driven subrecords).

/** @typedef {'verified'|'inferred'|'unknown'} Confidence */

/**
 * @typedef {Object} Field
 * @property {string} name
 * @property {number} off       byte offset relative to the record base
 * @property {string} type      u8|i8|u16|i16|u32|i32|hex(n)
 * @property {string} [meaning]
 * @property {Confidence} [conf]
 */

/** Fixed scalar widths; hex(n) is parsed separately. */
const SCALAR = {
  u8: 1, i8: 1, u16: 2, i16: 2, u32: 4, i32: 4,
};

/** Registry of named schemas. */
const schemas = new Map();

/**
 * Register a schema.
 * @param {string} name
 * @param {(Field|Function)[]} fields  static descriptors and/or section fns
 * @returns {string} name
 */
export function defineSchema(name, fields) {
  schemas.set(name, fields);
  return name;
}

/** @returns {(Field|Function)[]|undefined} */
export function getSchema(name) {
  return schemas.get(name);
}

/** Coerce a Uint8Array or DataView argument into a DataView. */
function asView(buf) {
  if (buf instanceof DataView) return buf;
  return new DataView(buf.buffer, buf.byteOffset, buf.byteLength);
}

/** hex(n) -> n, else -1. */
function hexWidth(type) {
  const m = /^hex\((\d+)\)$/.exec(type);
  return m ? parseInt(m[1], 10) : -1;
}

/** Read one scalar. Returns {value, raw, size}. */
function readScalar(view, at, type) {
  switch (type) {
    case 'u8': { const v = view.getUint8(at); return { value: v, raw: v, size: 1 }; }
    case 'i8': { const v = view.getInt8(at); return { value: v, raw: v & 0xff, size: 1 }; }
    case 'u16': { const v = view.getUint16(at, true); return { value: v, raw: v, size: 2 }; }
    case 'i16': { const v = view.getInt16(at, true); return { value: v, raw: v & 0xffff, size: 2 }; }
    case 'u32': { const v = view.getUint32(at, true); return { value: v, raw: v, size: 4 }; }
    case 'i32': { const v = view.getInt32(at, true); return { value: v, raw: v >>> 0, size: 4 }; }
    default: throw new Error(`schema: unknown type ${type}`);
  }
}

/** Hex-dump a byte span into a spaced string. */
export function hexBytes(view, at, n) {
  let s = '';
  for (let i = 0; i < n; i++) {
    s += view.getUint8(at + i).toString(16).padStart(2, '0');
    if (i + 1 < n) s += ' ';
  }
  return s;
}

/**
 * Decode a single field descriptor at record base `base`.
 * @returns {{name, value, raw, off, size, conf, meaning}}
 */
function decodeField(view, base, f) {
  const at = base + f.off;
  const hw = hexWidth(f.type);
  if (hw >= 0) {
    return {
      name: f.name, off: f.off, size: hw, conf: f.conf || 'unknown',
      meaning: f.meaning, value: hexBytes(view, at, hw), raw: null, hex: true,
    };
  }
  const { value, raw, size } = readScalar(view, at, f.type);
  return {
    name: f.name, off: f.off, size, conf: f.conf || 'verified',
    meaning: f.meaning, value, raw, hex: false,
  };
}

/**
 * Decode a record against a named schema.
 *
 * Section functions may append computed fields (item slots, subrecords); they
 * receive the DataView, the record base and the in-progress record object
 * (with `.fields` decoded so far) and return more field descriptors.
 *
 * @param {string} schemaName
 * @param {DataView|Uint8Array} buf
 * @param {number} [offset]
 * @returns {{fields:Object[], size:number}}
 */
export function decode(schemaName, buf, offset = 0) {
  const fields = getSchema(schemaName);
  if (!fields) throw new Error(`no schema: ${schemaName}`);
  const view = asView(buf);
  const out = { fields: [], size: 0 };
  let end = 0;

  for (const f of fields) {
    if (typeof f === 'function') {
      const extra = f(view, offset, out) || [];
      for (const ef of extra) {
        const d = decodeField(view, offset, ef);
        out.fields.push(d);
        end = Math.max(end, ef.off + d.size);
      }
    } else {
      const d = decodeField(view, offset, f);
      out.fields.push(d);
      end = Math.max(end, f.off + d.size);
    }
  }
  out.size = end;
  return out;
}

// ------------------------------------------------------------------ schemas

// .WLD placement record (20 bytes; the file is a bare array of these).
export const WLD_RECORD = defineSchema('wldRecord', [
  { name: 'shapeId', off: 0, type: 'u16', conf: 'verified', meaning: 'index into zone TBL' },
  { name: 'variant', off: 2, type: 'i16', conf: 'unknown', meaning: 'always 0 in shipped data' },
  { name: 'payloadW0', off: 4, type: 'i16', conf: 'unknown' },
  { name: 'rotZ', off: 6, type: 'i16', conf: 'verified', meaning: 'binary angle, 0x10000 = full turn' },
  { name: 'worldX', off: 8, type: 'i32', conf: 'verified', meaning: 'absolute; tile = 64000 units' },
  { name: 'worldY', off: 12, type: 'i32', conf: 'verified' },
  { name: 'tail', off: 16, type: 'u32', conf: 'unknown', meaning: 'always 0' },
]);

// STARTUP.GAM directory entry (0x16 bytes; 20 at file offset 0x1177).
export const GAM_DIR_ENTRY = defineSchema('gamDirEntry', [
  { name: 'locationId', off: 0, type: 'u16', conf: 'verified', meaning: 'zone (1..12, 15)' },
  { name: 'unk04', off: 2, type: 'hex(4)', conf: 'unknown' },
  { name: 'tempOffset', off: 6, type: 'u32', conf: 'verified', meaning: 'direct STARTUP.GAM file offset' },
  { name: 'objfixedOffset', off: 10, type: 'u32', conf: 'verified', meaning: 'offset into OBJFIXED.DAT' },
  { name: 'unk0e', off: 14, type: 'hex(8)', conf: 'unknown' },
]);

/** Subrecord sizes by mask bit, from actorrec_size. */
export const SUBREC_SIZE = { 0x01: 4, 0x02: 6, 0x04: 16, 0x08: 9, 0x10: 4, 0x20: 2 };

/** Ascending mask-bit order the subrecords appear in. */
const SUBREC_BITS = [0x01, 0x02, 0x04, 0x08, 0x10, 0x20];

/**
 * Byte size of a container/fixed-object record given its header at `base`.
 * @param {DataView} view
 * @param {number} base
 */
export function containerRecordSize(view, base) {
  const capacity = view.getUint8(base + 14);
  const mask = view.getUint8(base + 15);
  let size = 16 + capacity * 4;
  for (const bit of SUBREC_BITS) if (mask & bit) size += SUBREC_SIZE[bit];
  return size;
}

// Container / fixed-object record. Identical layout in STARTUP.GAM temp blocks
// and OBJFIXED.DAT: 16-byte header + capacity*4 item slots + mask-ordered
// subrecords. The header fields are static; item slots and subrecords are
// emitted by section functions since their count/presence is data-driven.
export const CONTAINER_RECORD = defineSchema('containerRecord', [
  { name: 'zone', off: 0, type: 'u8', conf: 'verified', meaning: "block's locationId" },
  { name: 'chapterBand', off: 1, type: 'u8', conf: 'verified', meaning: 'min nibble high, max nibble low' },
  { name: 'shapeId', off: 2, type: 'u16', conf: 'inferred', meaning: 'redundant .WLD shape id' },
  { name: 'worldX', off: 4, type: 'i32', conf: 'verified', meaning: 'join key' },
  { name: 'worldY', off: 8, type: 'i32', conf: 'verified', meaning: 'join key' },
  { name: 'residence', off: 12, type: 'u8', conf: 'verified', meaning: '4=container 5=body 6=fixed object 9=self-spawn' },
  { name: 'filledSlots', off: 13, type: 'u8', conf: 'verified', meaning: 'items actually present' },
  { name: 'capacity', off: 14, type: 'u8', conf: 'verified', meaning: 'item slot count' },
  { name: 'subrecMask', off: 15, type: 'u8', conf: 'verified', meaning: 'which subrecords follow' },
  // Item slots (4 B each): engine ItemSlot {u8 itemId, u8 condition, u16 flags}.
  // condition = quantity for stackables, percent for weapons/armor, spell id for
  // item 0x85 (Magical Scroll). Flag bits 0x20/0x40 observed, meaning unknown.
  function itemSlots(view, base) {
    const cap = view.getUint8(base + 14);
    const out = [];
    for (let i = 0; i < cap; i++) {
      const rel = 16 + i * 4;
      out.push({ name: `item${i}.raw`, off: rel, type: 'u32', conf: 'inferred', meaning: 'raw slot word' });
      out.push({ name: `item${i}.itemId`, off: rel, type: 'u8', conf: 'verified' });
      out.push({ name: `item${i}.condition`, off: rel + 1, type: 'u8', conf: 'verified', meaning: 'qty | percent | spell id' });
      out.push({ name: `item${i}.flags`, off: rel + 2, type: 'u16', conf: 'inferred', meaning: 'bits 0x20/0x40 observed' });
    }
    return out;
  },
  // Mask-ordered subrecords. Each appears only when its bit is set; offsets
  // accumulate in ascending bit order after the item slots.
  function subrecords(view, base) {
    const cap = view.getUint8(base + 14);
    const mask = view.getUint8(base + 15);
    let rel = 16 + cap * 4;
    const out = [];
    if (mask & 0x01) {
      out.push(
        { name: 'lock.kindFlags', off: rel + 0, type: 'u8', conf: 'inferred', meaning: 'bit2 = pickable lock' },
        { name: 'lock.difficultyOrKey', off: rel + 1, type: 'u8', conf: 'inferred', meaning: '0-100 pick difficulty; door: key id' },
        { name: 'lock.cipherPuzzleId', off: rel + 2, type: 'u8', conf: 'inferred', meaning: 'nonzero = Moredhel wordlock' },
        { name: 'lock.lockedFlag', off: rel + 3, type: 'u8', conf: 'inferred' },
      );
      rel += SUBREC_SIZE[0x01];
    }
    if (mask & 0x02) {
      // Interact message {u8 kind, u8 flags, u32 messageId}. WCURSOR.C:295-365
      // building-interaction handler + SHOP.C:44: kind = service category
      // (2 = blacksmith, gates the price-gouging check; 3 observed on inns);
      // flags bit 0x01 = closed-hours gate (gstate event 0x753a), bit 0x02 =
      // OPENS TRADE SCREEN (cmbinv_inventory_screen_run — the bit that makes a
      // building a functioning shop), bit 0x20 = skip playing the message first.
      out.push(
        { name: 'msg.kind', off: rel + 0, type: 'u8', conf: 'verified', meaning: 'service kind: 2 = blacksmith (SHOP.C:44); 3 = inn' },
        { name: 'msg.flags', off: rel + 1, type: 'u8', conf: 'verified', meaning: 'bit0x01 closed-hours gate; bit0x02 opens trade screen; bit0x20 skip message' },
        { name: 'msg.messageId', off: rel + 2, type: 'u32', conf: 'verified', meaning: 'dialog record id (epitaphs, signs)' },
      );
      rel += SUBREC_SIZE[0x02];
    }
    if (mask & 0x04) {
      // Service params (shop / temple / inn). The 16-byte sub-4 block is a
      // multi-purpose union view (structs.h ActorSubrecord). SHOP.C:34-56 reads
      // it as ActorSubrec02_InteractMsg: byte @0 = bKind_or_id (shop-kind
      // discriminator; ==2 gates the zone-3 price-gouging event), byte @1 =
      // bFlags = PRICE MARKUP PERCENT (price = basePrice*(markup+100)/100). The
      // remaining bytes are the ActorSubrec04_EventState temple/inn/rest params
      // (structs.h:515). Full 16 bytes surfaced as hex too.
      out.push(
        { name: 'svc.bKind_or_id', off: rel + 0, type: 'u8', conf: 'verified', meaning: 'shop-kind discriminator (SHOP.C:44 ==2 = price gouging)' },
        { name: 'svc.markupPct', off: rel + 1, type: 'u8', conf: 'verified', meaning: 'price markup %: price = basePrice*(markup+100)/100 (SHOP.C:55)' },
        { name: 'svc.bArg2', off: rel + 2, type: 'u8', conf: 'inferred' },
        { name: 'svc.bArg3', off: rel + 3, type: 'u8', conf: 'inferred' },
        { name: 'svc.bTemple_filter', off: rel + 4, type: 'u8', conf: 'inferred' },
        { name: 'svc.bTeleport_cost_msb', off: rel + 5, type: 'u8', conf: 'inferred' },
        { name: 'svc.pad06', off: rel + 6, type: 'u8', conf: 'unknown' },
        { name: 'svc.bPopup_retry_counter', off: rel + 7, type: 'u8', conf: 'inferred' },
        { name: 'svc.bRest_gold_unit', off: rel + 8, type: 'u8', conf: 'inferred' },
        { name: 'svc.bRest_last_chapter_done', off: rel + 9, type: 'u8', conf: 'inferred' },
        { name: 'svc.bRest_target_hour', off: rel + 10, type: 'u8', conf: 'inferred' },
        { name: 'svc.bRest_gold_cost', off: rel + 11, type: 'u8', conf: 'inferred' },
        { name: 'svc.bInvreq_arg_x', off: rel + 12, type: 'u8', conf: 'inferred' },
        { name: 'svc.bInvreq_arg_y', off: rel + 13, type: 'u8', conf: 'inferred' },
        { name: 'svc.wShop_disposition_flags', off: rel + 14, type: 'u16', conf: 'inferred' },
        { name: 'svc.raw', off: rel + 0, type: 'hex(16)', conf: 'inferred', meaning: 'all 16 bytes' },
      );
      rel += SUBREC_SIZE[0x04];
    }
    if (mask & 0x08) {
      // Click dispatch (WCURSOR.C wcursor_click_npc_or_trap / _door_or_secret):
      // clicking the object fires hotspotevt_dispatch_at_point(7|8, x, y) — the
      // tile hotspot whose bbox contains the stored point. Click-only
      // transitions park that bbox on unreachable terrain (the (37-39,37-39)
      // corner convention), making it a lookup key rather than a walk-in area.
      out.push(
        { name: 'hotspot.pad', off: rel + 0, type: 'u16', conf: 'unknown' },
        { name: 'hotspot.gameStateEventId', off: rel + 2, type: 'u16', conf: 'inferred', meaning: 'sets a game-state flag' },
        { name: 'hotspot.warpKind', off: rel + 4, type: 'u8', conf: 'inferred' },
        { name: 'hotspot.warpDest', off: rel + 5, type: 'u8', conf: 'inferred' },
        { name: 'hotspot.hasHotspot', off: rel + 6, type: 'u8', conf: 'verified', meaning: 'on click, dispatch the kind-7/8 tile hotspot containing (x,y)' },
        { name: 'hotspot.hotspotX', off: rel + 7, type: 'u8', conf: 'verified', meaning: 'tile-local sub-cell' },
        { name: 'hotspot.hotspotY', off: rel + 8, type: 'u8', conf: 'verified' },
      );
      rel += SUBREC_SIZE[0x08];
    }
    if (mask & 0x10) {
      out.push({ name: 'lastTouch.gameTime', off: rel + 0, type: 'u32', conf: 'inferred', meaning: 'game time' });
      rel += SUBREC_SIZE[0x10];
    }
    if (mask & 0x20) {
      out.push({ name: 'door.variant', off: rel + 0, type: 'i16', conf: 'inferred' });
      rel += SUBREC_SIZE[0x20];
    }
    return out;
  },
]);

// Tile hotspot (19 bytes). Files are T<zz><xx><yy>.DAT: 10 chapter slots x 0xC0.
// The dispatch-relevant fields (eventFlagPre1/pre2, eventKeyPost, inhibitChapter,
// repeat) are promoted to verified from HOTSPOT.C:413-415 and the fire path.
export const ZONE_HOTSPOT = defineSchema('zoneHotspot', [
  { name: 'kind', off: 0, type: 'u16', conf: 'verified', meaning: '0 dialog 1 combat 3 dialog-def 7 trap/event 8 transition' },
  // Byte order matches the engine TileBBox (structs.h:411): min_x, max_y,
  // max_x, min_y. Containment test hotspotevt_find_at_point (HOTSPOT.C:983);
  // party grid pos = (world / 1600) % 40, no Y flip (CZONE.C:291). For
  // click-fired kind-7/8 hotspots the bbox is a dispatch key that may sit on
  // unreachable terrain, not a walk-in region.
  { name: 'bboxMinX', off: 2, type: 'u8', conf: 'verified', meaning: 'tile-local sub-cell' },
  { name: 'bboxMaxY', off: 3, type: 'u8', conf: 'verified' },
  { name: 'bboxMaxX', off: 4, type: 'u8', conf: 'verified' },
  { name: 'bboxMinY', off: 5, type: 'u8', conf: 'verified' },
  { name: 'defRecordIndex', off: 6, type: 'u32', conf: 'verified', meaning: 'record in DEF file selected by kind' },
  { name: 'inhibitChapter', off: 10, type: 'u8', conf: 'verified', meaning: 'nonzero: sets per-tile "done" flag after firing' },
  { name: 'eventFlagPre1', off: 11, type: 'u16', conf: 'verified', meaning: 'if nonzero, gstate flag must READ 1' },
  { name: 'eventFlagPre2', off: 13, type: 'u16', conf: 'verified', meaning: 'if nonzero, gstate flag must READ 0' },
  { name: 'eventKeyPost', off: 15, type: 'u16', conf: 'verified', meaning: 'gstate flag written 1 after firing' },
  { name: 'repeat', off: 17, type: 'u16', conf: 'verified', meaning: '0 = one-shot bookkeeping on dialog kinds' },
]);

// OBJINFO.DAT item record (80 bytes; flat array of 138 from file offset 0).
// char name[32] then the LE scalar fields (verified against the engine
// ItemRecord). Trailing bytes to 80 are surfaced as hex.
export const ITEM_RECORD = defineSchema('itemRecord', [
  { name: 'name', off: 0, type: 'hex(32)', conf: 'verified', meaning: 'NUL-terminated char[32]' },
  { name: 'flags', off: 32, type: 'u16', conf: 'inferred' },
  { name: 'nameSplitOff', off: 34, type: 'u16', conf: 'inferred' },
  { name: 'damageClassThreshold', off: 36, type: 'u16', conf: 'inferred' },
  { name: 'basePrice', off: 38, type: 'i16', conf: 'inferred' },
  { name: 'swingDamage', off: 40, type: 'i16', conf: 'inferred' },
  { name: 'thrustDamage', off: 42, type: 'i16', conf: 'inferred' },
  { name: 'defenseOrRangeClose', off: 44, type: 'i16', conf: 'inferred' },
  { name: 'attackOrRangeLong', off: 46, type: 'i16', conf: 'inferred' },
  { name: 'unk30', off: 48, type: 'u16', conf: 'unknown' },
  { name: 'defaultQty', off: 50, type: 'u16', conf: 'inferred' },
  { name: 'useSfx', off: 52, type: 'u16', conf: 'inferred' },
  { name: 'maxStack', off: 54, type: 'u8', conf: 'verified', meaning: '>1 = stackable' },
  { name: 'chargesPerUse', off: 55, type: 'u8', conf: 'inferred' },
  { name: 'raceMask', off: 56, type: 'u16', conf: 'inferred' },
  { name: 'subFlags', off: 58, type: 'u16', conf: 'inferred' },
  { name: 'category', off: 60, type: 'u16', conf: 'verified', meaning: '1-4 = weapon/armor' },
  { name: 'effectArgA', off: 62, type: 'u16', conf: 'inferred' },
  { name: 'effectArgB', off: 64, type: 'u16', conf: 'inferred' },
  { name: 'effectChancePct', off: 66, type: 'u16', conf: 'inferred' },
  { name: 'effectStatValue', off: 68, type: 'u16', conf: 'inferred' },
  { name: 'playerStatMask', off: 70, type: 'u16', conf: 'inferred' },
  { name: 'statValue', off: 72, type: 'i16', conf: 'inferred' },
  { name: 'weaponBreakChancePct', off: 74, type: 'u16', conf: 'inferred' },
  { name: 'unk4c', off: 76, type: 'hex(4)', conf: 'unknown' },
]);

// DIAL_Z<nn>.DDX record header (9 bytes, PACKED). Choices (10 B each) and ops
// (10 B each) follow the header, then bodyLen bytes of text; those variable
// sections are parsed by gamedata.js, not this static schema.
export const DDX_RECORD = defineSchema('ddxRecord', [
  { name: 'style', off: 0, type: 'u8', conf: 'verified' },
  { name: 'speakerId', off: 1, type: 'u16', conf: 'verified' },
  { name: 'flags', off: 3, type: 'u16', conf: 'verified' },
  { name: 'choiceCount', off: 5, type: 'u8', conf: 'verified' },
  { name: 'opCount', off: 6, type: 'u8', conf: 'verified' },
  { name: 'bodyLen', off: 7, type: 'u16', conf: 'verified' },
]);

// ---------------------------------------------------------------- DEF records
//
// DEF databases sit behind zone tile hotspots: ZoneHotspot.kind selects the
// file AND the record layout (HOTSPOT.C dispatch; kind == file index). Records
// are read with a 4-byte file header then a present-byte-prefixed stride of
// (recordSize+1) — gamedata.js hands decode() the already-stripped record
// bytes, so these schemas are offset-from-record-start. Every layout below is
// engine-verified (HOTSPOT.C + structs.h). "dlgKey" fields chain to the dialog
// expandable (cipher rule as in Phase 2). Every record opens with a 2-byte
// header field wGap0 of unknown semantics.

// BKGR (0) / TOWN (6), 21 bytes — identical layout (HOTSPOT.C:366-399,626-660).
export const DEF_BKGR = defineSchema('defBkgr', [
  { name: 'wGap0', off: 0, type: 'u16', conf: 'unknown' },
  { name: 'sceneId', off: 2, type: 'u16', conf: 'verified', meaning: 'arg to townscene_main_loop' },
  { name: 'dlgKey', off: 6, type: 'u32', conf: 'verified', meaning: 'popup message played (0 = none)' },
  { name: 'walkSubX', off: 0xE, type: 'u8', conf: 'verified', meaning: 'camera walk-to target (TileMoveRecord)' },
  { name: 'walkSubY', off: 0xF, type: 'u8', conf: 'verified' },
  { name: 'walkHeading', off: 0x10, type: 'i16', conf: 'verified' },
  { name: 'animateCamera', off: 0x12, type: 'u8', conf: 'verified', meaning: 'nonzero: animate camera to the walk target first' },
  { name: 'tail', off: 0x13, type: 'hex(2)', conf: 'unknown' },
]);

// DIAL (3) / BLOC (11), 8 bytes.
export const DEF_DIAL = defineSchema('defDial', [
  { name: 'wGap0', off: 0, type: 'u16', conf: 'unknown' },
  { name: 'dlgKey', off: 2, type: 'u32', conf: 'verified', meaning: 'dialog record played' },
  { name: 'tail', off: 6, type: 'hex(2)', conf: 'unknown' },
]);

// ZONE (8), 19 bytes = ZoneEntryRecord (structs.h:1694). Destination the party
// is placed at plus two dialog keys.
export const DEF_ZONE = defineSchema('defZone', [
  { name: 'wGap0', off: 0, type: 'u16', conf: 'unknown' },
  { name: 'zoneId', off: 2, type: 'u8', conf: 'verified', meaning: 'destination zone' },
  { name: 'tileX', off: 3, type: 'u8', conf: 'verified' },
  { name: 'tileY', off: 4, type: 'u8', conf: 'verified' },
  { name: 'subX', off: 5, type: 'u8', conf: 'verified' },
  { name: 'subY', off: 6, type: 'u8', conf: 'verified' },
  { name: 'cameraHeading', off: 7, type: 'u16', conf: 'verified' },
  { name: 'promptDlgKey', off: 9, type: 'u32', conf: 'verified', meaning: 'confirmation dialog (try_enter path)' },
  { name: 'entryDlgKey', off: 0xD, type: 'u32', conf: 'verified', meaning: 'played on entry (0 = none)' },
  { name: 'tail', off: 0x11, type: 'hex(2)', conf: 'unknown' },
]);

// SOUN (5), 7 bytes: chance-gated sound effect.
export const DEF_SOUN = defineSchema('defSoun', [
  { name: 'wGap0', off: 0, type: 'u16', conf: 'unknown' },
  { name: 'chancePct', off: 2, type: 'u8', conf: 'verified' },
  { name: 'sfxId', off: 3, type: 'u16', conf: 'verified', meaning: 'audio_sfx_play_n_times' },
  { name: 'tail', off: 5, type: 'hex(2)', conf: 'unknown' },
]);

// DISA (9) / ENAB (10), 7 bytes: chance-gated gstate event write (0 / 1).
export const DEF_DISA = defineSchema('defDisa', [
  { name: 'wGap0', off: 0, type: 'u16', conf: 'unknown' },
  { name: 'chancePct', off: 2, type: 'u8', conf: 'verified' },
  { name: 'eventKey', off: 3, type: 'u16', conf: 'verified', meaning: 'on success writes gstate event 0 (DISA) / 1 (ENAB)' },
  { name: 'tail', off: 5, type: 'hex(2)', conf: 'unknown' },
]);

/**
 * Combatant slot section for the COMB/TRAP records. CombatantData is 48 bytes;
 * `n` slots start at `base`, but only the first `live` are populated (the rest
 * are surfaced collapsed by the inspector). `pos` x/y are tile-relative world
 * units (engine adds tileX*64000).
 */
function combatantFields(baseOff, i) {
  const b = baseOff + i * 48;
  return [
    { name: `comb${i}.monsterIndex`, off: b + 0x00, type: 'u16', conf: 'verified' },
    { name: `comb${i}.movementType`, off: b + 0x02, type: 'u16', conf: 'verified', meaning: '0 = stationary; 1/2/4 = patrol' },
    { name: `comb${i}.posX`, off: b + 0x04, type: 'i32', conf: 'verified', meaning: 'spawn pos, tile-relative' },
    { name: `comb${i}.posY`, off: b + 0x08, type: 'i32', conf: 'verified' },
    { name: `comb${i}.heading`, off: b + 0x0C, type: 'u16', conf: 'verified' },
    // Patrol bounds are only meaningful when movementType != 0; a stationary
    // combatant leaves them uninitialized (garbage). The inspector dims them.
    { name: `comb${i}.minX`, off: b + 0x0E, type: 'u32', conf: 'inferred', meaning: 'patrol bound (movementType != 0 only)' },
    { name: `comb${i}.maxX`, off: b + 0x12, type: 'u32', conf: 'inferred' },
    { name: `comb${i}.unk16`, off: b + 0x16, type: 'hex(8)', conf: 'unknown' },
    { name: `comb${i}.minY`, off: b + 0x1E, type: 'u32', conf: 'inferred', meaning: 'patrol bound (movementType != 0 only)' },
    { name: `comb${i}.maxY`, off: b + 0x22, type: 'u32', conf: 'inferred' },
    { name: `comb${i}.unk26`, off: b + 0x26, type: 'hex(10)', conf: 'unknown' },
  ];
}

/** GamePositionAndHeading @off: {s32 x, s32 y, u16 heading} (10 bytes). */
function posHeadingFields(prefix, off) {
  return [
    { name: `${prefix}.x`, off: off + 0, type: 'i32', conf: 'verified', meaning: 'tile-relative world units' },
    { name: `${prefix}.y`, off: off + 4, type: 'i32', conf: 'verified' },
    { name: `${prefix}.heading`, off: off + 8, type: 'u16', conf: 'verified' },
  ];
}

// COMB (1), 399 bytes = DefTrapRecord minus landing_primary (structs.h:802).
export const DEF_COMB = defineSchema('defComb', [
  { name: 'wGap0', off: 0, type: 'u16', conf: 'unknown' },
  { name: 'combatIndex', off: 0x02, type: 'u32', conf: 'verified', meaning: 'persistent encounter id (bookkeeping key)' },
  { name: 'entryDlgKey', off: 0x06, type: 'u32', conf: 'verified', meaning: 'played when combat triggers (0 = none)' },
  { name: 'scoutDlgKey', off: 0x0A, type: 'u32', conf: 'verified', meaning: 'on successful scouting (0 = engine default 0x2F)' },
  { name: 'zero', off: 0x0E, type: 'u32', conf: 'unknown', meaning: 'reserved' },
  ...posHeadingFields('landingN', 0x12),
  ...posHeadingFields('landingE', 0x1C),
  ...posHeadingFields('landingS', 0x26),
  ...posHeadingFields('landingW', 0x30),
  { name: 'numEnemies', off: 0x3A, type: 'u8', conf: 'verified' },
  function combatants() {
    const out = [];
    for (let i = 0; i < 7; i++) out.push(...combatantFields(0x3B, i));
    return out;
  },
  { name: 'unk18B', off: 0x18B, type: 'u16', conf: 'unknown' },
  { name: 'flags', off: 0x18D, type: 'u16', conf: 'verified', meaning: 'bit 0 = ambush (scoutable)' },
]);

// TRAP (7), 409 bytes = DefTrapRecord verbatim: COMB plus landingPrimary @0x3A,
// so numEnemies @0x44, combatants @0x45, flags @0x197.
export const DEF_TRAP = defineSchema('defTrap', [
  { name: 'wGap0', off: 0, type: 'u16', conf: 'unknown' },
  { name: 'combatIndex', off: 0x02, type: 'u32', conf: 'verified', meaning: 'persistent encounter id' },
  { name: 'entryDlgKey', off: 0x06, type: 'u32', conf: 'verified', meaning: 'played when combat triggers (0 = none)' },
  { name: 'scoutDlgKey', off: 0x0A, type: 'u32', conf: 'verified', meaning: 'on successful scouting (0 = engine default 0x2F)' },
  { name: 'zero', off: 0x0E, type: 'u32', conf: 'unknown', meaning: 'reserved' },
  ...posHeadingFields('landingN', 0x12),
  ...posHeadingFields('landingE', 0x1C),
  ...posHeadingFields('landingS', 0x26),
  ...posHeadingFields('landingW', 0x30),
  ...posHeadingFields('landingPrimary', 0x3A),
  { name: 'numEnemies', off: 0x44, type: 'u8', conf: 'verified' },
  function combatants() {
    const out = [];
    for (let i = 0; i < 7; i++) out.push(...combatantFields(0x45, i));
    return out;
  },
  { name: 'unk195', off: 0x195, type: 'u16', conf: 'unknown' },
  { name: 'flags', off: 0x197, type: 'u16', conf: 'verified', meaning: 'bit 0 = ambush (scoutable)' },
]);

// COMM (2), 10 bytes / HEAL (4), 13 bytes: no consumer in the world hotspot
// dispatch path — kept as a single hex field (see gamedata note).
export const DEF_COMM = defineSchema('defComm', [
  { name: 'raw', off: 0, type: 'hex(10)', conf: 'unknown', meaning: 'not consumed by zone hotspot dispatch' },
]);
export const DEF_HEAL = defineSchema('defHeal', [
  { name: 'raw', off: 0, type: 'hex(13)', conf: 'unknown', meaning: 'not consumed by zone hotspot dispatch' },
]);

// Schema name selected per hotspot kind (index == kind). null = hex-only.
export const DEF_SCHEMA_BY_KIND = [
  'defBkgr', // 0
  'defComb', // 1
  'defComm', // 2
  'defDial', // 3
  'defHeal', // 4
  'defSoun', // 5
  'defBkgr', // 6 TOWN, identical layout
  'defTrap', // 7
  'defZone', // 8
  'defDisa', // 9
  'defDisa', // 10 ENAB, identical layout
  'defDial', // 11 BLOC, identical layout
];

// TBL model header (the parsed record; offsets relative to the record start).
export const TBL_MODEL = defineSchema('tblModel', [
  { name: 'bFlags', off: 0x0, type: 'u8', conf: 'verified' },
  { name: 'bKind', off: 0x1, type: 'u8', conf: 'verified' },
  { name: 'bPriority', off: 0x2, type: 'u8', conf: 'verified' },
  { name: 'bShift', off: 0x3, type: 'u8', conf: 'verified' },
  { name: 'unk04', off: 0x4, type: 'hex(4)', conf: 'unknown' },
  { name: 'nLodCount', off: 0x8, type: 'i16', conf: 'verified' },
  { name: 'pLod', off: 0xa, type: 'u16', conf: 'verified', meaning: 'near ptr to LOD array' },
  { name: 'nRadius', off: 0xc, type: 'i16', conf: 'verified' },
  { name: 'unk0e', off: 0xe, type: 'hex(4)', conf: 'unknown' },
]);
