defmodule Site.Markdown do
  @moduledoc """
  Markdown rendering through MDEx.

  GFM tables, strikethrough, autolinks, footnotes and alerts (`> [!NOTE]`) are on,
  headings get ids, and raw HTML is never rendered (`unsafe: false`, and escaped
  as text so nothing vanishes silently).

  Code blocks are highlighted by Lumis with classes (`html_linked`), never inline
  styles: `site.css` gives the classes their ink. A language without a parser
  (mix.exs lists them) comes out as plain text.

  Two fenced blocks are not code. With the info string `stats`, each line is
  `value | label` and the block becomes a row of stat callouts,

      ```stats
      91% | only read or react
      82  | respondents
      ```

  rendered as `<dl class="stats"><div><dt>91%</dt><dd>only read or react</dd></div>…</dl>`.
  With the info string `mermaid`, the block is drawn as an inline SVG by
  `Site.Diagram`. A block that does not parse (a line that is not `value | label`,
  a diagram outside the subset) stays a code block, so a typo shows up as code
  instead of vanishing.
  """

  @options [
    extension: [
      table: true,
      strikethrough: true,
      autolink: true,
      footnotes: true,
      alerts: true,
      header_id_prefix: ""
    ],
    render: [unsafe: false, escape: true],
    syntax_highlight: [formatter: {:html_linked, []}]
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
    summary = document.nodes |> first_paragraph() |> truncate(@description_limit)
    {document, blocks} = MDEx.traverse_and_update(document, [], &lift/2)

    %{html: document |> MDEx.to_html!(@options) |> put_back(blocks), summary: summary}
  end

  # A `stats` or `mermaid` block that parses is taken out of the document before
  # it is rendered, and a paragraph holding one private-use marker is left in its
  # place; its HTML goes back in where the marker comes out. The renderer never
  # sees that HTML, so `unsafe: false` stays true for everything an author writes.
  defp lift(%MDEx.CodeBlock{info: info, literal: literal} = block, blocks) do
    built =
      case info |> to_string() |> String.split() |> List.first() do
        "stats" -> stats(literal)
        "mermaid" -> Site.Diagram.render(literal)
        _ -> :error
      end

    case built do
      {:ok, html} ->
        marker = "\u{E000}#{length(blocks)}\u{E000}"
        {%MDEx.Paragraph{nodes: [%MDEx.Text{literal: marker}]}, [{marker, html} | blocks]}

      :error ->
        {block, blocks}
    end
  end

  defp lift(node, blocks), do: {node, blocks}

  defp put_back(html, blocks) do
    Enum.reduce(blocks, html, fn {marker, block}, html ->
      String.replace(html, "<p>#{marker}</p>", block)
    end)
  end

  # One `value | label` per line; both are escaped here, as the page's only way in.
  defp stats(literal) do
    rows = literal |> String.split("\n") |> Enum.map(&String.trim/1) |> Enum.reject(&(&1 == ""))
    pairs = Enum.map(rows, &stat/1)

    if pairs != [] and :error not in pairs do
      items = Enum.map_join(pairs, fn {value, label} -> stat_item(value, label) end)
      {:ok, ~s(<dl class="stats">#{items}</dl>)}
    else
      :error
    end
  end

  defp stat_item(value, label) do
    "<div><dt>#{Site.HTML.escape(value)}</dt><dd>#{Site.HTML.escape(label)}</dd></div>"
  end

  # `value | label`, split at the first bar; both sides must be non-empty.
  defp stat(row) do
    with [value, label] <- String.split(row, "|", parts: 2),
         value = String.trim(value),
         label = String.trim(label),
         true <- value != "" and label != "" do
      {value, label}
    else
      _ -> :error
    end
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
