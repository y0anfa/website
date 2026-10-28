defmodule Site.Redirects do
  @moduledoc """
  The `_redirects` file (Cloudflare Workers static assets format) that sends the
  old Hugo URLs to the flat URLs of this site.

  The rules live in `Site.Config.redirects/0`. The file has no timestamps and a
  fixed order, so it is part of the deterministic build. The dev server does not
  apply it.
  """

  @doc "Renders `_redirects`: one `from to status` rule per line."
  @spec render() :: String.t()
  def render do
    Enum.map_join(Site.Config.redirects(), fn {from, to, status} ->
      "#{from} #{to} #{status}\n"
    end)
  end
end
