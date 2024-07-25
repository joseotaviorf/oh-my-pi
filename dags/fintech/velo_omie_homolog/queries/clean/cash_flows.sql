SELECT
    CAST(nCodTitulo AS BIGINT) AS id_securities,
    cCodCateg AS id_category,
    cCodIntTitulo AS id_integration_securities,
    cCodProjeto AS id_project,
    cCodVendedor AS id_seller,
    cGrupo AS id_group,
    CAST(cOperacao AS BIGINT) AS id_operation,
    cCPFCNPJCliente AS client_cpf_cnpj,
    cCodigoBarras AS barcode,
    CAST(cNumBoleto AS BIGINT) AS bill_number,
    CAST(cNumCtr AS BIGINT) AS contract_number,
    CAST(cNumDocFiscal AS BIGINT) AS tax_document_number,
    CAST(cNumOS AS BIGINT) AS service_order_number,
    CAST(nCodCliente AS BIGINT) AS id_client,
    CAST(nCodComprador AS BIGINT) AS id_buyer,
    CAST(nCodBaixa AS BIGINT) AS id_write_off,
    CAST(nCodCC AS BIGINT) AS id_bank_account,
    CAST(nCodCtr AS BIGINT) AS id_contract,
    CAST(nCodMovCC AS BIGINT) AS id_moviment_bank_account,
    CAST(nCodMovCCRepet AS BIGINT) AS id_moviment_bank_account_repeat,
    CAST(nCodNF AS BIGINT) AS id_invoice,
    CAST(nCodOS AS BIGINT) AS id_service_order,
    CAST(nCodTitRepet AS BIGINT) AS id_securities_repeat,
    cNSU AS id_payment_receipt,
    cNumParcela AS id_installment,
    cNumTitulo AS securities_code,
    cChaveNFe AS eletronic_invoice_key,
    cOrigem AS origin,
    cStatus AS status,
    cTipo AS TYPE,
    cNatureza AS financial_nature,
    cUsAlt AS alteration_user,
    cUsConcilia AS conciliation_user,
    cUsInc AS creation_user,
    CAST(nDesconto AS DOUBLE) AS discount_value,
    CAST(nJuros AS DOUBLE) AS interest_value,
    CAST(nMulta AS DOUBLE) AS fine_value,
    CAST(nValAberto AS DOUBLE) AS open_value,
    CAST(nValLiquido AS DOUBLE) AS net_value,
    CAST(nValPago AS DOUBLE) AS paid_value,
    CAST(nValorMovCC AS DOUBLE) AS bank_account_movement_value,
    CAST(nValorTitulo AS DOUBLE) AS securities_value,
    CAST(nValorPIS AS DOUBLE) AS pis_value,
    CAST(nValorCOFINS AS DOUBLE) AS cofins_value,
    CAST(nValorCSLL AS DOUBLE) AS csll_value,
    CAST(nValorIR AS DOUBLE) AS income_tax_value,
    CAST(nValorISS AS DOUBLE) AS iss_value,
    CAST(nValorINSS AS DOUBLE) AS inss_value,
    observacao AS comments,
    categorias AS categories,
    CASE
        WHEN cLiquidado = 'S' THEN TRUE
        WHEN cLiquidado = 'N' THEN FALSE
        ELSE NULL
    END AS is_liquidated,
    CASE
        WHEN cRetPIS = 'S' THEN TRUE
        WHEN cRetPIS = 'N' THEN FALSE
        ELSE NULL
    END AS is_pis_retained,
    CASE
        WHEN cRetCOFINS = 'S' THEN TRUE
        WHEN cRetCOFINS = 'N' THEN FALSE
        ELSE NULL
    END AS is_cofins_retained,
    CASE
        WHEN cRetCSLL = 'S' THEN TRUE
        WHEN cRetCSLL = 'N' THEN FALSE
        ELSE NULL
    END AS is_csll_retained,
    CASE
        WHEN cRetIR = 'S' THEN TRUE
        WHEN cRetIR = 'N' THEN FALSE
        ELSE NULL
    END AS is_income_tax_retained,
    CASE
        WHEN cRetISS = 'S' THEN TRUE
        WHEN cRetISS = 'N' THEN FALSE
        ELSE NULL
    END AS is_iss_retained,
    CASE
        WHEN cRetINSS = 'S' THEN TRUE
        WHEN cRetINSS = 'N' THEN FALSE
        ELSE NULL
    END AS is_inss_retained,
    TO_DATE(dDtCredito, 'dd/MM/yyyy') AS dt_credit,
    TO_DATE(dDtEmissao, 'dd/MM/yyyy') AS dt_issue,
    TO_DATE(dDtPagamento, 'dd/MM/yyyy') AS dt_payment,
    TO_DATE(dDtPrevisao, 'dd/MM/yyyy') AS dt_predicted,
    TO_DATE(dDtRegistro, 'dd/MM/yyyy') AS dt_register,
    TO_DATE(dDtVenc, 'dd/MM/yyyy') AS dt_due,
    to_timestamp(concat_ws(' ', dDtAlt, cHrAlt),'dd/MM/yyyy HH:mm:ss') AS ts_modified,
    to_timestamp(concat_ws(' ', dDtConcilia, cHrConcilia),'dd/MM/yyyy HH:mm:ss') AS ts_reconciliation,
    to_timestamp(concat_ws(' ', dDtInc, cHrInc),'dd/MM/yyyy HH:mm:ss') AS ts_created,
    year,
    month,
    day
FROM
    datalake_velo_omie_homolog_raw.cash_flows
WHERE
    nCodTitulo IS NOT NULL
    AND year = {year}
    AND month = {month}
    AND day = {day}
