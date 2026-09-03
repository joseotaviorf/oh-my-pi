SELECT
    idproducto AS id_product,
    idlineadeproducto AS id_product_line,
    idmaterialsap AS id_sap_material,
    idzona AS id_zone,
    idsublineadeproducto AS id_product_subline,
    nombre AS product_name,
    cantidadinicial AS initial_quantity,
    limiteentregaensimultaneo AS concurrent_delivery_limit,
    limiteentregapordia AS daily_delivery_limit,
    limiteentregapormes AS monthly_delivery_limit,
    diasvigencia AS validity_days,
    entregailimitada AS is_unlimited_delivery,
    habilitado AS is_enabled,
    esclonable AS is_cloneable
FROM
    datalake_imovelweb_raw.productos
