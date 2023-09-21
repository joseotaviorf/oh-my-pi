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
    dateupdate AS ts_updated,
    year,
    month,
    day
FROM
    datalake_rental_guarantee_platform_raw.clientes_person_legacy
QUALIFY
    ROW_NUMBER() OVER (PARTITION BY id ORDER BY dateupdate DESC) = 1
