defmodule Site.ContentTest do
  use ExUnit.Case, async: true

  import Site.TestHelpers

  alias Site.{Content, Entry}

  doctest Site.Content

  defp load_error(files) do
    assert_raise Site.Error, fn -> files |> minimal_content() |> Content.load() end
  end

  describe "the fixture content" do
    setup do
      %{content: Content.load(fixtures())}
    end

    test "loads every type", %{content: content} do
      assert %Site.Doc{key: :home, title: "Test Person"} = content.home
      assert %Site.Doc{key: :uses} = content.uses
      assert %Site.Doc{key: :cv} = content.cv
      assert Enum.map(content.essays, & &1.slug) == ["first-essay", "second-essay"]
      assert Enum.map(content.notes, & &1.slug) == ["escape-me", "small-note"]
      assert Enum.map(content.projects, & &1.slug) == ["widget"]
      assert length(Content.entries(content)) == 5
    end

    test "drafts are skipped unless asked for" do
      refute Enum.any?(Content.load(fixtures()).essays, &(&1.slug == "an-unfinished-draft"))

      with_drafts = Content.load(fixtures(), drafts: true)
      assert Enum.any?(with_drafts.essays, &(&1.slug == "an-unfinished-draft"))
    end

    test "slugs lose the extension and the date prefix", %{content: content} do
      first = Enum.find(content.essays, &(&1.title == "First essay"))
      assert first.slug == "first-essay"
      assert Entry.path(first) == "/essays/first-essay/"
      assert Enum.find(content.essays, &(&1.title == "Second essay")).slug == "second-essay"
    end

    test "dates are parsed", %{content: content} do
      assert Enum.find(content.essays, &(&1.slug == "first-essay")).date == ~D[2026-03-28]
    end

    test "description comes from frontmatter, else the first paragraph, else the tagline",
         %{content: content} do
      second = Enum.find(content.essays, &(&1.slug == "second-essay"))
      assert second.description == "A second essay, with its own description."

      first = Enum.find(content.essays, &(&1.slug == "first-essay"))

      assert first.description =~
               ~r/^An essay without a description, so the first paragraph with emphasis, code and a link becomes/

      assert String.length(first.description) <= 160
      assert String.ends_with?(first.description, "…")

      widget = hd(content.projects)
      assert widget.description == "A small widget for the fixtures."
    end

    test "project fields", %{content: content} do
      widget = hd(content.projects)
      assert widget.tagline == "A small widget for the fixtures."
      assert widget.link == "https://example.com/widget"
      assert widget.stack == ["Elixir", "YAML"]
      assert widget.status == "active"
      assert widget.html =~ "<li>one</li>"
    end

    test "Markdown is rendered to HTML", %{content: content} do
      assert content.home.html =~ ~s(<a href="https://example.com/">link</a>)
      assert content.home.tagline == "Fixture tagline for the home page."
      assert content.uses.html =~ "<table>"
    end
  end

  describe "validation" do
    test "a missing required field fails loudly, naming the file" do
      error = load_error(%{"notes/n.md" => "---\ndate: 2026-10-28\n---\nbody"})
      assert error.message =~ "notes/n.md"
      assert error.message =~ "missing required field `title`"
    end

    test "a missing date" do
      error = load_error(%{"notes/n.md" => "---\ntitle: N\n---\nbody"})
      assert error.message =~ "missing required field `date`"
    end

    test "a bad date" do
      for bad <- ["2026-13-45", "yesterday", "28/10/2026", "2026-10"] do
        error = load_error(%{"notes/n.md" => "---\ntitle: N\ndate: #{bad}\n---\nbody"})
        assert error.message =~ "`date` must be an ISO date", "accepted #{bad}"
      end
    end

    test "a non-string title must be quoted" do
      error = load_error(%{"notes/n.md" => "---\ntitle: 1984\ndate: 2026-10-28\n---\nbody"})
      assert error.message =~ "`title` must be a string (quote it)"
    end

    test "projects need a tagline" do
      error = load_error(%{"projects/p.md" => "---\ntitle: p\ndate: 2026-10-28\n---\nbody"})
      assert error.message =~ "missing required field `tagline`"
    end

    test "project status and link are checked" do
      head = "---\ntitle: p\ndate: 2026-10-28\ntagline: t\n"

      error = load_error(%{"projects/p.md" => head <> "status: sleeping\n---\nbody"})
      assert error.message =~ "`status` must be one of active, wip, archived"

      error = load_error(%{"projects/p.md" => head <> "link: javascript:alert(1)\n---\nbody"})
      assert error.message =~ "`link` must be an http(s) URL"

      error = load_error(%{"projects/p.md" => head <> "stack: Go\n---\nbody"})
      assert error.message =~ "`stack` must be a list"
    end

    test "draft must be a boolean" do
      error =
        load_error(%{"notes/n.md" => "---\ntitle: N\ndate: 2026-10-28\ndraft: ture\n---\nbody"})

      assert error.message =~ "`draft` must be true or false"
    end

    test "a duplicate slug within a type" do
      note = "---\ntitle: N\ndate: 2026-10-28\n---\nbody"

      error =
        load_error(%{"notes/2026-10-28-same.md" => note, "notes/same.md" => note})

      assert error.message =~ "duplicate note slug \"same\""
      assert error.message =~ "2026-10-28-same.md"
    end

    test "the same slug in different types is fine" do
      note = "---\ntitle: N\ndate: 2026-10-28\n---\nbody"
      essay = note

      content =
        minimal_content(%{"notes/same.md" => note, "essays/same.md" => essay}) |> Content.load()

      assert length(Content.entries(content)) == 2
    end

    test "a duplicate slug involving a skipped draft is not an error" do
      note = "---\ntitle: N\ndate: 2026-10-28\n---\nbody"
      draft = "---\ntitle: N\ndate: 2026-10-28\ndraft: true\n---\nbody"

      content =
        minimal_content(%{"notes/same.md" => note, "notes/2026-10-28-same.md" => draft})
        |> Content.load()

      assert length(content.notes) == 1
    end

    test "slugs must be URL-safe" do
      error = load_error(%{"notes/Bad Name.md" => "---\ntitle: N\ndate: 2026-10-28\n---\nbody"})
      assert error.message =~ "slug \"Bad Name\""
    end

    test "frontmatter problems are reported with the file" do
      error = load_error(%{"notes/n.md" => "no frontmatter"})
      assert error.message =~ "notes/n.md: missing frontmatter"
    end

    test "pages need a title and a description" do
      dir = minimal_content()
      File.write!(Path.join(dir, "cv.md"), "---\ntitle: cv\n---\nbody")
      error = assert_raise Site.Error, fn -> Content.load(dir) end
      assert error.message =~ "cv.md: missing required field `description`"
    end

    test "a missing page file is an error" do
      dir = minimal_content()
      File.rm!(Path.join(dir, "uses.md"))
      error = assert_raise Site.Error, fn -> Content.load(dir) end
      assert error.message =~ "uses.md: cannot read file"
    end

    test "all problems are reported together" do
      error =
        load_error(%{
          "notes/a.md" => "---\ntitle: A\n---\nbody",
          "notes/b.md" => "---\ndate: 2026-10-28\n---\nbody"
        })

      assert error.message =~ "2 problem(s)"
      assert error.message =~ "notes/a.md"
      assert error.message =~ "notes/b.md"
    end

    test "missing directories are just empty" do
      content = Content.load(minimal_content())
      assert Content.entries(content) == []
    end
  end

  describe "slug/1" do
    test "strips only a leading date prefix" do
      assert Content.slug("2026-03-28-threat-modeling.md") == "threat-modeling"
      assert Content.slug("a/b/2026-03-28-2026-01-01-x.md") == "2026-01-01-x"
      assert Content.slug("rhino.md") == "rhino"
      assert Content.slug("my-2026-03-28-post.md") == "my-2026-03-28-post"
    end
  end
end
