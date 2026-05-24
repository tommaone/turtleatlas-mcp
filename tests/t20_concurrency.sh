#!/bin/bash
# Test: Concurrency / session isolation — 10 agents, same question
# Agent: splinter — orchestrate parallel workers
source "$(dirname "$0")/lib.sh"

echo "=== T20: Concurrency — 10 agents in parallel ==="

results_dir=$(mktemp -d)
errors=0

for i in $(seq 1 10); do
  (
    tmp=$(mktemp)
    init='{"jsonrpc":"2.0","method":"initialize","params":{"protocolVersion":"2024-11-05","capabilities":{},"clientInfo":{"name":"conc-test-'$i'","version":"1.0"}},"id":1}'
    sid=$(curl -s -D "$tmp" -X POST "$SERVER" \
      -H "Content-Type: application/json" \
      -H "Accept: application/json, text/event-stream" \
      -d "$init" | grep '^data: ' > /dev/null; \
      grep -i 'mcp-session-id' "$tmp" | awk '{print $2}' | tr -d '\r\n')

    resp=$(curl -s -X POST "$SERVER" \
      -H "Content-Type: application/json" \
      -H "Accept: application/json, text/event-stream" \
      -H "mcp-session-id: $sid" \
      -d '{"jsonrpc":"2.0","method":"tools/call","params":{"name":"list_experts","arguments":{}},"id":2}')

    echo "$resp" > "$results_dir/agent_$i"
    echo "$sid" > "$results_dir/sid_$i"
    rm -f "$tmp"
  ) &
done

wait

# Collect results
all_same=1
first_len=""
for i in $(seq 1 10); do
  file="$results_dir/agent_$i"
  if [ ! -f "$file" ]; then
    echo "  FAIL: agent $i produced no output"
    errors=$((errors + 1))
    continue
  fi
  json=$(grep '^data: ' "$file" | sed 's/^data: //')
  has_error=$(echo "$json" | python3 -c "import sys,json; d=json.load(sys.stdin); print('y' if d.get('error') else 'n')" 2>/dev/null)
  if [ "$has_error" = "y" ]; then
    msg=$(echo "$json" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d['error']['message'])" 2>/dev/null)
    echo "  FAIL: agent $i returned error: $msg"
    errors=$((errors + 1))
    continue
  fi
  text_len=$(echo "$json" | python3 -c "import sys,json; d=json.load(sys.stdin); print(len(d['result']['content'][0]['text']))" 2>/dev/null)
  sid=$(cat "$results_dir/sid_$i" 2>/dev/null)
  echo "  Agent $i: OK ${text_len}B (session: ${sid:0:8}...)"

  if [ -z "$first_len" ]; then
    first_len="$text_len"
  elif [ "$text_len" != "$first_len" ]; then
    echo "  DATA INTEGRITY WARNING: agent $i size ($text_len) != agent 1 size ($first_len)"
    all_same=0
  fi
done

if [ "$errors" -eq 0 ]; then
  echo "  PASS: all 10 agents completed successfully"
  PASS=$((PASS + 1))
else
  echo "  FAIL: $errors agents had errors"
  FAIL=$((FAIL + 1))
fi

if [ "$all_same" -eq 1 ]; then
  echo "  PASS: all agents returned identical content"
  PASS=$((PASS + 1))
else
  echo "  FAIL: content mismatch between agents"
  FAIL=$((FAIL + 1))
fi

# Cleanup sessions
for i in $(seq 1 10); do
  sid=$(cat "$results_dir/sid_$i" 2>/dev/null)
  [ -n "$sid" ] && curl -s -X DELETE "$SERVER" -H "mcp-session-id: $sid" > /dev/null 2>&1
done
rm -rf "$results_dir"

summary
