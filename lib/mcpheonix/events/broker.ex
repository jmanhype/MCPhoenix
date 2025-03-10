defmodule MCPheonix.Events.Broker do
  @moduledoc """
  A simple event broker for publishing and subscribing to events.
  
  This module provides a central pub/sub mechanism for the application,
  allowing components to communicate asynchronously through events.
  """
  use GenServer
  require Logger

  # Client API

  @doc """
  Starts the event broker.
  """
  def start_link(_opts) do
    GenServer.start_link(__MODULE__, [], name: __MODULE__)
  end

  @doc """
  Publishes an event to a topic.
  
  ## Parameters
    * `topic` - The topic to publish to
    * `data` - The event data to publish
  """
  def publish(topic, data) do
    Logger.debug("Publishing event to topic #{topic}: #{inspect(data)}")
    Phoenix.PubSub.broadcast(MCPheonix.PubSub, topic, {:event, topic, data})
    :ok
  end

  @doc """
  Subscribes to a topic.
  
  ## Parameters
    * `topic` - The topic to subscribe to
  """
  def subscribe(topic) do
    Logger.debug("Subscribing to topic: #{topic}")
    Phoenix.PubSub.subscribe(MCPheonix.PubSub, topic)
    :ok
  end

  @doc """
  Unsubscribes from a topic.
  
  ## Parameters
    * `topic` - The topic to unsubscribe from
  """
  def unsubscribe(topic) do
    Logger.debug("Unsubscribing from topic: #{topic}")
    Phoenix.PubSub.unsubscribe(MCPheonix.PubSub, topic)
    :ok
  end

  # Server callbacks

  @impl true
  def init(_) do
    Logger.info("Event broker started")
    {:ok, %{}}
  end
end 