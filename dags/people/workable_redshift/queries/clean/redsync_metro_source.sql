SELECT
    -- ids
    job_id AS id_job,

    -- non-metrics
    category,
    source,
    source_domain,

    -- metrics
    CAST(num_views AS BIGINT) AS num_views,
    CAST(num_candidates AS BIGINT) AS num_candidates,
    CAST(num_hired AS BIGINT) AS num_hired,
    CAST(num_moved AS BIGINT) AS num_moved,

    -- timestamps
    NOW() AS ts_load

FROM
    datalake_workable_redshift_raw.redsync_metro_source