# Implementation Plan: [FEATURE]

**Branch**: `[###-feature-name]` | **Date**: [DATE] | **Spec**: [link]
**Input**: Feature specification from `/specs/[###-feature-name]/spec.md`

**Note**: This template is filled in by the `/speckit.plan` command. See `.specify/templates/commands/plan.md` for the execution workflow.

## Summary

[Extract from feature spec: primary requirement + technical approach from research]

## Technical Context

<!--
  ACTION REQUIRED: Replace the content in this section with the technical details
  for the project. The structure here is presented in advisory capacity to guide
  the iteration process.
-->

**Language/Version**: Elixir 1.17+ (OTP 27+)
**Primary Dependencies**: Phoenix 1.7+, Phoenix LiveView (dashboards), Ecto (database)
**Storage**: PostgreSQL + TimescaleDB extension (time-series market data)
**Testing**: ExUnit (unit/integration), Wallaby (end-to-end UI)
**Target Platform**: Linux server (production), macOS/Linux (development)
**Project Type**: Web application with real-time trading capabilities
**Performance Goals**: <50ms p95 strategy decision latency, <100ms p95 order placement latency
**Constraints**: Fault-tolerant (OTP supervision), no shared mutable state, async-first architecture
**Scale/Scope**: Multi-strategy portfolio management, real-time market data processing

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

**Strategy-as-Library** (Principle I):
- [ ] Strategy is self-contained module with clear API
- [ ] Independent unit tests planned (>80% coverage target)
- [ ] No dependencies on other strategy libraries

**Backtesting Required** (Principle II - NON-NEGOTIABLE):
- [ ] Backtest plan includes minimum 2 years historical data
- [ ] Transaction costs, slippage, realistic conditions included
- [ ] Backtest results documentation planned (Sharpe, drawdown, win rate)

**Risk Management First** (Principle III - NON-NEGOTIABLE):
- [ ] Maximum position size defined (% of portfolio)
- [ ] Stop-loss rules specified (time/price/volatility-based)
- [ ] Daily loss limits and drawdown thresholds planned
- [ ] Risk parameters configurable via environment/config

**Observability & Auditability** (Principle IV):
- [ ] Structured logging planned for all trading decisions
- [ ] State transitions use GenServer for auditability
- [ ] Metrics planned: fill rates, slippage, latency, P&L

**Real-Time Data Contracts** (Principle V):
- [ ] Contract tests planned for data provider APIs
- [ ] Failure handling defined (stale data, missing quotes, outages)
- [ ] WebSocket reconnection logic planned
- [ ] Fallback mechanisms specified

**Performance & Latency Discipline** (Principle VI):
- [ ] Strategy decision latency target <50ms p95
- [ ] Order placement latency target <100ms p95
- [ ] Realistic latency assumptions in backtests

**Simplicity & Transparency** (Principle VII):
- [ ] Starting with single-asset, single-timeframe approach
- [ ] No premature optimization
- [ ] Complexity justified in Complexity Tracking table below if needed

## Project Structure

### Documentation (this feature)

```text
specs/[###-feature]/
├── plan.md              # This file (/speckit.plan command output)
├── research.md          # Phase 0 output (/speckit.plan command)
├── data-model.md        # Phase 1 output (/speckit.plan command)
├── quickstart.md        # Phase 1 output (/speckit.plan command)
├── contracts/           # Phase 1 output (/speckit.plan command)
└── tasks.md             # Phase 2 output (/speckit.tasks command - NOT created by /speckit.plan)
```

### Source Code (repository root)
<!--
  ACTION REQUIRED: Replace the placeholder tree below with the concrete layout
  for this feature. Delete unused options and expand the chosen structure with
  real paths (e.g., apps/admin, packages/something). The delivered plan must
  not include Option labels.
-->

```text
# Elixir/Phoenix Trading Strategy Application
lib/
├── trading_strategy/              # Core business logic (context)
│   ├── strategies/               # Trading strategy modules
│   │   ├── strategy.ex          # Strategy behaviour contract
│   │   └── [strategy_name]/     # Individual strategy implementations
│   ├── market_data/             # Market data ingestion & processing
│   │   ├── providers/           # Exchange/data provider adapters
│   │   └── storage/             # TimescaleDB interactions
│   ├── risk/                    # Risk management engine
│   │   ├── position_sizing.ex
│   │   └── stop_loss.ex
│   ├── backtesting/             # Backtesting engine
│   └── orders/                  # Order management system
└── trading_strategy_web/         # Phoenix web layer
    ├── controllers/
    ├── live/                    # LiveView dashboards
    │   ├── dashboard_live.ex    # Real-time strategy monitoring
    │   └── backtest_live.ex     # Backtest visualization
    └── channels/                # WebSocket connections (exchanges)

test/
├── trading_strategy/
│   ├── strategies/
│   │   ├── [strategy_name]_test.exs        # Unit tests
│   │   └── [strategy_name]_backtest.exs    # Backtests
│   ├── market_data/
│   │   └── providers/
│   │       └── [provider]_contract_test.exs # Contract tests
│   └── integration/
│       └── strategy_lifecycle_test.exs      # End-to-end integration
└── trading_strategy_web/
    └── live/
        └── dashboard_live_test.exs          # UI tests (Wallaby)

config/
├── config.exs              # Base configuration
├── dev.exs                 # Development settings
├── prod.exs                # Production settings
└── runtime.exs             # Runtime risk parameters (DO NOT COMMIT SECRETS)
```

**Structure Decision**: Elixir/Phoenix umbrella-style application with clear separation between trading logic (`lib/trading_strategy/`) and web interface (`lib/trading_strategy_web/`). Each strategy is a self-contained module under `strategies/` following the Strategy behaviour contract.

## Complexity Tracking

> **Fill ONLY if Constitution Check has violations that must be justified**

| Violation | Why Needed | Simpler Alternative Rejected Because |
|-----------|------------|-------------------------------------|
| [e.g., 4th project] | [current need] | [why 3 projects insufficient] |
| [e.g., Repository pattern] | [specific problem] | [why direct DB access insufficient] |
