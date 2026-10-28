defmodule Mix.Tasks.Site.Build do
  @shortdoc "Builds the site into dist/"

  @moduledoc """
  Builds the site.

      mix site.build [--drafts] [--content DIR] [--out DIR]

  ## Options

    * `--drafts` - include entries marked `draft: true`
    * `--content DIR` - content directory (default `content`)
    * `--out DIR` - output directory, deleted first (default `dist`)

  Set `CF_BEACON_TOKEN` to include the Cloudflare Web Analytics beacon and its
  Content Security Policy entries.
  """

  use Mix.Task

  @switches [drafts: :boolean, content: :string, out: :string]

  @impl Mix.Task
  def run(args) do
    Mix.Task.run("app.start")

    {opts, rest} = OptionParser.parse!(args, strict: @switches)
    if rest != [], do: Mix.raise("unexpected arguments: #{Enum.join(rest, " ")}")

    %{out: out, files: files} = Site.Build.run(opts)
    Mix.shell().info("site.build: wrote #{files} files to #{out}")
  rescue
    error in Site.Error -> Mix.raise(Exception.message(error))
  end
end
