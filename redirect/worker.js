// Sends every request, path and query intact, to the canonical domain.
// Old Hugo paths (/blog/…) are then resolved by the site's own _redirects.
const CANONICAL = 'yoanfaure.com';

export default {
  fetch(request) {
    const url = new URL(request.url);
    url.protocol = 'https:';
    url.hostname = CANONICAL;
    url.port = '';

    return new Response(null, {
      status: 301,
      headers: {
        Location: url.toString(),
        'Strict-Transport-Security': 'max-age=63072000; includeSubDomains',
      },
    });
  },
};
