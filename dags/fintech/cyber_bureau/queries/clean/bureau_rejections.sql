SELECT
    DT_CICLO_COBRANCA AS ts_billing_cycle,
    CD_CPFCNPJ_CLI AS cpf_cnpj,
    CASE
        WHEN TP_PESSOA_CLI = "F" THEN "Physical Person"
        WHEN TP_PESSOA_CLI = "J" THEN "Legal Entity"
        ELSE TP_PESSOA_CLI
    END AS person_type,
    NR_REMESSA AS remittance_number,
    CD_BUREAU AS id_bureau,
    CD_EMPRESA AS id_company,
    CD_GRUPO AS contract_group,
    CASE
        WHEN CD_GRUPO = "1" THEN "QuintoAndar"
        WHEN CD_GRUPO = "2" THEN "QuintoCred"
        ELSE CD_GRUPO
    END AS creditor,
    CD_CONTRATO AS id_contract,
    CD_CTR_BUREAU AS contract_bureau_code,
    CD_MOTIVO AS reason_code,
    LN_DETALHE AS detail_line,
    NOW() AS ts_load
FROM datalake_cyber_bureau_raw.tb_rejeicoes_bureau
