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

  @light %{"bg" => "#f3f2ee", "fg" => "#121212", "muted" => "#6a6a66", "rule" => "#d6d5cf"}
  @dark %{"bg" => "#0f0f0e", "fg" => "#e8e7e1", "muted" => "#8b8a85", "rule" => "#2b2b29"}

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

  test "the home splits into two columns at 960px, with no variant switch left" do
    assert @css =~ "@media (min-width: 960px)"
    refute @css =~ "data-home"
    refute @css =~ "hotspot"
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
