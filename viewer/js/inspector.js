// Right-side inspector overlay for the editor layer (tabbed).
//
// The entity join is presented as a tabbed
// panel with a sticky header:
//   Overview   — curated human summary (no hex): shape/class, lock+answer,
//                item names, dialog first-lines, one-liner per hotspot,
//                provenance chips. Every line deep-links to the owning tab.
//   Placement  — .WLD record fields + tile + source file name
//                (labeled "Spawn" for self-spawned objects)
//   Shape      — TBL model header fields + a link back to the Models tab
//   State      — the container/fixed-object record (header, item table,
//                subrecords) with a provenance line "STARTUP.GAM @0x3B8A6"
//   Behavior   — decoded DEF records behind the entity tile's hotspots for the
//                current chapter: named fields (combat/zone/dialog/sound) with
//                dialog keys chaining to the dialog expandable, raw hex behind a
//                per-record expandable
// Tabs with no data are hidden. showEntity() keeps the tab set (an entity has
// several genuine facets). showHotspot()/showTile() do NOT tab: a hotspot has
// ONE story, so they render a single flat view (renderSingle), top-to-bottom:
// provenance lines (T-file @offset; DEF file · present · size), the decoded
// DEF payload, the folded full field tables, and the raw-hex expandable.
// Dialog references render as ONE compact clickable row each (label + key +
// truncated preview + "graph ⤴") — dialog CONTENT lives in the node viewer,
// never expanded inline here.
//
// Every rendered field carries its confidence tag and, for unknown/inferred
// scalars, a dimmed raw hex value — the panel never hides bytes it cannot name.
// Read-only: nothing here writes game data.

import { cipherDialogKey, itemIsSpellScroll } from './gamedata.js';

const el = () => document.getElementById('inspector');

/** Max nesting depth for choice targetKey -> dialog record expansion. */
const DIALOG_MAX_DEPTH = 3;

/** Callbacks wired by main.js (tab switch + model select). */
let onOpenModel = null;
/** Callback wired by main.js: fires after a tab becomes active (for READY line). */
let onTabChange = null;
/** Callback wired by main.js: open the DIALOG tab on a dialog key ("⤴ graph"). */
let onDialogGraph = null;

/** @param {(tbl:string, model:number)=>void} fn */
export function setOpenModelHandler(fn) { onOpenModel = fn; }
/** @param {(tab:string)=>void} fn */
export function setTabChangeHandler(fn) { onTabChange = fn; }
/** @param {(key:number)=>void} fn */
export function setDialogGraphHandler(fn) { onDialogGraph = fn; }

/** A small "⤴ graph" link that deep-links a dialog key into the DIALOG tab. */
function graphLink(key) {
  const k = (key & 0x7fffffff) >>> 0;
  return ` <span class="link dlg-graph" data-dlgkey="${k}" title="open in dialog graph">⤴ graph</span>`;
}


/** Active tab id while the panel stays open (default Overview). */
let activeTab = 'overview';
/**
 * Context for the prop Overview's "open tile view" muted line: the zone/tile/
 * chapter/gameData needed to call showTile without touching main.js. Set by
 * showEntity, consumed by the data-open-tile click handler in wire().
 */
let tileOpenCtx = null;
/** The tab id requested via ?tab= for the next open (consumed once). */
let pendingTab = null;

/** @param {string|null} tab  set the tab to auto-activate on the next open. */
export function requestTab(tab) { pendingTab = tab ? tab.toLowerCase() : null; }

/** The currently active tab id (for the READY line). */
export function currentTab() { return activeTab; }

export function hideInspector() {
  const p = el();
  p.classList.add('hidden');
  p.innerHTML = '';
}

function esc(s) {
  return String(s).replace(/[&<>]/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;' }[c]));
}

function hex(n, w = 0) {
  return '0x' + (n >>> 0).toString(16).toUpperCase().padStart(w, '0');
}

/**
 * A confidence dot after a field name. Verified is the default state and gets
 * no dot; inferred/unknown render an amber/red dot whose native tooltip is the
 * confidence word. Kept tiny so the row reads `name • value`, not a badge wall.
 */
function confDot(conf) {
  if (!conf || conf === 'verified') return '';
  return `<span class="dot ${conf}" title="${conf}"></span>`;
}

/** Escape a string for use inside an HTML attribute value (title=). */
function attr(s) {
  return String(s).replace(/[&<>"]/g, (c) =>
    ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;' }[c]));
}

/**
 * The hover-tooltip text for a field name: byte offset, then the meaning and
 * (for named scalars) the raw hex value. All the per-row explanation that used
 * to pollute the visible table now lives here.
 */
function fieldTitle(f) {
  const parts = [`+${hex(f.off)}`];
  if (f.meaning) parts.push(f.meaning);
  if (!f.hex && f.conf && f.conf !== 'verified') parts.push(`raw ${hex(f.raw)}`);
  return parts.join('  ·  ');
}

/**
 * One <tr> for a decoded schema field. The visible row is just `name  value`
 * (with a confidence dot after unverified names); the description, byte offset
 * and raw hex move into a hover tooltip on the name cell.
 */
function fieldRow(f) {
  const val = f.hex ? `<span class="raw">${esc(f.value)}</span>` : esc(f.value);
  return `<tr><td class="k" title="${attr(fieldTitle(f))}">${esc(f.name)}${confDot(f.conf)}</td>`
    + `<td>${val}</td></tr>`;
}

/** A field is "noise" when its value is 0/default and it is not verified. */
function isDefaultNoise(f) {
  if (!f.conf || f.conf === 'verified') return false;
  if (f.hex) return /^(00\s*)+$/.test(f.value);
  return f.value === 0;
}

/**
 * Render a field table. Rows whose value is a zero/default on an unverified
 * field collapse into one muted `▸ N more fields (defaults)` expandable when
 * there are more than two of them — non-zero gates always render visibly.
 */
function fieldsTable(fields) {
  const visible = [];
  const defaults = [];
  for (const f of fields) (isDefaultNoise(f) ? defaults : visible).push(f);
  let html = `<table>${visible.map(fieldRow).join('')}</table>`;
  if (defaults.length > 2) {
    html += `<details class="defaults"><summary>${defaults.length} more fields (defaults)</summary>`
      + `<table>${defaults.map(fieldRow).join('')}</table></details>`;
  } else if (defaults.length) {
    html = `<table>${fields.map(fieldRow).join('')}</table>`;
  }
  return html;
}

/** Human residence label. */
function residenceLabel(v) {
  return { 0: 'none', 4: 'container', 5: 'body', 6: 'fixed object', 9: 'self-spawn' }[v] || `?${v}`;
}

/** Service-kind label for the interact-message sub-2 `kind` byte (SHOP.C:44). */
function serviceKindLabel(kind) {
  return { 2: 'blacksmith', 3: 'inn' }[kind] || null;
}

/**
 * Decode the interact-message `flags` byte into its engine-verified bits
 * (WCURSOR.C:295-365): 0x01 closed-hours gate, 0x02 opens trade screen, 0x20
 * skip message. Returns an array of short labels for the bits that are set.
 */
function interactFlagLabels(flags) {
  const out = [];
  if (flags & 0x01) out.push('closed-hours gate');
  if (flags & 0x02) out.push('trade screen');
  if (flags & 0x20) out.push('skip message');
  return out;
}

// ------------------------------------------------------------------ sections

function placementSection(entity) {
  const p = entity.placement;
  const rows = [
    ['shapeId', p.id],
    ['variant', p.variant],
    ['rotZ', `${p.rotZ} (${(p.rotZ * 360 / 0x10000).toFixed(1)}°)`],
    ['worldX', p.x],
    ['worldY', p.y],
    ['tile', `${entity.tileX},${entity.tileY}`],
  ];
  const tbl = rows.map(([k, v]) => `<tr><td class="k">${k}</td><td>${esc(v)}</td></tr>`).join('');
  return `<h3>Placement</h3>`
    + `<div class="prov">${esc(entity.tileFile || '')} · placement #${entity.index}</div>`
    + `<table>${tbl}</table>`;
}

/**
 * "Spawn" section: the Placement variant for self-spawned objects (no .WLD
 * record). Provenance is the STARTUP.GAM temp-block offset; the one-line spawn
 * rule and the chapter band are shown so the reader knows why it appears.
 */
function spawnSection(entity) {
  const s = entity.spawn;
  const provFile = s.source === 'startup' ? 'STARTUP.GAM' : 'OBJFIXED.DAT';
  const rows = [
    ['shapeId', s.shapeId],
    ['worldX', s.x],
    ['worldY', s.y],
    ['tile', `${entity.tileX},${entity.tileY}`],
    ['chapter band', `${s.chapterMin}–${s.chapterMax}`],
  ];
  const tbl = rows.map(([k, v]) => `<tr><td class="k">${k}</td><td>${esc(v)}</td></tr>`).join('');
  return `<h3>Spawn</h3>`
    + `<div class="prov">${provFile} @${hex(s.offset)} · self-spawned on zone entry</div>`
    + `<div class="prov muted">rule: (subrecMask &amp; 0x80) or residence 9, no .WLD placement</div>`
    + `<table>${tbl}</table>`;
}

function shapeSection(entity) {
  if (!entity.model) return `<h3>Shape</h3><p class="muted">no model</p>`;
  const m = entity.model;
  const rows = [
    ['name', m.name],
    ['index', m.index],
    ['bFlags', hex(m.bFlags, 2)],
    ['bKind', m.bKind],
    ['bPriority', m.bPriority],
    ['bShift', m.bShift],
    ['nLodCount', m.nLodCount],
    ['nRadius', m.nRadius],
  ];
  const tbl = rows.map(([k, v]) => `<tr><td class="k">${k}</td><td>${esc(v)}</td></tr>`).join('');
  return `<h3>Shape</h3>`
    + `<div class="prov">${esc(entity.tblName || '')}</div>`
    + `<table>${tbl}</table>`
    + `<div><span class="link" data-open-model="${m.index}">open in Models tab →</span></div>`;
}

/**
 * Human label for one item slot. Uses the joined OBJINFO.DAT record so the
 * condition byte reads as quantity / percent / spell id per item semantics.
 */
function itemLabel(id, condition, gameData) {
  const name = (gameData && gameData.itemName(id)) || `item ${id}`;
  if (itemIsSpellScroll(id)) return `${name} (spell ${condition})`;
  if (gameData && gameData.itemIsConditioned(id)) return `${name} (${condition}%)`;
  if (gameData && gameData.itemIsStackable(id)) return `${name} ×${condition}`;
  return name;
}

/**
 * Item slot table. Filled slots show `name` with the semantic condition
 * (`×qty`, `(NN%)`, `spell N`); the raw slot word stays available per row.
 * Trailing empty slots collapse to a single "n empty slots" line.
 */
function itemTable(record, gameData) {
  if (!record.capacity) return '';
  const view = record.view;
  const base = record.offset;
  const rows = [];
  let emptyRun = 0;
  const flushEmpty = () => {
    if (emptyRun) {
      rows.push(`<tr class="muted"><td></td><td colspan="3">${emptyRun} empty slot${emptyRun > 1 ? 's' : ''}</td></tr>`);
      emptyRun = 0;
    }
  };
  for (let i = 0; i < record.capacity; i++) {
    const o = base + 16 + i * 4;
    const id = view.getUint8(o);
    const cond = view.getUint8(o + 1);
    const flags = view.getUint16(o + 2, true);
    const raw = view.getUint32(o, true);
    const filled = i < record.filledSlots && id !== 0;
    if (!filled) { emptyRun++; continue; }
    flushEmpty();
    rows.push(`<tr>`
      + `<td>${i}</td>`
      + `<td>${esc(itemLabel(id, cond, gameData))}</td>`
      + `<td class="raw">${hex(flags, 4)}</td>`
      + `<td class="raw">${hex(raw, 8)}</td></tr>`);
  }
  flushEmpty();
  return `<table class="itemtbl">`
    + `<tr><td class="k">slot</td><td class="k">item</td>`
    + `<td class="k">flags</td><td class="k">raw</td></tr>`
    + rows.join('') + `</table>`;
}

/** Render a dialog text body: keep \n as breaks, escape all bytes, mark control bytes. */
function renderDialogBody(textBytes) {
  let out = '';
  for (const b of textBytes) {
    if (b === 0x0a) out += '\n';
    else if (b === 0x09) out += '⇥'; // tab (paragraph indent)
    else if (b < 0x20) out += String.fromCharCode(0x2400 + b); // control picture
    else out += String.fromCharCode(b);
  }
  return esc(out);
}

/** First non-empty text line of a dialog record's OWN body (no recursion). */
function dialogFirstLine(rec, maxLen = 28) {
  let s = '';
  for (const b of rec.textBytes) {
    if (b === 0x0a) { if (s) break; else continue; }
    if (b === 0x09) s += '⇥'; // tab
    else if (b < 0x20) s += String.fromCharCode(0x2400 + b); // control picture
    else s += String.fromCharCode(b);
    if (s.length >= maxLen) { s += '…'; break; }
  }
  return s;
}

/**
 * A DDX choice/entry `targetKey` carries bit 31 (0x80000000): SET = global
 * directory key, CLEAR = raw same-file offset. Resolution needs the parent
 * record's file, so children are followed via gameData.dialogChild(parent,
 * targetKey) rather than by masking the value to a bare key. This mask is kept
 * only for building a display label / cycle-guard id from a target.
 */
const DDX_TARGET_MASK = 0x7fffffff;
function dialogTargetKey(target) { return (target & DDX_TARGET_MASK) >>> 0; }

/** Stable identity for a child record, for cycle-guard sets and display. */
function recordId(rec) {
  return rec ? `${rec.fileNumber}:${rec.offset}` : 'null';
}

/**
 * A dialog node's entries are engine-evaluated CONDITIONS (a branch tree), not
 * player choices, when it has entries AND either the node body is empty or any
 * entry carries a nonzero stateQuery (DDX `cond`). Plain player-choice menus
 * have a body and all-zero conds.
 */
function dialogIsBranch(rec) {
  if (!rec.choices.length) return false;
  if (!rec.textBytes.length) return true;
  return rec.choices.some((c) => c.cond !== 0);
}

/**
 * Summary first line for a dialog record used in Overview/one-liners and
 * expandable headers. Own body if present; otherwise (empty-body branch node)
 * the first resolvable CHILD's first line, recursively — so a condition node
 * shows the flavor text it dispatches to, never "". `seen` guards cycles.
 */
function dialogSummary(rec, gameData, maxLen = 28, seen = null) {
  if (!rec) return '';
  const own = dialogFirstLine(rec, maxLen);
  if (own) return own;
  if (!gameData) return '';
  const visited = seen || new Set();
  visited.add(recordId(rec));
  for (const c of rec.choices) {
    if (!c.targetKey) continue;
    const child = gameData.dialogChild(rec, c.targetKey);
    if (!child || visited.has(recordId(child))) continue;
    const line = dialogSummary(child, gameData, maxLen, visited);
    if (line) return line;
  }
  return '';
}

/** Summary first line for a dialog key (fetches the record). */
function dialogSummaryForKey(key, gameData, maxLen = 28) {
  if (!gameData) return '';
  const rec = gameData.dialogRecord(dialogTargetKey(key));
  return dialogSummary(rec, gameData, maxLen);
}

/** Render one condition-entry header: `if state N in lo..hi →` or `else →`. */
function branchEntryHead(c) {
  const isElse = c.cond === 0 && c.rangeMinOrMask === 0 && c.rangeMaxOrChapbits === 0;
  if (isElse) return 'else →';
  return `if state ${c.cond} in ${c.rangeMinOrMask}..${c.rangeMaxOrChapbits} →`;
}

/** Ops table for a dialog record. */
function dialogOpsTable(ops) {
  if (!ops.length) return '';
  const rows = ops.map((o, i) => `<tr><td class="k">${i}</td>`
    + `<td>${o.op}</td><td>${o.a1}</td><td>${o.a2}</td><td>${o.a3}</td><td>${o.a4}</td></tr>`).join('');
  return `<table class="itemtbl"><tr><td class="k">op#</td><td class="k">op</td>`
    + `<td class="k">a1</td><td class="k">a2</td><td class="k">a3</td><td class="k">a4</td></tr>`
    + rows + `</table>`;
}

/**
 * Build a `<details>` for a dialog key. The summary carries an inline preview
 * of the first meaningful text line (for empty-body condition nodes this is the
 * first resolvable child's line, so the header is never blank). A node whose
 * entries are engine conditions (dialogIsBranch) renders them as a branch tree
 * — one `if state N in lo..hi →` / `else →` row per entry with the child dialog
 * inline; ordinary player-choice menus keep the `choice →` recursion. Target
 * keys are masked (bit 31 flag) before resolving; recursion is capped at
 * DIALOG_MAX_DEPTH and cycle-guarded via `seen`.
 */
function dialogExpandable(key, gameData, label, depth = 0, seen = null) {
  const rec = gameData ? gameData.dialogRecord(dialogTargetKey(key)) : null;
  const cap = `${label || 'dialog'} ${dialogTargetKey(key)}`;
  if (!rec) {
    return `<details><summary>▸ ${esc(cap)}: <span class="muted">record not found</span></summary>`
      + `<div class="prov">${graphLink(dialogTargetKey(key))}</div></details>`;
  }
  return dialogExpandableRec(rec, gameData, cap, depth, seen, dialogTargetKey(key));
}

/**
 * Render the expandable for an already-resolved record. Children are followed
 * via gameData.dialogChild(rec, targetKey) so bit-31-CLEAR offset targets
 * resolve within the parent's file; the cycle guard and depth cap key off the
 * (file,offset) record identity, not the raw target value.
 */
function dialogExpandableRec(rec, gameData, cap, depth = 0, seen = null, graphKey = null) {
  const visited = seen || new Set();
  const rid = recordId(rec);
  const preview = dialogSummary(rec, gameData);
  let html = `<details><summary>▸ ${esc(cap)}: <span class="muted">"${esc(preview)}"</span></summary>`;
  html += `<div class="prov">${esc(rec.file)} @${hex(rec.offset)} `
    + `· style ${rec.style} · speaker ${rec.speakerId} · flags ${hex(rec.flags, 4)}`
    + `${graphKey ? graphLink(graphKey) : ''}</div>`;
  if (rec.textBytes.length) html += `<pre>${renderDialogBody(rec.textBytes)}</pre>`;

  const branch = dialogIsBranch(rec);
  if (visited.has(rid) || depth >= DIALOG_MAX_DEPTH) {
    if (rec.choices.length) {
      const kind = branch ? 'branch(es)' : 'choice(s)';
      html += `<div class="prov muted">${rec.choices.length} ${kind} not expanded (`
        + `${visited.has(rid) ? 'cycle' : 'depth cap'})</div>`;
    }
  } else {
    visited.add(rid);
    for (const c of rec.choices) {
      const child = c.targetKey ? gameData.dialogChild(rec, c.targetKey) : null;
      if (branch) {
        // Engine condition: `if state N in lo..hi →` / `else →`, child inline.
        html += `<div class="branch">${esc(branchEntryHead(c))}</div>`;
        if (child) {
          html += dialogExpandableRec(child, gameData, 'dialog', depth + 1, visited);
        } else {
          html += `<div class="prov muted">(no target)</div>`;
        }
      } else if (child) {
        html += dialogExpandableRec(child, gameData, 'choice →', depth + 1, visited);
      } else {
        html += `<div class="prov muted">choice cond ${hex(c.cond, 4)} (no target)</div>`;
      }
    }
    visited.delete(rid);
  }
  html += dialogOpsTable(rec.ops);
  html += `</details>`;
  return html;
}

/**
 * Compact dialog row: ONE tidy accent card per dialog reference — label + key,
 * a single truncated first-line preview, and the graph affordance. The whole
 * row is clickable and opens the node viewer (the dialog graph is where dialog
 * CONTENT lives; the panel only points at it). No inline branch expansion.
 */
function dialogRow(key, gameData, label) {
  const k = dialogTargetKey(key);
  const rec = gameData ? gameData.dialogRecord(k) : null;
  const preview = rec ? dialogSummary(rec, gameData, 40) : '';
  const mid = rec
    ? `<span class="dlgprev">“${esc(preview)}”</span>`
    : `<span class="muted">record not found</span>`;
  return `<div class="dlgrow dlg-graph" data-dlgkey="${k}" `
    + `title="open dialog ${k} in the node viewer">`
    + `<span class="dlglabel">${esc(label || 'dialog')} <span class="dlgkey">${k}</span></span>`
    + mid
    + `<span class="dlgopen">graph ⤴</span></div>`;
}

/**
 * The full single-view block for ONE hotspot, top-to-bottom: coverage /
 * click-source notes, provenance lines (T-file @offset; DEF file · present ·
 * size), the decoded DEF payload (dialogs as compact graph rows, combat roster
 * / destination / etc. inline), then the folded full DEF field table + raw hex
 * and the ZoneHotspot field table with its usual defaults collapse. Used by
 * showHotspot and by each expanded card in showTile. `sub` (optional) adds the
 * coverage annotation ("covers this object" / "elsewhere on tile").
 */
function hotspotFullBlock(hs, gameData, sub) {
  let html = '';

  // Coverage / click-source annotation.
  if (sub) {
    html += hotspotCovers(hs, sub)
      ? `<div class="prov"><span class="lock">covers this object</span></div>`
      : `<div class="prov muted">region elsewhere on tile (object at sub (${sub.sx},${sub.sy}))</div>`;
  }
  const src = gameData ? gameData.hotspotClickSource(hs) : null;
  if (src) {
    const obj = src.name ? `"${esc(src.name)}"` : `shape #${src.shapeId}`;
    html += `<div class="prov">click-fired by ${obj} at `
      + `(${src.worldX},${src.worldY}) via stored point (${src.gridX},${src.gridY}) `
      + `— the region is a dispatch key, not a walk-in area</div>`;
  }

  // Provenance lines (muted but visible — never buried).
  const defName = gameData ? gameData.defName(hs.kind) : null;
  const def = defName ? gameData.defRecordDecoded(hs.kind, hs.defRecordIndex) : null;
  html += `<div class="prov">${esc(hs.file)} @${hex(hs.offset)}</div>`;
  if (def && def.bytes) {
    html += `<div class="prov">${esc(def.file)} @${hex(def.offset)} `
      + `· present ${def.present} · ${def.size} B</div>`;
  } else if (defName) {
    html += `<div class="prov muted">${esc(defName)} absent or out of range</div>`;
  }

  // The decoded DEF payload (dialog rows, combat roster, destination, …).
  html += defPayload(hs.kind, def, gameData);

  // Full DEF field table + raw hex, folded (as in the entity Behavior block).
  const f = def && def.fields ? def.fields : [];
  if (f.length) {
    html += `<details class="defaults"><summary>all ${f.length} fields</summary>`
      + fieldsTable(f) + `</details>`;
  }
  if (def && def.bytes) {
    html += `<details class="defaults"><summary>raw DEF hex</summary><pre>${dumpHex(def.bytes)}</pre></details>`;
  }

  // ZoneHotspot record fields: nonzero gates visible, the rest folded.
  html += hotspotFieldsTable(hs.fields);
  return html;
}

/** Tile-local sub-cell size in world units (40 sub-cells per 64000-unit tile). */
const SUBCELL = 1600;
const TILE = 64000;

/** The entity's absolute world (x,y), whether placed or self-spawned. */
function entityWorld(entity) {
  if (entity.spawn) return { x: entity.spawn.x, y: entity.spawn.y };
  if (entity.placement) return { x: entity.placement.x, y: entity.placement.y };
  return { x: 0, y: 0 };
}

/** The entity's tile-local sub-cell (sx,sy), floored per axis. */
function entitySubCell(entity) {
  const w = entityWorld(entity);
  return {
    sx: Math.floor((w.x - entity.tileX * TILE) / SUBCELL),
    sy: Math.floor((w.y - entity.tileY * TILE) / SUBCELL),
  };
}

/** Whether sub-cell (sx,sy) falls inside a hotspot's decoded bbox. */
function hotspotCovers(hs, sub) {
  return sub.sx >= hs.bboxMinX && sub.sx <= hs.bboxMaxX
    && sub.sy >= hs.bboxMinY && sub.sy <= hs.bboxMaxY;
}

/** Field value by name from a decoded record, or undefined. */
function fieldValue(record, name) {
  const f = record.fields.find((x) => x.name === name);
  return f ? f.value : undefined;
}

/** Split the decoded container fields into header / item / subrecord groups. */
function stateSection(entity, gameData) {
  const st = entity.state;
  if (!st) return `<h3>State</h3><p class="muted">no data record (decorative object)</p>`;
  const r = st.record;
  const header = r.fields.filter((f) => !f.name.startsWith('item') && !subrecName(f.name));
  const provFile = st.source === 'startup' ? 'STARTUP.GAM' : 'OBJFIXED.DAT';

  let html = `<h3>State</h3>`;
  html += `<div class="prov">${provFile} @${hex(st.offset)} · residence `
    + `${r.residence} (${residenceLabel(r.residence)}) · ${r.filledSlots}/${r.capacity} items</div>`;
  html += fieldsTable(header);
  if (r.capacity) html += `<h3>Items</h3>${itemTable(r, gameData)}`;

  const subs = groupSubrecords(r.fields);
  for (const [group, fields] of subs) {
    html += `<details><summary>${esc(SUBREC_LABELS[group] || group)}</summary>${fieldsTable(fields)}</details>`;
  }

  // Decoded service summary: the interact-message service kind + flag bits and
  // the sub-4 price markup, in plain language (raw bytes stay in the subrecord
  // blocks above). WCURSOR.C:295-365 / SHOP.C:34-56.
  const svcKind = fieldValue(r, 'msg.kind');
  const svcFlags = fieldValue(r, 'msg.flags');
  if (svcKind !== undefined || svcFlags !== undefined) {
    const parts = [];
    if (svcKind !== undefined) {
      const kl = serviceKindLabel(svcKind);
      parts.push(`service kind ${svcKind}${kl ? ` (${kl})` : ''}`);
    }
    if (svcFlags !== undefined) {
      const fl = interactFlagLabels(svcFlags);
      parts.push(`flags ${hex(svcFlags, 2)}${fl.length ? ` — ${fl.join(', ')}` : ''}`);
    }
    const markup = fieldValue(r, 'svc.markupPct');
    if (markup !== undefined) parts.push(`markup +${markup}%`);
    html += `<div class="def">${parts.join(' · ')}</div>`;
  }

  // Dialog-key subrecords resolve to their text (spec Phase 2). Rendered at the
  // State top level (not inside the collapsed subrecord blocks) so the inline
  // text preview is legible without opening anything.
  const cipher = fieldValue(r, 'lock.cipherPuzzleId');
  const mid = fieldValue(r, 'msg.messageId');
  if (cipher || mid) {
    html += `<h3>Dialog</h3>`;
    if (cipher) html += dialogExpandable(cipherDialogKey(cipher), gameData, 'cipher dialog');
    if (mid) html += dialogExpandable(mid, gameData, 'message');
  }
  return html;
}

const SUBREC_GROUPS = ['lock', 'msg', 'svc', 'hotspot', 'lastTouch', 'door'];

/** Human title for a subrecord group in the State tab. */
const SUBREC_LABELS = {
  lock: 'lock / params', msg: 'interact message',
  svc: 'service params (shop/temple/inn)', hotspot: 'hotspot action',
  lastTouch: 'last touch', door: 'door variant',
};

function subrecName(name) {
  const dot = name.indexOf('.');
  if (dot < 0) return null;
  const g = name.slice(0, dot);
  return SUBREC_GROUPS.includes(g) ? g : null;
}

/** Map of subrecord group -> its fields, preserving order. */
function groupSubrecords(fields) {
  const map = new Map();
  for (const f of fields) {
    const g = subrecName(f.name);
    if (!g) continue;
    if (!map.has(g)) map.set(g, []);
    map.get(g).push(f);
  }
  return map;
}

// -------------------------------------------------------------- DEF decoding

/** Field value by name from a decoded DEF field list, or `dflt`. */
function defVal(fields, name, dflt = 0) {
  const f = fields.find((x) => x.name === name);
  return f ? f.value : dflt;
}

/** Live combatants (0..numEnemies) pulled from a decoded COMB/TRAP field list. */
function combatants(fields) {
  const n = defVal(fields, 'numEnemies', 0);
  const out = [];
  for (let i = 0; i < Math.min(n, 7); i++) {
    out.push({
      i,
      monsterIndex: defVal(fields, `comb${i}.monsterIndex`),
      movementType: defVal(fields, `comb${i}.movementType`),
      posX: defVal(fields, `comb${i}.posX`),
      posY: defVal(fields, `comb${i}.posY`),
      heading: defVal(fields, `comb${i}.heading`),
      minX: defVal(fields, `comb${i}.minX`),
      maxX: defVal(fields, `comb${i}.maxX`),
      minY: defVal(fields, `comb${i}.minY`),
      maxY: defVal(fields, `comb${i}.maxY`),
    });
  }
  return out;
}

/** Monster label: `#idx "name"` when it resolves, else raw `#idx`. */
function monsterLabel(index, gameData) {
  const name = gameData ? gameData.monsterName(index) : null;
  if (name) return `#${index} <span class="mono">"${esc(name)}"</span>`;
  return `#${index}${confDot('unknown')}`;
}

/** One combatant sub-block for the Behavior tab. */
function combatantBlock(c, gameData) {
  const patrol = c.movementType !== 0;
  let html = `<div class="combatant">`;
  html += `<div><b>enemy ${c.i}</b>: ${monsterLabel(c.monsterIndex, gameData)} `
    + `· <span title="movementType ${c.movementType}">${patrol ? 'patrol' : 'stationary'}</span> `
    + `· pos (${c.posX}, ${c.posY}) · heading ${c.heading}</div>`;
  if (patrol) {
    html += `<div class="prov">patrol X [${c.minX}..${c.maxX}] · Y [${c.minY}..${c.maxY}]</div>`;
  } else {
    html += `<div class="prov muted" title="bounds unused when stationary — `
      + `raw X [${c.minX}..${c.maxX}] Y [${c.minY}..${c.maxY}]">bounds unused (stationary)</div>`;
  }
  html += `</div>`;
  return html;
}

/**
 * Decoded DEF payload for the single hotspot view. Dialog references render as
 * compact dialogRow cards (one row, one click to the graph — content lives in
 * the node viewer, not here); combat roster / destination / scene scalars
 * render inline. The full field table and raw hex are appended by the caller
 * (hotspotFullBlock), not here. Returns a muted note when the DEF is absent.
 */
function defPayload(kind, def, gameData) {
  if (!def || !def.bytes) {
    return `<div class="prov muted">no decoded payload for this hotspot</div>`;
  }
  const f = def.fields || [];
  let html = '';

  if (kind === 3 || kind === 11) {
    // DIAL / BLOC: dialog message — one compact graph row.
    const key = defVal(f, 'dlgKey');
    if (key) html += dialogRow(key, gameData, 'dialog');
    else html += `<div class="prov muted">no dialog key</div>`;
  } else if (kind === 1 || kind === 7) {
    // COMB / TRAP: combat encounter.
    const trap = kind === 7;
    html += `<div class="def">${trap ? 'trap ' : ''}combatIndex ${defVal(f, 'combatIndex')}`
      + (defVal(f, 'flags') & 1 ? ` · <span class="ambush">ambush</span>` : '')
      + `</div>`;
    const list = combatants(f);
    html += `<div class="prov">${list.length} live combatant(s):</div>`;
    for (const c of list) html += combatantBlock(c, gameData);
    const entry = defVal(f, 'entryDlgKey');
    const scout = defVal(f, 'scoutDlgKey');
    if (entry) html += dialogRow(entry, gameData, 'entry dialog');
    if (scout) html += dialogRow(scout, gameData, 'scout dialog');
  } else if (kind === 8) {
    // ZONE transition.
    html += `<div class="def">→ zone ${defVal(f, 'zoneId')} `
      + `tile (${defVal(f, 'tileX')},${defVal(f, 'tileY')}) `
      + `sub (${defVal(f, 'subX')},${defVal(f, 'subY')}) · heading ${defVal(f, 'cameraHeading')}</div>`;
    const prompt = defVal(f, 'promptDlgKey');
    const entry = defVal(f, 'entryDlgKey');
    if (prompt) html += dialogRow(prompt, gameData, 'prompt dialog');
    if (entry) html += dialogRow(entry, gameData, 'entry dialog');
  } else if (kind === 0 || kind === 6) {
    // BKGR / TOWN: scene + popup message.
    html += `<div class="def">scene ${defVal(f, 'sceneId')} · `
      + `walk-to (${defVal(f, 'walkSubX')},${defVal(f, 'walkSubY')}) `
      + `· animateCamera ${defVal(f, 'animateCamera')}</div>`;
    const key = defVal(f, 'dlgKey');
    if (key) html += dialogRow(key, gameData, 'popup message');
  } else if (kind === 5) {
    // SOUN.
    html += `<div class="def">sfx ${defVal(f, 'sfxId')} · chance ${defVal(f, 'chancePct')}%</div>`;
  } else if (kind === 9 || kind === 10) {
    // DISA / ENAB.
    const verb = kind === 10 ? 'enable' : 'disable';
    html += `<div class="def">${verb} event ${defVal(f, 'eventKey')} · chance ${defVal(f, 'chancePct')}%</div>`;
  } else {
    html += `<div class="prov muted">kind ${kind} · ${def.size} B (no schema)</div>`;
  }
  return html;
}

/**
 * Render one DEF record's named fields for the Behavior tab. Dialog keys chain
 * to the dialog expandable; the raw hex dump lives behind a per-record
 * expandable at the bottom. Returns '' when the DEF has no schema (COMM/HEAL).
 */
function defNamedBlock(kind, def, gameData) {
  if (!def || !def.bytes) return '';
  const f = def.fields || [];
  let html = '';

  if (kind === 1 || kind === 7) {
    // COMB / TRAP: combat encounter.
    const trap = kind === 7;
    html += `<div class="def">combatIndex ${defVal(f, 'combatIndex')}`
      + (defVal(f, 'flags') & 1 ? ` · <span class="ambush">ambush</span>` : '')
      + `</div>`;
    const entry = defVal(f, 'entryDlgKey');
    const scout = defVal(f, 'scoutDlgKey');
    if (entry) html += dialogExpandable(entry, gameData, 'entry dialog');
    if (scout) html += dialogExpandable(scout, gameData, 'scout dialog');
    const list = combatants(f);
    html += `<div class="prov">${list.length} live combatant(s)${trap ? ' (trap)' : ''}:</div>`;
    for (const c of list) html += combatantBlock(c, gameData);
  } else if (kind === 8) {
    // ZONE transition.
    html += `<div class="def">→ zone ${defVal(f, 'zoneId')} `
      + `tile (${defVal(f, 'tileX')},${defVal(f, 'tileY')}) `
      + `sub (${defVal(f, 'subX')},${defVal(f, 'subY')}) · heading ${defVal(f, 'cameraHeading')}</div>`;
    const prompt = defVal(f, 'promptDlgKey');
    const entry = defVal(f, 'entryDlgKey');
    if (prompt) html += dialogExpandable(prompt, gameData, 'prompt dialog');
    if (entry) html += dialogExpandable(entry, gameData, 'entry dialog');
  } else if (kind === 3 || kind === 11) {
    // DIAL / BLOC: dialog message.
    const key = defVal(f, 'dlgKey');
    if (key) html += dialogExpandable(key, gameData, 'dialog');
    else html += `<div class="prov muted">no dialog key</div>`;
  } else if (kind === 0 || kind === 6) {
    // BKGR / TOWN: scene + popup message.
    html += `<div class="def">scene ${defVal(f, 'sceneId')} · `
      + `walk-to (${defVal(f, 'walkSubX')},${defVal(f, 'walkSubY')}) `
      + `· animateCamera ${defVal(f, 'animateCamera')}</div>`;
    const key = defVal(f, 'dlgKey');
    if (key) html += dialogExpandable(key, gameData, 'popup message');
  } else if (kind === 5) {
    // SOUN.
    html += `<div class="def">sfx ${defVal(f, 'sfxId')} · chance ${defVal(f, 'chancePct')}%</div>`;
  } else if (kind === 9 || kind === 10) {
    // DISA / ENAB.
    const verb = kind === 10 ? 'enable' : 'disable';
    html += `<div class="def">${verb} event ${defVal(f, 'eventKey')} · chance ${defVal(f, 'chancePct')}%</div>`;
  }

  // The curated lines above are the payload; the full decoded field table is
  // available but folded so the block stays compact (long COMB records dump
  // ~90 landing/combatant rows otherwise).
  if (f.length) {
    html += `<details class="defaults"><summary>all ${f.length} fields</summary>`
      + fieldsTable(f) + `</details>`;
  }
  return html;
}

/** Human dispatch-class name per ZoneHotspot.kind (index == kind). */
const HOTSPOT_KIND_NAMES = ['dialog popup', 'combat', '?', 'dialog', '?', 'sound',
  'town', 'trap', 'zone transition', 'disable', 'enable', 'message'];

function hotspotKindName(kind) {
  return HOTSPOT_KIND_NAMES[kind] || `kind ${kind}`;
}

/**
 * An entity is TERRAIN when its shape has a nonzero paint priority (bPriority):
 * the tile-canvas layers — ground (8), road overlays (7), river overlays (6).
 * Priority-0 shapes are props (chests, doors, decorations, spawns). Only terrain
 * keeps the tile-hotspot list in its Behavior tab; props get a single muted
 * Overview line that opens the tile view instead.
 */
function isTerrain(entity) {
  return !!(entity.model && entity.model.bPriority > 0);
}

/**
 * Short kind name for the tile-trigger summary line, with an `(ambush)` marker
 * for combat/trap hotspots whose decoded DEF flags say so.
 */
function hotspotSummaryName(hs, gameData) {
  const name = hotspotKindName(hs.kind);
  if ((hs.kind === 1 || hs.kind === 7) && gameData) {
    const def = gameData.defRecordDecoded(hs.kind, hs.defRecordIndex);
    if (def && def.bytes && (defVal(def.fields || [], 'flags') & 1)) {
      return `${name} (ambush)`;
    }
  }
  return name;
}

/**
 * The single muted Overview line for a PROP whose tile carries hotspots:
 * `tile (x,y): N triggers — <kind>, <kind>…`. Clicking it opens the tile view
 * (wired via data-open-tile in wire()). Returns '' when the tile has none.
 */
function tileTriggerLine(entity, gameData) {
  const list = entity.hotspots || [];
  if (!list.length) return '';
  const names = list.map((hs) => esc(hotspotSummaryName(hs, gameData)));
  const n = list.length;
  return `<div class="ovline muted" data-open-tile="1">`
    + `tile (${entity.tileX},${entity.tileY}): ${n} trigger${n > 1 ? 's' : ''} — `
    + `${names.join(', ')}</div>`;
}

/**
 * One tile-hotspot block for the Behavior tab. The header is ONE compact line:
 * `<kindName> · region (minX,minY)-(maxX,maxY) · def #N · <coverage>`; the kind
 * number and the raw bbox field rows fold into the collapsed defaults inside
 * the schema field table. The decoded DEF (named fields, dialog chains) renders
 * inline; the raw DEF hex dump hides behind a nested expandable. When `sub`
 * (the entity's tile-local sub-cell) is given, the coverage annotation says
 * whether the trigger region covers the object's position.
 */
function hotspotBlock(hs, gameData, sub) {
  const defName = gameData ? gameData.defName(hs.kind) : null;
  let cover = '';
  if (sub) {
    cover = hotspotCovers(hs, sub)
      ? ` · <span class="lock">covers this object</span>`
      : ` · <span class="muted">elsewhere on tile (obj at sub (${sub.sx},${sub.sy}))</span>`;
  }
  const head = `<b>${esc(hotspotKindName(hs.kind))}</b> · region `
    + `(${hs.bboxMinX},${hs.bboxMinY})–(${hs.bboxMaxX},${hs.bboxMaxY}) `
    + `· def #${hs.defRecordIndex}${cover}`;
  let html = `<details open><summary title="kind ${hs.kind} · ${attr(hs.file)} @${hex(hs.offset)}">`
    + `${head}</summary>`;
  html += `<div class="prov">${esc(hs.file)} @${hex(hs.offset)}</div>`;

  // Click-fired hotspot: the region is a dispatch key, not a walk-in area.
  // Clicking the linked fixed object dispatches at its stored sub-cell point
  // (WCURSOR.C -> hotspotevt_dispatch_at_point), which this bbox contains.
  const src = gameData ? gameData.hotspotClickSource(hs) : null;
  if (src) {
    const obj = src.name ? `"${esc(src.name)}"` : `shape #${src.shapeId}`;
    html += `<div class="prov">click-fired by ${obj} at `
      + `(${src.worldX},${src.worldY}) via stored point (${src.gridX},${src.gridY}) `
      + `— the region is a dispatch key, not a walk-in area</div>`;
  }

  if (gameData && defName) {
    const def = gameData.defRecordDecoded(hs.kind, hs.defRecordIndex);
    if (def && def.bytes) {
      html += `<div class="prov">${esc(def.file)} @${hex(def.offset)} `
        + `· present ${def.present} · ${def.size} B</div>`;
      html += defNamedBlock(hs.kind, def, gameData);
      html += `<details><summary>raw DEF hex</summary><pre>${dumpHex(def.bytes)}</pre></details>`;
    } else {
      html += `<div class="prov muted">${esc(defName)} absent or out of range</div>`;
    }
  }
  // The ZoneHotspot dispatch fields (kind, bbox, gates) are already summarized
  // in the header/DEF; keep them available but folded. Non-zero gates surface;
  // zero/default gates and the header-echoed fields stay collapsed.
  html += hotspotFieldsTable(hs.fields);
  html += `</details>`;
  return html;
}

/** Fields whose value the compact hotspot header already shows. */
const HOTSPOT_HEADER_FIELDS = new Set(
  ['kind', 'bboxMinX', 'bboxMinY', 'bboxMaxX', 'bboxMaxY', 'defRecordIndex']);

/**
 * Field table for a tile-hotspot record. Header-echoed fields (kind, bbox, def
 * index) and any zero-valued gate always fold into the `▸ N more fields
 * (defaults)` line; only non-zero gates render visibly (they change behavior).
 */
function hotspotFieldsTable(fields) {
  const visible = [];
  const defaults = [];
  for (const f of fields) {
    const noise = HOTSPOT_HEADER_FIELDS.has(f.name) || (!f.hex && f.value === 0);
    (noise ? defaults : visible).push(f);
  }
  let html = `<table>${visible.map(fieldRow).join('')}</table>`;
  if (defaults.length) {
    html += `<details class="defaults"><summary>${defaults.length} more fields (defaults)</summary>`
      + `<table>${defaults.map(fieldRow).join('')}</table></details>`;
  }
  return html;
}

/** Pull the hotspot-action subrecord's decoded scalars, or null. */
function hotspotAction(record) {
  const has = record.fields.find((f) => f.name === 'hotspot.hasHotspot');
  if (!has) return null;
  const get = (n) => { const f = record.fields.find((x) => x.name === n); return f ? f.value : 0; };
  return {
    gameStateEventId: get('hotspot.gameStateEventId'),
    warpKind: get('hotspot.warpKind'),
    warpDest: get('hotspot.warpDest'),
    hasHotspot: has.value,
    hotspotX: get('hotspot.hotspotX'),
    hotspotY: get('hotspot.hotspotY'),
  };
}

function behaviorSection(entity, gameData) {
  let html = `<h3>Behavior</h3>`;
  let any = false;

  if (entity.state) {
    const act = hotspotAction(entity.state.record);
    if (act) {
      any = true;
      html += `<div class="prov">hotspot-action: `
        + `eventId ${act.gameStateEventId}, warp ${act.warpKind}/${act.warpDest}, `
        + `hasHotspot ${act.hasHotspot} @(${act.hotspotX},${act.hotspotY})</div>`;
    }
  }

  // Only TERRAIN entities (the tile-canvas shapes) carry the tile-hotspot list
  // in Behavior — the hotspots ARE the tile's region triggers, and terrain is
  // the tile. Props get a single muted Overview line to the tile view instead.
  const list = isTerrain(entity) ? (entity.hotspots || []) : [];
  if (list.length) {
    any = true;
    const sub = entitySubCell(entity);
    // Hotspots are TILE-scoped region triggers, not object-attached: make the
    // scoping explicit and put the ones that actually cover this object first.
    const sorted = list.slice().sort(
      (a, b) => (hotspotCovers(b, sub) ? 1 : 0) - (hotspotCovers(a, sub) ? 1 : 0));
    html += `<div class="prov">tile (${entity.tileX},${entity.tileY}) hotspots — `
      + `region triggers on this tile, not attached to this object `
      + `(chapter ${entity.chapter}):</div>`;
    for (const hs of sorted) html += hotspotBlock(hs, gameData, sub);
  }

  if (!any) html += `<p class="muted">no behavior data for this chapter</p>`;
  return html;
}

function dumpHex(bytes) {
  const lines = [];
  for (let i = 0; i < bytes.length; i += 16) {
    let s = i.toString(16).padStart(4, '0') + '  ';
    for (let j = 0; j < 16 && i + j < bytes.length; j++) {
      s += bytes[i + j].toString(16).padStart(2, '0') + ' ';
    }
    lines.push(s.trimEnd());
  }
  return esc(lines.join('\n'));
}

// --------------------------------------------------------------- Overview tab

/** One-line human summary of a decoded DEF record for the Overview tab. */
function hotspotOneLiner(hs, gameData) {
  const defName = gameData ? gameData.defName(hs.kind) : null;
  const def = defName ? gameData.defRecordDecoded(hs.kind, hs.defRecordIndex) : null;
  const f = def && def.fields ? def.fields : [];
  if ((hs.kind === 1 || hs.kind === 7) && def && def.bytes) {
    const n = defVal(f, 'numEnemies', 0);
    const ambush = defVal(f, 'flags') & 1 ? ', ambush' : '';
    const trap = hs.kind === 7 ? 'trap ' : '';
    return `${trap}combat #${defVal(f, 'combatIndex')} — ${n} enem${n === 1 ? 'y' : 'ies'}${ambush}`;
  }
  if (hs.kind === 8 && def && def.bytes) {
    return `→ zone ${defVal(f, 'zoneId')} tile (${defVal(f, 'tileX')},${defVal(f, 'tileY')})`;
  }
  if ((hs.kind === 3 || hs.kind === 11) && def && def.bytes) {
    const line = dialogSummaryForKey(defVal(f, 'dlgKey'), gameData, 24);
    // Choice-only dialog nodes have no body text: nothing to summarize, so the
    // Overview suppresses the row ('' — the caller skips empty one-liners).
    return line ? `dialog "${esc(line)}"` : '';
  }
  if ((hs.kind === 0 || hs.kind === 6) && def && def.bytes) {
    return `scene ${defVal(f, 'sceneId')}`;
  }
  if (hs.kind === 5 && def && def.bytes) return `sound sfx ${defVal(f, 'sfxId')}`;
  if ((hs.kind === 9 || hs.kind === 10) && def && def.bytes) {
    return `${hs.kind === 10 ? 'enable' : 'disable'} event ${defVal(f, 'eventKey')}`;
  }
  return `hotspot kind ${hs.kind} · def #${hs.defRecordIndex}`;
}

/** A clickable Overview line that deep-links to a tab. */
function ovLine(tab, html) {
  return `<div class="ovline" data-goto="${tab}">${html}</div>`;
}

/**
 * Overview tab: curated human summary, no hex / field tables. Every line
 * deep-links to the owning tab. Assembled from the same joined data as the
 * detail tabs but rendered as prose + chips.
 */
function overviewSection(entity, gameData) {
  let html = `<h3>Overview</h3>`;

  // What it is.
  const cls = entity.spawn ? 'spawned object'
    : (entity.model ? `shape (bKind ${entity.model.bKind})` : 'object');
  const shapeName = entity.model ? entity.model.name : `shape ${entity.placement ? entity.placement.id : ''}`;
  html += ovLine('shape', `<b>${esc(shapeName)}</b> — ${cls}`);

  // Lock one-liner incl. answer.
  const st = entity.state;
  if (st) {
    const r = st.record;
    const cipher = fieldValue(r, 'lock.cipherPuzzleId');
    if (cipher) {
      const rec = gameData ? gameData.dialogRecord(cipherDialogKey(cipher)) : null;
      let answer = '';
      if (rec) {
        const first = dialogFirstLine(rec, 20).replace(/[␀-␟⇥].*$/, '').trim();
        if (first) answer = ` — answer "${esc(first)}"`;
      }
      html += ovLine('state', `<span class="lock">🔒 wordlock${answer} (cipher ${cipher})</span>`);
    } else if (fieldValue(r, 'lock.lockedFlag')) {
      html += ovLine('state', `<span class="lock">🔒 locked</span>`);
    }

    // Item names. When the record also carries the sub-4 service-params block
    // (mask bit 0x04), it is a shop/temple/inn stock list: qualify the line and
    // surface the price markup.
    if (r.capacity && r.filledSlots) {
      const names = [];
      const view = r.view;
      for (let i = 0; i < r.capacity && names.length < 8; i++) {
        const o = r.offset + 16 + i * 4;
        const id = view.getUint8(o);
        if (i < r.filledSlots && id) {
          const cond = view.getUint8(o + 1);
          names.push(esc(itemLabel(id, cond, gameData)));
        }
      }
      if (names.length) {
        // A functioning shop is one whose interact-message flags open the trade
        // screen (bit 0x02, WCURSOR.C:295-365). A record with the sub-4 service
        // block but no trade bit (e.g. the zone-1 blacksmith, flags 0x01 only)
        // is NOT a shop — it just plays a closed/flavor message.
        const msgFlags = fieldValue(r, 'msg.flags') || 0;
        const isShop = (msgFlags & 0x02) !== 0;
        if (isShop) {
          const markup = fieldValue(r, 'svc.markupPct');
          const mk = (markup ? ` <span class="muted">(+${markup}% markup)</span>` : '');
          html += ovLine('state',
            `<b>shop:</b> ${r.filledSlots} item${r.filledSlots > 1 ? 's' : ''} — ${names.join(', ')}${mk}`);
        } else {
          html += ovLine('state', `<b>items:</b> ${names.join(', ')}`);
        }
      }
    }

    // Interact message first line. For empty-body condition nodes (e.g. the
    // blacksmith's "shop closed" / "a bell rang" branch) dialogSummary resolves
    // into the first child's flavor text instead of showing "". Suppressed only
    // when nothing resolves.
    const mid = fieldValue(r, 'msg.messageId');
    if (mid) {
      const line = dialogSummaryForKey(mid, gameData, 30);
      if (line) html += ovLine('state', `<b>message:</b> "${esc(line)}"`);
    }
  }

  // Tile hotspots. TERRAIN owns them: one deep-linking one-liner each (they are
  // listed in its Behavior tab). PROPS carry no tile behavior — just one muted
  // discoverability line that opens the tile view. hotspotOneLiner may embed
  // markup (mono spans); its dynamic text is escaped inside the helper.
  const list = entity.hotspots || [];
  if (isTerrain(entity)) {
    const sub = list.length ? entitySubCell(entity) : null;
    for (const hs of list) {
      const line = hotspotOneLiner(hs, gameData);
      if (!line) continue;
      const outside = !hotspotCovers(hs, sub) ? ` <span class="muted">· not at this object</span>` : '';
      html += ovLine('behavior', `<span class="muted">tile:</span> ${line}${outside}`);
    }
  } else {
    html += tileTriggerLine(entity, gameData);
  }

  // Provenance chips.
  const chips = [];
  if (entity.placement) chips.push(chip('WLD', 'wld', 'placement'));
  if (st) chips.push(chip(st.source === 'startup' ? 'GAM' : 'OBJFIXED',
    st.source === 'startup' ? 'gam' : 'obj', 'state'));
  // The T-DAT chip deep-links into Behavior; only terrain has a Behavior tab
  // that lists hotspots. Props reach the tile triggers via the muted line above.
  if (list.length && isTerrain(entity)) chips.push(chip('T-DAT', 'tdat', 'behavior'));
  if (chips.length) html += `<div class="chips">${chips.join('')}</div>`;

  return html;
}

/** A provenance chip that deep-links to a tab. */
function chip(text, cls, tab) {
  return `<span class="chip ${cls}" data-goto="${tab}">${esc(text)}</span>`;
}

// ------------------------------------------------------------------ tab shell

/**
 * Render the tabbed shell: sticky header, tab bar (empty tabs hidden), and one
 * content div per available tab. `tabs` is [{id, label, html}]; the active tab
 * is `activeTab` if present, else the first.
 */
function renderTabs(header, tabs) {
  const avail = tabs.filter((t) => t.html);
  if (!avail.some((t) => t.id === activeTab)) {
    if (pendingTab && avail.some((t) => t.id === pendingTab)) activeTab = pendingTab;
    else activeTab = avail.length ? avail[0].id : 'overview';
  } else if (pendingTab && avail.some((t) => t.id === pendingTab)) {
    activeTab = pendingTab;
  }
  pendingTab = null;

  const bar = avail.map((t) =>
    `<button class="itab${t.id === activeTab ? ' sel' : ''}" data-tab="${t.id}">${esc(t.label)}</button>`
  ).join('');
  const bodies = avail.map((t) =>
    `<div class="tabbody${t.id === activeTab ? '' : ' hidden'}" data-tabbody="${t.id}">${t.html}</div>`
  ).join('');

  return `<div class="insphead">${header}</div>`
    + `<div class="itabs">${bar}</div>`
    + `<div class="itabwrap">${bodies}</div>`;
}

/**
 * Render a single (untabbed) view: sticky header + one body wrapper. Used for
 * the hotspot / tile views, which have one story and don't warrant tabs. Sets
 * activeTab to a synthetic id so the READY line (currentTab) stays coherent.
 */
function renderSingle(header, html) {
  activeTab = 'hotspot';
  pendingTab = null;
  return `<div class="insphead">${header}</div>`
    + `<div class="itabwrap">${html}</div>`;
}

/** Sticky header markup: title with badges, subtitle, close button. */
function headerHtml(title, badges, subtitle) {
  const b = badges.map((x) => `<span class="badge ${x.cls}">${esc(x.text)}</span>`).join(' ');
  return `<button class="close" title="close">×</button>`
    + `<h2>${esc(title)} ${b}</h2>`
    + (subtitle ? `<div class="subtitle">${esc(subtitle)}</div>` : '');
}

// ------------------------------------------------------------------ public

/**
 * Render a full entity join as a tabbed panel.
 * @param {Object} entity  {index, placement, model, tblName, tileFile,
 *   tileX, tileY, state, hotspots, chapter, spawn?}
 * @param {import('./gamedata.js').GameData|null} gameData
 */
export function showEntity(entity, gameData) {
  const p = el();
  // Remember the tile context for the prop Overview's "open tile view" line
  // (props only; terrain lists the hotspots inline). Cleared for non-prop views.
  tileOpenCtx = (!isTerrain(entity) && (entity.hotspots || []).length)
    ? { zone: entity.zone, tileX: entity.tileX, tileY: entity.tileY,
        chapter: entity.chapter, gameData }
    : null;
  const spawned = !!entity.spawn;
  const shapeId = spawned ? entity.spawn.shapeId
    : (entity.model ? entity.model.index : (entity.placement ? entity.placement.id : 0));
  const name = entity.model ? entity.model.name : `shape ${shapeId}`;

  const badges = [];
  if (spawned) badges.push({ text: 'SPAWN', cls: 'spawn' });

  const wx = spawned ? entity.spawn.x : (entity.placement ? entity.placement.x : 0);
  const wy = spawned ? entity.spawn.y : (entity.placement ? entity.placement.y : 0);
  const subtitle = `zone ${entity.zone || ''} · tile (${entity.tileX},${entity.tileY}) · world (${wx},${wy})`;
  const header = headerHtml(`${name} #${shapeId}${spawned ? ' (spawned)' : ''}`, badges, subtitle);

  const placementTab = spawned ? spawnSection(entity) : (entity.placement ? placementSection(entity) : '');
  const tabs = [
    { id: 'overview', label: 'Overview', html: overviewSection(entity, gameData) },
    { id: 'placement', label: spawned ? 'Spawn' : 'Placement', html: placementTab },
    { id: 'shape', label: 'Shape', html: entity.model ? shapeSection(entity) : '' },
    { id: 'state', label: 'State', html: entity.state ? stateSection(entity, gameData) : '' },
    { id: 'behavior', label: 'Behavior', html: behaviorHtml(entity, gameData) },
  ];

  p.innerHTML = renderTabs(header, tabs);
  p.classList.remove('hidden');
  wire(p);
}

/** Behavior tab HTML, or '' when there is no behavior data (so the tab hides). */
function behaviorHtml(entity, gameData) {
  const hasAction = entity.state && hotspotAction(entity.state.record);
  // Tile hotspots only populate a terrain entity's Behavior; for props they
  // never appear here, so they cannot keep the tab alive.
  const hasHotspots = isTerrain(entity) && (entity.hotspots || []).length > 0;
  if (!hasAction && !hasHotspots) return '';
  return behaviorSection(entity, gameData);
}

/**
 * Render a standalone hotspot (from a marker/rect click or a tile card): ONE
 * flat view, no tabs. Provenance, decoded payload (dialogs as compact one-click
 * graph rows), and the field tables read top-to-bottom (hotspotFullBlock).
 */
export function showHotspot(hotspot, gameData) {
  const p = el();
  tileOpenCtx = null;
  const badges = [{ text: `kind ${hotspot.kind}`, cls: 'kind' }];
  if (gameData && gameData.hotspotClickSource(hotspot)) {
    badges.push({ text: 'click-fired', cls: 'kind' });
  }
  const region = `region (${hotspot.bboxMinX},${hotspot.bboxMinY})–`
    + `(${hotspot.bboxMaxX},${hotspot.bboxMaxY}) · def #${hotspot.defRecordIndex}`;
  const sub = hotspot.tileX !== undefined
    ? `tile (${hotspot.tileX},${hotspot.tileY}) · ${region}` : region;
  const header = headerHtml(hotspotKindName(hotspot.kind), badges, sub);

  const body = hotspotFullBlock(hotspot, gameData);
  p.innerHTML = renderSingle(header, body);
  p.classList.remove('hidden');
  wire(p);
}

/**
 * Tile view: `tile (x,y)` header, then one compact CARD per hotspot. Each card's
 * summary is the payload one-liner plus (for dialog kinds) a direct graph link;
 * clicking a card expands it to the same full flat block as showHotspot. No
 * Overview/Behavior tabs — the tile has one story per trigger.
 */
export function showTile(zone, tileX, tileY, chapter, gameData) {
  const p = el();
  tileOpenCtx = null;
  const list = gameData ? gameData.hotspotsFor(zone, tileX, tileY, chapter) : [];
  const badges = [{ text: `${list.length} trigger${list.length === 1 ? '' : 's'}`, cls: 'kind' }];
  const header = headerHtml(`tile (${tileX},${tileY})`, badges,
    `zone ${zone || ''} · chapter ${chapter}`);

  let body = '';
  if (list.length) {
    for (const hs of list) body += hotspotCard(hs, gameData);
  } else {
    body += `<p class="muted">no triggers on this tile for this chapter</p>`;
  }
  p.innerHTML = renderSingle(header, body);
  p.classList.remove('hidden');
  wire(p);
}

/**
 * One compact tile-view card: a `<details>` whose summary is the payload
 * one-liner plus, for a dialog kind, a direct ⤴ graph link (so the node viewer
 * is reachable straight from the tile list). Expanding shows the full flat
 * block (provenance → payload → field tables).
 */
function hotspotCard(hs, gameData) {
  const line = hotspotOneLiner(hs, gameData)
    || `hotspot kind ${hs.kind} · def #${hs.defRecordIndex}`;
  const glink = cardGraphLink(hs, gameData);
  const summary = `<summary><b>${esc(hotspotKindName(hs.kind))}</b> — ${line}${glink}</summary>`;
  return `<details class="hscard">${summary}${hotspotFullBlock(hs, gameData)}</details>`;
}

/** The ⤴ graph link for a card summary, for dialog-bearing kinds only, else ''. */
function cardGraphLink(hs, gameData) {
  if (!gameData) return '';
  const def = gameData.defRecordDecoded(hs.kind, hs.defRecordIndex);
  if (!def || !def.bytes) return '';
  const f = def.fields || [];
  let key = 0;
  if (hs.kind === 3 || hs.kind === 11 || hs.kind === 0 || hs.kind === 6) key = defVal(f, 'dlgKey');
  else if (hs.kind === 8) key = defVal(f, 'promptDlgKey') || defVal(f, 'entryDlgKey');
  else if (hs.kind === 1 || hs.kind === 7) key = defVal(f, 'entryDlgKey');
  return key ? graphLink(key) : '';
}

function switchTab(p, id) {
  activeTab = id;
  for (const btn of p.querySelectorAll('.itab')) {
    btn.classList.toggle('sel', btn.dataset.tab === id);
  }
  for (const body of p.querySelectorAll('.tabbody')) {
    body.classList.toggle('hidden', body.dataset.tabbody !== id);
  }
  if (onTabChange) onTabChange(id);
}

function wire(p) {
  const close = p.querySelector('.close');
  if (close) close.addEventListener('click', hideInspector);
  const link = p.querySelector('[data-open-model]');
  if (link && onOpenModel) {
    link.addEventListener('click', () => onOpenModel(Number(link.dataset.openModel)));
  }
  for (const btn of p.querySelectorAll('.itab')) {
    btn.addEventListener('click', () => switchTab(p, btn.dataset.tab));
  }
  // Prop Overview -> tile view: the muted tile-trigger line opens showTile with
  // the captured tile context (no main.js involvement).
  const tileLink = p.querySelector('[data-open-tile]');
  if (tileLink) {
    tileLink.addEventListener('click', () => {
      const c = tileOpenCtx;
      if (c) showTile(c.zone, c.tileX, c.tileY, c.chapter, c.gameData);
    });
  }
  // "⤴ graph" links: open the DIALOG tab on the dialog key (in-page).
  for (const g of p.querySelectorAll('.dlg-graph')) {
    g.addEventListener('click', (ev) => {
      ev.stopPropagation();
      if (onDialogGraph) onDialogGraph(Number(g.dataset.dlgkey));
    });
  }
  // Overview deep-links: clicking a line/chip switches to the owning tab.
  for (const g of p.querySelectorAll('[data-goto]')) {
    g.addEventListener('click', () => {
      const tab = g.dataset.goto;
      if (p.querySelector(`.itab[data-tab="${tab}"]`)) switchTab(p, tab);
    });
  }
  // Announce the initial active tab (for the READY line).
  if (onTabChange) onTabChange(activeTab);
}
