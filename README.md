# MCPheonix

A simplified implementation of the Model Context Protocol (MCP) server using Elixir's Phoenix Framework.

## Overview

MCPheonix provides a server that implements the Model Context Protocol, allowing AI models to interact with your application data and functionality. This implementation is designed to be simple and easy to understand, without heavy dependencies on frameworks like Ash.

## Features

- Server-Sent Events (SSE) stream for real-time notifications
- JSON-RPC endpoint for client requests
- Simple resource system
- Event publish/subscribe mechanism
- Basic tool invocation
- Flux image generation integration

## Getting Started

### Prerequisites

- Elixir 1.14 or higher
- Erlang 25 or higher
- Phoenix 1.7.0 or higher
- Python 3.9+ (for Flux integration)

### Installation

1. Clone the repository
```bash
git clone https://github.com/yourusername/mcpheonix.git
cd mcpheonix
```

2. Install dependencies
```bash
mix deps.get
```

3. Configure the Flux integration (if using image generation)
   - Set up the Flux CLI environment as described in the [Flux Integration](#flux-integration) section

4. Start the server
```bash
mix phx.server
```

The server will be available at http://localhost:4001.

## MCP Endpoints

- **SSE Stream**: `GET /mcp/stream`
  - Establishes a Server-Sent Events stream for receiving real-time notifications
  - Returns a client ID in the response headers

- **JSON-RPC**: `POST /mcp/rpc`
  - Accepts JSON-RPC 2.0 requests
  - Client ID can be provided in the `x-mcp-client-id` header or will be generated if missing

## Built-in Capabilities

### Resources

- `user`: User resource
  - Actions: `list`, `get`
- `message`: Message resource
  - Actions: `list`, `get`

### Tools

- `echo`: Echoes back the input message
  - Parameters: `message` (string)
- `timestamp`: Returns the current timestamp
  - Parameters: none
- `random_number`: Generate a random number within a range
  - Parameters: `min` (integer), `max` (integer)
- `generate_image`: Generate an image from a text prompt
  - Parameters: `prompt` (string), `aspect_ratio` (string, optional), `model` (string, optional), `output` (string, optional)
- `img2img`: Generate an image using another image as reference
  - Parameters: `image` (string), `prompt` (string), `name` (string), `strength` (number, optional)

## Flux Integration

MCPheonix includes integration with the Flux CLI for image generation. This allows AI models to generate images or transform existing images through the MCP protocol.

### Setting Up Flux

1. Clone the Flux repository and set up the Python environment:
```bash
https://github.com/jmanhype/mcp-flux-studio
cd flux
python -m venv .venv
source .venv/bin/activate
pip install -r requirements.txt
```

2. Configure the Flux environment variables in `lib/mcpheonix/mcp/flux_server.ex`:
```elixir
@flux_dir "/path/to/your/flux/directory"
@virtual_env "/path/to/your/flux/.venv"
@bfl_api_key "your-api-key"
```

3. Make sure the Flux CLI is working by testing it directly:
```bash
cd /path/to/your/flux
.venv/bin/python fluxcli.py generate --prompt "Test image" --output test.jpg
```

### Using Image Generation Tools

Once set up, you can use the image generation tools through MCP:

#### Generate a new image:
```json
{
  "jsonrpc": "2.0",
  "method": "invoke_tool",
  "params": {
    "tool": "generate_image",
    "parameters": {
      "prompt": "A beautiful sunset over mountains",
      "aspect_ratio": "16:9"
    }
  },
  "id": 1
}
```

#### Transform an existing image:
```json
{
  "jsonrpc": "2.0",
  "method": "invoke_tool",
  "params": {
    "tool": "img2img",
    "parameters": {
      "image": "/path/to/input/image.jpg",
      "prompt": "A beautiful sunset over mountains with birds",
      "name": "transformed_image"
    }
  },
  "id": 2
}
```

Generated images are saved to `~/Pictures/flux-generations/` by default and will be opened automatically.

## Sample JSON-RPC Requests

Initialize the connection:
```json
{
  "jsonrpc": "2.0",
  "method": "initialize",
  "id": 1
}
```

Invoke a tool:
```json
{
  "jsonrpc": "2.0",
  "method": "invoke_tool",
  "params": {
    "tool": "echo",
    "parameters": {
      "message": "Hello, world!"
    }
  },
  "id": 2
}
```

## License

This project is licensed under the MIT License - see the LICENSE file for details.

## Acknowledgments

- The MCP Protocol specification
- Phoenix Framework
- Elixir community
- Flux image generation 
 
