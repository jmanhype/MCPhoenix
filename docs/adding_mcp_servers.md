# Adding MCP Servers to MCPheonix

This guide explains how to add new Model Context Protocol (MCP) servers to the MCPheonix application.

## Overview

MCPheonix acts as an MCP host that can connect to multiple MCP servers, each providing different capabilities. Following the [Model Context Protocol](https://modelcontextprotocol.io/introduction) architecture, MCPheonix:

1. Spawns and manages MCP server processes
2. Routes client requests to the appropriate server
3. Returns responses back to clients

Adding a new MCP server involves:
- Creating or obtaining the MCP server implementation
- Configuring the server in MCPheonix
- Defining the tools the server provides
- Testing the integration

## Server Configuration

### 1. Configuration File

All MCP servers are configured in the `priv/config/mcp_servers.json` file. Each server has its own configuration section identified by a unique `server_id`.

Here's the basic structure:

```json
{
  "mcpServers": {
    "your_server_id": {
      "command": "/path/to/executable",
      "args": ["/path/to/server/script.js"],
      "env": {
        "ENV_VAR1": "value1",
        "ENV_VAR2": "value2"
      },
      "autoApprove": ["tool1", "tool2"],
      "tools": {
        "tool1": {
          "description": "Description of tool1",
          "parameters": [
            {
              "name": "param1",
              "type": "string",
              "description": "Description of param1",
              "required": true
            },
            // Additional parameters...
          ]
        },
        // Additional tools...
      }
    }
  }
}
```

### 2. Configuration Options

- `command`: The executable to run (e.g., `/usr/bin/node`, `/usr/bin/python`)
- `args`: Array of command-line arguments to pass to the command
- `env`: Environment variables to set for the server process
- `autoApprove`: List of tools that don't require user approval
- `tools`: Map of available tools with their parameters
- `disabled` (optional): Set to `true` to disable the server without removing it

### 3. Defining Tools

Each tool requires:

- A unique name (the key in the tools object)
- A description explaining what the tool does
- A list of parameters the tool accepts

Each parameter requires:

- `name`: The parameter name
- `type`: The data type (`string`, `number`, `boolean`, `array`, `object`)
- `description`: A description of the parameter
- `required`: Whether the parameter is required (`true` or `false`)

Example:

```json
"get_weather": {
  "description": "Get the current weather for a location",
  "parameters": [
    {
      "name": "location",
      "type": "string",
      "description": "City name or coordinates",
      "required": true
    },
    {
      "name": "units",
      "type": "string",
      "description": "Units system (metric, imperial)",
      "required": false
    }
  ]
}
```

## Implementation Details

### Communication Protocols

MCPheonix supports two transport protocols for communicating with MCP servers:

1. **stdio** (Standard Input/Output): The default protocol where MCPheonix spawns the server as a child process and communicates via stdin/stdout. All JSON-RPC messages are sent line by line.

2. **HTTP**: For servers that expose an HTTP endpoint. This is less common but can be useful for servers running on different machines.

The configuration for each approach is slightly different:

#### stdio Configuration

```json
"example_server": {
  "command": "/path/to/executable",
  "args": ["/path/to/script.js"],
  "env": { ... }
}
```

#### HTTP Configuration

```json
"example_http_server": {
  "url": "http://localhost:3000",
  "transport": "http",
  "tools": { ... }
}
```

### Server Process Management

When MCPheonix starts, it:

1. Loads the server configurations from `priv/config/mcp_servers.json`
2. For each enabled server, starts the server process using the specified command and args
3. Sends an initialization request to get the server's capabilities
4. Stores the available tools for later use

When a tool is invoked:

1. MCPheonix routes the request to the appropriate server based on the `server_id`
2. It transforms the request to the MCP format using the method `tools/call`
3. It sends the request to the server and waits for a response
4. When the response is received, it forwards it back to the client

### Elixir Implementation Details

The MCPheonix application uses Elixir's process model to manage MCP servers efficiently:

#### Key Modules

1. **`MCPheonix.MCP.ServerManager`** (`lib/mcpheonix/mcp/server_manager.ex`):
   - A GenServer that starts and manages all MCP server processes
   - Routes tool invocations to the correct server
   - Called by the web controller when a client makes a request

2. **`MCPheonix.MCP.ServerProcess`** (`lib/mcpheonix/mcp/server_process.ex`):
   - A GenServer that manages a single MCP server process
   - Uses Erlang's `Port` module to spawn and communicate with the OS process
   - Handles JSON-RPC messaging with the MCP server
   - Implements the MCP client protocol

3. **`MCPheonix.MCP.Config`** (`lib/mcpheonix/mcp/config.ex`):
   - Loads and parses the server configurations
   - Converts JSON configurations to internal Elixir structures

4. **`MCPheonixWeb.MCPController`** (`lib/mcphoenix_web/controllers/mcp_controller.ex`):
   - Handles HTTP endpoints for client requests
   - Manages SSE streams for notifications
   - Routes client requests to the ServerManager

#### Process Flow

```
Client Request
    ↓
MCPController (Phoenix controller)
    ↓
ServerManager (routes to appropriate server)
    ↓
ServerProcess (manages OS process communication)
    ↓
MCP Server (OS process running Node.js, Python, etc.)
```

#### Extending with Custom Logic

To implement special behavior for a specific server, you can:

1. **Add Server-Specific Logic** - Modify the `ServerProcess` to handle specific servers differently:

```elixir
# In server_process.ex
additional_tools = case state.server_id do
  "your_server_id" ->
    # Custom tool definitions for your server
    %{
      "custom_tool" => %{
        "description" => "Your custom tool",
        "parameters" => %{
          "param1" => %{"description" => "Parameter 1", "type" => "string"}
        }
      }
    }
  
  # Other server IDs...
end
```

2. **Custom Request Preprocessing** - Transform parameters before sending to a server:

```elixir
# In a custom handler module
def preprocess_params(server_id, tool, params) do
  case server_id do
    "your_server_id" ->
      # Modify params before sending to the server
      transformed_params = do_transform(params)
      {:ok, transformed_params}
      
    _ ->
      {:ok, params}  # No changes for other servers
  end
end
```

3. **Custom Response Handling** - Process responses specially for certain servers:

```elixir
# In a custom handler module
def postprocess_response(server_id, tool, response) do
  case server_id do
    "your_server_id" ->
      # Transform response from this server
      transformed = transform_response(response)
      {:ok, transformed}
      
    _ ->
      {:ok, response}  # No changes for other servers
  end
end
```

### Example: Extending for Custom Logic

Here's a simplified example of adding a custom handler for a specific server:

```elixir
# lib/mcpheonix/mcp/custom_handler.ex
defmodule MCPheonix.MCP.CustomHandler do
  @moduledoc """
  Custom handler for special MCP server processing.
  """
  
  require Logger
  
  @doc """
  Preprocess parameters for specific server types.
  """
  def preprocess_params("special_server", "complex_tool", params) do
    # Special handling for this tool
    Logger.debug("Preprocessing params for special_server complex_tool")
    
    # Example: Add timestamp to params
    params = Map.put(params, "timestamp", DateTime.utc_now() |> DateTime.to_iso8601())
    
    {:ok, params}
  end
  
  def preprocess_params(_server_id, _tool, params), do: {:ok, params}
  
  @doc """
  Process responses from specific servers.
  """
  def postprocess_response("special_server", _tool, response) do
    # Process response from special server
    Logger.debug("Processing response from special_server")
    
    case response do
      %{"content" => content} when is_list(content) ->
        # Add metadata to the response
        enhanced = %{
          "content" => content,
          "metadata" => %{
            "processed_by" => "custom_handler",
            "timestamp" => DateTime.utc_now() |> DateTime.to_iso8601()
          }
        }
        {:ok, enhanced}
        
      _ ->
        {:ok, response}
    end
  end
  
  def postprocess_response(_server_id, _tool, response), do: {:ok, response}
end
```

Then integrate it with the ServerProcess:

```elixir
# In server_process.ex, modify handle_call for execute_tool
def handle_call({:execute_tool, tool, params}, from, state) do
  # Apply preprocessing
  {:ok, processed_params} = MCPheonix.MCP.CustomHandler.preprocess_params(
    state.server_id, tool, params
  )
  
  # Continue with standard processing using processed_params
  # ...
end

# Also modify response handling
defp handle_json_message(%{"jsonrpc" => "2.0", "id" => id, "result" => result} = message, state) do
  case Map.get(state.pending_requests, id) do
    nil -> 
      # Unknown request
      state
      
    from ->
      # Apply postprocessing
      {:ok, processed_result} = MCPheonix.MCP.CustomHandler.postprocess_response(
        state.server_id, Map.get(state.request_tools, id), result
      )
      
      # Reply with processed result
      GenServer.reply(from, {:ok, processed_result})
      
      # Update state
      state = %{state |
        pending_requests: Map.delete(state.pending_requests, id),
        request_tools: Map.delete(state.request_tools, id)
      }
      state
  end
end
```

## Adding a New Server

To add a new MCP server, follow these steps:

1. Create the MCP server implementation
2. Configure the server in `mcp_servers.json`
3. Define the tools the server provides
4. Test the integration

## Example: Adding a Python-based MCP Server

Let's walk through a more complex example of adding a Python-based MCP server that requires custom handling:

### 1. Create the Python MCP Server

First, create your Python server implementation using the MCP Python SDK:

```python
# python_mcp_server.py
import json
import sys
from mcp.server import MCPServer
from mcp.transports import StdioTransport

# Create the server
server = MCPServer(name="python-server", version="1.0.0")

# Register a tool
@server.tool(
    name="analyze_data",
    description="Analyze data and return insights",
    parameters={
        "data": {
            "type": "array",
            "description": "The data to analyze",
            "required": True
        },
        "analysis_type": {
            "type": "string",
            "description": "Type of analysis to perform",
            "required": True
        }
    }
)
async def analyze_data(params):
    # Extract parameters
    data = params["data"]
    analysis_type = params["analysis_type"]
    
    # Perform analysis (simplified example)
    result = {"average": sum(data) / len(data) if data else 0}
    if analysis_type == "full":
        result["min"] = min(data) if data else 0
        result["max"] = max(data) if data else 0
    
    # Return result in MCP content format
    return {
        "content": [
            {
                "type": "text",
                "text": f"Analysis results: {json.dumps(result)}"
            }
        ]
    }

# Start the server
server.listen(StdioTransport())
print("Python MCP server running on stdio", file=sys.stderr)
```

### 2. Configure the Server in `mcp_servers.json`

Add the server configuration:

```json
"python_analytics": {
  "command": "/usr/bin/python",
  "args": ["/path/to/python_mcp_server.py"],
  "env": {
    "PYTHONPATH": "/path/to/your/python/packages",
    "PYTHONUNBUFFERED": "1"
  },
  "autoApprove": ["analyze_data"],
  "tools": {
    "analyze_data": {
      "description": "Analyze data and return insights",
      "parameters": [
        {
          "name": "data",
          "type": "array",
          "description": "The data to analyze",
          "required": true
        },
        {
          "name": "analysis_type",
          "type": "string",
          "description": "Type of analysis to perform",
          "required": true
        }
      ]
    }
  }
}
```

### 3. Add Custom Elixir Logic (Optional)

If needed, add custom logic for array handling or specific response formatting:

```elixir
# lib/mcpheonix/mcp/custom_python_handler.ex
defmodule MCPheonix.MCP.CustomPythonHandler do
  @moduledoc """
  Custom handler for Python-based MCP servers.
  """
  
  require Logger
  
  @doc """
  Pre-process parameters for Python server.
  Some Python tools may need special formatting for complex data.
  """
  def preprocess_params("analyze_data", params) do
    # Ensure data is properly formatted for Python
    # For example, convert Elixir-style lists to JSON arrays
    data = Map.get(params, "data", [])
    Map.put(params, "data", data)
  end
  
  def preprocess_params(_tool, params), do: params
  
  @doc """
  Post-process response from Python server.
  """
  def postprocess_response(response) do
    # Extract nested JSON if needed
    case response do
      %{"content" => [%{"text" => text, "type" => "text"}]} ->
        if String.contains?(text, "Analysis results:") do
          # Extract and parse the JSON part
          [_, json_str] = String.split(text, "Analysis results: ", parts: 2)
          case Jason.decode(json_str) do
            {:ok, parsed} ->
              # Return a more structured response
              %{
                "content" => [
                  %{"type" => "text", "text" => "Analysis completed successfully"},
                  %{"type" => "json", "json" => parsed}
                ]
              }
            _ -> response
          end
        else
          response
        end
      _ -> response
    end
  end
end
```

### 4. Update the ServerProcess to Use Your Custom Handler

Modify the `server_process.ex` file to use your custom handler:

```elixir
# In lib/mcpheonix/mcp/server_process.ex

# For a specific server ID
def handle_call({:execute_tool, tool, params}, from, %{server_id: "python_analytics"} = state) do
  # Pre-process parameters
  processed_params = MCPheonix.MCP.CustomPythonHandler.preprocess_params(tool, params)
  
  # Continue with normal execution but use processed params
  request_id = state.request_id + 1
  
  # Create JSON-RPC request
  request = %{
    jsonrpc: "2.0", 
    method: "tools/call",
    params: %{
      name: tool,
      arguments: processed_params
    },
    id: request_id
  }
  
  # Send request to server
  request_json = Jason.encode!(request) <> "\n"
  Port.command(state.port, request_json)
  
  # Update state with pending request
  state = %{state |
    request_id: request_id,
    pending_requests: Map.put(state.pending_requests, request_id, from)
  }
  
  {:noreply, state}
end

# When handling response for this server
defp handle_json_message(%{"jsonrpc" => "2.0", "id" => id, "result" => result} = message, 
                         %{server_id: "python_analytics"} = state) do
  case Map.get(state.pending_requests, id) do
    nil ->
      Logger.warning("Received response for unknown request: #{inspect(message)}")
      state
      
    from ->
      # Post-process response
      processed_result = MCPheonix.MCP.CustomPythonHandler.postprocess_response(result)
      
      # Reply to caller with processed result
      GenServer.reply(from, {:ok, processed_result})
      
      # Remove from pending requests
      %{state | pending_requests: Map.delete(state.pending_requests, id)}
  end
end
```

### 5. Test Your Implementation

Test your Python analytics server with curl:

```bash
curl -X POST http://localhost:4001/mcp/rpc -H "Content-Type: application/json" -d '{
  "jsonrpc": "2.0",
  "id": 1,
  "method": "invoke_tool",
  "params": {
    "server_id": "python_analytics",
    "tool": "analyze_data",
    "parameters": {
      "data": [1, 2, 3, 4, 5],
      "analysis_type": "full"
    }
  }
}'
```

Expected response:

```json
{
  "jsonrpc": "2.0",
  "id": 1,
  "result": {
    "content": [
      {
        "type": "text",
        "text": "Analysis completed successfully"
      },
      {
        "type": "json",
        "json": {
          "average": 3,
          "min": 1,
          "max": 5
        }
      }
    ]
  }
}
```

## Resources

- [Model Context Protocol Documentation](https://modelcontextprotocol.io)
- [MCP TypeScript SDK](https://github.com/ModelContextProtocol/typescript-sdk)
- [MCP Python SDK](https://github.com/ModelContextProtocol/python-sdk) 