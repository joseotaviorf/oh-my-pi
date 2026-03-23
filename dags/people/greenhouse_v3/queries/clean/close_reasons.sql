SELECT
    -- ids
    id AS id_close_reason,
    -- text fields
    name,
    -- timestamps
    NOW() AS ts_load,
    -- partitions
    year,
    month,
    day
FROM
    datalake_greenhouse_v3_raw.close_reasons
