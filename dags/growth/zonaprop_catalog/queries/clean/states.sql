SELECT
    idprovincia AS id_state,
    idpais AS id_country,
    idprovinciasap AS id_sap_state,
    nombre AS state_name,
    sigla AS state_abbreviation,
    preposicion AS state_preposition,
    orden AS display_order
FROM
    datalake_zonaprop_raw.provincias
