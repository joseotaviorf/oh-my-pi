# SQL templates — map table usage

Replace placeholders before execution:

| Placeholder | Example |
| --- | --- |
| `{catalog}` | `quintoandar_prod` |
| `{schema}` | `dw_public` |
| `{table}` | `dim_house_listing` |
| `{replacement_schema}` | `dw_rent` |
| `{replacement_table}` | `dim_house_listing` |
| `{start_90d}` | `2026-03-18` |
| `{end_90d}` | `2026-06-16` |
| `{start_30d}` | `2026-05-17` |
| `{table_full_uc}` | `quintoandar_prod.dw_public.dim_house_listing` |
| `{id_lake_table}` | `dw_public.dim_house_listing` |

Engine: **Databricks Spark SQL** (Commands API via `scripts/run_governance_batch.py`). Do not run these via Trino MCP.

**Lean batch (6 SQL + post-processing):** `governance_queries.py` + `postprocess_csvs.py` — see docstrings.
Prefer `run_governance_batch.py` over copy-paste; use `--skip-existing` on re-runs.

> **Source of truth** for the batch runner: `governance_queries.py`. Sections 2–4 below are
> reference snippets (exploratory / replacement mode); they may differ from the lean batch.

---

## 1. Pipeline

### 1a. Repo scan (shell)

```bash
rg -l '{schema}\.{table}' dags/ --glob '*.sql'
```

### 1b. Replacement equivalence

**Only when user says:** `Map the usage of table X and its replacement by Y`.

**Do not assume** fixed columns (`status`, `city_group`, `sk_house_listing`, …). Every table pair needs an explicit **grain** derived from metadata, producer SQL, and column intersection **before** running SQL.

---

#### Step 0 — Define grain (mandatory)

| Input | Where |
| --- | --- |
| Table description & grain | `metadata/**/{table}.yml` for source and substitute |
| Producer logic | `queries/**/{table}.sql` (upstream joins, filters, dedup) |
| Column intersection | Columns with the **same name** on both sides (or documented rename map) |

Document in the report (subsection **What each table stores**):

| Field | Example |
| --- | --- |
| `{grain_description}` | *1 row per listing version* · *1 row per tenant status period* · *1 row per contract event* |
| `{join_cols}` | `sk_house_listing` · `sk_house_listing, ts_status_start` · `id_tenant, city_group, ts_start` |
| `{compare_cols}` | Business columns to match on overlap — **intersection minus join cols minus `ts_load`** |
| `{period_col}` | *(optional)* Timestamp on exclusive rows for Period column — pick one col from `{join_cols}` or a status-start ts |
| `{entity_cols}` | *(optional, near-miss only)* Subset of `{join_cols}` **without** the timestamp — e.g. `id_tenant, city_group` |
| `{ts_col}` | *(optional, near-miss only)* The timestamp column from `{join_cols}` |

**Optional shortcuts** (only after metadata confirms):

| Pattern | When | `{join_cols}` |
| --- | --- | --- |
| Row copy | Producer SQL is `SELECT … FROM substitute` with identical layout | All business columns → use **row-level `EXCEPT`** (below) instead of key anti-join |
| Single surrogate key | 1 row per SK, SK unique on both sides | One column, e.g. `sk_house_listing` |
| Composite period key | Multiple rows per entity, period identified by ts in key | Entity cols + `ts_*` start column |

See **§1b examples** at the end for prospect-status and listing grains — copy the pattern, not the column names.

---

#### Placeholders (generic)

| Placeholder | Meaning |
| --- | --- |
| `{grain_key_expr_source}` | Spark expression → string key per source row, e.g. `CONCAT(CAST(sk_house_listing AS STRING), '\|', CAST(ts_status_start AS STRING))` |
| `{grain_key_expr_replacement}` | Same for substitute (use replacement column names when they differ) |
| `{join_predicate}` | Full `ON` clause, e.g. `d.sk_house_listing = e.sk_house_listing AND d.ts_status_start <=> e.ts_status_start` |
| `{compare_cols}` | Comma-separated columns to compare on matched rows |
| `{period_col}` | Column for `YEAR`/`MONTH` breakdown of exclusives (omit query if not needed) |
| `{entity_join_predicate}` | Near-miss only: join exclusives to other side **without** ts, e.g. `o.id_tenant = x.id_tenant AND o.city_group = x.city_group` |

Build `{grain_key_expr_*}` from `{join_cols}` — one `CAST(col AS STRING)` per column, joined with `'\|'`.

---

#### Summary — row counts

```sql
SELECT '{schema}.{table}' AS table_name, COUNT(*) AS row_cnt
FROM {schema}.{table}
UNION ALL
SELECT '{replacement_schema}.{replacement_table}', COUNT(*)
FROM {replacement_schema}.{replacement_table};
```

Save as `replacement_equivalence_summary.csv`. Add `COUNT(DISTINCT …)` on `{grain_key_expr}` when duplicate keys are possible.

---

#### Diff — exclusive keys (generic)

```sql
WITH source AS (
  SELECT {grain_key_expr_source} AS grain_key
  FROM {schema}.{table}
),
substitute AS (
  SELECT {grain_key_expr_replacement} AS grain_key
  FROM {replacement_schema}.{replacement_table}
)
SELECT 'only_in_{schema}' AS side, COUNT(*) AS key_count
FROM source AS s LEFT ANTI JOIN substitute AS t ON s.grain_key = t.grain_key
UNION ALL
SELECT 'only_in_{replacement_schema}', COUNT(*)
FROM substitute AS t LEFT ANTI JOIN source AS s ON s.grain_key = t.grain_key
UNION ALL
SELECT 'in_both', COUNT(*)
FROM source AS s INNER JOIN substitute AS t ON s.grain_key = t.grain_key;
```

Save as `replacement_equivalence_diff.csv`.

**Note:** `in_both` counts **row pairs** when duplicate keys exist on either side. If duplicates are possible, also run **row-level `EXCEPT`** or compare `COUNT(*)` vs `COUNT(DISTINCT grain_key)` per side.

---

#### Row-level parity (optional — passthrough / identical layout)

When both tables share the same business columns (typical `dw_listing_temp` mirrors):

```sql
SELECT COUNT(*) AS rows_only_in_source FROM (
  SELECT {compare_cols_business_only}
  FROM {schema}.{table}
  EXCEPT
  SELECT {compare_cols_business_only}
  FROM {replacement_schema}.{replacement_table}
);
-- Repeat with sides swapped for rows_only_in_substitute
```

Exclude `ts_load` and any load-only columns. **0 rows** on both sides ⇒ full row parity regardless of duplicate keys.

---

#### Exclusive keys — when they occurred (optional)

Run only when `{period_col}` is set and exclusive counts > 0:

```sql
WITH source AS (
  SELECT {grain_key_expr_source} AS grain_key, {period_col} AS period_ts
  FROM {schema}.{table}
),
substitute AS (
  SELECT {grain_key_expr_replacement} AS grain_key, {period_col} AS period_ts
  FROM {replacement_schema}.{replacement_table}
),
only_source AS (
  SELECT s.period_ts
  FROM source AS s LEFT ANTI JOIN substitute AS t ON s.grain_key = t.grain_key
),
only_substitute AS (
  SELECT s.period_ts
  FROM substitute AS s LEFT ANTI JOIN source AS t ON s.grain_key = t.grain_key
)
SELECT 'only_in_{schema}' AS side, YEAR(period_ts) AS yr, MONTH(period_ts) AS mo, COUNT(*) AS key_count
FROM only_source GROUP BY 1, 2, 3
UNION ALL
SELECT 'only_in_{replacement_schema}', YEAR(period_ts), MONTH(period_ts), COUNT(*)
FROM only_substitute GROUP BY 1, 2, 3
ORDER BY side, yr, mo;
```

Save as `replacement_equivalence_diff_by_period.csv`.

---

#### Overlap attributes (generic)

For each column in `{compare_cols}`, add one `SUM(CASE WHEN dw_col <=> rent_col …)` line.

```sql
WITH matched AS (
  SELECT
    d.{col_a} AS dw_{col_a},
    e.{col_a} AS rent_{col_a}
    -- repeat for each column in {compare_cols}
  FROM {schema}.{table} AS d
  INNER JOIN {replacement_schema}.{replacement_table} AS e
    ON {join_predicate}
)
SELECT
  COUNT(*) AS matched_rows,
  SUM(CASE WHEN dw_{col_a} <=> rent_{col_a} THEN 1 ELSE 0 END) AS {col_a}_match
  -- one match column per {compare_cols} entry
FROM matched;
```

Save as `replacement_equivalence_overlap_attributes.csv`.

---

#### Categorical value map (optional — label drift)

When a `{compare_col}` is categorical and match rate < 100%, map value pairs on overlap:

```sql
SELECT d.{categorical_col} AS source_value, e.{categorical_col} AS substitute_value, COUNT(*) AS row_cnt
FROM {schema}.{table} AS d
INNER JOIN {replacement_schema}.{replacement_table} AS e
  ON {join_predicate}
GROUP BY 1, 2
ORDER BY row_cnt DESC;
```

Save as `replacement_equivalence_value_map.csv` (rename in report to the column, e.g. `status_detail` map).

---

#### Near-miss exclusives (optional)

Run only when **all** of:

1. `replacement_equivalence_diff` shows exclusives > 0 on either side
2. `{join_cols}` includes a **timestamp** and at least one **entity** column
3. Business hypothesis: exclusives may be the same entity with a slightly different timestamp

**Closest row** = on the other table, same `{entity_cols}`, the row whose `{ts_col}` is **nearest in time**; **≤60s** ⇒ near-miss.

```sql
WITH source AS (
  SELECT
    {grain_key_expr_source} AS grain_key,
    {entity_col_exprs_source},
    {ts_col_source} AS ts_col
  FROM {schema}.{table}
),
substitute AS (
  SELECT
    {grain_key_expr_replacement} AS grain_key,
    {entity_col_exprs_replacement},
    {ts_col_replacement} AS ts_col
  FROM {replacement_schema}.{replacement_table}
),
only_source AS (
  SELECT s.* FROM source AS s
  LEFT ANTI JOIN substitute AS t ON s.grain_key = t.grain_key
),
only_substitute AS (
  SELECT t.* FROM substitute AS t
  LEFT ANTI JOIN source AS s ON s.grain_key = t.grain_key
),
source_stats AS (
  SELECT
    COUNT(*) AS exclusive_count,
    SUM(CASE WHEN c.min_abs_sec_diff IS NULL THEN 1 ELSE 0 END) AS no_same_entity,
    SUM(CASE WHEN c.min_abs_sec_diff IS NOT NULL THEN 1 ELSE 0 END) AS same_entity_diff_ts,
    SUM(CASE WHEN c.min_abs_sec_diff IS NOT NULL AND c.min_abs_sec_diff <= 60 THEN 1 ELSE 0 END) AS nearest_within_60s,
    SUM(CASE WHEN c.min_abs_sec_diff IS NOT NULL AND c.min_abs_sec_diff <= 3600 THEN 1 ELSE 0 END) AS nearest_within_1h,
    SUM(CASE WHEN c.min_abs_sec_diff IS NOT NULL AND c.min_abs_sec_diff > 86400 THEN 1 ELSE 0 END) AS nearest_over_1d
  FROM only_source AS o
  LEFT JOIN (
    SELECT o.grain_key,
      MIN(ABS(UNIX_TIMESTAMP(o.ts_col) - UNIX_TIMESTAMP(x.ts_col))) AS min_abs_sec_diff
    FROM only_source AS o
    INNER JOIN substitute AS x ON {entity_join_predicate_source_to_substitute}
    GROUP BY 1
  ) AS c ON o.grain_key = c.grain_key
),
substitute_stats AS (
  -- mirror for only_substitute vs source
  SELECT COUNT(*) AS exclusive_count,
    SUM(CASE WHEN c.min_abs_sec_diff IS NULL THEN 1 ELSE 0 END) AS no_same_entity,
    SUM(CASE WHEN c.min_abs_sec_diff IS NOT NULL THEN 1 ELSE 0 END) AS same_entity_diff_ts,
    SUM(CASE WHEN c.min_abs_sec_diff IS NOT NULL AND c.min_abs_sec_diff <= 60 THEN 1 ELSE 0 END) AS nearest_within_60s,
    SUM(CASE WHEN c.min_abs_sec_diff IS NOT NULL AND c.min_abs_sec_diff <= 3600 THEN 1 ELSE 0 END) AS nearest_within_1h,
    SUM(CASE WHEN c.min_abs_sec_diff IS NOT NULL AND c.min_abs_sec_diff > 86400 THEN 1 ELSE 0 END) AS nearest_over_1d
  FROM only_substitute AS o
  LEFT JOIN (
    SELECT o.grain_key,
      MIN(ABS(UNIX_TIMESTAMP(o.ts_col) - UNIX_TIMESTAMP(x.ts_col))) AS min_abs_sec_diff
    FROM only_substitute AS o
    INNER JOIN source AS x ON {entity_join_predicate_substitute_to_source}
    GROUP BY 1
  ) AS c ON o.grain_key = c.grain_key
)
SELECT 'only_in_{schema}' AS side, * FROM source_stats
UNION ALL
SELECT 'only_in_{replacement_schema}', * FROM substitute_stats;
```

Save as `replacement_equivalence_near_miss.csv`.

**Report:** publish the **Near-miss logic trees** block (see [report-template.md](report-template.md)) — two ASCII trees (source-only / substitute-only), with sub-group **and** total % on the ≤60s and >60s branches.

---

#### Per pipeline consumer — volume / checksum

```sql
WITH consumer_output AS (
    -- Paste pipeline SQL; swap {schema}.{table} ↔ {replacement_schema}.{replacement_table}
    ...
)
SELECT COUNT(*) AS row_cnt FROM consumer_output;
```

Repeat null + `XXHASH64` per output column when full query is feasible. Document `fragment_only` when > ~30 min.

---

#### Report branching

| Condition | Publish |
| --- | --- |
| **0 exclusives** both sides + overlap / row `EXCEPT` **100%** | One **Prod parity** sentence — no Q&A, no value map, omit “What to do …” |
| **Exclusives > 0** or field drift | Short Q&A · value map for drifting categorical cols · near-miss **only if** `{entity_cols}` + `{ts_col}` were defined |
| **Row `EXCEPT` = 0** but duplicate keys | State duplicate-key structure; parity is row multiset, not unique key |

---

#### §1b examples (fill placeholders — do not copy column names blindly)

**Example A — single SK (listing dimension):**

- `{join_cols}` = `sk_house_listing`
- `{compare_cols}` = `status`, `ts_listing_version_end`, `status_reason`, …
- Skip near-miss

**Example B — composite period (prospect status):**

- `{join_cols}` = `id_tenant`, `city_group`, `ts_start`
- `{compare_cols}` = `status`, `ts_end`, `status_detail`
- `{entity_cols}` = `id_tenant`, `city_group` · `{ts_col}` = `ts_start` → run near-miss

**Example C — listing status history:**

- `{join_cols}` = `sk_house_listing`, `ts_status_start`
- `{compare_cols}` = `status_history`, `ts_status_end`, `status_change_reason`, …
- Skip near-miss unless business asks

**Example D — arbitrary fact:**

- Read metadata → define `{join_cols}` from declared grain → `{compare_cols}` = metric/dimension intersection → run generic diff + overlap only.

---

## 2. Superset catalog

### 2.1 Superset — charts referencing table

```sql
SELECT
    COUNT(DISTINCT s.id) AS distinct_charts,
    COUNT(DISTINCT ltu.id_dataset) AS distinct_datasets
FROM {catalog}.datalake_superset.lake_tables_usage AS ltu
INNER JOIN {catalog}.datalake_superset.slices AS s
    ON s.id_datasource = ltu.id_dataset
WHERE ltu.id_lake_table = '{id_lake_table}';
```

### 2.2 Superset — catalog enriched (charts × dashboards)

```sql
WITH target_slices AS (
    SELECT DISTINCT s.id AS chart_id
    FROM {catalog}.datalake_superset.lake_tables_usage AS ltu
    INNER JOIN {catalog}.datalake_superset.slices AS s
        ON s.id_datasource = ltu.id_dataset
    WHERE ltu.id_lake_table = '{id_lake_table}'
),
chart_dashboard AS (
    SELECT ts.chart_id, d.id AS dashboard_id
    FROM target_slices AS ts
    INNER JOIN {catalog}.datalake_superset.dashboards AS d
        ON array_contains(d.lineage_charts, ts.chart_id)
)
SELECT
    s.id AS chart_id,
    s.slice_name AS chart_name,
    s.entity_status AS chart_entity_status,
    d.id AS dashboard_id,
    d.entity_name AS dashboard_name,
    d.entity_status AS dashboard_entity_status,
    d.daily_users_last_90d AS dashboard_daily_users_90d,
    d.last_90d_views AS dashboard_last_90d_views
FROM chart_dashboard AS cd
INNER JOIN {catalog}.datalake_superset.slices AS s ON s.id = cd.chart_id
INNER JOIN {catalog}.datalake_superset.dashboards AS d ON d.id = cd.dashboard_id
ORDER BY d.daily_users_last_90d DESC, s.last_90d_views DESC;
```

### 2.3 Metabase — distinct cards (90d)

```sql
SELECT COUNT(DISTINCT qu.id_metabase_card) AS distinct_metabase_cards
FROM {catalog}.datalake_trino.query_information AS qi
INNER JOIN {catalog}.datalake_trino.query_usage_information AS qu
    ON qi.id_query = qu.id_query
WHERE qi.database_name = '{schema}'
  AND qi.table_name = '{table}'
  AND qu.tool = 'Metabase'
  AND qu.id_metabase_card IS NOT NULL
  AND qi.dt_extraction >= DATE '{start_90d}'
  AND qi.dt_extraction <= DATE '{end_90d}';
```

---

## 3. Trino runtime

### 3.1 Probe — event count

```sql
SELECT COUNT(*) AS query_information_rows
FROM {catalog}.datalake_trino.query_information
WHERE database_name = '{schema}'
  AND table_name = '{table}'
  AND dt_extraction >= DATE '{start_90d}'
  AND dt_extraction <= DATE '{end_90d}';
```

### 3.2 Summary by tool (90d / 30d)

```sql
SELECT
    qu.tool,
    COUNT(DISTINCT CASE WHEN qi.dt_extraction >= DATE '{start_90d}' THEN qi.id_query END) AS executions_90d,
    COUNT(DISTINCT CASE WHEN qi.dt_extraction >= DATE '{start_90d}'
        THEN COALESCE(qu.session_user, qu.user) END) AS distinct_users_90d,
    COUNT(DISTINCT CASE WHEN qi.dt_extraction >= DATE '{start_30d}' THEN qi.id_query END) AS executions_30d,
    COUNT(DISTINCT CASE WHEN qi.dt_extraction >= DATE '{start_30d}'
        THEN COALESCE(qu.session_user, qu.user) END) AS distinct_users_30d
FROM {catalog}.datalake_trino.query_information AS qi
INNER JOIN {catalog}.datalake_trino.query_usage_information AS qu
    ON qi.id_query = qu.id_query
WHERE qi.database_name = '{schema}'
  AND qi.table_name = '{table}'
  AND qi.dt_extraction >= DATE '{start_90d}'
  AND qi.dt_extraction <= DATE '{end_90d}'
GROUP BY qu.tool
ORDER BY executions_90d DESC;
```

### 3.3 Daily distinct users

```sql
SELECT
    qi.dt_extraction AS dt,
    qu.tool,
    COUNT(DISTINCT COALESCE(qu.session_user, qu.user)) AS daily_distinct_users
FROM {catalog}.datalake_trino.query_information AS qi
INNER JOIN {catalog}.datalake_trino.query_usage_information AS qu
    ON qi.id_query = qu.id_query
WHERE qi.database_name = '{schema}'
  AND qi.table_name = '{table}'
  AND qi.dt_extraction >= DATE '{start_90d}'
  AND qi.dt_extraction <= DATE '{end_90d}'
GROUP BY 1, 2
ORDER BY 1, 2;
```

### 3.4 Superset — query_reason breakdown

```sql
SELECT
    qu.query_reason,
    COUNT(DISTINCT qi.id_query) AS executions
FROM {catalog}.datalake_trino.query_information AS qi
INNER JOIN {catalog}.datalake_trino.query_usage_information AS qu
    ON qi.id_query = qu.id_query
WHERE qi.database_name = '{schema}'
  AND qi.table_name = '{table}'
  AND qu.tool = 'Superset'
  AND qi.dt_extraction >= DATE '{start_90d}'
  AND qi.dt_extraction <= DATE '{end_90d}'
GROUP BY qu.query_reason
ORDER BY executions DESC;
```

### 3.5 Superset runtime detail (top 50)

```sql
SELECT
    qu.query_reason,
    COALESCE(qu.session_user, qu.user) AS executor_user,
    qu.id_slice_superset,
    s.slice_name AS chart_name,
    d.id AS dashboard_id,
    d.entity_name AS dashboard_name,
    COUNT(DISTINCT qi.id_query) AS executions_90d
FROM {catalog}.datalake_trino.query_information AS qi
INNER JOIN {catalog}.datalake_trino.query_usage_information AS qu
    ON qi.id_query = qu.id_query
LEFT JOIN {catalog}.datalake_superset.slices AS s ON s.id = qu.id_slice_superset
LEFT JOIN {catalog}.datalake_superset.dashboards AS d ON d.id = qu.id_dash_superset
WHERE qi.database_name = '{schema}'
  AND qi.table_name = '{table}'
  AND qu.tool = 'Superset'
  AND qi.dt_extraction >= DATE '{start_90d}'
  AND qi.dt_extraction <= DATE '{end_90d}'
GROUP BY 1, 2, 3, 4, 5, 6
ORDER BY executions_90d DESC
LIMIT 50;
```

### 3.6 Metabase top cards

```sql
SELECT
    qu.id_metabase_card AS card_id,
    COALESCE(qu.session_user, qu.user) AS executor_user,
    COUNT(DISTINCT qi.id_query) AS executions_90d
FROM {catalog}.datalake_trino.query_information AS qi
INNER JOIN {catalog}.datalake_trino.query_usage_information AS qu
    ON qi.id_query = qu.id_query
WHERE qi.database_name = '{schema}'
  AND qi.table_name = '{table}'
  AND qu.tool = 'Metabase'
  AND qi.dt_extraction >= DATE '{start_90d}'
  AND qi.dt_extraction <= DATE '{end_90d}'
GROUP BY 1, 2
ORDER BY executions_90d DESC
LIMIT 15;
```

### 3.7 Ad-hoc tools (yellowbricks, other, cdp, mcp)

```sql
SELECT
    qu.tool,
    COALESCE(qu.session_user, qu.user) AS executor_user,
    COUNT(DISTINCT qi.id_query) AS executions_90d,
    COUNT(DISTINCT qi.dt_extraction) AS active_days_90d
FROM {catalog}.datalake_trino.query_information AS qi
INNER JOIN {catalog}.datalake_trino.query_usage_information AS qu
    ON qi.id_query = qu.id_query
WHERE qi.database_name = '{schema}'
  AND qi.table_name = '{table}'
  AND qu.tool IN ('yellowbricks', 'other', 'cdp', 'mcp')
  AND qi.dt_extraction >= DATE '{start_90d}'
  AND qi.dt_extraction <= DATE '{end_90d}'
GROUP BY 1, 2
ORDER BY executions_90d DESC
LIMIT 15;
```

---

## 4. Databricks direct reads

### 4.1 Summary by user

```sql
SELECT
    user_email,
    SUM(read_operations) AS reads_90d,
    SUM(write_operations) AS writes_90d,
    COUNT(DISTINCT dt_event) AS active_days_90d,
    MIN(dt_event) AS first_access,
    MAX(dt_event) AS last_access
FROM {catalog}.datalake_databricks.daily_table_usage_per_user
WHERE table_full_name = '{table_full_uc}'
  AND dt_event >= DATE '{start_90d}'
  AND dt_event <= DATE '{end_90d}'
GROUP BY user_email
ORDER BY reads_90d DESC;
```

### 4.2 Daily distinct readers

```sql
SELECT
    dt_event AS dt,
    COUNT(DISTINCT user_email) AS distinct_users,
    SUM(read_operations) AS reads
FROM {catalog}.datalake_databricks.daily_table_usage_per_user
WHERE table_full_name = '{table_full_uc}'
  AND dt_event >= DATE '{start_90d}'
  AND dt_event <= DATE '{end_90d}'
GROUP BY 1
ORDER BY 1 DESC
LIMIT 10;
```

---

## Queries doc (`{slug}_usage_queries.md`)

User-facing appendix listing **every SQL** that fed the analysis report. Generate with
`scripts/export_queries_md.py` (do not hand-write from scratch).

### Required structure

1. **Title:** `SQL queries — usage mapping \`{schema}.{table}\``
2. **Analysis report:** link to `{slug}_usage_deprecation_analysis.md` (never "Companion")
3. **Parameters:** table, catalog, date windows, cluster
4. **Index:** columns `Query` · `What it measures` · `Report section` · `CSV` (never header `§`).
   Pipeline row: `Table usage across the repo (dags/**/*.sql) — no SQL query` (not columns-only wording).
5. **One section per governance query:** report section, output CSV path, full ` ```sql ` block (dates substituted).
   **Do not** add a Pipeline section or a reproduction appendix.

### Generator

```bash
uv run python .cursor/skills/map-table-usage/scripts/export_queries_md.py \
  --schema {schema} --table {table} --cluster <CLUSTER_ID> \
  --output table_usage_map/{slug}/<YYYY-MM-DD>/{slug}_usage_queries.md \
  --end-date <YYYY-MM-DD>
```

SQL source of truth for sections 2–4: `governance_queries.py` (same templates as the batch runner).

