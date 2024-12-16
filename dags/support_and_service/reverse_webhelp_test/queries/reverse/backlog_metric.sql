SELECT
  CAST(ftb.sk_ticket AS STRING) AS sk_ticket,
  ftb.sk_analyst AS sk_agent,
  'email' AS channel,
  dit.status,
  da.agent_organization,
  da.email AS agent_email,
  dd.department,
  dd.front_or_back,
  dt.motivation AS contact_motivation_tag,
  dt.theme_detail AS contact_theme_detail_tag,
  dt.customer_type_tag AS customer_type_tag,
  dit.tags AS tag,
  dt.step_tag AS step_tag,
  dd.team,
  dd.journey_step,
  dd.area,
  ftb.sla_target,
  CAST(ftb.days_elapsed_business AS INTEGER) AS days_worked,
  CAST(ftb.days_elapsed_calendar AS INTEGER) AS days_worked_with_days_offs,
  ftb.days_off,
  TRUE AS is_daily_backlog,
  ftb.is_backlog_within_sla AS is_backlog_in_time,
  ftb.is_backlog_outside_sla AS is_backlog_not_in_time,
  ftb.dt_snapshot AS dt_metric_reference,
  ftb.ts_created AS ts_started,
  NULL AS ts_solved,
  tf.replies,
  YEAR(CURRENT_DATE - 1) AS year,
  MONTH(CURRENT_DATE - 1) AS month,
  DAY(CURRENT_DATE - 1) AS day,
  NOW() AS ts_load
FROM
  dw_customer_support.fact_tickets_backlog AS ftb
LEFT JOIN
  dw_customer_support.dim_taxonomy AS dt
    ON ftb.sk_taxonomy = dt.sk_taxonomy
LEFT JOIN
  dw_customer_support.dim_department AS dd
    ON ftb.sk_department = dd.sk_department
LEFT JOIN
  dw_customer_support.dim_analyst AS da
    ON ftb.sk_analyst = da.sk_analyst
LEFT JOIN
  dw_customer_support.dim_ticket dit
    ON dit.sk_ticket = ftb.sk_ticket
LEFT JOIN
  dw_customer_support.fact_ticket AS tf
    ON tf.sk_ticket = ftb.sk_ticket
WHERE
  DATE(ftb.dt_snapshot) BETWEEN DATE('{load_start_date}') - INTERVAL '1' YEAR AND DATE('{load_end_date}')
  AND dd.is_partner IS TRUE
  AND dd.front_or_back <> 'front'
  AND da.agent_organization IN ('webhelp', 'webhelpbr', 'contractors')
QUALIFY
  ROW_NUMBER() OVER(PARTITION BY ftb.sk_ticket, ftb.dt_snapshot ORDER BY ftb.sla_target DESC) = 1
