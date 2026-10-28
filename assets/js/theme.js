(function () {
  var button = document.querySelector('.theme-toggle');
  if (!button) return;

  var root = document.documentElement;
  var dark = window.matchMedia('(prefers-color-scheme: dark)');

  function effective() {
    var forced = root.getAttribute('data-theme');
    if (forced === 'light' || forced === 'dark') return forced;
    return dark.matches ? 'dark' : 'light';
  }

  button.addEventListener('click', function () {
    var next = effective() === 'dark' ? 'light' : 'dark';
    root.setAttribute('data-theme', next);
    try {
      localStorage.setItem('theme', next);
    } catch (e) {}
  });
})();
