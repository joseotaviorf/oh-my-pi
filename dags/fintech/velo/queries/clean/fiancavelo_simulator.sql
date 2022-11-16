SELECT
    id,
    person AS id_person,
    type AS id_type,
    userinsert AS id_user_insert,
    userupdate AS id_user_update,
    users,
    value,
    valueaproved AS value_approved,
    hash,
    approved AS is_approved,
    active AS is_active,
    dateinsert AS ts_insert,
    dateupdate AS ts_update
FROM
    datalake_velo_raw.fiancavelo_simulator
