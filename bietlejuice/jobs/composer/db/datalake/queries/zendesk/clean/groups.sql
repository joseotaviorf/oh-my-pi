WITH stitch_data AS (
    SELECT
        *,
        ROW_NUMBER() OVER (PARTITION BY id, dt ORDER BY updated_at DESC) AS last_updated
    FROM
        datalake_zendesk_tickets_raw.groups
    WHERE
        dt = '{year}-{month}-{day}'
)
SELECT
    id AS id_group,
    url AS url_group,
    name,
    deleted AS is_deleted,
    dt AS dt_extracted,
    FROM_UTC_TIMESTAMP(CAST(created_at AS TIMESTAMP), 'Brazil/East') AS ts_created_local,
    CAST(created_at AS TIMESTAMP) AS ts_created,
    CAST(updated_at AS TIMESTAMP) AS ts_updated,
    NOW() AS ts_load,
    YEAR(CAST(dt AS DATE)) AS year,
    MONTH(CAST(dt AS DATE)) AS month,
    DAY(CAST(dt AS DATE)) AS day
FROM
    stitch_data
WHERE
    last_updated = 1
