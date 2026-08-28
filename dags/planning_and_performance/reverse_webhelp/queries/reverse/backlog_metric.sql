WITH time_solved AS (
  SELECT
    sk_ticket,
    MIN(CAST(ts_solved AS DATE)) AS dt_solved
  FROM dw_customer_support.fact_tickets
  GROUP BY
    1
)
SELECT
  sk_ticket,
  sk_agent,
  channel,
  status,
  agent_organization,
  agent_email,
  department,
  front_or_back,
  contact_motivation_tag,
  contact_theme_detail_tag,
  customer_type_tag,
  tag,
  step_tag,
  team,
  journey_step,
  area,
  sla_target,
  days_worked,
  days_worked_with_days_offs,
  days_off,
  is_daily_backlog,
  is_backlog_in_time,
  is_backlog_not_in_time,
  dt_metric_reference,
  ts_started,
  ts_solved,
  replies,
  year,
  month,
  day,
  ts_load
FROM (
  SELECT
    bmt.sk_task AS sk_ticket,
    bmt.sk_agent,
    bmt.origin AS channel,
    CASE
      WHEN ts.dt_solved IS NULL
      THEN bmt.status
      WHEN ts.dt_solved > CAST(bmt.dt_metric_reference AS DATE)
      THEN bmt.status
      WHEN ts.dt_solved <= CAST(bmt.dt_metric_reference AS DATE)
      THEN dit.status
      ELSE bmt.status
    END AS status,
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
    tf.sla_target,
    bmt.days_worked,
    bmt.days_worked_with_days_offs,
    bmt.days_off,
    bmt.is_daily_backlog,
    CASE
      WHEN LEAST(bmt.days_worked, tf.days_elapsed_business) <= tf.sla_target
      THEN TRUE
      WHEN LEAST(bmt.days_worked, tf.days_elapsed_business) > tf.sla_target
      THEN FALSE
      ELSE NULL
    END AS is_backlog_in_time,
    CASE
      WHEN LEAST(bmt.days_worked, tf.days_elapsed_business) > tf.sla_target
      THEN TRUE
      WHEN LEAST(bmt.days_worked, tf.days_elapsed_business) <= tf.sla_target
      THEN FALSE
      ELSE NULL
    END AS is_backlog_not_in_time,
    bmt.dt_metric_reference,
    bmt.ts_started,
    bmt.ts_solved,
    tf.replies,
    YEAR(TO_DATE(CURRENT_DATE - 1)) AS year,
    MONTH(TO_DATE(CURRENT_DATE - 1)) AS month,
    DAY(TO_DATE(CURRENT_DATE - 1)) AS day,
    NOW() AS ts_load,
    ROW_NUMBER() OVER (PARTITION BY bmt.sk_task, bmt.dt_metric_reference ORDER BY bmt.sla_target DESC) AS _w,
    bmt.sk_task
  FROM dw_customer_support.fact_backlog_metrics_tasks AS bmt
  LEFT JOIN dw_customer_support.dim_taxonomy AS dt
    ON bmt.sk_taxonomy = dt.sk_taxonomy
  LEFT JOIN dw_customer_support.dim_department AS dd
    ON bmt.sk_main_department = dd.sk_department
  LEFT JOIN dw_customer_support.dim_analyst AS da
    ON bmt.sk_agent = da.sk_analyst
  LEFT JOIN dw_customer_support.dim_ticket AS dit
    ON dit.sk_ticket = bmt.sk_task
  LEFT JOIN dw_customer_support.fact_tickets AS tf
    ON tf.sk_ticket = bmt.sk_task
  LEFT JOIN time_solved AS ts
    ON CAST(ts.sk_ticket AS STRING) = bmt.sk_task
  WHERE
    CAST(bmt.dt_metric_reference AS DATE) BETWEEN CAST('{load_start_date}' AS DATE) - INTERVAL '1' YEAR AND CAST('{load_end_date}' AS DATE)
    AND dd.is_partner IS TRUE
    AND dd.front_or_back <> 'front'
    AND da.agent_organization IN ('webhelp', 'webhelpbr', 'contractors')
) AS _t
WHERE
  _w = 1
