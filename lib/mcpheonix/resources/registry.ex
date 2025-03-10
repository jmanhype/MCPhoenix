defmodule MCPheonix.Resources.Registry do
  @moduledoc """
  A simplified Resource Registry that doesn't depend on Ash.
  
  This module provides a simple way to register and retrieve resources
  used by the MCP system.
  """
  use GenServer
  require Logger

  # Client API

  @doc """
  Starts the resource registry.
  """
  def start_link(_opts) do
    GenServer.start_link(__MODULE__, [], name: __MODULE__)
  end

  @doc """
  Registers a resource module.
  
  ## Parameters
    * `resource_module` - The module to register
  """
  def register(resource_module) do
    GenServer.call(__MODULE__, {:register, resource_module})
  end

  @doc """
  Returns all registered resource modules.
  """
  def entries do
    GenServer.call(__MODULE__, :entries)
  end

  @doc """
  Finds a resource module by name.
  
  ## Parameters
    * `resource_name` - The name of the resource to find
  
  ## Returns
    * The resource module or nil if not found
  """
  def find_by_name(resource_name) do
    GenServer.call(__MODULE__, {:find_by_name, resource_name})
  end

  # Server callbacks

  @impl true
  def init(_) do
    Logger.info("Resource registry started")
    
    # Define some static resources for simplicity
    static_resources = [
      %{
        module: MCPheonix.Resources.User,
        name: "user",
        description: "User resource"
      },
      %{
        module: MCPheonix.Resources.Message,
        name: "message",
        description: "Message resource"
      }
    ]
    
    {:ok, %{resources: static_resources}}
  end

  @impl true
  def handle_call({:register, resource_module}, _from, state) do
    Logger.info("Registering resource: #{inspect(resource_module)}")
    
    # Check if the resource is already registered
    existing = Enum.find(state.resources, fn r -> r.module == resource_module end)
    
    if existing do
      {:reply, {:error, :already_registered}, state}
    else
      # Add resource to registry
      # In a real implementation, you would extract proper metadata from the module
      resource = %{
        module: resource_module,
        name: resource_module_to_name(resource_module),
        description: "Resource #{inspect(resource_module)}"
      }
      
      updated_resources = [resource | state.resources]
      
      {:reply, :ok, %{state | resources: updated_resources}}
    end
  end

  @impl true
  def handle_call(:entries, _from, state) do
    {:reply, Enum.map(state.resources, fn r -> r.module end), state}
  end

  @impl true
  def handle_call({:find_by_name, resource_name}, _from, state) do
    resource = Enum.find(state.resources, fn r -> r.name == resource_name end)
    
    if resource do
      {:reply, resource.module, state}
    else
      {:reply, nil, state}
    end
  end

  # Private functions

  defp resource_module_to_name(module) do
    module
    |> to_string()
    |> String.split(".")
    |> List.last()
    |> Macro.underscore()
  end
end 