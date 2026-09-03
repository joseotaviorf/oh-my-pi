SELECT
    idavisostiposdeoperaciones AS id_listing_operation_type,
    idaviso AS id_listing,
    idtipodeoperacion AS id_operation_type,
    idmoneda AS id_currency,
    precio AS price_amount,
    precioextra AS extra_price_amount
FROM
    datalake_imovelweb_raw.avisostiposdeoperaciones
