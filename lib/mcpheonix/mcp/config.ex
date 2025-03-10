defmodule MCPheonix.MCP.Config do
  @moduledoc """
  Configuration module for MCP servers.
  
  This module handles loading and validating MCP server configurations from JSON files
  or environment variables.
  """
  
  require Logger
  
  @type server_config :: %{
    command: String.t(),
    args: list(String.t()),
    env: %{String.t() => String.t()},
    tools: %{String.t() => map()},
    auto_approve: list(String.t()) | nil
  }
  
  @type server_configs :: %{String.t() => server_config()}
  
  @doc """
  Load MCP server configurations.
  
  ## Returns
    * `{:ok, configs}` - Successfully loaded configurations
    * `{:error, reason}` - Failed to load configurations
  """
  @spec load_configs() :: {:ok, server_configs()} | {:error, term()}
  def load_configs do
    config_path = Path.join([:code.priv_dir(:mcpheonix), "config", "mcp_servers.json"])
    
    case File.read(config_path) do
      {:ok, json} ->
        case Jason.decode(json) do
          {:ok, %{"mcpServers" => servers}} ->
            # Convert string keys to atoms for each server config
            configs = Enum.map(servers, fn {server_id, config} ->
              # Transform tools and parameters from arrays to maps
              tools = Enum.map(config["tools"] || %{}, fn {tool_name, tool_config} ->
                # Convert parameters array to map keyed by parameter name
                parameters = if is_list(tool_config["parameters"]) do
                  Enum.reduce(tool_config["parameters"], %{}, fn param, acc ->
                    param_name = param["name"]
                    # Create parameter definition with type and description
                    param_def = %{
                      "type" => param["type"],
                      "description" => param["description"]
                    }
                    Map.put(acc, param_name, param_def)
                  end)
                else
                  tool_config["parameters"] || %{}
                end
                
                # Create updated tool config with mapped parameters
                {tool_name, Map.put(tool_config, "parameters", parameters)}
              end)
              |> Map.new()
              
              Logger.info("Configured tools for server #{server_id}: #{inspect(Map.keys(tools))}")
              
              {server_id, %{
                command: config["command"],
                args: config["args"] || [],
                env: config["env"] || %{},
                tools: tools,
                auto_approve: config["autoApprove"] || []
              }}
            end)
            |> Map.new()
            
            {:ok, configs}
            
          {:ok, _} ->
            {:error, "Invalid configuration format: missing mcpServers key"}
            
          {:error, reason} ->
            {:error, "Failed to parse JSON configuration: #{inspect(reason)}"}
        end
        
      {:error, reason} ->
        {:error, "Failed to read configuration file: #{inspect(reason)}"}
    end
  end
  
  @doc """
  Validate a server configuration.
  
  ## Parameters
    * `config` - The server configuration to validate
    
  ## Returns
    * `:ok` - Configuration is valid
    * `{:error, reason}` - Configuration is invalid
  """
  @spec validate_config(server_config()) :: :ok | {:error, term()}
  def validate_config(config) when is_map(config) do
    required_keys = [:command, :args]
    
    case Enum.all?(required_keys, &Map.has_key?(config, &1)) do
      true -> :ok
      false -> {:error, "Missing required configuration keys"}
    end
  end
  
  @doc """
  Get the configuration for a specific server.
  
  ## Parameters
    * `server_id` - The ID of the server to get configuration for
    
  ## Returns
    * `{:ok, config}` - Successfully retrieved configuration
    * `{:error, reason}` - Failed to retrieve configuration
  """
  @spec get_server_config(String.t()) :: {:ok, server_config()} | {:error, term()}
  def get_server_config(server_id) do
    with {:ok, configs} <- load_configs(),
         config when not is_nil(config) <- Map.get(configs, server_id) do
      {:ok, config}
    else
      nil -> {:error, "Server configuration not found"}
      error -> error
    end
  end
end 