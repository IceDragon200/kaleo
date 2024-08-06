defmodule Kaleo.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      Kaleo.ConfigHost,
      # Kaleo.Repo,
      {DNSCluster, query: Application.get_env(:kaleo, :dns_cluster_query) || :ignore},
      {Phoenix.PubSub, name: Kaleo.PubSub},
      # Start the Finch HTTP client for sending emails
      # {Finch, name: Kaleo.Finch}
      # Start a worker by calling: Kaleo.Worker.start_link(arg)
      Kaleo.ItemProcessorHost,
      Kaleo.Scheduler,
    ]

    Supervisor.start_link(children, strategy: :one_for_one, name: Kaleo.Supervisor)
  end
end
