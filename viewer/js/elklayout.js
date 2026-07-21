// ELK (Eclipse Layout Kernel) layout backend for the dialog graph — an
// alternative to dialoggraph.js's hand-rolled layered layout, behind a runtime
// toggle. Same render MODEL in, same `layout` shape out, so the draw pass /
// edgeAudit / interaction are untouched; only node coordinates and edge geometry
// change.
//
// elkjs (jsdelivr CDN, elkjs@0.12.0/lib/elk.bundled.js) is a UMD bundle that
// installs a global `ELK` constructor. The viewer is ES modules, so we lazily
// inject it via a <script> tag once (with SRI integrity), then `new
// window.ELK()`. No WASM build of elkjs exists; the bundled JS variant is the
// right one. (EPL-2.0 OR GPL-3.0.)
//
// GRAPH MAPPING: the render model is FLAT — every model node becomes a plain
// top-level ELK node (sized by the caller's _boxOf), every model edge a plain
// ELK edge between node ids. There are NO compounds (no switch clusters, no
// lanes), so ELK just runs an ordinary layered pass and cross-hierarchy routing
// / elkjs #159 do not arise. Self-loops (drawn as a degenerate curve) are skipped.

let _elkPromise = null;   // resolves to a shared ELK instance (bundle loaded once)

// SRI hash for elkjs@0.12.0/lib/elk.bundled.js on jsdelivr (sha384).
const ELK_CDN = 'https://cdn.jsdelivr.net/npm/elkjs@0.12.0/lib/elk.bundled.js';
const ELK_SRI = 'sha384-ww57TDqx4cGknIavPm0QKO+aygLUR1BLSn2Vhbnt1XdYKWcwLyWTFKX7aZMaKIi2';
// The worker build runs the (multi-second, at giant-component scale) layout off
// the UI thread so pan/zoom stays responsive while it computes. elk.bundled.js
// installs a web-worker-compatible entry point that `new ELK({workerUrl})` uses.
const ELK_WORKER = 'https://cdn.jsdelivr.net/npm/elkjs@0.12.0/lib/elk-worker.min.js';

/**
 * Inject the UMD bundle once, then construct one shared ELK instance backed by a
 * web worker (workerUrl) so layout does not block the UI thread. If worker
 * construction throws, fall back to a main-thread instance.
 */
export function loadElk(base = ELK_CDN) {
  if (_elkPromise) return _elkPromise;
  _elkPromise = new Promise((resolve, reject) => {
    const construct = () => {
      if (!window.ELK) { reject(new Error('elk.bundled.js loaded but window.ELK is undefined')); return; }
      try {
        resolve(new window.ELK({ workerUrl: ELK_WORKER }));
      } catch (err) {
        console.warn('ELK worker unavailable; using main-thread layout:', err && err.message);
        resolve(new window.ELK());
      }
    };
    if (window.ELK) { construct(); return; }
    const s = document.createElement('script');
    s.src = base;
    if (base === ELK_CDN) { s.integrity = ELK_SRI; s.crossOrigin = 'anonymous'; }
    s.onload = construct;
    s.onerror = () => reject(new Error('failed to load ' + base));
    document.head.appendChild(s);
  });
  return _elkPromise;
}

// Spacing tuned to roughly match the classic layout's visual density
// (RANK_GAP 130 between columns, ROW_GAP 26 between stacked cards).
// `layered` keeps the left-to-right conversational flow; MULTI_EDGE graph
// wrapping folds the wide DAG into a compact block, and a LOW target
// aspectRatio (0.7) forces enough
// wrap cuts that the RENDERED aspect lands ~1.6:1 (Phillip 390) / ~2.7:1 (2691
// nodes) instead of the un-wrapped 20-44:1 strip. POLYLINE edge routing +
// SIMPLE node placement + thoroughness 1 + INTERACTIVE crossing minimization
// keep the 2691-node root under ~4s (ORTHOGONAL routing + BRANDES_KOEPF +
// LAYER_SWEEP at full thoroughness — the old defaults — timed out at >60s).
// ELK owns every coordinate; nothing here is hand-positioned.
const OPTS = {
  'elk.algorithm': 'layered',
  'elk.direction': 'RIGHT',
  'org.eclipse.elk.randomSeed': '1',
  'elk.edgeRouting': 'POLYLINE',
  'elk.layered.thoroughness': '1',
  'elk.layered.nodePlacement.strategy': 'SIMPLE',
  'elk.layered.crossingMinimization.strategy': 'INTERACTIVE',
  'elk.layered.cycleBreaking.strategy': 'GREEDY',
  'elk.aspectRatio': '0.7',
  'elk.layered.wrapping.strategy': 'MULTI_EDGE',
  'elk.layered.wrapping.correctionFactor': '1.0',
  'elk.layered.wrapping.additionalEdgeSpacing': '20',
  'elk.spacing.nodeNode': '26',
  'elk.layered.spacing.nodeNodeBetweenLayers': '55',
  'elk.spacing.edgeNode': '14',
  'elk.spacing.edgeEdge': '8',
  'elk.padding': '[top=24,left=24,bottom=24,right=24]',
};

// Spacing shared by the non-layered algorithms so cards stay legible and don't
// pile up. These carry no elk.layered.* keys (which those algorithms ignore).
const COMMON_SPACING = {
  'org.eclipse.elk.randomSeed': '1',
  'elk.spacing.nodeNode': '40',
  'elk.padding': '[top=24,left=24,bottom=24,right=24]',
};

/**
 * Named layout PRESETS the dialog toolbar exposes. Each entry is either
 *   { kind: 'classic' }                         — the hand-rolled kernel, OR
 *   { kind: 'elk', label, options }             — a full ELK layoutOptions map.
 * The ELK options are COMPLETE (not merged onto OPTS): each preset owns every
 * key it needs, so `layered` carries the tuned default and the others start
 * clean. `label` is the human/URL preset name. `elk.algorithm` values must be in
 * the bundled elkjs build; unavailable ones are dropped at build time.
 *
 * DEFAULT_PRESET is the initial + fallback-report default; do NOT change it
 * without intent — the toolbar and ?layout= both key off these names.
 */
export const DEFAULT_PRESET = 'layered';

export const PRESETS = {
  classic: { kind: 'classic', label: 'classic' },


  layered: { kind: 'elk', label: 'layered', options: { ...OPTS } },

  'layered-ortho': {
    kind: 'elk', label: 'layered-ortho',
    options: { ...OPTS, 'elk.edgeRouting': 'ORTHOGONAL' },
  },

  // mrtree: real tree layout — breaks DAGs/cycles into a spanning tree, so the
  // bundled-edge "lanes" of the layered view disappear. DOWN reads top-to-bottom
  // like a conversation script; RIGHT keeps the left-to-right flow of the others.
  // weighting CONSTRAINT: siblings honor a per-node
  // org.eclipse.elk.mrtree.positionConstraint (buildElkGraph sets it from a
  // switch's arm order, so arm subtrees fan out left-to-right in entry order —
  // DESCENDANTS/MODEL_ORDER weighting ignore the authored arm order).
  'tree-down': {
    kind: 'elk', label: 'tree-down',
    options: {
      'elk.algorithm': 'mrtree', 'elk.direction': 'DOWN',
      'elk.mrtree.searchOrder': 'DFS',
      'elk.mrtree.weighting': 'CONSTRAINT',
      'elk.mrtree.spacing.nodeNodeBetweenLayers': '55',
      ...COMMON_SPACING, 'elk.spacing.nodeNode': '30',
    },
  },
  'tree-right': {
    kind: 'elk', label: 'tree-right',
    options: {
      'elk.algorithm': 'mrtree', 'elk.direction': 'RIGHT',
      'elk.mrtree.searchOrder': 'DFS',
      'elk.mrtree.weighting': 'CONSTRAINT',
      'elk.mrtree.spacing.nodeNodeBetweenLayers': '90',
      ...COMMON_SPACING, 'elk.spacing.nodeNode': '30',
    },
  },

  force: {
    kind: 'elk', label: 'force',
    options: { 'elk.algorithm': 'force', ...COMMON_SPACING },
  },
  stress: {
    kind: 'elk', label: 'stress',
    options: { 'elk.algorithm': 'stress', ...COMMON_SPACING },
  },
  radial: {
    kind: 'elk', label: 'radial',
    options: { 'elk.algorithm': 'radial', ...COMMON_SPACING },
  },
  rectpacking: {
    kind: 'elk', label: 'rectpacking',
    options: { 'elk.algorithm': 'rectpacking', 'elk.aspectRatio': '1.3', ...COMMON_SPACING },
  },
};

/** Preset names in toolbar display order. */
export const PRESET_ORDER = [
  'classic', 'layered', 'layered-ortho',
  'tree-down', 'tree-right',
  'force', 'stress', 'radial', 'rectpacking',
];

/** Resolve a preset name to its descriptor, defaulting to DEFAULT_PRESET. */
export function presetFor(name) {
  return PRESETS[name] || PRESETS[DEFAULT_PRESET];
}

/**
 * The live TUNE-panel knob specs: the 5 ELK options the ⚙ panel exposes, each
 * layered as an OVERRIDE on top of the active preset (see buildElkGraph). Each
 * entry:
 *   key      — the ELK layoutOption key it drives
 *   kind     — 'select' | 'range'
 *   fallback — value used when the active preset does not set `key` (so a knob
 *              still has a sensible starting point)
 *   options  — [{value,label}] for selects
 *   min/max/step — for ranges
 * `elk.layered.spacing.nodeNodeBetweenLayers` is layered-specific; it is passed
 * through harmlessly under the non-layered algorithms (which ignore it).
 */
export const TUNE_KNOBS = [
  {
    id: 'edgeRouting', label: 'Edge routing', key: 'elk.edgeRouting', kind: 'select',
    fallback: 'ORTHOGONAL',
    options: [
      { value: 'ORTHOGONAL', label: 'Orthogonal' },
      { value: 'POLYLINE', label: 'Polyline' },
      { value: 'SPLINES', label: 'Splines (curved)' },
    ],
  },
  {
    id: 'nodeNode', label: 'Node spacing', key: 'elk.spacing.nodeNode', kind: 'range',
    fallback: 40, min: 5, max: 120, step: 1,
  },
  {
    id: 'betweenLayers', label: 'Layer spacing',
    key: 'elk.layered.spacing.nodeNodeBetweenLayers', kind: 'range',
    fallback: 55, min: 20, max: 250, step: 1,
  },
  {
    id: 'aspectRatio', label: 'Aspect ratio', key: 'elk.aspectRatio', kind: 'range',
    fallback: 1.3, min: 0.3, max: 3.0, step: 0.1,
  },
  {
    id: 'direction', label: 'Direction', key: 'elk.direction', kind: 'select',
    fallback: 'RIGHT',
    options: [
      { value: 'RIGHT', label: 'Right' },
      { value: 'DOWN', label: 'Down' },
      { value: 'LEFT', label: 'Left' },
      { value: 'UP', label: 'Up' },
    ],
  },
];

/**
 * The starting value for a tune knob under a given preset: the preset's own
 * value for that ELK key if it sets one, else the knob's fallback. Numbers are
 * parsed; selects stay strings.
 */
export function tuneBaselineValue(knob, presetOptions) {
  const raw = presetOptions && presetOptions[knob.key];
  const v = raw === undefined || raw === null ? knob.fallback : raw;
  if (knob.kind === 'range') { const n = parseFloat(v); return isNaN(n) ? knob.fallback : n; }
  return String(v);
}

/**
 * Ask a live ELK instance which layout algorithms the bundle ships, and drop any
 * PRESET whose elk.algorithm is missing. Returns { names, dropped } where `names`
 * is the surviving PRESET_ORDER and `dropped` is [{name, algorithm}]. Best-effort:
 * if knownLayoutAlgorithms is unavailable, nothing is dropped.
 */
export async function availablePresets(elk) {
  let ids = null;
  try {
    if (elk && typeof elk.knownLayoutAlgorithms === 'function') {
      const algs = await elk.knownLayoutAlgorithms();
      ids = new Set((algs || []).map((a) => (a.id || '').split('.').pop()));
    }
  } catch (_) { ids = null; }
  const names = [];
  const dropped = [];
  for (const n of PRESET_ORDER) {
    const p = PRESETS[n];
    if (p.kind !== 'elk') { names.push(n); continue; }
    const alg = p.options['elk.algorithm'];
    if (!ids || ids.has(alg)) names.push(n);
    else dropped.push({ name: n, algorithm: alg });
  }
  return { names, dropped };
}

/**
 * Build a FLAT ELK graph JSON from a DialogGraph render model. Every model node
 * is a plain top-level ELK node; every visible model edge is a plain ELK edge.
 * `model`  — the graph's `this.model` (nodes/edges/byId/...).
 * `boxOf(id)` — {w,h} box per model node id (the graph's _boxOf).
 * `presetOptions` — a COMPLETE ELK layoutOptions map (a PRESET's `options`);
 *   when omitted, the tuned `layered` default (OPTS) is used.
 * `overrides` — the live TUNE-panel override channel: a partial ELK
 *   layoutOptions map merged ON TOP of the preset (overrides win). The effective
 *   options are `{ ...presetOptions, ...overrides }`. Keys a given algorithm
 *   ignores (e.g. elk.layered.* under `force`/`mrtree`) are harmless.
 * Returns { elkGraph }.
 */
export function buildElkGraph(model, boxOf, presetOptions, overrides) {
  const byId = model.byId;

  // Effective options: preset baseline with the live tune overrides merged on
  // top (overrides win). Used for arm-ordering detection AND as the graph's
  // layoutOptions below, so a tuned elk.direction / edgeRouting / spacing takes
  // effect immediately.
  const opts = { ...(presetOptions || OPTS), ...(overrides || null) };

  // mrtree arm ordering: with weighting CONSTRAINT (tree presets), each switch
  // arm's target carries positionConstraint = arm index so sibling subtrees fan
  // out left-to-right in entry order (ch1, ch2, …, else). First switch wins on a
  // shared target; collapsed-arm stubs get their arm's index too.
  const armPos = new Map();
  if (opts['elk.mrtree.weighting'] === 'CONSTRAINT') {
    for (const mn of model.nodes) {
      if (mn.kind === 'stub' && mn.node && mn.node.armIndex !== undefined) {
        if (!armPos.has(mn.id)) armPos.set(mn.id, mn.node.armIndex);
        continue;
      }
      const sw = mn.node && mn.node.switch;
      if (!sw) continue;
      sw.arms.forEach((arm, ai) => {
        const t = arm.targetIds && arm.targetIds[0];
        if (t && byId.has(t) && !armPos.has(t)) armPos.set(t, ai);
      });
    }
  }

  const children = model.nodes.map((mn) => {
    const b = boxOf(mn.id);
    const child = { id: mn.id, width: b.w, height: b.h };
    if (armPos.has(mn.id)) {
      child.layoutOptions = {
        'org.eclipse.elk.mrtree.positionConstraint': String(armPos.get(mn.id)),
      };
    }
    return child;
  });

  // Edges: all visible model edges, by node id. Skip self loops (drawn as ↩
  // badges) and edges whose endpoints are not both present.
  const edges = [];
  let ei = 0;
  for (const e of model.edges) {
    if (!byId.has(e.from) || !byId.has(e.to)) continue;
    if (e.from === e.to) continue;
    edges.push({ id: `e${ei++}`, sources: [e.from], targets: [e.to] });
  }

  const elkGraph = { id: 'root', layoutOptions: opts, children, edges };
  return { elkGraph };
}

/**
 * Flatten a laid-out ELK graph into ABSOLUTE coordinates. ELK reports child
 * x/y relative to the parent's content box; walk the tree accumulating offsets.
 * Returns { pos: Map(id -> {x,y,w,h}), routes: Map(edgeId -> [{x,y}...]) }.
 */
export function flattenElk(laidOut) {
  const pos = new Map();
  const routes = new Map();
  const walk = (node, ox, oy) => {
    const ax = ox + (node.x || 0);
    const ay = oy + (node.y || 0);
    if (node.id !== 'root') {
      pos.set(node.id, { x: ax, y: ay, w: node.width || 0, h: node.height || 0 });
    }
    // Edges declared at this node's level: their section coords are relative to
    // this node's ORIGIN (the container the edge lives in). For root edges that
    // is the root content origin.
    for (const e of (node.edges || [])) {
      const pts = [];
      for (const sec of (e.sections || [])) {
        pts.push({ x: ax + sec.startPoint.x, y: ay + sec.startPoint.y });
        for (const bp of (sec.bendPoints || [])) pts.push({ x: ax + bp.x, y: ay + bp.y });
        pts.push({ x: ax + sec.endPoint.x, y: ay + sec.endPoint.y });
      }
      if (pts.length) routes.set(e.id, pts);
    }
    for (const c of (node.children || [])) walk(c, ax, ay);
  };
  walk(laidOut, 0, 0);
  return { pos, routes };
}
