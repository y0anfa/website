# yoanfaure.com

Personal site of Yoan Faure. A static site built by a small Elixir generator and served from Cloudflare Workers.

[SPEC.md](SPEC.md) is the contract for the site. If the code and the spec disagree, change one of them on purpose.

## Requirements

- Erlang and Elixir, as pinned in [.tool-versions](.tool-versions). CI reads the same file. Any version manager that reads `.tool-versions` (asdf, mise) will install them.
- Git is optional for building. The log shows commit hashes only for committed files, so a build without git still works and shows placeholders.

## Commands

```sh
mix deps.get       # fetch dependencies
mix site.serve     # build and serve at http://localhost:4000 (--port to change)
mix site.build     # write the site to dist/ (pages, assets, _headers, _redirects, robots.txt)
mix site.verify    # build twice into temporary directories and compare; fails on any difference
mix test           # run the test suite
```

`mix site.build` also accepts `--drafts`, `--content DIR` and `--out DIR`.

The field is a quiet backdrop of topographic contour lines on every page: behind everything on the home, only in the side margins on entry pages.

`mix site.serve` applies the headers from `dist/_headers`, so a Content Security Policy violation shows locally in the same way it does in production. It does not apply `dist/_redirects`: the old Hugo URLs only redirect on Cloudflare.

## Content

All words live in `content/`. The full model is in [SPEC.md §5](SPEC.md#5-content-model).

| Path | Holds |
|---|---|
| `content/home.md` | the home intro |
| `content/essays/*.md` | essays |
| `content/notes/*.md` | notes |
| `content/projects/*.md` | projects |

There is one log, on the home, and it lists every essay, note and project. The folder an entry lives in sets its type, which shows as a label in the log and in the entry's meta line. It does not set the URL: every entry lives at `/<slug>/`, for example `/threat-modeling-with-claude-code/` or `/rhino/`.

A slug is the filename without `.md` and without a leading `YYYY-MM-DD-` prefix. Dates come from the `date` field, not the filename. Slugs are unique across **all** types, so an essay and a note cannot share one. A few are reserved because they would collide with a site path or a legacy redirect: `assets`, `404`, `404.html`, `index`, `index.html`, `robots.txt`, `_headers`, `_redirects`, `blog`, `projects` and `resume`.

Frontmatter sits between `---` lines.

- **essays, notes:** `title` and `date` (required, `YYYY-MM-DD`). `description` is optional and falls back to the first paragraph, cut to 160 characters. `draft: true` keeps the entry out of the build unless you run `mix site.build --drafts`.
- **projects:** `title`, `date`, `tagline` and `status` (required; `active`, `wip` or `archived`). `link` and `stack` are optional.
- **home.md:** `title` and `description` (required), `tagline` (optional).

Markdown uses GitHub-flavoured extensions: tables, strikethrough, autolinks, footnotes and heading ids. Raw HTML is not rendered. The build fails on a missing required field, a bad date, a duplicate slug (it names both files) or a reserved slug.

The old Hugo URLs are redirected by `dist/_redirects`, which the build writes: `/blog/*` and `/projects/*` go to `/:splat`, and `/resume` and `/resume/` go to `/`. The rules are in `Site.Config.redirects/0`.

## Fonts

Text is Inter (variable, `assets/fonts/InterVariable.woff2` and `InterVariable-Italic.woff2`). JetBrains Mono (400 only) is used for code, the log's hash and date, and the backdrop field. Both are self-hosted, and their licences sit next to them (`Inter-OFL.txt`, `JetBrainsMono-OFL.txt`).

## Deploy

A push to `main` runs [.github/workflows/deploy.yml](.github/workflows/deploy.yml). It can also be started by hand with `workflow_dispatch`.

1. **build** checks out the full history, which the commit hashes need. It sets up Erlang and Elixir from `.tool-versions`, restores the dependency and `_build` cache, then runs the format check, the tests, `site.verify` and `site.build` in `prod` mode. The `dist/` directory is uploaded as an artifact. No repo variable or token is needed: Cloudflare Web Analytics runs on automatic setup, so Cloudflare injects the beacon at the edge.
2. **deploy** runs only for `main`, in the `production` environment. It downloads `dist/`, runs `wrangler deploy` for the site, then for the redirect Worker, with a pinned wrangler version. The Cloudflare secrets are used only in this job.

`wrangler.jsonc` defines an assets-only Worker with `yoanfaure.com` as its custom domain. A second step deploys the redirect Worker in `redirect/`, after the site.

## Domains

- `yoanfaure.com` is the site: a Workers custom domain on the `yoanfaure` Worker.
- `yoanfau.re` and `www.yoanfaure.com` redirect (301, path and query kept) to `yoanfaure.com`. The redirect Worker in `redirect/` keeps the old Worker name `yoanfau-re`, so the old domain never detached. `www.yoanfau.re` goes to the `yoanfau.re` apex by a Redirect Rule, then on to `yoanfaure.com`.
- Both zones are on Cloudflare. Mail for `@yoanfau.re` stays on OVH (keep its MX and SPF records). `hi@yoanfaure.com` uses Cloudflare Email Routing.
- The API token in `CLOUDFLARE_API_TOKEN` must cover both zones.

Owner steps still open:

1. In Cloudflare, turn on **Always Use HTTPS** and turn off **Email Address Obfuscation** for `yoanfaure.com`.
2. Set up Email Routing for `hi@yoanfaure.com`.
3. Re-enable DNSSEC for both zones in Cloudflare, and add each DS record at its registrar.
4. Optional, later: submit `yoanfaure.com` to the HSTS preload list. The list requires the `preload` directive, which the `Strict-Transport-Security` header in `_headers` does not have yet.

## Security

- The Content Security Policy is strict. Scripts come only from `'self'` and one hashed inline script (`assets/js/head.js`), plus the Cloudflare Web Analytics beacon, which Cloudflare injects at the edge. There are no inline styles or event handlers.
- There are no third-party assets. The one exception is the Cloudflare Web Analytics beacon: the CSP always allows `static.cloudflareinsights.com` (scripts) and `cloudflareinsights.com` (connections), and the built pages carry no beacon tag.
- Commits are signed with an SSH key registered on GitHub as a signing key. Security headers are generated into `dist/_headers` at build time.
- Every third-party action is pinned to a full commit SHA, with the release version in a comment.
- The build is deterministic. `mix site.verify` checks it, and CI runs it before every deploy.
