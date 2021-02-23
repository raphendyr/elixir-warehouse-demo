defmodule Warehouse.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  def start(_type, _args) do
    children = [
      # Start the Telemetry supervisor
      WarehouseWeb.Telemetry,
      # Start the PubSub system
      {Phoenix.PubSub, name: Warehouse.PubSub},
      # Start the Endpoint (http/https)
      WarehouseWeb.Endpoint,
      # Start a worker by calling: Warehouse.Worker.start_link(arg)
      # {Warehouse.Worker, arg}
      {ProductCache.Cache, []},
    ]

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: Warehouse.Supervisor]
    Supervisor.start_link(children, opts)
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  def config_change(changed, _new, removed) do
    WarehouseWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
