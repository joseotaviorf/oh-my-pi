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

## 8. `RANGE_JOIN` / `SKEW` optimizer hints → equi-join + window (🟠 performance)

**Why:** `RANGE_JOIN` and `SKEW` are **Databricks-only optimizer hints**. They do not exist in Apache Spark, so EMR Spark 3.5 **silently ignores** them (they are just hint comments). Results stay identical — but a range predicate join (`ON b BETWEEN a.lo AND a.hi`) that Databricks optimizes via the `RANGE_JOIN` bin strategy degrades on EMR to a **`BroadcastNestedLoopJoin` / `CartesianProduct`**: O(N×M), poorly parallelized (often 1-2 tasks), so a job that runs in minutes on Databricks can run for hours on EMR while the cluster sits nearly idle. This is a **performance cliff, not a correctness or parse error** — which is why it is 🟠, not 🔴.

**This recipe also applies with no `RANGE_JOIN` hint present at all.** The hint is one way to *write* a range join, but the failure is about the **join's shape**, not the hint: any `ON` condition whose only predicates are inequalities (`BETWEEN`, `>=`/`<=`, etc.) gives Spark no hash key regardless of hints, and gets the identical `BroadcastNestedLoopJoin` treatment. `enrich_cyber/queue_timeline.sql`'s range join (fixed in PR #27631) never had a `RANGE_JOIN` hint — it built a 186 MiB broadcast on a driving table with a single file, so the entire join ran on **one task**. `validate_join_shapes.py` (`.cursor/skills/databricks-emr-sql-lint/SKILL.md` Step 1b) catches this shape whether or not the hint is present; grepping for `RANGE_JOIN` alone does not.

**Recipe:** eliminate the range (`BETWEEN` / `>=` … `<=`) join. The most common shape in this repo is *"count rows from a small calendar/reference table that fall in a per-row range"*. When one side is an exploded per-day (or per-unit) sequence that already covers every point in the range, replace the range join with:

1. An **equi-join** of each exploded point against the reference table (`ON ref.point = exploded.point`), producing a 0/1 flag.
2. A **running-window aggregate** (`SUM(flag) OVER (PARTITION BY key ORDER BY point)`) that reproduces the "count within `[start, point]`" the range join computed.

This turns O(N×M) into a shuffle + sort (equi-join + window) that scales across the whole cluster.

**Before** (from `dags/support_and_service/enrich_customer_demand/queries/enrich/backlog_metrics.sql`):

```sql
days_off AS (
  SELECT /*+ RANGE_JOIN(eb, 150) */
    id_task,
    dt_interval,
    COUNT(1) AS days_off
  FROM
    exploded_backlog AS eb
  INNER JOIN
    weekends_and_holidays AS nw
      ON nw.dt_non_working BETWEEN DATE(eb.ts_started) AND eb.dt_interval
  GROUP BY 1,2
)
```

**After:**

```sql
marked_backlog AS (
  SELECT
    eb.id_task,
    eb.dt_interval,
    CASE
      WHEN nw.dt_non_working IS NOT NULL THEN 1
      ELSE 0
    END AS is_non_working
  FROM
    exploded_backlog AS eb
  LEFT JOIN
    weekends_and_holidays AS nw
      ON nw.dt_non_working = eb.dt_interval
),
days_off AS (
  SELECT
    id_task,
    dt_interval,
    SUM(is_non_working) OVER (
      PARTITION BY id_task
      ORDER BY dt_interval
    ) AS days_off
  FROM
    marked_backlog
)
```

**Why it is equivalent:** `exploded_backlog` is `EXPLODE(SEQUENCE(DATE(ts_started), …))`, so it already contains **every** day in `[ts_started, dt_interval]`. Flagging each day that is non-working and taking a cumulative `SUM` ordered by day yields exactly the count of non-working days in `[ts_started, dt_interval]` — the same number the `BETWEEN` join produced. The outer query's `LEFT JOIN days_off … COALESCE(days_off, 0)` behaves identically (the old `INNER JOIN` dropped zero-count rows; those become `0` via `COALESCE` either way).

**Caveats:**

- Only valid when the exploded side is **contiguous and complete** over the range (a `SEQUENCE`/calendar spine). If the join range is not covered by discrete equi-join keys, this rewrite does not apply — instead pre-bucket both sides into a coarse key and equi-join on the bucket, then filter the residual range in a `WHERE` (manual binning, the OSS equivalent of what `RANGE_JOIN` automates).
- The default window frame (`RANGE BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW`) is what you want here; it matches `ROWS` because `dt_interval` is unique per `id_task`.
- `SKEW` hints have no OSS equivalent — rely on AQE skew-join handling instead (`spark.sql.adaptive.enabled` / `spark.sql.adaptive.skewJoin.enabled`, on by default in Spark 3.5). Just remove the hint; do not try to emulate it in SQL.
- Do **not** merely delete the `RANGE_JOIN` hint and keep the `BETWEEN` join — that leaves the cartesian join in place. The join itself must change.

---

## 9. Disjunctive (`OR`) join across two columns → `UNION` of equi-joins (🟠 performance)

**Why:** `ON a.x = b.k OR a.y = b.k` (or the equivalent with the columns swapped) is not an
equi-join. Spark's planner extracts hash keys only from `AND`-conjuncts at the top level of
an `ON` condition (`ExtractEquiJoinKeys`); a top-level `OR` gives it nothing to hash on, so
the only physical plan is a **`BroadcastNestedLoopJoin`** — O(N×M) against the *entire*
build-side table, not just the matching rows.

This is the shape that hung `bietlejuice.enrich_transactional_entities` on EMR (never
completed a run; fixed in PRs #27637, #27641, #27643). `datalake_ebdb_clean
.house_listing_relation.id_related` is a `STRING` holding either a numeric `user.id` or a
`user.uuid_person`, resolved with:

```sql
LEFT JOIN datalake_ebdb_clean.user AS u
    ON u.id = hl.id_related
    OR u.uuid_person = hl.id_related
```

On the production cluster this built a **~634 MiB broadcast** (`autoBroadcastJoinThreshold`
is 10 MB — only `BroadcastNestedLoopJoin` ignores it) and stalled the query indefinitely: of
724 tasks in the affected stage, the 688 holding no matching rows finished in ~1s each; the 8
that did hold matching rows read the broadcast, entered the nested loop, and never returned.

**Recipe:** split the disjunction into two equi-joins against the *same* target table, one
per predicate, and combine with `UNION` (not `UNION ALL`) in a small resolver CTE:

**Before** (from `enrich_transactional_entities/queries/enrich/entities.sql`, pre-#27643):

```sql
LEFT JOIN
    datalake_ebdb_clean.house_listing_relation AS hl
        ON hl.id = rv.id_house
        AND hl.related_as = 'PROPERTY_OWNER'
LEFT JOIN
    datalake_ebdb_clean.user AS u
        ON (u.id = hl.id_related
        OR u.uuid_person = hl.id_related)
```

**After:**

```sql
owner_resolved AS (
    SELECT
        hl.id AS id_relation,
        u.id AS id_owner
    FROM
        datalake_ebdb_clean.house_listing_relation AS hl
    INNER JOIN
        datalake_ebdb_clean.user AS u
            ON u.id = hl.id_related
    WHERE
        hl.related_as = 'PROPERTY_OWNER'

    UNION

    SELECT
        hl.id AS id_relation,
        u.id AS id_owner
    FROM
        datalake_ebdb_clean.house_listing_relation AS hl
    INNER JOIN
        datalake_ebdb_clean.user AS u
            ON u.uuid_person = hl.id_related
    WHERE
        hl.related_as = 'PROPERTY_OWNER'
),
...
LEFT JOIN
    owner_resolved AS u
        ON u.id_relation = hl.id
```

and swap the outer `COALESCE(u.id, h.id_user)` to `COALESCE(u.id_owner, h.id_user)`.

**Why `UNION` and not `UNION ALL`:** under the original `OR`, a single `user` row that
matches **both** predicates (e.g. its `id` happens to equal `id_related`'s text *and* its
`uuid_person` also matches — a real case when `uuid_person` values can look numeric)
contributes exactly **one** row. Two **distinct** users that each match one predicate
contribute **two**. `UNION` reproduces both outcomes exactly (dedup on the whole row set does
nothing to the second case, since the two rows differ in `id_owner`). `UNION ALL` would
double-count the first case; a naive rewrite as two `LEFT JOIN`s + `COALESCE(u1.id, u2.id)`
would silently collapse the second case down to whichever join is listed first.

**Verification example** (Spark 3.5.3, from PR #27637 — this is the shape every §9 rewrite
must be checked against, not just a plan diff):

```
BEFORE plan : BroadcastHashJoin x18, BroadcastNestedLoopJoin x1
AFTER  plan : BroadcastHashJoin x19
rows before=2200  after=2200
diff: in BEFORE not in AFTER=0   in AFTER not in BEFORE=0
```

Build a fixture that specifically exercises: a match by the first key, a match by the second
key, a match by neither (the `LEFT JOIN` must still emit the row), **one row matching both
keys**, **two distinct rows each matching one key**, and a duplicate relation row. The two
collision cases are exactly what a naive rewrite gets wrong, and a plan-only check (counting
`BroadcastNestedLoopJoin`) cannot catch a row-count regression — only a data diff can.

**Caveats:**

- Only valid when both sides of the `OR` compare the *same* pair of tables — if the columns
  belong to genuinely different join targets, this is a different problem (likely two
  separate joins that were incorrectly merged into one).
- `INNER JOIN` inside the CTE, not `LEFT JOIN` — the CTE's job is to enumerate matches; the
  outer query's existing `LEFT JOIN owner_resolved` is what preserves non-matching rows.
- Check for the same pattern nearby: this defect was found duplicated across five files in
  one afternoon (two Glue views, three files in Databricks-only DAGs, and a copy inlined
  directly in a downstream query). Grep the repo for the same table/column pair before
  declaring the fix complete.

---

## After applying any rewrite

1. Re-run the Greps from `SKILL.md` Step 1 on the file (critical + 🟠 performance patterns).
2. Re-run Step 1b (`validate_join_shapes.py --paths <file> --json`) — §8 and §9 rewrites must
   drop the file's `OR_JOIN`/`NO_EQUI_KEY` count to zero.
3. For any §8/§9 rewrite, verify equivalence against synthetic data (see the "Verification
   example" in §9) — a clean plan alone does not confirm the rewrite is correct.
4. If Grep and Step 1b both return empty: `✅ EMR-compatible — all critical and performance constructs eliminated.`
5. Otherwise: re-emit the lint table with the remaining items.
6. Preserve all `{load_start_date}` / `{load_end_date}` placeholders and `{{ }}` literal-brace escapes (see `databricks_conventions.mdc` §"Literal Braces").
