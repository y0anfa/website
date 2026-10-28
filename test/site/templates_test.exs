defmodule Site.TemplatesTest do
  use ExUnit.Case, async: true

  # Every `<%= expr %>` in a template must be one of:
  #   * escape(...)                       interpolating a value
  #   * raw(@content | @head_js | @doc.html | @entry.html)   already-safe HTML
  #   * header(...) | footer(...) | log(...) | meta(...)    partials (linted themselves)
  #   * a block opener: for / if / cond / case / unless
  # Anything else would put an unescaped value into a page.
  @allowed [
    ~r/\Aescape\(.+\)\z/s,
    ~r/\Araw\(@(content|head_js|doc\.html|entry\.html)\)\z/,
    ~r/\A(header|footer|log|meta)\(%\{[^}]*\}\)\z/,
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

  test "the layout has exactly one inline script, and it is the head.js slot" do
    layout = File.read!("templates/layout.html.eex")

    # a <script> without attributes is an inline script
    assert Regex.scan(~r{<script>(.*?)</script>}s, layout) |> Enum.map(&List.last/1) ==
             ["<%= raw(@head_js) %>"]

    # every other script tag points at a file
    for line <- String.split(layout, "\n"),
        line =~ "<script",
        line != "<script><%= raw(@head_js) %></script>" do
      assert line =~ "src=", "inline script without src: #{line}"
    end
  end

  test "the home template only puts rendered Markdown through raw" do
    assert File.read!("templates/home.html.eex") =~ "raw(@doc.html)"
    refute File.read!("templates/home.html.eex") =~ "raw(@doc.title)"
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
        section: "notes",
        meta: Site.View.article_meta(entry)
      })

    refute article =~ "<script>"
    assert article =~ "<p>ok</p>"
  end
end
