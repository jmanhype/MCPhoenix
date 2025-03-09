defmodule MCPheonixWeb.Router do
  @moduledoc """
  Router for the MCPheonix web application.
  
  Defines routes for MCP communication, including SSE streams and JSON-RPC endpoints.
  """
  use Phoenix.Router
  import Plug.Conn
  import Phoenix.Controller

  pipeline :api do
    plug :accepts, ["json"]
  end

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_live_flash
    plug :put_root_layout, html: {MCPheonixWeb.Layouts, :root}
    plug :protect_from_forgery
    plug :put_secure_browser_headers
  end

  # MCP-specific routes
  scope "/mcp", MCPheonixWeb do
    pipe_through :api

    # SSE stream endpoint for server-to-client notifications
    get "/stream", MCPController, :stream
    
    # JSON-RPC endpoint for client-to-server requests
    post "/rpc", MCPController, :rpc
  end

  # Other API routes
  scope "/api", MCPheonixWeb do
    pipe_through :api
    
    # Add API endpoints here
  end

  # Browser routes
  scope "/", MCPheonixWeb do
    pipe_through :browser
    
    get "/", PageController, :home
    live_dashboard "/dashboard", metrics: MCPheonixWeb.Telemetry
  end

  # Enable LiveDashboard in development
  if Application.compile_env(:mcpheonix, :dev_routes) do
    import Phoenix.LiveDashboard.Router

    scope "/dev" do
      pipe_through :browser
      live_dashboard "/dashboard", metrics: MCPheonixWeb.Telemetry
    end
  end
end 