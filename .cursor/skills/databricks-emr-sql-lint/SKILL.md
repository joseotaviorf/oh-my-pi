---
name: databricks-emr-sql-lint
description: Lints SQL files under bi-etl-ejuice dags/ for Databricks-only constructs that break, change behavior, or silently degrade performance on EMR Spark 3.5. Operates in dual-runtime mode (queries must run on both Databricks DBR 16.4 and EMR Spark 3.5). Auto-invokes when editing or creating any .sql file in dags/. Detects QUALIFY, GROUP BY ALL, IFF, DECODE, DATEDIFF 3-arg, variant access (column:key), legacy DATE_FORMAT pattern letters, Databricks-only optimizer hints (RANGE_JOIN, SKEW) that EMR ignores, and — via validate_join_shapes.py's sqlglot-based join-shape analysis — any join whose ON condition has no extractable hash key (a written-out range join, or a disjunctive/OR join across two columns), which Spark can only plan as a BroadcastNestedLoopJoin; reports findings with severity (critical / performance / attention), line numbers, snippets, and dual-runtime-safe rewrite suggestions; uses the database MCP to inspect column types before suggesting variant rewrites; never rewrites automatically (lint-only) unless the user explicitly asks. Use when modifying any .sql file in dags/, when the user mentions EMR migration, Spark 3.5 compatibility, dual-runtime, nested loop, OR join, range join, BroadcastNestedLoopJoin, a query that is fast on Databricks but slow on EMR, or asks "is this query EMR-compatible?".
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
| `/\*\+[^*]*\bRANGE_JOIN\b` | 🟠 performance | Databricks-only `RANGE_JOIN` optimizer hint |
| `/\*\+[^*]*\bSKEW\b` | 🟠 performance | Databricks-only `SKEW` optimizer hint |
| `\bDATE_FORMAT\s*\([^)]*['"][^'"]*[uULFcE]` | 🟡 attention | `DATE_FORMAT` with pattern letters changed since Spark 3.0 |

**Severity legend:**
- 🔴 **critical** — errors (`ParseException`) or *changes results* on EMR Spark 3.5. Must be rewritten before running on EMR.
- 🟠 **performance** — **identical results** on both runtimes, but the construct is a Databricks-only optimizer hint that EMR Spark 3.5 **silently ignores**, causing a severe slowdown (e.g. a `RANGE_JOIN` `BETWEEN` join degrades to a nested-loop/cartesian join running on 1-2 tasks). No parse error, no wrong data — just a performance cliff. Rewrite to an equi-join + window (see `RECIPES.md` §8).
- 🟡 **attention** — works, but subtle semantic differences to verify.

### Step 2 — Filter false positives

Variant access regex (`[a-zA-Z_]\w*:[\["a-zA-Z_]`) is noisy. Discard matches that are:
- Inside a string literal (`'...'` or `"..."`).
- Inside a single-line comment (`-- ...`) or block comment (`/* ... */`).
- A reserved word followed by `:` (e.g., `CASE … WHEN x THEN y`, `BEGIN:`, `END:`) — these are not variant accesses.
- A timestamp/time literal (`'12:30:00'`, `'2026-04-24T14:30'`) — never matches because the pattern requires `[a-zA-Z_]` immediately before the `:`, but double-check when the literal is unquoted.

When in doubt, keep the match and let the report show it; the engineer can dismiss false positives.

**Exception — optimizer hints are NOT comments for this lint.** The 🟠 performance patterns (`RANGE_JOIN`, `SKEW`) live inside Spark hint blocks `/*+ ... */`, which look like block comments but are semantically significant. Do **not** discard a `RANGE_JOIN` / `SKEW` match just because it sits inside `/*+ ... */` — that is exactly where it belongs. Only discard these when they appear inside a string literal or a *plain* comment (`-- ...` or `/* ... */` without the leading `+`).

### Step 1b — Join-shape analysis (`validate_join_shapes.py`)

Grep catches the `RANGE_JOIN` *hint* — it cannot tell whether a join is actually a range or
disjunctive join written **without** the hint, which is what actually shipped in both
incidents this check exists for (`enrich_cyber/queue_timeline.sql`, a `BETWEEN` join with no
hint; `enrich_transactional_entities/entities.sql`, `ON a = b OR c = d`). Both built
multi-hundred-MB broadcasts and hung production DAGs. A line-based regex is not accurate
enough for this: it produced 82 false positives across this repo's corpus and missed real
cases by truncating multi-line conditions. Use the AST-based script instead:

```bash
uv run --project packages/bietlejuice-compiler python \
  packages/bietlejuice-compiler/scripts/ci_cd/validate_join_shapes.py \
  --paths <the edited file> --json
```

Parse the JSON `violations` array. Each finding has `kind` (`OR_JOIN`, `NO_EQUI_KEY`, or
`UNPARSEABLE`), `line_no`, and `text` (the flagged condition). Fold both `OR_JOIN` and
`NO_EQUI_KEY` into the Step 4 report as 🟠 **performance** findings — same severity class as
`RANGE_JOIN`/`SKEW`, since the result is identical on both runtimes and only parallelism is
lost. `UNPARSEABLE` means the file has a construct sqlglot's Spark dialect cannot handle
(distinct from EMR incompatibility) — mention it but do not guess at a rewrite.

Also runnable directly by a DE checking their own work, without going through this skill:

```bash
make validate-join-shapes paths=dags/<domain>/<dag>     # a DAG folder
make validate-join-shapes domain=<domain>               # a whole domain
make validate-join-shapes-all                           # whole-repo audit
```

### Step 3 — Resolve variant column types via Database MCP

For every variant access match, the rewrite depends on the column's Spark type. Before suggesting a rewrite:

1. Parse the SQL to find the table that owns the column (look in `FROM` and `JOIN` clauses; correlate via the alias prefix in `alias.column:key`).
2. Follow `database_schema_mcp_priority.mdc`: call the database MCP's `describe_table` on the source table.
3. Inspect the column's type:
   - **STRING** (raw JSON text) → suggest `GET_JSON_OBJECT(col, '$.path')`, wrap in `TRY_CAST(... AS <type>)` if a typed cast was present.
   - **STRUCT** → suggest dot notation `col.path` (or `col.path.subpath` for nesting).
   - **MAP<STRING, _>** → suggest bracket notation `col['key']`.
4. **Fallback** if the MCP is unavailable, errors, or the table cannot be located: surface the finding with severity `🔴 critical` and the suggestion `-- TODO: confirm column type before EMR migration; default rewrite is GET_JSON_OBJECT(col, '$.path') if STRING JSON`. State explicitly in the report that the MCP could not be consulted (per `database_schema_mcp_priority.mdc`).

For all other critical patterns (QUALIFY, GROUP BY ALL, IFF, DECODE, DATEDIFF 3-arg) and the 🟠 performance hints (RANGE_JOIN, SKEW), no schema lookup is needed — apply the recipe from `RECIPES.md` directly.

### Step 4 — Report

Output **one markdown table** at the end of the agent's reply for this turn (after the file edit's tool result). Suppress entirely if no findings.

```
**EMR Spark 3.5 lint — `<relative/path/to/file.sql>`**

| Sev | Construct        | Line | Snippet                              | Dual-runtime suggestion                                      |
|-----|------------------|------|--------------------------------------|--------------------------------------------------------------|
| 🔴  | QUALIFY          | 42   | `QUALIFY ROW_NUMBER() OVER (...) = 1`| Wrap as CTE with `rn`; filter `WHERE rn = 1` outside. See RECIPES.md §1. |
| 🔴  | variant access   | 7    | `event_properties:id_house`          | `GET_JSON_OBJECT(event_properties, '$.id_house')` — column is STRING (DataHub). |
| 🟠  | RANGE_JOIN hint  | 35   | `SELECT /*+ RANGE_JOIN(eb, 150) */`  | Hint ignored on EMR → BETWEEN join becomes nested-loop/cartesian. Equi-join + running window. See RECIPES.md §8. |
| 🟠  | OR_JOIN          | 61   | `ON u.id = hl.id_related OR u.uuid_person = hl.id_related` | No hash key across the OR → BroadcastNestedLoopJoin. UNION of equi-joins. See RECIPES.md §9. |
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
3. After edits, re-run **both** Step 1 (Grep) and Step 1b (`validate_join_shapes.py --paths <file> --json`) to verify no critical or performance pattern remains.
4. Report final state:
   - `✅ EMR-compatible — all critical and performance constructs eliminated.` if both Step 1 and Step 1b return empty.
   - Otherwise, repeat the table with what's left.

> A 🟠 performance rewrite must be **behavior-preserving**: results are already identical across runtimes, so the only goal is restoring parallelism. State the equivalence assumption explicitly (e.g. "cumulative window equals the `BETWEEN` count because the exploded rows cover every day in the range", or for §9 "UNION reproduces OR semantics: one row matching both predicates still yields one row, two distinct matches still yield two") so a reviewer can confirm it. **A rewrite of this kind is not done until it has been verified against synthetic data** — plan-only confirmation (no more `BroadcastNestedLoopJoin` in the output) is necessary but not sufficient; also diff the before/after row sets on a fixture covering the join's boundary cases (match by each key independently, match by neither, one row matching multiple keys, duplicate relation rows).

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
