// dialogview.js — one reusable dialog-graph controller.
//
// A DialogView owns ONE dialoggraph.js DialogGraph plus all the per-view state
// (current spec, selected node, breadcrumb trail) and the DOM it drives (canvas
// host, crumb/header bar, inspector, layout <select>, ⚙ tune button, …). It is
// instantiated twice by main.js: once for the fullscreen DIALOG tab
// (modal:false) and once for the floating overlay (modal:true). The two differ
// ONLY by which host elements they are handed and the `modal` flag — every
// feature (manual drag+persist, marks, snap, chapter, dev-paths, layout preset,
// tune, crumbs, search-select) is shared code here, so the overlay reaches full
// parity with the tab for free.
//
// CROSS-VIEW SETTINGS are SHARED: layout preset, chapter filter, dev-paths, and
// the live ELK tune overrides live in one module-level `dlgSettings` object.
// buildSpec() threads them into every view spec, so both views always render
// under the same filters. A toolbar knob updates dlgSettings then calls
// refreshAllViews(), which reopens every registered view under the new setting.
// Per-conversation MARKS + manual positions stay in DialogGraph (localStorage,
// keyed by conversation) — those are correctly per-conversation, not global.

import { DialogGraph } from './dialoggraph.js';

/**
 * SHARED cross-view settings. One object read by every DialogView.buildSpec()
 * so both views always render under the same filters.
 *   layoutPreset  — active elklayout.js PRESET name
 *   chapter       — chapter FILTER (null = all/unfiltered, else 1..10)
 *   showDev       — show developer PAGE_THRU paging edges?
 *   tuneOverrides — live ELK layoutOptions overrides (merged onto the preset)
 * The defaults here are placeholders; main.js seeds them from URL/localStorage
 * during boot before the first view opens.
 */
export const dlgSettings = {
  layoutPreset: 'layered-ortho',
  chapter: null,
  showDev: false,
  tuneOverrides: {},
};

/** Registry of live DialogView instances (fullscreen + overlay when open). */
const dialogViews = new Set();

/**
 * Re-render every registered view under the CURRENT shared settings. Called by a
 * toolbar handler after it mutates `dlgSettings` (chapter / dev-paths / preset /
 * tune), so a knob flipped in one view updates BOTH.
 */
export function refreshAllViews() {
  for (const v of dialogViews) v.reopen();
}

/** The max breadcrumb depth: older crumbs drop off the front past this. */
const CRUMB_CAP = 10;

export class DialogView {
  /**
   * @param opts.host        canvas host element for the DialogGraph
   * @param opts.headerEl     element the toolbar/crumbs render into
   * @param opts.inspectorEl  element the node inspector renders into
   * @param opts.emptyEl      optional "select a conversation" placeholder
   * @param opts.modal        true for the floating overlay (bottom inspector
   *                          strip, own header layout); false for the tab.
   * @param opts.deps         shared main.js helpers + hooks (see below).
   */
  constructor(opts = {}) {
    this.host = opts.host;
    this.headerEl = opts.headerEl;
    this.inspectorEl = opts.inspectorEl;
    this.emptyEl = opts.emptyEl || null;
    this.modal = !!opts.modal;
    this.deps = opts.deps || {};

    // Per-view state.
    this.spec = null;          // current canvas spec (compId | {forwardFrom} | {hubKey})
    // Layout PRESET is per-view (independent), unlike the shared chapter/dev
    // filters: changing the layout of one dialog/panel must not re-lay another.
    // Seeded from the boot default; thereafter each view owns its own.
    this.layoutPreset = opts.layoutPreset || dlgSettings.layoutPreset;
    this.selectedId = null;    // selected node id
    this.crumbStack = [];      // [{spec, label, select}] breadcrumb trail
    this.open_ = false;        // (overlay only) currently shown?
    this.openKey = null;       // (overlay only) the key it was opened on
    this.lastFocus = null;     // (overlay only) element to restore focus on close
    this.tunePanelOpen = false; // this view's ⚙ popover shown?

    // One DialogGraph, callbacks wired to THIS view's own methods. Manual
    // editing is enabled for BOTH views now (the whole point of the refactor).
    this.graph = new DialogGraph(this.host, {
      onSelect: (id) => this.select(id, { center: false }),
      onNavigate: (id) => this.navigate(id),
      onStatus: (text) => this.deps.onStatus(text, this),
      onManualChange: () => this.onManualChanged(),
    });
  }

  // -- shared spec build ------------------------------------------------------

  /**
   * The ONE place cross-view filters thread onto a spec. `base` is a raw view
   * spec (a component id number, {forwardFrom}, or {hubKey}); this returns a
   * copy with the shared chapter / dev-paths settings applied where they matter
   * (forward closures honor chapter; forward + hub honor dev-paths).
   */
  buildSpec(base) {
    if (typeof base === 'number') return base;              // component: no filters
    const spec = { ...base };
    if (spec.forwardFrom !== undefined) {
      if (dlgSettings.chapter != null) spec.chapter = dlgSettings.chapter;
      if (dlgSettings.showDev) spec.showDev = true;
    } else if (spec.hubKey !== undefined) {
      if (dlgSettings.showDev) spec.showDev = true;
    }
    return spec;
  }

  /**
   * Seed the graph's preset + tune overrides pre-render. The preset seeds from
   * the GLOBAL default — layout is now stored PER DIALOG (by convKey), and
   * render()'s restore overrides this with the dialog's own saved choice. An
   * uncustomized dialog thus opens at the default, never carrying over the last
   * dialog's layout.
   */
  _seedLayout() {
    this.graph.layoutPreset = dlgSettings.layoutPreset;
    this.graph.layoutOverrides = { ...dlgSettings.tuneOverrides };
  }

  // -- open entry points ------------------------------------------------------

  /** Resolve a directory key to its home view and open it, selecting the key. */
  openByKey(key) {
    const db = this.deps.db();
    const node = db.nodeByKey(key);
    if (!node) { this.deps.onReady(this); return; }
    const v = this.deps.dialogViewForNode(node);
    if (!v) return;
    if (v.kind === 'hub') this.openHub(v.spec.hubKey, { select: v.selectId });
    else this.openForward(v.spec.forwardFrom, { select: v.selectId });
  }

  /** Load the FULL forward closure from a node onto the canvas. */
  openForward(startId, o = {}) {
    const db = this.deps.db();
    const start = db.nodes.get(startId);
    if (!start) return;
    const base = { forwardFrom: startId };
    const spec = this.buildSpec(base);
    const label = `fwd:${start.key !== null ? start.key : startId}`;
    this._pushCrumb({ spec: base, label, select: o.select });
    this._render(spec, startId, o.select !== undefined ? o.select : startId, base);
  }

  /** Load a whole component onto the canvas. */
  openComponent(compId, o = {}) {
    const db = this.deps.db();
    const comp = db.components[compId];
    if (!comp) return;
    this._pushCrumb({ spec: compId, label: `comp ${compId}`, select: o.select });
    const rootId = comp.roots[0] ? comp.roots[0].node.id : (comp.nodes[0] && comp.nodes[0].id);
    this._render(compId, rootId, o.select, compId);
  }

  /** Load a hub neighborhood (depth 2) onto the canvas. */
  openHub(hubKeyOrId, o = {}) {
    const db = this.deps.db();
    const base = { hubKey: hubKeyOrId, depth: 2 };
    const spec = this.buildSpec(base);
    const start = db.nodeByKey(hubKeyOrId) || db.nodes.get(hubKeyOrId);
    const rootId = start ? start.id : null;
    const label = `hub:${hubKeyOrId}`;
    this._pushCrumb({ spec: base, label, select: o.select });
    this._render(spec, rootId, o.select !== undefined ? o.select : rootId, base);
  }

  /**
   * The single render primitive: seed layout, render the graph, select, fit,
   * repaint the header + READY. `rawSpec` is the UN-filtered base spec stored on
   * `this.spec` (so re-open re-threads current settings); `spec` is the filtered
   * one actually handed to the graph.
   */
  _render(spec, rootId, selectId, rawSpec) {
    const db = this.deps.db();
    this.spec = rawSpec !== undefined ? rawSpec : spec;
    this._seedLayout();
    this.graph.render(db, spec, rootId);
    // render() may have restored THIS dialog's own saved layout engine (per
    // convKey), overriding the seeded view default — adopt it so the toolbar
    // dropdown + READY line reflect the layout actually in use.
    this.layoutPreset = this.graph.layoutPreset;
    this.graph.rightInset = 0;
    if (this.emptyEl) this.emptyEl.classList.add('hidden');
    this._syncInset();
    this.renderHeader();
    if (selectId !== undefined && selectId !== null) this.select(selectId, { center: true });
    else { this.selectedId = null; this._hideInspector(); }
    this.graph.fit();
    this.deps.onReady(this);
  }

  /** Re-render the CURRENT view under current shared settings (preserving sel). */
  reopen() {
    if (this.spec === null) { this.renderHeader(); this.deps.onReady(this); return; }
    const sel = this.selectedId;
    // Pop the crumb we're about to re-push so re-open doesn't stack a dup.
    const top = this.crumbStack[this.crumbStack.length - 1];
    if (top && JSON.stringify(top.spec) === JSON.stringify(this.spec)) this.crumbStack.pop();
    if (typeof this.spec === 'number') this.openComponent(this.spec, { select: sel });
    else if (this.spec.forwardFrom !== undefined) this.openForward(this.spec.forwardFrom, { select: sel });
    else if (this.spec.hubKey !== undefined) this.openHub(this.spec.hubKey, { select: sel });
    else { this.renderHeader(); this.deps.onReady(this); }
  }

  // -- navigation -------------------------------------------------------------

  /**
   * Navigate to a node id/key (ghost card, back-badge, search hit, panel link).
   * If it is already on the canvas, select + center it; else open its home view.
   */
  navigate(idOrKey) {
    const db = this.deps.db();
    let node = db.nodes.get(idOrKey);
    if (!node && typeof idOrKey === 'number') node = db.nodeByKey(idOrKey);
    if (!node && /^\d+$/.test(String(idOrKey))) node = db.nodeByKey(parseInt(idOrKey, 10));
    if (!node) return;
    if (this.graph.graph && this.graph.graph.nodes.some((n) => n.id === node.id)) {
      this.select(node.id, { center: true, centerForce: true });
      return;
    }
    const v = this.deps.dialogViewForNode(node);
    if (!v) return;
    if (v.kind === 'hub') this.openHub(v.spec.hubKey, { select: v.selectId });
    else this.openForward(v.spec.forwardFrom, { select: v.selectId });
  }

  /** Select a node on the canvas and show its inspector. */
  select(id, opts = {}) {
    const db = this.deps.db();
    const node = db.nodes.get(id);
    if (!node) return;
    this.selectedId = id;
    this.graph.setSelected(id);
    if (opts.center) this.graph.centerOn(id, opts.centerForce);
    this._showInspector(node);
    this.renderHeader();   // refresh mark controls for the new selection
    this.deps.onReady(this);
  }

  /** Clear the canvas selection + hide the inspector. */
  clearSelection() {
    this.selectedId = null;
    this.graph.setSelected(null);
    this._hideInspector();
    this.renderHeader();
    this.deps.onReady(this);
  }

  // -- breadcrumbs ------------------------------------------------------------

  /** Push a crumb (dedup consecutive identical specs; cap depth). */
  _pushCrumb(entry) {
    const top = this.crumbStack[this.crumbStack.length - 1];
    if (top && JSON.stringify(top.spec) === JSON.stringify(entry.spec)) {
      top.select = entry.select;
      return;
    }
    this.crumbStack.push(entry);
    if (this.crumbStack.length > CRUMB_CAP) {
      this.crumbStack = this.crumbStack.slice(this.crumbStack.length - CRUMB_CAP);
    }
  }

  /** Return to a crumb index: pop the trail and re-open that view. */
  popToCrumb(i) {
    const target = this.crumbStack[i];
    this.crumbStack = this.crumbStack.slice(0, i); // re-open re-pushes it.
    if (typeof target.spec === 'number') this.openComponent(target.spec, { select: target.select });
    else if (target.spec.forwardFrom !== undefined) this.openForward(target.spec.forwardFrom, { select: target.select });
    else this.openHub(target.spec.hubKey, { select: target.select });
  }

  // -- header / toolbar -------------------------------------------------------

  /** Repaint THIS view's toolbar + crumbs. Delegated to main.js (which owns the
   *  DOM widgets). Overlay + tab pass different renderers via deps. */
  renderHeader() {
    if (this.modal) this.deps.renderOverlayHeader(this);
    else this.deps.renderTabHeader(this);
  }

  onManualChanged() {
    this.renderHeader();
    this.deps.onReady(this);
  }

  // -- inspector --------------------------------------------------------------

  _showInspector(node) {
    this.deps.renderInspector(this.inspectorEl, node, {
      onClose: this.modal ? undefined : () => this.clearSelection(),
      onNav: (id) => this.navigate(id),
    }, this);
    this._syncInset();
  }

  _hideInspector() {
    this.deps.hideInspector(this);
    this._syncInset();
  }

  /** Tell the graph how much right-edge width the floating inspector covers. */
  _syncInset() {
    if (this.modal) { this.graph.rightInset = 0; return; }
    const shown = this.inspectorEl && !this.inspectorEl.classList.contains('hidden');
    this.graph.rightInset = shown ? (this.inspectorEl.getBoundingClientRect().width || 0) : 0;
  }

  // -- lifecycle (overlay) ----------------------------------------------------

  /** (Overlay) Show + open on a key. Fresh crumb trail; records focus to restore. */
  openModal(key) {
    this.lastFocus = document.activeElement;
    this.crumbStack = [];
    this.open_ = true;
    this.openKey = key;
    this.deps.showModal(this);
    this.openByKey(key);
  }

  /** (Overlay) Hide + reset per-view state, leaving the underlying view alone. */
  close() {
    if (!this.open_) return;
    this.open_ = false;
    this.openKey = null;
    this.spec = null;
    this.selectedId = null;
    this.tunePanelOpen = false;
    this.deps.hideModal(this);
    this._hideInspector();
    if (this.lastFocus && this.lastFocus.focus) {
      try { this.lastFocus.focus(); } catch (_) {}
    }
  }

  // -- registry ---------------------------------------------------------------

  /** Add this view to the shared refresh registry (both views join at boot). */
  register() { dialogViews.add(this); return this; }

  // -- convenience passthroughs (for the READY line + test hooks) -------------

  get nodeCount() { return this.graph.graph ? this.graph.graph.nodes.length : 0; }
  get edgeCount() { return this.graph.graph ? this.graph.graph.edges.length : 0; }
  fit() { this.graph.fit(); }
  zoomBy(f) { this.graph.zoomBy(f); }
}
