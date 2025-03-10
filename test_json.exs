#!/usr/bin/env elixir

# Load the Mix environment to access dependencies
Mix.start()
Mix.shell(Mix.Shell.Process)

# Test JSON decoding
{:ok, _} = Application.ensure_all_started(:jason)

json_string = ~s({"jsonrpc":"2.0","method":"initialize","id":1})

IO.puts("Testing JSON string: #{json_string}")

case Jason.decode(json_string) do
  {:ok, data} ->
    IO.puts("Successfully decoded:")
    IO.inspect(data, pretty: true)
    
  {:error, error} ->
    IO.puts("Error decoding:")
    IO.inspect(error, pretty: true)
end

# Test with a file
File.write!("test.json", json_string)
file_content = File.read!("test.json")

IO.puts("\nFile content: #{file_content}")

case Jason.decode(file_content) do
  {:ok, data} ->
    IO.puts("Successfully decoded from file:")
    IO.inspect(data, pretty: true)
    
  {:error, error} ->
    IO.puts("Error decoding from file:")
    IO.inspect(error, pretty: true)
end 