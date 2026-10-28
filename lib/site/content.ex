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

  @doc "URL path of the entry, flat and with a trailing slash: `/rhino/`."
  @spec path(t()) :: String.t()
  def path(%__MODULE__{slug: slug}), do: "/#{slug}/"
end

defmodule Site.Doc do
  @moduledoc "A single page written in Markdown: the home intro."

  defstruct [:title, :description, :tagline, :html, :file]

  @type t :: %__MODULE__{
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

  The content directory (`essays/`, `notes/`, `projects/`) sets an entry's type,
  but every entry lives at `/<slug>/`, so slugs are unique across all types and
  may not be one of `Site.Config.reserved_slugs/0`.

  All problems are collected and raised together as one `Site.Error`, so a bad
  build lists every file that needs fixing instead of just the first.
  """

  alias Site.{Doc, Entry}

  defstruct [:home, essays: [], notes: [], projects: []]

  @type t :: %__MODULE__{
          home: Doc.t(),
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

    home_result = load_home(Path.join(dir, "home.md"))

    entries =
      for type <- Site.Config.types() do
        {type, load_entries(type, dir, drafts?)}
      end

    errors =
      errors(home_result) ++
        Enum.flat_map(entries, fn {_type, results} -> Enum.flat_map(results, &errors/1) end) ++
        duplicate_errors(entries)

    if errors != [] do
      raise Site.Error, message: format_errors(errors)
    end

    {:ok, home} = home_result
    by_type = Map.new(entries, fn {type, results} -> {type, sorted(results)} end)

    %__MODULE__{
      home: home,
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

  # -- home -----------------------------------------------------------------

  defp load_home(file) do
    with {:ok, meta, body} <- read(file),
         {:ok, title} <- required_string(meta, "title", file),
         {:ok, description} <- required_string(meta, "description", file),
         {:ok, tagline} <- optional_string(meta, "tagline", file) do
      %{html: html} = Site.Markdown.render(body)

      {:ok,
       %Doc{
         title: title,
         description: description,
         tagline: tagline,
         html: html,
         file: file
       }}
    end
  end

  # -- log entries ----------------------------------------------------------

  defp load_entries(type, dir, drafts?) do
    dir
    |> Path.join(Site.Config.dir(type))
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

    cond do
      slug in Site.Config.reserved_slugs() ->
        {:error,
         [
           problem(
             file,
             "slug #{inspect(slug)} is reserved: /#{slug}/ would collide with a site path"
           )
         ]}

      Regex.match?(@slug, slug) ->
        {:ok, slug}

      true ->
        {:error,
         [problem(file, "slug #{inspect(slug)} must be lowercase letters, digits and hyphens")]}
    end
  end

  defp sorted(results) do
    for({:ok, entry} <- results, do: entry) |> Enum.sort_by(& &1.slug)
  end

  # Every entry lives at /<slug>/, whatever its type, so a slug may be used once.
  defp duplicate_errors(entries) do
    for {_type, results} <- entries, {:ok, entry} <- results do
      entry
    end
    |> Enum.group_by(& &1.slug)
    |> Enum.sort()
    |> Enum.flat_map(fn
      {slug, [_, _ | _] = group} ->
        [
          "duplicate slug #{inspect(slug)}: " <>
            Enum.map_join(Enum.sort_by(group, & &1.file), ", ", & &1.file)
        ]

      _unique ->
        []
    end)
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
