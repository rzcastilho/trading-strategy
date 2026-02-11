# Implementation Plan: Indicator Output Values Display

**Branch**: `006-indicator-value-inspection` | **Date**: 2026-02-11 | **Spec**: [spec.md](./spec.md)
**Input**: Feature specification from `/specs/006-indicator-value-inspection/spec.md`

**Note**: This template is filled in by the `/speckit.plan` command. See `.specify/templates/commands/plan.md` for the execution workflow.

## Summary

Display indicator output value metadata in the strategy builder UI to help users understand what values are available for use in trading conditions. For single-value indicators (e.g., SMA), show that they can be referenced directly. For multi-value indicators (e.g., Bollinger Bands with upper_band, middle_band, lower_band), display all available fields with descriptions, units, and example usage syntax. Information is presented via tooltips in both the "Add Indicator" form and the configured indicators list, with <200ms latency requirement.

## Technical Context

**Language/Version**: Elixir 1.17+ (OTP 27+)
**Primary Dependencies**: Phoenix 1.7+, Phoenix LiveView, TradingIndicators library (external)
**Storage**: None (UI-only feature, metadata fetched from indicator modules)
**Testing**: ExUnit (unit tests for metadata helpers), Wallaby (end-to-end UI interactions)
**Target Platform**: Desktop browsers (Chrome, Firefox, Safari)
**Project Type**: UI enhancement for existing strategy builder LiveView
**Performance Goals**: <200ms latency for displaying indicator metadata after selection
**Constraints**: Desktop-only (no mobile optimization), basic keyboard accessibility required
**Scale/Scope**: Small - Tooltip-based information display, no backend changes

**Key Technical Decisions**:
- **Metadata Source**: TradingIndicators library provides `output_fields_metadata/0` function per indicator
- **UI Pattern**: Info icons with tooltips (hover/click) to avoid cluttering the interface
- **Component Reuse**: Leverage existing `core_components.ex` tooltip/icon components if available
- **JavaScript**: Minimal JS hooks for tooltip interactions and keyboard navigation (Tab, Enter, Escape)
- **LiveView Integration**: Enhance existing IndicatorBuilder LiveComponent
- **Caching Strategy**: NEEDS CLARIFICATION - Should metadata be cached or fetched on-demand?
- **Error Handling**: Graceful degradation - show "Output information unavailable" if metadata missing

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

**Note**: This is a UI/UX feature for the strategy builder, not a trading strategy implementation. Most constitution principles are not applicable (N/A). Only performance and simplicity principles apply.

**Strategy-as-Library** (Principle I): **N/A**
- Not a trading strategy - this is a UI enhancement for displaying metadata

**Backtesting Required** (Principle II - NON-NEGOTIABLE): **N/A**
- Not a trading strategy - no trading logic to backtest
- UI functionality validated via integration tests (Wallaby)

**Risk Management First** (Principle III - NON-NEGOTIABLE): **N/A**
- Informational feature only - no capital at risk
- Helps users understand indicators, but doesn't execute trades

**Observability & Auditability** (Principle IV): **N/A**
- No trading decisions made - purely informational display
- Standard Phoenix logging sufficient for debugging UI issues

**Real-Time Data Contracts** (Principle V): **N/A**
- No market data dependencies - metadata is static and sourced from indicator modules

**Performance & Latency Discipline** (Principle VI): **APPLICABLE** ✅
- [x] Metadata display latency target <200ms (spec requirement SC-007)
- [x] Performance testing planned for metadata retrieval
- [x] **POST-DESIGN**: Caching strategy selected (lazy persistent_term, 0.0006ms latency)
- [x] **POST-DESIGN**: Benchmark results show 2000x faster than requirement
- [x] **POST-DESIGN**: Tooltip display latency expected 10-20ms (well under target)

**Simplicity & Transparency** (Principle VII): **APPLICABLE** ✅
- [x] Starting with tooltip-based display (simplest viable approach)
- [x] Leveraging existing UI components (core_components)
- [x] **POST-DESIGN**: No premature optimization - persistent_term cache chosen for consistency with existing Registry pattern, not for performance necessity
- [x] **POST-DESIGN**: YAGNI enforced - only P1/P2 user stories implemented (P3 deferred)
- [x] **POST-DESIGN**: Hybrid approach (daisyUI + custom hook) matches Feature 005 pattern
- [x] **POST-DESIGN**: No external dependencies added (lightweight ~3KB custom code)

---

### Post-Design Evaluation (Phase 1 Complete)

**Performance Validation**:
- ✅ Metadata retrieval: 0.0006ms (2000x faster than 200ms target)
- ✅ Tooltip display: 10-20ms expected (10x better than 200ms target)
- ✅ Memory footprint: 4KB for metadata cache + 2KB per tooltip instance
- ✅ Bundle size: +3KB (TooltipHook.js)

**Simplicity Validation**:
- ✅ Minimal code changes: 1 new module (IndicatorMetadata), 1 new component (tooltip), 1 new hook
- ✅ No database migrations or schema changes
- ✅ No new API endpoints or backend services
- ✅ Leverages existing TradingIndicators library contract
- ✅ Follows established patterns (persistent_term caching from Registry, Hybrid architecture from Feature 005)

**Constitution Compliance**: **PASS** ✅
- All applicable principles (Performance, Simplicity) met or exceeded
- N/A principles correctly identified and justified
- No unnecessary complexity introduced
- No violations requiring Complexity Tracking table

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

**Files Modified**:
```text
lib/trading_strategy_web/
└── live/
    └── strategy_builder_live/
        └── indicator_builder.ex    # MODIFIED - Add metadata display to indicator form

lib/trading_strategy_web/
└── components/
    └── core_components.ex          # POSSIBLY MODIFIED - Enhance tooltip if needed
```

**Files Created**:
```text
lib/trading_strategy/
└── strategy_editor/
    └── indicator_metadata.ex       # NEW - Helper module for fetching indicator metadata

assets/js/
└── hooks/
    └── indicator_metadata_hook.js  # NEW - Tooltip interactions, keyboard navigation

test/trading_strategy/
└── strategy_editor/
    └── indicator_metadata_test.exs # NEW - Unit tests for metadata helper

test/trading_strategy_web/
└── live/
    └── strategy_builder_live/
        └── indicator_builder_test.exs # MODIFIED - Add tests for metadata display
```

**Structure Decision**: Minimal changes to existing codebase. Add a helper module (`IndicatorMetadata`) to encapsulate metadata fetching logic, enhance the existing `IndicatorBuilder` LiveComponent to display metadata, and add a JavaScript hook for tooltip interactions. No database migrations or schema changes required.

## Complexity Tracking

> **Fill ONLY if Constitution Check has violations that must be justified**

| Violation | Why Needed | Simpler Alternative Rejected Because |
|-----------|------------|-------------------------------------|
| [e.g., 4th project] | [current need] | [why 3 projects insufficient] |
| [e.g., Repository pattern] | [specific problem] | [why direct DB access insufficient] |
