# turtleatlas-mcp

A generic MCP server that turns a folder of Markdown files and table schemas into a structured knowledge base for LLMs.

Ask your LLM questions about your database in plain English. It uses the tools to look up what it needs — SQL rules, domain context, table schemas — before generating a query. No RAG pipeline, no vector database, no embeddings required.

## What it solves

LLMs hallucinate column names and join conditions when they don't have schema context. Stuffing 1,000 table definitions into a system prompt blows the context window. This server lets the LLM pull exactly what it needs, when it needs it.

## The knowledge model

- **Experts** (`resources/experts/`) — compact domain knowledge (~3–10k tokens). Business meaning of tables, domain values, gotchas. The LLM loads these per domain.
- **Journeys** (`resources/journeys/`) — deep process extracts (~10–25k tokens). Full business rules, state machines, integration contracts. Load only when needed.
- **SQL rules** (`resources/general_db_info.md`) — your database's dialect rules, schema conventions, join patterns. Always loaded first.
- **Table schemas** (`resources/tables.zip`) — compressed JSON schema files per table. Loaded on demand.

## Quick start

```bash
npm install
node index.js --port=3000   # HTTP mode
# or
npm start                   # stdio mode
```

Point your MCP client at `http://localhost:3000/mcp`.

## Populating your knowledge base

See `CLAUDE.md` for the full onboarding guide.

Use the `/add-expert` Claude Code skill to interactively add domain expert files. It handles the schema archive, keyword map, and file format for you.

```
/add-expert
```

## Companion app

[TurtleQL](https://github.com/tommaone/turtleql) — the NL→SQL web UI that uses this server as its knowledge backend.
