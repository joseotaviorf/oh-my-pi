SELECT DISTINCT
  ft.sk_ticket AS sk_task,
  ft.sk_last_analyst AS sk_agent,
  ft.sla_target,
  'email' AS channel,
  dit.status,
  da.email AS agent_email,
  da.agent_organization AS agent_company,
  dd.department,
  dd.journey_step,
  dd.front_or_back,
  dd.team,
  dd.area,
  dt.motivation AS contact_motivation_tag,
  dt.theme_detail AS contact_theme_detail_tag,
  dt.customer_type_tag,
  dt.step_tag,
  dit.tags AS tag,
  ft.days_elapsed_business AS time_spent_solved_within_sla,
  CASE
    WHEN ft.days_elapsed_business >= ft.sla_target THEN ft.days_elapsed_business - ft.sla_target
    ELSE 0
  END AS time_spent_solved_with_exceed_sla,
  ft.days_elapsed_business AS days_worked,
  ft.days_off,
  ft.days_elapsed_business AS leadtime_day,
  CASE
    WHEN ft.days_elapsed_business <= ft.sla_target THEN TRUE
    ELSE FALSE
  END AS is_ticket_solved_within_sla,
  CASE
    WHEN ft.days_elapsed_business > ft.sla_target THEN TRUE
    ELSE FALSE
  END AS is_ticket_solved_with_exceed_sla,
  TRUE AS is_received_demand,
  CASE
    WHEN ft.ts_solved IS NOT NULL THEN TRUE
    ELSE FALSE
  END AS is_solved_demand,
  CASE
    WHEN ft.ts_closed IS NOT NULL THEN TRUE
    ELSE FALSE
  END AS is_closed_demand,
  ft.ts_created AS ts_started,
  ft.ts_solved,
  ft.ts_closed,
  YEAR(CURRENT_DATE - 1) AS year,
  MONTH(CURRENT_DATE - 1) AS month,
  DAY(CURRENT_DATE - 1) AS day,
  NOW() AS ts_load
FROM
  dw_customer_support.fact_tickets AS ft
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
  dw_customer_support.dim_agent AS da
    ON ft.sk_last_analyst = da.sk_agent
WHERE
  DATE(ft.ts_created) BETWEEN DATE('{load_start_date}') - INTERVAL '1' YEAR AND DATE('{load_end_date}')
  AND dd.is_partner IS TRUE
  AND dd.front_or_back <> 'front'
  AND da.agent_organization IN ('webhelp', 'webhelpbr')
  AND ft.channel = 'email'
