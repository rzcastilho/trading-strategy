# trading-strategy Development Guidelines

Auto-generated from all feature plans. Last updated: 2025-12-04

## Active Technologies
- Postman Collection v2.1 JSON forma (002-postman-api-collection)
- Elixir 1.17+ (OTP 27+) + Phoenix 1.7+, Phoenix LiveView (dashboards), Ecto (database) (003-fix-backtesting)
- PostgreSQL + TimescaleDB extension (time-series market data) (003-fix-backtesting)

- Elixir 1.17+ (OTP 27+) (001-strategy-dsl-library)

## Project Structure

```text
backend/
frontend/
tests/
```

## Commands

# Add commands for Elixir 1.17+ (OTP 27+)

## Code Style

Elixir 1.17+ (OTP 27+): Follow standard conventions

## Recent Changes
- 004-strategy-ui: Added Elixir 1.17+ (OTP 27+) + Phoenix 1.7+, Phoenix LiveView (dashboards), Ecto (database)
- 003-fix-backtesting: Added Elixir 1.17+ (OTP 27+) + Phoenix 1.7+, Phoenix LiveView (dashboards), Ecto (database)
- 002-postman-api-collection: Added Postman Collection v2.1 JSON forma


<!-- MANUAL ADDITIONS START -->

## Phoenix Authentication Setup (Feature 004)

### Authentication Architecture
- **Generator Used**: `mix phx.gen.auth Accounts User users`
- **Pattern**: Phoenix 1.7+ passwordless magic link authentication with optional password support
- **Location**:
  - Context: `lib/trading_strategy/accounts.ex`
  - Schema: `lib/trading_strategy/accounts/user.ex`
  - LiveViews: `lib/trading_strategy_web/live/user_live/`
  - Auth Module: `lib/trading_strategy_web/user_auth.ex`

### Core Components Setup
- **File**: `lib/trading_strategy_web/components/core_components.ex`
- **Components Added**:
  - `button/1` - Flexible button with navigation support (href, navigate, patch)
  - `input/1` - Form inputs (text, email, password, checkbox, select, textarea)
  - `header/1` - Page headers with title, subtitle, and actions slots
  - `icon/1` - Heroicon SVG rendering
  - `table/1` - Generic table with columns and actions
  - `list/1` - Data list rendering
  - `flash/1` - Toast-style flash notifications
  - `flash_group/1` - Flash message group wrapper
- **Styling**: daisyUI + Tailwind CSS
- **Helper Functions**: `show/2`, `hide/2` (JS animations), `translate_error/1`

### Database Schema
- **Tables Created**:
  - `users` - User accounts with email (citext), hashed_password, confirmed_at
  - `users_tokens` - Authentication tokens (magic links, sessions, confirmations)
- **Indexes**:
  - `users_email_index` - Unique email lookup
  - `users_tokens_user_id_index` - Token lookup by user
  - `users_tokens_context_token_index` - Token validation

### LiveView Auth Pages
- **Login** (`login.ex`) - Magic link + password authentication
- **Registration** (`registration.ex`) - Email-based signup
- **Settings** (`settings.ex`) - Password management, sudo mode protected
- **Confirmation** (`confirmation.ex`) - Email confirmation via magic link
- **Module Fixes**: Added `alias TradingStrategyWeb.Layouts` and `alias Phoenix.LiveView.JS` to all auth LiveViews

### Known Issues
- Router needs root path ("/") configuration (warnings in UserAuth module)
- Mailer is configured for local development (Swoosh.Adapters.Local)

<!-- MANUAL ADDITIONS START -->

## Backtesting Architecture Patterns (Feature 003)

### ProgressTracker Pattern
- **Purpose**: Real-time progress monitoring for async backtests
- **Implementation**: GenServer + ETS table with `read_concurrency: true`
- **Location**: `lib/trading_strategy/backtesting/progress_tracker.ex`
- **Key Methods**:
  - `track(session_id, total_bars)` - Initialize tracking
  - `update(session_id, bars_processed)` - Fast ETS update (every 100 bars)
  - `get(session_id)` - Concurrent progress lookup
  - `complete(session_id)` - Cleanup after completion
- **Lifecycle**: Auto-cleanup after 24h of staleness

### ConcurrencyManager Pattern
- **Purpose**: Enforce concurrent backtest limit with FIFO queueing
- **Implementation**: GenServer with token-based semaphore
- **Location**: `lib/trading_strategy/backtesting/concurrency_manager.ex`
- **Configuration**: `config :trading_strategy, :max_concurrent_backtests, 5`
- **Key Methods**:
  - `request_slot(session_id)` - Returns `{:ok, :granted}` or `{:ok, {:queued, position}}`
  - `release_slot(session_id)` - Auto-dequeues next waiting backtest
  - `status()` - Monitor running count and queue depth
- **State Management**: In-memory (single-node), lost on restart (queue rebuilt from DB status)

### BacktestingSupervisor Pattern
- **Purpose**: Isolated supervision for backtest tasks
- **Implementation**: DynamicSupervisor with `:temporary` restart strategy
- **Location**: `lib/trading_strategy/backtesting/supervisor.ex`
- **Integration**: Added to Application supervision tree
- **Restart Detection**: On app restart, finds stale "running" sessions and marks as "error"

### Trade PnL Tracking
- **Schema**: Added `pnl`, `duration_seconds`, `entry_price`, `exit_price` to `trades` table
- **Calculation**: Net PnL = (exit_price - entry_price) × quantity × direction - fees
- **Storage**: Calculated at trade execution time, stored in database
- **Validation**: Position PnL = sum of trade PnLs (data integrity check)

### Equity Curve Storage
- **Schema**: JSONB column `equity_curve` in `performance_metrics` table
- **Format**: Array of `%{"timestamp" => ISO8601, "value" => float}`
- **Sampling**: Max 1000 points (trade entry/exit + every Nth bar)
- **Metadata**: `equity_curve_metadata` stores sampling info

### Performance Optimization
- **Issue**: O(n²) complexity from repeated historical data slicing
- **Solution**: Eliminated `Enum.take` in tight loop by using index-based bar access
- **Result**: 30%+ improvement for 10K+ bar backtests
- **Monitoring**: Benchmark tests in `test/trading_strategy/backtesting/benchmarks/`

<!-- MANUAL ADDITIONS END -->
