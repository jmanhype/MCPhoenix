defmodule MCPheonix.MCP.Connection do
  @moduledoc """
  Module for managing individual MCP client connections.
  
  This module is responsible for handling the lifecycle of a client connection,
  including monitoring the connection status and cleaning up when the connection is closed.
  """
  use GenServer
  require Logger
  alias MCPheonix.Events.Broker
  alias MCPheonix.MCP.Server

  # Client API

  @doc """
  Starts a new MCP client connection process.
  
  ## Parameters
    * `args` - Map containing client_id and conn
  """
  def start_link(args) do
    GenServer.start_link(__MODULE__, args, name: via_tuple(args.client_id))
  end

  @doc """
  Sends a notification to a client.
  
  ## Parameters
    * `client_id` - The ID of the client to notify
    * `notification` - The notification to send
  """
  def send_notification(client_id, notification) do
    case Registry.lookup(MCPheonix.MCP.ConnectionRegistry, client_id) do
      [{pid, _}] ->
        GenServer.cast(pid, {:send_notification, notification})
      [] ->
        {:error, :client_not_found}
    end
  end

  # Server callbacks

  @impl true
  def init(args) do
    client_id = args.client_id
    
    Logger.info("Initializing MCP connection for client: #{client_id}")
    
    # Subscribe to relevant event topics for this client
    Broker.subscribe("mcp:notifications:#{client_id}")
    
    # Register the connection with the registry
    {:ok, %{client_id: client_id, last_activity: DateTime.utc_now()}}
  end

  @impl true
  def handle_cast({:send_notification, notification}, state) do
    client_id = state.client_id
    
    Logger.debug("Sending notification to client #{client_id}: #{inspect(notification)}")
    
    # This would normally send the notification to the client's SSE stream
    # But in this architecture, the MCPController handles the actual sending
    # So we publish to the broker instead
    Broker.publish("mcp:notifications:#{client_id}", notification)
    
    {:noreply, %{state | last_activity: DateTime.utc_now()}}
  end

  @impl true
  def handle_info({:event, topic, event}, state) do
    Logger.debug("Connection received event on topic #{topic}: #{inspect(event)}")
    
    # Process the event - in this example, we're just logging it
    # In a real implementation, you might update local state or perform some action
    
    {:noreply, state}
  end

  @impl true
  def terminate(reason, state) do
    client_id = state.client_id
    
    Logger.info("MCP connection for client #{client_id} terminated: #{inspect(reason)}")
    
    # Clean up - unsubscribe from topics
    Broker.unsubscribe("mcp:notifications:#{client_id}")
    
    # Unregister the client
    Server.unregister_client(client_id)
    
    :ok
  end

  # Private functions

  defp via_tuple(client_id) do
    {:via, Registry, {MCPheonix.MCP.ConnectionRegistry, client_id}}
  end
end 