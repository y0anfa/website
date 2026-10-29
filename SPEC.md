# yoanfaure.com — v2 spec

The contract every contributor (human or agent) builds against. If code and spec disagree, fix one of them on purpose.

## 1. Intent

Personal site of **Yoan Faure, security engineer who builds** (Riot, Paris).
It shows who he is, what he thinks, and what he makes.

- **Audience:** security peers and curious strangers. Not recruiters.
- **Voice:** plain and precise. Short sentences, first person, no buzzwords, no exclamation marks, no emoji.
- **Style:** bold but simple. Little content, accessible information. Monochrome, set in Inter, with mono only for code and the log's metadata, and one signature moment (the ASCII field).
- **Language:** English.

## 2. Decisions

| Topic | Decision |
|---|---|
| Pages | The home (intro and log), one page per entry (essay, note or project), and the 404. There are no list pages (`/essays/`, `/notes/`, `/projects/`), no uses page and no cv page: the home log is the only list, and the career line lives in the home intro. No about page, no now page, no RSS, no colophon. |
| Home | One centred column: a compact, quiet intro (who, where, off-hours), then the log as the main content. No hero. (A split screen with the field on the left, and a "field is the nav" prototype, were tried and dropped at review.) |
| Feed | A "git log" list, the only list on the site. Essays, notes and projects share it. Each row is: real short commit hash (linked to GitHub), date, type, title. |
| URLs | Flat: every entry lives at `/<slug>/`, whatever its type. The content folder sets the type (a label in the log and in the entry's meta line), not the URL. Slugs are unique across all types. The old Hugo URLs are redirected (§4). |
| Signature | A quiet backdrop of topographic contour lines in ASCII, fixed behind every page: on the home it shows behind everything, on inner pages only in the side margins. (Water and wind presets were tried and dropped at review.) |
| Type | Inter (variable, self-hosted) for all text and UI. JetBrains Mono 400, self-hosted, only for code, the log's hash and date, and the backdrop field. |
| Color | Monochrome only. Light and dark follow the system, with a manual toggle. |
| Motion | The field moves, and pages change with a calm cross-document view transition: the clicked log title travels into the entry's heading, and back (§7, Transitions). Nothing else moves. `prefers-reduced-motion` gets a static field frame and no transitions. |
| Page transitions | One design, **the shared title**: the clicked log title travels to the entry's h1 and grows into it, and the h1 travels back into its row; the content around it rises 12px as it arrives, and going into an entry and coming back mirror each other. Two other prototypes, `slide` (the content slides sideways) and `sheet` (the entry is a sheet of paper over the still map), were tried at review and dropped, and so was the `?vt=` switch that compared them. A click on the side margins of an entry, or Escape, goes back to the log (§7). |
| Build | Hand-rolled static generator in Elixir: EEx templates, MDEx for Markdown, YamlElixir for frontmatter. |
| Hosting | Cloudflare Workers, assets-only, deployed by GitHub Actions with wrangler. |
| Analytics | Cloudflare Web Analytics with automatic setup: Cloudflare injects the beacon into the HTML at the edge, so the pages carry no beacon tag and no repo variable or token is needed. The CSP allows its two hosts, the single third-party exception. |
| Security | Strict CSP, no third-party assets, security headers via `_headers`, signed commits, deterministic build checked in CI. |
| Contact | `hi@yoanfaure.com` (Cloudflare Email Routing) and LinkedIn `https://linkedin.com/in/yoan-faure`. |
| Repo | `y0anfa/website` (formerly `y0anfa/yoanfau.re`), fresh orphan history on `main`. The old Hugo site is on `archive/hugo`. |
| Domains | `yoanfaure.com` serves the site. `yoanfau.re` and `www.yoanfaure.com` redirect to it (301, path kept). |

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
├── priv/og-fonts/             Inter-Bold.ttf, JetBrainsMono-Regular.ttf + OFL licences: build-only, for the share images (never copied to dist)
├── content/                   all words live here: home.md and essays/, notes/, projects/ (see §5)
├── assets/                    copied verbatim to dist/assets/
│   ├── css/site.css
│   ├── js/head.js             inlined into <head>; its sha256 goes in the CSP; applies the saved theme
│   ├── js/transitions.js      page transitions: direction, the shared title, the margin click and Escape (a deferred, render-blocking script on every page)
│   ├── js/theme.js            theme toggle (a cross-fade when view transitions are supported)
│   ├── js/field.js            the ASCII field (ES module)
│   ├── js/404.js              fills the missing path on the 404 page
│   ├── js/favicon.js          swaps the favicon to the sleeping one while the tab is hidden
│   ├── fonts/InterVariable.woff2, InterVariable-Italic.woff2 + Inter-OFL.txt
│   ├── fonts/JetBrainsMono-Regular.woff2 + JetBrainsMono-OFL.txt
│   ├── favicon.svg
│   └── favicon-sleep.svg      the same mark with a sleeping prompt (`>` and a z z)
├── lab/field.html             standalone playground for field.js (never built/deployed)
├── wrangler.jsonc             the site Worker (yoanfaure.com)
├── redirect/                  worker.js + wrangler.jsonc: 301s yoanfau.re and www to yoanfaure.com
├── .github/workflows/deploy.yml
└── dist/                      build output (gitignored)
```

## 4. URLs

| URL | Source | Template |
|---|---|---|
| `/` | `content/home.md` + every entry | `home.html.eex` |
| `/<slug>/` | one essay or note (`content/essays/*.md`, `content/notes/*.md`) | `article.html.eex` |
| `/<slug>/` | one project (`content/projects/*.md`) | `project.html.eex` |
| `/<slug>.md` | the Markdown twin of the same entry (see below) | `Site.Twin` |
| `/llms.txt` | an index of the twins, for language models | `Site.Llms` |
| `/404.html` | — | `404.html.eex` |

Every page is written as `<path>/index.html`. Slug = filename without `.md` and without a leading `YYYY-MM-DD-` prefix.
The content folder (`essays/`, `notes/`, `projects/`) sets the entry's type, not its URL: `content/essays/2026-03-28-threat-modeling-with-claude-code.md` is `/threat-modeling-with-claude-code/`, and `content/projects/rhino.md` is `/rhino/`. There are no `/essays/`, `/notes/`, `/projects/`, `/uses/` or `/cv/` pages.
Also emit `robots.txt` (allow all), `_headers` (§11) and `_redirects`. There is no sitemap and no feed.

**Markdown twins and `llms.txt`.** Every entry (essay, note, project) is also written as `dist/<slug>.md`, served at `/<slug>.md`, so a person or a model can read the words without the page. It is plain text built from the content, with no timestamps:

```
# <title>

<type> · <date> · https://yoanfaure.com/<slug>/

<the entry's original Markdown body, frontmatter stripped>
```

A project adds its tagline (as a `> ` quote) and a `link: <url>` line after the second line. Each entry page points at its twin with `<link rel="alternate" type="text/markdown" href="/<slug>.md">` in the `<head>`. Drafts have no twin.

`dist/llms.txt` follows [llmstxt.org](https://llmstxt.org): `# Yoan Faure`, a one-line `> ` summary (the home description), a short plain-text paragraph (the home intro), then `## Essays`, `## Projects` and `## Notes` (in that order, entries in log order, empty sections left out). Each entry is `- [Title](https://yoanfaure.com/<slug>.md): description`.

A `<slug>.md` cannot collide with a page or a site file: `llms` and `llms.txt` are reserved slugs (§5), as is every other site path. `_headers` (§11) gives the twins and `llms.txt` an explicit `Content-Type` (`text/markdown; charset=utf-8` and `text/plain; charset=utf-8`).

**Share images.** Every entry has a 1200×630 PNG at `dist/og/<slug>.png`, and the home has `dist/og/home.png` (`Site.OG`). Each page points at its own with `og:image` (absolute URL), `og:image:width` 1200, `og:image:height` 630 and `og:image:alt` (the page title); `twitter:card` is `summary_large_image`. The 404 has no image and keeps `twitter:card=summary`. An image is drawn as an SVG in the light palette (§8) and rasterised at build time by `resvg`:

- Background: a few faint topographic contour lines in `--rule`, in the spirit of the site's backdrop. A smooth height field (three octaves of value noise plus one round hill) is seeded from the slug by SHA-256, contoured with marching squares, and written as smoothed SVG paths. Index lines (every fourth) are slightly heavier.
- An entry: a mono (JetBrains Mono) kicker `essay · 2026-03-28` in `--muted`, then the title in Inter Bold, `--fg`, -0.02em, left-aligned. The title takes the largest of 96, 84, 72, 62 and 54px that fits in three lines (lines balanced); past three lines at 54px it ends with `…`. `Yoan Faure` bottom-left (Inter Bold), `yoanfaure.com` bottom-right (mono, `--muted`).
- The home: the name from `home.md` large (152px), the tagline under it in `--muted`, and `yoanfaure.com` bottom-left.
- Text is measured from the font files' glyph advances (`Site.OG.Text`, no kerning, so lines are never too wide) and a character the font lacks is dropped, never drawn as a box.
- Fonts: only `priv/og-fonts/Inter-Bold.ttf` and `JetBrainsMono-Regular.ttf` (resvg cannot read WOFF2), loaded with `skip_system_fonts`, so no system font ever changes an image. They sit outside `assets/` because the build uses them and the site does not publish them.
- Deterministic: no timestamps and no random state, and the PNG has only `IHDR`, `IDAT` and `IEND` chunks, so `mix site.verify` covers the images too. They are not cached between builds, so that it does.

**`_redirects`** sends the old Hugo URLs to the flat ones. It is written to `dist/_redirects` (Cloudflare Workers static assets read it from the assets directory), is the same on every build, and is generated from `Site.Config.redirects/0`:

```
/blog/* /:splat 301
/projects/* /:splat 301
/resume/ / 301
/resume / 301
```

The old essay at `/blog/threat-modeling-with-claude-code/` now lands on `/threat-modeling-with-claude-code/`. `mix site.serve` does not apply redirects.

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

**home.md**
```yaml
title: string
description: string
tagline: string      # optional; rendered under the h1
```

Raw HTML in Markdown is **not** rendered: MDEx runs with `unsafe: false`. Use GFM extensions: tables, strikethrough, autolink, footnotes, and heading ids. There is no syntax colouring; code blocks are plain monochrome `<pre><code>`.

**Stat callouts.** A fenced code block with the info string `stats` is a row of big numbers, one `value | label` per line:

````
```stats
91% | only read or react
0%  | chose "I comment"
82  | respondents
```
````

`Site.Markdown` post-processes MDEx's HTML: `<pre><code class="language-stats">` becomes `<dl class="stats"><div><dt>91%</dt><dd>only read or react</dd></div>…</dl>`. Values and labels are trimmed, split at the first `|`, and stay HTML-escaped exactly as MDEx wrote them (a `<script>` in a label is text, never markup). If any non-blank line has no `|`, or an empty value or label, or the block is empty, the whole block stays a plain code block, so a typo is visible instead of silently dropped. Only the exact info string `stats` counts. In `site.css`, `.stats` is a grid of `repeat(auto-fit, minmax(8.5rem, 1fr))`: up to four columns in the reading column, two on a phone (an odd last item takes the full row). Each cell has a `--rule` hairline on top, the `dl` one underneath. The value (`dt`) is Inter 700 at `clamp(2.25rem, 1.8rem + 1.6vw, 2.75rem)`, -0.03em, line-height 1. The label (`dd`) is 0.875rem in `--muted`. Monochrome, set in Inter.

**Slugs.** Every entry lives at `/<slug>/`, so a slug may be used once across **all** types: an essay and a note cannot share one. A skipped draft does not count. Some slugs are reserved because `/<slug>/` would collide with a site path or be taken over by a legacy redirect: `assets`, `404`, `404.html`, `home`, `index`, `index.html`, `llms`, `llms.txt`, `og`, `robots.txt`, `_headers`, `_redirects`, `blog`, `projects` and `resume` (`Site.Config.reserved_slugs/0`; the last three come from the redirects in §4).

The build fails loudly on a missing required field, a bad date, a duplicate slug (naming every file that uses it, for example `essays/same.md, notes/same.md`), or a reserved slug (naming the file).

## 6. The log

Entries are essays, notes, and projects, and the log on the home is the only list. Sort by date desc, then type (essay, project, note), then title asc.

```
9f19333  2026-10-28  note     Build the small tool
a3f9c21  2026-03-28  essay    Threat modeling with Claude Code
```

- **hash:** the first 7 characters of `git log -1 --format=%H -- <file>`. It links to `https://github.com/y0anfa/website/commit/<full sha>`. An untracked or uncommitted file, or no git at all, shows `·······` (7 middle dots) with no link.
- **date:** `YYYY-MM-DD`. **type:** `essay` / `note` / `project`, the label for the folder the entry lives in. **title:** links to the entry at `/<slug>/`.
- **Markup:** `<ol class="log">` > `<li class="log-row">` > `<a class="log-hash">`, `<time class="log-date">`, `<span class="log-type">`, `<a class="log-title">` (the title the `title` transition moves, §7).
- **Fonts:** the hash and the date are JetBrains Mono (`.log-hash`, `.log-date`, at 0.8em, muted). The type and the title are Inter: the type is muted and regular, the title is 600 weight.
- **Layout:** a CSS grid: `max-content max-content 3.75em 1fr`. The mono cells are `7ch` and `10ch` wide, in their own font, so the two mono columns line up in every row whatever the row's font; the sans type gets a fixed track in `em`. Under ~600px it becomes two lines: hash and date, then type and title (a `4em` first track, so the title stays aligned with the date).
- There are no list pages: the log appears on the home only.

## 7. Layout and pages

**Global shell**
- A skip link to `#main`.
- Immediately after it, on every page, the field backdrop root (field.js depends on it; see §9):

```html
<div class="field" data-field-root aria-hidden="true"><canvas class="field-canvas"></canvas></div>
```

- `header.site-header`: `a.brand` "yoan faure", linking home, on the left; `button.theme-toggle` (aria-label "Toggle theme") on the right. There is no nav: no `nav` element, no links to sections, no `aria-current`.
- `main#main`.
- `footer.site-footer`: `hi@yoanfaure.com · linkedin` on the left; `built from <a>a3f9c21</a>` on the right, linking to the HEAD commit (`-dirty` suffix if the tree is dirty, `unversioned` with no git).
- `<title>`: `<Page> — Yoan Faure` (home: `Yoan Faure — security engineer who builds`). Also meta description, canonical, `og:title/description/url/type`, `og:image` with its width, height and alt, and `twitter:card` (`summary_large_image`; the 404 has no image and keeps `summary`; share images, §4), favicon, and a preload for the Inter variable font (`/assets/fonts/InterVariable.woff2`, with `crossorigin`). An entry page also has `<link rel="alternate" type="text/markdown" href="/<slug>.md">` (§4).
- `<html lang="en">`. The inline head script (`assets/js/head.js`) applies `localStorage.theme` (`light` / `dark`) to `data-theme` before first paint, and does nothing else. One stylesheet is linked, `/assets/css/site.css`.
- A second inline script, `<script type="speculationrules">`, is in every page's `<head>`. Its text is the constant in `Site.Speculation`: prerender same-origin page links (`href_matches: "/*"`) with `eagerness: "moderate"` (a hover or focus hint), except `/*.md`, `/llms.txt`, `/assets/*` and any link with `rel~=nofollow`. The CSP allows it by its sha256 (§11). Browsers without Speculation Rules ignore it.
- `<script defer blocking="render" src="/assets/js/transitions.js">` is in every page's `<head>`, from the shared layout, before the field. It is deferred, and render-blocking so that its `pagereveal` listener exists before the first frame of a new page is shown.
- `<script type="module" src="/assets/js/field.js">` is loaded on every page, from the shared layout. `theme.js` and `favicon.js` (and `404.js` on the 404) are plain `defer` scripts.
- **Favicon.** `assets/favicon.svg` is the mark: a 32×32 rounded square with a `>_` prompt, light and dark by media query. `assets/favicon-sleep.svg` is the same square with a sleeping prompt: the `>` and a small z z, drawn with paths only. `favicon.js` swaps the `link[rel=icon]` href to the sleeping one when the tab becomes hidden (`visibilitychange`) and back when it is visible. It touches no markup.

**Backdrop and column**
- The field is a fixed, full-viewport layer behind the page (`z-index: 0`, no pointer events). The skip link, header, main and footer sit above it (`position: relative; z-index: 1`).
- Header, main and footer share one centred column on every page, so their edges line up and the brand never moves: 38rem of text plus gutters. In rem, not `ch`, because the footer has a smaller font.
- **Home:** the column is transparent. The field shows behind everything, and text carries a soft halo of the background colour so a line of the field never cuts through a word.
- **Inner pages** (entries, 404): the header, main and footer are painted with `var(--bg)` and have 1px `--rule` edges on both sides. The column reads as plain paper and the field shows only in the side margins. When the viewport is no wider than the column, the field is not visible at all.

**Home**
- DOM contract (the layout supplies the backdrop; the home has no hero and no field section):

```html
<div class="intro"> h1 "Yoan Faure" + p.tagline + rendered home.md + p.contact </div>
<section class="log-section" aria-labelledby="log-h"> <h2 id="log-h">log</h2> <ol class="log">…</ol> </section>
```

- **Layout:** one centred column on every viewport.
  - The intro is compact and quiet. The name stays the page's `<h1>` but is modest (1.5rem, no display heading). The tagline is 1.0625rem at 600 weight; the intro text and the contact line are 0.9375rem in `--muted`, at most 38rem wide. The intro text is three short paragraphs: who I am, the career line (`At Riot in Paris since 2025. Before: Worklife, Checkout.com.`, which replaces the cv page) and the off-hours line.
  - The log is the dominant element, at 1.125rem with about 0.95rem of padding above and below each row. Its grid is the one in §6, so under ~600px each row is still two lines. This is the only list on the site.

**Entries** are a centred reading column. The page column is 38rem of text (about 68 characters of Inter). The opaque "paper" column stays, so the field shows only in the side margins; the header and footer align to the same column.
- **Article (essay, note):** `article.prose`. A small, muted meta line `essay · 2026-03-28 · <hash link>` (0.875rem) above the h1, then h1, then the body, then a `← log` back link to `/`. The body is 1.125rem with line-height 1.7, paragraphs 1.35em apart, h2 at 1.5rem with 2.75rem above it. Lists use plain markers, tables are ruled, and code is mono (`pre` 0.875rem).
- **Project:** `article.prose.project`. h1, tagline, a meta line `status · stack · link`, then the body and the same `← log` back link.
- **Entry links (article and project).** Under the body, one quiet row (`div.entry-end`, on the back link's hairline): the `← log` back link on the left, and on the right, in 0.875rem muted lowercase, `markdown` and `ask claude ↗` (`p.entry-links`, separated by ` · `).
  - `markdown` links to `/<slug>.md`, the entry's twin (§4).
  - `ask claude ↗` links to `https://claude.ai/new?q=<prompt>`, with `rel="noopener"`, no `target` (same tab). The prompt is `Read https://yoanfaure.com/<slug>/ by Yoan Faure, a security engineer. Using only what is on that page, summarize the main argument in a few sentences, then tell me where you would push back.` For a project, the end is `summarize what the project does and why, then suggest one improvement.`
  - The prompt is URI-encoded (everything but unreserved characters, so a space is `%20`) in `Site.View.ask_url/1`, then HTML-escaped as an attribute by the template.

**404:** two `<pre>` lines (so they are mono): `zsh: no such file or directory: <span data-path></span>`, then `% cd ~` with `cd ~` linking home. `404.js` fills `data-path` via `textContent`.

**Back to the log from the margins.** On an entry page (essay, note or project), a click on the side margins, where the field shows, goes back to the log, and so does `Escape`. The `← log` link stays. Both are in `transitions.js`, which only registers them on those pages (`body[data-page]` is `essay`, `note` or `project`):

- *Where.* The margin is the `body` (or `html`) itself: the paper (header, main and footer) is its child and the field has no pointer events. The press (`pointerdown`, primary button) and the click must both be on the margin, so the end of a text selection that began on the paper does not count. Links, buttons, a text selection, a click with a modifier key or a non-primary button, and a coarse pointer (`(pointer: fine)` is false) are all left alone.
- *Which way.* If the page before this one in the session history, past any `#hash` hops on this page, is the home (`navigation.entries()`), it steps back to it with `history.go(-n)`, so the home keeps its scroll position and the back transition plays. Otherwise it navigates to `/`. Without the Navigation API it uses `document.referrer` and `history.length`, and a `#hash` on the page sends it to `/`.
- *Escape.* The same, unless it has a modifier, comes from a form field or `contenteditable`, was prevented, or is part of an input method.
- *Affordance.* In `site.css`, inside `@media (pointer: fine)`, `body:is([data-page="essay"], [data-page="note"], [data-page="project"])` has `cursor: zoom-out`, and `.site-header, main, .site-footer` inside it have `cursor: auto`, so the margins show the zoom-out and the paper keeps the normal cursor. The home and the 404 are not touched, and a phone has no margins.

**Transitions.** Pages change with cross-document view transitions. The motion is CSS (`site.css`); a small script (`transitions.js`) says which way a navigation goes and which element is the shared title.

- *Opt-in.* `@view-transition { navigation: auto; }` inside `prefers-reduced-motion: no-preference`, and `navigation: none` inside `reduce` (the two queries never match together, so which rule wins does not matter): a reduced-motion visitor gets no navigation transition at all. A browser without support (Firefox) navigates instantly.
- *Direction.* `transitions.js` listens to `pageswap` (old page) and `pagereveal` (new page; it also fires for a page restored from the back/forward cache or activated from a prerender, so the speculation rules of §7 still transition) and adds a view transition type from the two URLs (`navigation.activation`): `forward` for home to an entry, `back` for an entry to the home, whatever started it (a link, the back button, the brand link, the margin click). The old page also gets the type `leaving` and the new page `arriving` (`pageswap` adds the first, `pagereveal` the second). Every other navigation gets no type and the browser's own cross-fade. The CSS keys on `:active-view-transition-type(forward)` and `(back)` (and `arriving`), with no attribute on the root; the theme toggle's type `theme` never matches them.
- *Names.* Everything that styles a transition waits for a type. The content that moves is named by the CSS, and only on the page that arrives (type `arriving`): `home-intro` and `home-log` on the home, `entry-body` on an entry. The home's and an entry's names differ, so a group never pairs a page with itself. The old page names nothing: its content stays in its root image, which is only as big as the viewport (see *White frames*). The field, the header, the footer and the column's paper have no name either: they stay in the root image, and nothing that moves is in it, so they never move or flash. (Naming them was rejected: a named footer is drawn at its new position for both images, and pops when the old page's footer was on screen and the new page's is not.) The root image is not cross-faded: the old one stays as it is and the new one fades in over it in the time of an exit (`--vt-exit`, accelerating), which is also how the old page's content leaves. Both are opaque and blend normally, so the two never add up and the header and footer text never dip. The field is part of that fade; each page seeds its own map, so the old contours give way to new ones.
- *The shared title.* At most one element per page carries `view-transition-name: entry-title` at a time, written through the CSSOM (`el.style.setProperty`, which the CSP allows). Going in, `pageswap` names the clicked row's title link (the one whose `href` is the destination) and `pagereveal` names the h1. Coming back, `pageswap` names the h1 and `pagereveal` finds the row whose link is the entry we came from, scrolls it into view with `block: "nearest"` if it is not (the old image covers the jump) and names it. A title that is not fully on screen, or a row that is not there, is not named, and the other side then treats its title as ordinary content (`:only-child`). The names are cleared when `viewTransition.finished` settles, when `pageswap` starts, and when a page is restored from the cache.
- *Timing, in tokens on `:root`.* `--vt-enter: 400ms` with `cubic-bezier(0.2, 0, 0, 1)` (emphasized decelerate), `--vt-exit: 160ms` (40%) with `cubic-bezier(0.3, 0, 0.8, 0.15)` (emphasized accelerate), and `--vt-stagger: 70ms` before the new content starts. A new image uses `vt-in` (from 12px lower and transparent to its place and full opacity); an old image only fades (`vt-fade-out`) and is never moved or scaled. Only opacity and one 12px translation are used, with normal blending: no bounce, blur, scale or colour. The theme toggle keeps `--vt-duration: 200ms` and `--vt-ease: ease-out`.

- **The motion.** The clicked log title travels to the h1's position and grows into it, the old content fades out and the new content rises 12px and fades in after the stagger. Back: the h1 travels into its row and the log fades back in. The shared title's old and new images fill their group and scale together from its top left corner (`object-fit: contain`), so the text is only ever scaled, never stretched, and the last frame is the real h1 at its own size. The row and the heading are not the same picture (one line at 1.125rem against one or more lines at up to 2.5rem), so going in the row fades out in the first quarter and the heading arrives as that ends (coming back, the mirror image). The title carries a halo of the paper colour while it crosses the content that is fading in, so the lines beneath do not show through; it cannot be seen once the title has landed. The log title and the h1 are as wide as their text, and a hovered log title is captured as plain text rather than an inverted bar.
- **Dropped.** Two other prototypes were built and compared with `?vt=title|slide|sheet` (a few lines in `head.js` and a `data-vt` on the root, both gone now): `slide`, where the new content came in 28px from the side we were going to and the old faded in place, and `sheet`, where the entry was a sheet of paper that rose 24px over the still field. The shared title won. Nothing of the losers is left: no CSS, no custom properties or keyframes for them, no `sessionStorage` key.
- **Theme toggle.** `theme.js` calls `document.startViewTransition({ update, types: ['theme'] })` when it exists and `prefers-reduced-motion` is not `reduce`, and otherwise switches at once (an engine that only knows the callback form throws on the options object and falls back to the same). The result is one soft cross-fade of the whole page, `--vt-duration`, `--vt-ease`. A second click before the first update still toggles back, and a skipped transition is not an error.
- **White frames.** Coming back to the log showed a white frame, in every prototype that was tried. What was found, and what keeps each out:
  - *Reproduced.* The old page's content was named, so its old image was one picture as tall as the page (an essay is several thousand pixels), animated with opacity (and, in the two dropped prototypes, a transform). The browser fails to draw a picture that large that way and the whole frame comes out white; going into an entry the old picture is the short home, which is why only the way back showed it. Only the arriving page names its content now, which is a live element and not a picture, and the old page stays in its root image; an old image only fades and is never moved or scaled.
  - *Measured.* Both root images were blended with `plus-lighter` as a rule, and the computed styles at `pagereveal` (before the first animation tick) gave the old and the new image both full opacity, which adds up to white; the arriving content was visible in the same way. There is no `plus-lighter` anywhere now, and every image that arrives is hidden (`opacity: 0`) in the rule itself, so a frame before the animations start is the old page and nothing else.
  - *Hardening.* `html` was transparent (only `body` had the page colour) and `::view-transition` had its background only under a type, so anything transparent could show the browser's white canvas. `html` now has `background: var(--bg)` and `::view-transition` has it unscoped, for every transition, the theme toggle's included.
  - *Empty field.* A revealed home showed no field for its first frames (the field waited for the fonts, a few ticks later than the reveal): see §9.
- **Skipped transitions.** A browser skips a view transition when the document is hidden (a background tab, or a page that is not being composited), and cancels it when the new page is not revealed in time or two elements carry the same name. A skip is silent and the navigation still works: `transitions.js` never throws or logs on one, and its names are cleared whatever the outcome.

## 8. Visual system

```css
/* light (default when system is light) */
--bg: #f4efe4;  --fg: #262523;  --muted: #6b675f;  --rule: #ddd6c8;
/* dark */
--bg: #1e1d1b;  --fg: #ece6d9;  --muted: #9a958b;  --rule: #34322f;
```

- **Theming:** no `data-theme` means follow `prefers-color-scheme`; `[data-theme=light|dark]` forces it. `theme.js` toggles the effective theme and stores it in `localStorage`, inside a 200ms whole-page cross-fade when view transitions are supported (§7, Transitions).
- **Fonts:** Inter as a variable font (`InterVariable.woff2` and `InterVariable-Italic.woff2`, `font-weight: 100 900`) and JetBrains Mono 400 only (`JetBrainsMono-Regular.woff2`), all `font-display: swap`, all self-hosted with their OFL licences in `assets/fonts/`. The tokens:

  ```css
  --font-sans: "Inter", system-ui, -apple-system, "Segoe UI", Roboto, sans-serif;
  --font-mono: "JetBrains Mono", ui-monospace, "SF Mono", Menlo, monospace;
  ```

- **Where mono is allowed.** The body and all prose and UI use the sans. Mono is used only for `code`/`pre`/`kbd`, for the log's hash and date (`.log-hash`, `.log-date`, wherever the log appears), and for the backdrop field. `.field` sets `font-family: var(--font-mono)` itself, because field.js builds its character grid from the field root's computed font (§9) and would otherwise inherit the sans. The type label, the title, the meta line and the footer are sans. A test pins this list.
- **Type scale:** the root is 16px (17px at ≥ 960px). Body is 1rem with line-height 1.6; the entry body is 1.125rem with line-height 1.7. Headings are 700 weight with slightly negative tracking (-0.02em, h1 -0.03em). h1 is `clamp(1.875rem, 1.3rem + 2.2vw, 2.5rem)`, except the home name, which is a modest 1.5rem. Bold text and table heads are 650, the log title and the project tagline 600. Monochrome, bold but simple.
- **Links:** `color: inherit`, 1px underline with 0.2em offset. Hover and focus invert (`background: var(--fg); color: var(--bg)`). Focus-visible gets a 2px solid outline in `--fg`. Selection inverts.
- **Rules:** 1px `--rule`. Generous whitespace, lowercase UI labels, and nothing decorative except the field.
- **Layering:** the field (`z-index: 0`) sits behind header, main and footer (`z-index: 1`). Inner pages paint an opaque `var(--bg)` column over it, with `--rule` hairline edges; the home paints nothing. See §7.
- **Contrast:** `--muted` must keep ≥ 4.5:1 against `--bg` in both themes.

## 9. The backdrop field (`assets/js/field.js`)

A quiet, fixed, full-viewport layer behind every page: a watermark you notice after a few seconds, never competing with the text. An ES module with no dependencies and no `innerHTML`/`eval`. It exports `mountField(root)` and auto-mounts every `[data-field-root]`.

- **DOM:** `<div class="field" data-field-root aria-hidden="true"><canvas class="field-canvas"></canvas></div>` right after the skip link in the layout. `.field` is `position: fixed; inset: 0; z-index: 0; pointer-events: none` and sets `font-family: var(--font-mono)`, 14px. Header, main and footer sit above it. Inner pages paint their column opaque, so the field shows only in the margins.
- **Rendering:** a canvas sized to the root (ResizeObserver plus a window resize fallback), DPR-aware (capped at 2). Cell metrics come from the root's computed mono font; the cell height is 1.1em so line glyphs join. A pre-rendered glyph atlas is tinted with the root's computed `color` and rebuilt on theme change (MutationObserver on `<html>` `data-theme`, plus the `prefers-color-scheme` change event). Only changed cells are redrawn.
- **Topo:** topographic contour lines, like a retro survey map. The terrain is 3 octaves of 2D gradient noise pinned to viewport pixels, with slowly rotating gradients, so contours drift a few pixels per second and never jitter. A cell is lit when it sits within half a cell's gradient of a contour level, which gives thin, connected lines (about 7% of cells). Glyphs follow the line direction: `-`, `|`, `/`, `\`. Every 5th level is an index contour, drawn stronger. The pointer slowly raises a wide Gaussian hill (rises over ~1 s, relaxes over ~3 s), so the lines flow around it. 20 fps.
- **Alpha:** watermark level. Contours 0.13–0.17, index contours 0.26–0.32, scaled ×0.88 on dark.
- **Budget:** under 4 ms per frame on large screens (measured about 1 ms at 2560×1440, DPR 2). Pauses when the document is hidden.
- **Accessibility:** the root is `aria-hidden`. Under `prefers-reduced-motion: reduce`, it renders one static frame (a still map) with no loop and no pointer effects, re-rendered on resize and theme change.
- **CSP-safe:** sizing only via CSSOM (`canvas.style.width = …`), never `setAttribute('style')` and never inline `<style>`.
- **First frame:** the field draws its first frame as soon as it can, so a page that is revealed never shows an empty field. When the font is already usable (`document.fonts.check`) that is synchronous, in the module, whether or not the document is visible or prerendered; otherwise it waits for the font as before (up to 2.5s), but never past a prerendered page being activated (`prerenderingchange`) or the document becoming visible, and the atlas is rebuilt when the font arrives.
- **Page transitions:** the field has no `view-transition-name`; it stays in the root image, which only dissolves, so it never moves with the content (§7, Transitions).
- **Playground:** `lab/field.html` shows the backdrop behind a fake log and an "inner page" column, with theme and reduced-motion switches.

## 10. Build (Elixir)

- **Mix project `:site`.** Deps pinned in `mix.lock`:
  - `mdex`, `yaml_elixir` and `resvg` (runtime). `resvg` is a Rust NIF with precompiled binaries (macOS arm64, Linux x86_64 GNU), fetched on first compile like MDEx's; it rasterises the share images (§4) and pins `rustler_precompiled` to 0.8.x;
  - `bandit` and `plug`, `only: :dev`, for the dev server.
  - Nothing else.
- **`mix site.build [--drafts] [--content DIR] [--out DIR]`:**
  1. Clean the output.
  2. Load and validate content.
  3. Read git info (`System.cmd("git", …)`).
  4. Render the EEx templates. **EEx does not escape:** every interpolated string goes through `Site.HTML.escape/1`, and only rendered Markdown is inserted raw.
  5. Copy `assets/` to `dist/assets/` as is (no fingerprinting).
  6. Inline `assets/js/head.js` (trimmed) into `<head>` and compute its `sha256-…` for the CSP. Compute the `sha256-…` of the speculation rules (`Site.Speculation.rules/0`) too.
  7. Write `_headers` (§11), `_redirects` (§4), `robots.txt`, `404.html`, the Markdown twin of every entry, `llms.txt` and the share images in `og/` (§4).
- **Deterministic:** no build timestamps; sorted iteration everywhere; identical output for identical commit and env.
- **`mix site.verify`:** builds twice into temporary dirs, compares a SHA-256 over every file path and content, fails on mismatch, and prints the tree hash.
- **`mix site.serve [--port 4000]`:** builds, serves `dist/` with Bandit and Plug, and applies the headers parsed from `dist/_headers`, so CSP violations show up locally exactly as in production. It polls `content/`, `templates/`, `assets/` and `lib/` mtimes every second and rebuilds on change (no file_system dep). Missing paths serve `404.html` with status 404, and `/x/` serves `/x/index.html`.
- **Tests:** frontmatter parsing and validation, flat URLs, slugs (global uniqueness and reserved slugs), `_redirects`, escaping, log ordering, no nav and no list pages, the font and mono-only CSS rules, CSP hashes (head.js and the speculation rules), the Markdown twins and `llms.txt`, the entry links and their escaping, the favicon pair and its script, the share images (size, no metadata chunks, determinism, text wrapping, contours, meta tags), the `stats` callouts (rendering, escaping, CSS), the page transitions (`transitions.js` loaded on every page, the old generated stylesheet and `vt-<slug>` classes gone, the CSS opt-in and its reduced-motion opt-out, the `forward` and `back` rules, the timing tokens and the small-motion limits, no `data-vt`, `?vt=`, `slide`, `sheet` or `sessionStorage` left anywhere, the zoom-out margin rule scoped to entry pages and `pointer: fine`, the CSP's two hashes, and `head.js`, `theme.js` and `transitions.js` run under node with stubs when `node` is installed), and a determinism smoke test, all using `test/fixtures/content`.

## 11. Security headers (`dist/_headers`)

```
/*
  Content-Security-Policy: default-src 'none'; script-src 'self' '<head.js sha256>' '<speculation rules sha256>' https://static.cloudflareinsights.com; style-src 'self'; img-src 'self'; font-src 'self'; connect-src 'self' https://cloudflareinsights.com; manifest-src 'self'; base-uri 'none'; form-action 'none'; frame-ancestors 'none'; upgrade-insecure-requests
  Strict-Transport-Security: max-age=63072000; includeSubDomains
  X-Content-Type-Options: nosniff
  X-Frame-Options: DENY
  Referrer-Policy: strict-origin-when-cross-origin
  Permissions-Policy: accelerometer=(), camera=(), geolocation=(), gyroscope=(), magnetometer=(), microphone=(), payment=(), usb=()
  Cross-Origin-Opener-Policy: same-origin
  Cross-Origin-Resource-Policy: same-origin
/*.md
  Content-Type: text/markdown; charset=utf-8
/llms.txt
  Content-Type: text/plain; charset=utf-8
/assets/fonts/*
  Cache-Control: public, max-age=31536000, immutable
```

**Two inline scripts, two hashes.** `script-src` carries exactly two `sha256-…` sources: `assets/js/head.js` and the Speculation Rules (`<script type="speculationrules">`, §7). The build hashes the exact text of each, so the same JSON always gives the same hash, and `'inline-speculation-rules'` is not used. A change to either script changes its hash in the same build.

**Content-Type.** The Cloudflare Workers static assets docs say the defaults it sends, `Content-Type` included, can be overridden by a `_headers` rule ("Headers defined in the `_headers` file override what Cloudflare ordinarily sends"), so the `.md` and `llms.txt` rules pin the types. `mix site.serve` applies them too, and falls back to the file extension's type for everything else. If a deploy ever shows a duplicated or wrong `Content-Type`, delete those two rules and Cloudflare's own types apply.

The two Cloudflare hosts are always in the CSP, because Web Analytics runs on automatic setup: Cloudflare injects `<script defer src="https://static.cloudflareinsights.com/beacon.min.js" data-cf-beacon='{"token":"…"}'></script>` into the HTML at the edge. The build never writes that tag, so no built page contains `beacon.min.js` or `data-cf-beacon`.
The `/assets/fonts/*` rule covers every font file, so it lists no filenames. `dist/_redirects` (§4) sits next to `_headers`; Cloudflare reads both from the assets directory, and the build writes both.
The page transitions need no CSP change: `transitions.js` is a same-origin script, the names come from `site.css` or are written through the CSSOM (not an inline style attribute), and `style-src` stays `'self'`.
**Never** use inline `style=""` attributes, inline `<style>`, inline event handlers, or any inline script other than head.js and the speculation rules.

## 12. Hosting and deploy

- **`wrangler.jsonc`:** an assets-only Worker named `yoanfaure` with `assets.directory: ./dist`, `not_found_handling: "404-page"` and `html_handling: "auto-trailing-slash"`. `yoanfaure.com` is its custom domain (`routes`), so Cloudflare owns the apex record and certificate.
- **`redirect/`:** a script Worker named `yoanfau-re` (the old site Worker's name, so `yoanfau.re` stays attached) with custom domains `yoanfau.re` and `www.yoanfaure.com`. It answers every request with a 301 to the same path and query on `https://yoanfaure.com`, plus HSTS. Old Hugo paths then resolve through the site's `_redirects`. `www.yoanfau.re` reaches it through a Redirect Rule to the `yoanfau.re` apex.
- **`.github/workflows/deploy.yml`** runs on push to `main` and on `workflow_dispatch`, with least-privilege permissions. **Every third-party action is pinned to a full commit SHA** with a `# vX.Y.Z` comment.
  - The **build** job: checkout with `fetch-depth: 0` (needed for per-file hashes), then `erlef/setup-beam` with `version-file: .tool-versions` and `version-type: strict`, a deps cache, `mix format --check-formatted`, `mix test`, `MIX_ENV=prod mix site.verify`, and `MIX_ENV=prod mix site.build`. It uploads `dist`.
  - The **deploy** job (only on `main`) runs `cloudflare/wrangler-action` with secrets `CLOUDFLARE_API_TOKEN` and `CLOUDFLARE_ACCOUNT_ID`: the site first, then `deploy --config redirect/wrangler.jsonc`, so the old domain only redirects once the new one serves. The token must cover both zones.
- **Owner steps still open** (README, Domains): Always Use HTTPS and no Email Address Obfuscation on `yoanfaure.com`, Email Routing for `hi@`, and DNSSEC on both zones. Mail for `@yoanfau.re` stays on OVH.

## 13. Launch content

All drafts are Yoan's to edit. Everything is dated at launch (2026-10-28) unless noted.

- **home.md:** the intro (see `content/home.md`): the first paragraph, then the career line `At Riot in Paris since 2025. Before: Worklife, Checkout.com.` (which replaces the cv page), then the off-hours line.
- **essays/2026-03-28-threat-modeling-with-claude-code.md:** migrated verbatim from `archive/hugo`. It is at `/threat-modeling-with-claude-code/`; its old URL `/blog/threat-modeling-with-claude-code/` is redirected.
- **Notes**, one idea each, 120–300 words:
  1. *Build the small tool*: a lightweight, fine-tuned tool beats expensive complex software.
  2. *Security should unleash*: security exists to unleash engineering and the business, not to gate them.
  3. *Security pays in more than one currency*: risk reduction, business enablement, human time.
  4. *AI is a teammate*: security teams should treat AI as a teammate, not an enemy.
  5. *Comms is the staff skill*: security engineers avoid comms and politics, yet that skill separates senior from staff.
- **projects/rhino.md:** workflows as code, a mini Airflow in Go. At `/rhino/`.
- **Dropped at review:** the uses page and the cv page. The career line is in the home intro; the tools list is gone.

The launch log therefore has seven entries: one essay, five notes and one project.
