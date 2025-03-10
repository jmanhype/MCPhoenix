# Dart MCP Server Integration

This document describes the integration between the MCPheonix application and the Dart MCP server, including how to configure, use, and troubleshoot the integration.

## Overview

The MCPheonix application integrates with Dart via the Model Context Protocol (MCP). This allows AI assistants to interact with Dart features through standardized JSON-RPC requests. The MCPheonix application:

1. Acts as an MCP client interfacing with various MCP servers
2. Provides an HTTP endpoint for AI clients to send MCP requests
3. Routes these requests to the appropriate MCP servers (including Dart)
4. Returns responses back to the clients

The Dart MCP server runs as a child process of the Phoenix application, communicating via standard input/output streams (stdio).

## Architecture

```
┌──────────────┐      ┌───────────────┐      ┌─────────────────┐
│              │      │               │      │                 │
│  AI Client   │─────▶│  MCPheonix    │─────▶│  Dart MCP       │
│  (Claude)    │◀─────│  Application  │◀─────│  Server         │
│              │      │               │      │                 │
└──────────────┘      └───────────────┘      └─────────────────┘
    HTTP/SSE            Process Spawning      stdio (JSON-RPC)
```

The communication flow is:

1. AI client connects to the Phoenix application via HTTP/SSE
2. Phoenix application spawns and initializes the Dart MCP server
3. AI client sends JSON-RPC requests to Phoenix
4. Phoenix routes these requests to the appropriate MCP server (Dart in this case)
5. Dart MCP server processes the request and returns a JSON-RPC response
6. Phoenix forwards the response back to the AI client

## Configuration

The Dart MCP server is configured in `/priv/config/mcp_servers.json`. Here's the relevant configuration for the Dart server:

```json
{
  "mcpServers": {
    "dart": {
      "command": "/opt/homebrew/bin/node",
      "args": ["/Users/speed/Documents/Cline/MCP/dart-mcp-server/build/index.js"],
      "env": {
        "PATH": "/Users/speed/Documents/Cline/MCP/dart-mcp-server/.venv/bin:/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin",
        "PYTHONUNBUFFERED": "1",
        "VIRTUAL_ENV": "/Users/speed/Documents/Cline/MCP/dart-mcp-server/.venv"
      },
      "autoApprove": ["create_task", "get_default_space", "get_default_status", "update_task", "get_dartboards", "get_folders", "create_folder", "create_doc", "create_space", "delete_space"],
      "tools": {
        "create_task": {
          "description": "Create a new task",
          "parameters": [
            {
              "name": "title",
              "type": "string",
              "description": "Task title",
              "required": true
            },
            {
              "name": "description",
              "type": "string",
              "description": "Task description",
              "required": true
            },
            {
              "name": "dartboard_duid",
              "type": "string",
              "description": "Dartboard DUID",
              "required": true
            },
            // Additional parameters omitted for brevity
          ]
        },
        // Additional tools omitted for brevity
      }
    }
  }
}
```

### Configuration Options

- `command`: The command to run to start the MCP server
- `args`: Command-line arguments to pass to the command
- `env`: Environment variables to set for the MCP server process
- `autoApprove`: List of tools that don't require user approval
- `tools`: Map of available tools with their parameters

## Implemented Tools

The Dart MCP server provides the following tools:

### `create_task`

Creates a new task in Dart.

**Parameters:**
- `title` (string, required): Task title
- `description` (string, required): Task description
- `dartboard_duid` (string, required): Dartboard DUID
- `priority` (string, optional): Priority of the task
- `tags` (array, optional): Tags for the task
- `size` (number, optional): Size/complexity of the task (1-5)
- `assignee_duids` (array, optional): List of assignee DUIDs
- `subscriber_duids` (array, optional): List of subscriber DUIDs

**Example Request:**
```json
{
  "jsonrpc": "2.0",
  "id": 1,
  "method": "invoke_tool",
  "params": {
    "server_id": "dart",
    "tool": "create_task",
    "parameters": {
      "dartboard_duid": "FaKW5KTI1Efe",
      "title": "Test Task from Phoenix",
      "description": "Testing the integration between Phoenix and Dart MCP server"
    }
  }
}
```

**Example Response:**
```json
{
  "id": 1,
  "jsonrpc": "2.0",
  "result": {
    "content": [
      {
        "text": "Task created successfully with DUID: 3i0Blhh4avjP",
        "type": "text"
      }
    ]
  }
}
```

### `get_default_space`

Gets the default space DUID for a dartboard.

**Parameters:**
- `dartboard_duid` (string, required): Dartboard DUID

**Example Request:**
```json
{
  "jsonrpc": "2.0",
  "id": 1,
  "method": "invoke_tool",
  "params": {
    "server_id": "dart",
    "tool": "get_default_space",
    "parameters": {
      "dartboard_duid": "FaKW5KTI1Efe"
    }
  }
}
```

**Example Response:**
```json
{
  "id": 1,
  "jsonrpc": "2.0",
  "result": {
    "content": [
      {
        "text": "Default space DUID: sKMVyJB0fIaA",
        "type": "text"
      }
    ]
  }
}
```

## Implementation Details

### Server Process Management

The MCPheonix application manages the Dart MCP server process through the `ServerProcess` GenServer module. This module:

1. Starts the server process using Erlang's `Port` module
2. Sends an initialization request to get the server's capabilities
3. Manages the communication with the server via stdio
4. Handles request routing and response processing

When a tool is invoked, the Phoenix application:

1. Routes the request to the appropriate server based on the `server_id`
2. Formats the request according to the MCP protocol (using method "tools/call")
3. Sends the request to the server process
4. Waits for the response and returns it to the client

### Python Integration

The Dart MCP server uses Python to interact with the Dart API. It:

1. Spawns a Python process to execute Dart API calls
2. Passes parameters via command-line arguments and environment variables
3. Captures the output and formats it as a JSON-RPC response

## Error Handling

The integration includes several layers of error handling:

1. **JSON-RPC Error Responses**: If a request is malformed or invalid, the server returns a standard JSON-RPC error response
2. **Process Monitoring**: If the server process crashes, the Phoenix application detects this and returns an appropriate error
3. **Timeouts**: Requests have a timeout (60 seconds by default) to prevent hanging processes

## Troubleshooting

### Server Not Starting

If the Dart MCP server fails to start:

1. Check that the path to the server executable is correct in the configuration
2. Verify that the required environment variables are set correctly
3. Check the server logs for any error messages

### Method Not Found Errors

If you receive a "Method not found" error:

1. Verify that the method name in the request matches what the server expects
2. Check the server logs to see if the request is reaching the server
3. Ensure the tool is properly defined in the `mcp_servers.json` configuration

### Port Already in Use

If the Phoenix server fails to start with an "address already in use" error:

1. Check for existing Phoenix processes using `ps aux | grep "mix phx.server"`
2. Kill any existing Phoenix processes with `kill -9 <PID>`
3. Try starting the server again

## Testing

You can test the integration using curl:

```bash
curl -X POST http://localhost:4001/mcp/rpc -H "Content-Type: application/json" -d '{
  "jsonrpc": "2.0",
  "id": 1,
  "method": "invoke_tool",
  "params": {
    "server_id": "dart",
    "tool": "create_task",
    "parameters": {
      "dartboard_duid": "FaKW5KTI1Efe",
      "title": "Test Task from Phoenix",
      "description": "Testing the integration between Phoenix and Dart MCP server"
    }
  }
}'
```

## Resources

- [Model Context Protocol Documentation](https://github.com/ModelContextProtocol/service-model-context-protocol)
- [Dart API Documentation](https://docs.dartai.com)
- [Phoenix Framework Documentation](https://hexdocs.pm/phoenix/Phoenix.html) 