defmodule Site.Speculation do
  @moduledoc """
  The Speculation Rules that make navigation feel instant.

  Browsers that support them prerender a same-origin page link when the pointer
  or focus gives a moderate hint that it will be opened. The rules skip what is
  not a page: the Markdown twins, `llms.txt` and everything under `/assets/`,
  plus any link marked `rel~=nofollow`.

  The rules are one fixed inline `<script type="speculationrules">` in every
  page. Because the CSP allows no other inline script, the build puts its sha256
  in `script-src` next to the one of `head.js` (see `Site.Headers`). The text is
  a constant, so the same rules always give the same hash.
  """

  @rules ~s({"prerender":[{"where":{"and":[) <>
           ~s({"href_matches":"/*"},) <>
           ~s({"not":{"href_matches":"/*.md"}},) <>
           ~s({"not":{"href_matches":"/llms.txt"}},) <>
           ~s({"not":{"href_matches":"/assets/*"}},) <>
           ~s({"not":{"selector_matches":"[rel~=nofollow]"}}) <>
           ~s(]},"eagerness":"moderate"}]})

  @doc "The JSON text of the rules, exactly as it sits between the script tags."
  @spec rules() :: String.t()
  def rules, do: @rules

  @doc "The `sha256-…` CSP source expression for the rules."
  @spec hash() :: String.t()
  def hash, do: Site.Headers.script_hash(@rules)
end
