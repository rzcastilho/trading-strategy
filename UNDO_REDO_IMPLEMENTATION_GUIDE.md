# Undo/Redo Implementation Guide

**Quick Start for Developers**
**Target Version:** Elixir 1.17+, OTP 27+, Phoenix 1.7+

---

## Quick Reference: Architecture Decision

```
┌─────────────────────────────────────────────────────────────┐
│                    Browser (User)                           │
│                                                             │
│  ┌─────────────────────────────────┐                       │
│  │  LiveView Hook                  │                       │
│  │  - Undo/Redo Stacks (JS)        │                       │
│  │  - Ctrl+Z Handler               │                       │
│  │  - Optimistic Updates           │                       │
│  └───────────────┬─────────────────┘                       │
│                  │ (immediate UI update)                   │
│                  │ (async notify server)                   │
└──────────────────┼──────────────────────────────────────────┘
                   │
                   │ WebSocket
                   │
┌──────────────────┼──────────────────────────────────────────┐
│  Elixir Server                                              │
│                  │                                          │
│  ┌──────────────┴──────────────────┐                       │
│  │  StrategyLive.Form (LiveView)   │                       │
│  │  - Receives undo/redo events    │                       │
│  │  - Validates with server state  │                       │
│  └───────────────┬──────────────────┘                       │
│                  │                                          │
│  ┌──────────────┴──────────────────┐                       │
│  │  ChangeJournal (GenServer)      │                       │
│  │  - Manages ETS table            │                       │
│  │  - Records changes (cast)       │                       │
│  │  - Retrieves changes (direct)   │                       │
│  └───────────────┬──────────────────┘                       │
│                  │                                          │
│  ┌──────────────┴──────────────────┐                       │
│  │  ETS Table :change_journal      │                       │
│  │  - Fast reads (no blocking)     │                       │
│  │  - Concurrent access            │                       │
│  │  - Max 100 ops per session      │                       │
│  └───────────────┬──────────────────┘                       │
│                  │                                          │
│  ┌──────────────┴──────────────────┐                       │
│  │  PostgreSQL JSONB               │                       │
│  │  - Durable audit trail          │                       │
│  │  - 7-day retention              │                       │
│  └─────────────────────────────────┘                       │
│                                                             │
└─────────────────────────────────────────────────────────────┘
```

---

## File Structure

```
lib/trading_strategy/strategy_editor/
├── change_event.ex          # Change data structure
├── history_stack.ex         # Immutable undo/redo logic
├── change_journal.ex        # GenServer + ETS persistence
└── operations/
    ├── add_indicator.ex
    ├── remove_indicator.ex
    ├── edit_dsl.ex
    └── ...

lib/trading_strategy_web/live/strategy_live/
├── form.ex                  # Updated with undo/redo handling
├── indicator_builder.ex     # Emits change_event
└── condition_builder.ex     # Emits change_event

assets/js/hooks/
└── strategy_editor.js       # Client-side undo/redo

priv/repo/migrations/
└── 20250210000000_create_strategy_change_logs.exs

test/trading_strategy/strategy_editor/
├── change_event_test.exs
├── history_stack_test.exs
└── change_journal_test.exs
```

---

## Step 1: Define Change Events

**File:** `lib/trading_strategy/strategy_editor/change_event.ex`

```elixir
defmodule TradingStrategy.StrategyEditor.ChangeEvent do
  @moduledoc """
  Represents a single change in the strategy editor.

  Each change captures:
  - What changed (operation_type, path)
  - Old and new values (delta)
  - How to reverse it (inverse)
  - Who made it (user_id) and when (timestamp)
  - Where it came from (source: :builder or :dsl)
  """

  alias TradingStrategy.StrategyEditor.ChangeEvent

  @type source :: :builder | :dsl
  @type operation_type :: atom()
  @type path :: list(String.t() | integer())

  defstruct [
    :id,                    # UUID - unique identifier
    :session_id,            # Strategy UUID
    :timestamp,             # DateTime.utc_now()
    :source,                # :builder | :dsl
    :operation_type,        # :add_indicator, :remove_indicator, :edit_dsl, etc.
    :path,                  # JSON path to changed element
    :delta,                 # {old_value, new_value}
    :inverse,               # {new_value, old_value}
    :user_id,               # UUID of user who made change
    :version                # Monotonic timestamp for ordering
  ]

  @doc """
  Create a change from the visual builder.

  Example:
    iex> ChangeEvent.from_builder(
    ...>   "strategy-id",
    ...>   :add_indicator,
    ...>   ["indicators", 2],
    ...>   nil,
    ...>   %{type: "sma", params: %{period: 20}},
    ...>   "user-id"
    ...> )
  """
  def from_builder(session_id, op_type, path, old_value, new_value, user_id) do
    %ChangeEvent{
      id: Ecto.UUID.generate(),
      session_id: session_id,
      timestamp: DateTime.utc_now(),
      source: :builder,
      operation_type: op_type,
      path: path,
      delta: {old_value, new_value},
      inverse: {new_value, old_value},
      user_id: user_id,
      version: System.monotonic_time(:millisecond)
    }
  end

  @doc """
  Create a change from the DSL text editor.

  Example:
    iex> ChangeEvent.from_dsl(
    ...>   "strategy-id",
    ...>   old_content,
    ...>   new_content,
    ...>   "user-id"
    ...> )
  """
  def from_dsl(session_id, old_content, new_content, user_id) do
    %ChangeEvent{
      id: Ecto.UUID.generate(),
      session_id: session_id,
      timestamp: DateTime.utc_now(),
      source: :dsl,
      operation_type: :edit_dsl,
      path: ["content"],
      delta: {old_content, new_content},
      inverse: {new_content, old_content},
      user_id: user_id,
      version: System.monotonic_time(:millisecond)
    }
  end

  @doc """
  Create a change from removing an indicator.
  """
  def remove_indicator(session_id, index, indicator, user_id) do
    from_builder(
      session_id,
      :remove_indicator,
      ["indicators", index],
      indicator,
      nil,
      user_id
    )
  end

  @doc """
  Create a change from editing an indicator.
  """
  def edit_indicator(session_id, index, old_indicator, new_indicator, user_id) do
    from_builder(
      session_id,
      :edit_indicator,
      ["indicators", index],
      old_indicator,
      new_indicator,
      user_id
    )
  end

  @doc """
  Convert to JSON for storage/transmission.
  """
  def to_map(%ChangeEvent{} = event) do
    %{
      id: event.id,
      session_id: event.session_id,
      timestamp: DateTime.to_iso8601(event.timestamp),
      source: event.source,
      operation_type: event.operation_type,
      path: event.path,
      delta: event.delta,
      inverse: event.inverse,
      user_id: event.user_id,
      version: event.version
    }
  end

  @doc """
  Reconstruct from stored JSON.
  """
  def from_map(%{} = map) do
    %ChangeEvent{
      id: map["id"] || map[:id],
      session_id: map["session_id"] || map[:session_id],
      timestamp: parse_timestamp(map["timestamp"] || map[:timestamp]),
      source: String.to_atom(map["source"] || map[:source]),
      operation_type: String.to_atom(map["operation_type"] || map[:operation_type]),
      path: map["path"] || map[:path],
      delta: map["delta"] || map[:delta],
      inverse: map["inverse"] || map[:inverse],
      user_id: map["user_id"] || map[:user_id],
      version: map["version"] || map[:version]
    }
  end

  defp parse_timestamp(iso_string) when is_binary(iso_string) do
    case DateTime.from_iso8601(iso_string) do
      {:ok, dt, _offset} -> dt
      :error -> DateTime.utc_now()
    end
  end

  defp parse_timestamp(%DateTime{} = dt), do: dt
  defp parse_timestamp(_), do: DateTime.utc_now()
end
```

---

## Step 2: Immutable History Stack

**File:** `lib/trading_strategy/strategy_editor/history_stack.ex`

```elixir
defmodule TradingStrategy.StrategyEditor.HistoryStack do
  @moduledoc """
  Implements undo/redo as an immutable functional data structure.

  All operations return a new HistoryStack (no mutations).
  Undo stack is LIFO - last change added is first to be undone.
  """

  alias TradingStrategy.StrategyEditor.ChangeEvent

  defstruct [
    :session_id,
    undo_stack: [],      # List of ChangeEvent (LIFO)
    redo_stack: [],      # List of ChangeEvent (LIFO)
    max_depth: 100,      # Max operations to track
    version: 0           # Monotonic clock for ordering
  ]

  @type t :: %__MODULE__{
    session_id: String.t(),
    undo_stack: list(ChangeEvent.t()),
    redo_stack: list(ChangeEvent.t()),
    max_depth: integer(),
    version: integer()
  }

  @doc """
  Create a new empty history stack for a session.
  """
  @spec new(String.t(), integer()) :: t()
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
  Record a new change in the history.
  Clears the redo stack (standard undo/redo behavior).
  """
  @spec record_change(t(), ChangeEvent.t()) :: t()
  def record_change(%__MODULE__{} = history, %ChangeEvent{} = change) do
    # Add change to undo stack
    new_undo = [change | history.undo_stack]

    # Trim if exceeds max depth
    trimmed = Enum.take(new_undo, history.max_depth)

    %{history |
      undo_stack: trimmed,
      redo_stack: [],  # Clear redo on new change
      version: history.version + 1
    }
  end

  @doc """
  Check if undo is available without modifying the stack.
  """
  @spec can_undo?(t()) :: boolean()
  def can_undo?(%__MODULE__{undo_stack: stack}) do
    Enum.count(stack) > 0
  end

  @doc """
  Check if redo is available without modifying the stack.
  """
  @spec can_redo?(t()) :: boolean()
  def can_redo?(%__MODULE__{redo_stack: stack}) do
    Enum.count(stack) > 0
  end

  @doc """
  Peek at the next undo operation without modifying stacks.
  Returns nil if no undo available.
  """
  @spec peek_undo(t()) :: ChangeEvent.t() | nil
  def peek_undo(%__MODULE__{undo_stack: []}), do: nil
  def peek_undo(%__MODULE__{undo_stack: [change | _]}), do: change

  @doc """
  Peek at the next redo operation without modifying stacks.
  Returns nil if no redo available.
  """
  @spec peek_redo(t()) :: ChangeEvent.t() | nil
  def peek_redo(%__MODULE__{redo_stack: []}), do: nil
  def peek_redo(%__MODULE__{redo_stack: [change | _]}), do: change

  @doc """
  Pop from undo stack and push to redo stack.
  Returns {new_history, change} or {history, nil} if empty.
  """
  @spec undo(t()) :: {t(), ChangeEvent.t() | nil}
  def undo(%__MODULE__{undo_stack: [change | rest]} = history) do
    new_history = %{history |
      undo_stack: rest,
      redo_stack: [change | history.redo_stack],
      version: history.version + 1
    }
    {new_history, change}
  end

  def undo(%__MODULE__{undo_stack: []} = history) do
    {history, nil}
  end

  @doc """
  Pop from redo stack and push to undo stack.
  Returns {new_history, change} or {history, nil} if empty.
  """
  @spec redo(t()) :: {t(), ChangeEvent.t() | nil}
  def redo(%__MODULE__{redo_stack: [change | rest]} = history) do
    new_history = %{history |
      undo_stack: [change | history.undo_stack],
      redo_stack: rest,
      version: history.version + 1
    }
    {new_history, change}
  end

  def redo(%__MODULE__{redo_stack: []} = history) do
    {history, nil}
  end

  @doc """
  Get all changes in chronological order (oldest first).
  Useful for audit logs and visualization.
  """
  @spec all_changes(t()) :: list(ChangeEvent.t())
  def all_changes(%__MODULE__{undo_stack: undo, redo_stack: redo}) do
    Enum.reverse(undo) ++ redo
  end

  @doc """
  Get undo stack depth.
  """
  @spec undo_depth(t()) :: integer()
  def undo_depth(%__MODULE__{undo_stack: stack}) do
    Enum.count(stack)
  end

  @doc """
  Get redo stack depth.
  """
  @spec redo_depth(t()) :: integer()
  def redo_depth(%__MODULE__{redo_stack: stack}) do
    Enum.count(stack)
  end

  @doc """
  Clear all history (for new session or reset).
  """
  @spec clear(t()) :: t()
  def clear(%__MODULE__{} = history) do
    %{history |
      undo_stack: [],
      redo_stack: [],
      version: 0
    }
  end

  @doc """
  Build a summary for debugging/testing.
  """
  @spec summary(t()) :: map()
  def summary(%__MODULE__{} = history) do
    %{
      session_id: history.session_id,
      undo_depth: undo_depth(history),
      redo_depth: redo_depth(history),
      can_undo: can_undo?(history),
      can_redo: can_redo?(history),
      version: history.version
    }
  end
end
```

---

## Step 3: ETS-Backed Journal

**File:** `lib/trading_strategy/strategy_editor/change_journal.ex`

```elixir
defmodule TradingStrategy.StrategyEditor.ChangeJournal do
  use GenServer
  require Logger

  alias TradingStrategy.StrategyEditor.ChangeEvent
  alias TradingStrategy.Repo

  @moduledoc """
  Persistent change journal using ETS for fast concurrent reads.

  Key properties:
  - Writes via GenServer.cast (async, non-blocking)
  - Reads via ETS directly (fast, no blocking)
  - Database persistence via async Task
  - Auto-cleanup of old entries (>24h)

  ## Usage

      iex> ChangeJournal.record(change_event)
      :ok

      iex> ChangeJournal.get_changes("strategy-id")
      [change1, change2, ...]

      iex> ChangeJournal.get_changes("strategy-id", after_version: 100)
      [change3, change4, ...]  # only changes with version > 100
  """

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl true
  def init(_opts) do
    # Primary table: ordered by {session_id, timestamp}
    :ets.new(:change_journal, [
      :named_table,
      :ordered_set,
      :public,
      read_concurrency: true,
      write_concurrency: true
    ])

    # Index by session for fast lookups
    :ets.new(:change_journal_by_session, [
      :named_table,
      :bag,
      :public,
      read_concurrency: true,
      write_concurrency: true
    ])

    schedule_cleanup()

    {:ok, %{
      cleanup_interval: 3_600_000,  # 1 hour
      retention_hours: 24
    }}
  end

  @doc """
  Record a change to the journal (async).
  Returns immediately - actual write happens in GenServer.
  """
  def record(%ChangeEvent{} = change) do
    GenServer.cast(__MODULE__, {:record, change})
  end

  @doc """
  Retrieve all changes for a session in chronological order.
  Fast read directly from ETS (no GenServer call).

  Options:
    - after_version: Only return changes with version > this value
  """
  def get_changes(session_id, opts \\ []) do
    after_version = Keyword.get(opts, :after_version, 0)

    # Query ETS by session (bag table)
    changes =
      :ets.match_object(:change_journal_by_session, {session_id, :"$1"})
      |> Enum.map(&elem(&1, 1))
      |> Enum.filter(&(&1.version > after_version))
      |> Enum.sort_by(& &1.timestamp)

    changes
  end

  @doc """
  Get the latest version number for a session.
  Useful for detecting changes from other users.
  """
  def get_latest_version(session_id) do
    case get_changes(session_id) do
      [] -> 0
      changes -> Enum.max_by(changes, & &1.version).version
    end
  end

  @doc """
  Persist a change to the database (for durability).
  Called async from handle_cast to not block users.
  """
  def persist_to_database(%ChangeEvent{} = change) do
    # Create database record
    %StrategyEditor.StrategyChangeLog{}
    |> StrategyEditor.StrategyChangeLog.changeset(%{
      session_id: change.session_id,
      change_id: change.id,
      source: change.source,
      operation_type: change.operation_type,
      path: change.path,
      delta: Jason.encode!(change.delta),
      timestamp: change.timestamp
    })
    |> Repo.insert()
    |> case do
      {:ok, _} -> :ok
      {:error, reason} ->
        Logger.warn("Failed to persist change: #{inspect(reason)}")
        :error
    end
  end

  @impl true
  def handle_cast({:record, change}, state) do
    # 1. Insert into primary ETS table
    key = {change.session_id, change.timestamp}
    :ets.insert(:change_journal, {key, change})

    # 2. Insert into session index
    :ets.insert(:change_journal_by_session, {change.session_id, change})

    # 3. Schedule async database write (doesn't block)
    Task.start_link(fn -> persist_to_database(change) end)

    {:noreply, state}
  end

  @impl true
  def handle_info(:cleanup, state) do
    # Remove entries older than retention period
    cutoff = DateTime.add(DateTime.utc_now(), -state.retention_hours, :hour)

    # Match and delete old entries
    pattern = {:"_", %{timestamp: {:<, cutoff}}}
    :ets.match_delete(:change_journal, pattern)

    Logger.debug("ChangeJournal: cleaned up entries before #{cutoff}")
    schedule_cleanup()

    {:noreply, state}
  end

  defp schedule_cleanup do
    Process.send_after(self(), :cleanup, 3_600_000)
  end
end
```

---

## Step 4: LiveView Integration

**File:** `lib/trading_strategy_web/live/strategy_live/form.ex` (additions)

```elixir
defmodule TradingStrategyWeb.StrategyLive.Form do
  use TradingStrategyWeb, :live_view

  alias TradingStrategy.Strategies
  alias TradingStrategy.StrategyEditor.{ChangeEvent, HistoryStack, ChangeJournal}

  def mount(params, _session, socket) do
    strategy_id = params["id"]
    current_user = socket.assigns.current_scope.user

    # ... existing code ...

    if connected?(socket) do
      # Initialize empty history stack for this session
      history = HistoryStack.new(strategy_id)

      {:ok,
       socket
       |> assign(:history, history)
       |> push_event("strategy:history_loaded", HistoryStack.summary(history))}
    else
      {:ok, socket |> assign(:history, HistoryStack.new(strategy_id))}
    end
  end

  # Handle undo from client
  def handle_event("undo", params, socket) do
    {new_history, change} = HistoryStack.undo(socket.assigns.history)

    if change do
      # Apply inverse change to UI
      socket =
        socket
        |> apply_change(change.inverse)
        |> assign(:history, new_history)

      # Notify server async (fire-and-forget)
      ChangeJournal.record(change)

      # Update client state
      {:noreply,
       socket
       |> push_event("strategy:undo_performed", %{
         can_undo: HistoryStack.can_undo?(new_history),
         can_redo: HistoryStack.can_redo?(new_history)
       })}
    else
      {:noreply, socket}
    end
  end

  # Handle redo from client
  def handle_event("redo", params, socket) do
    {new_history, change} = HistoryStack.redo(socket.assigns.history)

    if change do
      socket =
        socket
        |> apply_change(change.delta)
        |> assign(:history, new_history)

      ChangeJournal.record(change)

      {:noreply,
       socket
       |> push_event("strategy:redo_performed", %{
         can_undo: HistoryStack.can_undo?(new_history),
         can_redo: HistoryStack.can_redo?(new_history)
       })}
    else
      {:noreply, socket}
    end
  end

  # Record change from indicator builder
  def handle_info({:record_change, change_event}, socket) do
    new_history = HistoryStack.record_change(socket.assigns.history, change_event)
    ChangeJournal.record(change_event)

    {:noreply,
     socket
     |> assign(:history, new_history)
     |> push_event("strategy:history_updated", HistoryStack.summary(new_history))}
  end

  # Apply change to UI
  defp apply_change(socket, change) do
    case change.operation_type do
      :add_indicator ->
        # Add indicator to socket state
        socket

      :remove_indicator ->
        # Remove indicator from socket state
        socket

      :edit_dsl ->
        {old_content, new_content} = change.delta
        assign(socket, :dsl_content, new_content)

      _ ->
        socket
    end
  end
end
```

---

## Step 5: Client-Side Hook

**File:** `assets/js/hooks/strategyEditor.js`

```javascript
const StrategyEditorHook = {
  mounted() {
    this.undoStack = [];
    this.redoStack = [];
    this.isReconciling = false;

    // Setup keyboard shortcuts
    document.addEventListener('keydown', this.handleKeyDown.bind(this));

    // Listen for server events
    this.el.addEventListener('phx:strategy:history_updated', (e) => {
      this.updateHistoryUI(e.detail);
    });

    this.el.addEventListener('phx:strategy:undo_performed', (e) => {
      this.updateHistoryUI(e.detail);
    });

    this.el.addEventListener('phx:strategy:redo_performed', (e) => {
      this.updateHistoryUI(e.detail);
    });

    this.updateUndoRedoButtons();
  },

  handleKeyDown(e) {
    // Ctrl+Z or Cmd+Z: Undo
    if ((e.ctrlKey || e.metaKey) && e.key === 'z' && !e.shiftKey) {
      e.preventDefault();
      this.performUndo();
    }

    // Ctrl+Shift+Z or Cmd+Shift+Z: Redo
    if ((e.ctrlKey || e.metaKey) && e.key === 'z' && e.shiftKey) {
      e.preventDefault();
      this.performRedo();
    }
  },

  performUndo() {
    // Send event to server
    this.el.pushEvent('undo', {
      timestamp: new Date().toISOString()
    });

    // Show visual feedback
    this.showUndoFeedback();
  },

  performRedo() {
    this.el.pushEvent('redo', {
      timestamp: new Date().toISOString()
    });

    this.showRedoFeedback();
  },

  updateHistoryUI(data) {
    this.updateUndoRedoButtons(data);
  },

  updateUndoRedoButtons(state = {}) {
    const undoBtn = document.querySelector('[data-action="undo"]');
    const redoBtn = document.querySelector('[data-action="redo"]');

    if (undoBtn) {
      undoBtn.disabled = !state.can_undo;
      undoBtn.title = state.can_undo ? 'Undo (Ctrl+Z)' : 'Nothing to undo';
    }

    if (redoBtn) {
      redoBtn.disabled = !state.can_redo;
      redoBtn.title = state.can_redo ? 'Redo (Ctrl+Shift+Z)' : 'Nothing to redo';
    }
  },

  showUndoFeedback() {
    this.showToast('↶ Undo', 'info', 1500);
  },

  showRedoFeedback() {
    this.showToast('↷ Redo', 'info', 1500);
  },

  showToast(message, type = 'info', duration = 3000) {
    const toast = document.createElement('div');
    toast.className = `toast toast-${type} animate-in animate-out`;
    toast.textContent = message;
    document.body.appendChild(toast);

    setTimeout(() => toast.remove(), duration);
  }
};

export { StrategyEditorHook };
```

---

## Step 6: Database Migration

**File:** `priv/repo/migrations/20250210000000_create_strategy_change_logs.exs`

```elixir
defmodule TradingStrategy.Repo.Migrations.CreateStrategyChangeLogs do
  use Ecto.Migration

  def change do
    create table(:strategy_change_logs, primary_key: false) do
      add :id, :uuid, primary_key: true, default: fragment("gen_random_uuid()")

      # Foreign keys
      add :strategy_id, references(:strategies, type: :uuid, on_delete: :cascade),
        null: false
      add :change_id, :uuid, null: false

      # Change metadata
      add :source, :string, null: false  # 'builder' or 'dsl'
      add :operation_type, :string, null: false
      add :path, {:array, :string}, default: []
      add :delta, :map, null: false  # {old, new}

      # Timestamps
      add :inserted_at, :utc_datetime_usec, null: false, default: fragment("NOW()")
    end

    # Indexes for fast queries
    create index(:strategy_change_logs, [:strategy_id, :inserted_at])
    create index(:strategy_change_logs, [:change_id], unique: true)
    create index(:strategy_change_logs, [:source])
  end
end
```

---

## Testing Template

**File:** `test/trading_strategy/strategy_editor/history_stack_test.exs`

```elixir
defmodule TradingStrategy.StrategyEditor.HistoryStackTest do
  use ExUnit.Case
  doctest TradingStrategy.StrategyEditor.HistoryStack

  alias TradingStrategy.StrategyEditor.{HistoryStack, ChangeEvent}

  setup do
    {:ok, history: HistoryStack.new("session-1")}
  end

  describe "record_change/2" do
    test "adds change to undo stack", %{history: history} do
      change = ChangeEvent.from_builder("session-1", :add_indicator, ["indicators", 0], nil, %{type: "sma"}, "user-1")
      new_history = HistoryStack.record_change(history, change)

      assert [^change] = new_history.undo_stack
      assert [] = new_history.redo_stack
    end

    test "clears redo stack on new change", %{history: history} do
      change1 = ChangeEvent.from_builder("session-1", :add_indicator, ["indicators", 0], nil, %{}, "user-1")
      change2 = ChangeEvent.from_builder("session-1", :add_indicator, ["indicators", 1], nil, %{}, "user-1")

      history = HistoryStack.record_change(history, change1)
      {history, _} = HistoryStack.undo(history)
      history = HistoryStack.record_change(history, change2)

      assert [change2] = history.undo_stack
      assert [] = history.redo_stack
    end

    test "respects max_depth limit" do
      history = HistoryStack.new("session-1", max_depth: 3)

      history = Enum.reduce(1..5, history, fn i, h ->
        change = ChangeEvent.from_builder("session-1", :add_indicator, ["indicators", i], nil, %{}, "user-1")
        HistoryStack.record_change(h, change)
      end)

      assert Enum.count(history.undo_stack) == 3
    end
  end

  describe "undo/1" do
    test "moves from undo to redo stack", %{history: history} do
      change = ChangeEvent.from_builder("session-1", :add_indicator, ["indicators", 0], nil, %{}, "user-1")
      history = HistoryStack.record_change(history, change)

      {new_history, popped} = HistoryStack.undo(history)

      assert popped == change
      assert [] = new_history.undo_stack
      assert [^change] = new_history.redo_stack
    end

    test "returns nil when undo stack empty", %{history: history} do
      {new_history, result} = HistoryStack.undo(history)

      assert result == nil
      assert new_history == history
    end
  end

  describe "redo/1" do
    test "moves from redo to undo stack", %{history: history} do
      change = ChangeEvent.from_builder("session-1", :add_indicator, ["indicators", 0], nil, %{}, "user-1")
      history = HistoryStack.record_change(history, change)
      {history, _} = HistoryStack.undo(history)

      {new_history, popped} = HistoryStack.redo(history)

      assert popped == change
      assert [^change] = new_history.undo_stack
      assert [] = new_history.redo_stack
    end
  end

  describe "can_undo?/1 and can_redo?/1" do
    test "returns false for empty stacks", %{history: history} do
      assert not HistoryStack.can_undo?(history)
      assert not HistoryStack.can_redo?(history)
    end

    test "returns true when changes available", %{history: history} do
      change = ChangeEvent.from_builder("session-1", :add_indicator, ["indicators", 0], nil, %{}, "user-1")
      history = HistoryStack.record_change(history, change)

      assert HistoryStack.can_undo?(history)
      assert not HistoryStack.can_redo?(history)
    end
  end
end
```

---

## Integration Checklist

- [ ] Create ChangeEvent module
- [ ] Create HistoryStack module
- [ ] Create ChangeJournal GenServer
- [ ] Create database migration
- [ ] Create StrategyChangeLog schema
- [ ] Update StrategyLive.Form with undo/redo handlers
- [ ] Update IndicatorBuilder to emit change events
- [ ] Update ConditionBuilder to emit change events
- [ ] Create JavaScript hook with keyboard shortcuts
- [ ] Add undo/redo buttons to UI
- [ ] Write unit tests
- [ ] Write integration tests
- [ ] Load hook in strategy form template

---

## Performance Expectations

| Operation | Expected Time | Notes |
|-----------|---------------|-------|
| User presses Ctrl+Z | <20ms | Immediate UI update |
| HistoryStack.undo | <1ms | Pure Elixir, no I/O |
| ETS read (get_changes) | <2ms | Per 100 operations |
| ChangeJournal.record | 0ms (cast) | Async, non-blocking |
| Database write | 5-10ms | Background task |
| Broadcast to other users | 50-150ms | Network dependent |

---

## Troubleshooting

**Q: Changes not being recorded?**
A: Check that ChangeJournal GenServer started:
```elixir
:global.registered_names() |> Enum.find(&(&1 == TradingStrategy.StrategyEditor.ChangeJournal))
```

**Q: Undo/redo not working?**
A: Verify hook is mounted:
```javascript
console.log(document.querySelector('[phx-hook="StrategyEditor"]'));
```

**Q: Memory growing unbounded?**
A: Check max_depth limit and ETS table size:
```elixir
:ets.info(:change_journal)
```

---

**Implementation Status:** Ready for Development
**Estimated Effort:** 2-3 days (with testing)
**Review Checkpoints:** After Phase 1 (server), Phase 2 (LiveView), Phase 3 (client)
