# Rewrite recipes — Databricks → EMR Spark 3.5 (dual-runtime safe)

Every recipe below produces SQL that runs **identically** on Databricks DBR 16.4 (Spark 3.5 + Photon) and on plain EMR Spark 3.5. Examples use real snippets from `bi-etl-ejuice/dags/` where useful.

All rewrites must preserve `sql_conventions.mdc` style: UPPERCASE keywords, snake_case columns, joins on new lines, CTEs over subqueries, no `SELECT *`.

---

## 1. `QUALIFY` → CTE + `WHERE rn = 1`

**Why:** `QUALIFY` is a Snowflake/Databricks/Teradata extension. Apache Spark only adds it in 4.0; EMR Spark 3.5 raises `ParseException`.

**Recipe:** wrap the query in a CTE that materializes the window result as `rn`, then filter on the outer `SELECT`. Move the explicit column list inside the CTE (no `SELECT *`).

**Before:**

```sql
SELECT
    id_event,
    status,
    ts_updated
FROM
    datalake_events.transactional
QUALIFY ROW_NUMBER() OVER (PARTITION BY id_event ORDER BY ts_updated DESC) = 1
```

**After:**

```sql
WITH ranked AS (
    SELECT
        id_event,
        status,
        ts_updated,
        ROW_NUMBER() OVER (PARTITION BY id_event ORDER BY ts_updated DESC) AS rn
    FROM
        datalake_events.transactional
)
SELECT
    id_event,
    status,
    ts_updated
FROM
    ranked
WHERE
    rn = 1
```

**Caveats:**

- Pick a CTE name that reflects intent (`deduped`, `latest_per_id`) — not a generic `t` or `q`.
- If `QUALIFY` filters on `RANK()` or `DENSE_RANK()`, mirror the same window function inside the CTE.
- If the original `SELECT` already had a CTE, append the new one to the existing `WITH` chain rather than nesting.

---

## 2. `GROUP BY ALL` → explicit column list

**Why:** Apache Spark adds `GROUP BY ALL` in 4.0; EMR Spark 3.5 raises `ParseException`.

**Recipe:** enumerate every non-aggregated expression from the `SELECT` list in the `GROUP BY` clause, in the same order they appear in `SELECT`.

**Before:**

```sql
SELECT
    region,
    DATE_TRUNC('month', dt_event) AS month_event,
    COUNT(*) AS total,
    SUM(amount) AS total_amount
FROM
    datalake_sales.transactions
GROUP BY ALL
```

**After:**

```sql
SELECT
    region,
    DATE_TRUNC('month', dt_event) AS month_event,
    COUNT(*) AS total,
    SUM(amount) AS total_amount
FROM
    datalake_sales.transactions
GROUP BY
    region,
    DATE_TRUNC('month', dt_event)
```

**Caveats:**

- Repeat the **expression**, not the alias. `GROUP BY month_event` works in Databricks but not on Spark 3.5 outside specific contexts; the safe form is repeating the expression.
- For long expressions, you may use `GROUP BY 1, 2` (positional) — Spark 3.5 accepts it — but the project's `sql_conventions.mdc` prefers explicit expressions for readability.

---

## 3. `IFF(cond, t, f)` → `IF(cond, t, f)`

**Why:** `IFF` is a Snowflake/Databricks alias. Spark exposes the same logic as `IF` (since 1.0).

**Before:**

```sql
SELECT
    id_user,
    IFF(is_active, 'on', 'off') AS user_state
FROM
    datalake_ebdb_clean.user
```

**After:**

```sql
SELECT
    id_user,
    IF(is_active, 'on', 'off') AS user_state
FROM
    datalake_ebdb_clean.user
```

**Alternative** (when nested or when readability suffers): use `CASE WHEN cond THEN t ELSE f END`.

**Caveats:**

- `IF` is a function, not a control statement — it lives in expression position. Don't confuse with stored-procedure `IF ... THEN` (which the pipeline doesn't use anyway).

---

## 4. `DECODE(expr, k1, v1, k2, v2, default)` → `CASE WHEN`

**Why:** `DECODE` is an Oracle/Databricks function. Spark 3.5 has no `DECODE`.

**Recipe:** expand to a `CASE WHEN expr = k_i THEN v_i ... ELSE default END` chain.

**Before:**

```sql
SELECT
    id_log,
    DECODE(severity_code, 1, 'low', 2, 'medium', 3, 'high', 'unknown') AS severity_label
FROM
    fintech_cyber_legal.logs_juridical
```

**After:**

```sql
SELECT
    id_log,
    CASE severity_code
        WHEN 1 THEN 'low'
        WHEN 2 THEN 'medium'
        WHEN 3 THEN 'high'
        ELSE 'unknown'
    END AS severity_label
FROM
    fintech_cyber_legal.logs_juridical
```

**Caveat — NULL semantics differ:**

- `DECODE(x, NULL, 'a', 'b')` returns `'a'` when `x IS NULL` (DECODE treats `NULL = NULL` as true).
- `CASE WHEN x = NULL THEN 'a' ELSE 'b' END` always returns `'b'` (because `x = NULL` is `NULL`, not true).
- If the original query relies on this DECODE quirk, use `CASE WHEN x IS NOT DISTINCT FROM k THEN v ...` (Spark 3.5 supports `IS NOT DISTINCT FROM`) or an explicit `CASE WHEN x IS NULL THEN v_null WHEN x = k THEN v ...` chain.

---

## 5. `DATEDIFF(unit, start, end)` → `TIMESTAMPDIFF(unit, start, end)`

**Why:** Spark 3.5 only supports `DATEDIFF(end_date, start_date)` (2 args, returns days). The Databricks 3-arg form with a unit is added in Spark 4.0. `TIMESTAMPDIFF` exists in both Databricks and Spark 3.4+.

**Recipe by unit:**

| Original | Dual-runtime rewrite |
|----------|----------------------|
| `DATEDIFF(DAY, start, end)` | `DATEDIFF(end, start)` *(2-arg form, args reversed)* |
| `DATEDIFF(MONTH, start, end)` | `TIMESTAMPDIFF(MONTH, start, end)` |
| `DATEDIFF(YEAR, start, end)` | `TIMESTAMPDIFF(YEAR, start, end)` |
| `DATEDIFF(HOUR, start, end)` | `TIMESTAMPDIFF(HOUR, start, end)` |
| `DATEDIFF(MINUTE, start, end)` | `TIMESTAMPDIFF(MINUTE, start, end)` |
| `DATEDIFF(SECOND, start, end)` | `TIMESTAMPDIFF(SECOND, start, end)` |
| `DATEDIFF(WEEK, start, end)` | `TIMESTAMPDIFF(WEEK, start, end)` |
| `DATEDIFF(QUARTER, start, end)` | `TIMESTAMPDIFF(QUARTER, start, end)` |

**Before:**

```sql
SELECT
    id_contract,
    DATEDIFF(MONTH, dt_signed, CURRENT_TIMESTAMP()) AS months_active
FROM
    datalake_ebdb_clean.contract
```

**After:**

```sql
SELECT
    id_contract,
    TIMESTAMPDIFF(MONTH, dt_signed, CURRENT_TIMESTAMP()) AS months_active
FROM
    datalake_ebdb_clean.contract
```

**Caveats:**

- For the `DAY` case, `DATEDIFF(end, start)` is the right rewrite — note the **arguments are reversed** versus the 3-arg form.
- `TIMESTAMPDIFF` is calendar-based (whole units crossed), same as the Databricks 3-arg `DATEDIFF`. Behavior matches.

---

## 6. Variant access (`column:key`, `column:["k"]`, `column:a:b.c`) — schema-driven rewrite

**Why:** The `:` operator (Databricks variant accessor) only exists in Databricks DBR 11+ on STRING/VARIANT columns. Apache Spark adds the `VARIANT` type and operator in 4.0; on EMR Spark 3.5 the `:` raises `ParseException`.

**Recipe — decide by column type (use the database MCP):**

```
1. Identify the source table that owns the column (look at FROM/JOIN; correlate via alias).
2. Use the database MCP (per database_schema_mcp_priority.mdc) to describe_table.
3. Find the column's Spark type. Branch:
   - STRING (raw JSON text)   → GET_JSON_OBJECT(col, '$.path')
   - STRUCT                   → col.path  (and col.path.subpath for nesting)
   - MAP<STRING, _>           → col['key']
4. If a CAST/TRY_CAST wrapped the variant access, keep it on the outer expression.
5. If MCP is unavailable, default to GET_JSON_OBJECT and add a `-- TODO: verify column type` comment.
```

### 6a. STRING JSON column (most common in `dags/`)

**Before** (column is `STRING` containing JSON):

```sql
SELECT
    e.id_event,
    TRY_CAST(e.event_properties:id_house AS INT) AS id_house,
    CAST(e.event_properties:contractId AS INT) AS id_contract,
    e.user_data:["user_phone"] AS user_phone
FROM
    datalake_cdp_clean.transactional AS e
```

**After:**

```sql
SELECT
    e.id_event,
    TRY_CAST(GET_JSON_OBJECT(e.event_properties, '$.id_house') AS INT) AS id_house,
    CAST(GET_JSON_OBJECT(e.event_properties, '$.contractId') AS INT) AS id_contract,
    GET_JSON_OBJECT(e.user_data, '$.user_phone') AS user_phone
FROM
    datalake_cdp_clean.transactional AS e
```

### 6b. STRUCT column

**Before** (column is `STRUCT<id_house: INT, status: STRING>`):

```sql
SELECT
    e.event_properties:id_house AS id_house,
    e.event_properties:status AS status
FROM
    datalake_events.parsed AS e
```

**After:**

```sql
SELECT
    e.event_properties.id_house AS id_house,
    e.event_properties.status AS status
FROM
    datalake_events.parsed AS e
```

### 6c. MAP<STRING, STRING> column

**Before** (column is `MAP<STRING, STRING>`):

```sql
SELECT
    p.tags:campaign AS campaign,
    p.tags:source AS source
FROM
    datalake_marketing.props AS p
```

**After:**

```sql
SELECT
    p.tags['campaign'] AS campaign,
    p.tags['source'] AS source
FROM
    datalake_marketing.props AS p
```

### 6d. Nested path (`col:a:b.c`)

The `:` chain in Databricks combines variant traversal and dot navigation. Flatten into a single JSONPath or struct accessor:

| Original | If STRING JSON | If STRUCT |
|----------|----------------|-----------|
| `attributes:analysis_output:scr.scr_data` | `GET_JSON_OBJECT(attributes, '$.analysis_output.scr.scr_data')` | `attributes.analysis_output.scr.scr_data` |
| `extra:certification.certified_by` | `GET_JSON_OBJECT(extra, '$.certification.certified_by')` | `extra.certification.certified_by` |

### 6e. Fallback when schema lookup fails

If the database MCP cannot resolve the table or column type, emit the rewrite suggestion with `GET_JSON_OBJECT` (the safest default for ingested raw/clean tables) **and** add a `-- TODO` comment so a human verifies before merging:

```sql
-- TODO: verify column type for `event_properties` before EMR migration
TRY_CAST(GET_JSON_OBJECT(e.event_properties, '$.id_house') AS INT) AS id_house,
```

State explicitly in the lint report that the MCP could not be consulted (per `database_schema_mcp_priority.mdc`).

---

## 7. `DATE_FORMAT` with legacy pattern letters (🟡 attention)

**Why:** Spark 3.0 switched from the legacy `SimpleDateFormat` pattern letters to the new `DateTimeFormatter` (Java 8+) letters. Several letters changed meaning. Databricks honors both via a fallback; EMR Spark 3.5 with `spark.sql.legacy.timeParserPolicy=CORRECTED` (the default) does not.

**Letters that changed semantics (lint flags only these):**

| Letter | Legacy meaning (Spark 2.x) | Spark 3.0+ meaning | Safe substitute |
|--------|----------------------------|---------------------|------------------|
| `u` | Day-of-week number (1=Mon) | Year (without era) | Use `E` (day-of-week short name) or `EEEE` (full name); for ISO day-of-week number use `e` |
| `U` | Week of year | (Reserved / different) | Use `w` (week-of-year) |
| `L` | Month | Month-of-year (standalone) | Use `M` (regular month) |
| `F` | Day of week in month | Day-of-week-in-month | Validate intent; usually `E` is what was meant |
| `c` | Day of week | Day-of-week (standalone) | Use `E` or `e` |
| `E` | Day name (text) | Day-of-week name | (No change; safe — flagged only when neighbor letters present) |

**Patterns used in the repo that are SAFE (do not flag):**

- `'yyyy-MM-dd'`, `'yyyy-MM-dd HH:mm:ss'`, `'yyyy-MM-dd\'T\'HH:mm:ss.SSS\'Z\''` — fully compatible.

**When flagged, suggest:** "Pattern letter `<X>` changed meaning in Spark 3.0; verify intent and substitute per the table in `RECIPES.md` §7." Do not auto-rewrite — pattern intent is human judgement.

---

## After applying any rewrite

1. Re-run the seven critical Greps from `SKILL.md` Step 1 on the file.
2. If all return empty: `✅ EMR-compatible — all critical constructs eliminated.`
3. Otherwise: re-emit the lint table with the remaining items.
4. Preserve all `{load_start_date}` / `{load_end_date}` placeholders and `{{ }}` literal-brace escapes (see `databricks_conventions.mdc` §"Literal Braces").
