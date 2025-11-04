defmodule MCPheonix.MCP.Connection do
  @moduledoc """
  Manages MCP client connections and processes JSON-RPC messages.
  
  This module provides functionality to handle client connections and send
  server-sent events (SSE) to connected clients.
  """
  require Logger
  alias MCPheonix.MCP.{ServerManager, SimpleServer}
  alias MCPheonix.MCP.JsonRpcProtocol.{Request, Notification, Response, Error}

  @doc """
  Starts a new connection for a client.

  ## Parameters
    * `client_id` - The unique identifier for the client
    * `conn` - The Phoenix connection for the SSE stream

  ## Returns
    * `{:ok, initial_data, conn}` - A connection that is ready to stream SSE events
    * `{:error, reason, conn}` - Connection failed to start
  """
  @spec start(String.t(), Plug.Conn.t()) :: {:ok, map(), Plug.Conn.t()} | {:error, term(), Plug.Conn.t()}
  def start(client_id, conn) do
    # Register the client with the MCP server
    case SimpleServer.register_client(client_id) do
      {:ok, capabilities} ->
        # Register this process in the connection registry
        Registry.register(MCPheonix.MCP.ConnectionRegistry, client_id, %{})
        
        # Send initial capabilities as an SSE event
        initial_data = %{
          event: "capabilities",
          data: capabilities
        }
        
        Logger.info("MCP client connected: #{client_id}")
        
        {:ok, initial_data, conn}
        
      {:error, reason} ->
        Logger.error("Failed to register MCP client #{client_id}: #{inspect(reason)}")
        {:error, reason, conn}
    end
  end

  @doc """
  Ends a client connection.

  ## Parameters
    * `client_id` - The unique identifier for the client
  """
  @spec end_connection(String.t()) :: :ok
  def end_connection(client_id) do
    # Unregister from the registry
    Registry.unregister(MCPheonix.MCP.ConnectionRegistry, client_id)
    
    # Unregister from the MCP server
    SimpleServer.unregister_client(client_id)
    
    Logger.info("MCP client disconnected: #{client_id}")
    
    :ok
  end

  @doc """
  Sends a notification to a client via the SSE stream.
  This is for server-initiated notifications to a specific client's SSE stream,
  not for handling incoming JSON-RPC Notification objects.

  ## Parameters
    * `client_id` - The unique identifier for the client
    * `event_name` - The name of the SSE event (e.g., "notification", "custom_event")
    * `data` - The data payload for the SSE event
  """
  @spec send_sse_event_to_client(String.t(), String.t(), term()) :: :ok | {:error, :client_not_found}
  def send_sse_event_to_client(client_id, event_name, data) do
    case Registry.lookup(MCPheonix.MCP.ConnectionRegistry, client_id) do
      [{pid, _}] ->
        send(pid, {:sse, %{event: event_name, data: data}})
        :ok
      [] ->
        Logger.warning("Attempted to send SSE event to unknown client: #{client_id}", [])
        {:error, :client_not_found}
    end
  end

  @doc """
  Processes an incoming parsed JSON-RPC message (Request or Notification) from the client.
  This function is called by the controller after initial parsing and validation.
  """
  @spec process_message(client_id :: String.t(), parsed_struct :: Request.t() | Notification.t()) ::
          {:ok, Response.t()} | {:error, Response.t()} | :noreply
  def process_message(client_id, %Request{} = request_struct) do
    Logger.debug("Connection: Processing Request: #{inspect(request_struct)}")
    handle_rpc_request(client_id, request_struct)
  end

  def process_message(client_id, %Notification{} = notification_struct) do
    Logger.debug("Connection: Processing Notification: #{inspect(notification_struct)}")
    handle_rpc_notification(client_id, notification_struct)
  end

  # Qodo Merge Pro Suggestion: Add catch-all error handler
  # The current implementation doesn't handle the case when process_message receives an unexpected type.
  # Add a catch-all function head to handle any unexpected input.
  # For actual JSON-RPC Request structs, an error *response* would be formulated.
  # For Notifications, or unexpected data that isn't a Request, we should aim for :noreply.
  def process_message(client_id, unexpected_input) do
    Logger.error("Connection: Received unexpected input type for client '#{client_id}': #{inspect(unexpected_input)}. This is not a recognized Request or Notification struct. Returning :noreply as per notification handling principles.")
    # Since this catch-all implies it's neither a Request we can form an error response for,
    # nor a known Notification struct, we treat it as something that doesn't expect a reply.
    :noreply
  end

  # --- Private Helper Functions for RPC Handling ---

  defp handle_rpc_request(client_id, %Request{method: method, params: params, id: id}) do
    Logger.info("Handling RPC Request: method=#{method}, id=#{id}, client=#{client_id}")
    try do
      case method do
        "invoke_tool" ->
          # Basic validation for invoke_tool params (more specific validation can be in ServerManager)
          if is_map(params) and Map.has_key?(params, "server_id") and Map.has_key?(params, "tool") do
            server_id = params["server_id"]
            tool_name = params["tool"]
            tool_params = params["parameters"] # parameters might be nil or a map

            Logger.info("Routing tool execution to server '#{server_id}': #{tool_name} with params: #{inspect(tool_params)}")
            case ServerManager.execute_tool(server_id, tool_name, tool_params) do
              {:ok, result} ->
                Logger.debug("Tool execution success: #{inspect(result)}")
                {:ok, Response.new_success(result, id)}
              
              {:error, reason} -> # reason could be a simple string or a more structured map
                Logger.error("Tool execution failed for '#{tool_name}': #{inspect(reason)}")
                error_data = if is_map(reason), do: reason, else: %{reason: inspect(reason)}
                error_struct = Error.new(-32000, "Tool execution failed", error_data)
                {:error, Response.new_error(error_struct, id)}
            end
          else
            Logger.warning("Invalid params for invoke_tool: #{inspect(params)}", [])
            error_struct = Error.invalid_params(%{method: method, reason: "Missing server_id or tool in params for invoke_tool"})
            {:error, Response.new_error(error_struct, id)}
          end

        # Placeholder for other potential MCP methods if not routed to SimpleServer by default
        # "get_capabilities" -> ... 
        # "subscribe_resource" -> ...

        _other_method ->
          # Delegate to SimpleServer for other methods or generic handling
          # SimpleServer.handle_request needs to be adapted to this new flow.
          # It should return {:ok, result_data} or {:error, error_data_map_for_struct}
          Logger.debug("Delegating method '#{method}' to SimpleServer.handle_request")
          case SimpleServer.handle_request(client_id, %{method: method, params: params, id: id}) do
            {:ok, result_data} ->
              {:ok, Response.new_success(result_data, id)}
            {:error, %{code: err_code, message: err_msg, data: err_data}} ->
              error_struct = Error.new(err_code, err_msg, err_data)
              {:error, Response.new_error(error_struct, id)}
            {:error, reason_atom_or_string} when is_atom(reason_atom_or_string) or is_binary(reason_atom_or_string) ->
              # Generic internal error if SimpleServer returns a simple error
              Logger.error("SimpleServer.handle_request for '#{method}' returned generic error: #{inspect(reason_atom_or_string)}")
              error_struct = Error.internal_error(%{method: method, reason: inspect(reason_atom_or_string)})
              {:error, Response.new_error(error_struct, id)}
            # Catch-all for unexpected SimpleServer returns
            unexpected_simple_server_return ->
              Logger.error("SimpleServer.handle_request for '#{method}' returned unexpected: #{inspect(unexpected_simple_server_return)}")
              error_struct = Error.internal_error(%{method: method, reason: "Unexpected response from SimpleServer.handle_request"})
              {:error, Response.new_error(error_struct, id)}
          end
      end
    rescue
      e ->
        Logger.error("Exception in handle_rpc_request for method '#{method}': #{inspect(e)} - Backtrace: #{inspect(Process.info(self(), :current_stacktrace))}")
        error_struct = Error.internal_error(%{method: method, reason: "Server exception: #{inspect(e)}"})
        {:error, Response.new_error(error_struct, id)}
    end
  end

  defp handle_rpc_notification(client_id, %Notification{method: method, params: params}) do
    Logger.info("Handling RPC Notification: method=#{method}, client=#{client_id}")
    try do
      # Example: Route specific notifications or log them
      # For now, we'll assume SimpleServer might have a way to handle them, or we just log.
      # If SimpleServer has `handle_notification/3`, call it.
      # SimpleServer.handle_notification(client_id, method, params)
      Logger.debug("Received notification '#{method}' with params: #{inspect(params)}. No specific handler implemented in Connection module yet.")
      
      # Notifications typically don't return an error response to the client unless the notification itself is malformed
      # (which parse_message should have caught). Server-side processing errors for notifications are usually just logged.
      :noreply 
    rescue
      e ->
        Logger.error("Exception processing notification '#{method}': #{inspect(e)}")
        # Even if an exception occurs, for a notification, we usually don't send an error response back.
        # We just log it and return :noreply to the controller so it sends 204.
        :noreply
    end
  end

  # The old process_message/2 is removed as it's replaced by the multi-head functions above.

end 