# MCPheonix

MCP (Model Context Protocol) server built on Elixir/Phoenix. Exposes resources and tools over SSE and JSON-RPC so LLM clients can interact with application data.

Note: the project name is spelled "MCPheonix" throughout the codebase (not "Phoenix"). This is baked into module names and file paths.

## Status

v0.1.0. Runs locally. No production deployment evidence. Test coverage is minimal (1 Cloudflare test, 1 mock WebSocket helper). The Cloudflare Durable Objects integration referenced in docs requires a paid Cloudflare account and has no automated tests.

## What It Does

1. Starts a Phoenix web server on port 4001
2. Exposes 2 MCP endpoints:
   - `GET /mcp/stream` -- SSE stream for real-time notifications
   - `POST /mcp/rpc` -- JSON-RPC 2.0 for tool invocation and resource queries
3. Manages multiple external MCP servers defined in `priv/config/mcp_servers.json`
4. Optionally integrates with Flux (image generation) and Dart (task management)

## Tech Stack

| Component | Technology |
|---|---|
| Language | Elixir 1.14+ / OTP 25+ |
| Web | Phoenix 1.7, LiveView 0.19, Cowboy |
| Data | Ash Framework 2.9 |
| HTTP Client | Finch, Mint |
| Protocol | JSON-RPC 2.0, Server-Sent Events |
| Optional | Cloudflare Durable Objects, Flux CLI, Dart MCP |

## Project Layout

```
lib/mcpheonix/
  mcp/
    server.ex             # Core MCP server
    server_manager.ex     # Multi-server lifecycle
    server_process.ex     # Per-server GenServer
    json_rpc_protocol.ex  # JSON-RPC 2.0 handling
    features/
      resources.ex        # Resource queries
      tools.ex            # Tool invocation
    flux_server.ex        # Flux image generation bridge
    supervisor.ex
  cloud/
    durable_objects/       # Cloudflare DO client
  events/
    broker.ex             # PubSub event broker
  resources/
    message.ex, user.ex, registry.ex
lib/mcpheonix_web/
  controllers/            # MCP + page controllers
  plugs/                  # RPC, raw body logging
  router.ex
config/
  mcp_servers.example.json
```

## Setup

```bash
git clone https://github.com/jmanhype/MCPhoenix.git
cd MCPhoenix
mix deps.get
mix phx.server
```

Server starts at http://localhost:4001.

### Adding MCP Servers

Edit `priv/config/mcp_servers.json`:

```json
{
  "mcpServers": {
    "your_server": {
      "command": "/path/to/executable",
      "args": ["--flag"],
      "env": { "API_KEY": "..." },
      "tools": {
        "tool_name": {
          "description": "What it does",
          "parameters": [
            { "name": "input", "type": "string", "description": "..." }
          ]
        }
      }
    }
  }
}
```

Servers start automatically on application boot.

## Limitations

- The name typo ("Pheonix" vs "Phoenix") is permanent unless all modules are renamed.
- Cloudflare Durable Objects integration is documented but untested and requires paid infrastructure.
- No authentication on MCP endpoints.
- Multiple README backup files in the repo (`README.head.tmp`, `README.md.backup`, `README.md.bak`) suggest repeated automated regeneration.
- Flux and Dart integrations require separate Python/Node.js runtimes and are not tested in CI.
- The Ash Framework integration appears scaffolded but not deeply used.

## License

See `LICENSE`.
