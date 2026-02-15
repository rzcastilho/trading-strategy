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
# For Wallaby tests (Feature 007), server is enabled conditionally
config :trading_strategy, TradingStrategyWeb.Endpoint,
  http: [ip: {127, 0, 0, 1}, port: 4002],
  secret_key_base: "ZNPaJiqxZUUKs7QlbmsNx0tFz9dF7vbs5Uwonc1eYeEWOXiuNEeYuU26mbzensEZ",
  server: System.get_env("WALLABY_TEST") == "true"

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

# Feature 005: Bidirectional Strategy Editor Synchronization
config :trading_strategy, :strategy_editor,
  debounce_delay: 300,
  sync_timeout: 500,
  max_undo_stack_size: 100

# Feature 007: Browser automation testing with Wallaby
config :wallaby,
  driver: Wallaby.Chrome,
  # Headless mode for CI environments
  hackney_options: [timeout: :infinity, recv_timeout: :infinity],
  # Chrome options for headless testing
  chromedriver: [
    headless: System.get_env("WALLABY_HEADLESS", "true") == "true"
  ],
  # Screenshot path for failed tests
  screenshot_on_failure: true,
  screenshot_dir: "tmp/wallaby_screenshots",
  # Maximum wait time for elements (default 3000ms, increased for stability)
  max_wait_time: 5_000
