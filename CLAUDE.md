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

### Adding a New Indicator
1. Indicators come from external `trading-indicators` library
2. Add indicator definition in strategy DSL: `indicator :name, Module, opts`
3. `TradingStrategy.Indicators` handles data extraction and caching
4. Indicator receives Decimal values from `extract_data_series/2`

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
