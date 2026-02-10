# Trading Strategy API Reference

Complete REST API documentation for the Trading Strategy DSL Library.

## Base URL

```
Development: http://localhost:4000/api
Production: https://your-domain.com/api
```

## Authentication

**Required for all strategy management endpoints**

The application uses session-based authentication via Phoenix's `phx.gen.auth`:

- **Web UI**: Authenticated via cookie sessions after login
- **API**: Include session cookie or add API key support (future enhancement)

### User Registration
```
POST /users/register
Content-Type: application/x-www-form-urlencoded

user[email]=user@example.com&user[password]=secure_password_123

Response: Redirect to dashboard
```

### User Login
```
POST /users/log_in
Content-Type: application/x-www-form-urlencoded

user[email]=user@example.com&user[password]=secure_password_123

Response: Redirect to dashboard with authenticated session
```

## API Endpoints

### Strategy Management

**All endpoints are user-scoped** - users can only access their own strategies.

See `specs/001-strategy-dsl-library/contracts/strategy_api.ex` and `specs/004-strategy-ui/contracts/` for detailed contracts.

#### List User Strategies
```
GET /api/strategies?status=active&limit=50&offset=0

Response: 200 OK
{
  "strategies": [
    {
      "id": "uuid",
      "name": "RSI Mean Reversion",
      "status": "active",
      "version": 1,
      "trading_pair": "BTC/USD",
      "timeframe": "1h",
      "updated_at": "2026-02-09T12:00:00Z"
    }
  ],
  "total": 1,
  "limit": 50,
  "offset": 0
}
```

#### Create Strategy
```
POST /api/strategies
Content-Type: application/json
Authorization: Required (session cookie)

{
  "name": "RSI Mean Reversion",
  "description": "Mean reversion strategy using RSI indicator",
  "format": "yaml",
  "content": "<yaml string>",
  "trading_pair": "BTC/USD",
  "timeframe": "1h",
  "status": "draft"
}

Response: 201 Created
{
  "id": "uuid",
  "user_id": "user-uuid",
  "name": "RSI Mean Reversion",
  "status": "draft",
  "version": 1,
  "lock_version": 1,
  "created_at": "2026-02-09T12:00:00Z"
}
```

#### Get Strategy
```
GET /api/strategies/:id

Response: 200 OK
{
  "strategy_id": "uuid",
  "name": "RSI Mean Reversion",
  "indicators": [...],
  ...
}
```

#### Update Strategy
```
PUT /api/strategies/:id
Content-Type: application/json
Authorization: Required (session cookie)

{
  "name": "Updated Strategy Name",
  "content": "<updated yaml>",
  "lock_version": 1  // Required for optimistic locking
}

Response: 200 OK
{
  "id": "uuid",
  "name": "Updated Strategy Name",
  "status": "draft",
  "version": 1,
  "lock_version": 2,  // Incremented
  "updated_at": "2026-02-09T12:30:00Z"
}

Response: 409 Conflict (if lock_version mismatch)
{
  "error": {
    "code": "stale_entry",
    "message": "Strategy was modified by another user. Please reload and try again.",
    "current_lock_version": 3
  }
}
```

#### Test Strategy Syntax
```
POST /api/strategies/test_syntax
Content-Type: application/json

{
  "content": "<yaml string>",
  "format": "yaml"
}

Response: 200 OK
{
  "valid": true,
  "parsed": {
    "indicators": ["rsi_14", "sma_50"],
    "entry_conditions": "rsi_14 < 30",
    "exit_conditions": "rsi_14 > 70"
  },
  "summary": "Strategy uses 2 indicators with buy signal on RSI < 30"
}

Response: 422 Unprocessable Entity (syntax errors)
{
  "valid": false,
  "errors": [
    "Line 5: Unknown indicator type 'invalid_indicator'",
    "Entry conditions: Undefined variable 'unknown_var'"
  ]
}
```

#### Duplicate Strategy
```
POST /api/strategies/:id/duplicate
Authorization: Required (session cookie)

Response: 201 Created
{
  "id": "new-uuid",
  "name": "RSI Mean Reversion - Copy",  // " - Copy" appended
  "status": "draft",
  "version": 1,
  "lock_version": 1
}
```

#### Delete Strategy
```
DELETE /api/strategies/:id

Response: 204 No Content
```

### Backtesting

See `specs/001-strategy-dsl-library/contracts/backtest_api.ex`.

#### Start Backtest
```
POST /api/backtests

{
  "strategy_id": "uuid",
  "trading_pair": "BTC/USD",
  "start_date": "2023-01-01T00:00:00Z",
  "end_date": "2024-12-31T23:59:59Z",
  "initial_capital": "10000",
  "commission_rate": "0.001",
  "slippage_bps": 5
}

Response: 202 Accepted
{
  "backtest_id": "uuid",
  "status": "running"
}
```

#### Get Backtest Results
```
GET /api/backtests/:id

Response: 200 OK
{
  "backtest_id": "uuid",
  "status": "completed",
  "performance_metrics": {
    "total_return": "0.342",
    "sharpe_ratio": "1.8",
    "max_drawdown": "0.12",
    ...
  },
  "trades": [...],
  "equity_curve": [...]
}
```

### Paper Trading

See `specs/001-strategy-dsl-library/contracts/paper_trading_api.ex`.

#### Start Paper Session
```
POST /api/paper_trading/sessions

{
  "strategy_id": "uuid",
  "trading_pair": "BTCUSDT",
  "initial_capital": "10000",
  "data_source": "binance"
}

Response: 201 Created
{
  "session_id": "uuid",
  "status": "active"
}
```

#### Get Session Status
```
GET /api/paper_trading/sessions/:id

Response: 200 OK
{
  "session_id": "uuid",
  "status": "active",
  "current_equity": "10450.23",
  "open_positions": [...],
  "trades_count": 8
}
```

#### Stop Session
```
DELETE /api/paper_trading/sessions/:id

Response: 200 OK
{
  "final_equity": "11250.00",
  "performance_metrics": {...}
}
```

### Live Trading

See `specs/001-strategy-dsl-library/contracts/live_trading_api.ex`.

#### Start Live Session
```
POST /api/live_trading/sessions

{
  "strategy_id": "uuid",
  "trading_pair": "BTCUSDT",
  "allocated_capital": "500",
  "exchange": "binance",
  "mode": "testnet",
  "api_credentials": {
    "api_key": "...",
    "api_secret": "..."
  }
}

Response: 201 Created
{
  "session_id": "uuid",
  "status": "active"
}
```

#### Emergency Stop
```
POST /api/live_trading/sessions/:id/emergency_stop

Response: 200 OK
{
  "positions_closed": 2,
  "final_equity": "523.50"
}
```

## Error Responses

All errors follow this format:

```json
{
  "error": {
    "code": "error_code",
    "message": "Human-readable message",
    "status": 400,
    "details": {}  // Optional
  }
}
```

### Error Codes

- `400` - Bad Request (invalid parameters)
- `401` - Unauthorized
- `404` - Not Found
- `409` - Conflict (resource already exists)
- `422` - Validation Error (includes details)
- `429` - Rate Limited
- `500` - Internal Server Error
- `502` - Exchange API Error

## Rate Limiting

- Default: 100 requests per minute per IP
- Headers: `X-RateLimit-Limit`, `X-RateLimit-Remaining`

## WebSocket API

For real-time updates (paper/live trading):

```javascript
const socket = new Phoenix.Socket("ws://localhost:4000/socket")
socket.connect()

const channel = socket.channel("trading:session_id", {})
channel.join()
  .receive("ok", resp => { console.log("Joined", resp) })

channel.on("signal_detected", payload => {
  console.log("Signal:", payload)
})

channel.on("position_opened", payload => {
  console.log("Position:", payload)
})
```

## Elixir Context Functions (Feature 004)

For programmatic access from within the application:

```elixir
alias TradingStrategy.Strategies
alias TradingStrategy.Accounts.User

# User-scoped functions
Strategies.list_strategies(%User{id: user_id}, status: "active", limit: 50)
Strategies.get_strategy(strategy_id, %User{id: user_id})
Strategies.create_strategy(attrs, %User{id: user_id})
Strategies.update_strategy(strategy, attrs, %User{id: user_id})
Strategies.delete_strategy(strategy, %User{id: user_id})

# Strategy operations
Strategies.can_edit?(strategy)  # => true/false
Strategies.can_activate?(strategy)  # => {:ok, :allowed} | {:error, reason}
Strategies.activate_strategy(strategy)
Strategies.test_strategy_syntax(content, :yaml)
Strategies.duplicate_strategy(strategy, %User{id: user_id})

# Version management
Strategies.get_strategy_versions(name, %User{id: user_id})
Strategies.create_new_version(strategy, attrs)
```

**Key Features**:
- All functions are user-scoped for security
- Optimistic locking prevents concurrent edit conflicts
- Status validation prevents editing active strategies
- Syntax testing validates DSL without execution
- PubSub broadcasts for real-time UI updates

## Complete Contracts

Full API contracts available in:
- `specs/001-strategy-dsl-library/contracts/strategy_api.ex`
- `specs/004-strategy-ui/contracts/liveview_routes.md` - LiveView routes and events
- `specs/004-strategy-ui/contracts/validation_api.md` - Validation flow and errors
- `specs/004-strategy-ui/data-model.md` - Database schema and relationships
- `specs/001-strategy-dsl-library/contracts/backtest_api.ex`
- `specs/001-strategy-dsl-library/contracts/paper_trading_api.ex`
- `specs/001-strategy-dsl-library/contracts/live_trading_api.ex`
- `specs/001-strategy-dsl-library/contracts/market_data_api.ex`
