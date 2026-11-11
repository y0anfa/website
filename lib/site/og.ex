defmodule Site.OG do
  @moduledoc """
  The share images (`og:image`): one 1200x630 PNG per entry at `og/<slug>.png`,
  and `og/home.png` for the home page.

  Each image is drawn as an SVG string in the site's dark palette: graphite, with
  the warm lamp glowing from the top left as it does over every page. An entry
  shows the lit mark and its date, the title in Inter Bold, and the name and the
  domain along the bottom; the home shows the name on two lines and the position.
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

  # The dark palette of SPEC section 8: --bg, --text, --name, --text-2, --text-3,
  # --lamp, and the three glows of the lamp over the page.
  @bg "#0d0f14"
  @text "#ecebe8"
  @name "#d6d5d2"
  @text_2 "#a2a6ae"
  @text_3 "#80848d"
  @lamp "#f2c47c"

  # {centre x, centre y, radius x, radius y, colour, opacity, where it fades out},
  # in the proportions of the page's `body::before`, a little warmer for a card.
  @glows [
    {0.20, -0.06, 0.30, 0.46, "#ffdeb4", 0.16, 0.7},
    {0.24, -0.14, 0.52, 0.64, "#f2aa5c", 0.16, 0.72},
    {0.70, -0.24, 0.72, 0.70, "#6e82be", 0.09, 0.7}
  ]

  @fonts_dir Path.expand("../../priv/og-fonts", __DIR__)
  @sans_file "Inter-Bold.ttf"
  @sans "Inter"

  # Font sizes in pixels, largest first: the first that fits in the allowed number
  # of lines is used. Titles are tightened like the site's headings.
  @title_sizes [96, 84, 72, 62, 54]
  @title_lines 3
  @title_baseline 468
  @name_sizes [168, 152, 128, 104, 84, 68]
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
      defs(),
      ~s(<rect width="#{@width}" height="#{@height}" fill="#{@bg}"/>),
      for(index <- 1..length(@glows), do: glow_rect(index)),
      body(card, fonts),
      "</svg>"
    ]
  end

  defp glow_rect(index),
    do: ~s|<rect width="#{@width}" height="#{@height}" fill="url(#glow-#{index})"/>|

  # The lamp: one radial gradient per glow, an ellipse drawn as a circle squashed
  # around its centre. And the halo of the lit mark.
  defp defs do
    glows =
      @glows
      |> Enum.with_index(1)
      |> Enum.map(fn {{x, y, rx, ry, colour, opacity, fade}, index} ->
        cx = x * @width
        cy = y * @height
        r = rx * @width
        squash = ry * @height / r

        [
          ~s(<radialGradient id="glow-#{index}" gradientUnits="userSpaceOnUse" ),
          ~s(cx="#{num(cx)}" cy="#{num(cy)}" r="#{num(r)}" ),
          ~s|gradientTransform="translate(#{num(cx)} #{num(cy)}) scale(1 #{num(squash)}) |,
          ~s|translate(#{num(-cx)} #{num(-cy)})">|,
          ~s(<stop offset="0" stop-color="#{colour}" stop-opacity="#{num(opacity)}"/>),
          ~s(<stop offset="#{num(fade)}" stop-color="#{colour}" stop-opacity="0"/>),
          "</radialGradient>"
        ]
      end)

    [
      "<defs>",
      glows,
      ~s(<radialGradient id="mark-glow">),
      ~s(<stop offset="0" stop-color="#{@lamp}" stop-opacity="0.45"/>),
      ~s(<stop offset="1" stop-color="#{@lamp}" stop-opacity="0"/>),
      "</radialGradient>",
      "</defs>"
    ]
  end

  # The home: the name on two lines, the position, the domain.
  defp body(%{kind: :home} = card, fonts) do
    {size, lines} = fit_words(fonts.sans, card.title, @name_sizes, @name_tracking_em)
    last_baseline = 400
    first_baseline = last_baseline - size * (length(lines) - 1)

    role =
      case card[:subtitle] do
        nil ->
          []

        subtitle ->
          {role_size, role_lines} = fit(fonts.sans, subtitle, [@role_size, 34, 28], 2, -0.01)

          lines_at(role_lines, last_baseline + 76, role_size * 1.3, role_size, @text_2, -0.01)
      end

    [
      lines_at(lines, first_baseline, size, size, @name, @name_tracking_em),
      role,
      text(domain(), @margin, @height - 64, 26, @text_3)
    ]
  end

  # An entry: the lit mark and the date, the title, the name and the domain.
  defp body(%{kind: :entry} = card, fonts) do
    {size, lines} = fit(fonts.sans, card.title, @title_sizes, @title_lines, @tracking_em)

    leading = size * @line_height
    first_baseline = @title_baseline - leading * (length(lines) - 1)
    kicker_baseline = first_baseline - size * 0.73 - 44

    [
      mark(@margin + 7, kicker_baseline - 10),
      text(clean(fonts.sans, card.kicker), @margin + 34, kicker_baseline, 28, @text_2),
      lines_at(lines, first_baseline, leading, size, @text, @tracking_em),
      text(Site.Config.name(), @margin, @height - 64, 30, @name),
      text(domain(), @width - @margin, @height - 64, 26, @text_3, anchor: "end")
    ]
  end

  # The entry's mark from the timeline, lit: a dot of lamp light with its ring and glow.
  defp mark(x, y) do
    [
      ~s|<circle cx="#{num(x)}" cy="#{num(y)}" r="34" fill="url(#mark-glow)"/>|,
      ~s(<circle cx="#{num(x)}" cy="#{num(y)}" r="13" fill="#{@lamp}" fill-opacity="0.18"/>),
      ~s(<circle cx="#{num(x)}" cy="#{num(y)}" r="7" fill="#{@lamp}"/>)
    ]
  end

  # The text laid out in lines no wider than the canvas minus its margins.
  defp fit(font, string, sizes, max_lines, tracking_em) do
    Text.fit(font, clean(font, string),
      sizes: sizes,
      max_lines: max_lines,
      max_width: @width - 2 * @margin,
      tracking_em: tracking_em
    )
  end

  # One word a line, as the name is set on the home, at the largest size where the
  # widest word fits; a name that cannot be set that way is fitted like a title.
  defp fit_words(font, string, sizes, tracking_em) do
    words = font |> clean(string) |> String.split()
    max_width = @width - 2 * @margin

    fits? = fn size ->
      Enum.all?(words, &(Text.width(font, &1, size, size * tracking_em) <= max_width))
    end

    case {words, Enum.find(sizes, fits?)} do
      {[_ | _], size} when length(words) <= 3 and is_number(size) -> {size, words}
      _ -> fit(font, string, sizes, 3, tracking_em)
    end
  end

  defp lines_at(lines, first_baseline, leading, size, fill, tracking_em) do
    lines
    |> Enum.with_index()
    |> Enum.map(fn {line, index} ->
      text(line, @margin, first_baseline + index * leading, size, fill,
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
