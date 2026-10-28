defmodule Site.TestHelpers do
  @moduledoc false

  @fixtures Path.expand("fixtures/content", __DIR__)

  @doc "The checked-in fixture content directory."
  def fixtures, do: @fixtures

  @doc "A fresh temporary directory, removed when the test exits."
  def tmp_dir(label \\ "site-test") do
    dir = Path.join(System.tmp_dir!(), "#{label}-#{System.unique_integer([:positive])}")
    File.mkdir_p!(dir)
    ExUnit.Callbacks.on_exit(fn -> File.rm_rf!(dir) end)
    dir
  end

  @doc """
  A copy of the fixture content in a temporary directory. Outside any git
  repository, so no file has a commit.
  """
  def fixture_copy do
    dir = Path.join(tmp_dir("site-content"), "content")
    File.cp_r!(@fixtures, dir)
    dir
  end

  @doc "Writes a content tree: `%{\"essays/a.md\" => source, ...}`, returns the directory."
  def write_content(files) do
    dir = Path.join(tmp_dir("site-content"), "content")

    for {path, source} <- files do
      File.mkdir_p!(Path.dirname(Path.join(dir, path)))
      File.write!(Path.join(dir, path), source)
    end

    dir
  end

  @doc "Minimal valid content with extra files merged in."
  def minimal_content(extra \\ %{}) do
    home = "---\ntitle: t\ndescription: d\n---\nbody\n"

    write_content(Map.merge(%{"home.md" => home}, extra))
  end

  @doc "Reads every file under `dir` into `%{relative_path => content}`."
  def read_tree(dir) do
    for rel <- Site.Build.files(dir), into: %{}, do: {rel, File.read!(Path.join(dir, rel))}
  end

  @doc "Builds the fixture content (copied outside git) into a temp dir."
  def build_fixtures(opts \\ []) do
    out = Path.join(tmp_dir("site-out"), "dist")
    content = Keyword.get_lazy(opts, :content, &fixture_copy/0)
    opts = opts |> Keyword.delete(:content) |> Keyword.put_new(:beacon_token, nil)
    Site.Build.run([content: content, out: out] ++ opts)
    out
  end
end

ExUnit.start()
