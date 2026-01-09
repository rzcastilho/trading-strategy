# Trading Strategy DSL Library

A comprehensive trading strategy library for cryptocurrency markets, built with Elixir and Phoenix. Define strategies using a declarative DSL (YAML/TOML), validate through backtesting, test in paper trading mode, and deploy to live trading with built-in risk management.

## Features

- **Declarative DSL**: Define strategies in YAML or TOML without writing code
- **Comprehensive Indicators**: 22+ technical indicators (RSI, MACD, SMA, EMA, Bollinger Bands, etc.)
- **Backtesting Engine**: Test strategies on 2+ years of historical data with realistic commissions and slippage
- **Paper Trading**: Real-time simulation with live market data via WebSocket
- **Live Trading**: Automated execution with exchange integration (Binance, Coinbase, Kraken)
- **Risk Management**: Portfolio-level limits, position sizing, stop-loss/take-profit automation
- **Observability**: Structured logging, telemetry metrics, performance tracking
- **Fault Tolerance**: OTP supervision trees, automatic reconnection, circuit breakers

## Quick Start

### Prerequisites

- **Elixir**: 1.17+ (OTP 27+)
- **PostgreSQL**: 14+ with TimescaleDB extension
- **Docker**: For local development environment (optional)

### Installation

1. Clone the repository:
```bash
git clone https://github.com/rzcastilho/trading-strategy.git
cd trading-strategy
```

2. Install dependencies:
```bash
mix deps.get
```

3. Set up the database:
```bash
# Start PostgreSQL with TimescaleDB (Docker)
docker-compose up -d postgres

# Create and migrate database
mix ecto.create
mix ecto.migrate
```

4. Start the application:
```bash
mix phx.server
```

Visit `http://localhost:4000` to access the dashboard.

### Your First Strategy

Create a simple RSI mean reversion strategy:

```yaml
# strategies/my_strategy.yaml
name: "RSI Mean Reversion"
trading_pair: "BTC/USD"
timeframe: "1h"

indicators:
  - type: "rsi"
    name: "rsi_14"
    parameters:
      period: 14

entry_conditions: "rsi_14 < 30"
exit_conditions: "rsi_14 > 70"
stop_conditions: "rsi_14 < 25"

position_sizing:
  type: "percentage"
  percentage_of_capital: 0.10

risk_parameters:
  max_daily_loss: 0.03
  max_drawdown: 0.15
  stop_loss_percentage: 0.05
```

### Run a Backtest

```elixir
iex> {:ok, strategy} = TradingStrategy.API.parse_strategy("strategies/my_strategy.yaml", :yaml)
iex> {:ok, strategy_id} = TradingStrategy.API.create_strategy(strategy)

iex> backtest_config = %{
  strategy_id: strategy_id,
  trading_pair: "BTC/USD",
  start_date: ~U[2023-01-01 00:00:00Z],
  end_date: ~U[2024-12-31 23:59:59Z],
  initial_capital: Decimal.new("10000"),
  commission_rate: Decimal.new("0.001"),
  slippage_bps: 5
}

iex> {:ok, backtest_id} = TradingStrategy.Backtest.start_backtest(backtest_config)
iex> {:ok, results} = TradingStrategy.Backtest.get_backtest_result(backtest_id)
iex> results.performance_metrics
# => %{total_return: Decimal.new("0.34"), sharpe_ratio: Decimal.new("1.8"), ...}
```

## Documentation

- **[Quick Start Guide](specs/001-strategy-dsl-library/quickstart.md)** - Detailed getting started guide
- **[API Reference](docs/api.md)** - Complete API documentation
- **[DSL Reference](docs/dsl_reference.md)** - Strategy DSL syntax guide
- **[Deployment Guide](docs/deployment.md)** - Production deployment instructions
- **[Examples](examples/)** - Sample strategy configurations

## Architecture

Built on Elixir/OTP for fault tolerance and scalability:

- **Phoenix 1.7+**: Web framework and REST API
- **Ecto + PostgreSQL**: Data persistence
- **TimescaleDB**: Time-series market data storage
- **GenServer**: Strategy execution processes
- **Supervision Trees**: Automatic failure recovery
- **WebSocket**: Real-time market data streaming

### Core Components

```
lib/trading_strategy/
├── strategies/          # Strategy DSL parsing and execution
├── market_data/         # Market data ingestion and storage
├── backtesting/         # Backtest engine and metrics
├── paper_trading/       # Paper trading session management
├── live_trading/        # Live trading with exchange integration
├── risk/                # Risk management and position sizing
└── orders/              # Order execution and tracking
```

## Trading Modes

### 1. Backtesting

Validate strategies against historical data:
- 2+ years of OHLCV data
- Realistic commission and slippage modeling
- Performance metrics: Sharpe ratio, max drawdown, win rate

### 2. Paper Trading

Test in real-time without risking capital:
- Live market data via WebSocket
- Simulated order execution
- Position tracking and P&L monitoring
- Minimum 30 days before live trading

### 3. Live Trading

Automated execution with real capital:
- Exchange integration (Binance, Coinbase, Kraken)
- Risk limit enforcement (max position, daily loss, drawdown)
- Emergency stop mechanism
- Audit logging with correlation IDs

## Risk Management

Built-in safeguards:
- **Position Sizing**: Percentage-based or fixed amount allocation
- **Stop-Loss**: Automatic exit on price threshold
- **Take-Profit**: Lock in gains at target levels
- **Daily Loss Limit**: Pause trading after threshold
- **Max Drawdown**: Emergency stop on peak-to-trough decline
- **Portfolio Limits**: Maximum allocation across positions

## Constitution Principles

Development follows strict guidelines:

1. **Strategy-as-Library**: Each strategy is self-contained with independent tests
2. **Backtesting Required**: Minimum 2 years historical data before paper trading
3. **Risk Management First**: All limits configurable and enforced at runtime
4. **Observability & Auditability**: Structured logging for all trading decisions
5. **Performance Discipline**: <50ms p95 decision latency, <100ms p95 order placement

See [Constitution](.specify/memory/constitution.md) for details.

## Development

### Run Tests

```bash
# All tests
mix test

# With coverage
mix test --cover

# Specific test file
mix test test/trading_strategy/strategies/dsl/parser_test.exs
```

### Code Quality

```bash
# Format code
mix format

# Static analysis
mix credo --strict

# Generate documentation
mix docs
```

## Contributing

1. Fork the repository
2. Create a feature branch (`git checkout -b feature/amazing-feature`)
3. Commit changes (`git commit -m 'Add amazing feature'`)
4. Push to branch (`git push origin feature/amazing-feature`)
5. Open a Pull Request

## License

This project is licensed under the MIT License - see LICENSE file for details.

## Disclaimer

**Trading cryptocurrencies involves substantial risk of loss. This software is for educational purposes only. Use at your own risk. The authors are not responsible for any financial losses incurred.**

## Support

- **Issues**: [GitHub Issues](https://github.com/rzcastilho/trading-strategy/issues)
- **Discussions**: [GitHub Discussions](https://github.com/rzcastilho/trading-strategy/discussions)
- **Documentation**: [Full Documentation](docs/)

## Acknowledgments

- Built with [Elixir](https://elixir-lang.org/) and [Phoenix](https://www.phoenixframework.org/)
- Indicators powered by [trading-indicators](https://github.com/rzcastilho/trading-indicators)
- Exchange integration via [crypto-exchange](https://github.com/rzcastilho/crypto-exchange)
