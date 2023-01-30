SELECT
    CAST(usr.id_user AS BIGINT) AS sk_zendesk_user,
    usr.url_user,
    usr.name,
    usr.alias,
    usr.email,
    usr.phone,
    usr.time_zone,
    usr.locale,
    usr.tags,
    usr.role,
    org.name AS cost_center,
    CAST(usr.is_active AS BOOLEAN) AS is_active,
    CAST(usr.is_shared_phone_number AS BOOLEAN) AS is_shared_phone_number,
    usr.ts_last_login,
    usr.ts_created,
    usr.ts_created_local,
    usr.ts_updated,
    NOW() AS ts_load
FROM
    datalake_zendesk_tickets_clean.users usr
LEFT JOIN
    datalake_zendesk_tickets_clean.organizations org
