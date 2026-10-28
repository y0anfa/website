defmodule Site.LogTest do
  use ExUnit.Case, async: true

  import Site.TestHelpers

  alias Site.{Content, Entry, Log}

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

  test "the fixture log is in the documented order" do
    content = Content.load(fixtures())

    assert content |> Content.entries() |> Log.sort() |> Enum.map(& &1.title) == [
             "Second essay",
             "widget",
             "Small note",
             ~S|Tom & "Jerry" <script>alert(1)</script>|,
             "First essay"
           ]
  end

  test "an uncommitted entry shows seven middle dots and no link" do
    row = Log.row(entry(:essay, "x", "2026-03-28"))

    assert row.hash == "·······"
    assert String.length(row.hash) == 7
    assert row.commit_url == nil
    assert row.date == "2026-03-28"
    assert row.type == "essay"
    assert row.href == "/x/"
  end

  test "a committed entry shows the first 7 characters, linked to GitHub" do
    sha = "a3f9c21" <> String.duplicate("0", 33)
    row = Log.row(entry(:note, "x", "2026-10-28", commit: sha))

    assert row.hash == "a3f9c21"
    assert row.commit_url == "https://github.com/y0anfa/yoanfau.re/commit/" <> sha
    assert row.href == "/x/"
  end

  test "fixtures copied outside git have no commits" do
    content = Content.load(fixture_copy())
    assert Enum.all?(Content.entries(content), &(&1.commit == nil))
    assert content |> Content.entries() |> Log.rows() |> Enum.all?(&(&1.hash == "·······"))
  end
end
