SELECT
    idlineadeproducto AS id_product_line,
    idtraduccion AS id_translation,
    nombre AS product_line_name,
    habilitada AS is_enabled
FROM
    datalake_realestate_raw.lineasdeproducto
