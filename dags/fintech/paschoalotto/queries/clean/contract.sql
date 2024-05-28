SELECT
    BIGINT(id_cbcontrato_int) AS id_contract,
    BIGINT(id_cbtiponegocio_int) AS id_product,
    BIGINT(id_geusuario_int) AS id_user,
    BIGINT(id_cbsituacaocontrato_int) AS id_customer_history,
    BIGINT(id_cbetapa_int) AS id_collection_step,
    contrato_str AS contract,
    nome_str AS name,
    cpf_str AS cpf,
    endereco_str AS address,
    complemento_str AS additional_address,
    bairro_str AS neighborhood,
    cep_str AS zip_code,
    cidade_str AS city,
    estado_str AS state,
    telefone_str AS telephone,
    estado_civil_str AS marital_status,
    observacao_str AS observation,
    email_str AS email,
    context,
    cliente_localizado_bit AS is_customer_located,
    TO_DATE(data_stand_by_dat, 'dd/MM/yyyy HH:mm:ss') AS dt_stand_by,
    TO_DATE(data_contato_dat, 'dd/MM/yyyy HH:mm:ss') AS dt_contact,
    TO_DATE(data_primeira_distrib_dat, 'dd/MM/yyyy HH:mm:ss') AS dt_first_distribution,
    TO_DATE(data_ultima_distrib_dat, 'dd/MM/yyyy HH:mm:ss') AS dt_last_distribution,
    TO_DATE(data_solicitacao_dat, 'dd/MM/yyyy HH:mm:ss') AS dt_request,
    TO_DATE(data_localizado_dat, 'dd/MM/yyyy HH:mm:ss') AS dt_located,
    TO_TIMESTAMP(tstamp, 'dd/MM/yyyy HH:mm:ss') AS ts_timestamp,
    NOW() AS ts_load,
    year,
    month,
    day
FROM datalake_paschoalotto_raw.cbcontrato
WHERE
    year = {year}
    AND month = {month}
    AND day = {day}
