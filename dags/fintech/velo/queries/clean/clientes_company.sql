SELECT
    id,
    userinsert AS id_user_insert,
    userupdate AS id_user_update,
    document,
    name,
    comercialname AS comercial_name,
    foundation,
    rental,
    complement,
    address,
    phone,
    BOOLEAN(active) AS is_active,
    dateinsert AS ts_inserted,
    dateupdate AS ts_updated
FROM
    datalake_velo_raw.clientes_company
