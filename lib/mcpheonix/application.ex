defmodule MCPheonix.Application do
  @moduledoc """
  The MCPheonix Application Service.
  
  This is the entry point for the MCPheonix application. It starts the
  supervision tree and defines workers for handling events and MCP integration.
  """
  use Application
  require Logger
  alias MCPheonix.Resources.{User, Message}

  @impl true
  def start(_type, _args) do
    children = [
      # Start the Telemetry supervisor
      MCPheonixWeb.Telemetry,
      # Start the PubSub system
      {Phoenix.PubSub, name: MCPheonix.PubSub},
      # Start Finch for HTTP requests
      {Finch, name: MCPheonix.Finch},
      # Start the event broker
      MCPheonix.Events.Broker,
      # ResourceInitializer to initialize ETS tables and sample data
      {Task, &initialize_resources/0},
      # Start the Resource Registry
      MCPheonix.Resources.Registry,
      # Start the MCP Simple Server - This is the server that actually handles requests
      MCPheonix.MCP.SimpleServer,
      # Start the MCP Server Manager
      MCPheonix.MCP.ServerManager,
      # Start the Connection Registry for MCP clients
      {Registry, keys: :unique, name: MCPheonix.MCP.ConnectionRegistry},
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
  
  # Initialize resources and create sample data
  defp initialize_resources do
    # Give the PubSub system time to start
    Process.sleep(100)
  
    Logger.info("Initializing resources")
    
    # Initialize ETS tables
    User.init()
    Message.init()
    
    # Create sample users
    {:ok, user1} = User.register(%{
      username: "john_doe",
      email: "john@example.com",
      full_name: "John Doe",
      password: "password123"
    })
    
    {:ok, user2} = User.register(%{
      username: "jane_smith",
      email: "jane@example.com",
      full_name: "Jane Smith",
      password: "password456"
    })
    
    # Create sample messages
    Message.create(user1.id, "Hello, world! This is my first message.")
    Message.create(user2.id, "Hi everyone! Nice to meet you all.")
    Message.create(user1.id, "The weather is great today!")
    
    Logger.info("Sample data initialized")
    
    :ok
  end
end 