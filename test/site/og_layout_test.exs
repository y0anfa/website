defmodule Site.OGLayoutTest do
  use ExUnit.Case, async: true

  import Site.TestHelpers, only: [tmp_dir: 0]

  alias Site.OG.Text

  @sizes [96, 84, 72, 62, 54]
  @max_width 1056

  setup_all do
    %{font: Text.load!("priv/og-fonts/Inter-Bold.ttf")}
  end

  defp fit(font, text, opts \\ []) do
    Text.fit(
      font,
      text,
      Keyword.merge(
        [sizes: @sizes, max_lines: 3, max_width: @max_width, tracking_em: -0.02],
        opts
      )
    )
  end

  describe "Text" do
    test "reads the metrics of the font", %{font: font} do
      assert font.units == 2048
      assert Text.advance(font, ?A) > 0
      assert Text.advance(font, ?\s) > 0
      assert Text.advance(font, ?i) < Text.advance(font, ?m)
    end

    test "has no advance for a character the font lacks", %{font: font} do
      assert Text.advance(font, 0x4E2D) == nil
      assert Text.advance(font, 0x10FFFF) == nil
    end

    test "refuses a file that is not a font" do
      path = Path.join(tmp_dir(), "not-a-font.ttf")
      File.write!(path, "this is not a font")

      assert_raise Site.Error, ~r/not a TrueType or OpenType font/, fn -> Text.load!(path) end
    end

    test "clean/2 collapses whitespace, drops what the font cannot draw, trims", %{font: font} do
      assert Text.clean(font, "  a \n\t b  c  ") == "a b c"
      assert Text.clean(font, "ok \u0007 ok") == "ok ok"
      assert Text.clean(font, "x\u{4E2D}y") == "xy"
      assert Text.clean(font, "🙂🙃") == ""
      assert Text.clean(font, "Tom & “Jerry” — é") == "Tom & “Jerry” — é"
    end

    test "width/4 grows with the size and shrinks with tight tracking", %{font: font} do
      assert Text.width(font, "Threat", 100) > Text.width(font, "Threat", 50)
      assert_in_delta Text.width(font, "Threat", 100), 2 * Text.width(font, "Threat", 50), 0.001
      assert Text.width(font, "Threat", 100, -2) < Text.width(font, "Threat", 100)
      assert Text.width(font, "", 100) == 0
    end
  end

  describe "Text.fit/3" do
    test "a short title takes the largest size, on one line", %{font: font} do
      assert fit(font, "rhino") == {96, ["rhino"]}
    end

    test "balances two lines instead of leaving one word alone", %{font: font} do
      assert fit(font, "Threat modeling with Claude Code") ==
               {96, ["Threat modeling", "with Claude Code"]}
    end

    test "a longer title steps down to a smaller size to stay within three lines", %{font: font} do
      title = "Why a lightweight, fine-tuned tool beats expensive and complex security software"
      {size, lines} = fit(font, title)

      assert size < 96
      assert size in @sizes
      assert length(lines) <= 3
      assert Enum.join(lines, " ") == title
    end

    test "no line is wider than the maximum", %{font: font} do
      titles = [
        "Security pays in more than one currency",
        "Comms is the staff skill",
        "A title with Wide Letters like MMMMMM WWWWWW and more of them to wrap around",
        String.duplicate("word ", 30) |> String.trim()
      ]

      for title <- titles do
        {size, lines} = fit(font, title)

        for line <- lines do
          assert Text.width(font, line, size, size * -0.02) <= @max_width, line
        end
      end
    end

    test "a title too long for three lines ends with an ellipsis, at the smallest size",
         %{font: font} do
      {size, lines} = fit(font, String.duplicate("word ", 80) |> String.trim())

      assert size == 54
      assert length(lines) == 3
      assert List.last(lines) |> String.ends_with?("…")
      assert Text.width(font, List.last(lines), size, size * -0.02) <= @max_width
    end

    test "a word wider than a line is split between characters", %{font: font} do
      {size, lines} = fit(font, String.duplicate("x", 120), max_lines: 5)

      assert length(lines) > 1
      assert lines |> Enum.join() |> String.replace("…", "") |> String.length() > 60

      for line <- lines, do: assert(Text.width(font, line, size, size * -0.02) <= @max_width)
    end

    test "an empty text has no lines", %{font: font} do
      assert fit(font, "") == {96, []}
    end

    test "the layout is the same every time", %{font: font} do
      title = "Security pays in more than one currency"
      assert fit(font, title) == fit(font, title)
    end
  end
end
