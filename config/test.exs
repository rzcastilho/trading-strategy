import Config

# Only in tests, remove the complexity from the password hashing algorithm
config :bcrypt_elixir, :log_rounds, 1

# Configure your database
#
# The MIX_TEST_PARTITION environment variable can be used
# to provide built-in test partitioning in CI environment.
# Run `mix help test` for more information.
config :trading_strategy, TradingStrategy.Repo,
  username: "postgres",
  password: "postgres",
  hostname: "localhost",
  port: 5433,
  database: "trading_strategy_test#{System.get_env("MIX_TEST_PARTITION")}",
  pool: Ecto.Adapters.SQL.Sandbox,
  pool_size: System.schedulers_online() * 2

# We don't run a server during test. If one is required,
# you can enable the server option below.
config :trading_strategy, TradingStrategyWeb.Endpoint,
  http: [ip: {127, 0, 0, 1}, port: 4002],
  secret_key_base: "ZNPaJiqxZUUKs7QlbmsNx0tFz9dF7vbs5Uwonc1eYeEWOXiuNEeYuU26mbzensEZ",
  server: false

# Print only warnings and errors during test
config :logger, level: :warning

# Initialize plugs at runtime for faster test compilation
config :phoenix, :plug_init_mode, :runtime

# Backtesting test configuration
config :trading_strategy,
  # Enable test mode to prevent actual backtest execution in tests
  backtest_test_mode: false,
  # Set low concurrency limit for testing
  max_concurrent_backtests: 3

# Disable swoosh mailer in tests
config :trading_strategy, TradingStrategy.Mailer, adapter: Swoosh.Adapters.Test
