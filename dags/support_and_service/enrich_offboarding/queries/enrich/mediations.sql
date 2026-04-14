WITH mediation_tickets AS (
  -- Source 1: Terminator (termination_task TERMINATION_LANDLORD + ticket em group)
  SELECT
    ts.id_termination,
    t.id_contract,
    tc.id_ticket,
    TRUE AS is_ticket_opened_via_terminator,
    tc.ts_created,
    tc.tags
  FROM
    datalake_terminator_clean.termination_task AS ts
  JOIN
    datalake_terminator_clean.termination AS t
      ON t.id = ts.id_termination
  JOIN
    datalake_zendesk.tickets_current AS tc
      ON ts.id_external = tc.id_ticket
  WHERE
    ts.type = 'TERMINATION_LANDLORD'
    AND tc.group_name IN ('Offboarding Reparos [OFF] [POS] [BACK]', 'CX Off Manager [SPOC]')
    AND t.status != 'CANCELED'
    AND tc.tags NOT LIKE '%ezsend_one%'
    AND tc.tags NOT LIKE '%closed_by_merge%'
    AND tc.tags NOT LIKE '%ticket_acompanhamento%'

  UNION ALL

  -- Source 2: Zendesk 
  SELECT
    NULL AS id_termination,
    CAST(tc.id_contract AS BIGINT) AS id_contract,
    tc.id_ticket,
    FALSE AS is_ticket_opened_via_terminator,
    tc.ts_created,
    tc.tags
  FROM
    datalake_zendesk.tickets_current AS tc
  WHERE
    tc.tags NOT LIKE '%ezsend_one%'
    AND tc.tags NOT LIKE '%closed_by_merge%'
    AND tc.tags NOT LIKE '%ticket_acompanhamento%'
    AND tc.group_name = 'Offboarding Reparos [OFF] [POS] [BACK]'
    AND COALESCE(element_at(tc.custom_fields, 'Tipo de Cliente [PRE-SAIDA]'), element_at(tc.custom_fields, 'Tipo de Cliente')) LIKE '%proprietário%'
    AND element_at(tc.custom_fields, 'Tipo de Demanda') = 'demanda_pos_saida'
    AND tc.id_contract IS NOT NULL
),
squad_from_tags AS (
  SELECT
    id_ticket,
    id_contract,
    id_termination,
    is_ticket_opened_via_terminator,
    ts_created,
    CASE
      WHEN tags LIKE '%"pp_multi"%' THEN 'Squad 6 - PP Multi'
      WHEN tags LIKE '%high_value%' THEN 'Squad 5 - High Value'
      WHEN tags LIKE '%checkout_wkf_budg_appr_by_ll%' AND tags LIKE '%checkout_wkf_budg_appr_by_tt%' THEN 'Squad 1 - Ambos Aprovam'
      WHEN tags LIKE '%checkout_wkf_budg_appr_by_ll%' AND tags NOT LIKE '%checkout_wkf_budg_appr_by_tt%' THEN 'Squad 2 - PP Aprova'
      WHEN tags LIKE '%checkout_wkf_budg_appr_by_tt%' AND tags NOT LIKE '%checkout_wkf_budg_appr_by_ll%' THEN 'Squad 3 - IQ Aprova'
      WHEN (tags NOT LIKE '%checkout_wkf_budg_appr_by_tt%' OR tags NOT LIKE '%checkout_wkf_budg_appr_by_ll%') THEN 'Squad 4 - PP e IQ reprovam ou sem resposta'
      ELSE NULL
    END AS squad
  FROM
    mediation_tickets
),
-- Source 3: Salesforce 
mediation_with_salesforce AS (
  SELECT
   id_ticket,
   id_contract,
   id_termination,
   is_ticket_opened_via_terminator,
   ts_created,
   squad
  FROM
    squad_from_tags
  UNION ALL 
  SELECT
    c.case_number AS id_ticket,
    c.id_contract,
    c.id_external AS id_termination,
    FALSE AS is_ticket_opened_via_terminator,
    c.ts_created,
    c.omni_channel_queue AS squad
  FROM 
    datalake_salesforce_clean.cases c
  JOIN 
    datalake_salesforce_clean.record_types rt
      ON c.id_record_type = rt.id_record_type
  WHERE 
    rt.record_type_name = 'Mediação'
    AND LOWER(c.case_status) NOT IN ('cancelado', 'canceled') 
    AND c.omni_channel_queue NOT IN ('Squad 7 - Mediação')
  QUALIFY
    ROW_NUMBER() OVER(PARTITION BY c.id_contract ORDER BY c.ts_created DESC) = 1
),
mediation_per_contract AS (
  SELECT
    id_contract,
    id_termination,
    id_ticket,
    is_ticket_opened_via_terminator,
    squad,
    DATE(ts_created - INTERVAL 3 HOUR) AS dt_mediation
  FROM
    mediation_with_salesforce
  QUALIFY
    ROW_NUMBER() OVER (PARTITION BY id_contract ORDER BY ts_created DESC) = 1
),
terminations AS (
  SELECT
    t.id_termination,
    t.id_contract,
    CASE
      WHEN DATE(ib.ts_synced - INTERVAL 3 HOUR) > DATE(t.ts_termination_request) THEN DATE(ib.ts_synced - INTERVAL 3 HOUR)
      ELSE NULL
    END AS dt_inspection,
    t.ts_termination_request,
    t.ts_termination_finished,
    t.ts_termination_updated
  FROM
    datalake_terminator.termination AS t
  LEFT JOIN
    datalake_inspections.inspection_booking AS ib
      ON t.id_contract = ib.id_contract
      AND ib.inspection_type = 'offboarding'
      AND DATE(ib.ts_synced - INTERVAL 3 HOUR) > DATE(t.ts_termination_request)
  WHERE
    t.status = 'DONE'
  QUALIFY
    ROW_NUMBER() OVER (PARTITION BY t.id_termination ORDER BY DATE(ib.ts_synced - INTERVAL 3 HOUR) DESC) = 1
)
SELECT
  t.id_termination,
  t.id_contract,
  m.id_ticket AS id_mediation_ticket,
  m.squad,
  m.id_ticket IS NOT NULL AS has_mediation_ticket,
  COALESCE(m.is_ticket_opened_via_terminator, FALSE) AS is_ticket_opened_via_terminator,
  m.dt_mediation,
  t.dt_inspection,
  t.ts_termination_request,
  t.ts_termination_finished,
  t.ts_termination_updated
FROM
  terminations AS t
LEFT JOIN
  mediation_per_contract AS m
    ON t.id_contract = m.id_contract
    AND (m.id_termination IS NULL OR m.id_termination = t.id_termination)
