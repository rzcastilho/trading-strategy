# Data Model: Comprehensive Testing for Strategy Editor Synchronization

**Feature**: 007-test-builder-dsl-sync
**Date**: 2026-02-11
**Status**: Draft

## Overview

This document defines the data structures and entities used in the test suite for validating bidirectional synchronization between the visual strategy builder and DSL editor. Since this is a **testing-only feature**, the data model describes test artifacts and fixtures, not production domain entities.

---

## Core Entities

### 1. Test Scenario

**Purpose**: Represents a specific test case with preconditions, actions, expected outcomes, and pass/fail criteria.

**Structure**:
```elixir
# ExUnit test case (not a database entity)
test "US1.001: adding indicator in builder updates DSL within 500ms", %{conn: conn} do
  # Test metadata embedded in test name and tags
  # US1 = User Story 1 (Builder-to-DSL Sync)
  # .001 = Test number within story
end
```

**Attributes**:
- **Test ID**: Format `US{story}.{number}` (e.g., US1.001, US2.003)
- **User Story**: One of US1-US6 (mapped to priority P1-P3)
- **Description**: What is being tested (from acceptance scenario)
- **Preconditions**: Setup state (fixtures, user sessions)
- **Actions**: Test steps (form submissions, DSL edits, keyboard shortcuts)
- **Expected Outcomes**: Assertions (synchronization state, performance metrics)
- **Tags**: `@tag :integration`, `@tag :benchmark`, `@tag :wallaby`

**Organizational Mapping** (FR-018):
```
User Story 1 (P1) → synchronization_test.exs
User Story 2 (P1) → dsl_to_builder_sync_test.exs
User Story 3 (P2) → comment_preservation_test.exs
User Story 4 (P2) → undo_redo_test.exs
User Story 5 (P3) → performance_test.exs
User Story 6 (P3) → error_handling_test.exs
Cross-cutting     → edge_cases_test.exs
```

**Lifecycle**:
1. Test defined in test file
2. Test executed via `mix test`
3. Results captured by ExUnit formatter
4. Summary statistics reported to console (FR-017)

---

### 2. Strategy Configuration (Test Fixtures)

**Purpose**: Test data structures containing indicators, rules, and parameters used in test scenarios.

**Complexity Levels** (FR-019):
- **Simple**: 1-2 indicators, minimal DSL (~10-20 lines)
- **Medium**: 5-10 indicators, moderate complexity (~50-100 lines)
- **Complex**: 20-30 indicators, advanced logic (~200-400 lines)
- **Large**: 50+ indicators, stress test scenarios (1000+ lines)

**Structure**:
```elixir
# test/support/fixtures/strategy_fixtures.ex
defmodule TradingStrategy.StrategyFixtures do
  alias TradingStrategy.StrategyEditor.BuilderState

  @doc """
  Simple RSI strategy fixture (US1, US2 testing).

  Returns a BuilderState with:
  - 1 RSI indicator (period 14)
  - Simple entry/exit conditions
  - Default position sizing
  """
  def simple_rsi_strategy do
    %BuilderState{
      name: "Simple RSI Strategy",
      trading_pair: "BTC/USD",
      timeframe: "1h",
      indicators: [
        %BuilderState.Indicator{
          type: "rsi",
          name: "rsi_14",
          parameters: %{"period" => 14},
          _id: "ind-#{:erlang.unique_integer([:positive])}"
        }
      ],
      entry_conditions: "rsi_14 < 30",
      exit_conditions: "rsi_14 > 70",
      position_sizing: default_position_sizing(),
      _comments: [],
      _version: 1
    }
  end

  @doc """
  Large performance test fixture (US5 testing).

  Returns a BuilderState with:
  - 50 indicators (various types)
  - Complex entry/exit logic
  - Expected to generate 1000+ lines of DSL
  """
  def large_performance_test_1 do
    # Loaded from .exs file for maintainability
    load_fixture_data("large/performance_test_1.exs")
  end
end
```

**Attributes**:
- **Name**: Descriptive fixture name (e.g., "Simple RSI Strategy")
- **Complexity**: simple/medium/complex/large
- **Indicator Count**: Number of configured indicators (1 to 50+)
- **DSL Line Count**: Estimated lines of generated DSL
- **Comments**: Number of comment lines (for US3 comment preservation testing)
- **Valid/Invalid**: Whether fixture has valid syntax (for US6 error handling)

**Fixture Data Files** (`.exs` for large fixtures):
```
test/support/fixtures/data/
├── simple/
│   ├── rsi_strategy.exs           # 1 indicator, ~15 lines DSL
│   └── sma_crossover.exs          # 2 indicators, ~25 lines DSL
├── medium/
│   ├── multi_indicator.exs        # 5 indicators, ~80 lines DSL
│   └── trend_following.exs        # 8 indicators, ~120 lines DSL
├── complex/
│   └── adaptive_strategy.exs      # 20 indicators, ~350 lines DSL
└── large/
    ├── performance_test_1.exs     # 50 indicators, ~1000 lines DSL
    └── performance_test_2.exs     # 50 indicators, extensive comments
```

**Validation**:
```elixir
defp validate_fixture(%BuilderState{} = state) do
  cond do
    is_nil(state.name) or state.name == "" ->
      {:error, "name is required"}

    not is_list(state.indicators) ->
      {:error, "indicators must be a list"}

    Enum.any?(state.indicators, &(!is_struct(&1, BuilderState.Indicator))) ->
      {:error, "all indicators must be Indicator structs"}

    true ->
      :ok
  end
end
```

---

### 3. Synchronization Event

**Purpose**: A measurable event representing data transfer between builder and DSL, including latency metrics.

**Structure**:
```elixir
# Not a persistent entity - measured in tests via :timer.tc
{time_microseconds, result} = :timer.tc(fn ->
  Synchronizer.builder_to_dsl(builder_state, comments)
end)

sync_event = %{
  direction: :builder_to_dsl,  # or :dsl_to_builder
  latency_ms: time_microseconds / 1000,
  indicator_count: length(builder_state.indicators),
  dsl_line_count: String.split(result, "\n") |> length(),
  timestamp: System.monotonic_time(:millisecond),
  success: match?({:ok, _}, result)
}
```

**Attributes**:
- **Direction**: `:builder_to_dsl` or `:dsl_to_builder`
- **Latency (ms)**: Time taken for synchronization operation
- **Indicator Count**: Number of indicators in the strategy
- **DSL Line Count**: Number of lines in generated/parsed DSL
- **Timestamp**: Monotonic time for ordering events
- **Success**: Boolean indicating operation succeeded
- **Error**: Optional error message if synchronization failed

**Usage in Tests**:
```elixir
# US1.001: Builder-to-DSL synchronization
test "adding indicator updates DSL within 500ms" do
  {latency_ms, {:ok, dsl_text}} = measure_sync(fn ->
    Synchronizer.builder_to_dsl(builder_state, [])
  end)

  assert latency_ms < 500, "Sync took #{latency_ms}ms, expected < 500ms"
end

# US5.003: Multiple sync events for P95 calculation
test "95% of sync operations complete within 500ms" do
  sync_events = for _ <- 1..100 do
    measure_sync_event(&operation/0)
  end

  latencies = Enum.map(sync_events, & &1.latency_ms)
  p95 = Enum.at(Enum.sort(latencies), 94)

  assert p95 < 500
end
```

---

### 4. Performance Metric

**Purpose**: Measured values for synchronization latency, undo/redo response time, comment preservation rate, and error rates.

**Structure**:
```elixir
%{
  metric_type: :sync_latency,  # or :undo_redo_latency, :comment_preservation_rate
  samples: [245.3, 267.1, 423.8, ...],  # List of measurements
  statistics: %{
    mean: 312.5,
    median: 289.0,
    p95: 456.2,
    p99: 489.7,
    min: 198.4,
    max: 512.3,
    std_dev: 87.6
  },
  target: 500.0,  # Target value from success criteria
  pass: true,     # Whether metric meets target
  timestamp: ~U[2026-02-11 14:23:45Z]
}
```

**Metric Types**:

| Metric Type | Unit | Target | Success Criteria |
|-------------|------|--------|------------------|
| `sync_latency_builder_to_dsl` | milliseconds | < 500ms | SC-003: 95%+ within target |
| `sync_latency_dsl_to_builder` | milliseconds | < 500ms | SC-003: 95%+ within target |
| `undo_latency` | milliseconds | < 50ms | SC-005: 100% within target |
| `redo_latency` | milliseconds | < 50ms | SC-005: 100% within target |
| `comment_preservation_rate` | percentage | > 90% | SC-004: After 100 round-trips |
| `test_pass_rate` | percentage | 100% | SC-001, SC-002 |
| `flakiness_rate` | percentage | 0% | SC-011: Over 10 runs |

**Statistical Calculation**:
```elixir
def calculate_statistics(samples) do
  sorted = Enum.sort(samples)
  count = length(samples)

  %{
    mean: Enum.sum(samples) / count,
    median: Enum.at(sorted, div(count, 2)),
    p95: Enum.at(sorted, round(count * 0.95) - 1),
    p99: Enum.at(sorted, round(count * 0.99) - 1),
    min: Enum.min(samples),
    max: Enum.max(samples),
    std_dev: standard_deviation(samples)
  }
end
```

---

### 5. Test Report

**Purpose**: Console-formatted aggregated results from all test scenarios including pass/fail status, performance metrics, and identified issues.

**Structure** (FR-017):
```elixir
%{
  total_tests: 52,
  passed: 50,
  failed: 2,
  skipped: 0,
  execution_time_seconds: 287.4,

  # Grouped by user story
  results_by_story: %{
    "US1: Builder-to-DSL Sync" => %{total: 10, passed: 10, failed: 0},
    "US2: DSL-to-Builder Sync" => %{total: 10, passed: 10, failed: 0},
    "US3: Comment Preservation" => %{total: 8, passed: 7, failed: 1},
    "US4: Undo/Redo" => %{total: 8, passed: 8, failed: 0},
    "US5: Performance Validation" => %{total: 10, passed: 9, failed: 1},
    "US6: Error Handling" => %{total: 6, passed: 6, failed: 0}
  },

  # Performance metrics
  performance_summary: %{
    sync_latency_p95: 432.1,  # milliseconds
    undo_latency_max: 38.6,   # milliseconds
    comment_preservation_rate: 92.4  # percentage
  },

  # Failed test details
  failures: [
    %{
      test_id: "US3.005",
      test_name: "comments preserved after 100 round-trips",
      error: "Expected 90+ comments, got 87 (96.7% retention)",
      file: "test/trading_strategy_web/live/strategy_editor_live/comment_preservation_test.exs",
      line: 142
    },
    # ... more failures
  ]
}
```

**Console Output Format** (FR-017):
```
============================================================
Test Suite: Strategy Editor Synchronization
============================================================

Summary:
  Total Tests: 52
  Passed:      50 (96.2%)
  Failed:       2 (3.8%)
  Skipped:      0
  Duration:    287.4 seconds

Results by User Story:
  [P1] US1: Builder-to-DSL Sync         10/10 ✓
  [P1] US2: DSL-to-Builder Sync         10/10 ✓
  [P2] US3: Comment Preservation         7/8  ✗
  [P2] US4: Undo/Redo                    8/8  ✓
  [P3] US5: Performance Validation       9/10 ✗
  [P3] US6: Error Handling               6/6  ✓

Performance Metrics:
  Sync Latency (P95):           432.1ms  (Target: <500ms) ✓
  Undo/Redo Latency (Max):       38.6ms  (Target: <50ms)  ✓
  Comment Preservation Rate:     92.4%   (Target: >90%)   ✓

Failed Tests:
  1. US3.005: comments preserved after 100 round-trips
     Expected 90+ comments, got 87 (96.7% retention)
     File: test/.../comment_preservation_test.exs:142

  2. US5.007: large strategy sync latency under stress
     P95 latency 523.4ms exceeds 500ms target
     File: test/.../performance_test.exs:198

============================================================
```

**ExUnit Integration**:
```elixir
# Custom formatter in test/support/test_reporter.ex
defmodule TradingStrategy.TestReporter do
  use GenServer

  def init(_opts) do
    {:ok, %{tests: [], start_time: System.monotonic_time()}}
  end

  def handle_cast({:test_finished, test_result}, state) do
    # Collect test results
    {:noreply, %{state | tests: [test_result | state.tests]}}
  end

  def terminate(_reason, state) do
    # Print summary report on suite completion
    print_summary_report(state)
  end
end

# Configure in test_helper.exs
ExUnit.configure(formatters: [TradingStrategy.TestReporter])
```

---

## Entity Relationships

```
Test Scenario
  ├─ uses → Strategy Configuration (fixture)
  ├─ generates → Synchronization Event(s)
  ├─ produces → Performance Metric(s)
  └─ contributes to → Test Report

Strategy Configuration
  ├─ defines → Builder State
  ├─ generates → DSL Text
  └─ used in → Multiple Test Scenarios

Synchronization Event
  ├─ measured by → :timer.tc/1
  ├─ contributes to → Performance Metric
  └─ logged in → Test Report

Performance Metric
  ├─ aggregates → Synchronization Events
  ├─ validates → Success Criteria
  └─ included in → Test Report

Test Report
  ├─ summarizes → Test Scenarios
  ├─ reports → Performance Metrics
  └─ outputs to → Console (FR-017)
```

---

## Validation Rules

### Test Scenario Validation:
- Test ID must follow format `US{1-6}.{001-999}`
- Test must belong to one of 6 user stories
- Test must have clear description (from acceptance scenario)
- Test must have at least one assertion

### Strategy Configuration Validation:
- Name must be non-empty string
- Indicators must be list of valid Indicator structs
- Entry/exit conditions must be valid Elixir code
- Complexity level must match indicator count:
  - Simple: 1-2 indicators
  - Medium: 3-10 indicators
  - Complex: 11-30 indicators
  - Large: 31+ indicators

### Performance Metric Validation:
- Sample count must be >= 1 for mean/median
- Sample count must be >= 100 for P95 calculation (statistical significance)
- Target must be positive number
- Pass/fail determined by comparing statistic to target

### Test Report Validation:
- Total tests = passed + failed + skipped
- All user stories (US1-US6) must be present
- Failed test details must include file, line, error message
- Performance metrics must include all required types (sync, undo/redo, comment preservation)

---

## Storage Strategy

**No Persistent Storage Required** (testing-only feature):
- Test scenarios: Defined in test files, executed by ExUnit
- Strategy configurations: Code fixtures in `test/support/fixtures/`
- Synchronization events: Measured at runtime, not persisted
- Performance metrics: Calculated at runtime, output to console
- Test reports: Printed to console, optionally saved to CI artifacts

**Version Control**:
- All test files versioned in Git
- Fixture data files (`.exs`) versioned in Git
- Test reports saved as CI artifacts (optional, not required by spec)

---

## Summary

This data model defines five core entities for testing the bidirectional strategy editor synchronization:

1. **Test Scenario**: Represents individual test cases organized by user story
2. **Strategy Configuration**: Test fixtures ranging from simple to large complexity
3. **Synchronization Event**: Measured events with latency metrics
4. **Performance Metric**: Statistical aggregations validating success criteria
5. **Test Report**: Console-formatted summary with pass/fail and metrics

All entities are ephemeral (runtime-only) except fixtures and tests (version-controlled code). No database schema changes required.
