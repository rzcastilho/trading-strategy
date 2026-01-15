# Data Model: Postman API Collection Structure

**Date**: 2026-01-14
**Feature**: 002-postman-api-collection

## Overview

This document defines the data models for the Postman Collection itself (collection structure) and the API request/response schemas that the collection tests.

---

## 1. Postman Collection Structure

### Collection Root Object
```typescript
interface PostmanCollection {
  info: CollectionInfo;
  item: Array<Folder | Request>;
  variable: Array<Variable>;
  event?: Array<Event>;
}
```

### Collection Info
```typescript
interface CollectionInfo {
  name: string;              // "Trading Strategy API"
  description: string;       // Collection description
  schema: string;            // "https://schema.getpostman.com/json/collection/v2.1.0/collection.json"
  version?: string;          // Optional version (e.g., "1.0.0")
}
```

### Folder (Request Group)
```typescript
interface Folder {
  name: string;              // e.g., "Strategy Management"
  description?: string;      // Optional folder description
  item: Array<Request>;      // Requests in this folder
}
```

### Request Object
```typescript
interface Request {
  name: string;              // e.g., "Create Strategy"
  request: RequestDetails;   // HTTP request configuration
  response: Array<Response>; // Example responses
  event?: Array<Event>;      // Test scripts
}
```

### Request Details
```typescript
interface RequestDetails {
  method: "GET" | "POST" | "PATCH" | "DELETE";
  header: Array<Header>;
  body?: Body;
  url: URL;
  description?: string;
}
```

### URL Object
```typescript
interface URL {
  raw: string;               // "{{base_url}}/api/strategies"
  protocol: string;          // "http"
  host: Array<string>;       // ["{{base_url}}"]
  path: Array<string>;       // ["api", "strategies"]
  query?: Array<QueryParam>; // Optional query parameters
  variable?: Array<PathVariable>; // Path variables (:id)
}
```

### Body Object (for POST/PATCH)
```typescript
interface Body {
  mode: "raw" | "formdata" | "urlencoded";
  raw?: string;              // JSON string for "raw" mode
  options?: {
    raw: {
      language: "json";
    }
  }
}
```

### Event Object (Test Scripts)
```typescript
interface Event {
  listen: "test" | "prerequest";
  script: Script;
}

interface Script {
  type: "text/javascript";
  exec: Array<string>;       // Lines of JavaScript code
}
```

### Variable Object
```typescript
interface Variable {
  key: string;               // "base_url", "strategy_id", etc.
  value: string | number;    // "http://localhost:4000"
  type: "string" | "number" | "boolean";
  description?: string;
}
```

### Response Object (Example)
```typescript
interface Response {
  name: string;              // "Success - 200 OK"
  originalRequest: RequestDetails;
  status: string;            // "OK", "Created", etc.
  code: number;              // 200, 201, 204, etc.
  header: Array<Header>;
  body: string;              // JSON string
  _postman_previewlanguage: "json";
}
```

---

## 2. API Request/Response Schemas

### 2.1 Strategy Management

#### Create Strategy Request
```json
{
  "strategy": {
    "name": "string (required)",
    "description": "string (optional)",
    "format": "yaml | toml (required)",
    "content": "string (required, DSL content)",
    "trading_pair": "string (required, e.g., BTC/USD)",
    "timeframe": "string (required, e.g., 1h, 4h, 1d)"
  }
}
```

#### Strategy Response (Single)
```json
{
  "data": {
    "id": "uuid (string)",
    "name": "string",
    "description": "string | null",
    "format": "yaml | toml",
    "content": "string",
    "trading_pair": "string",
    "timeframe": "string",
    "status": "draft | active | inactive | archived",
    "version": "integer",
    "inserted_at": "ISO8601 datetime string",
    "updated_at": "ISO8601 datetime string"
  }
}
```

#### Strategy List Response
```json
{
  "data": [
    {
      "id": "uuid",
      "name": "string",
      "trading_pair": "string",
      "timeframe": "string",
      "status": "string",
      "version": "integer",
      "inserted_at": "datetime",
      "updated_at": "datetime"
    }
  ]
}
```

**Validation Rules**:
- `id`: Must be valid UUID
- `name`: Required, non-empty string
- `format`: Must be "yaml" or "toml"
- `status`: Must be one of: draft, active, inactive, archived
- `version`: Positive integer
- Timestamps: ISO8601 format

---

### 2.2 Backtest Management

#### Create Backtest Request
```json
{
  "strategy_id": "uuid (required)",
  "trading_pair": "string (required)",
  "start_date": "ISO8601 datetime (required)",
  "end_date": "ISO8601 datetime (required)",
  "initial_capital": "decimal string (required)",
  "commission_rate": "decimal string (required, 0.0-1.0)",
  "slippage_bps": "integer (required, basis points)",
  "data_source": "string (required, e.g., binance)"
}
```

#### Create Backtest Response
```json
{
  "backtest_id": "uuid",
  "status": "running | completed | failed | cancelled",
  "message": "string"
}
```

#### Backtest Progress Response
```json
{
  "backtest_id": "uuid",
  "status": "running | completed | failed | cancelled",
  "progress_percentage": "integer (0-100)",
  "bars_processed": "integer",
  "total_bars": "integer",
  "estimated_time_remaining_ms": "integer"
}
```

#### Backtest Results Response
```json
{
  "backtest_id": "uuid",
  "strategy_id": "uuid",
  "config": {
    "trading_pair": "string",
    "start_date": "datetime",
    "end_date": "datetime",
    "initial_capital": "decimal string"
  },
  "performance_metrics": {
    "total_return": "decimal string (percentage)",
    "total_return_abs": "decimal string (absolute value)",
    "win_rate": "decimal string (0.0-1.0)",
    "max_drawdown": "decimal string (percentage)",
    "sharpe_ratio": "decimal string",
    "trade_count": "integer",
    "winning_trades": "integer",
    "losing_trades": "integer",
    "average_win": "decimal string",
    "average_loss": "decimal string",
    "profit_factor": "decimal string"
  },
  "trades": [
    {
      "timestamp": "datetime",
      "side": "buy | sell",
      "price": "decimal string",
      "quantity": "decimal string",
      "pnl": "decimal string"
    }
  ],
  "equity_curve": [
    {
      "timestamp": "datetime",
      "equity": "decimal string"
    }
  ]
}
```

#### Validate Data Request
```json
{
  "trading_pair": "string (required)",
  "start_date": "ISO8601 datetime (required)",
  "end_date": "ISO8601 datetime (required)",
  "timeframe": "string (required)",
  "data_source": "string (required)"
}
```

#### Validate Data Response
```json
{
  "total_bars_expected": "integer",
  "total_bars_available": "integer",
  "completeness_percentage": "decimal string",
  "quality_warnings": [
    {
      "type": "string (e.g., gap_detected, missing_bars)",
      "message": "string",
      "timestamp": "datetime"
    }
  ]
}
```

**Validation Rules**:
- `start_date` must be before `end_date`
- `initial_capital` must be positive decimal
- `commission_rate` must be between 0.0 and 1.0
- `slippage_bps` must be non-negative integer
- `progress_percentage` must be 0-100
- `win_rate`, `total_return`, `max_drawdown` are decimals between 0.0 and 1.0 (or >1.0 for returns)

---

### 2.3 Paper Trading

#### Create Session Request
```json
{
  "session": {
    "strategy_id": "uuid (required)",
    "trading_pair": "string (required)",
    "initial_capital": "decimal string (required)",
    "data_source": "string (required)",
    "position_sizing": "string (required, e.g., percentage)",
    "position_size_pct": "decimal (required, 0.0-1.0)"
  }
}
```

#### Session Status Response
```json
{
  "data": {
    "session_id": "uuid",
    "status": "active | paused | stopped",
    "started_at": "datetime",
    "current_equity": "decimal string",
    "unrealized_pnl": "decimal string",
    "realized_pnl": "decimal string",
    "open_positions": [
      {
        "trading_pair": "string",
        "side": "long | short",
        "entry_price": "decimal string",
        "quantity": "decimal string",
        "current_price": "decimal string",
        "unrealized_pnl": "decimal string",
        "duration_seconds": "integer"
      }
    ],
    "trades_count": "integer",
    "last_market_price": "decimal string",
    "last_updated_at": "datetime"
  }
}
```

#### Pause/Resume Response
```json
{
  "message": "string (e.g., Session paused successfully)",
  "session_id": "uuid",
  "status": "paused | active"
}
```

#### Trade History Response
```json
{
  "data": [
    {
      "trade_id": "uuid",
      "session_id": "uuid",
      "timestamp": "datetime",
      "trading_pair": "string",
      "side": "buy | sell",
      "quantity": "decimal string",
      "price": "decimal string",
      "signal_type": "entry | exit | stop_loss",
      "pnl": "decimal string"
    }
  ]
}
```

#### Performance Metrics Response
```json
{
  "data": {
    "session_id": "uuid",
    "total_trades": "integer",
    "winning_trades": "integer",
    "losing_trades": "integer",
    "win_rate": "decimal string",
    "total_pnl": "decimal string",
    "total_return_pct": "decimal string",
    "sharpe_ratio": "decimal string",
    "max_drawdown_pct": "decimal string",
    "average_win": "decimal string",
    "average_loss": "decimal string",
    "largest_win": "decimal string",
    "largest_loss": "decimal string"
  }
}
```

**Validation Rules**:
- `initial_capital` must be positive
- `position_size_pct` must be between 0.0 and 1.0
- `status` must be one of: active, paused, stopped
- `side` must be one of: buy, sell, long, short
- All decimal fields must be valid numeric strings

---

### 2.4 Live Trading

#### Create Session Request
```json
{
  "strategy_id": "uuid (required)",
  "trading_pair": "string (required)",
  "allocated_capital": "decimal string (required)",
  "exchange": "string (required, e.g., binance)",
  "mode": "testnet | live (required)",
  "api_credentials": {
    "api_key": "string (required)",
    "api_secret": "string (required)",
    "passphrase": "string | null"
  },
  "position_sizing": "string (required)",
  "risk_limits": {
    "max_position_size_pct": "decimal string (required)",
    "max_daily_loss_pct": "decimal string (required)",
    "max_drawdown_pct": "decimal string (required)",
    "max_concurrent_positions": "integer (required)"
  }
}
```

#### Session Status Response
```json
{
  "session_id": "uuid",
  "status": "active | paused | stopped",
  "started_at": "datetime",
  "exchange": "string",
  "current_equity": "decimal string",
  "unrealized_pnl": "decimal string",
  "realized_pnl": "decimal string",
  "open_positions": [
    {
      "position_id": "uuid",
      "trading_pair": "string",
      "side": "long | short",
      "entry_price": "decimal string",
      "quantity": "decimal string",
      "current_price": "decimal string",
      "unrealized_pnl": "decimal string"
    }
  ],
  "pending_orders": [
    {
      "order_id": "uuid",
      "exchange_order_id": "string",
      "type": "market | limit",
      "side": "buy | sell",
      "status": "pending | filled | cancelled",
      "quantity": "decimal string",
      "price": "decimal string | null"
    }
  ],
  "trades_count": "integer",
  "risk_limits_status": {
    "position_size_utilization_pct": "decimal string",
    "daily_loss_used_pct": "decimal string",
    "drawdown_from_peak_pct": "decimal string",
    "concurrent_positions": "integer",
    "can_open_new_position": "boolean"
  },
  "last_updated_at": "datetime",
  "connectivity_status": "connected | disconnected"
}
```

#### Place Order Request
```json
{
  "order_type": "market | limit (required)",
  "side": "buy | sell (required)",
  "quantity": "decimal string (required)",
  "price": "decimal string | null (required for limit orders)",
  "signal_type": "entry | exit | stop_loss"
}
```

#### Place Order Response
```json
{
  "order_id": "uuid",
  "message": "string (e.g., Order placed successfully)"
}
```

#### Order Status Response
```json
{
  "order_id": "uuid",
  "exchange_order_id": "string",
  "type": "market | limit",
  "side": "buy | sell",
  "status": "pending | filled | partially_filled | cancelled | rejected",
  "quantity": "decimal string",
  "filled_quantity": "decimal string",
  "price": "decimal string | null",
  "average_fill_price": "decimal string | null",
  "created_at": "datetime",
  "updated_at": "datetime"
}
```

#### Emergency Stop Response
```json
{
  "message": "string (Emergency stop executed)",
  "session_id": "uuid",
  "cancelled_orders": "integer",
  "failed_cancellations": "integer",
  "duration_ms": "integer"
}
```

**Validation Rules**:
- `allocated_capital` must be positive
- `mode` must be "testnet" or "live"
- `max_position_size_pct`, `max_daily_loss_pct`, `max_drawdown_pct` must be between 0.0 and 1.0
- `max_concurrent_positions` must be positive integer
- `order_type` must be "market" or "limit"
- `side` must be "buy" or "sell"
- `quantity` must be positive decimal
- `price` required for limit orders, null for market orders

---

## 3. Common Error Responses

### 404 Not Found
```json
{
  "error": "Not found"
}
```

### 422 Unprocessable Entity (Validation Error)
```json
{
  "errors": {
    "field_name": ["error message 1", "error message 2"]
  }
}
```

### 503 Service Unavailable (Data Feed)
```json
{
  "error": "Data feed unavailable",
  "retry_after": "integer (seconds)"
}
```

**Note**: Error responses are **out of scope** for this collection (happy path only per FR-013).

---

## 4. Environment Variables

### Collection Variables (Embedded)
| Variable | Type | Default Value | Description |
|----------|------|---------------|-------------|
| `base_url` | string | `http://localhost:4000` | Base URL for API |
| `port` | string | `4000` | API server port |

### Dynamic Variables (Set by Test Scripts)
| Variable | Type | Set By | Used By |
|----------|------|--------|---------|
| `strategy_id` | string | Create Strategy | Get/Update/Delete Strategy, Create Backtest, Create Sessions |
| `backtest_id` | string | Create Backtest | Get Results, Get Progress, Cancel Backtest |
| `session_id` | string | Create Session | Session operations, Place Order |
| `order_id` | string | Place Order | Get Order Status, Cancel Order |

---

## 5. Type Conventions

### UUID Format
- **String representation**: `"550e8400-e29b-41d4-a716-446655440000"`
- **Validation**: Must match UUID v4 regex pattern

### Decimal Format
- **String representation**: `"10000.00"`, `"0.001"`, `"1.8"`
- **Reason**: JSON number precision limitations; Elixir Decimal type serializes to string

### DateTime Format
- **Format**: ISO8601 with timezone
- **Example**: `"2023-01-01T00:00:00Z"`, `"2025-12-04T15:30:00+00:00"`
- **Validation**: Must be valid ISO8601 datetime

### Percentage Format
- **Decimal representation**: `"0.342"` = 34.2%, `"1.0"` = 100%
- **Range**: 0.0-1.0 for most percentages (returns can exceed 1.0)

### Enum Values
- **Case**: Lowercase with underscores
- **Examples**: `active`, `draft`, `running`, `buy`, `sell`, `stop_loss`

---

## Summary

This data model defines:
1. **Postman Collection Structure**: v2.1 schema with folders, requests, variables, test scripts
2. **API Schemas**: 28 request/response schemas across 4 functional areas
3. **Validation Rules**: Type constraints, required fields, enums
4. **Variable Strategy**: Collection variables + dynamic test-extracted variables
5. **Type Conventions**: UUID, Decimal, DateTime formatting standards

All schemas align with the Phoenix API implementation discovered during exploration phase.
