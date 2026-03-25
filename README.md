# MCPhoenix

MCP server built on Phoenix Framework (Elixir). Exposes Server-Sent Events and JSON-RPC endpoints for MCP clients, with support for managing multiple child MCP servers through JSON configuration.

Note: the module and directory names use the spelling "MCPheonix" (without the 'o') throughout the codebase.

## What It Does

Runs a Phoenix web server on port 4001 that:
1. Accepts MCP JSON-RPC requests at `POST /mcp/rpc`
2. Streams events to clients via SSE at `GET /mcp/stream`
3. Manages child MCP servers (Flux image generation, Dart task management, etc.) as supervised processes
4. Routes tool calls to the appropriate child server over stdio

Child servers are defined in `priv/config/mcp_servers.json` and started automatically at boot.

## Status

| Area | State |
|------|-------|
| Transport | HTTP (SSE + JSON-RPC) |
| Framework | Phoenix 1.7, Elixir >= 1.14, Erlang >= 25 |
| Child MCP servers | Flux (image generation), Dart (task management) |
| OTP supervision | Yes — child servers are supervised processes |
| Cloudflare integration | Durable Objects client (experimental, uses custom hex package) |
| Event system | Broadway + GenStage for processing pipelines |
| Tests | ExUnit, 2 test files (Cloudflare DO client, mock websocket) |
| License | MIT |

## Architecture

```
lib/
  mcpheonix/
    application.ex         — OTP application, supervision tree
    mcp/
      server.ex            — Core MCP server logic
      server_manager.ex    — Manages child MCP server processes
      server_process.ex    — GenServer wrapping a child stdio process
      supervisor.ex        — Supervisor for MCP server processes
      config.ex            — Reads mcp_servers.json
      connection.ex        — Client connection state
      json_rpc_protocol.ex — JSON-RPC 2.0 parsing
      jsonrpc_client.ex    — Client for calling child servers
      flux_server.ex       — Flux-specific server config
      features/
        resources.ex       — Resource listing
        tools.ex           — Tool listing and dispatch
    events/
      broker.ex            — Pub/sub event broker
    cloud/
      durable_objects/
        client.ex          — Cloudflare Durable Objects HTTP client
    resources/
      message.ex, registry.ex, user.ex — Domain resources (Ash framework)
  mcpheonix_web/
    endpoint.ex            — Phoenix endpoint
    router.ex              — Routes: /mcp/stream (SSE), /mcp/rpc (JSON-RPC)
    controllers/
      mcp_controller.ex    — SSE stream and RPC handler
      page_controller.ex   — Default page
    plugs/
      mcp_rpc_plug.ex      — Parses JSON-RPC body
      raw_body_*.ex        — Raw body reading for RPC
```

## Adding MCP Servers

Edit `priv/config/mcp_servers.json`:

```json
{
  "mcpServers": {
    "your_server": {
      "command": "/path/to/executable",
      "args": ["arg1"],
      "env": { "API_KEY": "value" },
      "tools": {
        "tool_name": {
          "description": "What it does",
          "parameters": [
            { "name": "param1", "type": "string", "description": "..." }
          ]
        }
      }
    }
  }
}
```

Servers are started as child processes under OTP supervision and restarted on failure.

## Setup

```bash
git clone https://github.com/jmanhype/MCPhoenix.git
cd MCPhoenix       # note: the repo name uses correct spelling
mix deps.get
mix phx.server     # starts on port 4001
```

### Requirements

| Dependency | Version |
|-----------|---------|
| Elixir | >= 1.14 |
| Erlang/OTP | >= 25 |
| Phoenix | ~> 1.7.0 |
| Node.js | >= 18 (for child MCP servers) |
| Python | >= 3.9 (for Flux/Dart integration) |

### Optional Integrations

| Integration | What's Needed |
|------------|---------------|
| Flux image generation | Python 3.9+, Flux CLI, `BFL_API_KEY` |
| Dart task management | Node.js 18+, `DART_TOKEN` |
| Cloudflare Durable Objects | Worker deployment, `CLOUDFLARE_WORKER_URL`, `CLOUDFLARE_ACCOUNT_ID`, `CLOUDFLARE_API_TOKEN` |

## MCP Endpoints

| Endpoint | Method | Purpose |
|----------|--------|---------|
| `/mcp/stream` | GET | SSE stream; returns `x-mcp-client-id` header |
| `/mcp/rpc` | POST | JSON-RPC 2.0; pass `x-mcp-client-id` header |

## Key Dependencies

| Package | Version | Purpose |
|---------|---------|---------|
| `phoenix` | ~> 1.7.0 | Web framework |
| `phoenix_live_view` | ~> 0.19.0 | LiveView (included but not primary interface) |
| `ash` | ~> 2.9 | Resource framework |
| `broadway` | ~> 1.0 | Event processing |
| `gen_stage` | ~> 1.2 | Event streams |
| `finch` | ~> 0.16 | HTTP client |
| `mint_web_socket` | ~> 1.0 | WebSocket support |
| `jason` | ~> 1.4 | JSON encoding |

## Limitations

- The Cloudflare Durable Objects integration depends on a custom GitHub hex package (`cloudflare_durable_ex`) that may not be publicly available
- No authentication on the MCP endpoints
- SSE connections are not persisted across server restarts
- The Ash framework resources (User, Message, Registry) appear scaffolded but not fully integrated
- LiveView and LiveDashboard are included but not used for the MCP interface
- Log files (`dev.log`, `phoenix_server.log`) and temporary files are committed to the repo

## License

MIT
