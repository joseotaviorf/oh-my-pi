SELECT
    CAST(sync_id AS STRING) AS id_sync,
    CAST(sync_run_id AS STRING) AS id_sync_run,
    CAST(model_id AS STRING) AS id_model,
    CAST(primary_key AS STRING) AS primary_key,
    CAST(destination AS STRING) AS destination,
    CAST(model_name AS STRING) AS model_name,
    CAST(error AS STRING) AS error,
    CAST(status AS STRING) AS status,

    CAST(num_planned_add AS DOUBLE) AS num_planned_add,
    CAST(num_planned_change AS DOUBLE) AS num_planned_change,
    CAST(num_planned_remove AS DOUBLE) AS num_planned_remove,
    CAST(num_attempted_add AS DOUBLE) AS num_attempted_add,
    CAST(num_attempted_change AS DOUBLE) AS num_attempted_change,
    CAST(num_attempted_remove AS DOUBLE) AS num_attempted_remove,
    CAST(num_succeeded_add AS DOUBLE) AS num_succeeded_add,
    CAST(num_succeeded_change AS DOUBLE) AS num_succeeded_change,
    CAST(num_succeeded_remove AS DOUBLE) AS num_succeeded_remove,
    CAST(num_failed_add AS DOUBLE) AS num_failed_add,
    CAST(num_failed_change AS DOUBLE) AS num_failed_change,
    CAST(num_failed_remove AS DOUBLE) AS num_failed_remove,

    CAST(started_at AS TIMESTAMP) AS ts_started,
    CAST(finished_at AS TIMESTAMP) AS ts_finished

FROM datalake_hightouch_logs_raw.sync_runs_databricks
