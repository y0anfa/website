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
 *    title on the line, the h1 on the entry.
 * 3. The home: the line. One path the height of the window, still unless a mouse
 *    comes close: then it leans a few pixels toward it and eases back. Each row's
 *    mark follows it through one custom property; the words never move.
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
    if (intro) root.classList.add('intro');
    if (line) line.start(intro);

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
        }
      }
    } catch (e) {}
  });

  // A page restored from the back/forward cache comes back as it was frozen.
  window.addEventListener('pageshow', function (event) {
    if (event.persisted) clear();
  });

  // ---- 3. the home: the line -------------------------------------------------

  var line = thisPage() === 'home' ? makeLine() : null;
  if (line && !('onpagereveal' in window)) line.start(false);

  function makeLine() {
    var svg = document.querySelector('.line');
    var path = svg && svg.querySelector('path');
    var stage = document.querySelector('.stage');
    if (!path || !stage) return null;

    var N = 72; // points along the line
    var REACH = 64; // px either side of the line within which it feels the pointer
    var SPREAD = 84; // px up and down the line that lean with it
    var TAU = 130; // ms: how softly it follows. No spring: it never overshoots.

    var rows = []; // the name and every entry: the element, its mark's height, its lean
    var u = []; // how far each point of the line leans, px
    var H = 0;
    var x0 = 0;
    var pointer = null; // a mouse on the page, in viewport coordinates
    var on = false;
    var raf = 0;
    var last = 0;

    for (var n = 0; n <= N; n++) u.push(0);
    Array.prototype.forEach.call(document.querySelectorAll('.identity, .entry-row'), function (el) {
      rows.push({ el: el, y: 0, dx: 0 });
    });

    // On start, resize and font load only. The marks are pseudo-elements, so their
    // place is read from the row and the stylesheet: on the axis, at their own top.
    function measure() {
      H = window.innerHeight;
      svg.setAttribute('viewBox', '0 0 ' + window.innerWidth + ' ' + H);
      var axis = parseFloat(window.getComputedStyle(stage).getPropertyValue('--axis')) || 0;
      for (var i = 0; i < rows.length; i++) {
        var box = rows[i].el.getBoundingClientRect();
        var mark = window.getComputedStyle(rows[i].el, '::before');
        rows[i].y = box.top + window.scrollY + (parseFloat(mark.top) || 0) + (parseFloat(mark.height) || 0) / 2;
        x0 = Math.round(box.left + axis) + 0.5; // on the pixel grid: a 1px line stays sharp
      }
      draw();
    }

    // Where a point of the line wants to be. Toward the pointer, a little: it leans
    // most (about 6px) at a third of its reach and is back in place at the edge of
    // it. Zero when the pointer is on the line, so crossing it is one smooth pass.
    function goal(y) {
      if (!pointer) return 0;
      var d = pointer.x - x0;
      var far = Math.abs(d) / REACH;
      if (far >= 1) return 0;
      var dy = (y - pointer.y) / SPREAD;
      return 0.6 * d * (1 - far) * (1 - far) * Math.exp(-dy * dy);
    }

    function at(y) {
      var f = Math.min(N, Math.max(0, (y / H) * N));
      var i = Math.min(N - 1, Math.floor(f));
      return u[i] + (u[i + 1] - u[i]) * (f - i);
    }

    function draw() {
      var step = H / N;
      var d = 'M' + x0.toFixed(1) + ' -2';
      for (var i = 1; i < N; i++) {
        d +=
          ' Q' + (x0 + u[i]).toFixed(2) + ' ' + (i * step).toFixed(1) +
          ' ' + (x0 + (u[i] + u[i + 1]) / 2).toFixed(2) + ' ' + ((i + 0.5) * step).toFixed(1);
      }
      path.setAttribute('d', d + ' L' + x0.toFixed(1) + ' ' + (H + 2));
      for (var r = 0; r < rows.length; r++) {
        var row = rows[r];
        var dx = at(row.y - window.scrollY);
        if (Math.abs(dx - row.dx) < 0.02) continue;
        row.dx = dx;
        row.el.style.setProperty('--lean', dx.toFixed(2) + 'px');
      }
    }

    function frame(now) {
      raf = 0;
      var k = 1 - Math.exp(-(last ? Math.min(64, now - last) : 16) / TAU);
      last = now;
      var step = H / N;
      var moving = false;
      for (var i = 1; i < N; i++) {
        var to = goal(i * step);
        u[i] += (to - u[i]) * k;
        if (Math.abs(to - u[i]) > 0.02) moving = true;
        else u[i] = to;
      }
      draw();
      if (moving) wake();
      else last = 0;
    }

    function wake() {
      if (on && !raf && !reduceMotion.matches) raf = window.requestAnimationFrame(frame);
    }

    function refresh() {
      if (on) measure();
    }

    document.addEventListener(
      'pointermove',
      function (event) {
        if (event.pointerType !== 'mouse') return; // a finger scrolls; the line stays still for it
        pointer = { x: event.clientX, y: event.clientY };
        wake();
      },
      { passive: true }
    );

    document.addEventListener('mouseout', function (event) {
      if (event.relatedTarget) return; // still on the page
      pointer = null;
      wake();
    });

    window.addEventListener(
      'scroll',
      function () {
        if (on) draw();
      },
      { passive: true }
    );
    window.addEventListener('resize', refresh);
    if (document.fonts && document.fonts.ready) document.fonts.ready.then(refresh);

    return {
      // Draw the line. On a fresh load, each mark appears as the drawn line reaches
      // it: --at is its moment in the entrance.
      start: function (intro) {
        if (on) return;
        on = true;
        measure();
        if (!intro) return;
        for (var i = 0; i < rows.length; i++) {
          var when = Math.round(160 + ((rows[i].y - window.scrollY) / H) * 820);
          rows[i].el.style.setProperty('--at', when + 'ms');
        }
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
