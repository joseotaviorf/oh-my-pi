SELECT
    id,
    atualizadoEm as ts_updated,
    criadoEm as ts_created,
    dataAssinatura as ts_signature,
    contrato_id as id_contract,
    contratoPessoa_id as id_contract_person
FROM
    datalake_ebdb_raw.assinatura