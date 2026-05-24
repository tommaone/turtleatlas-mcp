#!/bin/bash
# Test: Basic health check and server reachability
# Agent: raphael — fast, direct, gets it done
source "$(dirname "$0")/lib.sh"

echo "=== T01: Basic health & server reachability ==="

# 1. Health endpoint responds
code=$(curl -s -o /dev/null -w "%{http_code}" http://localhost:3456/health)
assert_eq "health endpoint HTTP 200" "200" "$code"

# 2. Health body is valid JSON
body=$(curl -s http://localhost:3456/health)
assert_true "health body is valid JSON" "echo '$body' | python3 -m json.tool > /dev/null 2>&1"

# 3. Health reports status healthy
status=$(echo "$body" | python3 -c "import sys,json; print(json.load(sys.stdin)['status'])")
assert_eq "status is healthy" "healthy" "$status"

# 4. Health reports transport type
transport=$(echo "$body" | python3 -c "import sys,json; print(json.load(sys.stdin)['transport'])")
assert_eq "transport is Streamable HTTP" "Streamable HTTP" "$transport"

# 5. MCP endpoint exists (no session returns 400, which proves it's reachable)
code=$(curl -s -o /dev/null -w "%{http_code}" -X POST "$SERVER" \
  -H "Content-Type: application/json" \
  -H "Accept: application/json, text/event-stream" \
  -d '{}')
assert_eq "MCP endpoint reachable (400 = listening)" "400" "$code"

summary
