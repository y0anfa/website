defmodule Site.BuildTest do
  use ExUnit.Case, async: true

  import Site.TestHelpers

  alias Site.{Build, Headers}

  @head_js File.read!("assets/js/head.js") |> String.trim()

  @pages ~w(
    404.html
    cv/index.html
    essays/first-essay/index.html
    essays/index.html
    essays/second-essay/index.html
    index.html
    notes/escape-me/index.html
    notes/index.html
    notes/small-note/index.html
    projects/index.html
    projects/widget/index.html
    uses/index.html
  )

  # One shared, read-only build of the fixtures; tests that change things build their own.
  setup_all do
    out = build_fixtures()
    %{tree: read_tree(out)}
  end

  defp page(tree, path), do: Map.fetch!(tree, path)

  describe "output" do
    test "writes every page of the URL map, plus _headers and robots.txt", %{tree: tree} do
      files = Map.keys(tree)

      for path <- @pages ++ ["_headers", "robots.txt"],
          do: assert(path in files, "missing #{path}")

      non_assets = Enum.reject(files, &String.starts_with?(&1, "assets/"))
      assert Enum.sort(non_assets) == Enum.sort(@pages ++ ["_headers", "robots.txt"])
    end

    test "does not write drafts", %{tree: tree} do
      refute Map.has_key?(tree, "essays/an-unfinished-draft/index.html")
      refute tree |> page("essays/index.html") |> String.contains?("unfinished")
    end

    test "writes drafts with drafts: true" do
      tree = [drafts: true] |> build_fixtures() |> read_tree()
      assert page(tree, "essays/an-unfinished-draft/index.html") =~ "An unfinished draft"
      assert page(tree, "index.html") =~ "An unfinished draft"
    end

    test "robots.txt allows everything and names no sitemap", %{tree: tree} do
      assert page(tree, "robots.txt") == "User-agent: *\nAllow: /\n"
    end

    test "copies assets verbatim, skipping dotfiles", %{tree: tree} do
      for rel <- ["css/site.css", "js/head.js", "js/theme.js", "js/404.js", "favicon.svg"] do
        assert page(tree, "assets/" <> rel) == File.read!("assets/" <> rel)
      end

      refute Enum.any?(Map.keys(tree), &String.contains?(&1, ".DS_Store"))
    end

    test "cleans stale files from the output directory" do
      out = build_fixtures()
      File.write!(Path.join(out, "stale.html"), "old")
      File.mkdir_p!(Path.join(out, "old-dir"))
      File.write!(Path.join(out, "old-dir/x.html"), "old")

      Build.run(content: fixture_copy(), out: out, beacon_token: nil)

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
      Build.run(content: fixture_copy(), out: out, assets: assets, beacon_token: nil)

      assert Build.files(Path.join(out, "assets")) == ["js/head.js", "js/ok.js"]
    end
  end

  describe "head" do
    test "titles", %{tree: tree} do
      assert page(tree, "index.html") =~
               "<title>Yoan Faure — security engineer who builds</title>"

      assert page(tree, "essays/index.html") =~ "<title>essays — Yoan Faure</title>"

      assert page(tree, "essays/first-essay/index.html") =~
               "<title>First essay — Yoan Faure</title>"

      assert page(tree, "uses/index.html") =~ "<title>uses — Yoan Faure</title>"
      assert page(tree, "404.html") =~ "<title>Not found — Yoan Faure</title>"
    end

    test "description, canonical, Open Graph, Twitter card, favicon, font preload", %{tree: tree} do
      html = page(tree, "essays/second-essay/index.html")

      assert html =~
               ~s(<meta name="description" content="A second essay, with its own description.">)

      assert html =~ ~s(<link rel="canonical" href="https://yoanfau.re/essays/second-essay/">)
      assert html =~ ~s(<meta property="og:title" content="Second essay — Yoan Faure">)

      assert html =~
               ~s(<meta property="og:description" content="A second essay, with its own description.">)

      assert html =~
               ~s(<meta property="og:url" content="https://yoanfau.re/essays/second-essay/">)

      assert html =~ ~s(<meta property="og:type" content="article">)
      assert html =~ ~s(<meta name="twitter:card" content="summary">)
      assert html =~ ~s(<link rel="icon" href="/assets/favicon.svg")

      assert html =~
               ~s(<link rel="preload" href="/assets/fonts/JetBrainsMono-Regular.woff2" as="font" type="font/woff2" crossorigin>)

      assert page(tree, "index.html") =~ ~s(<link rel="canonical" href="https://yoanfau.re/">)
      assert page(tree, "index.html") =~ ~s(<meta property="og:type" content="website">)
    end

    test "the 404 page has no canonical URL", %{tree: tree} do
      refute page(tree, "404.html") =~ "canonical"
      refute page(tree, "404.html") =~ "og:url"
    end

    test "the page sets the lang and the default field preset", %{tree: tree} do
      for path <- @pages do
        assert page(tree, path) =~ ~s(<html lang="en" data-field="topo">), path
      end
    end

    test "head.js offers the topo and water presets, topo first, and no wind" do
      assert @head_js =~ ~r/field: \['topo', 'water'\]/
      refute @head_js =~ "wind"
    end

    test "the stylesheet is linked and no script is deferred wrongly", %{tree: tree} do
      html = page(tree, "index.html")
      assert html =~ ~s(<link rel="stylesheet" href="/assets/css/site.css">)
      assert html =~ ~s(<script defer src="/assets/js/theme.js"></script>)
    end
  end

  describe "shell" do
    test "every page has the skip link, header, main, footer", %{tree: tree} do
      for path <- @pages do
        html = page(tree, path)
        assert html =~ ~s(<a class="skip-link" href="#main">), path
        assert html =~ ~s(<header class="site-header">), path
        assert html =~ ~s(<a class="brand" href="/">yoan faure</a>), path
        assert html =~ ~s(<nav class="site-nav" aria-label="Primary">), path

        assert html =~ ~s(<button class="theme-toggle" type="button" aria-label="Toggle theme">),
               path

        assert html =~ ~s(<main id="main">), path
        assert html =~ ~s(<footer class="site-footer">), path
        assert html =~ ~s(<a href="mailto:hello@yoanfau.re">hello@yoanfau.re</a>), path

        assert html =~
                 ~s(<a href="https://linkedin.com/in/yoan-faure" rel="noopener">linkedin</a>),
               path
      end
    end

    test "the nav lists the five sections in order", %{tree: tree} do
      html = page(tree, "essays/index.html")
      [_, nav] = Regex.run(~r{<nav class="site-nav".*?</nav>}s, html) |> then(&[nil, hd(&1)])
      labels = Regex.scan(~r{>([a-z]+)</a>}, nav) |> Enum.map(&List.last/1)
      assert labels == ~w(essays notes projects uses cv)
    end

    test "aria-current marks the active section", %{tree: tree} do
      assert page(tree, "essays/index.html") =~
               ~s(<a href="/essays/" aria-current="page">essays</a>)

      assert page(tree, "uses/index.html") =~ ~s(<a href="/uses/" aria-current="page">uses</a>)
      assert page(tree, "cv/index.html") =~ ~s(<a href="/cv/" aria-current="page">cv</a>)
      # inside a section the section is marked as the current parent
      assert page(tree, "notes/small-note/index.html") =~
               ~s(<a href="/notes/" aria-current="true">notes</a>)

      assert page(tree, "projects/widget/index.html") =~
               ~s(<a href="/projects/" aria-current="true">projects</a>)

      refute page(tree, "index.html") =~ "aria-current"
      refute page(tree, "404.html") =~ "aria-current"
      assert length(Regex.scan(~r/aria-current/, page(tree, "essays/index.html"))) == 1
    end

    test "the footer says unversioned or links the HEAD commit", %{tree: tree} do
      html = page(tree, "index.html")

      assert html =~ ~s(<p class="footer-build">built from <span>unversioned</span></p>) or
               html =~
                 ~r|built from <a href="https://github.com/y0anfa/yoanfau.re/commit/[0-9a-f]{40}">[0-9a-f]{7}(-dirty)?</a>|
    end
  end

  describe "the field backdrop (SPEC section 7)" do
    @backdrop ~s(<div class="field" data-field-root aria-hidden="true">) <>
                ~s(<canvas class="field-canvas"></canvas></div>)

    test "every page has one backdrop root, right after the skip link and before the header",
         %{tree: tree} do
      for path <- @pages do
        html = page(tree, path)
        assert length(Regex.scan(~r/data-field-root/, html)) == 1, path
        assert length(Regex.scan(~r/<canvas/, html)) == 1, path

        {skip, _} = :binary.match(html, ~s(<a class="skip-link"))
        {field, _} = :binary.match(html, @backdrop)
        {header, _} = :binary.match(html, ~s(<header class="site-header">))
        {main, _} = :binary.match(html, ~s(<main id="main">))
        assert skip < field and field < header and header < main, path

        # the backdrop belongs to the page, not to its content
        refute html |> String.split(~s(<main id="main">)) |> List.last() =~ "data-field-root",
               path
      end
    end

    test "every page loads field.js as a module, and only field.js", %{tree: tree} do
      for path <- @pages do
        html = page(tree, path)

        assert length(
                 Regex.scan(~r{<script type="module" src="/assets/js/field\.js"></script>}, html)
               ) ==
                 1,
               path

        assert length(Regex.scan(~r/field\.js/, html)) == 1, path
        assert length(Regex.scan(~r/type="module"/, html)) == 1, path
      end
    end

    test "no page has a hero or a second field", %{tree: tree} do
      for path <- @pages do
        html = page(tree, path)
        refute html =~ ~s(class="hero"), path
        refute html =~ "data-hotspot", path
      end
    end
  end

  describe "home (SPEC section 7)" do
    test "is an intro and the log, with no hero or field section", %{tree: tree} do
      html = page(tree, "index.html")

      assert html =~ ~s(<div class="intro">)
      assert html =~ ~s(<section class="log-section" aria-labelledby="log-h">)
      assert html =~ ~s(<h2 id="log-h">log</h2>)
      assert html =~ ~s(<ol class="log">)

      [_, main] = String.split(html, ~s(<main id="main">))
      refute main =~ "hero"
      refute main =~ "field"
      refute main =~ "canvas"
      assert length(Regex.scan(~r/<section/, main)) == 1
      assert length(Regex.scan(~r/<h1/, html)) == 1
    end

    test "the intro comes before the log and holds h1, tagline, the Markdown and the contact line",
         %{tree: tree} do
      html = page(tree, "index.html")
      {main, _} = :binary.match(html, ~s(<main id="main">))
      {intro, _} = :binary.match(html, ~s(<div class="intro">))
      {log, _} = :binary.match(html, ~s(<section class="log-section"))
      assert main < intro and intro < log

      [_, intro_html] = Regex.run(~r{<div class="intro">(.*?)<section class="log-section"}s, html)

      assert intro_html =~
               ~r{\A\s*<h1>Test Person</h1>\s*<p class="tagline">Fixture tagline for the home page.</p>}

      assert intro_html =~ ~s(<p>This is the intro paragraph.)
      assert intro_html =~ ~s(<p class="contact"><a href="mailto:hello@yoanfau.re">)
    end

    test "the log lists every entry in order, hashes as dots", %{tree: tree} do
      html = page(tree, "index.html")

      titles =
        Regex.scan(~r{<a class="log-title" href="([^"]+)">}, html) |> Enum.map(&List.last/1)

      assert titles == [
               "/essays/second-essay/",
               "/projects/widget/",
               "/notes/small-note/",
               "/notes/escape-me/",
               "/essays/first-essay/"
             ]

      assert length(Regex.scan(~s(<a class="log-hash">·······</a>) |> Regex.compile!(), html)) ==
               5

      assert html =~ ~s(<time class="log-date" datetime="2026-10-28">2026-10-28</time>)
      assert html =~ ~s(<span class="log-type">project</span>)
    end

    test "list pages reuse the log, filtered by type", %{tree: tree} do
      essays = page(tree, "essays/index.html")
      assert essays =~ "<h1>essays</h1>"
      assert essays =~ ~s(<p class="lede">)
      assert length(Regex.scan(~r/class="log-row"/, essays)) == 2
      refute essays =~ "widget"

      assert length(Regex.scan(~r/class="log-row"/, page(tree, "notes/index.html"))) == 2
      assert length(Regex.scan(~r/class="log-row"/, page(tree, "projects/index.html"))) == 1
    end

    test "an empty section says so" do
      dir = minimal_content()
      out = Path.join(tmp_dir(), "dist")
      Build.run(content: dir, out: out, beacon_token: nil)

      assert out |> Path.join("essays/index.html") |> File.read!() =~
               ~s(<p class="empty">nothing here yet.</p>)
    end
  end

  describe "articles, projects, pages" do
    test "an article has the meta line, the body and the back link", %{tree: tree} do
      html = page(tree, "essays/first-essay/index.html")

      assert html =~ ~s(<article class="prose">)

      assert html =~
               ~s(<p class="meta"><span>essay</span> · <time datetime="2026-03-28">2026-03-28</time> · <span>·······</span></p>)

      assert html =~ "<h1>First essay</h1>"
      assert html =~ ~s(<h2 id="a-heading">)
      assert html =~ ~s(<p class="back"><a href="/essays/">← essays</a></p>)
      assert html =~ "<table>"
      assert html =~ ~s(<pre><code class="language-sh">)

      assert page(tree, "notes/small-note/index.html") =~ ~s(<a href="/notes/">← notes</a>)
    end

    test "raw HTML in Markdown is never rendered", %{tree: tree} do
      html = page(tree, "essays/first-essay/index.html")

      refute html =~ "<script>alert"
      refute html =~ "<b>bold</b>"
      refute html =~ "javascript:"
      assert html =~ "&lt;script&gt;alert(1)&lt;/script&gt;"
    end

    test "a project has h1, tagline, meta line and body", %{tree: tree} do
      html = page(tree, "projects/widget/index.html")

      assert html =~ ~s(<article class="prose project">)
      assert html =~ ~r{<h1>widget</h1>\s*<p class="tagline">A small widget for the fixtures.</p>}

      assert html =~
               ~s(<p class="meta"><span>active</span> · <span>Elixir, YAML</span> · <a href="https://example.com/widget">example.com/widget</a></p>)

      assert html =~ "<li>one</li>"
      assert html =~ ~s(<a href="/projects/">← projects</a>)
    end

    test "uses and cv are pages with a table", %{tree: tree} do
      for {path, title} <- [{"uses/index.html", "uses"}, {"cv/index.html", "cv"}] do
        html = page(tree, path)
        assert html =~ ~s(<article class="prose page">)
        assert html =~ "<h1>#{title}</h1>"
        assert html =~ "<table>"
      end
    end

    test "the 404 page is a terminal", %{tree: tree} do
      html = page(tree, "404.html")

      assert html =~
               ~s(<pre class="terminal">zsh: no such file or directory: <span data-path>unknown</span></pre>)

      assert html =~ ~s(<a href="/">cd ~</a>)
      assert html =~ ~s(<script defer src="/assets/js/404.js"></script>)
    end
  end

  describe "escaping" do
    test "titles and descriptions are escaped everywhere", %{tree: tree} do
      title = "Tom &amp; &quot;Jerry&quot; &lt;script&gt;alert(1)&lt;/script&gt;"

      for path <- ["index.html", "notes/index.html", "notes/escape-me/index.html"] do
        html = page(tree, path)
        assert html =~ title, path
        refute html =~ "<script>alert", path
      end

      html = page(tree, "notes/escape-me/index.html")
      assert html =~ "<title>#{title} — Yoan Faure</title>"

      assert html =~
               ~s(<meta name="description" content="A &quot;quoted&quot; &lt;description&gt; &amp; more">)

      assert html =~ "<h1>#{title}</h1>"
    end

    test "no page contains an unexpected inline script", %{tree: tree} do
      for {path, html} <- tree, String.ends_with?(path, ".html") do
        inline =
          Regex.scan(~r{<script(?![^>]*\ssrc=)[^>]*>(.*?)</script>}s, html)
          |> Enum.map(&List.last/1)

        assert inline == [@head_js], "#{path}: inline scripts other than head.js"
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
    test "the CSP allows exactly the sha256 of the inline head script", %{tree: tree} do
      expected = "sha256-" <> Base.encode64(:crypto.hash(:sha256, @head_js))
      assert page(tree, "_headers") =~ "script-src 'self' '#{expected}'; style-src 'self';"

      [inline] =
        Regex.scan(~r{<script>(.*?)</script>}s, page(tree, "index.html"))
        |> Enum.map(&List.last/1)

      assert "sha256-" <> Base.encode64(:crypto.hash(:sha256, inline)) == expected
    end

    test "_headers matches Headers.render/2", %{tree: tree} do
      assert page(tree, "_headers") ==
               Headers.render(Headers.script_hash(@head_js), beacon: false)
    end

    test "without a beacon token there is no Cloudflare anywhere", %{tree: tree} do
      for {_path, content} <- tree, is_binary(content) do
        refute content =~ "cloudflareinsights"
      end

      refute Map.fetch!(tree, "_headers") =~ "cloudflare"
    end

    test "with a beacon token the script tag and both hosts appear" do
      tree = [beacon_token: "abc123DEF-_9"] |> build_fixtures() |> read_tree()

      for path <- @pages do
        assert page(tree, path) =~
                 ~s(<script defer src="https://static.cloudflareinsights.com/beacon.min.js" data-cf-beacon='{"token":"abc123DEF-_9"}'></script>),
               path
      end

      headers = page(tree, "_headers")
      assert headers =~ "script-src 'self' 'sha256-"
      assert headers =~ "' https://static.cloudflareinsights.com;"
      assert headers =~ "connect-src 'self' https://cloudflareinsights.com;"
    end

    test "an odd beacon token is refused" do
      assert_raise Site.Error, ~r/CF_BEACON_TOKEN/, fn ->
        build_fixtures(beacon_token: ~s(x'"><script>))
      end
    end

    test "an empty beacon token means no beacon" do
      tree = [beacon_token: "  "] |> build_fixtures() |> read_tree()
      refute page(tree, "index.html") =~ "cloudflareinsights"
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
          Build.run(content: content, out: out, beacon_token: nil)
        end
      end
    end

    test "content errors leave the previous output in place" do
      out = build_fixtures()
      bad = minimal_content(%{"notes/n.md" => "---\ntitle: x\n---\n"})

      assert_raise Site.Error, fn -> Build.run(content: bad, out: out, beacon_token: nil) end
      assert File.exists?(Path.join(out, "index.html"))
    end

    test "a missing head.js is a clear error" do
      assets = Path.join(tmp_dir(), "assets")
      File.mkdir_p!(assets)

      assert_raise Site.Error, ~r/head\.js/, fn ->
        Build.run(
          content: fixture_copy(),
          out: Path.join(tmp_dir(), "dist"),
          assets: assets,
          beacon_token: nil
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
          assets: assets,
          beacon_token: nil
        )
      end
    end
  end
end
