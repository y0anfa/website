(function () {
  var root = document.documentElement;
  try {
    var theme = localStorage.getItem('theme');
    if (theme === 'light' || theme === 'dark') root.setAttribute('data-theme', theme);
  } catch (e) {}
  // review only: ?vt=morph|fade|rise picks the page transition and sticks for the tab
  try {
    var ok = /^(morph|fade|rise)$/;
    var vt = new URLSearchParams(location.search).get('vt');
    if (ok.test(vt)) {
      root.setAttribute('data-vt', vt);
      sessionStorage.setItem('vt', vt);
    } else {
      vt = sessionStorage.getItem('vt');
      if (ok.test(vt)) root.setAttribute('data-vt', vt);
    }
  } catch (e) {}
})();
