defmodule Site.Log do
  @moduledoc """
  The entries of the home timeline, newest first.

  Sorted by date descending, then type (essay, project, note), then title
  ascending. The type only orders the list; it is not shown. Each row carries the
  title, the short summary and the date, and links to the entry's page, or, for a
  project with a `link`, straight to that link.
  """

  alias Site.Entry

  @type row :: %{
          n: pos_integer(),
          title: String.t(),
          href: String.t(),
          external: String.t() | nil,
          summary: String.t(),
          date: String.t(),
          day: String.t(),
          month: String.t(),
          year: integer()
        }

  @doc "Sorts entries in timeline order."
  @spec sort([Entry.t()]) :: [Entry.t()]
  def sort(entries) do
    Enum.sort_by(entries, fn entry ->
      {-Date.to_gregorian_days(entry.date), Site.Config.rank(entry.type),
       String.downcase(entry.title), entry.title, entry.slug}
    end)
  end

  @doc "Sorts entries and turns them into template rows, numbered from 1."
  @spec rows([Entry.t()]) :: [row()]
  def rows(entries) do
    entries
    |> sort()
    |> Enum.with_index(1)
    |> Enum.map(fn {entry, n} -> Map.put(row(entry), :n, n) end)
  end

  @doc """
  Rows grouped by year, newest first: `[{2026, rows}, {2025, rows}]`. The timeline
  shows a year label where the year changes.
  """
  @spec years([row()]) :: [{integer(), [row()]}]
  def years(rows) do
    rows
    |> Enum.chunk_by(& &1.year)
    |> Enum.map(fn [first | _] = group -> {first.year, group} end)
  end

  @doc "One template row, without its number."
  @spec row(Entry.t()) :: map()
  def row(%Entry{} = entry) do
    {href, external} = target(entry)

    %{
      title: entry.title,
      href: href,
      external: external,
      summary: entry.summary || entry.description || "",
      date: Date.to_iso8601(entry.date),
      day: Site.View.short_date(entry.date),
      month: Calendar.strftime(entry.date, "%Y-%m"),
      year: entry.date.year
    }
  end

  # A project with a link goes straight to it, and says where it goes; everything
  # else goes to its own page. The project's page is still built, only not linked.
  defp target(%Entry{type: :project, link: link}) when is_binary(link),
    do: {link, external_label(link)}

  defp target(%Entry{} = entry), do: {Entry.path(entry), nil}

  @doc """
  What a screen reader hears after the title of an entry that leaves the site.

      iex> Site.Log.external_label("https://github.com/y0anfa/rhino")
      "on GitHub"
      iex> Site.Log.external_label("https://example.com/widget")
      "external"
  """
  @spec external_label(String.t()) :: String.t()
  def external_label(url) do
    case URI.parse(url).host do
      "github.com" -> "on GitHub"
      _ -> "external"
    end
  end
end
