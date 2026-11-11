defmodule Site.OGTest do
  use ExUnit.Case, async: true

  import Site.TestHelpers

  alias Site.{Content, OG}

  # Every share image is a 1200x630 PNG, and nothing but the three chunks a
  # picture needs: no timestamp, no text chunk, no colour profile.
  @png_signature <<137, 80, 78, 71, 13, 10, 26, 10>>

  setup_all do
    content = Content.load(fixture_copy())
    %{content: content, files: Map.new(OG.files(content)), tree: read_tree(build_fixtures())}
  end

  defp chunks(<<@png_signature, rest::binary>>), do: chunks(rest, [])

  defp chunks(<<>>, acc), do: Enum.reverse(acc)

  defp chunks(
         <<length::32, type::binary-4, data::binary-size(length), _crc::32, rest::binary>>,
         acc
       ),
       do: chunks(rest, [{type, data} | acc])

  describe "files/1" do
    test "has the home image and one per entry, at og/<slug>.png", %{files: files} do
      assert files |> Map.keys() |> Enum.sort() == [
               "og/escape-me.png",
               "og/first-essay.png",
               "og/home.png",
               "og/second-essay.png",
               "og/small-note.png",
               "og/widget.png"
             ]
    end

    test "skips drafts, like the pages" do
      files = fixture_content() |> OG.files() |> Map.new()
      refute Map.has_key?(files, "og/an-unfinished-draft.png")

      with_drafts = [drafts: true] |> fixture_content() |> OG.files() |> Map.new()
      assert Map.has_key?(with_drafts, "og/an-unfinished-draft.png")
    end

    test "every image is a 1200x630 PNG with no metadata chunks", %{files: files} do
      for {path, png} <- files do
        assert [{"IHDR", header} | rest] = chunks(png), path
        assert <<1200::32, 630::32, 8, 6, 0, 0, 0>> = header, path
        assert Enum.uniq(Enum.map(rest, &elem(&1, 0))) == ["IDAT", "IEND"], path
        assert {1200, 630} == OG.size()
      end
    end

    test "images are small enough for every crawler", %{files: files} do
      for {path, png} <- files do
        assert byte_size(png) < 300_000, "#{path} is #{byte_size(png)} bytes"
      end
    end

    test "the same content gives byte-identical images", %{content: content, files: files} do
      assert Map.new(OG.files(content)) == files
    end

    test "each entry gets its own image", %{files: files} do
      images = Map.values(files)
      assert length(Enum.uniq(images)) == length(images)
    end

    test "a different title gives a different image", %{content: content, files: files} do
      entries =
        Enum.map(content.essays, fn entry ->
          if entry.slug == "first-essay", do: %{entry | title: "Another title"}, else: entry
        end)

      changed = Map.new(OG.files(%{content | essays: entries}))
      refute changed["og/first-essay.png"] == files["og/first-essay.png"]
      assert changed["og/widget.png"] == files["og/widget.png"]
      assert changed["og/home.png"] == files["og/home.png"]
    end

    test "a title with markup, quotes and an ampersand renders (it is escaped in the SVG)",
         %{files: files} do
      assert Map.has_key?(files, "og/escape-me.png")
    end

    test "a title with no drawable character still renders" do
      content = %{
        fixture_content()
        | essays: [entry(slug: "blank", title: "🙂🙃")],
          notes: [],
          projects: []
      }

      assert [{"og/blank.png", png}, {"og/home.png", _}] = OG.files(content)
      assert [{"IHDR", _} | _] = chunks(png)
    end

    test "a very long title still renders" do
      content = %{
        fixture_content()
        | essays: [entry(slug: "long", title: String.duplicate("supercalifragilistic ", 40))],
          notes: [],
          projects: []
      }

      assert [_home, {"og/long.png", _png}] = OG.files(content)
    end
  end

  describe "paths and URLs" do
    test "path/1 and url/1" do
      assert OG.path("rhino") == "og/rhino.png"
      assert OG.url("rhino") == "https://yoanfaure.com/og/rhino.png"
      assert OG.url(OG.home_key()) == "https://yoanfaure.com/og/home.png"
    end

    test "home and og are reserved slugs, so no entry can collide with them" do
      for slug <- ~w(home og) do
        assert slug in Site.Config.reserved_slugs()

        assert_raise Site.Error, ~r/slug "#{slug}" is reserved/, fn ->
          minimal_content(%{"notes/#{slug}.md" => "---\ntitle: N\ndate: 2026-10-28\n---\nb"})
          |> Content.load()
        end
      end
    end
  end

  describe "the SVG" do
    setup %{content: content} do
      fonts = OG.fonts!()
      %{fonts: fonts, content: content}
    end

    defp svg(card, fonts), do: card |> OG.svg(fonts) |> IO.iodata_to_binary()

    defp entry_card(attrs \\ []) do
      Map.merge(
        %{key: "a-slug", kind: :entry, title: "A title", kicker: "28 Mar 2026"},
        Map.new(attrs)
      )
    end

    test "uses the dark palette, the lamp and Inter only", %{fonts: fonts} do
      svg = svg(entry_card(), fonts)

      for colour <- ~w(#0d0f14 #ecebe8 #d6d5d2 #a2a6ae #80848d #f2c47c), do: assert(svg =~ colour)
      assert svg =~ ~s(width="1200" height="630")
      assert svg =~ ~s(font-family="Inter" font-weight="700")
      refute svg =~ "JetBrains"

      # the old beige palette and its contours are gone
      for old <- ~w(#f4efe4 #262523 #6b675f #ddd6c8), do: refute(svg =~ old)
      refute svg =~ ~r/<path stroke-width/
    end

    test "the lamp glows from the top left, as over every page", %{fonts: fonts} do
      svg = svg(entry_card(), fonts)

      assert length(Regex.scan(~r/<radialGradient id="glow-\d"/, svg)) == 3
      assert length(Regex.scan(~r|fill="url\(#glow-\d\)"|, svg)) == 3

      # every card has the same light: it does not depend on the title
      glow = fn svg -> Regex.scan(~r|<radialGradient id="glow.*?</radialGradient>|, svg) end
      assert glow.(svg) == glow.(svg(entry_card(key: "other", title: "Other"), fonts))
    end

    test "has the lit mark and the date, the title, the name and the domain", %{fonts: fonts} do
      svg = svg(entry_card(), fonts)

      assert svg =~ ~s|fill="url(#mark-glow)"|
      assert svg =~ ~r|<circle [^>]*r="7" fill="#f2c47c"/>|
      assert svg =~ ">28 Mar 2026</text>"
      assert svg =~ ">A title</text>"
      assert svg =~ ">Yoan Faure</text>"
      assert svg =~ ~s(text-anchor="end">yoanfaure.com</text>)
    end

    test "escapes the title, so it cannot add markup", %{fonts: fonts} do
      svg = svg(entry_card(title: "<b>\"x\" & 'y'"), fonts)

      refute svg =~ "<b>"
      assert svg =~ ">&lt;b&gt;&quot;x&quot; &amp; &#39;y&#39;</text>"
    end

    test "never loads anything: no image, link or external reference", %{fonts: fonts} do
      svg = svg(entry_card(), fonts)

      refute svg =~ ~r/<image|xlink:href|href=|<use|<script|<style|@import/
      refute svg =~ ~r{https?://(?!www\.w3\.org/2000/svg)}

      # url() only ever points inside the SVG, at its own gradients
      for [ref] <- Regex.scan(~r/url\([^)]*\)/, svg) do
        assert ref =~ ~r/\Aurl\(#[a-z-]+(-\d)?\)\z/, ref
      end
    end

    test "the home is the name on two lines, the position and the domain", %{
      content: content,
      fonts: fonts
    } do
      card = %{
        key: "home",
        kind: :home,
        title: content.home.title,
        subtitle: "Security engineer at Riot"
      }

      svg = svg(card, fonts)
      assert svg =~ ">Test</text>"
      assert svg =~ ">Person</text>"
      assert svg =~ ">Security engineer at Riot</text>"
      assert svg =~ ">yoanfaure.com</text>"
      refute svg =~ "Fixture tagline"
    end
  end

  describe "the build" do
    test "writes the images next to the pages, not under assets/", %{tree: tree} do
      assert tree |> Map.keys() |> Enum.filter(&String.starts_with?(&1, "og/")) |> length() == 6

      for {path, data} <- tree, String.starts_with?(path, "og/") do
        assert String.starts_with?(data, @png_signature), path
      end
    end

    test "publishes no font file: the TTF is build-only (priv/og-fonts/)", %{tree: tree} do
      refute Enum.any?(Map.keys(tree), &String.ends_with?(&1, [".ttf", ".otf"]))
      assert File.exists?("priv/og-fonts/Inter-Bold.ttf")
      assert File.exists?("priv/og-fonts/Inter-OFL.txt")

      assert Path.wildcard("priv/og-fonts/*") |> Enum.map(&Path.basename/1) |> Enum.sort() ==
               ["Inter-Bold.ttf", "Inter-OFL.txt"]

      assert Path.wildcard("assets/**/*.{ttf,otf}") == []
    end

    test "the home image says the position shown on the home", %{content: content} do
      files = Map.new(OG.files(content))
      fonts = OG.fonts!()

      role = Site.Config.role()

      card = %{
        key: "home",
        kind: :home,
        title: content.home.title,
        subtitle: "#{role.title} at #{role.company}"
      }

      png =
        card
        |> OG.svg(fonts)
        |> IO.iodata_to_binary()
        |> Resvg.svg_string_to_png_binary(
          fontdb: fonts.db,
          resources_dir: "priv/og-fonts",
          font_family: "Inter"
        )

      assert {:ok, files["og/home.png"]} == png
    end

    test "an entry page carries og:image, its size, its alt text and the large card",
         %{tree: tree} do
      html = Map.fetch!(tree, "second-essay/index.html")

      assert html =~
               ~s(<meta property="og:image" content="https://yoanfaure.com/og/second-essay.png">)

      assert html =~ ~s(<meta property="og:image:width" content="1200">)
      assert html =~ ~s(<meta property="og:image:height" content="630">)
      assert html =~ ~s(<meta property="og:image:alt" content="Second essay — Yoan Faure">)
      assert html =~ ~s(<meta name="twitter:card" content="summary_large_image">)
      refute html =~ ~s(content="summary")
    end

    test "the size in the meta tags is the size of the images", %{tree: tree} do
      {width, height} = OG.size()
      html = Map.fetch!(tree, "index.html")

      assert html =~ ~s(<meta property="og:image:width" content="#{width}">)
      assert html =~ ~s(<meta property="og:image:height" content="#{height}">)
    end

    test "the home page points at og/home.png", %{tree: tree} do
      html = Map.fetch!(tree, "index.html")

      assert html =~ ~s(<meta property="og:image" content="https://yoanfaure.com/og/home.png">)

      assert html =~
               ~s(<meta property="og:image:alt" content="Yoan Faure — Security engineer at Riot">)
    end

    test "every og:image on the site is an image the build wrote", %{tree: tree} do
      for {path, html} <- tree, String.ends_with?(path, ".html"), path != "404.html" do
        [_, url] = Regex.run(~r{<meta property="og:image" content="([^"]+)">}, html)
        assert "https://yoanfaure.com/" <> image = url, path
        assert Map.has_key?(tree, image), "#{path}: #{url} was not written"
      end
    end

    test "the 404 page has no share image, and keeps the small card", %{tree: tree} do
      html = Map.fetch!(tree, "404.html")

      refute html =~ "og:image"
      assert html =~ ~s(<meta name="twitter:card" content="summary">)
    end

    test "the alt text is escaped", %{tree: tree} do
      html = Map.fetch!(tree, "escape-me/index.html")

      assert html =~
               ~s|<meta property="og:image:alt" content="Tom &amp; &quot;Jerry&quot; &lt;script&gt;alert(1)&lt;/script&gt; — Yoan Faure">|

      refute html =~ "<script>alert"
    end
  end

  # -- helpers -----------------------------------------------------------------------

  defp fixture_content(opts \\ []), do: Content.load(fixture_copy(), opts)

  defp entry(attrs) do
    struct!(
      Site.Entry,
      Map.merge(
        %{
          type: :essay,
          date: ~D[2026-10-28],
          description: "d",
          html: "",
          file: "x.md"
        },
        Map.new(attrs)
      )
    )
  end
end
