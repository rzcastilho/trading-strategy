# Test Script Requirements Contract

**Feature**: 002-postman-api-collection
**Date**: 2026-01-14

## Overview

This document defines the contract requirements for Postman test scripts included in each request. All test scripts must validate responses according to these specifications.

---

## General Test Script Requirements

### 1. Status Code Validation (MANDATORY)
**Requirement**: Every request MUST include a test validating the HTTP status code.

**Pattern**:
```javascript
pm.test("Status code is {expected_code}", function () {
    pm.response.to.have.status({expected_code});
});
```

**Expected Codes by Method**:
- **GET** (retrieval): `200 OK`
- **POST** (creation): `201 Created`
- **PATCH** (update): `200 OK`
- **DELETE** (deletion): `204 No Content`

---

### 2. Response Body Validation (MANDATORY for non-DELETE)
**Requirement**: All non-DELETE requests MUST validate response body structure.

**Pattern for Single Resource (GET by ID, POST, PATCH)**:
```javascript
pm.test("Response contains data field", function () {
    var jsonData = pm.response.json();
    pm.expect(jsonData).to.have.property('data');
});
```

**Pattern for Collections (GET list endpoints)**:
```javascript
pm.test("Response contains data array", function () {
    var jsonData = pm.response.json();
    pm.expect(jsonData).to.have.property('data');
    pm.expect(jsonData.data).to.be.an('array');
});
```

---

### 3. Field Presence and Type Validation (MANDATORY)
**Requirement**: All requests MUST validate presence and type of key response fields.

**Pattern**:
```javascript
pm.test("Response has required fields with correct types", function () {
    var jsonData = pm.response.json();
    pm.expect(jsonData.data).to.have.property('id');
    pm.expect(jsonData.data.id).to.be.a('string'); // UUID as string
    pm.expect(jsonData.data).to.have.property('name');
    pm.expect(jsonData.data.name).to.be.a('string');
    // Add more field validations as needed
});
```

**Type Conventions**:
- `id`, `strategy_id`, `backtest_id`, `session_id`, `order_id`: `string` (UUID)
- `name`, `description`, `trading_pair`, `status`: `string`
- `version`, `trades_count`, `progress_percentage`: `number`
- Decimal values (prices, quantities, pnl): `string` (for precision)
- Arrays (data lists, trades, open_positions): `array`
- Objects (nested structures): `object`
- Booleans (can_open_new_position): `boolean`

---

### 4. Variable Extraction for Chaining (CONDITIONAL)
**Requirement**: Requests that create resources SHOULD extract IDs for use in subsequent requests.

**When to Extract**:
- **Create Strategy** → Extract `strategy_id`
- **Create Backtest** → Extract `backtest_id`
- **Create Paper Trading Session** → Extract `session_id`
- **Create Live Trading Session** → Extract `session_id`
- **Place Order** → Extract `order_id`

**Pattern**:
```javascript
pm.test("Extract ID to environment", function () {
    var jsonData = pm.response.json();
    pm.environment.set("strategy_id", jsonData.data.id);
});
```

**Variable Names**:
| Extracted From | Variable Name | Used In |
|----------------|---------------|---------|
| Create Strategy | `strategy_id` | Update/Delete Strategy, Create Backtest, Create Sessions |
| Create Backtest | `backtest_id` | Get Results, Get Progress, Cancel Backtest |
| Create Paper Session | `paper_session_id` | Paper trading operations |
| Create Live Session | `live_session_id` | Live trading operations, Place Order |
| Place Order | `order_id` | Get Order Status, Cancel Order |

**Note**: Use different variable names for paper vs live sessions to avoid conflicts.

---

## Request-Specific Test Script Requirements

### Strategy Management

#### List Strategies (GET /api/strategies)
```javascript
// Test 1: Status code
pm.test("Status code is 200", function () {
    pm.response.to.have.status(200);
});

// Test 2: Response is array
pm.test("Response contains data array", function () {
    var jsonData = pm.response.json();
    pm.expect(jsonData).to.have.property('data');
    pm.expect(jsonData.data).to.be.an('array');
});

// Test 3: Array items have required fields (if not empty)
pm.test("Array items have required fields", function () {
    var jsonData = pm.response.json();
    if (jsonData.data.length > 0) {
        pm.expect(jsonData.data[0]).to.have.property('id');
        pm.expect(jsonData.data[0]).to.have.property('name');
        pm.expect(jsonData.data[0]).to.have.property('status');
    }
});
```

#### Create Strategy (POST /api/strategies)
```javascript
// Test 1: Status code
pm.test("Status code is 201", function () {
    pm.response.to.have.status(201);
});

// Test 2: Response has data
pm.test("Response contains created strategy", function () {
    var jsonData = pm.response.json();
    pm.expect(jsonData).to.have.property('data');
});

// Test 3: Validate key fields
pm.test("Strategy has required fields", function () {
    var jsonData = pm.response.json();
    pm.expect(jsonData.data).to.have.property('id');
    pm.expect(jsonData.data.id).to.be.a('string');
    pm.expect(jsonData.data).to.have.property('name');
    pm.expect(jsonData.data).to.have.property('format');
    pm.expect(jsonData.data).to.have.property('trading_pair');
    pm.expect(jsonData.data).to.have.property('status');
});

// Test 4: Extract ID
pm.test("Extract strategy_id", function () {
    var jsonData = pm.response.json();
    pm.environment.set("strategy_id", jsonData.data.id);
});
```

#### Get Strategy by ID (GET /api/strategies/:id)
```javascript
pm.test("Status code is 200", function () {
    pm.response.to.have.status(200);
});

pm.test("Response contains strategy data", function () {
    var jsonData = pm.response.json();
    pm.expect(jsonData).to.have.property('data');
    pm.expect(jsonData.data).to.have.property('id');
    pm.expect(jsonData.data).to.have.property('name');
    pm.expect(jsonData.data).to.have.property('content');
});
```

#### Update Strategy (PATCH /api/strategies/:id)
```javascript
pm.test("Status code is 200", function () {
    pm.response.to.have.status(200);
});

pm.test("Response contains updated strategy", function () {
    var jsonData = pm.response.json();
    pm.expect(jsonData).to.have.property('data');
    pm.expect(jsonData.data).to.have.property('updated_at');
});
```

#### Delete Strategy (DELETE /api/strategies/:id)
```javascript
pm.test("Status code is 204", function () {
    pm.response.to.have.status(204);
});
```

---

### Backtest Management

#### Create Backtest (POST /api/backtests)
```javascript
pm.test("Status code is 201", function () {
    pm.response.to.have.status(201);
});

pm.test("Backtest started successfully", function () {
    var jsonData = pm.response.json();
    pm.expect(jsonData).to.have.property('backtest_id');
    pm.expect(jsonData).to.have.property('status');
    pm.expect(jsonData.status).to.equal('running');
});

pm.test("Extract backtest_id", function () {
    var jsonData = pm.response.json();
    pm.environment.set("backtest_id", jsonData.backtest_id);
});
```

#### Get Backtest Progress (GET /api/backtests/:id/progress)
```javascript
pm.test("Status code is 200", function () {
    pm.response.to.have.status(200);
});

pm.test("Progress response has required fields", function () {
    var jsonData = pm.response.json();
    pm.expect(jsonData).to.have.property('backtest_id');
    pm.expect(jsonData).to.have.property('status');
    pm.expect(jsonData).to.have.property('progress_percentage');
    pm.expect(jsonData.progress_percentage).to.be.a('number');
    pm.expect(jsonData.progress_percentage).to.be.at.least(0);
    pm.expect(jsonData.progress_percentage).to.be.at.most(100);
});
```

#### Get Backtest Results (GET /api/backtests/:id)
```javascript
pm.test("Status code is 200", function () {
    pm.response.to.have.status(200);
});

pm.test("Results have performance metrics", function () {
    var jsonData = pm.response.json();
    pm.expect(jsonData).to.have.property('performance_metrics');
    pm.expect(jsonData.performance_metrics).to.have.property('total_return');
    pm.expect(jsonData.performance_metrics).to.have.property('sharpe_ratio');
    pm.expect(jsonData.performance_metrics).to.have.property('max_drawdown');
    pm.expect(jsonData.performance_metrics).to.have.property('win_rate');
});

pm.test("Results have trades array", function () {
    var jsonData = pm.response.json();
    pm.expect(jsonData).to.have.property('trades');
    pm.expect(jsonData.trades).to.be.an('array');
});
```

#### Validate Historical Data (POST /api/backtests/validate-data)
```javascript
pm.test("Status code is 200", function () {
    pm.response.to.have.status(200);
});

pm.test("Validation response has quality metrics", function () {
    var jsonData = pm.response.json();
    pm.expect(jsonData).to.have.property('total_bars_expected');
    pm.expect(jsonData).to.have.property('total_bars_available');
    pm.expect(jsonData).to.have.property('completeness_percentage');
    pm.expect(jsonData).to.have.property('quality_warnings');
    pm.expect(jsonData.quality_warnings).to.be.an('array');
});
```

---

### Paper Trading

#### Create Session (POST /api/paper_trading/sessions)
```javascript
pm.test("Status code is 201", function () {
    pm.response.to.have.status(201);
});

pm.test("Session created successfully", function () {
    var jsonData = pm.response.json();
    pm.expect(jsonData).to.have.property('data');
    pm.expect(jsonData.data).to.have.property('session_id');
});

pm.test("Extract paper_session_id", function () {
    var jsonData = pm.response.json();
    pm.environment.set("paper_session_id", jsonData.data.session_id);
});
```

#### Get Session Status (GET /api/paper_trading/sessions/:id)
```javascript
pm.test("Status code is 200", function () {
    pm.response.to.have.status(200);
});

pm.test("Session status has required fields", function () {
    var jsonData = pm.response.json();
    pm.expect(jsonData.data).to.have.property('session_id');
    pm.expect(jsonData.data).to.have.property('status');
    pm.expect(jsonData.data).to.have.property('current_equity');
    pm.expect(jsonData.data).to.have.property('unrealized_pnl');
    pm.expect(jsonData.data).to.have.property('realized_pnl');
    pm.expect(jsonData.data).to.have.property('open_positions');
    pm.expect(jsonData.data.open_positions).to.be.an('array');
});
```

#### Pause/Resume Session
```javascript
pm.test("Status code is 200", function () {
    pm.response.to.have.status(200);
});

pm.test("Response confirms action", function () {
    var jsonData = pm.response.json();
    pm.expect(jsonData).to.have.property('message');
    pm.expect(jsonData).to.have.property('session_id');
    pm.expect(jsonData).to.have.property('status');
});
```

#### Get Trade History (GET /api/paper_trading/sessions/:id/trades)
```javascript
pm.test("Status code is 200", function () {
    pm.response.to.have.status(200);
});

pm.test("Response contains trades array", function () {
    var jsonData = pm.response.json();
    pm.expect(jsonData).to.have.property('data');
    pm.expect(jsonData.data).to.be.an('array');
});

pm.test("Trades have required fields", function () {
    var jsonData = pm.response.json();
    if (jsonData.data.length > 0) {
        pm.expect(jsonData.data[0]).to.have.property('trade_id');
        pm.expect(jsonData.data[0]).to.have.property('timestamp');
        pm.expect(jsonData.data[0]).to.have.property('side');
        pm.expect(jsonData.data[0]).to.have.property('price');
        pm.expect(jsonData.data[0]).to.have.property('quantity');
    }
});
```

#### Get Performance Metrics (GET /api/paper_trading/sessions/:id/metrics)
```javascript
pm.test("Status code is 200", function () {
    pm.response.to.have.status(200);
});

pm.test("Metrics have required fields", function () {
    var jsonData = pm.response.json();
    pm.expect(jsonData.data).to.have.property('session_id');
    pm.expect(jsonData.data).to.have.property('total_trades');
    pm.expect(jsonData.data).to.have.property('win_rate');
    pm.expect(jsonData.data).to.have.property('total_pnl');
    pm.expect(jsonData.data).to.have.property('sharpe_ratio');
    pm.expect(jsonData.data).to.have.property('max_drawdown_pct');
});
```

---

### Live Trading

#### Create Session (POST /api/live_trading/sessions)
```javascript
pm.test("Status code is 201", function () {
    pm.response.to.have.status(201);
});

pm.test("Session created successfully", function () {
    var jsonData = pm.response.json();
    pm.expect(jsonData).to.have.property('session_id');
});

pm.test("Extract live_session_id", function () {
    var jsonData = pm.response.json();
    pm.environment.set("live_session_id", jsonData.session_id);
});
```

#### Get Session Status (GET /api/live_trading/sessions/:id)
```javascript
pm.test("Status code is 200", function () {
    pm.response.to.have.status(200);
});

pm.test("Session status has risk limits", function () {
    var jsonData = pm.response.json();
    pm.expect(jsonData).to.have.property('session_id');
    pm.expect(jsonData).to.have.property('status');
    pm.expect(jsonData).to.have.property('risk_limits_status');
    pm.expect(jsonData.risk_limits_status).to.have.property('can_open_new_position');
    pm.expect(jsonData.risk_limits_status.can_open_new_position).to.be.a('boolean');
});

pm.test("Session has connectivity status", function () {
    var jsonData = pm.response.json();
    pm.expect(jsonData).to.have.property('connectivity_status');
});
```

#### Place Order (POST /api/live_trading/sessions/:id/orders)
```javascript
pm.test("Status code is 201", function () {
    pm.response.to.have.status(201);
});

pm.test("Order placed successfully", function () {
    var jsonData = pm.response.json();
    pm.expect(jsonData).to.have.property('order_id');
    pm.expect(jsonData).to.have.property('message');
});

pm.test("Extract order_id", function () {
    var jsonData = pm.response.json();
    pm.environment.set("order_id", jsonData.order_id);
});
```

#### Get Order Status (GET /api/live_trading/sessions/:id/orders/:order_id)
```javascript
pm.test("Status code is 200", function () {
    pm.response.to.have.status(200);
});

pm.test("Order status has required fields", function () {
    var jsonData = pm.response.json();
    pm.expect(jsonData).to.have.property('order_id');
    pm.expect(jsonData).to.have.property('exchange_order_id');
    pm.expect(jsonData).to.have.property('status');
    pm.expect(jsonData).to.have.property('type');
    pm.expect(jsonData).to.have.property('side');
    pm.expect(jsonData).to.have.property('quantity');
});
```

#### Emergency Stop (POST /api/live_trading/sessions/:id/emergency_stop)
```javascript
pm.test("Status code is 200", function () {
    pm.response.to.have.status(200);
});

pm.test("Emergency stop executed", function () {
    var jsonData = pm.response.json();
    pm.expect(jsonData).to.have.property('message');
    pm.expect(jsonData).to.have.property('cancelled_orders');
    pm.expect(jsonData.cancelled_orders).to.be.a('number');
    pm.expect(jsonData).to.have.property('duration_ms');
});
```

---

## Summary

### Coverage Requirements
- **Total requests requiring test scripts**: 28
- **Minimum tests per request**: 2-4 tests
- **Total estimated test assertions**: ~80-100

### Validation Hierarchy
1. **Status Code** (all 28 requests)
2. **Response Structure** (26 requests - excluding 2 DELETE endpoints)
3. **Field Presence & Types** (26 requests)
4. **Variable Extraction** (5 requests - create operations)

### Test Naming Convention
Use descriptive test names that clearly state what is being validated:
- ✅ "Status code is 200"
- ✅ "Response contains data array"
- ✅ "Strategy has required fields"
- ❌ "Test 1", "Check response", "Validation"

All test scripts must follow these contracts to ensure consistent, reliable API validation across the entire collection.
