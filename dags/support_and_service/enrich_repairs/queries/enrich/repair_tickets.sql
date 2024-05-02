WITH ticket_history_base AS (
    SELECT
        id_ticket,
        MIN(CASE
          WHEN tags LIKE ANY (
            "%pp_autosserviço_contestou%",
            "%iq_pp_autosserviço_contestou%",
            "%alteração_de_responsabilidade_criticidade%",
            "%acompanhamento_alteracao_responsabilidade_criticidade%",
            "%check_responsabilidade_reparos%",
            "%pp_autosserviço_contestou%"
          ) THEN ts_updated
        END) AS ts_contestation,
        MIN(CASE
          WHEN tags LIKE ANY (
            "%macro_ro_cont_benfeitoria_pp%", "%macro_ro_cont_benfeitoria_iq%", "%macro_ro_cont_terceiros_pp%",
            "%macro_ro_cont_terceiros_iq%", "%macro_ro_cont_aprovada_iq%", "%macro_ro_cont_aprovada_pp%",
            "%macro_ro_cont_reprovada_pp%", "%macro_ro_cont_reprovada_iq%", "%closed_by_merge%",
            "%reprovado_ro_%", "%aprovado_ro_%", "%opcional_ro_%", "%ação_backlog_contestação%",
            "%alteração_reprovada%", "%alteração_aprovada%", "%alteração_benfeitoria%"
          ) THEN ts_updated
        END) AS ts_resolution_contestation
    FROM
        datalake_zendesk.tickets
    WHERE
        year >= YEAR(CURRENT_DATE()) - 1
        AND YEAR(ts_updated) >= YEAR(CURRENT_DATE()) - 1
    GROUP BY 1
),
repair_tickets AS (
  SELECT DISTINCT
    tc.id_ticket,
    CASE
      WHEN (tc.tags LIKE ANY ('%iq_pp_autosserviço_contestou%', '%pp_autosserviço_contestou%')) THEN 'PWA'
      WHEN (tc.tags LIKE ANY (
          '%alteração_de_responsabilidade_criticidade%', '%acompanhamento_alteracao_responsabilidade_criticidade%',
          '%check_responsabilidade_reparos%', '%pp_contestou%'
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
      tc.group_name IN ('FullService [Back]','Prestadores Parceiros [SO]','Reparos [BACK]','Triagem Reparos [Back]','FullService [BACK]')
      AND (DATE(tc.ts_solved - INTERVAL 3 HOUR) >= DATE('2023-06-01') OR tc.ts_solved - INTERVAL 3 HOUR IS NULL)
      AND tc.channel NOT IN ('call')
      AND tc.status NOT IN ('deleted')
      AND tc.tags NOT LIKE '%caso_ticket_agregador%'
),
relisting_db AS (
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
      DATE_TRUNC('month',hl.ts_listing_version_start) >= ADD_MONTHS(DATE_TRUNC('month',CURRENT_DATE),-47)
      AND DATE_TRUNC('month',hl.ts_listing_version_start) <= DATE_ADD(CURRENT_DATE, -1)
      AND (hl.listing_category = 'Re-Listing')
      AND ((h.country_code <> 'MX') OR (h.country_code IS NULL))
),
relisting_distinct AS (
    SELECT
      id_contract,
      COUNT(DISTINCT listing) AS relisting
    FROM
      relisting_db
    WHERE
      id_contract IS NOT NULL
    GROUP BY 1
),
repairs_interaction AS (
    SELECT
      rr.id AS id_request,
      MIN(rr.ts_updated) AS ts_updated
    FROM
      datalake_repairs_clean.repair_request AS rr
    WHERE
      (STRING(GET_JSON_OBJECT(rr.owner_approval, '$.approved')) IS NOT NULL)
      AND CAST(rr.ts_created AS DATE) >= DATE('2023-01-01')
      AND rr.id_third_party_crm_ticket_external IS NOT NULL
    GROUP BY
      rr.id
),
service_provider AS (
    SELECT
      rr.id_third_party_crm_ticket_external AS sk_ticket,
      rr.id AS id_repair_request,
      rr.service_provider,
      rr.ts_created
    FROM
      datalake_repairs_clean.repair_request AS rr
    QUALIFY
      ROW_NUMBER() OVER (PARTITION BY rr.id_third_party_crm_ticket_external ORDER BY rr.ts_updated DESC) = 1
),
first_interaction AS(
    SELECT
      rr.id_third_party_crm_ticket_external,
      COALESCE(ri.ts_updated - INTERVAL 3 HOUR, rc.ts_started - INTERVAL 3 HOUR) AS ts_first_interaction,
      IF(rc.ts_started IS NOT NULL, TRUE, FALSE) AS has_chat_negociation
    FROM
      datalake_repairs_clean.repair_request AS rr
    LEFT JOIN
      datalake_repairs_clean.repair_request_chat AS rc
      ON rr.id = rc.id_repair_request
    LEFT JOIN
      repairs_interaction AS ri
      ON ri.id_request = rr.id
    GROUP BY rc.ts_started, ri.ts_updated, rr.id_third_party_crm_ticket_external
)

SELECT
  tc.id_ticket,
  rr.id_repair_request AS id_request,
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
  tc.analyst_organization AS agent_organization,
  th.contestation_task_origin,
  rr.service_provider,
  COALESCE(chat.contact_theme_tag, call.contact_theme_tag, email.contact_theme_tag) AS theme,
  COALESCE(chat.contact_theme_detail_tag, call.contact_theme_detail_tag, email.contact_theme_detail_tag) AS theme_detail,
  COALESCE(chat.request_type, call.request_type, email.request_type) AS request_type,
  COALESCE(chat.customer_type_tag, call.customer_type_tag, email.customer_type_tag) AS customer_type_tag,
  COALESCE(chat.contact_motivation_tag, call.contact_motivation_tag, email.contact_motivation_tag) AS motivation,
  COALESCE(chat.front_or_back, call.front_or_back, email.front_or_back) AS front_or_back,
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
  c.dt_entered AS entrance_date,
  th.ts_contestation,
  th.ts_resolution_contestation,
  fi.ts_first_interaction,
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
  YEAR(tc.ts_updated - INTERVAL 3 HOUR ) AS year,
  MONTH(tc.ts_updated - INTERVAL 3 HOUR ) AS month,
  DAY(tc.ts_updated - INTERVAL 3 HOUR ) AS day
FROM
  datalake_zendesk.tickets_current AS tc
LEFT JOIN
  datalake_customer_support.chat AS chat
    ON tc.id_ticket = chat.id_ticket
LEFT JOIN
  datalake_customer_support.call AS call
    ON tc.id_ticket = call.id_ticket
LEFT JOIN
  datalake_customer_support.email AS email
    ON tc.id_ticket = email.id_ticket
LEFT JOIN
  datalake_ebdb_contract.contract AS c
    ON tc.id_contract = c.id
LEFT JOIN
  service_provider AS rr
    ON tc.id_ticket = rr.sk_ticket
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
  repair_tickets AS th
    ON tc.id_ticket = th.id_ticket
WHERE
  tc.group_name IN ('Reparos [BACK]','Triagem Reparos [Back]','FullService [BACK]','Autosserviço Reparos [BACK]')
  AND (
    tc.ts_created >= DATE_ADD(CURRENT_DATE, -20*7)
    OR tc.ts_solved >= DATE('2023-01-01')
    OR tc.ts_solved IS NULL
  )
  AND tc.channel NOT IN ('call')
  AND tc.status NOT IN ('deleted')
  AND tc.tags NOT LIKE '%caso_ticket_agregador%'
QUALIFY
  ROW_NUMBER() OVER (PARTITION BY tc.id_ticket ORDER BY tc.ts_updated DESC) = 1
