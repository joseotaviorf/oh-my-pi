WITH last_dag_inventory_update AS (
  SELECT
    MAX(MAKE_DATE(t.year, t.month, t.day)) AS dt_last_update
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
  t.avg_file_size_in_bytes,
  t.is_delta
FROM
  datalake_dag_inventory_clean.table AS t
JOIN
  last_dag_inventory_update AS l
    ON l.dt_last_update = MAKE_DATE(t.year, t.month, t.day)
JOIN
  datalake_pipeline.dag AS d
    ON d.id_dag = t.dag
JOIN
  datalake_composer_clean.dag AS dd
    ON dd.id_dag = d.id_dag
WHERE
  DATE(dd.ts_last_scheduler_ran) = CURRENT_DATE -- Assuring only active DAGs on Airflow, due to interface bugs which can make it still appear on dag_inventory