SELECT
    id,
    person AS id_person,
    company AS id_company,
    status AS id_status,
    userinsert AS id_user_insert,
    userupdate AS id_user_update,
    creci,
    BOOLEAN(flexplan) AS has_flexplan,
    BOOLEAN(active) AS is_active,
    dateinsert AS ts_inserted,
    dateupdate AS ts_updated
FROM
    datalake_velo_raw.fiancavelo_realestate
