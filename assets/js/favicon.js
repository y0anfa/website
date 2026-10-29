(function () {
  var link = document.querySelector('link[rel="icon"]');
  if (!link) return;

  var awake = link.getAttribute('href');
  var asleep = '/assets/favicon-sleep.svg';

  document.addEventListener('visibilitychange', function () {
    link.setAttribute('href', document.visibilityState === 'hidden' ? asleep : awake);
  });
})();
