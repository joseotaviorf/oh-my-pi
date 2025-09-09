SELECT
    -- ids
    id,

    -- non-metrics
    name,
    slug,
    domain,
    provider_slug,
    job_board_type,

    -- metrics (booleans)
    available AS is_available,
    free AS is_free,
    is_feed,
    affiliate AS is_affiliate,

    -- timestamps
    NOW() AS ts_load

FROM
    datalake_workable_redshift_raw.job_boards