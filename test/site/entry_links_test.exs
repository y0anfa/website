defmodule Site.EntryLinksTest do
  use ExUnit.Case, async: true

  import Site.TestHelpers

  alias Site.{Entry, Templates, View}

  @css File.read!("assets/css/site.css")

  setup_all do
    %{tree: build_fixtures() |> read_tree()}
  end

  defp entry(attrs) do
    struct!(
      Entry,
      Map.merge(
        %{type: :essay, slug: "an-essay", title: "T", date: ~D[2026-10-28], description: "d"},
        Map.new(attrs)
      )
    )
  end

  # The href of the "ask claude" link in a built page, HTML-unescaped.
  defp ask_href(html) do
    [_, href] = Regex.run(~r{<a href="([^"]+)" rel="noopener">ask claude ↗</a>}, html)

    href
    |> String.replace("&amp;", "&")
    |> String.replace("&quot;", ~s("))
    |> String.replace("&#39;", "'")
    |> String.replace("&lt;", "<")
    |> String.replace("&gt;", ">")
  end

  defp prompt(href) do
    %URI{scheme: "https", host: "claude.ai", path: "/new", query: query} = URI.parse(href)
    URI.decode_query(query)["q"]
  end

  describe "the prompt" do
    test "an essay or a note asks for the main argument and where to push back" do
      for type <- [:essay, :note] do
        assert View.ask_prompt(entry(type: type)) ==
                 "Read https://yoanfaure.com/an-essay/ by Yoan Faure, a security engineer. " <>
                   "Using only what is on that page, summarize the main argument in a few " <>
                   "sentences, then tell me where you would push back."
      end
    end

    test "a project asks what it does and why, and for one improvement" do
      assert View.ask_prompt(entry(type: :project, slug: "rhino")) ==
               "Read https://yoanfaure.com/rhino/ by Yoan Faure, a security engineer. " <>
                 "Using only what is on that page, summarize what the project does and why, " <>
                 "then suggest one improvement."
    end
  end

  describe "the URL" do
    test "is claude.ai/new with the prompt, URI-encoded, in q" do
      for type <- [:essay, :project] do
        e = entry(type: type)
        url = View.ask_url(e)

        assert String.starts_with?(url, "https://claude.ai/new?q=")
        assert prompt(url) == View.ask_prompt(e)
      end
    end

    test "encodes everything but the unreserved characters: %20 for a space, never + or a raw &" do
      query = View.ask_url(entry([])) |> String.replace_prefix("https://claude.ai/new?q=", "")

      assert query =~ ~r/\A[A-Za-z0-9._~%-]+\z/
      assert query =~ "Read%20https%3A%2F%2Fyoanfaure.com%2Fan-essay%2F%20by%20Yoan%20Faure%2C"
      refute query =~ "+"
      refute query =~ " "
    end

    test "the entry links are the twin and the chat" do
      assert View.entry_links(entry(slug: "rhino")) == %{
               markdown: "/rhino.md",
               ask: View.ask_url(entry(slug: "rhino"))
             }
    end
  end

  describe "the partial" do
    test "escapes both hrefs for HTML after the URI encoding" do
      html =
        Templates.entry_links(%{
          links: %{markdown: ~S|/x".md|, ask: ~S|https://claude.ai/new?q=a&b"<c>'d|}
        })

      assert html =~ ~S|href="/x&quot;.md"|
      assert html =~ ~S|href="https://claude.ai/new?q=a&amp;b&quot;&lt;c&gt;&#39;d"|
      refute html =~ ~S|"<c>|
    end
  end

  describe "the built pages" do
    test "every entry page has both links after the body, next to the back link", %{tree: tree} do
      for slug <- ~w(escape-me first-essay second-essay small-note widget) do
        html = Map.fetch!(tree, "#{slug}/index.html")

        assert html =~
                 ~r{<div class="entry-end">\s*<p class="back"><a href="/">← log</a></p>\s*<p class="entry-links"><a href="/#{slug}.md">markdown</a> · <a href="https://claude.ai/new\?q=[^"]+" rel="noopener">ask claude ↗</a></p>\s*</div>\s*</article>}s,
               slug
      end
    end

    test "the Claude link opens in the same tab and does not leak the opener", %{tree: tree} do
      for {path, html} <- tree, String.ends_with?(path, "/index.html"), path != "index.html" do
        [_, anchor] = Regex.run(~r{(<a [^>]*>ask claude ↗</a>)}, html)

        assert anchor =~ ~s(rel="noopener"), path
        refute anchor =~ "target", path
        refute anchor =~ "_blank", path
      end
    end

    test "the link asks about the page it is on, with the right prompt for the type", %{
      tree: tree
    } do
      essay = prompt(ask_href(tree["first-essay/index.html"]))

      assert essay =~
               "Read https://yoanfaure.com/first-essay/ by Yoan Faure, a security engineer."

      assert essay =~ "summarize the main argument in a few sentences"

      note = prompt(ask_href(tree["small-note/index.html"]))
      assert note =~ "https://yoanfaure.com/small-note/"
      assert note =~ "summarize the main argument"

      project = prompt(ask_href(tree["widget/index.html"]))
      assert project =~ "Read https://yoanfaure.com/widget/ by Yoan Faure"
      assert project =~ "summarize what the project does and why, then suggest one improvement."
    end

    test "a hostile title cannot reach the links", %{tree: tree} do
      html = tree["escape-me/index.html"]
      [_, links] = Regex.run(~r{(<p class="entry-links">.*?</p>)}, html)

      assert links =~ ~S|href="/escape-me.md"|
      refute links =~ "script"
      refute links =~ ~r/[<>]"/
    end

    test "the home and the 404 have no such links", %{tree: tree} do
      for page <- ["index.html", "404.html"] do
        refute tree[page] =~ "entry-links", page
        refute tree[page] =~ "claude.ai", page
      end
    end

    test "the labels are lowercase", %{tree: tree} do
      [_, links] = Regex.run(~r{<p class="entry-links">(.*?)</p>}, tree["first-essay/index.html"])
      text = links |> String.replace(~r/<[^>]+>/, "") |> String.replace("&amp;", "&")

      assert text == "markdown · ask claude ↗"
      assert text == String.downcase(text)
    end
  end

  describe "the style" do
    defp block(selector) do
      [_, body] = Regex.run(~r/(?:^|\n)#{Regex.escape(selector)}\s*\{(.*?)\}/s, @css)
      body
    end

    test "the links are small and muted, and the row sits on the back link's hairline" do
      links = block(".entry-end .entry-links")
      assert links =~ "color: var(--muted);"
      assert links =~ "font-size: 0.875rem;"

      row = block(".entry-end")
      assert row =~ "display: flex;"
      assert row =~ "justify-content: space-between;"
      assert row =~ "border-top: 1px solid var(--rule);"
      assert block(".entry-end .back") =~ "border-top: 0;"
    end

    test "the new CSS names no font and sets no inline style" do
      [_, mine] = String.split(@css, "entry end: back link, markdown twin, ask claude", parts: 2)
      refute mine =~ "font-family"
    end
  end
end
