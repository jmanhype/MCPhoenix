defmodule MCPheonixWeb.PageController do
  @moduledoc """
  Controller for basic page rendering.
  """
  use Phoenix.Controller, namespace: MCPheonixWeb

  def home(conn, _params) do
    # In a real application, this would render a template
    # For now, just return a simple text response
    text(conn, "MCPheonix MCP Server")
  end
end 