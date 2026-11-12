defmodule Site.OG do
  @moduledoc """
  The share images (`og:image`): one 1200x630 PNG per entry at `og/<slug>.png`,
  and `og/home.png` for the home page.

  Each image is drawn as an SVG string in the site's dark palette, with no colour:
  the timeline's line down the left of the card and one filled mark on it. An
  entry shows its date beside the mark, the title in Inter Bold, and the name and
  the domain along the bottom; the home shows the name beside the mark, the
  position under it and the domain.
  The SVG is rasterised at build time by `resvg` (a precompiled Rust NIF) with only
  the font in `priv/og-fonts/`; system fonts are never read, so the output does not
  depend on the machine. The font lives outside `assets/` because the build uses it
  but the site does not publish it.

  The output is deterministic: no timestamps, no random state, no PNG metadata.
  """

  alias Site.{Content, Entry}
  alias Site.OG.Text

  @width 1200
  @height 630
  @margin 72

  # The timeline: the line stands here, and the words start to its right.
  @axis 120
  @left 164

  # The dark palette of SPEC section 8: --bg, --text, --text-2, --text-3. The line is
  # a step lighter than --hair, so it survives a thumbnail.
  @bg "#0e0f12"
  @text "#ecebe8"
  @text_2 "#9c9fa6"
  @text_3 "#80848d"
  @line "#34373e"

  @fonts_dir Path.expand("../../priv/og-fonts", __DIR__)
  @sans_file "Inter-Bold.ttf"
  @sans "Inter"

  # Font sizes in pixels, largest first: the first that fits in the allowed number
  # of lines is used. Titles are tightened like the site's headings.
  @title_sizes [96, 84, 72, 62, 54]
  @title_lines 3
  @title_baseline 468
  @name_sizes [132, 120, 104, 84, 68]
  @role_size 40
  @tracking_em -0.03
  @name_tracking_em -0.035
  @line_height 1.1

  @home_key "home"

  @type file :: {Path.t(), binary()}

  @doc "Output path of the image for a slug (or `\"home\"`): `og/<slug>.png`."
  @spec path(String.t()) :: Path.t()
  def path(key), do: "og/#{key}.png"

  @doc "Absolute URL of the image, for `og:image`."
  @spec url(String.t()) :: String.t()
  def url(key), do: Site.Config.absolute("/" <> path(key))

  @doc "Key of the home page's image."
  @spec home_key() :: String.t()
  def home_key, do: @home_key

  @doc "Width and height of every image, in pixels."
  @spec size() :: {pos_integer(), pos_integer()}
  def size, do: {@width, @height}

  @doc """
  Renders every image: the home and one per entry, as `{path, png}` sorted by path.
  Raises `Site.Error` if a PNG cannot be produced.
  """
  @spec files(Content.t()) :: [file()]
  def files(%Content{} = content) do
    fonts = fonts!()

    [home_card(content) | Enum.map(Content.entries(content), &entry_card/1)]
    |> Task.async_stream(&render(&1, fonts), ordered: true, timeout: :infinity)
    |> Enum.map(fn {:ok, result} -> ok_or_raise(result, "cannot render a share image") end)
    |> Enum.sort_by(&elem(&1, 0))
  end

  # -- cards -----------------------------------------------------------------------

  defp home_card(%Content{home: home}) do
    role = Site.Config.role()

    %{
      key: @home_key,
      kind: :home,
      title: home.title,
      subtitle: "#{role.title} at #{role.company}"
    }
  end

  defp entry_card(%Entry{} = entry) do
    %{
      key: entry.slug,
      kind: :entry,
      title: entry.title,
      kicker: Site.View.long_date(entry.date)
    }
  end

  # -- fonts -----------------------------------------------------------------------

  @doc false
  # The font of every image: the shared font database and the measures of the face.
  @spec fonts!() :: map()
  def fonts!() do
    file = Path.join(@fonts_dir, @sans_file)

    db =
      [
        font_files: [file],
        skip_system_fonts: true,
        font_family: @sans,
        sans_serif_family: @sans
      ]
      |> Resvg.init_fontdb()
      |> ok_or_raise("cannot load the font in #{@fonts_dir}")

    %{db: db, sans: Text.load!(file)}
  end

  defp ok_or_raise({:ok, value}, _message), do: value

  defp ok_or_raise({:error, reason}, message),
    do: raise(Site.Error, message: "#{message}: #{reason}")

  # -- rendering -------------------------------------------------------------------

  # Runs in a task, so a failure is returned and raised by the caller.
  defp render(card, fonts) do
    svg = card |> svg(fonts) |> IO.iodata_to_binary()
    opts = [fontdb: fonts.db, resources_dir: @fonts_dir, font_family: @sans]

    case Resvg.svg_string_to_png_binary(svg, opts) do
      {:ok, png} -> {:ok, {path(card.key), png}}
      {:error, reason} -> {:error, "#{path(card.key)}: #{reason}"}
    end
  end

  @doc false
  # The SVG of a card, as iodata. Public so tests can look at it.
  @spec svg(map(), map()) :: iodata()
  def svg(card, fonts) do
    [
      ~s(<svg xmlns="http://www.w3.org/2000/svg" width="#{@width}" height="#{@height}" ),
      ~s(viewBox="0 0 #{@width} #{@height}">),
      ~s(<rect width="#{@width}" height="#{@height}" fill="#{@bg}"/>),
      ~s(<rect x="#{@axis - 1}" y="0" width="2" height="#{@height}" fill="#{@line}"/>),
      body(card, fonts),
      "</svg>"
    ]
  end

  # The home: the name beside its mark, the position, the domain.
  defp body(%{kind: :home} = card, fonts) do
    {size, lines} = fit(fonts.sans, card.title, @name_sizes, 2, @name_tracking_em)
    last_baseline = 340
    first_baseline = last_baseline - size * (length(lines) - 1)

    role =
      case card[:subtitle] do
        nil ->
          []

        subtitle ->
          {role_size, role_lines} = fit(fonts.sans, subtitle, [@role_size, 34, 28], 2, -0.01)

          lines_at(role_lines, last_baseline + 68, role_size * 1.3, role_size, @text_2, -0.01)
      end

    [
      mark(first_baseline - size * 0.36),
      lines_at(lines, first_baseline, size, size, @text, @name_tracking_em),
      role,
      text(domain(), @left, @height - 64, 26, @text_3)
    ]
  end

  # An entry: its mark and the date, the title, the name and the domain.
  defp body(%{kind: :entry} = card, fonts) do
    {size, lines} = fit(fonts.sans, card.title, @title_sizes, @title_lines, @tracking_em)

    leading = size * @line_height
    first_baseline = @title_baseline - leading * (length(lines) - 1)
    kicker_baseline = first_baseline - size * 0.73 - 44

    [
      mark(kicker_baseline - 10),
      text(clean(fonts.sans, card.kicker), @left, kicker_baseline, 28, @text_2),
      lines_at(lines, first_baseline, leading, size, @text, @tracking_em),
      text(Site.Config.name(), @left, @height - 64, 30, @text),
      text(domain(), @width - @margin, @height - 64, 26, @text_3, anchor: "end")
    ]
  end

  # The mark on the line, filled: a dot of the text colour, with a ring of the page
  # colour that cuts the line around it.
  defp mark(y) do
    [
      ~s(<circle cx="#{@axis}" cy="#{num(y)}" r="20" fill="#{@bg}"/>),
      ~s(<circle cx="#{@axis}" cy="#{num(y)}" r="9" fill="#{@text}"/>)
    ]
  end

  # The text laid out in lines that fit between the line and the right margin.
  defp fit(font, string, sizes, max_lines, tracking_em) do
    Text.fit(font, clean(font, string),
      sizes: sizes,
      max_lines: max_lines,
      max_width: @width - @left - @margin,
      tracking_em: tracking_em
    )
  end

  defp lines_at(lines, first_baseline, leading, size, fill, tracking_em) do
    lines
    |> Enum.with_index()
    |> Enum.map(fn {line, index} ->
      text(line, @left, first_baseline + index * leading, size, fill,
        tracking: size * tracking_em
      )
    end)
  end

  defp clean(font, string), do: Text.clean(font, string)

  defp domain, do: Site.View.display_url(Site.Config.absolute(""))

  defp text(string, x, y, size, fill, opts \\ []) do
    tracking = if t = opts[:tracking], do: ~s( letter-spacing="#{num(t)}"), else: ""
    anchor = if a = opts[:anchor], do: ~s( text-anchor="#{a}"), else: ""

    [
      ~s(<text x="#{num(x)}" y="#{num(y)}" font-family="#{@sans}" font-weight="700" ),
      ~s(font-size="#{num(size)}" fill="#{fill}"#{tracking}#{anchor}>),
      Site.HTML.escape(string),
      "</text>"
    ]
  end

  defp num(value), do: :erlang.float_to_binary(value * 1.0, decimals: 2)
end
