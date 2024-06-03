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
    datalake_pipeline.dag AS d
        ON d.id_dag = t.dag
WHERE
  MAKE_DATE(t.year, t.month, t.day) = DATE_ADD(CURRENT_DATE, -1)