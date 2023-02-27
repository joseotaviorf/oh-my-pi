SELECT
    id,
    hash,
    RIGHT(CAST(hash AS VARCHAR), 64) AS hash_string,
    started_at,
    running_time,
    result_rows,
    native,
    context,
    error,
    executor_id,
    card_id,
    dashboard_id,
    pulse_id,
    database_id,
    cache_hit
FROM
    metabase.query_execution
