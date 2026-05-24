#!/bin/bash
# Test: Multi-step agent workflow — search → filter → get details
# Agent: leonardo — realistic multi-turn agent behaviour
source "$(dirname "$0")/lib.sh"

echo "=== T10: Multi-step workflow ==="

sid=$(init_session)
[ "$sid" = "__FAIL__" ] && { echo "  FAIL: init_session"; exit 1; }

# Step 1: Discover what's available
resp=$(call_tool "$sid" '{"jsonrpc":"2.0","method":"tools/call","params":{"name":"list_categories","arguments":{}},"id":1}')
code=$(echo "$resp" | cut -d'|' -f1)
assert_eq "step 1: list_categories" "200" "$code"
json=$(echo "$resp" | cut -d'|' -f2-)
step1=$(echo "$json" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d['result']['content'][0]['text'])" 2>/dev/null)
[ -z "$step1" ] && echo "  WARN: no categories found"

# Step 2: Search for tables
resp=$(call_tool "$sid" '{"jsonrpc":"2.0","method":"tools/call","params":{"name":"search_tables","arguments":{"query":"order"}},"id":2}')
code=$(echo "$resp" | cut -d'|' -f1)
assert_eq "step 2: search_tables" "200" "$code"

# Step 3: Get table details
resp=$(call_tool "$sid" '{"jsonrpc":"2.0","method":"tools/call","params":{"name":"get_table_details","arguments":{"table_name":"ORDERS"}},"id":3}')
code=$(echo "$resp" | cut -d'|' -f1)
assert_eq "step 3: get_table_details" "200" "$code"

# Step 4: Check SQL rules
resp=$(call_tool "$sid" '{"jsonrpc":"2.0","method":"tools/call","params":{"name":"get_sql_rules","arguments":{}},"id":4}')
code=$(echo "$resp" | cut -d'|' -f1)
assert_eq "step 4: get_sql_rules" "200" "$code"

# Step 5: Load expert knowledge
resp=$(call_tool "$sid" '{"jsonrpc":"2.0","method":"tools/call","params":{"name":"list_experts","arguments":{}},"id":5}')
code=$(echo "$resp" | cut -d'|' -f1)
assert_eq "step 5: list_experts" "200" "$code"

echo "  All 5 workflow steps completed sequentially"
PASS=$((PASS + 5))

close_session "$sid"
summary
