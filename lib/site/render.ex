defmodule Site.Render do
  @moduledoc """
  Turns loaded content into pages: a sorted list of `{relative file path, html}`.

  Every page goes through the same layout. The URL map is in SPEC.md section 4.
  """

  alias Site.{Content, Entry, Log, Templates, View}

  @type context :: %{required(:head_js) => String.t()}

  # Plain deferred scripts loaded on every page, after the render-blocking site.js.
  @scripts ["/assets/js/favicon.js"]

  @doc "Renders every page of the site."
  @spec pages(Content.t(), context()) :: [{Path.t(), String.t()}]
  def pages(%Content{} = content, context) do
    rows = content |> Content.entries() |> Log.rows()

    [home(content, rows, context), not_found(context)]
    |> Kernel.++(entry_pages(content, context))
    |> Enum.sort_by(&elem(&1, 0))
  end

  @doc "Output file for a URL path: `/rhino/` becomes `rhino/index.html`."
  @spec file_for(String.t()) :: Path.t()
  def file_for("/"), do: "index.html"
  def file_for("/" <> path), do: Path.join(path, "index.html")

  # -- pages ----------------------------------------------------------------

  defp home(content, rows, context) do
    inner =
      Templates.home(%{
        name_lines: View.name_lines(content.home.title),
        role: Site.Config.role(),
        years: Log.years(rows)
      })

    page(context, "/", inner,
      title: Site.Config.home_title(),
      description: content.home.description,
      og_image: Site.OG.url(Site.OG.home_key()),
      page_key: "home",
      skip: %{href: "#feed", label: "Skip to the entries"}
    )
  end

  defp not_found(context) do
    inner = Templates.not_found(%{fallback: "this address"})

    html =
      layout(context, inner,
        title: "Not found — #{Site.Config.name()}",
        description: "This page does not exist.",
        url: nil,
        page_key: "404",
        scripts: @scripts ++ ["/assets/js/404.js"]
      )

    {"404.html", html}
  end

  defp entry_pages(content, context) do
    for %Entry{} = entry <- Content.entries(content) do
      links = View.entry_links(entry)
      meta = View.article_meta(entry)

      inner =
        case entry.type do
          :project ->
            Templates.project(%{
              entry: entry,
              meta: meta,
              facts: View.project_facts(entry),
              links: links
            })

          _ ->
            Templates.article(%{entry: entry, meta: meta, links: links})
        end

      page(context, Entry.path(entry), inner,
        title: "#{entry.title} — #{Site.Config.name()}",
        description: entry.description,
        markdown: links.markdown,
        og_image: Site.OG.url(entry.slug),
        og_type: if(entry.type == :project, do: "website", else: "article"),
        page_key: "#{entry.type}"
      )
    end
  end

  # -- layout ---------------------------------------------------------------

  defp page(context, path, inner, opts) do
    html = layout(context, inner, Keyword.put_new(opts, :url, Site.Config.absolute(path)))
    {file_for(path), html}
  end

  defp layout(context, inner, opts) do
    Templates.layout(%{
      title: Keyword.fetch!(opts, :title),
      description: Keyword.fetch!(opts, :description),
      url: Keyword.fetch!(opts, :url),
      og_image: Keyword.get(opts, :og_image),
      og_type: Keyword.get(opts, :og_type, "website"),
      page_key: Keyword.fetch!(opts, :page_key),
      skip: Keyword.get(opts, :skip, %{href: "#main", label: "Skip to the content"}),
      scripts: Keyword.get(opts, :scripts, @scripts),
      markdown: Keyword.get(opts, :markdown),
      head_js: context.head_js,
      speculation: Site.Speculation.rules(),
      content: inner
    })
  end
end
