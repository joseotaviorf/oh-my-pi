SELECT
    NULLIF(offer, '') AS id_offer,
    NULLIF(id_interno, '') AS id_internal,
    NULLIF(codigo_cliente, '') AS id_client_sap,
    NULLIF(id_imovel, '') AS id_house,
    NULLIF(numero_rps, '') AS rps_number,
    NULLIF(n_da_nfse, '') AS invoice_number,
    NULLIF(chave_da_nfenfse, '') AS invoice_key,
    NULLIF(n_do_lote, '') AS batch_number,
    NULLIF(nome, '') AS client_name,
    NULLIF(valor_nfse, '') AS amount,
    NULLIF(status, '') AS status,
    TO_DATE(SPLIT(NULLIF(data_do_documento, ''), " ")[0], 'd/M/y') AS dt_due,
    TO_DATE(SPLIT(NULLIF(data_de_criacao, ''), " ")[0], 'd/M/y') AS dt_created,
    ts_load
FROM
    datalake_gsheets_raw.for_sale_casa_mineira_invoice_control
