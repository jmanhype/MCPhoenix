defmodule CloudflareDurable.WebSocket.Connection do
  @moduledoc """
  WebSocket connection to a Durable Object.
  
  This module manages a WebSocket connection to a Cloudflare Durable Object,
  handling reconnection, message sending, and event handling.
  """
  use GenServer
  require Logger
  alias MintWebSocket

  @reconnect_msg :reconnect
  @default_backoff_initial 500
  @default_backoff_max 30000

  # Client API

  @doc """
  Starts a WebSocket connection to a Durable Object.
  
  ## Parameters
    * `object_id` - ID of the Durable Object to connect to
    * `opts` - Connection options:
      * `:url` - WebSocket URL
      * `:auto_reconnect` - Whether to automatically reconnect (default: true)
      * `:backoff_initial` - Initial backoff time in ms (default: 500)
      * `:backoff_max` - Maximum backoff time in ms (default: 30000)
  """
  def start_link([object_id, opts]) do
    GenServer.start_link(__MODULE__, {object_id, opts})
  end

  @doc """
  Sends a message over the WebSocket connection.
  
  ## Parameters
    * `pid` - PID of the connection process
    * `message` - Message to send (will be JSON encoded)
  
  ## Returns
    * `:ok` - Message sent successfully
    * `{:error, reason}` - Failed to send message
  """
  def send_message(pid, message) do
    GenServer.call(pid, {:send_message, message})
  end

  @doc """
  Subscribes to messages from the WebSocket connection.
  
  ## Parameters
    * `pid` - PID of the connection process
  
  ## Returns
    * `:ok` - Subscription successful
  """
  def subscribe(pid) do
    GenServer.call(pid, {:subscribe, self()})
  end

  @doc """
  Unsubscribes from messages from the WebSocket connection.
  
  ## Parameters
    * `pid` - PID of the connection process
  
  ## Returns
    * `:ok` - Unsubscription successful
  """
  def unsubscribe(pid) do
    GenServer.call(pid, {:unsubscribe, self()})
  end

  # Server Callbacks

  @impl true
  def init({object_id, opts}) do
    url = Keyword.fetch!(opts, :url)
    auto_reconnect = Keyword.get(opts, :auto_reconnect, true)
    backoff_initial = Keyword.get(opts, :backoff_initial, @default_backoff_initial)
    backoff_max = Keyword.get(opts, :backoff_max, @default_backoff_max)

    state = %{
      object_id: object_id,
      url: url,
      auto_reconnect: auto_reconnect,
      backoff_initial: backoff_initial,
      backoff_max: backoff_max,
      backoff_current: backoff_initial,
      ws_conn: nil,
      subscribers: MapSet.new(),
      connected: false
    }

    # Start connection process
    send(self(), :connect)

    {:ok, state}
  end

  @impl true
  def handle_call({:send_message, _message}, _from, %{ws_conn: nil} = state) do
    {:reply, {:error, :not_connected}, state}
  end

  @impl true
  def handle_call({:send_message, message}, _from, %{ws_conn: ws_conn} = state) do
    json = Jason.encode!(message)
    result = MintWebSocket.send(ws_conn, {:text, json})
    {:reply, result, state}
  end

  @impl true
  def handle_call({:subscribe, pid}, _from, state) do
    Process.monitor(pid)
    {:reply, :ok, %{state | subscribers: MapSet.put(state.subscribers, pid)}}
  end

  @impl true
  def handle_call({:unsubscribe, pid}, _from, state) do
    {:reply, :ok, %{state | subscribers: MapSet.delete(state.subscribers, pid)}}
  end

  @impl true
  def handle_info(:connect, state) do
    Logger.debug("Connecting to WebSocket: #{state.url}")

    case MintWebSocket.connect(state.url, []) do
      {:ok, conn} ->
        Logger.debug("Connected to Durable Object WebSocket: #{state.object_id}")
        :telemetry.execute([:cloudflare_durable, :websocket, :connected], %{}, %{object_id: state.object_id})
        
        # Reset backoff on successful connection
        {:noreply, %{state | ws_conn: conn, connected: true, backoff_current: state.backoff_initial}}

      {:error, reason} ->
        Logger.error("Failed to connect to Durable Object WebSocket: #{inspect(reason)}")
        :telemetry.execute([:cloudflare_durable, :error], %{count: 1}, %{
          reason: :websocket_connection_error,
          object_id: state.object_id
        })
        
        # Schedule reconnect if enabled
        if state.auto_reconnect do
          Process.send_after(self(), @reconnect_msg, state.backoff_current)
          
          # Increase backoff for next attempt (with max limit)
          next_backoff = min(state.backoff_current * 2, state.backoff_max)
          {:noreply, %{state | backoff_current: next_backoff}}
        else
          {:noreply, state}
        end
    end
  end

  @impl true
  def handle_info(@reconnect_msg, state) do
    send(self(), :connect)
    {:noreply, state}
  end

  @impl true
  def handle_info({:websocket, conn, message}, %{ws_conn: conn} = state) do
    case message do
      {:text, text} ->
        case Jason.decode(text) do
          {:ok, decoded} ->
            broadcast_message(decoded, state.subscribers)
            {:noreply, state}
            
          {:error, reason} ->
            Logger.error("Failed to decode WebSocket message: #{inspect(reason)}")
            :telemetry.execute([:cloudflare_durable, :error], %{count: 1}, %{
              reason: :websocket_decode_error,
              object_id: state.object_id
            })
            {:noreply, state}
        end
        
      {:close, code, reason} ->
        Logger.info("WebSocket closed: code=#{code}, reason=#{reason}")
        :telemetry.execute([:cloudflare_durable, :websocket, :disconnected], %{}, %{
          object_id: state.object_id,
          code: code,
          reason: reason
        })
        
        if state.auto_reconnect do
          Process.send_after(self(), @reconnect_msg, state.backoff_current)
        end
        
        {:noreply, %{state | ws_conn: nil, connected: false}}
        
      _ ->
        {:noreply, state}
    end
  end

  @impl true
  def handle_info({:DOWN, _ref, :process, pid, _reason}, state) do
    # Remove subscriber if it went down
    {:noreply, %{state | subscribers: MapSet.delete(state.subscribers, pid)}}
  end

  # Private functions
  
  defp broadcast_message(message, subscribers) do
    Enum.each(subscribers, fn pid ->
      send(pid, {:durable_object_message, message})
    end)
  end
end 