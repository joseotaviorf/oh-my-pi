SELECT DISTINCT
  ft.sk_ticket,
  da.email,
  dd.team,
  CASE
    WHEN ft.channel = 'cs email' THEN  'email'
    ELSE ft.channel
  END AS channel,
  dd.department AS main_department,
  ftc.first_csat_comment AS csat_comment,
  dt.step_tag AS step_tag,
  dt.motivation AS motivation,
  dt.customer_type_tag AS customer_type_tag,
  dt.theme AS contact_theme_tag,
  dt.theme_detail AS contact_theme_detail_tag,
  ftc.is_solved AS resolution_survey,
  CAST(ftc.first_csat_score AS INT) AS csat_score,
  DATE(ft.ts_created) AS ts_started,
  DATE(ft.ts_closed) AS ts_closed,
  DATE(ftc.ts_first_response) AS ts_response,
  YEAR(CURRENT_DATE - 1) AS year,
  MONTH(CURRENT_DATE - 1) AS month,
  DAY(CURRENT_DATE - 1) AS day,
  NOW() AS ts_load
FROM
  dw_customer_support.fact_tickets AS ft
LEFT JOIN
  dw_satisfaction_rating.fact_ticket_csat AS ftc
    ON ftc.sk_ticket = ft.sk_ticket
LEFT JOIN
  dw_customer_support.dim_department AS dd
    ON ft.sk_main_department = dd.sk_department
LEFT JOIN
  dw_customer_support.dim_taxonomy AS dt
    ON ft.sk_taxonomy = dt.sk_taxonomy
LEFT JOIN
  dw_customer_support.dim_analyst AS da
    ON ft.sk_last_analyst = da.sk_analyst
WHERE
  DATE(ftc.ts_last_response) BETWEEN DATE_TRUNC('month',DATE('{load_start_date}') - INTERVAL '3' MONTH) AND DATE('{load_end_date}')
  AND dd.is_partner IS TRUE
  AND dd.front_or_back = 'front'
  AND da.agent_organization IN ('webhelp', 'webhelpbr')
