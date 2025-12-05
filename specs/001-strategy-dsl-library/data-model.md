# Data Model: Trading Strategy DSL Library

**Feature**: 001-strategy-dsl-library
**Date**: 2025-12-04
**Phase**: Phase 1 - Design & Contracts

This document defines the core entities, their attributes, relationships, validation rules, and state transitions for the trading strategy DSL library.

---

## Entity Diagram

```
┌─────────────────────┐
│ Strategy Definition │
└──────────┬──────────┘
           │ references (1:N)
           ▼
     ┌──────────┐
     │ Indicator│
     └─────┬────┘
           │ depends on (N:1)
           ▼
     ┌────────────┐         ┌────────────────┐
     │ Market Data│◄────────│Trading Session │
     └─────┬──────┘ uses    └────────┬───────┘
           │                          │ contains (1:N)
           │ drives                   ▼
           │ evaluation         ┌──────────┐
           │                    │  Trade   │
           │                    └────┬─────┘
           │                         │ linked to (N:1)
           ▼                         ▼
     ┌─────────┐              ┌──────────┐
     │ Signal  │─────────────►│ Position │
     └─────────┘ triggers     └──────────┘
           │                         │
           │ produces                │ computed from (N:1)
           │                         ▼
           │                   ┌────────────────────┐
           └──────────────────►│Performance Metrics │
                               └────────────────────┘
```

---

## 1. Strategy Definition

Declarative configuration file (YAML/TOML) specifying indicators, signal conditions, position sizing, and risk parameters.

### Attributes

| Field | Type | Required | Validation | Description |
|-------|------|----------|------------|-------------|
| `strategy_id` | String (UUID) | Yes | UUID v4 format | Unique identifier for strategy |
| `name` | String | Yes | 1-100 chars, alphanumeric | Human-readable strategy name |
| `description` | String | No | Max 500 chars | Strategy purpose/approach |
| `trading_pair` | String | Yes | Format: "BASE/QUOTE" | Symbol to trade (e.g., "BTC/USD") |
| `timeframe` | String | Yes | Enum: "1m", "5m", "15m", "1h", "4h", "1d" | Candlestick interval |
| `indicators` | List[IndicatorConfig] | Yes | Min 1 indicator | Technical indicators to calculate |
| `entry_conditions` | String | Yes | Valid expression syntax | Logical condition for entry signals |
| `exit_conditions` | String | Yes | Valid expression syntax | Logical condition for exit signals |
| `stop_conditions` | String | Yes | Valid expression syntax | Stop-loss/take-profit rules |
| `position_sizing` | PositionSizingConfig | Yes | See nested schema | Capital allocation rules |
| `risk_parameters` | RiskConfig | Yes | See nested schema | Risk management limits |
| `created_at` | DateTime (UTC) | Auto | ISO8601 | Strategy creation timestamp |
| `version` | String | Yes | Semver format | Strategy version (e.g., "1.0.0") |

### Nested Schemas

**IndicatorConfig:**
```yaml
type: String (Enum: "rsi", "macd", "sma", "ema", "bb", "obv", "mfi", "stochastic", "williams_r", "adi")
name: String (1-50 chars, unique per strategy)
parameters: Map[String, Any]  # Type-specific params (e.g., period: 14 for RSI)
```

**PositionSizingConfig:**
```yaml
type: String (Enum: "percentage", "fixed_amount", "risk_based")
percentage_of_capital: Decimal (0.01-1.0)  # If type=percentage
fixed_amount: Decimal (>0)                 # If type=fixed_amount
max_position_size: Decimal (0.01-1.0)      # Portfolio limit
```

**RiskConfig:**
```yaml
max_daily_loss: Decimal (0.01-1.0)        # % of portfolio
max_drawdown: Decimal (0.01-1.0)          # % threshold
stop_loss_percentage: Decimal (0.01-1.0)  # % below entry
take_profit_percentage: Decimal (0.01-1.0) # % above entry (optional)
```

### Relationships

- **References (1:N)**: One strategy definition references many indicator configurations
- **Consumed by**: Trading sessions (backtest, paper, live) use strategy definition

### Validation Rules

1. **Condition Syntax**: Entry/exit/stop conditions must be valid expressions referencing defined indicator names
2. **Indicator Name Uniqueness**: Each indicator `name` within a strategy must be unique
3. **Position Sizing**: Sum of all concurrent positions cannot exceed 1.0 (100% of capital)
4. **Risk Parameters**: `max_daily_loss` + `max_drawdown` should be set conservatively (recommended sum < 0.30)
5. **Conflicting Conditions**: System must detect and warn if entry/exit conditions can be simultaneously true

### State Transitions

Strategy definitions are immutable once deployed. Version changes create new strategy records.

```
[Draft] ──validate──► [Valid] ──deploy──► [Active]
   │                      │                   │
   │                      │                   │
   └──────invalidate──────┴────────archive────┴──► [Archived]
```

### Example YAML

```yaml
strategy_id: "550e8400-e29b-41d4-a716-446655440000"
name: "RSI Mean Reversion"
description: "Buy oversold, sell overbought using RSI(14)"
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
stop_conditions: "rsi_14 < 25 OR drawdown > 0.05"

position_sizing:
  type: "percentage"
  percentage_of_capital: 0.10
  max_position_size: 0.25

risk_parameters:
  max_daily_loss: 0.03
  max_drawdown: 0.15
  stop_loss_percentage: 0.05
  take_profit_percentage: 0.10
```

---

## 2. Indicator

Calculated technical analysis metric derived from market data.

### Attributes

| Field | Type | Required | Validation | Description |
|-------|------|----------|------------|-------------|
| `indicator_id` | String (UUID) | Auto | UUID v4 | Internal identifier |
| `type` | String | Yes | Valid indicator type | Indicator algorithm (RSI, MACD, etc.) |
| `parameters` | Map | Yes | Type-specific schema | Calculation parameters |
| `calculated_values` | List[Float] | Computed | Aligns with market data | Time-series output |
| `last_calculated_at` | DateTime | Auto | ISO8601 | Cache timestamp |
| `depends_on_bars` | Integer | Computed | >0 | Minimum bars required for calculation |

### Indicator-Specific Parameter Schemas

**RSI:**
- `period`: Integer (2-100, default 14)

**MACD:**
- `short_period`: Integer (2-50, default 12)
- `long_period`: Integer (2-200, default 26)
- `signal_period`: Integer (2-50, default 9)

**Bollinger Bands:**
- `period`: Integer (2-100, default 20)
- `std_dev`: Decimal (0.1-5.0, default 2.0)

**Moving Averages (SMA/EMA):**
- `period`: Integer (2-500, default 50)

**Volume Indicators (OBV, MFI):**
- No required parameters (uses volume + price)

### Relationships

- **Depends on (N:1)**: Multiple indicators consume same market data
- **Used in (N:M)**: Indicators used in signal condition expressions

### Validation Rules

1. **Parameter Ranges**: All numeric parameters must be within documented ranges
2. **Dependency Check**: `long_period` > `short_period` for MACD
3. **Data Sufficiency**: Cannot calculate indicator if available bars < `depends_on_bars`

### State Transitions

Indicators are stateless value transformations. Caching is handled at session level.

---

## 3. Market Data

Time-series price and volume information (OHLCV bars) for a trading pair.

### Attributes

| Field | Type | Required | Validation | Description |
|-------|------|----------|------------|-------------|
| `symbol` | String | Yes | Format: "BASE/QUOTE" | Trading pair |
| `timestamp` | DateTime (UTC) | Yes | ISO8601 | Bar start time |
| `open` | Decimal | Yes | >0 | Opening price |
| `high` | Decimal | Yes | >= open, >= close | Highest price in period |
| `low` | Decimal | Yes | <= open, <= close | Lowest price in period |
| `close` | Decimal | Yes | >0 | Closing price |
| `volume` | Decimal | Yes | >=0 | Trading volume |
| `timeframe` | String | Yes | Enum: "1m", "5m", "1h", "1d" | Bar interval |
| `data_source` | String | Yes | Exchange name | Provider (e.g., "binance") |
| `quality_flag` | String | Auto | Enum: "complete", "partial", "missing" | Data integrity indicator |

### Relationships

- **Consumed by (1:N)**: One market data bar consumed by many indicator calculations
- **Drives**: Signal evaluation (conditions checked on latest bar)

### Validation Rules

1. **OHLC Consistency**: `low <= open <= high`, `low <= close <= high`
2. **Timestamp Alignment**: Timestamps must align to timeframe boundaries (e.g., 1h bars start at :00 minutes)
3. **Volume Non-Negative**: Volume >= 0 (zero allowed for illiquid periods)
4. **No Duplicates**: Unique constraint on `(symbol, timestamp, timeframe, data_source)`

### State Transitions

Market data is immutable once written. Updates are new inserts (for real-time feeds).

---

## 4. Signal

Event indicating a trading action should occur (entry, exit, or stop).

### Attributes

| Field | Type | Required | Validation | Description |
|-------|------|----------|------------|-------------|
| `signal_id` | String (UUID) | Auto | UUID v4 | Unique signal identifier |
| `signal_type` | String | Yes | Enum: "entry", "exit", "stop" | Action type |
| `strategy_id` | String (UUID) | Yes | FK to Strategy Definition | Originating strategy |
| `trading_pair` | String | Yes | Format: "BASE/QUOTE" | Symbol |
| `timestamp` | DateTime (UTC) | Yes | ISO8601 | Signal generation time |
| `trigger_conditions` | Map | Yes | Condition → value pairs | Which conditions triggered |
| `indicator_values` | Map | Yes | Indicator name → value | Snapshot of indicators at signal |
| `price_at_signal` | Decimal | Yes | >0 | Market price when signal generated |
| `confidence_score` | Decimal | No | 0.0-1.0 | Optional signal strength |
| `session_id` | String (UUID) | Yes | FK to Trading Session | Associated session |

### Relationships

- **Produced by**: Strategy evaluation against market data
- **Triggers (1:1)**: One signal triggers one trade (or rejected if invalid)
- **Linked to**: Position (entry signals open, exit/stop signals close)

### Validation Rules

1. **Type Constraints**:
   - `entry` signals only valid when no open position exists
   - `exit` and `stop` signals only valid when position is open
2. **Timestamp Consistency**: Signal timestamp must be <= current market time (no future signals)
3. **Trigger Completeness**: At least one condition must be met from strategy definition

### State Transitions

```
[Generated] ──validate──► [Valid] ──execute──► [Executed]
      │                      │
      │                      │
      └────reject────────────┴──────► [Rejected]
```

**Rejection Reasons:**
- Invalid position state (e.g., entry when already in position)
- Risk limits exceeded (e.g., max daily loss hit)
- Exchange API failure

---

## 5. Trade

Record of a position being opened or closed.

### Attributes

| Field | Type | Required | Validation | Description |
|-------|------|----------|------------|-------------|
| `trade_id` | String (UUID) | Auto | UUID v4 | Unique trade identifier |
| `session_id` | String (UUID) | Yes | FK to Trading Session | Associated session |
| `strategy_id` | String (UUID) | Yes | FK to Strategy Definition | Strategy used |
| `signal_id` | String (UUID) | Yes | FK to Signal | Triggering signal |
| `trading_pair` | String | Yes | Format: "BASE/QUOTE" | Symbol traded |
| `side` | String | Yes | Enum: "buy", "sell" | Order direction |
| `order_type` | String | Yes | Enum: "market", "limit" | Order type |
| `quantity` | Decimal | Yes | >0 | Amount traded |
| `price` | Decimal | Yes | >0 | Execution price |
| `fees` | Decimal | Yes | >=0 | Trading commission |
| `timestamp` | DateTime (UTC) | Yes | ISO8601 | Execution timestamp |
| `mode` | String | Yes | Enum: "backtest", "paper", "live" | Trading mode |
| `pnl` | Decimal | Computed | Any value | Profit/loss for trade |
| `exchange_order_id` | String | Conditional | Required if mode=live | Exchange confirmation ID |
| `slippage` | Decimal | Conditional | >=0 | Diff between expected and actual price |

### Relationships

- **Linked to (N:1)**: Multiple trades can reference same signal (partial fills)
- **Tracked in (N:1)**: Many trades belong to one trading session
- **Opens/Closes (1:1)**: One trade opens or closes one position

### Validation Rules

1. **Mode-Specific**:
   - `backtest`: No `exchange_order_id`, slippage assumed from config
   - `paper`: No `exchange_order_id`, simulate instant fill
   - `live`: Must have `exchange_order_id`, actual slippage recorded
2. **Quantity Constraints**: Quantity must respect position sizing limits from strategy
3. **PnL Calculation**: For closing trades, `pnl = (exit_price - entry_price) * quantity - fees` (buy-to-sell) or `pnl = (entry_price - exit_price) * quantity - fees` (sell-to-buy)

### State Transitions

```
[Pending] ──fill──► [Filled] ──close_position──► [Closed]
    │                  │
    │                  │
    └─────cancel───────┴──────────► [Cancelled]
```

**Backtest/Paper**: Skip [Pending], go straight to [Filled]
**Live**: [Pending] → wait for exchange confirmation → [Filled]

---

## 6. Position

Open trade waiting for exit or stop conditions.

### Attributes

| Field | Type | Required | Validation | Description |
|-------|------|----------|------------|-------------|
| `position_id` | String (UUID) | Auto | UUID v4 | Unique position identifier |
| `session_id` | String (UUID) | Yes | FK to Trading Session | Associated session |
| `trading_pair` | String | Yes | Format: "BASE/QUOTE" | Symbol |
| `side` | String | Yes | Enum: "long", "short" | Position direction |
| `entry_price` | Decimal | Yes | >0 | Average entry price |
| `quantity` | Decimal | Yes | >0 | Position size |
| `entry_timestamp` | DateTime (UTC) | Yes | ISO8601 | Position opened at |
| `unrealized_pnl` | Decimal | Computed | Any value | Current profit/loss (mark-to-market) |
| `stop_loss_price` | Decimal | Conditional | >0 if set | Stop-loss trigger price |
| `take_profit_price` | Decimal | Conditional | >0 if set | Take-profit trigger price |
| `exit_signal_id` | String (UUID) | No | FK to Signal | Signal that closed position |
| `exit_timestamp` | DateTime (UTC) | Conditional | Required if closed | Position closed at |
| `realized_pnl` | Decimal | Conditional | Computed on close | Final profit/loss |

### Relationships

- **Created by (1:1)**: Entry signal/trade opens position
- **Closed by (1:1)**: Exit/stop signal/trade closes position
- **Computed from (N:1)**: Many trades can affect position (averaging)

### Validation Rules

1. **Entry/Exit Pairing**: Position must have entry trade before exit trade
2. **Unrealized PnL**: Continuously updated based on latest market price
   - `unrealized_pnl = (current_price - entry_price) * quantity` (long)
   - `unrealized_pnl = (entry_price - current_price) * quantity` (short)
3. **Stop-Loss Constraints**: `stop_loss_price < entry_price` (long) or `stop_loss_price > entry_price` (short)
4. **Single Position Per Pair**: In initial version, only one open position per trading pair per session

### State Transitions

```
[Open] ──monitor_exit_conditions──► [Closing] ──execute_exit──► [Closed]
  │                                      │
  │                                      │
  └──────stop_loss_triggered─────────────┘
  │
  └──────take_profit_triggered───────────┘
```

**Unrealized PnL** updated continuously while [Open].
**Realized PnL** computed once when transitioning to [Closed].

---

## 7. Trading Session

Execution context for running a strategy in one of three modes (backtest, paper, live).

### Attributes

| Field | Type | Required | Validation | Description |
|-------|------|----------|------------|-------------|
| `session_id` | String (UUID) | Auto | UUID v4 | Unique session identifier |
| `strategy_id` | String (UUID) | Yes | FK to Strategy Definition | Strategy being executed |
| `mode` | String | Yes | Enum: "backtest", "paper", "live" | Execution mode |
| `status` | String | Auto | Enum: "active", "paused", "stopped" | Session state |
| `start_time` | DateTime (UTC) | Yes | ISO8601 | Session started at |
| `end_time` | DateTime (UTC) | Conditional | Required if stopped | Session ended at |
| `capital_allocated` | Decimal | Yes | >0 | Starting capital |
| `capital_available` | Decimal | Computed | >=0 | Current free capital |
| `open_positions` | List[Position] | Computed | List of position IDs | Currently open positions |
| `cumulative_pnl` | Decimal | Computed | Any value | Total realized + unrealized PnL |
| `trades_count` | Integer | Computed | >=0 | Number of trades executed |
| `last_snapshot_at` | DateTime (UTC) | Auto | ISO8601 | Last state persistence time |
| `exchange` | String | Conditional | Required if mode=live | Exchange name (e.g., "binance") |
| `api_credentials` | Map | Conditional | Required if mode=live | Runtime-provided credentials |

### Relationships

- **Contains (1:N)**: One session contains many trades
- **Uses (N:1)**: Many sessions can use same strategy definition
- **Manages (1:N)**: One session manages multiple positions

### Validation Rules

1. **Mode-Specific**:
   - `backtest`: Requires `start_time` and `end_time` (historical range)
   - `paper`: `start_time` only (runs until manually stopped)
   - `live`: Requires `exchange` and `api_credentials`
2. **Capital Constraints**: `capital_available` cannot go negative (risk limits prevent overdraft)
3. **Status Transitions**: Cannot restart `stopped` session (must create new session)

### State Transitions

```
[Initializing] ──validate──► [Active] ──pause──► [Paused]
       │                        │                    │
       │                        │                    │
       └────fail────────────────┴─────stop───────────┴──► [Stopped]
                                 │
                                 └──resume──► [Active]
```

**Backtest**: Auto-transitions to [Stopped] when `end_time` reached.
**Paper/Live**: Remain [Active] until manually stopped or error occurs.

---

## 8. Performance Metrics

Calculated statistics summarizing strategy results.

### Attributes

| Field | Type | Required | Validation | Description |
|-------|------|----------|------------|-------------|
| `session_id` | String (UUID) | Yes | FK to Trading Session | Associated session |
| `total_return` | Decimal | Computed | Any value | % return on capital |
| `total_return_abs` | Decimal | Computed | Any value | Absolute profit/loss |
| `win_rate` | Decimal | Computed | 0.0-1.0 | % of winning trades |
| `max_drawdown` | Decimal | Computed | 0.0-1.0 | Largest peak-to-trough decline |
| `sharpe_ratio` | Decimal | Computed | Any value | Risk-adjusted return |
| `trade_count` | Integer | Computed | >=0 | Total trades executed |
| `winning_trades` | Integer | Computed | >=0 | Number of profitable trades |
| `losing_trades` | Integer | Computed | >=0 | Number of unprofitable trades |
| `average_trade_duration` | Interval | Computed | >=0 | Mean time position held |
| `max_consecutive_wins` | Integer | Computed | >=0 | Longest win streak |
| `max_consecutive_losses` | Integer | Computed | >=0 | Longest loss streak |
| `average_win` | Decimal | Computed | >=0 | Mean profit per winning trade |
| `average_loss` | Decimal | Computed | <=0 | Mean loss per losing trade |
| `profit_factor` | Decimal | Computed | >=0 | Gross profit / gross loss |
| `computed_at` | DateTime (UTC) | Auto | ISO8601 | Metrics calculation time |

### Relationships

- **Computed from (1:N)**: Metrics derived from all completed trades in session

### Validation Rules

1. **Trade Count Consistency**: `winning_trades + losing_trades <= trade_count` (some trades may be break-even)
2. **Win Rate**: `win_rate = winning_trades / trade_count` (undefined if trade_count = 0)
3. **Sharpe Ratio**: Requires minimum 30 trades for statistical significance (warn if less)
4. **Max Drawdown**: Computed as max(0, (peak_equity - current_equity) / peak_equity) across session lifetime

### Calculation Formulas

**Total Return:**
```
total_return = (final_equity - initial_capital) / initial_capital
```

**Sharpe Ratio:**
```
sharpe_ratio = (mean_return - risk_free_rate) / std_dev_returns
# Assume risk_free_rate = 0 for crypto
```

**Max Drawdown:**
```
max_drawdown = max(0, (peak_equity - trough_equity) / peak_equity)
# Track across all equity snapshots
```

**Profit Factor:**
```
profit_factor = sum(winning_trades_pnl) / abs(sum(losing_trades_pnl))
# Undefined if no losing trades
```

### State Transitions

Metrics are recalculated whenever:
- New trade completes
- Session status changes
- User requests refresh

---

## Database Schema Mapping

### PostgreSQL Tables

**strategies:**
- PK: `strategy_id` (UUID)
- Columns: `name`, `description`, `trading_pair`, `timeframe`, `indicators` (JSONB), `entry_conditions`, `exit_conditions`, `stop_conditions`, `position_sizing` (JSONB), `risk_parameters` (JSONB), `version`, `created_at`

**market_data:** (TimescaleDB hypertable)
- PK: `(symbol, timestamp, timeframe, data_source)`
- Columns: `open`, `high`, `low`, `close`, `volume`, `quality_flag`
- Index: `(symbol, timestamp DESC)` for fast latest bar queries

**trading_sessions:**
- PK: `session_id` (UUID)
- FK: `strategy_id` → `strategies(strategy_id)`
- Columns: `mode`, `status`, `start_time`, `end_time`, `capital_allocated`, `capital_available`, `cumulative_pnl`, `trades_count`, `last_snapshot_at`, `exchange`, `positions` (JSONB)

**trades:**
- PK: `trade_id` (UUID)
- FK: `session_id` → `trading_sessions(session_id)`
- FK: `strategy_id` → `strategies(strategy_id)`
- FK: `signal_id` → `signals(signal_id)`
- Columns: `trading_pair`, `side`, `order_type`, `quantity`, `price`, `fees`, `timestamp`, `mode`, `pnl`, `exchange_order_id`, `slippage`
- Index: `(session_id, timestamp DESC)` for session trade history

**signals:**
- PK: `signal_id` (UUID)
- FK: `strategy_id` → `strategies(strategy_id)`
- FK: `session_id` → `trading_sessions(session_id)`
- Columns: `signal_type`, `trading_pair`, `timestamp`, `trigger_conditions` (JSONB), `indicator_values` (JSONB), `price_at_signal`, `confidence_score`

**positions:**
- PK: `position_id` (UUID)
- FK: `session_id` → `trading_sessions(session_id)`
- Columns: `trading_pair`, `side`, `entry_price`, `quantity`, `entry_timestamp`, `unrealized_pnl`, `stop_loss_price`, `take_profit_price`, `exit_signal_id`, `exit_timestamp`, `realized_pnl`
- Unique constraint: `(session_id, trading_pair)` WHERE `exit_timestamp IS NULL` (one open position per pair)

**performance_metrics:**
- PK: `(session_id, computed_at)`
- FK: `session_id` → `trading_sessions(session_id)`
- Columns: All metric fields from entity definition
- Index: `(session_id, computed_at DESC)` for historical metric tracking

---

## Caching Strategy (FR-027)

**Indicator Values:**
- Cache in ETS table: `{strategy_id, indicator_name, timestamp} → calculated_values`
- Invalidate when new market data arrives for timeframe
- TTL: Until next bar completes

**Market Data:**
- PostgreSQL + TimescaleDB for historical data
- ETS for last N bars (sliding window, e.g., 500 bars)
- Real-time updates via WebSocket populate ETS first, then async DB write

**Session State:**
- GenServer process holds current session state (positions, capital)
- Periodic snapshots to PostgreSQL (every 60 seconds per research.md)
- On crash recovery: Load last snapshot + replay delta trades

---

## Validation Summary

**Cross-Entity Validation:**
1. Strategy references valid indicator types from Indicado library
2. Signal timestamps align with market data bar timestamps
3. Position entry/exit prices match trade prices
4. Session capital_available = capital_allocated - sum(open_position_values) - sum(unrealized_pnl)
5. Performance metrics trade_count matches actual trades in database

**Consistency Constraints:**
1. No orphaned trades (every trade has valid session_id and strategy_id)
2. No orphaned positions (every open position has entry trade)
3. Closed positions must have exit trade and realized_pnl computed
4. Session cumulative_pnl = sum(realized_pnl) + sum(unrealized_pnl)

---

This data model satisfies all functional requirements (FR-001 through FR-030) and supports the three trading modes (backtest, paper, live) with appropriate state management and validation.
