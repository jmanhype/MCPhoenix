defmodule MCPheonix.MCP.JsonRpcClient do
  @moduledoc """
  A JSON-RPC 2.0 client for communicating with MCP servers.
  
  This module provides functionality to make JSON-RPC 2.0 requests to MCP servers,
  handling request/response cycles, error management, and proper message formatting.
  It uses the common protocol definitions from `MCPheonix.MCP.JsonRpcProtocol`.
  """

  # use Finch.Manager # Use Finch for HTTP requests - To be removed
  require Logger

  # alias MCPheonix.MCP.JsonRpcProtocol # Alias the main protocol module - This alias seems unused
  alias MCPheonix.MCP.JsonRpcProtocol.{Request, Response, Error, Notification} # Specific structs are used

  # Types are now defined in JsonRpcProtocol, but can be referenced here if needed for clarity
  # or for functions specific to client behavior.
  @type request_id :: JsonRpcProtocol.request_id()
  @type method :: JsonRpcProtocol.method()
  @type params :: JsonRpcProtocol.params()
  # ... (other types can be aliased or referred to as Protocol.<type>)
  
  @type request_options :: [
    timeout: non_neg_integer(), # Finch uses receive_timeout
    headers: [{String.t(), String.t()}],
    ssl_options: keyword() # Finch handles SSL via URL (https) and pool options
  ]

  # Struct definitions (Request, Response, Error) are now removed from here.
  # They are defined in MCPheonix.MCP.JsonRpcProtocol.

  # Helper to generate ID for client-initiated requests
  defp generate_request_id do
      :rand.uniform(999_999)
  end

  @doc """
  Makes a JSON-RPC request to the specified URL using Finch.

  ## Parameters
    * `url` - The URL to send the request to
    * `method` - The JSON-RPC method to call
    * `params` - Optional parameters for the method
    * `opts` - Optional request options

  ## Options
    * `:timeout` - Request timeout in milliseconds (default: 5000). Finch calls this `receive_timeout`.
    * `:headers` - Additional HTTP headers
    * `:ssl_options` - SSL options (Finch handles via URL and pool options)

  ## Returns
    * `{:ok, response}` - Successful response
    * `{:error, error}` - Error response or HTTP error
  """
  @spec request(String.t(), method(), params(), request_options()) :: 
    {:ok, Response.t()} | {:error, Error.t() | any()}
  def request(url, method, params \\ nil, opts \\ []) do
    req_id = generate_request_id()
    request_struct = Request.new(method, params, req_id)
    
    finch_headers = [{"content-type", "application/json"} | Keyword.get(opts, :headers, [])]
    # Finch uses receive_timeout for response reading and pool_timeout for connection acquisition.
    # We'll use the provided :timeout for receive_timeout.
    receive_timeout = Keyword.get(opts, :timeout, 5000)
    # ssl_options are typically configured at the Finch pool level, not per request.
    # Finch handles https URLs automatically.
    
    case Jason.encode(request_struct) do
      {:ok, body} ->
        Logger.debug("Sending JSON-RPC request to #{url} via Finch: #{body}")
        
        finch_request = Finch.build(:post, url, finch_headers, body)
        
        case Finch.request(finch_request, MCPheonix.Finch, receive_timeout: receive_timeout) do
          {:ok, %Finch.Response{status: 200, body: response_body}} ->
            handle_response(response_body, req_id)
            
          {:ok, %Finch.Response{status: status_code, body: error_body}} ->
            Logger.error("Finch HTTP error: #{status_code}. Body: #{inspect(error_body)}", [])
            error_struct = Error.server_error(-32000, "HTTP error: #{status_code}", %{body: error_body})
            {:error, error_struct}
            
          {:error, reason} ->
            Logger.error("Finch client error: #{inspect(reason)}", [])
            error_struct = Error.server_error(-32001, "Finch HTTP client error", %{reason: inspect(reason)})
            {:error, error_struct}
        end
        
      {:error, reason} ->
        Logger.error("Failed to encode JSON-RPC request: #{inspect(reason)}", [])
        {:error, Error.internal_error(%{reason: "JSON encoding failed"})}
    end
  end

  @doc """
  Makes a notification (a request without an ID) to the specified URL using Finch.
  
  Notifications do not expect a response beyond HTTP success.

  ## Parameters
    * `url` - The URL to send the notification to
    * `method` - The JSON-RPC method to call
    * `params` - Optional parameters for the method
    * `opts` - Optional request options

  ## Returns
    * `:ok` - Notification sent successfully
    * `{:error, error}` - Error sending notification
  """
  @spec notify(String.t(), method(), params(), request_options()) :: :ok | {:error, Error.t() | any()}
  def notify(url, method, params \\ nil, opts \\ []) do
    notification_struct = Notification.new(method, params)
    
    finch_headers = [{"content-type", "application/json"} | Keyword.get(opts, :headers, [])]
    receive_timeout = Keyword.get(opts, :timeout, 5000)
    
    case Jason.encode(notification_struct) do
      {:ok, body} ->
        Logger.debug("Sending JSON-RPC notification to #{url} via Finch: #{body}")
        
        finch_request = Finch.build(:post, url, finch_headers, body)
        
        case Finch.request(finch_request, MCPheonix.Finch, receive_timeout: receive_timeout) do
          {:ok, %Finch.Response{status: status_code}} when status_code in [200, 202, 204] ->
            :ok
          {:ok, %Finch.Response{status: status_code, body: error_body}} ->
            Logger.error("Finch HTTP error for notification: #{status_code}. Body: #{inspect(error_body)}", [])
            {:error, Error.server_error(-32000, "HTTP error for notification: #{status_code}", %{body: error_body})}
          {:error, reason} ->
            Logger.error("Finch client error for notification: #{inspect(reason)}", [])
            {:error, Error.server_error(-32001, "Finch HTTP client error for notification", %{reason: inspect(reason)})}
        end
        
      {:error, reason} ->
        Logger.error("Failed to encode JSON-RPC notification: #{inspect(reason)}", [])
        {:error, Error.internal_error(%{reason: "JSON encoding failed for notification"})}
    end
  end

  @doc """
  Handles a JSON-RPC response, validating it and converting it to a Response struct.

  ## Parameters
    * `response_body` - The raw response body (String)
    * `request_id` - The ID of the original request

  ## Returns
    * `{:ok, response}` - Valid response
    * `{:error, error}` - Invalid response or parse error
  """
  @spec handle_response(String.t(), JsonRpcProtocol.request_id()) :: {:ok, Response.t()} | {:error, Error.t()}
  def handle_response(response_body, request_id) do
    case Jason.decode(response_body) do
      {:ok, %{"jsonrpc" => "2.0", "result" => result, "id" => ^request_id} = decoded_response} ->
        if Map.has_key?(decoded_response, "error") and not is_nil(decoded_response["error"]) do
          Logger.error("JSON-RPC response has both 'result' and 'error': #{inspect(decoded_response)}", [])
          {:error, Error.invalid_request("Response has both result and error fields")}
        else
          {:ok, Response.new_success(result, request_id)}
        end
        
      {:ok, %{"jsonrpc" => "2.0", "error" => %{"code" => code, "message" => msg} = error_map, "id" => ^request_id} = decoded_response} ->
        if Map.has_key?(decoded_response, "result") and not is_nil(decoded_response["result"]) do
          Logger.error("JSON-RPC error response also has 'result': #{inspect(decoded_response)}", [])
          {:error, Error.invalid_request("Error response has result field")}
        else
          {:error, Error.new(code, msg, Map.get(error_map, "data"))}
        end
        
      {:ok, response_map} ->
        cond do
          response_map["jsonrpc"] != "2.0" ->
            Logger.error("Invalid JSON-RPC version in response: #{inspect(response_map["jsonrpc"])}", [])
            {:error, Error.invalid_request("Invalid JSON-RPC version")}
          response_map["id"] != request_id ->
            Logger.error("Mismatched ID in JSON-RPC response. Expected #{inspect(request_id)}, got #{inspect(response_map["id"])}", [])
            {:error, Error.invalid_request("Mismatched ID")}
          not (Map.has_key?(response_map, "result") || Map.has_key?(response_map, "error")) ->
            Logger.error("JSON-RPC response lacks 'result' or 'error' field: #{inspect(response_map)}", [])
            {:error, Error.invalid_request("Missing result or error field")}
          true ->
            Logger.error("Invalid or unexpected JSON-RPC response format: #{inspect(response_map)}", [])
            {:error, Error.invalid_request("Malformed response")}
        end

      {:error, decode_error} ->
        Logger.error("Failed to decode JSON-RPC response: #{inspect(decode_error)}", [])
        {:error, Error.parse_error(%{reason: "Invalid JSON in response body", details: inspect(decode_error)})}
    end
  end
end 