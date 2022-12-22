SELECT
    id,
    userinsert AS id_user_insert,
    userupdate AS id_user_update,
    neighborhood,
    street,
    number,
    complement,
    zipcode,
    city,
    state,
    country,
    geolocation,
    BOOLEAN(active) AS is_active,
    dateinsert AS ts_inserted,
    dateupdate AS ts_updated
FROM
    datalake_velo_raw.clientes_address
