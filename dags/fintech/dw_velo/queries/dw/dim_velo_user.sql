SELECT
    id_user AS sk_user,
    name,
    email,
    user_role,
    phone,
    ts_created,
    NOW() AS ts_load
FROM
    datalake_velo.user
