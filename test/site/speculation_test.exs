defmodule Site.SpeculationTest do
  use ExUnit.Case, async: true

  import Site.TestHelpers

  alias Site.{Headers, Speculation}

  @head_js File.read!("assets/js/head.js") |> String.trim()

  setup_all do
    %{tree: build_fixtures() |> read_tree()}
  end

  defp sha(text), do: "sha256-" <> Base.encode64(:crypto.hash(:sha256, text))

  defp pages(tree),
    do: for({path, html} <- tree, String.ends_with?(path, ".html"), do: {path, html})

  describe "the rules" do
    test "are valid JSON: prerender every page link, with moderate eagerness" do
      assert %{"prerender" => [rule]} = JSON.decode!(Speculation.rules())

      assert rule["eagerness"] == "moderate"
      assert %{"and" => [first | exclusions]} = rule["where"]
      assert first == %{"href_matches" => "/*"}

      assert exclusions == [
               %{"not" => %{"href_matches" => "/*.md"}},
               %{"not" => %{"href_matches" => "/llms.txt"}},
               %{"not" => %{"href_matches" => "/assets/*"}},
               %{"not" => %{"selector_matches" => "[rel~=nofollow]"}}
             ]
    end

    test "only prerender, never prefetch or a cross-origin target" do
      text = Speculation.rules()

      refute text =~ "prefetch"
      refute text =~ "urls"
      refute text =~ "http"
      refute text =~ "immediate"
    end

    test "are one line and cannot close their own script tag" do
      refute Speculation.rules() =~ "\n"
      refute String.downcase(Speculation.rules()) =~ "</script"
      assert Speculation.rules() == String.trim(Speculation.rules())
    end

    test "the hash is the sha256 of exactly that text, and does not change" do
      assert Speculation.hash() == sha(Speculation.rules())
      assert Speculation.hash() == Headers.script_hash(Speculation.rules())
      assert Speculation.hash() == Speculation.hash()
      assert Speculation.hash() =~ ~r/\Asha256-[A-Za-z0-9+\/]{43}=\z/
    end
  end

  describe "the pages" do
    test "every page has the rules once, in the head, as the only extra inline script", %{
      tree: tree
    } do
      for {path, html} <- pages(tree) do
        [head, _body] = String.split(html, "</head>")

        assert Regex.scan(~r{<script type="speculationrules">(.*?)</script>}s, head)
               |> Enum.map(&List.last/1) == [Speculation.rules()],
               path

        assert length(Regex.scan(~r/speculationrules/, html)) == 1, path
      end
    end

    test "the text of the script is the text that is hashed", %{tree: tree} do
      for {path, html} <- pages(tree) do
        [_, inline] = Regex.run(~r{<script type="speculationrules">(.*?)</script>}s, html)
        assert sha(inline) == Speculation.hash(), path
      end
    end

    test "the rules are the same on every page", %{tree: tree} do
      texts =
        for {_path, html} <- pages(tree) do
          [_, inline] = Regex.run(~r{<script type="speculationrules">(.*?)</script>}s, html)
          inline
        end

      assert Enum.uniq(texts) == [Speculation.rules()]
    end
  end

  describe "the CSP" do
    test "csp/1 takes one hash or a list" do
      assert Headers.csp("sha256-a=") =~ "script-src 'self' 'sha256-a=' https://static."

      assert Headers.csp(["sha256-a=", "sha256-b="]) =~
               "script-src 'self' 'sha256-a=' 'sha256-b=' https://static.cloudflareinsights.com;"
    end

    test "_headers allows exactly two inline scripts, head.js first and the rules next", %{
      tree: tree
    } do
      headers = Map.fetch!(tree, "_headers")

      assert headers =~
               "script-src 'self' '#{sha(@head_js)}' '#{Speculation.hash()}' " <>
                 "https://static.cloudflareinsights.com;"

      [csp] = Regex.run(~r/Content-Security-Policy: (.*)/, headers, capture: :all_but_first)
      assert length(Regex.scan(~r/'sha256-/, csp)) == 2

      assert Regex.scan(~r/'(sha256-[^']+)'/, csp) |> Enum.map(&List.last/1) ==
               [sha(@head_js), Speculation.hash()]

      refute csp =~ "unsafe-inline"
      refute csp =~ "inline-speculation-rules"
    end

    test "the hash in _headers matches the script in the page", %{tree: tree} do
      [_, inline] =
        Regex.run(~r{<script type="speculationrules">(.*?)</script>}s, tree["index.html"])

      assert tree["_headers"] =~ "'#{sha(inline)}'"
    end

    test "the hashes are the same on every build" do
      content = fixture_copy()
      a = [content: content] |> build_fixtures() |> read_tree()
      b = [content: content] |> build_fixtures() |> read_tree()

      assert a["_headers"] == b["_headers"]
      assert a["index.html"] == b["index.html"]
    end
  end
end
