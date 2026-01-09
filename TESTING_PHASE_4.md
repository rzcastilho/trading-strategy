# Testing Phase 1-4: Quick Start Guide

This guide will help you validate that all features from Phase 1-4 are working correctly.

## Quick Start (Recommended)

The easiest way to test is using the automated test script:

```bash
# Make the script executable (first time only)
chmod +x test_phase_4.sh

# Run the test
./test_phase_4.sh
```

This script will:
1. ✅ Check prerequisites (Elixir, PostgreSQL)
2. ✅ Install dependencies if needed
3. ✅ Create and migrate the database
4. ✅ Compile the project
5. ✅ Run the comprehensive integration test
6. ✅ Display detailed results

## Manual Testing

If you prefer to run steps manually:

### 1. Prerequisites

```bash
# Check Elixir version (need 1.17+)
elixir --version

# Start PostgreSQL (if using Docker)
docker-compose up -d postgres
```

### 2. Setup

```bash
# Install dependencies
mix deps.get

# Create database
mix ecto.create

# Run migrations
mix ecto.migrate

# Compile project
mix compile
```

### 3. Run Integration Test

```bash
mix run priv/scripts/test_phase_4.exs
```

## What Gets Tested

### Phase 1: Database & Infrastructure
- ✅ PostgreSQL connection
- ✅ Ecto repository configuration
- ✅ Database migrations (8 tables)

### Phase 2: Schemas & Persistence
- ✅ Strategy schema
- ✅ TradingSession schema
- ✅ Trade schema
- ✅ PerformanceMetrics schema
- ✅ Market data seeding (100 OHLCV bars)

### Phase 3: Strategy DSL
- ✅ YAML parsing
- ✅ Strategy validation
- ✅ Strategy creation (CRUD operations)
- ✅ Indicator reference validation
- ✅ Condition syntax validation

### Phase 4: Backtesting
- ✅ Historical data retrieval
- ✅ Asynchronous backtest execution
- ✅ Progress monitoring
- ✅ Performance metrics calculation:
  - Total return
  - Sharpe ratio
  - Maximum drawdown
  - Win rate
  - Trade count
  - Winning/losing trades
  - Average win/loss
  - Profit factor
- ✅ Trade history tracking
- ✅ Equity curve generation

## Expected Results

### Successful Test Output

```
================================================================================
  Trading Strategy DSL Library - Phase 1-4 Integration Test
================================================================================

▶ Phase 1: Database Setup & Connectivity
  ✓ Database connection established
  ✓ Ecto.Repo loaded
  ✓ All required tables exist

▶ Phase 2: Foundational Infrastructure
  ✓ TradingStrategy.Strategies.Strategy loaded
  ✓ TradingStrategy.Backtesting.TradingSession loaded
  ✓ TradingStrategy.Orders.Trade loaded
  ✓ TradingStrategy.Backtesting.PerformanceMetrics loaded
  ✓ Seeded 100 market data bars

▶ Phase 3: Strategy DSL (Define Strategy)
  ✓ Strategy YAML parsed successfully
  ✓ Strategy DSL structure valid
  ✓ Strategy created with ID: 550e8400-...
  ✓ Strategy retrieved successfully
  ✓ Found 3 indicators: rsi_14, sma_50, ema_20

▶ Phase 4: Backtesting
  ✓ Found 100 historical bars
  ✓ Backtest started with ID: abc123-...
  ✓ Backtest completed
  ✓ Retrieved backtest results
  ✓ All performance metrics present
  ✓ Found N trades

✅ ALL PHASES COMPLETED SUCCESSFULLY!
```

### Performance Metrics

The test will display:
- **Total Return**: % profit/loss on initial capital
- **Sharpe Ratio**: Risk-adjusted return (>1.0 is good)
- **Max Drawdown**: Largest peak-to-trough decline
- **Win Rate**: Percentage of profitable trades
- **Trade Count**: Number of trades executed

## Testing the REST API

After the integration test passes, you can test the API endpoints:

### 1. Start the Phoenix Server

```bash
mix phx.server
```

### 2. Create a Strategy

```bash
curl -X POST http://localhost:4000/api/strategies \
  -H "Content-Type: application/json" \
  -d '{
    "name": "API Test Strategy",
    "format": "yaml",
    "content": "name: API Test\ntrading_pair: BTCUSDT\ntimeframe: 1h\nindicators:\n  - type: rsi\n    name: rsi_14\n    parameters:\n      period: 14\nentry_conditions: \"rsi_14 < 30\"\nexit_conditions: \"rsi_14 > 70\"\nstop_conditions: \"false\"\nposition_sizing:\n  type: percentage\n  percentage_of_capital: 0.10\nrisk_parameters:\n  max_daily_loss: 0.03\n  max_drawdown: 0.15"
  }'
```

### 3. List Strategies

```bash
curl http://localhost:4000/api/strategies
```

### 4. Run a Backtest

```bash
# Replace STRATEGY_ID with the ID from step 2
curl -X POST http://localhost:4000/api/backtests \
  -H "Content-Type: application/json" \
  -d '{
    "strategy_id": "STRATEGY_ID",
    "trading_pair": "BTCUSDT",
    "start_date": "2024-01-01T00:00:00Z",
    "end_date": "2024-01-31T23:59:59Z",
    "initial_capital": "10000",
    "commission_rate": "0.001",
    "slippage_bps": 5
  }'
```

### 5. Check Backtest Progress

```bash
# Replace BACKTEST_ID with the ID from step 4
curl http://localhost:4000/api/backtests/BACKTEST_ID/progress
```

### 6. Get Backtest Results

```bash
curl http://localhost:4000/api/backtests/BACKTEST_ID
```

## Troubleshooting

### Database Connection Failed

**Problem**: Can't connect to PostgreSQL

**Solutions**:
```bash
# If using Docker
docker-compose up -d postgres

# Check container status
docker-compose ps

# Check logs
docker-compose logs postgres

# Verify config in config/dev.exs matches your setup
```

### Missing Tables

**Problem**: Migration errors or missing tables

**Solutions**:
```bash
# Drop and recreate database
mix ecto.drop
mix ecto.create
mix ecto.migrate

# Or just run migrations
mix ecto.migrate
```

### Compilation Errors

**Problem**: Project won't compile

**Solutions**:
```bash
# Clean and recompile
mix clean
mix deps.clean --all
mix deps.get
mix compile
```

### No Trades in Backtest

**Problem**: Backtest completes but no trades executed

**Explanation**: This is normal if the strategy conditions were never met during the test period. The random market data may not trigger entry conditions.

**Solutions**:
- This is OK - the test validates that the system works
- Try running multiple times (different random data)
- Adjust strategy conditions to be less restrictive

### Backtest Timeout

**Problem**: Backtest takes too long or times out

**Solutions**:
```bash
# Check if backtest process is still running
ps aux | grep beam

# Increase timeout in test script
# Edit priv/scripts/test_phase_4.exs
# Change: max_attempts = 30  # to higher value
```

## Performance Benchmarks

Expected performance on standard hardware:

| Metric | Expected | Your Result |
|--------|----------|-------------|
| Test Duration | < 30 seconds | |
| Database Setup | < 2 seconds | |
| Strategy Creation | < 100ms | |
| Backtest Execution (100 bars) | < 5 seconds | |
| Metrics Calculation | < 100ms | |

## Next Steps After Successful Test

1. ✅ **Explore the Code**
   - Review `lib/trading_strategy/backtesting/engine.ex`
   - Check `lib/trading_strategy/strategies/signal_evaluator.ex`
   - Examine `lib/trading_strategy/backtesting/metrics_calculator.ex`

2. ✅ **Create Custom Strategies**
   - Write your own YAML strategy files
   - Test different indicators (RSI, MACD, SMA, EMA, BB, etc.)
   - Experiment with complex conditions

3. ✅ **Run Real Backtests**
   - Fetch real historical data from exchanges
   - Test with 1-2 years of data
   - Optimize strategy parameters

4. ✅ **Prepare for Phase 5**
   - Review paper trading requirements
   - Set up WebSocket connections
   - Test real-time data streams

## Cleaning Up Test Data

To clean up after testing:

```elixir
# Start IEx
iex -S mix

# Delete test strategies
import Ecto.Query
alias TradingStrategy.Repo

from(s in TradingStrategy.Strategies.Strategy,
     where: like(s.name, "% Test%"))
|> Repo.delete_all()

# Delete test market data
from(m in TradingStrategy.MarketData.MarketData,
     where: m.data_source == "test")
|> Repo.delete_all()

# Delete test backtests
from(b in TradingStrategy.Backtesting.TradingSession,
     where: b.mode == "backtest")
|> Repo.delete_all()
```

## Support & Documentation

- **Test Script**: `priv/scripts/test_phase_4.exs`
- **Test Documentation**: `priv/scripts/README.md`
- **Feature Specs**: `specs/001-strategy-dsl-library/`
- **API Contracts**: `specs/001-strategy-dsl-library/contracts/`
- **Implementation Plan**: `specs/001-strategy-dsl-library/tasks.md`

## Success Criteria

Your Phase 1-4 implementation is ready when:

- ✅ All test phases pass without errors
- ✅ Performance metrics are calculated correctly
- ✅ Backtest executes in reasonable time (< 30s for 100 bars)
- ✅ REST API endpoints respond correctly
- ✅ Database persists all data properly
- ✅ Strategy DSL parses and validates correctly

**Congratulations!** 🎉 You now have a working trading strategy backtesting system!
