defmodule Kaleo.Core.MixProject do
  use Mix.Project

  def project do
    [
      app: :kaleo_core,
      version: "0.1.0",
      build_path: "../../_build",
      config_path: "../../config/config.exs",
      deps_path: "../../deps",
      lockfile: "../../mix.lock",
      elixir: "~> 1.17",
      start_permanent: Mix.env() == :prod,
      deps: deps()
    ]
  end

  def application do
    [
      extra_applications: [:logger]
    ]
  end

  defp deps do
    [
      {:ecto, "~> 3.0"},
      {:jason, "~> 1.2"},
      {:loxe, git: "https://github.com/polyfox/loxe"},
    ]
  end
end
