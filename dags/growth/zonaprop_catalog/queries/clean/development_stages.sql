SELECT
    idetapadedesarrollo AS id_development_stage,
    idpais AS id_country,
    nombre AS development_stage_name,
    orden AS display_order
FROM
    datalake_zonaprop_raw.etapasdedesarrollo
