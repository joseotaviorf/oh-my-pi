SELECT
    id,
    userinsert AS id_user_insert,
    userupdate AS id_user_update,
    person AS id_person,
    bureau AS id_bureau,
    value,
    document,
    risk,
    BOOLEAN(active) AS is_active,
    dateinsert AS ts_insert,
    dateupdate AS ts_update
FROM
    datalake_velo_raw.veloscore_consultations
