# Feature 007: Configure ExUnit with custom formatter and test organization
ExUnit.start(
  # Exclude benchmark tests by default (run with: mix test --only benchmark)
  exclude: [:benchmark, :wallaby],
  # Use custom formatter for strategy editor tests
  formatters: [ExUnit.CLIFormatter, TradingStrategy.TestReporter],
  # Increase timeout for browser automation tests
  timeout: 60_000,
  # Maximum number of concurrent test cases
  max_cases: System.schedulers_online() * 2
)

# Configure Ecto Sandbox for database isolation in tests
Ecto.Adapters.SQL.Sandbox.mode(TradingStrategy.Repo, :manual)

# Feature 007: Configure Wallaby for browser automation tests
# Only start Wallaby if running wallaby tests (WALLABY_TEST=true)
if System.get_env("WALLABY_TEST") == "true" do
  {:ok, _} = Application.ensure_all_started(:wallaby)

  # Set base URL for Wallaby tests
  Application.put_env(:wallaby, :base_url, "http://localhost:4002")
end
