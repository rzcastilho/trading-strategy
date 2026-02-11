# Feature Specification: Bidirectional Strategy Editor Synchronization

**Feature Branch**: `005-builder-dsl-sync`
**Created**: 2026-02-10
**Status**: Draft
**Input**: User description: "In strategy UI, sync the editions in Advanced Strategy Builder with the manual dsl editor and vice and versa."

## Clarifications

### Session 2026-02-10

- Q: How should undo/redo functionality work when users switch between editors? → A: Single shared undo/redo stack - all changes (builder or DSL) go into one chronological stack. Undo reverts the last change regardless of which editor made it.
- Q: How should the system handle switching from builder to DSL when the builder contains incomplete or invalid data? → A: Allow the switch and generate DSL from current builder state (even if incomplete). DSL may have missing required fields marked with placeholders or comments.
- Q: Where should warnings about unsupported DSL features be displayed in the builder interface? → A: Persistent warning banner at the top of the builder listing unsupported features, with option to view full DSL or dismiss.
- Q: How should the system handle parser crashes or unexpected failures (not syntax errors)? → A: Preserve last valid state in builder, display error banner with retry option, and log failure details for debugging.
- Q: When should changes be automatically saved to the server during editing? → A: Only on explicit save action (no autosave) - users must manually save their work.

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Builder Changes Sync to DSL Editor (Priority: P1)

As a trader, I want my changes in the Advanced Strategy Builder to automatically appear in the manual DSL editor so that I can see the DSL code generated from my form inputs and learn the DSL syntax.

**Why this priority**: This is the most critical flow because the majority of users will start with the visual builder (easier for beginners) and need to see the corresponding DSL code. This delivers immediate value by making the DSL transparent and educational.

**Independent Test**: Can be fully tested by opening a strategy, making changes in the builder (e.g., adding an indicator, changing entry condition), and verifying the DSL editor updates automatically to reflect those changes. Delivers value by allowing visual-first users to understand and verify their strategy definitions.

**Acceptance Scenarios**:

1. **Given** I am editing a strategy in the Advanced Strategy Builder, **When** I add a new indicator (e.g., RSI with period 14), **Then** the DSL editor immediately shows the corresponding DSL code for that indicator
2. **Given** I have modified an entry condition in the builder, **When** I switch to view the DSL editor, **Then** the DSL code reflects the exact entry condition I configured
3. **Given** I am making multiple rapid changes in the builder, **When** I pause editing for 500ms, **Then** the DSL editor updates with all accumulated changes
4. **Given** the DSL editor is visible while I edit in the builder, **When** I change any parameter, **Then** the DSL editor highlights or scrolls to show the updated section

---

### User Story 2 - DSL Editor Changes Sync to Builder (Priority: P1)

As a power user, I want my manual DSL edits to automatically update the Advanced Strategy Builder so that I can work efficiently in my preferred text-based environment while still having a visual representation available.

**Why this priority**: This is equally critical because power users need the efficiency of text editing. Without this, they would be forced to use the slower builder interface. This is P1 because it enables a completely different user workflow.

**Independent Test**: Can be fully tested by typing valid DSL code in the manual editor and verifying the builder form updates to show the corresponding visual elements (indicators, conditions, parameters). Delivers value by enabling power users to work at full speed while maintaining visual feedback.

**Acceptance Scenarios**:

1. **Given** I am editing DSL code manually, **When** I add a valid indicator definition in DSL syntax, **Then** the builder immediately shows that indicator in the form with correct parameters
2. **Given** I have typed a complete entry condition in DSL, **When** the DSL is valid and I pause typing for 500ms, **Then** the builder updates to show the entry condition visually
3. **Given** I delete an indicator from the DSL, **When** the change is synchronized, **Then** the indicator is removed from the builder form
4. **Given** I modify a parameter value in DSL (e.g., change RSI period from 14 to 21), **When** synchronization occurs, **Then** the builder form shows the updated value

---

### User Story 3 - Validation and Error Handling (Priority: P2)

As a user, I want clear feedback when my DSL code has syntax errors so that I can fix issues without breaking the builder interface or losing my work.

**Why this priority**: This prevents data corruption and provides a safety net. It's P2 because basic synchronization (P1) must work first, but error handling is essential to make the feature robust and user-friendly.

**Independent Test**: Can be tested by intentionally introducing DSL syntax errors and verifying that: (1) errors are detected and displayed clearly, (2) the builder doesn't break or show invalid state, (3) users can fix errors and resume synchronization.

**Acceptance Scenarios**:

1. **Given** I am typing DSL code, **When** I introduce a syntax error (e.g., missing closing bracket), **Then** the editor shows an inline error message indicating the specific syntax issue
2. **Given** the DSL contains a syntax error, **When** synchronization is attempted, **Then** the builder maintains its last valid state and displays a warning that DSL has errors
3. **Given** I have fixed a DSL syntax error, **When** the DSL becomes valid again, **Then** synchronization to the builder resumes automatically
4. **Given** the DSL contains features not yet supported by the builder, **When** synchronization occurs, **Then** the system displays a message listing unsupported features but still syncs supported elements

---

### User Story 4 - Concurrent Edit Prevention (Priority: P3)

As a user, I want the system to prevent conflicts when I might try to edit both the builder and DSL editor simultaneously so that my changes don't conflict or get lost.

**Why this priority**: This is a defensive feature to handle edge cases. It's P3 because in practice, users work in one interface at a time, but having clear handling of simultaneous edits improves robustness.

**Independent Test**: Can be tested by attempting to edit both interfaces in rapid succession or simultaneously (if possible) and verifying the system handles it gracefully with clear feedback about which change was applied.

**Acceptance Scenarios**:

1. **Given** I am actively editing in the builder, **When** I switch to the DSL editor and start typing, **Then** the system indicates which editor is currently the "source of truth"
2. **Given** both editors have pending unsynchronized changes, **When** I save the strategy, **Then** the system uses the last-modified editor as the authoritative source
3. **Given** synchronization is in progress, **When** I start editing in the opposite editor, **Then** the system completes the current sync before processing new changes

---

### Edge Cases

- What happens when DSL contains syntax errors that prevent parsing? (Answered: FR-003, FR-004, FR-005 - builder maintains last valid state, shows inline errors)
- How does the system handle DSL features that cannot be represented in the builder (advanced logic, custom functions)? (Answered: FR-009 - shows persistent warning banner at top of builder listing unsupported features)
- What happens during very rapid consecutive edits (e.g., user types quickly in DSL)? (Answered: FR-008 - debouncing with 300ms delay)
- How does the system indicate which editor was last modified? (Answered: FR-007 - system indicates last modified editor)
- What happens if the builder is in an invalid state (e.g., required field empty) when user switches to DSL? (Answered: FR-019 - allows switch, generates DSL with placeholders for missing fields)
- How does undo/redo work across both editors? (Answered: FR-012 - single shared chronological stack for all changes)
- What happens when synchronization takes longer than expected (>1 second)? (Answered: FR-011 - shows loading indicator after 200ms)
- How are comments in DSL code handled (are they preserved during builder edits)? (Answered: FR-010, SC-009 - comments are preserved)
- What happens if the DSL parser crashes or throws unexpected exceptions? (Answered: FR-005a - preserves last valid state, shows error banner with retry, logs details)

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: System MUST synchronize changes from Advanced Strategy Builder to DSL editor within 500ms of user pausing input
- **FR-002**: System MUST synchronize changes from DSL editor to Advanced Strategy Builder within 500ms of user pausing input
- **FR-003**: System MUST validate DSL syntax before attempting to sync DSL changes to the builder
- **FR-004**: System MUST display clear, inline error messages when DSL contains syntax errors
- **FR-005**: System MUST preserve the last valid builder state when DSL contains errors, preventing the builder from showing invalid or broken UI
- **FR-005a**: System MUST handle DSL parser failures (crashes, timeouts, or unexpected exceptions) by preserving the last valid builder state, displaying an error banner with a retry option, and logging failure details for debugging
- **FR-006**: System MUST preserve all strategy data during synchronization without data loss
- **FR-007**: System MUST indicate which editor (builder or DSL) was last modified
- **FR-008**: System MUST use debouncing to avoid synchronizing on every keystroke (minimum 300ms delay after user stops typing)
- **FR-009**: System MUST handle DSL features not supported by the builder by syncing supported elements and displaying a persistent warning banner at the top of the builder that lists unsupported features, with options to view the full DSL or dismiss the warning
- **FR-010**: System MUST maintain DSL comments when changes are made in the builder
- **FR-011**: System MUST provide visual feedback during synchronization (e.g., loading indicator) if sync takes longer than 200ms
- **FR-012**: System MUST support undo/redo operations using a single shared chronological stack where all changes (from both builder and DSL editor) are tracked in order, allowing users to undo the last change regardless of which editor made it
- **FR-013**: System MUST detect when both editors have pending changes and use the last-modified timestamp to determine authoritative source
- **FR-014**: System MUST highlight or scroll to changed sections in the target editor after synchronization
- **FR-015**: System MUST validate DSL syntax incrementally as user types, showing errors in real-time
- **FR-016**: System MUST generate clean, properly formatted DSL code when synchronizing from builder to DSL
- **FR-017**: System MUST preserve DSL formatting preferences (indentation, line breaks) when synchronizing from DSL to builder and back
- **FR-018**: System MUST prevent data loss if user navigates away during unsaved changes in either editor by prompting the user to save before leaving
- **FR-020**: System MUST persist strategy changes to the server only when the user explicitly triggers a save action (no automatic background saving)
- **FR-019**: System MUST allow users to switch from builder to DSL editor even when builder contains incomplete or invalid data, generating DSL that represents the current state with placeholders or comments for missing required fields

### Key Entities

- **Strategy Definition**: The core data model representing a trading strategy that can be expressed in both builder form and DSL text format
- **DSL Representation**: The text-based representation of a strategy using the DSL syntax defined in Feature 001
- **Builder State**: The visual form representation of a strategy including all form fields, indicators, conditions, and parameters
- **Synchronization Event**: Represents a sync operation triggered by user edits in either editor, including source editor, timestamp, and change delta
- **Validation Result**: The outcome of DSL syntax validation including error messages, line numbers, and suggestions for fixes
- **Edit History**: Single shared chronological undo/redo stack that tracks all changes from both editors in the order they occurred, enabling consistent undo/redo behavior regardless of which editor is active

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: Changes in either editor reflect in the other editor within 500ms of user pausing input
- **SC-002**: 99% of valid DSL changes successfully synchronize to the builder without errors
- **SC-003**: Users can switch between builder and DSL editor without losing any work or data
- **SC-004**: Syntax errors are detected and displayed within 1 second of user input with specific line and column numbers
- **SC-005**: System handles strategies with up to 20 indicators and 10 entry/exit conditions without synchronization delays exceeding 500ms
- **SC-006**: Zero data loss during synchronization across 1000+ test scenarios
- **SC-007**: Users can complete a full edit workflow (make changes in builder, verify in DSL, make DSL tweaks, see builder update) in under 2 minutes
- **SC-008**: 95% of DSL syntax errors provide actionable error messages that help users fix the issue
- **SC-009**: Comments in DSL are preserved through 100+ round-trip synchronizations (builder → DSL → builder)

## Assumptions

- The DSL syntax and parser are already implemented in Feature 001 (strategy-dsl-library)
- The Advanced Strategy Builder UI exists from Feature 004 (strategy-ui)
- Both editors exist on the same page/view (no separate pages requiring navigation)
- Synchronization happens client-side for low latency, with server-side validation as backup
- DSL parser can provide detailed error information (line numbers, error types, suggestions)
- The builder can represent all common DSL features; advanced features are documented as "DSL-only"
- User sessions are single-user (no multi-user concurrent editing of same strategy)
- Modern browsers support the performance requirements for real-time synchronization
- Debouncing delay of 300ms is acceptable for user experience (industry standard for text editors)
- "Last write wins" is the conflict resolution strategy when both editors have pending changes
- DSL comments are stored separately or preserved in the underlying data model
- Strategy persistence uses explicit save actions only (differs from Feature 004's autosave approach, providing users with full control over when changes are committed)
