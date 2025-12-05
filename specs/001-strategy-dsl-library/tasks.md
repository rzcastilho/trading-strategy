# Trading Strategy DSL Library - Implementation Tasks

**Feature**: 001-strategy-dsl-library
**Branch**: `001-strategy-dsl-library`
**Status**: Ready for Implementation

## Overview

This document outlines the implementation tasks for building a trading strategy library with a declarative DSL, supporting backtesting, paper trading, and live trading modes.

## Dependency Graph

```
Setup (Phase 1)
    ↓
Foundational (Phase 2)
    ↓
    ├─→ US1: Define Strategy Using DSL (P1) [Phase 3]
    │       ↓
    │   US2: Backtest Strategy (P2) [Phase 4]
    │       ↓
    │   US3: Paper Trading (P3) [Phase 5]
    │       ↓
    │   US4: Live Trading (P4) [Phase 6]
    │
    └─→ Polish & Cross-Cutting (Phase 7) [Can run parallel with US4]
```

## Implementation Strategy

**MVP Scope**: User Story 1 (P1) - Define Strategy Using DSL
- Deliver immediate value: traders can define and validate strategies
- Enables early feedback on DSL usability
- Foundation for all subsequent features

**Incremental Delivery**:
1. **Sprint 1**: US1 (P1) - Strategy DSL definition and validation
2. **Sprint 2**: US2 (P2) - Backtesting with historical data
3. **Sprint 3**: US3 (P3) - Paper trading with live data
4. **Sprint 4**: US4 (P4) - Live trading with real capital

---

## Phase 1: Setup & Project Initialization

- [ ] T001 Initialize Elixir project with Phoenix 1.7+ and verify OTP 27+ compatibility at mix.exs
- [ ] T002 Add core dependencies to mix.exs: phoenix, phoenix_ecto, postgrex, yaml_elixir (~> 2.12), toml (~> 0.7), trading_indicators (~> 0.1.0), crypto_exchange (~> 0.1.0)
- [ ] T003 Run mix deps.get and mix deps.compile to install and compile all dependencies
- [ ] T004 Configure PostgreSQL database connection in config/dev.exs, config/test.exs, config/prod.exs
- [ ] T005 Install TimescaleDB extension and verify PostgreSQL connection with mix ecto.create
- [ ] T006 Create Phoenix application structure with mix phx.new --no-html --no-assets for API-only setup
- [ ] T007 Configure application supervision tree in lib/trading_strategy/application.ex with core supervisors

---

## Phase 2: Foundational Infrastructure (Blocking Prerequisites)

### Database Schema

- [ ] T008 [P] Create TimescaleDB migration for market_data hypertable at priv/repo/migrations/*_create_market_data_hypertable.exs
- [ ] T009 [P] Create migration for strategies table at priv/repo/migrations/*_create_strategies.exs
- [ ] T010 [P] Create migration for indicators table at priv/repo/migrations/*_create_indicators.exs
- [ ] T011 [P] Create migration for signals table at priv/repo/migrations/*_create_signals.exs
- [ ] T012 [P] Create migration for trades table at priv/repo/migrations/*_create_trades.exs
- [ ] T013 [P] Create migration for positions table at priv/repo/migrations/*_create_positions.exs
- [ ] T014 [P] Create migration for trading_sessions table at priv/repo/migrations/*_create_trading_sessions.exs
- [ ] T015 [P] Create migration for performance_metrics table at priv/repo/migrations/*_create_performance_metrics.exs
- [ ] T016 Run mix ecto.migrate to apply all database migrations

### Ecto Schemas

- [ ] T017 [P] Define Strategy schema at lib/trading_strategy/strategies/strategy.ex with DSL content field
- [ ] T018 [P] Define Indicator schema at lib/trading_strategy/strategies/indicator.ex
- [ ] T019 [P] Define MarketData schema at lib/trading_strategy/market_data/market_data.ex
- [ ] T020 [P] Define Signal schema at lib/trading_strategy/strategies/signal.ex
- [ ] T021 [P] Define Trade schema at lib/trading_strategy/orders/trade.ex
- [ ] T022 [P] Define Position schema at lib/trading_strategy/orders/position.ex
- [ ] T023 [P] Define TradingSession schema at lib/trading_strategy/backtesting/trading_session.ex
- [ ] T024 [P] Define PerformanceMetrics schema at lib/trading_strategy/backtesting/performance_metrics.ex

### Behaviour Contracts

- [ ] T025 [P] Create StrategyExecutor behaviour at lib/trading_strategy/strategies/strategy_executor.ex defining execute/2, validate/1
- [ ] T026 [P] Create IndicatorCalculator behaviour at lib/trading_strategy/strategies/indicator_calculator.ex defining calculate/2
- [ ] T027 [P] Create SignalGenerator behaviour at lib/trading_strategy/strategies/signal_generator.ex defining generate/2
- [ ] T028 [P] Create OrderExecutor behaviour at lib/trading_strategy/orders/order_executor.ex defining place_order/2, cancel_order/1

### Core Infrastructure

- [ ] T029 Create configuration module at lib/trading_strategy/config.ex for loading exchange API keys, rate limits, risk parameters
- [ ] T030 Create supervision tree for strategies at lib/trading_strategy/strategies/supervisor.ex
- [ ] T031 Create supervision tree for market data at lib/trading_strategy/market_data/supervisor.ex
- [ ] T032 Create supervision tree for backtesting at lib/trading_strategy/backtesting/supervisor.ex

---

## Phase 3: User Story 1 - Define Strategy Using DSL (P1)

**Story Goal**: Enable traders to define strategies using YAML/TOML without writing code

**Independent Test**: Strategy can be created via API, parsed, validated, and persisted

### DSL Parsing & Validation

- [ ] T033 [US1] Create DSL parser module at lib/trading_strategy/strategies/dsl/parser.ex supporting YAML and TOML formats
- [ ] T034 [US1] Implement YAML strategy parser at lib/trading_strategy/strategies/dsl/yaml_parser.ex using yaml_elixir
- [ ] T035 [US1] Implement TOML strategy parser at lib/trading_strategy/strategies/dsl/toml_parser.ex using toml library
- [ ] T036 [US1] Create DSL schema validator at lib/trading_strategy/strategies/dsl/validator.ex with required fields validation
- [ ] T037 [US1] Implement indicator definition validation at lib/trading_strategy/strategies/dsl/indicator_validator.ex using TradingIndicators.Behaviour.parameter_metadata/0 to validate indicator type exists and parameters match schema (type, min/max ranges, required fields)
- [ ] T038 [US1] Implement entry conditions validation at lib/trading_strategy/strategies/dsl/entry_condition_validator.ex
- [ ] T039 [US1] Implement exit conditions validation at lib/trading_strategy/strategies/dsl/exit_condition_validator.ex
- [ ] T040 [US1] Implement risk parameters validation at lib/trading_strategy/strategies/dsl/risk_validator.ex

### Strategy Management

- [ ] T041 [US1] Create strategy context module at lib/trading_strategy/strategies.ex with create_strategy/1, get_strategy/1, update_strategy/2, delete_strategy/1
- [ ] T042 [US1] Implement strategy changeset with validations at lib/trading_strategy/strategies/strategy.ex
- [ ] T043 [US1] Create StrategyController at lib/trading_strategy_web/controllers/strategy_controller.ex implementing strategy_api.ex contract
- [ ] T044 [US1] Add strategy routes to lib/trading_strategy_web/router.ex for POST /api/strategies, GET /api/strategies/:id, PUT /api/strategies/:id, DELETE /api/strategies/:id
- [ ] T045 [US1] Create strategy JSON views at lib/trading_strategy_web/views/strategy_view.ex for rendering responses

### Testing

- [ ] T046 [US1] Write unit tests for YAML parser at test/trading_strategy/strategies/dsl/yaml_parser_test.exs
- [ ] T047 [US1] Write unit tests for TOML parser at test/trading_strategy/strategies/dsl/toml_parser_test.exs
- [ ] T048 [US1] Write unit tests for DSL validators at test/trading_strategy/strategies/dsl/validator_test.exs
- [ ] T049 [US1] Write integration tests for strategy CRUD at test/trading_strategy_web/controllers/strategy_controller_test.exs

### Independent Test for US1

```bash
# Test strategy creation with YAML DSL
curl -X POST http://localhost:4000/api/strategies \
  -H "Content-Type: application/json" \
  -d '{
    "name": "RSI Mean Reversion",
    "format": "yaml",
    "content": "name: RSI Mean Reversion\ntrading_pair: BTC/USD\ntimeframe: 1h\nindicators:\n  - type: rsi\n    name: rsi_14\n    parameters:\n      period: 14\nentry_conditions: \"rsi_14 < 30\"\nexit_conditions: \"rsi_14 > 70\"\nstop_conditions: \"rsi_14 < 25\"\nposition_sizing:\n  type: percentage\n  percentage_of_capital: 0.10\nrisk_parameters:\n  max_daily_loss: 0.03\n  max_drawdown: 0.15"
  }'

# Expected: 201 Created with strategy_id

# Test strategy retrieval
curl http://localhost:4000/api/strategies/1

# Expected: 200 OK with full strategy definition

# Test strategy validation errors
curl -X POST http://localhost:4000/api/strategies \
  -H "Content-Type: application/json" \
  -d '{"name": "Invalid", "format": "yaml", "content": "invalid: yaml without required fields"}'

# Expected: 422 Unprocessable Entity with specific validation errors

# Run unit tests
mix test test/trading_strategy/strategies/dsl/
mix test test/trading_strategy_web/controllers/strategy_controller_test.exs
```

---

## Phase 4: User Story 2 - Backtest Strategy with Historical Data (P2)

**Story Goal**: Validate strategy profitability using historical market data

**Independent Test**: Backtest executes on 2 years of data and returns performance metrics

### Market Data Management

- [ ] T050 [US2] Create market data context at lib/trading_strategy/market_data.ex with get_historical_data/3 using CryptoExchange.API.get_historical_klines_bulk for date range queries
- [ ] T051 [US2] Implement market data seeder at priv/repo/seeds/market_data.exs using CryptoExchange.API.get_historical_klines_bulk to fetch and persist 2 years of OHLCV data
- [ ] T052 [US2] Create TimescaleDB-optimized queries at lib/trading_strategy/market_data/queries.ex using time_bucket for efficient aggregation

### Indicator Calculation

- [ ] T053 [US2] Create generic indicator adapter at lib/trading_strategy/strategies/indicators/adapter.ex implementing calculate/3 that dispatches to TradingIndicators modules dynamically using TradingIndicators.Behaviour pattern
- [ ] T054 [US2] Create indicator registry at lib/trading_strategy/strategies/indicators/registry.ex using TradingIndicators.categories/0 to discover all 22 indicators dynamically and build DSL name → module mapping (e.g., "rsi" → TradingIndicators.Momentum.RSI)
- [ ] T055 [US2] Implement parameter validation helper at lib/trading_strategy/strategies/indicators/param_validator.ex using TradingIndicators.Behaviour.parameter_metadata/0 to validate types, ranges, and required fields dynamically
- [ ] T056 [US2] Create indicator calculation engine at lib/trading_strategy/strategies/indicator_engine.ex coordinating multiple indicator calculations using registry and adapter

**Implementation Example for T054 (Registry)**:
```elixir
# lib/trading_strategy/strategies/indicators/registry.ex
defmodule TradingStrategy.Strategies.Indicators.Registry do
  def build_registry do
    TradingIndicators.categories()
    |> Enum.flat_map(fn category_module ->
      category_module.available_indicators()
      |> Enum.map(fn indicator_module ->
        name = extract_name(indicator_module)
        {String.downcase(name), indicator_module}
      end)
    end)
    |> Map.new()
  end

  # Result: %{"sma" => TradingIndicators.Trend.SMA, "rsi" => TradingIndicators.Momentum.RSI, ...}
end
```

**Implementation Example for T055 (Validation)**:
```elixir
# lib/trading_strategy/strategies/indicators/param_validator.ex
defmodule TradingStrategy.Strategies.Indicators.ParamValidator do
  def validate(indicator_module, params) do
    metadata = indicator_module.parameter_metadata()

    params
    |> Enum.reduce_while(:ok, fn {key, value}, _acc ->
      case validate_param(key, value, metadata) do
        :ok -> {:cont, :ok}
        error -> {:halt, error}
      end
    end)
  end

  defp validate_param(key, value, metadata) do
    case Map.get(metadata, key) do
      nil -> {:error, "Unknown parameter: #{key}"}
      schema -> check_type_and_range(value, schema)
    end
  end
end
```

### Signal Generation

- [ ] T057 [US2] Implement signal evaluator at lib/trading_strategy/strategies/signal_evaluator.ex parsing entry/exit conditions from DSL
- [ ] T058 [US2] Create condition parser at lib/trading_strategy/strategies/condition_parser.ex supporting comparison operators (>, <, ==, &&, ||)

### Backtest Execution

- [ ] T059 [US2] Implement backtest engine at lib/trading_strategy/backtesting/engine.ex orchestrating historical data replay
- [ ] T060 [US2] Create position manager at lib/trading_strategy/backtesting/position_manager.ex tracking open positions during backtest
- [ ] T061 [US2] Implement simulated order execution at lib/trading_strategy/backtesting/simulated_executor.ex with slippage modeling
- [ ] T062 [US2] Create performance metrics calculator at lib/trading_strategy/backtesting/metrics_calculator.ex computing total return, Sharpe ratio, max drawdown
- [ ] T063 [US2] Implement equity curve generator at lib/trading_strategy/backtesting/equity_curve.ex tracking portfolio value over time

### API & Testing

- [ ] T064 [US2] Create backtest context at lib/trading_strategy/backtesting.ex with run_backtest/3 function
- [ ] T065 [US2] Create BacktestController at lib/trading_strategy_web/controllers/backtest_controller.ex implementing backtest_api.ex contract
- [ ] T069 [US2] Add backtest routes to lib/trading_strategy_web/router.ex for POST /api/backtests, GET /api/backtests/:id
- [ ] T070 [US2] Create backtest JSON views at lib/trading_strategy_web/views/backtest_view.ex rendering results and metrics
- [ ] T071 [US2] Write unit tests for indicator calculators at test/trading_strategy/strategies/indicators/*_test.exs
- [ ] T072 [US2] Write unit tests for signal evaluator at test/trading_strategy/strategies/signal_evaluator_test.exs
- [ ] T073 [US2] Write unit tests for backtest engine at test/trading_strategy/backtesting/engine_test.exs
- [ ] T074 [US2] Write unit tests for metrics calculator at test/trading_strategy/backtesting/metrics_calculator_test.exs
- [ ] T075 [US2] Write integration tests for backtest API at test/trading_strategy_web/controllers/backtest_controller_test.exs

### Independent Test for US2

```bash
# Seed historical market data (2 years)
mix run priv/repo/seeds/market_data.exs

# Run backtest via API
curl -X POST http://localhost:4000/api/backtests \
  -H "Content-Type: application/json" \
  -d '{
    "strategy_id": 1,
    "trading_pair": "BTC/USD",
    "start_date": "2023-01-01T00:00:00Z",
    "end_date": "2024-12-31T23:59:59Z",
    "initial_capital": 10000,
    "commission_rate": 0.001,
    "slippage_bps": 5
  }'

# Expected: 202 Accepted with backtest_id

# Poll for results
curl http://localhost:4000/api/backtests/1

# Expected: 200 OK with performance_metrics containing:
# - total_return, win_rate, max_drawdown, sharpe_ratio
# - trade_count, average_trade_duration
# - equity_curve array

# Verify constitution requirement: Sharpe ratio > 1.0 before paper trading

# Run unit tests
mix test test/trading_strategy/backtesting/
mix test test/trading_strategy_web/controllers/backtest_controller_test.exs
```

---

## Phase 5: User Story 3 - Paper Trading in Real-Time (P3)

**Story Goal**: Test strategy in live market conditions without risking capital

**Independent Test**: Paper session runs with WebSocket, detects signals, logs simulated trades

### Real-Time Data Streaming

- [ ] T076 [US3] Integrate CryptoExchange.API.subscribe_to_ticker/1 at lib/trading_strategy/market_data/stream_subscriber.ex for real-time price updates via Phoenix.PubSub
- [ ] T077 [US3] Implement Phoenix.PubSub message handler at lib/trading_strategy/market_data/stream_handler.ex for {:ticker_update, data} messages
- [ ] T078 [US3] Create market data cache using ETS at lib/trading_strategy/market_data/cache.ex storing latest prices and candles
- [ ] T079 [US3] Add CryptoExchange.API.subscribe_to_trades/1 integration at lib/trading_strategy/market_data/stream_subscriber.ex for trade stream (optional, if needed for candle building)

### Paper Trading Execution

- [ ] T080 [US3] Create paper trading session manager at lib/trading_strategy/paper_trading/session_manager.ex using GenServer for state
- [ ] T081 [US3] Implement real-time indicator calculator at lib/trading_strategy/strategies/realtime_indicator_engine.ex updating on new data
- [ ] T082 [US3] Create real-time signal detector at lib/trading_strategy/strategies/realtime_signal_detector.ex evaluating conditions on each tick
- [ ] T083 [US3] Implement paper order executor at lib/trading_strategy/paper_trading/paper_executor.ex simulating order fills at market price
- [ ] T084 [US3] Create paper position tracker at lib/trading_strategy/paper_trading/position_tracker.ex maintaining virtual positions
- [ ] T085 [US3] Implement session state persistence at lib/trading_strategy/paper_trading/session_persister.ex saving to database periodically

### API & UI

- [ ] T086 [US3] Create paper trading context at lib/trading_strategy/paper_trading.ex with start_session/2, stop_session/1, get_session/1
- [ ] T087 [US3] Create PaperTradingController at lib/trading_strategy_web/controllers/paper_trading_controller.ex implementing paper_trading_api.ex contract
- [ ] T088 [US3] Add paper trading routes to lib/trading_strategy_web/router.ex for POST /api/paper_trading/sessions, GET /api/paper_trading/sessions/:id, DELETE /api/paper_trading/sessions/:id
- [ ] T089 [US3] Create Phoenix Channel at lib/trading_strategy_web/channels/trading_channel.ex broadcasting real-time updates
- [ ] T090 [US3] Implement LiveView dashboard at lib/trading_strategy_web/live/paper_trading_live.ex displaying active positions and PnL

### Testing

- [ ] T091 [US3] Write unit tests for WebSocket client at test/trading_strategy/market_data/websocket_client_test.exs
- [ ] T092 [US3] Write unit tests for signal detector at test/trading_strategy/strategies/realtime_signal_detector_test.exs
- [ ] T093 [US3] Write unit tests for paper executor at test/trading_strategy/paper_trading/paper_executor_test.exs
- [ ] T094 [US3] Write integration tests for paper trading API at test/trading_strategy_web/controllers/paper_trading_controller_test.exs

### Independent Test for US3

```bash
# Start paper trading session
curl -X POST http://localhost:4000/api/paper_trading/sessions \
  -H "Content-Type: application/json" \
  -d '{
    "strategy_id": 1,
    "trading_pair": "BTCUSDT",
    "initial_capital": 10000,
    "data_source": "binance"
  }'

# Expected: 201 Created with session_id

# Monitor session status (should show WebSocket connected)
curl http://localhost:4000/api/paper_trading/sessions/1

# Expected: 200 OK with status: "active", connectivity: "connected"

# Connect to WebSocket for real-time updates
wscat -c ws://localhost:4000/socket/websocket

# Expected: Real-time messages when signals detected

# Wait for signals (manual test - observe console logs)
# Should log: "Signal detected: entry" when conditions met

# Stop session after 5+ minutes
curl -X DELETE http://localhost:4000/api/paper_trading/sessions/1

# Expected: 200 OK with final metrics

# Verify session persisted across restart
mix phx.server  # Restart server
curl http://localhost:4000/api/paper_trading/sessions  # Should list session

# Run unit tests
mix test test/trading_strategy/paper_trading/
mix test test/trading_strategy_web/controllers/paper_trading_controller_test.exs
```

---

## Phase 6: User Story 4 - Live Trading with Exchange Integration (P4)

**Story Goal**: Execute real trades automatically with risk management

**Independent Test**: Live session places testnet order, enforces risk limits, handles failures

### Exchange Integration

- [ ] T095 [US4] Create exchange wrapper at lib/trading_strategy/exchanges/exchange.ex abstracting CryptoExchange.API functions (connect_user, place_order, cancel_order, get_balance)
- [ ] T096 [US4] Implement user credential management at lib/trading_strategy/exchanges/credentials.ex for runtime API key handling (no persistence)
- [ ] T097 [US4] Create order placement adapter at lib/trading_strategy/exchanges/order_adapter.ex translating internal order format to CryptoExchange.API.place_order/2 params
- [ ] T098 [US4] Implement exchange health monitor at lib/trading_strategy/exchanges/health_monitor.ex tracking CryptoExchange connection status

### Rate Limiting & Reliability

- [ ] T099 [US4] Configure crypto-exchange built-in rate limiting at config/runtime.exs with Binance endpoint limits
- [ ] T100 [US4] Implement request retry logic at lib/trading_strategy/exchanges/retry_handler.ex wrapping CryptoExchange.API calls with exponential backoff for transient failures
- [ ] T101 [US4] Monitor crypto-exchange circuit breaker status at lib/trading_strategy/exchanges/resilience_monitor.ex logging API health events

### Risk Management

- [ ] T103 [US4] Create order validator at lib/trading_strategy/orders/order_validator.ex checking balance, lot size, price filters
- [ ] T104 [US4] Implement risk manager at lib/trading_strategy/risk/risk_manager.ex enforcing max position size, daily loss limits
- [ ] T105 [US4] Create position size calculator at lib/trading_strategy/risk/position_sizer.ex computing order quantity based on risk percentage

### Live Execution

- [ ] T106 [US4] Implement live order executor at lib/trading_strategy/orders/live_executor.ex placing real orders via exchange adapter
- [ ] T107 [US4] Create order status tracker at lib/trading_strategy/orders/order_tracker.ex monitoring fills and partial fills
- [ ] T108 [US4] Implement live trading session manager at lib/trading_strategy/live_trading/session_manager.ex coordinating real-time execution
- [ ] T109 [US4] Create account balance monitor at lib/trading_strategy/live_trading/balance_monitor.ex tracking available funds
- [ ] T110 [US4] Implement emergency stop mechanism at lib/trading_strategy/live_trading/emergency_stop.ex canceling all orders on critical errors

### Connectivity Handling

- [ ] T111 [US4] Create connectivity monitor at lib/trading_strategy/live_trading/connectivity_monitor.ex detecting network failures
- [ ] T112 [US4] Implement reconnection handler at lib/trading_strategy/live_trading/reconnection_handler.ex resuming after disconnection

### API & Audit

- [ ] T113 [US4] Create live trading context at lib/trading_strategy/live_trading.ex with start_session/2, stop_session/1, emergency_stop/1
- [ ] T114 [US4] Create LiveTradingController at lib/trading_strategy_web/controllers/live_trading_controller.ex implementing live_trading_api.ex contract
- [ ] T115 [US4] Add live trading routes to lib/trading_strategy_web/router.ex for POST /api/live_trading/sessions, GET /api/live_trading/sessions/:id, DELETE /api/live_trading/sessions/:id, POST /api/live_trading/sessions/:id/emergency_stop
- [ ] T116 [US4] Create audit logger at lib/trading_strategy/live_trading/audit_logger.ex recording all orders with timestamps

### Testing

- [ ] T117 [US4] Write unit tests for Binance adapter at test/trading_strategy/exchanges/binance/adapter_test.exs using mock responses
- [ ] T118 [US4] Write unit tests for rate limiter at test/trading_strategy/exchanges/rate_limiter_test.exs
- [ ] T119 [US4] Write unit tests for risk manager at test/trading_strategy/risk/risk_manager_test.exs
- [ ] T120 [US4] Write unit tests for live executor at test/trading_strategy/orders/live_executor_test.exs
- [ ] T121 [US4] Write integration tests for live trading API at test/trading_strategy_web/controllers/live_trading_controller_test.exs

### Independent Test for US4

```bash
# IMPORTANT: Configure testnet API keys in config/dev.secret.exs
# DO NOT test with real funds - use Binance testnet only

# Start live trading session (testnet mode)
curl -X POST http://localhost:4000/api/live_trading/sessions \
  -H "Content-Type: application/json" \
  -d '{
    "strategy_id": 1,
    "trading_pair": "BTCUSDT",
    "allocated_capital": 100,
    "exchange": "binance",
    "mode": "testnet",
    "api_credentials": {
      "api_key": "testnet_key",
      "api_secret": "testnet_secret"
    }
  }'

# Expected: 201 Created with session_id

# Monitor session (should show active and connected)
curl http://localhost:4000/api/live_trading/sessions/1

# Expected: 200 OK with status, open positions, risk_limits_status

# Test risk limit enforcement (attempt large order)
# Should be rejected by risk manager

# Test emergency stop
curl -X POST http://localhost:4000/api/live_trading/sessions/1/emergency_stop

# Expected: 200 OK, all orders cancelled

# Verify audit log written
# Check logs for all order placements with timestamps

# Run unit tests with mocked exchange
mix test test/trading_strategy/live_trading/
mix test test/trading_strategy/exchanges/
```

---

## Phase 7: Polish & Cross-Cutting Concerns

### Observability

- [ ] T122 [P] Configure Telemetry at lib/trading_strategy/telemetry.ex with metrics for order latency, signal frequency, backtest duration
- [ ] T123 [P] Implement structured logging at lib/trading_strategy/logging.ex using Logger with metadata for correlation IDs
- [ ] T124 [P] Create error handling middleware at lib/trading_strategy_web/fallback_controller.ex standardizing error responses
- [ ] T125 [P] Create global exception handler at lib/trading_strategy_web/error_handler.ex catching unhandled errors

### Documentation & Examples

- [ ] T126 [P] Create example YAML strategy at examples/sma_crossover.yaml demonstrating DSL syntax
- [ ] T127 [P] Create example TOML strategy at examples/rsi_reversal.toml demonstrating alternative format
- [ ] T128 [P] Create example advanced strategy at examples/multi_indicator.yaml combining multiple indicators
- [ ] T129 [P] Write README documentation at README.md covering installation, quick start, DSL reference
- [ ] T130 [P] Write API documentation at docs/api.md documenting all REST endpoints
- [ ] T131 [P] Write DSL reference guide at docs/dsl_reference.md with complete syntax specification
- [ ] T132 [P] Write deployment guide at docs/deployment.md covering production setup with TimescaleDB

### Deployment & Operations

- [ ] T133 [P] Create Docker Compose configuration at docker-compose.yml for local development with PostgreSQL + TimescaleDB
- [ ] T134 [P] Add health check endpoint at lib/trading_strategy_web/controllers/health_controller.ex checking database and exchange connectivity

### Quality Assurance

- [ ] T135 Run full test suite with mix test --cover ensuring >80% coverage
- [ ] T136 Run mix format and mix credo for code quality checks
- [ ] T137 Generate ExDoc documentation with mix docs

---

## Completion Criteria

### US1 Complete When:
- [x] Strategy can be defined in YAML or TOML format
- [x] DSL validation rejects invalid syntax with specific error messages
- [x] CRUD API endpoints work for strategies (create, read, update, delete)
- [x] Strategy persisted to database with correct schema
- [x] All US1 tests pass (>80% coverage)

### US2 Complete When:
- [x] Backtest runs on 2 years of historical data in <30 seconds
- [x] Performance metrics calculated (total return, Sharpe ratio, max drawdown, win rate)
- [x] All configured indicators (RSI, MACD, SMA, EMA, BB) calculate correctly
- [x] Entry/exit/stop signals detected from DSL conditions
- [x] Equity curve generated showing portfolio value over time
- [x] All US2 tests pass (>80% coverage)

### US3 Complete When:
- [x] Paper trading session starts with WebSocket connection to Binance
- [x] Real-time signals detected from live market data within 5 seconds
- [x] Virtual positions tracked correctly with unrealized PnL
- [x] Simulated trades logged with timestamps and execution prices
- [x] Session state persisted to database (survives application restart)
- [x] All US3 tests pass (>80% coverage)

### US4 Complete When:
- [x] Live session authenticates with Binance and places real testnet orders
- [x] Rate limiting prevents API bans (20 req/sec limit enforced)
- [x] Circuit breaker triggers after 5 failures in 10 seconds
- [x] Risk limits enforced (max position 25%, daily loss 3%, max drawdown 15%)
- [x] Emergency stop cancels all open orders within 1 second
- [x] Connectivity failures handled with automatic reconnection
- [x] Audit log records every order with correlation IDs
- [x] All US4 tests pass (>80% coverage)

---

## Parallel Execution Opportunities

### Within Phase 2 (Foundational):
- T008-T015: All migrations can be created in parallel
- T017-T024: All schemas can be defined in parallel
- T025-T028: All behaviours can be created in parallel

### Within Phase 3 (US1):
- T046-T048: All US1 unit tests can be written in parallel

### Within Phase 4 (US2):
- T053-T057: All indicator calculators can be implemented in parallel
- T071-T074: All US2 unit tests can be written in parallel

### Within Phase 7 (Polish):
- T122-T134: All polish tasks can be executed in parallel

---

## Notes

**Task Format**:
- [P] = Parallelizable task (no blocking dependencies)
- [US#] = User story label (maps to acceptance criteria)
- File paths are absolute from repository root

**Dependencies**:
- Each phase MUST complete before next phase begins (except Phase 7)
- Phase 7 can run in parallel with Phase 6
- Tasks within a phase can be parallelized if marked [P]

**Testing Strategy**:
- Test coverage target: >80% for all core modules
- Use Binance testnet for all US4 integration tests
- Mock external dependencies (WebSocket, exchange APIs) in unit tests
- Integration tests should test full request/response cycle

**Constitution Compliance**:
- Backtest Sharpe ratio >1.0 required before paper trading (US2 → US3 gate)
- Paper trading 30+ days required before live trading (US3 → US4 gate)
- All trading decisions must be logged (FR-028)
- Risk limits enforced at runtime (FR-021)

---

## Task Summary

**Total Tasks**: 137
**Phase 1 (Setup)**: 7 tasks
**Phase 2 (Foundational)**: 25 tasks
**Phase 3 (US1)**: 17 tasks
**Phase 4 (US2)**: 26 tasks
**Phase 5 (US3)**: 19 tasks
**Phase 6 (US4)**: 27 tasks
**Phase 7 (Polish)**: 16 tasks

**Estimated Effort**:
- MVP (US1 only): ~2 weeks
- US1 + US2: ~4 weeks
- US1 + US2 + US3: ~6 weeks
- Full feature (US1-US4): ~8-10 weeks

**Parallel Opportunities**: 45 parallelizable tasks identified
