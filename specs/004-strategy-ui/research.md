# Research: Strategy Registration and Validation UI

**Feature**: 004-strategy-ui
**Date**: 2026-02-08
**Phase**: 0 (Research & Technical Decisions)

## Overview

This document captures technical research and design decisions for implementing a Phoenix LiveView-based UI for strategy registration, validation, and management.

---

## 1. Form Validation Architecture

### Decision
Use Phoenix LiveView 1.0+ with server-side validation via Ecto changesets, real-time validation on `phx-change`, and `phx-debounce="blur"` for expensive operations.

### Rationale
- Server-driven validation ensures consistency between frontend/backend
- LiveView's diff-based updates provide instant feedback
- No client-side duplication
- Existing codebase already uses LiveView (paper_trading_live.ex pattern)
- Meets spec requirement SC-002 (validation <1 second)

### Implementation Pattern
```elixir
def handle_event("validate", %{"strategy" => params}, socket) do
  changeset =
    %Strategy{}
    |> Strategies.change_strategy(params)
    |> Map.put(:action, :validate)

  {:noreply, assign(socket, :form, to_form(changeset))}
end
```

**Key Points:**
- Use `to_form/1` for form state management
- Set changeset action to `:validate` to show errors during typing
- Apply `phx-debounce="blur"` on expensive validations (uniqueness checks)
- Leverage existing DSL validators for strategy content validation

---

## 2. User Authentication & Authorization

### Decision
Implement `mix phx.gen.auth` with user scoping for all strategy resources.

### Rationale
- Official Phoenix authentication solution (recommended since Phoenix 1.5+)
- Includes LiveView support out-of-the-box
- Follows security best practices
- Codebase currently has no authentication - foundational requirement
- Spec FR-018a explicitly requires user-scoped strategies

### Database Changes
```elixir
# Add to strategies table
add :user_id, references(:users, on_delete: :delete_all, type: :binary_id), null: false
create index(:strategies, [:user_id])

# Update unique constraint
drop unique_index(:strategies, [:name, :version])
create unique_index(:strategies, [:user_id, :name, :version])
```

### Context Scoping Pattern
```elixir
def list_strategies(user, opts \\ []) do
  from(s in Strategy, where: s.user_id == ^user.id)
  |> apply_filters(opts)
  |> Repo.all()
end
```

**Key Points:**
- All strategy queries MUST filter by `user_id`
- Authentication required for all `/strategies/*` routes
- Use `pipe_through [:browser, :require_authenticated_user]` in router

---

## 3. Version Conflict Detection

### Decision
Optimistic locking using `lock_version` integer field with `Ecto.Changeset.optimistic_lock/3`.

### Rationale
- Ideal for rare concurrent edits (typical for strategy editing)
- Built-in Ecto support
- Prevents silent data loss from last-write-wins
- Low overhead (just counter increment)
- Meets spec requirement FR-014a

### Implementation
```elixir
# In migration
add :lock_version, :integer, default: 1, null: false

# In changeset
def changeset(strategy, attrs) do
  strategy
  |> cast(attrs, [...])
  |> optimistic_lock(:lock_version)
end

# In LiveView - handle conflicts
rescue
  Ecto.StaleEntryError ->
    latest = Strategies.get_strategy(id, user)
    {:noreply,
     socket
     |> assign(:strategy, latest)
     |> put_flash(:error, "Strategy modified elsewhere. Form reloaded.")}
end
```

**User Experience:**
1. User A opens strategy (lock_version: 1)
2. User B saves changes (lock_version: 2)
3. User A tries to save → `Ecto.StaleEntryError`
4. System reloads latest, warns user
5. User A reapplies changes

---

## 4. Uniqueness Validation

### Decision
Two-phase validation: `unsafe_validate_unique/4` for UX + `unique_constraint/3` for safety.

### Rationale
- `unsafe_validate_unique` provides immediate feedback
- `unique_constraint` prevents race conditions at DB level
- Debouncing reduces database load
- Best of both: good UX + data integrity
- Meets spec requirement FR-018

### Implementation
```elixir
def changeset(strategy, attrs) do
  strategy
  |> cast(attrs, [...])
  |> unsafe_validate_unique([:user_id, :name, :version], Repo,
      message: "A strategy with this name already exists")
  |> unique_constraint([:user_id, :name, :version])
end
```

```heex
<.input field={@form[:name]} type="text" label="Name"
        phx-debounce="blur" />
```

**Key Points:**
- Validation only runs on blur (not every keystroke)
- Scoped to user + version (users can have duplicate names, just not same version)
- Database unique index provides final safety net

---

## 5. Component Architecture

### Decision
Function components for UI elements, LiveComponents ONLY for stateful builders (indicators, conditions).

### Rationale
- Function components are simpler, stateless, easier to test
- LiveComponents add complexity - avoid unless state/events needed
- Follows existing codebase pattern (core_components.ex)
- Phoenix team guidance: "LiveComponents are best avoided if possible"

### When to Use Each

| Use Case | Component Type |
|----------|---------------|
| Display strategy card | Function Component |
| Reusable buttons, badges | Function Component |
| Basic form inputs | Function Component |
| Indicator builder (add/remove, state) | LiveComponent |
| Condition builder (dynamic rules) | LiveComponent |

### Structure
```text
lib/trading_strategy_web/
├── components/
│   ├── core_components.ex          # Existing: buttons, inputs, etc.
│   └── strategy_components.ex      # NEW: strategy_card, status_badge
└── live/
    └── strategy_live/
        ├── index.ex                 # Parent LiveView
        ├── form.ex                  # Parent LiveView
        ├── show.ex                  # Parent LiveView
        ├── indicator_builder.ex     # LiveComponent (stateful)
        └── condition_builder.ex     # LiveComponent (stateful)
```

**Key Points:**
- Parent LiveView owns master state (strategy changeset)
- LiveComponents manage own UI state (selected items, expanded panels)
- LiveComponents send messages to parent for strategy changes
- Keep state management clear and unidirectional

---

## 6. Autosave & Data Loss Prevention

### Decision
30-second periodic autosave + LiveView's built-in form auto-recovery.

### Rationale
- Meets spec requirement SC-006 (zero data loss)
- LiveView automatically recovers form values after reconnection
- Periodic save catches long editing sessions
- Saves as draft status

### Implementation
```elixir
def mount(_params, _session, socket) do
  if connected?(socket) do
    Process.send_after(self(), :autosave, 30_000)
  end
  # ...
end

def handle_info(:autosave, socket) do
  if socket.assigns.form.source.changes != %{} do
    save_draft(socket)
  end
  Process.send_after(self(), :autosave, 30_000)
  {:noreply, socket}
end
```

**Key Points:**
- Only save if form has changes
- Save as draft status (user can explicitly publish)
- Leverage LiveView's built-in recovery for disconnections
- Consider localStorage for additional safety

---

## 7. Strategy Status Management

### Decision
Four-state lifecycle: `draft` → `active` → `inactive` → `archived`.

### Rationale
- Prevents accidental activation of incomplete strategies
- Allows soft deletion (archived) for audit trail
- Meets spec requirement FR-020 (prevent editing active strategies)

### State Transitions
```
draft     → active      (require: valid DSL, risk params present)
active    → inactive    (anytime, stops trading)
inactive  → active      (anytime, resumes trading)
active    → archived    (disallowed - must deactivate first)
draft     → archived    (allowed)
inactive  → archived    (allowed)
```

### Validation Rules
- **draft**: Can edit freely, validation shows errors but doesn't block save
- **active**: Cannot edit (show error per FR-020), cannot delete
- **inactive**: Can edit, creates new version (FR-014)
- **archived**: Read-only, cannot unarchive (soft delete)

---

## 8. DSL Content Handling

### Decision
Reuse existing DSL validators, support both YAML and TOML formats.

### Rationale
- DSL validation logic already exists (`TradingStrategy.Strategies.DSL.Validator`)
- Current schema supports `format` field (yaml/toml)
- Parser handles both formats
- UI just needs to wrap validation in LiveView events

### Integration Pattern
```elixir
def handle_event("validate", %{"strategy" => params}, socket) do
  # Standard Ecto validation + DSL validation happens automatically
  # in Strategy.changeset/2 via validate_dsl_content/1
  changeset = Strategies.change_strategy(%Strategy{}, params)
  {:noreply, assign(socket, :form, to_form(changeset))}
end
```

**Key Points:**
- DSL validation happens server-side in changeset
- Syntax test (FR-015) reuses parser without executing trades
- Validation errors map to form fields via changeset
- UI provides syntax highlighting for DSL content (future enhancement)

---

## 9. Performance Targets

### Requirements from Spec
- **SC-001**: Strategy registration in <5 minutes
- **SC-002**: Validation errors in <1 second
- **SC-004**: Load 100+ strategies in <2 seconds
- **SC-005**: Syntax test in <3 seconds

### Optimization Strategies
- Use database indexes on `user_id`, `status`, `name`
- Pagination for strategy lists (50 per page default)
- Debounce validation events
- Stream strategy list via LiveView Streams for efficient updates
- Cache parsed DSL results for syntax tests

### Monitoring
- Add Telemetry events for validation latency
- Track form completion time
- Monitor autosave frequency

---

## 10. Testing Strategy

### Test Types
1. **Unit Tests**: Strategy context functions (scoping, versioning)
2. **LiveView Tests**: Real-time validation, form submission, error display
3. **Integration Tests**: End-to-end strategy creation flow
4. **Contract Tests**: DSL validation integration

### Example Test
```elixir
test "validates required fields in real-time", %{conn: conn} do
  {:ok, view, _html} = live(conn, ~p"/strategies/new")

  view
  |> form("#strategy-form", strategy: %{name: ""})
  |> render_change()

  assert view |> element("#strategy-form") |> render() =~ "can&#39;t be blank"
end
```

**Key Points:**
- Use `async: true` for parallel test execution
- Test version conflict scenarios
- Test uniqueness validation with database fixtures
- Test autosave behavior

---

## Summary of Key Decisions

| Area | Technology/Pattern | Primary Benefit |
|------|-------------------|----------------|
| **Form Validation** | LiveView + server-side changesets | Real-time UX, security, consistency |
| **Authentication** | `phx.gen.auth` | Best practices, LiveView support |
| **Version Conflicts** | Optimistic locking (`lock_version`) | Data loss prevention |
| **Uniqueness** | `unsafe_validate_unique` + DB constraint | UX + integrity |
| **Components** | Function components + selective LiveComponents | Simplicity, maintainability |
| **Autosave** | 30s periodic + LiveView recovery | Zero data loss |
| **Status Management** | Four-state lifecycle | Safe activation, audit trail |
| **DSL Handling** | Reuse existing validators | Consistency with backend |

---

## Next Steps (Phase 1: Design & Contracts)

1. Generate data model from spec entities
2. Define LiveView routes and page structure
3. Create API contracts for validation endpoints
4. Update quickstart guide with setup instructions
5. Run agent context update script
