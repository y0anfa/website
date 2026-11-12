defmodule Site.CSSTest do
  @moduledoc """
  Invariants of `assets/css/site.css` worth pinning: the palette and its contrast,
  the fonts, focus, reduced motion, the line and its marks, and that the old
  designs are gone. The page transitions have their own test.
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
    test "every colour of the page is a light-dark pair on :root, and none is an accent" do
      root = rule!(":root")

      for name <-
            ~w(--bg --hair --line --line-strong --hover --text --text-prose --text-2 --text-3 --focus --card) do
        assert root =~ ~r/#{name}: light-dark\(/, name
      end

      assert pair("--bg") == {"#f4f4f1", "#0e0f12"}
      assert pair("--hair") == {"#d6d6d1", "#292b31"}
      assert pair("--focus") == pair("--text")
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

      for name <- ~w(--text --text-prose --text-2 --text-3 --focus) do
        {light, dark} = pair(name)
        assert contrast(light, bg_light) >= 4.5, "#{name} on the light page"
        assert contrast(dark, bg_dark) >= 4.5, "#{name} on the dark page"
      end

      {text_light, text_dark} = pair("--text")
      assert contrast(text_light, bg_light) >= 7
      assert contrast(text_dark, bg_dark) >= 7
    end

    test "dates are the one secondary grey, and the old palettes are gone" do
      assert rule!(".entry-date") =~ "color: var(--text-2);"
      assert rule!(".role") =~ "color: var(--text-2);"

      for old <-
            ~w(#f4efe4 #262523 #6b675f #ddd6c8 #1e1d1b #ece6d9 #9a958b #34322f #9a5a00 #f2c47c #fff3df #8a4f00) do
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
    test "focus is always visible, in ink" do
      assert rule!(":focus-visible") =~ "outline: 2px solid var(--focus);"
      refute @code =~ ~r/outline:\s*(none|0)\b/
    end

    test "a focused entry looks exactly like a hovered one: its mark fills" do
      filled =
        rule!(".identity::before, .entry-row:is(:hover, :has(.entry:focus-visible))::before")

      assert filled =~ "border-color: var(--text);"
      assert filled =~ "background: var(--text);"

      assert Enum.any?(rules(), fn {selector, _} ->
               selector =~ ".entry-row:is(:hover, :has(.entry:focus-visible)) .entry-out"
             end)
    end

    test "the entry is a 44px target, and the skip link shows on focus" do
      assert rule!(".entry") =~ "min-height: 44px;"
      assert rule!(".skip-link") =~ "transform: translateY(-180%);"
      assert rule!(".skip-link:focus-visible") == "transform: none;"
    end

    test "the home shows a title and a date, never a description" do
      refute @code =~ "entry-desc"
    end
  end

  describe "motion" do
    test "the entrance only plays for people who have not asked for less motion" do
      entrance = media("@media (prefers-reduced-motion: no-preference) {\n  .intro .line path")
      assert is_binary(entrance)

      # every animation outside the view transitions sits in that block, but two:
      # the flicker of a title under the pointer or the keyboard, and the 404's heading
      for {selector, body} <- rules(),
          body =~ ~r/(?<![-\w])animation\s*:/,
          not String.contains?(selector, "view-transition") do
        assert String.starts_with?(selector, ".intro") or
                 selector in [
                   ".entry:is(:hover, :focus-visible) .entry-title",
                   ".not-found h1"
                 ],
               selector
      end
    end

    test "the 404's heading never quite settles: two beats in six seconds, then whole" do
      assert @code =~
               ~r/@media \(prefers-reduced-motion: no-preference\) \{\s*\.not-found h1 \{\s*animation: stutter 6s step-end 1200ms infinite;\s*\}\s*\}/

      [stutter] = Regex.run(~r/@keyframes stutter \{.*?\n\}\n/s, @code)

      # it starts and ends as the heading's own rules say, and is never hidden
      refute stutter =~ ~r/^\s*(0%|from|100%|to) \{/m
      refute stutter =~ "opacity"

      # each beat ends on a step that puts everything back
      whole = ~r/\{\s*transform: none;\s*clip-path: none;\s*text-shadow: none;\s*\}/
      steps = Regex.scan(~r/(\d+)% (\{[^}]*\})/, stutter)
      assert Enum.map(steps, fn [_, at, _] -> at end) == ~w(38 39 90 91 92 93 94)

      for [_, at, body] <- steps, at in ~w(39 94) do
        assert body =~ whole, at
      end

      for [_, px] <- Regex.scan(~r/translateX\((-?\d+)px\)/, stutter) do
        assert abs(String.to_integer(px)) <= 4
      end

      for [_, colour] <- Regex.scan(~r/px 0 0 ([^,;]+)/, stutter) do
        assert colour in ["var(--text-3)", "var(--hair)"]
      end
    end

    test "a title flickers once when the pointer or the keyboard reaches its link" do
      hover = media("@media (hover: hover) and (prefers-reduced-motion: no-preference)")

      assert hover =~
               ".entry:is(:hover, :focus-visible) .entry-title {\n    animation: flicker 280ms step-end both;"

      [flicker] = Regex.run(~r/@keyframes flicker \{.*?\n\}\n/s, @code)

      # smaller than the entrance's glitch, never hidden, and it ends as plain text
      refute flicker =~ "opacity"
      refute flicker =~ ~r/^\s*(100%|to) \{/m
      assert flicker =~ ~r/82% \{\s*transform: none;\s*clip-path: none;\s*text-shadow: none;\s*\}/

      for [_, px] <- Regex.scan(~r/translateX\((-?\d+)px\)/, flicker) do
        assert abs(String.to_integer(px)) <= 3
      end

      # the title that grows into the heading is captured whole
      assert rule!(":root:active-view-transition-type(forward, back) .entry-title") ==
               "animation: none;"
    end

    test "on a fresh load the words glitch in, in ink only, and settle as their own rules say" do
      assert rule!(".intro :is(.identity, .entry-row) > *") ==
               "animation: glitch 560ms step-end var(--at, 300ms) both;"

      [glitch] = Regex.run(~r/@keyframes glitch \{.*?\n\}\n/s, @code)

      # hidden until its moment; the last step it names is the plain text
      assert glitch =~ ~r/0% \{\s*opacity: 0;\s*\}/
      refute glitch =~ ~r/^\s*(100%|to) \{/m

      assert glitch =~
               ~r/86% \{\s*opacity: 1;\s*transform: none;\s*clip-path: none;\s*text-shadow: none;\s*\}/

      # small: nothing moves more than a few pixels, and the ghosts are grey, not coloured
      for [_, px] <- Regex.scan(~r/translateX\((-?\d+)px\)/, glitch) do
        assert abs(String.to_integer(px)) <= 6
      end

      for [_, colour] <- Regex.scan(~r/px 0 0 ([^,;]+)/, glitch) do
        assert colour in ["var(--text-3)", "var(--hair)"]
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

  describe "the line" do
    test "with script it is one path; without, a plain rule stands in its place" do
      line = rule!(".line")
      assert line =~ "position: fixed;"
      assert line =~ "pointer-events: none;"
      assert rule!(".line path") =~ "stroke: var(--hair);"

      stand_in = rule!(".stage::before")
      assert stand_in =~ "position: fixed;"
      assert stand_in =~ "background: var(--hair);"
      assert rule!(".js .stage::before") == "display: none;"
    end

    test "the name and the entries hang on it by the same mark, which follows its lean" do
      mark = rule!(".identity::before, .entry-row::before")
      assert mark =~ "left: calc(var(--axis) - 3.5px);"
      assert mark =~ "transform: translateX(var(--lean, 0px));"

      # one size for the name and the titles
      assert rule!(".name, .entry-title") =~ "font-size: 20px;"
    end

    test "an entry page carries the same line in its margin, and its mark by the date" do
      line = rule!(~s|body:not([data-page="home"])::before|)
      assert line =~ "position: fixed;"
      assert line =~ "left: calc(50% - 317px);"
      assert line =~ "background: var(--hair);"

      assert rule!(".meta::before") =~ "background: var(--text);"
    end

    test "on the 404 the line is broken: dashes where the mark would be, and no mark" do
      broken = rule!(".not-found .meta::before")

      # a patch of the page colour over the line, where a mark would sit, and no dot
      assert broken =~ "height: 60px;"
      assert broken =~ "margin-top: -30px;"
      assert broken =~ "border-radius: 0;"
      assert broken =~ "box-shadow: none;"

      # the dashes are drawn where the line runs: 3px into the patch (the patch is at
      # -30px, the line at -27px), 1px wide, in the line's colour, a gap at both ends
      assert broken =~
               "background: repeating-linear-gradient(transparent 0 4px, var(--hair) 4px 8px) 3px 0 / 1px 100% no-repeat var(--bg);"

      assert rule!(".meta::before") =~ "left: -30px;"
    end

    test "nothing of the lamp is left" do
      for gone <-
            ~w(.spot .beam .bead .name-lit .name-scramble .name-line --lamp --lit --glow --age is-lit beam-on) do
        refute @code =~ gone, gone
      end
    end
  end

  describe "layout" do
    test "the home is one narrow column; on a phone the line takes the left margin" do
      stage = rule!(".stage")
      assert stage =~ "--axis: 96px;"
      assert stage =~ "max-width: calc(540px + 2 * var(--gutter));"

      phone = media("@media (max-width: 640px)")
      assert phone =~ "--axis: -26px;"
      assert phone =~ "order: -1;"

      assert media("@media (max-width: 700px)") =~ "padding-left: 40px;"
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
