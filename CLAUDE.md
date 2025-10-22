# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

TradingStrategy is an Elixir library for defining, executing, and backtesting trading strategies using a declarative DSL. The library integrates with the [trading-indicators](https://github.com/rzcastilho/trading-indicators) library and uses Decimal precision for all financial calculations.

## Development Commands

### Build and Dependencies
```bash
# Install dependencies
mix deps.get

# Compile the project
mix compile

# Force recompile
mix compile --force
```

### Testing
```bash
# Run all tests
mix test

# Run a specific test file
mix test test/trading_strategy/patterns_test.exs

# Run a specific test by line number
mix test test/trading_strategy/patterns_test.exs:42

# Run tests with detailed output
mix test --trace
```

### Interactive Development
```bash
# Start IEx with the project loaded
iex -S mix

# Example: Test a strategy in IEx
iex> alias TradingStrategy.Types
iex> candles = [Types.new_ohlcv(100, 105, 95, 102, 1000)]
iex> TradingStrategy.Patterns.detect_all(candles)
```

## Architecture Overview

### Core Data Flow

1. **Strategy Definition (DSL)** → Parsed into `Definition` struct
2. **Market Data (OHLCV)** → Processed through `Engine` or `Backtest`
3. **Indicators** → Calculated with Decimal precision
4. **Conditions** → Evaluated to generate signals
5. **Signals** → Trigger position management

### Module Responsibilities

**Strategy Layer:**
- `TradingStrategy.DSL` - Macro-based DSL that compiles strategy definitions
- `TradingStrategy.Definition` - Struct holding strategy configuration (indicators, signals, metadata)

**Data Layer:**
- `TradingStrategy.Types` - OHLCV type definitions and Decimal conversion utilities
- All price data MUST use `Decimal.t()` for open/high/low/close

**Execution Layer:**
- `TradingStrategy.Engine` - GenServer managing real-time strategy state, processes candles sequentially
- `TradingStrategy.Backtest` - Historical simulation engine with performance metrics

**Analysis Layer:**
- `TradingStrategy.Indicators` - Bridge to trading-indicators library, extracts Decimal data series
- `TradingStrategy.Patterns` - Candlestick pattern detection (11 patterns, all using Decimal)
- `TradingStrategy.ConditionEvaluator` - Boolean logic engine for entry/exit rules

**Trading Layer:**
- `TradingStrategy.Signal` - Entry/exit signal representation
- `TradingStrategy.Position` - Position tracking with P&L calculations

### Key Design Patterns

**Decimal Precision:**
- ALL price values use `Decimal.t()` - never floats for OHLC data
- Use `Types.new_ohlcv/6` or `Types.to_decimal/1` for conversions
- Pattern detection uses `Decimal.compare/2` for comparisons
- Indicators return Decimal values

**GenServer Architecture:**
- Each strategy instance runs in its own GenServer process
- Process registry allows multiple concurrent strategies
- State includes: positions, signals, market_data, indicator_values

**DSL Compilation:**
- Macros in `TradingStrategy.DSL` transform declarative syntax into data structures
- `defstrategy` → compiled at compile-time into `strategy_definition/0` function
- Conditions are AST that gets evaluated at runtime by `ConditionEvaluator`

**Boolean Logic:**
- Nested structure: `when_all`, `when_any`, `when_not`
- Cross detection: compares current vs historical indicator values
- Pattern matching: delegates to `Patterns` module

## Critical Implementation Details

### OHLCV Data Structure
```elixir
%{
  open: Decimal.t(),      # Required: Decimal
  high: Decimal.t(),      # Required: Decimal
  low: Decimal.t(),       # Required: Decimal
  close: Decimal.t(),     # Required: Decimal
  volume: integer(),      # Required: non-negative integer
  timestamp: DateTime.t() # Required: DateTime
}
```

### Decimal Operations Reference
When working with price calculations:
```elixir
# Arithmetic
Decimal.add(a, b)      # a + b
Decimal.sub(a, b)      # a - b
Decimal.mult(a, b)     # a * b
Decimal.div(a, b)      # a / b

# Comparisons (returns :gt, :lt, or :eq)
Decimal.compare(a, b) == :gt   # a > b
Decimal.compare(a, b) == :lt   # a < b
Decimal.compare(a, b) != :lt   # a >= b
Decimal.compare(a, b) != :gt   # a <= b
Decimal.compare(a, b) == :eq   # a == b

# Utility
Decimal.abs(a)         # abs(a)
Decimal.max(a, b)      # max(a, b)
Decimal.min(a, b)      # min(a, b)
```

### Pattern Detection Implementation
All pattern functions follow this structure:
```elixir
def detect_pattern(candles) do
  candle = List.last(candles)  # or Enum.take(candles, -N) for multi-candle patterns

  if candle do
    # Convert to Decimal
    open = to_dec(candle.open)
    close = to_dec(candle.close)
    # ... other values

    # Calculate with Decimal
    body_size = Decimal.abs(Decimal.sub(close, open))

    # Compare with Decimal.compare
    if Decimal.compare(body_size, threshold) != :lt do
      :pattern_name
    end
  end
end
```

### Testing Patterns
- Test helpers in `test/support/test_helpers.ex` generate Decimal OHLCV data
- Use `Types.new_ohlcv/6` for test data creation
- `TestIndicator` modules in test files must return Decimal values

### Strategy Engine State
The GenServer state structure:
```elixir
%{
  strategy: Definition.t(),           # Strategy configuration
  positions: [Position.t()],          # All positions (open and closed)
  signals: [Signal.t()],              # All generated signals
  market_data: [ohlcv()],             # Historical candles
  indicator_values: %{atom() => any()}, # Current indicator values (Decimal)
  historical_indicators: %{atom() => [any()]}, # For cross detection
  config: %{
    symbol: String.t(),
    initial_capital: float(),
    position_size: float(),
    max_positions: integer()
  }
}
```

## Common Development Scenarios

### Adding a New Pattern
1. Add pattern function to `lib/trading_strategy/patterns.ex`
2. Use `to_dec/1` helper for Decimal conversion
3. All calculations must use Decimal operations
4. Add to `detect_all/1` function
5. Create test data in `test/support/test_helpers.ex`
6. Add tests in `test/trading_strategy/patterns_test.exs`

### Using Indicators from trading-indicators Library

**IMPORTANT:** This library integrates with the `trading-indicators` library which follows the `TradingIndicators.Behaviour` contract. All indicators must be used according to their API specifications.

#### Indicator Behaviour Contract

All indicators in the trading-indicators library implement these callbacks:

1. **`calculate/2`** - Batch calculation
   - Takes: `(data :: [Decimal.t()], opts :: keyword()) `
   - Returns: `{:ok, [result]} | {:error, reason}`
   - Result format: `%{value: Decimal.t(), timestamp: DateTime.t(), metadata: map()}`

2. **`validate_params/1`** - Parameter validation
   - Takes: `opts :: keyword()`
   - Returns: `:ok | {:error, reason}`

3. **`required_periods/0` or `required_periods/1`** - Minimum data requirements
   - Returns: `non_neg_integer()`

4. **`parameter_metadata/0`** - Parameter introspection
   - Returns: `[TradingIndicators.Types.ParamMetadata.t()]`

5. **`init_state/1` and `update_state/2`** - Optional streaming support
   - For real-time incremental updates

#### Integration Layer (`TradingStrategy.Indicators`)

The `Indicators` module provides the integration layer that:

- **Validates parameters** using `validate_params/1` before calculation
- **Checks data sufficiency** using `required_periods/0` or `required_periods/1`
- **Handles return tuples** (`{:ok, results}` or `{:error, reason}`)
- **Extracts values** from structured result format
- **Supports streaming** via `init_state/1` and `update_state/2` for real-time updates
- **Falls back gracefully** from streaming to batch when errors occur

#### Adding an Indicator to Your Strategy

**CRITICAL: Module Namespacing**
All indicator modules are namespaced by their category. You **MUST** use the full module path:
- ❌ `TradingIndicators.SMA` - **WRONG** (will cause UndefinedFunctionError)
- ✅ `TradingIndicators.Trend.SMA` - **CORRECT**

```elixir
defmodule MyStrategy do
  use TradingStrategy.DSL

  defstrategy :my_strategy do
    # Add indicators with proper module and parameters (note the category namespace!)
    indicator :sma_20, TradingIndicators.Trend.SMA, period: 20, source: :close
    indicator :rsi_14, TradingIndicators.Momentum.RSI, period: 14, source: :close
    indicator :ema_12, TradingIndicators.Trend.EMA, period: 12, source: :close

    entry_signal :long do
      when_all do
        indicator(:rsi_14) < 40
        cross_above(:ema_12, :sma_20)
      end
    end

    exit_signal do
      indicator(:rsi_14) > 60
    end
  end
end
```

#### Available Indicators

From the trading-indicators library (22 indicators across 4 categories):

**Trend Indicators:**
- `TradingIndicators.Trend.SMA` - Simple Moving Average
- `TradingIndicators.Trend.EMA` - Exponential Moving Average
- `TradingIndicators.Trend.WMA` - Weighted Moving Average
- `TradingIndicators.Trend.HMA` - Hull Moving Average
- `TradingIndicators.Trend.KAMA` - Kaufman Adaptive Moving Average
- `TradingIndicators.Trend.MACD` - Moving Average Convergence Divergence

**Momentum Indicators:**
- `TradingIndicators.Momentum.RSI` - Relative Strength Index
- `TradingIndicators.Momentum.Stochastic` - Stochastic Oscillator
- `TradingIndicators.Momentum.WilliamsR` - Williams %R
- `TradingIndicators.Momentum.CCI` - Commodity Channel Index
- `TradingIndicators.Momentum.ROC` - Rate of Change
- `TradingIndicators.Momentum.Momentum` - Momentum Indicator

**Volatility Indicators:**
- `TradingIndicators.Volatility.BollingerBands` - Bollinger Bands
- `TradingIndicators.Volatility.ATR` - Average True Range
- `TradingIndicators.Volatility.StdDev` - Standard Deviation
- `TradingIndicators.Volatility.VolatilityIndex` - Volatility Index

**Volume Indicators:**
- `TradingIndicators.Volume.OBV` - On-Balance Volume
- `TradingIndicators.Volume.VWAP` - Volume Weighted Average Price
- `TradingIndicators.Volume.ADLine` - Accumulation/Distribution Line
- `TradingIndicators.Volume.CMF` - Chaikin Money Flow

#### Multi-Value Indicators

Some indicators return multiple components in a single calculation. Instead of defining separate indicators for each component, define the indicator once and reference specific components in conditions.

**Indicators with Multiple Components:**

- **MACD** (`TradingIndicators.Trend.MACD`):
  - `:macd` - MACD line (fast EMA - slow EMA)
  - `:signal` - Signal line (EMA of MACD line)
  - `:histogram` - Histogram (MACD - Signal)

- **Bollinger Bands** (`TradingIndicators.Volatility.BollingerBands`):
  - `:upper_band` - Upper band (SMA + deviation × StdDev)
  - `:middle_band` - Middle band (SMA)
  - `:lower_band` - Lower band (SMA - deviation × StdDev)
  - `:percent_b` - %B indicator (price position within bands)
  - `:bandwidth` - Band width (distance between upper and lower bands)

- **Stochastic** (`TradingIndicators.Momentum.Stochastic`):
  - `:k` - %K line (fast stochastic)
  - `:d` - %D line (slow stochastic, SMA of %K)

**Usage Example:**

```elixir
defstrategy :multi_value_example do
  # Define indicators once
  indicator :macd, TradingIndicators.Trend.MACD, fast: 12, slow: 26, signal: 9, source: :close
  indicator :bb, TradingIndicators.Volatility.BollingerBands, period: 20, deviation: 2, source: :close

  entry_signal :long do
    when_all do
      # Access specific components using indicator(name, component)
      indicator(:macd, :histogram) > 0
      cross_above(indicator(:macd, :macd), indicator(:macd, :signal))
      price(:close) > indicator(:bb, :middle_band)
      indicator(:bb, :percent_b) < 0.2  # Oversold within bands
    end
  end

  exit_signal do
    when_any do
      indicator(:macd, :histogram) < 0
      price(:close) > indicator(:bb, :upper_band)
    end
  end
end
```

**Error Handling:**

The system provides helpful error messages:

- Using a multi-value indicator without specifying a component:
  ```
  Indicator :macd returns multiple values: :macd, :signal, :histogram
  You must specify which component to use: indicator(:macd, :component)
  Example: indicator(:macd, :histogram)
  ```

- Accessing a non-existent component:
  ```
  Invalid component :invalid for indicator :macd.
  Available components: :macd, :signal, :histogram
  Example usage: indicator(:macd, :histogram)
  ```

#### Common Parameters

Most indicators support these parameters:

- `:period` - Number of periods (e.g., `period: 14`)
- `:source` - Price field to use: `:open`, `:high`, `:low`, `:close` (default: `:close`)

Some indicators support additional parameters:
- `:hl2` - (High + Low) / 2
- `:hlc3` - (High + Low + Close) / 3
- `:ohlc4` - (Open + High + Low + Close) / 4

#### Helper Functions

The `Indicators` module provides helper functions:

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

#### How Indicator Integration Works

1. **Strategy Definition:** Indicators are defined in DSL with module and parameters
2. **Initialization:** Engine initializes streaming state for indicators that support it
3. **Data Processing:** On each new candle:
   - **Streaming mode:** Calls `update_state/2` with new data point (if supported)
   - **Batch mode:** Calls `calculate/2` with all historical data
   - **Fallback:** Falls back to batch if streaming fails
4. **Value Extraction:** Extracts Decimal value from structured result
5. **Condition Evaluation:** Indicator values used in signal conditions

#### Decimal Precision

All indicator calculations use Decimal precision:
- Input data is converted to Decimal via `extract_data_series/2`
- Indicators receive `[Decimal.t()]` as input
- Results contain `value: Decimal.t()`
- No floating-point arithmetic for financial calculations

#### Error Handling

The integration layer handles errors gracefully:

- **Invalid parameters:** Logged at error level and returns `nil`
- **Insufficient data:** Logged at **debug** level and returns `nil` (this is **normal** during warmup period)
- **Calculation errors:** Caught and logged at error level, returns `nil`
- **Streaming failures:** Logged at warning level and falls back to batch calculation

**Note on "Insufficient data" messages:** These debug messages are **expected and normal** during the initial candles. For example, a 14-period RSI requires 14 candles before it can calculate the first value. The first 13 candles will log "Insufficient data" at debug level - this is not an error, it's just informational logging. The indicator will start returning values once enough data is accumulated.

#### Testing with Real Indicators

Integration tests use actual indicators from trading-indicators:

```elixir
test "integration with real SMA indicator" do
  strategy =
    Definition.new(:test)
    |> Definition.add_indicator(:sma, TradingIndicators.Trend.SMA, period: 3, source: :close)

  market_data = generate_market_data(count: 10)
  result = Indicators.calculate_all(strategy, market_data)

  assert %Decimal{} = result[:sma]
end
```

See `test/integration/strategy_integration_test.exs` for more examples.

#### Important Notes

- Always validate parameters before using indicators
- Check data sufficiency to avoid nil results
- Use streaming mode for real-time applications (better performance)
- Use batch mode for backtesting and historical analysis
- All indicator values are Decimal - use Decimal operations for comparisons
- Refer to trading-indicators library docs for detailed parameter specifications

### Extending Boolean Logic
1. Add new condition type to `TradingStrategy.ConditionEvaluator`
2. Handle in `evaluate_condition/2` function
3. Update DSL macros in `TradingStrategy.DSL` if needed
4. Add tests for the new condition type

## File Organization

```
lib/trading_strategy/
  ├── types.ex              # OHLCV type & Decimal utilities
  ├── dsl.ex                # Strategy DSL macros
  ├── definition.ex         # Strategy struct
  ├── engine.ex             # Real-time GenServer
  ├── backtest.ex           # Historical simulation
  ├── indicators.ex         # Indicator integration
  ├── patterns.ex           # Candlestick patterns
  ├── patterns/helpers.ex   # Pattern utilities
  ├── condition_evaluator.ex # Boolean logic
  ├── signal.ex             # Signal struct
  ├── position.ex           # Position tracking
  └── application.ex        # OTP application

test/
  ├── support/test_helpers.ex  # Shared test utilities
  └── trading_strategy/        # Module-specific tests
```

## Important Notes

- **Never use float arithmetic for OHLC prices** - always use Decimal
- **Pattern detection requires minimum candle counts** - check function docs
- **Cross detection needs historical data** - stored in Engine state
- **Backtesting is sequential** - processes candles in order to simulate reality
- **Multiple TestIndicator definitions exist** - in test files, must all return Decimal

## Reference Documentation

- See `README.md` for user-facing documentation and examples
- See `DECIMAL_MIGRATION.md` for detailed Decimal conversion guide
- See `IMPLEMENTATION_SUMMARY.md` for complete feature list and metrics
