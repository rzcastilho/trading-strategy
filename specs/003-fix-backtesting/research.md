# Research Document: Fix Backtesting Issues

**Feature**: 003-fix-backtesting
**Date**: 2026-02-03
**Status**: Complete

## Research Questions

### 1. Progress Tracking Implementation

**Question**: How should real-time progress tracking be implemented for async backtests?

**Decision**: Use GenServer-based progress tracker with ETS table for fast lookups

**Rationale**:
- Current approach stores task references in process dictionary, lost on restart
- ETS provides fast, concurrent reads for polling without blocking backtest execution
- GenServer manages lifecycle and cleanup of progress records
- Aligns with Principle IV (Observability) and FR-006 (restart reliability)

**Alternatives Considered**:
- **Database polling**: Too slow for real-time updates, adds DB load
- **Phoenix PubSub broadcasts**: Overkill for simple progress tracking, requires client subscription
- **Process.get/put (current)**: Loses state on restart, not supervised

**Implementation Approach**:
```elixir
# New module: TradingStrategy.Backtesting.ProgressTracker
defmodule TradingStrategy.Backtesting.ProgressTracker do
  use GenServer

  def start_link(_opts) do
    GenServer.start_link(__MODULE__, :ok, name: __MODULE__)
  end

  def init(:ok) do
    :ets.new(:backtest_progress, [:set, :public, :named_table, read_concurrency: true])
    {:ok, %{}}
  end

  def update(session_id, bars_processed, total_bars) do
    :ets.insert(:backtest_progress, {session_id, bars_processed, total_bars, System.monotonic_time()})
  end

  def get(session_id) do
    case :ets.lookup(:backtest_progress, session_id) do
      [{^session_id, processed, total, updated_at}] ->
        percentage = if total > 0, do: Float.round(processed / total * 100, 2), else: 0.0
        {:ok, %{bars_processed: processed, total_bars: total, percentage: percentage}}
      [] ->
        {:error, :not_found}
    end
  end

  def remove(session_id) do
    :ets.delete(:backtest_progress, session_id)
  end
end
```

**Best Practices**:
- Update progress every N bars (e.g., every 100) to reduce overhead
- Clean up progress records after backtest completion or after timeout (24h)
- Use monotonic time for accurate time-remaining estimation

---

### 2. Equity Curve Storage Strategy

**Question**: What's the optimal storage approach for equity curve data (thousands of points per backtest)?

**Decision**: Store sampled equity curve in JSONB column in PerformanceMetrics table

**Rationale**:
- Equity curves are read-only after backtest completion (no updates needed)
- Sampling to ~1000 points provides sufficient visualization detail while minimizing storage
- JSONB provides flexible structure for timestamp-value pairs without schema changes
- Keeps related data (metrics + curve) in single table, simpler queries
- PostgreSQL JSONB is efficient for read-heavy workloads

**Alternatives Considered**:
- **Dedicated equity_curve_points table**: More normalized, but overkill for read-only sampled data; adds JOIN overhead
- **TimescaleDB hypertable**: Optimized for time-series writes, but equity curves are bulk-insert once (not streaming); TimescaleDB better suited for live market data
- **Text field (CSV)**: Less queryable, no type safety, parsing overhead
- **External storage (S3)**: Adds latency and complexity for small datasets (<100KB per backtest)

**Implementation Approach**:
```elixir
# Migration: Add equity_curve column to performance_metrics
alter table(:performance_metrics) do
  add :equity_curve, :jsonb, default: "[]"
end

# Format: Array of {timestamp, value} pairs (ISO8601 timestamp string for JSON compatibility)
[
  {"2024-01-01T00:00:00Z", 10000.00},
  {"2024-01-01T01:00:00Z", 10150.50},
  ...
]

# Sampling in EquityCurve.sample/2 already implemented (max 1000 points)
```

**Best Practices**:
- Sample at trade entry/exit points + intermediate bars (spec: every 100th bar)
- Use ISO8601 timestamp strings in JSON for client compatibility
- Index on performance_metrics.trading_session_id for fast lookup
- Include sampling metadata in PerformanceMetrics.metadata field (e.g., `"equity_curve_sampled": true, "sample_rate": 100`)

---

### 3. Trade PnL Attribution

**Question**: Where should individual trade PnL be stored (Trade vs Position schema)?

**Decision**: Add pnl field to Trade schema, calculate and store at trade execution time

**Rationale**:
- Positions can have multiple entry/exit trades (partial fills, scaling in/out)
- Trade-level PnL enables granular analysis (which specific trade profitable)
- Aligns with spec FR-004 (store actual PnL for each individual trade)
- MetricsCalculator already expects trade.pnl field (line 45-46 in metrics_calculator.ex)

**Alternatives Considered**:
- **Position-level PnL only (current)**: Loses granularity when position has multiple trades; trade analytics impossible
- **Calculated on-the-fly**: Repeating calculation wasteful, complicates metrics computation

**Implementation Approach**:
```elixir
# Migration: Add pnl and duration_seconds to trades table
alter table(:trades) do
  add :pnl, :decimal, precision: 20, scale: 8, default: 0
  add :duration_seconds, :integer
end

# In SimulatedExecutor.execute_order/5, calculate PnL:
# For entry trade: pnl = 0 (no realized gain yet)
# For exit trade: pnl = (exit_price - avg_entry_price) * quantity * direction - fees
#   direction = 1 for long, -1 for short

# In PositionManager.close_position/3, link exit trade PnL to position
```

**Best Practices**:
- Use Decimal type for PnL to avoid floating-point errors (already in codebase)
- Store both gross PnL (price difference) and net PnL (after fees) - use single pnl field for net
- Include fee breakdown in Trade.metadata for auditability (Principle IV)
- Duration calculated as `DateTime.diff(exit_timestamp, entry_timestamp, :second)`

---

### 4. State Persistence Across Restarts

**Question**: How should backtest task state be managed to survive application restarts?

**Decision**: Supervisor-based Task management with periodic checkpointing to database

**Rationale**:
- Current `Task.async` approach loses task reference on restart (FR-006 violation)
- Supervisor ensures task failures are isolated and logged
- Checkpointing enables resume capability (spec: "allow manual resume from last checkpoint")
- Aligns with OTP "let it crash" philosophy (Principle IV - auditability)

**Alternatives Considered**:
- **External job queue (Oban)**: Robust but adds dependency; overkill for single-node deployment (spec assumption)
- **Database-only polling**: No async execution, blocks API requests
- **Current Task.async (no supervision)**: Already proven insufficient (status lost on restart)

**Implementation Approach**:
```elixir
# Enable BacktestingSupervisor with DynamicSupervisor for backtest tasks
defmodule TradingStrategy.Backtesting.Supervisor do
  use DynamicSupervisor

  def start_link(init_arg) do
    DynamicSupervisor.start_link(__MODULE__, init_arg, name: __MODULE__)
  end

  def start_backtest_task(session_id, config) do
    child_spec = %{
      id: {BacktestTask, session_id},
      start: {Task, :start_link, [fn -> run_backtest_with_checkpoints(session_id, config) end]},
      restart: :temporary
    }
    DynamicSupervisor.start_child(__MODULE__, child_spec)
  end
end

# Checkpointing: Update TradingSession.metadata with checkpoint state every 1000 bars
# Structure: %{checkpoint: %{bar_index: N, last_equity: X, completed_trades: M}}
```

**Best Practices**:
- Mark interrupted backtests as "error" status on restart detection (spec clarification)
- Store checkpoint data in TradingSession.metadata (JSONB, no schema change needed)
- Checkpoint frequency: every 1000 bars or 10% progress (whichever is less frequent)
- On restart, check for "running" sessions without active task → mark as "error", preserve partial data

---

### 5. Concurrent Backtest Limiting

**Question**: How to enforce concurrent backtest limit (5-10) and queue excess requests?

**Decision**: Token-based semaphore with in-memory FIFO queue

**Rationale**:
- Spec clarifies: "Hard limit with queueing (e.g., max 5-10 concurrent, queue excess requests)" (FR-016)
- Prevents resource exhaustion on single-node deployment
- In-memory queue acceptable for single-node (spec assumption #8)
- Simplicity aligns with Principle VII (avoid premature optimization)

**Alternatives Considered**:
- **Oban job queue**: Persistent queue, but adds external dependency; not needed for single-node
- **No limit (current)**: Risks OOM with many concurrent backtests
- **Reject excess requests (no queue)**: Poor UX, forces client-side retry logic

**Implementation Approach**:
```elixir
defmodule TradingStrategy.Backtesting.Concurrency do
  use GenServer

  @max_concurrent 5

  def init(_) do
    {:ok, %{running: MapSet.new(), queue: :queue.new()}}
  end

  def request_slot(session_id) do
    GenServer.call(__MODULE__, {:request_slot, session_id})
  end

  def handle_call({:request_slot, session_id}, from, state) do
    if MapSet.size(state.running) < @max_concurrent do
      {:reply, :ok, %{state | running: MapSet.put(state.running, session_id)}}
    else
      new_queue = :queue.in({session_id, from}, state.queue)
      {:noreply, %{state | queue: new_queue}}
    end
  end

  def release_slot(session_id) do
    GenServer.cast(__MODULE__, {:release_slot, session_id})
  end

  def handle_cast({:release_slot, session_id}, state) do
    state = %{state | running: MapSet.delete(state.running, session_id)}

    case :queue.out(state.queue) do
      {{:value, {next_id, from}}, new_queue} ->
        GenServer.reply(from, :ok)
        {:noreply, %{state | running: MapSet.put(state.running, next_id), queue: new_queue}}
      {:empty, _} ->
        {:noreply, state}
    end
  end
end
```

**Best Practices**:
- Make max_concurrent configurable via Application.get_env (default: 5)
- Update TradingSession.status to "queued" for waiting backtests
- Add `queued_at` timestamp to TradingSession.metadata for queue time tracking
- Log queue depth as metric for monitoring (Principle IV - observability)

---

### 6. Performance Optimization (O(n²) Complexity)

**Question**: What causes O(n²) complexity in bar processing, and how to optimize?

**Investigation Results** (from codebase analysis):

**Root Cause**: Inefficient signal/position lookups in tight loop

In `Engine.execute_backtest_loop/3`, for each bar:
1. Evaluate entry signals (iterates strategy rules)
2. Check all open positions for exit conditions
3. Update equity curve (iterates all positions for unrealized PnL)

If using linear searches (`Enum.find`) in nested loops → O(n²) with n = number of bars

**Decision**: Use indexed data structures (Map) for positions and signals

**Rationale**:
- Map lookups are O(1) vs O(n) for Enum.find
- Minimal memory overhead for typical backtest (10K bars = ~10-20 open positions max)
- Aligns with Principle VI (performance discipline) and SC-010 (30% improvement target)

**Implementation Approach**:
```elixir
# Replace position list with map keyed by position ID
state = %{
  ...
  positions: %{} # Map of position_id => position_struct
}

# In PositionManager, return {:ok, position_id, updated_positions_map}
# Update equity by iterating map values (O(k) where k = open positions, typically < 20)

# For signal evaluation, maintain signal index by type
signal_index = %{
  entry: [...],  # List of entry signals (evaluated once per bar)
  exit: [...]    # List of exit signals (cached compiled expressions)
}
```

**Best Practices**:
- Profile with `:timer.tc` before/after optimization (Principle VI requirement)
- Benchmark with 10K, 50K, 100K bar datasets (SC-006)
- Cache compiled signal expressions (already done in strategy parsing)

**Alternatives Considered**:
- **ETS tables for positions**: Overkill for in-process data, adds serialization overhead
- **Parallel bar processing**: Breaks sequential causality (position state depends on previous bars)

---

### 7. Test Coverage Strategy

**Question**: How to achieve >80% unit test coverage for backtesting modules?

**Decision**: Combination of unit tests (module isolation) and property-based tests (edge cases)

**Rationale**:
- FR-008 requires comprehensive unit test coverage
- Property-based testing (StreamData) ideal for edge cases (spec: zero trades, insufficient data, etc.)
- Aligns with Principle II (Red-Green-Refactor) and Constitution testing requirements

**Test Organization**:
```
test/trading_strategy/backtesting/
├── engine_test.exs                  # Core execution logic
├── position_manager_test.exs        # Position open/close, PnL calculation
├── simulated_executor_test.exs      # Trade execution with slippage/fees
├── metrics_calculator_test.exs      # Performance metrics accuracy
├── equity_curve_test.exs            # Curve generation, sampling
├── progress_tracker_test.exs        # Progress tracking (NEW)
├── concurrency_test.exs             # Concurrent limit enforcement (NEW)
└── integration/
    └── full_backtest_flow_test.exs  # End-to-end backtest execution
```

**Property-Based Test Examples** (using StreamData):
```elixir
# Test position PnL with random prices
property "position PnL matches manual calculation" do
  check all entry <- float(min: 0.01, max: 100000),
            exit <- float(min: 0.01, max: 100000),
            quantity <- float(min: 0.001, max: 1000),
            side <- member_of([:long, :short]) do

    position = %Position{entry_price: entry, side: side, quantity: quantity}
    closed = PositionManager.close_position(position, exit, timestamp)

    expected_pnl = calculate_expected_pnl(entry, exit, quantity, side)
    assert_in_delta closed.realized_pnl, expected_pnl, 0.0001
  end
end

# Test equity curve with empty trade list
test "zero trades returns flat equity curve" do
  result = Engine.run_backtest(strategy, config_with_no_signals)

  assert result.equity_curve == [
    {config.start_time, 10000.00},
    {config.end_time, 10000.00}
  ]
  assert result.metrics.total_return_pct == 0.0
  assert result.metrics.win_rate == nil  # N/A for zero trades
end
```

**Coverage Targets** (per spec SC-005):
- MetricsCalculator: >90% (high complexity, critical for results)
- Engine: >85% (core execution path)
- PositionManager: >85% (PnL calculations)
- SimulatedExecutor: >80% (straightforward logic)
- ProgressTracker: >80% (new module)
- Overall: >80% (enforced by `mix test --cover`)

**Best Practices**:
- Mock MarketData module for deterministic bar data
- Use ExUnit's `describe` blocks for scenario grouping
- Tag slow integration tests with `@tag :integration` for optional runs
- Add edge cases from spec explicitly as individual test cases

---

## Technology Decisions Summary

| Component | Technology | Justification |
|-----------|-----------|---------------|
| Progress Tracking | GenServer + ETS | Fast concurrent reads, supervised, survives restarts if recreated |
| Equity Curve Storage | JSONB in PerformanceMetrics | Efficient for read-only sampled data, no schema changes needed |
| Trade PnL | Decimal field in Trade schema | Granular analytics, accurate calculations, matches MetricsCalculator expectations |
| State Persistence | DynamicSupervisor + Checkpointing | OTP-aligned, enables resume capability, isolates failures |
| Concurrent Limiting | Token-based semaphore + FIFO queue | Simple, single-node appropriate, good UX |
| Performance Optimization | Map-based indexing | O(1) lookups, minimal memory overhead, measurable improvement |
| Test Coverage | ExUnit + StreamData | Standard Elixir testing, property-based for edge cases, >80% achievable |

---

## Open Questions / Risks

### Resolved:
- ✅ How to track progress? → ETS + GenServer
- ✅ Where to store equity curve? → JSONB in performance_metrics
- ✅ Trade vs Position PnL? → Trade schema
- ✅ Restart reliability? → Supervisor + checkpoints
- ✅ Concurrent limit enforcement? → Semaphore + queue
- ✅ Performance bottleneck? → Indexed data structures
- ✅ Test strategy? → Unit + property-based tests

### Remaining (for implementation phase):
- Checkpoint resume UI/API design (spec says "manual resume" - needs endpoint design)
- Equity curve sampling rate tuning (spec says "every 100th bar" - may need adjustment based on data density)
- Migration rollback strategy (if equity_curve column added, how to handle old results?)

---

## References

- Feature Spec: `/specs/003-fix-backtesting/spec.md`
- Constitution: `/.specify/memory/constitution.md`
- Current Engine: `/lib/trading_strategy/backtesting/engine.ex`
- Current Backtesting Context: `/lib/trading_strategy/backtesting.ex`
- Schemas: `/lib/trading_strategy/backtesting/*.ex`, `/lib/trading_strategy/orders/*.ex`

---

**Research Phase Complete** - Ready for Phase 1 (Design & Contracts)
