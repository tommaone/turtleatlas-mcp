#!/bin/bash
# Test: Error handling — bad sessions, bad params, missing files
# Agent: shredder — devils advocate, find edge cases
source "$(dirname "$0")/lib.sh"

echo "=== T30: Error handling & edge cases ==="

# 1. Health endpoint
code=$(curl -s -o /dev/null -w "%{http_code}" http://localhost:3456/health)
assert_eq "health endpoint" "200" "$code"

# 2. No session ID on tool call
resp=$(curl -s -w '\n%{http_code}' -X POST "$SERVER" \
  -H "Content-Type: application/json" \
  -H "Accept: application/json, text/event-stream" \
  -d '{"jsonrpc":"2.0","method":"tools/call","params":{"name":"list_experts","arguments":{}},"id":1}')
code=$(echo "$resp" | tail -1)
assert_eq "no session ID -> 400" "400" "$code"

# 3. Wrong session ID
resp=$(curl -s -w '\n%{http_code}' -X POST "$SERVER" \
  -H "Content-Type: application/json" \
  -H "Accept: application/json, text/event-stream" \
  -H "mcp-session-id: 00000000-0000-0000-0000-000000000000" \
  -d '{"jsonrpc":"2.0","method":"tools/call","params":{"name":"list_experts","arguments":{}},"id":1}')
code=$(echo "$resp" | tail -1)
assert_eq "wrong session ID -> 400" "400" "$code"

# 4. Missing tool name
sid=$(init_session)
[ "$sid" = "__FAIL__" ] && { echo "  FAIL: init_session"; exit 1; }

resp=$(call_tool "$sid" '{"jsonrpc":"2.0","method":"tools/call","params":{"name":"","arguments":{}},"id":1}')
json=$(echo "$resp" | cut -d'|' -f2-)
err=$(echo "$json" | parse_error)
assert_contains "missing tool name" "Unknown tool" "$err"

# 5. Nonexistent expert
resp=$(call_tool "$sid" '{"jsonrpc":"2.0","method":"tools/call","params":{"name":"get_expert","arguments":{"name":"not-here.md"}},"id":1}')
json=$(echo "$resp" | cut -d'|' -f2-)
err=$(echo "$json" | parse_error)
assert_contains "nonexistent expert" "not found" "$err"

# 6. Nonexistent table
resp=$(call_tool "$sid" '{"jsonrpc":"2.0","method":"tools/call","params":{"name":"get_table_details","arguments":{"table_name":"FAKE_TABLE"}},"id":1}')
json=$(echo "$resp" | cut -d'|' -f2-)
text=$(echo "$json" | parse_result)
assert_contains "nonexistent table" "not found" "$text"

# 7. Missing required params
resp=$(call_tool "$sid" '{"jsonrpc":"2.0","method":"tools/call","params":{"name":"get_expert","arguments":{}},"id":1}')
json=$(echo "$resp" | cut -d'|' -f2-)
err=$(echo "$json" | parse_error)
assert_contains "missing name param" "required" "$err"

# 8. Invalid JSON-RPC (malformed)
resp=$(curl -s -w '\n%{http_code}' -X POST "$SERVER" \
  -H "Content-Type: application/json" \
  -H "Accept: application/json, text/event-stream" \
  -H "mcp-session-id: $sid" \
  -d 'not json')
code=$(echo "$resp" | tail -1)
assert_eq "malformed JSON -> 400" "400" "$code"

# 9. Reuse session ID for multiple calls
resp1=$(call_tool "$sid" '{"jsonrpc":"2.0","method":"tools/call","params":{"name":"list_experts","arguments":{}},"id":1}')
code1=$(echo "$resp1" | cut -d'|' -f1)
resp2=$(call_tool "$sid" '{"jsonrpc":"2.0","method":"tools/call","params":{"name":"list_experts","arguments":{}},"id":2}')
code2=$(echo "$resp2" | cut -d'|' -f1)
assert_eq "session reuse: call 1" "200" "$code1"
assert_eq "session reuse: call 2" "200" "$code2"

# 10. Delete with wrong session ID
code=$(curl -s -o /dev/null -w "%{http_code}" -X DELETE "$SERVER" \
  -H "mcp-session-id: 00000000-0000-0000-0000-000000000000")
assert_eq "delete wrong session -> 400" "400" "$code"

close_session "$sid"
summary
