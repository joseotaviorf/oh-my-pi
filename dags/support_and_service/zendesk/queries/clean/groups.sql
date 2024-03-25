SELECT DISTINCT
    id AS id_group,
    url,
    name,
    deleted AS is_deleted,
    CAST(dt AS DATE) AS dt_extracted,
    CAST(created_at AS TIMESTAMP) AS ts_created,
    CAST(updated_at AS TIMESTAMP) AS ts_updated,
    NOW() AS ts_load,
    YEAR(dt) AS year,
    MONTH(dt) AS month,
    DAY(dt) AS day
FROM
    datalake_zendesk_raw.groups
WHERE
    dt IN ('{year}-{month}-{day}', CAST((CAST('{year}-{month}-{day}' AS DATE) + INTERVAL 1 DAY) AS STRING))
