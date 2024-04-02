SELECT DISTINCT
    id AS id_group_membership,
    group_id AS id_group,
    user_id AS id_user,
    url,
    default AS is_default,
    CAST(dt AS DATE) AS dt_extracted,
    CAST(created_at AS TIMESTAMP) AS ts_created,
    CAST(updated_at AS TIMESTAMP) AS ts_updated,
    NOW() AS ts_load,
    YEAR(CAST(dt AS DATE)) AS year,
    MONTH(CAST(dt AS DATE)) AS month,
    DAY(CAST(dt AS DATE)) AS day
FROM
    datalake_zendesk_raw.group_memberships
WHERE
    dt IN ('{year}-{month}-{day}', CAST((CAST('{year}-{month}-{day}' AS DATE) + INTERVAL 1 DAY) AS STRING))
QUALIFY
    ROW_NUMBER() OVER(PARTITION BY id_group_membership, ts_updated ORDER BY dt_extracted DESC) = 1
