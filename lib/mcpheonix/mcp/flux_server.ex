defmodule MCPheonix.MCP.FluxServer do
  @moduledoc """
  Integration with the Flux MCP server for image generation capabilities.

  This module provides functionality to interact with the Flux server
  which offers image generation tools.
  """
  use GenServer
  require Logger

  # Configuration
  @flux_server_path "/Users/speed/Documents/Cline/MCP/flux-server/build/index.js"
  @flux_dir "/Users/speed/CascadeProjects/flux"
  @virtual_env "/Users/speed/CascadeProjects/flux/.venv"
  @python_path "#{@virtual_env}/bin/python"
  @bfl_api_key "47932f45-9b3d-4283-b525-92cca5a54f28"
  @optional true # Set to true to make Flux server optional (won't crash the app if unavailable)

  # Environment variables for Flux CLI
  @flux_env %{
    "BFL_API_KEY" => @bfl_api_key,
    "VIRTUAL_ENV" => @virtual_env,
    "PATH" => "#{@virtual_env}/bin:/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin",
    "PYTHONPATH" => @flux_dir
  }

  # Client API

  @doc """
  Starts the Flux server connection.
  """
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Gets the Flux server path.
  """
  def get_server_path do
    @flux_server_path
  end

  @doc """
  Checks if the Flux server is running.
  """
  def is_running? do
    case GenServer.whereis(__MODULE__) do
      nil -> false
      _pid -> GenServer.call(__MODULE__, :is_running?)
    end
  end

  @doc """
  Starts the Flux server if it's not already running.
  """
  def ensure_running do
    case GenServer.whereis(__MODULE__) do
      nil -> {:error, :not_started}
      _pid -> GenServer.call(__MODULE__, :ensure_running)
    end
  end

  @doc """
  Execute a tool on the Flux server.
  """
  def execute_tool(tool_name, params) do
    case GenServer.whereis(__MODULE__) do
      nil -> {:error, :flux_server_not_available}
      _pid -> GenServer.call(__MODULE__, {:execute_tool, tool_name, params}, 60_000)
    end
  end

  # Server callbacks

  @impl true
  def init(_opts) do
    # We're now using direct CLI execution with appropriate environment variables
    if flux_available?() do
      Logger.info("Flux CLI is available at #{@flux_dir}")
      {:ok, %{
        running: true,
        capabilities: nil,
      }}
    else
      Logger.warning("Flux CLI not available at #{@flux_dir}")
      if @optional do
        # Start with empty state if Flux server is optional
        {:ok, %{
          running: false,
          capabilities: nil
        }}
      else
        # Fail to start the GenServer if Flux server is required
        {:stop, {:shutdown, "Flux CLI not available"}}
      end
    end
  rescue
    exception ->
      Logger.error("Error initializing Flux server: #{inspect(exception)}")
      if @optional do
        {:ok, %{running: false, capabilities: nil}}
      else
        {:stop, exception}
      end
  end

  @impl true
  def handle_call(:is_running?, _from, state) do
    is_running = state.running && flux_available?()
    {:reply, is_running, %{state | running: is_running}}
  end

  @impl true
  def handle_call(:ensure_running, _from, %{running: true} = state) do
    if flux_available?() do
      {:reply, :ok, state}
    else
      {:reply, {:error, "Flux CLI not available"}, %{state | running: false}}
    end
  end

  @impl true
  def handle_call(:ensure_running, _from, state) do
    if flux_available?() do
      {:reply, :ok, %{state | running: true}}
    else
      {:reply, {:error, "Flux CLI not available"}, state}
    end
  end

  @impl true
  def handle_call({:execute_tool, tool_name, params}, _from, %{running: true} = state) do
    case execute_flux_cli(tool_name, params) do
      {:ok, output, filepath} ->
        Logger.info("Successfully executed Flux CLI: #{tool_name}")
        {:reply, {:ok, %{
          output: output,
          filepath: filepath,
          timestamp: DateTime.utc_now() |> DateTime.to_iso8601()
        }}, state}
        
      {:error, reason} ->
        Logger.error("Flux CLI execution failed: #{inspect(reason)}")
        {:reply, {:error, reason}, state}
    end
  end

  @impl true
  def handle_call({:execute_tool, tool_name, params}, from, %{running: false} = state) do
    if flux_available?() do
      new_state = %{state | running: true}
      # Forward the call now that we have it running
      handle_call({:execute_tool, tool_name, params}, from, new_state)
    else
      {:reply, {:error, "Flux CLI not available"}, state}
    end
  end

  # This handles unexpected messages
  @impl true
  def handle_info(message, state) do
    Logger.debug("Unexpected message received by FluxServer: #{inspect(message)}")
    {:noreply, state}
  end

  # Private functions

  defp flux_available? do
    # Check if the Flux CLI directory exists
    File.dir?(@flux_dir) && File.exists?(Path.join(@flux_dir, "fluxcli.py"))
  end

  defp create_output_path(generation_type, filename) do
    # Create date-based directory structure similar to what the Flux server does
    now = DateTime.utc_now()
    date_str = now |> Calendar.strftime("%Y-%m-%d")
    time_str = now |> Calendar.strftime("%H%M%S")
    
    # Get file extension from original filename or default to .jpg
    ext = Path.extname(filename)
    ext = if ext == "", do: ".jpg", else: ext
    
    base_name = Path.basename(filename, ext)
    
    # Create output directory
    home_dir = System.get_env("HOME") || "/Users/speed"
    output_base_dir = Path.join(home_dir, "Pictures/flux-generations")
    dir_path = Path.join([output_base_dir, generation_type, date_str])
    
    # Ensure directory exists
    File.mkdir_p!(dir_path)
    
    # Create filename with timestamp
    new_filename = "#{base_name}_#{time_str}#{ext}"
    relative_path = Path.join([generation_type, date_str, new_filename])
    absolute_path = Path.join(output_base_dir, relative_path)
    
    {relative_path, absolute_path}
  end

  defp open_file(filepath) do
    # Check if file exists
    if File.exists?(filepath) do
      # Use 'open' on macOS, 'xdg-open' on Linux, or 'start' on Windows
      cmd = case :os.type() do
        {:unix, :darwin} -> "open"
        {:unix, _} -> "xdg-open"
        {:win32, _} -> "start"
      end
      
      System.cmd(cmd, [filepath], stderr_to_stdout: true)
      :ok
    else
      {:error, "File not found: #{filepath}"}
    end
  end

  defp execute_flux_cli("generate", params) do
    # Build command arguments
    args = ["fluxcli.py", "generate"]
    
    # Add prompt
    args = args ++ ["--prompt", params["prompt"]]
    
    # Add optional parameters
    args = if Map.has_key?(params, "model"), do: args ++ ["--model", params["model"]], else: args
    args = if Map.has_key?(params, "aspect_ratio"), do: args ++ ["--aspect-ratio", params["aspect_ratio"]], else: args
    args = if Map.has_key?(params, "width"), do: args ++ ["--width", to_string(params["width"])], else: args
    args = if Map.has_key?(params, "height"), do: args ++ ["--height", to_string(params["height"])], else: args
    
    # Create output path
    {_relative_path, absolute_path} = create_output_path("text-to-image", params["output"] || "generated.jpg")
    args = args ++ ["--output", absolute_path]
    
    # Execute command with proper environment variables
    Logger.info("Executing Flux CLI: #{@python_path} #{Enum.join(args, " ")}")
    
    # Merge process environment with our Flux environment
    env = Map.merge(System.get_env(), @flux_env)
    
    case System.cmd(@python_path, args, cd: @flux_dir, stderr_to_stdout: true, env: env) do
      {output, 0} ->
        # Open the generated image
        open_file(absolute_path)
        {:ok, output, absolute_path}
        
      {error, code} ->
        {:error, "Flux CLI failed with code #{code}: #{error}"}
    end
  rescue
    e -> {:error, "Exception executing Flux CLI: #{inspect(e)}"}
  end

  defp execute_flux_cli("img2img", params) do
    # Build command arguments
    args = ["fluxcli.py", "img2img"]
    
    # Add required parameters
    args = args ++ ["--image", params["image"]]
    args = args ++ ["--prompt", params["prompt"]]
    args = args ++ ["--name", params["name"]]
    
    # Add optional parameters
    args = if Map.has_key?(params, "model"), do: args ++ ["--model", params["model"]], else: args
    args = if Map.has_key?(params, "strength"), do: args ++ ["--strength", to_string(params["strength"])], else: args
    args = if Map.has_key?(params, "width"), do: args ++ ["--width", to_string(params["width"])], else: args
    args = if Map.has_key?(params, "height"), do: args ++ ["--height", to_string(params["height"])], else: args
    
    # Create output path
    {_relative_path, absolute_path} = create_output_path("img2img", params["output"] || "generated.jpg")
    args = args ++ ["--output", absolute_path]
    
    # Execute command with proper environment variables
    Logger.info("Executing Flux CLI: #{@python_path} #{Enum.join(args, " ")}")
    
    # Merge process environment with our Flux environment
    env = Map.merge(System.get_env(), @flux_env)
    
    case System.cmd(@python_path, args, cd: @flux_dir, stderr_to_stdout: true, env: env) do
      {output, 0} ->
        # Open the generated image
        open_file(absolute_path)
        {:ok, output, absolute_path}
        
      {error, code} ->
        {:error, "Flux CLI failed with code #{code}: #{error}"}
    end
  rescue
    e -> {:error, "Exception executing Flux CLI: #{inspect(e)}"}
  end
end 