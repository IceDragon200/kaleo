defmodule Kaleo.Config do
  def use_cluster? do
    Application.get_env(:kaleo, :use_cluster, false)
  end

  def node_name do
    Application.fetch_env!(:kaleo, :node_name)
  end

  def runtime_config_path do
    if Application.get_env(:kaleo, :use_home_runtime_config, true) do
      home_path = System.user_home!()
      config_path = Path.join(home_path, ".config/kaleo/config.kdl")
      config_path
    else
      case Application.fetch_env(:kaleo, :runtime_config_path) do
        {:ok, path} ->
          path

        :error ->
          nil
      end
    end
  end
end
