SELECT DISTINCT
  dmt.sk_task,
  dmt.sk_agent,
  dmt.sla_target,
  dmt.origin AS channel,
  dmt.status,
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
  dtt.tags AS tag,
  dmt.time_spent_solved_within_sla,
  dmt.time_spent_solved_with_exceed_sla,
  dmt.days_worked,
  dmt.days_off,
  dmt.days_worked AS leadtime_day,
  dmt.is_ticket_solved_within_sla,
  dmt.is_ticket_solved_with_exceed_sla,
  dmt.is_received_demand,
  dmt.is_solved_demand,
  dmt.is_closed_demand,
  dmt.ts_started,
  dmt.ts_solved,
  dmt.ts_closed,
  YEAR(dmt.ts_started) AS year,
  MONTH(dmt.ts_started) AS month,
  DAY(dmt.ts_started) AS day,
  NOW() AS ts_load
FROM
  dw_customer_support.fact_demand_metrics_tasks AS dmt
LEFT JOIN
  dw_customer_support.dim_department AS dd
    ON dmt.sk_main_department = dd.sk_department
LEFT JOIN
  dw_customer_support.dim_ticket_tags AS dtt
    ON dmt.sk_tags = dtt.sk_tags
LEFT JOIN
  dw_customer_support.dim_taxonomy AS dt
    ON dmt.sk_taxonomy = dt.sk_taxonomy
LEFT JOIN
  dw_customer_support.dim_agent AS da
    ON dmt.sk_agent = da.sk_agent
WHERE
  DATE(dmt.ts_started) BETWEEN DATE('{load_start_date}') - INTERVAL '1' YEAR AND DATE('{load_end_date}')
AND
  dd.is_partner IS TRUE
  AND dd.front_or_back <> 'front'
  AND (da.agent_organization = "atento" OR da.agent_organization = "atn")
