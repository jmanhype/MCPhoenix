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
    plug Plug.Parsers, parsers: [:json], json_decoder: Jason
  end

  pipeline :sse do
    # This pipeline is for Server-Sent Events and does not parse JSON
    # or strictly check accept headers for JSON.
    # Add any other necessary plugs for SSE here if needed.
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
    # SSE stream uses its own pipeline
    pipe_through :sse
    get "/stream", MCPController, :stream # SSE stream for notifications

    # RPC endpoint uses the :api pipeline
    pipe_through :api
    post "/", MCPController, :rpc      # JSON-RPC requests, changed from /rpc
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

  # Enable LiveDashboard in development
  if Mix.env() == :dev do
    scope "/dev" do
      pipe_through :browser
      forward "/mailbox", Plug.Swoosh.MailboxPreview
    end
  end
end 