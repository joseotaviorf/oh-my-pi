SELECT
    CAST(id_house AS BIGINT) AS id_house,
    facade_recovery_channel,
    has_common_area_treated = 'TRUE' AS has_common_area_treated,
    has_facade_treated = 'TRUE' AS has_facade_treated,
    CAST(dt_analyzed AS DATE) AS dt_analyzed
FROM
    datalake_gsheets_raw.recuperacao_fachada_e_area_comum
