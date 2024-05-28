SELECT
    BIGINT(id_cbpagamento_int) AS id_agreement_payment,
    BIGINT(id_cbitembordero_int) AS id_agreement_detail,
    BIGINT(id_cbcontrato_int) AS id_contract,
    BIGINT(id_geusuario_int) AS id_user,
    BIGINT(id_geempresa_int) AS id_geempresa,
    BIGINT(sequencia_int) AS bank_slip_sequence,
    IF(id_gecliente_int = "465", "QuintoAndar", NULLIF(id_gecliente_int,"")) AS creditor,
    IF(id_geempresa_int = "1", "Paschoalotto Serviços Financeiros", NULLIF(id_geempresa_int, "")) AS company,
    CASE
        WHEN id_gefilial_int = "1" THEN "Bauru"
        WHEN id_gefilial_int = "21" THEN "Ribeirão Preto"
        ELSE NULLIF(id_gefilial_int,"")
    END AS branch,
    serie_recibo_str AS receipt_series,
    observacao_txt AS observation,
    tipo_recibo_str AS receipt_type,
    CASE
        WHEN situacao_str = "C" THEN "CANCELADO"
        WHEN situacao_str = "E"  THEN "EMITIDO"
    END AS bill_status,
    pc_magnetico_str AS magnetic,
    IF(situacao_pagto_str = "1", TRUE, FALSE) AS is_paid,
    tipo_pagamento_str AS type_payment,
    CASE
        WHEN id_cbtipopagamento_int = "1" THEN "Campanha API"
        WHEN id_cbtipopagamento_int = "3" THEN "PAGTO NOVO API VELO/QA 02/2023"
        WHEN id_cbtipopagamento_int = "4" THEN "teste"
        WHEN id_cbtipopagamento_int IN ("5", "6") THEN "Pagamento cartões"
        ELSE NULLIF(id_cbtipopagamento_int,"")
    END AS payment_type,
    IF(parcelado_str = "S", TRUE, FALSE) AS is_paid_in_installments,
    observacao_boleto_str AS bank_slip_note,
    produto_str AS product,
    IF(quitacao_str = "1", TRUE, FALSE) AS is_settlement,
    senha_str AS password,
    INT(chave_acesso_int) AS access_key,
    modalidade_num AS modality,
    parcelamento_str AS installment,
    colchao_str AS mattress,
    BIGINT(recibo_num) AS receipt,
    CAST(REPLACE(principal_num, ',', '.') AS DECIMAL(10, 2)) AS main_amount,
    CAST(REPLACE(cp_num, ',', '.') AS DECIMAL(10, 2)) AS cp,
    CAST(REPLACE(multa_num, ',', '.') AS DECIMAL(10, 2)) AS fine_amount,
    context,
    IF(notificacao_num = "1", TRUE, FALSE) AS has_notification,
    IF(despesa_banco_num = "1", TRUE, FALSE) AS has_bank_expense,
    IF(abatimento_num = "1", TRUE, FALSE) AS is_write_off,
    IF(honorarios_num = "1", TRUE, FALSE) AS has_honorarium,
    IF(comissionamento_num = "1", TRUE, FALSE) AS has_commissioning,
    CAST(REPLACE(desconto_num, ',', '.') AS DECIMAL(10, 2)) AS discount_amount,
    CAST(REPLACE(desconto_principal_num, ',', '.') AS DECIMAL(10, 2)) AS main_discount,
    CAST(REPLACE(juros_mora_num, ',', '.') AS DECIMAL(10, 2)) AS default_interest,
    CAST(REPLACE(valor_total_num, ',', '.') AS DECIMAL(10, 2)) AS total_amount,
    CAST(REPLACE(retido_num, ',', '.') AS DECIMAL(10, 2)) AS retained,
    CAST(REPLACE(acrescimo_num, ',', '.') AS DECIMAL(10, 2)) AS addition,
    CAST(REPLACE(acrescimo_np_num, ',', '.') AS DECIMAL(10, 2)) AS addition_np,
    CAST(REPLACE(percentual_desconto_num, ',', '.') AS DECIMAL(10, 2)) AS percentage_discount,
    TO_DATE(data_calculo_dat, 'dd/MM/yyyy HH:mm:ss') AS dt_calculation,
    TO_DATE(data_pagamento_dat, 'dd/MM/yyyy HH:mm:ss') AS dt_payment,
    TO_DATE(data_cadastro_dat, 'dd/MM/yyyy HH:mm:ss') AS dt_register,
    TO_DATE(data_retorno_dat, 'dd/MM/yyyy HH:mm:ss') AS dt_return,
    TO_DATE(data_retorno_banco_dat, 'dd/MM/yyyy HH:mm:ss') AS dt_bank_return,
    TO_TIMESTAMP(tstamp_mdm_inclusao, 'dd/MM/yyyy HH:mm:ss') AS ts_insert,
    TO_TIMESTAMP(tstamp_mdm_alteracao, 'dd/MM/yyyy HH:mm:ss') AS ts_update,
    TO_TIMESTAMP(tstamp, 'dd/MM/yyyy HH:mm:ss') AS ts_timestamp,
    NOW() AS ts_load
FROM datalake_paschoalotto_raw.cbpagamento
