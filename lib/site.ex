defmodule Site do
  @moduledoc """
  Hand-rolled static site generator for yoanfaure.com.

  The pipeline lives in `Site.Build`: load and validate `content/` (`Site.Content`),
  render the EEx templates (`Site.Render`, `Site.Templates`), copy `assets/`, and
  write `_headers`, `robots.txt` and `404.html`. See SPEC.md for the contract.
  """

  @doc "Builds the site. See `Site.Build.run/1` for the options."
  defdelegate build(opts \\ []), to: Site.Build, as: :run
end
