---
name: test-mcp
description: |
  Test the turtleatlas-mcp server end-to-end — health checks, session lifecycle,
  tool calls, concurrency, and cleanup. Use when the user asks to "test the MCP",
  "run a load test", "verify the server", or "check if tools work".
metadata:
  source: "turtleatlas-mcp repo — Streamable HTTP MCP server"
---

# Test MCP Server

End-to-end testing guide for turtleatlas-mcp (Streamable HTTP transport).

---

## 1. Start the Server

```bash
# HTTP mode (default port from MCP_PORT env)
cd /path/to/turtleatlas-mcp
node index.js --port=3456

# or via env
MCP_PORT=3456 node index.js

# stdio mode (for Claude Desktop / MCP client integration)
node index.js
```

## 2. Health Check

```bash
curl http://localhost:3456/health
```

Expect 200 with JSON:

```json
{
  "status": "healthy",
  "service": "turtleatlas-mcp-server",
  "version": "1.0.0",
  "transport": "Streamable HTTP",
  "uptime": 42.0,
  "timestamp": "2026-05-24T20:00:00.000Z",
  "activeSessions": 0
}
```

## 3. Session Lifecycle

MCP Streamable HTTP is **sessionful**. Every agent gets its own session.

### 3a. Initialize (creates a session)

```bash
INIT='{"jsonrpc":"2.0","method":"initialize","params":{"protocolVersion":"2024-11-05","capabilities":{},"clientInfo":{"name":"my-agent","version":"1.0"}},"id":1}'

curl -i -X POST http://localhost:3456/mcp \
  -H "Content-Type: application/json" \
  -H "Accept: application/json, text/event-stream" \
  -d "$INIT"
```

**Response:**
- Header `mcp-session-id: <uuid>` — **save this for all subsequent calls**
- Content-Type: `text/event-stream` (SSE)
- Body:
  ```
  event: message
  data: {"jsonrpc":"2.0","id":1,"result":{"protocolVersion":"2024-11-05","capabilities":{},"serverInfo":{"name":"turtleatlas-mcp-server","version":"1.0.0"}}}
  ```

**Important:** The `mcp-session-id` comes from the HTTP **response header**, not from the JSON body.

### 3b. Call a tool

```bash
SESSION_ID="<uuid-from-init>"

curl -X POST http://localhost:3456/mcp \
  -H "Content-Type: application/json" \
  -H "Accept: application/json, text/event-stream" \
  -H "mcp-session-id: $SESSION_ID" \
  -d '{"jsonrpc":"2.0","method":"tools/call","params":{"name":"get_expert","arguments":{"name":"example-expert.md"}},"id":2}'
```

**Response** (SSE):
```
event: message
data: {"jsonrpc":"2.0","id":2,"result":{"content":[{"type":"text","text":"# Example Expert ..."}]}}
```

### 3c. List available tools

```bash
curl -X POST http://localhost:3456/mcp \
  -H "Content-Type: application/json" \
  -H "Accept: application/json, text/event-stream" \
  -H "mcp-session-id: $SESSION_ID" \
  -d '{"jsonrpc":"2.0","method":"tools/list","params":{},"id":2}'
```

### 3d. Disconnect (cleanup)

```bash
curl -X DELETE http://localhost:3456/mcp \
  -H "mcp-session-id: $SESSION_ID"
```

Sessions that are not disconnected **accumulate in memory**. Always disconnect after testing.

## 4. Testing Each Tool

### list_experts

```bash
curl -X POST http://localhost:3456/mcp \
  -H "Content-Type: application/json" \
  -H "Accept: application/json, text/event-stream" \
  -H "mcp-session-id: $SESSION_ID" \
  -d '{"jsonrpc":"2.0","method":"tools/call","params":{"name":"list_experts","arguments":{}},"id":1}'
```

Expected: list of all `.md` files in `resources/experts/` with title and description.

### get_expert

```bash
curl -X POST http://localhost:3456/mcp \
  -H "Content-Type: application/json" \
  -H "Accept: application/json, text/event-stream" \
  -H "mcp-session-id: $SESSION_ID" \
  -d '{"jsonrpc":"2.0","method":"tools/call","params":{"name":"get_expert","arguments":{"name":"example-expert.md"}},"id":1}'
```

Expected: full markdown content of the expert file.

Error case (file not found):
```json
{
  "jsonrpc": "2.0",
  "id": 1,
  "error": {
    "code": -32602,
    "message": "Expert 'nope.md' not found"
  }
}
```

### list_categories

```bash
curl -X POST http://localhost:3456/mcp \
  -H "Content-Type: application/json" \
  -H "Accept: application/json, text/event-stream" \
  -H "mcp-session-id: $SESSION_ID" \
  -d '{"jsonrpc":"2.0","method":"tools/call","params":{"name":"list_categories","arguments":{}},"id":1}'
```

Expected: sorted list of categories from `table_overview.json`.

### get_tables_by_category

```bash
curl -X POST http://localhost:3456/mcp \
  -H "Content-Type: application/json" \
  -H "Accept: application/json, text/event-stream" \
  -H "mcp-session-id: $SESSION_ID" \
  -d '{"jsonrpc":"2.0","method":"tools/call","params":{"name":"get_tables_by_category","arguments":{"category":"Orders"}},"id":1}'
```

Supports pagination: `{"category":"Orders","limit":10,"offset":0}`

### search_tables

```bash
curl -X POST http://localhost:3456/mcp \
  -H "Content-Type: application/json" \
  -H "Accept: application/json, text/event-stream" \
  -H "mcp-session-id: $SESSION_ID" \
  -d '{"jsonrpc":"2.0","method":"tools/call","params":{"name":"search_tables","arguments":{"query":"customer order"}},"id":1}'
```

### get_table_details

```bash
curl -X POST http://localhost:3456/mcp \
  -H "Content-Type: application/json" \
  -H "Accept: application/json, text/event-stream" \
  -H "mcp-session-id: $SESSION_ID" \
  -d '{"jsonrpc":"2.0","method":"tools/call","params":{"name":"get_table_details","arguments":{"table_name":"ORDERS"}},"id":1}'
```

### get_sql_rules

```bash
curl -X POST http://localhost:3456/mcp \
  -H "Content-Type: application/json" \
  -H "Accept: application/json, text/event-stream" \
  -H "mcp-session-id: $SESSION_ID" \
  -d '{"jsonrpc":"2.0","method":"tools/call","params":{"name":"get_sql_rules","arguments":{}},"id":1}'
```

## 5. Concurrency / Load Test

The server creates one session per agent. Sessions are isolated. Run 10+ agents in parallel to verify no cross-session contamination.

```bash
#!/bin/bash
SERVER="http://localhost:3456/mcp"

agent() {
  local id=$1 TMP=$(mktemp -d)
  local start=$(date +%s%N)

  # Initialize
  INIT='{"jsonrpc":"2.0","method":"initialize","params":{"protocolVersion":"2024-11-05","capabilities":{},"clientInfo":{"name":"agent-'$id'","version":"1.0"}},"id":1}'
  curl -s -D "$TMP/headers" -X POST "$SERVER" \
    -H "Content-Type: application/json" \
    -H "Accept: application/json, text/event-stream" \
    -d "$INIT" > /dev/null

  SESSION_ID=$(grep -i 'mcp-session-id' "$TMP/headers" | awk '{print $2}' | tr -d '\r\n')
  HTTP_CODE=$(grep -i 'HTTP' "$TMP/headers" | awk '{print $2}')

  if [ -z "$SESSION_ID" ] || [ "$HTTP_CODE" != "200" ]; then
    echo "AGENT $id | FAIL | init HTTP $HTTP_CODE"
    rm -rf "$TMP"
    return
  fi

  # Call get_expert
  Q='{"jsonrpc":"2.0","method":"tools/call","params":{"name":"get_expert","arguments":{"name":"example-expert.md"}},"id":1}'
  curl -s -D "$TMP/headers2" -X POST "$SERVER" \
    -H "Content-Type: application/json" \
    -H "Accept: application/json, text/event-stream" \
    -H "mcp-session-id: $SESSION_ID" \
    -d "$Q" > "$TMP/body"

  CONTENT_LEN=$(grep -i 'content-length' "$TMP/headers2" | awk '{print $2}' | tr -d '\r')
  ELAPSED=$(( ($(date +%s%N) - start) / 1000000 ))
  echo "AGENT $id | OK | ${CONTENT_LEN}B | ${ELAPSED}ms"

  # Disconnect
  curl -s -X DELETE "$SERVER" -H "mcp-session-id: $SESSION_ID" > /dev/null
  rm -rf "$TMP"
}

for i in $(seq 1 10); do agent $i & done
wait
```

**What to check:**
- All agents return HTTP 200
- All agents get the same content (compare content-length)
- No agent gets another agent's session data
- Response times are consistent (no linear degradation)
- Active sessions clean up after DELETE

## 6. Streamable HTTP Protocol Notes

**Request headers (every call):**
```
Content-Type: application/json
Accept: application/json, text/event-stream
```

**Response format:**
- Initialize and tool calls return `Content-Type: text/event-stream`
- Each response has the SSE format:
  ```
  event: message
  data: <JSON-RPC response>
  ```
- The `mcp-session-id` header is set on every response once a session is established

**Error responses:**
- `400 Bad Request` — missing or invalid session ID (the most common error)
- `400 Bad Request: No valid session ID` — initialize was never called
- The session ID in the header may differ from the one that created it if you send the wrong one

**Content extraction from SSE:**
```bash
# Strip SSE wrapper, extract JSON
curl -s ... | grep '^data: ' | sed 's/^data: //'
```

## 7. Memory / Session Cleanup

Sessions live in an in-memory `Map` in `transports` (see `index.js` line ~819).

```js
const transports = {};  // sessionId → transport
```

Each session holds:
- The HTTP transport object (SDK `StreamableHTTPServerTransport`)
- A child `Server` instance (one per session)

**Without DELETE, sessions leak.** Monitor via `/health`:
```bash
curl -s http://localhost:3456/health | jq .activeSessions
```

If active sessions grow without bound, either:
- Clients are not sending DELETE on disconnect
- The `onclose` handler is not firing (network drops)

## 8. Common Failure Modes

| Symptom | Cause | Fix |
|---------|-------|-----|
| `400 Bad Request: No valid session ID` | First call was not `initialize`, or session ID header is missing | Send initialize first; copy `mcp-session-id` header from its response |
| `400 Bad Request` with no body | Session ID in header doesn't match any active session | Session may have expired or been deleted; re-initialize |
| `404` on `POST /mcp` | Server running in stdio mode, not HTTP | Restart with `--port=3456` |
| Cant connect | Port already in use | `kill $(lsof -ti:3456)` or choose different port |
| Empty response body (HTTP 200) | Response is SSE but you're parsing as JSON | Use `grep '^data: '` to extract the JSON payload |
| `content-length` varies between agents | Expected — different expert files have different sizes | Within same expert file, all agents should return identical size |
| Server crashes under load | Check `ulimit -n` for file descriptor limits; sessions may leak | Increase ulimit or add session TTL / LRU eviction |

## 9. Testing with MCP Clients

### Claude Desktop

In `claude_desktop_config.json`:
```json
{
  "mcpServers": {
    "turtleatlas-mcp": {
      "command": "node",
      "args": ["/path/to/turtleatlas-mcp/index.js"],
      "env": {
        "MCP_PORT": "3456"
      }
    }
  }
}
```

### raw curl (no MCP SDK)

See sections 3–4 above. The raw curl approach is the most reliable way to test — it isolates protocol issues from SDK bugs.

## 10. Sanity Checklist

- [ ] `GET /health` returns 200
- [ ] `POST /mcp` with initialize returns `mcp-session-id` header
- [ ] `tools/list` returns the expected 10 tools
- [ ] `get_expert` with valid name returns markdown content
- [ ] `get_expert` with invalid name returns error
- [ ] `list_experts` lists all `.md` files in `resources/experts/`
- [ ] `search_tables` returns ranked results
- [ ] `get_table_details` with missing table shows "did you mean?" suggestions
- [ ] Concurrency: 10 parallel agents all succeed, all get same content
- [ ] `DELETE /mcp` cleans up session (activeSessions decrements)
- [ ] Session reuse: same session ID across multiple tool calls works
- [ ] Session isolation: agent A cannot see agent B's data
