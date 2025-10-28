SELECT
    DT_CICLO_COBRANCA AS ts_billing_cycle,
    CD_CPFCNPJ_CLI AS cpf_cnpj,
    DT_SOLICITACAO AS ts_request,
    CD_GRUPO AS contract_group,
    CASE
        WHEN CD_GRUPO = "1" THEN "QuintoAndar"
        WHEN CD_GRUPO = "2" THEN "QuintoCred"
        ELSE CD_GRUPO
    END AS creditor,
    CD_CONTRATO AS id_contract,
    CD_POLITICA AS id_policy,
    DS_ACAO_BUREAU AS bureau_action_description,
    CD_BUREAU AS id_bureau,
    CD_EMPRESA AS id_company,
    NR_PARCELA AS installment_number,
    VL_PARCELA AS installment_amount,
    DT_PROCESSAMENTO AS ts_processing,
    TP_MOTIVO AS reason_type,
    CD_MOTIVO AS reason_code,
    DS_MOTIVO AS reason_description,
    IN_ORIGEM_CRIT AS origin_indicator,
    NR_REMESSA AS remittance_number,
    CD_CTR_BUREAU AS contract_bureau_code,
    NOW() AS ts_load
FROM datalake_cyber_bureau_raw.tb_criticados_mnr
