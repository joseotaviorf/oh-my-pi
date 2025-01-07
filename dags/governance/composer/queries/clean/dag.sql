SELECT
    dag_id AS id_dag,
    pickle_id AS id_pickle,
    root_dag_id AS id_root_dag,
    default_view,
    description,
    fileloc,
    last_pickled,
    owners,
    schedule_interval,
    scheduler_lock,
    CAST(is_active AS BOOLEAN) AS is_active,
    CAST(is_paused AS BOOLEAN) AS is_paused,
    CAST(is_subdag AS BOOLEAN) AS is_subdag,
    CAST(last_expired AS TIMESTAMP) AS ts_last_expired,
    CAST(last_scheduler_run AS TIMESTAMP) AS ts_last_scheduler_ran
FROM
    datalake_composer_raw.dag