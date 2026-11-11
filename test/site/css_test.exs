defmodule Site.CSSTest do
  @moduledoc """
  Invariants of `assets/css/site.css` worth pinning: the palette and its contrast,
  the fonts, focus, reduced motion, the light only on the timeline, and that the
  old design is gone. The page transitions have their own test.
  """

  use ExUnit.Case, async: true

  @css File.read!("assets/css/site.css")
  @code Regex.replace(~r{/\*.*?\*/}s, @css, "")

  # Contrast ratio between two #rrggbb colours, as defined by WCAG 2.
  defp luminance("#" <> hex) do
    [r, g, b] =
      for <<c::binary-size(2) <- hex>> do
        channel = String.to_integer(c, 16) / 255

        if channel <= 0.04045,
          do: channel / 12.92,
          else: :math.pow((channel + 0.055) / 1.055, 2.4)
      end

    0.2126 * r + 0.7152 * g + 0.0722 * b
  end

  defp contrast(a, b) do
    [hi, lo] = Enum.sort([luminance(a), luminance(b)], :desc)
    (hi + 0.05) / (lo + 0.05)
  end

  # The rules of the stylesheet as {selector, body}, comments stripped. Rules inside
  # an at-rule (@media) are found too; at-rule preludes are not rules.
  defp rules(css \\ @code) do
    for [_, selector, body] <- Regex.scan(~r/([^{}]+)\{([^{}]*)\}/, css) do
      {selector |> String.replace(~r/\s+/, " ") |> String.trim(), String.trim(body)}
    end
  end

  defp rule!(selector) do
    case for {^selector, body} <- rules(), do: body do
      [body | _] -> body
      [] -> flunk("no rule for #{selector}")
    end
  end

  # The body of an at-rule block, braces balanced.
  defp media(prelude) do
    [{start, len}] = Regex.run(~r/#{Regex.escape(prelude)}\s*\{/, @code, return: :index)
    rest = binary_part(@code, start + len, byte_size(@code) - start - len)
    take_block(rest, 1, "")
  end

  defp take_block(<<"}", _::binary>>, 1, acc), do: acc
  defp take_block(<<"}", rest::binary>>, n, acc), do: take_block(rest, n - 1, acc <> "}")
  defp take_block(<<"{", rest::binary>>, n, acc), do: take_block(rest, n + 1, acc <> "{")
  defp take_block(<<c::utf8, rest::binary>>, n, acc), do: take_block(rest, n, acc <> <<c::utf8>>)

  # `--name: light-dark(#light, #dark);` on :root, as {light, dark}.
  defp pair(name) do
    [_, light, dark] =
      Regex.run(
        ~r/#{Regex.escape(name)}:\s*light-dark\((#[0-9a-f]{6}),\s*(#[0-9a-f]{6})\);/,
        rule!(":root")
      )

    {light, dark}
  end

  describe "the palette" do
    test "every colour of the page is a light-dark pair on :root" do
      root = rule!(":root")

      for name <-
            ~w(--bg --line --line-strong --hover --text --text-prose --text-2 --text-3 --name --lamp --focus --lit --lit-glow --glow-hot --glow-core --glow-wide --spot --card --beam-line) do
        assert root =~ ~r/#{name}: light-dark\(/, name
      end

      assert pair("--bg") == {"#f7f7f6", "#0d0f14"}
      assert pair("--lamp") == {"#9a5a00", "#f2c47c"}
    end

    test "dark first; data-theme forces one, nothing else changes a colour" do
      assert rule!(":root") =~ "color-scheme: dark light;"
      assert rule!(~s|:root[data-theme="light"]|) == "color-scheme: light;"
      assert rule!(~s|:root[data-theme="dark"]|) == "color-scheme: dark;"

      # no second palette under a media query: light-dark() follows the scheme
      refute @code =~ ~r/prefers-color-scheme: dark/
      assert length(Regex.scan(~r/--bg:/, @code)) == 1
    end

    test "every text colour passes AA on the page in both themes, the text AAA" do
      {bg_light, bg_dark} = pair("--bg")

      for name <- ~w(--text --text-prose --text-2 --text-3 --name --lamp --focus --lit) do
        {light, dark} = pair(name)
        assert contrast(light, bg_light) >= 4.5, "#{name} on the light page"
        assert contrast(dark, bg_dark) >= 4.5, "#{name} on the dark page"
      end

      {text_light, text_dark} = pair("--text")
      assert contrast(text_light, bg_light) >= 7
      assert contrast(text_dark, bg_dark) >= 7
    end

    test "the date tint mixes two colours that both pass, and the old palette is gone" do
      assert rule!(".entry-date") =~
               "color: color-mix(in oklab, var(--lamp) calc(100% - var(--age) * 100%), var(--text-3));"

      for old <- ~w(#f4efe4 #262523 #6b675f #ddd6c8 #1e1d1b #ece6d9 #9a958b #34322f) do
        refute @css =~ old, old
      end
    end
  end

  describe "the fonts" do
    test "self-hosted: Inter variable (normal and italic) and JetBrains Mono 400, all swapping" do
      faces = Regex.scan(~r/@font-face\s*\{(.*?)\}/s, @css) |> Enum.map(&List.last/1)
      assert length(faces) == 3

      expected = [
        {"Inter", "InterVariable.woff2", "100 900", "normal"},
        {"Inter", "InterVariable-Italic.woff2", "100 900", "italic"},
        {"JetBrains Mono", "JetBrainsMono-Regular.woff2", "400", "normal"}
      ]

      for {family, file, weight, style} <- expected do
        assert Enum.any?(faces, fn face ->
                 face =~ ~s(font-family: "#{family}";) and
                   face =~ ~s|url("/assets/fonts/#{file}") format("woff2")| and
                   face =~ "font-weight: #{weight};" and face =~ "font-style: #{style};" and
                   face =~ "font-display: swap;"
               end),
               "no @font-face for #{file}"

        assert <<"wOF2", _::binary>> = File.read!("assets/fonts/#{file}")
      end

      assert File.exists?("assets/fonts/Inter-OFL.txt")
      assert File.exists?("assets/fonts/JetBrainsMono-OFL.txt")
    end

    test "nothing is loaded from elsewhere: no Google Fonts, no @import, no remote url()" do
      refute @css =~ ~r/googleapis|gstatic/
      refute @css =~ "@import"
      refute @css =~ ~r{url\(\s*["']?(https?:)?//}
    end

    test "Inter for everything, with its optical sizes; mono only for code" do
      assert rule!(":root") =~
               ~s(--font: "Inter", ui-sans-serif, system-ui, -apple-system, "Segoe UI", Roboto, sans-serif;)

      body = rule!("body")
      assert body =~ "font-family: var(--font);"
      assert body =~ "font-optical-sizing: auto;"

      families =
        for {selector, body} <- rules(),
            selector != "@font-face",
            [_, family] <- Regex.scan(~r/(?<![-\w])font-family:\s*([^;]+);/, body),
            do: {selector, family}

      assert Enum.sort(families) ==
               Enum.sort([
                 {"body", "var(--font)"},
                 {"code, pre", "var(--mono)"},
                 {".back kbd", "var(--font)"}
               ])
    end
  end

  describe "focus and the keyboard" do
    test "focus is always visible, in the lamp colour" do
      assert rule!(":focus-visible") =~ "outline: 2px solid var(--focus);"
      refute @code =~ ~r/outline:\s*(none|0)\b/
    end

    test "a focused entry looks exactly like a hovered one, description included" do
      assert rule!(".entry-row:is(.is-lit, :hover, :has(.entry:focus-visible)) .entry-desc") =~
               "opacity: 1;"

      for part <- ["::before", "::after", " .entry-title", " .entry-date"] do
        assert Enum.any?(rules(), fn {selector, _} ->
                 selector == ".entry-row:is(:hover, :has(.entry:focus-visible))" <> part
               end),
               part
      end
    end

    test "the entry is a 44px target, and the skip link shows on focus" do
      assert rule!(".entry") =~ "min-height: 44px;"
      assert rule!(".skip-link") =~ "transform: translateY(-180%);"
      assert rule!(".skip-link:focus-visible") == "transform: none;"
    end

    test "the description keeps its space at rest, so nothing moves when it shows" do
      desc = rule!(".entry-desc")
      assert desc =~ "display: block;"
      assert desc =~ "opacity: 0;"
      refute desc =~ "display: none"
    end
  end

  describe "motion" do
    test "the entrance only plays for people who have not asked for less motion" do
      entrance = media("@media (prefers-reduced-motion: no-preference) {\n  .intro body::before")
      assert is_binary(entrance)

      # every animation outside the view transitions sits in that block
      for {selector, body} <- rules(),
          body =~ ~r/(?<![-\w])animation\s*:/,
          not String.contains?(selector, "::view-transition") do
        assert String.starts_with?(selector, ".intro"), selector
      end
    end

    test "reduced motion stops every animation and transition" do
      [_, reduce] =
        Regex.run(
          ~r/@media \(prefers-reduced-motion: reduce\) \{\s*\*,\s*\*::before,\s*\*::after \{(.*?)\}/s,
          @code
        )

      assert reduce =~ "animation-duration: 0.01ms !important;"
      assert reduce =~ "animation-delay: 0ms !important;"
      assert reduce =~ "transition-duration: 0.01ms !important;"

      # and the arrows do not lean
      assert @code =~
               ~r/@media \(prefers-reduced-motion: reduce\) \{\s*\.entry-row:is\(:hover, :has\(\.entry:focus-visible\)\) \.entry-out,\s*a:is\(:hover, :focus-visible\) > \.link-out \{\s*transform: none;/
    end
  end

  describe "the light" do
    test "nothing of it without script, and nothing until site.js turns it on" do
      assert rule!(".spot, .beam, .bead") == "display: none;"
      assert rule!(".name-lit") == "display: none;"

      for layer <- ~w(.spot .beam .bead) do
        assert rule!(".js #{layer}") =~ "opacity: 0;", layer
      end

      assert rule!(".js.beam-on .spot") == "opacity: 1;"
      assert rule!(".js.beam-on .name-lit") == "opacity: 1;"
    end

    test "the scan line and the bead show only while the pointer is on the timeline" do
      assert rule!(".js.beam-on.on-timeline :is(.beam, .bead)") == "opacity: 1;"
      assert rule!(".js.beam-on .bead:is(.is-off, .is-locked)") == "opacity: 0;"

      # nothing else ever shows them
      shown =
        for {selector, body} <- rules(),
            selector =~ ~r/\.(beam|bead)(?![-\w])/,
            body =~ "opacity: 1",
            do: selector

      assert shown == [".js.beam-on.on-timeline :is(.beam, .bead)"]
    end

    test "moves by transforms from custom properties only, and never on a touch screen" do
      for layer <- ~w(.spot .beam .bead) do
        body = rule!(".js #{layer}")
        assert body =~ "transform: translate3d(", layer
        assert body =~ "var(--my", layer
        assert body =~ "pointer-events: none;", layer
      end

      assert media("@media (hover: none), (pointer: coarse)") =~ ".js .spot"
    end

    test "the decrypt hides the real name only while the overlay covers it" do
      assert rule!(".name-wrap.is-decrypting > .name") == "color: transparent;"
      assert rule!(".name-scramble") =~ "pointer-events: none;"
    end
  end

  describe "layout" do
    test "the home is two columns on a wide screen and one under 880px" do
      assert rule!(".stage") =~ "grid-template-columns: minmax(0, 1fr) minmax(0, 520px);"
      assert media("@media (max-width: 880px)") =~ "grid-template-columns: minmax(0, 1fr);"
      assert media("@media (max-width: 600px)") =~ "--axis: 64px;"
    end

    test "an entry is one centred reading column" do
      article = rule!(".article")
      assert article =~ "max-width: calc(580px + 2 * var(--gutter));"
      assert article =~ "margin-inline: auto;"

      prose = rule!(".prose")
      assert prose =~ "font-size: 17px;"
      assert prose =~ "line-height: 1.7;"
    end

    test "long words and wide code never push the page sideways" do
      assert rule!(".prose pre") =~ "overflow-x: auto;"
      assert rule!(".article h1") =~ "overflow-wrap: break-word;"
      assert rule!(".prose :is(th, td)") =~ "overflow-wrap: anywhere;"
      assert rule!(".entry-title") =~ "max-width: 100%;"
    end

    test "the theme toggle is hidden without script, which it needs" do
      assert rule!(":root:not(.js) .theme-toggle") == "display: none;"
    end

    test "the margins of an entry page go back, for a fine pointer only" do
      fine = media("@media (pointer: fine)")
      entry = ~s|body:is([data-page="essay"], [data-page="note"], [data-page="project"])|

      assert fine =~ entry <> " {\n    cursor: zoom-out;"
      assert fine =~ entry <> " :is(.skip-link, .bar, main) {\n    cursor: auto;"
      assert length(Regex.scan(~r/zoom-out/, @code)) == 1
    end
  end

  describe "what is gone" do
    test "no field, no log, no paper column, no site header or footer" do
      for gone <-
            ~w(.field .log- --paper --halo .site-header .site-footer .brand .terminal --font-sans --muted --rule) do
        refute @code =~ gone, gone
      end
    end
  end
end
