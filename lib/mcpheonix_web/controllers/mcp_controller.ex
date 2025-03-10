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
    {:ok, raw_body, conn} = Plug.Conn.read_body(conn)
    
    Logger.debug("Raw request body [#{byte_size(raw_body)} bytes]: #{inspect(raw_body)}")
    
    # Process the JSON-RPC request
    response = case Jason.decode(raw_body) do
      {:ok, request} ->
        # Successfully parsed the JSON
        Logger.debug("Parsed JSON-RPC request: #{inspect(request)}")
        
        # Process the request using the MCP Connection module
        case Connection.process_message(client_id, raw_body) do
          {:ok, response_json} -> Jason.decode!(response_json)
          {:error, reason} -> 
            %{
              jsonrpc: "2.0",
              id: request["id"],
              error: %{
                code: -32000,
                message: "Internal error",
                data: %{
                  reason: reason
                }
              }
            }
        end
        
      {:error, error} ->
        # JSON parsing error
        Logger.error("JSON decode error: #{inspect(error)}")
        
        # Return a standard JSON-RPC error response
        %{
          jsonrpc: "2.0",
          id: nil,
          error: %{
            code: -32700,
            message: "Parse error",
            data: %{
              reason: "Invalid JSON",
              details: inspect(error),
              body_size: byte_size(raw_body),
              body_preview: String.slice(raw_body, 0, 100),
              first_bytes: if byte_size(raw_body) > 0 do
                  Base.encode16(:binary.part(raw_body, 0, min(10, byte_size(raw_body))))
                else
                  ""
                end
            }
          }
        }
    end
    
    # Return the response
    conn
    |> put_resp_header("x-mcp-client-id", client_id)
    |> put_resp_content_type("application/json")
    |> send_resp(200, Jason.encode!(response))
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
    
    # Send the event as a chunk
    case chunk(conn, event_data) do
      {:ok, conn} -> {:ok, conn}
      {:error, reason} -> {:error, reason}
    end
  end
  
  # Generate a unique client ID
  defp generate_client_id do
    UUID.uuid4()
  end
end 