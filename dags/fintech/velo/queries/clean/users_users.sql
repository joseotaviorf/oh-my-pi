SELECT
    id,
    externalref AS id_external,
    userinsert AS id_user_insert,
    userupdate AS id_user_update,
    name,
    email,
    password,
    phone,
    profile,
    first AS is_first,
    active AS is_active,
    dateinsert AS ts_insert,
    dateupdate AS ts_update
FROM
    datalake_velo_raw.users_users
