defmodule Site.TemplatesTest do
  use ExUnit.Case, async: true

  # Every `<%= expr %>` in a template must be one of:
  #   * escape(...)                                    interpolating a value
  #   * raw(@content | @head_js | @speculation | @entry.html)   already-safe HTML
  #   * toggle() | back_icon()                         static partials
  #   * bar(...) | feed(...) | meta(...) | article_end(...)     partials (linted themselves)
  #   * a block opener: for / if / cond / case / unless
  # Anything else would put an unescaped value into a page.
  @allowed [
    ~r/\Aescape\(.+\)\z/s,
    ~r/\Araw\(@(content|head_js|speculation|entry\.html)\)\z/,
    ~r/\A(toggle|back_icon)\(\)\z/,
    ~r/\A(bar|feed|meta|article_end)\(%\{[^}]*\}\)\z/,
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

      test "loads nothing from elsewhere" do
        source = File.read!(@template)

        refute source =~ "fonts.googleapis"
        refute source =~ ~r/\ssrc="https?:/
        refute source =~ ~r/<link [^>]*href="https?:/
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

  test "the layout loads site.js render-blocking, and no field, theme or transitions script" do
    layout = File.read!("templates/layout.html.eex")

    assert layout =~ ~S(<script defer blocking="render" src="/assets/js/site.js"></script>)

    for gone <- ~w(field.js theme.js transitions.js data-field-root canvas type="module") do
      refute layout =~ gone, gone
    end
  end

  test "the layout preloads the Inter variable font and nothing from Google" do
    layout = File.read!("templates/layout.html.eex")

    assert layout =~
             ~S(<link rel="preload" href="/assets/fonts/InterVariable.woff2" as="font" type="font/woff2" crossorigin>)

    refute layout =~ "JetBrainsMono"
    refute layout =~ "preconnect"
  end

  test "the layout is a skip link and the page: no header, no footer of its own" do
    layout = File.read!("templates/layout.html.eex")

    assert layout =~ ~S|<a class="skip-link" href="<%= escape(@skip.href) %>">|
    refute layout =~ "<header"
    refute layout =~ "<footer"
    refute layout =~ "<main"
  end

  test "the home is the name, the position and the feed, and the line after main" do
    home = File.read!("templates/home.html.eex")

    assert home =~ ~S(<main id="main" class="stage">)
    assert home =~ ~S|<h1 class="name" id="name"><%= escape(@name) %></h1>|
    assert home =~ ~S(<p class="role">)
    assert home =~ "<%= feed(%{years: @years}) %>"
    refute home =~ "<footer"
    refute home =~ "raw("

    [_, after_main] = String.split(home, "</main>")

    assert String.trim(after_main) ==
             ~S(<svg class="line" aria-hidden="true"><path pathLength="1"/></svg>)
  end

  test "there are no list templates, and no nav anywhere" do
    refute File.exists?("templates/list.html.eex")
    refute File.exists?("templates/page.html.eex")

    for gone <- ~w(_log _footer _header _entry_links) do
      refute File.exists?("templates/#{gone}.html.eex"), gone
    end

    for file <- @template_files do
      refute File.read!(file) =~ "<nav", file
      refute File.read!(file) =~ "aria-current", file
    end
  end

  test "entries and the 404 open with the bar and end with the back link" do
    for file <- ~w(article project 404) do
      source = File.read!("templates/#{file}.html.eex")
      assert source =~ ~r/\A<%= bar\(%\{esc: (true|false)\}\) %>/, file
      assert source =~ "<%= article_end(%{links: ", file
    end

    end_ = File.read!("templates/_article_end.html.eex")
    assert end_ =~ ~S(<a class="back" href="/" data-home>)
    assert end_ =~ "All entries"
  end

  test "a hostile title cannot break out of a template" do
    entry = %Site.Entry{
      type: :note,
      slug: "x",
      title: ~S|"><script>alert(1)</script>|,
      date: ~D[2026-10-28],
      summary: ~S|<img src=x>|,
      html: "<p>ok</p>"
    }

    row = entry |> Site.Log.row() |> Map.put(:n, 1)
    html = Site.Templates.feed(%{years: [{2026, [row]}]})
    assert html =~ "&quot;&gt;&lt;script&gt;alert(1)&lt;/script&gt;"
    refute html =~ "<script>"
    # the summary is not on the home at all
    refute html =~ "src=x"

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
