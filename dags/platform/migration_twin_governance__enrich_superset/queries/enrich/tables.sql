with last_table AS (
  SELECT
    *,
    regexp_extract(table_name,'\\[(Bedrock|Cross|Data Ops \\& Governance|Fintech|For Brokers|For Rent|For Sale|Growth|Internacional|MLOps|Rede|Support and Services|People|Agents|Primitives)\\]') company_line,
    RANK() OVER (PARTITION BY id ORDER BY ts_changed DESC) most_recent_rank
  FROM datalake_superset_clean.tables
), table_owners as (
  SELECT
    squ.id_table,
    collect_set(u.email) as owners_email
  FROM datalake_superset_clean.sqlatable_user squ
  JOIN datalake_superset.ab_user u ON u.id = squ.id_user
  GROUP BY 1
), logs as (
  select
    id_slice,
    count(0) last_90d_views
  FROM datalake_superset_clean.logs
  WHERE id_slice IS NOT NULL
    AND action = 'ChartDataRestApi.data'
    AND ts_event > CURRENT_DATE - interval '90' day
  GROUP BY 1
), columns_list AS (
  SELECT
    id_table,
    collect_set(named_struct("column_name",column_name, "column_type", type, "description", description)) columns
  FROM datalake_superset.table_columns
  GROUP BY 1
), metrics_list AS (
  SELECT
    id_table,
    collect_set(named_struct("metric_name",metric_name, "verbose_name", verbose_name, "description", description, "metric_type", metric_type, "expression", expression)) metrics
  FROM datalake_superset_clean.sql_metrics
  GROUP BY 1
)
SELECT
  lt.id,
  lt.table_name,
  if(nullif(lt.sql_code,'') is null, "physical", "virtual") AS dataset_type,
  lt.schema,
  lt.description,
  lt.sql_code,
  cl.columns,
  ml.metrics,
  lt.company_line, -- no line from physical datasets
  array_remove(regexp_extract_all(lt.table_name, '\\[([^\\]]+)\\]'), lt.company_line) AS tags,
  extra:certification.certified_by,
  tow.owners_email AS business_owners,
  u_creator.email AS technical_owner,
  u_changed.email AS last_owner,
  array_contains(regexp_extract_all(lt.table_name, '\\[([^\\]]+)\\]'), 'Core') AS is_semantic_layer,
  lt.ts_created,
  lt.ts_changed,
  "superset" AS platform
FROM last_table lt
JOIN datalake_superset.ab_user u_creator ON u_creator.id = lt.id_user_created
JOIN datalake_superset.ab_user u_changed ON u_changed.id = lt.id_user_changed
LEFT JOIN table_owners tow ON tow.id_table = lt.id
JOIN columns_list cl ON cl.id_table = lt.id
LEFT JOIN metrics_list ml ON ml.id_table = lt.id
WHERE lt.most_recent_rank = 1
