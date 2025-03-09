defmodule MCPheonix.MCP.Server do
  @moduledoc """
  MCP Server implementation.
  
  This module implements the server-side of the Model Context Protocol (MCP),
  handling JSON-RPC requests from AI clients and exposing system capabilities.
  """
  use GenServer
  require Logger
  alias MCPheonix.Events.Broker
  alias MCPheonix.MCP.Features.{Resources, Tools}

  # Client API

  @doc """
  Starts the MCP server.
  """
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Registers a new client connection.
  """
  def register_client(client_id) do
    GenServer.call(__MODULE__, {:register_client, client_id})
  end

  @doc """
  Unregisters a client connection.
  """
  def unregister_client(client_id) do
    GenServer.cast(__MODULE__, {:unregister_client, client_id})
  end

  @doc """
  Handles an incoming JSON-RPC request from a client.
  """
  def handle_request(client_id, request) do
    GenServer.call(__MODULE__, {:handle_request, client_id, request})
  end

  @doc """
  Sends a notification to a client.
  """
  def notify_client(client_id, notification) do
    GenServer.cast(__MODULE__, {:notify_client, client_id, notification})
  end

  # Server callbacks

  @impl true
  def init(_opts) do
    # Subscribe to relevant event topics
    Broker.subscribe("mcp:notifications")
    
    # Initialize server state
    {:ok, %{
      clients: %{},
      capabilities: load_capabilities()
    }}
  end

  @impl true
  def handle_call({:register_client, client_id}, _from, state) do
    Logger.info("Registering MCP client: #{client_id}")
    
    # Add client to state
    updated_clients = Map.put(state.clients, client_id, %{
      connected_at: DateTime.utc_now(),
      subscriptions: []
    })
    
    {:reply, {:ok, state.capabilities}, %{state | clients: updated_clients}}
  end

  @impl true
  def handle_call({:handle_request, client_id, request}, _from, state) do
    Logger.debug("Handling MCP request from #{client_id}: #{inspect(request)}")
    
    # Process the JSON-RPC request
    response = process_request(client_id, request, state.capabilities)
    
    # Publish request event to the event system
    Broker.publish("mcp:requests", %{
      client_id: client_id,
      request: request,
      response: response,
      timestamp: DateTime.utc_now()
    })
    
    {:reply, response, state}
  end

  @impl true
  def handle_cast({:unregister_client, client_id}, state) do
    Logger.info("Unregistering MCP client: #{client_id}")
    
    # Remove client from state
    updated_clients = Map.delete(state.clients, client_id)
    
    {:noreply, %{state | clients: updated_clients}}
  end

  @impl true
  def handle_cast({:notify_client, client_id, notification}, state) do
    Logger.debug("Sending notification to client #{client_id}: #{inspect(notification)}")
    
    # This would be implemented through the MCP.Connection process
    # that manages the client's SSE stream
    # For now, we'll just log it
    case Registry.lookup(MCPheonix.MCP.ConnectionRegistry, client_id) do
      [{pid, _}] ->
        # Send the notification to the client's connection process
        MCPheonix.MCP.Connection.send_notification(client_id, notification)
        
      [] ->
        Logger.warning("Attempted to notify unknown client: #{client_id}")
    end
    
    {:noreply, state}
  end

  @impl true
  def handle_info({:event, "mcp:notifications", event}, state) do
    # Handle incoming events from the event system that should be forwarded to clients
    Logger.debug("Received event for MCP notifications: #{inspect(event)}")
    
    # Forward to relevant clients based on their subscriptions
    # This is a simplistic implementation - a real one would filter based on subscriptions
    for {client_id, _client_data} <- state.clients do
      notify_client(client_id, %{
        jsonrpc: "2.0",
        method: "notification",
        params: event
      })
    end
    
    {:noreply, state}
  end

  # Private functions

  defp load_capabilities do
    # Load capabilities from the feature modules
    %{
      resources: Resources.list_resources(),
      tools: Tools.list_tools(),
      prompts: [] # Not implemented in this example
    }
  end

  # Handle different types of JSON-RPC requests
  
  # Initialize request
  defp process_request(_client_id, %{"jsonrpc" => "2.0", "method" => "initialize", "id" => id}, capabilities) do
    # Handle initialize request
    %{
      jsonrpc: "2.0",
      id: id,
      result: %{
        capabilities: capabilities
      }
    }
  end
  
  # Tool invocation
  defp process_request(client_id, %{"jsonrpc" => "2.0", "method" => "invoke_tool", "params" => params, "id" => id}, _capabilities) do
    # Handle tool invocation
    tool_name = params["tool"]
    tool_params = params["parameters"]
    
    Logger.info("Client #{client_id} invoking tool: #{tool_name}")
    
    # Call the tool handler
    case Tools.execute_tool(tool_name, tool_params) do
      {:ok, result} ->
        %{
          jsonrpc: "2.0",
          id: id,
          result: result
        }
        
      {:error, reason} ->
        %{
          jsonrpc: "2.0",
          id: id,
          error: %{
            code: -32000,
            message: "Tool execution failed",
            data: %{
              reason: reason
            }
          }
        }
    end
  end
  
  # Resource action
  defp process_request(client_id, %{"jsonrpc" => "2.0", "method" => "resource_action", "params" => params, "id" => id}, _capabilities) do
    # Handle resource action invocation
    resource_name = params["resource"]
    action_name = params["action"]
    action_params = params["parameters"]
    
    Logger.info("Client #{client_id} invoking resource action: #{action_name} on #{resource_name}")
    
    # Call the resource handler
    case Resources.execute_action(resource_name, action_name, action_params) do
      {:ok, result} ->
        %{
          jsonrpc: "2.0",
          id: id,
          result: result
        }
        
      {:error, reason} ->
        %{
          jsonrpc: "2.0",
          id: id,
          error: %{
            code: -32000,
            message: "Resource action failed",
            data: %{
              reason: reason
            }
          }
        }
    end
  end
  
  # Resource subscription
  defp process_request(client_id, %{"jsonrpc" => "2.0", "method" => "subscribe", "params" => params, "id" => id}, _capabilities) do
    # Handle subscription request
    resource_name = params["resource"]
    
    Logger.info("Client #{client_id} subscribing to resource: #{resource_name}")
    
    # Call the subscription handler
    case Resources.subscribe(client_id, resource_name) do
      :ok ->
        %{
          jsonrpc: "2.0",
          id: id,
          result: %{
            status: "subscribed",
            resource: resource_name
          }
        }
        
      {:error, reason} ->
        %{
          jsonrpc: "2.0",
          id: id,
          error: %{
            code: -32000,
            message: "Subscription failed",
            data: %{
              reason: reason
            }
          }
        }
    end
  end
  
  # Unknown method
  defp process_request(_client_id, %{"jsonrpc" => "2.0", "method" => method, "id" => id}, _capabilities) do
    # Handle unknown method
    %{
      jsonrpc: "2.0",
      id: id,
      error: %{
        code: -32601,
        message: "Method not found",
        data: %{
          method: method
        }
      }
    }
  end
  
  # Invalid request
  defp process_request(_client_id, invalid_request, _capabilities) do
    # Handle invalid JSON-RPC request
    %{
      jsonrpc: "2.0",
      id: nil,
      error: %{
        code: -32600,
        message: "Invalid Request",
        data: %{
          received: invalid_request
        }
      }
    }
  end
end 