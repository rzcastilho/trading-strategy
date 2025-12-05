# Trading Strategy DSL Library - Quick Start Guide

**Feature**: 001-strategy-dsl-library
**Version**: 1.0.0
**Last Updated**: 2025-12-04

This guide helps you get started with the Trading Strategy DSL Library, from defining your first strategy to running backtests and deploying to live trading.

---

## Table of Contents

1. [Prerequisites](#prerequisites)
2. [Installation](#installation)
3. [Define Your First Strategy](#define-your-first-strategy)
4. [Run a Backtest](#run-a-backtest)
5. [Paper Trading](#paper-trading)
6. [Live Trading](#live-trading)
7. [Monitoring & Metrics](#monitoring--metrics)
8. [Troubleshooting](#troubleshooting)

---

## Prerequisites

### System Requirements
- **Elixir**: 1.17+ (with OTP 27+)
- **PostgreSQL**: 14+ with TimescaleDB extension
- **Redis**: 6+ (for distributed rate limiting, optional for single-node)
- **Operating System**: Linux (production), macOS/Linux (development)

### Recommended Knowledge
- Basic understanding of technical analysis indicators (RSI, MACD, moving averages)
- Familiarity with YAML configuration syntax
- Understanding of cryptocurrency trading concepts

### Exchange Account (for live trading)
- Binance, Coinbase Pro, or Kraken account
- API keys with trading permissions
- **IMPORTANT**: Start with small capital allocation for testing

---

## Installation

### 1. Clone the Repository

```bash
git clone https://github.com/your-org/trading-strategy.git
cd trading-strategy
```

### 2. Install Dependencies

```elixir
# mix.exs
defp deps do
  [
    {:phoenix, "~> 1.7"},
    {:phoenix_live_view, "~> 1.0"},
    {:ecto_sql, "~> 3.12"},
    {:postgrex, "~> 0.19"},
    {:yaml_elixir, "~> 2.12"},
    {:toml, "~> 0.7"},
    {:indicado, "~> 0.0.4"},
    {:websockex, "~> 0.4"},
    {:hammer, "~> 7.1"},
    {:external_service, "~> 1.1"},
    {:retry, "~> 0.18"}
  ]
end
```

```bash
mix deps.get
```

### 3. Configure Database

```bash
# Create database
mix ecto.create

# Run migrations
mix ecto.migrate

# Enable TimescaleDB extension
psql -d trading_strategy_dev -c "CREATE EXTENSION IF NOT EXISTS timescaledb;"
```

### 4. Configure Application

```elixir
# config/dev.exs
config :trading_strategy, TradingStrategy.Repo,
  username: "postgres",
  password: "postgres",
  hostname: "localhost",
  database: "trading_strategy_dev",
  pool_size: 10

# Redis for rate limiting (optional for single-node dev)
config :hammer,
  backend: {Hammer.Backend.Redis,
    redis_url: "redis://localhost:6379",
    pool_size: 4
  }
```

### 5. Start the Application

```bash
mix phx.server
```

Visit `http://localhost:4000` to see the dashboard (if web interface enabled).

---

## Define Your First Strategy

Let's create a simple RSI Mean Reversion strategy that buys when RSI < 30 and sells when RSI > 70.

### 1. Create Strategy Configuration File

```yaml
# strategies/rsi_mean_reversion.yaml
strategy_id: "550e8400-e29b-41d4-a716-446655440000"
name: "RSI Mean Reversion"
description: "Buy oversold (RSI < 30), sell overbought (RSI > 70)"
trading_pair: "BTC/USD"
timeframe: "1h"
version: "1.0.0"

indicators:
  - type: "rsi"
    name: "rsi_14"
    parameters:
      period: 14

  - type: "sma"
    name: "sma_50"
    parameters:
      period: 50

entry_conditions: "rsi_14 < 30 AND close > sma_50"
exit_conditions: "rsi_14 > 70"
stop_conditions: "rsi_14 < 25 OR unrealized_pnl_pct < -0.05"

position_sizing:
  type: "percentage"
  percentage_of_capital: 0.10  # 10% per trade
  max_position_size: 0.25      # Max 25% of portfolio

risk_parameters:
  max_daily_loss: 0.03          # 3% daily loss limit
  max_drawdown: 0.15            # 15% max drawdown
  stop_loss_percentage: 0.05    # 5% stop-loss
  take_profit_percentage: 0.10  # 10% take-profit (optional)
```

### 2. Validate Strategy

```elixir
# In IEx (iex -S mix)
iex> {:ok, strategy} = TradingStrategy.API.parse_strategy("strategies/rsi_mean_reversion.yaml", :yaml)
iex> TradingStrategy.API.validate_strategy(strategy)
{:ok, %{strategy_id: "550e8400-...", name: "RSI Mean Reversion", ...}}
```

### 3. Create Strategy in Database

```elixir
iex> {:ok, strategy_id} = TradingStrategy.API.create_strategy(strategy)
{:ok, "550e8400-e29b-41d4-a716-446655440000"}
```

**Success!** Your strategy is now defined and ready for testing.

---

## Run a Backtest

Validate your strategy against historical data before risking capital.

### 1. Configure Backtest

```elixir
backtest_config = %{
  strategy_id: "550e8400-e29b-41d4-a716-446655440000",
  trading_pair: "BTC/USD",
  start_date: ~U[2023-01-01 00:00:00Z],
  end_date: ~U[2024-12-31 23:59:59Z],
  initial_capital: Decimal.new("10000"),
  position_sizing: :percentage,
  commission_rate: Decimal.new("0.001"),  # 0.1% per trade
  slippage_bps: 5,  # 5 basis points (0.05%)
  data_source: "binance"
}
```

### 2. Start Backtest

```elixir
iex> {:ok, backtest_id} = TradingStrategy.Backtest.start_backtest(backtest_config)
{:ok, "backtest_abc123"}
```

### 3. Monitor Progress

```elixir
iex> TradingStrategy.Backtest.get_backtest_progress(backtest_id)
{:ok, %{
  status: :running,
  progress_percentage: 45,
  bars_processed: 6570,
  total_bars: 14600,
  estimated_time_remaining_ms: 12000
}}
```

### 4. View Results

```elixir
iex> {:ok, results} = TradingStrategy.Backtest.get_backtest_result(backtest_id)
{:ok, %{
  performance_metrics: %{
    total_return: Decimal.new("0.342"),  # 34.2% return
    sharpe_ratio: Decimal.new("1.8"),
    max_drawdown: Decimal.new("0.12"),   # 12% max drawdown
    win_rate: Decimal.new("0.58"),       # 58% win rate
    trade_count: 156,
    average_win: Decimal.new("245.50"),
    average_loss: Decimal.new("-123.25"),
    profit_factor: Decimal.new("2.1")
  },
  trades: [...],
  equity_curve: [...],
  data_quality_warnings: [...]
}}
```

### Interpreting Results

**Minimum Success Criteria (from Constitution):**
- ✅ Sharpe ratio > 1.0 required before paper trading
- ✅ Backtest processed 2 years of data (FR-007, Constitution II)
- ✅ Transaction costs and slippage included (FR-011)

**Next Steps:**
- If Sharpe ratio ≥ 1.0: Proceed to paper trading
- If Sharpe ratio < 1.0: Refine strategy parameters and re-backtest
- Analyze trade-by-trade to understand entry/exit timing

---

## Paper Trading

Test your strategy in real-time market conditions without risking capital.

### 1. Start Paper Session

```elixir
paper_config = %{
  strategy_id: "550e8400-e29b-41d4-a716-446655440000",
  trading_pair: "BTC/USD",
  initial_capital: Decimal.new("10000"),
  data_source: "binance",
  position_sizing: :percentage
}

iex> {:ok, session_id} = TradingStrategy.PaperTrading.start_paper_session(paper_config)
{:ok, "session_abc123"}
```

### 2. Monitor Session Status

```elixir
iex> TradingStrategy.PaperTrading.get_paper_session_status(session_id)
{:ok, %{
  status: :active,
  current_equity: Decimal.new("10450.23"),
  unrealized_pnl: Decimal.new("120.50"),
  realized_pnl: Decimal.new("329.73"),
  open_positions: [
    %{
      trading_pair: "BTC/USD",
      side: :long,
      entry_price: Decimal.new("42150.00"),
      current_price: Decimal.new("43200.00"),
      unrealized_pnl: Decimal.new("105.00")
    }
  ],
  trades_count: 8
}}
```

### 3. View Trade History

```elixir
iex> {:ok, trades} = TradingStrategy.PaperTrading.get_paper_session_trades(session_id, limit: 10)
{:ok, [
  %{
    timestamp: ~U[2025-12-04 10:15:30Z],
    side: :buy,
    quantity: Decimal.new("0.1"),
    price: Decimal.new("42150.00"),
    signal_type: :entry
  },
  ...
]}
```

### 4. Stop Paper Session (After 30+ Days Minimum)

```elixir
iex> {:ok, results} = TradingStrategy.PaperTrading.stop_paper_session(session_id)
{:ok, %{
  duration_seconds: 2592000,  # 30 days
  final_equity: Decimal.new("11250.00"),
  total_return: Decimal.new("0.125"),  # 12.5%
  performance_metrics: %{...}
}}
```

**Constitution Requirement:**
- Paper trading for **minimum 30 days** before live capital (Development Workflow)
- Monitor for system stability, signal accuracy, and behavioral differences from backtest

---

## Live Trading

**⚠️ WARNING: Live trading involves real capital and financial risk.**

### Prerequisites Checklist
- ✅ Backtest Sharpe ratio > 1.0
- ✅ Paper trading for 30+ days completed
- ✅ Strategy parameters finalized (no further changes)
- ✅ Exchange API keys obtained (read-write permissions)
- ✅ Risk limits configured conservatively
- ✅ Gradual capital allocation plan (1% → 5% → 10% → full)

### 1. Start Live Session

```elixir
live_config = %{
  strategy_id: "550e8400-e29b-41d4-a716-446655440000",
  trading_pair: "BTC/USD",
  allocated_capital: Decimal.new("500"),  # START SMALL (1% of portfolio)
  exchange: "binance",
  api_credentials: %{
    api_key: System.get_env("BINANCE_API_KEY"),
    api_secret: System.get_env("BINANCE_API_SECRET"),
    passphrase: nil
  },
  position_sizing: :percentage,
  risk_limits: %{
    max_position_size_pct: Decimal.new("0.25"),
    max_daily_loss_pct: Decimal.new("0.03"),
    max_drawdown_pct: Decimal.new("0.15"),
    max_concurrent_positions: 3
  }
}

iex> {:ok, session_id} = TradingStrategy.LiveTrading.start_live_session(live_config)
{:ok, "live_session_abc123"}
```

**IMPORTANT**: API credentials are NEVER persisted to database (FR-018). They exist only in GenServer state (memory).

### 2. Monitor Live Session

```elixir
iex> TradingStrategy.LiveTrading.get_live_session_status(session_id)
{:ok, %{
  status: :active,
  connectivity_status: :connected,
  current_equity: Decimal.new("525.00"),
  open_positions: [...],
  pending_orders: [...],
  risk_limits_status: %{
    position_size_utilization_pct: Decimal.new("0.20"),
    daily_loss_used_pct: Decimal.new("0.00"),
    drawdown_from_peak_pct: Decimal.new("0.02"),
    can_open_new_position: true
  }
}}
```

### 3. Emergency Stop

```elixir
# Closes all positions immediately at market price
iex> TradingStrategy.LiveTrading.stop_live_session(session_id)
{:ok, %{final_equity: Decimal.new("523.50"), ...}}
```

### Gradual Capital Allocation (Recommended)

1. **Week 1-2**: 1% of portfolio ($500 on $50k portfolio)
2. **Week 3-4**: 5% of portfolio ($2,500) if performance acceptable
3. **Month 2**: 10% of portfolio ($5,000) if continued success
4. **Month 3+**: Full allocation only after consistent profitability

---

## Monitoring & Metrics

### Performance Metrics Explained

| Metric | Description | Good Value | Poor Value |
|--------|-------------|------------|------------|
| **Total Return** | % profit/loss on capital | > 20% annually | < 5% annually |
| **Sharpe Ratio** | Risk-adjusted return | > 1.0 (required for paper) | < 0.5 |
| **Max Drawdown** | Largest peak-to-trough decline | < 15% | > 30% |
| **Win Rate** | % of profitable trades | > 50% | < 35% |
| **Profit Factor** | Gross profit / gross loss | > 1.5 | < 1.2 |
| **Trade Count** | Number of trades executed | Varies by strategy | Too few (< 30) |

### Viewing Metrics

```elixir
# Backtest metrics
iex> {:ok, results} = TradingStrategy.Backtest.get_backtest_result(backtest_id)
iex> results.performance_metrics

# Paper session metrics
iex> {:ok, metrics} = TradingStrategy.PaperTrading.get_paper_session_metrics(session_id)

# Live session trade history
iex> {:ok, trades} = TradingStrategy.LiveTrading.get_live_session_trades(session_id, limit: 50)
```

### Dashboard (Web Interface)

Visit `http://localhost:4000/dashboard` for real-time monitoring:
- Equity curve visualization
- Open positions table
- Recent trades log
- Risk limits gauges
- Connectivity status

---

## Troubleshooting

### Common Issues

#### 1. "Insufficient data for indicator calculation"

**Problem**: Not enough historical bars to calculate indicator (e.g., 200-period SMA needs 200 bars).

**Solution**:
```elixir
# Check available data
iex> TradingStrategy.MarketData.validate_data_quality(
  "BTC/USD",
  ~U[2023-01-01 00:00:00Z],
  ~U[2024-12-31 23:59:59Z],
  "1h",
  "binance"
)
```

Ensure date range provides enough bars for longest indicator period + buffer.

---

#### 2. "Strategy validation failed: undefined variable 'foo'"

**Problem**: Indicator referenced in conditions but not defined in `indicators` list.

**Solution**: Verify all indicator names in `entry_conditions`, `exit_conditions`, and `stop_conditions` match `name` fields in `indicators` list.

---

#### 3. "Rate limited by exchange"

**Problem**: Too many API requests (FR-023).

**Solution**: System automatically queues and retries with exponential backoff (1s, 2s, 4s, 8s). Monitor logs:

```elixir
# Check queue depth
iex> TradingStrategy.ExchangeClient.get_queue_status("binance")
{:ok, %{critical_queue_depth: 0, normal_queue_depth: 5}}
```

If persistent, reduce trading frequency or upgrade exchange API tier.

---

#### 4. "WebSocket disconnected"

**Problem**: Connection to exchange lost (FR-022).

**Solution**: System automatically reconnects with exponential backoff. Check status:

```elixir
iex> TradingStrategy.PaperTrading.get_paper_session_status(session_id)
{:ok, %{connectivity_status: :connected}}
```

If `:disconnected` persists > 5 minutes, check network/exchange status.

---

#### 5. "Risk limits exceeded"

**Problem**: Proposed trade violates risk thresholds (FR-021).

**Solution**:
```elixir
iex> TradingStrategy.LiveTrading.get_live_session_status(session_id)
{:ok, %{
  risk_limits_status: %{
    daily_loss_used_pct: Decimal.new("0.029"),  # 2.9% of 3% limit used
    can_open_new_position: false
  }
}}
```

- Wait for daily reset (00:00 UTC) for `daily_loss_limit`
- Close positions to reduce `drawdown_from_peak`
- Adjust `risk_parameters` in strategy definition if limits too conservative

---

### Logs & Debugging

**Structured Logging (FR-028):**
```elixir
# Enable debug logging
Logger.configure(level: :debug)

# View recent trading decisions
grep "Signal detected" logs/trading_strategy.log

# View error context
grep "ERROR" logs/trading_strategy.log | tail -n 20
```

**Telemetry Events:**
```elixir
# Attach telemetry handler for debugging
:telemetry.attach(
  "debug-handler",
  [:trading_strategy, :signal, :detected],
  fn _event, measurements, metadata, _config ->
    IO.inspect(metadata, label: "Signal")
  end,
  nil
)
```

---

## Next Steps

1. **Read Full Documentation**: See `/docs` directory for detailed API reference
2. **Review Constitution**: Understand design principles in `.specify/memory/constitution.md`
3. **Explore Examples**: Check `/examples` for more strategy configurations
4. **Join Community**: (Link to Discord/Slack/Forum)
5. **Report Issues**: https://github.com/your-org/trading-strategy/issues

---

## Important Reminders

✅ **ALWAYS backtest** before paper trading (Constitution Principle II)
✅ **Paper trade 30+ days** before live capital (Development Workflow)
✅ **Start with small capital** (1% of portfolio) in live trading
✅ **Monitor risk limits** daily in live trading
✅ **Never commit API credentials** to version control
✅ **Review trades regularly** to validate strategy assumptions

**Questions?** Consult the constitution (`.specify/memory/constitution.md`) for design philosophy and mandatory requirements.

---

**Happy Trading! 🚀**

*Remember: Past performance does not guarantee future results. Trade responsibly.*
