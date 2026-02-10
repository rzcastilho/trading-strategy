# Validation API Contract

**Feature**: 004-strategy-ui
**Date**: 2026-02-08

## Overview

Defines the contract between LiveView UI and the backend validation system. All validation happens server-side through Ecto changesets and DSL validators.

---

## Validation Flow

```
User Input (LiveView)
    │
    ├─> phx-change="validate"
    │     │
    │     └─> handle_event("validate", params, socket)
    │           │
    │           └─> Strategies.change_strategy(params)
    │                 │
    │                 └─> Strategy.changeset/2
    │                       │
    │                       ├─> Built-in Ecto validations
    │                       ├─> unsafe_validate_unique (name)
    │                       ├─> validate_dsl_content/1
    │                       │     └─> DSL.Parser.parse/2
    │                       │           └─> DSL.Validator.validate/1
    │                       │
    │                       └─> Returns changeset with errors
    │
    └─> Display errors in form
```

---

## Validation Levels

### Level 1: Field-Level Validation (Instant)

**Triggered**: On `phx-change` event (as user types)

**Validations**:
- Presence checks (required fields)
- Length constraints
- Format checks (email, timeframe enums)
- Type validations

**Response Time**: <100ms (in-memory validation)

**Example**:
```elixir
def changeset(strategy, attrs) do
  strategy
  |> cast(attrs, [:name, :description, ...])
  |> validate_required([:name, :trading_pair, :timeframe])
  |> validate_length(:name, min: 3, max: 200)
  |> validate_length(:description, max: 1000)
  |> validate_inclusion(:format, ["yaml", "toml"])
  |> validate_inclusion(:timeframe, ~w(1m 5m 15m 30m 1h 4h 1d 1w))
end
```

### Level 2: Database Validation (Debounced)

**Triggered**: On `phx-debounce="blur"` (when user leaves field)

**Validations**:
- Uniqueness checks (strategy name)
- Foreign key existence

**Response Time**: <500ms (single database query)

**Example**:
```elixir
def changeset(strategy, attrs) do
  strategy
  |> cast(...)
  # ... level 1 validations
  |> unsafe_validate_unique([:user_id, :name, :version], Repo,
      message: "You already have a strategy with this name and version")
  |> unique_constraint([:user_id, :name, :version])
end
```

### Level 3: DSL Content Validation (On Submit)

**Triggered**: On form submit or explicit "Test Syntax" button

**Validations**:
- DSL parsing (YAML/TOML syntax)
- Indicator parameter validation
- Entry/exit condition validation
- Risk parameter validation
- Logical consistency checks

**Response Time**: <1 second (SC-002)

**Example**:
```elixir
defp validate_dsl_content(changeset) do
  content = get_field(changeset, :content)
  format = get_field(changeset, :format)

  case {content, format} do
    {nil, _} -> changeset
    {_, nil} -> changeset
    {content, format} when format in ["yaml", "toml"] ->
      format_atom = String.to_existing_atom(format)

      case DSL.Parser.parse(content, format_atom) do
        {:ok, parsed} ->
          validate_parsed_strategy(changeset, parsed)

        {:error, reason} ->
          add_error(changeset, :content, "Failed to parse #{format}: #{reason}")
      end
  end
end

defp validate_parsed_strategy(changeset, parsed) do
  case DSL.Validator.validate(parsed) do
    {:ok, _validated} ->
      changeset

    {:error, errors} when is_list(errors) ->
      Enum.reduce(errors, changeset, fn error, acc ->
        add_error(acc, :content, error)
      end)

    {:error, error} ->
      add_error(changeset, :content, error)
  end
end
```

---

## Validation Response Format

### Success (No Errors)

**Changeset**:
```elixir
%Ecto.Changeset{
  valid?: true,
  errors: [],
  changes: %{
    name: "My Strategy",
    description: "...",
    # ... other changed fields
  }
}
```

**UI Display**: No error messages, green checkmarks (optional)

### Validation Errors

**Changeset**:
```elixir
%Ecto.Changeset{
  valid?: false,
  errors: [
    name: {"can't be blank", [validation: :required]},
    timeframe: {"is invalid", [validation: :inclusion, enum: ~w(1m 5m 1h 1d)]},
    content: {"Failed to parse yaml: Invalid YAML syntax at line 5", []}
  ],
  changes: %{...}
}
```

**UI Display**:
```heex
<.input field={@form[:name]} type="text" label="Name" />
<!-- Error automatically displayed below by Phoenix.Component -->
```

**Error Message Format**:
- Field-level errors appear inline below input
- Multiple errors per field stacked vertically
- Global errors (DSL parsing) appear at top of form

---

## Validation Error Types

### 1. Required Field Errors

**Validation**: `validate_required/2`

**Error Tuple**: `{field, {"can't be blank", [validation: :required]}}`

**User Message**: "Name can't be blank"

**Example**:
```elixir
|> validate_required([:name, :trading_pair, :timeframe, :content])
```

### 2. Length Errors

**Validation**: `validate_length/3`

**Error Tuple**: `{field, {"should be at least %{count} character(s)", [...]}}`

**User Messages**:
- "Name should be at least 3 characters"
- "Description should be at most 1000 characters"

**Example**:
```elixir
|> validate_length(:name, min: 3, max: 200)
|> validate_length(:description, max: 1000)
```

### 3. Inclusion Errors (Invalid Enum)

**Validation**: `validate_inclusion/3`

**Error Tuple**: `{field, {"is invalid", [validation: :inclusion, enum: [...]]}}`

**User Message**: "Timeframe is invalid. Must be one of: 1m, 5m, 15m, 30m, 1h, 4h, 1d, 1w"

**Example**:
```elixir
|> validate_inclusion(:timeframe, ~w(1m 5m 15m 30m 1h 4h 1d 1w))
```

### 4. Uniqueness Errors

**Validation**: `unsafe_validate_unique/4` + `unique_constraint/3`

**Error Tuple**: `{field, {"has already been taken", [validation: :unsafe_unique]}}`

**User Message**: "You already have a strategy named 'RSI Strategy' (version 1)"

**Example**:
```elixir
|> unsafe_validate_unique([:user_id, :name, :version], Repo)
|> unique_constraint([:user_id, :name, :version])
```

### 5. DSL Parsing Errors

**Validation**: Custom `validate_dsl_content/1`

**Error Tuple**: `{:content, {"Failed to parse yaml: Invalid YAML syntax at line 5", []}}`

**User Messages**:
- "Failed to parse yaml: Invalid YAML syntax at line 5"
- "Failed to parse toml: Missing required key 'indicators'"

**Example**:
```elixir
case DSL.Parser.parse(content, :yaml) do
  {:ok, parsed} -> changeset
  {:error, reason} ->
    add_error(changeset, :content, "Failed to parse yaml: #{reason}")
end
```

### 6. DSL Validation Errors

**Validation**: `DSL.Validator.validate/1`

**Error Tuples**:
```elixir
{:content, {"Indicator 'sma' missing required parameter 'period'", []}}
{:content, {"Entry condition references undefined indicator 'ema_fast'", []}}
{:content, {"Risk parameter 'max_position_size' must be between 0 and 100", []}}
```

**User Messages**: Specific errors from DSL validator with line/indicator context

---

## Syntax Testing API

### Purpose
Provide "Test Syntax" button that validates DSL without saving (FR-015).

### Function Signature
```elixir
@spec test_strategy_syntax(String.t(), :yaml | :toml) ::
  {:ok, parsed_strategy} | {:error, [String.t()]}

def test_strategy_syntax(content, format) do
  with {:ok, parsed} <- DSL.Parser.parse(content, format),
       {:ok, validated} <- DSL.Validator.validate(parsed) do
    {:ok, %{
      parsed: validated,
      summary: %{
        indicators: length(validated.indicators),
        entry_conditions: length(validated.entry_conditions),
        exit_conditions: length(validated.exit_conditions),
        risk_params: Map.keys(validated.risk_params)
      }
    }}
  else
    {:error, reason} when is_binary(reason) ->
      {:error, [reason]}

    {:error, reasons} when is_list(reasons) ->
      {:error, reasons}
  end
end
```

### LiveView Integration
```elixir
def handle_event("test_syntax", %{"content" => content, "format" => format}, socket) do
  format_atom = String.to_existing_atom(format)

  case Strategies.test_strategy_syntax(content, format_atom) do
    {:ok, result} ->
      {:noreply,
       socket
       |> assign(:syntax_test_result, result)
       |> put_flash(:info, "Syntax valid! #{result.summary.indicators} indicators detected.")}

    {:error, errors} ->
      {:noreply,
       socket
       |> assign(:syntax_test_errors, errors)
       |> put_flash(:error, "Syntax errors found")}
  end
end
```

### Response Format

**Success**:
```json
{
  "parsed": { /* full parsed structure */ },
  "summary": {
    "indicators": 3,
    "entry_conditions": 2,
    "exit_conditions": 2,
    "risk_params": ["max_position_size", "stop_loss_pct", "take_profit_pct"]
  }
}
```

**Failure**:
```json
{
  "errors": [
    "Indicator 'sma' missing required parameter 'period'",
    "Entry condition references undefined indicator 'ema_fast'",
    "Risk parameter 'max_position_size' must be between 0 and 100"
  ]
}
```

**Performance**: <3 seconds for strategies with up to 10 indicators (SC-005)

---

## Activation Validation

### Purpose
Prevent activation of strategies that haven't been backtested (per Constitution Principle II).

### Function Signature
```elixir
@spec can_activate?(Strategy.t()) :: {:ok, :allowed} | {:error, String.t()}

def can_activate?(%Strategy{} = strategy) do
  with :ok <- check_valid_dsl(strategy),
       :ok <- check_risk_params_present(strategy),
       :ok <- check_backtest_results_exist(strategy) do
    {:ok, :allowed}
  end
end

defp check_valid_dsl(strategy) do
  case DSL.Parser.parse(strategy.content, String.to_existing_atom(strategy.format)) do
    {:ok, parsed} ->
      case DSL.Validator.validate(parsed) do
        {:ok, _} -> :ok
        {:error, _} -> {:error, "Strategy has validation errors"}
      end
    {:error, _} -> {:error, "Strategy has parsing errors"}
  end
end

defp check_risk_params_present(strategy) do
  # Parse DSL and verify risk_params section exists
  # ...
  :ok
end

defp check_backtest_results_exist(strategy) do
  case Backtesting.get_latest_results(strategy.id) do
    nil -> {:error, "Strategy must be backtested before activation"}
    results -> :ok
  end
end
```

### LiveView Integration
```elixir
def handle_event("activate", _params, socket) do
  strategy = socket.assigns.strategy

  case Strategies.can_activate?(strategy) do
    {:ok, :allowed} ->
      case Strategies.activate_strategy(strategy) do
        {:ok, strategy} ->
          {:noreply,
           socket
           |> assign(:strategy, strategy)
           |> put_flash(:info, "Strategy activated successfully")}

        {:error, changeset} ->
          {:noreply, assign(socket, :form, to_form(changeset))}
      end

    {:error, reason} ->
      {:noreply, put_flash(socket, :error, reason)}
  end
end
```

---

## Validation Debouncing

### Strategy
- **Instant validation**: Presence, length, format (no debounce)
- **Debounced validation**: Uniqueness, database queries (`phx-debounce="blur"`)
- **On-demand validation**: DSL parsing/syntax testing (button click)

### Implementation
```heex
<!-- Instant validation -->
<.input field={@form[:description]} type="textarea" label="Description" />

<!-- Debounced validation (on blur) -->
<.input field={@form[:name]} type="text" label="Name"
        phx-debounce="blur" required />

<!-- On-demand validation -->
<.button type="button" phx-click="test_syntax">Test Syntax</.button>
```

### Performance Impact
- Instant validation: ~10ms (in-memory)
- Debounced validation: ~100-500ms (1 DB query)
- DSL validation: ~500ms-3s (parsing + validation)

---

## Error Recovery

### Stale Data Handling
```elixir
rescue
  Ecto.StaleEntryError ->
    # Reload latest version
    latest = Strategies.get_strategy(strategy.id, user)
    {:noreply,
     socket
     |> assign(:strategy, latest)
     |> assign(:form, to_form(Strategies.change_strategy(latest)))
     |> put_flash(:error, "Strategy modified elsewhere. Form reloaded.")}
end
```

### Network Errors
- LiveView automatically reconnects
- Form state preserved via built-in form recovery
- Autosave provides additional safety

### Database Constraints
- Unique constraint violations caught by `unique_constraint/3`
- Foreign key violations caught by `foreign_key_constraint/3`
- User-friendly error messages displayed

---

## Testing Validation

### Unit Tests
```elixir
describe "changeset/2" do
  test "validates required fields" do
    changeset = Strategy.changeset(%Strategy{}, %{})
    assert %{name: ["can't be blank"]} = errors_on(changeset)
  end

  test "validates name length" do
    changeset = Strategy.changeset(%Strategy{}, %{name: "ab"})
    assert %{name: ["should be at least 3 character(s)"]} = errors_on(changeset)
  end

  test "validates uniqueness" do
    user = user_fixture()
    strategy_fixture(user: user, name: "Test")

    changeset = Strategy.changeset(%Strategy{}, %{
      user_id: user.id,
      name: "Test",
      version: 1,
      # ... other required fields
    })

    assert {:error, changeset} = Repo.insert(changeset)
    assert %{name: ["has already been taken"]} = errors_on(changeset)
  end
end
```

### LiveView Tests
```elixir
test "displays validation errors in real-time", %{conn: conn, user: user} do
  {:ok, view, _html} = live(conn, ~p"/strategies/new")

  # Trigger validation with invalid data
  view
  |> form("#strategy-form", strategy: %{name: "ab"})  # Too short
  |> render_change()

  # Check error message displayed
  assert view |> element("#strategy-form") |> render() =~
    "should be at least 3 character"
end
```

---

## Summary

**Validation Levels**: 3 tiers (instant, debounced, on-submit)

**Response Times**:
- Instant: <100ms
- Debounced: <500ms
- DSL: <3 seconds

**Error Types**: 6 categories (required, length, inclusion, uniqueness, DSL parsing, DSL validation)

**Special Features**:
- Syntax testing without save
- Activation gate (requires backtest)
- Version conflict detection
- Optimistic locking

**Performance**: Meets all spec success criteria (SC-002, SC-005)
