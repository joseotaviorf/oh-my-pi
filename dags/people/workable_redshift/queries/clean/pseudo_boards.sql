SELECT
    -- ids
    id,

    -- non-metrics
    domain,

    -- metrics (booleans)
    enabled AS is_enabled,

    -- timestamps
    NOW() AS ts_load

FROM
    datalake_workable_redshift_raw.pseudo_boards