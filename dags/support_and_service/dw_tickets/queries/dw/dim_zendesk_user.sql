SELECT
    CAST(id_user_zendesk AS BIGINT) AS sk_zendesk_user,
    url_user,
    name,
    alias,
    email,
    phone,
    time_zone,
    locale,
    tags,
    role,
    organization AS cost_center,
    CAST(is_active AS BOOLEAN) AS is_active,
    CAST(is_shared_phone_number AS BOOLEAN) AS is_shared_phone_number,
    ts_last_login,
    ts_created,
    ts_created - INTERVAL 3 HOUR AS ts_created_local,
    ts_updated,
    NOW() AS ts_load
FROM
    datalake_support_users.zendesk_users
