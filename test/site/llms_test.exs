defmodule Site.LlmsTest do
  use ExUnit.Case, async: true

  import Site.TestHelpers

  alias Site.{Content, Llms}

  setup_all do
    tree = build_fixtures() |> read_tree()
    %{tree: tree, llms: Map.fetch!(tree, "llms.txt")}
  end

  defp render(files) do
    files |> minimal_content() |> Content.load() |> Llms.render()
  end

  @note "---\ntitle: A note\ndate: 2026-10-28\ndescription: Said once.\n---\nbody"

  describe "llms.txt (llmstxt.org)" do
    test "opens with the name, a one-line summary and the intro as one plain paragraph", %{
      llms: llms
    } do
      assert String.starts_with?(
               llms,
               "# Yoan Faure\n\n" <>
                 "> Fixture home page for the test suite.\n\n" <>
                 "This is the intro paragraph. It has a link and some inline code. " <>
                 "A second paragraph keeps the intro honest about wrapping.\n\n" <>
                 "## Log\n"
             )
    end

    test "the intro paragraph is plain text: no Markdown, no HTML", %{llms: llms} do
      [_h1, _summary, intro | _sections] = String.split(llms, "\n\n")

      refute intro =~ ~r/[\[\]`*_<>]/
      refute intro =~ "example.com"
    end

    test "lists every entry in one Log section, in log order, with no type", %{llms: llms} do
      assert Regex.scan(~r/^## (.+)$/m, llms) |> Enum.map(&List.last/1) == ["Log"]

      links =
        Regex.scan(~r{^- \[.*?\]\(https://yoanfaure\.com/([a-z0-9-]+)\.md\)}m, llms)
        |> Enum.map(&List.last/1)

      assert links == ~w(second-essay widget small-note escape-me first-essay)
    end

    test "every item is a link to a Markdown twin, then a colon and the description", %{
      llms: llms,
      tree: tree
    } do
      items = Regex.scan(~r/^- .*$/m, llms) |> List.flatten()
      assert length(items) == 5

      for item <- items do
        assert item =~ ~r{\A- \[[^\]]+\]\(https://yoanfaure\.com/[a-z0-9-]+\.md\): \S}, item
      end

      assert llms =~
               "- [Second essay](https://yoanfaure.com/second-essay.md): " <>
                 "A second essay, with its own description.\n"

      # a project's description is its tagline
      assert llms =~
               "- [widget](https://yoanfaure.com/widget.md): A small widget for the fixtures.\n"

      # every link has a file behind it
      for [_, slug] <- Regex.scan(~r{\(https://yoanfaure\.com/([a-z0-9-]+)\.md\)}, llms) do
        assert Map.has_key?(tree, slug <> ".md"), slug
      end
    end

    test "ends with one newline and is a plain text file", %{llms: llms} do
      assert String.ends_with?(llms, "\n")
      refute String.ends_with?(llms, "\n\n")
      assert String.valid?(llms)

      # plain text, not HTML: a title is written as it is, and nothing is escaped
      assert llms =~
               ~S|- [Tom & "Jerry" <script>alert(1)</script>](https://yoanfaure.com/escape-me.md)|

      refute llms =~ ~r/\n{3,}/
    end

    test "one entry is one Log section with one item, whatever its type" do
      llms = render(%{"notes/a.md" => @note})

      assert llms =~ "## Log\n\n- [A note](https://yoanfaure.com/a.md): Said once.\n"
      refute llms =~ "## Notes"
    end

    test "an empty log is the name, the summary and the intro" do
      assert render(%{}) == "# Yoan Faure\n\n> d\n\nbody\n"
    end

    test "an entry without a description is just a link" do
      llms = render(%{"notes/a.md" => "---\ntitle: A note\ndate: 2026-10-28\n---\n"})
      assert llms =~ "- [A note](https://yoanfaure.com/a.md)\n"
    end

    test "brackets in a title cannot close the link early" do
      note = "---\ntitle: '[draft] a\\b'\ndate: 2026-10-28\ndescription: d\n---\nbody"
      llms = render(%{"notes/a.md" => note})

      assert llms =~ ~S|- [\[draft\] a\\b](https://yoanfaure.com/a.md): d|
    end

    test "a multi-line description stays on one line" do
      note = "---\ntitle: A note\ndate: 2026-10-28\ndescription: |\n  one\n  two\n---\nbody"
      assert render(%{"notes/a.md" => note}) =~ "[A note](https://yoanfaure.com/a.md): one two\n"
    end

    test "has no draft", %{llms: llms} do
      refute llms =~ "unfinished"
    end

    test "is the same on every build" do
      content = fixture_copy()
      a = [content: content] |> build_fixtures() |> read_tree()
      b = [content: content] |> build_fixtures() |> read_tree()
      assert a["llms.txt"] == b["llms.txt"]
    end
  end
end
