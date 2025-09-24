SELECT
    CD_CONTRATO AS id_contract,
    CD_CTR_BUREAU AS id_contract_bureau,
    CASE
        WHEN CD_ACAO_BUREAU = "NEG" THEN "Negativation"
        WHEN CD_ACAO_BUREAU = "REA" THEN "Rehabilitation"
        ELSE CD_ACAO_BUREAU
    END AS id_action,
    CD_BUREAU AS id_bureau,
    CD_RET_BUREAU AS id_return,
    CD_EMPRESA AS id_company,
    CD_POLITICA AS id_policy,
    ID_REG_REMESSA AS id_register_remittance,
    CD_UNIDADE_CTR AS id_contract_unit,
    CD_CONTA_AVAL AS id_guarantor_account,
    ID_PAC AS id_pac,
    CASE
        WHEN IN_AVAL_ACIONA = "S" THEN TRUE
        WHEN IN_AVAL_ACIONA = "N" THEN FALSE
        ELSE NULL
    END AS is_guarantor,
    CASE
        WHEN IN_ENVIO_LEGADO = "S" THEN TRUE
        WHEN IN_ENVIO_LEGADO = "N" THEN FALSE
        ELSE NULL
    END AS is_legacy_sending,
    CASE
        WHEN ENVIADOQUINTO = "S" THEN TRUE
        WHEN ENVIADOQUINTO = "N" THEN FALSE
        ELSE NULL
    END AS is_sent_by_quinto,
    CD_USU_SOL AS requesting_user,
    CASE
        WHEN IN_SITUACAO_MOV = "C" THEN "Confirmed"
        WHEN IN_SITUACAO_MOV = "R" THEN "Rejected"
        WHEN IN_SITUACAO_MOV = "A" THEN "Awaiting Return"
        ELSE IN_SITUACAO_MOV
    END AS movement_status,
    IN_ORIGEM_SOL AS origin_indicator,
    DS_RET_BUREAU AS return_description,
    CD_CPFCNPJ_CLI AS cpf_cnpj,
    CASE
        WHEN TP_PESSOA_CLI = "F" THEN "Physical Person"
        WHEN TP_PESSOA_CLI = "J" THEN "Legal Entity"
        ELSE TP_PESSOA_CLI
    END AS person_type,
    CD_GRUPO AS contract_group,
    CASE
        WHEN CD_GRUPO = "1" THEN "QuintoAndar"
        WHEN CD_GRUPO = "2" THEN "QuintoCred"
        ELSE CD_GRUPO
    END AS creditor,
    NR_REMESSA AS remittance_number,
    NR_PARCELA AS installment_number,
    NU_SEQAVAL AS guarantor_sequence_number,
    VL_PARCELA AS installment_amount,
    QT_DIA_ATRASO AS delay_days,
    QT_DIA_ATR_MIN AS min_delay_days,
    QT_DIA_ATR_MAX AS max_delay_days,
    DT_VENC_PARC AS ts_installment_due_date,
    DT_SOLICITACAO AS ts_request,
    DT_RET_BUREAU AS ts_bureau_return,
    DT_MOVIMENTO AS ts_movement,
    NOW() AS ts_load
FROM datalake_cyber_raw.tb_historico_bureau
