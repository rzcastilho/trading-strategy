# Tasks: Indicator Output Values Display

**Input**: Design documents from `/specs/006-indicator-value-inspection/`
**Prerequisites**: plan.md, spec.md, research.md, data-model.md, quickstart.md, contracts/

**Tests**: Included as per feature specification requirements

**Organization**: Tasks are grouped by user story to enable independent implementation and testing of each story.

## Format: `[ID] [P?] [Story] Description`

- **[P]**: Can run in parallel (different files, no dependencies)
- **[Story]**: Which user story this task belongs to (e.g., US1, US2)
- Include exact file paths in descriptions

## Path Conventions

- Phoenix/Elixir project structure
- Source: `lib/trading_strategy/` and `lib/trading_strategy_web/`
- Tests: `test/trading_strategy/` and `test/trading_strategy_web/`
- Assets: `assets/js/`

---

## Phase 1: Setup (Shared Infrastructure)

**Purpose**: Verify prerequisites and prepare for implementation

- [X] T001 Verify TradingIndicators library is accessible in additional working directories
- [X] T002 [P] Review existing core_components.ex for tooltip patterns in lib/trading_strategy_web/components/core_components.ex
- [X] T003 [P] Review existing Registry module for persistent_term caching pattern in lib/trading_strategy/strategy_editor/registry.ex

---

## Phase 2: Foundational (Blocking Prerequisites)

**Purpose**: Core infrastructure that MUST be complete before ANY user story can be implemented

**⚠️ CRITICAL**: No user story work can begin until this phase is complete

- [X] T004 Create IndicatorMetadata helper module with lazy persistent_term caching in lib/trading_strategy/strategy_editor/indicator_metadata.ex
- [X] T005 Implement format_help/1 function to fetch and format indicator metadata in lib/trading_strategy/strategy_editor/indicator_metadata.ex
- [X] T006 Implement get_output_metadata/1 function with caching in lib/trading_strategy/strategy_editor/indicator_metadata.ex
- [X] T007 Implement format_metadata/2 private function for single-value indicators in lib/trading_strategy/strategy_editor/indicator_metadata.ex
- [X] T008 Implement format_metadata/2 private function for multi-value indicators in lib/trading_strategy/strategy_editor/indicator_metadata.ex
- [X] T009 Add error handling with graceful fallback messages in lib/trading_strategy/strategy_editor/indicator_metadata.ex
- [X] T010 [P] Create tooltip component with ARIA attributes in lib/trading_strategy_web/components/core_components.ex
- [X] T011 [P] Create TooltipHook JavaScript with keyboard navigation in assets/js/hooks/tooltip_hook.js
- [X] T012 [P] Register TooltipHook in Phoenix LiveSocket hooks in assets/js/app.js

**Checkpoint**: Foundation ready - user story implementation can now begin in parallel

---

## Phase 3: User Story 1 - View Output Values When Adding Indicator (Priority: P1) 🎯 MVP

**Goal**: Display indicator output value metadata in the "Add Indicator" form before user commits to adding the indicator, helping them make informed decisions about indicator selection.

**Independent Test**: Select an indicator type (e.g., Bollinger Bands) in the "Add Indicator" form and verify that output value information displays in a tooltip showing all available fields with descriptions, units, and example usage.

### Tests for User Story 1

> **NOTE: Write these tests FIRST, ensure they FAIL before implementation**

- [X] T013 [P] [US1] Unit test for format_help/1 with single-value indicator (SMA) in test/trading_strategy/strategy_editor/indicator_metadata_test.exs
- [X] T014 [P] [US1] Unit test for format_help/1 with multi-value indicator (Bollinger Bands) in test/trading_strategy/strategy_editor/indicator_metadata_test.exs
- [X] T015 [P] [US1] Unit test for error handling when indicator not found in test/trading_strategy/strategy_editor/indicator_metadata_test.exs
- [X] T016 [P] [US1] Unit test for error handling when metadata function missing in test/trading_strategy/strategy_editor/indicator_metadata_test.exs
- [X] T017 [P] [US1] Unit test for caching behavior (cache hit vs cache miss) in test/trading_strategy/strategy_editor/indicator_metadata_test.exs
- [X] T018 [P] [US1] Unit test for fallback content generation in test/trading_strategy/strategy_editor/indicator_metadata_test.exs

### Implementation for User Story 1

- [X] T019 [US1] Add IndicatorMetadata alias to IndicatorBuilder LiveComponent in lib/trading_strategy_web/live/strategy_live/indicator_builder.ex
- [X] T020 [US1] Implement maybe_fetch_indicator_help/1 function in IndicatorBuilder LiveComponent in lib/trading_strategy_web/live/strategy_live/indicator_builder.ex
- [X] T021 [US1] Update select_indicator_type event handler to fetch metadata when indicator selected in lib/trading_strategy_web/live/strategy_live/indicator_builder.ex
- [X] T022 [US1] Add tooltip component with info icon to indicator type selection in lib/trading_strategy_web/live/strategy_live/indicator_builder.ex
- [X] T023 [US1] Add conditional rendering for tooltip (only show if help text available) in lib/trading_strategy_web/live/strategy_live/indicator_builder.ex
- [X] T024 [US1] Add aria-label to info icon button for accessibility in lib/trading_strategy_web/live/strategy_live/indicator_builder.ex

### Integration Tests for User Story 1

- [ ] T025 [P] [US1] Integration test for tooltip display on indicator selection (mouse interaction) in test/trading_strategy_web/live/strategy_builder_live/indicator_builder_test.exs
- [ ] T026 [P] [US1] Integration test for keyboard navigation (Tab, Enter, Escape) in test/trading_strategy_web/live/strategy_builder_live/indicator_builder_test.exs
- [ ] T027 [P] [US1] Integration test for metadata content verification (Bollinger Bands fields) in test/trading_strategy_web/live/strategy_builder_live/indicator_builder_test.exs
- [ ] T028 [P] [US1] Integration test for single-value vs multi-value indicator distinction in test/trading_strategy_web/live/strategy_builder_live/indicator_builder_test.exs
- [ ] T029 [P] [US1] Integration test for fallback behavior when metadata unavailable in test/trading_strategy_web/live/strategy_builder_live/indicator_builder_test.exs

**Checkpoint**: At this point, User Story 1 should be fully functional - users can view indicator metadata when adding indicators

---

## Phase 4: User Story 2 - View Output Values in Configured Indicators List (Priority: P2)

**Goal**: Display indicator output value metadata for already-configured indicators, providing reference material when users are building conditions without needing to remember or look up information elsewhere.

**Independent Test**: Add one or more indicators to a strategy and verify that the configured indicators list shows an info icon for each indicator with a tooltip revealing output value information on hover/click.

### Implementation for User Story 2

- [X] T030 [P] [US2] Locate configured indicators list rendering in IndicatorBuilder or parent LiveView in lib/trading_strategy_web/live/strategy_builder_live/
- [X] T031 [US2] Add metadata fetching for configured indicators in mount or update callback in lib/trading_strategy_web/live/strategy_builder_live/indicator_builder.ex
- [X] T032 [US2] Update configured indicators data structure to include help_text field in lib/trading_strategy_web/live/strategy_builder_live/indicator_builder.ex
- [X] T033 [US2] Add tooltip component with info icon to each configured indicator card in lib/trading_strategy_web/live/strategy_builder_live/indicator_builder.ex
- [X] T034 [US2] Add unique tooltip IDs for each configured indicator (e.g., configured-#{indicator.id}-info) in lib/trading_strategy_web/live/strategy_builder_live/indicator_builder.ex
- [X] T035 [US2] Include example usage syntax in configured indicator tooltips showing indicator instance name in lib/trading_strategy_web/live/strategy_builder_live/indicator_builder.ex

### Integration Tests for User Story 2

- [X] T036 [P] [US2] Integration test for tooltip display on configured indicator info icon in test/trading_strategy_web/live/strategy_builder_live/indicator_builder_test.exs
- [X] T037 [P] [US2] Integration test for multiple indicators with independent tooltips in test/trading_strategy_web/live/strategy_builder_live/indicator_builder_test.exs
- [X] T038 [P] [US2] Integration test for example usage syntax with actual indicator parameters in test/trading_strategy_web/live/strategy_builder_live/indicator_builder_test.exs
- [X] T039 [P] [US2] Integration test for tooltip positioning in configured list (left position preferred) in test/trading_strategy_web/live/strategy_builder_live/indicator_builder_test.exs

**Checkpoint**: At this point, User Stories 1 AND 2 should both work independently - users can view metadata both when adding indicators and in the configured list

---

## Phase 5: Polish & Cross-Cutting Concerns

**Purpose**: Improvements that affect multiple user stories and validation

### Performance Validation

- [X] T040 [P] Create performance benchmark test for metadata retrieval latency (<200ms target) in test/trading_strategy/strategy_editor/indicator_metadata_benchmark_test.exs
- [X] T041 [P] Create performance benchmark test for caching effectiveness (<1ms cache hit) in test/trading_strategy/strategy_editor/indicator_metadata_benchmark_test.exs
- [X] T042 [P] Verify tooltip display latency meets SC-007 requirement (<200ms) in test/trading_strategy_web/live/strategy_builder_live/indicator_builder_performance_test.exs

### Code Quality & Documentation

- [X] T043 [P] Add module documentation (@moduledoc) with usage examples to IndicatorMetadata in lib/trading_strategy/strategy_editor/indicator_metadata.ex
- [X] T044 [P] Add function documentation (@doc) for all public functions in lib/trading_strategy/strategy_editor/indicator_metadata.ex
- [X] T045 [P] Add type specifications (@spec) for all functions in lib/trading_strategy/strategy_editor/indicator_metadata.ex
- [X] T046 [P] Add code comments explaining persistent_term caching strategy in lib/trading_strategy/strategy_editor/indicator_metadata.ex
- [X] T047 [P] Verify tooltip component documentation in core_components.ex matches implementation in lib/trading_strategy_web/components/core_components.ex
- [X] T048 [P] Add JSDoc comments to TooltipHook explaining keyboard behavior in assets/js/hooks/tooltip_hook.js

### Error Handling & Logging

- [X] T049 [P] Add Logger.warning for missing metadata functions in lib/trading_strategy/strategy_editor/indicator_metadata.ex
- [X] T050 [P] Add Logger.error for invalid metadata structures in lib/trading_strategy/strategy_editor/indicator_metadata.ex
- [X] T051 Verify graceful degradation when JavaScript hook fails (CSS-only fallback)

### Validation & Cleanup

- [X] T052 Run all unit tests and verify 100% pass rate with mix test test/trading_strategy/strategy_editor/
- [X] T053 Run all integration tests and verify 100% pass rate with mix test test/trading_strategy_web/
- [X] T054 Run performance benchmarks and verify all targets met
- [ ] T055 Manually test User Story 1 scenarios from spec.md acceptance criteria
- [ ] T056 Manually test User Story 2 scenarios from spec.md acceptance criteria
- [ ] T057 Verify keyboard accessibility (Tab, Enter, Escape) across all tooltips
- [ ] T058 Verify ARIA attributes are correct using browser DevTools accessibility inspector
- [ ] T059 Run quickstart.md validation (follow developer guide end-to-end)
- [X] T060 Code cleanup: Remove unused imports and dead code
- [X] T061 [P] Update CLAUDE.md with new patterns and components added by this feature in /Users/castilho/code/github.com/rzcastilho/trading-strategy/CLAUDE.md

---

## Dependencies & Execution Order

### Phase Dependencies

- **Setup (Phase 1)**: No dependencies - can start immediately (verification only)
- **Foundational (Phase 2)**: Depends on Setup completion - BLOCKS all user stories
- **User Stories (Phase 3-4)**: All depend on Foundational phase completion
  - User Story 1 (P1) can proceed after Phase 2
  - User Story 2 (P2) can proceed after Phase 2 (independent of US1)
- **Polish (Phase 5)**: Depends on User Stories 1 and 2 being complete

### User Story Dependencies

- **User Story 1 (P1)**: Can start after Foundational (Phase 2) - No dependencies on other stories
- **User Story 2 (P2)**: Can start after Foundational (Phase 2) - Independent of US1 but may share code patterns
- **User Story 3 (P3)**: DEFERRED - Not implemented in this iteration per plan.md

### Within Each User Story

- Tests MUST be written and FAIL before implementation
- IndicatorMetadata module must be complete before LiveComponent modifications
- Tooltip component must be complete before use in LiveComponents
- Core implementation before integration tests
- Story complete before moving to next priority

### Parallel Opportunities

#### Phase 1: Setup
- T002 and T003 can run in parallel (different files)

#### Phase 2: Foundational
- T004-T009 (IndicatorMetadata module) must run sequentially (same file)
- T010 (tooltip component), T011 (TooltipHook), T012 (registration) can run in parallel with each other
- T010-T012 can run in parallel with T004-T009 (different files)

#### Phase 3: User Story 1 Tests
- T013-T018 can all run in parallel (same test file but independent test cases)

#### Phase 3: User Story 1 Implementation
- T019-T024 must run sequentially (same file, dependent changes)

#### Phase 3: User Story 1 Integration Tests
- T025-T029 can all run in parallel (same test file but independent test cases)

#### Phase 4: User Story 2 Implementation
- T030-T035 likely sequential (same file), but T030 is discovery task

#### Phase 4: User Story 2 Integration Tests
- T036-T039 can all run in parallel (independent test cases)

#### Phase 5: Polish
- T040-T042 (performance) can run in parallel
- T043-T048 (documentation) can run in parallel
- T049-T051 (logging) can run in parallel
- T052-T061 (validation) mostly sequential (verification steps)

---

## Parallel Example: User Story 1 Tests

```bash
# Launch all unit tests for User Story 1 together:
Task: "Unit test for format_help/1 with single-value indicator (SMA)"
Task: "Unit test for format_help/1 with multi-value indicator (Bollinger Bands)"
Task: "Unit test for error handling when indicator not found"
Task: "Unit test for error handling when metadata function missing"
Task: "Unit test for caching behavior (cache hit vs cache miss)"
Task: "Unit test for fallback content generation"

# Launch all integration tests for User Story 1 together:
Task: "Integration test for tooltip display on indicator selection"
Task: "Integration test for keyboard navigation (Tab, Enter, Escape)"
Task: "Integration test for metadata content verification"
Task: "Integration test for single-value vs multi-value distinction"
Task: "Integration test for fallback behavior when metadata unavailable"
```

## Parallel Example: Phase 2 Foundation

```bash
# Core infrastructure tasks can run in parallel across different files:
Task: "Create IndicatorMetadata helper module" (lib/trading_strategy/strategy_editor/)
Task: "Create tooltip component" (lib/trading_strategy_web/components/)
Task: "Create TooltipHook JavaScript" (assets/js/hooks/)
```

---

## Implementation Strategy

### MVP First (User Story 1 Only)

1. Complete Phase 1: Setup (verification)
2. Complete Phase 2: Foundational (CRITICAL - blocks all stories)
3. Complete Phase 3: User Story 1 (tests → implementation → integration tests)
4. **STOP and VALIDATE**: Test User Story 1 independently with manual scenarios
5. Deploy/demo if ready - Users can now view metadata when adding indicators

### Incremental Delivery

1. Complete Setup + Foundational → Foundation ready
2. Add User Story 1 → Test independently → Deploy/Demo (MVP!)
   - **Value**: Users can make informed decisions when selecting indicators
3. Add User Story 2 → Test independently → Deploy/Demo
   - **Value**: Users can reference metadata for configured indicators when building conditions
4. Add Phase 5 Polish → Final quality checks → Deploy/Demo
   - **Value**: Performance validated, documentation complete, production-ready

### Parallel Team Strategy

With multiple developers:

1. Team completes Setup + Foundational together (Phase 1-2)
2. Once Foundational is done:
   - Developer A: User Story 1 tests and implementation (T013-T029)
   - Developer B: User Story 2 tests and implementation (T030-T039)
   - Developer C: Documentation and performance tests (T040-T048)
3. Stories complete and integrate independently
4. Team validates together (T052-T061)

---

## Notes

- [P] tasks = different files/independent, no dependencies
- [Story] label maps task to specific user story for traceability
- Each user story should be independently completable and testable
- Verify tests fail before implementing (TDD approach)
- Commit after each task or logical group
- Stop at any checkpoint to validate story independently
- **User Story 3 (P3)** is explicitly deferred per plan.md - not included in this iteration
- All file paths are absolute within the Phoenix/Elixir project structure
- Performance target: <200ms for metadata display (SC-007)
- Accessibility requirement: Keyboard navigation (FR-011) with ARIA compliance
- Caching strategy: Lazy persistent_term (0.0006ms retrieval per research.md)
