# MCPheonix Project Structure

This document outlines the structure of the MCPheonix project, explaining the major components and how they interact.

## Overview

MCPheonix is an intelligent, self-healing, distributed AI event system built with Elixir and the Phoenix Framework. The system implements the Model Context Protocol (MCP) to provide a standardized interface for AI models to interact with application data and functionality.

The project consists of several key components:

- **MCP Server**: The core server that implements the Model Context Protocol
- **Event System**: A publish/subscribe mechanism for real-time events
- **Resource System**: A simple system for managing resources like users and messages
- **Tool System**: Functionality that can be invoked by AI models
- **Cloudflare Integration**: Durable Objects for distributed, self-healing state
- **MCP Server Manager**: A component for managing multiple MCP servers
- **Web Interface**: Phoenix controllers and endpoints for client communication

## Directory Structure

```
/
├── assets/                  # Frontend assets (CSS, JS)
├── cloudflare/              # Cloudflare Workers and Durable Objects code
├── config/                  # Application configuration
│   ├── config.exs           # Main configuration
│   ├── dev.exs              # Development environment configuration
│   ├── prod.exs             # Production environment configuration
│   ├── test.exs             # Test environment configuration
│   └── mcp_servers.json     # MCP server configurations
├── docs/                    # Documentation
├── lib/                     # Application source code
│   ├── mcpheonix/           # Main application code
│   │   ├── application.ex   # Application entry point
│   │   ├── cloud/           # Cloud service integrations
│   │   ├── events/          # Event system
│   │   ├── mcp/             # MCP implementation
│   │   └── resources/       # Resource system
│   └── mcpheonix_web/       # Web interface
│       ├── controllers/     # Phoenix controllers
│       ├── endpoint.ex      # Phoenix endpoint
│       └── router.ex        # Request routing
├── priv/                    # Private assets and files
│   └── config/              # Additional configuration files
└── test/                    # Test files
```

## Core Components

### MCP Implementation (`lib/mcpheonix/mcp/`)

The MCP module implements the Model Context Protocol, which standardizes how AI models interact with external systems:

- **`server.ex`**: Core MCP server implementation that handles client requests
- **`connection.ex`**: Manages client connections and SSE streams
- **`server_manager.ex`**: Manages multiple MCP servers
- **`server_process.ex`**: Handles the lifecycle of individual server processes
- **`config.ex`**: Loads and validates server configurations
- **`features/`**: Contains resources, tools, and other capabilities

### Self-Healing Architecture Components

#### Cloudflare Integration (`lib/mcpheonix/cloud/`)

- **`durable_objects/client.ex`**: Client for interacting with Cloudflare Durable Objects
- **`durable_objects/supervisor.ex`**: Supervises Durable Object connections
- **`durable_objects/connection.ex`**: Manages WebSocket connections to Durable Objects

#### Cloudflare Workers (`cloudflare/`)

- **`durable-objects-worker.js`**: Implements the Durable Objects for distributed state
- **`wrangler.toml`**: Configuration file for the Cloudflare Worker

### Event System (`lib/mcpheonix/events/`)

The event system enables real-time communication between components:

- **`broker.ex`**: The central event hub that allows publishing and subscribing to events
- **`event.ex`**: Defines the structure of events
- **`subscription.ex`**: Manages event subscriptions

### Resources (`lib/mcpheonix/resources/`)

Resources represent entities that can be accessed and manipulated through MCP:

- **`registry.ex`**: Manages available resources
- **`user.ex`**: User resource implementation
- **`message.ex`**: Message resource implementation

### Web Interface (`lib/mcpheonix_web/`)

The web interface provides HTTP endpoints for MCP clients:

- **`controllers/mcp_controller.ex`**: Handles MCP HTTP requests and SSE streams
- **`router.ex`**: Defines routes for the application
- **`endpoint.ex`**: Configures the Phoenix endpoint

## Data Flow

### MCP Request Flow

```
  AI Client        MCPheonix App         MCP Server         Resources
     │                  │                    │                  │
     │  HTTP Request    │                    │                  │
     │─────────────────>│                    │                  │
     │                  │  JSON-RPC Request  │                  │
     │                  │───────────────────>│                  │
     │                  │                    │  Query/Action    │
     │                  │                    │────────────────>│
     │                  │                    │  Result          │
     │                  │                    │<────────────────│
     │                  │  JSON-RPC Response │                  │
     │                  │<───────────────────│                  │
     │  HTTP Response   │                    │                  │
     │<─────────────────│                    │                  │
     │                  │                    │                  │
```

### Self-Healing Flow

```
  MCPheonix App      Cloudflare Worker     Durable Object
     │                     │                    │
     │   Initialize DO     │                    │
     │────────────────────>│                    │
     │                     │   Create/Get DO    │
     │                     │───────────────────>│
     │                     │      Success       │
     │                     │<───────────────────│
     │       Success       │                    │
     │<────────────────────│                    │
     │                     │                    │
     │   Call Method       │                    │
     │────────────────────>│                    │
     │                     │   Execute Method   │
     │                     │───────────────────>│
     │                     │       Result       │
     │                     │<───────────────────│
     │        Result       │                    │
     │<────────────────────│                    │
     │                     │                    │
     │                     │    [DO Failure]    │
     │                     │                    │ ╳
     │                     │                    │
     │   Call Method       │                    │
     │────────────────────>│                    │
     │                     │ Recreate DO with   │
     │                     │ persisted state    │──┐
     │                     │                    │  │
     │                     │<───────────────────┘  │
     │                     │                       │
     │                     │   Execute Method      │
     │                     │──────────────────────>│
     │                     │       Result          │
     │                     │<──────────────────────│
     │        Result       │                       │
     │<────────────────────│                       │
     │                     │                       │
```

## Self-Healing Mechanisms

MCPheonix implements several mechanisms that enable self-healing:

### 1. Process Supervision

Elixir's built-in supervision trees ensure that critical processes are restarted if they crash:

```
MCPheonix.Supervisor
├── MCPheonixWeb.Endpoint
├── Phoenix.PubSub
├── MCPheonix.Events.Broker
├── MCPheonix.Resources.Registry
├── MCPheonix.MCP.SimpleServer
├── MCPheonix.MCP.ServerManager
└── MCPheonix.Cloud.DurableObjects.Supervisor
```

### 2. Stateful Redundancy

Durable Objects maintain state with automatic persistence:

- In-memory state for fast access
- Durable storage for persistence
- Global replication across Cloudflare's network

### 3. Event-Driven Architecture

The event system enables components to react to state changes:

```elixir
# Publish an event
Broker.publish("durable_objects:initialized", %{
  object_id: object_id,
  response: response,
  timestamp: DateTime.utc_now()
})

# Subscribe to events
Broker.subscribe("durable_objects:initialized")
```

### 4. Connection Monitoring

The system monitors connections to external services:

```elixir
def handle_info({:DOWN, _ref, :process, _pid, reason}, state) do
  Logger.warn("Connection to Durable Object lost: #{inspect(reason)}")
  
  # Schedule reconnection
  Process.send_after(self(), :reconnect, @reconnect_delay)
  
  {:noreply, %{state | connected: false}}
end
```

## Runtime Behavior

### Startup Sequence

1. The `Application` module (`application.ex`) starts the supervision tree
2. The `ServerManager` loads MCP server configurations
3. Each configured MCP server is started as a separate process
4. The Phoenix endpoint is started to handle HTTP requests
5. Connections to Durable Objects are established

### Request Handling

1. An AI client sends a request to the `/mcp/rpc` endpoint
2. The `MCPController` receives the request and assigns a client ID
3. The request is forwarded to the appropriate MCP server
4. The server processes the request and returns a response
5. The controller sends the response back to the client

### State Management

1. Critical state is stored in both Elixir and Durable Objects
2. Changes to state trigger events via the `Broker`
3. Components subscribe to relevant events and update their state
4. If a component fails, it can recover its state from persistence

## Configuration

### MCP Server Configuration

MCP servers are configured in `config/mcp_servers.json`:

```json
{
  "mcpServers": {
    "server_id": {
      "command": "/path/to/executable",
      "args": ["/path/to/script"],
      "env": { "ENV_VAR": "value" },
      "tools": { /* tool definitions */ }
    }
  }
}
```

### Cloudflare Configuration

Cloudflare integration is configured in `config/config.exs`:

```elixir
config :mcpheonix, :cloudflare,
  worker_url: System.get_env("CLOUDFLARE_WORKER_URL"),
  account_id: System.get_env("CLOUDFLARE_ACCOUNT_ID"),
  api_token: System.get_env("CLOUDFLARE_API_TOKEN")
```

## Extending the System

### Adding New Resources

To add a new resource:

1. Create a new module in `lib/mcpheonix/resources/`
2. Implement the resource interface
3. Register the resource in `MCPheonix.Resources.Registry`

### Adding New Tools

To add a new tool:

1. Define the tool in the MCP server configuration
2. Implement the tool's functionality
3. Update the MCP server to handle the tool invocation

### Adding New MCP Servers

To add a new MCP server:

1. Create a new server implementation
2. Configure the server in `config/mcp_servers.json`
3. Restart the application to load the new server

### Extending Durable Objects

To extend the Durable Objects functionality:

1. Add new methods to the `MCPheonixObject` class in `durable-objects-worker.js`
2. Implement corresponding client methods in `durable_objects/client.ex`
3. Deploy the updated worker to Cloudflare

## Conclusion

The MCPheonix project structure is designed to be modular, extensible, and self-healing. By leveraging Elixir's supervision trees, Phoenix's web capabilities, and Cloudflare's distributed infrastructure, the system provides a robust platform for AI model interactions through the Model Context Protocol.

Understanding the components and their interactions is key to extending and maintaining the system. The self-healing mechanisms ensure that the system can recover from failures automatically, providing a reliable service for AI clients. 