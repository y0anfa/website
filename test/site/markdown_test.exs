defmodule Site.MarkdownTest do
  use ExUnit.Case, async: true

  alias Site.Markdown

  doctest Site.Markdown

  defp html(markdown), do: Markdown.render(markdown).html

  test "raw HTML is escaped, never rendered" do
    out =
      html("Text <script>alert(1)</script> and <b>bold</b>\n\n<div onclick=\"x()\">block</div>\n")

    refute out =~ "<script"
    refute out =~ "<b>"
    refute out =~ "<div"
    assert out =~ "&lt;script&gt;"
    assert out =~ "&lt;div onclick"
  end

  test "dangerous link targets are neutralised" do
    out = html("[x](javascript:alert(1)) ![y](data:text/html;base64,AAA)")
    refute out =~ "javascript:"
    refute out =~ "data:text/html"
  end

  test "GFM tables, strikethrough, autolinks and footnotes" do
    out =
      html(
        "| a | b |\n|---|---|\n| 1 | 2 |\n\n~~gone~~ https://example.com/x note.[^1]\n\n[^1]: The note.\n"
      )

    assert out =~ "<table>"
    assert out =~ "<del>gone</del>"
    assert out =~ ~s(<a href="https://example.com/x">https://example.com/x</a>)
    assert out =~ ~s(<section class="footnotes")
    assert out =~ "The note."
  end

  test "headings get ids" do
    assert html("## A heading here\n") =~ ~s(<h2 id="a-heading-here">)
  end

  describe "code blocks" do
    test "are highlighted with classes, never with inline styles" do
      out = html("```elixir\n# say it\nIO.puts(\"<hi>\")\n```\n")

      assert out =~ ~s(<pre class="lumis"><code class="language-elixir")
      assert out =~ ~s(<span class="l-comment"># say it</span>)
      assert out =~ ~s(<span class="l-string">&quot;&lt;hi&gt;&quot;</span>)
      refute out =~ "style="
      refute out =~ "<hi>"
    end

    test "every language a post may use has its parser" do
      for {lang, code} <- [
            {"bash", "echo hi # c"},
            {"diff", "- a\n+ b"},
            {"dockerfile", "FROM scratch"},
            {"elixir", "def f, do: 1"},
            {"go", "func main() {}"},
            {"hcl", "a = 1"},
            {"javascript", "const a = 1"},
            {"json", ~s({"a": 1})},
            {"python", "def f(): pass"},
            {"rust", "fn main() {}"},
            {"sql", "select 1"},
            {"toml", "a = 1"},
            {"typescript", "const a: number = 1"},
            {"yaml", "a: 1"}
          ] do
        out = html("```#{lang}\n#{code}\n```\n")
        assert out =~ ~s(class="language-#{lang}"), lang
        # a token span inside the line span: the parser ran
        assert out =~ ~r/<span class="l-line"[^>]*>.*<span class="l-/s, lang
      end
    end

    test "a language without a parser, or none, is plain text, escaped" do
      for fence <- ["```cobol", "```"] do
        out = html("#{fence}\nplain <b>\n```\n")
        assert out =~ ~s(<pre class="lumis"><code class="language-plaintext")
        assert out =~ "plain &lt;b&gt;"
        refute out =~ ~s(class="l-keyword)
      end
    end
  end

  describe "callouts" do
    test "a GitHub alert becomes a titled box" do
      out = html("> [!WARNING]\n> Never log the **token**.\n")

      assert out =~ ~s(<div class="markdown-alert markdown-alert-warning">)
      assert out =~ ~s(<p class="markdown-alert-title">Warning</p>)
      assert out =~ "<p>Never log the <strong>token</strong>.</p>"
    end

    test "the five kinds, and a title of one's own" do
      for kind <- ~w(note tip important warning caution) do
        out = html("> [!#{String.upcase(kind)}]\n> x\n")
        assert out =~ "markdown-alert-#{kind}", kind
      end

      assert html("> [!NOTE] Read this first\n> x\n") =~
               ~s(<p class="markdown-alert-title">Read this first</p>)
    end

    test "a plain quote stays a quote, and markup in a callout stays text" do
      assert html("> just a quote\n") =~ "<blockquote>"

      out = html("> [!NOTE] <b>t</b>\n> <script>x</script>\n")
      refute out =~ "<script"
      refute out =~ "<b>"
    end
  end

  describe "diagrams" do
    test "a mermaid block is drawn as an inline SVG figure" do
      out = html("before\n\n```mermaid\ngraph TD\n  A[One] --> B[Two]\n```\n\nafter\n")

      assert out =~ ~r{<p>before</p>\s*<figure class="diagram"><svg }
      assert out =~ ~r{</svg></figure>\s*<p>after</p>}
      refute out =~ "language-mermaid"
      refute out =~ "\u{E000}"
    end

    test "a diagram outside the subset stays a code block" do
      out = html("```mermaid\npie title Pets\n  \"Dogs\" : 3\n```\n")

      assert out =~ ~s(<pre class="lumis"><code class="language-mermaid")
      assert out =~ "pie title Pets"
      refute out =~ "<svg"
    end

    test "the first paragraph is still the summary when a diagram opens the entry" do
      rendered = Markdown.render("```mermaid\ngraph TD\n  A --> B\n```\n\nThe words.\n")
      assert rendered.summary == "The words."
    end
  end

  describe "summary" do
    test "is the plain text of the first paragraph" do
      assert Markdown.render(
               "# Title\n\nSome *emphasised*, `coded` and [linked](https://x.y) text.\n\nSecond.\n"
             ).summary ==
               "Some emphasised, coded and linked text."
    end

    test "joins soft line breaks and collapses whitespace" do
      assert Markdown.render("one\ntwo   three\n").summary == "one two three"
    end

    test "is empty without a paragraph" do
      assert Markdown.render("# Only a heading\n").summary == ""
    end

    test "is cut to 160 characters on a word boundary" do
      summary = Markdown.render(String.duplicate("word ", 80)).summary
      assert String.length(summary) <= 160
      assert String.ends_with?(summary, "word…")
    end
  end

  describe "truncate/2" do
    test "keeps short text" do
      assert Markdown.truncate("short", 10) == "short"
    end

    test "cuts on a word boundary and adds an ellipsis" do
      assert Markdown.truncate("alpha beta gamma delta", 14) == "alpha beta…"
      assert String.length(Markdown.truncate("alpha beta gamma delta", 14)) <= 14
    end

    test "cuts a single long word" do
      out = Markdown.truncate(String.duplicate("x", 50), 10)
      assert String.length(out) == 10
      assert String.ends_with?(out, "…")
    end
  end
end
