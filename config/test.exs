import Config

# Configure your database
#
# The MIX_TEST_PARTITION environment variable can be used
# to provide built-in test partitioning in CI environment.
# Run `mix help test` for more information.
# Shared Supabase instance for tests
config :agentelic, Agentelic.Repo,
  username: "postgres",
  password: "postgres",
  hostname: "127.0.0.1",
  port: 54322,
  database: "postgres",
  pool: Ecto.Adapters.SQL.Sandbox,
  pool_size: System.schedulers_online() * 2,
  after_connect: {Postgrex, :query!, ["SET search_path TO agentelic,amp,public", []]}

# We don't run a server during test. If one is required,
# you can enable the server option below.
config :agentelic, AgentelicWeb.Endpoint,
  http: [ip: {127, 0, 0, 1}, port: 4002],
  secret_key_base: "Pd8FvtmmFBpsYIczNhzbkn251isF/iyLJ4XVhBKRJqJ1EDlYMVVHYpNaCQN4nF9X",
  server: false

# Print only warnings and errors during test
config :logger, level: :warning

# Initialize plugs at runtime for faster test compilation
config :phoenix, :plug_init_mode, :runtime

# Sort query params output of verified routes for robust url comparisons
config :phoenix,
  sort_verified_routes_query_params: true
