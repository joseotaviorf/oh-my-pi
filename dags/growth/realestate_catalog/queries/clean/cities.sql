SELECT
    idciudad AS id_city,
    idprovincia AS id_state,
    idpais AS id_country,
    idoriginal AS id_original,
    idregion AS id_region,
    nombre AS city_name,
    aliases AS city_aliases,
    preposicion AS city_preposition,
    escapital AS is_capital
FROM
    datalake_realestate_raw.ciudades
