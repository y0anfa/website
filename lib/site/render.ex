defmodule Site.Render do
  @moduledoc """
  Turns loaded content into pages: a sorted list of `{relative file path, html}`.

  Every page goes through the same layout. The URL map is in SPEC.md section 4.
  """

  alias Site.{Content, Entry, Log, Templates, View}

  @type context :: %{
          required(:head_js) => String.t(),
          required(:beacon_token) => String.t() | nil,
          required(:build) => %{label: String.t(), href: String.t() | nil}
        }

  @theme_script %{src: "/assets/js/theme.js", module: false}

  @doc "Renders every page of the site."
  @spec pages(Content.t(), context()) :: [{Path.t(), String.t()}]
  def pages(%Content{} = content, context) do
    rows = content |> Content.entries() |> Log.rows()

    [home(content, rows, context), not_found(context)]
    |> Kernel.++(lists(content, context))
    |> Kernel.++(entry_pages(content, context))
    |> Kernel.++(doc_pages(content, context))
    |> Enum.sort_by(&elem(&1, 0))
  end

  @doc "Output file for a URL path: `/essays/` becomes `essays/index.html`."
  @spec file_for(String.t()) :: Path.t()
  def file_for("/"), do: "index.html"
  def file_for("/" <> path), do: Path.join(path, "index.html")

  # -- pages ----------------------------------------------------------------

  defp home(content, rows, context) do
    inner = Templates.home(%{doc: content.home, rows: rows})

    page(context, "/", inner,
      title: Site.Config.home_title(),
      description: content.home.description,
      page_key: "home",
      scripts: [@theme_script, %{src: "/assets/js/field.js", module: true}]
    )
  end

  defp not_found(context) do
    inner = Templates.not_found(%{fallback: "unknown"})

    html =
      layout(context, inner,
        title: "Not found — #{Site.Config.name()}",
        description: "This page does not exist.",
        url: nil,
        page_key: "404",
        scripts: [@theme_script, %{src: "/assets/js/404.js", module: false}]
      )

    {"404.html", html}
  end

  defp lists(content, context) do
    for {section, entries} <- [
          {"essays", content.essays},
          {"notes", content.notes},
          {"projects", content.projects}
        ] do
      inner =
        Templates.list(%{
          section: section,
          intro: Site.Config.list_intro(section),
          rows: Log.rows(entries)
        })

      page(context, "/#{section}/", inner,
        title: "#{section} — #{Site.Config.name()}",
        description: Site.Config.list_intro(section),
        current: section,
        exact?: true,
        page_key: section
      )
    end
  end

  defp entry_pages(content, context) do
    for %Entry{} = entry <- Content.entries(content) do
      section = Site.Config.section(entry.type)

      inner =
        case entry.type do
          :project ->
            Templates.project(%{entry: entry, section: section, meta: View.project_meta(entry)})

          _ ->
            Templates.article(%{entry: entry, section: section, meta: View.article_meta(entry)})
        end

      page(context, Entry.path(entry), inner,
        title: "#{entry.title} — #{Site.Config.name()}",
        description: entry.description,
        og_type: if(entry.type == :project, do: "website", else: "article"),
        current: section,
        page_key: "#{entry.type}"
      )
    end
  end

  defp doc_pages(content, context) do
    for doc <- [content.uses, content.cv] do
      section = Atom.to_string(doc.key)
      inner = Templates.page(%{doc: doc})

      page(context, "/#{section}/", inner,
        title: "#{doc.title} — #{Site.Config.name()}",
        description: doc.description,
        current: section,
        exact?: true,
        page_key: section
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
      og_type: Keyword.get(opts, :og_type, "website"),
      page_key: Keyword.fetch!(opts, :page_key),
      nav: View.nav(opts[:current], Keyword.get(opts, :exact?, false)),
      scripts: Keyword.get(opts, :scripts, [@theme_script]),
      head_js: context.head_js,
      beacon_token: context.beacon_token,
      build: context.build,
      content: inner
    })
  end
end
