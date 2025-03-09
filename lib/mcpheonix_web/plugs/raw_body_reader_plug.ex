defmodule MCPheonixWeb.RawBodyReaderPlug do
  @moduledoc """
  A custom body reader plug that allows reading the request body
  and storing it for later use, especially for JSON-RPC requests.
  
  This helps address issues with JSON parsing by ensuring the
  raw body is preserved and can be accessed by controllers.
  """
  require Logger
  import Plug.Conn

  @doc """
  Custom body reader function for Plug.Parsers.
  
  This function allows us to read the request body once,
  store it in the connection, and make it available for
  both parsers and controllers.
  """
  def read_body(conn, opts) do
    # First, check if this is an MCP RPC request that we want to handle manually
    if is_mcp_rpc?(conn) do
      # Read the body
      case Plug.Conn.read_body(conn, opts) do
        {:ok, body, conn} ->
          Logger.debug("RawBodyReaderPlug: Read body: #{inspect(body)}")
          # Store the body in conn private
          conn = put_private(conn, :raw_body, body)
          # Return the body so parsers can still use it if needed
          {:ok, body, conn}
        
        other ->
          # Pass through any other response from read_body
          other
      end
    else
      # For all other requests, use the default read_body
      Plug.Conn.read_body(conn, opts)
    end
  end
  
  # Detect if this is an MCP RPC request that should bypass standard parsing
  defp is_mcp_rpc?(conn) do
    conn.path_info == ["mcp", "rpc"] && conn.method == "POST"
  end
end 