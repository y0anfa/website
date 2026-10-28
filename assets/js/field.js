/*
 * field.js: the ASCII field. The only motion on the site, and a quiet one.
 *
 * It is a backdrop: one fixed, full-viewport layer behind the page, low in
 * contrast and slow, a watermark you notice after a few seconds. Two presets,
 * chosen by <html data-field="topo|water"> (topo is the default; anything else
 * falls back to it):
 *   topo   a survey map. Contour lines of a slowly evolving landscape, drawn
 *          with - | / \ ; every fifth contour is an index contour, a little
 *          stronger. About 8% of the cells are lit, the rest stay blank. The
 *          pointer raises a wide, gentle hill (it eases in over about a second
 *          and relaxes over about three) and the lines flow around it.
 *   water  calm water. A blank, still surface; the pointer leaves slow, sparse
 *          rings and a rare drop falls on its own every 6-10 s.
 *
 * Contract (SPEC section 7 and 9): export mountField(root) -> { destroy() },
 * and auto-mount every [data-field-root]. No dependencies, no markup
 * injection, no dynamic code, no inline styles (sizing goes through CSSOM).
 *
 * CSS it expects: .field { position: fixed; inset: 0; z-index: 0;
 * pointer-events: none; font-family: <a mono face>; font-size: 14px;
 * line-height: 1; color: var(--fg) } and .field-canvas { position: absolute;
 * inset: 0 }. The cell metrics and the ink colour come from the root's computed
 * style. The root is sized with a ResizeObserver plus a window resize
 * fallback, and the pointer is read in viewport coordinates (the root is
 * fixed, so they are the same thing as root coordinates).
 *
 * Behaviour:
 *  - The canvas is redrawn by diff; typed arrays only, nothing allocated per
 *    frame. Topo runs at 20 fps (the landscape itself is recomputed at 10 Hz,
 *    on a half-resolution lattice), water at 30. Both take well under 2 ms a
 *    frame on a 2560x1440 viewport. Paused while the document is hidden or the
 *    root is off screen; DPR is capped at 2.
 *  - Glyph alpha is baked into the atlas: 0.13-0.17 for contours, about 0.3 for
 *    index contours, 0.14-0.27 for water rings. It is eased by 12% on a dark
 *    theme, where light ink reads heavier.
 *  - prefers-reduced-motion: one static frame (topo: a map; water: one faint
 *    settled ring), no loop and no pointer effects; redrawn on resize and
 *    theme change.
 *  - The atlas is rebuilt on [data-theme] and [data-field] changes and on the
 *    prefers-color-scheme change. A new [data-field] value swaps the preset.
 *
 * Optional extra (extends the SPEC, harmless if unused):
 *  - mountField(root).stats() returns debug numbers for lab/field.html.
 */

const DPR_CAP = 2;
const CELL_H = 1.25; // default cell height as a multiple of the font size
const DEFAULT_PRESET = 'topo';

/* ------------------------------------------------------------------------ *
 * Pure helpers. Exported so they can be unit-tested in node.
 * ------------------------------------------------------------------------ */

export function mulberry32(seed) {
  let a = seed >>> 0;
  return function () {
    a = (a + 0x6d2b79f5) >>> 0;
    let t = a;
    t = Math.imul(t ^ (t >>> 15), t | 1);
    t ^= t + Math.imul(t ^ (t >>> 7), t | 61);
    return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
  };
}

/** Integer lattice hash to [0, 1). Position based, so a landscape survives a resize. */
export function hash2(ix, iy, salt) {
  let h = (Math.imul(ix, 0x27d4eb2d) ^ Math.imul(iy, 0x165667b1) ^ Math.imul(salt, 0x9e3779b1)) >>> 0;
  h = Math.imul(h ^ (h >>> 15), 0x85ebca6b);
  h = Math.imul(h ^ (h >>> 13), 0xc2b2ae35);
  return ((h ^ (h >>> 16)) >>> 0) / 4294967296;
}

/**
 * Add a Gaussian hill to a height buffer, tapered to exactly zero at
 * `reach` standard deviations. Centre (cx, cy) is in fractional cell units,
 * `sigma` in cell widths, invAspect is the cell height divided by the cell width.
 */
export function addHill(buf, w, h, cx, cy, amp, sigma, reach, invAspect) {
  const R = sigma * reach;
  const ry = R / invAspect;
  const x0 = Math.max(0, Math.floor(cx - R));
  const x1 = Math.min(w - 1, Math.ceil(cx + R));
  const y0 = Math.max(0, Math.floor(cy - ry));
  const y1 = Math.min(h - 1, Math.ceil(cy + ry));
  const k = 1 / (2 * sigma * sigma);
  const R2 = R * R;
  const floor = Math.exp(-reach * reach * 0.5);
  const norm = amp / (1 - floor);
  for (let y = y0; y <= y1; y++) {
    const dy = (y + 0.5 - cy) * invAspect;
    const dy2 = dy * dy;
    let i = y * w + x0;
    for (let x = x0; x <= x1; x++, i++) {
      const dx = x + 0.5 - cx;
      const d2 = dx * dx + dy2;
      if (d2 < R2) buf[i] += norm * (Math.exp(-d2 * k) - floor);
    }
  }
}

/**
 * Critically damped smoothing (the closed form behind "smooth damp"): moves
 * `s.v` toward `target` with no jump in value or in velocity. `omega` is
 * roughly 4.7 / (time to get within 5% of the target). State lives in `s` so
 * nothing is allocated.
 */
export function smoothTo(s, target, omega, dt) {
  const x = omega * dt;
  const e = 1 / (1 + x + 0.48 * x * x + 0.235 * x * x * x);
  const change = s.v - target;
  const temp = (s.vel + omega * change) * dt;
  s.vel = (s.vel - omega * temp) * e;
  s.v = target + (change + temp) * e;
}

/* ------------------------------------------------------------------------ *
 * Glyph tables. Entry 0 is always blank. Alpha is baked into the atlas so a
 * cell is a single drawImage; the field stays quieter than body text.
 * ------------------------------------------------------------------------ */

// topo: index = 1 + shape * 2 + (index contour ? 1 : 0); shapes: - | / \
// (tall strokes carry more ink per cell, so they get a little less alpha)
const TOPO_GLYPHS = [
  ['', 0],
  ['-', 0.17],
  ['-', 0.32],
  ['|', 0.13],
  ['|', 0.26],
  ['/', 0.15],
  ['/', 0.3],
  ['\\', 0.15],
  ['\\', 0.3],
];

const WATER_GLYPHS = [
  ['', 0],
  ['.', 0.14],
  ['·', 0.18],
  [':', 0.22],
  ['-', 0.27],
];

/* ------------------------------------------------------------------------ *
 * Preset: topo
 *
 * Height field: three octaves of 2D gradient noise whose lattice gradients
 * slowly rotate, which makes the landscape evolve without ever jittering.
 * Heights are in contour intervals, so a contour sits at every integer and
 * every fifth integer is an index contour.
 *
 * Contours: for each cell the height h and the gradient (gx, gy), both per
 * cell, give the distance to the nearest integer level. The level crosses the
 * cell when |h - level| <= 0.5 * max(|gx|, |gy|). That is the digital-line
 * rule of marching squares for a locally linear field: exactly one cell per
 * column on shallow lines and one per row on steep ones, so lines are thin,
 * unbroken and 8-connected. The glyph comes from the gradient direction.
 * ------------------------------------------------------------------------ */

const TOPO = {
  fps: 20,
  cell: 1.1, // cell height, multiples of the font size; tight, so | and / chains read as one line
  baseDt: 0.1, // the landscape is recomputed at 10 Hz; contours move a few px a second
  relief: 4.3, // contour intervals per unit of noise; sets how dense the map is (about 8% of cells lit)
  octaves: [
    // size: lattice spacing in css px; amp: weight; spin: gradient rotation, rad/s
    { size: 640, amp: 1, spin: 0.028, salt: 1 },
    { size: 290, amp: 0.4, spin: 0.036, salt: 2 },
    { size: 140, amp: 0.13, spin: 0.045, salt: 3 },
  ],
  every: 5, // index contour period
  band: 0.5, // half-width of a line, in cells along its major axis
  steep: 0.3, // below this cols-per-row a steep line is |, above it / or \
  shallow: 0.3, // below this rows-per-col a shallow line is -, above it / or \
  hill: { levels: 2.4, sigma: 6.4, reach: 2.6, rise: 4.6, fall: 1.6, follow: 7 },
  staticT: 41, // the landscape at rest, for reduced motion
};

export function createTopo(seed) {
  const sd = seed === undefined ? (Math.random() * 1024) | 0 : seed | 0;
  const oct = TOPO.octaves.map((o) => ({
    size: o.size,
    amp: o.amp * TOPO.relief,
    spin: o.spin,
    salt: o.salt + sd * 16,
    nw: 0,
    nh: 0,
    ph: null, // lattice node: gradient phase and spin
    sp: null,
    gx: null, // lattice node: current gradient
    gy: null,
    cix: null, // per column: lattice cell, fraction, fade
    cfx: null,
    cu: null,
    riy: null, // per row
    rfy: null,
    rv: null,
  }));
  let w = 0;
  let h = 0;
  let base = null; // landscape, in contour intervals
  let hh = null; // landscape plus the pointer hill
  let coarse = null; // the landscape on every second cell
  let cw2 = 0;
  let ch2 = 0;
  let inv = 2.08; // cell height / cell width
  let t = 0;
  let acc = 0;
  let dirty = true;
  let hillWas = false;
  let started = false;

  // the pointer hill
  const amp = { v: 0, vel: 0 };
  const hx = { v: 0, vel: 0 };
  const hy = { v: 0, vel: 0 };
  let want = false;
  let px = 0;
  let py = 0;

  const fade = (f) => f * f * f * (f * (f * 6 - 15) + 10);

  // The landscape is smooth, so it is evaluated on a lattice of every second
  // cell and interpolated: a quarter of the noise work for the same lines.
  function layoutOctave(o, cols, rows, cellW, cellH, ox, oy) {
    const cw = (cols >> 1) + 2;
    const ch = (rows >> 1) + 2;
    const nw = Math.floor((ox + 2 * cw * cellW) / o.size) + 2;
    const nh = Math.floor((oy + 2 * ch * cellH) / o.size) + 2;
    if (nw !== o.nw || nh !== o.nh) {
      o.nw = nw;
      o.nh = nh;
      o.ph = new Float32Array(nw * nh);
      o.sp = new Float32Array(nw * nh);
      o.gx = new Float32Array(nw * nh);
      o.gy = new Float32Array(nw * nh);
      for (let j = 0; j < nh; j++) {
        for (let i = 0; i < nw; i++) {
          o.ph[j * nw + i] = hash2(i, j, o.salt * 2) * 6.283185307;
          const s = hash2(i, j, o.salt * 2 + 1);
          o.sp[j * nw + i] = (s < 0.5 ? -1 : 1) * o.spin * (0.45 + 0.55 * Math.abs(s * 2 - 1));
        }
      }
    }
    if (!o.cix || o.cix.length !== cw) {
      o.cix = new Int32Array(cw);
      o.cfx = new Float32Array(cw);
      o.cu = new Float32Array(cw);
    }
    if (!o.riy || o.riy.length !== ch) {
      o.riy = new Int32Array(ch);
      o.rfy = new Float32Array(ch);
      o.rv = new Float32Array(ch);
    }
    for (let c = 0; c < cw; c++) {
      const p = (ox + (2 * c + 0.5) * cellW) / o.size;
      const i = Math.floor(p);
      o.cix[c] = i;
      o.cfx[c] = p - i;
      o.cu[c] = fade(p - i);
    }
    for (let r = 0; r < ch; r++) {
      const p = (oy + (2 * r + 0.5) * cellH) / o.size;
      const j = Math.floor(p);
      o.riy[r] = j;
      o.rfy[r] = p - j;
      o.rv[r] = fade(p - j);
    }
    if (!coarse || coarse.length !== cw * ch) coarse = new Float32Array(cw * ch);
    cw2 = cw;
    ch2 = ch;
  }

  function fillBase() {
    const cw = cw2;
    const ch = ch2;
    for (let n = 0; n < oct.length; n++) {
      const o = oct[n];
      const gx = o.gx;
      const gy = o.gy;
      for (let k = 0; k < gx.length; k++) {
        const a = o.ph[k] + o.sp[k] * t;
        gx[k] = Math.cos(a);
        gy[k] = Math.sin(a);
      }
      const nw = o.nw;
      const cix = o.cix;
      const cfx = o.cfx;
      const cu = o.cu;
      const gain = o.amp;
      const add = n > 0;
      for (let r = 0; r < ch; r++) {
        const fy = o.rfy[r];
        const fy1 = fy - 1;
        const v = o.rv[r];
        const r0 = o.riy[r] * nw;
        const r1 = r0 + nw;
        let i = r * cw;
        for (let c = 0; c < cw; c++, i++) {
          const a = r0 + cix[c];
          const b = r1 + cix[c];
          const fx = cfx[c];
          const fx1 = fx - 1;
          const n00 = gx[a] * fx + gy[a] * fy;
          const n10 = gx[a + 1] * fx1 + gy[a + 1] * fy;
          const n01 = gx[b] * fx + gy[b] * fy1;
          const n11 = gx[b + 1] * fx1 + gy[b + 1] * fy1;
          const u = cu[c];
          const top = n00 + u * (n10 - n00);
          const val = (top + v * (n01 + u * (n11 - n01) - top)) * gain;
          coarse[i] = add ? coarse[i] + val : val;
        }
      }
    }
    // interpolate up to every cell
    for (let y = 0; y < h; y++) {
      const r0 = (y >> 1) * cw;
      const r1 = r0 + cw;
      const fy = (y & 1) * 0.5;
      let i = y * w;
      for (let x = 0; x < w; x++, i++) {
        const c = r0 + (x >> 1);
        const d = r1 + (x >> 1);
        const fx = (x & 1) * 0.5;
        const top = coarse[c] + fx * (coarse[c + 1] - coarse[c]);
        const bot = coarse[d] + fx * (coarse[d + 1] - coarse[d]);
        base[i] = top + fy * (bot - top);
      }
    }
  }

  return {
    glyphs: TOPO_GLYPHS,
    fps: TOPO.fps,
    cell: TOPO.cell,

    /** ox, oy: where the grid starts inside the viewport, css px. The landscape is pinned to the viewport, not the grid. */
    resize(cols, rows, cellW, cellH, ox, oy) {
      if (cols !== w || rows !== h || !base) {
        w = cols;
        h = rows;
        base = new Float32Array(w * h);
        hh = new Float32Array(w * h);
      }
      inv = cellH / cellW;
      for (let n = 0; n < oct.length; n++) layoutOctave(oct[n], w, h, cellW, cellH, ox || 0, oy || 0);
      dirty = true;
    },

    /** The first call picks a start time; `still` (reduced motion) pins the landscape and drops the hill. */
    settle(still) {
      if (!started) {
        started = true;
        t = 40 + Math.random() * 3000;
      }
      if (still) {
        t = TOPO.staticT;
        amp.v = amp.vel = 0;
        want = false;
      }
      dirty = true;
    },

    step(dt) {
      t += dt;
      acc += dt;
      if (acc >= TOPO.baseDt) {
        acc = 0;
        dirty = true;
      }
      const H = TOPO.hill;
      if (want) {
        smoothTo(hx, px, H.follow, dt);
        smoothTo(hy, py, H.follow, dt);
      }
      smoothTo(amp, want ? 1 : 0, want ? H.rise : H.fall, dt);
      if (!want && amp.v < 0.002 && Math.abs(amp.vel) < 0.002) amp.v = amp.vel = 0;
      if (amp.v < 0) amp.v = 0; // the smoothing can overshoot a hair when released mid-rise
    },

    render(out) {
      const hillOn = amp.v > 0.001;
      if (!dirty && !hillOn && !hillWas) return; // nothing moved since last time
      if (dirty) {
        fillBase();
        dirty = false;
      }
      hillWas = hillOn;
      hh.set(base);
      if (hillOn) addHill(hh, w, h, hx.v, hy.v, TOPO.hill.levels * amp.v, TOPO.hill.sigma, TOPO.hill.reach, inv);

      const every = TOPO.every;
      const band = TOPO.band;
      const steep = TOPO.steep;
      const shallow = TOPO.shallow;
      out.fill(0);
      for (let y = 1; y < h - 1; y++) {
        let i = y * w + 1;
        for (let x = 1; x < w - 1; x++, i++) {
          const v = hh[i] + 1000; // biased positive, and 1000 is a multiple of every
          const k = (v + 0.5) | 0; // nearest level
          let d = v - k;
          if (d < 0) d = -d;
          let gx = (hh[i + 1] - hh[i - 1]) * 0.5;
          let gy = (hh[i + w] - hh[i - w]) * 0.5;
          const sgn = gx * gy; // > 0: the level climbs towards lower right, so the line runs /
          if (gx < 0) gx = -gx;
          if (gy < 0) gy = -gy;
          const m = gx > gy ? gx : gy;
          if (d > band * m) continue;
          let shape;
          if (gx >= gy) shape = gy < gx * steep ? 1 : sgn > 0 ? 2 : 3; // steep line: | / \
          else shape = gx < gy * shallow ? 0 : sgn > 0 ? 2 : 3; // shallow line: - / \
          out[i] = 1 + shape * 2 + (k % every === 0 ? 1 : 0);
        }
      }
    },

    /** Called every frame while a pointer is over the page; cx, cy are in cell units. */
    pointer(cx, cy, moved) {
      px = cx;
      py = cy;
      if (!want) {
        // a fresh arrival: a hill that is not up yet starts under the pointer instead of sliding in
        if (amp.v < 0.04) {
          hx.v = cx;
          hy.v = cy;
          hx.vel = hy.vel = 0;
        }
        want = true;
      }
    },

    pointerLeave() {
      want = false;
    },

    time() {
      return t;
    },

    /** Debug: the hill's current strength, 0..1. */
    hill() {
      return amp.v;
    },
  };
}

/* ------------------------------------------------------------------------ *
 * Preset: water
 *
 * Calm water: a still, blank surface. Nothing moves until something falls in
 * it, and then only a ring does: a soft crest that opens slowly from the spot
 * and fades as it goes. The pointer drops one now and then (rate limited, and
 * never closer than a few cells to the last one), and a rare drop falls on its
 * own. Rings are drawn, not simulated: each is one analytic crest, and
 * overlapping rings take the stronger of the two, so there is no interference,
 * no wake and no speckle, and the surface is blank most of the time.
 * ------------------------------------------------------------------------ */

const WATER = {
  fps: 30,
  cell: 1.25,
  max: 24, // rings alive at once; the oldest is reused
  open: 1.2, // a ring starts this many cell widths wide
  grow: 0.04, // crest width, in cell widths: grow * radius + base
  base: 0.95,
  steps: [0.08, 0.17, 0.3, 0.5], // crest strength needed for ramp steps . · : -; below the first the cell stays blank
  fade: 0.35, // seconds a ring takes to come in
  pointer: { gap: 0.12, jitter: 0.08, dist: 14, amp: 0.5, life: 3.4, speed: 4.6 }, // one ring per 120-200 ms of movement; speed in cell widths a second
  ambient: { gap: 6, jitter: 4, first: 1.5, amp: 0.62, ampJitter: 0.1, life: 7.5, lifeJitter: 1.5, speed: 4.2 }, // one drop every 6-10 s
};

// strength (in hundredths) -> ramp level. No logs or branches per cell.
const WATER_LUT = (() => {
  const lut = new Uint8Array(256);
  for (let k = 0; k < 256; k++) {
    const v = k / 100;
    let lv = 0;
    for (let s = 0; s < WATER.steps.length; s++) if (v >= WATER.steps[s]) lv = s + 1;
    lut[k] = lv;
  }
  return lut;
})();

export function createWater(seed) {
  const rnd = mulberry32(seed === undefined ? (Math.random() * 4294967296) >>> 0 : seed);
  const M = WATER.max;
  const rx = new Float32Array(M); // ring centre, cells
  const ry = new Float32Array(M);
  const born = new Float32Array(M);
  const life = new Float32Array(M); // 0: slot is free
  const amp = new Float32Array(M);
  const speed = new Float32Array(M);
  let w = 0;
  let h = 0;
  let buf = null; // crest strength per cell
  let inv = 2.08; // cell height / cell width
  let t = 0;
  let nextDrop = 0;
  let nextPtr = 0;
  let lastX = -1e3; // where the pointer last dropped something, cells
  let lastY = -1e3;
  let any = false; // something was drawn last time

  // a free slot, else the ring closest to the end of its life
  function drop(cx, cy, a, l, v, age) {
    let k = 0;
    let least = Infinity;
    for (let i = 0; i < M; i++) {
      const rest = life[i] === 0 ? -1 : life[i] - (t - born[i]);
      if (rest < least) {
        least = rest;
        k = i;
      }
      if (rest <= 0) break;
    }
    rx[k] = cx;
    ry[k] = cy;
    born[k] = t - (age || 0);
    life[k] = l;
    amp[k] = a;
    speed[k] = v;
  }

  function ambient() {
    const A = WATER.ambient;
    const mx = 6;
    const my = 6 / inv;
    const cx = mx + rnd() * Math.max(1, w - 2 * mx);
    const cy = my + rnd() * Math.max(1, h - 2 * my);
    drop(cx, cy, A.amp + rnd() * A.ampJitter, A.life + rnd() * A.lifeJitter, A.speed);
  }

  return {
    glyphs: WATER_GLYPHS,
    fps: WATER.fps,
    cell: WATER.cell,

    resize(cols, rows, cellW, cellH) {
      if (cols !== w || rows !== h || !buf) {
        w = cols;
        h = rows;
        buf = new Float32Array(w * h);
        life.fill(0);
        any = true;
      }
      inv = cellH / cellW;
    },

    /** A blank surface. `still` (reduced motion) leaves one faint ring, mid-way through its life. */
    settle(still) {
      life.fill(0);
      t = 0;
      any = true;
      lastX = lastY = -1e3;
      if (still) {
        const A = WATER.ambient;
        drop(0.68 * w, 0.42 * h, A.amp, A.life, A.speed, 3);
      }
      nextDrop = t + WATER.ambient.first + rnd() * 2;
    },

    step(dt) {
      t += dt;
      if (t >= nextDrop) {
        ambient();
        nextDrop = t + WATER.ambient.gap + rnd() * WATER.ambient.jitter;
      }
    },

    render(out) {
      buf.fill(0);
      let live = false;
      for (let n = 0; n < M; n++) {
        const l = life[n];
        if (l === 0) continue;
        const age = t - born[n];
        if (age >= l) continue;
        live = true;
        const u = 1 - age / l;
        let env = amp[n] * u * Math.sqrt(u);
        if (age < WATER.fade) {
          const f = age / WATER.fade;
          env *= f * f * (3 - 2 * f);
        }
        const r = WATER.open + speed[n] * age;
        const sig = WATER.base + WATER.grow * r;
        const sf = sig * 0.7; // a crisper leading edge...
        const sb = sig * 1.4; // ... and a softer back
        const outer = r + 3 * sf;
        const inner = r - 3 * sb;
        const o2 = outer * outer;
        const i2 = inner > 0 ? inner * inner : -1;
        const cx = rx[n];
        const cy = ry[n];
        const x0 = Math.max(0, Math.floor(cx - outer));
        const x1 = Math.min(w - 1, Math.ceil(cx + outer));
        const y0 = Math.max(0, Math.floor(cy - outer / inv));
        const y1 = Math.min(h - 1, Math.ceil(cy + outer / inv));
        for (let y = y0; y <= y1; y++) {
          const dy = (y + 0.5 - cy) * inv;
          const dy2 = dy * dy;
          let i = y * w + x0;
          for (let x = x0; x <= x1; x++, i++) {
            const dx = x + 0.5 - cx;
            const d2 = dx * dx + dy2;
            if (d2 > o2 || d2 < i2) continue;
            const e = Math.sqrt(d2) - r;
            const q = e > 0 ? e / sf : e / sb;
            const v = env * Math.exp(-q * q);
            if (v > buf[i]) buf[i] = v;
          }
        }
      }
      if (!live) {
        if (any) out.fill(0);
        any = false;
        return;
      }
      any = true;
      for (let i = 0, n = w * h; i < n; i++) {
        const k = (buf[i] * 100) | 0;
        out[i] = WATER_LUT[k > 255 ? 255 : k];
      }
    },

    /** Called every frame while a pointer is over the page; cx, cy are in cell units. */
    pointer(cx, cy, moved) {
      const P = WATER.pointer;
      if (!moved || t < nextPtr) return;
      const dx = cx - lastX;
      const dy = (cy - lastY) * inv;
      if (dx * dx + dy * dy < P.dist * P.dist) return; // not far enough from the last ring: a slow pointer stays sparse
      drop(cx, cy, P.amp, P.life, P.speed);
      lastX = cx;
      lastY = cy;
      nextPtr = t + P.gap + rnd() * P.jitter;
    },

    pointerLeave() {
      lastX = lastY = -1e3;
    },

    time() {
      return t;
    },
  };
}

const PRESETS = { topo: createTopo, water: createWater };

function presetName(value) {
  return Object.prototype.hasOwnProperty.call(PRESETS, value) ? value : DEFAULT_PRESET;
}

/* ------------------------------------------------------------------------ *
 * Mounting
 * ------------------------------------------------------------------------ */

const mounts = new WeakMap();

function luminance(color) {
  const m = /(\d+(?:\.\d+)?)[ ,]+(\d+(?:\.\d+)?)[ ,]+(\d+(?:\.\d+)?)/.exec(color);
  if (!m) return 0;
  return (0.2126 * +m[1] + 0.7152 * +m[2] + 0.0722 * +m[3]) / 255;
}

export function mountField(root) {
  const prior = mounts.get(root);
  if (prior) prior.destroy();

  const canvas = root.querySelector('canvas.field-canvas') || root.querySelector('canvas');
  const ctx = canvas && canvas.getContext('2d');
  if (!ctx) return { destroy() {}, stats: () => ({}) };

  const html = document.documentElement;
  const mqReduce = window.matchMedia('(prefers-reduced-motion: reduce)');
  const mqDark = window.matchMedia('(prefers-color-scheme: dark)');
  const measure = document.createElement('canvas').getContext('2d');
  const atlas = document.createElement('canvas');
  const actx = atlas.getContext('2d');
  const timers = new Set();

  let destroyed = false;
  let ready = false;
  let sized = false;
  let reduced = mqReduce.matches;
  let visible = true;
  let docVisible = document.visibilityState !== 'hidden';
  let raf = 0;
  let last = 0;
  let cost = 0; // moving average of the work per frame, ms
  let costRender = 0; // ... of which the preset's render
  let costDraw = 0; // ... and of which drawing
  let lit = 0; // share of cells showing a glyph, 0..1

  let name = presetName(html.dataset.field);
  let preset = PRESETS[name]();
  let frameMs = 1000 / preset.fps;

  // metrics
  let styleKey = '';
  let sig = '';
  let dpr = 1;
  let cwD = 0; // cell size in device pixels
  let chD = 0;
  let cellW = 0; // cell size in css pixels
  let cellH = 0;
  let offX = 0; // grid origin inside the canvas, device pixels
  let offY = 0;
  let cols = 0;
  let rows = 0;
  let idx = null; // glyph index per cell
  let shown = null; // what is currently on the canvas
  let forceFull = true;

  const ptr = { inside: false, moved: false, had: false, x: 0, y: 0 };

  /* ---- atlas ---- */

  function buildAtlas(family, size, weight, color) {
    const defs = preset.glyphs;
    const fpx = size * dpr;
    const font = weight + ' ' + fpx + 'px ' + family;
    measure.font = font;
    const m = measure.measureText('M');
    cwD = Math.max(3, Math.round(m.width));
    chD = Math.max(4, Math.round(fpx * (preset.cell || CELL_H)));
    cellW = cwD / dpr;
    cellH = chD / dpr;
    atlas.width = cwD * defs.length;
    atlas.height = chD;
    actx.font = font;
    actx.textAlign = 'left';
    actx.textBaseline = 'alphabetic';
    actx.fillStyle = color;
    const asc = m.fontBoundingBoxAscent;
    const desc = m.fontBoundingBoxDescent;
    const base =
      asc !== undefined && desc !== undefined
        ? Math.round((chD - (asc + desc)) / 2 + asc)
        : Math.round(chD * 0.5 + fpx * 0.32);
    // light-on-dark reads heavier than dark-on-light; compensate a little
    const scale = luminance(color) > 0.5 ? 0.88 : 1;
    const dx = (cwD - m.width) / 2;
    for (let i = 1; i < defs.length; i++) {
      actx.globalAlpha = defs[i][1] * scale;
      actx.fillText(defs[i][0], i * cwD + dx, base);
    }
    forceFull = true;
  }

  /* ---- layout ---- */

  function layout() {
    if (!ready || destroyed) return;
    const cw = root.clientWidth;
    const ch = root.clientHeight;
    const cs = getComputedStyle(root);
    const size = parseFloat(cs.fontSize) || 14;
    const ratio = Math.min(DPR_CAP, window.devicePixelRatio || 1);
    const key = [name, cs.fontFamily, size, cs.fontWeight, cs.color, ratio].join('|');
    const now = key + '|' + cw + 'x' + ch;
    if (now === sig && sized) return; // nothing changed (the observer and the window both report a resize)
    sig = now;
    if (key !== styleKey) {
      styleKey = key;
      dpr = ratio;
      buildAtlas(cs.fontFamily || 'monospace', size, cs.fontWeight || '400', cs.color);
    }
    if (cw < 1 || ch < 1) {
      sized = false;
      cols = 0;
      rows = 0;
      stopLoop();
      return;
    }
    const bw = Math.max(1, Math.round(cw * dpr));
    const bh = Math.max(1, Math.round(ch * dpr));
    if (canvas.width !== bw || canvas.height !== bh) {
      canvas.width = bw;
      canvas.height = bh;
      forceFull = true;
    }
    if (canvas.style.display !== 'block') canvas.style.display = 'block'; // no inline-baseline gap, no layout feedback
    const wpx = cw + 'px';
    const hpx = ch + 'px';
    if (canvas.style.width !== wpx) canvas.style.width = wpx;
    if (canvas.style.height !== hpx) canvas.style.height = hpx;

    const nc = Math.floor(bw / cwD);
    const nr = Math.floor(bh / chD);
    if (nc < 2 || nr < 2) {
      sized = false;
      cols = 0;
      rows = 0;
      stopLoop();
      return;
    }
    offX = Math.floor((bw - nc * cwD) / 2);
    offY = Math.floor((bh - nr * chD) / 2);
    const fresh = nc !== cols || nr !== rows || !idx;
    cols = nc;
    rows = nr;
    if (fresh) {
      idx = new Uint8Array(cols * rows);
      shown = new Uint8Array(cols * rows);
      forceFull = true;
    }
    preset.resize(cols, rows, cellW, cellH, offX / dpr, offY / dpr);
    if (fresh || reduced) preset.settle(reduced);
    sized = true;
    paint();
    updateRunning();
  }

  /* ---- pointer ---- */

  function onPointerMove(e) {
    ptr.x = e.clientX;
    ptr.y = e.clientY;
    ptr.inside = true;
    ptr.moved = true;
  }
  function onPointerUp(e) {
    if (e.pointerType !== 'mouse') onPointerGone();
  }
  function onPointerOut(e) {
    if (!e.relatedTarget) onPointerGone(); // left the window
  }
  function onPointerGone() {
    ptr.inside = false;
    ptr.moved = false;
  }

  // The root is fixed to the viewport, so clientX/Y are already root coordinates.
  function tickPointer() {
    if (!ptr.inside) {
      if (ptr.had) {
        ptr.had = false;
        preset.pointerLeave();
      }
      return;
    }
    let cx = (ptr.x - offX / dpr) / cellW;
    let cy = (ptr.y - offY / dpr) / cellH;
    cx = cx < 0 ? 0 : cx > cols ? cols : cx;
    cy = cy < 0 ? 0 : cy > rows ? rows : cy;
    preset.pointer(cx, cy, ptr.moved);
    ptr.moved = false;
    ptr.had = true;
  }

  /* ---- drawing ---- */

  function paint() {
    if (!sized) return;
    const t0 = performance.now();
    preset.render(idx);
    const t1 = performance.now();
    draw();
    costRender = costRender * 0.92 + (t1 - t0) * 0.08;
    costDraw = costDraw * 0.92 + (performance.now() - t1) * 0.08;
  }

  function draw() {
    const n = cols * rows;
    let changed = 0;
    let on = 0;
    for (let i = 0; i < n; i++) {
      const k = idx[i];
      if (k !== shown[i]) changed++;
      if (k !== 0) on++;
    }
    lit = on / n;
    if (!forceFull && changed === 0) return;
    ctx.imageSmoothingEnabled = false;
    if (forceFull || changed * 3 > n) {
      ctx.clearRect(0, 0, canvas.width, canvas.height);
      let i = 0;
      for (let r = 0; r < rows; r++) {
        const y = offY + r * chD;
        for (let c = 0; c < cols; c++, i++) {
          const k = idx[i];
          if (k !== 0) ctx.drawImage(atlas, k * cwD, 0, cwD, chD, offX + c * cwD, y, cwD, chD);
        }
      }
      shown.set(idx);
      forceFull = false;
      return;
    }
    let i = 0;
    for (let r = 0; r < rows; r++) {
      const y = offY + r * chD;
      for (let c = 0; c < cols; c++, i++) {
        const k = idx[i];
        if (k === shown[i]) continue;
        shown[i] = k;
        const x = offX + c * cwD;
        ctx.clearRect(x, y, cwD, chD);
        if (k !== 0) ctx.drawImage(atlas, k * cwD, 0, cwD, chD, x, y, cwD, chD);
      }
    }
  }

  /* ---- loop ---- */

  function frame(now) {
    raf = requestAnimationFrame(frame);
    if (now - last < frameMs - 1.5) return;
    last += frameMs;
    if (now - last > frameMs) last = now;
    const t0 = performance.now();
    tickPointer();
    preset.step(frameMs / 1000);
    paint();
    cost = cost * 0.92 + (performance.now() - t0) * 0.08;
  }

  function updateRunning() {
    const should = ready && sized && visible && docVisible && !reduced && !destroyed;
    if (should && !raf) {
      last = performance.now();
      raf = requestAnimationFrame(frame);
    } else if (!should && raf) {
      stopLoop();
    }
  }
  function stopLoop() {
    if (raf) cancelAnimationFrame(raf);
    raf = 0;
  }

  /* ---- reactions ---- */

  function later(fn, ms) {
    const id = setTimeout(() => {
      timers.delete(id);
      if (!destroyed) fn();
    }, ms);
    timers.add(id);
  }

  function refreshTheme() {
    layout();
    // pick up the colour again if a CSS transition was still settling
    later(layout, 350);
  }

  function setPreset(next) {
    if (next === name) return;
    name = next;
    preset = PRESETS[name]();
    frameMs = 1000 / preset.fps;
    styleKey = '';
    sig = '';
    cols = 0; // forces the new preset to size and settle itself
    ptr.had = false;
    layout();
  }

  function onMutation(records) {
    let theme = false;
    let field = false;
    for (let k = 0; k < records.length; k++) {
      const a = records[k].attributeName;
      if (a === 'data-theme') theme = true;
      else if (a === 'data-field') field = true;
    }
    if (field) setPreset(presetName(html.dataset.field));
    if (theme) refreshTheme();
  }

  function onMotionChange() {
    reduced = mqReduce.matches;
    onPointerGone();
    attachPointer(!reduced);
    if (reduced) {
      stopLoop();
      if (sized) {
        preset.settle(true);
        forceFull = true;
        paint();
      }
    } else {
      updateRunning();
    }
  }

  function onVisibility() {
    docVisible = document.visibilityState !== 'hidden';
    updateRunning();
  }

  function onFontsDone() {
    styleKey = '';
    sig = '';
    layout();
  }

  let pointerOn = false;
  function attachPointer(on) {
    if (on === pointerOn) return;
    pointerOn = on;
    const m = on ? 'addEventListener' : 'removeEventListener';
    const opts = { passive: true };
    window[m]('pointermove', onPointerMove, opts);
    window[m]('pointerdown', onPointerMove, opts);
    window[m]('pointerup', onPointerUp, opts);
    window[m]('pointercancel', onPointerUp, opts);
    window[m]('blur', onPointerGone, opts);
    document[m]('pointerout', onPointerOut, opts);
    html[m]('pointerleave', onPointerGone, opts);
  }

  /* ---- wire up ---- */

  const ro = typeof ResizeObserver === 'function' ? new ResizeObserver(layout) : null;
  if (ro) ro.observe(root);
  // a fixed root is always intersecting; this only matters if a page hides or clips it
  const io =
    typeof IntersectionObserver === 'function'
      ? new IntersectionObserver((entries) => {
          visible = entries[entries.length - 1].isIntersecting;
          updateRunning();
        })
      : null;
  if (io) io.observe(root);
  const mo = new MutationObserver(onMutation);
  mo.observe(html, { attributes: true, attributeFilter: ['data-theme', 'data-field'] });

  const listen = (mq, fn) => (mq.addEventListener ? mq.addEventListener('change', fn) : mq.addListener(fn));
  const unlisten = (mq, fn) => (mq.removeEventListener ? mq.removeEventListener('change', fn) : mq.removeListener(fn));
  listen(mqReduce, onMotionChange);
  listen(mqDark, refreshTheme);
  document.addEventListener('visibilitychange', onVisibility);
  window.addEventListener('resize', layout);
  if (document.fonts && document.fonts.addEventListener) document.fonts.addEventListener('loadingdone', onFontsDone);
  attachPointer(!reduced);

  (async function start() {
    try {
      if (document.fonts && document.fonts.load) {
        const cs = getComputedStyle(root);
        const wait = new Promise((r) => later(r, 2500));
        await Promise.race([
          Promise.all([document.fonts.load(cs.fontWeight + ' ' + cs.fontSize + ' ' + cs.fontFamily, 'M.-|/\\'), document.fonts.ready]),
          wait,
        ]);
      }
    } catch (err) {
      /* fall through with whatever font we have */
    }
    if (destroyed) return;
    ready = true;
    layout();
  })();

  const api = {
    destroy() {
      if (destroyed) return;
      destroyed = true;
      stopLoop();
      attachPointer(false);
      if (ro) ro.disconnect();
      if (io) io.disconnect();
      mo.disconnect();
      unlisten(mqReduce, onMotionChange);
      unlisten(mqDark, refreshTheme);
      document.removeEventListener('visibilitychange', onVisibility);
      window.removeEventListener('resize', layout);
      if (document.fonts && document.fonts.removeEventListener) document.fonts.removeEventListener('loadingdone', onFontsDone);
      timers.forEach(clearTimeout);
      timers.clear();
      if (mounts.get(root) === api) mounts.delete(root);
    },
    /** Debug info for the playground. */
    stats() {
      return { preset: name, cols, rows, cellW, cellH, dpr, fps: preset.fps, ms: cost, renderMs: costRender, drawMs: costDraw, lit, running: !!raf, reduced };
    },
  };
  mounts.set(root, api);
  return api;
}

/* ------------------------------------------------------------------------ *
 * Auto-mount
 * ------------------------------------------------------------------------ */

function autoMount() {
  document.querySelectorAll('[data-field-root]').forEach((el) => {
    if (!mounts.has(el)) mountField(el);
  });
}

if (typeof document !== 'undefined' && typeof window !== 'undefined') {
  if (document.readyState === 'loading') document.addEventListener('DOMContentLoaded', autoMount, { once: true });
  else autoMount();
}
