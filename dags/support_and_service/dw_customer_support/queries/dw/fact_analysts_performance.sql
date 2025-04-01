WITH recontact_data AS (
  SELECT
    t.id_ticket,
    IF(t.ts_updated > t.ts_solved, TRUE, FALSE) AS is_recontact_ticket
  FROM
    datalake_customer_support.tickets AS t
  WHERE
    DATE(t.ts_solved) BETWEEN DATE('{load_start_date}') AND DATE('{load_end_date}')
  QUALIFY
    ROW_NUMBER() OVER (PARTITION BY t.id_ticket ORDER BY t.ts_updated DESC) = 1
)
,repair_ongoing AS (
  SELECT
    rt.id_ticket,
    MD5(rt.agent_email) AS id_agent,
    NULL AS csat_score,
    rt.replies AS replies,
    IF(rt.reopens > 0, 1, NULL) AS reopens,
    DATE_DIFF(DAY, DATE(rt.ts_created_local), COALESCE(DATE(rt.ts_solved_local),DATE(rt.ts_closed_local))) AS frt,
    COALESCE(DATE(rt.ts_solved_local),DATE(rt.ts_closed_local)) AS dt_solved,    
    rt.ts_updated_local,
    NULL AS ts_csat_response_submitted
  FROM
    datalake_repairs.ongoing_repair_tickets AS rt
  WHERE
    (rt.tags NOT LIKE '%teste_ps_pp_grupo_b_intermediacao_autosservico%'
      AND rt.tags NOT LIKE '%mvp_fup_iq_intermediacao_autosservico%'
      OR  rt.tags like '%mvp_fup_iq_intermediacao_autosservico%')
    AND COALESCE(DATE(rt.ts_solved_local),DATE(rt.ts_closed_local)) BETWEEN DATE('{load_start_date}') AND DATE('{load_end_date}')
    AND rt.tags NOT LIKE '%closed_by_merge%'
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
  FROM
    datalake_repairs.ongoing_repair_tickets AS rt
  WHERE
    (rt.tags NOT LIKE '%teste_ps_pp_grupo_b_intermediacao_autosservico%'
      AND rt.tags NOT LIKE '%mvp_fup_iq_intermediacao_autosservico%'
      OR  rt.tags like '%mvp_fup_iq_intermediacao_autosservico%')
    AND DATE(rt.ts_csat_response_submitted) BETWEEN DATE('{load_start_date}') AND DATE('{load_end_date}')
)
,without_agg_infos AS (
  SELECT
    t.id_ticket,
    MD5(t.last_analyst_email) AS id_agent,
    dc.team,
    rd.status,
    csat.is_solved AS resolution_survey,
    t.reopens AS reopened_tickets,
    t.replies AS replied_tickets,
    csat.first_csat_score AS first_csat_score,
    DATEDIFF(t.ts_solved, t.ts_created) AS attendance_time,
    r.is_recontact_ticket,
    IF(DATE(t.ts_solved) = DATE('{load_start_date}') OR DATE(t.ts_closed) = DATE('{load_start_date}'), TRUE, FALSE) AS is_received_demand,
    IF(DATE(t.ts_solved) = DATE('{load_start_date}'), TRUE, FALSE) AS is_productive_ticket,
    CASE
      WHEN ROW_NUMBER() OVER(PARTITION BY MD5(
        COALESCE(CONCAT(rd.sk_call, 'call'),
        CONCAT(rd.sk_session, 'chat'),
        CONCAT(rd.sk_ticket, 'email'))
      ), rd.sk_department ORDER BY COALESCE(rd.ts_task_created, rd.ts_task_created)) = 1 THEN TRUE
      ELSE FALSE
    END AS is_first_department_interaction,
    bmt.is_backlog_in_time,
    bmt.is_backlog_not_in_time,
    IF(bmt.is_backlog_in_time OR bmt.is_backlog_not_in_time, TRUE, FALSE) AS is_backlog,
    NULL AS frt,
    csat.ts_first_response AS ts_csat_response,
    DATE('{load_start_date}') AS dt_reference
  FROM
    datalake_customer_support.tickets t
  LEFT JOIN
    dw_customer_support.fact_customer_contacts AS rd
      ON CAST(t.id_ticket AS BIGINT) = rd.sk_ticket
  LEFT JOIN
    datalake_customer_demand.backlog_metrics_tasks AS bmt
      ON t.id_ticket = bmt.id_task
  LEFT JOIN
    datalake_gsheets_clean.department_control AS dc
      ON t.last_queue = dc.department
  LEFT JOIN
    recontact_data AS r
      ON t.id_ticket = r.id_ticket
  LEFT JOIN
    datalake_customer_support.csat AS csat
      ON csat.id_ticket = t.id_ticket
  WHERE
		t.front_or_back <> "undefined"
		AND dc.team IS NOT NULL
		AND t.last_analyst_email IS NOT NULL
		AND DATE(t.ts_updated) BETWEEN DATE('{load_start_date}') AND DATE('{load_end_date}')
  QUALIFY
		ROW_NUMBER() OVER (PARTITION BY t.id_ticket ORDER BY t.ts_updated DESC) = 1
  UNION ALL
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
    DATE('{load_start_date}') AS dt_reference
	FROM
    datalake_survicate.zendesk_email_surveys AS zes
  LEFT JOIN
    datalake_customer_support.tickets AS t
      ON zes.id_ticket = t.id_ticket
  LEFT JOIN
  datalake_offer.sale_offer eso
    ON eso.id_offer = GET_JSON_OBJECT(t.custom_fields, '$["[RC] ID Offer do Imóvel"]')
  WHERE
    zes.id_survey = '2f81495a1a142887'
    AND t.channel = 'whatsapp'
    AND DATE(zes.ts_first_response) BETWEEN DATE('{load_start_date}') AND DATE('{load_end_date}')
    AND eso.current_payment_method IN
      (
        'CASH',
        'CASH_USING_FGTS',
        'FINANCED',
        'FINANCED_USING_FGTS'
      )
    AND t.last_analyst_email IS NOT NULL
  QUALIFY
    ROW_NUMBER() OVER (PARTITION BY zes.id_ticket ORDER BY zes.ts_first_response DESC) = 1
  UNION ALL
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
    IF(ro.dt_solved = DATE('{load_start_date}'), TRUE, FALSE) AS is_productive_ticket,
    NULL AS is_first_department_interaction,
    NULL AS is_backlog_in_time,
    NULL AS is_backlog_not_in_time,
    NULL AS is_backlog,
    ro.frt,
    ro.ts_csat_response_submitted AS ts_csat_response,
    DATE('{load_start_date}') AS dt_reference
  FROM
    repair_ongoing AS ro
  WHERE
    ro.id_agent IS NOT NULL
  QUALIFY
    ROW_NUMBER() OVER (PARTITION BY ro.id_ticket ORDER BY ro.ts_updated_local DESC) = 1
)
SELECT
  wa.id_agent || dt_reference AS sk_snapshot,
  wa.id_agent AS sk_agent,
  COALESCE(CAST(DATE_FORMAT(wa.dt_reference,'yyyyMMdd') AS BIGINT), -1) AS sk_reference_date,
  COUNT_IF(DISTINCT wa.is_productive_ticket = TRUE) AS total_days_worked,
  COUNT(DISTINCT id_ticket) AS total_tickets,
  SUM(wa.reopened_tickets) AS ticket_reopenings,
  SUM(wa.replied_tickets) AS ticket_responses,
  SUM(wa.attendance_time) AS total_attendance_time,
  COUNT_IF(wa.is_recontact_ticket = TRUE) AS total_tickets_recontact,
  COUNT_IF(wa.is_received_demand = TRUE) AS total_received_demand,
  COUNT_IF(wa.is_productive_ticket = TRUE) AS total_productivity,
  COUNT(DISTINCT
    CASE
      WHEN
        wa.first_csat_score IS NOT NULL
        THEN wa.id_ticket
      ELSE NULL
    END
  ) AS tickets_with_csat_score,
  COUNT(DISTINCT
    CASE
      WHEN
        wa.first_csat_score IN (4,5)
        THEN wa.id_ticket
      ELSE NULL
    END
  ) AS tickets_csat_satisfied,
  COUNT(DISTINCT
    CASE
      WHEN
        wa.first_csat_score = 3
        THEN wa.id_ticket
      ELSE NULL
    END
  ) AS tickets_csat_neutral,
  COUNT(DISTINCT
    CASE
      WHEN
        wa.first_csat_score IN (1,2)
        THEN wa.id_ticket
      ELSE NULL
    END
  ) AS tickets_csat_dissatisfied,
  COUNT(DISTINCT
    CASE
      WHEN
        wa.resolution_survey IS NOT NULL
        OR wa.ts_csat_response IS NOT NULL
        THEN wa.id_ticket
    END
  ) AS tickets_with_resolution_answered,
  COUNT(DISTINCT
    CASE
      WHEN
        wa.resolution_survey = True
        OR wa.ts_csat_response IS NOT NULL
        THEN wa.id_ticket
    END
  ) AS tickets_with_resolution,
  COUNT(DISTINCT
    CASE
      WHEN wa.status = 'transferred'
        AND wa.is_first_department_interaction = True
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
  YEAR(wa.dt_reference) AS year,
  MONTH(wa.dt_reference) AS month,
  DAY(wa.dt_reference) AS day,
  NOW() AS ts_load
FROM
  without_agg_infos AS wa
GROUP BY
  ALL