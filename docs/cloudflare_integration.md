# Cloudflare Integration

This document describes how MCPheonix integrates with Cloudflare Durable Objects and Workers to create a self-healing, distributed architecture.

## Overview

MCPheonix leverages Cloudflare's edge computing platform to implement a fault-tolerant, globally distributed system architecture. This integration enables:

- **Self-healing capabilities**: If any component fails, the system can automatically recover
- **Global distribution**: State is replicated across Cloudflare's global network
- **Stateful edge computing**: Maintain consistency and state at the edge
- **Real-time collaboration**: Multiple clients can interact with the same stateful objects

## Architecture

The architecture consists of:

```
┌───────────────┐       ┌───────────────┐      ┌────────────────────┐
│               │       │               │      │                    │
│  MCPheonix    │ ─────▶│  Cloudflare   │ ────▶│  Durable Objects   │
│  (Elixir)     │◀─────┘│  Worker       │◀─────│  (Stateful Actors) │
│               │       │               │      │                    │
└───────────────┘       └───────────────┘      └────────────────────┘
   Server-side            Edge Gateway           Distributed State
```

1. **MCPheonix Elixir Application**: The core application hosting the MCP server and business logic
2. **Cloudflare Worker**: A serverless JavaScript application that routes requests to appropriate Durable Objects
3. **Durable Objects**: Stateful serverless components that maintain consistency and can recover from failures

## Self-Healing Mechanisms

The self-healing capabilities of MCPheonix come from several key mechanisms:

### 1. Stateful Redundancy

Durable Objects maintain state with multiple layers of durability:

- **In-memory state**: For fast access during normal operation
- **Durable storage**: State is automatically persisted to Cloudflare's storage system
- **Global replication**: Data is replicated across multiple data centers

If an instance becomes unavailable, Cloudflare automatically recreates it with the same state from durable storage. This happens transparently, with no action required from the application.

### 2. Event-Driven Architecture

The system uses a publish/subscribe model via `MCPheonix.Events.Broker`, allowing components to react to state changes and recover from failures:

- When state changes in a Durable Object, it broadcasts updates to all connected clients
- If a client reconnects after a disconnection, it receives the current state
- Changes are propagated through the system in real-time

### 3. Distributed State Management

Critical application state is stored in both:

- **Cloudflare Durable Objects**: For edge availability and real-time access
- **Elixir's persistent storage**: For long-term durability and business logic

This dual-storage approach ensures that even if one system fails, the other can continue operating and eventually resynchronize.

### 4. Automatic Reconnection

The system includes automatic reconnection logic:

- If a connection to a Durable Object is disrupted, MCPheonix will automatically attempt to reconnect
- Exponential backoff strategies prevent overloading the system during recovery
- Connection state tracking ensures proper re-establishment of sessions

### 5. Global Distribution

By leveraging Cloudflare's global edge network, the system continues functioning even if an entire region experiences downtime:

- Requests are routed to the nearest available edge location
- State is available globally, not just in a single region
- Cloudflare's anycast network provides natural failover

## Implementation Details

### Durable Objects Worker

The Cloudflare Worker (`cloudflare/durable-objects-worker.js`) implements:

- Routing requests to appropriate Durable Objects based on IDs
- Managing WebSocket connections for real-time communication
- Providing HTTP APIs for state management
- Method invocation for remote procedure calls

Key features of the Durable Objects implementation:

```javascript
export class MCPheonixObject {
  constructor(state, env) {
    this.state = state;
    this.storage = state.storage;
    this.sessions = new Map(); // WebSocket sessions
  }

  // HTTP API methods
  async fetch(request) {
    // Handle HTTP and WebSocket requests
  }

  // WebSocket support
  async handleWebSocketUpgrade(request) {
    // Establish bidirectional communication
  }

  // State management with automatic persistence
  async method_increment(data) {
    let value = await this.storage.get(key) || 0;
    value += increment;
    await this.storage.put(key, value);
    this.broadcastUpdate(key, value);
    return { key, value };
  }
}
```

### Elixir Integration with Cloudflare

MCPheonix communicates with Durable Objects through `MCPheonix.Cloud.DurableObjects.Client`, which provides:

- Initialization of Durable Objects with initial state
- Method calls on remote objects
- WebSocket connections for real-time updates
- Event publishing to the system event broker

Example usage:

```elixir
alias MCPheonix.Cloud.DurableObjects.Client

# Initialize a new Durable Object
{:ok, response} = Client.initialize(worker_url, "counter", %{value: 0})

# Call a method on the Durable Object
{:ok, result} = Client.call_method(worker_url, "counter", "increment", %{increment: 1})

# Open a WebSocket for real-time updates
{:ok, socket} = Client.open_websocket(worker_url, "counter")
```

## Configuration

### Environment Variables

Configuration is stored in `config/config.exs` and can be overridden in environment-specific configs:

```elixir
config :mcpheonix, :cloudflare,
  worker_url: System.get_env("CLOUDFLARE_WORKER_URL") || "https://example.cloudflare.workers.dev",
  account_id: System.get_env("CLOUDFLARE_ACCOUNT_ID"),
  api_token: System.get_env("CLOUDFLARE_API_TOKEN")
```

### Required Environment Variables

- `CLOUDFLARE_WORKER_URL`: URL of your deployed worker
- `CLOUDFLARE_ACCOUNT_ID`: Your Cloudflare account ID
- `CLOUDFLARE_API_TOKEN`: API token with Workers and DO permissions

## Setup Instructions

### 1. Deploy the Cloudflare Worker

1. Install Wrangler (Cloudflare's CLI tool):
   ```bash
   npm install -g wrangler
   ```

2. Authenticate with Cloudflare:
   ```bash
   wrangler login
   ```

3. Deploy the Worker and Durable Object:
   ```bash
   cd cloudflare
   wrangler publish
   ```

4. Note the URL of your deployed worker (displayed in the publish output)

### 2. Configure MCPheonix

1. Set the required environment variables:
   ```bash
   export CLOUDFLARE_WORKER_URL="https://your-worker.your-subdomain.workers.dev"
   export CLOUDFLARE_ACCOUNT_ID="your-account-id"
   export CLOUDFLARE_API_TOKEN="your-api-token"
   ```

2. Start the MCPheonix application:
   ```bash
   mix phx.server
   ```

## Usage Examples

### Creating a Distributed Counter

```elixir
# Initialize a counter with starting value
worker_url = Application.get_env(:mcpheonix, :cloudflare)[:worker_url]
{:ok, _} = MCPheonix.Cloud.DurableObjects.Client.initialize(worker_url, "counter", %{value: 0})

# Increment the counter
{:ok, result} = MCPheonix.Cloud.DurableObjects.Client.call_method(worker_url, "counter", "increment", %{increment: 1})
IO.puts("Counter value: #{result["value"]}")
```

### Collaborative Document Editing

```elixir
# Initialize a document with content
worker_url = Application.get_env(:mcpheonix, :cloudflare)[:worker_url]
{:ok, _} = MCPheonix.Cloud.DurableObjects.Client.initialize(worker_url, "document-123", %{
  content: "Initial document content",
  version: 1
})

# Update document content
{:ok, result} = MCPheonix.Cloud.DurableObjects.Client.call_method(worker_url, "document-123", "update", %{
  content: "Updated document content",
  version: 2
})

# Open WebSocket for real-time updates
{:ok, socket} = MCPheonix.Cloud.DurableObjects.Client.open_websocket(worker_url, "document-123")
```

## Troubleshooting

### Connection Issues

If you're experiencing connection issues with the Cloudflare Worker:

1. Verify that your Worker URL is correct
2. Check that your API token has the necessary permissions
3. Ensure your Worker is published and active on Cloudflare
4. Check Cloudflare's status page for any ongoing incidents

### Durable Object Errors

If you receive errors from Durable Objects operations:

1. Check the error message for specific details
2. Verify that the Durable Object exists (initialize it if needed)
3. Ensure you're sending valid parameters for the method
4. Check Cloudflare's Workers logs for more details

### Performance Issues

If you notice performance degradation:

1. Check your Worker's CPU usage (Cloudflare has limits)
2. Consider using batched operations for multiple updates
3. Implement caching for frequently accessed data
4. Use Cloudflare's analytics to identify bottlenecks

## Advanced Topics

### Custom Durable Object Methods

You can add custom methods to your Durable Objects by extending the `MCPheonixObject` class:

```javascript
// In durable-objects-worker.js
async method_custom_operation(data) {
  // Implement your custom logic
  // Use this.storage for persistence
  // Use this.broadcastUpdate for real-time updates
  return { result: "success" };
}
```

### WebSocket Integration with Phoenix Channels

For a more integrated experience, you can connect Phoenix Channels to Durable Objects:

```elixir
defmodule MCPheonixWeb.DurableObjectChannel do
  use Phoenix.Channel
  alias MCPheonix.Cloud.DurableObjects.Client

  def join("durable_object:" <> object_id, _params, socket) do
    # Connect to the Durable Object
    {:ok, ws} = Client.open_websocket(worker_url(), object_id)
    socket = assign(socket, :ws, ws)
    {:ok, socket}
  end

  def handle_in("call_method", %{"method" => method, "params" => params}, socket) do
    object_id = socket.topic |> String.replace("durable_object:", "")
    {:ok, result} = Client.call_method(worker_url(), object_id, method, params)
    {:reply, {:ok, result}, socket}
  end

  defp worker_url do
    Application.get_env(:mcpheonix, :cloudflare)[:worker_url]
  end
end
```

## References

- [Cloudflare Durable Objects Documentation](https://developers.cloudflare.com/workers/runtime-apis/durable-objects)
- [Cloudflare Workers Documentation](https://developers.cloudflare.com/workers)
- [Wrangler Documentation](https://developers.cloudflare.com/workers/wrangler)
- [Model Context Protocol Specification](https://modelcontextprotocol.io) 