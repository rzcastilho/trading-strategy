# Data Model: Fix Backtesting Issues

**Feature**: 003-fix-backtesting
**Date**: 2026-02-03
**Status**: Draft

## Overview

This document defines the data model changes required to support accurate progress tracking, equity curve storage, trade-level PnL, and persistent state management for the backtesting engine.

## Entity Relationship Diagram

```
TradingSession (existing + modified)
    ├── has_many Positions
    │   └── has_many Trades (modified: add pnl, duration)
    ├── has_many Signals
    ├── has_one PerformanceMetrics (modified: add equity_curve)
    └── metadata (enhanced: checkpoints, queue info)

ProgressTracker (new: in-memory ETS)
    └── tracks {session_id, bars_processed, total_bars}

ConcurrencyManager (new: in-memory GenServer state)
    ├── running: MapSet of session_ids
    └── queue: FIFO queue of pending session_ids
```

## Schema Changes

### 1. Trades Table (Modified)

**Purpose**: Store individual trade executions with PnL and duration

**Migration**: `priv/repo/migrations/YYYYMMDDHHMMSS_add_pnl_and_duration_to_trades.exs`

```elixir
defmodule TradingStrategy.Repo.Migrations.AddPnlAndDurationToTrades do
  use Ecto.Migration

  def change do
    alter table(:trades) do
      add :pnl, :decimal, precision: 20, scale: 8, default: 0
      add :duration_seconds, :integer
      add :entry_price, :decimal, precision: 20, scale: 8
      add :exit_price, :decimal, precision: 20, scale: 8
    end

    create index(:trades, [:pnl])
  end
end
```

**Schema Updates**: `lib/trading_strategy/orders/trade.ex`

```elixir
schema "trades" do
  # Existing fields
  field :side, Ecto.Enum, values: [:buy, :sell]
  field :quantity, :decimal
  field :price, :decimal
  field :fee, :decimal
  field :fee_currency, :string
  field :timestamp, :utc_datetime_usec
  field :exchange, :string
  field :status, :string
  field :metadata, :map

  # NEW FIELDS
  field :pnl, :decimal  # Net profit/loss for this trade (after fees)
  field :duration_seconds, :integer  # Time held (for position exit trades)
  field :entry_price, :decimal  # Average entry price (copied from position)
  field :exit_price, :decimal  # Exit price (for exit trades)

  belongs_to :position, TradingStrategy.Orders.Position
  belongs_to :signal, TradingStrategy.Signals.Signal
  belongs_to :order, TradingStrategy.Orders.Order

  timestamps(type: :utc_datetime_usec)
end
```

**Validation Rules**:
- `pnl` required for exit trades (side = :sell for long, :buy for short)
- `duration_seconds` required for exit trades, must be >= 0
- `entry_price` and `exit_price` required for PnL calculation verification
- `price` must be > 0
- `quantity` must be > 0

**State Transitions**: None (trades are immutable once created)

---

### 2. PerformanceMetrics Table (Modified)

**Purpose**: Store backtest performance metrics including equity curve

**Migration**: `priv/repo/migrations/YYYYMMDDHHMMSS_add_equity_curve_to_performance_metrics.exs`

```elixir
defmodule TradingStrategy.Repo.Migrations.AddEquityCurveToPerformanceMetrics do
  use Ecto.Migration

  def change do
    alter table(:performance_metrics) do
      add :equity_curve, :jsonb, default: "[]"
      add :equity_curve_metadata, :map, default: %{}
    end

    create index(:performance_metrics, [:equity_curve], using: :gin)
  end
end
```

**Schema Updates**: `lib/trading_strategy/backtesting/performance_metrics.ex`

```elixir
schema "performance_metrics" do
  # Existing fields
  field :total_return, :decimal
  field :total_return_pct, :decimal
  field :sharpe_ratio, :decimal
  field :max_drawdown, :decimal
  field :max_drawdown_pct, :decimal
  field :win_rate, :decimal
  field :profit_factor, :decimal
  field :total_trades, :integer
  field :winning_trades, :integer
  field :losing_trades, :integer
  field :avg_win, :decimal
  field :avg_loss, :decimal
  field :largest_win, :decimal
  field :largest_loss, :decimal
  field :consecutive_wins, :integer
  field :consecutive_losses, :integer
  field :avg_trade_duration, :integer

  # NEW FIELDS
  field :equity_curve, {:array, :map}  # Array of %{timestamp: ISO8601, value: Decimal}
  field :equity_curve_metadata, :map   # Sampling info, e.g., %{sampled: true, sample_rate: 100}

  belongs_to :trading_session, TradingStrategy.Backtesting.TradingSession

  timestamps(type: :utc_datetime_usec)
end
```

**Equity Curve Format**:
```json
[
  {"timestamp": "2024-01-01T00:00:00Z", "value": 10000.00},
  {"timestamp": "2024-01-01T01:00:00Z", "value": 10150.50},
  {"timestamp": "2024-01-01T02:00:00Z", "value": 10120.25},
  ...
]
```

**Validation Rules**:
- `equity_curve` array length <= 1000 (enforced by sampling)
- Each curve point must have `timestamp` (ISO8601 string) and `value` (numeric)
- `equity_curve[0].value` should equal `trading_session.initial_capital`
- `equity_curve[-1].value` should equal `trading_session.current_capital`
- Timestamps must be in ascending order

**Metadata Fields**:
```elixir
%{
  sampled: true,
  sample_rate: 100,  # Every 100th bar included
  original_length: 5000,  # Total bars before sampling
  trade_points_included: 150  # Entry/exit points always included
}
```

---

### 3. TradingSession Table (Modified)

**Purpose**: Enhanced metadata for checkpoints, queue state, and progress tracking

**Migration**: `priv/repo/migrations/YYYYMMDDHHMMSS_enhance_trading_session_metadata.exs`

```elixir
defmodule TradingStrategy.Repo.Migrations.EnhanceTradingSessionMetadata do
  use Ecto.Migration

  def change do
    alter table(:trading_sessions) do
      add :queued_at, :utc_datetime_usec
    end

    # Add index for finding stale "running" sessions on restart
    create index(:trading_sessions, [:status, :updated_at])
  end
end
```

**Schema Updates**: `lib/trading_strategy/backtesting/trading_session.ex`

```elixir
schema "trading_sessions" do
  # Existing fields
  field :strategy_id, :string
  field :mode, :string  # "backtest", "paper", "live"
  field :status, :string  # "pending", "queued", "running", "completed", "stopped", "error"
  field :initial_capital, :decimal
  field :current_capital, :decimal
  field :started_at, :utc_datetime_usec
  field :ended_at, :utc_datetime_usec
  field :config, :map
  field :metadata, :map

  # NEW FIELD
  field :queued_at, :utc_datetime_usec  # When session was queued (if applicable)

  has_many :positions, TradingStrategy.Orders.Position
  has_many :signals, TradingStrategy.Signals.Signal
  has_one :performance_metrics, TradingStrategy.Backtesting.PerformanceMetrics

  timestamps(type: :utc_datetime_usec)
end
```

**Enhanced Metadata Structure**:
```elixir
%{
  # Checkpoint data for resume capability
  checkpoint: %{
    bar_index: 2500,
    bars_processed: 2500,
    total_bars: 5000,
    last_equity: Decimal.new("10500.00"),
    completed_trades: 42,
    checkpointed_at: ~U[2024-01-01 12:30:45.123456Z]
  },

  # Queue tracking
  queue_position: 3,  # Position in queue when status = "queued"
  queue_depth: 5,     # Total backtests queued at time of entry

  # Execution tracking
  execution_started_at: ~U[2024-01-01 12:00:00Z],
  execution_ended_at: ~U[2024-01-01 12:35:00Z],
  execution_duration_ms: 2100000,

  # Error tracking (if status = "error")
  error_type: "application_restart",
  error_message: "Backtest interrupted by application restart at 50% completion",
  partial_data_saved: true
}
```

**Validation Rules**:
- `status` must be one of: "pending", "queued", "running", "completed", "stopped", "error"
- `queued_at` required when status = "queued"
- `started_at` required when status = "running"
- `ended_at` required when status in ["completed", "stopped", "error"]
- `config` must include: trading_pair, start_time, end_time, initial_capital, timeframe

**State Transitions**:
```
pending → queued → running → completed
                           → stopped
                           → error
pending → running → ... (if no queue)
```

---

### 4. Positions Table (No Schema Changes)

**Purpose**: Existing position tracking is sufficient

**Notes**:
- `realized_pnl` aggregates all trade PnLs for the position
- `opened_at` and `closed_at` provide position-level duration
- No changes needed, but Position PnL should be validated against sum of Trade PnLs

---

### 5. ProgressTracker (In-Memory ETS)

**Purpose**: Fast, concurrent progress lookup for active backtests

**Structure**: ETS table `:backtest_progress`

```elixir
# Table configuration
:ets.new(:backtest_progress, [
  :set,            # One entry per session_id
  :public,         # Any process can read
  :named_table,    # Access by name
  read_concurrency: true  # Optimize for concurrent reads
])

# Entry format
{
  session_id,          # UUID (binary)
  bars_processed,      # Integer
  total_bars,          # Integer
  started_at,          # System.monotonic_time() for accurate duration
  updated_at           # System.monotonic_time() for staleness detection
}
```

**Lifecycle**:
- **Created**: When backtest starts (`Backtesting.start_backtest/1`)
- **Updated**: Every 100 bars processed (or 1% progress, whichever is less frequent)
- **Deleted**: When backtest completes/fails or after 24h of staleness

**Access Pattern**:
```elixir
# Read (hot path - must be fast)
:ets.lookup(:backtest_progress, session_id)

# Write (less frequent)
:ets.insert(:backtest_progress, {session_id, processed, total, started, now})

# Cleanup
:ets.delete(:backtest_progress, session_id)
```

---

### 6. ConcurrencyManager (In-Memory GenServer State)

**Purpose**: Enforce concurrent backtest limit and manage queue

**State Structure**:
```elixir
%{
  running: MapSet.new(),  # Set of currently executing session_ids
  queue: :queue.new(),    # FIFO queue of {session_id, from_pid} tuples
  max_concurrent: 5       # Configurable limit
}
```

**Lifecycle**:
- **Start**: When application starts (in supervision tree)
- **Slot Request**: When `Backtesting.start_backtest/1` called
  - If slots available: Grant immediately, add to running set
  - If full: Add to queue, update session status to "queued"
- **Slot Release**: When backtest completes/fails
  - Remove from running set
  - Pop next from queue, grant slot, start queued backtest
- **Restart**: State is volatile - on restart, check DB for "running" sessions and mark as "error"

---

## Database Indexes

### New Indexes:
```elixir
# For finding stale running sessions on restart
create index(:trading_sessions, [:status, :updated_at])

# For trade PnL analysis and sorting
create index(:trades, [:pnl])
create index(:trades, [:position_id, :timestamp])

# For equity curve JSON queries (optional - if querying curve data)
create index(:performance_metrics, [:equity_curve], using: :gin)
```

### Existing Indexes (Preserved):
```elixir
create index(:positions, [:trading_session_id])
create index(:trades, [:position_id])
create index(:trades, [:signal_id])
create index(:performance_metrics, [:trading_session_id])
```

---

## Data Constraints

### Trade PnL Consistency:
```sql
-- Position realized_pnl should equal sum of trade PnLs for that position
-- Enforced in application logic, not database constraint (due to Decimal precision)

-- Validation query (for tests):
SELECT
  p.id,
  p.realized_pnl AS position_pnl,
  SUM(t.pnl) AS trades_pnl_sum,
  ABS(p.realized_pnl - SUM(t.pnl)) AS difference
FROM positions p
LEFT JOIN trades t ON t.position_id = p.id
WHERE p.status = 'closed'
GROUP BY p.id, p.realized_pnl
HAVING ABS(p.realized_pnl - SUM(t.pnl)) > 0.01;  -- Should return 0 rows
```

### Equity Curve Validation:
```elixir
# In application code, validate:
# 1. First point value = initial_capital
assert List.first(equity_curve)["value"] == Decimal.to_float(initial_capital)

# 2. Last point value = final_capital
assert List.last(equity_curve)["value"] == Decimal.to_float(current_capital)

# 3. Monotonic timestamps
timestamps = Enum.map(equity_curve, & &1["timestamp"])
assert timestamps == Enum.sort(timestamps)

# 4. No more than 1000 points (sampled)
assert length(equity_curve) <= 1000
```

---

## Migration Strategy

### Rollout Order:
1. **Add pnl and duration to trades** (backward compatible - default 0)
2. **Add equity_curve to performance_metrics** (backward compatible - default [])
3. **Add queued_at to trading_sessions** (backward compatible - nullable)
4. **Add indexes** (online, no downtime)
5. **Deploy application code** (backward reads old data as empty/default)
6. **Backfill equity curves** (optional - for historical backtests, if desired)

### Rollback Strategy:
- Migrations are additive (no data removal)
- If rollback needed, remove columns in reverse order
- Old code ignores new columns gracefully

### Data Backfill:
```elixir
# Optional: Backfill trade PnL from positions
defmodule Backfill.TradePnl do
  def run do
    from(t in Trade,
      join: p in Position, on: t.position_id == p.id,
      where: is_nil(t.pnl) and not is_nil(p.realized_pnl),
      select: {t.id, p.id}
    )
    |> Repo.all()
    |> Enum.each(fn {trade_id, position_id} ->
      # Calculate trade PnL from position data and update
      # (requires position entry/exit prices and trade details)
    end)
  end
end
```

---

## Performance Considerations

### Equity Curve Storage:
- **Size**: ~1000 points × 50 bytes/point = ~50KB per backtest
- **Growth**: 1000 backtests/day = 50MB/day (negligible)
- **JSONB Index**: GIN index on equity_curve if querying curve data (e.g., "find backtests with drawdown > X at time T")
- **Query**: Equity curve returned as JSON array, parsed client-side for charts

### Trade PnL Index:
- **Purpose**: Enable fast sorting/filtering by profitability
- **Cost**: Minimal - Decimal type is fixed-size
- **Benefit**: Enables queries like "top 10 most profitable trades" without full table scan

### Progress Tracking ETS:
- **Access Pattern**: High read frequency (polling every 5s), low write frequency (every 100 bars)
- **Memory**: ~100 bytes per active backtest, max 10 concurrent = ~1KB total (negligible)
- **Concurrency**: `read_concurrency: true` enables lock-free reads

---

## Testing Strategy

### Schema Tests:
```elixir
# test/trading_strategy/orders/trade_test.exs
test "trade with pnl is valid" do
  trade = %Trade{
    pnl: Decimal.new("150.50"),
    duration_seconds: 3600,
    entry_price: Decimal.new("50000"),
    exit_price: Decimal.new("50500"),
    ...
  }
  changeset = Trade.changeset(trade, %{})
  assert changeset.valid?
end

test "exit trade requires pnl" do
  trade = %Trade{side: :sell, pnl: nil, ...}
  changeset = Trade.changeset(trade, %{})
  refute changeset.valid?
  assert "can't be blank" in errors_on(changeset).pnl
end
```

### Migration Tests:
```elixir
# test/trading_strategy/repo/migrations_test.exs
test "equity_curve migration is reversible" do
  assert :ok = Ecto.Migrator.up(Repo, migration_version, AddEquityCurveToPerformanceMetrics)
  assert :ok = Ecto.Migrator.down(Repo, migration_version, AddEquityCurveToPerformanceMetrics)
end
```

### Constraint Tests:
```elixir
# test/trading_strategy/backtesting/data_integrity_test.exs
test "position pnl equals sum of trade pnls" do
  position = create_closed_position_with_trades()

  trades_pnl_sum = Enum.reduce(position.trades, Decimal.new(0), fn trade, acc ->
    Decimal.add(acc, trade.pnl)
  end)

  assert Decimal.eq?(position.realized_pnl, trades_pnl_sum)
end
```

---

**Data Model Complete** - Ready for API Contracts (Phase 1b)
