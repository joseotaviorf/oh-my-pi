SELECT
    run_id AS uuid_run,
    model,
    mode,
    completed_calls,
    duration_seconds,
    calls_per_second,
    CAST(observed_at AS TIMESTAMP) AS ts_observed,
    s3_key,
    ts_load,
    year,
    month,
    day
FROM
    datalake_vocs_machina_meta_raw.throughput_observations
