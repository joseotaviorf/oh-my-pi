  WITH last_extracted AS (
        SELECT
            id_group,
            name,
            dt_extracted
        FROM
            datalake_velo_zendesk_clean.groups
        QUALIFY
            ROW_NUMBER() OVER(PARTITION BY id_group ORDER BY dt_extracted DESC) = 1
        )


SELECT
    t.id_ticket,
    SUBSTRING(REGEXP_EXTRACT(t.description, 'Este é um acompanhamento da sua solicitação anterior #([0-9]+)',0),55,6) as id_main_ticket,
    cf.request_error,
    cf.request_type,
    cf.cancellation_reason,
    cf.broker_name,
    cf.contact_reason,
    cf.tenant_name,
    cf.client_request,
    le.name,
    t.id_group,
    t.priority,
    t.recipient,
    t.ticket_via,
    t.type AS ticket_type,
    CASE
        WHEN t.custom_fields LIKE '%"inadimplência_2_dias_sem_juros_e_multa"%' THEN '2 days'
        WHEN cf.request_type LIKE '%"receber_em_2_dias"%' THEN '2 days'
        WHEN cf.request_type LIKE '%"inadimplência_15_dias_com_juros_e_multa"%' THEN '15 days'
        WHEN cf.request_type LIKE '%"receber_em_15_dias"%' THEN '15 days'
        WHEN cf.request_type LIKE '%"cancelamento_de_contrato_com_acionamento_de_garantia"%' THEN 'Cancellation'
        WHEN cf.guarantee_activation LIKE '%"com_acionamento"%' THEN 'Cancellation'
        ELSE NULL
    END AS short_request_type,
    t.description,
    t.url_ticket AS ticket_url,
    t.tags,
    t.status AS ticket_status,
    t.subject,
    t.has_incidents,
    t.is_public,
    t.ts_created,
    t.ts_created_local,
    t.ts_updated,
    t.ts_load

FROM
    datalake_velo_zendesk_clean.tickets t

LEFT JOIN
    custom_fields cf
    ON t.id_ticket = cf.id_ticket

LEFT JOIN
    last_extracted le
    ON le.id_group = t.id_group
