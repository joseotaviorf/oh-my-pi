SELECT
    cod_tit AS id_contract,
    cod_tipc AS id_contract_type,
    cod_cred AS id_creditor,
    contrato_tit AS contract_number,
    compl_contrato_tit AS complement,
    cod_dev AS id_debtor,
    dt_bord_tit AS ts_inclusion,
    dt_expir_tit AS ts_expiration,
    NOW() AS ts_load
FROM datalake_webhelp_homolog_raw.titulos
