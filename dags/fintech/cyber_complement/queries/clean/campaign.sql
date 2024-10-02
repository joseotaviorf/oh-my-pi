SELECT
    CAID AS id_campaign,
    CASSNUM AS id_client,
    CAAHID AS id_agreement,
    CASE
        WHEN CASTATUSCA = 1 THEN 'Vigente'
        WHEN CASTATUSCA = 2 THEN 'Vencida'
        WHEN CASTATUSCA = 3 THEN 'Aceita'
        ELSE CASTATUSCA
    END AS campaign_status,
    CANUMOFERTA AS offer_number,
    CAGRUPO AS billing_group,
    CACPFCGC AS cpf_cnpj,
    CATYPE AS agreement_type,
    CARATE AS annual_interest_rate,
    CAPYTYPE AS interest_quota_type,
    CAORIGEM AS origin,
    CAACCTCOB AS billing_account,
    CAQUE AS campaign_queue,
    CANOSSONUM AS our_number,
    CAAGENCY AS agency,
    CAFREQ AS frequency,
    IF(CATIPOBOL = 'E', TRUE, FALSE) AS is_boletagem,
    CAGRDAYS AS grace_period_days,
    CAAGING AS contract_delay_days,
    CARATE2 AS grace_period_interest_rate,
    CAQTDOFER AS total_ofers,
    CATOTPARC AS total_invoices,
    CAQTDPA AS total_installments,
    CAPERENTR AS down_payment_percentage,
    CAVLRENTR AS down_payment_amount,
    CATOTPMT AS total_negotiated_with_fees,
    CATOTPMTSH AS total_negotiated_without_fees,
    CAHONO AS fees_amount,
    CADTPROC AS ts_boletagem_sent,
    CADTVAL AS ts_due_boletagem,
    CADTVCENTR AS ts_due_down_payment,
    NOW() AS ts_load
FROM datalake_cyber_raw.tb_campanha
