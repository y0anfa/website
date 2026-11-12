defmodule Site.SecurityTxt do
  @moduledoc """
  `/.well-known/security.txt` (RFC 9116): where to report a problem with the site.

  The expiry is a constant in `Site.Config`, not the build date, so the file is
  part of the deterministic build. A test fails once it has passed.
  """

  @path ".well-known/security.txt"

  @doc "The output file, relative to the build directory."
  @spec path() :: Path.t()
  def path, do: @path

  @doc "Renders the file: one comment, then the fields."
  @spec render() :: String.t()
  def render do
    """
    # This site is a folder of static files. If you still found a way in, tell me.
    Contact: #{Site.Config.linkedin()}
    Expires: #{DateTime.to_iso8601(Site.Config.security_expires())}
    Canonical: #{Site.Config.absolute("/" <> @path)}
    """
  end
end
