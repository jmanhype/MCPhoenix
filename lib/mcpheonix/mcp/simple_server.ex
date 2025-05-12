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
  def handle_call({:handle_request, client_id, request_struct}, _from, state) do
    # request_struct is MCPheonix.MCP.JsonRpcProtocol.Request.t()
    Logger.debug("Handling MCP request from #{client_id}: #{inspect(request_struct)}")
    
    # Process the JSON-RPC request using the new internal function
    response_tuple = process_request_internal(client_id, request_struct.method, request_struct.params)
    
    # Publish request event to the event system (optional, consider if this is still needed here)
    # If publishing, we might need to adapt what's being published if response_tuple is not the full JSON response.
    # For now, let's assume the Connection module will handle logging the full exchange if needed.
    # Broker.publish("mcp:requests", %{
    #   client_id: client_id,
    #   request: request_struct, # This is the Request struct
    #   response_payload: response_tuple, # This is {:ok, data} or {:error, error_map}
    #   timestamp: DateTime.utc_now()
    # })
    
    {:reply, response_tuple, state}
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

    # Qodo Merge Pro Suggestion: Check process liveness
    # The code sends a direct message to the client process but doesn't verify if the process is still alive.
    # Add a Process.alive?/1 check before sending the message to prevent sending to a dead process,
    # which could lead to unexpected behavior.
    if client_data && client_data.pid && Process.alive?(client_data.pid) do
      send(client_data.pid, {:send_event, "notification", notification})
      Logger.info("Successfully sent notification to client #{client_id} (pid: #{inspect(client_data.pid)})")
    else
      reason = cond do
        !client_data -> "client data not found"
        !client_data.pid -> "client pid not available"
        client_data.pid && !Process.alive?(client_data.pid) -> "client process no longer alive"
        true -> "unknown reason (client_data: #{inspect(client_data)})"
      end
      Logger.warning("Could not send notification to client #{client_id}. Reason: #{reason}", [])
      # If the client process is not alive, cast a message to unregister it.
      if client_data && client_data.pid && !Process.alive?(client_data.pid) do
        Logger.info("Casting :unregister_client for client #{client_id} as its process is no longer alive.")
        GenServer.cast(__MODULE__, {:unregister_client, client_id})
      end
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

  defp process_request_internal(client_id, method, params) do
    Logger.debug("SimpleServer.process_request_internal: client=#{client_id}, method=#{method}, params=#{inspect(params)}")
    case method do
      "initialize" ->
        {:ok, %{capabilities: load_capabilities()}}

      "call_tool" ->
        handle_tool_execution_internal(client_id, "call_tool", params)
      
      "invoke_tool" ->
        handle_tool_execution_internal(client_id, "invoke_tool", params)

      "execute" ->
        handle_tool_execution_internal(client_id, "execute", params)
        
      # Example: A method specific to SimpleServer, not a tool
      # "simple_server_echo" ->
      #   if Map.has_key?(params, "message") do
      #     {:ok, %{echo_response: params["message"]}}
      #   else
      #     {:error, %{code: -32602, message: "Invalid params", data: %{reason: "Missing 'message' for simple_server_echo"}}}
      #   end

      _unknown_method ->
        Logger.warning("Method not found in SimpleServer: #{method}", [])
        {:error, %{code: -32601, message: "Method not found", data: %{method: method}}}
    end
  end

  defp handle_tool_execution_internal(_client_id, original_method_name, params) do
    Logger.debug("SimpleServer.handle_tool_execution_internal: method=#{original_method_name}, params=#{inspect(params)}")
    
    # Determine tool name and parameters based on the original method name
    # This logic needs to be robust to missing keys.
    {tool_name, tool_params_map, server_id} =
      case original_method_name do
        "call_tool" -> 
          # call_tool expects "name" for tool_name and "arguments" for tool_params_map
          {Map.get(params, "name"), Map.get(params, "arguments"), Map.get(params, "server_id")}
        "invoke_tool" ->
          # invoke_tool expects "tool" for tool_name and "parameters" for tool_params_map
          {Map.get(params, "tool"), Map.get(params, "parameters"), Map.get(params, "server_id")}
        "execute" ->
          # execute also expects "tool" for tool_name and "parameters" for tool_params_map
          {Map.get(params, "tool"), Map.get(params, "parameters"), Map.get(params, "server_id")}
        _ ->
          # Should not happen if called from process_request_internal correctly
          Logger.error("Unknown original method name in handle_tool_execution_internal: #{original_method_name}")
          {nil, nil, nil}
      end

    # Validate essential parameters
    cond do
      is_nil(tool_name) ->
        error_message = 
          case original_method_name do
            "call_tool" -> "Missing 'name' (tool name) in params for #{original_method_name}"
            _ -> "Missing 'tool' (tool name) in params for #{original_method_name}"
          end
        Logger.warning(error_message <> ": #{inspect(params)}", [])
        {:error, %{code: -32602, message: "Invalid params", data: %{reason: error_message}}}

      # server_id is present, delegate to ServerManager
      # Note: tool_params_map can be nil if "arguments" or "parameters" are not provided, which is valid.
      !is_nil(server_id) ->
        Logger.info("Delegating tool '#{tool_name}' to server '#{server_id}' via ServerManager (original method: #{original_method_name})")
        case MCPheonix.MCP.ServerManager.execute_tool(server_id, tool_name, tool_params_map) do
        {:ok, result} ->
            {:ok, result}
        {:error, reason} ->
            Logger.error("Error from ServerManager.execute_tool for '#{tool_name}': #{inspect(reason)}", [])
            _error_data = if is_map(reason) and Map.has_key?(reason, :code) and Map.has_key?(reason, :message), do: reason, else: %{reason: inspect(reason)}
            # If reason is already a well-formed error map, use it, otherwise wrap it.
            if is_map(reason) and Map.has_key?(reason, :code) and Map.has_key?(reason, :message) do
              {:error, reason}
            else
              {:error, %{code: -32000, message: "Tool execution failed via ServerManager", data: %{original_reason: inspect(reason)}}}
      end
        end

      # server_id is NOT present, execute locally using Tools module
      true ->
        Logger.info("Executing tool '#{tool_name}' locally via Tools module (original method: #{original_method_name})")
        try do
          case Tools.execute_tool(tool_name, tool_params_map) do
        {:ok, result} ->
              {:ok, result}
            {:error, reason} ->
              # Construct the error map that will be the second element of the returned {:error, error_map} tuple
              error_payload = 
                cond do
                  is_map(reason) and Map.has_key?(reason, :code) and Map.has_key?(reason, :message) ->
                    # If 'reason' is already a well-formed error {code, message, data}, use it
                    reason
                  true -> 
                    # Otherwise, wrap it
                    %{code: -32000, message: "Tool execution failed", data: %{tool: tool_name, original_reason: inspect(reason)}}
                end
              Logger.error("Tool '#{tool_name}' execution failed. Error payload: #{inspect(error_payload)}", [])
              {:error, error_payload} # This is the value returned by this path of the 'case'
          end
        catch
          :error, reason ->
            stacktrace = __STACKTRACE__
            Logger.error(
              "Error during tool execution for '#{tool_name}'. Reason: #{inspect(reason)}. Stacktrace: #{inspect(stacktrace)}",
              []
            )
            # This will be the `reason` in `{:error, reason}` tuple from the catch block
            {:error, %{code: -32000, message: "Error during tool execution: #{reason}", data: %{tool: tool_name, params: tool_params_map, stacktrace: inspect(stacktrace)}}}

          :exit, reason ->
            stacktrace = __STACKTRACE__
            Logger.error(
              "Exit during tool execution for '#{tool_name}'. Reason: #{inspect(reason)}. Stacktrace: #{inspect(stacktrace)}",
              []
            )
            {:error, %{code: -32000, message: "Exit during tool execution: #{reason}", data: %{tool: tool_name, params: tool_params_map, stacktrace: inspect(stacktrace)}}}
        else
          # The value from the 'do' block (result_from_do_block) is passed here
          # if no exception was caught.
          result_from_do_block -> result_from_do_block
      end
    end
  end
end 