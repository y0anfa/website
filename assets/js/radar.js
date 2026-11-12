/* The scope (SPEC section 7, The scope). Home only, unannounced.
 *
 * Hold the name's mark for a second and a half: the page dims and a radar scope
 * opens over it. Contacts come in from the rim toward the centre. The beam shows
 * each one only as it passes, where it was then, and the echo fades; a press
 * sends a pulse that takes out what is really there now. A contact that reaches
 * the centre costs one of the three rings. No rings left, or Escape: the scope
 * folds back into the mark.
 *
 * Everything is drawn on one canvas, in the page's own ink. No inline styles (the
 * CSP is strict): the canvas is placed by site.css, and the page is dimmed by a
 * class on the root (radar-on).
 */
(function () {
  'use strict';

  var root = document.documentElement;
  var name = document.querySelector('.identity');
  var stage = document.querySelector('.stage');
  if (!name || !stage || !window.requestAnimationFrame) return;

  var reduceMotion = window.matchMedia('(prefers-reduced-motion: reduce)');

  var HIT = 12; // px around the centre of the mark, as in site.js
  var TOUCH = 24; // the same for a finger: as far as the name's first letter
  var DRIFT = 40; // px a finger may wander during the hold; a mouse stays within HIT
  var HOLD = 1500; // ms the mark is held before the scope opens
  var SHOWN = 250; // ms before the hold shows at all: a plain press shows nothing
  var OPEN = 520; // ms the scope takes to open, and to fold
  var RELOAD = 320; // ms between two pulses
  var TAU = Math.PI * 2;
  var BEST = 'radar'; // localStorage: the best score

  var canvas = null;
  var ctx = null;
  var ink = {};
  var font = '';
  var W = 0;
  var H = 0;
  var raf = 0;
  var last = 0;

  var mode = 'idle'; // idle, hold, open, play, over, fold
  var since = 0; // when the mode began
  var from = null; // the mark, where the scope opens from and folds to
  var finger = false; // the hold is a finger's
  var game = null;

  // ---- the mark ----------------------------------------------------------------

  // The centre of the name's mark, in viewport coordinates. The mark is a
  // pseudo-element: its place is read from its row and the stylesheet.
  function mark() {
    var box = name.getBoundingClientRect();
    var before = window.getComputedStyle(name, '::before');
    var axis = parseFloat(window.getComputedStyle(stage).getPropertyValue('--axis')) || 0;
    var lean = parseFloat(name.style.getPropertyValue('--lean')) || 0;
    return {
      x: Math.round(box.left + axis) + 0.5 + lean,
      y: box.top + (parseFloat(before.top) || 0) + (parseFloat(before.height) || 0) / 2
    };
  }

  function near(event, point, reach) {
    var dx = event.clientX - point.x;
    var dy = event.clientY - point.y;
    return dx * dx + dy * dy <= reach * reach;
  }

  // ---- the canvas --------------------------------------------------------------

  function size() {
    var ratio = window.devicePixelRatio || 1;
    W = window.innerWidth;
    H = window.innerHeight;
    canvas.width = Math.round(W * ratio);
    canvas.height = Math.round(H * ratio);
    ctx.setTransform(ratio, 0, 0, ratio, 0, 0);
  }

  // The page's colours, resolved for the theme in use. A custom property reads
  // back as written (light-dark(...)), which a canvas cannot paint with, so each
  // one is put on the canvas's own colour and read from there.
  function colours() {
    ['text', 'text-2', 'text-3', 'hair'].forEach(function (key) {
      canvas.style.setProperty('color', 'var(--' + key + ')');
      ink[key] = window.getComputedStyle(canvas).color;
    });
    canvas.style.removeProperty('color');
    font = window.getComputedStyle(document.body).fontFamily || 'sans-serif';
  }

  function mount() {
    if (canvas) return true;
    canvas = document.createElement('canvas');
    ctx = canvas.getContext && canvas.getContext('2d');
    if (!ctx) {
      canvas = null;
      return false;
    }
    canvas.className = 'radar';
    canvas.setAttribute('aria-hidden', 'true');
    document.body.appendChild(canvas);
    // The canvas takes the pointer only once the scope is open (site.css): until
    // then a move off the mark still reaches the page, and ends the hold.
    canvas.addEventListener('pointerdown', press);
    canvas.addEventListener('pointermove', function (event) {
      event.stopPropagation(); // the line under the scope stays still
    });
    size();
    colours();
    return true;
  }

  function unmount() {
    if (raf) window.cancelAnimationFrame(raf);
    raf = 0;
    last = 0;
    if (canvas && canvas.parentNode) canvas.parentNode.removeChild(canvas);
    canvas = null;
    ctx = null;
    game = null;
    mode = 'idle';
    root.classList.remove('radar-on');
    quiet(false);
  }

  // While the scope is open the page under it is out of reach, for the keyboard too.
  function quiet(on) {
    [stage, document.querySelector('.corner')].forEach(function (el) {
      if (el) el.inert = on;
    });
  }

  function set(next, now) {
    mode = next;
    since = now;
  }

  // ---- the game ----------------------------------------------------------------

  // Where the scope sits, its radius, and how far a pulse reaches (a tenth of it).
  function centre() {
    var r = Math.max(80, Math.min(W, H) / 2 - 36);
    return { x: W / 2, y: H / 2, r: r, pulse: Math.min(44, Math.max(26, r / 10)) };
  }

  function best() {
    try {
      return parseInt(window.localStorage.getItem(BEST), 10) || 0;
    } catch (e) {
      return 0;
    }
  }

  function start(now) {
    game = {
      t: 0, // ms played
      beam: -Math.PI / 2, // the beam's angle; it starts at twelve o'clock
      contacts: [],
      pulses: [],
      next: 900, // ms until the next contact
      loaded: 0, // when the next pulse may leave
      rings: 3,
      score: 0,
      best: best(),
      record: false,
      hurt: 0 // when a ring was last lost
    };
    root.classList.add('radar-on');
    quiet(true);
    set('open', now);
  }

  // How hard it is, 0 to 1, by what has been taken out.
  function heat() {
    return Math.min(1, game.score / 40);
  }

  function spawn() {
    var h = heat();
    game.contacts.push({
      a: Math.random() * TAU,
      d: 1, // distance from the centre, in radii
      v: 0.07 + 0.09 * h + Math.random() * 0.03, // radii a second
      turn: (Math.random() - 0.5) * 0.25 * h, // radians a second: later ones curve
      seen: null // the echo: where the beam last showed it, and when
    });
    game.next = 2300 - 1500 * h + Math.random() * 400;
  }

  function place(contact, c) {
    return { x: c.x + Math.cos(contact.a) * contact.d * c.r, y: c.y + Math.sin(contact.a) * contact.d * c.r };
  }

  // Did the beam, turning from angle a to angle b, pass over angle at?
  function swept(a, b, at) {
    var span = (((at - a) % TAU) + TAU) % TAU;
    return span <= b - a;
  }

  function step(dt, now) {
    var c = centre();
    var period = 2600 - 900 * heat(); // ms a turn
    var before = game.beam;
    game.t += dt;
    game.beam += (dt / period) * TAU;

    game.next -= dt;
    if (game.next <= 0) spawn();

    for (var i = game.contacts.length - 1; i >= 0; i--) {
      var contact = game.contacts[i];
      contact.d -= (contact.v * dt) / 1000;
      contact.a += (contact.turn * dt) / 1000;
      if (swept(before, game.beam, contact.a)) {
        var p = place(contact, c);
        contact.seen = { x: p.x, y: p.y, at: now };
      }
      if (contact.d <= 0.04) {
        game.contacts.splice(i, 1);
        game.rings--;
        game.hurt = now;
        if (game.rings <= 0) return end(now);
      }
    }

    for (var j = game.pulses.length - 1; j >= 0; j--) {
      if (now - game.pulses[j].at > 420) game.pulses.splice(j, 1);
    }
  }

  function press(event) {
    event.stopPropagation(); // not a press on the page under the scope
    if (mode !== 'play' || event.button !== 0 || event.isPrimary === false) return;
    var now = event.timeStamp;
    if (now < game.loaded) return;
    game.loaded = now + RELOAD;

    var c = centre();
    var at = { x: event.clientX, y: event.clientY };
    var hit = false;
    for (var i = game.contacts.length - 1; i >= 0; i--) {
      if (!near(event, place(game.contacts[i], c), c.pulse)) continue;
      game.contacts.splice(i, 1);
      game.score++;
      hit = true;
    }
    game.pulses.push({ x: at.x, y: at.y, at: now, hit: hit });
  }

  function end(now) {
    if (game.score > game.best) {
      game.record = true;
      try {
        window.localStorage.setItem(BEST, String(game.score));
      } catch (e) {}
    }
    set('over', now);
  }

  // ---- drawing -----------------------------------------------------------------

  function ring(x, y, r, colour, alpha, width) {
    if (r <= 0 || alpha <= 0) return;
    ctx.globalAlpha = alpha;
    ctx.strokeStyle = colour;
    ctx.lineWidth = width || 1;
    ctx.beginPath();
    ctx.arc(x, y, r, 0, TAU);
    ctx.stroke();
  }

  function dot(x, y, r, colour, alpha) {
    if (alpha <= 0) return;
    ctx.globalAlpha = alpha;
    ctx.fillStyle = colour;
    ctx.beginPath();
    ctx.arc(x, y, r, 0, TAU);
    ctx.fill();
  }

  function ease(k) {
    k = Math.min(1, Math.max(0, k));
    return 1 - Math.pow(1 - k, 3);
  }

  function drawHold(now) {
    var k = (now - since - SHOWN) / (HOLD - SHOWN);
    if (k <= 0) return;
    var r = finger ? 28 + 12 * ease(k) : 6 + 12 * ease(k); // a finger hides a small ring
    ring(from.x, from.y, r, ink['text-2'], 0.9, 1);
    // the arc fills as the hold goes on
    ctx.globalAlpha = 1;
    ctx.strokeStyle = ink.text;
    ctx.lineWidth = 1.5;
    ctx.beginPath();
    ctx.arc(from.x, from.y, r, -Math.PI / 2, -Math.PI / 2 + TAU * Math.min(1, k));
    ctx.stroke();
  }

  // The scope: k is how open it is, 0 at the mark and 1 in place.
  function drawScope(now, k) {
    var c = centre();
    var e = ease(k);
    var x = from.x + (c.x - from.x) * e;
    var y = from.y + (c.y - from.y) * e;
    var r = 18 + (c.r - 18) * e;

    // the rings are what is left to lose, from the rim inward
    for (var n = 1; n <= 3; n++) {
      var left = n > 3 - game.rings;
      var flash = !left && n === 3 - game.rings && now - game.hurt < 420 && Math.floor((now - game.hurt) / 70) % 2 === 0;
      ring(x, y, (r * n) / 3, left || flash ? ink['text-3'] : ink.hair, left || flash ? 0.9 : 0.5, 1);
    }
    dot(x, y, 3.5, ink.text, 1);
    if (k < 1) return;

    // the beam and its wake
    for (var w = 0; w < 28; w++) {
      ctx.globalAlpha = 0.12 * (1 - w / 28);
      ctx.fillStyle = ink['text-3'];
      ctx.beginPath();
      ctx.moveTo(x, y);
      ctx.arc(x, y, r, game.beam - ((w + 1) * 0.6) / 28, game.beam - (w * 0.6) / 28);
      ctx.fill();
    }
    ctx.globalAlpha = 0.9;
    ctx.strokeStyle = ink['text-2'];
    ctx.lineWidth = 1;
    ctx.beginPath();
    ctx.moveTo(x, y);
    ctx.lineTo(x + Math.cos(game.beam) * r, y + Math.sin(game.beam) * r);
    ctx.stroke();

    // echoes: where each contact was when the beam passed, fading
    for (var i = 0; i < game.contacts.length; i++) {
      var contact = game.contacts[i];
      if (mode === 'over') {
        var p = place(contact, c);
        ring(p.x, p.y, 4, ink.text, 0.9, 1); // the end shows where they really were
      } else if (contact.seen) {
        dot(contact.seen.x, contact.seen.y, 3, ink.text, 1 - (now - contact.seen.at) / 2200);
      }
    }

    for (var j = 0; j < game.pulses.length; j++) {
      var pulse = game.pulses[j];
      var age = (now - pulse.at) / 420;
      ring(pulse.x, pulse.y, c.pulse * ease(age * 1.6), pulse.hit ? ink.text : ink['text-3'], 1 - age, pulse.hit ? 1.5 : 1);
      if (pulse.hit) dot(pulse.x, pulse.y, 3 * (1 - age), ink.text, 1 - age);
    }

    // the count, under the scope; the best beside it, quieter
    ctx.font = '500 13px ' + font;
    ctx.textBaseline = 'middle';
    var count = String(game.score);
    var record = game.best ? String(Math.max(game.best, game.score)) : '';
    var width = ctx.measureText(count).width + (record ? 14 + ctx.measureText(record).width : 0);
    var left = x - width / 2;
    var base = Math.min(H - 16, y + r + 20);
    // a new best flickers as the scope closes
    var blink = mode === 'over' && game.record && Math.floor((now - since) / 90) % 2 === 1;
    ctx.textAlign = 'left';
    ctx.globalAlpha = blink ? 0.3 : 1;
    ctx.fillStyle = ink.text;
    ctx.fillText(count, left, base);
    if (record) {
      ctx.globalAlpha = 1;
      ctx.fillStyle = ink['text-3'];
      ctx.fillText(record, left + ctx.measureText(count).width + 14, base);
    }
  }

  function frame(now) {
    raf = 0;
    if (!canvas) return;
    var dt = last ? Math.min(50, now - last) : 16;
    last = now;

    if (mode === 'hold' && now - since >= HOLD) start(now);
    if (mode === 'open' && now - since >= OPEN) set('play', now);
    if (mode === 'play') step(dt, now);
    if (mode === 'over' && now - since >= 1700) set('fold', now);
    if (mode === 'fold' && now - since >= OPEN) return unmount();

    ctx.clearRect(0, 0, W, H);
    if (mode === 'hold') drawHold(now);
    else if (mode === 'open') drawScope(now, (now - since) / OPEN);
    else if (mode === 'fold') drawScope(now, 1 - (now - since) / OPEN);
    else if (game) drawScope(now, 1);
    ctx.globalAlpha = 1;

    raf = window.requestAnimationFrame(frame);
  }

  // ---- the hold, and the ways out ------------------------------------------------

  document.addEventListener('pointerdown', function (event) {
    if (mode !== 'idle' || reduceMotion.matches) return;
    if (event.button !== 0 || event.isPrimary === false) return;
    var at = mark();
    var touch = event.pointerType === 'touch';
    if (!near(event, at, touch ? TOUCH : HIT) || !mount()) return;
    from = at;
    finger = touch;
    set('hold', event.timeStamp);
    last = 0;
    raf = window.requestAnimationFrame(frame);
  });

  function letGo() {
    if (mode === 'hold') unmount();
  }

  document.addEventListener('pointerup', letGo);
  document.addEventListener('pointercancel', letGo);
  document.addEventListener('pointermove', function (event) {
    if (mode === 'hold' && !near(event, from, finger ? DRIFT : HIT)) unmount();
  });

  // A finger held on the mark would otherwise start a scroll at its first tremor
  // (the browser then cancels the pointer), or bring up the selection handles.
  // touchstart comes after pointerdown, so the hold has begun by then.
  document.addEventListener(
    'touchstart',
    function (event) {
      if (mode === 'hold' && event.cancelable) event.preventDefault();
    },
    { passive: false }
  );

  // a long press on a touch screen would open the system's menu, or select the name
  document.addEventListener('contextmenu', function (event) {
    if (mode !== 'idle') event.preventDefault();
  });
  document.addEventListener('selectstart', function (event) {
    if (mode !== 'idle') event.preventDefault();
  });

  document.addEventListener('keydown', function (event) {
    if (event.key !== 'Escape' || mode === 'idle') return;
    event.preventDefault();
    if (mode === 'play' || mode === 'over') set('fold', event.timeStamp);
    else if (mode !== 'fold') unmount();
  });

  window.addEventListener('resize', function () {
    if (canvas) size();
  });

  // leaving the page, or coming back to it from the cache, never finds a scope open
  window.addEventListener('pagehide', unmount);
})();
