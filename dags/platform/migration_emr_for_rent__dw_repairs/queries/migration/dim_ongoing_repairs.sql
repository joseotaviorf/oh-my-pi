WITH criticidade AS (
  SELECT
    id_ticket,
    CASE
      WHEN NOT CAST(GET_JSON_OBJECT(custom_fields, '$["Nova criticidade"]') AS STRING) IS NULL
      THEN CAST(GET_JSON_OBJECT(custom_fields, '$["Nova criticidade"]') AS STRING)
      WHEN NOT CAST(GET_JSON_OBJECT(custom_fields, '$["Criticidade"]') AS STRING) IS NULL
      THEN CAST(GET_JSON_OBJECT(custom_fields, '$["Criticidade"]') AS STRING)
      WHEN tags RLIKE 'triagem_automatica_comum'
      AND tags RLIKE 'resolve_iq_pp_autosservico_prestadorpp'
      THEN 'comum_criticidade'
      WHEN tags RLIKE 'triagem_automatica_urgente'
      AND tags RLIKE 'resolve_iq_pp_autosservico_prestadorpp'
      THEN 'urgente_criticidade'
      WHEN tags RLIKE 'triagem_automatica_emergencial'
      AND tags RLIKE 'resolve_iq_pp_autosservico_prestadorpp'
      THEN 'emergencial_criticidade'
      WHEN NOT CAST(GET_JSON_OBJECT(custom_fields, '$["Classificação do atendimento (Tags)"]') AS STRING) IS NULL
      THEN CAST(GET_JSON_OBJECT(custom_fields, '$["Classificação do atendimento (Tags)"]') AS STRING)
    END AS criticidade
  FROM datalake_repairs.ongoing_repair_tickets
), status_fup AS (
  SELECT
    sk_repair_request,
    status_fup_iq,
    reason_help_request
  FROM (
    SELECT
      id_repair_request AS sk_repair_request,
      status AS status_fup_iq,
      help_action AS reason_help_request,
      ROW_NUMBER() OVER (PARTITION BY id ORDER BY ts_updated DESC) AS _w,
      id,
      ts_updated
    FROM datalake_repairs_clean.repair_request_tenant_negotiation_follow_up
  ) AS _t
  WHERE
    _w = 1
), repair_request AS (
  SELECT
    sk_repair_request,
    owner_approval
  FROM (
    SELECT
      id AS sk_repair_request,
      owner_approval AS owner_approval,
      ROW_NUMBER() OVER (PARTITION BY id ORDER BY ts_updated DESC) AS _w,
      id,
      ts_updated
    FROM datalake_repairs_clean.repair_request
  ) AS _t
  WHERE
    _w = 1
)
SELECT
  sk_ticket,
  repair_class,
  repair_type,
  repair_detailed,
  execution_flow,
  criticality,
  ticket_opening,
  contract_journey,
  service_provider,
  created_front_or_back,
  agent_name,
  agent_email,
  email_assigned,
  email_requester,
  agent_organization,
  status_fup_iq,
  reason_help_request,
  owner_approval,
  group_name,
  channel,
  client_type,
  tags,
  year,
  month,
  day,
  ts_updated,
  ts_load
FROM (
  SELECT
    CAST(rt.id_ticket AS BIGINT) AS sk_ticket,
    CAST(tc.custom_fields['Classificação de Reparo 1'] AS STRING) AS repair_class,
    CAST(tc.custom_fields['Classificação de Reparo 2'] AS STRING) AS repair_type,
    CAST(tc.custom_fields['Classificação de Reparo 3'] AS STRING) AS repair_detailed,
    CAST(tc.custom_fields['Fluxo de execução dos reparos'] AS STRING) AS execution_flow,
    CASE
      WHEN c.criticidade RLIKE 'emergencial'
      THEN 'Emergencial'
      WHEN c.criticidade RLIKE 'urgente'
      THEN 'Urgente'
      WHEN c.criticidade RLIKE 'comum'
      THEN 'Comum'
      WHEN c.criticidade RLIKE 'benfeitoria'
      THEN 'Benfeitoria'
      WHEN c.criticidade IS NULL
      THEN 'Sem Defeito'
      ELSE 'Outros'
    END AS criticality,
    IF(tc.tags RLIKE 'tarefa_aberta_front', 'FRONT', 'APP') AS ticket_opening,
    IF(
      DATEDIFF(TO_DATE(CAST(rt.ts_created_local AS DATE)), TO_DATE(rt.entrance_date)) <= 40,
      'ONB',
      'ONG'
    ) AS contract_journey,
    rt.service_provider,
    rt.front_or_back AS created_front_or_back,
    tc.analyst_name AS agent_name,
    tc.analyst_email AS agent_email,
    u.email AS email_assigned,
    dzr.email AS email_requester,
    CASE
      WHEN tc.analyst_organization IN ('atn', 'atento')
      THEN 'atento'
      WHEN tc.analyst_organization IN ('webhelp', 'webhelpbr', 'contractors')
      THEN 'webhelp'
      WHEN tc.analyst_organization IN ('quintoandar.com', 'quintoandar')
      THEN 'quintoandar'
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
    tc.ts_updated,
    NOW() AS ts_load,
    ROW_NUMBER() OVER (PARTITION BY tc.id_ticket ORDER BY tc.ts_updated DESC) AS _w,
    tc.id_ticket
  FROM datalake_zendesk.tickets_current AS tc
  INNER JOIN datalake_repairs.ongoing_repair_tickets AS rt
    ON tc.id_ticket = rt.id_ticket
  LEFT JOIN criticidade AS c
    ON c.id_ticket = rt.id_ticket
  LEFT JOIN status_fup AS sf
    ON sf.sk_repair_request = rt.id_request
  LEFT JOIN repair_request AS rr
    ON rr.sk_repair_request = rt.id_request
  LEFT JOIN datalake_support_users.zendesk_users AS u
    ON u.id_user_zendesk = tc.id_assignee
  LEFT JOIN datalake_support_users.zendesk_users AS dzr
    ON dzr.id_user_zendesk = tc.id_requester
  WHERE
    tc.ts_created >= CURRENT_DATE - INTERVAL '3' YEAR
) AS _t
WHERE
  _w = 1
