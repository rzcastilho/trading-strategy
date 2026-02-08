#!/bin/bash

# Test Database Teardown Script
# Clean shutdown of test database

set -e

echo "🧹 Cleaning up test database..."
echo ""

# Check if docker-compose is available
if command -v docker-compose &> /dev/null; then
    COMPOSE_CMD="docker-compose"
elif docker compose version &> /dev/null 2>&1; then
    COMPOSE_CMD="docker compose"
else
    echo "❌ docker-compose not found"
    exit 1
fi

# Ask for confirmation
read -p "Remove test database and data? (y/N): " -n 1 -r
echo ""

if [[ $REPLY =~ ^[Yy]$ ]]; then
    echo "🗑️  Stopping container and removing data..."
    $COMPOSE_CMD -f docker-compose.test.yml down -v
    echo "✅ Test database removed"
else
    echo "🛑 Stopping container (keeping data)..."
    $COMPOSE_CMD -f docker-compose.test.yml down
    echo "✅ Container stopped (data preserved)"
fi

echo ""
echo "💡 To restart: ./scripts/test-db-setup.sh"
