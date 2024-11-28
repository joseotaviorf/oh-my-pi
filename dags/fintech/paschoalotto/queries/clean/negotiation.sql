SELECT
    BIGINT(id_cbbordero_int) AS id_negotiation,
    BIGINT(id_cbtiponegocio_int) AS id_product,
    BIGINT(id_geusuario_int) AS id_user,
    BIGINT(id_geempresa_int) AS id_geempresa,
    BIGINT(id_geusuario_execut_int) AS id_geusuario_execut,
    BIGINT(bordero_int) AS bordereau,
    IF(id_gecliente_int = "465", "QuintoAndar", NULLIF(id_gecliente_int,"")) AS creditor,
    CASE
        WHEN id_gefilial_int = "1" THEN "Bauru"
        WHEN id_gefilial_int = "21" THEN "Ribeirão Preto"
        ELSE NULLIF(id_gefilial_int,"")
    END AS branch,
    CASE
        WHEN id_fibanco_int = "66" THEN "Banco Bradesco S.A"
        WHEN id_fibanco_int = "88" THEN "Banco Itaú S.A"
        ELSE NULLIF(id_fibanco_int,"")
    END AS bank,
    IF(id_ficcbanco_int = "1", "CONTA 00050520-6 AGENCIA 1370-0", NULLIF(id_ficcbanco_int,"")) AS bank_detail,
    CASE
        WHEN id_cbtipopagamento_int = "1" THEN "Campanha API"
        WHEN id_cbtipopagamento_int = "3" THEN "PAGTO NOVO API VELO/QA 02/2023"
        WHEN id_cbtipopagamento_int = "4" THEN "teste"
        WHEN id_cbtipopagamento_int IN ("5", "6") THEN "Pagamento cartões"
        ELSE NULLIF(id_cbtipopagamento_int,"")
    END AS payment_type,
    CASE
        WHEN id_cbconvenio_int = "1" THEN "ESPELHO"
        WHEN id_cbconvenio_int = "2" THEN "PIX"
        WHEN id_cbconvenio_int = "3" THEN "CARTAO"
        ELSE NULLIF(id_cbconvenio_int,"")
    END AS convenio,
    BIGINT(itens_int) AS items,
    INT(situacao_int) AS status,
    arquivo_str AS file,
    INT(carteira_int) AS portfolio,
    CASE
        WHEN gerado_str = "0" THEN "NÃO FOI GERADO O BOLETO"
        WHEN gerado_str = "1" THEN "BOLETO FOI GERADO"
        WHEN gerado_str = "3" THEN "CANCELADO"
        ELSE NULLIF(gerado_str,"")
    END AS bill_creation,
    IF(followup_str = 0, FALSE, TRUE) AS is_followup,
    INT(modelo_carta_int) AS letter_template,
    INT(tipo_nosso_numero_int) AS our_number_type,
    repete_contrato_str AS repeat_contract,
    IF(quitacao_str = "S", TRUE, FALSE) AS is_settlement,
    CASE
        WHEN tipo_bordero_str = "C" THEN "CARTA DE COBRANÇA"
        WHEN tipo_bordero_str = "N" THEN "NOTIFICAÇÃO"
        ELSE NULLIF(tipo_bordero_str,"")
    END AS bordereau_type,
    IF(origem_str = "W", "Whatsapp", NULLIF(origem_str,"")) AS origin,
    forma_pagamento_api_recupera_str AS payment_type_recupera,
    link_cartao_api_recupera_str AS card_link,
    BIGINT(seq_calculo) AS calculation,
    COALESCE(BIGINT(numero_acordo_ws_int), BIGINT(numero_acordo_ws_str)) AS agreement_number_ws,
    CAST(REPLACE(total_num, ',', '.') AS DECIMAL(10, 2)) AS total_amount,
    context,
    TO_DATE(data_dat, 'dd/MM/yyyy HH:mm:ss') AS dt_bordereau,
    TO_TIMESTAMP(tstamp, 'dd/MM/yyyy HH:mm:ss') AS ts_tstamp,
    TO_TIMESTAMP(timestamp, 'dd/MM/yyyy HH:mm:ss') AS ts_timestamp,
    NOW() AS ts_load,
    year,
    month,
    day
FROM datalake_paschoalotto_raw.cbbordero
WHERE
    MAKE_DATE(year,month,day) BETWEEN DATE('{load_start_date}') AND DATE('{load_end_date}')
