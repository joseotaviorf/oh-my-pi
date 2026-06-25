"""Lean SQL templates for map-table-usage governance batch (Databricks Spark SQL).

Query budget (6 SQL executions + post-processing):

| Query | Report section | Output CSV |
| --- | --- | --- |
| superset_catalog_stats | 2 | `superset_catalog_stats.csv` |
| superset_active_charts | 2, 5 | `superset_active_charts.csv` |
| trino_usage_bundle | 3, 5 | `trino_usage_bundle.csv` → 4 derived CSVs |
| metabase_active_cards | 5 | `metabase_active_cards.csv` → `metabase_card_contacts.csv` |
| databricks_all_readers | 4, 5 | `databricks_all_readers.csv` → `databricks_reads.csv` |
| superset_active_contacts | 5 | `superset_active_contacts.csv` |

Post-processing (`postprocess_csvs.py`, no extra SQL):
- `trino_runtime_by_tool`, `trino_superset_reason`, `metabase_summary`, `trino_adhoc_executors` ← bundle
- `trino_adhoc_top` ← top 15 from `trino_adhoc_executors`
- `metabase_card_contacts` ← aggregation of `metabase_active_cards`
- `databricks_reads` ← TOTAL + top 25 from `databricks_all_readers`
"""

from __future__ import annotations

from dataclasses import dataclass


@dataclass(frozen=True)
class QuerySpec:
    name: str
    section: str
    sql: str
    description: str


def _trino_table_queries_cte(
    *,
    catalog: str,
    schema: str,
    table: str,
    start_90d: str,
    end_90d: str,
) -> str:
    return f"""
table_queries AS (
    SELECT
        qi.id_query,
        qi.dt_extraction
    FROM {catalog}.datalake_trino.query_information AS qi
    WHERE qi.database_name = '{schema}'
      AND qi.table_name = '{table}'
      AND qi.dt_extraction >= DATE '{start_90d}'
      AND qi.dt_extraction <= DATE '{end_90d}'
)""".strip()


def _trino_usage_bundle_sql(
    *,
    catalog: str,
    trino_cte: str,
    start_90d: str,
    start_30d: str,
) -> str:
    return f"""
WITH {trino_cte},
usage AS (
    SELECT
        tq.id_query,
        tq.dt_extraction,
        qu.tool,
        qu.query_reason,
        qu.id_metabase_card,
        COALESCE(qu.session_user, qu.user) AS executor_user
    FROM table_queries AS tq
    INNER JOIN {catalog}.datalake_trino.query_usage_information AS qu
        ON tq.id_query = qu.id_query
),
runtime AS (
    SELECT
        'runtime_by_tool' AS result_kind,
        tool AS dim_a,
        CAST(NULL AS STRING) AS dim_b,
        CAST(COUNT(DISTINCT CASE WHEN dt_extraction >= DATE '{start_90d}' THEN id_query END) AS DOUBLE) AS m1,
        CAST(COUNT(DISTINCT CASE WHEN dt_extraction >= DATE '{start_90d}' THEN executor_user END) AS DOUBLE) AS m2,
        CAST(COUNT(DISTINCT CASE WHEN dt_extraction >= DATE '{start_90d}'
            THEN CONCAT(CAST(dt_extraction AS STRING), '|', executor_user) END) AS DOUBLE) AS m3,
        ROUND(COUNT(DISTINCT CASE WHEN dt_extraction >= DATE '{start_90d}'
            THEN CONCAT(CAST(dt_extraction AS STRING), '|', executor_user) END) / 90.0, 2) AS m4,
        CAST(COUNT(DISTINCT CASE WHEN dt_extraction >= DATE '{start_30d}' THEN id_query END) AS DOUBLE) AS m5,
        CAST(COUNT(DISTINCT CASE WHEN dt_extraction >= DATE '{start_30d}' THEN executor_user END) AS DOUBLE) AS m6,
        CAST(COUNT(DISTINCT CASE WHEN dt_extraction >= DATE '{start_30d}'
            THEN CONCAT(CAST(dt_extraction AS STRING), '|', executor_user) END) AS DOUBLE) AS m7,
        ROUND(COUNT(DISTINCT CASE WHEN dt_extraction >= DATE '{start_30d}'
            THEN CONCAT(CAST(dt_extraction AS STRING), '|', executor_user) END) / 30.0, 2) AS m8
    FROM usage
    GROUP BY tool
),
superset_reason AS (
    SELECT
        'superset_reason' AS result_kind,
        query_reason AS dim_a,
        CAST(NULL AS STRING) AS dim_b,
        CAST(COUNT(DISTINCT id_query) AS DOUBLE) AS m1,
        CAST(COUNT(DISTINCT CASE WHEN dt_extraction >= DATE '{start_30d}' THEN id_query END) AS DOUBLE) AS m2,
        CAST(NULL AS DOUBLE) AS m3,
        CAST(NULL AS DOUBLE) AS m4,
        CAST(NULL AS DOUBLE) AS m5,
        CAST(NULL AS DOUBLE) AS m6,
        CAST(NULL AS DOUBLE) AS m7,
        CAST(NULL AS DOUBLE) AS m8
    FROM usage
    WHERE tool = 'Superset'
    GROUP BY query_reason
),
metabase AS (
    SELECT
        'metabase_summary' AS result_kind,
        '_summary' AS dim_a,
        CAST(NULL AS STRING) AS dim_b,
        CAST(COUNT(DISTINCT CASE WHEN id_metabase_card IS NOT NULL THEN id_metabase_card END) AS DOUBLE) AS m1,
        CAST(COUNT(DISTINCT CASE WHEN id_metabase_card IS NOT NULL AND dt_extraction >= DATE '{start_30d}' THEN id_metabase_card END) AS DOUBLE) AS m2,
        CAST(COUNT(DISTINCT CASE WHEN id_metabase_card IS NOT NULL THEN id_query END) AS DOUBLE) AS m3,
        CAST(COUNT(DISTINCT CASE WHEN id_metabase_card IS NOT NULL AND dt_extraction >= DATE '{start_30d}' THEN id_query END) AS DOUBLE) AS m4,
        CAST(COUNT(DISTINCT CASE WHEN id_metabase_card IS NULL THEN id_query END) AS DOUBLE) AS m5,
        CAST(COUNT(DISTINCT CASE WHEN id_metabase_card IS NULL AND dt_extraction >= DATE '{start_30d}' THEN id_query END) AS DOUBLE) AS m6,
        CAST(NULL AS DOUBLE) AS m7,
        CAST(NULL AS DOUBLE) AS m8
    FROM usage
    WHERE tool = 'Metabase'
),
adhoc AS (
    SELECT
        'adhoc_executor' AS result_kind,
        tool AS dim_a,
        executor_user AS dim_b,
        CAST(COUNT(DISTINCT CASE WHEN dt_extraction >= DATE '{start_90d}' THEN id_query END) AS DOUBLE) AS m1,
        CAST(COUNT(DISTINCT CASE WHEN dt_extraction >= DATE '{start_30d}' THEN id_query END) AS DOUBLE) AS m2,
        CAST(COUNT(DISTINCT dt_extraction) AS DOUBLE) AS m3,
        CAST(NULL AS DOUBLE) AS m4,
        CAST(NULL AS DOUBLE) AS m5,
        CAST(NULL AS DOUBLE) AS m6,
        CAST(NULL AS DOUBLE) AS m7,
        CAST(NULL AS DOUBLE) AS m8
    FROM usage
    WHERE tool IN ('yellowbricks', 'other', 'cdp', 'mcp')
      AND tool IS NOT NULL
      AND TRIM(tool) != ''
    GROUP BY tool, executor_user
)
SELECT result_kind, dim_a, dim_b, m1, m2, m3, m4, m5, m6, m7, m8 FROM runtime
UNION ALL
SELECT result_kind, dim_a, dim_b, m1, m2, m3, m4, m5, m6, m7, m8 FROM superset_reason
UNION ALL
SELECT result_kind, dim_a, dim_b, m1, m2, m3, m4, m5, m6, m7, m8 FROM metabase
UNION ALL
SELECT result_kind, dim_a, dim_b, m1, m2, m3, m4, m5, m6, m7, m8 FROM adhoc
""".strip()


def build_governance_queries(
    *,
    catalog: str,
    schema: str,
    table: str,
    start_90d: str,
    end_90d: str,
    start_30d: str,
) -> list[QuerySpec]:
    id_lake = f"{schema}.{table}"
    table_full_uc = f"{catalog}.{schema}.{table}"
    trino_cte = _trino_table_queries_cte(
        catalog=catalog,
        schema=schema,
        table=table,
        start_90d=start_90d,
        end_90d=end_90d,
    )

    return [
        QuerySpec(
            "superset_catalog_stats",
            "2",
            f"""
SELECT
    COUNT(DISTINCT s.id) AS distinct_charts,
    COUNT(DISTINCT ltu.id_dataset) AS distinct_datasets,
    COUNT(DISTINCT CASE WHEN s.entity_status = 'ACTIVE' THEN s.id END) AS active_charts,
    COUNT(DISTINCT CASE WHEN s.entity_status = 'DEPRECATED' THEN s.id END) AS deprecated_charts,
    COUNT(DISTINCT CASE WHEN COALESCE(s.last_90d_views, 0) > 0 THEN s.id END) AS charts_with_views_90d
FROM {catalog}.datalake_superset.lake_tables_usage AS ltu
INNER JOIN {catalog}.datalake_superset.slices AS s
    ON s.id_datasource = ltu.id_dataset
WHERE ltu.id_lake_table = '{id_lake}'
""".strip(),
            "Superset catalog — totals and ACTIVE/DEPRECATED",
        ),
        QuerySpec(
            "superset_active_charts",
            "2",
            f"""
WITH latest_slices AS (
    SELECT *
    FROM (
        SELECT
            s.*,
            ROW_NUMBER() OVER (PARTITION BY s.id ORDER BY s.ts_changed DESC) AS rn
        FROM {catalog}.datalake_superset.slices AS s
    ) AS ranked
    WHERE rn = 1
)
SELECT
    ls.id AS chart_id,
    ls.slice_name AS chart_name,
    COALESCE(
        ls.chart_url,
        CONCAT('https://superset.apps.data-prd.habitat.zone/explore/?slice_id=', ls.id)
    ) AS chart_url,
    ls.entity_status,
    ls.last_90d_views,
    ls.technical_owner,
    ls.last_owner
FROM {catalog}.datalake_superset.lake_tables_usage AS ltu
INNER JOIN latest_slices AS ls
    ON ls.id_datasource = ltu.id_dataset
WHERE ltu.id_lake_table = '{id_lake}'
  AND ls.entity_status = 'ACTIVE'
  AND COALESCE(ls.last_90d_views, 0) > 0
GROUP BY
    ls.id,
    ls.slice_name,
    ls.chart_url,
    ls.entity_status,
    ls.last_90d_views,
    ls.technical_owner,
    ls.last_owner
ORDER BY ls.last_90d_views DESC, ls.slice_name
""".strip(),
            "Superset — ACTIVE charts with views: id, name, URL, owners",
        ),
        QuerySpec(
            "trino_usage_bundle",
            "3",
            _trino_usage_bundle_sql(
                catalog=catalog,
                trino_cte=trino_cte,
                start_90d=start_90d,
                start_30d=start_30d,
            ),
            "Trino — runtime, superset_reason, metabase_summary, adhoc (1 scan)",
        ),
        QuerySpec(
            "metabase_active_cards",
            "5",
            f"""
WITH {trino_cte},
card_execs AS (
    SELECT
        qu.id_metabase_card AS card_id,
        COUNT(DISTINCT CASE WHEN tq.dt_extraction >= DATE '{start_90d}' THEN tq.id_query END) AS executions_90d,
        COUNT(DISTINCT CASE WHEN tq.dt_extraction >= DATE '{start_30d}' THEN tq.id_query END) AS executions_30d
    FROM table_queries AS tq
    INNER JOIN {catalog}.datalake_trino.query_usage_information AS qu
        ON tq.id_query = qu.id_query
    WHERE qu.tool = 'Metabase'
      AND qu.id_metabase_card IS NOT NULL
    GROUP BY qu.id_metabase_card
),
latest_cards AS (
    SELECT id, name, id_user_creator
    FROM (
        SELECT
            id,
            name,
            id_user_creator,
            ROW_NUMBER() OVER (PARTITION BY id ORDER BY ts_updated DESC) AS rn
        FROM {catalog}.datalake_metabase_clean.report_card
    ) AS ranked
    WHERE rn = 1
)
SELECT
    ce.card_id,
    lc.name AS card_name,
    CONCAT('https://metabase.quintoandar.com.br/card/', ce.card_id) AS card_url,
    cu.email AS creator_email,
    ce.executions_90d,
    ce.executions_30d
FROM card_execs AS ce
INNER JOIN latest_cards AS lc
    ON lc.id = ce.card_id
LEFT JOIN {catalog}.datalake_metabase_clean.core_user AS cu
    ON cu.id = lc.id_user_creator
ORDER BY ce.executions_90d DESC, lc.name
""".strip(),
            "Metabase — executed cards: id, name, URL, creator, execs 90d/30d",
        ),
        QuerySpec(
            "databricks_all_readers",
            "4",
            f"""
SELECT
    user_email,
    SUM(read_operations) AS reads_90d,
    SUM(write_operations) AS writes_90d,
    SUM(CASE WHEN dt_event >= DATE '{start_30d}' THEN read_operations ELSE 0 END) AS reads_30d,
    COUNT(DISTINCT dt_event) AS active_days_90d,
    MIN(dt_event) AS first_access,
    MAX(dt_event) AS last_access
FROM {catalog}.datalake_databricks.daily_table_usage_per_user
WHERE table_full_name = '{table_full_uc}'
  AND dt_event >= DATE '{start_90d}'
  AND dt_event <= DATE '{end_90d}'
GROUP BY user_email
ORDER BY reads_90d DESC
""".strip(),
            "Databricks — all readers (90d/30d); generates databricks_reads.csv",
        ),
        QuerySpec(
            "superset_active_contacts",
            "5",
            f"""
WITH latest_slices AS (
    SELECT *
    FROM (
        SELECT
            s.*,
            ROW_NUMBER() OVER (PARTITION BY s.id ORDER BY s.ts_changed DESC) AS rn
        FROM {catalog}.datalake_superset.slices AS s
    ) AS ranked
    WHERE rn = 1
),
base_charts AS (
    SELECT
        ls.id AS chart_id,
        ls.business_owners,
        ls.technical_owner,
        ls.last_owner,
        ls.last_90d_views
    FROM {catalog}.datalake_superset.lake_tables_usage AS ltu
    INNER JOIN latest_slices AS ls
        ON ls.id_datasource = ltu.id_dataset
    WHERE ltu.id_lake_table = '{id_lake}'
      AND ls.entity_status = 'ACTIVE'
),
charts_with_views_30d AS (
    SELECT DISTINCT lg.id_slice AS chart_id
    FROM {catalog}.datalake_superset_clean.logs AS lg
    INNER JOIN base_charts AS bc
        ON bc.chart_id = lg.id_slice
    WHERE lg.action IN ('ChartDataRestApi.data', 'ExploreRestApi.get')
      AND lg.id_slice IS NOT NULL
      AND lg.ts_event >= DATE '{start_30d}'
      AND lg.ts_event <= DATE '{end_90d}'
),
owners AS (
    SELECT chart_id, technical_owner AS contact_email
    FROM base_charts
    WHERE technical_owner IS NOT NULL
    UNION ALL
    SELECT chart_id, last_owner FROM base_charts WHERE last_owner IS NOT NULL
    UNION ALL
    SELECT chart_id, owner_email
    FROM base_charts
    LATERAL VIEW EXPLODE(business_owners) exploded AS owner_email
    WHERE owner_email IS NOT NULL
)
SELECT
    o.contact_email,
    COUNT(DISTINCT CASE WHEN COALESCE(bc.last_90d_views, 0) > 0 THEN o.chart_id END) AS charts_90d,
    COUNT(DISTINCT CASE WHEN c30.chart_id IS NOT NULL THEN o.chart_id END) AS charts_30d
FROM owners AS o
INNER JOIN base_charts AS bc
    ON bc.chart_id = o.chart_id
LEFT JOIN charts_with_views_30d AS c30
    ON c30.chart_id = o.chart_id
WHERE o.contact_email NOT IN ('default', 'Service-data@quintoandar.com.br')
GROUP BY o.contact_email
HAVING COUNT(DISTINCT CASE WHEN COALESCE(bc.last_90d_views, 0) > 0 THEN o.chart_id END) > 0
ORDER BY charts_90d DESC
LIMIT 25
""".strip(),
            "Superset — owners of ACTIVE charts with views (90d/30d)",
        ),
    ]
