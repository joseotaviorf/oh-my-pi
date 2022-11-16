SELECT
    id,
    userupdate AS id_user_update,
    name,
    hash,
    active,
    active AS is_active,
    dateinsert AS ts_insert,
    dateupdate AS ts_update
FROM
    datalake_velo_raw.velosign_template
