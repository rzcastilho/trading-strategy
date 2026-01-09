# Trading Strategy DSL Reference

Complete syntax reference for defining trading strategies in YAML or TOML.

## Format Support

- **YAML** (recommended): Better for complex nested structures
- **TOML**: Explicit typing, simpler for flat configurations

## Required Fields

### Strategy Metadata

```yaml
strategy_id: "unique-uuid-or-slug"  # UUID or slug format
name: "Strategy Name"                # 1-100 chars
description: "Strategy description"  # Optional, max 500 chars
trading_pair: "BTC/USD"              # Format: BASE/QUOTE
timeframe: "1h"                      # See timeframes below
version: "1.0.0"                     # Semver format
```

### Timeframes

Supported values: `1m`, `5m`, `15m`, `30m`, `1h`, `2h`, `4h`, `6h`, `8h`, `12h`, `1d`, `3d`, `1w`

## Indicators

### Available Indicators

#### Trend Indicators
- `sma` - Simple Moving Average
- `ema` - Exponential Moving Average
- `wma` - Weighted Moving Average
- `hma` - Hull Moving Average
- `kama` - Kaufman Adaptive Moving Average
- `macd` - Moving Average Convergence Divergence

#### Momentum Indicators
- `rsi` - Relative Strength Index
- `stochastic` - Stochastic Oscillator
- `williams_r` - Williams %R
- `cci` - Commodity Channel Index
- `roc` - Rate of Change
- `momentum` - Momentum

#### Volatility Indicators
- `bb` - Bollinger Bands
- `atr` - Average True Range
- `stddev` - Standard Deviation
- `vi` - Volatility Index

#### Volume Indicators
- `obv` - On-Balance Volume
- `vwap` - Volume Weighted Average Price
- `adi` - Accumulation/Distribution Index
- `cmf` - Chaikin Money Flow
- `mfi` - Money Flow Index

### Indicator Definition

```yaml
indicators:
  - type: "rsi"           # Indicator type (required)
    name: "rsi_14"        # Unique name within strategy (required)
    parameters:           # Type-specific parameters (required)
      period: 14
```

### Common Parameters

**RSI:**
```yaml
- type: "rsi"
  name: "rsi_14"
  parameters:
    period: 14  # Integer, 2-100, default: 14
```

**MACD:**
```yaml
- type: "macd"
  name: "macd_12_26_9"
  parameters:
    short_period: 12   # Integer, 2-50, default: 12
    long_period: 26    # Integer, 2-200, default: 26
    signal_period: 9   # Integer, 2-50, default: 9
```

**Bollinger Bands:**
```yaml
- type: "bb"
  name: "bollinger_20"
  parameters:
    period: 20         # Integer, 2-100, default: 20
    std_dev: 2.0       # Decimal, 0.1-5.0, default: 2.0
```

**Moving Averages (SMA/EMA/WMA):**
```yaml
- type: "sma"
  name: "sma_50"
  parameters:
    period: 50  # Integer, 2-500, default: 50
```

## Trading Conditions

### Entry Conditions

Boolean expression that triggers position entry:

```yaml
entry_conditions: "rsi_14 < 30 AND close > sma_50"
```

### Exit Conditions

Boolean expression that triggers position exit:

```yaml
exit_conditions: "rsi_14 > 70 OR close < sma_50"
```

### Stop Conditions

Emergency exit conditions (stop-loss/take-profit):

```yaml
stop_conditions: "unrealized_pnl_pct < -0.05 OR rsi_14 < 25"
```

### Condition Syntax

**Operators:**
- Comparison: `>`, `<`, `>=`, `<=`, `==`, `!=`
- Logical: `AND`, `OR`, `NOT`
- Parentheses: `(`, `)` for grouping

**Variables:**
- Indicator values: Use indicator `name` (e.g., `rsi_14`, `sma_50`)
- OHLCV data: `open`, `high`, `low`, `close`, `volume`
- Position metrics: `unrealized_pnl`, `unrealized_pnl_pct`, `entry_price`
- Indicator subfields: `macd_12_26_9_macd`, `macd_12_26_9_signal`, `bollinger_20_upper`

**Lookback:**
```yaml
# Previous value
"sma_50[1] < sma_200[1]"  # SMA 1 bar ago

# Multiple bars back
"close > close[3]"        # Current close > close 3 bars ago
```

**Examples:**
```yaml
# Simple
entry_conditions: "rsi_14 < 30"

# Multiple indicators
entry_conditions: "rsi_14 < 30 AND macd_12_26_9_macd > macd_12_26_9_signal"

# Crossover detection
entry_conditions: "sma_50 > sma_200 AND sma_50[1] <= sma_200[1]"

# Complex with grouping
entry_conditions: "(rsi_14 < 30 OR stoch_14_k < 20) AND close > ema_20"
```

## Position Sizing

### Percentage-Based

```yaml
position_sizing:
  type: "percentage"
  percentage_of_capital: 0.10     # 10% per trade
  max_position_size: 0.25         # Max 25% total allocation
```

### Fixed Amount

```yaml
position_sizing:
  type: "fixed_amount"
  fixed_amount: 1000              # $1000 per trade
  max_position_size: 0.50         # Max 50% total allocation
```

### Risk-Based (Advanced)

```yaml
position_sizing:
  type: "risk_based"
  risk_per_trade: 0.02            # 2% of capital at risk
  max_position_size: 0.30         # Max 30% total allocation
```

## Risk Parameters

```yaml
risk_parameters:
  max_daily_loss: 0.03              # 3% max loss per day
  max_drawdown: 0.15                # 15% max drawdown from peak
  stop_loss_percentage: 0.05        # 5% stop-loss below entry
  take_profit_percentage: 0.10      # 10% take-profit above entry (optional)
```

### Field Descriptions

- `max_daily_loss`: Halt trading if daily losses exceed this % of capital
- `max_drawdown`: Emergency stop if drawdown from peak exceeds this %
- `stop_loss_percentage`: Automatic exit if price drops this % below entry
- `take_profit_percentage`: Automatic exit if price rises this % above entry (optional)

## Complete Examples

See `examples/` directory:
- `sma_crossover.yaml` - Classic trend-following strategy
- `rsi_reversal.toml` - Mean reversion strategy (TOML format)
- `multi_indicator.yaml` - Advanced multi-indicator confluence

## Validation Rules

Strategies are validated on creation:

1. **Indicator Names**: Must be unique within strategy
2. **Condition References**: All variables in conditions must reference defined indicators or OHLCV fields
3. **Parameter Ranges**: Indicator parameters must be within documented ranges
4. **Position Sizing**: Sum of allocations cannot exceed 100%
5. **Risk Parameters**: `max_daily_loss + max_drawdown` recommended < 30%

## TOML Format

Equivalent TOML syntax:

```toml
strategy_id = "rsi-reversal-v1"
name = "RSI Mean Reversion"
trading_pair = "ETH/USD"
timeframe = "1h"
version = "1.0.0"

[[indicators]]
type = "rsi"
name = "rsi_14"
  [indicators.parameters]
  period = 14

entry_conditions = "rsi_14 < 30"
exit_conditions = "rsi_14 > 70"
stop_conditions = "rsi_14 < 25"

[position_sizing]
type = "percentage"
percentage_of_capital = 0.10

[risk_parameters]
max_daily_loss = 0.03
max_drawdown = 0.15
```

## Data Model Reference

Complete entity schemas in:
- `specs/001-strategy-dsl-library/data-model.md`

## Contract Reference

API contracts for strategy creation/validation:
- `specs/001-strategy-dsl-library/contracts/strategy_api.ex`
