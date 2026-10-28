# yoanfau.re — v2 spec

The contract every contributor (human or agent) builds against. If code and spec disagree, fix one of them on purpose.

## 1. Intent

Personal site of **Yoan Faure, security engineer who builds** (Riot, Paris).
It shows who he is, what he thinks, and what he makes.

- **Audience:** security peers and curious strangers. Not recruiters.
- **Voice:** plain and precise. Short sentences, first person, no buzzwords, no exclamation marks, no emoji.
- **Style:** bold but simple. Little content, accessible information. Monochrome, all monospace, and one signature moment (the ASCII field).
- **Language:** English.

## 2. Decisions

| Topic | Decision |
|---|---|
| Pages | home (with intro), essays, notes, projects, uses, cv, 404. No about page, no now page, no RSS, no colophon. |
| Home | Two prototypes, switched by `?home=b` (split screen, the default) or `?home=d` (the field is the nav). The loser gets deleted after review. |
| Feed | A "git log" list. Each row is: real short commit hash (linked to GitHub), date, type, title. |
| Signature | An abstract ASCII field, peaceful and a bit retro. Two presets compared via `?field=water` (default) or `?field=wind`. |
| Type | JetBrains Mono everywhere, self-hosted. |
| Color | Monochrome only. Light and dark follow the system, with a manual toggle. |
| Motion | Only the field moves. Everything else is static. `prefers-reduced-motion` gets a static field frame. |
| Build | Hand-rolled static generator in Elixir: EEx templates, MDEx for Markdown, YamlElixir for frontmatter. |
| Hosting | Cloudflare Workers, assets-only, deployed by GitHub Actions with wrangler. |
| Analytics | Cloudflare Web Analytics beacon, the single third-party exception in the CSP, included only when `CF_BEACON_TOKEN` is set at build time. |
| Security | Strict CSP, no third-party assets, security headers via `_headers`, signed commits, deterministic build checked in CI. |
| Contact | `hello@yoanfau.re` (Cloudflare Email Routing) and LinkedIn `https://linkedin.com/in/yoan-faure`. |
| Repo | `y0anfa/yoanfau.re`, fresh orphan history on `main`. The old Hugo site is on `archive/hugo`. |

## 3. Repository layout

```
.
├── SPEC.md                    this file
├── README.md                  how to build, run, deploy; cutover checklist
├── .tool-versions             erlang 29.1.2 / elixir 1.20.4-otp-29 (CI reads it)
├── .gitignore
├── mix.exs / mix.lock / .formatter.exs
├── lib/
│   ├── site/…                 build engine modules (Site.*)
│   └── mix/tasks/…            mix site.build | site.serve | site.verify
├── test/                      ExUnit tests + test/fixtures/content/…
├── templates/                 EEx templates (*.html.eex) and partials (_*.html.eex)
├── content/                   all words live here (see §5)
├── assets/                    copied verbatim to dist/assets/
│   ├── css/site.css
│   ├── js/head.js             inlined into <head>; its sha256 goes in the CSP
│   ├── js/theme.js            theme toggle
│   ├── js/field.js            the ASCII field (ES module)
│   ├── js/404.js              fills the missing path on the 404 page
│   ├── fonts/JetBrainsMono-{Regular,Italic,Bold,ExtraBold}.woff2 + OFL.txt
│   └── favicon.svg
├── lab/field.html             standalone playground for field.js (never built/deployed)
├── wrangler.jsonc
├── .github/workflows/deploy.yml
└── dist/                      build output (gitignored)
```

## 4. URLs

| URL | Source | Template |
|---|---|---|
| `/` | `content/home.md` + every entry | `home.html.eex` |
| `/essays/` | `content/essays/*.md` | `list.html.eex` |
| `/essays/<slug>/` | one essay | `article.html.eex` |
| `/notes/` | `content/notes/*.md` | `list.html.eex` |
| `/notes/<slug>/` | one note | `article.html.eex` |
| `/projects/` | `content/projects/*.md` | `list.html.eex` |
| `/projects/<slug>/` | one project | `project.html.eex` |
| `/uses/` | `content/uses.md` | `page.html.eex` |
| `/cv/` | `content/cv.md` | `page.html.eex` |
| `/404.html` | — | `404.html.eex` |

Every page is written as `<path>/index.html`. Slug = filename without `.md` and without a leading `YYYY-MM-DD-` prefix.
Also emit `robots.txt` (allow all) and `_headers`. There is no sitemap and no feed.

## 5. Content model

Markdown files with YAML frontmatter between `---` lines.

**essays/, notes/**
```yaml
title: string        # required
date: 2026-10-28     # required, ISO date
description: string  # optional; meta description (fallback: first paragraph, plain text, ≤160 chars)
draft: false         # optional; drafts are skipped unless `mix site.build --drafts`
```

**projects/**
```yaml
title: rhino
date: 2026-09-02           # required; position in the log
tagline: string            # required, one line
link: https://…            # optional
stack: [Go, YAML]          # optional
status: active | wip | archived
```

**home.md, uses.md, cv.md**
```yaml
title: string
description: string
tagline: string      # optional; home only — rendered under the h1, kept clear of the field
```

Raw HTML in Markdown is **not** rendered: MDEx runs with `unsafe: false`. Use GFM extensions: tables, strikethrough, autolink, footnotes, and heading ids. There is no syntax colouring; code blocks are plain monochrome `<pre><code>`.

The build fails loudly on a missing required field, a bad date, or a duplicate slug within a type.

## 6. The log

Entries are essays, notes, and projects. Sort by date desc, then type (essay, project, note), then title asc.

```
9f19333  2026-10-28  note     Build the small tool
a3f9c21  2026-03-28  essay    Threat modeling with Claude Code
```

- **hash:** the first 7 characters of `git log -1 --format=%H -- <file>`. It links to `https://github.com/y0anfa/yoanfau.re/commit/<full sha>`. An untracked or uncommitted file, or no git at all, shows `·······` (7 middle dots) with no link.
- **date:** `YYYY-MM-DD`. **type:** `essay` / `note` / `project`, padded with CSS to 7ch. **title:** links to the entry.
- **Markup:** `<ol class="log">` > `<li class="log-row">` > `<a class="log-hash">`, `<time class="log-date">`, `<span class="log-type">`, `<a class="log-title">`.
- **Layout:** a CSS grid in `ch` units. Under ~600px it becomes two lines: hash and date, then type and title.
- `/essays/`, `/notes/` and `/projects/` reuse the same log partial, filtered by type.

## 7. Layout and pages

**Global shell**
- A skip link to `#main`.
- `header.site-header`: `a.brand` "yoan faure" on the left; `nav.site-nav` on the right with lowercase links `essays notes projects uses cv` (`aria-current="page"` on the active one) and `button.theme-toggle` (aria-label "Toggle theme").
- `main#main`.
- `footer.site-footer`: `hello@yoanfau.re · linkedin` on the left; `built from <a>a3f9c21</a>` on the right, linking to the HEAD commit (`-dirty` suffix if the tree is dirty, `unversioned` with no git).
- `<title>`: `<Page> — Yoan Faure` (home: `Yoan Faure — security engineer who builds`). Also meta description, canonical, `og:title/description/url/type`, `twitter:card=summary`, favicon, and a preload for the Regular font.

**Home**
- `<html data-home="b" data-field="water">` by default. The inline head script (`assets/js/head.js`) does three things:
  - Reads `?home=b|d` and `?field=water|wind`, sets them on `<html>` and remembers them in `sessionStorage`, so navigating back home keeps the variant during review.
  - Without params, falls back to `sessionStorage`.
  - Applies `localStorage.theme` (`light` / `dark`) to `data-theme`.
- Both variants share **one** HTML document. CSS switches layout on `[data-home]`. DOM contract (field.js depends on it):

```html
<section class="hero">
  <div class="field" data-field-root>
    <canvas class="field-canvas" aria-hidden="true"></canvas>
    <nav class="field-nav" aria-label="Sections">           <!-- shown only in variant D -->
      <a class="hotspot hotspot--essays" href="/essays/" data-hotspot>essays</a>
      … notes, projects, uses, cv …
    </nav>
  </div>
  <div class="intro"> h1 "Yoan Faure" + rendered home.md + contact line </div>
</section>
<section class="log-section" aria-labelledby="log-h"> <h2 id="log-h">log</h2> <ol class="log">…</ol> </section>
```

- **Variant B (split):** at ≥ 960px, two columns. The left column is sticky at 100vh: field on top (~60%), intro below. The right column scrolls the log. Below 960px: field band (~45vh), then intro, then log. `.field-nav` is `display:none`.
- **Variant D (field is nav):** the first screen is a full-viewport field. `.hotspot` links are absolutely positioned over it with **CSS classes** (percent coordinates per `hotspot--*`, never inline styles). The name and tagline sit centred. Hovered or focused hotspots invert (bg ↔ fg). Intro and log follow below the fold. `.site-nav` links are visually hidden on the home page in D; brand and theme toggle stay. On narrow screens the hotspots stack as a centred column.

**Article (essay, note):** `article.prose`, max 72ch. A meta line `essay · 2026-03-28 · <hash link>`, then h1, then body, then a `← essays` / `← notes` back link.
**Project:** h1, tagline, a meta line `status · stack · link`, then the body.
**List pages:** h1 (lowercase type name), one plain sentence, then the log.
**Page (uses, cv):** h1 and body. Markdown tables are styled as clean two- or three-column tables with rules.
**404:** `<pre>` reading `zsh: no such file or directory: <span data-path></span>`, then `cd ~` linking home. `404.js` fills `data-path` via `textContent`.

## 8. Visual system

```css
/* light (default when system is light) */
--bg: #f3f2ee;  --fg: #121212;  --muted: #6a6a66;  --rule: #d6d5cf;
/* dark */
--bg: #0f0f0e;  --fg: #e8e7e1;  --muted: #8b8a85;  --rule: #2b2b29;
```

- **Theming:** no `data-theme` means follow `prefers-color-scheme`; `[data-theme=light|dark]` forces it. `theme.js` toggles the effective theme and stores it in `localStorage`.
- **Font:** JetBrains Mono 400, 400 italic, 700 and 800, all `font-display: swap`. Body is 15px (16px at ≥ 960px) with line-height 1.65. Headings are 800 weight with tight tracking. h1 is `clamp(1.9rem, 1.2rem + 3vw, 3.25rem)`.
- **Links:** `color: inherit`, 1px underline with 0.2em offset. Hover and focus invert (`background: var(--fg); color: var(--bg)`). Focus-visible gets a 2px solid outline in `--fg`. Selection inverts.
- **Rules:** 1px `--rule`. Generous whitespace, lowercase UI labels, and nothing decorative except the field.
- **Contrast:** `--muted` must keep ≥ 4.5:1 against `--bg` in both themes.

## 9. The ASCII field (`assets/js/field.js`)

An ES module with no dependencies and no `innerHTML`/`eval`. It exports `mountField(root)` and auto-mounts every `[data-field-root]`.

- **Rendering:** draws to `canvas.field-canvas` sized to the root via ResizeObserver, DPR-aware (DPR capped at 2). Cell metrics come from the root's computed `font-family` and `font-size`, with `.field` set to 14px and line-height 1. It uses a pre-rendered glyph atlas tinted with the root's computed `color`. It waits for `document.fonts.ready` and rebuilds the atlas when the theme changes (MutationObserver on `<html>` `data-theme` plus the `prefers-color-scheme` change event).
- **Presets:** read from `document.documentElement.dataset.field`. The preset re-mounts if the attribute changes.
  - **water** (default) is a calm surface. A two-buffer height-field ripple simulation with gentle damping, over a very slow low-amplitude swell so it is never fully still. Occasional ambient drops arrive every ~2–4 s. Pointer movement leaves rate-limited drops along its path. Height maps to a soft ramp, e.g. ` .·:-=+*`; avoid heavy `#@` so it stays peaceful.
  - **wind** is grass in wind. A slow, mostly horizontal noise flow field with drifting gusts. Each cell's glyph comes from local angle and strength: calm cells use ` .,'`, gusts use `- ~ / | \`. The pointer parts the wind: strokes deflect radially within ~8 cells, easing back.
- **Hotspots (variant D):** collect visible `[data-hotspot]` in the root, in cell coordinates, and recompute on resize and on `data-home` change. Draw blank cells in a padded rect around each one so the word reads cleanly. On `pointerenter` or `focus`, a hotspot emits a soft effect: a centred drop for water, a widening calm for wind.
- **Budget:** 30 fps cap; pause when off-screen (IntersectionObserver) or when the document is hidden. Under 4 ms per frame at ~160×60 cells.
- **Accessibility:** the canvas is `aria-hidden`. Under `prefers-reduced-motion: reduce`, render one static frame with no loop and no pointer effects, re-rendered on resize and theme change.
- **CSP-safe:** sizing only via CSSOM (`canvas.style.width = …`), never `setAttribute('style')` and never inline `<style>`.
- **Playground:** `lab/field.html` mounts the field with a preset switch, a theme switch and a fake hotspot, for tuning without the build.

## 10. Build (Elixir)

- **Mix project `:site`.** Deps pinned in `mix.lock`:
  - `mdex` and `yaml_elixir` (runtime);
  - `bandit` and `plug`, `only: :dev`, for the dev server.
  - Nothing else.
- **`mix site.build [--drafts] [--content DIR] [--out DIR]`:**
  1. Clean the output.
  2. Load and validate content.
  3. Read git info (`System.cmd("git", …)`).
  4. Render the EEx templates. **EEx does not escape:** every interpolated string goes through `Site.HTML.escape/1`, and only rendered Markdown is inserted raw.
  5. Copy `assets/` to `dist/assets/` as is (no fingerprinting).
  6. Inline `assets/js/head.js` (trimmed) into `<head>` and compute its `sha256-…` for the CSP.
  7. Write `_headers` (§11), `robots.txt` and `404.html`.
- **Deterministic:** no build timestamps; sorted iteration everywhere; identical output for identical commit and env.
- **`mix site.verify`:** builds twice into temporary dirs, compares a SHA-256 over every file path and content, fails on mismatch, and prints the tree hash.
- **`mix site.serve [--port 4000]`:** builds, serves `dist/` with Bandit and Plug, and applies the headers parsed from `dist/_headers`, so CSP violations show up locally exactly as in production. It polls `content/`, `templates/`, `assets/` and `lib/` mtimes every second and rebuilds on change (no file_system dep). Missing paths serve `404.html` with status 404, and `/x/` serves `/x/index.html`.
- **Tests:** frontmatter parsing and validation, slugs, escaping, log ordering, CSP hash, and a determinism smoke test, all using `test/fixtures/content`.

## 11. Security headers (`dist/_headers`)

```
/*
  Content-Security-Policy: default-src 'none'; script-src 'self' '<head.js sha256>'[ https://static.cloudflareinsights.com]; style-src 'self'; img-src 'self'; font-src 'self'; connect-src 'self'[ https://cloudflareinsights.com]; manifest-src 'self'; base-uri 'none'; form-action 'none'; frame-ancestors 'none'; upgrade-insecure-requests
  Strict-Transport-Security: max-age=63072000; includeSubDomains
  X-Content-Type-Options: nosniff
  X-Frame-Options: DENY
  Referrer-Policy: strict-origin-when-cross-origin
  Permissions-Policy: accelerometer=(), camera=(), geolocation=(), gyroscope=(), magnetometer=(), microphone=(), payment=(), usb=()
  Cross-Origin-Opener-Policy: same-origin
  Cross-Origin-Resource-Policy: same-origin
/assets/fonts/*
  Cache-Control: public, max-age=31536000, immutable
```

The bracketed Cloudflare hosts appear only when `CF_BEACON_TOKEN` is set. In that case every page also gets `<script defer src="https://static.cloudflareinsights.com/beacon.min.js" data-cf-beacon='{"token":"…"}'></script>`.
**Never** use inline `style=""` attributes, inline `<style>`, inline event handlers, or any inline script other than head.js.

## 12. Hosting and deploy

- **`wrangler.jsonc`:** an assets-only Worker named `yoanfau-re` with `assets.directory: ./dist`, `not_found_handling: "404-page"` and `html_handling: "auto-trailing-slash"`. The `yoanfau.re` custom-domain route stays **commented out** until the DNS cutover.
- **`.github/workflows/deploy.yml`** runs on push to `main` and on `workflow_dispatch`, with least-privilege permissions. **Every third-party action is pinned to a full commit SHA** with a `# vX.Y.Z` comment.
  - The **build** job: checkout with `fetch-depth: 0` (needed for per-file hashes), then `erlef/setup-beam` with `version-file: .tool-versions` and `version-type: strict`, a deps cache, `mix format --check-formatted`, `mix test`, `MIX_ENV=prod mix site.verify`, and `MIX_ENV=prod mix site.build` with `CF_BEACON_TOKEN: ${{ vars.CF_BEACON_TOKEN }}`. It uploads `dist`.
  - The **deploy** job (only on `main`) runs `cloudflare/wrangler-action` with secrets `CLOUDFLARE_API_TOKEN` and `CLOUDFLARE_ACCOUNT_ID`.
- **Cutover:** these are the owner's steps, documented in README:
  1. Add the zone to Cloudflare and switch the OVH nameservers.
  2. Create an API token and add the repo secrets.
  3. Create the Web Analytics site and add the repo variable `CF_BEACON_TOKEN`.
  4. Set up Email Routing for `hello@`.
  5. Uncomment the route and deploy.
  6. Disable GitHub Pages.
  7. Add the SSH key on GitHub as a *signing* key.

## 13. Launch content

All drafts are Yoan's to edit. Everything is dated at launch (2026-10-28) unless noted.

- **home.md:** the intro (see `content/home.md`).
- **essays/2026-03-28-threat-modeling-with-claude-code.md:** migrated verbatim from `archive/hugo`.
- **Notes**, one idea each, 120–300 words:
  1. *Build the small tool*: a lightweight, fine-tuned tool beats expensive complex software.
  2. *Security should unleash*: security exists to unleash engineering and the business, not to gate them.
  3. *Security pays in more than one currency*: risk reduction, business enablement, human time.
  4. *AI is a teammate*: security teams should treat AI as a teammate, not an enemy.
  5. *Comms is the staff skill*: security engineers avoid comms and politics, yet that skill separates senior from staff.
- **projects/rhino.md:** workflows as code, a mini Airflow in Go.
- **uses.md:** macOS, Warp, zsh, Zed, Chrome, 1Password, Claude Code (Desktop).
- **cv.md:** roles only, with no bullets, skills or education. Riot (2025–now), Worklife (2024–2025) and Checkout.com (2022–2024), all as Security Engineer.
