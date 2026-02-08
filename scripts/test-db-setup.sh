#!/bin/bash

# Test Database Setup Script
# Quick setup for Phase 5 integration tests

set -e

echo "🚀 Setting up test database for Phase 5 tests..."
echo ""

# Check if Docker is installed
if ! command -v docker &> /dev/null; then
    echo "❌ Docker not found. Please install Docker or use manual PostgreSQL setup."
    echo "   See TEST_DATABASE_SETUP.md for manual setup instructions."
    exit 1
fi

# Check if docker-compose is available
if command -v docker-compose &> /dev/null; then
    COMPOSE_CMD="docker-compose"
elif docker compose version &> /dev/null; then
    COMPOSE_CMD="docker compose"
else
    echo "❌ docker-compose not found. Please install docker-compose."
    exit 1
fi

echo "✅ Docker found"
echo ""

# Check if port 5433 is already in use
if lsof -Pi :5433 -sTCP:LISTEN -t >/dev/null 2>&1 ; then
    echo "⚠️  Port 5433 is already in use"
    echo ""
    read -p "   Stop existing service on port 5433? (y/N): " -n 1 -r
    echo ""
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        echo "   Attempting to stop existing container..."
        $COMPOSE_CMD -f docker-compose.test.yml down 2>/dev/null || true
    else
        echo "   Please stop the service manually or update config/test.exs to use a different port."
        exit 1
    fi
fi

# Start PostgreSQL container
echo "📦 Starting PostgreSQL container..."
$COMPOSE_CMD -f docker-compose.test.yml up -d

# Wait for PostgreSQL to be ready
echo "⏳ Waiting for PostgreSQL to be ready..."
sleep 3

# Check if container is healthy
for i in {1..30}; do
    if docker exec trading_strategy_test_db pg_isready -U postgres > /dev/null 2>&1; then
        echo "✅ PostgreSQL is ready!"
        break
    fi

    if [ $i -eq 30 ]; then
        echo "❌ PostgreSQL failed to start. Check logs:"
        echo "   docker logs trading_strategy_test_db"
        exit 1
    fi

    echo -n "."
    sleep 1
done
echo ""

# Create and migrate database
echo ""
echo "🗄️  Creating test database..."
MIX_ENV=test mix ecto.create 2>&1 | grep -v "warning:" || true

echo ""
echo "🔄 Running migrations..."
MIX_ENV=test mix ecto.migrate 2>&1 | grep -v "warning:" || true

echo ""
echo "✅ Test database setup complete!"
echo ""
echo "📋 Quick commands:"
echo "   Run Phase 5 tests:         mix test test/trading_strategy/backtesting_test.exs"
echo "   Run ConcurrencyManager:    mix test test/trading_strategy/backtesting/concurrency_manager_test.exs"
echo "   Run all tests:             mix test"
echo "   Stop database:             $COMPOSE_CMD -f docker-compose.test.yml down"
echo "   View logs:                 docker logs trading_strategy_test_db"
echo ""
echo "💡 See TEST_DATABASE_SETUP.md for more details"
