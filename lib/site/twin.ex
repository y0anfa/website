defmodule Site.Twin do
  @moduledoc """
  The Markdown twin of every entry, and `llms.txt`.

  Each essay, note and project is also written as `<slug>.md`, served at
  `/<slug>.md`: its title, one line saying what it is and where it lives, and the
  original Markdown body with the frontmatter stripped. Projects add their
  tagline and link. `Site.Llms` writes the `llms.txt` index that points at them.

  Everything is plain text built from the loaded content, with no timestamps, so
  the output is part of the deterministic build.
  """

  alias Site.{Content, Entry, Llms}

  @doc """
  Every extra file the content produces: one twin per entry, plus `llms.txt`,
  as `{relative file path, data}` in path order.
  """
  @spec files(Content.t()) :: [{Path.t(), String.t()}]
  def files(%Content{} = content) do
    twins = for entry <- Content.entries(content), do: {file(entry), render(entry)}

    Enum.sort_by([{"llms.txt", Llms.render(content)} | twins], &elem(&1, 0))
  end

  @doc "Output file of an entry's twin: `rhino.md`."
  @spec file(Entry.t()) :: Path.t()
  def file(%Entry{slug: slug}), do: slug <> ".md"

  @doc """
  The twin of one entry: `# <title>`, a `<type> · <date> · <url>` line, then the
  body. A project also gets its tagline (as a quote) and its link.
  """
  @spec render(Entry.t()) :: String.t()
  def render(%Entry{} = entry) do
    blocks =
      [
        "# " <> one_line(entry.title),
        "#{entry.type} · #{Date.to_iso8601(entry.date)} · #{Site.Config.absolute(Entry.path(entry))}"
      ] ++ project_lines(entry) ++ [String.trim(entry.body || "")]

    blocks
    |> Enum.reject(&(&1 == ""))
    |> Enum.join("\n\n")
    |> Kernel.<>("\n")
  end

  defp project_lines(%Entry{type: :project} = entry) do
    [entry.tagline && "> " <> one_line(entry.tagline), entry.link && "link: " <> entry.link]
    |> Enum.reject(&(&1 in [nil, false]))
  end

  defp project_lines(_entry), do: []

  defp one_line(text), do: text |> String.split() |> Enum.join(" ")
end
