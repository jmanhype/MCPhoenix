#!/usr/bin/env elixir

# Make sure the package is in the code path
Code.prepend_path("_build/dev/lib/cloudflare_durable/ebin")
Code.prepend_path("_build/dev/lib/jason/ebin")
Code.prepend_path("_build/dev/lib/finch/ebin")
Code.prepend_path("_build/dev/lib/mint_web_socket/ebin")
Code.prepend_path("_build/dev/lib/telemetry/ebin")
Code.prepend_path("_build/dev/lib/mint/ebin")
Code.prepend_path("_build/dev/lib/nimble_pool/ebin")
Code.prepend_path("_build/dev/lib/nimble_options/ebin")
Code.prepend_path("_build/dev/lib/castore/ebin")
Code.prepend_path("_build/dev/lib/hpax/ebin")

# Start the necessary applications
Application.ensure_all_started(:telemetry)
Application.ensure_all_started(:jason)
Application.ensure_all_started(:finch)
Application.ensure_all_started(:cloudflare_durable)

defmodule CounterExample do
  @moduledoc """
  Example showing how to use CloudflareDurable to implement a distributed counter.
  """
  
  def run do
    # Configure the worker URL
    worker_url = System.get_env("CLOUDFLARE_WORKER_URL") || 
                 raise "Please set the CLOUDFLARE_WORKER_URL environment variable"
                 
    Application.put_env(:cloudflare_durable, :worker_url, worker_url)
    
    # Generate a unique counter ID
    counter_id = "counter-#{:os.system_time(:millisecond)}"
    IO.puts("Using counter ID: #{counter_id}")
    
    # Initialize the counter with a starting value
    case CloudflareDurable.initialize(counter_id, %{value: 0}) do
      {:ok, response} ->
        IO.puts("Initialized counter: #{inspect(response)}")
        
        # Increment the counter 5 times
        Enum.each(1..5, fn i ->
          IO.puts("\nIncrementing counter (#{i}/5)...")
          case CloudflareDurable.call_method(counter_id, "method_increment", %{increment: 1}) do
            {:ok, %{"result" => %{"value" => value}}} ->
              IO.puts("Counter value: #{value}")
              
            {:error, reason} ->
              IO.puts("Error incrementing counter: #{inspect(reason)}")
          end
          
          # Pause between increments
          Process.sleep(1000)
        end)
        
        # Get final state
        case CloudflareDurable.get_state(counter_id) do
          {:ok, state} ->
            IO.puts("\nFinal counter state: #{inspect(state)}")
            
          {:error, reason} ->
            IO.puts("Error getting counter state: #{inspect(reason)}")
        end
        
      {:error, reason} ->
        IO.puts("Error initializing counter: #{inspect(reason)}")
    end
  end
end

CounterExample.run() 