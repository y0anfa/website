defmodule Site.TransitionsTest do
  use ExUnit.Case, async: true

  import Site.TestHelpers

  alias Site.{Content, Entry, Headers, Log, Speculation, Transitions}

  doctest Site.Transitions

  @css File.read!("assets/css/site.css")
  @code Regex.replace(~r{/\*.*?\*/}s, @css, "")
  @head_js "assets/js/head.js" |> File.read!() |> String.trim()
  @theme_js File.read!("assets/js/theme.js")
  @node System.find_executable("node")

  # The fixture entries, by slug: two essays, two notes and a project.
  @slugs ~w(escape-me first-essay second-essay small-note widget)

  # <custom-ident> as CSS defines it, without escapes: what the generated names must be.
  @ident ~r/\A-?[_a-zA-Z][_a-zA-Z0-9-]*\z/
  @css_wide ~w(initial inherit unset revert revert-layer default none auto)

  setup_all do
    %{tree: build_fixtures() |> read_tree()}
  end

  defp page(tree, path), do: Map.fetch!(tree, path)

  defp entries, do: fixtures() |> Content.load() |> Content.entries()

  # The rules of a CSS source as {selector, body}, comments stripped, in order. Rules inside
  # an at-rule (@media) are found too; at-rule preludes are not rules.
  defp rules(css) do
    css = Regex.replace(~r{/\*.*?\*/}s, css, "")

    for [_, selector, body] <- Regex.scan(~r/([^{}]+)\{([^{}]*)\}/, css) do
      {selector |> String.replace(~r/\s+/, " ") |> String.trim(), String.trim(body)}
    end
  end

  # The body of the one rule with exactly this selector.
  defp rule!(css, selector) do
    case for {^selector, body} <- rules(css), do: body do
      [body] -> body
      other -> flunk("expected one rule for #{selector}, found #{length(other)}")
    end
  end

  describe "class/1 and name/1" do
    test "prefix the slug, so a slug that starts with a digit is still a valid identifier" do
      assert Transitions.class("rhino") == "vt-rhino"
      assert Transitions.name("rhino") == "entry-rhino"
      assert Transitions.class("2026-recap") == "vt-2026-recap"
      assert Transitions.name("2026-recap") == "entry-2026-recap"
      assert Transitions.class("404-lessons") == "vt-404-lessons"

      for slug <- ["rhino", "2026-recap", "404-lessons", "9", "a-b-c-1"] do
        assert Transitions.class(slug) =~ @ident
        assert Transitions.name(slug) =~ @ident
        refute Transitions.name(slug) in @css_wide
      end
    end

    test "class and name differ, so the class never doubles as a name" do
      refute Transitions.class("x") == Transitions.name("x")
    end

    test "refuse anything that is not a kebab-case slug, instead of writing a broken rule" do
      for slug <- [
            "",
            "Upper",
            "has space",
            "under_score",
            "-leading",
            "trailing-",
            "double--hyphen",
            "dot.dot",
            "a{}b",
            "a,b",
            "é",
            "slash/slash",
            "new\nline"
          ] do
        assert_raise ArgumentError, ~r/cannot name a view transition/, fn ->
          Transitions.class(slug)
        end

        assert_raise ArgumentError, fn -> Transitions.name(slug) end
      end
    end

    test "every slug the content loader accepts is accepted here" do
      content =
        minimal_content(%{
          "notes/2026-10-28-a1.md" => "---\ntitle: a\ndate: 2026-10-28\n---\n",
          "notes/9-lives.md" => "---\ntitle: b\ndate: 2026-10-28\n---\n",
          "notes/x-y-z-0.md" => "---\ntitle: c\ndate: 2026-10-28\n---\n"
        })

      slugs = content |> Content.load() |> Content.entries() |> Enum.map(& &1.slug)
      assert Enum.sort(slugs) == ["9-lives", "a1", "x-y-z-0"]
      for slug <- slugs, do: assert(Transitions.class(slug) =~ @ident)
    end
  end

  describe "the generated stylesheet" do
    test "has one rule per entry, scoped to the morph prototype" do
      css = Transitions.css(entries())

      assert length(rules(css)) == length(@slugs)

      for slug <- @slugs do
        assert rule!(css, ~s(:root[data-vt="morph"] .vt-#{slug})) ==
                 "view-transition-name: entry-#{slug};"
      end

      # nothing else: no other selector, no other property, nothing outside a rule
      for {selector, body} <- rules(css) do
        assert selector =~ ~r/\A:root\[data-vt="morph"\] \.vt-[a-z0-9-]+\z/
        assert body =~ ~r/\Aview-transition-name: entry-[a-z0-9-]+;\z/
      end

      refute css =~ "@"
      refute css =~ "!important"
    end

    test "each rule's name is the entry's own, and every name and class is a valid identifier" do
      for {selector, body} <- rules(Transitions.css(entries())) do
        [_, class] = Regex.run(~r/\.(vt-[^\s{]+)\z/, selector)
        [_, name] = Regex.run(~r/view-transition-name: ([^;]+);/, body)

        assert class =~ @ident
        assert name =~ @ident
        refute name in @css_wide
        assert String.replace_prefix(class, "vt-", "entry-") == name
      end
    end

    test "names are unique: no two entries share a rule" do
      names = for {_, body} <- rules(Transitions.css(entries())), do: body
      assert names == Enum.uniq(names)
      assert length(names) == length(@slugs)
    end

    test "is in slug order, whatever order the entries come in" do
      shuffled = Enum.shuffle(entries())
      css = Transitions.css(shuffled)

      assert css == Transitions.css(entries())
      assert css == Transitions.css(Enum.reverse(shuffled))

      classes = for {selector, _} <- rules(css), do: selector
      assert classes == Enum.sort(classes)
    end

    test "has a header that says it is generated, and nothing but rules after it" do
      css = Transitions.css(entries())

      assert String.starts_with?(
               css,
               "/* Generated by the build (Site.Transitions). Do not edit."
             )

      assert String.ends_with?(css, "}\n")
      assert css == String.trim_trailing(css) <> "\n"
      assert length(Regex.scan(~r/\{/, css)) == length(Regex.scan(~r/\}/, css))
      refute css =~ ~r/\d{4}-\d{2}-\d{2}T/
    end

    test "with no entries is just the header" do
      css = Transitions.css([])
      assert rules(css) == []
      assert css =~ "Generated by the build"
    end

    test "files/1 is one file under assets/css, built from every entry" do
      content = Content.load(fixtures())

      assert [{"assets/css/transitions.css", css}] = Transitions.files(content)
      assert Transitions.file_path() == "assets/css/transitions.css"
      assert css == Transitions.css(Content.entries(content))
    end

    test "is written by the build, is the same on every build, and covers drafts only when asked" do
      content = fixture_copy()
      a = [content: content] |> build_fixtures() |> read_tree()
      b = [content: content] |> build_fixtures() |> read_tree()

      assert Map.fetch!(a, "assets/css/transitions.css") ==
               Map.fetch!(b, "assets/css/transitions.css")

      assert length(rules(a["assets/css/transitions.css"])) == 5
      refute a["assets/css/transitions.css"] =~ "an-unfinished-draft"

      drafts = [content: content, drafts: true] |> build_fixtures() |> read_tree()
      assert length(rules(drafts["assets/css/transitions.css"])) == 6
      assert drafts["assets/css/transitions.css"] =~ ".vt-an-unfinished-draft"
    end

    test "the built file is the module's output, and the build refuses a source file in its place",
         %{tree: tree} do
      assert page(tree, "assets/css/transitions.css") == Transitions.css(entries())

      assets = Path.join(tmp_dir(), "assets")
      File.mkdir_p!(Path.join(assets, "js"))
      File.mkdir_p!(Path.join(assets, "css"))
      File.write!(Path.join(assets, "js/head.js"), "(function(){})();\n")
      File.write!(Path.join(assets, "css/transitions.css"), "/* by hand */")

      error =
        assert_raise Site.Error, fn ->
          Site.Build.run(
            content: fixture_copy(),
            out: Path.join(tmp_dir(), "dist"),
            assets: assets
          )
        end

      assert error.message =~ "is generated by the build"
    end

    test "is no inline style: the CSP allows only same-origin stylesheets", %{tree: tree} do
      assert page(tree, "_headers") =~ "style-src 'self';"

      for path <- ["index.html", "404.html", "widget/index.html"] do
        html = page(tree, path)
        assert html =~ ~s(<link rel="stylesheet" href="/assets/css/transitions.css">), path
        refute html =~ ~r/<style[\s>]/i, path
      end
    end
  end

  describe "the markup" do
    test "a log row's title link carries the class of its entry", %{tree: tree} do
      home = page(tree, "index.html")

      rows = Regex.scan(~r{<a class="log-title (vt-[^"]+)" href="/([^/"]+)/">}, home)
      assert length(rows) == 5

      for [_, class, slug] <- rows do
        assert class == "vt-" <> slug
        assert slug in @slugs
      end

      # the log row data carries it too, for the template
      for entry <- entries(), do: assert(Log.row(entry).vt == "vt-" <> entry.slug)
    end

    test "every entry page's h1 carries the same class, for articles and projects", %{tree: tree} do
      for slug <- @slugs do
        html = page(tree, "#{slug}/index.html")
        assert [[_, class]] = Regex.scan(~r{<h1 class="(vt-[^"]+)">}, html), slug
        assert class == "vt-" <> slug
        assert length(Regex.scan(~r/<h1[\s>]/, html)) == 1, slug
      end

      # one article and one project, so both templates are covered
      assert page(tree, "first-essay/index.html") =~ ~s(<article class="prose">)
      assert page(tree, "widget/index.html") =~ ~s(<article class="prose project">)
    end

    test "a log title and the h1 it leads to share a class, and a class is used once per page",
         %{tree: tree} do
      home = page(tree, "index.html")

      classes =
        for [_, class, href] <- Regex.scan(~r{class="log-title (vt-[^"]+)" href="([^"]+)"}, home) do
          [_, h1] =
            Regex.run(
              ~r{<h1 class="(vt-[^"]+)">},
              page(tree, String.trim(href, "/") <> "/index.html")
            )

          assert h1 == class
          class
        end

      assert length(classes) == length(Enum.uniq(classes))

      for class <- classes do
        assert length(Regex.scan(~r/\b#{class}\b/, home)) == 1, class
      end
    end

    test "the home's own h1 and the 404 are not shared elements", %{tree: tree} do
      for path <- ["index.html", "404.html"] do
        refute page(tree, path) =~ ~r{<h1[^>]*class="[^"]*vt-}, path
      end
    end

    test "every page opts into the default prototype and links the generated stylesheet", %{
      tree: tree
    } do
      for {path, html} <- tree, String.ends_with?(path, ".html") do
        assert html =~ ~s(<html lang="en" data-vt="morph">), path

        {site, _} = :binary.match(html, ~s(<link rel="stylesheet" href="/assets/css/site.css">))

        {gen, _} =
          :binary.match(html, ~s(<link rel="stylesheet" href="/assets/css/transitions.css">))

        {head_end, _} = :binary.match(html, "</head>")
        assert site < gen and gen < head_end, path
      end
    end

    test "the templates only add the class, through the escaping helper" do
      log = File.read!("templates/_log.html.eex")
      assert log =~ ~S|<a class="log-title <%= escape(row.vt) %>" href=|

      for file <- ["templates/article.html.eex", "templates/project.html.eex"] do
        assert File.read!(file) =~
                 ~S|<h1 class="<%= escape(Site.Transitions.class(@entry.slug)) %>">|
      end

      assert File.read!("templates/layout.html.eex") =~ ~S(<html lang="en" data-vt="morph">)
    end

    test "a class cannot be forged through a hostile title or slug" do
      entry = %Entry{
        type: :note,
        slug: "x",
        title: ~S|" onfocus="alert(1)|,
        date: ~D[2026-10-28],
        html: "<p>ok</p>"
      }

      html = Site.Templates.log(%{rows: [Log.row(entry)]})
      assert html =~ ~s(<a class="log-title vt-x" href="/x/">)
      refute html =~ ~s(onfocus="alert)

      assert_raise ArgumentError, fn -> Log.row(%{entry | slug: ~S|x" onfocus="y|}) end
    end
  end

  describe "site.css" do
    test "opts in to cross-document view transitions for people who have not asked for less motion" do
      assert @css =~
               ~r/@media \(prefers-reduced-motion: no-preference\)\s*\{\s*@view-transition\s*\{/

      [_, body] =
        Regex.run(
          ~r/@media \(prefers-reduced-motion: no-preference\)\s*\{\s*@view-transition\s*\{(.*?)\}/s,
          @css
        )

      assert body =~ "navigation: auto;"
      assert body =~ "types: page;"
    end

    test "turns transitions off under prefers-reduced-motion: reduce" do
      assert [_, body] =
               Regex.run(
                 ~r/@media \(prefers-reduced-motion: reduce\)\s*\{\s*@view-transition\s*\{(.*?)\}/s,
                 @css
               )

      assert body =~ "navigation: none;"
      refute body =~ "navigation: auto"

      # exactly two @view-transition rules, one per query: whichever wins, a reduced-motion
      # visitor never matches the one that says auto
      assert length(Regex.scan(~r/@view-transition/, @code)) == 2
    end

    test "has the duration token at 200ms with ease-out, used by every group" do
      root = rule!(@css, ":root")
      assert root =~ "--vt-duration: 200ms;"
      assert root =~ "--vt-ease: ease-out;"

      group =
        rule!(
          @css,
          ":root:active-view-transition-type(page)::view-transition-group(*), " <>
            ":root:active-view-transition-type(theme)::view-transition-group(*)"
        )

      assert group =~ "animation-duration: var(--vt-duration);"
      assert group =~ "animation-timing-function: var(--vt-ease);"

      # no other duration or easing is hard-coded in a transition rule
      for {selector, body} <- rules(@css), selector =~ "::view-transition" do
        refute body =~ ~r/animation(-duration)?:[^;]*\d+m?s/, selector
      end
    end

    test "every view-transition rule waits for a transition type, so the theme toggle only gets its own" do
      transition_rules =
        for {selector, _} = rule <- rules(@css), selector =~ "::view-transition", do: rule

      assert length(transition_rules) == 5

      for {selector, _} <- transition_rules, part <- String.split(selector, ", ") do
        assert part =~ ~r/\A:root/, selector
        assert part =~ ~r/:active-view-transition-type\((page|theme)\)/, selector
      end

      # the theme transition is styled once, for every prototype alike; the rest is page only
      theme = for {s, _} <- transition_rules, s =~ "(theme)", do: s
      assert length(theme) == 1
      refute Enum.any?(theme, &(&1 =~ "[data-vt"))

      for {s, _} <- transition_rules, s =~ "[data-vt", do: refute(s =~ "(theme)")
    end

    test "each prototype is scoped by :root[data-vt]" do
      for variant <- ~w(morph fade rise) do
        assert @css =~ ~s(:root[data-vt="#{variant}"]), variant
      end

      # the old and new images are only styled for the rise prototype
      for {selector, _} <- rules(@css), selector =~ ~r/::view-transition-(old|new)\(/ do
        assert selector =~ ~s|:root[data-vt="rise"]:active-view-transition-type(page)|, selector
      end

      # no rule outside the three values
      values =
        Regex.scan(~r/\[data-vt="([^"]*)"\]/, @code) |> Enum.map(&List.last/1) |> Enum.uniq()

      assert Enum.sort(values) == ~w(fade morph rise)
    end

    test "morph: the log title and the h1 shrink to their text, and the hovered title is plain when captured" do
      assert rule!(@css, ~s(:root[data-vt="morph"] .log-title)) == "justify-self: start;"

      h1 = rule!(@css, ~s(:root[data-vt="morph"] .prose > h1[class]))
      assert h1 =~ "width: fit-content;"
      assert h1 =~ "max-width: 100%;"

      hover =
        rule!(
          @css,
          ~s|:root[data-vt="morph"]:active-view-transition-type(page) | <>
            ".log-title:is(:hover, :focus-visible, :active)"
        )

      assert hover =~ "background: none;"
      assert hover =~ "color: inherit;"
    end

    test "fade: the header and the footer have their own names and do not glide" do
      assert rule!(@css, ~s(:root[data-vt="fade"] .site-header)) ==
               "view-transition-name: site-header;"

      assert rule!(@css, ~s(:root[data-vt="fade"] .site-footer)) ==
               "view-transition-name: site-footer;"

      still =
        rule!(
          @css,
          ~s|:root[data-vt="fade"]:active-view-transition-type(page)| <>
            "::view-transition-group(site-header), " <>
            ~s|:root[data-vt="fade"]:active-view-transition-type(page)| <>
            "::view-transition-group(site-footer)"
        )

      assert still == "animation-name: none;"
    end

    test "rise: the old page fades out, the new one fades in and rises 12px" do
      page = ~s|:root[data-vt="rise"]:active-view-transition-type(page)|

      assert rule!(@css, page <> "::view-transition-old(root)") == "animation-name: vt-fade-out;"
      assert rule!(@css, page <> "::view-transition-new(root)") == "animation-name: vt-rise-in;"
      assert rule!(@css, page <> "::view-transition") == "background: var(--bg);"

      assert @code =~
               ~r/@keyframes vt-rise-in\s*\{\s*from\s*\{\s*opacity: 0;\s*transform: translateY\(12px\);\s*\}\s*\}/

      assert @code =~ ~r/@keyframes vt-fade-out\s*\{\s*to\s*\{\s*opacity: 0;\s*\}\s*\}/
    end

    test "the field is left in the page's image: it has no view-transition-name" do
      refute rule!(@css, ".field") =~ "view-transition-name"
      refute @css =~ "view-transition-name: field"

      names = Regex.scan(~r/view-transition-name:\s*([^;]+);/, @code) |> Enum.map(&List.last/1)
      assert Enum.sort(names) == ["site-footer", "site-header"]
    end

    test "uses no JavaScript-driven or inline mechanism: no view-transition-class, no @import" do
      refute @css =~ "view-transition-class"
      refute @css =~ "@import"
    end
  end

  describe "head.js" do
    test "reads ?vt=, keeps it for the tab and only accepts the three prototypes" do
      assert @head_js =~ "URLSearchParams(location.search).get('vt')"
      assert @head_js =~ "sessionStorage.setItem('vt'"
      assert @head_js =~ "sessionStorage.getItem('vt')"
      assert @head_js =~ "setAttribute('data-vt'"
      assert @head_js =~ "/^(morph|fade|rise)$/"

      # never localStorage for the prototype: it is per tab
      refute @head_js =~ ~r/localStorage\.\w+\('vt'/
    end

    test "is tiny, wrapped in try/catch, and cannot close its own script tag" do
      assert byte_size(@head_js) < 800
      assert length(Regex.scan(~r/\btry\s*\{/, @head_js)) == 2
      assert length(Regex.scan(~r/\bcatch\s*\(/, @head_js)) == 2
      refute String.downcase(@head_js) =~ "</script"
      refute @head_js =~ ~r/\binnerHTML\b|\beval\b|\bnew Function\b/
    end

    test "is still the inline script whose hash is in the CSP, and the page carries it verbatim",
         %{tree: tree} do
      assert page(tree, "index.html") =~ "<script>#{@head_js}</script>"
      assert page(tree, "_headers") =~ "'#{Headers.script_hash(@head_js)}'"
    end

    if @node do
      test "behaves, under node, with the document, location and storages stubbed" do
        results = run_node(head_harness(), "assets/js/head.js")

        # no param, nothing stored: the layout's default stays
        assert results["none"]["attrs"] == %{}
        assert results["none"]["writes"]["session"] == []
        assert results["none"]["error"] == nil

        # a valid param is applied and remembered for the tab
        assert results["fade"]["attrs"] == %{"data-vt" => "fade"}
        assert results["fade"]["writes"]["session"] == [["vt", "fade"]]
        assert results["morph"]["attrs"]["data-vt"] == "morph"
        assert results["rise-among-others"]["attrs"]["data-vt"] == "rise"
        assert results["first-wins"]["attrs"]["data-vt"] == "fade"

        # without a param, the remembered one is used and not written again
        assert results["remembered"]["attrs"] == %{"data-vt" => "rise"}
        assert results["remembered"]["writes"]["session"] == []

        # a param that is not one of the three is ignored, and does not clobber what is stored
        for name <- ["bogus", "upper-case", "empty", "padded", "prefix", "script"] do
          assert results[name]["attrs"]["data-vt"] == "rise", name
          assert results[name]["writes"]["session"] == [], name
          assert results[name]["error"] == nil, name
        end

        # a stored value that is not one of the three is ignored too
        assert results["bad-stored"]["attrs"] == %{}

        # blocked storage never throws, and the param still applies for this page
        assert results["write-blocked"]["attrs"] == %{"data-vt" => "fade"}
        assert results["write-blocked"]["error"] == nil
        assert results["read-blocked"]["attrs"] == %{}
        assert results["read-blocked"]["error"] == nil
        assert results["all-blocked"]["attrs"] == %{"data-vt" => "fade"}
        assert results["all-blocked"]["error"] == nil

        # the theme is still restored, from localStorage only, and independently of the prototype
        assert results["theme"]["attrs"] == %{"data-theme" => "dark", "data-vt" => "rise"}
        assert results["theme-bad"]["attrs"] == %{}
        assert results["theme-blocked-vt-ok"]["attrs"] == %{"data-vt" => "fade"}
        assert results["theme"]["writes"]["local"] == []
      end
    end
  end

  describe "theme.js" do
    test "wraps the switch in a view transition of type theme, unless motion is reduced" do
      assert @theme_js =~ "document.startViewTransition"
      assert @theme_js =~ "types: ['theme']"
      assert @theme_js =~ "(prefers-reduced-motion: reduce)"
      assert @theme_js =~ "typeof document.startViewTransition === 'function'"
      refute @theme_js =~ ~r/\binnerHTML\b|\beval\b|\binsertAdjacentHTML\b/
      refute @theme_js =~ ~r/\.style\b|setAttribute\(.style/
    end

    test "is a plain deferred script, loaded on every page", %{tree: tree} do
      for {path, html} <- tree, String.ends_with?(path, ".html") do
        assert html =~ ~s(<script defer src="/assets/js/theme.js"></script>), path
      end
    end

    if @node do
      test "behaves, under node, with the document, media queries and startViewTransition stubbed" do
        results = run_node(theme_harness(), "assets/js/theme.js")

        # supported: the switch waits for the browser's own update call
        s = results["supported"]
        assert s["calls"] == 1
        assert s["argKeys"] == ["types", "update"]
        assert s["types"] == ["theme"]
        assert s["themeBefore"] == nil
        assert s["themeAfter"] == "dark"
        assert s["stored"] == "dark"
        assert s["unhandled"] == 0

        # reduced motion: no transition, the theme switches at once
        r = results["reduced"]
        assert r["calls"] == 0
        assert r["themeBefore"] == "dark"
        assert r["stored"] == "dark"

        # no support, or an engine that only knows the callback form: switch once, at once
        for name <- ["unsupported", "throws"] do
          assert results[name]["themeBefore"] == "dark", name
          assert results[name]["themeAfter"] == "dark", name
          assert results[name]["applied"] == 1, name
          assert results[name]["stored"] == "dark", name
        end

        assert results["throws"]["calls"] == 1

        # the update callback may be called more than once: still one switch
        assert results["twice"]["applied"] == 1

        # the system is dark and the user toggles: light
        assert results["system-dark"]["themeAfter"] == "light"

        # a forced theme toggles back
        assert results["forced-dark"]["themeAfter"] == "light"
        assert results["forced-light"]["themeAfter"] == "dark"

        # two quick clicks, before the first update: back where it started, nothing unhandled
        d = results["double-click"]
        assert d["calls"] == 2
        assert d["themeAfter"] == "light"
        assert d["stored"] == "light"
        assert d["unhandled"] == 0

        # a skipped transition (a rejected ready promise) is not an error
        assert results["skipped"]["unhandled"] == 0
        assert results["skipped"]["themeAfter"] == "dark"

        # storage that throws does not stop the switch
        assert results["storage-blocked"]["themeAfter"] == "dark"

        # no button, no script
        assert results["no-button"]["handlers"] == 0
      end
    end
  end

  describe "the CSP" do
    test "still has exactly two script hashes: head.js and the speculation rules", %{tree: tree} do
      [csp] =
        Regex.run(~r/Content-Security-Policy: (.*)/, page(tree, "_headers"),
          capture: :all_but_first
        )

      hashes = Regex.scan(~r/'(sha256-[^']+)'/, csp) |> Enum.map(&List.last/1)
      assert hashes == [Headers.script_hash(@head_js), Speculation.hash()]
      assert length(Regex.scan(~r/'sha256-/, csp)) == 2

      refute csp =~ "unsafe-inline"
      refute csp =~ "unsafe-eval"
      assert csp =~ "style-src 'self';"
    end

    test "the pages carry no inline script but the two, no inline style and no handler", %{
      tree: tree
    } do
      for {path, html} <- tree, String.ends_with?(path, ".html") do
        inline =
          Regex.scan(~r{<script(?![^>]*\ssrc=)[^>]*>(.*?)</script>}s, html)
          |> Enum.map(&List.last/1)

        assert inline == [@head_js, Speculation.rules()], path
        refute html =~ ~r/\sstyle\s*=/i, path
        refute html =~ ~r/<style[\s>]/i, path
        refute html =~ ~r/\son[a-z]+\s*=/i, path
      end
    end
  end

  # -- node harnesses ---------------------------------------------------------

  defp run_node(harness, script) do
    dir = tmp_dir("site-node")
    path = Path.join(dir, "harness.cjs")
    File.write!(path, harness)

    case System.cmd(@node, [path, Path.expand(script)], stderr_to_stdout: true) do
      {out, 0} -> JSON.decode!(out)
      {out, status} -> flunk("node exited with #{status}:\n#{out}")
    end
  end

  # Runs head.js in a vm context whose document, location and storages are stubs.
  defp head_harness do
    ~S"""
    const fs = require('fs');
    const vm = require('vm');
    const src = fs.readFileSync(process.argv[2], 'utf8').trim();

    function run(o) {
      const attrs = {};
      const writes = { session: [], local: [] };
      const store = (name, data, blocked) => ({
        getItem(k) {
          if (blocked.includes('get')) throw new Error('blocked');
          return Object.prototype.hasOwnProperty.call(data, k) ? data[k] : null;
        },
        setItem(k, v) {
          if (blocked.includes('set')) throw new Error('blocked');
          data[k] = String(v);
          writes[name].push([k, String(v)]);
        },
      });
      const session = store('session', Object.assign({}, o.session), o.sessionBlocked || []);
      const local = store('local', Object.assign({}, o.local), o.localBlocked || []);
      const root = {
        setAttribute(k, v) { attrs[k] = v; },
        getAttribute(k) { return k in attrs ? attrs[k] : null; },
      };
      const ctx = {
        document: { documentElement: root },
        location: { search: o.search || '' },
        URLSearchParams,
      };
      // the browser throws on the property access itself when storage is blocked
      Object.defineProperty(ctx, 'sessionStorage', {
        get() { if (o.sessionDenied) throw new Error('denied'); return session; },
      });
      Object.defineProperty(ctx, 'localStorage', {
        get() { if (o.localDenied) throw new Error('denied'); return local; },
      });
      let error = null;
      try { vm.runInNewContext(src, ctx); } catch (e) { error = String(e); }
      return { attrs, writes, error };
    }

    const rise = { session: { vt: 'rise' } };
    const cases = {
      none: {},
      fade: { search: '?vt=fade' },
      morph: { search: '?vt=morph' },
      'rise-among-others': { search: '?a=1&vt=rise&b=2' },
      'first-wins': { search: '?vt=fade&vt=rise' },
      remembered: { ...rise },
      bogus: { ...rise, search: '?vt=bogus' },
      'upper-case': { ...rise, search: '?vt=FADE' },
      empty: { ...rise, search: '?vt=' },
      padded: { ...rise, search: '?vt=fade%20' },
      prefix: { ...rise, search: '?vt=fademorph' },
      script: { ...rise, search: '?vt=%3Cscript%3E' },
      'bad-stored': { session: { vt: 'wobble' } },
      'write-blocked': { search: '?vt=fade', sessionBlocked: ['set'] },
      'read-blocked': { sessionBlocked: ['get'] },
      'all-blocked': { sessionDenied: true, localDenied: true, search: '?vt=fade' },
      theme: { ...rise, local: { theme: 'dark' } },
      'theme-bad': { local: { theme: 'purple' } },
      'theme-blocked-vt-ok': { localDenied: true, search: '?vt=fade' },
    };
    const out = {};
    for (const [name, o] of Object.entries(cases)) out[name] = run(o);
    console.log(JSON.stringify(out));
    """
  end

  # Runs theme.js against stubs: one button, two media queries, a document that may offer
  # startViewTransition (and run its update callback only when the test says so).
  defp theme_harness do
    ~S"""
    const fs = require('fs');
    const vm = require('vm');
    const src = fs.readFileSync(process.argv[2], 'utf8');

    let unhandled = 0;
    process.on('unhandledRejection', () => { unhandled++; });

    async function run(o) {
      const attrs = Object.assign({}, o.attrs);
      const store = o.stored ? { theme: o.stored } : {};
      let handlers = 0;
      let click = null;
      const button = { addEventListener(type, fn) { handlers++; if (type === 'click') click = fn; } };
      const calls = [];
      let applied = 0;
      const root = {
        getAttribute(k) { return k in attrs ? attrs[k] : null; },
        setAttribute(k, v) { if (k === 'data-theme') applied++; attrs[k] = v; },
      };
      const document = {
        documentElement: root,
        querySelector: (sel) => (sel === '.theme-toggle' && !o.noButton ? button : null),
      };
      if (o.vt === 'supported' || o.vt === 'skipped') {
        document.startViewTransition = (arg) => {
          calls.push(arg);
          return { ready: o.vt === 'skipped' ? Promise.reject(new Error('skipped')) : Promise.resolve() };
        };
      } else if (o.vt === 'throws') {
        document.startViewTransition = (arg) => {
          calls.push(arg);
          throw new TypeError('The provided callback is not a function');
        };
      }
      const media = {
        '(prefers-color-scheme: dark)': { get matches() { return !!o.systemDark; } },
        '(prefers-reduced-motion: reduce)': { get matches() { return !!o.reduced; } },
      };
      const ctx = {
        document,
        window: { matchMedia: (q) => media[q] || { matches: false } },
        localStorage: {
          setItem(k, v) { if (o.storageBlocked) throw new Error('blocked'); store[k] = String(v); },
          getItem(k) { return k in store ? store[k] : null; },
        },
      };
      ctx.window.document = document;
      vm.runInNewContext(src, ctx);

      const out = { handlers, calls: 0, themeBefore: attrs['data-theme'] === undefined ? null : attrs['data-theme'] };
      if (!click) { out.calls = 0; return out; }

      const clicks = o.clicks || 1;
      for (let i = 0; i < clicks; i++) click();
      out.calls = calls.length;
      out.argKeys = calls.length ? Object.keys(calls[0]).sort() : [];
      out.types = calls.length ? calls[0].types : null;
      out.themeBefore = attrs['data-theme'] === undefined ? null : attrs['data-theme'];

      // the browser calls the update callbacks later, in order
      if (calls.length) {
        for (const c of calls) { c.update(); if (o.updateTwice) c.update(); }
      }
      await new Promise((r) => setImmediate(r));
      out.themeAfter = attrs['data-theme'] === undefined ? null : attrs['data-theme'];
      out.stored = store.theme === undefined ? null : store.theme;
      out.applied = applied;
      out.unhandled = unhandled;
      return out;
    }

    (async () => {
      const cases = {
        supported: { vt: 'supported' },
        reduced: { vt: 'supported', reduced: true },
        unsupported: {},
        throws: { vt: 'throws' },
        twice: { vt: 'supported', updateTwice: true },
        'system-dark': { vt: 'supported', systemDark: true },
        'forced-dark': { vt: 'supported', attrs: { 'data-theme': 'dark' } },
        'forced-light': { vt: 'supported', attrs: { 'data-theme': 'light' }, systemDark: true },
        'double-click': { vt: 'supported', clicks: 2 },
        skipped: { vt: 'skipped' },
        'storage-blocked': { vt: 'supported', storageBlocked: true },
        'no-button': { noButton: true },
      };
      const out = {};
      for (const [name, o] of Object.entries(cases)) {
        unhandled = 0;
        out[name] = await run(o);
      }
      console.log(JSON.stringify(out));
    })();
    """
  end
end
