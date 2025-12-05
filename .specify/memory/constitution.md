<!--
Sync Impact Report - Constitution v1.0.0

Version Change: Initial constitution (v1.0.0)
Modified Principles: N/A (initial version)
Added Sections: All sections (initial version)
Removed Sections: None

Templates Requiring Updates:
✅ .specify/templates/plan-template.md - Constitution Check section aligned
✅ .specify/templates/spec-template.md - Requirements structure aligned
✅ .specify/templates/tasks-template.md - Test-first discipline reflected

Follow-up TODOs: None
-->

# Trading Strategy Constitution

## Core Principles

### I. Strategy-as-Library

Every trading strategy is developed as a standalone, independently testable library.

- Strategies MUST be self-contained modules with clear public APIs
- Each strategy library MUST have independent unit tests achieving >80% coverage
- Strategy libraries MUST NOT depend on other strategy libraries (composability through configuration only)
- Clear purpose required - no organizational-only groupings without trading logic

**Rationale**: Isolation enables parallel development, independent testing, safe deployment, and portfolio composition flexibility.

### II. Backtesting Required (NON-NEGOTIABLE)

All trading strategies MUST be backtested before live deployment.

- Red-Green-Refactor for backtests: Write backtest → Verify failure → Implement strategy → Verify pass
- Backtests MUST cover minimum 2 years of historical data (where available)
- Backtests MUST include transaction costs, slippage, and realistic market conditions
- Backtest results (Sharpe ratio, max drawdown, win rate) MUST be documented before code review approval

**Rationale**: Historical validation reduces catastrophic losses and validates strategy robustness across market regimes.

### III. Risk Management First (NON-NEGOTIABLE)

Position sizing, stop-loss, and risk limits are mandatory for every strategy.

- Every strategy MUST implement maximum position size as percentage of portfolio
- Every strategy MUST define stop-loss rules (time-based, price-based, or volatility-based)
- Daily loss limits and drawdown thresholds MUST be enforced at runtime
- Risk parameters MUST be configurable without code changes (environment/config driven)

**Rationale**: Preservation of capital is paramount. Even profitable strategies fail without proper risk controls.

### IV. Observability & Auditability

All trading decisions MUST be logged and auditable for compliance and debugging.

- Structured logging required: every order decision MUST log reasoning, inputs, and timestamps
- Logs MUST capture strategy state, market conditions, and calculated signals
- Event-driven architecture: use Elixir GenServer state machines for auditable state transitions
- Metrics MUST include: order fill rates, slippage, latency (decision-to-execution), P&L tracking

**Rationale**: Regulatory compliance, post-mortem analysis, and continuous improvement depend on complete audit trails.

### V. Real-Time Data Contracts

All market data interfaces MUST define explicit contracts and handle failures gracefully.

- Contract tests MUST validate data provider API responses (schema, latency, completeness)
- Strategies MUST handle stale data, missing quotes, and exchange outages without crashing
- WebSocket reconnection logic required for real-time feeds
- Fallback mechanisms defined for data provider failures (secondary sources or safe halt)

**Rationale**: Market data is unreliable; strategies must be resilient to preserve capital during data failures.

### VI. Performance & Latency Discipline

Low-latency execution is a competitive advantage and MUST be measurable.

- Strategy decision latency MUST be <50ms p95 (measure tick-to-signal time)
- Order placement latency MUST be <100ms p95 (measure signal-to-exchange time)
- Backtests MUST include realistic latency assumptions (no zero-latency assumptions)
- Hot path code (signal generation, order placement) MUST avoid allocations where possible

**Rationale**: In algorithmic trading, latency directly impacts profitability through slippage and missed opportunities.

### VII. Simplicity & Transparency

Start simple. Complexity requires extraordinary justification.

- New strategies start with single-asset, single-timeframe implementations
- Avoid premature optimization: prove strategy profitability before performance tuning
- No machine learning models without interpretable feature importance and failure modes documented
- YAGNI strictly enforced - build what backtests prove necessary, not theoretical capabilities

**Rationale**: Simple strategies are easier to debug, backtest, and explain. Complexity often reduces, not improves, performance.

## Development Workflow

### Strategy Development Lifecycle

1. **Research Phase**: Document hypothesis, define entry/exit rules, identify data requirements
2. **Backtest Phase**: Write failing backtest, implement strategy, validate historical performance
3. **Paper Trading Phase**: Deploy to simulated environment, validate real-time behavior without capital risk
4. **Live Deployment Phase**: Gradual capital allocation (1% → 5% → 10% → full) with monitoring gates

**Mandatory Gates**:
- Backtest Sharpe ratio >1.0 before paper trading
- Paper trading for minimum 30 days before live capital
- Risk manager approval required for strategies managing >10% of portfolio

### Code Review Requirements

- All strategy PRs MUST include backtest results and risk parameters
- Reviewers MUST verify Constitution compliance (use checklist from `.specify/templates/checklist-template.md`)
- Performance-critical code MUST include benchmarks (`:timer.tc` measurements)
- Breaking changes to strategy APIs require migration plan and version bump

## Technology Constraints

### Elixir/Phoenix Stack

- **Language**: Elixir 1.17+ (OTP 27+)
- **Framework**: Phoenix 1.7+ for web interfaces, Phoenix LiveView for dashboards
- **Storage**: PostgreSQL for transactional data, TimescaleDB extension for time-series market data
- **Real-Time**: Phoenix PubSub for internal events, WebSockets for exchange connections
- **Testing**: ExUnit for unit/integration tests, Wallaby for end-to-end UI tests

### Prohibited Practices

- **No shared mutable state** between strategies (use message passing via GenServer)
- **No synchronous HTTP calls** in hot path (async Task-based approaches only)
- **No untyped configuration** (use `@behaviour` and specs for strategy contracts)
- **No silent failures** - all errors MUST crash and restart under supervision (let it crash philosophy)

## Governance

### Amendment Process

1. Propose amendment via PR to `.specify/memory/constitution.md`
2. Document rationale and impact analysis in PR description
3. Update affected templates (plan, spec, tasks, checklist) in same PR
4. Require approval from project maintainer(s)
5. Increment version per semantic versioning rules below

### Versioning Policy

- **MAJOR** (X.0.0): Remove or redefine core principle (e.g., remove mandatory backtesting)
- **MINOR** (0.X.0): Add new principle, expand governance section, add mandatory constraints
- **PATCH** (0.0.X): Clarifications, wording improvements, typo fixes, non-semantic updates

### Compliance Review

- Constitution compliance MUST be verified during code review (use `/speckit.checklist`)
- Complexity violations require explicit justification in `plan.md` Complexity Tracking table
- Annual constitution review scheduled to remove obsolete rules and incorporate lessons learned

**Version**: 1.0.0 | **Ratified**: 2025-12-03 | **Last Amended**: 2025-12-03
