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
    NOW() AS ts_load,

    -- partitions
    year,
    month,
    day

FROM
    datalake_workable_redshift_raw.job_boards
WHERE 
    MAKE_DATE(year, month, day) BETWEEN DATE('{load_start_date}') AND DATE('{load_end_date}')
QUALIFY 
    updated_at = MAX(updated_at) OVER (PARTITION BY id)