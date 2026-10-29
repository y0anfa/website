# yoanfau.re

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

1. **build** checks out the full history, which the commit hashes need. It sets up Erlang and Elixir from `.tool-versions`, restores the dependency and `_build` cache, then runs the format check, the tests, `site.verify` and `site.build` in `prod` mode. The `dist/` directory is uploaded as an artifact. The Web Analytics beacon is included only when the repo variable `CF_BEACON_TOKEN` is set.
2. **deploy** runs only for `main`, in the `production` environment. It downloads `dist/` and runs `wrangler deploy` with a pinned wrangler version. The Cloudflare secrets are used only in this job.

`wrangler.jsonc` defines an assets-only Worker with `yoanfau.re` as its custom domain.

## Cutover checklist

These are one-time steps for the owner, in order.

1. In Cloudflare, add the zone `yoanfau.re` (Free plan) and check the imported DNS records.
2. At OVH, switch the nameservers to the two Cloudflare nameservers.
3. Create an API token from the "Edit Cloudflare Workers" template, scoped to the account and the `yoanfau.re` zone. Add it as the GitHub repo secret `CLOUDFLARE_API_TOKEN`, and add the account ID as the repo secret `CLOUDFLARE_ACCOUNT_ID`.
4. In Cloudflare Web Analytics, add the site. Put its token in the GitHub repo *variable* `CF_BEACON_TOKEN`. It is a variable, not a secret, because the beacon sends it to the browser.
5. Mail stays on OVH (MX Plan): keep the OVH MX and SPF records in Cloudflare, and don't enable Cloudflare Email Routing, which would replace them. Create `hello@yoanfau.re` as an OVH redirection (Web Cloud → Emails → yoanfau.re → Redirections) to your inbox.
6. Turn off Email Address Obfuscation for the zone (it rewrites `mailto:` links and injects a script). Delete the old GitHub Pages A records (`185.199.108.153` to `185.199.111.153`) first, since a custom domain can't attach while they exist, then push with the `routes` line in `wrangler.jsonc`. Make `www` a proxied CNAME to `yoanfau.re` with the "Redirect from WWW to root" rule, and unpublish GitHub Pages.
7. Add the SSH key to GitHub as a signing key, so commits show as verified:

   ```sh
   gh auth refresh -s admin:ssh_signing_key
   gh ssh-key add ~/.ssh/id_ed25519.pub --type signing --title "yoanfa signing"
   ```

8. Optional, later: submit the domain to the HSTS preload list. The list requires the `preload` directive, which the `Strict-Transport-Security` header in `_headers` does not have yet.

## Security

- The Content Security Policy is strict. Scripts come only from `'self'` and one hashed inline script (`assets/js/head.js`), plus the beacon when it is enabled. There are no inline styles or event handlers.
- There are no third-party assets. The one exception is the optional Cloudflare Web Analytics beacon, included only when `CF_BEACON_TOKEN` is set.
- Commits are signed (see cutover step 7). Security headers are generated into `dist/_headers` at build time.
- Every third-party action is pinned to a full commit SHA, with the release version in a comment.
- The build is deterministic. `mix site.verify` checks it, and CI runs it before every deploy.
