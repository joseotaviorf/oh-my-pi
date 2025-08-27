SELECT
    -- ids
    id,
    type.id AS id_type,
    -- text fields
    name,
    type.name AS type_name,
    -- timestamps
    NOW() AS ts_load,
    -- partitions
    year,
    month,
    day
FROM
    datalake_greenhouse_raw.rejection_reasons