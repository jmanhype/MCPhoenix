defmodule MCPheonix.MCP.Features.Resources do
  @moduledoc """
  Simplified MCP integration for resources.
  
  This module provides functionality to expose resources through the MCP protocol,
  allowing AI models to interact with the application's data.
  """
  require Logger
  alias MCPheonix.Resources.Registry, as: ResourceRegistry
  alias MCPheonix.Events.Broker
  alias MCPheonix.Resources.{User, Message}

  @doc """
  Lists all available resources that can be accessed through MCP.
  
  ## Returns
    * A list of resource definitions
  """
  def list_resources do
    # Get all resources from the registry
    ResourceRegistry.entries()
    |> Enum.map(fn resource_module ->
      # Extract resource information
      resource_name = resource_module.__resource_name__()
      
      %{
        name: resource_name,
        description: get_resource_description(resource_module),
        actions: get_resource_actions(resource_module)
      }
    end)
  end

  @doc """
  Executes an action on a resource through MCP.
  
  ## Parameters
    * `resource_name` - The name of the resource
    * `action_name` - The name of the action to execute
    * `params` - The parameters for the action
  
  ## Returns
    * `{:ok, result}` - The action was executed successfully
    * `{:error, reason}` - The action failed
  """
  def execute_action(resource_name, action_name, params) do
    # Find the resource module
    resource_module = ResourceRegistry.find_by_name(resource_name)
    
    if resource_module do
      # Convert string keys to atoms (safely)
      atom_params = atomize_params(params)
      
      # Execute the action
      Logger.info("Executing #{action_name} on #{resource_name} with params: #{inspect(atom_params)}")
      
      try do
        # Define how different actions are handled
        case {String.to_atom(action_name), resource_module} do
          # User actions
          {:list, User} ->
            active_only = Map.get(atom_params, :active_only, false)
            result = User.list(active_only: active_only)
            {:ok, result}
            
          {:read, User} ->
            result = User.get(atom_params.id)
            result
            
          {:register, User} ->
            result = User.register(atom_params)
            result
            
          {:activate, User} ->
            result = User.activate(atom_params.id)
            result
            
          {:deactivate, User} ->
            result = User.deactivate(atom_params.id)
            result
            
          # Message actions
          {:list, Message} ->
            created_after = Map.get(atom_params, :created_after)
            result = Message.list(created_after: created_after)
            {:ok, result}
            
          {:post, Message} ->
            result = Message.create(atom_params.user_id, atom_params.content)
            result
            
          {:read, Message} ->
            result = Message.get(atom_params.id)
            result
            
          {:edit, Message} ->
            result = Message.update(atom_params.id, %{content: atom_params.content})
            result
            
          # Default case - unsupported action
          _ ->
            {:error, "Unsupported action: #{action_name} for resource: #{resource_name}"}
        end
      rescue
        e ->
          Logger.error("Error executing action: #{inspect(e)}")
          {:error, "Error executing action: #{Exception.message(e)}"}
      end
    else
      {:error, "Resource not found: #{resource_name}"}
    end
  end

  @doc """
  Subscribes to events from a specific resource.
  
  ## Parameters
    * `client_id` - The ID of the MCP client
    * `resource_name` - The name of the resource to subscribe to
  
  ## Returns
    * `:ok` - Successfully subscribed
    * `{:error, reason}` - Failed to subscribe
  """
  def subscribe(client_id, resource_name) do
    # Find the resource module
    resource_module = ResourceRegistry.find_by_name(resource_name)
    
    if resource_module do
      # Subscribe to resource events
      topic = "resources:#{resource_name}:*"
      Broker.subscribe(topic)
      
      Logger.info("Client #{client_id} subscribed to resource: #{resource_name}")
      
      # Return success
      :ok
    else
      {:error, "Resource not found: #{resource_name}"}
    end
  end

  # Private functions

  defp get_resource_description(resource_module) do
    # Extract description from @moduledoc
    case Code.fetch_docs(resource_module) do
      {:docs_v1, _, _, _, %{"en" => module_doc}, _, _} ->
        # Get first line of module doc as description
        module_doc
        |> String.split("\n", parts: 2)
        |> List.first()
        |> String.trim()
        
      _ ->
        "#{resource_module.__resource_name__()} resource"
    end
  end

  defp get_resource_actions(resource_module) do
    # Get actions defined on the resource
    primary_actions = resource_module.__primary_actions__()
    other_actions = resource_module.__actions__()
    
    # Format actions for MCP
    (Enum.map(primary_actions, fn {action_name, action} ->
      %{
        name: Atom.to_string(action_name),
        description: get_action_description(action_name, action),
        parameters: get_action_parameters(action)
      }
    end) ++ Enum.map(other_actions, fn {action_name, action} ->
      %{
        name: Atom.to_string(action_name),
        description: get_action_description(action_name, action),
        parameters: get_action_parameters(action)
      }
    end))
  end

  defp get_action_description(action_name, _action) do
    # This is simplified - in a real implementation, you might extract
    # descriptions from documentation or provide more detailed descriptions
    case action_name do
      :create -> "Create a new record"
      :read -> "Read a record by ID"
      :update -> "Update an existing record"
      :destroy -> "Delete a record"
      :list -> "List all records"
      :register -> "Register a new user"
      :post -> "Post a new message"
      :edit -> "Edit an existing message"
      :activate -> "Activate a user"
      :deactivate -> "Deactivate a user"
      _ -> "Execute the #{action_name} action"
    end
  end

  defp get_action_parameters(action) do
    # Extract arguments from the action
    action_arguments = action.arguments || []
    accepted_attributes = action.accept || []
    
    # Convert arguments to parameters
    arg_params = Enum.map(action_arguments, fn {arg_name, arg_config} ->
      %{
        name: Atom.to_string(arg_name),
        type: get_type_string(arg_config[:type]),
        description: "Argument for #{action.name}",
        required: !arg_config[:allow_nil?]
      }
    end)
    
    # Convert accepted attributes to parameters
    attr_params = Enum.map(accepted_attributes, fn attr_name ->
      %{
        name: Atom.to_string(attr_name),
        type: "string",
        description: "Attribute #{attr_name}",
        required: false
      }
    end)
    
    # Combine all parameters
    arg_params ++ attr_params
  end

  defp get_type_string(type) do
    case type do
      :string -> "string"
      :integer -> "integer"
      :boolean -> "boolean"
      :utc_datetime -> "string"
      :date -> "string"
      _ -> "string"
    end
  end

  defp atomize_params(params) when is_map(params) do
    Enum.reduce(params, %{}, fn {k, v}, acc ->
      key = if is_binary(k) do
        try do
          String.to_existing_atom(k)
        rescue
          ArgumentError -> k
        end
      else
        k
      end
      
      Map.put(acc, key, atomize_params(v))
    end)
  end
  
  defp atomize_params(params) when is_list(params) do
    Enum.map(params, &atomize_params/1)
  end
  
  defp atomize_params(params), do: params
end 