# Implementation Plan: Comprehensive Testing for Strategy Editor Synchronization

**Branch**: `007-test-builder-dsl-sync` | **Date**: 2026-02-11 | **Spec**: [spec.md](./spec.md)
**Input**: Feature specification from `/specs/007-test-builder-dsl-sync/spec.md`

**Note**: This template is filled in by the `/speckit.plan` command. See `.specify/templates/commands/plan.md` for the execution workflow.

## Summary

Create a comprehensive test suite (50+ scenarios) to validate the bidirectional synchronization between the visual strategy builder and DSL editor from Feature 005. Tests will verify synchronization performance (<500ms), comment preservation (90%+ retention), undo/redo responsiveness (<50ms), and error handling across 6 user stories. Tests will be organized by priority (P1: sync, P2: comments/undo, P3: performance/errors), use version-controlled code fixtures, output results to console only, and maintain 0% flakiness through deterministic design.

## Technical Context

**Language/Version**: Elixir 1.17+ (OTP 27+)
**Primary Dependencies**: ExUnit (test framework), Wallaby (browser automation), Phoenix LiveView (testing target)
**Storage**: PostgreSQL (test database), version-controlled `.exs` fixtures for test data
**Testing Framework**: ExUnit with custom test organization by user story (US1-US6)
**Target Platform**: macOS/Linux (test execution environment)
**Project Type**: Test suite for bidirectional strategy editor synchronization (Feature 005)
**Performance Goals**: Verify <500ms synchronization latency, <50ms undo/redo response time
**Test Data**: Code fixtures ranging from simple (1-2 indicators) to large (50 indicators, 1000+ DSL lines)
**Constraints**: Deterministic tests (0% flakiness), fail-fast strategy (no retries), console-only reporting
**Scale/Scope**: 50+ test scenarios across 6 user stories (P1: sync, P2: comments/undo, P3: performance/errors)

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

**Strategy-as-Library** (Principle I):
- [x] N/A - This is a test suite, not a trading strategy implementation
- [x] Test suite itself follows modular organization (tests by user story)
- [x] Test fixtures are self-contained and independently usable

**Backtesting Required** (Principle II - NON-NEGOTIABLE):
- [x] N/A - No trading strategy being implemented in this feature
- [x] This feature tests the infrastructure used to build/edit strategies

**Risk Management First** (Principle III - NON-NEGOTIABLE):
- [x] N/A - No trading strategy being implemented in this feature
- [x] Tests verify the editor that will be used to define risk parameters

**Observability & Auditability** (Principle IV):
- [x] Test results logged to console with summary statistics (FR-017)
- [x] Performance metrics tracked (mean/median/P95 latency) (SC-009)
- [x] Failed test details captured with error information

**Real-Time Data Contracts** (Principle V):
- [x] N/A - Testing UI synchronization, not market data contracts
- [x] Tests verify contract between builder and DSL editor

**Performance & Latency Discipline** (Principle VI):
- [x] Tests verify <500ms synchronization latency target (SC-003, FR-001, FR-002)
- [x] Tests verify <50ms undo/redo response time (SC-005, FR-004)
- [x] Performance benchmarks match Feature 005 targets (FR-012)

**Simplicity & Transparency** (Principle VII):
- [x] Tests organized by user story for clarity (FR-018)
- [x] Test data uses simple code fixtures (FR-019)
- [x] Deterministic design, no complex retry logic (FR-020)

**Constitution Alignment**: This feature is a **testing-only feature** and does not implement trading strategies. Principles I, II, III, and V are not applicable. Principles IV, VI, and VII are followed through structured test reporting, performance validation, and simple deterministic test design.

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
test/
├── trading_strategy_web/
│   └── live/
│       └── strategy_editor_live/
│           ├── synchronization_test.exs           # US1: Builder-to-DSL sync tests
│           ├── dsl_to_builder_sync_test.exs      # US2: DSL-to-builder sync tests
│           ├── comment_preservation_test.exs      # US3: Comment preservation tests
│           ├── undo_redo_test.exs                # US4: Undo/redo functionality tests
│           ├── performance_test.exs              # US5: Performance validation tests
│           ├── error_handling_test.exs           # US6: Error handling tests
│           └── edge_cases_test.exs               # Cross-cutting edge case tests
│
└── support/
    └── fixtures/
        └── strategies/
            ├── simple_sma_strategy.exs           # 1-2 indicators, minimal DSL
            ├── simple_ema_crossover.exs          # Basic crossover strategy
            ├── medium_5_indicators.exs           # 5 indicators, moderate complexity
            ├── medium_trend_following.exs        # Trend following with multiple rules
            ├── complex_20_indicators.exs         # 20 indicators, performance target
            ├── complex_multi_timeframe.exs       # Multiple timeframes, complex logic
            ├── large_50_indicators.exs           # 50 indicators, stress test
            ├── large_with_comments.exs           # Large strategy with extensive comments
            ├── invalid_syntax.exs                # Error testing fixture
            └── invalid_indicator_ref.exs         # Validation error fixture

# Existing code (not modified by this feature)
lib/
├── trading_strategy/
│   └── strategy_editor/                          # Feature 005 code being tested
│       ├── synchronizer.ex                       # Builder ↔ DSL sync logic
│       ├── validator.ex                          # DSL syntax validation
│       ├── edit_history.ex                       # Undo/redo GenServer
│       └── comment_preserver.ex                  # Comment preservation logic
└── trading_strategy_web/
    └── live/
        └── strategy_editor_live.ex               # LiveView being tested

config/
└── test.exs                                       # Test environment configuration
```

**Structure Decision**: Tests organized by user story (US1-US6) under `test/trading_strategy_web/live/strategy_editor_live/` to mirror the LiveView being tested. Test fixtures stored as version-controlled `.exs` files in `test/support/fixtures/strategies/` with descriptive names indicating complexity level. This organization enables easy navigation and maintenance while following ExUnit conventions.

## Complexity Tracking

> **Fill ONLY if Constitution Check has violations that must be justified**

| Violation | Why Needed | Simpler Alternative Rejected Because |
|-----------|------------|-------------------------------------|
| None | N/A | No constitution violations - testing feature aligns with applicable principles |

---

## Planning Status

**Phase 0: Research** ✅ Complete
- ✅ Research findings consolidated in `research.md`
- ✅ Wallaby & LiveView testing patterns documented
- ✅ Performance testing approach defined (`:timer.tc` + P95 percentile)
- ✅ Test fixture management strategy established
- ✅ Deterministic testing best practices identified (0% flakiness)

**Phase 1: Design & Contracts** ✅ Complete
- ✅ Data model documented in `data-model.md` (5 core entities)
- ✅ Contracts documented in `contracts/README.md` (testing existing Feature 005 contracts)
- ✅ Quickstart guide created in `quickstart.md`
- ✅ Agent context updated in `/CLAUDE.md`

**Next Steps**:
- Run `/speckit.tasks` to generate task breakdown in `tasks.md`
- Implement test suite according to tasks
- Validate 0% flakiness with 10-run script (SC-011)

**Branch**: `007-test-builder-dsl-sync`
**Implementation Plan**: `/Users/castilho/code/github.com/rzcastilho/trading-strategy/specs/007-test-builder-dsl-sync/plan.md`

**Generated Artifacts**:
- `/specs/007-test-builder-dsl-sync/research.md` - Research findings and technology decisions
- `/specs/007-test-builder-dsl-sync/data-model.md` - Test entities and fixtures data model
- `/specs/007-test-builder-dsl-sync/contracts/README.md` - Existing contracts under test
- `/specs/007-test-builder-dsl-sync/quickstart.md` - Test execution guide
- `/CLAUDE.md` - Updated with testing technology stack
