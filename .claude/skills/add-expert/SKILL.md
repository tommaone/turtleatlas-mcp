---
name: add-expert
description: This skill should be used when the user asks to "add an expert", "create an expert file", "update an expert", "correct the knowledge base", "fix the expert", "add knowledge", "document a table", or wants to teach or correct the knowledge server about a domain area.
version: 1.0.0
---

# Add, Update, or Correct Expert Knowledge

This skill guides the creation, correction, or update of an expert `.md` file in `resources/experts/` and ensures the schema archive and `index.js` keyword map are kept consistent.

**This skill applies to all three cases:**
- **Create**: New domain area not yet covered
- **Update**: Adding knowledge to an existing expert (new tables, new behaviours discovered)
- **Correct**: Fixing wrong information found through testing (bad joins, wrong format, missing fallbacks)

## Before Writing Anything — Ask These Questions

Gather the following from the user before touching any file. Do not proceed until you have clear answers:

1. **Domain area** — What topic does this cover? (e.g. "orders", "inventory", "customers")
2. **Key tables** — Which tables are central? List them with their primary keys and the most important columns.
3. **Relationships** — How do the tables join to each other? What are the FK chains?
4. **Business meaning** — What do the domain values mean in business terms? What are the gotchas or non-obvious behaviours?
5. **Common questions** — What questions will users typically ask that this expert should answer?
6. **Keywords** — What words would a user naturally say when asking about this topic? These go into the `index.js` keyword map.

## Expert File Format

Expert files live in `resources/experts/`. Study the existing files before writing — match their tone and structure exactly.

**The right format:**
- Short intro paragraph explaining the domain concept
- Key tables section: table name, key fields, and their business meaning in plain English
- Domain values explained (what does a status code of `'A'` actually mean?)
- A small set of illustrative query patterns — representative, not exhaustive
- Gotchas or non-obvious behaviours (e.g. default filters, silent fallbacks, type mismatches)

**What does NOT belong in an expert file:**
- Step-by-step SQL walkthroughs or diagnostic procedures with numbered steps
- Long lists of queries covering every possible scenario
- Redundant information already in the schema archive (column names, data types)
- Instructions to the user about what to do next

The schema archive carries structure (columns, types, joins). The expert carries **meaning** — why things work the way they do, what the values mean, what to watch out for.

## Schema Archive — Always Update

**Before touching `tables.zip`**: Ask the user to provide the authoritative schema definition for any table you need to add or correct. Do not hand-craft column names or primary keys from memory — they will be wrong.

For every table mentioned in the expert, verify it exists in `resources/tables.zip` and has join paths populated:

```js
node -e "
import('adm-zip').then(({default: AdmZip}) => {
  const zip = new AdmZip('resources/tables.zip');
  ['TABLE1.json','TABLE2.json'].forEach(name => {
    const entry = zip.getEntry(name);
    if (!entry) { console.log(name, 'MISSING'); return; }
    const obj = JSON.parse(zip.readAsText(name));
    console.log(name, JSON.stringify(obj.POSSIBLE_JOINS));
  });
});
"
```

If a table is missing — add it. If `POSSIBLE_JOINS` is empty — fill it in.

**Type warning**: Check column types carefully before writing joins — a type mismatch (e.g. joining a `CHAR(10)` code column directly to a `UUID` column) silently returns 0 rows. Always verify the actual column types match before writing a join condition.

## index.js Keyword Map — Always Update

After writing the expert file, add keywords to the `expertFiles` map in `index.js`:

```js
const expertFiles = {
  // existing entries...
  'keyword1': 'your-expert.md',
  'keyword2': 'your-expert.md',
};
```

Choose keywords that match what a user would naturally type. Check existing keywords to avoid collisions.

## Consumer Apps — Update if Present

If you have a consumer app (like TurtleQL) that uses this MCP server, update its system prompt to include the new domain in the examples list. The line to update looks like:

```python
system_prompt = """...
2. Call list_experts / get_expert for relevant domain knowledge (e.g. orders, customers, ...)
..."""
```

Add the new domain to the examples list.

## When Correcting an Existing Expert

Before editing, identify *why* the expert produced wrong output. Common root causes:

- **Wrong join in schema** — `POSSIBLE_JOINS` pointed to a mismatched column type. Fix the schema JSON in `tables.zip`, not just the expert text.
- **Missing table in archive** — LLM warned "table not found in schema". Add the missing table to `tables.zip` with correct columns and `POSSIBLE_JOINS`.
- **Too many queries** — Expert reads like a SQL cookbook. Strip back to 1-2 illustrative patterns; the LLM derives the rest from schema + concepts.
- **Missing fallback or special case** — LLM guessed when it hit a dead end. Add the knowledge as a concept note, not as a new query.
- **Wrong format** — Expert has numbered diagnostic steps instead of domain knowledge. Rewrite to match the style of the other expert files.

Always re-test after correcting: ask the server the exact question that previously failed and verify the output is correct before committing.

## Checklist Before Committing

- [ ] Expert file written in the same style as other experts in `resources/experts/` — concepts and meaning, not SQL procedures
- [ ] All referenced tables exist in `tables.zip` with correct join paths
- [ ] No direct joins between mismatched column types
- [ ] `index.js` keyword map updated
- [ ] Tested by asking the MCP a question that should load the new expert
