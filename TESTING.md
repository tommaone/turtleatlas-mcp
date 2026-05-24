# Testing turtleatlas-mcp

Quick reference for testing the MCP server. See `.opencode/skills/test-mcp/SKILL.md` for the full guide (loadable by opencode/Claude).

---

## Quick Start

```bash
node index.js --port=3456
curl http://localhost:3456/health
```

## Session Lifecycle

Every agent needs its own session. The `mcp-session-id` comes from the HTTP response header.

### Initialize

```bash
INIT='{"jsonrpc":"2.0","method":"initialize","params":{"protocolVersion":"2024-11-05","capabilities":{},"clientInfo":{"name":"my-agent","version":"1.0"}},"id":1}'

curl -i -X POST http://localhost:3456/mcp \
  -H "Content-Type: application/json" \
  -H "Accept: application/json, text/event-stream" \
  -d "$INIT"
# Look for: mcp-session-id: <uuid> in response headers
```

### Call a Tool

```bash
SESSION_ID="<uuid-from-init>"

curl -s -X POST http://localhost:3456/mcp \
  -H "Content-Type: application/json" \
  -H "Accept: application/json, text/event-stream" \
  -H "mcp-session-id: $SESSION_ID" \
  -d '{"jsonrpc":"2.0","method":"tools/call","params":{"name":"get_expert","arguments":{"name":"example-expert.md"}},"id":1}'
```

### Disconnect

```bash
curl -X DELETE http://localhost:3456/mcp -H "mcp-session-id: $SESSION_ID"
```

Sessions that are not disconnected **leak in memory**. Always clean up.

### Parse SSE Response

Responses are `text/event-stream`, not plain JSON:

```bash
curl -s ... | grep '^data: ' | sed 's/^data: //'
```

## All Tools

| Tool | Purpose |
|------|---------|
| `get_sql_rules` | Returns `general_db_info.md` |
| `list_categories` | List all table categories |
| `get_tables_by_category` | Full table info for a category (paginated) |
| `list_tables_in_category` | Lightweight table listing |
| `search_tables` | Keyword search across all tables |
| `get_table_details` | Full schema JSON from `tables.zip` |
| `list_experts` | List available expert files |
| `get_expert` | Load a specific expert file |
| `list_journeys` | List available journey files |
| `get_journey` | Load a specific journey file |

## Concurrency Test

```bash
#!/bin/bash
SERVER="http://localhost:3456/mcp"

agent() {
  local id=$1 TMP=$(mktemp -d)
  local start=$(date +%s%N)
  INIT='{"jsonrpc":"2.0","method":"initialize","params":{"protocolVersion":"2024-11-05","capabilities":{},"clientInfo":{"name":"a-'$id'","version":"1.0"}},"id":1}'
  curl -s -D "$TMP/h" -X POST "$SERVER" \
    -H "Content-Type: application/json" \
    -H "Accept: application/json, text/event-stream" \
    -d "$INIT" > /dev/null
  SID=$(grep -i 'mcp-session-id' "$TMP/h" | awk '{print $2}' | tr -d '\r\n')
  Q='{"jsonrpc":"2.0","method":"tools/call","params":{"name":"get_expert","arguments":{"name":"example-expert.md"}},"id":1}'
  LEN=$(curl -s -D "$TMP/h2" -X POST "$SERVER" \
    -H "Content-Type: application/json" \
    -H "Accept: application/json, text/event-stream" \
    -H "mcp-session-id: $SID" -d "$Q" \
    | grep '^data: ' | sed 's/^data: //' \
    | python3 -c "import sys,json; d=json.load(sys.stdin); print(len(d['result']['content'][0]['text']))")
  ELAPSED=$(( ($(date +%s%N) - start) / 1000000 ))
  echo "Agent $id: OK ${LEN}B ${ELAPSED}ms"
  curl -s -X DELETE "$SERVER" -H "mcp-session-id: $SID" > /dev/null
  rm -rf "$TMP"
}
for i in $(seq 1 10); do agent $i & done; wait
```

## Failure Modes

| Symptom | Fix |
|---------|-----|
| `400: No valid session ID` | Send `initialize` first; save `mcp-session-id` header |
| `400` with no body | Session expired or wrong ID; re-initialize |
| `404` on POST | Server not in HTTP mode; restart with `--port=X` |
| Empty body (HTTP 200) | Response is SSE; use `grep '^data: '` to extract JSON |
| Sessions grow unbounded | Clients not sending `DELETE`; check activeSessions on `/health` |

## Sanity Checklist

- [ ] `GET /health` returns 200
- [ ] `POST /mcp` with initialize returns `mcp-session-id` header
- [ ] `tools/list` returns 10 tools
- [ ] `get_expert` with valid name returns markdown
- [ ] `get_expert` with invalid name returns error
- [ ] `list_experts` lists all `.md` files
- [ ] 10 parallel agents all succeed
- [ ] `DELETE /mcp` decrements activeSessions
- [ ] Same session ID works across multiple calls
