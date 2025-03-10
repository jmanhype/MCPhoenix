import Config

# Configures Elixir's Logger
config :logger, :console,
  format: "$time $metadata[$level] $message\n",
  metadata: [:request_id]

# Use Jason for JSON parsing
config :phoenix, :json_library, Jason

# Configure esbuild
config :esbuild, 
  version: "0.17.11"

# Configure tailwind
config :tailwind,
  version: "3.3.2"

# MCPheonix MCP configuration
config :mcpheonix, MCPheonix.MCP,
  protocol_version: "1.0",
  capabilities: [:resources, :tools, :prompts]

# Cloudflare integration configuration
config :mcpheonix, :cloudflare,
  worker_url: System.get_env("CLOUDFLARE_WORKER_URL") || "https://example.cloudflare.workers.dev",
  account_id: System.get_env("CLOUDFLARE_ACCOUNT_ID"),
  api_token: System.get_env("CLOUDFLARE_API_TOKEN")

# Configure CloudflareDurable package
config :cloudflare_durable,
  worker_url: System.get_env("CLOUDFLARE_WORKER_URL") || "https://example.cloudflare.workers.dev",
  account_id: System.get_env("CLOUDFLARE_ACCOUNT_ID"),
  api_token: System.get_env("CLOUDFLARE_API_TOKEN")

# Import environment specific config
import_config "#{config_env()}.exs" 