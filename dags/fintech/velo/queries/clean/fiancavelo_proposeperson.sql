SELECT
    id,
    propose AS id_propose,
    person AS id_person,
    type AS id_type,
    BOOLEAN(active) AS is_active,
    userinsert AS id_user_insert,
    userupdate AS id_user_update,
    dateinsert AS ts_insert,
    dateupdate AS ts_update
FROM
    datalake_velo_raw.fiancavelo_proposeperson
