defmodule Site.CSSTest do
  use ExUnit.Case, async: true

  @css File.read!("assets/css/site.css")

  # Contrast ratio between two #rrggbb colours, as defined by WCAG 2.
  defp luminance("#" <> hex) do
    [r, g, b] =
      for <<c::binary-size(2) <- hex>> do
        channel = String.to_integer(c, 16) / 255

        if channel <= 0.03928,
          do: channel / 12.92,
          else: :math.pow((channel + 0.055) / 1.055, 2.4)
      end

    0.2126 * r + 0.7152 * g + 0.0722 * b
  end

  defp contrast(a, b) do
    [hi, lo] = Enum.sort([luminance(a), luminance(b)], :desc)
    (hi + 0.05) / (lo + 0.05)
  end

  defp tokens(block) do
    for [_, name, value] <- Regex.scan(~r/--(bg|fg|muted|rule):\s*(#[0-9a-fA-F]{6});/, block),
        into: %{},
        do: {name, String.downcase(value)}
  end

  defp block(selector) do
    [_, body] = Regex.run(~r/(?:^|\n)[ \t]*#{Regex.escape(selector)}\s*\{(.*?)\}/s, @css)
    body
  end

  # Every rule that sets `font-family`, as `{selector, value}`. Comments are
  # stripped; at-rule wrappers such as @media are not rules, @font-face is.
  defp font_family_rules do
    css = Regex.replace(~r{/\*.*?\*/}s, @css, "")

    for [_, selector, body] <- Regex.scan(~r/([^{}]+)\{([^{}]*)\}/, css),
        [_, family] <- Regex.scan(~r/(?<![-\w])font-family:\s*([^;]+);/, body) do
      {selector |> String.replace(~r/\s+/, " ") |> String.trim(), family}
    end
  end

  @light %{"bg" => "#f4efe4", "fg" => "#262523", "muted" => "#6b675f", "rule" => "#ddd6c8"}
  @dark %{"bg" => "#1e1d1b", "fg" => "#ece6d9", "muted" => "#9a958b", "rule" => "#34322f"}

  test "the light palette is the one in the spec" do
    assert tokens(block(":root")) == @light
  end

  test "the dark palette is the one in the spec, both for the system and the manual theme" do
    assert tokens(block(~S|:root:not([data-theme="light"])|)) == @dark
    assert tokens(block(~s(:root[data-theme="dark"]))) == @dark
  end

  test "dark values under the media query only apply when the theme is not forced light" do
    assert @css =~
             ~r/@media \(prefers-color-scheme: dark\)\s*\{\s*:root:not\(\[data-theme="light"\]\)/
  end

  test "muted text keeps at least 4.5:1 against the background in both themes" do
    for palette <- [@light, @dark] do
      assert contrast(palette["muted"], palette["bg"]) >= 4.5
      assert contrast(palette["fg"], palette["bg"]) >= 7.0
    end
  end

  test "the font faces are Inter (variable, normal and italic) and JetBrains Mono 400, all swapping" do
    faces = Regex.scan(~r/@font-face\s*\{(.*?)\}/s, @css) |> Enum.map(&List.last/1)
    assert length(faces) == 3

    expected = [
      {"Inter", "InterVariable.woff2", "100 900", "normal"},
      {"Inter", "InterVariable-Italic.woff2", "100 900", "italic"},
      {"JetBrains Mono", "JetBrainsMono-Regular.woff2", "400", "normal"}
    ]

    for {family, file, weight, style} <- expected do
      assert Enum.any?(faces, fn face ->
               face =~ ~s(font-family: "#{family}";) and face =~ "/assets/fonts/#{file}" and
                 face =~ "font-weight: #{weight};" and face =~ "font-style: #{style};" and
                 face =~ "font-display: swap;"
             end),
             "no @font-face for #{file}"
    end

    for {_, file, _, _} <- expected, do: assert(File.exists?("assets/fonts/#{file}"))
  end

  test "the font files are WOFF2, the licences ship, and nothing unused is left" do
    for file <- [
          "InterVariable.woff2",
          "InterVariable-Italic.woff2",
          "JetBrainsMono-Regular.woff2"
        ] do
      assert <<"wOF2", _::binary>> = File.read!("assets/fonts/#{file}"), "#{file} is not WOFF2"
    end

    assert File.exists?("assets/fonts/Inter-OFL.txt")
    assert File.exists?("assets/fonts/JetBrainsMono-OFL.txt")
    refute File.exists?("assets/fonts/OFL.txt")

    assert "assets/fonts/*" |> Path.wildcard() |> Enum.map(&Path.basename/1) |> Enum.sort() == [
             "Inter-OFL.txt",
             "InterVariable-Italic.woff2",
             "InterVariable.woff2",
             "JetBrainsMono-OFL.txt",
             "JetBrainsMono-Regular.woff2"
           ]
  end

  test "the font tokens: Inter for the text, JetBrains Mono for the few mono places" do
    root = block(":root")

    assert root =~
             ~s(--font-sans: "Inter", system-ui, -apple-system, "Segoe UI", Roboto, sans-serif;)

    assert root =~
             ~s(--font-mono: "JetBrains Mono", ui-monospace, "SF Mono", Menlo, monospace;)

    assert block("body") =~ "font-family: var(--font-sans);"
  end

  test "mono is used only for code, the log's hash and date, and the backdrop field" do
    # outside the @font-face rules, the only rules that name a font
    rules =
      for {selector, family} <- font_family_rules(),
          selector != "@font-face",
          do: {selector, family}

    assert Enum.sort(rules) ==
             Enum.sort([
               {"body", "var(--font-sans)"},
               {"code, pre, kbd", "var(--font-mono)"},
               {".log-hash, .log-date", "var(--font-mono)"},
               {".field", "var(--font-mono)"}
             ])
  end

  test "the field sets its own mono font, because field.js reads its computed font" do
    assert block(".field") =~ "font-family: var(--font-mono);"
  end

  test "the log's type and title are sans: they set no font of their own" do
    for selector <- [".log-type", ".log-title", ".log-row", ".log"] do
      refute block(selector) =~ "font-family", "#{selector} sets a font"
    end
  end

  test "the field has the metrics field.js reads" do
    assert block(".field") =~ "font-size: 14px;"
    assert block(".field") =~ "line-height: 1;"
    assert block(".field") =~ "color: var(--fg);"
  end

  test "the field is a fixed, full-viewport layer behind the page that never takes the pointer" do
    field = block(".field")

    for declaration <- [
          "position: fixed;",
          "inset: 0;",
          "z-index: 0;",
          "pointer-events: none;",
          "overflow: hidden;"
        ] do
      assert field =~ declaration, "`.field` lacks #{declaration}"
    end

    canvas = block(".field-canvas")
    assert canvas =~ "position: absolute;"
    assert canvas =~ "inset: 0;"
    assert canvas =~ "display: block;"
  end

  test "header, main and footer sit above the field" do
    shell = block(".site-header,\nmain,\n.site-footer")
    assert shell =~ "position: relative;"
    assert shell =~ "z-index: 1;"

    # the skip link stays on top of everything
    assert block(".skip-link") =~ "z-index: 100;"
  end

  test "inner pages paint an opaque column, the home paints nothing" do
    # the shell is painted with --paper, which is the background colour by default ...
    assert block(":root") =~ "--paper: var(--bg);"
    assert block(".site-header,\nmain,\n.site-footer") =~ "background: var(--paper);"

    # ... and which only the home turns transparent
    assert block(~S|body[data-page="home"]|) =~ "--paper: transparent;"
    assert length(Regex.scan(~r/--paper:/, @css)) == 2
  end

  test "the page column is one width for header, main and footer, in rem" do
    assert block(":root") =~ ~r/--column: calc\([\d.]+rem \+ 2 \* var\(--gutter\)\);/
    assert block(".site-header,\nmain,\n.site-footer") =~ "max-width: var(--column);"
    assert block(".site-header,\nmain,\n.site-footer") =~ "margin-inline: auto;"
  end

  test "entries are a centred reading column: 38-40rem of text, 1.0625-1.125rem body, 1.7 leading" do
    [_, measure] =
      Regex.run(~r/--column: calc\(([\d.]+)rem \+ 2 \* var\(--gutter\)\);/, block(":root"))

    assert {rem, ""} = Float.parse(measure)
    assert rem >= 38.0 and rem <= 40.0

    prose = block(".prose")
    [_, size] = Regex.run(~r/font-size: ([\d.]+)rem;/, prose)
    assert {rem_size, ""} = Float.parse(size)
    assert rem_size >= 1.0625 and rem_size <= 1.125
    assert prose =~ "line-height: 1.7;"

    # paragraphs and headings have room
    assert block(".prose :is(p, ul, ol, pre, table, blockquote, figure)") =~ "margin: 0 0 1.35em;"
    assert block(".prose h2") =~ ~r/margin: 2\.\d+rem 0 0\.\d+rem;/

    # the paper column stays opaque: the field only shows in the side margins
    assert block(".site-header,\nmain,\n.site-footer") =~ "background: var(--paper);"

    # the meta line is small and muted
    assert block(".meta") =~ "color: var(--muted);"
    assert block(".meta") =~ "font-size: 0.875rem;"
  end

  test "every page shares one column width, and the home only drops the paper" do
    home = block(~S|body[data-page="home"]|)
    refute home =~ "--column:"
    assert home =~ "--paper: transparent;"
    assert length(Regex.scan(~r/--column:/, @css)) == 1
  end

  test "the shell has no nav, and the old list, page and uses/cv styles are gone" do
    refute @css =~ "site-nav"
    refute @css =~ "aria-current"
    refute @css =~ ".list-page"
    refute @css =~ ".lede"
    refute @css =~ ".page table"
    refute @css =~ ~r/data-page="(essays|notes|projects)"/

    # the header is the name and the toggle, spaced apart
    header = block(".site-header")
    assert header =~ "justify-content: space-between;"
    refute header =~ "flex-wrap"
  end

  test "type scale: 16-17px body, 1.6 leading, headings 650-700 with negative tracking" do
    assert block("html") =~ "font-size: 16px;"
    assert @css =~ ~r/@media \(min-width: 960px\)\s*\{\s*html\s*\{\s*font-size: 17px;/
    assert block("body") =~ "font-size: 1rem;"
    assert block("body") =~ "line-height: 1.6;"

    headings = block("h1,\nh2,\nh3,\nh4")
    [_, weight] = Regex.run(~r/font-weight: (\d+);/, headings)
    assert String.to_integer(weight) in 650..700
    assert headings =~ ~r/letter-spacing: -0\.0\d+em;/
  end

  test "the split layout is gone: no hero, no sticky column, no field band" do
    refute @css =~ ".hero"
    refute @css =~ "sticky"
    refute @css =~ "minmax(0, 5fr)"
    refute @css =~ "45vh"
    refute @css =~ "data-home"
    refute @css =~ "hotspot"
  end

  test "the home intro is modest and the log is the larger element" do
    refute block(".intro h1") =~ "clamp(",
           "the home name must not be a display heading"

    assert block(".intro p") =~ "color: var(--muted);"
    assert block(".log-section .log") =~ "font-size: 1.125rem;"
    assert block(".log-section .log-row") =~ ~r/padding: 0\.9\d*rem 0;/
  end

  test "the log grid lines up whatever the row font is, and collapses under 600px" do
    # the mono columns are as wide as 7 and 10 of their own characters ...
    assert @css =~ ~r/\n\.log-hash \{\s*width: 7ch;/
    assert @css =~ ~r/\n\.log-date \{\s*width: 10ch;/

    # ... and the grid sizes them to that, then gives the sans type a fixed track in em
    assert block(".log-row") =~
             "grid-template-columns: max-content max-content 3.75em minmax(0, 1fr);"

    # two lines under 600px: hash and date, then type and title
    assert @css =~ "@media (max-width: 599.98px)"
    assert @css =~ "grid-template-columns: 4em minmax(0, 1fr);"

    for {cell, area} <- [
          {".log-hash", "1 / 1"},
          {".log-date", "1 / 2"},
          {".log-type", "2 / 1"},
          {".log-title", "2 / 2"}
        ] do
      assert @css =~ ~r/#{Regex.escape(cell)} \{\s*grid-area: #{Regex.escape(area)};/
    end
  end

  test "links invert, selection inverts" do
    assert @css =~
             ~r/a\[href\]:hover,\s*a\[href\]:focus-visible[^{]*\{\s*background: var\(--fg\);\s*color: var\(--bg\);/

    assert block("::selection") =~ "background: var(--fg);"
    assert block(":focus-visible") =~ "outline: 2px solid var(--fg);"
    assert block("h1") =~ "clamp(1.875rem, 1.3rem + 2.2vw, 2.5rem)"
  end

  test "nothing is loaded from elsewhere" do
    refute @css =~ ~r{url\(\s*["']?(https?:)?//}
    refute @css =~ "@import"
  end

  test "only the field moves, and pages change by view transition: no CSS transitions, and every animation sits in a view-transition rule" do
    css = Regex.replace(~r{/\*.*?\*/}s, @css, "")

    refute css =~ ~r/\btransition\s*:/
    refute css =~ ~r/\btransition-(property|duration|delay)\s*:/

    # the keyframes are the page transitions' own ...
    names = Regex.scan(~r/@keyframes\s+([\w-]+)/, css) |> Enum.map(&List.last/1)
    assert Enum.sort(names) == ["vt-fade-out", "vt-rise-in"]

    # ... and an `animation` property is only ever set on a ::view-transition-* pseudo-element
    for [_, selector, body] <- Regex.scan(~r/([^{}]+)\{([^{}]*)\}/, css),
        body =~ ~r/(?<![-\w])animation(-[a-z-]+)?\s*:/ do
      assert selector =~ "::view-transition-", "animation outside a view transition: #{selector}"
    end
  end
end
