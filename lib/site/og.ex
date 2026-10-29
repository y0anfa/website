defmodule Site.OG do
  @moduledoc """
  The share images (`og:image`): one 1200x630 PNG per entry at `og/<slug>.png`,
  and `og/home.png` for the home page.

  Each image is drawn as an SVG string in the light palette: faint topographic
  contour lines seeded from the slug, a small mono line with the type and date,
  the title in Inter Bold, and the name and domain along the bottom. The SVG is
  rasterised at build time by `resvg` (a precompiled Rust NIF) with only the two
  fonts in `priv/og-fonts/`; system fonts are never read, so the output does not
  depend on the machine. The fonts live outside `assets/` because the build
  uses them but the site does not publish them.

  The output is deterministic: no timestamps, no random state, no PNG metadata.
  """

  alias Site.{Content, Entry}
  alias Site.OG.{Contours, Text}

  @width 1200
  @height 630
  @margin 72

  # The light palette of SPEC section 8.
  @bg "#f4efe4"
  @fg "#262523"
  @muted "#6b675f"
  @rule "#ddd6c8"

  @fonts_dir Path.expand("../../priv/og-fonts", __DIR__)
  @sans_file "Inter-Bold.ttf"
  @mono_file "JetBrainsMono-Regular.ttf"
  @sans "Inter"
  @mono "JetBrains Mono"

  # Font sizes in pixels, largest first: the first that fits in the allowed number
  # of lines is used. Titles are tightened by 2% of the em, like the site's headings.
  @title_sizes [96, 84, 72, 62, 54]
  @title_lines 3
  @title_baseline 468
  @name_sizes [152, 128, 104, 84, 68]
  @tagline_sizes [52, 44, 38]
  @tracking_em -0.02
  @name_tracking_em -0.03
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
    %{key: @home_key, kind: :home, title: home.title, subtitle: home.tagline}
  end

  defp entry_card(%Entry{} = entry) do
    %{
      key: entry.slug,
      kind: :entry,
      title: entry.title,
      kicker: "#{entry.type} · #{Date.to_iso8601(entry.date)}"
    }
  end

  # -- fonts -----------------------------------------------------------------------

  @doc false
  # The fonts of every image: the shared font database and the measures of both faces.
  @spec fonts!() :: map()
  def fonts!() do
    files = Enum.map([@sans_file, @mono_file], &Path.join(@fonts_dir, &1))

    db =
      [
        font_files: files,
        skip_system_fonts: true,
        font_family: @sans,
        sans_serif_family: @sans,
        monospace_family: @mono
      ]
      |> Resvg.init_fontdb()
      |> ok_or_raise("cannot load the fonts in #{@fonts_dir}")

    %{db: db, sans: Text.load!(hd(files)), mono: Text.load!(List.last(files))}
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
    %{minor: minor, major: major} = Contours.paths(card.key, @width, @height)

    [
      ~s(<svg xmlns="http://www.w3.org/2000/svg" width="#{@width}" height="#{@height}" ),
      ~s(viewBox="0 0 #{@width} #{@height}">),
      ~s(<rect width="#{@width}" height="#{@height}" fill="#{@bg}"/>),
      ~s(<g fill="none" stroke="#{@rule}" stroke-linecap="round" stroke-linejoin="round">),
      path_element(minor, 1.5),
      path_element(major, 2.5),
      "</g>",
      body(card, fonts),
      "</svg>"
    ]
  end

  defp path_element("", _width), do: []
  defp path_element(d, width), do: [~s(<path stroke-width="#{width}" d="#{d}"/>)]

  # The home: the name, the tagline, the domain.
  defp body(%{kind: :home} = card, fonts) do
    {name_size, name_lines} = fit(fonts.sans, card.title, @name_sizes, 2, @name_tracking_em)
    name_leading = name_size * @line_height
    name_baseline = 350

    name =
      lines_at(
        name_lines,
        name_baseline - name_leading * (length(name_lines) - 1),
        name_leading,
        name_size,
        @fg,
        @name_tracking_em
      )

    tagline =
      case card[:subtitle] do
        nil ->
          []

        tagline ->
          {size, lines} = fit(fonts.sans, tagline, @tagline_sizes, 2, @tracking_em)
          lines_at(lines, name_baseline + 86, size * @line_height, size, @muted, @tracking_em)
      end

    [name, tagline, text(domain(), @margin, @height - 64, @mono, 28, @muted)]
  end

  # An entry: the kicker, the title, the name and the domain.
  defp body(%{kind: :entry} = card, fonts) do
    {size, lines} = fit(fonts.sans, card.title, @title_sizes, @title_lines, @tracking_em)

    leading = size * @line_height
    first_baseline = @title_baseline - leading * (length(lines) - 1)
    kicker_baseline = first_baseline - size * 0.73 - 38

    [
      text(clean(fonts.mono, card.kicker), @margin, kicker_baseline, @mono, 28, @muted),
      lines_at(lines, first_baseline, leading, size, @fg, @tracking_em),
      text(Site.Config.name(), @margin, @height - 64, @sans, 30, @fg),
      text(domain(), @width - @margin, @height - 64, @mono, 28, @muted, anchor: "end")
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

  defp lines_at(lines, first_baseline, leading, size, fill, tracking_em) do
    lines
    |> Enum.with_index()
    |> Enum.map(fn {line, index} ->
      text(line, @margin, first_baseline + index * leading, @sans, size, fill,
        tracking: size * tracking_em
      )
    end)
  end

  defp clean(font, string), do: Text.clean(font, string)

  defp domain, do: Site.View.display_url(Site.Config.absolute(""))

  defp text(string, x, y, family, size, fill, opts \\ []) do
    weight = if family == @sans, do: ~s( font-weight="700"), else: ""
    tracking = if t = opts[:tracking], do: ~s( letter-spacing="#{num(t)}"), else: ""
    anchor = if a = opts[:anchor], do: ~s( text-anchor="#{a}"), else: ""

    [
      ~s(<text x="#{num(x)}" y="#{num(y)}" font-family="#{family}"#{weight} ),
      ~s(font-size="#{num(size)}" fill="#{fill}"#{tracking}#{anchor}>),
      Site.HTML.escape(string),
      "</text>"
    ]
  end

  defp num(value), do: :erlang.float_to_binary(value * 1.0, decimals: 2)
end
