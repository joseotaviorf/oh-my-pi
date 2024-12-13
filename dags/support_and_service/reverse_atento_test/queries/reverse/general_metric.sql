SELECT DISTINCT
  ft.sk_ticket,
  ft.sk_last_analyst AS sk_agent,
  CASE
    WHEN ft.channel = 'cs email' THEN  'email'
    ELSE ft.channel
  END AS channel,
  ftc.first_csat_score AS csat_score,
  dit.status,
  CASE
    WHEN ftc.last_csat_score BETWEEN 4 AND 5 THEN 'Satisfied'
    WHEN ftc.last_csat_score = 3 THEN 'Neutral'
    WHEN ftc.last_csat_score BETWEEN 1 AND 2 THEN 'Dissatisfied'
    ELSE NULL
  END AS csat_type,
  ftc.first_csat_comment AS csat_comment,
  dd.department AS main_department,
  ft.direction,
  dd.area,
  dd.department,
  dd.journey_step,
  ft.front_or_back,
  dd.team,
  dt.motivation AS contact_motivation_tag,
  dt.theme_detail AS contact_theme_detail_tag,
  dt.customer_type_tag,
  dit.tags AS tag,
  dt.step_tag,
  CONCAT('https://quintoandar.zendesk.com/agent/tickets/', ft.sk_ticket) AS external_url,
  ROUND(CAST(ft.full_resolution_time_min_business/60.0 AS DOUBLE), 2) AS hours_to_solve_ticket,
  da.full_name AS agent_full_name,
  da.email AS agent_email,
  da.agent_organization AS agent_company,
  ft.reopens,
  ft.replies,
  dd.is_active,
  CASE
    WHEN ftc.sk_ticket IS NOT NULL THEN TRUE
    ELSE FALSE
  END AS has_answered_csat,
  NULL AS has_transfers,
  ftc.is_solved AS is_resolution,
  ft.ts_created AS ts_started,
  ftc.ts_last_response AS ts_survey,
  ftc.ts_first_response AS ts_csat_response,
  ft.ts_solved,
  ft.ts_closed,
  YEAR(CURRENT_DATE) AS year,
  MONTH(CURRENT_DATE) AS month,
  DAY(CURRENT_DATE) AS day,
  NOW() AS ts_load,
  ft.requester_wait_time_min_business AS minutes_requester_wait_time_business,
  ft.reply_time_min_business AS minutes_first_reply_time_business,
  ft.full_resolution_time_min_business AS minutes_full_resolution_time_business
FROM
  dw_customer_support.fact_tickets AS ft
LEFT JOIN
  dw_satisfaction_rating.fact_ticket_csat AS ftc
    ON ftc.sk_ticket = ft.sk_ticket
LEFT JOIN
  dw_customer_support.dim_ticket AS dit
    ON dit.sk_ticket = ft.sk_ticket
LEFT JOIN
  dw_customer_support.dim_department AS dd
    ON ft.sk_main_department = dd.sk_department
LEFT JOIN
  dw_customer_support.dim_taxonomy AS dt
    ON ft.sk_taxonomy = dt.sk_taxonomy
LEFT JOIN
  dw_customer_support.dim_analyst AS da
    ON ft.sk_last_analyst = da.sk_analyst
    OR ft.sk_last_analyst = da.sk_agent_twilio
WHERE
  DATE(ft.ts_created) BETWEEN DATE('{load_start_date}') - INTERVAL '1' YEAR AND DATE('{load_end_date}')
  AND dd.is_partner IS TRUE
  AND dd.front_or_back <> 'front'
  AND (da.agent_organization = "atento" OR da.agent_organization = "atn")
