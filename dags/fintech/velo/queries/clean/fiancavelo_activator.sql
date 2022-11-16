SELECT
    id,
    userinsert AS id_user_insert,
    userupdate AS id_user_update,
    name,
    value,
    icon,
    active AS is_active,
    dateinsert AS ts_insert,
    dateupdate AS ts_update
FROM
    datalake_velo_raw.fiancavelo_activator
