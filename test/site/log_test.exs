defmodule Site.LogTest do
  use ExUnit.Case, async: true

  import Site.TestHelpers

  alias Site.{Content, Entry, Log}

  doctest Site.Log

  defp entry(type, title, date, extra \\ []) do
    struct!(
      Entry,
      [type: type, slug: String.downcase(title), title: title, date: Date.from_iso8601!(date)] ++
        extra
    )
  end

  test "sorts by date descending, then type (essay, project, note), then title ascending" do
    entries = [
      entry(:note, "b note", "2026-10-28"),
      entry(:essay, "old essay", "2026-01-01"),
      entry(:project, "proj", "2026-10-28"),
      entry(:note, "A note", "2026-10-28"),
      entry(:essay, "z essay", "2026-10-28"),
      entry(:essay, "a essay", "2026-10-28"),
      entry(:note, "newest", "2026-11-02")
    ]

    assert entries |> Log.sort() |> Enum.map(& &1.title) ==
             ["newest", "a essay", "z essay", "proj", "A note", "b note", "old essay"]
  end

  test "title ordering ignores case" do
    titles = [entry(:note, "banana", "2026-01-01"), entry(:note, "Apple", "2026-01-01")]
    assert titles |> Log.sort() |> Enum.map(& &1.title) == ["Apple", "banana"]
  end

  test "the fixture timeline is in the documented order" do
    content = Content.load(fixtures())

    assert content |> Content.entries() |> Log.sort() |> Enum.map(& &1.title) == [
             "Second essay",
             "widget",
             "Small note",
             ~S|Tom & "Jerry" <script>alert(1)</script>|,
             "First essay"
           ]
  end

  test "a row is the title, the summary and the date, linked to the entry's page" do
    row = Log.row(entry(:essay, "x", "2026-03-08", summary: "Short.", description: "Long."))

    assert row == %{
             title: "x",
             href: "/x/",
             external: nil,
             summary: "Short.",
             date: "2026-03-08",
             day: "8 Mar",
             month: "2026-03",
             year: 2026
           }

    refute Map.has_key?(row, :type)
    refute Map.has_key?(row, :hash)
  end

  test "the summary falls back to the description, then to nothing" do
    assert Log.row(entry(:note, "x", "2026-03-08", description: "Long.")).summary == "Long."
    assert Log.row(entry(:note, "x", "2026-03-08")).summary == ""
  end

  test "a project with a link goes there and says where; without one, to its page" do
    github = entry(:project, "rhino", "2026-09-02", link: "https://github.com/y0anfa/rhino")
    assert %{href: "https://github.com/y0anfa/rhino", external: "on GitHub"} = Log.row(github)

    other = entry(:project, "w", "2026-09-02", link: "https://example.com/w")
    assert %{href: "https://example.com/w", external: "external"} = Log.row(other)

    assert %{href: "/p/", external: nil} = Log.row(entry(:project, "p", "2026-09-02"))

    # only a project leaves the site: a link field elsewhere means nothing
    assert %{href: "/n/", external: nil} =
             Log.row(entry(:note, "n", "2026-09-02", link: "https://example.com/"))
  end

  test "rows are numbered from 1 in timeline order" do
    rows =
      Log.rows([
        entry(:note, "old", "2025-12-31"),
        entry(:note, "new", "2026-01-02")
      ])

    assert Enum.map(rows, &{&1.n, &1.title}) == [{1, "new"}, {2, "old"}]
  end

  test "years groups the rows where the year changes, newest first" do
    rows =
      Log.rows([
        entry(:note, "a", "2026-02-01"),
        entry(:note, "b", "2025-11-20"),
        entry(:note, "c", "2025-01-05"),
        entry(:note, "d", "2024-06-01")
      ])

    assert rows
           |> Log.years()
           |> Enum.map(fn {year, group} -> {year, Enum.map(group, & &1.title)} end) ==
             [{2026, ["a"]}, {2025, ["b", "c"]}, {2024, ["d"]}]

    assert Log.years([]) == []
  end
end
