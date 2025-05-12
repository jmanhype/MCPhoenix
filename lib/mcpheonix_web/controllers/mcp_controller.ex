defmodule MCPheonixWeb.MCPController do
  @moduledoc """
  Controller for Model Context Protocol (MCP) endpoints.
  
  This controller handles:
  1. Server-Sent Events (SSE) stream for server->client notifications
  2. JSON-RPC endpoint for client->server requests
  """
  use Phoenix.Controller, namespace: MCPheonixWeb
  require Logger
  alias MCPheonix.MCP.Connection
  alias MCPheonix.MCP.JsonRpcProtocol
  alias MCPheonix.MCP.JsonRpcProtocol.{Request, Notification, Response, Error}
  
  # Import Kernel for binary_part/2
  import Kernel, except: [to_string: 1]

  @doc """
  Establishes a Server-Sent Events (SSE) stream for MCP notifications.
  
  This creates a persistent connection that allows the server to push
  notifications to the client in real-time.
  """
  def stream(conn, _params) do
    # Generate a unique client ID for this connection
    client_id = generate_client_id()
    
    # Configure the connection for SSE
    conn = conn
      |> put_resp_content_type("text/event-stream")
      |> put_resp_header("cache-control", "no-cache")
      |> put_resp_header("connection", "keep-alive")
      |> send_chunked(200)
    
    # Start the MCP client connection
    case Connection.start(client_id, conn) do
      {:ok, initial_data, conn} ->
        # Send the initial capabilities event
        send_sse_event(conn, initial_data.event, initial_data.data)
        
        # Enter the SSE loop
        sse_loop(conn, client_id)
        
      {:error, _reason, conn} ->
        # Return an error response
        conn
        |> put_status(500)
        |> json(%{error: "Failed to establish MCP connection"})
    end
  end

  @doc """
  Handles JSON-RPC requests from MCP clients.
  
  This endpoint processes client requests and returns responses according
  to the JSON-RPC 2.0 specification.
  """
  def rpc(conn, _params) do
    # Read the client ID from request headers or generate a new one
    client_id = get_req_header(conn, "x-mcp-client-id")
      |> List.first()
      |> case do
        nil -> generate_client_id()
        id -> id
      end
      
    # Read the request directly from the connection request
    {:ok, raw_body, conn_after_read_body} = Plug.Conn.read_body(conn)
    
    Logger.debug("RPC: Raw request body [#{byte_size(raw_body)} bytes]: #{inspect(raw_body)}")
    
    # Parse and validate the JSON-RPC message using the protocol module
    case JsonRpcProtocol.parse_message(raw_body) do
      {:ok, %Request{} = parsed_request} -> # It's a Request
        Logger.debug("RPC: Parsed Request: #{inspect(parsed_request)}")
        # Process the parsed request
        # Connection.process_message will now take client_id and the parsed_struct
        # and is expected to return {:ok, response_struct} or {:error, error_response_struct}
        case Connection.process_message(client_id, parsed_request) do
          {:ok, %Response{} = success_response} ->
            Logger.debug("RPC: Sending success response: #{inspect(success_response)}")
            conn_after_read_body
            |> put_resp_header("x-mcp-client-id", client_id)
            |> put_resp_content_type("application/json")
            |> send_resp(200, Jason.encode!(success_response))

          {:error, %Response{} = error_response} -> # Error during processing, already a Response struct
            Logger.debug("RPC: Sending error response from processing: #{inspect(error_response)}")
            conn_after_read_body
            |> put_resp_header("x-mcp-client-id", client_id)
            |> put_resp_content_type("application/json")
            |> send_resp(200, Jason.encode!(error_response)) # Send JSON-RPC error with HTTP 200
          
          # Catch-all for unexpected returns from Connection.process_message for Requests
          other_outcome -> 
            Logger.error("RPC: Unexpected outcome from Connection.process_message for Request: #{inspect(other_outcome)}")
            internal_error_response = Response.new_error(Error.internal_error("Server error processing request"), parsed_request.id)
            conn_after_read_body
            |> put_resp_header("x-mcp-client-id", client_id)
            |> put_resp_content_type("application/json")
            |> send_resp(200, Jason.encode!(internal_error_response))
        end

      {:ok, %Notification{} = parsed_notification} -> # It's a Notification
        Logger.debug("RPC: Parsed Notification: #{inspect(parsed_notification)}")
        # Process the parsed notification
        # Connection.process_message for notifications is expected to return :noreply.
        # If it deviates or raises an error, higher-level error handling will catch it.
        case Connection.process_message(client_id, parsed_notification) do
          :noreply ->
            Logger.debug("RPC: Notification processed, sending 204 No Content.")
            conn_after_read_body
            |> put_resp_header("x-mcp-client-id", client_id)
            |> send_resp(204, "")

          # Qodo Merge Pro Suggestion: Proper error response handling
          # Changed to align with JSON-RPC: notifications are fire-and-forget.
          # If an internal error occurs processing a notification, log it, but still return 204.
          unexpected_outcome ->
            Logger.error("RPC: Unexpected outcome from Connection.process_message for Notification: #{inspect(unexpected_outcome)}. Sending 204 No Content as per JSON-RPC notification handling.", [])
            # Even if server-side processing of a notification has an issue,
            # for the client, the notification was 'received'.
            conn_after_read_body
            |> put_resp_header("x-mcp-client-id", client_id)
            |> send_resp(204, "") # Send 204 No Content
        end

      {:error, %Error{} = error_from_parser} -> # Error from JsonRpcProtocol.parse_message
        Logger.warning("RPC: Invalid JSON-RPC message: #{inspect(error_from_parser)}", [])
        # The ID might not be determinable for parse errors. Defaulting to nil.
        # For Invalid Request, an ID might have been part of the (malformed) request but parse_message doesn't return it with the error struct currently.
        error_response = Response.new_error(error_from_parser, nil) 
        conn_after_read_body
    |> put_resp_header("x-mcp-client-id", client_id)
    |> put_resp_content_type("application/json")
        |> send_resp(200, Jason.encode!(error_response)) # Send JSON-RPC error with HTTP 200
    end
  end

  # Private functions

  # Main SSE event loop
  defp sse_loop(conn, client_id) do
    receive do
      {:sse, %{event: event, data: data}} ->
        # Send the SSE event to the client
        case send_sse_event(conn, event, data) do
          {:ok, conn} ->
            # Continue the loop
            sse_loop(conn, client_id)
            
          {:error, _reason} ->
            # Connection closed, clean up
            Connection.end_connection(client_id)
            conn
        end
        
      {:send_event, event, data} ->
        Logger.info("Received direct :send_event for #{event}, forwarding to client.")
        case send_sse_event(conn, event, data) do
          {:ok, conn_after_send} ->
            sse_loop(conn_after_send, client_id)
          {:error, _reason} ->
            # Connection closed, clean up
            Connection.end_connection(client_id)
            # If send_sse_event fails, conn hasn't changed.
            # If it failed due to closed connection, returning conn is fine as the loop will exit.
            conn
        end
        
      other ->
        Logger.warning("Unexpected message in SSE loop: #{inspect(other)}")
        sse_loop(conn, client_id)
    after
      # Keep-alive ping every 30 seconds
      30_000 ->
        case send_sse_event(conn, "ping", %{timestamp: DateTime.utc_now()}) do
          {:ok, conn} ->
            # Continue the loop
            sse_loop(conn, client_id)
            
          {:error, _reason} ->
            # Connection closed, clean up
            Connection.end_connection(client_id)
            conn
        end
    end
  end
  
  # Send an SSE event to the client
  defp send_sse_event(conn, event, data) do
    # Format the SSE event
    event_data = "event: #{event}\ndata: #{Jason.encode!(data)}\n\n"
    Logger.debug("SSE: Attempting to send event '#{event}' with data: #{event_data}")
    
    # Send the event as a chunk
    case chunk(conn, event_data) do
      {:ok, new_conn} -> 
        Logger.debug("SSE: Chunk sent successfully for event '#{event}'.")
        {:ok, new_conn}
      {:error, reason} -> 
        Logger.error("SSE: Failed to send chunk for event '#{event}'. Reason: #{inspect(reason)}")
        {:error, reason}
    end
  end
  
  # Generate a unique client ID
  defp generate_client_id do
    UUID.uuid4()
  end
end 