WITH deduped AS (
    SELECT
        id,
        visitor_id AS id_visitor,
        creator_id AS id_creator,
        version,
        value,
        created_at AS ts_created,
        updated_at AS ts_updated,
        year,
        month,
        day,
        ROW_NUMBER() OVER (PARTITION BY id ORDER BY updated_at DESC) AS rn
    FROM
        datalake_hub_services_raw.observation
)
SELECT
    id,
    id_visitor,
    id_creator,
    version,
    value,
    ts_created,
    ts_updated,
    year,
    month,
    day
FROM
    deduped
WHERE
    rn = 1
