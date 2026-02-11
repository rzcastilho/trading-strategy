# Quickstart: Bidirectional Strategy Editor Synchronization

**Feature**: 005-builder-dsl-sync
**Phase**: 1 - Design & Contracts
**Date**: 2026-02-10
**Status**: Complete

---

## Purpose

This guide helps developers set up their local environment to work on the bidirectional strategy editor synchronization feature. Follow these steps to get the editor running locally within 15-20 minutes.

---

## Prerequisites

Ensure you have these installed:

- **Elixir**: 1.17+ (OTP 27+)
- **Phoenix**: 1.7+
- **PostgreSQL**: 14+ (for strategy storage)
- **Node.js**: 18+ and npm 9+ (for CodeMirror 6)
- **Git**: For cloning the repository

Check versions:

```bash
elixir --version  # Should show Elixir 1.17+ and Erlang/OTP 27+
psql --version    # Should show PostgreSQL 14+
node --version    # Should show v18+
npm --version     # Should show 9+
```

---

## Quick Start (15 Minutes)

### Step 1: Clone and Setup (5 minutes)

```bash
# Clone repository (if not already)
cd trading-strategy

# Install Elixir dependencies
mix deps.get

# Install Node.js dependencies for assets
cd assets && npm install && cd ..

# Create database (if not exists)
mix ecto.create

# Run migrations
mix ecto.migrate
```

### Step 2: Install Feature Dependencies (3 minutes)

#### A. Add Sourceror for Comment Preservation

Edit `mix.exs` and add to dependencies:

```elixir
defp deps do
  [
    # ... existing dependencies ...
    {:sourceror, "~> 1.10"}  # Comment preservation (FR-010)
  ]
end
```

Install:

```bash
mix deps.get
```

#### B. Install CodeMirror 6 for DSL Editor

Navigate to assets directory and install:

```bash
cd assets
npm install codemirror @codemirror/lang-yaml @codemirror/view @codemirror/state @codemirror/commands
cd ..
```

Verify installation:

```bash
cd assets && npm list codemirror && cd ..
# Should show codemirror@6.x.x
```

### Step 3: Start Development Server (2 minutes)

```bash
# Start Phoenix server
mix phx.server

# Or start with interactive Elixir shell
iex -S mix phx.server
```

Server starts at: **http://localhost:4000**

### Step 4: Verify Installation (5 minutes)

1. **Open browser**: Navigate to `http://localhost:4000`
2. **Login**: Use existing credentials or create account
3. **Navigate to strategy editor**: Go to `/strategies/new/edit`
4. **Test synchronization**:
   - Type in DSL editor (right pane)
   - Verify builder form updates (left pane) after 300ms
   - Edit builder form
   - Verify DSL editor updates

**Success Indicators**:
- ✅ DSL editor (CodeMirror 6) loads with syntax highlighting
- ✅ Builder form shows indicators, conditions, risk parameters
- ✅ Changes in DSL reflect in builder within 500ms
- ✅ Changes in builder reflect in DSL within 500ms
- ✅ Undo (Ctrl+Z) reverts last change
- ✅ Redo (Ctrl+Shift+Z) re-applies undone change

---

## Development Workflow

### File Structure for This Feature

```
lib/
├── trading_strategy/
│   └── strategy_editor/              # NEW: Core synchronization logic
│       ├── dsl_parser.ex            # Wraps Feature 001 parser
│       ├── builder_state.ex         # Builder form data structure
│       ├── synchronizer.ex          # Builder ↔ DSL conversion
│       ├── validator.ex             # DSL validation
│       ├── comment_preserver.ex     # Comment handling (Sourceror)
│       └── edit_history.ex          # Undo/redo stack
│
└── trading_strategy_web/
    ├── live/
    │   └── strategy_live/
    │       └── edit.ex                   # MODIFY: Main editor LiveView
    │
    └── assets/
        └── js/
            ├── hooks/
            │   ├── dsl_editor_hook.js    # NEW: CodeMirror integration
            │   ├── builder_form_hook.js  # NEW: Form debouncing
            │   └── sync_indicator_hook.js # NEW: Sync status
            └── app.js                     # MODIFY: Register hooks

test/
├── trading_strategy/
│   └── strategy_editor/
│       ├── synchronizer_test.exs         # Sync logic tests
│       ├── validator_test.exs            # Validation tests
│       └── comment_preserver_test.exs    # Comment preservation tests
│
└── trading_strategy_web/
    └── live/
        └── strategy_live/
            └── edit_test.exs             # Integration tests (Wallaby)
```

### Common Development Tasks

#### Run Tests

```bash
# All tests
mix test

# Feature-specific tests
mix test test/trading_strategy/strategy_editor/

# Integration tests only
mix test test/trading_strategy_web/live/strategy_live/

# Watch mode (re-run on file changes)
mix test.watch
```

#### Format Code

```bash
# Format Elixir code
mix format

# Format JavaScript (from assets/)
cd assets && npm run format && cd ..
```

#### Database Operations

```bash
# Reset database (drops, creates, migrates)
mix ecto.reset

# Rollback last migration
mix ecto.rollback

# Check migration status
mix ecto.migrations
```

#### Interactive Console

```bash
# Start IEx with application loaded
iex -S mix

# Test synchronizer directly
iex> alias TradingStrategy.StrategyEditor.{Synchronizer, BuilderState}
iex> dsl = """
...> name: Test Strategy
...> trading_pair: BTC/USD
...> """
iex> {:ok, builder_state} = Synchronizer.dsl_to_builder(dsl)
iex> {:ok, generated_dsl} = Synchronizer.builder_to_dsl(builder_state)
```

---

## Configuration

### Development Environment (`config/dev.exs`)

```elixir
config :trading_strategy, TradingStrategyWeb.Endpoint,
  debug_errors: true,
  code_reloader: true,
  check_origin: false,
  watchers: [
    node: [
      "node_modules/webpack/bin/webpack.js",
      "--mode",
      "development",
      "--watch-stdin",
      cd: Path.expand("../assets", __DIR__)
    ]
  ]

# Feature 005: Editor synchronization settings
config :trading_strategy, :strategy_editor,
  debounce_delay: 300,              # FR-008: 300ms debounce
  sync_timeout: 500,                # FR-001, FR-002: 500ms sync latency
  max_undo_stack_size: 100,         # Undo history limit
  validation_timeout: 1000,         # Parser timeout (1 second)
  enable_comment_preservation: true # FR-010: Comments preserved
```

### Test Environment (`config/test.exs`)

```elixir
# Use faster settings for tests
config :trading_strategy, :strategy_editor,
  debounce_delay: 50,     # Faster tests
  sync_timeout: 200,
  max_undo_stack_size: 50
```

### Feature Flags

Enable/disable features via config:

```elixir
config :trading_strategy, :features,
  bidirectional_sync: true,      # Feature 005
  advanced_builder: true,        # Feature 004
  dsl_editor: true              # Required for Feature 005
```

---

## Troubleshooting

### Issue: CodeMirror Not Loading

**Symptoms**: DSL editor shows blank or plain textarea

**Solution**:

```bash
cd assets
rm -rf node_modules package-lock.json
npm install
npm install codemirror @codemirror/lang-yaml
cd .. && mix phx.server
```

**Verify**: Check browser console for JavaScript errors

---

### Issue: Synchronization Timeout (>500ms)

**Symptoms**: Changes take longer than 500ms to sync

**Debug**:

```elixir
# In IEx console
iex> :timer.tc(fn ->
...>   Synchronizer.dsl_to_builder("name: Test")
...> end)
{microseconds, result}

# Should be < 500_000 microseconds (500ms)
```

**Common Causes**:
- Large DSL (20+ indicators) - optimize parser
- Database slow - check PostgreSQL logs
- Network latency - check WebSocket connection

---

### Issue: Comments Lost During Sync

**Symptoms**: DSL comments disappear after builder changes

**Solution**: Ensure Sourceror is installed and used:

```bash
mix deps.get
iex -S mix

# Test comment preservation
iex> {:ok, ast, comments} = Sourceror.parse_string("# Comment\nname: Test")
iex> output = Sourceror.to_string(ast, comments: comments)
iex> IO.puts(output)
# Should show: # Comment
#              name: Test
```

---

### Issue: Undo/Redo Not Working

**Symptoms**: Ctrl+Z doesn't revert changes

**Debug**:

```bash
# Check EditHistory GenServer is running
iex> GenServer.whereis(TradingStrategy.StrategyEditor.EditHistory)
#=> #PID<0.1234.0>  (should return PID, not nil)

# Check undo stack
iex> EditHistory.can_undo?(session_id)
#=> true or false
```

**Common Causes**:
- GenServer not started - check `application.ex` supervision tree
- Session ID mismatch - verify `socket.assigns.session_id`

---

### Issue: Database Migration Errors

**Symptoms**: `mix ecto.migrate` fails

**Solution**:

```bash
# Drop and recreate database
mix ecto.drop
mix ecto.create
mix ecto.migrate

# Or reset (drops + creates + migrates + seeds)
mix ecto.reset
```

---

## Performance Monitoring

### Check Synchronization Latency

```elixir
# Add to LiveView handle_event
def handle_event("dsl_changed", params, socket) do
  {time_us, result} = :timer.tc(fn ->
    Synchronizer.dsl_to_builder(params["dsl_text"])
  end)

  IO.puts("Sync latency: #{time_us / 1000}ms")  # Convert to milliseconds

  # ... rest of handler
end
```

### Monitor ETS Memory (Undo Stack)

```elixir
iex> :ets.info(:edit_histories, :memory)
#=> 1234  (memory in words, 1 word = 8 bytes on 64-bit)
```

### Profile Parser Performance

```bash
# Run benchmarks
mix run benchmarks/parser_bench.exs

# Example output:
# DSL parsing (10 indicators): 5.2ms
# DSL parsing (20 indicators): 12.8ms
# Builder→DSL generation: 8.1ms
```

---

## Next Steps

### For Frontend Developers

1. **Study CodeMirror 6 integration**: Read `assets/js/hooks/dsl_editor_hook.js`
2. **Implement custom DSL syntax highlighting**: Use `@codemirror/lang-yaml` as base
3. **Add visual feedback**: Loading indicators, sync status badges
4. **Keyboard shortcuts**: Ctrl+Z (undo), Ctrl+Shift+Z (redo), Ctrl+S (save)

### For Backend Developers

1. **Study synchronizer logic**: Read `lib/trading_strategy/strategy_editor/synchronizer.ex`
2. **Implement comment preservation**: Use Sourceror in `comment_preserver.ex`
3. **Add validation**: Extend `validator.ex` with semantic checks
4. **Optimize performance**: Profile and optimize AST traversal

### For Full-Stack Developers

1. **Integrate LiveView events**: Connect hooks to `handle_event` handlers
2. **Test bidirectional sync**: Write integration tests in `edit_test.exs`
3. **Handle edge cases**: Parser crashes (FR-005a), validation errors (FR-003-005)
4. **Implement undo/redo**: Create `edit_history.ex` GenServer

---

## Useful Resources

### Documentation

- **[Phoenix LiveView](https://hexdocs.pm/phoenix_live_view/)** - LiveView fundamentals
- **[CodeMirror 6](https://codemirror.net/)** - Code editor API
- **[Sourceror](https://hexdocs.pm/sourceror/)** - AST manipulation
- **[Ecto](https://hexdocs.pm/ecto/)** - Database queries and changesets

### Examples

- **[Alex Pearwin - CodeMirror + LiveView](https://alex.pearwin.com/2022/06/codemirror-phoenix-liveview/)** - Integration tutorial
- **[Livebook codemirror-lang-elixir](https://github.com/livebook-dev/codemirror-lang-elixir)** - Custom syntax highlighting

### Internal Docs

- **[Feature Spec](./spec.md)** - Requirements and user scenarios
- **[Research](./research.md)** - Technology decisions
- **[Data Model](./data-model.md)** - Entity structures
- **[Contracts](./contracts/liveview_events.md)** - Event handlers

---

## Development Checklist

Before starting implementation, ensure:

- [ ] Elixir 1.17+ installed
- [ ] Phoenix server runs without errors
- [ ] PostgreSQL database created and migrated
- [ ] Sourceror dependency installed (`mix deps.get`)
- [ ] CodeMirror 6 installed (`npm install` in assets/)
- [ ] Tests pass (`mix test`)
- [ ] Feature flag enabled in config
- [ ] Browser DevTools shows no JavaScript errors
- [ ] You've read the [spec](./spec.md) and [data-model](./data-model.md)

---

## Getting Help

- **Questions**: Ask in #phoenix-liveview or #elixir channels
- **Bugs**: Check `mix test` output and server logs (`_build/dev/lib/trading_strategy/priv/static`)
- **Performance**: Use `:timer.tc/1` to profile slow operations
- **Integration Issues**: Check browser DevTools Network tab for WebSocket errors

---

**Status**: ✅ Complete
**Last Updated**: 2026-02-10
**Ready for Implementation**: Yes

---

## Quick Command Reference

```bash
# Setup
mix deps.get && cd assets && npm install && cd .. && mix ecto.setup

# Development
mix phx.server          # Start server
mix test                # Run tests
mix format              # Format code
iex -S mix              # Interactive console

# Database
mix ecto.migrate        # Run migrations
mix ecto.rollback       # Rollback last migration
mix ecto.reset          # Drop, create, migrate, seed

# Assets
cd assets && npm install && cd ..   # Install JS dependencies
cd assets && npm run format && cd .. # Format JavaScript

# Monitoring
mix phx.routes          # List all routes
mix ecto.migrations     # Check migration status
```
