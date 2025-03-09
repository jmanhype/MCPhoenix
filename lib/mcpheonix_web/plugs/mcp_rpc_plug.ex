defmodule MCPheonixWeb.Plugs.MCPRpcPlug do
  @moduledoc """
  A plug that directly handles Model Context Protocol (MCP) JSON-RPC requests.
  
  This plug bypasses the usual Phoenix parsers and controllers to directly
  read and handle the raw request body for the MCP RPC endpoint.
  """
  import Plug.Conn
  require Logger
  alias MCPheonix.MCP.Connection

  def init(opts), do: opts

  def call(conn, _opts) do
    # Only handle POST requests to the MCP RPC endpoint
    if conn.method == "POST" && conn.path_info == ["mcp", "rpc"] do
      handle_rpc(conn)
    else
      # For all other paths, continue the plug pipeline
      conn
    end
  end

  defp handle_rpc(conn) do
    # Generate a unique client ID or use the one from headers
    client_id = get_req_header(conn, "x-mcp-client-id")
      |> List.first()
      |> case do
        nil -> UUID.uuid4()
        id -> id
      end
      
    # Read the request body
    {:ok, body, conn} = read_body(conn)
    
    # Log the raw request
    Logger.debug("MCPRpcPlug: Raw request body [#{byte_size(body)} bytes]: #{inspect(body)}")
    
    # Process the JSON-RPC request
    response = case Jason.decode(body) do
      {:ok, request} ->
        # Successfully parsed the JSON
        Logger.debug("MCPRpcPlug: Parsed JSON-RPC request: #{inspect(request)}")
        
        # Process the request using the MCP Connection module
        case Connection.process_message(client_id, body) do
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
        Logger.error("MCPRpcPlug: JSON decode error: #{inspect(error)}")
        
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
              body_size: byte_size(body),
              body_preview: if byte_size(body) > 0 do 
                String.slice(body, 0, 100) 
                else 
                  "" 
                end,
              first_bytes: if byte_size(body) > 0 do
                  Base.encode16(:binary.part(body, 0, min(10, byte_size(body))))
                else
                  ""
                end
            }
          }
        }
    end
    
    # Return the JSON-RPC response
    conn
    |> put_resp_header("x-mcp-client-id", client_id)
    |> put_resp_content_type("application/json")
    |> send_resp(200, Jason.encode!(response))
    |> halt() # Stop the plug pipeline
  end
end 