SELECT
    id,
    type AS id_type,
    userinsert AS id_user_insert,
    userupdate AS id_user_update,
    name,
    active AS is_active,
    dateinsert AS ts_insert,
    dateupdate AS ts_update
FROM
    datalake_velo_raw.fiancavelo_propertytype
