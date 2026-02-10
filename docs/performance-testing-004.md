# Performance Testing Guide: Strategy UI (Feature 004)

**Feature**: Strategy Registration and Validation UI
**Date**: 2026-02-09
**Tester**: _______________
**Environment**: [ ] Local Dev [ ] Staging [ ] Production

---

## Success Criteria to Validate

From `specs/004-strategy-ui/spec.md`:

| ID | Criterion | Target | Priority |
|----|-----------|--------|----------|
| SC-001 | Strategy registration completion time | <5 minutes | P1 |
| SC-002 | Real-time validation response time | <1 second | P1 |
| SC-003 | Concurrent user support | 100+ users | P2 |
| SC-004 | Strategy list load time (100+ strategies) | <2 seconds | P2 |
| SC-005 | Syntax test completion (10 indicators) | <3 seconds | P2 |
| SC-006 | Data loss prevention | 0 incidents | P1 |
| SC-007 | Uniqueness validation accuracy | 100% | P1 |
| SC-008 | Version conflict detection accuracy | 100% | P1 |
| SC-009 | User isolation enforcement | 100% | P1 |

---

## Prerequisites

### Load Testing Tools

Install one of the following:

#### Option 1: wrk (Recommended for HTTP load testing)
```bash
# macOS
brew install wrk

# Linux
sudo apt-get install wrk
```

#### Option 2: k6 (Recommended for complex scenarios)
```bash
# macOS
brew install k6

# Linux
wget https://github.com/grafana/k6/releases/download/v0.45.0/k6-v0.45.0-linux-amd64.tar.gz
tar -xzf k6-v0.45.0-linux-amd64.tar.gz
sudo mv k6 /usr/local/bin/
```

#### Option 3: Apache Bench (Simple HTTP benchmarking)
```bash
# Usually pre-installed on macOS/Linux
ab -V
```

### Test Data Setup

```bash
# Start server
mix phx.server

# Create test user and 100+ strategies
mix run priv/repo/seeds_performance.exs
```

**Create `priv/repo/seeds_performance.exs`**:
```elixir
alias TradingStrategy.{Repo, Accounts, Strategies}

# Create test user
{:ok, user} = Accounts.register_user(%{
  email: "perftest@example.com",
  password: "PerformanceTest123!"
})

# Create 150 strategies with varying statuses
for i <- 1..150 do
  status = case rem(i, 4) do
    0 -> "active"
    1 -> "inactive"
    2 -> "archived"
    _ -> "draft"
  end

  {:ok, _strategy} = Strategies.create_strategy(%{
    name: "Performance Test Strategy #{i}",
    description: "Auto-generated for performance testing",
    format: "yaml",
    content: """
    indicators:
      - type: rsi
        name: rsi_14
        parameters:
          period: 14
    entry_conditions: "rsi_14 < 30"
    exit_conditions: "rsi_14 > 70"
    """,
    trading_pair: "BTC/USD",
    timeframe: "1h",
    status: status
  }, user)

  if rem(i, 10) == 0, do: IO.puts("Created #{i} strategies...")
end

IO.puts("✓ Performance test data created successfully!")
```

---

## Test 1: Strategy Registration Completion (SC-001)

**Target**: <5 minutes end-to-end

### Manual Timing Test

1. Start timer
2. Navigate to `/strategies/new`
3. Fill all required fields:
   - Name: "Manual Performance Test"
   - Description: "Testing registration time"
   - Trading Pair: "BTC/USD"
   - Timeframe: "1h"
   - Format: "yaml"
   - Content: (Paste 50-line YAML strategy)
4. Click "Create Strategy"
5. Wait for success confirmation
6. Stop timer

**Result**:
- Time taken: _______ seconds
- **PASS if <300 seconds (5 minutes)**

**Status**: [ ] PASS [ ] FAIL

---

## Test 2: Real-Time Validation Response (SC-002)

**Target**: <1 second (1000ms)

### Browser Performance Measurement

Open DevTools → Network tab:

1. Navigate to `/strategies/new`
2. Enter invalid data in Name field (e.g., "AB" - too short)
3. Tab out of field to trigger blur validation
4. Measure network request time in DevTools

**Alternative: Automated Timing**

```javascript
// Run in browser console
async function testValidation() {
  const start = performance.now();

  // Trigger validation change event
  document.querySelector('#strategy_name').value = 'AB';
  document.querySelector('#strategy_name').dispatchEvent(new Event('blur'));

  // Wait for LiveView response
  await new Promise(resolve => setTimeout(resolve, 2000));

  const end = performance.now();
  console.log(`Validation response time: ${end - start}ms`);
}

testValidation();
```

**Results**:
- Average response time: _______ ms
- **PASS if <1000ms**

**Status**: [ ] PASS [ ] FAIL

---

## Test 3: Concurrent User Support (SC-003)

**Target**: 100+ concurrent users

### Using wrk

```bash
# Test with 100 concurrent connections for 30 seconds
wrk -t10 -c100 -d30s \
  --header "Cookie: _trading_strategy_key=YOUR_SESSION_COOKIE" \
  http://localhost:4000/strategies

# To get session cookie:
# 1. Login via browser
# 2. Open DevTools → Application → Cookies
# 3. Copy _trading_strategy_key value
```

**Expected Results**:
- Requests/sec: >500
- Latency p95: <500ms
- Error rate: <1%

**Actual Results**:
- Requests/sec: _______
- Latency p95: _______ ms
- Error rate: _______ %

**Status**: [ ] PASS [ ] FAIL

### Using k6

**Create `scripts/load-test-strategies.js`**:
```javascript
import http from 'k6/http';
import { check, sleep } from 'k6';

export let options = {
  stages: [
    { duration: '30s', target: 50 },  // Ramp up to 50 users
    { duration: '1m', target: 100 },  // Ramp up to 100 users
    { duration: '30s', target: 100 }, // Stay at 100 users
    { duration: '30s', target: 0 },   // Ramp down to 0
  ],
  thresholds: {
    http_req_duration: ['p(95)<500'], // 95% of requests must complete below 500ms
    http_req_failed: ['rate<0.01'],   // Error rate must be below 1%
  },
};

export default function () {
  const res = http.get('http://localhost:4000/strategies', {
    headers: { 'Cookie': 'YOUR_SESSION_COOKIE' },
  });

  check(res, {
    'status is 200': (r) => r.status === 200,
    'response time < 500ms': (r) => r.timings.duration < 500,
  });

  sleep(1);
}
```

Run test:
```bash
k6 run scripts/load-test-strategies.js
```

**Status**: [ ] PASS [ ] FAIL

---

## Test 4: Strategy List Load Time (SC-004)

**Target**: <2 seconds for 100+ strategies

### Browser Performance API

```javascript
// Run in browser console on /strategies page
performance.mark('start');
location.reload();

// After page loads, run:
performance.mark('end');
performance.measure('pageLoad', 'start', 'end');
const measure = performance.getEntriesByName('pageLoad')[0];
console.log(`Page load time: ${measure.duration}ms`);
```

### Automated Test with wrk

```bash
wrk -t4 -c10 -d10s \
  --header "Cookie: _trading_strategy_key=YOUR_SESSION_COOKIE" \
  http://localhost:4000/strategies
```

**Results**:
- Page load time (browser): _______ ms
- Average response time (wrk): _______ ms
- **PASS if <2000ms**

**Status**: [ ] PASS [ ] FAIL

---

## Test 5: Syntax Test Completion (SC-005)

**Target**: <3 seconds for 10 indicators

### Test Strategy with 10 Indicators

**Create `test_strategy_10_indicators.yaml`**:
```yaml
indicators:
  - type: rsi
    name: rsi_14
    parameters:
      period: 14
  - type: sma
    name: sma_50
    parameters:
      period: 50
  - type: ema
    name: ema_20
    parameters:
      period: 20
  - type: macd
    name: macd
    parameters:
      fast_period: 12
      slow_period: 26
      signal_period: 9
  - type: bollinger_bands
    name: bb
    parameters:
      period: 20
      std_dev: 2
  - type: atr
    name: atr_14
    parameters:
      period: 14
  - type: stochastic
    name: stoch
    parameters:
      k_period: 14
      d_period: 3
  - type: volume_sma
    name: vol_sma
    parameters:
      period: 20
  - type: rsi
    name: rsi_7
    parameters:
      period: 7
  - type: sma
    name: sma_200
    parameters:
      period: 200

entry_conditions: "rsi_14 < 30 AND sma_50 > sma_200"
exit_conditions: "rsi_14 > 70"
```

### Manual Timing Test

1. Navigate to `/strategies/new`
2. Paste YAML content above
3. Start timer
4. Click "Test Syntax" button
5. Wait for result
6. Stop timer

**Result**:
- Time taken: _______ seconds
- **PASS if <3 seconds**

**Status**: [ ] PASS [ ] FAIL

### API Test (if syntax test exposed as API)

```bash
time curl -X POST http://localhost:4000/api/strategies/test_syntax \
  -H "Content-Type: application/json" \
  -H "Cookie: YOUR_SESSION_COOKIE" \
  -d @test_strategy_10_indicators.json
```

---

## Test 6: Data Loss Prevention (SC-006)

**Target**: 0 data loss incidents

### Autosave Test

1. Navigate to `/strategies/new`
2. Fill in Name: "Autosave Test"
3. Fill in other fields partially
4. Wait 35 seconds (autosave interval + buffer)
5. **Simulate crash**: Close browser tab WITHOUT saving
6. Reopen `/strategies/new`
7. **Expected**: Form data recovered OR draft strategy exists

**Result**: [ ] PASS (data recovered) [ ] FAIL (data lost)

### Network Interruption Test

1. Start filling form
2. Disable network connection (airplane mode)
3. Continue filling form
4. Re-enable network
5. Click "Save"
6. **Expected**: Save succeeds with queued changes

**Result**: [ ] PASS [ ] FAIL

**Status**: [ ] PASS [ ] FAIL

---

## Test 7-9: Functional Accuracy (SC-007, SC-008, SC-009)

These are validated through functional tests, not performance tests.

- **SC-007**: Uniqueness validation → See security-audit-004.md
- **SC-008**: Version conflict detection → See manual-testing-checklist-004.md
- **SC-009**: User isolation → See security-audit-004.md

---

## Database Performance Tests

### Query Performance

```sql
-- Test strategy list query performance
EXPLAIN ANALYZE
SELECT * FROM strategies
WHERE user_id = 'test-user-id'
ORDER BY inserted_at DESC
LIMIT 50;

-- Expected: Index scan on strategies_user_id_idx
-- Execution time: <50ms

-- Test strategy detail query
EXPLAIN ANALYZE
SELECT * FROM strategies
WHERE id = 'test-strategy-id' AND user_id = 'test-user-id';

-- Expected: Index scan on primary key + user_id check
-- Execution time: <10ms
```

**Results**:
- List query time: _______ ms
- Detail query time: _______ ms

**Status**: [ ] PASS [ ] FAIL

---

## Memory & CPU Usage Tests

### Memory Profiling

```bash
# Monitor server memory during load test
ps aux | grep beam
# Note RSS (memory) before and after load test

# Before test
RSS before: _______ MB

# Run load test (Test 3)

# After test
RSS after: _______ MB
RSS increase: _______ MB

# Expected: <500MB increase for 100 concurrent users
```

**Status**: [ ] PASS [ ] FAIL

### CPU Usage

```bash
# Monitor CPU during load test
top -pid $(pgrep beam)

# Peak CPU usage: _______ %
# Average CPU usage: _______ %

# Expected: <80% on single core
```

**Status**: [ ] PASS [ ] FAIL

---

## LiveView Performance

### Channel Latency

Open browser DevTools → Network → WS tab:

1. Navigate to `/strategies/new`
2. Monitor WebSocket messages
3. Type in form field
4. Measure time between client message and server response

**Results**:
- Average WebSocket round-trip: _______ ms
- **PASS if <100ms**

**Status**: [ ] PASS [ ] FAIL

---

## Summary

| Test | Target | Result | Status |
|------|--------|--------|--------|
| SC-001: Registration time | <5 min | _____ s | [ ] PASS [ ] FAIL |
| SC-002: Validation response | <1 sec | _____ ms | [ ] PASS [ ] FAIL |
| SC-003: Concurrent users | 100+ | _____ | [ ] PASS [ ] FAIL |
| SC-004: List load time | <2 sec | _____ ms | [ ] PASS [ ] FAIL |
| SC-005: Syntax test | <3 sec | _____ s | [ ] PASS [ ] FAIL |
| SC-006: Data loss | 0 incidents | _____ | [ ] PASS [ ] FAIL |
| Database queries | <50ms | _____ ms | [ ] PASS [ ] FAIL |
| Memory usage | <500MB increase | _____ MB | [ ] PASS [ ] FAIL |
| CPU usage | <80% | _____ % | [ ] PASS [ ] FAIL |

**Overall Performance**: [ ] ACCEPTABLE [ ] NEEDS OPTIMIZATION [ ] CRITICAL ISSUES

**Bottlenecks Identified**:
________________________________________________
________________________________________________

**Optimization Recommendations**:
________________________________________________
________________________________________________

**Sign-off**:
- [ ] All success criteria met
- [ ] Performance acceptable for production load
- [ ] No critical bottlenecks identified

**Tester Signature**: _______________ **Date**: ___________
