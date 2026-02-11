# Data Model: Bidirectional Strategy Editor Synchronization

**Feature**: 005-builder-dsl-sync
**Phase**: 1 - Design & Contracts
**Date**: 2026-02-10
**Status**: Complete

---

## Purpose

This document defines the core data structures and entities for the bidirectional strategy editor synchronization feature. All entities support conversion between visual builder form state and DSL text representation.

---

## Entity Diagram

```
┌──────────────────────────────────────────────────────────────┐
│                      StrategyDefinition                      │
├──────────────────────────────────────────────────────────────┤
│ + id: UUID                                                   │
│ + user_id: UUID                                              │
│ + name: String                                               │
│ + dsl_text: String                                           │
│ + builder_state: BuilderState                                │
│ + last_modified_editor: :builder | :dsl                      │
│ + last_modified_at: DateTime                                 │
│ + validation_status: ValidationResult                        │
│ + comments: [Comment]                                        │
└──────────────────────────────────────────────────────────────┘
                            ↓ has many
┌──────────────────────────────────────────────────────────────┐
│                       EditHistory                            │
├──────────────────────────────────────────────────────────────┤
│ + session_id: UUID                                           │
│ + events: [ChangeEvent]                                      │
│ + undo_stack: [ChangeEvent]                                  │
│ + redo_stack: [ChangeEvent]                                  │
│ + max_size: Integer (default: 100)                           │
└──────────────────────────────────────────────────────────────┘
                            ↓ contains
┌──────────────────────────────────────────────────────────────┐
│                       ChangeEvent                            │
├──────────────────────────────────────────────────────────────┤
│ + id: UUID                                                   │
│ + timestamp: Integer (monotonic milliseconds)                │
│ + source: :builder | :dsl                                    │
│ + operation_type: Atom                                       │
│ + path: [String]                                             │
│ + delta: {old_value, new_value}                              │
│ + inverse: {new_value, old_value}                            │
│ + user_id: UUID                                              │
│ + version: Integer                                           │
└──────────────────────────────────────────────────────────────┘
```

---

## Core Entities

### 1. StrategyDefinition

**Purpose**: Root entity representing a trading strategy that can be edited in either builder or DSL format.

**Schema**:

```elixir
defmodule TradingStrategy.StrategyEditor.StrategyDefinition do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "strategy_definitions" do
    field :name, :string
    field :dsl_text, :string
    field :builder_state, :map  # JSON field storing BuilderState
    field :last_modified_editor, Ecto.Enum, values: [:builder, :dsl]
    field :last_modified_at, :utc_datetime_usec
    field :validation_status, :map  # JSON field storing ValidationResult
    field :comments, {:array, :map}  # Preserved DSL comments

    belongs_to :user, TradingStrategy.Accounts.User

    timestamps(type: :utc_datetime_usec)
  end

  @doc """
  Changeset for strategy definition updates.
  Validates that either dsl_text or builder_state is modified, not both simultaneously.
  """
  def changeset(strategy, attrs) do
    strategy
    |> cast(attrs, [:name, :dsl_text, :builder_state, :last_modified_editor, :last_modified_at])
    |> validate_required([:name])
    |> validate_length(:name, min: 1, max: 255)
    |> validate_editor_consistency()
  end

  defp validate_editor_consistency(changeset) do
    # Ensure last_modified_editor matches the field being changed
    dsl_changed? = get_change(changeset, :dsl_text)
    builder_changed? = get_change(changeset, :builder_state)

    cond do
      dsl_changed? && is_nil(builder_changed?) ->
        put_change(changeset, :last_modified_editor, :dsl)

      builder_changed? && is_nil(dsl_changed?) ->
        put_change(changeset, :last_modified_editor, :builder)

      dsl_changed? && builder_changed? ->
        # Both changed - use last_modified_editor from attrs or error
        changeset

      true ->
        changeset
    end
  end
end
```

**Relationships**:
- **belongs_to**: `User` (owner of the strategy)
- **has_many (virtual)**: `EditHistory` (undo/redo events, stored in GenServer)

**Validation Rules**:
- `name` must be present and 1-255 characters
- `dsl_text` or `builder_state` must be present
- `last_modified_editor` must match the last changed field
- `comments` are preserved during transformations (FR-010)

**Lifecycle States**:
- `draft` - Being edited, not validated
- `valid` - Passed semantic validation
- `invalid` - Failed validation, has errors
- `saved` - Persisted to database (explicit save only, FR-020)

---

### 2. BuilderState

**Purpose**: Represents the visual form state of the strategy builder. This is the structured representation that maps to/from DSL text.

**Structure** (TypeSpec-equivalent in Elixir):

```elixir
defmodule TradingStrategy.StrategyEditor.BuilderState do
  @moduledoc """
  Structured representation of strategy form data.
  Converts bidirectionally with DSL text.
  """

  defstruct [
    # Basic Information
    :name,              # String
    :trading_pair,      # String, e.g., "BTC/USD"
    :timeframe,         # String, e.g., "1h", "1d"
    :description,       # String (optional)

    # Indicators
    :indicators,        # [Indicator]

    # Entry/Exit Conditions
    :entry_conditions,  # String (expression)
    :exit_conditions,   # String (expression)
    :stop_conditions,   # String (expression)

    # Position Sizing
    :position_sizing,   # PositionSizing

    # Risk Parameters
    :risk_parameters,   # RiskParameters

    # Metadata (not part of DSL)
    :_comments,         # [Comment] - preserved from DSL
    :_version,          # Integer
    :_last_sync_at      # DateTime
  ]

  @type t :: %__MODULE__{
    name: String.t() | nil,
    trading_pair: String.t() | nil,
    timeframe: String.t() | nil,
    description: String.t() | nil,
    indicators: [Indicator.t()],
    entry_conditions: String.t() | nil,
    exit_conditions: String.t() | nil,
    stop_conditions: String.t() | nil,
    position_sizing: PositionSizing.t() | nil,
    risk_parameters: RiskParameters.t() | nil,
    _comments: [Comment.t()],
    _version: integer(),
    _last_sync_at: DateTime.t() | nil
  }

  defmodule Indicator do
    defstruct [:type, :name, :parameters, :_id]

    @type t :: %__MODULE__{
      type: String.t(),           # e.g., "rsi", "sma", "ema"
      name: String.t(),           # e.g., "rsi_14"
      parameters: map(),          # e.g., %{"period" => 14}
      _id: String.t()             # Client-side UUID for tracking
    }
  end

  defmodule PositionSizing do
    defstruct [:type, :percentage_of_capital, :fixed_amount, :_id]

    @type t :: %__MODULE__{
      type: String.t(),                    # "percentage" | "fixed"
      percentage_of_capital: float() | nil,
      fixed_amount: float() | nil,
      _id: String.t()
    }
  end

  defmodule RiskParameters do
    defstruct [:max_daily_loss, :max_drawdown, :max_position_size, :_id]

    @type t :: %__MODULE__{
      max_daily_loss: float() | nil,      # e.g., 0.03 (3%)
      max_drawdown: float() | nil,        # e.g., 0.15 (15%)
      max_position_size: float() | nil,   # e.g., 0.10 (10%)
      _id: String.t()
    }
  end

  defmodule Comment do
    defstruct [:line, :column, :text, :preserved_from_dsl]

    @type t :: %__MODULE__{
      line: integer(),
      column: integer(),
      text: String.t(),
      preserved_from_dsl: boolean()
    }
  end
end
```

**Conversion Functions**:

```elixir
# Convert BuilderState to DSL text
def to_dsl(builder_state, comments \\ []) do
  TradingStrategy.StrategyEditor.Synchronizer.builder_to_dsl(builder_state, comments)
end

# Convert DSL text to BuilderState
def from_dsl(dsl_text) do
  TradingStrategy.StrategyEditor.Synchronizer.dsl_to_builder(dsl_text)
end
```

**Validation Rules**:
- `name` required
- `trading_pair` must match format "XXX/YYY"
- `timeframe` must be valid (1m, 5m, 15m, 1h, 4h, 1d, etc.)
- `indicators` must reference valid indicator types
- `entry_conditions`, `exit_conditions`, `stop_conditions` must parse as valid expressions
- `position_sizing` required (percentage or fixed)
- `risk_parameters` required (max_daily_loss, max_drawdown)

---

### 3. ChangeEvent

**Purpose**: Represents a single atomic change made in either the builder or DSL editor. Used for undo/redo functionality (FR-012).

**Structure**:

```elixir
defmodule TradingStrategy.StrategyEditor.ChangeEvent do
  @moduledoc """
  Immutable event representing a single change in the editor.
  Both builder and DSL changes emit ChangeEvents into a shared timeline.
  """

  defstruct [
    :id,              # UUID
    :session_id,      # User session UUID
    :timestamp,       # Monotonic milliseconds for ordering
    :source,          # :builder | :dsl
    :operation_type,  # See operation types below
    :path,            # JSON path to changed field, e.g., ["indicators", 0, "period"]
    :delta,           # {old_value, new_value}
    :inverse,         # {new_value, old_value} - used for undo
    :user_id,         # UUID
    :version          # Integer, increments on each change
  ]

  @type t :: %__MODULE__{
    id: String.t(),
    session_id: String.t(),
    timestamp: integer(),
    source: :builder | :dsl,
    operation_type: operation_type(),
    path: [String.t() | integer()],
    delta: {any(), any()},
    inverse: {any(), any()},
    user_id: String.t(),
    version: integer()
  }

  @type operation_type ::
    :add_indicator |
    :remove_indicator |
    :update_indicator |
    :update_entry_condition |
    :update_exit_condition |
    :update_stop_condition |
    :update_position_sizing |
    :update_risk_parameters |
    :update_dsl_text |
    :full_replace  # When DSL text is completely replaced

  @doc """
  Create a new ChangeEvent from a builder or DSL modification.
  """
  def new(attrs) do
    %__MODULE__{
      id: Ecto.UUID.generate(),
      session_id: attrs[:session_id],
      timestamp: System.monotonic_time(:millisecond),
      source: attrs[:source],
      operation_type: attrs[:operation_type],
      path: attrs[:path] || [],
      delta: attrs[:delta],
      inverse: invert_delta(attrs[:delta]),
      user_id: attrs[:user_id],
      version: attrs[:version] || 1
    }
  end

  defp invert_delta({old, new}), do: {new, old}

  @doc """
  Apply the change represented by this event.
  """
  def apply(event, builder_state) do
    TradingStrategy.StrategyEditor.ChangeApplier.apply_change(builder_state, event)
  end

  @doc """
  Create the inverse event for undo functionality.
  """
  def undo_event(event) do
    %__MODULE__{event |
      id: Ecto.UUID.generate(),
      timestamp: System.monotonic_time(:millisecond),
      delta: event.inverse,
      inverse: event.delta,
      version: event.version + 1
    }
  end
end
```

**Operation Types**:
- `add_indicator` - New indicator added to builder
- `remove_indicator` - Indicator removed from builder
- `update_indicator` - Indicator parameter changed
- `update_entry_condition` - Entry condition expression modified
- `update_exit_condition` - Exit condition expression modified
- `update_stop_condition` - Stop condition expression modified
- `update_position_sizing` - Position sizing configuration changed
- `update_risk_parameters` - Risk parameters modified
- `update_dsl_text` - Direct DSL text edit (from DSL editor)
- `full_replace` - Complete strategy replacement (e.g., paste new DSL)

**Example ChangeEvents**:

```elixir
# Builder: User changes RSI period from 14 to 21
%ChangeEvent{
  id: "a1b2c3...",
  session_id: "session-123",
  timestamp: 1734567890123,
  source: :builder,
  operation_type: :update_indicator,
  path: ["indicators", 0, "parameters", "period"],
  delta: {14, 21},
  inverse: {21, 14},
  user_id: "user-456",
  version: 42
}

# DSL Editor: User types new entry condition
%ChangeEvent{
  id: "d4e5f6...",
  session_id: "session-123",
  timestamp: 1734567891234,
  source: :dsl,
  operation_type: :update_entry_condition,
  path: ["entry_conditions"],
  delta: {"rsi_14 < 30", "rsi_14 < 25 && volume > 1000"},
  inverse: {"rsi_14 < 25 && volume > 1000", "rsi_14 < 30"},
  user_id: "user-456",
  version: 43
}
```

---

### 4. EditHistory

**Purpose**: Manages the undo/redo stack for a single editing session. Stored in-memory (GenServer + ETS) for performance, persisted to database for durability.

**Structure**:

```elixir
defmodule TradingStrategy.StrategyEditor.EditHistory do
  @moduledoc """
  Manages undo/redo stacks for a strategy editing session.
  Stored in GenServer + ETS for fast access (<50ms undo/redo response).
  """

  defstruct [
    :session_id,       # UUID
    :undo_stack,       # [ChangeEvent] - LIFO stack
    :redo_stack,       # [ChangeEvent] - LIFO stack
    :max_size,         # Integer, default 100
    :created_at,       # DateTime
    :last_modified_at  # DateTime
  ]

  @type t :: %__MODULE__{
    session_id: String.t(),
    undo_stack: [ChangeEvent.t()],
    redo_stack: [ChangeEvent.t()],
    max_size: integer(),
    created_at: DateTime.t(),
    last_modified_at: DateTime.t()
  }

  @doc """
  Push a new change event onto the undo stack.
  Clears the redo stack (standard undo/redo behavior).
  """
  def push(history, event) do
    new_undo_stack = [event | history.undo_stack]
                     |> Enum.take(history.max_size)  # Limit stack size

    %__MODULE__{history |
      undo_stack: new_undo_stack,
      redo_stack: [],  # Clear redo stack on new change
      last_modified_at: DateTime.utc_now()
    }
  end

  @doc """
  Pop the most recent change from undo stack for undo operation.
  Moves the event to redo stack.
  """
  def undo(history) do
    case history.undo_stack do
      [event | rest] ->
        {:ok, event, %__MODULE__{history |
          undo_stack: rest,
          redo_stack: [event | history.redo_stack],
          last_modified_at: DateTime.utc_now()
        }}

      [] ->
        {:error, :nothing_to_undo}
    end
  end

  @doc """
  Pop the most recent undone change from redo stack for redo operation.
  Moves the event back to undo stack.
  """
  def redo(history) do
    case history.redo_stack do
      [event | rest] ->
        {:ok, event, %__MODULE__{history |
          undo_stack: [event | history.undo_stack],
          redo_stack: rest,
          last_modified_at: DateTime.utc_now()
        }}

      [] ->
        {:error, :nothing_to_redo}
    end
  end

  @doc """
  Check if undo is available.
  """
  def can_undo?(history), do: history.undo_stack != []

  @doc """
  Check if redo is available.
  """
  def can_redo?(history), do: history.redo_stack != []
end
```

**Storage Strategy**:
- **Primary**: GenServer + ETS (in-memory, fast access)
- **Backup**: PostgreSQL (periodic snapshot every 10 events or 5 minutes)
- **Cleanup**: Stale histories (>24h inactive) removed automatically

---

### 5. ValidationResult

**Purpose**: Represents the outcome of DSL syntax and semantic validation.

**Structure**:

```elixir
defmodule TradingStrategy.StrategyEditor.ValidationResult do
  defstruct [
    :valid,            # Boolean
    :errors,           # [ValidationError]
    :warnings,         # [ValidationWarning]
    :unsupported,      # [String] - DSL features not supported by builder
    :validated_at      # DateTime
  ]

  @type t :: %__MODULE__{
    valid: boolean(),
    errors: [ValidationError.t()],
    warnings: [ValidationWarning.t()],
    unsupported: [String.t()],
    validated_at: DateTime.t()
  }

  defmodule ValidationError do
    defstruct [:type, :message, :line, :column, :path, :severity]

    @type t :: %__MODULE__{
      type: :syntax | :semantic | :parser_crash,
      message: String.t(),
      line: integer() | nil,
      column: integer() | nil,
      path: [String.t()] | nil,
      severity: :error | :warning
    }
  end

  defmodule ValidationWarning do
    defstruct [:type, :message, :suggestion]

    @type t :: %__MODULE__{
      type: :unsupported_feature | :incomplete_data | :performance,
      message: String.t(),
      suggestion: String.t() | nil
    }
  end
end
```

**Example ValidationResult**:

```elixir
# Valid DSL
%ValidationResult{
  valid: true,
  errors: [],
  warnings: [],
  unsupported: [],
  validated_at: ~U[2026-02-10 17:30:00Z]
}

# Invalid DSL (syntax error)
%ValidationResult{
  valid: false,
  errors: [
    %ValidationError{
      type: :syntax,
      message: "Unbalanced parentheses in entry_conditions",
      line: 12,
      column: 45,
      path: ["entry_conditions"],
      severity: :error
    }
  ],
  warnings: [],
  unsupported: [],
  validated_at: ~U[2026-02-10 17:31:00Z]
}

# Valid DSL with unsupported features (FR-009)
%ValidationResult{
  valid: true,
  errors: [],
  warnings: [
    %ValidationWarning{
      type: :unsupported_feature,
      message: "Custom Elixir functions in conditions are not supported by the builder",
      suggestion: "Edit in DSL mode or remove custom functions"
    }
  ],
  unsupported: ["custom_function/2"],
  validated_at: ~U[2026-02-10 17:32:00Z]
}
```

---

## State Transitions

### StrategyDefinition Lifecycle

```
     ┌─────────┐
     │  Draft  │ (New strategy, no validation)
     └────┬────┘
          │ user edits (builder or DSL)
          ↓
     ┌─────────┐
     │ Editing │ (Changes pending, debounce in progress)
     └────┬────┘
          │ 300ms debounce complete
          ↓
     ┌─────────┐
     │Validating│ (Parsing + semantic check)
     └────┬────┘
          │
   ┌──────┴──────┐
   ↓             ↓
┌────────┐   ┌────────┐
│ Valid  │   │Invalid │
└───┬────┘   └───┬────┘
    │            │
    │ user saves │ user fixes errors
    ↓            ↓
┌────────┐   ┌─────────┐
│ Saved  │   │ Editing │
└────────┘   └─────────┘
```

### EditHistory State Transitions

```
Empty Stack
     │
     │ user makes change
     ↓
Has Undo
     │
     │ user presses Ctrl+Z
     ↓
Has Undo + Redo
     │
     ├─ user presses Ctrl+Shift+Z ──→ Has Undo + Redo (move between stacks)
     │
     └─ user makes new change ──→ Has Undo (redo stack cleared)
```

---

## Database Schema (PostgreSQL)

```sql
-- Strategy definitions table
CREATE TABLE strategy_definitions (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  name VARCHAR(255) NOT NULL,
  dsl_text TEXT,
  builder_state JSONB,  -- BuilderState serialized as JSON
  last_modified_editor VARCHAR(20),  -- 'builder' or 'dsl'
  last_modified_at TIMESTAMP WITH TIME ZONE,
  validation_status JSONB,  -- ValidationResult serialized as JSON
  comments JSONB,  -- Array of Comment objects
  inserted_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_strategy_definitions_user_id ON strategy_definitions(user_id);
CREATE INDEX idx_strategy_definitions_last_modified ON strategy_definitions(last_modified_at DESC);

-- Edit history table (backup for GenServer state)
CREATE TABLE edit_histories (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  session_id UUID NOT NULL UNIQUE,
  strategy_id UUID NOT NULL REFERENCES strategy_definitions(id) ON DELETE CASCADE,
  undo_stack JSONB,  -- Array of ChangeEvent objects
  redo_stack JSONB,  -- Array of ChangeEvent objects
  max_size INTEGER DEFAULT 100,
  created_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT NOW(),
  last_modified_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_edit_histories_session_id ON edit_histories(session_id);
CREATE INDEX idx_edit_histories_strategy_id ON edit_histories(strategy_id);
CREATE INDEX idx_edit_histories_last_modified ON edit_histories(last_modified_at DESC);

-- Cleanup old edit histories (>24h inactive)
CREATE INDEX idx_edit_histories_cleanup ON edit_histories(last_modified_at)
WHERE last_modified_at < NOW() - INTERVAL '24 hours';
```

---

## Performance Considerations

### Data Structure Sizes

| Entity | Typical Size | Max Size | Storage Location |
|--------|--------------|----------|------------------|
| StrategyDefinition | 5-20 KB | 100 KB | PostgreSQL |
| BuilderState | 3-15 KB | 50 KB | Memory + PostgreSQL |
| ChangeEvent | 0.5-2 KB | 10 KB | GenServer/ETS + PostgreSQL |
| EditHistory (100 events) | 50-200 KB | 1 MB | GenServer/ETS (primary), PostgreSQL (backup) |
| ValidationResult | 0.5-5 KB | 20 KB | Memory (ephemeral) |

### Access Patterns

| Operation | Latency Target | Implementation |
|-----------|----------------|----------------|
| Load strategy | <100ms | PostgreSQL query with index |
| Push ChangeEvent | <1ms | ETS insert |
| Undo/Redo | <50ms | ETS read + GenServer state update |
| Validate DSL | <250ms | Server-side parser (Feature 001) |
| Sync Builder→DSL | <450ms | Sourceror format + network |
| Sync DSL→Builder | <450ms | Parser + state update + network |

---

## Related Documents

- **[spec.md](./spec.md)** - Feature requirements and user scenarios
- **[research.md](./research.md)** - Technology decisions and rationale
- **[contracts/](./contracts/)** - API contracts for LiveView events
- **[quickstart.md](./quickstart.md)** - Development environment setup

---

**Status**: ✅ Complete
**Next**: Generate API contracts (`/contracts/`)
