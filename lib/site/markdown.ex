defmodule Site.Markdown do
  @moduledoc """
  Markdown rendering through MDEx.

  GFM tables, strikethrough, autolinks and footnotes are on, headings get ids,
  raw HTML is never rendered (`unsafe: false`, and escaped as text so nothing
  vanishes silently), and there is no syntax highlighting: code blocks come out as
  plain `<pre><code class="language-x">`.

  One fenced block gets special treatment: with the info string `stats`, each line
  is `value | label` and the block becomes a row of stat callouts,

      ```stats
      91% | only read or react
      82  | respondents
      ```

  rendered as `<dl class="stats"><div><dt>91%</dt><dd>only read or react</dd></div>…</dl>`.
  A block with a line that is not `value | label` stays a plain code block, so a
  typo shows up as code instead of vanishing.
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
      html: document |> MDEx.to_html!(@options) |> stats(),
      summary: document.nodes |> first_paragraph() |> truncate(@description_limit)
    }
  end

  # Turns each `stats` code block of MDEx's HTML into a definition list. The text
  # inside is already HTML-escaped by MDEx and is only trimmed and split here,
  # never unescaped, so it goes back in as it came out.
  defp stats(html) do
    block = ~r{<pre><code class="language-stats">(.*?)</code></pre>}s
    Regex.replace(block, html, &stats_block/2)
  end

  defp stats_block(whole, body) do
    rows = body |> String.split("\n") |> Enum.map(&String.trim/1) |> Enum.reject(&(&1 == ""))
    pairs = Enum.map(rows, &stat/1)

    if pairs != [] and :error not in pairs do
      items = Enum.map_join(pairs, fn {value, label} -> stat_item(value, label) end)
      ~s(<dl class="stats">#{items}</dl>)
    else
      whole
    end
  end

  defp stat_item(value, label), do: "<div><dt>#{value}</dt><dd>#{label}</dd></div>"

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
