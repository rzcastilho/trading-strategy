# Quickstart Guide: Trading Strategy API Postman Collection

**Feature**: 002-postman-api-collection
**Date**: 2026-01-14

## Overview

This guide will help you import and start using the Trading Strategy API Postman Collection within 10 minutes. You'll be able to test all API endpoints for strategy management, backtesting, paper trading, and live trading operations.

---

## Prerequisites

1. **Postman Installed**: Download from [postman.com](https://www.postman.com/downloads/) (desktop or web version)
2. **API Server Running**: Trading Strategy API must be running at `http://localhost:4000`
   - To start the server: `cd /path/to/trading-strategy && mix phx.server`
3. **No Authentication Required**: This collection assumes unauthenticated local development access

---

## Step 1: Import the Collection (1 minute)

### Option A: Import from File
1. Open Postman
2. Click **Import** button (top left)
3. Select **File** tab
4. Navigate to `postman/trading-strategy-api.postman_collection.json`
5. Click **Import**

### Option B: Import from URL (if hosted)
1. Click **Import** button
2. Select **Link** tab
3. Paste the collection URL
4. Click **Continue** → **Import**

**Expected Result**: You should see a new collection named "Trading Strategy API" in your Collections sidebar with 4 folders.

---

## Step 2: Verify Environment Setup (30 seconds)

The collection includes built-in variables, so no separate environment import is needed.

### Verify Collection Variables
1. Click on the "Trading Strategy API" collection
2. Go to **Variables** tab
3. Confirm these variables exist:
   - `base_url` = `http://localhost:4000`
   - `port` = `4000`

**Optional**: If you prefer using a separate environment:
- Import `postman/localhost-dev.postman_environment.json` (if provided)
- Select "Trading Strategy - Localhost" from the environment dropdown (top right)

---

## Step 3: Test the Connection (1 minute)

Let's verify the API is accessible.

1. Expand the **Strategy Management** folder
2. Click on **List Strategies** request
3. Click **Send** button

**Expected Response**:
- Status: `200 OK`
- Body: `{"data": [...]}`
- Test Results: All tests passing (green checkmarks)

**If you see an error**:
- ❌ "Could not get response" → API server is not running
- ❌ "ECONNREFUSED" → Check that `base_url` is correct
- ❌ 404 Not Found → API routes may not be implemented yet

---

## Step 4: End-to-End Workflow (5 minutes)

Follow this guided workflow to create a strategy, run a backtest, and start paper trading.

### 4.1 Create a Strategy

1. Go to **Strategy Management** → **Create Strategy**
2. Click **Send**

**What happens**:
- Request sends a semi-realistic RSI strategy example
- Response returns the created strategy with a UUID
- Test scripts automatically extract `strategy_id` to environment

**Verify**: Check the **Environment** quick look (eye icon, top right) and confirm `strategy_id` now has a value.

---

### 4.2 Get the Strategy

1. Go to **Strategy Management** → **Get Strategy by ID**
2. Notice the URL uses `{{strategy_id}}` (from previous step)
3. Click **Send**

**Expected Response**:
- Status: `200 OK`
- Body contains the full strategy details (including DSL content)

---

### 4.3 Run a Backtest

1. Go to **Backtest Management** → **Create Backtest**
2. Notice the request body uses `"strategy_id": "{{strategy_id}}"`
3. Click **Send**

**What happens**:
- Backtest starts running against 2 years of historical data
- Response includes `backtest_id` and `status: "running"`
- Test scripts extract `backtest_id` to environment

---

### 4.4 Check Backtest Progress

1. Go to **Backtest Management** → **Get Backtest Progress**
2. Click **Send**
3. Repeat every few seconds to watch progress

**Expected Response**:
```json
{
  "backtest_id": "...",
  "status": "running",
  "progress_percentage": 45,
  "bars_processed": 6570,
  "total_bars": 14600,
  "estimated_time_remaining_ms": 12000
}
```

**Wait until** `status: "completed"` and `progress_percentage: 100`

---

### 4.5 Get Backtest Results

1. Go to **Backtest Management** → **Get Backtest Results**
2. Click **Send**

**Expected Response**:
- Performance metrics: Sharpe ratio, max drawdown, win rate, total return
- Trade history array
- Equity curve data

**Example Metrics**:
```json
{
  "performance_metrics": {
    "total_return": "0.342",
    "sharpe_ratio": "1.8",
    "max_drawdown": "0.12",
    "win_rate": "0.65",
    "trade_count": 50
  }
}
```

---

### 4.6 Start Paper Trading

1. Go to **Paper Trading** → **Create Session**
2. Notice it uses `{{strategy_id}}`
3. Click **Send**

**What happens**:
- Paper trading session starts with $10,000 virtual capital
- Response includes `session_id`
- Test scripts extract `paper_session_id` to environment

---

### 4.7 Monitor Paper Trading

1. Go to **Paper Trading** → **Get Session Status**
2. Click **Send** to see current session state

**Expected Response**:
```json
{
  "data": {
    "session_id": "...",
    "status": "active",
    "current_equity": "10500.00",
    "unrealized_pnl": "300.00",
    "realized_pnl": "200.00",
    "open_positions": [...],
    "trades_count": 5
  }
}
```

---

### 4.8 View Trade History

1. Go to **Paper Trading** → **Get Trade History**
2. Click **Send**

**Expected Response**: Array of executed trades with timestamps, prices, quantities, and P&L.

---

### 4.9 Pause the Session (Optional)

1. Go to **Paper Trading** → **Pause Session**
2. Click **Send**
3. Verify status changes to `"paused"`

To resume:
1. Go to **Paper Trading** → **Resume Session**
2. Click **Send**

---

## Step 5: Explore Other Endpoints (2 minutes)

### Update a Strategy
1. Go to **Strategy Management** → **Update Strategy**
2. Modify the request body (e.g., change `timeframe` from `"1h"` to `"4h"`)
3. Click **Send**

### Validate Historical Data
1. Go to **Backtest Management** → **Validate Historical Data**
2. Click **Send**
3. Review data quality warnings (gaps, missing bars)

### Live Trading (Caution!)
**⚠️ Important**: Live trading endpoints use **testnet mode** by default with placeholder credentials. Do NOT use real API keys in this collection.

1. Go to **Live Trading** → **Create Session**
2. Review the risk limits in the request body
3. **Only send if you have testnet credentials**

---

## Understanding Test Scripts

Every request includes automated test scripts that validate responses.

### View Test Results
1. Send any request
2. Click **Test Results** tab (bottom panel)
3. See green checkmarks for passing tests

**Example Tests**:
- ✅ Status code is 200
- ✅ Response contains data field
- ✅ Response has required fields with correct types
- ✅ Extract ID to environment

### Why Tests Matter
- **Immediate Feedback**: Know instantly if API responses are valid
- **No Manual Checking**: Tests validate field presence and types automatically
- **Request Chaining**: Extracted IDs enable end-to-end workflows

---

## Common Use Cases

### Use Case 1: Test a New Strategy
1. Create Strategy → Get Strategy → Create Backtest → Get Results
2. **Time**: ~2-5 minutes (depending on backtest duration)

### Use Case 2: Debug Strategy Performance
1. Get Backtest Results → Review trade history
2. Adjust strategy parameters → Create new backtest
3. Compare metrics

### Use Case 3: Paper Trade Before Live
1. Create Strategy → Run Backtest (verify profitability)
2. Start Paper Trading → Monitor for 30 days
3. If successful → Consider live trading (with extreme caution)

### Use Case 4: Monitor Active Sessions
1. List Sessions (paper or live)
2. Get Session Status → Get Trade History → Get Metrics
3. Pause/Resume as needed

---

## Tips and Best Practices

### Tip 1: Use Collection Runner for Sequential Tests
1. Right-click on **Strategy Management** folder
2. Select **Run folder**
3. All 5 requests execute in order

**Benefit**: Quickly test all CRUD operations for strategies.

### Tip 2: Customize Example Data
- Edit request bodies to test your own strategy DSL
- Change `trading_pair` (e.g., `"ETH/USD"`)
- Adjust `timeframe` (e.g., `"4h"`, `"1d"`)

### Tip 3: Save Responses as Examples
1. Send a request
2. Click **Save Response** → **Save as Example**
3. Adds to collection for documentation

### Tip 4: Use Variables for Multiple Environments
Create environments for:
- Local development (`http://localhost:4000`)
- Staging server (`https://staging.example.com`)
- Production (if safe to test)

### Tip 5: Check Console for Debugging
1. Open Postman Console (bottom left, console icon)
2. See all requests, responses, and test script logs
3. Useful for debugging test failures

---

## Troubleshooting

### Problem: "Could not get response"
**Solution**:
1. Verify API server is running: `curl http://localhost:4000/api/strategies`
2. Check server logs for errors
3. Confirm port 4000 is not blocked by firewall

### Problem: "Cannot read property 'id' of undefined"
**Cause**: Test scripts expect a `data` field in response, but API returned error.

**Solution**:
1. Check response body for error messages
2. Verify request body is valid JSON
3. Ensure required fields are present

### Problem: Tests Failing with 404
**Cause**: API endpoints may not be implemented yet.

**Solution**:
1. Check Phoenix router to confirm endpoint exists
2. Verify URL pattern matches (e.g., `/api/strategies/:id` vs `/api/strategy/:id`)
3. Review server logs for routing errors

### Problem: UUID Not Extracted to Environment
**Cause**: Test script expects different response structure.

**Solution**:
1. Check response body structure
2. Adjust test script path (e.g., `jsonData.data.id` vs `jsonData.id`)
3. Manually set environment variable for testing

### Problem: Backtest Never Completes
**Cause**: Server may not have historical data or backtest engine not running.

**Solution**:
1. Try **Validate Historical Data** endpoint first
2. Check server logs for backtest errors
3. Reduce date range (e.g., 1 month instead of 2 years)

---

## Next Steps

### Beginner: Learn the API
- Explore all 29 endpoints across 4 folders
- Read request descriptions for each endpoint
- Review example responses

### Intermediate: Customize the Collection
- Modify test scripts to add custom validations
- Create pre-request scripts to generate dynamic data
- Save multiple response examples (success, edge cases)

### Advanced: Automate with Newman
1. Install Newman CLI: `npm install -g newman`
2. Run collection from command line:
   ```bash
   newman run trading-strategy-api.postman_collection.json \
     --environment localhost-dev.postman_environment.json
   ```
3. Integrate into CI/CD pipeline

### Expert: Performance Testing
- Use Postman monitors to run tests on schedule
- Track API response times over time
- Set up alerts for failing tests

---

## Collection Statistics

- **Total Endpoints**: 29
- **Folders**: 4 (Strategy Management, Backtest Management, Paper Trading, Live Trading)
- **Test Assertions**: ~90-110 across all requests
- **Variables**: 7 (base_url, port, strategy_id, backtest_id, paper_session_id, live_session_id, order_id)
- **Example Responses**: 29 (1 per request)

---

## Support

### Documentation
- **Feature Spec**: `specs/002-postman-api-collection/spec.md`
- **Data Model**: `specs/002-postman-api-collection/data-model.md`
- **Research**: `specs/002-postman-api-collection/research.md`

### API Documentation
- **Phoenix Router**: `lib/trading_strategy_web/router.ex`
- **Controllers**: `lib/trading_strategy_web/controllers/`
- **Local Endpoint**: `http://localhost:4000/` (may have API docs)

### Questions?
- Check the description field on each request
- Review example responses
- Inspect test scripts for validation logic

---

**Congratulations!** You've completed the quickstart guide. You can now test all Trading Strategy API endpoints using Postman. Happy testing! 🚀
