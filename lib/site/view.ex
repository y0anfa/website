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

  @doc "Meta line of an essay or note: `2026-03-28 · a3f9c21`."
  @spec article_meta(Entry.t()) :: [part()]
  def article_meta(%Entry{} = entry) do
    date = Date.to_iso8601(entry.date)

    [
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
  The two quiet links at the end of an entry page: its Markdown twin and a
  prefilled "ask claude" chat. Both are plain values; the template escapes them.
  """
  @spec entry_links(Entry.t()) :: %{markdown: String.t(), ask: String.t()}
  def entry_links(%Entry{} = entry) do
    %{markdown: Entry.markdown_path(entry), ask: ask_url(entry)}
  end

  @doc """
  The claude.ai link that starts a chat about an entry. The prompt names the page
  and tells Claude to rely only on it. It is URI-encoded here (everything but the
  unreserved characters, so a space is `%20`); the template then HTML-escapes the
  whole attribute.
  """
  @spec ask_url(Entry.t()) :: String.t()
  def ask_url(%Entry{} = entry) do
    "https://claude.ai/new?q=" <> URI.encode(ask_prompt(entry), &URI.char_unreserved?/1)
  end

  @doc "The prompt behind `ask_url/1`."
  @spec ask_prompt(Entry.t()) :: String.t()
  def ask_prompt(%Entry{type: type} = entry) do
    task =
      case type do
        :project ->
          "summarize what the project does and why, then suggest one improvement."

        _ ->
          "summarize the main argument in a few sentences, then tell me where you would push back."
      end

    "Read #{Site.Config.absolute(Entry.path(entry))} by #{Site.Config.name()}, " <>
      "a security engineer. Using only what is on that page, #{task}"
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
