SELECT
    id,
    userinsert AS id_user_insert,
    userupdate AS id_user_update,
    name,
    document,
    email,
    mother,
    phone,
    rental,
    BOOLEAN(estrangeiro) AS is_foreigner,
    BOOLEAN(active) AS is_active,
    birth AS dt_birth,
    dateinsert AS ts_inserted,
    dateupdate AS ts_updated
FROM
    datalake_velo_raw.clientes_person
