WITH recontact_data AS (
  SELECT
    id_ticket,
    is_recontact_ticket
  FROM (
    SELECT
      t.id_ticket,
      IF(t.ts_updated > t.ts_solved, TRUE, FALSE) AS is_recontact_ticket,
      ROW_NUMBER() OVER (PARTITION BY t.id_ticket ORDER BY t.ts_updated DESC) AS _w,
      t.ts_updated
    FROM datalake_customer_support.tickets AS t
    WHERE
      CAST(t.ts_solved AS DATE) BETWEEN CAST('{load_start_date}' AS DATE) AND CAST('{load_end_date}' AS DATE)
  ) AS _t
  WHERE
    _w = 1
), repair_ongoing AS (
  SELECT
    rt.id_ticket,
    MD5(rt.agent_email) AS id_agent,
    NULL AS csat_score,
    rt.replies AS replies,
    IF(rt.reopens > 0, 1, NULL) AS reopens,
    DATEDIFF(
      TO_DATE(COALESCE(CAST(rt.ts_solved_local AS DATE), CAST(rt.ts_closed_local AS DATE))),
      TO_DATE(CAST(rt.ts_created_local AS DATE))
    ) AS frt,
    COALESCE(CAST(rt.ts_solved_local AS DATE), CAST(rt.ts_closed_local AS DATE)) AS dt_solved,
    rt.ts_updated_local,
    NULL AS ts_csat_response_submitted
  FROM datalake_repairs.ongoing_repair_tickets AS rt
  WHERE
    (
      NOT rt.tags LIKE '%teste_ps_pp_grupo_b_intermediacao_autosservico%'
      AND NOT rt.tags LIKE '%mvp_fup_iq_intermediacao_autosservico%'
      OR rt.tags LIKE '%mvp_fup_iq_intermediacao_autosservico%'
    )
    AND COALESCE(CAST(rt.ts_solved_local AS DATE), CAST(rt.ts_closed_local AS DATE)) BETWEEN CAST('{load_start_date}' AS DATE) AND CAST('{load_end_date}' AS DATE)
    AND NOT rt.tags LIKE '%closed_by_merge%'
    AND rt.group_name <> 'FullService [BACK]'
  UNION ALL
  SELECT
    rt.id_ticket AS id_ticket,
    MD5(rt.agent_email) AS id_agent,
    rt.csat_score,
    NULL AS replies,
    NULL AS reopens,
    NULL AS frt,
    NULL AS dt_solved,
    rt.ts_updated_local,
    rt.ts_csat_response_submitted AS ts_csat_response_submitted
  FROM datalake_repairs.ongoing_repair_tickets AS rt
  WHERE
    (
      NOT rt.tags LIKE '%teste_ps_pp_grupo_b_intermediacao_autosservico%'
      AND NOT rt.tags LIKE '%mvp_fup_iq_intermediacao_autosservico%'
      OR rt.tags LIKE '%mvp_fup_iq_intermediacao_autosservico%'
    )
    AND CAST(rt.ts_csat_response_submitted AS DATE) BETWEEN CAST('{load_start_date}' AS DATE) AND CAST('{load_end_date}' AS DATE)
), without_agg_infos AS (
  SELECT
    id_ticket,
    id_agent,
    team,
    status,
    resolution_survey,
    reopened_tickets,
    replied_tickets,
    first_csat_score,
    attendance_time,
    is_recontact_ticket,
    is_received_demand,
    is_productive_ticket,
    is_first_department_interaction,
    is_backlog_in_time,
    is_backlog_not_in_time,
    is_backlog,
    frt,
    ts_csat_response,
    dt_reference
  FROM (
    SELECT
      t.id_ticket,
      MD5(t.last_analyst_email) AS id_agent,
      dc.team,
      rd.status,
      csat.is_solved AS resolution_survey,
      t.reopens AS reopened_tickets,
      t.replies AS replied_tickets,
      csat.first_csat_score AS first_csat_score,
      DATEDIFF(TO_DATE(t.ts_solved), TO_DATE(t.ts_created)) AS attendance_time,
      r.is_recontact_ticket,
      IF(
        CAST(t.ts_solved AS DATE) = CAST('{load_start_date}' AS DATE)
        OR CAST(t.ts_closed AS DATE) = CAST('{load_start_date}' AS DATE),
        TRUE,
        FALSE
      ) AS is_received_demand,
      IF(CAST(t.ts_solved AS DATE) = CAST('{load_start_date}' AS DATE), TRUE, FALSE) AS is_productive_ticket,
      CASE
        WHEN ROW_NUMBER() OVER (PARTITION BY MD5(
          COALESCE(
            CONCAT(rd.sk_call, 'call'),
            CONCAT(rd.sk_session, 'chat'),
            CONCAT(rd.sk_ticket, 'email')
          )
        ), rd.sk_department ORDER BY COALESCE(rd.ts_task_created, rd.ts_task_created)) = 1
        THEN TRUE
        ELSE FALSE
      END AS is_first_department_interaction,
      bmt.is_backlog_in_time,
      bmt.is_backlog_not_in_time,
      IF(bmt.is_backlog_in_time OR bmt.is_backlog_not_in_time, TRUE, FALSE) AS is_backlog,
      NULL AS frt,
      csat.ts_first_response AS ts_csat_response,
      CAST('{load_start_date}' AS DATE) AS dt_reference,
      ROW_NUMBER() OVER (PARTITION BY t.id_ticket ORDER BY t.ts_updated DESC) AS _w,
      t.ts_updated
    FROM datalake_customer_support.tickets AS t
    LEFT JOIN dw_customer_support.fact_customer_contacts AS rd
      ON CAST(t.id_ticket AS BIGINT) = rd.sk_ticket
    LEFT JOIN datalake_customer_demand.backlog_metrics_tasks AS bmt
      ON t.id_ticket = bmt.id_task
    LEFT JOIN datalake_gsheets_clean.department_control AS dc
      ON t.last_queue = dc.department
    LEFT JOIN recontact_data AS r
      ON t.id_ticket = r.id_ticket
    LEFT JOIN datalake_customer_support.csat AS csat
      ON csat.id_ticket = t.id_ticket
    WHERE
      t.front_or_back <> 'undefined'
      AND NOT dc.team IS NULL
      AND NOT t.last_analyst_email IS NULL
      AND CAST(t.ts_updated AS DATE) BETWEEN CAST('{load_start_date}' AS DATE) AND CAST('{load_end_date}' AS DATE)
  ) AS _t
  WHERE
    _w = 1
  UNION ALL
  SELECT
    id_ticket,
    id_agent,
    team,
    status,
    resolution_survey,
    reopened_tickets,
    replied_tickets,
    first_csat_score,
    attendance_time,
    is_recontact_ticket,
    is_received_demand,
    is_productive_ticket,
    is_first_department_interaction,
    is_backlog_in_time,
    is_backlog_not_in_time,
    is_backlog,
    frt,
    ts_csat_response,
    dt_reference
  FROM (
    SELECT
      t.id_ticket,
      MD5(t.last_analyst_email) AS id_agent,
      NULL AS team,
      NULL AS status,
      NULL AS resolution_survey,
      NULL AS reopened_tickets,
      NULL AS replied_tickets,
      zes.csat_score AS first_csat_score,
      NULL AS attendance_time,
      NULL AS is_recontact_ticket,
      NULL AS is_received_demand,
      NULL AS is_productive_ticket,
      NULL AS is_first_department_interaction,
      NULL AS is_backlog_in_time,
      NULL AS is_backlog_not_in_time,
      NULL AS is_backlog,
      NULL AS frt,
      zes.ts_first_response AS ts_csat_response,
      CAST('{load_start_date}' AS DATE) AS dt_reference,
      ROW_NUMBER() OVER (PARTITION BY zes.id_ticket ORDER BY zes.ts_first_response DESC) AS _w,
      zes.ts_first_response
    FROM datalake_survicate.zendesk_email_surveys AS zes
    LEFT JOIN datalake_customer_support.tickets AS t
      ON zes.id_ticket = t.id_ticket
    LEFT JOIN datalake_sale_offer.sale_offer AS eso
      ON eso.id_offer = GET_JSON_OBJECT(t.custom_fields, ARRAY('[RC] ID Offer do Imóvel'))
    WHERE
      zes.id_survey = '2f81495a1a142887'
      AND t.channel = 'whatsapp'
      AND CAST(zes.ts_first_response AS DATE) BETWEEN CAST('{load_start_date}' AS DATE) AND CAST('{load_end_date}' AS DATE)
      AND eso.current_payment_method IN ('CASH', 'CASH_USING_FGTS', 'FINANCED', 'FINANCED_USING_FGTS')
      AND NOT t.last_analyst_email IS NULL
  ) AS _t
  WHERE
    _w = 1
  UNION ALL
  SELECT
    id_ticket,
    id_agent,
    team,
    status,
    resolution_survey,
    reopened_tickets,
    replied_tickets,
    first_csat_score,
    attendance_time,
    is_recontact_ticket,
    is_received_demand,
    is_productive_ticket,
    is_first_department_interaction,
    is_backlog_in_time,
    is_backlog_not_in_time,
    is_backlog,
    frt,
    ts_csat_response,
    dt_reference
  FROM (
    SELECT
      ro.id_ticket,
      ro.id_agent,
      NULL AS team,
      NULL AS status,
      NULL AS resolution_survey,
      ro.reopens AS reopened_tickets,
      ro.replies AS replied_tickets,
      ro.csat_score AS first_csat_score,
      NULL AS attendance_time,
      NULL AS is_recontact_ticket,
      NULL AS is_received_demand,
      IF(ro.dt_solved = CAST('{load_start_date}' AS DATE), TRUE, FALSE) AS is_productive_ticket,
      NULL AS is_first_department_interaction,
      NULL AS is_backlog_in_time,
      NULL AS is_backlog_not_in_time,
      NULL AS is_backlog,
      ro.frt,
      ro.ts_csat_response_submitted AS ts_csat_response,
      CAST('{load_start_date}' AS DATE) AS dt_reference,
      ROW_NUMBER() OVER (PARTITION BY ro.id_ticket ORDER BY ro.ts_updated_local DESC) AS _w,
      ro.ts_updated_local
    FROM repair_ongoing AS ro
    WHERE
      NOT ro.id_agent IS NULL
  ) AS _t
  WHERE
    _w = 1
), pause_metrics AS (
  SELECT
    CAST(ts_created AS DATE) AS date,
    worker_email,
    SUM(CAST(total_inactivity_time AS DOUBLE) / 1000) AS total_inactivity_time_sum,
    SUM(CAST(last_inactivity_time AS DOUBLE) / 1000) AS last_inactivity_time_sum
  FROM datalake_customer_support.chats
  WHERE
    MAKE_DATE(year, month, day) BETWEEN CAST('{load_start_date}' AS DATE) AND CAST('{load_end_date}' AS DATE)
    AND task_status = 'completed'
  GROUP BY
    worker_email,
    CAST(ts_created AS DATE)
), activity_times AS (
  SELECT
    date,
    analyst_email,
    SUM(total_activity_time) AS total_activity_time,
    SUM(CASE WHEN activity LIKE 'Pausa%' THEN total_activity_time ELSE 0 END) AS total_paused,
    SUM(CASE WHEN activity LIKE 'Offline%' THEN total_activity_time ELSE 0 END) AS total_offline,
    SUM(CASE WHEN activity LIKE 'Dispon%' THEN total_activity_time ELSE 0 END) AS total_available,
    SUM(CASE WHEN activity LIKE 'Indispon%' THEN total_activity_time ELSE 0 END) AS total_unavailable
  FROM datalake_twilio_flex_insights_clean.analyst_activity_time
  WHERE
    MAKE_DATE(year, month, day) BETWEEN CAST('{load_start_date}' AS DATE) AND CAST('{load_end_date}' AS DATE)
  GROUP BY
    date,
    analyst_email
), twilio_metrics AS (
  SELECT
    at.date,
    MD5(at.analyst_email) AS id_agent,
    at.total_activity_time,
    at.total_paused,
    at.total_offline,
    at.total_available,
    at.total_unavailable,
    pm.total_inactivity_time_sum,
    pm.last_inactivity_time_sum
  FROM activity_times AS at
  INNER JOIN pause_metrics AS pm
    ON at.analyst_email = pm.worker_email AND at.date = pm.date
)
SELECT
  wa.id_agent || dt_reference AS sk_snapshot,
  wa.id_agent AS sk_agent,
  COALESCE(CAST(DATE_FORMAT(wa.dt_reference, 'yyyyMMdd') AS BIGINT), -1) AS sk_reference_date,
  COUNT_IF(DISTINCT wa.is_productive_ticket = TRUE) AS total_days_worked,
  COUNT(DISTINCT id_ticket) AS total_tickets,
  SUM(wa.reopened_tickets) AS ticket_reopenings,
  SUM(wa.replied_tickets) AS ticket_responses,
  SUM(wa.attendance_time) AS total_attendance_time,
  COUNT_IF(wa.is_recontact_ticket = TRUE) AS total_tickets_recontact,
  COUNT_IF(wa.is_received_demand = TRUE) AS total_received_demand,
  COUNT_IF(wa.is_productive_ticket = TRUE) AS total_productivity,
  tm.total_activity_time,
  tm.total_paused AS total_status_paused,
  tm.total_offline AS total_status_offline,
  tm.total_available AS total_status_available,
  tm.total_unavailable AS total_status_unavailable,
  ROUND(tm.total_inactivity_time_sum, 2) AS total_tasks_inactivity_time,
  COUNT(
    DISTINCT CASE WHEN NOT wa.first_csat_score IS NULL THEN wa.id_ticket ELSE NULL END
  ) AS tickets_with_csat_score,
  COUNT(DISTINCT CASE WHEN wa.first_csat_score IN (4, 5) THEN wa.id_ticket ELSE NULL END) AS tickets_csat_satisfied,
  COUNT(DISTINCT CASE WHEN wa.first_csat_score = 3 THEN wa.id_ticket ELSE NULL END) AS tickets_csat_neutral,
  COUNT(DISTINCT CASE WHEN wa.first_csat_score IN (1, 2) THEN wa.id_ticket ELSE NULL END) AS tickets_csat_dissatisfied,
  COUNT(
    DISTINCT CASE
      WHEN NOT wa.resolution_survey IS NULL OR NOT wa.ts_csat_response IS NULL
      THEN wa.id_ticket
    END
  ) AS tickets_with_resolution_answered,
  COUNT(
    DISTINCT CASE
      WHEN wa.resolution_survey = TRUE OR NOT wa.ts_csat_response IS NULL
      THEN wa.id_ticket
    END
  ) AS tickets_with_resolution,
  COUNT(
    DISTINCT CASE
      WHEN wa.status = 'transferred'
      AND wa.is_first_department_interaction = TRUE
      AND wa.team <> 'Inside Sales'
      THEN wa.id_ticket
      ELSE NULL
    END
  ) AS tickets_transferred,
  AVG(wa.replied_tickets) AS replies,
  AVG(wa.frt) AS frt,
  COUNT_IF(wa.is_backlog = TRUE) AS tickets_in_backlog,
  COUNT_IF(wa.is_backlog_in_time = TRUE) AS backlog_within_sla,
  COUNT_IF(wa.is_backlog_not_in_time = TRUE) AS backlog_with_exceed_sla,
  YEAR(TO_DATE(wa.dt_reference)) AS year,
  MONTH(TO_DATE(wa.dt_reference)) AS month,
  DAY(TO_DATE(wa.dt_reference)) AS day,
  NOW() AS ts_load
FROM without_agg_infos AS wa
LEFT JOIN twilio_metrics AS tm
  ON wa.id_agent = tm.id_agent AND wa.dt_reference = tm.date
GROUP BY ALL