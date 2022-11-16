SELECT
    id,
    propose AS id_propose,
    objecttype AS id_object_type,
    property AS id_property,
    description,
    userinsert AS id_user_insert,
    userupdate AS id_user_update,
    active AS is_active,
    dateinsert AS ts_insert,
    dateupdate AS ts_update
FROM
    datalake_velo_raw.fiancavelo_object
