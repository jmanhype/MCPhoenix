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
  def handle_call({:register_client, client_id}, from, state) do
    actual_client_pid = elem(from, 0) # Extract the actual PID from the {pid, ref} tuple
    Logger.info("Registering MCP client: #{client_id} with actual_pid: #{inspect(actual_client_pid)}")
    
    # Add client to state, including its actual pid
    updated_clients = Map.put(state.clients, client_id, %{
      pid: actual_client_pid, # Store the client's actual process ID
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
    Logger.debug("Attempting to send notification to client #{client_id}: #{inspect(notification)}")

    # Retrieve the client's data, which includes the pid, from state.clients
    client_data = Map.get(state.clients, client_id)

    if client_data && client_data.pid do
      send(client_data.pid, {:send_event, "notification", notification})
      Logger.info("Successfully sent notification to client #{client_id} (pid: #{inspect(client_data.pid)})")
    else
      Logger.warn("Could not find pid for client_id #{client_id}. Notification not sent. Client data: #{inspect(client_data)}")
    end

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

  defp process_request(_client_id, %{"jsonrpc" => "2.0", "method" => "call_tool", "params" => params, "id" => id}) do
    # Handle tool invocation using the 'call_tool' method
    handle_tool_execution(params, id, "call_tool")
  end

  defp process_request(_client_id, %{"jsonrpc" => "2.0", "method" => "invoke_tool", "params" => params, "id" => id}) do
    # Handle tool invocation using 'invoke_tool' method
    handle_tool_execution(params, id, "invoke_tool")
  end

  defp process_request(_client_id, %{"jsonrpc" => "2.0", "method" => "execute", "params" => params, "id" => id}) do
    # Handle tool invocation using 'execute' method
    handle_tool_execution(params, id, "execute")
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

  defp handle_tool_execution(params, id, method_name) do
    # Check if this is a server-specific tool invocation
    if params["server_id"] do
      server_id = params["server_id"]
      
      # Extract tool and parameters based on method name
      {tool, tool_params} = case method_name do
        "call_tool" -> 
          # The call_tool method uses "name" and "arguments" 
          {params["name"], params["arguments"]}
        
        _ -> 
          # The invoke_tool and execute methods use "tool" and "parameters"
          {params["tool"], params["parameters"]}
      end
      
      Logger.debug("Delegating tool execution to server #{server_id}: #{tool} (method: #{method_name})")
      
      # Use the ServerManager to execute the tool on the specific server
      # The ServerManager will use the correct "tools/call" method when forwarding to the server process
      case MCPheonix.MCP.ServerManager.execute_tool(server_id, tool, tool_params) do
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
    else
      # Handle generic tool invocation (not server-specific)
      # For these types of requests, the method name doesn't matter
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
  end
end 