defmodule Mix.Tasks.Site.Serve do
  @shortdoc "Builds and serves the site locally, rebuilding on change"

  @moduledoc """
  Builds the site, serves `dist/` with Bandit, and rebuilds when `content/`,
  `templates/`, `assets/` or `lib/` change (polled every second).

      mix site.serve [--port 4000] [--drafts] [--content DIR] [--out DIR]

  Responses carry the headers from `dist/_headers`, including the Content
  Security Policy, so violations show up locally exactly as in production.
  Unknown paths get `404.html` with status 404.

  Only available in the `:dev` environment, where Bandit and Plug are installed.
  """

  use Mix.Task

  @switches [port: :integer, drafts: :boolean, content: :string, out: :string]

  @impl Mix.Task
  def run(args) do
    Mix.Task.run("app.start")

    {opts, rest} = OptionParser.parse!(args, strict: @switches)
    if rest != [], do: Mix.raise("unexpected arguments: #{Enum.join(rest, " ")}")

    # Looked up at run time: the module only exists where Bandit and Plug do.
    dev_server = Module.concat(Site, DevServer)

    if Code.ensure_loaded?(dev_server) do
      dev_server.run(opts)
    else
      Mix.raise("mix site.serve needs the :dev environment (bandit and plug are dev-only deps)")
    end
  end
end
