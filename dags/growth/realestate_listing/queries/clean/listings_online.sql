SELECT
    idaviso AS id_listing,
    idplandepublicacion AS id_publication_plan,
    idempresa AS id_company,
    idpedido AS id_order,
    iditempedido AS id_order_item,
    identregaaviso AS id_listing_delivery,
    nivelaviso AS listing_level,
    fechapublicacion AS dt_published,
    fechamodificado AS ts_updated
FROM
    datalake_realestate_raw.avisosonline
