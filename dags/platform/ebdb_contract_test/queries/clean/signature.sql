SELECT
    id,
    atualizadoEm AS ts_updated,
    criadoEm AS ts_created,
    dataAssinatura AS ts_signature,
    contrato_id AS id_contract,
    contratoPessoa_id AS id_contract_person
FROM
    datalake_ebdb_test_raw.assinatura