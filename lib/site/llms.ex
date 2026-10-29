defmodule Site.Llms do
  @moduledoc """
  `llms.txt`, in the llmstxt.org format: the name as an h1, a one-line summary
  as a quote, a short paragraph, then one section per entry type, each entry a
  link to its Markdown twin with its description.

      # Yoan Faure

      > Security engineer who builds. Paris.

      I work on the balance between security and productivity. …

      ## Essays

      - [Title](https://yoanfaure.com/slug.md): description

  Sections without entries are left out. Entries are in log order.
  """

  alias Site.{Content, Doc, Entry, Log}

  @sections [{"Essays", :essay}, {"Projects", :project}, {"Notes", :note}]

  @doc "Renders `llms.txt` for the loaded content."
  @spec render(Content.t()) :: String.t()
  def render(%Content{home: %Doc{} = home} = content) do
    entries = Content.entries(content)

    head = [
      "# " <> Site.Config.name(),
      "> " <> one_line(home.description),
      intro(home)
    ]

    sections =
      for {heading, type} <- @sections,
          group = entries |> Enum.filter(&(&1.type == type)) |> Log.sort(),
          group != [] do
        "## #{heading}\n\n" <> Enum.map_join(group, "\n", &item/1)
      end

    (head ++ sections)
    |> Enum.reject(&(&1 == ""))
    |> Enum.join("\n\n")
    |> Kernel.<>("\n")
  end

  defp item(%Entry{} = entry) do
    link =
      "[#{escape_text(one_line(entry.title))}](#{Site.Config.absolute(Entry.markdown_path(entry))})"

    case one_line(entry.description || "") do
      "" -> "- " <> link
      description -> "- #{link}: #{description}"
    end
  end

  # The home intro as one plain-text paragraph: the text of each top-level
  # paragraph of home.md, with links, emphasis and code reduced to their words.
  defp intro(%Doc{body: body}) when is_binary(body) do
    body
    |> MDEx.parse_document!()
    |> Map.fetch!(:nodes)
    |> Enum.filter(&match?(%MDEx.Paragraph{}, &1))
    |> Enum.map(&plain_text(&1.nodes))
    |> Enum.map(&one_line/1)
    |> Enum.reject(&(&1 == ""))
    |> Enum.join(" ")
  end

  defp intro(_doc), do: ""

  defp plain_text(nodes), do: nodes |> Enum.map(&node_text/1) |> IO.iodata_to_binary()

  defp node_text(%MDEx.Text{literal: literal}), do: literal
  defp node_text(%MDEx.Code{literal: literal}), do: literal
  defp node_text(%MDEx.SoftBreak{}), do: " "
  defp node_text(%MDEx.LineBreak{}), do: " "
  defp node_text(%{nodes: children}) when is_list(children), do: plain_text(children)
  defp node_text(_other), do: ""

  defp one_line(text), do: text |> String.split() |> Enum.join(" ")

  # Link text: keep a title with brackets from closing the link early.
  defp escape_text(text), do: String.replace(text, ["\\", "[", "]"], &("\\" <> &1))
end
