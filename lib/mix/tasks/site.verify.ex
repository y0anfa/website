defmodule Mix.Tasks.Site.Verify do
  @shortdoc "Checks that the build is deterministic"

  @moduledoc """
  Builds the site twice into temporary directories and compares a SHA-256 over
  every file path and content. Prints the tree hash, and fails if the two builds
  differ.

      mix site.verify [--drafts] [--content DIR]
  """

  use Mix.Task

  @switches [drafts: :boolean, content: :string]

  @impl Mix.Task
  def run(args) do
    Mix.Task.run("app.start")

    {opts, rest} = OptionParser.parse!(args, strict: @switches)
    if rest != [], do: Mix.raise("unexpected arguments: #{Enum.join(rest, " ")}")

    base = Path.join(System.tmp_dir!(), "site-verify-#{System.unique_integer([:positive])}")
    [first, second] = Enum.map(["a", "b"], &Path.join(base, &1))

    try do
      hashes =
        for out <- [first, second] do
          Site.Build.run([out: out] ++ opts)
          Site.Build.tree_hash(out)
        end

      case hashes do
        [same, same] ->
          Mix.shell().info("site.verify: deterministic, tree hash #{same}")

        [one, two] ->
          Mix.raise("""
          site.verify: the build is not deterministic
            first build:  #{one}
            second build: #{two}
          """)
      end
    rescue
      error in Site.Error -> Mix.raise(Exception.message(error))
    after
      File.rm_rf!(base)
    end
  end
end
