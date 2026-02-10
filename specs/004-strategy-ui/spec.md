# Feature Specification: Strategy Registration and Validation UI

**Feature Branch**: `004-strategy-ui`
**Created**: 2026-02-08
**Status**: Draft
**Input**: User description: "Create a UI to register and validate strategies"

## Clarifications

### Session 2026-02-08

- Q: How should the system handle attempts to register a strategy with a duplicate name? → A: Prevent submission with inline validation error showing the duplicate name conflict before user submits
- Q: How should the system handle concurrent edits to the same strategy in multiple browser tabs? → A: Last-write-wins with version conflict detection - warn user if strategy was modified elsewhere since they opened it
- Q: Can users view or edit other users' strategies, or are strategies private to each user? → A: Private - each user can only view and edit their own strategies
- Q: How long should strategy version history be retained? → A: Retain all versions indefinitely for complete audit trail and historical analysis
- Q: What should happen when a user attempts to edit or delete a strategy that is currently active? → A: Display error message indicating strategy is active and must be stopped before editing/deleting

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Register New Trading Strategy (Priority: P1)

As a trader, I want to register a new trading strategy through a web interface so that I can test my strategy ideas without writing code directly.

**Why this priority**: This is the core functionality of the feature - without strategy registration, users cannot create or manage their strategies. This delivers immediate value by allowing users to define their first strategy.

**Independent Test**: Can be fully tested by accessing the UI, filling out a strategy form with valid parameters, and submitting. The strategy should be saved and visible in the system. Delivers value by enabling users to create their first working strategy.

**Acceptance Scenarios**:

1. **Given** I am on the strategy registration page, **When** I fill in the strategy name "Moving Average Crossover", select indicators, and define entry/exit conditions, **Then** the strategy is saved and I receive confirmation
2. **Given** I am registering a strategy, **When** I provide all required fields (name, timeframe, indicators, entry rules, exit rules), **Then** the system accepts the strategy and generates a unique identifier
3. **Given** I have successfully registered a strategy, **When** I navigate to the strategy list, **Then** I can see my newly created strategy with its basic details

---

### User Story 2 - Validate Strategy Configuration (Priority: P1)

As a trader, I want the system to validate my strategy configuration in real-time so that I can catch errors before running backtests or live trading.

**Why this priority**: Validation prevents users from creating invalid strategies that would fail during execution. This is P1 because it protects data integrity and saves users time by catching errors early.

**Independent Test**: Can be tested by attempting to register strategies with various invalid configurations (missing fields, invalid parameter ranges, incompatible indicator combinations). The system should display appropriate error messages and prevent submission.

**Acceptance Scenarios**:

1. **Given** I am filling out the strategy form, **When** I leave required fields empty, **Then** the system highlights missing fields and prevents submission
2. **Given** I am defining entry conditions, **When** I select incompatible indicators or invalid parameter values, **Then** the system displays specific validation errors explaining the issue
3. **Given** I am setting position sizing rules, **When** I enter a percentage greater than 100%, **Then** the system shows an error message and suggests valid ranges
4. **Given** I have entered valid strategy configuration, **When** the validation runs, **Then** the system shows green checkmarks or success indicators next to validated sections

---

### User Story 3 - View and Edit Existing Strategies (Priority: P2)

As a trader, I want to view all my registered strategies and edit them so that I can refine my trading rules over time.

**Why this priority**: This enables iterative improvement of strategies. It's P2 because users first need to create strategies (P1) before they can edit them, but it's essential for ongoing strategy development.

**Independent Test**: Can be tested by creating several strategies, viewing the list, selecting one for editing, making changes, and verifying the updates are saved. Delivers value by enabling continuous improvement of existing strategies.

**Acceptance Scenarios**:

1. **Given** I have multiple registered strategies, **When** I access the strategy management page, **Then** I see a list of all my strategies with key details (name, status, creation date)
2. **Given** I am viewing my strategy list, **When** I click on a strategy, **Then** the strategy details page opens showing all configuration parameters
3. **Given** I am viewing a strategy, **When** I click the edit button, **Then** the registration form pre-populates with current values and allows modifications
4. **Given** I have edited a strategy, **When** I save the changes, **Then** the system validates the new configuration and updates the strategy if valid

---

### User Story 4 - Test Strategy Syntax (Priority: P2)

As a trader, I want to test my strategy's syntax and structure before saving so that I can verify the strategy logic is correct.

**Why this priority**: This provides immediate feedback on strategy correctness without requiring a full backtest. It's P2 because basic validation (P1) catches structural errors, but syntax testing verifies logical correctness.

**Independent Test**: Can be tested by using the syntax test feature with various strategy configurations, including both valid and invalid logic. The system should provide detailed feedback on syntax correctness and logical consistency.

**Acceptance Scenarios**:

1. **Given** I am creating a strategy, **When** I click the "Test Syntax" button, **Then** the system analyzes the strategy structure and reports any syntax errors or warnings
2. **Given** my strategy has logical inconsistencies (e.g., buy and sell conditions that can never both be true), **When** I run syntax testing, **Then** the system warns me about potential issues
3. **Given** my strategy syntax is correct, **When** I run the test, **Then** the system displays a success message with a summary of the parsed rules

---

### User Story 5 - Duplicate and Clone Strategies (Priority: P3)

As a trader, I want to duplicate existing strategies so that I can create variations without starting from scratch.

**Why this priority**: This is a productivity enhancement that accelerates strategy development. It's P3 because users can still create variations manually by creating new strategies, but cloning saves time.

**Independent Test**: Can be tested by selecting an existing strategy, clicking duplicate, modifying the clone, and verifying both the original and clone exist independently.

**Acceptance Scenarios**:

1. **Given** I have an existing strategy, **When** I select the "Duplicate" option, **Then** the system creates a copy with a new name (e.g., "Original Name - Copy")
2. **Given** I have duplicated a strategy, **When** I edit the duplicate, **Then** changes do not affect the original strategy
3. **Given** I want to create a strategy variation, **When** I duplicate and modify key parameters, **Then** I can quickly test different configurations of the same core strategy

---

### Edge Cases

- When a user tries to register a strategy with a duplicate name, the system prevents submission by showing an inline validation error during name entry, before form submission
- How does the system handle strategies with circular dependencies in indicator calculations?
- When a user tries to edit or delete a strategy that is currently active in backtesting or live trading, the system displays a clear error message indicating the strategy is in use and must be stopped before modifications can be made
- How does the system handle very large strategies with dozens of indicators and conditions?
- What happens if a user navigates away from the registration form with unsaved changes?
- When concurrent edits occur to the same strategy in multiple browser tabs, the system uses last-write-wins with version conflict detection, warning the user if the strategy was modified elsewhere since they opened it for editing
- What happens when validation rules change after a strategy has been registered (backward compatibility)?

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: System MUST provide a web-based interface for registering new trading strategies
- **FR-002**: System MUST allow users to specify strategy name, description, and timeframe (e.g., 1m, 5m, 1h, 1d)
- **FR-003**: System MUST support selection of technical indicators from a predefined list with configurable parameters
- **FR-004**: System MUST allow users to define entry conditions using a combination of indicator values, price levels, and logical operators
- **FR-005**: System MUST allow users to define exit conditions including take-profit, stop-loss, and trailing stop rules
- **FR-006**: System MUST validate strategy configuration in real-time as users fill out the form
- **FR-007**: System MUST display clear, actionable error messages for validation failures, indicating which fields need correction
- **FR-008**: System MUST prevent submission of strategies with missing required fields or invalid parameter values
- **FR-009**: System MUST verify that indicator parameters are within valid ranges (e.g., RSI period must be positive integer)
- **FR-010**: System MUST check for logical consistency in entry/exit conditions (e.g., stop-loss should be below entry price for long positions)
- **FR-011**: System MUST provide a list view of all registered strategies showing name, status, creation date, and last modified date
- **FR-012**: System MUST allow users to view detailed configuration of any registered strategy
- **FR-013**: System MUST enable editing of existing strategies with full validation
- **FR-014**: System MUST preserve strategy history by creating new versions when strategies are edited, retaining all versions indefinitely to maintain a complete audit trail
- **FR-014a**: System MUST detect version conflicts when saving a strategy that was modified by another session since it was opened for editing, and warn the user before allowing them to overwrite or merge changes
- **FR-015**: System MUST provide a syntax testing feature that validates strategy logic without executing trades
- **FR-016**: System MUST display syntax test results with specific feedback on errors or warnings
- **FR-017**: System MUST support duplicating existing strategies to create variations
- **FR-018**: System MUST enforce unique strategy names per user with inline validation that checks name uniqueness during entry and displays an error before form submission if a duplicate is detected
- **FR-018a**: System MUST restrict strategy access so that each user can only view, edit, and manage their own strategies, preventing access to other users' strategies
- **FR-019**: System MUST persist all strategy data so it remains available across sessions
- **FR-020**: System MUST prevent editing or deletion of strategies that are currently active in backtesting or live trading by displaying a clear error message that indicates the strategy is in use and must be stopped first
- **FR-021**: Users MUST be able to save partially completed strategies as drafts for later completion
- **FR-022**: System MUST provide tooltips or help text explaining technical terms and parameter meanings
- **FR-023**: System MUST support position sizing rules (fixed amount, percentage of portfolio, risk-based)
- **FR-024**: System MUST allow users to specify risk management parameters (max position size, max daily loss, max concurrent positions)

### Key Entities

- **Strategy**: Represents a complete trading strategy definition including name, description, timeframe, indicator configurations, entry/exit rules, position sizing rules, and risk parameters. Each strategy has a unique identifier, creation timestamp, last modified timestamp, version number, and status (draft, active, inactive).
- **Indicator Configuration**: Represents a technical indicator instance with its specific parameters (e.g., SMA with period=20, RSI with period=14). Multiple indicator configurations can be associated with a single strategy.
- **Entry Condition**: Defines the rules that must be met to open a position. Can consist of multiple indicator comparisons combined with logical operators (AND, OR). Linked to a specific strategy.
- **Exit Condition**: Defines the rules for closing positions including take-profit levels, stop-loss levels, trailing stops, and indicator-based exit signals. Linked to a specific strategy.
- **Strategy Version**: Represents a historical snapshot of a strategy's configuration at a specific point in time. All versions are retained indefinitely to provide a complete audit trail for compliance, analysis, and rollback capability.
- **Validation Result**: Captures the outcome of strategy validation including error messages, warnings, and success indicators. Associated with a validation attempt on a specific strategy configuration.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: Users can complete registration of a simple strategy (name, 1-2 indicators, basic entry/exit conditions) in under 5 minutes
- **SC-002**: Validation errors appear within 1 second of user input to provide immediate feedback
- **SC-003**: 95% of validation errors provide specific, actionable guidance that users can understand without technical expertise
- **SC-004**: Users can view a list of 100+ registered strategies with initial page load time under 2 seconds
- **SC-005**: Strategy syntax testing completes within 3 seconds for strategies with up to 10 indicators
- **SC-006**: Zero data loss when users navigate away from registration forms with autosave or warning prompts
- **SC-007**: System prevents 100% of invalid strategy configurations from being saved through validation
- **SC-008**: Users can successfully edit and save strategy modifications in under 3 minutes
- **SC-009**: Strategy duplication completes instantly (under 1 second) regardless of strategy complexity

## Assumptions

- Users have basic familiarity with trading concepts (indicators, entry/exit conditions, stop-loss, take-profit)
- The strategy DSL library (Feature 001) provides the underlying strategy definition and validation logic that this UI will interface with
- Users access the UI through modern web browsers (Chrome, Firefox, Safari, Edge - last 2 versions)
- The UI will integrate with the existing Phoenix LiveView application infrastructure mentioned in CLAUDE.md
- Strategy validation rules are defined by the backend/DSL library and exposed via API
- The system supports multi-user scenarios with basic user authentication already in place, where each user has isolated access to their own strategies
- Form autosave will occur every 30 seconds to prevent data loss
- The predefined list of technical indicators includes common ones (SMA, EMA, RSI, MACD, Bollinger Bands, etc.)
- Strategy execution (backtesting, live trading) is handled by separate features; this UI only handles registration and validation
