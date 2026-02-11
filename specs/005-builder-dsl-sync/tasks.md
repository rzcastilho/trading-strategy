---
description: "Implementation tasks for Feature 005: Bidirectional Strategy Editor Synchronization"
---

# Tasks: Bidirectional Strategy Editor Synchronization

**Feature**: 005-builder-dsl-sync
**Input**: Design documents from `/specs/005-builder-dsl-sync/`
**Prerequisites**: ✅ plan.md, ✅ spec.md, ✅ research.md, ✅ data-model.md, ✅ contracts/

**Organization**: Tasks are grouped by user story to enable independent implementation and testing of each story.

**Tests**: Included as part of standard practice (ExUnit unit tests + Wallaby integration tests per plan.md)

---

## Format: `[ID] [P?] [Story?] Description`

- **[P]**: Can run in parallel (different files, no dependencies)
- **[Story]**: Which user story this task belongs to (US1, US2, US3, US4)
- All tasks include exact file paths

---

## Phase 1: Setup (Shared Infrastructure)

**Purpose**: Project initialization and dependency installation

- [X] T001 Install Sourceror dependency for comment preservation in mix.exs
- [X] T002 [P] Install CodeMirror 6 and related packages in assets/package.json
- [X] T003 [P] Create strategy_editor directory structure in lib/trading_strategy/strategy_editor/
- [X] T004 Run mix deps.get and npm install to fetch dependencies

---

## Phase 2: Foundational (Blocking Prerequisites)

**Purpose**: Core infrastructure that MUST be complete before ANY user story can be implemented

**⚠️ CRITICAL**: No user story work can begin until this phase is complete

### Database & Schema

- [X] T005 Create database migration for strategy_definitions table with dsl_text, builder_state (JSONB), last_modified_editor, last_modified_at, validation_status (JSONB), comments (JSONB) in priv/repo/migrations/
- [X] T006 [P] Create database migration for edit_histories table with session_id, strategy_id, undo_stack (JSONB), redo_stack (JSONB) in priv/repo/migrations/
- [X] T007 Run mix ecto.migrate to apply database schema changes

### Core Data Structures

- [X] T008 [P] Implement StrategyDefinition schema module with Ecto changeset validation in lib/trading_strategy/strategy_editor/strategy_definition.ex
- [X] T009 [P] Implement BuilderState struct with type specifications in lib/trading_strategy/strategy_editor/builder_state.ex
- [X] T010 [P] Implement ChangeEvent struct for undo/redo tracking in lib/trading_strategy/strategy_editor/change_event.ex
- [X] T011 [P] Implement ValidationResult struct with error/warning types in lib/trading_strategy/strategy_editor/validation_result.ex

### Undo/Redo Infrastructure

- [X] T012 Implement EditHistory GenServer with ETS storage for undo/redo stacks in lib/trading_strategy/strategy_editor/edit_history.ex
- [X] T013 Add EditHistory to application supervision tree in lib/trading_strategy/application.ex
- [X] T014 Create ChangeApplier module to apply ChangeEvents to state in lib/trading_strategy/strategy_editor/change_applier.ex

### LiveView Foundation

- [X] T015 Update strategy edit LiveView to initialize session state (session_id, builder_state, dsl_text, last_modified_editor) in lib/trading_strategy_web/live/strategy_live/edit.ex
- [X] T016 Add undo/redo event handlers (handle_event "undo" and "redo") in lib/trading_strategy_web/live/strategy_live/edit.ex
- [X] T017 Add save_strategy event handler with explicit save (no autosave, FR-020) in lib/trading_strategy_web/live/strategy_live/edit.ex
- [X] T018 Update edit.html.heex template to add data attributes for hooks (phx-hook="DSLEditorHook" and phx-hook="BuilderFormHook") in lib/trading_strategy_web/live/strategy_live/edit.html.heex

### JavaScript Hook Registration

- [X] T019 Register LiveView hooks (DSLEditorHook, BuilderFormHook) in assets/js/app.js

### Configuration

- [X] T020 [P] Add strategy_editor configuration (debounce_delay: 300, sync_timeout: 500, max_undo_stack_size: 100) in config/dev.exs and config/test.exs

**Checkpoint**: Foundation ready - user story implementation can now begin in parallel

---

## Phase 3: User Story 1 - Builder Changes Sync to DSL Editor (Priority: P1) 🎯 MVP

**Goal**: Enable users to edit strategies in the Advanced Strategy Builder and see changes automatically reflected in the DSL editor, making the DSL transparent and educational.

**Independent Test**: Open a strategy, add an indicator (e.g., RSI with period 14) in the builder, verify DSL editor updates within 500ms to show corresponding DSL code.

### Tests for User Story 1

> **NOTE: Write these tests FIRST, ensure they FAIL before implementation**

- [X] T021 [P] [US1] Create unit test file for builder_to_dsl conversion in test/trading_strategy/strategy_editor/synchronizer_test.exs
- [X] T022 [P] [US1] Write test: builder_to_dsl converts simple strategy with one indicator
- [X] T023 [P] [US1] Write test: builder_to_dsl handles multiple indicators (up to 20, SC-005)
- [X] T024 [P] [US1] Write test: builder_to_dsl preserves existing DSL comments (FR-010, SC-009)
- [X] T025 [P] [US1] Write test: builder_to_dsl generates properly formatted DSL with correct indentation (FR-016)

### Implementation for User Story 1

- [X] T026 [P] [US1] Implement CommentPreserver module using Sourceror for comment preservation in lib/trading_strategy/strategy_editor/comment_preserver.ex
- [X] T027 [US1] Implement Synchronizer.builder_to_dsl/2 function with comment preservation in lib/trading_strategy/strategy_editor/synchronizer.ex
- [X] T028 [US1] Add builder_changed event handler with 300ms server-side rate limiting (FR-008) in lib/trading_strategy_web/live/strategy_live/edit.ex
- [X] T029 [US1] Implement BuilderFormHook JavaScript hook with 300ms debouncing in assets/js/hooks/builder_form_hook.js
- [X] T030 [US1] Add sync status indicator component (success/error/loading) in lib/trading_strategy_web/live/strategy_live/edit.html.heex
- [X] T031 [US1] Add loading indicator that shows after 200ms sync delay (FR-011) in lib/trading_strategy_web/live/strategy_live/edit.html.heex

### Integration Tests for User Story 1

- [X] T032 [US1] Write Wallaby test: user adds indicator in builder, DSL updates within 500ms in test/trading_strategy_web/live/strategy_live/edit_test.exs
- [X] T033 [US1] Write Wallaby test: user modifies indicator parameter in builder, DSL reflects change in test/trading_strategy_web/live/strategy_live/edit_test.exs
- [X] T034 [US1] Write Wallaby test: rapid changes in builder are debounced correctly (FR-008) in test/trading_strategy_web/live/strategy_live/edit_test.exs

**Checkpoint**: At this point, User Story 1 (Builder → DSL sync) should be fully functional and testable independently

---

## Phase 4: User Story 2 - DSL Editor Changes Sync to Builder (Priority: P1)

**Goal**: Enable power users to edit DSL code manually and see changes automatically reflected in the Advanced Strategy Builder, allowing efficient text-based editing with visual feedback.

**Independent Test**: Type valid DSL code (e.g., add indicator definition) in the DSL editor, verify builder form updates within 500ms to show the indicator visually.

### Tests for User Story 2

- [X] T035 [P] [US2] Write test: dsl_to_builder parses simple strategy with one indicator in test/trading_strategy/strategy_editor/synchronizer_test.exs
- [X] T036 [P] [US2] Write test: dsl_to_builder handles complex strategy (20 indicators + 10 conditions, SC-005) in test/trading_strategy/strategy_editor/synchronizer_test.exs
- [X] T037 [P] [US2] Write test: dsl_to_builder extracts and preserves comments in test/trading_strategy/strategy_editor/synchronizer_test.exs
- [X] T038 [P] [US2] Write test: dsl_to_builder handles indicator deletion in test/trading_strategy/strategy_editor/synchronizer_test.exs

### Implementation for User Story 2

- [X] T039 [P] [US2] Implement DslParser module wrapping Feature 001 parser in lib/trading_strategy/strategy_editor/dsl_parser.ex
- [X] T040 [US2] Implement Synchronizer.dsl_to_builder/1 function in lib/trading_strategy/strategy_editor/synchronizer.ex
- [X] T041 [US2] Add dsl_changed event handler with 300ms server-side rate limiting in lib/trading_strategy_web/live/strategy_live/edit.ex
- [X] T042 [US2] Install and configure CodeMirror 6 with basic setup extensions in assets/js/hooks/dsl_editor_hook.js
- [X] T043 [US2] Implement DSLEditorHook JavaScript hook with 300ms debouncing and cursor preservation in assets/js/hooks/dsl_editor_hook.js
- [X] T044 [US2] Add client-side syntax validation (brackets, quotes) with <100ms feedback in assets/js/hooks/dsl_editor_hook.js
- [X] T045 [US2] Implement external DSL update handling in DSLEditorHook.updated() to sync from builder changes in assets/js/hooks/dsl_editor_hook.js

### Integration Tests for User Story 2

- [X] T046 [US2] Write Wallaby test: user types valid DSL, builder updates within 500ms in test/trading_strategy_web/live/strategy_live/edit_test.exs
- [X] T047 [US2] Write Wallaby test: user deletes indicator in DSL, builder removes it in test/trading_strategy_web/live/strategy_live/edit_test.exs
- [X] T048 [US2] Write Wallaby test: rapid typing in DSL is debounced correctly in test/trading_strategy_web/live/strategy_live/edit_test.exs
- [X] T049 [US2] Write Wallaby test: cursor position preserved during external DSL updates in test/trading_strategy_web/live/strategy_live/edit_test.exs

**Checkpoint**: At this point, User Stories 1 AND 2 (bidirectional sync) should both work independently

---

## Phase 5: User Story 3 - Validation and Error Handling (Priority: P2)

**Goal**: Provide clear feedback when DSL code has syntax errors, preventing data corruption and providing a safety net for users.

**Independent Test**: Introduce a DSL syntax error (e.g., missing closing bracket), verify error is detected and displayed clearly, builder maintains last valid state, user can fix error and resume synchronization.

### Tests for User Story 3

- [X] T050 [P] [US3] Write test: Validator detects syntax errors with line/column numbers in test/trading_strategy/strategy_editor/validator_test.exs
- [X] T051 [P] [US3] Write test: Validator detects semantic errors (invalid indicator types) in test/trading_strategy/strategy_editor/validator_test.exs
- [X] T052 [P] [US3] Write test: Validator identifies unsupported DSL features (FR-009) in test/trading_strategy/strategy_editor/validator_test.exs
- [X] T053 [P] [US3] Write test: Validator handles parser crashes gracefully (FR-005a) in test/trading_strategy/strategy_editor/validator_test.exs

### Implementation for User Story 3

- [X] T054 [P] [US3] Implement Validator module with syntax validation in lib/trading_strategy/strategy_editor/validator.ex
- [X] T055 [P] [US3] Add semantic validation (indicator compatibility, condition logic) to Validator in lib/trading_strategy/strategy_editor/validator.ex
- [X] T056 [US3] Add validate_dsl event handler for manual validation trigger in lib/trading_strategy_web/live/strategy_live/edit.ex
- [X] T057 [US3] Update dsl_changed handler to preserve last valid builder state on error (FR-005) in lib/trading_strategy_web/live/strategy_live/edit.ex
- [X] T058 [US3] Add parser crash handler with error banner and retry option (FR-005a) in lib/trading_strategy_web/live/strategy_live/edit.ex
- [X] T059 [US3] Create inline error display component showing line/column numbers (FR-004) in lib/trading_strategy_web/live/strategy_live/components/validation_errors.ex
- [X] T060 [US3] Create persistent warning banner for unsupported DSL features (FR-009) in lib/trading_strategy_web/live/strategy_live/components/unsupported_features_banner.ex
- [X] T061 [US3] Add real-time syntax error display to DSLEditorHook (client-side validation) in assets/js/hooks/dsl_editor_hook.js

### Integration Tests for User Story 3

- [X] T062 [US3] Write Wallaby test: syntax error displayed inline with line/column numbers in test/trading_strategy_web/live/strategy_live/edit_test.exs
- [X] T063 [US3] Write Wallaby test: builder maintains last valid state when DSL has errors in test/trading_strategy_web/live/strategy_live/edit_test.exs
- [X] T064 [US3] Write Wallaby test: fixing DSL error resumes synchronization automatically in test/trading_strategy_web/live/strategy_live/edit_test.exs
- [X] T065 [US3] Write Wallaby test: unsupported DSL features show warning banner but sync supported elements in test/trading_strategy_web/live/strategy_live/edit_test.exs
- [X] T066 [US3] Write Wallaby test: parser crash shows error banner with retry option in test/trading_strategy_web/live/strategy_live/edit_test.exs

**Checkpoint**: At this point, all core functionality (bidirectional sync + validation) should be robust and user-friendly

---

## Phase 6: User Story 4 - Concurrent Edit Prevention (Priority: P3)

**Goal**: Prevent conflicts when users might edit both builder and DSL simultaneously, ensuring changes don't conflict or get lost.

**Independent Test**: Attempt to edit both interfaces in rapid succession, verify system handles it gracefully with clear feedback about which change was applied.

### Tests for User Story 4

- [X] T067 [P] [US4] Write test: last-modified timestamp determines authoritative source in test/trading_strategy/strategy_editor/synchronizer_test.exs
- [X] T068 [P] [US4] Write test: pending changes from both editors handled correctly in test/trading_strategy/strategy_editor/synchronizer_test.exs
- [X] T069 [P] [US4] Write test: synchronization completes before processing new opposite-editor changes in test/trading_strategy/strategy_editor/synchronizer_test.exs

### Implementation for User Story 4

- [X] T070 [P] [US4] Add last-modified editor tracking (FR-007) to ChangeEvent creation in lib/trading_strategy/strategy_editor/change_event.ex
- [X] T071 [US4] Implement conflict detection logic using last_modified_at timestamp in lib/trading_strategy_web/live/strategy_live/edit.ex
- [X] T072 [US4] Add visual indicator showing which editor was last modified (FR-007) in lib/trading_strategy_web/live/strategy_live/edit.html.heex
- [X] T073 [US4] Implement synchronization lock to prevent simultaneous syncs in lib/trading_strategy_web/live/strategy_live/edit.ex

### Integration Tests for User Story 4

- [X] T074 [US4] Write Wallaby test: rapid edits in both editors handled gracefully in test/trading_strategy_web/live/strategy_live/edit_test.exs
- [X] T075 [US4] Write Wallaby test: last-modified indicator shows correct editor in test/trading_strategy_web/live/strategy_live/edit_test.exs
- [X] T076 [US4] Write Wallaby test: saving with pending changes uses last-modified editor as source in test/trading_strategy_web/live/strategy_live/edit_test.exs

**Checkpoint**: All user stories should now be independently functional with robust conflict handling

---

## Phase 7: Polish & Cross-Cutting Concerns

**Purpose**: Improvements that affect multiple user stories

### Performance & Optimization

- [X] T077 [P] Run benchmark tests for 20-indicator strategy sync (SC-005, target <500ms) in test/trading_strategy/strategy_editor/benchmarks/
- [X] T078 [P] Add structured logging for synchronization events and errors (Observability principle) in lib/trading_strategy/strategy_editor/synchronizer.ex
- [X] T079 [P] Add Telemetry metrics for sync latency, parse errors, undo/redo usage in lib/trading_strategy/strategy_editor/telemetry.ex

### User Experience

- [X] T080 [P] Implement unsaved changes warning when navigating away (FR-018) in lib/trading_strategy_web/live/strategy_live/edit.ex
- [X] T081 [P] Add keyboard shortcuts (Ctrl+Z for undo, Ctrl+Shift+Z for redo, Ctrl+S for save) in assets/js/hooks/keyboard_shortcuts_hook.js
- [X] T082 [P] Add visual feedback for DSL changes (highlight/scroll to changed section, FR-014) in assets/js/hooks/dsl_editor_hook.js

### Testing & Validation

- [X] T083 [P] Run property-based tests for comment preservation (100+ round-trips, SC-009) in test/trading_strategy/strategy_editor/comment_preserver_test.exs
- [X] T084 [P] Write unit tests for EditHistory undo/redo stack operations in test/trading_strategy/strategy_editor/edit_history_test.exs
- [ ] T085 [P] Run end-to-end test of complete edit workflow (SC-007, target <2 minutes) in test/trading_strategy_web/live/strategy_live/edit_test.exs
- [ ] T086 Run full test suite (mix test) and verify all tests pass

### Documentation & Deployment

- [ ] T087 [P] Verify quickstart.md instructions work end-to-end (15-minute setup)
- [ ] T088 [P] Add inline code documentation (moduledoc, doc) for all new modules in lib/trading_strategy/strategy_editor/
- [X] T089 Code cleanup and formatting (mix format, remove debug code)
- [X] T090 Update CLAUDE.md with lessons learned from this feature

---

## Dependencies & Execution Order

### Phase Dependencies

- **Setup (Phase 1)**: No dependencies - can start immediately
- **Foundational (Phase 2)**: Depends on Setup completion - BLOCKS all user stories
- **User Stories (Phase 3-6)**: All depend on Foundational phase completion
  - User Story 1 (P1): Can start after Foundational - No dependencies on other stories
  - User Story 2 (P1): Can start after Foundational - Independent of US1 (but integrates)
  - User Story 3 (P2): Can start after Foundational - Enhances US1 + US2
  - User Story 4 (P3): Can start after Foundational - Enhances US1 + US2
- **Polish (Phase 7)**: Depends on all desired user stories being complete

### Within Each User Story

1. **Tests FIRST**: Write tests, ensure they FAIL
2. **Models/Data**: Implement data structures
3. **Services**: Implement business logic
4. **Handlers**: Implement event handlers
5. **UI**: Implement user interface components
6. **Integration**: Verify story works independently

### Parallel Opportunities

**Setup Phase (Phase 1)**:
- T002 (CodeMirror install) || T003 (Directory structure)

**Foundational Phase (Phase 2)**:
- T006 (edit_histories migration) || T008-T011 (All struct definitions)
- T020 (Configuration)

**User Story 1 (Phase 3)**:
- All tests (T021-T025) can run in parallel
- T026 (CommentPreserver) || T029 (BuilderFormHook) can run in parallel

**User Story 2 (Phase 4)**:
- All tests (T035-T038) can run in parallel
- T039 (DslParser) can run in parallel with T042 (CodeMirror setup)

**User Story 3 (Phase 5)**:
- All tests (T050-T053) can run in parallel
- T054 (syntax validation) || T055 (semantic validation) can run in parallel

**User Story 4 (Phase 6)**:
- All tests (T067-T069) can run in parallel
- T070 (ChangeEvent tracking) || T072 (UI indicator)

**Polish Phase (Phase 7)**:
- Almost all tasks can run in parallel (T077-T085)

---

## Parallel Example: User Story 2 (DSL → Builder Sync)

```bash
# Launch all tests for User Story 2 together:
claude-code task launch "Write test: dsl_to_builder parses simple strategy" --task-id T035 &
claude-code task launch "Write test: dsl_to_builder handles complex strategy" --task-id T036 &
claude-code task launch "Write test: dsl_to_builder extracts comments" --task-id T037 &
claude-code task launch "Write test: dsl_to_builder handles deletion" --task-id T038 &

# After tests fail, launch parallel implementation:
claude-code task launch "Implement DslParser wrapper" --task-id T039 &
claude-code task launch "Configure CodeMirror 6" --task-id T042 &
```

---

## Implementation Strategy

### MVP First (User Stories 1 + 2 Only)

1. ✅ Complete Phase 1: Setup
2. ✅ Complete Phase 2: Foundational (CRITICAL - blocks all stories)
3. ✅ Complete Phase 3: User Story 1 (Builder → DSL)
4. ✅ Complete Phase 4: User Story 2 (DSL → Builder)
5. **STOP and VALIDATE**: Test bidirectional sync independently (SC-001, SC-007)
6. Deploy/demo if ready (full bidirectional synchronization working)

### Incremental Delivery

1. **Foundation** (Phases 1-2) → Foundation ready
2. **+ User Story 1** (Phase 3) → Builder → DSL sync working → Test → Demo
3. **+ User Story 2** (Phase 4) → Full bidirectional sync → Test → Demo (MVP!)
4. **+ User Story 3** (Phase 5) → Error handling → Test → Demo
5. **+ User Story 4** (Phase 6) → Concurrent edit safety → Test → Demo
6. **+ Polish** (Phase 7) → Production-ready → Deploy

### Parallel Team Strategy

With multiple developers:

1. **Team completes Setup + Foundational together** (Phases 1-2)
2. **Once Foundational is done**:
   - Developer A: User Story 1 (Builder → DSL)
   - Developer B: User Story 2 (DSL → Builder)
   - Developer C: User Story 3 (Validation) - can start immediately
3. Stories complete and integrate independently
4. Team reviews and completes User Story 4 + Polish together

---

## Task Summary

| Phase | Task Count | Parallel Opportunities |
|-------|------------|------------------------|
| Phase 1: Setup | 4 | 2 parallel (T002, T003) |
| Phase 2: Foundational | 16 | 6 parallel (T006, T008-T011, T020) |
| Phase 3: User Story 1 (P1) | 14 | 5 tests + 2 implementation |
| Phase 4: User Story 2 (P1) | 15 | 4 tests + 2 implementation |
| Phase 5: User Story 3 (P2) | 17 | 4 tests + 3 implementation |
| Phase 6: User Story 4 (P3) | 10 | 3 tests + 2 implementation |
| Phase 7: Polish | 14 | 10 parallel |
| **TOTAL** | **90 tasks** | **42 parallelizable tasks** |

---

## Success Criteria Verification

Each phase maps to specific success criteria from spec.md:

- **Phase 3 (US1)**: Verifies SC-001 (Builder → DSL <500ms), FR-010 (comment preservation), FR-016 (clean DSL generation)
- **Phase 4 (US2)**: Verifies SC-001 (DSL → Builder <500ms), SC-005 (20 indicators without delay)
- **Phase 5 (US3)**: Verifies SC-002 (99% valid DSL syncs), SC-004 (errors within 1 second), SC-008 (95% actionable errors)
- **Phase 6 (US4)**: Verifies SC-003 (no data loss on editor switch), SC-006 (zero data loss across 1000+ scenarios)
- **Phase 7 (Polish)**: Verifies SC-007 (full workflow <2 minutes), SC-009 (comments preserved 100+ round-trips)

---

## Notes

- [P] tasks = different files, no dependencies, can run in parallel
- [Story] label maps task to specific user story for traceability
- Each user story should be independently completable and testable
- **Write tests FIRST**, ensure they FAIL before implementing
- Commit after each task or logical group
- Stop at any checkpoint to validate story independently
- Follow Elixir/Phoenix conventions (contexts, LiveView patterns, Ecto changesets)
- Use CodeMirror 6 (not Monaco Editor, as decided in research)
- Use Sourceror for comment preservation (FR-010, SC-009)
- Implement hybrid parsing (client-side syntax + server-side semantic) as per research
- No autosave - explicit save only (FR-020)
- 300ms debounce minimum (FR-008)
- <500ms synchronization latency target (FR-001, FR-002, SC-001)

---

## Suggested MVP Scope

**Minimum Viable Product** = Phases 1 + 2 + 3 + 4

This delivers:
- ✅ Bidirectional synchronization (Builder ↔ DSL)
- ✅ Comment preservation (FR-010)
- ✅ Undo/redo support (FR-012)
- ✅ Debouncing (FR-008)
- ✅ <500ms latency (FR-001, FR-002)
- ✅ Handles 20 indicators (SC-005)

**Total MVP Tasks**: 49 tasks (Setup + Foundational + US1 + US2)

**Estimated Effort**: 2-3 weeks (as per research.md timeline)

After MVP, incrementally add:
- **Phase 5** (US3) for robust error handling
- **Phase 6** (US4) for concurrent edit safety
- **Phase 7** for polish and optimization
