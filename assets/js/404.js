(function () {
  var target = document.querySelector('[data-path]');
  if (target) target.textContent = location.pathname;
})();
