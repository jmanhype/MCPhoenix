import Config

# Configure the endpoint
config :mcpheonix, MCPheonixWeb.Endpoint,
  http: [ip: {127, 0, 0, 1}, port: 4000],
  check_origin: false,
  code_reloader: true,
  debug_errors: true,
  secret_key_base: "Jup2i3mosfGLjk4lHrBtR+/h9iy2Hp9uSeMwffmOyUE3UCIiDxL9VQUehXdjyVzQ",
  watchers: [
    esbuild: {Esbuild, :install_and_run, [:default, ~w(--sourcemap=inline --watch)]},
    tailwind: {Tailwind, :install_and_run, [:default, ~w(--watch)]}
  ]

# Configure Ash
config :ash, :use_all_identities_in_manage_relationships?, true

# Configure live reload
config :mcpheonix, MCPheonixWeb.Endpoint,
  live_reload: [
    patterns: [
      ~r"priv/static/.*(js|css|png|jpeg|jpg|gif|svg)$",
      ~r"priv/gettext/.*(po)$",
      ~r"lib/mcpheonix_web/(controllers|components|live|views)/.*(ex|heex)$"
    ]
  ]

# Set a higher stacktrace during development
config :phoenix, :stacktrace_depth, 20

# Initialize plugs at runtime for faster development compilation
config :phoenix, :plug_init_mode, :runtime

# Set the debug mode for easier debugging
config :logger, level: :debug 