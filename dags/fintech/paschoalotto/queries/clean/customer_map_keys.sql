SELECT
    BIGINT(id_geqlcontrato_int) AS id_customer_map_keys,
    BIGINT(id_geqlcliente_int) AS id_customer,
    BIGINT(id_cbtiponegocio_int) AS id_product,
    BIGINT(id_cbcontrato_int) AS id_contract,
    contrato_str AS contract,
    context,
    TO_TIMESTAMP(tstamp, 'dd/MM/yyyy HH:mm:ss') AS ts_timestamp,
    NOW() AS ts_load
FROM datalake_paschoalotto_raw.geqlcontrato
QUALIFY ROW_NUMBER() OVER(PARTITION BY id_geqlcontrato_int ORDER BY DATE(CONCAT(year, "-", month, "-", day)) DESC, ts_load DESC) = 1
