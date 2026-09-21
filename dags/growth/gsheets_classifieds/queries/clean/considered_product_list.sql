-- Query for cleaning considered_product_list
SELECT
    NULLIF(fuente, '') AS source,
    NULLIF(lineadeproducto, '') AS product_line,
    NULLIF(nombre, '') AS name,
    NULLIF(idproducto, '') AS id_product,
    NULLIF(idmaterialsap, '') AS id_material_sap,
    NULLIF(Renovable, '') AS is_renewable,
    ts_load
FROM
    datalake_gsheets_raw.listado_productos
