defmodule MCPheonix.MixProject do
  use Mix.Project

  def project do
    [
      app: :mcpheonix,
      version: "0.1.0",
      elixir: "~> 1.14",
      elixirc_paths: elixirc_paths(Mix.env()),
      start_permanent: Mix.env() == :prod,
      aliases: aliases(),
      deps: deps(),
      test_coverage: [tool: ExCoveralls],
      preferred_cli_env: [
        coveralls: :test,
        "coveralls.detail": :test,
        "coveralls.post": :test,
        "coveralls.html": :test
      ]
    ]
  end

  # Configuration for the OTP application
  def application do
    [
      mod: {MCPheonix.Application, []},
      extra_applications: [:logger, :runtime_tools, :finch]
    ]
  end

  # Specifies which paths to compile per environment
  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  # Dependencies
  defp deps do
    [
      # Phoenix and web
      {:phoenix, "~> 1.7.0"},
      {:phoenix_html, "~> 3.3"},
      {:phoenix_live_view, "~> 0.19.0"},
      {:phoenix_live_reload, "~> 1.4", only: :dev},
      {:phoenix_live_dashboard, "~> 0.8.0"},
      {:esbuild, "~> 0.7", runtime: Mix.env() == :dev},
      {:tailwind, "~> 0.2", runtime: Mix.env() == :dev},
      {:telemetry_metrics, "~> 0.6"},
      {:telemetry_poller, "~> 1.0"},
      {:gettext, "~> 0.20"},
      {:jason, "~> 1.4"},      # JSON library
      {:plug_cowboy, "~> 2.5"}, # HTTP server
      {:uuid, "~> 1.1"},       # For generating UUIDs

      # Ash Framework
      {:ash, "~> 2.9"},
      {:ash_phoenix, "~> 1.2"},
      {:ash_json_api, "~> 0.31"},

      # HTTP client
      {:finch, "~> 0.16"},
      {:mint, "~> 1.5"},       # For WebSockets and SSE
      {:mint_web_socket, "~> 1.0"}, # Explicitly add MintWebSocket

      # Event system
      {:broadway, "~> 1.0"},   # For event processing pipelines
      {:gen_stage, "~> 1.2"},  # For event streams

      # Utilities
      {:typed_struct, "~> 0.3"}, # For defining structs with types
      {:ex_doc, "~> 0.29", only: :dev, runtime: false},

      # Testing
      {:excoveralls, "~> 0.15", only: :test},
      {:credo, "~> 1.6", only: [:dev, :test], runtime: false},
      {:dialyxir, "~> 1.2", only: [:dev, :test], runtime: false},
      {:mix_test_watch, "~> 1.1", only: [:dev, :test], runtime: false},

      # Cloudflare Durable Objects client
      {:cloudflare_durable, github: "jmanhype/cloudflare_durable_ex"}
    ]
  end

  # Aliases are shortcuts or tasks specific to the current project
  defp aliases do
    [
      setup: ["deps.get", "cmd --cd assets npm install"],
      "assets.deploy": ["tailwind default --minify", "esbuild default --minify", "phx.digest"],
      test: ["test"],
      lint: ["credo --strict", "dialyzer"]
    ]
  end
end 