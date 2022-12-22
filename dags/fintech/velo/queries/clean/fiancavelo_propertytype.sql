SELECT
    id,
    type AS id_type,
    userinsert AS id_user_insert,
    userupdate AS id_user_update,
    name,
    BOOLEAN(active) AS is_active,
    dateinsert AS ts_inserted,
    dateupdate AS ts_updated
FROM
    datalake_velo_raw.fiancavelo_propertytype
