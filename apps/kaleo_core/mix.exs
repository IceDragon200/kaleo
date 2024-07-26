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
      {:kuddle, "~> 0.2.1"},
      {:kuddle_config, "~> 0.3.0"},
      {:timex, "~> 3.6"},
      {:loxe, git: "https://github.com/polyfox/loxe"},
      # {:artemis_ql, git: "https://github.com/Tychron/artemis_ql", branch: "0.7.0"},
      {:unit_fmt, git: "https://github.com/IceDragon200/unit_fmt.git"},
    ]
  end
end
