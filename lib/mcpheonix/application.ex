defmodule MCPheonix.Application do
  @moduledoc """
  The MCPheonix Application Service.
  
  This is the entry point for the MCPheonix application. It starts the
  supervision tree and defines workers for handling events and MCP integration.
  """
  use Application

  @impl true
  def start(_type, _args) do
    children = [
      # Start the Telemetry supervisor
      MCPheonixWeb.Telemetry,
      # Start the PubSub system
      {Phoenix.PubSub, name: MCPheonix.PubSub},
      # Start Finch for HTTP requests
      {Finch, name: MCPheonix.Finch},
      # Start MCP server supervisor
      MCPheonix.MCP.Supervisor,
      # Start the event broker
      MCPheonix.Events.Broker,
      # Start the Endpoint (http/https)
      MCPheonixWeb.Endpoint
    ]

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: MCPheonix.Supervisor]
    Supervisor.start_link(children, opts)
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  @impl true
  def config_change(changed, _new, removed) do
    MCPheonixWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end 