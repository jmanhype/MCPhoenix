defmodule MCPheonix.MCP.JsonRpcClient do
  @moduledoc """
  A JSON-RPC 2.0 client for communicating with MCP servers.
  
  This module provides functionality to make JSON-RPC 2.0 requests to MCP servers,
  handling request/response cycles, error management, and proper message formatting.
  """

  require Logger
  alias MCPheonix.MCP.JsonRpcClient.{Request, Response, Error}

  @type request_id :: String.t() | integer()
  @type method :: String.t()
  @type params :: map() | list() | nil
  @type result :: map() | list() | String.t() | number() | boolean() | nil
  @type error_code :: integer()
  @type error_message :: String.t()
  @type error_data :: map() | nil
  
  @type request_options :: [
    timeout: non_neg_integer(),
    headers: [{String.t(), String.t()}],
    ssl_options: keyword()
  ]

  defmodule Request do
    @moduledoc """
    Represents a JSON-RPC 2.0 request.
    """
    
    @type t :: %__MODULE__{
      jsonrpc: String.t(),
      method: String.t(),
      params: map() | list() | nil,
      id: String.t() | integer() | nil
    }
    
    defstruct [:jsonrpc, :method, :params, :id]
    
    @spec new(String.t(), map() | list() | nil, String.t() | integer() | nil) :: t()
    def new(method, params \\ nil, id \\ nil) do
      %__MODULE__{
        jsonrpc: "2.0",
        method: method,
        params: params,
        id: id || generate_id()
      }
    end
    
    @spec generate_id() :: integer()
    defp generate_id do
      :rand.uniform(999_999)
    end
  end

  defmodule Response do
    @moduledoc """
    Represents a JSON-RPC 2.0 response.
    """
    
    @type t :: %__MODULE__{
      jsonrpc: String.t(),
      result: map() | list() | String.t() | number() | boolean() | nil,
      error: Error.t() | nil,
      id: String.t() | integer() | nil
    }
    
    defstruct [:jsonrpc, :result, :error, :id]
    
    @spec new(map() | list() | String.t() | number() | boolean() | nil, String.t() | integer() | nil) :: t()
    def new(result, id) do
      %__MODULE__{
        jsonrpc: "2.0",
        result: result,
        id: id
      }
    end
  end

  defmodule Error do
    @moduledoc """
    Represents a JSON-RPC 2.0 error.
    """
    
    @type t :: %__MODULE__{
      code: integer(),
      message: String.t(),
      data: map() | nil
    }
    
    defstruct [:code, :message, :data]
    
    # Standard JSON-RPC 2.0 error codes
    @parse_error -32700
    @invalid_request -32600
    @method_not_found -32601
    @invalid_params -32602
    @internal_error -32603
    @server_error_start -32000
    @server_error_end -32099
    
    @spec new(integer(), String.t(), map() | nil) :: t()
    def new(code, message, data \\ nil) do
      %__MODULE__{
        code: code,
        message: message,
        data: data
      }
    end
    
    @spec parse_error(String.t() | nil) :: t()
    def parse_error(data \\ nil), do: new(@parse_error, "Parse error", data)
    
    @spec invalid_request(String.t() | nil) :: t()
    def invalid_request(data \\ nil), do: new(@invalid_request, "Invalid Request", data)
    
    @spec method_not_found(String.t() | nil) :: t()
    def method_not_found(data \\ nil), do: new(@method_not_found, "Method not found", data)
    
    @spec invalid_params(String.t() | nil) :: t()
    def invalid_params(data \\ nil), do: new(@invalid_params, "Invalid params", data)
    
    @spec internal_error(String.t() | nil) :: t()
    def internal_error(data \\ nil), do: new(@internal_error, "Internal error", data)
    
    @spec server_error(integer(), String.t(), map() | nil) :: t()
    def server_error(code, message, data \\ nil) when code >= @server_error_start and code <= @server_error_end do
      new(code, message, data)
    end
  end

  @doc """
  Makes a JSON-RPC request to the specified URL.

  ## Parameters
    * `url` - The URL to send the request to
    * `method` - The JSON-RPC method to call
    * `params` - Optional parameters for the method
    * `opts` - Optional request options

  ## Options
    * `:timeout` - Request timeout in milliseconds (default: 5000)
    * `:headers` - Additional HTTP headers
    * `:ssl_options` - SSL options for HTTPS requests

  ## Returns
    * `{:ok, response}` - Successful response
    * `{:error, error}` - Error response or HTTP error
  """
  @spec request(String.t(), method(), params(), request_options()) :: 
    {:ok, Response.t()} | {:error, Error.t() | any()}
  def request(url, method, params \\ nil, opts \\ []) do
    request = Request.new(method, params)
    
    headers = [{"content-type", "application/json"} | Keyword.get(opts, :headers, [])]
    timeout = Keyword.get(opts, :timeout, 5000)
    ssl_options = Keyword.get(opts, :ssl_options, [])
    
    case Jason.encode(request) do
      {:ok, body} ->
        Logger.debug("Sending JSON-RPC request to #{url}: #{body}")
        
        case HTTPoison.post(url, body, headers, [timeout: timeout, ssl: ssl_options]) do
          {:ok, %HTTPoison.Response{status_code: 200, body: response_body}} ->
            handle_response(response_body, request.id)
            
          {:ok, %HTTPoison.Response{status_code: status_code}} ->
            error = Error.server_error(-32000, "HTTP error: #{status_code}")
            {:error, error}
            
          {:error, %HTTPoison.Error{reason: reason}} ->
            error = Error.server_error(-32001, "HTTP client error: #{inspect(reason)}")
            {:error, error}
        end
        
      {:error, reason} ->
        Logger.error("Failed to encode JSON-RPC request: #{inspect(reason)}")
        {:error, Error.internal_error("JSON encoding failed")}
    end
  end

  @doc """
  Makes a notification (a request without an ID) to the specified URL.
  
  Notifications do not expect a response.

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
    request = %Request{
      jsonrpc: "2.0",
      method: method,
      params: params,
      id: nil
    }
    
    headers = [{"content-type", "application/json"} | Keyword.get(opts, :headers, [])]
    timeout = Keyword.get(opts, :timeout, 5000)
    ssl_options = Keyword.get(opts, :ssl_options, [])
    
    case Jason.encode(request) do
      {:ok, body} ->
        Logger.debug("Sending JSON-RPC notification to #{url}: #{body}")
        
        case HTTPoison.post(url, body, headers, [timeout: timeout, ssl: ssl_options]) do
          {:ok, %HTTPoison.Response{status_code: 200}} -> :ok
          {:ok, %HTTPoison.Response{status_code: status_code}} ->
            {:error, Error.server_error(-32000, "HTTP error: #{status_code}")}
          {:error, %HTTPoison.Error{reason: reason}} ->
            {:error, Error.server_error(-32001, "HTTP client error: #{inspect(reason)}")}
        end
        
      {:error, reason} ->
        Logger.error("Failed to encode JSON-RPC notification: #{inspect(reason)}")
        {:error, Error.internal_error("JSON encoding failed")}
    end
  end

  @doc """
  Handles a JSON-RPC response, validating it and converting it to a Response struct.

  ## Parameters
    * `response_body` - The raw response body
    * `request_id` - The ID of the original request

  ## Returns
    * `{:ok, response}` - Valid response
    * `{:error, error}` - Invalid response or parse error
  """
  @spec handle_response(String.t(), request_id()) :: {:ok, Response.t()} | {:error, Error.t()}
  def handle_response(response_body, request_id) do
    case Jason.decode(response_body) do
      {:ok, %{"jsonrpc" => "2.0", "result" => result, "id" => ^request_id}} ->
        {:ok, Response.new(result, request_id)}
        
      {:ok, %{"jsonrpc" => "2.0", "error" => %{"code" => code, "message" => msg} = error, "id" => ^request_id}} ->
        {:error, Error.new(code, msg, Map.get(error, "data"))}
        
      {:ok, response} ->
        Logger.error("Invalid JSON-RPC response format: #{inspect(response)}")
        {:error, Error.invalid_request()}
        
      {:error, reason} ->
        Logger.error("Failed to decode JSON-RPC response: #{inspect(reason)}")
        {:error, Error.parse_error()}
    end
  end
end 