SELECT
    id,
    externalref AS id_external,
    userinsert AS id_user_insert,
    userupdate AS id_user_update,
    name,
    email,
    phone,
    profile,
    BOOLEAN(first) AS is_first,
    BOOLEAN(active) AS is_active,
    dateinsert AS ts_inserted,
    dateupdate AS ts_updated
FROM
    datalake_velo_raw.users_users
