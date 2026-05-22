# SQL Generation Rules

This file is served by the `get_sql_rules` tool. Replace this template with your actual database rules.

## What to put here

- **Dialect rules** — e.g. `FETCH FIRST 100 ROWS ONLY` (DB2), `LIMIT 100` (PostgreSQL/MySQL), `TOP 100` (SQL Server)
- **Schema qualification** — e.g. always prefix tables with the schema name: `SELECT * FROM myschema.orders`
- **Date/string quoting** — e.g. dates as `'2024-01-15'`, string comparisons, case sensitivity
- **Common join patterns** — standard FK chains used across your database
- **NULL handling** — any non-obvious NULL behaviours in your schema
- **Performance hints** — read consistency hints, index hints, pagination patterns
- **Gotchas** — anything that would trip up an LLM generating SQL for the first time

## Example (PostgreSQL)

```
Always qualify tables with the schema: SELECT * FROM public.orders o
Use LIMIT for pagination: SELECT * FROM public.orders LIMIT 100
Dates are ISO format: WHERE created_at > '2024-01-01'
Use ILIKE for case-insensitive string search: WHERE name ILIKE '%smith%'
```

## Example (DB2)

```
Always qualify tables with the schema: SELECT * FROM myschema.orders o
Use FETCH FIRST for pagination: SELECT * FROM myschema.orders FETCH FIRST 100 ROWS ONLY
Add WITH UR on read-only queries against production: SELECT ... WITH UR
```
