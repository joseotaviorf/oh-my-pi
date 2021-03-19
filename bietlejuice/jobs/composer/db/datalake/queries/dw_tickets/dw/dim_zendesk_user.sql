WITH last_zendesk_user AS (
    SELECT
        id_user,
        MAX(ts_updated) AS ts_last_updated
    FROM
        datalake_zendesk_tickets_clean.users
    GROUP BY 1
)
SELECT
    CAST(du.id_user AS BIGINT) AS sk_zendesk_user,
    du.url_user,
    du.name,
    du.alias,
    du.email,
    du.phone,
    du.time_zone,
    du.locale,
    du.tags,
    du.role,
    CAST(du.is_active AS BOOLEAN) AS is_active,
    CAST(du.is_shared_phone_number AS BOOLEAN) AS is_shared_phone_number,
    du.ts_last_login,
    du.ts_created,
    du.ts_created_local,
    du.ts_updated,
    NOW() AS ts_load
FROM
    datalake_zendesk_tickets_clean.users du
INNER JOIN
    last_zendesk_user lu
        ON du.id_user=lu.id_user
        AND du.ts_updated=lu.ts_last_updated
