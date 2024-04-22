SELECT
    id_dag,
    dag_owner,
    DATE(dt_added) AS dt_added,
    DATE(dt_removed) AS dt_removed
FROM
    datalake_gsheets_raw.dags_special_scheduler