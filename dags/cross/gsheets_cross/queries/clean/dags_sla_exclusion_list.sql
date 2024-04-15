SELECT
    context,
    dag,
    DATE(dt_dag_added) AS dt_dag_added,
    NOW() AS ts_load
FROM
    datalake_gsheets_raw.dags_sla_exclusion_list