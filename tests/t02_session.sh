#!/bin/bash
# Test: Session lifecycle — init, call tools, delete, cleanup
# Agent: donatello — infrastructure verification
source "$(dirname "$0")/lib.sh"

echo "=== T02: Session lifecycle ==="

before=$(curl -s http://localhost:3456/health | python3 -c "import sys,json; print(json.load(sys.stdin)['activeSessions'])")

# 1. Init creates session
sid=$(init_session)
[ "$sid" = "__FAIL__" ] && { echo "  FAIL: init_session"; FAIL=$((FAIL + 1)); summary; exit 1; }
assert_true "session ID is UUID format" "echo '$sid' | grep -qE '^[0-9a-f-]{36}$'"

after_init=$(curl -s http://localhost:3456/health | python3 -c "import sys,json; print(json.load(sys.stdin)['activeSessions'])")
assert_true "session count increased" "[ $after_init -gt $before ]"

# 2. Call a tool with valid session
resp=$(call_tool "$sid" '{"jsonrpc":"2.0","method":"tools/list","params":{},"id":1}')
code=$(echo "$resp" | cut -d'|' -f1)
assert_eq "tools/list with valid session" "200" "$code"

# 3. Reuse session for another call
resp2=$(call_tool "$sid" '{"jsonrpc":"2.0","method":"tools/call","params":{"name":"list_experts","arguments":{}},"id":2}')
code2=$(echo "$resp2" | cut -d'|' -f1)
assert_eq "second call with same session" "200" "$code2"

# 4. Delete session
close_session "$sid"
after_delete=$(curl -s http://localhost:3456/health | python3 -c "import sys,json; print(json.load(sys.stdin)['activeSessions'])")
assert_true "session count decreased after delete" "[ $after_delete -lt $after_init ]"

# 5. Tool call after delete fails
resp3=$(curl -s -w '\n%{http_code}' -X POST "$SERVER" \
  -H "Content-Type: application/json" \
  -H "Accept: application/json, text/event-stream" \
  -H "mcp-session-id: $sid" \
  -d '{"jsonrpc":"2.0","method":"tools/list","params":{},"id":1}')
code3=$(echo "$resp3" | tail -1)
assert_eq "call after delete -> 400" "400" "$code3"

# 6. Init again still works (new session)
sid2=$(init_session)
[ -n "$sid2" ] && assert_true "re-init creates new session" "echo '$sid2' | grep -qE '^[0-9a-f-]{36}$'"
close_session "$sid2"

summary
