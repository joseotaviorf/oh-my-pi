SELECT
    NULLIF(offer, '') AS id_offer,
    NULLIF(chave, '') AS invoice_key,
    NULLIF(id_interno, '') AS id_internal,
    NULLIF(contrapartida, '') AS id_client_sap,
    NULLIF(id_imovel, '') AS id_house,
    NULLIF(conta, '') AS id_account,
    NULLIF(cc, '') AS cost_center_code,
    NULLIF(rps, '') AS rps_number,
    NULLIF(nf, '') AS invoice_number,
    NULLIF(no_transacao, '') AS transaction_number,
    NULLIF(nome_conta_contrap, '') AS client_name,
    NULLIF(descricao, '') AS description,
    NULLIF(observacoes, '') AS comments,
    NULLIF(valor, '') AS amount,
    NULLIF(saldo_acumulado, '') AS accumulated_amount,
    TO_DATE(SPLIT(NULLIF(vencimento, ''), " ")[0], 'd/M/y') AS dt_due,
    TO_DATE(SPLIT(NULLIF(data, ''), " ")[0], 'd/M/y') AS dt_created,
    ts_load
FROM
    datalake_gsheets_raw.for_sale_platform_invoice_control
