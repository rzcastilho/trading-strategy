# Research: Postman API Collection for Trading Strategy

**Date**: 2026-01-14
**Feature**: 002-postman-api-collection

## Phase 0: Research & Technology Decisions

This document consolidates research findings to resolve all technical unknowns identified in the Technical Context section of plan.md.

---

## 1. Postman Collection v2.1 Schema Structure

### Decision
Use **Postman Collection Format v2.1** as the standard schema for the collection JSON file.

### Rationale
- **Industry Standard**: v2.1 is the most widely supported Postman collection format (2018+)
- **Feature Complete**: Supports folders, environments, test scripts, pre-request scripts, and variables
- **Backward Compatible**: Works with both Postman desktop and web versions
- **Forward Compatible**: Can be upgraded to v2.2 if needed without breaking changes
- **Tool Support**: Compatible with Newman CLI for automated testing (future use case)

### Schema Structure
```json
{
  "info": {
    "name": "Collection Name",
    "description": "Collection Description",
    "schema": "https://schema.getpostman.com/json/collection/v2.1.0/collection.json"
  },
  "item": [
    {
      "name": "Folder Name",
      "item": [
        {
          "name": "Request Name",
          "request": {
            "method": "GET|POST|PATCH|DELETE",
            "header": [],
            "body": {},
            "url": {
              "raw": "{{base_url}}/api/endpoint",
              "host": ["{{base_url}}"],
              "path": ["api", "endpoint"]
            },
            "description": "Request description"
          },
          "response": [],
          "event": [
            {
              "listen": "test",
              "script": {
                "exec": ["pm.test('Test name', function() {", "  // test code", "});"],
                "type": "text/javascript"
              }
            }
          ]
        }
      ]
    }
  ],
  "variable": [
    {
      "key": "base_url",
      "value": "http://localhost:4000",
      "type": "string"
    }
  ]
}
```

### Key Components
- **info**: Collection metadata (name, description, schema version)
- **item**: Array of folders and requests (hierarchical structure)
- **variable**: Collection-level variables ({{base_url}}, etc.)
- **event**: Test scripts attached to requests (pre-request, test phases)
- **response**: Example responses for documentation (saved responses)

### Alternatives Considered
- **v2.0**: Deprecated, lacks some modern features
- **v2.2**: Newer but has limited tool support; v2.1 is safer choice
- **OpenAPI/Swagger**: Different purpose (API specification vs testing collection)

---

## 2. Postman Test Script Best Practices

### Decision
Use **Postman JavaScript test scripts** with the following patterns for basic validation:
1. Status code validation
2. Response time checks (optional, not enforced)
3. JSON schema validation (field presence + type checking)
4. Data extraction for chaining requests (using `pm.environment.set()`)

### Rationale
- **Built-in Assertions**: Postman provides `pm.test()` API with Chai.js assertions
- **Variable Chaining**: Can extract IDs from responses and use in subsequent requests
- **Simple Syntax**: JavaScript-based, easy to read and maintain
- **No External Dependencies**: Runs directly in Postman without plugins

### Test Script Template (Status Code + Field Validation)
```javascript
// Test 1: Validate status code
pm.test("Status code is 200", function () {
    pm.response.to.have.status(200);
});

// Test 2: Validate response has data field
pm.test("Response contains data field", function () {
    var jsonData = pm.response.json();
    pm.expect(jsonData).to.have.property('data');
});

// Test 3: Validate key fields exist and have correct type
pm.test("Response has required fields with correct types", function () {
    var jsonData = pm.response.json();
    pm.expect(jsonData.data).to.have.property('id');
    pm.expect(jsonData.data.id).to.be.a('string'); // UUID as string
    pm.expect(jsonData.data).to.have.property('name');
    pm.expect(jsonData.data.name).to.be.a('string');
});

// Test 4: Extract ID for use in subsequent requests
pm.test("Extract ID to environment", function () {
    var jsonData = pm.response.json();
    pm.environment.set("strategy_id", jsonData.data.id);
});
```

### Test Script Template (List Endpoints)
```javascript
// Test 1: Validate status code
pm.test("Status code is 200", function () {
    pm.response.to.have.status(200);
});

// Test 2: Validate response is an array
pm.test("Response contains data array", function () {
    var jsonData = pm.response.json();
    pm.expect(jsonData).to.have.property('data');
    pm.expect(jsonData.data).to.be.an('array');
});

// Test 3: Validate array items have required fields (if not empty)
pm.test("Array items have required fields", function () {
    var jsonData = pm.response.json();
    if (jsonData.data.length > 0) {
        pm.expect(jsonData.data[0]).to.have.property('id');
        pm.expect(jsonData.data[0]).to.have.property('name');
    }
});
```

### Test Script Template (201 Created)
```javascript
pm.test("Status code is 201", function () {
    pm.response.to.have.status(201);
});

pm.test("Response contains created resource", function () {
    var jsonData = pm.response.json();
    pm.expect(jsonData).to.have.property('data');
    pm.expect(jsonData.data).to.have.property('id');
});
```

### Test Script Template (204 No Content - Delete)
```javascript
pm.test("Status code is 204", function () {
    pm.response.to.have.status(204);
});
```

### Variable Chaining Strategy
To enable end-to-end workflows (create strategy → run backtest → start session), use environment variables:

1. **Create Strategy** → Extract `strategy_id` → Store as `{{strategy_id}}`
2. **Create Backtest** → Use `{{strategy_id}}` → Extract `backtest_id` → Store as `{{backtest_id}}`
3. **Create Paper Trading Session** → Use `{{strategy_id}}` → Extract `session_id` → Store as `{{session_id}}`

Example extraction:
```javascript
pm.environment.set("strategy_id", pm.response.json().data.id);
pm.environment.set("backtest_id", pm.response.json().backtest_id);
pm.environment.set("session_id", pm.response.json().session_id);
```

Example usage in URL:
```
{{base_url}}/api/strategies/{{strategy_id}}
{{base_url}}/api/backtests/{{backtest_id}}/progress
{{base_url}}/api/paper_trading/sessions/{{session_id}}/trades
```

### Alternatives Considered
- **No test scripts**: Rejected - automation benefit lost, manual verification error-prone
- **Complex schema validation**: Rejected - over-engineering for basic validation needs
- **External JSON Schema files**: Rejected - adds complexity, not needed for 28 endpoints

---

## 3. Realistic Example Data for Trading APIs

### Decision
Use **semi-realistic trading data** with plausible values based on common cryptocurrency trading scenarios.

### Rationale
- **User Requirement**: Spec explicitly requests "semi-realistic, plausible values" (spec.md FR-005)
- **Educational Value**: Realistic examples help developers understand expected data formats
- **Not Production Data**: Avoid real API keys, real account IDs, or sensitive information
- **Common Patterns**: Use well-known indicators (RSI, MACD), popular trading pairs (BTC/USD, ETH/USD)

### Strategy Example Data (YAML DSL Format)
```json
{
  "strategy": {
    "name": "RSI Mean Reversion",
    "description": "Buy when RSI < 30 (oversold), sell when RSI > 70 (overbought) on 1-hour BTC/USD",
    "format": "yaml",
    "content": "name: RSI Mean Reversion\nindicators:\n  - name: rsi\n    period: 14\nentry_rules:\n  - rsi < 30\nexit_rules:\n  - rsi > 70\nstop_loss:\n  percentage: 0.02\nposition_sizing:\n  method: percentage\n  value: 0.1\n",
    "trading_pair": "BTC/USD",
    "timeframe": "1h"
  }
}
```

### Backtest Example Data
```json
{
  "strategy_id": "{{strategy_id}}",
  "trading_pair": "BTC/USD",
  "start_date": "2023-01-01T00:00:00Z",
  "end_date": "2024-12-31T23:59:59Z",
  "initial_capital": "10000.00",
  "commission_rate": "0.001",
  "slippage_bps": 5,
  "data_source": "binance"
}
```

**Plausible Values**:
- **Dates**: 2-year historical range (2023-2024)
- **Capital**: $10,000 (typical retail starting capital)
- **Commission**: 0.1% (typical exchange fee)
- **Slippage**: 5 basis points (realistic for liquid pairs)

### Paper Trading Session Example Data
```json
{
  "session": {
    "strategy_id": "{{strategy_id}}",
    "trading_pair": "BTC/USD",
    "initial_capital": "10000.00",
    "data_source": "binance",
    "position_sizing": "percentage",
    "position_size_pct": 0.1
  }
}
```

**Plausible Values**:
- **Position Size**: 10% of portfolio (conservative risk management)
- **Capital**: $10,000 (consistent with backtest)

### Live Trading Session Example Data
```json
{
  "strategy_id": "{{strategy_id}}",
  "trading_pair": "BTC/USDT",
  "allocated_capital": "5000.00",
  "exchange": "binance",
  "mode": "testnet",
  "api_credentials": {
    "api_key": "testnet_key_placeholder",
    "api_secret": "testnet_secret_placeholder",
    "passphrase": null
  },
  "position_sizing": "percentage",
  "risk_limits": {
    "max_position_size_pct": "0.25",
    "max_daily_loss_pct": "0.03",
    "max_drawdown_pct": "0.15",
    "max_concurrent_positions": 3
  }
}
```

**Plausible Values**:
- **Mode**: "testnet" (safe for testing, no real money)
- **Capital**: $5,000 (lower than paper trading for safety)
- **Max Position Size**: 25% (aggressive but realistic)
- **Max Daily Loss**: 3% (common risk management rule)
- **Max Drawdown**: 15% (typical stop-out threshold)
- **API Credentials**: Placeholder strings (NOT real keys)

### Trading Pair Conventions
- **BTC/USD**: Bitcoin vs US Dollar (common for backtesting)
- **BTC/USDT**: Bitcoin vs Tether (common for live trading on Binance)
- **ETH/USD**: Ethereum vs US Dollar (alternative example)

### Indicator Conventions
- **RSI (Relative Strength Index)**: Period 14, oversold < 30, overbought > 70
- **MACD (Moving Average Convergence Divergence)**: Fast 12, Slow 26, Signal 9
- **Bollinger Bands**: Period 20, Standard Deviation 2

### Alternatives Considered
- **Minimal/Mock Data**: Rejected - less educational value, harder to understand API semantics
- **Production-like Data**: Rejected - security risk (real API keys), too complex for examples
- **Exhaustive Edge Cases**: Rejected - out of scope (happy path only per spec.md FR-013)

---

## 4. Environment Configuration Strategy

### Decision
Use **Postman Collection Variables** (embedded in JSON) for localhost configuration. Optionally provide a separate environment file for users who prefer explicit environment management.

### Rationale
- **Self-Contained**: Collection variables travel with the collection (no separate import needed)
- **Single File**: Simplifies onboarding (one import vs two)
- **Override Capability**: Users can still create custom environments to override collection variables
- **Spec Requirement**: FR-007 requires "local development environment configuration"

### Collection Variables (Embedded in JSON)
```json
{
  "variable": [
    {
      "key": "base_url",
      "value": "http://localhost:4000",
      "type": "string"
    },
    {
      "key": "port",
      "value": "4000",
      "type": "string"
    }
  ]
}
```

### Optional: Separate Environment File (`localhost-dev.postman_environment.json`)
```json
{
  "id": "unique-uuid-here",
  "name": "Trading Strategy - Localhost",
  "values": [
    {
      "key": "base_url",
      "value": "http://localhost:4000",
      "enabled": true
    },
    {
      "key": "port",
      "value": "4000",
      "enabled": true
    },
    {
      "key": "strategy_id",
      "value": "",
      "enabled": true
    },
    {
      "key": "backtest_id",
      "value": "",
      "enabled": true
    },
    {
      "key": "session_id",
      "value": "",
      "enabled": true
    }
  ],
  "_postman_variable_scope": "environment"
}
```

**Note**: Environment file is **optional** - collection works without it using embedded variables.

### Alternatives Considered
- **Hardcoded URLs**: Rejected - inflexible, can't change ports easily
- **Multiple Environments (staging, prod)**: Rejected - out of scope (spec.md: only local dev)
- **No variables**: Rejected - poor user experience, violates FR-007

---

## 5. Request Organization Strategy

### Decision
Organize requests into **4 top-level folders** matching functional areas from the spec:
1. Strategy Management (5 requests)
2. Backtest Management (6 requests)
3. Paper Trading (8 requests)
4. Live Trading (9 requests)

**Total**: 28 requests across 4 folders

### Rationale
- **Spec Alignment**: FR-008 requires "folders by functional area"
- **User Mental Model**: Matches the user journey (define strategy → backtest → paper trade → live trade)
- **Logical Grouping**: Each folder contains related operations for a single domain concept
- **Flat Hierarchy**: 2 levels only (folder → request), easy to navigate

### Folder Structure Details

#### Folder 1: Strategy Management
- List Strategies (GET /api/strategies)
- Create Strategy (POST /api/strategies)
- Get Strategy by ID (GET /api/strategies/:id)
- Update Strategy (PATCH /api/strategies/:id)
- Delete Strategy (DELETE /api/strategies/:id)

**Order Rationale**: RESTful convention (List, Create, Get, Update, Delete)

#### Folder 2: Backtest Management
- Create Backtest (POST /api/backtests)
- List Backtests (GET /api/backtests)
- Get Backtest Results (GET /api/backtests/:id)
- Get Backtest Progress (GET /api/backtests/:id/progress)
- Cancel Backtest (DELETE /api/backtests/:id)
- Validate Historical Data (POST /api/backtests/validate-data)

**Order Rationale**: Creation first, then monitoring (list, get, progress), then control (cancel), then utility (validate)

#### Folder 3: Paper Trading
- Create Session (POST /api/paper_trading/sessions)
- List Sessions (GET /api/paper_trading/sessions)
- Get Session Status (GET /api/paper_trading/sessions/:id)
- Stop Session (DELETE /api/paper_trading/sessions/:id)
- Pause Session (POST /api/paper_trading/sessions/:id/pause)
- Resume Session (POST /api/paper_trading/sessions/:id/resume)
- Get Trade History (GET /api/paper_trading/sessions/:id/trades)
- Get Performance Metrics (GET /api/paper_trading/sessions/:id/metrics)

**Order Rationale**: Session lifecycle (create, list, status, stop), control (pause/resume), analysis (trades, metrics)

#### Folder 4: Live Trading
- Create Session (POST /api/live_trading/sessions)
- List Sessions (GET /api/live_trading/sessions)
- Get Session Status (GET /api/live_trading/sessions/:id)
- Stop Session (DELETE /api/live_trading/sessions/:id)
- Pause Session (POST /api/live_trading/sessions/:id/pause)
- Resume Session (POST /api/live_trading/sessions/:id/resume)
- Emergency Stop (POST /api/live_trading/sessions/:id/emergency_stop)
- Place Order (POST /api/live_trading/sessions/:id/orders)
- Get Order Status (GET /api/live_trading/sessions/:id/orders/:order_id)
- Cancel Order (DELETE /api/live_trading/sessions/:id/orders/:order_id)

**Order Rationale**: Session lifecycle, control (pause/resume/emergency), order management (place, status, cancel)

### Alternatives Considered
- **Single flat list**: Rejected - 28 requests too many, poor UX
- **Organize by HTTP method**: Rejected - not semantic (mixes unrelated operations)
- **Organize by entity (Strategy, Session, Order)**: Rejected - doesn't match user journey flow

---

## 6. Response Example Strategy

### Decision
Include **saved example responses** for each request showing expected success responses.

### Rationale
- **Documentation Value**: Developers see expected format without running API
- **Spec Requirement**: FR-006 requires "example response bodies showing expected success responses"
- **Postman Feature**: Response examples are first-class feature in v2.1 schema
- **No Overhead**: Examples stored in collection JSON, no runtime impact

### Example Response Structure
Each request will have 1 saved response example:
```json
{
  "name": "Success - 200 OK",
  "originalRequest": { /* mirror of request */ },
  "status": "OK",
  "code": 200,
  "_postman_previewlanguage": "json",
  "header": [
    {
      "key": "Content-Type",
      "value": "application/json"
    }
  ],
  "body": "{\n  \"data\": {\n    \"id\": \"550e8400-e29b-41d4-a716-446655440000\",\n    \"name\": \"RSI Mean Reversion\",\n    ...\n  }\n}"
}
```

### Alternatives Considered
- **No examples**: Rejected - violates FR-006, reduces collection value
- **Multiple examples per request**: Rejected - happy path only (no error examples needed per FR-013)

---

## Summary of Decisions

| Research Area | Decision | Rationale |
|---------------|----------|-----------|
| **Collection Format** | Postman Collection v2.1 | Industry standard, wide tool support, feature complete |
| **Test Scripts** | JavaScript with Chai assertions | Built-in, simple, status + field validation |
| **Example Data** | Semi-realistic trading data | Educational, plausible values (RSI, MACD, BTC/USD) |
| **Environment** | Collection variables + optional env file | Self-contained, user flexibility |
| **Organization** | 4 folders by functional area | User journey flow, spec alignment (FR-008) |
| **Response Examples** | 1 success example per request | Documentation value, spec requirement (FR-006) |

**All unknowns resolved. Ready for Phase 1 (Design & Contracts).**
