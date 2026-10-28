defmodule Site.HTML do
  @moduledoc """
  The only two ways a value gets into a page.

  EEx does not escape. Every interpolated string in a template goes through
  `escape/1`; the few things that are already HTML (rendered Markdown, the inline
  head script, partials) go through `raw/1` so the intent is visible and lintable.
  """

  @doc """
  Escapes a value for HTML text and attribute contexts (quoted with `"` or `'`).

      iex> Site.HTML.escape(~s(<a href="x">&</a>))
      "&lt;a href=&quot;x&quot;&gt;&amp;&lt;/a&gt;"
  """
  @spec escape(term()) :: String.t()
  def escape(nil), do: ""

  def escape(value) when is_binary(value) do
    String.replace(value, ["&", "<", ">", "\"", "'"], fn
      "&" -> "&amp;"
      "<" -> "&lt;"
      ">" -> "&gt;"
      "\"" -> "&quot;"
      "'" -> "&#39;"
    end)
  end

  def escape(%Date{} = date), do: Date.to_iso8601(date)
  def escape(value) when is_atom(value) or is_number(value), do: escape(to_string(value))

  @doc """
  Marks an already-safe HTML string for insertion as is. Only rendered Markdown,
  the inline head script and partial output may be passed here.
  """
  @spec raw(String.t()) :: String.t()
  def raw(html) when is_binary(html), do: html
end
