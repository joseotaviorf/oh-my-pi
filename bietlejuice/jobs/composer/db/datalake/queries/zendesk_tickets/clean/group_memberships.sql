WITH stitch_data AS (
    SELECT
        *,
        ROW_NUMBER() OVER (PARTITION BY id, dt ORDER BY updated_at DESC) AS last_updated
    FROM
        datalake_zendesk_tickets_raw.group_memberships
    WHERE
        dt = '{year}-{month}-{day}'
)
SELECT
    id AS id_group_memberships,
    group_id AS id_group,
    user_id AS id_user,
    url AS url_group_memberships,
    default AS is_default,
    dt AS dt_extracted,
    CAST(created_at AS TIMESTAMP) AS ts_created,
    FROM_UTC_TIMESTAMP(CAST(created_at AS TIMESTAMP), 'Brazil/East') AS ts_created_local,
    CAST(updated_at AS TIMESTAMP) AS ts_updated,
    NOW() AS ts_load,
    YEAR(CAST(dt AS DATE)) AS year,
    MONTH(CAST(dt AS DATE)) AS month,
    DAY(CAST(dt AS DATE)) AS day
FROM
    stitch_data
WHERE
    last_updated = 1
