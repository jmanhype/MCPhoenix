defmodule CloudflareDurable.MockWebSocket do
  @moduledoc """
  Mock module for testing WebSocket connections.
  """
  
  def connect(_url, _opts) do
    {:ok, :mock_websocket_connection}
  end
  
  def send(_conn, _message) do
    :ok
  end
end 