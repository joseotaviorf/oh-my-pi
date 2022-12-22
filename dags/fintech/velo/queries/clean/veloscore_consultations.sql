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
    dateinsert AS ts_inserted,
    dateupdate AS ts_updated
FROM
    datalake_velo_raw.veloscore_consultations
