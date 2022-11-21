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
    dateinsert AS ts_insert,
    dateupdate AS ts_update
FROM
    datalake_velo_raw.clientes_person
