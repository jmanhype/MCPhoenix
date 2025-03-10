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
    plug :protect_from_forgery
    plug :put_secure_browser_headers
  end
  
  # Custom pipeline for MCP RPC that skips parsers
  pipeline :raw_json do
    plug :accepts, ["json"]
  end

  # MCP-specific routes
  scope "/mcp", MCPheonixWeb do
    # SSE stream endpoint for server-to-client notifications
    get "/stream", MCPController, :stream, pipe_through: [:api]
    
    # JSON-RPC endpoint for client-to-server requests - with minimal parsing
    post "/rpc", MCPController, :rpc, pipe_through: [:raw_json]
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
  end
end 