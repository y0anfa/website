defmodule Site.MixProject do
  use Mix.Project

  def project do
    [
      app: :site,
      version: "2.0.0",
      elixir: "~> 1.20",
      start_permanent: false,
      deps: deps()
    ]
  end

  def application do
    [extra_applications: [:logger, :crypto]]
  end

  defp deps do
    [
      {:mdex, "~> 0.14"},
      # one parser per language a post may highlight (SPEC §5); `comment` is injected by others
      {:lumis_wasm_bash, "~> 0.26"},
      {:lumis_wasm_comment, "~> 0.26"},
      {:lumis_wasm_diff, "~> 0.26"},
      {:lumis_wasm_dockerfile, "~> 0.26"},
      {:lumis_wasm_elixir, "~> 0.26"},
      {:lumis_wasm_go, "~> 0.26"},
      {:lumis_wasm_hcl, "~> 0.26"},
      {:lumis_wasm_javascript, "~> 0.26"},
      {:lumis_wasm_json, "~> 0.26"},
      {:lumis_wasm_python, "~> 0.26"},
      {:lumis_wasm_rust, "~> 0.26"},
      {:lumis_wasm_sql, "~> 0.26"},
      {:lumis_wasm_toml, "~> 0.26"},
      {:lumis_wasm_typescript, "~> 0.26"},
      {:lumis_wasm_yaml, "~> 0.26"},
      {:yaml_elixir, "~> 2.12"},
      {:resvg, "~> 0.6.0"},
      {:bandit, "~> 1.14", only: :dev},
      {:plug, "~> 1.20", only: :dev}
    ]
  end
end
