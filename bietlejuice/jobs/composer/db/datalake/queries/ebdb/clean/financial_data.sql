SELECT
    id,
    partner_id,
    bankdata_banco_id AS id_bank,
    bankdata_agencia AS bank_agency,
    bankdata_contacorrente AS bank_account,
    bankdata_tipoconta AS bank_account_type,
    bankdata_cpfOuCnpj AS bank_cpf_cnpj,
    bankdata_nome AS bank_account_holder_name,
    bankdata_outroTitular AS bank_account_secondary_holder,
    criadoem AS ts_created,
    atualizadoem AS ts_updated
FROM
    datalake_ebdb_raw.financialdata
