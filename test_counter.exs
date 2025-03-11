#!/usr/bin/env elixir

# Mix environment setup
Mix.start()
Mix.shell(Mix.Shell.IO)

# Compile the project
Mix.Task.run("compile")

# Start all required applications
Application.ensure_all_started(:jason)
Application.ensure_all_started(:mime)
Application.ensure_all_started(:finch)
Application.ensure_all_started(:mint)
Application.ensure_all_started(:mint_web_socket)
Application.ensure_all_started(:telemetry)
Application.ensure_all_started(:cloudflare_durable)

# Configure CloudflareDurable
worker_url = System.get_env("CLOUDFLARE_WORKER_URL") || 
             raise "Please set the CLOUDFLARE_WORKER_URL environment variable"
Application.put_env(:cloudflare_durable, :worker_url, worker_url)

# Start Finch
Finch.start_link(name: CloudflareDurable.Finch)

# Generate a unique counter ID
counter_id = "counter-#{:os.system_time(:millisecond)}"
IO.puts("Using counter ID: #{counter_id}")

# Test initialize call
IO.puts("\n== Testing initialize ==")
case CloudflareDurable.initialize(counter_id, %{value: 0}) do
  {:ok, response} ->
    IO.puts("✅ Successfully initialized counter: #{inspect(response)}")
    
    # Test method call
    IO.puts("\n== Testing method_increment ==")
    Enum.each(1..3, fn i ->
      IO.puts("\nIncrementing counter (#{i}/3)...")
      case CloudflareDurable.call_method(counter_id, "method_increment", %{increment: 1}) do
        {:ok, %{"result" => %{"value" => value}}} ->
          IO.puts("✅ Counter value: #{value}")
          
        {:error, reason} ->
          IO.puts("❌ Error incrementing counter: #{inspect(reason)}")
      end
      Process.sleep(1000)
    end)
    
    # Test get_state call
    IO.puts("\n== Testing get_state ==")
    case CloudflareDurable.get_state(counter_id) do
      {:ok, state} ->
        IO.puts("✅ Final counter state: #{inspect(state)}")
        
      {:error, reason} ->
        IO.puts("❌ Error getting counter state: #{inspect(reason)}")
    end
    
  {:error, reason} ->
    IO.puts("❌ Error initializing counter: #{inspect(reason)}")
end

IO.puts("\n✨ Test complete!") 