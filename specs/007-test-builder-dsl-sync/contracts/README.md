# API Contracts: Strategy Editor Synchronization Testing

**Feature**: 007-test-builder-dsl-sync
**Date**: 2026-02-11

## No New Contracts Defined

This feature **does not introduce new API contracts** because it is a testing-only feature that validates existing functionality from Feature 005 (bidirectional strategy editor).

## Existing Contracts Under Test

The test suite validates the following existing contracts from Feature 005:

### 1. Synchronizer Module Contract

**Module**: `TradingStrategy.StrategyEditor.Synchronizer`

**Functions Under Test**:

```elixir
@spec builder_to_dsl(BuilderState.t(), list(Comment.t())) ::
  {:ok, String.t()} | {:error, String.t()}

@spec dsl_to_builder(String.t()) ::
  {:ok, BuilderState.t()} | {:error, list(ValidationError.t())}
```

**Test Coverage**:
- US1: Builder-to-DSL synchronization (FR-001)
- US2: DSL-to-builder synchronization (FR-002)
- US5: Performance validation (<500ms latency) (FR-012)

---

### 2. Validator Module Contract

**Module**: `TradingStrategy.StrategyEditor.Validator`

**Functions Under Test**:

```elixir
@spec validate_dsl(String.t()) ::
  {:ok, AST.t()} | {:error, list(SyntaxError.t())}

@spec validate_builder_state(BuilderState.t()) ::
  {:ok, BuilderState.t()} | {:error, list(ValidationError.t())}
```

**Test Coverage**:
- US6: Error handling with invalid DSL syntax (FR-005)
- US6: Validation error reporting (FR-005)

---

### 3. EditHistory GenServer Contract

**Module**: `TradingStrategy.StrategyEditor.EditHistory`

**Functions Under Test**:

```elixir
@spec start_session(strategy_id :: String.t(), user_id :: String.t()) ::
  {:ok, session_id :: String.t()}

@spec push_event(session_id :: String.t(), event :: ChangeEvent.t()) :: :ok

@spec undo(session_id :: String.t()) ::
  {:ok, ChangeEvent.t()} | {:error, :no_undo_history}

@spec redo(session_id :: String.t()) ::
  {:ok, ChangeEvent.t()} | {:error, :no_redo_history}

@spec end_session(session_id :: String.t()) :: :ok
```

**Test Coverage**:
- US4: Undo/redo functionality (FR-004)
- US4: Shared history across editors (FR-004)
- US5: Undo/redo performance (<50ms latency) (FR-004)

---

### 4. CommentPreserver Module Contract

**Module**: `TradingStrategy.StrategyEditor.CommentPreserver`

**Functions Under Test**:

```elixir
@spec preserve_comments(original_dsl :: String.t(), new_dsl :: String.t()) ::
  {:ok, String.t()}
```

**Test Coverage**:
- US3: Comment preservation across synchronization (FR-003)
- US3: 90%+ retention rate after 100 round-trips (SC-004)

---

### 5. LiveView Event Handlers

**Module**: `TradingStrategyWeb.StrategyEditorLive`

**Events Under Test**:

```elixir
# Builder form changes
def handle_event("indicator_added", %{"indicator" => params}, socket)
def handle_event("indicator_updated", %{"indicator" => params}, socket)
def handle_event("indicator_removed", %{"id" => id}, socket)

# DSL editor changes (via hooks)
def handle_event("dsl_change", %{"value" => dsl_text}, socket)

# Undo/redo keyboard shortcuts
def handle_event("keyboard_shortcut", %{"key" => key, "ctrlKey" => true}, socket)

# Debouncing
def handle_info({:debounced_sync, dsl_text}, socket)
```

**Test Coverage**:
- US1, US2: Form/editor change synchronization (FR-001, FR-002)
- US4: Keyboard shortcuts (FR-009)
- US6: Debouncing (FR-007)
- Edge cases: Browser refresh warning (FR-013)

---

## Test Contract (New)

The only "contract" introduced by this feature is the **test organization contract** (FR-018):

### Test File Organization Contract

```elixir
# test/trading_strategy_web/live/strategy_editor_live/

# User Story 1 (P1): Builder-to-DSL Synchronization
synchronization_test.exs           # US1.001 - US1.010

# User Story 2 (P1): DSL-to-Builder Synchronization
dsl_to_builder_sync_test.exs      # US2.001 - US2.010

# User Story 3 (P2): Comment Preservation
comment_preservation_test.exs      # US3.001 - US3.008

# User Story 4 (P2): Undo/Redo Functionality
undo_redo_test.exs                 # US4.001 - US4.008

# User Story 5 (P3): Performance Validation
performance_test.exs               # US5.001 - US5.010

# User Story 6 (P3): Error Handling
error_handling_test.exs            # US6.001 - US6.006

# Cross-cutting concerns
edge_cases_test.exs                # Browser refresh, rapid switching, etc.
```

### Test Fixture Contract

```elixir
# test/support/fixtures/strategy_fixtures.ex

@spec simple_rsi_strategy() :: BuilderState.t()
@spec simple_sma_crossover() :: BuilderState.t()
@spec medium_multi_indicator() :: BuilderState.t()
@spec medium_trend_following() :: BuilderState.t()
@spec complex_adaptive_strategy() :: BuilderState.t()
@spec large_performance_test_1() :: BuilderState.t()
@spec large_performance_test_2() :: BuilderState.t()
```

**Naming Convention** (FR-019):
- `simple_*`: 1-2 indicators, ~10-20 lines DSL
- `medium_*`: 5-10 indicators, ~50-100 lines DSL
- `complex_*`: 20-30 indicators, ~200-400 lines DSL
- `large_*`: 50+ indicators, 1000+ lines DSL

---

## Why No New Contracts?

1. **Testing-only feature**: Validates existing Feature 005 code, doesn't add new functionality
2. **No new API endpoints**: Tests interact with existing LiveView events
3. **No new modules**: No new public APIs introduced
4. **No external integrations**: Tests run in isolated environment

## Contract Validation Strategy

The test suite validates existing contracts through:

1. **Type Checking**: Dialyzer specs validated via test compilation
2. **Behavior Validation**: Tests verify functions behave according to spec
3. **Performance Contracts**: Tests verify latency targets are met (SC-003, SC-005)
4. **Error Contracts**: Tests verify error handling matches spec (US6)

---

## References

- **Feature 005 Spec**: `/specs/005-builder-dsl-sync/spec.md` (original contracts)
- **Feature 005 Plan**: `/specs/005-builder-dsl-sync/plan.md` (implementation details)
- **This Feature Spec**: `/specs/007-test-builder-dsl-sync/spec.md` (test requirements)
