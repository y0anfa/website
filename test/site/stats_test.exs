defmodule Site.StatsTest do
  use ExUnit.Case, async: true

  import Site.TestHelpers

  alias Site.Markdown

  @css File.read!("assets/css/site.css")

  defp html(markdown), do: Markdown.render(markdown).html

  describe "the stats code block" do
    test "becomes a definition list, one div per line" do
      out =
        html("""
        ```stats
        91% | only read or react
        0%  | chose "I comment"
        82  | respondents
        ```
        """)

      assert out ==
               ~s(<dl class="stats">) <>
                 ~s(<div><dt>91%</dt><dd>only read or react</dd></div>) <>
                 ~s(<div><dt>0%</dt><dd>chose &quot;I comment&quot;</dd></div>) <>
                 ~s(<div><dt>82</dt><dd>respondents</dd></div>) <>
                 "</dl>"
    end

    test "trims values and labels, and skips blank lines" do
      out = html("```stats\n\n   7   |    seven   \n\n\t8|eight\n\n```\n")

      assert out =~ "<div><dt>7</dt><dd>seven</dd></div>"
      assert out =~ "<div><dt>8</dt><dd>eight</dd></div>"
      assert length(Regex.scan(~r/<div>/, out)) == 2
    end

    test "splits at the first bar, so a label can contain one" do
      assert html("```stats\n3 | a | b\n```\n") =~ "<dt>3</dt><dd>a | b</dd>"
    end

    test "keeps the text escaped: markup in a value or a label stays text" do
      out = html("```stats\n<b>1</b> | a <script>alert(1)</script> & \"q\" 'r'\n```\n")

      refute out =~ "<script"
      refute out =~ "<b>"
      assert out =~ "<dt>&lt;b&gt;1&lt;/b&gt;</dt>"

      assert out =~
               "<dd>a &lt;script&gt;alert(1)&lt;/script&gt; &amp; &quot;q&quot; 'r'</dd>"
    end

    test "never unescapes: an entity typed by the author is shown as typed" do
      out = html("```stats\n1 | &lt;already&gt; &amp;\n```\n")

      assert out =~ "<dd>&amp;lt;already&amp;gt; &amp;amp;</dd>"
    end

    test "a block with a line that is not value | label stays a plain code block" do
      source = "```stats\n91% | only read\nthis line has no bar\n```\n"
      out = html(source)

      assert out =~ ~s(<pre><code class="language-stats">)
      assert out =~ "this line has no bar"
      refute out =~ "<dl"
    end

    test "an empty value or label is not a stat" do
      for line <- ["| label only", "value only |", "  |  "] do
        out = html("```stats\n#{line}\n```\n")
        assert out =~ ~s(<pre><code class="language-stats">), line
        refute out =~ "<dl", line
      end
    end

    test "an empty block stays a plain code block" do
      out = html("```stats\n```\n")

      assert out =~ ~s(<pre><code class="language-stats">)
      refute out =~ "<dl"
    end

    test "only the info string stats counts, and other code blocks are untouched" do
      out = html("```text\n1 | a\n```\n\n```Stats\n1 | a\n```\n\n```\n1 | a\n```\n")

      refute out =~ "<dl"
      assert length(Regex.scan(~r/<pre>/, out)) == 3
    end

    test "extra words after the info string are ignored" do
      assert html("```stats survey\n1 | a\n```\n") =~ ~s(<dl class="stats">)
    end

    test "several blocks, with prose between them" do
      out = html("one\n\n```stats\n1 | a\n```\n\ntwo\n\n```stats\n2 | b\n```\n\nthree\n")

      assert length(Regex.scan(~r/<dl class="stats">/, out)) == 2
      assert out =~ "<p>one</p>"
      assert out =~ "<p>two</p>"
      assert out =~ "<p>three</p>"
    end

    test "inline code that spells the markup is just code" do
      out = html(~S|Write `<pre><code class="language-stats">` to see it.|)

      refute out =~ "<dl"
      assert out =~ "&lt;pre&gt;"
    end

    test "adds nothing to the summary" do
      assert Markdown.render("```stats\n1 | a\n```\n\nSecond.\n").summary == "Second."
    end
  end

  describe "in a built page" do
    test "an essay gets the callout, with no inline style" do
      body = "Intro.\n\n```stats\n91% | only read or react\n82 | respondents\n```\n"

      dir =
        minimal_content(%{
          "essays/survey.md" => "---\ntitle: Survey\ndate: 2026-10-28\n---\n" <> body
        })

      out = Path.join(tmp_dir(), "dist")
      Site.Build.run(content: dir, out: out)
      page = File.read!(Path.join(out, "survey/index.html"))

      assert page =~ ~s(<dl class="stats"><div><dt>91%</dt><dd>only read or react</dd></div>)
      refute page =~ ~r/\sstyle\s*=/i
    end
  end

  describe "the stylesheet" do
    test "has a commented stats block" do
      assert @css =~ "stat callouts"
      assert @css =~ ~r/^\.stats \{/m
      assert @css =~ ~r/^\.stats > div \{/m
      assert @css =~ ~r/^\.stats dt \{/m
      assert @css =~ ~r/^\.stats dd \{/m
    end

    defp rule(selector) do
      [_, body] = Regex.run(~r/^#{Regex.escape(selector)} \{\n(.*?)\n\}/ms, @css)
      body
    end

    test "is a responsive grid of at most four columns" do
      grid = rule(".stats")

      assert grid =~ "display: grid;"
      # 8.5rem minimum: four columns fit the 38rem reading column, two fit a phone
      assert grid =~ "grid-template-columns: repeat(auto-fit, minmax(8.5rem, 1fr));"
    end

    test "sets the value in Inter 700, large and tight, and the label small and muted" do
      value = rule(".stats dt")
      label = rule(".stats dd")

      assert value =~ ~r/font-size: clamp\(2\.25rem, [^;]*, 2\.75rem\);/
      assert value =~ "font-weight: 700;"
      assert value =~ "letter-spacing: -0.03em;"
      refute value =~ "font-family"

      assert label =~ "color: var(--muted);"
      assert label =~ "font-size: 0.875rem;"
      refute label =~ "font-family"
    end

    test "is ruled with the --rule hairline and uses no raw colour" do
      cell = rule(".stats > div")

      assert cell =~ "border-top: 1px solid var(--rule);"

      block = @css |> String.split("stat callouts") |> List.last()
      refute block =~ ~r/#[0-9a-fA-F]{3,6}\b/
      refute block =~ "!important"
    end
  end
end
