defmodule MCPheonix.MCP.SimpleServer do
  @moduledoc """
  A simplified MCP Server implementation.
  
  This module implements a basic MCP server without the Ash Framework dependency.
  """
  use GenServer
  require Logger
  alias MCPheonix.Events.Broker
  alias MCPheonix.MCP.Features.Tools

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
    # Increase the timeout to 60 seconds to allow for longer-running operations like image generation
    GenServer.call(__MODULE__, {:handle_request, client_id, request}, 60_000)
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
    response = process_request(client_id, request)
    
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
    
    # In a real implementation, this would send the notification to the client's SSE stream
    # For now, we'll just log it
    Logger.info("Would send notification to client #{client_id}: #{inspect(notification)}")
    
    {:noreply, state}
  end

  @impl true
  def handle_info({:event, "mcp:notifications", event}, state) do
    # Handle incoming events from the event system that should be forwarded to clients
    Logger.debug("Received event for MCP notifications: #{inspect(event)}")
    
    # Forward to all clients
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
    # Simple static capabilities
    %{
      resources: [
        %{
          name: "user",
          description: "User resource",
          actions: [
            %{
              name: "list",
              description: "List all users",
              parameters: []
            },
            %{
              name: "get",
              description: "Get a user by ID",
              parameters: [
                %{
                  name: "id",
                  type: "string",
                  description: "User ID",
                  required: true
                }
              ]
            }
          ]
        },
        %{
          name: "message",
          description: "Message resource",
          actions: [
            %{
              name: "list",
              description: "List all messages",
              parameters: []
            },
            %{
              name: "get",
              description: "Get a message by ID",
              parameters: [
                %{
                  name: "id",
                  type: "string",
                  description: "Message ID",
                  required: true
                }
              ]
            }
          ]
        }
      ],
      tools: Tools.list_tools(),
      prompts: []
    }
  end

  defp process_request(_client_id, %{"jsonrpc" => "2.0", "method" => "initialize", "id" => id}) do
    # Handle initialize request
    %{
      jsonrpc: "2.0",
      id: id,
      result: %{
        capabilities: load_capabilities()
      }
    }
  end

  defp process_request(_client_id, %{"jsonrpc" => "2.0", "method" => "invoke_tool", "params" => params, "id" => id}) do
    # Handle tool invocation
    tool_name = params["tool"]
    tool_params = params["parameters"]
    
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

  defp process_request(_client_id, %{"jsonrpc" => "2.0", "method" => method, "id" => id}) do
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

  defp process_request(_client_id, invalid_request) do
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