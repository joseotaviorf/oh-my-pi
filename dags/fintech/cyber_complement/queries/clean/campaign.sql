SELECT
    CAID AS id_campaign,
    CASSNUM AS id_client,
    CAAHID AS id_agreement,
    CAACCTCOB AS id_contract,
    CAAGENCY AS id_agency,
    source,
    CAGRUPO AS contract_group,
    CASE
        WHEN CAGRUPO = "1" THEN "QuintoAndar"
        WHEN CAGRUPO = "2" THEN "QuintoCred"
        ELSE CAGRUPO
    END AS creditor,
    CANUMOFERTA AS id_offer,
    CASE
        WHEN CASTATUSCA = 1 THEN "Vigente"
        WHEN CASTATUSCA = 2 THEN "Vencida"
        WHEN CASTATUSCA = 3 THEN "Aceita"
        ELSE CASTATUSCA
    END AS campaign_status,
    CACPFCGC AS cpf_cnpj,
    CATYPE AS agreement_type,
    CASE
        WHEN UPPER(CAPYTYPE) = "NO_INT" THEN "Sem Juros"
        WHEN UPPER(CAPYTYPE) = "EQUAL" THEN "Cota Constante (PRICE)"
        WHEN UPPER(CAPYTYPE) = "INCR" THEN "Cota Crescente (SAC)"
        WHEN UPPER(CAPYTYPE) = "DECR" THEN "Cota Decrescente"
        ELSE CAPYTYPE
    END AS type_interest_quota,
    CASE
      WHEN CAORIGEM = "I" THEN "Interna"
      WHEN CAORIGEM = "E" THEN "Externa"
    END AS origin,
    CAQUE AS agreement_queue,
    CANOSSONUM AS down_payment_our_number,
    CAFREQ AS frequency,
    IF(CATIPOBOL = "E", TRUE, FALSE) AS is_boletagem,
    CAAGING AS contract_delay_days,
    CAGRDAYS AS grace_period_days,
    CARATE2 AS grace_period_interest_rate,
    CARATE AS installment_interest_rate,
    CAQTDOFER AS total_ofers,
    CATOTPARC AS total_invoices,
    CAQTDPA AS total_installments,
    CAPERENTR AS down_payment_percentage,
    CAVLRENTR AS down_payment_amount,
    CATOTPMT AS total_negotiated_with_honorarium,
    CATOTPMTSH AS total_negotiated_without_honorarium,
    CAHONO AS honorarium_amount,
    CADTPROC AS ts_boletagem_sent,
    CADTVAL AS ts_due_boletagem,
    CADTVCENTR AS ts_due_down_payment,
    CADTUPDATE AS ts_record_updated,
    NOW() AS ts_load
FROM datalake_cyber_raw.tb_campanha
