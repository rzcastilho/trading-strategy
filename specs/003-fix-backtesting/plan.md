# Implementation Plan: Fix Backtesting Issues

**Branch**: `003-fix-backtesting` | **Date**: 2026-02-03 | **Spec**: [spec.md](./spec.md)
**Input**: Feature specification from `/specs/003-fix-backtesting/spec.md`

**Note**: This template is filled in by the `/speckit.plan` command. See `.specify/templates/commands/plan.md` for the execution workflow.

## Summary

Fix critical issues in the backtesting feature to provide accurate progress tracking, complete equity curve visualization, reliable state management across restarts, accurate trade analytics, and comprehensive test coverage. This is a bug fix and reliability improvement feature, not a new trading strategy implementation.

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

**FEATURE TYPE**: Bug Fix / Infrastructure Improvement (not a new trading strategy)

This feature fixes the existing backtesting engine and does not introduce a new trading strategy. Constitution principles still apply where relevant:

**Strategy-as-Library** (Principle I):
- [x] N/A - This is infrastructure work on the backtesting engine itself
- [x] Independent unit tests planned (>80% coverage target) - **APPLIES**: FR-008 requires comprehensive unit test coverage
- [x] No dependencies on other strategy libraries - **APPLIES**: Engine remains independent

**Backtesting Required** (Principle II - NON-NEGOTIABLE):
- [x] N/A - This feature IS the backtesting engine being fixed
- [x] **META-COMPLIANCE**: These fixes ensure future strategies can meet Principle II requirements

**Risk Management First** (Principle III - NON-NEGOTIABLE):
- [x] N/A - Not implementing a new strategy with trading decisions
- [x] **META-COMPLIANCE**: Accurate PnL and metrics calculation enables risk analysis

**Observability & Auditability** (Principle IV):
- [x] **APPLIES**: FR-006 requires reliable state management with persistence
- [x] **APPLIES**: FR-004/FR-005 ensure trade-level auditability (PnL, duration, linking signals)
- [x] Structured logging already exists, improvements in scope for progress tracking

**Real-Time Data Contracts** (Principle V):
- [x] N/A - Not modifying market data ingestion layer
- [x] Existing contracts preserved

**Performance & Latency Discipline** (Principle VI):
- [x] **APPLIES**: FR-011 requires optimizing O(n²) complexity to avoid degradation
- [x] **APPLIES**: SC-006 requires backtests to handle 10,000+ bars without memory errors
- [x] Latency targets apply to execution engine (out of scope for this backtest fix)

**Simplicity & Transparency** (Principle VII):
- [x] **APPLIES**: Fixes are focused and minimal - no architectural overhauls
- [x] YAGNI strictly enforced - only fix documented bugs, no speculative features
- [x] No complexity violations anticipated

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

**No Constitution Violations** - All fixes align with simplicity principles:
- Progress tracking: GenServer + ETS (standard Elixir patterns)
- Equity curve storage: JSONB column (minimal schema changes)
- Trade PnL: Decimal field (straightforward addition)
- Concurrency: Token-based semaphore (simple, single-node appropriate)
- State persistence: DynamicSupervisor (OTP best practice)

No complex abstractions, no premature optimization, no architectural overhauls.

---

## Phase 0: Research Summary

**Completed**: 2026-02-03

**Key Decisions**:
1. **Progress Tracking**: GenServer + ETS for fast concurrent reads
2. **Equity Curve Storage**: JSONB in PerformanceMetrics (sampled to 1000 points)
3. **Trade PnL**: Add `pnl` field to Trade schema, calculate at execution time
4. **State Persistence**: DynamicSupervisor + checkpointing every 1000 bars
5. **Concurrent Limiting**: Token-based semaphore with FIFO queue (max 5 concurrent)
6. **Performance**: Map-based position indexing to eliminate O(n²) complexity
7. **Testing**: ExUnit + StreamData for property-based edge case testing

**Research Document**: `specs/003-fix-backtesting/research.md`

---

## Phase 1: Design & Contracts Summary

**Completed**: 2026-02-03

**Artifacts Generated**:
1. **Data Model** (`data-model.md`):
   - Migration: Add `pnl`, `duration_seconds`, `entry_price`, `exit_price` to trades
   - Migration: Add `equity_curve`, `equity_curve_metadata` to performance_metrics
   - Migration: Add `queued_at` to trading_sessions, enhance metadata structure
   - In-memory: ProgressTracker ETS table, ConcurrencyManager state
   - Indexes: Added for performance (pnl, status+updated_at)

2. **API Contracts** (`contracts/backtest_api.yaml`):
   - Enhanced `GET /backtests/{id}/progress` with accurate real-time tracking
   - Updated `GET /backtests/{id}` to include equity curve and complete config
   - Added queue status fields to creation response
   - Trade objects now include `pnl`, `duration_seconds`, `entry_price`, `exit_price`
   - OpenAPI 3.0 specification with full request/response examples

3. **Quickstart Guide** (`quickstart.md`):
   - 7-phase implementation plan with estimated times
   - Step-by-step code examples for each module
   - Testing strategies and validation checklists
   - Troubleshooting common issues

**Agent Context Updated**: CLAUDE.md synchronized with new patterns

---

## Post-Design Constitution Check

**Re-evaluated**: 2026-02-03 (after Phase 1 completion)

### Design Validation Against Constitution

**Strategy-as-Library** (Principle I):
- ✅ Backtesting engine remains independent module
- ✅ Unit test coverage planned >80% (Phase 7)
- ✅ No new cross-dependencies introduced

**Backtesting Required** (Principle II - NON-NEGOTIABLE):
- ✅ **META-COMPLIANCE MAINTAINED**: Fixes enable future strategies to meet backtesting requirements
- ✅ Accurate metrics calculation essential for strategy validation

**Risk Management First** (Principle III - NON-NEGOTIABLE):
- ✅ N/A - Not implementing trading strategy
- ✅ Accurate PnL tracking supports risk analysis

**Observability & Auditability** (Principle IV):
- ✅ **ENHANCED**: Real-time progress tracking improves observability
- ✅ **ENHANCED**: Trade-level PnL/duration enables granular audit trails
- ✅ **ENHANCED**: Equity curve persistence enables post-mortem analysis
- ✅ State management improvements align with GenServer auditability

**Real-Time Data Contracts** (Principle V):
- ✅ N/A - Not modifying market data layer
- ✅ Existing contracts preserved

**Performance & Latency Discipline** (Principle VI):
- ✅ **IMPROVED**: O(n²) complexity addressed with Map-based indexing
- ✅ **IMPROVED**: ETS table with read_concurrency for fast progress lookups
- ✅ Benchmark plan included (10K, 50K, 100K bars)

**Simplicity & Transparency** (Principle VII):
- ✅ **ADHERED**: All solutions use standard Elixir/OTP patterns
- ✅ GenServer, ETS, DynamicSupervisor (not custom abstractions)
- ✅ JSONB storage (not new tables/relationships)
- ✅ YAGNI enforced: Only fixes documented bugs, no speculative features

### Final Verdict

**CONSTITUTION COMPLIANT** ✅

All design decisions align with project principles. No complexity violations. Implementation ready to proceed to Phase 2 (Tasks).

---

## Implementation Readiness

**Phase 0 (Research)**: ✅ Complete
**Phase 1 (Design & Contracts)**: ✅ Complete
**Phase 2 (Tasks)**: ⏳ Ready to generate (use `/speckit.tasks` command)

**Deliverables**:
- ✅ `research.md` - All unknowns resolved
- ✅ `data-model.md` - Complete schema changes documented
- ✅ `contracts/backtest_api.yaml` - OpenAPI specification
- ✅ `quickstart.md` - Implementation guide
- ✅ CLAUDE.md updated with new patterns

**Next Steps**:
1. Generate tasks with `/speckit.tasks` command
2. Review and approve task breakdown
3. Begin implementation following quickstart guide
4. Run comprehensive test suite (>80% coverage goal)
5. Validate all functional requirements (FR-001 through FR-016)
6. Verify success criteria (SC-001 through SC-010)
