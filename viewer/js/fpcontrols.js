// First-person camera controller for the zone view: fly and walk modes.
//
// Editor-style controls, in three.js world space (Y up — the zone root
// already maps BaK Z-up into it):
//   LEFT drag           touchpad-friendly look; a drag under 4px is a pick
//   RIGHT mouse (hold)  capture the pointer and look around; release frees it
//   double-click        toggle pointer-lock free-look (Esc / click exits)
//   W/A/S/D  move   (walk projects onto the ground plane)
//   Q or C   down,  E or Space  up          (fly only)
//   Shift    4x speed boost
//   wheel               adjust base speed (normalized); ctrl+wheel = dolly
//
// The left button doubles as drag-look and pick: it only looks once the drag
// passes the pick threshold, so a plain click still falls through to the
// picker (main.js). Walk mode pins the camera to eye height above the ground.

import * as THREE from 'three';

const LOOK_SPEED = 0.0022; // rad per pixel (shared by drag-look and pointer lock)
const BOOST = 4;
const PITCH_LIMIT = Math.PI / 2 - 0.01;
const DRAG_THRESHOLD = 4; // px of movement before a left drag becomes a look
const WHEEL_LINE_PX = 8; // DOM_DELTA_LINE → pixels (touchpad normalization)
const WHEEL_PAGE_PX = 24; // DOM_DELTA_PAGE → pixels
const WHEEL_CLAMP = 50; // max |delta| applied per wheel event
const DOLLY_STEP = 40; // world units per clamped pinch-delta unit

export class FPControls {
  /**
   * @param {THREE.PerspectiveCamera} camera
   * @param {HTMLElement} domElement  the renderer canvas
   */
  constructor(camera, domElement) {
    this.camera = camera;
    this.domElement = domElement;
    this.enabled = false;
    this.mode = 'fly'; // 'fly' | 'walk'
    this.speed = 24000; // units/second, wheel-adjustable
    this.eyeHeight = 230; // walk-mode camera height over the ground plane
    this.yaw = 0;
    this.pitch = 0;
    this._keys = new Set();
    this._onLockChange = null; // optional UI callback(locked)

    // Left-drag look state. `_drag` is null until a pointerdown; its `moved`
    // flag flips once the movement clears DRAG_THRESHOLD. `dragLooked`
    // records that the most recent drag actually turned the camera, so the
    // picker (main.js) can skip a look-drag release and a following dblclick
    // toggle can veto itself.
    this._drag = null; // {id, startX, startY, lastX, lastY, moved}
    this.dragLooked = false;

    this._mousemove = (e) => {
      if (!this.enabled || document.pointerLockElement !== this.domElement) return;
      this.yaw -= e.movementX * LOOK_SPEED;
      this.pitch -= e.movementY * LOOK_SPEED;
      this.pitch = Math.max(-PITCH_LIMIT, Math.min(PITCH_LIMIT, this.pitch));
    };
    this._pointerdown = (e) => {
      // Left-button drag-look, pointer-lock free-look excluded (that path uses
      // movementX/Y from _mousemove). No-op in orbit mode (not enabled).
      if (!this.enabled || e.button !== 0 ||
          document.pointerLockElement === this.domElement) return;
      this._drag = {
        id: e.pointerId, startX: e.clientX, startY: e.clientY,
        lastX: e.clientX, lastY: e.clientY, moved: false,
      };
      this.dragLooked = false;
    };
    this._pointermove = (e) => {
      const d = this._drag;
      if (!d || e.pointerId !== d.id) return;
      if (!d.moved) {
        if (Math.abs(e.clientX - d.startX) + Math.abs(e.clientY - d.startY)
            <= DRAG_THRESHOLD) return;
        d.moved = true;
        this.dragLooked = true;
        // Keep tracking even if the pointer leaves the canvas.
        if (this.domElement.setPointerCapture) {
          try { this.domElement.setPointerCapture(d.id); } catch (_) { /* ignore */ }
        }
      }
      // Same radians/px as the pointer-lock path.
      this.yaw -= (e.clientX - d.lastX) * LOOK_SPEED;
      this.pitch -= (e.clientY - d.lastY) * LOOK_SPEED;
      this.pitch = Math.max(-PITCH_LIMIT, Math.min(PITCH_LIMIT, this.pitch));
      d.lastX = e.clientX;
      d.lastY = e.clientY;
    };
    this._pointerup = (e) => {
      const d = this._drag;
      if (!d || e.pointerId !== d.id) return;
      if (this.domElement.releasePointerCapture &&
          this.domElement.hasPointerCapture &&
          this.domElement.hasPointerCapture(d.id)) {
        try { this.domElement.releasePointerCapture(d.id); } catch (_) { /* ignore */ }
      }
      this._drag = null;
      // dragLooked stays true through the trailing click/dblclick so the picker
      // and toggle can see it; it is reset on the next pointerdown.
    };
    this._dblclick = (e) => {
      // Double-click toggles pointer-lock free-look. A dblclick that trails a
      // drag-look must not toggle (the drag already turned the camera).
      if (!this.enabled || this.dragLooked) return;
      if (document.pointerLockElement !== this.domElement) {
        e.preventDefault();
        this.domElement.requestPointerLock();
      }
    };
    this._keydown = (e) => {
      if (!this.enabled) return;
      this._keys.add(e.code);
      if (e.code === 'Space') e.preventDefault();
    };
    this._keyup = (e) => this._keys.delete(e.code);
    this._mousedown = (e) => {
      if (!this.enabled) return;
      if (e.button === 2 && document.pointerLockElement !== this.domElement) {
        this.domElement.requestPointerLock();
      } else if (e.button === 0 && document.pointerLockElement === this.domElement) {
        // In toggle free-look a left click exits the toggle (it must NOT pick;
        // main.js already gates picking on !pointerLockElement).
        document.exitPointerLock();
      }
    };
    this._mouseup = (e) => {
      if (e.button === 2 && document.pointerLockElement === this.domElement) {
        document.exitPointerLock();
      }
    };
    this._contextmenu = (e) => {
      if (this.enabled) e.preventDefault();
    };
    this._wheel = (e) => {
      // Works while looking (pointer lock) AND while free (touchpad drag-look).
      if (!this.enabled) return;
      e.preventDefault();
      // Normalize across deltaMode so a touchpad's small pixel deltas and a
      // wheel-mouse's line/page deltas are comparable, then clamp per event.
      let d = e.deltaY;
      if (e.deltaMode === 1) d *= WHEEL_LINE_PX; // DOM_DELTA_LINE
      else if (e.deltaMode === 2) d *= WHEEL_PAGE_PX; // DOM_DELTA_PAGE
      d = THREE.MathUtils.clamp(d, -WHEEL_CLAMP, WHEEL_CLAMP);

      if (e.ctrlKey) {
        // Pinch-zoom gesture (browsers report it as ctrl+wheel): dolly the
        // camera along its look direction. Scroll up / pinch out = forward.
        const fwd = this.camera.getWorldDirection(new THREE.Vector3());
        this.camera.position.addScaledVector(fwd, -d * DOLLY_STEP);
        if (this.mode === 'walk') this.camera.position.y = this.eyeHeight;
        return;
      }
      // Plain wheel = speed. Scale by the clamped magnitude so a gentle
      // two-finger scroll nudges rather than slams the speed.
      const factor = Math.pow(1.25, -d / 10);
      this.speed = THREE.MathUtils.clamp(this.speed * factor, 500, 500000);
    };
    this._lockchange = () => {
      if (this._onLockChange) {
        this._onLockChange(document.pointerLockElement === this.domElement);
      }
    };

    document.addEventListener('mousemove', this._mousemove);
    document.addEventListener('keydown', this._keydown);
    document.addEventListener('keyup', this._keyup);
    document.addEventListener('mouseup', this._mouseup);
    document.addEventListener('pointerlockchange', this._lockchange);
    domElement.addEventListener('mousedown', this._mousedown);
    domElement.addEventListener('contextmenu', this._contextmenu);
    domElement.addEventListener('wheel', this._wheel, { passive: false });
    domElement.addEventListener('pointerdown', this._pointerdown);
    domElement.addEventListener('pointermove', this._pointermove);
    domElement.addEventListener('pointerup', this._pointerup);
    domElement.addEventListener('pointercancel', this._pointerup);
    domElement.addEventListener('dblclick', this._dblclick);
  }

  /** Take over the camera, keeping its current view direction. */
  enable(mode) {
    this.mode = mode;
    this.enabled = true;
    const dir = this.camera.getWorldDirection(new THREE.Vector3());
    this.yaw = Math.atan2(-dir.x, -dir.z);
    this.pitch = Math.asin(THREE.MathUtils.clamp(dir.y, -1, 1));
    if (mode === 'walk') this.camera.position.y = this.eyeHeight;
  }

  disable() {
    this.enabled = false;
    this._keys.clear();
    this._drag = null;
    this.dragLooked = false;
    if (document.pointerLockElement === this.domElement) document.exitPointerLock();
  }

  /** Per-frame integration. @param {number} dt seconds */
  update(dt) {
    if (!this.enabled) return;

    // Look
    const q = new THREE.Quaternion().setFromEuler(
      new THREE.Euler(this.pitch, this.yaw, 0, 'YXZ'));
    this.camera.quaternion.copy(q);

    // Move
    const k = this._keys;
    let step = this.speed * dt;
    if (k.has('ShiftLeft') || k.has('ShiftRight')) step *= BOOST;

    const fwd = new THREE.Vector3(0, 0, -1).applyQuaternion(q);
    const right = new THREE.Vector3(1, 0, 0).applyQuaternion(q);
    if (this.mode === 'walk') {
      fwd.y = 0;
      right.y = 0;
      fwd.normalize();
      right.normalize();
    }

    const move = new THREE.Vector3();
    if (k.has('KeyW')) move.add(fwd);
    if (k.has('KeyS')) move.sub(fwd);
    if (k.has('KeyD')) move.add(right);
    if (k.has('KeyA')) move.sub(right);
    if (this.mode === 'fly') {
      if (k.has('KeyE') || k.has('Space')) move.y += 1;
      if (k.has('KeyQ') || k.has('KeyC')) move.y -= 1;
    }
    if (move.lengthSq() > 0) {
      move.normalize().multiplyScalar(step);
      this.camera.position.add(move);
    }
    if (this.mode === 'walk') this.camera.position.y = this.eyeHeight;
  }

  dispose() {
    this.disable();
    document.removeEventListener('mousemove', this._mousemove);
    document.removeEventListener('keydown', this._keydown);
    document.removeEventListener('keyup', this._keyup);
    document.removeEventListener('mouseup', this._mouseup);
    document.removeEventListener('pointerlockchange', this._lockchange);
    this.domElement.removeEventListener('mousedown', this._mousedown);
    this.domElement.removeEventListener('contextmenu', this._contextmenu);
    this.domElement.removeEventListener('wheel', this._wheel);
    this.domElement.removeEventListener('pointerdown', this._pointerdown);
    this.domElement.removeEventListener('pointermove', this._pointermove);
    this.domElement.removeEventListener('pointerup', this._pointerup);
    this.domElement.removeEventListener('pointercancel', this._pointerup);
    this.domElement.removeEventListener('dblclick', this._dblclick);
  }
}
