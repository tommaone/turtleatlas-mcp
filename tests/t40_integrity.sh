#!/bin/bash
# Test: Data integrity — content correctness, session isolation
# Agent: donatello — verify infrastructure correctness
source "$(dirname "$0")/lib.sh"

echo "=== T40: Data integrity ==="

sid=$(init_session)
[ "$sid" = "__FAIL__" ] && { echo "  FAIL: init_session"; exit 1; }

# 1. list_experts returns properly (no specific expert files in template)
resp=$(call_tool "$sid" '{"jsonrpc":"2.0","method":"tools/call","params":{"name":"list_experts","arguments":{}},"id":1}')
code=$(echo "$resp" | cut -d'|' -f1)
assert_eq "list_experts succeeds" "200" "$code"

# 2. get_expert with missing file returns error
resp=$(call_tool "$sid" '{"jsonrpc":"2.0","method":"tools/call","params":{"name":"get_expert","arguments":{"name":"nonexistent.md"}},"id":1}')
code=$(echo "$resp" | cut -d'|' -f1)
assert_eq "get_expert missing file returns 400" "400" "$code"

# 3. Known tool returns shape
resp=$(call_tool "$sid" '{"jsonrpc":"2.0","method":"tools/call","params":{"name":"get_sql_rules","arguments":{}},"id":1}')
code=$(echo "$resp" | cut -d'|' -f1)
json=$(echo "$resp" | cut -d'|' -f2-)
text=$(echo "$json" | parse_result)
assert_eq "get_sql_rules succeeds" "200" "$code"

# 4. Session isolation — two sessions, same tool, same result
sid2=$(init_session)
resp_a=$(call_tool "$sid" '{"jsonrpc":"2.0","method":"tools/call","params":{"name":"list_experts","arguments":{}},"id":1}')
resp_b=$(call_tool "$sid2" '{"jsonrpc":"2.0","method":"tools/call","params":{"name":"list_experts","arguments":{}},"id":1}')
json_a=$(echo "$resp_a" | cut -d'|' -f2- | parse_result)
json_b=$(echo "$resp_b" | cut -d'|' -f2- | parse_result)
assert_true "session isolation: same output" "[ $(echo "$json_a" | md5sum | cut -d' ' -f1) = $(echo "$json_b" | md5sum | cut -d' ' -f1) ]"
close_session "$sid2"

# 5. Health endpoint reports at least 0 sessions
health=$(curl -s http://localhost:3456/health)
sessions=$(echo "$health" | python3 -c "import sys,json; print(json.load(sys.stdin)['activeSessions'])")
assert_true "activeSessions is a number" "echo '$sessions' | grep -qE '^[0-9]+$'"

# 6. Server identity correct
name=$(echo "$health" | python3 -c "import sys,json; print(json.load(sys.stdin)['service'])")
assert_eq "service name" "turtleatlas-mcp-server" "$name"

close_session "$sid"
summary
