# Undo/Redo Implementation Research for Bidirectional Editor

**Research Date:** 2025-02-10
**Target:** Phoenix LiveView with visual builder + DSL text editor
**Requirement:** <500ms undo/redo response time, shared change history
**Codebase Context:** Elixir 1.17+ (OTP 27+), Phoenix 1.7+, GenServer patterns already in use

---

## Executive Summary

For a bidirectional editor (visual builder ↔ DSL text editor) in Phoenix LiveView with <500ms response time requirements and shared change history tracking, **a hybrid approach with client-side undo/redo backed by server-side event sourcing is recommended**.

The strategy leverages your existing GenServer patterns (ConcurrencyManager, ProgressTracker) and adds:
1. **Client-side undo stack** (JavaScript/LiveView hooks) for instant UI feedback
2. **Server-side event journal** (ETS-backed GenServer) for persistence and synchronization
3. **Change event normalization** to handle both editor sources in a unified timeline

---

## 1. Architecture Comparison

### 1.1 Client-Side Only (Pure JavaScript)

**Implementation Approach:**
- CommandPattern: Each user action creates a reversible Command object
- MementoPattern: Store state snapshots before/after each operation
- Keep undo/redo stacks in browser memory

```javascript
class Command {
  constructor(execute, undo) {
    this.execute = execute;
    this.undo = undo;
  }
}

const undoStack = [];
const redoStack = [];

function executeCommand(cmd) {
  cmd.execute();
  undoStack.push(cmd);
  redoStack.length = 0; // Clear redo on new command
}

function undo() {
  const cmd = undoStack.pop();
  cmd.undo();
  redoStack.push(cmd);
}
```

**Pros:**
- ✅ **Instant response** (<10ms) - no server round-trip
- ✅ **No network latency** affecting user experience
- ✅ **Simplest implementation** - all logic client-side
- ✅ **Works offline** - no server dependency

**Cons:**
- ❌ **No persistence** - lost on page refresh
- ❌ **No multi-user synchronization** - conflicts if another user edits
- ❌ **Memory bloat** - storing full state snapshots consumes significant RAM
- ❌ **State synchronization hell** - must keep client and server in sync
- ❌ **No audit trail** - cannot replay changes from database

**Memory Analysis:**
- 50 operations × 5KB per snapshot = 250KB (acceptable)
- 100 operations × 5KB per snapshot = 500KB (becoming problematic)
- Large DSL content (10KB+) compounds the issue

**Recommendation:** ❌ **NOT suitable for this use case** - loses data on refresh, lacks server persistence


### 1.2 Server-Side Only (Elixir GenServer)

**Implementation Approach:**
- GenServer maintains complete history in-memory with ETS for concurrent reads
- Client sends change events, waits for server confirmation before rendering
- Server broadcasts state to all connected clients

```elixir
defmodule StrategyEditor.ChangeHistory do
  use GenServer

  defstruct [
    :session_id,
    :changes,           # List of changes with timestamps
    :undo_stack,
    :redo_stack,
    :current_version
  ]

  def start_link(session_id) do
    GenServer.start_link(__MODULE__, session_id,
      name: via_tuple(session_id))
  end

  def handle_event(session_id, change_event) do
    GenServer.call(via_tuple(session_id), {:apply_change, change_event})
  end

  def undo(session_id) do
    GenServer.call(via_tuple(session_id), :undo)
  end

  def redo(session_id) do
    GenServer.call(via_tuple(session_id), :redo)
  end
end
```

**Pros:**
- ✅ **Single source of truth** - one authoritative state
- ✅ **Persistent** - can reload history from database
- ✅ **Collaborative** - all users see same timeline
- ✅ **Audit trail** - full change history for compliance
- ✅ **Conflict resolution** - server can handle race conditions

**Cons:**
- ❌ **Network latency** - every undo/redo is a round-trip (100-200ms typical)
- ❌ **User perception** - feels "sluggish" with <500ms requirement
- ❌ **Server CPU** - GenServer handles all operations (doesn't scale well)
- ❌ **Backpressure issues** - if many users edit, GenServer becomes bottleneck

**Latency Analysis (Real-World Conditions):**
- Client→Server: 50-100ms (typical)
- Server processing: 5-20ms (GenServer call overhead)
- Server→Client: 50-100ms
- **Total: 105-220ms** ✅ Meets <500ms requirement
- But with network jitter: 150-300ms (acceptable but noticeable)

**Recommendation:** ⚠️ **Acceptable but suboptimal** - meets timing requirements but feels slower to users


### 1.3 Hybrid Approach (Recommended) ⭐

**Implementation Strategy:**
- **Client-side:** Instant undo/redo without waiting for server
- **Server-side:** Event journal + state persistence
- **Synchronization:** Optimistic updates + eventual consistency

```elixir
# Server-side: Event journal in ETS + GenServer
defmodule StrategyEditor.ChangeJournal do
  use GenServer
  require Logger

  # Change event structure
  defstruct [
    :id,              # UUID for deduplication
    :session_id,
    :timestamp,       # ISO8601 UTC
    :source,          # :builder or :dsl
    :operation_type,  # :add_indicator, :edit_dsl, etc.
    :delta,           # The actual change
    :inverse,         # How to undo it
    :applied_at       # Server timestamp when applied
  ]

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl true
  def init(_opts) do
    # ETS table for fast concurrent reads
    :ets.new(:change_journal, [
      :named_table,
      :ordered_set,        # Ordered by timestamp
      :public,             # Visible to all processes
      read_concurrency: true,
      write_concurrency: true
    ])

    {:ok, %{
      max_history: 100,    # Per-session limit
      cleanup_after: 24 * 60 * 60  # 24 hours in seconds
    }}
  end

  def record_change(session_id, change_event) do
    GenServer.cast(__MODULE__, {:record, session_id, change_event})
  end

  def get_changes(session_id, after_version \\ 0) do
    # Fast read from ETS - no call overhead
    ets_read_changes(session_id, after_version)
  end

  @impl true
  def handle_cast({:record, session_id, change_event}, state) do
    change = %__MODULE__{
      id: UUID.uuid4(),
      session_id: session_id,
      timestamp: DateTime.utc_now(),
      source: change_event.source,
      operation_type: change_event.operation_type,
      delta: change_event.delta,
      inverse: change_event.inverse,
      applied_at: DateTime.utc_now()
    }

    # Store in ETS
    key = {session_id, change.timestamp}
    :ets.insert(:change_journal, {key, change})

    # Cleanup old entries if needed
    maybe_cleanup_old_entries(session_id, state)

    {:noreply, state}
  end
end
```

**Client-side Hook (LiveView):**

```javascript
// hooks/strategyEditor.js
const StrategyEditorHook = {
  mounted() {
    this.undoStack = [];
    this.redoStack = [];
    this.isReconciling = false;

    // Setup keyboard shortcuts
    document.addEventListener('keydown', (e) => {
      if ((e.ctrlKey || e.metaKey) && e.key === 'z') {
        e.preventDefault();
        this.undo();
      }
      if ((e.ctrlKey || e.metaKey) && e.shiftKey && e.key === 'z') {
        e.preventDefault();
        this.redo();
      }
    });
  },

  undo() {
    if (this.undoStack.length === 0) return;

    const change = this.undoStack.pop();
    this.redoStack.push(change);

    // Apply inverse operation immediately (optimistic)
    this.applyChange(change.inverse, true);

    // Notify server asynchronously (fire-and-forget)
    this.el.pushEvent('undo', {
      change_id: change.id,
      timestamp: change.timestamp
    });
  },

  redo() {
    if (this.redoStack.length === 0) return;

    const change = this.redoStack.pop();
    this.undoStack.push(change);

    // Apply change immediately (optimistic)
    this.applyChange(change.delta, true);

    // Notify server asynchronously
    this.el.pushEvent('redo', {
      change_id: change.id,
      timestamp: change.timestamp
    });
  },

  applyChange(delta, optimistic = false) {
    // Update UI immediately
    if (delta.type === 'add_indicator') {
      this.addIndicatorUI(delta.payload);
    } else if (delta.type === 'edit_dsl') {
      this.updateDSLEditor(delta.payload);
    }

    if (!optimistic) {
      this.undoStack.push(delta);
      this.redoStack = [];
    }
  }
};
```

**Server-side Handler:**

```elixir
# In StrategyLive.Form
def handle_event("undo", %{"change_id" => change_id, "timestamp" => ts}, socket) do
  session_id = socket.assigns.strategy.id

  # Verify change exists and belongs to this session (security)
  case ChangeJournal.verify_and_undo(session_id, change_id, ts) do
    {:ok, new_state} ->
      # Broadcast to all connected clients
      broadcast_state_change(session_id, new_state)
      {:noreply, socket}

    {:error, reason} ->
      Logger.warn("Undo failed: #{reason}")
      {:noreply, put_flash(socket, :error, "Undo failed")}
  end
end
```

**Pros:**
- ✅ **Instant response** (<50ms) - client applies changes immediately
- ✅ **Persistent** - server maintains durable journal
- ✅ **Collaborative** - changes broadcast to all users
- ✅ **Conflict detection** - server validates each operation
- ✅ **Fallback handling** - if server fails, client queue survives
- ✅ **Scales** - ETS provides concurrent reads without GenServer contention
- ✅ **Audit trail** - full operational history

**Cons:**
- ⚠️ **Eventual consistency** - brief window where client≠server
- ⚠️ **Reconciliation needed** - if server rejects change, must rollback
- ⚠️ **More complex** - requires careful state management

**Latency Breakdown:**
- User presses Ctrl+Z: 0ms → immediate UI feedback
- Server is notified asynchronously: 50-100ms (no blocking)
- Other users see change after broadcast: 100-150ms
- **Perceived responsiveness: <50ms ✅**

**Recommendation:** ⭐ **BEST FIT** - Delivers instant UI feedback while maintaining server persistence


---

## 2. Shared Change Timeline Architecture

### 2.1 Change Event Structure

For a unified timeline tracking changes from both visual builder and DSL text editor:

```elixir
defmodule StrategyEditor.ChangeEvent do
  @type operation :: atom()
  @type source :: :builder | :dsl

  defstruct [
    :id,                    # UUID for deduplication
    :session_id,            # Strategy editing session
    :timestamp,             # DateTime.utc_now()
    :source,                # :builder | :dsl
    :operation_type,        # :add_indicator, :edit_dsl, :remove_condition, etc.
    :path,                  # ["indicators", 0] for nested changes
    :delta,                 # {old_value, new_value}
    :inverse,               # Reverse operation
    :user_id,               # Who made the change
    :version                # Monotonic clock for ordering
  ]

  @doc """
  Track changes from visual builder
  """
  def from_builder(session_id, operation_type, path, old_value, new_value) do
    %__MODULE__{
      id: UUID.uuid4(),
      session_id: session_id,
      timestamp: DateTime.utc_now(),
      source: :builder,
      operation_type: operation_type,
      path: path,
      delta: {old_value, new_value},
      inverse: {new_value, old_value},
      version: System.monotonic_time(:millisecond)
    }
  end

  @doc """
  Track changes from DSL text editor
  """
  def from_dsl(session_id, old_content, new_content) do
    %__MODULE__{
      id: UUID.uuid4(),
      session_id: session_id,
      timestamp: DateTime.utc_now(),
      source: :dsl,
      operation_type: :edit_dsl,
      path: ["content"],
      delta: {old_content, new_content},
      inverse: {new_content, old_content},
      version: System.monotonic_time(:millisecond)
    }
  end
end
```

### 2.2 History Stack Implementation

```elixir
defmodule StrategyEditor.HistoryStack do
  @moduledoc """
  Manages undo/redo stacks for a strategy editing session.

  Key design decisions:
  - Uses lists (not arrays) for O(1) push/pop
  - Limits history to max 100 operations (configurable)
  - Stores only deltas, not full state snapshots
  - Tracks monotonic version for conflict detection
  """

  defstruct [
    :session_id,
    undo_stack: [],     # Stack of ChangeEvent
    redo_stack: [],     # Stack of ChangeEvent
    max_depth: 100,     # Max operations to keep
    version: 0          # Monotonic clock
  ]

  def new(session_id, max_depth \\ 100) do
    %__MODULE__{
      session_id: session_id,
      undo_stack: [],
      redo_stack: [],
      max_depth: max_depth,
      version: 0
    }
  end

  @doc """
  Record a new change in the undo stack.
  Clears redo stack (standard undo/redo behavior).
  """
  def record_change(%__MODULE__{} = history, change_event) do
    updated_stack = [change_event | history.undo_stack]

    # Trim if exceeds max depth
    trimmed = Enum.take(updated_stack, history.max_depth)

    %{history |
      undo_stack: trimmed,
      redo_stack: [],  # Clear redo on new change
      version: history.version + 1
    }
  end

  @doc """
  Get the next undo operation without applying it.
  """
  def peek_undo(%__MODULE__{undo_stack: []}), do: nil
  def peek_undo(%__MODULE__{undo_stack: [change | _]}), do: change

  @doc """
  Get the next redo operation without applying it.
  """
  def peek_redo(%__MODULE__{redo_stack: []}), do: nil
  def peek_redo(%__MODULE__{redo_stack: [change | _]}), do: change

  @doc """
  Pop from undo stack and push to redo stack.
  Returns {history, change_event} or {history, nil} if empty.
  """
  def undo(%__MODULE__{undo_stack: [change | rest]} = history) do
    new_history = %{history |
      undo_stack: rest,
      redo_stack: [change | history.redo_stack]
    }
    {new_history, change}
  end

  def undo(%__MODULE__{undo_stack: []} = history) do
    {history, nil}
  end

  @doc """
  Pop from redo stack and push to undo stack.
  Returns {history, change_event} or {history, nil} if empty.
  """
  def redo(%__MODULE__{redo_stack: [change | rest]} = history) do
    new_history = %{history |
      undo_stack: [change | history.undo_stack],
      redo_stack: rest
    }
    {new_history, change}
  end

  def redo(%__MODULE__{redo_stack: []} = history) do
    {history, nil}
  end

  @doc """
  Get all changes in chronological order (for display/audit).
  """
  def all_changes(%__MODULE__{undo_stack: undo, redo_stack: redo}) do
    # Undo stack is in reverse order (LIFO), so reverse it
    Enum.reverse(undo) ++ redo
  end
end
```

### 2.3 ETS-Backed Journal for Persistence

```elixir
defmodule StrategyEditor.ChangeJournal do
  use GenServer
  require Logger

  @moduledoc """
  Persists change history to ETS and database.

  Provides:
  - Fast reads via ETS (no GenServer contention)
  - Durable storage in Postgres
  - Cleanup of old entries (>24h)
  - Conflict detection for collaborative editing
  """

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl true
  def init(_opts) do
    # Primary ETS table: ordered by {session_id, timestamp}
    :ets.new(:change_journal, [
      :named_table,
      :ordered_set,
      :public,
      read_concurrency: true,
      write_concurrency: true
    ])

    # Index table for quick session lookups
    :ets.new(:change_journal_by_session, [
      :named_table,
      :bag,
      :public,
      read_concurrency: true
    ])

    # Schedule periodic cleanup
    schedule_cleanup()

    {:ok, %{cleanup_interval: 3_600_000}}  # 1 hour
  end

  @doc """
  Record a change to the journal.
  """
  def record(change_event) do
    GenServer.cast(__MODULE__, {:record, change_event})
  end

  @doc """
  Retrieve changes for a session after a specific version.
  Fast read - no blocking!
  """
  def get_changes(session_id, after_version \\ 0) do
    # Query ETS directly - no GenServer call
    pattern = {{session_id, :"_"}, :"$1"}
    matches = :ets.match(:change_journal_by_session, pattern)

    matches
    |> List.flatten()
    |> Enum.filter(fn change -> change.version > after_version end)
    |> Enum.sort_by(& &1.timestamp)
  end

  @impl true
  def handle_cast({:record, change_event}, state) do
    # Insert into ETS (primary store)
    key = {change_event.session_id, change_event.timestamp}
    :ets.insert(:change_journal, {key, change_event})

    # Insert into session index
    :ets.insert(:change_journal_by_session, {change_event.session_id, change_event})

    # Async persist to database (doesn't block client)
    Task.Supervisor.start_child(
      TradingStrategy.TaskSupervisor,
      fn -> persist_to_database(change_event) end
    )

    {:noreply, state}
  end

  @impl true
  def handle_info(:cleanup, state) do
    # Remove entries older than 24h
    cutoff = DateTime.add(DateTime.utc_now(), -24, :hour)

    # In production: more sophisticated cleanup with pagination
    :ets.match_delete(:change_journal, {:"_", %{timestamp: {:<, cutoff}}})

    schedule_cleanup()
    {:noreply, state}
  end

  defp schedule_cleanup do
    Process.send_after(self(), :cleanup, 3_600_000)
  end

  defp persist_to_database(change_event) do
    %StrategyChangeLog{}
    |> StrategyChangeLog.changeset(%{
      session_id: change_event.session_id,
      change_id: change_event.id,
      source: change_event.source,
      operation_type: change_event.operation_type,
      delta: Jason.encode!(change_event.delta),
      timestamp: change_event.timestamp
    })
    |> TradingStrategy.Repo.insert()
  end
end
```

---

## 3. Maximum History Depth Analysis

### 3.1 Memory Consumption

Assuming average change event size: **0.5-1 KB**

| Operations | Memory (ETS) | Memory (Storage) | Duration |
|------------|------------|------------------|----------|
| 50 | 25-50 KB | 25-50 KB | ~15 min (avg 18s/op) |
| 100 | 50-100 KB | 50-100 KB | ~30 min |
| 200 | 100-200 KB | 100-200 KB | ~60 min |
| **500** | **250-500 KB** | **250-500 KB** | **~150 min** |

**Recommended: 100-200 operations max per session**

Rationale:
- 100 ops = ~30 minutes of editing at normal pace
- Users rarely undo beyond 30 minutes back
- Keeps ETS footprint minimal (<100 KB per session)
- Can store in PostgreSQL JSONB with minimal storage

### 3.2 Cleanup Strategy

```elixir
@doc """
Implement a two-tier cleanup strategy:
1. In-memory: Keep max 100 operations in ETS
2. Database: Keep full history for 7-30 days
"""
def cleanup_old_entries(session_id, max_ops \\ 100) do
  changes = get_all_changes(session_id)

  if Enum.count(changes) > max_ops do
    to_delete = Enum.drop(changes, max_ops)

    Enum.each(to_delete, fn change ->
      key = {session_id, change.timestamp}
      :ets.delete(:change_journal, key)
    end)
  end
end
```

---

## 4. Implementation Roadmap for Your Codebase

### Phase 1: Server-Side Foundation (Week 1)

**Files to create:**

1. **`lib/trading_strategy/strategy_editor/change_event.ex`**
   - Define ChangeEvent structure
   - Add builders: `from_builder/5`, `from_dsl/3`

2. **`lib/trading_strategy/strategy_editor/history_stack.ex`**
   - Implement HistoryStack (immutable, functional)
   - Add `record_change/2`, `undo/1`, `redo/1`, `peek_undo/1`, `peek_redo/1`

3. **`lib/trading_strategy/strategy_editor/change_journal.ex`**
   - GenServer + ETS for persistence
   - Add `record/1`, `get_changes/2`
   - Database schema: `strategy_change_logs` table

4. **Database migration:**
   ```sql
   CREATE TABLE strategy_change_logs (
     id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
     strategy_id UUID NOT NULL REFERENCES strategies(id),
     change_id UUID NOT NULL UNIQUE,
     source VARCHAR(50) NOT NULL,  -- 'builder' or 'dsl'
     operation_type VARCHAR(100) NOT NULL,
     delta JSONB NOT NULL,
     path TEXT[] DEFAULT '{}',
     inserted_at TIMESTAMP NOT NULL DEFAULT NOW(),

     INDEX (strategy_id, inserted_at)
   );
   ```

### Phase 2: LiveView Integration (Week 2)

1. **Update `StrategyLive.Form`:**
   - Add `history_stack` to socket assigns
   - Handle new events: `"undo"`, `"redo"`
   - Sync builder + DSL state

2. **Update builders (IndicatorBuilder, ConditionBuilder):**
   - Emit `change_event` to parent
   - Parent records in journal

3. **Create LiveView hook: `assets/js/hooks/strategyEditor.js`**
   - Client-side undo/redo stacks
   - Keyboard shortcuts: Ctrl+Z / Ctrl+Shift+Z
   - Optimistic updates

### Phase 3: Collaboration Features (Week 3)

1. **Add conflict detection:**
   - Check version numbers
   - Detect overlapping edits
   - Merge or reject

2. **Add change visualization:**
   - Timeline view of changes
   - "Undo 3 steps" confirmation
   - Show who changed what

---

## 5. Comparison Matrix

| Aspect | Client-Only | Server-Only | Hybrid ⭐ |
|--------|-------------|-------------|----------|
| **Response Time** | <10ms ✅ | 150-300ms ⚠️ | <50ms ✅ |
| **Persistence** | ❌ Lost on refresh | ✅ Durable | ✅ Durable |
| **Collaboration** | ❌ No sync | ✅ Full | ✅ Full |
| **Memory** | 250-500 KB | GenServer heap | 50-100 KB (ETS) |
| **Complexity** | ⭐ Low | ⭐⭐ Medium | ⭐⭐⭐ Medium-High |
| **Scalability** | ⭐ Good (local) | ⭐ Poor (GenServer) | ⭐⭐⭐ Excellent (ETS) |
| **Audit Trail** | ❌ No | ✅ Yes | ✅ Yes |
| **Offline Support** | ✅ Limited | ❌ No | ✅ Queue changes |
| **Recommended for** | Simple, single-user | Low concurrency | This project ⭐ |

---

## 6. Code Example: Integration with Your Builders

### Adding to IndicatorBuilder:

```elixir
# In handle_event("add_indicator", ...)
def handle_event("add_indicator", _params, socket) do
  type = socket.assigns.new_indicator_type
  params = socket.assigns.new_indicator_params

  new_indicator = %{
    id: generate_indicator_id(),
    type: type,
    params: params,
    valid?: validate_indicator(type, params, socket.assigns.available_indicators)
  }

  updated_indicators = socket.assigns.selected_indicators ++ [new_indicator]

  # Record change in parent
  change_event = ChangeEvent.from_builder(
    socket.assigns.strategy.id,
    :add_indicator,
    ["indicators", length(updated_indicators) - 1],
    nil,  # old_value
    new_indicator  # new_value
  )

  send(self(), {:indicators_changed, updated_indicators})
  send(socket.parent_pid, {:record_change, change_event})

  {:noreply,
   socket
   |> assign(:selected_indicators, updated_indicators)
   |> assign(:show_add_form, false)
   |> assign(:new_indicator_type, nil)
   |> assign(:new_indicator_params, %{})}
end
```

### In StrategyLive.Form:

```elixir
def mount(params, _session, socket) do
  # ... existing code ...

  if connected?(socket) do
    # Initialize history for this session
    history = HistoryStack.new(strategy.id)

    {:ok,
     socket
     |> assign(:history_stack, history)
     |> assign(:page_title, "Strategy Editor")}
  else
    {:ok, socket}
  end
end

def handle_event("undo", _params, socket) do
  {new_history, change} = HistoryStack.undo(socket.assigns.history_stack)

  # Apply inverse change to UI
  socket = apply_change_to_ui(socket, change.inverse)

  # Notify server async
  ChangeJournal.record(change)

  {:noreply, assign(socket, :history_stack, new_history)}
end

def handle_info({:record_change, change_event}, socket) do
  new_history = HistoryStack.record_change(socket.assigns.history_stack, change_event)
  ChangeJournal.record(change_event)

  {:noreply, assign(socket, :history_stack, new_history)}
end
```

---

## 7. Testing Strategy

```elixir
# test/trading_strategy/strategy_editor/history_stack_test.exs
describe "undo/redo" do
  test "records changes in undo stack" do
    history = HistoryStack.new("session-1")
    change = ChangeEvent.from_builder("session-1", :add_indicator, ["indicators", 0], nil, %{})

    history = HistoryStack.record_change(history, change)

    assert [^change] = history.undo_stack
    assert [] = history.redo_stack
  end

  test "undo pops from undo stack and pushes to redo stack" do
    history = HistoryStack.new("session-1")
    change = ChangeEvent.from_builder("session-1", :add_indicator, ["indicators", 0], nil, %{})

    history = HistoryStack.record_change(history, change)
    {history, popped_change} = HistoryStack.undo(history)

    assert popped_change == change
    assert [] = history.undo_stack
    assert [^change] = history.redo_stack
  end

  test "new change clears redo stack" do
    history = HistoryStack.new("session-1")
    change1 = ChangeEvent.from_builder("session-1", :add_indicator, ["indicators", 0], nil, %{})
    change2 = ChangeEvent.from_builder("session-1", :add_indicator, ["indicators", 1], nil, %{})

    history = HistoryStack.record_change(history, change1)
    {history, _} = HistoryStack.undo(history)
    history = HistoryStack.record_change(history, change2)

    assert [change2] = history.undo_stack
    assert [] = history.redo_stack
  end
end
```

---

## 8. Performance Considerations

### 8.1 Benchmarks (Expected)

```
Operation          Time
undo (ETS read)    < 1ms
redo (ETS read)    < 1ms
record (cast)      < 5ms
get_changes        < 2ms per 100 ops
```

### 8.2 Optimization Tips

1. **Use ETS reads directly** (public table) to avoid GenServer call overhead
2. **Batch database writes** if logging high volume
3. **Store deltas, not snapshots** to minimize memory
4. **Limit history to 100 operations** per session

---

## 9. Error Handling & Edge Cases

### 9.1 Network Disconnection

```javascript
// Client: Queue changes during disconnect
const pendingChanges = [];

function recordOfflineChange(delta) {
  pendingChanges.push(delta);
  // Apply to UI immediately
}

// On reconnect
function syncPendingChanges() {
  pendingChanges.forEach(delta => {
    this.el.pushEvent('apply_change', delta);
  });
  pendingChanges = [];
}
```

### 9.2 Server Rejection

```javascript
// If server rejects a change (e.g., conflict):
this.el.on('change_rejected', (payload) => {
  // Roll back optimistic update
  this.rollbackChange(payload.change_id);
  // Show user error
  showAlert("Change conflict - please retry");
});
```

### 9.3 Version Conflicts

```elixir
# Server detects two users editing simultaneously
def handle_undo_with_conflict(session_id, change_id, current_version) do
  case ChangeJournal.get_changes(session_id, current_version) do
    [] -> {:ok, "undo applied"}
    conflicting_changes ->
      {:error, {:conflict, conflicting_changes}}
  end
end
```

---

## 10. Recommendations Summary

### Chosen Approach: **Hybrid (Client + Server)**

**Implementation Priority:**
1. ✅ Server-side ChangeEvent + HistoryStack (stateless, pure functions)
2. ✅ ETS-backed ChangeJournal (GenServer for writes, public ETS for reads)
3. ✅ LiveView form integration (emit change events from builders)
4. ✅ JavaScript hook for client-side undo/redo (Ctrl+Z)
5. ⚠️ Conflict detection (Phase 2)
6. ⚠️ Change timeline UI (Phase 3)

### Expected Performance:
- **User-perceived latency:** <50ms ✅ (instant feedback)
- **Server consistency:** <200ms ✅ (async broadcast)
- **Memory per session:** 50-100 KB ✅
- **Concurrent users:** 100+ on single node ✅

### Testing Coverage:
- Unit tests for HistoryStack (pure functions)
- Integration tests for ChangeJournal + ETS
- LiveView component tests for builder changes
- E2E tests for undo/redo workflows

---

## References & Further Reading

1. **Command Pattern**: https://refactoring.guru/design-patterns/command
2. **Memento Pattern**: https://refactoring.guru/design-patterns/memento
3. **Event Sourcing**: https://martinfowler.com/eaaDev/EventSourcing.html
4. **Operational Transformation**: https://en.wikipedia.org/wiki/Operational_transformation
5. **Elixir GenServer Best Practices**: https://hexdocs.pm/elixir/GenServer.html
6. **ETS Concurrency**: https://erlang.org/doc/man/ets.html
7. **Phoenix LiveView Hooks**: https://hexdocs.pm/phoenix_live_view/js-interop.html

---

**Document Status:** Research Complete
**Last Updated:** 2025-02-10
**Recommended for Review:** Architecture team, Frontend leads
