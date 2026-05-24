# Shared test library for turtleatlas-mcp test portfolio
# Source this in every test script: source "$(dirname "$0")/lib.sh"

SERVER="${SERVER:-http://localhost:3456/mcp}"
PASS=0
FAIL=0

init_session() {
  local tmp=$(mktemp)
  local init='{"jsonrpc":"2.0","method":"initialize","params":{"protocolVersion":"2024-11-05","capabilities":{},"clientInfo":{"name":"test-agent","version":"1.0"}},"id":1}'
  curl -s -D "$tmp" -X POST "$SERVER" \
    -H "Content-Type: application/json" \
    -H "Accept: application/json, text/event-stream" \
    -d "$init" > /dev/null
  local sid=$(grep -i 'mcp-session-id' "$tmp" | awk '{print $2}' | tr -d '\r\n')
  local code=$(grep -i 'HTTP' "$tmp" | awk '{print $2}')
  rm -f "$tmp"
  if [ -z "$sid" ] || [ "$code" != "200" ]; then
    echo "__FAIL__"
    return 1
  fi
  echo "$sid"
  return 0
}

close_session() {
  local sid="$1"
  curl -s -X DELETE "$SERVER" -H "mcp-session-id: $sid" > /dev/null 2>&1
}

call_tool() {
  local sid="$1" body="$2"
  local tmp=$(mktemp)
  curl -s -D "$tmp" -X POST "$SERVER" \
    -H "Content-Type: application/json" \
    -H "Accept: application/json, text/event-stream" \
    -H "mcp-session-id: $sid" \
    -d "$body" > "$tmp.body" 2>/dev/null
  local code=$(grep -i 'HTTP' "$tmp" | awk '{print $2}')
  local json=$(grep '^data: ' "$tmp.body" | sed 's/^data: //')
  rm -f "$tmp" "$tmp.body"
  echo "$code|$json"
}

parse_result() {
  # usage: echo "$response" | parse_result .result.content[0].text
  local filter="${1:-.result.content[0].text}"
  python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('result',{}).get('content',[{}])[0].get('text',''))" 2>/dev/null
}

parse_error() {
  python3 -c "import sys,json; d=json.load(sys.stdin); e=d.get('error',{}); print(e.get('message',''))" 2>/dev/null
}

parse_error_code() {
  python3 -c "import sys,json; d=json.load(sys.stdin); e=d.get('error',{}); print(e.get('code',-1))" 2>/dev/null
}

assert_eq() {
  local label="$1" expected="$2" actual="$3"
  if [ "$expected" = "$actual" ]; then
    echo "  PASS: $label"
    PASS=$((PASS + 1))
  else
    echo "  FAIL: $label (expected: '$expected', got: '$actual')"
    FAIL=$((FAIL + 1))
  fi
}

assert_contains() {
  local label="$1" needle="$2" haystack="$3"
  if echo "$haystack" | grep -q "$needle"; then
    echo "  PASS: $label"
    PASS=$((PASS + 1))
  else
    echo "  FAIL: $label (expected to contain '$needle')"
    FAIL=$((FAIL + 1))
  fi
}

assert_true() {
  local label="$1" condition="$2"
  if eval "$condition" 2>/dev/null; then
    echo "  PASS: $label"
    PASS=$((PASS + 1))
  else
    echo "  FAIL: $label (condition false)"
    FAIL=$((FAIL + 1))
  fi
}

assert_status() {
  local label="$1" expected="$2" code="$3"
  if [ "$code" = "$expected" ]; then
    echo "  PASS: $label"
    PASS=$((PASS + 1))
  else
    echo "  FAIL: $label (HTTP $code, expected $expected)"
    FAIL=$((FAIL + 1))
  fi
}

summary() {
  echo ""
  echo "---"
  if [ "$FAIL" -eq 0 ]; then
    echo "RESULT: ALL $PASS TESTS PASSED"
    return 0
  else
    echo "RESULT: $FAIL/$((PASS + FAIL)) TESTS FAILED"
    return 1
  fi
}
