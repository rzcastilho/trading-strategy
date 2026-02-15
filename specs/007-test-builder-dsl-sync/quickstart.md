# Quickstart: Strategy Editor Synchronization Test Suite

**Feature**: 007-test-builder-dsl-sync
**Date**: 2026-02-11
**Audience**: Developers, QA Engineers, CI/CD Maintainers

## Overview

This guide provides quick commands and examples for running the comprehensive test suite that validates the bidirectional synchronization between the visual strategy builder and DSL editor (Feature 005).

---

## Prerequisites

- **Elixir**: 1.17+ (OTP 27+)
- **PostgreSQL**: Running instance with test database
- **Dependencies**: `mix deps.get` completed
- **Database**: Test database migrated (`MIX_ENV=test mix ecto.setup`)

---

## Quick Commands

### Run All Tests

```bash
# Run entire test suite (excludes benchmarks by default)
mix test test/trading_strategy_web/live/strategy_editor_live/
```

**Expected Output**:
```
.....................

Finished in 45.3 seconds (0.1s async, 45.2s sync)
52 tests, 0 failures
```

---

### Run Tests by User Story

```bash
# P1: Builder-to-DSL Synchronization (US1)
mix test test/trading_strategy_web/live/strategy_editor_live/synchronization_test.exs

# P1: DSL-to-Builder Synchronization (US2)
mix test test/trading_strategy_web/live/strategy_editor_live/dsl_to_builder_sync_test.exs

# P2: Comment Preservation (US3)
mix test test/trading_strategy_web/live/strategy_editor_live/comment_preservation_test.exs

# P2: Undo/Redo Functionality (US4)
mix test test/trading_strategy_web/live/strategy_editor_live/undo_redo_test.exs

# P3: Performance Validation (US5)
mix test test/trading_strategy_web/live/strategy_editor_live/performance_test.exs

# P3: Error Handling (US6)
mix test test/trading_strategy_web/live/strategy_editor_live/error_handling_test.exs

# Edge Cases
mix test test/trading_strategy_web/live/strategy_editor_live/edge_cases_test.exs
```

---

### Run Performance Benchmarks

```bash
# Run performance tests with detailed metrics (tagged with :benchmark)
BENCHMARK=true mix test --only benchmark test/trading_strategy_web/live/strategy_editor_live/

# Or run specific benchmark test
mix test --only benchmark:true test/trading_strategy_web/live/strategy_editor_live/performance_test.exs
```

**Expected Output**:
```
=== SC-003: Synchronization Performance ===
Samples: 100
Mean: 312.5ms
Median: 289.0ms
P95: 432.1ms
Max: 498.3ms
Success rate: 97.0%
Over threshold: 3/100
Target: P95 < 500ms

✓ Test passed
```

---

### Run Wallaby Browser Tests

```bash
# Run Wallaby tests (visual feedback, keyboard shortcuts)
mix test --only wallaby test/trading_strategy_web/live/strategy_editor_live/
```

**Note**: Wallaby tests require Chrome/Chromium installed. Set `CHROMEDRIVER_PATH` if not in PATH.

---

### Run Specific Test by ID

```bash
# Run specific test scenario (e.g., US1.001)
mix test test/trading_strategy_web/live/strategy_editor_live/synchronization_test.exs:23
```

---

### Verify 0% Flakiness (SC-011)

```bash
# Run tests 10 times consecutively to verify determinism
for i in {1..10}; do
  echo "=== Run $i/10 ==="
  mix test test/trading_strategy_web/live/strategy_editor_live/ || exit 1
done

echo "✅ 0% flakiness achieved!"
```

---

## Test Organization

### File Structure

```
test/trading_strategy_web/live/strategy_editor_live/
├── synchronization_test.exs           # US1: Builder-to-DSL sync (10 tests)
├── dsl_to_builder_sync_test.exs      # US2: DSL-to-builder sync (10 tests)
├── comment_preservation_test.exs      # US3: Comment preservation (8 tests)
├── undo_redo_test.exs                # US4: Undo/redo (8 tests)
├── performance_test.exs              # US5: Performance validation (10 tests)
├── error_handling_test.exs           # US6: Error handling (6 tests)
└── edge_cases_test.exs               # Cross-cutting edge cases
```

### Test Fixtures

```
test/support/fixtures/
├── strategy_fixtures.ex              # Fixture builder functions
└── data/
    ├── simple/                       # 1-2 indicators
    ├── medium/                       # 5-10 indicators
    ├── complex/                      # 20-30 indicators
    └── large/                        # 50+ indicators, 1000+ lines
```

---

## Example Test Scenarios

### US1.001: Builder-to-DSL Synchronization

**Acceptance Criteria**: Adding indicator in builder updates DSL within 500ms

```bash
mix test test/trading_strategy_web/live/strategy_editor_live/synchronization_test.exs:23
```

**What it tests**:
- ✅ Indicator added via builder form
- ✅ DSL editor updates with correct syntax
- ✅ Synchronization completes within 500ms target (FR-001)

---

### US3.003: Comment Preservation Across Round-Trips

**Acceptance Criteria**: 90%+ comments preserved after 10 round-trip edits

```bash
mix test test/trading_strategy_web/live/strategy_editor_live/comment_preservation_test.exs:67
```

**What it tests**:
- ✅ DSL with 20 comment lines
- ✅ 10 round-trip synchronizations (5 builder, 5 DSL changes)
- ✅ At least 18 comment lines (90%) remain intact (SC-004)

---

### US4.001: Undo Operation Performance

**Acceptance Criteria**: Undo completes within 50ms and updates both editors

```bash
mix test test/trading_strategy_web/live/strategy_editor_live/undo_redo_test.exs:12
```

**What it tests**:
- ✅ Make changes in builder
- ✅ Trigger undo via Ctrl+Z keyboard shortcut
- ✅ Both editors revert to previous state
- ✅ Operation completes within 50ms (SC-005)

---

### US5.001: Large Strategy Performance

**Acceptance Criteria**: 20-indicator strategy syncs within 500ms

```bash
mix test --only benchmark test/trading_strategy_web/live/strategy_editor_live/performance_test.exs:18
```

**What it tests**:
- ✅ Strategy with 20 configured indicators (complex fixture)
- ✅ Builder-to-DSL synchronization
- ✅ Latency within 500ms target (SC-001, FR-012)

---

## Interpreting Test Results

### Success Criteria Mapping

| Test Suite | Success Criteria | Target | Command |
|------------|------------------|--------|---------|
| US1 (synchronization_test.exs) | SC-001 | 100% pass | `mix test ...synchronization_test.exs` |
| US2 (dsl_to_builder_sync_test.exs) | SC-002 | 100% pass | `mix test ...dsl_to_builder_sync_test.exs` |
| US3 (comment_preservation_test.exs) | SC-004 | 90%+ retention | `mix test ...comment_preservation_test.exs` |
| US4 (undo_redo_test.exs) | SC-005 | <50ms response | `mix test ...undo_redo_test.exs` |
| US5 (performance_test.exs) | SC-003, SC-009 | <500ms P95 | `mix test --only benchmark ...performance_test.exs` |
| US6 (error_handling_test.exs) | SC-006 | 0 data loss | `mix test ...error_handling_test.exs` |
| All (10x runs) | SC-011 | 0% flakiness | `for i in {1..10}; do mix test ...; done` |

---

### Console Output Example

```
============================================================
Test Suite: Strategy Editor Synchronization
============================================================

Summary:
  Total Tests: 52
  Passed:      52 (100%)
  Failed:       0 (0%)
  Skipped:      0
  Duration:    45.3 seconds

Results by User Story:
  [P1] US1: Builder-to-DSL Sync         10/10 ✓
  [P1] US2: DSL-to-Builder Sync         10/10 ✓
  [P2] US3: Comment Preservation         8/8  ✓
  [P2] US4: Undo/Redo                    8/8  ✓
  [P3] US5: Performance Validation      10/10 ✓
  [P3] US6: Error Handling               6/6  ✓

Performance Metrics:
  Sync Latency (P95):           432.1ms  (Target: <500ms) ✓
  Undo/Redo Latency (Max):       38.6ms  (Target: <50ms)  ✓
  Comment Preservation Rate:     92.4%   (Target: >90%)   ✓

============================================================
```

---

## Troubleshooting

### Database Connection Errors

**Error**: `** (DBConnection.OwnershipError)`

**Solution**:
```bash
# Ensure test database is running and migrated
MIX_ENV=test mix ecto.reset
MIX_ENV=test mix ecto.migrate
```

---

### Wallaby ChromeDriver Errors

**Error**: `Could not start ChromeDriver`

**Solution**:
```bash
# Install ChromeDriver (macOS)
brew install chromedriver

# Or set path explicitly
export CHROMEDRIVER_PATH=/usr/local/bin/chromedriver

# Verify installation
chromedriver --version
```

---

### Performance Test Failures

**Error**: `P95 latency 523.4ms exceeds 500ms target`

**Possible Causes**:
- System under heavy load (close other applications)
- Database not optimized (run `ANALYZE` on test database)
- GC pressure (increase BEAM heap size: `ERL_FLAGS="+hmax 2097152" mix test`)

**Run in isolated environment**:
```bash
# Run benchmarks sequentially with reduced concurrency
BENCHMARK=true mix test --max-cases 1 --only benchmark
```

---

### Flaky Tests

**Error**: Tests pass individually but fail when run together

**Solution**:
```bash
# Check for shared state issues
mix test --seed 0 --trace test/trading_strategy_web/live/strategy_editor_live/

# Verify test isolation
mix test --only integration --max-cases 1
```

**Common causes**:
- Shared EditHistory session IDs (should use `Ecto.UUID.generate()` per test)
- Database state leakage (verify Ecto Sandbox is enabled)
- ETS table pollution (verify cleanup in `on_exit` callbacks)

---

## CI/CD Integration

### GitHub Actions Example

```yaml
# .github/workflows/test-strategy-editor.yml
name: Strategy Editor Synchronization Tests

on:
  pull_request:
    paths:
      - 'lib/trading_strategy/strategy_editor/**'
      - 'lib/trading_strategy_web/live/strategy_editor_live.ex'
      - 'test/trading_strategy_web/live/strategy_editor_live/**'

jobs:
  test:
    runs-on: ubuntu-latest

    services:
      postgres:
        image: postgres:15
        env:
          POSTGRES_PASSWORD: postgres
        options: >-
          --health-cmd pg_isready
          --health-interval 10s
          --health-timeout 5s
          --health-retries 5

    steps:
      - uses: actions/checkout@v3
      - uses: erlef/setup-beam@v1
        with:
          elixir-version: '1.17'
          otp-version: '27'

      - name: Install dependencies
        run: mix deps.get

      - name: Setup test database
        env:
          MIX_ENV: test
        run: mix ecto.setup

      - name: Run functional tests
        run: mix test test/trading_strategy_web/live/strategy_editor_live/

      - name: Run performance benchmarks
        env:
          BENCHMARK: true
        run: mix test --only benchmark test/trading_strategy_web/live/strategy_editor_live/

      - name: Verify 0% flakiness (10 runs)
        run: |
          for i in {1..10}; do
            echo "=== Flakiness check $i/10 ==="
            mix test test/trading_strategy_web/live/strategy_editor_live/ || exit 1
          done
```

---

## Next Steps

1. **Read Feature Spec**: `/specs/007-test-builder-dsl-sync/spec.md`
2. **Review Data Model**: `/specs/007-test-builder-dsl-sync/data-model.md`
3. **Check Research**: `/specs/007-test-builder-dsl-sync/research.md`
4. **Run Tests**: `mix test test/trading_strategy_web/live/strategy_editor_live/`
5. **Report Issues**: Create GitHub issue with test output and steps to reproduce

---

## Resources

- **Feature 005 Spec**: `/specs/005-builder-dsl-sync/spec.md` (code being tested)
- **Feature 005 CLAUDE.md**: Manual additions section for architecture patterns
- **ExUnit Documentation**: https://hexdocs.pm/ex_unit/ExUnit.html
- **Wallaby Documentation**: https://hexdocs.pm/wallaby/Wallaby.html
- **Phoenix LiveView Testing**: https://hexdocs.pm/phoenix_live_view/Phoenix.LiveViewTest.html
