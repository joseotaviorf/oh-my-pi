WITH last_table AS (
  SELECT
    id,
    table_name,
    sql_code,
    schema,
    description,
    extra,
    id_user_created,
    id_user_changed,
    ts_created,
    ts_changed,
    REGEXP_EXTRACT(
      table_name,
      '\\[(Bedrock|Cross|Data Ops \\& Governance|Fintech|For Brokers|For Rent|For Sale|Growth|Internacional|MLOps|Rede|Support and Services|People|Agents|Primitives)\\]'
    ) AS company_line,
    RANK() OVER (PARTITION BY id ORDER BY ts_changed DESC) AS most_recent_rank
  FROM datalake_superset_clean.tables
), table_owners AS (
  SELECT
    squ.id_table,
    COLLECT_SET(u.email) AS owners_email
  FROM datalake_superset_clean.sqlatable_user AS squ
  JOIN datalake_superset.ab_user AS u
    ON u.id = squ.id_user
  GROUP BY
    1
), logs AS (
  SELECT
    id_slice,
    COUNT(0) AS last_90d_views
  FROM datalake_superset_clean.logs
  WHERE
    id_slice IS NOT NULL
    AND action = 'ChartDataRestApi.data'
    AND ts_event > CURRENT_DATE - INTERVAL '90' DAY
  GROUP BY
    1
), columns_list AS (
  SELECT
    id_table,
    COLLECT_SET(
      NAMED_STRUCT('column_name', column_name, 'column_type', type, 'description', description)
    ) AS columns
  FROM datalake_superset.table_columns
  GROUP BY
    1
), metrics_list AS (
  SELECT
    id_table,
    COLLECT_SET(
      NAMED_STRUCT(
        'metric_name',
        metric_name,
        'verbose_name',
        verbose_name,
        'description',
        description,
        'metric_type',
        metric_type,
        'expression',
        expression
      )
    ) AS metrics
  FROM datalake_superset_clean.sql_metrics
  GROUP BY
    1
)
SELECT
  lt.id,
  lt.table_name,
  IF(NULLIF(lt.sql_code, '') IS NULL, 'physical', 'virtual') AS dataset_type,
  lt.schema,
  lt.description,
  lt.sql_code,
  cl.columns,
  ml.metrics,
  lt.company_line, /* no line from physical datasets */
  ARRAY_REMOVE(REGEXP_EXTRACT_ALL(lt.table_name, '\\[([^\\]]+)\\]'), lt.company_line) AS tags,
  GET_JSON_OBJECT(lt.extra, '$.certification.certified_by') AS certified_by,
  tow.owners_email AS business_owners,
  u_creator.email AS technical_owner,
  u_changed.email AS last_owner,
  ARRAY_CONTAINS(REGEXP_EXTRACT_ALL(lt.table_name, '\\[([^\\]]+)\\]'), 'Core') AS is_semantic_layer,
  lt.ts_created,
  lt.ts_changed,
  'superset' AS platform
FROM last_table AS lt
JOIN datalake_superset.ab_user AS u_creator
  ON u_creator.id = lt.id_user_created
JOIN datalake_superset.ab_user AS u_changed
  ON u_changed.id = lt.id_user_changed
LEFT JOIN table_owners AS tow
  ON tow.id_table = lt.id
JOIN columns_list AS cl
  ON cl.id_table = lt.id
LEFT JOIN metrics_list AS ml
  ON ml.id_table = lt.id
WHERE
  lt.most_recent_rank = 1
