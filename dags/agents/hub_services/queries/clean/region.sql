WITH deduped AS (
    SELECT
        id,
        version,
        name AS region_name,
        created_at AS ts_created,
        updated_at AS ts_updated,
        year,
        month,
        day,
        ROW_NUMBER() OVER (PARTITION BY id ORDER BY updated_at DESC) AS rn
    FROM
        datalake_hub_services_raw.region
)
SELECT
    id,
    version,
    region_name,
    ts_created,
    ts_updated,
    year,
    month,
    day
FROM
    deduped
WHERE
    rn = 1
