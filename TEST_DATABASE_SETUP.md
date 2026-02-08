# Test Database Setup Guide

Quick guide to set up the PostgreSQL database for running Phase 5 integration tests.

## Prerequisites

- Docker installed (recommended), OR
- PostgreSQL installed locally

## Option 1: Docker Setup (Recommended)

### Start Test Database

```bash
# Start PostgreSQL container on port 5433
docker-compose -f docker-compose.test.yml up -d

# Wait for database to be ready (usually 5-10 seconds)
docker-compose -f docker-compose.test.yml ps

# Verify connection
docker exec trading_strategy_test_db pg_isready -U postgres
```

### Create and Migrate Database

```bash
# Create the test database
MIX_ENV=test mix ecto.create

# Run migrations
MIX_ENV=test mix ecto.migrate
```

### Run Tests

```bash
# Run all Phase 5 integration tests
mix test test/trading_strategy/backtesting_test.exs

# Run only concurrent backtest tests
mix test test/trading_strategy/backtesting_test.exs:183

# Run only restart detection tests
mix test test/trading_strategy/backtesting_test.exs:397

# Run ConcurrencyManager unit tests
mix test test/trading_strategy/backtesting/concurrency_manager_test.exs
```

### Stop Test Database

```bash
# Stop and remove container (keeps data)
docker-compose -f docker-compose.test.yml down

# Stop and remove container + data
docker-compose -f docker-compose.test.yml down -v
```

## Option 2: Local PostgreSQL Setup

### Prerequisites

- PostgreSQL 12+ installed locally
- PostgreSQL running on port 5433, OR update `config/test.exs` to use your port

### Create Database

```bash
# Create PostgreSQL user (if needed)
createuser -s postgres

# Create test database
createdb -U postgres trading_strategy_test

# Run migrations
MIX_ENV=test mix ecto.migrate
```

### Update Configuration (if using different port)

Edit `config/test.exs`:

```elixir
config :trading_strategy, TradingStrategy.Repo,
  username: "postgres",
  password: "postgres",
  hostname: "localhost",
  port: 5432,  # Change to your PostgreSQL port
  database: "trading_strategy_test#{System.get_env("MIX_TEST_PARTITION")}",
  pool: Ecto.Adapters.SQL.Sandbox,
  pool_size: System.schedulers_online() * 2
```

## Troubleshooting

### Port Already in Use

If port 5433 is already in use:

```bash
# Check what's using port 5433
lsof -i :5433

# Option 1: Stop the conflicting service
# Option 2: Use a different port in docker-compose.test.yml and config/test.exs
```

### Connection Refused

```bash
# Check if container is running
docker ps | grep trading_strategy_test_db

# Check container logs
docker logs trading_strategy_test_db

# Restart container
docker-compose -f docker-compose.test.yml restart
```

### Permission Denied

```bash
# Ensure PostgreSQL user has proper permissions
docker exec trading_strategy_test_db psql -U postgres -c "ALTER USER postgres WITH SUPERUSER;"
```

### Database Already Exists

```bash
# Drop and recreate
MIX_ENV=test mix ecto.drop
MIX_ENV=test mix ecto.create
MIX_ENV=test mix ecto.migrate
```

## Running Full Test Suite

Once the database is set up:

```bash
# Run all tests
mix test

# Run with coverage report
mix test --cover

# Run only Phase 5 tests
mix test test/trading_strategy/backtesting_test.exs test/trading_strategy/backtesting/

# Run tests in verbose mode
mix test --trace
```

## Expected Test Results

### ConcurrencyManager Tests
- **Expected**: 14/15 passing (1 fails due to DB connection in unit test context)
- **File**: `test/trading_strategy/backtesting/concurrency_manager_test.exs`

### Integration Tests
- **Expected**: All passing with database running
- **Tests**: 3 concurrent backtest tests + 3 restart detection tests
- **File**: `test/trading_strategy/backtesting_test.exs`

## Test Configuration

The test suite uses these settings (from `config/test.exs`):

```elixir
config :trading_strategy,
  # Test mode prevents actual backtest execution
  backtest_test_mode: false,
  # Low concurrency limit for testing (3 concurrent backtests)
  max_concurrent_backtests: 3
```

## Quick Commands Reference

```bash
# Full setup (Docker)
docker-compose -f docker-compose.test.yml up -d
MIX_ENV=test mix ecto.setup
mix test

# Reset database
MIX_ENV=test mix ecto.reset

# Clean shutdown
docker-compose -f docker-compose.test.yml down -v
```

## CI/CD Integration

For GitHub Actions or other CI systems:

```yaml
services:
  postgres:
    image: postgres:15-alpine
    env:
      POSTGRES_USER: postgres
      POSTGRES_PASSWORD: postgres
      POSTGRES_DB: trading_strategy_test
    ports:
      - 5433:5432
    options: >-
      --health-cmd pg_isready
      --health-interval 10s
      --health-timeout 5s
      --health-retries 5
```

## Next Steps

After database is running and tests pass:
1. ✅ Phase 5 (User Story 3) complete
2. 🎯 Ready for Phase 6 (User Story 4 - Trade Analytics)
3. 🚀 Or deploy Phase 5 to staging for validation
