# yoanfaure.com — v2 spec

The contract every contributor (human or agent) builds against. If code and spec disagree, fix one of them on purpose.

## 1. Intent

Personal site of **Yoan Faure, security engineer at Riot** (Paris).
It shows who he is, what he thinks, and what he makes.

- **Audience:** security peers and curious strangers. Not recruiters.
- **Voice:** plain and precise. Short sentences, first person, no buzzwords, no exclamation marks, no emoji.
- **Style:** bold but simple. Dark graphite and one warm lamp, set in Inter. Little content: the home is the name, the position and the entries, and nothing else.
- **Language:** English.

## 2. Decisions

| Topic | Decision |
|---|---|
| Pages | The home (name, position, timeline), one page per entry (essay, note or project), and the 404. There are no list pages (`/essays/`, `/notes/`, `/projects/`), no uses page, no cv page, no about page, no now page, no RSS, no colophon. |
| Home | One poster: the name and the position on the left, the timeline on the right (stacked on a phone). No intro text, no contact line, no footer. |
| Timeline | The only list on the site. Essays, notes and projects share it, newest first, on a vertical axis under the year. Each entry is a date, a title, and a short description shown only on the entry that is lit, hovered or focused. A project with a `link` goes straight to it. The type is not shown anywhere. |
| URLs | Flat: every entry lives at `/<slug>/`, whatever its type. The content folder sets the type (which only orders the timeline and picks the project template), not the URL. Slugs are unique across all types. The old Hugo URLs are redirected (§4). |
| Signature | The light: a warm glow that follows the pointer over the home, rides the timeline, lights the entry it reaches and rakes across the name. A scan line crosses the axis while the pointer is on the timeline. The name decrypts once a visit. |
| Type | Inter (variable, self-hosted, with its optical-size axis) for all text and UI. JetBrains Mono 400, self-hosted, only for code. |
| Color | Graphite and one warm lamp colour. Dark first, light as well: both follow the system, with a manual toggle. |
| Motion | The light, the home's entrance, and the shared-title view transition between the home and an entry (§7). `prefers-reduced-motion` gets none of it: no decrypt, no light, no entrance, no navigation transition. |
| Page transitions | **The shared title**: the clicked title lifts off the axis and grows into the entry's h1, and settles back on its row on the way home; the content around it rises 12px as it arrives. A click on the side margins of an entry, or Escape, goes back home (§7). |
| Build | Hand-rolled static generator in Elixir: EEx templates, MDEx for Markdown, YamlElixir for frontmatter. |
| Hosting | Cloudflare Workers, assets-only, deployed by GitHub Actions with wrangler. |
| Analytics | Cloudflare Web Analytics with automatic setup: Cloudflare injects the beacon into the HTML at the edge, so the pages carry no beacon tag and no repo variable or token is needed. The CSP allows its two hosts, the single third-party exception. |
| Security | Strict CSP, no third-party assets, security headers via `_headers`, signed commits, deterministic build checked in CI. |
| Contact | Not on the site. `hi@yoanfaure.com` (Cloudflare Email Routing) still receives mail. |
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
├── priv/og-fonts/             Inter-Bold.ttf + OFL licence: build-only, for the share images (never copied to dist)
├── content/                   all words live here: home.md and essays/, notes/, projects/ (see §5)
├── assets/                    copied verbatim to dist/assets/
│   ├── css/site.css
│   ├── js/head.js             inlined into <head>; its sha256 goes in the CSP; applies the saved theme
│   ├── js/site.js             the theme toggle, the page transitions, the home's light, decrypt and entrance, the margins and Escape (a deferred, render-blocking script on every page)
│   ├── js/404.js              fills the missing path on the 404 page
│   ├── js/favicon.js          swaps the favicon to the sleeping one while the tab is hidden
│   ├── fonts/InterVariable.woff2, InterVariable-Italic.woff2 + Inter-OFL.txt
│   ├── fonts/JetBrainsMono-Regular.woff2 + JetBrainsMono-OFL.txt
│   ├── favicon.svg            the mark: the timeline's axis and a lit entry on graphite
│   └── favicon-sleep.svg      the same mark with the lamp out
├── lab/                       playgrounds and design samples (never built or deployed)
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
A project with a `link` is not linked from the home (its timeline entry goes to the link), but its page, its twin and its `llms.txt` line are built all the same, so its URL keeps working.
Also emit `robots.txt` (allow all), `_headers` (§11) and `_redirects`. There is no sitemap and no feed.

**Markdown twins and `llms.txt`.** Every entry (essay, note, project) is also written as `dist/<slug>.md`, served at `/<slug>.md`, so a person or a model can read the words without the page. It is plain text built from the content, with no timestamps:

```
# <title>

<date> · https://yoanfaure.com/<slug>/

<the entry's original Markdown body, frontmatter stripped>
```

A project adds its tagline (as a `> ` quote) and a `link: <url>` line after the second line. Each entry page points at its twin with `<link rel="alternate" type="text/markdown" href="/<slug>.md">` in the `<head>`. Drafts have no twin.

`dist/llms.txt` follows [llmstxt.org](https://llmstxt.org): `# Yoan Faure`, a one-line `> ` summary (the home description), a short plain-text paragraph (the home intro), then one `## Log` section with every entry in timeline order (left out when there are none). Each entry is `- [Title](https://yoanfaure.com/<slug>.md): description`.

A `<slug>.md` cannot collide with a page or a site file: `llms` and `llms.txt` are reserved slugs (§5), as is every other site path. `_headers` (§11) gives the twins and `llms.txt` an explicit `Content-Type` (`text/markdown; charset=utf-8` and `text/plain; charset=utf-8`).

**Share images.** Every entry has a 1200×630 PNG at `dist/og/<slug>.png`, and the home has `dist/og/home.png` (`Site.OG`). Each page points at its own with `og:image` (absolute URL), `og:image:width` 1200, `og:image:height` 630 and `og:image:alt` (the page title); `twitter:card` is `summary_large_image`. The 404 has no image and keeps `twitter:card=summary`. An image is drawn as an SVG in the dark palette (§8) and rasterised at build time by `resvg`:

- Background: `--bg` graphite, with the lamp glowing from the top left: the three radial gradients of the page's `body::before`, a little warmer. The same on every card.
- An entry: the lit mark (a lamp-coloured dot with its ring and glow) and the full date (`28 Mar 2026`) in `--text-2`, then the title in Inter Bold, `--text`, -0.03em, left-aligned. The title takes the largest of 96, 84, 72, 62 and 54px that fits in three lines (lines balanced); past three lines at 54px it ends with `…`. `Yoan Faure` bottom-left in `--name`, `yoanfaure.com` bottom-right in `--text-3`.
- The home: the name from `home.md`, one word a line as on the page (up to 168px, -0.035em, `--name`), the position (`Security engineer at Riot`) under it in `--text-2`, and `yoanfaure.com` bottom-left.
- Text is measured from the font file's glyph advances (`Site.OG.Text`, no kerning, so lines are never too wide) and a character the font lacks is dropped, never drawn as a box.
- Font: only `priv/og-fonts/Inter-Bold.ttf` (resvg cannot read WOFF2), loaded with `skip_system_fonts`, so no system font ever changes an image. It sits outside `assets/` because the build uses it and the site does not publish it.
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
summary: string      # optional; the short line on the home timeline (fallback: description)
description: string  # optional; meta description (fallback: first paragraph, plain text, ≤160 chars)
draft: false         # optional; drafts are skipped unless `mix site.build --drafts`
```

**projects/**
```yaml
title: rhino
date: 2026-09-02           # required; position on the timeline
summary: string            # optional, as above
tagline: string            # required, one line (also the description when there is none)
link: https://…            # optional; the home timeline links here instead of to /<slug>/
stack: [Go, YAML]          # optional
status: active | wip | archived
```

**home.md**
```yaml
title: string        # the name, the h1 of the home
description: string  # meta description and the llms.txt summary
tagline: string      # optional; no longer shown on a page
```

The body of `home.md` is the intro paragraph of `llms.txt`; the home page itself does not show it. The position under the name (`Security engineer at Riot`, Riot linked to `https://tryriot.com`) is `Site.Config.role/0`.

Raw HTML in Markdown is **not** rendered: MDEx runs with `unsafe: false`. Use GFM extensions: tables, strikethrough, autolink, footnotes, and heading ids. There is no syntax colouring; code blocks are plain `<pre><code>`.

**Stat callouts.** A fenced code block with the info string `stats` is a row of big numbers, one `value | label` per line:

````
```stats
91% | only read or react
0%  | chose "I comment"
82  | respondents
```
````

`Site.Markdown` post-processes MDEx's HTML: `<pre><code class="language-stats">` becomes `<dl class="stats"><div><dt>91%</dt><dd>only read or react</dd></div>…</dl>`. Values and labels are trimmed, split at the first `|`, and stay HTML-escaped exactly as MDEx wrote them (a `<script>` in a label is text, never markup). If any non-blank line has no `|`, or an empty value or label, or the block is empty, the whole block stays a plain code block, so a typo is visible instead of silently dropped. Only the exact info string `stats` counts. In `site.css`, `.stats` is a grid of `repeat(auto-fit, minmax(136px, 1fr))`: up to four columns in the reading column, two on a phone (an odd last item takes the full row). Each cell has a `--line` hairline on top, the `dl` one underneath. The value (`dt`) is Inter 600 at `clamp(36px, 28px + 1.6vw, 44px)`, -0.03em, line-height 1. The label (`dd`) is 14px in `--text-2`.

**Slugs.** Every entry lives at `/<slug>/`, so a slug may be used once across **all** types: an essay and a note cannot share one. A skipped draft does not count. Some slugs are reserved because `/<slug>/` would collide with a site path or be taken over by a legacy redirect: `assets`, `404`, `404.html`, `home`, `index`, `index.html`, `llms`, `llms.txt`, `og`, `robots.txt`, `_headers`, `_redirects`, `blog`, `projects` and `resume` (`Site.Config.reserved_slugs/0`; the last three come from the redirects in §4).

The build fails loudly on a missing required field, a bad date, a field of the wrong type, a duplicate slug (naming every file that uses it, for example `essays/same.md, notes/same.md`), or a reserved slug (naming the file).

## 6. The timeline

Entries are essays, notes, and projects, and the timeline on the home is the only list. Sort by date desc, then type (essay, project, note), then title asc (`Site.Log`). Drafts never appear unless the build asks for them.

- **Row** (`Site.Log.row/1`): the title; the summary (`summary`, else `description`); the date as `datetime` (`2026-10-29`), as shown (`29 Oct`), its month (`2026-10`) and its year; and where it goes: `/<slug>/`, or for a project with a `link`, that link and what a screen reader hears after the title (` (on GitHub)` when the host is `github.com`, else ` (external)`). Rows are numbered from 1 (`data-row`).
- **Years:** `Site.Log.years/1` groups the rows where the year changes. Each year is a `p.year` label (aria-hidden) and its own `ol.feed`; every date also carries its year for a screen reader.
- **Markup:**

```html
<section class="timeline" id="feed" aria-labelledby="feed-label">
  <h2 class="visually-hidden" id="feed-label">Entries, newest first</h2>
  <p class="year" aria-hidden="true">2026</p>
  <div class="tl">
    <ol class="feed">
      <li class="entry-row" data-row="1" data-month="2026-10">
        <a class="entry" href="/build-the-small-tool/">
          <span class="entry-title">Build the small tool</span>
          <span class="entry-desc">A Slack agent in three days, not a vendor.</span>
        </a>
        <time class="entry-date" datetime="2026-10-29">29 Oct<span class="visually-hidden"> 2026</span></time>
      </li>
      <li class="entry-row" data-row="2" data-month="2026-09">
        <a class="entry" href="https://github.com/y0anfa/rhino" rel="noopener">
          <span class="entry-title">rhino<span class="entry-out" aria-hidden="true">↗</span><span class="visually-hidden"> (on GitHub)</span></span>
          …
```

- An empty timeline is `<p class="empty">Nothing here yet.</p>`.

## 7. Layout and pages

**Global shell**
- `<html lang="en">`, `<body data-page="home|essay|note|project|404">`, then one skip link: `Skip to the entries` (`#feed`) on the home, `Skip to the content` (`#main`) elsewhere. Each page template writes the rest. There is no nav, no site header and no site footer.
- `<head>`: `<title>` is `<Page> — Yoan Faure` (home: `Yoan Faure — Security engineer at Riot`); meta description, `color-scheme` `dark light`, canonical, `og:title/description/url/type`, `og:image` with its width, height and alt, and `twitter:card` (`summary_large_image`; the 404 has no image and keeps `summary`; §4), the favicon, and a preload for `/assets/fonts/InterVariable.woff2` (with `crossorigin`). An entry page also has `<link rel="alternate" type="text/markdown" href="/<slug>.md">`. Nothing is loaded from another origin: no Google Fonts, no preconnect.
- Two inline scripts: `head.js` (applies `localStorage.theme`, `light` or `dark`, to `data-theme` before the first paint, and nothing else) and `<script type="speculationrules">` (the constant in `Site.Speculation`: prerender same-origin page links, `href_matches: "/*"`, with `eagerness: "moderate"`, except `/*.md`, `/llms.txt`, `/assets/*` and `rel~=nofollow`). The CSP allows both by sha256 (§11).
- One stylesheet, `/assets/css/site.css`. Then `<script defer blocking="render" src="/assets/js/site.js">`, render-blocking so its `pagereveal` listener and the `js` class exist before the first frame, and `favicon.js` (plus `404.js` on the 404) as plain `defer` scripts.
- **Favicon.** `assets/favicon.svg` is the mark: a 32×32 graphite square with the timeline's axis and a lit entry on it (a lamp dot and its halo). `assets/favicon-sleep.svg` is the same square with the lamp out (a grey ring). `favicon.js` swaps the `link[rel=icon]` href to the sleeping one when the tab becomes hidden (`visibilitychange`) and back when it is visible.
- **The lamp.** `body::before` paints three soft radial glows from the top of every page (warm, warmer, a cool wide one), part of the root image so they stay put during a transition. On entries and the 404 it is shorter and at 70%.

**Home** (`home.html.eex`)

```html
<div class="corner"> the theme toggle </div>
<main id="main" class="stage">
  <section class="identity" aria-labelledby="name">
    <div class="name-wrap">
      <h1 class="name" id="name"> one span.name-line per word </h1>
      <div class="name-lit" aria-hidden="true"> the same name, lit </div>
    </div>
    <p class="role">Security engineer at <a class="text-link" href="https://tryriot.com" rel="noopener">Riot</a></p>
  </section>
  <section class="timeline" id="feed"> … (§6) </section>
</main>
<div class="spot"> <div class="beam"> <div class="bead"> (aria-hidden, empty: the light)
```

- **Layout.** `.stage` is a grid, `minmax(0, 1fr) minmax(0, 520px)`, centred, at most 1040px plus gutters, as tall as the viewport, the two columns centred together. Under 880px it is one column, the timeline 72px under the position. The name is Inter 600, `clamp(2.5rem, 1.7rem + 2.6vw, 4.25rem)`, -0.035em, line-height 1, in `--name`. The position is 17px in `--text-2`.
- **The timeline.** The axis is a 1px `--line-strong` line 96px in (64px under 600px), fading out at the bottom. Each entry has a mark on the axis (an 11px ring), a leader to its title, its date to the left of the axis (13px, tabular), and the title (22px, 560, -0.02em; 20px under 600px). The date is tinted by age: `--age` 0 (newest, the lamp's colour) to 1 (oldest, `--text-3`), mixed in oklab; `site.js` computes it from the dates, and CSS has a fallback by position. The description (15px, `--text-2`) keeps its space at rest with opacity 0, and shows on the entry that is lit, hovered or has keyboard focus (`:has(.entry:focus-visible)`), so nothing moves. Hover and focus are the same light: the mark fills with the lamp and glows, the leader and the date take the lamp, the title brightens, and the other entries step down one tone (still AA). The entry is a link of at least 44px. A project that leaves the site carries a small `↗` (aria-hidden) that leans toward where it goes on hover and focus, and a visually hidden ` (on GitHub)`.
- **The light** (`site.js`, home only). Two custom properties, `--mx` and `--my`, written through the CSSOM once a frame at most, with no layout read in the handler; CSS moves everything with transforms.
  - the spot: a 720px soft glow under the pointer, everywhere on the page (fine pointers only);
  - the scan line: a hairline across the axis at the pointer's height, and the bead, a point of light on the axis: both only while the pointer is over the timeline itself (`on-timeline`). The bead reads out a date only over an empty month row, which the timeline does not draw, so over entries it hides and the entry's own mark takes the light;
  - the lit entry: the entry at the light's height gets `is-lit`. With the pointer elsewhere, or off the page, the light rests on the newest entry (or, back from an entry, on the one we came from); on a touch screen it holds 42% of the viewport height while the page scrolls past;
  - the lit name: an aria-hidden copy of the name in `--lit`, seen through a 220px window that follows the light's height, so the light rakes across the letters.
- **The decrypt.** Once a visit (`sessionStorage.decrypted`), on a fresh load: the real h1 stays in place and in the accessibility tree but transparent, while an aria-hidden overlay puts one slot over each letter, at its measured place, cycles random glyphs in the lamp's colour and locks the letters left to right (about 0.6s), then removes itself.
- **The entrance.** On a fresh load only (not when a transition brings the home back), `site.js` adds `.intro`: the name rises into its lines (or decrypts), the position fades up, the axis draws down, each entry slides in as the axis reaches it (`--i`, its place, from `site.js`), then the light comes on (`beam-on`, after 1150ms).
- **The theme toggle.** A 36px button with a sun and a moon (aria-hidden SVGs); the icon shows the theme a click switches to, and `site.js` labels it `Switch to light theme` or `Switch to dark theme`. Choosing what the system prefers forgets the choice (`localStorage.theme` removed), so the page follows the system again. The switch is one 280ms cross-fade (a view transition of type `theme`), at once under reduced motion or without view transitions. Without script the toggle is hidden.

**Entries** (`article.html.eex`, `project.html.eex`)

```html
<header class="bar"> a.back "Yoan Faure" + kbd "Esc" · the theme toggle </header>
<main id="main" class="article">
  <article>
    <p class="meta"><time datetime="2026-10-29">29 Oct 2026</time></p>
    <h1>Build the small tool</h1>
    <div class="prose"> the body </div>
    <footer class="article-end"> a.back "All entries" · p.entry-links </footer>
  </article>
</main>
```

- **The bar.** 68px, as wide as 1200px plus gutters: the back link (a chevron, the name, and an `Esc` key hint shown only with a fine pointer) on the left, the toggle on the right.
- **The column.** One centred reading measure, 580px plus gutters. The meta line is the full date only, 14px in `--text-2`, after a lit lamp dot. The h1 is `clamp(34px, 6.4vw, 54px)`, 600, -0.04em, line-height 1.04, as wide as its text. The text starts 40px under a `--line` rule: 17px, line-height 1.7, `--text-prose`, paragraphs 1.15em apart, h2 22px 600 with 2.3em above. Lists have `--text-3` markers; inline code and code blocks are JetBrains Mono on a faint card with a `--line` border; tables are ruled with `--line`; footnotes are 14px under a rule; heading anchors show a `#` on hover.
- **A project** adds its tagline under the h1 (`p.lede`, 19px, `--text-2`) and a quiet line of facts (`p.facts`: status · stack · link, 14px, `--text-3`).
- **The end.** 64px under the text, on a `--line` rule: `All entries` (back home) on the left, and on the right, 13px and quiet, `Markdown` (the twin, `/<slug>.md`) and `Ask Claude ↗` (`https://claude.ai/new?q=<prompt>`, `rel="noopener"`, same tab). The separator and the arrow are aria-hidden. The prompt is `Read https://yoanfaure.com/<slug>/ by Yoan Faure, a security engineer. Using only what is on that page, summarize the main argument in a few sentences, then tell me where you would push back.`; for a project the end is `summarize what the project does and why, then suggest one improvement.` It is URI-encoded (everything but unreserved characters, so a space is `%20`) in `Site.View.ask_url/1`, then HTML-escaped by the template.
- There is no site footer on an entry either: no email, no LinkedIn, no build hash.

**404** (`404.html.eex`): the bar (without the `Esc` hint), then in the reading column a meta line `404`, the h1 `Not found`, `There is no page at <span data-path>this address</span>.` (`404.js` puts `location.pathname` in it via `textContent`), and the `All entries` link.

**Back home from an entry.** On an entry page (`data-page` is `essay`, `note` or `project`), a click on the side margins, Escape, and both back links (`[data-home]`) go back home. All in `site.js`:

- *Where.* The margin is the `body` (or `html`) itself: the bar and the column are its children. The press (`pointerdown`, primary button) and the click must both be on the margin, so the end of a text selection that began on the text does not count. Links, buttons, a text selection, a click with a modifier key or a non-primary button, and a coarse pointer are all left alone. The back links take a plain primary click only.
- *Which way.* If the page before this one in the session history, past any `#hash` hops on this page, is the home (`navigation.entries()`), it steps back to it with `history.go(-n)`, so the home keeps its scroll position and the back transition plays. Otherwise it opens `/`. Without the Navigation API it uses `document.referrer` and `history.length`, and a `#hash` on the page sends it to `/`.
- *Escape.* The same, unless it has a modifier, comes from a form field or `contenteditable`, was prevented, or is part of an input method.
- *Affordance.* Inside `@media (pointer: fine)`, entry pages have `cursor: zoom-out` on the body and `cursor: auto` on the skip link, the bar and `main`. The home and the 404 are not touched.

**Transitions.** Cross-document view transitions. The motion is CSS (`site.css`); `site.js` says which way a navigation goes and which element is the shared title.

- *Opt-in.* `@view-transition { navigation: auto; }` inside `prefers-reduced-motion: no-preference`, and `navigation: none` inside `reduce`. A browser without support navigates at once.
- *Direction.* On `pageswap` (old page) and `pagereveal` (new page; also for a page restored from the back/forward cache or activated from a prerender, so the speculation rules still transition), `site.js` types the transition from the two URLs (`navigation.activation`): `forward` for home to an entry, `back` for an entry to the home, whatever started it. The old page also gets `leaving`, the new page `arriving`. Every other navigation gets no type and the browser's own cross-fade.
- *Names.* Only the page that arrives names its content: `home-name` (`.identity`) and `home-year` (`.timeline`) on the home, `entry-body` (`.article`) on an entry. The old page names nothing, so it is never cut into tall pictures (a long essay named as one picture can come out as a white frame). The lamp, the corner and the bar stay in the root images.
- *The shared title.* At most one element per page carries `view-transition-name: entry-title`, written through the CSSOM. Going in, `pageswap` names the clicked entry's `.entry-title` and `pagereveal` names the h1. Coming back, `pageswap` names the h1 and `pagereveal` finds the entry we came from, scrolls it into view (`block: "nearest"`, unless the URL has a hash), names it and rests the light on it. A title not fully on screen is not named, and the other side then treats its title as ordinary content (`:only-child`). Names are cleared when `viewTransition.finished` settles, when `pageswap` starts, and when a page is restored from the cache.
- *Timing,* in tokens on `:root`: `--vt-enter: 480ms` with `cubic-bezier(0.2, 0, 0, 1)`, `--vt-exit: 160ms` with `cubic-bezier(0.3, 0, 0.8, 0.15)`, `--vt-stagger: 60ms`. New content uses `vt-in` (12px lower and transparent to its place); old content only fades. The new root fades in over the old one in `--vt-exit`. Back home, the timeline arrives a beat after the name. The title's two pictures fill their group and scale from its top left corner (`object-fit: contain`): going in, the row fades out in the first quarter and the heading fades in as that ends; coming back, the mirror image. The arriving h1 carries a halo of the page colour while it crosses the fading content. A hovered entry is captured without its glow.
- *White frames.* `html` and `::view-transition` have the page colour, as does the root group during a navigation; every arriving image is `opacity: 0` in its rule until its animation runs; no `plus-lighter`.
- *Skipped transitions.* A browser skips a view transition when the page is hidden or not composited, and cancels it when two elements share a name. `site.js` handles the promises of every transition it is handed, never throws or logs, and clears its names whatever the outcome. (In a page that is not composited at all, Chrome can skip the arriving transition before the page sees it and log the skip itself; the design sample does the same.)

## 8. Visual system

```css
/* light-dark(light, dark) on :root */
--bg:         #f7f7f6  #0d0f14     --text:       #15171c  #ecebe8
--text-prose: #2a2d34  #cfd0d3     --text-2:     #4d515a  #a2a6ae
--text-3:     #62666f  #80848d     --name:       #15171c  #d6d5d2
--lamp:       #9a5a00  #f2c47c     --lit:        #8a4f00  #fff3df
--line:       rgb(20 22 28 / .09)  rgb(255 255 255 / .07)
--line-strong rgb(20 22 28 / .18)  rgb(255 255 255 / .15)
```

Plus the glows of the lamp (`--glow-hot`, `--glow-core`, `--glow-wide`, `--spot`, `--lit-glow`, `--beam-line`), `--hover` and `--card`, all `light-dark()` pairs. `--focus` is `--lamp`.

- **Theming:** `:root` has `color-scheme: dark light`, so with no `data-theme` the system decides; `[data-theme=light|dark]` sets `color-scheme` and every `light-dark()` follows. There is one palette, no second set under a media query.
- **Fonts:** Inter as a variable font (`InterVariable.woff2`, `InterVariable-Italic.woff2`, `font-weight: 100 900`) with `font-optical-sizing: auto`, and JetBrains Mono 400 only for `code` and `pre`. All `font-display: swap`, all self-hosted with their OFL licences in `assets/fonts/`.

  ```css
  --font: "Inter", ui-sans-serif, system-ui, -apple-system, "Segoe UI", Roboto, sans-serif;
  --mono: "JetBrains Mono", ui-monospace, "SF Mono", Menlo, monospace;
  ```

- **Sizes** are in px, as designed: body 16px, line-height 1.6; the text of an entry 17px, line-height 1.7. Weights are 400, 500 (UI), 560 (timeline titles) and 600 (name, headings).
- **Links:** `color: inherit`; in text, a 1px underline at 40% of the colour, 0.22em offset, that takes the lamp on hover. Focus-visible is a 2px solid outline in `--focus`, 3px off (2px on an entry). Selection is the lamp at 30%.
- **Contrast:** every text colour (`--text`, `--text-prose`, `--text-2`, `--text-3`, `--name`, `--lamp`, `--lit`) keeps at least 4.5:1 on `--bg` in both themes, `--text` at least 7:1; so does every date tint between `--lamp` and `--text-3`. A test checks the pairs.
- **Layout guards:** no horizontal scroll down to 360px: code blocks scroll inside their box, headings and table cells break long words, the entry's negative margins stay inside the gutter.

## 9. Accessibility and reduced motion

- Every page has a skip link, one h1, and landmarks (`main`; on entries a `header` bar and the article's `footer`). The timeline is an ordered list under a visually hidden h2; years are aria-hidden and every date carries its year for a screen reader.
- Keyboard: Tab reaches the toggle, the company link and every entry; focus is always visible and lights an entry exactly like hover, description included. Escape goes back home from an entry.
- Decorative things are aria-hidden: the lit name, the decrypt overlay, the light, the toggle's icons, the arrows, the separators and the `Esc` hint.
- **Reduced motion:** no decrypt, no light (it stays off; hover and focus still brighten), no entrance, no navigation transition, no theme cross-fade, the arrows do not lean, and every remaining animation and transition is cut to 0.01ms.
- **Without script:** the name, the position, the timeline and every entry read and link as normal; the description shows on hover and focus; the light, the lit name and the theme toggle (which needs script) are not shown.

**Removed with the redesign:** the ASCII topographic field (`field.js`, its canvas and CSS, `lab/field.html` is left as it was), the git-log list and its commit hashes (and the git reading behind them), the beige palette, `theme.js` and `transitions.js` (both in `site.js` now), the site header and footer (email, LinkedIn, build hash), the home intro text, the terminal 404, and the contour lines and JetBrains Mono of the share images.

## 10. Build (Elixir)

- **Mix project `:site`.** Deps pinned in `mix.lock`:
  - `mdex`, `yaml_elixir` and `resvg` (runtime). `resvg` is a Rust NIF with precompiled binaries (macOS arm64, Linux x86_64 GNU), fetched on first compile like MDEx's; it rasterises the share images (§4) and pins `rustler_precompiled` to 0.8.x;
  - `bandit` and `plug`, `only: :dev`, for the dev server.
  - Nothing else.
- **`mix site.build [--drafts] [--content DIR] [--out DIR]`:**
  1. Clean the output.
  2. Load and validate content.
  3. Render the EEx templates. **EEx does not escape:** every interpolated string goes through `Site.HTML.escape/1`, and only rendered Markdown is inserted raw. The build does not read git.
  4. Copy `assets/` to `dist/assets/` as is (no fingerprinting).
  5. Inline `assets/js/head.js` (trimmed) into `<head>` and compute its `sha256-…` for the CSP. Compute the `sha256-…` of the speculation rules (`Site.Speculation.rules/0`) too.
  6. Write `_headers` (§11), `_redirects` (§4), `robots.txt`, `404.html`, the Markdown twin of every entry, `llms.txt` and the share images in `og/` (§4).
- **Deterministic:** no build timestamps; sorted iteration everywhere; identical output for identical sources and env.
- **`mix site.verify`:** builds twice into temporary dirs, compares a SHA-256 over every file path and content, fails on mismatch, and prints the tree hash.
- **`mix site.serve [--port 4000]`:** builds, serves `dist/` with Bandit and Plug, and applies the headers parsed from `dist/_headers`, so CSP violations show up locally exactly as in production. It polls `content/`, `templates/`, `assets/` and `lib/` mtimes every second and rebuilds on change (no file_system dep). Missing paths serve `404.html` with status 404, and `/x/` serves `/x/index.html`.
- **Tests:** frontmatter parsing and validation (the `summary` field too), flat URLs, slugs (global uniqueness and reserved slugs), `_redirects`, escaping, timeline order, rows and years, no nav, no footer and no list pages, the home markup (name, position, timeline structure, the summary fallback, the external project link and its label, no drafts, the light layers), the entry, project and 404 markup, the CSS invariants (the palette and its contrast, the fonts, focus, the description reveal, the light only on the timeline, reduced-motion guards, no trace of the old design), CSP hashes (head.js and the speculation rules) and no inline style, the Markdown twins and `llms.txt`, the entry links and their escaping, the favicon pair and its script, the share images (size, palette, no metadata chunks, determinism, text wrapping, meta tags), the `stats` callouts, the page transitions in CSS, and `site.js` run under node with stubs when `node` is installed (direction and names, the margins, Escape and the back links, the theme toggle, the entrance), and a determinism smoke test, all using `test/fixtures/content`.

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
`site.js` needs no CSP change: it is a same-origin script, and everything it positions or names (the light's custom properties, the decrypt's slots, the transition names) is written through the CSSOM (`style.setProperty`), never as an inline style attribute, so `style-src` stays `'self'`. Fonts are self-hosted, so `font-src` and `style-src` stay `'self'`.
**Never** use inline `style=""` attributes, inline `<style>`, inline event handlers, or any inline script other than head.js and the speculation rules.

## 12. Hosting and deploy

- **`wrangler.jsonc`:** an assets-only Worker named `yoanfaure` with `assets.directory: ./dist`, `not_found_handling: "404-page"` and `html_handling: "auto-trailing-slash"`. `yoanfaure.com` is its custom domain (`routes`), so Cloudflare owns the apex record and certificate.
- **`redirect/`:** a script Worker named `yoanfau-re` (the old site Worker's name, so `yoanfau.re` stays attached) with custom domains `yoanfau.re` and `www.yoanfaure.com`. It answers every request with a 301 to the same path and query on `https://yoanfaure.com`, plus HSTS. Old Hugo paths then resolve through the site's `_redirects`. `www.yoanfau.re` reaches it through a Redirect Rule to the `yoanfau.re` apex.
- **`.github/workflows/deploy.yml`** runs on push to `main` and on `workflow_dispatch`, with least-privilege permissions. **Every third-party action is pinned to a full commit SHA** with a `# vX.Y.Z` comment.
  - The **build** job: checkout with `fetch-depth: 0` (left from the commit hashes the old log showed; the build no longer reads git), then `erlef/setup-beam` with `version-file: .tool-versions` and `version-type: strict`, a deps cache, `mix format --check-formatted`, `mix test`, `MIX_ENV=prod mix site.verify`, and `MIX_ENV=prod mix site.build`. It uploads `dist`.
  - The **deploy** job (only on `main`) runs `cloudflare/wrangler-action` with secrets `CLOUDFLARE_API_TOKEN` and `CLOUDFLARE_ACCOUNT_ID`: the site first, then `deploy --config redirect/wrangler.jsonc`, so the old domain only redirects once the new one serves. The token must cover both zones.
- **Owner steps still open** (README, Domains): Always Use HTTPS and no Email Address Obfuscation on `yoanfaure.com`, Email Routing for `hi@`, and DNSSEC on both zones. Mail for `@yoanfau.re` stays on OVH.

## 13. Launch content

All drafts are Yoan's to edit.

- **home.md:** the name, the description, and the intro used by `llms.txt`: the first paragraph, the career line `At Riot in Paris since 2025. Before: Worklife, Checkout.com.`, and the off-hours line.
- **essays/2026-03-28-threat-modeling-with-claude-code.md:** migrated verbatim from `archive/hugo`, summary `A Claude Code skill that runs STRIDE.` It is at `/threat-modeling-with-claude-code/`; its old URL `/blog/threat-modeling-with-claude-code/` is redirected.
- **notes/2026-10-29-build-the-small-tool.md:** summary `A Slack agent in three days, not a vendor.`
- **projects/rhino.md:** workflows as code, a mini Airflow in Go, summary `Workflows as code. A mini Airflow in Go.` On the home it links to `https://github.com/y0anfa/rhino`; its page stays at `/rhino/`.
- **Drafts** (`draft: true`): *Security should unleash*, *Security pays in more than one currency*, *AI is a teammate*, *Comms is the staff skill*.
- **Dropped at review:** the uses page and the cv page.

The public timeline therefore has three entries, all in 2026: one note, one project and one essay.
