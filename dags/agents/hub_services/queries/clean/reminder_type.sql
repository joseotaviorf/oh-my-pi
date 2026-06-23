WITH deduped AS (
    SELECT
        id,
        name,
        status,
        version,
        created_at AS ts_created,
        updated_at AS ts_updated,
        year,
        month,
        day,
        ROW_NUMBER() OVER (PARTITION BY id ORDER BY updated_at DESC) AS rn
    FROM
        datalake_hub_services_raw.reminder_type
)
SELECT
    id,
    name,
    status,
    version,
    ts_created,
    ts_updated,
    year,
    month,
    day
FROM
    deduped
WHERE
    rn = 1
