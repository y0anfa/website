defmodule Site.OG.Text do
  @moduledoc """
  Measures and wraps text for the share images.

  SVG has no text wrapping, so the build has to know how wide a word is before
  it draws it. This module reads the glyph advances straight from a TrueType
  file (the `head`, `hhea`, `hmtx` and `cmap` tables) and lays a title out in at
  most a few lines, stepping the font size down until it fits. Kerning is
  ignored: it only ever narrows a line, so the measure errs on the safe side.

  Everything is plain arithmetic on the font file, so the layout is the same on
  every machine.
  """

  defstruct [:units, :advances, :groups]

  @type t :: %__MODULE__{
          units: pos_integer(),
          advances: tuple(),
          groups: [{non_neg_integer(), non_neg_integer(), non_neg_integer()}]
        }

  @doc "Reads the metrics of a TrueType font file. Raises if the file cannot be used."
  @spec load!(Path.t()) :: t()
  def load!(path) do
    binary = File.read!(path)
    tables = tables!(binary, path)

    <<_::binary-size(18), units::16, _::binary>> = table!(binary, tables, "head", path)
    <<_::binary-size(34), metric_count::16, _::binary>> = table!(binary, tables, "hhea", path)
    hmtx = table!(binary, tables, "hmtx", path)

    advances =
      for <<advance::16, _bearing::16 <- binary_part(hmtx, 0, metric_count * 4)>>, do: advance

    %__MODULE__{
      units: units,
      advances: List.to_tuple(advances),
      groups: groups!(table!(binary, tables, "cmap", path), path)
    }
  end

  @doc "Advance width of a codepoint in font units, or `nil` when the font has no glyph for it."
  @spec advance(t(), non_neg_integer()) :: non_neg_integer() | nil
  def advance(%__MODULE__{} = font, codepoint) do
    case glyph(font.groups, codepoint) do
      0 -> nil
      glyph -> elem(font.advances, min(glyph, tuple_size(font.advances) - 1))
    end
  end

  @doc """
  Prepares a string for drawing: control characters and runs of whitespace
  become single spaces, and characters the font cannot draw are dropped, so a
  missing glyph never shows up as an empty box.
  """
  @spec clean(t(), String.t()) :: String.t()
  def clean(%__MODULE__{} = font, string) do
    string
    |> String.replace(~r/[[:space:][:cntrl:]]+/u, " ")
    |> String.to_charlist()
    |> Enum.filter(&(&1 == ?\s or advance(font, &1) != nil))
    |> List.to_string()
    |> String.trim()
  end

  @doc "Width of a string in pixels at `size`, with `tracking` pixels added after every character."
  @spec width(t(), String.t(), number(), number()) :: float()
  def width(%__MODULE__{} = font, string, size, tracking \\ 0) do
    string
    |> String.to_charlist()
    |> Enum.reduce(0.0, fn codepoint, sum ->
      sum + (advance(font, codepoint) || 0) * size / font.units + tracking
    end)
  end

  @doc """
  Lays `text` out in at most `max_lines` lines no wider than `max_width`.

  Tries each of `sizes` (largest first, in pixels) and takes the first one whose
  wrapped text fits. When even the smallest size needs more lines, the text is cut
  with an ellipsis on the last line. Lines are balanced: they are made as narrow
  as the line count allows, so a title does not end on a single orphaned word.

  Returns `{size, lines}`. `tracking_em` is letter spacing in em.
  """
  @spec fit(t(), String.t(), keyword()) :: {number(), [String.t()]}
  def fit(%__MODULE__{} = font, text, opts) do
    sizes = Keyword.fetch!(opts, :sizes)
    max_lines = Keyword.fetch!(opts, :max_lines)
    max_width = Keyword.fetch!(opts, :max_width)
    tracking_em = Keyword.get(opts, :tracking_em, 0)

    layouts =
      for size <- sizes do
        {size, wrap(font, text, size, size * tracking_em, max_width)}
      end

    case Enum.find(layouts, fn {_size, lines} -> length(lines) <= max_lines end) do
      nil ->
        size = List.last(sizes)
        lines = wrap(font, text, size, size * tracking_em, max_width)
        {size, truncate(font, lines, max_lines, size, size * tracking_em, max_width)}

      {size, lines} ->
        {size, balance(font, text, size, size * tracking_em, max_width, lines)}
    end
  end

  # -- wrapping --------------------------------------------------------------

  # Greedy wrap: as many words as fit on a line. A word wider than a line is
  # split between characters.
  defp wrap(font, text, size, tracking, max_width) do
    space = width(font, " ", size, tracking)

    text
    |> String.split(" ", trim: true)
    |> Enum.flat_map(&split_long(font, &1, size, tracking, max_width))
    |> Enum.reduce({[], nil, 0.0}, fn word, {lines, line, line_width} ->
      word_width = width(font, word, size, tracking)

      cond do
        line == nil ->
          {lines, word, word_width}

        line_width + space + word_width <= max_width ->
          {lines, line <> " " <> word, line_width + space + word_width}

        true ->
          {[line | lines], word, word_width}
      end
    end)
    |> then(fn
      {lines, nil, _} -> Enum.reverse(lines)
      {lines, line, _} -> Enum.reverse([line | lines])
    end)
  end

  defp split_long(font, word, size, tracking, max_width) do
    if width(font, word, size, tracking) <= max_width do
      [word]
    else
      chars = String.graphemes(word)

      count =
        Enum.find_value(length(chars)..1//-1, 1, fn n ->
          width(font, Enum.join(Enum.take(chars, n)), size, tracking) <= max_width && n
        end)

      {head, tail} = Enum.split(chars, count)
      [Enum.join(head) | split_long(font, Enum.join(tail), size, tracking, max_width)]
    end
  end

  # Narrows the wrap width while the text still fits in the same number of lines,
  # so the lines come out about equally long.
  defp balance(_font, _text, _size, _tracking, _max_width, lines) when length(lines) < 2,
    do: lines

  defp balance(font, text, size, tracking, max_width, lines) do
    count = length(lines)
    step = max(size / 2, 8)

    widest =
      text
      |> String.split(" ", trim: true)
      |> Enum.map(&width(font, &1, size, tracking))
      |> Enum.max()

    Stream.iterate(max_width - step, &(&1 - step))
    |> Enum.take_while(&(&1 >= widest))
    |> Enum.reduce_while(lines, fn width, best ->
      candidate = wrap(font, text, size, tracking, width)
      if length(candidate) == count, do: {:cont, candidate}, else: {:halt, best}
    end)
  end

  # Keeps `max_lines` lines and ends the last one with an ellipsis.
  defp truncate(font, lines, max_lines, size, tracking, max_width) do
    {kept, [last | _rest]} = Enum.split(lines, max_lines - 1)
    words = String.split(last, " ")

    ellipsised =
      Enum.find_value(length(words)..1//-1, "…", fn n ->
        candidate = Enum.join(Enum.take(words, n), " ") <> "…"
        width(font, candidate, size, tracking) <= max_width && candidate
      end)

    kept ++ [ellipsised]
  end

  # -- TrueType --------------------------------------------------------------

  defp tables!(binary, path) do
    case binary do
      <<version::binary-4, count::16, _::binary-6, directory::binary-size(count * 16), _::binary>>
      when version in [<<0, 1, 0, 0>>, "true", "OTTO"] ->
        for <<tag::binary-4, _checksum::32, offset::32, length::32 <- directory>>,
          do: {tag, offset, length}

      _ ->
        raise Site.Error, message: "#{path} is not a TrueType or OpenType font"
    end
  end

  defp table!(binary, tables, tag, path) do
    case List.keyfind(tables, tag, 0) do
      {^tag, offset, length} -> binary_part(binary, offset, length)
      nil -> raise Site.Error, message: "#{path} has no #{String.trim(tag)} table"
    end
  end

  # The `cmap` subtable for Unicode (platform 3, encoding 10, format 12): a
  # sorted list of {first codepoint, last codepoint, glyph of the first}.
  defp groups!(cmap, path) do
    <<_version::16, count::16, records::binary-size(count * 8), _::binary>> = cmap

    offset =
      Enum.find_value(
        for(<<platform::16, encoding::16, offset::32 <- records>>,
          do: {platform, encoding, offset}
        ),
        fn
          {3, 10, offset} -> offset
          _ -> nil
        end
      )

    with offset when is_integer(offset) <- offset,
         <<_::binary-size(^offset), 12::16, _reserved::16, _length::32, _language::32,
           group_count::32, groups::binary-size(group_count * 12), _::binary>> <- cmap do
      for <<first::32, last::32, glyph::32 <- groups>>, do: {first, last, glyph}
    else
      _ -> raise Site.Error, message: "#{path} has no Unicode (format 12) character map"
    end
  end

  defp glyph(groups, codepoint) do
    Enum.find_value(groups, 0, fn
      {first, last, glyph} when codepoint >= first and codepoint <= last ->
        glyph + codepoint - first

      _ ->
        nil
    end)
  end
end
