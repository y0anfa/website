(function () {
  var button = document.querySelector('.theme-toggle');
  if (!button) return;

  var root = document.documentElement;
  var dark = window.matchMedia('(prefers-color-scheme: dark)');
  var still = window.matchMedia('(prefers-reduced-motion: reduce)');
  var wanted = null; // the theme a view transition is about to apply

  function effective() {
    var forced = root.getAttribute('data-theme');
    if (forced === 'light' || forced === 'dark') return forced;
    return dark.matches ? 'dark' : 'light';
  }

  button.addEventListener('click', function () {
    var next = (wanted || effective()) === 'dark' ? 'light' : 'dark';
    var applied = false;
    wanted = next;

    function apply() {
      if (applied) return;
      applied = true;
      if (wanted === next) wanted = null;
      root.setAttribute('data-theme', next);
      try {
        localStorage.setItem('theme', next);
      } catch (e) {}
    }

    // A soft cross-fade of the whole page (type "theme", see site.css). Without
    // view transitions, or with reduced motion, the theme just switches.
    if (typeof document.startViewTransition === 'function' && !still.matches) {
      try {
        var transition = document.startViewTransition({ update: apply, types: ['theme'] });
        // a second click skips the first transition: that is not an error
        transition.ready.catch(function () {});
        return;
      } catch (e) {
        // an engine that only knows the callback form throws on the options object
      }
    }
    apply();
  });
})();
