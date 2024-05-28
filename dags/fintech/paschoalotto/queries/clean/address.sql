SELECT
    BIGINT(id_geqlendereco_int) AS id_address,
    BIGINT(id_geqlcliente_int) AS id_customer,
    endereco_str AS address,
    complemento_str AS additional_address,
    bairro_str AS neighborhood,
    cep_str AS zip_code,
    cidade_str AS city,
    estado_str AS state,
    classificacao_str AS classification,
    context,
    BOOLEAN(excluido_bit) AS is_deleted,
    TO_TIMESTAMP(tstamp_inclusao, 'dd/MM/yyyy HH:mm:ss') AS ts_inclusion,
    TO_TIMESTAMP(tstamp_mdm_inclusao, 'dd/MM/yyyy HH:mm:ss') AS ts_insert,
    TO_TIMESTAMP(tstamp_mdm_alteracao, 'dd/MM/yyyy HH:mm:ss') AS ts_update,
    TO_TIMESTAMP(tstamp, 'dd/MM/yyyy HH:mm:ss') AS timestamp,
    NOW() AS ts_load
FROM datalake_paschoalotto_raw.geqlendereco
QUALIFY ROW_NUMBER() OVER(PARTITION BY id_geqlendereco_int ORDER BY DATE(CONCAT(year, "-", month, "-", day)) DESC, ts_load DESC) = 1
