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

  test "the font faces are 400, 400 italic, 700 and 800, all swapping" do
    faces = Regex.scan(~r/@font-face\s*\{(.*?)\}/s, @css) |> Enum.map(&List.last/1)
    assert length(faces) == 4

    expected = [
      {"JetBrainsMono-Regular.woff2", "400", "normal"},
      {"JetBrainsMono-Italic.woff2", "400", "italic"},
      {"JetBrainsMono-Bold.woff2", "700", "normal"},
      {"JetBrainsMono-ExtraBold.woff2", "800", "normal"}
    ]

    for {file, weight, style} <- expected do
      assert Enum.any?(faces, fn face ->
               face =~ "/assets/fonts/#{file}" and face =~ "font-weight: #{weight};" and
                 face =~ "font-style: #{style};" and face =~ "font-display: swap;"
             end),
             "no @font-face for #{file}"
    end

    for {file, _, _} <- expected, do: assert(File.exists?("assets/fonts/#{file}"))
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

  test "the log grid is in ch units and collapses under 600px" do
    assert block(".log-row") =~ "grid-template-columns: 7ch 10ch 7ch minmax(0, 1fr);"
    assert @css =~ "@media (max-width: 599.98px)"
  end

  test "headings are 800 weight, links invert, selection inverts" do
    assert block("h1,\nh2,\nh3,\nh4") =~ "font-weight: 800;"

    assert @css =~
             ~r/a\[href\]:hover,\s*a\[href\]:focus-visible[^{]*\{\s*background: var\(--fg\);\s*color: var\(--bg\);/

    assert block("::selection") =~ "background: var(--fg);"
    assert block(":focus-visible") =~ "outline: 2px solid var(--fg);"
    assert block("h1") =~ "clamp(1.9rem, 1.2rem + 3vw, 3.25rem)"
  end

  test "nothing is loaded from elsewhere" do
    refute @css =~ ~r{url\(\s*["']?(https?:)?//}
    refute @css =~ "@import"
  end

  test "only the field moves: no animations or transitions" do
    refute @css =~ "@keyframes"
    refute @css =~ ~r/\banimation\s*:/
    refute @css =~ ~r/\btransition\s*:/
  end
end
