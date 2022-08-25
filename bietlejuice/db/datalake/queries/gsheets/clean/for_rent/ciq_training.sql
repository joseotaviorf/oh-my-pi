SELECT
    CAST(id_ciq AS BIGINT) AS id_ciq,
    event,
    TO_DATE(data_treinamento,'yyyyMMdd') AS dt_training
FROM
    datalake_gsheets_raw.ciq_training
