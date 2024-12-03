SELECT DISTINCT
  ft.sk_ticket,
  da.email,
  dd.team,
  ft.channel,
  ft.main_department,
  ft.first_csat_comment AS csat_comment,
  dt.step_tag AS step_tag,
  dt.motivation AS motivation,
  dt.customer_type_tag AS customer_type_tag,
  dt.theme AS contact_theme_tag,
  dt.theme_detail AS contact_theme_detail_tag,
  ft.resolution_survey,
  CAST(ft.first_csat_score AS INT) AS csat_score,
  DATE(ts_started) AS ts_started,
  DATE(ts_closed) AS ts_closed,
  DATE(ts_csat_first_response) AS ts_response,
  YEAR(CURRENT_DATE) AS year,
  MONTH(CURRENT_DATE) AS month,
  DAY(CURRENT_DATE) AS day,
  NOW() AS ts_load
FROM
  dw_customer_support.fact_ticket AS ft
LEFT JOIN
  dw_customer_support.dim_department AS dd
    ON ft.sk_main_department = dd.sk_department
LEFT JOIN
  dw_customer_support.dim_taxonomy AS dt
    ON ft.sk_taxonomy = dt.sk_taxonomy
LEFT JOIN
  dw_customer_support.dim_agent AS da
    ON ft.sk_last_agent = da.sk_agent
WHERE
  ft.ts_csat_response BETWEEN DATE_TRUNC('month',DATE('{load_start_date}') - INTERVAL '3' MONTH) AND DATE('{load_end_date}')
  AND dd.is_partner IS TRUE
  AND dd.front_or_back = 'front'
  AND (da.agent_organization = "atento" OR da.agent_organization = "atn")
