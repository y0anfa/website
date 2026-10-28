(function () {
  var root = document.documentElement;
  var choices = { field: ['topo', 'water'] };
  try {
    var query = new URLSearchParams(location.search);
    Object.keys(choices).forEach(function (key) {
      var value = query.get(key);
      try {
        if (choices[key].indexOf(value) > -1) sessionStorage.setItem(key, value);
        else value = sessionStorage.getItem(key);
      } catch (e) {
        if (choices[key].indexOf(value) < 0) value = null;
      }
      if (choices[key].indexOf(value) > -1) root.setAttribute('data-' + key, value);
    });
  } catch (e) {}
  try {
    var theme = localStorage.getItem('theme');
    if (theme === 'light' || theme === 'dark') root.setAttribute('data-theme', theme);
  } catch (e) {}
})();
