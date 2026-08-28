WITH weekends_and_holidays AS (
  SELECT
    ad.date AS dt_non_working
  FROM datalake_quintoandar.aux_date AS ad
  WHERE
    ad.weekend = 'Weekend'
  UNION
  SELECT
    sch.dt_holiday AS dt_non_working
  FROM datalake_gsheets_clean.service_city_holidays AS sch
  WHERE
    sch.category = 'Nacional'
), csat AS (
  SELECT
    sk_case,
    ts_submitted,
    sk_answer,
    satisfaction_score,
    respondent_comments,
    is_solved
  FROM (
    SELECT
      sk_case,
      fa.ts_submitted,
      fa.sk_answer,
      satisfaction_score,
      respondent_comments,
      fa.is_solved,
      ROW_NUMBER() OVER (PARTITION BY sk_case ORDER BY fa.ts_submitted ASC) AS _w
    FROM dw_satisfaction_rating.fact_answer AS fa
    LEFT JOIN dw_satisfaction_rating.dim_answer AS da
      ON da.sk_answer = fa.sk_answer
    WHERE
      NOT satisfaction_score IS NULL
  ) AS _t
  WHERE
    _w = 1
), spoc AS (
  SELECT
    ft.sk_termination,
    ft.sk_contract,
    ft.ts_termination_request,
    ft.ts_termination_finished,
    ft.ts_termination_canceled,
    ft.is_spoc_contract,
    ft.spoc_wave,
    ft.is_spoc_control_group,
    dit.team AS spoc_team,
    dit.has_mediation,
    dit.has_ac_repairs,
    dit.dt_inspection,
    CASE
      WHEN ts_termination_request < CAST('2025-05-22' AS DATE)
      AND is_spoc_contract = TRUE
      AND (
        is_spoc_control_group = FALSE OR is_spoc_control_group IS NULL
      )
      THEN 'before_wave_6_lab_test'
      WHEN ts_termination_request < CAST('2025-05-22' AS DATE)
      AND is_spoc_contract = TRUE
      AND is_spoc_control_group = TRUE
      THEN 'before_wave_6_lab_control'
      WHEN ts_termination_request >= CAST('2025-05-22' AS DATE)
      AND is_spoc_contract = TRUE
      AND (
        is_spoc_control_group = FALSE OR is_spoc_control_group IS NULL
      )
      AND (
        dit.team IN ('ROLLOUT', 'BAU_LONG_LDT', 'BAU_SHORT_LDT') OR dit.team IS NULL
      )
      THEN 'rollout'
      WHEN ts_termination_request >= CAST('2025-05-22' AS DATE)
      AND is_spoc_contract = TRUE
      AND (
        is_spoc_control_group = FALSE OR is_spoc_control_group IS NULL
      )
      AND dit.team = 'LAB'
      THEN 'lab_test'
      WHEN ts_termination_request >= CAST('2025-05-22' AS DATE)
      AND is_spoc_contract = TRUE
      AND is_spoc_control_group = TRUE
      THEN 'lab_control'
      ELSE NULL
    END AS spoc_class
  FROM dw_offboarding.fact_terminations AS ft
  LEFT JOIN dw_offboarding.dim_termination AS dit
    ON ft.sk_termination = dit.sk_termination
  WHERE
    ft.ts_termination_canceled IS NULL
    AND ft.ts_termination_request >= CAST('2025-01-01' AS DATE)
), record_types AS (
  SELECT
    id_record_type,
    ts_last_modified,
    record_type_name,
    developer_name
  FROM (
    SELECT
      id_record_type,
      ts_last_modified,
      record_type_name,
      developer_name,
      ROW_NUMBER() OVER (PARTITION BY id_record_type ORDER BY ts_last_modified DESC) AS _w
    FROM datalake_salesforce_clean.record_types
  ) AS _t
  WHERE
    _w = 1
), first_reply_sf AS (
  SELECT
    c.id_case,
    c.case_number,
    CAST(c.ts_created AS TIMESTAMP) - INTERVAL '7' HOURS AS ts_created,
    MIN(e.ts_message - INTERVAL '7' HOURS) AS ts_first_reply,
    COUNT(DISTINCT ts_message) AS replies,
    (
      CAST(MIN(e.ts_message - INTERVAL '7' HOURS) AS BIGINT) - CAST((
        CAST(c.ts_created AS TIMESTAMP) - INTERVAL '7' HOURS
      ) AS BIGINT)
    ) /* Cálculo de diferença em minutos no Spark */ / 60 AS minutes_first_reply_time_business
  FROM datalake_salesforce_clean.cases AS c
  INNER JOIN datalake_salesforce_clean.email_message AS e
    ON c.id_case = e.id_parent
  WHERE
    NOT e.ts_message IS NULL AND e.is_incoming = FALSE
  GROUP BY
    c.id_case,
    c.case_number,
    c.ts_created
), first_resolution AS (
  SELECT
    COALESCE(tp.last_agent_email, u.email) AS last_agent_email,
    MIN(COALESCE(tp.ts_solved, c.ts_closed)) AS first_resolution
  FROM dw_bpo_performance.tickets_perspective AS tp
  LEFT JOIN datalake_salesforce_clean.users AS u
    ON u.email = tp.last_agent_email
  LEFT JOIN datalake_salesforce_clean.cases AS c
    ON c.id_owner = u.id_user_salesforce
  GROUP BY
    1
), tickets_perspective AS (
  SELECT
    case_number,
    sk_contract,
    sk_user,
    ts_started,
    ts_solved,
    ts_closed,
    channel,
    status,
    last_department,
    last_team,
    last_area,
    front_or_back,
    theme,
    theme_detail,
    theme_recontact_flag_d4,
    theme_recontact_flag_d0,
    is_ticket_solved_within_sla,
    is_auto_reparo,
    minutes_first_reply_time_business,
    subject,
    first_csat_ts_response,
    first_csat_score,
    first_csat_comment,
    resolution_survey,
    last_agent_email,
    last_agent_organization,
    is_spoc_test,
    is_pp_multi,
    first_resolution,
    reopens,
    off_area,
    tags,
    replies,
    ticket_type,
    canal_de_entrada,
    criticidade_ro,
    group_name_ro,
    flag_sla_reparos,
    flag_sla_med,
    tkt_despejo,
    tipo_de_cliente,
    Platform
  FROM (
    SELECT
      tp.sk_ticket AS case_number,
      CAST(tp.sk_contract AS STRING) AS sk_contract,
      tp.sk_user,
      tp.ts_started,
      tp.ts_solved,
      tp.ts_closed,
      tp.channel,
      tp.status,
      CASE
        WHEN last_department = '[AeC] CX Pagamentos [FRONT] [POS]'
        THEN 'CX Pagamentos [FRONT] [POS]'
        WHEN last_department = '[AeC] CX Rescisão [FRONT] [POS]'
        THEN 'CX Rescisão [FRONT] [POS]'
        WHEN last_department = '[AeC] CX Mudança [FRONT] [POS]'
        THEN 'CX Mudança [FRONT] [POS]'
        WHEN last_department = '[AeC] CX Reparos [FRONT] [POS]'
        THEN 'CX Reparos [FRONT] [POS]'
        WHEN last_department = '[AeC] CX Propostas [FRONT] [PRE]'
        THEN 'CX Propostas [FRONT] [PRE]'
        WHEN last_department = '[AeC] CX Visitas [FRONT] [PRE]'
        THEN 'CX Visitas [FRONT] [PRE]'
        WHEN last_department = '[AeC] CX Parceiros [FRONT] [PRE]'
        THEN 'CX Parceiros [FRONT] [PRE]'
        ELSE last_department
      END AS last_department,
      last_team,
      last_area,
      front_or_back,
      theme,
      theme_detail,
      theme_recontact_flag_d4,
      theme_recontact_flag_d0,
      is_ticket_solved_within_sla,
      CASE
        WHEN canal_de_entrada = 'Api / PWA' AND NOT group_name_ro IS NULL
        THEN 1
        ELSE 0
      END AS is_auto_reparo,
      minutes_first_reply_time_business,
      tp.subject,
      first_csat_ts_response,
      first_csat_score,
      first_csat_comment,
      resolution_survey,
      tp.last_agent_email,
      last_agent_organization,
      CASE
        WHEN spoc.is_spoc_contract = TRUE
        AND spoc.spoc_class IN ('before_wave_6_lab_test', 'lab_test', 'rollout')
        THEN TRUE
        ELSE FALSE
      END AS is_spoc_test,
      is_pp_multi,
      first_resolution,
      tp.reopens,
      off_area,
      tp.tags,
      tp.replies,
      tp.ticket_type,
      tp.canal_de_entrada,
      tp.criticidade_ro,
      tp.group_name_ro,
      CASE
        WHEN (
          CASE
            WHEN ddend.is_brz_holiday = 'Holiday'
            OR DAYOFWEEK(TO_DATE(deadline_ticket_reparos)) = 1
            THEN DATE_ADD(deadline_ticket_reparos, 1)
            ELSE deadline_ticket_reparos
          END
        ) >= TS_SOLVED
        THEN 1
        ELSE 0
      END AS flag_sla_reparos,
      CASE
        WHEN COALESCE(CAST(spoc.ts_termination_finished AS DATE), CURRENT_DATE) >= ww_backlog.dt_end_9
        THEN 0
        ELSE 1
      END AS flag_sla_med,
      IF(
        dt.group_name = 'Rescisão por Inadimplência [OFF][POS][BACK]'
        AND tp.tipo_de_cliente LIKE '%proprietário%'
        AND tp.tipo_de_demanda IN ('demanda_de_processos')
        AND tp.tipo_de_processo IN ('despejo/fraude')
        AND dt.subject LIKE '%Rescisão do contrato%',
        'despejo',
        NULL
      ) AS tkt_despejo,
      tp.tipo_de_cliente,
      'Zendesk' AS Platform,
      ROW_NUMBER() OVER (PARTITION BY tp.sk_ticket ORDER BY tp.ts_load DESC) AS _w,
      tp.sk_ticket,
      tp.ts_load
    FROM dw_bpo_performance.tickets_perspective AS tp
    LEFT JOIN spoc
      ON tp.sk_contract = spoc.sk_contract
    LEFT JOIN first_resolution AS fr
      ON fr.last_agent_email = tp.last_agent_email
    LEFT JOIN dw_public.dim_date AS ddend
      ON ddend.date = deadline_ticket_reparos
    LEFT JOIN datalake_date.workday_window AS ww_backlog
      ON CAST(tp.ts_started AS DATE) = ww_backlog.dt_ref AND ww_backlog.id_city = 39
    LEFT JOIN dw_customer_support.dim_ticket AS dt
      ON dt.sk_ticket = tp.sk_ticket
  ) AS _t
  WHERE
    _w = 1
), solved_date AS (
  SELECT
    case_number,
    status,
    ts_event
  FROM (
    SELECT
      CAST(case_number AS INT) AS case_number,
      status,
      CAST(last_modified_date AS TIMESTAMP) - INTERVAL '7' HOURS AS ts_event,
      ROW_NUMBER() OVER (PARTITION BY CAST(case_number AS INT) ORDER BY CAST(last_modified_date AS TIMESTAMP) ASC) AS _w,
      last_modified_date
    FROM datalake_salesforce_clean.events_Case AS E
    WHERE
      status = 'Solved'
  ) AS _t
  WHERE
    _w = 1
), case_span AS (
  SELECT
    c.id_case,
    CAST(c.ts_created AS DATE) AS dt_start,
    COALESCE(
      CAST(COALESCE(c.ts_closed, sd.ts_event) AS DATE),
      CURRENT_DATE
    ) AS dt_end
  FROM datalake_salesforce_clean.cases AS c
  LEFT JOIN solved_date AS sd
    ON sd.case_number = c.case_number
), case_days AS (
  SELECT
    cs.id_case,
    EXPLODE(SEQUENCE(cs.dt_start, cs.dt_end, INTERVAL 1 DAY)) AS dt_day
  FROM case_span AS cs
  WHERE
    cs.dt_start IS NOT NULL
    AND cs.dt_end IS NOT NULL
    AND cs.dt_start <= cs.dt_end
), case_non_working_days AS (
  SELECT
    cd.id_case,
    COUNT(wh.dt_non_working) AS total_non_working
  FROM case_days AS cd
  LEFT JOIN weekends_and_holidays AS wh
    ON wh.dt_non_working = cd.dt_day
  GROUP BY
    cd.id_case
), events AS (
  SELECT
    case_number,
    case_reason,
    fila_omni_channel,
    reopens,
    id_inspection,
    id_house,
    is_eviction,
    is_pp_multi,
    is_kirk,
    is_high_value,
    client_type,
    criticidade,
    criticidade_sla,
    sla_target,
    event_type
  FROM (
    SELECT
      CAST(case_number AS INT) AS case_number,
      reason AS case_reason,
      omni_channel_queue__c AS fila_omni_channel,
      fr_case_reopen_count__c AS reopens,
      inspection_external_id__c AS id_inspection,
      property_id__c AS id_house,
      is_eviction__c AS is_eviction,
      is_pp_multi__c AS is_pp_multi,
      is_kirk__c AS is_kirk,
      is_high_value__c AS is_high_value,
      client_type__c AS client_type,
      criticality__c AS criticidade,
      criticality_sla__c AS criticidade_sla,
      sla_due_days__c AS sla_target,
      event_type AS event_type,
      ROW_NUMBER() OVER (PARTITION BY CAST(case_number AS INT) ORDER BY last_modified_date DESC) AS _w,
      last_modified_date
    FROM datalake_salesforce_clean.events_case
  ) AS _t
  WHERE
    _w = 1
), cases_perspective AS (
  SELECT
    id_case,
    case_number,
    id_contract,
    sk_user,
    external_id__c,
    team,
    Front_Or_Back,
    Pre_Pos,
    Area,
    ops,
    case_status,
    subject,
    record_type_name,
    theme,
    case_type,
    ts_created,
    ts_solved,
    ts_closed,
    sk_answer_csat,
    first_csat_ts_response,
    first_csat_score,
    first_csat_comment,
    is_solved,
    data_first_reply,
    minutes_first_reply_time_business,
    replies,
    ldt_ticket,
    sla_tgt,
    is_ticket_solved_within_sla,
    agent_email,
    agent_organization,
    flag_teste,
    is_spoc_contract,
    spoc_wave,
    is_spoc_control_group,
    spoc_team,
    spoc_class,
    is_spoc_test,
    case_origin,
    first_resolution,
    off_area,
    flag_sla_med,
    supplied_email,
    case_reason,
    fila_omni_channel,
    reopens,
    id_inspection,
    id_house,
    is_eviction,
    is_pp_multi,
    is_kirk,
    is_high_value,
    client_type,
    criticidade,
    criticidade_sla,
    event_type,
    tkt_despejo,
    channel,
    Platform
  FROM (
    SELECT DISTINCT
      c.id_case,
      c.case_number,
      c.id_contract,
      du.sk_user,
      external_id__c,
      sla.ops AS team,
      sla.Front_Or_Back,
      sla.Pre_Pos,
      sla.Area,
      sla.ops,
      c.case_status,
      c.case_subject AS subject,
      rt.record_type_name,
      rt.developer_name AS theme,
      case_type,
      c.ts_created,
      sd.ts_event AS ts_solved,
      c.ts_closed,
      csat.sk_answer AS sk_answer_csat,
      csat.ts_submitted AS first_csat_ts_response,
      csat.satisfaction_score AS first_csat_score,
      csat.respondent_comments AS first_csat_comment,
      csat.is_solved,
      c.ts_created + (
        INTERVAL '1' MINUTE * fr.minutes_first_reply_time_business
      ) AS data_first_reply,
      fr.minutes_first_reply_time_business AS minutes_first_reply_time_business,
      fr.replies,
      DATEDIFF(TO_DATE(c.ts_closed), TO_DATE(c.ts_created)) AS ldt_ticket,
      COALESCE(cm.target_response_in_days, CAST(sla.sla_tgt AS INT)) AS sla_tgt,
      CASE
        WHEN ts_closed IS NULL
        THEN NULL
        WHEN (
          DATEDIFF(
            TO_DATE(CAST(COALESCE(c.ts_closed, sd.ts_event) AS DATE)),
            TO_DATE(CAST(c.ts_created AS DATE))
          ) - COALESCE(cnw.total_non_working, 0)
        ) <= COALESCE(cm.target_response_in_days, CAST(sla.sla_tgt AS INT))
        THEN TRUE
        ELSE FALSE
      END AS is_ticket_solved_within_sla,
      u.email AS agent_email,
      CASE
        WHEN u.email LIKE '%webhelp%'
        THEN 'webhelp'
        WHEN u.email LIKE '%atento%'
        THEN 'atento'
        WHEN u.email LIKE '%aec%'
        THEN 'aec'
        WHEN u.email LIKE '%quintoandar%'
        THEN 'quintoandar'
      END AS agent_organization,
      CASE WHEN rt.record_type_name RLIKE '\\[NÃO UTILIZAR\\]' THEN 'Sim' ELSE 'Não' END AS flag_teste,
      spoc.is_spoc_contract,
      spoc.spoc_wave,
      spoc.is_spoc_control_group,
      spoc.spoc_team,
      spoc.spoc_class,
      CASE
        WHEN spoc.is_spoc_contract = TRUE
        AND spoc.spoc_class IN ('before_wave_6_lab_test', 'lab_test', 'rollout')
        THEN TRUE
        ELSE FALSE
      END AS is_spoc_test,
      c.case_origin,
      fr_res.first_resolution,
      CASE WHEN c.case_type LIKE '%Mediation%' THEN 'MED' END AS off_area,
      CASE
        WHEN COALESCE(CAST(spoc.ts_termination_finished AS DATE), CURRENT_DATE) >= ww_backlog.dt_end_9
        THEN 0
        ELSE 1
      END AS flag_sla_med,
      c.supplied_email,
      e.case_reason,
      e.fila_omni_channel,
      e.reopens,
      e.id_inspection,
      e.id_house,
      e.is_eviction,
      e.is_pp_multi,
      e.is_kirk,
      e.is_high_value,
      e.client_type,
      e.criticidade,
      e.criticidade_sla,
      e.event_type,
      CASE WHEN c.omni_channel_queue = 'Squad 7 - Mediação' THEN 'despejo' ELSE NULL END AS tkt_despejo,
      'email' AS channel,
      'SalesForce' AS Platform,
      ROW_NUMBER() OVER (PARTITION BY c.case_number ORDER BY c.TS_LAST_MODIFIED DESC) AS _w,
      c.TS_LAST_MODIFIED
    FROM datalake_salesforce_clean.cases AS c
    LEFT JOIN record_types AS rt
      ON rt.id_record_type = c.id_record_type
    LEFT JOIN csat AS csat
      ON csat.sk_case = c.id_Case
    LEFT JOIN sandbox.sla_target_salesforce AS sla
      ON sla.theme_type = COALESCE(CONCAT(rt.developer_name, c.case_type), rt.developer_name)
    LEFT JOIN datalake_salesforce_clean.users AS u
      ON u.id_user_salesforce = c.id_owner
    LEFT JOIN datalake_salesforce_clean.account AS a
      ON a.id_account = c.id_account
    LEFT JOIN spoc
      ON CAST(c.id_contract AS STRING) = CAST(spoc.sk_contract AS STRING)
    LEFT JOIN first_reply_sf AS fr
      ON fr.id_case = c.id_case
    LEFT JOIN first_resolution AS fr_res
      ON fr_res.last_agent_email = u.email
    LEFT JOIN datalake_date.workday_window AS ww_backlog
      ON CAST(C.ts_created AS DATE) = ww_backlog.dt_ref AND ww_backlog.id_city = 39
    LEFT JOIN solved_date AS sd
      ON sd.case_number = c.case_number
    LEFT JOIN datalake_salesforce_clean.events_case_member AS cm
      ON cm.case__c = c.id_Case AND type__c = 'Service requester'
    LEFT JOIN dw_public.dim_user AS du
      ON du.uuid_person = SPLIT(cm.external_id__c, '_')[2]
    LEFT JOIN case_non_working_days AS cnw
      ON cnw.id_case = c.id_case
    LEFT JOIN datalake_salesforce_clean.case_milestones AS cm
      ON cm.id_case = c.id_case
    LEFT JOIN events AS e
      ON e.case_number = c.case_number
  ) AS _t
  WHERE
    _w = 1
)
SELECT
  case_number,
  ts_created AS ts_started,
  COALESCE(ts_solved, ts_closed) AS ts_solved,
  ts_closed AS ts_closed,
  id_contract AS sk_contract,
  sk_user AS sk_user,
  channel,
  case_status AS status,
  fila_omni_channel AS last_team,
  Area AS last_area,
  front_or_back,
  COALESCE(fila_omni_channel, record_type_name) AS last_department,
  first_csat_ts_response,
  first_csat_score,
  first_csat_comment,
  is_solved AS resolution_survey,
  minutes_first_reply_time_business,
  subject,
  theme,
  case_type AS theme_detail,
  NULL AS theme_recontact_flag_d4,
  NULL AS theme_recontact_flag_d0,
  is_ticket_solved_within_sla,
  agent_email AS last_agent_email,
  agent_organization AS last_agent_organization,
  reopens AS reopens,
  is_spoc_test,
  is_pp_multi,
  off_area,
  NULL AS tags,
  replies,
  NULL AS ticket_type,
  client_type,
  case_origin AS canal_de_entrada,
  NULL AS is_auto_reparo,
  NULL AS group_name_ro,
  criticidade AS criticidade_ro,
  NULL AS flag_sla_reparos,
  flag_sla_med,
  tkt_despejo AS tkt_despejo,
  first_resolution AS first_resolution_last_agent,
  id_inspection,
  id_house,
  is_eviction,
  is_kirk,
  is_high_value,
  criticidade_sla,
  event_type,
  supplied_email,
  Platform,
  YEAR(TO_DATE(CURRENT_DATE)) AS year,
  MONTH(TO_DATE(CURRENT_DATE)) AS month,
  DAY(TO_DATE(CURRENT_DATE)) AS day,
  NOW() AS ts_load
FROM cases_perspective
UNION ALL
SELECT
  case_number,
  ts_started,
  ts_solved,
  ts_closed,
  sk_contract,
  CAST(sk_user AS STRING) AS sk_user,
  channel,
  status,
  last_team,
  last_area,
  front_or_back,
  last_department,
  first_csat_ts_response,
  first_csat_score,
  first_csat_comment,
  resolution_survey,
  minutes_first_reply_time_business,
  subject,
  theme,
  theme_detail,
  theme_recontact_flag_d4,
  theme_recontact_flag_d0,
  is_ticket_solved_within_sla,
  last_agent_email,
  last_agent_organization,
  reopens,
  is_spoc_test,
  is_pp_multi,
  off_area,
  tags,
  replies,
  ticket_type,
  tipo_de_cliente AS client_type,
  canal_de_entrada,
  is_auto_reparo,
  group_name_ro,
  criticidade_ro,
  flag_sla_reparos,
  flag_sla_med,
  tkt_despejo,
  first_resolution AS first_resolution_last_agent,
  NULL AS id_inspection,
  NULL AS id_house,
  NULL AS is_eviction,
  NULL AS supplied_email,
  NULL AS is_kirk,
  NULL AS is_high_value,
  NULL AS criticidade_sla,
  NULL AS event_type,
  Platform,
  YEAR(TO_DATE(CURRENT_DATE)) AS year,
  MONTH(TO_DATE(CURRENT_DATE)) AS month,
  DAY(TO_DATE(CURRENT_DATE)) AS day,
  NOW() AS ts_load
FROM tickets_perspective
