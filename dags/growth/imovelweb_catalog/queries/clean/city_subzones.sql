SELECT
    idsubzonaciudad AS id_city_subzone,
    idzonaciudad AS id_city_zone,
    idciudad AS id_city,
    idprovincia AS id_state,
    idpais AS id_country,
    nombre AS city_subzone_name
FROM
    datalake_imovelweb_raw.subzonasciudad
