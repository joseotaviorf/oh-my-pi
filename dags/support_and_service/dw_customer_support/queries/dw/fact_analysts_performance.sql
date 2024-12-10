WITH recontact_data AS (
  SELECT
    t.id_ticket,
    IF(t.ts_updated > t.ts_solved, TRUE, FALSE) AS is_recontact_ticket
  FROM
    datalake_customer_support.tickets AS t
  WHERE
    DATE(t.ts_solved) = MAKE_DATE({year}, {month}, {day})
  QUALIFY
    ROW_NUMBER() OVER (PARTITION BY t.id_ticket ORDER BY t.ts_updated DESC) = 1
),
without_agg_infos AS (
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
    IF(DATE(t.ts_solved) = MAKE_DATE({year}, {month}, {day}) OR DATE(t.ts_closed) = MAKE_DATE({year}, {month}, {day}), TRUE, FALSE) AS is_received_demand,
    IF(DATE(t.ts_solved) = MAKE_DATE({year}, {month}, {day}), TRUE, FALSE) AS is_productive_ticket,
    CASE
      WHEN ROW_NUMBER() OVER(PARTITION BY MD5(
        COALESCE(CONCAT(rd.id_call, 'call'),
        CONCAT(rd.id_session, 'chat'),
        CONCAT(rd.id_ticket, 'email'))
      ), rd.department ORDER BY rd.ts_created) = 1 THEN TRUE
      ELSE FALSE
    END AS is_first_department_interaction,
    bmt.is_backlog_in_time,
    bmt.is_backlog_not_in_time,
    IF(bmt.is_backlog_in_time OR bmt.is_backlog_not_in_time, TRUE, FALSE) AS is_backlog,
    csat.ts_first_response AS ts_csat_response,
    DATE(t.ts_updated) AS dt_last_ticket_updated
  FROM
    datalake_customer_support.tickets t
  LEFT JOIN
    datalake_customer_support.received_demand AS rd
      ON t.id_ticket = rd.id_ticket
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
		AND DATE(t.ts_updated) = MAKE_DATE({year}, {month}, {day})
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
    zes.ts_first_response AS ts_csat_response,
    CURRENT_DATE - 1 AS dt_last_ticket_updated
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
    AND DATE(zes.ts_first_response) = CURRENT_DATE - 1
    AND eso.current_payment_method IN ('CASH','CASH_USING_FGTS','FINANCED','FINANCED_USING_FGTS')
    AND t.last_analyst_email IS NOT NULL
  QUALIFY
    ROW_NUMBER() OVER (PARTITION BY zes.id_ticket ORDER BY zes.ts_first_response DESC) = 1
)
SELECT
    wa.id_agent || dt_last_ticket_updated AS sk_snapshot,
    wa.id_agent AS sk_agent,
    COALESCE(CAST(DATE_FORMAT(wa.dt_last_ticket_updated,'yyyyMMdd') AS BIGINT), -1) AS sk_last_ticket_updated_date,
    COUNT(id_ticket) AS total_tickets,
    SUM(wa.reopened_tickets) AS ticket_reopenings,
    SUM(wa.replied_tickets) AS ticket_responses,
    SUM(wa.attendance_time) AS total_attendance_time,
    COUNT_IF(wa.is_recontact_ticket = TRUE) AS total_tickets_recontact,
    COUNT_IF(wa.is_received_demand = TRUE) AS total_received_demand,
    COUNT_IF(wa.is_productive_ticket = TRUE) AS total_productivity,
    COUNT(
      CASE
        WHEN
          wa.first_csat_score IS NOT NULL
          THEN wa.id_ticket
        ELSE NULL
      END
    ) AS tickets_with_csat_score,
    COUNT(
      CASE
        WHEN
          wa.first_csat_score IN (4,5)
          THEN wa.id_ticket
        ELSE NULL
      END
    ) AS tickets_csat_satisfied,
    COUNT(
      CASE
        WHEN
          wa.first_csat_score = 3
          THEN wa.id_ticket
        ELSE NULL
      END
    ) AS tickets_csat_neutral,
    COUNT(
      CASE
        WHEN
          wa.first_csat_score IN (1,2)
          THEN wa.id_ticket
        ELSE NULL
      END
    ) AS tickets_csat_dissatisfied,
    COUNT(
      CASE
        WHEN
          wa.resolution_survey IS NOT NULL
          OR wa.ts_csat_response IS NOT NULL
          THEN wa.id_ticket
      END
    ) AS tickets_with_resolution_answered,
    COUNT(
      CASE
        WHEN
          wa.resolution_survey = True
          OR wa.ts_csat_response IS NOT NULL
          THEN wa.id_ticket
      END
    ) AS tickets_with_resolution,
    COUNT(
      CASE
        WHEN wa.status = 'TRANSFERRED'
          AND wa.is_first_department_interaction = True
          AND wa.team <> 'Inside Sales'
          THEN wa.id_ticket
          ELSE NULL
      END
    ) AS tickets_transferred,
    COUNT_IF(wa.is_backlog = TRUE) AS tickets_in_backlog,
    COUNT_IF(wa.is_backlog_in_time = TRUE) AS backlog_within_sla,
    COUNT_IF(wa.is_backlog_not_in_time = TRUE) AS backlog_with_exceed_sla,
    YEAR(wa.dt_last_ticket_updated) AS year,
    MONTH(wa.dt_last_ticket_updated) AS month,
    DAY(wa.dt_last_ticket_updated) AS day,
    NOW() AS ts_load
FROM
    without_agg_infos AS wa
GROUP BY
  ALL
