defmodule Site.FaviconTest do
  use ExUnit.Case, async: true

  import Site.TestHelpers

  @awake File.read!("assets/favicon.svg")
  @asleep File.read!("assets/favicon-sleep.svg")
  @script File.read!("assets/js/favicon.js")

  setup_all do
    %{tree: build_fixtures() |> read_tree()}
  end

  defp tags(svg),
    do: Regex.scan(~r/<([a-z]+)[\s>\/]/, svg) |> Enum.map(&List.last/1) |> Enum.uniq()

  # every tag is closed, in order: a cheap well-formedness check
  defp balanced?(svg) do
    Regex.scan(~r{<(/?)([a-z]+)[^>]*?(/?)>}, svg)
    |> Enum.reduce([], fn
      [_, "", _name, "/"], stack -> stack
      [_, "", name, ""], stack -> [name | stack]
      [_, "/", name, ""], [name | stack] -> stack
    end) == []
  end

  describe "the marks" do
    test "are small, well-formed SVGs made of shapes only" do
      for svg <- [@awake, @asleep] do
        assert byte_size(svg) < 1024
        assert balanced?(svg)
        assert svg =~ ~r/\A<svg [^>]*xmlns="http:\/\/www\.w3\.org\/2000\/svg"/
        assert Enum.sort(tags(svg)) -- ~w(circle path rect style svg) == []
        refute svg =~ ~r/<(text|script|image|use|foreignObject)/i
        refute svg =~ ~r/\son[a-z]+\s*=/i
      end
    end

    test "are the same graphite square with the timeline's axis" do
      square = ~S|<rect class="bg" x="0" y="0" width="32" height="32" rx="6"/>|
      axis = ~S|d="M16 5 V27"|

      for svg <- [@awake, @asleep] do
        assert svg =~ square
        assert svg =~ axis
        assert svg =~ ~S|viewBox="0 0 32 32"|
        assert svg =~ ".bg { fill: #0e0f12; }"
      end
    end

    test "awake, the mark is filled; asleep, it is an empty ring; neither has a colour" do
      assert @awake =~ ".mark { fill: #ecebe8; stroke: #0e0f12; }"
      assert @asleep =~ ".mark { fill: #0e0f12; stroke: #80848d; }"

      for svg <- [@awake, @asleep] do
        assert length(Regex.scan(~r/<circle class="mark"/, svg)) == 1
        refute svg =~ "#f2c47c"
      end
    end

    test "the old palettes are gone" do
      for svg <- [@awake, @asleep], old <- ~w(#262523 #f4efe4 #0d0f14) do
        refute svg =~ old
      end
    end

    test "are copied to the site", %{tree: tree} do
      assert tree["assets/favicon-sleep.svg"] == @asleep
      assert tree["assets/favicon.svg"] == @awake
    end
  end

  describe "assets/js/favicon.js" do
    test "swaps the icon link on visibilitychange, to the sleep SVG when hidden and back" do
      assert @script =~ ~s|document.querySelector('link[rel="icon"]')|
      assert @script =~ "document.addEventListener('visibilitychange'"
      assert @script =~ "document.visibilityState === 'hidden'"
      assert @script =~ "'/assets/favicon-sleep.svg'"
      assert @script =~ "var awake = link.getAttribute('href');"
    end

    test "is a plain script: no innerHTML, no eval, no markup, no network, no module syntax" do
      for forbidden <- ~w(innerHTML outerHTML insertAdjacentHTML document.write eval Function
                          fetch XMLHttpRequest import export) do
        refute @script =~ ~r/\b#{Regex.escape(forbidden)}\b/, forbidden
      end

      refute @script =~ "<"
    end

    test "is copied to the site verbatim", %{tree: tree} do
      assert tree["assets/js/favicon.js"] == @script
    end
  end

  describe "the pages" do
    test "every page, the 404 too, loads favicon.js deferred, right after site.js", %{tree: tree} do
      for {path, html} <- tree, String.ends_with?(path, ".html") do
        assert html =~
                 ~s(<script defer blocking="render" src="/assets/js/site.js"></script>\n) <>
                   ~s(<script defer src="/assets/js/favicon.js"></script>\n),
               path

        assert length(Regex.scan(~r{/assets/js/favicon\.js}, html)) == 1, path
      end
    end

    test "every page has one icon link for the script to swap", %{tree: tree} do
      for {path, html} <- tree, String.ends_with?(path, ".html") do
        assert Regex.scan(~r/<link rel="icon" /, html) |> length() == 1, path
        assert html =~ ~s(<link rel="icon" href="/assets/favicon.svg" type="image/svg+xml">), path
      end
    end

    test "the sleep icon is only ever named by the script, not by a page", %{tree: tree} do
      for {path, content} <- tree, String.ends_with?(path, [".html", "_headers"]) do
        refute content =~ "favicon-sleep", path
      end
    end
  end
end
