defmodule Site.Log do
  @moduledoc """
  The git-log style list of entries.

  Sorted by date descending, then type (essay, project, note), then title
  ascending. Each row carries the short hash of the last commit that touched the
  entry's file, linked to GitHub, or seven middle dots when there is none.
  """

  alias Site.Entry

  @no_hash String.duplicate("·", 7)

  @type row :: %{
          hash: String.t(),
          commit_url: String.t() | nil,
          date: String.t(),
          type: String.t(),
          title: String.t(),
          href: String.t()
        }

  @doc "The placeholder shown for an entry that is not committed yet."
  @spec no_hash() :: String.t()
  def no_hash, do: @no_hash

  @doc "Sorts entries in log order."
  @spec sort([Entry.t()]) :: [Entry.t()]
  def sort(entries) do
    Enum.sort_by(entries, fn entry ->
      {-Date.to_gregorian_days(entry.date), Site.Config.rank(entry.type),
       String.downcase(entry.title), entry.title, entry.slug}
    end)
  end

  @doc "Sorts entries and turns them into template rows."
  @spec rows([Entry.t()]) :: [row()]
  def rows(entries), do: entries |> sort() |> Enum.map(&row/1)

  @spec row(Entry.t()) :: row()
  def row(%Entry{} = entry) do
    %{
      hash: hash(entry),
      commit_url: entry.commit && Site.Git.commit_url(entry.commit),
      date: Date.to_iso8601(entry.date),
      type: Atom.to_string(entry.type),
      title: entry.title,
      href: Entry.path(entry)
    }
  end

  @doc "Short hash of the entry's last commit, or the dotted placeholder."
  @spec hash(Entry.t()) :: String.t()
  def hash(%Entry{commit: nil}), do: @no_hash
  def hash(%Entry{commit: sha}), do: Site.Git.short(sha)
end
