SELECT
    -- ids
    id,
    -- Non-ids (foreign keys)
    user_id AS id_user,
    -- Non-metrics (properties)
    name,
    -- Date, timestamp
    CAST(created_at AS TIMESTAMP) AS ts_created,
    CAST(updated_at AS TIMESTAMP) AS ts_updated,
    NOW() AS ts_load,
    -- Partitions
    year,
    month,
    day
FROM
    datalake_greenhouse_v3_raw.referrers

