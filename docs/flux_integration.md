# Flux Image Generation Integration

MCPheonix integrates with the Flux CLI for AI image generation, allowing AI assistants to generate and manipulate images via the Model Context Protocol (MCP). This document explains how to set up, configure, and troubleshoot the Flux integration.

## Overview

The integration provides two main tools:
- `generate_image`: Create new images from text prompts
- `img2img`: Transform existing images based on text prompts

Both tools use the Flux CLI to interact with image generation models, and the integration handles all the necessary environment setup, command execution, and file management.

## Setup and Configuration

### Requirements

- Python 3.9+ installed on your system
- Flux CLI repository cloned locally
- An API key for the Flux service

### Installation Steps

1. Clone the Flux repository:
   ```bash
   git clone https://github.com/Cascade-AI/flux.git
   cd flux
   ```

2. Set up a Python virtual environment:
   ```bash
   python -m venv .venv
   source .venv/bin/activate  # On Windows: .venv\Scripts\activate
   pip install -r requirements.txt
   ```

3. Test the Flux CLI works:
   ```bash
   python fluxcli.py generate --prompt "Test prompt" --output test.jpg
   ```

4. Configure the MCPheonix integration by editing `lib/mcpheonix/mcp/flux_server.ex`:
   ```elixir
   # Configuration
   @flux_dir "/path/to/your/flux/directory"  # Update this path
   @virtual_env "/path/to/your/flux/.venv"   # Update this path
   @python_path "#{@virtual_env}/bin/python" # Path to Python in virtual env
   @bfl_api_key "your-api-key-here"          # Update with your API key
   ```

5. Configure environment variables:
   The Flux integration uses several environment variables:
   - `BFL_API_KEY`: Your Flux API key
   - `VIRTUAL_ENV`: Path to the virtual environment
   - `PATH`: System path including the virtual environment's bin directory
   - `PYTHONPATH`: Path to the Flux directory

   These are set automatically based on the configuration values, but you may need to customize them if you have a non-standard setup.

## Usage

### Generate Image

To generate an image from a text prompt, use the `generate_image` tool:

```json
{
  "jsonrpc": "2.0",
  "method": "invoke_tool",
  "params": {
    "tool": "generate_image",
    "parameters": {
      "prompt": "A beautiful sunset over mountains",
      "aspect_ratio": "16:9",
      "model": "flux.1.1-pro",
      "output": "my_sunset.jpg"
    }
  },
  "id": 1
}
```

Parameters:
- `prompt` (required): Text description of the image to generate
- `aspect_ratio` (optional): Aspect ratio of the image (1:1, 4:3, 3:4, 16:9, 9:16)
- `model` (optional): Model to use (flux.1.1-pro, flux.1-pro, flux.1-dev, flux.1.1-ultra)
- `output` (optional): Custom output filename
- `width` (optional): Custom width in pixels
- `height` (optional): Custom height in pixels

### Image-to-Image Transformation

To transform an existing image, use the `img2img` tool:

```json
{
  "jsonrpc": "2.0",
  "method": "invoke_tool",
  "params": {
    "tool": "img2img",
    "parameters": {
      "image": "/path/to/input/image.jpg",
      "prompt": "A beautiful sunset over mountains with birds",
      "name": "transformed_image",
      "strength": 0.7
    }
  },
  "id": 2
}
```

Parameters:
- `image` (required): Path to the input image
- `prompt` (required): Text description of the desired transformation
- `name` (required): Base name for the output image
- `strength` (optional): Transformation strength from 0.0 to 1.0
- `model` (optional): Model to use
- `width` (optional): Custom width in pixels
- `height` (optional): Custom height in pixels

### Response Format

Both tools return a response with this structure:

```json
{
  "id": 1,
  "jsonrpc": "2.0",
  "result": {
    "status": "success",
    "message": "Image generated successfully",
    "timestamp": "2025-03-09T12:00:46.418705Z",
    "filepath": "/Users/username/Pictures/flux-generations/text-to-image/2025-03-09/generated_120041.jpg",
    "output": "Command output text..."
  }
}
```

## File Management

Generated images are saved in a structured directory hierarchy:
- Base directory: `~/Pictures/flux-generations/`
- For text-to-image: `~/Pictures/flux-generations/text-to-image/YYYY-MM-DD/`
- For image-to-image: `~/Pictures/flux-generations/img2img/YYYY-MM-DD/`

Filenames include timestamps to ensure uniqueness.

## Troubleshooting

### Common Issues

1. **API Key Issues**
   - Error: `"Flux CLI failed with code 1: API key required"`
   - Solution: Ensure the `@bfl_api_key` is set correctly in `flux_server.ex`

2. **Path Issues**
   - Error: `"Flux CLI not available"`
   - Solution: Verify paths in `@flux_dir` and `@virtual_env`, ensure the Flux CLI exists

3. **Python Issues**
   - Error: `"Exception executing Flux CLI"`
   - Solution: Check Python environment is properly set up, dependencies installed

4. **Timeout Issues**
   - Error: `"Request timed out"`
   - Solution: The default timeout is 60 seconds; for large images or slow systems, consider increasing this value

5. **File Access Issues**
   - Error: `"Permission denied"` or `"File not found"`
   - Solution: Ensure the server has permission to write to the output directory and read input images

### Debugging Tips

1. Check logs for execution details:
   - The FluxServer logs the full commands it executes
   - Look for lines starting with `"Executing Flux CLI:"`

2. Test the Flux CLI directly to isolate issues:
   ```bash
   cd /path/to/flux
   .venv/bin/python fluxcli.py generate --prompt "Test" --output test.jpg
   ```

3. Verify environment variables:
   - Print environment variables inside the FluxServer module to confirm they're set correctly

## Implementation Details

The Flux integration is implemented in these files:

- `lib/mcpheonix/mcp/flux_server.ex`: Main FluxServer GenServer implementation
- `lib/mcpheonix/mcp/features/tools.ex`: Integration with the MCP tools system

The FluxServer uses direct execution of the Flux CLI through Elixir's `System.cmd/3`, handling all the necessary environment setup and command-line argument construction.

## Configuration Options

### Optional Mode

By default, the FluxServer is marked as optional:

```elixir
@optional true
```

If set to `false`, the MCPheonix server will fail to start if the Flux CLI is not available. This is useful for deployments where image generation is a critical feature.

### Custom Directories

You can customize where generated images are saved by modifying the `create_output_path/2` function in `flux_server.ex`. 