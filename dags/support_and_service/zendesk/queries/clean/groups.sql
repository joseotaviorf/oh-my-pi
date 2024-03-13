SELECT DISTINCT
    id AS id_group,
    url,
    name,
    deleted AS is_deleted,
    CAST(dt AS DATE) AS dt_extracted,
    created_at AS ts_created,
    updated_at AS ts_updated,
    NOW() AS ts_load,
    YEAR(dt) AS year,
    MONTH(dt) AS month,
    DAY(dt) AS day
FROM
    datalake_zendesk_raw.groups
WHERE
    dt IN (CAST('{year}-{month}-{day}' AS DATE), CAST('{year}-{month}-{day}' AS DATE) + INTERVAL 1 DAY)
