SELECT
    id,
    propose AS id_propose,
    typehistory AS id_type_history,
    textkey AS id_text_key,
    additionalkey AS id_additional_key,
    userinsert AS id_user_insert,
    userupdate AS id_user_update,
    BOOLEAN(active) AS is_active,
    dateinsert AS ts_insert,
    dateupdate AS ts_update
FROM
    datalake_velo_raw.fiancavelo_proposehistory
