defmodule Site.View do
  @moduledoc """
  View data for the templates: plain values only, no HTML, so that the templates
  stay the one place where markup is written and escaped.
  """

  alias Site.Entry

  @type part :: %{
          required(:text) => String.t(),
          optional(:href) => String.t() | nil,
          optional(:datetime) => String.t() | nil
        }

  @doc """
  The date on the home timeline: day and short month, no year.

      iex> Site.View.short_date(~D[2026-09-02])
      "2 Sep"
  """
  @spec short_date(Date.t()) :: String.t()
  def short_date(%Date{} = date), do: Calendar.strftime(date, "%-d %b")

  @doc """
  The full date of an entry's meta line.

      iex> Site.View.long_date(~D[2026-10-29])
      "29 Oct 2026"
  """
  @spec long_date(Date.t()) :: String.t()
  def long_date(%Date{} = date), do: Calendar.strftime(date, "%-d %b %Y")

  @doc "Meta line of an entry: its full date, and nothing else."
  @spec article_meta(Entry.t()) :: [part()]
  def article_meta(%Entry{} = entry) do
    [%{text: long_date(entry.date), datetime: Date.to_iso8601(entry.date)}]
  end

  @doc "The facts under a project's tagline: `active · Go, YAML · github.com/y0anfa/rhino`."
  @spec project_facts(Entry.t()) :: [part()]
  def project_facts(%Entry{} = entry) do
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
  prefilled "Ask Claude" chat. Both are plain values; the template escapes them.
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
