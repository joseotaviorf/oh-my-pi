SELECT
    id AS id_group_membership,
    group_id AS id_group,
    user_id AS id_user,
    url,
    default AS is_default,
    dt AS dt_extracted,
    created_at AS ts_created,
    updated_at AS ts_updated,
    NOW() AS ts_load,
    YEAR(dt) AS year,
    MONTH(dt) AS month,
    DAY(dt) AS day
FROM
    datalake_zendesk_raw.group_memberships
WHERE
    dt IN (CAST('{year}-{month}-{day}' AS DATE), CAST('{year}-{month}-{day}' AS DATE) + INTERVAL 1 DAY)
