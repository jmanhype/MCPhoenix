defmodule MCPheonix.MCP.Supervisor do
  @moduledoc """
  Supervisor for MCP-related processes.
  
  This supervisor manages all processes related to Model Context Protocol (MCP)
  integration, including the MCP server, client connections, and feature modules.
  """
  use Supervisor

  def start_link(init_arg) do
    Supervisor.start_link(__MODULE__, init_arg, name: __MODULE__)
  end

  @impl true
  def init(_init_arg) do
    children = [
      # MCP Server process
      MCPheonix.MCP.Server,
      
      # Registry for client connections
      {Registry, keys: :unique, name: MCPheonix.MCP.ConnectionRegistry},
      
      # Dynamic supervisor for client connections
      {DynamicSupervisor, 
        strategy: :one_for_one, 
        name: MCPheonix.MCP.ConnectionSupervisor
      }
    ]

    Supervisor.init(children, strategy: :one_for_one)
  end
end 