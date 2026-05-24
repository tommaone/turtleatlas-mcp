#!/bin/bash
# turtleatlas-mcp Test Portfolio Runner
#
# Runs the full test suite against a running MCP server.
# Usage:
#   ./tests/run.sh                         # run all tests
#   ./tests/run.sh t01 t02                 # run specific infrastructure tests
#   ./tests/run.sh expert/grey-knights     # run a specific content test
#   SERVER=http://other:3456/mcp ./tests/run.sh   # custom server URL
set -euo pipefail

SERVER="${SERVER:-http://localhost:3456/mcp}"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
TOTAL_PASS=0
TOTAL_FAIL=0
TIMING=""

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

check_server() {
  if ! curl -sf http://localhost:3456/health > /dev/null 2>&1; then
    echo -e "${RED}ERROR:${NC} MCP server not running on localhost:3456"
    echo "  Start it first:"
    echo "    cd $(dirname "$SCRIPT_DIR") && node index.js --port=3456"
    exit 1
  fi
}

run_test() {
  local script="$1"
  local name=$(basename "$script" .sh)
  local start=$(date +%s%N)

  echo ""
  echo -e "${CYAN}━━━ ${name} ━━━${NC}"

  local output
  output=$("$script" 2>&1)
  local exit_code=$?
  local end=$(date +%s%N)
  local elapsed=$(( (end - start) / 1000000 ))

  # Count pass/fail from output
  local p=$(echo "$output" | grep -c '^  PASS:' || true)
  local f=$(echo "$output" | grep -c '^  FAIL:' || true)
  TOTAL_PASS=$((TOTAL_PASS + p))
  TOTAL_FAIL=$((TOTAL_FAIL + f))

  echo "$output"
  TIMING="${TIMING}  ${name}: ${elapsed}ms (${p}p/${f}f)\n"

  if [ "$exit_code" -ne 0 ] && [ "$f" -eq 0 ]; then
    # Script crashed without reporting FAIL
    echo -e "  ${RED}CRASHED (exit code $exit_code)${NC}"
  fi
}

# Parse test selection
if [ $# -gt 0 ]; then
  tests=()
  for arg in "$@"; do
    tests+=("$SCRIPT_DIR/${arg}.sh")
  done
else
  # Run infrastructure tests + all per-expert content tests
  tests=("$SCRIPT_DIR"/t*.sh)
  for f in "$SCRIPT_DIR"/expert/*.sh; do
    [ -f "$f" ] && tests+=("$f")
  done
fi

echo "═══════════════════════════════════════════"
echo " turtleatlas-mcp Test Portfolio"
echo " Server: $SERVER"
echo " Tests:  ${#tests[@]}"
echo "═══════════════════════════════════════════"

check_server

overall_start=$(date +%s%N)
for test in "${tests[@]}"; do
  if [ -f "$test" ]; then
    run_test "$test"
  else
    echo -e "${RED}Test not found:${NC} $test"
  fi
done
overall_end=$(date +%s%N)
overall_ms=$(( (overall_end - overall_start) / 1000000 ))

echo ""
echo "═══════════════════════════════════════════"
echo -e " RESULTS"
echo "═══════════════════════════════════════════"
echo -e "$TIMING"
echo " Total:  ${TOTAL_PASS} passed, ${TOTAL_FAIL} failed"
echo " Time:   ${overall_ms}ms"
echo "═══════════════════════════════════════════"

if [ "$TOTAL_FAIL" -eq 0 ]; then
  echo -e "${GREEN}ALL TESTS PASSED${NC}"
  exit 0
else
  echo -e "${RED}SOME TESTS FAILED${NC}"
  exit 1
fi
