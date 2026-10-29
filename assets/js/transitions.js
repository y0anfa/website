/* Page transitions, the half that needs script (SPEC section 7, Transitions).
 *
 * The motion itself is CSS (site.css). This file only tells the browser which way
 * a navigation goes and which one element is the shared title, using the page
 * swap events of cross-document view transitions:
 *
 *   pageswap    the old page, about to unload.
 *   pagereveal  the new page, about to be shown (it also fires when a page is
 *               restored from the back/forward cache or activated from a prerender).
 *
 * Direction: home -> entry is "forward", entry -> home is "back" (a link, the back
 * button and the margin click all alike). Every other navigation gets no type.
 * Side: the old page also gets the type "leaving" and the new page "arriving". Only
 * the new page names its content (in the CSS): the old page's picture of a long essay
 * would be one very tall image, which the browser can fail to draw (a white frame), so
 * the old content stays in the old page's root image, which is only as big as the
 * viewport.
 * Shared title: at most one element per page carries the name "entry-title" at a
 * time (a duplicate name makes the browser skip the whole transition). The clicked
 * log title on the way in, the h1 on the way back, and the same pair mirrored on the
 * new page. A page that cannot name its title (it is scrolled out of view, or the
 * row is not there) just skips the morph: the CSS then treats the other side as
 * ordinary content.
 *
 * Also here: on an entry page, a click on the side margins, or Escape, goes back to
 * the log. No inline handler, no inline style: names are written through the CSSOM.
 */
(function () {
  'use strict';

  var NAME = 'entry-title';
  var root = document.documentElement;
  var named = null; // the one element that carries the name right now

  // ---- which page is which ----------------------------------------------------

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

  // ---- the shared title -------------------------------------------------------

  function clear() {
    if (!named) return;
    try {
      named.style.removeProperty('view-transition-name');
    } catch (e) {}
    named = null;
  }

  function claim(el) {
    clear();
    if (!el) return false;
    el.style.setProperty('view-transition-name', NAME);
    named = el;
    return true;
  }

  // Fully on screen: a title that is half cut off would fly in from nowhere.
  function inView(el) {
    var r = el.getBoundingClientRect();
    return r.height > 0 && r.top >= 0 && r.bottom <= window.innerHeight;
  }

  function rowTitle(url) {
    var path = pathOf(url);
    var links = document.querySelectorAll('.log-title');
    for (var i = 0; i < links.length; i++) {
      if (pathOf(links[i].href) === path) return links[i];
    }
    return null;
  }

  function heading() {
    return document.querySelector('main .prose > h1');
  }

  function mark(vt, type, side) {
    if (vt.types && typeof vt.types.add === 'function') {
      vt.types.add(type);
      vt.types.add(side);
    }
    // clear on any outcome: finished, skipped, or a rejected promise
    vt.finished.then(clear, clear);
    // a skipped transition (a hidden page, say) is not an error
    vt.ready.catch(function () {});
  }

  window.addEventListener('pageswap', function (event) {
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
    clear();
    try {
      var vt = event.viewTransition;
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
          // bring the row we came from on screen, the least it takes, so the
          // title has somewhere to land (the old image covers any jump)
          row.scrollIntoView({ block: 'nearest', inline: 'nearest' });
          if (inView(row)) claim(row);
        }
      }
    } catch (e) {}
  });

  // A page restored from the back/forward cache comes back as it was frozen.
  window.addEventListener('pageshow', function (event) {
    if (event.persisted) clear();
  });

  // ---- entry pages: the margins and Escape go back to the log -----------------

  if (thisPage() !== 'entry') return;

  // Back to the log. If the page before this one (past any #hash hops on this page)
  // is the home, step back to it, so the home keeps its scroll position and the back
  // transition plays; otherwise go to the home.
  function goLog() {
    try {
      var nav = window.navigation;
      if (nav && typeof nav.entries === 'function' && nav.currentEntry) {
        var list = nav.entries();
        var here = nav.currentEntry.index;
        var now = pathOf(location.href);
        var j = here - 1;
        while (j >= 0 && list[j].url && pathOf(list[j].url) === now) j--;
        if (j >= 0 && list[j].url && kind(list[j].url) === 'home') {
          history.go(j - here);
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

  var fine = window.matchMedia ? window.matchMedia('(pointer: fine)') : null;
  var armed = false; // the press began on the margin, not on the paper

  // The margin is the body (or html) itself: the paper (header, main, footer) is
  // a child of it, and the field has no pointer events.
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
    if (!fine || !fine.matches) return;
    if (!onMargin(event.target)) return;
    var selection = window.getSelection && window.getSelection();
    if (selection && !selection.isCollapsed) return; // the end of a text selection
    goLog();
  });

  document.addEventListener('keydown', function (event) {
    if (event.key !== 'Escape' || event.defaultPrevented || event.isComposing) return;
    if (event.metaKey || event.ctrlKey || event.shiftKey || event.altKey) return;
    var t = event.target;
    if (t && t.closest && t.closest('input, textarea, select, [contenteditable]')) return;
    goLog();
  });
})();
