# TradingStrategy

A comprehensive Elixir library for defining, executing, and backtesting trading strategies with a declarative DSL.

## Features

- **Declarative DSL**: Define trading strategies using an intuitive, macro-based syntax
- **Indicator Integration**: Seamless integration with the [trading-indicators](https://github.com/rzcastilho/trading-indicators) library (22 indicators across 4 categories)
  - Automatic parameter validation
  - Data sufficiency checks
  - Streaming support for real-time updates
  - Graceful fallback from streaming to batch calculation
- **Decimal Precision**: All financial calculations use `Decimal` for exact precision (no floating-point errors)
- **Boolean Logic**: Combine conditions with AND/OR/NOT operators for complex entry/exit rules
- **Pattern Recognition**: Automatic detection of 11 candlestick patterns (hammer, engulfing, doji, etc.)
- **Multi-timeframe Analysis**: Analyze multiple timeframes simultaneously
- **GenServer-based Engine**: Real-time strategy execution with state management and indicator streaming
- **Backtesting Framework**: Comprehensive performance metrics including win rate, profit factor, Sharpe ratio, and drawdown analysis
- **Position Management**: Automatic tracking of open/closed positions with P&L calculations

## Installation

Add `trading_strategy` to your list of dependencies in `mix.exs`:

```elixir
def deps do
  [
    {:trading_strategy, "~> 0.1.0"}
  ]
end
```

## Quick Start

### 1. Define a Strategy

Create a strategy using the DSL:

```elixir
defmodule MyStrategy do
  use TradingStrategy.DSL

  defstrategy :ma_crossover do
    description "Moving average crossover with RSI confirmation"

    # Define indicators from trading-indicators library
    indicator :sma_fast, TradingIndicators.Trend.SMA, period: 10, source: :close
    indicator :sma_slow, TradingIndicators.Trend.SMA, period: 30, source: :close
    indicator :rsi, TradingIndicators.Momentum.RSI, period: 14, source: :close

    # Entry signal
    entry_signal :long do
      when_all do
        cross_above(:sma_fast, :sma_slow)
        indicator(:rsi) > 30
      end
    end

    # Exit signal
    exit_signal do
      when_any do
        cross_below(:sma_fast, :sma_slow)
        indicator(:rsi) > 70
      end
    end
  end
end
```

### 2. Run a Backtest

Test your strategy against historical data:

```elixir
# Load historical market data (using Decimal for price precision)
market_data = [
  %{
    open: Decimal.new("100"),
    high: Decimal.new("105"),
    low: Decimal.new("95"),
    close: Decimal.new("102"),
    volume: 1000,
    timestamp: ~U[2025-01-01 00:00:00Z]
  },
  %{
    open: Decimal.new("102"),
    high: Decimal.new("108"),
    low: Decimal.new("100"),
    close: Decimal.new("106"),
    volume: 1100,
    timestamp: ~U[2025-01-01 01:00:00Z]
  },
  # ... more candles
]

# Or use the helper function
alias TradingStrategy.Types
market_data = [
  Types.new_ohlcv(100, 105, 95, 102, 1000, ~U[2025-01-01 00:00:00Z]),
  Types.new_ohlcv(102, 108, 100, 106, 1100, ~U[2025-01-01 01:00:00Z])
]

# Get strategy definition
strategy = MyStrategy.strategy_definition()

# Run backtest
result = TradingStrategy.backtest(
  strategy: strategy,
  market_data: market_data,
  symbol: "BTCUSD",
  initial_capital: 10_000,
  commission: 0.001  # 0.1% commission
)

# Print results
TradingStrategy.print_report(result)
```

### 3. Real-time Execution

Run your strategy in real-time for live signal generation:

```elixir
# Get your strategy definition
strategy = MyStrategy.strategy_definition()

# Start the strategy engine
{:ok, engine} = TradingStrategy.start_strategy(
  strategy: strategy,
  symbol: "BTCUSD",
  initial_capital: 10_000,
  position_size: 1.0,
  max_positions: 1  # Allow max 1 concurrent position
)

# Simulate receiving market data (e.g., from an exchange WebSocket)
# In production, this would come from your data feed
# IMPORTANT: Use Decimal for all price values
new_candle = %{
  open: Decimal.new("50000.0"),
  high: Decimal.new("51000.0"),
  low: Decimal.new("49500.0"),
  close: Decimal.new("50500.0"),
  volume: 1000,
  timestamp: DateTime.utc_now()
}

# Or use the helper
new_candle = TradingStrategy.Types.new_ohlcv(50000, 51000, 49500, 50500, 1000)

# Process the new candle through the strategy
{:ok, result} = TradingStrategy.process_data(engine, new_candle)

# Check if any signals were generated
case result.signals do
  [] ->
    IO.puts("No signals generated")

  signals ->
    Enum.each(signals, fn signal ->
      IO.puts("Signal: #{signal.type} #{signal.direction} at #{signal.price}")

      # In a live system, you would:
      # - Send order to exchange
      # - Update position tracking
      # - Log the signal
      # - Send notifications
    end)
end

# Monitor open positions
open_positions = TradingStrategy.get_open_positions(engine)
Enum.each(open_positions, fn position ->
  current_price = 50500.0
  unrealized_pnl = TradingStrategy.Position.unrealized_pnl(position, current_price)
  IO.puts("Position: #{position.direction} | Entry: #{position.entry_price} | P&L: #{unrealized_pnl}")
end)

# Get complete engine state
state = TradingStrategy.get_state(engine)
IO.inspect(state.indicator_values, label: "Current Indicators")

# Stop the engine when done
TradingStrategy.stop(engine)
```

#### Real-time Execution Example - Complete Workflow

Here's a more complete example showing how to integrate with a live data stream:

```elixir
defmodule LiveTradingBot do
  use GenServer

  def start_link(strategy, symbol) do
    GenServer.start_link(__MODULE__, {strategy, symbol}, name: __MODULE__)
  end

  def init({strategy, symbol}) do
    # Start the strategy engine
    {:ok, engine} = TradingStrategy.start_strategy(
      strategy: strategy,
      symbol: symbol,
      initial_capital: 10_000,
      position_size: 0.1,  # Trade 0.1 BTC per signal
      max_positions: 3
    )

    # Subscribe to market data feed (pseudo-code)
    # ExchangeClient.subscribe_to_candles(symbol, "1h")

    {:ok, %{engine: engine, symbol: symbol}}
  end

  # Handle incoming candle data from exchange
  def handle_info({:candle, candle_data}, state) do
    # Process the candle through the strategy
    case TradingStrategy.process_data(state.engine, candle_data) do
      {:ok, result} ->
        # Handle any generated signals
        handle_signals(result.signals, state)

        # Update dashboard/monitoring
        update_dashboard(result, state)

      {:error, reason} ->
        IO.puts("Error processing candle: #{inspect(reason)}")
    end

    {:noreply, state}
  end

  defp handle_signals([], _state), do: :ok
  defp handle_signals(signals, state) do
    Enum.each(signals, fn signal ->
      case signal.type do
        :entry ->
          # Place buy order on exchange
          IO.puts("🟢 ENTRY SIGNAL: #{signal.direction} #{state.symbol} @ #{signal.price}")
          # ExchangeClient.place_order(...)

        :exit ->
          # Place sell order on exchange
          IO.puts("🔴 EXIT SIGNAL: #{state.symbol} @ #{signal.price}")
          # ExchangeClient.place_order(...)
      end
    end)
  end

  defp update_dashboard(result, state) do
    open_positions = result.open_positions
    total_unrealized_pnl = Enum.reduce(open_positions, 0, fn pos, acc ->
      acc + (pos.pnl || 0)
    end)

    IO.puts("""
    ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    Strategy: #{state.symbol}
    Open Positions: #{length(open_positions)}
    Unrealized P&L: $#{Float.round(total_unrealized_pnl, 2)}
    Last Signal: #{if length(result.signals) > 0, do: "✓", else: "-"}
    ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    """)
  end
end

# Start the live trading bot
strategy = MyStrategy.strategy_definition()
{:ok, _bot} = LiveTradingBot.start_link(strategy, "BTCUSD")

# The bot will now process candles in real-time and generate signals
```

#### Processing Multiple Candles (Batch)

```elixir
# Start engine
{:ok, engine} = TradingStrategy.start_strategy(
  strategy: strategy,
  symbol: "BTCUSD"
)

# Process a stream of candles
alias TradingStrategy.Types

candles_stream = [
  Types.new_ohlcv(50000, 50500, 49800, 50200, 1000, ~U[2025-01-01 00:00:00Z]),
  Types.new_ohlcv(50200, 50800, 50100, 50600, 1100, ~U[2025-01-01 01:00:00Z]),
  Types.new_ohlcv(50600, 51200, 50500, 51000, 1200, ~U[2025-01-01 02:00:00Z])
]

results = Enum.map(candles_stream, fn candle ->
  {:ok, result} = TradingStrategy.process_data(engine, candle)
  result
end)

# Collect all signals
all_signals = Enum.flat_map(results, & &1.signals)
IO.puts("Generated #{length(all_signals)} signals from #{length(candles_stream)} candles")

# Get final state
final_state = TradingStrategy.get_state(engine)
IO.inspect(final_state.positions, label: "All Positions")
```

## Important: Decimal Precision

**All price values in OHLCV data MUST use `Decimal` types** for exact financial precision. Never use floats for price data as they introduce rounding errors.

### Creating OHLCV Data

```elixir
# Using the helper function (recommended)
alias TradingStrategy.Types

candle = Types.new_ohlcv(
  100,    # open
  105,    # high
  95,     # low
  102,    # close
  1000,   # volume
  ~U[2025-01-01 00:00:00Z]  # timestamp (optional)
)

# Manual creation with Decimal
candle = %{
  open: Decimal.new("100.0"),
  high: Decimal.new("105.0"),
  low: Decimal.new("95.0"),
  close: Decimal.new("102.0"),
  volume: 1000,
  timestamp: ~U[2025-01-01 00:00:00Z]
}
```

### Why Decimal?

- **Financial Accuracy**: Prevents floating-point rounding errors
- **Regulatory Compliance**: Exact arithmetic required for financial applications
- **Indicator Precision**: All indicators receive and return `Decimal` values
- **Comparison Safety**: Use `Decimal.compare/2` for reliable price comparisons

```elixir
# ❌ WRONG - Don't use floats
candle = %{close: 100.50, high: 101.25, ...}

# ✅ CORRECT - Use Decimal
candle = %{close: Decimal.new("100.50"), high: Decimal.new("101.25"), ...}

# ✅ CORRECT - Use helper (converts to Decimal automatically)
candle = Types.new_ohlcv(100.50, 101.25, 99.75, 100.80, 1000)
```

## DSL Reference

### Indicators

Define indicators to use in your strategy. All indicators come from the [trading-indicators](https://github.com/rzcastilho/trading-indicators) library and follow the `TradingIndicators.Behaviour` contract.

```elixir
indicator :name, Module, option1: value1, option2: value2
```

Examples:
```elixir
# Trend indicators
indicator :sma, TradingIndicators.Trend.SMA, period: 20, source: :close
indicator :ema, TradingIndicators.Trend.EMA, period: 12, source: :close
indicator :macd, TradingIndicators.Trend.MACD, fast: 12, slow: 26, signal: 9

# Momentum indicators
indicator :rsi, TradingIndicators.Momentum.RSI, period: 14, source: :close
indicator :stoch, TradingIndicators.Momentum.Stochastic, period: 14

# Volatility indicators
indicator :bb, TradingIndicators.Volatility.BollingerBands, period: 20, std_dev: 2
indicator :atr, TradingIndicators.Volatility.ATR, period: 14

# Volume indicators
indicator :obv, TradingIndicators.Volume.OBV
indicator :vwap, TradingIndicators.Volume.VWAP
```

#### Available Indicators (22 total)

**Trend (6):** SMA, EMA, WMA, HMA, KAMA, MACD
**Momentum (6):** RSI, Stochastic, Williams %R, CCI, ROC, Momentum
**Volatility (4):** Bollinger Bands, ATR, Standard Deviation, Volatility Index
**Volume (4):** OBV, VWAP, A/D Line, CMF

#### Common Parameters

- `:period` - Number of periods for calculation (e.g., `period: 14`)
- `:source` - Price field to use: `:open`, `:high`, `:low`, `:close` (default: `:close`)

#### Indicator Integration

The library automatically:
- **Validates parameters** before calculation using `validate_params/1`
- **Checks data sufficiency** using `required_periods/0` or `required_periods/1`
- **Uses streaming updates** when available for real-time processing (better performance)
- **Falls back to batch calculation** if streaming fails or isn't supported
- **Returns `nil`** during warmup period when insufficient data is available (this is normal)

**Note:** You may see "Insufficient data" debug messages for the first few candles - this is expected behavior during the warmup period while the indicator accumulates enough data.

### Entry Signals

Define when to enter positions:

```elixir
entry_signal :long do
  # conditions
end

entry_signal :short do
  # conditions
end
```

### Exit Signals

Define when to exit positions:

```elixir
exit_signal do
  # conditions
end
```

### Conditions

**Note on Warmup Period:** During the initial candles (warmup period), indicators may return `nil` when they don't have sufficient data. Any condition involving a `nil` indicator will evaluate to `false`, preventing signals from being generated until all indicators are ready. This ensures your strategy only acts on complete data.

#### Boolean Logic

Combine conditions with `when_all` (AND), `when_any` (OR), and `when_not` (NOT):

```elixir
# All conditions must be true
when_all do
  indicator(:rsi) > 30
  indicator(:rsi) < 70
  cross_above(:sma_fast, :sma_slow)
end

# At least one condition must be true
when_any do
  indicator(:rsi) > 70
  pattern(:shooting_star)
end

# Negate a condition
when_not do
  indicator(:rsi) > 50
end
```

#### Indicator Comparisons

Compare indicator values:

```elixir
indicator(:rsi) > 70
indicator(:rsi) < 30
indicator(:sma_fast) > indicator(:sma_slow)
```

#### Cross Detection

Detect when indicators cross:

```elixir
cross_above(:sma_fast, :sma_slow)  # Fast crosses above slow
cross_below(:macd, :signal)         # MACD crosses below signal line
```

#### Pattern Recognition

Match candlestick patterns:

```elixir
pattern(:hammer)
pattern(:bullish_engulfing)
pattern(:shooting_star)
pattern(:doji)
```

Supported patterns:
- `:hammer` - Bullish reversal
- `:inverted_hammer` - Bullish reversal
- `:bullish_engulfing` - Bullish reversal
- `:bearish_engulfing` - Bearish reversal
- `:doji` - Indecision
- `:morning_star` - Bullish reversal
- `:evening_star` - Bearish reversal
- `:three_white_soldiers` - Strong bullish
- `:three_black_crows` - Strong bearish
- `:shooting_star` - Bearish reversal
- `:hanging_man` - Bearish reversal

## Backtesting

The backtesting engine provides comprehensive performance metrics:

### Metrics Included

- **Total Trades**: Number of completed trades
- **Win Rate**: Percentage of winning trades
- **Profit Factor**: Ratio of gross profit to gross loss
- **Net Profit**: Total profit after commissions and slippage
- **Average Win/Loss**: Average profit per winning/losing trade
- **Max Drawdown**: Largest peak-to-trough decline
- **Sharpe Ratio**: Risk-adjusted return metric
- **Return on Capital**: Percentage return on initial capital

### Example Output

```
============================================================
BACKTEST REPORT: ma_crossover
============================================================
Symbol: BTCUSD
Period: 2025-01-01 to 2025-12-31
------------------------------------------------------------

PERFORMANCE METRICS:
Total Trades: 45
Winning Trades: 28
Losing Trades: 17
Win Rate: 62.22%

PROFIT/LOSS:
Net Profit: $5,432.10
Gross Profit: $8,921.50
Gross Loss: $3,489.40
Profit Factor: 2.56
Return on Capital: 54.32%

TRADE STATISTICS:
Average Win: $318.63
Average Loss: $205.26
Largest Win: $892.00
Largest Loss: $445.00

RISK METRICS:
Max Drawdown: $1,234.56
Max Drawdown %: 12.35%
Sharpe Ratio: 1.85
============================================================
```

## Examples

See the `examples/` directory for complete strategy examples:

- **[moving_average_crossover.ex](examples/moving_average_crossover.ex)** - Simple MA crossover with RSI filter
- **[rsi_reversal.ex](examples/rsi_reversal.ex)** - Mean reversion strategy with pattern confirmation
- **[bollinger_breakout.ex](examples/bollinger_breakout.ex)** - Bollinger Bands breakout with volume confirmation

## Architecture

### Core Components

- **`TradingStrategy.DSL`** - Macro-based DSL for strategy definition
- **`TradingStrategy.Engine`** - GenServer-based execution engine with indicator streaming support
- **`TradingStrategy.Backtest`** - Historical backtesting framework
- **`TradingStrategy.Indicators`** - Indicator integration layer with automatic validation and streaming
- **`TradingStrategy.ConditionEvaluator`** - Boolean logic evaluation engine
- **`TradingStrategy.Patterns`** - Candlestick pattern recognition (11 patterns)
- **`TradingStrategy.Signal`** - Trading signal representation
- **`TradingStrategy.Position`** - Position tracking and P&L calculation with Decimal precision
- **`TradingStrategy.Types`** - OHLCV type definitions and Decimal conversion utilities

### Indicator Integration Layer

The `TradingStrategy.Indicators` module provides a robust integration with the trading-indicators library:

**Features:**
- Automatic parameter validation using `validate_params/1` callback
- Data sufficiency checks using `required_periods/0` or `required_periods/1` callback
- Proper handling of `{:ok, results}` and `{:error, reason}` tuples
- Value extraction from structured result format
- Streaming support with `init_state/1` and `update_state/2` for real-time updates
- Graceful fallback from streaming to batch calculation on errors
- Module loading and introspection with `Code.ensure_loaded/1`

**Helper Functions:**
```elixir
# Validate indicator parameters
Indicators.validate_indicator_params(TradingIndicators.Trend.SMA, period: 20, source: :close)
# => {:ok, :valid} or {:error, reason}

# Check data sufficiency
Indicators.check_sufficient_data(TradingIndicators.Trend.SMA, market_data, period: 20)
# => :ok or :insufficient_data

# Get parameter metadata
Indicators.get_parameter_metadata(TradingIndicators.Trend.SMA)
# => [%ParamMetadata{name: :period, type: :integer, ...}, ...]

# Check streaming support
Indicators.supports_streaming?(TradingIndicators.Trend.SMA)
# => true or false
```

### Streaming vs Batch Processing

The Engine automatically uses the most efficient calculation method:

**Streaming Mode (Real-time):**
- Uses `init_state/1` and `update_state/2` for incremental updates
- Better performance for live trading
- Maintains indicator state across candles
- Automatically initialized for indicators that support it

**Batch Mode (Historical):**
- Uses `calculate/2` for full recalculation
- Used during backtesting
- Fallback when streaming fails
- No state maintenance required

The system seamlessly switches between modes based on availability and errors.

## Contributing

Contributions are welcome! Please feel free to submit a Pull Request.

## License

This project is licensed under the MIT License - see the LICENSE file for details.

## Acknowledgments

- Built for use with the [trading-indicators](https://github.com/rzcastilho/trading-indicators) library
- Inspired by popular trading platforms like TradingView's Pine Script and QuantConnect

