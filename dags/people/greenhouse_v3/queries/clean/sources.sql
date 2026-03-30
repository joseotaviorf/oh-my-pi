SELECT
    -- ids
    id AS id_source,
    type.id AS id_type,
    -- text fields
    name,
    type.name AS type_name,
    -- timestamps
    CAST(created_at AS TIMESTAMP) AS ts_created,
    CAST(updated_at AS TIMESTAMP) AS ts_updated,
    NOW() AS ts_load,
    -- partitions
    year,
    month,
    day
FROM
    datalake_greenhouse_v3_raw.sources
