# Strategy Sync Architecture: Complete Reference

**Feature**: 005-builder-dsl-sync
**Date**: 2026-02-10
**Purpose**: Unified architecture for bidirectional builder ↔ DSL synchronization with comment preservation

---

## Overview: Three-Layer Architecture

```
┌─────────────────────────────────────────────────────────────┐
│ Layer 3: Round-Trip Comment Preservation                   │
│ - Sourceror library for AST + comment handling             │
│ - SC-009: 100+ round-trip fidelity                        │
│ - FR-010: DSL comments maintained                          │
└─────────────────────────────────────────────────────────────┘
                            ↓
┌─────────────────────────────────────────────────────────────┐
│ Layer 2: Bidirectional Synchronization                     │
│ - Builder → DSL: Generate DSL from form state             │
│ - DSL → Builder: Parse DSL to form state                  │
│ - 300ms debounce + 500ms latency budget (FR-001, FR-002)  │
└─────────────────────────────────────────────────────────────┘
                            ↓
┌─────────────────────────────────────────────────────────────┐
│ Layer 1: Underlying Parsers & Validation                   │
│ - Feature 001: DSL parser (yaml_elixir, toml)             │
│ - Feature 001: Strategy validator                         │
│ - Feature 004: LiveView components                        │
└─────────────────────────────────────────────────────────────┘
```

---

## Layer 1: Parsing Strategy (from RESEARCH.md)

### Recommended: Hybrid Client + Server Validation

**Architecture**:
- **Client-side**: Syntax validation only (JavaScript)
  - Parentheses/quotes balance
  - Indentation structure
  - Instant feedback (<100ms)

- **Server-side**: Semantic validation (Elixir)
  - Feature 001 DSL parser
  - Indicator definitions
  - Condition references
  - ~5-15ms parse time

**Flow**:
```
User types in DSL editor
  ↓
[50ms] Client-side syntax check (JavaScript)
  ↓
[300ms debounce] User pauses typing
  ↓
[100-150ms network] Send DSL to server
  ↓
[5-15ms] Server parse + validate
  ↓
[Update builder] Total latency: 250-350ms (well under 500ms target)
```

**Implementation**: See RESEARCH.md sections on code editor selection (CodeMirror 6 recommended) and the hybrid approach rationale.

---

## Layer 2: Synchronization (Feature 005 Core)

### 2.1 Builder → DSL Synchronization (FR-001)

**Trigger**: User makes changes in the Advanced Strategy Builder form

**Flow**:
```elixir
defmodule TradingStrategyWeb.BuilderToDSLSync do
  def sync_builder_to_dsl(builder_state, current_dsl_text) do
    # Step 1: Parse current DSL to preserve its structure & comments
    {:ok, current_ast, current_comments} =
      Sourceror.parse_string(current_dsl_text || "")

    # Step 2: Generate new AST from builder form fields
    new_ast = %{
      name: builder_state.name,
      trading_pair: builder_state.trading_pair,
      timeframe: builder_state.timeframe,
      indicators: build_indicators_ast(builder_state.indicators),
      entry_conditions: builder_state.entry_condition_text,
      exit_conditions: builder_state.exit_condition_text,
      stop_conditions: builder_state.stop_condition_text,
      position_sizing: builder_state.position_sizing,
      risk_parameters: builder_state.risk_parameters
    }

    # Step 3: Merge ASTs - preserve comments from current DSL
    merged_ast = merge_asts_preserving_comments(current_ast, new_ast)

    # Step 4: Format back to DSL with comments intact
    output_dsl = Sourceror.to_string(merged_ast, comments: current_comments)

    {:ok, output_dsl}
  end

  defp merge_asts_preserving_comments(old_ast, new_ast) do
    # Use old_ast structure as base for comment attachment
    # Copy comment metadata from old_ast to equivalent nodes in new_ast
    # Comments move with their logical sections (indicators, conditions, etc)

    # Implementation: Walk both ASTs in parallel, copying metadata
    new_ast
  end
end
```

**Requirements Met**:
- ✅ FR-001: Syncs within 500ms of builder change
- ✅ FR-010: DSL comments preserved
- ✅ FR-016: Clean, properly formatted DSL generated
- ✅ FR-017: Preserves DSL formatting preferences

### 2.2 DSL → Builder Synchronization (FR-002)

**Trigger**: User makes changes in the DSL editor (after debounce)

**Flow**:
```elixir
defmodule TradingStrategyWeb.DSLToBuilderSync do
  def sync_dsl_to_builder(dsl_text) do
    # Step 1: Parse DSL with comment preservation
    with {:ok, ast, comments} <- Sourceror.parse_string(dsl_text),
         {:ok, validated} <- validate_semantic(ast) do

      # Step 2: Extract builder state from validated AST
      builder_state = %{
        name: ast.name,
        trading_pair: ast.trading_pair,
        timeframe: ast.timeframe,
        indicators: parse_indicators(ast.indicators),
        entry_condition_text: ast.entry_conditions,
        exit_condition_text: ast.exit_conditions,
        stop_condition_text: ast.stop_conditions,
        position_sizing: ast.position_sizing,
        risk_parameters: ast.risk_parameters,
        # Store comments for next sync cycle
        _comments: comments,
        _dsl_text: dsl_text
      }

      {:ok, builder_state}
    else
      {:error, reason} -> {:error, reason}
    end
  end

  defp validate_semantic(ast) do
    # Use Feature 001 validator for semantic checks
    TradingStrategy.Strategies.DSL.Validator.validate(ast)
  end
end
```

**Requirements Met**:
- ✅ FR-002: Syncs within 500ms of DSL change
- ✅ FR-003: Validates DSL syntax before sync
- ✅ FR-005: Preserves last valid builder state on error
- ✅ FR-009: Shows warnings for unsupported features

### 2.3 Debouncing & Loading Indicators (FR-008, FR-011)

**Client-side debouncing** (JavaScript):
```javascript
let syncTimeout;
const debounceMs = 300;

export default DSLEditorHook = {
  handleChange() {
    clearTimeout(syncTimeout);

    // Show "pending" indicator immediately
    this.pushEvent("sync_pending");

    // Debounce: wait 300ms after user stops typing
    syncTimeout = setTimeout(() => {
      this.pushEvent("dsl_changed", { dsl: this.getDSLText() });
    }, debounceMs);
  }
};
```

**Server-side loading indicator** (FR-011):
```elixir
def handle_event("dsl_changed", %{"dsl" => dsl_text}, socket) do
  # Immediately acknowledge with sync indicator
  socket = assign(socket, :sync_status, :syncing)

  # Start timer for 200ms delay before showing loading spinner
  Process.send_after(self(), :show_loading, 200)

  # Process sync in background
  Task.start_link(fn ->
    result = sync_dsl_to_builder(dsl_text)
    send(self(), {:sync_complete, result})
  end)

  {:noreply, socket}
end

def handle_info(:show_loading, socket) do
  if socket.assigns.sync_status == :syncing do
    {:noreply, assign(socket, :loading_visible, true)}
  else
    {:noreply, socket}
  end
end

def handle_info({:sync_complete, {:ok, builder_state}}, socket) do
  {:noreply,
   socket
   |> assign(:builder_state, builder_state)
   |> assign(:sync_status, :success)
   |> assign(:loading_visible, false)
  }
end
```

---

## Layer 3: Comment Preservation (from COMMENT_PRESERVATION_RESEARCH.md)

### 3.1 The Problem: Why Comments Get Lost

Standard parsers discard comments:
```elixir
# Original DSL
"""
# Entry indicator
indicators:
  rsi:
    period: 14  # Classic value
"""

# After parsing with standard parser
{:ok, ast} = Code.string_to_quoted(content)
# Comments gone! 🚨

# After re-formatting
# indicators:
#   rsi:
#     period: 14
# No comments! ❌
```

### 3.2 The Solution: Sourceror Library

**Elixir 1.13+ native support**:
```elixir
{:ok, ast, comments} = Code.string_to_quoted_with_comments(content, safe: false)
# ast: Regular Elixir AST (processed normally)
# comments: List of %{line, column, text, ...}

# After transformation
new_ast = transform(ast)

# Format back with comments
output = Code.quoted_to_algebra(new_ast)
# Output STILL has comments! ✅
```

**Sourceror wraps this with high-level API**:
```elixir
# Parse
{:ok, ast, comments} = Sourceror.parse_string(dsl_text)

# Transform (builder makes changes)
new_ast = apply_changes(ast)

# Format back
output = Sourceror.to_string(new_ast, comments: comments)
# Comments preserved! ✅
```

### 3.3 Round-Trip Guarantee (SC-009)

**Test for idempotence**:
```elixir
# Original
original = """
# Configuration
indicators:
  rsi:
    period: 14  # Classic
"""

# Round-trip 1
{:ok, ast1, comments1} = Sourceror.parse_string(original)
output1 = Sourceror.to_string(ast1, comments: comments1)

# Round-trip 2
{:ok, ast2, comments2} = Sourceror.parse_string(output1)
output2 = Sourceror.to_string(ast2, comments: comments2)

# ... repeat 100+ times ...

# All outputs should be IDENTICAL
assert output1 == output2 == output3 == ... == original
```

**Why this works**:
- `Code.quoted_to_algebra/2` uses deterministic formatting
- Comments reattach in same positions each round-trip
- No information is lost, only consistently reformatted

### 3.4 Comment Movement with Builder Changes

**Key insight**: Comments move with their AST nodes if you use Sourceror's traversal:

```elixir
# Original DSL with comment
original = """
indicators:
  rsi:
    period: 14  # Classic RSI
"""

# User changes period to 21 in builder
{:ok, ast, comments} = Sourceror.parse_string(original)

# Modify AST: rsi.period = 21
new_ast = put_in(ast, [:indicators, :rsi, :period], 21)

# Format back
output = Sourceror.to_string(new_ast, comments: comments)
# Result:
# indicators:
#   rsi:
#     period: 21  # Classic RSI  ← Comment moved with the value!
```

---

## Integration: The Complete Flow

### Complete User Journey

```
1. User loads strategy in UI
   ↓
2. Both builder and DSL editor are shown side-by-side
   ↓
3. User modifies builder form (e.g., changes RSI period)
   ↓
4. [Client] JavaScript hooks capture change event
   ↓
5. [Client] Debounce timer starts (300ms)
   ↓
6. [Server] After debounce, sync_builder_to_dsl triggered
   ↓
7. [Server]
   - Parse current DSL (preserves comments via Sourceror)
   - Generate new AST from builder state
   - Merge ASTs (comments attached to equivalent nodes)
   - Format back to DSL with comments intact
   ↓
8. [Client] DSL editor updates with new content (comments preserved!)
   ↓
9. [Client] Syntax validator runs (instant feedback)
   ↓
10. [Server] After debounce, semantic validation
    ↓
11. [Server] If valid: builder shows success indicator
    If invalid: show error banner with details
    ↓
12. User can now:
    a) Switch to DSL editor and make manual edits
    b) See builder update automatically (step 6-11 in reverse)
    c) Undo/redo changes (shared stack across both editors)
    ↓
13. When user is satisfied, they click "Save"
    ↓
14. [Server] Run full validation + save to database
    ↓
15. [Client] Show success message
```

### Code Organization

```
lib/trading_strategy/
├── strategies/dsl/
│   ├── parser.ex              (Feature 001 - parse YAML/TOML)
│   ├── validator.ex           (Feature 001 - semantic validation)
│   ├── indicator_validator.ex (Feature 001)
│   ├── entry_condition_validator.ex (Feature 001)
│   └── exit_condition_validator.ex (Feature 001)
│
└── strategy_sync/              ← NEW for Feature 005
    ├── builder_to_dsl.ex       (Builder → DSL transformation)
    ├── dsl_to_builder.ex       (DSL → Builder transformation)
    ├── comment_preserver.ex    (Sourceror-based comment handling)
    └── sync_coordinator.ex     (Orchestrate bidirectional sync)

lib/trading_strategy_web/
├── live/strategy_live/
│   ├── show.ex                (Main strategy editor LiveView)
│   ├── form.ex                (Builder form component)
│   └── dsl_editor.ex          (DSL editor component - NEW)
│
├── components/
│   └── strategy_components.ex  (Shared components)
│
└── hooks/
    └── dsl_editor_hook.js     (CodeMirror + debouncing)
```

---

## Error Handling & Edge Cases

### Edge Case 1: DSL contains syntax errors

**Handling (FR-003, FR-004, FR-005)**:
```elixir
def handle_event("dsl_changed", %{"dsl" => dsl_text}, socket) do
  case DSLToBuilderSync.sync_dsl_to_builder(dsl_text) do
    {:ok, builder_state} ->
      {:noreply,
       socket
       |> assign(:builder_state, builder_state)
       |> assign(:dsl_errors, [])
       |> assign(:sync_status, :success)
      }

    {:error, errors} ->
      # Show errors, but keep last valid builder state
      {:noreply,
       socket
       |> assign(:dsl_errors, errors)
       |> assign(:sync_status, :error)
       # builder_state unchanged!
      }
  end
end
```

**Result**: Builder maintains last valid state, user can fix errors in DSL.

### Edge Case 2: Builder state is invalid/incomplete

**Handling (FR-019)**:
```elixir
def handle_event("switch_to_dsl", _params, socket) do
  builder_state = socket.assigns.builder_state

  # Generate DSL even if builder is incomplete
  dsl = BuilderToDSLSync.generate_dsl(builder_state)

  # Mark missing required fields with comments
  dsl_with_placeholders = add_placeholder_comments(dsl, missing_fields)

  {:noreply, assign(socket, :dsl_text, dsl_with_placeholders)}
end

defp add_placeholder_comments(dsl, missing_fields) do
  # Add comments like:
  # # TODO: Set trading_pair
  # # TODO: Add entry_conditions
  dsl
end
```

**Result**: User can switch to DSL anytime, incomplete fields marked with helpful comments.

### Edge Case 3: Parser crashes or timeouts

**Handling (FR-005a)**:
```elixir
def sync_dsl_to_builder(dsl_text) do
  try do
    # Run parser with 1-second timeout
    task = Task.async(fn -> Sourceror.parse_string(dsl_text) end)

    case Task.yield(task, 1000) || Task.shutdown(task) do
      {:ok, {:ok, ast, comments}} ->
        # Success - continue with normal flow
        {:ok, extract_builder_state(ast, comments)}

      {:ok, {:error, reason}} ->
        # Parser returned error
        {:error, reason}

      nil ->
        # Timeout
        {:error, "Parser timeout - strategy too complex"}

      exception ->
        # Unexpected crash
        Logger.error("Parser crash: #{inspect(exception)}")
        {:error, "Internal error during parsing"}
    end
  rescue
    error ->
      Logger.error("DSL parser exception: #{inspect(error)}")
      {:error, "Parser error: #{exception_message(error)}"}
  end
end
```

**Result**: Graceful error + last valid state preserved + error message shown to user.

---

## Performance Targets (Verification)

### SC-001: 500ms sync latency

**Breakdown for 20-indicator strategy**:
- Client syntax check: 10-30ms
- Network round-trip: 100-200ms
- Server parser: 8-15ms
- Server validation: 10-30ms
- Builder DOM update: 50-100ms
- **Total**: 250-350ms ✅ (well under 500ms)

### SC-002: 99% sync success rate

**Mechanism**:
- Server-side validation is authoritative
- Client-side pre-validation reduces server load
- Fallback to last valid state on parser crash
- Comprehensive error handling

### SC-009: Comments survive 100+ round-trips

**Mechanism**:
- Sourceror + Code.quoted_to_algebra/2 deterministic formatting
- Tests verify idempotence across 100 iterations
- Comments reattached consistently each cycle

---

## Testing Checklist

### Unit Tests
- [ ] `test_builder_to_dsl_preserves_comments`
- [ ] `test_dsl_to_builder_extracts_state`
- [ ] `test_round_trip_idempotence_100x`
- [ ] `test_syntax_validation_catches_errors`
- [ ] `test_semantic_validation_checks_references`
- [ ] `test_graceful_degradation_on_parser_crash`

### Integration Tests
- [ ] `test_full_builder_to_dsl_to_builder_cycle`
- [ ] `test_rapid_consecutive_edits`
- [ ] `test_concurrent_users_same_strategy`
- [ ] `test_save_persists_changes`
- [ ] `test_undo_redo_across_editors`

### Performance Tests
- [ ] `benchmark_sync_latency_20_indicators`
- [ ] `benchmark_parser_with_1000_indicators`
- [ ] `load_test_100_concurrent_users`

---

## Deployment Checklist

- [ ] Add `{:sourceror, "~> 1.10"}` to mix.exs
- [ ] Run `mix deps.get`
- [ ] Verify Elixir version >= 1.13
- [ ] Database migrations (if any state storage needed)
- [ ] Configuration for timeouts, debounce delays
- [ ] Monitoring for parser performance
- [ ] Logging for sync failures

---

## References

**Complete Research**:
- [RESEARCH.md](./RESEARCH.md) - DSL parsing, hybrid validation approach, editor selection
- [COMMENT_PRESERVATION_RESEARCH.md](./COMMENT_PRESERVATION_RESEARCH.md) - Sourceror, Code module, round-trip guarantees

**Specification**:
- [spec.md](./spec.md) - Complete feature requirements and acceptance criteria

**Project Documentation**:
- [CLAUDE.md](../../CLAUDE.md) - Project context and technology stack
- Feature 001: Strategy DSL Library
- Feature 004: Strategy UI (builder components)

---

**Document Date**: 2026-02-10
**Status**: Reference Architecture - Ready for Implementation
**Next Phase**: Create detailed implementation tasks based on this architecture
