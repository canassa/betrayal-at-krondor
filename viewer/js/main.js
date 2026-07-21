// App wiring: load archive, populate UI, render the selected asset.
//
// Two explorer views share the sidebar and the 3D canvas:
//   models — the .TBL model viewer (per-table model list, LOD select)
//   zones  — full-zone renderer (T<zz>xxyy.WLD placements over the zone TBL)

import * as THREE from 'three';
import { OrbitControls } from 'three/addons/controls/OrbitControls.js';

import { loadArchive } from './rmf.js';
import { parseTbl } from './tbl.js';
import { loadPaletteFor, loadRemapFor, parsePalette } from './pal.js';
import { loadSpriteBanksFor, parseBmx } from './bmx.js';
import { loadGroundAtlasFor, decodeScreen } from './scx.js';
import { buildModel, frameObject, spriteCycleUpdate } from './mesh.js';
import { listZones, buildZone } from './zone.js';
import { FPControls } from './fpcontrols.js';
import { loadGameData, worldToTile } from './gamedata.js';
import {
  showEntity, showHotspot, hideInspector, setOpenModelHandler,
  setTabChangeHandler, requestTab, currentTab, setDialogGraphHandler,
} from './inspector.js';
import { DialogView, dlgSettings, refreshAllViews } from './dialogview.js';
import {
  loadElk, availablePresets, PRESETS, PRESET_ORDER, DEFAULT_PRESET,
  presetFor, TUNE_KNOBS, tuneBaselineValue,
} from './elklayout.js';

const DATA = {
  rmf: './data/KRONDOR.RMF',
  dat: './data/KRONDOR.001',
};

const BG_DEFAULT = new THREE.Color(0x2a2d33);

const el = {
  tabModels: document.getElementById('tabModels'),
  tabZones: document.getElementById('tabZones'),
  tabScx: document.getElementById('tabScx'),
  tabDialog: document.getElementById('tabDialog'),
  scxView: document.getElementById('scxView'),
  scxCanvas: document.getElementById('scxCanvas'),
  scxPalCtl: document.getElementById('scxPalCtl'),
  scxPalSelect: document.getElementById('scxPalSelect'),
  filterCtl: document.getElementById('filterCtl'),
  dlgSearchCtl: document.getElementById('dlgSearchCtl'),
  dlgSearch: document.getElementById('dlgSearch'),
  dialogSidebar: document.getElementById('dialogSidebar'),
  dialogView: document.getElementById('dialogView'),
  dlgCrumbs: document.getElementById('dlgCrumbs'),
  dlgCanvasHost: document.getElementById('dlgCanvasHost'),
  dlgEmpty: document.getElementById('dlgEmpty'),
  dlgInspector: document.getElementById('dlgInspector'),
  dlgOverlay: document.getElementById('dlgOverlay'),
  dlgOvlHeader: document.getElementById('dlgOvlHeader'),
  dlgOvlBackdrop: document.getElementById('dlgOvlBackdrop'),
  dlgOvlTitle: document.getElementById('dlgOvlTitle'),
  dlgOvlCrumbs: document.getElementById('dlgOvlCrumbs'),
  dlgOvlOpenTab: document.getElementById('dlgOvlOpenTab'),
  dlgOvlLayout: document.getElementById('dlgOvlLayout'),
  dlgOvlClose: document.getElementById('dlgOvlClose'),
  dlgOvlCanvasHost: document.getElementById('dlgOvlCanvasHost'),
  dlgOvlInspStrip: document.getElementById('dlgOvlInspStrip'),
  dlgOvlInspToggle: document.getElementById('dlgOvlInspToggle'),
  dlgOvlInsp: document.getElementById('dlgOvlInsp'),
  tblCtl: document.getElementById('tblCtl'),
  tblSelect: document.getElementById('tblSelect'),
  modeSelect: document.getElementById('modeSelect'),
  lodCtl: document.getElementById('lodCtl'),
  lodSelect: document.getElementById('lodSelect'),
  palSelect: document.getElementById('palSelect'),
  navCtl: document.getElementById('navCtl'),
  navSelect: document.getElementById('navSelect'),
  gridCtl: document.getElementById('gridCtl'),
  gridChk: document.getElementById('gridChk'),
  chapterCtl: document.getElementById('chapterCtl'),
  chapterSelect: document.getElementById('chapterSelect'),
  dataCtl: document.getElementById('dataCtl'),
  dataChk: document.getElementById('dataChk'),
  encCtl: document.getElementById('encCtl'),
  encChk: document.getElementById('encChk'),
  segCtl: document.getElementById('segCtl'),
  segZones: document.getElementById('segZones'),
  segEntities: document.getElementById('segEntities'),
  kindCtl: document.getElementById('kindCtl'),
  kindSelect: document.getElementById('kindSelect'),
  helpBtn: document.getElementById('helpBtn'),
  helpPanel: document.getElementById('helpPanel'),
  filter: document.getElementById('filter'),
  modelList: document.getElementById('modelList'),
  infoBody: document.getElementById('infoBody'),
  status: document.getElementById('status'),
  view: document.getElementById('view'),
};

// ---- Render state ----
let renderer, scene, camera, controls, axes, fp;
let currentGroup = null;
let lastFrameMs = 0;

// ---- App state ----
let archive = null;
let view = 'models'; // 'models' | 'zones' | 'scx' | 'dialog'
let scxNames = []; // all .SCX + .BMX resource names, sorted (Images tab list)
let palNames = []; // all .PAL resource names, sorted
let selectedScx = null; // active image resource in the Images tab
/** @type {ReturnType<typeof parseTbl>|null} */
let table = null;
let palette = null; // {name, rgb, fallback?}
let remap = null; // {name, table, count, sky} — zone color remap
let banks = null; // {images, slots, forModel?} — sprite banks
let groundAtlas = null; // Z<nn>L.SCX band atlas (grass shader), zone TBLs only
let selectedIndex = -1;
let zones = []; // [{zone, tiles, placements}]
let selectedZone = null;
let lastStats = null;
let urlYaw = 0; // ?yaw=<degrees> camera azimuth offset (0 = default framing)
let urlPitch = null; // ?pitch=<degrees> camera elevation (null = default framing)

// ---- Editor layer ----
let gameData = null; // GameData join (STARTUP.GAM + OBJFIXED.DAT); null on 404
let zoneBuild = null; // last buildZone result (placements + center)
let chapter = 1; // active chapter for hotspot lists/markers
let listMode = 'zones'; // zones-view sidebar list: 'zones' | 'entities'
let selectedPlacement = -1; // currently selected placement index (zones view)
let selectedSpawn = -1; // currently selected self-spawn index (zones view)
const ENTITY_ROW_CAP = 500; // rendered-row cap in Entities mode
let selectionHelper = null; // THREE.BoxHelper around the selected instance
let markersGroup = null; // Points cloud (state records + hotspot bboxes)
let encounterMarkers = null; // combat spawn-marker layer (kind 1/7 hotspots)
let encounterHotspots = []; // [{hotspot, worldX, worldY}] backing the markers
let encounterRects = null; // translucent ground rects over every hotspot bbox
let encounterRectHotspots = []; // per-rect owning hotspot, parallel to child order
let encounterLinks = null; // click-source link lines (fixed object -> bbox key)
let readyBase = ''; // last READY status text; the TAB:<active> suffix appends to it
let selectionActive = false; // a placement/spawn/hotspot is currently inspected
const raycaster = new THREE.Raycaster();
const pickNdc = new THREE.Vector2();

function setStatus(text, cls) {
  el.status.textContent = text;
  el.status.className = cls || '';
}

function fatal(msg) {
  window.__viewerError = msg;
  setStatus('ERROR: ' + msg, 'err');
  console.error(msg);
}

window.onerror = (m, src, line, col, err) => {
  fatal((err && err.stack) || `${m} @ ${src}:${line}:${col}`);
};

// ---------------------------------------------------------------- three setup
function initThree() {
  // Log depth: zone scenes span ~5 m to ~4,000,000 units of depth; a linear
  // 24-bit z-buffer has >100-unit error at zone distances, which makes the
  // coplanar-overlay biases (mesh.js) and the ground plane flicker.
  renderer = new THREE.WebGLRenderer({ antialias: true, logarithmicDepthBuffer: true });
  renderer.setPixelRatio(window.devicePixelRatio || 1);
  scene = new THREE.Scene();
  scene.background = BG_DEFAULT.clone();

  camera = new THREE.PerspectiveCamera(55, 1, 1, 200000);
  camera.position.set(3000, 3000, 5000);

  controls = new OrbitControls(camera, renderer.domElement);
  controls.enableDamping = true;
  controls.dampingFactor = 0.08;

  fp = new FPControls(camera, renderer.domElement);
  fp._onLockChange = (locked) => {
    if (!fp.enabled) return;
    if (locked) {
      el.helpPanel.classList.add('hidden');
      setStatus('free-look · WASD move · Shift boost · wheel speed · click/Esc exits', 'ready');
    } else {
      setStatus('drag to look · WASD move · dbl-click toggles look · left click inspects · ? = help');
    }
  };

  axes = new THREE.AxesHelper(1000);
  scene.add(axes);

  el.view.appendChild(renderer.domElement);
  resize();
  window.addEventListener('resize', resize);

  renderer.setAnimationLoop((timeMs) => {
    const dt = Math.min((timeMs - lastFrameMs) / 1000, 0.1);
    lastFrameMs = timeMs;
    if (fp.enabled) fp.update(dt);
    else controls.update();
    if (currentGroup) spriteCycleUpdate(currentGroup, timeMs);
    renderer.render(scene, camera);
  });
}

function resize() {
  const w = el.view.clientWidth || 1;
  const h = el.view.clientHeight || 1;
  renderer.setSize(w, h, false);
  camera.aspect = w / h;
  camera.updateProjectionMatrix();
}

// ---------------------------------------------------------------- URL params
// With NO view/tbl/model params the app defaults to the ZONES view, zone 01,
// encounter/hotspot overlay on. Any explicit param keeps its usual meaning.
function params() {
  const p = new URLSearchParams(location.search);
  return {
    // ?hotspot=<zz>,<xx>,<yy>,<idx> : open the zone with the inspector already
    // showing tile (xx,yy)'s hotspot #idx (index into that tile's chapter-gated
    // list). Deep link for the payload-first hotspot inspector; consumed in
    // selectZone once the zone build (and its hotspot join) exists.
    hotspot: p.get('hotspot'),
    view: p.get('view'),
    zone: p.get('zone'),
    nav: p.get('nav'),
    tbl: p.get('tbl'),
    model: p.get('model'),
    mode: p.get('mode'),
    lod: p.get('lod'),
    palette: p.get('palette'),
    yaw: p.get('yaw'),
    pitch: p.get('pitch'),
    // legacy hooks, accepted but ignored: colorbyte (semantics now pinned),
    // depth (painter mode removed — always z-buffered).
    colorbyte: p.get('colorbyte'),
  };
}

// ---------------------------------------------------------------- view switch
function setView(v, opts = {}) {
  const prev = view;
  view = v;
  const dialogMode = v === 'dialog';
  el.tabModels.classList.toggle('sel', v === 'models');
  el.tabZones.classList.toggle('sel', v === 'zones');
  el.tabScx.classList.toggle('sel', v === 'scx');
  el.tabDialog.classList.toggle('sel', dialogMode);
  el.scxPalCtl.classList.toggle('hidden', v !== 'scx');
  el.scxView.classList.toggle('hidden', v !== 'scx');
  // The 3D mode/day-night block means nothing for flat screens.
  document.getElementById('modeCtl').classList.toggle('hidden', v === 'scx');

  // Models/zones control blocks are irrelevant in dialog mode.
  el.tblCtl.classList.toggle('hidden', v !== 'models');
  el.lodCtl.classList.toggle('hidden', v !== 'models');
  el.navCtl.classList.toggle('hidden', v !== 'zones');
  el.gridCtl.classList.toggle('hidden', v !== 'zones');
  el.chapterCtl.classList.toggle('hidden', v !== 'zones');
  el.dataCtl.classList.toggle('hidden', v !== 'zones');
  el.encCtl.classList.toggle('hidden', v !== 'zones');
  el.segCtl.classList.toggle('hidden', v !== 'zones');
  // Sidebar body + filter/search swap for dialog mode.
  el.filterCtl.classList.toggle('hidden', dialogMode);
  el.dlgSearchCtl.classList.toggle('hidden', !dialogMode);
  document.getElementById('modelListWrap').classList.toggle('hidden', dialogMode);
  el.dialogSidebar.classList.toggle('hidden', !dialogMode);
  el.dialogView.classList.toggle('hidden', !dialogMode);
  document.getElementById('info').classList.toggle('hidden', dialogMode);

  updateListModeUi();
  if (v !== 'zones') hideInspector();
  updateFilterPlaceholder();
  // Leaving the DIALOG tab dismisses its ⚙ popover (body-mounted, so not hidden
  // by the tab swap otherwise).
  if (prev === 'dialog' && v !== 'dialog') { if (dialogFull) dialogFull.tunePanelOpen = false; removeTunePanel('tab'); }

  if (dialogMode) {
    enterDialogView(opts);
    return;
  }
  rebuildList();
  if (v === 'zones') {
    const zone = opts.zone && zones.some((z) => z.zone === opts.zone)
      ? opts.zone
      : (selectedZone || (zones[0] && zones[0].zone));
    if (zone) selectZone(zone);
  } else if (v === 'scx') {
    selectScx(opts.scx || selectedScx || scxNames[0]);
  } else {
    applyNav('orbit');
    scene.background = BG_DEFAULT.clone();
    if (selectedIndex >= 0) rebuildMesh();
    else selectModel(0, opts.lod);
  }
}

/** Switch camera controls. Models view is always orbit; zones follow navSelect. */
function applyNav(nav) {
  if (nav === 'fly' || nav === 'walk') {
    controls.enabled = false;
    fp.enable(nav);
    if (document.pointerLockElement !== renderer.domElement) {
      setStatus('drag to look · WASD move · dbl-click toggles look · left click inspects · ? = help');
    }
  } else {
    fp.disable();
    controls.enabled = true;
    // Re-aim orbit at whatever we are looking at now.
    const dir = camera.getWorldDirection(new THREE.Vector3());
    controls.target.copy(camera.position).addScaledVector(dir, 5000);
    controls.update();
  }
}

// ---------------------------------------------------------------- table load
/**
 * Load a .TBL (+palette/remap/banks) into the module state and, unless
 * opts.defer, render its first/requested model. `defer` is the boot path for
 * non-models views: the table data is needed (entity Shape join), but building
 * a model mesh that the zone build immediately replaces is a wasted flash —
 * the first MODELS-tab visit selects model 0 as usual.
 */
function loadTable(tblName, opts = {}) {
  const bytes = archive.getResource(tblName);
  if (!bytes) return fatal(`resource not found: ${tblName}`);

  try {
    table = parseTbl(bytes);
  } catch (e) {
    return fatal(`parse ${tblName}: ${e.message}`);
  }

  try {
    palette = loadPaletteFor(archive, tblName);
  } catch (e) {
    return fatal(`palette for ${tblName}: ${e.message}`);
  }

  try {
    remap = loadRemapFor(archive, tblName);
  } catch (e) {
    return fatal(`remap for ${tblName}: ${e.message}`);
  }

  try {
    banks = loadSpriteBanksFor(archive, tblName);
  } catch (e) {
    banks = { images: [], slots: [] };
  }

  try {
    groundAtlas = loadGroundAtlasFor(archive, tblName);
  } catch (e) {
    groundAtlas = null;
  }

  el.tblSelect.value = tblName;
  rebuildList();
  if (opts.defer) return;

  // Pick model.
  let idx = 0;
  if (opts.model !== undefined && opts.model !== null && opts.model !== '') {
    const n = parseInt(opts.model, 10);
    if (!isNaN(n) && n >= 0 && n < table.models.length) idx = n;
  }
  selectModel(idx, opts.lod);
}

// ---------------------------------------------------------------- sidebar list
function rebuildList() {
  if (view === 'zones') {
    if (listMode === 'entities') rebuildEntityList();
    else rebuildZoneList();
  } else if (view === 'scx') {
    rebuildScxList();
  } else {
    rebuildModelList();
  }
}

/** Toggle the segmented control + kind dropdown to match the current mode. */
function updateListModeUi() {
  const entities = view === 'zones' && listMode === 'entities';
  el.segZones.classList.toggle('sel', listMode !== 'entities');
  el.segEntities.classList.toggle('sel', listMode === 'entities');
  el.kindCtl.classList.toggle('hidden', !entities);
}

function updateFilterPlaceholder() {
  if (view === 'scx') el.filter.placeholder = 'image name substring';
  else if (view !== 'zones') el.filter.placeholder = 'name / idx substring';
  else el.filter.placeholder = listMode === 'entities' ? 'shape name / #idx' : 'zone id substring';
}

/** Switch the zones-view sidebar list between the zone list and entity list. */
function setListMode(mode) {
  if (listMode === mode) return;
  listMode = mode === 'entities' ? 'entities' : 'zones';
  updateListModeUi();
  updateFilterPlaceholder();
  rebuildList();
}

function rebuildModelList() {
  const filter = el.filter.value.trim().toLowerCase();
  el.modelList.innerHTML = '';
  if (!table) return;
  for (const m of table.models) {
    const label = `${m.index} ${m.name}`.toLowerCase();
    if (filter && !label.includes(filter)) continue;

    const li = document.createElement('li');
    li.dataset.index = m.index;
    if (m.index === selectedIndex) li.classList.add('sel');

    const idx = document.createElement('span');
    idx.className = 'idx';
    idx.textContent = m.index;
    const nm = document.createElement('span');
    nm.className = 'nm';
    nm.textContent = m.name;
    const kind = document.createElement('span');
    kind.className = 'kind';
    kind.textContent = 'k' + m.bKind;

    li.append(idx, nm, kind);

    if (m.error) li.append(badge('err', 'err'));
    else if (m.empty) li.append(badge('empty', 'empty'));
    else if (hasSprite(m)) li.append(badge('sprite', 'sprite'));

    li.addEventListener('click', () => selectModel(m.index));
    el.modelList.appendChild(li);
  }
}

function rebuildZoneList() {
  const filter = el.filter.value.trim().toLowerCase();
  el.modelList.innerHTML = '';
  for (const z of zones) {
    const label = `z${z.zone}`.toLowerCase();
    if (filter && !label.includes(filter)) continue;

    const li = document.createElement('li');
    li.dataset.zone = z.zone;
    if (z.zone === selectedZone) li.classList.add('sel');

    const idx = document.createElement('span');
    idx.className = 'idx';
    idx.textContent = `Z${z.zone}`;
    const nm = document.createElement('span');
    nm.className = 'nm';
    nm.textContent = `${z.tiles.length} tiles`;
    const kind = document.createElement('span');
    kind.className = 'kind';
    kind.textContent = `${z.placements} objs`;

    li.append(idx, nm, kind);
    li.addEventListener('click', () => selectZone(z.zone));
    el.modelList.appendChild(li);
  }
}

// ---------------------------------------------------------------- SCX screens

function rebuildScxList() {
  const filter = el.filter.value.trim().toLowerCase();
  el.modelList.innerHTML = '';
  for (const name of scxNames) {
    if (filter && !name.toLowerCase().includes(filter)) continue;
    const li = document.createElement('li');
    li.dataset.scx = name;
    if (name === selectedScx) li.classList.add('sel');
    const nm = document.createElement('span');
    nm.className = 'nm';
    nm.textContent = name;
    const kind = document.createElement('span');
    kind.className = 'kind';
    const bytes = archive.getResource(name);
    if (name.endsWith('.BMX') && bytes.length >= 6
      && (bytes[0] | (bytes[1] << 8)) === 0x1066) {
      const n = bytes[4] | (bytes[5] << 8);
      kind.textContent = `${n} img`;
    } else {
      kind.textContent = `${bytes.length} B`;
    }
    li.append(nm, kind);
    li.addEventListener('click', () => selectScx(name));
    el.modelList.appendChild(li);
  }
}

/**
 * Verified screen -> palette pairs that name derivation can't reach. Sources:
 * engine call sites (DIALOG + the rift map run over INVENTOR.PAL,
 * MODALSCR.C:358,402; CONT2 shares CONTENTS.PAL, GMAIN.C:425-431) and the
 * decompressed TTM cutscene scripts (INTRO.TTM loads INT_BORD.SCR with
 * INT_DYN.PAL; C11.TTM opens on C11A.PAL; the scrolling credits draw over
 * BLANK after the intro's credits segment applies CREDITS.PAL, GMAIN.C:259).
 * The in-world screens — the HUD frames FRAME/CFRAME/FCOMBAT/ENCAMP and the
 * combat spell-pick screen CAST (CSPELL.C:2153) — draw under whatever zone
 * palette is active; Z01.PAL stands in. C42 has two lives: its cutscene pairs the same-stem
 * C42.PAL (C42.TTM, found by the stem rule); the teleport modal reuses it
 * under TELEPORT.PAL (MODALSCR.C:194,212) — pick that from the dropdown.
 */
const SCX_PALETTE_PAIRS = {
  // From a slot-accurate simulation of the TTM scripts (palettes/images load
  // into numbered slots, pairing recorded at DRAW time — TTM.C 0x1061/0xf05f/
  // 0x1051/0xf02f/0xa5xx), each entry then adjudicated by rendering under
  // both candidates (clean art vs confetti). Draw-time losers (C21A_BAK,
  // C21_MAK) turned out to be draw-then-recolor boundary cases already
  // covered by the name ladder.
  'C11.SCX': 'C11B.PAL',
  'C12B_SRL.BMX': 'C12A.PAL',
  'C21B1.BMX': 'C21.PAL',
  'C21C.BMX': 'FULLMAP.PAL',
  'C61A_TLK.BMX': 'C61B.PAL',
  'DIALOG.SCX': 'INVENTOR.PAL',
  'RIFTMAP.SCX': 'INVENTOR.PAL',
  'CONT2.SCX': 'CONTENTS.PAL',
  'INT_BORD.SCX': 'INT_DYN.PAL',
  'INT_LGHT.BMX': 'INT_DYN.PAL',
  'INT_BUNT.BMX': 'INT_DYN.PAL',
  'INT_BOOK.BMX': 'INT_TITL.PAL',
  'BLANK.SCX': 'CREDITS.PAL',
  'FRAME.SCX': 'Z01.PAL',
  'CFRAME.SCX': 'Z01.PAL',
  'FCOMBAT.SCX': 'Z01.PAL',
  'ENCAMP.SCX': 'Z01.PAL',
  'CAST.SCX': 'Z01.PAL',
  // BMX banks drawn on engine screens whose palette is set elsewhere:
  // inventory/dialog sprites and portraits (INVENTOR.PAL), and the combat
  // spell/projectile sheet FIGS swapped into bank 0 in-world (zone pal).
  'HEADS.BMX': 'INVENTOR.PAL',
  'INVSHP1.BMX': 'INVENTOR.PAL',
  'INVSHP2.BMX': 'INVENTOR.PAL',
  'INVLOCK.BMX': 'INVENTOR.PAL',
  'FIGS.BMX': 'Z01.PAL',
  'ENCAMP.BMX': 'Z01.PAL',
};

/**
 * Palette for an image resource: the dropdown override, the verified pair, or
 * a name-derived guess. The derivation ladder mirrors the archive's naming
 * conventions (all confirmed by the decompressed TTM scripts): same stem
 * (PUZZLE.SCX/PUZZLE.PAL), minus trailing digits (OPTIONS0 -> OPTIONS.PAL),
 * minus an _SUFFIX (C42_PNTR -> C42.PAL), minus a BAK/PPL/ARM role suffix
 * (TVRN1BAK -> TVRN1.PAL), minus one trailing letter (ACT009A -> ACT009.PAL,
 * Z01L -> Z01.PAL), and Z<nn>SLOT<d> texture banks -> Z<nn>.PAL.
 */
function scxPaletteFor(scxName) {
  const sel = el.scxPalSelect.value;
  if (sel && sel !== 'auto') return sel;
  const pair = SCX_PALETTE_PAIRS[scxName];
  if (pair && palNames.includes(pair)) return pair;
  const slot = /^Z(\d\d)SLOT\d+\.BMX$/.exec(scxName);
  if (slot && palNames.includes(`Z${slot[1]}.PAL`)) return `Z${slot[1]}.PAL`;
  const stem = scxName.replace(/\.(SCX|BMX)$/i, '');
  const cands = [
    stem,
    stem.replace(/\d+$/, ''),
    stem.replace(/_[A-Z0-9]+$/, ''),
    stem.replace(/(BAK|PPL|ARM)$/, ''),
    stem.replace(/[A-Z]$/, ''),
    // Composed: chapter-scene assets like C51A_BAK -> segment C51A -> the
    // single chapter palette C51.PAL (C51.TTM loads only that one).
    stem.replace(/_[A-Z0-9]+$/, '').replace(/[A-Z]$/, ''),
    stem.replace(/_[A-Z0-9]+$/, '').replace(/\d+$/, ''),
  ];
  for (const c of cands) {
    if (c && palNames.includes(`${c}.PAL`)) return `${c}.PAL`;
  }
  return palNames.includes('OPTIONS.PAL') ? 'OPTIONS.PAL' : palNames[0];
}

/**
 * Lay a BMX bank's images out as a contact sheet: left-to-right rows wrapped
 * at 640px, 2px gaps, palette index 0 transparent. Returns {pixels (-1 =
 * transparent), width, height} in sheet coordinates.
 */
function bmxContactSheet(images) {
  const GAP = 2;
  const WRAP = 640;
  let x = 0;
  let y = 0;
  let rowH = 0;
  let sheetW = 0;
  const places = [];
  for (const im of images) {
    if (x > 0 && x + im.width > WRAP) {
      x = 0;
      y += rowH + GAP;
      rowH = 0;
    }
    places.push({ im, x, y });
    x += im.width + GAP;
    rowH = Math.max(rowH, im.height);
    sheetW = Math.max(sheetW, x - GAP);
  }
  const sheetH = y + rowH;
  const pixels = new Int16Array(sheetW * sheetH).fill(-1);
  for (const { im, x: px, y: py } of places) {
    for (let iy = 0; iy < im.height; iy++) {
      for (let ix = 0; ix < im.width; ix++) {
        const c = im.pixels[iy * im.width + ix];
        if (c !== 0) pixels[(py + iy) * sheetW + px + ix] = c;
      }
    }
  }
  return { pixels, width: sheetW, height: sheetH };
}

/** Decode + paint an image resource (SCX screen or BMX bank) + info panel. */
function selectScx(name) {
  if (!name || !archive.hasResource(name)) return;
  selectedScx = name;
  for (const li of el.modelList.querySelectorAll('li')) {
    li.classList.toggle('sel', li.dataset.scx === name);
  }
  try {
    const palName = scxPaletteFor(name);
    const rgb = parsePalette(archive.getResource(palName));
    let sheet;
    let meta = null;
    let images = null;
    if (name.endsWith('.BMX')) {
      images = parseBmx(archive.getResource(name));
      sheet = bmxContactSheet(images);
    } else {
      meta = decodeScreen(archive.getResource(name));
      sheet = meta;
    }
    const img = new ImageData(sheet.width, sheet.height);
    for (let i = 0; i < sheet.width * sheet.height; i++) {
      const c = sheet.pixels[i];
      if (c < 0) continue; // sheet gap / transparent texel
      img.data[i * 4] = rgb[c * 3];
      img.data[i * 4 + 1] = rgb[c * 3 + 1];
      img.data[i * 4 + 2] = rgb[c * 3 + 2];
      img.data[i * 4 + 3] = 255;
    }
    el.scxCanvas.width = sheet.width;
    el.scxCanvas.height = sheet.height;
    el.scxCanvas.getContext('2d').putImageData(img, 0, 0);
    // Upscale via CSS (nearest-neighbor); the CSS max-width/height cap keeps
    // wide sheets and the 640-wide book spread inside the viewport.
    const k = sheet.width <= 320 ? 3 : 2;
    el.scxCanvas.style.width = `${sheet.width * k}px`;
    showScxInfo(name, meta, images, palName);
    signalReady(`READY ${name} ${sheet.width}x${sheet.height} ${palName}`);
  } catch (e) {
    setStatus(`${name}: ${e.message}`, 'err');
  }
}

function showScxInfo(name, meta, images, palName) {
  const rows = [];
  const add = (k, v) => rows.push(infoRow(k, v));
  add('resource', escapeHtml(name));
  if (images) {
    add('container', 'BMX bank (magic 0x1066)');
    add('images', images.length);
    const dims = images.slice(0, 6).map((im) => `${im.width}×${im.height}`).join(' ');
    add('sizes', dims + (images.length > 6 ? ' …' : ''));
  } else {
    add('container', meta.headered ? 'SCX (magic 0x27B6)' : 'headerless codec stream');
    add('codec', meta.codec === 2 ? '2 (LZW)' : meta.codec === 0 ? '0 (raw)' : meta.codec);
    add('size', `${meta.width}×${meta.height} @ ${meta.bpp}bpp`);
  }
  add('palette', escapeHtml(palName)
    + (el.scxPalSelect.value === 'auto' ? ' (auto)' : ''));
  infoTable(rows);
}

// ---------------------------------------------------------------- entity list

/** Which state file (if any) backs a placement: 'startup' | 'objfixed' | null. */
function stateSourceFor(p) {
  if (!gameData || !selectedZone) return null;
  const st = gameData.stateFor(selectedZone, p.worldX, p.worldY);
  return st ? st.source : null;
}

/** True when the placement's state record carries a nonzero interact message. */
function hasTextMessage(p) {
  if (!gameData || !selectedZone) return false;
  const st = gameData.stateFor(selectedZone, p.worldX, p.worldY);
  if (!st) return false;
  const f = st.record.fields.find((x) => x.name === 'msg.messageId');
  return !!(f && f.value);
}

/** True when the placement's state record is a container (residence 4 or 9). */
function isContainer(p) {
  const st = gameData && selectedZone
    ? gameData.stateFor(selectedZone, p.worldX, p.worldY) : null;
  return !!st && (st.record.residence === 4 || st.record.residence === 9);
}

/** True when the placement's tile has hotspots for the current chapter. */
function tileHasHotspots(p) {
  if (!gameData || !selectedZone) return false;
  const tx = worldToTile(p.worldX);
  const ty = worldToTile(p.worldY);
  return gameData.hotspotsFor(selectedZone, tx, ty, chapter).length > 0;
}

/** Apply the kind dropdown to a placement. */
function matchesKind(p, kind) {
  switch (kind) {
    case 'withdata': return !!stateSourceFor(p);
    case 'containers': return isContainer(p);
    case 'text': return hasTextMessage(p);
    case 'hotspot': return tileHasHotspots(p);
    default: return true; // 'all'
  }
}

/** Apply the kind dropdown to a self-spawned object (its own record). */
function matchesSpawnKind(s, kind) {
  switch (kind) {
    case 'withdata': return true; // a spawn is always a state record
    case 'containers': return true; // residence 9 counts as a container (spec)
    case 'text': {
      const f = s.record.fields.find((x) => x.name === 'msg.messageId');
      return !!(f && f.value);
    }
    case 'hotspot':
      return gameData
        ? gameData.hotspotsFor(selectedZone, worldToTile(s.worldX),
          worldToTile(s.worldY), chapter).length > 0
        : false;
    default: return true; // 'all'
  }
}

/**
 * Entities-mode sidebar list: rows from zoneBuild.placements with a data-source
 * badge (GAM/OBJ), filtered by the kind dropdown and the filter box (shape name
 * / #index). A red gap row leads if the parse hit gaps; rendered rows are capped
 * at 500 with a "showing 500 of N" footer.
 */
function rebuildEntityList() {
  el.modelList.innerHTML = '';
  if (!zoneBuild) return;
  const filter = el.filter.value.trim().toLowerCase();
  const kind = el.kindSelect.value;

  // Leading gap row (parse gaps in the STARTUP.GAM temp block).
  const gapCount = gameData && selectedZone ? gameData.gaps(selectedZone).length : 0;
  if (gapCount) {
    const li = document.createElement('li');
    li.className = 'gaprow';
    li.textContent = `⚠ ${gapCount} parse gap${gapCount === 1 ? '' : 's'}`;
    el.modelList.appendChild(li);
  }

  const matched = [];
  for (const p of zoneBuild.placements) {
    if (!matchesKind(p, kind)) continue;
    if (filter) {
      const label = `#${p.index} ${p.name}`.toLowerCase();
      if (!label.includes(filter)) continue;
    }
    matched.push({ kind: 'placement', item: p });
  }
  // Self-spawned objects are their own record (residence 9): always a container.
  for (const s of zoneBuild.spawns || []) {
    if (!matchesSpawnKind(s, kind)) continue;
    if (filter) {
      const label = `#${s.index} ${s.name}`.toLowerCase();
      if (!label.includes(filter)) continue;
    }
    matched.push({ kind: 'spawn', item: s });
  }

  const shown = Math.min(matched.length, ENTITY_ROW_CAP);
  for (let i = 0; i < shown; i++) {
    const m = matched[i];
    el.modelList.appendChild(m.kind === 'spawn' ? spawnRow(m.item) : entityRow(m.item));
  }
  if (matched.length > ENTITY_ROW_CAP) {
    const li = document.createElement('li');
    li.className = 'footrow';
    li.textContent = `showing ${ENTITY_ROW_CAP} of ${matched.length}`;
    el.modelList.appendChild(li);
  }
}

/** One entity row: `#index shapeName badge tile`. */
function entityRow(p) {
  const li = document.createElement('li');
  li.dataset.index = p.index;
  if (p.index === selectedPlacement) li.classList.add('sel');

  const idx = document.createElement('span');
  idx.className = 'idx';
  idx.textContent = `#${p.index}`;
  const nm = document.createElement('span');
  nm.className = 'nm';
  nm.textContent = p.name;
  li.append(idx, nm);

  const src = stateSourceFor(p);
  if (src === 'startup') li.append(badge('GAM', 'gam'));
  else if (src === 'objfixed') li.append(badge('OBJ', 'obj'));

  const tile = document.createElement('span');
  tile.className = 'tile';
  tile.textContent = `${worldToTile(p.worldX)},${worldToTile(p.worldY)}`;
  li.append(tile);

  li.addEventListener('click', () => selectEntityRow(p.index));
  return li;
}

/** One self-spawned-object row: `#index shapeName SPAWN tile`. */
function spawnRow(s) {
  const li = document.createElement('li');
  li.dataset.index = s.index;
  li.dataset.kind = 'spawn';
  if (s.index === selectedSpawn) li.classList.add('sel');

  const idx = document.createElement('span');
  idx.className = 'idx';
  idx.textContent = `#${s.index}`;
  const nm = document.createElement('span');
  nm.className = 'nm';
  nm.textContent = s.name;
  li.append(idx, nm);
  li.append(badge('SPAWN', 'spawn'));

  const tile = document.createElement('span');
  tile.className = 'tile';
  tile.textContent = `${worldToTile(s.worldX)},${worldToTile(s.worldY)}`;
  li.append(tile);

  li.addEventListener('click', () => selectSpawnRow(s.index));
  return li;
}

/** Select an entity from a list-row click: inspect it and fly the camera to it. */
function selectEntityRow(index) {
  selectPlacement(index);
  moveCameraToPlacement(index);
}

/** Select a self-spawn from a list-row click: inspect it and move the camera. */
function selectSpawnRow(index) {
  selectSpawn(index);
  moveCameraToInstance(zoneBuild && zoneBuild.spawns[index]
    ? zoneBuild.spawns[index].instanceGroup : null);
}

/** Move the active camera to a placement's instance by index. */
function moveCameraToPlacement(index) {
  if (!zoneBuild) return;
  const p = zoneBuild.placements[index];
  if (p) moveCameraToInstance(p.instanceGroup);
}

/**
 * Move the active camera to look at an instance group's THREE world position.
 * Orbit: re-target keeping the current view direction, backed off by radius*3.
 * Fly/walk: stand 2500 units out horizontally at current/eye height, look at it.
 */
function moveCameraToInstance(instanceGroup) {
  if (!instanceGroup) return;
  currentGroup.updateMatrixWorld(true);
  const target = new THREE.Vector3().setFromMatrixPosition(instanceGroup.matrixWorld);

  if (fp.enabled) {
    // Stand a fixed horizontal distance out, keeping the current heading's
    // azimuth so the entity lands in front of the camera.
    const dist = 2500;
    const flat = new THREE.Vector3(
      camera.position.x - target.x, 0, camera.position.z - target.z);
    if (flat.lengthSq() < 1) flat.set(0, 0, 1);
    flat.normalize().multiplyScalar(dist);
    const eye = fp.mode === 'walk' ? fp.eyeHeight : camera.position.y;
    camera.position.set(target.x + flat.x, eye, target.z + flat.z);
    const look = new THREE.Vector3().subVectors(target, camera.position);
    fp.yaw = Math.atan2(-look.x, -look.z);
    fp.pitch = Math.atan2(look.y, Math.hypot(look.x, look.z));
  } else {
    // Orbit: keep the current offset direction, back off proportional to the
    // instance size so the entity fills a reasonable part of the frame.
    const size = new THREE.Box3().setFromObject(instanceGroup)
      .getSize(new THREE.Vector3());
    const radius = Math.max(size.length() / 2, 500);
    const dir = camera.position.clone().sub(controls.target);
    if (dir.lengthSq() < 1) dir.set(1, 1, 1);
    dir.normalize().multiplyScalar(radius * 3);
    controls.target.copy(target);
    camera.position.copy(target).add(dir);
    controls.update();
  }
}

function badge(text, cls) {
  const b = document.createElement('span');
  b.className = 'badge ' + cls;
  b.textContent = text;
  return b;
}

function hasSprite(m) {
  for (const lod of m.lods)
    for (const part of lod.parts) if (part.nonMesh) return true;
  return false;
}

// ---------------------------------------------------------------- LOD select
function populateLodSelect(model, wantLod) {
  el.lodSelect.innerHTML = '';
  const n = model.lods.length;
  for (let i = 0; i < n; i++) {
    const o = document.createElement('option');
    o.value = i;
    o.textContent = `${i} (thr ${model.lods[i].threshold})`;
    el.lodSelect.appendChild(o);
  }
  let lod = 0;
  if (wantLod !== undefined && wantLod !== null && wantLod !== '') {
    const v = parseInt(wantLod, 10);
    if (!isNaN(v) && v >= 0 && v < n) lod = v;
  }
  el.lodSelect.value = String(lod);
  return lod;
}

// ---------------------------------------------------------------- shared bits
function clearCurrentGroup() {
  clearEditorOverlays();
  zoneBuild = null;
  if (currentGroup) {
    scene.remove(currentGroup);
    disposeGroup(currentGroup);
    currentGroup = null;
  }
}

/** Dispose the selection highlight and marker cloud (THREE objects we own). */
function clearEditorOverlays() {
  if (selectionHelper) {
    if (selectionHelper.parent) selectionHelper.parent.remove(selectionHelper);
    disposeGroup(selectionHelper);
    selectionHelper = null;
  }
  if (markersGroup) {
    if (markersGroup.parent) markersGroup.parent.remove(markersGroup);
    disposeGroup(markersGroup);
    markersGroup = null;
  }
  if (encounterMarkers) {
    if (encounterMarkers.parent) encounterMarkers.parent.remove(encounterMarkers);
    disposeGroup(encounterMarkers);
    encounterMarkers = null;
  }
  if (encounterRects) {
    if (encounterRects.parent) encounterRects.parent.remove(encounterRects);
    disposeGroup(encounterRects);
    encounterRects = null;
  }
  if (encounterLinks) {
    if (encounterLinks.parent) encounterLinks.parent.remove(encounterLinks);
    disposeGroup(encounterLinks);
    encounterLinks = null;
  }
  encounterHotspots = [];
  encounterRectHotspots = [];
}

/** Apply ?yaw/?pitch to the camera around the framed target. */
function applyUrlCamera(center) {
  if (!urlYaw && urlPitch === null) return;
  const off = camera.position.clone().sub(center);
  if (urlPitch !== null) {
    const s = new THREE.Spherical().setFromVector3(off);
    s.phi = THREE.MathUtils.clamp(
      Math.PI / 2 - (urlPitch * Math.PI) / 180, 0.01, Math.PI - 0.01);
    off.setFromSpherical(s);
  }
  off.applyAxisAngle(new THREE.Vector3(0, 1, 0), (urlYaw * Math.PI) / 180);
  camera.position.copy(center).add(off);
  controls.update();
}

/** Flag readiness (headless capture hook) after one frame renders. */
function signalReady(text) {
  readyBase = text;
  requestAnimationFrame(() => {
    requestAnimationFrame(() => {
      window.__viewerReady = true;
      setStatus(readyStatusText(), 'ready');
    });
  });
}

/**
 * READY text plus ` TAB:<active>` while an entity/hotspot is inspected, plus
 * ` OVL:<key>` while the dialog-graph overlay is open. Both suffixes are
 * appended to whatever base READY the underlying tab last produced, so the
 * overlay never rewrites the underlying view's READY line.
 */
function readyStatusText() {
  let t = selectionActive ? `${readyBase} TAB:${currentTab()}` : readyBase;
  if (dialogOverlay && dialogOverlay.open_) t += ` OVL:${dialogOverlay.openKey}`;
  return t;
}

/** Re-paint the READY status line (e.g. after a tab switch). */
function refreshReadyStatus() {
  if (window.__viewerReady && readyBase) setStatus(readyStatusText(), 'ready');
}

// ---------------------------------------------------------------- select model
function selectModel(index, wantLod) {
  selectedIndex = index;
  const model = table.models[index];

  for (const li of el.modelList.querySelectorAll('li')) {
    li.classList.toggle('sel', Number(li.dataset.index) === index);
  }

  populateLodSelect(model, wantLod);
  rebuildMesh();
}

// ---------------------------------------------------------------- build mesh
function rebuildMesh() {
  if (selectedIndex < 0 || !table) return;
  const model = table.models[selectedIndex];

  clearCurrentGroup();

  const lodIndex = parseInt(el.lodSelect.value, 10) || 0;
  const opts = {
    mode: el.modeSelect.value,
    palette: el.palSelect.value,
    remap: remap ? remap.table : null,
    // COMBAT.TBL resolves sprite images per model (combatant sheets).
    banks: banks ? (banks.forModel ? banks.forModel(selectedIndex) : banks.images) : [],
    atlas: groundAtlas,
  };

  let stats = null;
  try {
    const built = buildModel(model, lodIndex, palette.rgb, opts);
    currentGroup = built.group;
    stats = built.stats;
    scene.add(currentGroup);

    const { center, radius } = frameObject(currentGroup, camera, controls);
    axes.scale.setScalar(Math.max(radius, 500) / 1000);
    applyUrlCamera(center);
  } catch (e) {
    fatal(`build model ${selectedIndex}: ${e.message}`);
    return;
  }

  lastStats = stats;
  showModelInfo(model);
  signalReady(`READY ${el.tblSelect.value} #${model.index} ${model.name}`);
}

// ---------------------------------------------------------------- select zone
function selectZone(zone) {
  selectedZone = zone;
  selectedPlacement = -1;
  selectedSpawn = -1;
  selectionActive = false;
  for (const li of el.modelList.querySelectorAll('li')) {
    li.classList.toggle('sel', li.dataset.zone === zone);
  }

  clearCurrentGroup();
  setStatus(`building zone ${zone}…`);

  // Let the status line paint before the (heavy) synchronous build.
  requestAnimationFrame(() => {
    if (view !== 'zones' || selectedZone !== zone) return;
    try {
      const urlTiles = new URLSearchParams(location.search).get('tiles');
      const built = buildZone(archive, zone, {
        mode: el.modeSelect.value,
        palette: el.palSelect.value,
        grid: el.gridChk.checked,
        tiles: urlTiles ? urlTiles.split(',') : undefined,
        spawns: gameData ? gameData.selfSpawns(zone) : [],
      });
      currentGroup = built.group;
      zoneBuild = built;
      scene.add(currentGroup);
      scene.background = built.skyColor || BG_DEFAULT.clone();

      const { center, radius } = frameObject(currentGroup, camera, controls);
      // frameObject's radius-derived near plane is too far out for walking
      // into a town; keep close-up zoom usable.
      camera.near = Math.max(2, radius / 50000);
      camera.updateProjectionMatrix();
      axes.scale.setScalar(Math.max(radius, 500) / 1000);
      applyUrlCamera(center);

      // Scale fly speed to the zone and hand over to the selected nav mode.
      fp.speed = Math.max(8000, Math.round(radius / 12));
      if (el.navSelect.value === 'walk') {
        // Start at street level in the middle of the zone, not the aerial
        // framing position.
        camera.position.set(center.x, fp.eyeHeight, center.z);
      }
      applyNav(el.navSelect.value);

      lastStats = built.stats; // let chapter change re-render the info panel
      buildMarkers();
      buildEncounterMarkers();
      applySpawnVisibility();
      showZoneInfo(built.stats); // re-render with entity/gap counts
      exposeEditor();
      // The entity list needs the built placements; re-render now that they exist.
      if (listMode === 'entities') rebuildList();

      // Auto-select from URL for headless testing / deep links. A selection is
      // {kind:'placement'|'spawn', index}; ?selectat= picks the nearest across
      // both sets.
      const sp = new URLSearchParams(location.search);
      let sel = null;
      const selAt = sp.get('selectat');
      if (selAt) {
        const parts = selAt.split(',').map((v) => parseInt(v, 10));
        if (parts.length === 2 && parts.every((n) => !isNaN(n))) {
          sel = nearestEntity(parts[0], parts[1]);
        }
      }
      const selP = sp.get('select');
      if (!sel && selP !== null) {
        const n = parseInt(selP, 10);
        if (!isNaN(n) && built.placements[n]) sel = { kind: 'placement', index: n };
      }

      // ?rowclick=<i> simulates an Entities-list row click (select + camera
      // move) for headless testing of the browser panel.
      const rowClick = sp.get('rowclick');
      if (rowClick !== null) {
        const n = parseInt(rowClick, 10);
        if (!isNaN(n) && built.placements[n]) sel = { kind: 'placement', index: n };
      }

      // ?hotspot=<zz>,<xx>,<yy>,<idx> : open the inspector on a specific tile
      // hotspot (payload-first view). Takes precedence over entity selection.
      const hsParam = sp.get('hotspot');
      if (hsParam) {
        const parts = hsParam.split(',').map((v) => parseInt(v, 10));
        if (parts.length === 4 && parts.every((n) => !isNaN(n)) && gameData) {
          const [, tx, ty, hi] = parts;
          const list = gameData.hotspotsFor(selectedZone, tx, ty, chapter);
          const hs = list[hi];
          if (hs) {
            showHotspot({ ...hs, tileX: tx, tileY: ty }, gameData);
            selectionActive = true;
            refreshReadyStatus();
            const ec2 = gameData.zoneRecords(selectedZone).length;
            signalReady(`READY zone Z${zone} (${built.stats.instanced} objects) `
              + `ENT#${ec2} HS ${tx},${ty}#${hi}`);
            return;
          }
        }
      }

      let readyTail = '';
      if (sel && sel.kind === 'spawn' && built.spawns[sel.index]) {
        selectSpawn(sel.index);
        readyTail = ` SEL#${sel.index}`;
      } else if (sel && built.placements[sel.index]) {
        if (rowClick !== null) selectEntityRow(sel.index);
        else selectPlacement(sel.index);
        readyTail = ` SEL#${sel.index}`;
      }
      const ec = gameData && selectedZone ? gameData.zoneRecords(selectedZone).length : 0;
      signalReady(`READY zone Z${zone} (${built.stats.instanced} objects) ENT#${ec}` + readyTail);
    } catch (e) {
      fatal(`build zone ${zone}: ${e.message}`);
    }
  });
}

// ---------------------------------------------------------------- editor layer

/** Build the entity join for a placement index in the current zone. */
function buildEntity(index) {
  if (!zoneBuild) return null;
  const p = zoneBuild.placements[index];
  if (!p) return null;
  const model = table && table.models[p.id] ? table.models[p.id] : null;
  const tileX = worldToTile(p.worldX);
  const tileY = worldToTile(p.worldY);

  let state = null;
  let hotspots = [];
  if (gameData) {
    state = gameData.stateFor(selectedZone, p.worldX, p.worldY);
    hotspots = gameData.hotspotsFor(selectedZone, tileX, tileY, chapter);
  }

  return {
    index,
    zone: selectedZone,
    placement: { id: p.id, variant: p.variant, w0: p.w0, rotZ: p.rotZ, x: p.worldX, y: p.worldY },
    model,
    tblName: `Z${selectedZone}.TBL`,
    tileFile: p.tileFile,
    tileX,
    tileY,
    state,
    hotspots,
    chapter,
  };
}

/**
 * Build the entity join for a self-spawned object. Unlike a placement, its
 * visual + State are one and the same record; the entity carries a `spawn`
 * descriptor so the inspector renders a "Spawn" section in place of Placement.
 */
function buildSpawnEntity(index) {
  if (!zoneBuild || !zoneBuild.spawns) return null;
  const s = zoneBuild.spawns[index];
  if (!s) return null;
  const model = table && table.models[s.shapeId] ? table.models[s.shapeId] : null;
  const tileX = worldToTile(s.worldX);
  const tileY = worldToTile(s.worldY);
  const state = { source: s.source, offset: s.offset, record: s.record };
  const hotspots = gameData
    ? gameData.hotspotsFor(selectedZone, tileX, tileY, chapter) : [];

  return {
    index,
    zone: selectedZone,
    spawn: {
      shapeId: s.shapeId,
      x: s.worldX,
      y: s.worldY,
      chapterMin: s.chapterMin,
      chapterMax: s.chapterMax,
      source: s.source,
      offset: s.offset,
    },
    model,
    tblName: `Z${selectedZone}.TBL`,
    tileX,
    tileY,
    state,
    hotspots,
    chapter,
  };
}

/** Replace the selection highlight box around an instance group. */
function highlightInstance(instanceGroup) {
  if (selectionHelper) {
    if (selectionHelper.parent) selectionHelper.parent.remove(selectionHelper);
    disposeGroup(selectionHelper);
    selectionHelper = null;
  }
  selectionHelper = new THREE.BoxHelper(instanceGroup, 0xffd54a);
  selectionHelper.material.depthTest = false;
  selectionHelper.renderOrder = 999;
  currentGroup.add(selectionHelper);
  selectionHelper.update();
}

/** Highlight + inspect a placement by index. */
function selectPlacement(index) {
  if (!zoneBuild) return;
  const p = zoneBuild.placements[index];
  if (!p) return;

  highlightInstance(p.instanceGroup);
  selectedPlacement = index;
  selectedSpawn = -1;
  syncEntityRowSelection('placement', index);

  const entity = buildEntity(index);
  if (entity) { showEntity(entity, gameData); selectionActive = true; refreshReadyStatus(); }
}

/** Highlight + inspect a self-spawned object by index. */
function selectSpawn(index) {
  if (!zoneBuild || !zoneBuild.spawns) return;
  const s = zoneBuild.spawns[index];
  if (!s) return;

  highlightInstance(s.instanceGroup);
  selectedSpawn = index;
  selectedPlacement = -1;
  syncEntityRowSelection('spawn', index);

  const entity = buildSpawnEntity(index);
  if (entity) { showEntity(entity, gameData); selectionActive = true; refreshReadyStatus(); }
}

/**
 * Reflect the current selection in the Entities list: highlight the matching
 * row and scroll it into view. `kind` is 'placement' or 'spawn' (spawn indices
 * overlap placement indices, so both key parts must match). No-op unless the
 * entity list is showing.
 */
function syncEntityRowSelection(kind, index) {
  if (view !== 'zones' || listMode !== 'entities') return;
  let selRow = null;
  for (const li of el.modelList.querySelectorAll('li[data-index]')) {
    const on = Number(li.dataset.index) === index
      && (li.dataset.kind || 'placement') === kind;
    li.classList.toggle('sel', on);
    if (on) selRow = li;
  }
  if (selRow && selRow.scrollIntoView) {
    selRow.scrollIntoView({ block: 'nearest' });
  }
}

/**
 * Nearest entity to a world coordinate across BOTH placements and self-spawns
 * (for ?selectat=). Returns {kind:'placement'|'spawn', index} or null.
 */
function nearestEntity(x, y) {
  if (!zoneBuild) return null;
  let best = null;
  let bestD = Infinity;
  for (const p of zoneBuild.placements) {
    const dx = p.worldX - x;
    const dy = p.worldY - y;
    const d = dx * dx + dy * dy;
    if (d < bestD) { bestD = d; best = { kind: 'placement', index: p.index }; }
  }
  for (const s of zoneBuild.spawns || []) {
    const dx = s.worldX - x;
    const dy = s.worldY - y;
    const d = dx * dx + dy * dy;
    if (d < bestD) { bestD = d; best = { kind: 'spawn', index: s.index }; }
  }
  return best;
}

/**
 * Build the "Data" markers cloud: gold points at entities that carry a state
 * record, red points at hotspot bbox centers for the current chapter. Drawn on
 * top (depthTest off); rebuilt on chapter change without a zone rebuild.
 */
function buildMarkers() {
  if (markersGroup) {
    if (markersGroup.parent) markersGroup.parent.remove(markersGroup);
    disposeGroup(markersGroup);
    markersGroup = null;
  }
  if (!zoneBuild) return;
  const cx = zoneBuild.center.x;
  const cy = zoneBuild.center.y;

  const pos = [];
  const col = [];
  const gold = [1.0, 0.82, 0.25];
  const red = [1.0, 0.30, 0.30];

  if (gameData) {
    // Gold: placements with a joined state record.
    for (const p of zoneBuild.placements) {
      const st = gameData.stateFor(selectedZone, p.worldX, p.worldY);
      if (!st) continue;
      pos.push(p.worldX - cx, p.worldY - cy, 400);
      col.push(...gold);
    }
    // Red: hotspot bbox centers per tile for the current chapter. tileOrigin +
    // subcell*1600 average (40 subcells across a 64000-unit tile).
    const T = 64000;
    for (const name of archive.names()) {
      const m = name.match(/^T(\d\d)(\d\d)(\d\d)\.DAT$/);
      if (!m || m[1] !== String(selectedZone).padStart(2, '0')) continue;
      const tileX = parseInt(m[2], 10);
      const tileY = parseInt(m[3], 10);
      const list = gameData.hotspotsFor(selectedZone, tileX, tileY, chapter);
      for (const hs of list) {
        const midX = (hs.bboxMinX + hs.bboxMaxX) / 2;
        const midY = (hs.bboxMinY + hs.bboxMaxY) / 2;
        const wx = tileX * T + midX * 1600;
        const wy = tileY * T + midY * 1600;
        pos.push(wx - cx, wy - cy, 400);
        col.push(...red);
      }
    }
  }

  if (!pos.length) return;
  const geo = new THREE.BufferGeometry();
  geo.setAttribute('position', new THREE.Float32BufferAttribute(pos, 3));
  geo.setAttribute('color', new THREE.Float32BufferAttribute(col, 3));
  const mat = new THREE.PointsMaterial({
    size: 1400, sizeAttenuation: true, vertexColors: true,
    depthTest: false, transparent: true,
  });
  markersGroup = new THREE.Points(geo, mat);
  markersGroup.name = 'dataMarkers';
  markersGroup.renderOrder = 998;
  markersGroup.visible = el.dataChk.checked;
  currentGroup.add(markersGroup);
}

/** Color for a hotspot's trigger rectangle, by kind. */
function hotspotRectColor(kind) {
  if (kind === 1) return 0xd83a3a; // combat: red
  if (kind === 7) return 0xdd8a26; // trap: orange
  return 0x5a7088; // everything else: neutral blue-gray
}

/**
 * Local ground z under a group-local (lx,ly): raycast straight down the group's
 * own vertical (BaK z) axis through the zone geometry and take the LOWEST mesh
 * surface (the walkable floor — a dungeon corridor floor sits below its roof,
 * and the materials are Back/DoubleSide so a descending ray also reports the
 * roof triangles); 0 if nothing is below. `lx`,`ly` are the marker's local
 * offsets (worldX-cx, worldY-cy), the same frame the overlay meshes live in.
 *
 * The zone root is rotated -90 deg about X (BaK z-up -> three y-up), so the
 * group's vertical axis is NOT world z. We therefore cast in the group's LOCAL
 * frame — transforming a local down-ray through group.matrixWorld to raycast in
 * world space, then reading each hit back into local space to compare z.
 *
 * Results are cached per sub-cell (1600 units). MUST be called before the
 * overlay meshes are added to currentGroup so the cast never hits the overlay's
 * own geometry (zoneBuild.group IS currentGroup). Caller must have refreshed the
 * group's world matrices (updateMatrixWorld) — the raycaster does not do it.
 */
const floorZCache = new Map();
function floorZAt(x, y) {
  const cx = zoneBuild.center.x;
  const cy = zoneBuild.center.y;
  const lx = x - cx;
  const ly = y - cy;
  const key = Math.round(lx / 1600) + ',' + Math.round(ly / 1600);
  const cached = floorZCache.get(key);
  if (cached !== undefined) return cached;
  const g = zoneBuild.group;
  // Local down-ray (BaK z is up): origin high above, direction -z. Transform to
  // world through the group's matrix so the raycast runs in world space.
  const origin = new THREE.Vector3(lx, ly, 100000).applyMatrix4(g.matrixWorld);
  const dir = new THREE.Vector3(0, 0, -1)
    .transformDirection(g.matrixWorld).normalize();
  const rc = new THREE.Raycaster(origin, dir);
  // Ground is Mesh geometry; a camera is only needed so sprite billboards in
  // the group don't throw during traversal (we ignore sprite/line/point hits).
  rc.camera = camera;
  const hits = rc.intersectObject(g, true);
  const p = new THREE.Vector3();
  let z = 0;
  let found = false;
  for (const h of hits) {
    if (!h.object.visible || !h.object.isMesh) continue;
    // Read the hit back into the group's local frame to get BaK z.
    const lz = g.worldToLocal(p.copy(h.point)).z;
    if (!found || lz < z) { z = lz; found = true; }
  }
  floorZCache.set(key, z);
  return z;
}

/**
 * Encounter overlay for the current chapter, under the "encounter markers" Data
 * control. Real floor-anchored geometry (raycast down onto the zone to find
 * local ground z), rendered as a two-pass editor "X-ray": a depth-tested
 * visible pass where the marker is directly seen, plus an inverted-depth
 * (GreaterDepth) ghost pass that draws only the occluded fragments, so markers
 * inside dungeon rooms stay dimly visible through walls/ceilings. Both passes
 * render after all zone geometry (renderOrder 100-102 > zone's <= ~50) so
 * transparent-pass sort order can never garble them.
 * Three layers built together and disposed together:
 *  - encounterMarkers: a Group of small solid spheres — one per live combatant
 *    of every kind-1 (combat) / kind-7 (trap) tile hotspot, plus one per
 *    click-source object. Each sphere's index parallels encounterHotspots.
 *  - encounterRects: a translucent 3D box over EVERY tile hotspot's bbox
 *    sub-cell rect (any kind), rising floorZ+BOX_LIFT..floorZ+BOX_H (sized to
 *    fit inside dungeon corridors) with a depth-tested edge outline; clicking a
 *    box opens the owning hotspot (encounterRectHotspots parallels the group's
 *    child order).
 *  - encounterLinks: for kind-7/8 hotspots fired by CLICKING a fixed object
 *    (gamedata hotspotClickSource), a depth-tested line from the object to its
 *    bbox key rect (at floorZ+LINK_Z on each end); the object itself gets a
 *    sphere in encounterMarkers.
 * Chapter-gated (rebuilt on chapter change).
 */
function buildEncounterMarkers() {
  if (encounterMarkers) {
    if (encounterMarkers.parent) encounterMarkers.parent.remove(encounterMarkers);
    disposeGroup(encounterMarkers);
    encounterMarkers = null;
  }
  if (encounterRects) {
    if (encounterRects.parent) encounterRects.parent.remove(encounterRects);
    disposeGroup(encounterRects);
    encounterRects = null;
  }
  if (encounterLinks) {
    if (encounterLinks.parent) encounterLinks.parent.remove(encounterLinks);
    disposeGroup(encounterLinks);
    encounterLinks = null;
  }
  encounterHotspots = [];
  encounterRectHotspots = [];
  if (!zoneBuild || !gameData) return;
  // Refresh world matrices once: the group was just built and added to the
  // scene without a render yet, so children's matrixWorld are still identity;
  // THREE.Raycaster does not update them, so every floorZAt ray would miss.
  zoneBuild.group.updateMatrixWorld(true);
  floorZCache.clear();
  const cx = zoneBuild.center.x;
  const cy = zoneBuild.center.y;
  const T = 64000;
  const SUB = 1600;
  const combatColor = 0xd83a3a; // red
  const trapColor = 0xdd8a26;   // orange
  // Marker dimensions are sized to the DUNGEON interior: mine corridor/room
  // models span local z 1..451 (~450-unit clearance; walk eye height is 230),
  // so everything must top out well under 451 or it pokes through the roofs
  // and is visible from outside, defeating the depth-tested design.
  const BOX_LIFT = 5;    // box bottom above floorZ (avoids floor z-fighting)
  const BOX_H = 340;     // box top above floorZ (~0.75 x corridor clearance)
  const SPHERE_R = 120;  // marker sphere radius; center sits at floorZ+SPHERE_R
  const LINK_Z = 280;    // link-line height above floorZ on both endpoints

  // X-ray ghost pass: per marker, a second mesh/line sharing the SAME geometry
  // drawn with depth testing OFF — an always-visible overlay hint so markers
  // inside dungeon rooms read through walls/ceilings on any GPU/depth setup.
  // Same-color ghost-over-visible blends benignly (the visible pass already
  // painted those fragments the same hue). Materials are shared per
  // role+color; renderOrder 101 (ghost fill) / 102 (ghost edges/spheres/
  // lines) puts every ghost after ALL zone geometry (<= ~50) so
  // transparent-pass sort order can never garble the pass.
  const ghostMats = new Map();
  const ghostMatFor = (role, color) => {
    const key = role + ':' + color;
    let mat = ghostMats.get(key);
    if (mat) return mat;
    const common = {
      color, transparent: true, depthWrite: false, depthTest: false,
    };
    if (role === 'fill') {
      mat = new THREE.MeshBasicMaterial(
        { ...common, opacity: 0.18, side: THREE.DoubleSide });
    } else if (role === 'sphere') {
      mat = new THREE.MeshBasicMaterial({ ...common, opacity: 0.55 });
    } else { // 'edge' | 'link'
      mat = new THREE.LineBasicMaterial(
        { ...common, opacity: role === 'edge' ? 0.85 : 0.55 });
    }
    ghostMats.set(key, mat);
    return mat;
  };

  // Spheres (combatant spawns + click-source dots) share one group; the boxes
  // and link lines their own. All meshes are built here — with their floor-z
  // raycasts against zoneBuild.group — and only added to currentGroup at the
  // end, so the casts never hit the overlay's own geometry.
  const spheres = new THREE.Group();
  spheres.name = 'encounterMarkers';
  const rects = new THREE.Group();
  rects.name = 'encounterRects';
  const links = new THREE.Group();
  links.name = 'encounterLinks';
  // CRITICAL: three sorts render items by the nearest ancestor GROUP's
  // renderOrder (groupOrder) BEFORE the item's own renderOrder, and zone.js
  // sets renderOrder on the zone instance Groups (layers 1..~9). At group
  // order 0 the overlay's transparent fills draw FIRST and the zone's
  // depth-writing alphaTest quads (the dungeon's textured floors/walls)
  // overwrite them — fills vanish wherever such a quad is behind them. Lift
  // the whole overlay to groupOrder 100 so it draws after all zone geometry;
  // the per-mesh renderOrders (100/101/102) then order passes within it.
  spheres.renderOrder = 100;
  rects.renderOrder = 100;
  links.renderOrder = 100;

  const sphereGeo = new THREE.SphereGeometry(SPHERE_R, 12, 8);

  const urlTiles = new URLSearchParams(location.search).get('tiles');
  const tileFilter = urlTiles ? new Set(urlTiles.split(',')) : null;

  for (const name of archive.names()) {
    const m = name.match(/^T(\d\d)(\d\d)(\d\d)\.DAT$/);
    if (!m || m[1] !== String(selectedZone).padStart(2, '0')) continue;
    if (tileFilter && !tileFilter.has(m[2] + m[3])) continue;
    const tileX = parseInt(m[2], 10);
    const tileY = parseInt(m[3], 10);
    const list = gameData.hotspotsFor(selectedZone, tileX, tileY, chapter);
    for (const hs of list) {
      // Trigger-region box spanning the bbox sub-cell rect (any kind), rising
      // from the local floor so it reads as a real 3D volume.
      const x0 = tileX * T + hs.bboxMinX * SUB;
      const x1 = tileX * T + (hs.bboxMaxX + 1) * SUB;
      const y0 = tileY * T + hs.bboxMinY * SUB;
      const y1 = tileY * T + (hs.bboxMaxY + 1) * SUB;
      const w = x1 - x0;
      const h = y1 - y0;
      if (w > 0 && h > 0) {
        const rectCx = (x0 + x1) / 2;
        const rectCy = (y0 + y1) / 2;
        const floorZ = floorZAt(rectCx, rectCy);
        const z0 = floorZ + BOX_LIFT;
        const z1 = floorZ + BOX_H;
        const boxGeo = new THREE.BoxGeometry(w, h, z1 - z0);
        const boxMat = new THREE.MeshBasicMaterial({
          color: hotspotRectColor(hs.kind), transparent: true, opacity: 0.30,
          depthWrite: false, side: THREE.DoubleSide,
        });
        const mesh = new THREE.Mesh(boxGeo, boxMat);
        // The zone's textured wall/ceiling quads are alphaTest transparents
        // that WRITE depth and render at renderOrder <= ~50 (layer lifts + the
        // grid). This no-depth-write fill must draw AFTER all of them so its
        // occlusion comes from the depth buffer, not transparent-pass sort
        // order — otherwise a farther wall drawn later paints over the fill.
        // 100 stays below the deliberately depth-ignoring Data markers (998)
        // and selection helper (999). The edge-outline child keeps order 0.
        mesh.renderOrder = 100;
        mesh.position.set(rectCx - cx, rectCy - cy, (z0 + z1) / 2);
        // Depth-tested edge outline as a child of the box.
        const edgeGeo = new THREE.EdgesGeometry(boxGeo);
        const edges = new THREE.LineSegments(
          edgeGeo,
          new THREE.LineBasicMaterial({ color: hotspotRectColor(hs.kind) }),
        );
        mesh.add(edges);
        // Ghost pass (occluded fragments only) reusing the same geometries.
        const ghostFill = new THREE.Mesh(
          boxGeo, ghostMatFor('fill', hotspotRectColor(hs.kind)));
        ghostFill.renderOrder = 101;
        mesh.add(ghostFill);
        const ghostEdges = new THREE.LineSegments(
          edgeGeo, ghostMatFor('edge', hotspotRectColor(hs.kind)));
        ghostEdges.renderOrder = 102;
        mesh.add(ghostEdges);
        rects.add(mesh);
        encounterRectHotspots.push({ hotspot: { ...hs, tileX, tileY } });
      }

      // Click-source link: a kind-7/8 hotspot fired by clicking a fixed object
      // (WCURSOR.C -> hotspotevt_dispatch_at_point). The bbox is then a
      // dispatch key, often parked on unreachable terrain; mark the object
      // that actually fires it and tie the two together with a line.
      const src = gameData.hotspotClickSource(hs);
      if (src) {
        const srcFloorZ = floorZAt(src.worldX, src.worldY);
        const dot = new THREE.Mesh(sphereGeo, new THREE.MeshBasicMaterial({
          color: hotspotRectColor(hs.kind),
        }));
        dot.position.set(src.worldX - cx, src.worldY - cy, srcFloorZ + SPHERE_R);
        const ghostDot = new THREE.Mesh(
          sphereGeo, ghostMatFor('sphere', hotspotRectColor(hs.kind)));
        ghostDot.renderOrder = 102;
        dot.add(ghostDot);
        spheres.add(dot);
        encounterHotspots.push({
          hotspot: { ...hs, tileX, tileY },
          worldX: src.worldX, worldY: src.worldY,
        });
        const bboxCx = (x0 + x1) / 2;
        const bboxCy = (y0 + y1) / 2;
        const bboxFloorZ = floorZAt(bboxCx, bboxCy);
        const lgeo = new THREE.BufferGeometry().setFromPoints([
          new THREE.Vector3(src.worldX - cx, src.worldY - cy, srcFloorZ + LINK_Z),
          new THREE.Vector3(bboxCx - cx, bboxCy - cy, bboxFloorZ + LINK_Z),
        ]);
        const line = new THREE.Line(lgeo, new THREE.LineBasicMaterial({
          color: hotspotRectColor(hs.kind), transparent: true, opacity: 0.6,
        }));
        const ghostLine = new THREE.Line(
          lgeo, ghostMatFor('link', hotspotRectColor(hs.kind)));
        ghostLine.renderOrder = 102;
        line.add(ghostLine);
        links.add(line);
      }

      // Combatant spawn points (kind 1/7 only).
      if (hs.kind !== 1 && hs.kind !== 7) continue;
      const def = gameData.defRecordDecoded(hs.kind, hs.defRecordIndex);
      if (!def || !def.fields) continue;
      const fv = (nm) => { const f = def.fields.find((x) => x.name === nm); return f ? f.value : 0; };
      const n = fv('numEnemies');
      const color = hs.kind === 7 ? trapColor : combatColor;
      for (let i = 0; i < Math.min(n, 7); i++) {
        const wx = tileX * T + fv(`comb${i}.posX`);
        const wy = tileY * T + fv(`comb${i}.posY`);
        const floorZ = floorZAt(wx, wy);
        const dot = new THREE.Mesh(sphereGeo, new THREE.MeshBasicMaterial({ color }));
        dot.position.set(wx - cx, wy - cy, floorZ + SPHERE_R);
        const ghostDot = new THREE.Mesh(sphereGeo, ghostMatFor('sphere', color));
        ghostDot.renderOrder = 102;
        dot.add(ghostDot);
        spheres.add(dot);
        encounterHotspots.push({ hotspot: { ...hs, tileX, tileY }, worldX: wx, worldY: wy });
      }
    }
  }

  if (rects.children.length) {
    rects.visible = el.encChk.checked;
    encounterRects = rects;
    currentGroup.add(rects);
  }
  if (links.children.length) {
    links.visible = el.encChk.checked;
    encounterLinks = links;
    currentGroup.add(links);
  }
  if (spheres.children.length) {
    spheres.visible = el.encChk.checked;
    encounterMarkers = spheres;
    currentGroup.add(spheres);
  } else {
    sphereGeo.dispose(); // shared geo unused if no spheres were built
  }
}

/**
 * Toggle each self-spawned instance's visibility for the active chapter
 * (chapterMin <= chapter <= chapterMax). A visibility flip only — never a zone
 * rebuild — so it is cheap to call on chapter change.
 */
function applySpawnVisibility() {
  if (!zoneBuild || !zoneBuild.spawns) return;
  for (const s of zoneBuild.spawns) {
    s.instanceGroup.visible = chapter >= s.chapterMin && chapter <= s.chapterMax;
  }
}

/** Count of self-spawned objects visible in the active chapter. */
function spawnVisibleCount() {
  if (!zoneBuild || !zoneBuild.spawns) return 0;
  let n = 0;
  for (const s of zoneBuild.spawns) {
    if (chapter >= s.chapterMin && chapter <= s.chapterMax) n++;
  }
  return n;
}

/** Raycast a canvas click into the zone group; select the hit placement/spawn. */
function pickAt(clientX, clientY) {
  if (view !== 'zones' || !zoneBuild || document.pointerLockElement) return;
  const rect = renderer.domElement.getBoundingClientRect();
  pickNdc.x = ((clientX - rect.left) / rect.width) * 2 - 1;
  pickNdc.y = -((clientY - rect.top) / rect.height) * 2 + 1;
  raycaster.setFromCamera(pickNdc, camera);

  // Encounter markers first: a Group of spheres; the hit sphere's index in the
  // group's children maps back to its owning hotspot (encounterHotspots
  // parallels child order).
  if (encounterMarkers && encounterMarkers.visible && encounterHotspots.length) {
    const mh = raycaster.intersectObject(encounterMarkers, true);
    if (mh.length) {
      // The hit may be the sphere or its X-ray ghost child; map either to the
      // top-level dot whose index parallels encounterHotspots.
      let hitObj = mh[0].object;
      while (hitObj && hitObj.parent !== encounterMarkers) hitObj = hitObj.parent;
      const idx = hitObj ? encounterMarkers.children.indexOf(hitObj) : -1;
      const owner = idx >= 0 ? encounterHotspots[idx] : null;
      if (owner) {
        showHotspot(owner.hotspot, gameData);
        selectionActive = true;
        refreshReadyStatus();
        return;
      }
    }
  }

  // Trigger-region boxes: clicking one opens its owning hotspot. Checked after
  // the marker spheres but before world geometry so a box over open ground is
  // still reachable.
  if (encounterRects && encounterRects.visible && encounterRectHotspots.length) {
    const rh = raycaster.intersectObject(encounterRects, true);
    if (rh.length) {
      // The hit may be the box mesh or its edge-line child; map either to the
      // top-level box whose index parallels encounterRectHotspots.
      let hitObj = rh[0].object;
      while (hitObj && hitObj.parent !== encounterRects) hitObj = hitObj.parent;
      const idx = hitObj ? encounterRects.children.indexOf(hitObj) : -1;
      const owner = idx >= 0 ? encounterRectHotspots[idx] : null;
      if (owner) {
        showHotspot(owner.hotspot, gameData);
        selectionActive = true;
        refreshReadyStatus();
        return;
      }
    }
  }

  const hits = raycaster.intersectObject(currentGroup, true);
  for (const h of hits) {
    // Walk up to the instance group that carries a placementIndex/spawnIndex.
    let o = h.object;
    while (o && o.userData.placementIndex === undefined
      && o.userData.spawnIndex === undefined) o = o.parent;
    if (!o) continue;
    if (o.userData.placementIndex !== undefined) {
      selectPlacement(o.userData.placementIndex);
      return;
    }
    if (o.userData.spawnIndex !== undefined) {
      selectSpawn(o.userData.spawnIndex);
      return;
    }
  }
}

/**
 * Dev-only synthetic-input harness for headless validation (no real touchpad
 * in --headless). Dispatches PointerEvents / WheelEvents on the canvas and
 * reports the camera state the handlers produced. Harmless in production; only
 * exercises the same public paths a user's touchpad would.
 */
function exposeFpTest() {
  const cv = renderer.domElement;
  const rect = () => cv.getBoundingClientRect();
  const snap = () => ({
    yaw: fp.yaw, pitch: fp.pitch, speed: fp.speed,
    pos: camera.position.toArray(),
    selectionActive,
  });
  const pev = (type, x, y, button, extra) => cv.dispatchEvent(
    new PointerEvent(type, {
      pointerId: 1, pointerType: 'mouse', button, buttons: button === 0 ? 1 : 0,
      clientX: x, clientY: y, bubbles: true, cancelable: true, ...(extra || {}),
    }));
  const mev = (type, x, y, button) => cv.dispatchEvent(
    new MouseEvent(type, {
      button, clientX: x, clientY: y, bubbles: true, cancelable: true,
    }));

  window.__fpTest = {
    snap,
    /** Synthetic left-drag from (x,y) by (dx,dy) in `steps`. Returns before/after. */
    drag(dx = 200, dy = 0, steps = 4) {
      const r = rect();
      const x0 = r.left + r.width / 2;
      const y0 = r.top + r.height / 2;
      const before = snap();
      pev('pointerdown', x0, y0, 0);
      for (let i = 1; i <= steps; i++) {
        pev('pointermove', x0 + (dx * i) / steps, y0 + (dy * i) / steps, 0);
      }
      pev('pointerup', x0 + dx, y0 + dy, 0);
      return { before, after: snap(), dragLooked: fp.dragLooked };
    },
    /** Synthetic sub-threshold click (press+release+click) at the canvas center. */
    click() {
      const r = rect();
      const x = r.left + r.width / 2;
      const y = r.top + r.height / 2;
      const before = snap();
      pev('pointerdown', x, y, 0);
      mev('mousedown', x, y, 0);
      pev('pointerup', x, y, 0);
      mev('mouseup', x, y, 0);
      mev('click', x, y, 0);
      return { before, after: snap(), dragLooked: fp.dragLooked };
    },
    /** Synthetic wheel; ctrl=true simulates a pinch (dolly). */
    wheel(deltaY = 120, ctrl = false, deltaMode = 0) {
      const r = rect();
      const before = snap();
      cv.dispatchEvent(new WheelEvent('wheel', {
        deltaY, deltaMode, ctrlKey: ctrl, bubbles: true, cancelable: true,
        clientX: r.left + r.width / 2, clientY: r.top + r.height / 2,
      }));
      return { before, after: snap() };
    },
  };
}

/** Publish the headless testing hook. */
function exposeEditor() {
  window.__editor = {
    selectPlacement,
    selectSpawn,
    get spawnCount() { return zoneBuild && zoneBuild.spawns ? zoneBuild.spawns.length : 0; },
    get entityCount() {
      if (!gameData || !selectedZone) return 0;
      return gameData.zoneRecords(selectedZone).length;
    },
    get gapCount() {
      if (!gameData || !selectedZone) return 0;
      return gameData.gaps(selectedZone).length;
    },
    get chapter() { return chapter; },
    get placements() { return zoneBuild ? zoneBuild.placements.length : 0; },
    get listMode() { return listMode; },
    setListMode,
    selectEntityRow,
  };
}

// ---------------------------------------------------------------- dialog tab
//
// A third top-level view over the DDX dialog graph (dialog.js DialogDb). The
// sidebar lists Conversations / Keyword web / Popups; selecting a row loads a
// component (or a hub neighborhood for the giant web) onto the SVG canvas
// (dialoggraph.js). A breadcrumb bar tracks drill-in navigation; the right panel
// inspects the selected node.

let dialogDb = null;            // DialogDb (built once, lazily)
// The two DialogView controllers (dialogview.js). Both wrap one DialogGraph and
// carry their OWN per-view state (spec / selection / crumbs); they differ only
// by host elements + the `modal` flag, and SHARE the cross-view settings in
// `dlgSettings` (layout preset / chapter / dev-paths / tune). Created lazily on
// first dialog use / first overlay open.
let dialogFull = null;          // fullscreen DIALOG tab view (modal:false)
let dialogOverlay = null;       // floating overlay view (modal:true)
// The viewer's default layout preset (elklayout.js PRESETS). Its orthogonal
// edge routing reads conversations more clearly than plain 'layered'; it is the
// preset that adds no ` LAYOUT:` tag to the READY line (any OTHER preset tags).
const DLG_DEFAULT_LAYOUT = 'layered-ortho';
// dlgSettings.chapter default = null (unfiltered/all): the fullscreen AND
// overlay views open unfiltered by default; ?chapter=N forces N (seeded at boot).
// dlgSettings.showDev is seeded from localStorage below, then ?dev=1 may override.
dlgSettings.layoutPreset = DLG_DEFAULT_LAYOUT;
const DLG_SHOWDEV_LS_KEY = 'bakDlgShowDev';
dlgSettings.showDev = (() => {
  try { return localStorage.getItem(DLG_SHOWDEV_LS_KEY) === '1'; } catch (_) { return false; }
})();
let dlgPresetNames = PRESET_ORDER.slice(); // presets shown in the toolbar dropdown
let dlgPresetsProbed = false;    // true once availablePresets() has pruned dlgPresetNames

/**
 * One-time probe of the bundled elkjs build: drop any PRESET whose ELK algorithm
 * is absent, then rebuild the toolbar so the dropdown lists only usable presets.
 * Best-effort and idempotent; failures leave the full PRESET_ORDER.
 */
async function probeLayoutPresets() {
  if (dlgPresetsProbed) return;
  dlgPresetsProbed = true;
  try {
    const elk = await loadElk();
    const { names, dropped } = await availablePresets(elk);
    dlgPresetNames = names;
    window.__dlgDroppedPresets = dropped;
    fillLayoutOptions(el.dlgOvlLayout);
    if (dialogFull) dialogFull.renderHeader();
  } catch (_) { /* keep the full list */ }
}

const POPUP_PAGE = 60;          // popup rows rendered per "show more" page
let popupShown = POPUP_PAGE;    // how many popups are currently listed
const dlgGroupState = { conv: false, kw: false, popup: true }; // collapsed?

/** Lazily build (or return) the dialog DB via the game-data join. */
function ensureDialogDb() {
  if (dialogDb) return dialogDb;
  if (!gameData) return null;
  dialogDb = gameData.dialogDb();
  return dialogDb;
}

/**
 * The shared dependency bundle handed to every DialogView: the DB accessor, the
 * pure view-choice + inspector + status helpers that already live in main.js,
 * and the per-view header/inspector/modal hooks (dispatched on view.modal). One
 * bundle instance serves both views.
 */
function makeDialogDeps() {
  return {
    db: () => dialogDb,
    dialogViewForNode,
    renderInspector: (host, node, cb) => renderDlgInspectorInto(host, node, cb),
    hideInspector: (v) => { if (v.modal) hideOverlayInsp(); else hideDlgInspector(); },
    renderTabHeader: () => renderCrumbs(),
    renderOverlayHeader: () => renderOverlayHeader(),
    showModal: () => showDialogOverlay(),
    hideModal: () => hideDialogOverlay(),
    onStatus: (text) => { if (text) setStatus(text); else refreshReadyStatus(); },
    onReady: (v) => { if (!v.modal) updateDialogReady(); else refreshReadyStatus(); },
  };
}

/** Lazily construct the fullscreen + overlay DialogViews (once). */
function ensureDialogViews() {
  if (dialogFull) return;
  const deps = makeDialogDeps();
  dialogFull = new DialogView({
    host: el.dlgCanvasHost, headerEl: el.dlgCrumbs, inspectorEl: el.dlgInspector,
    emptyEl: el.dlgEmpty, modal: false, deps,
  }).register();
  dialogOverlay = new DialogView({
    host: el.dlgOvlCanvasHost, headerEl: el.dlgOvlHeader, inspectorEl: el.dlgOvlInsp,
    modal: true, deps,
  }).register();
  wireOverlayControls();
  window.addEventListener('resize', () => {
    if (view === 'dialog' && dialogFull) dialogFull.fit();
    if (dialogOverlay && dialogOverlay.open_) dialogOverlay.fit();
  });
}

/** Enter the dialog view: build the canvas + sidebar, then honor URL/opts. */
function enterDialogView(opts = {}) {
  const db = ensureDialogDb();
  if (!db) {
    el.dialogSidebar.innerHTML = '<div class="demptyhits">dialog data unavailable (game data not loaded)</div>';
    signalReady('READY DLG 0 comps 0 nodes');
    return;
  }
  ensureDialogViews();
  dialogFull._syncInset();
  rebuildDialogSidebar();
  exposeDialog();
  wireTuneOutsideClose();
  probeLayoutPresets();

  // Resolve URL/opts intent: ?key=<K> [&hub=<K>] or an in-page request. The
  // layout / chapter / dev params seed the SHARED settings (dlgSettings) so both
  // views open under them.
  const sp = new URLSearchParams(location.search);
  // ?layout=<presetName> selects the layout preset before the first view
  // renders. Legacy alias: ?layout=elk maps to the default ELK preset.
  const layoutParam = opts.layout !== undefined ? opts.layout : sp.get('layout');
  if (layoutParam === 'elk') dlgSettings.layoutPreset = DEFAULT_PRESET;
  else if (layoutParam && PRESETS[layoutParam]) dlgSettings.layoutPreset = layoutParam;
  // An explicit ?layout= (or opts.layout) seeds BOTH views' per-view preset;
  // absent, each view keeps its own.
  if (layoutParam) {
    if (dialogFull) dialogFull.layoutPreset = dlgSettings.layoutPreset;
    if (dialogOverlay) dialogOverlay.layoutPreset = dlgSettings.layoutPreset;
  }
  // ?chapter=<N> (1..10) deep-links the chapter filter before the first view
  // renders; 'all' / absent / out-of-range = no filter (the default).
  const chapterParam = opts.chapter !== undefined ? opts.chapter : sp.get('chapter');
  if (chapterParam != null && chapterParam !== 'all') {
    const cn = parseInt(chapterParam, 10);
    dlgSettings.chapter = (!isNaN(cn) && cn >= 1 && cn <= 10) ? cn : null;
  }
  // ?dev=1 starts with the developer PAGE_THRU paging edges shown (also persists
  // the flag, so it survives reloads like a manual toggle would).
  const devParam = opts.dev !== undefined ? opts.dev : sp.get('dev');
  if (devParam != null && devParam !== '0' && devParam !== 'false') setDlgShowDev(true);
  const key = opts.key !== undefined ? opts.key : sp.get('key');
  const hub = opts.hub !== undefined ? opts.hub : sp.get('hub');
  if (hub) {
    dialogFull.openHub(hub, { select: hub });
  } else if (key) {
    dialogFull.openByKey(parseInt(key, 10));
  } else if (dialogFull.spec !== null) {
    // Returning to the tab: keep the current view.
    dialogFull.fit();
    updateDialogReady();
  } else {
    // Default landing: the largest non-giant conversation, scoped to its root's
    // forward closure (same scoping every conversation-open uses).
    const comp = db.components.find((c) => c.id !== 0 && c.size > 1);
    const startId = comp ? firstSelectable(comp) : null;
    if (startId) dialogFull.openForward(startId, { select: startId });
    else updateDialogReady();
  }
}

/** The DDX-provenance chip set for a component (from its external roots). */
function compProvChips(comp) {
  const kinds = new Set(comp.roots.map((r) => r.kind));
  const chips = [];
  if (kinds.has('object')) chips.push(['OBJ', 'obj']);
  if (kinds.has('hotspot')) chips.push(['HOT', 'hot']);
  if (kinds.has('cipher')) chips.push(['CIPHER', 'cipher']);
  if (kinds.has('engine')) chips.push(['ENG', 'eng']);
  return chips;
}

/** First readable line for a component: its first root's summary, else any node. */
function compTitle(comp) {
  const db = dialogDb;
  for (const r of comp.roots) {
    const line = dialogNodeSummary(r.node);
    if (line) return line;
  }
  for (const n of comp.nodes) {
    const line = db.firstLine(n);
    if (line) return line;
  }
  return `(${comp.nodes[0] ? comp.nodes[0].class : 'component'} ${comp.id})`;
}

/**
 * Fill a `.dtxt` span with a node's preview. A `#title#`-form body renders as the
 * bare title with a distinct (small-caps/accent) style; otherwise the plain
 * control-cleaned summary.
 */
function fillSummary(txt, node) {
  const db = dialogDb;
  const title = db.titleOf(node);
  if (title !== null) {
    txt.textContent = title;
    txt.title = title;
    txt.classList.add('dtitle');
    return;
  }
  const s = dialogNodeSummary(node) || `(${node.class} ${node.key !== null ? node.key : node.id})`;
  txt.textContent = s;
  txt.title = s;
}

/** Node summary: own first line, else first resolvable child's (cycle-guarded). */
function dialogNodeSummary(node, seen) {
  const db = dialogDb;
  const own = db.firstLine(node);
  if (own) return own;
  const visited = seen || new Set();
  visited.add(node.id);
  for (const e of db.outEdges(node)) {
    if (!e.node || visited.has(e.node.id)) continue;
    const line = dialogNodeSummary(e.node, visited);
    if (line) return line;
  }
  return '';
}

/** Build the three collapsible sidebar groups. */
function rebuildDialogSidebar() {
  const db = dialogDb;
  if (!db) return;
  const filter = el.dlgSearch.value.trim();

  // Search mode: numeric key lookup or substring over node text.
  if (filter) {
    renderDialogSearch(filter);
    return;
  }

  const frag = document.createDocumentFragment();

  // Conversations: multi-node components (excluding the giant web, id 0),
  // sorted by size desc (components are already size-sorted).
  const convs = db.components.filter((c) => c.id !== 0 && c.size > 1);
  frag.appendChild(dialogGroup('conv', 'Conversations', convs.length, () => {
    const rows = [];
    for (const c of convs) {
      rows.push(convRow(c));
    }
    return rows;
  }));

  // Keyword web: the giant component, listed as its hubs.
  const hubs = db.hubs();
  frag.appendChild(dialogGroup('kw', 'Keyword web', hubs.length, () => {
    return hubs.map((h) => hubRow(h));
  }));

  // Popups: single-node components, paginated.
  const popups = db.components.filter((c) => c.size === 1);
  frag.appendChild(dialogGroup('popup', 'Popups', popups.length, () => {
    const rows = [];
    const shown = Math.min(popupShown, popups.length);
    for (let i = 0; i < shown; i++) rows.push(popupRow(popups[i]));
    if (popups.length > shown) {
      const more = document.createElement('div');
      more.className = 'drow moar';
      more.textContent = `show more (${popups.length - shown} left)`;
      more.addEventListener('click', () => { popupShown += POPUP_PAGE; rebuildDialogSidebar(); });
      rows.push(more);
    }
    return rows;
  }));

  el.dialogSidebar.innerHTML = '';
  el.dialogSidebar.appendChild(frag);
}

/** A collapsible sidebar group; body rows are built lazily by `bodyFn`. */
function dialogGroup(id, title, count, bodyFn) {
  const g = document.createElement('div');
  g.className = 'dgroup' + (dlgGroupState[id] ? ' collapsed' : '');
  const head = document.createElement('div');
  head.className = 'dghead';
  head.innerHTML = `<span>${title}</span><span class="cnt">${count}</span>`;
  const body = document.createElement('div');
  body.className = 'dgbody';
  for (const row of bodyFn()) body.appendChild(row);
  head.addEventListener('click', () => {
    dlgGroupState[id] = !dlgGroupState[id];
    g.classList.toggle('collapsed', dlgGroupState[id]);
  });
  g.append(head, body);
  return g;
}

/** Conversation row: class dot + first-line + node-count badge + prov chips. */
function convRow(comp) {
  const db = dialogDb;
  const row = document.createElement('div');
  row.className = 'drow';
  row.dataset.comp = comp.id;
  const first = comp.roots[0] ? comp.roots[0].node : comp.nodes[0];
  const cls = first ? first.class : 'text';
  const dot = document.createElement('span');
  dot.className = 'cdot';
  dot.style.background = classAccent(cls);
  const txt = document.createElement('span');
  txt.className = 'dtxt';
  txt.textContent = compTitle(comp);
  txt.title = txt.textContent;
  const cnt = document.createElement('span');
  cnt.className = 'dcnt';
  cnt.textContent = `${comp.size}n`;
  const chips = document.createElement('span');
  chips.className = 'dchips';
  for (const [t, c] of compProvChips(comp)) {
    const b = document.createElement('span');
    b.className = `dpv ${c}`;
    b.textContent = t;
    chips.appendChild(b);
  }
  row.append(dot, txt, cnt, chips);
  // Open the conversation scoped to its root's forward closure (out-edges only),
  // not the whole weakly-connected component (which fuses shared response nodes
  // from unrelated conversations — e.g. every tavern reusing one tavernkeeper).
  row.addEventListener('click', () => openConversationFrom(firstSelectable(comp)));
  return row;
}

/** Open a conversation scoped to a start node's FORWARD CLOSURE in the tab. */
function openConversationFrom(startId) {
  if (!startId) return;
  dialogFull.openForward(startId, { select: startId });
}

/** Keyword-web hub row: speaker/first-line + spoke count. */
function hubRow(hub) {
  const db = dialogDb;
  const row = document.createElement('div');
  row.className = 'drow';
  row.dataset.hub = hub.id;
  const dot = document.createElement('span');
  dot.className = 'cdot';
  dot.style.background = classAccent(hub.class);
  const txt = document.createElement('span');
  txt.className = 'dtxt';
  const title = db.titleOf(hub);
  if (title !== null) { txt.textContent = title; txt.classList.add('dtitle'); }
  else txt.textContent = dialogNodeSummary(hub) || db.speakerName(hub) || hub.id;
  txt.title = `${txt.textContent} · ${hub.id}`;
  const cnt = document.createElement('span');
  cnt.className = 'dcnt';
  cnt.textContent = `${hub.entries.length} spokes`;
  row.append(dot, txt, cnt);
  row.addEventListener('click', () => dialogFull.openHub(hub.key !== null ? hub.key : hub.id, { select: hub.id }));
  return row;
}

/** Popup row: single-node first-line + prov chips. */
function popupRow(comp) {
  const db = dialogDb;
  const node = comp.nodes[0];
  const row = document.createElement('div');
  row.className = 'drow';
  row.dataset.comp = comp.id;
  const dot = document.createElement('span');
  dot.className = 'cdot';
  dot.style.background = classAccent(node.class);
  const txt = document.createElement('span');
  txt.className = 'dtxt';
  fillSummary(txt, node);
  const chips = document.createElement('span');
  chips.className = 'dchips';
  for (const [t, c] of compProvChips(comp)) {
    const b = document.createElement('span');
    b.className = `dpv ${c}`;
    b.textContent = t;
    chips.appendChild(b);
  }
  row.append(dot, txt, chips);
  // A popup is a single-node component; its forward closure is just itself
  // (plus any op-16 chain it pushes), so this is the scoped conversation.
  row.addEventListener('click', () => openConversationFrom(node.id));
  return row;
}

/** Class accent color (mirror of dialoggraph.js CLASS_COLORS accents). */
function classAccent(cls) {
  return ({
    text: '#7b8494', branch: '#d9a441', menu: '#6fb3ff',
    'keyword-hub': '#c79bff', cipher: '#5fcf7f', chain: '#5fd6d6',
  })[cls] || '#7b8494';
}

/** The node id to auto-select when opening a component (first root, else first). */
function firstSelectable(comp) {
  return comp.roots[0] ? comp.roots[0].node.id : (comp.nodes[0] ? comp.nodes[0].id : null);
}

/** Render the search-results list into the sidebar (numeric key or text). */
function renderDialogSearch(query) {
  const db = dialogDb;
  el.dialogSidebar.innerHTML = '';
  const results = [];
  const asNum = /^\d+$/.test(query) ? parseInt(query, 10) : null;
  if (asNum !== null) {
    const node = db.nodeByKey(asNum);
    if (node) results.push({ node, line: `key ${asNum}: ${dialogNodeSummary(node) || '(no text)'}` });
  }
  for (const hit of db.search(query, 200)) {
    results.push({ node: hit.node, line: hit.line || dialogNodeSummary(hit.node) || '(no text)' });
  }
  const head = document.createElement('div');
  head.className = 'dghead';
  head.style.cursor = 'default';
  head.innerHTML = `<span>Search hits</span><span class="cnt">${results.length}</span>`;
  el.dialogSidebar.appendChild(head);
  if (!results.length) {
    const empty = document.createElement('div');
    empty.className = 'demptyhits';
    empty.textContent = `no dialog matches “${query}”`;
    el.dialogSidebar.appendChild(empty);
    return;
  }
  for (const r of results.slice(0, 200)) {
    const row = document.createElement('div');
    row.className = 'drow';
    row.dataset.hit = r.node.id;
    const dot = document.createElement('span');
    dot.className = 'cdot';
    dot.style.background = classAccent(r.node.class);
    const txt = document.createElement('span');
    txt.className = 'dtxt';
    const title = db.titleOf(r.node);
    if (title !== null && r.line === title) txt.classList.add('dtitle');
    txt.textContent = r.line;
    txt.title = r.line;
    row.append(dot, txt);
    row.addEventListener('click', () => dialogFull.navigate(r.node.id));
    el.dialogSidebar.appendChild(row);
  }
}

// -- navigation -------------------------------------------------------------

/** A real hub = a node in the giant component (id 0) with >= 6 out-entries. */
function isHubNode(node) {
  if (!node) return false;
  const comp = dialogDb.componentForNode(node);
  return !!(comp && comp.id === 0 && node.entries.length >= 6);
}

/**
 * Resolve the home VIEW for a dialog node: a hub neighborhood, or the FORWARD
 * CLOSURE of the node. Returns a render-ready `{spec, rootId, selectId, kind}`
 * shared by the DIALOG tab and the overlay so both build the exact same view
 * from a key/node without duplicating the choice. `kind` is 'hub' | 'forward';
 * null when the node has no view.
 *
 * Opening a conversation is scoped to the node's OUT-edge forward closure (not
 * its weakly-connected component). Many small conversations share generic
 * response nodes — e.g. ~13 taverns/inns across zones 1-6 reuse one pair of
 * tavernkeeper "greeted / cash up front" nodes — so the component fuses them all
 * into one WCC. Forward closure follows the opened key's own out-edges only, so a
 * tavern shows its 5-node conversation, not the 34-node union of all taverns. The
 * closure is uncapped: a genuinely large conversation (Phillip, ~383 nodes) or a
 * dev root (~2691 nodes) still renders in full.
 */
function dialogViewForNode(node) {
  if (!node) return null;
  if (isHubNode(node)) {
    const hubKey = node.key !== null ? node.key : node.id;
    return { kind: 'hub', spec: { hubKey, depth: 2 }, rootId: node.id, selectId: node.id };
  }
  return {
    kind: 'forward', spec: { forwardFrom: node.id },
    rootId: node.id, selectId: node.id,
  };
}


/** Fill a <select> with the current layout presets, selecting the active one. */
function fillLayoutOptions(sel) {
  if (!sel) return;
  sel.innerHTML = '';
  for (const name of dlgPresetNames) {
    const o = document.createElement('option');
    o.value = name; o.textContent = name;
    sel.appendChild(o);
  }
  sel.value = dlgSettings.layoutPreset;
}

// -- layout TUNE panel ------------------------------------------------------
//
// A ⚙ popover next to the `layout:` dropdown exposing 5 live ELK knobs that
// OVERRIDE options on top of the active preset (dlgSettings.tuneOverrides),
// applied to BOTH views via refreshAllViews(). ELK-only: under the custom
// `classic` preset the ⚙ is disabled (its options don't apply to the
// hand-rolled kernels). Each view has its OWN popover toggle (v.tunePanelOpen)
// but they SHARE the one global override map.

/** True when the active preset is an ELK algorithm (tune knobs apply). Manual
 *  mode freezes auto-layout, so tune is disabled there too. */
function tuneApplies() {
  if (dialogFull && dialogFull.graph.manual) return false;
  return presetFor(dlgSettings.layoutPreset).kind === 'elk';
}

// Close an open ⚙ popover on an outside click (registered once).
let _tuneOutsideWired = false;
function wireTuneOutsideClose() {
  if (_tuneOutsideWired) return;
  _tuneOutsideWired = true;
  document.addEventListener('click', (e) => {
    // Ignore clicks on a ⚙ button (.ptune) or inside a body-mounted popover.
    if (e.target.closest && (e.target.closest('.ptune') || e.target.closest('.tunePanel'))) return;
    if (dialogFull && dialogFull.tunePanelOpen) {
      dialogFull.tunePanelOpen = false;
      if (view === 'dialog') renderCrumbs(); else removeTunePanel('tab');
    }
    if (dialogOverlay && dialogOverlay.tunePanelOpen) {
      dialogOverlay.tunePanelOpen = false;
      if (dialogOverlay.open_) renderOverlayHeader(); else removeTunePanel('ovl');
    }
  });
}

/** Count of live overrides — drives the ⚙ badge and READY ` TUNED:<n>`. */
function tuneCount() { return Object.keys(dlgSettings.tuneOverrides).length; }

/**
 * Set one override key (from a knob change) and re-lay-out live in BOTH views. A
 * value equal to the preset's baseline is still recorded as an explicit override
 * (so the knob's effect is deterministic and TUNED counts it).
 */
function setTuneOverride(key, value) {
  dlgSettings.tuneOverrides = { ...dlgSettings.tuneOverrides, [key]: value };
  refreshAllViews();
  renderCrumbs();
  if (dialogOverlay && dialogOverlay.open_) renderOverlayHeader();
  updateDialogReady();
}

/** Clear all live overrides back to the pure preset and re-lay-out both views. */
function resetTuneOverrides() {
  dlgSettings.tuneOverrides = {};
  refreshAllViews();
  renderCrumbs();
  if (dialogOverlay && dialogOverlay.open_) renderOverlayHeader();
  updateDialogReady();
}

/**
 * Build the ⚙ tune control (button + its anchored popover) for `v`'s toolbar.
 * The two views each get an independent popover toggle (v.tunePanelOpen) but
 * SHARE the one global dlgSettings.tuneOverrides. The popover is anchored under
 * the button on the LEFT so the right-side inspector never covers it.
 */
function makeTuneControl(v) {
  const overlay = v.modal;
  const wrap = document.createElement('span');
  wrap.className = 'ptune';

  const btn = document.createElement('button');
  btn.className = 'tuneBtn';
  btn.type = 'button';
  const applies = tuneApplies();
  const n = tuneCount();
  btn.textContent = n > 0 ? `⚙ tune (${n})` : '⚙ tune';
  btn.classList.toggle('on', n > 0);
  if (!applies) {
    btn.disabled = true;
    btn.title = 'layout tuning applies to ELK presets only — the classic kernel is hand-rolled';
  } else {
    btn.title = 'tune individual ELK layout options on top of the active preset';
  }

  const open = v.tunePanelOpen;
  btn.classList.toggle('active', open && applies);

  btn.addEventListener('click', (e) => {
    e.stopPropagation();
    if (!tuneApplies()) return;
    v.tunePanelOpen = !v.tunePanelOpen;
    // Re-render only THIS toolbar so the other one's popover state is untouched.
    if (overlay) renderOverlayHeader(); else renderCrumbs();
  });
  wrap.appendChild(btn);

  // The popover is rendered into document.body (not in-flow) and anchored FIXED
  // under the ⚙ button: the crumb bar (overflow-x:auto) and the overlay panel
  // (overflow:hidden) would both clip an in-flow popover. A stale panel for this
  // channel is always removed first, so exactly one is live per channel.
  const channel = overlay ? 'ovl' : 'tab';
  removeTunePanel(channel);
  // The tab popover only mounts while the DIALOG tab is actually showing (the
  // crumb bar is rebuilt even when hidden); the overlay popover mounts whenever
  // the overlay is open.
  const visible = overlay ? v.open_ : (view === 'dialog');
  if (open && applies && visible) mountTunePanel(overlay, btn, channel);
  return wrap;
}

/** Remove any live popover for a channel ('tab' | 'ovl') from document.body. */
function removeTunePanel(channel) {
  for (const p of document.querySelectorAll(`.tunePanel[data-tune-channel="${channel}"]`)) p.remove();
}

/**
 * Build the popover, append it to document.body, and anchor it FIXED under
 * `btn`. Left-aligned to the button so the right-side inspector never covers it;
 * clamped into the viewport so it is never off-screen.
 */
function mountTunePanel(overlay, btn, channel) {
  const panel = buildTunePanel(overlay);
  panel.dataset.tuneChannel = channel;
  document.body.appendChild(panel);
  const place = () => {
    if (!btn.isConnected) return;
    const r = btn.getBoundingClientRect();
    if (!r.width && !r.height) return;
    const pw = panel.offsetWidth || 250;
    let left = Math.round(r.left);
    left = Math.max(6, Math.min(left, window.innerWidth - pw - 6));
    panel.style.left = left + 'px';
    panel.style.top = Math.round(r.bottom + 4) + 'px';
  };
  place();
  requestAnimationFrame(place);
}

/**
 * The compact popover with the 5 knobs. Each control initializes to the active
 * preset's value for its option (falling back to the knob's default), so it is a
 * starting point, not a jump. Changing a control writes an override and
 * re-lays-out immediately; sliders debounce ~150ms so dragging doesn't spam
 * layouts.
 */
function buildTunePanel(overlay) {
  const preset = presetFor(dlgSettings.layoutPreset);
  const opts = preset.options || {};
  const panel = document.createElement('div');
  panel.className = 'tunePanel';
  panel.addEventListener('click', (e) => e.stopPropagation());

  const head = document.createElement('div');
  head.className = 'tuneHead';
  head.textContent = `tune · ${dlgSettings.layoutPreset}`;
  panel.appendChild(head);

  for (const knob of TUNE_KNOBS) {
    const row = document.createElement('label');
    row.className = 'tuneRow';
    const lab = document.createElement('span');
    lab.className = 'tuneLbl';
    lab.textContent = knob.label;
    row.appendChild(lab);

    // Current value: an explicit override if set, else the preset baseline.
    const hasOverride = Object.prototype.hasOwnProperty.call(dlgSettings.tuneOverrides, knob.key);
    const baseline = tuneBaselineValue(knob, opts);
    const cur = hasOverride
      ? (knob.kind === 'range' ? parseFloat(dlgSettings.tuneOverrides[knob.key]) : String(dlgSettings.tuneOverrides[knob.key]))
      : baseline;

    if (knob.kind === 'select') {
      const sel = document.createElement('select');
      sel.className = 'tuneSel';
      for (const o of knob.options) {
        const op = document.createElement('option');
        op.value = o.value; op.textContent = o.label;
        sel.appendChild(op);
      }
      sel.value = String(cur);
      sel.addEventListener('change', () => setTuneOverride(knob.key, sel.value));
      row.appendChild(sel);
    } else {
      const box = document.createElement('span');
      box.className = 'tuneRange';
      const rng = document.createElement('input');
      rng.type = 'range';
      rng.min = String(knob.min); rng.max = String(knob.max); rng.step = String(knob.step);
      rng.value = String(cur);
      const num = document.createElement('span');
      num.className = 'tuneNum';
      num.textContent = String(cur);
      let t = null;
      rng.addEventListener('input', () => {
        num.textContent = rng.value;
        if (t) clearTimeout(t);
        t = setTimeout(() => setTuneOverride(knob.key, rng.value), 150);
      });
      box.append(rng, num);
      row.appendChild(box);
    }
    if (hasOverride) row.classList.add('tuned');
    panel.appendChild(row);
  }

  const foot = document.createElement('div');
  foot.className = 'tuneFoot';
  const info = document.createElement('span');
  info.className = 'tuneInfo';
  info.textContent = tuneCount() > 0 ? `${tuneCount()} override${tuneCount() === 1 ? '' : 's'}` : 'no overrides';
  const reset = document.createElement('button');
  reset.type = 'button';
  reset.className = 'tuneReset';
  reset.textContent = 'reset';
  reset.disabled = tuneCount() === 0;
  reset.addEventListener('click', (e) => { e.stopPropagation(); resetTuneOverrides(); });
  foot.append(info, reset);
  panel.appendChild(foot);
  return panel;
}

/**
 * A `layout:` preset dropdown (classic kernel + ELK algorithm presets,
 * elklayout.js PRESETS) wired to setDlgLayoutEngine. Reused by the tab crumb
 * bar and the overlay header.
 */
function makeLayoutSelect(v) {
  const wrap = document.createElement('label');
  wrap.className = 'plumb';
  wrap.title = 'graph layout preset (per dialog view)';
  wrap.append(document.createTextNode('layout:'));
  const sel = document.createElement('select');
  sel.style.cssText = 'font:inherit;font-size:11px;background:var(--panel);color:var(--accent);'
    + 'border:1px solid #14161a;border-radius:3px;padding:1px 4px;cursor:pointer;';
  fillLayoutOptions(sel);
  if (v) sel.value = v.layoutPreset;   // PER-VIEW preset, not the shared default
  sel.addEventListener('change', () => setDlgLayoutEngine(v, sel.value));
  wrap.appendChild(sel);
  return wrap;
}

/**
 * Serialize the manual layout to a downloadable JSON file. `all` dumps every
 * manually-arranged conversation from localStorage; otherwise just the current
 * one. Uses a Blob + object URL + a temporary <a download> (no server).
 */
function downloadManualLayout(v, all) {
  const g = v.graph;
  const obj = all ? g.dumpAllManualLayouts() : g.dumpManualLayout();
  const json = JSON.stringify(obj, null, 2);
  const blob = new Blob([json], { type: 'application/json' });
  const url = URL.createObjectURL(blob);
  const a = document.createElement('a');
  a.href = url;
  a.download = all ? 'dialog-layouts-all.json'
    : `dialog-layout-${g.convKey || 'view'}.json`;
  document.body.appendChild(a);
  a.click();
  a.remove();
  setTimeout(() => URL.revokeObjectURL(url), 1000);
}

/** Read a dumped layout JSON file and import it into `v`'s graph. */
function importManualLayoutFromFile(v, file) {
  if (!file) return;
  const reader = new FileReader();
  reader.onload = () => {
    let obj;
    try { obj = JSON.parse(String(reader.result)); }
    catch (_) { setStatus('manual layout: invalid JSON'); return; }
    v.graph.importManualLayout(obj);
  };
  reader.readAsText(file);
}

/**
 * Build the SHARED toolbar controls for a DialogView `v` into `host`: layout /
 * chapter / dev-paths / ⚙ tune / fit / snap, the manual-layout chip + dump/load
 * controls (when arranged), and the merge-mark controls for the selection. Used
 * by BOTH the tab crumb bar and the overlay header so the overlay has full
 * manual-edit + mark parity.
 */
function buildDialogToolbar(v, host) {
  const g = v.graph;
  host.appendChild(makeLayoutSelect(v));
  host.appendChild(makeChapterSelect());
  host.appendChild(makeDevPathsToggle());
  host.appendChild(makeTuneControl(v));
  const fit = document.createElement('button');
  fit.textContent = 'fit';
  fit.addEventListener('click', () => g.fit());
  host.appendChild(fit);
  // Snap-to-grid toggle: reachable in ?bare=1. Snaps a dragged node's CENTER to
  // a 20px grid; toggling affects only future drags.
  const snap = document.createElement('button');
  const on = g.snapGrid;
  snap.textContent = on ? '▣ snap: on' : '▢ snap: off';
  snap.title = on
    ? 'snap to grid is ON — dragged nodes snap their center to the grid (click to disable)'
    : 'snap to grid is OFF (click to snap dragged nodes’ center to a 20px grid)';
  if (on) { snap.classList.add('on'); snap.style.cssText = 'color:#5fd6d6;border-color:#5fd6d6;'; }
  snap.addEventListener('click', () => g.setSnap(!g.snapGrid));
  host.appendChild(snap);
  // Manual-layout toolbar: a "● manual" chip + reset-to-auto and dump controls,
  // shown only while the current view is user-arranged.
  if (g.manual) {
    const chip = document.createElement('span');
    chip.className = 'crumb cur';
    chip.style.cssText = 'color:#ffd54a;border-color:#ffd54a;';
    chip.textContent = `● manual (${g.manualMovedCount()})`;
    chip.title = 'manual layout: nodes have been dragged; auto-layout is frozen';
    host.appendChild(chip);
    const reset = document.createElement('button');
    reset.textContent = 'reset to auto';
    reset.title = 'discard manual edits and re-run the auto layout';
    reset.addEventListener('click', () => g.resetToAuto());
    host.appendChild(reset);
    const dump = document.createElement('button');
    dump.textContent = 'dump ⭳';
    dump.title = 'download this conversation’s manual layout as JSON';
    dump.addEventListener('click', () => downloadManualLayout(v, false));
    host.appendChild(dump);
    const dumpAll = document.createElement('button');
    dumpAll.textContent = 'dump all';
    dumpAll.title = 'download every manually-arranged conversation as JSON';
    dumpAll.addEventListener('click', () => downloadManualLayout(v, true));
    host.appendChild(dumpAll);
    const load = document.createElement('label');
    load.className = 'plumb';
    load.textContent = 'load ⭱';
    load.title = 'load a previously-dumped layout JSON';
    load.style.cursor = 'pointer';
    const fin = document.createElement('input');
    fin.type = 'file';
    fin.accept = 'application/json,.json';
    fin.style.display = 'none';
    fin.addEventListener('change', () => importManualLayoutFromFile(v, fin.files && fin.files[0]));
    load.appendChild(fin);
    host.appendChild(load);
  }
  // Merge-mark controls for the selected node (unmerge / reference / clear).
  renderMarkControls(v, host);
}

/** Render the tab breadcrumb bar. Toolbar controls + crumbs. */
function renderCrumbs() {
  const v = dialogFull;
  el.dlgCrumbs.innerHTML = '';
  buildDialogToolbar(v, el.dlgCrumbs);
  const gap = document.createElement('span');
  gap.className = 'sep';
  gap.textContent = '·';
  el.dlgCrumbs.appendChild(gap);
  v.crumbStack.forEach((c, i) => {
    if (i > 0) {
      const sep = document.createElement('span');
      sep.className = 'sep';
      sep.textContent = '›';
      el.dlgCrumbs.appendChild(sep);
    }
    const span = document.createElement('span');
    const isCur = i === v.crumbStack.length - 1;
    span.className = 'crumb' + (isCur ? ' cur' : '');
    span.textContent = crumbLabel(c);
    if (!isCur) span.addEventListener('click', () => v.popToCrumb(i));
    el.dlgCrumbs.appendChild(span);
  });
  const spacer = document.createElement('span');
  spacer.className = 'spacer';
  el.dlgCrumbs.appendChild(spacer);
}

/**
 * Merge-mark toolbar for the selected node: "merge:" label + unmerge / reference
 * / clear buttons, plus an inline mark chip and the unmerge validation error.
 * The unmerge + reference buttons are enabled only when the selected node is
 * SHARED (in-degree >= 2 within the current view); on a single-parent node they
 * are disabled (the marks are a no-op there). Lives in the crumb bar so it is
 * reachable in ?bare=1.
 */
function renderMarkControls(v, host) {
  const g = v.graph;
  if (!g.graph) return;
  const id = v.selectedId;
  const marks = g.marksObject();
  const totalMarks = g.markCount();

  const wrap = document.createElement('span');
  wrap.className = 'dlgMarkTools';

  const lbl = document.createElement('span');
  lbl.className = 'dlgMarkLabel';
  lbl.textContent = totalMarks ? `merge (${totalMarks}):` : 'merge:';
  wrap.appendChild(lbl);

  const inView = id && g.graph.nodes.some((n) => n.id === id);
  const inDeg = inView ? g.inDegreeOf(id) : 0;
  const shared = inDeg >= 2;
  const curMark = id ? marks[id] : null;

  const mkBtn = (text, title, on, active, disabled) => {
    const b = document.createElement('button');
    b.textContent = text;
    b.title = title;
    if (active) b.classList.add('on');
    if (disabled) { b.disabled = true; b.classList.add('disabled'); }
    else b.addEventListener('click', on);
    wrap.appendChild(b);
    return b;
  };

  if (!inView) {
    const hint = document.createElement('span');
    hint.className = 'dlgMarkHint';
    hint.textContent = 'select a shared node';
    wrap.appendChild(hint);
  } else {
    mkBtn('unmerge', shared
      ? 'clone this node’s self-contained leaf block once per parent'
      : 'select a shared node (in-degree ≥ 2) to unmerge',
      () => markDialogNode(v, id, 'unmerge'), curMark === 'unmerge', !shared);
    mkBtn('reference', shared
      ? 'show this node once, detached, with a dashed link from each parent'
      : 'select a shared node (in-degree ≥ 2) to reference',
      () => markDialogNode(v, id, 'reference'), curMark === 'reference', !shared);
    if (curMark) {
      mkBtn('clear', 'remove this node’s merge mark',
        () => markDialogNode(v, id, null), false, false);
    }
    if (!shared) {
      // Say WHY the marks are unavailable: a node reached from < 2 parents in
      // THIS view isn't a merge, even if its own subtree is a leaf.
      const hint = document.createElement('span');
      hint.className = 'dlgMarkHint';
      hint.textContent = `— reached from ${inDeg} place${inDeg === 1 ? '' : 's'} in this view; needs ≥2 to un/merge`;
      wrap.appendChild(hint);
    }
  }

  host.appendChild(wrap);

  // Inline unmerge validation error (last failure), with a dismiss.
  const err = g._markError;
  if (err && err.reason) {
    const box = document.createElement('span');
    box.className = 'dlgMarkErr';
    box.textContent = '⚠ ' + err.reason;
    box.title = 'unmerge validation failed';
    host.appendChild(box);
  }
}

/**
 * Switch the dialog layout PRESET (elklayout.js PRESETS) and re-lay-out the
 * current view LIVE. Applies to both the DIALOG tab graph and the overlay (so
 * an open overlay honors the selected preset too). Legacy 'elk' -> default.
 */
// Layout preset is PER-VIEW: this changes only the given view `v`, never the
// other one — so re-laying out one dialog/panel can't disturb another.
function setDlgLayoutEngine(v, name) {
  if (!v) v = dialogFull;
  if (!v) return;
  if (name === 'elk') name = DEFAULT_PRESET;
  const next = PRESETS[name] ? name : DLG_DEFAULT_LAYOUT;
  const changed = next !== v.layoutPreset;
  v.layoutPreset = next;
  // Switching presets clears the (shared) live tune overrides — they belong to
  // the old preset and shouldn't silently ride onto a different algorithm.
  if (changed) {
    dlgSettings.tuneOverrides = {};
    if (dialogFull) dialogFull.graph.layoutOverrides = {};
    if (dialogOverlay) dialogOverlay.graph.layoutOverrides = {};
  }
  v.graph.setLayoutEngine(next);
  v.fit();
  v.renderHeader();
  updateDialogReady();
}

/**
 * A `chapter:` filter dropdown (`all` + 1..10) wired to setDlgChapterFilter.
 * Sits next to the `layout:` dropdown so it is reachable in `?bare=1` mode.
 */
function makeChapterSelect() {
  const wrap = document.createElement('label');
  wrap.className = 'plumb';
  wrap.title = 'prune the view to a chapter (chapter-gated arms only)';
  wrap.append(document.createTextNode('chapter:'));
  const sel = document.createElement('select');
  sel.style.cssText = 'font:inherit;font-size:11px;background:var(--panel);color:var(--accent);'
    + 'border:1px solid #14161a;border-radius:3px;padding:1px 4px;cursor:pointer;';
  const optAll = document.createElement('option');
  optAll.value = 'all'; optAll.textContent = 'all';
  sel.appendChild(optAll);
  for (let c = 1; c <= 10; c++) {
    const o = document.createElement('option');
    o.value = String(c); o.textContent = String(c);
    sel.appendChild(o);
  }
  sel.value = dlgSettings.chapter == null ? 'all' : String(dlgSettings.chapter);
  sel.addEventListener('change', () => setDlgChapterFilter(sel.value));
  wrap.appendChild(sel);
  return wrap;
}

/**
 * Switch the SHARED dialog chapter FILTER ('all' or 1..10) and re-render EVERY
 * open view LIVE via refreshAllViews(). Persists across navigation. Only the
 * forward-closure view is affected by the value; hub/component views re-render
 * unchanged. Both views' dropdowns reflect the new value on the next header
 * paint (renderCrumbs / renderOverlayHeader).
 */
function setDlgChapterFilter(value) {
  const next = (value === 'all' || value == null) ? null : parseInt(value, 10);
  if (next === dlgSettings.chapter) return;
  dlgSettings.chapter = next;
  refreshAllViews();
  renderCrumbs();
  if (dialogOverlay && dialogOverlay.open_) renderOverlayHeader();
  updateDialogReady();
}

/**
 * A `dev paths:` toggle button (off/on) wired to setDlgShowDev. Sits next to the
 * `chapter:` dropdown so it is reachable in `?bare=1` mode. Default off = the
 * developer PAGE_THRU paging edges are hidden.
 */
function makeDevPathsToggle() {
  const btn = document.createElement('button');
  const on = dlgSettings.showDev;
  btn.textContent = on ? '▣ dev paths: on' : '▢ dev paths: off';
  btn.title = on
    ? 'developer PAGE_THRU paging edges are SHOWN — conversations page into the '
      + 'next (never happens in real play). Click to hide.'
    : 'developer PAGE_THRU paging edges are hidden (a conversation stops at its '
      + 'END-OF-PATH markers). Click to show them.';
  if (on) { btn.classList.add('on'); btn.style.cssText = 'color:#d6a15f;border-color:#d6a15f;'; }
  btn.addEventListener('click', () => setDlgShowDev(!dlgSettings.showDev));
  return btn;
}

/**
 * Switch the SHARED developer-paths flag and re-render EVERY open view LIVE via
 * refreshAllViews(), persisting the flag globally (localStorage). Guards against
 * the boot path (no view yet — refreshAllViews is a no-op then).
 */
function setDlgShowDev(on) {
  on = !!on;
  if (on === dlgSettings.showDev) return;
  dlgSettings.showDev = on;
  try { localStorage.setItem(DLG_SHOWDEV_LS_KEY, on ? '1' : '0'); } catch (_) {}
  refreshAllViews();
  if (view === 'dialog') renderCrumbs();
  if (dialogOverlay && dialogOverlay.open_) renderOverlayHeader();
  updateDialogReady();
}

/** Human-readable crumb label. */
function crumbLabel(c) {
  const db = dialogDb;
  if (typeof c.spec === 'number') {
    const comp = db.components[c.spec];
    return comp ? truncate(compTitle(comp), 24) : `comp ${c.spec}`;
  }
  if (c.spec && c.spec.hubKey !== undefined) {
    const start = db.nodeByKey(c.spec.hubKey) || db.nodes.get(c.spec.hubKey);
    return 'hub ' + (start ? truncate(dialogNodeSummary(start) || db.speakerName(start) || String(c.spec.hubKey), 18) : c.spec.hubKey);
  }
  if (c.spec && c.spec.forwardFrom !== undefined) {
    const start = db.nodes.get(c.spec.forwardFrom);
    return truncate(start ? (dialogNodeSummary(start) || db.speakerName(start) || String(c.spec.forwardFrom)) : String(c.spec.forwardFrom), 22);
  }
  return c.label || 'view';
}

function truncate(s, n) { return s.length > n ? s.slice(0, n - 1) + '…' : s; }

// -- selection / inspector --------------------------------------------------

/**
 * Set / clear a merge mark on `v`'s selected dialog node and surface any unmerge
 * validation failure (inline status + console.warn). `kind` is
 * 'unmerge'|'reference'|null. Returns {ok, reason?}. Re-renders the view's
 * header so the mark chip + error update. Reachable in ?bare=1.
 */
function markDialogNode(v, id, kind) {
  const res = v.graph.setMark(id, kind);
  if (!res.ok && res.reason) {
    console.warn('dialog mark:', res.reason);
    setStatus('unmerge: ' + res.reason);
  }
  v.renderHeader();
  if (!v.modal) updateDialogReady(); else refreshReadyStatus();
  return res;
}

/** Hide the tab dialog inspector panel. */
function hideDlgInspector() {
  el.dlgInspector.classList.add('hidden');
  el.dlgInspector.innerHTML = '';
}

/** flags-word decode. */
const DLG_FLAG_BITS = [
  [0x0001, 'show name'], [0x0002, 'portrait/scene'], [0x0004, 'wrap-align'],
  [0x0008, 'ack timeout scale'], [0x0010, 'auto-advance'], [0x0020, 'force interactive'],
  [0x0040, 'force non-interactive'], [0x0080, 'stub'], [0x0100, 'clear backbuf'],
  [0x0200, 'paged menu'], [0x0400, 'askabout'], [0x0800, 'random branch'],
  [0x1000, 'party picker'], [0x2000, 'no wipe'], [0x4000, 'instant ack'],
  [0x8000, 'stable dither'],
];

function dlgFlagLabels(flags) {
  return DLG_FLAG_BITS.filter(([m]) => flags & m).map(([, n]) => n);
}

/** Render the dialog body with @n speaker resolution + control-byte markers. */
function renderDlgBody(node) {
  const db = dialogDb;
  let out = '';
  const bytes = node.textBytes;
  for (let i = 0; i < bytes.length; i++) {
    const b = bytes[i];
    if (b === 0x0a) { out += '\n'; continue; }
    if (b === 0x40 && i + 1 < bytes.length && bytes[i + 1] >= 0x30 && bytes[i + 1] <= 0x39) {
      const slot = bytes[i + 1] - 0x30;
      out += `@${slot}`; // name slot; resolved names live at runtime, keep literal
      i++;
      continue;
    }
    if (b === 0x09) out += '⇥'; // tab (paragraph indent)
    else if (b < 0x20) out += String.fromCharCode(0x2400 + b); // control picture
    else out += String.fromCharCode(b);
  }
  return out;
}

/** A clickable link that navigates to a target node/key on the canvas. */
function dlgLink(idOrKey, text) {
  return `<span class="link" data-nav="${escapeHtml(String(idOrKey))}">${escapeHtml(text)}</span>`;
}

/**
 * Build the dialog node-inspector HTML for `node` into `host` and wire its close
 * button + `data-nav` links. Shared by the DIALOG tab inspector and the overlay's
 * node-inspector strip so both render identical node detail from one renderer.
 * `cb.onClose` runs on the × button; `cb.onNav(idOrKey)` on a link click.
 */
function renderDlgInspectorInto(host, node, cb = {}) {
  const db = dialogDb;
  const fileName = `DIAL_Z${String(node.file).padStart(2, '0')}.DDX`;
  const title = node.key !== null ? `dialog ${node.key}` : `dialog ${fileName}@${node.offset.toString(16)}`;
  const cc = classAccent(node.class);
  let h = `<div class="insphead">`
    + `<button class="close" title="close">×</button>`
    + `<h2>${escapeHtml(title)} <span class="badge dlgClassBadge" style="background:${cc}">${escapeHtml(node.class)}</span></h2>`
    + `<div class="subtitle">${escapeHtml(fileName)} · +0x${node.offset.toString(16)} · in-degree ${node.inDegree}</div>`
    + `</div><div class="ibody">`;

  // Body text.
  h += `<h3>Body</h3>`;
  const body = renderDlgBody(node);
  h += body.trim() ? `<pre>${escapeHtml(body)}</pre>` : `<div class="prov">(no body text)</div>`;

  // Entries table.
  if (node.entries.length) {
    h += `<h3>Entries (${node.entries.length})</h3><table>`
      + `<tr><td class="k">label</td><td class="k">cond/min/max</td><td class="k">target</td></tr>`;
    for (const e of node.entries) {
      const res = db.resolveTarget(node.file, e.target);
      const tgt = res
        ? dlgLink(res.node.id, `${res.kind === 'key' ? res.key : '+' + res.offset.toString(16)} — ${truncate(dialogNodeSummary(res.node) || res.node.class, 20)}`)
        : (e.target ? `<span class="raw">${(e.target >>> 0).toString(16)} (dangling)</span>` : '—');
      h += `<tr><td>${escapeHtml(db.describeEntry(e, node))}</td>`
        + `<td class="raw">${e.cond}/${e.min}/${e.max}</td><td>${tgt}</td></tr>`;
    }
    h += `</table>`;
  }

  // Fused-switch provenance: the cascade members this card absorbed (consumed
  // same-state switches + swallowed/spliced empty pass-throughs), clickable.
  if (node.switchInfo && node.switchInfo.fusedFrom && node.switchInfo.fusedFrom.length) {
    const ff = node.switchInfo.fusedFrom;
    h += `<h3>Fused</h3><div class="prov">fused from ${ff.length} node${ff.length === 1 ? '' : 's'}: `
      + ff.map((f) => `${dlgLink(f.nodeId, f.nodeId)} <span class="raw">(${escapeHtml(f.role)})</span>`).join(' · ')
      + `</div>`;
    h += `<div class="prov">arms (${node.switchInfo.arms.length}): `
      + node.switchInfo.arms.map((a) => escapeHtml(a.label)).join(' · ') + `</div>`;
  }

  // Ops table.
  if (node.ops.length) {
    h += `<h3>Ops (${node.ops.length})</h3><table>`
      + `<tr><td class="k">op</td><td class="k">summary</td><td class="k">raw</td></tr>`;
    for (const o of node.ops) {
      h += `<tr><td>${o.op}</td><td>${escapeHtml(db.describeOp(o))}</td>`
        + `<td class="raw">${o.a1},${o.a2},${o.a3},${o.a4}</td></tr>`;
    }
    h += `</table>`;
  }

  // Header fields.
  h += `<h3>Header</h3><table>`
    + `<tr><td class="k">style</td><td>${node.style}</td></tr>`
    + `<tr><td class="k">speaker</td><td>${escapeHtml(db.speakerName(node))} <span class="raw">(${node.speakerId})</span></td></tr>`
    + `<tr><td class="k">flags</td><td class="raw">0x${(node.flags >>> 0).toString(16).padStart(4, '0')}</td></tr></table>`;
  const fl = dlgFlagLabels(node.flags);
  if (fl.length) h += `<div class="flags">${fl.map((f) => `<span class="flag">${escapeHtml(f)}</span>`).join('')}</div>`;

  // Provenance (roots referencing this node's component/key).
  if (node.key !== null) {
    const comp = db.componentForNode(node);
    const refs = comp ? comp.roots.filter((r) => r.node.id === node.id) : [];
    if (refs.length) {
      h += `<h3>Referenced by</h3>`;
      for (const r of refs) h += `<div class="prov">${escapeHtml(r.kind)}: ${escapeHtml(r.detail || '')}</div>`;
    }
  }

  // Raw hex.
  h += `<details><summary>raw hex</summary><pre>${escapeHtml(dlgHexDump(node))}</pre></details>`;

  h += `</div>`;
  host.innerHTML = h;
  host.classList.remove('hidden');
  // Wire links + close.
  const close = host.querySelector('.close');
  if (close && cb.onClose) close.addEventListener('click', cb.onClose);
  for (const a of host.querySelectorAll('[data-nav]')) {
    a.addEventListener('click', () => cb.onNav && cb.onNav(a.dataset.nav));
  }
}

/** Reconstruct a raw-byte hex dump of a node's record (header+entries+ops+body). */
function dlgHexDump(node) {
  const bytes = [];
  const push16 = (v) => { bytes.push(v & 0xff, (v >>> 8) & 0xff); };
  bytes.push(node.style & 0xff);
  push16(node.speakerId);
  push16(node.flags);
  bytes.push(node.nEntries & 0xff, node.nOps & 0xff);
  push16(node.bodyLen);
  for (const e of node.entries) {
    push16(e.cond); push16(e.min); push16(e.max);
    const t = e.target >>> 0;
    bytes.push(t & 0xff, (t >>> 8) & 0xff, (t >>> 16) & 0xff, (t >>> 24) & 0xff);
  }
  for (const o of node.ops) {
    push16(o.op);
    for (const a of [o.a1, o.a2, o.a3, o.a4]) push16(a & 0xffff);
  }
  for (const b of node.textBytes) bytes.push(b);
  const lines = [];
  for (let i = 0; i < bytes.length; i += 16) {
    let s = i.toString(16).padStart(4, '0') + '  ';
    for (let j = 0; j < 16 && i + j < bytes.length; j++) {
      s += bytes[i + j].toString(16).padStart(2, '0') + ' ';
    }
    lines.push(s.trimEnd());
  }
  return lines.join('\n');
}

/** READY line for the dialog view (headless contract). Reads the FULLSCREEN
 *  view's state — the overlay only ever appends ` OVL:<key>` in readyStatusText. */
function updateDialogReady() {
  const db = dialogDb;
  const v = dialogFull;
  const g = v ? v.graph : null;
  let text = `READY DLG ${db ? db.stats.components : 0} comps ${db ? db.stats.nodes : 0} nodes`;
  const spec = v ? v.spec : null;
  if (v && v.selectedId) {
    const node = db.nodes.get(v.selectedId);
    if (node) text += ` SEL:${node.key !== null ? node.key : node.file + '@' + node.offset}`;
  }
  if (spec !== null) {
    let vid;
    if (typeof spec === 'number') vid = String(spec);
    else if (spec.forwardFrom !== undefined) {
      const n = db.nodes.get(spec.forwardFrom);
      vid = (n && n.key !== null) ? String(n.key) : spec.forwardFrom;
    } else vid = 'hub:' + spec.hubKey;
    text += ` VIEW:${vid}`;
  }
  // The default preset ('layered-ortho') adds no tag; any other preset appends
  // ` LAYOUT:<presetName>` so headless deep-links can assert the layout.
  if (dialogFull && dialogFull.layoutPreset !== DLG_DEFAULT_LAYOUT) text += ` LAYOUT:${dialogFull.layoutPreset}`;
  // ` CH:<n>` only when a chapter filter is active ('all' appends nothing).
  if (dlgSettings.chapter != null) text += ` CH:${dlgSettings.chapter}`;
  // ` DEV` only when the developer PAGE_THRU paging edges are shown.
  if (dlgSettings.showDev) text += ` DEV`;
  // ` TUNED:<n>` where n = number of active ELK-option overrides (0 = nothing
  // appended), so headless can assert the live tune state.
  const tn = tuneCount();
  if (tn > 0) text += ` TUNED:${tn}`;
  // ` COLLAPSED:<n>` only when n>0 arms are collapsed (headless-assertable).
  const nc = g ? g.collapsedCount() : 0;
  if (nc > 0) text += ` COLLAPSED:${nc}`;
  // ` MANUAL:<n>` where n = number of manually-moved nodes (auto mode: absent).
  if (g && g.manual) text += ` MANUAL:${g.manualMovedCount()}`;
  // ` MARKS:<n>` where n = number of active merge marks (0 = absent).
  const mk = g ? g.markCount() : 0;
  if (mk > 0) text += ` MARKS:${mk}`;
  signalReady(text);
}

/**
 * Headless test hook + in-page navigation entry for deep links. Reads/drives the
 * FULLSCREEN view (`dialogFull`); its `.graph` is the underlying DialogGraph. The
 * overlay* accessors reach into `dialogOverlay`.
 */
function exposeDialog() {
  const gf = () => (dialogFull ? dialogFull.graph : null);
  const go = () => (dialogOverlay ? dialogOverlay.graph : null);
  window.__dialog = {
    openByKey: (k) => dialogFull.openByKey(k),
    openHub: (k, o) => dialogFull.openHub(k, o),
    openComponent: (id, o) => dialogFull.openComponent(id, o),
    navigateDialogTo: (id) => dialogFull.navigate(id),
    get selected() { return dialogFull ? dialogFull.selectedId : null; },
    get viewSpec() { return dialogFull ? dialogFull.spec : null; },
    get nodeCount() { const g = gf(); return g && g.graph ? g.graph.nodes.length : 0; },
    get edgeCount() { const g = gf(); return g && g.graph ? g.graph.edges.length : 0; },
    fit() { const g = gf(); if (g) g.fit(); },
    zoomBy(f) { const g = gf(); if (g) g.zoomBy(f); },
    db: () => dialogDb,
    // Rendered-node count (every graph node is a card now, so == nodeCount).
    get visibleCount() { const g = gf(); return g && g.model ? g.model.nodes.length : 0; },
    // DEV: model-vs-drawn edge accounting (unaccounted must be empty).
    edgeAudit(detail) { const g = gf(); return g && g.model ? g.edgeAudit(detail) : null; },
    overlayEdgeAudit(detail) { const g = go(); return g && g.model ? g.edgeAudit(detail) : null; },
    // DEV: visual layout-sanity (dangling arrows / off-canvas / overlaps). All
    // fields must be 0 on a clean view — the check edgeAudit's accounting missed.
    layoutSanity(detail) { const g = gf(); return g && g.model ? g.layoutSanity(detail) : null; },
    overlayLayoutSanity(detail) { const g = go(); return g && g.model ? g.layoutSanity(detail) : null; },
    // Layout preset (SHARED). ELK is async; readiness is when lastLayoutMs
    // updates and edgeAudit reflects the ELK-positioned edges.
    setLayoutEngine(name) { setDlgLayoutEngine(dialogFull, name); },
    get layoutEngine() { return dialogFull ? dialogFull.layoutPreset : dlgSettings.layoutPreset; },
    get layoutPreset() { return dialogFull ? dialogFull.layoutPreset : dlgSettings.layoutPreset; },
    // Overlay's per-view layout (independent of the tab's).
    setOverlayLayout(name) { setDlgLayoutEngine(dialogOverlay, name); },
    get overlayLayout() { return dialogOverlay ? dialogOverlay.layoutPreset : null; },
    // Chapter filter (SHARED; null = all, else 1..10). `setChapter` accepts
    // 'all'|N and re-renders BOTH views live; `chapterFilter` reads the value.
    setChapter(value) { setDlgChapterFilter(value); },
    get chapterFilter() { return dlgSettings.chapter; },
    // Developer PAGE_THRU paging edges (SHARED; default hidden). `setShowDev(on)`
    // flips the flag, re-renders BOTH views live, and persists it.
    setShowDev(on) { setDlgShowDev(on); },
    get showDev() { return dlgSettings.showDev; },
    // Live TUNE overrides (SHARED ELK options layered on top of the preset).
    setTune(key, value) { setTuneOverride(key, value); },
    resetTune() { resetTuneOverrides(); },
    get tuneOverrides() { return { ...dlgSettings.tuneOverrides }; },
    get tuneCount() { return tuneCount(); },
    get tuneApplies() { return tuneApplies(); },
    get presetNames() { return dlgPresetNames.slice(); },
    get droppedPresets() { return window.__dlgDroppedPresets || []; },
    get lastLayoutMs() { const g = gf(); return g ? g.lastLayoutMs : 0; },
    get lastElkError() { const g = gf(); return g ? g._lastElkError : null; },
    get graphInstance() { return gf(); },
    get overlayGraphInstance() { return go(); },
    // Per-arm collapse (manual). `collapseArm` toggles by (switchNodeId,
    // armIndex); collapsedCount reports live collapsed arms.
    collapseArm(stateNodeId, armIndex) {
      const g = gf(); if (g) g.toggleArmCollapse(stateNodeId, armIndex);
    },
    get collapsedCount() { const g = gf(); return g ? g.collapsedCount() : 0; },
    get overlayCollapsedCount() { const g = go(); return g ? g.collapsedCount() : 0; },
    // Manual layout editing. `manual` = in manual mode; `manualCount` == READY
    // MANUAL:<n>. `resetManual` returns to auto. `dumpManualLayout` /
    // `dumpAllManualLayouts` serialize; `importManualLayout` restores;
    // `manualPositions` returns the live {id:{x,y}} map for the conversation.
    get manual() { const g = gf(); return g ? g.manual : false; },
    get manualCount() { const g = gf(); return g ? g.manualMovedCount() : 0; },
    // Snap-to-grid: `setSnap(on)` toggles; `snapGrid` reads the flag;
    // `snapGridSize` (== GRID) is the world-unit pitch.
    setSnap(on) { const g = gf(); if (g) g.setSnap(on); if (view === 'dialog') renderCrumbs(); },
    get snapGrid() { const g = gf(); return g ? g.snapGrid : false; },
    get snapGridSize() { const g = gf(); return g ? g.snapGridSize() : 20; },
    get GRID() { const g = gf(); return g ? g.snapGridSize() : 20; },
    get manualConvKey() { const g = gf(); return g ? g.convKey : null; },
    resetManual() { const g = gf(); if (g) g.resetToAuto(); },
    dumpManualLayout() { const g = gf(); return g ? g.dumpManualLayout() : {}; },
    dumpAllManualLayouts() { const g = gf(); return g ? g.dumpAllManualLayouts() : {}; },
    importManualLayout(obj) { const g = gf(); return g ? g.importManualLayout(obj) : false; },
    manualPositions() {
      const g = gf();
      if (!g || !g.manual) return {};
      const o = {};
      for (const [id, p] of g.manualPos) o[id] = { x: p.x, y: p.y };
      return o;
    },
    // Overlay manual-edit test hooks — now that the overlay has full parity.
    get overlayManual() { const g = go(); return g ? g.manual : false; },
    get overlayManualCount() { const g = go(); return g ? g.manualMovedCount() : 0; },
    overlayManualPositions() {
      const g = go();
      if (!g || !g.manual) return {};
      const o = {};
      for (const [id, p] of g.manualPos) o[id] = { x: p.x, y: p.y };
      return o;
    },
    overlayCollapseArm(stateNodeId, armIndex) {
      const g = go(); if (g) g.toggleArmCollapse(stateNodeId, armIndex);
    },
    // Per-node MERGE marks (unmerge / reference). Marks persist alongside manual
    // positions (same record + dump).
    markUnmerge(id) { return dialogFull ? markDialogNode(dialogFull, id, 'unmerge') : { ok: false, reason: 'no graph' }; },
    markReference(id) { return dialogFull ? markDialogNode(dialogFull, id, 'reference') : { ok: false, reason: 'no graph' }; },
    clearMark(id) { return dialogFull ? markDialogNode(dialogFull, id, null) : { ok: false, reason: 'no graph' }; },
    canUnmerge(id) { const g = gf(); return g ? g.canUnmerge(id) : { ok: false, reason: 'no graph' }; },
    get marks() { const g = gf(); return g ? g.marksObject() : {}; },
    get markCount() { const g = gf(); return g ? g.markCount() : 0; },
    get markError() { const g = gf(); return g ? g._markError : null; },
    // Overlay marks (for parity validation).
    overlayMarkUnmerge(id) { return dialogOverlay ? markDialogNode(dialogOverlay, id, 'unmerge') : { ok: false, reason: 'no graph' }; },
    overlayClearMark(id) { return dialogOverlay ? markDialogNode(dialogOverlay, id, null) : { ok: false, reason: 'no graph' }; },
    get overlayMarkCount() { const g = go(); return g ? g.markCount() : 0; },
    // Switch nodes in the current tab graph, with their arm structure.
    switchNodes() {
      const g = gf();
      if (!g || !g.graph) return [];
      return g.graph.nodes.filter((n) => n.switch)
        .map((n) => ({ id: n.id, stateName: n.switch.stateName,
          arms: n.switch.arms.map((a, i) => ({ i, label: a.label, targetIds: a.targetIds })) }));
    },
    // Overlay switch nodes (for parity-driven collapse/mark tests).
    overlaySwitchNodes() {
      const g = go();
      if (!g || !g.graph) return [];
      return g.graph.nodes.filter((n) => n.switch)
        .map((n) => ({ id: n.id, stateName: n.switch.stateName,
          arms: n.switch.arms.map((a, i) => ({ i, label: a.label, targetIds: a.targetIds })) }));
    },
    // Overlay (floats over any tab) hooks for headless validation.
    openOverlay: (key) => openDialogFromKey(key),
    closeOverlay: () => closeDialogOverlay(),
    overlayOpenInTab: () => overlayOpenInTab(),
    get overlayOpen() { return !!(dialogOverlay && dialogOverlay.open_); },
    get overlayKey() { return dialogOverlay ? dialogOverlay.openKey : null; },
    get overlaySpec() { return dialogOverlay ? dialogOverlay.spec : null; },
    get overlaySelected() { return dialogOverlay ? dialogOverlay.selectedId : null; },
    get overlayCrumbs() { return dialogOverlay ? dialogOverlay.crumbStack.map((c) => c.spec) : []; },
    get overlayNodeCount() { const g = go(); return g && g.graph ? g.graph.nodes.length : 0; },
    get overlayEdgeCount() { const g = go(); return g && g.graph ? g.graph.edges.length : 0; },
    get crumbs() { return dialogFull ? dialogFull.crumbStack.map((c) => c.spec) : []; },
  };
}

// -- dialog graph overlay ---------------------------------------------------
//
// A floating panel that renders one conversation over WHATEVER tab is showing,
// without touching the DIALOG tab's own state. It is now the SAME DialogView
// class as the tab (dialogOverlay, modal:true) — full feature parity — so these
// functions are thin wrappers routing through it plus the overlay-only DOM hooks
// (header title, inspector strip, backdrop/close, show/hide) that the shared
// DialogView deps dispatch to.

/**
 * Deep-link entry from the ⤴ graph links: open the dialog-graph OVERLAY on the
 * component/hub containing `key`, selecting it. Does NOT switch tabs and never
 * touches the DIALOG tab's state — the underlying view stays as it was.
 */
function openDialogFromKey(key) {
  const db = ensureDialogDb();
  if (!db) return;
  ensureDialogViews();
  wireTuneOutsideClose();
  dialogOverlay.openModal(key);
  exposeDialog();
}

/** One-time wiring of the overlay panel's chrome (close / backdrop / layout /
 *  inspector-strip toggle). Called from ensureDialogViews(). */
function wireOverlayControls() {
  el.dlgOvlClose.addEventListener('click', closeDialogOverlay);
  el.dlgOvlBackdrop.addEventListener('click', closeDialogOverlay);
  el.dlgOvlOpenTab.addEventListener('click', overlayOpenInTab);
  if (el.dlgOvlLayout) {
    fillLayoutOptions(el.dlgOvlLayout);
    el.dlgOvlLayout.addEventListener('change', () => setDlgLayoutEngine(el.dlgOvlLayout.value));
  }
  el.dlgOvlInspToggle.addEventListener('click', () =>
    el.dlgOvlInspStrip.classList.toggle('collapsed'));
}

/** (deps.showModal) Show the overlay panel. */
function showDialogOverlay() { el.dlgOverlay.classList.remove('hidden'); }

/** (deps.hideModal) Hide the overlay panel + its tune popover. */
function hideDialogOverlay() {
  removeTunePanel('ovl');
  el.dlgOverlay.classList.add('hidden');
}

/** Hide the overlay's node-inspector strip. */
function hideOverlayInsp() {
  el.dlgOvlInspStrip.classList.add('hidden');
  el.dlgOvlInsp.innerHTML = '';
}

/**
 * Fill the overlay header: conversation title, its breadcrumb trail, and the
 * SHARED toolbar (layout / chapter / dev / ⚙ tune / fit / snap / manual / marks)
 * — the same buildDialogToolbar the tab uses, so the overlay has full parity.
 */
function renderOverlayHeader() {
  const v = dialogOverlay;
  const db = dialogDb;
  // Title = the current view's first-line summary.
  let title = '';
  const spec = v.spec;
  if (typeof spec === 'number') {
    const comp = db.components[spec];
    title = comp ? compTitle(comp) : `comp ${spec}`;
  } else if (spec && spec.forwardFrom !== undefined) {
    const n = db.nodes.get(spec.forwardFrom);
    title = n ? (dialogNodeSummary(n) || db.speakerName(n) || String(spec.forwardFrom)) : '';
  } else if (spec && spec.hubKey !== undefined) {
    const start = db.nodeByKey(spec.hubKey) || db.nodes.get(spec.hubKey);
    title = start ? (dialogNodeSummary(start) || db.speakerName(start) || String(spec.hubKey)) : '';
  }
  el.dlgOvlTitle.textContent = truncate(title || 'dialog', 40);
  el.dlgOvlTitle.title = title;

  // Breadcrumbs (only shown when the user has drilled in).
  el.dlgOvlCrumbs.innerHTML = '';
  if (v.crumbStack.length > 1) {
    v.crumbStack.forEach((c, i) => {
      if (i > 0) {
        const sep = document.createElement('span');
        sep.className = 'sep';
        sep.textContent = '›';
        el.dlgOvlCrumbs.appendChild(sep);
      }
      const span = document.createElement('span');
      const isCur = i === v.crumbStack.length - 1;
      span.className = 'crumb' + (isCur ? ' cur' : '');
      span.textContent = crumbLabel(c);
      if (!isCur) span.addEventListener('click', () => v.popToCrumb(i));
      el.dlgOvlCrumbs.appendChild(span);
    });
  }

  // The SHARED toolbar (manual / marks / snap now work in the overlay too). Built
  // into the header's own holder so the existing layout: <select> + tune holder
  // in the markup are superseded by the toolbar controls. The static layout
  // dropdown is kept in sync for users who use it; the toolbar builds its own.
  const holder = document.getElementById('dlgOvlTuneHolder');
  if (holder) { holder.innerHTML = ''; buildDialogToolbar(v, holder); }
  if (el.dlgOvlLayout) el.dlgOvlLayout.value = dlgSettings.layoutPreset;
}

/**
 * "open in DIALOG tab ⇗": switch to the DIALOG tab, navigating it to the
 * overlay's CURRENT view. The navigation pushes onto the tab's existing
 * breadcrumb trail (never clears it). Then close the overlay.
 */
function overlayOpenInTab() {
  const spec = dialogOverlay.spec;
  const select = dialogOverlay.selectedId;
  closeDialogOverlay();
  setView('dialog');
  if (spec === null || spec === undefined) return;
  if (typeof spec === 'number') dialogFull.openComponent(spec, { select });
  else if (spec.forwardFrom !== undefined) dialogFull.openForward(spec.forwardFrom, { select });
  else if (spec.hubKey !== undefined) dialogFull.openHub(spec.hubKey, { select });
}

/** Close the overlay, leaving the underlying view (and its READY) untouched. */
function closeDialogOverlay() {
  if (!dialogOverlay || !dialogOverlay.open_) return;
  dialogOverlay.close();
  refreshReadyStatus();
  exposeDialog();
}

// ---------------------------------------------------------------- info panel
// Stats render as a compact 2-column grid (label / value) rather than a table.
function infoTable(rows) {
  el.infoBody.innerHTML = `<div class="grid">${rows.join('')}</div>`;
}

function infoRow(k, v) {
  return `<div class="k">${k}</div><div class="v">${v}</div>`;
}

function showModelInfo(model) {
  const s = lastStats || {};
  const rows = [];
  const add = (k, v) => rows.push(infoRow(k, v));

  add('name', escapeHtml(model.name));
  add('index', model.index);
  add('bFlags', '0x' + model.bFlags.toString(16).padStart(2, '0'));
  add('bKind', model.bKind);
  add('bPriority', model.bPriority);
  add('bShift', model.bShift);
  add('nRadius', model.nRadius);
  add('LOD count', model.nLodCount);

  const thr = model.lods.map((l, i) => `${i}:${l.threshold}`).join(' ');
  add('LOD thresholds', thr || '—');
  add('parts', s.parts ?? 0);
  add('verts', s.verts ?? 0);
  add('polys', s.polys ?? 0);
  add('tris', s.tris ?? 0);
  if (s.lines) add('lines', s.lines);
  if (s.points) add('points', s.points);
  if (s.nonMesh) {
    const bits = [];
    if (s.sprites) bits.push(`${s.sprites} sprite`);
    if (s.circles) bits.push(`${s.circles} circle`);
    if (s.spriteFallback) bits.push(`${s.spriteFallback} placeholder`);
    add('sprite/point parts', `${s.nonMesh} (${bits.join(', ') || '—'})`);
  }
  if (s.bandFills) add('ground band fills', s.bandFills);
  if (s.textured || s.texturedFallback) {
    const banksUsed = s.banksUsed && s.banksUsed.size
      ? [...s.banksUsed].sort((a, b) => a - b).map((b) => `slot${b}`).join(',')
      : '—';
    add('textured polys', `${s.textured} (banks ${banksUsed})`);
    if (s.texturedFallback) add('textured fallback', s.texturedFallback);
  }
  add('sprite banks', banks && banks.slots.length ? banks.slots.length : 0);
  add('palette', escapeHtml(palette.name) + (palette.fallback ? ' (fallback)' : ''));
  add('remap', remap && remap.name
    ? `${escapeHtml(remap.name)} (${remap.count} entries)`
    : 'none');

  if (model.empty) add('note', '<span style="color:#cc9">empty — no geometry</span>');
  if (model.error) add('parse error', `<span style="color:#f88">${escapeHtml(model.error)}</span>`);

  infoTable(rows);
}

function showZoneInfo(s) {
  const rows = [];
  const add = (k, v) => rows.push(infoRow(k, v));
  add('zone', `Z${s.zone}`);
  add('tiles (.WLD)', s.tiles);
  add('placements', s.placements);
  add('instanced', s.instanced);
  add('distinct models', s.distinctModels);
  if (s.gridTiles) add('map grid tiles', s.gridTiles);
  if (s.duplicates) add('duplicate placements', s.duplicates);
  if (s.emptyModels) add('empty models', s.emptyModels);
  if (s.outOfRange) add('out-of-range ids', s.outOfRange);
  if (s.modelErrors) add('model build errors', s.modelErrors);
  if (s.spawned) add('spawned objects', `${s.spawned} (${spawnVisibleCount()} visible in ch ${chapter})`);
  if (s.spawnSkipped) add('spawns skipped (dup coord)', s.spawnSkipped);
  add('shape table', `Z${s.zone}.TBL`);
  // Entities section: state-record and gap counts from the game-data join.
  if (gameData && s.zone) {
    const recs = gameData.zoneRecords(s.zone);
    const gaps = gameData.gaps(s.zone);
    const startup = recs.filter((r) => r.source === 'startup').length;
    const objf = recs.length - startup;
    add('entities w/ record', `${recs.length} (${startup} GAM, ${objf} OBJFIXED)`);
    add('parse gaps', gaps.length);
    if (!gameData.available.startup) add('game data', 'STARTUP.GAM absent (OBJFIXED only)');
  } else {
    add('game data', 'not loaded');
  }
  infoTable(rows);
}

function escapeHtml(s) {
  return String(s).replace(/[&<>]/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;' }[c]));
}

// ---------------------------------------------------------------- cleanup
function disposeGroup(group) {
  group.traverse((o) => {
    if (o.geometry) o.geometry.dispose();
    if (o.material) {
      const mats = Array.isArray(o.material) ? o.material : [o.material];
      mats.forEach((m) => {
        if (m.map) m.map.dispose(); // palette-resolved DataTextures
        if (m.uniforms && m.uniforms.uAtlas) m.uniforms.uAtlas.value.dispose();
        m.dispose();
      });
    }
  });
}

// ---------------------------------------------------------------- events
function wireEvents() {
  el.tabModels.addEventListener('click', () => setView('models'));
  el.tabZones.addEventListener('click', () => setView('zones'));
  el.tabScx.addEventListener('click', () => setView('scx'));
  el.tabDialog.addEventListener('click', () => setView('dialog'));
  el.scxPalSelect.addEventListener('change', () => {
    if (view === 'scx' && selectedScx) selectScx(selectedScx);
  });
  el.dlgSearch.addEventListener('input', () => { if (view === 'dialog') rebuildDialogSidebar(); });
  el.helpBtn.addEventListener('click', () =>
    el.helpPanel.classList.toggle('hidden'));
  el.navSelect.addEventListener('change', () => applyNav(el.navSelect.value));
  el.gridChk.addEventListener('change', () => {
    // Pure visibility flip — no zone rebuild.
    const grid = currentGroup && currentGroup.getObjectByName('tileGrid');
    if (grid) grid.visible = el.gridChk.checked;
  });
  el.chapterSelect.addEventListener('change', () => {
    chapter = parseInt(el.chapterSelect.value, 10) || 1;
    // Chapter only changes hotspot lists/markers + spawn visibility — no zone
    // rebuild.
    buildMarkers();
    buildEncounterMarkers();
    applySpawnVisibility();
    // Refresh "spawned objects: N (M visible in ch K)".
    if (view === 'zones' && zoneBuild && lastStats) showZoneInfo(lastStats);
    exposeEditor();
    // The "hotspot tiles" filter depends on the chapter.
    if (view === 'zones' && listMode === 'entities') rebuildList();
  });
  el.segZones.addEventListener('click', () => setListMode('zones'));
  el.segEntities.addEventListener('click', () => setListMode('entities'));
  el.kindSelect.addEventListener('change', rebuildList);
  el.dataChk.addEventListener('change', () => {
    if (markersGroup) markersGroup.visible = el.dataChk.checked;
  });
  el.encChk.addEventListener('change', () => {
    if (encounterMarkers) encounterMarkers.visible = el.encChk.checked;
    if (encounterRects) encounterRects.visible = el.encChk.checked;
    if (encounterLinks) encounterLinks.visible = el.encChk.checked;
  });
  // Zone picking with the LEFT button. In fly/walk the left button doubles as
  // drag-look (fpcontrols.js): a sub-threshold press-release is a pick, a drag
  // past 4px is a look and must not pick. Skip when the pointer is locked
  // (mid look-drag / toggle free-look, stale coordinates) and after drags —
  // `click` fires for a press-drag-release too (orbit rotation, drag-look),
  // which would select whatever sits under the release. `fp.dragLooked` is the
  // controller's own verdict that the release turned the camera, so the two
  // paths never double-handle the same gesture.
  let pickDownAt = null;
  renderer.domElement.addEventListener('mousedown', (e) => {
    if (e.button === 0) pickDownAt = [e.clientX, e.clientY];
  });
  renderer.domElement.addEventListener('click', (e) => {
    const moved = !pickDownAt ||
      Math.abs(e.clientX - pickDownAt[0]) + Math.abs(e.clientY - pickDownAt[1]) > 4;
    if (view === 'zones' && !document.pointerLockElement && !moved
      && !(fp.enabled && fp.dragLooked)) {
      pickAt(e.clientX, e.clientY);
    }
  });
  // Dialog keyboard. Esc closes the overlay FIRST (from any tab); only if no
  // overlay is open does it fall through to clear the DIALOG tab's canvas
  // selection. +/- zoom the active dialog canvas (overlay if open, else tab).
  window.addEventListener('keydown', (e) => {
    if (e.target && /^(INPUT|TEXTAREA|SELECT)$/.test(e.target.tagName)) return;
    // Overlay Esc + zoom work over any underlying tab.
    if (dialogOverlay && dialogOverlay.open_) {
      if (e.key === 'Escape') { closeDialogOverlay(); return; }
      if (e.key === '+' || e.key === '=') { dialogOverlay.zoomBy(1.15); return; }
      if (e.key === '-' || e.key === '_') { dialogOverlay.zoomBy(0.87); return; }
      return;
    }
    if (view !== 'dialog' || !dialogFull) return;
    if (e.key === 'Escape') {
      dialogFull.clearSelection();
    } else if (e.key === '+' || e.key === '=') {
      dialogFull.zoomBy(1.15);
    } else if (e.key === '-' || e.key === '_') {
      dialogFull.zoomBy(0.87);
    }
  });
  el.tblSelect.addEventListener('change', () => loadTable(el.tblSelect.value));
  el.modeSelect.addEventListener('change', rebuildCurrent);
  el.palSelect.addEventListener('change', rebuildCurrent);
  el.lodSelect.addEventListener('change', rebuildMesh);
  el.filter.addEventListener('input', rebuildList);
}

function rebuildCurrent() {
  if (view === 'zones') {
    if (selectedZone) selectZone(selectedZone);
  } else {
    rebuildMesh();
  }
}

// ---------------------------------------------------------------- boot
async function boot() {
  // ?bare=1 : graph-only mode — hide the sidebar + floating panels (CSS), so the
  // dialog canvas fills the window. Applied before layout so widths are correct.
  if (new URLSearchParams(location.search).get('bare')) document.body.classList.add('bare');

  initThree();
  wireEvents();
  exposeFpTest();

  // Chapter selector (1–10) drives which hotspots are listed/marked.
  for (let c = 1; c <= 10; c++) {
    const o = document.createElement('option');
    o.value = c;
    o.textContent = `ch ${c}`;
    el.chapterSelect.appendChild(o);
  }
  // Models-tab link from the inspector: switch tab, load the zone TBL, select.
  setOpenModelHandler((modelIndex) => {
    setView('models');
    if (selectedZone) el.tblSelect.value = `Z${selectedZone}.TBL`;
    loadTable(el.tblSelect.value, { model: modelIndex });
  });
  // Inspector tab switches re-paint the READY line (` TAB:<active>`) so headless
  // runs can assert the active tab.
  setTabChangeHandler(() => refreshReadyStatus());
  // Zone-inspector "⤴ graph" deep link: switch to the DIALOG tab on a key.
  setDialogGraphHandler((key) => openDialogFromKey(key));
  // Always-available headless entry for the dialog-graph overlay (independent of
  // whether the DIALOG tab has been entered, which is what defines window.__dialog).
  window.__openDialogGraph = (key) => openDialogFromKey(key);
  // ?tab=<name> selects a tab on the auto-opened inspector.
  const tabParam = new URLSearchParams(location.search).get('tab');
  if (tabParam) requestTab(tabParam);

  setStatus('fetching archive (11.5 MB)…');
  try {
    archive = await loadArchive(DATA.rmf, DATA.dat);
  } catch (e) {
    return fatal('archive load: ' + e.message);
  }

  const tbls = archive.tableNames();
  el.tblSelect.innerHTML = '';
  for (const t of tbls) {
    const o = document.createElement('option');
    o.value = t;
    o.textContent = t;
    el.tblSelect.appendChild(o);
  }
  zones = listZones(archive);

  // Editor game-data join. STARTUP.GAM may 404; loadGameData degrades and the
  // inspector reports availability — never fatal.
  try {
    gameData = await loadGameData(archive);
  } catch (e) {
    gameData = null;
    console.warn('game data load failed:', e && e.message);
  }

  const p = params();
  const tbl = p.tbl && archive.hasResource(p.tbl) ? p.tbl.toUpperCase() : (tbls.includes('Z01.TBL') ? 'Z01.TBL' : tbls[0]);
  // Default landing (no view/tbl/model params): the ZONES view on zone 01 with
  // the encounter/hotspot overlay on. Explicit params keep today's behavior.
  const bareDefault = !p.view && !p.tbl && !p.model;
  // The model mesh is skipped when boot lands on a non-models view — the zone
  // build replaces it immediately, so rendering it is a wasted flash.
  const deferModel = ((p.view && p.view !== 'models') || bareDefault)
    && !p.model && !p.lod;

  if (p.mode) el.modeSelect.value = p.mode;
  if (p.palette) el.palSelect.value = p.palette;
  if (p.yaw) {
    const y = parseFloat(p.yaw);
    if (!isNaN(y)) urlYaw = y;
  }
  if (p.pitch) {
    const v = parseFloat(p.pitch);
    if (!isNaN(v)) urlPitch = v;
  }

  // Images tab data: all .SCX screens + .BMX banks + the palette dropdown.
  scxNames = archive.names()
    .filter((n) => n.endsWith('.SCX') || n.endsWith('.BMX')).sort();
  palNames = archive.names().filter((n) => n.endsWith('.PAL')).sort();
  el.scxPalSelect.innerHTML = '<option value="auto" selected>(auto)</option>'
    + palNames.map((n) => `<option value="${n}">${n}</option>`).join('');

  setStatus(`loaded ${archive.names().length} resources, ${tbls.length} tables, ${zones.length} zones`);
  loadTable(tbl, { model: p.model, lod: p.lod, defer: deferModel });

  if (p.nav && ['fly', 'walk', 'orbit'].includes(p.nav)) el.navSelect.value = p.nav;
  const chParam = new URLSearchParams(location.search).get('chapter');
  if (chParam) {
    const c = parseInt(chParam, 10);
    if (c >= 1 && c <= 10) { chapter = c; el.chapterSelect.value = String(c); }
  }
  if (new URLSearchParams(location.search).get('list') === 'entities') {
    listMode = 'entities';
  }
  if (new URLSearchParams(location.search).get('grid')) el.gridChk.checked = true;
  if (new URLSearchParams(location.search).get('data')) el.dataChk.checked = true;
  if (new URLSearchParams(location.search).get('enc')) el.encChk.checked = true;
  if (new URLSearchParams(location.search).get('help')) {
    el.helpPanel.classList.remove('hidden');
  }

  if (p.view === 'zones' || bareDefault) {
    if (bareDefault) el.encChk.checked = true; // land with hotspots visible
    const zone = p.zone ? String(parseInt(p.zone, 10)).padStart(2, '0')
      : (bareDefault ? '01' : null);
    setView('zones', { zone });
  } else if (p.view === 'dialog') {
    setView('dialog');
  } else if (p.view === 'scx') {
    const scx = new URLSearchParams(location.search).get('scx');
    setView('scx', { scx: scx ? scx.toUpperCase() : null });
  }
}

boot();
