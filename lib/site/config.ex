defmodule Site.Config do
  @moduledoc """
  Constants of the site: identity, URLs, navigation, and the one-line sentence
  shown under each list page title.
  """

  @url "https://yoanfau.re"

  @types [
    # type, section (directory and URL segment), log sort rank
    essay: %{section: "essays", rank: 0},
    project: %{section: "projects", rank: 1},
    note: %{section: "notes", rank: 2}
  ]

  @nav ["essays", "notes", "projects", "uses", "cv"]

  @list_intros %{
    "essays" => "Longer pieces on security and the things I build.",
    "notes" => "Short notes, one idea each.",
    "projects" => "Things I have built."
  }

  def name, do: "Yoan Faure"
  def home_title, do: "Yoan Faure — security engineer who builds"
  def repo_url, do: "https://github.com/y0anfa/yoanfau.re"
  def email, do: "hello@yoanfau.re"
  def linkedin, do: "https://linkedin.com/in/yoan-faure"

  @doc "Navigation sections, in display order."
  def nav, do: @nav

  @doc "Entry types that appear in the log."
  def types, do: Keyword.keys(@types)

  @doc "Section name for an entry type (`:essay` -> `\"essays\"`)."
  def section(type), do: @types[type].section

  @doc "Sort rank of an entry type in the log (essay, project, note)."
  def rank(type), do: @types[type].rank

  @doc "The plain sentence under a list page title."
  def list_intro(section), do: Map.fetch!(@list_intros, section)

  @doc "Absolute URL for a site path."
  def absolute(path), do: @url <> path
end
