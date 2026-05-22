# CLAUDE.md

## What This Is

**knowledge-artisan-mcp** is a generic MCP (Model Context Protocol) server that serves structured Markdown knowledge to any LLM client. Point it at your database schema, domain expert files, and process documentation — the LLM gets it all via tool calls, without you needing to stuff it all into a system prompt.

Works with any MCP-compatible client: TurtleQL, Claude Desktop, or any SDK that supports MCP tool use.

## The Two-Tier Knowledge Model

### Experts (`resources/experts/`)
Compact domain knowledge files (~3–10k tokens each). They explain the **meaning** of your data:
- What the key tables contain in business terms
- What status codes and enum values mean
- Common query patterns for a domain
- Gotchas and non-obvious behaviours

Use experts for: "what does this domain look like and how do I query it?"

### Journeys (`resources/journeys/`)
Deep-detail process extracts (~10–25k tokens each). They cover a specific business process end-to-end:
- Complete business rules and validation logic
- State machine transitions with guards and side effects
- Integration contracts between systems

Use journeys for: "walk me through exactly what happens when X occurs."

**Load only what is relevant** — the LLM context window is finite. The `list_experts` / `list_journeys` tools help the LLM discover what exists and load only the relevant file.

## What Goes Where

### `resources/general_db_info.md`
Served by the `get_sql_rules` tool. Put here:
- Your SQL dialect rules (FETCH FIRST vs LIMIT vs TOP)
- Schema qualification rules (always prefix tables with schema name)
- Common join patterns used across your database
- Date/string quoting conventions
- Performance hints (read consistency hints, pagination patterns)

Replace the template content with your actual rules.

### `resources/table_overview.json`
Lightweight metadata for all tables — used by `search_tables`, `list_categories`, `get_tables_by_category`. Structure:

```json
{
  "files": [
    {
      "filename": "ORDERS.json",
      "summary": "Customer orders header table",
      "description": "One row per order...",
      "categories": ["Orders", "Sales"]
    }
  ]
}
```

### `resources/tables.zip`
Compressed full schema JSONs, one file per table. Extracted on-demand by `get_table_details`. Each table JSON:

```json
{
  "TABLE_NAME": "ORDERS",
  "NUMBER_OF_COLUMNS": 12,
  "COLUMNS": {
    "ORDER_ID": {"DATA_TYPE": "INTEGER", "NULLABLE": false},
    "STATUS": {
      "DATA_TYPE": "CHAR",
      "COLUMN_LENGTH": 1,
      "DOMAIN": {
        "DOMAIN_NAME": "ORDER_STATUS",
        "VALUES": {"N": "New", "P": "Processing", "C": "Complete"}
      }
    }
  },
  "POSSIBLE_JOINS": {
    "ORDER_LINES": "ORDERS.ORDER_ID = ORDER_LINES.ORDER_ID"
  }
}
```

## How to Add Knowledge

Use the `/add-expert` Claude Code skill — it guides you through the correct process.

```
/add-expert
```

The skill will ask you for the domain area, key tables, relationships, and keywords, then write the expert file and update the `index.js` keyword map.

## Tools

| Tool | Purpose |
|------|---------|
| `get_sql_rules` | Returns `general_db_info.md` — always call first |
| `list_categories` | List all table categories from `table_overview.json` |
| `get_tables_by_category` | Full table info for a category (paginated) |
| `list_tables_in_category` | Lightweight table listing for quick browsing |
| `search_tables` | Keyword search across all tables |
| `get_table_details` | Full schema JSON from `tables.zip` |
| `list_experts` | List available expert files with descriptions |
| `get_expert` | Load a specific expert file by name |
| `list_journeys` | List available journey files, optionally filtered by domain |
| `get_journey` | Load a specific journey file by name |

## Running

```bash
npm install
npm start              # stdio mode (for Claude Desktop / MCP clients)
node index.js --port=3000   # HTTP mode (for TurtleQL / remote clients)
```

## Connection to TurtleQL

TurtleQL is the companion NL→SQL web UI. Point it at this server:

```yaml
# TurtleQL config.local.yaml
mcp_server_url: http://localhost:3000/mcp
```

## Development

### Adding a New Tool

1. Add tool definition in `setupToolHandlers()` → `ListToolsRequestSchema` handler
2. Add switch case in `CallToolRequestSchema` handler
3. Implement `handle<ToolName>(args)` method
