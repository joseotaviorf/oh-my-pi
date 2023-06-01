SELECT
    id_user AS sk_user,
    uuid_user,
    name,
    email,
    user_role,
    phone,
    ts_created,
    is_legacy,
    NOW() AS ts_load
FROM
    datalake_velo.user
