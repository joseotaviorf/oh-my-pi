SELECT
    idzonaciudad AS id_city_zone,
    idciudad AS id_city,
    idprovincia AS id_state,
    idtipodezonaciudad AS id_city_zone_type,
    idpais AS id_country,
    nombre AS city_zone_name,
    codigoPostal AS postal_code,
    aliases AS city_zone_aliases,
    latitud AS latitude,
    longitud AS longitude
FROM
    datalake_realestate_raw.zonasciudad
