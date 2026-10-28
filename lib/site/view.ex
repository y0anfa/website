defmodule Site.View do
  @moduledoc """
  View data for the templates: plain values only, no HTML, so that the templates
  stay the one place where markup is written and escaped.
  """

  alias Site.{Entry, Log}

  @type part :: %{
          required(:text) => String.t(),
          optional(:href) => String.t() | nil,
          optional(:datetime) => String.t() | nil
        }

  @doc """
  The primary navigation. `current` is the active section (or `nil`); `exact?` is
  true on the section's own page and false on a page inside it.
  """
  @spec nav(String.t() | nil, boolean()) :: [map()]
  def nav(current, exact?) do
    for section <- Site.Config.nav() do
      aria =
        cond do
          section != current -> nil
          exact? -> "page"
          true -> "true"
        end

      %{label: section, href: "/#{section}/", aria_current: aria}
    end
  end

  @doc "The label and link of the footer's `built from` text."
  @spec build_info(%{sha: String.t(), dirty?: boolean()} | nil) :: %{
          label: String.t(),
          href: String.t() | nil
        }
  def build_info(nil), do: %{label: "unversioned", href: nil}

  def build_info(%{sha: sha, dirty?: dirty?}) do
    %{
      label: Site.Git.short(sha) <> if(dirty?, do: "-dirty", else: ""),
      href: Site.Git.commit_url(sha)
    }
  end

  @doc "Meta line of an essay or note: `essay · 2026-03-28 · a3f9c21`."
  @spec article_meta(Entry.t()) :: [part()]
  def article_meta(%Entry{} = entry) do
    date = Date.to_iso8601(entry.date)

    [
      %{text: Atom.to_string(entry.type)},
      %{text: date, datetime: date},
      %{text: Log.hash(entry), href: entry.commit && Site.Git.commit_url(entry.commit)}
    ]
  end

  @doc "Meta line of a project: `active · Go, YAML · github.com/y0anfa/rhino`."
  @spec project_meta(Entry.t()) :: [part()]
  def project_meta(%Entry{} = entry) do
    Enum.reject(
      [
        entry.status && %{text: entry.status},
        entry.stack != [] && %{text: Enum.join(entry.stack, ", ")},
        entry.link && %{text: display_url(entry.link), href: entry.link}
      ],
      &(&1 in [nil, false])
    )
  end

  @doc """
  A URL without scheme or trailing slash, for display.

      iex> Site.View.display_url("https://github.com/y0anfa/rhino/")
      "github.com/y0anfa/rhino"
  """
  @spec display_url(String.t()) :: String.t()
  def display_url(url) do
    url |> String.replace(~r{\Ahttps?://}, "") |> String.trim_trailing("/")
  end
end
