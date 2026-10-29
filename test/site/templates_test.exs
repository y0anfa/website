defmodule Site.TemplatesTest do
  use ExUnit.Case, async: true

  # Every `<%= expr %>` in a template must be one of:
  #   * escape(...)                       interpolating a value
  #   * raw(@content | @head_js | @speculation | @doc.html | @entry.html)   already-safe HTML
  #   * header() | footer(...) | log(...) | meta(...) | entry_links(...)    partials (linted themselves)
  #   * a block opener: for / if / cond / case / unless
  # Anything else would put an unescaped value into a page.
  @allowed [
    ~r/\Aescape\(.+\)\z/s,
    ~r/\Araw\(@(content|head_js|speculation|doc\.html|entry\.html)\)\z/,
    ~r/\Aheader\(\)\z/,
    ~r/\A(footer|log|meta|entry_links)\(%\{[^}]*\}\)\z/,
    ~r/\A(for|if|cond|case|unless)\s/
  ]

  @template_files Path.wildcard("templates/*.eex") |> Enum.sort()

  test "the template files are the ones compiled into Site.Templates" do
    compiled = Site.Templates.files() |> Enum.map(&elem(&1, 1)) |> Enum.map(&Path.basename/1)
    assert Enum.sort(compiled) == Enum.map(@template_files, &Path.basename/1)
  end

  for file <- @template_files do
    describe Path.basename(file) do
      @template file

      test "routes every interpolation through escape/1 or an allowed raw form" do
        source = File.read!(@template)

        for [_, expr] <- Regex.scan(~r/<%=\s*(.*?)\s*%>/s, source) do
          assert Enum.any?(@allowed, &Regex.match?(&1, expr)),
                 "#{@template}: unescaped interpolation <%= #{expr} %>"
        end
      end

      test "has no inline style, <style>, or inline event handler" do
        source = File.read!(@template)

        refute source =~ ~r/\sstyle\s*=/i
        refute source =~ ~r/<style[\s>]/i
        refute source =~ ~r/\son[a-z]+\s*=/i
        refute source =~ ~r/javascript:/i
      end

      test "only the layout carries scripts" do
        scripts = Regex.scan(~r/<script/, File.read!(@template))

        if Path.basename(@template) == "layout.html.eex",
          do: assert(scripts != []),
          else: assert(scripts == [])
      end
    end
  end

  test "the layout has two inline scripts: the head.js slot and the speculation rules" do
    layout = File.read!("templates/layout.html.eex")
    rules = ~S|<script type="speculationrules"><%= raw(@speculation) %></script>|

    # a <script> without attributes is the head.js inline script
    assert Regex.scan(~r{<script>(.*?)</script>}s, layout) |> Enum.map(&List.last/1) ==
             ["<%= raw(@head_js) %>"]

    # the other inline script is the speculation rules, and nothing else
    assert Regex.scan(~r{<script type="speculationrules">(.*?)</script>}s, layout)
           |> Enum.map(&List.last/1) == ["<%= raw(@speculation) %>"]

    # every other script tag points at a file
    for line <- String.split(layout, "\n"),
        line =~ "<script",
        line not in ["<script><%= raw(@head_js) %></script>", rules] do
      assert line =~ "src=", "inline script without src: #{line}"
    end
  end

  test "the layout has the field backdrop between the skip link and the header, on every page" do
    layout = File.read!("templates/layout.html.eex")

    backdrop =
      ~S(<div class="field" data-field-root aria-hidden="true">) <>
        ~S(<canvas class="field-canvas"></canvas></div>)

    assert layout =~
             ~r/<a class="skip-link" href="#main">[^<]*<\/a>\n#{Regex.escape(backdrop)}\n<%= header\(/

    assert length(Regex.scan(~r/data-field-root/, layout)) == 1
  end

  test "the layout loads field.js as a module, with no preset switch" do
    layout = File.read!("templates/layout.html.eex")

    assert layout =~ ~S(<html lang="en" data-vt="morph">)
    assert layout =~ ~S(<script type="module" src="/assets/js/field.js"></script>)
    refute layout =~ "data-field="
  end

  test "no page template but the layout knows about the field" do
    for file <- @template_files, Path.basename(file) != "layout.html.eex" do
      source = File.read!(file)
      refute source =~ "data-field", file
      refute source =~ "canvas", file
      refute source =~ "field.js", file
    end
  end

  test "the home template is an intro and the log, with no hero or field section" do
    home = File.read!("templates/home.html.eex")

    refute home =~ "hero"
    refute home =~ "field"
    assert home =~ ~S(<div class="intro">)
    assert home =~ ~S(<section class="log-section" aria-labelledby="log-h">)
  end

  test "the home template only puts rendered Markdown through raw" do
    assert File.read!("templates/home.html.eex") =~ "raw(@doc.html)"
    refute File.read!("templates/home.html.eex") =~ "raw(@doc.title)"
  end

  test "there are no list or page templates, and no nav in the shell" do
    refute File.exists?("templates/list.html.eex")
    refute File.exists?("templates/page.html.eex")
    refute Map.has_key?(Map.new(Site.Templates.files()), :list)
    refute Map.has_key?(Map.new(Site.Templates.files()), :page)

    header = File.read!("templates/_header.html.eex")
    refute header =~ "<nav"
    refute header =~ "site-nav"
    refute header =~ "aria-current"
    assert header =~ ~S(<a class="brand" href="/">yoan faure</a>)
    assert header =~ ~S(<button class="theme-toggle" type="button" aria-label="Toggle theme">)
  end

  test "entries link back to the log, not to a section" do
    for file <- ["templates/article.html.eex", "templates/project.html.eex"] do
      source = File.read!(file)
      assert source =~ ~S(<p class="back"><a href="/">← log</a></p>), file
      refute source =~ "@section", file
    end
  end

  test "the 404 terminal is made of pre lines, so every line is mono" do
    source = File.read!("templates/404.html.eex")
    assert length(Regex.scan(~r/<pre class="terminal/, source)) == 2
    refute source =~ ~r/<p[\s>]/
  end

  test "the layout preloads the Inter variable font and has no script flag for modules" do
    layout = File.read!("templates/layout.html.eex")

    assert layout =~
             ~S(<link rel="preload" href="/assets/fonts/InterVariable.woff2" as="font" type="font/woff2" crossorigin>)

    refute layout =~ "JetBrainsMono"
    refute layout =~ ".module"
  end

  test "a hostile title cannot break out of a template" do
    entry = %Site.Entry{
      type: :note,
      slug: "x",
      title: ~S|"><script>alert(1)</script>|,
      date: ~D[2026-10-28],
      html: "<p>ok</p>"
    }

    row = Site.Log.row(entry)
    html = Site.Templates.log(%{rows: [row]})
    assert html =~ "&quot;&gt;&lt;script&gt;alert(1)&lt;/script&gt;"
    refute html =~ "<script>"

    article =
      Site.Templates.article(%{
        entry: entry,
        meta: Site.View.article_meta(entry),
        links: Site.View.entry_links(entry)
      })

    refute article =~ "<script>"
    assert article =~ "<p>ok</p>"
  end
end
