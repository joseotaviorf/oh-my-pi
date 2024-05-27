SELECT
    u.id_user AS sk_user,
    u.id_main_user AS sk_main_user,
    u.name,
    u.email,
    u.phone_number,
    u.is_active,
    u.ts_created,
    u.ts_updated,
    NOW() AS ts_load
FROM
    datalake_hub_services.users AS u
QUALIFY
    ROW_NUMBER() OVER (PARTITION BY u.id_user ORDER BY u.ts_updated DESC) = 1