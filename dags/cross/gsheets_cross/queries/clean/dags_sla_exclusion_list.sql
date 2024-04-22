SELECT
    context,
    dag,
    DATE(dt_dag_added) AS dt_dag_added,
    DATE(dt_dag_removed) AS dt_dag_removed,
    NOW() AS ts_load
FROM
    datalake_gsheets_raw.dags_sla_exclusion_list