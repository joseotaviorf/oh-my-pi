SELECT
    -- ids
    job_id AS id_job,

    -- non-metrics
    referrer_domain,
    outlet,

    -- metrics
    CAST(views_count AS BIGINT) AS views_count,

    -- timestamps
    TO_TIMESTAMP(first_view_at) AS ts_first_viewed,
    TO_TIMESTAMP(last_view_at) AS ts_last_viewed,
    NOW() AS ts_load,

    -- partitions
    year,
    month,
    day

FROM
    datalake_workable_redshift_raw.job_views