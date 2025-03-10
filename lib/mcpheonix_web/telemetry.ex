defmodule MCPheonixWeb.Telemetry do
  @moduledoc """
  Telemetry metrics for the MCPheonix application.
  
  This module defines the metrics and telemetry events that are tracked
  by the application, enabling monitoring and observability.
  """
  use Supervisor
  import Telemetry.Metrics

  def start_link(arg) do
    Supervisor.start_link(__MODULE__, arg, name: __MODULE__)
  end

  @impl true
  def init(_arg) do
    children = [
      # Telemetry poller
      {:telemetry_poller, measurements: periodic_measurements(), period: 10_000}
    ]

    Supervisor.init(children, strategy: :one_for_one)
  end

  def metrics do
    [
      # Phoenix Metrics
      summary("phoenix.endpoint.start.system_time",
        unit: {:native, :millisecond}
      ),
      summary("phoenix.endpoint.stop.duration",
        unit: {:native, :millisecond}
      ),
      summary("phoenix.router_dispatch.start.system_time",
        tags: [:route],
        unit: {:native, :millisecond}
      ),
      summary("phoenix.router_dispatch.exception.duration",
        tags: [:route],
        unit: {:native, :millisecond}
      ),
      summary("phoenix.router_dispatch.stop.duration",
        tags: [:route],
        unit: {:native, :millisecond}
      ),
      summary("phoenix.socket_connected.duration",
        unit: {:native, :millisecond}
      ),
      summary("phoenix.channel_joined.duration",
        unit: {:native, :millisecond}
      ),
      summary("phoenix.channel_handled_in.duration",
        tags: [:event],
        unit: {:native, :millisecond}
      ),

      # MCP Metrics
      counter("mcpheonix.mcp.client_connections.count"),
      counter("mcpheonix.mcp.rpc_requests.count"),
      summary("mcpheonix.mcp.rpc_requests.duration",
        unit: {:native, :millisecond}
      ),
      counter("mcpheonix.mcp.notifications.count"),
      
      # Event Broker Metrics
      counter("mcpheonix.events.published.count"),
      counter("mcpheonix.events.subscriptions.count"),
      
      # VM Metrics
      summary("vm.memory.total", unit: {:byte, :kilobyte}),
      summary("vm.total_run_queue_lengths.total"),
      summary("vm.total_run_queue_lengths.cpu"),
      summary("vm.total_run_queue_lengths.io")
    ]
  end

  defp periodic_measurements do
    [
      # Only VM metrics for now
      # A function returning the measurement
      {__MODULE__, :vm_memory_measurement, []}
    ]
  end

  @doc """
  Reports VM memory usage.
  """
  def vm_memory_measurement do
    memory = :erlang.memory()
    total = memory[:total]
    
    :telemetry.execute(
      [:vm, :memory],
      %{total: total},
      %{}
    )
  end
end 