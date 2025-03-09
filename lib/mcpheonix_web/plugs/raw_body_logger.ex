defmodule MCPheonixWeb.RawBodyLogger do
  @moduledoc """
  A plug that logs the raw request body for debugging purposes.
  
  This is especially useful for diagnosing JSON parsing issues.
  """
  require Logger
  import Plug.Conn

  def init(opts), do: opts

  def call(conn, _opts) do
    # Only process JSON requests to the MCP endpoint
    if json_request?(conn) && mcp_rpc_path?(conn) do
      {:ok, body, conn} = read_body(conn)
      
      # Log the raw body with special attention to the first few bytes
      if byte_size(body) > 0 do
        first_byte = :binary.part(body, {0, 1})
        Logger.debug("Raw request body (first byte: #{inspect(first_byte, base: :hex)}): #{inspect(body)}")
        
        # Check for any non-printable or special characters at the start
        if byte_size(body) >= 4 do
          first_bytes = :binary.part(body, {0, 4})
          Logger.debug("First 4 bytes: #{inspect(first_bytes, base: :hex)}")
        end
      else
        Logger.debug("Empty request body")
      end
      
      # Put the body back so it can be read again by the JSON parser
      conn = put_private(conn, :raw_body, body)
      conn
    else
      conn
    end
  end
  
  # Helpers to determine if this is a JSON request to the MCP RPC endpoint
  defp json_request?(conn) do
    case get_req_header(conn, "content-type") do
      ["application/json" <> _] -> true
      _ -> false
    end
  end
  
  defp mcp_rpc_path?(conn) do
    conn.request_path == "/mcp/rpc"
  end
end 