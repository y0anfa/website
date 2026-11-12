defmodule Site.BuildTest do
  use ExUnit.Case, async: true

  import Site.TestHelpers

  alias Site.{Build, Headers}

  @head_js File.read!("assets/js/head.js") |> String.trim()

  # The home, the 404, and one flat page per entry (essays, notes and projects alike).
  @pages ~w(
    404.html
    escape-me/index.html
    first-essay/index.html
    index.html
    second-essay/index.html
    small-note/index.html
    widget/index.html
  )

  # Besides the pages: the site files, llms.txt, the Markdown twin of each entry and
  # the share image (og/) of the home and of each entry.
  @extras ~w(
    _headers
    _redirects
    robots.txt
    llms.txt
    escape-me.md
    first-essay.md
    second-essay.md
    small-note.md
    widget.md
    og/escape-me.png
    og/first-essay.png
    og/home.png
    og/second-essay.png
    og/small-note.png
    og/widget.png
  )

  # One shared, read-only build of the fixtures; tests that change things build their own.
  setup_all do
    out = build_fixtures()
    %{tree: read_tree(out)}
  end

  defp page(tree, path), do: Map.fetch!(tree, path)

  describe "output" do
    test "writes every page of the URL map, plus _headers, _redirects and robots.txt",
         %{tree: tree} do
      files = Map.keys(tree)

      for path <- @pages ++ @extras, do: assert(path in files, "missing #{path}")

      non_assets = Enum.reject(files, &String.starts_with?(&1, "assets/"))
      assert Enum.sort(non_assets) == Enum.sort(@pages ++ @extras)
    end

    test "every entry is one flat page, whatever its type", %{tree: tree} do
      # an essay, a note and a project all live at /<slug>/
      assert page(tree, "first-essay/index.html") =~ ~s(<h1>First essay</h1>)
      assert page(tree, "small-note/index.html") =~ ~s(<h1>Small note</h1>)
      assert page(tree, "widget/index.html") =~ ~s(<h1>widget</h1>)

      # and the folders of the content tree are not URL segments
      for dir <- ~w(essays notes projects uses cv) do
        refute Enum.any?(Map.keys(tree), &String.starts_with?(&1, dir <> "/")),
               "#{dir}/ was written"
      end
    end

    test "does not write drafts", %{tree: tree} do
      refute Map.has_key?(tree, "an-unfinished-draft/index.html")
      refute tree |> page("index.html") |> String.contains?("unfinished")
    end

    test "writes drafts with drafts: true" do
      tree = [drafts: true] |> build_fixtures() |> read_tree()
      assert page(tree, "an-unfinished-draft/index.html") =~ "An unfinished draft"
      assert page(tree, "index.html") =~ "An unfinished draft"
    end

    test "_redirects sends the old Hugo URLs to the flat ones, in a fixed order", %{tree: tree} do
      assert page(tree, "_redirects") ==
               "/blog/* /:splat 301\n" <>
                 "/projects/* /:splat 301\n" <>
                 "/resume/ / 301\n" <>
                 "/resume / 301\n"

      assert page(tree, "_redirects") == Site.Redirects.render()
    end

    test "robots.txt allows everything and names no sitemap", %{tree: tree} do
      assert page(tree, "robots.txt") == "User-agent: *\nAllow: /\n"
    end

    test "copies assets verbatim, skipping dotfiles", %{tree: tree} do
      for rel <- ["css/site.css", "js/head.js", "js/site.js", "js/404.js", "favicon.svg"] do
        assert page(tree, "assets/" <> rel) == File.read!("assets/" <> rel)
      end

      refute Enum.any?(Map.keys(tree), &String.contains?(&1, ".DS_Store"))
    end

    test "cleans stale files from the output directory" do
      out = build_fixtures()
      File.write!(Path.join(out, "stale.html"), "old")
      File.mkdir_p!(Path.join(out, "old-dir"))
      File.write!(Path.join(out, "old-dir/x.html"), "old")

      Build.run(content: fixture_copy(), out: out)

      refute File.exists?(Path.join(out, "stale.html"))
      refute File.exists?(Path.join(out, "old-dir"))
    end

    test "skips dotfiles in assets" do
      assets = Path.join(tmp_dir(), "assets")
      File.mkdir_p!(Path.join(assets, "js"))
      File.write!(Path.join(assets, "js/head.js"), "(function(){})();\n")
      File.write!(Path.join(assets, ".DS_Store"), "junk")
      File.write!(Path.join(assets, "js/.hidden"), "junk")
      File.write!(Path.join(assets, "js/ok.js"), "ok")

      out = Path.join(tmp_dir(), "dist")
      Build.run(content: fixture_copy(), out: out, assets: assets)

      assert Build.files(Path.join(out, "assets")) == ["js/head.js", "js/ok.js"]
    end
  end

  describe "head" do
    test "titles", %{tree: tree} do
      assert page(tree, "index.html") =~
               "<title>Yoan Faure — Security engineer at Riot</title>"

      assert page(tree, "first-essay/index.html") =~
               "<title>First essay — Yoan Faure</title>"

      assert page(tree, "widget/index.html") =~ "<title>widget — Yoan Faure</title>"
      assert page(tree, "404.html") =~ "<title>Not found — Yoan Faure</title>"
    end

    test "description, canonical, Open Graph, Twitter card, favicon, font preload", %{tree: tree} do
      html = page(tree, "second-essay/index.html")

      assert html =~
               ~s(<meta name="description" content="A second essay, with its own description.">)

      assert html =~ ~s(<link rel="canonical" href="https://yoanfaure.com/second-essay/">)
      assert html =~ ~s(<meta property="og:title" content="Second essay — Yoan Faure">)

      assert html =~
               ~s(<meta property="og:description" content="A second essay, with its own description.">)

      assert html =~
               ~s(<meta property="og:url" content="https://yoanfaure.com/second-essay/">)

      assert html =~ ~s(<meta property="og:type" content="article">)
      assert html =~ ~s(<meta name="twitter:card" content="summary_large_image">)
      assert html =~ ~s(<link rel="icon" href="/assets/favicon.svg")

      assert html =~
               ~s(<link rel="preload" href="/assets/fonts/InterVariable.woff2" as="font" type="font/woff2" crossorigin>)

      assert page(tree, "index.html") =~ ~s(<link rel="canonical" href="https://yoanfaure.com/">)
      assert page(tree, "index.html") =~ ~s(<meta property="og:type" content="website">)
    end

    test "the 404 page has no canonical URL", %{tree: tree} do
      refute page(tree, "404.html") =~ "canonical"
      refute page(tree, "404.html") =~ "og:url"
    end

    test "the page sets the lang and a dark-first colour scheme", %{tree: tree} do
      for path <- @pages do
        assert page(tree, path) =~ ~s(<html lang="en">), path
        assert page(tree, path) =~ ~s(<meta name="color-scheme" content="dark light">), path
        refute page(tree, path) =~ "data-vt", path
      end
    end

    test "head.js restores the theme, and nothing else" do
      assert @head_js =~ "localStorage.getItem('theme')"
      refute @head_js =~ "sessionStorage"
      refute @head_js =~ "field"
    end

    test "one stylesheet, site.js render-blocking, favicon.js deferred, nothing else", %{
      tree: tree
    } do
      for path <- @pages do
        html = page(tree, path)
        assert html =~ ~s(<link rel="stylesheet" href="/assets/css/site.css">), path

        assert html =~ ~s(<script defer blocking="render" src="/assets/js/site.js"></script>),
               path

        assert html =~ ~s(<script defer src="/assets/js/favicon.js"></script>), path

        srcs = Regex.scan(~r/<script[^>]*\ssrc="([^"]+)"/, html) |> Enum.map(&List.last/1)
        expected = ["/assets/js/site.js", "/assets/js/favicon.js"]
        expected = if path == "404.html", do: expected ++ ["/assets/js/404.js"], else: expected
        assert srcs == expected, path
      end
    end

    test "fonts are self-hosted: no Google Fonts, no third-party stylesheet", %{tree: tree} do
      for path <- @pages do
        html = page(tree, path)
        refute html =~ "fonts.googleapis", path
        refute html =~ "fonts.gstatic", path
        refute html =~ ~s(rel="preconnect"), path
        assert length(Regex.scan(~r/<link rel="stylesheet"/, html)) == 1, path
      end
    end
  end

  describe "shell" do
    test "every page has one skip link, to the entries on the home and the content elsewhere",
         %{tree: tree} do
      assert page(tree, "index.html") =~
               ~s(<body data-page="home">\n<a class="skip-link" href="#feed">Skip to the entries</a>)

      for path <- @pages, path != "index.html" do
        html = page(tree, path)

        assert html =~ ~s(<a class="skip-link" href="#main">Skip to the content</a>), path
        assert length(Regex.scan(~r/class="skip-link"/, html)) == 1, path
        assert html =~ ~s(<main id="main" class="article), path
      end
    end

    test "the home has the LinkedIn link and the theme toggle in a corner, and no bar", %{
      tree: tree
    } do
      html = page(tree, "index.html")
      [corner] = Regex.run(~r{<div class="corner">.*?</div>}s, html)

      assert corner =~
               ~r{^<div class="corner">\n<a class="corner-link" [^>]*>.*?</a>\n<button class="theme-toggle" type="button"}s

      refute html =~ ~s(class="bar")
      assert length(Regex.scan(~r/class="theme-toggle"/, html)) == 1
    end

    test "entry pages and the 404 have the bar: back to the name on the left, the toggle on the right",
         %{tree: tree} do
      for path <- @pages, path != "index.html" do
        html = page(tree, path)
        [bar] = Regex.run(~r{<header class="bar">.*?</header>}s, html)

        assert bar =~ ~s(<a class="back" href="/" data-home>), path
        assert bar =~ "Yoan Faure", path

        assert bar =~ ~s(<button class="theme-toggle" type="button" aria-label="Switch theme">),
               path

        assert length(Regex.scan(~r/<a[\s>]/, bar)) == 1, path
        assert length(Regex.scan(~r/<button[\s>]/, bar)) == 1, path

        # the Escape hint only where Escape goes back: entry pages, not the 404
        if path == "404.html",
          do: refute(bar =~ "<kbd"),
          else: assert(bar =~ ~s(<kbd aria-hidden="true">Esc</kbd>), path)
      end
    end

    test "the toggle's icons are decorative and its label is set by site.js", %{tree: tree} do
      html = page(tree, "index.html")
      [toggle] = Regex.run(~r{<button class="theme-toggle".*?</button>}s, html)

      assert length(Regex.scan(~r/<svg [^>]*aria-hidden="true"/, toggle)) == 2
      assert toggle =~ ~s(class="icon-sun")
      assert toggle =~ ~s(class="icon-moon")
    end

    test "no page has a nav, a site header or a site footer", %{tree: tree} do
      for path <- @pages do
        html = page(tree, path)
        refute html =~ "<nav", path
        refute html =~ "aria-current", path
        refute html =~ "site-header", path
        refute html =~ "site-footer", path
        refute html =~ "built from", path
        refute html =~ "mailto:", path
        # LinkedIn only in the home's corner
        if path != "index.html", do: refute(html =~ "linkedin", path)
      end
    end

    test "the old design is gone: no field backdrop, no canvas, no log", %{tree: tree} do
      for path <- @pages do
        html = page(tree, path)
        refute html =~ "data-field", path
        refute html =~ "<canvas", path
        refute html =~ "field.js", path
        refute html =~ "theme.js", path
        refute html =~ "transitions.js", path
        refute html =~ ~s(type="module"), path
        refute html =~ ~r/class="log/, path
      end

      for asset <- ~w(assets/js/field.js assets/js/theme.js assets/js/transitions.js) do
        refute Map.has_key?(tree, asset), asset
      end
    end
  end

  describe "home (SPEC section 7)" do
    defp main(html) do
      [_, main] = Regex.run(~r{<main id="main" class="stage">(.*)</main>}s, html)
      main
    end

    test "is the name, the position and the timeline, and nothing else", %{tree: tree} do
      html = page(tree, "index.html")
      main = main(html)

      assert main =~ ~s(<section class="identity" aria-labelledby="name">)
      assert main =~ ~s(<section class="timeline" id="feed" aria-labelledby="feed-label">)
      assert length(Regex.scan(~r/<section/, main)) == 2
      assert length(Regex.scan(~r/<h1/, html)) == 1

      # no intro text, no contact line, no footer, no build hash
      refute html =~ "This is the intro paragraph."
      refute html =~ "Fixture tagline for the home page."
      refute html =~ "<footer"
      refute html =~ "unversioned"
      refute html =~ ~r/[0-9a-f]{7}-dirty|·······/
    end

    test "the name is the h1, on one line, in the first row of the timeline", %{tree: tree} do
      main = main(page(tree, "index.html"))

      assert main =~
               ~r{<section class="identity" aria-labelledby="name">\s*<h1 class="name" id="name">Test Person</h1>\s*<p class="role">}

      refute main =~ "name-line"
      refute main =~ "name-lit"
    end

    test "the one contact is a quiet LinkedIn icon in the corner, named for screen readers", %{
      tree: tree
    } do
      html = page(tree, "index.html")

      assert html =~
               ~s(<a class="corner-link" href="https://www.linkedin.com/in/yoan-faure" rel="me noopener" aria-label="LinkedIn">)

      assert length(Regex.scan(~r/linkedin\.com/, html)) == 1
    end

    test "the position links the company", %{tree: tree} do
      assert main(page(tree, "index.html")) =~
               ~s(<p class="role">Security engineer at <a class="text-link" href="https://tryriot.com" rel="noopener">Riot</a></p>)
    end

    test "the timeline is a hidden heading, a year label and one ordered list", %{tree: tree} do
      main = main(page(tree, "index.html"))

      assert main =~
               ~r{<h2 class="visually-hidden" id="feed-label">Entries, newest first</h2>\s*<p class="year" aria-hidden="true">2026</p>\s*<div class="tl">\s*<ol class="feed">}

      assert length(Regex.scan(~r/<ol class="feed">/, main)) == 1
      assert length(Regex.scan(~r/class="year"/, main)) == 1
    end

    test "lists every entry in order, numbered, with its month", %{tree: tree} do
      main = main(page(tree, "index.html"))

      rows =
        Regex.scan(~r{<li class="entry-row" data-row="(\d+)" data-month="([\d-]+)">}, main)
        |> Enum.map(fn [_, n, month] -> {n, month} end)

      assert rows == [
               {"1", "2026-10"},
               {"2", "2026-10"},
               {"3", "2026-10"},
               {"4", "2026-10"},
               {"5", "2026-03"}
             ]

      hrefs = Regex.scan(~r{<a class="entry" href="([^"]+)"}, main) |> Enum.map(&List.last/1)

      assert hrefs == [
               "/second-essay/",
               "https://example.com/widget",
               "/small-note/",
               "/escape-me/",
               "/first-essay/"
             ]
    end

    test "an entry is its title in the link, and its date beside it", %{tree: tree} do
      main = main(page(tree, "index.html"))

      assert main =~
               ~r{<a class="entry" href="/small-note/">\s*<span class="entry-title">Small note</span>\s*</a>\s*<time class="entry-date" datetime="2026-10-28">28 Oct<span class="visually-hidden"> 2026</span></time>\s*</li>}

      # the date is day and month; the year is there for a screen reader only
      assert main =~
               ~s(<time class="entry-date" datetime="2026-03-28">28 Mar<span class="visually-hidden"> 2026</span></time>)
    end

    test "no summary or description is shown on the home", %{tree: tree} do
      main = main(page(tree, "index.html"))

      refute main =~ "entry-desc"
      refute main =~ "The short line on the timeline."
      refute main =~ "A second essay, with its own description."
      refute main =~ "One idea, briefly."
    end

    test "a project with a link goes straight to it, and says so", %{tree: tree} do
      main = main(page(tree, "index.html"))

      assert main =~
               ~s(<a class="entry" href="https://example.com/widget" rel="noopener">\n) <>
                 ~s|          <span class="entry-title">widget<span class="entry-out" aria-hidden="true">↗</span><span class="visually-hidden"> (external)</span></span>|

      # only the link that leaves the site has rel and the arrow
      assert length(Regex.scan(~r/rel="noopener"/, main)) == 2
      assert length(Regex.scan(~r/class="entry-out"/, main)) == 1
      refute main =~ ~s(href="/widget/")

      # its own page is still built, with its twin and its share image
      assert page(tree, "widget/index.html") =~ "<h1>widget</h1>"
      assert Map.has_key?(tree, "widget.md")
      assert Map.has_key?(tree, "og/widget.png")
    end

    test "the line is one empty, aria-hidden svg after main, on the home only", %{tree: tree} do
      html = page(tree, "index.html")
      [_, after_main] = String.split(html, "</main>")

      assert after_main =~ ~s(<svg class="line" aria-hidden="true"><path pathLength="1"/></svg>)
      refute html =~ ~r/class="(spot|beam|bead)"/

      for path <- @pages, path != "index.html" do
        refute page(tree, path) =~ ~s(class="line"), path
      end
    end

    test "the type is not shown", %{tree: tree} do
      html = page(tree, "index.html")
      refute html =~ ~r{>(essay|note|project)</}
      refute html =~ "log-type"
    end

    test "no list pages, and no link to one", %{tree: tree} do
      html = page(tree, "index.html")

      refute html =~ ~r{href="/(essays|notes|projects|uses|cv)/}

      for {path, content} <- tree, String.ends_with?(path, ".html") do
        refute content =~ ~s(class="list-page"), path
      end
    end

    test "an empty timeline says so" do
      dir = minimal_content()
      out = Path.join(tmp_dir(), "dist")
      Build.run(content: dir, out: out)
      html = out |> Path.join("index.html") |> File.read!()

      assert html =~ ~s(<p class="empty">Nothing here yet.</p>)
      refute html =~ "<ol"
      refute html =~ ~s(class="year")
    end

    test "a year label where the year changes, each year its own list" do
      entry = fn title, date -> "---\ntitle: #{title}\ndate: #{date}\n---\nBody.\n" end

      dir =
        minimal_content(%{
          "notes/a.md" => entry.("New", "2026-02-01"),
          "notes/b.md" => entry.("Old", "2025-11-20"),
          "notes/c.md" => entry.("Older", "2025-01-05")
        })

      out = Path.join(tmp_dir(), "dist")
      Build.run(content: dir, out: out)
      html = out |> Path.join("index.html") |> File.read!()

      years = Regex.scan(~r{<p class="year" aria-hidden="true">(\d+)</p>}, html)
      assert Enum.map(years, &List.last/1) == ["2026", "2025"]
      assert length(Regex.scan(~r/<ol class="feed">/, html)) == 2

      # the rows are numbered across the years, newest first
      assert Regex.scan(~r/data-row="(\d)"/, html) |> Enum.map(&List.last/1) == ~w(1 2 3)
      assert html =~ ~s(1 Feb<span class="visually-hidden"> 2026</span>)
      assert html =~ ~s(5 Jan<span class="visually-hidden"> 2025</span>)
    end
  end

  describe "entries and the 404" do
    test "an article: the meta line is the full date only, then h1, the text and the end",
         %{tree: tree} do
      html = page(tree, "first-essay/index.html")

      assert html =~
               ~r{<main id="main" class="article">\s*<article>\s*<p class="meta"><time datetime="2026-03-28">28 Mar 2026</time></p>\s*<h1>First essay</h1>\s*<div class="prose">}

      assert html =~ ~s(<h2 id="a-heading">)
      assert html =~ "<table>"
      assert html =~ ~s(<pre><code class="language-sh">)
      assert html =~ ~r{<footer class="article-end">\s*<a class="back" href="/" data-home>}
      assert html =~ ~r{</svg>\s*All entries\s*</a>}

      note = page(tree, "small-note/index.html")
      assert note =~ ~s(<p class="meta"><time datetime="2026-10-28">28 Oct 2026</time></p>)
      refute note =~ "·······"
    end

    test "raw HTML in Markdown is never rendered", %{tree: tree} do
      html = page(tree, "first-essay/index.html")

      refute html =~ "<script>alert"
      refute html =~ "<b>bold</b>"
      refute html =~ "javascript:"
      assert html =~ "&lt;script&gt;alert(1)&lt;/script&gt;"
    end

    test "a project: date, h1, tagline, facts, the text and the end", %{tree: tree} do
      html = page(tree, "widget/index.html")

      assert html =~ ~s(<main id="main" class="article project">)

      assert html =~
               ~r{<p class="meta"><time datetime="2026-10-28">28 Oct 2026</time></p>\s*<h1>widget</h1>\s*<p class="lede">A small widget for the fixtures.</p>}

      assert html =~
               ~s(<p class="facts"><span>active</span><span class="sep" aria-hidden="true"> · </span><span>Elixir, YAML</span><span class="sep" aria-hidden="true"> · </span><a href="https://example.com/widget">example.com/widget</a></p>)

      assert html =~ "<li>one</li>"
      assert html =~ ~s(<footer class="article-end">)
    end

    test "the 404 is a short page in the same language", %{tree: tree} do
      html = page(tree, "404.html")

      assert html =~
               ~r{<main id="main" class="article not-found">\s*<p class="meta">404</p>\s*<h1>Not found</h1>}

      assert html =~
               ~s(<p>There is no page at <span class="path" data-path>this address</span>.</p>)

      assert html =~ ~r{<footer class="article-end">\s*<a class="back" href="/" data-home>}
      refute html =~ "entry-links"
      refute html =~ "<pre"
      assert html =~ ~s(<script defer src="/assets/js/404.js"></script>)
    end
  end

  describe "escaping" do
    test "titles and descriptions are escaped everywhere", %{tree: tree} do
      title = "Tom &amp; &quot;Jerry&quot; &lt;script&gt;alert(1)&lt;/script&gt;"

      for path <- ["index.html", "escape-me/index.html"] do
        html = page(tree, path)
        assert html =~ title, path
        refute html =~ "<script>alert", path
      end

      html = page(tree, "escape-me/index.html")
      assert html =~ "<title>#{title} — Yoan Faure</title>"

      assert html =~
               ~s(<meta name="description" content="A &quot;quoted&quot; &lt;description&gt; &amp; more">)

      assert html =~ ~s(<h1>#{title}</h1>)
    end

    test "no page contains an unexpected inline script", %{tree: tree} do
      for {path, html} <- tree, String.ends_with?(path, ".html") do
        inline =
          Regex.scan(~r{<script(?![^>]*\ssrc=)[^>]*>(.*?)</script>}s, html)
          |> Enum.map(&List.last/1)

        assert inline == [@head_js, Site.Speculation.rules()],
               "#{path}: inline scripts other than head.js and the speculation rules"
      end
    end
  end

  describe "CSP-safe markup" do
    test "no inline styles, style tags or inline event handlers on any page", %{tree: tree} do
      for {path, html} <- tree, String.ends_with?(path, ".html") do
        refute html =~ ~r/\sstyle\s*=/i, "#{path}: style attribute"
        refute html =~ ~r/<style[\s>]/i, "#{path}: <style>"
        refute html =~ ~r/\son[a-z]+\s*=/i, "#{path}: inline event handler"
        refute html =~ ~r/javascript:/i, "#{path}: javascript: URL"
      end
    end

    test "everything is loaded from the same origin", %{tree: tree} do
      for {path, html} <- tree, String.ends_with?(path, ".html") do
        sources = Regex.scan(~r/\s(?:src|href)="(https?:)?\/\/[^"]+"/, html)
        # only outbound <a> links may leave the site; no src ever does
        refute html =~ ~r/\ssrc="(https?:)?\/\//, "#{path}: external src"
        assert is_list(sources)
      end
    end
  end

  describe "_headers and the CSP" do
    test "the CSP allows exactly the sha256 of the two inline scripts", %{tree: tree} do
      expected = "sha256-" <> Base.encode64(:crypto.hash(:sha256, @head_js))
      rules = "sha256-" <> Base.encode64(:crypto.hash(:sha256, Site.Speculation.rules()))

      assert page(tree, "_headers") =~
               "script-src 'self' '#{expected}' '#{rules}' https://static.cloudflareinsights.com;"

      [inline] =
        Regex.scan(~r{<script>(.*?)</script>}s, page(tree, "index.html"))
        |> Enum.map(&List.last/1)

      assert "sha256-" <> Base.encode64(:crypto.hash(:sha256, inline)) == expected
    end

    test "_headers matches Headers.render/1", %{tree: tree} do
      hashes = [Headers.script_hash(@head_js), Headers.script_hash(Site.Speculation.rules())]
      assert page(tree, "_headers") == Headers.render(hashes)
    end

    test "_headers always allows the two Cloudflare Web Analytics hosts", %{tree: tree} do
      headers = page(tree, "_headers")

      assert headers =~ "script-src 'self' 'sha256-"
      assert headers =~ "' https://static.cloudflareinsights.com;"
      assert headers =~ "connect-src 'self' https://cloudflareinsights.com;"
    end

    test "no page carries a beacon, because Cloudflare injects it at the edge", %{tree: tree} do
      for {path, content} <- tree do
        refute content =~ "beacon.min.js", "#{path}: beacon script"
        refute content =~ "data-cf-beacon", "#{path}: beacon token"
      end
    end

    test "the Cloudflare hosts appear in _headers and nowhere else", %{tree: tree} do
      for {path, content} <- tree, path != "_headers" do
        refute content =~ "cloudflareinsights", "#{path}: Cloudflare host"
      end
    end
  end

  describe "determinism" do
    test "two builds are byte-identical" do
      content = fixture_copy()
      a = build_fixtures(content: content)
      b = build_fixtures(content: content)

      assert read_tree(a) == read_tree(b)
      assert Build.tree_hash(a) == Build.tree_hash(b)
      assert Build.tree_hash(a) =~ ~r/\A[0-9a-f]{64}\z/
    end

    test "the tree hash changes with content and with paths" do
      out = build_fixtures()
      before = Build.tree_hash(out)

      File.write!(Path.join(out, "robots.txt"), "User-agent: *\nDisallow: /\n")
      changed = Build.tree_hash(out)
      assert changed != before

      File.rename!(Path.join(out, "robots.txt"), Path.join(out, "robots2.txt"))
      assert Build.tree_hash(out) != changed
    end

    test "no build timestamp leaks into the output", %{tree: tree} do
      for {path, content} <- tree, String.ends_with?(path, [".html", "_headers", ".txt"]) do
        refute content =~ ~r/\b20\d\d-\d\d-\d\dT\d\d:\d\d/, "#{path}: looks like a timestamp"
      end
    end
  end

  describe "safety" do
    test "refuses an output directory that would delete the sources" do
      content = fixture_copy()

      for out <- [".", File.cwd!(), "..", "/", "assets", "templates", "lib", "test", content] do
        assert_raise Site.Error, ~r/refusing to use/, fn ->
          Build.run(content: content, out: out)
        end
      end
    end

    test "content errors leave the previous output in place" do
      out = build_fixtures()
      bad = minimal_content(%{"notes/n.md" => "---\ntitle: x\n---\n"})

      assert_raise Site.Error, fn -> Build.run(content: bad, out: out) end
      assert File.exists?(Path.join(out, "index.html"))
    end

    test "two entries with one slug fail the build, naming both files, writing nothing" do
      entry = "---\ntitle: N\ndate: 2026-10-28\n---\nbody"

      dir =
        minimal_content(%{"essays/same.md" => entry, "notes/2026-10-28-same.md" => entry})

      out = Path.join(tmp_dir(), "dist")

      error =
        assert_raise Site.Error, fn -> Build.run(content: dir, out: out) end

      assert error.message =~ ~s(duplicate slug "same")
      assert error.message =~ "essays/same.md"
      assert error.message =~ "notes/2026-10-28-same.md"
      refute File.exists?(out)
    end

    test "a reserved slug fails the build" do
      dir = minimal_content(%{"notes/robots.txt.md" => "---\ntitle: N\ndate: 2026-10-28\n---\nb"})
      out = Path.join(tmp_dir(), "dist")

      error =
        assert_raise Site.Error, fn -> Build.run(content: dir, out: out) end

      assert error.message =~ ~s(slug "robots.txt" is reserved)
      refute File.exists?(out)
    end

    test "a missing head.js is a clear error" do
      assets = Path.join(tmp_dir(), "assets")
      File.mkdir_p!(assets)

      assert_raise Site.Error, ~r/head\.js/, fn ->
        Build.run(
          content: fixture_copy(),
          out: Path.join(tmp_dir(), "dist"),
          assets: assets
        )
      end
    end

    test "a head.js that could close its own script tag is refused" do
      assets = Path.join(tmp_dir(), "assets")
      File.mkdir_p!(Path.join(assets, "js"))
      File.write!(Path.join(assets, "js/head.js"), "var x = '</script><b>';")

      assert_raise Site.Error, ~r/</, fn ->
        Build.run(
          content: fixture_copy(),
          out: Path.join(tmp_dir(), "dist"),
          assets: assets
        )
      end
    end
  end
end
