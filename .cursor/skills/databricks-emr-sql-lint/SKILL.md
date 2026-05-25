---
name: databricks-emr-sql-lint
description: Lints SQL files under bi-etl-ejuice dags/ for Databricks-only constructs that break or change behavior on EMR Spark 3.5. Operates in dual-runtime mode (queries must run on both Databricks DBR 16.4 and EMR Spark 3.5). Auto-invokes when editing or creating any .sql file in dags/. Detects QUALIFY, GROUP BY ALL, IFF, DECODE, DATEDIFF 3-arg, variant access (column:key), and legacy DATE_FORMAT pattern letters; reports findings with severity, line numbers, snippets, and dual-runtime-safe rewrite suggestions; uses the database MCP to inspect column types before suggesting variant rewrites; never rewrites automatically (lint-only) unless the user explicitly asks. Use when modifying any .sql file in dags/, when the user mentions EMR migration, Spark 3.5 compatibility, dual-runtime, or asks "is this query EMR-compatible?".
disable-model-invocation: false
---

# Databricks → EMR Spark 3.5 SQL Linter

This skill is the gatekeeper for the **dual-runtime migration window**: every `.sql` file under `bi-etl-ejuice/dags/` must run identically on Databricks DBR 16.4 (Spark 3.5 + Photon) **and** on plain EMR Spark 3.5. Any construct that exists only on Databricks must be rewritten to a form that works on both.

This skill is **lint-only**. It detects, reports, and suggests — it never edits the SQL unless the user explicitly asks for a rewrite.

## When to apply

Auto-invoke whenever:
- The agent is editing, creating, or about to commit a `.sql` file inside `bi-etl-ejuice/dags/**`.
- The user mentions: EMR, Spark 3.5, dual-runtime, "EMR-compatible", migration, ParseException on Spark, "is this query portable?".

Stay silent when:
- The file is outside `dags/` (skill is scoped to pipeline SQL).
- The lint produces zero findings (do not announce "all clear" — silence is the success state).

## Lint workflow

Run after every edit to a `.sql` file in `dags/`. Report **once per edited file**, immediately after the edit's tool result, before moving on to the next action.

### Step 1 — Detect critical patterns (parallel Grep)

Run these patterns with the Grep tool (case-insensitive, scoped to the edited file):

| Pattern | Severity | Construct |
|---------|----------|-----------|
| `\bQUALIFY\b` | 🔴 critical | `QUALIFY` clause (Spark 4.0+) |
| `\bGROUP BY ALL\b` | 🔴 critical | `GROUP BY ALL` (Spark 4.0+) |
| `\bIFF\s*\(` | 🔴 critical | `IFF()` function (Databricks-only) |
| `\bDECODE\s*\(` | 🔴 critical | `DECODE()` function (Oracle/Databricks) |
| `\bDATEDIFF\s*\(\s*['"]?(YEAR\|QUARTER\|MONTH\|WEEK\|DAY\|HOUR\|MINUTE\|SECOND\|MILLISECOND\|MICROSECOND)\b` | 🔴 critical | `DATEDIFF(unit, start, end)` 3-arg form |
| `[a-zA-Z_]\w*:\[?["']?[a-zA-Z_]` | 🔴 critical | Variant access `column:key`, `column:["k"]`, `column:a:b.c` |
| `\bDATE_FORMAT\s*\([^)]*['"][^'"]*[uULFcE]` | 🟡 attention | `DATE_FORMAT` with pattern letters changed since Spark 3.0 |

### Step 2 — Filter false positives

Variant access regex (`[a-zA-Z_]\w*:[\["a-zA-Z_]`) is noisy. Discard matches that are:
- Inside a string literal (`'...'` or `"..."`).
- Inside a single-line comment (`-- ...`) or block comment (`/* ... */`).
- A reserved word followed by `:` (e.g., `CASE … WHEN x THEN y`, `BEGIN:`, `END:`) — these are not variant accesses.
- A timestamp/time literal (`'12:30:00'`, `'2026-04-24T14:30'`) — never matches because the pattern requires `[a-zA-Z_]` immediately before the `:`, but double-check when the literal is unquoted.

When in doubt, keep the match and let the report show it; the engineer can dismiss false positives.

### Step 3 — Resolve variant column types via Database MCP

For every variant access match, the rewrite depends on the column's Spark type. Before suggesting a rewrite:

1. Parse the SQL to find the table that owns the column (look in `FROM` and `JOIN` clauses; correlate via the alias prefix in `alias.column:key`).
2. Follow `database_schema_mcp_priority.mdc`: call the database MCP's `describe_table` on the source table.
3. Inspect the column's type:
   - **STRING** (raw JSON text) → suggest `GET_JSON_OBJECT(col, '$.path')`, wrap in `TRY_CAST(... AS <type>)` if a typed cast was present.
   - **STRUCT** → suggest dot notation `col.path` (or `col.path.subpath` for nesting).
   - **MAP<STRING, _>** → suggest bracket notation `col['key']`.
4. **Fallback** if the MCP is unavailable, errors, or the table cannot be located: surface the finding with severity `🔴 critical` and the suggestion `-- TODO: confirm column type before EMR migration; default rewrite is GET_JSON_OBJECT(col, '$.path') if STRING JSON`. State explicitly in the report that the MCP could not be consulted (per `database_schema_mcp_priority.mdc`).

For all other critical patterns (QUALIFY, GROUP BY ALL, IFF, DECODE, DATEDIFF 3-arg), no schema lookup is needed — apply the recipe from `RECIPES.md` directly.

### Step 4 — Report

Output **one markdown table** at the end of the agent's reply for this turn (after the file edit's tool result). Suppress entirely if no findings.

```
**EMR Spark 3.5 lint — `<relative/path/to/file.sql>`**

| Sev | Construct        | Line | Snippet                              | Dual-runtime suggestion                                      |
|-----|------------------|------|--------------------------------------|--------------------------------------------------------------|
| 🔴  | QUALIFY          | 42   | `QUALIFY ROW_NUMBER() OVER (...) = 1`| Wrap as CTE with `rn`; filter `WHERE rn = 1` outside. See RECIPES.md §1. |
| 🔴  | variant access   | 7    | `event_properties:id_house`          | `GET_JSON_OBJECT(event_properties, '$.id_house')` — column is STRING (DataHub). |
| 🟡  | DATE_FORMAT 'u'  | 88   | `DATE_FORMAT(ts, 'u')`               | `u` changed semantics in Spark 3.0; use `'E'` for day-of-week or `'EEEE'` for full name. |
```

- One table per file. If multiple files were edited in the same turn, emit one table per file, in edit order.
- Snippets are truncated to ~60 chars; cite the line number for context.
- The "Dual-runtime suggestion" cell is short — refer to `RECIPES.md` for the full pattern.
- Do not include findings for constructs that work on both runtimes (see `COMPATIBLE.md` for the allow-list).

### Step 5 — On explicit rewrite request

If the user says "reescreve", "fix the lint", "make this EMR-compatible", or similar:

1. Apply the recipes from `RECIPES.md` deterministically.
2. Preserve `sql_conventions.mdc` style (UPPERCASE keywords, snake_case columns, joins on new lines, no `SELECT *`, CTEs over subqueries).
3. After edits, re-run Step 1 (Grep) on the file to verify no critical pattern remains.
4. Report final state:
   - `✅ EMR-compatible — all critical constructs eliminated.` if Step 1 returns empty.
   - Otherwise, repeat the table with what's left.

## Out of scope (do NOT report or touch)

These are framework-level concerns; the user owns them separately:

- `MERGE INTO`, `OPTIMIZE`, `ZORDER BY`, `VACUUM` — abstracted via `tables_customization` in `<dag>_declaration.yml` (see `databricks_conventions.mdc` §"MERGE, OPTIMIZE, and Z-ORDER are Abstracted").
- `CREATE TABLE ... USING DELTA` — the DAG Builder generates DDL.
- `SET spark.databricks.*` configs — live in `cluster.custom_configurations.spark_conf` of the declaration; no-ops on EMR but not a SQL-level concern.
- UDFs registered via `spark_session_configs.udfs` — re-registration is a Python concern, not SQL.

If the user asks about any of these, surface them as out-of-scope and point to the framework rather than touching SQL files.

## Reference files

- [`RECIPES.md`](RECIPES.md) — detailed before/after rewrites for each critical construct, with examples drawn from the actual repo.
- [`COMPATIBLE.md`](COMPATIBLE.md) — allow-list of Databricks-flavored constructs that work unchanged on EMR Spark 3.5 (do not flag these).

## Related rules

- `databricks_conventions.mdc` — current Databricks dialect (the source of truth for what exists today).
- `sql_conventions.mdc` — style rules to preserve in any rewrite output.
- `database_schema_mcp_priority.mdc` — required reading before fetching a column type for a variant rewrite.
- `emr_compatibility.mdc` — project rule that always loads on `**/*.sql` and pins this skill as the lint authority.
