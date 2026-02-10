# Trading Strategy API - Postman Collection

## Overview

This Postman collection provides comprehensive testing for the Trading Strategy API, supporting both **Admin API** (current) and **Authenticated API** (future) versions.

## Files

- `trading-strategy-api.postman_collection.json` - Main API collection with 29 endpoints
- `localhost-dev.postman_environment.json` - Environment variables for local development

## Quick Start

### 1. Import into Postman

```bash
# Import the collection
1. Open Postman
2. Click "Import"
3. Select both JSON files
4. Collection appears in sidebar
```

### 2. Select Environment

```bash
1. Click the environment dropdown (top right)
2. Select "Localhost Development"
3. Verify base_url is http://localhost:4000
```

### 3. Verify Server is Running

```bash
# Start the Phoenix server
cd /path/to/trading-strategy
mix phx.server

# Test endpoint
curl http://localhost:4000/api/strategies
# Expected: {"data":[]}
```

### 4. Run Your First Request

```bash
1. Open "Strategy Management" folder
2. Click "Create Strategy"
3. Click "Send"
4. Verify response: 201 Created with strategy data
5. Check environment: strategy_id variable is automatically set
```

## Current API Version: Admin API

### Authentication Status

⚠️ **Current**: Admin API (no authentication required)
- All endpoints use admin functions (`list_all_strategies`, `create_strategy_admin`, etc.)
- Requires `user_id` in request payload for strategy creation
- Default `user_id = 1` is pre-configured in environment

🔐 **Future**: Authenticated API (planned)
- User authentication via Phoenix.Auth
- User ID extracted from session/token
- No `user_id` required in payload

### Environment Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `base_url` | `http://localhost:4000` | API base URL |
| `port` | `4000` | Server port |
| `user_id` | `1` | User ID for strategy creation (Admin API) |
| `strategy_id` | _auto-set_ | Extracted from Create Strategy response |
| `backtest_id` | _auto-set_ | Extracted from Create Backtest response |
| `paper_session_id` | _auto-set_ | Extracted from Create Paper Session response |
| `live_session_id` | _auto-set_ | Extracted from Create Live Session response |
| `order_id` | _auto-set_ | Extracted from Place Order response |

### Using Different Users

To test with a different user:

```bash
# Option 1: Update environment variable
1. Click environment dropdown
2. Click "Edit" (Localhost Development)
3. Change user_id value
4. Save

# Option 2: Inline in request
In the Create Strategy request body, change:
"user_id": "{{user_id}}"
to:
"user_id": "2"  # or any valid user ID
```

## API Endpoints

### Strategy Management (5 endpoints)

- **GET** `/api/strategies` - List all strategies
- **POST** `/api/strategies` - Create strategy _(requires user_id)_
- **GET** `/api/strategies/:id` - Get strategy details
- **PUT** `/api/strategies/:id` - Update strategy
- **DELETE** `/api/strategies/:id` - Delete strategy

### Backtest Management (6 endpoints)

- **POST** `/api/backtests` - Create backtest
- **GET** `/api/backtests/:id` - Get backtest status
- **GET** `/api/backtests/:id/results` - Get backtest results
- **GET** `/api/backtests/:id/trades` - Get backtest trades
- **POST** `/api/backtests/validate-data` - Validate market data
- **DELETE** `/api/backtests/:id` - Cancel backtest

### Paper Trading (8 endpoints)

- **POST** `/api/paper-trading/sessions` - Create paper session
- **GET** `/api/paper-trading/sessions/:id` - Get session status
- **POST** `/api/paper-trading/sessions/:id/start` - Start session
- **POST** `/api/paper-trading/sessions/:id/stop` - Stop session
- **GET** `/api/paper-trading/sessions/:id/trades` - Get trades
- **GET** `/api/paper-trading/sessions/:id/metrics` - Get metrics
- **GET** `/api/paper-trading/sessions` - List sessions
- **DELETE** `/api/paper-trading/sessions/:id` - Delete session

### Live Trading (10 endpoints)

- **POST** `/api/live-trading/sessions` - Create live session
- **POST** `/api/live-trading/sessions/:id/start` - Start live trading
- **POST** `/api/live-trading/sessions/:id/stop` - Emergency stop
- **GET** `/api/live-trading/sessions/:id` - Get session status
- **POST** `/api/live-trading/sessions/:id/orders` - Place order
- **GET** `/api/live-trading/sessions/:id/orders` - List orders
- **DELETE** `/api/live-trading/sessions/:id/orders/:order_id` - Cancel order
- **GET** `/api/live-trading/sessions/:id/trades` - Get trades
- **GET** `/api/live-trading/sessions` - List sessions
- **POST** `/api/live-trading/sessions/:id/pause` - Pause session

## Testing Workflows

### End-to-End Strategy Testing

```
1. Create Strategy → Extracts strategy_id
2. Create Backtest → Uses {{strategy_id}}, extracts backtest_id
3. Get Backtest Results → Uses {{backtest_id}}
4. Create Paper Session → Uses {{strategy_id}}
5. Start Paper Session → Test in real-time simulation
```

### Running All Tests

```bash
# Option 1: Collection Runner (GUI)
1. Right-click on "Trading Strategy API" collection
2. Click "Run collection"
3. Review test results

# Option 2: Newman CLI
npm install -g newman
newman run trading-strategy-api.postman_collection.json \
  -e localhost-dev.postman_environment.json
```

## Automated Tests

Every request includes automated tests:

```javascript
✅ Status code validation (200, 201, 204, 404, etc.)
✅ Response structure validation (data, errors, fields)
✅ Field type checking (string, number, array, object)
✅ Required field presence (id, name, status, etc.)
✅ Environment variable extraction (strategy_id, backtest_id, etc.)
```

## Troubleshooting

### Issue: "user_id can't be blank"

**Solution**: Ensure `user_id` is set in the environment:
```bash
1. Check environment variables (eye icon, top right)
2. Verify user_id = 1 (or valid user ID)
3. If missing, edit environment and add user_id variable
```

### Issue: "Strategy not found"

**Solution**: Create a strategy first:
```bash
1. Run "Strategy Management → Create Strategy"
2. Verify 201 Created response
3. Check {{strategy_id}} variable is set
4. Try again
```

### Issue: Connection refused

**Solution**: Start the Phoenix server:
```bash
cd /path/to/trading-strategy
mix phx.server
# Verify: Server running at http://localhost:4000
```

### Issue: "a strategy with this name already exists"

**Solution**: Change the strategy name:
```bash
1. Edit "Create Strategy" request
2. Change: "name": "RSI Mean Reversion v2"
3. Send again
```

## Changelog

### Version 1.1.0 (2026-02-09)
- ✨ Added `user_id` support for Admin API
- 📝 Updated collection description to clarify Admin vs Authenticated API
- 🔧 Added `user_id` environment variable (default: 1)
- 📚 Created comprehensive README documentation
- ⚡ All 29 endpoints tested and working

### Version 1.0.0 (2026-01-14)
- 🎉 Initial release with 29 endpoints
- ✅ 100% test coverage with automated scripts
- 🔄 Environment variable chaining for workflows
- 📖 Semi-realistic example data

## Support

For issues or questions:
1. Check `specs/002-postman-api-collection/quickstart.md`
2. Review API documentation at http://localhost:4000/api/docs (if available)
3. Open issue at: https://github.com/rzcastilho/trading-strategy/issues

---

**Ready to test?** Start with "Strategy Management → Create Strategy"! 🚀
