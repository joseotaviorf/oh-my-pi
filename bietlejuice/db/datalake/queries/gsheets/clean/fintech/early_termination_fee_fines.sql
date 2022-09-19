SELECT
    solicitante AS requester_email,
    time AS requester_team,
    CAST(solicitacao AS BIGINT) AS id_request,
    ticket,
    CAST(contrato AS BIGINT) AS id_contract,
    CAST(imovel AS BIGINT) AS id_house,
    NULLIF(id_do_bandaid, '') AS id_bandaid,
    tipo_de_multa AS fee_fine_type,
    CAST(NULLIF(valor_total,'') AS DOUBLE) AS total_value,
    CAST(NULLIF(valor_final_negociado,'') AS DOUBLE) AS final_negotiated_value,
    CAST(parcelas_cobranca AS INT) AS quantity_installments_collection,
    CAST(parcelas_repasses AS INT) AS quantity_installments_pass_through,
    CAST(NULLIF(tx_de_corretagem_corretor,'') AS DOUBLE) AS agent_brokerage_fee,
    CAST(NULLIF(tx_de_corretagem_5a,'') AS DOUBLE) AS quintoandar_brokerage_fee,
    NULLIF(dados_iq_cpfcnpj, '') AS tenant_document_number,
    NULLIF(dados_iq_banco, '') AS tenant_bank_name,
    NULLIF(dados_iq_agencia, '') AS tenant_bank_branch,
    NULLIF(dados_iq_tipo_de_conta, '') AS tenant_bank_account_type,
    CAST(taxa_adm AS BIGINT) AS admininistration_rate,
    NULLIF(motivo_manual, '') AS reason_manual_task,
    NULLIF(fatura_zerada, '') AS installment_zeroing_status,
    NULLIF(fatura_paga, '') AS installment_payment_status,
    NULLIF(fatura_pp_fechada, '') AS installment_owner_status,
    NULLIF(boleto, '') AS bill_code,
    NULLIF(alteracao_admin, '') AS admin_updated_status,
    CAST(`row` AS BIGINT) AS sheet_row_number,
    CASE
        WHEN getnet = 'Sim' THEN TRUE
        WHEN getnet = 'Não' THEN FALSE
        ELSE NULL
    END AS is_getnet_transaction,
    CASE
        WHEN isencao_de_juros = 'Sim' THEN TRUE
        WHEN isencao_de_juros = 'Não' THEN FALSE
        ELSE NULL
    END AS has_interest_exemption,
    CASE
        WHEN bandaid_aberto = 'Sim' THEN TRUE
        WHEN bandaid_aberto = 'Não' THEN FALSE
        ELSE NULL
    END AS has_related_bandaid,
    BOOLEAN(adm_isenta) AS is_adm_exempt,
    BOOLEAN(isirentororent) AS is_irent_orent,
    BOOLEAN(tarefa_manual) AS is_manual_task,
    TO_TIMESTAMP(NULLIF(execucao, ''), 'y-M-d H:m:s') AS ts_execution,
    CAST(tempo_gasto AS BIGINT) AS spent_time,
    TO_TIMESTAMP(NULLIF(data_de_solicitacao, ''), 'y-M-d H:m:s') AS ts_request,
    TO_DATE(vigencia) AS dt_start,
    TO_DATE(rescisao) AS dt_termination,
    TO_DATE(dataprimeirorepasse) AS dt_first_pass_through,
    TO_DATE(dataprimeiracobranca) AS dt_first_collection,
    ts_load
FROM
    datalake_gsheets_raw.early_termination_fee_fines
