defmodule Site.TransitionsTest do
  @moduledoc """
  The page transition (SPEC section 7, Transitions) and the rest of `site.js`: the
  title transition in `site.css`, the direction and the shared title, the margin
  click, Escape and the back links, the theme toggle and its cross-fade, the home's
  entrance, and the theme-only `head.js`.
  """

  use ExUnit.Case, async: true

  import Site.TestHelpers

  alias Site.{Headers, Speculation}

  @css File.read!("assets/css/site.css")
  @code Regex.replace(~r{/\*.*?\*/}s, @css, "")
  @head_js "assets/js/head.js" |> File.read!() |> String.trim()
  @site_js File.read!("assets/js/site.js")
  @node System.find_executable("node")

  @script_tag ~s(<script defer blocking="render" src="/assets/js/site.js"></script>)

  setup_all do
    # site.js runs once under node, against stubs, when node is installed
    r = if @node, do: run_node(harness(), "assets/js/site.js")
    %{tree: build_fixtures() |> read_tree(), r: r}
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

  describe "site.js is loaded on every page" do
    test "one render-blocking deferred script in the head, after the stylesheet", %{tree: tree} do
      for {path, html} <- tree, String.ends_with?(path, ".html") do
        assert length(String.split(html, @script_tag)) == 2, path

        {css, _} = :binary.match(html, ~s(<link rel="stylesheet" href="/assets/css/site.css">))
        {js, _} = :binary.match(html, @script_tag)
        {head_end, _} = :binary.match(html, "</head>")

        assert css < js and js < head_end, path
      end
    end

    test "the file is served as written, and replaces the old scripts", %{tree: tree} do
      assert page(tree, "assets/js/site.js") == @site_js

      for gone <- ~w(transitions.js theme.js field.js) do
        refute File.exists?("assets/js/" <> gone), gone
      end
    end

    test "it is not an inline script: the CSP keeps exactly two hashes", %{tree: tree} do
      [csp] =
        Regex.run(~r/Content-Security-Policy: (.*)/, page(tree, "_headers"),
          capture: :all_but_first
        )

      hashes = Regex.scan(~r/'(sha256-[^']+)'/, csp) |> Enum.map(&List.last/1)
      assert hashes == [Headers.script_hash(@head_js), Speculation.hash()]
      assert csp =~ "script-src 'self'"
      assert csp =~ "style-src 'self';"
      refute csp =~ "unsafe-inline"
      refute csp =~ "unsafe-eval"
    end

    test "the source writes no markup and no inline style attribute, only CSSOM properties" do
      refute @site_js =~
               ~r/\binnerHTML\b|\beval\b|\binsertAdjacentHTML\b|document\.write|new Function/

      refute @site_js =~ ~r/setAttribute\(\s*['"]style|cssText|<style/
      refute @site_js =~ ~r/\.style\.[a-z]+\s*=/
      assert @site_js =~ "style.setProperty('view-transition-name', NAME)"
      assert @site_js =~ "style.removeProperty('view-transition-name')"
      assert @site_js =~ "var NAME = 'entry-title';"
      refute @site_js =~ ~r/console\./
      refute @site_js =~ ~r/fetch\(|XMLHttpRequest|import\(/
    end

    test "it listens to the page events and sets the types and the direction from the URLs" do
      assert @site_js =~ "addEventListener('pageswap'"
      assert @site_js =~ "addEventListener('pagereveal'"
      assert @site_js =~ "navigation.activation"
      assert @site_js =~ "'forward'"
      assert @site_js =~ "'back'"
      assert @site_js =~ "block: 'nearest'"
    end

    if @node do
      test "node accepts the syntax of every script" do
        for file <- Path.wildcard("assets/js/*.js") do
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
    end

    test "and off under prefers-reduced-motion: reduce, so no navigation animates" do
      assert [_, body] =
               Regex.run(
                 ~r/@media \(prefers-reduced-motion: reduce\)\s*\{\s*@view-transition\s*\{(.*?)\}/s,
                 @css
               )

      assert body =~ "navigation: none;"
      assert length(Regex.scan(~r/@view-transition/, @code)) == 2
    end

    test "the theme toggle has its own short cross-fade" do
      theme = rule!(@css, ":root:active-view-transition-type(theme)::view-transition-group(*)")
      assert theme =~ "animation-duration: 280ms;"
      assert theme =~ "animation-timing-function: ease-out;"
      assert @site_js =~ "types: ['theme']"
    end
  end

  describe "site.css: timing" do
    test "the tokens: enter in 480ms, leave in 160ms, content a beat after" do
      assert ms(token("--vt-enter")) == 480
      assert ms(token("--vt-exit")) == 160
      assert ms(token("--vt-stagger")) == 60
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

  describe "site.css: types and names" do
    test "every navigation rule waits for a type, so the theme toggle only gets its own" do
      transition_rules =
        for {selector, _} = rule <- rules(@css), selector =~ "::view-transition", do: rule

      assert transition_rules != []

      for {selector, _} <- transition_rules,
          selector != "::view-transition",
          part <- String.split(selector, ", :root") do
        assert part =~ ~r/:active-view-transition-type\((forward|back|theme)(, back)?\)/, selector
      end

      # leaving and arriving are only ever used as types
      refute @code =~ "(leaving)"
      refute @code =~ "[data-vt"
    end

    test "the root holds what stays: the old one stays, the new one covers it quickly" do
      page = ":root:active-view-transition-type(forward, back)"

      old = rule!(@css, page <> "::view-transition-old(root)")
      assert old =~ "animation: none;"

      new = rule!(@css, page <> "::view-transition-new(root)")
      assert new =~ "animation: vt-fade-in var(--vt-exit) var(--vt-ease-enter) both;"
      assert new =~ "opacity: 0;"
      refute new =~ "transform"
    end

    test "only the page that arrives names its content, and the names belong to a page" do
      names = Regex.scan(~r/view-transition-name:\s*([^;]+);/, @code) |> Enum.map(&List.last/1)
      assert Enum.sort(Enum.uniq(names)) == ~w(entry-body home-name home-year)

      for {selector, body} <- rules(@css), body =~ "view-transition-name" do
        assert selector =~ ":active-view-transition-type(arriving)", selector
      end

      assert rule!(@css, ":root:active-view-transition-type(arriving) .identity") ==
               "view-transition-name: home-name;"

      assert rule!(@css, ":root:active-view-transition-type(arriving) .timeline") ==
               "view-transition-name: home-year;"

      assert rule!(@css, ":root:active-view-transition-type(arriving) .article") ==
               "view-transition-name: entry-body;"
    end

    test "no white frame: the page colour is under everything, nothing adds up" do
      assert [_ | _] =
               for({"html", body} <- rules(@css), body =~ "background: var(--bg);", do: body)

      assert rule!(@css, "::view-transition") == "background: var(--bg);"
      refute @code =~ "plus-lighter"

      for {selector, body} <- rules(@css), selector =~ ~r/::view-transition-old\(/ do
        refute body =~ "transform:", selector
        refute body =~ "vt-in", selector
      end
    end

    test "the shared title fills its group and scales as one piece, never stretched" do
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

      for side <- ~w(old new) do
        alone = rule!(@css, page <> "::view-transition-#{side}(entry-title):only-child")
        assert alone =~ "animation: vt-"
        assert alone =~ "object-fit: fill;"
      end

      # both ends are as wide as their text
      assert @code =~ ~r/\n\.entry-title \{[^}]*width: fit-content;/
      assert rule!(@css, ".article h1") =~ "width: fit-content;"
    end

    test "the navigation keyframes: what arrives rises 12px and fades, what leaves only fades" do
      assert @code =~
               ~r/@keyframes vt-in\s*\{\s*from\s*\{\s*opacity: 0;\s*transform: translateY\(12px\);\s*\}\s*to\s*\{\s*opacity: 1;\s*transform: none;\s*\}\s*\}/

      assert @code =~
               ~r/@keyframes vt-fade-out\s*\{\s*from\s*\{\s*opacity: 1;\s*\}\s*to\s*\{\s*opacity: 0;/

      refute @code =~ "view-transition-class"
    end
  end

  describe "head.js" do
    test "restores the theme and nothing else" do
      assert @head_js =~ "localStorage.getItem('theme')"
      assert @head_js =~ "setAttribute('data-theme'"
      refute @head_js =~ ~r/sessionStorage|URLSearchParams|location|data-vt/
      assert byte_size(@head_js) < 400
      refute String.downcase(@head_js) =~ "</script"
    end

    test "site.js toggles the same key head.js reads" do
      assert @site_js =~ "var THEME_KEY = 'theme';"
    end

    test "the page carries head.js verbatim, and the CSP its hash", %{tree: tree} do
      assert page(tree, "index.html") =~ "<script>#{@head_js}</script>"
      assert page(tree, "_headers") =~ "'#{Headers.script_hash(@head_js)}'"
    end
  end

  describe "site.js under node" do
    if @node do
      test "going from the home into an entry is forward, and names the clicked title", %{r: r} do
        c = r["swap-forward"]
        assert c["types"] == ["forward", "leaving"]
        assert c["named"] == ["/rhino/"]
        assert c["error"] == nil

        assert r["swap-forward-trailing"]["named"] == ["/rhino/"]
      end

      test "a title off screen, or no row, skips the morph and keeps the direction", %{r: r} do
        assert r["swap-forward-offscreen"]["types"] == ["forward", "leaving"]
        assert r["swap-forward-offscreen"]["named"] == []
        assert r["swap-forward-norow"]["types"] == ["forward", "leaving"]
        assert r["swap-forward-norow"]["named"] == []
        assert r["swap-forward-norow"]["error"] == nil
      end

      test "going back to the home names the h1, however the navigation was made", %{r: r} do
        for name <- ["swap-back", "swap-back-project"] do
          assert r[name]["types"] == ["back", "leaving"], name
          assert r[name]["named"] == ["h1"], name
        end

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
      end

      test "on the new page: the h1 going in, the row we came from coming back", %{r: r} do
        c = r["reveal-forward"]
        assert c["types"] == ["forward", "arriving"]
        assert c["named"] == ["h1"]

        b = r["reveal-back"]
        assert b["types"] == ["back", "arriving"]
        assert b["named"] == ["/rhino/"]

        assert b["scrolls"] == [
                 [
                   "/rhino/",
                   %{"block" => "nearest", "inline" => "nearest", "behavior" => "instant"}
                 ]
               ]
      end

      test "a row off screen is scrolled into view before it is named, unless there is a hash",
           %{r: r} do
        c = r["reveal-back-offscreen"]
        assert c["named"] == ["/rhino/"]
        assert c["order"] == ["scroll:/rhino/", "set:/rhino/"]

        assert r["reveal-back-hash"]["scrolls"] == []

        assert r["reveal-back-norow"]["types"] == ["back", "arriving"]
        assert r["reveal-back-norow"]["named"] == []
        assert r["reveal-back-norow"]["error"] == nil
      end

      test "at most one element carries the name, and it is cleared on any outcome", %{r: r} do
        for {name, c} <- r, is_map(c), Map.has_key?(c, "maxNamed") do
          assert c["maxNamed"] <= 1, name
        end

        assert r["stale"]["named"] == ["/rhino/"]
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

      test "the home's entrance plays on a fresh load only, never under reduced motion", %{r: r} do
        assert "intro" in r["home-fresh"]["classes"]
        refute "intro" in r["home-back"]["classes"]
        refute "intro" in r["home-reduced"]["classes"]
        refute "intro" in r["entry-fresh"]["classes"]

        # the script marks the page as scripted before anything else
        for name <- ~w(home-fresh home-back home-reduced entry-fresh) do
          assert "js" in r[name]["classes"], name
        end
      end

      test "five quick presses on the name's mark play the entrance again", %{r: r} do
        assert r["mark-five"]["error"] == nil
        assert r["mark-five"]["replays"] == 1
        assert r["mark-five"]["intro"] == true
        assert r["mark-ten"]["replays"] == 2

        # not four, not with a press elsewhere or a pause in between, not another button
        for name <- ~w(mark-four mark-missed mark-slow mark-other-button mark-second-finger) do
          assert r[name]["replays"] == 0, name
        end

        # reduced motion: nothing to play
        assert r["mark-reduced"]["replays"] == 0
        assert r["mark-reduced"]["intro"] == false

        # a home a transition brought back never had its entrance: it has one now,
        # and every row gets its moment
        back = r["mark-after-transition"]
        assert back["atBefore"] == [nil, nil, nil]
        assert back["replays"] == 1
        assert back["intro"] == true
        assert Enum.all?(back["at"], &(&1 =~ ~r/^\d+ms$/))
      end

      test "a repeated press on the mark does not select the name", %{r: r} do
        m = r["mark-mousedown"]
        assert m["first"] == false
        assert m["second"] == true
        assert m["elsewhere"] == false
        assert m["docListeners"] == ["mousedown", "mouseout", "pointerdown", "pointermove"]
      end

      test "on an entry page the margins and Escape go back to the home", %{r: r} do
        assert r["go-prev-home"]["go"] == [-1]
        assert r["go-prev-home"]["assign"] == []
        assert r["go-hash-hops"]["go"] == [-3]
        assert r["go-prev-entry"]["go"] == []
        assert r["go-prev-entry"]["assign"] == ["/"]
        assert r["go-first"]["assign"] == ["/"]
        assert r["go-other-origin"]["assign"] == ["/"]

        assert r["go-ref-home"]["back"] == 1
        assert r["go-ref-home"]["assign"] == []
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

        assert r["click-twice"]["go"] == [-1]
      end

      test "Escape goes back unless a modifier, a form field or another handler has it", %{r: r} do
        assert r["escape"]["go"] == [-1]
        # handled, so Chrome's own Escape (stop loading) can't abort the trip home
        assert r["escape"]["prevented"] == true

        for name <-
              ~w(escape-ctrl escape-shift escape-alt escape-meta escape-field escape-prevented
                 escape-composing other-key) do
          assert r[name]["go"] == [], name
          assert r[name]["assign"] == [], name
          assert r[name]["prevented"] == false, name
        end
      end

      test "the back links step back to the home too, and leave modified clicks alone", %{r: r} do
        assert r["back-link"]["go"] == [-1]
        assert r["back-link"]["prevented"] == true

        for name <- ~w(back-link-meta back-link-middle) do
          assert r[name]["go"] == [], name
          assert r[name]["prevented"] == false, name
        end
      end

      test "the home and the 404 have no margin handler", %{r: r} do
        for name <- ~w(page-home page-404 page-none) do
          assert r[name]["docListeners"] == [], name
          assert r[name]["winListeners"] == ["pagereveal", "pageshow", "pageswap"], name
        end

        assert r["entry-listeners"]["docListeners"] == ["click", "keydown", "pointerdown"]
      end

      test "the theme toggle: a cross-fade of type theme, unless motion is reduced", %{r: r} do
        s = r["theme-supported"]
        assert s["calls"] == 1
        assert s["argKeys"] == ["types", "update"]
        assert s["types"] == ["theme"]
        assert s["themeBefore"] == nil
        assert s["themeAfter"] == "light"
        assert s["stored"] == "light"
        assert s["unhandled"] == 0

        reduced = r["theme-reduced"]
        assert reduced["calls"] == 0
        assert reduced["themeBefore"] == "light"

        for name <- ["theme-unsupported", "theme-throws"] do
          assert r[name]["themeBefore"] == "light", name
          assert r[name]["applied"] == 1, name
        end

        # an engine that only knows the callback form still cross-fades
        callback = r["theme-callback-only"]
        assert callback["calls"] == 2
        assert callback["themeBefore"] == nil
        assert callback["themeAfter"] == "light"

        assert r["theme-twice"]["applied"] == 1
      end

      test "choosing what the system prefers forgets the choice", %{r: r} do
        # forced light on a dark system: back to dark is back to the system
        f = r["theme-forget"]
        assert f["themeAfter"] == nil
        assert f["stored"] == nil
        assert f["removed"] == ["theme"]

        # a light system: the toggle forces dark, then forgets it
        assert r["theme-system-light"]["themeAfter"] == "dark"
        assert r["theme-system-light"]["stored"] == "dark"

        # two quick clicks before the first update: back where it started
        d = r["theme-double-click"]
        assert d["calls"] == 2
        assert d["themeAfter"] == nil
        assert d["stored"] == nil
        assert d["unhandled"] == 0
      end

      test "the toggle says which theme it switches to", %{r: r} do
        assert r["theme-supported"]["labelBefore"] == "Switch to light theme"
        assert r["theme-supported"]["labelAfter"] == "Switch to dark theme"
        assert r["theme-supported"]["title"] == "Switch to dark theme"
        assert r["theme-system-light"]["labelBefore"] == "Switch to dark theme"
      end

      test "a skipped cross-fade, blocked storage or no button are not errors", %{r: r} do
        assert r["theme-skipped"]["unhandled"] == 0
        assert r["theme-skipped"]["themeAfter"] == "light"
        assert r["theme-storage-blocked"]["themeAfter"] == "light"
        assert r["theme-no-button"]["handlers"] == 0
        assert r["theme-no-button"]["error"] == nil
      end
    end
  end

  # -- the node harness -------------------------------------------------------

  defp run_node(harness, script) do
    dir = tmp_dir("site-node")
    path = Path.join(dir, "harness.cjs")
    File.write!(path, harness)

    case System.cmd(@node, [path, Path.expand(script)], stderr_to_stdout: true) do
      {out, 0} -> JSON.decode!(out)
      {out, status} -> flunk("node exited with #{status}:\n#{out}")
    end
  end

  # Runs site.js against stubs: the page events, a view transition whose types and
  # promises the test controls, timeline entries and an h1 that know whether they
  # carry the name, the Navigation API, the history, the location, the media
  # queries, storage and the theme toggle.
  defp harness do
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

    function classes() {
      const set = new Set();
      const added = [];
      return {
        added,
        add: (...c) => c.forEach((x) => { set.add(x); added.push(x); }),
        remove: (...c) => c.forEach((x) => set.delete(x)),
        toggle: (c, on) => { if (on === undefined ? !set.has(c) : on) set.add(c); else set.delete(c); },
        contains: (c) => set.has(c),
        list: () => [...set].sort(),
      };
    }

    // One page: its context, the listeners the script registered and a log.
    function page(o) {
      const log = { go: [], assign: [], back: 0, scrolls: [], order: [], removed: [] };
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
          removeProperty() { named.delete(e); log.order.push('remove:' + label); },
        };
        e.getBoundingClientRect = () => e.rect;
        e.scrollIntoView = (opts) => {
          log.scrolls.push([label, opts]);
          log.order.push('scroll:' + label);
          if (o.scrollMakesVisible) e.rect = VISIBLE;
        };
        e.closest = () => null;
        return e;
      };
      // a timeline entry: the link, and the title inside it that carries the name
      const links = (o.rows || []).map(([label, rect]) => {
        const title = el(label, rect || VISIBLE);
        return { href: ORIGIN + label, querySelector: (sel) => (sel === '.entry-title' ? title : null) };
      });
      const h1 = o.h1 === false ? null : el('h1', o.h1 || VISIBLE);

      const backLinks = (o.backLinks || 0) ? [{ handlers: {}, addEventListener(t, f) { this.handlers[t] = f; }, getAttribute: () => '/' }] : [];

      // the home's line: the svg and its path, the stage, and three rows, the name first
      const lineRows = !o.line ? [] : [0, 1, 2].map((i) => {
        const props = {};
        return { props, style: { setProperty(k, v) { props[k] = v; } }, getBoundingClientRect: () => ({ left: 100, top: 100 + 80 * i }) };
      });
      const svg = !o.line ? null : { setAttribute() {}, querySelector: (sel) => (sel === 'path' ? { setAttribute() {} } : null) };

      const win = {};
      const doc = {};
      const here = ORIGIN + (o.path || '/');
      const body = { getAttribute: (k) => (k === 'data-page' && o.page !== undefined ? o.page : null) };
      const attrs = Object.assign({}, o.attrs);
      let applied = 0;
      const root = {
        classList: classes(),
        getAttribute: (k) => (k in attrs ? attrs[k] : null),
        setAttribute(k, v) { if (k === 'data-theme') applied++; attrs[k] = v; },
        removeAttribute(k) { if (k === 'data-theme') applied++; delete attrs[k]; },
        style: { setProperty() {} },
      };
      let handlers = 0;
      let click = null;
      const toggleAttrs = {};
      const toggle = o.toggle === false ? null : {
        addEventListener(t, f) { handlers++; if (t === 'click') click = f; },
        setAttribute(k, v) { toggleAttrs[k] = v; },
      };
      const store = o.stored ? { theme: o.stored } : {};
      const media = {
        '(prefers-reduced-motion: reduce)': !!o.reduced,
        '(prefers-color-scheme: light)': !!o.systemLight,
        '(pointer: fine)': o.fine !== false,
      };
      const calls = [];
      const document = {
        documentElement: root,
        body,
        referrer: o.referrer || '',
        querySelectorAll: (sel) => (sel === 'a.entry' ? links : sel === '[data-home]' ? backLinks : sel === '.identity, .entry-row' ? lineRows : []),
        querySelector: (sel) => (sel === '.article h1' ? h1 : sel === '.theme-toggle' ? toggle : sel === '.line' ? svg : sel === '.stage' && o.line ? {} : null),
        addEventListener: (t, f) => { (doc[t] = doc[t] || []).push(f); },
      };
      if (o.vt === 'supported' || o.vt === 'skipped') {
        document.startViewTransition = (arg) => {
          calls.push(arg);
          return { ready: o.vt === 'skipped' ? Promise.reject(new Error('skipped')) : Promise.resolve(), finished: Promise.resolve() };
        };
      } else if (o.vt === 'throws') {
        document.startViewTransition = (arg) => { calls.push(arg); throw new TypeError('no'); };
      } else if (o.vt === 'callback-only') {
        document.startViewTransition = (arg) => {
          calls.push(arg);
          if (typeof arg !== 'function') throw new TypeError('The provided callback is not a function');
          return { ready: Promise.resolve(), finished: Promise.resolve() };
        };
      }
      const ctx = {
        URL,
        innerHeight: 800,
        scrollY: 0,
        location: { href: here, origin: ORIGIN, hash: o.hash || '', assign: (u) => log.assign.push(u) },
        history: { length: o.histLen === undefined ? 4 : o.histLen, go: (n) => log.go.push(n), back: () => { log.back++; } },
        matchMedia: (q) => ({ matches: !!media[q], addEventListener() {} }),
        getSelection: () => ({ isCollapsed: !o.selection }),
        setTimeout: () => 0,
        requestAnimationFrame: () => 0,
        document,
        addEventListener: (t, f) => { (win[t] = win[t] || []).push(f); },
        localStorage: {
          getItem: (k) => (k in store ? store[k] : null),
          setItem(k, v) { if (o.storageBlocked) throw new Error('blocked'); store[k] = String(v); },
          removeItem(k) { log.removed.push(k); delete store[k]; },
        },
        sessionStorage: { getItem: () => null, setItem() {} },
      };
      ctx.window = ctx;
      if (o.line) {
        // the axis is 96px into the stage; a mark is 7px, 11px under its row's top
        ctx.innerWidth = 1000;
        ctx.onpagereveal = null;
        ctx.getComputedStyle = (el, pseudo) => (pseudo ? { top: '11px', height: '7px' } : { getPropertyValue: () => '96px' });
      }
      if (o.nav !== false) {
        ctx.navigation = {
          activation: o.from === undefined ? null : { from: o.from === null ? null : { url: ORIGIN + o.from } },
          entries: () => (o.entries || []).map((p) => ({ url: p === null ? null : ORIGIN + p })),
          currentEntry: { index: o.index === undefined ? 0 : o.index },
        };
      }
      if (o.referrer !== undefined && o.nav === false) document.referrer = ORIGIN + o.referrer;

      let error = null;
      try { vm.runInNewContext(src, ctx); } catch (e) { error = String(e); }

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

      return {
        ctx, log, fire, fireDoc, names, transition, body, root, error, win, doc, backLinks, lineRows,
        maxNamed: () => maxNamed, attrs, store, calls, toggleAttrs, applied: () => applied,
        click: () => click && click(), handlers: () => handlers,
      };
    }

    const homeRows = [['/a/'], ['/rhino/'], ['/c/']];

    function swap(o, to, extra = {}) {
      const p = page({ page: 'home', path: '/', rows: homeRows, ...o });
      const t = p.transition();
      let error = p.error;
      try { p.fire('pageswap', { viewTransition: extra.noVt ? null : t.vt, activation: { entry: { url: to.startsWith('http') ? to : ORIGIN + to } } }); } catch (e) { error = String(e); }
      return { p, t, result: { types: t.types, named: p.names(), maxNamed: p.maxNamed(), scrolls: p.log.scrolls, order: p.log.order, error } };
    }

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
      out['swap-back-project'] = swap({ ...entryPage, rows: undefined, page: 'project' }, ORIGIN + '/?from=entry').result;
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
      out['reveal-back-hash'] = reveal({ ...homePage, hash: '#feed' }, '/rhino/').result;
      out['reveal-back-norow'] = reveal({ ...homePage, rows: [['/a/']] }, '/rhino/').result;
      out['reveal-entry-entry'] = reveal(entryPage, '/other/').result;
      out['reveal-from-nowhere'] = reveal(entryPage, null).result;
      out['reveal-no-transition'] = reveal(entryPage, '/', { noVt: true }).result;

      // ---- the entrance
      {
        const fresh = page({ ...homePage });
        fresh.fire('pagereveal', { viewTransition: null });
        out['home-fresh'] = { classes: fresh.root.classList.list() };
        const back = reveal(homePage, '/rhino/');
        out['home-back'] = { classes: back.p.root.classList.list() };
        const reduced = page({ ...homePage, reduced: true });
        reduced.fire('pagereveal', { viewTransition: null });
        out['home-reduced'] = { classes: reduced.root.classList.list() };
        const entry = page({ ...entryPage });
        entry.fire('pagereveal', { viewTransition: null });
        out['entry-fresh'] = { classes: entry.root.classList.list() };
      }

      // ---- one name at a time, and cleared
      {
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

      // ---- going back to the home
      const E = (o) => ({ page: 'essay', path: '/rhino/', from: '/', ...o });
      function goHome(name, o) {
        const p = page(E(o));
        p.fireDoc('keydown', { key: 'Escape', target: { closest: () => null }, preventDefault() {} });
        out[name] = { go: p.log.go, assign: p.log.assign, back: p.log.back };
      }
      goHome('go-prev-home', { entries: ['/', '/rhino/'], index: 1 });
      goHome('go-hash-hops', { entries: ['/', '/rhino/', '/rhino/#a', '/rhino/#b'], index: 3, hash: '#b' });
      goHome('go-prev-entry', { entries: ['/other/', '/rhino/'], index: 1 });
      goHome('go-first', { entries: ['/rhino/'], index: 0 });
      goHome('go-other-origin', { entries: [null, '/rhino/'], index: 1 });
      goHome('go-ref-home', { nav: false, referrer: '/', histLen: 3 });
      goHome('go-ref-other', { nav: false, referrer: '/other/', histLen: 3 });
      goHome('go-ref-home-hash', { nav: false, referrer: '/', histLen: 3, hash: '#x' });
      goHome('go-ref-home-alone', { nav: false, referrer: '/', histLen: 1 });

      // ---- the margin click
      const prevHome = { entries: ['/', '/rhino/'], index: 1 };
      function click(name, o, steps) {
        const p = page(E({ ...prevHome, ...o }));
        steps(p);
        out[name] = { go: p.log.go, assign: p.log.assign };
      }
      const paper = { closest: () => null };
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
      const key = (name, ev, o = {}) => {
        let prevented = false;
        click(name, o, (p) => p.fireDoc('keydown', { target: { closest: () => null }, preventDefault() { prevented = true; }, ...ev }));
        out[name].prevented = prevented;
      };
      key('escape', { key: 'Escape' });
      key('escape-ctrl', { key: 'Escape', ctrlKey: true });
      key('escape-shift', { key: 'Escape', shiftKey: true });
      key('escape-alt', { key: 'Escape', altKey: true });
      key('escape-meta', { key: 'Escape', metaKey: true });
      key('escape-prevented', { key: 'Escape', defaultPrevented: true });
      key('escape-composing', { key: 'Escape', isComposing: true });
      key('escape-field', { key: 'Escape', target: { closest: () => ({}) } });
      key('other-key', { key: 'Enter' });

      // ---- the back links
      for (const [name, ev] of [['back-link', {}], ['back-link-meta', { metaKey: true }], ['back-link-middle', { button: 1 }]]) {
        const p = page(E({ ...prevHome, backLinks: 1 }));
        let prevented = false;
        p.backLinks[0].handlers.click({ button: 0, defaultPrevented: false, preventDefault() { prevented = true; }, ...ev });
        out[name] = { go: p.log.go, assign: p.log.assign, prevented };
      }

      // ---- which pages get the margin handler
      for (const [name, o] of [['page-home', { page: 'home' }], ['page-404', { page: '404' }], ['page-none', {}]]) {
        const p = page({ path: '/', ...o });
        out[name] = { docListeners: Object.keys(p.doc).sort(), winListeners: Object.keys(p.win).sort() };
      }
      out['entry-listeners'] = { docListeners: Object.keys(page(E(prevHome)).doc).sort() };

      // ---- the name's mark: five quick presses play the entrance again
      {
        // the stubs put the name's mark at (196.5, 114.5)
        const lined = { ...homePage, line: true };
        const on = (t, extra = {}) => ({ clientX: 197, clientY: 115, button: 0, isPrimary: true, timeStamp: t, ...extra });
        function mark(name, o, presses, from) {
          const p = from === undefined ? page(o) : page({ ...o, from });
          p.fire('pagereveal', { viewTransition: from === undefined ? null : p.transition().vt });
          const before = p.root.classList.added.filter((c) => c === 'intro').length;
          const atBefore = p.lineRows.map((r) => r.props['--at'] || null);
          for (const ev of presses) p.fireDoc('pointerdown', ev);
          out[name] = {
            replays: p.root.classList.added.filter((c) => c === 'intro').length - before,
            intro: p.root.classList.contains('intro'),
            atBefore,
            at: p.lineRows.map((r) => r.props['--at'] || null),
            error: p.error,
          };
        }
        const quick = (n, start = 1000) => Array.from({ length: n }, (_, i) => on(start + 150 * i));
        mark('mark-five', lined, quick(5));
        mark('mark-four', lined, quick(4));
        mark('mark-ten', lined, quick(10));
        mark('mark-missed', lined, [...quick(4), on(1600, { clientX: 240 }), on(1750)]);
        mark('mark-slow', lined, [...quick(3), on(2100), on(2250)]);
        mark('mark-other-button', lined, quick(5).map((ev) => ({ ...ev, button: 2 })));
        mark('mark-second-finger', lined, quick(5).map((ev) => ({ ...ev, isPrimary: false })));
        mark('mark-reduced', { ...lined, reduced: true }, quick(5));
        mark('mark-after-transition', lined, quick(5), '/rhino/');

        const p = page(lined);
        p.fire('pagereveal', { viewTransition: null });
        const down = (ev) => { let prevented = false; p.fireDoc('mousedown', { ...ev, preventDefault() { prevented = true; } }); return prevented; };
        out['mark-mousedown'] = {
          first: down(on(0, { detail: 1 })),
          second: down(on(0, { detail: 2 })),
          elsewhere: down(on(0, { detail: 2, clientX: 400 })),
          docListeners: Object.keys(p.doc).sort(),
        };
      }

      // ---- the theme toggle
      async function theme(name, o) {
        unhandled = 0;
        const p = page({ page: '404', path: '/nope/', ...o });
        const r = { handlers: p.handlers(), error: p.error, labelBefore: p.toggleAttrs['aria-label'] || null };
        for (let i = 0; i < (o.clicks || 1); i++) p.click();
        r.calls = p.calls.length;
        r.argKeys = p.calls.length && typeof p.calls[0] === 'object' ? Object.keys(p.calls[0]).sort() : [];
        r.types = p.calls.length && typeof p.calls[0] === 'object' ? p.calls[0].types : null;
        r.themeBefore = p.attrs['data-theme'] === undefined ? null : p.attrs['data-theme'];
        // the browser calls the update callbacks later, in order
        for (const c of p.calls) {
          const update = typeof c === 'function' ? c : c.update;
          update();
          if (o.updateTwice) update();
        }
        await tick();
        r.themeAfter = p.attrs['data-theme'] === undefined ? null : p.attrs['data-theme'];
        r.stored = p.store.theme === undefined ? null : p.store.theme;
        r.removed = p.log.removed;
        r.applied = p.applied();
        r.unhandled = unhandled;
        r.labelAfter = p.toggleAttrs['aria-label'] || null;
        r.title = p.toggleAttrs.title || null;
        out[name] = r;
      }
      await theme('theme-supported', { vt: 'supported' });
      await theme('theme-reduced', { vt: 'supported', reduced: true });
      await theme('theme-unsupported', {});
      await theme('theme-throws', { vt: 'throws' });
      await theme('theme-callback-only', { vt: 'callback-only' });
      await theme('theme-twice', { vt: 'supported', updateTwice: true });
      await theme('theme-forget', { vt: 'supported', attrs: { 'data-theme': 'light' }, stored: 'light' });
      await theme('theme-system-light', { vt: 'supported', systemLight: true });
      await theme('theme-double-click', { vt: 'supported', clicks: 2 });
      await theme('theme-skipped', { vt: 'skipped' });
      await theme('theme-storage-blocked', { vt: 'supported', storageBlocked: true });
      await theme('theme-no-button', { toggle: false });

      console.log(JSON.stringify(out));
    }

    main().catch((e) => { console.error(e); process.exit(1); });
    """
  end
end
