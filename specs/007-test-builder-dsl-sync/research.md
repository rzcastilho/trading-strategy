# Research: Comprehensive Testing for Strategy Editor Synchronization

**Feature**: 007-test-builder-dsl-sync
**Date**: 2026-02-11
**Status**: Complete

## Overview

This document consolidates research findings for implementing a comprehensive test suite (50+ scenarios) to validate the bidirectional synchronization between the visual strategy builder and DSL editor from Feature 005. Research covered four key technical areas: LiveView testing with Wallaby, performance testing in ExUnit, test fixture management, and deterministic testing practices.

---

## 1. Wallaby & LiveView Testing Best Practices

### Decision: Hybrid Testing Approach (LiveViewTest + Wallaby)

**Rationale**:
- **Phoenix.LiveViewTest** (80% of tests): Faster execution (no browser overhead), deterministic by design, direct LiveView state access
- **Wallaby** (20% of tests): Required for JavaScript hooks (CodeMirror), visual feedback validation, real browser behavior

**Key Patterns**:

#### Pattern 1: LiveViewTest for Synchronization Logic
```elixir
test "builder-to-DSL sync within 500ms", %{conn: conn} do
  {:ok, view, _html} = live(conn, ~p"/strategies/new/editor")

  {time_micros, _result} = :timer.tc(fn ->
    view
    |> form("#indicator-builder-form", indicator: %{type: "sma", period: 20})
    |> render_submit()
  end)

  time_ms = time_micros / 1000

  # Assert synchronization happened
  dsl_content = view |> element("#dsl-editor") |> render()
  assert dsl_content =~ "indicator :sma_20, :sma, period: 20"

  # Assert performance target (FR-001)
  assert time_ms < 500
end
```

#### Pattern 2: Wallaby for Visual Feedback
```elixir
@tag :wallaby
test "changed lines highlighted in DSL editor", %{session: session} do
  session
  |> visit("/strategies/new/editor")
  |> click(button("Add Indicator"))

  # Wait for synchronization with built-in retry
  session
  |> assert_has(css("#dsl-editor .line-changed", count: 1))
  |> assert_has(css("#dsl-editor[data-scrolled='true']"))
end
```

#### Pattern 3: Debouncing Tests
```elixir
test "300ms debounce prevents excessive sync events", %{conn: conn} do
  {:ok, view, _html} = live(conn, ~p"/strategies/new/editor")

  # Simulate rapid typing (5 changes)
  for dsl_text <- dsl_changes do
    view |> element("#dsl-editor-textarea") |> render_hook("dsl_change", %{"value" => dsl_text})
  end

  # Wait for debounce period + processing time
  Process.sleep(350)  # 300ms debounce + 50ms buffer
  render(view)

  # With 300ms debounce, only 1-2 syncs should occur (not 5)
  assert sync_count <= 2
end
```

#### Pattern 4: Undo/Redo Testing
```elixir
test "undo operation completes within 50ms", %{conn: conn} do
  {:ok, view, _html} = live(conn, ~p"/strategies/#{strategy}/edit")

  # Make changes
  view |> add_indicator("sma_20")
  view |> add_indicator("ema_50")

  # Measure undo latency
  {time_micros, _result} = :timer.tc(fn ->
    view |> render_hook("keyboard_shortcut", %{"key" => "z", "ctrlKey" => true})
  end)

  time_ms = time_micros / 1000
  assert time_ms < 50
end
```

**Alternatives Considered**:
- Pure Wallaby: Too slow (2-3 seconds per test vs 50-200ms), harder to debug
- Pure LiveViewTest: Cannot test JavaScript hooks or visual feedback
- Manual testing: Not sustainable for 50+ scenarios

---

## 2. Performance Testing in ExUnit

### Decision: `:timer.tc/1` for Assertions + Percentile Calculations + Telemetry for Observability

**Rationale**:
- `:timer.tc/1` is standard Erlang approach with minimal overhead (~1μs)
- Already used successfully in codebase (`sync_benchmark_test.exs`, `indicator_metadata_benchmark_test.exs`)
- Statistical approach (P95 instead of max) handles GC pauses and OS scheduling

**Key Patterns**:

#### Pattern 1: Single Operation Timing
```elixir
test "DSL-to-builder sync within 500ms", %{conn: conn} do
  {time_us, {:ok, result}} = :timer.tc(fn ->
    Synchronizer.dsl_to_builder(@twenty_indicator_strategy)
  end)

  time_ms = time_us / 1000
  assert time_ms < 500, "Sync took #{time_ms}ms, expected < 500ms"
end
```

#### Pattern 2: P95 Percentile Validation (SC-003)
```elixir
test "95% of sync operations complete within 500ms" do
  samples = 100

  times = for _ <- 1..samples do
    {time_us, _result} = :timer.tc(&operation/0)
    time_us / 1000
  end

  sorted = Enum.sort(times)
  p95 = Enum.at(sorted, 94)  # 95th percentile

  # Assert on P95, not max - handles GC spikes
  assert p95 < 500, "P95 latency #{p95}ms exceeds 500ms"
end
```

#### Pattern 3: Statistics Calculation
```elixir
test "performance statistics for analysis" do
  times = collect_timings(100)

  mean = Enum.sum(times) / length(times)
  median = Enum.at(Enum.sort(times), 50)
  p95 = Enum.at(Enum.sort(times), 94)

  IO.puts("\n=== Performance Report ===")
  IO.puts("Mean: #{Float.round(mean, 2)}ms")
  IO.puts("Median: #{Float.round(median, 2)}ms")
  IO.puts("P95: #{Float.round(p95, 2)}ms")
  IO.puts("Target: <500ms")

  assert p95 < 500
end
```

#### Pattern 4: Test Organization
```elixir
# Separate benchmark tests with tags
@tag :benchmark
test "20-indicator strategy performance" do
  # benchmark code
end

# Configuration in test_helper.exs
ExUnit.configure(exclude: :benchmark)  # Exclude by default

# Run: mix test --only benchmark
```

**Performance Targets**:
- **SC-003**: 95%+ of sync operations < 500ms (use P95 percentile)
- **SC-005**: 100% of undo/redo < 50ms (use max time, stricter requirement)

**Alternatives Considered**:
- Benchee: Better for deep analysis but adds complexity
- System.monotonic_time: More verbose than `:timer.tc`
- No performance tests: Would miss regressions

---

## 3. Test Fixture Management

### Decision: Hybrid Approach - `.ex` Modules for Builders + `.exs` Files for Large Static Data

**Rationale**:
- `.ex` files (compiled modules) best for reusable fixture functions
- `.exs` files (scripts) better for large static data (50 indicators, 1000+ lines DSL)
- Matches Phoenix conventions (`test/support/fixtures/*_fixtures.ex`)

**Directory Structure**:
```
test/
├── support/
│   ├── fixtures/
│   │   ├── strategy_fixtures.ex           # Main builder functions
│   │   └── data/                          # Static .exs data files
│   │       ├── simple/                    # 1-2 indicators
│   │       │   ├── rsi_strategy.exs
│   │       │   └── sma_strategy.exs
│   │       ├── medium/                    # 5-10 indicators
│   │       │   ├── multi_indicator.exs
│   │       │   └── trend_following.exs
│   │       ├── complex/                   # 20-30 indicators
│   │       │   └── advanced_strategy.exs
│   │       └── large/                     # 50+ indicators
│   │           ├── performance_test_1.exs
│   │           └── performance_test_2.exs
```

**Key Patterns**:

#### Pattern 1: Composable Fixture Builders
```elixir
defmodule TradingStrategy.StrategyFixtures do
  # Base builder with defaults
  def base_strategy(overrides \\ %{}) do
    defaults = %BuilderState{
      name: "Test Strategy",
      indicators: [],
      # ... defaults
    }
    struct!(defaults, overrides)
  end

  # Composable component builders
  def rsi_indicator(name \\ "rsi_14", period \\ 14) do
    %Indicator{type: "rsi", name: name, parameters: %{"period" => period}}
  end

  # Complexity-specific strategies
  def simple_rsi_strategy do
    base_strategy(%{
      name: "Simple RSI",
      indicators: [rsi_indicator()],
      entry_conditions: "rsi_14 < 30"
    })
  end

  # Parameterized builders
  def strategy_with_n_indicators(n) do
    base_strategy(%{indicators: sma_indicators(n)})
  end

  # Load large fixtures from .exs
  def large_performance_test_1 do
    Path.join([__DIR__, "data", "large", "performance_test_1.exs"])
    |> Code.eval_file()
    |> elem(0)
  end
end
```

#### Pattern 2: Naming Convention
```elixir
# Format: {complexity}_{domain}_{variant?}

simple_rsi_strategy()                   # Simple: 1 indicator
simple_sma_crossover()                  # Simple: 2 indicators
medium_multi_indicator()                # Medium: 5-10 indicators
complex_adaptive_strategy()             # Complex: 20+ indicators
large_performance_test_1()              # Large: 50+ indicators, 1000+ lines
```

#### Pattern 3: Fixture Validation
```elixir
defp validate_fixture(%BuilderState{} = state) do
  cond do
    is_nil(state.name) -> {:error, "name required"}
    not is_list(state.indicators) -> {:error, "indicators must be list"}
    true -> :ok
  end
end

# Validate on load
def large_strategy do
  data = load_fixture_data("large_strategy.exs")

  case validate_fixture(data) do
    :ok -> data
    {:error, reason} -> raise "Invalid fixture: #{reason}"
  end
end
```

#### Pattern 4: Usage in Tests
```elixir
defmodule SynchronizerTest do
  use ExUnit.Case, async: true
  import TradingStrategy.StrategyFixtures

  test "converts simple RSI strategy" do
    builder_state = simple_rsi_strategy()
    assert {:ok, dsl_text} = Synchronizer.builder_to_dsl(builder_state)
  end

  @tag :performance
  test "handles 1000+ line DSL" do
    builder_state = large_performance_test_1()
    {time_us, {:ok, _}} = :timer.tc(fn -> Synchronizer.builder_to_dsl(builder_state) end)
    assert time_us < 500_000
  end
end
```

**Alternatives Considered**:
- Pure `.exs` with ExUnitFixtures library: Requires additional dependency
- Pure `.ex` with inline data: Large datasets slow compilation
- Database-backed fixtures: Adds unnecessary complexity for read-only test data

---

## 4. Deterministic Testing (0% Flakiness)

### Decision: Multi-Layered Defense-in-Depth Approach

**Rationale**:
- Flakiness comes from non-deterministic behavior (race conditions, shared state, timing dependencies)
- Eliminate sources of randomness through design, not retries
- SC-011 requires 0% flakiness rate over 10 consecutive runs

**Key Patterns**:

#### Pattern 1: Race Condition Prevention with render_async
```elixir
test "async operation completes", %{conn: conn} do
  {:ok, view, _html} = live(conn, ~p"/strategies")
  view |> element("button#load-data") |> render_click()

  # ✅ Wait for async operations to complete
  render_async(view)

  assert render(view) =~ "Data loaded"
end
```

**Rationale**: LiveView's FIFO message queue ensures `render_async/2` waits for all `assign_async`, `start_async` tasks.

#### Pattern 2: Test Isolation with Unique Session IDs
```elixir
defmodule EditHistoryTest do
  use ExUnit.Case, async: true  # ✅ Can run async now

  setup do
    # Each test gets unique IDs - no collision
    session_id = Ecto.UUID.generate()
    user_id = Ecto.UUID.generate()

    {:ok, ^session_id} = EditHistory.start_session(strategy_id, user_id)

    on_exit(fn -> EditHistory.end_session(session_id) end)

    {:ok, session_id: session_id, user_id: user_id}
  end
end
```

**Rationale**: Session-based isolation allows parallel test execution without shared state interference.

#### Pattern 3: Database Isolation with Ecto Sandbox
```elixir
# test/test_helper.exs
Ecto.Adapters.SQL.Sandbox.mode(TradingStrategy.Repo, :manual)

# In test module
use TradingStrategyWeb.ConnCase, async: true
# ConnCase automatically handles Sandbox.checkout/1
# Each test gets isolated database transaction
```

#### Pattern 4: Wallaby Implicit Waits (Not Manual Sleeps)
```elixir
# ❌ FLAKY - manual sleep
session
|> click(button("Add Indicator"))
|> (&Process.sleep(1000)).()
|> assert_has(css(".indicator-card"))

# ✅ DETERMINISTIC - declarative query with retry
session
|> click(button("Add Indicator"))
|> assert_has(css(".indicator-card"))  # Polls until present
```

**Rationale**: Wallaby's `assert_has` retries for up to `max_wait_time` (default 5s), succeeding as soon as element appears.

#### Pattern 5: Explicit Debounce Waits
```elixir
@debounce_ms 300

test "debounced input synchronizes", %{conn: conn} do
  {:ok, view, _html} = live(conn, ~p"/strategies/new")

  view |> element("#dsl-editor") |> render_change(%{"value" => "new DSL"})

  # ✅ Explicit wait for client-side debounce timer
  :timer.sleep(@debounce_ms + 50)
  render(view)

  assert render(view) =~ "new DSL"
end
```

**Rationale**: Debouncing is a client-side timer that cannot be introspected - must wait explicitly.

#### Pattern 6: GenServer Database Access Allowance
```elixir
setup do
  :ok = Ecto.Adapters.SQL.Sandbox.checkout(TradingStrategy.Repo)

  # Allow EditHistory GenServer to access this test's DB connection
  Ecto.Adapters.SQL.Sandbox.allow(
    TradingStrategy.Repo,
    self(),
    Process.whereis(TradingStrategy.StrategyEditor.EditHistory)
  )

  # ... rest of setup
end
```

#### Pattern 7: Sequential Execution for Benchmarks Only
```elixir
# Regular tests: async: true
defmodule SynchronizerTest do
  use ExUnit.Case, async: true
end

# Benchmark tests: async: false (avoid resource contention)
defmodule SyncBenchmarkTest do
  use ExUnit.Case, async: false

  @tag :benchmark
  test "performance under load" do
    # ...
  end
end
```

**Anti-Flakiness Checklist**:
- ✅ Use `render_async/2` for LiveView async operations
- ✅ Use Ecto Sandbox for database isolation
- ✅ Use Wallaby's `assert_has` implicit waits
- ✅ Generate unique IDs per test (`Ecto.UUID.generate()`)
- ✅ Use `on_exit/1` callbacks for cleanup
- ✅ Prefer `async: true` with isolated resources
- ✅ Use P95 percentile for performance (not max)
- ✅ No automatic retries - tests must be deterministic

**Flakiness Detection**:
```bash
# Run tests 10 times to verify 0% flakiness (SC-011)
for i in {1..10}; do
  echo "Run $i/10..."
  mix test test/trading_strategy_web/live/strategy_editor_live/ || exit 1
done
echo "✅ 0% flakiness achieved!"
```

**Alternatives Considered**:
- Retry libraries: Mask underlying flakiness instead of fixing root cause
- `async: false` everywhere: Slow test suite, doesn't eliminate race conditions
- Manual timeout management: Wallaby's built-in retry is more robust

---

## Technology Decisions Summary

| Area | Decision | Rationale |
|------|----------|-----------|
| **Test Framework** | ExUnit + Wallaby | Standard Phoenix stack, proven in codebase |
| **Test Organization** | By user story (US1-US6) | Clear mapping to requirements (FR-018) |
| **Performance Timing** | `:timer.tc/1` | Simple, accurate, minimal overhead |
| **Performance Metrics** | P95 percentile (SC-003), Max (SC-005) | Statistical approach handles variance |
| **Fixture Structure** | `.ex` modules + `.exs` data files | Compiled helpers + static data separation |
| **Fixture Organization** | By complexity (simple/medium/complex/large) | Progressive testing, easy navigation |
| **Test Data** | Version-controlled code fixtures | Reproducible, reviewable, DRY (FR-019) |
| **Determinism** | Unique IDs + Ecto Sandbox + render_async | Session isolation + database isolation |
| **Wallaby Waits** | Declarative queries with implicit retry | Robust timing, no manual sleeps |
| **Debouncing** | Explicit `sleep(debounce_ms + buffer)` | Client-side timers need explicit waits |
| **Test Reporting** | `IO.puts` with formatted tables | Human-readable console output (FR-017) |
| **Flakiness Prevention** | Multi-layered defense-in-depth | 0% flakiness requirement (SC-011) |

---

## Implementation Recommendations

### Phase 1 Priorities:
1. Create test file structure (7 test files by user story)
2. Create fixture module with simple/medium/complex/large builders
3. Implement US1 (builder-to-DSL) and US2 (DSL-to-builder) tests first (P1)
4. Add performance benchmarks with `:timer.tc` and P95 validation
5. Validate 0% flakiness with 10-run script

### Phase 2 Priorities:
1. Implement US3 (comment preservation) and US4 (undo/redo) tests (P2)
2. Add large fixture data files for performance testing (50 indicators, 1000+ lines)
3. Implement US5 (performance validation) and US6 (error handling) tests (P3)
4. Add edge case tests (browser refresh, rapid switching, concurrent changes)

### Phase 3 Priorities:
1. Add console reporting formatter for test results (FR-017)
2. Document fixture usage and test patterns
3. Run flakiness detection (10x consecutive runs)
4. Optimize slow tests if needed (target <5 minutes total suite runtime)

---

## Open Questions (None - All Resolved via Clarifications)

All technical unknowns were resolved through:
- **Clarification Session 2026-02-11**: Test organization, reporting, edge cases, test data, retry strategy
- **Research**: Best practices for Wallaby/LiveView, performance testing, fixtures, deterministic testing

---

## References

### Wallaby & LiveView Testing:
- [Testing a Phoenix LiveView that does an async operation after mount](https://medium.com/elixir-learnings/testing-a-phoenix-liveview-that-does-an-async-operation-after-mount-b8ec27e6c167)
- [Starting Browser Testing for Phoenix LiveView with Wallaby](https://brittonbroderick.com/2022/03/20/starting-browser-testing-for-phoenix-liveview-with-wallaby/)
- [Phoenix.LiveViewTest Documentation](https://hexdocs.pm/phoenix_live_view/Phoenix.LiveViewTest.html)
- [Wallaby Documentation](https://hexdocs.pm/wallaby/Wallaby.html)

### Performance Testing:
- [Benchmark Your Elixir App's Performance with Benchee](https://blog.appsignal.com/2022/09/06/benchmark-your-elixir-apps-performance-with-benchee.html)
- [Elixir Telemetry: Metrics and Reporters](https://samuelmullen.com/articles/elixir-telemetry-metrics-and-reporters)

### Test Fixtures:
- [An Introduction to Test Factories and Fixtures for Elixir](https://blog.appsignal.com/2023/02/28/an-introduction-to-test-factories-and-fixtures-for-elixir.html)
- [Sharing fixtures between test modules in Elixir](https://medium.com/@ejpcmac/sharing-fixtures-between-test-modules-in-elixir-15add7c7cbd2)

### Deterministic Testing:
- [8 Common Causes of Flaky Tests in Elixir](https://blog.appsignal.com/2021/12/21/eight-common-causes-of-flaky-tests-in-elixir.html)
- [Understanding Test Concurrency In Elixir](https://dockyard.com/blog/2019/02/13/understanding-test-concurrency-in-elixir)
- [`async: false` is the worst](https://saltycrackers.dev/posts/bye-bye-async-false/)

---

**Status**: Research complete. All NEEDS CLARIFICATION items resolved. Ready for Phase 1: Design & Contracts.
