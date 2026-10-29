defmodule Site.TransitionsTest do
  @moduledoc """
  The page transition (SPEC section 7, Transitions): the one design in `site.css`,
  the direction and shared-title script `transitions.js`, the margin click and
  Escape, the theme-only `head.js` and the theme toggle's own cross-fade in
  `theme.js`.
  """

  use ExUnit.Case, async: true

  import Site.TestHelpers

  alias Site.{Headers, Log, Speculation}

  @css File.read!("assets/css/site.css")
  @code Regex.replace(~r{/\*.*?\*/}s, @css, "")
  @head_js "assets/js/head.js" |> File.read!() |> String.trim()
  @theme_js File.read!("assets/js/theme.js")
  @transitions_js File.read!("assets/js/transitions.js")
  @node System.find_executable("node")

  @script_tag ~s(<script defer blocking="render" src="/assets/js/transitions.js"></script>)

  setup_all do
    %{tree: build_fixtures() |> read_tree()}
  end

  defp page(tree, path), do: Map.fetch!(tree, path)

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

  defp ms(value) do
    {n, "ms"} = Integer.parse(value)
    n
  end

  defp token(name) do
    [_, value] = Regex.run(~r/#{Regex.escape(name)}:\s*([^;]+);/, @code)
    value
  end

  describe "what is gone" do
    test "the generated stylesheet, its module and the per-slug classes", %{tree: tree} do
      refute Code.ensure_loaded?(Site.Transitions)
      refute File.exists?("lib/site/transitions.ex")
      refute File.exists?("assets/css/transitions.css")
      refute Map.has_key?(tree, "assets/css/transitions.css")

      for {path, html} <- tree, String.ends_with?(path, ".html") do
        refute html =~ "transitions.css", path
        refute html =~ ~r/\bvt-[a-z0-9]/, path
      end

      for file <- Path.wildcard("templates/*.eex") ++ Path.wildcard("lib/**/*.ex") do
        refute File.read!(file) =~ ~r/\bvt-[a-z0-9]|Transitions\.(class|name)/, file
      end

      refute Map.has_key?(
               Log.row(%Site.Entry{
                 type: :note,
                 slug: "x",
                 title: "x",
                 date: ~D[2026-10-28],
                 html: ""
               }),
               :vt
             )
    end

    test "no leftover of the dropped prototypes, nor of the ?vt= switch" do
      # morph, fade and rise went first; slide and sheet were tried and dropped
      for dead <- ~w(morph fade rise slide sheet) do
        refute @code =~ ~r/data-vt=["']?#{dead}|view-transition-name:\s*[\w-]*#{dead}/, dead
      end

      refute @code =~ "data-vt"
      refute @code =~ ~r/vt-rise-in|type\(page\)|home-sheet|entry-sheet/
      refute @code =~ ~r/--vt-in-|--vt-out/
      refute @css =~ ~r/\b(slide|sheet)\b/i

      # head.js is theme-only: no ?vt= parsing, no sessionStorage key for it
      refute @head_js =~
               ~r/vt|sessionStorage|URLSearchParams|location|morph|fade|rise|slide|sheet/

      refute @transitions_js =~ ~r/data-vt|wantsTitle|variant/

      for file <- Path.wildcard("templates/*.eex") do
        refute File.read!(file) =~ "data-vt", file
      end

      refute File.read!("README.md") =~ "?vt="
    end
  end

  describe "transitions.js is loaded on every page" do
    test "one render-blocking deferred script in the head, before the field", %{tree: tree} do
      for {path, html} <- tree, String.ends_with?(path, ".html") do
        assert length(String.split(html, @script_tag)) == 2, path

        {css, _} = :binary.match(html, ~s(<link rel="stylesheet" href="/assets/css/site.css">))
        {js, _} = :binary.match(html, @script_tag)
        {field, _} = :binary.match(html, ~s(<script type="module" src="/assets/js/field.js">))
        {head_end, _} = :binary.match(html, "</head>")

        assert css < js and js < field and field < head_end, path
      end
    end

    test "the file is served as written", %{tree: tree} do
      assert page(tree, "assets/js/transitions.js") == @transitions_js
    end

    test "it is not an inline script: the CSP keeps exactly two hashes", %{tree: tree} do
      [csp] =
        Regex.run(~r/Content-Security-Policy: (.*)/, page(tree, "_headers"),
          capture: :all_but_first
        )

      hashes = Regex.scan(~r/'(sha256-[^']+)'/, csp) |> Enum.map(&List.last/1)
      assert hashes == [Headers.script_hash(@head_js), Speculation.hash()]
      assert length(Regex.scan(~r/'sha256-/, csp)) == 2
      assert csp =~ "script-src 'self'"
      assert csp =~ "style-src 'self';"
      refute csp =~ "unsafe-inline"
      refute csp =~ "unsafe-eval"
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

    test "the source writes no markup and no inline style, only CSSOM properties" do
      refute @transitions_js =~ ~r/\binnerHTML\b|\beval\b|\binsertAdjacentHTML\b|document\.write/
      refute @transitions_js =~ ~r/setAttribute\(\s*['"]style|cssText|<style/
      assert @transitions_js =~ "style.setProperty('view-transition-name', NAME)"
      assert @transitions_js =~ "style.removeProperty('view-transition-name')"
      assert @transitions_js =~ "var NAME = 'entry-title';"
      refute @transitions_js =~ ~r/console\./
    end

    test "it listens to the page events and sets the types and the direction from the URLs" do
      assert @transitions_js =~ "addEventListener('pageswap'"
      assert @transitions_js =~ "addEventListener('pagereveal'"
      assert @transitions_js =~ "navigation.activation"
      assert @transitions_js =~ "'forward'"
      assert @transitions_js =~ "'back'"
      assert @transitions_js =~ "block: 'nearest'"
    end

    if @node do
      test "node accepts the syntax of every script" do
        for file <- Path.wildcard("assets/js/*.js"), file != "assets/js/field.js" do
          assert {_, 0} = System.cmd(@node, ["--check", file], stderr_to_stdout: true), file
        end
      end
    end
  end

  describe "site.css: opt-in" do
    test "cross-document transitions are on only for people who have not asked for less motion" do
      assert [_, body] =
               Regex.run(
                 ~r/@media \(prefers-reduced-motion: no-preference\)\s*\{\s*@view-transition\s*\{(.*?)\}/s,
                 @css
               )

      assert body =~ "navigation: auto;"
      refute body =~ "types:"
    end

    test "and off under prefers-reduced-motion: reduce, so no navigation animates" do
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

    test "the theme toggle keeps its own cross-fade, untouched" do
      assert token("--vt-duration") == "200ms"
      assert token("--vt-ease") == "ease-out"

      theme = rule!(@css, ":root:active-view-transition-type(theme)::view-transition-group(*)")
      assert theme =~ "animation-duration: var(--vt-duration);"
      assert theme =~ "animation-timing-function: var(--vt-ease);"
      assert @theme_js =~ "types: ['theme']"
    end
  end

  describe "site.css: timing" do
    test "the tokens: enters in about 400ms, leaves in 40% of that, content a beat after" do
      enter = ms(token("--vt-enter"))
      exit = ms(token("--vt-exit"))
      stagger = ms(token("--vt-stagger"))

      assert enter in 380..450
      assert_in_delta exit / enter, 0.4, 0.02
      assert stagger in 60..90
    end

    test "emphasized decelerate in, emphasized accelerate out" do
      assert token("--vt-ease-enter") == "cubic-bezier(0.2, 0, 0, 1)"
      assert token("--vt-ease-exit") == "cubic-bezier(0.3, 0, 0.8, 0.15)"
    end

    test "every duration, delay and easing of a navigation comes from the tokens" do
      nav =
        for {selector, body} <- rules(@css),
            selector =~ ~r/active-view-transition-type\((forward|back)/,
            body =~ "animation",
            do: {selector, body}

      assert nav != []

      for {selector, body} <- nav do
        refute body =~ ~r/\d+m?s\b/, "hard-coded time in #{selector}"
        refute body =~ "cubic-bezier", "hard-coded easing in #{selector}"
      end

      # exactly the two easings of the brief exist in the whole sheet
      assert Regex.scan(~r/cubic-bezier\([^)]*\)/, @code) |> Enum.map(&hd/1) |> Enum.sort() ==
               ["cubic-bezier(0.2, 0, 0, 1)", "cubic-bezier(0.3, 0, 0.8, 0.15)"]
    end

    test "old images leave on the exit timing, new images arrive after the stagger" do
      page = ":root:active-view-transition-type(forward, back)"

      old = rule!(@css, page <> "::view-transition-old(*)")
      assert old =~ "animation: vt-fade-out var(--vt-exit) var(--vt-ease-exit) both;"
      assert old =~ "mix-blend-mode: normal;"

      new = rule!(@css, page <> "::view-transition-new(*)")

      assert new =~
               "animation: vt-in var(--vt-enter) var(--vt-ease-enter) var(--vt-stagger) both;"

      # hidden in the rule itself: the frame before the animation starts never shows it
      assert new =~ "opacity: 0;"

      assert new =~ "mix-blend-mode: normal;"

      group = rule!(@css, page <> "::view-transition-group(*)")
      assert group =~ "animation-duration: var(--vt-enter);"
      assert group =~ "animation-timing-function: var(--vt-ease-enter);"
    end
  end

  describe "site.css: types and prototypes" do
    test "every navigation rule waits for a type, so the theme toggle only gets its own" do
      transition_rules =
        for {selector, _} = rule <- rules(@css), selector =~ "::view-transition", do: rule

      assert transition_rules != []

      # one rule is for every transition, the theme toggle's included: the page colour
      # under it all (see "no white frame")
      for {selector, _} <- transition_rules,
          selector != "::view-transition",
          part <- String.split(selector, ", :root") do
        assert part =~ ~r/:active-view-transition-type\((forward|back|theme)(, back)?\)/, selector
      end

      theme = for {s, _} <- transition_rules, s =~ "(theme)", do: s
      assert length(theme) == 1
      refute Enum.any?(theme, &(&1 =~ "forward"))
    end

    test "forward and back both have rules, and the CSS needs no attribute on the root" do
      for type <- ~w(forward back) do
        scope = ":root:active-view-transition-type(#{type})"

        assert Enum.any?(rules(@css), fn {selector, _} -> String.starts_with?(selector, scope) end),
               "no #{type} rule"
      end

      # leaving and arriving are only ever used as types, never as a rule of their own
      assert Enum.any?(rules(@css), fn {selector, _} -> selector =~ "(arriving)" end)
      refute @code =~ "(leaving)"
      refute @code =~ "[data-vt"
    end

    test "the root holds what stays: the old one stays, the new one fades in over it" do
      page = ":root:active-view-transition-type(forward, back)"

      old = rule!(@css, page <> "::view-transition-old(root)")
      assert old =~ "animation: none;"
      assert old =~ "mix-blend-mode: normal;"

      new = rule!(@css, page <> "::view-transition-new(root)")
      # in the time of an exit: it is also how the old page's content leaves
      assert new =~ "animation: vt-fade-in var(--vt-exit) var(--vt-ease-exit) both;"
      assert new =~ "opacity: 0;"
      assert new =~ "mix-blend-mode: normal;"
      refute new =~ "transform"

      # nothing that stays put has a name of its own: not the field, header, footer or paper
      names = Regex.scan(~r/view-transition-name:\s*([^;]+);/, @code) |> Enum.map(&List.last/1)

      assert Enum.sort(Enum.uniq(names)) == ~w(entry-body home-intro home-log)

      refute rule!(@css, ".field") =~ "view-transition-name"
      refute @code =~ ~r/view-transition-name:\s*(site-header|site-footer|field)/
    end

    test "no white frame: the page colour is under everything, nothing adds up, nothing shows early" do
      # the root element has the page colour itself, not only body, so a root image or a
      # transparent corner never starts from the canvas white
      assert [_ | _] =
               for({"html", body} <- rules(@css), body =~ "background: var(--bg);", do: body)

      # under every transition, the theme toggle's too, and not scoped by a type: the first
      # frame of a navigation may come before the types do
      assert rule!(@css, "::view-transition") == "background: var(--bg);"

      # plus-lighter adds two images up; a frame with both at full opacity is white
      refute @code =~ "plus-lighter"

      # the new image of every group is hidden by the rule, so it cannot show before its
      # animation does, and what leaves is visible until its animation runs
      for sel <- ["(*)", "(root)"] do
        new =
          rule!(
            @css,
            ":root:active-view-transition-type(forward, back)::view-transition-new#{sel}"
          )

        assert new =~ "opacity: 0;", sel
      end

      for name <- ~w(vt-in vt-fade-in) do
        assert @code =~
                 ~r/@keyframes #{name}\s*\{\s*from\s*\{[^}]*opacity: 0;[^}]*\}\s*to\s*\{[^}]*opacity: 1;/,
               name
      end

      assert @code =~
               ~r/@keyframes vt-fade-out\s*\{\s*from\s*\{\s*opacity: 1;\s*\}\s*to\s*\{\s*opacity: 0;/
    end

    test "no white frame: an old picture is only ever faded, never moved, and the old page names nothing tall" do
      # what leaves is a still picture of the old page, often a very tall one (an essay):
      # moved or scaled while it fades, the browser can draw it as a white rectangle
      refute @code =~ "vt-out"
      refute @code =~ "--vt-out"

      for {selector, body} <- rules(@css),
          selector =~ ~r/::view-transition-old\(/ do
        refute body =~ "transform:", selector
        refute body =~ "vt-in", selector
      end

      # only the page that arrives names its content (type "arriving"); the old page's
      # content stays in its root image, which is as big as the viewport
      for {selector, body} <- rules(@css), body =~ "view-transition-name" do
        assert selector =~ ":active-view-transition-type(arriving)", selector
        refute selector =~ "leaving", selector
      end
    end

    test "names belong to a page type, so a group never pairs a page with itself" do
      # home and entry content have different names
      assert rule!(@css, ":root:active-view-transition-type(arriving) .intro") ==
               "view-transition-name: home-intro;"

      assert rule!(@css, ":root:active-view-transition-type(arriving) .log-section") ==
               "view-transition-name: home-log;"

      assert rule!(@css, ":root:active-view-transition-type(arriving) .prose") ==
               "view-transition-name: entry-body;"
    end

    test "title: the shared title fills its group and scales as one piece, never stretched" do
      page = ":root:active-view-transition-type(forward, back)"

      fit =
        rule!(
          @css,
          page <>
            "::view-transition-old(entry-title), " <>
            page <> "::view-transition-new(entry-title)"
        )

      assert fit =~ "object-fit: contain;"
      assert fit =~ "object-position: left top;"
      assert fit =~ "width: 100%;"
      assert fit =~ "height: 100%;"

      # going in, the row fades out in the first quarter; coming back, the heading fades out late
      fwd_old =
        rule!(
          @css,
          ":root:active-view-transition-type(forward)::view-transition-old(entry-title)"
        )

      assert fwd_old =~ "calc(var(--vt-enter) * 0.25)"

      back_new =
        rule!(
          @css,
          ":root:active-view-transition-type(back)::view-transition-new(entry-title)"
        )

      assert back_new =~ "calc(var(--vt-enter) * 0.75)"

      # a title with no partner is ordinary content
      for side <- ~w(old new) do
        alone = rule!(@css, page <> "::view-transition-#{side}(entry-title):only-child")
        assert alone =~ "animation: vt-"
        assert alone =~ "object-fit: fill;"
      end

      # the content rises 12px after the title
      assert @code =~
               ~r/@keyframes vt-in\s*\{\s*from\s*\{\s*opacity: 0;\s*transform: translateY\(12px\);/
    end

    test "title: the log title and the h1 are as wide as their text, and the hovered row is captured plain" do
      assert [_ | _] = for({".log-title", "justify-self: start;"} <- rules(@css), do: :ok)
      assert rule!(@css, ".prose > h1") =~ "width: fit-content;"

      hover =
        rule!(
          @css,
          ":root:active-view-transition-type(forward, back) " <>
            ".log-title:is(:hover, :focus-visible, :active)"
        )

      assert hover =~ "background: none;"
      assert hover =~ "color: inherit;"
      assert hover =~ "outline: none;"
    end

    test "the keyframes: what arrives rises and fades, what leaves only fades, nothing is left over" do
      assert @code =~
               ~r/@keyframes vt-in\s*\{\s*from\s*\{\s*opacity: 0;\s*transform: translateY\(12px\);\s*\}\s*to\s*\{\s*opacity: 1;\s*transform: none;\s*\}\s*\}/

      names = Regex.scan(~r/@keyframes\s+([\w-]+)/, @code) |> Enum.map(&List.last/1)
      assert Enum.sort(names) == ["vt-fade-in", "vt-fade-out", "vt-in"]

      # every keyframe and every custom property of the transition is used
      for name <- names do
        assert length(Regex.scan(~r/animation:[^;]*\b#{name}\b/, @code)) >= 1, name
      end

      for token <-
            ~w(--vt-enter --vt-exit --vt-stagger --vt-ease-enter --vt-ease-exit --vt-duration --vt-ease) do
        assert length(Regex.scan(~r/var\(#{token}\)/, @code)) >= 1, token
      end

      assert length(Regex.scan(~r/--vt-[\w-]+:/, @code)) == 7
    end

    test "the motion stays small and calm: at most 32px, no scale, no blur, colour or rotation" do
      px = Regex.scan(~r/translate[XY]?\((-?\d+)px/, @code)
      assert px != []

      for [_, n] <- px do
        assert abs(String.to_integer(n)) <= 32
      end

      # nothing is scaled by the CSS at all
      refute @code =~ ~r/scale\(|scale:/

      refute @code =~ ~r/blur\(|filter:|backdrop-filter|rotate|skew|perspective|steps\(/
      refute @code =~ ~r/@keyframes[^{]*\{[^}]*(?:color|background)/
    end

    test "no CSS-driven shortcut: no view-transition-class, no @import" do
      refute @css =~ "view-transition-class"
      refute @css =~ "@import"
    end
  end

  describe "site.css: the margins go back" do
    test "the zoom-out cursor is on entry pages only, for a fine pointer only" do
      assert [_, media] =
               Regex.run(~r/@media \(pointer: fine\)\s*\{(.*?)\n\}\n/s, @code)

      entry = ~s|body:is([data-page="essay"], [data-page="note"], [data-page="project"])|

      assert rule!(media, entry) == "cursor: zoom-out;"

      assert rule!(media, entry <> " :is(.site-header, main, .site-footer)") == "cursor: auto;"

      # nowhere else, so the home and the 404 keep the normal cursor
      assert length(Regex.scan(~r/zoom-out/, @code)) == 1
      refute @code =~ ~r/body\[data-page="home"\][^{]*zoom-out/
    end
  end

  describe "field.js: a revealed page never shows an empty field" do
    @field_js File.read!("assets/js/field.js")

    test "the first frame is drawn at once when the font is usable, and never later than a page being shown" do
      # at once, whether or not the document is visible or prerendered
      assert @field_js =~ "document.fonts.check(face, "
      assert @field_js =~ "function begin()"

      assert @field_js =~
               ~r/function begin\(\) \{\s*if \(ready \|\| destroyed\) return;\s*ready = true;\s*layout\(\);/

      # otherwise the wait for the font is what it was (up to 2.5s), but a page being
      # activated from a prerender, or shown, ends it
      assert @field_js =~ "later(r, 2500)"

      assert @field_js =~
               "document.addEventListener('prerenderingchange', begin, { once: true });"

      assert @field_js =~ ~r/function onVisibility\(\) \{[^}]*if \(docVisible\) begin\(\);/s
      assert @field_js =~ "document.removeEventListener('prerenderingchange', begin);"
    end

    test "nothing else about the field changed: no new timer, loop or listener on a page that loads normally" do
      # the loop still waits for a visible document and an unreduced motion preference
      assert @field_js =~
               "const should = ready && sized && visible && docVisible && !reduced && !destroyed;"

      assert length(Regex.scan(~r/requestAnimationFrame\(/, @field_js)) == 2
    end

    if @node do
      test "node accepts the module" do
        dir = tmp_dir("site-field")
        path = Path.join(dir, "field.mjs")
        File.write!(path, @field_js)
        assert {_, 0} = System.cmd(@node, ["--check", path], stderr_to_stdout: true)
      end
    end
  end

  describe "head.js" do
    test "restores the theme and nothing else: no ?vt= switch, no sessionStorage" do
      assert @head_js =~ "localStorage.getItem('theme')"
      assert @head_js =~ "setAttribute('data-theme'"

      refute @head_js =~ ~r/sessionStorage|URLSearchParams|location|data-vt|'vt'/
      refute @head_js =~ ~r/title|slide|sheet|morph|fade|rise/
    end

    test "is tiny, wrapped in try/catch, and cannot close its own script tag" do
      assert byte_size(@head_js) < 400
      assert length(Regex.scan(~r/\btry\s*\{/, @head_js)) == 1
      assert length(Regex.scan(~r/\bcatch\s*\(/, @head_js)) == 1
      refute String.downcase(@head_js) =~ "</script"
      refute @head_js =~ ~r/\binnerHTML\b|\beval\b|\bnew Function\b/
    end

    test "the root element carries no data-vt, and the page carries head.js verbatim", %{
      tree: tree
    } do
      refute File.read!("templates/layout.html.eex") =~ "data-vt"

      for {path, html} <- tree, String.ends_with?(path, ".html") do
        assert html =~ ~s(<html lang="en">), path
        refute html =~ "data-vt", path
      end

      assert page(tree, "index.html") =~ "<script>#{@head_js}</script>"
      assert page(tree, "_headers") =~ "'#{Headers.script_hash(@head_js)}'"
    end

    if @node do
      test "behaves, under node, with the document, location and storages stubbed" do
        results = run_node(head_harness(), "assets/js/head.js")

        # the theme is restored from localStorage, light or dark only
        assert results["none"]["attrs"] == %{}
        assert results["none"]["error"] == nil
        assert results["dark"]["attrs"] == %{"data-theme" => "dark"}
        assert results["light"]["attrs"] == %{"data-theme" => "light"}
        assert results["bad"]["attrs"] == %{}

        # nothing is ever written, and a ?vt= in the URL or a stored vt does nothing
        for name <- ~w(none dark light bad vt-slide vt-title stored-vt blocked denied) do
          assert results[name]["writes"] == [], name
        end

        for name <- ~w(vt-slide vt-title stored-vt) do
          assert results[name]["attrs"] == %{}, name
        end

        # blocked storage never throws
        assert results["blocked"]["attrs"] == %{}
        assert results["blocked"]["error"] == nil
        assert results["denied"]["attrs"] == %{}
        assert results["denied"]["error"] == nil
      end
    end
  end

  describe "transitions.js under node" do
    if @node do
      setup do
        %{r: run_node(transitions_harness(), "assets/js/transitions.js")}
      end

      test "going from the home into an entry is forward, and names the clicked row", %{r: r} do
        c = r["swap-forward"]
        assert c["types"] == ["forward", "leaving"]
        assert c["named"] == ["/rhino/"]
        assert c["error"] == nil

        # the same navigation, started from anywhere: a link, the keyboard, a prerender
        assert r["swap-forward-trailing"]["named"] == ["/rhino/"]
      end

      test "a row that is not on screen, or not there, skips the morph and keeps the direction",
           %{
             r: r
           } do
        assert r["swap-forward-offscreen"]["types"] == ["forward", "leaving"]
        assert r["swap-forward-offscreen"]["named"] == []
        assert r["swap-forward-norow"]["types"] == ["forward", "leaving"]
        assert r["swap-forward-norow"]["named"] == []
        assert r["swap-forward-norow"]["error"] == nil
      end

      test "going back to the home names the h1, however the navigation was made", %{r: r} do
        for name <- ["swap-back", "swap-back-traverse"] do
          assert r[name]["types"] == ["back", "leaving"], name
          assert r[name]["named"] == ["h1"], name
        end

        # an h1 scrolled out of view is not named
        assert r["swap-back-scrolled"]["types"] == ["back", "leaving"]
        assert r["swap-back-scrolled"]["named"] == []
      end

      test "unrelated navigations get no type and no name", %{r: r} do
        for name <-
              ~w(swap-entry-entry swap-home-home swap-home-markdown swap-home-other-origin swap-404) do
          assert r[name]["types"] == [], name
          assert r[name]["named"] == [], name
          assert r[name]["error"] == nil, name
        end

        assert r["reveal-entry-entry"]["types"] == []
        assert r["reveal-from-nowhere"]["types"] == []
        assert r["reveal-no-transition"]["types"] == []
        assert r["swap-no-transition"]["named"] == []
        assert r["swap-no-transition"]["error"] == nil
      end

      test "on the new page: the h1 going in, the row we came from coming back", %{r: r} do
        c = r["reveal-forward"]
        assert c["types"] == ["forward", "arriving"]
        assert c["named"] == ["h1"]

        b = r["reveal-back"]
        assert b["types"] == ["back", "arriving"]
        assert b["named"] == ["/rhino/"]
        assert b["scrolls"] == [["/rhino/", %{"block" => "nearest", "inline" => "nearest"}]]
      end

      test "a row off screen is scrolled to the nearest edge before it is named", %{r: r} do
        c = r["reveal-back-offscreen"]
        assert c["scrolls"] == [["/rhino/", %{"block" => "nearest", "inline" => "nearest"}]]
        assert c["named"] == ["/rhino/"]
        assert c["order"] == ["scroll:/rhino/", "set:/rhino/"]

        # no row for the entry we came from: the directional fallback
        assert r["reveal-back-norow"]["types"] == ["back", "arriving"]
        assert r["reveal-back-norow"]["named"] == []
        assert r["reveal-back-norow"]["error"] == nil
      end

      test "at most one element carries the name at any time", %{r: r} do
        for {name, c} <- r, is_map(c), Map.has_key?(c, "maxNamed") do
          assert c["maxNamed"] <= 1, name
        end

        # a stale name (a page restored from the cache) is dropped before the next claim
        c = r["stale"]
        assert c["named"] == ["/rhino/"]
        assert c["maxNamed"] == 1
      end

      test "the names are cleared when the transition finishes, is skipped or fails", %{r: r} do
        assert r["finished"]["namedBefore"] == ["/rhino/"]
        assert r["finished"]["named"] == []
        assert r["rejected"]["namedBefore"] == ["h1"]
        assert r["rejected"]["named"] == []
        assert r["pageshow-persisted"]["named"] == []
        assert r["pageshow-fresh"]["named"] == ["h1"]
      end

      test "a skipped transition or an old engine is not an error", %{r: r} do
        assert r["ready-rejected"]["unhandled"] == 0
        assert r["ready-rejected"]["types"] == ["forward", "leaving"]
        assert r["no-types-api"]["error"] == nil
        assert r["no-types-api"]["named"] == ["/rhino/"]
        assert r["no-navigation-api"]["error"] == nil
      end

      test "on an entry page the margins and Escape go back to the log", %{r: r} do
        # the previous history entry is the home: step back, so the home keeps its place
        assert r["go-prev-home"]["go"] == [-1]
        assert r["go-prev-home"]["assign"] == []

        # hash hops on this page do not count
        assert r["go-hash-hops"]["go"] == [-3]

        # otherwise, the home
        assert r["go-prev-entry"]["go"] == []
        assert r["go-prev-entry"]["assign"] == ["/"]
        assert r["go-first"]["assign"] == ["/"]
        assert r["go-other-origin"]["assign"] == ["/"]

        # without the Navigation API: the referrer and the history length
        assert r["go-ref-home"]["back"] == 1
        assert r["go-ref-home"]["assign"] == []
        assert r["go-ref-other"]["back"] == 0
        assert r["go-ref-other"]["assign"] == ["/"]
        assert r["go-ref-home-hash"]["assign"] == ["/"]
        assert r["go-ref-home-alone"]["assign"] == ["/"]
      end

      test "only a plain click that began and ended on the margin goes back", %{r: r} do
        assert r["margin-click"]["go"] == [-1]
        assert r["margin-click-root"]["go"] == [-1]

        for name <-
              ~w(click-paper click-link-text press-paper-release-margin click-without-press
                 click-ctrl click-meta click-shift click-alt click-middle click-prevented
                 click-coarse click-selection) do
          assert r[name]["go"] == [], name
          assert r[name]["assign"] == [], name
        end

        # the press is forgotten after one click
        assert r["click-twice"]["go"] == [-1]
      end

      test "Escape goes back unless a modifier, a form field or another handler has it", %{r: r} do
        assert r["escape"]["go"] == [-1]

        for name <-
              ~w(escape-ctrl escape-shift escape-alt escape-meta escape-field escape-prevented
                 escape-composing other-key) do
          assert r[name]["go"] == [], name
          assert r[name]["assign"] == [], name
        end
      end

      test "the home, the 404 and the log have no margin handler", %{r: r} do
        for name <- ~w(page-home page-404 page-none) do
          assert r[name]["docListeners"] == [], name
          # the direction script still runs there
          assert r[name]["winListeners"] == ["pagereveal", "pageshow", "pageswap"], name
        end

        assert r["go-prev-home"]["docListeners"] == ["click", "keydown", "pointerdown"]
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
      const writes = [];
      const store = (data, blocked) => ({
        getItem(k) {
          if (blocked) throw new Error('blocked');
          return Object.prototype.hasOwnProperty.call(data, k) ? data[k] : null;
        },
        setItem(k, v) { writes.push([k, String(v)]); },
      });
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
      Object.defineProperty(ctx, 'localStorage', {
        get() { if (o.denied) throw new Error('denied'); return store(o.local || {}, o.blocked); },
      });
      Object.defineProperty(ctx, 'sessionStorage', {
        get() { return store(o.session || {}, false); },
      });
      let error = null;
      try { vm.runInNewContext(src, ctx); } catch (e) { error = String(e); }
      return { attrs, writes, error };
    }

    const cases = {
      none: {},
      dark: { local: { theme: 'dark' } },
      light: { local: { theme: 'light' } },
      bad: { local: { theme: 'purple' } },
      'vt-slide': { search: '?vt=slide' },
      'vt-title': { search: '?vt=title', local: {} },
      'stored-vt': { session: { vt: 'sheet' } },
      blocked: { blocked: true, local: { theme: 'dark' } },
      denied: { denied: true },
    };
    const out = {};
    for (const [name, o] of Object.entries(cases)) out[name] = run(o);
    console.log(JSON.stringify(out));
    """
  end

  # Runs transitions.js against stubs: the page events, a view transition whose types and
  # promises the test controls, a few rows and an h1 that know whether they carry the name,
  # the Navigation API, the history and the location.
  defp transitions_harness do
    ~S"""
    const fs = require('fs');
    const vm = require('vm');
    const src = fs.readFileSync(process.argv[2], 'utf8');

    const ORIGIN = 'https://site.test';
    const VISIBLE = { top: 120, bottom: 150, height: 30 };
    const OFFSCREEN = { top: 2400, bottom: 2430, height: 30 };
    const ABOVE = { top: -900, bottom: -860, height: 40 };

    let unhandled = 0;
    process.on('unhandledRejection', () => { unhandled++; });

    const tick = () => new Promise((r) => setImmediate(r));

    // One page: its context, the listeners the script registered and a log.
    function page(o) {
      const log = { go: [], assign: [], back: 0, scrolls: [], order: [] };
      const named = new Set();
      let maxNamed = 0;
      const el = (label, rect) => {
        const e = { label, rect };
        e.style = {
          setProperty(k, v) {
            if (k !== 'view-transition-name' || v !== 'entry-title') throw new Error('unexpected ' + k + ' ' + v);
            named.add(e);
            maxNamed = Math.max(maxNamed, named.size);
            log.order.push('set:' + label);
          },
          removeProperty(k) { named.delete(e); log.order.push('remove:' + label); },
        };
        e.getBoundingClientRect = () => e.rect;
        e.scrollIntoView = (opts) => {
          log.scrolls.push([label, opts]);
          log.order.push('scroll:' + label);
          if (o.scrollMakesVisible) e.rect = VISIBLE;
        };
        Object.defineProperty(e, 'href', { value: ORIGIN + label });
        return e;
      };
      const rows = (o.rows || []).map(([label, rect]) => el(label, rect || VISIBLE));
      const h1 = o.h1 === false ? null : el('h1', o.h1 || VISIBLE);

      const win = {};
      const doc = {};
      const here = ORIGIN + (o.path || '/');
      const body = { getAttribute: (k) => (k === 'data-page' && o.page !== undefined ? o.page : null) };
      const root = { getAttribute: () => null };
      const ctx = {
        URL,
        innerHeight: 800,
        location: { href: here, origin: ORIGIN, hash: o.hash || '', assign: (u) => log.assign.push(u) },
        history: { length: o.histLen === undefined ? 4 : o.histLen, go: (n) => log.go.push(n), back: () => { log.back++; } },
        matchMedia: () => ({ matches: o.fine !== false }),
        getSelection: () => ({ isCollapsed: !o.selection }),
        document: {
          documentElement: root,
          body,
          referrer: o.referrer || '',
          querySelectorAll: (sel) => (sel === '.log-title' ? rows : []),
          querySelector: (sel) => (sel === 'main .prose > h1' ? h1 : null),
          addEventListener: (t, f) => { (doc[t] = doc[t] || []).push(f); },
        },
        addEventListener: (t, f) => { (win[t] = win[t] || []).push(f); },
      };
      ctx.window = ctx;
      if (o.nav !== false) {
        ctx.navigation = {
          activation: o.from === undefined ? null : { from: o.from === null ? null : { url: ORIGIN + o.from } },
          entries: () => (o.entries || []).map((p) => ({ url: p === null ? null : ORIGIN + p })),
          currentEntry: { index: o.index === undefined ? 0 : o.index },
        };
      }
      if (o.referrer !== undefined && o.nav === false) ctx.document.referrer = ORIGIN + o.referrer;

      let error = null;
      try { require('vm').runInNewContext(src, ctx); } catch (e) { error = String(e); }

      const fire = (t, ev) => { for (const f of win[t] || []) f(ev); };
      const fireDoc = (t, ev) => { for (const f of doc[t] || []) f(ev); };
      const names = () => [...named].map((e) => e.label);

      // a view transition whose promises the test settles
      const transition = () => {
        let ok, no;
        const finished = new Promise((a, b) => { ok = a; no = b; });
        const ready = o.readyRejects ? Promise.reject(new Error('skipped')) : Promise.resolve();
        const types = [];
        const vt = { finished, ready };
        if (!o.noTypes) vt.types = { add: (t) => types.push(t) };
        return { vt, types, finish: ok, fail: no };
      };

      return { ctx, log, fire, fireDoc, names, transition, body, root, error, win, doc, maxNamed: () => maxNamed, rows, h1 };
    }

    const homeRows = [['/a/'], ['/rhino/'], ['/c/']];

    // pageswap on the old page
    function swap(o, to, extra = {}) {
      const p = page({ page: 'home', path: '/', rows: homeRows, ...o });
      const t = p.transition();
      let error = p.error;
      try { p.fire('pageswap', { viewTransition: extra.noVt ? null : t.vt, activation: { entry: { url: to.startsWith('http') ? to : ORIGIN + to }, from: { url: ORIGIN + (o.path || '/') } } }); } catch (e) { error = String(e); }
      return { p, t, result: { types: t.types, named: p.names(), maxNamed: p.maxNamed(), scrolls: p.log.scrolls, order: p.log.order, error } };
    }

    // pagereveal on the new page
    function reveal(o, from, extra = {}) {
      const p = page({ from, ...o });
      const t = p.transition();
      let error = p.error;
      try { p.fire('pagereveal', { viewTransition: extra.noVt ? null : t.vt }); } catch (e) { error = String(e); }
      return { p, t, result: { types: t.types, named: p.names(), maxNamed: p.maxNamed(), scrolls: p.log.scrolls, order: p.log.order, error } };
    }

    const entryPage = { page: 'essay', path: '/rhino/', h1: VISIBLE };
    const homePage = { page: 'home', path: '/', rows: homeRows };

    async function main() {
      const out = {};

      // ---- pageswap
      out['swap-forward'] = swap({}, '/rhino/').result;
      out['swap-forward-trailing'] = swap({}, '/rhino').result;
      out['swap-forward-offscreen'] = swap({ rows: [['/a/'], ['/rhino/', OFFSCREEN]] }, '/rhino/').result;
      out['swap-forward-norow'] = swap({ rows: [['/a/']] }, '/rhino/').result;
      out['swap-back'] = swap({ ...entryPage, rows: undefined }, '/').result;
      out['swap-back-traverse'] = swap({ ...entryPage, rows: undefined, page: 'project' }, ORIGIN + '/?from=entry').result;
      out['swap-back-scrolled'] = swap({ ...entryPage, h1: ABOVE }, '/').result;
      out['swap-entry-entry'] = swap({ ...entryPage }, '/other/').result;
      out['swap-home-home'] = swap({}, '/').result;
      out['swap-home-markdown'] = swap({}, '/rhino.md').result;
      out['swap-home-other-origin'] = swap({}, 'https://elsewhere.test/rhino/').result;
      out['swap-404'] = swap({ page: '404', path: '/nope/' }, '/').result;
      out['swap-no-transition'] = swap({}, '/rhino/', { noVt: true }).result;

      // ---- pagereveal
      out['reveal-forward'] = reveal(entryPage, '/').result;
      out['reveal-back'] = reveal(homePage, '/rhino/').result;
      out['reveal-back-offscreen'] = reveal({ ...homePage, rows: [['/a/'], ['/rhino/', OFFSCREEN]], scrollMakesVisible: true }, '/rhino/').result;
      out['reveal-back-norow'] = reveal({ ...homePage, rows: [['/a/']] }, '/rhino/').result;
      out['reveal-entry-entry'] = reveal(entryPage, '/other/').result;
      out['reveal-from-nowhere'] = reveal(entryPage, null).result;
      out['reveal-no-transition'] = reveal(entryPage, '/', { noVt: true }).result;

      // ---- one name at a time, and cleared
      {
        // a page restored from the cache still has the name of its last swap
        const p = page({ ...homePage, from: '/rhino/' });
        const a = p.transition();
        p.fire('pagereveal', { viewTransition: a.vt });
        const b = p.transition();
        p.fire('pageswap', { viewTransition: b.vt, activation: { entry: { url: ORIGIN + '/other-entry/' } } });
        const c = p.transition();
        p.fire('pageswap', { viewTransition: c.vt, activation: { entry: { url: ORIGIN + '/rhino/' } } });
        out['stale'] = { named: p.names(), maxNamed: p.maxNamed() };
      }
      {
        const s = swap({}, '/rhino/');
        const namedBefore = s.p.names();
        s.t.finish();
        await tick();
        out['finished'] = { namedBefore, named: s.p.names() };
      }
      {
        const r = reveal(entryPage, '/');
        const namedBefore = r.p.names();
        r.t.fail(new Error('boom'));
        await tick();
        out['rejected'] = { namedBefore, named: r.p.names() };
      }
      {
        const r = reveal(entryPage, '/');
        r.p.fire('pageshow', { persisted: true });
        out['pageshow-persisted'] = { named: r.p.names() };
        const f = reveal(entryPage, '/');
        f.p.fire('pageshow', { persisted: false });
        out['pageshow-fresh'] = { named: f.p.names() };
      }

      // ---- skipped transitions and old engines
      {
        unhandled = 0;
        const s = swap({ readyRejects: true }, '/rhino/');
        await tick();
        out['ready-rejected'] = { unhandled, types: s.t.types };
      }
      out['no-types-api'] = swap({ noTypes: true }, '/rhino/').result;
      {
        const p = page({ ...entryPage, nav: false });
        let error = p.error;
        try { p.fire('pagereveal', { viewTransition: p.transition().vt }); p.fire('pageshow', { persisted: true }); } catch (e) { error = String(e); }
        out['no-navigation-api'] = { error };
      }

      // ---- going back to the log
      const E = (o) => ({ page: 'essay', path: '/rhino/', from: '/', ...o });
      function goLog(name, o, how = 'escape') {
        const p = page(E(o));
        if (how === 'escape') p.fireDoc('keydown', { key: 'Escape', target: { closest: () => null } });
        out[name] = { go: p.log.go, assign: p.log.assign, back: p.log.back, docListeners: Object.keys(p.doc).sort(), winListeners: Object.keys(p.win).sort() };
      }
      goLog('go-prev-home', { entries: ['/', '/rhino/'], index: 1 });
      goLog('go-hash-hops', { entries: ['/', '/rhino/', '/rhino/#a', '/rhino/#b'], index: 3, hash: '#b' });
      goLog('go-prev-entry', { entries: ['/other/', '/rhino/'], index: 1 });
      goLog('go-first', { entries: ['/rhino/'], index: 0 });
      goLog('go-other-origin', { entries: [null, '/rhino/'], index: 1 });
      goLog('go-ref-home', { nav: false, referrer: '/', histLen: 3 });
      goLog('go-ref-other', { nav: false, referrer: '/other/', histLen: 3 });
      goLog('go-ref-home-hash', { nav: false, referrer: '/', histLen: 3, hash: '#x' });
      goLog('go-ref-home-alone', { nav: false, referrer: '/', histLen: 1 });

      // ---- the margin click
      const prevHome = { entries: ['/', '/rhino/'], index: 1 };
      function click(name, o, steps) {
        const p = page(E({ ...prevHome, ...o }));
        steps(p);
        out[name] = { go: p.log.go, assign: p.log.assign };
      }
      const paper = { closest: () => null, paper: true };
      const press = (p, target, extra = {}) => p.fireDoc('pointerdown', { button: 0, target, ...extra });
      const clk = (p, target, extra = {}) => p.fireDoc('click', { button: 0, target, ...extra });
      click('margin-click', {}, (p) => { press(p, p.body); clk(p, p.body); });
      click('margin-click-root', {}, (p) => { press(p, p.root); clk(p, p.root); });
      click('click-paper', {}, (p) => { press(p, paper); clk(p, paper); });
      click('click-link-text', {}, (p) => { const a = { closest: () => ({}) }; press(p, a); clk(p, a); });
      click('press-paper-release-margin', {}, (p) => { press(p, paper); clk(p, p.body); });
      click('click-without-press', {}, (p) => { clk(p, p.body); });
      for (const [name, mod] of [['click-ctrl', { ctrlKey: true }], ['click-meta', { metaKey: true }], ['click-shift', { shiftKey: true }], ['click-alt', { altKey: true }], ['click-middle', { button: 1 }], ['click-prevented', { defaultPrevented: true }]]) {
        click(name, {}, (p) => { press(p, p.body); clk(p, p.body, mod); });
      }
      click('click-coarse', { fine: false }, (p) => { press(p, p.body); clk(p, p.body); });
      click('click-selection', { selection: true }, (p) => { press(p, p.body); clk(p, p.body); });
      click('click-twice', {}, (p) => { press(p, p.body); clk(p, p.body); clk(p, p.body); });

      // ---- Escape
      const key = (name, ev, o = {}) => click(name, o, (p) => p.fireDoc('keydown', { target: { closest: () => null }, ...ev }));
      key('escape', { key: 'Escape' });
      key('escape-ctrl', { key: 'Escape', ctrlKey: true });
      key('escape-shift', { key: 'Escape', shiftKey: true });
      key('escape-alt', { key: 'Escape', altKey: true });
      key('escape-meta', { key: 'Escape', metaKey: true });
      key('escape-prevented', { key: 'Escape', defaultPrevented: true });
      key('escape-composing', { key: 'Escape', isComposing: true });
      key('escape-field', { key: 'Escape', target: { closest: () => ({}) } });
      key('other-key', { key: 'Enter' });

      // ---- which pages get the margin handler
      for (const [name, o] of [['page-home', { page: 'home' }], ['page-404', { page: '404' }], ['page-none', {}]]) {
        const p = page({ path: '/', ...o });
        out[name] = { docListeners: Object.keys(p.doc).sort(), winListeners: Object.keys(p.win).sort() };
      }
      out['go-prev-home'].docListeners = Object.keys(page(E(prevHome)).doc).sort();

      console.log(JSON.stringify(out));
    }

    main().catch((e) => { console.error(e); process.exit(1); });
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
