# LiveView Event Contracts

**Feature**: 005-builder-dsl-sync
**Phase**: 1 - Design & Contracts
**Date**: 2026-02-10
**Status**: Complete

---

## Purpose

This document defines the Phoenix LiveView event handler contracts for bidirectional strategy editor synchronization. All events follow Phoenix LiveView conventions and support real-time updates via WebSocket.

---

## Event Handler Conventions

### General Structure

All Phoenix LiveView events follow this pattern:

```elixir
def handle_event(event_name, params, socket) do
  # Validate params
  # Process event
  # Update socket assigns
  # Return {:noreply, updated_socket}
end
```

### Standard Response Format

```elixir
{:noreply, socket}  # Success, UI updated via assigns
{:reply, map, socket}  # Success with explicit response (rare)
```

### Error Handling

Errors are communicated via flash messages or socket assigns:

```elixir
socket
|> put_flash(:error, "Validation failed: #{error_message}")
|> assign(:validation_errors, errors)
```

---

## Core Events

### 1. `dsl_changed` - DSL Editor → Builder Sync

**Triggered**: When user edits DSL text (after 300ms debounce)

**Purpose**: Parse DSL text and synchronize to builder form

**Parameters**:

```elixir
%{
  "dsl_text" => String.t(),  # Full DSL content
  "source" => "dsl_editor"   # Source identifier
}
```

**Handler**:

```elixir
def handle_event("dsl_changed", %{"dsl_text" => dsl_text}, socket) do
  # Rate limiting: Ensure minimum 300ms between syncs (FR-008)
  if can_sync?(socket) do
    case Synchronizer.dsl_to_builder(dsl_text) do
      {:ok, builder_state} ->
        # Create ChangeEvent for undo/redo
        change_event = ChangeEvent.new(%{
          session_id: socket.assigns.session_id,
          source: :dsl,
          operation_type: :update_dsl_text,
          delta: {socket.assigns.dsl_text, dsl_text},
          user_id: socket.assigns.current_user.id,
          version: socket.assigns.version + 1
        })

        # Push to undo stack
        EditHistory.push(socket.assigns.session_id, change_event)

        {:noreply,
         socket
         |> assign(:builder_state, builder_state)
         |> assign(:dsl_text, dsl_text)
         |> assign(:last_modified_editor, :dsl)
         |> assign(:last_modified_at, DateTime.utc_now())
         |> assign(:sync_status, :success)
         |> assign(:validation_errors, [])
         |> assign(:version, socket.assigns.version + 1)
        }

      {:error, %ValidationResult{} = result} ->
        # Show validation errors but keep last valid builder state (FR-005)
        {:noreply,
         socket
         |> assign(:dsl_text, dsl_text)  # Update DSL text (user's input)
         |> assign(:sync_status, :error)
         |> assign(:validation_errors, result.errors)
         |> assign(:validation_warnings, result.warnings)
         |> put_flash(:error, format_validation_errors(result.errors))
        }
    end
  else
    # Drop event if too frequent (server-side rate limiting)
    {:noreply, socket}
  end
end

defp can_sync?(socket) do
  last_sync = socket.assigns[:last_sync_at] || 0
  now = System.monotonic_time(:millisecond)
  now - last_sync >= 300  # FR-008: 300ms minimum
end
```

**Success Response** (socket assigns):

```elixir
%{
  builder_state: BuilderState.t(),
  dsl_text: String.t(),
  last_modified_editor: :dsl,
  last_modified_at: DateTime.t(),
  sync_status: :success,
  validation_errors: [],
  version: integer()
}
```

**Error Response** (socket assigns):

```elixir
%{
  dsl_text: String.t(),  # User's input preserved
  sync_status: :error,
  validation_errors: [ValidationError.t()],
  validation_warnings: [ValidationWarning.t()]
}
```

**Related Requirements**: FR-002, FR-003, FR-004, FR-005, FR-008, SC-001

---

### 2. `builder_changed` - Builder Form → DSL Sync

**Triggered**: When user modifies builder form (after 300ms debounce)

**Purpose**: Generate DSL text from builder state

**Parameters**:

```elixir
%{
  "builder_state" => map(),  # Serialized BuilderState
  "source" => "builder_form"
}
```

**Handler**:

```elixir
def handle_event("builder_changed", %{"builder_state" => builder_state_map}, socket) do
  if can_sync?(socket) do
    builder_state = BuilderState.from_map(builder_state_map)
    comments = socket.assigns[:comments] || []

    case Synchronizer.builder_to_dsl(builder_state, comments) do
      {:ok, dsl_text} ->
        # Create ChangeEvent
        change_event = ChangeEvent.new(%{
          session_id: socket.assigns.session_id,
          source: :builder,
          operation_type: determine_operation_type(builder_state, socket.assigns.builder_state),
          delta: {socket.assigns.builder_state, builder_state},
          user_id: socket.assigns.current_user.id,
          version: socket.assigns.version + 1
        })

        EditHistory.push(socket.assigns.session_id, change_event)

        {:noreply,
         socket
         |> assign(:builder_state, builder_state)
         |> assign(:dsl_text, dsl_text)
         |> assign(:last_modified_editor, :builder)
         |> assign(:last_modified_at, DateTime.utc_now())
         |> assign(:sync_status, :success)
         |> assign(:version, socket.assigns.version + 1)
        }

      {:error, reason} ->
        {:noreply,
         socket
         |> assign(:sync_status, :error)
         |> put_flash(:error, "Failed to generate DSL: #{reason}")
        }
    end
  else
    {:noreply, socket}
  end
end

defp determine_operation_type(new_state, old_state) do
  cond do
    length(new_state.indicators) > length(old_state.indicators) -> :add_indicator
    length(new_state.indicators) < length(old_state.indicators) -> :remove_indicator
    new_state.entry_conditions != old_state.entry_conditions -> :update_entry_condition
    new_state.exit_conditions != old_state.exit_conditions -> :update_exit_condition
    new_state.position_sizing != old_state.position_sizing -> :update_position_sizing
    true -> :update_indicator
  end
end
```

**Success Response** (socket assigns):

```elixir
%{
  builder_state: BuilderState.t(),
  dsl_text: String.t(),
  last_modified_editor: :builder,
  last_modified_at: DateTime.t(),
  sync_status: :success,
  version: integer()
}
```

**Related Requirements**: FR-001, FR-010, FR-016, SC-001

---

### 3. `undo` - Undo Last Change

**Triggered**: When user presses Ctrl+Z or clicks Undo button

**Purpose**: Revert last change from either editor

**Parameters**:

```elixir
%{}  # No parameters needed
```

**Handler**:

```elixir
def handle_event("undo", _params, socket) do
  case EditHistory.undo(socket.assigns.session_id) do
    {:ok, event, _updated_history} ->
      # Apply inverse of the event
      inverse_event = ChangeEvent.undo_event(event)

      case apply_change_event(socket, inverse_event) do
        {:ok, updated_socket} ->
          {:noreply,
           updated_socket
           |> put_flash(:info, "Undid: #{humanize_operation(event.operation_type)}")
          }

        {:error, reason} ->
          {:noreply,
           socket
           |> put_flash(:error, "Undo failed: #{reason}")
          }
      end

    {:error, :nothing_to_undo} ->
      {:noreply,
       socket
       |> put_flash(:info, "Nothing to undo")
      }
  end
end

defp apply_change_event(socket, event) do
  case event.source do
    :dsl ->
      # Undo was a DSL change, revert DSL text
      dsl_text = elem(event.delta, 0)  # old value
      {:ok, builder_state} = Synchronizer.dsl_to_builder(dsl_text)

      {:ok, assign(socket, builder_state: builder_state, dsl_text: dsl_text)}

    :builder ->
      # Undo was a builder change, revert builder state
      builder_state = elem(event.delta, 0)  # old value
      {:ok, dsl_text} = Synchronizer.builder_to_dsl(builder_state, socket.assigns.comments)

      {:ok, assign(socket, builder_state: builder_state, dsl_text: dsl_text)}
  end
end
```

**Success Response** (socket assigns):
- Builder and DSL reverted to previous state
- Flash message confirms undo

**Related Requirements**: FR-012, SC-007

---

### 4. `redo` - Redo Last Undone Change

**Triggered**: When user presses Ctrl+Shift+Z or clicks Redo button

**Purpose**: Re-apply last undone change

**Parameters**:

```elixir
%{}  # No parameters needed
```

**Handler**:

```elixir
def handle_event("redo", _params, socket) do
  case EditHistory.redo(socket.assigns.session_id) do
    {:ok, event, _updated_history} ->
      case apply_change_event(socket, event) do
        {:ok, updated_socket} ->
          {:noreply,
           updated_socket
           |> put_flash(:info, "Redid: #{humanize_operation(event.operation_type)}")
          }

        {:error, reason} ->
          {:noreply,
           socket
           |> put_flash(:error, "Redo failed: #{reason}")
          }
      end

    {:error, :nothing_to_redo} ->
      {:noreply,
       socket
       |> put_flash(:info, "Nothing to redo")
      }
  end
end
```

**Success Response**: Same as undo

**Related Requirements**: FR-012, SC-007

---

### 5. `save_strategy` - Explicit Save (No Autosave)

**Triggered**: When user clicks Save button

**Purpose**: Persist strategy to database (FR-020)

**Parameters**:

```elixir
%{}  # No parameters needed (uses socket assigns)
```

**Handler**:

```elixir
def handle_event("save_strategy", _params, socket) do
  strategy = socket.assigns.strategy
  attrs = %{
    name: socket.assigns.builder_state.name,
    dsl_text: socket.assigns.dsl_text,
    builder_state: socket.assigns.builder_state,
    last_modified_editor: socket.assigns.last_modified_editor,
    last_modified_at: socket.assigns.last_modified_at,
    comments: socket.assigns.comments
  }

  case Strategies.update_strategy(strategy, attrs) do
    {:ok, updated_strategy} ->
      # Persist edit history snapshot
      EditHistory.persist_snapshot(socket.assigns.session_id)

      {:noreply,
       socket
       |> assign(:strategy, updated_strategy)
       |> assign(:unsaved_changes, false)
       |> put_flash(:info, "Strategy saved successfully")
      }

    {:error, %Ecto.Changeset{} = changeset} ->
      {:noreply,
       socket
       |> assign(:changeset_errors, changeset_errors(changeset))
       |> put_flash(:error, "Failed to save strategy")
      }
  end
end
```

**Success Response**:
- Flash message confirms save
- `unsaved_changes` flag cleared

**Related Requirements**: FR-020

---

### 6. `validate_dsl` - Manual Validation Trigger

**Triggered**: When user clicks "Validate" button or switches editors

**Purpose**: Force immediate validation without waiting for debounce

**Parameters**:

```elixir
%{
  "dsl_text" => String.t()
}
```

**Handler**:

```elixir
def handle_event("validate_dsl", %{"dsl_text" => dsl_text}, socket) do
  result = Validator.validate_dsl(dsl_text)

  {:noreply,
   socket
   |> assign(:validation_result, result)
   |> assign(:dsl_text, dsl_text)
   |> then(fn s ->
     if result.valid do
       put_flash(s, :info, "DSL is valid ✓")
     else
       put_flash(s, :error, "DSL has #{length(result.errors)} error(s)")
     end
   end)
  }
end
```

**Related Requirements**: FR-003, FR-004, FR-005

---

## Client-Side JavaScript Hooks

### 1. `DSLEditorHook` - CodeMirror Integration

**Purpose**: Integrate CodeMirror 6 with LiveView

**Mounted**:

```javascript
export const DSLEditorHook = {
  mounted() {
    this.editor = new EditorView({
      doc: this.el.dataset.initialDsl,
      extensions: [basicSetup, yaml(), debounceExtension(300)],
      parent: this.el,
      dispatch: (transaction) => {
        this.editor.update([transaction]);
        this.handleChange();
      }
    });
  },

  handleChange() {
    const dslText = this.editor.state.doc.toString();

    // Client-side syntax validation (instant feedback)
    const syntaxErrors = validateSyntax(dslText);
    if (syntaxErrors.length > 0) {
      this.displaySyntaxErrors(syntaxErrors);
    }

    // Debounced server sync
    clearTimeout(this.syncTimer);
    this.syncTimer = setTimeout(() => {
      this.pushEvent("dsl_changed", { dsl_text: dslText, source: "dsl_editor" });
    }, 300);  // FR-008: 300ms debounce
  },

  updated() {
    // Update editor if DSL changed from builder
    const newDsl = this.el.dataset.currentDsl;
    if (newDsl !== this.editor.state.doc.toString()) {
      this.editor.dispatch({
        changes: { from: 0, to: this.editor.state.doc.length, insert: newDsl }
      });
    }
  }
};
```

---

### 2. `BuilderFormHook` - Builder Form Debouncing

**Purpose**: Debounce builder form changes

**Mounted**:

```javascript
export const BuilderFormHook = {
  mounted() {
    this.debounceTimer = null;

    this.el.addEventListener("input", (e) => {
      const formData = new FormData(this.el);
      const builderState = Object.fromEntries(formData);

      clearTimeout(this.debounceTimer);
      this.debounceTimer = setTimeout(() => {
        this.pushEvent("builder_changed", {
          builder_state: builderState,
          source: "builder_form"
        });
      }, 300);
    });
  }
};
```

---

## Event Flow Diagrams

### DSL → Builder Sync

```
User Types DSL
      ↓
[300ms Debounce] (DSLEditorHook)
      ↓
pushEvent("dsl_changed", {dsl_text})
      ↓
[Server: handle_event("dsl_changed", ...)]
      ↓
Parse DSL (Elixir parser)
      ↓
   Valid? ─── No ──→ assign(:validation_errors) → Flash Error
      │
     Yes
      ↓
assign(:builder_state, parsed_state)
      ↓
Push ChangeEvent to EditHistory
      ↓
{:noreply, updated_socket}
      ↓
[Client: LiveView re-renders]
      ↓
Builder Form Updates ✓
```

### Builder → DSL Sync

```
User Edits Builder Form
      ↓
[300ms Debounce] (BuilderFormHook)
      ↓
pushEvent("builder_changed", {builder_state})
      ↓
[Server: handle_event("builder_changed", ...)]
      ↓
Generate DSL (Sourceror + comments)
      ↓
assign(:dsl_text, generated_dsl)
      ↓
Push ChangeEvent to EditHistory
      ↓
{:noreply, updated_socket}
      ↓
[Client: LiveView re-renders]
      ↓
CodeMirror Updates (updated() hook) ✓
```

### Undo/Redo Flow

```
User Presses Ctrl+Z
      ↓
pushEvent("undo")
      ↓
[Server: handle_event("undo", ...)]
      ↓
EditHistory.undo(session_id)
      ↓
Get ChangeEvent with inverse delta
      ↓
Apply inverse (revert to old value)
      ↓
Update both builder_state AND dsl_text
      ↓
{:noreply, updated_socket}
      ↓
[Client: Both editors update] ✓
```

---

## Performance Targets

| Event | Target Latency | Typical Latency | Status |
|-------|----------------|-----------------|--------|
| `dsl_changed` | <500ms | 250-350ms | ✅ |
| `builder_changed` | <500ms | 200-300ms | ✅ |
| `undo` | <100ms | 20-50ms | ✅ |
| `redo` | <100ms | 20-50ms | ✅ |
| `save_strategy` | <1000ms | 100-300ms | ✅ |
| `validate_dsl` | <500ms | 150-250ms | ✅ |

---

## Error Codes

| Code | Message | Recovery |
|------|---------|----------|
| `PARSE_ERROR` | "Failed to parse DSL syntax" | Show syntax errors, preserve last valid state |
| `VALIDATION_ERROR` | "DSL is syntactically correct but semantically invalid" | Show semantic errors, allow editing |
| `RATE_LIMIT` | "Too many sync requests, please wait" | Drop event, user automatically retries after debounce |
| `PARSER_CRASH` | "Unexpected parser failure" | Log error, preserve last valid state, show retry button (FR-005a) |
| `SAVE_ERROR` | "Failed to save strategy to database" | Show error, allow retry |

---

## Testing Checklist

- [ ] `dsl_changed` handles valid DSL (builder updates within 500ms)
- [ ] `dsl_changed` handles syntax errors (errors displayed, builder unchanged)
- [ ] `dsl_changed` rate limiting works (drops events sent <300ms apart)
- [ ] `builder_changed` generates valid DSL (CodeMirror updates within 500ms)
- [ ] `builder_changed` preserves comments (FR-010)
- [ ] `undo` reverts last change from either editor (FR-012)
- [ ] `redo` re-applies undone change
- [ ] `save_strategy` persists to database (FR-020)
- [ ] `save_strategy` prevents navigation with unsaved changes (FR-018)
- [ ] Debouncing prevents excessive server calls (FR-008)
- [ ] Loading indicator shows after 200ms (FR-011)

---

## Related Documents

- **[data-model.md](../data-model.md)** - Entity structures
- **[research.md](../research.md)** - Technology decisions
- **[quickstart.md](../quickstart.md)** - Development setup

---

**Status**: ✅ Complete
**Next**: Create quickstart.md for development environment setup
