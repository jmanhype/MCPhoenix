defmodule MCPheonix.MCP.Features.Tools do
  @moduledoc """
  Simple tool implementation for the MCP protocol.
  
  This module provides functionality to expose tools through the MCP protocol,
  allowing AI models to invoke operations in the application.
  """
  require Logger

  @doc """
  Lists all available tools that can be invoked through MCP.

  ## Returns
    * A list of tool definitions
  """
  @spec list_tools() :: [map()]
  def list_tools do
    [
      %{
        name: "echo",
        description: "Echo back the input",
        parameters: [
          %{
            name: "message",
            type: "string",
            description: "Message to echo",
            required: true
          }
        ]
      },
      %{
        name: "timestamp",
        description: "Get the current timestamp",
        parameters: []
      },
      %{
        name: "random_number",
        description: "Generate a random number within a range",
        parameters: [
          %{
            name: "min",
            type: "integer",
            description: "Minimum value (inclusive)",
            required: true
          },
          %{
            name: "max",
            type: "integer",
            description: "Maximum value (inclusive)",
            required: true
          }
        ]
      },
      %{
        name: "generate",
        description: "Generate an image from a text prompt using the Flux server",
        parameters: [
          %{
            name: "prompt",
            type: "string",
            description: "Text prompt for image generation",
            required: true
          },
          %{
            name: "aspect_ratio",
            type: "string",
            description: "Aspect ratio of the output image (1:1, 4:3, 3:4, 16:9, 9:16)",
            required: false
          },
          %{
            name: "model",
            type: "string",
            description: "Model to use for generation (flux.1.1-pro, flux.1-pro, flux.1-dev, flux.1.1-ultra)",
            required: false
          },
          %{
            name: "output",
            type: "string",
            description: "Output filename",
            required: false
          }
        ]
      },
      %{
        name: "img2img",
        description: "Generate an image using another image as reference",
        parameters: [
          %{
            name: "image",
            type: "string",
            description: "Input image path",
            required: true
          },
          %{
            name: "prompt",
            type: "string",
            description: "Text prompt for generation",
            required: true
          },
          %{
            name: "name",
            type: "string",
            description: "Name for the generation",
            required: true
          },
          %{
            name: "strength",
            type: "number",
            description: "Generation strength",
            required: false
          }
        ]
      }
    ]
  end

  @doc """
  Executes a tool through MCP.

  ## Parameters
    * `tool_name` - The name of the tool to execute
    * `params` - The parameters for the tool

  ## Returns
    * `{:ok, result}` - The tool was executed successfully
    * `{:error, reason}` - The tool failed
  """
  @spec execute_tool(String.t(), map() | nil) :: {:ok, map()} | {:error, String.t()}
  def execute_tool(tool_name, params) do
    Logger.info("Executing tool: #{tool_name} with params: #{inspect(params)}")
    
    case tool_name do
      "echo" ->
        message = params["message"]
        
        if message do
          {:ok, %{
            echo: message,
            timestamp: DateTime.utc_now() |> DateTime.to_iso8601()
          }}
        else
          {:error, "Missing required parameter: message"}
        end
        
      "timestamp" ->
        {:ok, %{
          timestamp: DateTime.utc_now() |> DateTime.to_iso8601()
        }}
        
      "random_number" ->
        min = parse_integer(params["min"])
        max = parse_integer(params["max"])
        
        cond do
          is_nil(min) ->
            {:error, "Missing or invalid parameter: min"}
            
          is_nil(max) ->
            {:error, "Missing or invalid parameter: max"}
            
          min > max ->
            {:error, "Min value must be less than or equal to max value"}
            
          true ->
            random_number = :rand.uniform(max - min + 1) + min - 1
            
            {:ok, %{
              number: random_number,
              min: min,
              max: max
            }}
        end
        
      "generate" ->
        # Execute image generation via Flux server
        execute_flux_tool("generate", params)
        
      "img2img" ->
        # Execute image-to-image generation via Flux server
        execute_flux_tool("img2img", params)
        
      _ ->
        {:error, "Unknown tool: #{tool_name}"}
    end
  end

  # Private functions

  defp parse_integer(value) when is_binary(value) do
    case Integer.parse(value) do
      {int, ""} -> int
      _ -> nil
    end
  end
  
  defp parse_integer(value) when is_integer(value), do: value
  defp parse_integer(_), do: nil
  
  defp execute_flux_tool(tool, params) do
    Logger.info("Executing tool: #{tool} with params: #{inspect(params)}")
    
    try do
      case GenServer.whereis(MCPheonix.MCP.FluxServer) do
        nil ->
          Logger.error("Flux server is not running")
          {:error, "Flux server is not available"}
          
        _pid ->
          # Increase timeout to 60 seconds (60_000 ms) to allow for longer image generation
          case GenServer.call(MCPheonix.MCP.FluxServer, {:execute_tool, tool, params}, 60_000) do
            {:ok, result} ->
              # Successfully executed the tool, extract data from result
              timestamp = Map.get(result, :timestamp, DateTime.utc_now() |> DateTime.to_iso8601())
              filepath = Map.get(result, :filepath, nil)
              output = Map.get(result, :output, nil)
              
              {:ok, %{
                status: "success",
                message: "Image generated successfully",
                timestamp: timestamp,
                filepath: filepath,
                output: output
              }}
              
            {:error, reason} ->
              Logger.error("Flux server tool execution failed: #{inspect(reason)}")
              {:error, "Flux server tool execution failed: #{inspect(reason)}"}
          end
      end
    rescue
      error ->
        Logger.error("Error executing Flux tool: #{inspect(error)}")
        {:error, "Flux server tool execution failed: #{inspect(error)}"}
    end
  end
end 