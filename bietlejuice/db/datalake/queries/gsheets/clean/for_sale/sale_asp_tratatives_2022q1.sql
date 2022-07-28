SELECT
    INT(NULLIF(id_house,'')) AS id_house,
    ASP_responsavel AS asp_responsavel,
    grupo_sf
FROM
    datalake_gsheets_raw.sale_asp_tratatives_2022q1
