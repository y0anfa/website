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

  describe "assets/favicon-sleep.svg" do
    test "has balanced tags and is under 1 KB" do
      assert byte_size(@asleep) < 1024

      # every tag is closed, in order: a cheap well-formedness check
      open =
        Regex.scan(~r{<(/?)([a-z]+)[^>]*?(/?)>}, @asleep)
        |> Enum.reduce([], fn
          [_, "", _name, "/"], stack -> stack
          [_, "", name, ""], stack -> [name | stack]
          [_, "/", name, ""], [name | stack] -> stack
        end)

      assert open == []
      assert @asleep =~ ~r/\A<svg [^>]*xmlns="http:\/\/www\.w3\.org\/2000\/svg"/
    end

    test "is the same 32x32 rounded square as the awake mark" do
      mark = ~S|<rect class="bg" x="0" y="0" width="32" height="32" rx="6"/>|

      assert @awake =~ mark
      assert @asleep =~ mark
      assert @asleep =~ ~S|viewBox="0 0 32 32"|
      assert @asleep =~ ~S|width="32" height="32"|
    end

    test "has the same light and dark palette, switched by the same media query" do
      for rule <- [
            ".bg { fill: #262523; }",
            ".stroke { stroke: #f4efe4; }",
            "@media (prefers-color-scheme: dark) {",
            ".bg { fill: #f4efe4; }",
            ".stroke { stroke: #262523; }"
          ] do
        assert @awake =~ rule, "awake lacks #{rule}"
        assert @asleep =~ rule, "asleep lacks #{rule}"
      end
    end

    test "is made of paths and rects, with a z z next to the prompt" do
      assert Enum.sort(tags(@asleep)) == ~w(g path rect style svg)
      refute @asleep =~ "<text"
      refute @asleep =~ ~r/<(script|image|use|foreignObject)/i
      refute @asleep =~ ~r/\son[a-z]+\s*=/i

      # the prompt chevron, then two z paths (a bigger and a smaller one)
      paths = Regex.scan(~r/<path [^>]*\sd="([^"]+)"/, @asleep) |> Enum.map(&List.last/1)
      assert length(paths) == 3
      assert Enum.at(paths, 0) =~ ~r/\AM[\d. ]+L[\d. ]+L[\d. ]+\z/
      assert Enum.drop(paths, 1) |> Enum.all?(&(&1 =~ ~r/\AM[\d. ]+H[\d. ]+L[\d. ]+H[\d. ]+\z/))
    end

    test "differs from the awake mark" do
      refute @asleep == @awake
    end

    test "is copied to the site", %{tree: tree} do
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
      assert @script =~ "setAttribute('href'"

      # it puts the original href back, whatever it was
      assert @script =~ "var awake = link.getAttribute('href');"
    end

    test "is a plain script: no innerHTML, no eval, no markup, no network, no module syntax" do
      for forbidden <- ~w(innerHTML outerHTML insertAdjacentHTML document.write eval Function
                          fetch XMLHttpRequest import export) do
        refute @script =~ ~r/\b#{Regex.escape(forbidden)}\b/, forbidden
      end

      refute @script =~ "<"
    end

    test "names a file that exists" do
      assert File.exists?("assets/favicon-sleep.svg")
    end

    test "is copied to the site verbatim", %{tree: tree} do
      assert tree["assets/js/favicon.js"] == @script
    end
  end

  describe "the pages" do
    test "every page, the 404 too, loads favicon.js deferred, right after theme.js", %{tree: tree} do
      for {path, html} <- tree, String.ends_with?(path, ".html") do
        assert html =~
                 ~s(<script defer src="/assets/js/theme.js"></script>\n) <>
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
