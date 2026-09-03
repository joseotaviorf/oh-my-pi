SELECT
    idtelefonoaviso AS id_listing_phone,
    idaviso AS id_listing,
    prefijo AS phone_prefix,
    numero AS phone_number,
    tipodetelefono AS phone_type
FROM
    datalake_imovelweb_raw.telefonosaviso
