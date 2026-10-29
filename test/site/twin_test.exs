defmodule Site.TwinTest do
  use ExUnit.Case, async: true

  import Site.TestHelpers

  alias Site.{Config, Content, Entry, Frontmatter, Headers, Twin}

  # One shared, read-only build of the fixtures.
  setup_all do
    %{tree: build_fixtures() |> read_tree()}
  end

  defp entry(attrs) do
    struct!(
      Entry,
      Map.merge(
        %{
          type: :note,
          slug: "x",
          title: "X",
          date: ~D[2026-10-28],
          description: "d",
          body: "Body.\n"
        },
        Map.new(attrs)
      )
    )
  end

  describe "the twin of an essay or a note" do
    test "is the title, one line saying when and where it is, and the original Markdown body",
         %{tree: tree} do
      {:ok, _meta, body} =
        fixtures()
        |> Path.join("essays/2026-03-28-first-essay.md")
        |> File.read!()
        |> Frontmatter.parse()

      assert Map.fetch!(tree, "first-essay.md") ==
               "# First essay\n\n" <>
                 "2026-03-28 · https://yoanfaure.com/first-essay/\n\n" <>
                 String.trim(body) <> "\n"
    end

    test "strips the frontmatter and keeps Markdown, not HTML", %{tree: tree} do
      twin = Map.fetch!(tree, "first-essay.md")

      refute twin =~ ~r/^---$/m
      refute twin =~ "title: First essay"
      refute twin =~ "date: 2026-03-28"

      assert twin =~ "## A heading"
      assert twin =~ "~~strikethrough~~"
      assert twin =~ "[^1]: The footnote text."
      refute twin =~ "<h2"
      refute twin =~ "<p>"
    end

    test "a note is the same shape", %{tree: tree} do
      assert Map.fetch!(tree, "small-note.md") ==
               "# Small note\n\n2026-10-28 · https://yoanfaure.com/small-note/\n\n" <>
                 "One idea, said once.\n"
    end

    test "ends with exactly one newline and has no stray blank lines around the body", %{
      tree: tree
    } do
      for {file, twin} <- tree, String.ends_with?(file, ".md") do
        assert String.ends_with?(twin, "\n"), file
        refute String.ends_with?(twin, "\n\n"), file
        refute twin =~ ~r/\n{3,}\z/, file
      end
    end

    test "the title is one line" do
      twin = Twin.render(entry(title: "Two\nlines  here"))
      assert String.starts_with?(twin, "# Two lines here\n\n")
    end

    test "an empty body leaves no trailing blank line" do
      twin = Twin.render(entry(body: "\n\n"))
      assert twin == "# X\n\n2026-10-28 · https://yoanfaure.com/x/\n"
    end
  end

  describe "the twin of a project" do
    test "adds the tagline and the link after the meta line", %{tree: tree} do
      assert Map.fetch!(tree, "widget.md") ==
               "# widget\n\n" <>
                 "2026-10-28 · https://yoanfaure.com/widget/\n\n" <>
                 "> A small widget for the fixtures.\n\n" <>
                 "link: https://example.com/widget\n\n" <>
                 "Widget is a fixture project.\n\n- one\n- two\n"
    end

    test "has no link line without a link" do
      twin = Twin.render(entry(type: :project, tagline: "A tagline.", link: nil))

      assert twin =~ "> A tagline.\n"
      refute twin =~ "link:"
    end
  end

  describe "the build" do
    test "writes one <slug>.md per entry, at the top level, and none for a draft", %{tree: tree} do
      twins = tree |> Map.keys() |> Enum.filter(&String.ends_with?(&1, ".md")) |> Enum.sort()

      assert twins == ~w(escape-me.md first-essay.md second-essay.md small-note.md widget.md)
      refute Map.has_key?(tree, "an-unfinished-draft.md")
    end

    test "writes a draft's twin with drafts: true" do
      tree = [drafts: true] |> build_fixtures() |> read_tree()
      assert Map.fetch!(tree, "an-unfinished-draft.md") =~ "# An unfinished draft\n"
    end

    test "Twin.files is the twins and llms.txt, in path order, with no duplicate" do
      files = fixture_copy() |> Content.load() |> Twin.files()
      names = Enum.map(files, &elem(&1, 0))

      assert names ==
               ~w(escape-me.md first-essay.md llms.txt second-essay.md small-note.md widget.md)

      assert names == Enum.uniq(names)
    end

    test "a twin never takes the place of a page or a site file", %{tree: tree} do
      twins = for file <- Map.keys(tree), String.ends_with?(file, ".md"), do: file

      for twin <- twins do
        slug = String.replace_suffix(twin, ".md", "")
        refute slug in Config.reserved_slugs(), "#{twin} is a reserved name"
        refute Map.has_key?(tree, slug), "#{twin} collides with #{slug}"
      end
    end
  end

  describe "reserved slugs" do
    test "llms and llms.txt are reserved" do
      assert "llms" in Config.reserved_slugs()
      assert "llms.txt" in Config.reserved_slugs()
      assert Config.reserved_slugs() == Config.reserved_slugs() |> Enum.uniq() |> Enum.sort()
    end

    test "an entry cannot be called llms or llms.txt" do
      for slug <- ~w(llms llms.txt) do
        dir =
          minimal_content(%{
            "notes/#{slug}.md" => "---\ntitle: N\ndate: 2026-10-28\n---\nbody"
          })

        error = assert_raise Site.Error, fn -> Content.load(dir) end
        assert error.message =~ "slug #{inspect(slug)} is reserved", slug
      end
    end
  end

  describe "the head link" do
    test "every entry page points at its twin, and only entry pages do", %{tree: tree} do
      for slug <- ~w(escape-me first-essay second-essay small-note widget) do
        html = Map.fetch!(tree, "#{slug}/index.html")
        link = ~s(<link rel="alternate" type="text/markdown" href="/#{slug}.md">)

        assert length(Regex.scan(~r/rel="alternate"/, html)) == 1, slug
        [head, _body] = String.split(html, "</head>")
        assert head =~ link, slug
        assert Map.has_key?(tree, "#{slug}.md")
      end

      for page <- ["index.html", "404.html"] do
        refute Map.fetch!(tree, page) =~ "rel=\"alternate\"", page
      end
    end
  end

  describe "Content-Type" do
    test "_headers gives the twins and llms.txt a text type with a charset", %{tree: tree} do
      rules = tree |> Map.fetch!("_headers") |> Headers.parse()

      for path <- ["/rhino.md", "/first-essay.md", "/a/b.md"] do
        assert {"Content-Type", "text/markdown; charset=utf-8"} in Headers.for_path(rules, path)
      end

      assert {"Content-Type", "text/plain; charset=utf-8"} in Headers.for_path(rules, "/llms.txt")
    end

    test "no other path gets a Content-Type from _headers", %{tree: tree} do
      rules = tree |> Map.fetch!("_headers") |> Headers.parse()

      for path <- [
            "/",
            "/rhino/",
            "/404.html",
            "/robots.txt",
            "/assets/css/site.css",
            "/assets/favicon.svg"
          ] do
        refute Enum.any?(Headers.for_path(rules, path), &match?({"Content-Type", _}, &1)), path
      end
    end
  end
end
