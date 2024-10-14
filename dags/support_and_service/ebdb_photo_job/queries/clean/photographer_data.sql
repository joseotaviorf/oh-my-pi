SELECT
    id,
    tipoContrato AS contract_type,
    preferenciaPagamento AS payment_preference,
    ativo AS is_active,
    inicioContrato AS ts_contract_started,
    criadoEm AS ts_created,
    atualizadoEm AS ts_updated
FROM
    datalake_ebdb_raw.dadosfotografo
