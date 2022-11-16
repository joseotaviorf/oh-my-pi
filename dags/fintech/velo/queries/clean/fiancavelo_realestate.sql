SELECT
    id,
    person AS id_person,
    company AS id_company,
    status AS id_status,
    userinsert AS id_user_insert,
    userupdate AS id_user_update,
    creci,
    flexplan AS has_flexplan,
    active AS is_active,
    dateinsert AS ts_insert,
    dateupdate AS ts_update
FROM
    datalake_velo_raw.fiancavelo_realestate
