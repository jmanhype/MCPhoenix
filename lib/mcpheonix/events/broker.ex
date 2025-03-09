defmodule MCPheonix.Events.Broker do
  @moduledoc """
  Event broker for the MCPheonix system.
  
  This module provides a centralized event system for publishing and subscribing to events.
  It acts as the backbone for the distributed event system, allowing components to
  communicate without direct dependencies.
  """
  use GenServer
  require Logger

  # Client API

  @doc """
  Starts the event broker.
  """
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Publishes an event to a topic.
  
  ## Parameters
    * `topic` - The topic to publish the event to
    * `event` - The event data
  """
  def publish(topic, event) do
    GenServer.cast(__MODULE__, {:publish, topic, event})
  end

  @doc """
  Subscribes the calling process to events from a topic.
  
  ## Parameters
    * `topic` - The topic to subscribe to
  """
  def subscribe(topic) do
    GenServer.call(__MODULE__, {:subscribe, topic, self()})
  end

  @doc """
  Unsubscribes the calling process from events from a topic.
  
  ## Parameters
    * `topic` - The topic to unsubscribe from
  """
  def unsubscribe(topic) do
    GenServer.cast(__MODULE__, {:unsubscribe, topic, self()})
  end

  # Server callbacks

  @impl true
  def init(_opts) do
    # Initialize state with empty subscribers map
    {:ok, %{subscribers: %{}}}
  end

  @impl true
  def handle_call({:subscribe, topic, pid}, _from, state) do
    Logger.debug("Process #{inspect(pid)} subscribing to topic: #{topic}")
    
    # Add process to subscribers for the topic
    subscribers = Map.update(
      state.subscribers,
      topic,
      [pid],
      fn pids -> [pid | pids] |> Enum.uniq() end
    )
    
    # Monitor the subscriber so we can clean up if it terminates
    Process.monitor(pid)
    
    {:reply, :ok, %{state | subscribers: subscribers}}
  end

  @impl true
  def handle_cast({:publish, topic, event}, state) do
    Logger.debug("Publishing event to topic: #{topic}")
    
    # Get subscribers for the topic
    topic_subscribers = Map.get(state.subscribers, topic, [])
    
    # Notify each subscriber
    for pid <- topic_subscribers do
      send(pid, {:event, topic, event})
    end
    
    {:noreply, state}
  end

  @impl true
  def handle_cast({:unsubscribe, topic, pid}, state) do
    Logger.debug("Process #{inspect(pid)} unsubscribing from topic: #{topic}")
    
    # Remove process from subscribers for the topic
    subscribers = Map.update(
      state.subscribers,
      topic,
      [],
      fn pids -> Enum.reject(pids, fn p -> p == pid end) end
    )
    
    {:noreply, %{state | subscribers: subscribers}}
  end

  @impl true
  def handle_info({:DOWN, _ref, :process, pid, reason}, state) do
    Logger.debug("Subscriber #{inspect(pid)} went down: #{inspect(reason)}")
    
    # Remove the terminated process from all topics
    subscribers = Enum.map(state.subscribers, fn {topic, pids} ->
      {topic, Enum.reject(pids, fn p -> p == pid end)}
    end)
    |> Enum.into(%{})
    
    {:noreply, %{state | subscribers: subscribers}}
  end
end 