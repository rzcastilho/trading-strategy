# Quickstart: Strategy Registration and Validation UI

**Feature**: 004-strategy-ui
**Date**: 2026-02-08
**For**: Developers implementing this feature

## Overview

This guide walks through implementing the Strategy Registration and Validation UI feature from setup to deployment. Follow these steps in order for successful implementation.

---

## Prerequisites

Before starting, ensure:
- [x] Elixir 1.17+ and OTP 27+ installed
- [x] Phoenix 1.7+ project set up (already exists)
- [x] PostgreSQL running with TimescaleDB extension
- [x] Existing Strategy DSL library (Feature 001) functional
- [x] Existing `strategies` table with DSL validation logic

---

## Phase 1: Authentication System (Days 1-2)

### Step 1.1: Generate Authentication

```bash
cd /path/to/trading-strategy

# Generate phx.gen.auth authentication system
mix phx.gen.auth Accounts User users

# This creates:
# - lib/trading_strategy/accounts.ex (context)
# - lib/trading_strategy/accounts/user.ex (schema)
# - lib/trading_strategy_web/user_auth.ex (plugs)
# - priv/repo/migrations/*_create_users_auth_tables.exs
# - LiveView pages for login/register/settings
# - Tests for all generated code
```

### Step 1.2: Run Migrations

```bash
mix ecto.migrate
```

**Result**: Creates `users`, `users_tokens` tables with authentication logic.

### Step 1.3: Verify Authentication

```bash
# Start server
mix phx.server

# Visit http://localhost:4000/users/register
# Create test account
# Verify login works
```

---

## Phase 2: Database Schema Updates (Day 2)

### Step 2.1: Create Migration for Strategy User Association

```bash
mix ecto.gen.migration add_user_fields_to_strategies
```

Edit the migration file:
```elixir
# priv/repo/migrations/XXXXXX_add_user_fields_to_strategies.exs
defmodule TradingStrategy.Repo.Migrations.AddUserFieldsToStrategies do
  use Ecto.Migration

  def change do
    alter table(:strategies) do
      add :user_id, references(:users, on_delete: :delete_all, type: :binary_id),
          null: false
      add :lock_version, :integer, default: 1, null: false
      add :metadata, :map
    end

    create index(:strategies, [:user_id])

    # Update unique constraint to scope by user
    drop_if_exists unique_index(:strategies, [:name, :version])
    create unique_index(:strategies, [:user_id, :name, :version])
  end
end
```

### Step 2.2: Run Migration

```bash
mix ecto.migrate
```

**Note**: If you have existing strategies in the database, you'll need to handle the NOT NULL constraint. Either:
- Delete test data: `mix ecto.reset` (loses all data)
- Or create a dummy user first and backfill

---

## Phase 3: Update Strategy Schema and Context (Days 3-4)

### Step 3.1: Update Strategy Schema

Edit `lib/trading_strategy/strategies/strategy.ex`:

```elixir
schema "strategies" do
  # Existing fields
  field :name, :string
  field :description, :string
  field :format, :string
  field :content, :string
  field :trading_pair, :string
  field :timeframe, :string
  field :status, :string, default: "draft"
  field :version, :integer, default: 1

  # NEW: Add these fields
  field :lock_version, :integer, default: 1
  field :metadata, :map

  # NEW: Add user relationship
  belongs_to :user, TradingStrategy.Accounts.User

  # Existing relationships (unchanged)
  has_many :indicators, TradingStrategy.Strategies.Indicator
  has_many :signals, TradingStrategy.Strategies.Signal
  has_many :trading_sessions, TradingStrategy.Backtesting.TradingSession
  has_many :positions, TradingStrategy.Orders.Position

  timestamps(type: :utc_datetime_usec)
end

def changeset(strategy, attrs) do
  strategy
  |> cast(attrs, [
      :name, :description, :format, :content,
      :trading_pair, :timeframe, :status, :version,
      :user_id, :metadata  # NEW
    ])
  |> validate_required([
      :name, :format, :content, :trading_pair,
      :timeframe, :user_id  # NEW: user_id required
    ])
  |> validate_length(:name, min: 3, max: 200)
  |> validate_inclusion(:format, ["yaml", "toml"])
  |> validate_inclusion(:status, ["draft", "active", "inactive", "archived"])
  |> validate_dsl_content()  # Existing validator
  |> foreign_key_constraint(:user_id)
  |> unsafe_validate_unique([:user_id, :name, :version], TradingStrategy.Repo)
  |> unique_constraint([:user_id, :name, :version])
  |> optimistic_lock(:lock_version)  # NEW: Optimistic locking
end
```

### Step 3.2: Update Strategies Context

Edit `lib/trading_strategy/strategies.ex`:

Add user-scoped functions:

```elixir
# Update existing functions to accept user parameter
def list_strategies(user, opts \\ []) do
  from(s in Strategy,
    where: s.user_id == ^user.id,
    order_by: [desc: s.inserted_at])
  |> maybe_filter_by_status(opts[:status])
  |> maybe_limit(opts[:limit] || 50)
  |> maybe_offset(opts[:offset] || 0)
  |> Repo.all()
end

def get_strategy(id, user) do
  Repo.one(from s in Strategy,
    where: s.id == ^id and s.user_id == ^user.id)
end

def create_strategy(attrs, user) do
  %Strategy{user_id: user.id}
  |> Strategy.changeset(attrs)
  |> Repo.insert()
  |> broadcast_strategy_change(:strategy_created, user.id)
end

def update_strategy(strategy, attrs, user) do
  # Verify ownership
  if strategy.user_id != user.id do
    {:error, :unauthorized}
  else
    strategy
    |> Strategy.changeset(attrs)
    |> Repo.update()
    |> broadcast_strategy_change(:strategy_updated, user.id)
  end
end

# Add new functions
def can_edit?(%Strategy{status: status}), do: status not in ["active", "archived"]

def can_activate?(strategy) do
  with :ok <- check_valid_dsl(strategy),
       :ok <- check_backtest_results_exist(strategy) do
    {:ok, :allowed}
  end
end

def test_strategy_syntax(content, format) do
  with {:ok, parsed} <- DSL.Parser.parse(content, format),
       {:ok, validated} <- DSL.Validator.validate(parsed) do
    {:ok, %{
      parsed: validated,
      summary: summarize_strategy(validated)
    }}
  end
end

# PubSub broadcasting
defp broadcast_strategy_change({:ok, strategy} = result, event, user_id) do
  Phoenix.PubSub.broadcast(
    TradingStrategy.PubSub,
    "strategies:user:#{user_id}",
    {event, strategy.id}
  )
  result
end

defp broadcast_strategy_change(error, _event, _user_id), do: error
```

### Step 3.3: Write Tests

```bash
# Run existing tests to ensure nothing broke
mix test

# Fix any failing tests due to new user_id requirement
# (Update fixtures to include user associations)
```

---

## Phase 4: Create LiveView Components (Days 5-7)

### Step 4.1: Create Directory Structure

```bash
mkdir -p lib/trading_strategy_web/live/strategy_live
mkdir -p lib/trading_strategy_web/components
```

### Step 4.2: Create Strategy Components

Create `lib/trading_strategy_web/components/strategy_components.ex`:

```elixir
defmodule TradingStrategyWeb.StrategyComponents do
  use Phoenix.Component
  import TradingStrategyWeb.CoreComponents

  attr :strategy, :map, required: true
  def strategy_card(assigns) do
    ~H"""
    <div class="bg-white rounded-lg shadow p-4 hover:shadow-lg transition-shadow">
      <h3 class="text-lg font-semibold text-gray-900"><%= @strategy.name %></h3>
      <p class="text-sm text-gray-600 mt-1 line-clamp-2"><%= @strategy.description %></p>
      <div class="mt-3 flex items-center gap-2">
        <.badge color={status_color(@strategy.status)}>
          <%= @strategy.status %>
        </.badge>
        <span class="text-xs text-gray-500">v<%= @strategy.version %></span>
        <span class="text-xs text-gray-500"><%= @strategy.trading_pair %></span>
      </div>
    </div>
    """
  end

  defp status_color("active"), do: :green
  defp status_color("draft"), do: :gray
  defp status_color("inactive"), do: :yellow
  defp status_color("archived"), do: :red
end
```

### Step 4.3: Create Index LiveView

Create `lib/trading_strategy_web/live/strategy_live/index.ex`:

```elixir
defmodule TradingStrategyWeb.StrategyLive.Index do
  use TradingStrategyWeb, :live_view
  alias TradingStrategy.Strategies

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket) do
      # Subscribe to strategy updates
      Phoenix.PubSub.subscribe(
        TradingStrategy.PubSub,
        "strategies:user:#{socket.assigns.current_user.id}"
      )
    end

    {:ok,
     socket
     |> assign(:page, 1)
     |> assign(:page_size, 50)
     |> load_strategies()}
  end

  @impl true
  def handle_params(params, _uri, socket) do
    {:noreply,
     socket
     |> assign(:status_filter, params["status"])
     |> load_strategies()}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8 py-8">
      <div class="flex justify-between items-center mb-6">
        <h1 class="text-3xl font-bold text-gray-900">Strategies</h1>
        <.link navigate={~p"/strategies/new"} class="btn-primary">
          New Strategy
        </.link>
      </div>

      <!-- Filter tabs -->
      <div class="mb-6 border-b border-gray-200">
        <nav class="flex space-x-8">
          <.filter_tab status={nil} current={@status_filter}>All</.filter_tab>
          <.filter_tab status="draft" current={@status_filter}>Drafts</.filter_tab>
          <.filter_tab status="active" current={@status_filter}>Active</.filter_tab>
          <.filter_tab status="inactive" current={@status_filter}>Inactive</.filter_tab>
        </nav>
      </div>

      <!-- Strategy grid -->
      <%= if Enum.empty?(@strategies) do %>
        <div class="text-center py-12">
          <p class="text-gray-500">No strategies found</p>
          <.link navigate={~p"/strategies/new"} class="text-blue-600 hover:underline mt-2">
            Create your first strategy
          </.link>
        </div>
      <% else %>
        <div class="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-6">
          <%= for strategy <- @strategies do %>
            <.link navigate={~p"/strategies/#{strategy.id}"}>
              <.strategy_card strategy={strategy} />
            </.link>
          <% end %>
        </div>
      <% end %>
    </div>
    """
  end

  defp load_strategies(socket) do
    strategies = Strategies.list_strategies(
      socket.assigns.current_user,
      status: socket.assigns.status_filter,
      limit: socket.assigns.page_size
    )

    assign(socket, :strategies, strategies)
  end

  @impl true
  def handle_info({:strategy_created, _id}, socket) do
    {:noreply, load_strategies(socket)}
  end

  def handle_info({:strategy_updated, _id}, socket) do
    {:noreply, load_strategies(socket)}
  end
end
```

### Step 4.4: Create Form LiveView

Create `lib/trading_strategy_web/live/strategy_live/form.ex` (see full implementation in contracts/liveview_routes.md)

### Step 4.5: Create Show LiveView

Create `lib/trading_strategy_web/live/strategy_live/show.ex`

---

## Phase 5: Update Router (Day 7)

Edit `lib/trading_strategy_web/router.ex`:

```elixir
scope "/", TradingStrategyWeb do
  pipe_through [:browser, :require_authenticated_user]

  # NEW: Strategy management routes
  live "/strategies", StrategyLive.Index, :index
  live "/strategies/new", StrategyLive.Form, :new
  live "/strategies/:id", StrategyLive.Show, :show
  live "/strategies/:id/edit", StrategyLive.Form, :edit

  # Existing routes
  live "/paper_trading", PaperTradingLive
  live "/paper_trading/:session_id", PaperTradingLive
end
```

---

## Phase 6: Testing (Days 8-9)

### Step 6.1: Create Test Fixtures

Edit `test/support/fixtures/accounts_fixtures.ex` (generated by phx.gen.auth):
```elixir
def user_fixture(attrs \\ %{}) do
  {:ok, user} =
    attrs
    |> Enum.into(%{
      email: unique_user_email(),
      password: valid_user_password()
    })
    |> TradingStrategy.Accounts.register_user()

  user
end
```

Update `test/support/fixtures/strategies_fixtures.ex`:
```elixir
def strategy_fixture(attrs \\ %{}) do
  user = attrs[:user] || user_fixture()

  {:ok, strategy} =
    attrs
    |> Enum.into(%{
      user_id: user.id,
      name: "Test Strategy #{System.unique_integer()}",
      format: "yaml",
      content: valid_yaml_strategy(),
      trading_pair: "BTC/USD",
      timeframe: "1h"
    })
    |> TradingStrategy.Strategies.create_strategy()

  strategy
end
```

### Step 6.2: Write LiveView Tests

Create `test/trading_strategy_web/live/strategy_live/index_test.exs`:
```elixir
defmodule TradingStrategyWeb.StrategyLive.IndexTest do
  use TradingStrategyWeb.ConnCase, async: true
  import Phoenix.LiveViewTest

  setup :register_and_log_in_user

  test "lists all user's strategies", %{conn: conn, user: user} do
    strategy1 = strategy_fixture(user: user, name: "Strategy 1")
    strategy2 = strategy_fixture(user: user, name: "Strategy 2")

    {:ok, _view, html} = live(conn, ~p"/strategies")

    assert html =~ "Strategy 1"
    assert html =~ "Strategy 2"
  end

  test "does not show other users' strategies", %{conn: conn, user: user} do
    other_user = user_fixture()
    other_strategy = strategy_fixture(user: other_user, name: "Other Strategy")

    {:ok, _view, html} = live(conn, ~p"/strategies")

    refute html =~ "Other Strategy"
  end
end
```

### Step 6.3: Run All Tests

```bash
mix test
```

---

## Phase 7: Manual Testing (Day 10)

### Checklist

1. **Authentication**:
   - [ ] Register new user
   - [ ] Login/logout
   - [ ] Password reset

2. **Strategy List**:
   - [ ] View empty list
   - [ ] Create first strategy
   - [ ] Filter by status
   - [ ] Pagination works (if >50 strategies)

3. **Strategy Creation**:
   - [ ] Required field validation
   - [ ] Real-time validation (<1s response)
   - [ ] Name uniqueness check
   - [ ] DSL parsing errors displayed
   - [ ] Autosave works
   - [ ] Form submission succeeds

4. **Strategy Editing**:
   - [ ] Load existing strategy
   - [ ] Cannot edit active strategy
   - [ ] Version conflict detection works
   - [ ] Save creates new version (for inactive)

5. **Strategy Viewing**:
   - [ ] Display all strategy details
   - [ ] Show parsed DSL structure
   - [ ] Version history visible
   - [ ] Activation blocked without backtest

6. **Performance**:
   - [ ] List loads in <2s (100+ strategies)
   - [ ] Validation responds in <1s
   - [ ] Syntax test completes in <3s

---

## Phase 8: Deployment

### Step 8.1: Update Production Config

Ensure `config/runtime.exs` has:
```elixir
config :trading_strategy, TradingStrategyWeb.Endpoint,
  url: [host: System.get_env("PHX_HOST"), port: 443, scheme: "https"]
```

### Step 8.2: Run Migrations on Production

```bash
# On production server
mix ecto.migrate
```

### Step 8.3: Deploy

```bash
# Build release
MIX_ENV=prod mix release

# Deploy (method depends on your infrastructure)
```

---

## Troubleshooting

### Issue: "user_id can't be blank"

**Cause**: Not passing current_user to context functions

**Fix**: Ensure all Strategies context calls include user parameter:
```elixir
Strategies.list_strategies(socket.assigns.current_user)
```

### Issue: Validation not appearing in real-time

**Cause**: Missing `phx-change="validate"` on form

**Fix**: Add to form:
```heex
<.form for={@form} phx-change="validate" phx-submit="save">
```

### Issue: Optimistic locking not working

**Cause**: Missing `optimistic_lock(:lock_version)` in changeset

**Fix**: Add to Strategy.changeset/2:
```elixir
|> optimistic_lock(:lock_version)
```

### Issue: Strategies not isolated per user

**Cause**: Forgot to filter by user_id in queries

**Fix**: All queries must include `where: s.user_id == ^user.id`

---

## Next Steps

After completing this feature:

1. **Feature 005**: Backtest UI integration (display results, link to strategies)
2. **Feature 006**: Paper trading UI with strategy selection
3. **Feature 007**: Live trading UI with enhanced risk controls

---

## Resources

- [Phoenix LiveView Docs](https://hexdocs.pm/phoenix_live_view/)
- [phx.gen.auth Guide](https://hexdocs.pm/phoenix/mix_phx_gen_auth.html)
- [Ecto Changeset Docs](https://hexdocs.pm/ecto/Ecto.Changeset.html)
- [Optimistic Locking](https://hexdocs.pm/ecto/Ecto.Changeset.html#optimistic_lock/3)

---

## Time Estimate

- Phase 1 (Auth): 1-2 days
- Phase 2 (Schema): 0.5 day
- Phase 3 (Context): 1-2 days
- Phase 4 (LiveViews): 3 days
- Phase 5 (Router): 0.25 day
- Phase 6 (Testing): 2 days
- Phase 7 (Manual Testing): 1 day
- Phase 8 (Deployment): 0.5 day

**Total**: ~10 days for experienced Elixir/Phoenix developer

---

## Success Metrics

After implementation, verify:
- [ ] All user stories in spec.md are satisfied
- [ ] All acceptance scenarios pass
- [ ] All success criteria met (SC-001 through SC-009)
- [ ] Constitution principles followed
- [ ] Test coverage >80%
- [ ] Manual testing checklist complete
