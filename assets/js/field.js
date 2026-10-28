/*
 * field.js: the ASCII field. The only motion on the site.
 *
 * Two presets, chosen by <html data-field="water|wind">:
 *   water  a calm surface: damped height-field ripples over a slow swell.
 *   wind   grass in wind: a drifting noise flow field with gusts.
 *
 * Contract (SPEC section 7 and 9): export mountField(root) -> { destroy() },
 * and auto-mount every [data-field-root]. No dependencies, no markup
 * injection, no dynamic code, no inline styles (sizing goes through CSSOM).
 *
 * CSS it expects: .field { position: relative; font-size: 14px; line-height: 1;
 * color: var(--fg) } and .field-canvas { position: absolute; inset: 0 }.
 *
 * Optional extra (extends the SPEC, harmless if unused):
 *  - mountField(root).stats() returns debug numbers for lab/field.html.
 */

const FPS = 30;
const FRAME_MS = 1000 / FPS;
const STEP_DT = 1 / FPS;
const DPR_CAP = 2;
const CELL_H = 1.25; // cell height as a multiple of the font size
const PTR_RADIUS = 8; // wind deflection radius, in cell widths

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

/** Improved Perlin noise in 3D, roughly in [-1, 1] (typically within +-0.7). */
export function createNoise3(seed) {
  const rnd = mulberry32(seed);
  const p = new Uint8Array(512);
  for (let i = 0; i < 256; i++) p[i] = i;
  for (let i = 255; i > 0; i--) {
    const j = (rnd() * (i + 1)) | 0;
    const t = p[i];
    p[i] = p[j];
    p[j] = t;
  }
  for (let i = 0; i < 256; i++) p[i + 256] = p[i];

  function grad(h, x, y, z) {
    h &= 15;
    const u = h < 8 ? x : y;
    const v = h < 4 ? y : h === 12 || h === 14 ? x : z;
    return ((h & 1) === 0 ? u : -u) + ((h & 2) === 0 ? v : -v);
  }

  return function noise3(x, y, z) {
    const fx = Math.floor(x);
    const fy = Math.floor(y);
    const fz = Math.floor(z);
    x -= fx;
    y -= fy;
    z -= fz;
    const X = fx & 255;
    const Y = fy & 255;
    const Z = fz & 255;
    const u = x * x * x * (x * (x * 6 - 15) + 10);
    const v = y * y * y * (y * (y * 6 - 15) + 10);
    const w = z * z * z * (z * (z * 6 - 15) + 10);
    const A = p[X] + Y;
    const AA = p[A] + Z;
    const AB = p[A + 1] + Z;
    const B = p[X + 1] + Y;
    const BA = p[B] + Z;
    const BB = p[B + 1] + Z;
    const g000 = grad(p[AA], x, y, z);
    const g100 = grad(p[BA], x - 1, y, z);
    const g010 = grad(p[AB], x, y - 1, z);
    const g110 = grad(p[BB], x - 1, y - 1, z);
    const g001 = grad(p[AA + 1], x, y, z - 1);
    const g101 = grad(p[BA + 1], x - 1, y, z - 1);
    const g011 = grad(p[AB + 1], x, y - 1, z - 1);
    const g111 = grad(p[BB + 1], x - 1, y - 1, z - 1);
    const x00 = g000 + u * (g100 - g000);
    const x10 = g010 + u * (g110 - g010);
    const x01 = g001 + u * (g101 - g001);
    const x11 = g011 + u * (g111 - g011);
    const y0 = x00 + v * (x10 - x00);
    const y1 = x01 + v * (x11 - x01);
    return y0 + w * (y1 - y0);
  };
}

/**
 * One step of the damped 2D wave equation on a two-buffer height field.
 * `prev` is overwritten with the new state; the caller then swaps the two
 * buffers. kx and ky are the squared Courant numbers along x and y (they
 * differ because cells are taller than wide); stable while kx + ky <= 1.
 * Border cells are never written, so they stay at rest.
 */
export function rippleStep(prev, cur, w, h, kx, ky, damp, sponge) {
  const c0 = 2 - 2 * kx - 2 * ky;
  if (sponge) {
    // per-cell damping: stronger near the edges so ripples fade out instead of bouncing back
    for (let y = 1; y < h - 1; y++) {
      let i = y * w + 1;
      for (let x = 1; x < w - 1; x++, i++) {
        prev[i] = (c0 * cur[i] + kx * (cur[i - 1] + cur[i + 1]) + ky * (cur[i - w] + cur[i + w]) - prev[i]) * sponge[i];
      }
    }
    return;
  }
  for (let y = 1; y < h - 1; y++) {
    let i = y * w + 1;
    for (let x = 1; x < w - 1; x++, i++) {
      prev[i] = (c0 * cur[i] + kx * (cur[i - 1] + cur[i + 1]) + ky * (cur[i - w] + cur[i + w]) - prev[i]) * damp;
    }
  }
}

/** Per-cell damping for rippleStep: `damp` inside, falling to damp * (1 - edge) at the border, over `band` cells. */
export function makeSponge(w, h, damp, edge, band, invAspect) {
  const sp = new Float32Array(w * h);
  const bandY = band / invAspect;
  for (let y = 0; y < h; y++) {
    for (let x = 0; x < w; x++) {
      const dx = Math.min(x, w - 1 - x) / band;
      const dy = Math.min(y, h - 1 - y) / bandY;
      const d = Math.min(1, dx, dy);
      sp[y * w + x] = damp * (1 - edge * (1 - d) * (1 - d));
    }
  }
  return sp;
}

/**
 * Add a raised-cosine bump to a height buffer. Centre (cx, cy) is in
 * fractional cell units, radius is in cell widths, invAspect is the cell
 * height divided by the cell width (so the bump is round on screen).
 */
export function addDrop(buf, w, h, cx, cy, amp, radius, invAspect) {
  const ry = radius / invAspect;
  const x0 = Math.max(1, Math.floor(cx - radius));
  const x1 = Math.min(w - 2, Math.ceil(cx + radius));
  const y0 = Math.max(1, Math.floor(cy - ry));
  const y1 = Math.min(h - 2, Math.ceil(cy + ry));
  for (let y = y0; y <= y1; y++) {
    const dy = (y + 0.5 - cy) * invAspect;
    for (let x = x0; x <= x1; x++) {
      const dx = x + 0.5 - cx;
      const d = Math.sqrt(dx * dx + dy * dy);
      if (d < radius) buf[y * w + x] += amp * 0.5 * (1 + Math.cos((Math.PI * d) / radius));
    }
  }
}

/* ------------------------------------------------------------------------ *
 * Glyph tables. Entry 0 is always blank. Alpha is baked into the atlas so a
 * cell is a single drawImage; the field stays quieter than body text.
 * ------------------------------------------------------------------------ */

const WATER_GLYPHS = [
  ['', 0],
  ['.', 0.34],
  ['·', 0.38],
  [':', 0.42],
  ['-', 0.46],
  ['=', 0.5],
  ['+', 0.55],
  ['*', 0.6],
];

const WIND_GLYPHS = (() => {
  const g = [
    ['', 0],
    ['.', 0.3],
    [',', 0.34],
    ["'", 0.38],
  ];
  // index = 4 + shape * 3 + tier; shapes: - ~ / | \ (tall strokes read heavier, so they get less alpha)
  const light = [0.38, 0.46, 0.55];
  const tall = [0.32, 0.4, 0.48];
  for (const ch of ['-', '~']) for (const a of light) g.push([ch, a]);
  for (const ch of ['/', '|', '\\']) for (const a of tall) g.push([ch, a]);
  return g;
})();

/* ------------------------------------------------------------------------ *
 * Preset: water
 * ------------------------------------------------------------------------ */

const WATER = {
  kx: 0.17, // squared Courant number along x (wave speed ~0.41 cells/step)
  damp: 0.988, // per-step damping, gentle: a ring lasts around 5 s
  crest: 3.4, // height -> brightness gain for crests
  trough: 1.8, // ... and for troughs (dimmer, so rings read as light and dark)
  dither: 0.4, // static per-cell wobble of the thresholds, breaks up banding
  swellAmp: 0.9,
  swellThresh: 0.28,
  threshold: 0.12, // brightness below this stays blank
  ratio: 1.85, // each ramp step needs this much more brightness than the last
  spacing: 3.2, // pointer drop spacing, in cell widths
  edge: 0.2, // extra damping at the border (a soft sponge), so ripples fade out there
  band: 7, // ... over this many cell widths
};

// brightness (in hundredths) -> ramp level. No logs or branches per cell.
const WATER_LUT = (() => {
  const lut = new Uint8Array(256);
  for (let k = 0; k < 256; k++) {
    const v = k / 100;
    lut[k] = v < WATER.threshold ? 0 : Math.min(7, 1 + Math.floor(Math.log(v / WATER.threshold) / Math.log(WATER.ratio)));
  }
  return lut;
})();

export function createWater(seed) {
  const noise = createNoise3(1337);
  const rnd = mulberry32(seed === undefined ? (Math.random() * 4294967296) >>> 0 : seed);
  let w = 0;
  let h = 0;
  let u0 = null; // previous state, overwritten by each step
  let u1 = null; // current state
  let jit = null;
  let sponge = null;
  let sx = 0.084; // noise units per cell, x
  let sy = 0.175; // ... y
  let inv = 2.08; // cell height / cell width
  let kx = WATER.kx;
  let ky = WATER.kx / (inv * inv);
  let t = 0;
  let nextDrop = 0;
  let carry = 0;
  let nextPtr = 0;

  // A drop goes into the current buffer only, so it carries momentum (an
  // impulse): the ring it throws is much stronger than a plain displacement.
  function drop(cx, cy, amp, radius) {
    addDrop(u1, w, h, cx, cy, amp, radius, inv);
  }

  function ambient() {
    const r = 3.6 + rnd() * 2.2;
    const mx = r + 2;
    const my = (r + 2) / inv;
    const cx = mx + rnd() * Math.max(1, w - 2 * mx);
    const cy = my + rnd() * Math.max(1, h - 2 * my);
    drop(cx, cy, 0.28 + rnd() * 0.2, r);
  }

  return {
    glyphs: WATER_GLYPHS,

    resize(cols, rows, cellW, cellH) {
      if (cols !== w || rows !== h || !u0) {
        w = cols;
        h = rows;
        u0 = new Float32Array(w * h);
        u1 = new Float32Array(w * h);
        jit = new Float32Array(w * h);
        const r = mulberry32(99);
        for (let i = 0; i < jit.length; i++) jit[i] = (r() - 0.5) * WATER.dither;
      }
      sx = cellW / 100;
      sy = cellH / 100;
      const nextInv = cellH / cellW;
      if (!sponge || sponge.length !== w * h || Math.abs(nextInv - inv) > 1e-6) {
        inv = nextInv;
        sponge = makeSponge(w, h, WATER.damp, WATER.edge, WATER.band, inv);
      }
      ky = WATER.kx / (inv * inv);
      kx = WATER.kx;
    },

    /** Reset to a pleasing, already-moving state (also the static frame). */
    settle() {
      u0.fill(0);
      u1.fill(0);
      t = 0;
      const plan = [
        [0, 0.3, 0.46, 0.4, 4.8],
        [22, 0.7, 0.6, 0.32, 4.2],
        [40, 0.52, 0.2, 0.28, 3.6],
      ];
      for (let s = 0; s < 74; s++) {
        for (let k = 0; k < plan.length; k++) {
          if (plan[k][0] === s) drop(plan[k][1] * w, plan[k][2] * h, plan[k][3], plan[k][4]);
        }
        rippleStep(u0, u1, w, h, kx, ky, WATER.damp, sponge);
        const tmp = u0;
        u0 = u1;
        u1 = tmp;
      }
      t = 11.7;
      nextDrop = t + 1.2 + rnd() * 1.5;
    },

    step(dt) {
      t += dt;
      if (t >= nextDrop) {
        ambient();
        nextDrop = t + 2 + rnd() * 2;
      }
      rippleStep(u0, u1, w, h, kx, ky, WATER.damp, sponge);
      const tmp = u0;
      u0 = u1;
      u1 = tmp;
    },

    render(out) {
      const crest = WATER.crest;
      const trough = WATER.trough;
      const sa = WATER.swellAmp;
      const st = WATER.swellThresh;
      const tz = t * 0.055;
      let i = 0;
      for (let y = 0; y < h; y++) {
        const ny = y * sy * 0.55;
        for (let x = 0; x < w; x++, i++) {
          const hv = u1[i];
          let v = hv > 0 ? hv * crest : -hv * trough;
          // very slow, low-amplitude swell so the surface is never fully still
          const s = noise(x * sx * 0.5 - t * 0.04, ny, tz);
          if (s > st) v += (s - st) * sa;
          let k = (v * (1 + jit[i]) * 100) | 0;
          if (k > 255) k = 255;
          out[i] = WATER_LUT[k];
        }
      }
    },

    pointer(cx, cy, px, py, had) {
      if (!had) return;
      const dx = cx - px;
      const dy = (cy - py) * inv;
      const dist = Math.sqrt(dx * dx + dy * dy);
      if (dist < 0.01) return;
      let s = WATER.spacing - carry;
      let n = 0;
      while (s <= dist && n < 3) {
        if (t >= nextPtr) {
          const f = s / dist;
          drop(px + dx * f, py + (cy - py) * f, 0.11, 2.8);
          nextPtr = t + 0.06;
        }
        s += WATER.spacing;
        n++;
      }
      carry = n === 0 ? Math.min(WATER.spacing, carry + dist) : dist - (s - WATER.spacing);
      if (carry < 0) carry = 0;
    },

    /** A tap or click: one soft drop (touch screens rarely send moves). */
    tap(cx, cy) {
      drop(cx, cy, 0.3, 3.4);
    },

    time() {
      return t;
    },
  };
}

/* ------------------------------------------------------------------------ *
 * Preset: wind
 * ------------------------------------------------------------------------ */

const WIND = {
  base: 0.1, // resting energy (the sparse dots of calm grass)
  gust: 0.62, // added by a gust
  reach: 2.2, // how much of the field a gust covers (higher = more)
  detail: 0.3, // fine structure inside gusts
  flutter: 0.045, // per-cell shimmer
  jitter: 0.12, // static per-cell wobble of the thresholds (stippled gust edges)
  speed: 0.55, // gust drift, noise units per second (rightwards)
  tCalm1: 0.15,
  tCalm2: 0.25,
  tCalm3: 0.34,
  tDir: 0.44, // above this a cell draws a directional glyph
  tWave: 0.62, // above this a horizontal glyph becomes ~
  ripple: 0.16, // size of the wave that rides through gusts
  decay: 0.955, // pointer wake, per frame
  push: 1.15, // pointer wake peak strength
};

export function createWind() {
  const noise = createNoise3(4242);
  let w = 0;
  let h = 0;
  let wx = null; // pointer wake (flow offset), physical units
  let wy = null;
  let jit = null;
  let ph = null;
  let ce = null; // coarse lattice: resting energy
  let cth = null; // coarse lattice: flow angle
  let cw2 = 0;
  let ch2 = 0;
  let sx = 0.084;
  let sy = 0.175;
  let inv = 2.08;
  let t = 0;
  let wake = 0; // 0 when the wake is fully faded; skips all wake work

  function stamp(cx, cy) {
    const R = PTR_RADIUS;
    const x0 = Math.max(0, Math.floor(cx - R));
    const x1 = Math.min(w - 1, Math.ceil(cx + R));
    const y0 = Math.max(0, Math.floor(cy - R / inv));
    const y1 = Math.min(h - 1, Math.ceil(cy + R / inv));
    for (let y = y0; y <= y1; y++) {
      const dy = (y + 0.5 - cy) * inv;
      for (let x = x0; x <= x1; x++) {
        const dx = x + 0.5 - cx;
        const d2 = dx * dx + dy * dy;
        if (d2 >= R * R) continue;
        const d = Math.sqrt(d2) || 0.001;
        let f = 1 - d / R;
        f = f * f * (3 - 2 * f);
        const i = y * w + x;
        const k = f * 0.5;
        wx[i] += ((dx / d) * WIND.push * f - wx[i]) * k;
        wy[i] += ((dy / d) * WIND.push * f - wy[i]) * k;
      }
    }
    wake = 1;
  }

  return {
    glyphs: WIND_GLYPHS,

    resize(cols, rows, cellW, cellH) {
      if (cols !== w || rows !== h || !wx) {
        w = cols;
        h = rows;
        wx = new Float32Array(w * h);
        wy = new Float32Array(w * h);
        jit = new Float32Array(w * h);
        ph = new Float32Array(w * h);
        // the noise fields are smooth, so they are sampled on a lattice of every
        // second cell and interpolated: a quarter of the noise evaluations
        cw2 = ((w - 1) >> 1) + 2;
        ch2 = ((h - 1) >> 1) + 2;
        ce = new Float32Array(cw2 * ch2);
        cth = new Float32Array(cw2 * ch2);
        const r = mulberry32(77);
        for (let i = 0; i < jit.length; i++) {
          jit[i] = r() - 0.5;
          ph[i] = r();
        }
        wake = 0;
      }
      sx = cellW / 100;
      sy = cellH / 100;
      inv = cellH / cellW;
    },

    settle() {
      wx.fill(0);
      wy.fill(0);
      wake = 0;
      t = 6.4;
    },

    step(dt) {
      t += dt;
      if (wake > 0) {
        wake *= WIND.decay;
        if (wake < 0.004) {
          wx.fill(0);
          wy.fill(0);
          wake = 0;
        } else {
          const d = WIND.decay;
          for (let i = 0; i < wx.length; i++) {
            wx[i] *= d;
            wy[i] *= d;
          }
        }
      }
    },

    render(out) {
      const tt = t;
      const useWake = wake > 0;
      const drift = tt * WIND.speed;

      // 1. noise on the coarse lattice
      let c = 0;
      for (let j = 0; j < ch2; j++) {
        const ny = j * 2 * sy;
        for (let i = 0; i < cw2; i++, c++) {
          const adv = i * 2 * sx - drift;
          // slow, mostly horizontal flow direction, with a little faster swirl on top
          const th = noise(adv * 0.3, ny * 0.45, tt * 0.06) * 0.85 + noise(adv * 1.0 + 3.3, ny * 1.2, tt * 0.3 + 7) * 0.55;
          cth[c] = th < -1.4 ? -1.4 : th > 1.4 ? 1.4 : th;
          // drifting gust envelope, with finer streaks inside it
          let g = noise(adv * 0.3 + 31.7, ny * 0.65, tt * 0.045 + 5.1) * WIND.reach;
          g = g < 0 ? 0 : g > 1 ? 1 : g;
          g = g * g * (3 - 2 * g);
          const dn = noise((adv - drift * 0.5) * 1.3 + 9.3, ny * 1.5, tt * 0.22 + 2.2);
          ce[c] = WIND.base + g * (WIND.gust + WIND.detail * dn);
        }
      }

      // 2. per cell: interpolate, add flutter and the pointer wake, pick a glyph
      let k = 0;
      for (let y = 0; y < h; y++) {
        const row0 = (y >> 1) * cw2;
        const row1 = row0 + cw2;
        const fy = (y & 1) * 0.5;
        for (let x = 0; x < w; x++, k++) {
          const a = row0 + (x >> 1);
          const b = row1 + (x >> 1);
          const fx = (x & 1) * 0.5;
          const e0 = (ce[a] * (1 - fx) + ce[a + 1] * fx) * (1 - fy) + (ce[b] * (1 - fx) + ce[b + 1] * fx) * fy;
          const th = (cth[a] * (1 - fx) + cth[a + 1] * fx) * (1 - fy) + (cth[b] * (1 - fx) + cth[b + 1] * fx) * fy;
          // flutter: a cheap triangle wave with a per-cell phase
          let f = ph[k] + tt * 0.21;
          f -= Math.floor(f);
          const e = e0 + WIND.flutter * (f < 0.5 ? f * 4 - 1 : 3 - f * 4);
          // cos and sin by polynomial: th is within +-1.4, error stays under 0.01
          const t2 = th * th;
          let vx = e * (1 - t2 * (0.5 - t2 * (1 / 24 - t2 / 720)));
          let vy = e * th * (1 - t2 * (1 / 6 - t2 * (1 / 120 - t2 / 5040)));
          if (useWake) {
            vx += wx[k];
            vy += wy[k];
          }
          const es = Math.sqrt(vx * vx + vy * vy) + jit[k] * WIND.jitter;
          if (es < WIND.tCalm1) {
            out[k] = 0;
          } else if (es < WIND.tDir) {
            out[k] = es < WIND.tCalm2 ? 1 : es < WIND.tCalm3 ? 2 : 3;
          } else {
            // a faint wave rides through the gust, drifting with the wind
            let wv = x * 0.23 - tt * 0.9 + ph[k] * 0.4;
            wv -= Math.floor(wv);
            const ew = es + WIND.ripple * (wv < 0.5 ? wv * 4 - 1 : 3 - wv * 4);
            const ax = vx < 0 ? -vx : vx;
            const ay = vy < 0 ? -vy : vy;
            let shape;
            if (ay < ax * 0.4142) shape = ew >= WIND.tWave ? 1 : 0; // ~ or -
            else if (ay > ax * 2.4142) shape = 3; // |
            else shape = vx * vy > 0 ? 4 : 2; // \ or /
            const tier = ew < WIND.tDir + 0.2 ? 0 : ew < WIND.tDir + 0.42 ? 1 : 2;
            out[k] = 4 + shape * 3 + tier;
          }
        }
      }
    },

    pointer(cx, cy, px, py, had) {
      if (!had) {
        stamp(cx, cy);
        return;
      }
      const dx = cx - px;
      const dy = (cy - py) * inv;
      const dist = Math.sqrt(dx * dx + dy * dy);
      const n = Math.min(12, Math.ceil(dist / 2));
      for (let k = 1; k <= n; k++) stamp(px + ((cx - px) * k) / n, py + ((cy - py) * k) / n);
    },

    tap(cx, cy) {
      stamp(cx, cy);
    },

    time() {
      return t;
    },
  };
}

function makePreset(name) {
  return name === 'wind' ? createWind() : createWater();
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
  let costDraw = 0; // ... of which drawing

  let presetName = html.dataset.field === 'wind' ? 'wind' : 'water';
  let preset = makePreset(presetName);

  // metrics
  let styleKey = '';
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

  const ptr = { active: false, dirty: false, tap: false, has: false, x: 0, y: 0, cx: 0, cy: 0 };

  /* ---- atlas ---- */

  function buildAtlas(family, size, weight, color) {
    const defs = preset.glyphs;
    const fpx = size * dpr;
    const font = weight + ' ' + fpx + 'px ' + family;
    measure.font = font;
    const m = measure.measureText('M');
    cwD = Math.max(3, Math.round(m.width));
    chD = Math.max(4, Math.round(fpx * CELL_H));
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
    const key = [presetName, cs.fontFamily, size, cs.fontWeight, cs.color, ratio].join('|');
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
    preset.resize(cols, rows, cellW, cellH);
    if (fresh) preset.settle();
    sized = true;
    paint();
    updateRunning();
  }

  /* ---- pointer ---- */

  function gridOrigin(rr) {
    return {
      x: rr.left + root.clientLeft + offX / dpr,
      y: rr.top + root.clientTop + offY / dpr,
    };
  }

  function onPointerMove(e) {
    ptr.x = e.clientX;
    ptr.y = e.clientY;
    ptr.active = true;
    ptr.dirty = true;
  }
  function onPointerDown(e) {
    onPointerMove(e);
    ptr.tap = true;
  }
  function onPointerUp(e) {
    if (e.pointerType !== 'mouse') {
      ptr.active = false;
      ptr.has = false;
    }
  }
  function onPointerGone() {
    ptr.active = false;
    ptr.has = false;
  }

  function tickPointer() {
    if (!ptr.dirty) return;
    const tap = ptr.tap;
    ptr.dirty = false;
    ptr.tap = false;
    if (!ptr.active) return;
    const rr = root.getBoundingClientRect();
    if (ptr.x < rr.left || ptr.x >= rr.right || ptr.y < rr.top || ptr.y >= rr.bottom) {
      ptr.has = false;
      return;
    }
    const o = gridOrigin(rr);
    const cx = (ptr.x - o.x) / cellW;
    const cy = (ptr.y - o.y) / cellH;
    if (cx < 0 || cy < 0 || cx >= cols || cy >= rows) {
      ptr.has = false;
      return;
    }
    if (tap) preset.tap(cx, cy);
    else preset.pointer(cx, cy, ptr.has ? ptr.cx : cx, ptr.has ? ptr.cy : cy, ptr.has);
    ptr.cx = cx;
    ptr.cy = cy;
    ptr.has = true;
  }

  /* ---- drawing ---- */

  function paint() {
    if (!sized) return;
    preset.render(idx);
    const t0 = performance.now();
    draw();
    costDraw = costDraw * 0.92 + (performance.now() - t0) * 0.08;
  }

  function draw() {
    const n = cols * rows;
    let changed = 0;
    if (!forceFull) {
      for (let i = 0; i < n; i++) if (idx[i] !== shown[i]) changed++;
      if (changed === 0) return;
    }
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

  /** One settled frame for prefers-reduced-motion. */
  function paintStatic() {
    if (!sized) return;
    preset.settle();
    forceFull = true;
    paint();
  }

  /* ---- loop ---- */

  function frame(now) {
    raf = requestAnimationFrame(frame);
    if (now - last < FRAME_MS - 1.5) return;
    last += FRAME_MS;
    if (now - last > FRAME_MS) last = now;
    const t0 = performance.now();
    tickPointer();
    preset.step(STEP_DT);
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

  function setPreset(name) {
    if (name === presetName) return;
    presetName = name;
    preset = makePreset(name);
    styleKey = '';
    cols = 0; // forces the new preset to size and settle itself
    ptr.has = false;
    layout();
    if (reduced) paintStatic();
  }

  function onMutation(records) {
    let theme = false;
    let field = false;
    for (let k = 0; k < records.length; k++) {
      const a = records[k].attributeName;
      if (a === 'data-theme') theme = true;
      else if (a === 'data-field') field = true;
    }
    if (field) setPreset(html.dataset.field === 'wind' ? 'wind' : 'water');
    if (theme) refreshTheme();
  }

  function onResize() {
    layout();
    if (reduced) paintStatic();
  }

  function onMotionChange() {
    reduced = mqReduce.matches;
    ptr.active = false;
    ptr.has = false;
    attachPointer(!reduced);
    if (reduced) {
      stopLoop();
      paintStatic();
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
    layout();
    if (reduced) paintStatic();
  }

  let pointerOn = false;
  function attachPointer(on) {
    if (on === pointerOn) return;
    pointerOn = on;
    const m = on ? 'addEventListener' : 'removeEventListener';
    const opts = { passive: true };
    window[m]('pointermove', onPointerMove, opts);
    window[m]('pointerdown', onPointerDown, opts);
    window[m]('pointerup', onPointerUp, opts);
    window[m]('pointercancel', onPointerUp, opts);
    window[m]('blur', onPointerGone, opts);
    html[m]('pointerleave', onPointerGone, opts);
  }

  /* ---- wire up ---- */

  const ro = typeof ResizeObserver === 'function' ? new ResizeObserver(onResize) : null;
  if (ro) ro.observe(root);
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
  window.addEventListener('resize', onResize);
  if (document.fonts && document.fonts.addEventListener) document.fonts.addEventListener('loadingdone', onFontsDone);
  attachPointer(!reduced);

  (async function start() {
    try {
      if (document.fonts && document.fonts.load) {
        const cs = getComputedStyle(root);
        const wait = new Promise((r) => later(r, 2500));
        await Promise.race([
          Promise.all([document.fonts.load(cs.fontWeight + ' ' + cs.fontSize + ' ' + cs.fontFamily, 'M.-~'), document.fonts.ready]),
          wait,
        ]);
      }
    } catch (err) {
      /* fall through with whatever font we have */
    }
    if (destroyed) return;
    ready = true;
    layout();
    if (reduced) paintStatic();
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
      window.removeEventListener('resize', onResize);
      if (document.fonts && document.fonts.removeEventListener) document.fonts.removeEventListener('loadingdone', onFontsDone);
      timers.forEach(clearTimeout);
      timers.clear();
      if (mounts.get(root) === api) mounts.delete(root);
    },
    /** Debug info for the playground. */
    stats() {
      return { preset: presetName, cols, rows, cellW, cellH, dpr, ms: cost, drawMs: costDraw, running: !!raf, reduced };
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
