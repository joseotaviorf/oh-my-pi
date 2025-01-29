WITH ticket_history_base AS (
  SELECT
    t.id_ticket,
    MIN(CASE
      WHEN t.tags LIKE ANY (
        "%pp_autosserviço_contestou%",
        "%iq_pp_autosserviço_contestou%",
        "%alteração_de_responsabilidade_criticidade%",
        "%acompanhamento_alteracao_responsabilidade_criticidade%",
        "%check_responsabilidade_reparos%",
        "%pp_autosserviço_contestou%"
      ) THEN t.ts_updated
    END) AS ts_contestation,
    MIN(CASE
      WHEN t.tags LIKE ANY (
        "%macro_ro_cont_benfeitoria_pp%",
        "%macro_ro_cont_benfeitoria_iq%",
        "%macro_ro_cont_terceiros_pp%",
        "%macro_ro_cont_terceiros_iq%",
        "%macro_ro_cont_aprovada_iq%",
        "%macro_ro_cont_aprovada_pp%",
        "%macro_ro_cont_reprovada_pp%",
        "%macro_ro_cont_reprovada_iq%",
        "%closed_by_merge%",
        "%reprovado_ro_%",
        "%aprovado_ro_%",
        "%opcional_ro_%",
        "%ação_backlog_contestação%",
        "%alteração_reprovada%",
        "%alteração_aprovada%",
        "%alteração_benfeitoria%"
      ) THEN t.ts_updated
    END) AS ts_resolution_contestation
  FROM
    datalake_zendesk.tickets AS t
  WHERE
    MAKE_DATE(t.year,t.month,t.day) >= CURRENT_DATE - INTERVAL 1 YEAR
    AND t.ts_updated >= CURRENT_DATE - INTERVAL 1 YEAR
  GROUP BY
    ALL
)
,repair_tickets AS (
  SELECT DISTINCT
    tc.id_ticket,
    CASE
      WHEN (
          tc.tags LIKE ANY (
            '%iq_pp_autosserviço_contestou%',
            '%pp_autosserviço_contestou%')) THEN 'PWA'
      WHEN
        (tc.tags LIKE ANY (
          '%alteração_de_responsabilidade_criticidade%',
          '%acompanhamento_alteracao_responsabilidade_criticidade%',
          '%check_responsabilidade_reparos%',
          '%pp_contestou%'
        )
      ) AND tc.tags NOT LIKE '%ticket_acompanhamento%' THEN 'CX'
    END AS contestation_task_origin,
    IF(tc.tags LIKE '%closed_by_merge%', TRUE, FALSE) AS is_closed_by_merge,
    IF(
      ww.dt_end_1 > (CURRENT_DATE - INTERVAL 1 DAY)
      AND ts_resolution_contestation IS NULL
      AND DATE(tc.ts_solved - INTERVAL 3 HOUR
    ) IS NULL, TRUE, FALSE) AS is_contestation_backlog,
    IF(tc.tags LIKE '%ticket_acompanhamento%', TRUE, FALSE) AS is_ticket_followup,
    th.ts_contestation,
    th.ts_resolution_contestation
  FROM
    datalake_zendesk.tickets_current AS tc
  INNER JOIN
    ticket_history_base AS th
      ON th.id_ticket = tc.id_ticket
  LEFT JOIN
    datalake_date.workday_window AS ww
      ON ww.dt_Ref = DATE(th.ts_contestation) AND id_city = 39
  WHERE
    tc.year >= YEAR(CURRENT_DATE - INTERVAL 1 YEAR)
    AND tc.group_name IN (
      'FullService [Back]',
      'Prestadores Parceiros [SO]',
      'Reparos [BACK]',
      'Triagem Reparos [Back]',
      'FullService [BACK]',
      'ReparAção (Piloto Urgente)')
    AND tc.channel NOT IN ('call')
    AND tc.status NOT IN ('deleted')
    AND tc.tags NOT LIKE '%caso_ticket_agregador%'
)
,relisting_db AS (
    SELECT
      rf.id_contract,
      IF(hl.version >= 0, hl.id_house_listing, NULL) AS listing
    FROM
      datalake_ebdb_rent_flow.rent_flow AS rf
    LEFT JOIN
      datalake_ebdb_listing.house_listing AS hl
        ON rf.id_house = hl.id_house
    LEFT JOIN
      datalake_ebdb_listing.house AS h
        ON rf.id_house = h.id
    WHERE
      hl.ts_listing_version_start BETWEEN CURRENT_DATE - INTERVAL 3 YEAR AND CURRENT_DATE - 1
      AND (hl.listing_category = 'Re-Listing')
      AND ((h.country_code <> 'MX') OR (h.country_code IS NULL))
)
,relisting_distinct AS (
  SELECT
    id_contract,
    COUNT(DISTINCT listing) AS relisting
  FROM
    relisting_db
  WHERE
    id_contract IS NOT NULL
  GROUP BY
    ALL
)
,repairs_interaction AS (
  SELECT
    rr.id AS id_request,
    rr.id_contract,
    rr.ts_updated
  FROM
    datalake_repairs_clean.repair_request AS rr
  WHERE
    (STRING(GET_JSON_OBJECT(rr.owner_approval, '$.approved')) IS NOT NULL)
    AND CAST(rr.ts_created AS DATE) >= CURRENT_DATE - INTERVAL 1 YEAR
    AND rr.id_third_party_crm_ticket_external IS NOT NULL
  QUALIFY
    ROW_NUMBER() OVER(PARTITION BY rr.id, rr.id_third_party_crm_ticket_external ORDER BY rr.ts_updated ASC) = 1
)
,repair_interaction_pp AS (
  SELECT
    sr.id_repair_request
    , ri.ts_updated
    , sr.id_third_party_crm_ticket_external
  FROM
    datalake_repairs_clean.service_request sr
  LEFT JOIN
    repairs_interaction AS ri
      ON ri.id_request = sr.id_repair_request
  WHERE
    CAST(sr.ts_created AS DATE) >= CURRENT_DATE - INTERVAL 1 YEAR
    AND sr.id_third_party_crm_ticket_external IS NOT NULL
  QUALIFY
    ROW_NUMBER() OVER(PARTITION BY sr.id_repair_request, ri.id_contract ORDER BY sr.id_third_party_crm_ticket_external ASC) = 1
)
,service_provider AS (
  SELECT
    rr.id_third_party_crm_ticket_external AS sk_ticket,
    rr.id AS id_repair_request,
    rr.service_provider,
    rr.ts_created
  FROM
    datalake_repairs_clean.repair_request AS rr
  QUALIFY
    ROW_NUMBER() OVER (PARTITION BY rr.id_third_party_crm_ticket_external ORDER BY rr.ts_updated DESC) = 1
)
,first_interaction AS(
  SELECT
    sr.id_third_party_crm_ticket_external,
    IF(rc.ts_started IS NOT NULL, TRUE, FALSE) AS has_chat_negociation,
    CASE
      WHEN ri.ts_updated <= rc.ts_started THEN (ri.ts_updated - INTERVAL 3 HOUR)
      WHEN ri.ts_updated > rc.ts_started THEN (rc.ts_started - INTERVAL 3 HOUR)
      ELSE COALESCE(ri.ts_updated - INTERVAL 3 HOUR ,rc.ts_started - INTERVAL 3 HOUR)
    END AS ts_first_interaction,
    DATE(rc.ts_started - INTERVAL 3 HOUR) AS dt_chat
  FROM
    datalake_repairs_clean.service_request sr
  LEFT JOIN
    datalake_repairs_clean.repair_request AS rr
      ON rr.id = sr.id_repair_request
  LEFT JOIN
    datalake_repairs_clean.repair_request_chat AS rc
      ON rr.id = rc.id_repair_request
  LEFT JOIN
    repairs_interaction AS ri
      ON ri.id_request = rr.id
  GROUP BY
    ALL
)
,ticket_comment_metrics AS (
  SELECT
    tc.id_ticket,
    MAX(CASE WHEN is_public AND zu.role = 'end-user' THEN tc.ts_created END) AS ts_latest_customer_comment,
    MAX(CASE WHEN is_public AND zu.role = 'agent' THEN tc.ts_created END) AS ts_latest_analyst_comment
  FROM
    datalake_zendesk_clean.ticket_comments AS tc
  LEFT JOIN
    datalake_support_users.zendesk_users AS zu
      ON zu.id_user_zendesk = tc.id_author
  GROUP BY 1
)
SELECT
  tc.id_ticket,
  REPLACE(CAST(GET_JSON_OBJECT(TO_JSON(tc.custom_fields), '$["Ticket do contato"]') AS STRING),'#','') AS id_contact_ticket,
  sr.id_repair_request AS id_request,
  CAST(tc.id_contract AS INTEGER) AS id_contract,
  tc.group_name,
  tc.client_type,
  tc.status,
  TO_JSON(tc.custom_fields) AS custom_fields,
  tc.tags,
  tc.via_channel AS ticket_via,
  tc.channel,
  tc.analyst_name AS agent_name,
  tc.analyst_email AS agent_email,
  u.email AS email_assigned,
  dzr.email AS email_requester,
  CASE
    WHEN tc.analyst_organization = 'atn' THEN 'atento'
    WHEN tc.analyst_organization = 'atento' THEN 'atento'
    WHEN tc.analyst_organization = 'webhelp' THEN 'webhelp'
    WHEN tc.analyst_organization = 'webhelpbr' THEN 'webhelp'
    WHEN tc.analyst_organization = 'quintoandar.com' THEN 'quintoandar'
    WHEN tc.analyst_organization = 'quintoandar' THEN 'quintoandar'
    WHEN tc.analyst_organization = 'contractors' THEN 'webhelp'
    ELSE tc.analyst_organization
  END AS agent_organization,
  th.contestation_task_origin,
  rr.service_provider,
  t.contact_theme_tag AS theme,
  t.contact_theme_detail_tag AS theme_detail,
  t.request_type AS request_type,
  t.customer_type_tag AS customer_type_tag,
  t.contact_motivation_tag AS motivation,
  t.front_or_back AS front_or_back,
  csat.respondent_comments AS comment_csat,
  csat.improvement_tags AS csat_tags,
  csat.satisfaction_score AS csat_score,
  csat.secondary_satisfaction_score AS csat_partes,
  th.is_closed_by_merge,
  th.is_contestation_backlog,
  th.is_ticket_followup,
  fi.has_chat_negociation,
  CAST(tc.reopens AS INT) AS reopens,
  CAST(tc.replies AS INT) AS replies,
  rd.relisting,
  CAST(tc.reply_time_min_calendar AS INT) AS minutes_first_reply_time_calendar,
  COALESCE(
    TRY_CAST(from_unixtime(unix_timestamp(
      CAST(GET_JSON_OBJECT(TO_JSON(tc.custom_fields), '$["[Data] Definição do prestador"]') AS STRING), 'dd/MM/yy HH')) AS TIMESTAMP),
    TRY_CAST(SPLIT(SPLIT(TO_JSON(tc.custom_fields), '[Data] Definição do prestador":"')[1], '"')[0] AS DATE)
  ) AS dt_definition,
  fi.dt_chat,
  c.dt_entered AS entrance_date,
  th.ts_contestation,
  th.ts_resolution_contestation,
  CASE
    WHEN
      tc.client_type = 'proprietário'
      AND rpp.ts_updated >= tc.ts_created - INTERVAL 3 HOUR
    THEN rpp.ts_updated
    ELSE fi.ts_first_interaction
  END AS ts_first_interaction,
  tc.ts_created - INTERVAL 3 HOUR AS ts_created_local,
  tc.ts_updated - INTERVAL 3 HOUR AS ts_updated_local,
  CASE
    WHEN tc.status = 'closed' THEN tc.ts_updated - INTERVAL 3 HOUR
    ELSE NULL
  END AS ts_closed_local,
  tc.ts_solved - INTERVAL 3 HOUR AS ts_solved_local,
  rr.ts_created - INTERVAL 3 HOUR AS ts_request_created,
  CAST(csat.ts_submitted AS DATE) AS ts_csat_response_submitted,
  tc.ts_initially_assigned  - INTERVAL 3 HOUR AS ts_initially_assigned_local,
  tc.ts_assigned - INTERVAL 3 HOUR AS ts_last_assigned_local,
  tcm.ts_latest_customer_comment,
  tcm.ts_latest_analyst_comment,
  YEAR(tc.ts_updated - INTERVAL 3 HOUR ) AS year,
  MONTH(tc.ts_updated - INTERVAL 3 HOUR ) AS month,
  DAY(tc.ts_updated - INTERVAL 3 HOUR ) AS day
FROM
  datalake_zendesk.tickets_current AS tc
LEFT JOIN
  datalake_customer_support.tickets AS t
    ON t.id_ticket = tc.id_ticket
LEFT JOIN
  datalake_ebdb_contract.contract AS c
    ON tc.id_contract = c.id
LEFT JOIN
  datalake_repairs_clean.service_request AS sr
    ON sr.id_third_party_crm_ticket_external = tc.id_ticket
LEFT JOIN
  service_provider AS rr
    ON sr.id_repair_request = rr.id_repair_request
LEFT JOIN
  repairs_interaction AS ri
    ON ri.id_request = rr.id_repair_request
LEFT JOIN
  relisting_distinct AS rd
    ON rd.id_contract = tc.id_contract
LEFT JOIN
  datalake_survicate.repairs_surveys AS csat
    ON csat.id_ticket = tc.id_ticket
LEFT JOIN
  datalake_repairs_clean.repair_request AS rr_first_interaction
    ON tc.id_ticket = rr_first_interaction.id_third_party_crm_ticket_external
    AND rr_first_interaction.id_third_party_crm_ticket_external IS NOT NULL
LEFT JOIN
  first_interaction AS fi
    ON fi.id_third_party_crm_ticket_external = tc.id_ticket
LEFT JOIN
  repair_interaction_pp AS rpp
    ON rpp.id_third_party_crm_ticket_external = tc.id_ticket
LEFT JOIN
  repair_tickets AS th
    ON tc.id_ticket = th.id_ticket
LEFT JOIN
  datalake_support_users.zendesk_users AS u
    ON u.id_user_zendesk = tc.id_assignee
LEFT JOIN
  datalake_support_users.zendesk_users AS dzr
    ON dzr.id_user_zendesk = tc.id_requester
LEFT JOIN
  ticket_comment_metrics AS tcm
    ON tcm.id_ticket = t.id_ticket
WHERE
  tc.group_name IN (
    'Reparos [BACK]',
    'Triagem Reparos [Back]',
    'FullService [BACK]',
    'Autosserviço Reparos [BACK]',
    'ReparAção (Piloto Urgente)')
  AND (
    tc.ts_created >= CURRENT_DATE - INTERVAL 6 MONTH
    OR tc.ts_solved >= CURRENT_DATE - INTERVAL 2 YEAR
    OR tc.ts_solved IS NULL
  )
  AND tc.channel NOT IN ('call')
  AND tc.status NOT IN ('deleted')
  AND tc.tags NOT LIKE '%caso_ticket_agregador%'
QUALIFY
  ROW_NUMBER() OVER (PARTITION BY tc.id_ticket ORDER BY tc.ts_updated DESC) = 1
