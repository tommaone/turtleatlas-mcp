#!/bin/bash
# Test: Session memory leak detection
# Agent: shredder — catch drift, verify cleanup
source "$(dirname "$0")/lib.sh"

echo "=== T50: Session cleanup & memory ==="

base=$(curl -s http://localhost:3456/health | python3 -c "import sys,json; print(json.load(sys.stdin)['activeSessions'])")
echo "  Baseline sessions: $base"

# Spawn 5 sessions, verify count goes up by 5
sids=()
for i in $(seq 1 5); do
  sid=$(init_session)
  [ "$sid" = "__FAIL__" ] && { echo "  FAIL: init_session $i"; FAIL=$((FAIL + 1)); continue; }
  sids+=("$sid")
done
count_after=$(curl -s http://localhost:3456/health | python3 -c "import sys,json; print(json.load(sys.stdin)['activeSessions'])")
expected=$((base + 5))
assert_eq "sessions increase by 5" "$expected" "$count_after"

# Close all, verify count returns to baseline
for sid in "${sids[@]}"; do
  close_session "$sid"
done
count_clean=$(curl -s http://localhost:3456/health | python3 -c "import sys,json; print(json.load(sys.stdin)['activeSessions'])")
assert_eq "sessions return to baseline" "$base" "$count_clean"

# Double delete is safe (should 400, not crash)
code=$(curl -s -o /dev/null -w "%{http_code}" -X DELETE "$SERVER" \
  -H "mcp-session-id: 00000000-0000-0000-0000-000000000000")
assert_eq "double delete returns 400" "400" "$code"

# Server still healthy after all that
code=$(curl -s -o /dev/null -w "%{http_code}" http://localhost:3456/health)
assert_eq "server still healthy after cleanup" "200" "$code"

summary
