WITH exploded_metric_vality AS (
  SELECT
    *,
    'Support' AS vertical,
    EXPLODE(SEQUENCE(dt_start, dt_end)) AS dt_metric_valid
  FROM
    datalake_gsheets_clean.target_support_kpis
  UNION ALL
  SELECT
    *,
    'Service' AS vertical,
    EXPLODE(SEQUENCE(dt_start, dt_end)) AS dt_metric_valid
  FROM
    datalake_gsheets_clean.target_service_kpis
)
SELECT DISTINCT
  metric_name,
  team,
  granularity,
  vertical,
  target,
  DATE_TRUNC(granularity, dt_metric_valid) AS dt_target
FROM
  exploded_metric_vality