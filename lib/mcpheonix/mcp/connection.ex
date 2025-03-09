defmodule MCPheonix.MCP.Connection do
  @moduledoc """
  Manages MCP client connections.
  
  This module provides functionality to handle client connections and send
  server-sent events (SSE) to connected clients.
  """
  require Logger
  alias MCPheonix.MCP.SimpleServer

  @doc """
  Starts a new connection for a client.
  
  ## Parameters
    * `client_id` - The unique identifier for the client
    * `conn` - The Phoenix connection for the SSE stream
  
  ## Returns
    * `{:ok, conn}` - A connection that is ready to stream SSE events
  """
  def start(client_id, conn) do
    # Register the client with the MCP server
    case SimpleServer.register_client(client_id) do
      {:ok, capabilities} ->
        # Register this process in the connection registry
        Registry.register(MCPheonix.MCP.ConnectionRegistry, client_id, %{})
        
        # Send initial capabilities as an SSE event
        initial_data = %{
          event: "capabilities",
          data: capabilities
        }
        
        Logger.info("MCP client connected: #{client_id}")
        
        {:ok, initial_data, conn}
        
      {:error, reason} ->
        Logger.error("Failed to register MCP client #{client_id}: #{inspect(reason)}")
        {:error, reason, conn}
    end
  end

  @doc """
  Ends a client connection.
  
  ## Parameters
    * `client_id` - The unique identifier for the client
  """
  def end_connection(client_id) do
    # Unregister from the registry
    Registry.unregister(MCPheonix.MCP.ConnectionRegistry, client_id)
    
    # Unregister from the MCP server
    SimpleServer.unregister_client(client_id)
    
    Logger.info("MCP client disconnected: #{client_id}")
    
    :ok
  end

  @doc """
  Sends a notification to a client.
  
  ## Parameters
    * `client_id` - The unique identifier for the client
    * `notification` - The notification data to send
  """
  def send_notification(client_id, notification) do
    case Registry.lookup(MCPheonix.MCP.ConnectionRegistry, client_id) do
      [{pid, _}] ->
        # Send the notification to the process handling the SSE stream
        # In Phoenix, we use the send/2 function to send a message to the process
        send(pid, {:sse, %{
          event: "notification",
          data: notification
        }})
        :ok
        
      [] ->
        Logger.warning("Attempted to notify unknown client: #{client_id}")
        {:error, :client_not_found}
    end
  end

  @doc """
  Processes an incoming JSON-RPC message from the client.
  """
  def process_message(client_id, message) do
    try do
      # Parse the JSON message
      with {:ok, request} <- Jason.decode(message) do
        # Log the request
        Logger.debug("Parsed JSON-RPC request: #{inspect(request)}")
        
        # Process the request
        # Increase the timeout to 60 seconds to allow for long-running operations
        response = SimpleServer.handle_request(client_id, request)
        
        # Send the response back to the client
        {:ok, Jason.encode!(response)}
      else
        {:error, %Jason.DecodeError{}} ->
          # Handle JSON parse error
          {:error, "Invalid JSON"}
      end
    rescue
      e ->
        # Handle other errors
        Logger.error("Error processing JSON-RPC message: #{inspect(e)}")
        {:error, "Internal server error"}
    end
  end
end 