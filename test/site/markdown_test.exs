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

  test "code blocks are plain: no syntax colouring, no inline styles" do
    out = html("```elixir\nIO.puts(\"<hi>\")\n```\n")

    assert out =~ ~s(<pre><code class="language-elixir">)
    assert out =~ "&lt;hi&gt;"
    refute out =~ "style="
    refute out =~ "<span"
  end

  test "an unlabelled code block is a bare pre/code" do
    assert html("```\nplain\n```\n") =~ "<pre><code>plain\n</code></pre>"
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
