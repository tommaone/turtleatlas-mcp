# turtleatlas-mcp

A **template** for creating a structured MCP knowledge server. Turns a folder of Markdown files and table schemas into a tool-based knowledge base for any LLM (TurtleQL, Claude Desktop, or any MCP-compatible client).

No RAG pipeline, no vector database, no embeddings — just files on disk, served through MCP tools.

## Quick start

```bash
# 1. Create your concrete knowledge base from this template
npm install
./init.sh

# 2. Fill in your actual data
#    resources/table_overview.json   — table metadata
#    resources/tables.zip             — full schema JSONs per table
#    resources/general_db_info.md     — SQL dialect rules
#    resources/experts/               — domain expert files
#    resources/journeys/              — business process journeys

# 3. Run
npm start                    # stdio mode (Claude Desktop)
node index.js --port=3000    # HTTP mode (TurtleQL / remote)
```

## How it works

The server exposes MCP tools that let the LLM pull exactly what it needs:

| Tool | What it returns |
|------|----------------|
| `get_sql_rules` | SQL dialect rules — always call first |
| `list_categories` | Table categories from `table_overview.json` |
| `get_tables_by_category` | Full table info for a category |
| `list_tables_in_category` | Lightweight table listing |
| `search_tables` | Keyword search across all tables |
| `get_table_details` | Full schema JSON from `tables.zip` |
| `list_experts` | Available domain expert files |
| `get_expert` | Load a specific expert file |
| `list_journeys` | Available process journeys |
| `get_journey` | Load a specific journey file |

## Creating a concrete implementation

This repo is a [GitHub template](https://docs.github.com/en/repositories/creating-and-managing-repositories/creating-a-template-repository). To create your own:

```bash
gh repo create my-knowledge-base --template=tommaone/turtleatlas-mcp --public
git clone https://github.com/you/my-knowledge-base
cd my-knowledge-base
npm install
./init.sh
# then fill in resources/ with your data
```

Or just fork it and replace `resources/` with your own content.

## The knowledge model

- **Experts** (`resources/experts/`) — compact domain knowledge (~3–10k tokens each). Business meaning of tables, domain values, gotchas.
- **Journeys** (`resources/journeys/`) — deep process extracts (~10–25k tokens each). Full business rules, state machines, integration contracts.
- **SQL rules** (`resources/general_db_info.md`) — your database's dialect rules, schema conventions, join patterns.
- **Table schemas** (`resources/tables.zip`) — compressed JSON schema files, one per table.

## Adding expert knowledge

```bash
/add-expert
```

This skill (available as both an [opencode](.opencode/skills/add-expert/SKILL.md) and [Claude Code](.claude/skills/add-expert/SKILL.md) skill) walks you through creating expert files and keeping the schema archive consistent.

## Companion app

[TurtleQL](https://github.com/tommaone/turtleql) — the NL→SQL web UI that uses this server as its knowledge backend.
