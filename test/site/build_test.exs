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
               "<title>Yoan Faure — security engineer who builds</title>"

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

    test "the page sets the lang, with no field preset attribute and no transition switch",
         %{tree: tree} do
      for path <- @pages do
        assert page(tree, path) =~ ~s(<html lang="en">), path
        refute page(tree, path) =~ "data-field=", path
        refute page(tree, path) =~ "data-vt", path
      end
    end

    test "head.js restores the theme, and nothing else" do
      assert @head_js =~ "localStorage.getItem('theme')"
      refute @head_js =~ "sessionStorage"
      refute @head_js =~ "field"
    end

    test "the stylesheet is linked and no script is deferred wrongly", %{tree: tree} do
      html = page(tree, "index.html")
      assert html =~ ~s(<link rel="stylesheet" href="/assets/css/site.css">)
      refute html =~ "transitions.css"
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

        assert html =~ ~s(<button class="theme-toggle" type="button" aria-label="Toggle theme">),
               path

        assert html =~ ~s(<main id="main">), path
        assert html =~ ~s(<footer class="site-footer">), path
        assert html =~ ~s(<a href="mailto:hi@yoanfaure.com">hi@yoanfaure.com</a>), path

        assert html =~
                 ~s(<a href="https://linkedin.com/in/yoan-faure" rel="noopener">linkedin</a>),
               path
      end
    end

    test "the header is the name and the theme toggle, and nothing else", %{tree: tree} do
      for path <- @pages do
        html = page(tree, path)
        [header] = Regex.run(~r{<header class="site-header">.*?</header>}s, html)

        assert header =~ ~s(<a class="brand" href="/">yoan faure</a>), path
        assert header =~ ~s(<button class="theme-toggle"), path
        assert length(Regex.scan(~r/<a[\s>]/, header)) == 1, path
        assert length(Regex.scan(~r/<button[\s>]/, header)) == 1, path

        # no navigation anywhere on the page
        refute html =~ "<nav", path
        refute html =~ "site-nav", path
        refute html =~ "aria-current", path
      end
    end

    test "the footer says unversioned or links the HEAD commit", %{tree: tree} do
      html = page(tree, "index.html")

      assert html =~ ~s(<p class="footer-build">built from <span>unversioned</span></p>) or
               html =~
                 ~r|built from <a href="https://github.com/y0anfa/website/commit/[0-9a-f]{40}">[0-9a-f]{7}(-dirty)?</a>|
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
      assert intro_html =~ ~s(<p class="contact"><a href="mailto:hi@yoanfaure.com">)
    end

    test "the log lists every entry in order, hashes as dots", %{tree: tree} do
      html = page(tree, "index.html")

      titles =
        Regex.scan(~r{<a class="log-title" href="([^"]+)">}, html)
        |> Enum.map(&List.last/1)

      assert titles == [
               "/second-essay/",
               "/widget/",
               "/small-note/",
               "/escape-me/",
               "/first-essay/"
             ]

      assert length(Regex.scan(~s(<a class="log-hash">·······</a>) |> Regex.compile!(), html)) ==
               5

      assert html =~ ~s(<time class="log-date" datetime="2026-10-28">2026-10-28</time>)
      assert html =~ ~s(<span class="log-type">project</span>)
    end

    test "the log is the only list: no list pages, and no link to one", %{tree: tree} do
      html = page(tree, "index.html")

      assert length(Regex.scan(~r/class="log-row"/, html)) == 5
      refute html =~ ~r{href="/(essays|notes|projects|uses|cv)/}

      for {path, content} <- tree, String.ends_with?(path, ".html") do
        refute content =~ ~s(class="list-page"), path
        refute content =~ ~s(class="lede"), path
      end
    end

    test "each row says what the entry is: essay, note or project", %{tree: tree} do
      html = page(tree, "index.html")

      assert length(Regex.scan(~r{<span class="log-type">essay</span>}, html)) == 2
      assert length(Regex.scan(~r{<span class="log-type">note</span>}, html)) == 2
      assert length(Regex.scan(~r{<span class="log-type">project</span>}, html)) == 1
    end

    test "an empty log says so" do
      dir = minimal_content()
      out = Path.join(tmp_dir(), "dist")
      Build.run(content: dir, out: out)

      assert out |> Path.join("index.html") |> File.read!() =~
               ~s(<p class="empty">nothing here yet.</p>)
    end
  end

  describe "entries and the 404" do
    test "an article has the meta line, the body and the back link", %{tree: tree} do
      html = page(tree, "first-essay/index.html")

      assert html =~ ~s(<article class="prose">)

      assert html =~
               ~s(<p class="meta"><span>essay</span> · <time datetime="2026-03-28">2026-03-28</time> · <span>·······</span></p>)

      assert html =~ ~s(<h1>First essay</h1>)
      assert html =~ ~s(<h2 id="a-heading">)
      assert html =~ ~s(<p class="back"><a href="/">← log</a></p>)
      assert html =~ "<table>"
      assert html =~ ~s(<pre><code class="language-sh">)

      note = page(tree, "small-note/index.html")
      assert note =~ ~s(<p class="back"><a href="/">← log</a></p>)

      assert note =~
               ~s(<p class="meta"><span>note</span> · <time datetime="2026-10-28">2026-10-28</time> · <span>·······</span></p>)
    end

    test "raw HTML in Markdown is never rendered", %{tree: tree} do
      html = page(tree, "first-essay/index.html")

      refute html =~ "<script>alert"
      refute html =~ "<b>bold</b>"
      refute html =~ "javascript:"
      assert html =~ "&lt;script&gt;alert(1)&lt;/script&gt;"
    end

    test "a project has h1, tagline, meta line and body", %{tree: tree} do
      html = page(tree, "widget/index.html")

      assert html =~ ~s(<article class="prose project">)

      assert html =~
               ~r{<h1>widget</h1>\s*<p class="tagline">A small widget for the fixtures.</p>}

      assert html =~
               ~s(<p class="meta"><span>active</span> · <span>Elixir, YAML</span> · <a href="https://example.com/widget">example.com/widget</a></p>)

      assert html =~ "<li>one</li>"
      assert html =~ ~s(<p class="back"><a href="/">← log</a></p>)
    end

    test "the 404 page is a terminal", %{tree: tree} do
      html = page(tree, "404.html")

      assert html =~
               ~s(<pre class="terminal">zsh: no such file or directory: <span data-path>unknown</span></pre>)

      assert html =~ ~s(<pre class="terminal prompt"><a href="/">cd ~</a></pre>)
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
