WITH criticidade AS (
  SELECT
    rt.id_ticket,
    CASE
      WHEN
        CAST(GET_JSON_OBJECT(rt.custom_fields, '$["Nova criticidade"]') AS STRING) IS NOT NULL
        THEN CAST(GET_JSON_OBJECT(rt.custom_fields, '$["Nova criticidade"]') AS STRING)
      WHEN
        CAST(GET_JSON_OBJECT(rt.custom_fields, '$["Criticidade"]') AS STRING) IS NOT NULL
      THEN CAST(GET_JSON_OBJECT(rt.custom_fields, '$["Criticidade"]') AS STRING)
      WHEN
        regexp_like(rt.tags,'triagem_automatica_comum')
        AND regexp_like(rt.tags, 'resolve_iq_pp_autosservico_prestadorpp')
      THEN 'comum_criticidade'
      WHEN
        regexp_like(rt.tags, 'triagem_automatica_urgente')
        AND regexp_like(rt.tags, 'resolve_iq_pp_autosservico_prestadorpp')
      THEN 'urgente_criticidade'
      WHEN
        regexp_like(rt.tags, 'triagem_automatica_emergencial')
        AND regexp_like(rt.tags, 'resolve_iq_pp_autosservico_prestadorpp')
      THEN 'emergencial_criticidade'
      WHEN
        CAST(GET_JSON_OBJECT(rt.custom_fields, '$["Classificação do atendimento (Tags)"]') AS STRING) IS NOT NULL
      THEN CAST(GET_JSON_OBJECT(rt.custom_fields, '$["Classificação do atendimento (Tags)"]') AS STRING)
    END AS criticidade
  FROM datalake_repairs.ongoing_repair_tickets AS rt
)
,status_fup AS (
  SELECT
    rrtnf.id_repair_request AS sk_repair_request
    ,rrtnf.status AS status_fup_iq
    ,rrtnf.help_action AS reason_help_request
  FROM datalake_repairs_clean.repair_request_tenant_negotiation_follow_up AS rrtnf
  QUALIFY
    ROW_NUMBER() OVER (PARTITION BY rrtnf.id ORDER BY rrtnf.ts_updated DESC) = 1
)
,repair_request AS (
  SELECT
    rr.id AS sk_repair_request
    ,rr.owner_approval AS owner_approval
  FROM datalake_repairs_clean.repair_request AS rr
  QUALIFY
    ROW_NUMBER() OVER (PARTITION BY rr.id ORDER BY rr.ts_updated DESC) = 1
)

SELECT
  CAST(rt.id_ticket AS BIGINT) AS sk_ticket,
  CAST(tc.custom_fields['Classificação de Reparo 1'] AS STRING) AS repair_class,
  CAST(tc.custom_fields['Classificação de Reparo 2'] AS STRING) AS repair_type,
  CAST(tc.custom_fields['Classificação de Reparo 3'] AS STRING) AS repair_detailed,
  CAST(tc.custom_fields['Fluxo de execução dos reparos'] AS STRING) AS execution_flow,
  CASE
    WHEN regexp_like(c.criticidade, 'emergencial')
      THEN 'Emergencial'
    WHEN regexp_like(c.criticidade, 'urgente')
      THEN 'Urgente'
    WHEN regexp_like(c.criticidade, 'comum')
      THEN 'Comum'
    WHEN regexp_like(c.criticidade, 'benfeitoria')
      THEN 'Benfeitoria'
    WHEN c.criticidade IS NULL
      THEN 'Sem Defeito'
    ELSE 'Outros'
  END AS criticality,
  IF(regexp_like(tc.tags,'tarefa_aberta_front'), 'FRONT', 'APP') AS ticket_opening,
  IF(DATEDIFF(DAY, rt.entrance_date, cast(rt.ts_created_local AS DATE)) <= 40, 'ONB', 'ONG') AS contract_journey,
  rt.service_provider,
  rt.front_or_back AS created_front_or_back,
  tc.analyst_name AS agent_name,
  tc.analyst_email AS agent_email,
  u.email AS email_assigned,
  dzr.email AS email_requester,
  CASE
    WHEN tc.analyst_organization IN ('atn','atento') THEN 'atento'
    WHEN tc.analyst_organization IN ('webhelp','webhelpbr','contractors') THEN 'webhelp'
    WHEN tc.analyst_organization IN ('quintoandar.com','quintoandar') THEN 'quintoandar'
    ELSE tc.analyst_organization
  END AS agent_organization,
  sf.status_fup_iq,
  sf.reason_help_request,
  rr.owner_approval,
  tc.group_name,
  tc.channel,
  tc.client_type,
  tc.tags,
  tc.year,
  tc.month,
  tc.day,
  NOW() AS ts_load
FROM
  datalake_zendesk.tickets_current tc
LEFT JOIN
  datalake_repairs.ongoing_repair_tickets AS rt
    ON tc.id_ticket = rt.id_ticket
LEFT JOIN 
  criticidade AS c
    ON c.id_ticket = rt.id_ticket
LEFT JOIN
  status_fup AS sf
    ON sf.sk_repair_request = rt.id_request
LEFT JOIN
  repair_request AS rr
    ON rr.sk_repair_request = rt.id_request
LEFT JOIN
  datalake_support_users.zendesk_users AS u
    ON u.id_user_zendesk = tc.id_assignee
LEFT JOIN
  datalake_support_users.zendesk_users AS dzr
    ON dzr.id_user_zendesk = tc.id_requester
WHERE
  tc.ts_created >= CURRENT_DATE - INTERVAL 3 YEAR
QUALIFY
  ROW_NUMBER() OVER (PARTITION BY rt.id_ticket ORDER BY tc.ts_updated DESC) = 1