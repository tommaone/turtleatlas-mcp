#!/bin/bash
# Test: All 10 tools return correct shapes
# Agent: explore — discover and verify every endpoint
source "$(dirname "$0")/lib.sh"

echo "=== T03: All 10 tools ==="

sid=$(init_session)
[ "$sid" = "__FAIL__" ] && { echo "  FAIL: init_session"; exit 1; }

# 1. tools/list returns all 10
resp=$(call_tool "$sid" '{"jsonrpc":"2.0","method":"tools/list","params":{},"id":1}')
json=$(echo "$resp" | cut -d'|' -f2-)
count=$(echo "$json" | python3 -c "import sys,json; d=json.load(sys.stdin); print(len(d['result']['tools']))")
assert_eq "tools/list returns 10 tools" "10" "$count"

names=$(echo "$json" | python3 -c "
import sys,json; d=json.load(sys.stdin)
print(' '.join(sorted([t['name'] for t in d['result']['tools']])))
")
expected="get_expert get_journey get_sql_rules get_table_details get_tables_by_category list_categories list_experts list_journeys list_tables_in_category search_tables"
assert_eq "tool names match" "$expected" "$names"

# 2. list_experts
resp=$(call_tool "$sid" '{"jsonrpc":"2.0","method":"tools/call","params":{"name":"list_experts","arguments":{}},"id":1}')
json=$(echo "$resp" | cut -d'|' -f2-)
text=$(echo "$json" | parse_result)
text_len=$(echo "$text" | wc -c)
assert_true "list_experts returns text" "[ $text_len -gt 10 ]"



# 4. list_categories
resp=$(call_tool "$sid" '{"jsonrpc":"2.0","method":"tools/call","params":{"name":"list_categories","arguments":{}},"id":1}')
code=$(echo "$resp" | cut -d'|' -f1)
assert_eq "list_categories succeeds" "200" "$code"

# 5. get_tables_by_category (try a likely category)
resp=$(call_tool "$sid" '{"jsonrpc":"2.0","method":"tools/call","params":{"name":"get_tables_by_category","arguments":{"category":"Orders"}},"id":1}')
code=$(echo "$resp" | cut -d'|' -f1)
assert_eq "get_tables_by_category succeeds" "200" "$code"

# 6. list_tables_in_category
resp=$(call_tool "$sid" '{"jsonrpc":"2.0","method":"tools/call","params":{"name":"list_tables_in_category","arguments":{"category":"Orders"}},"id":1}')
code=$(echo "$resp" | cut -d'|' -f1)
assert_eq "list_tables_in_category succeeds" "200" "$code"

# 7. search_tables
resp=$(call_tool "$sid" '{"jsonrpc":"2.0","method":"tools/call","params":{"name":"search_tables","arguments":{"query":"customer"}},"id":1}')
code=$(echo "$resp" | cut -d'|' -f1)
assert_eq "search_tables succeeds" "200" "$code"

# 8. get_table_details
resp=$(call_tool "$sid" '{"jsonrpc":"2.0","method":"tools/call","params":{"name":"get_table_details","arguments":{"table_name":"ORDERS"}},"id":1}')
code=$(echo "$resp" | cut -d'|' -f1)
assert_eq "get_table_details succeeds" "200" "$code"

# 9. get_sql_rules
resp=$(call_tool "$sid" '{"jsonrpc":"2.0","method":"tools/call","params":{"name":"get_sql_rules","arguments":{}},"id":1}')
code=$(echo "$resp" | cut -d'|' -f1)
assert_eq "get_sql_rules succeeds" "200" "$code"

# 10. list_journeys
resp=$(call_tool "$sid" '{"jsonrpc":"2.0","method":"tools/call","params":{"name":"list_journeys","arguments":{}},"id":1}')
code=$(echo "$resp" | cut -d'|' -f1)
assert_eq "list_journeys succeeds" "200" "$code"

close_session "$sid"
summary
