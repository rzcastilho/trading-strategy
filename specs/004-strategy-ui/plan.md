# Implementation Plan: Strategy Registration and Validation UI

**Branch**: `004-strategy-ui` | **Date**: 2026-02-08 | **Spec**: [spec.md](./spec.md)
**Input**: Feature specification from `/specs/004-strategy-ui/spec.md`

**Note**: This template is filled in by the `/speckit.plan` command. See `.specify/templates/commands/plan.md` for the execution workflow.

## Summary

Create a Phoenix LiveView-based web interface for registering, validating, and managing trading strategies. The UI will provide real-time validation feedback, strategy list management, editing capabilities, and syntax testing features. This feature builds on top of the existing Strategy DSL (Feature 001) and leverages Phoenix LiveView for reactive, real-time user interactions without requiring page refreshes.

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

**Strategy-as-Library** (Principle I):
- [x] Strategy is self-contained module with clear API (✓ Feature is UI layer, not a strategy itself)
- [x] Independent unit tests planned (>80% coverage target) (✓ LiveView tests planned)
- [x] No dependencies on other strategy libraries (✓ UI consumes Strategy DSL library, proper layering)

**Backtesting Required** (Principle II - NON-NEGOTIABLE):
- [x] N/A - This is a UI feature for strategy registration, not a trading strategy implementation
- [x] However, UI MUST enforce that strategies can only be activated if backtest results exist (enforcement mechanism required)

**Risk Management First** (Principle III - NON-NEGOTIABLE):
- [x] N/A - This is a UI feature, but UI MUST validate that risk parameters are present before allowing strategy save
- [x] UI will validate presence of: max_position_size, stop_loss rules, daily_loss_limit via DSL validator

**Observability & Auditability** (Principle IV):
- [x] Structured logging planned for strategy creation/updates (audit trail of who created/modified what)
- [x] LiveView state transitions for auditability (form changes, validation events)
- [x] Metrics: form completion time, validation error rates, user actions tracked

**Real-Time Data Contracts** (Principle V):
- [x] N/A - UI feature does not interact with market data streams
- [x] Validation API contract with DSL library clearly defined

**Performance & Latency Discipline** (Principle VI):
- [x] Validation response time <1 second per spec (SC-002)
- [x] Strategy list load time <2 seconds for 100+ strategies (SC-004)
- [x] Syntax test completion <3 seconds for 10 indicators (SC-005)

**Simplicity & Transparency** (Principle VII):
- [x] Starting with simple form-based registration (no complex builders yet)
- [x] No premature optimization - use standard LiveView patterns
- [x] YAGNI enforced - build only what spec requires (no advanced features like visual strategy builders)

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
# Feature 004: Strategy Registration and Validation UI

lib/trading_strategy_web/
├── live/
│   ├── strategy_live/               # NEW: Strategy management LiveViews
│   │   ├── index.ex                 # NEW: Strategy list page
│   │   ├── form.ex                  # NEW: Strategy registration/edit form component
│   │   └── show.ex                  # NEW: Strategy details view
│   └── paper_trading_live.ex        # EXISTING: Reference for LiveView patterns
├── controllers/
│   └── strategy_controller.ex       # EXISTING: API endpoints (unchanged)
├── components/
│   ├── core_components.ex           # EXISTING: Shared UI components
│   └── strategy_components.ex       # NEW: Strategy-specific components
└── router.ex                        # MODIFIED: Add LiveView routes

lib/trading_strategy/
├── strategies/
│   ├── strategy.ex                  # EXISTING: Schema (may need minor changes)
│   └── dsl/
│       └── validator.ex             # EXISTING: Used by UI for real-time validation
└── strategies.ex                    # MODIFIED: Add user-scoped queries, version conflict detection

priv/repo/migrations/
└── [timestamp]_add_user_fields_to_strategies.exs  # NEW: Add user_id, updated_by, metadata

test/trading_strategy_web/
└── live/
    └── strategy_live/
        ├── index_test.exs           # NEW: List view tests
        ├── form_test.exs            # NEW: Form validation tests
        └── show_test.exs            # NEW: Detail view tests

assets/
├── css/
│   └── app.css                      # MODIFIED: Add strategy form styles
└── js/
    └── app.js                       # MODIFIED: Add client-side form helpers (autosave)
```

**Structure Decision**: Extends existing Phoenix/LiveView architecture. LiveView components under `live/strategy_live/` follow the established pattern from `paper_trading_live.ex`. Reuses existing DSL validation logic, adds user authentication/authorization layer, and implements version conflict detection at the context layer.

## Complexity Tracking

> **Fill ONLY if Constitution Check has violations that must be justified**

**No violations** - All Constitution principles are satisfied:
- This is a UI layer feature (not a trading strategy), so strategy-specific principles are N/A
- Validation and enforcement mechanisms ensure strategies cannot violate Constitution when activated
- Architecture follows Phoenix/LiveView best practices (simplicity principle)
- No premature abstractions or over-engineering detected

---

## Implementation Summary

### Phase 0: Research (COMPLETED)

**Output**: `research.md`

**Key Decisions**:
1. **Form Validation**: LiveView with server-side changesets, real-time validation via `phx-change`
2. **Authentication**: `mix phx.gen.auth` with user-scoped strategies
3. **Version Conflicts**: Optimistic locking using `lock_version` field
4. **Uniqueness**: Two-phase validation (`unsafe_validate_unique` + `unique_constraint`)
5. **Component Architecture**: Function components for UI, LiveComponents for stateful builders
6. **Autosave**: 30-second periodic save + LiveView form recovery
7. **Status Management**: Four-state lifecycle (draft → active → inactive → archived)
8. **DSL Handling**: Reuse existing validators, support YAML/TOML

### Phase 1: Design & Contracts (COMPLETED)

**Outputs**: 
- `data-model.md` - Entity schemas, relationships, validation rules
- `contracts/liveview_routes.md` - Route definitions, events, socket assigns
- `contracts/validation_api.md` - Validation flow, error types, testing
- `quickstart.md` - Step-by-step implementation guide

**Key Artifacts**:
1. **Data Model**: Extended `strategies` table with `user_id`, `lock_version`, `metadata` fields
2. **LiveView Routes**: 4 main routes (index, new, show, edit) + 2 LiveComponents
3. **Validation API**: 3-tier validation (instant, debounced, on-submit)
4. **Context Functions**: User-scoped queries, version conflict handling, status transitions

**Updated Files**:
- `CLAUDE.md` - Added Phoenix LiveView, authentication patterns to project context

### Phase 2: Tasks Generation (NEXT STEP)

**Command**: `/speckit.tasks`

**Expected Output**: `tasks.md` with actionable, dependency-ordered implementation tasks

**Task Categories**:
1. Authentication setup (`mix phx.gen.auth`)
2. Database migrations (user association, lock_version, metadata)
3. Schema updates (Strategy + User relationship)
4. Context functions (user scoping, validation, versioning)
5. LiveView implementation (index, form, show)
6. LiveComponents (indicator builder, condition builder)
7. Router configuration
8. Testing (unit, integration, LiveView)
9. Manual QA checklist

---

## Technical Debt & Future Enhancements

### Technical Debt Identified
None - clean implementation following established patterns.

### Future Enhancements (Out of Scope for Feature 004)
1. **Advanced DSL Editor**: Syntax highlighting, autocomplete, live preview
2. **Visual Strategy Builder**: Drag-and-drop interface for non-technical users
3. **Strategy Templates**: Pre-built templates for common patterns (mean reversion, momentum, etc.)
4. **Strategy Comparison**: Side-by-side comparison of multiple strategies
5. **Collaborative Editing**: Multiple users editing same strategy with operational transformation
6. **Strategy Marketplace**: Share/discover strategies (with permission controls)
7. **AI-Assisted Strategy Generation**: LLM-powered strategy suggestions based on goals

---

## Risk Assessment

| Risk | Likelihood | Impact | Mitigation |
|------|-----------|--------|------------|
| Authentication vulnerabilities | Low | High | Use battle-tested `phx.gen.auth`, follow security best practices |
| Version conflict edge cases | Medium | Medium | Comprehensive testing of concurrent edits, clear user messaging |
| DSL validation performance | Low | Medium | Cache parsed results, lazy validation for large strategies |
| User confusion on status transitions | Medium | Low | Clear UI messaging, tooltips, validation gates |
| Data loss during form editing | Low | High | Autosave + LiveView recovery + localStorage backup |

---

## Dependencies

### Depends On (Existing Features)
- **Feature 001**: Strategy DSL Library - Provides parser and validator used by UI

### Depended On By (Future Features)
- **Feature 005**: Backtest UI - Will need to link backtests to strategies
- **Feature 006**: Paper Trading UI - Will select strategies from this UI
- **Feature 007**: Live Trading UI - Will activate strategies created here

---

## Metrics & Monitoring

### Performance Metrics
- Strategy list load time (target: <2s for 100+ strategies)
- Validation response time (target: <1s)
- Syntax test duration (target: <3s for 10 indicators)
- Form autosave frequency (every 30s)

### Business Metrics
- Number of strategies created per user (avg, p50, p95)
- Strategies activation rate (% of drafts that become active)
- Strategy edit frequency (edits per strategy lifetime)
- Validation error rates (by error type)

### Telemetry Events
```elixir
[:trading_strategy, :strategies, :create, :start]
[:trading_strategy, :strategies, :create, :stop]
[:trading_strategy, :strategies, :validate, :start]
[:trading_strategy, :strategies, :validate, :stop]
[:trading_strategy, :strategies, :syntax_test, :start]
[:trading_strategy, :strategies, :syntax_test, :stop]
[:trading_strategy, :strategies, :version_conflict]
```

---

## Rollout Plan

### Phase A: Internal Testing (Week 1)
- Deploy to staging environment
- Manual testing by dev team
- Load testing with 500+ strategies per user
- Security audit of authentication flow

### Phase B: Alpha Testing (Week 2)
- Invite 5-10 internal users
- Collect feedback on UX
- Monitor performance metrics
- Fix critical bugs

### Phase C: Beta Testing (Weeks 3-4)
- Invite 50 early adopters
- A/B test different form layouts
- Iterate on validation error messaging
- Performance tuning based on real usage

### Phase D: General Availability (Week 5+)
- Announce feature to all users
- Provide migration guide for existing strategies
- Monitor error rates and performance
- Plan next iteration based on feedback

---

## Sign-off Checklist

Before considering this feature complete:

- [ ] All user stories in `spec.md` implemented
- [ ] All acceptance scenarios pass
- [ ] All success criteria met (SC-001 through SC-009)
- [ ] Constitution principles verified (see Constitution Check above)
- [ ] Test coverage >80%
- [ ] Manual testing checklist complete (see quickstart.md Phase 7)
- [ ] Performance targets met (load time, validation speed, syntax testing)
- [ ] Security audit passed (authentication, authorization, SQL injection, XSS)
- [ ] Documentation updated (README, API docs, user guide)
- [ ] Deployment runbook created
- [ ] Monitoring dashboards configured
- [ ] Rollback procedure tested

---

## Approval

**Planning Completed**: 2026-02-08

**Ready for Implementation**: ✅ Yes

**Next Command**: `/speckit.tasks` to generate implementation task list

**Estimated Effort**: 10 days (1 experienced Elixir/Phoenix developer)

**Blocked By**: None (all dependencies satisfied)

---

*This plan was generated by `/speckit.plan` following the workflow defined in `.specify/templates/commands/plan.md`*
