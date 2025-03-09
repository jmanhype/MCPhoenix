import Config

# We don't run a server during test. If one is required,
# you can enable the server option below.
config :mcpheonix, MCPheonixWeb.Endpoint,
  http: [ip: {127, 0, 0, 1}, port: 4002],
  secret_key_base: "R7GUoJZqFHXpJSR/Xc6l7l+5UZnqixnBj9i1m9S1xN4kCcSqnOuJ+1AZ8pOeSqEH",
  server: false

# Disable Ash events during test
config :ash, :disable_async?, true

# Print only warnings and errors during test
config :logger, level: :warning

# Initialize plugs at runtime for faster test compilation
config :phoenix, :plug_init_mode, :runtime

# Mock external services during test
config :mcpheonix, :cloudflare,
  worker_url: "http://mock-cloudflare-worker.test",
  account_id: "test_account_id",
  api_token: "test_api_token" 