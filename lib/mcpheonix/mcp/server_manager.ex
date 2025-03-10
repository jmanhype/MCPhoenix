defmodule MCPheonix.MCP.ServerManager do
  @moduledoc """
  Manager for MCP servers.
  
  This module is responsible for starting and managing multiple MCP servers,
  including handling their lifecycle and tool registration.
  """
  
  use GenServer
  require Logger
  alias MCPheonix.MCP.{Config, ServerProcess}
  
  # Client API
  
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end
  
  @doc """
  Start a specific MCP server.
  
  ## Parameters
    * `server_id` - The ID of the server to start
  """
  def start_server(server_id) do
    GenServer.call(__MODULE__, {:start_server, server_id})
  end
  
  @doc """
  Stop a specific MCP server.
  
  ## Parameters
    * `server_id` - The ID of the server to stop
  """
  def stop_server(server_id) do
    GenServer.call(__MODULE__, {:stop_server, server_id})
  end
  
  @doc """
  Execute a tool on a specific server.
  
  ## Parameters
    * `server_id` - The ID of the server to execute the tool on
    * `tool` - The name of the tool to execute
    * `params` - The parameters for the tool
  """
  def execute_tool(server_id, tool, params) do
    GenServer.call(__MODULE__, {:execute_tool, server_id, tool, params}, 60_000)
  end
  
  # Server Callbacks
  
  @impl true
  def init(_opts) do
    # Initialize state with empty maps for servers and tools
    state = %{
      servers: %{},  # server_id => server_pid
      tools: %{},    # tool_name => {server_id, tool_config}
      configs: %{}   # server_id => config
    }
    
    # Load configurations and start configured servers
    case Config.load_configs() do
      {:ok, configs} ->
        state = %{state | configs: configs}
        # Start each configured server
        state = Enum.reduce(configs, state, fn {server_id, config}, acc ->
          case start_server_process(server_id, config) do
            {:ok, pid} ->
              # Register tools for this server
              tools = Map.get(config, :tools, %{})
              acc = register_server_tools(acc, server_id, tools)
              %{acc | servers: Map.put(acc.servers, server_id, pid)}
            {:error, reason} ->
              Logger.error("Failed to start server #{server_id}: #{inspect(reason)}")
              acc
          end
        end)
        {:ok, state}
        
      {:error, reason} ->
        Logger.error("Failed to load MCP server configurations: #{inspect(reason)}")
        {:ok, state}
    end
  end
  
  @impl true
  def handle_call({:start_server, server_id}, _from, state) do
    case Map.get(state.configs, server_id) do
      nil ->
        {:reply, {:error, "Server configuration not found"}, state}
        
      config ->
        case start_server_process(server_id, config) do
          {:ok, pid} ->
            # Register tools for this server
            tools = Map.get(config, :tools, %{})
            new_state = register_server_tools(state, server_id, tools)
            new_state = %{new_state | servers: Map.put(new_state.servers, server_id, pid)}
            {:reply, :ok, new_state}
            
          error ->
            {:reply, error, state}
        end
    end
  end
  
  @impl true
  def handle_call({:stop_server, server_id}, _from, state) do
    case Map.get(state.servers, server_id) do
      nil ->
        {:reply, {:error, "Server not found"}, state}
        
      pid ->
        # Stop the server process
        GenServer.stop(pid, :normal)
        new_state = %{state | 
          servers: Map.delete(state.servers, server_id),
          tools: remove_server_tools(state.tools, server_id)
        }
        {:reply, :ok, new_state}
    end
  end
  
  @impl true
  def handle_call({:execute_tool, server_id, tool, params}, _from, state) do
    Logger.info("Routing tool execution to server #{server_id}: #{tool}")
    
    case Map.get(state.servers, server_id) do
      nil ->
        Logger.error("Server not found: #{server_id}")
        {:reply, {:error, "Server not found"}, state}
        
      pid ->
        # Forward the tool execution directly to the server process
        # Skip checking if the tool is registered, as the server might have dynamically available tools
        Logger.debug("Forwarding tool execution to server process #{inspect(pid)}")
        result = ServerProcess.execute_tool(pid, tool, params)
        Logger.debug("Result from server process: #{inspect(result)}")
        {:reply, result, state}
    end
  end
  
  # Private Functions
  
  defp start_server_process(server_id, config) do
    Logger.info("Starting MCP server: #{server_id}")
    
    case Config.validate_config(config) do
      :ok ->
        # Start a new server process
        ServerProcess.start_link([
          server_id: server_id,
          command: config.command,
          args: config.args,
          env: config.env || %{}
        ])
        
      {:error, reason} ->
        Logger.error("Invalid configuration for server #{server_id}: #{inspect(reason)}")
        {:error, reason}
    end
  end
  
  defp register_server_tools(state, server_id, tools) do
    # Add each tool to the tools map with its server_id
    Enum.reduce(tools, state, fn {tool_name, tool_config}, acc ->
      tools = Map.put(acc.tools, tool_name, {server_id, tool_config})
      %{acc | tools: tools}
    end)
  end
  
  defp remove_server_tools(tools, server_id) do
    Enum.reduce(tools, %{}, fn {tool_name, {sid, config}}, acc ->
      if sid == server_id do
        acc
      else
        Map.put(acc, tool_name, {sid, config})
      end
    end)
  end
  
  defp get_tool_config(tools, server_id, tool_name) do
    case Map.get(tools, tool_name) do
      {^server_id, config} -> config
      _ -> nil
    end
  end
end 