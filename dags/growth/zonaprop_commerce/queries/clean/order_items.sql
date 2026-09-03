SELECT
    iditempedido AS id_order_item,
    idpedido AS id_order,
    idproducto AS id_product,
    idzona AS id_zone,
    idpais AS id_country,
    idcuenta AS id_account,
    idposicionpedidodeventasap AS id_sap_sales_order_position,
    posicion AS item_position,
    cantidad AS quantity,
    consumidos AS consumed_quantity,
    monto AS amount,
    preciounitario AS unit_price,
    preciounitariodelista AS list_unit_price,
    noentregable AS is_non_deliverable,
    fechadevencimiento AS dt_expired
FROM
    datalake_zonaprop_raw.itemspedido
