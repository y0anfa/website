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
mix site.build     # write the site to dist/
mix site.verify    # build twice into temporary directories and compare; fails on any difference
mix test           # run the test suite
```

`mix site.build` also accepts `--drafts`, `--content DIR` and `--out DIR`.

Two review variants of the home page are chosen with query parameters:

- `?home=b` (split screen, the default) or `?home=d` (the field is the nav).
- `?field=water` (the default) or `?field=wind`.

For example, `http://localhost:4000/?home=d&field=wind`. The choice is kept for the session, so it holds when you navigate back home.

`mix site.serve` applies the headers from `dist/_headers`, so a Content Security Policy violation shows locally in the same way it does in production.

## Content

All words live in `content/`. The full model is in [SPEC.md §5](SPEC.md#5-content-model).

| Path | Holds |
|---|---|
| `content/home.md` | home intro |
| `content/essays/*.md` | essays |
| `content/notes/*.md` | notes |
| `content/projects/*.md` | projects |
| `content/uses.md`, `content/cv.md` | the uses and cv pages |

A slug is the filename without `.md` and without a leading `YYYY-MM-DD-` prefix. Dates come from the `date` field, not the filename.

Frontmatter sits between `---` lines.

- **essays, notes:** `title` and `date` (required, `YYYY-MM-DD`). `description` is optional and falls back to the first paragraph, cut to 160 characters. `draft: true` keeps the entry out of the build unless you run `mix site.build --drafts`.
- **projects:** `title`, `date`, `tagline` and `status` (required; `active`, `wip` or `archived`). `link` and `stack` are optional.
- **home.md, uses.md, cv.md:** `title` and `description` (required).

Markdown uses GitHub-flavoured extensions: tables, strikethrough, autolinks, footnotes and heading ids. Raw HTML is not rendered. The build fails on a missing required field, a bad date, or a duplicate slug within a type.

## Deploy

A push to `main` runs [.github/workflows/deploy.yml](.github/workflows/deploy.yml). It can also be started by hand with `workflow_dispatch`.

1. **build** checks out the full history, which the commit hashes need. It sets up Erlang and Elixir from `.tool-versions`, restores the dependency and `_build` cache, then runs the format check, the tests, `site.verify` and `site.build` in `prod` mode. The `dist/` directory is uploaded as an artifact. The Web Analytics beacon is included only when the repo variable `CF_BEACON_TOKEN` is set.
2. **deploy** runs only for `main`, in the `production` environment. It downloads `dist/` and runs `wrangler deploy` with a pinned wrangler version. The Cloudflare secrets are used only in this job.

`wrangler.jsonc` defines an assets-only Worker. Its custom domain route stays commented out until the cutover below.

## Cutover checklist

These are one-time steps for the owner, in order.

1. In Cloudflare, add the zone `yoanfau.re` (Free plan) and check the imported DNS records.
2. At OVH, switch the nameservers to the two Cloudflare nameservers.
3. Create an API token from the "Edit Cloudflare Workers" template, scoped to the account and the `yoanfau.re` zone. Add it as the GitHub repo secret `CLOUDFLARE_API_TOKEN`, and add the account ID as the repo secret `CLOUDFLARE_ACCOUNT_ID`.
4. In Cloudflare Web Analytics, add the site. Put its token in the GitHub repo *variable* `CF_BEACON_TOKEN`. It is a variable, not a secret, because the beacon sends it to the browser.
5. Set up Email Routing so `hello@yoanfau.re` forwards to a personal inbox.
6. Uncomment the `routes` line in `wrangler.jsonc` and push. Once the Worker serves `yoanfau.re`, delete the old GitHub Pages A records (`185.199.108.153` to `185.199.111.153`) and disable GitHub Pages in the repo settings.
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
