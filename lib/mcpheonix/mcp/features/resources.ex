defmodule MCPheonix.MCP.Features.Resources do
  @moduledoc """
  MCP integration for Ash resources.
  
  This module provides functionality to expose Ash resources through the MCP protocol,
  allowing AI models to interact with the application's data.
  """
  require Logger
  alias MCPheonix.Resources.Registry, as: ResourceRegistry
  alias MCPheonix.Events.Broker

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
    resource_module = find_resource_module(resource_name)
    
    if resource_module do
      # Convert string keys to atoms (safely)
      atom_params = atomize_params(params)
      
      # Execute the action
      Logger.info("Executing #{action_name} on #{resource_name} with params: #{inspect(atom_params)}")
      
      try do
        # Define how different actions are handled
        case {String.to_atom(action_name), resource_module} do
          # User actions
          {:list, MCPheonix.Resources.User} ->
            result = MCPheonix.Resources.User
              |> Ash.Query.new()
              |> Ash.Query.filter(expr(active == true))
              |> Ash.read!()
            
            {:ok, result}
            
          {:read, MCPheonix.Resources.User} ->
            result = MCPheonix.Resources.User
              |> Ash.get!(atom_params[:id])
            
            {:ok, result}
            
          {:register, MCPheonix.Resources.User} ->
            result = MCPheonix.Resources.User
              |> Ash.Changeset.new()
              |> Ash.Changeset.for_create(:register)
              |> Ash.Changeset.set_arguments(atom_params)
              |> Ash.create!()
            
            # Publish an event
            Broker.publish("resources:user:registered", %{
              id: result.id,
              username: result.username,
              timestamp: DateTime.utc_now()
            })
            
            {:ok, result}
            
          # Message actions
          {:list, MCPheonix.Resources.Message} ->
            result = MCPheonix.Resources.Message
              |> Ash.Query.new()
              |> Ash.Query.load(:user)
              |> Ash.read!()
            
            {:ok, result}
            
          {:post, MCPheonix.Resources.Message} ->
            result = MCPheonix.Resources.Message
              |> Ash.Changeset.new()
              |> Ash.Changeset.for_create(:post)
              |> Ash.Changeset.set_arguments(atom_params)
              |> Ash.create!()
            
            {:ok, result}
            
          {:read, MCPheonix.Resources.Message} ->
            result = MCPheonix.Resources.Message
              |> Ash.get!(atom_params[:id])
              |> Ash.load!(:user)
            
            {:ok, result}
            
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
    resource_module = find_resource_module(resource_name)
    
    if resource_module do
      # Set up subscription for client
      # This is a simplified approach - in a real implementation, you would
      # store subscription preferences and filter events accordingly
      
      Logger.info("Client #{client_id} subscribed to resource: #{resource_name}")
      
      # Return success
      :ok
    else
      {:error, "Resource not found: #{resource_name}"}
    end
  end

  # Private functions

  defp find_resource_module(resource_name) do
    # Find the resource module by name
    ResourceRegistry.entries()
    |> Enum.find(fn module ->
      module.__resource_name__() == resource_name
    end)
  end

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
    other_actions = resource_module.__actions__() -- primary_actions
    
    # Format actions for MCP
    Enum.map(primary_actions ++ other_actions, fn {action_name, action} ->
      %{
        name: Atom.to_string(action_name),
        description: get_action_description(action_name, action),
        parameters: get_action_parameters(action)
      }
    end)
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
    
    # Add ID parameter for read/update/destroy actions
    id_param = case action.name do
      name when name in [:read, :update, :destroy] ->
        [%{
          name: "id",
          type: "string",
          description: "ID of the record",
          required: true
        }]
      _ ->
        []
    end
    
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
    id_param ++ arg_params ++ attr_params
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
    Map.new(params, fn {k, v} ->
      if is_binary(k) do
        # Safely convert string keys to atoms
        {String.to_existing_atom(k), atomize_params(v)}
      else
        {k, atomize_params(v)}
      end
    rescue
      ArgumentError ->
        # If the atom doesn't exist, keep it as a string
        {k, atomize_params(v)}
    end)
  end
  
  defp atomize_params(params) when is_list(params) do
    Enum.map(params, &atomize_params/1)
  end
  
  defp atomize_params(params), do: params
end 