# Quickstart: Fix Backtesting Issues

**Feature**: 003-fix-backtesting
**Status**: Implementation Ready
**Date**: 2026-02-03

## Overview

This guide helps developers implement fixes to the backtesting engine for accurate progress tracking, equity curve persistence, trade-level PnL, and reliable state management.

## Prerequisites

- Elixir 1.17+ (OTP 27+) installed
- PostgreSQL database running
- Existing backtesting engine code (lib/trading_strategy/backtesting/)
- Familiarity with GenServer, ETS, and Ecto

## Implementation Phases

### Phase 1: Database Migrations (30 min)

**Goal**: Add database columns for equity curves, trade PnL, and enhanced metadata

```bash
# 1. Generate migrations
mix ecto.gen.migration add_pnl_and_duration_to_trades
mix ecto.gen.migration add_equity_curve_to_performance_metrics
mix ecto.gen.migration enhance_trading_session_metadata

# 2. Edit migrations (see data-model.md for schema details)

# 3. Run migrations
mix ecto.migrate

# 4. Verify migrations
mix ecto.migrations

# 5. Test rollback (in development)
mix ecto.rollback --step 3
mix ecto.migrate
```

**Files Modified**:
- `priv/repo/migrations/YYYYMMDDHHMMSS_add_pnl_and_duration_to_trades.exs`
- `priv/repo/migrations/YYYYMMDDHHMMSS_add_equity_curve_to_performance_metrics.exs`
- `priv/repo/migrations/YYYYMMDDHHMMSS_enhance_trading_session_metadata.exs`

**Success Criteria**:
- [ ] Migrations run without errors
- [ ] New columns exist in database (check with `\d trades`, `\d performance_metrics` in psql)
- [ ] Rollback/migrate cycle works cleanly

---

### Phase 2: Progress Tracker Implementation (45 min)

**Goal**: Create GenServer-based progress tracker with ETS for fast lookups

```bash
# 1. Create progress tracker module
touch lib/trading_strategy/backtesting/progress_tracker.ex

# 2. Add to supervision tree
# Edit lib/trading_strategy/application.ex
```

**Implementation Steps**:

1. **Create ProgressTracker GenServer** (`lib/trading_strategy/backtesting/progress_tracker.ex`):
```elixir
defmodule TradingStrategy.Backtesting.ProgressTracker do
  use GenServer
  require Logger

  @table_name :backtest_progress
  @cleanup_interval 60_000  # 1 minute

  # Client API

  def start_link(_opts) do
    GenServer.start_link(__MODULE__, :ok, name: __MODULE__)
  end

  def track(session_id, total_bars) do
    GenServer.cast(__MODULE__, {:track, session_id, total_bars})
  end

  def update(session_id, bars_processed) do
    now = System.monotonic_time(:millisecond)
    :ets.update_element(@table_name, session_id, [
      {2, bars_processed},
      {4, now}
    ])
  end

  def get(session_id) do
    case :ets.lookup(@table_name, session_id) do
      [{^session_id, bars_processed, total_bars, updated_at}] ->
        percentage = if total_bars > 0, do: Float.round(bars_processed / total_bars * 100, 2), else: 0.0
        {:ok, %{
          bars_processed: bars_processed,
          total_bars: total_bars,
          percentage: percentage,
          updated_at: updated_at
        }}
      [] ->
        {:error, :not_found}
    end
  end

  def complete(session_id) do
    :ets.delete(@table_name, session_id)
  end

  # Server Callbacks

  def init(:ok) do
    :ets.new(@table_name, [:set, :public, :named_table, read_concurrency: true])
    schedule_cleanup()
    {:ok, %{}}
  end

  def handle_cast({:track, session_id, total_bars}, state) do
    now = System.monotonic_time(:millisecond)
    :ets.insert(@table_name, {session_id, 0, total_bars, now})
    {:noreply, state}
  end

  def handle_info(:cleanup, state) do
    now = System.monotonic_time(:millisecond)
    stale_threshold = now - 86_400_000  # 24 hours

    :ets.select_delete(@table_name, [
      {
        {:"$1", :"$2", :"$3", :"$4"},
        [{:<, :"$4", stale_threshold}],
        [true]
      }
    ])

    schedule_cleanup()
    {:noreply, state}
  end

  defp schedule_cleanup do
    Process.send_after(self(), :cleanup, @cleanup_interval)
  end
end
```

2. **Add to Supervision Tree** (edit `lib/trading_strategy/application.ex`):
```elixir
def start(_type, _args) do
  children = [
    TradingStrategy.Repo,
    TradingStrategyWeb.Telemetry,
    {Phoenix.PubSub, name: TradingStrategy.PubSub},
    TradingStrategyWeb.Endpoint,

    # ADD THIS LINE
    TradingStrategy.Backtesting.ProgressTracker
  ]

  opts = [strategy: :one_for_one, name: TradingStrategy.Supervisor]
  Supervisor.start_link(children, opts)
end
```

3. **Update Engine to Report Progress** (edit `lib/trading_strategy/backtesting/engine.ex`):
```elixir
# At start of run_backtest/2:
defp execute_backtest_loop(bars, state, session_id) do
  total_bars = length(bars)

  # Initialize progress tracking
  ProgressTracker.track(session_id, total_bars)

  bars
  |> Enum.with_index(1)
  |> Enum.reduce(state, fn {bar, index}, acc ->
    # Update progress every 100 bars or 1% (whichever is less frequent)
    if rem(index, max(div(total_bars, 100), 100)) == 0 do
      ProgressTracker.update(session_id, index)
    end

    process_bar(bar, acc)
  end)
end

# At end of run_backtest/2, after finalize:
ProgressTracker.complete(session_id)
```

**Files Modified**:
- `lib/trading_strategy/backtesting/progress_tracker.ex` (new)
- `lib/trading_strategy/application.ex`
- `lib/trading_strategy/backtesting/engine.ex`

**Testing**:
```elixir
# test/trading_strategy/backtesting/progress_tracker_test.exs
defmodule TradingStrategy.Backtesting.ProgressTrackerTest do
  use ExUnit.Case, async: true

  alias TradingStrategy.Backtesting.ProgressTracker

  setup do
    session_id = Ecto.UUID.generate()
    {:ok, session_id: session_id}
  end

  test "tracks progress accurately", %{session_id: session_id} do
    ProgressTracker.track(session_id, 1000)

    assert {:ok, progress} = ProgressTracker.get(session_id)
    assert progress.bars_processed == 0
    assert progress.total_bars == 1000
    assert progress.percentage == 0.0

    ProgressTracker.update(session_id, 500)

    assert {:ok, progress} = ProgressTracker.get(session_id)
    assert progress.bars_processed == 500
    assert progress.percentage == 50.0
  end

  test "returns error for unknown session", %{session_id: session_id} do
    assert {:error, :not_found} = ProgressTracker.get(session_id)
  end
end
```

**Success Criteria**:
- [ ] ProgressTracker GenServer starts without errors
- [ ] ETS table `:backtest_progress` created
- [ ] Unit tests pass
- [ ] Manual backtest shows real-time progress updates (not placeholder 50%)

---

### Phase 3: Equity Curve Persistence (30 min)

**Goal**: Store sampled equity curve in PerformanceMetrics table

**Implementation Steps**:

1. **Update PerformanceMetrics Schema** (`lib/trading_strategy/backtesting/performance_metrics.ex`):
```elixir
schema "performance_metrics" do
  # ... existing fields ...

  field :equity_curve, {:array, :map}  # NEW
  field :equity_curve_metadata, :map   # NEW

  # ...
end

def changeset(metrics, attrs) do
  metrics
  |> cast(attrs, [
    # ... existing fields ...,
    :equity_curve,
    :equity_curve_metadata
  ])
  |> validate_equity_curve()
end

defp validate_equity_curve(changeset) do
  curve = get_field(changeset, :equity_curve)

  if curve && length(curve) > 1000 do
    add_error(changeset, :equity_curve, "cannot exceed 1000 points")
  else
    changeset
  end
end
```

2. **Update Engine to Save Equity Curve** (`lib/trading_strategy/backtesting/engine.ex`):
```elixir
def finalize_backtest(state, session) do
  # ... existing code ...

  # Generate and sample equity curve
  equity_curve = EquityCurve.generate(state.equity_history)
  sampled_curve = EquityCurve.sample(equity_curve, 1000)

  # Convert to JSON-compatible format
  json_curve = Enum.map(sampled_curve, fn {timestamp, value} ->
    %{
      "timestamp" => DateTime.to_iso8601(timestamp),
      "value" => Decimal.to_float(value)
    }
  end)

  metrics = MetricsCalculator.calculate_metrics(
    state.trades,
    state.equity_history,
    session.initial_capital
  )

  # Add equity curve to metrics
  metrics_with_curve = Map.merge(metrics, %{
    equity_curve: json_curve,
    equity_curve_metadata: %{
      sampled: true,
      sample_rate: 100,
      original_length: length(state.equity_history),
      trade_points_included: length(state.trades) * 2  # entry + exit
    }
  })

  {:ok, metrics_with_curve}
end
```

3. **Update Backtesting Context** (`lib/trading_strategy/backtesting.ex`):
```elixir
defp save_backtest_results(session_id, results) do
  # ... existing code to save trades, signals ...

  # Create or update PerformanceMetrics with equity curve
  metrics_attrs = %{
    trading_session_id: session_id,
    total_return: results.metrics.total_return,
    # ... other metrics ...,
    equity_curve: results.metrics.equity_curve,
    equity_curve_metadata: results.metrics.equity_curve_metadata
  }

  %PerformanceMetrics{}
  |> PerformanceMetrics.changeset(metrics_attrs)
  |> Repo.insert!()
end

def get_backtest_result(backtest_id) do
  # ... existing code ...

  # Include equity curve in results
  %{
    backtest_id: session.id,
    strategy_id: session.strategy_id,
    config: session.config,
    performance_metrics: metrics,
    trades: trades,
    equity_curve: metrics.equity_curve,  # NOW POPULATED
    started_at: session.started_at,
    completed_at: session.ended_at
  }
end
```

**Files Modified**:
- `lib/trading_strategy/backtesting/performance_metrics.ex`
- `lib/trading_strategy/backtesting/engine.ex`
- `lib/trading_strategy/backtesting.ex`

**Testing**:
```bash
# Run a backtest and verify equity curve is saved
iex -S mix

iex> {:ok, backtest_id} = TradingStrategy.Backtesting.start_backtest(config)
iex> # Wait for completion...
iex> {:ok, result} = TradingStrategy.Backtesting.get_backtest_result(backtest_id)
iex> length(result.equity_curve)  # Should be <= 1000
iex> hd(result.equity_curve)      # Should have "timestamp" and "value" keys
```

**Success Criteria**:
- [ ] Equity curve saved to database
- [ ] Curve is sampled to max 1000 points
- [ ] Format is JSON-compatible (ISO8601 timestamp strings, numeric values)
- [ ] Equity curve returned in API response

---

### Phase 4: Trade PnL & Duration (45 min)

**Goal**: Calculate and store trade-level PnL and duration

**Implementation Steps**:

1. **Update Trade Schema** (`lib/trading_strategy/orders/trade.ex`):
```elixir
schema "trades" do
  # ... existing fields ...

  field :pnl, :decimal                 # NEW
  field :duration_seconds, :integer    # NEW
  field :entry_price, :decimal         # NEW
  field :exit_price, :decimal          # NEW

  # ...
end

def changeset(trade, attrs) do
  trade
  |> cast(attrs, [
    # ... existing ...,
    :pnl,
    :duration_seconds,
    :entry_price,
    :exit_price
  ])
  |> validate_pnl_for_exit_trades()
end

defp validate_pnl_for_exit_trades(changeset) do
  side = get_field(changeset, :side)
  pnl = get_field(changeset, :pnl)

  # For exit trades, PnL must be present
  if side in [:sell] and is_nil(pnl) do
    add_error(changeset, :pnl, "required for exit trades")
  else
    changeset
  end
end
```

2. **Update PositionManager to Calculate Trade PnL** (`lib/trading_strategy/backtesting/position_manager.ex`):
```elixir
def close_position(state, position_id, bar, signal_id) do
  position = get_position(state, position_id)

  # Calculate realized PnL
  direction = if position.side == :long, do: 1, else: -1
  gross_pnl = Decimal.mult(
    Decimal.sub(bar.close, position.entry_price),
    Decimal.mult(position.quantity, direction)
  )

  # Calculate exit trade attributes
  entry_time = position.opened_at
  exit_time = bar.timestamp
  duration_seconds = DateTime.diff(exit_time, entry_time, :second)

  # Net PnL after fees (fees already included in position)
  net_pnl = Decimal.sub(gross_pnl, position.fees)

  # Create exit trade with PnL
  exit_trade = %{
    position_id: position_id,
    signal_id: signal_id,
    side: if(position.side == :long, do: :sell, else: :buy),
    quantity: position.quantity,
    price: bar.close,
    timestamp: bar.timestamp,
    pnl: net_pnl,                     # NEW
    duration_seconds: duration_seconds, # NEW
    entry_price: position.entry_price,  # NEW
    exit_price: bar.close               # NEW
  }

  {:ok, exit_trade, updated_state}
end
```

3. **Update SimulatedExecutor** (`lib/trading_strategy/backtesting/simulated_executor.ex`):
```elixir
def execute_order(order, bar, config, position_manager_state, position_id) do
  # ... existing slippage/commission calculation ...

  # For entry trades, PnL is 0 (no realized gain yet)
  # For exit trades, PnL calculated in PositionManager.close_position

  trade = %{
    position_id: position_id,
    side: order.side,
    quantity: net_quantity,
    price: executed_price,
    fee: total_fees,
    timestamp: bar.timestamp,
    pnl: Decimal.new(0),  # Entry trades have 0 PnL
    entry_price: nil,
    exit_price: nil,
    duration_seconds: nil
  }

  {:ok, trade}
end
```

4. **Update Backtesting Context** (`lib/trading_strategy/backtesting.ex`):
```elixir
defp get_backtest_result(session_id) do
  # ... load trades from database ...

  # Trades now have PnL populated from database
  trades = Enum.map(db_trades, fn trade ->
    %{
      timestamp: trade.timestamp,
      side: trade.side,
      price: trade.price,
      quantity: trade.quantity,
      fees: trade.fee,
      pnl: trade.pnl,                    # NOW POPULATED (was Decimal.new("0"))
      duration_seconds: trade.duration_seconds,  # NEW
      entry_price: trade.entry_price,    # NEW
      exit_price: trade.exit_price,      # NEW
      signal_type: # ... existing logic ...
    }
  end)

  # ...
end
```

**Files Modified**:
- `lib/trading_strategy/orders/trade.ex`
- `lib/trading_strategy/backtesting/position_manager.ex`
- `lib/trading_strategy/backtesting/simulated_executor.ex`
- `lib/trading_strategy/backtesting.ex`

**Testing**:
```elixir
# test/trading_strategy/backtesting/trade_pnl_test.exs
defmodule TradingStrategy.Backtesting.TradePnlTest do
  use TradingStrategy.DataCase

  test "exit trade has accurate PnL" do
    # Setup: Create position with entry trade
    position = insert(:position,
      entry_price: Decimal.new("50000"),
      quantity: Decimal.new("0.1"),
      side: :long
    )

    # Close position at higher price
    exit_bar = %{close: Decimal.new("51000"), timestamp: DateTime.utc_now()}

    {:ok, exit_trade, _state} = PositionManager.close_position(
      state,
      position.id,
      exit_bar,
      signal_id
    )

    # Verify PnL calculation
    expected_pnl = Decimal.new("100.00")  # (51000 - 50000) * 0.1 = 100
    assert Decimal.eq?(exit_trade.pnl, expected_pnl)

    # Verify duration
    assert is_integer(exit_trade.duration_seconds)
    assert exit_trade.duration_seconds > 0
  end
end
```

**Success Criteria**:
- [ ] Trade PnL accurately calculated for long and short positions
- [ ] Duration stored in seconds
- [ ] Entry/exit prices stored for verification
- [ ] Unit tests pass
- [ ] Position PnL equals sum of trade PnLs (consistency check)

---

### Phase 5: Concurrency Management (60 min)

**Goal**: Enforce concurrent backtest limit with queueing

**Implementation Steps** (see research.md for detailed code):

1. Create `ConcurrencyManager` GenServer
2. Add to supervision tree
3. Update `Backtesting.start_backtest/1` to request slot before execution
4. Update `Backtesting.finalize/cancel` to release slot
5. Implement queue status in `TradingSession.metadata`

**Files Created**:
- `lib/trading_strategy/backtesting/concurrency_manager.ex`

**Files Modified**:
- `lib/trading_strategy/application.ex`
- `lib/trading_strategy/backtesting.ex`

**Success Criteria**:
- [ ] Only 5 (configurable) backtests run concurrently
- [ ] Excess requests are queued
- [ ] Queued backtests start automatically when slots available
- [ ] Queue position visible in progress endpoint

---

### Phase 6: State Persistence & Restart Handling (60 min)

**Goal**: Detect interrupted backtests and mark as failed on restart

**Implementation Steps**:

1. **Enable Backtesting Supervisor** (`lib/trading_strategy/backtesting/supervisor.ex`):
```elixir
defmodule TradingStrategy.Backtesting.Supervisor do
  use DynamicSupervisor

  def start_link(init_arg) do
    DynamicSupervisor.start_link(__MODULE__, init_arg, name: __MODULE__)
  end

  def init(_init_arg) do
    DynamicSupervisor.init(strategy: :one_for_one)
  end

  def start_backtest_task(session_id, config) do
    task_spec = %{
      id: {BacktestTask, session_id},
      start: {Task, :start_link, [fn ->
        Engine.run_backtest(config, session_id)
      end]},
      restart: :temporary
    }

    DynamicSupervisor.start_child(__MODULE__, task_spec)
  end
end
```

2. **Add Restart Detection** (in `lib/trading_strategy/application.ex` start/2):
```elixir
def start(_type, _args) do
  children = [
    # ... existing children ...,
    {DynamicSupervisor, name: TradingStrategy.Backtesting.Supervisor, strategy: :one_for_one}
  ]

  # After supervisor starts, check for stale running sessions
  Task.start(fn ->
    Process.sleep(1000)  # Wait for app to initialize
    handle_stale_sessions()
  end)

  Supervisor.start_link(children, opts)
end

defp handle_stale_sessions do
  # Find sessions that were "running" but app restarted
  cutoff = DateTime.add(DateTime.utc_now(), -5, :minute)

  from(s in TradingSession,
    where: s.status == "running" and s.updated_at < ^cutoff
  )
  |> Repo.all()
  |> Enum.each(fn session ->
    Logger.warning("Marking interrupted backtest as failed: #{session.id}")

    Backtesting.mark_as_failed(session.id, %{
      error_type: "application_restart",
      error_message: "Backtest interrupted by application restart",
      partial_data_saved: true
    })
  end)
end
```

**Files Modified**:
- `lib/trading_strategy/backtesting/supervisor.ex`
- `lib/trading_strategy/application.ex`
- `lib/trading_strategy/backtesting.ex` (add `mark_as_failed/2`)

**Success Criteria**:
- [ ] Running backtests marked as "error" after restart
- [ ] Partial results preserved
- [ ] Supervisor logs show task failures

---

### Phase 7: Comprehensive Testing (90 min)

**Goal**: Achieve >80% test coverage with edge case handling

**Test Files to Create**:
```bash
test/trading_strategy/backtesting/
├── progress_tracker_test.exs  (created in Phase 2)
├── equity_curve_persistence_test.exs
├── trade_pnl_test.exs  (created in Phase 4)
├── concurrency_manager_test.exs
├── restart_handling_test.exs
└── integration/
    └── full_backtest_flow_test.exs
```

**Key Tests**:
- Zero trades backtest (flat equity curve, null metrics)
- Insufficient data validation
- Concurrent limit enforcement
- Restart detection
- PnL accuracy (long/short positions)
- Equity curve sampling

**Run Coverage**:
```bash
mix test --cover
open cover/excoveralls.html
```

**Success Criteria**:
- [ ] Overall coverage >80%
- [ ] All edge cases from spec tested
- [ ] Integration test passes end-to-end

---

## Validation Checklist

Before marking implementation complete, verify:

- [ ] **FR-001**: Progress tracking accurate within 5%
- [ ] **FR-002**: Equity curves generated with trade points + sampled bars
- [ ] **FR-003**: All config params stored in TradingSession
- [ ] **FR-004**: Trade PnL calculated and stored
- [ ] **FR-005**: Trade duration calculated
- [ ] **FR-006**: Interrupted backtests marked as failed on restart
- [ ] **FR-011**: O(n²) complexity fixed (Map-based indexing)
- [ ] **FR-012**: Equity curve returned in results
- [ ] **FR-016**: Concurrent limit enforced with queueing
- [ ] **SC-005**: Test coverage >80%

## Troubleshooting

### Progress stuck at placeholder 50%
- Check ProgressTracker is in supervision tree
- Verify ETS table exists: `:ets.info(:backtest_progress)`
- Ensure Engine calls `ProgressTracker.update/2` in loop

### Equity curve empty in results
- Check PerformanceMetrics schema includes `equity_curve` field
- Verify migration ran successfully
- Ensure `Engine.finalize_backtest/2` saves curve to metrics
- Check `Backtesting.get_backtest_result/1` includes `equity_curve` in map

### Trade PnL is zero
- Verify `PositionManager.close_position/3` calculates PnL
- Check exit trades have `pnl` field populated
- Ensure migrations added `pnl` column to trades table

### Backtests not queued when limit reached
- Check ConcurrencyManager is started
- Verify `Backtesting.start_backtest/1` calls `ConcurrencyManager.request_slot/1`
- Check queue depth: `GenServer.call(ConcurrencyManager, :status)`

## Next Steps

After implementation:

1. Run full test suite: `mix test`
2. Run manual integration test with real strategy
3. Benchmark performance with 50K+ bar dataset
4. Update CLAUDE.md with any new patterns learned
5. Create PR with reference to this quickstart

## Reference Documents

- Feature Spec: `specs/003-fix-backtesting/spec.md`
- Data Model: `specs/003-fix-backtesting/data-model.md`
- Research: `specs/003-fix-backtesting/research.md`
- API Contracts: `specs/003-fix-backtesting/contracts/backtest_api.yaml`
- Constitution: `.specify/memory/constitution.md`
