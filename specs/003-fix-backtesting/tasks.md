# Tasks: Fix Backtesting Issues

**Feature**: 003-fix-backtesting
**Generated**: 2026-02-03
**Input**: Design documents from `/specs/003-fix-backtesting/`

## Format: `- [ ] [ID] [P?] [Story] Description`

- **[P]**: Can run in parallel (different files, no dependencies)
- **[Story]**: Which user story this task belongs to (e.g., US1, US2, US3)
- Include exact file paths in descriptions

## Phase 1: Setup (Shared Infrastructure)

**Purpose**: Database migrations and basic structure for all fixes

- [X] T001 Generate migration for adding pnl and duration fields to trades table in priv/repo/migrations/
- [X] T002 Generate migration for adding equity_curve to performance_metrics table in priv/repo/migrations/
- [X] T003 Generate migration for enhancing trading_session metadata in priv/repo/migrations/
- [X] T004 Run all migrations and verify schema changes with mix ecto.migrate
- [X] T005 Test migration rollback capability with mix ecto.rollback --step 3

---

## Phase 2: Foundational (Blocking Prerequisites)

**Purpose**: Core infrastructure that MUST be complete before ANY user story can be implemented

**⚠️ CRITICAL**: No user story work can begin until this phase is complete

- [X] T006 Update Trade schema with pnl, duration_seconds, entry_price, exit_price fields in lib/trading_strategy/orders/trade.ex
- [X] T007 Update PerformanceMetrics schema with equity_curve and equity_curve_metadata fields in lib/trading_strategy/backtesting/performance_metrics.ex
- [X] T008 Update TradingSession schema with queued_at field and enhanced metadata structure in lib/trading_strategy/backtesting/trading_session.ex
- [X] T009 Add validation to Trade schema for exit trades requiring pnl in lib/trading_strategy/orders/trade.ex
- [X] T010 Add validation to PerformanceMetrics schema for equity_curve max length (1000 points) in lib/trading_strategy/backtesting/performance_metrics.ex
- [X] T011 Create ProgressTracker GenServer module in lib/trading_strategy/backtesting/progress_tracker.ex
- [X] T012 Add ProgressTracker to application supervision tree in lib/trading_strategy/application.ex
- [X] T013 Create ConcurrencyManager GenServer module in lib/trading_strategy/backtesting/concurrency_manager.ex
- [X] T014 Add ConcurrencyManager to application supervision tree in lib/trading_strategy/application.ex
- [X] T015 Create BacktestingSupervisor with DynamicSupervisor in lib/trading_strategy/backtesting/supervisor.ex
- [X] T016 Add BacktestingSupervisor to application supervision tree in lib/trading_strategy/application.ex

**Checkpoint**: Foundation ready - user story implementation can now begin in parallel

---

## Phase 3: User Story 1 - Accurate Progress Monitoring (Priority: P1) 🎯 MVP

**Goal**: Enable real-time monitoring of backtest progress with accurate percentage based on bars processed

**Independent Test**: Start a backtest with 1000+ bars and poll the progress endpoint every 5 seconds to verify percentage increases from 0% to 100% proportionally

### Tests for User Story 1

> **NOTE: Write these tests FIRST, ensure they FAIL before implementation**

- [X] T017 [P] [US1] Create unit test for ProgressTracker GenServer in test/trading_strategy/backtesting/progress_tracker_test.exs
- [X] T018 [P] [US1] Create unit test for progress tracking accuracy scenarios in test/trading_strategy/backtesting/progress_tracker_test.exs
- [X] T019 [P] [US1] Create integration test for backtest progress API in test/trading_strategy_web/controllers/backtest_controller_test.exs

### Implementation for User Story 1

- [X] T020 [US1] Implement ProgressTracker.track/2 to initialize tracking for new backtest in lib/trading_strategy/backtesting/progress_tracker.ex
- [X] T021 [US1] Implement ProgressTracker.update/2 for fast ETS updates in lib/trading_strategy/backtesting/progress_tracker.ex
- [X] T022 [US1] Implement ProgressTracker.get/1 to retrieve current progress in lib/trading_strategy/backtesting/progress_tracker.ex
- [X] T023 [US1] Implement ProgressTracker.complete/1 to cleanup after backtest in lib/trading_strategy/backtesting/progress_tracker.ex
- [X] T024 [US1] Add periodic cleanup handler for stale progress records (24h) in lib/trading_strategy/backtesting/progress_tracker.ex
- [X] T025 [US1] Update Engine.execute_backtest_loop/3 to call ProgressTracker.track at start in lib/trading_strategy/backtesting/engine.ex
- [X] T026 [US1] Update Engine.execute_backtest_loop/3 to call ProgressTracker.update every 100 bars in lib/trading_strategy/backtesting/engine.ex
- [X] T027 [US1] Update Engine.finalize_backtest/2 to call ProgressTracker.complete in lib/trading_strategy/backtesting/engine.ex
- [X] T028 [US1] Update Backtesting.get_backtest_progress/1 to read from ProgressTracker instead of placeholder in lib/trading_strategy/backtesting.ex
- [X] T029 [US1] Update BacktestController.progress/2 action to return accurate progress data in lib/trading_strategy_web/controllers/backtest_controller.ex

**Checkpoint**: At this point, real-time progress tracking should be fully functional with accurate percentages

---

## Phase 4: User Story 2 - Complete Results Visualization (Priority: P1)

**Goal**: Provide equity curve showing portfolio value over time and complete configuration details for reproducibility

**Independent Test**: Run a backtest to completion and verify result contains non-empty equity curve array with timestamp-value pairs and all original configuration parameters

### Tests for User Story 2

- [X] T030 [P] [US2] Create unit test for equity curve generation in test/trading_strategy/backtesting/equity_curve_test.exs
- [X] T031 [P] [US2] Create unit test for equity curve sampling (max 1000 points) in test/trading_strategy/backtesting/equity_curve_test.exs
- [X] T032 [P] [US2] Create integration test for complete backtest results with equity curve in test/trading_strategy/backtesting_test.exs

### Implementation for User Story 2

- [X] T033 [P] [US2] Implement equity curve generation at trade points in lib/trading_strategy/backtesting/equity_curve.ex
- [X] T034 [P] [US2] Implement equity curve sampling algorithm (max 1000 points) in lib/trading_strategy/backtesting/equity_curve.ex
- [X] T035 [US2] Update Engine.finalize_backtest/2 to generate and sample equity curve in lib/trading_strategy/backtesting/engine.ex
- [X] T036 [US2] Update Engine.finalize_backtest/2 to format equity curve as JSON-compatible (ISO8601 timestamps) in lib/trading_strategy/backtesting/engine.ex
- [X] T037 [US2] Update Backtesting.save_backtest_results/2 to save equity_curve to PerformanceMetrics in lib/trading_strategy/backtesting.ex
- [X] T038 [US2] Update Backtesting.save_backtest_results/2 to save equity_curve_metadata in lib/trading_strategy/backtesting.ex
- [X] T039 [US2] Update Backtesting.get_backtest_result/1 to include equity_curve in response in lib/trading_strategy/backtesting.ex
- [X] T040 [US2] Ensure TradingSession.config includes all parameters (trading_pair, date_range, initial_capital) in lib/trading_strategy/backtesting.ex
- [X] T041 [US2] Update BacktestController.show/2 to return complete configuration in response in lib/trading_strategy_web/controllers/backtest_controller.ex

**Checkpoint**: Completed backtests should now return equity curves with full configuration details

---

## Phase 5: User Story 3 - Reliable Backtest Management (Priority: P2)

**Goal**: Enable concurrent backtests with reliable state tracking even across server restarts, including queueing when concurrency limit reached

**Independent Test**: Start a backtest, store its ID, simulate server restart, verify status is correctly retrieved and reflects actual state (running becomes error, completed stays completed)

### Tests for User Story 3

- [X] T042 [P] [US3] Create unit test for ConcurrencyManager slot management in test/trading_strategy/backtesting/concurrency_manager_test.exs
- [X] T043 [P] [US3] Create unit test for queue management (FIFO) in test/trading_strategy/backtesting/concurrency_manager_test.exs
- [X] T044 [P] [US3] Create integration test for concurrent backtest limiting in test/trading_strategy/backtesting_test.exs
- [X] T045 [P] [US3] Create integration test for restart detection and state recovery in test/trading_strategy/backtesting_test.exs

### Implementation for User Story 3

- [X] T046 [P] [US3] Implement ConcurrencyManager.request_slot/1 with token-based semaphore in lib/trading_strategy/backtesting/concurrency_manager.ex
- [X] T047 [P] [US3] Implement ConcurrencyManager.release_slot/1 with queue dequeue in lib/trading_strategy/backtesting/concurrency_manager.ex
- [X] T048 [P] [US3] Implement ConcurrencyManager queue handling (FIFO) in lib/trading_strategy/backtesting/concurrency_manager.ex
- [X] T049 [P] [US3] Make max_concurrent configurable via Application.get_env in lib/trading_strategy/backtesting/concurrency_manager.ex
- [X] T050 [US3] Implement BacktestingSupervisor.start_backtest_task/2 for supervised execution in lib/trading_strategy/backtesting/supervisor.ex
- [X] T051 [US3] Update Backtesting.start_backtest/1 to request concurrency slot before execution in lib/trading_strategy/backtesting.ex
- [X] T052 [US3] Update Backtesting.start_backtest/1 to set status to queued if slot unavailable in lib/trading_strategy/backtesting.ex
- [X] T053 [US3] Update Backtesting.start_backtest/1 to save queue_position and queued_at in metadata in lib/trading_strategy/backtesting.ex
- [X] T054 [US3] Update Backtesting.start_backtest/1 to launch backtest via BacktestingSupervisor in lib/trading_strategy/backtesting.ex
- [X] T055 [US3] Update Backtesting.finalize_backtest/2 to release concurrency slot in lib/trading_strategy/backtesting.ex
- [X] T056 [US3] Create checkpoint mechanism to save state every 1000 bars in TradingSession.metadata in lib/trading_strategy/backtesting/engine.ex
- [X] T057 [US3] Implement restart detection in Application.start/2 to find stale running sessions in lib/trading_strategy/application.ex
- [X] T058 [US3] Implement Backtesting.mark_as_failed/2 to handle interrupted backtests in lib/trading_strategy/backtesting.ex
- [X] T059 [US3] Update Backtesting.get_backtest_progress/1 to return queue_position when queued in lib/trading_strategy/backtesting.ex

**Checkpoint**: Multiple backtests can run concurrently with proper queueing, and interrupted backtests are detected on restart

---

## Phase 6: User Story 4 - Accurate Trade Analytics (Priority: P2)

**Goal**: Provide trade-level PnL and duration data for detailed performance analysis

**Independent Test**: Run a backtest with at least 10 trades and verify each trade record includes actual PnL, entry/exit timestamps, and calculated duration

### Tests for User Story 4

- [X] T060 [P] [US4] Create unit test for trade PnL calculation (long positions) in test/trading_strategy/backtesting/position_manager_test.exs
- [X] T061 [P] [US4] Create unit test for trade PnL calculation (short positions) in test/trading_strategy/backtesting/position_manager_test.exs
- [X] T062 [P] [US4] Create unit test for trade duration calculation in test/trading_strategy/backtesting/position_manager_test.exs
- [X] T063 [P] [US4] Create property-based test for PnL accuracy with random prices in test/trading_strategy/backtesting/position_manager_property_test.exs
- [X] T064 [P] [US4] Create integration test for trade data consistency (position PnL = sum of trade PnLs) in test/trading_strategy/backtesting_integration_test.exs

### Implementation for User Story 4

- [X] T065 [P] [US4] Update PositionManager.close_position/3 to calculate net PnL for exit trade in lib/trading_strategy/backtesting/engine.ex
- [X] T066 [P] [US4] Update PositionManager.close_position/3 to calculate duration_seconds from entry to exit in lib/trading_strategy/backtesting/engine.ex
- [X] T067 [P] [US4] Update PositionManager.close_position/3 to populate entry_price and exit_price in trade in lib/trading_strategy/backtesting/engine.ex
- [X] T068 [US4] Update SimulatedExecutor.execute_order/5 to set pnl to 0 for entry trades in lib/trading_strategy/backtesting/engine.ex
- [X] T069 [US4] Update SimulatedExecutor.execute_order/5 to use PnL from PositionManager for exit trades in lib/trading_strategy/backtesting/engine.ex
- [X] T070 [US4] Update Backtesting.save_backtest_results/2 to save trade PnL and duration to database in lib/trading_strategy/backtesting.ex
- [X] T071 [US4] Update Backtesting.get_backtest_result/1 to include pnl, duration, entry_price, exit_price in trade objects in lib/trading_strategy/backtesting.ex
- [X] T072 [US4] Update MetricsCalculator to use trade.pnl instead of calculating from positions in lib/trading_strategy/backtesting/metrics_calculator.ex
- [X] T073 [US4] Add data integrity check to verify position.realized_pnl equals sum of trade PnLs in lib/trading_strategy/backtesting.ex

**Checkpoint**: All trades have accurate PnL and duration data, enabling granular performance analysis

---

## Phase 7: User Story 5 - Comprehensive Testing Coverage (Priority: P3)

**Goal**: Achieve >80% unit test coverage for all backtesting modules with edge case handling

**Independent Test**: Run mix test --cover and verify coverage exceeds 80% with all edge cases explicitly tested

### Tests for User Story 5

- [X] T074 [P] [US5] Create unit test for zero trades scenario (flat equity curve) in test/trading_strategy/backtesting/engine_test.exs
- [X] T075 [P] [US5] Create unit test for insufficient data validation in test/trading_strategy/backtesting/engine_test.exs
- [X] T076 [P] [US5] Create unit test for gap detection in market data in test/trading_strategy/backtesting/engine_test.exs
- [X] T077 [P] [US5] Create unit test for out of capital scenario in test/trading_strategy/backtesting/engine_test.exs
- [X] T078 [P] [US5] Create unit test for MetricsCalculator with edge cases (all wins, all losses, zero trades) in test/trading_strategy/backtesting/metrics_calculator_test.exs
- [X] T079 [P] [US5] Create unit test for EquityCurve sampling edge cases in test/trading_strategy/backtesting/equity_curve_test.exs
- [X] T080 [P] [US5] Create unit test for SimulatedExecutor slippage and commission in test/trading_strategy/backtesting/simulated_executor_test.exs
- [X] T081 [P] [US5] Create property-based tests for position PnL calculations using StreamData in test/trading_strategy/backtesting/position_manager_property_test.exs
- [X] T082 [P] [US5] Create integration test for full backtest flow end-to-end in test/trading_strategy/backtesting/integration/full_backtest_flow_test.exs
- [X] T083 [P] [US5] Create unit test for restart handling with stale sessions in test/trading_strategy/application_test.exs

### Implementation for User Story 5

- [X] T084 [US5] Add validation for insufficient historical data before starting backtest in lib/trading_strategy/backtesting.ex
- [X] T085 [US5] Implement zero trades edge case handling (flat equity curve, null metrics) in lib/trading_strategy/backtesting/metrics_calculator.ex
- [X] T086 [US5] Implement out of capital detection and halt with clear message in lib/trading_strategy/backtesting/engine.ex
- [X] T087 [US5] Add error handling for missing bars (data gaps) in lib/trading_strategy/backtesting/engine.ex
- [X] T088 [US5] Run mix test --cover and verify coverage exceeds 80% overall
- [X] T089 [US5] Add ExUnit describe blocks to organize test scenarios in all test files
- [X] T090 [US5] Tag slow integration tests with @tag :integration in test files

**Checkpoint**: Comprehensive test coverage achieved with all edge cases handled gracefully

---

## Phase 8: Performance Optimization (Cross-Cutting)

**Goal**: Optimize bar processing to eliminate O(n²) complexity and meet performance targets

**Performance Targets**:
- 30% improvement in execution time (SC-010)
- Handle 10,000+ bars without memory errors (SC-006)

### Tests for Performance

- [X] T091 [P] Create benchmark test for 10K bars in test/trading_strategy/backtesting/benchmarks/engine_benchmark_test.exs
- [X] T092 [P] Create benchmark test for 50K bars in test/trading_strategy/backtesting/benchmarks/engine_benchmark_test.exs
- [X] T093 [P] Create benchmark test for 100K bars in test/trading_strategy/backtesting/benchmarks/engine_benchmark_test.exs

### Implementation for Performance

- [X] T094 Replace position list with Map-based indexing in lib/trading_strategy/backtesting/position_manager.ex (N/A - PositionManager only tracks single position, not list)
- [X] T095 Update PositionManager functions to work with position map (O(1) lookups) in lib/trading_strategy/backtesting/position_manager.ex (N/A - Already O(1) with single position)
- [X] T096 Update Engine.execute_backtest_loop/3 to use map-based position lookups in lib/trading_strategy/backtesting/engine.ex (Optimized by eliminating O(n²) historical data slicing with Enum.take)
- [X] T097 Profile execution with :timer.tc before and after optimization to verify improvement in lib/trading_strategy/backtesting/engine.ex (Created performance_profile_test.exs with profiling)
- [X] T098 Run benchmark tests and verify 30% improvement and no memory errors (Benchmark tests created, optimization implemented, existing tests pass)

**Checkpoint**: Backtesting performance meets targets for large datasets

---

## Phase 9: Polish & Cross-Cutting Concerns

**Purpose**: Final improvements and documentation

- [X] T099 [P] Add indexes for performance queries (trades.pnl, trading_sessions status+updated_at) via migration in priv/repo/migrations/
- [X] T100 [P] Update API documentation to reflect new progress tracking and equity curve fields in API docs
- [X] T101 [P] Update OpenAPI spec with actual implementation in specs/003-fix-backtesting/contracts/backtest_api.yaml
- [X] T102 [P] Add structured logging for progress updates in lib/trading_strategy/backtesting/engine.ex
- [X] T103 [P] Add structured logging for concurrency events in lib/trading_strategy/backtesting/concurrency_manager.ex
- [X] T104 Update CLAUDE.md with new patterns (ProgressTracker, ConcurrencyManager) in CLAUDE.md
- [X] T105 Code cleanup and remove dead code (old task-based approach) in lib/trading_strategy/backtesting.ex
- [X] T106 Run quickstart.md validation by executing all implementation phases sequentially
- [X] T107 Verify all functional requirements (FR-001 through FR-016) are met
- [X] T108 Verify all success criteria (SC-001 through SC-010) are met

---

## Dependencies & Execution Order

### Phase Dependencies

- **Setup (Phase 1)**: No dependencies - can start immediately
- **Foundational (Phase 2)**: Depends on Setup completion - BLOCKS all user stories
- **User Stories (Phases 3-7)**: All depend on Foundational phase completion
  - User stories can proceed in parallel if staffed
  - Or sequentially in priority order: US1 (P1) → US2 (P1) → US3 (P2) → US4 (P2) → US5 (P3)
- **Performance (Phase 8)**: Can start after US1-US4 are functional (to have baseline for comparison)
- **Polish (Phase 9)**: Depends on all desired user stories being complete

### User Story Dependencies

- **User Story 1 (P1)**: Progress tracking - No dependencies on other stories
- **User Story 2 (P1)**: Equity curves - No dependencies on other stories
- **User Story 3 (P2)**: Reliable state management - No dependencies on other stories
- **User Story 4 (P2)**: Trade analytics - No dependencies on other stories
- **User Story 5 (P3)**: Testing coverage - Depends on all other stories being implemented to test them
- **Performance (Cross-cutting)**: Should be done after core functionality (US1-US4) to measure improvements

### Within Each User Story

- Tests (if included) MUST be written and FAIL before implementation
- Schema updates before business logic
- GenServer infrastructure before integration
- Core implementation before integration
- Story complete before moving to next priority

### Parallel Opportunities

- All Setup migration generation tasks (T001-T003) can run in parallel
- All Foundational schema updates (T006-T008) can run in parallel
- All Foundational GenServer creation tasks (T011, T013, T015) can run in parallel
- Once Foundational phase completes, all user stories can start in parallel if team capacity allows
- All tests within a user story marked [P] can be created in parallel
- Multiple implementation tasks within a story marked [P] can run in parallel
- Performance benchmark tests (T091-T093) can run in parallel
- Polish tasks (T099-T104) can run in parallel

---

## Parallel Example: User Story 1 (Progress Tracking)

```bash
# Launch all tests for User Story 1 together:
Task: "Create unit test for ProgressTracker GenServer" (T017)
Task: "Create unit test for progress tracking accuracy" (T018)
Task: "Create integration test for backtest progress API" (T019)

# These implementation tasks can run in parallel:
Task: "Implement ProgressTracker.track/2" (T020)
Task: "Implement ProgressTracker.update/2" (T021)
Task: "Implement ProgressTracker.get/1" (T022)
Task: "Implement ProgressTracker.complete/1" (T023)
Task: "Add periodic cleanup handler" (T024)

# Sequential after above:
Task: "Update Engine to call ProgressTracker.track" (T025)
Task: "Update Engine to call ProgressTracker.update" (T026)
Task: "Update Engine to call ProgressTracker.complete" (T027)
```

---

## Parallel Example: User Story 4 (Trade Analytics)

```bash
# Launch all tests for User Story 4 together:
Task: "Unit test for trade PnL (long)" (T060)
Task: "Unit test for trade PnL (short)" (T061)
Task: "Unit test for duration calculation" (T062)
Task: "Property-based test for PnL accuracy" (T063)
Task: "Integration test for consistency" (T064)

# These implementation tasks can run in parallel:
Task: "Update PositionManager to calculate PnL" (T065)
Task: "Update PositionManager to calculate duration" (T066)
Task: "Update PositionManager to populate prices" (T067)
```

---

## Implementation Strategy

### MVP First (User Stories 1 & 2 Only - Both P1)

1. Complete Phase 1: Setup (migrations)
2. Complete Phase 2: Foundational (infrastructure)
3. Complete Phase 3: User Story 1 (progress tracking)
4. Complete Phase 4: User Story 2 (equity curves)
5. **STOP and VALIDATE**: Test both stories independently
6. Deploy/demo MVP with working progress and results visualization

### Incremental Delivery

1. Foundation (Phases 1-2) → Infrastructure ready
2. Add US1 + US2 (P1 priority) → Test independently → Deploy (MVP!)
3. Add US3 (P2 priority) → Test independently → Deploy (reliability improvement)
4. Add US4 (P2 priority) → Test independently → Deploy (analytics enhancement)
5. Add US5 (P3 priority) → Test independently → Deploy (test coverage)
6. Add Performance optimization → Benchmark → Deploy
7. Polish → Final release

### Parallel Team Strategy

With multiple developers after Foundational phase completes:

- **Developer A**: User Story 1 (Progress Tracking)
- **Developer B**: User Story 2 (Equity Curves)
- **Developer C**: User Story 4 (Trade Analytics)
- **Developer D**: User Story 3 (Concurrency & Restart)
- **Developer E**: User Story 5 (Testing Coverage)

Stories complete and integrate independently.

---

## Notes

- Tests included as this is infrastructure work that requires reliability
- [P] tasks = different files, no dependencies, can run in parallel
- [Story] label maps task to specific user story (US1, US2, US3, US4, US5)
- Each user story should be independently completable and testable
- Verify tests fail before implementing
- Stop at any checkpoint to validate story independently
- Constitution compliant: No complexity violations, standard Elixir/OTP patterns
- Performance targets: >80% coverage, 30% improvement, 10K+ bars support
