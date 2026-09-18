WITH mediation_tickets AS (
  -- Zendesk source 1: Terminator (TERMINATION_LANDLORD + ticket in mediation groups)
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
  -- Zendesk source 2: legacy direct Zendesk tickets
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
    AND COALESCE(
      element_at(tc.custom_fields, 'Tipo de Cliente [PRE-SAIDA]'),
      element_at(tc.custom_fields, 'Tipo de Cliente')
    ) LIKE '%proprietário%'
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
zendesk_mediation_ranked AS (
  SELECT
    id_contract,
    id_termination,
    id_ticket,
    is_ticket_opened_via_terminator,
    squad,
    DATE(ts_created - INTERVAL 3 HOUR) AS dt_mediation,
    ROW_NUMBER() OVER (PARTITION BY id_contract ORDER BY ts_created DESC) AS rn
  FROM
    squad_from_tags
),
zendesk_mediation AS (
  SELECT
    id_contract,
    id_termination,
    id_ticket,
    is_ticket_opened_via_terminator,
    squad,
    dt_mediation
  FROM
    zendesk_mediation_ranked
  WHERE
    rn = 1
),
sf_mediation_cases_ranked AS (
  SELECT
    c.case_number AS id_ticket,
    c.id_contract,
    FALSE AS is_ticket_opened_via_terminator,
    c.omni_channel_queue AS squad,
    DATE(c.ts_created - INTERVAL 3 HOUR) AS dt_mediation,
    ROW_NUMBER() OVER (PARTITION BY c.id_contract ORDER BY c.ts_created DESC) AS rn
  FROM
    datalake_salesforce_clean.cases AS c
  JOIN
    datalake_salesforce_clean.record_types AS rt
      ON c.id_record_type = rt.id_record_type
  WHERE
    rt.record_type_name = 'Mediação'
    AND LOWER(c.case_status) NOT IN ('cancelado', 'canceled')
    AND c.omni_channel_queue NOT IN ('Squad 7 - Mediação')
),
sf_mediation_cases AS (
  SELECT
    id_ticket,
    id_contract,
    is_ticket_opened_via_terminator,
    squad,
    dt_mediation
  FROM
    sf_mediation_cases_ranked
  WHERE
    rn = 1
),
sf_spoc_mediation_tasks_ranked AS (
  SELECT
    t.id_task AS id_ticket,
    t.id_contract,
    FALSE AS is_ticket_opened_via_terminator,
    CAST(NULL AS STRING) AS squad,
    DATE(t.ts_created - INTERVAL 3 HOUR) AS dt_mediation,
    ROW_NUMBER() OVER (PARTITION BY t.id_contract ORDER BY t.ts_created ASC) AS rn
  FROM
    datalake_salesforce_clean.task AS t
  WHERE
    t.subject IN (
      'Tarefa de contato: Negociação + Pagamento PP',
      'Tarefa de contato: Negociação + Cobrança IQ'
    )
    AND t.status NOT IN ('Cancelled')
),
sf_spoc_mediation_tasks AS (
  SELECT
    id_ticket,
    id_contract,
    is_ticket_opened_via_terminator,
    squad,
    dt_mediation
  FROM
    sf_spoc_mediation_tasks_ranked
  WHERE
    rn = 1
),
terminations_ranked AS (
  SELECT
    t.id_termination,
    t.id_contract,
    CASE
      WHEN DATE(ib.ts_synced - INTERVAL 3 HOUR) > DATE(t.ts_termination_request) THEN DATE(ib.ts_synced - INTERVAL 3 HOUR)
      ELSE NULL
    END AS dt_inspection,
    t.ts_termination_request,
    t.ts_termination_finished,
    t.ts_termination_updated,
    ROW_NUMBER() OVER (
      PARTITION BY t.id_termination
      ORDER BY DATE(ib.ts_synced - INTERVAL 3 HOUR) DESC
    ) AS rn
  FROM
    transformation_terminator_test_curated.termination AS t
  LEFT JOIN
    datalake_inspections.inspection_booking AS ib
      ON t.id_contract = ib.id_contract
      AND ib.inspection_type = 'offboarding'
      AND DATE(ib.ts_synced - INTERVAL 3 HOUR) > DATE(t.ts_termination_request)
  WHERE
    t.status = 'DONE'
),
terminations AS (
  SELECT
    id_termination,
    id_contract,
    dt_inspection,
    ts_termination_request,
    ts_termination_finished,
    ts_termination_updated
  FROM
    terminations_ranked
  WHERE
    rn = 1
)
SELECT
  t.id_termination,
  t.id_contract,
  COALESCE(sfmc.id_ticket, sfspoc.id_ticket, zd.id_ticket) AS id_mediation_ticket,
  CASE
    WHEN sfmc.id_ticket IS NOT NULL THEN sfmc.squad
    WHEN sfspoc.id_ticket IS NOT NULL THEN sfspoc.squad
    ELSE zd.squad
  END AS squad,
  COALESCE(sfmc.id_ticket, sfspoc.id_ticket, zd.id_ticket) IS NOT NULL AS has_mediation_ticket,
  CASE
    WHEN sfmc.id_ticket IS NOT NULL THEN FALSE
    WHEN sfspoc.id_ticket IS NOT NULL THEN FALSE
    ELSE COALESCE(zd.is_ticket_opened_via_terminator, FALSE)
  END AS is_ticket_opened_via_terminator,
  COALESCE(sfmc.dt_mediation, sfspoc.dt_mediation, zd.dt_mediation) AS dt_mediation,
  t.dt_inspection,
  t.ts_termination_request,
  t.ts_termination_finished,
  t.ts_termination_updated
FROM
  terminations AS t
LEFT JOIN
  sf_mediation_cases AS sfmc
    ON t.id_contract = sfmc.id_contract
LEFT JOIN
  sf_spoc_mediation_tasks AS sfspoc
    ON t.id_contract = sfspoc.id_contract
LEFT JOIN
  zendesk_mediation AS zd
    ON t.id_contract = zd.id_contract
    AND (zd.id_termination IS NULL OR zd.id_termination = t.id_termination)
