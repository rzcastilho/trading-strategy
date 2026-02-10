# LiveView Routes Contract

**Feature**: 004-strategy-ui
**Date**: 2026-02-08

## Overview

Defines the LiveView routes, their responsibilities, and the data they handle.

---

## Routes

### 1. Strategy List (`/strategies`)

**LiveView Module**: `TradingStrategyWeb.StrategyLive.Index`

**Purpose**: Display paginated list of user's strategies with filtering and sorting.

**Route Definition**:
```elixir
# In router.ex
scope "/", TradingStrategyWeb do
  pipe_through [:browser, :require_authenticated_user]

  live "/strategies", StrategyLive.Index, :index
end
```

**Mount Parameters**:
```elixir
# URL: /strategies?status=active&page=2
%{
  "status" => "active" | "draft" | "inactive" | "archived" | nil,
  "page" => integer string,
  "sort_by" => "name" | "updated_at" | "created_at",
  "sort_order" => "asc" | "desc"
}
```

**Socket Assigns**:
```elixir
%{
  current_user: %User{},
  strategies: [%Strategy{}],
  page: 1,
  page_size: 50,
  total_count: integer(),
  filters: %{status: string()},
  sort_by: atom(),
  sort_order: :asc | :desc
}
```

**Events**:
- `"filter"` - Update status filter
- `"sort"` - Change sort column/order
- `"paginate"` - Load next/previous page
- `"delete_strategy"` - Soft delete (archive) strategy
- `"duplicate_strategy"` - Clone strategy

**Success Criteria**:
- Load time <2 seconds for 100+ strategies (SC-004)
- Real-time updates via PubSub when strategies created/updated

---

### 2. New Strategy Form (`/strategies/new`)

**LiveView Module**: `TradingStrategyWeb.StrategyLive.Form`

**Purpose**: Create new strategy with real-time validation.

**Route Definition**:
```elixir
live "/strategies/new", StrategyLive.Form, :new
```

**Mount Parameters**: None (blank form)

**Socket Assigns**:
```elixir
%{
  current_user: %User{},
  strategy: nil,
  form: %Phoenix.HTML.Form{},
  indicators: [],
  entry_conditions: [],
  exit_conditions: [],
  loading: false,
  metadata: %{
    autosave_enabled: true,
    last_autosave: nil,
    unsaved_changes: false
  }
}
```

**Events**:
- `"validate"` - Real-time form validation
- `"save"` - Submit strategy
- `"save_draft"` - Save as draft
- `"test_syntax"` - Run DSL syntax test
- `"indicators_changed"` - From LiveComponent
- `"conditions_changed"` - From LiveComponent

**Navigation**:
- On success: Navigate to `/strategies/:id`
- On cancel: Navigate to `/strategies`

**Success Criteria**:
- Validation response <1 second (SC-002)
- Form completion <5 minutes (SC-001)
- Autosave every 30 seconds

---

### 3. Edit Strategy Form (`/strategies/:id/edit`)

**LiveView Module**: `TradingStrategyWeb.StrategyLive.Form`

**Purpose**: Edit existing strategy with version conflict detection.

**Route Definition**:
```elixir
live "/strategies/:id/edit", StrategyLive.Form, :edit
```

**Mount Parameters**:
```elixir
%{"id" => strategy_id}
```

**Socket Assigns** (same as new, plus):
```elixir
%{
  strategy: %Strategy{},  # Existing strategy loaded
  original_lock_version: integer(),  # For conflict detection
  # ... rest same as :new
}
```

**Events** (same as new, plus):
- `"reload_latest"` - Reload after version conflict
- `"create_new_version"` - Save as new version

**Version Conflict Handling**:
```elixir
rescue
  Ecto.StaleEntryError ->
    # Reload latest version
    # Show warning to user
    # Offer to reapply changes
```

**Success Criteria**:
- Detect 100% of concurrent edits (SC via lock_version)
- Update time <3 minutes (SC-008)

---

### 4. Strategy Detail View (`/strategies/:id`)

**LiveView Module**: `TradingStrategyWeb.StrategyLive.Show`

**Purpose**: Display read-only strategy details with parsed DSL visualization.

**Route Definition**:
```elixir
live "/strategies/:id", StrategyLive.Show, :show
```

**Mount Parameters**:
```elixir
%{"id" => strategy_id}
```

**Socket Assigns**:
```elixir
%{
  current_user: %User{},
  strategy: %Strategy{} | nil,
  parsed_dsl: %{
    indicators: [...],
    entry_conditions: [...],
    exit_conditions: [...],
    risk_params: %{}
  },
  versions: [%Strategy{}],  # All versions of this strategy
  backtest_results: [...] | nil,
  can_edit?: boolean(),
  can_activate?: boolean()
}
```

**Events**:
- `"activate"` - Change status to active
- `"deactivate"` - Change status to inactive
- `"archive"` - Soft delete
- `"duplicate"` - Clone strategy
- `"view_version"` - Switch to different version

**Authorization**:
- 404 if strategy not found or belongs to different user
- Display "Cannot edit" message if status is active/archived

**Success Criteria**:
- Load time <1 second
- Correctly parse and display DSL structure

---

## Shared LiveComponents

### IndicatorBuilderComponent

**Module**: `TradingStrategyWeb.StrategyLive.IndicatorBuilderComponent`

**Purpose**: Stateful component for adding/removing/configuring indicators.

**Props**:
```elixir
%{
  id: "indicator-builder",
  selected_indicators: [%{
    id: string(),
    type: string(),
    params: %{}
  }]
}
```

**Events** (phx-target={@myself}):
- `"add_indicator"` - Add new indicator
- `"remove_indicator"` - Remove indicator
- `"update_params"` - Modify indicator parameters
- `"validate_params"` - Check parameter validity

**Messages to Parent**:
- `{:indicators_changed, [%{}]}` - Notify parent of changes

---

### ConditionBuilderComponent

**Module**: `TradingStrategyWeb.StrategyLive.ConditionBuilderComponent`

**Purpose**: Stateful component for building entry/exit conditions with logical operators.

**Props**:
```elixir
%{
  id: "entry-condition-builder",
  condition_type: :entry | :exit,
  conditions: [%{
    id: string(),
    left: string(),
    operator: string(),
    right: string()
  }],
  logical_operator: "AND" | "OR"
}
```

**Events**:
- `"add_condition"` - Add new condition rule
- `"remove_condition"` - Remove condition
- `"update_condition"` - Modify condition
- `"toggle_logical_operator"` - Switch AND/OR

**Messages to Parent**:
- `{:conditions_changed, type, conditions}` - Notify parent

---

## PubSub Topics

### Strategy Updates

**Topic**: `"strategies:user:#{user_id}"`

**Events**:
- `{:strategy_created, strategy_id}`
- `{:strategy_updated, strategy_id}`
- `{:strategy_deleted, strategy_id}`

**Subscribers**:
- `StrategyLive.Index` - Refresh list
- `StrategyLive.Show` - Reload if viewing updated strategy

**Usage**:
```elixir
# In Strategies context after create/update
Phoenix.PubSub.broadcast(
  TradingStrategy.PubSub,
  "strategies:user:#{user_id}",
  {:strategy_created, strategy.id}
)

# In LiveView
def mount(_params, _session, socket) do
  if connected?(socket) do
    Phoenix.PubSub.subscribe(
      TradingStrategy.PubSub,
      "strategies:user:#{socket.assigns.current_user.id}"
    )
  end
  # ...
end

def handle_info({:strategy_created, _id}, socket) do
  # Reload strategies list
  {:noreply, reload_strategies(socket)}
end
```

---

## Error Handling

### 404 Not Found
```elixir
# Strategy doesn't exist or doesn't belong to user
{:noreply,
 socket
 |> put_flash(:error, "Strategy not found")
 |> push_navigate(to: ~p"/strategies")}
```

### 403 Forbidden
```elixir
# Attempt to edit active strategy
{:noreply,
 socket
 |> put_flash(:error, "Cannot edit active strategy. Deactivate it first.")
 |> push_navigate(to: ~p"/strategies/#{strategy.id}")}
```

### Version Conflict
```elixir
# Optimistic locking failure
rescue
  Ecto.StaleEntryError ->
    {:noreply,
     socket
     |> reload_latest_version()
     |> put_flash(:error, "Strategy was modified elsewhere. Form reloaded with latest version.")}
```

### Validation Errors
```elixir
# Changeset errors
{:error, changeset} ->
  {:noreply, assign(socket, :form, to_form(changeset))}
```

---

## Authentication & Authorization

### Authentication
```elixir
# In router.ex
pipe_through [:browser, :require_authenticated_user]
```

### Authorization (Per-Route)
```elixir
# In LiveView mount/3
def mount(%{"id" => id}, _session, socket) do
  case Strategies.get_strategy(id, socket.assigns.current_user) do
    nil ->
      {:ok,
       socket
       |> put_flash(:error, "Strategy not found")
       |> redirect(to: ~p"/strategies")}

    strategy ->
      {:ok, assign(socket, :strategy, strategy)}
  end
end
```

---

## Performance Targets

| Route | Target | Measurement |
|-------|--------|-------------|
| `/strategies` | <2s load (100+ strategies) | Time to render |
| `/strategies/new` | <1s validation response | Time from input to error display |
| `/strategies/:id/edit` | <1s load | Time to mount |
| `/strategies/:id` | <1s load | Time to mount |

---

## Navigation Flow

```
/strategies (list)
  ├─> /strategies/new (create)
  │     └─> /strategies/:id (view after create)
  ├─> /strategies/:id (view details)
  │     ├─> /strategies/:id/edit (edit)
  │     │     └─> /strategies/:id (view after save)
  │     └─> /strategies/:id?version=2 (view specific version)
  └─> /strategies?status=active (filtered list)
```

---

## Testing Contracts

### LiveView Tests
```elixir
# Mount test
test "mounts strategy list for authenticated user", %{conn: conn, user: user} do
  {:ok, view, html} = live(conn, ~p"/strategies")
  assert html =~ "Strategies"
end

# Event test
test "validates strategy name in real-time", %{conn: conn, user: user} do
  {:ok, view, _html} = live(conn, ~p"/strategies/new")

  view
  |> form("#strategy-form", strategy: %{name: ""})
  |> render_change()

  assert view |> element("#strategy-form") |> render() =~ "can&#39;t be blank"
end

# Navigation test
test "redirects to detail page after save", %{conn: conn, user: user} do
  {:ok, view, _html} = live(conn, ~p"/strategies/new")

  view
  |> form("#strategy-form", strategy: valid_attrs())
  |> render_submit()

  assert_redirect(view, ~p"/strategies/#{strategy.id}")
end
```

---

## Summary

**Total Routes**: 4 LiveView routes
- List: `/strategies`
- Create: `/strategies/new`
- Edit: `/strategies/:id/edit`
- Show: `/strategies/:id`

**Total Components**: 2 stateful LiveComponents
- IndicatorBuilderComponent
- ConditionBuilderComponent

**PubSub Integration**: Real-time updates for strategy changes

**Authentication**: Required for all routes via `require_authenticated_user` plug

**Authorization**: User can only access their own strategies (enforced in context layer)
