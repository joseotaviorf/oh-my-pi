---
name: validate-dag
description: Run all local CI validations for a DAG in parallel and synthesize results into a single prioritized fix list. Use when the user asks to validate a DAG, debug a CI failure, or check a DAG before pushing.
---

# Validate a DAG

## When to use

After creating or modifying a DAG declaration, SQL query, or metadata file — or when debugging a Woodpecker CI failure locally.

## Step 1 — Identify scope

Determine the `dag_name` from context (the folder name under `dags/{line}/{dag_name}/`). If not clear, ask the user.

## Step 2 — Launch three shell subagents in parallel

Use the Task tool with `subagent_type: shell` for all three simultaneously. Do NOT run them sequentially.

**Subagent A — Declaration validation:**
```bash
cd /path/to/bi-etl-ejuice
make validate-dag-declaration-files dag_name={dag_name}
```

**Subagent B — Metadata content validation:**
```bash
cd /path/to/bi-etl-ejuice
make validate-metadata-files-content
```

**Subagent C — Lineage consistency validation:**
```bash
cd /path/to/bi-etl-ejuice
make validate-lineage-consistency
```

Ask each subagent to return: exit code, full stdout, and any lines containing "ERROR", "FAIL", or the dag_name.

## Step 3 — Synthesize results

Group all findings by file, ordered by severity:

1. **Declaration errors** (from subagent A) — block DAG from loading; fix first.
2. **Metadata schema errors** (from subagent B) — block CI merge; fix second.
3. **Lineage inconsistencies** (from subagent C) — often caused by missing metadata columns, not SQL errors; fix last.

For each error, provide:
- File path (relative to repo root)
- What is wrong
- Exact fix (field to add/change, not just a description)

## Step 4 — Common error patterns and fixes

| Error | Likely cause | Fix |
|-------|-------------|-----|
| `missing required field` in declaration | Required YAML key absent | Add the key per `dag_build` rule |
| `description too short` in metadata | `description:` < 10 chars | Expand the description string |
| `lineage not found` | SQL column has no `lineage:` in metadata | Add `lineage: [db.table.col]` to the metadata YAML |
| `table referenced in SQL not in lineage` | Lineage points to wrong source | Check the SQL `FROM` clause and align metadata |
| `metadata file missing` | `.sql` exists but no matching `.yml` | Create `metadata/{layer}/{table}.yml` |

## Step 5 — Verify fix

After the user makes changes, re-run only the subagents that reported errors to confirm they now pass.
