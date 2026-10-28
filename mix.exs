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
      {:yaml_elixir, "~> 2.12"},
      {:bandit, "~> 1.14", only: :dev},
      {:plug, "~> 1.20", only: :dev}
    ]
  end
end
