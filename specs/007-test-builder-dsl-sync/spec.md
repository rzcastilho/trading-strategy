# Feature Specification: Comprehensive Testing for Strategy Editor Synchronization

**Feature Branch**: `007-test-builder-dsl-sync`
**Created**: 2026-02-11
**Status**: Draft
**Input**: User description: "Let's test the strategy editor feature that sync advanced strategy builder with manual DSL"

## Clarifications

### Session 2026-02-11

- Q: Which edge case categories should be actively tested in this feature? → A: Test critical edge cases only - browser refresh warning, rapid changes, large strategies (up to 50 indicators) - defer network and multi-user scenarios
- Q: How should test results be reported and delivered to stakeholders? → A: Console output only - Test results printed to terminal with summary statistics
- Q: How should the 50+ test scenarios be organized? → A: By user story priority - Organize tests matching the 6 user stories (P1 sync, P2 comment/undo, P3 performance/error)
- Q: How should test data (sample strategies) be managed? → A: Version-controlled fixtures - Strategy definitions as code fixtures in test repo (e.g., `simple_sma_strategy.exs`)
- Q: Should flaky tests be automatically retried? → A: No retries - fail fast - Tests must be deterministic, no automatic retries, forces proper test design

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Builder-to-DSL Synchronization Verification (Priority: P1)

A QA engineer or developer modifies strategy parameters in the visual builder (adding/removing indicators, changing entry/exit rules) and needs to verify that the DSL editor immediately reflects these changes with correct syntax and preserved structure.

**Why this priority**: Core functionality of the bidirectional sync feature. Without reliable builder-to-DSL sync, users cannot trust the visual builder as an alternative to manual DSL editing.

**Independent Test**: Can be fully tested by making a single change in the builder (e.g., adding a new indicator) and verifying the DSL updates within performance targets (<500ms) with correct syntax.

**Acceptance Scenarios**:

1. **Given** a strategy with 5 indicators in the builder, **When** I add a new SMA indicator with period 20, **Then** the DSL editor updates within 500ms showing the new indicator configuration with correct syntax
2. **Given** a strategy with entry rules in the builder, **When** I modify the entry condition from "crossover" to "crossunder", **Then** the DSL reflects the change immediately and the syntax remains valid
3. **Given** a complex strategy with 15 indicators, **When** I remove 3 indicators from the builder, **Then** the DSL updates within 500ms and removed indicators are no longer present
4. **Given** a strategy in the builder, **When** I change position sizing from "fixed" to "percentage", **Then** the DSL shows the updated position sizing configuration

---

### User Story 2 - DSL-to-Builder Synchronization Verification (Priority: P1)

A QA engineer or developer manually edits the DSL code (adding indicators, modifying parameters) and needs to verify that the visual builder immediately reflects these changes with correct UI state.

**Why this priority**: Equal priority to Story 1 as bidirectional sync is the core feature. Advanced users prefer DSL editing, so DSL-to-builder sync is equally critical.

**Independent Test**: Can be fully tested by making a single DSL change (e.g., adding a new indicator in code) and verifying the builder updates within performance targets with correct form values.

**Acceptance Scenarios**:

1. **Given** a valid strategy DSL, **When** I add a new indicator via DSL code, **Then** the builder form updates within 500ms showing the new indicator in the indicators list
2. **Given** a strategy DSL with an SMA indicator period of 50, **When** I change it to 100 in the DSL, **Then** the builder form immediately shows period=100 in the indicator configuration
3. **Given** a DSL with entry/exit rules, **When** I modify the entry condition logic, **Then** the builder reflects the change in the entry rules form section
4. **Given** an empty strategy DSL, **When** I paste a complete valid strategy, **Then** the builder populates all forms with correct values within 500ms

---

### User Story 3 - Comment Preservation During Synchronization (Priority: P2)

A developer adds code comments in the DSL editor to document strategy logic and needs to verify that these comments survive multiple round-trip synchronizations (DSL → builder → DSL → builder → ...).

**Why this priority**: Comments are critical for strategy documentation and maintenance. Loss of comments would severely impact usability for professional users.

**Independent Test**: Can be fully tested by adding comments to DSL, making changes in builder, and verifying comments persist after each synchronization cycle.

**Acceptance Scenarios**:

1. **Given** a strategy DSL with inline comments above indicator configurations, **When** I add a new indicator via the builder, **Then** the original comments remain in the DSL after synchronization
2. **Given** a strategy with comments documenting entry logic, **When** I modify entry conditions in the builder, **Then** the comments are preserved at 90%+ retention rate
3. **Given** a DSL with 20 comment lines, **When** I perform 10 round-trip edits (5 builder changes, 5 DSL changes), **Then** at least 18 comment lines (90%) remain intact
4. **Given** a strategy with multi-line comment blocks, **When** I remove an indicator via builder, **Then** comment blocks not associated with the removed indicator are preserved

---

### User Story 4 - Undo/Redo Functionality Across Editors (Priority: P2)

A developer makes changes in both editors and needs to verify that undo/redo operations work correctly across both the builder and DSL editor with shared history.

**Why this priority**: Essential for user confidence and productivity. Without reliable undo/redo, users fear making experimental changes.

**Independent Test**: Can be fully tested by making changes in both editors, performing undo/redo operations, and verifying state consistency within <50ms response time.

**Acceptance Scenarios**:

1. **Given** a strategy with 3 indicators, **When** I add an indicator via builder, then undo, **Then** the strategy returns to 3 indicators in both builder and DSL within 50ms
2. **Given** a strategy, **When** I make 5 changes (3 in builder, 2 in DSL), then undo all 5, **Then** both editors return to original state
3. **Given** an undo stack with 10 operations, **When** I undo 5 times then redo 3 times, **Then** both editors show the correct state corresponding to the undo/redo position
4. **Given** a strategy, **When** I make a change in builder, undo it, then make a new change in DSL, **Then** redo stack is cleared and the new change appears in both editors

---

### User Story 5 - Performance Validation Under Load (Priority: P3)

A QA engineer tests the synchronization feature with large, complex strategies (20+ indicators) to verify that performance targets are met under realistic load conditions.

**Why this priority**: Performance targets are defined in the original feature spec (SC-001: <500ms sync, SC-005: 20 indicators without delay). Validation is necessary but can be tested after core functionality is verified.

**Independent Test**: Can be fully tested by creating a strategy with 20 indicators and measuring synchronization latency across multiple operations.

**Acceptance Scenarios**:

1. **Given** a strategy with 20 configured indicators, **When** I add the 21st indicator via builder, **Then** DSL synchronization completes within 500ms
2. **Given** a strategy with 20 indicators in DSL, **When** I modify indicator parameters, **Then** builder synchronization completes within 500ms
3. **Given** a strategy with 15 indicators and complex entry/exit rules, **When** I perform rapid changes (5 edits in 3 seconds), **Then** all synchronizations complete without errors and final state is consistent
4. **Given** a strategy with 20 indicators, **When** I perform undo/redo operations, **Then** each operation completes within 50ms

---

### User Story 6 - Error Handling and Validation (Priority: P3)

A developer introduces invalid DSL syntax or invalid builder configurations to verify that error handling provides clear feedback without breaking synchronization or causing data loss.

**Why this priority**: Robust error handling prevents user frustration and data loss, but is less critical than core synchronization functionality.

**Independent Test**: Can be fully tested by introducing specific syntax errors and verifying error messages appear without data loss.

**Acceptance Scenarios**:

1. **Given** a valid strategy DSL, **When** I introduce a syntax error (missing closing bracket), **Then** the DSL editor shows a clear error message (including line number, error type, code snippet, and fix suggestion) and builder does not update until syntax is fixed
2. **Given** a valid strategy in builder, **When** I manually edit DSL to create an invalid indicator reference, **Then** validation fails with specific error message identifying the invalid indicator (error message MUST include: line number, error type, invalid indicator name, and actionable fix suggestion)
3. **Given** a strategy with unsaved changes in DSL, **When** I introduce a syntax error, **Then** previous valid state is preserved in builder and can be recovered
4. **Given** rapid typing in DSL editor, **When** I pause typing after creating valid syntax, **Then** builder synchronizes after debounce period (300ms) with no errors

---

### Edge Cases

**In Scope - Critical Edge Cases to Test**:
- Browser refresh during active editing session must show unsaved changes warning
- Rapid switching between builder and DSL editors (multiple switches within seconds) must maintain synchronization consistency
- Very large strategies (up to 50 indicators, 1000+ lines of DSL) must meet performance targets (<500ms sync)
- Rapid changes (5+ edits within 3 seconds) must complete without errors and maintain final state consistency
- User making changes during active synchronization operation must either queue the change or show appropriate feedback

**Out of Scope - Deferred to Future Testing**:
- Network connectivity loss during synchronization (requires integration testing setup)
- Concurrent multi-user editing of the same strategy (requires multi-user infrastructure)
- Browser tab inactive for extended period then reactivated (low priority, not critical path)
- Undo/redo history exceeding configured limits (edge case of edge case, low probability)

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: Test suite MUST verify that builder changes synchronize to DSL within 500ms for strategies with up to 20 indicators
- **FR-002**: Test suite MUST verify that DSL changes synchronize to builder within 500ms for valid syntax
- **FR-003**: Test suite MUST verify that comments in DSL are preserved across at least 90% of synchronization round-trips
- **FR-004**: Test suite MUST verify that undo/redo operations complete within 50ms and maintain consistent state across both editors
- **FR-005**: Test suite MUST verify that invalid DSL syntax is detected and reported with specific error messages (error messages MUST include: line number, error type, code snippet showing the error, and actionable fix suggestion)
- **FR-006**: Test suite MUST verify that synchronization failures do not result in data loss (previous valid state is recoverable)
- **FR-007**: Test suite MUST verify that the debounce mechanism (300ms) prevents excessive synchronization events during rapid typing
- **FR-008**: Test suite MUST verify that visual feedback (changed line highlighting, scroll position) works correctly during synchronization
- **FR-009**: Test suite MUST verify that keyboard shortcuts (Ctrl+Z, Ctrl+Shift+Z, Ctrl+S) function correctly in both builder and DSL editors regardless of which editor currently has focus
- **FR-010**: Test suite MUST verify that unsaved changes warning appears when user attempts to navigate away from the page
- **FR-011**: Test suite MUST verify that synchronization maintains correct state for all strategy components (indicators, entry rules, exit rules, position sizing)
- **FR-012**: Test suite MUST verify performance benchmarks match the targets defined in feature 005 (SC-001, SC-005, SC-009)
- **FR-013**: Test suite MUST verify that browser refresh during active editing triggers an unsaved changes warning dialog
- **FR-014**: Test suite MUST verify that rapid switching between builder and DSL editors (5+ switches in 10 seconds) maintains synchronization consistency
- **FR-015**: Test suite MUST verify that large strategies (up to 50 indicators, 1000+ lines of DSL) meet performance targets (<500ms synchronization)
- **FR-016**: Test suite MUST verify that changes made during active synchronization are handled safely (IMPLEMENTATION NOTE: Verify whether Feature 005 uses queuing or user feedback approach before writing tests)
- **FR-017**: Test results MUST be output to console with summary statistics including total tests, pass/fail counts, performance metrics (mean/median/P95 latency), and list of failed tests with error details
- **FR-018**: Test scenarios MUST be organized by user story priority with clear mapping to the 6 user stories (US1: Builder-to-DSL sync, US2: DSL-to-Builder sync, US3: Comment preservation, US4: Undo/Redo, US5: Performance validation, US6: Error handling)
- **FR-019**: Test data MUST be managed as version-controlled code fixtures with descriptive names indicating complexity level (e.g., `simple_sma_strategy.exs`, `medium_5_indicators.exs`, `complex_20_indicators.exs`, `large_50_indicators.exs`)
- **FR-020**: Test suite MUST use a fail-fast strategy with no automatic retries, ensuring all tests are deterministic and properly designed with explicit waits and assertions

### Key Entities

- **Test Scenario**: Represents a specific test case with preconditions, actions, expected outcomes, and pass/fail criteria, organized by user story for traceability (e.g., US1.001, US1.002, US2.001, etc.)
- **Strategy Configuration**: The test data structure containing indicators, rules, and parameters used in test scenarios
- **Synchronization Event**: A measurable event representing data transfer between builder and DSL, including latency metrics
- **Performance Metric**: Measured values for synchronization latency, undo/redo response time, comment preservation rate, and error rates
- **Test Report**: Console-formatted aggregated results from all test scenarios including pass/fail status, performance metrics (mean/median/P95 latency), and identified issues with summary statistics

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: 100% of builder-to-DSL synchronization tests pass for strategies with up to 20 indicators
- **SC-002**: 100% of DSL-to-builder synchronization tests pass for valid syntax inputs
- **SC-003**: 95%+ of synchronization operations complete within 500ms target latency
- **SC-004**: 90%+ comment preservation rate verified across at least 100 round-trip synchronization cycles
- **SC-005**: 100% of undo/redo tests pass with <50ms response time
- **SC-006**: 0 data loss incidents during synchronization error scenarios
- **SC-007**: All visual feedback mechanisms (highlighting, scrolling, tooltips) function as specified in 100% of test cases
- **SC-008**: All keyboard shortcuts work correctly in 100% of test scenarios across both editors
- **SC-009**: Performance benchmarks match or exceed targets from feature 005 specification (synchronization <500ms, undo/redo <50ms)
- **SC-010**: Test coverage includes at least 50 distinct test scenarios covering happy paths, edge cases, and error conditions
- **SC-011**: All tests are deterministic with 0% flakiness rate when run multiple times (minimum 10 consecutive runs with identical results)

## Assumptions

- Feature 005 (bidirectional strategy editor) is fully implemented and deployed to a test environment
- Test environment has access to a PostgreSQL database with test data
- Test execution environment supports automated browser testing (Wallaby/Selenium)
- Performance testing can be conducted on a consistent hardware/network configuration
- All test scenarios assume single-user editing (no concurrent multi-user testing unless specified)
- Test data (sample strategies) is stored as version-controlled code fixtures in the test repository, ranging from simple (1-2 indicators) to complex (20+ indicators)
- DSL syntax validation rules are documented and accessible for test case creation
- Standard debounce period is 300ms as specified in feature 005 documentation

## Dependencies

- Feature 005 (bidirectional strategy editor) must be deployed and accessible
- Test database must be populated with sample strategy configurations
- Browser automation tools (Wallaby) must be configured and operational
- Performance monitoring tools must be available to measure synchronization latency
- Access to feature 005 specification documents for reference benchmarks (SC-001, SC-005, SC-009)

## Out of Scope

- Implementing new features or bug fixes for the strategy editor (testing only)
- Load testing with multiple concurrent users (single-user focus)
- Security testing or penetration testing
- Accessibility compliance testing (WCAG)
- Cross-browser compatibility testing (assume single target browser for initial testing)
- Mobile device testing (desktop browser focus)
- Integration testing with external systems (backtesting engine, live trading)
- Performance optimization of the synchronization feature itself
- Creating new test infrastructure or frameworks (use existing Wallaby/ExUnit setup)
- Network connectivity loss testing during synchronization (deferred to integration testing phase)
- Concurrent multi-user editing scenarios (requires multi-user test infrastructure)
- Browser tab inactivity and reactivation scenarios (low priority edge case)
- Undo/redo history limit overflow testing (low probability edge case)
