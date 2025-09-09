SELECT
    -- ids
    id,

    -- non-metrics
    domain,

    -- metrics (booleans)
    enabled AS is_enabled,

    -- timestamps
    NOW() AS ts_load,

    -- partitions
    year,
    month,
    day

FROM
    datalake_workable_redshift_raw.pseudo_boards
WHERE 
    MAKE_DATE(year, month, day) BETWEEN DATE('{load_start_date}') AND DATE('{load_end_date}')
QUALIFY 
    updated_at = MAX(updated_at) OVER (PARTITION BY id)