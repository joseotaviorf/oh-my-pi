WITH last_dag_inventory_update AS (
  SELECT
    MAX(MAKE_DATE(t.year, t.month, t.day)) AS dt_last_updated
  FROM
    datalake_dag_inventory_clean.table AS t
)
SELECT
  t.table AS id_table,
  t.dag AS id_dag,
  t.task AS id_task,
  d.id_line,
  REGEXP_EXTRACT(t.table, '(\\w+$)') AS table_name,
  REGEXP_EXTRACT(t.table, '(^\\w+)') AS schema,
  t.layer,
  t.criticality,
  t.sla_deadline_localtime,
  t.avg_file_size_in_bytes,
  t.is_delta,
  IF(l.dt_last_updated IS NOT NULL, TRUE, FALSE) AS is_active,
  IF(t.layer IN ('dw', 'metric') AND id_dag NOT LIKE '%datamart%', TRUE, FALSE) AS is_certified_layer,
  MAKE_DATE(t.year, t.month, t.day) AS dt_last_updated
FROM
  datalake_dag_inventory_clean.table AS t
JOIN
  datalake_pipeline.dag AS d
    ON d.id_dag = t.dag
LEFT JOIN
  last_dag_inventory_update AS l
    ON l.dt_last_updated = MAKE_DATE(t.year, t.month, t.day)