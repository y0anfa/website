defmodule Site.Config do
  @moduledoc """
  Constants of the site: identity, URLs, entry types, legacy redirects, and the
  slugs that entries may not use.
  """

  @url "https://yoanfaure.com"

  @types [
    # type, content directory under content/, log sort rank
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
  def home_title, do: "Yoan Faure — security engineer who builds"
  def repo_url, do: "https://github.com/y0anfa/website"
  def email, do: "hi@yoanfaure.com"
  def linkedin, do: "https://linkedin.com/in/yoan-faure"

  @doc "Entry types that appear in the log."
  def types, do: Keyword.keys(@types)

  @doc "Content directory of an entry type (`:essay` -> `\"essays\"`). It sets the type, not the URL."
  def dir(type), do: @types[type].dir

  @doc "Sort rank of an entry type in the log (essay, project, note)."
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
