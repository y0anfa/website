/* yoanfaure.com: the one script (SPEC section 7).
 *
 * Loaded on every page with defer + blocking="render": it runs before the first
 * frame, so the page-swap listeners are in place and the home's entrance starts
 * from its first state. The saved theme is applied earlier still, by the inline
 * head.js.
 *
 * 1. Theme: the toggle switches the theme with a short cross-fade. Choosing what
 *    the system already prefers forgets the choice.
 * 2. The title transition. Cross-document view transitions, typed "forward" (the
 *    home to an entry) or "back" (an entry to the home), plus "leaving" and
 *    "arriving". One element per page carries the name "entry-title": the clicked
 *    title on the axis, the h1 on the entry.
 * 3. The home: the light, a warm glow that follows the pointer (or holds a height
 *    while a touch screen scrolls) and rides the timeline, lighting the entry it
 *    reaches and raking across the name; the name's decrypt, once a visit; the
 *    date tints. The light is two custom properties written once a frame at most;
 *    CSS does the motion.
 * 4. An entry page: a click in the side margins, or Escape, goes back to the home.
 *
 * No inline handlers and no inline style attributes (the CSP is strict): positions
 * and names are written through the CSSOM.
 */
(function () {
  'use strict';

  var root = document.documentElement;
  var reduceMotion = window.matchMedia('(prefers-reduced-motion: reduce)');
  var prefersLight = window.matchMedia('(prefers-color-scheme: light)');

  root.classList.add('js');

  // ---- 1. theme ---------------------------------------------------------------

  var THEME_KEY = 'theme'; // the key head.js reads before the first paint

  function writeTheme(value) {
    try {
      if (value) localStorage.setItem(THEME_KEY, value);
      else localStorage.removeItem(THEME_KEY);
    } catch (e) {}
  }

  function systemTheme() {
    return prefersLight.matches ? 'light' : 'dark';
  }

  function currentTheme() {
    var forced = root.getAttribute('data-theme');
    return forced === 'light' || forced === 'dark' ? forced : systemTheme();
  }

  var toggle = document.querySelector('.theme-toggle');
  var wanted = null; // the theme a view transition is about to apply

  function labelToggle() {
    if (!toggle) return;
    var label = 'Switch to ' + ((wanted || currentTheme()) === 'dark' ? 'light' : 'dark') + ' theme';
    toggle.setAttribute('aria-label', label);
    toggle.setAttribute('title', label);
  }

  function setTheme(next) {
    if (next === systemTheme()) {
      root.removeAttribute('data-theme');
      writeTheme(null);
    } else {
      root.setAttribute('data-theme', next);
      writeTheme(next);
    }
  }

  labelToggle();
  if (prefersLight.addEventListener) prefersLight.addEventListener('change', labelToggle);

  if (toggle) {
    toggle.addEventListener('click', function () {
      var next = (wanted || currentTheme()) === 'dark' ? 'light' : 'dark';
      var applied = false;
      wanted = next;
      labelToggle();

      var apply = function () {
        if (applied) return;
        applied = true;
        if (wanted === next) wanted = null;
        setTheme(next);
        labelToggle();
      };

      // One soft cross-fade of the whole page (type "theme", see site.css). Without
      // view transitions, or with reduced motion, the theme just switches.
      if (typeof document.startViewTransition !== 'function' || reduceMotion.matches) {
        apply();
        return;
      }
      var vt = null;
      try {
        vt = document.startViewTransition({ update: apply, types: ['theme'] });
      } catch (e) {
        // an engine that only knows the callback form throws on the options object
        try {
          vt = document.startViewTransition(apply);
        } catch (e2) {
          apply();
        }
      }
      quiet(vt);
    });
  }

  // ---- 2. the title transition -----------------------------------------------

  var NAME = 'entry-title';
  var named = null; // the one element that carries the name right now

  function pathOf(url) {
    try {
      return new URL(url, location.href).pathname.replace(/\/+$/, '') || '/';
    } catch (e) {
      return null;
    }
  }

  // 'home', 'entry' (one slug, no dot: /<slug>/) or null for anything else.
  function kind(url) {
    try {
      var u = new URL(url, location.href);
      if (u.origin !== location.origin) return null;
      if (u.pathname === '/') return 'home';
      return /^\/[^\/.]+\/?$/.test(u.pathname) ? 'entry' : null;
    } catch (e) {
      return null;
    }
  }

  function thisPage() {
    var key = document.body && document.body.getAttribute('data-page');
    if (key === 'home') return 'home';
    return key === 'essay' || key === 'note' || key === 'project' ? 'entry' : null;
  }

  function direction(from, to) {
    if (from === 'home' && to === 'entry') return 'forward';
    if (from === 'entry' && to === 'home') return 'back';
    return null;
  }

  function clear() {
    if (!named) return;
    try {
      named.style.removeProperty('view-transition-name');
    } catch (e) {}
    named = null;
  }

  // At most one element per page carries the name: a duplicate makes the browser
  // skip the whole transition.
  function claim(el) {
    clear();
    if (!el) return false;
    el.style.setProperty('view-transition-name', NAME);
    named = el;
    return true;
  }

  // Fully on screen: a title half cut off would fly in from nowhere.
  function inView(el) {
    var r = el.getBoundingClientRect();
    return r.height > 0 && r.top >= 0 && r.bottom <= window.innerHeight;
  }

  // The title of the timeline entry that links to this URL.
  function rowTitle(url) {
    var path = pathOf(url);
    var links = document.querySelectorAll('a.entry');
    for (var i = 0; i < links.length; i++) {
      if (pathOf(links[i].href) === path) return links[i].querySelector('.entry-title');
    }
    return null;
  }

  function heading() {
    return document.querySelector('.article h1');
  }

  // A skipped transition (a hidden tab, say) is not an error: handle every
  // promise first, so a skip never surfaces as an uncaught rejection.
  function quiet(vt) {
    if (!vt) return;
    var ignore = function () {};
    if (vt.ready) vt.ready.catch(ignore);
    if (vt.finished) vt.finished.catch(ignore);
    if (vt.updateCallbackDone) vt.updateCallbackDone.catch(ignore);
  }

  function mark(vt, type, side) {
    if (vt.types && typeof vt.types.add === 'function') {
      vt.types.add(type);
      vt.types.add(side);
    }
    vt.finished.then(clear, clear); // clear on any outcome
  }

  window.addEventListener('pageswap', function (event) {
    quiet(event.viewTransition);
    clear(); // a page restored from the cache may still carry a name
    try {
      var vt = event.viewTransition;
      var next = event.activation && event.activation.entry;
      if (!vt || !next) return;

      var type = direction(thisPage(), kind(next.url));
      if (!type) return;
      mark(vt, type, 'leaving');

      var el = type === 'forward' ? rowTitle(next.url) : heading();
      if (el && inView(el)) claim(el);
    } catch (e) {}
  });

  window.addEventListener('pagereveal', function (event) {
    var vt = event.viewTransition;
    quiet(vt);
    clear();

    // The entrance plays on a fresh load of the home only.
    var intro = !vt && thisPage() === 'home' && !reduceMotion.matches;
    if (intro) {
      root.classList.add('intro');
      decrypt();
    }
    if (light) light.start(intro);

    try {
      var activation = window.navigation && window.navigation.activation;
      var prev = activation && activation.from;
      if (!vt || !prev) return;

      var type = direction(kind(prev.url), thisPage());
      if (!type) return;
      mark(vt, type, 'arriving');

      if (type === 'forward') {
        var h1 = heading();
        if (h1 && inView(h1)) claim(h1);
      } else {
        var row = rowTitle(prev.url);
        if (row) {
          // Bring the row on screen, the least it takes, so the title has somewhere
          // to land (the old picture covers the jump).
          if (!location.hash) row.scrollIntoView({ block: 'nearest', inline: 'nearest', behavior: 'instant' });
          if (inView(row)) claim(row);
          if (light) light.hold(row.closest('.entry-row'));
        }
      }
    } catch (e) {}
  });

  // A page restored from the back/forward cache comes back as it was frozen.
  window.addEventListener('pageshow', function (event) {
    if (event.persisted) clear();
  });

  // ---- 3. the home: the light, the decrypt, the date tints -------------------

  var light = thisPage() === 'home' ? makeLight() : null;
  if (thisPage() === 'home') tintDates();
  if (light && !('onpagereveal' in window)) light.start(false);

  // On each entry: --age, 0 for the newest and 1 for the oldest, from the dates
  // (the stylesheet tints the date with it, and has a fallback by position); --i,
  // its place in the entrance.
  function tintDates() {
    var times = document.querySelectorAll('.entry-row > .entry-date[datetime]');
    var stamps = [];
    for (var i = 0; i < times.length; i++) stamps.push(Date.parse(times[i].getAttribute('datetime')));
    var valid = stamps.filter(function (s) {
      return !isNaN(s);
    });
    var newest = Math.max.apply(null, valid);
    var oldest = Math.min.apply(null, valid);
    var span = newest - oldest || 1;
    for (var j = 0; j < times.length; j++) {
      var row = times[j].parentNode;
      row.style.setProperty('--i', String(j + 1));
      if (isNaN(stamps[j])) continue;
      row.style.setProperty('--age', ((newest - stamps[j]) / span).toFixed(3));
    }
  }

  // The name decrypts: once a visit, on a fresh load, never under reduced motion.
  // The real name stays in the h1 (read by assistive tech, holding the layout); an
  // aria-hidden overlay puts one slot over each letter, at the letter's measured
  // place and width, cycles glyphs in it and locks the letters left to right.
  var DECRYPT_KEY = 'decrypted';

  function decrypt() {
    var wrap = document.querySelector('.name-wrap');
    var name = wrap && wrap.querySelector('.name');
    if (!name || reduceMotion.matches || !document.createRange) return;
    try {
      if (sessionStorage.getItem(DECRYPT_KEY)) return;
      sessionStorage.setItem(DECRYPT_KEY, '1');
    } catch (e) {
      return;
    }
    wrap.classList.add('no-rise', 'is-decrypting');
    var begun = false;
    var go = function () {
      if (begun) return;
      begun = true;
      scramble(wrap, name);
    };
    // measure with the real font, but never wait long for it
    if (document.fonts && document.fonts.ready) document.fonts.ready.then(go, go);
    window.setTimeout(go, 400);
  }

  function scramble(wrap, name) {
    var GLYPHS = 'ABCDEFGHJKLMNPQRSTUVWXYZabcdefghkmnpqrstuvwxyz0123456789#%&*+=<>/';
    var pick = function () {
      return GLYPHS.charAt(Math.floor(Math.random() * GLYPHS.length));
    };
    var box = wrap.getBoundingClientRect();
    var overlay = document.createElement('div');
    overlay.className = 'name name-scramble';
    overlay.setAttribute('aria-hidden', 'true');
    var range = document.createRange();
    var slots = [];
    var lines = name.querySelectorAll('.name-line > span');
    for (var l = 0; l < lines.length; l++) {
      var node = lines[l].firstChild;
      if (!node || node.nodeType !== 3) continue;
      for (var i = 0; i < node.length; i++) {
        range.setStart(node, i);
        range.setEnd(node, i + 1);
        var r = range.getBoundingClientRect();
        var el = document.createElement('span');
        el.className = 'scramble-slot';
        el.style.setProperty('left', (r.left - box.left).toFixed(2) + 'px');
        el.style.setProperty('top', (r.top - box.top).toFixed(2) + 'px');
        el.style.setProperty('width', r.width.toFixed(2) + 'px');
        el.style.setProperty('height', r.height.toFixed(2) + 'px');
        el.style.setProperty('line-height', r.height.toFixed(2) + 'px');
        el.textContent = pick();
        overlay.appendChild(el);
        slots.push({ el: el, ch: node.data.charAt(i), at: 140 + slots.length * 52, next: 60, done: false });
      }
    }
    wrap.appendChild(overlay);

    var t0 = 0;
    var tick = function (now) {
      if (!t0) t0 = now;
      var t = now - t0;
      var left = 0;
      for (var s = 0; s < slots.length; s++) {
        var slot = slots[s];
        if (slot.done) continue;
        if (t >= slot.at) {
          // the real letter, set where the real letter sits
          slot.el.textContent = slot.ch;
          slot.el.classList.add('is-locked');
          slot.done = true;
          continue;
        }
        left++;
        if (t >= slot.next) {
          slot.el.textContent = pick();
          slot.next = t + 55;
        }
      }
      if (left) {
        window.requestAnimationFrame(tick);
        return;
      }
      wrap.classList.remove('is-decrypting');
      overlay.remove();
    };
    window.requestAnimationFrame(tick);
  }

  function makeLight() {
    var bead = document.querySelector('.bead');
    var readout = bead && bead.querySelector('.bead-date');
    var tls = document.querySelectorAll('.tl');
    var tl = tls[0];
    var last = tls[tls.length - 1];
    var wrap = document.querySelector('.name-wrap');
    if (!bead || !readout || !tl || !wrap) return null;

    var MONTHS = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    var finePointer = window.matchMedia('(hover: hover) and (pointer: fine)');

    // Measured on start, resize and font load only, in document coordinates.
    var rows = []; // one per entry, top to bottom
    var ax = 0; // the axis, in viewport x
    var tlBox = null; // the timeline: left and right in viewport x, top and bottom in document y
    var wrapTop = 0; // the top of the name
    var restTop = null; // where the light rests with a mouse: the newest entry
    var restHeld = false; // or the entry the back transition landed on

    var sy = window.scrollY;
    var px = null; // the pointer, null while it is off the page
    var py = null;
    var queued = 0;
    var on = false;
    var lastWy = null;

    var litRow = null;
    var scrubbed = null;
    var shown = '';

    function measure() {
      sy = window.scrollY;
      var box = tl.getBoundingClientRect();
      var end = last.getBoundingClientRect();
      tlBox = { left: box.left, right: box.right, top: box.top + sy, bottom: end.bottom + sy };
      var axis = parseFloat(window.getComputedStyle(tl).getPropertyValue('--axis')) || 96;
      ax = Math.round(box.left + axis);
      root.style.setProperty('--ax', ax + 'px');

      var byRow = {};
      var items = document.querySelectorAll('.timeline [data-row]');
      for (var i = 0; i < items.length; i++) {
        var el = items[i];
        var n = Number(el.getAttribute('data-row'));
        var r = el.getBoundingClientRect();
        byRow[n] = {
          n: n,
          top: r.top + sy,
          bottom: r.bottom + sy,
          month: el.getAttribute('data-month'),
          from: el.getAttribute('data-month-from'), // a folded stretch of empty months

          entry: el.classList.contains('entry-row') ? el : null,
          label: el.classList.contains('month') ? el : null
        };
      }
      rows = Object.keys(byRow)
        .map(function (k) {
          return byRow[k];
        })
        .sort(function (a, b) {
          return a.n - b.n;
        });
      for (var j = 0; j < rows.length - 1; j++) rows[j].bottom = rows[j + 1].top;
      if (restTop === null || !restHeld) {
        restTop = null;
        for (var k = 0; k < rows.length; k++) {
          if (rows[k].entry) {
            restTop = rows[k].top + 15;
            break;
          }
        }
      }
      wrapTop = wrap.getBoundingClientRect().top + sy;
    }

    // Where the light rests, in viewport y: with a mouse, on the newest entry (or the
    // one the back transition landed on); on a touch screen, a fixed height the page
    // scrolls past.
    function restY() {
      if (finePointer.matches && restTop !== null) return restTop - sy;
      return Math.round(window.innerHeight * 0.42);
    }

    // The light's height: the pointer's while it is on the page, else where it rests.
    function lightY() {
      return py !== null ? py : restY();
    }

    // Is the pointer on the timeline itself? Only then does the scan line show and the
    // light pick the entry; elsewhere the glow follows the pointer and the entries rest.
    function onTimeline() {
      if (px === null || py === null || !tlBox) return false;
      var docY = py + sy;
      return px >= tlBox.left && px <= tlBox.right && docY >= tlBox.top && docY <= tlBox.bottom;
    }

    function rowAt(docY) {
      for (var i = 0; i < rows.length; i++) {
        if (docY >= rows[i].top && docY < rows[i].bottom) return rows[i];
      }
      return null;
    }

    // An empty month reads from its last day at the top to its first at the bottom;
    // a folded stretch from the last day of its newest month to the first of its oldest.
    function dateIn(row, docY) {
      var to = row.month.split('-');
      var from = (row.from || row.month).split('-');
      var top = new Date(Number(to[0]), Number(to[1]), 0).getTime(); // last day of the newest
      var bottom = new Date(Number(from[0]), Number(from[1]) - 1, 1).getTime(); // first of the oldest
      var f = Math.min(1, Math.max(0, (docY - row.top) / Math.max(1, row.bottom - row.top)));
      var d = new Date(top - f * (top - bottom));
      return d.getDate() + ' ' + MONTHS[d.getMonth()];
    }

    // Classes change only when the row under the light changes.
    function track(docY) {
      var row = rowAt(docY);
      var entry = row ? row.entry : null;
      var label = row ? row.label : null;
      if (entry !== litRow) {
        if (litRow) litRow.classList.remove('is-lit');
        if (entry) entry.classList.add('is-lit');
        litRow = entry;
      }
      if (label !== scrubbed) {
        if (scrubbed) scrubbed.classList.remove('is-scrubbed');
        if (label) label.classList.add('is-scrubbed');
        scrubbed = label;
      }
      bead.classList.toggle('is-off', !row);
      bead.classList.toggle('is-locked', !!entry);
      if (label) {
        var text = dateIn(row, docY);
        if (text !== shown) readout.textContent = shown = text;
      }
    }

    // Once a frame at most: two custom properties (the top of the name too, when
    // a scroll has moved it), then the row under the light. No layout read here.
    function apply() {
      queued = 0;
      var y = lightY();
      root.style.setProperty('--mx', (px === null ? ax : px) + 'px');
      root.style.setProperty('--my', y + 'px');
      var wy = wrapTop - sy;
      if (wy !== lastWy) {
        root.style.setProperty('--wy', wy + 'px');
        lastWy = wy;
      }
      var inside = onTimeline();
      root.classList.toggle('on-timeline', inside);
      track((inside ? y : restY()) + sy);
    }

    function schedule() {
      if (on && !queued) queued = window.requestAnimationFrame(apply);
    }

    function refresh() {
      if (!on) return;
      measure();
      schedule();
    }

    document.addEventListener(
      'pointermove',
      function (event) {
        if (event.pointerType !== 'mouse' || !finePointer.matches) return;
        px = event.clientX;
        py = event.clientY;
        schedule();
      },
      { passive: true }
    );

    document.addEventListener('mouseout', function (event) {
      if (event.relatedTarget) return; // still on the page
      px = null;
      py = null;
      schedule();
    });

    window.addEventListener(
      'scroll',
      function () {
        sy = window.scrollY;
        schedule();
      },
      { passive: true }
    );

    window.addEventListener('resize', refresh);
    if (window.ResizeObserver) {
      var observer = new ResizeObserver(refresh);
      for (var t = 0; t < tls.length; t++) observer.observe(tls[t]);
    }
    if (document.fonts && document.fonts.ready) document.fonts.ready.then(refresh);

    return {
      // Turn the light on: after the entrance on a fresh load, at once otherwise.
      // Under reduced motion it stays off; hover and focus still brighten.
      start: function (intro) {
        if (on || reduceMotion.matches) return;
        on = true;
        measure();
        apply();
        if (intro) {
          window.setTimeout(function () {
            root.classList.add('beam-on');
          }, 1150);
        } else {
          root.classList.add('beam-on');
        }
      },
      // Rest the light on an entry (the row the title lands on, back home).
      hold: function (li) {
        if (!li) return;
        restTop = li.getBoundingClientRect().top + window.scrollY + 15;
        restHeld = true;
        schedule();
      }
    };
  }

  // ---- 4. an entry page: the margins and Escape go back to the home ----------

  if (thisPage() !== 'entry') return;

  // If the page before this one (past any #hash hops on this page) is the home,
  // step back to it: the home keeps its scroll position and the back transition
  // plays. Otherwise open the home.
  function goHome() {
    try {
      var nav = window.navigation;
      if (nav && typeof nav.entries === 'function' && nav.currentEntry) {
        var list = nav.entries();
        var at = nav.currentEntry.index;
        var now = pathOf(location.href);
        var j = at - 1;
        while (j >= 0 && list[j].url && pathOf(list[j].url) === now) j--;
        if (j >= 0 && list[j].url && kind(list[j].url) === 'home') {
          history.go(j - at);
          return;
        }
        location.assign('/');
        return;
      }
    } catch (e) {}
    // no Navigation API: the referrer says where this page was opened from
    var ref = document.referrer;
    if (history.length > 1 && !location.hash && ref && kind(ref) === 'home') history.back();
    else location.assign('/');
  }

  // The back links do the same, so the home comes back where it was left.
  var backLinks = document.querySelectorAll('[data-home]');
  Array.prototype.forEach.call(backLinks, function (link) {
    link.addEventListener('click', function (event) {
      if (event.defaultPrevented || event.button !== 0) return;
      if (event.metaKey || event.ctrlKey || event.shiftKey || event.altKey) return;
      event.preventDefault();
      goHome();
    });
  });

  var armed = false; // the press began on the margin, not on the column

  // The margin is the body (or html) itself: the bar and the column are its children.
  function onMargin(target) {
    return target === document.body || target === root;
  }

  document.addEventListener(
    'pointerdown',
    function (event) {
      armed = event.button === 0 && onMargin(event.target);
    },
    true
  );

  document.addEventListener('click', function (event) {
    var wasArmed = armed;
    armed = false;
    if (!wasArmed || event.defaultPrevented) return;
    if (event.button !== 0 || event.metaKey || event.ctrlKey || event.shiftKey || event.altKey) return;
    if (!window.matchMedia('(pointer: fine)').matches) return;
    if (!onMargin(event.target)) return;
    var selection = window.getSelection && window.getSelection();
    if (selection && !selection.isCollapsed) return; // the end of a text selection
    goHome();
  });

  document.addEventListener('keydown', function (event) {
    if (event.key !== 'Escape' || event.defaultPrevented || event.isComposing) return;
    if (event.metaKey || event.ctrlKey || event.shiftKey || event.altKey) return;
    var t = event.target;
    if (t && t.closest && t.closest('input, textarea, select, [contenteditable]')) return;
    // Handled here: left unhandled, the same press reaches Chrome's own Escape
    // (stop loading), which aborts the navigation goHome has just started.
    event.preventDefault();
    goHome();
  });
})();
