defmodule MCPheonixWeb.MCPController do
  @moduledoc """
  Controller for MCP communication.
  
  Handles SSE streams for server-to-client notifications and
  JSON-RPC endpoints for client-to-server requests.
  """
  use Phoenix.Controller, namespace: MCPheonixWeb
  alias MCPheonix.MCP.Server
  alias MCPheonix.Events.Broker
  require Logger

  # UUID generation for client IDs
  @doc """
  Generates a random UUID v4 for client identification.
  
  ## Returns
    * A string containing a UUID v4
  """
  def generate_client_id do
    <<u0::48, _::4, u1::12, _::2, u2::62>> = :crypto.strong_rand_bytes(16)
    <<u0::48, 4::4, u1::12, 2::2, u2::62>>
    |> Base.encode16(case: :lower)
    |> (fn <<a::8, b::8, c::8, d::8, e::8, f::8, g::8, h::8, i::8, j::8, k::8, l::8, m::8, n::8, o::8, p::8, q::8, r::8, s::8, t::8, u::8, v::8, w::8, x::8, y::8, z::8, aa::8, ab::8, ac::8, ad::8, ae::8, af::8>> ->
          <<a, b, c, d, e, f, g, h, ?-, i, j, k, l, ?-, m, n, o, p, ?-, q, r, s, t, ?-, u, v, w, x, y, z, aa, ab, ac, ad, ae, af>>
        end).()
  end

  @doc """
  Handles SSE stream connections from MCP clients.
  
  Sets up a Server-Sent Events stream for pushing notifications
  to connected MCP clients in real-time.
  
  ## Parameters
    * `conn` - The Plug connection
    * `_params` - The request parameters (unused)
  """
  def stream(conn, _params) do
    client_id = generate_client_id()
    Logger.info("New MCP client connected: #{client_id}")
    
    # Register the client with the MCP server
    {:ok, capabilities} = Server.register_client(client_id)
    
    # Set up a process to handle the SSE stream
    # This process will terminate when the client disconnects
    {:ok, client_pid} = DynamicSupervisor.start_child(
      MCPheonix.MCP.ConnectionSupervisor,
      {MCPheonix.MCP.Connection, %{client_id: client_id, conn: conn}}
    )
    
    # Monitor the client process
    Process.monitor(client_pid)
    
    # Set up the SSE stream
    conn
    |> put_resp_content_type("text/event-stream")
    |> put_resp_header("cache-control", "no-cache")
    |> put_resp_header("connection", "keep-alive")
    |> send_chunked(200)
    |> send_initialize_event(client_id, capabilities)
    |> wait_for_events(client_id)
  end

  @doc """
  Handles JSON-RPC requests from MCP clients.
  
  Processes incoming JSON-RPC requests, passes them to the MCP server,
  and returns the response.
  
  ## Parameters
    * `conn` - The Plug connection
    * `params` - The request parameters containing the JSON-RPC request
  """
  def rpc(conn, params) do
    client_id = params["client_id"] || "anonymous"
    request = params
    
    Logger.debug("Received RPC request from #{client_id}: #{inspect(request)}")
    
    # Handle the request with the MCP server
    response = Server.handle_request(client_id, request)
    
    # Return the response as JSON
    conn
    |> put_resp_content_type("application/json")
    |> send_resp(200, Jason.encode!(response))
  end

  # Private functions

  # Send the initialize event to the client
  defp send_initialize_event(conn, client_id, capabilities) do
    event = %{
      jsonrpc: "2.0",
      method: "initialize",
      params: %{
        server_info: %{
          name: "MCPheonix",
          version: "0.1.0"
        },
        capabilities: capabilities
      }
    }
    
    send_sse_event(conn, "initialize", Jason.encode!(event))
    
    # Publish client connected event
    Broker.publish("mcp:client_connected", %{
      client_id: client_id,
      timestamp: DateTime.utc_now()
    })
    
    conn
  end

  # Send an SSE event to the client
  defp send_sse_event(conn, event_name, data) do
    chunk(conn, "event: #{event_name}\ndata: #{data}\n\n")
  end

  # Wait for events to send to the client
  defp wait_for_events(conn, client_id) do
    # Subscribe to client-specific notifications
    Broker.subscribe("mcp:notifications:#{client_id}")
    
    # Keep the connection open and wait for events
    wait_for_events_loop(conn, client_id)
  end

  # Loop to wait for events to send to the client
  defp wait_for_events_loop(conn, client_id) do
    receive do
      {:event, topic, event} ->
        Logger.debug("Sending event to client #{client_id} on topic #{topic}: #{inspect(event)}")
        
        # Send the event to the client
        case send_sse_event(conn, "notification", Jason.encode!(event)) do
          {:ok, conn} ->
            # Continue waiting for events
            wait_for_events_loop(conn, client_id)
            
          {:error, reason} ->
            # Client disconnected or error occurred
            Logger.info("Client #{client_id} disconnected: #{inspect(reason)}")
            
            # Unregister the client
            Server.unregister_client(client_id)
            
            # Publish client disconnected event
            Broker.publish("mcp:client_disconnected", %{
              client_id: client_id,
              timestamp: DateTime.utc_now()
            })
            
            conn
        end
        
      {:DOWN, _ref, :process, _pid, reason} ->
        # Client process terminated
        Logger.info("Client #{client_id} process terminated: #{inspect(reason)}")
        
        # Unregister the client
        Server.unregister_client(client_id)
        
        conn
    end
  end
end 