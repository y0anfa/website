defmodule Site.HeadersTest do
  use ExUnit.Case, async: true

  alias Site.Headers

  @hash "sha256-abc="

  test "script_hash is the base64 sha256 of the script text" do
    expected = "sha256-" <> Base.encode64(:crypto.hash(:sha256, "console.log(1)"))
    assert Headers.script_hash("console.log(1)") == expected
    assert Headers.script_hash("") == "sha256-47DEQpj8HBSa+/TImW+5JCeuQeRkm5NMpJWZG3hSuFU="
  end

  test "the CSP has exactly the directives of the spec" do
    assert Headers.csp(@hash) ==
             "default-src 'none'; script-src 'self' '#{@hash}' https://static.cloudflareinsights.com; " <>
               "style-src 'self'; img-src 'self'; font-src 'self'; " <>
               "connect-src 'self' https://cloudflareinsights.com; manifest-src 'self'; " <>
               "base-uri 'none'; form-action 'none'; frame-ancestors 'none'; " <>
               "upgrade-insecure-requests"
  end

  test "the CSP always allows the two Cloudflare hosts and no other third party" do
    csp = Headers.csp(@hash)

    assert csp =~ "script-src 'self' '#{@hash}' https://static.cloudflareinsights.com;"
    assert csp =~ "connect-src 'self' https://cloudflareinsights.com;"

    hosts = ~r{https?://[^\s;']+} |> Regex.scan(csp) |> List.flatten() |> Enum.sort()
    assert hosts == ["https://cloudflareinsights.com", "https://static.cloudflareinsights.com"]
    refute csp =~ "*"
  end

  test "the CSP never allows inline styles or eval" do
    csp = Headers.csp(@hash)
    refute csp =~ "unsafe-inline"
    refute csp =~ "unsafe-eval"
    refute csp =~ "style-src 'self' '"
  end

  test "render produces the documented _headers file" do
    text = Headers.render(@hash)

    assert String.starts_with?(text, "/*\n  Content-Security-Policy: default-src 'none'; ")
    assert text =~ " https://static.cloudflareinsights.com; "
    assert text =~ " https://cloudflareinsights.com; "
    assert text =~ "\n  Strict-Transport-Security: max-age=63072000; includeSubDomains\n"
    assert text =~ "\n  X-Content-Type-Options: nosniff\n"
    assert text =~ "\n  X-Frame-Options: DENY\n"
    assert text =~ "\n  Referrer-Policy: strict-origin-when-cross-origin\n"

    assert text =~
             "\n  Permissions-Policy: accelerometer=(), camera=(), geolocation=(), gyroscope=(), "

    assert text =~ "\n  Cross-Origin-Opener-Policy: same-origin\n"
    assert text =~ "\n  Cross-Origin-Resource-Policy: same-origin\n"

    assert String.ends_with?(
             text,
             "/assets/fonts/*\n  Cache-Control: public, max-age=31536000, immutable\n"
           )
  end

  describe "parse/1 and for_path/2" do
    setup do
      %{rules: Headers.parse(Headers.render(@hash))}
    end

    test "parses patterns and headers", %{rules: rules} do
      assert [
               %{pattern: "/*", headers: all},
               %{pattern: "/*.md"},
               %{pattern: "/llms.txt"},
               %{pattern: "/assets/fonts/*", headers: fonts}
             ] = rules

      assert {"X-Frame-Options", "DENY"} in all
      assert {"Content-Security-Policy", Headers.csp(@hash)} in all
      assert fonts == [{"Cache-Control", "public, max-age=31536000, immutable"}]
    end

    test "/* matches every path", %{rules: rules} do
      for path <- ["/", "/rhino/", "/assets/js/field.js", "/404.html"] do
        headers = Headers.for_path(rules, path)
        assert {"X-Content-Type-Options", "nosniff"} in headers
        refute Enum.any?(headers, &match?({"Cache-Control", _}, &1))
      end
    end

    test "fonts get both rules", %{rules: rules} do
      headers = Headers.for_path(rules, "/assets/fonts/InterVariable.woff2")
      assert {"Cache-Control", "public, max-age=31536000, immutable"} in headers
      assert {"X-Frame-Options", "DENY"} in headers
    end

    test "comments, blank lines and tabs are tolerated" do
      rules = Headers.parse("# a comment\n\n/x/*\n\tA: 1\n  B:  two words \n")
      assert rules == [%{pattern: "/x/*", headers: [{"A", "1"}, {"B", "two words"}]}]
    end
  end

  test "splat matching" do
    assert Headers.matches?("/*", "/")
    assert Headers.matches?("/*", "/a/b/c")
    assert Headers.matches?("/assets/*", "/assets/x.css")
    refute Headers.matches?("/assets/*", "/other/x.css")
    assert Headers.matches?("/exact", "/exact")
    refute Headers.matches?("/exact", "/exact/more")
    assert Headers.matches?("/a/*/c", "/a/b/c")
    refute Headers.matches?("/a.b", "/axb")
  end
end
