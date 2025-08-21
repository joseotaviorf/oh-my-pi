SELECT
    id_house,
    DATE(data_de_distribuicao) AS dt_distribution,
    DATE(data_exp) AS dt_expiration,
    NOW() AS ts_load
FROM
    datalake_gsheets_raw.asp_rent_fl_and_ciq_opportunity_distribution
