defmodule Site.Entry do
  @moduledoc "An essay, note or project: one row of the log and one page."

  defstruct [
    :type,
    :slug,
    :title,
    :date,
    :description,
    :html,
    :file,
    :commit,
    :tagline,
    :link,
    :status,
    stack: []
  ]

  @type t :: %__MODULE__{
          type: :essay | :note | :project,
          slug: String.t(),
          title: String.t(),
          date: Date.t(),
          description: String.t(),
          html: String.t(),
          file: Path.t(),
          commit: String.t() | nil,
          tagline: String.t() | nil,
          link: String.t() | nil,
          status: String.t() | nil,
          stack: [String.t()]
        }

  @doc "URL path of the entry, with trailing slash."
  @spec path(t()) :: String.t()
  def path(%__MODULE__{type: type, slug: slug}), do: "/#{Site.Config.section(type)}/#{slug}/"
end

defmodule Site.Doc do
  @moduledoc "A single page written in Markdown: home, uses or cv."

  defstruct [:key, :title, :description, :tagline, :html, :file]

  @type t :: %__MODULE__{
          key: :home | :uses | :cv,
          title: String.t(),
          description: String.t(),
          tagline: String.t() | nil,
          html: String.t(),
          file: Path.t()
        }
end

defmodule Site.Content do
  @moduledoc """
  Loads and validates everything under `content/`.

  All problems are collected and raised together as one `Site.Error`, so a bad
  build lists every file that needs fixing instead of just the first.
  """

  alias Site.{Doc, Entry}

  defstruct [:home, :uses, :cv, essays: [], notes: [], projects: []]

  @type t :: %__MODULE__{
          home: Doc.t(),
          uses: Doc.t(),
          cv: Doc.t(),
          essays: [Entry.t()],
          notes: [Entry.t()],
          projects: [Entry.t()]
        }

  @statuses ~w(active wip archived)
  @slug ~r/\A[a-z0-9]+(?:-[a-z0-9]+)*\z/
  @date_prefix ~r/\A\d{4}-\d{2}-\d{2}-/

  @doc """
  Loads the content tree rooted at `dir`.

  Options: `:drafts` (default `false`) keeps entries marked `draft: true`.
  """
  @spec load(Path.t(), keyword()) :: t()
  def load(dir, opts \\ []) do
    drafts? = Keyword.get(opts, :drafts, false)

    docs =
      for {key, file} <- [home: "home.md", uses: "uses.md", cv: "cv.md"],
          do: load_doc(key, Path.join(dir, file))

    entries =
      for type <- Site.Config.types() do
        {type, load_entries(type, dir, drafts?)}
      end

    errors =
      Enum.flat_map(docs, fn {_key, result} -> errors(result) end) ++
        Enum.flat_map(entries, fn {_type, results} -> Enum.flat_map(results, &errors/1) end) ++
        duplicate_errors(entries)

    if errors != [] do
      raise Site.Error, message: format_errors(errors)
    end

    [home, uses, cv] = for {_key, {:ok, doc}} <- docs, do: doc
    by_type = Map.new(entries, fn {type, results} -> {type, sorted(results)} end)

    %__MODULE__{
      home: home,
      uses: uses,
      cv: cv,
      essays: by_type.essay,
      notes: by_type.note,
      projects: by_type.project
    }
  end

  @doc "Every log entry (essays, notes, projects), unsorted."
  @spec entries(t()) :: [Entry.t()]
  def entries(%__MODULE__{} = content), do: content.essays ++ content.notes ++ content.projects

  @doc """
  The slug of a content file: the file name without `.md` and without a leading
  `YYYY-MM-DD-` date prefix.

      iex> Site.Content.slug("content/essays/2026-03-28-threat-modeling.md")
      "threat-modeling"
      iex> Site.Content.slug("rhino.md")
      "rhino"
  """
  @spec slug(Path.t()) :: String.t()
  def slug(file) do
    file |> Path.basename(".md") |> String.replace(@date_prefix, "", global: false)
  end

  # -- single pages ---------------------------------------------------------

  defp load_doc(key, file) do
    result =
      with {:ok, meta, body} <- read(file),
           {:ok, title} <- required_string(meta, "title", file),
           {:ok, description} <- required_string(meta, "description", file),
           {:ok, tagline} <- optional_string(meta, "tagline", file) do
        %{html: html} = Site.Markdown.render(body)

        {:ok,
         %Doc{
           key: key,
           title: title,
           description: description,
           tagline: tagline,
           html: html,
           file: file
         }}
      end

    {key, result}
  end

  # -- log entries ----------------------------------------------------------

  defp load_entries(type, dir, drafts?) do
    dir
    |> Path.join(Site.Config.section(type))
    |> Path.join("*.md")
    |> Path.wildcard()
    |> Enum.sort()
    |> Enum.map(&load_entry(type, &1, drafts?))
    |> Enum.reject(&(&1 == :draft))
  end

  defp load_entry(type, file, drafts?) do
    with {:ok, meta, body} <- read(file),
         {:ok, slug} <- check_slug(file),
         {:ok, title} <- required_string(meta, "title", file),
         {:ok, date} <- required_date(meta, file),
         {:ok, draft?} <- optional_boolean(meta, "draft", file),
         {:ok, description} <- optional_string(meta, "description", file),
         {:ok, extra} <- type_fields(type, meta, file) do
      if draft? and not drafts? do
        :draft
      else
        %{html: html, summary: summary} = Site.Markdown.render(body)

        {:ok,
         struct!(
           Entry,
           Map.merge(extra, %{
             type: type,
             slug: slug,
             title: title,
             date: date,
             description: description || extra[:tagline] || summary,
             html: html,
             file: file,
             commit: Site.Git.last_commit(file)
           })
         )}
      end
    end
  end

  defp type_fields(:project, meta, file) do
    with {:ok, tagline} <- required_string(meta, "tagline", file),
         {:ok, link} <- optional_link(meta, file),
         {:ok, stack} <- optional_stack(meta, file),
         {:ok, status} <- optional_status(meta, file) do
      {:ok, %{tagline: tagline, link: link, stack: stack, status: status}}
    end
  end

  defp type_fields(_type, _meta, _file), do: {:ok, %{}}

  defp check_slug(file) do
    slug = slug(file)

    if Regex.match?(@slug, slug) do
      {:ok, slug}
    else
      {:error,
       [problem(file, "slug #{inspect(slug)} must be lowercase letters, digits and hyphens")]}
    end
  end

  defp sorted(results) do
    for({:ok, entry} <- results, do: entry) |> Enum.sort_by(& &1.slug)
  end

  defp duplicate_errors(entries) do
    for {type, results} <- entries,
        {slug, [_, _ | _] = group} <- Enum.group_by(for({:ok, e} <- results, do: e), & &1.slug),
        do:
          "duplicate #{type} slug #{inspect(slug)}: " <>
            Enum.map_join(Enum.sort_by(group, & &1.file), ", ", & &1.file)
  end

  # -- field validation -----------------------------------------------------

  defp read(file) do
    case File.read(file) do
      {:ok, source} ->
        case Site.Frontmatter.parse(source) do
          {:ok, meta, body} -> {:ok, meta, body}
          {:error, message} -> {:error, [problem(file, message)]}
        end

      {:error, reason} ->
        {:error, [problem(file, "cannot read file (#{:file.format_error(reason)})")]}
    end
  end

  defp required_string(meta, key, file) do
    case Map.fetch(meta, key) do
      {:ok, value} when is_binary(value) ->
        if String.trim(value) == "" do
          {:error, [problem(file, "`#{key}` is empty")]}
        else
          {:ok, String.trim(value)}
        end

      {:ok, value} when not is_nil(value) ->
        {:error, [problem(file, "`#{key}` must be a string (quote it): got #{inspect(value)}")]}

      _ ->
        {:error, [problem(file, "missing required field `#{key}`")]}
    end
  end

  defp optional_string(meta, key, file) do
    case Map.get(meta, key) do
      nil -> {:ok, nil}
      _ -> required_string(meta, key, file)
    end
  end

  defp required_date(meta, file) do
    with {:ok, string} <- required_string(meta, "date", file),
         {:ok, date} <- Date.from_iso8601(string) do
      {:ok, date}
    else
      {:error, [_ | _] = errors} ->
        {:error, errors}

      {:error, _reason} ->
        {:error,
         [problem(file, "`date` must be an ISO date (YYYY-MM-DD): got #{inspect(meta["date"])}")]}
    end
  end

  defp optional_boolean(meta, key, file) do
    case Map.get(meta, key) do
      nil -> {:ok, false}
      value when is_boolean(value) -> {:ok, value}
      value -> {:error, [problem(file, "`#{key}` must be true or false: got #{inspect(value)}")]}
    end
  end

  defp optional_link(meta, file) do
    with {:ok, link} <- optional_string(meta, "link", file) do
      if is_nil(link) or Regex.match?(~r{\Ahttps?://\S+\z}, link) do
        {:ok, link}
      else
        {:error, [problem(file, "`link` must be an http(s) URL: got #{inspect(link)}")]}
      end
    end
  end

  defp optional_stack(meta, file) do
    case Map.get(meta, "stack") do
      nil ->
        {:ok, []}

      list when is_list(list) ->
        if Enum.all?(list, &(is_binary(&1) or is_number(&1))) do
          {:ok, Enum.map(list, &to_string/1)}
        else
          {:error, [problem(file, "`stack` must be a list of names, e.g. [Go, YAML]")]}
        end

      other ->
        {:error,
         [
           problem(
             file,
             "`stack` must be a list of names, e.g. [Go, YAML]: got #{inspect(other)}"
           )
         ]}
    end
  end

  defp optional_status(meta, file) do
    case Map.get(meta, "status") do
      nil ->
        {:ok, nil}

      status when status in @statuses ->
        {:ok, status}

      other ->
        {:error,
         [
           problem(
             file,
             "`status` must be one of #{Enum.join(@statuses, ", ")}: got #{inspect(other)}"
           )
         ]}
    end
  end

  # -- error plumbing -------------------------------------------------------

  defp problem(file, message), do: "#{file}: #{message}"

  defp errors({:error, messages}), do: messages
  defp errors(_ok_or_draft), do: []

  defp format_errors(errors) do
    "content has #{length(errors)} problem(s):\n" <> Enum.map_join(errors, "\n", &("  - " <> &1))
  end
end
