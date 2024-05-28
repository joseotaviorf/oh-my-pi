SELECT
    BIGINT(id_cbetapa_int) AS id_collection_step,
    BIGINT(id_geusuario_int) AS id_user,
    INT(id_gecliente_int) AS id_customer,
    codigo_str AS code,
    descricao_str AS description,
    context,
    TO_TIMESTAMP(tstamp, 'dd/MM/yyyy HH:mm:ss') AS ts_timestamp,
    NOW() AS ts_load
FROM datalake_paschoalotto_raw.cbetapa
QUALIFY ROW_NUMBER() OVER(PARTITION BY id_cbetapa_int ORDER BY DATE(CONCAT(year, "-", month, "-", day)) DESC, ts_load DESC) = 1
