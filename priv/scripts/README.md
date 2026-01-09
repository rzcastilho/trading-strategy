# Integration Test Scripts

This directory contains scripts for testing the Trading Strategy DSL Library.

## Phase 4 Integration Test

**File**: `test_phase_4.exs`

Comprehensive end-to-end test that validates all features from Phase 1-4:

### What It Tests

**Phase 1: Database Setup & Connectivity**
- Database connection
- Ecto repository availability
- Required tables (migrations)

**Phase 2: Foundational Infrastructure**
- Schema modules (Strategy, TradingSession, Trade, PerformanceMetrics)
- Market data seeding (100 bars of sample OHLCV data)

**Phase 3: Strategy DSL**
- YAML parsing
- Strategy validation
- Strategy CRUD operations
- Indicator reference validation

**Phase 4: Backtesting**
- Historical data quality validation
- Backtest execution (asynchronous)
- Progress monitoring
- Performance metrics calculation
- Trade history verification

### Usage

```bash
# From the project root directory
mix run priv/scripts/test_phase_4.exs
```

### Prerequisites

1. **Database running**:
   ```bash
   # If using Docker
   docker-compose up -d postgres
   ```

2. **Database created and migrated**:
   ```bash
   mix ecto.create
   mix ecto.migrate
   ```

3. **Dependencies installed**:
   ```bash
   mix deps.get
   ```

### Expected Output

The script will display a progress indicator for each phase:

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
  ✓ Found 12 trades

✅ ALL PHASES COMPLETED SUCCESSFULLY!

Summary:
  Strategy: RSI Mean Reversion Test
  Strategy ID: 550e8400-e29b-41d4-a716-446655440000
  Backtest ID: abc123-def456-...

Performance Metrics:
  Total Return: 15.50%
  Sharpe Ratio: 1.25
  Max Drawdown: 8.30%
  Win Rate: 58.33%
  Trade Count: 12
  Winning Trades: 7
  Losing Trades: 5

Trades:
  Total Trades: 12
  First Trade: 2024-01-01 00:00:00Z (buy)
  Last Trade: 2024-01-05 08:00:00Z (sell)
```

### Test Strategy

The script uses a pre-defined RSI Mean Reversion strategy:

```yaml
name: RSI Mean Reversion Test
trading_pair: BTCUSDT
timeframe: 1h

indicators:
  - type: rsi
    name: rsi_14
    parameters:
      period: 14
  - type: sma
    name: sma_50
    parameters:
      period: 50
  - type: ema
    name: ema_20
    parameters:
      period: 20

entry_conditions: "rsi_14 < 30 AND close > sma_50"
exit_conditions: "rsi_14 > 70"
stop_conditions: "rsi_14 < 25 OR unrealized_pnl_pct < -0.05"

position_sizing:
  type: percentage
  percentage_of_capital: 0.10

risk_parameters:
  max_daily_loss: 0.03
  max_drawdown: 0.15
```

### Troubleshooting

**Error: Database connection failed**
- Ensure PostgreSQL is running
- Check database credentials in `config/dev.exs`

**Error: Missing tables**
- Run migrations: `mix ecto.migrate`

**Error: No historical data available**
- The script automatically seeds 100 bars of data
- If this fails, check database write permissions

**Error: Backtest timeout**
- Increase `max_attempts` in the script
- Check that the backtest engine is processing correctly

**Error: Strategy creation failed**
- Check that all schema fields are valid
- Verify indicator types are supported by TradingIndicators library

### What Success Looks Like

A successful test run indicates:

✅ **Phase 1**: Database and ORM working correctly
✅ **Phase 2**: All schemas defined and data persistence working
✅ **Phase 3**: Strategy DSL parser, validator, and CRUD operations functional
✅ **Phase 4**: Backtesting engine executes and calculates metrics correctly

### Cleaning Up

The script automatically cleans up test strategies before running. Market data is left in the database for subsequent test runs.

To manually clean up:

```elixir
# In IEx
iex -S mix

# Delete test strategies
from(s in TradingStrategy.Strategies.Strategy, where: like(s.name, "RSI Mean Reversion Test%")) |> Repo.delete_all()

# Delete test market data
from(m in TradingStrategy.MarketData.MarketData, where: m.data_source == "test") |> Repo.delete_all()

# Delete test backtests
from(b in TradingStrategy.Backtesting.TradingSession, where: b.mode == "backtest") |> Repo.delete_all()
```

### Next Steps

After a successful Phase 4 test:

1. **Manual API Testing**: Test the REST API endpoints directly
2. **Phase 5 Implementation**: Paper trading with real-time data
3. **Performance Testing**: Run backtests with larger datasets (1-2 years)
4. **Integration Testing**: Test with real exchange data

### Support

For issues or questions:
- Check logs in `logs/` directory
- Review the code in `lib/trading_strategy/`
- Consult the feature specification in `specs/001-strategy-dsl-library/`
