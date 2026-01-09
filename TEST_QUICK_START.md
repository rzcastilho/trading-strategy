# Test Quick Start Guide

## Phase 5 Paper Trading Tests - Quick Reference

### Files Created

1. **test/trading_strategy/market_data/stream_subscriber_test.exs** (10KB)
   - Tests WebSocket streaming subscriptions
   - Tests PubSub broadcasting
   - Tests reconnection logic

2. **test/trading_strategy/strategies/realtime_signal_detector_test.exs** (17KB)
   - Tests real-time signal detection
   - Tests subscriber notifications
   - Tests signal history tracking

3. **test/trading_strategy/paper_trading/paper_executor_test.exs** (15KB)
   - Tests simulated trade execution
   - Tests slippage and fee calculation
   - Tests P&L calculation

4. **test/trading_strategy/paper_trading/position_tracker_test.exs** (21KB)
   - Tests position management
   - Tests capital allocation
   - Tests serialization

5. **test/trading_strategy/market_data/cache_test.exs** (14KB)
   - Tests ETS-based caching
   - Tests concurrent access
   - Tests ring buffer behavior

6. **test/trading_strategy_web/controllers/paper_trading_controller_test.exs** (16KB)
   - Tests REST API endpoints
   - Tests error handling
   - Tests parameter validation

7. **test/support/paper_trading_helpers.ex** (4.8KB)
   - Shared test utilities
   - Data generators
   - Test fixtures

## Running Tests

### Run All Tests
```bash
mix test
```

### Run Specific Test File
```bash
# Stream subscriber tests
mix test test/trading_strategy/market_data/stream_subscriber_test.exs

# Signal detector tests
mix test test/trading_strategy/strategies/realtime_signal_detector_test.exs

# Paper executor tests
mix test test/trading_strategy/paper_trading/paper_executor_test.exs

# Position tracker tests
mix test test/trading_strategy/paper_trading/position_tracker_test.exs

# Cache tests
mix test test/trading_strategy/market_data/cache_test.exs

# Controller tests
mix test test/trading_strategy_web/controllers/paper_trading_controller_test.exs
```

### Run Tests by Pattern
```bash
# Run all paper trading tests
mix test test/trading_strategy/paper_trading/

# Run all market data tests
mix test test/trading_strategy/market_data/

# Run all controller tests
mix test test/trading_strategy_web/
```

### Run Specific Test
```bash
# Run specific test by line number
mix test test/trading_strategy/market_data/cache_test.exs:42
```

### Run with Coverage
```bash
mix test --cover
```

### Run with Verbose Output
```bash
mix test --trace
```

### Run Only Failed Tests
```bash
mix test --failed
```

## Test Structure

### Typical Test Pattern
```elixir
defmodule MyModuleTest do
  use ExUnit.Case, async: true  # or async: false for shared state

  setup do
    # Setup code runs before each test
    %{fixture: "data"}
  end

  describe "function_name/arity" do
    test "describes what it should do", %{fixture: fixture} do
      # Arrange
      input = prepare_input()

      # Act
      result = MyModule.function_name(input)

      # Assert
      assert result == expected_value
    end
  end
end
```

## Common Assertions

```elixir
# Equality
assert actual == expected
refute actual == unexpected

# Pattern matching
assert {:ok, result} = function_call()

# Numeric comparisons
assert value > 0
assert_in_delta float_value, expected, 0.001

# Boolean
assert is_map(value)
assert is_binary(value)

# Message reception
assert_receive {:message, _data}, 1000
refute_receive {:unexpected_message, _}, 500

# Exceptions
assert_raise ArgumentError, fn -> function() end
```

## Using Test Helpers

```elixir
# In your test file
import TradingStrategy.PaperTradingHelpers

test "example using helpers" do
  # Generate test data
  strategy = sample_strategy()
  bar = sample_bar(base_price: 43000.0)
  indicators = sample_indicator_values(rsi: 25.0)

  # Create pre-populated tracker
  tracker = tracker_with_positions(10000.0, [
    [symbol: "BTC/USD", side: :long, entry_price: 43000.0]
  ])

  # Use in tests
  assert PositionTracker.has_open_positions?(tracker)
end
```

## Test Data Generators

### Sample Strategy
```elixir
strategy = sample_strategy(
  name: "My Strategy",
  entry_conditions: "rsi_14 < 30",
  exit_conditions: "rsi_14 > 70"
)
```

### Sample Bar
```elixir
bar = sample_bar(
  timestamp: ~U[2025-12-04 12:00:00Z],
  base_price: 43000.0,
  symbol: "BTC/USD"
)
```

### Sample Bar Series
```elixir
bars = sample_bar_series(100,
  base_price: 43000.0,
  start_time: ~U[2025-12-04 00:00:00Z],
  interval_seconds: 3600  # 1 hour
)
```

## Debugging Tests

### Print Debug Info
```elixir
test "debugging example" do
  result = some_function()
  IO.inspect(result, label: "Result")
  assert result.status == :ok
end
```

### Use IEx.pry
```elixir
test "interactive debugging" do
  result = some_function()
  require IEx; IEx.pry()  # Breakpoint
  assert result.status == :ok
end
```

### Capture Logs
```elixir
import ExUnit.CaptureLog

test "with log capture" do
  log = capture_log(fn ->
    function_that_logs()
  end)

  assert log =~ "Expected log message"
end
```

## Common Issues & Solutions

### Issue: Tests Pass Individually but Fail Together
**Solution**: Tests are not isolated. Check for:
- Shared GenServer state
- ETS tables not cleaned up
- Database transactions not rolled back
- Use `async: false` for tests with shared state

### Issue: Flaky Tests
**Solution**:
- Avoid timing-based assertions
- Use proper synchronization (`assert_receive` with timeout)
- Clean up processes in `on_exit`
- Don't rely on execution order

### Issue: Database Conflicts
**Solution**:
```elixir
setup tags do
  :ok = Ecto.Adapters.SQL.Sandbox.checkout(Repo)

  unless tags[:async] do
    Ecto.Adapters.SQL.Sandbox.mode(Repo, {:shared, self()})
  end

  :ok
end
```

### Issue: GenServer Not Stopping
**Solution**:
```elixir
setup do
  {:ok, pid} = start_supervised(MyGenServer)
  # supervised processes are automatically stopped
  %{pid: pid}
end

# OR manually:
on_exit(fn ->
  if Process.alive?(pid) do
    GenServer.stop(pid)
  end
end)
```

## Test Coverage

### View Coverage Report
```bash
mix test --cover
```

### Generate HTML Coverage Report
```bash
# Add to mix.exs
test_coverage: [tool: ExCoveralls]

# Install excoveralls
{:excoveralls, "~> 0.18", only: :test}

# Run
mix coveralls.html
open cover/excoveralls.html
```

## Next Steps

1. **Run tests to verify they work**
   ```bash
   mix test
   ```

2. **Add Mox for proper mocking**
   - See PHASE_5_TEST_SUMMARY.md for details

3. **Set up CI/CD**
   - Add GitHub Actions workflow
   - Run tests on every PR

4. **Monitor coverage**
   - Aim for >80% overall
   - Critical paths should have >95%

5. **Add integration tests**
   - Full session lifecycle
   - Real PubSub flows
   - Database persistence

## Resources

- [ExUnit Guide](https://hexdocs.pm/ex_unit/ExUnit.html)
- [Testing Elixir Book](https://pragprog.com/titles/lmelixir/testing-elixir/)
- [Phoenix Testing](https://hexdocs.pm/phoenix/testing.html)
- [Mox Documentation](https://hexdocs.pm/mox/Mox.html)

## Notes

⚠️ **Important**: Some tests use stub functions instead of proper mocks. For production:
1. Implement Mox behaviours for external APIs
2. Add proper test database setup
3. Create mock implementations for CryptoExchange.API
4. Add property-based testing with StreamData

✅ **Test Coverage Target**: >80% overall, >95% for critical modules

📊 **Current Test Count**: ~150+ test cases across all modules
