# Trading Strategy API Reference

Complete REST API documentation for the Trading Strategy DSL Library.

## Base URL

```
Development: http://localhost:4000/api
Production: https://your-domain.com/api
```

## Authentication

Currently no authentication required (add API key authentication for production).

## API Endpoints

### Strategy Management

See `specs/001-strategy-dsl-library/contracts/strategy_api.ex` for detailed contract.

#### Create Strategy
```
POST /api/strategies
Content-Type: application/json

{
  "name": "RSI Mean Reversion",
  "format": "yaml",
  "content": "<yaml string>"
}

Response: 201 Created
{
  "strategy_id": "uuid",
  "name": "RSI Mean Reversion",
  "status": "active"
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

Request/Response: Same as Create
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

## Complete Contracts

Full API contracts available in:
- `specs/001-strategy-dsl-library/contracts/strategy_api.ex`
- `specs/001-strategy-dsl-library/contracts/backtest_api.ex`
- `specs/001-strategy-dsl-library/contracts/paper_trading_api.ex`
- `specs/001-strategy-dsl-library/contracts/live_trading_api.ex`
- `specs/001-strategy-dsl-library/contracts/market_data_api.ex`
