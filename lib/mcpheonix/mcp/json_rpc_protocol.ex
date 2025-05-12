# Intentionally empty for now. Structs and functions will be added in subsequent steps. 

defmodule MCPheonix.MCP.JsonRpcProtocol do
  @moduledoc """
  Defines core structures and helpers for JSON-RPC 2.0 messages.

  This module provides common definitions for requests, responses, notifications,
  and errors according to the JSON-RPC 2.0 specification.
  """

  @type request_id :: String.t() | integer() | nil # nil is allowed for id in requests if server allows
  @type method :: String.t()
  @type params :: map() | list() | nil
  @type result :: map() | list() | String.t() | number() | boolean() | nil
  @type error_code :: integer()
  @type error_message :: String.t()
  @type error_data :: map() | list() | String.t() | number() | boolean() | nil # More flexible error data

  defmodule Request do
    @moduledoc """
    Represents a JSON-RPC 2.0 Request object.
    """
    @derive Jason.Encoder
    @type t :: %__MODULE__{
            jsonrpc: String.t(),
            method: MCPheonix.MCP.JsonRpcProtocol.method(),
            params: MCPheonix.MCP.JsonRpcProtocol.params(),
            id: MCPheonix.MCP.JsonRpcProtocol.request_id()
          }
    defstruct [:jsonrpc, :method, :params, :id]

    @doc """
    Creates a new JSON-RPC Request.
    The `id` should be unique for concurrent requests if a response is expected.
    It can be nil for notifications if not using the separate Notification struct.
    """
    @spec new(MCPheonix.MCP.JsonRpcProtocol.method(), MCPheonix.MCP.JsonRpcProtocol.params(), MCPheonix.MCP.JsonRpcProtocol.request_id()) :: t()
    def new(method, params \\ nil, id) do
      %__MODULE__{
        jsonrpc: "2.0",
        method: method,
        params: params,
        id: id
      }
    end
  end

  defmodule Notification do
    @moduledoc """
    Represents a JSON-RPC 2.0 Notification object (a Request object without an "id" member).
    """
    @derive Jason.Encoder
    @type t :: %__MODULE__{
            jsonrpc: String.t(),
            method: MCPheonix.MCP.JsonRpcProtocol.method(),
            params: MCPheonix.MCP.JsonRpcProtocol.params()
          }
    defstruct [:jsonrpc, :method, :params]

    @doc """
    Creates a new JSON-RPC Notification.
    """
    @spec new(MCPheonix.MCP.JsonRpcProtocol.method(), MCPheonix.MCP.JsonRpcProtocol.params()) :: t()
    def new(method, params \\ nil) do
      %__MODULE__{
        jsonrpc: "2.0",
        method: method,
        params: params
      }
    end
  end

  defmodule Response do
    @moduledoc """
    Represents a JSON-RPC 2.0 Response object.
    """
    @derive Jason.Encoder
    @type t :: %__MODULE__{
            jsonrpc: String.t(),
            result: MCPheonix.MCP.JsonRpcProtocol.result() | nil, # result is nil if error is present
            error: MCPheonix.MCP.JsonRpcProtocol.Error.t() | nil,  # error is nil if result is present
            id: MCPheonix.MCP.JsonRpcProtocol.request_id() # Can be nil if the request id was nil (e.g. parse error before id known)
          }
    defstruct [:jsonrpc, :result, :error, :id]

    @doc """
    Creates a new successful JSON-RPC Response.
    """
    @spec new_success(MCPheonix.MCP.JsonRpcProtocol.result(), MCPheonix.MCP.JsonRpcProtocol.request_id()) :: t()
    def new_success(result, id) do
      %__MODULE__{
        jsonrpc: "2.0",
        result: result,
        error: nil,
        id: id
      }
    end

    @doc """
    Creates a new error JSON-RPC Response.
    """
    @spec new_error(MCPheonix.MCP.JsonRpcProtocol.Error.t(), MCPheonix.MCP.JsonRpcProtocol.request_id()) :: t()
    def new_error(error_struct, id) do
      %__MODULE__{
        jsonrpc: "2.0",
        result: nil,
        error: error_struct,
        id: id
      }
    end
  end

  defmodule Error do
    @moduledoc """
    Represents a JSON-RPC 2.0 Error object.
    """
    @derive Jason.Encoder
    @type t :: %__MODULE__{
            code: MCPheonix.MCP.JsonRpcProtocol.error_code(),
            message: MCPheonix.MCP.JsonRpcProtocol.error_message(),
            data: MCPheonix.MCP.JsonRpcProtocol.error_data()
          }
    defstruct [:code, :message, :data]

    # Standard JSON-RPC 2.0 error codes
    @parse_error -32700
    @invalid_request -32600
    @method_not_found -32601
    @invalid_params -32602
    @internal_error -32603
    # -32000 to -32099: Server error. Reserved for implementation-defined server-errors.

    @doc """
    Creates a new Error struct.
    """
    @spec new(MCPheonix.MCP.JsonRpcProtocol.error_code(), MCPheonix.MCP.JsonRpcProtocol.error_message(), MCPheonix.MCP.JsonRpcProtocol.error_data()) :: t()
    def new(code, message, data \\ nil) do
      %__MODULE__{
        code: code,
        message: message,
        data: data
      }
    end

    @doc """
    Error structure for Parse error (-32700).
    """
    @spec parse_error(MCPheonix.MCP.JsonRpcProtocol.error_data()) :: t()
    def parse_error(data \\ nil), do: new(@parse_error, "Parse error", data)

    @doc """
    Error structure for Invalid Request (-32600).
    """
    @spec invalid_request(MCPheonix.MCP.JsonRpcProtocol.error_data()) :: t()
    def invalid_request(data \\ nil), do: new(@invalid_request, "Invalid Request", data)

    @doc """
    Error structure for Method not found (-32601).
    """
    @spec method_not_found(MCPheonix.MCP.JsonRpcProtocol.error_data()) :: t()
    def method_not_found(data \\ nil), do: new(@method_not_found, "Method not found", data)

    @doc """
    Error structure for Invalid params (-32602).
    """
    @spec invalid_params(MCPheonix.MCP.JsonRpcProtocol.error_data()) :: t()
    def invalid_params(data \\ nil), do: new(@invalid_params, "Invalid params", data)

    @doc """
    Error structure for Internal error (-32603).
    """
    @spec internal_error(MCPheonix.MCP.JsonRpcProtocol.error_data()) :: t()
    def internal_error(data \\ nil), do: new(@internal_error, "Internal error", data)

    @doc """
    Error structure for server-defined errors (-32000 to -32099).
    """
    @spec server_error(integer(), String.t(), MCPheonix.MCP.JsonRpcProtocol.error_data()) :: t()
    def server_error(code, message, data \\ nil) when code >= -32099 and code <= -32000 do
      new(code, message, data)
    end
  end

  @doc """
  Parses a JSON string into a JSON-RPC Request or Notification struct.
  Performs basic validation against the JSON-RPC 2.0 specification.
  """
  @spec parse_message(String.t()) ::
          {:ok, Request.t() | Notification.t()} | {:error, Error.t()}
  def parse_message(json_string) when is_binary(json_string) do
    case Jason.decode(json_string) do
      {:ok, decoded_map} when is_map(decoded_map) ->
        validate_structure(decoded_map)
      {:error, reason} ->
        {:error, Error.parse_error(%{reason: "Invalid JSON", details: inspect(reason)})}
      _ -> # Jason.decode returned :ok but not with a map, or some other unexpected value
        {:error, Error.parse_error(%{reason: "Invalid JSON structure, expected a JSON object."})}
    end
  end

  defp validate_structure(map) do
    # 1. Check "jsonrpc" version
    if Map.get(map, "jsonrpc") != "2.0" do
      {:error, Error.invalid_request(%{reason: "Missing or invalid 'jsonrpc' member. Must be '2.0'."})}
    else
      # 2. Check "method"
      method = Map.get(map, "method")
      if not (is_binary(method) and String.length(method) > 0) do
        {:error, Error.invalid_request(%{reason: "Missing or invalid 'method' member. Must be a non-empty string."})}
      else
        # 3. Check "params" (if present)
        params = Map.get(map, "params")
        case params do
          nil ->
            # Params are optional, proceed to ID check
            validate_id_and_create_struct(map, method, params)
          val when is_map(val) or is_list(val) ->
            # Params are valid, proceed to ID check
            validate_id_and_create_struct(map, method, params)
          _ ->
            {:error, Error.invalid_params(%{reason: "'params' member, if present, must be a structured value (object or array)."})}
        end
      end
    end
  end

  defp validate_id_and_create_struct(map, method, params) do
    id_value = Map.get(map, "id")

    cond do
      Map.has_key?(map, "id") ->
        # "id" key is present, validate it
        is_valid_id = is_binary(id_value) or is_integer(id_value) or is_number(id_value) or is_nil(id_value)
        if is_valid_id do
          {:ok, %Request{jsonrpc: "2.0", method: method, params: params, id: id_value}}
        else
          {:error, Error.invalid_request(%{reason: "'id' member, if present, must be a String, Number, or null."})}
        end

      true ->
        # "id" key is not present, so it's a Notification
        {:ok, %Notification{jsonrpc: "2.0", method: method, params: params}}
    end
  end
end 