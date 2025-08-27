SELECT
    -- ids
    id,
    -- text fields
    name,
    -- timestamps
    NOW() AS ts_load,
    -- partitions
    year,
    month,
    day
FROM
    datalake_greenhouse_raw.tags_candidate
