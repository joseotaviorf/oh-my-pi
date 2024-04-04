SELECT DISTINCT
    id AS id_group,
    url,
    name,
    deleted AS is_deleted,
    CAST(dt AS DATE) AS dt_extracted,
    CAST(created_at AS TIMESTAMP) AS ts_created,
    CAST(updated_at AS TIMESTAMP) AS ts_updated,
    NOW() AS ts_load,
    YEAR(CAST(dt AS DATE)) AS year,
    MONTH(CAST(dt AS DATE)) AS month,
    DAY(CAST(dt AS DATE)) AS day
FROM
    datalake_zendesk_raw.groups
WHERE
    dt IN (MAKE_DATE({year}, {month}, {day}), MAKE_DATE({year}, {month}, {day}) + INTERVAL 1 DAY)
QUALIFY
    ROW_NUMBER() OVER(PARTITION BY id_group, ts_updated ORDER BY dt_extracted DESC) = 1
