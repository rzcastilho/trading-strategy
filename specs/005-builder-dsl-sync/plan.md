# Implementation Plan: Bidirectional Strategy Editor Synchronization

**Branch**: `005-builder-dsl-sync` | **Date**: 2026-02-10 | **Spec**: [spec.md](./spec.md)
**Input**: Feature specification from `/specs/005-builder-dsl-sync/spec.md`

**Note**: This template is filled in by the `/speckit.plan` command. See `.specify/templates/commands/plan.md` for the execution workflow.

## Summary

Implement bidirectional real-time synchronization between the Advanced Strategy Builder (visual form interface) and manual DSL editor, allowing users to seamlessly edit strategies in either interface with changes automatically reflected in the other. This includes validation, error handling, undo/redo support, and preservation of DSL comments.

## Technical Context

**Language/Version**: Elixir 1.17+ (OTP 27+)
**Primary Dependencies**:
- Phoenix 1.7+ with LiveView for real-time UI updates
- DSL parser from Feature 001 (strategy-dsl-library)
- JavaScript code editor (NEEDS CLARIFICATION: CodeMirror vs Monaco Editor)
- Phoenix.PubSub for event broadcasting
**Storage**: PostgreSQL (strategy definitions via Ecto)
**Testing**: ExUnit (unit tests for parser integration), Wallaby (end-to-end UI synchronization)
**Target Platform**: Web browser (client-side editor), Phoenix server (DSL validation)
**Project Type**: UI feature - real-time bidirectional editor synchronization
**Performance Goals**:
- <500ms synchronization latency (builder ↔ DSL)
- <300ms debounce delay for user input
- <200ms loading indicator threshold
**Constraints**:
- Client-side state management for low-latency sync
- Preserve DSL comments during transformations
- Handle parser failures gracefully
- Single shared undo/redo stack across both editors
**Scale/Scope**: Single-user editing session, strategies with up to 20 indicators, 10 entry/exit conditions

**Key Unknowns**:
- NEEDS CLARIFICATION: Best JavaScript code editor for Phoenix LiveView integration (CodeMirror, Monaco, Ace)
- NEEDS CLARIFICATION: Client-side vs server-side DSL parsing approach
- NEEDS CLARIFICATION: AST format that preserves comments and formatting
- NEEDS CLARIFICATION: Undo/redo implementation pattern (client-side stack, server-side, or hybrid)
- NEEDS CLARIFICATION: Debouncing strategy in LiveView (JS hook, server-side, or both)

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

**⚠️ FEATURE TYPE: UI TOOL (NOT A TRADING STRATEGY)**

This feature implements a UI component for editing strategies, not a trading strategy itself. Therefore, most trading-specific principles are not applicable.

**Strategy-as-Library** (Principle I): ✅ **N/A**
- Rationale: This is a UI tool, not a strategy library

**Backtesting Required** (Principle II - NON-NEGOTIABLE): ✅ **N/A**
- Rationale: No trading logic to backtest; this is an editor interface

**Risk Management First** (Principle III - NON-NEGOTIABLE): ✅ **N/A**
- Rationale: No trading decisions made; this tool edits strategy definitions

**Observability & Auditability** (Principle IV): ⚠️ **PARTIALLY APPLIES**
- [x] Structured logging planned for synchronization events and errors
- [x] User actions logged for debugging (editor switches, validation errors)
- [x] Metrics planned: sync latency, parse errors, undo/redo usage
- Note: Not trading decisions, but user editing actions for debugging

**Real-Time Data Contracts** (Principle V): ✅ **N/A**
- Rationale: No market data integration; operates on strategy definitions only

**Performance & Latency Discipline** (Principle VI): ✅ **APPLIES**
- [x] Synchronization latency target <500ms (FR-001, FR-002)
- [x] Debounce delay 300ms minimum (FR-008)
- [x] Loading indicator threshold <200ms (FR-011)
- [x] Performance testing planned for strategies with 20 indicators + 10 conditions (SC-005)

**Simplicity & Transparency** (Principle VII): ✅ **APPLIES**
- [x] Starting with synchronous client-side approach (LiveView + JS hooks)
- [x] No premature optimization (client-side parsing before server-side validation)
- [x] Clear separation: builder state ↔ DSL text ↔ parser
- [x] Avoiding over-engineering: single shared undo stack (not dual stacks)

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

```text
# Feature 005: Bidirectional Strategy Editor Synchronization

lib/
├── trading_strategy/
│   └── strategy_editor/              # NEW: Editor synchronization logic
│       ├── dsl_parser.ex            # Interface to Feature 001 DSL parser
│       ├── builder_state.ex         # Builder form state management
│       ├── synchronizer.ex          # Core sync logic (builder ↔ DSL)
│       ├── validator.ex             # DSL syntax validation
│       ├── comment_preserver.ex     # Comment preservation during transformations
│       └── edit_history.ex          # Shared undo/redo stack
│
└── trading_strategy_web/
    ├── live/
    │   └── strategy_live/
    │       ├── edit.ex              # MODIFY: Main strategy editor LiveView
    │       ├── edit.html.heex       # MODIFY: Add DSL editor pane
    │       └── components/
    │           ├── builder_form.ex       # MODIFY: Advanced Strategy Builder component
    │           └── dsl_editor.ex         # NEW: DSL code editor component
    │
    └── assets/
        └── js/
            ├── hooks/
            │   ├── dsl_editor_hook.js    # NEW: CodeMirror/Monaco integration
            │   ├── debounce_hook.js      # NEW: Input debouncing
            │   └── sync_indicator_hook.js # NEW: Sync status indicator
            └── app.js                     # MODIFY: Register new hooks

test/
├── trading_strategy/
│   └── strategy_editor/
│       ├── dsl_parser_test.exs           # Unit tests for parser integration
│       ├── synchronizer_test.exs         # Sync logic tests
│       ├── validator_test.exs            # Validation tests
│       ├── comment_preserver_test.exs    # Comment preservation tests
│       └── edit_history_test.exs         # Undo/redo tests
│
└── trading_strategy_web/
    └── live/
        └── strategy_live/
            └── edit_test.exs             # Integration tests (Wallaby)
                                          # - Builder → DSL sync
                                          # - DSL → Builder sync
                                          # - Error handling
                                          # - Undo/redo across editors

config/
├── config.exs              # MODIFY: Add editor configuration (debounce delays, sync thresholds)
└── dev.exs                 # MODIFY: Development-specific editor settings
```

**Structure Decision**: New `strategy_editor/` context module for synchronization logic, keeping it separate from trading strategy execution logic. LiveView components handle real-time UI updates, with JavaScript hooks managing the code editor integration and client-side debouncing for performance.

## Complexity Tracking

> **Fill ONLY if Constitution Check has violations that must be justified**

| Violation | Why Needed | Simpler Alternative Rejected Because |
|-----------|------------|-------------------------------------|
| N/A | No violations | All applicable constitution principles satisfied |

---

## Phase Completion Status

### ✅ Phase 0: Research (COMPLETE)

**Duration**: 2026-02-10 (completed in parallel)
**Status**: ✅ All technical unknowns resolved

**Deliverables**:
- ✅ **[research.md](./research.md)** - Consolidated research findings (15KB)
  - JavaScript code editor selection: **CodeMirror 6**
  - DSL parsing strategy: **Hybrid (Client + Server)**
  - Comment preservation: **Sourceror library**
  - Undo/redo pattern: **Hybrid (Client + Server)**
  - Debouncing strategy: **Hybrid (JS Hooks + Server Rate Limiting)**

**Supporting Research** (60,000+ words, 250+ KB):
- ✅ [EDITOR_RESEARCH.md](./EDITOR_RESEARCH.md) (26KB) - CodeMirror vs Monaco vs Ace comparison
- ✅ [DSL_PARSING_DETAILED.md](./DSL_PARSING_DETAILED.md) (27KB) - Hybrid parsing approach
- ✅ [COMMENT_PRESERVATION_RESEARCH.md](./COMMENT_PRESERVATION_RESEARCH.md) (28KB) - Sourceror analysis
- ✅ [DEBOUNCE_RESEARCH.md](./DEBOUNCE_RESEARCH.md) (34KB) - Debouncing patterns
- ✅ [IMPLEMENTATION_GUIDE.md](./IMPLEMENTATION_GUIDE.md) (15KB) - CodeMirror setup
- ✅ [SYNC_ARCHITECTURE.md](./SYNC_ARCHITECTURE.md) (17KB) - System design
- ✅ [INDEX.md](./INDEX.md) (14KB) - Navigation guide

**Key Decisions**:
- CodeMirror 6 (124KB) over Monaco (2+ MB) - lighter, proven in Livebook
- Hybrid parsing for <500ms latency (client syntax + server semantic)
- Sourceror for 100+ round-trip comment preservation (FR-010, SC-009)
- Hybrid undo/redo for <50ms response time (10x better than target)
- 300ms debounce with defense-in-depth (JS + server rate limiting)

**Gate Status**: ✅ PASSED - All NEEDS CLARIFICATION items resolved

---

### ✅ Phase 1: Design & Contracts (COMPLETE)

**Duration**: 2026-02-10 (completed immediately after Phase 0)
**Status**: ✅ All design artifacts generated

**Deliverables**:
- ✅ **[data-model.md](./data-model.md)** (25KB) - Entity definitions
  - StrategyDefinition (root entity)
  - BuilderState (form data structure)
  - ChangeEvent (undo/redo operations)
  - EditHistory (undo/redo stack)
  - ValidationResult (error/warning reporting)

- ✅ **[contracts/liveview_events.md](./contracts/liveview_events.md)** (22KB) - Event handler contracts
  - `dsl_changed` - DSL → Builder sync
  - `builder_changed` - Builder → DSL sync
  - `undo` / `redo` - Undo/redo operations
  - `save_strategy` - Explicit save (no autosave, FR-020)
  - `validate_dsl` - Manual validation trigger
  - JavaScript hooks (DSLEditorHook, BuilderFormHook)

- ✅ **[quickstart.md](./quickstart.md)** (18KB) - Development environment setup
  - 15-minute quickstart guide
  - Dependency installation (Sourceror, CodeMirror 6)
  - Configuration examples (dev.exs, test.exs)
  - Troubleshooting guide
  - Performance monitoring tips

- ✅ **CLAUDE.md updated** - Agent context now includes:
  - Elixir 1.17+ (OTP 27+)
  - Phoenix LiveView for real-time sync
  - CodeMirror 6 for DSL editor
  - Sourceror for comment preservation
  - Hybrid parsing architecture

**Architecture Summary**:
- **UI Layer**: Phoenix LiveView + CodeMirror 6
- **Parsing**: Hybrid (client JS syntax + server Elixir semantic)
- **Synchronization**: Bidirectional (builder ↔ DSL) with debouncing
- **Undo/Redo**: Hybrid (client stacks + server event sourcing)
- **Persistence**: PostgreSQL (strategy_definitions + edit_histories tables)

**Requirements Coverage**: All 19 functional requirements (FR-001 through FR-020) addressed in design

**Constitution Check (Re-evaluated)**:
- ✅ Performance & Latency: <500ms sync target achievable (typically 250-350ms)
- ✅ Simplicity & Transparency: Hybrid pattern is industry standard, not over-engineered
- ✅ N/A Principles: Strategy-as-Library, Backtesting, Risk Management (UI tool, not trading strategy)

**Gate Status**: ✅ PASSED - Design complete, ready for implementation

---

### ⏳ Phase 2: Task Generation (PENDING)

**Next Command**: `/speckit.tasks`
**Purpose**: Generate actionable, dependency-ordered task list (`tasks.md`)

**Prerequisites**:
- ✅ Phase 0 research complete
- ✅ Phase 1 design artifacts generated
- ✅ Constitution check passed (twice)
- ⏳ User approval of plan (this document)

**Expected Output**:
- `tasks.md` with dependency-ordered implementation tasks
- Test-first approach (write tests → implement → verify)
- Clear acceptance criteria per task
- Estimated effort per task (hours/days)

---

## Implementation Readiness Checklist

Before proceeding to task generation:

- [x] All NEEDS CLARIFICATION resolved (Phase 0)
- [x] Technology stack validated (CodeMirror 6, Sourceror, Hybrid parsing)
- [x] Data model defined (5 core entities)
- [x] API contracts specified (6 event handlers + 2 JS hooks)
- [x] Development environment documented (quickstart.md)
- [x] Agent context updated (CLAUDE.md)
- [x] Constitution compliance verified (twice - before and after design)
- [ ] User/team approval of plan (awaiting sign-off)

**Next Step**: Review this plan, approve, then run `/speckit.tasks` to generate implementation tasks
