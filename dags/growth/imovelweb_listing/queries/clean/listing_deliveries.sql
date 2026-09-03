SELECT
    identregaaviso AS id_listing_delivery,
    identregaavisoriginal AS id_original_listing_delivery,
    idcuenta AS id_account,
    idpedido AS id_order,
    iditempedido AS id_order_item,
    idusuarioempresa AS id_company_user,
    idaviso AS id_listing,
    fecha AS dt_delivered
FROM
    datalake_imovelweb_raw.entregasavisos
