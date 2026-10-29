defmodule Site.Headers do
  @moduledoc """
  The `_headers` file (Cloudflare format) and the Content Security Policy.

  The CSP allows exactly two inline scripts, by their sha256: `assets/js/head.js`
  and the Speculation Rules (`Site.Speculation`).
  Cloudflare Web Analytics runs on automatic setup: Cloudflare injects the beacon
  at the edge, so the CSP always allows its two hosts, the one third-party
  exception.
  """

  @beacon_script "https://static.cloudflareinsights.com"
  @beacon_connect "https://cloudflareinsights.com"

  @security [
    {"Strict-Transport-Security", "max-age=63072000; includeSubDomains"},
    {"X-Content-Type-Options", "nosniff"},
    {"X-Frame-Options", "DENY"},
    {"Referrer-Policy", "strict-origin-when-cross-origin"},
    {"Permissions-Policy",
     "accelerometer=(), camera=(), geolocation=(), gyroscope=(), magnetometer=(), microphone=(), payment=(), usb=()"},
    {"Cross-Origin-Opener-Policy", "same-origin"},
    {"Cross-Origin-Resource-Policy", "same-origin"}
  ]

  @type rule :: %{pattern: String.t(), headers: [{String.t(), String.t()}]}

  @doc "The `sha256-…` source expression for an inline script."
  @spec script_hash(String.t()) :: String.t()
  def script_hash(script) do
    "sha256-" <> Base.encode64(:crypto.hash(:sha256, script))
  end

  @doc """
  The Content Security Policy for the hashes of the inline scripts: one hash or a
  list. The site has exactly two, `head.js` and the Speculation Rules.
  """
  @spec csp(String.t() | [String.t()]) :: String.t()
  def csp(script_hashes) do
    hashes = script_hashes |> List.wrap() |> Enum.map_join(" ", &"'#{&1}'")

    [
      "default-src 'none'",
      "script-src 'self' #{hashes} #{@beacon_script}",
      "style-src 'self'",
      "img-src 'self'",
      "font-src 'self'",
      "connect-src 'self' #{@beacon_connect}",
      "manifest-src 'self'",
      "base-uri 'none'",
      "form-action 'none'",
      "frame-ancestors 'none'",
      "upgrade-insecure-requests"
    ]
    |> Enum.join("; ")
  end

  @doc """
  Renders the `_headers` file. Takes the inline-script hash, or a list of them.

  The Markdown twins and `llms.txt` get an explicit `Content-Type`, so they are
  served as text with a charset whatever the platform guesses from the extension.
  """
  @spec render(String.t() | [String.t()]) :: String.t()
  def render(script_hashes) do
    all = [{"Content-Security-Policy", csp(script_hashes)} | @security]

    sections = [
      {"/*", all},
      {"/*.md", [{"Content-Type", "text/markdown; charset=utf-8"}]},
      {"/llms.txt", [{"Content-Type", "text/plain; charset=utf-8"}]},
      {"/assets/fonts/*", [{"Cache-Control", "public, max-age=31536000, immutable"}]}
    ]

    Enum.map_join(sections, fn {pattern, headers} ->
      pattern <> "\n" <> Enum.map_join(headers, fn {name, value} -> "  #{name}: #{value}\n" end)
    end)
  end

  @doc """
  Parses a `_headers` file into rules. A line that starts at column 0 is a path
  pattern; the indented `Name: value` lines below it are its headers.
  """
  @spec parse(String.t()) :: [rule()]
  def parse(text) do
    text
    |> String.split("\n")
    |> Enum.reduce([], &parse_line/2)
    |> Enum.reverse()
    |> Enum.map(fn %{headers: headers} = rule -> %{rule | headers: Enum.reverse(headers)} end)
  end

  defp parse_line(line, acc) do
    cond do
      String.trim(line) == "" or String.starts_with?(String.trim_leading(line), "#") ->
        acc

      String.starts_with?(line, [" ", "\t"]) ->
        add_header(String.trim(line), acc)

      true ->
        [%{pattern: String.trim(line), headers: []} | acc]
    end
  end

  defp add_header(line, [rule | rest]) do
    case String.split(line, ":", parts: 2) do
      [name, value] ->
        [%{rule | headers: [{String.trim(name), String.trim(value)} | rule.headers]} | rest]

      _ ->
        [rule | rest]
    end
  end

  defp add_header(_line, []), do: []

  @doc """
  Headers that apply to a request path. Every matching rule contributes, in file
  order, and `*` is a splat that matches any run of characters.
  """
  @spec for_path([rule()], String.t()) :: [{String.t(), String.t()}]
  def for_path(rules, path) do
    rules
    |> Enum.filter(&matches?(&1.pattern, path))
    |> Enum.flat_map(& &1.headers)
  end

  @doc false
  @spec matches?(String.t(), String.t()) :: boolean()
  def matches?(pattern, path) do
    regex =
      pattern
      |> String.split("*")
      |> Enum.map_join(".*", &Regex.escape/1)

    Regex.match?(Regex.compile!("\\A" <> regex <> "\\z"), path)
  end
end
