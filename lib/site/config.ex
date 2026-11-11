defmodule Site.Config do
  @moduledoc """
  Constants of the site: identity and position, URLs, entry types, legacy
  redirects, and the slugs that entries may not use.
  """

  @url "https://yoanfaure.com"

  @types [
    # type, content directory under content/, timeline sort rank
    essay: %{dir: "essays", rank: 0},
    project: %{dir: "projects", rank: 1},
    note: %{dir: "notes", rank: 2}
  ]

  # Old Hugo URLs, sent to the flat URLs of this site: from, to, status.
  @redirects [
    {"/blog/*", "/:splat", 301},
    {"/projects/*", "/:splat", 301},
    {"/resume/", "/", 301},
    {"/resume", "/", 301}
  ]

  # Top-level names of files and directories the build writes.
  @site_paths ~w(assets 404 404.html home index index.html llms llms.txt og robots.txt _headers _redirects)

  def name, do: "Yoan Faure"
  def home_title, do: "Yoan Faure — Security engineer at Riot"
  def repo_url, do: "https://github.com/y0anfa/website"

  @doc "The position under the name on the home: `Security engineer at Riot`, Riot linked."
  def role, do: %{title: "Security engineer", company: "Riot", url: "https://tryriot.com"}

  @doc "Entry types that appear on the timeline."
  def types, do: Keyword.keys(@types)

  @doc "Content directory of an entry type (`:essay` -> `\"essays\"`). It sets the type, not the URL."
  def dir(type), do: @types[type].dir

  @doc "Sort rank of an entry type on the timeline (essay, project, note)."
  def rank(type), do: @types[type].rank

  @doc "Legacy redirects as `{from, to, status}`, in file order."
  def redirects, do: @redirects

  @doc """
  Slugs no entry may use, because `/<slug>/` would collide with a site path or
  be taken over by a legacy redirect (`blog`, `projects`, `resume`).
  """
  def reserved_slugs do
    redirected =
      for {from, _to, _status} <- @redirects, do: from |> String.split("/") |> Enum.at(1)

    Enum.sort(Enum.uniq(@site_paths ++ redirected))
  end

  @doc "Absolute URL for a site path."
  def absolute(path), do: @url <> path
end
