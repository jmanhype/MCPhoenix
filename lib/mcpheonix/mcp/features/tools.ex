defmodule MCPheonix.MCP.Features.Tools do
  @moduledoc """
  MCP integration for tools.
  
  This module provides functionality to expose system actions as tools through the MCP protocol,
  allowing AI models to perform operations on the system.
  """
  require Logger
  alias MCPheonix.Events.Broker
  alias MCPheonix.Cloud.DurableObjects.Client, as: DOClient

  @doc """
  Lists all available tools that can be called through MCP.
  
  ## Returns
    * A list of tool definitions
  """
  def list_tools do
    [
      # Message tools
      %{
        name: "send_message",
        description: "Send a message to a user",
        parameters: [
          %{
            name: "user_id",
            type: "string",
            description: "ID of the recipient user",
            required: true
          },
          %{
            name: "content",
            type: "string",
            description: "Content of the message",
            required: true
          }
        ]
      },
      
      # User tools
      %{
        name: "activate_user",
        description: "Activate a user account",
        parameters: [
          %{
            name: "user_id",
            type: "string",
            description: "ID of the user to activate",
            required: true
          }
        ]
      },
      %{
        name: "deactivate_user",
        description: "Deactivate a user account",
        parameters: [
          %{
            name: "user_id",
            type: "string",
            description: "ID of the user to deactivate",
            required: true
          }
        ]
      },
      
      # Durable Objects tools
      %{
        name: "create_durable_object",
        description: "Create a new Durable Object for state management",
        parameters: [
          %{
            name: "name",
            type: "string",
            description: "Name for the Durable Object",
            required: true
          },
          %{
            name: "initial_data",
            type: "object",
            description: "Initial data for the Durable Object",
            required: true
          }
        ]
      },
      %{
        name: "call_durable_object",
        description: "Call a method on a Durable Object",
        parameters: [
          %{
            name: "object_id",
            type: "string",
            description: "ID of the Durable Object",
            required: true
          },
          %{
            name: "method",
            type: "string",
            description: "Method to call on the Durable Object",
            required: true
          },
          %{
            name: "params",
            type: "object",
            description: "Parameters for the method call",
            required: true
          }
        ]
      }
    ]
  end

  @doc """
  Executes a tool through MCP.
  
  ## Parameters
    * `tool_name` - The name of the tool to execute
    * `params` - The parameters for the tool
  
  ## Returns
    * `{:ok, result}` - The tool was executed successfully
    * `{:error, reason}` - The tool execution failed
  """
  def execute_tool(tool_name, params) do
    Logger.info("Executing tool: #{tool_name} with params: #{inspect(params)}")
    
    # Execute the tool based on its name
    case tool_name do
      "send_message" ->
        send_message(params["user_id"], params["content"])
        
      "activate_user" ->
        activate_user(params["user_id"])
        
      "deactivate_user" ->
        deactivate_user(params["user_id"])
        
      "create_durable_object" ->
        create_durable_object(params["name"], params["initial_data"])
        
      "call_durable_object" ->
        call_durable_object(params["object_id"], params["method"], params["params"])
        
      _ ->
        {:error, "Unknown tool: #{tool_name}"}
    end
  end

  # Tool implementations

  defp send_message(user_id, content) do
    try do
      # Create a message using Ash
      result = MCPheonix.Resources.Message.create_message(user_id, content)
      
      # Publish an event
      Broker.publish("tools:message_sent", %{
        user_id: user_id,
        content: content,
        timestamp: DateTime.utc_now()
      })
      
      {:ok, %{
        message_id: result.id,
        status: "sent",
        timestamp: DateTime.utc_now()
      }}
    rescue
      e ->
        Logger.error("Error sending message: #{inspect(e)}")
        {:error, "Error sending message: #{Exception.message(e)}"}
    end
  end

  defp activate_user(user_id) do
    try do
      # Load the user
      user = MCPheonix.Resources.User
        |> Ash.get!(user_id)
        
      # Activate the user
      result = user
        |> Ash.Changeset.new()
        |> Ash.Changeset.for_action(:activate)
        |> Ash.update!()
      
      # Publish an event
      Broker.publish("tools:user_activated", %{
        user_id: user_id,
        username: result.username,
        timestamp: DateTime.utc_now()
      })
      
      {:ok, %{
        user_id: result.id,
        username: result.username,
        active: result.active,
        timestamp: DateTime.utc_now()
      }}
    rescue
      e ->
        Logger.error("Error activating user: #{inspect(e)}")
        {:error, "Error activating user: #{Exception.message(e)}"}
    end
  end

  defp deactivate_user(user_id) do
    try do
      # Load the user
      user = MCPheonix.Resources.User
        |> Ash.get!(user_id)
        
      # Deactivate the user
      result = user
        |> Ash.Changeset.new()
        |> Ash.Changeset.for_action(:deactivate)
        |> Ash.update!()
      
      # Publish an event
      Broker.publish("tools:user_deactivated", %{
        user_id: user_id,
        username: result.username,
        timestamp: DateTime.utc_now()
      })
      
      {:ok, %{
        user_id: result.id,
        username: result.username,
        active: result.active,
        timestamp: DateTime.utc_now()
      }}
    rescue
      e ->
        Logger.error("Error deactivating user: #{inspect(e)}")
        {:error, "Error deactivating user: #{Exception.message(e)}"}
    end
  end

  defp create_durable_object(name, initial_data) do
    # Get Cloudflare Worker URL from config
    worker_url = Application.get_env(:mcpheonix, :cloudflare_worker_url) ||
                "https://example.cloudflare.workers.dev"
    
    # Generate a unique ID for the Durable Object
    object_id = "#{name}-#{:crypto.strong_rand_bytes(8) |> Base.encode16(case: :lower)}"
    
    # Initialize the Durable Object
    case DOClient.initialize(worker_url, object_id, initial_data) do
      {:ok, response} ->
        # Publish an event
        Broker.publish("tools:durable_object_created", %{
          object_id: object_id,
          name: name,
          timestamp: DateTime.utc_now()
        })
        
        {:ok, %{
          object_id: object_id,
          name: name,
          status: "created",
          response: response,
          timestamp: DateTime.utc_now()
        }}
        
      error ->
        error
    end
  end

  defp call_durable_object(object_id, method, params) do
    # Get Cloudflare Worker URL from config
    worker_url = Application.get_env(:mcpheonix, :cloudflare_worker_url) ||
                "https://example.cloudflare.workers.dev"
    
    # Call the method on the Durable Object
    case DOClient.call_method(worker_url, object_id, method, params) do
      {:ok, response} ->
        # Publish an event
        Broker.publish("tools:durable_object_method_called", %{
          object_id: object_id,
          method: method,
          timestamp: DateTime.utc_now()
        })
        
        {:ok, %{
          object_id: object_id,
          method: method,
          status: "called",
          response: response,
          timestamp: DateTime.utc_now()
        }}
        
      error ->
        error
    end
  end
end 