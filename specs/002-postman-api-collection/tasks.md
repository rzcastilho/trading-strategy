# Tasks: Postman API Collection for Trading Strategy

**Input**: Design documents from `/specs/002-postman-api-collection/`
**Prerequisites**: plan.md, spec.md, research.md, data-model.md, contracts/

**Tests**: No tests requested for this feature (artifact creation only)

**Organization**: Tasks are grouped by user story to enable independent implementation and testing of each story.

## Format: `[ID] [P?] [Story?] Description`

- **[P]**: Can run in parallel (different files, no dependencies)
- **[Story]**: Which user story this task belongs to (e.g., US1, US2, US3)
- Include exact file paths in descriptions

## Path Conventions

- Collection file: `postman/trading-strategy-api.postman_collection.json`
- Optional environment file: `postman/localhost-dev.postman_environment.json`

---

## Phase 1: Setup (Project Structure)

**Purpose**: Initialize project structure for Postman collection artifacts

- [X] T001 Create postman/ directory at repository root

---

## Phase 2: Foundational (Collection Skeleton)

**Purpose**: Create base collection structure that ALL user stories depend on

**⚠️ CRITICAL**: No user story work can begin until this phase is complete

- [X] T002 Create base collection JSON structure in postman/trading-strategy-api.postman_collection.json
- [X] T003 Add collection metadata (name: "Trading Strategy API", schema: v2.1, description) in postman/trading-strategy-api.postman_collection.json
- [X] T004 Add collection variables (base_url: http://localhost:4000, port: 4000) in postman/trading-strategy-api.postman_collection.json
- [X] T005 Create 4 empty folder structures (Strategy Management, Backtest Management, Paper Trading, Live Trading) in postman/trading-strategy-api.postman_collection.json

**Checkpoint**: Collection skeleton ready - user story implementation can now begin in parallel

---

## Phase 3: User Story 1 - Test Strategy Management Endpoints (Priority: P1) 🎯 MVP

**Goal**: Enable developers to test strategy CRUD operations (create, retrieve, update, delete) through the REST API

**Independent Test**: Import collection → Set base_url → Execute all Strategy Management folder requests → Verify 200/201/204 responses and test scripts pass

### Implementation for User Story 1

- [X] T006 [P] [US1] Add "List Strategies" GET request to Strategy Management folder in postman/trading-strategy-api.postman_collection.json
- [X] T007 [P] [US1] Add test scripts for "List Strategies" (status 200, data array, array item fields) in postman/trading-strategy-api.postman_collection.json
- [X] T008 [P] [US1] Add example response for "List Strategies" (200 OK with strategies array) in postman/trading-strategy-api.postman_collection.json
- [X] T009 [P] [US1] Add "Create Strategy" POST request with semi-realistic RSI strategy example body to Strategy Management folder in postman/trading-strategy-api.postman_collection.json
- [X] T010 [P] [US1] Add test scripts for "Create Strategy" (status 201, required fields, extract strategy_id) in postman/trading-strategy-api.postman_collection.json
- [X] T011 [P] [US1] Add example response for "Create Strategy" (201 Created with strategy data) in postman/trading-strategy-api.postman_collection.json
- [X] T012 [P] [US1] Add "Get Strategy by ID" GET request with {{strategy_id}} variable to Strategy Management folder in postman/trading-strategy-api.postman_collection.json
- [X] T013 [P] [US1] Add test scripts for "Get Strategy by ID" (status 200, strategy data fields) in postman/trading-strategy-api.postman_collection.json
- [X] T014 [P] [US1] Add example response for "Get Strategy by ID" (200 OK with full strategy details) in postman/trading-strategy-api.postman_collection.json
- [X] T015 [P] [US1] Add "Update Strategy" PATCH request with {{strategy_id}} variable and update example body to Strategy Management folder in postman/trading-strategy-api.postman_collection.json
- [X] T016 [P] [US1] Add test scripts for "Update Strategy" (status 200, updated_at field) in postman/trading-strategy-api.postman_collection.json
- [X] T017 [P] [US1] Add example response for "Update Strategy" (200 OK with updated strategy) in postman/trading-strategy-api.postman_collection.json
- [X] T018 [P] [US1] Add "Delete Strategy" DELETE request with {{strategy_id}} variable to Strategy Management folder in postman/trading-strategy-api.postman_collection.json
- [X] T019 [P] [US1] Add test scripts for "Delete Strategy" (status 204) in postman/trading-strategy-api.postman_collection.json
- [X] T020 [P] [US1] Add example response for "Delete Strategy" (204 No Content) in postman/trading-strategy-api.postman_collection.json

**Checkpoint**: At this point, User Story 1 should be fully functional - all 5 strategy management endpoints testable independently

---

## Phase 4: User Story 2 - Test Backtest Execution Endpoints (Priority: P2)

**Goal**: Enable developers to test backtest operations (create, monitor progress, get results, validate data)

**Independent Test**: Import collection → Create strategy via US1 → Execute all Backtest Management folder requests → Verify backtest lifecycle works end-to-end

### Implementation for User Story 2

- [X] T021 [P] [US2] Add "Create Backtest" POST request with {{strategy_id}} and semi-realistic config to Backtest Management folder in postman/trading-strategy-api.postman_collection.json
- [X] T022 [P] [US2] Add test scripts for "Create Backtest" (status 201, backtest_id, status=running, extract backtest_id) in postman/trading-strategy-api.postman_collection.json
- [X] T023 [P] [US2] Add example response for "Create Backtest" (201 Created with backtest_id and status) in postman/trading-strategy-api.postman_collection.json
- [X] T024 [P] [US2] Add "List Backtests" GET request to Backtest Management folder in postman/trading-strategy-api.postman_collection.json
- [X] T025 [P] [US2] Add test scripts for "List Backtests" (status 200, data array) in postman/trading-strategy-api.postman_collection.json
- [X] T026 [P] [US2] Add example response for "List Backtests" (200 OK with backtests array) in postman/trading-strategy-api.postman_collection.json
- [X] T027 [P] [US2] Add "Get Backtest Results" GET request with {{backtest_id}} to Backtest Management folder in postman/trading-strategy-api.postman_collection.json
- [X] T028 [P] [US2] Add test scripts for "Get Backtest Results" (status 200, performance_metrics, trades array) in postman/trading-strategy-api.postman_collection.json
- [X] T029 [P] [US2] Add example response for "Get Backtest Results" (200 OK with full results) in postman/trading-strategy-api.postman_collection.json
- [X] T030 [P] [US2] Add "Get Backtest Progress" GET request with {{backtest_id}} to Backtest Management folder in postman/trading-strategy-api.postman_collection.json
- [X] T031 [P] [US2] Add test scripts for "Get Backtest Progress" (status 200, progress_percentage 0-100) in postman/trading-strategy-api.postman_collection.json
- [X] T032 [P] [US2] Add example response for "Get Backtest Progress" (200 OK with progress data) in postman/trading-strategy-api.postman_collection.json
- [X] T033 [P] [US2] Add "Cancel Backtest" DELETE request with {{backtest_id}} to Backtest Management folder in postman/trading-strategy-api.postman_collection.json
- [X] T034 [P] [US2] Add test scripts for "Cancel Backtest" (status 204) in postman/trading-strategy-api.postman_collection.json
- [X] T035 [P] [US2] Add example response for "Cancel Backtest" (204 No Content) in postman/trading-strategy-api.postman_collection.json
- [X] T036 [P] [US2] Add "Validate Historical Data" POST request with data validation params to Backtest Management folder in postman/trading-strategy-api.postman_collection.json
- [X] T037 [P] [US2] Add test scripts for "Validate Historical Data" (status 200, quality metrics, warnings array) in postman/trading-strategy-api.postman_collection.json
- [X] T038 [P] [US2] Add example response for "Validate Historical Data" (200 OK with validation results) in postman/trading-strategy-api.postman_collection.json

**Checkpoint**: At this point, User Stories 1 AND 2 should both work independently - full backtest workflow testable

---

## Phase 5: User Story 3 - Test Paper Trading Session Management (Priority: P3)

**Goal**: Enable developers to test paper trading operations (sessions, pause/resume, trade history, metrics)

**Independent Test**: Import collection → Create strategy via US1 → Execute all Paper Trading folder requests → Verify paper trading lifecycle works

### Implementation for User Story 3

- [X] T039 [P] [US3] Add "Create Session" POST request with {{strategy_id}} and paper trading config to Paper Trading folder in postman/trading-strategy-api.postman_collection.json
- [X] T040 [P] [US3] Add test scripts for "Create Session" (status 201, session_id, extract paper_session_id) in postman/trading-strategy-api.postman_collection.json
- [X] T041 [P] [US3] Add example response for "Create Session" (201 Created with session data) in postman/trading-strategy-api.postman_collection.json
- [X] T042 [P] [US3] Add "List Sessions" GET request to Paper Trading folder in postman/trading-strategy-api.postman_collection.json
- [X] T043 [P] [US3] Add test scripts for "List Sessions" (status 200, data array) in postman/trading-strategy-api.postman_collection.json
- [X] T044 [P] [US3] Add example response for "List Sessions" (200 OK with sessions array) in postman/trading-strategy-api.postman_collection.json
- [X] T045 [P] [US3] Add "Get Session Status" GET request with {{paper_session_id}} to Paper Trading folder in postman/trading-strategy-api.postman_collection.json
- [X] T046 [P] [US3] Add test scripts for "Get Session Status" (status 200, equity, pnl, open_positions array) in postman/trading-strategy-api.postman_collection.json
- [X] T047 [P] [US3] Add example response for "Get Session Status" (200 OK with session status) in postman/trading-strategy-api.postman_collection.json
- [X] T048 [P] [US3] Add "Stop Session" DELETE request with {{paper_session_id}} to Paper Trading folder in postman/trading-strategy-api.postman_collection.json
- [X] T049 [P] [US3] Add test scripts for "Stop Session" (status 204) in postman/trading-strategy-api.postman_collection.json
- [X] T050 [P] [US3] Add example response for "Stop Session" (204 No Content) in postman/trading-strategy-api.postman_collection.json
- [X] T051 [P] [US3] Add "Pause Session" POST request with {{paper_session_id}} to Paper Trading folder in postman/trading-strategy-api.postman_collection.json
- [X] T052 [P] [US3] Add test scripts for "Pause Session" (status 200, message, status=paused) in postman/trading-strategy-api.postman_collection.json
- [X] T053 [P] [US3] Add example response for "Pause Session" (200 OK with confirmation) in postman/trading-strategy-api.postman_collection.json
- [X] T054 [P] [US3] Add "Resume Session" POST request with {{paper_session_id}} to Paper Trading folder in postman/trading-strategy-api.postman_collection.json
- [X] T055 [P] [US3] Add test scripts for "Resume Session" (status 200, message, status=active) in postman/trading-strategy-api.postman_collection.json
- [X] T056 [P] [US3] Add example response for "Resume Session" (200 OK with confirmation) in postman/trading-strategy-api.postman_collection.json
- [X] T057 [P] [US3] Add "Get Trade History" GET request with {{paper_session_id}} to Paper Trading folder in postman/trading-strategy-api.postman_collection.json
- [X] T058 [P] [US3] Add test scripts for "Get Trade History" (status 200, trades array with required fields) in postman/trading-strategy-api.postman_collection.json
- [X] T059 [P] [US3] Add example response for "Get Trade History" (200 OK with trades data) in postman/trading-strategy-api.postman_collection.json
- [X] T060 [P] [US3] Add "Get Performance Metrics" GET request with {{paper_session_id}} to Paper Trading folder in postman/trading-strategy-api.postman_collection.json
- [X] T061 [P] [US3] Add test scripts for "Get Performance Metrics" (status 200, win_rate, total_pnl, sharpe_ratio) in postman/trading-strategy-api.postman_collection.json
- [X] T062 [P] [US3] Add example response for "Get Performance Metrics" (200 OK with metrics data) in postman/trading-strategy-api.postman_collection.json

**Checkpoint**: At this point, User Stories 1, 2, AND 3 should all work independently - full paper trading workflow testable

---

## Phase 6: User Story 4 - Test Live Trading Operations (Priority: P4)

**Goal**: Enable developers to test live trading endpoints (sessions, orders, emergency stop) with proper safeguards

**Independent Test**: Import collection → Create strategy via US1 → Execute all Live Trading folder requests (with testnet credentials) → Verify live trading workflow works

### Implementation for User Story 4

- [X] T063 [P] [US4] Add "Create Session" POST request with {{strategy_id}}, testnet config, and risk limits to Live Trading folder in postman/trading-strategy-api.postman_collection.json
- [X] T064 [P] [US4] Add test scripts for "Create Session" (status 201, session_id, extract live_session_id) in postman/trading-strategy-api.postman_collection.json
- [X] T065 [P] [US4] Add example response for "Create Session" (201 Created with session data) in postman/trading-strategy-api.postman_collection.json
- [X] T066 [P] [US4] Add "List Sessions" GET request to Live Trading folder in postman/trading-strategy-api.postman_collection.json
- [X] T067 [P] [US4] Add test scripts for "List Sessions" (status 200, data array) in postman/trading-strategy-api.postman_collection.json
- [X] T068 [P] [US4] Add example response for "List Sessions" (200 OK with sessions array) in postman/trading-strategy-api.postman_collection.json
- [X] T069 [P] [US4] Add "Get Session Status" GET request with {{live_session_id}} to Live Trading folder in postman/trading-strategy-api.postman_collection.json
- [X] T070 [P] [US4] Add test scripts for "Get Session Status" (status 200, risk_limits_status, connectivity_status) in postman/trading-strategy-api.postman_collection.json
- [X] T071 [P] [US4] Add example response for "Get Session Status" (200 OK with full session status) in postman/trading-strategy-api.postman_collection.json
- [X] T072 [P] [US4] Add "Stop Session" DELETE request with {{live_session_id}} to Live Trading folder in postman/trading-strategy-api.postman_collection.json
- [X] T073 [P] [US4] Add test scripts for "Stop Session" (status 204) in postman/trading-strategy-api.postman_collection.json
- [X] T074 [P] [US4] Add example response for "Stop Session" (204 No Content) in postman/trading-strategy-api.postman_collection.json
- [X] T075 [P] [US4] Add "Pause Session" POST request with {{live_session_id}} to Live Trading folder in postman/trading-strategy-api.postman_collection.json
- [X] T076 [P] [US4] Add test scripts for "Pause Session" (status 200, message, status=paused) in postman/trading-strategy-api.postman_collection.json
- [X] T077 [P] [US4] Add example response for "Pause Session" (200 OK with confirmation) in postman/trading-strategy-api.postman_collection.json
- [X] T078 [P] [US4] Add "Resume Session" POST request with {{live_session_id}} to Live Trading folder in postman/trading-strategy-api.postman_collection.json
- [X] T079 [P] [US4] Add test scripts for "Resume Session" (status 200, message, status=active) in postman/trading-strategy-api.postman_collection.json
- [X] T080 [P] [US4] Add example response for "Resume Session" (200 OK with confirmation) in postman/trading-strategy-api.postman_collection.json
- [X] T081 [P] [US4] Add "Emergency Stop" POST request with {{live_session_id}} to Live Trading folder in postman/trading-strategy-api.postman_collection.json
- [X] T082 [P] [US4] Add test scripts for "Emergency Stop" (status 200, cancelled_orders count, duration_ms) in postman/trading-strategy-api.postman_collection.json
- [X] T083 [P] [US4] Add example response for "Emergency Stop" (200 OK with emergency stop results) in postman/trading-strategy-api.postman_collection.json
- [X] T084 [P] [US4] Add "Place Order" POST request with {{live_session_id}} and order params to Live Trading folder in postman/trading-strategy-api.postman_collection.json
- [X] T085 [P] [US4] Add test scripts for "Place Order" (status 201, order_id, extract order_id) in postman/trading-strategy-api.postman_collection.json
- [X] T086 [P] [US4] Add example response for "Place Order" (201 Created with order confirmation) in postman/trading-strategy-api.postman_collection.json
- [X] T087 [P] [US4] Add "Get Order Status" GET request with {{live_session_id}} and {{order_id}} to Live Trading folder in postman/trading-strategy-api.postman_collection.json
- [X] T088 [P] [US4] Add test scripts for "Get Order Status" (status 200, order fields, exchange_order_id) in postman/trading-strategy-api.postman_collection.json
- [X] T089 [P] [US4] Add example response for "Get Order Status" (200 OK with order status) in postman/trading-strategy-api.postman_collection.json
- [X] T090 [P] [US4] Add "Cancel Order" DELETE request with {{live_session_id}} and {{order_id}} to Live Trading folder in postman/trading-strategy-api.postman_collection.json
- [X] T091 [P] [US4] Add test scripts for "Cancel Order" (status 204) in postman/trading-strategy-api.postman_collection.json
- [X] T092 [P] [US4] Add example response for "Cancel Order" (204 No Content) in postman/trading-strategy-api.postman_collection.json

**Checkpoint**: All user stories should now be independently functional - complete API collection ready for use

---

## Phase 7: Polish & Documentation

**Purpose**: Finalize collection and add optional supporting artifacts

- [X] T093 Validate collection JSON against Postman Collection v2.1 schema contract in contracts/collection-schema.json
- [X] T094 Verify all 29 requests are present across 4 folders (5 Strategy + 6 Backtest + 8 Paper + 10 Live)
- [X] T095 Verify all requests include test scripts per contracts/test-script-requirements.md
- [X] T096 Verify all requests include example responses
- [X] T097 Verify all POST/PATCH requests include Content-Type: application/json headers
- [X] T098 [P] Create optional environment file postman/localhost-dev.postman_environment.json
- [X] T099 [P] Add collection description with usage instructions in postman/trading-strategy-api.postman_collection.json
- [X] T100 Test collection import and execution per quickstart.md validation steps (automated validation passed, manual testing checklist created)

---

## Dependencies & Execution Order

### Phase Dependencies

- **Setup (Phase 1)**: No dependencies - can start immediately
- **Foundational (Phase 2)**: Depends on Setup (Phase 1) - BLOCKS all user stories
- **User Stories (Phase 3-6)**: All depend on Foundational phase completion
  - User stories can proceed in parallel (different folders in same JSON file - merge conflicts possible)
  - Or sequentially in priority order (P1 → P2 → P3 → P4) - RECOMMENDED
- **Polish (Phase 7)**: Depends on all user stories being complete

### User Story Dependencies

- **User Story 1 (P1)**: Can start after Foundational (Phase 2) - No dependencies on other stories
- **User Story 2 (P2)**: Can start after Foundational (Phase 2) - Uses {{strategy_id}} from US1 in examples but testable independently
- **User Story 3 (P3)**: Can start after Foundational (Phase 2) - Uses {{strategy_id}} from US1 in examples but testable independently
- **User Story 4 (P4)**: Can start after Foundational (Phase 2) - Uses {{strategy_id}} from US1 in examples but testable independently

### Within Each User Story

All tasks within a user story are marked [P] and can technically run in parallel since they're adding different requests to the collection JSON. However, editing the same JSON file in parallel creates merge conflicts, so **sequential execution within each story is recommended**.

### Parallel Opportunities

- All Setup tasks can run in parallel (different operations)
- All Foundational tasks can run in parallel if using JSON editing tools with merge support
- User stories can be worked on in parallel by different team members using Git branches and merging
- Polish tasks T093-T097 can run in parallel (different validation checks)
- Polish tasks T098-T100 can run in parallel (different files/operations)

---

## Parallel Example: User Story 1 (Theoretical - Sequential Recommended)

```bash
# These CAN run in parallel if using proper JSON merge tools:
Task: "Add List Strategies request to Strategy Management folder"
Task: "Add Create Strategy request to Strategy Management folder"
Task: "Add Get Strategy by ID request to Strategy Management folder"
Task: "Add Update Strategy request to Strategy Management folder"
Task: "Add Delete Strategy request to Strategy Management folder"

# In practice, sequential execution is safer to avoid JSON merge conflicts
```

---

## Implementation Strategy

### MVP First (User Story 1 Only)

1. Complete Phase 1: Setup
2. Complete Phase 2: Foundational (CRITICAL - blocks all stories)
3. Complete Phase 3: User Story 1 (5 strategy endpoints)
4. Complete Phase 7: Polish (validation)
5. **STOP and VALIDATE**: Test User Story 1 independently per quickstart.md
6. Deliverable: Minimal working collection with strategy management testing capability

### Incremental Delivery

1. Complete Setup + Foundational → Collection skeleton ready
2. Add User Story 1 → Test independently → **Deliverable: Strategy management testing**
3. Add User Story 2 → Test independently → **Deliverable: Backtest testing**
4. Add User Story 3 → Test independently → **Deliverable: Paper trading testing**
5. Add User Story 4 → Test independently → **Deliverable: Full API testing coverage**
6. Add Polish → Validate → **Deliverable: Production-ready collection**

### Sequential Team Strategy (Recommended)

One developer working sequentially:

1. Complete Setup + Foundational (base structure)
2. Complete User Story 1 (5 requests) → Validate
3. Complete User Story 2 (6 requests) → Validate
4. Complete User Story 3 (8 requests) → Validate
5. Complete User Story 4 (9 requests) → Validate
6. Complete Polish → Final validation

**Rationale**: All tasks edit the same JSON file - parallel work creates merge conflicts

---

## Summary Statistics

- **Total Tasks**: 100
- **Total Requests**: 28 (5 + 6 + 8 + 9)
- **Tasks per User Story**:
  - US1 (Strategy Management): 15 tasks → 5 requests
  - US2 (Backtest Management): 18 tasks → 6 requests
  - US3 (Paper Trading): 24 tasks → 8 requests
  - US4 (Live Trading): 30 tasks → 9 requests
- **Setup & Foundational**: 5 tasks
- **Polish**: 8 tasks
- **Parallel Opportunities**: Limited (same file edits) - sequential execution recommended
- **Independent Test Criteria**: Each user story validates full workflow for its functional area
- **MVP Scope**: User Story 1 only (Strategy Management - 5 endpoints)

---

## Notes

- [P] tasks = theoretically parallelizable but sequential execution recommended due to single JSON file
- [Story] label maps task to specific user story for traceability
- Each user story should be independently testable after completion
- All requests use Postman Collection v2.1 format per research.md decisions
- All test scripts follow contracts/test-script-requirements.md specifications
- All request/response schemas follow data-model.md specifications
- Collection focuses on happy-path testing only per spec.md FR-013
- No authentication required per spec.md FR-014
- Commit after completing each user story phase for safety
- Validate collection structure against contracts/collection-schema.json before finalizing
