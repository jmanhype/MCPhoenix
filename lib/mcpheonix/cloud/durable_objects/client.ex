defmodule MCPheonix.Cloud.DurableObjects.Client do
  @moduledoc """
  Client for interacting with Cloudflare Durable Objects.
  
  This module provides functions for communicating with Cloudflare Workers and Durable Objects,
  allowing the MCPheonix system to leverage edge-located, stateful storage and processing.
  
  This is a wrapper around the CloudflareDurable package, adding MCPheonix-specific event
  publishing and error handling.
  """
  require Logger
  alias MCPheonix.Events.Broker

  @doc """
  Initializes a new Durable Object instance.
  
  ## Parameters
    * `worker_url` - URL of the Cloudflare Worker that fronts Durable Objects
    * `object_id` - ID of the Durable Object to initialize
    * `data` - Initial data to store in the Durable Object
  
  ## Returns
    * `{:ok, response}` - Successfully initialized Durable Object
    * `{:error, reason}` - Failed to initialize Durable Object
  """
  def initialize(worker_url, object_id, data) do
    Logger.info("Initializing Durable Object: #{object_id}")
    
    case CloudflareDurable.initialize(object_id, data, worker_url: worker_url) do
      {:ok, response} ->
        # Publish event
        Broker.publish("durable_objects:initialized", %{
          object_id: object_id,
          response: response,
          timestamp: DateTime.utc_now()
        })
        
        {:ok, response}
        
      {:error, reason} = error ->
        Logger.error("Failed to initialize Durable Object: #{inspect(reason)}")
        error
    end
  end

  @doc """
  Calls a method on a Durable Object.
  
  ## Parameters
    * `worker_url` - URL of the Cloudflare Worker that fronts Durable Objects
    * `object_id` - ID of the Durable Object to call
    * `method` - Method to call on the Durable Object
    * `params` - Parameters to pass to the method
  
  ## Returns
    * `{:ok, response}` - Successfully called method on Durable Object
    * `{:error, reason}` - Failed to call method on Durable Object
  """
  def call_method(worker_url, object_id, method, params) do
    Logger.info("Calling method #{method} on Durable Object: #{object_id}")
    
    case CloudflareDurable.call_method(object_id, method, params, worker_url: worker_url) do
      {:ok, response} ->
        # Publish event
        Broker.publish("durable_objects:method_called", %{
          object_id: object_id,
          method: method,
          params: params,
          response: response,
          timestamp: DateTime.utc_now()
        })
        
        {:ok, response}
        
      {:error, reason} = error ->
        Logger.error("Failed to call method on Durable Object: #{inspect(reason)}")
        error
    end
  end

  @doc """
  Opens a WebSocket connection to a Durable Object.
  
  ## Parameters
    * `worker_url` - URL of the Cloudflare Worker that fronts Durable Objects
    * `object_id` - ID of the Durable Object to connect to
  
  ## Returns
    * `{:ok, socket}` - Successfully opened WebSocket connection
    * `{:error, reason}` - Failed to open WebSocket connection
  """
  def open_websocket(worker_url, object_id) do
    Logger.info("Opening WebSocket connection to Durable Object: #{object_id}")
    
    case CloudflareDurable.open_websocket(object_id, worker_url: worker_url) do
      {:ok, socket} ->
        # Publish event
        Broker.publish("durable_objects:websocket_opened", %{
          object_id: object_id,
          timestamp: DateTime.utc_now()
        })
        
        # Subscribe to messages
        CloudflareDurable.WebSocket.Connection.subscribe(socket)
        
        {:ok, socket}
        
      {:error, reason} = error ->
        Logger.error("Failed to open WebSocket connection to Durable Object: #{inspect(reason)}")
        error
    end
  end
end 