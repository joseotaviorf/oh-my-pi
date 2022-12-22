SELECT
    id,
    packtype AS id_pack_type,
    propose AS id_propose,
    userinsert AS id_user_insert,
    userupdate AS id_user_update,
    description,
    value,
    BOOLEAN(active) AS is_active,
    dateinsert AS ts_inserted,
    dateupdate AS ts_updated
FROM
    datalake_velo_raw.fiancavelo_packvalues
