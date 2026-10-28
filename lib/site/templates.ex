defmodule Site.Templates do
  @moduledoc """
  The EEx templates in `templates/`, compiled into functions at build time.

  Each function takes an `assigns` map and returns a binary. EEx does not
  escape, so every template routes interpolated values through
  `Site.HTML.escape/1`; only rendered Markdown, the inline head script and
  partials go through `Site.HTML.raw/1` (or are called as partials). The
  template test in `test/site/templates_test.exs` enforces that rule.
  """

  require EEx
  import Site.HTML, only: [escape: 1, raw: 1]

  @dir Path.expand("../../templates", __DIR__)

  @templates [
    layout: "layout.html.eex",
    home: "home.html.eex",
    article: "article.html.eex",
    project: "project.html.eex",
    not_found: "404.html.eex",
    footer: "_footer.html.eex",
    log: "_log.html.eex",
    meta: "_meta.html.eex"
  ]

  # Nothing to interpolate: these take no assigns.
  @static [header: "_header.html.eex"]

  @doc "The template files, as `{function name, absolute path}`."
  def files, do: for({name, file} <- @templates ++ @static, do: {name, Path.join(@dir, file)})

  for {name, file} <- @templates do
    EEx.function_from_file(:def, name, Path.join(@dir, file), [:assigns], trim: true)
  end

  for {name, file} <- @static do
    EEx.function_from_file(:def, name, Path.join(@dir, file), [], trim: true)
  end
end
