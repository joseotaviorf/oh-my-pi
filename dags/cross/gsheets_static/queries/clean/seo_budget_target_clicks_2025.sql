SELECT
    NULLIF(pais, '') AS pais,
    NULLIF(fuente, '') AS fuente,
    NULLIF(periodo, '') AS periodo,
    NULLIF(variable, '') AS variable,
    CAST(REPLACE(NULLIF(valor, ''), ',', '') AS FLOAT) AS valor
FROM
    datalake_gsheets_raw.seo_budget_target_clicks_2025
