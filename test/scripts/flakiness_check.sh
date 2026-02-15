#!/usr/bin/env bash
#
# Flakiness Validation Script for Strategy Editor Synchronization Tests
#
# Purpose: Verify 0% flakiness rate by running tests 10 consecutive times (SC-011, FR-020)
#
# Usage:
#   ./test/scripts/flakiness_check.sh
#   ./test/scripts/flakiness_check.sh --runs 20       # Custom run count
#   ./test/scripts/flakiness_check.sh --only benchmark # Only benchmark tests
#
# Exit Codes:
#   0 - All runs passed (0% flakiness)
#   1 - One or more runs failed (flaky tests detected)
#
# Success Criteria:
#   SC-011: 0% flakiness rate over 10 consecutive test suite runs
#   FR-020: Fail-fast strategy with no automatic retries
#

set -euo pipefail

# Configuration
RUNS=${1:-10}
TEST_PATH="test/trading_strategy_web/live/strategy_editor_live/"
TIMESTAMP=$(date +"%Y%m%d_%H%M%S")
LOG_DIR="test/scripts/flakiness_logs"
SUMMARY_FILE="${LOG_DIR}/flakiness_summary_${TIMESTAMP}.txt"

# Parse arguments
EXTRA_ARGS=""
if [[ "${2:-}" == "--only" ]] && [[ -n "${3:-}" ]]; then
  EXTRA_ARGS="--only ${3}"
fi

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Create log directory
mkdir -p "$LOG_DIR"

echo -e "${BLUE}============================================================${NC}"
echo -e "${BLUE}Flakiness Validation: Strategy Editor Synchronization Tests${NC}"
echo -e "${BLUE}============================================================${NC}"
echo ""
echo "Configuration:"
echo "  Runs:       ${RUNS}"
echo "  Test Path:  ${TEST_PATH}"
echo "  Extra Args: ${EXTRA_ARGS:-none}"
echo "  Log Dir:    ${LOG_DIR}"
echo ""
echo -e "${BLUE}------------------------------------------------------------${NC}"
echo ""

# Track results
PASSED_RUNS=0
FAILED_RUNS=0
FAILED_RUN_NUMBERS=()

# Run tests N times
for i in $(seq 1 "$RUNS"); do
  echo -e "${YELLOW}=== Run ${i}/${RUNS} ===${NC}"

  # Log file for this run
  RUN_LOG="${LOG_DIR}/run_${i}_${TIMESTAMP}.log"

  # Run tests and capture output
  if MIX_ENV=test mix test ${EXTRA_ARGS} "$TEST_PATH" > "$RUN_LOG" 2>&1; then
    echo -e "${GREEN}✓ Run ${i} PASSED${NC}"
    PASSED_RUNS=$((PASSED_RUNS + 1))
  else
    echo -e "${RED}✗ Run ${i} FAILED${NC}"
    FAILED_RUNS=$((FAILED_RUNS + 1))
    FAILED_RUN_NUMBERS+=("$i")

    # FR-020: Fail-fast strategy - optionally exit on first failure
    # Uncomment to enable fail-fast:
    # echo -e "${RED}Fail-fast enabled. Exiting on first failure.${NC}"
    # exit 1
  fi

  echo ""
done

# Calculate flakiness rate
FLAKINESS_RATE=$(awk "BEGIN {print ($FAILED_RUNS / $RUNS) * 100}")

# Generate summary report
{
  echo "============================================================"
  echo "Flakiness Validation Report"
  echo "============================================================"
  echo ""
  echo "Timestamp: $(date)"
  echo "Test Path: ${TEST_PATH}"
  echo "Extra Args: ${EXTRA_ARGS:-none}"
  echo ""
  echo "Results:"
  echo "  Total Runs:    ${RUNS}"
  echo "  Passed Runs:   ${PASSED_RUNS}"
  echo "  Failed Runs:   ${FAILED_RUNS}"
  echo "  Flakiness Rate: ${FLAKINESS_RATE}%"
  echo ""
  echo "Success Criteria:"
  echo "  SC-011 Target: 0% flakiness rate"
  if (( FAILED_RUNS == 0 )); then
    echo "  SC-011 Status: ✓ PASSED"
  else
    echo "  SC-011 Status: ✗ FAILED"
  fi
  echo ""

  if (( FAILED_RUNS > 0 )); then
    echo "Failed Run Numbers: ${FAILED_RUN_NUMBERS[*]}"
    echo ""
    echo "Failed Run Logs:"
    for run_num in "${FAILED_RUN_NUMBERS[@]}"; do
      echo "  - ${LOG_DIR}/run_${run_num}_${TIMESTAMP}.log"
    done
    echo ""
    echo "Action Required:"
    echo "  1. Review failed run logs for error details"
    echo "  2. Identify non-deterministic test behavior:"
    echo "     - Timing issues (missing render_async, Wallaby waits)"
    echo "     - Shared state (EditHistory session IDs, database leakage)"
    echo "     - Race conditions (concurrent async operations)"
    echo "  3. Fix root cause (do not add retries - FR-020)"
    echo "  4. Re-run flakiness validation to verify fix"
  fi

  echo ""
  echo "Logs saved to: ${LOG_DIR}/"
  echo "============================================================"
} | tee "$SUMMARY_FILE"

# Print summary to console
echo ""
echo -e "${BLUE}============================================================${NC}"
echo -e "${BLUE}Final Summary${NC}"
echo -e "${BLUE}============================================================${NC}"
echo ""

if (( FAILED_RUNS == 0 )); then
  echo -e "${GREEN}✓ SUCCESS: All ${RUNS} runs passed${NC}"
  echo -e "${GREEN}✓ SC-011: 0% flakiness rate achieved${NC}"
  echo ""
  echo "Summary report saved to: ${SUMMARY_FILE}"
  exit 0
else
  echo -e "${RED}✗ FAILURE: ${FAILED_RUNS}/${RUNS} runs failed${NC}"
  echo -e "${RED}✗ SC-011: ${FLAKINESS_RATE}% flakiness rate (target: 0%)${NC}"
  echo ""
  echo "Failed runs: ${FAILED_RUN_NUMBERS[*]}"
  echo "Summary report saved to: ${SUMMARY_FILE}"
  echo ""
  echo "Review logs and fix non-deterministic behavior."
  exit 1
fi
