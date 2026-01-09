#!/bin/bash

# Trading Strategy DSL Library - Phase 4 Integration Test Runner
# This script ensures the environment is ready and runs the integration test

set -e  # Exit on error

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${BLUE}Trading Strategy DSL Library - Phase 4 Test Setup${NC}\n"

# Function to print status
print_status() {
    echo -e "${YELLOW}▶${NC} $1"
}

print_success() {
    echo -e "${GREEN}✓${NC} $1"
}

print_error() {
    echo -e "${RED}✗${NC} $1"
}

# Check if we're in the right directory
if [ ! -f "mix.exs" ]; then
    print_error "Please run this script from the project root directory"
    exit 1
fi

# Check if Elixir is installed
if ! command -v elixir &> /dev/null; then
    print_error "Elixir is not installed. Please install Elixir 1.17+"
    exit 1
fi

print_success "Elixir found: $(elixir --version | grep Elixir)"

# Check if PostgreSQL is accessible
print_status "Checking PostgreSQL connection..."
if mix run -e "TradingStrategy.Repo.query!(\"SELECT 1\")" &> /dev/null; then
    print_success "PostgreSQL is accessible"
else
    print_error "PostgreSQL is not accessible"
    echo ""
    echo "Please ensure PostgreSQL is running. If using Docker:"
    echo "  docker-compose up -d postgres"
    echo ""
    echo "Or start PostgreSQL manually and check config/dev.exs for connection settings"
    exit 1
fi

# Check if dependencies are installed
print_status "Checking dependencies..."
if [ ! -d "deps" ] || [ -z "$(ls -A deps)" ]; then
    print_status "Installing dependencies..."
    mix deps.get
    print_success "Dependencies installed"
else
    print_success "Dependencies already installed"
fi

# Check if database exists
print_status "Checking database..."
if mix run -e "TradingStrategy.Repo.query!(\"SELECT 1\")" &> /dev/null; then
    print_success "Database exists"
else
    print_status "Creating database..."
    mix ecto.create
    print_success "Database created"
fi

# Check if migrations are up to date
print_status "Checking migrations..."
PENDING_MIGRATIONS=$(mix ecto.migrations 2>&1 | grep "down" | wc -l)
if [ "$PENDING_MIGRATIONS" -gt 0 ]; then
    print_status "Running pending migrations..."
    mix ecto.migrate
    print_success "Migrations completed"
else
    print_success "Migrations up to date"
fi

# Compile the project
print_status "Compiling project..."
if mix compile --warnings-as-errors 2>&1 | grep -q "Compiled"; then
    print_success "Project compiled successfully"
elif mix compile &> /dev/null; then
    print_success "Project already compiled"
else
    print_error "Compilation failed"
    echo "Please fix compilation errors before running the test"
    exit 1
fi

echo ""
echo -e "${GREEN}Environment ready!${NC}"
echo ""
echo -e "${BLUE}Running Phase 4 Integration Test...${NC}"
echo ""

# Run the integration test
mix run priv/scripts/test_phase_4.exs

# Capture exit code
EXIT_CODE=$?

echo ""
if [ $EXIT_CODE -eq 0 ]; then
    echo -e "${GREEN}╔════════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${GREEN}║                    TEST PASSED ✓                               ║${NC}"
    echo -e "${GREEN}╚════════════════════════════════════════════════════════════════╝${NC}"
    echo ""
    echo "All Phase 1-4 features are working correctly!"
    echo ""
    echo "Next steps:"
    echo "  1. Review the backtest results above"
    echo "  2. Test the REST API endpoints manually"
    echo "  3. Run additional backtests with different strategies"
    echo "  4. Proceed to Phase 5 implementation (Paper Trading)"
else
    echo -e "${RED}╔════════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${RED}║                    TEST FAILED ✗                               ║${NC}"
    echo -e "${RED}╚════════════════════════════════════════════════════════════════╝${NC}"
    echo ""
    echo "Please review the error messages above and fix any issues."
    echo ""
    echo "Common troubleshooting steps:"
    echo "  1. Check that PostgreSQL is running"
    echo "  2. Verify database migrations: mix ecto.migrate"
    echo "  3. Check logs in logs/ directory"
    echo "  4. Review the test script: priv/scripts/test_phase_4.exs"
fi

exit $EXIT_CODE
