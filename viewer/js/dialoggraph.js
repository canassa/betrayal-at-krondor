// Dialog graph canvas: a plain-SVG, left-to-right layered renderer for one DDX
// component (or a hub neighborhood / forward closure of the giant conversation
// web). Renders a RAW, FLAT DAG — every node is an ordinary card, every edge an
// ordinary labeled arrow. No compound nesting: no switch/variant lanes, no
// pass-through splicing, no op-only pills, no dead-end stop-dots. This kills the
// entire class of nested-cross-hierarchy layout bugs.
//
// The data layer (dialog.js / DialogDb) supplies render-ready {nodes, edges}
// via db.graphFor(spec); this module lays them out and draws them. Layout is a
// small Sugiyama-style pipeline: longest-path ranking from the view root (BFS
// fallback on cycles), then 2 barycenter sweeps for within-rank order, with
// serpentine wrapping for long narrow chains. No libs (or ELK on the same flat
// graph when the layout backend is 'elk' — no compounds either way).
//
// Nodes are cards (~220x64) with a class-colored left accent + header; edges are
// cubic beziers with a label pill at the midpoint. Back-edges (target rank <=
// source rank) are drawn as a small '↩' badge on the source card instead of a
// long arrow; out-of-view targets render as small dashed ghost link stubs.
//
// NOTHING is capped, collapsed, or hidden. A forward-closure view pulls the WHOLE
// reachable subgraph (dialog.js), so opening a conversation that chains into the
// giant web renders every one of its ~5362 nodes as a card. Layout of the giant
// component is a multi-second synchronous pass (classic) or an off-thread worker
// pass (elk); a "laying out N nodes…" status covers it. See the report for
// measured numbers.

import { loadElk, buildElkGraph, flattenElk, presetFor, PRESETS, DEFAULT_PRESET } from './elklayout.js';

const SVG_NS = 'http://www.w3.org/2000/svg';

// Card geometry.
const CARD_W = 220;
const CARD_H = 64;
// Compact chip size for "audio-only" nodes (blank text, only sfx/music ops).
const AUDIO_W = 92;
const AUDIO_H = 26;
const RANK_GAP = 130;   // horizontal gap between rank columns
const ROW_GAP = 26;     // vertical gap between cards in a rank
const MIN_ROW_GAP = 20; // enforced minimum vertical gap between cards in a rank
// Max on-screen card width (px): fit() never zooms past this, so a small view
// (e.g. a 3-card story) stays card-sized instead of ballooning to billboard.
const MAX_CARD_SCREEN_W = 320;
// Serpentine wrap: linear/narrow layouts longer than this many ranks fold into
// rows, so a long chain reads as stacked rows instead of one endless line.
const SERP_MAX_RANKS = 6;   // wrap when a narrow layout exceeds this rank count
const SERP_ROW_RANKS = 5;   // ranks per serpentine row
const SERP_ROW_GAP = 70;    // vertical gap between serpentine rows

// Snap-to-grid: world-unit lattice pitch for manual node editing. When snap is
// on, a dragged node's CENTER lands on a GRID x GRID intersection.
const GRID = 20;


/** Class -> accent + header colors (matches the inspector dark palette). */
const CLASS_COLORS = {
  text: { accent: '#7b8494', head: '#2f3542' },       // slate
  branch: { accent: '#d9a441', head: '#3a3320' },     // amber
  switch: { accent: '#f2b134', head: '#42360f' },     // bright amber (dispatcher)
  menu: { accent: '#6fb3ff', head: '#123a55' },       // blue
  'keyword-hub': { accent: '#c79bff', head: '#2c1c40' }, // violet
  cipher: { accent: '#5fcf7f', head: '#183a24' },     // green
  chain: { accent: '#5fd6d6', head: '#173a3a' },      // teal
};

/** Edge-kind -> label pill color. */
const EDGE_COLORS = {
  cond: '#8b93a0',
  choice: '#6fb3ff',
  keyword: '#c79bff',
  chain: '#5fd6d6',
};

function classColor(cls) { return CLASS_COLORS[cls] || CLASS_COLORS.text; }

/**
 * Per-arm hue tint so parallel storylines are traceable in the fully-open tree.
 * A deterministic spread around the color wheel keyed by arm index (subtle:
 * used only for the edge stroke + label-pill border, never the nodes).
 */
function armHue(armIndex) {
  const h = (armIndex * 47 + 20) % 360;
  return `hsl(${h}, 62%, 62%)`;
}

/** Collapse-key for a switch arm: "<stateNodeId>\x00<armIndex>". */
function armKey(stateNodeId, armIndex) { return stateNodeId + '\x00' + armIndex; }

/** Create an SVG element with attributes. */
function svg(tag, attrs, parent) {
  const e = document.createElementNS(SVG_NS, tag);
  if (attrs) for (const k in attrs) e.setAttribute(k, attrs[k]);
  if (parent) parent.appendChild(e);
  return e;
}

/**
 * The graph canvas. Owns one <svg> inside a host element; renders a {nodes,
 * edges} payload with layered layout, pan/zoom, and selection. Callbacks:
 *   onSelect(nodeId)      — a card was clicked.
 *   onNavigate(targetId)  — an out-of-view / back-badge target should be opened.
 *   onStatus(text|null)   — a transient status (e.g. "laying out N nodes…"); null
 *                           clears it.
 *   onManualChange()      — the manual-edit state changed (entered/exited manual
 *                           mode, or a node moved) — repaint the toolbar + READY.
 */
export class DialogGraph {
  constructor(host, callbacks = {}) {
    this.host = host;
    this.onSelect = callbacks.onSelect || (() => {});
    this.onNavigate = callbacks.onNavigate || (() => {});
    this.onStatus = callbacks.onStatus || (() => {});
    this.db = null;
    this.graph = null;      // {nodes, edges}
    this.rootId = null;
    this.selectedId = null;
    this.layout = null;     // {pos: Map(id -> {x,y,rank}), width, height}
    this.model = null;      // render model (nodes/edges) after transform
    // View transform (world -> screen): screen = world*scale + [tx,ty].
    this.scale = 1;
    this.tx = 0;
    this.ty = 0;
    // Right-edge inset (px) reserved for the floating inspector overlay so fit()
    // frames content into the visible canvas, not behind the panel.
    this.rightInset = 0;
    // Layout preset (see elklayout.js PRESETS): a NAMED config that resolves to
    // either the classic hand-rolled kernel or an ELK algorithm + options. ELK is
    // async; _layoutGen guards against stale async results clobbering a newer
    // layout. lastLayoutMs records the most recent layout compute time.
    this.layoutPreset = DEFAULT_PRESET;
    // Live TUNE-panel override channel: a partial ELK layoutOptions map merged
    // ON TOP of the active preset's options in _computeLayoutElk (overrides
    // win). Empty {} = pure preset. Global-like the preset; set via
    // setLayoutOverrides. ELK-only (classic ignores it).
    this.layoutOverrides = {};
    this._elk = null;                   // shared ELK instance (lazy)
    this._layoutGen = 0;
    this.lastLayoutMs = 0;
    // Per-arm collapse (manual): a Set of "stateNodeId\x00armIndex" keys whose
    // subtrees are collapsed to a stub card. A FLAT-GRAPH FILTER — collapsed
    // arms are removed from the model before layout, so both the classic and ELK
    // kernels still receive a plain flat {nodes, edges}. Per-view (reset in
    // render()); survives re-layout / preset switches (_rebuild keeps it).
    this.collapsedArms = new Set();
    // Set by _buildModel each pass: how many arms are actually collapsed in the
    // current model (a collapse key whose switch node isn't in view is inert).
    this._collapsedActive = 0;

    // MANUAL LAYOUT EDITING. `manual` = the whole view is user-arranged: the
    // first time a node is dragged, EVERY node's current auto-layout position is
    // snapshotted into `manualPos` and auto-layout stops running (positions come
    // from manualPos, not _computeLayout*). `convKey` keys the per-conversation
    // localStorage entry (the view root key / spec). `onManualChange` lets the
    // controller repaint the toolbar chip / READY line. See _snapshotManual,
    // _dominatedSubtree, and the pointer handler.
    this.manual = false;
    this.manualPos = new Map();       // id -> {x,y} (user-arranged positions)
    this._manualMoved = 0;            // # of nodes actually moved (READY MANUAL:<n>)
    this._movedIds = new Set();       // ids the user actually dragged (dump basis)
    this.convKey = null;              // localStorage key for this conversation
    this.onManualChange = callbacks.onManualChange || (() => {});
    // Manual editing is a per-instance opt-in. The DIALOG tab enables it; the
    // floating overlay leaves it OFF (v1 is tab-only) so overlay drags stay pans
    // and it never restores/persists a manual arrangement. Auto-layout there is
    // completely unchanged.
    this.manualEnabled = callbacks.manualEnabled !== false;
    // Overlay to draw the dashed selection bounding box (set during drag).
    this._selBox = null;              // {minX,minY,maxX,maxY} or null

    // SNAP TO GRID. When on, a manual drag snaps the dragged anchor node's CENTER
    // to the nearest GRID x GRID intersection (world space) LIVE during the drag,
    // translating the whole dominated subtree by the snapped delta so relative
    // arrangement is preserved. Off by default. Persisted in the per-conversation
    // manual record (restored on open); toggling it does NOT move existing nodes.
    // When on and in manual mode, a faint grid overlay is drawn behind the graph.
    this.snapGrid = false;

    // PER-NODE MERGE MARKS. A shared node (in-degree >= 2 within the view) can be
    // marked 'unmerge' (clone its self-contained leaf block once per parent) or
    // 'reference' (show its block once, detached, with a dashed LINK from each
    // parent). At most one mark per node. Applied as a STATELESS model transform
    // in _applyMarks (after the collapse pass, before layout) so the marks are
    // reproducible from this Map alone. Persisted alongside manualPos (same
    // localStorage record + JSON dump). Per-conversation (reset in render()).
    this.nodeMarks = new Map();       // id -> 'unmerge' | 'reference'
    this._markError = null;           // last unmerge validation failure (inline)

    host.innerHTML = '';
    this.svg = svg('svg', { class: 'dlgcanvas' }, host);
    this.svg.style.cursor = 'grab';
    this.gRoot = svg('g', { class: 'dlgViewport' }, this.svg);
    this.gEdges = svg('g', {}, this.gRoot);
    this.gNodes = svg('g', {}, this.gRoot);
    this._wirePointer();
  }

  /**
   * Load and render a component/neighborhood. `spec` is passed to
   * db.graphFor(); `rootKeyOrId` names the layout root (a key or a nodeId).
   */
  render(db, spec, rootKeyOrId) {
    this.db = db;
    this.graph = db.graphFor(spec);
    this.rootId = this._resolveRootId(rootKeyOrId);
    this.selectedId = null;
    this.collapsedArms = new Set();   // collapse is per-view; navigation resets it
    // Manual layout is per-conversation. Compute a stable key from the view root
    // + spec, then try to restore a saved arrangement for it (localStorage).
    this.convKey = this._convKey(spec, rootKeyOrId);
    this.manual = false;
    this.manualPos = new Map();
    this._movedIds = new Set();
    this._selBox = null;
    this.nodeMarks = new Map();       // marks are per-conversation; navigation resets
    this._markError = null;
    this.snapGrid = false;            // snap is per-conversation; navigation resets
    this._restoreManual();            // populates manualPos + marks + snap; sets manual if saved
    this._rebuild();
    this.fit();
    this.onManualChange();
  }

  /**
   * Stable per-conversation key for the manual-layout localStorage entry. Uses
   * the view root key/id first (the same identifier deep links use, e.g.
   * 3000019) and falls back to the JSON spec so hub/forward/component views each
   * get their own slot.
   */
  _convKey(spec, rootKeyOrId) {
    let root = '';
    if (rootKeyOrId !== undefined && rootKeyOrId !== null) root = String(rootKeyOrId);
    let sp = '';
    try { sp = JSON.stringify(spec); } catch (_) { sp = String(spec); }
    return root ? `${root}` : sp;
  }

  /** localStorage key namespace for manual layouts. */
  _lsKey() { return 'bakDlgManual:' + this.convKey; }

  /**
   * Re-render the SAME view spec with an extended node set (expand-in-place),
   * preserving selection and roughly the camera focus (the clicked card stays
   * visible). `newSpec` is the extended spec; `keepVisibleId` is the expanded card.
   */
  reRender(db, newSpec, keepVisibleId) {
    this.db = db;
    this.graph = db.graphFor(newSpec);
    this._rebuild();
    // Roughly preserve camera focus: keep the expanded card on screen. If it is
    // gone (expanded away), re-fit; otherwise pan it into view at current zoom.
    if (keepVisibleId && this.layout && this.layout.pos.has(keepVisibleId)) {
      this.centerOn(keepVisibleId);
    } else {
      this.fit();
    }
  }

  /**
   * Rebuild the render model + layout + drawing.
   *
   * CLASSIC: synchronous — compute + draw immediately.
   *
   * ELK: async and off-thread. To avoid flashing the (unreadable, wide-strip)
   * classic layout as an intermediate, the canvas is CLEARED and a centered
   * "laying out N nodes…" placeholder is shown while the worker computes; the
   * graph is drawn only when ELK returns (_computeLayoutElk). If ELK errors, that
   * path falls back to the synchronous classic layout so there is always a
   * result.
   */
  _rebuild() {
    this._buildModel();
    // MANUAL MODE: auto-layout is frozen. Positions come from manualPos (a
    // snapshot of the last auto-layout, edited by dragging). Build this.layout
    // directly and draw — never re-run _computeLayout*.
    if (this.manual) {
      this._applyManualLayout();
      this._draw();
      this.onStatus(null);
      return;
    }
    const preset = presetFor(this.layoutPreset);
    if (preset.kind === 'elk') {
      // Show the placeholder INSTEAD of the classic strip; ELK draws when ready.
      this._showPlaceholder();
      this._computeLayoutElk(preset);
      return;
    }
    // The classic kernel is synchronous. A large flat graph (up
    // to the whole ~5362-node giant component) takes a multi-second pass; surface
    // a status hint for it.
    const big = this.model.nodes.length > 600;
    if (big) this.onStatus(`laying out ${this.model.nodes.length} nodes…`);
    this._computeLayout();   // synchronous classic layout (always populates this.layout)
    this._draw();
    if (big) this.onStatus(null);
  }

  /**
   * Clear the canvas and paint a centered "laying out N nodes…" placeholder (ELK
   * mode, while the async worker computes). Leaves this.layout null so fit() and
   * the draw pass no-op until _computeLayoutElk (or its classic fallback) lands.
   */
  _showPlaceholder() {
    this.layout = null;
    this.gEdges.innerHTML = '';
    this.gNodes.innerHTML = '';
    const rect = this.svg.getBoundingClientRect();
    const cx = (rect.width || 1000) / 2;
    const cy = (rect.height || 700) / 2;
    // Draw in screen space: reset the viewport transform so the text is centered
    // regardless of the previous view's pan/zoom.
    this.scale = 1; this.tx = 0; this.ty = 0;
    this._applyTransform();
    const g = svg('g', { class: 'dlgPlaceholder' }, this.gNodes);
    const ring = svg('circle', {
      cx, cy: cy - 22, r: 13, fill: 'none', stroke: '#5fd6d6',
      'stroke-width': 2.5, 'stroke-opacity': 0.5, 'stroke-dasharray': '20 14',
    }, g);
    svg('animateTransform', {
      attributeName: 'transform', type: 'rotate',
      from: `0 ${cx} ${cy - 22}`, to: `360 ${cx} ${cy - 22}`,
      dur: '1s', repeatCount: 'indefinite',
    }, ring);
    const t = svg('text', {
      x: cx, y: cy + 12, 'text-anchor': 'middle', 'font-size': 15,
      fill: '#8b93a0', 'font-family': 'ui-monospace, monospace',
    }, g);
    t.textContent = `laying out ${this.model.nodes.length} nodes…`;
    this.onStatus(`laying out ${this.model.nodes.length} nodes…`);
  }

  /**
   * Switch the layout PRESET (a named elklayout.js config: 'classic', 'layered',
   * 'tree-down', 'force', …) and re-lay-out in place. Idempotent. Unknown names
   * resolve to the default preset. ELK loads lazily on first use.
   */
  setLayoutEngine(name) {
    const key = presetFor(name) === presetFor(DEFAULT_PRESET) && name !== DEFAULT_PRESET
      ? DEFAULT_PRESET : name;
    if (this.layoutPreset === key) return;
    this.layoutPreset = key;
    this._saveManual();               // remember this dialog's layout choice
    if (!this.graph) return;
    // A manual arrangement is the user's OWN layout and outlasts a preset change:
    // the preset only governs AUTO layout, so a manually-arranged view keeps its
    // positions (the new preset takes effect only when the user hits "reset to
    // auto"). Discarding manual edits here would destroy the current conversation's
    // arrangement — and, since the preset is shared, other open conversations' too.
    // Only auto-mode views re-lay-out on a preset change.
    if (this.manual) return;
    this._rebuild();
    this.fit();
  }

  /**
   * Replace the live TUNE-panel override map (see this.layoutOverrides) and
   * re-lay-out in place. `obj` is a partial ELK layoutOptions map merged on top
   * of the active preset (overrides win). ELK-only: under the classic preset it
   * is stored but has no effect (the classic kernel ignores ELK options). Pass
   * {} to clear back to the pure preset.
   */
  setLayoutOverrides(obj) {
    this.layoutOverrides = obj ? { ...obj } : {};
    if (!this.graph) return;
    this._rebuild();
    this.fit();
  }

  /** Map a key or nodeId to a nodeId present in the current graph. */
  _resolveRootId(rootKeyOrId) {
    if (rootKeyOrId === undefined || rootKeyOrId === null) return null;
    const ids = new Set(this.graph.nodes.map((n) => n.id));
    if (ids.has(rootKeyOrId)) return rootKeyOrId;
    // A directory key: find its node id inside the graph.
    const node = this.db.nodeByKey(rootKeyOrId);
    if (node && ids.has(node.id)) return node.id;
    return null;
  }

  // -- render model ---------------------------------------------------------

  /**
   * Transform the raw {nodes, edges} into a FLAT render model:
   *   model.nodes  — [{id, node, kind:'card'}] — every graph node a full card
   *   model.edges  — [{from, to, label, kind}] (in-view edges only)
   *   model.byId   — Map(id -> model node) for the nodes actually rendered
   * Nothing is spliced, compacted, hidden, or capped.
   */
  _buildModel() {
    const db = this.db;
    const raw = this.graph;
    // Apply the manual per-arm collapse filter: drop arm-exclusive nodes and
    // splice in a stub per collapsed arm. Both layout kernels get the resulting
    // flat {nodes, edges}. `collapse` also carries the audit bookkeeping.
    const collapse = this._applyArmCollapse(raw);
    const nodes = collapse.nodes;   // filtered flat node payloads (raw + stubs)
    const edges = collapse.edges;   // filtered flat edges (arm edge -> stub)
    this._collapsedActive = collapse.activeArms;

    const present = new Set(nodes.map((n) => n.id));
    const nodeById = new Map(nodes.map((n) => [n.id, n]));
    const dbNodeById = new Map();
    for (const n of nodes) dbNodeById.set(n.id, db.nodes.get(n.id));

    const modelNodes = [];
    const byId = new Map();
    for (const n of nodes) {
      const m = { id: n.id, node: n, kind: n.stub ? 'stub' : 'card' };
      modelNodes.push(m);
      byId.set(n.id, m);
    }

    const modelEdges = [];
    const seenEdge = new Set();
    for (const e of edges) {
      if (!present.has(e.from) || !present.has(e.to)) continue;
      const sig = `${e.from}\x00${e.to}\x00${e.kind}`;
      if (seenEdge.has(sig)) continue;
      seenEdge.add(sig);
      modelEdges.push({
        from: e.from, to: e.to, label: e.label, kind: e.kind,
        switchArm: e.switchArm || null, stub: e.stub || false,
      });
    }

    this.model = {
      nodes: modelNodes, edges: modelEdges,
      byId, nodeById, dbNodeById,
      hiddenCollapsed: collapse.hiddenEdges,
    };

    // Apply per-node merge marks (unmerge / reference) on the flat model, AFTER
    // the collapse pass and BEFORE layout. Rebuilds model.byId/nodeById for any
    // synthesized clone / ref-link nodes so downstream (layout, audit, draw) is
    // unchanged.
    this._applyMarks();

    // Flag "audio-only" cards (blank body + only sfx/music ops) so they render
    // as compact ♪/∿ chips instead of full-size cards (see _boxOf/_drawAudioNode).
    for (const mn of this.model.nodes) {
      mn.audio = mn.kind === 'card' ? this._audioKind(mn.cloneOf || mn.id) : null;
    }
  }

  /**
   * 'music' | 'sfx' | null. An audio-only node has NO own body text and its ops
   * are exclusively sfx/music (op 11/12) plus filler (nop/chain). Switch nodes
   * never qualify. 'music' if any op-12 track (a1 >= 1000), else 'sfx'.
   */
  _audioKind(id) {
    const raw = this.db.nodes.get(id);
    if (!raw || raw.switchInfo) return null;
    for (const b of raw.textBytes) if (b >= 0x21) return null; // has own body text
    let music = false, sfx = false;
    for (const o of raw.ops) {
      if (o.op === 11) sfx = true;
      else if (o.op === 12) { if (o.a1 >= 1000) music = true; else sfx = true; }
      else if (o.op !== 0 && o.op !== 16) return null; // any other content op
    }
    if (!music && !sfx) return null;
    return music ? 'music' : 'sfx';
  }

  /**
   * Apply the per-node merge marks (this.nodeMarks) to the flat render model
   * IN PLACE. Two transforms break a MERGE (a shared node C with in-degree >= 2)
   * so the graph reads as a tree:
   *
   *   reference C — remove every real edge P->C; C + its subtree stay in the
   *     model as a DETACHED root; each former parent P gets a lightweight dashed
   *     LINK node (kind 'ref') titled with C, and a P->ref edge (kind 'ref').
   *     Clicking the ref pans/selects the real C. No isolation requirement.
   *
   *   unmerge C — VALIDATE C's forward subtree S is a self-contained LEAF BLOCK
   *     (_canUnmerge). If valid, for each incoming parent edge Pi->C, deep-CLONE
   *     S with fresh ids `um:<Pi>:<origId>`, copy S's internal edges among the
   *     clone, rewire Pi->clone(C). The ORIGINAL S nodes + Pi->C edges are
   *     removed. Clones render as ordinary cards flagged .clone for legibility.
   *     Invalid marks are skipped and recorded in this._markError.
   *
   * Stateless: recomputed from nodeMarks on every render. Marks on non-shared
   * nodes (in-degree < 1 in the current model) are inert.
   */
  _applyMarks() {
    this._markError = null;
    if (!this.nodeMarks || this.nodeMarks.size === 0) return;
    const m = this.model;

    // Work over live copies; rebuild indices at the end.
    let nodes = m.nodes.slice();
    let edges = m.edges.slice();

    // Model in-degree over the CURRENT model edges (what "shared" means in view).
    const inDegOf = (edgeList) => {
      const d = new Map();
      for (const mn of nodes) d.set(mn.id, 0);
      for (const e of edgeList) if (d.has(e.to)) d.set(e.to, d.get(e.to) + 1);
      return d;
    };

    // -- reference marks first (they only remove/redirect edges) --------------
    for (const [id, kind] of this.nodeMarks) {
      if (kind !== 'reference') continue;
      const present = new Set(nodes.map((n) => n.id));
      if (!present.has(id)) continue;
      const indeg = inDegOf(edges);
      if ((indeg.get(id) || 0) < 2) continue;   // not a merge in this view: inert
      const parents = [];
      const kept = [];
      for (const e of edges) {
        if (e.to === id) { parents.push(e); } else { kept.push(e); }
      }
      if (parents.length < 2) continue;
      edges = kept;
      // One dashed ref LINK per parent, pointing at the real C.
      const title = this._markTitle(id);
      let seq = 0;
      for (const pe of parents) {
        const refId = `ref:${pe.from}:${id}:${seq++}`;
        nodes.push({
          id: refId, kind: 'ref', refTarget: id, refLabel: title,
          node: { id: refId, class: 'ref', refTarget: id, refLabel: title },
        });
        edges.push({
          from: pe.from, to: refId, label: pe.label, kind: 'ref',
          switchArm: pe.switchArm || null, stub: false, refTarget: id,
        });
      }
    }

    // -- unmerge marks (clone the node's PRIVATE block per parent) ------------
    // Each external parent gets its own copy of C and everything C EXCLUSIVELY
    // dominates (reachable only through C). Edges leaving that private block into
    // a SHARED descendant (reachable from outside too — e.g. a common end-of-path
    // sink) are redirected to the ORIGINAL, which stays merged, so the shared
    // node's other parents are never stranded.
    for (const [id, kind] of this.nodeMarks) {
      if (kind !== 'unmerge') continue;
      const chk = this._canUnmergeOn(nodes, edges, id);
      if (!chk.ok) { if (!this._markError) this._markError = chk; continue; }
      const S = chk.subtree;                 // C + the nodes it exclusively dominates
      // EXTERNAL parents of C: incoming edges from OUTSIDE S (the merges to break).
      const parents = edges.filter((e) => e.to === id && !S.has(e.from));
      // Edges INTERNAL to the private block (both ends in S) — cloned per copy.
      const internal = edges.filter((e) => S.has(e.from) && S.has(e.to));
      // Edges LEAVING the block into a shared descendant — each clone points at
      // the ORIGINAL shared node (kept merged), not at a clone.
      const crossOut = edges.filter((e) => S.has(e.from) && !S.has(e.to));
      // Everything else survives EXCEPT the external parent->C edges and the
      // private-block nodes + their internal/crossOut edges (replaced per parent).
      const keptEdges = edges.filter((e) =>
        !(e.to === id && !S.has(e.from))
        && !(S.has(e.from) && S.has(e.to))
        && !(S.has(e.from) && !S.has(e.to)));
      const keptNodes = nodes.filter((mn) => !S.has(mn.id));
      const origById = new Map(nodes.map((mn) => [mn.id, mn]));
      const newNodes = keptNodes.slice();
      const newEdges = keptEdges.slice();
      // Manual-layout seeding: so the per-parent clones don't all pile at the
      // origin (they carry no saved position), stamp each with a delta that
      // drops its copy of C directly beneath that parent, translating the whole
      // cloned subtree by the same amount (preserving its arranged shape).
      const posOf = (nid) => this.manualPos.get(nid)
        || (this.layout && this.layout.pos && this.layout.pos.get(nid)) || null;
      const cPos = posOf(id);
      for (const pe of parents) {
        const pref = `um:${pe.from}:`;
        const cloneId = (orig) => pref + orig;
        const pPos = posOf(pe.from);
        // Clone every S node with a fresh id (flagged .clone).
        for (const sid of S) {
          const om = origById.get(sid);
          const src = om ? om.node : { id: sid };
          const nid = cloneId(sid);
          // Manual-layout seed: land this clone just below ITS parent. Anchored
          // to the PARENT position (always present) — NOT to C's, which the
          // unmerge just removed, so it can never collapse every clone onto one
          // spot. Shape relative to C is preserved when both positions are known.
          let seedPos = null;
          if (pPos) {
            const sPos = posOf(sid);
            const ox = (cPos && sPos) ? sPos.x - cPos.x : 0;
            const oy = (cPos && sPos) ? sPos.y - cPos.y : 0;
            seedPos = { x: pPos.x + ox, y: pPos.y + CARD_H + 40 + oy };
          }
          newNodes.push({
            id: nid, kind: 'card', clone: true, cloneOf: sid, _seedPos: seedPos,
            node: { ...src, id: nid, _cloneOf: sid },
          });
        }
        // Copy the internal edges among the clone.
        for (const e of internal) {
          newEdges.push({
            from: cloneId(e.from), to: cloneId(e.to), label: e.label,
            kind: e.kind, switchArm: e.switchArm ? { ...e.switchArm,
              stateNodeId: cloneId(e.switchArm.stateNodeId) } : null,
            stub: e.stub || false,
          });
        }
        // Edges from a clone into a SHARED descendant point at the ORIGINAL node
        // (which stays merged) — so unmerging a node whose tail funnels into a
        // common sink doesn't strand the sink's other parents.
        for (const e of crossOut) {
          newEdges.push({
            from: cloneId(e.from), to: e.to, label: e.label, kind: e.kind,
            switchArm: e.switchArm || null, stub: e.stub || false,
          });
        }
        // Rewire the parent edge to this parent's clone of C.
        newEdges.push({
          from: pe.from, to: cloneId(id), label: pe.label, kind: pe.kind,
          switchArm: pe.switchArm || null, stub: pe.stub || false,
        });
      }
      nodes = newNodes;
      edges = newEdges;
    }

    // Rebuild the model in place.
    const byId = new Map();
    const nodeById = new Map();
    for (const mn of nodes) {
      byId.set(mn.id, mn);
      nodeById.set(mn.id, mn.node);
    }
    m.nodes = nodes;
    m.edges = edges;
    m.byId = byId;
    m.nodeById = nodeById;
    m.marked = true;
  }

  /** Short display title for a marked node C (used on ref links). */
  _markTitle(id) {
    const mn = this.model.byId.get(id) || (this.model.nodeById.get(id) && { node: this.model.nodeById.get(id) });
    const n = mn && mn.node;
    let s = (n && n.firstLine) || '';
    if (!s) {
      const raw = this.db && this.db.nodes.get(id);
      if (raw) s = this.db.firstLine(raw, 24) || '';
    }
    if (!s) {
      const key = n && n.key != null ? n.key : id;
      s = String(key);
    }
    return s.length > 24 ? s.slice(0, 23) + '…' : s;
  }

  /**
   * The leaf-block validation for `unmerge id` over an explicit {nodes, edges}
   * model view. Returns {ok:true, subtree:Set} or {ok:false, reason, id, ...}.
   * `subtree` is C's DOMINATED set (C + nodes reachable only through it). Valid
   * iff C has >= 2 external parents (a real merge to break); shared descendants
   * are allowed — the transform keeps them merged rather than rejecting.
   */
  _canUnmergeOn(nodes, edges, id) {
    const present = new Set(nodes.map((n) => n.id));
    if (!present.has(id)) return { ok: false, id, reason: `node ${id} is not in view` };
    const out = new Map();
    const parentsOf = new Map();
    for (const nid of present) { out.set(nid, []); parentsOf.set(nid, []); }
    for (const e of edges) {
      if (!present.has(e.from) || !present.has(e.to)) continue;
      out.get(e.from).push(e.to);
      parentsOf.get(e.to).push(e.from);
    }
    // Forward reach of C within the view.
    const reach = new Set([id]);
    const q = [id];
    while (q.length) {
      const c = q.shift();
      for (const t of out.get(c) || []) if (!reach.has(t)) { reach.add(t); q.push(t); }
    }
    // DOMINATED set S: C plus every reachable node whose EVERY in-view parent is
    // already in S (all paths to it pass through C). Nodes with a parent from
    // outside — the SHARED descendants — are left out; the transform keeps those
    // merged and points the clones at the originals.
    const S = new Set([id]);
    let grew = true;
    while (grew) {
      grew = false;
      for (const x of reach) {
        if (S.has(x)) continue;
        const ps = parentsOf.get(x);
        if (ps.length && ps.every((p) => S.has(p))) { S.add(x); grew = true; }
      }
    }
    // EXTERNAL parents = in-edges to C from OUTSIDE S (the merges to break). Need
    // >= 2 for there to be a merge; otherwise unmerge is a silent no-op.
    const extParents = parentsOf.get(id).filter((p) => !S.has(p)).length;
    if (extParents < 2) {
      return { ok: false, id, reason:
        `${id} isn't a merge in this view (${extParents} external parent${extParents === 1 ? '' : 's'}) — open a view where it's reached from ≥2 places` };
    }
    return { ok: true, id, subtree: S };
  }

  /**
   * Public validation for `unmerge id` against the CURRENT (post-collapse,
   * pre-mark) flat model. Returns {ok, reason?}. Used by the UI (enable/disable
   * + inline error) and the window.__dialog.canUnmerge test hook. Recomputes the
   * base model so it is independent of any marks already applied.
   */
  canUnmerge(id) {
    if (!this.graph) return { ok: false, id, reason: 'no graph' };
    const saved = this.nodeMarks;
    const savedErr = this._markError;   // _buildModel clears it — preserve
    this.nodeMarks = new Map();       // base (unmarked) model for the check
    this._buildModel();
    const res = this._canUnmergeOn(this.model.nodes, this.model.edges, id);
    this.nodeMarks = saved;
    this._buildModel();               // restore the marked model
    this._markError = savedErr;
    return res.ok ? { ok: true, id } : { ok: res.ok, id, reason: res.reason, boundary: res.boundary };
  }

  /** In-degree of a node in the CURRENT base (unmarked) model — for the UI. */
  inDegreeOf(id) {
    if (!this.graph) return 0;
    const saved = this.nodeMarks;
    const savedErr = this._markError;   // _buildModel clears it — preserve
    this.nodeMarks = new Map();
    this._buildModel();
    let d = 0;
    for (const e of this.model.edges) if (e.to === id) d++;
    this.nodeMarks = saved;
    this._buildModel();
    this._markError = savedErr;
    return d;
  }

  /**
   * Set / clear a node's merge mark and re-render + persist. `kind` is
   * 'unmerge' | 'reference' | null (clear). For 'unmerge' the leaf-block rule is
   * validated first; an invalid mark is NOT applied and the failure is returned
   * (and surfaced inline via onMarkError). Returns {ok, reason?}.
   */
  setMark(id, kind) {
    if (!this.graph) return { ok: false, reason: 'no graph' };
    if (kind === null || kind === undefined) {
      this.nodeMarks.delete(id);
    } else if (kind === 'unmerge') {
      const chk = this.canUnmerge(id);
      if (!chk.ok) { this._markError = chk; this.onManualChange(); return chk; }
      this.nodeMarks.set(id, 'unmerge');
    } else if (kind === 'reference') {
      this.nodeMarks.set(id, 'reference');
    } else {
      return { ok: false, reason: `unknown mark ${kind}` };
    }
    this._markError = null;
    this._rebuild();
    this.fit();
    this._saveManual();
    this.onManualChange();
    return { ok: true, id, mark: kind || null };
  }

  /** The active merge marks as a plain object {id: 'unmerge'|'reference'}. */
  marksObject() {
    const o = {};
    for (const [id, k] of this.nodeMarks) o[id] = k;
    return o;
  }

  /** Count of active marks whose node is actually present in the current graph. */
  markCount() {
    if (!this.graph) return 0;
    const present = new Set(this.graph.nodes.map((n) => n.id));
    let n = 0;
    for (const id of this.nodeMarks.keys()) if (present.has(id)) n++;
    return n;
  }

  /**
   * FLAT-GRAPH arm-collapse filter. Given the raw flat {nodes, edges} and
   * this.collapsedArms (a set of "stateNodeId\x00armIndex" keys), remove every
   * node reachable ONLY via a collapsed arm and replace each collapsed arm's
   * subtree with a single stub card. Shared/converging nodes still reachable from
   * a live path stay. Returns:
   *   { nodes, edges, activeArms, hiddenEdges }
   * where nodes/edges are the filtered flat payload (stubs added), activeArms is
   * the number of collapse keys that actually applied (switch in view), and
   * hiddenEdges counts the raw edges suppressed by the collapse (for edgeAudit's
   * `hiddenCollapsed` bucket). With no collapse this is an identity pass.
   */
  _applyArmCollapse(raw) {
    const rawNodes = raw.nodes;
    const rawEdges = raw.edges;
    const present = new Set(rawNodes.map((n) => n.id));

    // Which collapse keys are actually applicable (their switch node is in view)?
    const nodeById = new Map(rawNodes.map((n) => [n.id, n]));
    const active = [];       // [{key, stateNodeId, armIndex, arm, node}]
    for (const key of this.collapsedArms) {
      const [stateNodeId, armStr] = key.split('\x00');
      const node = nodeById.get(stateNodeId);
      if (!node || !node.switch) continue;
      const armIndex = parseInt(armStr, 10);
      const arm = node.switch.arms[armIndex];
      if (!arm) continue;
      active.push({ key, stateNodeId, armIndex, arm, node });
    }
    if (active.length === 0) {
      return { nodes: rawNodes, edges: rawEdges, activeArms: 0, hiddenEdges: 0 };
    }

    // Edges suppressed by collapse: the collapsed-arm out-edges themselves
    // (switch -> arm target). Cut them, then recompute forward reachability from
    // the live seeds; any node no longer reachable is arm-exclusive → removed.
    const cutEdge = new Set();       // "from\x00to\x00kind"
    for (const a of active) {
      for (const e of rawEdges) {
        if (e.from !== a.stateNodeId) continue;
        if (!e.switchArm || e.switchArm.armIndex !== a.armIndex) continue;
        cutEdge.add(`${e.from}\x00${e.to}\x00${e.kind}`);
      }
    }

    // Forward adjacency over the NON-cut edges, plus the FULL-graph in-degree
    // (over ALL edges, including cut ones). Seeds must be genuine roots of the
    // full graph — NOT a node orphaned only because its incoming arm edge was
    // cut (seeding those would wrongly keep the whole arm subtree alive).
    const out = new Map();
    const fullIndeg = new Map();
    for (const id of present) { out.set(id, []); fullIndeg.set(id, 0); }
    for (const e of rawEdges) {
      if (!present.has(e.from) || !present.has(e.to)) continue;
      fullIndeg.set(e.to, fullIndeg.get(e.to) + 1);
      if (cutEdge.has(`${e.from}\x00${e.to}\x00${e.kind}`)) continue;
      out.get(e.from).push(e.to);
    }
    // Live seeds: the view root (always live) + every FULL-graph in-degree-0 node
    // (a real root). BFS forward over non-cut edges → nodes surviving collapse.
    const live = new Set();
    const queue = [];
    const seed = (id) => { if (present.has(id) && !live.has(id)) { live.add(id); queue.push(id); } };
    if (this.rootId) seed(this.rootId);
    for (const id of present) if (fullIndeg.get(id) === 0) seed(id);
    while (queue.length) {
      const cur = queue.shift();
      for (const to of out.get(cur) || []) seed(to);
    }

    // Filtered node list: live raw nodes + one stub per active arm.
    const nodes = rawNodes.filter((n) => live.has(n.id));
    for (const a of active) {
      const armExclusive = a.arm.targetIds.filter((t) => present.has(t) && !live.has(t));
      // Count everything removed under THIS arm (its exclusive forward closure).
      const count = this._armExclusiveCount(a, rawEdges, present, live);
      nodes.push({
        id: this._stubId(a.stateNodeId, a.armIndex),
        stub: true,
        class: 'switch',
        armIndex: a.armIndex,
        stateNodeId: a.stateNodeId,
        armLabel: a.arm.label,
        hiddenCount: count,
        firstLine: `${a.arm.label} · ${count} node${count === 1 ? '' : 's'} — click to expand`,
        key: null, speaker: 'narrator', badges: [], shared: false, switch: null,
      });
      void armExclusive;
    }

    // Filtered edges: keep any edge whose endpoints are both live; redirect a
    // collapsed-arm edge to the stub; drop all others (counted as hidden).
    const nodeIds = new Set(nodes.map((n) => n.id));
    const edges = [];
    let hiddenEdges = 0;
    const stubEdgeSeen = new Set();
    for (const e of rawEdges) {
      if (!present.has(e.from) || !present.has(e.to)) continue;
      const isCut = cutEdge.has(`${e.from}\x00${e.to}\x00${e.kind}`);
      if (isCut) {
        // Redirect the switch's collapsed-arm edge to its stub (one per arm).
        const a = active.find((x) => x.stateNodeId === e.from
          && e.switchArm && e.switchArm.armIndex === x.armIndex);
        if (a) {
          const stubId = this._stubId(a.stateNodeId, a.armIndex);
          const sig = e.from + '\x00' + stubId;
          if (!stubEdgeSeen.has(sig)) {
            stubEdgeSeen.add(sig);
            edges.push({
              from: e.from, to: stubId, label: e.label, kind: e.kind,
              switchArm: e.switchArm, stub: true,
            });
          }
        }
        hiddenEdges++;   // the original arm edge is suppressed
        continue;
      }
      if (nodeIds.has(e.from) && nodeIds.has(e.to)) {
        edges.push(e);
      } else {
        hiddenEdges++;   // edge into/among removed arm-exclusive nodes
      }
    }
    return { nodes, edges, activeArms: active.length, hiddenEdges };
  }

  /** Stub node id for a collapsed arm. */
  _stubId(stateNodeId, armIndex) { return `stub:${stateNodeId}:${armIndex}`; }

  /**
   * Count the arm-exclusive nodes hidden by ONE collapsed arm: nodes reachable
   * from the arm's targets that are NOT in the live set (i.e. removed). Used only
   * for the stub's "N nodes" label.
   */
  _armExclusiveCount(a, rawEdges, present, live) {
    const out = new Map();
    for (const id of present) out.set(id, []);
    for (const e of rawEdges) {
      if (present.has(e.from) && present.has(e.to)) out.get(e.from).push(e.to);
    }
    const seen = new Set();
    const queue = a.arm.targetIds.filter((t) => present.has(t) && !live.has(t));
    for (const t of queue) seen.add(t);
    let i = 0;
    while (i < queue.length) {
      const cur = queue[i++];
      for (const to of out.get(cur) || []) {
        if (!live.has(to) && !seen.has(to)) { seen.add(to); queue.push(to); }
      }
    }
    return seen.size;
  }

  /** Toggle a switch arm's collapse; re-lay-out in place (preserves selection). */
  toggleArmCollapse(stateNodeId, armIndex) {
    const key = armKey(stateNodeId, armIndex);
    if (this.collapsedArms.has(key)) this.collapsedArms.delete(key);
    else this.collapsedArms.add(key);
    this._rebuild();
    this.fit();
    this.onStatus(null);   // repaint READY (COLLAPSED count may have changed)
  }

  /** Count of arms currently collapsed AND applicable in the live view. */
  collapsedCount() { return this._collapsedActive || 0; }

  // -- layout ---------------------------------------------------------------

  /**
   * ELK layout backend. Builds ONE FLAT ELK graph from the render model (see
   * elklayout.js) — no compounds, so ELK just runs an ordinary layered pass.
   * Rewrites this.layout in the SAME shape the classic path produces (absolute
   * node rects, orthogonal edge routes) so the draw pass, edgeAudit, layoutSanity,
   * fit and interaction are unchanged. Async + generation-guarded. While it runs,
   * _rebuild has cleared the canvas to a "laying out…" placeholder; the graph is
   * drawn only when ELK returns. On ANY failure (load or layout) it falls back to
   * the synchronous classic layout so there is always a result.
   */
  async _computeLayoutElk(preset) {
    const gen = ++this._layoutGen;
    const model = this.model;
    const p = preset || presetFor(this.layoutPreset);
    let elk;
    try {
      if (!this._elk) this._elk = await loadElk();
      elk = this._elk;
    } catch (err) {
      console.warn('ELK load failed; falling back to classic layout:', err && err.message);
      this._fallbackClassic(gen);
      return;
    }
    const { elkGraph } = buildElkGraph(
      model, (id) => this._boxOf(id), p.options, this.layoutOverrides);
    const t0 = (typeof performance !== 'undefined' ? performance.now() : Date.now());
    let laid;
    try {
      laid = await elk.layout(elkGraph);
    } catch (err) {
      this._lastElkError = { message: err && err.message, graph: elkGraph };
      console.warn('ELK layout threw; falling back to classic layout:', err && err.message);
      try { window.__lastElkErrorGraph = JSON.stringify(elkGraph); } catch (_) {}
      this._fallbackClassic(gen);
      return;
    }
    const t1 = (typeof performance !== 'undefined' ? performance.now() : Date.now());
    if (gen !== this._layoutGen) return;   // superseded by a newer layout
    this.lastLayoutMs = t1 - t0;
    this._applyElkLayout(laid);
    this._draw();
    this.onStatus(null);
    this.fit();   // frame the freshly-laid-out graph (placeholder had no layout)
  }

  /**
   * Render the synchronous classic layout as the ELK fallback: only when this is
   * still the current generation (a newer render hasn't superseded us).
   */
  _fallbackClassic(gen) {
    if (gen !== this._layoutGen) return;
    this._computeLayout();
    this._draw();
    this.onStatus(null);
    this.fit();
  }

  /**
   * Convert a laid-out (flat) ELK graph into this.layout (classic shape). Node
   * rects come from ELK absolute coords; edge `routes` carry ELK's orthogonal
   * bend points keyed by "from\x00to".
   */
  _applyElkLayout(laid) {
    const m = this.model;
    const { pos: elkPos, routes: elkRoutes } = flattenElk(laid);

    const pos = new Map();
    const rank = new Map();      // x-derived pseudo-rank (column order)
    let minX = Infinity, minY = Infinity, maxX = -Infinity, maxY = -Infinity;

    for (const mn of m.nodes) {
      const p = elkPos.get(mn.id);
      if (!p) continue;
      pos.set(mn.id, { x: p.x, y: p.y, rank: 0 });
      const b = this._boxOf(mn.id);
      minX = Math.min(minX, p.x); minY = Math.min(minY, p.y);
      maxX = Math.max(maxX, p.x + b.w); maxY = Math.max(maxY, p.y + b.h);
    }
    // Pseudo-rank by x-position so _classifyEdge's back-edge test still works.
    const xs = [...pos.values()].map((p) => p.x).sort((a, b) => a - b);
    const rankOfX = (x) => {
      let r = 0; for (const v of xs) { if (v < x - 1) r++; else break; } return r;
    };
    for (const [id, p] of pos) { p.rank = rankOfX(p.x); rank.set(id, p.rank); }

    // Edge routes keyed by endpoint pair (draw pass looks these up).
    const routes = new Map();
    let ei = 0;
    for (const e of m.edges) {
      if (!m.byId.has(e.from) || !m.byId.has(e.to)) continue;
      if (e.from === e.to) continue;
      const pts = elkRoutes.get(`e${ei++}`);
      if (pts && pts.length) routes.set(e.from + '\x00' + e.to, pts);
    }

    if (minX === Infinity) { minX = 0; minY = 0; maxX = CARD_W; maxY = CARD_H; }
    this.layout = {
      pos, rank, routes, elk: true,
      width: maxX - minX, height: maxY - minY,
      box: { minX, minY, maxX, maxY },
    };
  }

  /**
   * Layout entry point. Runs the flat layered pipeline over the whole node set,
   * then assembles absolute positions + the outer rank map. Fills this.layout.
   */
  _computeLayout() {
    const m = this.model;
    const ids = m.nodes.map((mn) => mn.id);
    const idSet = new Set(ids);
    const out = new Map(); const inn = new Map();
    for (const id of ids) { out.set(id, []); inn.set(id, []); }
    const seen = new Set();
    for (const e of m.edges) {
      if (!idSet.has(e.from) || !idSet.has(e.to)) continue;
      const sig = e.from + '\x00' + e.to;
      if (seen.has(sig)) continue;
      seen.add(sig);
      out.get(e.from).push(e.to);
      inn.get(e.to).push(e.from);
    }
    const base = this._layeredPositions(
      ids, out, inn, this.rootId, true, (id) => this._boxOf(id));

    const pos = new Map();
    const rank = new Map();
    let minX = Infinity, minY = Infinity, maxX = -Infinity, maxY = -Infinity;
    for (const [id, p] of base.pos) {
      rank.set(id, base.rank.get(id) || 0);
      const b = this._boxOf(id);
      pos.set(id, { x: p.x, y: p.y, rank: rank.get(id) });
      minX = Math.min(minX, p.x); minY = Math.min(minY, p.y);
      maxX = Math.max(maxX, p.x + b.w); maxY = Math.max(maxY, p.y + b.h);
    }
    if (minX === Infinity) { minX = 0; minY = 0; maxX = CARD_W; maxY = CARD_H; }
    this.layout = {
      pos, rank,
      width: maxX - minX, height: maxY - minY,
      box: { minX, minY, maxX, maxY },
    };
  }

  /**
   * Core layered-layout kernel. `ids` = node ids; `out`/`inn` = adjacency Maps;
   * `rootId` = preferred rank-0 seed; `allowSerpentine` = fold long narrow chains
   * into rows. Returns {pos, width, height, ranks, serpentine, rank}. `sizeOf(id)`
   * gives each node's box.
   */
  _layeredPositions(ids, out, inn, rootId, allowSerpentine, sizeOf) {
    const size = sizeOf || ((id) => this._boxOf(id));
    const present = new Set(ids);
    // Back-edge classification via iterative DFS.
    const seeds = [];
    const seedSet = new Set();
    const addSeed = (id) => { if (!seedSet.has(id)) { seedSet.add(id); seeds.push(id); } };
    if (rootId && present.has(rootId)) addSeed(rootId);
    for (const id of ids) if ((inn.get(id) || []).length === 0) addSeed(id);
    for (const id of ids) addSeed(id);

    const color = new Map();
    const forward = new Map();
    for (const id of ids) forward.set(id, []);
    for (const s of seeds) {
      if (color.get(s)) continue;
      const stack = [{ id: s, i: 0 }];
      color.set(s, 1);
      while (stack.length) {
        const top = stack[stack.length - 1];
        const kids = out.get(top.id) || [];
        if (top.i < kids.length) {
          const v = kids[top.i++];
          if (!present.has(v)) continue;
          const c = color.get(v) || 0;
          if (c === 1) continue;
          forward.get(top.id).push(v);
          if (c === 0) { color.set(v, 1); stack.push({ id: v, i: 0 }); }
        } else { color.set(top.id, 2); stack.pop(); }
      }
    }

    const rank = new Map();
    const fparents = new Map();
    for (const id of ids) fparents.set(id, []);
    for (const id of ids) for (const c of forward.get(id)) fparents.get(c).push(id);
    const indeg = new Map();
    for (const id of ids) indeg.set(id, fparents.get(id).length);
    const tq = [];
    for (const id of ids) if (indeg.get(id) === 0) { rank.set(id, 0); tq.push(id); }
    let ti = 0;
    while (ti < tq.length) {
      const u = tq[ti++];
      const ru = rank.get(u);
      for (const v of forward.get(u)) {
        rank.set(v, Math.max(rank.get(v) ?? 0, ru + 1));
        indeg.set(v, indeg.get(v) - 1);
        if (indeg.get(v) === 0) tq.push(v);
      }
    }
    for (const id of ids) if (!rank.has(id)) rank.set(id, 0);

    const maxRank = Math.max(0, ...ids.map((id) => rank.get(id)));
    const ranks = [];
    for (let r = 0; r <= maxRank; r++) ranks.push([]);
    for (const id of ids) ranks[rank.get(id)].push(id);
    for (const col of ranks) col.sort();

    const orderOf = new Map();
    const reindex = () => { for (const col of ranks) col.forEach((id, i) => orderOf.set(id, i)); };
    reindex();
    const bary = (id, neighbors) => {
      const ns = neighbors.get(id) || [];
      if (!ns.length) return orderOf.get(id);
      let s = 0; for (const mm of ns) s += (orderOf.get(mm) ?? 0);
      return s / ns.length;
    };
    for (let sweep = 0; sweep < 2; sweep++) {
      for (let r = 1; r < ranks.length; r++) { ranks[r].sort((a, b) => bary(a, inn) - bary(b, inn)); reindex(); }
      for (let r = ranks.length - 2; r >= 0; r--) { ranks[r].sort((a, b) => bary(a, out) - bary(b, out)); reindex(); }
    }

    const rowGap = Math.max(ROW_GAP, MIN_ROW_GAP);
    const widestRank = Math.max(1, ...ranks.map((c) => c.length));
    const serpentine = allowSerpentine && ranks.length > SERP_MAX_RANKS && widestRank <= 2;
    const pos = new Map();
    let width = 0, height = 0;

    // Column x-position uses the widest box in each rank.
    const colW = ranks.map((col) => Math.max(0, ...col.map((id) => size(id).w)));
    const colH = ranks.map((col) => {
      let h = 0; for (const id of col) h += size(id).h + rowGap;
      return Math.max(0, h - rowGap);
    });

    if (serpentine) {
      const rowsOfRanks = [];
      for (let r = 0; r < ranks.length; r += SERP_ROW_RANKS) {
        rowsOfRanks.push({ start: r, cols: ranks.slice(r, r + SERP_ROW_RANKS) });
      }
      let rowTop = 0;
      rowsOfRanks.forEach((row, ri) => {
        const rowRanks = row.cols;
        const rowH = Math.max(CARD_H, ...rowRanks.map((col, ci) => colH[row.start + ci]));
        const leftToRight = ri % 2 === 0;
        let xAcc = 0;
        const xs = rowRanks.map((_, ci) => {
          const x = xAcc; xAcc += colW[row.start + ci] + RANK_GAP; return x;
        });
        rowRanks.forEach((col, ci) => {
          const slot = leftToRight ? ci : (rowRanks.length - 1 - ci);
          const x = xs[slot];
          const h = colH[row.start + ci];
          let y = rowTop + (rowH - h) / 2;
          for (const id of col) { pos.set(id, { x, y }); y += size(id).h + rowGap; }
          width = Math.max(width, x + colW[row.start + ci]);
        });
        rowTop += rowH + SERP_ROW_GAP;
      });
      height = rowTop - SERP_ROW_GAP;
    } else {
      const maxH = Math.max(CARD_H, ...colH);
      let x = 0;
      for (let r = 0; r < ranks.length; r++) {
        const col = ranks[r];
        const h = colH[r];
        let y = (maxH - h) / 2;
        for (const id of col) { pos.set(id, { x, y }); y += size(id).h + rowGap; }
        x += colW[r] + RANK_GAP;
      }
      width = Math.max(0, x - RANK_GAP);
      height = maxH;
    }
    return { pos, width, height, ranks, serpentine, rank };
  }

  /** Layout box {w,h} of a model node (all cards are uniform). */
  _boxOf(id) {
    const mn = this.model && this.model.byId && this.model.byId.get(id);
    if (mn && mn.audio) return { w: AUDIO_W, h: AUDIO_H };
    return { w: CARD_W, h: CARD_H };
  }

  // -- manual layout --------------------------------------------------------

  /**
   * Build this.layout from manualPos (manual mode's position source). Any model
   * node without a saved manual position (e.g. an expanded stub added after the
   * snapshot) falls back to its last-known layout pos, or the origin. Assembles
   * the same {pos, rank, box, ...} shape the auto path produces so draw / fit /
   * edgeAudit / layoutSanity are unchanged. No routes (manual is straight-line
   * cubic edges — the classic renderer).
   */
  _applyManualLayout() {
    const m = this.model;
    const prev = this.layout && this.layout.pos;
    const pos = new Map();
    const rank = new Map();
    let minX = Infinity, minY = Infinity, maxX = -Infinity, maxY = -Infinity;
    for (const mn of m.nodes) {
      let p = this.manualPos.get(mn.id);
      if (!p && prev && prev.has(mn.id)) p = prev.get(mn.id);
      // A freshly synthesized clone (unmerge) with no saved position: seed it at
      // its precomputed absolute spot (just below its parent), so copies spread
      // under their parents instead of crumpling onto one spot.
      if (!p && mn.cloneOf) {
        if (mn._seedPos) p = { x: mn._seedPos.x, y: mn._seedPos.y };
        else {
          const base = this.manualPos.get(mn.cloneOf) || (prev && prev.get(mn.cloneOf));
          if (base) p = { x: base.x, y: base.y };
        }
      }
      if (!p) p = { x: 0, y: 0 };
      pos.set(mn.id, { x: p.x, y: p.y, rank: 0 });
      const b = this._boxOf(mn.id);
      minX = Math.min(minX, p.x); minY = Math.min(minY, p.y);
      maxX = Math.max(maxX, p.x + b.w); maxY = Math.max(maxY, p.y + b.h);
    }
    // Pseudo-rank by x so _classifyEdge's back-edge test still works (like ELK).
    const xs = [...pos.values()].map((p) => p.x).sort((a, b) => a - b);
    const rankOfX = (x) => { let r = 0; for (const v of xs) { if (v < x - 1) r++; else break; } return r; };
    for (const [id, p] of pos) { p.rank = rankOfX(p.x); rank.set(id, p.rank); }
    if (minX === Infinity) { minX = 0; minY = 0; maxX = CARD_W; maxY = CARD_H; }
    this.layout = {
      pos, rank, manual: true,
      width: maxX - minX, height: maxY - minY,
      box: { minX, minY, maxX, maxY },
    };
  }

  /**
   * Enter manual mode: snapshot EVERY current auto-layout position into
   * manualPos and freeze auto-layout. Idempotent (no-op if already manual). The
   * first drag calls this before applying its delta.
   */
  _snapshotManual() {
    if (this.manual) return;
    this.manualPos = new Map();
    this._movedIds = new Set();
    if (this.layout) {
      for (const [id, p] of this.layout.pos) this.manualPos.set(id, { x: p.x, y: p.y });
    }
    this.manual = true;
    this._manualMoved = 0;
  }

  /** Recount user-moved nodes (the READY MANUAL:<n> value == dragged-id set). */
  _recountMoved() { this._manualMoved = this._movedIds.size; }

  /**
   * Exclusive-subtree (dominated set) of a dragged node `id`: the node plus
   * every node reachable from it that is NOT still reachable from the view root
   * when `id` is removed. Shared / reconvergence nodes (reachable another way)
   * are excluded so they stay put. If there is no view root, the whole forward
   * closure of `id` is used (nothing else to dominate against). Returns a Set of
   * ids that always contains `id`.
   */
  _dominatedSubtree(id) {
    const m = this.model;
    const ids = new Set(m.nodes.map((n) => n.id));
    const out = new Map();
    for (const nid of ids) out.set(nid, []);
    const seen = new Set();
    for (const e of m.edges) {
      if (e.from === e.to) continue;
      if (!ids.has(e.from) || !ids.has(e.to)) continue;
      const sig = e.from + '\x00' + e.to;
      if (seen.has(sig)) continue;
      seen.add(sig);
      out.get(e.from).push(e.to);
    }
    // Forward closure FROM the dragged node (candidate members).
    const fwd = new Set([id]);
    let q = [id];
    while (q.length) { const c = q.shift(); for (const t of out.get(c) || []) if (!fwd.has(t)) { fwd.add(t); q.push(t); } }

    const root = this.rootId && ids.has(this.rootId) ? this.rootId : null;
    if (!root || root === id) return fwd;

    // Reachable from root WITHOUT going through the dragged node.
    const reachSansNode = new Set([root]);
    q = [root];
    while (q.length) {
      const c = q.shift();
      for (const t of out.get(c) || []) {
        if (t === id) continue;           // remove the dragged node from the graph
        if (!reachSansNode.has(t)) { reachSansNode.add(t); q.push(t); }
      }
    }
    // Exclusive = forward-closure members the root can no longer reach.
    const dom = new Set();
    for (const nid of fwd) if (nid === id || !reachSansNode.has(nid)) dom.add(nid);
    return dom;
  }

  /** Number of nodes whose manual position differs from... always == manualPos moved set. */
  manualMovedCount() { return this.manual ? this._manualMoved : 0; }

  /**
   * Leave manual mode: discard the manual arrangement, clear the saved entry,
   * and re-run the current preset's auto-layout, then re-fit. Called by the
   * toolbar "reset to auto" and on a preset change.
   */
  resetToAuto() {
    this.manual = false;
    this.manualPos = new Map();
    this._movedIds = new Set();
    this._selBox = null;
    this._manualMoved = 0;
    // Preserve node marks: reset-to-auto discards the manual ARRANGEMENT only.
    // _saveManual rewrites the record with marks (or clears it if none remain).
    this._saveManual();
    if (this.graph) { this._rebuild(); this.fit(); }
    this.onManualChange();
  }

  /**
   * Snap-to-grid grid pitch (world units). Fixed at GRID for v1.
   */
  snapGridSize() { return GRID; }

  /**
   * Enable / disable snap-to-grid for subsequent manual drags. Persists the flag
   * in this conversation's manual record and repaints the toolbar. Does NOT move
   * any already-placed nodes (only future drags snap). Redraws so the grid
   * overlay appears / disappears immediately.
   */
  setSnap(on) {
    const next = !!on;
    if (this.snapGrid === next) return;
    this.snapGrid = next;
    this._saveManual();
    if (this.layout) this._draw();   // paint / clear the grid overlay
    this.onManualChange();
  }

  // -- manual persistence + export/import -----------------------------------

  /**
   * Persist manualPos + marks to localStorage under this conversation's key.
   * Manual positions and node marks share ONE record: `marks` sits alongside
   * `pos`/`movedIds`. If neither manual mode nor any mark is active the record
   * is cleared.
   */
  _saveManual() {
    if (!this.convKey) return;
    try {
      const hasManual = this.manual && this.manualPos.size > 0;
      const hasMarks = this.nodeMarks && this.nodeMarks.size > 0;
      // A non-default layout engine is itself worth persisting (per-dialog), even
      // with no manual arrangement / marks / snap.
      const hasLayout = this.layoutPreset && this.layoutPreset !== DEFAULT_PRESET;
      if (!hasManual && !hasMarks && !this.snapGrid && !hasLayout) { this._clearManualStore(); return; }
      // Persist the FULL frozen snapshot (for an exact restore) plus the list of
      // ids the user actually moved (for the MANUAL:<n> count on reload).
      const obj = {};
      if (hasManual) for (const [id, p] of this.manualPos) obj[id] = { x: Math.round(p.x), y: Math.round(p.y) };
      const payload = {
        manual: hasManual, moved: this._manualMoved || 0,
        movedIds: [...this._movedIds], pos: obj,
        marks: this.marksObject(),
        snapGrid: this.snapGrid,
        layoutEngine: this.layoutPreset,
      };
      localStorage.setItem(this._lsKey(), JSON.stringify(payload));
    } catch (_) { /* storage may be unavailable / full — non-fatal */ }
  }

  /**
   * Restore a saved manual arrangement AND node marks for the current
   * conversation, if any. Marks restore independently of a manual arrangement
   * (a record may carry `marks` with no `pos`), so they survive even when the
   * view was never manually dragged.
   */
  _restoreManual() {
    this._manualMoved = 0;
    this.nodeMarks = new Map();
    if (!this.manualEnabled || !this.convKey) return;
    let raw;
    try { raw = localStorage.getItem(this._lsKey()); } catch (_) { return; }
    if (!raw) return;
    let data;
    try { data = JSON.parse(raw); } catch (_) { this._clearManualStore(); return; }
    if (!data) return;
    const present = new Set(this.graph.nodes.map((n) => n.id));
    // Restore the per-dialog layout engine (back-compat: absent → keep whatever
    // the view seeded). Applied before _rebuild() so the restored graph lays out
    // with this dialog's own choice, not the view default.
    if (typeof data.layoutEngine === 'string' && PRESETS[data.layoutEngine]) {
      this.layoutPreset = data.layoutEngine;
    }
    // Restore the snap-to-grid flag (back-compat: absent → off).
    this.snapGrid = data.snapGrid === true;
    // Restore marks (back-compat: a record without `marks` simply has none).
    if (data.marks && typeof data.marks === 'object') {
      for (const id in data.marks) {
        const k = data.marks[id];
        if ((k === 'unmerge' || k === 'reference') && present.has(id)) this.nodeMarks.set(id, k);
      }
    }
    if (!data.manual || !data.pos || typeof data.pos !== 'object') return;
    const pos = new Map();
    for (const id in data.pos) {
      const p = data.pos[id];
      if (!p || typeof p.x !== 'number' || typeof p.y !== 'number') continue;
      // Guard against stale keys: only restore ids that exist in this graph —
      // BUT keep synthesized `um:`/`ref:`/`stub:` ids (unmerge clones, reference
      // links, collapsed-arm stubs). Those are created by the marks/collapse
      // transform in _rebuild(), which runs AFTER restore, so they aren't in the
      // base graph yet; dropping them here would discard a dragged clone's saved
      // position and make the clones re-pile on their seed spot every render.
      if (!present.has(id) && !/^(um|ref|stub):/.test(id)) continue;
      pos.set(id, { x: p.x, y: p.y });
    }
    if (pos.size === 0) return;
    this.manualPos = pos;
    this.manual = true;
    // Restore the moved-id set (fall back to all-present if the entry predates
    // movedIds), then recount so MANUAL:<n> matches what was saved.
    this._movedIds = new Set();
    if (Array.isArray(data.movedIds)) {
      for (const id of data.movedIds) if (present.has(id)) this._movedIds.add(id);
    } else {
      for (const id of pos.keys()) this._movedIds.add(id);
    }
    this._manualMoved = this._movedIds.size;
  }

  /** Remove this conversation's saved manual entry. */
  _clearManualStore() {
    if (!this.convKey) return;
    try { localStorage.removeItem(this._lsKey()); } catch (_) {}
  }

  /**
   * Dump the CURRENT conversation's manual layout + marks as a plain JSON object
   * keyed by conversation: { "<convKey>": { "<nodeId>": {x,y}, ..., __marks:
   * {id: 'unmerge'|'reference'} } }. The reserved `__marks` sub-key carries the
   * node marks in the SAME per-conversation record (import ignores it as a
   * position, so old importers stay compatible). Emitted whenever there are
   * moved nodes OR active marks. Reloadable via importManualLayout.
   */
  dumpManualLayout() {
    const out = {};
    if (!this.convKey) return out;
    const conv = {};
    if (this.manual && this._movedIds.size) {
      for (const id of this._movedIds) {
        const p = this.manualPos.get(id);
        if (p) conv[id] = { x: Math.round(p.x), y: Math.round(p.y) };
      }
    }
    if (this.nodeMarks && this.nodeMarks.size) conv.__marks = this.marksObject();
    if (this.snapGrid) conv.__snapGrid = true;
    if (Object.keys(conv).length) out[this.convKey] = conv;
    return out;
  }

  /**
   * Dump EVERY conversation's manual arrangement from localStorage (the whole
   * manual set), same schema as dumpManualLayout: { conv: { id: {x,y} } }.
   */
  dumpAllManualLayouts() {
    const out = {};
    let n;
    try { n = localStorage.length; } catch (_) { return out; }
    for (let i = 0; i < n; i++) {
      let k;
      try { k = localStorage.key(i); } catch (_) { continue; }
      if (!k || k.indexOf('bakDlgManual:') !== 0) continue;
      const conv = k.slice('bakDlgManual:'.length);
      let data;
      try { data = JSON.parse(localStorage.getItem(k)); } catch (_) { continue; }
      if (!data || (!data.pos && !data.marks)) continue;
      // Emit only the moved ids (same schema as dumpManualLayout); fall back to
      // the full pos map for legacy entries without a movedIds list. Marks (if
      // any) ride along under the reserved __marks sub-key.
      let c;
      if (data.pos && Array.isArray(data.movedIds)) {
        c = {};
        for (const id of data.movedIds) if (data.pos[id]) c[id] = data.pos[id];
      } else {
        c = data.pos ? { ...data.pos } : {};
      }
      if (data.marks && Object.keys(data.marks).length) c.__marks = data.marks;
      if (data.snapGrid === true) c.__snapGrid = true;
      if (Object.keys(c).length) out[conv] = c;
    }
    // Include the live (possibly-unsaved) current conversation too.
    const cur = this.dumpManualLayout();
    for (const c in cur) out[c] = cur[c];
    return out;
  }

  /**
   * Import a previously-dumped layout object ({ conv: { id: {x,y} } }). If it
   * carries an entry for the CURRENT conversation, apply it live (enter manual
   * mode, restore those positions, re-render). Also writes every conversation's
   * entry into localStorage so other conversations restore on open. Malformed
   * input is ignored (returns false).
   */
  importManualLayout(obj) {
    if (!obj || typeof obj !== 'object') return false;
    let appliedCurrent = false;
    for (const conv in obj) {
      const convPos = obj[conv];
      if (!convPos || typeof convPos !== 'object') continue;
      const clean = {};
      const movedIds = [];
      const marks = {};
      let snap = false;
      for (const id in convPos) {
        if (id === '__snapGrid') { snap = convPos.__snapGrid === true; continue; }
        if (id === '__marks') {
          // Reserved sub-key: node marks (not a position).
          const mm = convPos.__marks;
          if (mm && typeof mm === 'object') {
            for (const mid in mm) {
              if (mm[mid] === 'unmerge' || mm[mid] === 'reference') marks[mid] = mm[mid];
            }
          }
          continue;
        }
        const p = convPos[id];
        if (!p || typeof p.x !== 'number' || typeof p.y !== 'number') continue;
        clean[id] = { x: p.x, y: p.y };
        movedIds.push(id);
      }
      const hasMarks = Object.keys(marks).length > 0;
      if (movedIds.length === 0 && !hasMarks && !snap) continue;
      if (conv === this.convKey) {
        appliedCurrent = this._applyImport(clean, movedIds, marks, snap);
      } else {
        // Not the current conversation: persist the moved positions + marks + snap
        // so it restores on open. Stored as moved-only; the un-moved nodes will
        // take that conversation's fresh auto layout when next rendered.
        try {
          localStorage.setItem('bakDlgManual:' + conv,
            JSON.stringify({ manual: movedIds.length > 0, moved: movedIds.length,
              movedIds, pos: clean, marks, snapGrid: snap }));
        } catch (_) {}
      }
    }
    if (appliedCurrent) { this.onManualChange(); }
    return true;
  }

  /**
   * Apply an imported set of moved positions to the CURRENT view: lay out fresh
   * auto positions as the baseline, snapshot them, overlay the moved positions,
   * mark them moved, freeze, redraw, refit, and persist.
   */
  _applyImport(clean, movedIds, marks, snap) {
    const present = this.graph ? new Set(this.graph.nodes.map((n) => n.id)) : null;
    if (snap !== undefined) this.snapGrid = !!snap;
    // Apply imported marks first (present-guarded) so the transform + save pick
    // them up regardless of whether there are also manual positions.
    if (marks) {
      for (const mid in marks) {
        if (!present || present.has(mid)) this.nodeMarks.set(mid, marks[mid]);
      }
    }
    // Baseline: fresh auto layout so un-moved nodes have real positions.
    const wasManual = this.manual;
    this.manual = false;
    this._buildModel();
    // Synchronous classic baseline (even under an ELK preset — ELK is async and
    // import needs positions NOW; the un-moved nodes only need a sane baseline).
    this._computeLayout();
    // Marks-only import (no moved positions): re-render + persist the marks and
    // stay in auto layout.
    if (!movedIds || movedIds.length === 0) {
      this.manual = wasManual;
      this._rebuild();
      this._saveManual();
      this.fit();
      return true;
    }
    this._snapshotManual();            // manual=true, manualPos = auto snapshot
    this._movedIds = new Set();
    for (const id of movedIds) {
      if (present && !present.has(id)) continue;
      this.manualPos.set(id, clean[id]);
      this._movedIds.add(id);
    }
    if (this._movedIds.size === 0) { this.manual = wasManual; this._saveManual(); return true; }
    this._recountMoved();
    this._applyManualLayout();
    this._draw();
    this._saveManual();
    this.fit();
    return true;
  }

  // -- drawing --------------------------------------------------------------

  _draw() {
    // No layout yet (ELK placeholder is showing) — leave the placeholder be.
    if (!this.layout) return;
    this.gEdges.innerHTML = '';
    this.gNodes.innerHTML = '';
    const m = this.model;
    const pos = this.layout.pos;

    // Faint snap-to-grid overlay (world space, behind edges/nodes). Only in manual
    // mode with snap on. pointer-events:none so it never intercepts pan/drag.
    if (this.snapGrid && this.manual) this._drawGrid();

    // Collision rects (cards) for label-pill avoidance.
    const cardRects = [];
    for (const mn of m.nodes) {
      const p = pos.get(mn.id);
      if (!p) continue;
      const b = this._boxOf(mn.id);
      cardRects.push({ x: p.x, y: p.y, w: b.w, h: b.h });
    }

    // Edges + back-edge badges (classification shared with edgeAudit()).
    const backBadges = new Map();
    for (const e of m.edges) {
      const cls = this._classifyEdge(e);
      if (cls === 'noPos') continue;
      if (cls === 'badge') {
        if (!backBadges.has(e.from)) backBadges.set(e.from, []);
        const tgt = m.nodeById.get(e.to);
        backBadges.get(e.from).push({ targetId: e.to, label: this._shortWords(tgt) });
        continue;
      }
      this._drawEdge(e, cardRects);
    }

    // Nodes.
    for (const mn of m.nodes) {
      const p = pos.get(mn.id);
      if (!p) continue;
      this._drawCard(mn, p, backBadges.get(mn.id) || []);
    }

    // Manual-drag selection bounding box (dashed) around the moving subtree.
    if (this._selBox) this._drawSelBox(this._selBox);
  }

  /**
   * Faint snap-to-grid lattice behind the graph, aligned to the SAME GRID origin
   * the snap math uses (world (0,0), pitch GRID). Spans the layout box padded to
   * grid, into gEdges (below nodes). pointer-events:none — never blocks a gesture.
   */
  _drawGrid() {
    const box = this.layout && this.layout.box;
    if (!box) return;
    const PAD = GRID * 4;
    const x0 = Math.floor((box.minX - PAD) / GRID) * GRID;
    const y0 = Math.floor((box.minY - PAD) / GRID) * GRID;
    const x1 = Math.ceil((box.maxX + PAD) / GRID) * GRID;
    const y1 = Math.ceil((box.maxY + PAD) / GRID) * GRID;
    // Cap the line count so a giant layout doesn't spray thousands of lines.
    if ((x1 - x0) / GRID > 4000 || (y1 - y0) / GRID > 4000) return;
    const g = svg('g', { class: 'dlgGrid', 'pointer-events': 'none' }, this.gEdges);
    let d = '';
    for (let x = x0; x <= x1; x += GRID) d += `M${x} ${y0}V${y1}`;
    for (let y = y0; y <= y1; y += GRID) d += `M${x0} ${y}H${x1}`;
    svg('path', {
      d, fill: 'none', stroke: '#5fd6d6', 'stroke-width': 0.5,
      'stroke-opacity': 0.12, 'pointer-events': 'none',
    }, g);
  }

  /** Dashed bounding box around the currently-selected/dragging subtree. */
  _drawSelBox(b) {
    const pad = 10;
    svg('rect', {
      x: b.minX - pad, y: b.minY - pad,
      width: (b.maxX - b.minX) + 2 * pad, height: (b.maxY - b.minY) + 2 * pad,
      rx: 8, fill: 'none', stroke: '#ffd54a', 'stroke-width': 1.5,
      'stroke-dasharray': '7 5', 'stroke-opacity': 0.85, 'pointer-events': 'none',
    }, this.gNodes);
  }

  /** World-space bounding box of a set of node ids under the current layout. */
  _bboxOf(ids) {
    let minX = Infinity, minY = Infinity, maxX = -Infinity, maxY = -Infinity;
    for (const id of ids) {
      const p = this.layout.pos.get(id);
      if (!p) continue;
      const b = this._boxOf(id);
      minX = Math.min(minX, p.x); minY = Math.min(minY, p.y);
      maxX = Math.max(maxX, p.x + b.w); maxY = Math.max(maxY, p.y + b.h);
    }
    if (minX === Infinity) return null;
    return { minX, minY, maxX, maxY };
  }

  /**
   * Classify one visible model edge for the draw pass: 'drawn' | 'badge' |
   * 'noPos'. A back-edge (target rank <= source rank) draws as a ↩ badge on the
   * source card; forward edges draw as arrows.
   */
  _classifyEdge(e) {
    const pos = this.layout.pos;
    const a = pos.get(e.from);
    const b = pos.get(e.to);
    if (!a || !b) return 'noPos';
    // ELK mode: ELK routes every non-self edge as a real orthogonal path
    // (including back edges), so there is no ↩ badge conversion. Self-loops
    // (which ELK does not route) draw as a degenerate curve.
    if (this.layout.elk) return 'drawn';
    // MANUAL mode uses arbitrary user positions, so a rank-based back-edge test
    // is meaningless: draw every non-self edge as a real arrow (a self-loop
    // still becomes a ↩ badge, as in the classic path).
    if (this.layout.manual) return e.from === e.to ? 'badge' : 'drawn';
    const backEdge = (this.layout.rank.get(e.to) ?? 0) <= (this.layout.rank.get(e.from) ?? 0);
    if (backEdge && e.from !== e.to) return 'badge';
    return 'drawn';
  }

  /**
   * DEV edge audit: account for every edge. Visible model edges must classify as
   * drawn/badge (badgeDropped flags badges on nodes that can't render them — only
   * cards show ↩ badges); raw edges absent from the model are dropped (must be
   * none in a flat model). `unaccounted` must be EMPTY.
   */
  edgeAudit(detail) {
    const m = this.model;
    // Layout not yet computed (ELK worker in flight, placeholder showing): report
    // pending rather than throwing on a null layout.
    if (!this.layout) {
      return {
        pending: true, hiddenCollapsed: m.hiddenCollapsed || 0,
        fused: (this.graph.meta && this.graph.meta.fused) || 0, unaccounted: [],
      };
    }
    const out = {
      modelEdges: m.edges.length, drawn: 0, badge: 0, badgeDropped: 0,
      rawEdges: this.graph.edges.length, spliced: 0,
      hiddenCollapsed: m.hiddenCollapsed || 0,
      // Structural nodes hidden by switch FUSION in this view (consumed cascade
      // switches + swallowed/spliced empty pass-throughs) — see dialog.js
      // _fuseSwitches. Accounted here so the flat model's node math closes.
      fused: (this.graph.meta && this.graph.meta.fused) || 0,
      unaccounted: [],
    };
    if (detail) out.detail = [];
    for (const e of m.edges) {
      const cls = this._classifyEdge(e);
      let bucket = cls;
      if (cls === 'drawn') out.drawn++;
      else if (cls === 'badge') out.badge++; // every node is a card → renders ↩
      else out.unaccounted.push(['noPos', e.from, e.to]);
      if (detail) out.detail.push([bucket, e.from, e.to, e.kind, e.label]);
    }
    // Raw edges absent from the model are either (a) suppressed by a collapsed
    // arm — one endpoint is an arm-exclusive node that was removed (or the
    // switch's arm edge redirected to a stub), all counted in hiddenCollapsed —
    // or (b) a genuine drop (unaccounted). A flat model with no collapse keeps
    // every edge whose endpoints are both present.
    for (const e of this.graph.edges) {
      if (m.byId.has(e.from) && m.byId.has(e.to)) continue;
      // Endpoint removed by collapse (not a live model node) → hiddenCollapsed.
      if (this._collapsedActive
        && (!m.byId.has(e.from) || !m.byId.has(e.to))) continue;
      // Endpoint removed by an UNMERGE mark: the original shared subtree S is
      // replaced by per-parent clones, so a raw edge into/among S has no live
      // endpoint. Accounted here (the clone edges re-express it per parent).
      if (m.marked && (!m.byId.has(e.from) || !m.byId.has(e.to))) continue;
      out.unaccounted.push(['dropped', e.from, e.to]);
    }
    return out;
  }

  /**
   * DEV layout-sanity check (visual, not accounting). edgeAudit can report
   * unaccounted:0 while the view is visibly broken (arrows into empty space) —
   * this instrument catches THAT. For the current view it returns, all of which
   * must be 0 on a clean layout:
   *   danglingEdges  — drawn edges whose terminal point is not within ~12px of
   *                    the target node's rendered rect (arrows into empty space);
   *   offCanvasNodes — nodes whose rect falls outside the content bbox fit() uses;
   *   nodeOverlaps   — overlapping node rects (jumbled layout).
   * `detail` attaches the offending id lists.
   */
  layoutSanity(detail) {
    const m = this.model;
    if (!this.layout) return { pending: true, danglingEdges: 0, offCanvasNodes: 0, nodeOverlaps: 0 };
    const pos = this.layout.pos;
    const out = { danglingEdges: 0, offCanvasNodes: 0, nodeOverlaps: 0 };
    if (detail) { out.dangling = []; out.offCanvas = []; out.overlaps = []; }
    const TOL = 12;
    const rectOf = (id) => { const p = pos.get(id); if (!p) return null; const b = this._boxOf(id); return { x: p.x, y: p.y, w: b.w, h: b.h }; };

    // 1. Dangling drawn edges: terminal point must land on the target rect (+tol).
    for (const e of m.edges) {
      if (e.from === e.to) continue;
      if (this._classifyEdge(e) !== 'drawn') continue;
      const rb = rectOf(e.to);
      if (!rb) continue;
      let tx, ty;
      const route = this.layout.routes && this.layout.routes.get(e.from + '\x00' + e.to);
      if (route && route.length >= 2) { tx = route[route.length - 1].x; ty = route[route.length - 1].y; }
      else { const t = this._entryPoint(e.to, pos.get(e.to)); tx = t.x; ty = t.y; }
      const dx = Math.max(rb.x - tx, 0, tx - (rb.x + rb.w));
      const dy = Math.max(rb.y - ty, 0, ty - (rb.y + rb.h));
      if (Math.hypot(dx, dy) > TOL) { out.danglingEdges++; if (detail) out.dangling.push([e.from, e.to, Math.round(Math.hypot(dx, dy))]); }
    }

    // 2. Off-canvas nodes: node rect must lie inside the fit() content bbox.
    const box = this._contentBox();
    const bx0 = box.x, by0 = box.y, bx1 = box.x + box.w, by1 = box.y + box.h;
    for (const mn of m.nodes) {
      const r = rectOf(mn.id);
      if (!r) continue;
      if (r.x < bx0 - 1 || r.y < by0 - 1 || r.x + r.w > bx1 + 1 || r.y + r.h > by1 + 1) {
        out.offCanvasNodes++; if (detail) out.offCanvas.push(mn.id);
      }
    }

    // 3. Node overlaps.
    const rects = m.nodes.map((mn) => ({ id: mn.id, r: rectOf(mn.id) })).filter((x) => x.r);
    for (let i = 0; i < rects.length; i++) {
      for (let j = i + 1; j < rects.length; j++) {
        const a = rects[i], b = rects[j];
        if (this._rectsOverlap(a.r, b.r)) { out.nodeOverlaps++; if (detail) out.overlaps.push([a.id, b.id]); }
      }
    }
    return out;
  }

  /** Axis-aligned rect overlap test. */
  _rectsOverlap(a, b) {
    return a.x < b.x + b.w && a.x + a.w > b.x && a.y < b.y + b.h && a.y + a.h > b.y;
  }

  /** First 3 words of a node's summary, for a back-edge badge. `node` = payload. */
  _shortWords(node) {
    if (!node) return '?';
    let s = (node.firstLine || '').trim();
    if (!s) {
      const raw = this.db.nodes.get(node.id);
      if (raw) s = (this._childSummary(raw) || node.class || '').trim();
    }
    if (!s) s = node.class || '?';
    return s.split(/\s+/).slice(0, 3).join(' ');
  }

  /** First resolvable child's first-line for an empty-body raw DB node. */
  _childSummary(raw, seen) {
    const visited = seen || new Set([raw.id]);
    for (const e of this.db.outEdges(raw)) {
      if (!e.node || visited.has(e.node.id)) continue;
      visited.add(e.node.id);
      const own = this.db.firstLine(e.node, 40);
      if (own) return own;
      const deep = this._childSummary(e.node, visited);
      if (deep) return deep;
    }
    return '';
  }

  /** Attach point for an edge leaving a node (right-center of its box). */
  _exitPoint(id, p) {
    const b = this._boxOf(id);
    return { x: p.x + b.w, y: p.y + b.h / 2 };
  }

  /** Attach point for an edge entering a node (left-center of its box). */
  _entryPoint(id, p) {
    const b = this._boxOf(id);
    return { x: p.x, y: p.y + b.h / 2 };
  }

  /**
   * Border anchor on node `id`'s box facing point `toward` {x,y}, plus the
   * outward unit normal of the chosen side. Picks the side nearest the other
   * endpoint (so a dragged/back edge connects on the correct side instead of
   * always exiting right / entering left).
   */
  _anchor(id, p, toward) {
    const b = this._boxOf(id);
    const cx = p.x + b.w / 2, cy = p.y + b.h / 2;
    const dx = toward.x - cx, dy = toward.y - cy;
    const hw = b.w / 2, hh = b.h / 2;
    // Clamp the ray from the box center toward `toward` onto the box border.
    const tx = dx === 0 ? Infinity : hw / Math.abs(dx);
    const ty = dy === 0 ? Infinity : hh / Math.abs(dy);
    const s = Math.min(tx, ty);
    if (!isFinite(s)) return { x: cx + hw, y: cy, nx: 1, ny: 0 };
    const horiz = tx <= ty; // the vertical (left/right) side is hit first
    return {
      x: cx + dx * s, y: cy + dy * s,
      nx: horiz ? Math.sign(dx) || 1 : 0,
      ny: horiz ? 0 : Math.sign(dy) || 1,
    };
  }

  _drawEdge(e, cardRects) {
    const pa = this.layout.pos.get(e.from);
    const pb = this.layout.pos.get(e.to);
    const ba = this._boxOf(e.from), bb = this._boxOf(e.to);
    const ca = { x: pa.x + ba.w / 2, y: pa.y + ba.h / 2 };
    const cb = { x: pb.x + bb.w / 2, y: pb.y + bb.h / 2 };
    const s = this._anchor(e.from, pa, cb); // exit on the side facing the target
    const t = this._anchor(e.to, pb, ca);   // enter on the side facing the source
    const x1 = s.x, y1 = s.y, x2 = t.x, y2 = t.y;
    // Control points push out along each anchor's normal so the curve leaves and
    // enters perpendicular to the box side, whatever the relative positions.
    const k = Math.max(36, Math.hypot(x2 - x1, y2 - y1) / 3);
    const c1x = x1 + s.nx * k, c1y = y1 + s.ny * k;
    const c2x = x2 + t.nx * k, c2y = y2 + t.ny * k;
    // Switch-arm edges get a per-arm hue tint so parallel storylines are
    // traceable in the fully-open tree; everything else uses the kind color.
    const color = e.switchArm
      ? armHue(e.switchArm.armIndex)
      : (EDGE_COLORS[e.kind] || EDGE_COLORS.cond);

    // ELK supplies orthogonal bend-point routes; draw them as a polyline.
    // Otherwise (classic, or an ELK edge with no reported route) use the cubic.
    const route = this.layout.routes && this.layout.routes.get(e.from + '\x00' + e.to);
    let d, sampleAt;
    if (route && route.length >= 2) {
      d = 'M' + route.map((p) => `${p.x},${p.y}`).join(' L');
      // Arc-length sampler along the polyline for label placement.
      const segs = [];
      let total = 0;
      for (let i = 1; i < route.length; i++) {
        const L = Math.hypot(route[i].x - route[i - 1].x, route[i].y - route[i - 1].y);
        segs.push({ a: route[i - 1], b: route[i], L, acc: total });
        total += L;
      }
      sampleAt = (u) => {
        const target = u * total;
        for (const sg of segs) {
          if (target <= sg.acc + sg.L || sg === segs[segs.length - 1]) {
            const f = sg.L ? (target - sg.acc) / sg.L : 0;
            return [sg.a.x + (sg.b.x - sg.a.x) * f, sg.a.y + (sg.b.y - sg.a.y) * f];
          }
        }
        return [route[route.length - 1].x, route[route.length - 1].y];
      };
    } else {
      d = `M${x1},${y1} C${c1x},${c1y} ${c2x},${c2y} ${x2},${y2}`;
      sampleAt = (u) => {
        const mt = 1 - u;
        const bx = mt * mt * mt * x1 + 3 * mt * mt * u * c1x
          + 3 * mt * u * u * c2x + u * u * u * x2;
        const by = mt * mt * mt * y1 + 3 * mt * mt * u * c1y
          + 3 * mt * u * u * c2y + u * u * u * y2;
        return [bx, by];
      };
    }
    const path = svg('path', {
      d, fill: 'none', stroke: color,
      'stroke-width': 2, 'stroke-opacity': 0.65,
    }, this.gEdges);
    path.setAttribute('marker-end', 'url(#dlgArrow)');

    if (e.label) {
      const short = e.label.length > 22 ? e.label.slice(0, 21) + '…' : e.label;
      const w = short.length * 6.2 + 12;
      const h = 16;
      const bez = sampleAt;
      const clears = (cx, cy) => {
        const r = { x: cx - w / 2, y: cy - h / 2, w, h };
        for (const cr of cardRects) if (this._rectsOverlap(r, cr)) return false;
        return true;
      };
      const ts = [0.5, 0.42, 0.58, 0.34, 0.66, 0.26, 0.74];
      const dys = [0, -13, 13, -26, 26];
      let mx = (x1 + x2) / 2, my = (y1 + y2) / 2, placed = false;
      outer:
      for (const u of ts) {
        const [bx, by] = bez(u);
        for (const off of dys) {
          if (clears(bx, by + off)) { mx = bx; my = by + off; placed = true; break outer; }
        }
      }
      if (!placed) { mx = bez(0.5)[0]; my = bez(0.5)[1]; }
      // A switch-arm pill is CLICKABLE: it collapses (or, if it already targets a
      // stub, re-expands) that arm. Marked with .dlgArmPill + data attrs.
      const gAttrs = {};
      if (e.switchArm) {
        gAttrs.class = 'dlgArmPill';
        gAttrs['data-state'] = e.switchArm.stateNodeId;
        gAttrs['data-arm'] = String(e.switchArm.armIndex);
      }
      const g = svg('g', gAttrs, this.gEdges);
      if (e.switchArm) g.style.cursor = 'pointer';
      svg('rect', {
        x: mx - w / 2, y: my - 9, width: w, height: 16, rx: 8,
        fill: '#1a1c20', stroke: color,
        'stroke-opacity': e.switchArm ? 0.95 : 0.7,
        'stroke-width': e.switchArm ? 1.5 : 1,
      }, g);
      const tx = svg('text', {
        x: mx, y: my + 3, 'text-anchor': 'middle', 'font-size': 10,
        fill: color, 'font-family': 'ui-monospace, monospace',
      }, g);
      tx.textContent = short;
    }
  }

  /**
   * Compact chip for an audio-only node: a small pill with a ♪ (music) / ∿ (sfx)
   * glyph + the track/effect id. Clickable & selectable like a normal card.
   */
  _drawAudioNode(mn, p) {
    const node = mn.node;
    const kind = mn.audio;
    const raw = this.db.nodes.get(mn.cloneOf || node.id);
    const a = raw && raw.ops.find((o) => o.op === 11 || o.op === 12);
    const accent = kind === 'music' ? '#a98bff' : '#4fd1c5';
    const label = `${kind === 'music' ? '♪' : '∿'} ${a ? a.a1 : ''}`.trim();
    const selected = node.id === this.selectedId;
    const g = svg('g', {
      class: 'dlgCard', transform: `translate(${p.x},${p.y})`, 'data-id': node.id,
    }, this.gNodes);
    g.style.cursor = 'pointer';
    const rectAttrs = {
      x: 0, y: 0, width: AUDIO_W, height: AUDIO_H, rx: AUDIO_H / 2,
      fill: '#20232a', stroke: selected ? '#ffd54a' : accent,
      'stroke-width': selected ? 2 : 1.5,
    };
    if (mn.clone && !selected) rectAttrs['stroke-dasharray'] = '5 3';
    svg('rect', rectAttrs, g);
    const t = svg('text', {
      x: AUDIO_W / 2, y: AUDIO_H / 2 + 4, 'text-anchor': 'middle',
      'font-size': 12, fill: accent, 'font-family': 'ui-monospace, monospace',
    }, g);
    t.textContent = label;
    this._drawGhosts(node, p);
  }

  _drawCard(mn, p, backBadges) {
    const node = mn.node;
    if (mn.kind === 'stub') { this._drawStub(mn, p); return; }
    if (mn.kind === 'ref') { this._drawRefLink(mn, p); return; }
    if (mn.audio) { this._drawAudioNode(mn, p); return; }
    const cc = classColor(node.class);
    const g = svg('g', {
      class: 'dlgCard', transform: `translate(${p.x},${p.y})`,
      'data-id': node.id,
    }, this.gNodes);
    g.style.cursor = 'pointer';

    const selected = node.id === this.selectedId;
    // A node marked unmerge/reference gets a colored border; an unmerge CLONE
    // (a per-parent copy) gets a dashed teal border + a ⧉ badge for legibility.
    const mark = this.nodeMarks && this.nodeMarks.get(mn.cloneOf || node.id);
    const isClone = !!mn.clone;
    const markStroke = mark === 'unmerge' ? '#f2b134' : (mark === 'reference' ? '#c79bff' : null);
    const cardH = CARD_H;
    const borderStroke = selected ? '#ffd54a'
      : (isClone ? '#5fd6d6' : (markStroke || '#14161a'));
    const rectAttrs = {
      x: 0, y: 0, width: CARD_W, height: cardH, rx: 7,
      fill: '#24272e', stroke: borderStroke,
      'stroke-width': (selected || markStroke || isClone) ? 2 : 1,
    };
    if (isClone && !selected) rectAttrs['stroke-dasharray'] = '5 3';
    svg('rect', rectAttrs, g);
    if (isClone || markStroke) {
      const badge = isClone ? '⧉' : (mark === 'unmerge' ? '⧉ unmerge' : '⟿ ref');
      const bw = badge.length * 5.6 + 10;
      const bg = svg('g', {}, g);
      svg('rect', {
        x: CARD_W - bw - 4, y: -8, width: bw, height: 13, rx: 6,
        fill: '#14161a', stroke: isClone ? '#5fd6d6' : markStroke,
        'stroke-width': 1, 'stroke-opacity': 0.9,
      }, bg);
      const bt = svg('text', {
        x: CARD_W - bw / 2 - 4, y: 2, 'text-anchor': 'middle',
        'font-size': 9, fill: isClone ? '#5fd6d6' : markStroke,
        'font-family': 'ui-monospace, monospace',
      }, bg);
      bt.textContent = badge;
    }
    svg('rect', { x: 4, y: 0, width: CARD_W - 4, height: 18, rx: 5, fill: cc.head }, g);
    svg('rect', { x: 4, y: 8, width: CARD_W - 4, height: 10, fill: cc.head }, g);
    svg('rect', { x: 0, y: 0, width: 4, height: cardH, rx: 2, fill: cc.accent }, g);

    const hdr = svg('text', {
      x: 10, y: 13, 'font-size': 10, fill: cc.accent,
      'font-family': 'ui-monospace, monospace',
    }, g);
    // A switch node titles as '⑃ <stateName>?' (e.g. '⑃ chapter?'); everything
    // else keeps the 'class · key' header.
    if (node.switch) {
      hdr.textContent = `⑃ ${node.switch.stateName}?`;
    } else {
      hdr.textContent = node.key !== null ? `${node.class} · ${node.key}` : `${node.class} · ${node.id}`;
    }

    let body = node.firstLine;
    if (!body) {
      const raw = this.db.nodes.get(node.id);
      const borrowed = raw && this._childSummary(raw);
      body = borrowed ? `→ ${borrowed}` : `(${node.class})`;
    }
    const lines = wrap(body, 34, 2);
    for (let i = 0; i < lines.length; i++) {
      const t = svg('text', {
        x: 10, y: 33 + i * 12, 'font-size': 11, fill: '#d6dae0',
        'font-family': 'ui-monospace, monospace',
      }, g);
      t.textContent = lines[i];
    }

    // Footer badges: speaker, ops, shared, end.
    const foot = [];
    const spk = node.speaker;
    if (spk && spk !== 'narrator') foot.push({ text: spk, cls: 'spk' });
    const dbNode = this.db.nodes.get(node.id);
    if (node.shared) {
      const n = dbNode ? dbNode.inDegree : 2;
      foot.push({ text: `shared x${n}`, cls: 'shared' });
    }
    if (dbNode) {
      const opStrs = dbNode.ops.filter((o) => o.op !== 0 && o.op !== 6 && o.op !== 21)
        .map((o) => this.db.describeOp(o));
      const endOp = dbNode.ops.find((o) => o.op === 21);
      const shown = opStrs.slice(0, 2);
      let ops = shown.join(' · ');
      if (opStrs.length > 2) ops += ` +${opStrs.length - 2}`;
      if (ops) foot.push({ text: ops, cls: 'op' });
      if (endOp) foot.push({ text: `⏹ end ${endOp.a1}`, cls: 'end' });
    }
    let fx = 10;
    const fy = 58;
    for (const f of foot) {
      const label = f.text.length > 26 ? f.text.slice(0, 25) + '…' : f.text;
      const t = svg('text', {
        x: fx, y: fy, 'font-size': 9,
        fill: f.cls === 'end' ? '#ff8a6b' : (f.cls === 'shared' ? '#ffd54a' : '#8b93a0'),
        'font-family': 'ui-monospace, monospace',
      }, g);
      t.textContent = label;
      fx += label.length * 5.4 + 8;
      if (fx > CARD_W - 20) break;
    }

    // Back-edge return badges (top-right of the card).
    let by = -6;
    for (const bb of backBadges.slice(0, 2)) {
      const label = `↩ ${bb.label}`;
      const shortL = label.length > 16 ? label.slice(0, 15) + '…' : label;
      const w = shortL.length * 5.6 + 10;
      const bg = svg('g', { class: 'dlgBack', 'data-target': bb.targetId }, g);
      bg.style.cursor = 'pointer';
      svg('rect', {
        x: CARD_W - w - 4, y: by, width: w, height: 14, rx: 7,
        fill: '#173a3a', stroke: '#5fd6d6', 'stroke-width': 1, 'stroke-opacity': 0.8,
      }, bg);
      const t = svg('text', {
        x: CARD_W - w / 2 - 4, y: by + 10, 'text-anchor': 'middle',
        'font-size': 9, fill: '#5fd6d6', 'font-family': 'ui-monospace, monospace',
      }, bg);
      t.textContent = shortL;
      by += 17;
    }

    this._drawGhosts(node, p);
  }

  /**
   * A collapsed-arm STUB card: dashed, arm-tinted, showing the arm label + the
   * hidden node count. Clicking (or its inbound arm pill) re-expands the arm.
   * Carries .dlgStub + data attrs so the click handler routes to
   * toggleArmCollapse.
   */
  _drawStub(mn, p) {
    const node = mn.node;
    const hue = armHue(node.armIndex);
    const g = svg('g', {
      class: 'dlgStub', transform: `translate(${p.x},${p.y})`,
      'data-state': node.stateNodeId, 'data-arm': String(node.armIndex),
    }, this.gNodes);
    g.style.cursor = 'pointer';
    svg('rect', {
      x: 0, y: 0, width: CARD_W, height: CARD_H, rx: 7,
      fill: '#1e2128', stroke: hue, 'stroke-width': 1.5,
      'stroke-dasharray': '6 4', 'stroke-opacity': 0.9,
    }, g);
    svg('rect', { x: 0, y: 0, width: 4, height: CARD_H, rx: 2, fill: hue }, g);
    const hdr = svg('text', {
      x: 12, y: 20, 'font-size': 11, fill: hue,
      'font-family': 'ui-monospace, monospace', 'font-weight': 'bold',
    }, g);
    hdr.textContent = `⊕ ${node.armLabel}`;
    const lines = wrap(`${node.hiddenCount} node${node.hiddenCount === 1 ? '' : 's'} collapsed`, 30, 1);
    const b1 = svg('text', {
      x: 12, y: 40, 'font-size': 11, fill: '#d6dae0',
      'font-family': 'ui-monospace, monospace',
    }, g);
    b1.textContent = lines[0];
    const b2 = svg('text', {
      x: 12, y: 54, 'font-size': 9, fill: '#8b93a0',
      'font-family': 'ui-monospace, monospace',
    }, g);
    b2.textContent = 'click to expand';
  }

  /**
   * A REFERENCE link marker (from a 'reference'-marked merge). A small dashed
   * card (reuses the ghost visual) titled with the real target C; clicking it
   * pans to / selects the real detached C block. Carries .dlgRef + data-ref.
   */
  _drawRefLink(mn, p) {
    const target = mn.refTarget;
    const label = `⟿ ${mn.refLabel || target}`;
    const shortL = label.length > 30 ? label.slice(0, 29) + '…' : label;
    const g = svg('g', {
      class: 'dlgRef', transform: `translate(${p.x},${p.y})`,
      'data-ref': target,
    }, this.gNodes);
    g.style.cursor = 'pointer';
    svg('rect', {
      x: 0, y: 0, width: CARD_W, height: CARD_H, rx: 7,
      fill: '#1e1a26', stroke: '#c79bff', 'stroke-width': 1.5,
      'stroke-dasharray': '6 4', 'stroke-opacity': 0.9,
    }, g);
    svg('rect', { x: 0, y: 0, width: 4, height: CARD_H, rx: 2, fill: '#c79bff' }, g);
    const hdr = svg('text', {
      x: 12, y: 20, 'font-size': 11, fill: '#c79bff',
      'font-family': 'ui-monospace, monospace', 'font-weight': 'bold',
    }, g);
    hdr.textContent = 'reference →';
    const lines = wrap(shortL, 30, 2);
    for (let i = 0; i < lines.length; i++) {
      const t = svg('text', {
        x: 12, y: 38 + i * 13, 'font-size': 11, fill: '#d6dae0',
        'font-family': 'ui-monospace, monospace',
      }, g);
      t.textContent = lines[i];
    }
  }

  /**
   * Ghost link cards for out-of-graph targets: a dashed stub for each real
   * out-edge whose target is not present in the current graph (cross-component /
   * bit-31 entry jump). Double-click navigates to it.
   */
  _drawGhosts(node, p) {
    const dbNode = this.db.nodes.get(node.id);
    if (!dbNode) return;
    const present = new Set(this.graph.nodes.map((n) => n.id));
    const hidden = (this.graph.meta && this.graph.meta.hiddenIds) || new Set();
    const ghosts = [];
    for (const e of this.db.outEdges(dbNode)) {
      if (!e.node) continue;
      if (present.has(e.node.id)) continue;
      // A raw edge into a fusion-consumed structural node is represented by the
      // host's fused arm edge — no ghost stub for it.
      if (hidden.has(e.node.id)) continue;
      ghosts.push(e.node);
    }
    if (!ghosts.length) return;
    let gy = p.y + this._boxOf(node.id).h + 6;
    const gx = p.x + CARD_W + 20;
    for (const t of ghosts.slice(0, 3)) {
      const label = `→ ${t.key !== null ? t.key : t.id} ${this.db.firstLine(t, 18)}`;
      const shortL = label.length > 30 ? label.slice(0, 29) + '…' : label;
      const w = 200;
      const g = svg('g', {
        class: 'dlgGhost', transform: `translate(${gx},${gy})`,
        'data-target': t.id,
      }, this.gNodes);
      g.style.cursor = 'pointer';
      svg('rect', {
        x: 0, y: 0, width: w, height: 22, rx: 5, fill: '#1e2128',
        stroke: '#556', 'stroke-width': 1, 'stroke-dasharray': '4 3',
      }, g);
      const tx = svg('text', {
        x: 8, y: 15, 'font-size': 10, fill: '#8b93a0',
        'font-family': 'ui-monospace, monospace',
      }, g);
      tx.textContent = shortL;
      svg('path', {
        d: `M${p.x + CARD_W},${p.y + CARD_H / 2} L${gx},${gy + 11}`,
        stroke: '#556', 'stroke-width': 1, 'stroke-dasharray': '4 3', fill: 'none',
      }, this.gEdges);
      gy += 28;
    }
  }

  // -- transform / fit ------------------------------------------------------

  _applyTransform() {
    this.gRoot.setAttribute('transform',
      `translate(${this.tx},${this.ty}) scale(${this.scale})`);
  }

  /**
   * Frame the whole graph: scale so the content bounding box fills ~90% of the
   * viewport, centered. Max zoom is clamped so a card never balloons past
   * MAX_CARD_SCREEN_W on screen. Runs after every layout/navigation.
   */
  fit() {
    if (!this.layout) return;
    const rect = this.svg.getBoundingClientRect();
    const fullW = rect.width || 1000;
    const vh = rect.height || 700;
    const inset = Math.min(this.rightInset || 0, fullW * 0.5);
    const vw = fullW - inset;
    const box = this._contentBox();
    const fillW = vw * 0.9;
    const fillH = vh * 0.9;
    const maxScale = MAX_CARD_SCREEN_W / CARD_W;
    let s = Math.min(fillW / box.w, fillH / box.h, maxScale);
    if (!(s > 0) || !isFinite(s)) s = 1;
    this.scale = s;
    this.tx = (vw - box.w * s) / 2 - box.x * s;
    this.ty = (vh - box.h * s) / 2 - box.y * s;
    this._applyTransform();
  }

  /**
   * World-space bounding box of everything drawn: node boxes plus the ghost/back
   * overhang.
   */
  _contentBox() {
    let minX = Infinity, minY = Infinity, maxX = -Infinity, maxY = -Infinity;
    const m = this.model;
    for (const mn of m.nodes) {
      const p = this.layout.pos.get(mn.id);
      if (!p) continue;
      const b = this._boxOf(mn.id);
      minX = Math.min(minX, p.x);
      minY = Math.min(minY, p.y);
      maxX = Math.max(maxX, p.x + b.w);
      maxY = Math.max(maxY, p.y + b.h);
      const raw = this.db.nodes.get(mn.id);
      if (raw && mn.kind === 'card') {
        const hidden = (this.graph.meta && this.graph.meta.hiddenIds) || new Set();
        let ghosts = 0;
        for (const e of this.db.outEdges(raw)) {
          if (e.node && !this.model.byId.has(e.node.id) && !hidden.has(e.node.id)) ghosts++;
        }
        if (ghosts) {
          maxX = Math.max(maxX, p.x + CARD_W + 20 + 200);
          maxY = Math.max(maxY, p.y + CARD_H + 6 + Math.min(ghosts, 3) * 28);
        }
      }
    }
    if (minX === Infinity) { minX = 0; minY = 0; maxX = CARD_W; maxY = CARD_H; }
    const mrg = 24;
    return { x: minX - mrg, y: minY - mrg, w: (maxX - minX) + 2 * mrg, h: (maxY - minY) + 2 * mrg };
  }

  zoomBy(factor, cx, cy) {
    const rect = this.svg.getBoundingClientRect();
    const px = cx === undefined ? rect.width / 2 : cx - rect.left;
    const py = cy === undefined ? rect.height / 2 : cy - rect.top;
    const wx = (px - this.tx) / this.scale;
    const wy = (py - this.ty) / this.scale;
    this.scale = Math.max(0.08, Math.min(4, this.scale * factor));
    this.tx = px - wx * this.scale;
    this.ty = py - wy * this.scale;
    this._applyTransform();
  }

  setSelected(id) {
    // Selecting a different card clears the drag bounding box.
    if (id !== this.selectedId) this._selBox = null;
    this.selectedId = id;
    this._draw();
  }

  /**
   * Pan (keeping scale) so a node's card is centered — but ONLY if the card is
   * not already fully on screen. Preserves fit()'s framing for small views.
   */
  centerOn(id, force = false) {
    if (!this.layout) return;
    const p = this.layout.pos.get(id);
    if (!p) return;
    const b = this._boxOf(id);
    const rect = this.svg.getBoundingClientRect();
    const sx = p.x * this.scale + this.tx;
    const sy = p.y * this.scale + this.ty;
    const sw = b.w * this.scale;
    const sh = b.h * this.scale;
    const margin = 12;
    const visible = sx >= margin && sy >= margin
      && sx + sw <= rect.width - margin && sy + sh <= rect.height - margin;
    // `force` (explicit navigation, e.g. clicking a target link) always recenters;
    // otherwise leave an already-visible node where it is to avoid a jarring jump.
    if (visible && !force) return;
    const cx = p.x + b.w / 2;
    const cy = p.y + b.h / 2;
    this.tx = rect.width / 2 - cx * this.scale;
    this.ty = rect.height / 2 - cy * this.scale;
    this._applyTransform();
  }

  // -- pointer --------------------------------------------------------------

  _wirePointer() {
    // Three gestures, disambiguated at pointerdown / first-move:
    //   - pointerdown on a CARD (left button) + move past THRESH  -> move its
    //     exclusive subtree (flips to manual on the first such drag);
    //   - pointerdown on EMPTY canvas + move                      -> pan;
    //   - pointerdown + release without moving past THRESH        -> click.
    const THRESH = 4;         // px (screen) before a press becomes a drag
    let panning = false;      // background pan in progress
    let last = null;          // last pointer pos (pan)
    let downAt = null;        // pointerdown screen pos (click threshold)
    // Node-drag state.
    let nodeDown = null;      // { id, sx, sy, subtree:Set, base:Map(id->{x,y}) }
    let nodeDragging = false; // node drag has crossed THRESH
    let rafPending = false;   // pointermove redraw coalescing
    // Multi-touch pinch-zoom: track every active pointer; two down = pinch.
    const pointers = new Map(); // pointerId -> {x,y} (screen)
    let pinch = null;           // { startDist, startScale, worldX, worldY }
    const dist2 = (a, b) => Math.hypot(a.x - b.x, a.y - b.y);
    const beginPinch = () => {
      const pts = [...pointers.values()];
      if (pts.length < 2) return;
      const rect = this.svg.getBoundingClientRect();
      const midX = (pts[0].x + pts[1].x) / 2 - rect.left;
      const midY = (pts[0].y + pts[1].y) / 2 - rect.top;
      pinch = {
        startDist: dist2(pts[0], pts[1]) || 1,
        startScale: this.scale,
        worldX: (midX - this.tx) / this.scale,
        worldY: (midY - this.ty) / this.scale,
      };
    };

    this.svg.addEventListener('pointerdown', (e) => {
      downAt = [e.clientX, e.clientY];
      pointers.set(e.pointerId, { x: e.clientX, y: e.clientY });
      if (pointers.size >= 2) {
        // Second finger down -> pinch-zoom; abandon any pan/node drag in flight.
        panning = false; nodeDown = null; nodeDragging = false;
        this.svg.style.cursor = '';
        beginPinch();
        return;
      }
      // Only a plain card is draggable (not ghost/back/arm-pill/stub — those are
      // click actions). Right/middle buttons never drag a node.
      const card = e.target.closest && e.target.closest('.dlgCard');
      const otherHit = e.target.closest
        && e.target.closest('.dlgGhost, .dlgBack, .dlgArmPill, .dlgStub, .dlgRef');
      if (this.manualEnabled && card && !otherHit && e.button === 0
        && this.layout && this.layout.pos.has(card.dataset.id)) {
        nodeDown = { id: card.dataset.id, sx: e.clientX, sy: e.clientY };
        nodeDragging = false;
        this.svg.setPointerCapture(e.pointerId);
        return;
      }
      if (card || otherHit) return;   // click gesture on a hit element -> pan skip
      panning = true;
      last = [e.clientX, e.clientY];
      this.svg.style.cursor = 'grabbing';
      this.svg.setPointerCapture(e.pointerId);
    });

    this.svg.addEventListener('pointermove', (e) => {
      if (pointers.has(e.pointerId)) pointers.set(e.pointerId, { x: e.clientX, y: e.clientY });
      if (pinch) {
        const pts = [...pointers.values()];
        if (pts.length >= 2) {
          const rect = this.svg.getBoundingClientRect();
          const midX = (pts[0].x + pts[1].x) / 2 - rect.left;
          const midY = (pts[0].y + pts[1].y) / 2 - rect.top;
          const d = dist2(pts[0], pts[1]) || 1;
          this.scale = Math.max(0.08, Math.min(4, pinch.startScale * d / pinch.startDist));
          this.tx = midX - pinch.worldX * this.scale;
          this.ty = midY - pinch.worldY * this.scale;
          this._applyTransform();
        }
        return;
      }
      if (nodeDown) {
        const ddx = e.clientX - nodeDown.sx;
        const ddy = e.clientY - nodeDown.sy;
        if (!nodeDragging) {
          if (Math.abs(ddx) + Math.abs(ddy) <= THRESH) return;
          // Crossed the threshold: begin the subtree drag. Flip to manual on the
          // FIRST drag (snapshots every node's current position + freezes auto).
          this._snapshotManual();
          // Ensure layout reflects the frozen positions before computing subtree.
          if (!this.layout || !this.layout.manual) this._applyManualLayout();
          const subtree = this._dominatedSubtree(nodeDown.id);
          const base = new Map();
          for (const id of subtree) {
            const p = this.layout.pos.get(id);
            if (p) base.set(id, { x: p.x, y: p.y });
          }
          nodeDown.subtree = subtree;
          nodeDown.base = base;
          nodeDragging = true;
          this.svg.style.cursor = 'grabbing';
          this.onManualChange();     // repaint the toolbar chip / READY
        }
        // Translate every subtree member by the world-space delta.
        let wdx = ddx / this.scale;
        let wdy = ddy / this.scale;
        // Snap to grid (CENTER-based): move the whole subtree by the delta that
        // lands the DRAGGED anchor node's center on the nearest grid intersection,
        // so relative arrangement of the subtree is preserved.
        if (this.snapGrid) {
          const a = nodeDown.base.get(nodeDown.id);   // anchor start pos
          const bx = this._boxOf(nodeDown.id);        // anchor size (per-node)
          const cx = a.x + bx.w / 2 + wdx;            // anchor center after raw move
          const cy = a.y + bx.h / 2 + wdy;
          wdx = Math.round(cx / GRID) * GRID - (a.x + bx.w / 2);
          wdy = Math.round(cy / GRID) * GRID - (a.y + bx.h / 2);
        }
        for (const [id, b] of nodeDown.base) {
          const p = this.layout.pos.get(id);
          if (p) { p.x = b.x + wdx; p.y = b.y + wdy; }
        }
        this._selBox = this._bboxOf(nodeDown.subtree);
        if (!rafPending) {
          rafPending = true;
          requestAnimationFrame(() => { rafPending = false; this._draw(); });
        }
        return;
      }
      if (!panning) return;
      this.tx += e.clientX - last[0];
      this.ty += e.clientY - last[1];
      last = [e.clientX, e.clientY];
      this._applyTransform();
    });

    const endDrag = (e) => {
      pointers.delete(e.pointerId);
      if (pinch && pointers.size < 2) pinch = null; // last-but-one finger up -> end pinch
      if (nodeDown) {
        if (nodeDragging) {
          // Commit the moved subtree into manualPos + persist. Record the
          // subtree ids as user-moved (the dump basis / MANUAL:<n> count).
          for (const id of nodeDown.subtree) {
            const p = this.layout.pos.get(id);
            if (p) this.manualPos.set(id, { x: p.x, y: p.y });
            this._movedIds.add(id);
          }
          this._recountMoved();
          this._selBox = this._bboxOf(nodeDown.subtree);   // keep box on the selection
          this._draw();
          this._saveManual();
          this.onManualChange();
        } else {
          // A tap on a draggable card (no drag): SELECT it here. In manual mode
          // the card captured the pointer on pointerdown, which retargets the
          // trailing `click` to the <svg> — so the click handler's .dlgCard
          // hit-test misses. Do the selection the click handler would have done.
          this.onSelect(nodeDown.id);
        }
        try { this.svg.releasePointerCapture(e.pointerId); } catch (_) {}
        nodeDown = null; nodeDragging = false;
        this.svg.style.cursor = 'grab';
        return;
      }
      if (panning) {
        panning = false;
        this.svg.style.cursor = 'grab';
        try { this.svg.releasePointerCapture(e.pointerId); } catch (_) {}
      }
    };
    this.svg.addEventListener('pointerup', endDrag);
    this.svg.addEventListener('pointercancel', endDrag);

    this.svg.addEventListener('wheel', (e) => {
      e.preventDefault();
      const f = e.deltaY < 0 ? (e.ctrlKey ? 1.08 : 1.12) : (e.ctrlKey ? 0.93 : 0.89);
      this.zoomBy(f, e.clientX, e.clientY);
    }, { passive: false });

    // Safari reports pinch as native gesture* events (macOS trackpad AND iOS
    // touch), NOT ctrl+wheel like Chrome, and iOS ignores `touch-action:none`
    // for page pinch-zoom — so a pinch over the graph would zoom the whole PAGE
    // under our custom zoom. Swallow the native gesture. On a touchscreen the
    // two-finger pointer pinch (above) already drives the zoom, so only act on
    // the gesture when there aren't two live pointers (the macOS-trackpad case).
    let gestureStartScale = 1;
    this.svg.addEventListener('gesturestart', (e) => {
      e.preventDefault();
      gestureStartScale = this.scale;
    }, { passive: false });
    this.svg.addEventListener('gesturechange', (e) => {
      e.preventDefault();
      if (pointers.size >= 2) return; // touch pinch already handling it
      const target = Math.max(0.08, Math.min(4, gestureStartScale * e.scale));
      this.zoomBy(target / this.scale, e.clientX, e.clientY);
    }, { passive: false });
    this.svg.addEventListener('gestureend', (e) => e.preventDefault(), { passive: false });

    this.svg.addEventListener('click', (e) => {
      if (downAt && Math.abs(e.clientX - downAt[0]) + Math.abs(e.clientY - downAt[1]) > 4) return;
      // A switch-arm pill collapses its arm; a stub card re-expands it.
      const pill = e.target.closest && e.target.closest('.dlgArmPill');
      if (pill) {
        this.toggleArmCollapse(pill.dataset.state, parseInt(pill.dataset.arm, 10));
        return;
      }
      const stub = e.target.closest && e.target.closest('.dlgStub');
      if (stub) {
        this.toggleArmCollapse(stub.dataset.state, parseInt(stub.dataset.arm, 10));
        return;
      }
      const ref = e.target.closest && e.target.closest('.dlgRef');
      if (ref) {
        // A reference LINK pans/selects the real (detached) C block.
        const t = ref.dataset.ref;
        this.centerOn(t);
        this.onSelect(t);
        return;
      }
      const back = e.target.closest && e.target.closest('.dlgBack');
      if (back) { this.onNavigate(back.dataset.target); return; }
      // An out-of-view ghost link: 1st click SELECTS its target for inspection
      // in place (it isn't a card in this view); a quick 2nd click on the SAME
      // ghost drills in. Done manually (not via the native dblclick) and keyed
      // by target id, because the 1st click's selection redraw replaces the
      // ghost element — which suppresses the browser's dblclick event.
      const ghost = e.target.closest && e.target.closest('.dlgGhost');
      if (ghost) {
        const tgt = ghost.dataset.target;
        const lg = this._lastGhostClick;
        if (lg && lg.tgt === tgt && e.timeStamp - lg.t < 400) {
          this._lastGhostClick = null;
          this.onNavigate(tgt);
        } else {
          this._lastGhostClick = { tgt, t: e.timeStamp };
          this.onSelect(tgt);
        }
        return;
      }
      const card = e.target.closest && e.target.closest('.dlgCard');
      if (card) { this.onSelect(card.dataset.id); return; }
    });
    this.svg.addEventListener('dblclick', (e) => {
      // Double-click on an out-of-view ghost stub / back badge DRILLS IN.
      const ghost = e.target.closest && e.target.closest('.dlgGhost');
      if (ghost) { this.onNavigate(ghost.dataset.target); return; }
      const back = e.target.closest && e.target.closest('.dlgBack');
      if (back) { this.onNavigate(back.dataset.target); return; }
    });

    const defs = svg('defs', {}, this.svg);
    const mk = svg('marker', {
      id: 'dlgArrow', viewBox: '0 0 8 8', refX: 7, refY: 4,
      markerWidth: 6, markerHeight: 6, orient: 'auto-start-reverse',
    }, defs);
    svg('path', { d: 'M0,0 L8,4 L0,8 Z', fill: '#8b93a0', 'fill-opacity': 0.7 }, mk);
  }
}

/** Truncate a string with an ellipsis. */
function short(s, n) {
  s = String(s || '');
  return s.length > n ? s.slice(0, n - 1) + '…' : s;
}

/** Word-wrap a string to at most `maxLines` lines of ~`width` chars, ellipsized. */
function wrap(s, width, maxLines) {
  const words = s.split(/\s+/);
  const lines = [];
  let cur = '';
  for (const w of words) {
    if (!cur) { cur = w; continue; }
    if ((cur + ' ' + w).length <= width) cur += ' ' + w;
    else { lines.push(cur); cur = w; if (lines.length === maxLines) break; }
  }
  if (lines.length < maxLines && cur) lines.push(cur);
  if (lines.length === maxLines) {
    const consumed = lines.join(' ').length;
    if (consumed < s.length - 1) {
      let last = lines[maxLines - 1];
      if (last.length > width - 1) last = last.slice(0, width - 1);
      lines[maxLines - 1] = last + '…';
    }
  }
  return lines.length ? lines : [''];
}
