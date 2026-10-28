defmodule Site.Markdown do
  @moduledoc """
  Markdown rendering through MDEx.

  GFM tables, strikethrough, autolinks and footnotes are on, headings get ids,
  raw HTML is never rendered (`unsafe: false`, and escaped as text so nothing
  vanishes silently), and there is no syntax highlighting: code blocks come out as
  plain `<pre><code class="language-x">`.
  """

  @options [
    extension: [
      table: true,
      strikethrough: true,
      autolink: true,
      footnotes: true,
      header_id_prefix: ""
    ],
    render: [unsafe: false, escape: true],
    syntax_highlight: nil
  ]

  @description_limit 160

  @type rendered :: %{html: String.t(), summary: String.t()}

  @doc """
  Renders Markdown to HTML and extracts a plain-text summary of the first
  paragraph (at most #{@description_limit} characters), used as the fallback meta description.
  """
  @spec render(String.t()) :: rendered()
  def render(markdown) when is_binary(markdown) do
    document = MDEx.parse_document!(markdown, @options)

    %{
      html: MDEx.to_html!(document, @options),
      summary: document.nodes |> first_paragraph() |> truncate(@description_limit)
    }
  end

  @doc """
  Shortens text to at most `limit` characters on a word boundary, adding an
  ellipsis when something was cut.

      iex> Site.Markdown.truncate("one two three", 9)
      "one two…"
  """
  @spec truncate(String.t(), pos_integer()) :: String.t()
  def truncate(text, limit) do
    text = text |> String.split() |> Enum.join(" ")

    if String.length(text) <= limit do
      text
    else
      cut = String.slice(text, 0, limit - 1)

      cut =
        case Regex.run(~r/\A(.+)\s\S*\z/su, cut) do
          [_, head] -> head
          nil -> cut
        end

      String.trim_trailing(cut, " ,;:.-") <> "…"
    end
  end

  defp first_paragraph(nodes) do
    case Enum.find(nodes, &match?(%MDEx.Paragraph{}, &1)) do
      %MDEx.Paragraph{nodes: children} -> plain_text(children)
      nil -> ""
    end
  end

  defp plain_text(nodes), do: nodes |> Enum.map(&node_text/1) |> IO.iodata_to_binary()

  defp node_text(%MDEx.Text{literal: literal}), do: literal
  defp node_text(%MDEx.Code{literal: literal}), do: literal
  defp node_text(%MDEx.SoftBreak{}), do: " "
  defp node_text(%MDEx.LineBreak{}), do: " "
  defp node_text(%{nodes: children}) when is_list(children), do: plain_text(children)
  defp node_text(_other), do: ""
end
